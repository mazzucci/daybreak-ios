import Foundation

/// "This week": plain advice about being outside, from rules and the forecast alone (no model), ported from Android's
/// domain/WeekOutlook.kt. Each of the next [Outlook.days] days (today and the six after it; days 8 to 10 are too
/// uncertain) gets a score from 0 to 100 for time outside, an [OutlookTier], and the page gets one line about today
/// ("Great day to be outside, best 1–5 PM") and up to two about the week ("Rainy spell from tomorrow until Monday",
/// "Saturday is the best day this week").
///
/// **A day's score.** Its daylight hours within waking hours (6 AM to 10 PM) are scored one by one with
/// [OutdoorScorer] and [WeatherProfile.outdoor], and the day takes the average of its best run of [Outlook.runHours]
/// hours, so one nice hour doesn't make a good day. Each hour is judged on what Open-Meteo says about it (see
/// [withRainDuring] for which stamp that is). Today counts only the daylight still ahead; with fewer than
/// [Outlook.minLightHours] hours left it has no score, and the today line looks at tomorrow. Under polar night, and
/// on a day with under [Outlook.minLightHours] hours of daylight, the waking hours stand in for daylight, capped below
/// "good"; under the midnight sun the waking hours are the daylight. A day with rain in at least a third of its hours
/// is capped below "good" too, however dry its best run. A day the hourly data doesn't reach is scored from its daily
/// figures as one stand-in hour.
///
/// **Rain words** come from [Precip] and never contradict it: a day [Precip] calls dry is never rainy here, a day is
/// wet ([DayKind.wet], a spell's day) only when [Precip.dayRain] says so, the strip speaks the day page's own verdict
/// ("rain likely", "showers possible"), and "dry until 2 PM" needs every hour before 2 PM to be dry by
/// [Precip.classify]. The lines don't contradict each other either: today counts towards a spell only when what's
/// still to come today is wet, the day the today line calls good or great is never part of one, "Dry again" follows
/// only a wet today line, and the best day is never a wet day or a day inside the spell.
///
/// Copy is English with US numbers and day names, in one voice and without semicolons; temperatures and wind follow
/// the user's unit, as elsewhere.
enum Outlook {
    /// Today and the six days after it.
    static let days = 7

    /// Tier floors, tuned on the fixtures. Great needs dry, calm hours from about 6 °C to 32 °C (a 40% chance or a
    /// 3 °C morning is only good); good allows one small dent, such as 0 °C or a breezy hour; mixed is about one rule
    /// broken (a drizzly hour, a gale's gusts); below that it's raining, stormy, freezing or too hot.
    static let greatMin = 80
    static let goodMin = 60
    static let mehMin = 35

    /// A day is as good as its best run of this many daylight hours.
    static let runHours = 3

    /// Today needs at least this many daylight hours ahead to get a score of its own; a day with fewer light waking
    /// hours than this in all is judged like polar night.
    static let minLightHours = 2

    /// Hours next to the best run within this many points of it widen "best 1–5 PM".
    static let stretchDrop = 10

    /// The best day is named only when it's this far over the week's median, and at least good.
    static let bestMargin = 10

    /// A weekend day this close to the best day is named instead: that's when most people can go.
    static let weekendSlack = 5

    /// Highs from here make a heat spell (two days or more in a row).
    static let heatSpellC = 30.0

    /// From here (the profile's limit) a day's peak gets "Hot day: 34° by 3 PM".
    static let hotC = 32.0

    /// A high this much below today's makes a cold snap, when it's under [coldSnapHighC].
    static let coldDropC = 8.0
    static let coldSnapHighC = 16.0

    /// Gusts (or, without them, wind) from here (gale force) get a line of their own.
    static let galeGustKmh = 70.0

    /// The share of the hours with rain that makes it "rain most of the day".
    static let mostOfDay = 0.6

    /// A day with rain in at least this share of its scored hours is mixed at best.
    static let wetCapShare = 1.0 / 3

    /// A morning low under this is frost: it rounds to −1° or lower in °C (and 31° or lower in °F), so the line never
    /// reads "down to 0°".
    static let frostC = -0.5

    /// A morning's low is the lowest of the stamps from midnight to this hour.
    static let morningUntil = 9

    /// "First frost" needs at least this many frost-free mornings before it in the data; otherwise it's "Frost".
    static let firstFrostAfter = 5

    /// Waking hours: hours starting from 6 AM up to 9 PM.
    static let wakingFrom = 6
    static let wakingUntil = 22
}

/// How good a day is for being outside, by its score.
enum OutlookTier: Sendable {
    case great, good, meh, stayIn

    /// For the explanation: "Great", "Stay in".
    var word: String {
        switch self {
        case .great: "Great"
        case .good: "Good"
        case .meh: "Mixed"
        case .stayIn: "Stay in"
        }
    }

    /// For screen readers, after the day's name: "Saturday, great for being outside".
    var spoken: String {
        switch self {
        case .great: "great for being outside"
        case .good: "good for being outside"
        case .meh: "a mixed day"
        case .stayIn: "one for staying in"
        }
    }

    var atLeastGood: Bool { self == .great || self == .good }

    static func of(_ score: Int) -> OutlookTier {
        if score >= Outlook.greatMin { return .great }
        if score >= Outlook.goodMin { return .good }
        if score >= Outlook.mehMin { return .meh }
        return .stayIn
    }
}

