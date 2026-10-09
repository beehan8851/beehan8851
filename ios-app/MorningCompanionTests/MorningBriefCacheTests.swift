import Foundation
import Testing
@testable import MorningCompanion

private struct Offline: Error {}

private final class OfflineHealth: HealthKitServiceProtocol {
    func authorizationState() async -> HealthKitAuthorizationState { .authorized }
    func requestAuthorization() async throws {}
    func lastNightSleepDuration() async throws -> TimeInterval? { throw Offline() }
    func sleepHistory(days: Int) async throws -> [SleepEntry] { throw Offline() }
}

private final class OfflineWeather: WeatherServiceProtocol {
    func authorizationState() async -> ContextualPermissionState { .granted }
    func requestAuthorization() async throws {}
    func currentConditions() async throws -> WeatherConditions? { throw Offline() }
}

private final class OfflineCalendar: CalendarServiceProtocol {
    func authorizationState() async -> ContextualPermissionState { .granted }
    func requestAuthorization() async throws {}
    func firstEventToday() async throws -> CalendarEventSummary? { throw Offline() }
}

/// Today shows what it kept from the last visit while the slow sources answer, and
/// keeps it when they do not. None of it may pass for today's once it is not.
@Suite("Morning brief cache")
@MainActor
struct MorningBriefCacheTests {
    /// A fixed Gregorian calendar in UTC so "today" never moves under the tests.
    private static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Wednesday 2026-09-09, 07:15 UTC.
    private static let morning = Date(timeIntervalSince1970: 1_788_938_100)

    private func hours(_ h: Double) -> Date { Self.morning.addingTimeInterval(h * 3600) }

    private func weather(at date: Date?) -> WeatherConditions {
        WeatherConditions(temperature: 18, high: 22, low: 13, symbolName: "sun.max.fill",
                          description: "Clear", precipitationChance: 0, capturedAt: date)
    }

    private func cache(readAt read: Date, event: Date? = nil) -> CachedMorningBrief {
        CachedMorningBrief(
            sleepDuration: 7 * 3600,
            weather: weather(at: read),
            calendarEvent: event.map { CalendarEventSummary(title: "Stand-up", startDate: $0, location: nil) },
            cachedAt: read,
            sleepReadAt: read,
            weatherReadAt: read
        )
    }

    // MARK: - What is still true

    @Test("Read this morning, everything stands")
    func fresh() {
        let kept = cache(readAt: hours(-1), event: hours(2)).usable(at: Self.morning, calendar: Self.calendar)
        #expect(kept.sleepDuration == TimeInterval(7 * 3600))
        #expect(kept.weather != nil)
        #expect(kept.calendarEvent != nil)
    }

    @Test("Yesterday's sleep is not last night's")
    func sleepFromYesterday() {
        let kept = cache(readAt: hours(-9)).usable(at: Self.morning, calendar: Self.calendar)
        #expect(kept.sleepDuration == nil)
    }

    @Test("Weather older than three hours is not the weather now")
    func staleWeather() {
        #expect(cache(readAt: hours(-2.5)).usable(at: Self.morning, calendar: Self.calendar).weather != nil)
        #expect(cache(readAt: hours(-3.5)).usable(at: Self.morning, calendar: Self.calendar).weather == nil)
    }

    @Test("An event that has begun, or is on another day, is no longer the next one")
    func staleEvent() {
        #expect(cache(readAt: hours(-1), event: hours(-0.5)).usable(at: Self.morning, calendar: Self.calendar).calendarEvent == nil)
        #expect(cache(readAt: hours(-1), event: hours(24)).usable(at: Self.morning, calendar: Self.calendar).calendarEvent == nil)
    }

    @Test("A cache from before the read dates is judged by when it was saved")
    func legacyCache() {
        let old = CachedMorningBrief(sleepDuration: 7 * 3600, weather: weather(at: nil), calendarEvent: nil, cachedAt: hours(-10))
        let kept = old.usable(at: Self.morning, calendar: Self.calendar)
        #expect(kept.sleepDuration == nil)
        #expect(kept.weather == nil)
    }

    // MARK: - On Today, with every source offline

    private func brief(storage: InMemoryStorageService) -> MorningBriefViewModel {
        MorningBriefViewModel(
            alarmManager: AlarmManager(repository: MockAlarmRepository(alarms: []), engine: StubAlarmEngineService()),
            healthKitService: OfflineHealth(),
            weatherService: OfflineWeather(),
            calendarService: OfflineCalendar(),
            storageService: storage,
            now: { Self.morning },
            calendar: Self.calendar
        )
    }

    @Test("Offline, a stale cache shows nothing as today's")
    func offlineStale() async throws {
        let storage = InMemoryStorageService()
        try storage.save(cache(readAt: hours(-20), event: hours(-18)), key: StorageKeys.morningBriefCache)
        let vm = brief(storage: storage)
        await vm.load()
        guard case .loaded(let data) = vm.state else { Issue.record("not loaded"); return }
        #expect(data.sleepDuration == nil)
        #expect(data.weather == nil)
        #expect(data.calendarEvent == nil)
    }

    @Test("Offline, a fresh cache is kept, and re-saving it does not make it newer")
    func offlineFresh() async throws {
        let storage = InMemoryStorageService()
        let read = hours(-1)
        try storage.save(cache(readAt: read, event: hours(2)), key: StorageKeys.morningBriefCache)
        let vm = brief(storage: storage)
        await vm.load()
        guard case .loaded(let data) = vm.state else { Issue.record("not loaded"); return }
        #expect(data.sleepDuration == TimeInterval(7 * 3600))
        #expect(data.weather != nil)
        #expect(data.calendarEvent != nil)
        let saved: CachedMorningBrief = try storage.load(key: StorageKeys.morningBriefCache)
        #expect(saved.sleepReadAt == read)
        #expect(saved.weatherReadAt == read)
    }
}
