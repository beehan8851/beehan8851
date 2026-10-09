import SwiftUI

/// What a long streak teaches the cat. Each trick is learned the first time a streak
/// reaches its number of mornings and is kept for good — they follow the best streak,
/// not the current one, so a missed morning takes nothing away. Most show when the
/// cat is tapped; the last two it wears.
nonisolated enum CatTrick: Int, CaseIterable, Identifiable, Sendable {
    case wave = 3
    case somersault = 7
    case leap = 14
    case sparkle = 30
    case collar = 60
    case medal = 100

    var id: Int { rawValue }
    /// Mornings in a row to learn it.
    var days: Int { rawValue }

    var name: String {
        switch self {
        case .wave: String(localized: "Wave", comment: "Cat trick: it waves when tapped")
        case .somersault: String(localized: "Somersault", comment: "Cat trick: a somersault every few taps")
        case .leap: String(localized: "Big leap", comment: "Cat trick: a high jump every few taps")
        case .sparkle: String(localized: "Sparkles", comment: "Cat trick: sparkles when tapped")
        case .collar: String(localized: "Collar and bell", comment: "Cat trick: the cat wears a collar with a bell")
        case .medal: String(localized: "Gold medal", comment: "Cat trick: the cat wears a gold medal")
        }
    }

    var detail: String {
        switch self {
        case .wave: String(localized: "Tap the cat and it waves back.", comment: "Cat trick detail: wave")
        case .somersault: String(localized: "Every fourth tap, a somersault.", comment: "Cat trick detail: somersault")
        case .leap: String(localized: "Every third tap, a jump twice as high.", comment: "Cat trick detail: big leap")
        case .sparkle: String(localized: "Every tap leaves a few sparkles.", comment: "Cat trick detail: sparkles")
        case .collar: String(localized: "A collar with a yolk bell, everywhere the cat goes.", comment: "Cat trick detail: collar")
        case .medal: String(localized: "A gold medal on its collar, for a hundred mornings.", comment: "Cat trick detail: medal")
        }
    }

    /// The first trick not learned yet with a best streak of `best`.
    static func next(afterBest best: Int) -> CatTrick? {
        allCases.first { $0.days > best }
    }
}

/// The tricks the cat knows, as the views need them.
struct CatTricks: Equatable, Sendable {
    var best = 0

    func knows(_ trick: CatTrick) -> Bool { best >= trick.days }

    var dressing: CatDressing {
        knows(.medal) ? .medal : (knows(.collar) ? .collar : .none)
    }
}

extension EnvironmentValues {
    /// Set once, at the root, from the best streak.
    @Entry var catTricks = CatTricks()
}

extension View {
    /// Teaches every cat inside what `best` mornings in a row have earned.
    func catTricks(best: Int) -> some View {
        let tricks = CatTricks(best: best)
        return environment(\.catTricks, tricks).environment(\.catDressing, tricks.dressing)
    }
}

/// A few sparkles flung out from the cat on a tap: the 30-morning trick. Each burst
/// is drawn from its own start time, so taps in quick succession overlap.
struct SparkleBurst: View {
    let trigger: Int
    var ground: CatMascot.Ground = .light

    @State private var bursts: [(id: Int, start: Date)] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let length: TimeInterval = 0.7
    /// Directions, as angles in degrees, and how far each goes as a share of the width.
    private static let rays: [(angle: Double, reach: CGFloat, size: CGFloat)] = [
        (-150, 0.62, 9), (-100, 0.58, 12), (-55, 0.66, 8), (-15, 0.56, 10), (-125, 0.4, 6)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: bursts.isEmpty)) { context in
            Canvas { g, size in
                // From the edge of the head outwards: never across the face.
                let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
                let start = size.width * 0.3
                for burst in bursts {
                    let p = context.date.timeIntervalSince(burst.start) / Self.length
                    guard p >= 0, p < 1 else { continue }
                    let out = CGFloat(1 - pow(1 - p, 3))
                    let fade = 1 - p * p
                    for (i, ray) in Self.rays.enumerated() {
                        let angle = (ray.angle + Double(burst.id % 3) * 9 + Double(i)) * .pi / 180
                        let r = start + (size.width * ray.reach - start) * out
                        let c = CGPoint(x: center.x + CGFloat(cos(angle)) * r, y: center.y + CGFloat(sin(angle)) * r)
                        CatArt.drawSparkle(&g, center: c, radius: ray.size * (0.6 + 0.4 * out),
                                           color: CatArt.Palette.sparkle(on: ground).opacity(fade))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, value in
            guard !reduceMotion else { return }
            let now = Date.now
            bursts = bursts.filter { now.timeIntervalSince($0.start) < Self.length } + [(value, now)]
        }
    }
}
