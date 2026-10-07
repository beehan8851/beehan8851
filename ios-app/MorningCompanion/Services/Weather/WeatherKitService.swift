import CoreLocation
import Foundation
import OSLog
import WeatherKit

enum WeatherKitServiceError: LocalizedError {
    case weatherRequestFailed(any Error)

    var errorDescription: String? {
        switch self {
        case .weatherRequestFailed(let error):
            return "WeatherKit request failed: \(error.localizedDescription)"
        }
    }
}

/// WeatherKit adapter. Location resolution lives in `LocationProvider` so the
/// fallback provider can share the same coalesced Core Location request.
@MainActor
final class WeatherKitService: WeatherServiceProtocol {
    private let service: WeatherService
    private let locationProvider: LocationProvider
    private let placeNameResolver: PlaceNameResolver

    init(
        service: WeatherService = .shared,
        locationProvider: LocationProvider,
        placeNameResolver: PlaceNameResolver
    ) {
        self.service = service
        self.locationProvider = locationProvider
        self.placeNameResolver = placeNameResolver
    }

    func authorizationState() async -> ContextualPermissionState {
        await locationProvider.authorizationState
    }

    func requestAuthorization() async throws {
        try await locationProvider.requestAuthorization()
    }

    func currentConditions() async throws -> WeatherConditions? {
        try await requestAuthorization()
        let location = try await locationProvider.currentLocation()
        // Coordinates are personal data: `.private` keeps them out of collected logs
        // and out of any sysdiagnose the user might send to someone else.
        Log.services.debug("""
            Weather location \(location.coordinate.latitude, privacy: .private), \
            \(location.coordinate.longitude, privacy: .private) \
            accuracy=\(location.horizontalAccuracy)m
            """)

        do {
            let weather = try await service.weather(for: location)
            Log.services.debug("WeatherKit current \(weather.currentWeather.temperature.converted(to: .celsius).value)°C")
            let current = weather.currentWeather
            let today = weather.dailyForecast.first
            let celsius = UnitTemperature.celsius
            let currentTemperature = current.temperature.converted(to: celsius).value

            // hourlyForecast begins at the start of the current day, so drop past hours.
            let cutoff = Date().addingTimeInterval(-30 * 60)
            let hourly = weather.hourlyForecast
                .filter { $0.date >= cutoff }
                .prefix(24)
                .map { hour in
                    HourlyForecastPoint(
                        date: hour.date,
                        temperature: hour.temperature.converted(to: celsius).value,
                        symbolName: hour.symbolName,
                        precipitationChance: hour.precipitationChance
                    )
                }

            let placeName = await placeNameResolver.placeName(for: location)

            return WeatherConditions(
                temperature: currentTemperature,
                high: today?.highTemperature.converted(to: celsius).value ?? currentTemperature,
                low: today?.lowTemperature.converted(to: celsius).value ?? currentTemperature,
                symbolName: current.symbolName,
                description: current.condition.description,
                precipitationChance: today?.precipitationChance ?? 0,
                humidity: current.humidity,
                windSpeed: current.wind.speed.converted(to: .kilometersPerHour).value,
                hourly: Array(hourly),
                placeName: placeName,
                source: .weatherKit,
                capturedAt: Date()
            )
        } catch {
            Log.services.debug("WeatherKit request failed: \(String(reflecting: error), privacy: .public)")
            throw WeatherKitServiceError.weatherRequestFailed(error)
        }
    }
}
