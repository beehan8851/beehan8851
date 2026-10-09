import Foundation

enum HealthKitAuthorizationState: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

enum HealthKitServiceError: LocalizedError {
    case healthDataUnavailable
    case authorizationDenied
    case sleepTypeUnavailable
    case queryFailed(underlying: any Error)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return String(localized: "Health data is not available on this device.", comment: "HealthKit unavailable error")
        case .authorizationDenied:
            return String(localized: "Sleep access was not granted.", comment: "HealthKit permission denied error")
        case .sleepTypeUnavailable:
            return String(localized: "Sleep data is not supported on this device.", comment: "HealthKit sleep type error")
        case .queryFailed(let error):
            return String(localized: "Sleep data could not be loaded: \(error.localizedDescription)", comment: "HealthKit query error")
        }
    }
}

struct SleepEntry: Identifiable, Sendable, Equatable {
    let date: Date
    let duration: TimeInterval
    let inBedDuration: TimeInterval

    var id: Date { date }
}

protocol HealthKitServiceProtocol {
    func authorizationState() async -> HealthKitAuthorizationState
    func requestAuthorization() async throws
    func lastNightSleepDuration() async throws -> TimeInterval?
    func sleepHistory(days: Int) async throws -> [SleepEntry]
}

/// Preview and test implementation. It intentionally returns no health data.
final class StubHealthKitService: HealthKitServiceProtocol {
    func authorizationState() async -> HealthKitAuthorizationState { .authorized }
    func requestAuthorization() async throws {}
    func lastNightSleepDuration() async throws -> TimeInterval? { nil }
    func sleepHistory(days: Int) async throws -> [SleepEntry] { [] }
}
