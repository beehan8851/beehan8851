import Foundation
import Observation
import OSLog

// MARK: - Cache

/// The slow parts of Today, kept so the screen shows something at once on the next
/// visit. Each part goes stale on its own clock, and a stale part is dropped rather
/// than shown as today's: last night's sleep and today's first event belong to the
/// day they were read on, the weather to the next few hours.
struct CachedMorningBrief: Codable {
    var sleepDuration: TimeInterval?
    var weather: WeatherConditions?
    var calendarEvent: CalendarEventSummary?
    var cachedAt: Date
    /// When each part was last read from its source. A failed refresh keeps the old
    /// value and its old date, so a value cannot stay fresh just by being re-saved.
    /// Caches written before these existed have neither; `cachedAt` stands in.
    var sleepReadAt: Date?
    var weatherReadAt: Date?

    /// How long a weather reading may stand in for the weather now.
    static let weatherShelfLife: TimeInterval = 3 * 3600

    /// What is still true at `now`.
    func usable(at now: Date, calendar: Calendar = .current) -> CachedMorningBrief {
        var kept = self
        if !calendar.isDate(sleepReadAt ?? cachedAt, inSameDayAs: now) {
            kept.sleepDuration = nil
        }
        // The next event today, as the calendar is asked for it: one that has begun, or
        // is on another day, is no longer that.
        if let event = calendarEvent, event.startDate < now || !calendar.isDate(event.startDate, inSameDayAs: now) {
            kept.calendarEvent = nil
        }
        let weatherRead = weather?.capturedAt ?? weatherReadAt ?? cachedAt
        // A reading from the future is a clock that was changed: not to be trusted either.
        if abs(now.timeIntervalSince(weatherRead)) > Self.weatherShelfLife {
            kept.weather = nil
        }
        return kept
    }
}

// MARK: - Data

struct MorningBriefData {
    let nextAlarm: Alarm?
    let nextFireDate: Date?
    let sleepDuration: TimeInterval?
    let weather: WeatherConditions?
    let calendarEvent: CalendarEventSummary?
    let streakDays: Int?
    /// Whether today's mission has already been completed.
    var wokeToday: Bool = false
    /// The current week for the strip at the top of Home.
    var week: [DayCell] = []
    /// The best streak so far, for the next trick the cat learns.
    var bestStreak: Int = 0
    /// Missed mornings the cat can still cover for.
    var covers: Int = 0
}

// MARK: - ViewModel

@MainActor
@Observable
final class MorningBriefViewModel {
    var state: FeatureLoadState<MorningBriefData> = .idle
    var focusText = ""
    var focusSaveFailed = false
    private(set) var weatherErrorDescription: String?
    /// Whether the weather is missing because location was refused, rather than
    /// because the network or the provider had a bad moment. Only the first of those
    /// is worth offering the user a way to fix.
    private(set) var weatherNeedsLocationPermission = false
    /// What the two optional permissions are doing, so the cards can offer rather
    /// than the screen demanding.
    private(set) var locationPermission: ContextualPermissionState = .notDetermined
    private(set) var calendarPermission: ContextualPermissionState = .notDetermined

    private let alarmManager: AlarmManager
    private let healthKitService: any HealthKitServiceProtocol
    private let weatherService: any WeatherServiceProtocol
    private let calendarService: any CalendarServiceProtocol
    private let storageService: any StorageServiceProtocol
    private let now: () -> Date
    private let calendar: Calendar
    private var isRefreshing = false
    private let logger = Logger(subsystem: Log.subsystem, category: "MorningBrief")

    init(
        alarmManager: AlarmManager,
        healthKitService: any HealthKitServiceProtocol,
        weatherService: any WeatherServiceProtocol,
        calendarService: any CalendarServiceProtocol,
        storageService: any StorageServiceProtocol,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.alarmManager = alarmManager
        self.healthKitService = healthKitService
        self.weatherService = weatherService
        self.calendarService = calendarService
        self.storageService = storageService
        self.now = now
        self.calendar = calendar
    }

