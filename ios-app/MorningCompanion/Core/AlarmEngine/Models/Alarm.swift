import Foundation

// MARK: - Alarm

struct Alarm: Identifiable, Sendable, Equatable {
    var id: UUID
    var label: String
    var wallClockTime: AlarmTime
    var recurrence: AlarmRecurrence
    /// One to three missions, executed sequentially at wake time.
    /// `AlarmManager.validate` rejects an empty array, so a saved alarm always has at
    /// least one; the ring screen still tolerates an empty one defensively.
    var missions: [MissionConfig]
    var sound: AlarmSound
    /// Playback volume (0.0–1.0).
    var volume: Float
    var gradualWakeDuration: GradualWakeDuration
    var snooze: SnoozeConfig
    var wakeCheck: WakeCheckConfig
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        label: String = "",
        wallClockTime: AlarmTime = AlarmTime(hour: 7, minute: 0),
        recurrence: AlarmRecurrence = .daily,
        missions: [MissionConfig] = [.defaultMath],
        sound: AlarmSound = .default,
        volume: Float = 1.0,
        gradualWakeDuration: GradualWakeDuration = .off,
        snooze: SnoozeConfig = .default,
        wakeCheck: WakeCheckConfig = .off,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.label = label
        self.wallClockTime = wallClockTime
        self.recurrence = recurrence
        self.missions = missions
        self.sound = sound
        self.volume = volume
        self.gradualWakeDuration = gradualWakeDuration
        self.snooze = snooze
        self.wakeCheck = wakeCheck
        self.isEnabled = isEnabled
    }
}

// MARK: - Weekday

enum Weekday: Int, Codable, CaseIterable, Sendable, Hashable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    /// The full name, for anywhere the abbreviation is not enough — VoiceOver
    /// especially, where the day circles show a single letter and Tuesday and
    /// Thursday are both "T".
    var displayName: String {
        switch self {
        case .sunday:    return String(localized: "Sunday", comment: "Weekday")
        case .monday:    return String(localized: "Monday", comment: "Weekday")
        case .tuesday:   return String(localized: "Tuesday", comment: "Weekday")
        case .wednesday: return String(localized: "Wednesday", comment: "Weekday")
        case .thursday:  return String(localized: "Thursday", comment: "Weekday")
        case .friday:    return String(localized: "Friday", comment: "Weekday")
        case .saturday:  return String(localized: "Saturday", comment: "Weekday")
        }
    }

    var shortName: String {
        switch self {
        case .sunday:    return String(localized: "Sun", comment: "Weekday abbreviation")
        case .monday:    return String(localized: "Mon", comment: "Weekday abbreviation")
        case .tuesday:   return String(localized: "Tue", comment: "Weekday abbreviation")
        case .wednesday: return String(localized: "Wed", comment: "Weekday abbreviation")
        case .thursday:  return String(localized: "Thu", comment: "Weekday abbreviation")
        case .friday:    return String(localized: "Fri", comment: "Weekday abbreviation")
        case .saturday:  return String(localized: "Sat", comment: "Weekday abbreviation")
        }
    }
}

// MARK: - Codable (custom for v1 → v2 migration)

extension Alarm: Codable {
    private enum CodingKeys: String, CodingKey {
        // v2 keys
        case id, label, wallClockTime, recurrence, sound, volume
        case gradualWakeDuration, missions, snooze, wakeCheck, isEnabled
        // v1 legacy keys (see AlarmSchemaV1)
        case time, repeatDays, missionType, isSnoozeEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self,            forKey: .id)
        label         = try c.decode(String.self,          forKey: .label)
        // Time and recurrence are the two fields v1 spelled differently. A record
        // carrying neither spelling is genuinely unreadable, so the v1 read is left
        // to throw — the envelope isolates that to the one alarm.
        if let time = try? c.decode(AlarmTime.self, forKey: .wallClockTime) {
            wallClockTime = time
        } else {
            wallClockTime = AlarmSchemaV1.wallClockTime(from: try c.decode(Date.self, forKey: .time))
        }

