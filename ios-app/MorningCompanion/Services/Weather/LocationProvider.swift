import CoreLocation
import Foundation

enum LocationProviderError: LocalizedError {
    case permissionDenied
    case restricted
    case unavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Location access is turned off for Dawnwick."
        case .restricted:
            return "Location access is restricted on this device."
        case .unavailable:
            return "Your current location could not be determined."
        case .timedOut:
            return "The location request timed out."
        }
    }
}

/// Core Location wrapper with one coalesced request shared by all callers.
///
/// Multiple Morning Brief refreshes — and multiple weather providers behind
/// `FallbackWeatherService` — may ask for a location at the same time. All callers
/// wait on the same CLLocationManager request instead of replacing one continuation.
@MainActor
final class LocationProvider: NSObject {
    private struct LocationWaiter {
        let continuation: CheckedContinuation<CLLocation, Error>
        let timeoutTask: Task<Void, Never>
    }

    private let manager: CLLocationManager
    private var authorizationWaiters: [CheckedContinuation<Void, Error>] = []
    private var locationWaiters: [UUID: LocationWaiter] = [:]
    private var isRequestingLocation = false

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Reads the status without prompting, so a screen can offer before it asks.
    var authorizationState: ContextualPermissionState {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .notDetermined:                          return .notDetermined
        default:                                      return .unavailable
        }
    }

    func requestAuthorization() async throws {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return
        case .denied:
            throw LocationProviderError.permissionDenied
        case .restricted:
            throw LocationProviderError.restricted
        case .notDetermined:
            try await withCheckedThrowingContinuation { continuation in
                authorizationWaiters.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        @unknown default:
            throw LocationProviderError.unavailable
        }
    }

    func currentLocation() async throws -> CLLocation {
        if let location = manager.location,
           location.horizontalAccuracy >= 0,
           Date().timeIntervalSince(location.timestamp) < 15 * 60 {
            return location
        }

        let waiterID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.timeoutLocationWaiter(id: waiterID)
            }
            locationWaiters[waiterID] = LocationWaiter(
                continuation: continuation,
                timeoutTask: timeoutTask
            )

            guard !isRequestingLocation else { return }
            isRequestingLocation = true
            manager.requestLocation()
        }
    }

    private func finishAuthorization(with result: Result<Void, Error>) {
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(with: result)
        }
    }

    private func finishLocation(with result: Result<CLLocation, Error>) {
        isRequestingLocation = false
        let waiters = locationWaiters.values
        locationWaiters.removeAll()
        for waiter in waiters {
            waiter.timeoutTask.cancel()
            waiter.continuation.resume(with: result)
        }
    }

    private func timeoutLocationWaiter(id: UUID) {
        guard let waiter = locationWaiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: LocationProviderError.timedOut)
        if locationWaiters.isEmpty {
            isRequestingLocation = false
        }
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                self.finishAuthorization(with: .success(()))
            case .denied:
                self.finishAuthorization(with: .failure(LocationProviderError.permissionDenied))
            case .restricted:
                self.finishAuthorization(with: .failure(LocationProviderError.restricted))
            case .notDetermined:
                break
            @unknown default:
                self.finishAuthorization(with: .failure(LocationProviderError.unavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations
            .filter { $0.horizontalAccuracy >= 0 }
            .max { $0.timestamp < $1.timestamp }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let location {
                self.finishLocation(with: .success(location))
            } else {
                self.finishLocation(with: .failure(LocationProviderError.unavailable))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let locationError = error as? CLError, locationError.code == .denied {
                self.finishLocation(with: .failure(LocationProviderError.permissionDenied))
            } else {
                self.finishLocation(with: .failure(LocationProviderError.unavailable))
            }
        }
    }
}