/// What holds a day back most: rain (or snow, or storms), wind, heat or cold; darkness under polar night.
enum OutlookTopic: Sendable { case wet, wind, heat, cold, dark }

/// Which rule a line comes from, highest priority first for the week lines.
enum LineKind: Sendable { case day, wetSpell, dryTurn, bestDay, bigWind, heatSpell, coldSnap, frost, dryWeek }

/// One line of the outlook: [text] as shown, [spoken] for screen readers (both temperature units, "to" for ranges).
/// [date] is the day it's mainly about (a spell's first day, with its last as [end]) and [topic] what it's about, so a
/// week line can skip what the today line says.
struct OutlookLine: Equatable, Sendable {
    let text: String
    let spoken: String
    let kind: LineKind
    var date: LocalDate? = nil
    var topic: OutlookTopic? = nil
    var end: LocalDate? = nil
}

/// A day in the strip. [score] and [tier] are nil for today once there isn't enough daylight left to judge. [rain]
/// is the day's [Precip] kind (a wet day gets a glyph) and [snow] whether its amount is snow; [highC] its high.
struct OutlookDay: Sendable {
    let date: LocalDate
    let score: Int?
    let tier: OutlookTier?
    let isBest: Bool
    let rain: DayKind
    let snow: Bool
    let highC: Double
    /// "Saturday, best day, great for being outside, dry"; "Today, daylight's over, rain likely".
    let spoken: String
}

/// The outlook for a page: the [today] line (always there), 0–2 [week] lines, the [days] of the strip, today first,
/// and the lines in one [spoken] summary. [focus] is the day the today line talks about (today, or tomorrow once
/// today's daylight is over), for the explanation.
struct WeekOutlook: Sendable {
    let today: OutlookLine
    let week: [OutlookLine]
    let days: [OutlookDay]
    let spoken: String
    let focus: DayRead?

    /// The day marked best in the strip (at least good), if any.
    var bestDate: LocalDate? { days.first { $0.isBest }?.date }
}

/// A day's scored hours: daylight (still ahead, for today) within waking hours, in order, or one stand-in from the
/// daily figures ([fromDaily]). [best] is the best run of [Outlook.runHours] hours (fewer when there are fewer) and
/// [stretch] the run around it worth recommending; [score] is [best]'s average, capped below "good" under polar night,
/// on a [shortDay], or when at least a third of the hours are rainy ([mostlyWet]).
struct DayRead: Sendable {
    let date: LocalDate
    let hours: [HourScore]
    let best: [HourScore]
    let stretch: [HourScore]
    let score: Int
    let fromDaily: Bool
    let polarNight: Bool
    var mostlyWet: Bool = false
    /// Under [Outlook.minLightHours] hours of daylight in all, so judged like polar night.
    var shortDay: Bool = false

    var tier: OutlookTier { OutlookTier.of(score) }

    /// Without (enough) daylight: the waking hours stand in for it.
    var dim: Bool { polarNight || shortDay }

    /// The warmest scored hour, for "34° by 3 PM" and "no warmer than 2°".
    var warmest: HourScore { hours.max { $0.hour.tempC < $1.hour.tempC }! }

    var maxGustKmh: Double? { hours.compactMap(\.hour.gustKmh).max() }
    var maxWindKmh: Double? { hours.compactMap(\.hour.windKmh).max() }

    /// The stronger of the gusts and the wind over the scored hours, for the gale rules.
    var peakWindKmh: Double { max(maxGustKmh ?? 0.0, maxWindKmh ?? 0.0) }

    /// Whether a scored hour has a thunderstorm code.
    var stormy: Bool { hours.contains { $0.limits.contains(.storm) } }

    /// What holds the day back most, by how many hours it hits; ties go to rain, then wind, heat and cold. Rain, when
    /// it's [mostlyWet].
    var topic: OutlookTopic? {
        if mostlyWet { return .wet }
        let counts: [(OutlookTopic, Int)] = [
            (.wet, hours.count { h in h.limits.contains { $0 == .storm || $0 == .rain || $0 == .snow } }),
            (.wind, hours.count { $0.limits.contains(.wind) }),
            (.heat, hours.count { $0.limits.contains(.heat) }),
            (.cold, hours.count { $0.limits.contains(.cold) }),
        ].filter { $0.1 > 0 }
        // The most hours; on a tie the earlier topic in the list wins.
        var top: (OutlookTopic, Int)? = nil
        for c in counts where top == nil || c.1 > top!.1 { top = c }
        return top?.0
    }
}

/// The moment the outlook is for, at the forecast's place: the later of the forecast's own time and [clock] (in the
/// forecast's UTC offset, so its stamps line up), to the hour. It moves on at most once an hour, so a screen can work
/// the outlook out again only then, and a forecast fetched at 2 PM and still shown at 8 PM is judged at 8 PM.
func outlookMoment(_ forecast: Forecast, _ clock: Date) -> LocalDateTime {
    let local = LocalDateTime.from(clock, utcOffsetSeconds: forecast.utcOffsetSeconds).truncatedToHour
    return max(forecast.current.time, local)
}

