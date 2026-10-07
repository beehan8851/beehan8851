import Foundation

/// Weather in the units the person reads it in. Both backends hand over Celsius and
/// km/h; what is shown follows the locale and the Temperature choice in Settings ›
/// General › Language & Region, which reaches the app as part of the locale.
///
/// Temperatures are shown as a bare number and a degree sign, as the Weather app
/// shows them: in a weather row there is no doubt which scale it is, and "22°C"
/// beside "H:25° L:14°" only adds noise.
nonisolated enum WeatherUnits {
    static func degrees(_ celsius: Double, locale: Locale = .autoupdatingCurrent) -> Int {
        let unit = UnitTemperature(forLocale: locale, usage: .weather)
        return Int(Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit).value.rounded())
    }

    static func wind(_ kilometresPerHour: Double, locale: Locale = .autoupdatingCurrent) -> String {
        Measurement(value: kilometresPerHour, unit: UnitSpeed.kilometersPerHour).formatted(
            .measurement(width: .abbreviated, usage: .wind, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
        )
    }
}
