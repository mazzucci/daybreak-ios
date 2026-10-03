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

    /// 21.4°C (71°F) partly cloudy now; high 23.6 (74°F), low 13.2 (56°F); rain possible from 5 PM (60% stamped 6 PM,
    /// then 40%), 4.1 mm of it still to come, about 6.5 mm today. From 6 PM the breeze makes it feel 2.5°C colder,
    /// enough to show in °F. Wind from the SW.
    static func forecast(tempC: Double = 21.4, rainAt: Int? = 4) -> Forecast {
        Forecast(
            current: CurrentConditions(time: now, tempC: tempC, feelsLikeC: 20.1, humidity: 58, windKmh: 14.2, code: 2,
                                       windDirectionDeg: 235),
            days: week(now, DaySummary(date: now.date, highC: 23.6, lowC: 13.2, precipChance: rainAt != nil ? 60 : 5, code: 61,
                                       uvIndexMax: 6.2)),
            hours: (0..<12).map { (i: Int) -> HourForecast in
                let wet = rainAt.map { i >= $0 } ?? false
                let amounts = [0.6, 1.8, 1.2, 0.4, 0.1]
                let chance: Int = rainAt.map { i == $0 ? 60 : i > $0 ? 40 : 10 } ?? 0
                let mm: Double = rainAt.map { i < $0 ? 0.0 : i - $0 < amounts.count ? amounts[i - $0] : 0.0 } ?? 0.0
                return HourForecast(
                    time: now.truncatedToHour.plusHours(i),
                    tempC: tempC - Double(i) * 0.6,
                    precipChance: chance,
                    code: wet ? 61 : 2,
                    windKmh: 14.2 + Double(i),
                    gustKmh: 24.0 + Double(i),
                    feelsLikeC: tempC - Double(i) * 0.6 - (wet ? 2.5 : 0.5),
                    precipMm: mm,
                    windDirectionDeg: 235
                )
            },
            utcOffsetSeconds: -7 * 3600 // PDT
        )
    }

    /// 9.8°C (50°F), steady rain at 10:30 PM in London; a few hours of showers then clearing to overcast.
    static func rainyNight() -> Forecast {
        let at = LocalDateTime(2026, 9, 28, 22, 30)
        return Forecast(
            current: CurrentConditions(time: at, tempC: 9.8, feelsLikeC: 7.4, humidity: 91, windKmh: 27.0, code: 63,
                                       windDirectionDeg: 200),
            days: week(at, DaySummary(date: at.date, highC: 14.1, lowC: 8.3, precipChance: 90, code: 63, uvIndexMax: 1.4)),
            hours: (0..<12).map { (i: Int) -> HourForecast in
                let chance: Int = i < 3 ? 90 : i < 6 ? 60 : 20
                let code: Int = i < 3 ? 63 : i < 6 ? 80 : i < 9 ? 3 : 2
                let mm: Double = i < 3 ? 1.6 : i < 6 ? 0.4 : 0.0
                return HourForecast(
                    time: at.truncatedToHour.plusHours(i),
                    tempC: 9.8 - Double(i) * 0.2,
                    precipChance: chance,
                    code: code,
                    feelsLikeC: 7.4 - Double(i) * 0.2,
                    precipMm: mm,
                    windDirectionDeg: 200
                )
            },
            utcOffsetSeconds: 3600 // BST
        )
    }

    /// [today] followed by varied days (a wet one, a showery one, a sunny one, …), so tests see a realistic 10-day
    /// forecast. Every day gets sunrise 7:02 and sunset 18:56 plus wind and UV.
    private static func week(_ now: LocalDateTime, _ today: DaySummary) -> [DaySummary] {
        let highs: [Double] = [0, 2, -4, 1, 3, -1, 2, 0, -2, 1]
        let lows: [Double] = [0, 1, -2, 0, 2, -1, 1, 0, -1, 0]
        let rest = (1..<forecastDays).map { d in
            let wet = d == 2
            let showery = d == 8
            return DaySummary(
                date: now.date.plusDays(d),
                highC: today.highC + highs[d],
                lowC: today.lowC + lows[d],
                precipChance: wet ? 70 : showery ? 45 : 10,
                code: wet ? 63 : showery ? 80 : [0, 1, 2, 3][d % 4],
                precipSumMm: showery ? 2.4 : nil,
                uvIndexMax: wet ? 2.0 : 5.5,
                precipHours: showery ? 3.0 : nil
            )
        }
        return ([today] + rest).map { day in
            modified(day) {
                $0.sunrise = day.date.atTime(7, 2)
                $0.sunset = day.date.atTime(18, 56)
                $0.windMaxKmh = 20.0
                $0.gustMaxKmh = 35.0
                $0.windDirectionDeg = 250.0
                $0.precipSumMm = day.precipSumMm ?? (day.precipChance >= 60 ? 6.5 : 0.0)
                $0.precipHours = day.precipHours ?? (day.precipChance >= 60 ? 5.0 : 0.0)
            }
        }
    }

    /// One day of a [synthetic] forecast: its low (at 5 AM) and high (at 3 PM), the hours rain falls in ([rainHours],
    /// each the start of the hour, 0–22) with their chance and amount, snow instead of rain, and the wind.
    struct DaySpec {
        var highC = 20.0
        var lowC = 11.0
        var rainHours: ClosedRange<Int>? = nil
        var chance = 80
        var mmPerHour = 1.5
        var snow = false
        var windKmh = 12.0
        var gustKmh = 25.0
    }

    /// How the sun behaves in a [synthetic] forecast.
    enum Sun { case normal, polarNight, midnightSun }

    /// A forecast with full hourly data for [days] (today first, at [at]), built to order for the outlook's rules: a
    /// smooth day from each low to high, rain stamped at the end of the hour it falls in (see Precip) with the weather
    /// code at its start (an instant value), sunrise 7 AM and sunset 7 PM unless [sun] says otherwise.
    static func synthetic(_ days: [DaySpec], _ at: LocalDateTime = LocalDateTime(2026, 10, 1, 8, 0), _ sun: Sun = .normal) -> Forecast {
        let start = at.date
        func stamp(_ d: Int, _ h: Int) -> LocalDateTime { start.plusDays(d).atTime(h, 0) }
        let hours = days.enumerated().flatMap { d, spec in
            (0..<24).map { h in
                // The rain falling during hour h - 1 is stamped h.
                let wet = spec.rainHours?.contains(h - 1) == true
                let t = spec.lowC + (spec.highC - spec.lowC) * (1 - cos(Double.pi * Double(min((h - 5 + 24) % 24, 20)) / 10.0)) / 2
                return HourForecast(
                    time: stamp(d, h),
                    tempC: t,
                    precipChance: wet ? spec.chance : 5,
                    // The code is instant (Open-Meteo): it's raining at h when rain falls during the hour from h.
                    code: spec.rainHours?.contains(h) == true ? (spec.snow ? 73 : 63) : 1,
                    windKmh: spec.windKmh,
                    gustKmh: spec.gustKmh,
                    precipMm: wet ? spec.mmPerHour : 0.0,
                    snowCm: wet && spec.snow ? spec.mmPerHour * 0.7 : 0.0
                )
            }
        }
        let summaries = days.enumerated().map { d, spec in
            let date = start.plusDays(d)
            let dayHours = hours.filter { $0.time.date == date }
            let (rise, set): (LocalDateTime, LocalDateTime) = switch sun {
            case .normal: (date.atTime(7, 0), date.atTime(19, 0))
            case .polarNight: (date.atStartOfDay, date.atStartOfDay)
            case .midnightSun: (date.atStartOfDay, date.plusDays(1).atStartOfDay)
            }
            return DaySummary(
                date: date, highC: spec.highC, lowC: spec.lowC,
                precipChance: dayHours.map(\.precipChance).max()!,
                code: spec.rainHours != nil ? (spec.snow ? 73 : 63) : 1,
                sunrise: rise, sunset: set,
                windMaxKmh: spec.windKmh, gustMaxKmh: spec.gustKmh,
                precipSumMm: dayHours.reduce(0) { $0 + ($1.precipMm ?? 0.0) },
                precipHours: Double(dayHours.count { ($0.precipMm ?? 0.0) > 0.0 }),
                snowSumCm: dayHours.reduce(0) { $0 + ($1.snowCm ?? 0.0) }
            )
        }
        let now = hours.first { !($0.time > at) && $0.time.plusHours(1) > at } ?? hours[0]
        return Forecast(
            current: CurrentConditions(time: at, tempC: now.tempC, feelsLikeC: now.tempC, humidity: 60, windKmh: now.windKmh ?? 0.0,
                                       code: now.code),
            days: summaries,
            hours: hours
        )
    }
}

/// [value] with [edit] applied: Kotlin's data-class `copy` for the tests' structs.
func modified<T>(_ value: T, _ edit: (inout T) -> Void) -> T {
    var copy = value
    edit(&copy)
    return copy
}

extension Forecast {
    /// Kotlin's data-class `copy`, for tests: the forecast with the given fields replaced.
    func copy(current: CurrentConditions? = nil, days: [DaySummary]? = nil, hours: [HourForecast]? = nil,
              utcOffsetSeconds: Int? = nil) -> Forecast {
        Forecast(current: current ?? self.current, days: days ?? self.days, hours: hours ?? self.hours,
                 utcOffsetSeconds: utcOffsetSeconds ?? self.utcOffsetSeconds)
    }
}

extension LocalDateTime {
    /// java.time's `withHour` and `withMinute`, for tests.
    func withHour(_ hour: Int) -> LocalDateTime { date.atTime(hour, minute) }
    func withMinute(_ minute: Int) -> LocalDateTime { date.atTime(hour, minute) }
}
