import SwiftUI

struct SleepActiveView: View {
    let service: SleepTrackingService
    let nextAlarmText: String?
    /// The alarm the night ends with. The big number on this screen.
    var nextAlarmDate: Date? = nil
    let onStop: (SleepSession) -> Void

    @State private var showingStopConfirmation = false
    @Environment(\.pageLayout) private var pageLayout

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()

            if pageLayout == .spread {
                // Open on a Duo: the night card on the left page, the room and the way
                // to stop on the right.
                HStack(spacing: PageLayout.gutter) {
                    timerSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 0) {
                        header
                        Spacer()
                        detailsStack
                            .padding(.horizontal, DesignTokens.Spacing.s)
                        stopButton
                            .padding(.horizontal, DesignTokens.Spacing.s)
                            .padding(.bottom, DesignTokens.Spacing.m)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    header
                    Spacer()
                    timerSection
                    Spacer()
                    detailsStack
                        .padding(.horizontal, DesignTokens.Spacing.s)
                    stopButton
                        .padding(.horizontal, DesignTokens.Spacing.s)
                        .padding(.bottom, DesignTokens.Spacing.m)
                }
            }
        }
        .confirmationDialog(
            String(localized: "End sleep tracking?", comment: "Stop tracking dialog title"),
            isPresented: $showingStopConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Stop Tracking", comment: "Stop tracking confirm"), role: .destructive) {
                Task { await stopTracking() }
            }
            Button(String(localized: "Keep Tracking", comment: "Keep tracking cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "Your session will be saved.", comment: "Stop tracking message"))
        }
    }

    // MARK: - Header

    private var header: some View {
        Text(service.isRestoredSession
             ? String(localized: "Session restored", comment: "Restored sleep session label")
             : String(localized: "Tracking your sleep", comment: "Active sleep tracking label"))
            .font(.mcSubhead)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.top, DesignTokens.Spacing.l)
    }

    // MARK: - Timer

    /// The one time that matters: the alarm, or failing that the hour you went to
    /// bed, on the night card with the cat asleep. The running count sits under it.
    @ViewBuilder
    private var timerSection: some View {
        if let session = service.activeSession {
            VStack(spacing: DesignTokens.Spacing.s) {
                CatMascot(mood: .sleeping, ground: .dark)
                    .frame(maxWidth: 210)
                VStack(spacing: DesignTokens.Spacing.xxs) {
                    Text(nextAlarmDate == nil
                         ? String(localized: "Went to bed", comment: "Sleep tracking, eyebrow over the bedtime")
                         : String(localized: "Alarm", comment: "Sleep tracking, eyebrow over the alarm time"))
                        .font(.mcHeadline)
                        .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                    Text(nextAlarmDate ?? session.startDate, style: .time)
                        .mcScaledFont(60, weight: .semibold)
                        .foregroundStyle(DesignTokens.Colors.nightText)
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text(String(localized: "Asleep for", comment: "Sleep tracking, label before the elapsed time"))
                            .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                        Text(session.startDate, style: .timer)
                            .monospacedDigit()
                            .foregroundStyle(DesignTokens.Colors.nightAccent)
                            .accessibilityLabel(String(localized: "Elapsed sleep time", comment: "Accessibility label"))
                    }
                    .font(.system(.callout, weight: .semibold))
                }
            }
            .padding(.vertical, DesignTokens.Spacing.m)
            .padding(.horizontal, DesignTokens.Spacing.s)
            .frame(maxWidth: .infinity)
            .background(DesignTokens.Colors.nightBand,
                        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous))
            .padding(.horizontal, DesignTokens.Spacing.s)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Details

    /// The alarm, the room and the sound, as rows of one group.
    private var detailsStack: some View {
        VStack(spacing: 0) {
            if let alarmText = nextAlarmText {
                detailRow(systemImage: "alarm") { Text(alarmText) }
                Divider().padding(.leading, 44)
            }
            if service.hasMicPermission {
                detailRow(systemImage: "waveform") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "Ambient noise", comment: "Noise level label"))
                            Spacer()
                            Text(noiseEventLabel).foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                        SleepNoiseLevelBar(levelDB: service.currentLevelDB)
                            .frame(height: 4)
                    }
                }
                Divider().padding(.leading, 44)
            }
            detailRow(systemImage: service.selectedSound.systemImage) {
                Text(service.audioPlayer.isPlaying
                     ? service.selectedSound.displayName
                     : String(localized: "No sound", comment: "No sleep sound playing"))
            }
        }
        .background(DesignTokens.Colors.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
        .padding(.bottom, DesignTokens.Spacing.s)
    }

    private func detailRow<Content: View>(systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(DesignTokens.Colors.accent)
                .frame(width: 20)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.mcCallout)
        .foregroundStyle(DesignTokens.Colors.textPrimary)
        .padding(.horizontal, DesignTokens.Spacing.s)
        .frame(minHeight: DesignTokens.Size.row)
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }

    private var noiseEventLabel: String {
        let count = service.noiseEvents.count
        return count == 0 ? String(localized: "Quiet", comment: "No noise events") :
               count == 1 ? String(localized: "1 event", comment: "One noise event") :
               String(localized: "\(count) events", comment: "Multiple noise events")
    }

    // MARK: - Stop

    private var stopButton: some View {
        Button {
            showingStopConfirmation = true
        } label: {
            Text(String(localized: "Stop Tracking", comment: "Stop sleep tracking button"))
                .mcDestructiveButton()
        }
    }

    private func stopTracking() async {
        guard let session = await service.stopSession() else { return }
        onStop(session)
    }
}

// MARK: - Noise level bar

struct SleepNoiseLevelBar: View {
    let levelDB: Float

    private var fraction: CGFloat {
        let lo: Float = -80
        let hi: Float = -10
        let clamped = min(max(levelDB, lo), hi)
        return CGFloat((clamped - lo) / (hi - lo))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DesignTokens.Colors.surfaceSecondary)
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: geo.size.width * fraction)
                    .animation(.linear(duration: 0.3), value: fraction)
            }
        }
    }

    private var barColor: Color {
        if fraction < 0.4 { return DesignTokens.Colors.success }
        if fraction < 0.7 { return DesignTokens.Colors.warning }
        return DesignTokens.Colors.destructive
    }
}

#Preview {
    let container = AppContainer.preview()
    return SleepActiveView(
        service: container.sleepTrackingService,
        nextAlarmText: "Alarm at 6:30 AM",
        nextAlarmDate: Calendar.current.date(bySettingHour: 6, minute: 30, second: 0, of: .now),
        onStop: { _ in }
    )
    .environment(container)
}
