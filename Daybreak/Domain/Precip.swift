import Foundation

/// The one rule set for rain and snow, ported from Android's domain/Precip.kt, so the hourly strip, the 10-day list,
/// the hero pill, Home and the summary never disagree about when a chance or an amount is worth showing, or what to
/// call it. One classifier ([classify]) is behind all of them.
///
/// Amounts are kept in mm (water) and cm (snow depth) as Open-Meteo sends them, and shown in one unit system that
/// follows the temperature setting: mm and cm with °C, inches with °F. Never both.
///
/// **Which hour a value belongs to.** Open-Meteo stamps an hour's precipitation, snowfall and
/// precipitation_probability with the hour's end: the value at 15:00 is what falls from 14:00 to 15:00. So a stretch
/// of time from A to B holds the values stamped after A, up to and including B; "heaviest around 2 PM" names the
/// hour the rain falls in (the stamp minus an hour); and the hourly strip's cell for the hour starting at H shows the
/// values stamped H + 1 ([Forecast.rainDuring]).
///
/// **Which day.** A date's stamps run from 00:00 to 23:00, and Open-Meteo's daily figures are built from exactly
/// those, so the hours are grouped the same way ([Forecast.hoursOf]) and no hour is counted on two days.
enum Precip {
    /// An hourly chance below this is noise: the cell leaves its line blank.
    static let hourChanceMin = 10
    /// From here a chance is worth planning around, and is drawn in the rain colour.
    static let chanceHighlight = 40
    /// A daily chance below this isn't printed; without a real amount it makes a dry day (or part of one).
    static let dayChanceMin = 20
    /// Open-Meteo's probability is defined on 0.1 mm an hour; below it is a trace.
    static let hourAmountMinMm = 0.1
    /// The smallest day total worth a number.
    static let dayTotalMinMm = 0.5
    /// From here a modelled amount is real enough to show whatever the chance ("a small chance · up to 2 mm").
    static let amountAloneMm = 1.0
    /// The smallest snowfall that makes it a snow day (or part of one), or a snow hour.
    static let snowDayMinCm = 0.5
    static let snowHourMinCm = 0.1
    /// A wet day needs both a real chance and a real amount.
    static let wetDayChance = 50
    static let wetDayMm = 1.0
    /// Chance words: likely, possible, a small chance, unlikely.
    static let likely = 70
    static let possible = 40
    /// Below this a day's rain is "a few drops", so the verdict doesn't print a number.
    static let fewDropsMm = 1.0

    /// Open-Meteo: 7 cm of snow is about 10 mm of water.
    private static let snowCmPerWaterMm = 0.7
    private static let mmPerInch = 25.4
    private static let cmPerInch = 2.54
    /// One hour holding at least this share of the day's total gets "heaviest around …".
    private static let peakShare = 0.35
    /// A part of the day holding this share of the total gets "mostly in the …".
    private static let mostlyShare = 0.6
    /// A part of the day with at least this share counts as wet when the rain is spread out.
    private static let someShare = 0.15
    private static let hoursPerDay = 24

    static func showHourChance(_ chance: Int) -> Bool { chance >= hourChanceMin }
    static func highlightChance(_ chance: Int) -> Bool { chance >= chanceHighlight }
    static func showDayChance(_ chance: Int) -> Bool { chance >= dayChanceMin }

    static func likelihood(_ chance: Int) -> Likelihood {
        if chance >= likely { return .likely }
        if chance >= possible { return .possible }
        if chance >= dayChanceMin { return .small }
        return .unlikely
    }

    /// Judges a day, a part of one or an hour from its highest hourly [chance] and its amount ([mm] of water, nil
    /// when unknown): dry, possible ([DayKind.mixed]) or likely ([DayKind.wet]), and whether the amount is worth a
    /// number.
    ///
    /// - An amount is shown from 0.1 mm, and only with at least a 20% chance or at least 1 mm.
    /// - Dry: under 20% with no amount worth showing.
    /// - Wet: at least 50% and 1 mm.
    /// - Possible: anything in between, including a real chance with no modelled amount.
    static func classify(_ chance: Int, _ mm: Double?) -> RainCall {
        let amountShown = mm.map { $0 >= hourAmountMinMm && (chance >= dayChanceMin || $0 >= amountAloneMm) } ?? false
        let kind: DayKind
        if chance < dayChanceMin && !amountShown { kind = .dry }
        else if chance >= wetDayChance && (mm ?? 0) >= wetDayMm { kind = .wet }
        else { kind = .mixed }
        return RainCall(kind: kind, amountShown: amountShown)
    }

