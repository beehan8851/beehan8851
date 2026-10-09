import Foundation

/// Reading the schema this app shipped before the alarm model was rebuilt.
///
/// Schema v1 stored a bare JSON array under the same UserDefaults key that now holds
/// an `AlarmEnvelope`, and described an alarm with four fields that no longer exist:
///
/// | v1                        | v2                              |
/// |---------------------------|---------------------------------|
/// | `time: Date`              | `wallClockTime: AlarmTime`      |
/// | `repeatDays: Set<Weekday>`| `recurrence: AlarmRecurrence`   |
/// | `missionType: MissionType`| `missions: [MissionConfig]`     |
/// | `isSnoozeEnabled: Bool`   | `snooze: SnoozeConfig`          |
///
/// `Alarm.init(from:)` reads either shape, so nothing above this file needs to know
/// which version it is holding. The one thing that cannot be recovered is intent the
/// old model never recorded — volume, gradual wake and wake checks did not exist, so
/// migrated alarms get the same defaults a new alarm would.
enum AlarmSchemaV1 {

    /// The v1 mission list. Three of these were dropped from the product; an alarm
    /// that used one still has to keep working, so it wakes the user with the
    /// default Math mission rather than with nothing at all.
    enum MissionType: String, Codable {
        case math, shake, qrCode, photo, nfc, walking

        var migrated: MissionConfig {
            switch self {
            case .math:                  return .defaultMath
            case .shake:                 return .defaultShake
            case .qrCode:                return .defaultQR
            case .photo, .nfc, .walking: return .defaultMath
            }
        }
    }

    /// v1 stored an absolute instant; v2 stores the wall-clock time the user chose.
    ///
    /// The instant is read in the device's current calendar, which is the same
    /// calendar that produced it unless the user has moved time zone since. In that
    /// case the reading is the one the clock face showed them last, which is the
    /// intent worth keeping — an alarm is a promise about a clock, not about UTC.
    static func wallClockTime(from instant: Date, calendar: Calendar = .current) -> AlarmTime {
        AlarmTime(from: instant, calendar: calendar)
    }

    /// v1 had no explicit "one time" case: an empty day set simply meant the alarm
    /// was not weekly.
    ///
    /// Such an alarm is migrated to fire at its next occurrence rather than on the
    /// date the old record happens to carry, which is almost always in the past. A
    /// one-time alarm whose date has passed is a silently dead alarm, which for this
    /// app is the worst possible outcome of an upgrade.
    static func recurrence(
        fromRepeatDays days: Set<Weekday>,
        wallClockTime: AlarmTime,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> AlarmRecurrence {
        if days.isEmpty {
            return .oneTime(date: AlarmDate(from: nextOccurrence(of: wallClockTime, after: now, calendar: calendar),
                                            calendar: calendar))
        }
        if days.count == Weekday.allCases.count { return .daily }
        return .repeating(days: days)
    }

    /// Today at that time if it has not passed yet, otherwise tomorrow.
    static func nextOccurrence(
        of time: AlarmTime,
        after now: Date,
        calendar: Calendar = .current
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = time.hour
        components.minute = time.minute
        components.second = 0
        guard let today = calendar.date(from: components) else { return now }
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
