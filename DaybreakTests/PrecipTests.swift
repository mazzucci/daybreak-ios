import Foundation
import Testing
@testable import Daybreak

/// Ported from Android's PrecipTest: the one rule set for rain and snow, on hand-made days and a real forecast.
struct PrecipTests {
    private let date = LocalDate(2026, 9, 28)
    private let alps = TestData.alps()

    private func alpsDay(_ d: Int) -> DayRain { Precip.dayRain(alps, LocalDate(2026, 10, d)) }

    private func day(_ chance: Int, _ sumMm: Double?, code: Int = 61, hours: Double? = nil, snowCm: Double? = nil) -> DaySummary {
        DaySummary(date: date, highC: 20, lowC: 10, precipChance: chance, code: code, precipSumMm: sumMm, precipHours: hours,
                   snowSumCm: snowCm)
    }

    /// A day with only its daily figures (no hourly data), as the verdict sees it.
    private func verdictOf(_ day: DaySummary, _ unit: TempUnit = .c) -> String {
        Precip.verdict(Precip.dayRain(Forecast(current: TestData.current, days: [day], hours: []), day.date), unit)
    }

    private func hour(_ at: Int, _ mm: Double?, chance: Int = 50, snowCm: Double? = nil) -> HourForecast {
        HourForecast(time: date.atTime(at), tempC: 10, precipChance: chance, code: 61, precipMm: mm, snowCm: snowCm)
    }

    /// [date] and the day after, hour by hour, with [mm] stamped at the given hours of [date] (at [chance]) and nothing
    /// elsewhere (at 5%); sun 7:02 to 18:56 unless [sunrise] and [sunset] say otherwise.
    private func forecastWith(
        _ mm: [(Int, Double)],
        chance: Int = 50,
        snowCm: [Int: Double] = [:],
        sunrise: (LocalDate) -> LocalDateTime? = { $0.atTime(7, 2) },
        sunset: (LocalDate) -> LocalDateTime? = { $0.atTime(18, 56) }
    ) -> Forecast {
        let wet = Dictionary(mm, uniquingKeysWith: { a, _ in a })
        let hours = (0..<48).map { i -> HourForecast in
            let wetHere = i < 24 && wet[i] != nil
            return HourForecast(time: date.atStartOfDay.plusHours(i), tempC: 10, precipChance: wetHere ? chance : 5, code: 61,
                                precipMm: wetHere ? wet[i]! : 0, snowCm: i < 24 ? snowCm[i] ?? 0 : 0)
        }
        let days = [date, date.plusDays(1)].map { d in
            DaySummary(date: d, highC: 12, lowC: 6, precipChance: hours.filter { $0.time.date == d }.map(\.precipChance).max()!,
                       code: 61, sunrise: sunrise(d), sunset: sunset(d))
        }
        return Forecast(current: CurrentConditions(time: date.atTime(6, 30), tempC: 8, feelsLikeC: 7, humidity: 80, windKmh: 10, code: 61),
                        days: days, hours: hours)
    }

    private func label(_ p: RainPeriod) -> String { "\(formatHour(p.labelStart))–\(formatHour(p.labelEnd))" }

    // MARK: Thresholds and the one classifier

    @Test("chances are shown from 10 percent an hour and 20 a day, blue from 40")
    func thresholds() {
        #expect(!Precip.showHourChance(9))
        #expect(Precip.showHourChance(10))
        #expect(!Precip.showDayChance(19))
        #expect(Precip.showDayChance(20))
        #expect(!Precip.highlightChance(39))
        #expect(Precip.highlightChance(40))
    }

    @Test("chance words")
    func chanceWords() {
        #expect(Precip.likelihood(19) == .unlikely)
        #expect(Precip.likelihood(20) == .small)
        #expect(Precip.likelihood(39) == .small)
        #expect(Precip.likelihood(40) == .possible)
        #expect(Precip.likelihood(69) == .possible)
        #expect(Precip.likelihood(70) == .likely)
    }

