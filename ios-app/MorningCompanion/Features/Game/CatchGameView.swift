import SwiftUI

/// "Catch the cat": a short game for the first minutes of the day, when the hands
/// and eyes are still catching up. Not a mission — it never stands between anyone
/// and their alarm. On paper, with yolk only where the eye should go: the disc under
/// the cat, the button.
struct CatchGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var game = CatchGame()
    @State private var best = CatchGameRecord.best()
    @State private var newBest = false

    init(startImmediately: Bool = false) {
        let game = CatchGame()
        if startImmediately { game.start(at: .now) }
        _game = State(initialValue: game)
    }

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
            newBest = CatchGameRecord.submit(game.score)
            best = CatchGameRecord.best()
            Haptics.notify(.success)
        }
    }

    // MARK: - Intro

    private var intro: some View {
        GamePage(spacing: DesignTokens.Spacing.m) {
            topBar { EmptyView() }
        } picture: {
            CatMascot(mood: .ringing, ground: .light)
                .frame(width: 150)
                .background { YolkDisc(size: 190).offset(y: 10) }
                .padding(.bottom, DesignTokens.Spacing.s)
        } words: {
            Text(String(localized: "Catch the cat", comment: "Game title"))
                .mcScaledFont(34, weight: .heavy, relativeTo: .largeTitle)
                .foregroundStyle(DesignTokens.Colors.ink)
                .multilineTextAlignment(.center)
            Text(String(localized: "Tap the cat before it jumps away. Thirty seconds, and it gets quicker with every catch. Five in a row and each catch counts double.", comment: "Game rules"))
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
                    // A tap on the empty board is a miss: it costs the combo, and the
                    // cat takes fright and bolts.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            game.miss(at: .now)
                            Haptics.impact(.rigid)
                        }
                    if let caught = game.lastCatch {
                        PointsPop(points: caught.points)
                            .position(x: caught.point.x * geo.size.width, y: caught.point.y * geo.size.height - 40)
                            .id(caught.index)
                            .allowsHitTesting(false)
                    }
                    cat
                        .position(x: game.position.x * geo.size.width, y: game.position.y * geo.size.height)
                        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.72), value: game.jumps)
                }
            }
            comboLine
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.bottom, DesignTokens.Spacing.s)
    }

    /// The cat, fidgeting just before it jumps so a quick eye can see it coming, and
    /// bristling for a moment after a missed tap.
    private var cat: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let left = game.jumpsAt.map { $0.timeIntervalSince(context.date) } ?? 1
            let restless = !reduceMotion && left < 0.35
            let startled = game.isStartled(at: context.date)
            Button {
                let points = game.catchCat(at: .now)
                if points > 0 { Haptics.impact(points > 1 ? .heavy : .medium) }
            } label: {
                CatStage(mood: startled ? .startled : (game.isOnCombo ? .proud : .awake), ground: .light,
                         animated: startled)
                    .frame(width: 92)
                    // Each jump lands with a squash; the jump that starts a combo is a
                    // somersault, and a fright is straight up with a shiver.
                    .catMotion(startled ? .startle : (game.combo == CatchGame.comboThreshold ? .flip : .hop),
                               trigger: game.jumps, size: 80)
                    .background { YolkDisc(size: 104).offset(y: 6) }
                    .rotationEffect(.degrees(restless ? sin(context.date.timeIntervalSinceReferenceDate * 60) * 7 : 0))
                    .padding(14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(String(localized: "Cat", comment: "Game: the cat to tap, VoiceOver"))
        .accessibilityHint(String(localized: "Double-tap to catch it before it jumps.", comment: "Game: the cat, VoiceOver hint"))
    }

    private var timerBar: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { context in
            let left = game.remaining(at: context.date)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignTokens.Colors.ink.opacity(0.12))
                    Capsule()
                        .fill(left < 5 ? DesignTokens.Colors.ink : DesignTokens.Colors.ink.opacity(0.85))
                        .frame(width: geo.size.width * left / CatchGame.roundLength)
                }
            }
            .frame(height: 8)
            .accessibilityElement()
            .accessibilityLabel(String(localized: "\(Int(left.rounded(.up))) seconds left", comment: "Game: time left, VoiceOver"))
        }
    }

    private var comboLine: some View {
        Group {
            if game.isOnCombo {
                Text(String(localized: "Combo · every catch ×2", comment: "Game: combo is on"))
                    .foregroundStyle(DesignTokens.Colors.ink)
            } else if game.combo > 1 {
                Text(String(localized: "\(game.combo) in a row", comment: "Game: catches in a row so far"))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            } else {
                Text(String(localized: "Tap the cat", comment: "Game: hint while playing"))
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
            CatMascot(mood: newBest ? .proud : (game.score >= 10 ? .awake : .grumpy), ground: .light)
                .frame(width: 130)
                .catMotion(.flip, trigger: newBest ? 1 : 0, size: 120)
                .background { YolkDisc(size: 164).offset(y: 8) }
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
            try? await Task.sleep(for: .milliseconds(33))
        }
    }
}

/// The yolk under the cat: on paper the white cat needs somewhere to stand.
private struct YolkDisc: View {
    let size: CGFloat
    var body: some View {
        Circle()
            .fill(DesignTokens.Colors.yolk)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// "+1" or "+2", rising from where it was won and fading.
struct PointsPop: View {
    let points: Int
    var color: Color = DesignTokens.Colors.ink
    @State private var gone = false

    var body: some View {
        Text(verbatim: "+\(points)")
            .font(.system(size: points > 1 ? 34 : 28, weight: .heavy).width(.expanded))
            .foregroundStyle(color)
            .offset(y: gone ? -46 : 0)
            .opacity(gone ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) { gone = true }
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    CatchGameView()
}
