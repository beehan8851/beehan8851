import CoreLocation
import Foundation
import MapKit

/// Resolves a human-readable place name for a location, with a distance/age cache so
/// the rate-limited geocoder is hit at most a few times a day.
///
/// Uses `MKReverseGeocodingRequest`; `CLGeocoder` was deprecated in iOS 26, which is
/// this app's floor, so there is no reason to carry the old one.
///
/// Deliberately separate from `LocationProvider`: that type is a pure Core Location
/// wrapper with delicate continuation-coalescing, while reverse geocoding is a display
/// concern with a different failure and rate-limit profile. The in-flight task below
/// does the coalescing that `CLGeocoder`'s per-instance serialisation used to.
@MainActor
final class PlaceNameResolver {
    struct CachedPlace: Codable {
        var name: String
        var latitude: Double
        var longitude: Double
        var resolvedAt: Date
    }

    private let storage: (any StorageServiceProtocol)?
    private let now: () -> Date
    private var cached: CachedPlace?
    private var hydrated = false
    private var inFlight: Task<String?, Never>?

    private let maxDistance: CLLocationDistance = 5_000   // metres
    private let maxAge: TimeInterval = 6 * 60 * 60        // 6 hours

    init(storage: (any StorageServiceProtocol)? = nil, now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.now = now
    }

    /// Never throws — a geocoding failure must never fail a weather fetch.
    func placeName(for location: CLLocation) async -> String? {
        hydrateIfNeeded()

        if let cached, isFresh(cached, for: location) {
            return cached.name
        }

        if let inFlight {
            return await inFlight.value
        }

        let task = Task { [weak self] () -> String? in
            guard let self else { return nil }
            defer { self.inFlight = nil }
            return await self.resolve(location)
        }
        inFlight = task
        return await task.value
    }

    private func resolve(_ location: CLLocation) async -> String? {
        guard let name = await Self.cityName(near: location) else {
            // Rate-limit or empty result — keep showing the last known name.
            return cached?.name
        }

        let place = CachedPlace(
            name: name,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            resolvedAt: now()
        )
        cached = place
        try? storage?.save(place, key: StorageKeys.weatherPlaceName)
        return name
    }

    /// The city, named the way a person would say it. Never throws: a geocoding
    /// failure has to leave the weather fetch alone.
    ///
    /// `.automatic` adds the country only when it differs from the device's own
    /// region — "Tashkent" at home, "Paris, France" while travelling, which is what
    /// someone glancing at a weather card wants either way.
    private static func cityName(near location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        let items = (try? await request.mapItems) ?? []
        return items.lazy
            .compactMap { $0.addressRepresentations?.cityWithContext(.automatic) }
            .first { !$0.isEmpty }
    }

    private func isFresh(_ place: CachedPlace, for location: CLLocation) -> Bool {
        guard now().timeIntervalSince(place.resolvedAt) < maxAge else { return false }
        let cachedLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
        return cachedLocation.distance(from: location) < maxDistance
    }

    private func hydrateIfNeeded() {
        guard !hydrated else { return }
        hydrated = true
        cached = try? storage?.load(key: StorageKeys.weatherPlaceName)
    }
}
