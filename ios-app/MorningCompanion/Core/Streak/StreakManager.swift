import Foundation
import Observation

/// Single write boundary for wake-streak persistence.
///
/// Rules enforced here:
/// - Same calendar day cannot increment the streak twice.
/// - A missed *scheduled* morning resets currentStreak to 1 on the next completion.
///   A day with no alarm is a rest day and does not break the streak — the person
///   who sleeps in on Sunday because they chose to has not failed at anything.
/// - Every seventh morning in a row earns a cover, up to two: a missed morning the
///   cat covers for does not break the streak. Covers are spent only when they are
///   enough for every morning missed; otherwise the streak ends and they are kept.
/// - bestStreak is a high-water mark that never decreases.
/// - completedDates is kept for about thirteen months, enough for the monthly
///   calendar and a year-on-year glance; anything older is dropped on write.
@MainActor
@Observable
final class StreakManager {
    private(set) var record = StreakRecord()

    private let storage: any StorageServiceProtocol
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    /// How far back `completedDates` is kept.
    static let retentionDays = 400

    init(
        storage: any StorageServiceProtocol,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storage = storage
        self.calendar = calendar
        self.now = now
        record = (try? storage.load(key: StorageKeys.streakRecord)) ?? StreakRecord()
    }

    // MARK: - Write

    /// Records a successful mission completion.
    ///
    /// - `date`: pass only in tests; production callers omit it.
    /// - `hadAlarm`: whether a given day had an alarm scheduled. Days in the gap since
    ///   the last completion for which this returns false are rest days and are
    ///   skipped. `nil` treats every day as scheduled, the strict rule.
    func recordCompletion(on date: Date? = nil, hadAlarm: ((Date) -> Bool)? = nil) {
        let completionDate = date ?? now()
        let today = dateKey(for: completionDate)

        guard !record.completedDates.contains(today) else { return }

        // The cat covers what it can before the gap is judged.
        record = record.settled(on: completionDate, calendar: calendar, hadAlarm: hadAlarm)
        if let last = record.lastCompletionDate {
            let missed = StreakRecord.missedScheduledDays(
                between: calendar.startOfDay(for: last),
                and: calendar.startOfDay(for: completionDate),
                calendar: calendar,
                hadAlarm: hadAlarm,
                covered: record.coveredDates
            )
            record.currentStreak = missed.isEmpty ? record.currentStreak + 1 : 1
        } else {
            record.currentStreak = 1
        }

        record.completedDates.insert(today)
        record.lastCompletionDate = calendar.startOfDay(for: completionDate)
        record.bestStreak = max(record.bestStreak, record.currentStreak)
        if record.currentStreak % StreakRecord.coverEvery == 0 {
            record.covers = min(StreakRecord.maxCovers, record.covers + 1)
        }
        pruneHistory(relativeTo: completionDate)

        try? storage.save(record, key: StorageKeys.streakRecord)
    }

    /// Convenience for the app: the rest-day rule judged by the alarms as they are
    /// now. The app keeps no diary of schedule edits, and a morning is not worth one.
    func recordCompletion(alarms: [Alarm]) {
        recordCompletion(hadAlarm: StreakRecord.scheduled(by: alarms, calendar: calendar))
    }

    /// Spends covers on mornings missed since the last win and saves, so the days
    /// read as covered everywhere from now on. Called when the app comes forward.
    /// Returns how many mornings the cat covered for just now.
    @discardableResult
    func settle(on date: Date? = nil, hadAlarm: ((Date) -> Bool)? = nil) -> Int {
        let settled = record.settled(on: date ?? now(), calendar: calendar, hadAlarm: hadAlarm)
        guard settled != record else { return 0 }
        let spent = record.covers - settled.covers
        record = settled
        try? storage.save(record, key: StorageKeys.streakRecord)
        return spent
    }

    func settle(alarms: [Alarm]) {
        settle(hadAlarm: StreakRecord.scheduled(by: alarms, calendar: calendar))
    }

    /// Re-reads the record from storage. For the one caller that writes the record
    /// behind this manager's back: the DEBUG seeding hook.
    func reload() {
        record = (try? storage.load(key: StorageKeys.streakRecord)) ?? StreakRecord()
    }

    // MARK: - Read

    /// Returns 7 days oldest → newest, each flagged with whether it was completed.
    func sevenDayHistory(relativeTo date: Date? = nil) -> [DayCompletion] {
        let ref = calendar.startOfDay(for: date ?? now())
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset - 6, to: ref) else { return nil }
            return DayCompletion(date: day, completed: record.completedDates.contains(dateKey(for: day)))
        }
    }

    // MARK: - Private

    private func pruneHistory(relativeTo date: Date) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: calendar.startOfDay(for: date)) else { return }
        let cutoffKey = dateKey(for: cutoff)
        record.completedDates = record.completedDates.filter { $0 >= cutoffKey }
        record.coveredDates = record.coveredDates.filter { $0 >= cutoffKey }
    }

    private func dateKey(for date: Date) -> String {
        StreakRecord.dateKey(for: date, calendar: calendar)
    }
}
