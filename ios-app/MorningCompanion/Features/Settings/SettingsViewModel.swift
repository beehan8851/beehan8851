import Foundation
import Observation
import UserNotifications

enum NotificationPermissionState: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    var displayName: String {
        switch self {
        case .notDetermined: return String(localized: "Not requested", comment: "Notification permission state")
        case .denied: return String(localized: "Off", comment: "Notification permission state")
        case .authorized: return String(localized: "On", comment: "Notification permission state")
        case .provisional: return String(localized: "Provisional", comment: "Notification permission state")
        case .ephemeral: return String(localized: "Temporary", comment: "Notification permission state")
        case .unknown: return String(localized: "Unknown", comment: "Notification permission state")
        }
    }
}

@MainActor
@Observable
final class SettingsViewModel {
    var notificationStatus: NotificationPermissionState = .unknown
    var healthStatus: HealthKitAuthorizationState = .notDetermined
    var isLoadingStatuses = false

    private let notificationCenter: UNUserNotificationCenter
    private let healthKitService: any HealthKitServiceProtocol

    init(
        notificationCenter: UNUserNotificationCenter = .current(),
        healthKitService: any HealthKitServiceProtocol
    ) {
        self.notificationCenter = notificationCenter
        self.healthKitService = healthKitService
    }

    func loadStatuses() async {
        isLoadingStatuses = true
        defer { isLoadingStatuses = false }

        let notificationSettings = await notificationCenter.notificationSettings()
        notificationStatus = NotificationPermissionState(notificationSettings.authorizationStatus)
        healthStatus = await healthKitService.authorizationState()
    }
}

private extension NotificationPermissionState {
    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized: self = .authorized
        case .provisional: self = .provisional
        case .ephemeral: self = .ephemeral
        @unknown default: self = .unknown
        }
    }
}

extension HealthKitAuthorizationState {
    var settingsDisplayName: String {
        switch self {
        case .notDetermined: return String(localized: "Not connected", comment: "HealthKit connection state")
        case .authorized: return String(localized: "Connected", comment: "HealthKit connection state")
        case .denied: return String(localized: "Off", comment: "HealthKit connection state")
        case .unavailable: return String(localized: "Unavailable", comment: "HealthKit connection state")
        }
    }
}
