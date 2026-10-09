import Testing
import Foundation
@testable import MorningCompanion

/// The streak as it is shown: the stored count, unless a scheduled morning has gone
/// by unwon since the last win — in the app, and in a widget whose app has not been
/// opened since.
@Suite("Live streak")
struct LiveStreakTests {

    /// A fixed Gregorian calendar in UTC so "today" never moves under the tests.
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }()

    /// Wednesday 2026-09-09, 07:15 UTC.
    private static let wednesday = Date(timeIntervalSince1970: 1_788_938_100)

    private func day(_ offset: Int) -> Date {
        Self.calendar.date(byAdding: .day, value: offset, to: Self.wednesday)!
    }

    private func record(streak: Int, lastWin offset: Int) -> StreakRecord {
        var record = StreakRecord()
        record.currentStreak = streak
        record.bestStreak = streak
        record.lastCompletionDate = Self.calendar.startOfDay(for: day(offset))
        return record
    }

    private let weekdays = StreakRecord.scheduled(
        by: [Alarm(recurrence: .repeating(days: [.monday, .tuesday, .wednesday, .thursday, .friday]))],
        calendar: LiveStreakTests.calendar
    )

    // MARK: - In the app

    @Test("Won today or yesterday, the streak stands")
    func recentWin() {
        #expect(record(streak: 5, lastWin: 0).liveStreak(on: Self.wednesday, calendar: Self.calendar) == 5)
        #expect(record(streak: 5, lastWin: -1).liveStreak(on: Self.wednesday, calendar: Self.calendar) == 5)
    }

    @Test("A scheduled morning missed since the last win ends it")
    func missedMorning() {
        // Won Monday; Tuesday had an alarm and was not won; it is Wednesday.
        let live = record(streak: 5, lastWin: -2).liveStreak(on: Self.wednesday, calendar: Self.calendar, hadAlarm: weekdays)
        #expect(live == 0)
    }

    @Test("Rest days in between break nothing")
    func restDays() {
        // Won Friday; Saturday and Sunday had no alarm; it is Monday.
        let monday = day(-2)
        let live = record(streak: 5, lastWin: -5).liveStreak(on: monday, calendar: Self.calendar, hadAlarm: weekdays)
        #expect(live == 5)
    }

    @Test("Today is still to play for, even with its alarm gone by")
    func todayNotOver() {
        let evening = Self.wednesday.addingTimeInterval(12 * 3600)
        #expect(record(streak: 5, lastWin: -1).liveStreak(on: evening, calendar: Self.calendar, hadAlarm: weekdays) == 5)
    }

    @Test("Without a schedule, every day counts")
    func strictRule() {
        #expect(record(streak: 5, lastWin: -2).liveStreak(on: Self.wednesday, calendar: Self.calendar) == 0)
    }

    @Test("No streak, nothing to show")
    func noStreak() {
        #expect(StreakRecord().liveStreak(on: Self.wednesday, calendar: Self.calendar) == 0)
    }

    // MARK: - In a widget

    private func snapshot(streak: Int?, lastWin: Int?, scheduled: [Int]?, next: Int? = nil) -> WidgetSharedSnapshot {
        WidgetSharedSnapshot(
            nextAlarmDate: next.map(day),
            streakDays: streak,
            lastWin: lastWin.map { Self.calendar.startOfDay(for: day($0)) },
            scheduledDays: scheduled?.map { Self.calendar.startOfDay(for: day($0)) }
        )
    }

    @Test("A widget keeps the streak while no scheduled day has gone by unwon")
    func widgetStands() {
        // Written Wednesday after the win; Thursday is next. It is Thursday morning.
        let s = snapshot(streak: 5, lastWin: 0, scheduled: [0, 1, 2])
        #expect(s.liveStreak(at: day(1), calendar: Self.calendar) == 5)
    }

    @Test("A widget drops the streak once a scheduled day is over with no new snapshot")
    func widgetDrops() {
        // Written Wednesday after the win; Thursday had an alarm; it is Friday.
        let s = snapshot(streak: 5, lastWin: 0, scheduled: [0, 1, 2])
        #expect(s.liveStreak(at: day(2), calendar: Self.calendar) == 0)
    }

    @Test("A widget counts today's alarm as missed once today is over")
    func widgetSameDayMiss() {
        // Written Wednesday evening, today's alarm missed, last win Tuesday.
        let s = snapshot(streak: 5, lastWin: -1, scheduled: [0, 1])
        #expect(s.liveStreak(at: Self.wednesday.addingTimeInterval(12 * 3600), calendar: Self.calendar) == 5)
        #expect(s.liveStreak(at: day(1), calendar: Self.calendar) == 0)
    }

    @Test("An older snapshot is judged by its next alarm")
    func widgetFallback() {
        let s = snapshot(streak: 5, lastWin: nil, scheduled: nil, next: 1)
        #expect(s.liveStreak(at: day(1), calendar: Self.calendar) == 5)
        #expect(s.liveStreak(at: day(2), calendar: Self.calendar) == 0)
    }
}
