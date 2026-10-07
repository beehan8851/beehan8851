import Foundation

/// Persisted wake-streak data. Encoded to/from UserDefaults via StorageServiceProtocol.
struct StreakRecord: Codable, Sendable, Equatable {
    var currentStreak: Int = 0
    var bestStreak: Int = 0
    /// Start-of-day for the most recent successful mission completion.
    var lastCompletionDate: Date?
    /// Completed dates as "yyyy-MM-dd" strings, kept for about thirteen months.
    var completedDates: Set<String> = []
    /// Times the cat can still cover for a missed morning. One is earned with every
    /// seventh morning in a row, up to `maxCovers`.
    var covers: Int = 0
    /// Mornings the cat covered for, as "yyyy-MM-dd": scheduled, not won, and still
    /// not a break in the streak.
    var coveredDates: Set<String> = []

    /// A cover for every this many mornings in a row.
    static let coverEvery = 7
    /// The most covers kept at once: enough for a bad week, not for a holiday.
    static let maxCovers = 2

    /// Whether the mission was completed on the given calendar day.
    func isCompleted(_ date: Date, calendar: Calendar = .current) -> Bool {
        completedDates.contains(Self.dateKey(for: date, calendar: calendar))
    }

    /// Whether the cat covered for the given calendar day.
    func isCovered(_ date: Date, calendar: Calendar = .current) -> Bool {
        coveredDates.contains(Self.dateKey(for: date, calendar: calendar))
    }

    /// The "yyyy-MM-dd" form `completedDates` is keyed by.
    static func dateKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

extension StreakRecord {
    /// Records written before covers existed have neither key.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentStreak = try c.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        bestStreak = try c.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
        lastCompletionDate = try c.decodeIfPresent(Date.self, forKey: .lastCompletionDate)
        completedDates = try c.decodeIfPresent(Set<String>.self, forKey: .completedDates) ?? []
        covers = try c.decodeIfPresent(Int.self, forKey: .covers) ?? 0
        coveredDates = try c.decodeIfPresent(Set<String>.self, forKey: .coveredDates) ?? []
    }
}

// MARK: - The streak as it stands

extension StreakRecord {
    /// The streak on `date`. The stored count changes only when a mission is
    /// completed, so read on its own it went on showing the old number after a
    /// morning was missed — on Today, in Progress and in the widgets — until the next
    /// win started it again at one. A morning counts as missed once its day is over:
    /// today is still to play for.
    ///
    /// - `hadAlarm`: whether a day was scheduled. A day it says was not is a rest day
    ///   and breaks nothing; nil treats every day as scheduled.
    ///
    /// A missed morning the cat can still cover for does not end it: the covers are
    /// spent (`settled(on:)`), and the streak stands.
    func liveStreak(on date: Date, calendar: Calendar = .current, hadAlarm: ((Date) -> Bool)? = nil) -> Int {
        guard currentStreak > 0, let last = lastCompletionDate else { return 0 }
        let settled = settled(on: date, calendar: calendar, hadAlarm: hadAlarm)
        let missed = Self.missedScheduledDays(between: calendar.startOfDay(for: last),
                                              and: calendar.startOfDay(for: date),
                                              calendar: calendar, hadAlarm: hadAlarm,
                                              covered: settled.coveredDates)
        return missed.isEmpty ? currentStreak : 0
    }

    /// The record with the cat's covers spent on the mornings missed since the last
    /// win, if there are covers enough for all of them. If there are not, the streak
    /// is over and the covers are kept for the next one; nothing changes.
    func settled(on date: Date, calendar: Calendar = .current, hadAlarm: ((Date) -> Bool)? = nil) -> StreakRecord {
        guard currentStreak > 0, let last = lastCompletionDate else { return self }
        let missed = Self.missedScheduledDays(between: calendar.startOfDay(for: last),
                                              and: calendar.startOfDay(for: date),
                                              calendar: calendar, hadAlarm: hadAlarm,
                                              covered: coveredDates)
        guard !missed.isEmpty, missed.count <= covers else { return self }
        var settled = self
        settled.covers -= missed.count
        settled.coveredDates.formUnion(missed.map { Self.dateKey(for: $0, calendar: calendar) })
        return settled
    }

    /// Whether any day strictly between the two had an alarm and so needed a win.
    static func missedScheduledDay(between last: Date, and day: Date, calendar: Calendar,
                                   hadAlarm: ((Date) -> Bool)?) -> Bool {
        !missedScheduledDays(between: last, and: day, calendar: calendar, hadAlarm: hadAlarm).isEmpty
    }

    /// The days strictly between the two that had an alarm and so needed a win, less
    /// those the cat already covered. The days themselves are not checked for wins:
    /// there is none between two consecutive completions.
    static func missedScheduledDays(between last: Date, and day: Date, calendar: Calendar,
                                    hadAlarm: ((Date) -> Bool)?, covered: Set<String> = []) -> [Date] {
        let gap = calendar.dateComponents([.day], from: last, to: day).day ?? 0
        guard gap > 1 else { return [] }
        return (1..<gap).compactMap { offset -> Date? in
            guard let between = calendar.date(byAdding: .day, value: offset, to: last) else { return nil }
            guard hadAlarm?(between) ?? true else { return nil }
            return covered.contains(dateKey(for: between, calendar: calendar)) ? nil : between
        }
    }

    /// The rest-day rule as the alarms stand now: a day was scheduled if an enabled
    /// alarm repeats on it. The app keeps no diary of schedule edits.
    static func scheduled(by alarms: [Alarm], calendar: Calendar = .current) -> (Date) -> Bool {
        { day in alarms.contains { $0.isEnabled && $0.recurrence.occurs(on: day, calendar: calendar) } }
    }
}

/// A single day in a 7-day completion history.
struct DayCompletion: Equatable, Identifiable, Sendable {
    let date: Date
    let completed: Bool
    var id: Date { date }
}
