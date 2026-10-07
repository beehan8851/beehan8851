import Foundation
import os
import Observation
import UserNotifications

/// State for the three onboarding steps.
///
/// Holds the permission results and the first alarm the user builds, so the view stays
/// a rendering of this and the flow can be tested without one.
@MainActor
@Observable
final class OnboardingModel {

    enum Step: Int, CaseIterable, Comparable {
        case welcome, permissions, firstAlarm

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// What the user is looking at, and what a permission has settled on.
    private(set) var step: Step = .welcome
    private(set) var alarmAuthorization: AlarmKitAuthorizationState = .notDetermined
    private(set) var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    private(set) var isRequestingPermissions = false
    private(set) var isSavingAlarm = false
    private(set) var alarmSaveError: String?

    /// The first alarm. 7:00 is a default, not a recommendation — the picker is right
    /// there, and an alarm the user actually chose is one they will trust.
    var wakeTime = AlarmTime(hour: 7, minute: 0)
    /// Which mission the first alarm gets. Not optional: `AlarmManager.validate`
    /// rejects an alarm with no mission, so "just dismiss" is not a thing this app can
    /// save. Both choices offered are free-tier.
    var mission: MissionKind = .math

    private let permissions: any OnboardingPermissionsProviding

    /// `nonisolated` so a view can construct one in a default argument, which Swift
    /// evaluates outside the main actor even when every caller is on it.
    nonisolated init(permissions: any OnboardingPermissionsProviding = SystemOnboardingPermissions()) {
        self.permissions = permissions
    }

    // MARK: - Derived state

    /// Whether the alarm can actually ring. Notifications are wanted but not fatal:
    /// without them the user loses wake checks and snooze reminders, not the alarm.
    var canAlarmsRing: Bool { alarmAuthorization == .authorized }

    var hasDecidedAlarmPermission: Bool { alarmAuthorization != .notDetermined }

    var isAnyPermissionDenied: Bool {
        alarmAuthorization == .denied || notificationAuthorization == .denied
    }

    /// True once asking again would do nothing, because iOS only prompts once.
    /// From here the only way forward is the Settings app.
    var permissionsAreSettled: Bool {
        hasDecidedAlarmPermission && notificationAuthorization != .notDetermined
    }

    var isLastStep: Bool { step == .firstAlarm }

    // MARK: - Navigation

    func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func go(to step: Step) {
        self.step = step
    }

    // MARK: - Permissions

    func refreshPermissions() async {
        alarmAuthorization = await permissions.alarmAuthorization()
        notificationAuthorization = await permissions.notificationAuthorization()
    }

    /// Asks for both, in the order they matter.
    ///
    /// Alarms first: it is the one the app cannot work without, and asking for it while
    /// the user is still reading about alarms is the whole point of a priming screen.
    /// Notifications follow immediately — two prompts back to back are read as one
    /// step, where a prompt arriving later feels like a second demand.
    func requestPermissions() async {
        guard !isRequestingPermissions else { return }
        isRequestingPermissions = true
        defer { isRequestingPermissions = false }

        alarmAuthorization = await permissions.requestAlarmAuthorization()
        notificationAuthorization = await permissions.requestNotificationAuthorization()
    }

    // MARK: - First alarm

    var firstAlarm: Alarm {
        Alarm(
            label: String(localized: "Wake up", comment: "Default label for the alarm created during onboarding"),
            wallClockTime: wakeTime,
            recurrence: .daily,
            missions: [mission.onboardingConfig],
            isEnabled: true
        )
    }

    /// Saves the first alarm. Returns whether onboarding may finish: a validation or
    /// storage failure keeps the user here with the reason, because silently dropping
    /// the alarm they just set is how an alarm app loses someone on day one.
    func saveFirstAlarm(using manager: AlarmManager) async -> Bool {
        guard !isSavingAlarm else { return false }
        isSavingAlarm = true
        defer { isSavingAlarm = false }
        alarmSaveError = nil

        switch await manager.save(firstAlarm) {
        case .success:
            return true
        case .partialSuccess(_, let schedulingError):
            // The alarm is stored; only the system scheduling failed, which the alarm
            // list surfaces and a later reconcile retries. Not worth blocking here.
            Log.alarm.error("First alarm saved but not scheduled: \(schedulingError.localizedDescription, privacy: .public)")
            return true
        case .failure(let error):
            alarmSaveError = error.localizedDescription
            return false
        case .deleted:
            // save() never reports a deletion; treated as done rather than stranding
            // the user on a screen with nothing left to do.
            return true
        }
    }
}

// MARK: - Missions offered during onboarding

extension MissionKind {
    /// The configuration onboarding creates for a mission the user picks.
    /// Deliberately the gentlest setting of each — the first morning is not the place
    /// to discover that you signed up for twelve rounds of arithmetic.
    var onboardingConfig: MissionConfig {
        switch self {
        case .shake: return .shake(targetCount: 15)
        default:     return .math(difficulty: .easy, rounds: 1)
        }
    }

    /// One line on what the mission asks of you, shown under the choice.
    var onboardingDescription: String {
        switch self {
        case .shake:
            return String(localized: "Shake the phone until you're properly awake.", comment: "Shake mission description in onboarding")
        default:
            return String(localized: "Solve one easy sum before the alarm stops.", comment: "Math mission description in onboarding")
        }
    }
}