    func load() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        focusSaveFailed = false
        weatherErrorDescription = nil
        weatherNeedsLocationPermission = false
        let referenceDate = now()

        // Fast local data — UserDefaults reads, no I/O wait
        let alarms = (try? await alarmManager.fetchAll()) ?? []
        let next = alarms
            .compactMap { alarm -> (alarm: Alarm, date: Date)? in
                guard let date = NextAlarmCalculator.nextFireDate(
                    for: alarm,
                    after: referenceDate,
                    in: calendar
                ) else { return nil }
                return (alarm, date)
            }
            .min { $0.date < $1.date }
        let storedStreak: StreakRecord = (try? storageService.load(key: StorageKeys.streakRecord)) ?? StreakRecord()
        let scheduled = StreakRecord.scheduled(by: alarms, calendar: calendar)
        // With any covers due spent, so a covered morning reads as covered.
        let streakRecord = storedStreak.settled(on: referenceDate, calendar: calendar, hadAlarm: scheduled)
        let live = streakRecord.liveStreak(on: referenceDate, calendar: calendar, hadAlarm: scheduled)
        let streakDays = live > 0 ? live : nil
        let wokeToday = streakRecord.isCompleted(referenceDate, calendar: calendar)
        let week = DayCell.currentWeek(record: streakRecord, alarms: alarms, now: referenceDate, calendar: calendar)
        loadFocus(for: referenceDate)

        // Show cached data immediately — Today screen appears with no spinner on repeat visits
        let stored: CachedMorningBrief? = try? storageService.load(key: StorageKeys.morningBriefCache)
        let cached = stored?.usable(at: referenceDate, calendar: calendar)
        if let cached {
            state = .loaded(MorningBriefData(
                nextAlarm: next?.alarm,
                nextFireDate: next?.date,
                sleepDuration: cached.sleepDuration,
                weather: cached.weather,
                calendarEvent: cached.calendarEvent,
                streakDays: streakDays,
                wokeToday: wokeToday,
                week: week,
                bestStreak: streakRecord.bestStreak,
                covers: streakRecord.covers
            ))
        } else {
            state = .loading
        }

        // Read the permissions; never ask for them here. Opening a tab is not consent,
        // and a system dialog the user did not press a button for is answered "Don't
        // Allow" often enough that it is worth waiting for the tap. `enableWeather`
        // and `enableCalendar` do the asking, from the cards themselves.
        locationPermission = await weatherService.authorizationState()
        calendarPermission = await calendarService.authorizationState()
        weatherNeedsLocationPermission = (locationPermission == .unavailable)
        logger.debug("Brief permissions — location \(String(describing: self.locationPermission), privacy: .public), calendar \(String(describing: self.calendarPermission), privacy: .public)")

        // Parallel slow loads — total wait = max(sleep, weather, calendar) not their sum
        async let sleepTask = healthKitService.lastNightSleepDuration()
        async let calendarTask = calendarService.firstEventToday()

        // Read, or failed to read: `nil` here means the source did not answer, which
        // is not the same as answering "nothing".
        let freshSleep: TimeInterval??
        do { freshSleep = .some(try await sleepTask) } catch { freshSleep = nil }
        let freshWeather: WeatherConditions?
        // `currentConditions()` asks for location itself when it has not been decided,
        // which would put the prompt back on the tab appearing. Nothing is fetched
        // until the user has said yes from the card.
        if locationPermission == .notDetermined {
            freshWeather = nil
        } else {
            do {
                freshWeather = try await weatherService.currentConditions()
                if freshWeather == nil {
                    weatherErrorDescription = "WeatherKit returned no conditions."
                    logger.error("WeatherKit returned no conditions")
                }
            } catch {
                freshWeather = nil
                weatherErrorDescription = error.localizedDescription
                noteLocationRefusal(error)
                logger.error("Weather refresh failed: \(error.localizedDescription, privacy: .public)")
                // The full error, not just its message: `.debug` is compiled in but
                // not written to disk, so this costs nothing until someone streams it.
                logger.debug("Weather refresh failure detail: \(String(reflecting: error), privacy: .public)")
            }
        }
        let freshEvent: CalendarEventSummary??
        do { freshEvent = .some(try await calendarTask) } catch { freshEvent = nil }

