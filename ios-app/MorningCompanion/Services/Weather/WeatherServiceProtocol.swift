import Foundation

protocol WeatherServiceProtocol {
    /// The location permission's state, read without prompting.
    func authorizationState() async -> ContextualPermissionState
    func requestAuthorization() async throws
    func currentConditions() async throws -> WeatherConditions?
}

/// Which backend produced a `WeatherConditions` value. Drives the required
/// attribution footer on the detail screen.
enum WeatherSource: String, Codable, Sendable {
    case weatherKit
    case openMeteo
    case stub
}

struct HourlyForecastPoint: Codable, Sendable, Equatable, Identifiable {
    let date: Date
    let temperature: Double          // Celsius
    let symbolName: String           // SF Symbol
    let precipitationChance: Double  // 0...1

    var id: Date { date }            // computed → not encoded
}

struct WeatherConditions: Codable, Sendable, Equatable {
    // Existing fields — names and types unchanged so legacy cached JSON still decodes.
    let temperature: Double
    let high: Double
    let low: Double
    let symbolName: String
    let description: String
    let precipitationChance: Double

    // New fields — all optional so pre-upgrade cache payloads decode to nil
    // (synthesized Codable emits decodeIfPresent for Optionals).
    let humidity: Double?            // 0...1 fraction (NOT percent)
    let windSpeed: Double?           // km/h
    let hourly: [HourlyForecastPoint]?
    let placeName: String?
    let source: WeatherSource?
    let capturedAt: Date?

    init(
        temperature: Double,
        high: Double,
        low: Double,
        symbolName: String,
        description: String,
        precipitationChance: Double,
        humidity: Double? = nil,
        windSpeed: Double? = nil,
        hourly: [HourlyForecastPoint]? = nil,
        placeName: String? = nil,
        source: WeatherSource? = nil,
        capturedAt: Date? = nil
    ) {
        self.temperature = temperature
        self.high = high
        self.low = low
        self.symbolName = symbolName
        self.description = description
        self.precipitationChance = precipitationChance
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.hourly = hourly
        self.placeName = placeName
        self.source = source
        self.capturedAt = capturedAt
    }
}

/// Preview stub — returns realistic sample data including an hourly strip.
final class StubWeatherService: WeatherServiceProtocol {
    func authorizationState() async -> ContextualPermissionState { .granted }
    func requestAuthorization() async throws {}
    func currentConditions() async throws -> WeatherConditions? {
        let base = Date()
        let symbols = ["sun.max.fill", "cloud.sun.fill", "cloud.fill", "cloud.drizzle.fill"]
        let hourly = (0..<12).map { index -> HourlyForecastPoint in
            HourlyForecastPoint(
                date: base.addingTimeInterval(TimeInterval(index) * 3600),
                temperature: 18 - Double(index % 5),
                symbolName: symbols[index % symbols.count],
                precipitationChance: index % 4 == 0 ? 0.3 : 0.05
            )
        }
        return WeatherConditions(
            temperature: 18,
            high: 22,
            low: 13,
            symbolName: "cloud.sun.fill",
            description: "Partly Cloudy",
            precipitationChance: 0.2,
            humidity: 0.48,
            windSpeed: 9,
            hourly: hourly,
            placeName: "Cupertino",
            source: .stub,
            capturedAt: base
        )
    }
}
