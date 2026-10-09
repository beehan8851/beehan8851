import Foundation

enum AlarmRepositoryError: LocalizedError {
    case storageFailure(StorageError)
    case dataCorrupted(reason: String)
    case migrationRequired(fromVersion: Int, toVersion: Int)

    var errorDescription: String? {
        switch self {
        case .storageFailure(let e):              return e.localizedDescription
        case .dataCorrupted(let r):               return "Alarm data is corrupted: \(r)"
        case .migrationRequired(let from, let to): return "Schema migration required: v\(from) → v\(to)"
        }
    }
}

protocol AlarmRepositoryProtocol {
    /// Returns persisted alarms.
    /// Returns [] on first launch (key not found).
    /// Throws AlarmRepositoryError for corrupted data or migration failure —
    /// never silently converts corruption into an empty list.
    func fetchAll() async throws -> [Alarm]
    func save(_ alarm: Alarm) async throws
    func delete(id: UUID) async throws
    /// Emits the full alarm list whenever it changes.
    var alarmsStream: AsyncStream<[Alarm]> { get }
}
