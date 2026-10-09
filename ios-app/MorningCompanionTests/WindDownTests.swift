import Foundation
import Testing
@testable import MorningCompanion

@Suite("Breath pacer")
struct BreathPacerTests {
    let pacer = BreathPacer()

    @Test("In for four, out for six")
    func phases() {
        #expect(pacer.moment(at: 0).phase == .breatheIn)
        #expect(pacer.moment(at: 3.9).phase == .breatheIn)
        #expect(pacer.moment(at: 4.1).phase == .breatheOut)
        #expect(pacer.moment(at: 9.9).phase == .breatheOut)
        #expect(pacer.moment(at: 10.1).phase == .breatheIn)
    }

    @Test("The breath is continuous across the turns")
    func continuous() {
        for turn in [4.0, 10.0, 14.0] {
            let before = pacer.moment(at: turn - 0.001).breath
            let after = pacer.moment(at: turn + 0.001).breath
            #expect(abs(before - after) < 0.01)
        }
        #expect(abs(pacer.moment(at: 0).breath + 1) < 0.0001, "starts all out")
        #expect(abs(pacer.moment(at: 4).breath - 1) < 0.0001, "full at the top")
    }

    @Test("Every turn gets its own index")
    func indices() {
        #expect(pacer.moment(at: 1).index == 0)
        #expect(pacer.moment(at: 5).index == 1)
        #expect(pacer.moment(at: 11).index == 2)
    }

    @Test("Sessions end on a whole breath")
    func wholeBreaths() {
        #expect(pacer.wholeBreaths(in: 5) == 300)
        #expect(pacer.wholeBreaths(in: 3) == 180)
        #expect(pacer.wholeBreaths(in: 0) == 10)
    }
}

@Suite("Wind-down note")
struct WindDownNoteTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test("In the evening the note is for tomorrow")
    func evening() {
        let morning = WindDownNote.morning(now: date(2, 23), nextAlarm: nil, calendar: calendar)
        #expect(morning == date(3, 0))
    }

    @Test("After midnight it is for the same day")
    func afterMidnight() {
        let morning = WindDownNote.morning(now: date(3, 1), nextAlarm: nil, calendar: calendar)
        #expect(morning == date(3, 0))
    }

    @Test("The next alarm decides when there is one")
    func followsAlarm() {
        let morning = WindDownNote.morning(now: date(2, 23), nextAlarm: date(3, 7), calendar: calendar)
        #expect(morning == date(3, 0))
    }

    @Test("A note joins what is already there")
    func appends() throws {
        let storage = InMemoryStorageService()
        #expect(WindDownNote.park("Call the bank", in: storage, now: date(2, 23), nextAlarm: nil, calendar: calendar))
        #expect(WindDownNote.park("  Gym bag  ", in: storage, now: date(2, 23), nextAlarm: nil, calendar: calendar))
        #expect(!WindDownNote.park("   ", in: storage, now: date(2, 23), nextAlarm: nil, calendar: calendar))
        let key = MorningBriefViewModel.focusStorageKey(for: date(3, 0), calendar: calendar)
        let saved: String = try storage.load(key: key)
        #expect(saved == "Call the bank\nGym bag")
    }
}
