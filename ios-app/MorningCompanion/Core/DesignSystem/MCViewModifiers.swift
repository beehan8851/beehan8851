import SwiftUI

extension View {
    /// A section that has to stand on its own outside a List. Prefer a List section.
    func mcCard() -> some View {
        self
            .padding(DesignTokens.Spacing.s)
            .background(DesignTokens.Colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
    }

    /// Card that fills its container's height — for side-by-side equal-height rows.
    /// Do NOT use on a full-width card in a vertical stack: `maxHeight: .infinity`
    /// would make it absorb all remaining screen height.
    func mcFillCard() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .mcCard()
    }

    /// Recessed secondary surface
    func mcSurface() -> some View {
        self
            .background(DesignTokens.Colors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.s))
    }

    /// Full-width primary action button style: yolk with ink type.
    ///
    /// Apply it to the **label inside** the button — `Button { } label: { Text(t).mcPrimaryButton() }`
    /// — never to the `Button` itself. On the outside it paints a full-width plate
    /// whose only tappable part is the text in the middle (found on the onboarding
    /// button, 2026-09-09).
    func mcPrimaryButton() -> some View {
        self
            .font(.mcButton)
            .foregroundStyle(DesignTokens.Colors.onAccent)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.button)
            .background(DesignTokens.Colors.accentFill)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous))
    }

    /// The primary button on a yolk surface: ink with yolk type. Same rule: on the label.
    func mcInkButton() -> some View {
        self
            .font(.mcButton)
            .foregroundStyle(DesignTokens.Colors.yolk)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.button)
            .background(DesignTokens.Colors.ink)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous))
    }

    /// Full-width secondary action: a quiet fill, primary type. Same rule: on the label.
    func mcSecondaryButton() -> some View {
        self
            .font(.system(.headline, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.button)
            .background(DesignTokens.Colors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous))
    }

    /// Destructive action button style. Same rule as `mcPrimaryButton`: on the label, not the button.
    func mcDestructiveButton() -> some View {
        self
            .font(.system(.headline, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.destructive)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.Size.button)
            .background(DesignTokens.Colors.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous))
    }

    /// A List on the app's page colour instead of the system grey.
    func mcList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(DesignTokens.Colors.background.ignoresSafeArea())
    }

    /// Rows of a List section on the app's surface colour. Apply to each Section.
    func mcRows() -> some View {
        self
            .listRowBackground(DesignTokens.Colors.surfacePrimary)
            .listRowSeparatorTint(DesignTokens.Colors.separator)
    }
}

// MARK: - Section title

/// The title over a group on a page that is not a plain list: rounded, primary
/// colour, with an optional trailing control. Replaces the small grey list header
/// where a section is a destination of its own (Today, Progress, Sleep).
struct MCSectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.mcSectionTitle)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DesignTokens.Spacing.xs)
            trailing()
        }
    }
}

extension MCSectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

// MARK: - Appearance for presented views

/// `preferredColorScheme` set on the root does not reach a `sheet` or a
/// `fullScreenCover`: each presentation is its own window scene and falls back to
/// the system appearance. Every presented root applies this, so "Dark" in Settings
/// means dark on the ring screen too.
private struct AppAppearanceModifier: ViewModifier {
    @Environment(AppContainer.self) private var container
    func body(content: Content) -> some View {
        content.preferredColorScheme(container.appPreferences.appearance.colorScheme)
    }
}

extension View {
    func appAppearance() -> some View { modifier(AppAppearanceModifier()) }

    /// The night screens: the dark appearance whatever the setting.
    func nightAppearance() -> some View {
        self
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
    }

    /// The morning screens — the ring, a mission, the success, the wake check — are
    /// yolk and paper whatever the setting: they are there to wake you, and they are the
    /// screens that carry the brand. Use instead of `appAppearance()` on those roots.
    func daylightAppearance() -> some View {
        self
            .environment(\.colorScheme, .light)
            .preferredColorScheme(.light)
    }
}