/// Works out the outlook from [forecast] as of [now] (see [outlookMoment]; the forecast's own time when nil), in
/// [unit]. [weekend] (from [weekendDays]) decides which days count as the weekend when two are about as good. [rains]
/// is [Precip.dayRain] for each of [Forecast.upcomingDays], when the page has already worked it out.
func weekOutlook(
    _ forecast: Forecast,
    _ unit: TempUnit,
    weekend: Set<DayOfWeek> = weekendDays(nil),
    now: LocalDateTime? = nil,
    rains: [DayRain]? = nil,
    profile: WeatherProfile = .outdoor
) -> WeekOutlook {
    let now = now ?? forecast.current.time
    let today = forecast.today.date
    let days = forecast.upcomingDays(Outlook.days)
    let reads = days.map { readDay(forecast, $0, now, profile) }
    let upcoming = forecast.upcomingDays()
    let allRains: [DayRain]
    if let rains, rains.map(\.date) == upcoming.map(\.date) { allRains = rains }
    else { allRains = upcoming.map { Precip.dayRain(forecast, $0.date) } }

    let todayRead = reads.first.flatMap { $0 }
    let focusIndex = todayRead != nil ? 0 : 1
    let focus = focusIndex < reads.count ? reads[focusIndex] : nil
    let todayLine = if let focus { dayLine(focus, allRains[focusIndex], tomorrow: focusIndex == 1, unit) }
        else { line(.day, unit, today) { _ in "Daylight's over for today" } }

    let ctx = Context(forecast: forecast, now: now, today: today, days: days, reads: reads, rains: allRains,
                      weekend: weekend, focusIndex: focusIndex, todayLine: todayLine)
    let spell = ctx.spell()
    let best = ctx.bestDay(spell)
    let candidates = [
        spell.map { ctx.wetSpellLine($0, unit) },
        ctx.dryTurn(unit, spell),
        best.flatMap { ctx.bestDayLine($0, unit) },
        ctx.bigWind(unit, said: todayLine.topic == .wind ? todayLine.date : nil),
        ctx.heatSpell(unit),
        ctx.coldSnap(unit) ?? ctx.frost(unit),
    ].compactMap { $0 }
    let week = candidates.isEmpty ? [ctx.dryWeek(unit)].compactMap { $0 } : Array(candidates.prefix(2))

    let bestDate = best.flatMap { $0.tier.atLeastGood ? $0.date : nil }
    let outlookDays = days.enumerated().map { i, day in
        let read = reads[i]
        let rain = allRains[i]
        let name = outlookDayName(day.date, today).capitalizedFirst
        let isBest = day.date == bestDate
        return OutlookDay(
            date: day.date,
            score: read?.score,
            tier: read?.tier,
            isBest: isBest,
            rain: rain.kind,
            snow: rain.showsSnow,
            highC: day.highC,
            spoken: [
                name,
                isBest ? "best day" : nil,
                read?.tier.spoken ?? (daylightOver(forecast, day, now) ? "daylight's over" : "not enough daylight left"),
                rainWords(rain, unit),
            ].compactMap { $0 }.joined(separator: ", ")
        )
    }
    let spoken = ([todayLine] + week).map(\.spoken).joined(separator: ". ") + "."
    return WeekOutlook(today: todayLine, week: week, days: outlookDays, spoken: spoken, focus: focus)
}

/// Whether [now] is past [day]'s sunset (when it has one) or the end of its waking hours.
private func daylightOver(_ forecast: Forecast, _ day: DaySummary, _ now: LocalDateTime) -> Bool {
    if now >= day.date.atTime(Outlook.wakingUntil, 0) { return true }
    switch day.daylight {
    case .normal: return now >= day.sunset!
    case .unknown: return forecast.isNight(now) && now.hour >= 12 // the fixed 8 PM fallback sunset
    case .polarNight, .midnightSun: return false
    }
}

/// "dry", or the day page's verdict without its amount: "rain likely", "showers possible", "a small chance of snow".
func rainWords(_ rain: DayRain, _ unit: TempUnit) -> String {
    if rain.dry { return "dry" }
    let head = Precip.verdict(rain, unit).components(separatedBy: " · ")[0]
    return head.prefix(1).lowercased() + head.dropFirst()
}

/// "today", "tomorrow", a weekday within six days ("Saturday"), then "next Monday". Lower case; capitalise at the
/// start of a sentence.
func outlookDayName(_ date: LocalDate, _ today: LocalDate) -> String {
    let days = date.epochDay - today.epochDay
    let weekday = weekdayName(date)
    switch days {
    case 0: return "today"
    case 1: return "tomorrow"
    case 2...6: return weekday
    default: return "next \(weekday)"
    }
}

// MARK: - Scoring a day

