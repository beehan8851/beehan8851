import Foundation
import Observation

enum PaywallActionState {
    case idle
    case loading
    case success(SubscriptionTier)
    case cancelled
    case error(any Error)
}

@Observable
final class PaywallViewModel {
    /// Product id of the highlighted plan. Annual is preselected — it carries the trial.
    var selectedPlanID: String?
    var actionState: PaywallActionState = .idle

    private let service: any SubscriptionServiceProtocol

    init(subscriptionService: any SubscriptionServiceProtocol) {
        self.service = subscriptionService
    }

    // MARK: - Store state (read straight through, so the view tracks the service)

    var plans: [SubscriptionPlan] { service.plans }
    var isLoadingPlans: Bool { service.isLoadingPlans }
    var planLoadError: (any Error)? { service.planLoadError }
    var isPremium: Bool { service.currentTier.isPremium }

    var selectedPlan: SubscriptionPlan? {
        plans.first { $0.id == selectedPlanID } ?? plans.first { $0.kind == .annual } ?? plans.first
    }

    var isBusy: Bool {
        if case .loading = actionState { return true }
        return false
    }

    // MARK: - Copy

    var callToAction: String {
        guard let plan = selectedPlan else {
            return String(localized: "Continue", comment: "Paywall CTA fallback")
        }
        guard let days = plan.introTrialDays else {
            return String(localized: "Subscribe", comment: "Paywall CTA without trial")
        }
        return String(localized: "Start \(days)-day free trial", comment: "Paywall CTA with trial")
    }

    /// App Review 3.1.2: the paywall must state the length, the price and that the
    /// subscription auto-renews, next to the buy button — not only in the store sheet.
    var renewalTerms: String? {
        guard let plan = selectedPlan else { return nil }
        let period = plan.kind == .annual
            ? String(localized: "year", comment: "Subscription period noun")
            : String(localized: "month", comment: "Subscription period noun")
        let cancelNote = String(
            localized: "Cancel any time in Settings › Apple Account › Subscriptions, at least 24 hours before the period ends.",
            comment: "Subscription cancellation instructions"
        )
        if let days = plan.introTrialDays {
            return String(
                localized: "The first \(days) days are free. After that Dawnwick Premium renews automatically at \(plan.localizedPrice) per \(period) until you cancel. \(cancelNote)",
                comment: "Auto-renew disclosure with trial"
            )
        }
        return String(
            localized: "Dawnwick Premium renews automatically at \(plan.localizedPrice) per \(period) until you cancel. \(cancelNote)",
            comment: "Auto-renew disclosure"
        )
    }

    // MARK: - Actions

    func loadPlans() async {
        await service.loadPlans()
        if selectedPlanID == nil { selectedPlanID = selectedPlan?.id }
    }

    func select(_ plan: SubscriptionPlan) {
        selectedPlanID = plan.id
        actionState = .idle
    }

    func purchase() async {
        guard let plan = selectedPlan else {
            actionState = .error(SubscriptionError.planUnavailable)
            return
        }
        actionState = .loading
        do {
            actionState = state(for: try await service.purchase(plan))
        } catch {
            actionState = .error(error)
        }
    }

    func restore() async {
        actionState = .loading
        do {
            actionState = state(for: try await service.restorePurchases())
        } catch {
            actionState = .error(error)
        }
    }

    func manageSubscription() async {
        do { try await service.showManageSubscriptions() }
        catch { actionState = .error(error) }
    }

    func resetStatus() { actionState = .idle }

    private func state(for result: SubscriptionActionResult) -> PaywallActionState {
        switch result {
        case .success(let tier): return .success(tier)
        case .cancelled:         return .cancelled
        }
    }
}
