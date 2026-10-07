import SwiftUI

/// The streak, opened from its card on Today: the number on an ink card with the cat,
/// the tricks long streaks teach it, the covers it holds for a missed morning, and
/// this month as paw prints. A share button makes a card of it for anyone else.
struct StreakView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.pageLayout) private var pageLayout
    @Environment(\.catDressing) private var dressing
    @State private var viewModel: StreakViewModel?
    @State private var shareImage: Image?

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            content
        }
        .navigationTitle(String(localized: "Streak", comment: "Streak row title on Today"))
        .navigationBarTitleDisplayMode(.inline)
        .hidesInkTabBar()
        .toolbar {
            if let shareImage {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareImage, preview: SharePreview(
                        String(localized: "My morning streak", comment: "Share sheet title for the streak card"),
                        image: shareImage
                    )) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(String(localized: "Share your streak", comment: "Streak page share button, VoiceOver"))
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = StreakViewModel(streakManager: container.streakManager, alarmManager: container.alarmManager)
            }
            await viewModel?.load()
        }
        .onChange(of: viewModel?.state.loadedValue) { _, data in
            guard let data, data.currentStreak > 0 else { shareImage = nil; return }
            shareImage = StreakShareCard.image(streak: data.currentStreak, week: data.week, dressing: dressing)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state ?? .idle {
        case .idle, .loading, .empty:
            SwiftUI.ProgressView()
        case .loaded(let data):
            loaded(data)
        case .failure(let error):
            ContentUnavailableView {
                Label(String(localized: "Progress unavailable", comment: "Progress error title"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button(String(localized: "Try Again", comment: "Progress retry button")) {
                    Task { await viewModel?.load() }
                }
            }
        }
    }

    @ViewBuilder
    private func loaded(_ data: StreakData) -> some View {
        if pageLayout == .spread {
            // Open on a Duo: the streak and what it earns on the left page, the
            // covers and the month on the right.
            Spread {
                list { heroSection(data); tricksSection(data) }
            } right: {
                list { coversSection(data); monthSection(data) }
            }
        } else {
            list {
                heroSection(data)
                tricksSection(data)
                coversSection(data)
                monthSection(data)
            }
        }
    }

    private func list<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        List { content() }
            .listStyle(.insetGrouped)
            .mcList()
    }

    // MARK: - The number

    private func heroSection(_ data: StreakData) -> some View {
        Section {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.xs) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    if data.bestStreak == 0 {
                        Text(String(localized: "No streak yet", comment: "Progress empty state title"))
                            .mcScaledFont(28, weight: .heavy, relativeTo: .title)
                            .foregroundStyle(DesignTokens.Colors.onTile)
                        Text(String(localized: "Complete your morning mission to start your streak.", comment: "Progress empty state message"))
                            .font(.mcFootnote)
                            .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        let streak = CountPhrase(String(localized: "\(data.currentStreak) days in a row", comment: "Streak on Today and Progress: the number is set large and the words small beside it. Keep the number in the text; the app cuts the phrase where it sits."), count: data.currentStreak)
                        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
                            if !streak.before.isEmpty {
                                Text(streak.before)
                                    .font(.system(.callout, weight: .semibold))
                                    .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                            }
                            Text(streak.number)
                                .mcScaledFont(64, weight: .heavy)
                                .foregroundStyle(DesignTokens.Colors.yolk)
                            Text(streak.after)
                                .font(.system(.callout, weight: .semibold))
                                .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                        }
                        Text(verbatim: [
                            String(localized: "Best \(data.bestStreak)", comment: "Progress streak card: the longest streak so far"),
                            String(localized: "\(data.wonThisMonth) mornings this month", comment: "Progress streak card: mornings won this month"),
                        ].joined(separator: " · "))
                            .font(.mcFootnote)
                            .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                // Pleased while it lasts, sad once it is lost, curious before the first.
                TappableCat(mood: data.bestStreak == 0 ? .awake : (data.currentStreak > 0 ? .proud : .sad),
                            ground: .dark, width: 104)
            }
            .padding(.vertical, DesignTokens.Spacing.xs)
            .listRowBackground(DesignTokens.Colors.tile)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 16))
        }
    }

    // MARK: - Tricks

    private func tricksSection(_ data: StreakData) -> some View {
        Section {
            TricksPanel(best: data.bestStreak, current: data.currentStreak)
                .padding(.vertical, DesignTokens.Spacing.xs)
        } header: {
            Text(String(localized: "The cat's tricks", comment: "Streak page section: tricks earned by long streaks"))
        } footer: {
            Text(String(localized: "A streak teaches the cat a trick at 3, 7, 14, 30, 60 and 100 mornings. It keeps them, whatever happens to the streak.", comment: "Streak page: how tricks are earned"))
        }
        .mcRows()
    }

    // MARK: - Covers

    private func coversSection(_ data: StreakData) -> some View {
        Section {
            CoversPanel(covers: data.covers, nextCoverAt: data.nextCoverAt)
                .padding(.vertical, DesignTokens.Spacing.xs)
        } header: {
            Text(String(localized: "Covers", comment: "Streak page section: streak covers"))
        } footer: {
            Text(String(localized: "One for every 7 mornings in a row, up to 2. A missed morning uses one, and your streak goes on.", comment: "Streak page: how covers are earned and used"))
        }
        .mcRows()
    }

    // MARK: - Month

    private func monthSection(_ data: StreakData) -> some View {
        Section {
            MonthGrid(days: data.month)
                .padding(.vertical, DesignTokens.Spacing.xs)
            legend
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(Date.now, format: .dateTime.month(.wide))
                Spacer()
                Text(String(localized: "\(data.wonThisMonth) / \(data.scheduledThisMonth) scheduled", comment: "Mornings won out of scheduled this month"))
            }
        } footer: {
            Text(String(localized: "Rest days don't break your streak", comment: "Progress note title"))
        }
        .mcRows()
    }

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.s) { legendItems; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) { legendItems }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var legendItems: some View {
        legendItem(.won, String(localized: "Woke up", comment: "Calendar legend"))
        legendItem(.covered, String(localized: "Covered", comment: "Calendar legend: a missed morning the cat covered for"))
        legendItem(.missed, String(localized: "Missed", comment: "Calendar legend"))
        legendItem(.rest, String(localized: "Rest", comment: "Calendar legend"))
    }

    private func legendItem(_ outcome: DayOutcome, _ label: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xxs + 2) {
            DayGlyph(outcome: outcome).frame(width: 16, height: 16)
            Text(label)
                .font(.mcFootnote)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }
}

