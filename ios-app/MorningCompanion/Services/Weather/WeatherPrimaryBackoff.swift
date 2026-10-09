import Foundation

/// Pure, persistable backoff state for the primary weather provider.
///
/// When WeatherKit's auth backend is broken, every refresh otherwise pays a full
/// `weatherd` round trip before falling through to Open-Meteo. After a few consecutive
/// failures this suppresses the primary for a growing window, and any success clears it
/// immediately so the app self-heals the moment Apple's backend recovers.
///
/// No storage, no side effects — all transitions are pure functions, so this is trivially
/// testable once a test target exists.
struct WeatherPrimaryBackoffState: Codable, Equatable {
    var consecutiveFailures: Int = 0
    var suppressedUntil: Date?
    var lastFailureAt: Date?

    static let clear = WeatherPrimaryBackoffState()

    /// The first two failures are free — a transient network blip must not suppress
    /// WeatherKit. Suppression starts at the 3rd consecutive failure.
    static let failureThreshold = 3

    /// 15 min → 1 h → 6 h, capped. Index = consecutiveFailures - failureThreshold.
    static let delays: [TimeInterval] = [15 * 60, 60 * 60, 6 * 60 * 60]

    /// Longest window we'd ever legitimately suppress for; used to sanitize a
    /// forward-dated `suppressedUntil` after a device clock change.
    static let maxWindow: TimeInterval = 6 * 60 * 60

    func isSuppressed(at date: Date) -> Bool {
        guard let suppressedUntil else { return false }
        return date < suppressedUntil
    }

    func recordingFailure(at date: Date) -> WeatherPrimaryBackoffState {
        let failures = consecutiveFailures + 1
        guard failures >= Self.failureThreshold else {
            return WeatherPrimaryBackoffState(
                consecutiveFailures: failures,
                suppressedUntil: nil,
                lastFailureAt: date
            )
        }
        let index = min(failures - Self.failureThreshold, Self.delays.count - 1)
        return WeatherPrimaryBackoffState(
            consecutiveFailures: failures,
            suppressedUntil: date.addingTimeInterval(Self.delays[index]),
            lastFailureAt: date
        )
    }

    /// Guards against a corrupt or clock-skewed persisted value parking the window
    /// impossibly far in the future.
    func sanitized(at date: Date) -> WeatherPrimaryBackoffState {
        if let suppressedUntil, suppressedUntil.timeIntervalSince(date) > Self.maxWindow {
            return .clear
        }
        return self
    }
}
