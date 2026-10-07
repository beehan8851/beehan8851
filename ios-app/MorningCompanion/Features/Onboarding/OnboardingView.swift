import SwiftUI
import UserNotifications

/// Three steps: what the app is, the permissions it needs, and the first alarm. The
/// first is all yolk, the cat pawing at you as the icon does; the others are paper,
/// the cat watching, then pleased. Light throughout (set at the app root).
///
/// No system dialog appears before the user has pressed a button that says what it is
/// for. That is the whole point of the middle step — iOS asks once, and a "Don't
/// Allow" collected in the first two seconds of the app's life cannot be taken back
/// from inside the app.
struct OnboardingView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.pageLayout) private var pageLayout

    @State private var model: OnboardingModel

    @MainActor
    init(model: OnboardingModel = OnboardingModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ZStack {
            (model.step == .welcome ? DesignTokens.Colors.yolk : DesignTokens.Colors.background).ignoresSafeArea()

            if spread {
                // Open like a book: the picture on the left page — the cat, and on the
                // last step the time it will ring — the words and buttons on the right.
                HStack(spacing: PageLayout.gutter) {
                    picture
                        .padding(.leading, DesignTokens.Spacing.s)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    page
                        .frame(maxWidth: .infinity)
                }
            } else {
                page
            }
        }
        .animation(.easeInOut(duration: DesignTokens.Motion.controls), value: model.step)
        .task {
            #if DEBUG
            if let step = DebugLaunch.onboardingStep, let target = OnboardingModel.Step(rawValue: step) {
                model.go(to: target)
            }
            #endif
            await model.refreshPermissions()
        }
    }

    /// Two pages, unless the text is so large that half the screen will not hold it.
    private var spread: Bool { pageLayout == .spread && !dynamicTypeSize.isAccessibilitySize }

    @ViewBuilder
    private var picture: some View {
        switch model.step {
        case .welcome:
            CatMascot(mood: .ringing, ground: .light)
                .frame(maxWidth: 300)
        case .permissions:
            CatMascot(mood: .awake, ground: .light)
                .frame(maxWidth: 260)
        case .firstAlarm:
            VStack(spacing: DesignTokens.Spacing.s) {
                CatMascot(mood: .proud, ground: .light)
                    .frame(width: 120)
                drums
            }
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                            switch model.step {
                            case .welcome:     welcome
                            case .permissions: permissionsStep
                            case .firstAlarm:  firstAlarmStep
                            }
                        }
                        .padding(.horizontal, DesignTokens.Spacing.s)
                        .padding(.top, model.step == .welcome ? DesignTokens.Spacing.xl : DesignTokens.Spacing.l)
                        .padding(.bottom, DesignTokens.Spacing.m)
                    }
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            footer
        }
    }

    // MARK: - Step 1 · What this is

    private var welcome: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            if !spread {
                CatMascot(mood: .ringing, ground: .light)
                    .frame(maxWidth: 230)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, DesignTokens.Spacing.xs)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(String(localized: "Sleep peacefully.\nWake confidently.", comment: "Onboarding tagline"))
                    .font(.mcTitle1)
                    .foregroundStyle(DesignTokens.Colors.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(
                    localized: "Dawnwick rings through Silent mode and Focus, then asks you to do one small thing before it stops.",
                    comment: "Onboarding subtitle"
                ))
                .font(.mcCallout)
                .foregroundStyle(DesignTokens.Colors.onYolkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                point("alarm.waves.left.and.right",
                      String(localized: "A real system alarm, not a notification", comment: "Onboarding point: system alarm"))
                point("figure.walk.motion",
                      String(localized: "Missions that make sure you're actually up", comment: "Onboarding point: missions"))
                point("bed.double",
                      String(localized: "Your sleep, tracked without wearing anything", comment: "Onboarding point: sleep"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.ink)
                .frame(width: 26, alignment: .leading)
            Text(text)
                .font(.mcBody)
                .foregroundStyle(DesignTokens.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Step 2 · Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            if !spread {
                CatMascot(mood: .awake, ground: .light)
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
            }
            stepHeader {
                Text(String(localized: "Alarms that actually ring", comment: "Onboarding permissions title"))
                    .font(.mcTitle2)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(String(
                    localized: "Dawnwick uses the system alarm, so it sounds even when your phone is silenced. iOS will ask you twice.",
                    comment: "Onboarding permissions subtitle"
                ))
                .font(.mcCallout)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                permissionRow(
                    title: String(localized: "Alarms & Timers", comment: "AlarmKit permission name"),
                    detail: String(localized: "Lets the alarm sound through Silent mode and Focus.", comment: "AlarmKit permission rationale"),
                    state: alarmRowState
                )
                Divider().padding(.leading, 52)
                permissionRow(
                    title: String(localized: "Notifications", comment: "Notification permission name"),
                    detail: String(localized: "Used for wake checks and snooze reminders.", comment: "Notification permission rationale"),
                    state: notificationRowState
                )
            }
            .background(DesignTokens.Colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))

            if model.isAnyPermissionDenied {
                deniedNotice
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var alarmRowState: PermissionRowState {
        switch model.alarmAuthorization {
        case .authorized: return .granted
        case .denied:     return .denied
        default:          return .pending
        }
    }

    private var notificationRowState: PermissionRowState {
        switch model.notificationAuthorization {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied:                               return .denied
        default:                                    return .pending
        }
    }

    private func permissionRow(title: String, detail: String, state: PermissionRowState) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.s) {
            Image(systemName: state.symbol)
                .font(.system(size: 18))
                .foregroundStyle(state.tint)
                .frame(width: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.mcHeadline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(detail)
                    .font(.mcFootnote)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(state.accessibilityValue)
    }

    /// Shown only once a permission has actually been refused. iOS will not prompt
    /// again, so the honest thing is to say so and point at the one place that can
    /// still change it.
    private var deniedNotice: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(model.canAlarmsRing
                 ? String(localized: "Wake checks and snooze reminders are off.", comment: "Notifications denied notice")
                 : String(localized: "Without Alarms & Timers, Dawnwick can't wake you.", comment: "Alarm permission denied notice"))
                .font(.mcSubhead)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(
                localized: "iOS only asks once. You can turn it on in Settings and come straight back.",
                comment: "Explains that the system will not prompt again"
            ))
            .font(.mcFootnote)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "Open Settings", comment: "Opens the app's page in the Settings app")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.system(.subheadline, weight: .bold))
            .foregroundStyle(DesignTokens.Colors.accent)
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.s)
        .background(DesignTokens.Colors.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
    }

    /// Title and subtitle of a step.
    private func stepHeader<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Step 3 · First alarm

    private var firstAlarmStep: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.s) {
                stepHeader {
                    Text(String(localized: "Set your first alarm", comment: "Onboarding first alarm title"))
                        .font(.mcTitle2)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(String(localized: "Every day, to start with. You can change all of this later.", comment: "Onboarding first alarm subtitle"))
                        .font(.mcCallout)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !dynamicTypeSize.isAccessibilitySize && !spread {
                    CatMascot(mood: .proud, ground: .light)
                        .frame(width: 86)
                }
            }

            if !spread { drums }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(String(localized: "How you'll turn it off", comment: "Onboarding mission chooser label"))
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)

                HStack(spacing: 10) {
                    missionChoice(.math, title: String(localized: "Math", comment: "Math mission name"))
                    missionChoice(.shake, title: String(localized: "Shake", comment: "Shake mission name"))
                }

                Text(missionExplanation)
                    .font(.mcFootnote)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = model.alarmSaveError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.mcFootnote)
                    .foregroundStyle(DesignTokens.Colors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var drums: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            TimeDrumPicker(
                hour: Binding(get: { model.wakeTime.hour },
                              set: { model.wakeTime = AlarmTime(hour: $0, minute: model.wakeTime.minute) }),
                minute: Binding(get: { model.wakeTime.minute },
                                set: { model.wakeTime = AlarmTime(hour: model.wakeTime.hour, minute: $0) })
            )
            .accessibilityLabel(String(localized: "Wake time", comment: "Onboarding time picker label"))
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(DesignTokens.Colors.yolk, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous))
    }

    private var missionExplanation: String { model.mission.onboardingDescription }

    /// One of the two free missions, as a tile with its moving picture.
    private func missionChoice(_ kind: MissionKind, title: String) -> some View {
        let chosen = model.mission == kind
        return Button {
            Haptics.selection()
            withAnimation(.snappy(duration: 0.25)) { model.mission = kind }
        } label: {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(chosen ? DesignTokens.Colors.ink : DesignTokens.Colors.onTile)
                MissionArt(kind: kind, tone: chosen ? .onYolk : .onInk)
                    .frame(width: 84, height: 56)
                    .padding(.leading, -6)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(chosen ? DesignTokens.Colors.yolk : DesignTokens.Colors.tile,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Button {
                Task { await performPrimaryAction() }
            } label: {
                if model.step == .welcome {
                    Text(primaryTitle).mcInkButton()
                } else {
                    Text(primaryTitle).mcPrimaryButton()
                }
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(model.isRequestingPermissions || model.isSavingAlarm)
            .opacity(model.isRequestingPermissions || model.isSavingAlarm ? 0.5 : 1)

            if let title = secondaryTitle {
                Button(title) { secondaryAction() }
                    .font(.mcCallout)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(minHeight: 44)
            } else {
                Color.clear.frame(height: 44)
            }

            stepIndicator
        }
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.top, DesignTokens.Spacing.xs)
        .background(alignment: .top) {
            (model.step == .welcome ? DesignTokens.Colors.yolk : DesignTokens.Colors.background)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingModel.Step.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step == model.step ? DesignTokens.Colors.ink : DesignTokens.Colors.ink.opacity(0.22))
                    .frame(width: step == model.step ? 18 : 6, height: 6)
            }
        }
        .padding(.bottom, DesignTokens.Spacing.xs)
        .accessibilityElement()
        .accessibilityLabel(String(
            localized: "Step \(model.step.rawValue + 1) of \(OnboardingModel.Step.allCases.count)",
            comment: "Onboarding progress"
        ))
    }

    private var primaryTitle: String {
        switch model.step {
        case .welcome:
            return String(localized: "Get Started", comment: "Onboarding CTA")
        case .permissions:
            return model.hasDecidedAlarmPermission
                ? String(localized: "Continue", comment: "Onboarding continue after permissions")
                : String(localized: "Allow Alarms", comment: "Requests the alarm permissions")
        case .firstAlarm:
            return String(localized: "Create Alarm", comment: "Creates the first alarm")
        }
    }

    private var secondaryTitle: String? {
        switch model.step {
        case .welcome:
            return nil
        case .permissions:
            return model.hasDecidedAlarmPermission
                ? nil
                : String(localized: "Not now", comment: "Skips the permission request")
        case .firstAlarm:
            return String(localized: "Skip for now", comment: "Finishes onboarding without creating an alarm")
        }
    }

    private func performPrimaryAction() async {
        switch model.step {
        case .welcome:
            model.advance()
        case .permissions:
            if model.hasDecidedAlarmPermission {
                model.advance()
            } else {
                await model.requestPermissions()
                container.refreshAlarmKitAuthorization()
            }
        case .firstAlarm:
            if await model.saveFirstAlarm(using: container.alarmManager) {
                container.markOnboardingComplete()
            }
        }
    }

    private func secondaryAction() {
        switch model.step {
        case .welcome:
            break
        case .permissions:
            model.advance()
        case .firstAlarm:
            container.markOnboardingComplete()
        }
    }
}

// MARK: - Row state presentation

/// Whether a permission has been asked for yet, and how it went.
private enum PermissionRowState {
    case pending, granted, denied

    var symbol: String {
        switch self {
        case .pending: return "circle"
        case .granted: return "checkmark.circle.fill"
        case .denied:  return "exclamationmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .pending: return DesignTokens.Colors.textTertiary
        case .granted: return DesignTokens.Colors.success
        case .denied:  return DesignTokens.Colors.destructive
        }
    }

    var accessibilityValue: String {
        switch self {
        case .pending: return String(localized: "Not asked yet", comment: "Permission row state")
        case .granted: return String(localized: "Allowed", comment: "Permission row state")
        case .denied:  return String(localized: "Not allowed", comment: "Permission row state")
        }
    }
}

// MARK: - Previews

#Preview("Welcome") {
    OnboardingView()
        .environment(AppContainer.preview())
}

#Preview("Permission denied") {
    OnboardingView(model: {
        let model = OnboardingModel(permissions: StubOnboardingPermissions(
            state: .init(alarmOnRequest: .denied, notificationsOnRequest: .denied)
        ))
        model.go(to: .permissions)
        return model
    }())
    .environment(AppContainer.preview())
}
