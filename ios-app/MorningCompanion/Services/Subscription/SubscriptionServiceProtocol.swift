import Foundation

// MARK: - Tier

enum SubscriptionTier: Sendable, Equatable {
    case free
    case premium

    var isPremium: Bool { self == .premium }
}

// MARK: - Plans

/// The two products in the App Store Connect "Premium" subscription group.
enum SubscriptionPlanKind: String, CaseIterable, Identifiable, Sendable {
    case annual
    case monthly

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .monthly: return "dev.numonov.dawnwick.premium.monthly"
        case .annual:  return "dev.numonov.dawnwick.premium.annual"
        }
    }

    var displayName: String {
        switch self {
        case .monthly: return String(localized: "Monthly", comment: "Monthly subscription plan")
        case .annual:  return String(localized: "Annual", comment: "Annual subscription plan")
        }
    }
}

/// A store-backed plan, ready to render.
///
/// Every price string comes from the store, never from source (App Review 3.1.2:
/// the paywall must show the real price, duration and renewal terms).
struct SubscriptionPlan: Identifiable, Sendable, Equatable {
    let kind: SubscriptionPlanKind
    let productID: String
    /// Recurring price in the user's currency, e.g. "$39.99".
    let localizedPrice: String
    /// Same price divided over a month, e.g. "$3.33" — nil when it adds nothing (monthly).
    let localizedMonthlyEquivalent: String?
    /// Length of the free trial *this account is eligible for*, in days. Nil when
    /// there is no intro offer or the account already used it.
    let introTrialDays: Int?

    var id: String { productID }
    var hasFreeTrial: Bool { introTrialDays != nil }
}

// MARK: - Results

enum SubscriptionActionResult: Sendable, Equatable {
    case success(SubscriptionTier)
    case cancelled
}

enum SubscriptionError: LocalizedError {
    case notConfigured
    case planUnavailable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "The store isn't available right now. Try again in a moment.", comment: "Subscription service not configured")
        case .planUnavailable:
            return String(localized: "That plan couldn't be loaded from the App Store. Pull to retry.", comment: "Subscription plan missing")
        }
    }
}

// MARK: - Protocol

/// Everything the app knows about the user's entitlement.
///
/// Kept deliberately store-agnostic: RevenueCat is an implementation detail behind
/// `RevenueCatSubscriptionService`, so moving to plain StoreKit 2 later touches one file.
protocol SubscriptionServiceProtocol: AnyObject {
    /// Entitlement in force right now. Seeded from the App Group cache before the
    /// first network round-trip, so it is never `.free` just because we are offline.
    var currentTier: SubscriptionTier { get }
    /// Plans to show on the paywall; empty until `loadPlans()` succeeds.
    var plans: [SubscriptionPlan] { get }
    var isLoadingPlans: Bool { get }
    /// Non-nil when the last `loadPlans()` failed — the paywall shows a retry.
    var planLoadError: (any Error)? { get }
    /// Expiry of the active entitlement, for the Settings row. Nil when free or unknown.
    var expirationDate: Date? { get }

    /// Configures the store SDK and starts observing entitlement changes. Idempotent.
    func start()
    func loadPlans() async
    func purchase(_ plan: SubscriptionPlan) async throws -> SubscriptionActionResult
    func restorePurchases() async throws -> SubscriptionActionResult
    /// Opens the system "Manage Subscription" sheet.
    func showManageSubscriptions() async throws
}

// MARK: - Stub

/// Deterministic stand-in for previews, unit tests and any build without a store.
/// Purchase succeeds locally so the success path can be exercised without StoreKit.
@Observable
final class StubSubscriptionService: SubscriptionServiceProtocol {
    private(set) var currentTier: SubscriptionTier
    private(set) var plans: [SubscriptionPlan]
    private(set) var isLoadingPlans = false
    private(set) var planLoadError: (any Error)?
    private(set) var expirationDate: Date?

    init(currentTier: SubscriptionTier = .free, plans: [SubscriptionPlan] = SubscriptionPlan.previewPlans) {
        self.currentTier = currentTier
        self.plans = plans
    }

    func start() {}

    func loadPlans() async {}

    func purchase(_ plan: SubscriptionPlan) async throws -> SubscriptionActionResult {
        currentTier = .premium
        expirationDate = Calendar.current.date(byAdding: plan.kind == .annual ? .year : .month, value: 1, to: .now)
        return .success(.premium)
    }

    func restorePurchases() async throws -> SubscriptionActionResult {
        .success(currentTier)
    }

    func showManageSubscriptions() async throws {}
}

extension SubscriptionPlan {
    /// Placeholder prices for previews only. Never shown in a shipping build —
    /// `RevenueCatSubscriptionService` renders nothing until the store answers.
    static let previewPlans: [SubscriptionPlan] = [
        SubscriptionPlan(
            kind: .annual,
            productID: SubscriptionPlanKind.annual.productID,
            localizedPrice: "$39.99",
            localizedMonthlyEquivalent: "$3.33",
            introTrialDays: 7
        ),
        SubscriptionPlan(
            kind: .monthly,
            productID: SubscriptionPlanKind.monthly.productID,
            localizedPrice: "$4.99",
            localizedMonthlyEquivalent: nil,
            introTrialDays: nil
        )
    ]
}