    /// Snow when there's enough of it and it makes up most of the water that falls.
    static func isSnow(_ snowCm: Double?, _ precipMm: Double?, minCm: Double) -> Bool {
        guard let snowCm, snowCm >= minCm else { return false }
        return snowCm / snowCmPerWaterMm >= (precipMm ?? 0) / 2
    }

    // MARK: Amounts as text

    /// Rain (water) for cells and rows: "0.6 mm", "4 mm", "18 mm" with °C; "0.02 in", "0.7 in", "1.2 in" with °F.
    /// [rough] rounds mm to a whole number, for amounts at a low chance ("up to 2 mm").
    static func formatRain(_ mm: Double, _ unit: TempUnit, rough: Bool = false) -> String {
        switch unit {
        case .c: "\(metric(mm, rough)) mm"
        case .f: "\(inches(mm / mmPerInch)) in"
        }
    }

    /// Snow depth for cells and rows: "0.4 cm", "3 cm", or "0.16 in", "1.2 in".
    static func formatSnow(_ cm: Double, _ unit: TempUnit, rough: Bool = false) -> String {
        switch unit {
        case .c: "\(metric(cm, rough)) cm"
        case .f: "\(inches(cm / cmPerInch)) in"
        }
    }

    /// Rain in a sentence: "4 mm", or "0.26 inches" (one inch is "1 inch").
    static func proseRain(_ mm: Double, _ unit: TempUnit, rough: Bool = false) -> String {
        switch unit {
        case .c: "\(metric(mm, rough)) mm"
        case .f: proseInches(mm / mmPerInch)
        }
    }

    /// Snow in a sentence: "3 cm", or "1.2 inches".
    static func proseSnow(_ cm: Double, _ unit: TempUnit, rough: Bool = false) -> String {
        switch unit {
        case .c: "\(metric(cm, rough)) cm"
        case .f: proseInches(cm / cmPerInch)
        }
    }

    /// For VoiceOver: "0.6 millimetres", "0.02 inches".
    static func spokenRain(_ mm: Double, _ unit: TempUnit, rough: Bool = false) -> String {
        switch unit {
        case .c: "\(metric(mm, rough)) millimetres"
        case .f: proseRain(mm, unit)
        }
    }

    /// "3 centimetres of snow", "1.2 inches of snow".
    static func spokenSnow(_ cm: Double, _ unit: TempUnit, rough: Bool = false) -> String {
        switch unit {
        case .c: "\(metric(cm, rough)) centimetres of snow"
        case .f: "\(proseSnow(cm, unit)) of snow"
        }
    }

    private static func metric(_ v: Double, _ rough: Bool) -> String {
        if rough && v > 0 { return "\(max(1, roundToInt(v)))" }
        if v >= 9.95 { return "\(roundToInt(v))" }
        return formatFixed(v, 1).removingSuffix(".0")
    }

    /// "0.02", "0.15", "0.7" below an inch (two decimals, a trailing zero dropped), "1.2" and "3" from one. Never
    /// "0.00": the smallest amount shown (0.1 mm) still reads as 0.01.
    private static func inches(_ v: Double) -> String {
        if v <= 0 { return "0" }
        if v < 0.995 { return formatFixed(max(v, 0.01), 2).trimmingTrailing("0").removingSuffix(".") }
        return formatFixed(v, 1).removingSuffix(".0")
    }

    private static func proseInches(_ v: Double) -> String {
        let s = inches(v)
        return s == "1" ? "1 inch" : "\(s) inches"
    }

    // MARK: Hours

    static func isSnowHour(_ hour: HourForecast) -> Bool { isSnow(hour.snowCm, hour.precipMm, minCm: snowHourMinCm) }

