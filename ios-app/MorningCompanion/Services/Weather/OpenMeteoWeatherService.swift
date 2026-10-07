import CoreLocation
import Foundation
import OSLog

enum OpenMeteoServiceError: LocalizedError {
    case badResponse(Int)
    case requestFailed(any Error)

    var errorDescription: String? {
        switch self {
        case .badResponse(let status):
            return "Weather service returned HTTP \(status)."
        case .requestFailed(let error):
            return "Weather request failed: \(error.localizedDescription)"
        }
    }
}

/// Keyless weather provider used when WeatherKit is unavailable.
///
/// Open-Meteo needs no API key or account, so this keeps the Today screen populated
/// while a WeatherKit entitlement/provisioning problem is being resolved.
@MainActor
final class OpenMeteoWeatherService: WeatherServiceProtocol {
    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature2m: Double
            let weatherCode: Int
            let isDay: Int
            let relativeHumidity2m: Int?
            let windSpeed10m: Double?

            enum CodingKeys: String, CodingKey {
                case temperature2m = "temperature_2m"
                case weatherCode = "weather_code"
                case isDay = "is_day"
                case relativeHumidity2m = "relative_humidity_2m"
                case windSpeed10m = "wind_speed_10m"
            }
        }

        struct Hourly: Decodable {
            let time: [Int]
            let temperature2m: [Double?]
            let weatherCode: [Int?]
            let precipitationProbability: [Int?]?
            let isDay: [Int?]?

            enum CodingKeys: String, CodingKey {
                case time
                case temperature2m = "temperature_2m"
                case weatherCode = "weather_code"
                case precipitationProbability = "precipitation_probability"
                case isDay = "is_day"
            }
        }

        struct Daily: Decodable {
            let temperature2mMax: [Double?]
            let temperature2mMin: [Double?]
            let precipitationProbabilityMax: [Int?]?

            enum CodingKeys: String, CodingKey {
                case temperature2mMax = "temperature_2m_max"
                case temperature2mMin = "temperature_2m_min"
                case precipitationProbabilityMax = "precipitation_probability_max"
            }
        }

        let current: Current
        let hourly: Hourly?
        let daily: Daily?
    }

    private let locationProvider: LocationProvider
    private let placeNameResolver: PlaceNameResolver
    private let session: URLSession

    init(
        locationProvider: LocationProvider,
        placeNameResolver: PlaceNameResolver,
        session: URLSession = .shared
    ) {
        self.locationProvider = locationProvider
        self.placeNameResolver = placeNameResolver
        self.session = session
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
        let response = try await fetch(for: location.coordinate)

        let current = response.current
        let currentTemperature = current.temperature2m
        let isDay = current.isDay == 1

        let hourly = Self.hourlyPoints(from: response.hourly)
        let placeName = await placeNameResolver.placeName(for: location)

        return WeatherConditions(
            temperature: currentTemperature,
            high: response.daily?.temperature2mMax.first.flatMap { $0 } ?? currentTemperature,
            low: response.daily?.temperature2mMin.first.flatMap { $0 } ?? currentTemperature,
            symbolName: Self.symbolName(forWMOCode: current.weatherCode, isDay: isDay),
            description: Self.description(forWMOCode: current.weatherCode),
            precipitationChance: response.daily?.precipitationProbabilityMax?.first
                .flatMap { $0 }
                .map { Double($0) / 100 } ?? 0,
            humidity: current.relativeHumidity2m.map { Double($0) / 100 },
            windSpeed: current.windSpeed10m,
            hourly: hourly,
            placeName: placeName,
            source: .openMeteo,
            capturedAt: Date()
        )
    }

    /// Zips Open-Meteo's parallel hourly arrays by index, defending against short or
    /// mismatched arrays, and drops past hours.
    private static func hourlyPoints(from hourly: Response.Hourly?) -> [HourlyForecastPoint]? {
        guard let hourly else { return nil }
        let cutoff = Date().addingTimeInterval(-30 * 60)

        let points: [HourlyForecastPoint] = hourly.time.indices.compactMap { index in
            let date = Date(timeIntervalSince1970: TimeInterval(hourly.time[index]))
            guard date >= cutoff,
                  let temperature = hourly.temperature2m[safe: index] ?? nil,
                  let code = hourly.weatherCode[safe: index] ?? nil
            else { return nil }

            let isDay = (hourly.isDay?[safe: index] ?? nil) != 0
            let precipitation = (hourly.precipitationProbability?[safe: index] ?? nil)
                .map { Double($0) / 100 } ?? 0

            return HourlyForecastPoint(
                date: date,
                temperature: temperature,
                symbolName: symbolName(forWMOCode: code, isDay: isDay),
                precipitationChance: precipitation
            )
        }

        let trimmed = Array(points.prefix(24))
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fetch(for coordinate: CLLocationCoordinate2D) async throws -> Response {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,weather_code,is_day,relative_humidity_2m,wind_speed_10m"
            ),
            URLQueryItem(
                name: "hourly",
                value: "temperature_2m,weather_code,precipitation_probability,is_day"
            ),
            URLQueryItem(
                name: "daily",
                value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"
            ),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
            // Absolute seconds — avoids ISO8601 misparsing the offset-less local
            // times that timezone=auto otherwise returns.
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15

        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: request)
        } catch {
            Log.services.debug("Open-Meteo transport error: \(String(reflecting: error), privacy: .public)")
            throw OpenMeteoServiceError.requestFailed(error)
        }

        if let http = urlResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OpenMeteoServiceError.badResponse(http.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            Log.services.debug("Open-Meteo current \(decoded.current.temperature2m)°C code=\(decoded.current.weatherCode)")
            return decoded
        } catch {
            throw OpenMeteoServiceError.requestFailed(error)
        }
    }

    // MARK: - WMO weather code mapping
    //
    // https://open-meteo.com/en/docs — the `weather_code` field uses WMO 4677.
    // Symbols are chosen to match the SF Symbol names WeatherKit returns, so the
    // Today screen renders identically whichever provider answered.

    static func symbolName(forWMOCode code: Int, isDay: Bool) -> String {
        switch code {
        case 0:
            return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1:
            return isDay ? "sun.max.fill" : "moon.fill"
        case 2:
            return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:
            return "cloud.fill"
        case 45, 48:
            return "cloud.fog.fill"
        case 51, 53, 55:
            return "cloud.drizzle.fill"
        case 56, 57, 66, 67:
            return "cloud.sleet.fill"
        case 61, 63:
            return "cloud.rain.fill"
        case 65:
            return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86:
            return "cloud.snow.fill"
        case 80, 81:
            return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 82:
            return "cloud.heavyrain.fill"
        case 95, 96, 99:
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }

    static func description(forWMOCode code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73: return "Snow"
        case 75: return "Heavy Snow"
        case 77: return "Snow Grains"
        case 80, 81: return "Rain Showers"
        case 82: return "Heavy Rain Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorms"
        case 96, 99: return "Thunderstorms with Hail"
        default: return "Unknown"
        }
    }
}

private extension Collection {
    /// Bounds-checked subscript — Open-Meteo's parallel arrays are not guaranteed equal length.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
