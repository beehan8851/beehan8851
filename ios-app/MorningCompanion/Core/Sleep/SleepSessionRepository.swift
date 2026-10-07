import Foundation

// MARK: - Protocol

protocol SleepSessionRepositoryProtocol: AnyObject {
    func saveActive(_ session: SleepSession) throws
    func loadActive() -> SleepSession?
    func clearActive()
    func saveCompleted(_ session: SleepSession) throws
    func loadCompleted() -> [SleepSession]
}

// MARK: - UserDefaults implementation

final class LocalSleepSessionRepository: SleepSessionRepositoryProtocol {
    private let storage: any StorageServiceProtocol

    private enum Keys {
        static let active    = "com.morningcompanion.sleep.activeSession"
        static let completed = "com.morningcompanion.sleep.completedSessions"
    }

    init(storage: any StorageServiceProtocol) {
        self.storage = storage
    }

    func saveActive(_ session: SleepSession) throws {
        try storage.save(session, key: Keys.active)
    }

    func loadActive() -> SleepSession? {
        try? storage.load(key: Keys.active)
    }

    func clearActive() {
        storage.remove(key: Keys.active)
    }

    func saveCompleted(_ session: SleepSession) throws {
        var sessions: [SleepSession] = (try? storage.load(key: Keys.completed)) ?? []
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
        if sessions.count > 30 { sessions = Array(sessions.prefix(30)) }
        try storage.save(sessions, key: Keys.completed)
    }

    func loadCompleted() -> [SleepSession] {
        (try? storage.load(key: Keys.completed)) ?? []
    }
}

// MARK: - In-memory (previews / tests)

final class InMemorySleepSessionRepository: SleepSessionRepositoryProtocol {
    private var active: SleepSession?
    private var completed: [SleepSession] = []

    func saveActive(_ session: SleepSession) throws { active = session }
    func loadActive() -> SleepSession? { active }
    func clearActive() { active = nil }

    func saveCompleted(_ session: SleepSession) throws {
        if let idx = completed.firstIndex(where: { $0.id == session.id }) {
            completed[idx] = session
        } else {
            completed.insert(session, at: 0)
        }
    }

    func loadCompleted() -> [SleepSession] { completed }
}
