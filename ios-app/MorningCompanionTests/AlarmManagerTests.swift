import Testing
import Foundation
@testable import MorningCompanion

// MARK: - Test helpers

private final class SeedableEngineService: AlarmEngineServiceProtocol {
    var pendingIDs: [UUID] = []

    func schedule(_ alarm: Alarm) async throws {
        if !pendingIDs.contains(alarm.id) { pendingIDs.append(alarm.id) }
    }
    func scheduleSnooze(for alarm: Alarm, delay: TimeInterval) async throws {}
    func scheduleReArm(for alarm: Alarm, reArmID: UUID, delay: TimeInterval) async throws {}
    func cancel(id: UUID) async throws {
        pendingIDs.removeAll { $0 == id }
    }
    func cancelAll() async throws { pendingIDs.removeAll() }
    func pendingAlarmIDs() async throws -> [UUID] { pendingIDs }
}

@Suite("AlarmManager")
struct AlarmManagerTests {

    private func makeManager(
        alarms: [Alarm] = [],
        fetchError: (any Error)? = nil,
        engine: any AlarmEngineServiceProtocol = StubAlarmEngineService()
    ) -> AlarmManager {
        let repo = MockAlarmRepository(alarms: alarms, fetchError: fetchError)
        return AlarmManager(repository: repo, engine: engine)
    }

    // MARK: - Validation

    @Test("Invalid hour returns validation failure")
    func invalidHour() async {
        let alarm = Alarm(wallClockTime: AlarmTime(hour: 24, minute: 0), recurrence: .daily)
        let manager = makeManager()
        let result = await manager.save(alarm)
        if case .failure(let err) = result, case .validation = err { } else {
            Issue.record("Expected .failure(.validation), got \(result)")
        }
    }

    @Test("Invalid minute returns validation failure")
    func invalidMinute() async {
        let alarm = Alarm(wallClockTime: AlarmTime(hour: 7, minute: 60), recurrence: .daily)
        let manager = makeManager()
        let result = await manager.save(alarm)
        if case .failure(let err) = result, case .validation = err { } else {
            Issue.record("Expected .failure(.validation), got \(result)")
        }
    }

    @Test("Repeating alarm with empty days returns validation failure")
    func repeatingEmptyDaysValidation() async {
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .repeating(days: [])
        )
        let manager = makeManager()
        let result = await manager.save(alarm)
        if case .failure(let err) = result, case .validation = err { } else {
            Issue.record("Expected .failure(.validation), got \(result)")
        }
    }

    @Test("Past one-time alarm returns validation failure")
    func pastOneTimeValidation() async {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let components = Calendar.current.dateComponents([.year, .month, .day], from: yesterday)
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .oneTime(date: AlarmDate(
                year: components.year!,
                month: components.month!,
                day: components.day!
            ))
        )
        let result = await makeManager().save(alarm)
        if case .failure(let error) = result, case .validation = error { } else {
            Issue.record("Expected a validation failure, got \(result)")
        }
    }

    // MARK: - Persistence failure

    @Test("Write error returns persistence failure without scheduling")
    func persistenceFailure() async {
        let alarm = Alarm(wallClockTime: AlarmTime(hour: 7, minute: 0), recurrence: .daily)
        let engine = SeedableEngineService()
        let repo = MockAlarmRepository(alarms: [])
        repo.writeError = AlarmRepositoryError.dataCorrupted(reason: "disk full")
        let manager = AlarmManager(repository: repo, engine: engine)

        let result = await manager.save(alarm)
        if case .failure(let err) = result, case .persistence = err { } else {
            Issue.record("Expected .failure(.persistence), got \(result)")
        }
        // Engine must not have been touched
        #expect(engine.pendingIDs.isEmpty)
    }

    // MARK: - Partial success

    @Test("Engine failure after persist returns partialSuccess")
    func engineFailureIsPartialSuccess() async {
        let alarm = Alarm(wallClockTime: AlarmTime(hour: 7, minute: 0), recurrence: .daily)
        let repo = MockAlarmRepository(alarms: [])
        let engine = FailingAlarmEngineService()
        let manager = AlarmManager(repository: repo, engine: engine)

        let result = await manager.save(alarm)
        if case .partialSuccess(let persisted, _) = result {
            #expect(persisted.id == alarm.id)
        } else {
            Issue.record("Expected .partialSuccess, got \(result)")
        }
        // Alarm must be in the repository despite the engine error
        let stored = try? await manager.fetchAll()
        #expect(stored?.contains { $0.id == alarm.id } == true)
    }

    // MARK: - Happy path

    @Test("Valid alarm save returns success and is fetchable")
    func saveThenFetch() async throws {
        let alarm = Alarm(
            label: "Morning",
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .daily
        )
        let manager = makeManager()
        let result = await manager.save(alarm)
        if case .success(let saved) = result {
            #expect(saved.id == alarm.id)
        } else {
            Issue.record("Expected .success, got \(result)")
        }
        let fetched = try await manager.fetchAll()
        #expect(fetched.contains { $0.id == alarm.id })
    }

    @Test("Delete returns .deleted and removes alarm from repository")
    func deleteAlarm() async throws {
        let alarm = Alarm(wallClockTime: AlarmTime(hour: 7, minute: 0), recurrence: .daily)
        let manager = makeManager(alarms: [alarm])
        let result = await manager.delete(id: alarm.id)
        if case .deleted = result { } else {
            Issue.record("Expected .deleted, got \(result)")
        }
        let remaining = try await manager.fetchAll()
        #expect(!remaining.contains { $0.id == alarm.id })
    }

    // MARK: - Reconciliation

    @Test("Reconcile schedules missing enabled alarms")
    func reconcileSchedulesMissing() async {
        let alarm1 = Alarm(wallClockTime: AlarmTime(hour: 7, minute: 0), recurrence: .daily, isEnabled: true)
        let alarm2 = Alarm(wallClockTime: AlarmTime(hour: 8, minute: 0), recurrence: .daily, isEnabled: true)
        let engine = SeedableEngineService()
        engine.pendingIDs = [alarm1.id]  // alarm2 is missing from engine

        let repo = MockAlarmRepository(alarms: [alarm1, alarm2])
        let manager = AlarmManager(repository: repo, engine: engine)
        await manager.reconcile()

        #expect(engine.pendingIDs.contains(alarm1.id))
        #expect(engine.pendingIDs.contains(alarm2.id))
    }

    @Test("Reconcile cancels orphaned pending IDs")
    func reconcileCancelsOrphans() async {
        let orphanID = UUID()
        let engine = SeedableEngineService()
        engine.pendingIDs = [orphanID]  // nothing in repository

        let repo = MockAlarmRepository(alarms: [])
        let manager = AlarmManager(repository: repo, engine: engine)
        await manager.reconcile()

        #expect(engine.pendingIDs.isEmpty)
    }

    @Test("Reconcile is a no-op when repository fetch fails")
    func reconcileSilentOnFetchError() async {
        let engine = SeedableEngineService()
        let repo = MockAlarmRepository(alarms: [], fetchError: StorageError.notFound(key: "x"))
        let manager = AlarmManager(repository: repo, engine: engine)
        // Should not throw and should leave engine state unchanged
        await manager.reconcile()
        #expect(engine.pendingIDs.isEmpty)
    }
}
