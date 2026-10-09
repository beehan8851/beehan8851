import CoreGraphics
import Foundation

/// "Laser": thirty seconds of the oldest game there is. A finger on the board is a
/// laser dot; the cat runs after it, drops into a crouch when it is close, and
/// pounces at where the dot is heading. Every pounce that lands on nothing is a
/// point; three in a row and each one counts double. A pounce that lands on the dot
/// is the cat's: no point, the run is over, and it sits on its catch for a moment.
///
/// Lift the finger and the dot is gone: the cat sits and looks for it, and a pounce
/// already in the air lands on nothing worth a point. The cat gets quicker, crouches
/// for less and reaches further with every point, so a dot that only runs in a
/// straight line is soon caught.
///
/// The rules only. The board is in points; the screen sets its size, calls
/// `tick(at:)` and reports the finger. Tests drive it with fixed dates and a seeded
/// generator.
@MainActor
@Observable
final class LaserGame {
    enum Phase: Equatable { case ready, playing, over }

    enum Cat: Equatable {
        /// No dot: sitting, looking about.
        case waiting
        /// Running after the dot.
        case chasing
        /// Low, rump up, about to go.
        case crouching(until: Date)
        /// In the air from `from` to `to`.
        case pouncing(from: CGPoint, to: CGPoint, start: Date)
        /// Down again. `caught`: on the dot.
        case landed(caught: Bool, until: Date)
    }

    static var roundLength: TimeInterval {
        #if DEBUG
        if DebugLaunch.slowCat { return 300 }
        #endif
        return 30
    }
    /// Dodges in a row before each one counts double.
    static let comboThreshold = 3
    /// Time in the air.
    static let flight: TimeInterval = 0.3
    /// How close the dot must be for the cat to stop running and crouch.
    static let pounceRange: CGFloat = 170
    /// The longest pounce; a dot further than this when it springs is out of reach.
    static let longestPounce: CGFloat = 230
    /// The cat drawn side on: half its length and half its height, so it never goes
    /// under an edge.
    static let halfLength: CGFloat = 75
    static let halfHeight: CGFloat = 46
    /// Where the front paws are from the cat's middle when they are out, facing left;
    /// what lands on the dot, or does not.
    static let paws = CGVector(dx: -56, dy: 34)

    private(set) var phase: Phase = .ready
    private(set) var cat: Cat = .waiting
    private(set) var score = 0
    /// Pounces dodged in a row.
    private(set) var combo = 0
    private(set) var bestCombo = 0
    private(set) var dodges = 0
    /// Times the cat landed on the dot.
    private(set) var caught = 0
    /// The cat's middle, when it is on the ground; mid-pounce see `catPosition(at:)`.
    private(set) var position: CGPoint = .zero
    /// −1 facing left, 1 facing right.
    private(set) var facing: CGFloat = -1
    /// The finger, or nil when it is off the board.
    private(set) var dot: CGPoint?
    /// The dot's velocity in points a second, smoothed over the last few moves.
    private(set) var dotVelocity: CGVector = .zero
    /// Counts every pounce, so the view can play one each time.
    private(set) var pounces = 0
    /// The last dodge and what it was worth, for the "+1".
    private(set) var lastDodge: (point: CGPoint, points: Int, index: Int)?

    private(set) var startedAt: Date?
    private var board: CGSize = CGSize(width: 360, height: 560)
    private var lastMove: (point: CGPoint, at: Date)?
    private var lastTick: Date?
    private var generator: any RandomNumberGenerator

    init(generator: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.generator = generator
    }

    // MARK: - How hard

    /// Running speed, points a second.
    var runSpeed: CGFloat { min(520, 300 + CGFloat(score) * 9) }

    /// How near the landing the dot must be to be caught: generous paws by the end.
    var catchRadius: CGFloat { min(78, 50 + CGFloat(score) * 1.2) }

