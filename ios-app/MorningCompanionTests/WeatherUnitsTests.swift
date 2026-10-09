import Foundation
import Testing
@testable import MorningCompanion

@Suite("Weather units")
struct WeatherUnitsTests {
    @Test("Fahrenheit where the locale reads it")
    func fahrenheit() {
        #expect(WeatherUnits.degrees(22.4, locale: Locale(identifier: "en_US")) == 72)
        #expect(WeatherUnits.degrees(-3.6, locale: Locale(identifier: "en_US")) == 26)
    }

    @Test("Celsius elsewhere")
    func celsius() {
        #expect(WeatherUnits.degrees(22.4, locale: Locale(identifier: "de_DE")) == 22)
        #expect(WeatherUnits.degrees(-3.6, locale: Locale(identifier: "uz_UZ")) == -4)
    }

    @Test("The Temperature setting wins over the region")
    func setting() {
        #expect(WeatherUnits.degrees(22.4, locale: Locale(identifier: "en_GB@mu=fahrenhe")) == 72)
        #expect(WeatherUnits.degrees(22.4, locale: Locale(identifier: "en_US@mu=celsius")) == 22)
    }

    @Test("Wind in the locale's unit")
    func wind() {
        #expect(WeatherUnits.wind(12, locale: Locale(identifier: "en_US")) == "7 mph")
        #expect(WeatherUnits.wind(12, locale: Locale(identifier: "de_DE")) == "12 km/h")
    }
}
