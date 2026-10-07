import Testing
import Foundation
@testable import MorningCompanion

// Reference context:
// Jan 7 2025 06:00:00 UTC — a Tuesday (Weekday.tuesday rawValue=3, Calendar.weekday=3)
// Jan 1 2025 is a Wednesday → Jan 6=Monday, Jan 7=Tuesday, Jan 8=Wednesday

@Suite("NextAlarmCalculator")
struct NextAlarmCalculatorTests {

    private var utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private func makeReference(
        year: Int = 2025, month: Int = 1, day: Int = 7,
        hour: Int = 6, minute: Int = 0
    ) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return utcCalendar.date(from: comps)!
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = 0
        return utcCalendar.date(from: comps)!
    }

    // Scenario 1: disabled alarm → nil regardless of recurrence
    @Test("Disabled alarm returns nil")
    func disabledAlarm() {
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .daily,
            isEnabled: false
        )
        let result = NextAlarmCalculator.nextFireDate(
            for: alarm, after: makeReference(), in: utcCalendar
        )
        #expect(result == nil)
    }

    // Scenario 2: one-time alarm with a future date → returns that date
    @Test("One-time future alarm returns the scheduled date")
    func oneTimeFuture() {
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .oneTime(date: AlarmDate(year: 2025, month: 1, day: 8)),
            isEnabled: true
        )
        let expected = makeDate(year: 2025, month: 1, day: 8, hour: 7, minute: 0)
        let result = NextAlarmCalculator.nextFireDate(
            for: alarm, after: makeReference(), in: utcCalendar
        )
        #expect(result == expected)
    }

    // Scenario 3: one-time alarm in the past → nil
    @Test("One-time past alarm returns nil")
    func oneTimePast() {
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .oneTime(date: AlarmDate(year: 2025, month: 1, day: 6)),
            isEnabled: true
        )
        let result = NextAlarmCalculator.nextFireDate(
            for: alarm, after: makeReference(), in: utcCalendar
        )
        #expect(result == nil)
    }

    // Scenario 4: repeating on today's weekday, fire time is later today → same day
    @Test("Repeating alarm fires later today")
    func repeatingLaterToday() {
        // Reference: Jan 7 (Tuesday) 06:00; alarm fires at 07:00 on Tuesdays
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .repeating(days: [.tuesday]),
            isEnabled: true
        )
        let expected = makeDate(year: 2025, month: 1, day: 7, hour: 7, minute: 0)
        let result = NextAlarmCalculator.nextFireDate(
            for: alarm, after: makeReference(), in: utcCalendar
        )
        #expect(result == expected)
    }

    // Scenario 5: repeating on today's weekday but fire time already past → next occurrence (7 days)
    @Test("Repeating alarm that missed today fires next week")
    func repeatingPastToday() {
        // Reference: Jan 7 (Tuesday) 06:00; alarm fires at 05:00 on Tuesdays → next is Jan 14
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 5, minute: 0),
            recurrence: .repeating(days: [.tuesday]),
            isEnabled: true
        )
        let expected = makeDate(year: 2025, month: 1, day: 14, hour: 5, minute: 0)
        let result = NextAlarmCalculator.nextFireDate(
            for: alarm, after: makeReference(), in: utcCalendar
        )
        #expect(result == expected)
    }

    // Scenario 6: repeating on the next calendar day → tomorrow
    @Test("Repeating alarm on next weekday fires tomorrow")
    func repeatingNextDay() {
        // Reference: Jan 7 (Tuesday) 06:00; alarm fires at 08:00 on Wednesdays → Jan 8
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 8, minute: 0),
            recurrence: .repeating(days: [.wednesday]),
            isEnabled: true
        )
        let expected = makeDate(year: 2025, month: 1, day: 8, hour: 8, minute: 0)
        let result = NextAlarmCalculator.nextFireDate(
            for: alarm, after: makeReference(), in: utcCalendar
        )
        #expect(result == expected)
    }

    // Scenario 7: repeating with empty days set → nil
    @Test("Repeating alarm with empty days returns nil")
    func repeatingEmptyDays() {
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .repeating(days: []),
            isEnabled: true
        )
        let result = NextAlarmCalculator.nextFireDate(
            for: alarm, after: makeReference(), in: utcCalendar
        )
        #expect(result == nil)
    }

    // Scenario 8: daily alarm, fire time later today → today
    @Test("Daily alarm fires later today")
    func dailyLaterToday() {
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 9, minute: 0),
            recurrence: .daily,
            isEnabled: true
        )
        let expected = makeDate(year: 2025, month: 1, day: 7, hour: 9, minute: 0)
        let result = NextAlarmCalculator.nextFireDate(
            for: alarm, after: makeReference(), in: utcCalendar
        )
        #expect(result == expected)
    }

    // Bonus: daily alarm, fire time already passed today → tomorrow
    @Test("Daily alarm fires tomorrow when today's time is past")
    func dailyNextDay() {
        // Reference: Jan 7 06:00; alarm at 05:00 daily → fires Jan 8 at 05:00
        let alarm = Alarm(
            wallClockTime: AlarmTime(hour: 5, minute: 0),
            recurrence: .daily,
            isEnabled: true
        )
        let expected = makeDate(year: 2025, month: 1, day: 8, hour: 5, minute: 0)
        let result = NextAlarmCalculator.nextFireDate(
            for: alarm, after: makeReference(), in: utcCalendar
        )
        #expect(result == expected)
    }
}
