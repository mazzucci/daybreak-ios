import Foundation
import Testing
@testable import Daybreak

/// Ported from Android's OpenMeteoParsersTest, on the same fixtures.
struct OpenMeteoParserTests {
    private func sf() throws -> Forecast { try parseForecast(TestData.fixture("forecast_sf.json")) }

    @Test("parses current conditions")
    func current() throws {
        let f = try sf()
        #expect(f.current.time == LocalDateTime(2026, 9, 28, 14, 30))
        #expect(abs(f.current.tempC - 21.1) < 0.001)
        #expect(abs(f.current.feelsLikeC - 20.4) < 0.001)
        #expect(f.current.humidity == 56)
        #expect(abs(f.current.windKmh - 15.2) < 0.001)
        #expect(f.current.code == 0)
    }

    @Test("next hours start at the current hour and span 12 hours across midnight")
    func nextHours() throws {
        let f = try sf()
        #expect(f.nextHours.count == 12)
        #expect(f.nextHours.first?.time == LocalDateTime(2026, 9, 28, 14, 0))
        #expect(f.nextHours.last?.time == LocalDateTime(2026, 9, 29, 1, 0))
        #expect(abs(f.nextHours[0].tempC - 21.8) < 0.001)
        #expect(abs(f.nextHours[11].tempC - 13.0) < 0.001)
    }

    @Test("keeps every day and hour returned")
    func everything() throws {
        let f = try sf()
        #expect(f.days.map(\.date) == [LocalDate(2026, 9, 28), LocalDate(2026, 9, 29)])
        #expect(f.hours.count == 48)
        #expect(abs(f.days[1].highC - 26.7) < 0.001)
    }

    @Test("today is the daily entry matching the current date")
    func today() throws {
        let f = try sf()
        #expect(abs(f.today.highC - 21.8) < 0.001)
        #expect(abs(f.today.lowC - 12.5) < 0.001)
        #expect(f.today.precipChance == 0)
        #expect(f.today.code == 45)
    }

    @Test("null precipitation probabilities count as zero")
    func nullChances() throws {
        let json = """
            {"current":{"time":"2026-01-01T00:00","temperature_2m":1,"apparent_temperature":0,
              "relative_humidity_2m":90,"wind_speed_10m":3,"weather_code":3},
             "hourly":{"time":["2026-01-01T00:00"],"temperature_2m":[1],"precipitation_probability":[null],"weather_code":[3]},
             "daily":{"time":["2026-01-01"],"temperature_2m_max":[2],"temperature_2m_min":[-1],
              "precipitation_probability_max":[null],"weather_code":[3]}}
            """
        let f = try parseForecast(json)
        #expect(f.nextHours.count == 1)
        #expect(f.nextHours.first?.precipChance == 0)
        #expect(f.today.precipChance == 0)
    }

    @Test("an empty daily forecast is a friendly error")
    func emptyDaily() throws {
        var root = try #require(try JSONSerialization.jsonObject(with: Data(TestData.fixture("forecast_sf.json").utf8)) as? [String: Any])
        var daily = try #require(root["daily"] as? [String: Any])
        for key in daily.keys { daily[key] = [Any]() }
        root["daily"] = daily
        let json = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
        #expect(throws: ServiceError("Weather service returned no daily forecast")) { try parseForecast(json) }
    }

    @Test("parses a full week with wind, sun times and UV")
    func week() throws {
        let f = try parseForecast(TestData.fixture("forecast_sf_week.json"))
        #expect(f.days.count == 8)
        #expect(f.hours.count == 192)
        #expect(f.today.date == LocalDate(2026, 9, 28))
        #expect(f.upcomingDays().count == 8) // an 8-day response from before the list grew to 10
        #expect(f.upcomingDays().last?.date == LocalDate(2026, 10, 5))

        let today = f.today
        #expect(today.sunrise == LocalDateTime(2026, 9, 28, 7, 2))
        #expect(today.sunset == LocalDateTime(2026, 9, 28, 18, 56))
        #expect(abs(try #require(today.windMaxKmh) - 25.0) < 0.001)
        #expect(abs(try #require(today.gustMaxKmh) - 36.7) < 0.001)
        #expect(abs(try #require(today.precipSumMm) - 0.0) < 0.001)
        #expect(abs(try #require(today.uvIndexMax) - 6.05) < 0.001)

        #expect(f.current.isDay == true)
        let now = try #require(f.nextHours.first)
        #expect(now.time == LocalDateTime(2026, 9, 28, 16, 0))
        #expect(abs(try #require(now.windKmh) - 21.9) < 0.001)
        #expect(abs(try #require(now.gustKmh) - 31.7) < 0.001)
        #expect(now.isDay == true)
        #expect(f.nextHours.last?.isDay == false)
    }

