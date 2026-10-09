import Foundation
import Testing
@testable import MorningCompanion

/// A repeatable generator, so the boxes move the same way every run.
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

@Suite("Which box?")
@MainActor
struct BoxGameTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func playing(seed: UInt64 = 3) -> BoxGame {
        let game = BoxGame(generator: SplitMix(state: seed))
        game.start(at: t0)
        return game
    }

    /// Ticks from `from` until the boxes wait for a guess; returns the time then.
    @discardableResult
    private func untilGuessing(_ game: BoxGame, from: Date) -> Date {
        var now = from
        for _ in 0..<5000 where game.step != .guessing {
            now = now.addingTimeInterval(1.0 / 60.0)
            game.tick(at: now)
        }
        return now
    }

    /// Ticks through a reveal to the next round.
    private func pastReveal(_ game: BoxGame, from: Date) -> Date {
        let now = from.addingTimeInterval(BoxGame.missedLength + 0.05)
        game.tick(at: now)
        return now
    }

    @Test("A round shows, hides, shuffles and then waits for a guess")
    func script() {
        let game = playing()
        guard case .showing = game.step else { Issue.record("not showing"); return }
        #expect(game.count == 3)
        #expect(game.swaps.count == BoxGame.swapCount(forScore: 0))
        untilGuessing(game, from: t0)
        #expect(game.step == .guessing)
    }

    @Test("The cat is where the swaps took its box")
    func tracking() {
        for seed in 1...20 as ClosedRange<UInt64> {
            let game = playing(seed: seed)
            let expected = BoxGame.apply(game.swaps, to: Array(0..<game.count))[game.catBox]
            untilGuessing(game, from: t0)
            #expect(game.catPlace == expected)
        }
    }

    @Test("Mid-swap, the two boxes are on their way, one in front and one behind")
    func midSwap() {
        let game = playing()
        // Through showing and hiding into the first swap.
        var now = t0
        while true {
            now = now.addingTimeInterval(0.01)
            game.tick(at: now)
            if case .shuffling = game.step { break }
        }
        let halfway = now.addingTimeInterval(game.swapLength / 2)
        let spots = game.layout(at: halfway)
        let swap = game.swaps[0]
        let moving = spots.filter { $0.arc != 0 }
        #expect(moving.count == 2)
        #expect(moving.allSatisfy { abs($0.place - CGFloat(swap.a + swap.b) / 2) < 0.01 })
        #expect(Set(moving.map { $0.arc > 0 }) == [true, false])
    }

    @Test("Every swap moves two different places, and the cat's box is in most of them")
    func swapsAreReal() {
        let game = playing()
        #expect(game.swaps.allSatisfy { $0.a != $0.b })
        var catAt = game.places[game.catBox]
        var withCat = 0
        for swap in game.swaps {
            if swap.a == catAt || swap.b == catAt { withCat += 1 }
            if catAt == swap.a { catAt = swap.b } else if catAt == swap.b { catAt = swap.a }
        }
        #expect(withCat * 2 >= game.swaps.count)
    }

    @Test("The right box scores; a tap before the guess does nothing")
    func rightBox() {
        let game = playing()
        #expect(game.choose(box: game.catBox, at: t0) == nil)
        let now = untilGuessing(game, from: t0)
        #expect(game.choose(box: game.catBox, at: now) == true)
        #expect(game.score == 1)
        #expect(game.lives == BoxGame.startingLives)
        // Only one guess a round.
        #expect(game.choose(box: game.catBox, at: now) == nil)
    }

    @Test("Three wrong boxes and the game is over")
    func threeMisses() {
        let game = playing()
        var now = t0
        for miss in 1...3 {
            now = untilGuessing(game, from: now)
            let wrong = (game.catBox + 1) % game.count
            #expect(game.choose(box: wrong, at: now) == false)
            #expect(game.lives == BoxGame.startingLives - miss)
            now = pastReveal(game, from: now)
        }
        #expect(game.phase == .over)
    }

    @Test("Finds add boxes and speed")
    func harder() {
        #expect(BoxGame.boxes(forScore: 3) == 3)
        #expect(BoxGame.boxes(forScore: 4) == 4)
        #expect(BoxGame.boxes(forScore: 9) == 5)
        #expect(BoxGame.swapLength(forScore: 10) < BoxGame.swapLength(forScore: 0))
        #expect(BoxGame.swapLength(forScore: 100) == 0.2)
        #expect(BoxGame.swapCount(forScore: 100) == 14)

        let game = playing()
        var now = t0
        for _ in 0..<4 {
            now = untilGuessing(game, from: now)
            game.choose(box: game.catBox, at: now)
            now = pastReveal(game, from: now)
        }
        #expect(game.score == 4)
        #expect(game.count == 4)
        #expect(game.places == [0, 1, 2, 3])
    }

    @Test("The best score is kept only when beaten")
    func record() {
        let defaults = UserDefaults(suiteName: "box-tests-\(UUID().uuidString)")!
        #expect(BoxGameRecord.submit(5, in: defaults))
        #expect(!BoxGameRecord.submit(2, in: defaults))
        #expect(BoxGameRecord.best(in: defaults) == 5)
    }
}
