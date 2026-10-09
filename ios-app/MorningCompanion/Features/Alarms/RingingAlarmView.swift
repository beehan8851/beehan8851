import SwiftUI
import UIKit
import UserNotifications

// MARK: - Ring screen

/// The alarm, ringing: what it is, the time, the cat pawing at the glass, what turns
/// it off, and one button. All yolk, whatever the appearance setting: it is there to
/// wake you. Snooze is there but second: a plain text control under the primary
/// action, with how many are left.
///
/// The audio handoff and the haptic cadence are unchanged from F1 — this file's
/// redesign is the view only.
struct RingingAlarmView: View {
    let alarm: Alarm
    @Environment(AppContainer.self) private var container
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pageLayout) private var pageLayout

    @State private var showMission = false
    @State private var missionSucceeded = false
    @State private var audioPlayer = AlarmAudioPlayer()
    /// True while `audioPlayer` is carrying the ring (AlarmKit not alerting).
    @State private var inAppAudioActive = false
    /// The alarm has just gone off: for a moment the cat is as startled as anyone.
    @State private var startled = true
    @State private var startles = 0

    /// Haptic + audio-handoff cadence.
    private static let ringTick: UInt64 = 2_000_000_000

    var body: some View {
        ZStack {
            DesignTokens.Colors.yolk.ignoresSafeArea()
            // At accessibility sizes the hero no longer fits above the buttons on one
            // screen. It scrolls.
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: DesignTokens.Spacing.m) {
                        hero
                        missionLine
                        actionArea
                    }
                    .padding(.top, DesignTokens.Spacing.xl)
                }
            } else if pageLayout == .spread {
                // Open like a book: the cat has the left page to itself, everything to
                // read and press is on the right.
                HStack(spacing: PageLayout.gutter) {
                    cat
                        .frame(maxWidth: 320, maxHeight: 340)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 0) {
                        Spacer(minLength: DesignTokens.Spacing.s)
                        hero
                        Spacer(minLength: DesignTokens.Spacing.s)
                        missionLine
                            .padding(.bottom, DesignTokens.Spacing.m)
                        actionArea
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    hero
                        .padding(.top, DesignTokens.Spacing.xl)
                    Spacer(minLength: DesignTokens.Spacing.s)
                    cat
                        .frame(maxWidth: 240, maxHeight: 260)
                    Spacer(minLength: DesignTokens.Spacing.s)
                    missionLine
                        .padding(.bottom, DesignTokens.Spacing.m)
                    actionArea
                }
            }
        }
        .onAppear {
            triggerHaptic()
            #if DEBUG
            if DebugLaunch.autoStartMission { showMission = true }
            #endif
        }
        // Volume handoff (F1 step 3): AlarmKit keeps ringing at alarm volume until the
        // mission completes or the user snoozes. In-app audio (media volume) only takes
        // over when AlarmKit is *not* alerting — notification fallback, system Stop
        // pressed, wake-check re-ring gap. Re-checked every tick together with haptics.
        .task(id: alarm.id) { await ringLoop() }
        .task {
            // The jump waits for the screen to finish arriving.
            try? await Task.sleep(for: .seconds(0.45))
            startles += 1
            try? await Task.sleep(for: .seconds(CatStage.startleHold))
            withAnimation(.easeOut(duration: 0.2)) { startled = false }
        }
        .onDisappear { stopInAppAudio() }
        .onChange(of: showMission) { _, isShowing in
            // Mission screen closed without success → timeout. Make sure the alarm is audible.
            if !isShowing && !missionSucceeded { triggerHaptic() }
        }
        .fullScreenCover(isPresented: $showMission, onDismiss: {
            if missionSucceeded {
                container.selectedTabIndex = 0
                Task { await clearBadge() }
                container.currentRingingAlarm = nil
            }
            // Timeout path: ringing screen stays visible; ringLoop keeps audio/haptics going.
        }) {
            MissionHostView(
                alarm: alarm,
                onMissionComplete: {
                    missionSucceeded = true
                    audioPlayer.fadeOut()
                    inAppAudioActive = false
                },
                onDismiss: { showMission = false }
            )
            .readsPageLayout()
            .interactiveDismissDisabled(true)
            .daylightAppearance()
        }
    }

    // MARK: - Ring loop (audio handoff + continuous haptics)

    private func ringLoop() async {
        await reconcileAudio()
        while !Task.isCancelled && !missionSucceeded {
            try? await Task.sleep(nanoseconds: Self.ringTick)
            if Task.isCancelled || missionSucceeded { return }
            if !showMission { triggerHaptic() }
            await reconcileAudio()
        }
    }

    private func reconcileAudio() async {
        guard !missionSucceeded else { return }
        let alarmKitAlerting = await container.isAlarmKitAlerting(for: alarm)
        if alarmKitAlerting {
            if inAppAudioActive { stopInAppAudio() }
        } else if !inAppAudioActive {
            audioPlayer.play(sound: alarm.sound, volume: alarm.volume, gradualWake: alarm.gradualWakeDuration)
            inAppAudioActive = true
        }
    }

    private func stopInAppAudio() {
        audioPlayer.stop()
        inAppAudioActive = false
    }

    // MARK: - Hero

    private var cat: some View {
        CatStage(mood: startled ? .startled : .ringing, ground: .light)
            .catMotion(.startle, trigger: startles, size: 200)
    }

    private var hero: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.onYolkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            AlarmTimeText(time: alarm.wallClockTime, size: 96, weight: .heavy,
                          color: DesignTokens.Colors.ink, periodColor: DesignTokens.Colors.onYolkSecondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .accessibilityElement(children: .combine)
    }

    /// What turns it off, in order, each with its symbol.
    @ViewBuilder
    private var missionLine: some View {
        if !alarm.missions.isEmpty {
            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(Array(alarm.missions.enumerated()), id: \.offset) { index, mission in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.onYolkSecondary)
                    }
                    Label(mission.displayName, systemImage: mission.systemImage)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.ink)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .accessibilityElement(children: .combine)
        }
    }

    /// "Work · Every weekday": the label if there is one, then the recurrence.
    private var caption: String {
        [alarm.label, alarm.recurrence.ringScreenSummary]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    // MARK: - Action area

    private var actionArea: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            // Always require mission completion — zero-mission alarms use a defensive fallback
            // so there is never a one-tap dismiss bypass.
            Button {
                Haptics.notify(.warning)
                showMission = true
            } label: {
                Text(String(localized: "Start Mission", comment: "Start mission button"))
                    .mcInkButton()
            }
            .buttonStyle(PressScaleButtonStyle())

            if alarm.snooze.isEnabled {
                let snoozeCount = container.snoozeCount(for: alarm.id)
                let atLimit = alarm.snooze.maxCount > 0 && snoozeCount >= alarm.snooze.maxCount
                if !atLimit {
                    Button {
                        Haptics.impact(.medium)
                        Task {
                            await container.snoozePendingMission(alarm: alarm)
                            // Snooze is refused when the re-arm could not be scheduled — keep ringing.
                            guard container.pendingMissionAlarmID != alarm.id else { return }
                            audioPlayer.fadeOut()
                            inAppAudioActive = false
                            await clearBadge()
                            container.currentRingingAlarm = nil
                        }
                    } label: {
                        Text(snoozeLabel(snoozeCount: snoozeCount))
                            .font(.mcSubhead)
                            .foregroundStyle(DesignTokens.Colors.onYolkSecondary)
                            .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.row)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(String(localized: "No more snoozes", comment: "Snooze limit reached"))
                        .font(.mcFootnote)
                        .foregroundStyle(DesignTokens.Colors.onYolkSecondary)
                        .frame(height: DesignTokens.Size.row)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.bottom, DesignTokens.Spacing.s)
    }

    private func snoozeLabel(snoozeCount: Int) -> String {
        let minutes = alarm.snooze.durationMinutes
        guard alarm.snooze.maxCount > 0 else {
            return String(localized: "Snooze \(minutes) min", comment: "Snooze button, unlimited")
        }
        let remaining = alarm.snooze.maxCount - snoozeCount
        if remaining <= 1 {
            return String(localized: "Snooze \(minutes) min · last one", comment: "Snooze button, one left")
        }
        return String(localized: "Snooze \(minutes) min · \(remaining) left", comment: "Snooze button with remaining count")
    }

    // MARK: - Helpers

    private func clearBadge() async {
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    private func triggerHaptic() {
        Haptics.notify(.warning)
    }
}

// MARK: - Button style

/// Pressed feedback the way system buttons give it: the label dims, nothing moves.
struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: DesignTokens.Motion.immediate), value: configuration.isPressed)
    }
}

