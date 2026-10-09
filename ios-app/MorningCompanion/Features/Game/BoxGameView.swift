import SwiftUI

/// "Which box?": watch the box with the cat in it while the boxes change places, then
/// tap it. A short game for the morning like the other two, never a mission. On
/// paper, the boxes ink, so the white cat and the yolk labels are what the eye follows.
struct BoxGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageLayout) private var pageLayout

    @State private var game = BoxGame()
    @State private var best = BoxGameRecord.best()
    @State private var newBest = false
    @State private var lastSwap = 0

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
            newBest = BoxGameRecord.submit(game.score)
            best = BoxGameRecord.best()
            Haptics.notify(.success)
        }
    }

    // MARK: - Intro

    private var intro: some View {
        GamePage(spacing: DesignTokens.Spacing.m) {
            topBar { EmptyView() }
        } picture: {
            BoxPoster()
                .frame(maxWidth: 300)
                .padding(.bottom, DesignTokens.Spacing.s)
        } words: {
            Text(String(localized: "Which box?", comment: "Box game title"))
                .mcScaledFont(34, weight: .heavy, relativeTo: .largeTitle)
                .foregroundStyle(DesignTokens.Colors.ink)
                .multilineTextAlignment(.center)
            Text(String(localized: "The cat hides in a box, and the boxes change places. Keep your eye on it, then tap the box it is in. It gets quicker with every find. Three wrong boxes and the game is over.", comment: "Box game rules"))
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
            } trailing: {
                livesView
            }
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isMoving)) { context in
                    row(in: geo.size, at: context.date)
                }
            }
            hintLine
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.bottom, DesignTokens.Spacing.s)
    }

    /// Whether anything on the board is moving on its own.
    private var isMoving: Bool {
        switch game.step {
        case .guessing: false
        default: true
        }
    }

    /// The boxes in their row. On a spread the places are shared between the two
    /// pages so that no box comes to rest on the fold.
    private func row(in size: CGSize, at now: Date) -> some View {
        let count = game.count
        let spread = pageLayout == .spread
        let pitch = spread ? (size.width / 2 - PageLayout.gutter / 2) / CGFloat(Int((Double(count) / 2).rounded(.up))) : size.width / CGFloat(count)
        // The box itself most of its place; the open flaps reach into the rest.
        let boxWidth = min(pitch * 0.72 / (BoxArt.body.width / BoxArt.designSize.width), 260)
        let spots = game.layout(at: now)
        return ZStack {
            ForEach(0..<count, id: \.self) { box in
                let spot = spots[box]
                BoxDrawing(
                    width: boxWidth,
                    open: openAmount(box: box, at: now),
                    cat: catShown(in: box, at: now),
                    duck: duckAmount(box: box, at: now)
                )
                .scaleEffect(1 + 0.07 * spot.arc)
                .position(x: x(forPlace: spot.place, count: count, width: size.width, spread: spread),
                          y: size.height * 0.5 + spot.arc * boxWidth * 0.32)
                .zIndex(Double(spot.arc))
                .onTapGesture { choose(box) }
                .accessibilityElement()
                .accessibilityLabel(String(localized: "Box \(Int(spot.place.rounded()) + 1)", comment: "Box game: one of the boxes, VoiceOver"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { choose(box) }
            }
        }
        .frame(width: size.width, height: size.height)
        .id(game.round)
        .onChange(of: game.swapNumber(at: now)) { _, number in
            if number > 0, number != lastSwap { Haptics.impact(.soft) }
            lastSwap = number
        }
    }

    /// Places along the row. A place can be fractional mid-swap.
    private func x(forPlace place: CGFloat, count: Int, width: CGFloat, spread: Bool) -> CGFloat {
        guard spread else { return width * (place + 0.5) / CGFloat(count) }
        let left = Int((Double(count) / 2).rounded(.up))
        let page = width / 2 - PageLayout.gutter / 2
        // Each page's places evenly over that page; between pages, straight across.
        func at(_ p: Int) -> CGFloat {
            p < left
                ? page * (CGFloat(p) + 0.5) / CGFloat(left)
                : width - page + page * (CGFloat(p - left) + 0.5) / CGFloat(count - left)
        }
        let lower = Int(place.rounded(.down))
        let upper = min(lower + 1, count - 1)
        let fraction = place - CGFloat(lower)
        return at(lower) + (at(upper) - at(lower)) * fraction
    }

    // MARK: - What each box shows

    private func openAmount(box: Int, at now: Date) -> CGFloat {
        switch game.step {
        case .showing:
            return 1
        case .hiding(let until):
            // The cat ducks first, then the lids come down.
            let left = until.timeIntervalSince(now)
            return CGFloat(min(1, max(0, (left - 0.05) / 0.25)))
        case .shuffling, .guessing:
            return 0
        case .revealing(let chosen, let until):
            let opened = box == chosen || (!game.lastGuessRight && box == game.catBox)
            guard opened else { return 0 }
            // On a miss the cat's own box opens a moment after the wrong one.
            let since = (game.lastGuessRight ? BoxGame.foundLength : BoxGame.missedLength) - until.timeIntervalSince(now)
            let delay = box == chosen ? 0 : 0.45
            return CGFloat(min(1, max(0, (since - delay) / 0.2)))
        }
    }

    private func catShown(in box: Int, at now: Date) -> CatMascot.Mood? {
        guard box == game.catBox else { return nil }
        switch game.step {
        case .showing, .hiding: return .awake
        case .revealing(let chosen, _):
            return chosen == box ? .proud : .ringing
        case .shuffling, .guessing: return nil
        }
    }

    /// 0 sitting up in the box, 1 down out of sight.
    private func duckAmount(box: Int, at now: Date) -> CGFloat {
        switch game.step {
        case .hiding(let until):
            let since = BoxGame.hideLength - until.timeIntervalSince(now)
            return CGFloat(min(1, max(0, since / 0.25)))
        case .revealing(let chosen, let until):
            // Up out of the box, once its lid is open.
            let since = (game.lastGuessRight ? BoxGame.foundLength : BoxGame.missedLength) - until.timeIntervalSince(now)
            let delay = (box == chosen ? 0 : 0.45) + 0.12
            return 1 - CGFloat(min(1, max(0, (since - delay) / 0.22)))
        default:
            return 0
        }
    }

    // MARK: - Pieces on the board

    private var livesView: some View {
        HStack(spacing: 6) {
            ForEach(0..<BoxGame.startingLives, id: \.self) { i in
                PawPrintShape()
                    .fill(i < game.lives ? DesignTokens.Colors.ink : DesignTokens.Colors.ink.opacity(0.15))
                    .frame(width: 18, height: 18)
            }
        }
        .animation(.snappy, value: game.lives)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "\(game.lives) tries left", comment: "Box game: wrong guesses left, VoiceOver"))
    }

    private var hintLine: some View {
        Group {
            switch game.step {
            case .showing, .hiding:
                Text(String(localized: "Watch the box with the cat", comment: "Box game: before the shuffle"))
            case .shuffling:
                Text(String(localized: "Keep your eye on it", comment: "Box game: during the shuffle"))
            case .guessing:
                Text(String(localized: "Which box?", comment: "Box game title"))
                    .foregroundStyle(DesignTokens.Colors.ink)
            case .revealing:
                Text(game.lastGuessRight
                     ? String(localized: "Found it!", comment: "Box game: the right box")
                     : String(localized: "Not that one", comment: "Box game: the wrong box"))
                    .foregroundStyle(DesignTokens.Colors.ink)
            }
        }
        .font(.system(.headline, weight: .bold))
        .foregroundStyle(DesignTokens.Colors.textSecondary)
        .frame(minHeight: 28)
        .contentTransition(.opacity)
        .animation(.snappy, value: game.step)
    }

    // MARK: - Results

    private var results: some View {
        let phrase = CountPhrase(String(localized: "\(game.score) points", comment: "Game result: the score. The number is set large; keep it in the text."), count: game.score)
        return GamePage(spacing: DesignTokens.Spacing.s) {
            topBar { EmptyView() }
        } picture: {
            BoxPoster(mood: newBest ? .proud : (game.score >= 6 ? .awake : .ringing))
                .frame(maxWidth: 220)
                .padding(.bottom, DesignTokens.Spacing.xs)
        } words: {
            Text(newBest
                 ? String(localized: "New best!", comment: "Game result: a new record")
                 : String(localized: "Game over", comment: "Box game result: out of tries"))
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

    private func topBar<Center: View, Trailing: View>(@ViewBuilder center: () -> Center,
                                                      @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
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
                trailing()
            }
        }
        .padding(.top, DesignTokens.Spacing.xs)
    }

    // MARK: - Play

    private func start() {
        Haptics.impact(.medium)
        newBest = false
        lastSwap = 0
        game.start(at: .now)
    }

    private func choose(_ box: Int) {
        guard let right = game.choose(box: box, at: .now) else { return }
        if right {
            Haptics.notify(.success)
            CatVoice.shared.mrrp()
        } else {
            Haptics.impact(.rigid)
        }
    }

    private func run() async {
        while !Task.isCancelled, game.phase == .playing {
            game.tick(at: .now)
            try? await Task.sleep(for: .milliseconds(16))
        }
    }
}