    @Test("one classifier judges chance and amount together")
    func classifier() {
        #expect(Precip.classify(60, 3.0) == RainCall(kind: .wet, amountShown: true)) // a wet day
        #expect(Precip.classify(30, 3.0) == RainCall(kind: .mixed, amountShown: true)) // a gamble, not a spell
        #expect(Precip.classify(60, 0.5) == RainCall(kind: .mixed, amountShown: true))
        // A real modelled amount counts at a low chance; a trace doesn't.
        #expect(Precip.classify(15, 2.4) == RainCall(kind: .mixed, amountShown: true))
        #expect(Precip.classify(15, 0.6) == RainCall(kind: .dry, amountShown: false))
        // A real chance stays possible without a modelled amount, but has no amount to show.
        #expect(Precip.classify(60, 0.0) == RainCall(kind: .mixed, amountShown: false))
        #expect(Precip.classify(25, 0.05) == RainCall(kind: .mixed, amountShown: false))
        #expect(Precip.classify(45, nil) == RainCall(kind: .mixed, amountShown: false))
        #expect(Precip.classify(5, nil) == RainCall(kind: .dry, amountShown: false))
    }

    @Test("snow when there's enough and it's most of the water")
    func snow() {
        #expect(Precip.isSnowDay(day(70, 4.3, snowCm: 3.0)))
        #expect(!Precip.isSnowDay(day(70, 0.6, snowCm: 0.4))) // too little to call
        #expect(!Precip.isSnowDay(day(70, 10.0, snowCm: 1.0))) // mostly rain
        #expect(!Precip.isSnowDay(day(70, 4.0, snowCm: nil)))
        #expect(Precip.isSnowHour(hour(3, 0.3, snowCm: 0.21)))
        #expect(!Precip.isSnowHour(hour(3, 0.1, snowCm: 0.05)))
    }

    // MARK: Amounts as text

    @Test("rain in mm with C")
    func rainInMm() {
        #expect(Precip.formatRain(0.6, .c) == "0.6 mm")
        #expect(Precip.formatRain(4.0, .c) == "4 mm")
        #expect(Precip.formatRain(4.3, .c) == "4.3 mm")
        #expect(Precip.formatRain(9.96, .c) == "10 mm")
        #expect(Precip.formatRain(18.4, .c) == "18 mm")
        #expect(Precip.formatRain(2.4, .c, rough: true) == "2 mm")
        #expect(Precip.formatRain(0.6, .c, rough: true) == "1 mm")
    }

    @Test("inches take two decimals under an inch and one from there, never 0 point 00")
    func inches() {
        #expect(Precip.formatRain(0.5, .f) == "0.02 in")
        #expect(Precip.formatRain(0.1, .f) == "0.01 in")
        #expect(Precip.formatRain(3.8, .f) == "0.15 in")
        #expect(Precip.formatRain(6.6, .f) == "0.26 in")
        #expect(Precip.formatRain(2.54, .f) == "0.1 in") // 0.10: the trailing zero goes
        #expect(Precip.formatRain(17.8, .f) == "0.7 in")
        #expect(Precip.formatRain(25.2, .f) == "0.99 in")
        #expect(Precip.formatRain(25.3, .f) == "1 in")
        #expect(Precip.formatRain(25.4, .f) == "1 in")
        #expect(Precip.formatRain(30.5, .f) == "1.2 in")
        #expect(Precip.formatRain(76.2, .f) == "3 in")
        #expect(Precip.formatRain(0.0, .f) == "0 in")
    }

    @Test("snow in cm with C and in inches with F")
    func snowAmounts() {
        #expect(Precip.formatSnow(0.4, .c) == "0.4 cm")
        #expect(Precip.formatSnow(3.0, .c) == "3 cm")
        #expect(Precip.formatSnow(19.32, .c) == "19 cm")
        #expect(Precip.formatSnow(3.0, .f) == "1.2 in")
        #expect(Precip.formatSnow(0.4, .f) == "0.16 in")
    }

