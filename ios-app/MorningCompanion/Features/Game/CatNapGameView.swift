import SwiftUI

/// Cat Naps: today's puzzles, three a day like a newspaper's — easy, medium and hard.
/// Put a cat to sleep on every cushion — one to a row, a column and a cushion, none
/// touching. A tap rules a cell out, a second puts a cat on it, a third clears it; a
/// finger drawn across the board rules out a run of cells. Someone new starts on
/// easy, and each result offers the next level up. Free: today's three, and three
/// unlimited puzzles to try. Premium: unlimited puzzles, a new board every time, the
/// puzzles of the days before, and hints.
struct CatNapGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageLayout) private var pageLayout
    @Environment(AppContainer.self) private var container

    @State private var number = CatNapDay.number(for: .now)
    @State private var level = CatNapRecord.lastLevel()
    /// Set while playing unlimited puzzles: the board's seed.
    @State private var unlimitedSeed: UInt64?
    @State private var unlimitedStats = CatNapRecord.UnlimitedStats()
    /// Go straight to the board once the next puzzle is made.
    @State private var autoStart = false
    @State private var game: CatNapGame?
    /// The levels of this day already solved, for the ticks on the picker.
    @State private var solvedLevels: [CatNapLevel: CatNapRecord.Solve] = [:]
    @State private var screen: Screen = .intro
    @State private var solve: CatNapRecord.Solve?
    @State private var newBest = false
    @State private var showingArchive = false
    @State private var paywallFeature: PremiumFeature?
    /// The finger on the board: the cell it came down on, and what it is painting
    /// once it has moved off that cell.
    @State private var strokeStart: Int?
    @State private var strokePaint: CatNapGame.Cell??
    @State private var strokeOrigin: CGPoint?

    private enum Screen { case intro, board, solved }

    private var today: Int { CatNapDay.number(for: .now) }
    private var isToday: Bool { number == today }
    private var isUnlimited: Bool { unlimitedSeed != nil }
    private var unlimitedOpen: Bool { CatNapAccess.unlimited(isPremium: container.isPremium) }

    private struct LoadKey: Hashable {
        let number: Int
        let level: CatNapLevel
        let seed: UInt64?
    }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            switch screen {
            case .intro: intro.transition(.opacity)
            case .board: board.transition(.opacity)
            case .solved: results.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: screen)
        .task(id: LoadKey(number: number, level: level, seed: unlimitedSeed)) { await load() }
        .onChange(of: scenePhase) { _, phase in
            guard let game, screen == .board else { return }
            if phase == .active { game.resume(at: .now) } else { pause(game) }
        }
        .onChange(of: game?.solved) { _, solved in
            if solved == true { finish() }
        }
        .onDisappear { if let game, screen == .board { pause(game) } }
        .sheet(isPresented: $showingArchive) {
            CatNapArchiveView(today: today) { picked in
                showingArchive = false
                open(picked)
            }
        }
        .paywall(for: $paywallFeature)
    }

    // MARK: - Loading

    /// A big board takes a moment to make in a debug build: off the main thread.
    private func load() async {
        let number = number, level = level, seed = unlimitedSeed
        game = nil
        solvedLevels = seed == nil ? CatNapRecord.solves(number) : [:]
        solve = solvedLevels[level]
        unlimitedStats = CatNapRecord.stats(level)
        let puzzle = await Task.detached(priority: .userInitiated) {
            seed.map { CatNapDay.puzzle(seed: $0, level: level) } ?? CatNapDay.puzzle(number, level: level)
        }.value
        guard number == self.number, level == self.level, seed == unlimitedSeed else { return }
        game = CatNapGame(number: number, level: level, puzzle: puzzle,
                          saved: CatNapRecord.progress(number, level: level))
        if autoStart {
            autoStart = false
            start()
        }
    }

    /// A day's puzzle: today's, one from the past, or the next level up.
    private func open(_ picked: Int, level: CatNapLevel? = nil, play: Bool = false) {
        if let game, screen == .board { pause(game) }
        unlimitedSeed = nil
        number = picked
        if let level { self.level = level }
        autoStart = play
        screen = .intro
    }

    /// Unlimited puzzles at the current level: the one under way there, or with
    /// `fresh` a new one. Locked, it shows the paywall instead.
    private func openUnlimited(fresh: Bool, play: Bool = false) {
        guard let seed = unlimitedSeed(for: level, fresh: fresh) else { return }
        if let game, screen == .board { pause(game) }
        number = CatNapDay.unlimited
        unlimitedSeed = seed
        autoStart = play
        screen = .intro
    }

    /// The seed to play at `level`, or nil — and the paywall — once a free account
    /// has had its tries. Picking up a board already under way costs no try.
    private func unlimitedSeed(for level: CatNapLevel, fresh: Bool) -> UInt64? {
        if !fresh, let seed = CatNapRecord.unlimitedSeed(level) { return seed }
        if unlimitedOpen { return CatNapRecord.newUnlimitedSeed(level) }
        if CatNapRecord.freeTriesLeft() > 0 {
            CatNapRecord.useFreeTry()
            return CatNapRecord.newUnlimitedSeed(level)
        }
        paywallFeature = .catNapsUnlimited
        return nil
    }

    // MARK: - Intro

    private var intro: some View {
        GamePage(spacing: DesignTokens.Spacing.m) {
            topBar { EmptyView() }
        } picture: {
            CatNapPoster()
                .frame(maxWidth: 190)
                .padding(.bottom, DesignTokens.Spacing.xs)
        } words: {
            VStack(spacing: DesignTokens.Spacing.xxs) {
                Text(isUnlimited
                     ? String(localized: "Unlimited · a new board every time", comment: "Cat Naps: over the title in unlimited mode").uppercased()
                     : puzzleLine(number))
                    .font(.system(.caption, weight: .heavy).width(.expanded))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(String(localized: "Cat Naps", comment: "Cat Naps game title"))
                    .mcScaledFont(34, weight: .heavy, relativeTo: .largeTitle)
                    .foregroundStyle(DesignTokens.Colors.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            Text(String(localized: "Every cushion wants one cat asleep on it. One cat to a row, one to a column, and no two touching, not even at a corner. Tap once to rule a cell out, twice for a cat.", comment: "Cat Naps rules"))
                .font(.mcCallout)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            levelPicker
            Group {
                if isUnlimited, !unlimitedOpen {
                    chip(String(localized: "Free tries left: \(CatNapRecord.freeTriesLeft())", comment: "Cat Naps unlimited: tries a free account has left"))
                } else if isUnlimited {
                    if let best = unlimitedStats.bestSeconds {
                        chip(String(localized: "Best \(Self.clock(best)) · \(unlimitedStats.solved) solved", comment: "Cat Naps unlimited: best time and puzzles solved at this level"))
                    }
                } else if let solve {
                    chip(String(localized: "Solved in \(Self.clock(solve.seconds))", comment: "Cat Naps: this puzzle was already solved, with its time"))
                } else if isToday, streak > 0 {
                    chip(String(localized: "Streak \(streak)", comment: "Cat Naps: days in a row with the day's puzzle solved"))
                }
            }
            .frame(minHeight: 36)
            Spacer(minLength: 0)
            Button { start() } label: {
                Group {
                    if game == nil {
                        ProgressView().tint(DesignTokens.Colors.yolk)
                    } else {
                        Text(introButtonTitle)
                    }
                }
                .mcInkButton()
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(game == nil)
            HStack {
                if isUnlimited {
                    todayButton
                } else {
                    archiveButton
                    unlimitedButton
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.bottom, DesignTokens.Spacing.xs)
    }

    private var introButtonTitle: String {
        if solve != nil { return String(localized: "Play again", comment: "Game: another round") }
        if let game, !game.isUntouched { return String(localized: "Carry on", comment: "Cat Naps: go back to a board left half done") }
        return String(localized: "Play", comment: "Game: start a round")
    }

    private var streak: Int { CatNapRecord.streak(today: today) }

    /// Easy, medium, hard: the board's size under each, a tick on those solved.
    private var levelPicker: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(CatNapLevel.allCases) { option in
                let chosen = option == level
                Button {
                    guard option != level else { return }
                    if isUnlimited {
                        guard let seed = unlimitedSeed(for: option, fresh: false) else { return }
                        unlimitedSeed = seed
                    }
                    Haptics.selection()
                    level = option
                    CatNapRecord.setLastLevel(option)
                } label: {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Text(option.title)
                            if solvedLevels[option] != nil {
                                Image(systemName: "checkmark").font(.caption.weight(.heavy))
                            }
                        }
                        .font(.system(.subheadline, weight: .heavy))
                        Text("\(option.size) × \(option.size)")
                            .font(.system(.caption, weight: .semibold).monospacedDigit())
                            .opacity(0.7)
                    }
                    .foregroundStyle(chosen ? DesignTokens.Colors.yolk : DesignTokens.Colors.ink)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(chosen ? DesignTokens.Colors.ink : DesignTokens.Colors.ink.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(option.title)
                .accessibilityValue(solvedLevels[option] != nil
                                    ? String(localized: "\(option.size) by \(option.size), solved", comment: "Cat Naps level picker: board size, solved, VoiceOver")
                                    : String(localized: "\(option.size) by \(option.size)", comment: "Cat Naps level picker: board size, VoiceOver"))
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }

    /// Unlimited puzzles: open on Premium, three tries free, then a lock.
    private var unlimitedButton: some View {
        Button { openUnlimited(fresh: false) } label: {
            HStack(spacing: 6) {
                Image(systemName: "infinity").font(.callout.weight(.bold))
                Text(String(localized: "Unlimited", comment: "Cat Naps: opens unlimited puzzles"))
                unlimitedBadge
            }
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    @ViewBuilder
    private var unlimitedBadge: some View {
        if !unlimitedOpen {
            if CatNapRecord.freeTriesLeft() > 0 {
                Text(String(localized: "\(CatNapRecord.freeTriesLeft()) free", comment: "Cat Naps: unlimited puzzles a free account can still try"))
                    .font(.system(.caption, weight: .heavy))
                    .foregroundStyle(DesignTokens.Colors.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(DesignTokens.Colors.yolk, in: Capsule())
            } else {
                Image(systemName: "lock.fill").font(.caption.weight(.bold))
            }
        }
    }

    private var todayButton: some View {
        Button { open(today) } label: {
            Text(String(localized: "Today's puzzles", comment: "Cat Naps: back from unlimited to today's three"))
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private var archiveButton: some View {
        Button {
            if container.isPremium { showingArchive = true } else { paywallFeature = .catNaps }
        } label: {
            HStack(spacing: 6) {
                Text(String(localized: "Past puzzles", comment: "Cat Naps: opens the puzzles of earlier days"))
                if !container.isPremium {
                    Image(systemName: "lock.fill").font(.caption.weight(.bold))
                }
            }
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: - Board

    @ViewBuilder
    private var board: some View {
        if let game {
            let controls = VStack(spacing: DesignTokens.Spacing.s) {
                statusLine(game)
                HStack(spacing: DesignTokens.Spacing.s) {
                    toolButton(String(localized: "Clear", comment: "Cat Naps: empty the whole board"), symbol: "eraser", locked: false) {
                        Haptics.impact(.light)
                        game.clear(at: .now)
                        save(game)
                    }
                    .disabled(game.isUntouched)
                    toolButton(String(localized: "Hint", comment: "Cat Naps: a cat put in the right place for you"), symbol: "lightbulb", locked: !container.isPremium) {
                        guard container.isPremium else { paywallFeature = .catNaps; return }
                        Haptics.impact(.medium)
                        game.hint(at: .now)
                        save(game)
                    }
                }
            }
            VStack(spacing: DesignTokens.Spacing.s) {
                topBar {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Self.clock(Int(game.elapsed(at: context.date))))
                            .mcScaledFont(28, weight: .heavy, relativeTo: .title, monospacedDigits: true)
                            .foregroundStyle(DesignTokens.Colors.ink)
                    }
                    .accessibilityHidden(true)
                } trailing: {
                    circleButton(symbol: "arrow.uturn.backward", label: String(localized: "Undo", comment: "Cat Naps: take back the last move")) {
                        Haptics.selection()
                        game.undo(at: .now)
                        save(game)
                    }
                    .disabled(!game.canUndo)
                    .opacity(game.canUndo ? 1 : 0.35)
                }
                if pageLayout == .spread {
                    HStack(spacing: PageLayout.gutter) {
                        grid(game).frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack { Spacer(); controls }.frame(maxWidth: .infinity)
                    }
                } else {
                    Text(boardLine)
                        .font(.system(.caption, weight: .heavy).width(.expanded))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    grid(game)
                        .frame(maxWidth: 560, maxHeight: .infinity)
                    controls
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.bottom, DesignTokens.Spacing.s)
        }
    }

    private func grid(_ game: CatNapGame) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / CGFloat(game.size)
            // Read here, in the body, so a change redraws the board even while the
            // clock that animates it is paused; the canvas draws from this copy.
            let state = BoardState(game)
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion && !game.solved)) { context in
                Canvas { g, _ in draw(state, cell: cell, at: context.date, in: &g) }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(stroke(game, cell: cell))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Board", comment: "Cat Naps: the board, VoiceOver"))
            .accessibilityChildren { cellElements(game, cell: cell) }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    /// What the canvas draws.
    private struct BoardState {
        let size: Int
        let regions: [Int]
        let cells: [CatNapGame.Cell]
        let clashing: Set<Int>
        let awake: Set<Int>
        let placedAt: [Int: Date]
        let solved: Bool

        @MainActor init(_ game: CatNapGame) {
            size = game.size
            regions = game.puzzle.regions
            cells = game.cells
            clashing = game.clashing
            awake = game.awake
            placedAt = game.placedAt
            solved = game.solved
        }
    }

    private func draw(_ game: BoardState, cell: CGFloat, at now: Date, in g: inout GraphicsContext) {
        let n = game.size
        let marks = Set(game.cells.indices.filter { game.cells[$0] == .mark })
        CatNapArt.drawBoard(size: n, regions: game.regions, cell: cell, in: &g,
                            clashing: game.clashing, marks: marks, thick: max(2.5, cell / 15))
        let t = now.timeIntervalSinceReferenceDate
        for (index, value) in game.cells.enumerated() where value == .cat {
            let rect = CGRect(x: CGFloat(index % n) * cell, y: CGFloat(index / n) * cell, width: cell, height: cell)
            // Dropped onto the cushion: a little too big, then settling.
            var scale: CGFloat = 1
            if let placed = game.placedAt[index], !reduceMotion {
                let p = min(1, now.timeIntervalSince(placed) / 0.28)
                scale = 1 + 0.18 * CGFloat(sin(p * .pi)) * CGFloat(1 - p)
            }
            let inset = cell * 0.05
            let box = rect.insetBy(dx: inset, dy: inset)
            let scaled = CGRect(x: box.midX - box.width * scale / 2, y: box.midY - box.height * scale / 2,
                                width: box.width * scale, height: box.height * scale)
            let breath = reduceMotion ? 0 : CGFloat(sin(t * 2 * .pi / 3.6 + Double(index)))
            CatNapArt.drawCat(in: &g, rect: scaled, awake: game.awake.contains(index), breath: breath)
            if game.solved, !reduceMotion {
                CatNapArt.drawZ(in: &g, rect: rect, t: t - (solvedAt ?? t), delay: Double(index / n) * 0.12)
            }
        }
    }

    @State private var solvedAt: TimeInterval?

    /// One gesture for taps and strokes: a finger that lifts on the cell it came down
    /// on is a tap; one that moves on paints every cell it crosses the way the first
    /// one went — ruled out, or cleared.
    private func stroke(_ game: CatNapGame, cell: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // A gesture the system cancels never ends: a new touch starts afresh.
                if value.startLocation != strokeOrigin {
                    strokeOrigin = value.startLocation
                    strokeStart = index(at: value.startLocation, cell: cell, size: game.size)
                    strokePaint = nil
                }
                guard let index = index(at: value.location, cell: cell, size: game.size),
                      let start = strokeStart else { return }
                if strokePaint == nil {
                    guard index != start else { return }
                    let paint: CatNapGame.Cell? = switch game.cells[start] {
                    case .empty: .mark
                    case .mark: .empty
                    case .cat: nil
                    }
                    strokePaint = .some(paint)
                    if let paint {
                        game.beginStroke()
                        game.paint(start, paint, at: .now)
                    }
                }
                if case .some(.some(let paint)) = strokePaint, game.cells[index] != paint, game.cells[index] != .cat {
                    game.paint(index, paint, at: .now)
                    Haptics.selection()
                }
            }
            .onEnded { value in
                if value.startLocation != strokeOrigin {
                    strokeStart = index(at: value.startLocation, cell: cell, size: game.size)
                    strokePaint = nil
                }
                if strokePaint == nil, let start = strokeStart { tap(start) }
                if strokePaint != nil { save(game) }
                strokeStart = nil
                strokePaint = nil
                strokeOrigin = nil
            }
    }

    private func index(at point: CGPoint, cell: CGFloat, size: Int) -> Int? {
        let column = Int(point.x / cell), row = Int(point.y / cell)
        guard point.x >= 0, point.y >= 0, row < size, column < size else { return nil }
        return row * size + column
    }

    private func tap(_ index: Int) {
        guard let game else { return }
        let hadClash = !game.clashing.isEmpty
        let placed = game.tap(index, at: .now)
        if placed == .cat && !hadClash && !game.clashing.isEmpty {
            Haptics.impact(.rigid)
        } else if placed == .cat {
            Haptics.impact(.soft)
        } else {
            Haptics.selection()
        }
        save(game)
    }

    /// One invisible element a cell, in reading order, for VoiceOver.
    private func cellElements(_ game: CatNapGame, cell: CGFloat) -> some View {
        let n = game.size
        return VStack(spacing: 0) {
            ForEach(0..<n, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<n, id: \.self) { column in
                        let index = row * n + column
                        Color.clear
                            .frame(width: cell, height: cell)
                            .accessibilityElement()
                            .accessibilityLabel(String(localized: "Row \(row + 1), column \(column + 1)", comment: "Cat Naps: a cell, VoiceOver"))
                            .accessibilityValue(cellValue(game, index))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { tap(index) }
                    }
                }
            }
        }
    }

    private func cellValue(_ game: CatNapGame, _ index: Int) -> String {
        let cushion = CatNapArt.cushionName(game.puzzle.regions[index])
        let what: String = switch game.cells[index] {
        case .empty: String(localized: "empty", comment: "Cat Naps: a cell with nothing on it, VoiceOver")
        case .mark: String(localized: "ruled out", comment: "Cat Naps: a cell marked as no place for a cat, VoiceOver")
        case .cat: game.awake.contains(index)
            ? String(localized: "cat, awake: too close to another", comment: "Cat Naps: a cat in a clash, VoiceOver")
            : String(localized: "cat, asleep", comment: "Cat Naps: a cat, VoiceOver")
        }
        return String(localized: "\(cushion) cushion, \(what)", comment: "Cat Naps: a cell's cushion colour and what is on it, VoiceOver")
    }

    private func statusLine(_ game: CatNapGame) -> some View {
        Group {
            if game.solved {
                Text(String(localized: "All asleep.", comment: "Cat Naps: the puzzle is solved"))
                    .foregroundStyle(DesignTokens.Colors.ink)
            } else if !game.clashing.isEmpty {
                Text(String(localized: "Too close. They woke each other up.", comment: "Cat Naps: two cats in one row, column or cushion, or touching"))
                    .foregroundStyle(CatNapArt.clash)
            } else if game.catCount == 0 {
                Text(String(localized: "Tip: start with the smallest cushion.", comment: "Cat Naps: a first move, shown on an empty board"))
            } else {
                Text(String(localized: "\(game.catCount) of \(game.size) cats asleep", comment: "Cat Naps: cats placed so far"))
            }
        }
        .font(.system(.headline, weight: .bold))
        .foregroundStyle(DesignTokens.Colors.textSecondary)
        .multilineTextAlignment(.center)
        .frame(minHeight: 28)
        .contentTransition(.opacity)
        .animation(.snappy, value: game.clashing.isEmpty)
    }

    private func toolButton(_ title: String, symbol: String, locked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title)
                if locked { Image(systemName: "lock.fill").font(.caption.weight(.bold)) }
            }
            .font(.system(.headline, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(DesignTokens.Colors.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: - Results

    private var results: some View {
        let seconds = solve?.seconds ?? 0
        let hints = game?.hints ?? 0
        return GamePage(spacing: DesignTokens.Spacing.s) {
            topBar { EmptyView() }
        } picture: {
            CatMascot(mood: .proud, ground: .light)
                .frame(maxWidth: 170)
                .padding(.bottom, DesignTokens.Spacing.xs)
        } words: {
            Text(newBest
                 ? String(localized: "New best!", comment: "Game result: a new record")
                 : String(localized: "All asleep.", comment: "Cat Naps: the puzzle is solved"))
                .mcScaledFont(28, weight: .heavy, relativeTo: .title)
                .foregroundStyle(DesignTokens.Colors.ink)
            Text(Self.clock(seconds))
                .mcScaledFont(96, weight: .heavy, relativeTo: .largeTitle, monospacedDigits: true)
                .foregroundStyle(DesignTokens.Colors.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel(Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
            HStack(spacing: DesignTokens.Spacing.xs) {
                if hints == 0 {
                    chip(String(localized: "No hints", comment: "Cat Naps result: solved without help"))
                }
                if isUnlimited {
                    chip(String(localized: "\(unlimitedStats.solved) solved", comment: "Cat Naps unlimited result: puzzles solved at this level"))
                } else if isToday, streak > 0 {
                    chip(String(localized: "Streak \(streak)", comment: "Cat Naps: days in a row with the day's puzzle solved"))
                }
            }
            .frame(minHeight: 36)
            Spacer(minLength: 0)
            if isUnlimited {
                // One after another, for as long as they like.
                Button { openUnlimited(fresh: true, play: true) } label: {
                    HStack(spacing: 8) {
                        Text(String(localized: "Next puzzle", comment: "Cat Naps unlimited: a new board at the same level"))
                        unlimitedBadge
                    }
                    .mcInkButton()
                }
                .buttonStyle(PressScaleButtonStyle())
                HStack {
                    todayButton
                    doneButton
                }
            } else {
                // The next level up while there is one; after the hardest, another
                // puzzle — the moment a free account most wants one.
                if let next = level.next {
                    Button { open(number, level: next, play: true) } label: {
                        Text(String(localized: "Try \(next.title): \(next.size) × \(next.size)", comment: "Cat Naps result: play the next level up, with its board size"))
                            .mcInkButton()
                    }
                    .buttonStyle(PressScaleButtonStyle())
                } else {
                    Button { openUnlimited(fresh: true, play: true) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "infinity")
                            Text(String(localized: "Another puzzle", comment: "Cat Naps result: an unlimited puzzle after today's three"))
                            unlimitedBadge
                        }
                        .mcInkButton()
                    }
                    .buttonStyle(PressScaleButtonStyle())
                }
                ShareLink(item: shareText(seconds: seconds, hints: hints)) {
                    Label(String(localized: "Share", comment: "Cat Naps result: share the time"), systemImage: "square.and.arrow.up")
                        .mcSecondaryButton()
                }
                .buttonStyle(PressScaleButtonStyle())
                HStack {
                    if level.next == nil { archiveButton } else { unlimitedButton }
                    doneButton
                }
            }
            if !unlimitedOpen {
                Text(CatNapRecord.freeTriesLeft() > 0
                     ? String(localized: "Try unlimited puzzles free, then go Premium for a new board every time.", comment: "Cat Naps result: a free account with tries left")
                     : String(localized: "Premium: a new board every time, every past day, and hints.", comment: "Cat Naps result: a free account with no tries left"))
                    .font(.mcFootnote)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.bottom, DesignTokens.Spacing.xs)
    }

    private var doneButton: some View {
        Button { dismiss() } label: {
            Text(String(localized: "Done", comment: "Done button"))
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func shareText(seconds: Int, hints: Int) -> String {
        var lines = [String(localized: "Cat Naps #\(number) · \(level.title) · \(Self.clock(seconds))", comment: "Cat Naps share text: the puzzle number, the level and the time")]
        if hints == 0 {
            lines.append(String(localized: "No hints", comment: "Cat Naps result: solved without help"))
        }
        lines.append(String(repeating: "😴", count: game?.size ?? 0))
        return lines.joined(separator: "\n")
    }

    // MARK: - Pieces

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.ink)
            .padding(.horizontal, DesignTokens.Spacing.s)
            .frame(minHeight: 36)
            .background(DesignTokens.Colors.ink.opacity(0.08), in: Capsule())
    }

    private func puzzleLine(_ number: Int) -> String {
        let day = CatNapDay.date(of: number).formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        return String(localized: "No. \(number) · \(day)", comment: "Cat Naps: the puzzle's number and its day").uppercased()
    }

    private var boardLine: String {
        if isUnlimited {
            return String(localized: "Unlimited · \(level.title) · \(level.size) × \(level.size)", comment: "Cat Naps: over an unlimited board, its level and size").uppercased()
        }
        return String(localized: "No. \(number) · \(level.title) · \(level.size) × \(level.size)", comment: "Cat Naps: over the board, the puzzle's number, level and size").uppercased()
    }

    private func circleButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.yolk)
                .frame(width: 44, height: 44)
                .background(DesignTokens.Colors.ink, in: Circle())
        }
        .accessibilityLabel(label)
    }

    private func topBar<Center: View, Trailing: View>(@ViewBuilder center: () -> Center,
                                                      @ViewBuilder trailing: () -> Trailing = { EmptyView() }) -> some View {
        ZStack {
            center()
            HStack {
                circleButton(symbol: "xmark", label: String(localized: "Close", comment: "Close button")) { dismiss() }
                Spacer()
                trailing()
            }
        }
        .padding(.top, DesignTokens.Spacing.xs)
    }

    /// 1:42, or 1:02:09 for a long one.
    static func clock(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    // MARK: - Play

    private func start() {
        guard let game else { return }
        Haptics.impact(.medium)
        newBest = false
        solvedAt = nil
        if game.solved {
            // Again from the start, on a fresh board.
            self.game = CatNapGame(number: number, level: level, puzzle: game.puzzle)
        }
        self.game?.resume(at: .now)
        screen = .board
    }

    private func finish() {
        guard let game else { return }
        solvedAt = Date.now.timeIntervalSinceReferenceDate
        let seconds = max(1, Int(game.elapsed(at: .now).rounded()))
        CatNapRecord.setLastLevel(level)
        if isUnlimited {
            newBest = CatNapRecord.submitUnlimited(level: level, seconds: seconds) && unlimitedStats.solved > 0
            unlimitedStats = CatNapRecord.stats(level)
        } else {
            newBest = CatNapRecord.submit(number: number, level: level, seconds: seconds, hints: game.hints, onTheDay: isToday)
            solvedLevels = CatNapRecord.solves(number)
            CatNapRecord.forget(number, level: level)
        }
        // This round's time on the result, the record kept for the intro.
        solve = CatNapRecord.Solve(seconds: seconds, hints: game.hints, onTheDay: isToday)
        Haptics.notify(.success)
        CatVoice.shared.mrrp()
        Task {
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.8 : 2.2))
            if screen == .board { screen = .solved }
        }
    }

    private func pause(_ game: CatNapGame) {
        game.pause(at: .now)
        save(game)
    }

    private func save(_ game: CatNapGame) {
        guard !game.solved else { return }
        if game.isUntouched && game.elapsed(at: .now) < 1 {
            CatNapRecord.forget(game.number, level: game.level)
        } else {
            CatNapRecord.save(game.progress)
        }
    }
}

// MARK: - Past puzzles

/// Every day before today's, newest first, with a mark for each level solved.
struct CatNapArchiveView: View {
    let today: Int
    let pick: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array((1..<today).reversed()), id: \.self) { number in
                    Button { pick(number) } label: { row(number) }
                }
            }
            .mcList()
            .overlay {
                if today <= 1 {
                    ContentUnavailableView(String(localized: "No past puzzles yet", comment: "Cat Naps archive: empty"),
                                           systemImage: "calendar")
                }
            }
            .navigationTitle(String(localized: "Past puzzles", comment: "Cat Naps: opens the puzzles of earlier days"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done", comment: "Done button")) { dismiss() }
                }
            }
        }
    }

    private func row(_ number: Int) -> some View {
        let solved = CatNapRecord.solves(number)
        return HStack(spacing: DesignTokens.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "No. \(number)", comment: "Cat Naps archive: a puzzle's number"))
                    .font(.system(.headline, weight: .heavy).width(.expanded))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(CatNapDay.date(of: number).formatted(.dateTime.weekday(.wide).day().month()))
                    .font(.mcFootnote)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            Spacer()
            // One paw a level, filled once solved.
            HStack(spacing: 6) {
                ForEach(CatNapLevel.allCases) { level in
                    PawPrintShape()
                        .fill(solved[level] != nil ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textPrimary.opacity(0.15))
                        .frame(width: 16, height: 16)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(solved.isEmpty
                                ? String(localized: "Not solved", comment: "Cat Naps archive: no level of this day solved, VoiceOver")
                                : String(localized: "Solved: \(CatNapLevel.allCases.filter { solved[$0] != nil }.map(\.title).formatted(.list(type: .and)))", comment: "Cat Naps archive: the levels of this day solved, VoiceOver"))
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    CatNapGameView()
        .environment(AppContainer.preview(tier: .premium))
}