func readDay(_ forecast: Forecast, _ day: DaySummary, _ now: LocalDateTime, _ profile: WeatherProfile) -> DayRead? {
    let isToday = day.date == forecast.today.date
    let polarNight = day.daylight == .polarNight
    let all = forecast.hoursOf(day.date)
    if all.isEmpty { return isToday ? nil : fromDaily(day, profile) }
    let waking = all.filter { (Outlook.wakingFrom..<Outlook.wakingUntil).contains($0.time.hour) }
    let light = waking.filter { !OutdoorScorer.isDark($0, forecast) }
    // A whole day of waking hours with hardly any daylight (sunrise 11:40, sunset 12:20) is judged like polar night.
    let shortDay = !polarNight && waking.count == Outlook.wakingUntil - Outlook.wakingFrom && light.count < Outlook.minLightHours
    let dim = polarNight || shortDay
    // Today's light is over once the sun has set or the waking hours have ended, whatever stands in for it.
    if isToday && dim && daylightOver(forecast, day, now) { return nil }
    // An hour still counts as ahead while its middle is.
    let candidates = dim ? waking : light
    let ahead = isToday ? candidates.filter { $0.time.plusMinutes(30) > now } : candidates
    if ahead.count < Outlook.minLightHours { return isToday ? nil : fromDaily(day, profile) }
    let scored = ahead.map { OutdoorScorer.score(withRainDuring(forecast, $0), profile, dark: false) }
    let run = min(Outlook.runHours, scored.count)
    // The earliest of the best runs, so a tie goes to the sooner hours.
    func runSum(_ i: Int) -> Int { scored[i..<(i + run)].reduce(0) { $0 + $1.score } }
    var bestStart = 0
    for i in 0...(scored.count - run) where runSum(i) > runSum(bestStart) { bestStart = i }
    let best = Array(scored[bestStart..<(bestStart + run)])
    let average = Double(best.reduce(0) { $0 + $1.score }) / Double(best.count)
    var from = bestStart
    var to = bestStart + run // exclusive
    let floor = average - Double(Outlook.stretchDrop)
    while from > 0 && Double(scored[from - 1].score) >= floor { from -= 1 }
    while to < scored.count && Double(scored[to].score) >= floor { to += 1 }
    // A poor hour at the edge of the best run isn't part of what we recommend.
    while to - from > 1 && Double(scored[from].score) < floor { from += 1 }
    while to - from > 1 && Double(scored[to - 1].score) < floor { to -= 1 }
    // Rain in a third of the hours makes a mixed day at best, however dry the rest, as does a day without the sun.
    let mostlyWet = Double(scored.count { isRainyHour($0.hour) }) >= Outlook.wetCapShare * Double(scored.count)
    let rounded = roundToInt(average)
    let score = dim || mostlyWet ? min(rounded, Outlook.goodMin - 1) : rounded
    return DayRead(date: day.date, hours: scored, best: best, stretch: Array(scored[from..<to]), score: score,
                   fromDaily: false, polarNight: polarNight, mostlyWet: mostlyWet, shortDay: shortDay)
}

/// An hour (with the rain that falls during it) that's rainy: from a 40% chance ("possible"), or wet by [Precip.classify].
private func isRainyHour(_ hour: HourForecast) -> Bool {
    hour.precipChance >= Precip.possible || Precip.classify(hour.precipChance, hour.precipMm).kind == .wet
}

/// The hour starting at [hour] as the outlook judges it, by Open-Meteo's own conventions
/// (https://open-meteo.com/en/docs, the hourly table's "valid time"):
/// - precipitation, snowfall and precipitation_probability are the **preceding hour's** sum and probability, and
///   wind_gusts_10m is the **preceding hour's maximum**: for the hour from H to H + 1 they come from the stamp H + 1
///   ([Forecast.rainDuring]), as the hourly strip's rain lines do;
/// - weather_code, temperature_2m and wind_speed_10m are **instant**, valid at the stamp itself: they stay the hour's
///   own, which is the icon the hourly strip draws in the cell for H. So the strip and the outlook agree on which hour
///   a storm is in.
/// The last hour of the data has no later stamp and keeps its own values.
func withRainDuring(_ forecast: Forecast, _ hour: HourForecast) -> HourForecast {
    guard let next = forecast.rainDuring(hour) else { return hour }
    var h = hour
    h.precipChance = next.precipChance
    h.precipMm = next.precipMm
    h.snowCm = next.snowCm
    h.gustKmh = next.gustKmh ?? hour.gustKmh
    return h
}

/// One stand-in hour at 1 PM from the day's figures: its high, highest chance, code, strongest wind and gusts.
private func fromDaily(_ day: DaySummary, _ profile: WeatherProfile) -> DayRead {
    let stand = HourForecast(
        time: day.date.atTime(13, 0),
        tempC: day.highC,
        precipChance: day.precipChance,
        code: day.code,
        windKmh: day.windMaxKmh,
        gustKmh: day.gustMaxKmh,
        precipMm: day.precipSumMm,
        snowCm: day.snowSumCm
    )
    let scored = [OutdoorScorer.score(stand, profile, dark: false)]
    let first = scored[0].score
    let score = day.daylight == .polarNight ? min(first, Outlook.goodMin - 1) : first
    return DayRead(date: day.date, hours: scored, best: scored, stretch: scored, score: score, fromDaily: true,
                   polarNight: day.daylight == .polarNight)
}

// MARK: - The today line

/// How numbers are written: on screen ("34°", "1–5 PM") or for screen readers ("93°F (34°C)", "1 PM to 5 PM").
private struct Words {
    let unit: TempUnit
    let spoken: Bool

    func deg(_ c: Double) -> String { spoken ? formatBothUnits(c, unit) : formatDegrees(c, unit) }
    func wind(_ kmh: Double) -> String { formatWind(kmh, unit) }
    func hour(_ t: LocalDateTime) -> String { formatHour(t) }
    func span(_ start: LocalDateTime, _ end: LocalDateTime) -> String {
        spoken ? "\(hour(start)) to \(hour(end))" : formatSpan(start, end)
    }
}