    @Test("prose and spoken amounts")
    func prose() {
        #expect(Precip.proseRain(6.5, .c) == "6.5 mm")
        #expect(Precip.proseRain(6.5, .f) == "0.26 inches")
        #expect(Precip.proseRain(25.4, .f) == "1 inch")
        #expect(Precip.spokenRain(0.6, .c) == "0.6 millimetres")
        #expect(Precip.spokenRain(0.5, .f) == "0.02 inches")
        #expect(Precip.spokenSnow(3.0, .c) == "3 centimetres of snow")
    }

    @Test("an hour's amount follows the classifier, as snow when it's snow")
    func hourAmount() {
        #expect(Precip.hourAmount(hour(3, 0.05), .c) == nil)
        #expect(Precip.hourAmount(hour(3, nil), .c) == nil) // a model without amounts
        #expect(Precip.hourAmount(hour(3, 0.1), .c) == "0.1 mm")
        #expect(Precip.hourAmount(hour(3, 1.8), .c) == "1.8 mm")
        #expect(Precip.hourAmount(hour(3, 1.8), .f) == "0.07 in")
        #expect(Precip.hourAmount(hour(3, 0.6, snowCm: 0.4), .c) == "0.4 cm")
        #expect(Precip.hourAmount(hour(3, 0.4, chance: 5), .c) == nil) // a trace nobody expects
        #expect(Precip.hourAmount(hour(3, 1.5, chance: 5), .c) == "1.5 mm") // a real amount
        #expect(Precip.hourAmountSpoken(hour(3, 1.8), .c) == "about 1.8 millimetres")
    }

    @Test("the hourly strip's hour gets the values stamped at its end")
    func stripStamps() throws {
        let f = forecastWith([(15, 2.0)])
        let threePm = try #require(f.hourAt(date.atTime(14)))
        #expect(f.rainDuring(threePm)?.time == date.atTime(15))
        #expect(f.rainDuring(threePm)?.precipMm == 2.0)
        #expect(f.rainDuring(f.hours.last!) == nil) // past the end of the data
    }

    // MARK: Verdicts

    @Test("verdict pairs the chance word with the total and hours")
    func verdicts() {
        #expect(verdictOf(day(75, 12.0, hours: 6.0)) == "Rain likely · about 12 mm over 6 hours")
        #expect(verdictOf(day(75, 12.0, hours: 1.0), .f) == "Rain likely · about 0.47 inches over 1 hour")
        #expect(verdictOf(day(50, 0.6, code: 80)) == "Showers possible · a few drops")
        #expect(verdictOf(day(30, 3.0)) == "A small chance of rain · about 3 mm")
        #expect(verdictOf(day(45, 7.0, code: 95, hours: 3.0)) == "Thunderstorms possible · about 7 mm over 3 hours")
        #expect(verdictOf(day(80, 4.3, code: 73, hours: 5.0, snowCm: 3.0)) == "Snow likely · about 3 cm over 5 hours")
        #expect(verdictOf(day(10, 0.0)) == "Rain unlikely")
        #expect(verdictOf(day(45, 0.0)) == "Rain possible") // a chance with no amount says just that
        #expect(verdictOf(day(45, nil)) == "Rain possible")
    }

    @Test("a low chance with a real amount is a small chance, up to a rounded amount")
    func lowChanceRealAmount() {
        #expect(verdictOf(day(15, 2.4, hours: 6.0)) == "A small chance of rain · up to 2 mm over 6 hours")
        #expect(verdictOf(day(15, 0.6, hours: 2.0)) == "Rain unlikely") // a trace: nothing to show
        let oct4 = alpsDay(4) // 15% at most, 2.4 mm in the afternoon
        #expect(Precip.verdict(oct4, .c) == "A small chance of rain · up to 2 mm over 6 hours")
        #expect(Precip.dayAmount(oct4, .c) == "2 mm")
        #expect(Precip.dayAmountSpoken(oct4, .c) == "up to 2 millimetres")
        #expect(oct4.rows.map { $0.describe(.c) } == ["14% · up to 2 mm · 6 h"])
    }

