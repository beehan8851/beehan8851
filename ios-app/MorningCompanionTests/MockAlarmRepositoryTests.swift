import Testing
import Foundation
@testable import MorningCompanion

@Suite("MockAlarmRepository")
struct MockAlarmRepositoryTests {

    @Test("fetchAll returns seeded alarms")
    func fetchAllReturnsSeedData() async throws {
        let repo = MockAlarmRepository(alarms: Alarm.samples)
        let alarms = try await repo.fetchAll()
        #expect(alarms.count == 2)
    }

    @Test("save appends new alarm")
    func saveAppends() async throws {
        let repo = MockAlarmRepository(alarms: [])
        let alarm = Alarm(label: "New")
        try await repo.save(alarm)
        let alarms = try await repo.fetchAll()
        #expect(alarms.count == 1)
        #expect(alarms.first?.label == "New")
    }

    @Test("save updates existing alarm by id")
    func saveUpdatesExisting() async throws {
        var alarm = Alarm(label: "Original")
        let repo = MockAlarmRepository(alarms: [alarm])
        alarm.label = "Updated"
        try await repo.save(alarm)
        let alarms = try await repo.fetchAll()
        #expect(alarms.count == 1)
        #expect(alarms.first?.label == "Updated")
    }

    @Test("delete removes alarm by id")
    func deleteRemoves() async throws {
        let alarm = Alarm(label: "To delete")
        let repo = MockAlarmRepository(alarms: [alarm])
        try await repo.delete(id: alarm.id)
        let alarms = try await repo.fetchAll()
        #expect(alarms.isEmpty)
    }

    @Test("delete non-existent id is a no-op")
    func deleteNonExistent() async throws {
        let repo = MockAlarmRepository(alarms: Alarm.samples)
        try await repo.delete(id: UUID())
        let alarms = try await repo.fetchAll()
        #expect(alarms.count == 2)
    }
}
