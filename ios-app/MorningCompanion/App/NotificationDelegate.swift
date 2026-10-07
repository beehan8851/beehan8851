import Foundation
import UserNotifications

// MARK: - Notification action enum

/// Describes what the user did with an alarm notification.
enum AlarmNotificationAction {
    /// User tapped the notification (default action) — show the ring screen.
    case `default`
    /// User triggered the "Snooze" action from the lock screen.
    case snooze
    /// User triggered the "Dismiss" action from the lock screen.
    case dismiss
}

// Notification action identifiers (must match AlarmNotificationService)
extension AlarmNotificationAction {
    static let snoozeIdentifier  = "SNOOZE_ALARM"
    static let dismissIdentifier = "DISMISS_ALARM"
}

/// What the user did with the post-mission "Still awake?" notification.
enum WakeCheckNotificationAction {
    /// Tapped the notification body — open the app and show the prompt.
    case open
    /// Tapped the "I'm awake" action — acknowledge without opening the app.
    case awake

    static let categoryIdentifier = "WAKE_CHECK"
    static let awakeIdentifier    = "WAKE_CHECK_AWAKE"
    static let requestIdentifier  = "wakecheck"
}

// MARK: - Delegate

/// UNUserNotificationCenterDelegate retained by AppContainer.
///
/// Forwards alarm events to AppContainer via `onAlarmAction` so that
/// the ring screen can be presented or snooze can be scheduled
/// without making the delegate depend on AppContainer directly.
///
/// UNUserNotificationCenter.delegate is weak — AppContainer must
/// hold a strong reference to this object for the app's lifetime.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    /// Called when an alarm notification fires or is acted on.
    /// Runs on an arbitrary thread — callers must dispatch to main as needed.
    var onAlarmAction: ((String, AlarmNotificationAction) async -> Void)?

    /// Called when the wake-check notification is tapped or its action is used.
    var onWakeCheckAction: ((WakeCheckNotificationAction) async -> Void)?

    /// Called when the bedtime reminder is tapped.
    var onBedtimeReminder: (() async -> Void)?

    /// Must match `SleepViewModel`'s reminder request identifier.
    static let bedtimeReminderIdentifier = "com.morningcompanion.sleep.bedtimeReminder"

    // MARK: - Foreground presentation

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        if let alarmID = content.userInfo["alarmID"] as? String {
            // Alarm notification while app is foregrounded — show ring screen instead of banner
            Task {
                await onAlarmAction?(alarmID, .default)
                completionHandler([.sound, .badge])
            }
        } else if content.categoryIdentifier == WakeCheckNotificationAction.categoryIdentifier {
            // Foreground: the in-app timer already presents the prompt; play the sound only.
            Task {
                await onWakeCheckAction?(.open)
                completionHandler([.sound])
            }
        } else {
            // Non-alarm notification (debug, system) — show the banner
            completionHandler([.banner, .sound, .badge])
        }
    }

    // MARK: - Response handling

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task {
            let content = response.notification.request.content
            if let alarmID = content.userInfo["alarmID"] as? String {
                switch response.actionIdentifier {
                case AlarmNotificationAction.snoozeIdentifier:
                    await onAlarmAction?(alarmID, .snooze)
                case AlarmNotificationAction.dismissIdentifier:
                    await onAlarmAction?(alarmID, .dismiss)
                default:
                    await onAlarmAction?(alarmID, .default)
                }
            } else if content.categoryIdentifier == WakeCheckNotificationAction.categoryIdentifier {
                switch response.actionIdentifier {
                case WakeCheckNotificationAction.awakeIdentifier:
                    await onWakeCheckAction?(.awake)
                case UNNotificationDismissActionIdentifier:
                    break   // swiped away: the auto-fail re-arm stays armed
                default:
                    await onWakeCheckAction?(.open)
                }
            } else if response.notification.request.identifier == Self.bedtimeReminderIdentifier,
                      response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                await onBedtimeReminder?()
            }
            completionHandler()
        }
    }
}