/// "1–5 PM", "11 AM–2 PM", or "13:00–17:00" on the 24-hour clock.
func formatSpan(_ start: LocalDateTime, _ end: LocalDateTime, use24Hour: Bool = ClockFormat.use24Hour) -> String {
    let sameHalf = (start.hour < 12) == (end.hour < 12) && end.hour != 0
    if !use24Hour && sameHalf {
        return "\(start.hour % 12 == 0 ? 12 : start.hour % 12)–\(formatHour(end, use24Hour: use24Hour))"
    }
    return "\(formatHour(start, use24Hour: use24Hour))–\(formatHour(end, use24Hour: use24Hour))"
}

private func line(
    _ kind: LineKind,
    _ unit: TempUnit,
    _ date: LocalDate?,
    topic: OutlookTopic? = nil,
    end: LocalDate? = nil,
    _ build: (Words) -> String
) -> OutlookLine {
    OutlookLine(text: build(Words(unit: unit, spoken: false)), spoken: build(Words(unit: unit, spoken: true)), kind: kind,
                date: date, topic: topic, end: end)
}

private extension Words {
    /// ", best 1–5 PM", ", best before 3 PM", ", best from 2 PM"; nothing when the good stretch is the whole day.
    func qualifier(_ read: DayRead) -> String {
        if read.fromDaily { return "" }
        let first = read.stretch.first == read.hours.first
        let last = read.stretch.last == read.hours.last
        let start = read.stretch.first!.hour.time
        let end = read.stretch.last!.hour.time.plusHours(1)
        if first && last { return "" }
        if first { return ", best before \(hour(end))" }
        if last { return ", best from \(hour(start))" }
        return ", best \(span(start, end))"
    }

    /// When the rain falls in the day's scored hours, by [Precip]'s rules: "rain most of the day", "dry until 2 PM, then
    /// showers", "showers until 11 AM, then drier", "showers from 2 PM", "showers on and off"; nil on a day [Precip]
    /// calls dry, or when none of the rain falls in them. An hour counts as rainy from a 40% chance ("possible").
    func rainPattern(_ read: DayRead, _ rain: DayRain) -> String? {
        if rain.dry || read.fromDaily { return nil }
        let word = rain.word.word.lowercased()
        let hours = read.hours.map(\.hour)
        let wet = hours.map(isRainyHour)
        let wetCount = wet.count { $0 }
        if wetCount == 0 { return nil }
        let first = wet.firstIndex(of: true)!
        let last = wet.lastIndex(of: true)!
        let dry = hours.map { Precip.classify($0.precipChance, $0.precipMm).dry }
        // Mostly wet from the first rainy hour to the last: more than half of them.
        let solid = wet[first...last].count { $0 } * 2 > last - first + 1
        let wetFromFirst = wet.dropFirst(first).count { $0 }
        if Double(wetCount) >= Outlook.mostOfDay * Double(hours.count) { return "\(word) most of the day" }
        if first >= 2 && wetFromFirst * 2 >= hours.count - first {
            return dry.prefix(first).allSatisfy { $0 } ? "dry until \(hour(hours[first].time)), then \(word)"
                : "\(word) from \(hour(hours[first].time))"
        }
        if first == 0 && last <= hours.count - 3 && solid { return "\(word) until \(hour(hours[last].time.plusHours(1))), then drier" }
        return "\(word) on and off"
    }

    /// Why a day held back by rain is: its [rainPattern], "risk of thunderstorms" for storms without rain worth the name,
    /// or the day page's verdict ("rain possible"). Nil only on a dry day without storms.
    func wetReason(_ read: DayRead, _ rain: DayRain) -> String? {
        rainPattern(read, rain)
            ?? (read.stormy ? "risk of thunderstorms" : nil)
            ?? (!rain.dry ? rainWords(rain, unit) : nil)
    }

    /// The end of a good or great day's line: its [qualifier], and where the rain falls when [Precip] doesn't call the day
    /// dry and some of its scored hours are rainy: ", best from 3 PM after showers", ", best before 2 PM, then rain",
    /// ", best 11 AM–2 PM, showers on and off"; ", risk of thunderstorms" for storms without rain.
    func goodTail(_ read: DayRead, _ rain: DayRain) -> String {
        let q = qualifier(read)
        if read.fromDaily { return q }
        let rainy = read.hours.indices.filter { isRainyHour(read.hours[$0].hour) }
        if rain.dry || rainy.isEmpty { return q + (read.stormy ? ", risk of thunderstorms" : "") }
        let word = rain.word.word.lowercased()
        let from = read.hours.firstIndex(of: read.stretch.first!)!
        let to = read.hours.firstIndex(of: read.stretch.last!)!
        if rainy.allSatisfy({ $0 < from }) { return "\(q) after \(word)" }
        if rainy.allSatisfy({ $0 > to }) { return "\(q), then \(word)" }
        return "\(q), \(word) on and off"
    }

    /// "gusts to 85 km/h", or "wind to 50 km/h" when the gusts are missing or no stronger than the wind.
    func windPeak(_ read: DayRead) -> String {
        let gust = read.maxGustKmh
        let wind = read.maxWindKmh ?? 0.0
        if let gust, gust >= wind { return "gusts to \(self.wind(gust))" }
        return "wind to \(self.wind(wind))"
    }
}

