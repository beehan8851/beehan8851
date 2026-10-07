import Foundation

/// Ephemeral storage backed by a dictionary.
/// Used in SwiftUI previews and unit tests — never persists to disk.
final class InMemoryStorageService: StorageServiceProtocol {
    private var store: [String: Data] = [:]
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {}

    func load<T: Codable>(key: String) throws -> T {
        guard let data = store[key] else {
            throw StorageError.notFound(key: key)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw StorageError.decodingFailed(underlying: error)
        }
    }

    func save<T: Codable>(_ value: T, key: String) throws {
        do {
            store[key] = try encoder.encode(value)
        } catch {
            throw StorageError.encodingFailed(underlying: error)
        }
    }

    func remove(key: String) {
        store.removeValue(forKey: key)
    }

    /// Test helper: injects raw bytes for a key — a payload written by a schema
    /// older than anything this build can still encode, for instance.
    func injectRaw(_ data: Data, key: String) {
        store[key] = data
    }

    /// Test helper: injects raw bytes for a key to simulate corrupted data.
    func injectCorruptData(key: String, bytes: [UInt8] = [0xFF, 0xFE, 0x00]) {
        store[key] = Data(bytes)
    }
}
