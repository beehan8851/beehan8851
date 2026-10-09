import Foundation
import os
import Observation
import RevenueCat
import WidgetKit

/// The shipping `SubscriptionServiceProtocol`, backed by RevenueCat.
///
/// RevenueCat owns receipt validation and cross-device entitlement, so this class
/// only has to do three things well:
/// 1. keep `currentTier` truthful — seeded from the App Group cache so a cold launch
///    in airplane mode does not read as `.free`, then corrected by `customerInfoStream`;
/// 2. mirror every confirmed state into the App Group, for `AlarmManager` (an actor
///    that cannot await the SDK) and for the widget (which has no SDK at all);
/// 3. surface store-loaded prices, never hard-coded ones (App Review 3.1.2).
///
/// Nothing here ever *blocks* on the store: if RevenueCat is unreachable or the API
/// key is missing, the app runs on the cached entitlement and the paywall shows a retry.
@Observable
final class RevenueCatSubscriptionService: SubscriptionServiceProtocol {

    private(set) var currentTier: SubscriptionTier
    private(set) var plans: [SubscriptionPlan] = []
    private(set) var isLoadingPlans = false
    private(set) var planLoadError: (any Error)?
    private(set) var expirationDate: Date?

    /// Called after every confirmed entitlement change so the caller can refresh the
    /// widget snapshot. Set by `AppContainer`.
    var onTierChange: ((SubscriptionTier) -> Void)?

    @ObservationIgnored private let cache: SubscriptionEntitlementCache
    @ObservationIgnored private var packagesByProductID: [String: Package] = [:]
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var didStart = false

    init(cache: SubscriptionEntitlementCache = SubscriptionEntitlementCache()) {
        self.cache = cache
        self.currentTier = cache.isPremium() ? .premium : .free
        self.expirationDate = cache.snapshot()?.expiresAt
    }

    deinit { observationTask?.cancel() }

    // MARK: - Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true

        guard RevenueCatConfig.isConfigured else {
            Log.app.error("RevenueCat API key is not set — running on the cached entitlement only")
            return
        }

        #if DEBUG
        Purchases.logLevel = .warn
        #else
        Purchases.logLevel = .error
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)

        // `customerInfoStream` replays the cached CustomerInfo immediately and then
        // emits on renewal, expiry, refund, restore and family-sharing changes.
        observationTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                guard let self else { return }
                self.apply(info)
            }
        }

        Task { await loadPlans() }
    }

    // MARK: - Plans

    func loadPlans() async {
        guard RevenueCatConfig.isConfigured else {
            planLoadError = SubscriptionError.notConfigured
            return
        }
        isLoadingPlans = true
        planLoadError = nil
        defer { isLoadingPlans = false }

        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.all[RevenueCatConfig.offeringID] ?? offerings.current
            guard let offering else {
                planLoadError = SubscriptionError.planUnavailable
                return
            }

            let candidates: [(SubscriptionPlanKind, Package)] = [
                (.annual, offering.annual),
                (.monthly, offering.monthly)
            ].compactMap { kind, package in package.map { (kind, $0) } }

            guard !candidates.isEmpty else {
                planLoadError = SubscriptionError.planUnavailable
                return
            }

            // One eligibility round-trip for all products rather than one per plan.
            let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(
                productIdentifiers: candidates.map { $0.1.storeProduct.productIdentifier }
            )

            var loadedPackages: [String: Package] = [:]
            var loadedPlans: [SubscriptionPlan] = []
            for (kind, package) in candidates {
                let product = package.storeProduct
                loadedPackages[product.productIdentifier] = package
                loadedPlans.append(
                    SubscriptionPlan(
                        kind: kind,
                        productID: product.productIdentifier,
                        localizedPrice: product.localizedPriceString,
                        localizedMonthlyEquivalent: kind == .annual ? Self.monthlyEquivalent(of: product) : nil,
                        introTrialDays: Self.trialDays(
                            of: product,
                            eligibility: eligibility[product.productIdentifier]?.status
                        )
                    )
                )
            }
            packagesByProductID = loadedPackages
            plans = loadedPlans
        } catch {
            Log.app.error("RevenueCat offerings failed: \(String(describing: error), privacy: .public)")
            planLoadError = error
        }
    }

    /// The annual price expressed per month, formatted in the product's own currency.
    private static func monthlyEquivalent(of product: StoreProduct) -> String? {
        guard let perMonth = product.pricePerMonth, let formatter = product.priceFormatter else { return nil }
        return formatter.string(from: perMonth)
    }

    /// Free-trial length *this account can actually get*. An account that already used
    /// the intro offer must not be shown "7 days free" (App Review 3.1.2).
    private static func trialDays(of product: StoreProduct, eligibility: IntroEligibilityStatus?) -> Int? {
        guard let discount = product.introductoryDiscount, discount.paymentMode == .freeTrial else { return nil }
        // `.unknown` happens on a StoreKit hiccup; showing no trial is the safe error.
        guard eligibility == .eligible else { return nil }
        let period = discount.subscriptionPeriod
        let days: Int
        switch period.unit {
        case .day:   days = period.value
        case .week:  days = period.value * 7
        case .month: days = period.value * 30
        case .year:  days = period.value * 365
        @unknown default: return nil
        }
        return days * max(1, discount.numberOfPeriods)
    }

    // MARK: - Purchase

    func purchase(_ plan: SubscriptionPlan) async throws -> SubscriptionActionResult {
        guard RevenueCatConfig.isConfigured else { throw SubscriptionError.notConfigured }
        guard let package = packagesByProductID[plan.productID] else { throw SubscriptionError.planUnavailable }

        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled { return .cancelled }
        apply(result.customerInfo)
        return .success(currentTier)
    }

    func restorePurchases() async throws -> SubscriptionActionResult {
        guard RevenueCatConfig.isConfigured else { throw SubscriptionError.notConfigured }
        apply(try await Purchases.shared.restorePurchases())
        return .success(currentTier)
    }

    func showManageSubscriptions() async throws {
        guard RevenueCatConfig.isConfigured else { throw SubscriptionError.notConfigured }
        try await Purchases.shared.showManageSubscriptions()
    }

    // MARK: - Entitlement

    /// Single write point for the entitlement: local state, App Group cache and widget.
    private func apply(_ info: CustomerInfo) {
        let entitlement = info.entitlements[RevenueCatConfig.entitlementID]
        let isPremium = entitlement?.isActive == true
        let tier: SubscriptionTier = isPremium ? .premium : .free

        cache.save(
            SubscriptionEntitlementSnapshot(
                isPremium: isPremium,
                expiresAt: entitlement?.expirationDate,
                verifiedAt: .now
            )
        )
        expirationDate = isPremium ? entitlement?.expirationDate : nil

        guard tier != currentTier else { return }
        currentTier = tier
        Log.app.info("Entitlement changed → \(isPremium ? "premium" : "free", privacy: .public)")
        WidgetCenter.shared.reloadAllTimelines()
        onTierChange?(tier)
    }
}