private func dayLine(_ read: DayRead, _ rain: DayRain, tomorrow: Bool, _ unit: TempUnit) -> OutlookLine {
    let tier = read.tier
    let topic = read.topic
    let notGood = !tier.atLeastGood
    let stayIn = tier == .stayIn
    let warmest = read.warmest
    func says(_ topic: OutlookTopic?, _ build: (Words) -> String) -> OutlookLine { line(.day, unit, read.date, topic: topic, build) }
    func pick(_ today: String, _ tmrw: String) -> String { tomorrow ? tmrw : today }
    if notGood && topic == .wet && Words(unit: unit, spoken: false).wetReason(read, rain) != nil {
        return says(.wet) { w in
            let why = w.wetReason(read, rain)!
            return stayIn ? pick("Better stay in: \(why)", "Better stay in tomorrow: \(why)")
                : pick("Mixed day: \(why)", "Tomorrow looks mixed: \(why)")
        }
    }
    if warmest.hour.tempC >= Outlook.hotC && !read.fromDaily {
        return says(.heat) { w in
            let peak = "\(w.deg(warmest.hour.tempC)) by \(w.hour(warmest.hour.time))"
            return stayIn ? pick("Too hot to enjoy outside: \(peak)", "Tomorrow looks too hot to enjoy: \(peak)")
                : pick("Hot day: \(peak)", "Hot day tomorrow: \(peak)") + w.qualifier(read)
        }
    }
    if (notGood && topic == .wind) || read.peakWindKmh >= Outlook.galeGustKmh {
        return says(.wind) { w in
            let peak = w.windPeak(read)
            return notGood && (stayIn || read.peakWindKmh >= Outlook.galeGustKmh)
                ? pick("Too windy to enjoy outside: \(peak)", "Tomorrow looks too windy to enjoy: \(peak)")
                : pick("Blustery day: \(peak)", "Tomorrow looks blustery: \(peak)") + w.qualifier(read)
        }
    }
    if notGood && topic == .cold {
        return says(.cold) { w in
            let t = "no warmer than \(w.deg(warmest.hour.tempC))"
            return stayIn ? pick("Too cold to enjoy outside: \(t)", "Tomorrow looks too cold to enjoy: \(t)")
                : pick("Cold day: \(t)", "Cold day tomorrow: \(t)")
        }
    }
    if read.dim {
        return says(.dark) { w in
            let but = rain.dry ? ", but dry" : ""
            let q = w.qualifier(read).removingPrefix(", ")
            let tail = q.isEmpty ? "" : ": \(q)"
            let light = read.polarNight ? "No daylight" : "Little daylight"
            return pick("\(light) today\(but)\(tail)", "\(light) tomorrow\(but)\(tail)")
        }
    }
    if tier == .great {
        return says(nil) { w in pick("Great day to be outside", "Tomorrow looks great outside") + w.goodTail(read, rain) }
    }
    if tier == .good && topic == .cold {
        return says(.cold) { w in
            pick("Cold but good to be outside", "Tomorrow looks cold but good outside") + w.goodTail(read, rain)
        }
    }
    if tier == .good {
        return says(nil) { w in pick("Good day to be outside", "Tomorrow looks good outside") + w.goodTail(read, rain) }
    }
    if tier == .meh { return says(topic) { w in pick("Mixed day", "Tomorrow looks mixed") + w.qualifier(read) } }
    return says(topic) { _ in pick("Better stay in", "Better stay in tomorrow") }
}

// MARK: - The week lines

/// A run of wet days: indexes into the forecast's days from today, [end] inclusive.
private struct Spell {
    let start: Int
    let end: Int

    func contains(_ i: Int) -> Bool { (start...end).contains(i) }
}

/// The days of the outlook with their reads (nil: today, not enough daylight left), every forecast day's rain from
/// today, which day the today line is about ([focusIndex]) and the line itself.
private struct Context {
    let forecast: Forecast
    let now: LocalDateTime
    let today: LocalDate
    let days: [DaySummary]
    let reads: [DayRead?]
    /// Every forecast day from today, past the outlook too: a spell can run on into them.
    let rains: [DayRain]
    let weekend: Set<DayOfWeek>
    let focusIndex: Int
    let todayLine: OutlookLine

    /// Whether what's still to come today is wet by [Precip.classify], judged on the stamps after [now].
    private let restOfTodayWet: Bool

    init(forecast: Forecast, now: LocalDateTime, today: LocalDate, days: [DaySummary], reads: [DayRead?],
         rains: [DayRain], weekend: Set<DayOfWeek>, focusIndex: Int, todayLine: OutlookLine) {
        self.forecast = forecast
        self.now = now
        self.today = today
        self.days = days
        self.reads = reads
        self.rains = rains
        self.weekend = weekend
        self.focusIndex = focusIndex
        self.todayLine = todayLine
        restOfTodayWet = {
            guard let r = rains.first, r.kind == .wet else { return false }
            let chance = r.counted.filter { $0.time > now }.map(\.precipChance).max() ?? 0
            return Precip.classify(chance, r.stillToCome(now).mm).kind == .wet
        }()
    }

    func name(_ i: Int) -> String { outlookDayName(rains[i].date, today) }
    func capitalName(_ i: Int) -> String { name(i).capitalizedFirst }

