import SwiftUI

/// Decides whether to show onboarding or the main tab shell,
/// and presents the full-screen ring screen when an alarm fires.
struct AppRootView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        shell
        .fullScreenCover(
            item: Binding(
                get: { container.currentRingingAlarm },
                set: { container.currentRingingAlarm = $0 }
            )
        ) { alarm in
            RingingAlarmView(alarm: alarm)
                .readsPageLayout()
                .interactiveDismissDisabled(true)
                .daylightAppearance()
        }
        .sheet(isPresented: Binding(
            get: { container.showWakeCheckPrompt },
            set: { if !$0 { container.acknowledgeWakeCheck() } }
        )) {
            WakeCheckPromptView(
                onStillAwake: { container.acknowledgeWakeCheck() },
                onFellAsleep: { container.failWakeCheck() }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(true)
            .daylightAppearance()
        }
        .onOpenURL { container.handleDeepLink($0) }
        #if DEBUG
        .task { await DebugLaunch.apply(to: container) }
        .sheet(isPresented: .constant(DebugLaunch.paywall)) { NavigationStack { PaywallView() }.readsPageLayout().appAppearance() }
        .fullScreenCover(isPresented: .constant(DebugLaunch.success && DebugLaunch.duo == nil)) {
            MissionSuccessView(elapsedSeconds: 140, streakDays: 12, onComplete: {}).daylightAppearance()
        }
        #endif
        // Every cat in the app, presented screens included, knows the tricks the best
        // streak has taught it.
        .catTricks(best: container.streakManager.record.bestStreak)
    }
}

extension AppRootView {
    @ViewBuilder
    private var shell: some View {
        #if DEBUG
        if let duo = DebugLaunch.duo {
            DuoEmulator(mode: duo) {
                // A full-screen cover is presented by the real window and would miss the
                // emulated one, so a mission is shown in place of the app instead.
                if DebugLaunch.success {
                    MissionSuccessView(elapsedSeconds: 140, streakDays: 12, onComplete: {})
                        .readsPageLayout()
                        .daylightAppearance()
                } else if let screen = DebugLaunch.duoScreen {
                    duoScreen(screen)
                        .readsPageLayout()
                } else if DebugLaunch.missionKind != nil {
                    MissionHostView(alarm: DebugLaunch.ringAlarm, onDismiss: {})
                        .readsPageLayout()
                        .daylightAppearance()
                } else {
                    pages
                }
            }
        } else {
            pages
        }
        #else
        pages
        #endif
    }

    #if DEBUG
    /// What `-mc.debug.duoScreen` names, as it is presented in the app.
    @ViewBuilder
    private func duoScreen(_ name: String) -> some View {
        switch name {
        case "ring":
            RingingAlarmView(alarm: DebugLaunch.ringAlarm).daylightAppearance()
        case "editor":
            AlarmEditorView(mode: .create, manager: container.alarmManager).appAppearance()
        case "onboarding":
            OnboardingView().daylightAppearance()
        case "paywall":
            NavigationStack { PaywallView() }.appAppearance()
        case "winddown", "breathing", "winddone":
            WindDownView(
                storage: container.storageService,
                tracking: container.sleepTrackingService,
                nextAlarmDate: nil,
                initialStage: name == "breathing" ? .breathing(started: .now, length: 300)
                    : name == "winddone" ? .done : .setup,
                onStartTracking: {}
            )
            .nightAppearance()
        case "game":
            CatchGameView().daylightAppearance()
        case "laser":
            LaserGameView().daylightAppearance()
        case "boxes":
            BoxGameView().daylightAppearance()
        case "share":
            StreakShareCard(streak: container.streakManager.record.currentStreak, week: DayCell.currentWeek(
                record: container.streakManager.record, alarms: []))
                .environment(\.colorScheme, .light)
        default:
            pages
        }
    }
    #endif

    private var pages: some View {
        Group {
            if container.hasCompletedOnboarding {
                AppTabBarView()
            } else {
                OnboardingView()
            }
        }
        .readsPageLayout()
    }
}

// MARK: - Wake check prompt

/// Paper, with the cat on a yolk disc and the answer as the yolk button: the
/// morning's colour as the thing to tap, not the whole sheet.
private struct WakeCheckPromptView: View {
    let onStillAwake: () -> Void
    let onFellAsleep: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            CatMascot(mood: .awake, ground: .light)
                .frame(height: 78)
                .background {
                    Circle()
                        .fill(DesignTokens.Colors.yolk)
                        .frame(width: 108, height: 108)
                        .offset(y: 5)
                }
                .padding(.top, DesignTokens.Spacing.xl)
                .padding(.bottom, DesignTokens.Spacing.s)
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(String(localized: "Still awake?", comment: "Wake check title"))
                    .font(.mcTitle2)
                    .foregroundStyle(DesignTokens.Colors.ink)
                Text(String(localized: "Confirm you're up and your alarm won't ring again.", comment: "Wake check subtitle"))
                    .font(.mcCallout)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DesignTokens.Spacing.xs)

            VStack(spacing: DesignTokens.Spacing.xs) {
                Button(action: onStillAwake) {
                    Text(String(localized: "Yes, I'm awake", comment: "Wake check confirm button"))
                        .mcPrimaryButton()
                }
                .buttonStyle(PressScaleButtonStyle())

                Button(action: onFellAsleep) {
                    Text(String(localized: "I fell back asleep", comment: "Wake check fell asleep button"))
                        .font(.mcCallout)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.row)
                }
            }
            .padding(.bottom, DesignTokens.Spacing.s)
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.Colors.background.ignoresSafeArea())
    }
}

#Preview {
    AppRootView()
        .environment(AppContainer.preview())
}