    /// How long a crouch lasts: never the same twice, so a spring cannot be timed by
    /// counting; shorter as the score climbs.
    private func crouchLength() -> TimeInterval {
        #if DEBUG
        if DebugLaunch.slowCat { return 3 }
        #endif
        let longest = max(0.42, 0.85 - Double(score) * 0.018)
        return Double.random(in: (longest * 0.55)...longest, using: &generator)
    }

    /// How far ahead of the dot the cat aims: at first where the dot is, by the end
    /// where it will be when the paws come down.
    private var lead: TimeInterval { min(Self.flight, 0.12 + Double(score) * 0.012) }

    func remaining(at now: Date) -> TimeInterval {
        guard let startedAt else { return Self.roundLength }
        return max(0, Self.roundLength - now.timeIntervalSince(startedAt))
    }

    var isOnCombo: Bool { combo >= Self.comboThreshold }

    /// Where the cat is drawn at `now`, and how high off the floor, 0–1.
    /// Where its front paws are, facing the way it faces.
    var strikePoint: CGPoint { strike(from: position) }

    func catPosition(at now: Date) -> (point: CGPoint, height: CGFloat) {
        guard case .pouncing(let from, let to, let start) = cat else { return (position, 0) }
        let p = min(max(now.timeIntervalSince(start) / Self.flight, 0), 1)
        let point = CGPoint(x: from.x + (to.x - from.x) * p, y: from.y + (to.y - from.y) * p)
        return (point, CGFloat(sin(.pi * p)))
    }

    // MARK: - Play

    /// The board's size in points. The cat and its landings stay inside it.
    func setBoard(_ size: CGSize) {
        guard size.width > Self.halfLength * 2, size.height > Self.halfHeight * 2 else { return }
        let fresh = phase != .playing && position == .zero
        board = size
        if fresh { position = CGPoint(x: size.width / 2, y: size.height * 0.62) }
        position = clamped(position)
    }

    func start(at now: Date) {
        phase = .playing
        cat = .waiting
        score = 0
        combo = 0
        bestCombo = 0
        dodges = 0
        caught = 0
        lastDodge = nil
        dot = nil
        dotVelocity = .zero
        lastMove = nil
        startedAt = now
        lastTick = now
        position = CGPoint(x: board.width / 2, y: board.height * 0.62)
    }

    /// The finger is on the board at `point`.
    func pointDot(at point: CGPoint, at now: Date) {
        guard phase == .playing else { return }
        let point = CGPoint(x: min(max(point.x, 0), board.width), y: min(max(point.y, 0), board.height))
        if let lastMove {
            let dt = now.timeIntervalSince(lastMove.at)
            if dt > 0.004 {
                let v = CGVector(dx: (point.x - lastMove.point.x) / dt, dy: (point.y - lastMove.point.y) / dt)
                // A light smoothing: a jittery finger should not send the cat's aim about.
                let k: CGFloat = 0.45
                dotVelocity = CGVector(dx: dotVelocity.dx + (v.dx - dotVelocity.dx) * k,
                                       dy: dotVelocity.dy + (v.dy - dotVelocity.dy) * k)
                self.lastMove = (point, now)
            }
        } else {
            dotVelocity = .zero
            lastMove = (point, now)
        }
        dot = point
        if cat == .waiting { cat = .chasing }
    }

    /// The finger is off the board.
    func liftDot() {
        dot = nil
        dotVelocity = .zero
        lastMove = nil
        if case .chasing = cat { cat = .waiting }
        if case .crouching = cat { cat = .waiting }
    }

