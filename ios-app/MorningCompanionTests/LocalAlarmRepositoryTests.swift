import Testing
import Foundation
@testable import MorningCompanion

@Suite("LocalAlarmRepository")
struct LocalAlarmRepositoryTests {

    private func makeRepository() -> LocalAlarmRepository {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let storage = UserDefaultsStorageService(defaults: defaults)
        return LocalAlarmRepository(storage: storage)
    }

    @Test("fetchAll returns empty list when no data stored")
    func fetchAllEmpty() async throws {
        let repo = makeRepository()
        let alarms = try await repo.fetchAll()
        #expect(alarms.isEmpty)
    }

    @Test("save then fetchAll returns saved alarm")
    func saveThenFetch() async throws {
        let repo = makeRepository()
        let alarm = Alarm(label: "Persisted")
        try await repo.save(alarm)
        let alarms = try await repo.fetchAll()
        #expect(alarms.count == 1)
        #expect(alarms.first?.label == "Persisted")
    }

    @Test("save updates existing alarm")
    func saveUpdates() async throws {
        var alarm = Alarm(label: "Original")
        let repo = makeRepository()
        try await repo.save(alarm)
        alarm.label = "Updated"
        try await repo.save(alarm)
        let alarms = try await repo.fetchAll()
        #expect(alarms.count == 1)
        #expect(alarms.first?.label == "Updated")
    }

    @Test("delete removes alarm and fetch returns empty")
    func deleteAndFetch() async throws {
        let alarm = Alarm(label: "Gone")
        let repo = makeRepository()
        try await repo.save(alarm)
        try await repo.delete(id: alarm.id)
        let alarms = try await repo.fetchAll()
        #expect(alarms.isEmpty)
    }
}