// MARK: - AlarmRecurrence ring screen summary

extension AlarmRecurrence {
    var ringScreenSummary: String {
        switch self {
        case .daily:    return String(localized: "Every day",  comment: "Ring screen recurrence — daily")
        case .oneTime:  return String(localized: "Today only", comment: "Ring screen recurrence — one-time")
        case .repeating(let days):
            if days.isEmpty { return "" }
            if days == Set(Weekday.allCases) { return String(localized: "Every day", comment: "Ring screen — all days") }
            let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
            let weekend:  Set<Weekday> = [.saturday, .sunday]
            if days == weekdays { return String(localized: "Every weekday", comment: "Ring screen — weekdays") }
            if days == weekend  { return String(localized: "Weekends", comment: "Ring screen — weekends") }
            let ordered: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
            return ordered.filter { days.contains($0) }.map(\.shortName).joined(separator: " · ")
        }
    }
}

// MARK: - Previews

#Preview("Ring — multi-mission") {
    RingingAlarmView(alarm: Alarm(
        label: "Morning run",
        wallClockTime: AlarmTime(hour: 6, minute: 30),
        recurrence: .repeating(days: [.monday, .wednesday, .friday]),
        missions: [.defaultMath, .defaultShake],
        snooze: .default
    ))
    .environment(AppContainer.preview())
}

#Preview("Ring — no missions") {
    RingingAlarmView(alarm: Alarm(
        label: "Wake up",
        wallClockTime: AlarmTime(hour: 7, minute: 0),
        recurrence: .daily,
        missions: [],
        snooze: .off
    ))
    .environment(AppContainer.preview())
}
