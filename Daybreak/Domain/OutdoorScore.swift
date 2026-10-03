import Foundation

// How good an hour is for being outside, ported from Android's domain/OutdoorScore.kt.

/// Comfortable ([idealC]) and still acceptable ([okC]) conditions for being outside. °C, km/h, %.
struct WeatherProfile: Equatable, Sendable {
    var idealC: ClosedRange<Double>
    var okC: ClosedRange<Double>
    var maxWindKmh: Double
    var maxGustKmh: Double
    var maxPrecipChance: Int
    var snowOk: Bool

    /// Time outside in general (a walk, the park, errands on foot): forgiving of cool weather and a little snow,
    /// not of rain, storms or a gale. The "This week" outlook scores every day with it.
    static let outdoor = WeatherProfile(
        idealC: 12.0...26.0, okC: 0.0...32.0, maxWindKmh: 35.0, maxGustKmh: 60.0, maxPrecipChance: 30, snowOk: true
    )
}

/// Why an hour lost points.
enum Limit: Hashable, Sendable { case storm, snow, rain, wind, cold, heat, dark }

/// How good one hour is for being outside, 0–100, and what held it back.
struct HourScore: Equatable, Sendable {
    let hour: HourForecast
    let score: Int
    let limits: Set<Limit>
}

/// Scores single hours against a [WeatherProfile].
enum OutdoorScorer {
    /// [isNow] uses the current conditions' daylight, so "Now" agrees with the rest of the page.
    static func score(_ hour: HourForecast, _ forecast: Forecast, _ profile: WeatherProfile, isNow: Bool = false) -> HourScore {
        score(hour, profile, dark: isDark(hour, forecast, isNow: isNow))
    }

    /// Scores [hour] (with the rain that falls during it) from 100 down: storms rule it out (and snow, unless the
    /// profile allows it); rain, a chance over the profile's limit, temperatures outside the ideal band, and wind or
    /// gusts over the limits each cost points. A [dark] hour is never more than "poor", however nice the weather.
    ///
    /// The weather code's rain and snow only count when the hour's own chance and amount aren't dry by
    /// [Precip.classify], so the score never calls an hour wet that every other surface calls dry; a storm code with
    /// dry numbers still costs [dryStorm] points (a storm nearby), and is still named.
    static func score(_ hour: HourForecast, _ profile: WeatherProfile, dark: Bool) -> HourScore {
        var limits = Set<Limit>()
        var score = 100.0
        let dry = Precip.classify(hour.precipChance, hour.precipMm).dry
        if (95...99).contains(hour.code) && dry { limits.insert(.storm); score -= dryStorm }
        else if (95...99).contains(hour.code) { limits.insert(.storm); score = 0.0 }
        else if dry {}
        else if snow.contains(hour.code) && !profile.snowOk { limits.insert(.snow); score = 0.0 }
        else if snow.contains(hour.code) { limits.insert(.snow); score -= 35 }
        else if rain.contains(hour.code) { limits.insert(.rain); score -= 45 }
        if hour.precipChance > profile.maxPrecipChance {
            limits.insert(.rain)
            score -= limitStep + Double(hour.precipChance - profile.maxPrecipChance) * 1.2
        }
        let t = hour.tempC
        let ideal = profile.idealC
        let ok = profile.okC
        if t < ok.lowerBound {
            limits.insert(.cold); score -= 40 + (ok.lowerBound - t) * 4 + (ideal.lowerBound - ok.lowerBound) * 3
        } else if t > ok.upperBound {
            limits.insert(.heat); score -= 40 + (t - ok.upperBound) * 4 + (ok.upperBound - ideal.upperBound) * 3
        } else if t < ideal.lowerBound {
            let penalty = (ideal.lowerBound - t) * 3
            score -= penalty
            if penalty > notable { limits.insert(.cold) }
        } else if t > ideal.upperBound {
            let penalty = (t - ideal.upperBound) * 3
            score -= penalty
            if penalty > notable { limits.insert(.heat) }
        }
        let windOver = hour.windKmh.map { $0 - profile.maxWindKmh }.flatMap { $0 > 0 ? $0 : nil }
        let gustOver = hour.gustKmh.map { $0 - profile.maxGustKmh }.flatMap { $0 > 0 ? $0 : nil }
        if windOver != nil || gustOver != nil {
            limits.insert(.wind)
            score -= limitStep + (windOver ?? 0.0) * 2 + (gustOver ?? 0.0) * 1.5
        }
        if dark {
            limits.insert(.dark)
            score = min(score - 50, darkMax)
        }
        return HourScore(hour: hour, score: min(max(roundToInt(score), 0), 100), limits: limits)
    }

    /// Daylight at the middle of the hour, so an hour the sun rises early in (7:00 with sunrise 7:02) counts as
    /// light and one it sets early in (18:00 with sunset 18:05) as dark. The current hour follows the current
    /// conditions instead.
    static func isDark(_ hour: HourForecast, _ forecast: Forecast, isNow: Bool = false) -> Bool {
        isNow ? forecast.isNightNow : forecast.isNight(hour.time.plusMinutes(30))
    }

    /// Extra cost for crossing a rain or wind limit at all, so an hour over the limit rarely still counts as good.
    private static let limitStep = 15.0

    /// What a storm code costs when the hour's chance and amount are dry.
    private static let dryStorm = 30.0

    /// The best a dark hour can score.
    private static let darkMax = 30.0

    /// An in-band temperature penalty big enough to be worth naming as a reason.
    private static let notable = 15.0

    private static let snow: Set<Int> = [71, 73, 75, 77, 85, 86]
    private static let rain: Set<Int> = [51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82]
}