    /// The amount for an hour's cell ("0.6 mm", "0.4 cm") from [rain], the hour stamped at the end of the cell's
    /// hour; nil when [classify] says it isn't worth a number, or it's missing.
    static func hourAmount(_ rain: HourForecast, _ unit: TempUnit) -> String? {
        guard classify(rain.precipChance, rain.precipMm).amountShown else { return nil }
        return isSnowHour(rain) ? formatSnow(rain.snowCm!, unit) : formatRain(rain.precipMm!, unit)
    }

    /// The same, spoken: "about 0.6 millimetres".
    static func hourAmountSpoken(_ rain: HourForecast, _ unit: TempUnit) -> String? {
        guard classify(rain.precipChance, rain.precipMm).amountShown else { return nil }
        return isSnowHour(rain) ? "about \(spokenSnow(rain.snowCm!, unit))" : "about \(spokenRain(rain.precipMm!, unit))"
    }

    // MARK: Days

    static func isSnowDay(_ day: DaySummary) -> Bool { isSnow(day.snowSumCm, day.precipSumMm, minCm: snowDayMinCm) }

    /// The day's amount for the end of its 10-day row and the hero pill ("4 mm", "3 cm" of snow; "2 mm" rounded when
    /// the chance is low), or nil when there's too little to mention.
    static func dayAmount(_ rain: DayRain, _ unit: TempUnit) -> String? {
        if !rain.amountShown { return nil }
        if rain.showsSnow { return formatSnow(rain.snowCm, unit, rough: rain.rough) }
        if rain.rough || rain.totalMm >= dayTotalMinMm { return formatRain(rain.totalMm, unit, rough: rain.rough) }
        return nil
    }

    /// The same, spoken: "about 4 millimetres", "about 3 centimetres of snow", "up to 2 millimetres".
    static func dayAmountSpoken(_ rain: DayRain, _ unit: TempUnit) -> String? {
        if dayAmount(rain, unit) == nil { return nil }
        let lead = rain.rough ? "up to" : "about"
        return rain.showsSnow ? "\(lead) \(spokenSnow(rain.snowCm, unit, rough: rain.rough))"
            : "\(lead) \(spokenRain(rain.totalMm, unit, rough: rain.rough))"
    }

    /// The day's headline: "Rain likely · about 12 mm over 6 hours", "Showers possible · a few drops", "A small chance
    /// of rain · up to 2 mm over 6 hours", "Rain unlikely".
    static func verdict(_ rain: DayRain, _ unit: TempUnit) -> String {
        if rain.dry { return "Rain unlikely" }
        let word = rain.word.word
        let head: String
        switch likelihood(rain.chance) {
        case .likely: head = "\(word) likely"
        case .possible: head = "\(word) possible"
        case .small, .unlikely: head = "A small chance of \(word.lowercased())"
        }
        return [head, amountPhrase(rain, unit)].compactMap { $0 }.joined(separator: " · ")
    }

    private static func amountPhrase(_ rain: DayRain, _ unit: TempUnit) -> String? {
        if !rain.amountShown { return nil }
        let lead = rain.rough ? "up to" : "about"
        let hours = rain.wetHours > 0 ? " over \(plural(rain.wetHours, "hour"))" : ""
        let amount: String
        if rain.mix == .rainAndSnow {
            let snow = "\(proseSnow(rain.snowCm, unit, rough: rain.rough)) of snow"
            amount = rain.rainMm < fewDropsMm ? "a few drops of rain and \(lead) \(snow)"
                : "\(lead) \(proseRain(rain.rainMm, unit, rough: rain.rough)) of rain and \(snow)"
        } else if rain.showsSnow {
            amount = "\(lead) \(proseSnow(rain.snowCm, unit, rough: rain.rough))"
        } else if !rain.rough && rain.totalMm < fewDropsMm {
            amount = "a few drops"
        } else {
            amount = "\(lead) \(proseRain(rain.totalMm, unit, rough: rain.rough))"
        }
        return amount + hours
    }

