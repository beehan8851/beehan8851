import Testing
import Foundation
@testable import MorningCompanion

/// The streak rules as the app states them: one increment per day, a missed
/// *scheduled* morning resets, a day with no alarm is rest and does not, best is a
/// high-water mark, history is kept for about thirteen months.
@Suite("StreakManager")
@MainActor
struct StreakManagerTests {

    // MARK: - Fixtures

    /// A fixed Gregorian calendar in UTC so "today" never moves under the tests.
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }()

    /// Wednesday 2026-09-09, 07:15 UTC.
    private static let wednesday = Date(timeIntervalSince1970: 1_788_938_100)

    private func day(_ offset: Int, from base: Date = wednesday) -> Date {
        Self.calendar.date(byAdding: .day, value: offset, to: base)!
    }

    private func makeManager(storage: InMemoryStorageService = InMemoryStorageService()) -> StreakManager {
        StreakManager(storage: storage, calendar: Self.calendar, now: { Self.wednesday })
    }

    private func weekdayAlarm() -> Alarm {
        Alarm(recurrence: .repeating(days: [.monday, .tuesday, .wednesday, .thursday, .friday]))
    }

    // MARK: - Increment

    @Test("First completion starts a streak of one")
    func firstCompletion() {
        let manager = makeManager()
        manager.recordCompletion()
        #expect(manager.record.currentStreak == 1)
        #expect(manager.record.bestStreak == 1)
        #expect(manager.record.isCompleted(Self.wednesday, calendar: Self.calendar))
    }

    @Test("Consecutive days increment")
    func consecutiveDays() {
        let manager = makeManager()
        manager.recordCompletion(on: day(-2))
        manager.recordCompletion(on: day(-1))
        manager.recordCompletion(on: day(0))
        #expect(manager.record.currentStreak == 3)
        #expect(manager.record.bestStreak == 3)
    }

    @Test("The same day cannot be counted twice")
    func sameDayIdempotent() {
        let manager = makeManager()
        manager.recordCompletion(on: day(0))
        manager.recordCompletion(on: day(0).addingTimeInterval(3600))
        #expect(manager.record.currentStreak == 1)
        #expect(manager.record.completedDates.count == 1)
    }

    // MARK: - Missed and rest days

    @Test("A gap with no schedule information resets the streak (strict rule)")
    func gapWithoutScheduleResets() {
        let manager = makeManager()
        manager.recordCompletion(on: day(-3))
        manager.recordCompletion(on: day(-2))
        manager.recordCompletion(on: day(0)) // day(-1) skipped, nobody says it was rest
        #expect(manager.record.currentStreak == 1)
        #expect(manager.record.bestStreak == 2)
    }

    @Test("A skipped day with an alarm is a miss")
    func missedScheduledDayResets() {
        let manager = makeManager()
        manager.recordCompletion(on: day(-3), hadAlarm: { _ in true })
        manager.recordCompletion(on: day(-2), hadAlarm: { _ in true })
        manager.recordCompletion(on: day(0), hadAlarm: { _ in true })
        #expect(manager.record.currentStreak == 1)
    }

    @Test("A skipped day with no alarm is rest and keeps the streak")
    func restDayKeepsStreak() {
        let manager = makeManager()
        manager.recordCompletion(on: day(-3), hadAlarm: { _ in true })
        manager.recordCompletion(on: day(-2), hadAlarm: { _ in true })
        manager.recordCompletion(on: day(0), hadAlarm: { [cal = Self.calendar, rest = day(-1)] date in
            !cal.isDate(date, inSameDayAs: rest)
        })
        #expect(manager.record.currentStreak == 3)
    }

    @Test("A weekend off does not break a weekday streak")
    func weekendIsRest() {
        // Friday 2026-09-04 → Monday 2026-09-07, alarm Mon–Fri.
        let friday = day(-5), monday = day(-2)
        #expect(Self.calendar.component(.weekday, from: friday) == 6)
        #expect(Self.calendar.component(.weekday, from: monday) == 2)

        let manager = StreakManager(storage: InMemoryStorageService(), calendar: Self.calendar, now: { friday })
        let alarms = [weekdayAlarm()]
        manager.recordCompletion(on: day(-6), hadAlarm: { d in alarms.contains { $0.recurrence.occurs(on: d, calendar: Self.calendar) } })
        manager.recordCompletion(on: friday, hadAlarm: { d in alarms.contains { $0.recurrence.occurs(on: d, calendar: Self.calendar) } })
        manager.recordCompletion(on: monday, hadAlarm: { d in alarms.contains { $0.recurrence.occurs(on: d, calendar: Self.calendar) } })
        #expect(manager.record.currentStreak == 3)
    }

    @Test("recordCompletion(alarms:) judges rest days by enabled alarms only")
    func alarmsConvenienceIgnoresDisabled() {
        let storage = InMemoryStorageService()
        // Seed Monday and Tuesday won; Wednesday is now.
        let seeded = makeManager(storage: storage)
        seeded.recordCompletion(on: day(-2), hadAlarm: { _ in true })

        // Tuesday skipped. A *disabled* daily alarm must not turn it into a miss.
        let manager = makeManager(storage: storage)
        var disabled = Alarm(recurrence: .daily)
        disabled.isEnabled = false
        manager.recordCompletion(alarms: [disabled])
        #expect(manager.record.currentStreak == 2)

        // The same gap with the alarm enabled is a miss.
        let strict = makeManager(storage: InMemoryStorageService())
        strict.recordCompletion(on: day(-2), hadAlarm: { _ in true })
        strict.recordCompletion(alarms: [Alarm(recurrence: .daily)])
        #expect(strict.record.currentStreak == 1)
    }

    @Test("Best streak never decreases")
    func bestIsHighWaterMark() {
        let manager = makeManager()
        for offset in (-6)...(-3) { manager.recordCompletion(on: day(offset), hadAlarm: { _ in true }) }
        #expect(manager.record.bestStreak == 4)
        manager.recordCompletion(on: day(0), hadAlarm: { _ in true }) // two misses
        #expect(manager.record.currentStreak == 1)
        #expect(manager.record.bestStreak == 4)
    }

    // MARK: - Persistence

    @Test("The record survives a new manager on the same storage")
    func persistsAcrossInstances() {
        let storage = InMemoryStorageService()
        let first = makeManager(storage: storage)
        first.recordCompletion(on: day(-1))
        first.recordCompletion(on: day(0))

        let second = makeManager(storage: storage)
        #expect(second.record == first.record)
        #expect(second.record.currentStreak == 2)
    }

    @Test("reload() picks up a record written behind the manager's back")
    func reloadReadsStorage() throws {
        let storage = InMemoryStorageService()
        let manager = makeManager(storage: storage)
        var record = StreakRecord()
        record.currentStreak = 12
        record.bestStreak = 30
        try storage.save(record, key: StorageKeys.streakRecord)
        manager.reload()
        #expect(manager.record.currentStreak == 12)
        #expect(manager.record.bestStreak == 30)
    }

    @Test("History is pruned to the retention window on write")
    func historyPruned() {
        let manager = makeManager()
        let old = day(-(StreakManager.retentionDays + 1))
        let edge = day(-StreakManager.retentionDays)
        manager.recordCompletion(on: old)
        manager.recordCompletion(on: edge)
        manager.recordCompletion(on: day(0))
        #expect(!manager.record.isCompleted(old, calendar: Self.calendar))
        #expect(manager.record.isCompleted(edge, calendar: Self.calendar))
        #expect(manager.record.isCompleted(day(0), calendar: Self.calendar))
        #expect(manager.record.completedDates.count == 2)
    }

    @Test("Seven-day history is oldest to newest and flags completions")
    func sevenDayHistory() {
        let manager = makeManager()
        manager.recordCompletion(on: day(-1))
        manager.recordCompletion(on: day(0))
        let history = manager.sevenDayHistory()
        #expect(history.count == 7)
        #expect(history.map(\.completed) == [false, false, false, false, false, true, true])
        #expect(Self.calendar.isDate(history.last!.date, inSameDayAs: Self.wednesday))
    }

    // MARK: - DayCell

    @Test("currentWeek reads won, missed, rest, today and upcoming")
    func currentWeekOutcomes() {
        // Week of Mon 7 → Sun 13 Sep 2026; today Wednesday 9.
        var record = StreakRecord()
        record.completedDates = [StreakRecord.dateKey(for: day(-2), calendar: Self.calendar)] // Monday won
        let alarms = [weekdayAlarm()] // Tuesday had an alarm and no completion → missed

        let week = DayCell.currentWeek(record: record, alarms: alarms, now: Self.wednesday, calendar: Self.calendar)
        #expect(week.count == 7)
        #expect(Self.calendar.component(.weekday, from: week[0].date) == 2)
        #expect(week.map(\.outcome) == [.won, .missed, .today, .upcoming, .upcoming, .upcoming, .upcoming])
    }

    @Test("currentWeek: a past weekday without an alarm is rest")
    func currentWeekRest() {
        let weekendOnly = Alarm(recurrence: .repeating(days: [.saturday, .sunday]))
        let week = DayCell.currentWeek(record: StreakRecord(), alarms: [weekendOnly], now: Self.wednesday, calendar: Self.calendar)
        #expect(week[0].outcome == .rest)
        #expect(week[1].outcome == .rest)
        #expect(week[2].outcome == .today)
    }

    @Test("currentWeek: a completed today is won, not today")
    func currentWeekTodayWon() {
        var record = StreakRecord()
        record.completedDates = [StreakRecord.dateKey(for: Self.wednesday, calendar: Self.calendar)]
        let week = DayCell.currentWeek(record: record, alarms: [], now: Self.wednesday, calendar: Self.calendar)
        #expect(week[2].outcome == .won)
    }

    @Test("month covers every day and judges them like the week")
    func monthOutcomes() {
        var record = StreakRecord()
        record.completedDates = [
            StreakRecord.dateKey(for: day(-8), calendar: Self.calendar), // Tue 1 Sep
            StreakRecord.dateKey(for: day(-2), calendar: Self.calendar), // Mon 7 Sep
        ]
        let month = DayCell.month(containing: Self.wednesday, record: record, alarms: [weekdayAlarm()], calendar: Self.calendar)
        #expect(month.count == 30)
        #expect(Self.calendar.component(.day, from: month[0].date) == 1)
        #expect(month[0].outcome == .won)      // Tue 1
        #expect(month[1].outcome == .missed)   // Wed 2
        #expect(month[4].outcome == .rest)     // Sat 5
        #expect(month[5].outcome == .rest)     // Sun 6
        #expect(month[6].outcome == .won)      // Mon 7
        #expect(month[7].outcome == .missed)   // Tue 8
        #expect(month[8].outcome == .today)    // Wed 9
        #expect(month[9].outcome == .upcoming) // Thu 10
        #expect(month.last?.outcome == .upcoming)
    }

    @Test("One-time alarms occur only on their date")
    func oneTimeRecurrence() {
        let target = day(-1)
        let c = Self.calendar.dateComponents([.year, .month, .day], from: target)
        let alarm = AlarmRecurrence.oneTime(date: AlarmDate(year: c.year!, month: c.month!, day: c.day!))
        #expect(alarm.occurs(on: target, calendar: Self.calendar))
        #expect(!alarm.occurs(on: day(0), calendar: Self.calendar))
        #expect(AlarmRecurrence.daily.occurs(on: day(0), calendar: Self.calendar))
    }
}
