import SwiftUI
import StoreKit

/// Today: the next alarm under the cat, the week as paw prints, then the facts of the
/// morning — calendar, weather, sleep — and one line of focus.
///
/// The cat is the status, not decoration: asleep on its moon when tonight's alarm is
/// set, pleased once the morning is won, unimpressed after a miss, awake otherwise.
/// The line under it says the same in words. Nothing here asks for a permission on
/// its own; rows offer.
struct TodayView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.requestReview) private var requestReview
    @Environment(\.pageLayout) private var pageLayout
    @State private var viewModel: MorningBriefViewModel?
    @State private var playing: MorningGame?
    @State private var showingStreak = false
    /// Bumped once when Today opens on a won morning, so the cat leaps.
    @State private var celebrationCue = 0
    @State private var gameOfTheDayBest = MorningGame.ofTheDay().best()
    /// Bumped when a Duo opens: the cat stretches across the fold, then leaps home.
    @State private var foldCue = 0
    @State private var stretching = false
    @State private var landingCue = 0

    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        content
            .background(DesignTokens.Colors.background.ignoresSafeArea())
            .navigationTitle(String(localized: "Today", comment: "Tab label"))
            .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.large)
            .task {
                guard viewModel == nil else { return }
                let model = MorningBriefViewModel(
                    alarmManager: container.alarmManager,
                    healthKitService: container.healthKitService,
                    weatherService: container.weatherService,
                    calendarService: container.calendarService,
                    storageService: container.storageService
                )
                viewModel = model
                await model.load()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, let vm = viewModel else { return }
                Task { await vm.load() }
            }
            .onDisappear { viewModel?.saveFocus() }
            .onChange(of: wonStreak) { _, days in askForReviewIfDue(streak: days) }
            .task(id: wonStreak) {
                guard wonStreak > 0 else { return }
                try? await Task.sleep(for: .seconds(0.6))
                celebrationCue += 1
            }
            .onChange(of: pageLayout) { _, layout in
                // Asleep on its moon, the cat stays asleep: opening the phone at night
                // is not a reason to wake it.
                guard layout == .spread, case .loaded(let data) = viewModel?.state, heroMood(data) != .sleeping else { return }
                foldCue += 1
            }
            .onChange(of: stretching) { _, now in
                if !now { landingCue += 1 }
            }
            .morningGame($playing) { gameOfTheDayBest = MorningGame.ofTheDay().best() }
            .navigationDestination(isPresented: $showingStreak) { StreakView() }
            .onChange(of: container.streakPageRequested, initial: true) { _, requested in
                guard requested else { return }
                container.streakPageRequested = false
                showingStreak = true
            }
            #if DEBUG
            .onAppear {
                guard playing == nil else { return }
                if DebugLaunch.game { playing = .catchCat }
                if DebugLaunch.laser { playing = .laser }
                if DebugLaunch.boxes { playing = .boxes }
                if DebugLaunch.naps { playing = .catNaps }
            }
            #endif
    }

    // MARK: - Game

    /// One of the morning games, a different one each day, and the way to the rest.
    /// Not missions: they are here to play, never in the way of an alarm.
    private var gameSection: some View {
        let game = MorningGame.ofTheDay()
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            MCSectionTitle(String(localized: "Today's game", comment: "Today section title: the game of the day")) {
                Button {
                    container.selectedTabIndex = 3
                } label: {
                    Text(String(localized: "All games", comment: "Today: opens the Play tab"))
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.accent)
                        .frame(minHeight: 44)
                }
            }
            GameCard(game: game, best: gameOfTheDayBest) { playing = game }
        }
    }

    // MARK: - Review

    private var wonStreak: Int {
        guard case .loaded(let data) = viewModel?.state, data.wokeToday else { return 0 }
        return data.streakDays ?? 0
    }

    /// Asks for a rating on a good morning, never a bad one: only on the day a mission
    /// was just won, and only when the streak reaches 3, 7 or 30 — once for each. The
    /// system decides whether the sheet actually shows, and caps it at three a year.
    private func askForReviewIfDue(streak: Int) {
        guard let milestone = ReviewMilestones.due(for: streak) else { return }
        ReviewMilestones.markAsked(milestone)
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            requestReview()
        }
    }

    // MARK: - State routing

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state ?? .idle {
        case .idle, .loading:
            ProgressView()
                .tint(DesignTokens.Colors.nightTextSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(String(localized: "Preparing your morning brief…", comment: "Morning Brief loading state"))
        case .loaded(let data):
            page(data)
        case .empty:
            page(MorningBriefData(nextAlarm: nil, nextFireDate: nil, sleepDuration: nil,
                                  weather: nil, calendarEvent: nil, streakDays: nil))
        case .failure:
            failureView
        }
    }

    @ViewBuilder
    private func page(_ data: MorningBriefData) -> some View {
        if pageLayout == .spread {
            // Open on a Duo: the night and the streak on the left page, the day on the
            // right, and the cat free to stretch across the fold.
            Spread {
                column { hero(data, tall: true); streakSection(data) }
            } right: {
                column { gameSection; todaySection(data); focusSection }
            }
            .overlay(alignment: .bottom) {
                FoldStretch(cue: foldCue, playing: $stretching)
                    .padding(.bottom, DesignTokens.Spacing.xs)
            }
        } else {
            column {
                hero(data)
                streakSection(data)
                gameSection
                todaySection(data)
                focusSection
            }
        }
    }

    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.l, content: content)
                .padding(.horizontal, DesignTokens.Spacing.s)
                .padding(.top, DesignTokens.Spacing.xs)
                .padding(.bottom, DesignTokens.Spacing.l)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Hero

    /// The band: the next alarm and the cat saying how things stand. Yolk by day, ink
    /// at night while the cat sleeps on its moon — the same time of day you are in.
    /// In the dark appearance it is always ink, with the time in yolk: a page-wide
    /// block of yellow is a lamp switched on in a dark room.
    /// `tall` is the left page of an open Duo: more room, a bigger cat.
    private func hero(_ data: MorningBriefData, tall: Bool = false) -> some View {
        let mood = heroMood(data)
        let night = mood == .sleeping || colorScheme == .dark
        let tone = BandTone(night: night)
        let catWidth: CGFloat = (mood == .sleeping ? 132 : 104) * (tall ? 1.3 : 1)
        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            heroText(data, tone: tone)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.s) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    if let alarm = data.nextAlarm, let summary = alarmSummary(alarm) {
                        Text(summary)
                            .font(.mcCallout)
                            .foregroundStyle(tone.secondary)
                            .lineLimit(2)
                    }
                    if let line = voiceLine(for: mood, data: data) {
                        Text(line)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(tone.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, DesignTokens.Spacing.xs)
                if !stacked {
                    // The cat sits on the band, the whole of it in view.
                    // Tap it: it hops, and every fifth tap it somersaults. On a won
                    // morning it leaps by itself when the page opens.
                    TappableCat(mood: mood, ground: night ? .dark : .light, width: catWidth,
                                cue: (mood == .proud ? celebrationCue : 0) + landingCue)
                        // Out on the fold, stretching: there is only one cat.
                        .opacity(stretching ? 0 : 1)
                        .animation(.easeOut(duration: 0.2), value: stretching)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, DesignTokens.Spacing.s)
        .padding(.bottom, DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: tall ? 340 : 236, alignment: .topLeading)
        .background(night ? DesignTokens.Colors.nightBand : DesignTokens.Colors.dayBand)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous))
    }

    /// Type colours for the band, which is yolk or ink whatever the appearance.
    private struct BandTone {
        let night: Bool
        var primary: Color { night ? DesignTokens.Colors.nightText : DesignTokens.Colors.ink }
        var secondary: Color { night ? DesignTokens.Colors.nightTextSecondary : DesignTokens.Colors.onYolkSecondary }
        var accent: Color { night ? DesignTokens.Colors.yolk : DesignTokens.Colors.ink }
        /// The big time: ink on yolk, yolk on ink.
        var time: Color { night ? DesignTokens.Colors.yolk : DesignTokens.Colors.ink }
    }

    @ViewBuilder
    private func heroText(_ data: MorningBriefData, tone: BandTone) -> some View {
        if let alarm = data.nextAlarm, let fireDate = data.nextFireDate {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(NextAlarmPhrase.relativeDay(for: fireDate).capitalized(with: .current))
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(tone.secondary)
                    Spacer()
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(NextAlarmPhrase.ringsIn(fireDate, now: context.date))
                            .font(.system(.subheadline, weight: .bold))
                            .foregroundStyle(tone.accent)
                    }
                }
                AlarmTimeText(time: alarm.wallClockTime, size: 76, weight: .bold,
                              color: tone.time, periodColor: tone.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(String(localized: "No alarm set", comment: "Next alarm card, empty"))
                    .font(.mcTitle2)
                    .foregroundStyle(tone.primary)
                Text(String(localized: "Tomorrow starts when you say so.", comment: "Next alarm card, empty, detail"))
                    .font(.mcCallout)
                    .foregroundStyle(tone.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    container.selectedTabIndex = 1
                } label: {
                    Text(String(localized: "Set an alarm", comment: "Opens the Alarms tab"))
                        .font(.mcButton)
                        .foregroundStyle(tone.night ? DesignTokens.Colors.ink : DesignTokens.Colors.yolk)
                        .padding(.horizontal, DesignTokens.Spacing.m)
                        .frame(minHeight: 46)
                        .background(tone.night ? DesignTokens.Colors.yolk : DesignTokens.Colors.ink,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())
                .padding(.top, DesignTokens.Spacing.xxs)
            }
        }
    }

    /// How the cat is doing. Follows the morning first, then the clock.
    private func heroMood(_ data: MorningBriefData) -> CatMascot.Mood {
        #if DEBUG
        if let forced = DebugLaunch.mood { return forced }
        #endif
        if data.wokeToday { return .proud }
        if data.week.last(where: { $0.outcome == .won || $0.outcome == .missed })?.outcome == .missed {
            return .grumpy
        }
        guard data.nextAlarm != nil else { return .awake }
        let hour = Calendar.current.component(.hour, from: .now)
        return (hour >= 19 || hour < 5) ? .sleeping : .awake
    }

    private func voiceLine(for mood: CatMascot.Mood, data: MorningBriefData) -> String? {
        switch mood {
        case .sleeping:
            return String(localized: "Sleep well. I'll wake you.", comment: "Today hero line while an alarm is set for the night; the cat speaking")
        case .proud:
            guard let days = data.streakDays, days > 0 else { return nil }
            return String(localized: "Day \(days) of your streak.", comment: "Home hero detail, streak")
        case .grumpy:
            return String(localized: "Missed the last one. Tomorrow counts.", comment: "Today hero line after a missed morning")
        case .awake, .ringing, .startled, .sad, .yawning:
            return nil
        }
    }

    /// "Wake up · Math, Shake": what the alarm is and what turns it off.
    private func alarmSummary(_ alarm: Alarm) -> String? {
        var parts: [String] = []
        if !alarm.label.isEmpty { parts.append(alarm.label) }
        let missions = alarm.missions.map(\.displayName).joined(separator: ", ")
        if !missions.isEmpty { parts.append(missions) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Streak

    @ViewBuilder
    private func streakSection(_ data: MorningBriefData) -> some View {
        if !data.week.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                MCSectionTitle(String(localized: "Streak", comment: "Streak row title on Today"))
                // The whole card opens the streak page.
                Button { showingStreak = true } label: {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                    if let days = data.streakDays, days > 0 {
                        let streak = CountPhrase(String(localized: "\(days) days in a row", comment: "Streak on Today and Progress: the number is set large and the words small beside it. Keep the number in the text; the app cuts the phrase where it sits."), count: days)
                        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
                            if !streak.before.isEmpty {
                                Text(streak.before)
                                    .font(.mcCallout)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            Text(streak.number)
                                .mcScaledFont(40, weight: .bold)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            Text(streak.after)
                                .font(.mcCallout)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        Text(String(localized: "Complete your morning mission to start your streak.", comment: "Progress empty state message"))
                            .font(.mcCallout)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    WeekStrip(days: data.week)
                    streakFooter(data)
                }
                .padding(DesignTokens.Spacing.s)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .padding(DesignTokens.Spacing.s)
                        .accessibilityHidden(true)
                }
                .background(DesignTokens.Colors.surfacePrimary,
                            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
                }
                .buttonStyle(PressScaleButtonStyle())
                .accessibilityHint(String(localized: "Opens your streak, the cat's tricks and this month", comment: "Today streak card, VoiceOver hint"))
            }
        }
    }

    /// Under the week: the next trick the cat will learn, and the covers it holds.
    @ViewBuilder
    private func streakFooter(_ data: MorningBriefData) -> some View {
        let next = CatTrick.next(afterBest: data.bestStreak)
        if next != nil || data.covers > 0 {
            HStack(spacing: DesignTokens.Spacing.xs) {
                if let next {
                    Text(String(localized: "Next trick at \(next.days): \(next.name)", comment: "Today streak card: the next trick the cat learns and the streak it needs"))
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if data.covers > 0 {
                    HStack(spacing: 3) {
                        ForEach(0..<data.covers, id: \.self) { _ in
                            DayGlyph(outcome: .covered).frame(width: 18, height: 18)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(String(localized: "Covers: \(data.covers)", comment: "Today streak card: how many missed mornings the cat can cover, VoiceOver"))
                }
            }
        }
    }

    // MARK: - Today

    @ViewBuilder
    private func todaySection(_ data: MorningBriefData) -> some View {
        let hasEvent = data.calendarEvent != nil
        let offersCalendar = !hasEvent && viewModel?.calendarPermission == .notDetermined
        let hasWeather = data.weather != nil
        let offersWeather = !hasWeather && (viewModel?.locationPermission == .notDetermined
                                            || viewModel?.weatherNeedsLocationPermission == true)
        let hasSleep = data.sleepDuration != nil

        if hasEvent || offersCalendar || hasWeather || offersWeather || hasSleep {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                MCSectionTitle(String(localized: "Today", comment: "Today card title"))
                let rows = todayRows(data, offersCalendar: offersCalendar, offersWeather: offersWeather)
                VStack(spacing: 0) {
                    ForEach(rows.indices, id: \.self) { index in
                        if index > 0 {
                            Divider().overlay(DesignTokens.Colors.separator).padding(.leading, 52)
                        }
                        rows[index]
                    }
                }
                .background(DesignTokens.Colors.surfacePrimary,
                            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
            }
        }
    }

    /// The rows of the Today group, in order: calendar, weather, sleep. Each either
    /// shows its fact or offers to fetch it.
    private func todayRows(_ data: MorningBriefData, offersCalendar: Bool, offersWeather: Bool) -> [AnyView] {
        var rows: [AnyView] = []
        if let event = data.calendarEvent {
            rows.append(AnyView(infoRow(symbol: "calendar", title: event.title) {
                Text(event.startDate, style: .time)
            }))
        } else if offersCalendar {
            rows.append(AnyView(offerRow(
                symbol: "calendar",
                String(localized: "Your first event of the day", comment: "Calendar offer row"),
                action: String(localized: "Connect Calendar", comment: "Requests calendar access")
            ) { Task { await viewModel?.enableCalendar() } }))
        }
        if let weather = data.weather {
            rows.append(AnyView(NavigationLink { WeatherDetailView(weather: weather).hidesInkTabBar() } label: {
                infoRow(symbol: weather.symbolName, title: "\(WeatherUnits.degrees(weather.temperature))°  \(weather.description)", chevron: true) {
                    Text(String(localized: "H:\(WeatherUnits.degrees(weather.high))° L:\(WeatherUnits.degrees(weather.low))°", comment: "Daily high and low temperature"))
                }
            }
            .buttonStyle(.plain)))
        } else if offersWeather {
            if viewModel?.weatherNeedsLocationPermission == true {
                rows.append(AnyView(offerRow(
                    symbol: "location.slash",
                    String(localized: "Weather needs location, which is off", comment: "Weather offer row, permission refused"),
                    action: String(localized: "Turn on", comment: "Opens Settings to grant location")
                ) { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }))
            } else {
                rows.append(AnyView(offerRow(
                    symbol: "cloud.sun",
                    String(localized: "The weather where you are", comment: "Weather offer row"),
                    action: String(localized: "Add weather", comment: "Requests location so weather can load")
                ) { Task { await viewModel?.enableWeather() } }))
            }
        }
        if let sleep = data.sleepDuration {
            rows.append(AnyView(infoRow(symbol: "bed.double", title: String(localized: "Slept \(formattedSleepDuration(sleep))", comment: "Sleep row on Home")) {
                EmptyView()
            }))
        }
        return rows
    }

    private func infoRow<Trailing: View>(symbol: String, title: String, chevron: Bool = false,
                                         @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DesignTokens.Colors.accent)
                .frame(width: 24)
            Text(title)
                .font(.mcBody)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(2)
            Spacer(minLength: DesignTokens.Spacing.xs)
            trailing()
                .font(.mcCallout)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func offerRow(symbol: String, _ text: String, action: String, perform: @escaping () -> Void) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DesignTokens.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DesignTokens.Spacing.sm))
        return layout {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .frame(width: 24)
                Text(text)
                    .font(.mcBody)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !stacked { Spacer(minLength: DesignTokens.Spacing.xs) }
            Button(action, action: perform)
                .font(.system(.subheadline, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.accent)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(minHeight: 52)
    }

    // MARK: - Focus

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            MCSectionTitle(String(localized: "Focus", comment: "Today's Focus title"))
            TextField(
                String(localized: "What matters most today?", comment: "Today's Focus empty state"),
                text: focusBinding,
                axis: .vertical
            )
            .font(.mcBody)
            .foregroundStyle(DesignTokens.Colors.textPrimary)
            .submitLabel(.done)
            .onSubmit { viewModel?.saveFocus() }
            .onChange(of: viewModel?.focusText ?? "") { _, _ in viewModel?.focusSaveFailed = false }
            .padding(DesignTokens.Spacing.s)
            .frame(minHeight: 52)
            .background(DesignTokens.Colors.surfacePrimary,
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
            if viewModel?.focusSaveFailed == true {
                Text(String(localized: "Focus could not be saved.", comment: "Today's Focus save error"))
                    .font(.mcFootnote)
                    .foregroundStyle(DesignTokens.Colors.destructive)
            }
        }
    }

    // MARK: - Failure

    private var failureView: some View {
        ContentUnavailableView {
            Label(String(localized: "Morning Brief unavailable", comment: "Morning Brief error title"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(String(localized: "We couldn't load your brief. Please try again.", comment: "Morning Brief error detail"))
        } actions: {
            Button(String(localized: "Try Again", comment: "Morning Brief retry button")) {
                Task { await viewModel?.load() }
            }
        }
        .background(DesignTokens.Colors.background)
    }

    // MARK: - Helpers

    private var focusBinding: Binding<String> {
        Binding(get: { viewModel?.focusText ?? "" }, set: { viewModel?.focusText = $0 })
    }

    private func formattedSleepDuration(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int(duration / 60))
        return String(localized: "\(totalMinutes / 60) hr \(totalMinutes % 60) min", comment: "Sleep duration")
    }
}

#Preview {
    NavigationStack { TodayView() }
        .environment(AppContainer.preview())
}
