import SwiftUI
import UIKit

/// The cat on the Home Screen, in whichever mood suits. Classic is free; the rest
/// are Premium, and a locked one opens the paywall instead.
struct AppIconPickerView: View {
    @Environment(AppContainer.self) private var container
    @State private var current = AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)
    @State private var paywallFeature: PremiumFeature?
    @State private var failed = false
    /// An icon change is with the system (its alert is up): further taps wait.
    @State private var changing = false

    private let columns = [GridItem(.flexible(), spacing: DesignTokens.Spacing.s),
                           GridItem(.flexible(), spacing: DesignTokens.Spacing.s)]

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                    Text(String(localized: "The cat on your Home Screen, in the mood that suits you.", comment: "App icon picker: explanation"))
                        .font(.mcCallout)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: columns, spacing: DesignTokens.Spacing.s) {
                        ForEach(AppIconChoice.allCases) { choice in
                            tile(choice)
                        }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.m)
                .padding(.vertical, DesignTokens.Spacing.s)
            }
        }
        .navigationTitle(String(localized: "App icon", comment: "Settings row and screen title: choose the app icon"))
        .navigationBarTitleDisplayMode(.inline)
        .hidesInkTabBar()
        .paywall(for: $paywallFeature)
        .alert(String(localized: "The icon couldn't be changed.", comment: "App icon picker: error"), isPresented: $failed) {
            Button(String(localized: "OK", comment: "Dismiss")) {}
        }
    }

    private func tile(_ choice: AppIconChoice) -> some View {
        let locked = choice.isPremium && !container.isPremium
        let selected = choice == current
        return Button {
            choose(choice)
        } label: {
            VStack(spacing: DesignTokens.Spacing.xs) {
                AppIconArt(choice: choice).iconShape(92)
                    .padding(5)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: 102 * 0.2237 + 2, style: .continuous)
                                .strokeBorder(DesignTokens.Colors.accent, lineWidth: 3)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(DesignTokens.Colors.yolk)
                                .frame(width: 26, height: 26)
                                .background(DesignTokens.Colors.ink, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                Text(choice.title)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                if locked {
                    Text(String(localized: "PREMIUM", comment: "Premium label on a locked mission tile"))
                        .font(.system(size: 10, weight: .heavy).width(.expanded))
                        .tracking(0.6)
                        .foregroundStyle(DesignTokens.Colors.yolk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignTokens.Colors.ink, in: Capsule())
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DesignTokens.Spacing.s)
            .background(DesignTokens.Colors.surfacePrimary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(choice.title)
        .accessibilityValue(locked ? String(localized: "PREMIUM", comment: "Premium label on a locked mission tile") : "")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func choose(_ choice: AppIconChoice) {
        guard choice != current, !changing else { return }
        if choice.isPremium && !container.isPremium {
            paywallFeature = .appIcons
            return
        }
        guard UIApplication.shared.supportsAlternateIcons else { failed = true; return }
        Haptics.impact(.light)
        changing = true
        Task {
            defer { changing = false }
            do {
                try await UIApplication.shared.setAlternateIconName(choice.alternateIconName)
                current = choice
            } catch {
                failed = true
            }
        }
    }
}

extension AppIconChoice {
    var title: String {
        switch self {
        case .classic: String(localized: "Classic", comment: "App icon: the original, the cat batting the Z away")
        case .startled: String(localized: "Startled", comment: "App icon: the cat with its back arched and fur on end")
        case .night: String(localized: "Night", comment: "App icon: the cat asleep on the moon")
        case .proud: String(localized: "Proud", comment: "App icon: the pleased cat with sparkles")
        case .unimpressed: String(localized: "Unimpressed", comment: "App icon: the grumpy, half-lidded cat")
        }
    }
}

#Preview {
    NavigationStack { AppIconPickerView() }
        .environment(AppContainer.preview(tier: .free))
}
