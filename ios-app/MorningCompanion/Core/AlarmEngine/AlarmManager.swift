import Foundation
import os

// MARK: - Result types

enum AlarmManagerResult {
    /// Alarm was persisted and scheduled (or cancelled) successfully.
    case success(Alarm)
    /// Alarm was persisted but scheduling/cancellation failed.
    case partialSuccess(Alarm, schedulingError: any Error)
    /// Alarm was deleted from the repository and its notification was cancelled.
    case deleted
    /// Operation failed; no state was changed.
    case failure(AlarmManagerError)
}

enum AlarmManagerError: LocalizedError {
    case validation(String)
    case persistence(any Error)
    /// The free tier's alarm limit would be exceeded. The caller shows the paywall.
    case freeAlarmLimit

    var errorDescription: String? {
        switch self {
        case .validation(let msg): return "Validation failed: \(msg)"
        case .persistence(let e):  return "Persistence failed: \(e.localizedDescription)"
        case .freeAlarmLimit:
            return String(localized: "Free covers \(FreeTier.enabledAlarmLimit) alarms. Upgrade to Premium for as many as you need.", comment: "Free alarm limit reached")
        }
    }
}

// MARK: - AlarmManager

/// Single write boundary for all alarm mutations.
///
/// Transaction order for save(_:):
///   1. Validate  — fast fail, zero side-effects
///   2. Persist   — repository write; if this fails, scheduling is not attempted
///   3. Cancel every registered re-arm/snooze for the alarm (an edit invalidates them)
///   4. Schedule / cancel — engine call; if this fails, alarm remains persisted
///      and a reconcile() pass will retry on the next launch or foreground transition
///
/// The repository is always the source of truth.
/// Engine state is reconciled against it on every app launch and foreground transition.
actor AlarmManager {
    /// Minimum playback volume. Anything quieter is inaudible on a night stand.
    static let minimumVolume: Float = 0.3

    /// `Log.alarm` is main-actor isolated (project default isolation); the actor needs its own.
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MorningCompanion", category: "Alarm")

    private let repository: any AlarmRepositoryProtocol
    private let engine: any AlarmEngineServiceProtocol
    private let registry: ReArmRegistry
    private let entitlements: any EntitlementProviding

    init(
        repository: any AlarmRepositoryProtocol,
        engine: any AlarmEngineServiceProtocol,
        registry: ReArmRegistry = ReArmRegistry(),
        entitlements: any EntitlementProviding = CachedEntitlementProvider()
    ) {
        self.repository = repository
        self.engine = engine
        self.registry = registry
        self.entitlements = entitlements
    }

    // MARK: - Read

    func fetchAll() async throws -> [Alarm] {
        try await repository.fetchAll()
    }

    func alarm(id: UUID) async -> Alarm? {
        (try? await repository.fetchAll())?.first { $0.id == id }
    }

    /// True while the system (AlarmKit) is alerting for `id`.
    func isAlerting(id: UUID) async -> Bool {
        await engine.isAlerting(id: id)
    }

    // MARK: - Write

    func save(_ alarm: Alarm) async -> AlarmManagerResult {
        if let validationError = validate(alarm) {
            return .failure(.validation(validationError))
        }
        if let gateError = await freeTierRejection(for: alarm) {
            return .failure(gateError)
        }

        do {
            try await repository.save(alarm)
        } catch {
            return .failure(.persistence(error))
        }

        // Any snooze / re-arm created for the previous version of this alarm is now wrong.
        await cancelReArms(for: alarm.id)

        do {
            if alarm.isEnabled {
                try await engine.schedule(alarm)
            } else {
                try await engine.cancel(id: alarm.id)
            }
        } catch {
            return .partialSuccess(alarm, schedulingError: error)
        }

        return .success(alarm)
    }

    // MARK: - Free-tier gate

    /// Enforces the free alarm limit at the model layer (docs/15 §10), so no UI path
    /// — editor, duplicate, toggle, Siri intent — can slip past it.
    ///
    /// Two rules, both counting alarms that already exist:
    /// - a *new* alarm is refused once the account is already at the limit;
    /// - switching an alarm *on* is refused when the limit is already switched on.
    ///
    /// A downgrade never deletes or silences what is already there: alarms someone
    /// relies on to wake up keep ringing, they just cannot add or re-enable more.
    private func freeTierRejection(for alarm: Alarm) async -> AlarmManagerError? {
        guard !entitlements.isPremium else { return nil }
        guard let existing = try? await repository.fetchAll() else { return nil }

        let isNew = !existing.contains { $0.id == alarm.id }
        if isNew, existing.count >= FreeTier.enabledAlarmLimit { return .freeAlarmLimit }

        guard alarm.isEnabled else { return nil }
        let wasEnabled = existing.first { $0.id == alarm.id }?.isEnabled ?? false
        guard !wasEnabled else { return nil }  // already on — an edit must not be blocked
        let othersEnabled = existing.filter { $0.id != alarm.id && $0.isEnabled }.count
        return othersEnabled >= FreeTier.enabledAlarmLimit ? .freeAlarmLimit : nil
    }

    /// Schedules a registry-tracked snooze `delay` seconds from now.
    /// Does not modify the persisted alarm. Returns the re-arm id on success.
    @discardableResult
    func snooze(_ alarm: Alarm, delay: TimeInterval) async -> UUID? {
        let id = UUID()
        return await scheduleReArm(for: alarm, reArmID: id, delay: delay, kind: .snooze) ? id : nil
    }

    /// Schedules a one-shot re-arm alarm under `reArmID` after `delay` seconds and
    /// records it in the registry so it can always be found and cancelled later.
    @discardableResult
    func scheduleReArm(
        for alarm: Alarm,
        reArmID: UUID,
        delay: TimeInterval,
        kind: ReArmRegistry.Kind = .reArm
    ) async -> Bool {
        let fireDate = Date().addingTimeInterval(max(1, delay))
        registry.register(reArmID: reArmID, originalID: alarm.id, fireDate: fireDate, kind: kind)
        do {
            try await engine.scheduleReArm(for: alarm, reArmID: reArmID, delay: delay)
            return true
        } catch {
            Self.logger.error("Re-arm \(reArmID.uuidString, privacy: .public) for \(alarm.id.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            registry.remove(reArmID: reArmID)
            return false
        }
    }

    /// Cancels one registered re-arm (e.g. the one that just fired) and forgets it.
    func cancelReArm(id: UUID) async {
        try? await engine.cancel(id: id)
        registry.remove(reArmID: id)
    }

    /// Cancels every snooze / re-arm registered for `originalID` and forgets them.
    func cancelReArms(for originalID: UUID) async {
        for id in registry.reArmIDs(for: originalID) {
            try? await engine.cancel(id: id)
        }
        registry.removeAll(for: originalID)
    }

    /// Cancels re-arms of one kind only (e.g. the wake-check auto-fail).
    func cancelReArms(for originalID: UUID, kind: ReArmRegistry.Kind) async {
        for id in registry.reArmIDs(for: originalID, kind: kind) {
            try? await engine.cancel(id: id)
            registry.remove(reArmID: id)
        }
    }

    /// Marks a completed one-shot alarm disabled while preserving it in history.
    /// Repeating alarms remain scheduled by AlarmKit for their next occurrence.
    func completeOccurrence(for alarm: Alarm) async {
        await cancelReArms(for: alarm.id)
        guard case .oneTime = alarm.recurrence else { return }
        var completed = alarm
        completed.isEnabled = false
        try? await repository.save(completed)
        try? await engine.cancel(id: alarm.id)
    }

    func delete(id: UUID) async -> AlarmManagerResult {
        do {
            try await repository.delete(id: id)
        } catch {
            return .failure(.persistence(error))
        }
        await cancelReArms(for: id)
        try? await engine.cancel(id: id)
        return .deleted
    }

    // MARK: - Reconciliation

    /// Brings the engine in line with the repository.
    ///
    /// - Enabled alarms missing from the engine (or parked on the notification
    ///   fallback) are (re)scheduled — through `validate`, so a one-time alarm
    ///   whose date has passed is disabled instead of re-registered in the past.
    /// - Engine ids that are neither enabled alarms nor registered re-arms are cancelled.
    /// - Registered re-arms whose original alarm is gone or disabled are cancelled.
    func reconcile(skipIDs: Set<UUID> = []) async {
        guard let alarms = try? await repository.fetchAll(),
              let pendingIDs = try? await engine.pendingAlarmIDs() else { return }

        // 0. Registry hygiene: forget stale entries, then drop orphans.
        for staleID in registry.prune() { try? await engine.cancel(id: staleID) }
        let activeOriginals = Set(alarms.filter(\.isEnabled).map(\.id))
        let orphans = ReArmRegistry.orphanedReArmIDs(entries: registry.entries, activeOriginalIDs: activeOriginals)
        for id in orphans {
            try? await engine.cancel(id: id)
            registry.remove(reArmID: id)
        }
        let knownReArmIDs = registry.allReArmIDs

        let fallbackIDs = await engine.idsHeldByFallback()
        let plan = Self.reconcilePlan(
            alarms: alarms,
            pendingIDs: Set(pendingIDs),
            skipIDs: skipIDs,
            reArmIDs: knownReArmIDs,
            fallbackIDs: fallbackIDs
        )

        for alarm in plan.toSchedule {
            if let reason = validate(alarm) {
                if Self.isPastOneTime(alarm) {
                    Self.logger.warning("Reconcile: one-time alarm \(alarm.id.uuidString, privacy: .public) is in the past — disabling instead of re-registering")
                    var expired = alarm
                    expired.isEnabled = false
                    try? await repository.save(expired)
                    try? await engine.cancel(id: alarm.id)
                    await cancelReArms(for: alarm.id)
                } else {
                    Self.logger.warning("Reconcile: alarm \(alarm.id.uuidString, privacy: .public) failed validation (\(reason, privacy: .public)) — skipped")
                }
                continue
            }
            do { try await engine.schedule(alarm) }
            catch { Self.logger.error("Reconcile: schedule \(alarm.id.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)") }
        }

        for id in plan.toCancel {
            try? await engine.cancel(id: id)
        }
    }

    struct ReconcilePlan: Equatable {
        var toSchedule: [Alarm]
        var toCancel: [UUID]
    }

    /// Pure planning step so the reconcile rules are unit-testable without an engine.
    nonisolated static func reconcilePlan(
        alarms: [Alarm],
        pendingIDs: Set<UUID>,
        skipIDs: Set<UUID>,
        reArmIDs: Set<UUID>,
        fallbackIDs: Set<UUID>
    ) -> ReconcilePlan {
        let enabledAlarms = alarms.filter(\.isEnabled)
        let enabledIDs = Set(enabledAlarms.map(\.id))
        let known = pendingIDs.union(skipIDs)

        // Alarms on the fallback engine are re-attempted so they can move to AlarmKit.
        let toSchedule = enabledAlarms.filter { !known.contains($0.id) || fallbackIDs.contains($0.id) }
        let toCancel = pendingIDs.filter { !enabledIDs.contains($0) && !reArmIDs.contains($0) }
        return ReconcilePlan(toSchedule: toSchedule, toCancel: Array(toCancel))
    }

    nonisolated static func isPastOneTime(_ alarm: Alarm, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard case .oneTime(let alarmDate) = alarm.recurrence else { return false }
        var components = DateComponents()
        components.year = alarmDate.year; components.month = alarmDate.month
        components.day = alarmDate.day; components.hour = alarm.wallClockTime.hour
        components.minute = alarm.wallClockTime.minute
        guard let date = calendar.date(from: components) else { return true }
        return date <= now
    }

    // MARK: - Validation

    /// Returns a human-readable reason the alarm cannot be scheduled, or nil when valid.
    func validate(_ alarm: Alarm) -> String? {
        guard (0..<24).contains(alarm.wallClockTime.hour) else {
            return "Hour must be 0–23, got \(alarm.wallClockTime.hour)"
        }
        guard (0..<60).contains(alarm.wallClockTime.minute) else {
            return "Minute must be 0–59, got \(alarm.wallClockTime.minute)"
        }
        if case .repeating(let days) = alarm.recurrence, days.isEmpty {
            return "A repeating alarm requires at least one weekday"
        }
        if case .oneTime = alarm.recurrence, Self.isPastOneTime(alarm) {
            return "A one-time alarm must be scheduled in the future"
        }
        guard alarm.volume >= Self.minimumVolume else {
            return "Volume must be at least \(Int(Self.minimumVolume * 100))%"
        }
        guard alarm.missions.count >= 1 else {
            return "An alarm requires at least one mission"
        }
        guard alarm.missions.count <= 3 else {
            return "A maximum of 3 missions is allowed"
        }
        for mission in alarm.missions where !mission.isConfigured {
            return "'\(mission.displayName)' mission requires setup before saving"
        }
        return nil
    }
}
