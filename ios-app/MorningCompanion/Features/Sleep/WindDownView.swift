import SwiftUI
import UIKit

/// A few minutes of slow breathing before bed, paced by the cat asleep on its moon.
///
/// Three stages: choose a length, a sound and leave what is on your mind for the
/// morning; breathe — in for four, out for six, the moon's halo swelling and the cat
/// rising with each breath while the screen slowly dims; then good night, with the
/// offer to start tracking. A soft tap marks every turn of the breath, so it works
/// with the eyes closed and the phone on the chest.
struct WindDownView: View {
    enum Stage: Equatable, Identifiable {
        case setup
        case breathing(started: Date, length: TimeInterval)
        case done

        var id: String {
            switch self {
            case .setup: "setup"
            case .breathing: "breathing"
            case .done: "done"
            }
        }
    }

    let storage: any StorageServiceProtocol
    let tracking: SleepTrackingService
    let nextAlarmDate: Date?
    /// Starts tonight's tracking; the view closes itself afterwards.
    let onStartTracking: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pageLayout) private var pageLayout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var stage: Stage
    @AppStorage("com.morningcompanion.windDown.minutes") private var minutes = 5
    @State private var note = ""
    @State private var noteParked = false
    @State private var player = SleepAudioPlayer()
    @FocusState private var noteFocused: Bool

    private let pacer = BreathPacer()
    private static let lengths = [3, 5, 10]

    init(
        storage: any StorageServiceProtocol,
        tracking: SleepTrackingService,
        nextAlarmDate: Date?,
        initialStage: Stage = .setup,
        onStartTracking: @escaping () -> Void
    ) {
        self.storage = storage
        self.tracking = tracking
        self.nextAlarmDate = nextAlarmDate
        self.onStartTracking = onStartTracking
        _stage = State(initialValue: initialStage)
    }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            switch stage {
            case .setup:
                setup.transition(.opacity)
            case let .breathing(started, length):
                breathing(started: started, length: length).transition(.opacity)
            case .done:
                done.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: stage)
        .task(id: stage) { await runSession() }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if !tracking.isActive {
                player.stop()
            }
        }
    }

    // MARK: - Setup

    /// Two pages, unless the text is so large that half the screen will not hold it.
    private var spread: Bool { pageLayout == .spread && !dynamicTypeSize.isAccessibilitySize }

    @ViewBuilder
    private var setup: some View {
        if spread {
            // Open like a book: the cat and what this is on the left page, the choices
            // and the button on the right.
            HStack(spacing: PageLayout.gutter) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                    closeButton
                    Spacer(minLength: 0)
                    setupIntro(catSize: 150)
                    Spacer(minLength: 0)
                }
                .padding(.leading, DesignTokens.Spacing.m)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .frame(maxWidth: .infinity)
                ScrollView {
                    setupFields
                        .padding(.trailing, DesignTokens.Spacing.m)
                        .padding(.vertical, DesignTokens.Spacing.m)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    beginButton
                        .padding(.trailing, DesignTokens.Spacing.m)
                        .padding(.vertical, DesignTokens.Spacing.s)
                        .background(DesignTokens.Colors.background)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            setupSingle
        }
    }

    private func setupIntro(catSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            // Yawning: the cat is ready for bed before you are.
            CatMascot(mood: .yawning, ground: .dark)
                .frame(width: catSize)
                .background {
                    Circle()
                        .fill(DesignTokens.Colors.yolk.opacity(0.08))
                        .frame(width: catSize * 1.36, height: catSize * 1.36)
                }
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(String(localized: "Wind down", comment: "Wind-down screen title"))
                    .mcScaledFont(34, weight: .heavy, relativeTo: .largeTitle)
                    .foregroundStyle(DesignTokens.Colors.nightText)
                Text(String(localized: "Breathe with the cat for a few minutes: in for four, out for six. A soft tap marks each turn, so you can close your eyes.", comment: "Wind-down screen explanation"))
                    .font(.mcCallout)
                    .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var beginButton: some View {
        Button(action: begin) {
            Text(String(localized: "Begin", comment: "Wind-down: start breathing"))
                .mcPrimaryButton()
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    private var setupSingle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                setupIntro(catSize: 118)
                    .padding(.top, 36)
                setupFields
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.bottom, DesignTokens.Spacing.l)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                closeButton
                Spacer()
            }
            .padding(.horizontal, DesignTokens.Spacing.m)
            .padding(.vertical, DesignTokens.Spacing.xs)
            .background(DesignTokens.Colors.background)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            beginButton
                .padding(.horizontal, DesignTokens.Spacing.m)
                .padding(.vertical, DesignTokens.Spacing.s)
                .background(DesignTokens.Colors.background)
        }
    }

    /// Length, sound, and the note for the morning.
    private var setupFields: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                fieldTitle(String(localized: "Length", comment: "Wind-down: session length"))
                // Side by side, or stacked when large text will not fit three across.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(Self.lengths, id: \.self) { length in
                            lengthChip(length)
                        }
                    }
                    VStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(Self.lengths, id: \.self) { length in
                            lengthChip(length)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                fieldTitle(String(localized: "Sound", comment: "Wind-down: background sound"))
                soundMenu
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                fieldTitle(String(localized: "On your mind?", comment: "Wind-down: note for the morning, title"))
                TextField(
                    String(localized: "Write it down. It waits for you on Today in the morning.", comment: "Wind-down: note for the morning, placeholder"),
                    text: $note,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .focused($noteFocused)
                .font(.mcBody)
                .foregroundStyle(DesignTokens.Colors.nightText)
                .padding(DesignTokens.Spacing.s)
                .background(DesignTokens.Colors.surfacePrimary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
                // The whole card takes the tap, not only the line of text in it.
                .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
                .onTapGesture { noteFocused = true }
            }
        }
    }

    private func fieldTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
    }

    private func lengthChip(_ length: Int) -> some View {
        let chosen = length == minutes
        return Button {
            Haptics.selection()
            minutes = length
        } label: {
            Text(String(localized: "\(length) min", comment: "Wind-down length chip, e.g. 5 min"))
                .font(.system(.body, weight: .bold).width(.expanded))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(chosen ? DesignTokens.Colors.ink : DesignTokens.Colors.nightText)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(chosen ? DesignTokens.Colors.yolk : DesignTokens.Colors.surfacePrimary,
                            in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    private var soundMenu: some View {
        Menu {
            Picker(selection: Binding(get: { tracking.selectedSound }, set: { tracking.selectSound($0) })) {
                ForEach(SleepSoundType.allCases, id: \.self) { sound in
                    Label(sound.displayName, systemImage: sound.systemImage).tag(sound)
                }
            } label: { EmptyView() }
        } label: {
            HStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: tracking.selectedSound.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.yolk)
                    .frame(width: 24)
                Text(tracking.selectedSound.displayName)
                    .font(.mcBody)
                    .foregroundStyle(DesignTokens.Colors.nightText)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
            .frame(minHeight: 52)
            .background(DesignTokens.Colors.surfacePrimary, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
        }
        .accessibilityLabel(String(localized: "Sound", comment: "Wind-down: background sound"))
        .accessibilityValue(tracking.selectedSound.displayName)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DesignTokens.Colors.nightText)
                .frame(width: 44, height: 44)
                .background(DesignTokens.Colors.surfacePrimary, in: Circle())
        }
        .accessibilityLabel(String(localized: "Close", comment: "Close button"))
    }

    // MARK: - Breathing

    private func breathing(started: Date, length: TimeInterval) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let elapsed = context.date.timeIntervalSince(started)
            let moment = pacer.moment(at: elapsed)
            let fullness = (moment.breath + 1) / 2
            let moon = ZStack {
                halo(fullness: fullness)
                CatMascot(mood: .sleeping, ground: .dark, animated: !reduceMotion,
                          breath: reduceMotion ? nil : moment.breath)
                    .frame(width: 220)
                    .scaleEffect(reduceMotion ? 1 : 1 + 0.04 * fullness, anchor: .bottom)
                    .offset(y: 18)
            }
            .frame(height: 340)
            let words = VStack(spacing: DesignTokens.Spacing.l) {
                Text(phaseText(moment.phase))
                    .mcScaledFont(30, weight: .heavy, relativeTo: .title)
                    .foregroundStyle(DesignTokens.Colors.nightText)
                    .opacity(0.25 + 0.75 * min(1, min(moment.progress, 1 - moment.progress) * 5 + 0.1))
                    .accessibilityHidden(true)

                Text(remaining(length - elapsed))
                    .font(.system(.subheadline, weight: .semibold).monospacedDigit())
                    .foregroundStyle(DesignTokens.Colors.nightTextTertiary)
                    .accessibilityHidden(true)
            }
            let end = Button {
                finish()
            } label: {
                Text(String(localized: "End", comment: "Wind-down: stop breathing early"))
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                    .frame(minWidth: 120, minHeight: 44)
            }
            .padding(.bottom, DesignTokens.Spacing.m)
            Group {
                if spread {
                    // The moon on the left page, the words on the right: nothing on the fold.
                    HStack(spacing: PageLayout.gutter) {
                        moon
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack {
                            Spacer()
                            words
                            Spacer()
                            end
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    VStack(spacing: DesignTokens.Spacing.l) {
                        Spacer()
                        moon
                        words
                        Spacer()
                        end
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .overlay {
                // The room gets darker as the minutes go by.
                Color.black
                    .opacity(0.55 * min(1, max(0, elapsed / length)))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Breathing with the cat. A soft tap marks each turn of the breath.", comment: "Wind-down breathing, VoiceOver"))
    }

    /// The moon's light: three flat rings that swell on the in-breath. Under Reduce
    /// Motion they stay put and only brighten.
    private func halo(fullness: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                let base = 170.0 + Double(ring) * 56
                let grow = reduceMotion ? 0 : (36.0 + Double(ring) * 22) * fullness
                Circle()
                    .fill(DesignTokens.Colors.yolk.opacity((0.11 - Double(ring) * 0.03) * (reduceMotion ? 0.5 + fullness : 1)))
                    .frame(width: base + grow, height: base + grow)
            }
        }
        .accessibilityHidden(true)
    }

    private func phaseText(_ phase: BreathPacer.Phase) -> String {
        switch phase {
        case .breatheIn:  String(localized: "Breathe in", comment: "Wind-down: inhale cue")
        case .breatheOut: String(localized: "Breathe out", comment: "Wind-down: exhale cue")
        }
    }

    private func remaining(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Done

    @ViewBuilder
    private var done: some View {
        if spread {
            HStack(spacing: PageLayout.gutter) {
                CatMascot(mood: .sleeping, ground: .dark)
                    .frame(width: 260)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                doneWords(cat: false)
                    .frame(maxWidth: .infinity)
            }
        } else {
            doneWords(cat: true)
        }
    }

    private func doneWords(cat: Bool) -> some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Spacer()
            if cat {
                CatMascot(mood: .sleeping, ground: .dark)
                    .frame(width: 200)
            }
            Text(String(localized: "Sleep well.", comment: "Wind-down: finished, title"))
                .mcScaledFont(34, weight: .heavy, relativeTo: .largeTitle)
                .foregroundStyle(DesignTokens.Colors.nightText)
            Text(doneDetail)
                .font(.mcBody)
                .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            VStack(spacing: DesignTokens.Spacing.xs) {
                if !tracking.isActive {
                    Button {
                        player.stopImmediate()
                        onStartTracking()
                        dismiss()
                    } label: {
                        Text(String(localized: "Start Sleep Tracking", comment: "Start sleep tracking button"))
                            .mcPrimaryButton()
                    }
                    .buttonStyle(PressScaleButtonStyle())
                }
                Button { dismiss() } label: {
                    Text(String(localized: "Close", comment: "Close button"))
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.bottom, DesignTokens.Spacing.s)
        .frame(maxWidth: 520)
    }

    private var doneDetail: String {
        var lines: [String] = []
        if noteParked {
            lines.append(String(localized: "Your note is waiting on Today.", comment: "Wind-down: finished, a note was saved for the morning"))
        }
        lines.append(tracking.isActive
            ? String(localized: "Tracking is on. Put the phone face down.", comment: "Wind-down: finished, tracking already running")
            : String(localized: "Start tracking, then put the phone face down.", comment: "Wind-down: finished, tracking not running"))
        return lines.joined(separator: "\n")
    }

    // MARK: - Flow

    private func begin() {
        noteFocused = false
        noteParked = WindDownNote.park(note, in: storage, nextAlarm: nextAlarmDate) || noteParked
        if noteParked { note = "" }
        let sound = tracking.selectedSound
        if sound != .none && !tracking.isActive {
            SleepAudioPlayer.activatePlayback()
            player.play(sound)
        }
        stage = .breathing(started: .now, length: pacer.wholeBreaths(in: minutes))
    }

    private func finish() {
        Haptics.notify(.success)
        UIApplication.shared.isIdleTimerDisabled = false
        stage = .done
    }

    /// While breathing: keep the screen on, tap at every turn, and end on time.
    private func runSession() async {
        guard case let .breathing(started, length) = stage else { return }
        UIApplication.shared.isIdleTimerDisabled = true
        var index = pacer.moment(at: Date.now.timeIntervalSince(started)).index
        while !Task.isCancelled {
            let elapsed = Date.now.timeIntervalSince(started)
            if elapsed >= length {
                finish()
                return
            }
            let moment = pacer.moment(at: elapsed)
            if moment.index != index {
                index = moment.index
                Haptics.impact(.soft)
            }
            try? await Task.sleep(for: .milliseconds(80))
        }
    }
}

#Preview("Setup") {
    WindDownView(
        storage: InMemoryStorageService(),
        tracking: SleepTrackingService(repository: InMemorySleepSessionRepository()),
        nextAlarmDate: nil,
        onStartTracking: {}
    )
    .nightAppearance()
}