    @Test("verdicts on a real forecast")
    func realVerdicts() {
        #expect(Precip.verdict(alpsDay(1), .c) == "Showers possible · about 4.2 mm over 7 hours")
        #expect(Precip.verdict(alpsDay(2), .c) == "Showers possible · about 12 mm over 5 hours")
        #expect(Precip.verdict(alpsDay(7), .c) == "A small chance of rain") // 32%, nothing modelled
        #expect(Precip.verdict(alpsDay(8), .f) == "Snow possible · about 7.6 inches over 21 hours")
        #expect(Precip.verdict(alpsDay(6), .c) == "Rain unlikely")
    }

    @Test("the 10-day row's total is the verdict's")
    func rowTotals() {
        #expect(Precip.dayAmount(alpsDay(1), .c) == "4.2 mm")
        #expect(Precip.dayAmount(alpsDay(8), .c) == "19 cm")
        #expect(Precip.dayAmountSpoken(alpsDay(8), .c) == "about 19 centimetres of snow")
        #expect(Precip.dayAmount(alpsDay(7), .c) == nil) // a chance, no amount
        #expect(Precip.dayAmount(alpsDay(6), .c) == nil)
    }

    // MARK: The day's rows

    @Test("rows partition the calendar day and add up to the verdict")
    func rows() throws {
        let rain = alpsDay(1)
        #expect(rain.periods.map(\.name) == ["Before sunrise", "Daytime", "Evening"])
        // Sunrise 7:26 and sunset 19:08 round to the hour; the day runs midnight to midnight.
        #expect(rain.periods.map(label) == ["12 AM–7 AM", "7 AM–7 PM", "7 PM–12 AM"])
        // Every stamp of the day is in exactly one row, and nothing else is.
        #expect(rain.hours.allSatisfy { h in rain.periods.filter { $0.contains(h.time) }.count == 1 })
        #expect(rain.hours.count == 24)
        // Before sunrise has a 43% chance but no modelled amount: a row with just the chance.
        #expect(rain.rows.map { $0.describe(.c) } == ["43%", "60% · 2.1 mm · 3 h", "50% · 2.1 mm · 4 h"])
        #expect(abs(rain.totalMm - rain.rows.reduce(0) { $0 + $1.totalMm }) < 1e-9)
        #expect(rain.wetHours == rain.rows.reduce(0) { $0 + $1.wetHours })
        #expect(abs(rain.totalMm - 4.2) < 1e-9)
        #expect(rain.wetHours == 7)
        let daily = try #require(alps.day(rain.date)?.precipSumMm)
        #expect(abs(daily - rain.totalMm) < 1e-9) // and Open-Meteo's daily sum
        #expect(rain.rows.last?.spoken(.f) == "50 percent chance, about 0.08 inches, over 4 hours")
    }

    @Test("periods take the hours after their start up to their end")
    func periodBounds() {
        let rain = alpsDay(1)
        let early = rain.periods[0], daytime = rain.periods[1]
        // The 7:00 stamp is rain from 6 to 7, before sunrise; 19:00 is 6 to 7 PM, still daytime.
        #expect(early.contains(LocalDateTime(2026, 10, 1, 7, 0)))
        #expect(!daytime.contains(LocalDateTime(2026, 10, 1, 7, 0)))
        #expect(daytime.contains(LocalDateTime(2026, 10, 1, 19, 0)))
        // The 00:00 stamp opens the day, as in Open-Meteo's daily sums.
        #expect(early.contains(LocalDateTime(2026, 10, 1, 0, 0)))
    }

    @Test("a trace in a dry part is left out of the rows and the verdict alike")
    func traceLeftOut() {
        // Oct 9: snow before sunrise (35%), then 0.1 mm an hour at 14 to 16% through the afternoon and evening.
        let rain = alpsDay(9)
        #expect(rain.rows.map(\.name) == ["Before sunrise"])
        #expect(abs(rain.rows.reduce(0) { $0 + $1.snowCm } - rain.snowCm) < 1e-9)
        #expect(rain.rows.reduce(0) { $0 + $1.wetHours } == rain.wetHours)
        #expect(Precip.verdict(rain, .c) == "A small chance of snow · about 5.9 cm over 9 hours")
        #expect(rain.counted.allSatisfy { $0.time.hour <= 8 })
    }

