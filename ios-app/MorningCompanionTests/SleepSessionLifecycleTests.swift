import Foundation
import Testing
@testable import MorningCompanion

/// The parts of a sleep session that go wrong while nobody is watching: a session
/// nobody stopped, and a reminder that forgets itself between launches.
@Suite("Sleep session lifecycle")
@MainActor
struct SleepSessionLifecycleTests {

    private final class InMemorySleepRepository: SleepSessionRepositoryProtocol {
        var active: SleepSession?
        var completed: [SleepSession] = []

        init(active: SleepSession? = nil) { self.active = active }

        func saveActive(_ session: SleepSession) throws { active = session }
        func loadActive() -> SleepSession? { active }
        func clearActive() { active = nil }
        func saveCompleted(_ session: SleepSession) throws { completed.append(session) }
        func loadCompleted() -> [SleepSession] { completed }
    }

    private func session(startedHoursAgo hours: Double) -> SleepSession {
        SleepSession(startDate: Date.now.addingTimeInterval(-hours * 3600))
    }

    // MARK: - Restore cap

    @Test("A session from a few hours ago is restored")
    func recentSessionRestores() {
        let repository = InMemorySleepRepository(active: session(startedHoursAgo: 7))
        let service = SleepTrackingService(repository: repository)
        #expect(service.isActive)
        #expect(service.isRestoredSession)
    }

    @Test("A session nobody ever stopped is discarded, not restored")
    func staleSessionDiscarded() {
        let repository = InMemorySleepRepository(active: session(startedHoursAgo: 30))
        let service = SleepTrackingService(repository: repository)
        #expect(!service.isActive)
        // Cleared, so tonight can start; and not written to history, because nobody
        // knows when this person actually woke up.
        #expect(repository.active == nil)
        #expect(repository.completed.isEmpty)
    }

    @Test("The cap is a boundary, not a range")
    func boundary() {
        let justInside = InMemorySleepRepository(active: session(startedHoursAgo: 13.9))
        #expect(SleepTrackingService(repository: justInside).isActive)

        let justOutside = InMemorySleepRepository(active: session(startedHoursAgo: 14.1))
        #expect(!SleepTrackingService(repository: justOutside).isActive)
    }

    // MARK: - Noise monitoring preference

    @Test("Noise monitoring is off until the user turns it on")
    func noiseMonitoringDefaultsOff() {
        UserDefaults.standard.removeObject(forKey: "com.morningcompanion.sleep.noiseMonitoring")
        let service = SleepTrackingService(repository: InMemorySleepRepository())
        #expect(!service.noiseMonitoringEnabled)
    }

    @Test("Noise monitoring survives a relaunch")
    func noiseMonitoringPersists() {
        let repository = InMemorySleepRepository()
        SleepTrackingService(repository: repository).setNoiseMonitoring(true)
        #expect(SleepTrackingService(repository: repository).noiseMonitoringEnabled)
        SleepTrackingService(repository: repository).setNoiseMonitoring(false)
        #expect(!SleepTrackingService(repository: repository).noiseMonitoringEnabled)
    }

    // MARK: - Bedtime reminder

    @Test("The bedtime reminder is remembered across launches")
    func bedtimeReminderPersists() throws {
        let storage = InMemoryStorageService()
        try storage.save(BedtimeReminder(isEnabled: true, hour: 23, minute: 15), key: StorageKeys.bedtimeReminder)

        let model = SleepViewModel(
            healthKitService: StubHealthKitService(),
            trackingService: SleepTrackingService(repository: InMemorySleepRepository()),
            alarmManager: AlarmManager(repository: MockAlarmRepository(alarms: []), engine: StubAlarmEngineService()),
            storageService: storage
        )
        #expect(model.bedtimeReminder == BedtimeReminder(isEnabled: true, hour: 23, minute: 15))
    }

    @Test("An out-of-range stored time is clamped rather than scheduled")
    func reminderTimeIsClamped() {
        let reminder = BedtimeReminder(isEnabled: true, hour: 47, minute: 91)
        #expect(reminder.hour == 23)
        #expect(reminder.minute == 59)
    }

    @Test("A store with no reminder in it starts disabled")
    func defaultReminder() {
        let model = SleepViewModel(
            healthKitService: StubHealthKitService(),
            trackingService: SleepTrackingService(repository: InMemorySleepRepository()),
            alarmManager: AlarmManager(repository: MockAlarmRepository(alarms: []), engine: StubAlarmEngineService()),
            storageService: InMemoryStorageService()
        )
        #expect(model.bedtimeReminder == .disabled)
        #expect(!model.bedtimeReminder.isEnabled)
    }
}