private extension FeatureLoadState where T == StreakData {
    var loadedValue: StreakData? {
        if case .loaded(let data) = self { return data }
        return nil
    }
}

// MARK: - Tricks panel

/// The six tricks as a row of badges, learned ones in yolk, the next one ringed, the
/// rest grey; under them the one chosen — the next to learn, until another is tapped.
struct TricksPanel: View {
    let best: Int
    let current: Int
    @State private var chosen: CatTrick?

    private var shown: CatTrick { chosen ?? CatTrick.next(afterBest: best) ?? .medal }
    private var next: CatTrick? { CatTrick.next(afterBest: best) }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack(spacing: 0) {
                ForEach(CatTrick.allCases) { trick in
                    badge(trick).frame(maxWidth: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(shown.name)
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Spacer()
                    if best >= shown.days {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                            Text(String(localized: "Learned", comment: "Streak page: a trick the cat knows"))
                        }
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.accent)
                    }
                }
                Text(shown.detail)
                    .font(.mcFootnote)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if best < shown.days {
                    progress(to: shown)
                        .padding(.top, DesignTokens.Spacing.xxs)
                }
            }
            .animation(.snappy, value: shown)
        }
    }

    private func badge(_ trick: CatTrick) -> some View {
        let learned = best >= trick.days
        let isNext = trick == next
        let isShown = trick == shown
        return Button {
            Haptics.selection()
            chosen = trick
        } label: {
            ZStack {
                if learned {
                    Circle().fill(DesignTokens.Colors.yolk)
                } else if isNext {
                    Circle().strokeBorder(DesignTokens.Colors.accent, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                } else {
                    Circle().fill(DesignTokens.Colors.surfaceSecondary)
                }
                Text(trick.days, format: .number)
                    .font(.system(size: trick.days >= 100 ? 13 : 16, weight: .heavy).width(.expanded))
                    .foregroundStyle(learned ? DesignTokens.Colors.ink : (isNext ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textTertiary))
            }
            .frame(width: 44, height: 44)
            .padding(3)
            .overlay {
                if isShown {
                    Circle().strokeBorder(DesignTokens.Colors.textPrimary, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(trick.name)
        .accessibilityValue(learned
            ? String(localized: "Learned", comment: "Streak page: a trick the cat knows")
            : String(localized: "At \(trick.days) mornings in a row", comment: "Streak page: when a trick is learned, VoiceOver"))
        .accessibilityAddTraits(isShown ? [.isButton, .isSelected] : .isButton)
    }

    /// How far the current streak has come towards the trick.
    private func progress(to trick: CatTrick) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignTokens.Colors.textPrimary.opacity(0.1))
                    Capsule()
                        .fill(DesignTokens.Colors.accent)
                        .frame(width: geo.size.width * min(1, CGFloat(current) / CGFloat(trick.days)))
                }
            }
            .frame(height: 8)
            Text(String(localized: "\(current) of \(trick.days) mornings in a row", comment: "Streak page: progress towards a trick"))
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Covers panel

/// The covers the cat holds, as paw prints: filled for one ready, outlined for an
/// empty place.
struct CoversPanel: View {
    let covers: Int
    let nextCoverAt: Int?

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.s) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(0..<StreakRecord.maxCovers, id: \.self) { i in
                    Group {
                        if i < covers {
                            PawPrintShape().fill(DesignTokens.Colors.streakFlame)
                        } else {
                            PawPrintShape().stroke(DesignTokens.Colors.textTertiary, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 30, height: 30)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(covers > 0
                     ? String(localized: "The cat has your back", comment: "Streak page: covers are ready")
                     : String(localized: "No covers yet", comment: "Streak page: no covers"))
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(String(localized: "\(covers) of \(StreakRecord.maxCovers) ready", comment: "Streak page: covers ready out of the most there can be"))
                    .font(.mcFootnote)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                if let nextCoverAt {
                    Text(String(localized: "Next at \(nextCoverAt) in a row", comment: "Streak page: the streak at which the next cover is earned"))
                        .font(.mcFootnote)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Month grid

/// A calendar month as glyphs. Weekday headers follow the calendar's first weekday;
/// leading blanks pad the first row.
struct MonthGrid: View {
    let days: [DayCell]
    var calendar: Calendar = .current

    /// Week rows built eagerly. A lazy grid inside a self-sizing List row never settles
    /// on a height and trips UIKit's layout-loop trap (crashed on 2026-10-01).
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.offset) { item in
                    Text(item.element)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        Group {
                            if let day {
                                VStack(spacing: 2) {
                                    DayGlyph(outcome: day.outcome)
                                        .frame(width: 24, height: 24)
                                    Text(day.date, format: .dateTime.day())
                                        .font(.system(.caption))
                                        .foregroundStyle(day.outcome == .upcoming
                                                         ? DesignTokens.Colors.textTertiary
                                                         : DesignTokens.Colors.textSecondary)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(label(for: day))
                            } else {
                                Color.clear.frame(height: 22)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// The month padded to whole weeks: leading blanks, the days, trailing blanks.
    private var weeks: [[DayCell?]] {
        var cells: [DayCell?] = Array(repeating: nil, count: leadingBlanks) + days.map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    private var weekdaySymbols: [(offset: Int, element: String)] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { i in (i, symbols[(first + i) % 7]) }
    }

    private var leadingBlanks: Int {
        guard let first = days.first?.date else { return 0 }
        let weekday = calendar.component(.weekday, from: first) - 1
        return (weekday - (calendar.firstWeekday - 1) + 7) % 7
    }

    private func label(for day: DayCell) -> String {
        let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        switch day.outcome {
        case .won:      return String(localized: "\(date), woke up", comment: "Calendar day, VoiceOver")
        case .missed:   return String(localized: "\(date), missed", comment: "Calendar day, VoiceOver")
        case .rest:     return String(localized: "\(date), rest day", comment: "Calendar day, VoiceOver")
        case .covered:  return String(localized: "\(date), the cat covered for you", comment: "Calendar day, VoiceOver: a missed morning a streak cover saved")
        case .today:    return String(localized: "\(date), today", comment: "Calendar day, VoiceOver")
        case .upcoming: return String(localized: "\(date), upcoming", comment: "Calendar day, VoiceOver")
        }
    }
}

#Preview {
    NavigationStack { StreakView() }
        .environment(AppContainer.preview())
}
