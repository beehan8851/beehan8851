import Foundation

/// Wall-clock hour and minute, independent of calendar and time zone.
/// Represents user intent: "I want to wake at 7:00" not "I want to wake at
/// 2025-01-01T07:00:00Z". Separation from AlarmDate prevents DST bugs in
/// recurring alarms and makes persistence deterministic across time-zone changes.
struct AlarmTime: Codable, Sendable, Equatable {
    let hour: Int    // 0–23
    let minute: Int  // 0–59

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// Reads the hour and minute an instant shows on the local clock.
    ///
    /// Used when an absolute `Date` has to become user intent — reading the v1 alarm
    /// schema, and anywhere a picker hands back a full date.
    init(from date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        hour = components.hour ?? 0
        minute = components.minute ?? 0
    }

    /// Today at this wall-clock time — what a `DatePicker` needs to bind against.
    /// The date part is meaningless and is discarded on the way back in.
    func asDate(on day: Date = .now, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components) ?? day
    }

    /// Formats this wall-clock time for display, respecting the device's
    /// 12h/24h preference via the current Calendar locale.
    var displayString: String {
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        if let date = Calendar.current.date(from: comps) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return String(format: "%02d:%02d", hour, minute)
    }
}

/// Wall-clock calendar date (year/month/day) as user intent, not a UTC instant.
/// Decoupled from Date so that persisted one-time alarms are not affected by
/// time-zone changes between write and read.
struct AlarmDate: Codable, Sendable, Equatable {
    let year: Int
    let month: Int  // 1–12
    let day: Int    // 1–31

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Convenience initializer that decomposes a Date into local calendar components.
    init(from date: Date, calendar: Calendar = .current) {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        year  = comps.year  ?? 1970
        month = comps.month ?? 1
        day   = comps.day   ?? 1
    }
}

/// Defines when an alarm fires relative to its wall-clock time.
enum AlarmRecurrence: Codable, Sendable, Equatable {
    /// Fires once on the given calendar date at the alarm's wall-clock time.
    case oneTime(date: AlarmDate)
    /// Fires every week on the specified weekdays at the alarm's wall-clock time.
    case repeating(days: Set<Weekday>)
    /// Fires every day at the alarm's wall-clock time.
    case daily
}