    /// "Carries on after midnight: about 12 mm by 7 AM Friday."
    static func carryOnLine(_ next: RainPeriod, _ unit: TempUnit) -> String {
        let call = next.call
        let lead = next.rough ? "up to" : "about"
        let amount: String
        if !call.amountShown { amount = "a \(next.chance)% chance" }
        else if next.snow { amount = "\(lead) \(proseSnow(next.snowCm, unit, rough: next.rough)) of snow" }
        else if !next.rough && next.totalMm < fewDropsMm { amount = "a few drops" }
        else { amount = "\(lead) \(proseRain(next.totalMm, unit, rough: next.rough))" }
        return "Carries on after midnight: \(amount) by \(formatHour(next.labelEnd)) \(weekdayName(next.labelEnd.date))."
    }

    /// Everything about a day's rain: the day's chance, its counted amount and hours, how it's judged, its parts
    /// (before sunrise, daytime, evening), when it falls, and how much of the next day's first part carries on after
    /// midnight. The figures are the sum of the parts that aren't dry, so the parts add up to the verdict exactly.
    /// Without hourly amounts for the whole day, the day's own daily figures stand in.
    static func dayRain(_ forecast: Forecast, _ date: LocalDate) -> DayRain {
        let day = forecast.day(date)
        let hours = forecast.hoursOf(date)
        let parts = dayParts(day, date)
        let periods = !hours.isEmpty && hours.allSatisfy({ $0.precipMm != nil }) ? parts.periods(hours) : []
        let counted = periods.filter { !$0.dry }
        let countedHours = hours.filter { h in counted.contains { $0.contains(h.time) } }
        let complete = hours.count == hoursPerDay && !periods.isEmpty && periods.allSatisfy { $0.complete }
        let carryOn: RainPeriod? = forecast.day(date.plusDays(1)).flatMap { next in
            let nextHours = forecast.hoursOf(next.date)
            if nextHours.isEmpty || nextHours.contains(where: { $0.precipMm == nil }) { return nil }
            guard let first = dayParts(next, next.date).periods(nextHours).first, first.complete, !first.dry else { return nil }
            return first
        }
        let timing = timing(countedHours, parts)
        if !complete {
            return fromDaily(day, date, parts, hours, periods, countedHours, timing, carryOn)
        }
        let snowParts = counted.filter { $0.snow }
        let rainParts = counted.filter { !$0.snow && $0.totalMm >= hourAmountMinMm }
        let chance = hours.map(\.precipChance).max() ?? 0
        let totalMm = counted.reduce(0) { $0 + $1.totalMm }
        let mix: Mix = snowParts.isEmpty ? .rain : rainParts.isEmpty ? .snow : .rainAndSnow
        return DayRain(
            date: date,
            code: day?.code ?? 0,
            chance: chance,
            totalMm: totalMm,
            rainMm: rainParts.reduce(0) { $0 + $1.totalMm },
            snowCm: snowParts.reduce(0) { $0 + $1.snowCm },
            wetHours: counted.reduce(0) { $0 + $1.wetHours },
            call: classify(chance, totalMm),
            mix: mix,
            complete: true,
            parts: parts,
            hours: hours,
            periods: periods,
            counted: countedHours,
            timing: timing,
            carryOn: carryOn
        )
    }

    private static func fromDaily(
        _ day: DaySummary?, _ date: LocalDate, _ parts: DayParts, _ hours: [HourForecast], _ periods: [RainPeriod],
        _ counted: [HourForecast], _ timing: Timing?, _ carryOn: RainPeriod?
    ) -> DayRain {
        let chance = day?.precipChance ?? 0
        let call = classify(chance, day?.precipSumMm)
        let dry = call.kind == .dry
        let snow = day.map(isSnowDay) ?? false
        let totalMm = dry ? 0 : day?.precipSumMm ?? 0
        return DayRain(
            date: date,
            code: day?.code ?? 0,
            chance: chance,
            totalMm: totalMm,
            rainMm: snow ? 0 : totalMm,
            snowCm: snow && !dry ? day?.snowSumCm ?? 0 : 0,
            wetHours: dry ? 0 : day?.precipHours.map(roundToInt) ?? 0,
            call: call,
            mix: snow ? .snow : .rain,
            complete: false,
            parts: parts,
            hours: hours,
            periods: periods,
            counted: counted,
            timing: timing,
            carryOn: carryOn
        )
    }