// MARK: - Merging the two sleep sources

/// A user who tracks with Dawnwick and never connects Apple Health still has sleep to
/// show. Until this worked, the Health permission decided whether their own recorded
/// nights appeared at all.
@Suite("Sleep sources")
struct SleepSourceMergeTests {

    /// 07:00 on the morning `daysAgo` days back. Nights are keyed by the morning they
    /// end on, so the fixtures end at a fixed hour: built from `.now`, a run after about
    /// 16:30 pushed a 7.5-hour session past midnight into the next day.
    private func morning(daysAgo: Int) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: .now))!
        return cal.date(bySettingHour: 7, minute: 0, second: 0, of: day)!
    }

    private func session(daysAgo: Int, hours: Double) -> SleepSession {
        let wake = morning(daysAgo: daysAgo)
        var s = SleepSession(startDate: wake.addingTimeInterval(-hours * 3600))
        s.endDate = wake
        return s
    }

    private func entry(daysAgo: Int, hours: Double) -> SleepEntry {
        SleepEntry(
            date: morning(daysAgo: daysAgo),
            duration: hours * 3600,
            inBedDuration: hours * 3600
        )
    }

    @Test("Local sessions alone still produce a history")
    func localOnly() {
        let merged = DaySleepSummary.merge(sessions: [session(daysAgo: 1, hours: 7)], healthEntries: [])
        #expect(merged.count == 1)
        #expect(merged.first?.duration == .some(7 * 3600))
    }

    @Test("Health entries alone still produce a history")
    func healthOnly() {
        let merged = DaySleepSummary.merge(sessions: [], healthEntries: [entry(daysAgo: 1, hours: 6)])
        #expect(merged.count == 1)
        #expect(merged.first?.duration == .some(6 * 3600))
    }

    @Test("For the same night the longer figure wins")
    func longerWins() {
        let merged = DaySleepSummary.merge(
            sessions: [session(daysAgo: 1, hours: 7.5)],
            healthEntries: [entry(daysAgo: 1, hours: 6)]
        )
        #expect(merged.count == 1, "the same night must not appear twice")
        #expect(merged.first?.duration == .some(7.5 * 3600))

        let other = DaySleepSummary.merge(
            sessions: [session(daysAgo: 1, hours: 5)],
            healthEntries: [entry(daysAgo: 1, hours: 8)]
        )
        #expect(other.first?.duration == .some(8 * 3600))
    }

    @Test("Different nights are kept separate and ordered newest first")
    func distinctNights() {
        let merged = DaySleepSummary.merge(
            sessions: [session(daysAgo: 3, hours: 6)],
            healthEntries: [entry(daysAgo: 1, hours: 7)]
        )
        #expect(merged.count == 2)
        #expect(merged.first?.duration == .some(7 * 3600), "newest first")
    }

    @Test("A session that never ended is not counted")
    func unfinishedSessionIgnored() {
        let running = SleepSession(startDate: .now.addingTimeInterval(-3600))
        #expect(DaySleepSummary.merge(sessions: [running], healthEntries: []).isEmpty)
    }
}

// MARK: - Sleep sounds

@Suite("Sleep sounds")
struct SleepSoundTests {

    @Test("Every offered sound has a file in the bundle")
    func everySoundIsBundled() throws {
        for sound in SleepSoundType.allCases where sound != .none {
            let name = try #require(sound.audioResourceName)
            #expect(
                Bundle.main.url(forResource: name, withExtension: "caf") != nil,
                "\(sound) is offered in the picker but has no audio — it would play silence"
            )
        }
    }

    @Test("A session recorded with a since-removed sound still decodes")
    func retiredSoundDecodes() throws {
        // Rain and ocean were in the picker before any audio existed for them. A
        // strict decode would throw here and take the whole night's record with it.
        for retired in ["rain", "ocean", "something_new"] {
            let json = Data("\"\(retired)\"".utf8)
            #expect(try JSONDecoder().decode(SleepSoundType.self, from: json) == SleepSoundType.none)
        }
    }

    @Test("Known sounds still round-trip")
    func knownSoundsRoundTrip() throws {
        for sound in SleepSoundType.allCases {
            let data = try JSONEncoder().encode(sound)
            #expect(try JSONDecoder().decode(SleepSoundType.self, from: data) == sound)
        }
    }
}
