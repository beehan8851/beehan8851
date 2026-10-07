import Foundation
import Testing
@testable import MorningCompanion

/// A repeatable generator, so crouches last the same every run.
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

@Suite("Laser")
@MainActor
struct LaserGameTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private static let step: TimeInterval = 1.0 / 60.0

    private func playing() -> LaserGame {
        let game = LaserGame(generator: SplitMix(state: 7))
        game.setBoard(CGSize(width: 360, height: 560))
        game.start(at: t0)
        return game
    }

    /// Runs the clock from `from` for `seconds`, calling `each` before every tick.
    @discardableResult
    private func run(_ game: LaserGame, from: TimeInterval, for seconds: TimeInterval,
                     each: (Date) -> Void = { _ in }) -> TimeInterval {
        var t = from
        while t < from + seconds, game.phase == .playing {
            let now = t0.addingTimeInterval(t)
            each(now)
            game.tick(at: now)
            t += Self.step
        }
        return t
    }

    @Test("With no dot the cat sits and waits")
    func waits() {
        let game = playing()
        run(game, from: 0, for: 2)
        #expect(game.cat == .waiting)
        #expect(game.pounces == 0)
    }

    @Test("A dot held still under its nose is caught, and scores nothing")
    func stillDotIsCaught() {
        let game = playing()
        let dot = CGPoint(x: game.strikePoint.x - 40, y: game.strikePoint.y)
        run(game, from: 0, for: 3) { game.pointDot(at: dot, at: $0) }
        #expect(game.pounces >= 1)
        #expect(game.caught >= 1)
        #expect(game.score == 0)
    }

    @Test("A dot that is gone when the paws come down is a point")
    func dodgeScores() {
        let game = playing()
        var dot = CGPoint(x: 100, y: 380)
        var moved = false
        run(game, from: 0, for: 4) { now in
            if case .pouncing = game.cat, !moved {
                dot = CGPoint(x: 300, y: 120)
                moved = true
            }
            game.pointDot(at: dot, at: now)
        }
        #expect(moved)
        #expect(game.dodges >= 1)
        #expect(game.score >= 1)
        #expect(game.caught == 0 || game.dodges >= 1)
    }

    @Test("After three dodges in a row each one counts double")
    func combo() {
        let game = playing()
        let spots = [CGPoint(x: 70, y: 140), CGPoint(x: 290, y: 470)]
        var dot = spots[0]
        var handled = 0
        run(game, from: 0, for: 25) { now in
            if case .pouncing(_, let to, _) = game.cat, handled < game.pounces {
                handled = game.pounces
                // Wherever it is going, be at the other end of the board.
                dot = spots.max { hypot($0.x - to.x, $0.y - to.y) < hypot($1.x - to.x, $1.y - to.y) }!
            }
            if game.dodges < 4 { game.pointDot(at: dot, at: now) } else { game.liftDot() }
        }
        #expect(game.dodges == 4)
        #expect(game.caught == 0)
        #expect(game.score == 5)
        #expect(game.bestCombo == 4)
    }

    @Test("A pounce that lands after the finger lifts is worth nothing")
    func liftMidAir() {
        let game = playing()
        var lifted = false
        run(game, from: 0, for: 4) { now in
            if case .pouncing = game.cat { lifted = true }
            if lifted { game.liftDot() } else { game.pointDot(at: CGPoint(x: 100, y: 380), at: now) }
        }
        #expect(lifted)
        #expect(game.score == 0)
        #expect(game.caught == 0)
        #expect(game.cat == .waiting)
    }

    @Test("A dot in a corner it cannot reach is not jumped at")
    func outOfReach() {
        let game = playing()
        run(game, from: 0, for: 5) { game.pointDot(at: CGPoint(x: 4, y: 6), at: $0) }
        #expect(game.pounces == 0)
        #expect(game.score == 0)
    }

    @Test("The round is over at thirty seconds")
    func roundEnds() {
        let game = playing()
        run(game, from: 0, for: LaserGame.roundLength + 1)
        #expect(game.phase == .over)
    }

    @Test("The best score is kept only when beaten")
    func record() {
        let defaults = UserDefaults(suiteName: "laser-tests-\(UUID().uuidString)")!
        #expect(LaserGameRecord.submit(4, in: defaults))
        #expect(!LaserGameRecord.submit(3, in: defaults))
        #expect(LaserGameRecord.best(in: defaults) == 4)
    }
}