    /// The day's parts: sunrise and sunset rounded to the hour, or 7 AM and 7 PM when the sun doesn't rise or set (or
    /// the times are missing), kept inside the day so every hour lands in exactly one part.
    private static func dayParts(_ day: DaySummary?, _ date: LocalDate) -> DayParts {
        let daylight = day?.daylight ?? .unknown
        let normal = daylight == .normal
        let rise = clamp(normal ? nearestHour(day!.sunrise!) : date.atTime(7), date.atTime(1), date.atTime(23))
        let set = clamp(normal ? nearestHour(day!.sunset!) : date.atTime(19), rise, date.atTime(23))
        return DayParts(date: date, sunrise: rise, sunset: set, daylight: daylight)
    }

    private static func clamp(_ t: LocalDateTime, _ lo: LocalDateTime, _ hi: LocalDateTime) -> LocalDateTime {
        min(max(t, lo), hi)
    }

    private static func nearestHour(_ t: LocalDateTime) -> LocalDateTime {
        t.minute >= 30 ? t.truncatedToHour.plusHours(1) : t.truncatedToHour
    }

    /// When in the day the rain in [hours] falls: mostly in one part of the day, in two, on and off all day, or
    /// before sunrise and then clearing; with the heaviest hour when one stands out. Nil when the hours hold no rain.
    static func timing(_ hours: [HourForecast], _ parts: DayParts) -> Timing? {
        let amounts = hours.map { ($0.time, $0.precipMm ?? 0) }
        let total = amounts.reduce(0) { $0 + $1.1 }
        if total < hourAmountMinMm { return nil }
        let shares: [(PartOfDay, Double)] = PartOfDay.allCases.map { part in
            (part, amounts.filter { parts.partOf($0.0) == part }.reduce(0) { $0 + $1.1 } / total)
        }
        let wetHours = amounts.filter { $0.1 >= hourAmountMinMm }.count
        var peakIndex = 0
        for i in amounts.indices where amounts[i].1 > amounts[peakIndex].1 { peakIndex = i }
        let (peakStamp, peakMm) = amounts[peakIndex]
        // The stamp ends the hour the rain falls in: name that hour.
        let peak = wetHours >= 2 && total >= fewDropsMm && peakMm / total >= peakShare ? peakStamp.minusHours(1) : nil
        var main = shares[0]
        for s in shares where s.1 > main.1 { main = s }
        let wetParts = shares.filter { $0.1 >= someShare }.map(\.0)
        let sunrise = parts.daylight == .normal
        if main.0 == .early && main.1 > 0.95 {
            return Timing(shape: .clearingByMorning, parts: [.early], peak: nil, sunrise: sunrise)
        }
        if main.1 >= mostlyShare { return Timing(shape: .mostly, parts: [main.0], peak: peak, sunrise: sunrise) }
        if wetParts.count >= 3 { return Timing(shape: .onAndOff, parts: wetParts, peak: peak, sunrise: sunrise) }
        return Timing(shape: .mostly, parts: wetParts.isEmpty ? [main.0] : wetParts, peak: peak, sunrise: sunrise)
    }

    /// "Mostly in the afternoon, heaviest around 4 PM." · "On and off all day." · "Before sunrise, clearing by morning."
    static func timingSentence(_ timing: Timing) -> String {
        let base: String
        switch timing.shape {
        case .clearingByMorning: return "\(timing.early.capitalizedFirst), clearing by morning."
        case .onAndOff: base = "On and off all day"
        case .mostly: base = "Mostly " + joinParts(timing.parts) { $0 == .early ? timing.early : $0.phrase }
        }
        let peak = timing.peak.map { ", heaviest around \(formatHour($0))" } ?? ""
        return "\(base)\(peak)."
    }

    /// The same for today: "mostly this evening", "on and off", "before sunrise, clearing by morning".
    static func timingToday(_ timing: Timing) -> String {
        switch timing.shape {
        case .clearingByMorning: "\(timing.early), clearing by morning"
        case .onAndOff: "on and off"
        case .mostly: "mostly " + joinParts(timing.parts) { $0 == .early ? timing.early : $0.today }
        }
    }

