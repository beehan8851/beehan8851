import SwiftUI
import UIKit

// MARK: - Typing mission

struct TypingMissionView: View {
    let config: MissionConfig
    var onSuccess: () -> Void

    private let phrase: String
    @State private var input = ""
    @State private var isWrong = false
    @State private var shakeOffset: CGFloat = 0
    @State private var didSucceed = false
    @FocusState private var focused: Bool

    init(config: MissionConfig, onSuccess: @escaping () -> Void) {
        self.config = config
        self.onSuccess = onSuccess
        if case .typing(let p) = config, !p.isEmpty { phrase = p } else { phrase = "Good morning" }
    }

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            VStack(spacing: 0) {
                missionHeader
                Spacer()
                phraseDisplay
                inputArea
                Spacer()
                submitButton
                    .padding(.horizontal, DesignTokens.Spacing.l)
                    .padding(.bottom, DesignTokens.Spacing.xl)
            }
        }
        .onAppear {
            // The keyboard is the mission. Half a second so the cover has finished
            // presenting; asking earlier is silently ignored.
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                focused = true
            }
        }
    }

    private var missionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: MissionKind.typing.systemImage).font(.system(size: 14)).foregroundStyle(DesignTokens.Colors.emberText)
            Text(String(localized: "Typing", comment: "Typing mission header")).font(.mcSubhead).foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.top, DesignTokens.Spacing.l)
    }

    private var phraseDisplay: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            Text(String(localized: "Type this phrase:", comment: "Typing instruction"))
                .font(.mcCallout)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text("\u{201C}\(phrase)\u{201D}")
                .font(.mcDisplayHero22)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.Spacing.l)
        }
        .padding(.bottom, DesignTokens.Spacing.l)
    }

    private var inputArea: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.m)
                .fill(isWrong ? DesignTokens.Colors.destructive.opacity(0.10) : DesignTokens.Colors.surfacePrimary)
                .animation(.easeInOut(duration: DesignTokens.Motion.immediate), value: isWrong)
            RoundedRectangle(cornerRadius: DesignTokens.Radius.m)
                .stroke(isWrong ? DesignTokens.Colors.destructive : DesignTokens.Colors.surfaceSecondary, lineWidth: 1.5)

            TextField("", text: $input)
                .font(.mcBody)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .tint(DesignTokens.Colors.accent)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .focused($focused)
                .submitLabel(.go)
                .onSubmit { checkAnswer() }
                .padding(.horizontal, DesignTokens.Spacing.s)
        }
        .frame(height: 56)
        .padding(.horizontal, DesignTokens.Spacing.l)
        .offset(x: shakeOffset)
    }

    private var submitButton: some View {
        Button { checkAnswer() } label: {
            Text(String(localized: "Submit", comment: "Submit typing answer"))
                .font(.mcHeadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.s)
                .background(input.isEmpty ? DesignTokens.Colors.surfaceSecondary : DesignTokens.Colors.ember)
                .foregroundStyle(input.isEmpty ? DesignTokens.Colors.textTertiary : DesignTokens.Colors.onEmber)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m))
                .animation(.easeInOut(duration: DesignTokens.Motion.immediate), value: input.isEmpty)
        }
        .disabled(input.isEmpty)
        .buttonStyle(.plain)
    }

    private func checkAnswer() {
        guard !didSucceed else { return }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == phrase.lowercased() {
            didSucceed = true
            Haptics.notify(.success)
            onSuccess()
        } else {
            Haptics.notify(.error)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.2)) { isWrong = true; shakeOffset = 12 }
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { shakeOffset = 0 }
                try? await Task.sleep(nanoseconds: 200_000_000)
                withAnimation { isWrong = false }
                input = ""
                focused = true
            }
        }
    }
}

#Preview("Typing mission") {
    TypingMissionView(config: .typing(phrase: "Good morning"), onSuccess: {})
        .environment(AppContainer.preview())
}
