import Foundation
import AlarmKit

/// App-level mirror of `AlarmKit.AlarmManager.AuthorizationState` so views can
/// observe it without importing AlarmKit.
enum AlarmKitAuthorizationState: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case unknown

    init(_ state: AlarmKit.AlarmManager.AuthorizationState) {
        switch state {
        case .notDetermined: self = .notDetermined
        case .denied:        self = .denied
        case .authorized:    self = .authorized
        @unknown default:    self = .unknown
        }
    }

    /// True when the system alarm path (Focus / ringer-switch override) is usable.
    var isAuthorized: Bool { self == .authorized }

    var displayName: String {
        switch self {
        case .notDetermined: return String(localized: "Not requested", comment: "AlarmKit permission state")
        case .denied:        return String(localized: "Off", comment: "AlarmKit permission state")
        case .authorized:    return String(localized: "On", comment: "AlarmKit permission state")
        case .unknown:       return String(localized: "Unknown", comment: "AlarmKit permission state")
        }
    }
}
