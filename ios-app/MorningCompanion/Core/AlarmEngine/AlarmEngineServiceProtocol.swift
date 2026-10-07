import Foundation
import os

/// Interface for alarm scheduling backed by AlarmKit (production) or
/// UNUserNotificationCenter (legacy/fallback).
///
/// There is deliberately no untracked "snooze" entry point: every transient
/// occurrence (snooze, re-arm, wake-check auto-fail, test alarm) goes through
/// `scheduleReArm(for:reArmID:delay:)` with an id the caller has registered in
/// `ReArmRegistry`, so it can always be cancelled later.
protocol AlarmEngineServiceProtocol {
    func schedule(_ alarm: Alarm) async throws
    /// Schedules a one-shot alarm under `reArmID` (not the alarm's own id) so
    /// cancellation doesn't touch the alarm's recurring schedule.
    func scheduleReArm(for alarm: Alarm, reArmID: UUID, delay: TimeInterval) async throws
    func cancel(id: UUID) async throws
    func cancelAll() async throws
    /// Every id the engine currently holds (recurring alarms *and* re-arms).
    func pendingAlarmIDs() async throws -> [UUID]
    /// True when the system is currently alerting (ringing) for `id`.
    /// Only the AlarmKit engine can answer this; the notification engine returns false.
    func isAlerting(id: UUID) async -> Bool
    /// Ids currently owned by a degraded/fallback path that should be re-tried on the
    /// primary engine during reconcile. Engines without a fallback return [].
    func idsHeldByFallback() async -> Set<UUID>
}

extension AlarmEngineServiceProtocol {
    func isAlerting(id: UUID) async -> Bool { false }
    func idsHeldByFallback() async -> Set<UUID> { [] }
}

/// No-op stub for previews and unit tests.
final class StubAlarmEngineService: AlarmEngineServiceProtocol {
    private(set) var scheduledIDs: [UUID] = []
    private(set) var reArmIDs: [UUID] = []
    /// Ids the test can mark as "alerting" to exercise the ring-screen audio handoff.
    var alertingIDs: Set<UUID> = []

    func schedule(_ alarm: Alarm) async throws {
        if !scheduledIDs.contains(alarm.id) {
            scheduledIDs.append(alarm.id)
        }
    }

    func scheduleReArm(for alarm: Alarm, reArmID: UUID, delay: TimeInterval) async throws {
        if !reArmIDs.contains(reArmID) { reArmIDs.append(reArmID) }
    }

    func cancel(id: UUID) async throws {
        scheduledIDs.removeAll { $0 == id }
        reArmIDs.removeAll { $0 == id }
    }

    func cancelAll() async throws {
        scheduledIDs.removeAll()
        reArmIDs.removeAll()
    }

    func pendingAlarmIDs() async throws -> [UUID] {
        return scheduledIDs + reArmIDs
    }

    func isAlerting(id: UUID) async -> Bool { alertingIDs.contains(id) }
}

/// Engine stub that always throws, used in AlarmManager partial-failure tests.
final class FailingAlarmEngineService: AlarmEngineServiceProtocol {
    enum Failure: Error { case intentional }

    func schedule(_ alarm: Alarm) async throws                                            { throw Failure.intentional }
    func scheduleReArm(for alarm: Alarm, reArmID: UUID, delay: TimeInterval) async throws { throw Failure.intentional }
    func cancel(id: UUID) async throws                                                     { throw Failure.intentional }
    func cancelAll() async throws                                                          { throw Failure.intentional }
    func pendingAlarmIDs() async throws -> [UUID]                                          { throw Failure.intentional }
}

/// Uses AlarmKit whenever possible and falls back to a local notification only
/// when AlarmKit cannot register the alarm. The two engines are never left
/// scheduled for the same occurrence, preventing double alerts.
///
/// Which engine currently owns an id is remembered in the App Group so that,
/// once the user grants the AlarmKit permission later, `AlarmManager.reconcile`
/// can move alarms off the weaker notification path (audit §3 P1 "no upgrade").
final class ReliableAlarmEngineService: AlarmEngineServiceProtocol {
    private let primary: any AlarmEngineServiceProtocol
    private let fallback: any AlarmEngineServiceProtocol
    private let defaults: UserDefaults
    private let fallbackIDsKey = "com.morningcompanion.engine.fallbackIDs.v1"

    init(
        primary: any AlarmEngineServiceProtocol,
        fallback: any AlarmEngineServiceProtocol,
        defaults: UserDefaults? = nil
    ) {
        self.primary = primary
        self.fallback = fallback
        self.defaults = defaults ?? UserDefaults(suiteName: ReArmRegistry.suiteName) ?? .standard
    }

    func schedule(_ alarm: Alarm) async throws {
        do {
            try await primary.schedule(alarm)
            try? await fallback.cancel(id: alarm.id)
            setHeldByFallback(alarm.id, false)
        } catch {
            Log.alarm.warning("Primary engine refused \(alarm.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public) — using notification fallback")
            try await fallback.schedule(alarm)
            setHeldByFallback(alarm.id, alarm.isEnabled)
        }
    }

    func scheduleReArm(for alarm: Alarm, reArmID: UUID, delay: TimeInterval) async throws {
        do {
            try await primary.scheduleReArm(for: alarm, reArmID: reArmID, delay: delay)
            try? await fallback.cancel(id: reArmID)
            setHeldByFallback(reArmID, false)
        } catch {
            Log.alarm.warning("Primary engine refused re-arm \(reArmID.uuidString, privacy: .public): \(String(describing: error), privacy: .public) — using notification fallback")
            try await fallback.scheduleReArm(for: alarm, reArmID: reArmID, delay: delay)
            setHeldByFallback(reArmID, true)
        }
    }

    func cancel(id: UUID) async throws {
        var firstError: (any Error)?
        do { try await primary.cancel(id: id) } catch { firstError = error }
        do { try await fallback.cancel(id: id) } catch { if firstError == nil { firstError = error } }
        setHeldByFallback(id, false)
        if let firstError { throw firstError }
    }

    func cancelAll() async throws {
        var firstError: (any Error)?
        do { try await primary.cancelAll() } catch { firstError = error }
        do { try await fallback.cancelAll() } catch { if firstError == nil { firstError = error } }
        defaults.removeObject(forKey: fallbackIDsKey)
        if let firstError { throw firstError }
    }

    func pendingAlarmIDs() async throws -> [UUID] {
        let primaryIDs = (try? await primary.pendingAlarmIDs()) ?? []
        let fallbackIDs = (try? await fallback.pendingAlarmIDs()) ?? []
        return Array(Set(primaryIDs).union(fallbackIDs))
    }

    func isAlerting(id: UUID) async -> Bool {
        await primary.isAlerting(id: id)
    }

    func idsHeldByFallback() async -> Set<UUID> {
        heldByFallback()
    }

    // MARK: - Ownership bookkeeping

    private func heldByFallback() -> Set<UUID> {
        Set((defaults.stringArray(forKey: fallbackIDsKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    private func setHeldByFallback(_ id: UUID, _ held: Bool) {
        var ids = heldByFallback()
        if held { ids.insert(id) } else { ids.remove(id) }
        defaults.set(ids.map(\.uuidString), forKey: fallbackIDsKey)
    }
}
