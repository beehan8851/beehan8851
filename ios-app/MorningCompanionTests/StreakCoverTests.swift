import Testing
import Foundation
@testable import MorningCompanion

/// Covers: one for every seventh morning in a row, two at most; a missed scheduled
/// morning the cat covers for does not end the streak, in the app or in a widget.
/// And the tricks long streaks teach, and the game of the day.
@Suite("Streak covers and tricks")
@MainActor
struct StreakCoverTests {

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

    private func manager(_ storage: InMemoryStorageService = InMemoryStorageService(), now offset: Int = 0) -> StreakManager {
        let now = day(offset)
        return StreakManager(storage: storage, calendar: Self.calendar, now: { now })
    }

    /// Every day has an alarm: the strict rule.
    private let everyDay: (Date) -> Bool = { _ in true }

    /// Wins `count` days in a row, ending `endingAt` days from Wednesday.
    private func win(_ m: StreakManager, days count: Int, endingAt end: Int) {
        for offset in (end - count + 1)...end {
            m.recordCompletion(on: day(offset), hadAlarm: everyDay)
        }
    }

    // MARK: - Earning

    @Test("The seventh morning in a row earns a cover, the fourteenth another, and no more than two")
    func earning() {
        let m = manager()
        win(m, days: 6, endingAt: -30)
        #expect(m.record.covers == 0)
        m.recordCompletion(on: day(-29), hadAlarm: everyDay)
        #expect(m.record.currentStreak == 7)
        #expect(m.record.covers == 1)
        win(m, days: 7, endingAt: -22)
        #expect(m.record.covers == 2)
        win(m, days: 7, endingAt: -15)
        #expect(m.record.currentStreak == 21)
        #expect(m.record.covers == StreakRecord.maxCovers)
    }

    // MARK: - Spending

    @Test("A missed morning with a cover keeps the streak, and the next win carries on from it")
    func coveredMiss() {
        let storage = InMemoryStorageService()
        let m = manager(storage)
        win(m, days: 7, endingAt: -3)          // Sun…Sat… a week, one cover
        #expect(m.record.covers == 1)
        // Missed day -2 (scheduled); it is day -1, so day -2 is over.
        #expect(m.record.liveStreak(on: day(-1), calendar: Self.calendar, hadAlarm: everyDay) == 7)
        m.recordCompletion(on: day(-1), hadAlarm: everyDay)
        #expect(m.record.currentStreak == 8)
        #expect(m.record.covers == 0)
        #expect(m.record.isCovered(day(-2), calendar: Self.calendar))
    }

    @Test("More misses than covers end the streak, and the covers are kept for the next one")
    func tooManyMisses() {
        let m = manager()
        win(m, days: 7, endingAt: -4)
        #expect(m.record.covers == 1)
        // Days -3 and -2 missed: two misses, one cover.
        #expect(m.record.liveStreak(on: day(-1), calendar: Self.calendar, hadAlarm: everyDay) == 0)
        m.recordCompletion(on: day(-1), hadAlarm: everyDay)
        #expect(m.record.currentStreak == 1)
        #expect(m.record.covers == 1)
        #expect(m.record.coveredDates.isEmpty)
    }

    @Test("Rest days need no cover")
    func restDaysFree() {
        let m = manager()
        win(m, days: 7, endingAt: -4)
        let onlyToday: (Date) -> Bool = { _ in false }
        m.recordCompletion(on: day(-1), hadAlarm: onlyToday)
        #expect(m.record.currentStreak == 8)
        #expect(m.record.covers == 1)
    }

    @Test("Settling spends covers once, saves, and reads the same after")
    func settle() throws {
        let storage = InMemoryStorageService()
        let m = manager(storage, now: -1)
        win(m, days: 7, endingAt: -3)
        #expect(m.settle(hadAlarm: everyDay) == 1)
        #expect(m.settle(hadAlarm: everyDay) == 0)
        let saved: StreakRecord = try storage.load(key: StorageKeys.streakRecord)
        #expect(saved.covers == 0)
        #expect(saved.isCovered(day(-2), calendar: Self.calendar))
        #expect(saved.liveStreak(on: day(-1), calendar: Self.calendar, hadAlarm: everyDay) == 7)
    }

