import Foundation
import os
import UserNotifications

// MARK: - Screen data types (used by SleepView)

struct SleepScreenData {
    let lastNightDuration: TimeInterval?
    let history: [SleepEntry]
}

enum SleepScreenState {
    case idle
    case loading
    case loaded(SleepScreenData)
    case empty
    /// Health has never been asked for. The screen offers; the tap does the asking.
    case notConnected
    case permissionDenied
    case error(any Error)
}

// MARK: - Mode

enum SleepViewMode {
    case morning   // 05:00 – 16:59 — show last night
    case evening   // 17:00 – 04:59 — show tracking setup

    static var current: SleepViewMode {
        let h = Calendar.current.component(.hour, from: .now)
        return h >= 5 && h < 17 ? .morning : .evening
    }
}

// MARK: - ViewModel

@MainActor
@Observable
final class SleepViewModel {

    // MARK: - Health state

    var healthState: SleepScreenState = .idle

    // MARK: - Next alarm

    private(set) var nextAlarmDate: Date?
    private(set) var nextAlarmLabel: String?

    var nextAlarmText: String? {
        guard let date = nextAlarmDate else { return nil }
        let time = date.formatted(.dateTime.hour().minute())
        if let label = nextAlarmLabel, !label.isEmpty {
            return "\(time) — \(label)"
        }
        return String(localized: "Alarm at \(time)", comment: "Next alarm time text")
    }

    // MARK: - Bedtime reminder

    private(set) var bedtimeReminder: BedtimeReminder = .disabled
    /// Set when the reminder was switched on but notifications are refused. The toggle
    /// goes back to off, because a switch that says "on" while nothing can arrive is a
    /// lie the user only discovers by not being reminded.
    private(set) var bedtimeReminderNeedsPermission = false

    // MARK: - Post-session result

    var completedSession: SleepSession?
    var showingResult: Bool = false

    // MARK: - Report data (loaded lazily)

    private(set) var completedSessions: [SleepSession] = []
    /// Both sources merged, for the Sleep screen's list.
    private(set) var sleepHistory: [SleepEntry] = []
    /// Health alone, for the report — which merges the sources itself and labels
    /// each night with where it came from. Handing it the merged list made every
    /// night the app recorded read "Apple Health".
    private(set) var healthEntries: [SleepEntry] = []

    // MARK: - Mode

    var viewMode: SleepViewMode { .current }

    // MARK: - Dependencies

    let trackingService: SleepTrackingService
    private let healthKitService: any HealthKitServiceProtocol
    private let alarmManager: AlarmManager
    private let storageService: any StorageServiceProtocol
    private let notificationCenter: UNUserNotificationCenter
    private let calendar = Calendar.current

    init(
        healthKitService: any HealthKitServiceProtocol,
        trackingService: SleepTrackingService,
        alarmManager: AlarmManager,
        storageService: any StorageServiceProtocol,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.healthKitService = healthKitService
        self.trackingService = trackingService
        self.alarmManager = alarmManager
        self.storageService = storageService
        self.notificationCenter = notificationCenter
        bedtimeReminder = (try? storageService.load(key: StorageKeys.bedtimeReminder)) ?? .disabled
    }

    // MARK: - Load

