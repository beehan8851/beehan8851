import Foundation
import UserNotifications

// MARK: - Error

enum NotificationServiceError: LocalizedError {
    case notAuthorized
    case invalidFireDate
    case schedulingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return String(
                localized: "Notification permission is not granted. Open Settings → Dawnwick → Notifications to enable alarms.",
                comment: "Notification denied error"
            )
        case .invalidFireDate:
            return String(localized: "The one-time alarm must be scheduled in the future.", comment: "Past alarm error")
        case .schedulingFailed(let err):
            return String(
                localized: "Alarm could not be scheduled: \(err.localizedDescription)",
                comment: "Scheduling failure error"
            )
        }
    }
}

// MARK: - Service

/// Production UNUserNotificationCenter-backed alarm engine.
///
/// Notification ID scheme (using | as separator, safe because UUID strings never contain |):
///   daily alarm:           "{UUID}|daily"
///   one-time alarm:        "{UUID}|once"
///   repeating weekday N:   "{UUID}|day|{weekday.rawValue}"    (rawValue 1=Sun … 7=Sat)
///   re-arm / snooze:       "{reArmUUID}|snooze"   (reArmUUID is registered in ReArmRegistry)
///   wake check:            "wakecheck"            (category WAKE_CHECK, see AppContainer)
///
/// All scheduling is authoritative: schedule() cancels old requests for the alarm
/// before adding new ones, so edit/reschedule is idempotent.
final class AlarmNotificationService: AlarmEngineServiceProtocol {

    private let center = UNUserNotificationCenter.current()

    init() {
        registerCategories()
    }

    // MARK: - Authorization

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - AlarmEngineServiceProtocol

    func schedule(_ alarm: Alarm) async throws {
        guard alarm.isEnabled else {
            try await cancel(id: alarm.id)
            return
        }

        try await requireAuthorization()

        // Remove stale requests before re-scheduling (handles edits)
        await removeAllPending(for: alarm.id)

        let content = makeContent(for: alarm)

        switch alarm.recurrence {
        case .oneTime(let date):
            try await scheduleOneTime(alarm: alarm, alarmDate: date, content: content)
        case .daily:
            try await scheduleDaily(alarm: alarm, content: content)
        case .repeating(let days):
            guard !days.isEmpty else { return }
            try await scheduleRepeating(alarm: alarm, days: days, content: content)
        }
    }

    func scheduleReArm(for alarm: Alarm, reArmID: UUID, delay: TimeInterval) async throws {
        try await requireAuthorization()

        let content = makeContent(for: alarm)
        let snoozeLabel = alarm.label.isEmpty
            ? String(localized: "Wake up", comment: "Default snooze title")
            : alarm.label
        content.title = "\(snoozeLabel) (Snooze)"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(
            identifier: notifID(reArmID, tag: "snooze"),
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            throw NotificationServiceError.schedulingFailed(underlying: error)
        }
    }

    func cancel(id: UUID) async throws {
        await removeAllPending(for: id)
    }

    func cancelAll() async throws {
        center.removeAllPendingNotificationRequests()
    }

    func pendingAlarmIDs() async throws -> [UUID] {
        let requests = await center.pendingNotificationRequests()
        var seen = Set<UUID>()
        for req in requests {
            // ID format: "{UUID}|{tag}" — split on first | to extract the UUID
            guard let separator = req.identifier.firstIndex(of: "|") else { continue }
            let uuidPart = String(req.identifier[req.identifier.startIndex..<separator])
            // Re-arm ("|snooze") ids are reported too; AlarmManager filters them via ReArmRegistry.
            if let uuid = UUID(uuidString: uuidPart) {
                seen.insert(uuid)
            }
        }
        return Array(seen)
    }

    // MARK: - Debug

    /// Schedules a visible notification `seconds` from now.
    /// Useful for verifying the full scheduling stack on a physical device.
    func scheduleTestNotification(in seconds: TimeInterval = 10) async throws {
        try await requireAuthorization()

        let content = UNMutableNotificationContent()
        content.title = String(localized: "Test Alarm", comment: "Debug test notification title")
        content.body  = String(localized: "Scheduling is working — app + background + lock screen.", comment: "Debug test body")
        content.sound = .default
        content.badge = 1

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(
            identifier: "debug|test|\(Int(Date.now.timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            throw NotificationServiceError.schedulingFailed(underlying: error)
        }
    }

    // MARK: - Private scheduling helpers

