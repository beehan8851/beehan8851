import SwiftUI

// MARK: - Moves

/// What the cat does when something happens to it. Every move is squash and stretch
/// on the whole drawing: it crouches, stretches as it leaves the ground, hangs at the
/// top, and squashes again when it lands — the oldest trick in cartoon animation, and
/// the one that makes a drawing feel like it has weight.
enum CatMove: Equatable {
    /// A small hop: a tap, a jump in the game.
    case hop
    /// A big leap for a won morning.
    case leap
    /// A leap with a full turn at the top: a new record, a milestone.
    case flip
    /// The sleeping cat does not get up. It stirs, and settles again.
    case stir
    /// Straight up off all four feet with no crouch first, then a shiver on landing:
    /// a fright. Goes with the startled cat.
    case startle

    /// How high, as a share of the cat's own height.
    fileprivate var height: CGFloat {
        switch self {
        case .hop: 0.28
        case .leap: 0.5
        case .flip: 0.62
        case .stir: 0
        case .startle: 0.34
        }
    }

    fileprivate var turns: Double { self == .flip ? 360 : 0 }
    fileprivate var tilt: Double {
        switch self {
        case .stir: 7
        case .startle: 3.5
        default: 0
        }
    }

    /// Getting ready to jump. A fright has no time for it.
    fileprivate var crouch: TimeInterval { self == .startle ? 0.02 : 0.1 }
    /// Going up, and again coming down.
    fileprivate var air: TimeInterval {
        switch self {
        case .hop: 0.16
        case .startle: 0.1
        default: 0.24
        }
    }
    /// Hanging at the top.
    fileprivate var top: TimeInterval {
        switch self {
        case .flip: 0.16
        case .startle: 0.12
        default: 0.06
        }
    }
    /// How long the sway or shiver waits before it starts: the shiver comes on landing.
    fileprivate var shiverDelay: TimeInterval { self == .startle ? crouch + air * 2 + top : 0 }
    /// One beat of the sway or shiver.
    fileprivate var shiverBeat: TimeInterval { self == .startle ? 0.05 : 0.16 }
}

// MARK: - Modifier

extension View {
    /// Plays `move` every time `trigger` changes. `size` is the cat's height in points,
    /// which sets how far it jumps; `shadow` draws its shadow on the ground beneath.
    /// Under Reduce Motion nothing moves.
    func catMotion(_ move: CatMove, trigger: Int, size: CGFloat, shadow: Bool = false) -> some View {
        modifier(CatMotionModifier(move: move, trigger: trigger, size: size, shadow: shadow))
    }
}

private struct CatMotionValues {
    var lift: CGFloat = 0       // 0 on the ground, 1 at the top
    var stretch: CGFloat = 1    // vertical scale; under 1 is a squash
    var spin: Double = 0
    var tilt: Double = 0
}