    @Test("no rain is counted on two days")
    func noDoubleCounting() {
        let days = alps.days.map { Precip.dayRain(alps, $0.date) }
        for rain in days { #expect(rain.counted.allSatisfy { $0.time.date == rain.date }) }
        let stamps = days.flatMap { $0.counted.map(\.time) }
        #expect(stamps.count == Set(stamps).count)
    }

    @Test("the next day's early rain is one line, and only that crosses midnight")
    func carryOn() throws {
        let oct1 = alpsDay(1)
        let next = try #require(oct1.carryOn)
        #expect(next.date == LocalDate(2026, 10, 2))
        #expect(Precip.carryOnLine(next, .c) == "Carries on after midnight: about 12 mm by 7 AM Friday.")
        #expect(abs(next.totalMm - alpsDay(2).rows[0].totalMm) < 1e-9) // the same hours as the next page's first row
        #expect(!oct1.counted.contains { $0.time.date == next.date })
        #expect(Precip.carryOnLine(try #require(alpsDay(8).carryOn), .f)
            == "Carries on after midnight: about 2.3 inches of snow by 8 AM Friday.")
        #expect(alpsDay(2).carryOn == nil) // a dry early morning on the 3rd
        #expect(alpsDay(10).carryOn == nil) // the end of the data
    }

    @Test("a snow card names its rows without saying snow again, a rain card says snow where it is")
    func snowCard() {
        let snowy = alpsDay(8)
        #expect(snowy.title == "Snow")
        #expect(snowy.mix == .snow)
        #expect(snowy.rows.map { $0.describe(.c, snowWord: false) } == ["45% · 1.3 cm · 6 h", "53% · 13 cm · 11 h", "53% · 5.5 cm · 4 h"])
        #expect(snowy.rows.first?.describe(.c) == "45% · 1.3 cm snow · 6 h")
        #expect(abs(snowy.snowCm - 19.32) < 1e-9)
        #expect(Precip.verdict(snowy, .c) == "Snow possible · about 19 cm over 21 hours")
    }

    @Test("rain by day and snow by night makes a rain and snow card")
    func rainAndSnow() {
        let f = forecastWith([(10, 2.0), (11, 2.0), (21, 1.5), (22, 1.5)], snowCm: [21: 1.5, 22: 1.5])
        let rain = Precip.dayRain(f, date)
        #expect(rain.mix == .rainAndSnow)
        #expect(rain.title == "Rain and snow")
        #expect(Precip.verdict(rain, .c) == "Rain and snow possible · about 4 mm of rain and 3 cm of snow over 4 hours")
        #expect(rain.rows.map { $0.describe(.c) } == ["50% · 4 mm · 2 h", "50% · 3 cm snow · 2 h"])
    }

    @Test("an older response without amounts has no rows and no timing, and falls back to the daily figures")
    func withoutAmounts() {
        let bare = Forecast(current: alps.current, days: alps.days,
                            hours: alps.hours.map { var h = $0; h.precipMm = nil; h.snowCm = nil; return h })
        let rain = Precip.dayRain(bare, LocalDate(2026, 10, 2))
        #expect(!rain.complete)
        #expect(rain.rows.isEmpty)
        #expect(rain.timing == nil)
        #expect(Precip.verdict(rain, .c) == "Showers possible · about 12 mm over 5 hours")
    }

    // MARK: Timing

    private func timingOf(_ mm: [(Int, Double)]) -> Timing? { Precip.dayRain(forecastWith(mm), date).timing }

