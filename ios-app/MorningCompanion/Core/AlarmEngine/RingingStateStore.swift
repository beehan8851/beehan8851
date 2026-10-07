import Foundation

/// Persists "an alarm is ringing and its mission is not done" across a
/// force-quit so the ring screen can be presented immediately on relaunch
/// instead of waiting for the 2-minute persistence re-arm (audit §3 P1).
nonisolated struct RingingStateStore: Sendable {

    struct State: Codable, Sendable, Equatable {
        let alarmID: UUID
        let startedAt: Date
        /// The AlarmKit id that was alerting when the state was recorded
        /// (the alarm's own id or a re-arm id).
        let alertingID: UUID?
    }

    /// Ringing state older than this is ignored on launch — the user has most
    /// likely dealt with the alarm through the system UI.
    static let maxAge: TimeInterval = 15 * 60
    private static let storageKey = "com.morningcompanion.ringing.state.v1"

    /// UserDefaults is documented thread-safe; the struct stays Sendable so actors can hold it.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: ReArmRegistry.suiteName) ?? .standard
    }

    func save(alarmID: UUID, alertingID: UUID?, startedAt: Date = .now) {
        let state = State(alarmID: alarmID, startedAt: startedAt, alertingID: alertingID)
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func load() -> State? {
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(State.self, from: data)
    }

    /// Returns the persisted state only if it is fresh enough to act on.
    func loadIfFresh(now: Date = .now) -> State? {
        guard let state = load() else { return nil }
        return Self.isFresh(state, now: now) ? state : nil
    }

    func clear() { defaults.removeObject(forKey: Self.storageKey) }

    static func isFresh(_ state: State, now: Date = .now) -> Bool {
        let age = now.timeIntervalSince(state.startedAt)
        return age >= 0 && age < maxAge
    }
}
