import SwiftUI
import UIKit

// MARK: - Mission host

/// Runs the alarm's mission sequence in order, showing "X of N" progress.
/// After all missions succeed, shows the success screen then calls onDismiss.
/// Audio fades when the final mission is solved, not before.
struct MissionHostView: View {
    let alarm: Alarm
    var onMissionComplete: (() -> Void)? = nil
    var onDismiss: () -> Void

    @Environment(AppContainer.self) private var container
    @State private var missionIndex = 0
    @State private var phase: Phase = .mission
    @State private var secondsLeft = 300   // 5 minute limit
    /// Mission indices that already reported success. Mission views can fire
    /// `onSuccess` twice (sensor callbacks, delayed Tasks); the second call must not
    /// skip a mission or double-complete the alarm (F1 step 10).
    @State private var advancedIndices: Set<Int> = []
    /// Soft-lock policy (F1 step 11): missions that cannot run on this device right
    /// now are swapped for Math, with a note explaining why. Resolved once on appear.
    @State private var runnable: (missions: [MissionConfig], notes: [String])? = nil

    private enum Phase { case mission, success }

    private var countdownLabel: String {
        String(format: "%d:%02d", secondsLeft / 60, secondsLeft % 60)
    }

    /// Defensive fallback: if the alarm somehow has zero missions (legacy/corrupt data),
    /// substitute a default math mission so there is always something to complete.
    private var effectiveMissions: [MissionConfig] {
        if let runnable { return runnable.missions }
        return alarm.missions.isEmpty ? [.defaultMath] : alarm.missions
    }
    private var substitutionNotes: [String] { runnable?.notes ?? [] }
    private var currentMission: MissionConfig? {
        guard missionIndex < effectiveMissions.count else { return nil }
        return effectiveMissions[missionIndex]
    }

    var body: some View {
        ZStack {
            // Paper (the host is always presented in the daylight appearance); keys
            // and fields are white on it.
            DesignTokens.Colors.background.ignoresSafeArea()
            switch phase {
            case .mission:
                if let mission = currentMission {
                    VStack(spacing: 0) {
                        if !substitutionNotes.isEmpty {
                            substitutionBanner
                                .padding(.horizontal, DesignTokens.Spacing.s)
                                .padding(.top, DesignTokens.Spacing.xs)
                        }
                        missionView(for: mission)
                    }
                    .overlay(alignment: .top) { progressBar }
                } else {
                    Color.clear.onAppear { succeed() }
                }
            case .success:
                MissionSuccessView(
                    elapsedSeconds: 300 - secondsLeft,
                    streakDays: container.streakManager.record.currentStreak,
                    onComplete: onDismiss
                )
            }
        }
        .onAppear {
            if runnable == nil {
                runnable = MissionCapability.runnableMissions(
                    from: alarm.missions,
                    isPremium: container.isPremium
                )
            }
        }
        .task {
            while secondsLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled || phase == .success { return }
                secondsLeft -= 1
            }
            if phase != .success { onDismiss() }
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressBar: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            if effectiveMissions.count > 1 {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    ForEach(0..<effectiveMissions.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i < missionIndex
                                  ? DesignTokens.Colors.ink
                                  : (i == missionIndex
                                     ? DesignTokens.Colors.yolk
                                     : DesignTokens.Colors.surfaceSecondary))
                            .frame(height: 4)
                            .animation(.easeInOut(duration: DesignTokens.Motion.controls), value: missionIndex)
                    }
                }
            }

            HStack {
                Spacer()
                Text(countdownLabel)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(
                        secondsLeft <= 30  ? DesignTokens.Colors.destructive :
                        secondsLeft <= 60  ? DesignTokens.Colors.warning     :
                        DesignTokens.Colors.textSecondary
                    )
                    .monospacedDigit()
                    .animation(.easeInOut(duration: 0.3), value: secondsLeft <= 60)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.top, DesignTokens.Spacing.s)
    }

    private var substitutionBanner: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.Colors.warning)
            Text(substitutionNotes.joined(separator: " "))
                .font(.mcCaption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.s, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Mission routing

    @ViewBuilder
    private func missionView(for mission: MissionConfig) -> some View {
        if !mission.isConfigured {
            // Should be unreachable: runnableMissions() already swapped it for Math.
            MathMissionView(config: .defaultMath, onSuccess: advanceMission)
        } else {
            switch mission {
            case .math:
                MathMissionView(config: mission, onSuccess: advanceMission)
            case .shake:
                ShakeMissionView(config: mission, onSuccess: advanceMission)
            case .steps:
                StepsMissionView(config: mission, onSuccess: advanceMission)
            case .qrCode:
                QRMissionView(config: mission, onSuccess: advanceMission)
            case .memory:
                MemoryMissionView(config: mission, onSuccess: advanceMission)
            case .typing:
                TypingMissionView(config: mission, onSuccess: advanceMission)
            case .draw:
                DrawMissionView(config: mission, onSuccess: advanceMission)
            case .jump:
                JumpMissionView(config: mission, onSuccess: advanceMission)
            case .catchCat:
                CatchCatMissionView(config: mission, onSuccess: advanceMission)
            }
        }
    }

    // MARK: - Flow

    private func advanceMission() {
        guard phase == .mission, !advancedIndices.contains(missionIndex) else { return }
        advancedIndices.insert(missionIndex)
        let next = missionIndex + 1
        if next < effectiveMissions.count {
            withAnimation(.easeInOut(duration: DesignTokens.Motion.controls)) {
                missionIndex = next
            }
        } else {
            succeed()
        }
    }

    private func succeed() {
        guard phase == .mission else { return }
        container.completeMission(for: alarm)
        onMissionComplete?()
        let alarmID = alarm.id
        Task {
            // The rest-day rule needs the alarm list; it is a UserDefaults read, so
            // the success screen is not measurably later for waiting on it.
            let alarms = (try? await container.alarmManager.fetchAll()) ?? [alarm]
            container.streakManager.recordCompletion(alarms: alarms)
            phase = .success
            _ = await AlarmLiveActivityController.end(alarmID: alarmID, finalStatus: .dismissed)
            await container.refreshWidgetSnapshot()
            // Schedule wake check after the success screen transitions away
            await container.scheduleWakeCheck(for: alarm)
        }
    }
}

