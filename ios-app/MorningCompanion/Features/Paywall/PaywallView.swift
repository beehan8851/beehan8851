import SwiftUI

/// Dawnwick Premium paywall.
///
/// One left-aligned column: the promise on a yolk band with the cat, what you get, what
/// it costs, and only then the small print. What is pinned is only
/// what the user acts on, so the resting view ends on a whole plan card instead of
/// slicing one in half.
///
/// App Review 3.1.2 checklist, all on this screen: subscription name, length, price
/// per period, an explicit auto-renew sentence, Restore, Terms of Use, Privacy Policy,
/// and a non-punitive way out ("Continue with Free").
struct PaywallView: View {
    var reason: PremiumFeature = .general

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.pageLayout) private var pageLayout
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var viewModel: PaywallViewModel?

    var body: some View {
        ZStack {
            DesignTokens.Colors.background.ignoresSafeArea()
            if pageLayout == .spread && !dynamicTypeSize.isAccessibilitySize {
                // Open like a book: what you get on the left page, the band as tall as
                // the page; what it costs and the way to pay on the right.
                HStack(alignment: .top, spacing: PageLayout.gutter) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                            header(tall: true)
                            benefits
                        }
                        .padding(.leading, DesignTokens.Spacing.s)
                        .padding(.vertical, DesignTokens.Spacing.s)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxWidth: .infinity)
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                                planSection
                                smallPrint
                                legalLinks
                            }
                            .padding(.horizontal, DesignTokens.Spacing.s)
                            .padding(.vertical, DesignTokens.Spacing.s)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        footer
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                single
            }
        }
        .toolbar { closeButton }
        .navigationTitle(String(localized: "Premium", comment: "Paywall navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                viewModel = PaywallViewModel(subscriptionService: container.subscriptionService)
            }
            await viewModel?.loadPlans()
        }
        .onChange(of: isPurchased) { _, purchased in
            // Nothing left to sell — get out of the user's way.
            if purchased { dismiss() }
        }
    }

    private var single: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                    header()
                    benefits
                    planSection
                    smallPrint
                    legalLinks
                }
                .padding(.horizontal, DesignTokens.Spacing.s)
                .padding(.top, DesignTokens.Spacing.s)
                .padding(.bottom, DesignTokens.Spacing.m)
            }
            .scrollBounceBehavior(.basedOnSize)
            footer
        }
    }

    private var isPurchased: Bool {
        if case .success(.premium) = viewModel?.actionState { return true }
        return false
    }

    // MARK: - Header

    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .accessibilityLabel(String(localized: "Close", comment: "Close paywall"))
        }
    }

    /// `tall`: the cat stands on its own above the title rather than beside it.
    private func header(tall: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            if tall {
                CatMascot(mood: .proud)
                    .frame(width: 150)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, DesignTokens.Spacing.xs)
                Text(String(localized: "Every morning, yours", comment: "Paywall title"))
                    .font(.mcTitle1)
                    .foregroundStyle(DesignTokens.Colors.onHero)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .bottom) {
                    Text(String(localized: "Every morning, yours", comment: "Paywall title"))
                        .font(.mcTitle1)
                        .foregroundStyle(DesignTokens.Colors.onHero)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CatMascot(mood: .proud)
                        .frame(width: 112)
                        .padding(.bottom, -6)
                }
            }
            Text(reason.prompt ?? String(localized: "Unlock every mission, every alarm and your full sleep history.", comment: "Paywall subtitle"))
                .font(.mcCallout)
                .foregroundStyle(DesignTokens.Colors.onHeroSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.Colors.heroBand, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl, style: .continuous))
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            benefit(String(localized: "Unlimited alarms and all 8 missions", comment: "Paywall benefit: alarms and missions"))
            benefit(String(localized: "Sleep history and your 30-day trend", comment: "Paywall benefit: sleep history"))
            benefit(String(localized: "Streak and Sleep widgets", comment: "Paywall benefit: widgets"))
            benefit(String(localized: "Four more app icons", comment: "Paywall benefit: alternate app icons"))
            benefit(String(localized: "Unlimited Cat Naps puzzles, every past day, and hints", comment: "Paywall benefit: Cat Naps unlimited, archive and hints"))
            benefit(String(localized: "Wake checks so you don't drift back to sleep", comment: "Paywall benefit: wake checks"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
            PawPrintShape()
                .fill(DesignTokens.Colors.streakFlame)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(text)
                .font(.mcBody)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Plans

    @ViewBuilder
    private var planSection: some View {
        if let viewModel, !viewModel.plans.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.plans.enumerated()), id: \.element.id) { index, plan in
                    if index > 0 { Divider().padding(.leading, DesignTokens.Spacing.s) }
                    planCard(plan, isSelected: viewModel.selectedPlan?.id == plan.id)
                }
            }
            .background(DesignTokens.Colors.surfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
        } else if viewModel?.isLoadingPlans ?? true {
            HStack(spacing: DesignTokens.Spacing.xs) {
                SwiftUI.ProgressView()
                Text(String(localized: "Loading plans…", comment: "Paywall loading plans"))
                    .font(.mcCallout)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            unavailableState
        }
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(String(localized: "Plans couldn't be loaded", comment: "Paywall plans unavailable title"))
                .font(.mcHeadline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Text(viewModel?.planLoadError?.localizedDescription
                 ?? String(localized: "Check your connection and try again.", comment: "Paywall plans unavailable message"))
                .font(.mcFootnote)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "Try Again", comment: "Retry button")) {
                Task { await viewModel?.loadPlans() }
            }
            .font(.mcSubhead)
            .foregroundStyle(DesignTokens.Colors.accent)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mcCard()
    }

    private func planCard(_ plan: SubscriptionPlan, isSelected: Bool) -> some View {
        Button {
            Haptics.selection()
            viewModel?.select(plan)
        } label: {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.s) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text(plan.kind.displayName)
                            .font(.mcHeadline)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                        if let days = plan.introTrialDays { trialBadge(days: days) }
                    }
                    Text(planDetail(plan))
                        .font(.mcFootnote)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? DesignTokens.Colors.accent : DesignTokens.Colors.textTertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// The trial, said in the plan's own line rather than in a badge.
    private func trialBadge(days: Int) -> some View {
        Text(String(localized: "\(days) DAYS FREE", comment: "Free trial badge"))
            .font(.mcFootnoteSemibold)
            .foregroundStyle(DesignTokens.Colors.accent)
    }

    private func planDetail(_ plan: SubscriptionPlan) -> String {
        switch plan.kind {
        case .annual:
            if let perMonth = plan.localizedMonthlyEquivalent {
                return String(localized: "\(plan.localizedPrice) per year · \(perMonth) a month", comment: "Annual plan detail")
            }
            return String(localized: "\(plan.localizedPrice) per year", comment: "Annual plan detail without monthly")
        case .monthly:
            return String(localized: "\(plan.localizedPrice) per month · cancel any time", comment: "Monthly plan detail")
        }
    }

    // MARK: - Small print

    /// Scrolls with the page rather than sitting under the button. Two stacked
    /// paragraphs of centred legalese made the pinned footer tall enough to leave a
    /// viewport that cut the second plan card in half — this is the same text, in the
    /// reading order it belongs to, ranged left like everything else on the screen.
    private var smallPrint: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(String(
                localized: "Free includes \(FreeTier.enabledAlarmLimit) alarms with the Math and Shake missions.",
                comment: "What the free tier includes, shown next to the way out of the paywall"
            ))

            if let terms = viewModel?.renewalTerms {
                Text(terms)
            }
        }
        .font(.mcCaption)
        .foregroundStyle(legalTextColor)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The small print was given its own colour because `textSecondary` measured
    /// 4.0:1 on the light ground, just under the 4.5:1 floor. That token has since
    /// been raised to 5.0:1, so this is now the standard one.
    private var legalTextColor: Color { DesignTokens.Colors.textSecondary }

    private var legalLinks: some View {
        HStack(spacing: DesignTokens.Spacing.m) {
            Button(String(localized: "Restore", comment: "Restore purchases button")) {
                Task { await viewModel?.restore() }
            }
            .disabled(viewModel?.isBusy ?? false)
            Button(String(localized: "Terms", comment: "Terms of use link")) { openURL(LegalLinks.terms) }
            Button(String(localized: "Privacy", comment: "Privacy policy link")) { openURL(LegalLinks.privacy) }
        }
        .font(.mcFootnote)
        .fontWeight(.medium)
        .foregroundStyle(DesignTokens.Colors.accent)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    // MARK: - Footer

    /// Only the two things the user acts on. Everything else reads above.
    private var footer: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            statusLine

            Button {
                Task { await viewModel?.purchase() }
            } label: {
                Text(viewModel?.callToAction ?? String(localized: "Continue", comment: "Paywall CTA fallback"))
                    .mcPrimaryButton()
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(isCTADisabled)
            .opacity(isCTADisabled ? 0.5 : 1)

            Button(String(localized: "Continue with Free", comment: "Dismiss paywall without buying")) {
                dismiss()
            }
            .font(.mcCallout)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .frame(minHeight: 44)
        }
        .padding(.horizontal, DesignTokens.Spacing.s)
        .padding(.top, DesignTokens.Spacing.xs)
        .background(alignment: .top) {
            // Names the edge the scroll ends at, so content passing under it reads as
            // continuing rather than clipped.
            DesignTokens.Colors.background
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DesignTokens.Colors.separator)
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var isCTADisabled: Bool {
        (viewModel?.isBusy ?? false) || viewModel?.selectedPlan == nil
    }

    @ViewBuilder
    private var statusLine: some View {
        switch viewModel?.actionState ?? .idle {
        case .idle, .success:
            EmptyView()
        case .loading:
            HStack(spacing: DesignTokens.Spacing.xs) {
                SwiftUI.ProgressView().tint(DesignTokens.Colors.accent)
                Text(String(localized: "Talking to the App Store…", comment: "Subscription loading state"))
            }
            .font(.mcFootnote)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
        case .cancelled:
            Label(String(localized: "Purchase cancelled.", comment: "Subscription cancelled state"), systemImage: "xmark.circle")
                .font(.mcFootnote)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        case .error(let error):
            Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                .font(.mcFootnote)
                .foregroundStyle(DesignTokens.Colors.destructive)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Presentation helper

extension View {
    /// Presents the paywall over the current screen.
    ///
    /// Always presented locally rather than from the app root: editors and the ring
    /// screen are full-screen covers, and a root-level sheet would never appear above them.
    func paywall(for feature: Binding<PremiumFeature?>) -> some View {
        sheet(item: feature) { reason in
            NavigationStack { PaywallView(reason: reason) }.readsPageLayout().appAppearance()
        }
    }
}

#Preview("Free") {
    NavigationStack { PaywallView(reason: .unlimitedAlarms) }
        .environment(AppContainer.preview(tier: .free))
}
