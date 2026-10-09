import SwiftUI

// MARK: - Rules

/// "Catch the cat" as a mission: catch it so many times and the alarm is off. No
/// score and no clock of its own — the host's five minutes are the only limit — and
/// the cat is slower than in the game, for someone who is not awake yet. A tap that
/// misses only startles it into jumping.
///
/// On an open Duo there are two pages, and every jump takes the cat across the fold
/// to the other one.
@MainActor
@Observable
final class CatchMission {
    let required: Int
    private(set) var caught = 0
    /// Where the cat sits on its page, 0–1 in both directions.
    private(set) var position = CGPoint(x: 0.5, y: 0.5)
    /// Which page it is on: 0, or 1 on a spread.
    private(set) var page = 0
    /// Counts every jump, so the view can animate each one.
    private(set) var jumps = 0
    /// Whether the last jump crossed the fold.
    private(set) var crossed = false
    private(set) var jumpsAt: Date?
    private(set) var startledUntil: Date?
    private(set) var started = false

    /// One page, or two on an open Duo. Folding mid-mission brings the cat back to
    /// the page that is left.
    var pages = 1 {
        didSet { if page >= pages { page = pages - 1 } }
    }

    private var generator: any RandomNumberGenerator

    init(required: Int, generator: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.required = max(1, required)
        self.generator = generator
    }

    var isDone: Bool { caught >= required }

    /// Generous at first, a little quicker with each catch.
    var stayDuration: TimeInterval {
        #if DEBUG
        if DebugLaunch.slowCat { return 60 }
        #endif
        return max(1.0, 1.9 - Double(caught) * 0.08)
    }

    static let startleLength: TimeInterval = 0.7

    func isStartled(at now: Date) -> Bool {
        startledUntil.map { now < $0 } ?? false
    }

    func start(at now: Date) {
        guard !started else { return }
        started = true
        jumpsAt = now.addingTimeInterval(stayDuration)
    }

    /// The cat was tapped. Returns whether it counted.
    @discardableResult
    func catchCat(at now: Date) -> Bool {
        guard started, !isDone else { return false }
        caught += 1
        startledUntil = nil
        if isDone {
            jumpsAt = nil
        } else {
            jump(at: now)
        }
        return true
    }

    func miss(at now: Date) {
        guard started, !isDone else { return }
        startledUntil = now.addingTimeInterval(Self.startleLength)
        jump(at: now)
    }

    /// Moves time on: the cat jumps when its stay is up.
    func tick(at now: Date) {
        guard started, !isDone, let jumpsAt, now >= jumpsAt else { return }
        jump(at: now)
    }

    /// Somewhere new, well away from where it was. On a spread, always the other page.
    private func jump(at now: Date) {
        let nextPage = pages > 1 ? 1 - page : 0
        var next = position
        for _ in 0..<12 {
            next = CGPoint(x: Double.random(in: 0.1...0.9, using: &generator),
                           y: Double.random(in: 0.12...0.88, using: &generator))
            if nextPage != page || hypot(next.x - position.x, next.y - position.y) > 0.32 { break }
        }
        crossed = nextPage != page
        page = nextPage
        position = next
        jumps += 1
        jumpsAt = now.addingTimeInterval(stayDuration)
    }
}

// MARK: - Mission view

/// The cat will not sit still; catch it. On a phone that folds and is closed, the cat
/// has gone inside: the mission is to open it, and then to catch a cat that jumps
/// from page to page across the fold.
struct CatchCatMissionView: View {
    let config: MissionConfig
    var onSuccess: () -> Void

    @Environment(\.pageLayout) private var pageLayout
    @Environment(\.deviceFolds) private var deviceFolds
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mission: CatchMission

    init(config: MissionConfig, onSuccess: @escaping () -> Void) {
        self.config = config
        self.onSuccess = onSuccess
        let required: Int
        if case .catchCat(let n) = config { required = n } else { required = 8 }
        _mission = State(initialValue: CatchMission(required: required))
    }