    private func scheduleOneTime(
        alarm: Alarm,
        alarmDate: AlarmDate,
        content: UNMutableNotificationContent
    ) async throws {
        var comps = DateComponents()
        comps.year   = alarmDate.year
        comps.month  = alarmDate.month
        comps.day    = alarmDate.day
        comps.hour   = alarm.wallClockTime.hour
        comps.minute = alarm.wallClockTime.minute
        comps.second = 0

        guard let fireDate = Calendar.current.date(from: comps), fireDate > .now else {
            throw NotificationServiceError.invalidFireDate
        }

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: notifID(alarm.id, tag: "once"),
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            throw NotificationServiceError.schedulingFailed(underlying: error)
        }
    }

    private func scheduleDaily(alarm: Alarm, content: UNMutableNotificationContent) async throws {
        var comps = DateComponents()
        comps.hour   = alarm.wallClockTime.hour
        comps.minute = alarm.wallClockTime.minute
        comps.second = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(
            identifier: notifID(alarm.id, tag: "daily"),
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            throw NotificationServiceError.schedulingFailed(underlying: error)
        }
    }

    private func scheduleRepeating(
        alarm: Alarm,
        days: Set<Weekday>,
        content: UNMutableNotificationContent
    ) async throws {
        for day in days {
            var comps = DateComponents()
            comps.weekday = day.rawValue  // Calendar: 1=Sunday … 7=Saturday
            comps.hour    = alarm.wallClockTime.hour
            comps.minute  = alarm.wallClockTime.minute
            comps.second  = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(
                identifier: notifID(alarm.id, tag: "day|\(day.rawValue)"),
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
            } catch {
                throw NotificationServiceError.schedulingFailed(underlying: error)
            }
        }
    }

    // MARK: - Private helpers

    private func requireAuthorization() async throws {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return
        case .notDetermined:
            let granted = try await requestAuthorization()
            if !granted { throw NotificationServiceError.notAuthorized }
        case .denied:
            throw NotificationServiceError.notAuthorized
        @unknown default:
            throw NotificationServiceError.notAuthorized
        }
    }

    private func makeContent(for alarm: Alarm) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty
            ? String(localized: "Wake up", comment: "Default alarm notification title")
            : alarm.label
        content.body  = alarm.wallClockTime.displayString
        content.sound = notificationSound(for: alarm.sound)
        content.badge = 1
        content.userInfo = ["alarmID": alarm.id.uuidString]
        // Use separate categories so the Snooze button only appears when snooze is enabled
        content.categoryIdentifier = alarm.snooze.isEnabled ? "ALARM" : "ALARM_NO_SNOOZE"
        // TimeSensitive breaks through Focus and Notification Summary without a special entitlement.
        // It does not bypass the ringer switch — that requires the critical-alerts entitlement.
        content.interruptionLevel = .timeSensitive
        return content
    }

    private func notificationSound(for sound: AlarmSound) -> UNNotificationSound {
        switch sound {
        case .default:
            // defaultRingtone plays at ringtone volume, noticeably louder than the standard
            // notification sound for alarm use cases.
            return .defaultRingtone
        case .gentle, .rise, .pulse, .chime, .digital, .meow:
            // A missing named file can result in no useful custom tone on some
            // system versions, so explicitly fall back to an audible ringtone.
            guard Bundle.main.url(forResource: sound.rawValue, withExtension: "caf") != nil else {
                return .defaultRingtone
            }
            return UNNotificationSound(named: UNNotificationSoundName(rawValue: "\(sound.rawValue).caf"))
        }
    }

    private func notifID(_ uuid: UUID, tag: String) -> String {
        "\(uuid.uuidString)|\(tag)"
    }

    /// All possible notification identifiers for a given alarm UUID.
    /// Used to cancel all variants atomically (daily, once, snooze, and all 7 weekdays).
    private func allNotifIDs(for uuid: UUID) -> [String] {
        var ids = [
            notifID(uuid, tag: "daily"),
            notifID(uuid, tag: "once"),
            notifID(uuid, tag: "snooze"),
        ]
        for weekday in 1...7 {
            ids.append(notifID(uuid, tag: "day|\(weekday)"))
        }
        return ids
    }

    private func removeAllPending(for uuid: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: allNotifIDs(for: uuid))
    }

    private func registerCategories() {
        let snoozeAction = UNNotificationAction(
            identifier: AlarmNotificationAction.snoozeIdentifier,
            title: String(localized: "Snooze", comment: "Alarm snooze action"),
            options: []
        )
        let dismissAction = UNNotificationAction(
            identifier: AlarmNotificationAction.dismissIdentifier,
            title: String(localized: "Dismiss", comment: "Alarm dismiss action"),
            options: [.foreground, .destructive]
        )

        // "ALARM" — snooze-enabled alarms show both actions
        let alarmWithSnooze = UNNotificationCategory(
            identifier: "ALARM",
            actions: [snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        // "ALARM_NO_SNOOZE" — alarms with snooze disabled only show Dismiss
        let alarmNoSnooze = UNNotificationCategory(
            identifier: "ALARM_NO_SNOOZE",
            actions: [dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        // "WAKE_CHECK" — the post-mission "Still awake?" prompt. Tapping the body opens the
        // prompt; the action acknowledges without opening the app (AppContainer routes both).
        let awakeAction = UNNotificationAction(
            identifier: WakeCheckNotificationAction.awakeIdentifier,
            title: String(localized: "I'm awake", comment: "Wake check notification action"),
            options: []
        )
        let wakeCheck = UNNotificationCategory(
            identifier: WakeCheckNotificationAction.categoryIdentifier,
            actions: [awakeAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([alarmWithSnooze, alarmNoSnooze, wakeCheck])
    }
}
