import SwiftUI

// MARK: - Cat mascot

/// The cat from the app icon, drawn in code so it can say how the night is going:
/// asleep on its moon while an alarm is set, awake when nothing is, pleased after a
/// morning won, unimpressed after a snooze, and insistent while the alarm rings.
///
/// It is never there on its own: every screen that shows it says the same thing in
/// words beside it, and VoiceOver reads only the words.
struct CatMascot: View {
    enum Mood: String, CaseIterable {
        /// Curled on the moon. An alarm is set and it is night.
        case sleeping
        /// Sitting, eyes open. Daytime, or nothing is set yet.
        case awake
        /// Eyes closed in a smile. The morning was won.
        case proud
        /// Half-lidded. The last alarm was snoozed or missed.
        case grumpy
        /// Wide-eyed, paw up, meowing. The alarm is ringing.
        case ringing
        /// Back arched, fur on end, tail like a bottle brush. Something just happened:
        /// the alarm went off, a tap missed it. Never for long.
        case startled
        /// Ears down, tail on the floor, a tear. The streak is gone.
        case sad
        /// Eyes shut, mouth wide, every few seconds. Time to wind down.
        case yawning
    }

    /// What the cat is drawn on. Decides the colour of the zzz, the whiskers and the
    /// little marks around it, so they read on yolk and paper as well as on ink.
    enum Ground { case light, dark }

    var mood: Mood
    /// Nil follows the page: light in the light appearance, dark in the dark one.
    var ground: Ground? = nil
    /// Breathing, blinking, the tail and the zzz. Off under Reduce Motion.
    var animated: Bool = true
    /// The breath from outside, -1 (out) to 1 (in), for a cat that breathes with a
    /// pacer rather than on its own. Only the sleeping cat follows it.
    var breath: Double? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    /// Set while the cat is in the air (`catMotion`): it jumps with its eyes wide open.
    @Environment(\.catEyesWide) private var eyesWide
    /// Set while someone strokes it (`TappableCat`).
    @Environment(\.catPetting) private var petting
    /// What it has earned to wear: set by the app from the best streak.
    @Environment(\.catDressing) private var dressing

    private var resolvedGround: Ground { ground ?? (colorScheme == .dark ? .dark : .light) }

    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    canvas(time: context.date.timeIntervalSinceReferenceDate,
                           petted: petting.amount(at: context.date))
                }
            } else {
                canvas(time: 0.6, petted: petting.isStroking ? 1 : 0)
            }
        }
        .aspectRatio(CatArt.aspectRatio(for: mood), contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func canvas(time: Double, petted: CGFloat) -> some View {
        Canvas { context, size in
            CatArt.draw(mood, ground: resolvedGround, in: &context, size: size, time: time, breath: breath,
                        eyesWide: eyesWide, petted: petted, lean: petting.lean, purrSide: petting.purrSide,
                        dressing: dressing)
        }
    }
}

extension EnvironmentValues {
    /// Whether a sitting cat should be drawn with its eyes wide open — set by
    /// `catMotion` while it is off the ground.
    @Entry var catEyesWide: Bool = false
    @Entry var catPetting = CatPetting()
    @Entry var catDressing: CatDressing = .none
}

/// What the cat wears, earned with long streaks: a collar with a yolk bell, then a
/// gold medal in the bell's place. Only the sitting cat shows it; curled up asleep or
/// standing in a fright, the collar is out of sight.
enum CatDressing: Int, Comparable, Sendable {
    case none, collar, medal
    static func < (a: CatDressing, b: CatDressing) -> Bool { a.rawValue < b.rawValue }
}

/// A stroke, as the drawing needs it: when it began, when the finger lifted, and
/// which side the finger is on. The drawing works out from the clock how far into
/// it the cat is, so the eyes close and open smoothly on every frame — an amount
/// passed in from outside would jump, since the environment is not animated.
struct CatPetting: Equatable {
    var since: Date?
    var released: Date?
    /// Where the finger is across the cat, -1 (its left edge) to 1 (its right).
    var lean: CGFloat = 0
    /// Which side the purr shows on: away from the hand, changing only once the hand
    /// is well over the other side, so a finger near the middle does not flick it
    /// back and forth.
    var purrSide: CGFloat = 1

    mutating func follow(_ lean: CGFloat) {
        self.lean = lean
        if lean > 0.3 { purrSide = -1 } else if lean < -0.3 { purrSide = 1 }
    }

    var isStroking: Bool { since != nil && released == nil }

    /// 0 untouched, 1 eyes shut and leaning in.
    func amount(at now: Date) -> CGFloat {
        guard let since else { return 0 }
        func ease(_ x: Double) -> CGFloat {
            let x = min(max(x, 0), 1)
            return CGFloat(x * x * (3 - 2 * x))
        }
        guard let released else { return ease(now.timeIntervalSince(since) / 0.35) }
        let reached = ease(released.timeIntervalSince(since) / 0.35)
        return reached * (1 - ease(now.timeIntervalSince(released) / 0.5))
    }
}

// MARK: - Drawing

/// The artwork itself, in a fixed design space that `draw` scales to fit. Flat
/// shapes, one shade per surface, no outlines: the same rules the icon's cat
/// follows once its rendering is taken away.
enum CatArt {

    enum Palette {
        static let fur       = Color(artHex: 0xFFFCF8)
        static let furShade  = Color(artHex: 0xEDE5D8)
        static let furDeep   = Color(artHex: 0xD9CDBB)
        static let earInner  = Color(artHex: 0xF7A38E)
        static let nose      = Color(artHex: 0xF08B76)
        static let ink       = Color(artHex: 0x1C1A17)
        static let blush     = Color(artHex: 0xF59A97)
        static let moon      = Color(artHex: 0xFFC629)
        static let moonLight = Color(artHex: 0xFFE27F)
        static let moonShade = Color(artHex: 0xE9A400)
        static let tear      = Color(artHex: 0x9FD3F5)

        /// Marks that sit beside the cat rather than on it: zzz, whiskers, sparkles, taps.
        static func mark(on ground: CatMascot.Ground) -> Color {
            ground == .dark ? .white : ink
        }
        static func sparkle(on ground: CatMascot.Ground) -> Color {
            ground == .dark ? moon : ink
        }
    }

    static func designSize(for mood: CatMascot.Mood) -> CGSize {
        switch mood {
        case .sleeping: CGSize(width: 240, height: 180)
        // Side on, and taller: the fright lines go above the head.
        case .startled: CGSize(width: 250, height: 240)
        default: CGSize(width: 200, height: 222)
        }
    }

    static func aspectRatio(for mood: CatMascot.Mood) -> CGFloat {
        let size = designSize(for: mood)
        return size.width / size.height
    }

    /// How far into a yawn the yawning cat is, 0 to 1: a slow open, a hold, a close,
    /// then a few seconds of nothing. A still drawing (t = 0.6) is mid-yawn.
    static func yawn(at t: Double) -> CGFloat {
        let phase = t.truncatingRemainder(dividingBy: 5.2)
        func ease(_ x: Double) -> CGFloat { CGFloat(x * x * (3 - 2 * x)) }
        switch phase {
        case ..<0.55: return ease(phase / 0.55)
        case ..<1.7: return 1
        case ..<2.3: return 1 - ease((phase - 1.7) / 0.6)
        default: return 0
        }
    }

