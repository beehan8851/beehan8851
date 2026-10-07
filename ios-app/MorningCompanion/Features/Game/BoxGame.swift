import CoreGraphics
import Foundation

/// "Which box?": the oldest trick with the most cat-shaped prize. The cat sits in one
/// of a row of boxes, ducks down, the lids close and the boxes change places; tap the
/// one it is in. Every find makes the next round quicker and longer, and in time adds
/// a box. Three wrong boxes and the game is over.
///
/// A round is a script played from timestamps: showing, hiding, the swaps one after
/// another, then the guess and the reveal. The rules only — the screen calls
/// `tick(at:)`, asks `layout(at:)` where each box is, and reports the tap. Tests
/// drive it with fixed dates and a seeded generator.
@MainActor
@Observable
final class BoxGame {
    enum Phase: Equatable { case ready, playing, over }

    enum Step: Equatable {
        /// Lids open, the cat in its box for all to see.
        case showing(until: Date)
        /// The cat ducks, the lids close.
        case hiding(until: Date)
        /// The swaps, one after another from `start`.
        case shuffling(start: Date)
        /// Waiting for a tap.
        case guessing
        /// The chosen box open; on a miss, the cat's too.
        case revealing(chosen: Int, until: Date)
    }

    /// Two places in the row trading boxes.
    struct Swap: Equatable {
        let a: Int
        let b: Int
    }

    static let startingLives = 3
    static let showLength: TimeInterval = 1.1
    static let hideLength: TimeInterval = 0.55
    static let foundLength: TimeInterval = 1.2
    static let missedLength: TimeInterval = 1.7

    private(set) var phase: Phase = .ready
    private(set) var step: Step = .guessing
    private(set) var score = 0
    private(set) var lives = BoxGame.startingLives
    /// Counts rounds, so the view can tell one from the next.
    private(set) var round = 0
    /// How many boxes this round.
    private(set) var count = 3
    /// Where each box is: `places[box]` is its place in the row, 0 at the left.
    private(set) var places: [Int] = [0, 1, 2]
    /// The box the cat is in. Boxes keep their number however they move.
    private(set) var catBox = 0
    private(set) var swaps: [Swap] = []
    /// How long one swap takes this round.
    private(set) var swapLength: TimeInterval = 0.5
    /// Where the boxes stood before this round's swaps.
    private var startPlaces: [Int] = [0, 1, 2]
    /// The last guess, right or not, for the reveal.
    private(set) var lastGuessRight = false

    private var generator: any RandomNumberGenerator

    init(generator: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.generator = generator
    }

    // MARK: - How hard

    /// Three boxes to begin with, four from the fourth find, five from the ninth.
    static func boxes(forScore score: Int) -> Int {
        score < 4 ? 3 : (score < 9 ? 4 : 5)
    }

    /// More swaps every other find, up to fourteen.
    static func swapCount(forScore score: Int) -> Int {
        min(14, 4 + score / 2)
    }

    /// Half a second a swap at first, a fifth by the end.
    static func swapLength(forScore score: Int) -> TimeInterval {
        #if DEBUG
        if DebugLaunch.slowCat { return 1.5 }
        #endif
        return max(0.2, 0.5 - Double(score) * 0.022)
    }

    var shuffleLength: TimeInterval { Double(swaps.count) * swapLength }

    /// The place the cat's box is in, once the swaps are done.
    var catPlace: Int { places[catBox] }

    // MARK: - Play

    func start(at now: Date) {
        phase = .playing
        score = 0
        lives = Self.startingLives
        round = 0
        nextRound(at: now)
    }

    /// The tap. Returns whether it found the cat, or nil when it is not the time.
    @discardableResult
    func choose(box: Int, at now: Date) -> Bool? {
        guard phase == .playing, step == .guessing, (0..<count).contains(box) else { return nil }
        let right = box == catBox
        lastGuessRight = right
        if right {
            score += 1
        } else {
            lives -= 1
        }
        step = .revealing(chosen: box, until: now.addingTimeInterval(right ? Self.foundLength : Self.missedLength))
        return right
    }

