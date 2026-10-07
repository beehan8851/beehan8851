import SwiftUI

/// The missions as tiles, two to a row, each with a small moving picture of what you
/// will do. Tap a tile to add it to the wake sequence (or take it out), hold one to
/// try it, up to three in the order they were tapped. A chosen tile turns yolk and
/// shows its place in the sequence; the sequence reads out above the Done button.
struct MissionPickerView: View {
    @Binding var missions: [MissionConfig]

    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container
    @State private var preview: MissionKind?
    @State private var paywallFeature: PremiumFeature?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    private static let limit = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                    Text(String(localized: "Tap to add · hold to try · up to \(Self.limit)", comment: "Mission picker hint"))
                        .font(.mcCallout)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(MissionKind.allCases) { kind in tile(kind) }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.s)
                .padding(.top, DesignTokens.Spacing.xs)
                .padding(.bottom, DesignTokens.Spacing.m)
            }
            .background(DesignTokens.Colors.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle(String(localized: "Missions", comment: "Mission picker title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Cancel")) { dismiss() }
                }
            }
            .fullScreenCover(item: $preview) { kind in previewCover(kind).daylightAppearance() }
            .paywall(for: $paywallFeature)
        }
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Text(summary)
                .font(.mcCallout)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: DesignTokens.Motion.controls), value: missions.count)
            Button { dismiss() } label: {
                Text(String(localized: "Done", comment: "Mission picker done")).mcPrimaryButton()
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(missions.isEmpty)
            .opacity(missions.isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.top, DesignTokens.Spacing.sm)
        .padding(.bottom, DesignTokens.Spacing.xs)
        .background(DesignTokens.Colors.background.ignoresSafeArea())
    }

    // MARK: Tiles

    private func tile(_ kind: MissionKind) -> some View {
        let position = missions.firstIndex { $0.kind == kind }
        let isLocked = kind.isPremium && !container.isPremium
        let isFull = position == nil && missions.count >= Self.limit
        let chosen = position != nil
        let ink = chosen ? DesignTokens.Colors.ink : DesignTokens.Colors.onTile
        return Button {
            toggle(kind, position: position, locked: isLocked, full: isFull)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.displayName)
                            .font(.system(.headline, weight: .bold))
                            .foregroundStyle(ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(kind.pickerLine)
                            .font(.mcCaption)
                            .foregroundStyle(ink.opacity(0.6))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let position {
                        Text("\(position + 1)")
                            .font(.system(.footnote, weight: .heavy).width(.expanded))
                            .foregroundStyle(DesignTokens.Colors.yolk)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(DesignTokens.Colors.ink))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Spacer(minLength: DesignTokens.Spacing.xs)
                HStack(alignment: .bottom) {
                    MissionArt(kind: kind, tone: chosen ? .onYolk : .onInk)
                        .frame(width: 96, height: 64)
                        .opacity(isLocked ? 0.55 : 1)
                        .padding(.leading, -6)
                    Spacer(minLength: 0)
                    if isLocked {
                        Text(String(localized: "PREMIUM", comment: "Premium label on a locked mission tile"))
                            .font(.system(size: 10, weight: .heavy).width(.expanded))
                            .tracking(0.6)
                            .foregroundStyle(DesignTokens.Colors.yolk)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(chosen ? DesignTokens.Colors.yolk : DesignTokens.Colors.tile,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .opacity(isFull ? 0.45 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                guard !isLocked else { return }
                Haptics.impact(.medium)
                preview = kind
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.displayName)
        .accessibilityValue(accessibilityValue(position: position, locked: isLocked))
        .accessibilityHint(String(localized: "Double-tap to add or remove.", comment: "Mission tile hint"))
        .accessibilityAddTraits(position == nil ? .isButton : [.isButton, .isSelected])
    }

    private func accessibilityValue(position: Int?, locked: Bool) -> String {
        if let position {
            return String(localized: "Selected, step \(position + 1)", comment: "Mission tile VoiceOver value")
        }
        return locked ? String(localized: "Premium", comment: "Mission tile VoiceOver value, locked") : ""
    }

    private func toggle(_ kind: MissionKind, position: Int?, locked: Bool, full: Bool) {
        if let position {
            Haptics.selection()
            _ = withAnimation(.snappy(duration: 0.28)) { missions.remove(at: position) }
            return
        }
        guard !locked else { paywallFeature = .advancedMissions; return }
        guard !full else { Haptics.notify(.warning); return }
        Haptics.selection()
        withAnimation(.snappy(duration: 0.28)) { missions.append(kind.defaultConfig) }
    }

    private var summary: String {
        guard !missions.isEmpty else {
            return String(localized: "Pick at least one mission", comment: "Mission picker footer, nothing selected")
        }
        let chain = missions.map(\.displayName).joined(separator: " → ")
        return String(localized: "Selected: \(chain)", comment: "Mission picker footer")
    }

    // MARK: Preview

    private func previewCover(_ kind: MissionKind) -> some View {
        ZStack(alignment: .topTrailing) {
            DesignTokens.Colors.background.ignoresSafeArea()
            previewMission(kind) { preview = nil }
            Button { preview = nil } label: {
                Image(systemName: "xmark")
                    .font(.mcHeadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(DesignTokens.Colors.surfaceSecondary)
                    .clipShape(Circle())
                    .padding()
            }
            .accessibilityLabel(String(localized: "Close preview", comment: "Close mission preview"))
        }
    }

    private func previewConfig(_ kind: MissionKind) -> MissionConfig {
        if case .typing = kind.defaultConfig { return .typing(phrase: "I am awake and ready") }
        return kind.defaultConfig
    }

    @ViewBuilder
    private func previewMission(_ kind: MissionKind, onSuccess: @escaping () -> Void) -> some View {
        let config = previewConfig(kind)
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
}

// MARK: - What each mission asks of you

private extension MissionKind {
    /// A few words for the tile: what you will do, not how it is configured.
    var pickerLine: String {
        switch self {
        case .math:   return String(localized: "Solve sums", comment: "Mission picker tile: what the Math mission asks")
        case .shake:  return String(localized: "Shake the phone", comment: "Mission picker tile: what the Shake mission asks")
        case .steps:  return String(localized: "Walk around", comment: "Mission picker tile: what the Steps mission asks")
        case .qrCode: return String(localized: "Scan a code", comment: "Mission picker tile: what the QR mission asks")
        case .memory: return String(localized: "Repeat a pattern", comment: "Mission picker tile: what the Memory mission asks")
        case .typing: return String(localized: "Type a phrase", comment: "Mission picker tile: what the Typing mission asks")
        case .draw:   return String(localized: "Trace a shape", comment: "Mission picker tile: what the Draw mission asks")
        case .jump:   return String(localized: "Jump on the spot", comment: "Mission picker tile: what the Jump mission asks")
        case .catchCat: return String(localized: "Tap it before it jumps", comment: "Mission picker tile: what the Catch the cat mission asks")
        }
    }
}

#Preview {
    struct Host: View {
        @State private var missions: [MissionConfig] = [.defaultMath, .defaultShake]
        var body: some View { MissionPickerView(missions: $missions) }
    }
    return Host().environment(AppContainer.preview())
}
