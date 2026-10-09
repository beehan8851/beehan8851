import Foundation

/// Last entitlement state confirmed against the store, in the App Group.
///
/// Written by `RevenueCatSubscriptionService`; read by anything that needs an answer
/// *synchronously*, before or without a network round-trip:
/// - `AlarmManager` (an actor, off the main actor) enforcing the free alarm limit,
/// - the widget extension, which has no store SDK at all,
/// - the app itself on a cold launch in airplane mode.
///
/// It is a cache, not the source of truth. The store always wins once it answers.
nonisolated struct SubscriptionEntitlementSnapshot: Codable, Sendable, Equatable {
    var isPremium: Bool
    /// Entitlement expiry as reported by the store; nil for lifetime or unknown.
    var expiresAt: Date?
    /// When this state was last confirmed against the store.
    var verifiedAt: Date

    init(isPremium: Bool, expiresAt: Date? = nil, verifiedAt: Date = .now) {
        self.isPremium = isPremium
        self.expiresAt = expiresAt
        self.verifiedAt = verifiedAt
    }
}

nonisolated struct SubscriptionEntitlementCache: Sendable {
    /// How long a premium entitlement survives without being re-confirmed.
    ///
    /// Covers a few days offline and Apple's own billing-retry window: someone who
    /// paid must never be locked out of their alarms because a server was unreachable.
    static let graceInterval: TimeInterval = 3 * 24 * 60 * 60

    /// UserDefaults is documented thread-safe; the struct stays Sendable so the
    /// `AlarmManager` actor and the widget process can both hold one.
    nonisolated(unsafe) private let defaults: UserDefaults?
    private let storageKey = "subscription.entitlement.snapshot.v1"

    init(appGroupIdentifier: String = WidgetSharedDataStore.appGroupIdentifier) {
        self.defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    func snapshot() -> SubscriptionEntitlementSnapshot? {
        guard let data = defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(SubscriptionEntitlementSnapshot.self, from: data)
    }

    func save(_ snapshot: SubscriptionEntitlementSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: storageKey)
    }

    /// The entitlement to act on right now.
    ///
    /// Premium holds while *both* are true: the state was confirmed within
    /// `graceInterval`, and any known expiry is not more than `graceInterval` past.
    /// Anything else is free — a stale cache must not grant premium forever.
    func isPremium(now: Date = .now) -> Bool {
        guard let current = snapshot(), current.isPremium else { return false }
        if let expiresAt = current.expiresAt,
           now > expiresAt.addingTimeInterval(Self.graceInterval) { return false }
        return now <= current.verifiedAt.addingTimeInterval(Self.graceInterval)
    }

    func clear() {
        defaults?.removeObject(forKey: storageKey)
    }
}