private struct CatMotionModifier: ViewModifier {
    let move: CatMove
    let trigger: Int
    let size: CGFloat
    let shadow: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Off the ground. Drives the wide-open eyes, which have to reach the drawing
    /// itself — the keyframe animator only moves what it is given.
    @State private var airborne = false

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            let height = move.height * size
            content
                .environment(\.catEyesWide, airborne)
                .task(id: trigger) {
                    guard trigger != 0, move != .stir else { return }
                    defer { airborne = false }
                    try? await Task.sleep(for: .seconds(move.crouch - 0.02))
                    airborne = true
                    try? await Task.sleep(for: .seconds(move.air * 2 + move.top - 0.02))
                    airborne = false
                }
                .keyframeAnimator(initialValue: CatMotionValues(), trigger: trigger) { view, value in
                    view
                        // Volume is kept: what it loses in height it gains in width.
                        .scaleEffect(x: 1 / max(value.stretch, 0.5), y: value.stretch, anchor: .bottom)
                        .rotationEffect(.degrees(value.spin + value.tilt), anchor: value.spin == 0 ? .bottom : .center)
                        .offset(y: -height * value.lift)
                        .background(alignment: .bottom) {
                            if shadow {
                                Ellipse()
                                    .fill(.black.opacity(0.14 * (1 - 0.6 * value.lift)))
                                    .frame(width: size * 0.7 * (1 - 0.35 * value.lift), height: size * 0.07)
                                    .offset(y: size * 0.03)
                                    .allowsHitTesting(false)
                            }
                        }
                } keyframes: { _ in
                    let air = move.air, top = move.top, crouch = move.crouch
                    let jumps = move != .stir
                    KeyframeTrack(\.lift) {
                        LinearKeyframe(0, duration: crouch)
                        CubicKeyframe(jumps ? 1 : 0, duration: air)        // up
                        CubicKeyframe(jumps ? 1 : 0, duration: top)
                        CubicKeyframe(0, duration: air)                    // down
                        LinearKeyframe(0, duration: 0.3)
                    }
                    KeyframeTrack(\.stretch) {
                        CubicKeyframe(move == .stir ? 0.96 : (move == .startle ? 1 : 0.82), duration: crouch)
                        CubicKeyframe(move == .stir ? 1.02 : (move == .startle ? 1.16 : 1.12), duration: air * 0.7)
                        CubicKeyframe(1, duration: air * 0.3 + top)
                        CubicKeyframe(move == .stir ? 1 : 1.05, duration: air * 0.8)
                        CubicKeyframe(move == .stir ? 1 : 0.86, duration: air * 0.2)
                        SpringKeyframe(1, duration: 0.3, spring: .bouncy)
                    }
                    KeyframeTrack(\.spin) {
                        LinearKeyframe(0, duration: crouch + air * 0.6)
                        CubicKeyframe(move.turns, duration: air * 0.4 + top + air * 0.4)
                        LinearKeyframe(move.turns, duration: 0.3)
                    }
                    KeyframeTrack(\.tilt) {
                        LinearKeyframe(0, duration: max(move.shiverDelay, 0.001))
                        CubicKeyframe(move.tilt, duration: move.shiverBeat * 0.9)
                        CubicKeyframe(-move.tilt, duration: move.shiverBeat * 1.1)
                        CubicKeyframe(move.tilt * 0.6, duration: move.shiverBeat)
                        CubicKeyframe(-move.tilt * 0.4, duration: move.shiverBeat)
                        SpringKeyframe(0, duration: 0.3)
                    }
                }
        }
    }
}

// MARK: - A cat that answers a tap

/// The cat, tappable: it hops. Tapped three times in quick succession it takes
/// fright. Asleep, it only stirs. What else it does it learns from long streaks
/// (`CatTrick`): it waves back, turns somersaults, leaps, throws off sparkles.
///
/// Stroked — a finger drawn across it, or simply left resting on it — it shuts its
/// eyes, pushes its head into the hand and purrs, until the finger lifts. A sad cat
/// is comforted; a sleeping one purrs without waking. Small things nobody is told
/// about.
struct TappableCat: View {
    let mood: CatMascot.Mood
    var ground: CatMascot.Ground? = nil
    var width: CGFloat
    /// Increment from outside to make it jump on its own (a won morning).
    var cue: Int = 0

    @State private var taps = 0
    @State private var recent: [Date] = []
    @State private var startled = false
    @State private var petting = CatPetting()
    /// Starts the purr when a finger rests on the cat without moving.
    @State private var resting: Task<Void, Never>?
    /// Waving back, for a moment after a tap.
    @State private var waving = false
    @State private var sparkles = 0
    @Environment(\.catTricks) private var tricks
    @Environment(\.colorScheme) private var colorScheme

    /// How far a finger has to travel before a touch is a stroke rather than a tap.
    private static let strokeDistance: CGFloat = 14
    /// How long a still finger has to rest on the cat to count as stroking it.
    private static let restLength: Duration = .milliseconds(500)

    private var height: CGFloat { width / CatArt.aspectRatio(for: mood) }

    private var move: CatMove {
        if mood == .sleeping { return .stir }
        if startled { return .startle }
        if taps > 0, tricks.knows(.somersault), taps % 4 == 0 { return .flip }
        if taps > 0, tricks.knows(.leap), taps % 3 == 0 { return .leap }
        return cue > 0 && taps == 0 ? .leap : .hop
    }

