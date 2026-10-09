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

@Suite("Catch the cat")
@MainActor
struct CatchGameTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func playing() -> CatchGame {
        let game = CatchGame(generator: SplitMix(state: 42))
        game.start(at: t0)
        return game
    }

    @Test("A catch scores and moves the cat")
    func catchScores() {
        let game = playing()
        let before = game.position
        #expect(game.catchCat(at: t0.addingTimeInterval(0.5)) == 1)
        #expect(game.score == 1)
        #expect(game.combo == 1)
        #expect(game.position != before)
        #expect(game.jumps == 1)
    }

    @Test("After five in a row every catch counts double")
    func combo() {
        let game = playing()
        for i in 0..<5 { game.catchCat(at: t0.addingTimeInterval(Double(i) * 0.2)) }
        #expect(game.score == 5)
        #expect(game.catchCat(at: t0.addingTimeInterval(1.2)) == 2)
        #expect(game.score == 7)
        #expect(game.isOnCombo)
    }

    @Test("A miss costs the combo, not the score")
    func missResetsCombo() {
        let game = playing()
        game.catchCat(at: t0.addingTimeInterval(0.2))
        game.catchCat(at: t0.addingTimeInterval(0.4))
        game.miss(at: t0.addingTimeInterval(0.6))
        #expect(game.combo == 0)
        #expect(game.score == 2)
        #expect(game.bestCombo == 2)
    }

    @Test("A miss startles the cat into a new spot, briefly")
    func missStartles() {
        let game = playing()
        let before = game.position
        let at = t0.addingTimeInterval(0.3)
        game.miss(at: at)
        #expect(game.position != before)
        #expect(game.jumps == 1)
        #expect(game.isStartled(at: at.addingTimeInterval(0.1)))
        #expect(!game.isStartled(at: at.addingTimeInterval(CatchGame.startleLength + 0.01)))
        // A catch calms it at once.
        game.miss(at: t0.addingTimeInterval(1))
        game.catchCat(at: t0.addingTimeInterval(1.1))
        #expect(!game.isStartled(at: t0.addingTimeInterval(1.2)))
    }

    @Test("A fright resets the cat's stay, so it does not bolt twice at once")
    func missResetsStay() {
        let game = playing()
        let at = t0.addingTimeInterval(game.stayDuration - 0.05)
        game.miss(at: at)
        game.tick(at: at.addingTimeInterval(0.1))
        #expect(game.jumps == 1)
    }

    @Test("A cat left alone jumps away and breaks the run")
    func escapes() {
        let game = playing()
        game.catchCat(at: t0.addingTimeInterval(0.1))
        let jumps = game.jumps
        game.tick(at: t0.addingTimeInterval(0.1 + game.stayDuration + 0.01))
        #expect(game.jumps == jumps + 1)
        #expect(game.combo == 0)
    }

    @Test("It gets quicker, down to a floor")
    func speedsUp() {
        let game = playing()
        let first = game.stayDuration
        for i in 0..<60 { game.catchCat(at: t0.addingTimeInterval(Double(i) * 0.1)) }
        #expect(game.stayDuration < first)
        #expect(game.stayDuration >= 0.55)
    }

    @Test("The round ends at thirty seconds and stops scoring")
    func ends() {
        let game = playing()
        game.tick(at: t0.addingTimeInterval(30.01))
        #expect(game.phase == .over)
        #expect(game.catchCat(at: t0.addingTimeInterval(30.5)) == 0)
    }

    @Test("The cat stays on the board")
    func staysInside() {
        let game = playing()
        for i in 0..<200 {
            game.catchCat(at: t0.addingTimeInterval(Double(i) * 0.05))
            #expect((0.12...0.88).contains(game.position.x))
            #expect((0.12...0.88).contains(game.position.y))
        }
    }

    @Test("Only a better score becomes the record")
    func record() {
        let defaults = UserDefaults(suiteName: "catch-tests-\(UUID().uuidString)")!
        #expect(CatchGameRecord.submit(12, in: defaults))
        #expect(!CatchGameRecord.submit(9, in: defaults))
        #expect(CatchGameRecord.best(in: defaults) == 12)
    }
}