    @Test("timing finds the part of the day and names the hour the heaviest rain falls in")
    func timing() throws {
        let afternoon = try #require(timingOf([(13, 0.4), (14, 0.6), (15, 0.8), (16, 2.5), (17, 0.5)]))
        #expect(afternoon.shape == .mostly)
        #expect(afternoon.parts == [.afternoon])
        #expect(afternoon.peak == date.atTime(15)) // stamped 16:00: it falls from 3 to 4 PM
        #expect(Precip.timingSentence(afternoon) == "Mostly in the afternoon, heaviest around 3 PM.")

        #expect(Precip.timingSentence(try #require(timingOf([(2, 1.0), (8, 1.0), (14, 1.0), (21, 1.0)]))) == "On and off all day.")

        let two = try #require(timingOf([(9, 1.0), (10, 1.0), (13, 1.0), (14, 1.0)]))
        #expect(Precip.timingSentence(two) == "Mostly in the morning and afternoon.")
        #expect(Precip.timingToday(two) == "mostly this morning and afternoon")

        #expect(timingOf([(10, 0.05)]) == nil)
        #expect(timingOf([]) == nil)
    }

    @Test("the hours before sunrise are before sunrise, never overnight")
    func beforeSunrise() throws {
        let earlyAndMorning = try #require(timingOf([(4, 1.0), (5, 1.0), (9, 1.0), (10, 1.0)]))
        #expect(Precip.timingSentence(earlyAndMorning) == "Mostly before sunrise and in the morning.")
        #expect(Precip.timingToday(earlyAndMorning) == "mostly before sunrise and this morning")
        let clearing = try #require(timingOf([(1, 1.0), (2, 1.0), (3, 1.0)]))
        #expect(Precip.timingSentence(clearing) == "Before sunrise, clearing by morning.")
        #expect(Precip.timingToday(clearing) == "before sunrise, clearing by morning")
        #expect(Precip.timingSentence(try #require(alpsDay(2).timing)) == "Before sunrise, clearing by morning.")
        #expect(Precip.timingSentence(try #require(alpsDay(1).timing)) == "Mostly in the afternoon and evening.")
    }

    @Test("a single wet hour or a tiny total has no heaviest")
    func noPeak() {
        #expect(timingOf([(15, 3.0)])?.peak == nil)
        #expect(timingOf([(15, 0.4), (16, 0.2)])?.peak == nil)
    }

    @Test("today's rain still to come counts the hours that end after now")
    func stillToCome() {
        let rain = alpsDay(1)
        let evening = rain.stillToCome(LocalDateTime(2026, 10, 1, 19, 30))
        #expect(abs(evening.mm - 2.1) < 1e-9)
        #expect(evening.wetHours == 4)
        #expect(Precip.spanPhrase(evening, rain, .c) == "about 2.1 mm over 4 hours, mostly this evening")
        #expect(rain.stillToCome(LocalDateTime(2026, 10, 1, 23, 30)).mm == 0)
    }

    // MARK: Days without a sunrise or a sunset

    @Test("polar night and midnight sun run 7 to 7 with a midday, and leave no hour between rows")
    func polar() throws {
        let night = forecastWith([(1, 1.0), (2, 1.0), (3, 1.0)], sunrise: { $0.atStartOfDay }, sunset: { $0.atStartOfDay })
        let sun = forecastWith([(1, 1.0)], sunrise: { $0.atStartOfDay }, sunset: { $0.plusDays(1).atStartOfDay })
        for f in [night, sun] {
            let rain = Precip.dayRain(f, date)
            #expect(rain.periods.map(\.name) == ["Early", "Midday", "Evening"])
            #expect(rain.periods.map(label) == ["12 AM–7 AM", "7 AM–7 PM", "7 PM–12 AM"])
            #expect(rain.hours.allSatisfy { h in rain.periods.filter { $0.contains(h.time) }.count == 1 })
        }
        #expect(Precip.timingSentence(try #require(Precip.dayRain(night, date).timing)) == "In the early hours, clearing by morning.")
    }

    @Test("a sunset after midnight ends the daytime at midnight, with no evening")
    func lateSunset() {
        let f = forecastWith([(22, 1.0)], sunrise: { $0.atTime(2, 40) }, sunset: { $0.plusDays(1).atTime(0, 20) })
        let rain = Precip.dayRain(f, date)
        #expect(rain.periods.map(\.name) == ["Before sunrise", "Daytime"])
        #expect(rain.periods.last.map(label) == "3 AM–12 AM")
        #expect(rain.hours.allSatisfy { h in rain.periods.filter { $0.contains(h.time) }.count == 1 })
    }
}
