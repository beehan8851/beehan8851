import Foundation
import os

final class UserDefaultsStorageService: StorageServiceProtocol {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - App Group

    /// Key prefix shared by every value this service persists for the app.
    static let keyPrefix = "com.morningcompanion."
    private static let migrationMarkerKey = "com.morningcompanion.storage.migratedToAppGroup.v1"

    /// Storage backed by the App Group suite so the widget extension can read the
    /// alarm list (audit §3 P1). On first use it copies every `com.morningcompanion.*`
    /// value from `UserDefaults.standard` when the group suite has none yet.
    static func appGroup(
        suiteName: String = ReArmRegistry.suiteName,
        legacy: UserDefaults = .standard
    ) -> UserDefaultsStorageService {
        guard let group = UserDefaults(suiteName: suiteName) else {
            Log.storage.error("App Group suite \(suiteName, privacy: .public) unavailable — falling back to standard defaults")
            return UserDefaultsStorageService(defaults: legacy)
        }
        migrateIfNeeded(from: legacy, to: group)
        return UserDefaultsStorageService(defaults: group)
    }

    /// One-time copy of prefixed keys. Pure with respect to the two suites passed in
    /// so it can be exercised with throwaway suites in tests.
    @discardableResult
    static func migrateIfNeeded(from legacy: UserDefaults, to group: UserDefaults) -> Int {
        guard !group.bool(forKey: migrationMarkerKey) else { return 0 }
        let groupHasData = group.dictionaryRepresentation().keys.contains { $0.hasPrefix(keyPrefix) && $0 != migrationMarkerKey }
        var copied = 0
        if !groupHasData {
            for (key, value) in legacy.dictionaryRepresentation() where key.hasPrefix(keyPrefix) {
                group.set(value, forKey: key)
                copied += 1
            }
        }
        group.set(true, forKey: migrationMarkerKey)
        if copied > 0 {
            Log.storage.info("Migrated \(copied, privacy: .public) value(s) from standard defaults to the App Group")
        }
        return copied
    }

    // MARK: - StorageServiceProtocol

    func load<T: Codable>(key: String) throws -> T {
        guard let data = defaults.data(forKey: key) else {
            throw StorageError.notFound(key: key)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw StorageError.decodingFailed(underlying: error)
        }
    }

    func save<T: Codable>(_ value: T, key: String) throws {
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw StorageError.encodingFailed(underlying: error)
        }
        defaults.set(data, forKey: key)
    }

    func remove(key: String) {
        defaults.removeObject(forKey: key)
    }
}