    /// "in the morning and afternoon", "before sunrise and in the morning": the article isn't repeated.
    private static func joinParts(_ parts: [PartOfDay], _ phrase: (PartOfDay) -> String) -> String {
        let first = phrase(parts[0])
        let article = ["in the ", "this "].first { first.hasPrefix($0) }
        let rest = parts.dropFirst().map { p in article.map { phrase(p).removingPrefix($0) } ?? phrase(p) }
        return ([first] + rest).joined(separator: " and ")
    }

    /// "about 4.1 mm over 5 hours, mostly this evening" for [span] of [rain]'s day; "a few drops", "up to 2 mm".
    static func spanPhrase(_ span: RainSpan, _ rain: DayRain, _ unit: TempUnit) -> String {
        let lead = rain.rough ? "up to" : "about"
        let amount: String
        if rain.showsSnow && span.snowCm >= snowHourMinCm { amount = "\(lead) \(proseSnow(span.snowCm, unit, rough: rain.rough))" }
        else if !rain.rough && span.mm < fewDropsMm { amount = "a few drops" }
        else { amount = "\(lead) \(proseRain(span.mm, unit, rough: rain.rough))" }
        let hours = span.wetHours > 0 ? " over \(plural(span.wetHours, "hour"))" : ""
        let timing = span.timing.map { ", \(timingToday($0))" } ?? ""
        return "\(amount)\(hours)\(timing)"
    }

    static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
}

enum Likelihood: Sendable {
    case likely, possible, small, unlikely

    var word: String {
        switch self {
        case .likely: "likely"
        case .possible: "possible"
        case .small: "a small chance"
        case .unlikely: "unlikely"
        }
    }
}

/// How a day (or part of one, or an hour) is judged: dry, possible ([mixed]) or likely, a wet day ([wet]).
enum DayKind: Sendable { case wet, mixed, dry }

/// [Precip.classify]'s answer: the [kind] of day, and whether its amount is worth a number.
struct RainCall: Equatable, Sendable {
    let kind: DayKind
    let amountShown: Bool
    var dry: Bool { kind == .dry }
}

enum PrecipKind: Sendable {
    case rain, showers, snow, rainAndSnow, thunderstorms

    var word: String {
        switch self {
        case .rain: "Rain"
        case .showers: "Showers"
        case .snow: "Snow"
        case .rainAndSnow: "Rain and snow"
        case .thunderstorms: "Thunderstorms"
        }
    }
}

/// What a day's counted parts hold: only rain, only snow, or some of each.
enum Mix: Sendable { case rain, snow, rainAndSnow }

/// The day's parts for timing words (the daytime split at noon).
enum PartOfDay: CaseIterable, Sendable {
    case early, morning, afternoon, evening

    var phrase: String {
        switch self {
        case .early: "before sunrise"
        case .morning: "in the morning"
        case .afternoon: "in the afternoon"
        case .evening: "in the evening"
        }
    }

    var today: String {
        switch self {
        case .early: "before sunrise"
        case .morning: "this morning"
        case .afternoon: "this afternoon"
        case .evening: "this evening"
        }
    }
}

/// The bounds of a day's parts, as stamps (start, end]: before sunrise up to [sunrise], daytime up to [sunset], then
/// the evening. [start] is 11 PM the evening before, so the 00:00 stamp is the day's first.
struct DayParts: Sendable {
    let date: LocalDate
    let sunrise: LocalDateTime
    let sunset: LocalDateTime
    let daylight: Daylight

    var start: LocalDateTime { date.atStartOfDay.minusHours(1) }
    var end: LocalDateTime { date.atTime(23) }

    func partOf(_ stamp: LocalDateTime) -> PartOfDay {
        let noon = max(date.atTime(12), sunrise)
        if stamp <= sunrise { return .early }
        if stamp <= noon { return .morning }
        if stamp <= max(sunset, noon) { return .afternoon }
        return .evening
    }

    /// The rows: "Before sunrise", "Daytime" (sunrise to sunset), "Evening" (sunset to midnight). When the sun doesn't
    /// rise or set they run 7 AM to 7 PM and read "Early", "Midday" and "Evening". Parts without an hour are left out.
    func periods(_ hours: [HourForecast]) -> [RainPeriod] {
        let sun = daylight == .normal
        let polar = daylight == .polarNight || daylight == .midnightSun
        return [
            period(hours, sun ? "Before sunrise" : "Early", start, sunrise),
            period(hours, polar ? "Midday" : "Daytime", sunrise, sunset),
            period(hours, "Evening", sunset, end),
        ].compactMap { $0 }
    }