    /// The day the today line calls good or great: never part of a spell, so the two never disagree.
    private var focusGood: Bool { (focusIndex < reads.count ? reads[focusIndex] : nil)?.tier.atLeastGood == true }

    /// A day that counts towards a spell: wet by [Precip], today only for what's still to come, and not [focusGood].
    private func wet(_ i: Int) -> Bool {
        rains[i].kind == .wet && (i != 0 || restOfTodayWet) && !(i == focusIndex && focusGood)
    }

    /// The first run of two or more wet days that starts within the week, as far as the data shows it.
    func spell() -> Spell? {
        let upper = min(Outlook.days, rains.count - 1)
        guard upper > 0, let start = (0..<upper).first(where: { wet($0) && wet($0 + 1) }) else { return nil }
        var end = start
        while end + 1 < rains.count && wet(end + 1) { end += 1 }
        return Spell(start: start, end: end)
    }

    /// "Wet until Wednesday, drier from Thursday" (from today), "Showers today and tomorrow, then drier", "Rainy spell
    /// from tomorrow until Monday", "Showers on and off Thursday to Saturday", "Rainy spell Thursday to next
    /// Saturday", "Snowy from Friday, into next week" (only when it runs to the end of the data). It's "on and off"
    /// when its days are showers or average under six wet hours.
    func wetSpellLine(_ spell: Spell, _ unit: TempUnit) -> OutlookLine {
        let start = spell.start, end = spell.end
        let days = rains[start...end]
        let snow = days.count { $0.showsSnow } * 2 > days.count
        let showers = days.contains { $0.word == .showers }
        let onAndOff = showers
            || (days.allSatisfy { $0.complete } && Double(days.reduce(0) { $0 + $1.wetHours }) / Double(days.count) < 6)
        let open = end == rains.count - 1 // the data ends before the spell does
        let after = end + 1
        let adjective = snow ? "Snowy" : "Rainy"
        let noun = snow ? "Snow" : showers ? "Showers" : "Rain"
        let text: String
        if start == 0 && open { text = snow ? "Snowy into next week" : "Wet into next week" }
        else if start == 0 && end == 1 { text = "\(noun) today and tomorrow, then drier" }
        else if start == 0 {
            text = (onAndOff ? "\(noun) on and off until \(name(end))" : "\(snow ? "Snowy" : "Wet") until \(name(end))") +
                ", drier from \(name(after))"
        }
        else if open && onAndOff { text = "\(noun) on and off from \(name(start)), into next week" }
        else if open { text = "\(adjective) from \(name(start)), into next week" }
        else if start == 1 && onAndOff { text = "\(noun) on and off from tomorrow until \(name(end))" }
        else if start == 1 { text = "\(adjective) spell from tomorrow until \(name(end))" }
        else if onAndOff { text = "\(noun) on and off \(name(start)) to \(name(end))" }
        else { text = "\(adjective) spell \(name(start)) to \(name(end))" }
        return line(.wetSpell, unit, rains[start].date, topic: .wet, end: rains[end].date) { _ in text }
    }

    /// Today's line is wet, and today is a wet day on its own (not a spell): the first dry day after it. "Dry again
    /// from Thursday".
    func dryTurn(_ unit: TempUnit, _ spell: Spell?) -> OutlookLine? {
        if spell?.start == 0 || !restOfTodayWet { return nil }
        if todayLine.date != today || todayLine.topic != .wet { return nil }
        let upper = min(Outlook.days, rains.count)
        guard upper > 1, let i = (1..<upper).first(where: { rains[$0].dry }) else { return nil }
        return line(.dryTurn, unit, rains[i].date, topic: .wet) { _ in "Dry again from \(name(i))" }
    }