    @Test("A covered day shows as covered in the week")
    func weekShowsCover() {
        let m = manager()
        win(m, days: 7, endingAt: -3)
        let settled = m.record.settled(on: day(0), calendar: Self.calendar, hadAlarm: everyDay)
        // Day -2 and day -1 both missed with one cover: not covered; the streak is over.
        #expect(settled.coveredDates.isEmpty)
        let earlier = m.record.settled(on: day(-1), calendar: Self.calendar, hadAlarm: everyDay)
        let week = DayCell.currentWeek(record: earlier, alarms: [Alarm(recurrence: .daily)],
                                       now: day(-1), calendar: Self.calendar)
        #expect(week.first { Self.calendar.isDate($0.date, inSameDayAs: day(-2)) }?.outcome == .covered)
    }

    @Test("Records saved before covers existed still load")
    func legacyDecode() throws {
        let json = #"{"currentStreak":4,"bestStreak":9,"completedDates":["2026-09-08"]}"#
        let record = try JSONDecoder().decode(StreakRecord.self, from: Data(json.utf8))
        #expect(record.currentStreak == 4)
        #expect(record.covers == 0)
        #expect(record.coveredDates.isEmpty)
    }

    // MARK: - In a widget

    @Test("A widget keeps the streak while the cat's covers last")
    func widgetCovers() {
        let start = Self.calendar.startOfDay(for: day(-3))
        let snapshot = WidgetSharedSnapshot(
            streakDays: 7, lastWin: start,
            scheduledDays: [-3, -2, -1, 0].map { Self.calendar.startOfDay(for: day($0)) },
            covers: 1
        )
        // Day -2 missed, one cover: stands. Day -1 missed too: two misses, over.
        #expect(snapshot.liveStreak(at: day(-1), calendar: Self.calendar) == 7)
        #expect(snapshot.liveStreak(at: day(0), calendar: Self.calendar) == 0)
    }

    // MARK: - Tricks

    @Test("Tricks follow the best streak, and the next is the first not learned")
    func tricks() {
        let tricks = CatTricks(best: 14)
        #expect(tricks.knows(.wave))
        #expect(tricks.knows(.leap))
        #expect(!tricks.knows(.sparkle))
        #expect(tricks.dressing == .none)
        #expect(CatTricks(best: 60).dressing == .collar)
        #expect(CatTricks(best: 250).dressing == .medal)
        #expect(CatTrick.next(afterBest: 0) == .wave)
        #expect(CatTrick.next(afterBest: 7) == .leap)
        #expect(CatTrick.next(afterBest: 100) == nil)
    }

    @Test("The streak page says when the next cover comes, until the cat holds two")
    func nextCover() {
        var record = StreakRecord()
        record.currentStreak = 9
        record.bestStreak = 9
        record.lastCompletionDate = Self.calendar.startOfDay(for: day(0))
        record.covers = 1
        let data = StreakViewModel.data(record: record, alarms: [], now: day(0), calendar: Self.calendar, hadAlarm: everyDay)
        #expect(data.nextCoverAt == 14)
        record.covers = 2
        let full = StreakViewModel.data(record: record, alarms: [], now: day(0), calendar: Self.calendar, hadAlarm: everyDay)
        #expect(full.nextCoverAt == nil)
    }

    // MARK: - Game of the day

    @Test("Today's game changes every day and comes round again")
    func gameOfTheDay() {
        let count = MorningGame.allCases.count
        let games = (0...count).map { MorningGame.ofTheDay(day($0), calendar: Self.calendar) }
        #expect(Set(games.prefix(count)).count == count)
        #expect(games[0] == games[count])
    }
}