// MARK: - A box

/// One box, with the cat in it or not. The cat sits between the box's two layers,
/// its head over the rim; ducking, it sinks behind the front wall and never shows
/// below the box. Shared by the board and the posters.
struct BoxDrawing: View {
    let width: CGFloat
    var open: CGFloat = 1
    var cat: CatMascot.Mood? = nil
    var duck: CGFloat = 0
    var ground: BoxArt.Ground = .paper

    private var height: CGFloat { width * BoxArt.designSize.height / BoxArt.designSize.width }
    private var catWidth: CGFloat { width * BoxArt.body.width / BoxArt.designSize.width * 0.86 }
    private var catHeight: CGFloat { catWidth / CatArt.aspectRatio(for: .awake) }

    var body: some View {
        let rimY = height * BoxArt.rim
        let bottom = height * BoxArt.body.maxY / BoxArt.designSize.height
        // Room above the box for a head that comes up out of it.
        let room = catHeight * 0.7
        ZStack(alignment: .top) {
            Canvas { g, size in BoxArt.draw(.back, in: &g, size: size, open: open, ground: ground) }
                .frame(width: width, height: height)
                .offset(y: room)
            if let cat {
                CatStage(mood: cat, ground: ground == .paper ? .light : .dark)
                    .frame(width: catWidth, height: catHeight)
                    .offset(y: room + rimY - catHeight * 0.66 + duck * catHeight * 0.75)
                    .frame(width: width, height: room + bottom - 3, alignment: .top)
                    .clipped()
            }
            Canvas { g, size in BoxArt.draw(.front, in: &g, size: size, open: open, ground: ground) }
                .frame(width: width, height: height)
                .offset(y: room)
        }
        .frame(width: width, height: room + height, alignment: .top)
        // The board places a box by its middle; keep that the box's, not the room's.
        .offset(y: -room / 2)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }
}

/// The intro's picture, and the Today card's: three boxes, the cat in the middle one.
struct BoxPoster: View {
    var mood: CatMascot.Mood = .awake
    var ground: BoxArt.Ground = .paper

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width / 2.2
            ZStack {
                BoxDrawing(width: w, open: 0, ground: ground).offset(x: -w * 0.74)
                BoxDrawing(width: w, open: 0, ground: ground).offset(x: w * 0.74)
                BoxDrawing(width: w, open: 1, cat: mood, ground: ground)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(2.0, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview {
    BoxGameView()
}
