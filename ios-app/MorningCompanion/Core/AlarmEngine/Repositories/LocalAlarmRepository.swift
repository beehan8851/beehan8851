import Foundation
import os

/// Persists alarms as a versioned JSON envelope in UserDefaults.
/// All write operations update the envelope at currentSchemaVersion.
/// Corruption is surfaced as AlarmRepositoryError — never silently treated as empty.
final class LocalAlarmRepository: AlarmRepositoryProtocol {
    private let storage: any StorageServiceProtocol
    private let storageKey = "com.morningcompanion.alarms.v1"
    private var continuation: AsyncStream<[Alarm]>.Continuation?

    let alarmsStream: AsyncStream<[Alarm]>

    init(storage: any StorageServiceProtocol) {
        self.storage = storage
        var cont: AsyncStream<[Alarm]>.Continuation?
        alarmsStream = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func fetchAll() async throws -> [Alarm] {
        do {
            let envelope: AlarmEnvelope = try storage.load(key: storageKey)
            let alarms = try envelope.migrate()
            if envelope.needsUpgrade {
                // Write the migrated list back once, so the old shape stops being read
                // on every launch and a later failure cannot resurrect it. A failed
                // rewrite is not worth failing the read over — the next save retries.
                do {
                    try persist(alarms)
                    Log.storage.info("Upgraded the alarm store from schema \(envelope.schemaVersion, privacy: .public) to \(AlarmEnvelope.currentSchemaVersion, privacy: .public)")
                } catch {
                    Log.storage.error("Alarm store upgrade could not be written: \(error.localizedDescription, privacy: .public)")
                }
            }
            return alarms
        } catch StorageError.notFound {
            return []   // Valid first-launch path
        } catch let error as StorageError {
            throw AlarmRepositoryError.storageFailure(error)
        } catch let error as AlarmRepositoryError {
            throw error
        } catch {
            throw AlarmRepositoryError.dataCorrupted(reason: error.localizedDescription)
        }
    }

    func save(_ alarm: Alarm) async throws {
        var alarms = try await fetchAll()
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
        try persist(alarms)
        continuation?.yield(alarms)
    }

    func delete(id: UUID) async throws {
        var alarms = try await fetchAll()
        alarms.removeAll { $0.id == id }
        try persist(alarms)
        continuation?.yield(alarms)
    }

    // MARK: - Private

    private func persist(_ alarms: [Alarm]) throws {
        let envelope = AlarmEnvelope(alarms: alarms)
        do {
            try storage.save(envelope, key: storageKey)
        } catch let error as StorageError {
            throw AlarmRepositoryError.storageFailure(error)
        }
    }
}