    private func period(_ hours: [HourForecast], _ name: String, _ from: LocalDateTime, _ to: LocalDateTime) -> RainPeriod? {
        let expected = (to.seconds - from.seconds) / 3_600
        if expected <= 0 { return nil }
        let inside = hours.filter { $0.time > from && $0.time <= to }
        if inside.isEmpty { return nil }
        return RainPeriod(
            name: name,
            date: date,
            start: from,
            end: to,
            complete: inside.count >= expected,
            chance: inside.map(\.precipChance).max() ?? 0,
            totalMm: inside.reduce(0) { $0 + ($1.precipMm ?? 0) },
            snowCm: inside.reduce(0) { $0 + ($1.snowCm ?? 0) },
            wetHours: inside.filter { ($0.precipMm ?? 0) >= Precip.hourAmountMinMm }.count
        )
    }
}

enum TimingShape: Sendable { case mostly, onAndOff, clearingByMorning }

/// When a day's rain falls: its [shape], the [parts] of the day involved, and the [peak] hour (the hour the rain
/// falls in) if one stands out. [sunrise] is false on a day the sun doesn't rise, which has early hours instead.
struct Timing: Sendable {
    let shape: TimingShape
    let parts: [PartOfDay]
    let peak: LocalDateTime?
    var sunrise: Bool = true

    var early: String { sunrise ? PartOfDay.early.phrase : "in the early hours" }
}

/// Rain over a part of [date]: the stamps after [start] up to [end], with their highest hourly chance, their total,
/// their snow and the hours with at least 0.1 mm. [complete] once every hour of it is in the data.
struct RainPeriod: Sendable {
    let name: String
    let date: LocalDate
    let start: LocalDateTime
    let end: LocalDateTime
    let complete: Bool
    let chance: Int
    let totalMm: Double
    let snowCm: Double
    let wetHours: Int

    /// Judged on its own hours, by the same rule as a day.
    var call: RainCall { Precip.classify(chance, totalMm) }
    var dry: Bool { call.dry }
    /// Under 20% but with a real amount, so the amount is rounded and reads "up to".
    var rough: Bool { chance < Precip.dayChanceMin && call.amountShown }
    /// Mostly snow.
    var snow: Bool { Precip.isSnow(snowCm, totalMm, minCm: Precip.snowDayMinCm) }
    /// "12 AM" for a part that starts the day.
    var labelStart: LocalDateTime { start < date.atStartOfDay ? date.atStartOfDay : start }
    /// "12 AM" (midnight) for a part that ends the day.
    var labelEnd: LocalDateTime { end >= date.atTime(23) ? date.plusDays(1).atStartOfDay : end }

    func contains(_ stamp: LocalDateTime) -> Bool { stamp > start && stamp <= end }

