import Foundation
import Observation

struct StreakData: Equatable {
    let currentStreak: Int
    let bestStreak: Int
    /// Missed mornings the cat can still cover for.
    let covers: Int
    /// The streak at which the next cover is earned; nil while the cat holds all it can.
    let nextCoverAt: Int?
    /// This week, for the strip and the share card.
    let week: [DayCell]
    /// This month, for the calendar.
    let month: [DayCell]
    /// Mornings won this month.
    let wonThisMonth: Int
    /// Mornings that had an alarm this month, up to and including today.
    let scheduledThisMonth: Int
}

@MainActor
@Observable
final class StreakViewModel {
    var state: FeatureLoadState<StreakData> = .idle

    private let streakManager: StreakManager
    private let alarmManager: AlarmManager
    private let calendar: Calendar
    private let now: () -> Date

    init(streakManager: StreakManager, alarmManager: AlarmManager, calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.streakManager = streakManager
        self.alarmManager = alarmManager
        self.calendar = calendar
        self.now = now
    }

    func load() async {
        if case .idle = state { state = .loading }
        let alarms = (try? await alarmManager.fetchAll()) ?? []
        let now = now()
        let scheduled = StreakRecord.scheduled(by: alarms, calendar: calendar)
        // With any covers due spent, so a covered morning reads as covered.
        let record = streakManager.record.settled(on: now, calendar: calendar, hadAlarm: scheduled)
        state = .loaded(Self.data(record: record, alarms: alarms, now: now, calendar: calendar, hadAlarm: scheduled))
    }

    static func data(record: StreakRecord, alarms: [Alarm], now: Date, calendar: Calendar,
                     hadAlarm: @escaping (Date) -> Bool) -> StreakData {
        let current = record.liveStreak(on: now, calendar: calendar, hadAlarm: hadAlarm)
        let month = DayCell.month(containing: now, record: record, alarms: alarms, calendar: calendar)
        let won = month.filter { $0.outcome == .won }.count
        let scheduled = month.filter { [.won, .missed, .covered].contains($0.outcome) }.count
        let nextCoverAt = record.covers < StreakRecord.maxCovers
            ? (current / StreakRecord.coverEvery + 1) * StreakRecord.coverEvery
            : nil
        return StreakData(
            currentStreak: current,
            bestStreak: record.bestStreak,
            covers: record.covers,
            nextCoverAt: nextCoverAt,
            week: DayCell.currentWeek(record: record, alarms: alarms, now: now, calendar: calendar),
            month: month,
            wonThisMonth: won,
            scheduledThisMonth: scheduled
        )
    }
}
