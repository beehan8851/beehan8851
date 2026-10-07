import Testing
import Foundation
@testable import MorningCompanion

@Suite("Storage")
struct StorageTests {

    // MARK: - InMemoryStorageService

    @Test("Load from empty store throws notFound")
    func inMemoryNotFound() {
        let storage = InMemoryStorageService()
        #expect(throws: StorageError.self) {
            let _: String = try storage.load(key: "missing")
        }
    }

    @Test("Save then load round-trips a Codable value")
    func inMemoryRoundTrip() throws {
        let storage = InMemoryStorageService()
        try storage.save("hello", key: "greeting")
        let loaded: String = try storage.load(key: "greeting")
        #expect(loaded == "hello")
    }

    @Test("Remove makes key unavailable")
    func inMemoryRemove() throws {
        let storage = InMemoryStorageService()
        try storage.save(42, key: "number")
        storage.remove(key: "number")
        #expect(throws: StorageError.self) {
            let _: Int = try storage.load(key: "number")
        }
    }

    @Test("Injected corrupt data throws decodingFailed")
    func inMemoryCorruption() {
        let storage = InMemoryStorageService()
        storage.injectCorruptData(key: "alarms")
        var caught = false
        do {
            let _: [Alarm] = try storage.load(key: "alarms")
        } catch StorageError.decodingFailed {
            caught = true
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
        #expect(caught)
    }

    @Test("Struct value round-trips through InMemory storage")
    func inMemoryStructRoundTrip() throws {
        let storage = InMemoryStorageService()
        let original = AlarmTime(hour: 7, minute: 30)
        try storage.save(original, key: "time")
        let loaded: AlarmTime = try storage.load(key: "time")
        #expect(loaded == original)
    }

    // MARK: - UserDefaultsStorageService

    @Test("Load from empty UserDefaults throws notFound")
    func userDefaultsNotFound() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let storage = UserDefaultsStorageService(defaults: defaults)
        #expect(throws: StorageError.self) {
            let _: String = try storage.load(key: "missing")
        }
    }

    @Test("Save then load round-trips through UserDefaults")
    func userDefaultsRoundTrip() throws {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let storage = UserDefaultsStorageService(defaults: defaults)
        try storage.save("world", key: "key")
        let loaded: String = try storage.load(key: "key")
        #expect(loaded == "world")
    }

    @Test("UserDefaults corruption throws storageFailure via LocalAlarmRepository")
    func repositoryCorruptionSurfaces() async {
        let storage = InMemoryStorageService()
        // Inject raw bytes that are valid JSON for a wrong type → decoding failure
        storage.injectCorruptData(key: "com.morningcompanion.alarms.v1")

        let repo = LocalAlarmRepository(storage: storage)
        do {
            _ = try await repo.fetchAll()
            Issue.record("Expected AlarmRepositoryError.storageFailure, but no error was thrown")
        } catch let error as AlarmRepositoryError {
            if case .storageFailure = error { /* expected */ } else {
                Issue.record("Expected .storageFailure, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
