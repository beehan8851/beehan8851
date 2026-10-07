import SwiftUI

// MARK: - Mission editor sheet

/// Presented from AlarmEditorView to configure or change a single mission slot.
struct MissionEditorView: View {
    @Binding var config: MissionConfig
    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container

    @State private var selectedKind: MissionKind
    @State private var workingConfig: MissionConfig
    @State private var showSetup = false
    @State private var showPreview = false
    @State private var capabilityError: String?
    @State private var paywallFeature: PremiumFeature?

    init(config: Binding<MissionConfig>) {
        _config = config
        let initial = config.wrappedValue
        _selectedKind   = State(wrappedValue: initial.kind)
        _workingConfig  = State(wrappedValue: initial)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DesignTokens.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        kindPicker
                            .padding(.top, DesignTokens.Spacing.s)
                        configSection
                        previewButton
                            .padding(.horizontal, DesignTokens.Spacing.s)
                            .padding(.top, DesignTokens.Spacing.m)
                        Color.clear.frame(height: DesignTokens.Spacing.xl)
                    }
                }
            }
            .navigationTitle(String(localized: "Configure Mission", comment: "Mission editor title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .fullScreenCover(isPresented: $showSetup) { setupSheet.appAppearance() }
            .fullScreenCover(isPresented: $showPreview) { previewCover.appAppearance() }
            .alert(
                String(localized: "Mission Unavailable", comment: "Mission capability error title"),
                isPresented: Binding(get: { capabilityError != nil }, set: { if !$0 { capabilityError = nil } })
            ) {
                Button(String(localized: "OK", comment: "Dismiss")) {}
            } message: { Text(capabilityError ?? "") }
            .paywall(for: $paywallFeature)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(String(localized: "Cancel", comment: "Cancel")) { dismiss() }
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(String(localized: "Save", comment: "Save")) {
                // Soft-lock policy (F1 step 11): Steps needs a pedometer, Jump an
                // accelerometer, QR a camera the user hasn't denied.
                if let reason = MissionCapability.availability(of: workingConfig.kind).reason {
                    capabilityError = reason
                    return
                }
                config = workingConfig
                dismiss()
            }
            .fontWeight(.semibold)
            .foregroundStyle(DesignTokens.Colors.emberText)
        }
    }

    // MARK: Kind picker

    private var kindPicker: some View {
        VStack(spacing: 0) {
            sectionHeader(String(localized: "Mission Type", comment: "Mission type section"))
            ForEach(Array(MissionKind.allCases.enumerated()), id: \.element.id) { idx, kind in
                if idx > 0 { cardDivider }
                kindRow(kind)
            }
        }
        .background(DesignTokens.Colors.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
        .padding(.horizontal, DesignTokens.Spacing.s)
    }

    private func kindRow(_ kind: MissionKind) -> some View {
        let isLocked = kind.isPremium && !container.isPremium
        return Button {
            guard !isLocked else {
                paywallFeature = .advancedMissions
                return
            }
            Haptics.selection()
            selectedKind = kind
            workingConfig = kind.defaultConfig
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(selectedKind == kind ? DesignTokens.Colors.accent : DesignTokens.Colors.textTertiary)
                    .frame(width: 22)
                Text(kind.displayName)
                    .font(.mcBody)
                    .foregroundStyle(isLocked ? DesignTokens.Colors.textSecondary : DesignTokens.Colors.textPrimary)
                Spacer()
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                } else if selectedKind == kind {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(DesignTokens.Colors.emberText)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isLocked
                           ? String(localized: "Premium mission. Opens the upgrade screen.", comment: "Locked mission accessibility hint")
                           : "")
    }

    // MARK: Config section

    @ViewBuilder
    private var configSection: some View {
        switch workingConfig {
        case .math(let d, let r):
            mathConfig(difficulty: d, rounds: r)
        case .shake(let n):
            countConfig(label: String(localized: "Shakes", comment: "Shake target label"),
                        range: 5...30, step: 5, value: n) { workingConfig = .shake(targetCount: $0) }
        case .steps(let n):
            countConfig(label: String(localized: "Steps", comment: "Steps target label"),
                        range: 10...100, step: 10, value: n) { workingConfig = .steps(targetCount: $0) }
        case .qrCode:
            qrSetupRow
        case .memory(let d, let r):
            memoryConfig(difficulty: d, rounds: r)
        case .typing(let phrase):
            typingConfig(phrase: phrase)
        case .draw:
            drawSetupRow
        case .jump(let n):
            countConfig(label: String(localized: "Jumps", comment: "Jump target label"),
                        range: 3...20, step: 1, value: n) { workingConfig = .jump(targetCount: $0) }
        case .catchCat(let n):
            countConfig(label: String(localized: "Catches", comment: "Catch the cat target label"),
                        range: 5...20, step: 1, value: n) { workingConfig = .catchCat(catches: $0) }
        }
    }

    private func mathConfig(difficulty: MathDifficulty, rounds: Int) -> some View {
        VStack(spacing: 0) {
            sectionHeader(String(localized: "Settings", comment: "Settings section header")).padding(.top, DesignTokens.Spacing.m)
            VStack(spacing: 0) {
                enumPickerRow(
                    label: String(localized: "Difficulty", comment: "Difficulty label"),
                    cases: MathDifficulty.allCases,
                    selected: difficulty,
                    label: \.displayName
                ) { workingConfig = .math(difficulty: $0, rounds: rounds) }
                cardDivider
                stepperRow(
                    label: String(localized: "Rounds", comment: "Rounds label"),
                    value: rounds, range: 1...10
                ) { workingConfig = .math(difficulty: difficulty, rounds: $0) }
            }
            .background(DesignTokens.Colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
            .padding(.horizontal, DesignTokens.Spacing.s)
        }
    }

    private func memoryConfig(difficulty: MemoryDifficulty, rounds: Int) -> some View {
        VStack(spacing: 0) {
            sectionHeader(String(localized: "Settings", comment: "Settings section header")).padding(.top, DesignTokens.Spacing.m)
            VStack(spacing: 0) {
                enumPickerRow(
                    label: String(localized: "Difficulty", comment: "Difficulty label"),
                    cases: MemoryDifficulty.allCases,
                    selected: difficulty,
                    label: \.displayName
                ) { workingConfig = .memory(difficulty: $0, rounds: rounds) }
                cardDivider
                stepperRow(
                    label: String(localized: "Rounds", comment: "Rounds label"),
                    value: rounds, range: 1...5
                ) { workingConfig = .memory(difficulty: difficulty, rounds: $0) }
            }
            .background(DesignTokens.Colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
            .padding(.horizontal, DesignTokens.Spacing.s)
        }
    }

    private func typingConfig(phrase: String) -> some View {
        let binding = Binding(
            get: { phrase },
            set: { workingConfig = .typing(phrase: $0) }
        )
        return VStack(spacing: 0) {
            sectionHeader(String(localized: "Phrase", comment: "Typing phrase section")).padding(.top, DesignTokens.Spacing.m)
            HStack {
                TextField(
                    String(localized: "Enter the phrase to type", comment: "Typing phrase placeholder"),
                    text: binding
                )
                .font(.mcBody).foregroundStyle(DesignTokens.Colors.textPrimary)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                if !phrase.isEmpty {
                    Button { workingConfig = .typing(phrase: "") } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16)).foregroundStyle(DesignTokens.Colors.textTertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.vertical, 14)
            .background(DesignTokens.Colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
            .padding(.horizontal, DesignTokens.Spacing.s)

            let remaining = MissionConfig.typingMinimumLength - phrase.trimmingCharacters(in: .whitespacesAndNewlines).count
            Text(remaining > 0
                 ? String(localized: "At least \(MissionConfig.typingMinimumLength) characters — \(remaining) more to go.", comment: "Typing phrase footer, too short")
                 : String(localized: "You'll type this exactly, capitals aside.", comment: "Typing phrase footer"))
                .font(.mcFootnote)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DesignTokens.Spacing.s + 4)
                .padding(.top, 6)
        }
    }

    private var qrSetupRow: some View {
        VStack(spacing: 0) {
            sectionHeader(String(localized: "Registration", comment: "QR registration section")).padding(.top, DesignTokens.Spacing.m)
            Button { showSetup = true } label: {
                HStack {
                    Image(systemName: "qrcode.viewfinder").foregroundStyle(DesignTokens.Colors.emberText)
                    Text(workingConfig.configSummary).font(.mcBody).foregroundStyle(DesignTokens.Colors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .padding(.horizontal, DesignTokens.Spacing.s).padding(.vertical, 14)
                .background(DesignTokens.Colors.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.s)
        }
    }

    private var drawSetupRow: some View {
        VStack(spacing: 0) {
            sectionHeader(String(localized: "Calibration", comment: "Draw calibration section")).padding(.top, DesignTokens.Spacing.m)
            Button { showSetup = true } label: {
                HStack {
                    Image(systemName: "scribble.variable").foregroundStyle(DesignTokens.Colors.emberText)
                    Text(workingConfig.configSummary).font(.mcBody).foregroundStyle(DesignTokens.Colors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .padding(.horizontal, DesignTokens.Spacing.s).padding(.vertical, 14)
                .background(DesignTokens.Colors.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.s)
        }
    }

    private func countConfig(label: String, range: ClosedRange<Int>, step: Int, value: Int, onSet: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 0) {
            sectionHeader(String(localized: "Target", comment: "Target count section")).padding(.top, DesignTokens.Spacing.m)
            HStack {
                Text(label).font(.mcBody).foregroundStyle(DesignTokens.Colors.textPrimary)
                Spacer()
                Stepper("\(value)", value: Binding(get: { value }, set: { onSet(min(range.upperBound, max(range.lowerBound, $0))) }), step: step)
                    .labelsHidden()
                Text("\(value)").font(.mcBody.monospacedDigit()).foregroundStyle(DesignTokens.Colors.emberText).frame(minWidth: 40, alignment: .trailing)
            }
            .padding(.horizontal, DesignTokens.Spacing.s).padding(.vertical, 14)
            .background(DesignTokens.Colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
            .padding(.horizontal, DesignTokens.Spacing.s)
        }
    }

    // MARK: Preview

    private var previewButton: some View {
        let enabled = workingConfig.isConfigured
        return Button {
            Haptics.impact(.medium)
            showPreview = true
        } label: {
            Label(String(localized: "Preview Mission", comment: "Preview mission button"), systemImage: "play.circle")
                .font(.mcSubhead)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.s)
                .background(DesignTokens.Colors.surfacePrimary)
                .foregroundStyle(enabled ? DesignTokens.Colors.accent : DesignTokens.Colors.textTertiary)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: Setup sheet

    @ViewBuilder
    private var setupSheet: some View {
        switch workingConfig {
        case .qrCode:
            QRSetupView(config: $workingConfig)
        case .draw:
            DrawSetupView(config: $workingConfig)
        default:
            EmptyView()
        }
    }

    // MARK: Preview full-screen

    @ViewBuilder
    private var previewCover: some View {
        ZStack(alignment: .topLeading) {
            missionForConfig(workingConfig, onSuccess: { showPreview = false })
                .environment(AppContainer.preview())
            Button { showPreview = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .padding()
            }
        }
        .interactiveDismissDisabled(false)
    }

    @ViewBuilder
    private func missionForConfig(_ config: MissionConfig, onSuccess: @escaping () -> Void) -> some View {
        switch config {
        case .math:   MathMissionView(config: config, onSuccess: onSuccess)
        case .shake:  ShakeMissionView(config: config, onSuccess: onSuccess)
        case .steps:  StepsMissionView(config: config, onSuccess: onSuccess)
        case .qrCode: QRMissionView(config: config, onSuccess: onSuccess)
        case .memory: MemoryMissionView(config: config, onSuccess: onSuccess)
        case .typing: TypingMissionView(config: config, onSuccess: onSuccess)
        case .draw:   DrawMissionView(config: config, onSuccess: onSuccess)
        case .jump:   JumpMissionView(config: config, onSuccess: onSuccess)
        case .catchCat: CatchCatMissionView(config: config, onSuccess: onSuccess)
        }
    }

    // MARK: Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.s + 4)
            .padding(.bottom, 6)
    }

    private var cardDivider: some View {
        DesignTokens.Colors.surfaceSecondary.opacity(0.8).frame(height: 0.5).padding(.leading, DesignTokens.Spacing.s)
    }

    private func enumPickerRow<T: CaseIterable & Hashable>(
        label: String,
        cases: [T],
        selected: T,
        label nameOf: KeyPath<T, String>,
        onSelect: @escaping (T) -> Void
    ) -> some View {
        HStack {
            Text(label).font(.mcBody).foregroundStyle(DesignTokens.Colors.textPrimary)
            Spacer()
            Picker("", selection: Binding(get: { selected }, set: onSelect)) {
                ForEach(cases, id: \.self) { item in Text(item[keyPath: nameOf]).tag(item) }
            }
            .pickerStyle(.menu)
            .tint(DesignTokens.Colors.accent)
        }
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func stepperRow(label: String, value: Int, range: ClosedRange<Int>, onSet: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(label).font(.mcBody).foregroundStyle(DesignTokens.Colors.textPrimary)
            Spacer()
            Stepper("", value: Binding(get: { value }, set: { onSet(min(range.upperBound, max(range.lowerBound, $0))) }))
                .labelsHidden()
            Text("\(value)").font(.mcBody.monospacedDigit()).foregroundStyle(DesignTokens.Colors.emberText).frame(minWidth: 36, alignment: .trailing)
        }
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.vertical, 13)
    }
}