    var body: some View {
        Group {
            if mood == .sleeping {
                CatMascot(mood: mood, ground: ground)
            } else {
                CatStage(mood: startled ? .startled : (waving ? .ringing : mood), ground: ground)
            }
        }
        .frame(width: width)
        .overlay {
            if tricks.knows(.sparkle) {
                SparkleBurst(trigger: sparkles, ground: ground ?? (colorScheme == .dark ? .dark : .light))
                    .frame(width: width * 1.6, height: height * 1.4)
            }
        }
        .environment(\.catPetting, petting)
        .catMotion(move, trigger: taps + cue * 1000, size: height)
        .contentShape(Rectangle())
        // One gesture for both, so a tap and a stroke cannot both fire.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { touch in
                    let moved = hypot(touch.translation.width, touch.translation.height)
                    if !petting.isStroking {
                        if moved > Self.strokeDistance {
                            beginStroke()
                        } else if resting == nil {
                            resting = Task {
                                try? await Task.sleep(for: Self.restLength)
                                guard !Task.isCancelled else { return }
                                beginStroke()
                            }
                        }
                    }
                    if petting.isStroking {
                        petting.follow(min(max(touch.location.x / max(width, 1) * 2 - 1, -1), 1))
                    }
                }
                .onEnded { touch in
                    resting?.cancel()
                    resting = nil
                    if petting.isStroking {
                        endStroke()
                    } else if hypot(touch.translation.width, touch.translation.height) <= Self.strokeDistance {
                        tapped()
                    }
                }
        )
        .onDisappear {
            resting?.cancel()
            resting = nil
            if petting.isStroking { endStroke() }
        }
        .task(id: startled) {
            guard startled else { return }
            try? await Task.sleep(for: .seconds(CatStage.startleHold))
            startled = false
        }
        .task(id: waving) {
            guard waving else { return }
            try? await Task.sleep(for: .seconds(0.9))
            waving = false
        }
        .accessibilityHidden(true)
    }

    private func beginStroke() {
        guard !petting.isStroking, !startled else { return }
        var stroke = CatPetting(since: .now, released: nil)
        stroke.follow(petting.lean)
        petting = stroke
        Purr.shared.start()
    }

    private func endStroke() {
        petting.released = .now
        Purr.shared.stop()
    }

    private func tapped() {
        let now = Date.now
        recent = recent.filter { now.timeIntervalSince($0) < 0.7 } + [now]
        if mood != .sleeping, !startled, recent.count >= 3 {
            recent = []
            startled = true
            Haptics.impact(.rigid)
        } else {
            Haptics.impact(mood == .sleeping ? .soft : .light)
            // Awake, it answers; asleep, it only stirs.
            if mood != .sleeping && !startled {
                CatVoice.shared.mrrp()
                if tricks.knows(.wave) { waving = true }
                if tricks.knows(.sparkle) { sparkles += 1 }
            }
        }
        taps += 1
    }
}

// MARK: - Room for every mood

/// A sitting cat's space, whatever the mood. The startled cat stands side on and is
/// wider and taller: it spills over the sides and the top at the same scale, feet on
/// the same ground, rather than shrinking or pushing the layout about. Not for the
/// sleeping cat, which has its own shape.
struct CatStage: View {
    let mood: CatMascot.Mood
    var ground: CatMascot.Ground? = nil
    var animated: Bool = true

    /// How long a fright shows before the cat is itself again.
    static let startleHold: TimeInterval = 1.1

    var body: some View {
        Color.clear
            .aspectRatio(CatArt.aspectRatio(for: .awake), contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    // Same scale as the sitting cat, standing on the same ground.
                    let spread = CatArt.designSize(for: mood).width / CatArt.designSize(for: .awake).width
                    let width = geo.size.width * spread
                    let height = width / CatArt.aspectRatio(for: mood)
                    CatMascot(mood: mood, ground: ground, animated: animated)
                        .frame(width: width, height: height)
                        .position(x: geo.size.width / 2, y: geo.size.height - height / 2)
                }
            }
            .accessibilityHidden(true)
    }
}