    /// The best of the scored days when it stands out: at least [Outlook.bestMargin] over the median. Never a wet day
    /// or a day in the [spell]. A weekend day within [Outlook.weekendSlack] of it (good, and standing out itself) is
    /// picked instead; ties go to the earlier day. Nil with fewer than three scored days, or when none stands out.
    func bestDay(_ spell: Spell?) -> DayRead? {
        let scored = reads.compactMap { $0 }
        if scored.count < 3 { return nil }
        let sorted = scored.map(\.score).sorted()
        let median = sorted.count % 2 == 1 ? Double(sorted[sorted.count / 2])
            : Double(sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2.0
        let eligible = reads.indices.compactMap { i -> DayRead? in
            guard let r = reads[i], rains[i].kind != .wet, spell.map({ !$0.contains(i) }) ?? true else { return nil }
            return r
        }
        // The earliest of equals.
        guard let top = firstMax(eligible) else { return nil }
        if Double(top.score) < median + Double(Outlook.bestMargin) { return nil }
        if !top.tier.atLeastGood { return top }
        let weekendPick = firstMax(eligible.filter {
            weekend.contains($0.date.dayOfWeek) && $0.tier.atLeastGood && $0.score >= top.score - Outlook.weekendSlack
                && Double($0.score) >= median + Double(Outlook.bestMargin)
        })
        return weekendPick ?? top
    }

    /// The highest-scoring read, the earliest of equals (Kotlin's `maxByOrNull`).
    private func firstMax(_ reads: [DayRead]) -> DayRead? { reads.max { $0.score < $1.score } }

    /// "Saturday is the best day this week", "Today's the best day this week", or with no good day at all, "Thursday
    /// is the best of a poor week". Nil when the best that's left isn't good but a good day is (a wet one).
    func bestDayLine(_ best: DayRead, _ unit: TempUnit) -> OutlookLine? {
        let i = rains.firstIndex { $0.date == best.date }!
        let text: String
        if !best.tier.atLeastGood {
            if reads.contains(where: { $0?.tier.atLeastGood == true }) { return nil }
            text = "\(capitalName(i)) is the best of a poor week"
        } else if i == 0 {
            text = "Today's the best day this week"
        } else {
            text = "\(capitalName(i)) is the best day this week"
        }
        return line(.bestDay, unit, best.date) { _ in text }
    }

    /// The first day whose scored hours have gusts (or wind) of [Outlook.galeGustKmh] or more, other than [said]
    /// (the day the today line already calls too windy): "Very windy Thursday: gusts to 80 km/h". Today counts only
    /// while it has a score.
    func bigWind(_ unit: TempUnit, said: LocalDate?) -> OutlookLine? {
        guard let i = reads.indices.first(where: { i in
            reads[i].map { $0.peakWindKmh >= Outlook.galeGustKmh && $0.date != said } == true
        }) else { return nil }
        let read = reads[i]!
        return line(.bigWind, unit, days[i].date, topic: .wind) { w in "Very windy \(name(i)): \(w.windPeak(read))" }
    }

    /// Two or more days in a row with highs of [Outlook.heatSpellC]: "Hot spell Thursday to Saturday, up to 34°".
    func heatSpell(_ unit: TempUnit) -> OutlookLine? {
        let hot = days.map { $0.highC >= Outlook.heatSpellC }
        guard days.count > 1, let start = (0..<(days.count - 1)).first(where: { hot[$0] && hot[$0 + 1] }) else { return nil }
        var end = start
        while end + 1 < days.count && hot[end + 1] { end += 1 }
        let peak = days[start...end].map(\.highC).max()!
        let toEnd = end == days.count - 1 && days.count == Outlook.days
        return line(.heatSpell, unit, days[start].date, topic: .heat, end: days[end].date) { w in
            let upTo = "up to \(w.deg(peak))"
            if start == 0 && toEnd { return "Hot all week, \(upTo)" }
            if start == 0 { return "Hot until \(name(end)), \(upTo)" }
            if toEnd { return "Hot from \(name(start)) on, \(upTo)" }
            if start == 1 { return "Hot spell from tomorrow until \(name(end)), \(upTo)" }
            return "Hot spell \(name(start)) to \(name(end)), \(upTo)"
        }
    }

    /// The first day whose high is [Outlook.coldDropC] or more below today's, and cool ([Outlook.coldSnapHighC]):
    /// "Much colder Friday: 9°, down from 18° today". The end of a heat spell isn't a cold snap.
    func coldSnap(_ unit: TempUnit) -> OutlookLine? {
        guard let high = days.first?.highC else { return nil }
        guard let i = (1..<days.count).first(where: {
            days[$0].highC <= high - Outlook.coldDropC && days[$0].highC < Outlook.coldSnapHighC
        }) else { return nil }
        return line(.coldSnap, unit, days[i].date, topic: .cold) { w in
            "Much colder \(name(i)): \(w.deg(days[i].highC)), down from \(w.deg(high)) today"
        }
    }

    /// A morning's low: the lowest of its stamps from midnight to 9 AM, or the day's low without hourly data.
    private func morningLow(_ i: Int) -> Double {
        forecast.hoursOf(days[i].date).filter { $0.time.hour <= Outlook.morningUntil }.map(\.tempC).min() ?? days[i].lowC
    }

    /// The first frosty morning (under [Outlook.frostC]) when this morning wasn't: "Frost by Wednesday morning: down
    /// to −2°", or "First frost by Saturday morning" after [Outlook.firstFrostAfter] frost-free mornings.
    func frost(_ unit: TempUnit) -> OutlookLine? {
        if days.isEmpty { return nil }
        let lows = days.indices.map(morningLow)
        if lows[0] < Outlook.frostC { return nil }
        guard let i = (1..<days.count).first(where: { lows[$0] < Outlook.frostC }) else { return nil }
        let first = (0..<i).count { lows[$0] >= 0.0 } >= Outlook.firstFrostAfter
        return line(.frost, unit, days[i].date, topic: .cold) { w in
            "\(first ? "First frost" : "Frost") by \(name(i)) morning: down to \(w.deg(lows[i]))"
        }
    }

    /// Every day of the week dry by [Precip], when nothing else is worth saying: "Great all week" when every scored
    /// day is great, "Good all week" when every one is at least good, otherwise "Dry all week".
    func dryWeek(_ unit: TempUnit) -> OutlookLine? {
        if days.count < Outlook.days || rains.prefix(Outlook.days).contains(where: { !$0.dry }) { return nil }
        let tiers = reads.compactMap { $0?.tier }
        let text: String
        if tiers.allSatisfy({ $0 == .great }) { text = "Great all week" }
        else if tiers.allSatisfy(\.atLeastGood) { text = "Good all week" }
        else { text = "Dry all week" }
        return line(.dryWeek, unit, nil) { _ in text }
    }
}