    @Test("parses ten days with amounts, snow, hours, feels-like and wind direction")
    func tenDays() throws {
        let f = try parseForecast(TestData.fixture("forecast_alps_10day.json"))
        #expect(f.days.count == 10)
        #expect(f.hours.count == 240)
        #expect(f.upcomingDays().count == 10)
        let snowy = f.days[7]
        #expect(snowy.date == LocalDate(2026, 10, 8))
        #expect(abs(try #require(snowy.precipSumMm) - 27.6) < 0.001)
        #expect(abs(try #require(snowy.snowSumCm) - 19.32) < 0.001)
        #expect(abs(try #require(snowy.precipHours) - 21.0) < 0.001)
        #expect(abs(try #require(snowy.windDirectionDeg) - 4.0) < 0.001)
        let wet = try #require(f.hours.first { $0.time == LocalDateTime(2026, 10, 2, 1, 0) })
        #expect(abs(try #require(wet.precipMm) - 6.3) < 0.001)
        #expect(abs(try #require(wet.snowCm) - 0.0) < 0.001)
        #expect(abs(try #require(wet.feelsLikeC) - -0.7) < 0.001)
        #expect(abs(try #require(wet.windDirectionDeg) - 333.0) < 0.001)
    }

    @Test("the wind's direction now comes with its speed now")
    func windDirectionNow() throws {
        let fixture = TestData.fixture("forecast_alps_10day.json")
        let json = fixture.replacingOccurrences(of: "\"wind_speed_10m\":3.1,", with: "\"wind_speed_10m\":3.1,\"wind_direction_10m\":225,")
        let f = try parseForecast(json)
        #expect(abs(f.current.windKmh - 3.1) < 0.001)
        #expect(f.current.windDirectionDeg == 225)
        #expect(try parseForecast(fixture).current.windDirectionDeg == nil)
    }

    @Test("responses without the detail fields still parse")
    func withoutDetails() throws {
        let f = try sf()
        #expect(f.today.sunrise == nil)
        #expect(f.today.uvIndexMax == nil)
        #expect(f.nextHours.first?.gustKmh == nil)
        #expect(f.nextHours.first?.isDay == nil)
        #expect(f.nextHours.first?.precipMm == nil)
        #expect(f.nextHours.first?.feelsLikeC == nil)
        #expect(f.today.snowSumCm == nil)
        #expect(f.today.windDirectionDeg == nil)
    }

    @Test("null detail values become nil, not zero")
    func nullDetails() throws {
        let json = """
            {"current":{"time":"2026-06-21T12:00","temperature_2m":1,"apparent_temperature":0,
              "relative_humidity_2m":90,"wind_speed_10m":3,"weather_code":3,"is_day":null,"wind_direction_10m":null},
             "hourly":{"time":["2026-06-21T12:00"],"temperature_2m":[1],"precipitation_probability":[0],"weather_code":[3],
              "wind_speed_10m":[null],"wind_gusts_10m":[null],"is_day":[null],"apparent_temperature":[null],
              "precipitation":[null],"snowfall":[null],"wind_direction_10m":[null]},
             "daily":{"time":["2026-06-21"],"temperature_2m_max":[2],"temperature_2m_min":[-1],
              "precipitation_probability_max":[0],"weather_code":[3],"sunrise":[null],"sunset":["not a time"],
              "wind_speed_10m_max":[null],"wind_gusts_10m_max":[null],"precipitation_sum":[null],"uv_index_max":[null],
              "precipitation_hours":[null],"snowfall_sum":[null],"wind_direction_10m_dominant":[null]}}
            """
        let f = try parseForecast(json)
        #expect(f.current.isDay == nil)
        #expect(f.current.windDirectionDeg == nil)
        let t = f.today
        #expect(t.sunrise == nil && t.sunset == nil && t.windMaxKmh == nil && t.gustMaxKmh == nil && t.precipSumMm == nil)
        #expect(t.uvIndexMax == nil && t.precipHours == nil && t.snowSumCm == nil && t.windDirectionDeg == nil)
        let h = try #require(f.nextHours.first)
        #expect(h.windKmh == nil && h.gustKmh == nil && h.isDay == nil && h.feelsLikeC == nil)
        #expect(h.precipMm == nil && h.snowCm == nil && h.windDirectionDeg == nil)
    }

