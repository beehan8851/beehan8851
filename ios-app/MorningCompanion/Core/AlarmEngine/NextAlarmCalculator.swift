import Foundation

/// Stateless, pure next-fire-date calculator.
///
/// All functions are deterministic: given the same inputs they return the same output.
/// Calendar is injected so tests can control time zone, locale, and DST transitions.
/// This type has zero dependencies on repositories, storage, or AlarmManager.
struct NextAlarmCalculator {

    // MARK: - Public

    /// Returns the next Date this alarm should fire strictly after `reference`,
    /// or nil if the alarm will never fire again.
    ///
    /// Rules:
    /// - Disabled alarm               → nil
    /// - .oneTime alarm in the past   → nil
    /// - .repeating with empty days   → nil
    /// - .daily                       → always returns a future date within 24h
    static func nextFireDate(
        for alarm: Alarm,
        after reference: Date = .now,
        in calendar: Calendar = .current
    ) -> Date? {
        guard alarm.isEnabled else { return nil }
        switch alarm.recurrence {
        case .oneTime(let date):
            return nextOneTimeDate(date: date, time: alarm.wallClockTime, after: reference, calendar: calendar)
        case .repeating(let days):
            guard !days.isEmpty else { return nil }
            return nextRepeatingDate(days: days, time: alarm.wallClockTime, after: reference, calendar: calendar)
        case .daily:
            return nextDailyDate(time: alarm.wallClockTime, after: reference, calendar: calendar)
        }
    }

    // MARK: - Private helpers

    private static func nextOneTimeDate(
        date: AlarmDate, time: AlarmTime,
        after reference: Date, calendar: Calendar
    ) -> Date? {
        var comps = DateComponents()
        comps.year   = date.year
        comps.month  = date.month
        comps.day    = date.day
        comps.hour   = time.hour
        comps.minute = time.minute
        comps.second = 0
        guard let fireDate = calendar.date(from: comps) else { return nil }
        return fireDate > reference ? fireDate : nil
    }

    private static func nextRepeatingDate(
        days: Set<Weekday>, time: AlarmTime,
        after reference: Date, calendar: Calendar
    ) -> Date? {
        // Search up to 8 days to guarantee we hit every possible weekday combination
        for offset in 0..<8 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: reference) else { continue }
            let weekdayInt = calendar.component(.weekday, from: candidate)
            guard let weekday = Weekday(rawValue: weekdayInt), days.contains(weekday) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: candidate)
            comps.hour   = time.hour
            comps.minute = time.minute
            comps.second = 0
            if let fireDate = calendar.date(from: comps), fireDate > reference {
                return fireDate
            }
        }
        return nil
    }

    private static func nextDailyDate(
        time: AlarmTime,
        after reference: Date, calendar: Calendar
    ) -> Date? {
        for offset in 0..<2 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: reference) else { continue }
            var comps = calendar.dateComponents([.year, .month, .day], from: candidate)
            comps.hour   = time.hour
            comps.minute = time.minute
            comps.second = 0
            if let fireDate = calendar.date(from: comps), fireDate > reference {
                return fireDate
            }
        }
        return nil
    }
}