        if let value = try? c.decode(AlarmRecurrence.self, forKey: .recurrence) {
            recurrence = value
        } else {
            recurrence = AlarmSchemaV1.recurrence(
                fromRepeatDays: (try? c.decode(Set<Weekday>.self, forKey: .repeatDays)) ?? [],
                wallClockTime: wallClockTime
            )
        }
        sound         = (try? c.decode(AlarmSound.self,    forKey: .sound))  ?? .default
        // Legacy alarms could be saved at 0 — clamp up so they pass AlarmManager.validate
        // (minimum 0.3) and are actually audible.
        volume        = max(AlarmManager.minimumVolume, (try? c.decode(Float.self, forKey: .volume)) ?? 1.0)
        gradualWakeDuration = (try? c.decode(GradualWakeDuration.self, forKey: .gradualWakeDuration)) ?? .off
        isEnabled     = try c.decode(Bool.self,            forKey: .isEnabled)

        // Missions: prefer v2, fall back to v1 missionType
        if let ms = try? c.decode([MissionConfig].self, forKey: .missions) {
            missions = ms
        } else if let legacy = try? c.decode(AlarmSchemaV1.MissionType.self, forKey: .missionType) {
            missions = [legacy.migrated]
        } else {
            missions = [.defaultMath]
        }

        // Snooze: prefer v2, fall back to v1 isSnoozeEnabled
        if let s = try? c.decode(SnoozeConfig.self, forKey: .snooze) {
            snooze = s
        } else if let enabled = try? c.decode(Bool.self, forKey: .isSnoozeEnabled) {
            snooze = enabled ? .default : .off
        } else {
            snooze = .default
        }

        wakeCheck = (try? c.decode(WakeCheckConfig.self, forKey: .wakeCheck)) ?? .off
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                  forKey: .id)
        try c.encode(label,               forKey: .label)
        try c.encode(wallClockTime,       forKey: .wallClockTime)
        try c.encode(recurrence,          forKey: .recurrence)
        try c.encode(sound,               forKey: .sound)
        try c.encode(volume,              forKey: .volume)
        try c.encode(gradualWakeDuration, forKey: .gradualWakeDuration)
        try c.encode(missions,            forKey: .missions)
        try c.encode(snooze,              forKey: .snooze)
        try c.encode(wakeCheck,           forKey: .wakeCheck)
        try c.encode(isEnabled,           forKey: .isEnabled)
    }
}

// MARK: - Test alarm

extension Alarm {
    /// Transient alarm used by "Test alarm (30 s)". It is never written to the
    /// repository; the ring screen resolves it from `ReArmRegistry` (kind `.test`).
    static func testAlarm(id: UUID, sound: AlarmSound = .default) -> Alarm {
        Alarm(
            id: id,
            label: String(localized: "Test alarm", comment: "Test alarm label"),
            wallClockTime: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: .now)
                return AlarmTime(hour: c.hour ?? 7, minute: c.minute ?? 0)
            }(),
            recurrence: .oneTime(date: AlarmDate(from: .now)),
            missions: [.math(difficulty: .easy, rounds: 1)],
            sound: sound,
            volume: 1.0,
            snooze: .off,
            wakeCheck: .off,
            isEnabled: true
        )
    }
}

// MARK: - Samples

extension Alarm {
    static let samples: [Alarm] = [
        Alarm(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            label: "Wake up",
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .repeating(days: [.monday, .tuesday, .wednesday, .thursday, .friday]),
            missions: [.defaultMath, .defaultShake],
            sound: .default,
            snooze: .default,
            isEnabled: true
        ),
        Alarm(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            label: "Weekend",
            wallClockTime: AlarmTime(hour: 9, minute: 0),
            recurrence: .repeating(days: [.saturday, .sunday]),
            missions: [.defaultShake],
            sound: .default,
            snooze: .off,
            isEnabled: false
        ),
    ]
}
