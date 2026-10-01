import Foundation

/// The summary line at the top of the Weather page, ported from Android's TemplateNarrator: a deterministic
/// description of the forecast, in English with numbers and times written the US way.
///
/// "71° and partly cloudy now, with a high of 74° and a low of 56°. Rain is possible around 5 PM (60% chance, about
/// 0.16 inches still to come today)."
enum Summary {
    /// The summary. [withTotal] adds how much of today's rain is still to come.
    static func describe(_ forecast: Forecast, _ unit: TempUnit, withTotal: Bool = true) -> String {
        let condition = describeWeatherCode(forecast.current.code).lowercased()
        let now = formatDegrees(forecast.current.tempC, unit)
        let high = formatDegrees(forecast.today.highC, unit)
        let low = formatDegrees(forecast.today.lowC, unit)
        return "\(now) and \(condition) now, with a high of \(high) and a low of \(low). \(rainSentence(forecast, unit, withTotal))"
    }

    /// The rain (or snow) sentence: the first hour ahead where it's likely, else the first where it's possible (each
    /// hour with the chance stamped at its end, as the hourly strip shows it); otherwise whether it's easing, today's
    /// chance, or none.
    private static func rainSentence(_ f: Forecast, _ unit: TempUnit, _ withTotal: Bool) -> String {
        let today = Precip.dayRain(f, f.today.date)
        let ahead = f.nextHours.compactMap { h in f.rainDuring(h).map { (h, $0) } }
        let wet = ahead.first { $0.1.precipChance >= Precip.likely } ?? ahead.first { $0.1.precipChance >= Precip.possible }
        if let (hour, rain) = wet {
            // Today's figures hold the hours stamped today: an hour stamped after midnight belongs to tomorrow's.
            let isToday = rain.time.date == today.date
            let snow = Precip.isSnowHour(rain) || (isToday && today.showsSnow)
            let what = snow ? "Snow" : "Rain"
            let word = Precip.likelihood(rain.precipChance).word
            let amount = withTotal && isToday ? stillToCome(today, f.current.time, unit) : nil
            return "\(what) is \(word) around \(formatHour(hour.time)) (\(rain.precipChance)% chance\(amount.map { ", \($0)" } ?? ""))."
        }
        if wetCodes.contains(f.current.code) { return "It should ease off soon." }
        if today.dry { return "No rain expected." }
        if Precip.showDayChance(today.chance) { return "There's a \(today.chance)% chance of \(today.noun.lowercased()) today." }
        return "There's a small chance of \(today.noun.lowercased()) today."
    }

    /// "about 4 mm still to come today" (or "about 3 cm" of snow) once that's at least a millimetre of water.
    private static func stillToCome(_ today: DayRain, _ now: LocalDateTime, _ unit: TempUnit) -> String? {
        guard today.amountShown else { return nil }
        let rest = today.stillToCome(now)
        guard rest.mm >= 1.0 else { return nil }
        let lead = today.rough ? "up to" : "about"
        let amount = today.showsSnow && rest.snowCm >= Precip.snowHourMinCm
            ? Precip.proseSnow(rest.snowCm, unit, rough: today.rough)
            : Precip.proseRain(rest.mm, unit, rough: today.rough)
        return "\(lead) \(amount) still to come today"
    }

    private static let snowCodes: Set<Int> = [71, 73, 75, 77, 85, 86]
    /// Drizzle, rain, showers, snow and storms.
    private static let wetCodes: Set<Int> = Set([51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99]).union(snowCodes)
}

/// "Good morning" 05–11, "Good afternoon" 12–17, "Good evening" 18–21, "Good night" 22–04.
func greeting(hour: Int) -> String {
    switch hour {
    case 5...11: "Good morning"
    case 12...17: "Good afternoon"
    case 18...21: "Good evening"
    default: "Good night"
    }
}

/// The rain pill's value and its spoken form, by the shared classifier: "60% · 4 mm" (the chance from 20%, the total
/// from 0.5 mm), "small chance · up to 2 mm" for a real amount at a low chance, "unlikely" for a dry day.
func rainPill(_ rain: DayRain, _ unit: TempUnit) -> (value: String, spoken: String) {
    if rain.dry { return ("unlikely", "unlikely") }
    let amount = Precip.dayAmount(rain, unit)
    let spokenAmount = Precip.dayAmountSpoken(rain, unit)?.removingSuffix(" of snow")
    if !Precip.showDayChance(rain.chance) {
        return (["small chance", amount.map { "up to \($0)" }].compactMap { $0 }.joined(separator: " · "),
                ["small chance", spokenAmount].compactMap { $0 }.joined(separator: ", "))
    }
    return (["\(rain.chance)%", amount].compactMap { $0 }.joined(separator: " · "),
            ["\(rain.chance)% chance", spokenAmount].compactMap { $0 }.joined(separator: ", "))
}
