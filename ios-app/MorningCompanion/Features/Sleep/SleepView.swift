import SwiftUI

struct SleepView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.pageLayout) private var pageLayout

    @State private var viewModel: SleepViewModel?
    @State private var paywallFeature: PremiumFeature?
    @State private var windDown: WindDownView.Stage?

    var body: some View {
        mainContent
        .background(DesignTokens.Colors.background.ignoresSafeArea())
        .navigationTitle(String(localized: "Sleep", comment: "Sleep navigation title"))
        .navigationBarTitleDisplayMode(container.sleepTrackingService.isActive ? .inline : .large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let vm = viewModel, !container.sleepTrackingService.isActive {
                    if container.isPremium {
                        NavigationLink {
                            SleepReportView(
                                localSessions: vm.completedSessions,
                                healthEntries: vm.healthEntries
                            )
                            .hidesInkTabBar()
                        } label: {
                            Text(String(localized: "History", comment: "Sleep history button"))
                        }
                    } else {
                        Button {
                            paywallFeature = .sleepHistory
                        } label: {
                            Label(String(localized: "History", comment: "Sleep history button"), systemImage: "lock.fill")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
        }
        .paywall(for: $paywallFeature)
        .fullScreenCover(item: $windDown) { stage in
            WindDownView(
                storage: container.storageService,
                tracking: container.sleepTrackingService,
                nextAlarmDate: viewModel?.nextAlarmDate,
                initialStage: stage
            ) {
                Task {
                    await viewModel?.startTracking(withNoiseMonitoring: container.sleepTrackingService.noiseMonitoringEnabled)
                }
            }
            .readsPageLayout()
            .nightAppearance()
        }
        .onChange(of: container.windDownRequested, initial: true) { _, requested in
            guard requested else { return }
            container.windDownRequested = false
            if !container.sleepTrackingService.isActive { windDown = .setup }
        }
        .sheet(isPresented: Binding(
            get: { viewModel?.showingResult == true },
            set: { if !$0 { viewModel?.showingResult = false } }
        )) {
            if let session = viewModel?.completedSession {
                SleepResultView(session: session) {
                    viewModel?.showingResult = false
                }
                .appAppearance()
            }
        }
        .task {
            if viewModel == nil {
                let vm = SleepViewModel(
                    healthKitService: container.healthKitService,
                    trackingService: container.sleepTrackingService,
                    alarmManager: container.alarmManager,
                    storageService: container.storageService
                )
                viewModel = vm
                #if DEBUG
                switch DebugLaunch.windDown {
                case "setup": windDown = .setup
                case "breathing": windDown = .breathing(started: .now.addingTimeInterval(-1.5), length: 300)
                case "done": windDown = .done
                default: break
                }
                #endif
                await vm.load()
                if case .loaded(let data) = vm.healthState {
                    await container.refreshWidgetSnapshot(sleepDuration: data.lastNightDuration, sleepHistory: vm.sleepHistory)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel?.refreshHealthData() }
            }
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        let service = container.sleepTrackingService
        if service.isActive {
            SleepActiveView(
                service: service,
                nextAlarmText: viewModel?.nextAlarmText,
                nextAlarmDate: viewModel?.nextAlarmDate,
                onStop: { session in viewModel?.onSessionCompleted(session) }
            )
        } else if pageLayout == .spread {
            // Open on a Duo: tonight on the left page, last night on the right.
            Spread {
                List {
                    heroSection
                    tonightSection.mcRows()
                }
                .listStyle(.insetGrouped)
                .mcList()
            } right: {
                List { lastNightSection.mcRows() }
                    .listStyle(.insetGrouped)
                    .mcList()
            }
        } else {
            // One screen. The clock decides only what comes first: last night in the
            // morning, tonight the rest of the day.
            List {
                heroSection
                if viewModel?.viewMode == .morning {
                    lastNightSection.mcRows()
                    tonightSection.mcRows()
                } else {
                    tonightSection.mcRows()
                    lastNightSection.mcRows()
                }
            }
            .listStyle(.insetGrouped)
            .mcList()
        }
    }

    // MARK: - Hero

    /// The night card: the alarm tonight ends with, the cat already asleep on its moon,
    /// and the button that starts tracking.
    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                HStack(alignment: .center, spacing: DesignTokens.Spacing.xs) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(String(localized: "Tonight", comment: "Sleep screen section: setting up tonight"))
                            .font(.mcHeadline)
                            .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                        Text(tonightSummary)
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(DesignTokens.Colors.nightText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    CatMascot(mood: .sleeping, ground: .dark)
                        .frame(width: 128)
                        .padding(.trailing, -8)
                }
                startButton
                windDownButton
            }
            .padding(.vertical, DesignTokens.Spacing.xs)
            .listRowBackground(DesignTokens.Colors.nightBand)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 16, trailing: 20))
        }
    }

    // MARK: - Tonight

    /// Setting up tonight: the sound and the options. The alarm and the start button
    /// are on the card above.
    @ViewBuilder
    private var tonightSection: some View {
        Section {
            soundPicker
            noiseMicRow
            bedtimeReminderRows
        } header: {
            Text(String(localized: "Tonight", comment: "Sleep screen section: setting up tonight"))
        }
    }

    /// "Alarm at 07:00. Sleep now for 7h 40m." in the evening; the alarm alone at
    /// other times; a plain "No alarm set" when there is none.
    private var tonightSummary: String {
        guard let alarm = viewModel?.nextAlarmDate else {
            return String(localized: "No alarm set", comment: "Next alarm card, empty")
        }
        let time = alarm.formatted(date: .omitted, time: .shortened)
        let untilAlarm = alarm.timeIntervalSinceNow
        guard viewModel?.viewMode == .evening, (3600...14 * 3600).contains(untilAlarm) else {
            return String(localized: "Alarm at \(time).", comment: "Sleep hero detail, alarm time only")
        }
        return String(localized: "Alarm at \(time). Sleep now for \(formattedDuration(untilAlarm)).", comment: "Sleep hero detail; second argument is a duration like 7h 40m")
    }

    private var soundPicker: some View {
        let service = container.sleepTrackingService
        return Picker(selection: Binding(
            get: { service.selectedSound },
            set: { service.selectSound($0) }
        )) {
            ForEach(SleepSoundType.allCases, id: \.self) { sound in
                Label(sound.displayName, systemImage: sound.systemImage).tag(sound)
            }
        } label: {
            Text(String(localized: "Sleep sound", comment: "Sleep sound picker label"))
        }
        .pickerStyle(.menu)
        .font(.mcBody)
    }

    @ViewBuilder
    private var noiseMicRow: some View {
        let service = container.sleepTrackingService
        if service.noiseMonitor.micPermission == .denied {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Monitor noise", comment: "Noise monitoring toggle"))
                        .font(.mcBody)
                    Text(String(localized: "Microphone access denied", comment: "Mic permission denied label"))
                        .font(.mcFootnote)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
                Button(String(localized: "Settings", comment: "Open settings for mic")) {
                    if let url = URL(string: "app-settings:") { openURL(url) }
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DesignTokens.Colors.accent)
            }
        } else {
            Toggle(isOn: Binding(
                get: { service.noiseMonitoringEnabled },
                set: { service.setNoiseMonitoring($0) }
            )) {
                Text(String(localized: "Monitor noise", comment: "Noise monitoring toggle"))
                    .font(.mcBody)
            }
            .tint(DesignTokens.Colors.accent)
        }
    }

    @ViewBuilder
    private var bedtimeReminderRows: some View {
        if let vm = viewModel {
            Toggle(isOn: Binding(
                get: { vm.bedtimeReminder.isEnabled },
                set: { on in Task { await vm.setBedtimeReminderEnabled(on) } }
            )) {
                Text(String(localized: "Bedtime reminder", comment: "Bedtime reminder toggle"))
                    .font(.mcBody)
            }
            .tint(DesignTokens.Colors.accent)

            if vm.bedtimeReminder.isEnabled {
                DatePicker(
                    selection: Binding(
                        get: { vm.bedtimeReminder.time.asDate() },
                        set: { date in
                            let time = AlarmTime(from: date)
                            Task { await vm.setBedtimeReminderTime(hour: time.hour, minute: time.minute) }
                        }
                    ),
                    displayedComponents: .hourAndMinute
                ) {
                    Text(String(localized: "Remind me at", comment: "Bedtime reminder time label"))
                        .font(.mcBody)
                }
            }

            if vm.bedtimeReminderNeedsPermission {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(String(
                        localized: "Notifications are off, so the reminder can't arrive.",
                        comment: "Bedtime reminder needs notification permission"
                    ))
                    .font(.mcFootnote)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(String(localized: "Settings", comment: "Opens the Settings app")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.borderless)
                    .font(.mcFootnote)
                    .foregroundStyle(DesignTokens.Colors.accent)
                }
            }
        }
    }

    private var startButton: some View {
        Button {
            Task {
                await viewModel?.startTracking(withNoiseMonitoring: container.sleepTrackingService.noiseMonitoringEnabled)
            }
        } label: {
            Text(String(localized: "Start Sleep Tracking", comment: "Start sleep tracking button"))
                .mcPrimaryButton()
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    /// The way into a calmer bedtime, under the button that starts the night.
    private var windDownButton: some View {
        Button {
            windDown = .setup
        } label: {
            Label(String(localized: "Wind down first", comment: "Sleep screen: opens the breathing wind-down"), systemImage: "wind")
                .font(.mcButton)
                .foregroundStyle(DesignTokens.Colors.nightText)
                .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.button)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    // MARK: - Last night

    /// Last night, then the nights before it (Premium) or what is behind the lock.
    @ViewBuilder
    private var lastNightSection: some View {
        Section {
            lastNightRows
            // The nights before last night: last night itself is the big number above.
            if case .loaded(let data) = viewModel?.healthState,
               case let earlier = data.history.filter({ !Calendar.current.isDateInToday($0.date) }),
               !earlier.isEmpty {
                if container.isPremium {
                    ForEach(earlier, id: \.id) { entry in
                        LabeledContent {
                            Text(formattedDuration(entry.duration))
                        } label: {
                            Text(entry.date, format: .dateTime.weekday(.wide))
                        }
                        .font(.mcBody)
                    }
                } else {
                    historyUpsellRow(nights: earlier.count)
                }
            }
        } header: {
            Text(String(localized: "Last night", comment: "Sleep screen section: last night"))
        }
    }

    /// Free tier: last night is shown in full; only the history is held back, and the
    /// row says exactly what is behind it.
    private func historyUpsellRow(nights: Int) -> some View {
        Button {
            paywallFeature = .sleepHistory
        } label: {
            HStack(spacing: DesignTokens.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "\(nights) more nights with Premium", comment: "Sleep history upsell title"))
                        .font(.mcBody)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(String(localized: "See your full history and 30-day trend.", comment: "Sleep history upsell detail"))
                        .font(.mcFootnote)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.mcFootnote)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var lastNightRows: some View {
        switch viewModel?.healthState ?? .idle {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.xs)

        case .loaded(let data):
            if let dur = data.lastNightDuration {
                Text(formattedDuration(dur))
                    .mcScaledFont(40, weight: .bold, relativeTo: .largeTitle, monospacedDigits: true)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
            } else {
                Text(String(localized: "No sleep recorded", comment: "No sleep data"))
                    .font(.mcBody)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

        case .notConnected:
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(String(localized: "Connect Health for sleep", comment: "HealthKit not connected title"))
                    .font(.mcBody)
                Text(String(
                    localized: "Dawnwick reads the sleep your iPhone or Watch already records. Nothing leaves your device.",
                    comment: "HealthKit not connected message"
                ))
                .font(.mcFootnote)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Button(String(localized: "Connect Health", comment: "Requests HealthKit access")) {
                Task { await viewModel?.connectHealth() }
            }
            .foregroundStyle(DesignTokens.Colors.accent)

        case .empty:
            infoRow(
                title: String(localized: "No sleep data yet", comment: "Empty sleep state"),
                message: String(localized: "Connect Apple Health or track tonight to see your sleep here.", comment: "Empty sleep hint")
            )

        case .permissionDenied:
            // Health read access is never re-prompted, so the path is spelled out.
            infoRow(
                title: String(localized: "Sleep access is off", comment: "Permission denied title"),
                message: String(localized: "Turn on Sleep for Dawnwick in Settings › Health › Data Access & Devices.", comment: "Permission denied message")
            )
            Button(String(localized: "Open Settings", comment: "Opens the Settings app")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .foregroundStyle(DesignTokens.Colors.accent)

        case .error:
            infoRow(
                title: String(localized: "Sleep data unavailable", comment: "Sleep error title"),
                message: String(localized: "Pull to refresh or check your connection.", comment: "Sleep error hint")
            )
        }
    }

    private func infoRow(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(title).font(.mcBody)
            Text(message)
                .font(.mcFootnote)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func formattedDuration(_ d: TimeInterval) -> String {
        let mins = max(0, Int(d / 60))
        return String(localized: "\(mins / 60)h \(mins % 60)m", comment: "Duration format")
    }
}

#Preview {
    NavigationStack { SleepView() }
        .environment(AppContainer.preview())
}
