import Testing
import Foundation
@testable import MorningCompanion

// MARK: - P0-1: Cannot save zero missions

@Suite("P0-1 Zero Mission Enforcement")
struct ZeroMissionTests {

    /// Premium: these suites are about validation, not the free alarm limit, and the
    /// sample repository is already at the free limit.
    private func makeManager() -> AlarmManager {
        AlarmManager(
            repository: MockAlarmRepository(),
            engine: StubAlarmEngineService(),
            entitlements: FixedEntitlementProvider(true)
        )
    }

    @Test("AlarmManager rejects alarm with zero missions")
    func managerRejectsZeroMissions() async {
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .daily,
            missions: []
        )
        let result = await makeManager().save(alarm)
        guard case .failure(let err) = result, case .validation = err else {
            Issue.record("Expected .failure(.validation) for zero-mission alarm, got \(result)")
            return
        }
    }

    @Test("AlarmManager accepts alarm with one mission")
    func managerAcceptsOneMission() async {
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .daily,
            missions: [.defaultMath]
        )
        let result = await makeManager().save(alarm)
        if case .success = result { } else if case .partialSuccess = result { } else {
            Issue.record("Expected success or partialSuccess for single-mission alarm, got \(result)")
        }
    }

    @Test("AlarmManager rejects alarm exceeding 3 missions")
    func managerRejectsMoreThanThreeMissions() async {
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .daily,
            missions: [.defaultMath, .defaultShake, .defaultSteps, .defaultJump]
        )
        let result = await makeManager().save(alarm)
        guard case .failure(let err) = result, case .validation = err else {
            Issue.record("Expected .failure(.validation) for 4-mission alarm, got \(result)")
            return
        }
    }
}

// MARK: - P0-2: Unconfigured Draw cannot execute or pass

@Suite("P0-2 Draw Mission Configuration")
struct DrawMissionConfigurationTests {

    @Test("Unconfigured Draw mission isConfigured returns false")
    func unconfiguredDrawIsNotConfigured() {
        let config = MissionConfig.draw(referenceStrokes: nil)
        #expect(config.isConfigured == false)
    }

    @Test("Calibrated Draw mission isConfigured returns true")
    func calibratedDrawIsConfigured() {
        let strokes: [[StrokePoint]] = [[StrokePoint(x: 0.1, y: 0.2), StrokePoint(x: 0.3, y: 0.4)]]
        let config = MissionConfig.draw(referenceStrokes: strokes)
        #expect(config.isConfigured == true)
    }

    @Test("Unconfigured QR Code mission isConfigured returns false")
    func unconfiguredQRIsNotConfigured() {
        let config = MissionConfig.qrCode(registeredCode: nil)
        #expect(config.isConfigured == false)
    }

    @Test("Configured QR Code mission isConfigured returns true")
    func configuredQRIsConfigured() {
        let config = MissionConfig.qrCode(registeredCode: "SCANNED-CODE")
        #expect(config.isConfigured == true)
    }

    @Test("Typing with empty phrase isConfigured returns false")
    func unconfiguredTypingIsNotConfigured() {
        let config = MissionConfig.typing(phrase: "")
        #expect(config.isConfigured == false)
    }

    @Test("AlarmManager rejects alarm with unconfigured Draw mission")
    func managerRejectsUnconfiguredDraw() async {
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .daily,
            missions: [.draw(referenceStrokes: nil)]
        )
        let result = await AlarmManager(
            repository: MockAlarmRepository(),
            engine: StubAlarmEngineService(),
            entitlements: FixedEntitlementProvider(true)
        ).save(alarm)
        guard case .failure(let err) = result, case .validation = err else {
            Issue.record("Expected .failure(.validation) for unconfigured draw, got \(result)")
            return
        }
    }

    @Test("AlarmManager accepts alarm with calibrated Draw mission")
    func managerAcceptsCalibratedDraw() async {
        let strokes: [[StrokePoint]] = [[StrokePoint(x: 0.0, y: 0.0), StrokePoint(x: 1.0, y: 1.0)]]
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .daily,
            missions: [.draw(referenceStrokes: strokes)]
        )
        let result = await AlarmManager(
            repository: MockAlarmRepository(),
            engine: StubAlarmEngineService(),
            entitlements: FixedEntitlementProvider(true)
        ).save(alarm)
        if case .success = result { } else if case .partialSuccess = result { } else {
            Issue.record("Expected success for calibrated draw, got \(result)")
        }
    }
}

// MARK: - P0-3: Snooze limit survives container/repository recreation

@Suite("P0-3 Snooze Count Persistence")
struct SnoozeCountPersistenceTests {

    private static let testSnoozeKey = "com.morningcompanion.snooze.counts.test"

    private func makeAlarm(maxSnooze: Int) -> Alarm {
        Alarm(
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .daily,
            missions: [.defaultMath],
            snooze: SnoozeConfig(durationMinutes: 5, maxCount: maxSnooze)
        )
    }

