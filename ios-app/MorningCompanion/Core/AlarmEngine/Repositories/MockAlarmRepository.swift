import Foundation

/// In-memory alarm repository for SwiftUI previews and unit tests.
/// Exposes injectable error hooks for negative-path testing.
final class MockAlarmRepository: AlarmRepositoryProtocol {
    var alarms: [Alarm]
    /// When set, fetchAll() throws this error instead of returning alarms.
    var fetchError: (any Error)?
    /// When set, save() and delete() throw this error.
    var writeError: (any Error)?

    private var continuation: AsyncStream<[Alarm]>.Continuation?
    let alarmsStream: AsyncStream<[Alarm]>

    init(alarms: [Alarm] = Alarm.samples, fetchError: (any Error)? = nil) {
        self.alarms = alarms
        self.fetchError = fetchError
        var cont: AsyncStream<[Alarm]>.Continuation?
        alarmsStream = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func fetchAll() async throws -> [Alarm] {
        if let error = fetchError { throw error }
        return alarms
    }

    func save(_ alarm: Alarm) async throws {
        if let error = writeError { throw error }
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
        continuation?.yield(alarms)
    }

    func delete(id: UUID) async throws {
        if let error = writeError { throw error }
        alarms.removeAll { $0.id == id }
        continuation?.yield(alarms)
    }
}
