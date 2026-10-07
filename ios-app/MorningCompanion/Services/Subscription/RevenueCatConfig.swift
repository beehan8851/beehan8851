import Foundation

/// Store and legal configuration for the subscription flow.
///
/// The RevenueCat key here is the **public SDK key** (`appl_…`) from
/// app.revenuecat.com → Project settings → API keys → Apple. It identifies the app
/// and authorises nothing on its own, so shipping it inside the binary is expected —
/// it is not a secret. The secret half (the In-App Purchase .p8) lives in RevenueCat.
enum RevenueCatConfig {

    /// Replace with the project's public SDK key. While it is the placeholder the app
    /// runs in free mode and the paywall shows "store unavailable" instead of crashing,
    /// so a mis-configured build is obvious in QA but never fatal to a user's alarms.
    static let apiKey = "appl_REPLACE_WITH_REVENUECAT_PUBLIC_SDK_KEY"

    /// Entitlement identifier configured in RevenueCat.
    static let entitlementID = "premium"

    /// Offering identifier; `$rc_monthly` and `$rc_annual` packages live inside it.
    static let offeringID = "default"

    static var isConfigured: Bool {
        apiKey.hasPrefix("appl_") && !apiKey.contains("REPLACE_WITH")
    }
}

/// Links the paywall and Settings are required to expose (App Review 3.1.2 and 5.1.1).
enum LegalLinks {
    /// Apple's standard EULA — valid Terms of Use for an app that does not ship its own.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// Hosted copy of `web/privacy.html` (docs/21 §1). Must match the Privacy Policy
    /// URL entered in App Store Connect.
    static let privacy = URL(string: "https://numonov.github.io/dawnwick-site/privacy.html")!

    /// Hosted copy of `web/support.html`. Must match the Support URL in App Store Connect.
    static let support = URL(string: "https://numonov.github.io/dawnwick-site/support.html")!

    /// App Store review deep link. Filled in once the app record has an Apple ID.
    static let appStoreID = "REPLACE_WITH_APP_STORE_ID"

    static var reviewURL: URL? {
        guard !appStoreID.contains("REPLACE_WITH") else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
}