// MARK: - Mission success screen

/// A short confirmation that the alarm is off: the cat, pleased; good morning; when
/// you got up and how long the mission took; and the streak, with today's paw print
/// pressed in. Hands over to Today on its own after a moment.
struct MissionSuccessView: View {
    var elapsedSeconds: Int = 0
    var streakDays: Int = 0
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageLayout) private var pageLayout
    @State private var shown = false
    @State private var stamped = false
    /// Two leaps of joy as the screen comes in.
    @State private var leaps = 0

    /// Long enough to read, short enough not to be in the way of someone who is up.
    private static let dwell: UInt64 = 2_800_000_000

    var body: some View {
        ZStack {
            DesignTokens.Colors.yolk.ignoresSafeArea()
            // Open on a Duo, the cat has the left page and the words the right, so
            // neither sits on the fold.
            let spread = pageLayout == .spread
            let layout = spread
                ? AnyLayout(HStackLayout(spacing: PageLayout.gutter))
                : AnyLayout(VStackLayout(spacing: DesignTokens.Spacing.s))
            layout {
                CatMascot(mood: .proud, ground: .light)
                    .frame(height: spread ? 240 : 190)
                    .catMotion(.leap, trigger: leaps, size: spread ? 240 : 190, shadow: true)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.92)
                    .padding(.bottom, DesignTokens.Spacing.xs)
                    .frame(maxWidth: spread ? .infinity : nil)
                VStack(spacing: DesignTokens.Spacing.s) {
                Text(String(localized: "Good morning.", comment: "Mission success message"))
                    .font(.mcTitle1)
                    .foregroundStyle(DesignTokens.Colors.ink)
                Text(summary)
                    .font(.mcCallout)
                    .foregroundStyle(DesignTokens.Colors.onYolkSecondary)
                HStack(spacing: DesignTokens.Spacing.xs) {
                    PawPrintShape()
                        .fill(DesignTokens.Colors.ink)
                        .frame(width: 22, height: 22)
                        .scaleEffect(stamped || reduceMotion ? 1 : 1.8)
                        .opacity(stamped || reduceMotion ? 1 : 0)
                        .accessibilityHidden(true)
                    Text(streakLine)
                        .font(.system(.headline, weight: .bold))
                        .foregroundStyle(DesignTokens.Colors.ink)
                }
                .padding(.top, DesignTokens.Spacing.xs)
                }
                .frame(maxWidth: spread ? .infinity : nil)
            }
            .multilineTextAlignment(.center)
            .padding(DesignTokens.Spacing.m)
            .opacity(shown ? 1 : 0)
        }
        .accessibilityElement(children: .combine)
        .onAppear {
            Haptics.notify(.success)
            withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8)) { shown = true }
            Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                leaps += 1
                try? await Task.sleep(nanoseconds: 200_000_000)
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.55)) { stamped = true }
                Haptics.impact(.medium)
                try? await Task.sleep(nanoseconds: 750_000_000)
                leaps += 1
                try? await Task.sleep(nanoseconds: Self.dwell - 750_000_000)
                onComplete()
            }
        }
    }

    /// "07:03 · 3 min": when you got up and how long the mission took.
    private var summary: String {
        let time = Date.now.formatted(date: .omitted, time: .shortened)
        let minutes = max(1, Int((Double(elapsedSeconds) / 60).rounded(.up)))
        return String(localized: "\(time) · \(minutes) min", comment: "Success screen eyebrow: wake time and minutes the mission took")
    }

    private var streakLine: String {
        streakDays > 1
            ? String(localized: "Day \(streakDays) of your streak.", comment: "Home hero detail, streak")
            : String(localized: "Your streak starts today.", comment: "Home hero detail, first day")
    }
}

// MARK: - Previews

#Preview("Math then Shake") {
    MissionHostView(
        alarm: Alarm(
            label: "Morning",
            wallClockTime: AlarmTime(hour: 7, minute: 0),
            recurrence: .daily,
            missions: [.defaultMath, .defaultShake]
        ),
        onDismiss: {}
    )
    .environment(AppContainer.preview())
}

#Preview("Success screen") {
    MissionSuccessView(elapsedSeconds: 140, streakDays: 12, onComplete: {})
}
