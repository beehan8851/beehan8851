import Foundation

/// Typed storage errors that allow callers to distinguish failure modes.
enum StorageError: LocalizedError {
    case notFound(key: String)
    case decodingFailed(underlying: Error)
    case encodingFailed(underlying: Error)
    case writeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notFound(let key):         return "No data found for key '\(key)'"
        case .decodingFailed(let e):     return "Decoding failed: \(e.localizedDescription)"
        case .encodingFailed(let e):     return "Encoding failed: \(e.localizedDescription)"
        case .writeFailed(let e):        return "Write failed: \(e.localizedDescription)"
        }
    }
}

protocol StorageServiceProtocol: AnyObject {
    /// Loads and decodes a value. Throws StorageError.notFound when the key is absent
    /// (first-launch normal path), StorageError.decodingFailed for corrupted data.
    func load<T: Codable>(key: String) throws -> T
    func save<T: Codable>(_ value: T, key: String) throws
    func remove(key: String)
}