    /// `petted` 0…1 is how far into being stroked the cat is; `lean` is the side the
    /// hand is on, -1…1. Only the sitting and sleeping cats are ever stroked.
    static func draw(_ mood: CatMascot.Mood, ground: CatMascot.Ground = .dark,
                     in context: inout GraphicsContext, size: CGSize, time t: Double,
                     breath: Double? = nil, eyesWide: Bool = false, petted: CGFloat = 0, lean: CGFloat = 0,
                     purrSide: CGFloat = 1, dressing: CatDressing = .none) {
        let design = designSize(for: mood)
        let k = min(size.width / design.width, size.height / design.height)
        var g = context
        g.translateBy(x: (size.width - design.width * k) / 2, y: (size.height - design.height * k) / 2)
        g.scaleBy(x: k, y: k)
        if mood == .sleeping {
            drawSleeping(&g, ground: ground, t: t, breath: breath, petted: petted, lean: lean)
        } else if mood == .startled {
            drawStartled(&g, ground: ground, t: t)
        } else {
            drawSitting(&g, mood: mood, ground: ground, t: t, eyesWide: eyesWide, petted: petted, lean: lean, purrSide: purrSide,
                        dressing: dressing)
        }
    }

    // MARK: Poses

    private static func drawSleeping(_ g: inout GraphicsContext, ground: CatMascot.Ground, t: Double, breath paced: Double? = nil,
                                     petted: CGFloat = 0, lean: CGFloat = 0) {
        let breath = CGFloat(paced.map { -$0 * 2.2 } ?? sin(t * 2 * .pi / 4.4))

        // Zzz, rising and fading on a loop, behind everything else.
        for i in 0..<3 {
            let phase = (t / 3.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
            let rise = CGFloat(phase) * 24
            let fade = sin(phase * .pi)
            let size = 11 + CGFloat(i) * 4
            let origin = CGPoint(x: 176 + CGFloat(i) * 16, y: 40 - CGFloat(i) * 13 - rise)
            g.draw(
                Text(verbatim: "z").font(.system(size: size, weight: .heavy))
                    .foregroundStyle(Palette.mark(on: ground).opacity((ground == .dark ? 0.8 : 0.5) * fade)),
                at: origin
            )
        }

        // Head, in the bowl of the moon, rising a little with each breath.
        var head = g
        head.translateBy(x: 104, y: 80 + breath * 1.2)
        // Stroked, it nuzzles into the hand without waking.
        head.rotate(by: .degrees(-7 + Double(lean * petted) * 5))
        drawHead(&head, mood: .sleeping, ground: ground, t: t, petted: petted)

        // The moon, in front of the chin.
        var moon = g
        moon.translateBy(x: 124, y: 103)
        moon.rotate(by: .degrees(-15))
        drawMoon(&moon)

        // Tail over the far horn.
        var tail = Path()
        tail.move(to: CGPoint(x: 184, y: 95))
        tail.addCurve(to: CGPoint(x: 207, y: 146), control1: CGPoint(x: 214, y: 96), control2: CGPoint(x: 228, y: 132))
        let tailSway = CGFloat(sin(t * 2 * .pi / 5.2)) * 2
        g.stroke(tail.offsetBy(dx: tailSway, dy: 0), with: .color(Palette.furShade), style: StrokeStyle(lineWidth: 13, lineCap: .round))
        g.stroke(tail.offsetBy(dx: tailSway - 1.2, dy: -1), with: .color(Palette.fur), style: StrokeStyle(lineWidth: 9, lineCap: .round))

        // Paws on the rim.
        drawPaw(&g, center: CGPoint(x: 66, y: 126 + breath * 0.8), size: CGSize(width: 35, height: 24), angle: -22)
        drawPaw(&g, center: CGPoint(x: 156, y: 111 + breath * 0.8), size: CGSize(width: 36, height: 25), angle: -12)

        drawPurr(&g, at: CGPoint(x: 22, y: 64), outwards: -1, strength: petted, t: t, ground: ground)
    }

    private static func drawSitting(_ g: inout GraphicsContext, mood: CatMascot.Mood, ground: CatMascot.Ground, t: Double, eyesWide: Bool = false,
                                    petted: CGFloat = 0, lean: CGFloat = 0, purrSide away: CGFloat = 1,
                                    dressing: CatDressing = .none) {
        let breath = CGFloat(sin(t * 2 * .pi / 3.4))

        // Tail, behind the body, swaying from its root. The ringing cat has its right
        // paw up, so its tail goes to the other side to keep the two apart.
        var tail = g
        let tailRoot = CGPoint(x: mood == .ringing ? 54 : 146, y: 200)
        let sway = mood == .ringing ? sin(t * 2 * .pi / 0.9) * 9 : sin(t * 2 * .pi / 2.8) * 5
        tail.translateBy(x: tailRoot.x, y: tailRoot.y)
        if mood == .ringing { tail.scaleBy(x: -1, y: 1) }
        if mood == .sad {
            // Down on the floor, barely moving.
            tail.rotate(by: .degrees(40 + sway * 0.2))
            tail.scaleBy(x: 0.8, y: 0.8)
        } else {
            tail.rotate(by: .degrees(sway))
        }
        var tailPath = Path()
        tailPath.move(to: .zero)
        tailPath.addCurve(to: CGPoint(x: 30, y: -78), control1: CGPoint(x: 48, y: 0), control2: CGPoint(x: 52, y: -50))
        tail.stroke(tailPath, with: .color(Palette.furShade), style: StrokeStyle(lineWidth: 18, lineCap: .round))
        tail.stroke(tailPath.offsetBy(dx: -2, dy: -1), with: .color(Palette.fur), style: StrokeStyle(lineWidth: 13, lineCap: .round))

        // The ringing cat's raised arm, from behind the body; its paw goes on top later.
        let tap = CGFloat(abs(sin(t * 2 * .pi / 0.62)))
        let pawCenter = CGPoint(x: 174, y: 104 - tap * 8)
        if mood == .ringing {
            var arm = Path()
            arm.move(to: CGPoint(x: 138, y: 160))
            arm.addQuadCurve(to: CGPoint(x: pawCenter.x - 2, y: pawCenter.y + 8), control: CGPoint(x: 172, y: 150))
            g.stroke(arm, with: .color(Palette.furShade), style: StrokeStyle(lineWidth: 22, lineCap: .round))
            g.stroke(arm.offsetBy(dx: -1.5, dy: -1), with: .color(Palette.fur), style: StrokeStyle(lineWidth: 17, lineCap: .round))
        }

        // Body.
        let body = Path.squircle(center: CGPoint(x: 100, y: 166 - breath * 0.6), rx: 57, ry: 46, exponent: 2.3, flare: 0.13)
        g.fill(body, with: .color(Palette.fur))
        g.fill(body.subtracting(body.offsetBy(dx: 8, dy: -7)), with: .color(Palette.furShade))

        // Front paws. The ringing cat has one of them up.
        drawPaw(&g, center: CGPoint(x: 83, y: 207), size: CGSize(width: 29, height: 17), angle: 0)
        if mood != .ringing {
            drawPaw(&g, center: CGPoint(x: 117, y: 207), size: CGSize(width: 29, height: 17), angle: 0)
        }

        // The collar, under the chin: drawn before the head, which overlaps its top.
        if dressing >= .collar {
            var collar = Path()
            collar.move(to: CGPoint(x: 62, y: 146))
            collar.addQuadCurve(to: CGPoint(x: 138, y: 146), control: CGPoint(x: 100, y: 174))
            g.stroke(collar, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        }

        // Head.
        var head = g
        let yawn = mood == .yawning ? yawn(at: t) : 0
        let lift: CGFloat
        let tilt: Double
        switch mood {
        case .proud: lift = -3; tilt = -4
        case .sad: lift = 6; tilt = 4
        case .yawning: lift = -4 * yawn; tilt = -6 * Double(yawn)
        default: lift = 0; tilt = 0
        }
        let wobble: Double = mood == .ringing ? sin(t * 2 * .pi / 0.62) * 2.5 : 0
        // Stroked, it pushes its head into the hand.
        head.translateBy(x: 100 + lean * petted * 3, y: 97 + lift - breath * 1.0)
        head.rotate(by: .degrees(tilt + wobble + Double(lean * petted) * 9))
        drawHead(&head, mood: mood, ground: ground, t: t, eyesWide: eyesWide, petted: petted)

        // What hangs from the collar, over the chin's shadow: a bell, or a medal.
        if dressing >= .collar {
            drawCharm(&g, at: CGPoint(x: 100, y: 165 - breath * 0.6), medal: dressing == .medal)
        }

        // The purr, on the side away from the hand.
        drawPurr(&g, at: CGPoint(x: 100 + away * 62, y: 158), outwards: away, strength: petted, t: t, ground: ground)

        if mood == .ringing {
            // The raised paw, tapping at the glass, with two short strokes for the tap.
            drawPaw(&g, center: pawCenter, size: CGSize(width: 30, height: 28), angle: -12, pads: true)
            for (i, offset) in [CGPoint(x: 22, y: -18), CGPoint(x: 27, y: -2)].enumerated() {
                var mark = Path()
                let start = CGPoint(x: pawCenter.x + offset.x, y: pawCenter.y + offset.y)
                mark.move(to: start)
                mark.addLine(to: CGPoint(x: start.x + 9, y: start.y + (i == 0 ? -6 : 1)))
                g.stroke(mark, with: .color(Palette.sparkle(on: ground).opacity(0.35 + 0.65 * Double(tap))),
                         style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            }
        }

        if mood == .proud {
            drawSparkle(&g, center: CGPoint(x: 168, y: 46), radius: 11, color: Palette.sparkle(on: ground))
            drawSparkle(&g, center: CGPoint(x: 34, y: 72), radius: 6.5, color: Palette.sparkle(on: ground).opacity(0.85))
        }
    }

    /// Side on, facing left, head turned to us: up on stiff legs, back arched into a
    /// hoop, every hair along it and the tail standing on end. The whole cat trembles.
    private static func drawStartled(_ g: inout GraphicsContext, ground: CatMascot.Ground, t: Double) {
        let shiver = CGFloat(sin(t * 2 * .pi * 9)) * 0.9
        g.translateBy(x: shiver, y: 18)
        let bristle = { (i: Int) in CGFloat(sin(t * 2 * .pi * 4 + Double(i) * 2.1)) * 1.5 }

        // Fright lines, fanned over the head and back.
        for (i, mark) in [(CGPoint(x: 18, y: 72), -150.0), (CGPoint(x: 34, y: 46), -120.0), (CGPoint(x: 62, y: 34), -92.0),
                          (CGPoint(x: 92, y: 40), -64.0)].enumerated() {
            let a = mark.1 * .pi / 180
            let length = (i % 2 == 0 ? 14 : 11) * CGFloat(1 + 0.18 * sin(t * 2 * .pi * 3 + Double(i) * 1.3))
            var line = Path()
            line.move(to: mark.0)
            line.addLine(to: CGPoint(x: mark.0.x + cos(a) * length, y: mark.0.y + sin(a) * length))
            g.stroke(line, with: .color(Palette.mark(on: ground).opacity(ground == .dark ? 0.85 : 0.75)),
                     style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }

        // Tail, straight up and fluffed to a bottle brush, fur swept towards the tip.
        let tailCurve = Cubic(CGPoint(x: 196, y: 110), CGPoint(x: 236, y: 98), CGPoint(x: 206, y: 58),
                              CGPoint(x: 226 + shiver * 2, y: 20))
        var tail = tailCurve.path.strokedPath(StrokeStyle(lineWidth: 17, lineCap: .round))
        for i in 0..<9 {
            let u = 0.2 + Double(i) * 0.085
            for side in [-1.0, 1.0] as [CGFloat] {
                tail = tail.union(tailCurve.flame(at: u + (side > 0 ? 0.04 : 0), side: side,
                                                  length: 12 + CGFloat((i + (side > 0 ? 1 : 0)) % 3) * 2.5 + bristle(i) * 0.6,
                                                  halfWidth: 0.055, sweep: 0.07))
            }
        }
        tail = tail.union(tailCurve.flame(at: 0.99, side: 1, length: 9, halfWidth: 0.04, sweep: 0.0, along: 0.6))
        tail = tail.union(tailCurve.flame(at: 0.99, side: -1, length: 9, halfWidth: 0.04, sweep: 0.0, along: 0.6))
        g.fill(tail, with: .color(Palette.furShade))
        g.fill(tail.offsetBy(dx: -2, dy: -1.5).intersection(tail), with: .color(Palette.fur))

        // Legs straight and stiff, thick where they leave the body and tapering to the
        // paws. A leg and its paw are one shape, and the near pair is one shape with the
        // body, so there is no seam where they meet.
        func leg(top: CGPoint, topWidth: CGFloat, foot: CGPoint) -> Path {
            var shape = Path.roundedPolygon([
                CGPoint(x: top.x - topWidth / 2, y: top.y), CGPoint(x: top.x + topWidth / 2, y: top.y),
                CGPoint(x: foot.x + 8, y: foot.y), CGPoint(x: foot.x - 8, y: foot.y),
            ], radius: 7)
            shape = shape.union(Path(ellipseIn: CGRect(x: foot.x - 14, y: foot.y - 5, width: 27, height: 14)))
            return shape
        }
        // The far pair, behind and in shade.
        // The far hind leg starts well inside the body, so it comes out from under the
        // belly with no top edge showing.
        var farHind = Path()
        farHind.move(to: CGPoint(x: 168, y: 104))
        farHind.addCurve(to: CGPoint(x: 173, y: 202), control1: CGPoint(x: 170, y: 140), control2: CGPoint(x: 171, y: 176))
        farHind.addLine(to: CGPoint(x: 188, y: 202))
        farHind.addCurve(to: CGPoint(x: 202, y: 112), control1: CGPoint(x: 190, y: 168), control2: CGPoint(x: 200, y: 140))
        farHind.closeSubpath()
        farHind = farHind.union(Path(ellipseIn: CGRect(x: 166, y: 197, width: 27, height: 14)))
        for far in [leg(top: CGPoint(x: 96, y: 130), topWidth: 26, foot: CGPoint(x: 92, y: 202)), farHind] {
            g.fill(far, with: .color(Palette.furShade))
            g.fill(far.subtracting(far.offsetBy(dx: 4, dy: -4)), with: .color(Palette.furDeep))
        }

        // The body: one hoop from chest to rump, fur standing all along the top.
        let back = Cubic(CGPoint(x: 60, y: 146), CGPoint(x: 58, y: 18), CGPoint(x: 204, y: 8), CGPoint(x: 214, y: 128))
        var body = Path()
        body.move(to: back.p0)
        body.addCurve(to: back.p3, control1: back.c1, control2: back.c2)
        body.addCurve(to: CGPoint(x: 196, y: 158), control1: CGPoint(x: 222, y: 142), control2: CGPoint(x: 212, y: 158))
        body.addCurve(to: CGPoint(x: 90, y: 160), control1: CGPoint(x: 168, y: 96), control2: CGPoint(x: 116, y: 96))
        body.addCurve(to: back.p0, control1: CGPoint(x: 74, y: 170), control2: CGPoint(x: 58, y: 162))
        body.closeSubpath()
        let fringe = [0.0, -3, 2.5, -1.5, 3.5, -2.5, 1, -3.5, 2, -1, 3, -2, 0.5, -2.5, 1.5, -1, 2, -2, 1]
        for (i, jitter) in fringe.enumerated() {
            let u = 0.16 + Double(i) * 0.044
            // Longest at the top of the arch.
            let envelope = CGFloat(sin(.pi * min(1, max(0, (u - 0.1) / 0.9))))
            body = body.union(back.flame(at: u, side: 1, length: 7 + 13 * envelope + CGFloat(jitter) + bristle(i),
                                         halfWidth: 0.03, sweep: 0.032))
        }
        // The near pair, each edge running on from the body's own outline: the front
        // leg's front edge out of the chest, the hind leg's back edge out of the rump.
        var hind = Path()
        hind.move(to: CGPoint(x: 176, y: 126))
        hind.addCurve(to: CGPoint(x: 191, y: 204), control1: CGPoint(x: 184, y: 150), control2: CGPoint(x: 190, y: 180))
        hind.addLine(to: CGPoint(x: 207, y: 204))
        hind.addCurve(to: back.p3, control1: CGPoint(x: 211, y: 178), control2: CGPoint(x: 222, y: 152))
        hind.closeSubpath()
        var fore = Path()
        fore.move(to: CGPoint(x: 90, y: 134))
        fore.addCurve(to: CGPoint(x: 78, y: 204), control1: CGPoint(x: 84, y: 160), control2: CGPoint(x: 79, y: 182))
        fore.addLine(to: CGPoint(x: 62, y: 204))
        fore.addCurve(to: CGPoint(x: 58, y: 148), control1: CGPoint(x: 60, y: 182), control2: CGPoint(x: 55, y: 162))
        fore.closeSubpath()
        body = body.union(hind).union(fore)
        g.fill(body, with: .color(Palette.fur))
        g.fill(body.subtracting(body.offsetBy(dx: 5, dy: -6)), with: .color(Palette.furShade))
        // Paws, toes forward, over the ankles, shaded only underneath.
        for center in [CGPoint(x: 197, y: 208), CGPoint(x: 67, y: 208)] {
            let paw = Path(roundedRect: CGRect(x: center.x - 14, y: center.y - 7, width: 27, height: 13), cornerRadius: 6.5)
            g.fill(paw, with: .color(Palette.fur))
            g.fill(paw.subtracting(paw.offsetBy(dx: 1.5, dy: -3.5)), with: .color(Palette.furShade))
        }
        // Toes.
        for x in [62.0, 69.0, 192.0, 199.0] as [CGFloat] {
            var toe = Path()
            toe.move(to: CGPoint(x: x, y: 214))
            toe.addLine(to: CGPoint(x: x, y: 210))
            g.stroke(toe, with: .color(Palette.furDeep), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }

        // Head low at the front, turned to face us.
        var head = g
        head.translateBy(x: 60, y: 124)
        head.rotate(by: .degrees(-8))
        head.scaleBy(x: 0.64, y: 0.64)
        drawHead(&head, mood: .startled, ground: ground, t: t)
    }

    // MARK: Stretch

    /// The stretch's design space. The hind paws stay put at the right; the front
    /// reaches left as `reach` goes to 1. Wide enough that the far forepaw and the
    /// shadow stay inside it at full reach.
    static let stretchDesignSize = CGSize(width: 364, height: 200)

    /// Side on, facing left, head turned to us: forelegs flat out in front, chest
    /// down, rump up, tail high with a hook at the tip, mid-yawn. The cat a phone
    /// opening wakes. `reach` 0…1 is how far the front has gone; `yawn` 0…1 how
    /// wide the mouth is. `hunting`: the same shape is a cat about to pounce, or
    /// running, or in the air — eyes wide on its prey, no yawn, the tail twitching.
    static func drawStretch(in context: inout GraphicsContext, size: CGSize, ground: CatMascot.Ground,
                            time t: Double, reach: CGFloat, yawn: CGFloat, hunting: Bool = false) {
        let design = stretchDesignSize
        let k = min(size.width / design.width, size.height / design.height)
        var g = context
        g.translateBy(x: (size.width - design.width * k) / 2, y: (size.height - design.height * k) / 2)
        g.scaleBy(x: k, y: k)
        // The pose is drawn from x = 0 at rest; at full reach the far paw goes 14 to the
        // left of that, the shadow 4.
        g.translateBy(x: 20, y: 0)

        let e = 60 * min(max(reach, 0), 1)
        // How far a point moves with the reach: the paws all the way, the rump not at all.
        func front(_ x: CGFloat, _ y: CGFloat, _ share: CGFloat) -> CGPoint { CGPoint(x: x - e * share, y: y) }

        // Its shadow on the floor, from the front paws to the back ones: the stretch
        // happens on whatever page is there, and this is what puts the cat on it.
        let shadowLeft = front(86, 0, 1).x - 30
        g.fill(Path(ellipseIn: CGRect(x: shadowLeft, y: 183, width: 308 - shadowLeft, height: 12)),
               with: .color(ground == .dark ? .black.opacity(0.35) : Palette.ink.opacity(0.1)))

        // Tail, high and hooked, behind everything.
        let sway = hunting ? CGFloat(sin(t * 2 * .pi / 0.45)) * 5 : CGFloat(sin(t * 2 * .pi / 2.6)) * 3
        var tail = Path()
        tail.move(to: CGPoint(x: 290, y: 82))
        tail.addCurve(to: CGPoint(x: 322 + sway, y: 26), control1: CGPoint(x: 318, y: 74), control2: CGPoint(x: 330, y: 46))
        tail.addQuadCurve(to: CGPoint(x: 302 + sway * 1.4, y: 14), control: CGPoint(x: 316 + sway, y: 6))
        g.stroke(tail, with: .color(Palette.furShade), style: StrokeStyle(lineWidth: 17, lineCap: .round, lineJoin: .round))
        g.stroke(tail.offsetBy(dx: -2, dy: -1), with: .color(Palette.fur), style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))

        // Forelegs: flat along the floor from a rounded elbow under the chest, slim at
        // the wrist, a paw at the end a little taller than the wrist.
        func foreleg(dx: CGFloat, dy: CGFloat) -> Path {
            let elbow = front(184 + dx, 178 + dy, 0.42), wrist = front(86 + dx, 181 + dy, 1)
            let floor = 188 + dy
            var leg = Path()
            leg.move(to: CGPoint(x: wrist.x, y: wrist.y - 5))
            leg.addCurve(to: CGPoint(x: elbow.x - 6, y: elbow.y - 16),
                         control1: CGPoint(x: wrist.x + 44, y: wrist.y - 6), control2: CGPoint(x: elbow.x - 44, y: elbow.y - 17))
            leg.addCurve(to: CGPoint(x: elbow.x + 6, y: floor - 3),
                         control1: CGPoint(x: elbow.x + 8, y: elbow.y - 15), control2: CGPoint(x: elbow.x + 12, y: floor - 8))
            leg.addQuadCurve(to: CGPoint(x: elbow.x - 4, y: floor), control: CGPoint(x: elbow.x + 3, y: floor))
            leg.addLine(to: CGPoint(x: wrist.x, y: floor))
            leg.closeSubpath()
            return leg.union(Path(roundedRect: CGRect(x: wrist.x - 24, y: 173 + dy, width: 36, height: 16), cornerRadius: 8))
        }
        // Hind legs: a round thigh tapering to the hock, then nearly straight down.
        func hindleg(dx: CGFloat, dy: CGFloat) -> Path {
            var leg = Path()
            leg.move(to: CGPoint(x: 244 + dx, y: 120 + dy))
            leg.addCurve(to: CGPoint(x: 268 + dx, y: 184 + dy), control1: CGPoint(x: 258 + dx, y: 142 + dy), control2: CGPoint(x: 266 + dx, y: 166 + dy))
            leg.addLine(to: CGPoint(x: 290 + dx, y: 184 + dy))
            leg.addCurve(to: CGPoint(x: 296 + dx, y: 150 + dy), control1: CGPoint(x: 290 + dx, y: 172 + dy), control2: CGPoint(x: 292 + dx, y: 160 + dy))
            leg.addCurve(to: CGPoint(x: 300 + dx, y: 92 + dy), control1: CGPoint(x: 304 + dx, y: 132 + dy), control2: CGPoint(x: 316 + dx, y: 110 + dy))
            leg.closeSubpath()
            return leg
        }
        func hindPaw(dx: CGFloat, dy: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: 262 + dx, y: 174 + dy, width: 34, height: 15), cornerRadius: 7.5)
        }

        // The far pair, behind and in shade.
        for far in [foreleg(dx: -16, dy: -3), hindleg(dx: -18, dy: -2).union(hindPaw(dx: -18, dy: -2))] {
            g.fill(far, with: .color(Palette.furShade))
            g.fill(far.subtracting(far.offsetBy(dx: 4, dy: -4)), with: .color(Palette.furDeep))
        }

        // The body: the nape low at the front, the back dipping then climbing to the
        // rump, the belly drawn long and tight up from a chest held just off the floor.
        let nape = front(150, 120, 0.6)
        let chest = front(182, 172, 0.48)
        var body = Path()
        body.move(to: nape)
        body.addCurve(to: CGPoint(x: 268, y: 60), control1: front(196, 128, 0.35), control2: CGPoint(x: 226, y: 62))
        body.addCurve(to: CGPoint(x: 300, y: 92), control1: CGPoint(x: 288, y: 58), control2: CGPoint(x: 300, y: 72))
        body.addLine(to: CGPoint(x: 248, y: 136))
        body.addCurve(to: chest, control1: CGPoint(x: 230, y: 152), control2: front(212, 170, 0.3))
        body.addCurve(to: nape, control1: front(150, 176, 0.55), control2: front(128, 140, 0.6))
        body.closeSubpath()
        body = body.union(hindleg(dx: 0, dy: 0))
        g.fill(body, with: .color(Palette.fur))
        g.fill(body.subtracting(body.offsetBy(dx: 5, dy: -6)), with: .color(Palette.furShade))

        // The near foreleg and hind paw over the body, shaded only underneath.
        for part in [foreleg(dx: 0, dy: 0), hindPaw(dx: 0, dy: 0)] {
            g.fill(part, with: .color(Palette.fur))
            g.fill(part.subtracting(part.offsetBy(dx: 1.5, dy: -3.5)), with: .color(Palette.furShade))
        }
        // Toes.
        let wrist = front(86, 181, 1)
        for x in [wrist.x - 17, wrist.x - 10, 272, 279] as [CGFloat] {
            var toe = Path()
            toe.move(to: CGPoint(x: x, y: 189))
            toe.addLine(to: CGPoint(x: x, y: 184.5))
            g.stroke(toe, with: .color(Palette.furDeep), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }

        // Head low over the paws, turned to us, chin up into the yawn.
        var head = g
        let headCenter = front(118, 132, 0.72)
        if hunting {
            head.translateBy(x: headCenter.x, y: headCenter.y + 4)
            head.rotate(by: .degrees(-3))
            head.scaleBy(x: 0.62, y: 0.62)
            drawHead(&head, mood: .awake, ground: ground, t: t, eyesWide: true)
            return
        }
        head.translateBy(x: headCenter.x, y: headCenter.y - yawn * 3)
        head.rotate(by: .degrees(-5 - 5 * Double(yawn)))
        head.scaleBy(x: 0.62, y: 0.62)
        drawHead(&head, mood: .yawning, ground: ground, t: t, yawnAmount: yawn)
    }

    // MARK: Head

    /// Ears, head, face, whiskers. Drawn around (0, 0), the middle of the head.
    /// `yawnAmount` holds a yawning face at a given opening instead of running the cycle.
    /// `petted`: being stroked, whatever its mood the cat shuts its eyes, content, and
    /// lets its ears go; a sleeping cat only lets its ears go.
    private static func drawHead(_ g: inout GraphicsContext, mood: CatMascot.Mood, ground: CatMascot.Ground, t: Double, eyesWide: Bool = false,
                                 yawnAmount: CGFloat? = nil, petted: CGFloat = 0) {
        let rx: CGFloat = 72, ry: CGFloat = 55
        let open = mood == .yawning ? (yawnAmount ?? yawn(at: t)) : 0
        // The face it makes: its own until the eyes have closed, then content.
        let face: CatMascot.Mood = petted > 0.5 && !eyesWide && mood != .sleeping ? .proud : mood

        // Ear set: tilted out further when cross, straighter when alert.
        let earTilt: Double
        let earDrop: CGFloat
        switch mood {
        case .grumpy:   earTilt = 34; earDrop = 8
        case .sleeping: earTilt = 30; earDrop = 5
        case .ringing:  earTilt = 8;  earDrop = -4
        // Flattened, as a frightened cat's are.
        case .startled: earTilt = 24; earDrop = 0
        case .sad:      earTilt = 40; earDrop = 6
        case .yawning:  earTilt = 15 + 14 * Double(open); earDrop = 3 * open
        default:       earTilt = 15; earDrop = 0
        }
        let earsLetGo = Double(petted) * 9
        // An occasional twitch of the right ear.
        let twitchPhase = t.truncatingRemainder(dividingBy: 6.5)
        let twitch = twitchPhase < 0.28 ? sin(twitchPhase / 0.28 * .pi) * 9 : 0

        drawEar(&g, base: CGPoint(x: -41, y: -38 + earDrop + petted * 2), tilt: -earTilt - earsLetGo)
        drawEar(&g, base: CGPoint(x: 41, y: -38 + earDrop + petted * 2), tilt: earTilt + earsLetGo + twitch)

        // Whiskers start behind the cheeks.
        for side in [-1.0, 1.0] as [CGFloat] {
            for (dy, reach) in [(CGFloat(-2), CGFloat(-7)), (CGFloat(6), CGFloat(2))] {
                var w = Path()
                w.move(to: CGPoint(x: side * 58, y: 18 + dy))
                w.addQuadCurve(to: CGPoint(x: side * 92, y: 18 + dy + reach),
                               control: CGPoint(x: side * 76, y: 16 + dy))
                g.stroke(w, with: .color(Palette.mark(on: ground).opacity(ground == .dark ? 0.75 : 0.3)),
                         style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }

        let head = Path.squircle(center: .zero, rx: rx, ry: ry, exponent: 2.45, flare: 0.07)
        g.fill(head, with: .color(Palette.fur))
        g.fill(head.subtracting(head.offsetBy(dx: 9, dy: -10)), with: .color(Palette.furShade))

        // Cheeks.
        let blushOpacity = face == .proud || petted > 0.5 ? 0.55 : (face == .sad ? 0.22 : 0.36)
        for x in [-45.0, 45.0] as [CGFloat] {
            g.fill(Path(ellipseIn: CGRect(x: x - 8, y: 17, width: 16, height: 8)),
                   with: .color(Palette.blush.opacity(blushOpacity)))
        }

        drawEyes(&g, mood: face, t: t, wide: eyesWide, yawn: open, squint: min(1, petted * 2))

        if face == .sad && !eyesWide {
            // One tear, welling and running down the cheek, now and then.
            let phase = t.truncatingRemainder(dividingBy: 4.2) / 4.2
            let run = CGFloat(min(1, phase * 1.6))
            let fade = phase < 0.75 ? 1 : max(0, 1 - (phase - 0.75) / 0.2)
            let center = CGPoint(x: -33, y: 18 + run * 16)
            var drop = Path()
            drop.move(to: CGPoint(x: center.x, y: center.y - 7))
            drop.addQuadCurve(to: CGPoint(x: center.x + 4, y: center.y + 1), control: CGPoint(x: center.x + 3.4, y: center.y - 3))
            drop.addArc(center: CGPoint(x: center.x, y: center.y + 1), radius: 4, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            drop.addQuadCurve(to: CGPoint(x: center.x, y: center.y - 7), control: CGPoint(x: center.x - 3.4, y: center.y - 3))
            g.fill(drop, with: .color(Palette.tear.opacity(fade)))
            g.fill(Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 1, width: 1.8, height: 2.4)), with: .color(.white.opacity(0.8 * fade)))
        }

        // Nose.
        let nose = Path.roundedPolygon([CGPoint(x: -5.5, y: 17.5), CGPoint(x: 5.5, y: 17.5), CGPoint(x: 0, y: 24)], radius: 2.2)
        g.fill(nose, with: .color(Palette.nose))

        // Mouth.
        let mouthStyle = StrokeStyle(lineWidth: 2.1, lineCap: .round, lineJoin: .round)
        switch face {
        case .ringing:
            let open = 5.5 + CGFloat(abs(sin(t * 2 * .pi / 0.62))) * 2.5
            let mouth = Path(roundedRect: CGRect(x: -6, y: 26, width: 12, height: open), cornerRadius: 5)
            g.fill(mouth, with: .color(Palette.ink))
            g.fill(Path(ellipseIn: CGRect(x: -3.5, y: 26 + open - 4, width: 7, height: 4)), with: .color(Palette.nose))
        case .startled:
            // Open in a hiss, two little fangs showing.
            let mouth = Path(roundedRect: CGRect(x: -10, y: 27, width: 20, height: 13), cornerRadius: 6.5)
            g.fill(mouth, with: .color(Palette.ink))
            g.fill(Path(ellipseIn: CGRect(x: -5, y: 34.5, width: 10, height: 5)), with: .color(Palette.nose))
            for x in [-5.6, 5.6] as [CGFloat] {
                g.fill(Path.roundedPolygon([CGPoint(x: x - 2.6, y: 27), CGPoint(x: x + 2.6, y: 27), CGPoint(x: x, y: 32.5)], radius: 0.6),
                       with: .color(.white))
            }
        case .sad:
            var mouth = Path()
            mouth.move(to: CGPoint(x: -7, y: 33))
            mouth.addQuadCurve(to: CGPoint(x: 7, y: 33), control: CGPoint(x: 0, y: 26))
            g.stroke(mouth, with: .color(Palette.ink), style: mouthStyle)
        case .yawning:
            if open > 0.08 {
                // Wide open, the tongue showing.
                let width = 10 + 10 * open, height = 4 + 20 * open
                let rect = CGRect(x: -width / 2, y: 25, width: width, height: height)
                g.fill(Path(ellipseIn: rect), with: .color(Palette.ink))
                g.fill(Path(ellipseIn: CGRect(x: -width * 0.32, y: rect.maxY - height * 0.42, width: width * 0.64, height: height * 0.36)),
                       with: .color(Palette.nose))
            } else {
                var mouth = Path()
                mouth.move(to: CGPoint(x: -7, y: 26.5))
                mouth.addQuadCurve(to: CGPoint(x: 0, y: 25.5), control: CGPoint(x: -3.6, y: 32))
                mouth.addQuadCurve(to: CGPoint(x: 7, y: 26.5), control: CGPoint(x: 3.6, y: 32))
                g.stroke(mouth, with: .color(Palette.ink), style: mouthStyle)
            }
        case .grumpy:
            var mouth = Path()
            mouth.move(to: CGPoint(x: -6, y: 31))
            mouth.addQuadCurve(to: CGPoint(x: 6, y: 31), control: CGPoint(x: 0, y: 27.5))
            g.stroke(mouth, with: .color(Palette.ink), style: mouthStyle)
        default:
            var mouth = Path()
            mouth.move(to: CGPoint(x: -7, y: 26.5))
            mouth.addQuadCurve(to: CGPoint(x: 0, y: 25.5), control: CGPoint(x: -3.6, y: 32))
            mouth.addQuadCurve(to: CGPoint(x: 7, y: 26.5), control: CGPoint(x: 3.6, y: 32))
            g.stroke(mouth, with: .color(Palette.ink), style: mouthStyle)
        }
    }

    private static func drawEar(_ g: inout GraphicsContext, base: CGPoint, tilt: Double) {
        var ear = g
        ear.translateBy(x: base.x, y: base.y)
        ear.rotate(by: .degrees(tilt))
        let outer = Path.roundedPolygon([CGPoint(x: -26, y: 12), CGPoint(x: 26, y: 12), CGPoint(x: 2, y: -40)], radius: 9)
        ear.fill(outer, with: .color(Palette.fur))
        let inner = Path.roundedPolygon([CGPoint(x: -14, y: 9), CGPoint(x: 15, y: 9), CGPoint(x: 2, y: -24)], radius: 5)
        ear.fill(inner, with: .color(Palette.earInner))
    }

    /// `squint` 0…1 narrows open eyes towards shut: a cat being stroked, on its way
    /// to closing them.
    private static func drawEyes(_ g: inout GraphicsContext, mood: CatMascot.Mood, t: Double, wide: Bool = false, yawn squeeze: CGFloat = 0,
                                 squint: CGFloat = 0) {
        let eyes = [CGPoint(x: -27, y: 7), CGPoint(x: 27, y: 7)]
        // Mid-jump, whatever the mood: eyes open wide and shining, no blink, no lids.
        if wide {
            for e in eyes {
                g.fill(Path(ellipseIn: CGRect(x: e.x - 8, y: e.y - 10, width: 16, height: 20)), with: .color(Palette.ink))
                g.fill(Path(ellipseIn: CGRect(x: e.x + 3.2 - 3.6, y: e.y - 4.8 - 3.6, width: 7.2, height: 7.2)), with: .color(.white))
                g.fill(Path(ellipseIn: CGRect(x: e.x - 4.4, y: e.y + 2.6, width: 3, height: 3)), with: .color(.white.opacity(0.85)))
            }
            return
        }
        switch mood {
        case .sleeping:
            for e in eyes {
                g.fill(Path.sliver(center: CGPoint(x: e.x, y: e.y + 1), halfWidth: 12.5, sag: 7, thickness: 4.4),
                       with: .color(Palette.ink))
            }
        case .yawning:
            // Shut: drowsy between yawns, pressed flatter at the top of one. The arc
            // only flattens; it never turns over, which would pass through straight.
            for e in eyes {
                g.fill(Path.sliver(center: CGPoint(x: e.x, y: e.y + 2 + squeeze), halfWidth: 12 - squeeze, sag: 6 - 2.5 * squeeze,
                                   thickness: 4.2), with: .color(Palette.ink))
            }
        case .sad:
            // Big and wet, the outer corners drooping.
            for (i, e) in eyes.enumerated() {
                let outer: CGFloat = 3.5, inner: CGFloat = -2.5
                let left = i == 0 ? outer : inner
                let right = i == 0 ? inner : outer
                let lid = Path(CGRect(x: e.x - 12, y: e.y - 20, width: 24, height: 40)).subtracting(
                    Path.roundedPolygon([CGPoint(x: e.x - 14, y: e.y - 20), CGPoint(x: e.x + 14, y: e.y - 20),
                                         CGPoint(x: e.x + 14, y: e.y - 9 + right), CGPoint(x: e.x - 14, y: e.y - 9 + left)], radius: 0.1))
                let eye = Path(ellipseIn: CGRect(x: e.x - 7.5, y: e.y - 8, width: 15, height: 17)).intersection(lid)
                g.fill(eye, with: .color(Palette.ink))
                g.fill(Path(ellipseIn: CGRect(x: e.x + 0.6, y: e.y - 3.4, width: 4.8, height: 4.8)), with: .color(.white))
                g.fill(Path(ellipseIn: CGRect(x: e.x - 4.6, y: e.y + 2.4, width: 3.2, height: 3.2)), with: .color(.white.opacity(0.85)))
                // Brows up in the middle.
                let toNose: CGFloat = i == 0 ? 1 : -1
                var brow = Path()
                brow.move(to: CGPoint(x: e.x - toNose * 8, y: e.y - 13))
                brow.addQuadCurve(to: CGPoint(x: e.x + toNose * 7, y: e.y - 19), control: CGPoint(x: e.x, y: e.y - 14))
                g.stroke(brow, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
        case .proud:
            for e in eyes {
                g.fill(Path.sliver(center: CGPoint(x: e.x, y: e.y + 6), halfWidth: 11.5, sag: -7.5, thickness: 4.4),
                       with: .color(Palette.ink))
            }
        case .startled:
            // Round as coins, small shine, and the brows shot up.
            for e in eyes {
                g.fill(Path(ellipseIn: CGRect(x: e.x - 10.5, y: e.y - 11, width: 21, height: 22)), with: .color(Palette.ink))
                g.fill(Path(ellipseIn: CGRect(x: e.x + 1.4, y: e.y - 6.6, width: 5.6, height: 5.6)), with: .color(.white))
                var brow = Path()
                brow.move(to: CGPoint(x: e.x - 8, y: e.y - 17))
                brow.addQuadCurve(to: CGPoint(x: e.x + 8, y: e.y - 17), control: CGPoint(x: e.x, y: e.y - 24))
                g.stroke(brow, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            }
        case .awake, .ringing, .grumpy:
            let big = mood == .ringing
            let w: CGFloat = big ? 15 : 13
            let h: CGFloat = big ? 18 : 16
            // A blink every few seconds; the ringing cat does not blink.
            let blinkPhase = t.truncatingRemainder(dividingBy: 4.7)
            let blinking: CGFloat = (!big && blinkPhase < 0.16) ? CGFloat(0.12 + 0.88 * abs(blinkPhase / 0.08 - 1)) : 1
            let blink = min(blinking, max(0.12, 1 - squint * 0.88))
            for (i, e) in eyes.enumerated() {
                var eye = Path(ellipseIn: CGRect(x: e.x - w / 2, y: e.y - h / 2 * blink, width: w, height: h * blink))
                if mood == .grumpy {
                    // Upper lids, slanting down towards the nose.
                    let outer: CGFloat = -1.5, inner: CGFloat = 2.5
                    let left = i == 0 ? outer : inner
                    let right = i == 0 ? inner : outer
                    let lid = Path(CGRect(x: e.x - 12, y: e.y - 20, width: 24, height: 40)).subtracting(
                        Path.roundedPolygon([CGPoint(x: e.x - 14, y: e.y - 20), CGPoint(x: e.x + 14, y: e.y - 20),
                                             CGPoint(x: e.x + 14, y: e.y + right), CGPoint(x: e.x - 14, y: e.y + left)], radius: 0.1))
                    eye = eye.intersection(lid)
                }
                g.fill(eye, with: .color(Palette.ink))
                if blink > 0.6 {
                    let hx = e.x + (big ? 2.8 : 2.4)
                    let hy = e.y - (mood == .grumpy ? -1.5 : (big ? 4.2 : 3.6))
                    let r: CGFloat = big ? 3.2 : 2.7
                    g.fill(Path(ellipseIn: CGRect(x: hx - r, y: hy - r, width: r * 2, height: r * 2)), with: .color(.white))
                    if mood != .grumpy {
                        g.fill(Path(ellipseIn: CGRect(x: e.x - 3.8, y: e.y + 2.2, width: 2.6, height: 2.6)),
                               with: .color(.white.opacity(0.8)))
                    }
                }
            }
        }
    }

    // MARK: Parts

    /// Two short arcs beside the cat, opening away from it, that swell with each breath
    /// of the purr: out for a second, a pause, in for less and softer. The same breath
    /// as the sound and the haptic, so with the sound off the purr still shows.
    private static func drawPurr(_ g: inout GraphicsContext, at p: CGPoint, outwards side: CGFloat, strength: CGFloat,
                                 t: Double, ground: CatMascot.Ground) {
        guard strength > 0.02 else { return }
        let b = t.truncatingRemainder(dividingBy: 2.0)
        let breath: Double
        switch b {
        case ..<1.05: breath = sin(.pi * b / 1.05)
        case 1.17..<1.89: breath = 0.55 * sin(.pi * (b - 1.17) / 0.72)
        default: breath = 0
        }
        let alpha = Double(strength) * (0.3 + 0.7 * breath)
        let middle: Double = side < 0 ? 180 : 0
        for (i, radius) in [CGFloat(8), 15].enumerated() {
            var arc = Path()
            arc.addArc(center: p, radius: radius + CGFloat(breath) * 1.5,
                       startAngle: .degrees(middle - 36), endAngle: .degrees(middle + 36), clockwise: false)
            g.stroke(arc, with: .color(Palette.mark(on: ground).opacity(alpha * (i == 0 ? 0.85 : 0.55))),
                     style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
        }
    }

    private static func drawPaw(_ g: inout GraphicsContext, center: CGPoint, size: CGSize, angle: Double, pads: Bool = false) {
        var paw = g
        paw.translateBy(x: center.x, y: center.y)
        paw.rotate(by: .degrees(angle))
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        let shape = Path(ellipseIn: rect)
        paw.fill(shape, with: .color(Palette.fur))
        paw.fill(shape.subtracting(shape.offsetBy(dx: 0, dy: -4)), with: .color(Palette.furShade))
        if pads {
            // The underside, shown when the paw is up.
            paw.fill(Path(ellipseIn: CGRect(x: -6, y: -1, width: 12, height: 9)), with: .color(Palette.earInner))
            for x in [-9.0, 0.0, 9.0] as [CGFloat] {
                paw.fill(Path(ellipseIn: CGRect(x: x - 3, y: -9 - (x == 0 ? 2 : 0), width: 6, height: 6)),
                         with: .color(Palette.earInner))
            }
        } else {
            // Toes.
            for x in [-size.width * 0.14, size.width * 0.14] {
                var toe = Path()
                toe.move(to: CGPoint(x: x, y: size.height * 0.5 - 1))
                toe.addLine(to: CGPoint(x: x, y: size.height * 0.5 - 6))
                paw.stroke(toe, with: .color(Palette.furDeep), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
    }

    /// The crescent the cat sleeps on. Drawn around (0, 0), the middle of its chord.
    /// The collar's charm. A bell: yolk, with its slot and the shade on its lower
    /// half. A medal: a larger yolk disc with a rim and a paw stamped in it.
    private static func drawCharm(_ g: inout GraphicsContext, at c: CGPoint, medal: Bool) {
        if medal {
            g.fill(Path(ellipseIn: CGRect(x: c.x - 12, y: c.y - 10, width: 24, height: 24)), with: .color(Palette.moonShade))
            g.fill(Path(ellipseIn: CGRect(x: c.x - 9.5, y: c.y - 7.5, width: 19, height: 19)), with: .color(Palette.moon))
            g.fill(Path(ellipseIn: CGRect(x: c.x - 3.6, y: c.y + 1.2, width: 7.2, height: 6)), with: .color(Palette.moonShade))
            for (dx, dy) in [(-5.2, -1.6), (-1.9, -4.6), (1.9, -4.6), (5.2, -1.6)] as [(CGFloat, CGFloat)] {
                g.fill(Path(ellipseIn: CGRect(x: c.x + dx - 1.6, y: c.y + dy - 1.6, width: 3.2, height: 3.2)), with: .color(Palette.moonShade))
            }
        } else {
            let bell = Path(ellipseIn: CGRect(x: c.x - 8, y: c.y - 6, width: 16, height: 16))
            g.fill(bell, with: .color(Palette.moon))
            g.fill(bell.subtracting(bell.offsetBy(dx: 0, dy: -4)), with: .color(Palette.moonShade))
            var slot = Path()
            slot.move(to: CGPoint(x: c.x - 4, y: c.y + 4))
            slot.addLine(to: CGPoint(x: c.x + 4, y: c.y + 4))
            g.stroke(slot, with: .color(Palette.ink), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
    }

    private static func drawMoon(_ g: inout GraphicsContext) {
        let crescent = Path.sliver(center: .zero, halfWidth: 88, sag: 62, thickness: 42)
        let moon = crescent.union(crescent.strokedPath(StrokeStyle(lineWidth: 12, lineJoin: .round)))
        g.fill(moon, with: .color(Palette.moon))
        g.fill(moon.subtracting(moon.offsetBy(dx: 0, dy: 8)), with: .color(Palette.moonLight))
        g.fill(moon.subtracting(moon.offsetBy(dx: -5, dy: -10)), with: .color(Palette.moonShade))
    }

    static func drawSparkle(_ g: inout GraphicsContext, center: CGPoint, radius r: CGFloat, color: Color) {
        g.fill(Path.sparkle(center: center, radius: r), with: .color(color))
    }
}

/// A cubic Bézier with what the startled cat needs from it: points, the way out of
/// the curve, and tufts of fur standing on it.
private struct Cubic {
    let p0, c1, c2, p3: CGPoint

    init(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint) {
        self.p0 = p0; self.c1 = c1; self.c2 = c2; self.p3 = p3
    }

    var path: Path {
        var p = Path()
        p.move(to: p0)
        p.addCurve(to: p3, control1: c1, control2: c2)
        return p
    }

    func point(_ u: Double) -> CGPoint {
        let u = CGFloat(u), v = 1 - u
        let a = v * v * v, b = 3 * v * v * u, c = 3 * v * u * u, d = u * u * u
        return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x,
                       y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
    }

    /// The unit normal at `u`, to the left of the direction of travel when `side` is 1.
    func normal(_ u: Double, side: CGFloat) -> CGVector {
        let a = point(max(0, u - 0.01)), b = point(min(1, u + 0.01))
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.0001)
        return CGVector(dx: side * dy / length, dy: -side * dx / length)
    }

    /// A tuft that curls like a flame: its base on the curve, `halfWidth` of it either
    /// side, the tip `length` out along the normal, leaning `sweep` further along the
    /// curve (and, with `along`, out along the curve's own direction at the tip).
    func flame(at u: Double, side: CGFloat, length: CGFloat, halfWidth: Double, sweep: Double, along: CGFloat = 0) -> Path {
        let n = normal(min(max(u, 0.01), 0.99), side: side)
        func inward(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - n.dx * 4, y: p.y - n.dy * 4) }
        let a = inward(point(max(0, u - halfWidth)))
        let b = inward(point(min(1, u + halfWidth)))
        let foot = point(min(1, u + sweep))
        let ahead = point(min(1, u + 0.01)), behind = point(max(0, u - 0.01))
        let dir = CGVector(dx: ahead.x - behind.x, dy: ahead.y - behind.y)
        let dirLength = max(hypot(dir.dx, dir.dy), 0.0001)
        let tip = CGPoint(x: foot.x + n.dx * length + dir.dx / dirLength * length * along,
                          y: foot.y + n.dy * length + dir.dy / dirLength * length * along)
        let mid = point(u)
        var p = Path()
        p.move(to: a)
        p.addQuadCurve(to: tip, control: CGPoint(x: mid.x + n.dx * length * 0.75, y: mid.y + n.dy * length * 0.75))
        p.addQuadCurve(to: b, control: CGPoint(x: b.x + n.dx * length * 0.3, y: b.y + n.dy * length * 0.3))
        p.closeSubpath()
        return p
    }
}

// MARK: - Shapes shared by the brand art

/// The four-point star from the app icon.
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path.sparkle(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2)
    }
}

/// A paw print: one won morning.
struct PawPrintShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let o = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: o.x + x * s, y: o.y + y * s, width: w * s, height: h * s)
        }
        var p = Path()
        // Main pad: a rounded, slightly heart-like trapezoid.
        p.addPath(Path.roundedPolygon([
            CGPoint(x: o.x + 0.50 * s, y: o.y + 0.43 * s),
            CGPoint(x: o.x + 0.80 * s, y: o.y + 0.80 * s),
            CGPoint(x: o.x + 0.50 * s, y: o.y + 0.96 * s),
            CGPoint(x: o.x + 0.20 * s, y: o.y + 0.80 * s),
        ], radius: 0.17 * s))
        p.addEllipse(in: r(0.02, 0.36, 0.20, 0.25))
        p.addEllipse(in: r(0.21, 0.08, 0.21, 0.27))
        p.addEllipse(in: r(0.58, 0.08, 0.21, 0.27))
        p.addEllipse(in: r(0.78, 0.36, 0.20, 0.25))
        return p
    }
}

extension Path {
    /// A rounded square-ish ellipse, optionally wider at the bottom (`flare` > 0).
    static func squircle(center c: CGPoint, rx a: CGFloat, ry b: CGFloat, exponent n: CGFloat = 2.5, flare: CGFloat = 0) -> Path {
        var p = Path()
        let steps = 160
        let e = 2 / Double(n)
        for i in 0..<steps {
            let th = Double(i) / Double(steps) * 2 * .pi
            let ct = cos(th), st = sin(th)
            var x = a * CGFloat(copysign(pow(abs(ct), e), ct))
            let y = b * CGFloat(copysign(pow(abs(st), e), st))
            x *= 1 + flare * (y / b)
            let point = CGPoint(x: c.x + x, y: c.y + y)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }

    /// A polygon with every corner rounded to `radius`.
    static func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> Path {
        var p = Path()
        guard points.count > 2 else { return p }
        let last = points[points.count - 1], first = points[0]
        p.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for i in points.indices {
            p.addArc(tangent1End: points[i], tangent2End: points[(i + 1) % points.count], radius: radius)
        }
        p.closeSubpath()
        return p
    }

    /// A crescent between two arcs through the same two corners, `halfWidth` either side
    /// of `center`. The outer arc bows `sag` below the chord (above it when negative);
    /// the crescent is `thickness` thick in the middle and comes to a point at both ends.
    static func sliver(center c: CGPoint, halfWidth l: CGFloat, sag: CGFloat, thickness: CGFloat) -> Path {
        let direction: CGFloat = sag < 0 ? -1 : 1
        // Near straight, the arcs' radii run off towards infinity, and once the inner
        // arc bows further than the outer one the crescent turns inside out into a
        // shape the size of the screen. Keep both bowed, the inner one less.
        let s1 = Swift.max(abs(sag), 1)
        let s2 = Swift.min(Swift.max(s1 - thickness, 0.5), s1 - 0.5)
        let r1 = (s1 * s1 + l * l) / (2 * s1)
        let r2 = (s2 * s2 + l * l) / (2 * s2)
        let c1 = CGPoint(x: c.x, y: c.y + direction * (s1 - r1))
        let c2 = CGPoint(x: c.x, y: c.y + direction * (s2 - r2))
        let outer = Path(ellipseIn: CGRect(x: c1.x - r1, y: c1.y - r1, width: r1 * 2, height: r1 * 2))
        let inner = Path(ellipseIn: CGRect(x: c2.x - r2, y: c2.y - r2, width: r2 * 2, height: r2 * 2))
        return outer.subtracting(inner)
    }

    /// The icon's four-point star: concave sides meeting at four sharp tips.
    static func sparkle(center c: CGPoint, radius r: CGFloat) -> Path {
        var p = Path()
        let waist = r * 0.16
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + waist, y: c.y - waist))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + waist, y: c.y + waist))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - waist, y: c.y + waist))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - waist, y: c.y - waist))
        p.closeSubpath()
        return p
    }
}

extension Color {
    /// Fixed artwork colour (the cat is white in both appearances).
    init(artHex hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Previews

#Preview("Moods") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach(CatMascot.Mood.allCases, id: \.self) { mood in
                CatMascot(mood: mood).frame(height: 180)
            }
        }
        .padding()
    }
    .background(Color(artHex: 0x1C1A17))
}