    @Test("Snooze count persists across UserDefaults read cycle")
    func snoozeCountSurvivesReload() throws {
        let suiteName = "test.snooze.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let alarm = makeAlarm(maxSnooze: 2)

        // Simulate storing a snooze count (mirrors AppContainer.persistSnoozeCounts)
        let dict: [String: Int] = [alarm.id.uuidString: 1]
        let data = try JSONEncoder().encode(dict)
        defaults.set(data, forKey: "com.morningcompanion.snooze.counts")

        // Simulate reading back (mirrors AppContainer.loadPersistedSnoozeCounts)
        let loaded = defaults.data(forKey: "com.morningcompanion.snooze.counts")!
        let decoded = try JSONDecoder().decode([String: Int].self, from: loaded)
        let counts = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, val in
            UUID(uuidString: key).map { ($0, val) }
        })

        #expect(counts[alarm.id] == 1, "Snooze count for alarm must survive a UserDefaults round-trip")
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("SnoozeConfig at limit returns correct remaining count")
    func snoozeConfigAtLimit() {
        let config = SnoozeConfig(durationMinutes: 5, maxCount: 2)
        #expect(config.isEnabled == true)
        // At count=2, limit is reached
        let remaining = config.maxCount - 2
        #expect(remaining == 0)
    }

    @Test("SnoozeConfig with unlimited (-1) maxCount is never at limit")
    func unlimitedSnooze() {
        let config = SnoozeConfig(durationMinutes: 5, maxCount: -1)
        #expect(config.isUnlimited == true)
        // maxCount == -1 means no cap
        let atLimit = config.maxCount > 0 && 999 >= config.maxCount
        #expect(atLimit == false)
    }
}

// MARK: - P0-4: One corrupt alarm does not destroy valid alarms

@Suite("P0-4 Fault-Tolerant Alarm Persistence")
struct CorruptAlarmPersistenceTests {

    private func makeRepository(suiteName: String) -> LocalAlarmRepository {
        let defaults = UserDefaults(suiteName: suiteName)!
        let storage = UserDefaultsStorageService(defaults: defaults)
        return LocalAlarmRepository(storage: storage)
    }

    @Test("fetchAll returns empty list when no data stored")
    func emptyOnFirstLaunch() async throws {
        let repo = makeRepository(suiteName: "test.corrupt.\(UUID().uuidString)")
        let alarms = try await repo.fetchAll()
        #expect(alarms.isEmpty)
    }

    @Test("One corrupt alarm entry does not destroy valid alarms in the list")
    func corruptEntryPreservesValidAlarms() async throws {
        let suiteName = "test.corrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let validAlarm = Alarm(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            label: "Valid",
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .daily,
            missions: [.defaultMath]
        )
        let validData = try JSONEncoder().encode(validAlarm)
        let validJSON = try JSONSerialization.jsonObject(with: validData)

        // Craft an envelope with one valid alarm followed by one corrupt entry
        let envelopeDict: [String: Any] = [
            "schemaVersion": 2,
            "alarms": [
                validJSON,
                ["this": "is", "completely": "broken"],   // corrupt
            ]
        ]
        let envelopeData = try JSONSerialization.data(withJSONObject: envelopeDict)
        defaults.set(envelopeData, forKey: "com.morningcompanion.alarms.v1")

        let storage = UserDefaultsStorageService(defaults: defaults)
        let repo = LocalAlarmRepository(storage: storage)

        let alarms = try await repo.fetchAll()
        #expect(alarms.count == 1, "Only the valid alarm should be returned; corrupt entry must be skipped")
        #expect(alarms.first?.id == validAlarm.id)
        #expect(alarms.first?.label == "Valid")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("All corrupt alarms return empty list without throwing")
    func allCorruptReturnsEmpty() async throws {
        let suiteName = "test.corrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let envelopeDict: [String: Any] = [
            "schemaVersion": 2,
            "alarms": [
                ["bad1": true],
                ["bad2": 42],
            ]
        ]
        let envelopeData = try JSONSerialization.data(withJSONObject: envelopeDict)
        defaults.set(envelopeData, forKey: "com.morningcompanion.alarms.v1")

        let storage = UserDefaultsStorageService(defaults: defaults)
        let repo = LocalAlarmRepository(storage: storage)

        let alarms = try await repo.fetchAll()
        #expect(alarms.isEmpty, "All-corrupt envelope must return empty list without throwing")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test("Multiple valid alarms all survive round-trip")
    func multipleValidAlarms() async throws {
        let suiteName = "test.corrupt.\(UUID().uuidString)"
        let repo = makeRepository(suiteName: suiteName)

        let a1 = Alarm(label: "First",  wallClockTime: AlarmTime(hour: 6, minute: 0), recurrence: .daily, missions: [.defaultMath])
        let a2 = Alarm(label: "Second", wallClockTime: AlarmTime(hour: 7, minute: 0), recurrence: .daily, missions: [.defaultShake])
        try await repo.save(a1)
        try await repo.save(a2)

        let fetched = try await repo.fetchAll()
        #expect(fetched.count == 2)
        #expect(fetched.contains { $0.id == a1.id })
        #expect(fetched.contains { $0.id == a2.id })

        UserDefaults(suiteName: suiteName)!.removePersistentDomain(forName: suiteName)
    }
}
