import Foundation

/// "Catch the cat": thirty seconds, a cat that will not sit still. Tap it before it
/// jumps away; every catch makes the next jump come sooner. Five catches in a row
/// start a combo that is worth double. A tap that misses gives the cat a fright: it
/// bolts somewhere else.
///
/// The rules only — no views, no clock of its own. The screen calls `tick(at:)` and
/// reports taps; tests drive it with fixed dates and a seeded generator.
@MainActor
@Observable
final class CatchGame {
    enum Phase: Equatable { case ready, playing, over }

    static var roundLength: TimeInterval {
        #if DEBUG
        if DebugLaunch.slowCat { return 300 }
        #endif
        return 30
    }
    /// Catches in a row before each catch counts double.
    static let comboThreshold = 5

    private(set) var phase: Phase = .ready
    private(set) var score = 0
    /// Catches in a row, without a miss or a cat that got away.
    private(set) var combo = 0
    private(set) var bestCombo = 0
    private(set) var catches = 0
    /// Where the cat sits, 0–1 in both directions of the play area.
    private(set) var position = CGPoint(x: 0.5, y: 0.5)
    /// Counts every jump, so the view can animate each one.
    private(set) var jumps = 0
    /// Until when the cat is still bristling from a missed tap.
    private(set) var startledUntil: Date?
    /// Where the last catch happened and what it was worth, for the "+1".
    private(set) var lastCatch: (point: CGPoint, points: Int, index: Int)?

    private(set) var startedAt: Date?
    private(set) var jumpsAt: Date?
    private var generator: any RandomNumberGenerator

    init(generator: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.generator = generator
    }

    /// How long the cat stays put: generous at first, quick by the end.
    var stayDuration: TimeInterval {
        #if DEBUG
        if DebugLaunch.slowCat { return 60 }
        #endif
        return max(0.55, 1.5 - Double(catches) * 0.045)
    }

    var isOnCombo: Bool { combo >= Self.comboThreshold }

    /// How long a fright lasts.
    static let startleLength: TimeInterval = 0.7

    func isStartled(at now: Date) -> Bool {
        startledUntil.map { now < $0 } ?? false
    }

    func remaining(at now: Date) -> TimeInterval {
        guard let startedAt else { return Self.roundLength }
        return max(0, Self.roundLength - now.timeIntervalSince(startedAt))
    }

    // MARK: - Play

    func start(at now: Date) {
        phase = .playing
        score = 0
        combo = 0
        bestCombo = 0
        catches = 0
        lastCatch = nil
        startledUntil = nil
        startedAt = now
        position = CGPoint(x: 0.5, y: 0.5)
        jumpsAt = now.addingTimeInterval(stayDuration)
    }

    /// The cat was tapped. Returns the points it earned.
    @discardableResult
    func catchCat(at now: Date) -> Int {
        guard phase == .playing, remaining(at: now) > 0 else { return 0 }
        combo += 1
        catches += 1
        startledUntil = nil
        bestCombo = max(bestCombo, combo)
        let points = combo > Self.comboThreshold ? 2 : 1
        score += points
        lastCatch = (position, points, catches)
        jump(at: now)
        return points
    }

    /// A tap that found no cat. The combo is gone, and the cat, startled, bolts
    /// somewhere new; the clock keeps running.
    func miss(at now: Date) {
        guard phase == .playing, remaining(at: now) > 0 else { return }
        combo = 0
        startledUntil = now.addingTimeInterval(Self.startleLength)
        jump(at: now)
    }

    /// Moves time on: the cat jumps when its stay is up, and the round ends at thirty
    /// seconds.
    func tick(at now: Date) {
        guard phase == .playing else { return }
        if remaining(at: now) <= 0 {
            phase = .over
            jumpsAt = nil
            return
        }
        if let jumpsAt, now >= jumpsAt {
            combo = 0
            jump(at: now)
        }
    }

    // MARK: - Moving

    /// Somewhere new, well away from where it was, and never under the screen's edges.
    private func jump(at now: Date) {
        var next = position
        for _ in 0..<12 {
            next = CGPoint(
                x: Double.random(in: 0.12...0.88, using: &generator),
                y: Double.random(in: 0.12...0.88, using: &generator)
            )
            if hypot(next.x - position.x, next.y - position.y) > 0.32 { break }
        }
        position = next
        jumps += 1
        jumpsAt = now.addingTimeInterval(stayDuration)
    }
}

/// The best score, kept on this device.
enum CatchGameRecord {
    private static let key = "com.morningcompanion.game.catch.best"

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