    /// Moves time on: the cat runs, crouches, springs and lands, and the round ends
    /// at thirty seconds.
    func tick(at now: Date) {
        guard phase == .playing else { return }
        let dt = min(max(now.timeIntervalSince(lastTick ?? now), 0), 0.1)
        lastTick = now
        if remaining(at: now) <= 0 {
            if case .pouncing = cat { land(at: now) }
            phase = .over
            return
        }
        // A dot that has not moved for a while is standing still, whatever the last
        // move's speed was.
        if let lastMove, now.timeIntervalSince(lastMove.at) > 0.08 { dotVelocity = .zero }

        switch cat {
        case .waiting:
            break
        case .chasing:
            guard let dot else { cat = .waiting; break }
            face(dot)
            let paws = strikePoint
            if hypot(dot.x - paws.x, dot.y - paws.y) < Self.pounceRange {
                cat = .crouching(until: now.addingTimeInterval(crouchLength()))
            } else {
                // Run so the paws head for the dot; the middle follows.
                let goal = middle(forPawsAt: dot)
                let dx = goal.x - position.x, dy = goal.y - position.y
                let distance = hypot(dx, dy)
                guard distance > 0.5 else { break }
                let step = min(distance, runSpeed * CGFloat(dt))
                position = clamped(CGPoint(x: position.x + dx / distance * step, y: position.y + dy / distance * step))
            }
        case .crouching(let until):
            guard let dot else { cat = .waiting; break }
            face(dot)
            if now >= until { spring(at: now, towards: dot) }
        case .pouncing(_, _, let start):
            if now.timeIntervalSince(start) >= Self.flight { land(at: now) }
        case .landed(_, let until):
            if now >= until { cat = dot == nil ? .waiting : .chasing }
        }
    }

    // MARK: - Pouncing

    /// Springs at where the dot will be, if it can get there. A dot out of reach is
    /// not jumped at: too far and the cat runs on; against an edge it cannot reach,
    /// it stays down and waits, as a cat does at the edge of a table. Neither gives a
    /// point for a pounce that could never land.
    private func spring(at now: Date, towards dot: CGPoint) {
        let aim = CGPoint(x: dot.x + dotVelocity.dx * lead, y: dot.y + dotVelocity.dy * lead)
        let paws = strikePoint
        guard hypot(aim.x - paws.x, aim.y - paws.y) <= Self.longestPounce else {
            cat = .chasing
            return
        }
        let landing = clamped(middle(forPawsAt: aim))
        let reached = strike(from: landing)
        guard hypot(reached.x - aim.x, reached.y - aim.y) < 12 else {
            cat = .crouching(until: now.addingTimeInterval(0.25))
            return
        }
        cat = .pouncing(from: position, to: landing, start: now)
        pounces += 1
    }

    private func land(at now: Date) {
        guard case .pouncing(_, let to, _) = cat else { return }
        position = to
        let paws = strikePoint
        if let dot, hypot(dot.x - paws.x, dot.y - paws.y) <= catchRadius {
            caught += 1
            combo = 0
            cat = .landed(caught: true, until: now.addingTimeInterval(0.9))
            return
        }
        cat = .landed(caught: false, until: now.addingTimeInterval(0.35))
        // Dodged only if there was a dot to dodge with.
        guard dot != nil else { return }
        combo += 1
        dodges += 1
        bestCombo = max(bestCombo, combo)
        let points = combo > Self.comboThreshold ? 2 : 1
        score += points
        lastDodge = (paws, points, dodges)
    }

    // MARK: - Where

    /// Turns to the dot, but not for a dot nearly straight above or below: a cat
    /// does not spin round for every twitch.
    private func face(_ dot: CGPoint) {
        let dx = dot.x - position.x
        if abs(dx) > 24 { facing = dx < 0 ? -1 : 1 }
    }

    private func strike(from middle: CGPoint) -> CGPoint {
        CGPoint(x: middle.x + Self.paws.dx * -facing, y: middle.y + Self.paws.dy)
    }

    private func middle(forPawsAt paws: CGPoint) -> CGPoint {
        CGPoint(x: paws.x - Self.paws.dx * -facing, y: paws.y - Self.paws.dy)
    }

    private func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, Self.halfLength), board.width - Self.halfLength),
                y: min(max(p.y, Self.halfHeight), board.height - Self.halfHeight))
    }
}

/// The best score, kept on this device.
enum LaserGameRecord {
    private static let key = "com.morningcompanion.game.laser.best"

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
