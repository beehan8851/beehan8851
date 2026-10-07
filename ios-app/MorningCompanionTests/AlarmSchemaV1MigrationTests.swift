import Foundation
import Testing
@testable import MorningCompanion

/// Reading the schema this app used before the alarm model was rebuilt.
///
/// The payloads below are written by hand rather than by encoding a Swift type,
/// because the point of these tests is bytes that already exist on someone's phone.
/// If the v1 struct were still around to encode from, there would be nothing to test.
@Suite("Alarm schema v1 migration")
struct AlarmSchemaV1MigrationTests {

    /// A v1 alarm as `JSONEncoder` wrote it: `time` is an absolute instant encoded as
    /// seconds since the reference date, `repeatDays` is an array of `Weekday` raws.
    private func v1Alarm(
        id: UUID = UUID(),
        label: String = "Wake up",
        hour: Int = 7,
        minute: Int = 0,
        repeatDays: [Int] = [2, 3, 4, 5, 6],
        missionType: String = "math",
        isSnoozeEnabled: Bool = true,
        isEnabled: Bool = true
    ) -> [String: Any] {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = hour
        components.minute = minute
        let instant = Calendar.current.date(from: components) ?? .now
        return [
            "id": id.uuidString,
            "label": label,
            "time": instant.timeIntervalSinceReferenceDate,
            "repeatDays": repeatDays,
            "missionType": missionType,
            "sound": "default",
            "isSnoozeEnabled": isSnoozeEnabled,
            "isEnabled": isEnabled,
        ]
    }

    private func data(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    // MARK: - Field migration

    @Test("A v1 alarm keeps its wall-clock time")
    func timeSurvives() throws {
        let payload = try data([v1Alarm(hour: 6, minute: 45)])
        let envelope = try JSONDecoder().decode(AlarmEnvelope.self, from: payload)
        let alarm = try #require(envelope.alarms.first)
        #expect(alarm.wallClockTime == AlarmTime(hour: 6, minute: 45))
    }

    @Test("Weekdays become a repeating recurrence")
    func weekdaysBecomeRepeating() throws {
        let payload = try data([v1Alarm(repeatDays: [2, 6])])
        let envelope = try JSONDecoder().decode(AlarmEnvelope.self, from: payload)
        let alarm = try #require(envelope.alarms.first)
        #expect(alarm.recurrence == .repeating(days: [.monday, .friday]))
    }

    @Test("All seven weekdays collapse to daily")
    func everyDayBecomesDaily() throws {
        let payload = try data([v1Alarm(repeatDays: [1, 2, 3, 4, 5, 6, 7])])
        let envelope = try JSONDecoder().decode(AlarmEnvelope.self, from: payload)
        #expect(envelope.alarms.first?.recurrence == .daily)
    }

    @Test("An alarm with no repeat days is not migrated into the past")
    func nonRepeatingFiresInTheFuture() throws {
        // The stored instant is this morning, so a naive migration would produce a
        // one-time alarm whose date has already passed — a silently dead alarm.
        let payload = try data([v1Alarm(hour: 0, minute: 1, repeatDays: [])])
        let envelope = try JSONDecoder().decode(AlarmEnvelope.self, from: payload)
        let alarm = try #require(envelope.alarms.first)
        guard case .oneTime(let date) = alarm.recurrence else {
            Issue.record("expected a one-time recurrence, got \(alarm.recurrence)")
            return
        }
        let today = AlarmDate(from: .now)
        #expect(date == today || date == AlarmDate(from: Date.now.addingTimeInterval(86_400)))
    }

    @Test("Retired mission types fall back to Math rather than to nothing")
    func retiredMissionsFallBack() throws {
        for retired in ["photo", "nfc", "walking"] {
            let payload = try data([v1Alarm(missionType: retired)])
            let envelope = try JSONDecoder().decode(AlarmEnvelope.self, from: payload)
            let alarm = try #require(envelope.alarms.first)
            #expect(alarm.missions.count == 1)
            #expect(alarm.missions.first?.kind == .math)
        }
    }

    @Test("Snooze off in v1 stays off")
    func snoozeSurvives() throws {
        let payload = try data([v1Alarm(isSnoozeEnabled: false)])
        let envelope = try JSONDecoder().decode(AlarmEnvelope.self, from: payload)
        #expect(envelope.alarms.first?.snooze == .off)
    }

    @Test("Fields v1 never had get the defaults a new alarm would")
    func absentFieldsGetDefaults() throws {
        let payload = try data([v1Alarm()])
        let envelope = try JSONDecoder().decode(AlarmEnvelope.self, from: payload)
        let alarm = try #require(envelope.alarms.first)
        #expect(alarm.volume >= AlarmManager.minimumVolume)
        #expect(alarm.gradualWakeDuration == .off)
        #expect(alarm.wakeCheck == .off)
    }

    // MARK: - Envelope shape

    @Test("A bare v1 array is read as schema 1")
    func bareArrayIsVersionOne() throws {
        let payload = try data([v1Alarm(), v1Alarm(label: "Gym")])
        let envelope = try JSONDecoder().decode(AlarmEnvelope.self, from: payload)
        #expect(envelope.schemaVersion == 1)
        #expect(envelope.alarms.count == 2)
        #expect(envelope.needsUpgrade)
    }

    @Test("One unreadable v1 alarm does not take the others with it")
    func corruptEntryIsIsolated() throws {
        var broken = v1Alarm(label: "Broken")
        broken.removeValue(forKey: "time")          // neither v1 nor v2 time
        let payload = try data([v1Alarm(label: "Good"), broken, v1Alarm(label: "Also good")])
        let envelope = try JSONDecoder().decode(AlarmEnvelope.self, from: payload)
        #expect(envelope.alarms.count == 2)
        #expect(envelope.alarms.map(\.label) == ["Good", "Also good"])
    }

    @Test("A v2 envelope is untouched")
    func currentSchemaIsNotUpgraded() throws {
        let original = AlarmEnvelope(alarms: [Alarm(label: "Wake up")])
        let payload = try JSONEncoder().encode(original)
        let envelope = try JSONDecoder().decode(AlarmEnvelope.self, from: payload)
        #expect(envelope.schemaVersion == AlarmEnvelope.currentSchemaVersion)
        #expect(!envelope.needsUpgrade)
        #expect(envelope.alarms.first?.label == "Wake up")
    }

    // MARK: - Through the repository

    @Test("Reading a v1 store rewrites it in the current shape")
    func repositoryUpgradesInPlace() async throws {
        let storage = InMemoryStorageService()
        let key = "com.morningcompanion.alarms.v1"
        storage.injectRaw(try data([v1Alarm(label: "Wake up", hour: 6, minute: 30)]), key: key)

        let repository = LocalAlarmRepository(storage: storage)
        let alarms = try await repository.fetchAll()
        #expect(alarms.count == 1)
        #expect(alarms.first?.wallClockTime == AlarmTime(hour: 6, minute: 30))

        // The store now holds a v2 envelope, so the v1 path is never taken again.
        let rewritten: AlarmEnvelope = try storage.load(key: key)
        #expect(rewritten.schemaVersion == AlarmEnvelope.currentSchemaVersion)
        #expect(rewritten.alarms.first?.label == "Wake up")
    }
}