        // A source that did not answer keeps what it said last, while that is still
        // true (`usable(at:)` above); one that answered is believed, "nothing" included.
        let weather = freshWeather ?? cached?.weather
        let sleepDuration = freshSleep ?? cached?.sleepDuration
        let calendarEvent = freshEvent ?? cached?.calendarEvent

        // Persist for the next visit, each part with when it was really read.
        let newCache = CachedMorningBrief(
            sleepDuration: sleepDuration,
            weather: weather,
            calendarEvent: calendarEvent,
            cachedAt: referenceDate,
            sleepReadAt: freshSleep != nil ? referenceDate : (cached?.sleepReadAt ?? cached?.cachedAt),
            weatherReadAt: freshWeather != nil ? referenceDate : (cached?.weatherReadAt ?? cached?.cachedAt)
        )
        try? storageService.save(newCache, key: StorageKeys.morningBriefCache)

        // Update view with fresh data (replaces cache or initial loading state)
        state = .loaded(MorningBriefData(
            nextAlarm: next?.alarm,
            nextFireDate: next?.date,
            sleepDuration: sleepDuration,
            weather: weather,
            calendarEvent: calendarEvent,
            streakDays: streakDays,
            wokeToday: wokeToday,
            week: week,
            bestStreak: streakRecord.bestStreak,
            covers: streakRecord.covers
        ))
    }

    func saveFocus() {
        let normalizedFocus = focusText.trimmingCharacters(in: .whitespacesAndNewlines)
        focusText = normalizedFocus

        do {
            if normalizedFocus.isEmpty {
                storageService.remove(key: focusStorageKey(for: now()))
            } else {
                try storageService.save(normalizedFocus, key: focusStorageKey(for: now()))
            }
            focusSaveFailed = false
        } catch {
            focusSaveFailed = true
        }
    }

    private func loadFocus(for date: Date) {
        do {
            focusText = try storageService.load(key: focusStorageKey(for: date))
        } catch StorageError.notFound {
            focusText = ""
        } catch {
            focusText = ""
            focusSaveFailed = true
        }
    }

    /// Asks for location, then reloads. Called from the weather card's own button —
    /// the tap is the consent, and it is the only thing that opens the system prompt.
    func enableWeather() async {
        do {
            try await weatherService.requestAuthorization()
        } catch {
            weatherErrorDescription = error.localizedDescription
            noteLocationRefusal(error)
            logger.error("Weather authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        locationPermission = await weatherService.authorizationState()
        await load()
    }

    /// Asks for calendar access, then reloads. Same rule as `enableWeather`.
    func enableCalendar() async {
        try? await calendarService.requestAuthorization()
        calendarPermission = await calendarService.authorizationState()
        await load()
    }

    /// A refused permission is the one weather failure the user can do something
    /// about. Everything else — a timeout, a provider outage — resolves on its own and
    /// should not send anyone to the Settings app.
    private func noteLocationRefusal(_ error: any Error) {
        guard let locationError = error as? LocationProviderError else { return }
        switch locationError {
        case .permissionDenied, .restricted:
            weatherNeedsLocationPermission = true
        case .unavailable, .timedOut:
            weatherNeedsLocationPermission = false
        }
    }

    private func focusStorageKey(for date: Date) -> String {
        Self.focusStorageKey(for: date, calendar: calendar)
    }

    /// The day's focus lives under its date, so the wind-down can leave tomorrow's.
    static func focusStorageKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "com.morningcompanion.today.focus.\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}
