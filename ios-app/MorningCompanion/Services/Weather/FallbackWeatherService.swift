import Foundation
import OSLog

/// Tries a primary weather provider, then falls back to a secondary one.
///
/// WeatherKit fails hard when the App ID's entitlement is not honoured by Apple's
/// auth service (`Failed to generate jwt token` / `Errors error 2`), which otherwise
/// leaves the Today screen showing "Unavailable" forever. The fallback keeps the
/// brief populated without an API key.
///
/// A persisted backoff (`WeatherPrimaryBackoffState`) suppresses the primary after
/// repeated failures so refreshes stop paying the `weatherd` round trip, and clears
/// on the first success so recovery is automatic.
@MainActor
final class FallbackWeatherService: WeatherServiceProtocol {
    private let primary: any WeatherServiceProtocol
    private let fallback: any WeatherServiceProtocol
    private let storage: (any StorageServiceProtocol)?
    private let now: () -> Date
    private let logger = Logger(subsystem: Log.subsystem, category: "Weather")

    init(
        primary: any WeatherServiceProtocol,
        fallback: any WeatherServiceProtocol,
        storage: (any StorageServiceProtocol)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.primary = primary
        self.fallback = fallback
        self.storage = storage
        self.now = now
    }

    /// Both providers share the same Core Location permission, so authorizing the
    /// primary is enough — and a denial must still surface to the caller.
    /// Both providers resolve the same location, so the primary's answer is the answer.
    func authorizationState() async -> ContextualPermissionState {
        await primary.authorizationState()
    }

    func requestAuthorization() async throws {
        try await primary.requestAuthorization()
    }

    func currentConditions() async throws -> WeatherConditions? {
        let state = loadState()

        if state.isSuppressed(at: now()) {
            let remaining = state.suppressedUntil.map { Int($0.timeIntervalSince(now())) } ?? 0
            logger.info("Skipping primary weather provider; backoff for \(remaining)s")
            // Fallback still resolves location, so LocationProviderError still surfaces.
            return try await fallback.currentConditions()
        }

        do {
            if let conditions = try await primary.currentConditions() {
                if state != .clear { persist(.clear) }   // self-heal, immediate
                return conditions
            }
            // A nil (unusable) response also earns backoff, else a silently-empty
            // primary would be retried on every refresh forever.
            logger.warning("Primary weather provider returned no conditions; using fallback")
            persist(state.recordingFailure(at: now()))
        } catch let error as LocationProviderError {
            // A location failure would defeat the fallback too, and must not poison
            // the WeatherKit backoff — report it as-is without touching state.
            throw error
        } catch {
            logger.warning(
                "Primary weather provider failed (\(error.localizedDescription, privacy: .public)); using fallback"
            )
            logger.debug("Primary weather failure detail: \(String(reflecting: error), privacy: .public)")
            persist(state.recordingFailure(at: now()))
        }

        return try await fallback.currentConditions()
    }

    private func loadState() -> WeatherPrimaryBackoffState {
        let stored: WeatherPrimaryBackoffState? = try? storage?.load(key: StorageKeys.weatherPrimaryBackoff)
        return (stored ?? .clear).sanitized(at: now())
    }

    private func persist(_ state: WeatherPrimaryBackoffState) {
        // A storage failure degrades to today's behaviour (always try primary),
        // never breaks the fetch.
        try? storage?.save(state, key: StorageKeys.weatherPrimaryBackoff)
    }
}
