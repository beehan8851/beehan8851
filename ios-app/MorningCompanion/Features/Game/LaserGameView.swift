import SwiftUI

/// "Laser": a finger is the dot, the cat chases it. A short game for the morning
/// like "Catch the cat", never a mission. The board is a dark room, where a laser
/// dot shows and a white cat stands out; the screen around it is paper, as the
/// other game is.
struct LaserGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var game = LaserGame()
    @State private var best = LaserGameRecord.best()
    @State private var newBest = false

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            switch game.phase {
            case .ready: intro.transition(.opacity)
            case .playing: board.transition(.opacity)
            case .over: results.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: game.phase)
        .task(id: game.phase) { await run() }
        .onChange(of: game.phase) { _, phase in
            guard phase == .over else { return }
            newBest = LaserGameRecord.submit(game.score)
            best = LaserGameRecord.best()
            Haptics.notify(.success)
        }
        .onChange(of: game.cat) { old, new in
            switch (old, new) {
            case (_, .pouncing): Haptics.impact(.light)
            case (_, .landed(caught: true, _)): Haptics.impact(.heavy)
            case (.pouncing, .landed(caught: false, _)) where game.dot != nil: Haptics.impact(.rigid)
            default: break
            }
        }
    }

    // MARK: - Intro

    private var intro: some View {
        GamePage(spacing: DesignTokens.Spacing.m) {
            topBar { EmptyView() }
        } picture: {
            LaserPoster()
                .frame(maxWidth: 320)
                .padding(.bottom, DesignTokens.Spacing.s)
        } words: {
            Text(String(localized: "Laser", comment: "Laser game title"))
                .mcScaledFont(34, weight: .heavy, relativeTo: .largeTitle)
                .foregroundStyle(DesignTokens.Colors.ink)
                .multilineTextAlignment(.center)
            Text(String(localized: "Your finger is the dot. When the cat crouches, it is about to pounce: get out from under its paws. Every pounce you dodge is a point, and after three in a row each one counts double.", comment: "Laser game rules"))
                .font(.mcCallout)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if best > 0 {
                Text(String(localized: "Best \(best)", comment: "Progress streak card: the longest streak so far"))
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.ink)
            }
            Spacer(minLength: 0)
            Button { start() } label: {
                Text(String(localized: "Play", comment: "Game: start a round"))
                    .mcInkButton()
            }
            .buttonStyle(PressScaleButtonStyle())
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.bottom, DesignTokens.Spacing.s)
    }

    // MARK: - Board

    private var board: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            topBar {
                Text(game.score, format: .number)
                    .mcScaledFont(34, weight: .heavy, relativeTo: .largeTitle, monospacedDigits: true)
                    .foregroundStyle(DesignTokens.Colors.ink)
                    .contentTransition(.numericText(value: Double(game.score)))
                    .animation(.snappy, value: game.score)
                    .accessibilityLabel(String(localized: "Score \(game.score)", comment: "Game: score, VoiceOver"))
            }
            timerBar
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                        .fill(DesignTokens.Colors.nightBand)
                    if game.dot == nil, game.cat == .waiting {
                        Text(String(localized: "Put a finger down", comment: "Laser game: hint while the dot is off"))
                            .font(.system(.headline, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                            .padding(.top, DesignTokens.Spacing.l)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .transition(.opacity)
                    }
                    if let dodge = game.lastDodge {
                        PointsPop(points: dodge.points, color: DesignTokens.Colors.yolk)
                            .position(x: dodge.point.x, y: dodge.point.y - 70)
                            .id(dodge.index)
                    }
                    LaserBoardCat(game: game, reduceMotion: reduceMotion)
                }
                .animation(.easeInOut(duration: 0.2), value: game.dot == nil)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { game.pointDot(at: $0.location, at: .now) }
                        .onEnded { _ in game.liftDot() }
                )
                .onAppear { game.setBoard(geo.size) }
                .onChange(of: geo.size) { _, size in game.setBoard(size) }
            }
            comboLine
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.bottom, DesignTokens.Spacing.s)
        .accessibilityElement(children: .contain)
    }

    private var timerBar: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let left = game.remaining(at: context.date)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignTokens.Colors.ink.opacity(0.12))
                    Capsule()
                        .fill(left < 5 ? DesignTokens.Colors.ink : DesignTokens.Colors.ink.opacity(0.85))
                        .frame(width: geo.size.width * left / LaserGame.roundLength)
                }
            }
            .frame(height: 8)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "\(Int(left.rounded(.up))) seconds left", comment: "Game: time left, VoiceOver"))
        }
    }

    private var comboLine: some View {
        Group {
            if case .landed(caught: true, _) = game.cat {
                Text(String(localized: "Got it", comment: "Laser game: the cat landed on the dot"))
                    .foregroundStyle(DesignTokens.Colors.ink)
            } else if game.isOnCombo {
                Text(String(localized: "Combo · every dodge ×2", comment: "Laser game: combo is on"))
                    .foregroundStyle(DesignTokens.Colors.ink)
            } else if game.combo > 1 {
                Text(String(localized: "\(game.combo) in a row", comment: "Game: catches in a row so far"))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            } else {
                Text(String(localized: "Dodge the pounce", comment: "Laser game: hint while playing"))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .font(.system(.headline, weight: .bold))
        .frame(minHeight: 28)
        .animation(.snappy, value: game.isOnCombo)
    }

    // MARK: - Results

    private var results: some View {
        let phrase = CountPhrase(String(localized: "\(game.score) points", comment: "Game result: the score. The number is set large; keep it in the text."), count: game.score)
        return GamePage(spacing: DesignTokens.Spacing.s) {
            topBar { EmptyView() }
        } picture: {
            CatMascot(mood: newBest ? .proud : (game.score >= 8 ? .awake : .grumpy), ground: .light)
                .frame(width: 130)
                .catMotion(.flip, trigger: newBest ? 1 : 0, size: 120)
                .background {
                    Circle().fill(DesignTokens.Colors.yolk).frame(width: 164, height: 164).offset(y: 8)
                }
                .padding(.bottom, DesignTokens.Spacing.xs)
        } words: {
            Text(newBest
                 ? String(localized: "New best!", comment: "Game result: a new record")
                 : String(localized: "Time!", comment: "Game result: the round is over"))
                .mcScaledFont(28, weight: .heavy, relativeTo: .title)
                .foregroundStyle(DesignTokens.Colors.ink)
            VStack(spacing: 0) {
                if !phrase.before.isEmpty { resultWords(phrase.before) }
                Text(phrase.number)
                    .mcScaledFont(96, weight: .heavy, relativeTo: .largeTitle, monospacedDigits: true)
                    .foregroundStyle(DesignTokens.Colors.ink)
                if !phrase.after.isEmpty { resultWords(phrase.after) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(phrase.joined)
            HStack(spacing: DesignTokens.Spacing.m) {
                if best > 0, !newBest {
                    stat(String(localized: "Best \(best)", comment: "Progress streak card: the longest streak so far"))
                }
                if game.bestCombo > 1 {
                    stat(String(localized: "Longest run \(game.bestCombo)", comment: "Game result: most catches in a row"))
                }
            }
            .frame(minHeight: 36)
            Spacer(minLength: 0)
            Button { start() } label: {
                Text(String(localized: "Play again", comment: "Game: another round"))
                    .mcInkButton()
            }
            .buttonStyle(PressScaleButtonStyle())
            Button { dismiss() } label: {
                Text(String(localized: "Done", comment: "Done button"))
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.bottom, DesignTokens.Spacing.xs)
    }

    private func resultWords(_ text: String) -> some View {
        Text(text)
            .font(.system(.title3, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.textSecondary)
    }

    private func stat(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.ink)
            .padding(.horizontal, DesignTokens.Spacing.s)
            .frame(minHeight: 36)
            .background(DesignTokens.Colors.ink.opacity(0.08), in: Capsule())
    }

    // MARK: - Pieces

    private func topBar<Center: View>(@ViewBuilder center: () -> Center) -> some View {
        ZStack {
            center()
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.yolk)
                        .frame(width: 44, height: 44)
                        .background(DesignTokens.Colors.ink, in: Circle())
                }
                .accessibilityLabel(String(localized: "Close", comment: "Close button"))
                Spacer()
            }
        }
        .padding(.top, DesignTokens.Spacing.xs)
    }

    private func start() {
        Haptics.impact(.medium)
        newBest = false
        game.start(at: .now)
    }

    private func run() async {
        while !Task.isCancelled, game.phase == .playing {
            game.tick(at: .now)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
}

// MARK: - The cat on the board

/// The cat, and the dot. Side on, facing the dot: bounding after it with the front
/// reaching and gathering, low and wriggling its rump before a spring, stretched out
/// in the air, paws out where it lands. Sitting up when there is no dot to chase.
private struct LaserBoardCat: View {
    let game: LaserGame
    let reduceMotion: Bool

    /// The side-on cat's size on the board; the model's `halfLength` and
    /// `halfHeight` keep it inside.
    private static let width: CGFloat = 150
    private static var height: CGFloat { width * CatArt.stretchDesignSize.height / CatArt.stretchDesignSize.width }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let now = context.date
            let t = now.timeIntervalSinceReferenceDate
            let (point, height) = game.catPosition(at: now)
            let caught: Bool = { if case .landed(caught: true, _) = game.cat { true } else { false } }()
            ZStack {
                if caught, let dot = game.dot { LaserDot().position(dot) }
                pose(at: t, height: height)
                    .position(x: point.x, y: point.y - height * 70)
                if !caught, let dot = game.dot { LaserDot().position(dot) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func pose(at t: Double, height: CGFloat) -> some View {
        switch game.cat {
        case .waiting:
            CatStage(mood: .awake, ground: .dark)
                .frame(width: 74)
                // Feet on the same floor as the side-on cat's.
                .offset(y: Self.height / 2 - 74 / CatArt.aspectRatio(for: .awake) / 2)
                .transition(.opacity)
        case .chasing:
            // A bound: front out and in, three and a bit strides a second.
            let stride = reduceMotion ? 0.5 : 0.5 + 0.5 * sin(t * 2 * .pi * 3.4)
            side(reach: CGFloat(stride), at: t)
                .offset(y: reduceMotion ? 0 : -abs(sin(t * .pi * 3.4)) * 6)
        case .crouching:
            side(reach: 0, at: t)
                .scaleEffect(x: 1, y: 0.93, anchor: .bottom)
                // The wriggle before the spring.
                .rotationEffect(.degrees(reduceMotion ? 0 : sin(t * 2 * .pi * 6) * 1.6),
                                anchor: game.facing < 0 ? .bottomLeading : .bottomTrailing)
        case .pouncing:
            side(reach: 1, at: t)
                .rotationEffect(.degrees(Double(game.facing) * Double(height) * 8))
        case .landed(let caught, _):
            side(reach: caught ? 1 : 0.6, at: t)
        }
    }

    private func side(reach: CGFloat, at t: Double) -> some View {
        Canvas { g, size in
            CatArt.drawStretch(in: &g, size: size, ground: .dark, time: t, reach: reach, yawn: 0, hunting: true)
        }
        .frame(width: Self.width, height: Self.height)
        // Drawn facing left.
        .scaleEffect(x: game.facing < 0 ? 1 : -1, y: 1)
    }
}

/// A laser pointer's dot: flat red, the hot middle paler. No glow; on the dark
/// board it does not need one.
private struct LaserDot: View {
    var body: some View {
        ZStack {
            Circle().fill(DesignTokens.Colors.laser).frame(width: 22, height: 22)
            Circle().fill(Color(hex: 0xFFB3A8)).frame(width: 8, height: 8)
        }
    }
}

/// The intro's picture, and the Today card's: the cat down low, eyes on the dot.
struct LaserPoster: View {
    var ground: CatMascot.Ground = .dark
    var room: Bool = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 0) {
                LaserDot()
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity)
                Canvas { g, size in
                    CatArt.drawStretch(in: &g, size: size, ground: ground, time: t, reach: 0, yawn: 0, hunting: true)
                }
                .aspectRatio(CatArt.stretchDesignSize.width / CatArt.stretchDesignSize.height, contentMode: .fit)
                .layoutPriority(1)
            }
            .padding(room ? DesignTokens.Spacing.m : 0)
            .background {
                if room {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous)
                        .fill(DesignTokens.Colors.nightBand)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    LaserGameView()
}
