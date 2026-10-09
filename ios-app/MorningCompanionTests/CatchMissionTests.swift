import Foundation
import Testing
@testable import MorningCompanion

/// A repeatable generator, so the cat jumps the same way every run.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite("Catch the cat mission")
@MainActor
struct CatchMissionTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func started(_ required: Int = 3, pages: Int = 1) -> CatchMission {
        let mission = CatchMission(required: required, generator: SplitMix(state: 7))
        mission.pages = pages
        mission.start(at: t0)
        return mission
    }

    @Test("Nothing counts before it starts")
    func notStarted() {
        let mission = CatchMission(required: 3, generator: SplitMix(state: 7))
        #expect(mission.catchCat(at: t0) == false)
        #expect(mission.caught == 0)
    }

    @Test("The required number of catches finishes it, and no more count")
    func finishes() {
        let mission = started(3)
        for i in 1...3 { #expect(mission.catchCat(at: t0.addingTimeInterval(Double(i)))) }
        #expect(mission.isDone)
        #expect(mission.catchCat(at: t0.addingTimeInterval(5)) == false)
        #expect(mission.caught == 3)
        #expect(mission.jumpsAt == nil)
    }

    @Test("A miss does not count; it makes the cat jump, startled")
    func miss() {
        let mission = started()
        mission.miss(at: t0.addingTimeInterval(0.2))
        #expect(mission.caught == 0)
        #expect(mission.jumps == 1)
        #expect(mission.isStartled(at: t0.addingTimeInterval(0.3)))
        #expect(!mission.isStartled(at: t0.addingTimeInterval(1.0)))
    }

    @Test("On a spread every jump crosses the fold")
    func crossesFold() {
        let mission = started(10, pages: 2)
        var page = mission.page
        for i in 1...4 {
            mission.catchCat(at: t0.addingTimeInterval(Double(i)))
            #expect(mission.page != page)
            #expect(mission.crossed)
            page = mission.page
        }
    }

    @Test("On one page the cat stays on it")
    func onePage() {
        let mission = started(10, pages: 1)
        for i in 1...4 {
            mission.catchCat(at: t0.addingTimeInterval(Double(i)))
            #expect(mission.page == 0)
            #expect(!mission.crossed)
        }
    }

    @Test("Folding the phone brings the cat back to the page that is left")
    func folding() {
        let mission = started(10, pages: 2)
        mission.catchCat(at: t0.addingTimeInterval(1))
        #expect(mission.page == 1)
        mission.pages = 1
        #expect(mission.page == 0)
    }

    @Test("Left alone, it jumps when its stay is up")
    func jumpsOnItsOwn() {
        let mission = started()
        mission.tick(at: t0.addingTimeInterval(mission.stayDuration - 0.1))
        #expect(mission.jumps == 0)
        mission.tick(at: t0.addingTimeInterval(mission.stayDuration + 0.01))
        #expect(mission.jumps == 1)
    }

    @Test("It is a premium mission that VoiceOver swaps out")
    func gating() {
        #expect(MissionKind.catchCat.isPremium)
        #expect(MissionCapability.isBlockedByVoiceOver(.catchCat))
        #expect(MissionKind.catchCat.requiresSetup == false)
        #expect(MissionConfig.defaultCatchCat.kind == .catchCat)
        #expect(MissionConfig.defaultCatchCat.isConfigured)
    }
}