    @Test("polar sun times come through as the API sends them")
    func polar() throws {
        // Shapes returned by the live API: polar night has sunrise == sunset, midnight sun a 24 h gap.
        func day(_ date: String, _ sunrise: String, _ sunset: String) -> String {
            """
            {"current":{"time":"\(date)T12:00","temperature_2m":1,"apparent_temperature":0,
              "relative_humidity_2m":90,"wind_speed_10m":3,"weather_code":3,"is_day":false},
             "hourly":{"time":["\(date)T12:00"],"temperature_2m":[1],"precipitation_probability":[0],"weather_code":[3]},
             "daily":{"time":["\(date)"],"temperature_2m_max":[2],"temperature_2m_min":[-1],
              "precipitation_probability_max":[0],"weather_code":[3],"sunrise":["\(sunrise)"],"sunset":["\(sunset)"]}}
            """
        }
        let night = try parseForecast(day("2026-12-21", "2026-12-21T00:00", "2026-12-21T00:00"))
        #expect(night.today.daylight == .polarNight)
        #expect(night.current.isDay == false) // JSON booleans are accepted as well as 0/1
        let sun = try parseForecast(day("2026-06-21", "2026-06-21T00:00", "2026-06-22T00:00"))
        #expect(sun.today.daylight == .midnightSun)
    }

    @Test("asks Open-Meteo for current, hourly and ten days, as Android does")
    func request() {
        let url = OpenMeteo.forecastURL(latitude: 42.36, longitude: -71.29).absoluteString
        #expect(url.hasPrefix("https://api.open-meteo.com/v1/forecast?latitude=42.36&longitude=-71.29&current="))
        #expect(url.contains("&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max,"))
        #expect(url.hasSuffix("&timezone=auto&forecast_days=10"))
    }

    @Test("parses geocoding results")
    func geocoding() throws {
        let places = try parseGeocoding(TestData.fixture("geocoding_springfield.json"))
        #expect(places.count == 5)
        let first = try #require(places.first)
        #expect(first.id == "geo:4409896")
        #expect(first.name == "Springfield")
        #expect(first.region == "Missouri")
        #expect(first.country == "United States")
        #expect(abs(first.latitude - 37.21533) < 1e-6)
        #expect(abs(first.longitude - -93.29824) < 1e-6)
        #expect(first.detail == "Missouri, United States")
        #expect(first.zoneId == "America/Chicago")
    }

    @Test("geocoding with no matches returns an empty list")
    func noMatches() throws {
        #expect(try parseGeocoding(TestData.fixture("geocoding_empty.json")).isEmpty)
    }

    @Test("geocoding tolerates missing region and country")
    func missingRegion() throws {
        let p = try #require(try parseGeocoding(#"{"results":[{"id":1,"name":"Nowhere","latitude":1.5,"longitude":2.5}]}"#).first)
        #expect(p.region == nil)
        #expect(p.country == nil)
        #expect(p.detail == nil)
    }
}

/// The hourly strip's "Now" cell and the summary use the current conditions.
struct WeatherFormattingTests {
    @Test("temperatures in both units, with a true minus sign")
    func temperatures() {
        #expect(formatTemp(21.4, .f) == "71°F")
        #expect(formatTemp(21.4, .c) == "21°C")
        #expect(formatDegrees(-6.2, .c) == "\u{2212}6°")
        #expect(formatBothUnits(23.6, .f) == "74°F (24°C)")
    }

    @Test("the summary describes now, today's range and the rain ahead")
    func summary() throws {
        let f = try parseForecast(TestData.fixture("forecast_sf_week.json"))
        let text = Summary.describe(f, .f)
        #expect(text.hasPrefix("\(formatDegrees(f.current.tempC, .f)) and "))
        #expect(text.contains("with a high of \(formatDegrees(f.today.highC, .f)) and a low of \(formatDegrees(f.today.lowC, .f))."))
    }

    @Test("updated lines and the greeting")
    func updated() {
        let now = Date()
        #expect(formatUpdated(now, now: now) == "Updated just now")
        #expect(formatUpdated(now.addingTimeInterval(-8 * 60), now: now) == "Updated 8 min ago")
        #expect(formatUpdated(now.addingTimeInterval(-90 * 60), now: now) == "Updated over an hour ago")
        #expect(formatUpdated(now.addingTimeInterval(-3 * 3600), now: now) == "Updated 3 hours ago")
        #expect(!isStale(now.addingTimeInterval(-90 * 60), now: now))
        #expect(isStale(now.addingTimeInterval(-91 * 60), now: now))
        #expect(greeting(hour: 5) == "Good morning")
        #expect(greeting(hour: 12) == "Good afternoon")
        #expect(greeting(hour: 21) == "Good evening")
        #expect(greeting(hour: 4) == "Good night")
    }

    @Test("dates without a zone line up with java.time's")
    func localDates() {
        #expect(LocalDate(1970, 1, 1).epochDay == 0)
        #expect(LocalDate(2026, 10, 1).epochDay == 20_727)
        #expect(LocalDate(2026, 10, 1).weekday == 4) // a Thursday
        #expect(LocalDate(epochDay: 20_727).description == "2026-10-01")
        #expect(LocalDate(2024, 2, 29).plusYears(1) == LocalDate(2025, 2, 28))
        #expect(LocalDateTime.parse("2026-09-28T14:30")?.truncatedToHour == LocalDateTime(2026, 9, 28, 14, 0))
    }
}
