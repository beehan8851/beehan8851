import Testing
import Foundation
@testable import MorningCompanion

/// The Sleep History merge: one entry per night, a night dated by the morning it
/// ended on, the longer source winning, and each night saying where it came from.
@Suite("DaySleepSummary")
struct DaySleepSummaryTests {

    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Wednesday 2026-09-09 00:00 UTC.
    private static let wednesday = Date(timeIntervalSince1970: 1_788_912_000)

    private func at(dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
        let day = Self.calendar.date(byAdding: .day, value: dayOffset, to: Self.wednesday)!
        return Self.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func session(from start: Date, to end: Date) -> SleepSession {
        var s = SleepSession(startDate: start, soundUsed: .none)
        s.endDate = end
        return s
    }

    @Test("Consecutive nights stay separate even when one starts after midnight")
    func nightsKeyedByWakeDay() {
        // Monday 23:30 → Tuesday 07:00, then Tuesday 00:54 → Wednesday 07:00. Keyed by
        // the evening they started, both would be "Tuesday" and one would vanish.
        let nightEndingTuesday = session(from: at(dayOffset: -2, hour: 23, minute: 30), to: at(dayOffset: -1, hour: 7))
        let nightEndingWednesday = session(from: at(dayOffset: -1, hour: 0, minute: 54), to: at(dayOffset: 0, hour: 7))

        let merged = DaySleepSummary.merge(sessions: [nightEndingTuesday, nightEndingWednesday], healthEntries: [], calendar: Self.calendar)
        #expect(merged.count == 2)
        #expect(merged.map(\.date) == [at(dayOffset: 0, hour: 0), at(dayOffset: -1, hour: 0)])
        #expect(merged.allSatisfy { $0.sourceLabel == "Tracked" })
    }

    @Test("For the same night the longer source wins and keeps its label")
    func longerSourceWins() {
        let local = session(from: at(dayOffset: -1, hour: 23), to: at(dayOffset: 0, hour: 6)) // 7 h
        let health = SleepEntry(date: at(dayOffset: 0, hour: 0), duration: 7.5 * 3600, inBedDuration: 8 * 3600)

        let healthWins = DaySleepSummary.merge(sessions: [local], healthEntries: [health], calendar: Self.calendar)
        #expect(healthWins.count == 1)
        #expect(healthWins[0].duration == 7.5 * 3600)
        #expect(healthWins[0].sourceLabel == "Apple Health")

        let shorterHealth = SleepEntry(date: at(dayOffset: 0, hour: 0), duration: 5 * 3600, inBedDuration: 5 * 3600)
        let localWins = DaySleepSummary.merge(sessions: [local], healthEntries: [shorterHealth], calendar: Self.calendar)
        #expect(localWins[0].duration == TimeInterval(7 * 3600))
        #expect(localWins[0].sourceLabel == "Tracked")
    }

    @Test("An unfinished session is not a night")
    func activeSessionIgnored() {
        let active = SleepSession(startDate: at(dayOffset: -1, hour: 23), soundUsed: .none)
        let merged = DaySleepSummary.merge(sessions: [active], healthEntries: [], calendar: Self.calendar)
        #expect(merged.isEmpty)
    }

    @Test("Newest night first")
    func sortedNewestFirst() {
        let a = session(from: at(dayOffset: -3, hour: 23), to: at(dayOffset: -2, hour: 7))
        let b = session(from: at(dayOffset: -1, hour: 23), to: at(dayOffset: 0, hour: 7))
        let merged = DaySleepSummary.merge(sessions: [a, b], healthEntries: [], calendar: Self.calendar)
        #expect(merged.first?.date == at(dayOffset: 0, hour: 0))
        #expect(merged.last?.date == at(dayOffset: -2, hour: 0))
    }
}
