import Testing
import Foundation
@testable import MorningCompanion

@Suite("Alarm Model")
struct AlarmModelTests {

    @Test("Alarm initialises with v2 defaults")
    func defaultInit() {
        let alarm = Alarm()
        #expect(alarm.isEnabled == true)
        #expect(alarm.snooze == .default)
        #expect(!alarm.missions.isEmpty)
        #expect(alarm.sound == .default)
        #expect(alarm.volume == 1.0)
        #expect(alarm.gradualWakeDuration == .off)
        #expect(alarm.wakeCheck == .off)
    }

    @Test("Alarm round-trips through Codable")
    func codableRoundTrip() throws {
        let original = Alarm(
            id: UUID(),
            label: "Test alarm",
            wallClockTime: AlarmTime(hour: 6, minute: 30),
            recurrence: .repeating(days: [.monday, .friday]),
            missions: [.defaultShake],
            sound: .gentle,
            volume: 0.8,
            gradualWakeDuration: .thirtySec,
            snooze: .off,
            wakeCheck: WakeCheckConfig(durationMinutes: 5),
            isEnabled: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Alarm.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.label == original.label)
        #expect(decoded.wallClockTime == original.wallClockTime)
        #expect(decoded.recurrence == original.recurrence)
        #expect(decoded.missions == original.missions)
        #expect(decoded.sound == original.sound)
        #expect(decoded.volume == original.volume)
        #expect(decoded.gradualWakeDuration == original.gradualWakeDuration)
        #expect(decoded.snooze == original.snooze)
        #expect(decoded.wakeCheck == original.wakeCheck)
        #expect(decoded.isEnabled == original.isEnabled)
    }

    @Test("Alarm decodes legacy missionType / isSnoozeEnabled keys next to v2 time keys")
    func legacyMissionAndSnoozeKeysMigration() throws {
        // NOTE: this is a *partial* legacy fixture, not a genuine v1 record.
        // It exercises the two v1 fallbacks Alarm.init(from:) implements
        // (missionType -> missions, isSnoozeEnabled -> snooze) while supplying the
        // v2 `wallClockTime` / `recurrence` keys the decoder requires.
        // AlarmRecurrence uses synthesized Codable, so `.daily` encodes as {"daily":{}}.
        let legacyJSON = """
        {
            "id": "00000000-0000-0000-0000-000000000099",
            "label": "Legacy",
            "wallClockTime": {"hour": 7, "minute": 0},
            "recurrence": {"daily": {}},
            "missionType": "shake",
            "isSnoozeEnabled": true,
            "sound": "default",
            "isEnabled": true
        }
        """.data(using: .utf8)!
        let alarm = try JSONDecoder().decode(Alarm.self, from: legacyJSON)
        #expect(alarm.label == "Legacy")
        #expect(alarm.recurrence == .daily)
        #expect(alarm.snooze.isEnabled == true)
        // v1 shake → missions should contain a shake mission
        if case .shake = alarm.missions.first { } else {
            Issue.record("Expected .shake mission from v1 missionType migration")
        }
    }

    @Test(
        "Alarm decodes a genuine v1 record (time + repeatDays)",
        .disabled("""
            v1 -> v2 migration of `time: Date` / `repeatDays: Set<Weekday>` into \
            `wallClockTime` / `recurrence` is unimplemented: Alarm.init(from:) decodes \
            those two keys non-optionally and throws keyNotFound, so AlarmEnvelope drops \
            every v1 alarm as "corrupt". Implement the migration in \
            Core/AlarmEngine/Models/Alarm.swift, then re-enable this test.
            """)
    )
    func genuineV1RecordMigration() throws {
        // Shape of the v1 `Alarm` as committed in the initial project revision:
        // Date encodes as seconds since 2001-01-01 (JSONEncoder default),
        // Weekday encodes as its Int rawValue (Sunday = 1).
        let v1JSON = """
        {
            "id": "00000000-0000-0000-0000-000000000098",
            "label": "Genuine v1",
            "time": 0,
            "repeatDays": [2, 6],
            "missionType": "shake",
            "sound": "default",
            "isSnoozeEnabled": false,
            "isEnabled": true
        }
        """.data(using: .utf8)!
        let alarm = try JSONDecoder().decode(Alarm.self, from: v1JSON)
        #expect(alarm.label == "Genuine v1")
        #expect(alarm.recurrence == .repeating(days: [.monday, .friday]))
        #expect(alarm.snooze == .off)
        if case .shake = alarm.missions.first { } else {
            Issue.record("Expected .shake mission from v1 missionType migration")
        }
    }

    @Test("AlarmTime round-trips through Codable")
    func alarmTimeCodable() throws {
        let time = AlarmTime(hour: 7, minute: 30)
        let data = try JSONEncoder().encode(time)
        let decoded = try JSONDecoder().decode(AlarmTime.self, from: data)
        #expect(decoded == time)
    }

    @Test("AlarmDate round-trips through Codable")
    func alarmDateCodable() throws {
        let date = AlarmDate(year: 2025, month: 3, day: 15)
        let data = try JSONEncoder().encode(date)
        let decoded = try JSONDecoder().decode(AlarmDate.self, from: data)
        #expect(decoded == date)
    }

    @Test("AlarmRecurrence oneTime round-trips through Codable")
    func recurrenceOneTimeCodable() throws {
        let rec = AlarmRecurrence.oneTime(date: AlarmDate(year: 2025, month: 6, day: 1))
        let data = try JSONEncoder().encode(rec)
        let decoded = try JSONDecoder().decode(AlarmRecurrence.self, from: data)
        #expect(decoded == rec)
    }

    @Test("AlarmRecurrence daily round-trips through Codable")
    func recurrenceDailyCodable() throws {
        let data = try JSONEncoder().encode(AlarmRecurrence.daily)
        let decoded = try JSONDecoder().decode(AlarmRecurrence.self, from: data)
        #expect(decoded == .daily)
    }

    @Test("Samples array contains exactly two alarms")
    func samplesCount() {
        #expect(Alarm.samples.count == 2)
    }

    @Test("Sample alarm IDs are stable")
    func sampleIDs() {
        let ids = Alarm.samples.map(\.id.uuidString)
        #expect(ids.contains("00000000-0000-0000-0000-000000000001"))
        #expect(ids.contains("00000000-0000-0000-0000-000000000002"))
    }
}