    /// Closed, on a phone that opens: the cat is inside.
    private var mustOpen: Bool { deviceFolds && pageLayout == .single }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            if mustOpen {
                openPrompt.transition(.opacity)
            } else {
                board.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: mustOpen)
        .onChange(of: pageLayout, initial: true) { _, layout in
            mission.pages = layout == .spread ? 2 : 1
        }
        .task(id: mustOpen) {
            guard !mustOpen else { return }
            mission.start(at: .now)
            while !Task.isCancelled, !mission.isDone {
                mission.tick(at: .now)
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    // MARK: Closed

    /// Where the cat sits, empty, and its footprints going off to the edge the phone
    /// opens on.
    private var openPrompt: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            header
            Spacer(minLength: 0)
            Text(String(localized: "The cat went inside.", comment: "Catch the cat mission on a closed foldable phone: title"))
                .font(.mcTitle1)
                .foregroundStyle(DesignTokens.Colors.ink)
            Text(String(localized: "Open your phone to catch it.", comment: "Catch the cat mission on a closed foldable phone: what to do"))
                .font(.mcBody)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PawTrail()
                .frame(height: 110)
                .padding(.top, DesignTokens.Spacing.m)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Open, or one page

    private var board: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            HStack(alignment: .top, spacing: PageLayout.gutter) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    header
                    count
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if pageLayout == .spread {
                    hint.frame(maxWidth: .infinity, alignment: .leading).padding(.top, DesignTokens.Spacing.l)
                }
            }
            if pageLayout == .single { hint.frame(maxWidth: .infinity, alignment: .leading) }
            GeometryReader { geo in
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            mission.miss(at: .now)
                            Haptics.impact(.rigid)
                        }
                    cat.position(point(in: geo.size))
                        .animation(reduceMotion ? nil : .spring(response: mission.crossed ? 0.55 : 0.28, dampingFraction: 0.75),
                                   value: mission.jumps)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.top, DesignTokens.Spacing.l)
        .padding(.bottom, DesignTokens.Spacing.s)
    }

    /// The cat's place on the board: within its page, clear of the fold.
    private func point(in size: CGSize) -> CGPoint {
        let pages = CGFloat(mission.pages)
        let pageWidth = (size.width - PageLayout.gutter * (pages - 1)) / pages
        let inset: CGFloat = 50
        let x = CGFloat(mission.page) * (pageWidth + PageLayout.gutter) + inset + mission.position.x * (pageWidth - inset * 2)
        let y = inset + mission.position.y * max(size.height - inset * 2, 1)
        return CGPoint(x: x, y: y)
    }

    private var cat: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let startled = mission.isStartled(at: context.date)
            let left = mission.jumpsAt.map { $0.timeIntervalSince(context.date) } ?? 1
            Button {
                if mission.catchCat(at: .now) {
                    if mission.isDone {
                        Haptics.notify(.success)
                        Task { try? await Task.sleep(for: .milliseconds(350)); onSuccess() }
                    } else {
                        Haptics.impact(.medium)
                    }
                }
            } label: {
                CatStage(mood: mission.isDone ? .proud : (startled ? .startled : .awake), ground: .light, animated: startled)
                    .frame(width: 88)
                    // Across the fold is a leap; on the same page, a hop.
                    .catMotion(startled ? .startle : (mission.crossed ? .leap : .hop), trigger: mission.jumps, size: 78)
                    .background {
                        Circle().fill(DesignTokens.Colors.yolk).frame(width: 100, height: 100).offset(y: 6)
                    }
                    // Fidgets just before it goes, so a quick eye can see it coming.
                    .rotationEffect(.degrees(!reduceMotion && left < 0.35 ? sin(context.date.timeIntervalSinceReferenceDate * 60) * 7 : 0))
                    .padding(14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(String(localized: "Cat", comment: "Game: the cat to tap, VoiceOver"))
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: MissionKind.catchCat.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(DesignTokens.Colors.emberText)
            Text(MissionKind.catchCat.displayName)
                .font(.mcSubhead)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.top, DesignTokens.Spacing.xs)
    }

    private var count: some View {
        Text(verbatim: "\(mission.caught) / \(mission.required)")
            .font(.system(size: 44, weight: .bold).width(.expanded))
            .monospacedDigit()
            .foregroundStyle(DesignTokens.Colors.textPrimary)
            .contentTransition(.numericText(value: Double(mission.caught)))
            .animation(.snappy, value: mission.caught)
    }

    private var hint: some View {
        Text(pageLayout == .spread
             ? String(localized: "It jumps from page to page. Catch it.", comment: "Catch the cat mission on an open foldable phone: hint")
             : String(localized: "Tap the cat before it jumps away.", comment: "Catch the cat mission: hint"))
            .font(.mcCallout)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// An empty yolk disc and paw prints walking from it to the right edge, one after
/// another: the cat was here, and went that way. Still under Reduce Motion.
private struct PawTrail: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let prints = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = reduceMotion ? 3.0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let disc: CGFloat = 76
                let startX = disc + 18
                let endX = geo.size.width - 20
                ZStack(alignment: .topLeading) {
                    Circle()
                        .fill(DesignTokens.Colors.yolk)
                        .frame(width: disc, height: disc)
                        .position(x: disc / 2, y: geo.size.height / 2)
                    ForEach(0..<Self.prints, id: \.self) { i in
                        let u = CGFloat(i) / CGFloat(Self.prints - 1)
                        PawPrintShape()
                            .fill(DesignTokens.Colors.ink)
                            .frame(width: 20, height: 20)
                            // Toes towards the edge, left and right feet in turn.
                            .rotationEffect(.degrees(90))
                            .position(x: startX + (endX - startX) * u, y: geo.size.height / 2 + (i.isMultiple(of: 2) ? -11 : 11))
                            .opacity(Self.opacity(of: i, at: t))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Each print appears in turn and all fade together, every three seconds.
    private static func opacity(of i: Int, at t: Double) -> Double {
        let p = t.truncatingRemainder(dividingBy: 3.0)
        let appears = 0.25 + Double(i) * 0.3
        if p < appears { return 0.12 }
        if p > 2.6 { return 0.12 + 0.73 * max(0, (3.0 - p) / 0.4) }
        return 0.85
    }
}

#Preview("Catch the cat mission") {
    CatchCatMissionView(config: .defaultCatchCat, onSuccess: {})
}
