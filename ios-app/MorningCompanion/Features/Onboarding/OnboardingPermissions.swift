import AlarmKit
import Foundation
import os
import UserNotifications

/// The two permissions an alarm cannot work without, behind a protocol so the
/// onboarding flow can be exercised without a device that has real ones.
///
/// Both are asked for in onboarding rather than at launch: a permission dialog with
/// no explanation in front of it is the single most expensive mistake an alarm app can
/// make — a "Don't Allow" here is unrecoverable in-app, and the user finds out at 7am.
protocol OnboardingPermissionsProviding: Sendable {
    func alarmAuthorization() async -> AlarmKitAuthorizationState
    /// Presents the system prompt when the state is `.notDetermined`; returns the
    /// state afterwards either way.
    func requestAlarmAuthorization() async -> AlarmKitAuthorizationState

    func notificationAuthorization() async -> UNAuthorizationStatus
    func requestNotificationAuthorization() async -> UNAuthorizationStatus
}

struct SystemOnboardingPermissions: OnboardingPermissionsProviding {
    private var manager: AlarmKit.AlarmManager { .shared }
    private var center: UNUserNotificationCenter { .current() }

    func alarmAuthorization() async -> AlarmKitAuthorizationState {
        AlarmKitAuthorizationState(manager.authorizationState)
    }

    func requestAlarmAuthorization() async -> AlarmKitAuthorizationState {
        guard manager.authorizationState == .notDetermined else {
            return AlarmKitAuthorizationState(manager.authorizationState)
        }
        do {
            return AlarmKitAuthorizationState(try await manager.requestAuthorization())
        } catch {
            Log.alarm.error("AlarmKit authorization request failed: \(String(describing: error), privacy: .public)")
            return AlarmKitAuthorizationState(manager.authorizationState)
        }
    }

    func notificationAuthorization() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestNotificationAuthorization() async -> UNAuthorizationStatus {
        // A second request after a decision is a no-op in iOS, not a second prompt,
        // so this is safe to call without checking the state first.
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Log.alarm.error("Notification authorization request failed: \(String(describing: error), privacy: .public)")
        }
        return await notificationAuthorization()
    }
}

/// Previews and tests. Starts undecided and grants whatever it is told to grant.
struct StubOnboardingPermissions: OnboardingPermissionsProviding {
    final class State: @unchecked Sendable {
        var alarm: AlarmKitAuthorizationState
        var notifications: UNAuthorizationStatus
        /// What a request resolves to, so a denial can be exercised too.
        var alarmOnRequest: AlarmKitAuthorizationState
        var notificationsOnRequest: UNAuthorizationStatus

        init(
            alarm: AlarmKitAuthorizationState = .notDetermined,
            notifications: UNAuthorizationStatus = .notDetermined,
            alarmOnRequest: AlarmKitAuthorizationState = .authorized,
            notificationsOnRequest: UNAuthorizationStatus = .authorized
        ) {
            self.alarm = alarm
            self.notifications = notifications
            self.alarmOnRequest = alarmOnRequest
            self.notificationsOnRequest = notificationsOnRequest
        }
    }

    let state: State

    init(state: State = State()) { self.state = state }

    func alarmAuthorization() async -> AlarmKitAuthorizationState { state.alarm }

    func requestAlarmAuthorization() async -> AlarmKitAuthorizationState {
        if state.alarm == .notDetermined { state.alarm = state.alarmOnRequest }
        return state.alarm
    }

    func notificationAuthorization() async -> UNAuthorizationStatus { state.notifications }

    func requestNotificationAuthorization() async -> UNAuthorizationStatus {
        if state.notifications == .notDetermined { state.notifications = state.notificationsOnRequest }
        return state.notifications
    }
}
