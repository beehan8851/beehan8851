import Foundation

/// Persistent map of every transient AlarmKit/notification id the app creates
/// (snooze, escape/persistence re-arm, wake-check auto-fail, test alarm) back to
/// the *original* alarm it belongs to.
///
/// Stored in the App Group suite so the same registry is visible to the app
/// after a force-quit and to the widget/intent extension processes. All reads
/// and writes go straight to `UserDefaults`, so any number of `ReArmRegistry`
/// values observe the same state.
///
/// Why it exists (audit §3 P1 "Ghost alarms"): disabling, editing, deleting or
/// completing an alarm must cancel *every* transient id that was created for it,
/// otherwise a snoozed copy keeps ringing under a UUID nobody remembers.
nonisolated struct ReArmRegistry: Sendable {

    // MARK: - Types

    enum Kind: String, Codable, Sendable {
        case snooze
        case reArm
        case wakeCheck
        case test
    }

    struct Entry: Codable, Sendable, Equatable {
        let originalID: UUID
        let fireDate: Date
        let kind: Kind
    }

    // MARK: - Storage

    static let suiteName = "group.dev.numonov.dawnwick"
    private static let storageKey = "com.morningcompanion.rearm.registry.v1"
    /// Entries older than this past their fire date are forgotten during `prune()`.
    static let staleGrace: TimeInterval = 30 * 60

    /// UserDefaults is documented thread-safe; the struct stays Sendable so actors can hold it.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.suiteName) ?? .standard
    }

    // MARK: - Reads

    /// All entries keyed by re-arm id.
    var entries: [UUID: Entry] { load() }

    /// Every transient id currently registered (any kind, any original).
    var allReArmIDs: Set<UUID> { Set(load().keys) }

    func entry(for reArmID: UUID) -> Entry? { load()[reArmID] }

    /// The original alarm an id was created for, or nil if it isn't a re-arm.
    func originalID(for reArmID: UUID) -> UUID? { load()[reArmID]?.originalID }

    /// All transient ids created for `originalID`.
    func reArmIDs(for originalID: UUID) -> [UUID] {
        load().filter { $0.value.originalID == originalID }.map(\.key)
    }

    func reArmIDs(for originalID: UUID, kind: Kind) -> [UUID] {
        load().filter { $0.value.originalID == originalID && $0.value.kind == kind }.map(\.key)
    }

    /// True when `originalID` was registered by the "Test alarm" flow (not in the repository).
    func isTestOriginal(_ originalID: UUID) -> Bool {
        load().values.contains { $0.originalID == originalID && $0.kind == .test }
    }

    // MARK: - Writes

    func register(reArmID: UUID, originalID: UUID, fireDate: Date, kind: Kind) {
        var all = load()
        all[reArmID] = Entry(originalID: originalID, fireDate: fireDate, kind: kind)
        store(all)
    }

    func remove(reArmID: UUID) {
        var all = load()
        guard all.removeValue(forKey: reArmID) != nil else { return }
        store(all)
    }

    /// Forgets every id that belongs to `originalID` and returns them so the
    /// caller can cancel them in the engine.
    @discardableResult
    func removeAll(for originalID: UUID) -> [UUID] {
        var all = load()
        let ids = all.filter { $0.value.originalID == originalID }.map(\.key)
        guard !ids.isEmpty else { return [] }
        for id in ids { all.removeValue(forKey: id) }
        store(all)
        return ids
    }

    func removeAll() { defaults.removeObject(forKey: Self.storageKey) }

    /// Drops entries whose fire date is more than `staleGrace` in the past.
    /// Returns the pruned ids so the caller can make sure the engine forgot them too.
    @discardableResult
    func prune(now: Date = .now) -> [UUID] {
        var all = load()
        let stale = all.filter { now.timeIntervalSince($0.value.fireDate) > Self.staleGrace }.map(\.key)
        guard !stale.isEmpty else { return [] }
        for id in stale { all.removeValue(forKey: id) }
        store(all)
        return stale
    }

    // MARK: - Pure helpers (unit-testable)

    /// Given the registry contents and the set of alarms that still exist and are
    /// enabled, returns the transient ids that must be cancelled because their
    /// original alarm is gone or disabled. Test-alarm entries are exempt (their
    /// original never lives in the repository) until they go stale.
    static func orphanedReArmIDs(
        entries: [UUID: Entry],
        activeOriginalIDs: Set<UUID>,
        now: Date = .now
    ) -> [UUID] {
        entries.compactMap { id, entry in
            if entry.kind == .test {
                return now.timeIntervalSince(entry.fireDate) > staleGrace ? id : nil
            }
            return activeOriginalIDs.contains(entry.originalID) ? nil : id
        }
    }

    // MARK: - Private

    private func load() -> [UUID: Entry] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let raw = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }

    private func store(_ entries: [UUID: Entry]) {
        let raw = Dictionary(uniqueKeysWithValues: entries.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