    /// "90% · 11 mm · 5 h", "40% · 3 cm snow · 4 h", "15% · up to 2 mm · 6 h", "45%". [snowWord] false drops "snow".
    func describe(_ unit: TempUnit, snowWord: Bool = true) -> String {
        [
            "\(chance)%",
            amount(unit).map { snow && snowWord ? "\($0) snow" : $0 },
            wetHours > 0 && call.amountShown ? "\(wetHours) h" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }

    /// "40 percent chance, about 3 millimetres, over 4 hours".
    func spoken(_ unit: TempUnit) -> String {
        let lead = rough ? "up to" : "about"
        let amount: String?
        if !call.amountShown { amount = nil }
        else if snow { amount = "\(lead) \(Precip.spokenSnow(snowCm, unit, rough: rough))" }
        else if rough || totalMm >= Precip.dayTotalMinMm { amount = "\(lead) \(Precip.spokenRain(totalMm, unit, rough: rough))" }
        else { amount = "a few drops" }
        return [
            "\(chance) percent chance",
            amount,
            wetHours > 0 && call.amountShown ? "over \(Precip.plural(wetHours, "hour"))" : nil,
        ].compactMap { $0 }.joined(separator: ", ")
    }

    private func amount(_ unit: TempUnit) -> String? {
        let lead = rough ? "up to " : ""
        if !call.amountShown { return nil }
        if snow { return lead + Precip.formatSnow(snowCm, unit, rough: rough) }
        if rough || totalMm >= Precip.dayTotalMinMm { return lead + Precip.formatRain(totalMm, unit, rough: rough) }
        return "a few drops"
    }
}

/// Part of a day's counted rain, such as what's still to come: water, snow, wet hours and when it falls.
struct RainSpan: Sendable {
    let mm: Double
    let snowCm: Double
    let wetHours: Int
    let timing: Timing?
}

/// Everything about one day's rain or snow; see [Precip.dayRain].
struct DayRain: Sendable {
    let date: LocalDate
    /// The day's weather code, for "Showers" and "Thunderstorms".
    let code: Int
    /// The day's highest hourly chance.
    let chance: Int
    /// The counted water, mm: the parts that aren't dry. 0 on a dry day.
    let totalMm: Double
    /// The water in the parts that are mostly rain, and the snow (cm) in those that are mostly snow.
    let rainMm: Double
    let snowCm: Double
    /// Counted hours with at least 0.1 mm.
    let wetHours: Int
    let call: RainCall
    let mix: Mix
    /// Whether the hourly data covers the whole day with amounts.
    let complete: Bool
    let parts: DayParts
    /// The day's stamps, 00:00 to 23:00.
    let hours: [HourForecast]
    /// The day's parts in order, dry ones included; empty without hourly amounts.
    let periods: [RainPeriod]
    /// The stamps of the parts that aren't dry.
    let counted: [HourForecast]
    let timing: Timing?
    /// The next day's first part (midnight to its sunrise), when it isn't dry.
    let carryOn: RainPeriod?

    var kind: DayKind { call.kind }
    var dry: Bool { call.dry }
    var amountShown: Bool { call.amountShown && !dry }
    /// Under 20% but with a real amount, so the amount is rounded and reads "up to".
    var rough: Bool { chance < Precip.dayChanceMin && call.amountShown }
    /// Whether the day's amount is shown as snow: most of the counted water fell as snow.
    var showsSnow: Bool { mix == .snow || (mix == .rainAndSnow && Precip.isSnow(snowCm, totalMm, minCm: Precip.snowDayMinCm)) }
    /// "Rain" or "Snow", for labels like the hero pill.
    var noun: String { showsSnow ? "Snow" : "Rain" }

    /// The day page card's title: "Rain", "Snow" or "Rain and snow".
    var title: String {
        switch mix {
        case .rain: "Rain"
        case .snow: "Snow"
        case .rainAndSnow: "Rain and snow"
        }
    }

    /// What falls: storms, snow, showers or rain, from the day's weather code and its mix.
    var word: PrecipKind {
        if (95...99).contains(code) { return .thunderstorms }
        if mix == .snow { return .snow }
        if mix == .rainAndSnow { return .rainAndSnow }
        if (80...82).contains(code) { return .showers }
        return .rain
    }

    /// The parts to list on a day page: those that aren't dry, once the data covers the whole day.
    var rows: [RainPeriod] { complete && !dry ? periods.filter { !$0.dry } : [] }

    /// The counted rain from the hour that ends after [now] on (today's "still to come").
    func stillToCome(_ now: LocalDateTime) -> RainSpan {
        let ahead = counted.filter { $0.time > now }
        let snowParts = periods.filter { !$0.dry && $0.snow }
        return RainSpan(
            mm: ahead.reduce(0) { $0 + ($1.precipMm ?? 0) },
            snowCm: ahead.filter { h in snowParts.contains { $0.contains(h.time) } }.reduce(0) { $0 + ($1.snowCm ?? 0) },
            wetHours: ahead.filter { ($0.precipMm ?? 0) >= Precip.hourAmountMinMm }.count,
            timing: Precip.timing(ahead, parts)
        )
    }

    /// The whole day's counted rain as a span.
    var whole: RainSpan { RainSpan(mm: totalMm, snowCm: snowCm, wetHours: wetHours, timing: timing) }
}