    func load() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadHealthData() }
            group.addTask { await self.loadNextAlarm() }
        }
        completedSessions = trackingService.loadCompletedSessions()
    }

    func refreshHealthData() async {
        await loadHealthData()
    }

    /// Requests Health access and reloads. Called from the card's own button.
    func connectHealth() async {
        do {
            try await healthKitService.requestAuthorization()
        } catch {
            Log.services.error("HealthKit authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        await loadHealthData()
    }

    // MARK: - Tracking

    func startTracking(withNoiseMonitoring: Bool) async {
        if withNoiseMonitoring && !trackingService.hasMicPermission {
            _ = await trackingService.requestMicrophonePermission()
        }
        await loadNextAlarm()
        await trackingService.startSession(
            nextAlarmDate: nextAlarmDate,
            nextAlarmLabel: nextAlarmLabel
        )
    }

    func onSessionCompleted(_ session: SleepSession) {
        completedSessions = trackingService.loadCompletedSessions()
        completedSession = session
        showingResult = true
    }

    // MARK: - Private loaders

    private func loadNextAlarm() async {
        guard let alarms = try? await alarmManager.fetchAll() else { return }
        let next = alarms
            .compactMap { alarm -> (Alarm, Date)? in
                guard let d = NextAlarmCalculator.nextFireDate(for: alarm, after: .now) else { return nil }
                return (alarm, d)
            }
            .min { $0.1 < $1.1 }
        nextAlarmDate = next?.1
        nextAlarmLabel = next?.0.label.isEmpty == false ? next?.0.label : nil
    }

    private func loadHealthData() async {
        healthState = .loading

        // Sessions this app tracked itself are always available and never need a
        // permission. They are loaded first, because a user who tracks with Dawnwick
        // and has never connected Health used to see an empty screen and no way to
        // understand why: the Health state decided everything, including whether their
        // own recorded nights were shown at all.
        let local = trackingService.loadCompletedSessions()
        completedSessions = local

        let authState = await healthKitService.authorizationState()
        if authState == .unavailable {
            healthState = present(local: local, health: [], lastNightFromHealth: nil)
                ?? .error(HealthKitServiceError.healthDataUnavailable)
            return
        }
        if authState == .denied {
            healthState = present(local: local, health: [], lastNightFromHealth: nil) ?? .permissionDenied
            return
        }
        if authState == .notDetermined {
            // Opening a tab is not consent. `connectHealth()` does the asking, from a
            // button that says what it is for.
            healthState = present(local: local, health: [], lastNightFromHealth: nil) ?? .notConnected
            return
        }

        do {
            let lastNight = try await healthKitService.lastNightSleepDuration()
            let history = try await healthKitService.sleepHistory(days: 7)
            healthState = present(local: local, health: history, lastNightFromHealth: lastNight) ?? .empty
        } catch HealthKitServiceError.authorizationDenied {
            healthState = present(local: local, health: [], lastNightFromHealth: nil) ?? .permissionDenied
        } catch {
            healthState = present(local: local, health: [], lastNightFromHealth: nil) ?? .error(error)
        }
    }

    /// Combines both sources into what the screen shows, or `nil` when there is
    /// nothing at all — in which case the caller decides which empty state fits.
    ///
    /// The merge rule is the report screen's: for a given night, whichever source
    /// recorded more sleep wins. A phone left on a nightstand under-reports against a
    /// Watch, and a Watch under-reports against a phone that was actually running all
    /// night, so the longer figure is the less wrong one.
    private func present(
        local: [SleepSession],
        health: [SleepEntry],
        lastNightFromHealth: TimeInterval?
    ) -> SleepScreenState? {
        healthEntries = health
        let merged = DaySleepSummary.merge(sessions: local, healthEntries: health)
        sleepHistory = merged.compactMap { summary in
            summary.duration.map {
                SleepEntry(date: summary.date, duration: $0, inBedDuration: $0)
            }
        }

        let startOfToday = calendar.startOfDay(for: .now)
        let lastNightLocal = local
            .filter { $0.startDate >= calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday }
            .compactMap(\.duration)
            .max()
        let lastNight = [lastNightFromHealth, lastNightLocal].compactMap { $0 }.max()

        guard lastNight != nil || !sleepHistory.isEmpty else { return nil }
        return .loaded(SleepScreenData(lastNightDuration: lastNight, history: sleepHistory))
    }

    // MARK: - Bedtime reminder

    private let bedtimeReminderID = NotificationDelegate.bedtimeReminderIdentifier

    func setBedtimeReminderEnabled(_ isEnabled: Bool) async {
        var updated = bedtimeReminder
        updated.isEnabled = isEnabled
        await apply(updated)
    }

    func setBedtimeReminderTime(hour: Int, minute: Int) async {
        var updated = bedtimeReminder
        updated.hour = hour
        updated.minute = minute
        await apply(updated)
    }

    /// Stores the setting, then makes the system match it.
    ///
    /// Order matters: the notification is the source of truth for what actually
    /// happens at night, so nothing is stored as "on" that could not be scheduled.
    private func apply(_ reminder: BedtimeReminder) async {
        bedtimeReminderNeedsPermission = false

        guard reminder.isEnabled else {
            bedtimeReminder = reminder
            persistBedtimeReminder()
            cancelBedtimeReminder()
            return
        }

        guard await hasNotificationPermission() else {
            bedtimeReminderNeedsPermission = true
            bedtimeReminder = BedtimeReminder(isEnabled: false, hour: reminder.hour, minute: reminder.minute)
            persistBedtimeReminder()
            cancelBedtimeReminder()
            return
        }

        bedtimeReminder = reminder
        persistBedtimeReminder()
        scheduleBedtimeReminder()
    }

    /// Asks only when nothing has been decided — the user turning this switch on is
    /// the consent. A previous refusal is reported, not re-prompted; iOS would not
    /// show the dialog a second time anyway.
    private func hasNotificationPermission() async -> Bool {
        switch await notificationCenter.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            let granted = (try? await notificationCenter.requestAuthorization(options: [.alert, .sound])) ?? false
            return granted
        default:
            return false
        }
    }

    private func persistBedtimeReminder() {
        do {
            try storageService.save(bedtimeReminder, key: StorageKeys.bedtimeReminder)
        } catch {
            Log.storage.error("Bedtime reminder could not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleBedtimeReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [bedtimeReminderID])

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time to wind down", comment: "Bedtime reminder title")
        if let text = nextAlarmText {
            content.body = String(localized: "Your alarm is set for \(text).", comment: "Bedtime reminder body")
        } else {
            content.body = String(localized: "Get a good night's sleep.", comment: "Bedtime reminder body no alarm")
        }
        content.sound = UNNotificationSound.default

        var comps = DateComponents()
        comps.hour = bedtimeReminder.hour
        comps.minute = bedtimeReminder.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        notificationCenter.add(UNNotificationRequest(
            identifier: bedtimeReminderID,
            content: content,
            trigger: trigger
        ))
    }

    private func cancelBedtimeReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [bedtimeReminderID])
    }
}
