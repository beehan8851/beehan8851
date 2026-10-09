import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppContainer.self) private var container
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel: SettingsViewModel?
    @State private var paywallFeature: PremiumFeature?
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    @State private var appIcon = AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName)

    var body: some View {
        @Bindable var preferences = container.appPreferences

        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            List {
                if !container.isPremium { premiumCard }
                permissionsSection

                Section(String(localized: "Alarm defaults", comment: "Alarm defaults settings section")) {
                    Picker(String(localized: "Default sound", comment: "Default alarm sound setting"), selection: $preferences.defaultAlarmSound) {
                        ForEach(AlarmSound.allCases, id: \.self) { sound in
                            Text(sound.displayName).tag(sound)
                        }
                    }

                    Toggle(String(localized: "Haptics", comment: "Haptics setting"), isOn: $preferences.hapticsEnabled)
                        .tint(DesignTokens.Colors.accent)
                }
                .listRowBackground(DesignTokens.Colors.surfacePrimary)

                Section(String(localized: "Appearance", comment: "Appearance settings section")) {
                    Picker(String(localized: "Theme", comment: "App appearance setting"), selection: $preferences.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.displayName).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)

                    NavigationLink {
                        AppIconPickerView()
                    } label: {
                        HStack {
                            Label {
                                Text(String(localized: "App icon", comment: "Settings row and screen title: choose the app icon"))
                            } icon: {
                                AppIconArt(choice: appIcon).iconShape(26)
                            }
                            Spacer()
                            Text(appIcon.title)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }
                }
                .listRowBackground(DesignTokens.Colors.surfacePrimary)

                subscriptionSection
                aboutSection
                colophon
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .labelStyle(SettingsLabelStyle())
            .tint(DesignTokens.Colors.accent)
        }
        .paywall(for: $paywallFeature)
        .alert(
            String(localized: "Restore Purchases", comment: "Restore purchases alert title"),
            isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })
        ) {
            Button(String(localized: "OK", comment: "Dismiss")) {}
        } message: { Text(restoreMessage ?? "") }
        .onAppear { appIcon = AppIconChoice(alternateIconName: UIApplication.shared.alternateIconName) }
        .navigationTitle(String(localized: "Settings", comment: "Settings navigation title"))
        .navigationBarTitleDisplayMode(.large)
        .task {
            if viewModel == nil {
                viewModel = SettingsViewModel(healthKitService: container.healthKitService)
            }
            await viewModel?.loadStatuses()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            container.refreshAlarmKitAuthorization()
            Task { await viewModel?.loadStatuses() }
        }
    }

    /// Free users only: what Premium is, on an ink card with a yolk button, one tap
    /// from the plans.
    private var premiumCard: some View {
        Section {
            Button {
                paywallFeature = .general
            } label: {
                HStack(alignment: .center, spacing: DesignTokens.Spacing.s) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        Text(String(localized: "Dawnwick Premium", comment: "Subscription entry title"))
                            .font(.mcTitle3)
                            .foregroundStyle(DesignTokens.Colors.onTile)
                        Text(String(localized: "Unlock every mission, every alarm and your full sleep history.", comment: "Paywall subtitle"))
                            .font(.mcCallout)
                            .foregroundStyle(DesignTokens.Colors.nightTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(String(localized: "See Premium", comment: "Open paywall from save error"))
                            .font(.system(.subheadline, weight: .bold))
                            .foregroundStyle(DesignTokens.Colors.ink)
                            .padding(.horizontal, DesignTokens.Spacing.s)
                            .frame(minHeight: 38)
                            .background(DesignTokens.Colors.yolk,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .padding(.top, DesignTokens.Spacing.xxs)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    CatMascot(mood: .proud, ground: .dark)
                        .frame(width: 92)
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(DesignTokens.Colors.tile)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 16))
        }
    }

    private var permissionsSection: some View {
        Section(String(localized: "Connections", comment: "Connection settings section")) {
            Link(destination: notificationSettingsURL) {
                settingsValueRow(
                    title: String(localized: "Alarms", comment: "AlarmKit permission settings row"),
                    value: container.alarmKitAuthorization.displayName,
                    systemImage: "alarm.waves.left.and.right"
                )
            }

            Link(destination: notificationSettingsURL) {
                settingsValueRow(
                    title: String(localized: "Notifications", comment: "Notification settings row"),
                    value: viewModel?.notificationStatus.displayName ?? String(localized: "Loading…", comment: "Settings status loading"),
                    systemImage: "bell.fill"
                )
            }

            settingsValueRow(
                title: String(localized: "Apple Health", comment: "Health connection row"),
                value: viewModel?.healthStatus.settingsDisplayName ?? String(localized: "Loading…", comment: "Settings status loading"),
                systemImage: "heart.fill"
            )
        }
        .listRowBackground(DesignTokens.Colors.surfacePrimary)
    }

    // MARK: - Subscription

    @ViewBuilder
    private var subscriptionSection: some View {
        Section(String(localized: "Subscription", comment: "Subscription settings section")) {
            if container.isPremium {
                settingsValueRow(
                    title: String(localized: "Dawnwick Premium", comment: "Subscription entry title"),
                    value: premiumStatusValue,
                    systemImage: "star.fill"
                )
                Button {
                    Task { try? await container.subscriptionService.showManageSubscriptions() }
                } label: {
                    Label(String(localized: "Manage Subscription", comment: "Manage subscription row"), systemImage: "creditcard.fill")
                }
            } else {
                Button {
                    paywallFeature = .general
                } label: {
                    settingsValueRow(
                        title: String(localized: "Dawnwick Premium", comment: "Subscription entry title"),
                        value: String(localized: "Free", comment: "Free subscription tier"),
                        systemImage: "star.fill"
                    )
                }
            }

            Button {
                Task { await restorePurchases() }
            } label: {
                HStack {
                    Label(String(localized: "Restore Purchases", comment: "Restore purchases row"), systemImage: "arrow.clockwise")
                    if isRestoring {
                        Spacer()
                        ProgressView().tint(DesignTokens.Colors.accent)
                    }
                }
            }
            .disabled(isRestoring)
        }
        .listRowBackground(DesignTokens.Colors.surfacePrimary)
    }

    /// "Renews 12 Jan 2027" when the store told us; plain "Premium" otherwise
    /// (lifetime, family sharing, or an entitlement served from the offline cache).
    private var premiumStatusValue: String {
        guard let date = container.subscriptionService.expirationDate else {
            return String(localized: "Premium", comment: "Premium subscription tier")
        }
        return String(
            localized: "Renews \(date.formatted(date: .abbreviated, time: .omitted))",
            comment: "Subscription renewal date"
        )
    }

    private func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            switch try await container.subscriptionService.restorePurchases() {
            case .success(.premium):
                restoreMessage = String(localized: "Premium is active on this device.", comment: "Restore succeeded")
            case .success(.free), .cancelled:
                restoreMessage = String(localized: "No previous Premium purchase was found for this Apple Account.", comment: "Restore found nothing")
            }
        } catch {
            restoreMessage = error.localizedDescription
        }
    }

    // MARK: - About

    /// The ask first, then help, then the legal pair. Every row leaves the app, and
    /// says so. The version lives in the colophon below, not in a row.
    private var aboutSection: some View {
        Section(String(localized: "About", comment: "About settings section")) {
            // Appears once `LegalLinks.appStoreID` has the App Store record's id (docs/25).
            if let reviewURL = LegalLinks.reviewURL {
                linkRow(reviewURL, title: String(localized: "Rate Dawnwick", comment: "Rate app settings row"), systemImage: "star.bubble.fill")
            }
            linkRow(LegalLinks.support, title: String(localized: "Help and Contact", comment: "Support settings row"), systemImage: "envelope.fill")
            linkRow(LegalLinks.privacy, title: String(localized: "Privacy Policy", comment: "Privacy policy settings row"), systemImage: "hand.raised.fill")
            linkRow(LegalLinks.terms, title: String(localized: "Terms of Use", comment: "Terms of use settings row"), systemImage: "doc.text.fill")
        }
        .listRowBackground(DesignTokens.Colors.surfacePrimary)
    }

    /// The version, at the end of the list, under the cat asleep on its moon.
    private var colophon: some View {
        Section {
            EmptyView()
        } footer: {
            VStack(spacing: DesignTokens.Spacing.xs) {
                CatMascot(mood: .sleeping)
                    .frame(width: 96)
                    .opacity(0.9)
                Text(verbatim: "Dawnwick \(Self.versionString)")
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DesignTokens.Spacing.m)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "Version \(Self.versionString)", comment: "Settings colophon, VoiceOver"))
        }
    }

    /// A row that opens a web page: label in the text colour, a small outward arrow
    /// instead of the disclosure chevron, so it does not promise a screen it has not got.
    private func linkRow(_ url: URL, title: String, systemImage: String) -> some View {
        Link(destination: url) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    /// Title with its value at the trailing edge — or under it at accessibility sizes,
    /// where the two fought over the width and both lost letters.
    @ViewBuilder
    private func settingsValueRow(title: String, value: String, systemImage: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Label(title, systemImage: systemImage)
                Text(value)
                    .font(.mcCallout)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        } else {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(value)
                    .font(.mcCallout)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
    }

    private var notificationSettingsURL: URL {
        URL(string: UIApplication.openNotificationSettingsURLString)
            ?? URL(string: UIApplication.openSettingsURLString)!
    }
}

/// Accent icon, ink title — the same on a plain row, a `Link` and a `Button`, none of
/// which would otherwise agree on a colour.
private struct SettingsLabelStyle: LabelStyle {
    /// The icon column grows with the type, so a large symbol is not clipped.
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            configuration.icon
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.emberText)
                .frame(width: iconWidth)
            configuration.title
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .environment(AppContainer.preview())
}
