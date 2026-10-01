import Foundation
@testable import Daybreak

/// Shared sample data for the tests: Android's JSON fixtures (copied into Fixtures/) and a few builders.
enum TestData {
    private final class Token {}

    /// A fixture's text, from the test bundle.
    static func fixture(_ name: String) -> String {
        let bundle = Bundle(for: Token.self)
        guard let url = bundle.url(forResource: name, withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("Missing fixture \(name)")
        }
        return text
    }

    /// A real 10-day Open-Meteo response for the Jungfraujoch (3,200 m): showers, a dry spell, then two days of snow.
    static func alps() -> Forecast { try! parseForecast(fixture("forecast_alps_10day.json")) }

    static let now = LocalDateTime(2026, 9, 28, 14, 30)

    /// The current conditions of Android's TestData.forecast(): 21.4°C, partly cloudy, wind from the SW.
    static let current = CurrentConditions(time: now, tempC: 21.4, feelsLikeC: 20.1, humidity: 58, windKmh: 14.2, code: 2,
                                           windDirectionDeg: 235)
}