    /// Moves the script on.
    func tick(at now: Date) {
        guard phase == .playing else { return }
        switch step {
        case .showing(let until):
            if now >= until { step = .hiding(until: now.addingTimeInterval(Self.hideLength)) }
        case .hiding(let until):
            if now >= until { step = .shuffling(start: now) }
        case .shuffling(let start):
            if now.timeIntervalSince(start) >= shuffleLength {
                places = Self.apply(swaps, to: startPlaces)
                step = .guessing
            }
        case .guessing:
            break
        case .revealing(_, let until):
            guard now >= until else { break }
            if lives <= 0 {
                phase = .over
            } else {
                nextRound(at: now)
            }
        }
    }

    // MARK: - Where the boxes are

    /// One box's place at a moment: `place` along the row, fractional mid-swap, and
    /// `arc` −1…1, how far it has swung out of line — below the row (in front) when
    /// positive, above it (behind) when negative.
    struct Spot: Equatable {
        var place: CGFloat
        var arc: CGFloat
    }

    func layout(at now: Date) -> [Spot] {
        guard case .shuffling(let start) = step, swapLength > 0 else {
            return places.map { Spot(place: CGFloat($0), arc: 0) }
        }
        let elapsed = max(0, now.timeIntervalSince(start))
        let done = min(swaps.count, Int(elapsed / swapLength))
        let settled = Self.apply(Array(swaps.prefix(done)), to: startPlaces)
        guard done < swaps.count else {
            return settled.map { Spot(place: CGFloat($0), arc: 0) }
        }
        let swap = swaps[done]
        let p = (elapsed - Double(done) * swapLength) / swapLength
        let eased = CGFloat(0.5 - 0.5 * cos(.pi * p))
        let swing = CGFloat(sin(.pi * p))
        return settled.map { place in
            if place == swap.a {
                return Spot(place: CGFloat(swap.a) + CGFloat(swap.b - swap.a) * eased, arc: swing)
            }
            if place == swap.b {
                return Spot(place: CGFloat(swap.b) + CGFloat(swap.a - swap.b) * eased, arc: -swing)
            }
            return Spot(place: CGFloat(place), arc: 0)
        }
    }

    /// Which swap is under way, counting from 1; 0 when none is. For a tick of feel
    /// at each one.
    func swapNumber(at now: Date) -> Int {
        guard case .shuffling(let start) = step, swapLength > 0 else { return 0 }
        let done = Int(max(0, now.timeIntervalSince(start)) / swapLength)
        return done < swaps.count ? done + 1 : 0
    }

    static func apply(_ swaps: [Swap], to places: [Int]) -> [Int] {
        var places = places
        for swap in swaps {
            for box in places.indices {
                if places[box] == swap.a { places[box] = swap.b } else if places[box] == swap.b { places[box] = swap.a }
            }
        }
        return places
    }

    // MARK: - Setting a round

    private func nextRound(at now: Date) {
        round += 1
        count = Self.boxes(forScore: score)
        places = Array(0..<count)
        startPlaces = places
        catBox = Int.random(in: 0..<count, using: &generator)
        swapLength = Self.swapLength(forScore: score)
        swaps = makeSwaps(Self.swapCount(forScore: score))
        step = .showing(until: now.addingTimeInterval(Self.showLength))
    }

    /// Random pairs of places, the cat's box in at least every other one — a shuffle
    /// that leaves the cat alone is no shuffle — and never the same pair twice running.
    private func makeSwaps(_ n: Int) -> [Swap] {
        var result: [Swap] = []
        var catAt = places[catBox]
        for i in 0..<n {
            var swap: Swap
            repeat {
                let a: Int
                if i % 2 == 0 || Bool.random(using: &generator) {
                    a = catAt
                } else {
                    a = Int.random(in: 0..<count, using: &generator)
                }
                var b = Int.random(in: 0..<(count - 1), using: &generator)
                if b >= a { b += 1 }
                swap = Swap(a: min(a, b), b: max(a, b))
            } while swap == result.last
            if catAt == swap.a { catAt = swap.b } else if catAt == swap.b { catAt = swap.a }
            result.append(swap)
        }
        return result
    }
}

/// The best score, kept on this device.
enum BoxGameRecord {
    private static let key = "com.morningcompanion.game.box.best"

    static func best(in defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: key)
    }

    /// Stores `score` if it beats the record. Returns whether it did.
    @discardableResult
    static func submit(_ score: Int, in defaults: UserDefaults = .standard) -> Bool {
        guard score > best(in: defaults) else { return false }
        defaults.set(score, forKey: key)
        return true
    }
}
