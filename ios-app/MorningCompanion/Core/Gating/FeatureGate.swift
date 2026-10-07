import Foundation

// MARK: - Free-tier limits

/// Everything the free tier is allowed, in one place (docs/15 §10).
///
/// `nonisolated`: `AlarmManager` is an actor and reads the limit off the main actor.
nonisolated enum FreeTier {
    /// Alarms a free account can keep *enabled* at once.
    ///
    /// Enforced on the enabled count, not the stored count, so a lapsed subscriber
    /// never loses alarms they configured — they simply cannot switch on more than
    /// two until they resubscribe.
    static let enabledAlarmLimit = 2
}

// MARK: - Premium features

/// The reason a paywall is being shown. Drives the paywall's one-line headline so
/// the user always knows which tap led there.
enum PremiumFeature: String, Identifiable, Equatable {
    case unlimitedAlarms
    case advancedMissions
    case sleepHistory
    case homeScreenWidget
    case appIcons
    case catNaps
    case catNapsUnlimited
    /// Opened from Settings rather than blocked by a feature.
    case general

    var id: String { rawValue }

    var prompt: String? {
        switch self {
        case .unlimitedAlarms:
            return String(localized: "Free covers two alarms. Premium has no limit.", comment: "Paywall reason: alarm limit")
        case .advancedMissions:
            return String(localized: "Steps, QR, Memory, Typing, Draw and Jump missions are Premium.", comment: "Paywall reason: missions")
        case .sleepHistory:
            return String(localized: "Last night is free. Your full history and trend are Premium.", comment: "Paywall reason: sleep history")
        case .homeScreenWidget:
            return String(localized: "The Streak and Sleep widgets are Premium.", comment: "Paywall reason: widget")
        case .appIcons:
            return String(localized: "The cat's other app icons are Premium.", comment: "Paywall reason: alternate app icons")
        case .catNaps:
            return String(localized: "Today's three Cat Naps are free. Unlimited puzzles, past days and hints are Premium.", comment: "Paywall reason: Cat Naps archive and hints")
        case .catNapsUnlimited:
            return String(localized: "Want another? Premium makes a new Cat Naps board every time, as many as you like.", comment: "Paywall reason: unlimited Cat Naps puzzles")
        case .general:
            return nil
        }
    }
}

extension MissionKind {
    /// Math and Shake stay free: a free account must still be able to build an alarm
    /// that actually wakes someone, and neither needs hardware or a setup step.
    var isPremium: Bool {
        switch self {
        case .math, .shake:
            return false
        case .steps, .qrCode, .memory, .typing, .draw, .jump, .catchCat:
            return true
        }
    }
}

// MARK: - Entitlement provider

/// Synchronous, `Sendable` read of the current entitlement.
///
/// `AlarmManager` is an actor and the widget has no store SDK, so neither can talk
/// to `SubscriptionServiceProtocol` (main-actor, async). Both read the App Group
/// cache through this instead.
nonisolated protocol EntitlementProviding: Sendable {
    var isPremium: Bool { get }
}

/// Production provider: the App Group snapshot written by the subscription service.
nonisolated struct CachedEntitlementProvider: EntitlementProviding {
    private let cache: SubscriptionEntitlementCache

    init(cache: SubscriptionEntitlementCache = SubscriptionEntitlementCache()) {
        self.cache = cache
    }

    var isPremium: Bool { cache.isPremium() }
}

/// Fixed answer, for tests and previews.
nonisolated struct FixedEntitlementProvider: EntitlementProviding {
    let isPremium: Bool

    init(_ isPremium: Bool) { self.isPremium = isPremium }
}
