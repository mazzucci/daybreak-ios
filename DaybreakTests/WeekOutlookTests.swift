import Foundation
import Testing
@testable import Daybreak

private typealias DaySpec = TestData.DaySpec
private typealias Sun = TestData.Sun

/// Ported from Android's WeekOutlookTest: the "This week" outlook on synthetic weeks and the fixtures.
///
/// Android also checks the outlook's explanation (`explain(Term.WEEK, …)` from Glossary.kt) in three tests. The
/// Glossary isn't ported yet, so those checks look at what the explanation's sentences are built from (the focus
/// day's read, its best hours and its cap) with the same expected values; see the comments there.
struct WeekOutlookTests {
    /// Monday, October 5, 2026, 8 AM; the synthetic days have sunrise at 7 AM and sunset at 7 PM.
    private let monday = LocalDateTime(2026, 10, 5, 8, 0)

    private let fine = DaySpec()
    private let breezy = DaySpec(windKmh: 38.0, gustKmh: 50.0) // 79: good, not great
    private func rainy(_ hours: ClosedRange<Int> = 0...22, chance: Int = 85) -> DaySpec {
        DaySpec(highC: 13.0, rainHours: hours, chance: chance)
    }

    /// Breezy today, a rainy spell Tuesday to Thursday, a cool Friday, a sunny weekend.
    private var mixed: [DaySpec] {
        [breezy, rainy(8...20), rainy(), rainy(5...15), DaySpec(highC: 10.0, lowC: 5.0), DaySpec(highC: 21.0), DaySpec(highC: 19.0)] +
            Array(repeating: fine, count: 3)
    }

    private func outlook(
        _ days: [DaySpec],
        _ at: LocalDateTime? = nil,
        unit: TempUnit = .c,
        sun: Sun = .normal,
        weekend: Set<DayOfWeek> = weekendDays(nil),
        now: LocalDateTime? = nil
    ) -> WeekOutlook {
        let at = at ?? monday
        return weekOutlook(TestData.synthetic(days, at, sun), unit, weekend: weekend, now: now ?? at)
    }

    private var mondayDate: LocalDate { monday.date }

    private func instant(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }

    // MARK: The mixed week

    @Test("a mixed week names the spell and the weekend")
    func mixedWeek() {
        let o = outlook(mixed)
        #expect(o.today.text == "Good day to be outside")
        #expect(o.lines() == ["Rainy spell from tomorrow until Thursday", "Saturday is the best day this week"])
        #expect(o.days.count == 7)
        #expect(o.days.filter(\.isBest).map(\.date) == [LocalDate(2026, 10, 10)])
        #expect(o.days.map(\.tier) == [.good, .stayIn, .stayIn, .meh, .great, .great, .great])
        #expect(o.days.map(\.rain) == [.dry, .wet, .wet, .wet, .dry, .dry, .dry])
        #expect(o.days[5].spoken == "Saturday, best day, great for being outside, dry")
        #expect(o.days[1].spoken == "Tomorrow, one for staying in, rain likely")
        #expect(o.spoken == "Good day to be outside. Rainy spell from tomorrow until Thursday. Saturday is the best day this week.")
    }

    @Test("a day that's rainy for most of its daylight is mixed at best, however dry its end")
    func mostlyRainyDay() {
        let thursday = outlook(mixed).days[3]
        #expect(thursday.tier == .meh)
        #expect(thursday.score == Outlook.goodMin - 1)
    }

    // MARK: Spells

    @Test("a spell that starts today says when it ends")
    func spellFromToday() {
        let o = outlook([rainy(), rainy(), rainy(), fine, fine, fine, fine])
        #expect(o.today.text == "Better stay in: rain most of the day")
        #expect(o.week[0].text == "Wet until Wednesday, drier from Thursday")
        #expect(o.week[0].end == LocalDate(2026, 10, 7))
        #expect(o.week[0].kind == .wetSpell)
    }

    @Test("a spell past the week names its end when the data shows it")
    func spellPastTheWeek() {
        let o = outlook([fine, fine, fine, fine, rainy(), rainy(), rainy(), rainy(), rainy(), fine])
        #expect(o.week[0].text == "Rainy spell Friday to next Tuesday")
        // Starting on the last day of the week, it still counts when the day after is wet too.
        let late = outlook([fine, fine, fine, fine, fine, fine, rainy(), rainy(), fine, fine])
        #expect(late.week[0].text == "Rainy spell Sunday to next Monday")
        // "Into next week" only when it runs to the end of the data.
        let open = outlook([fine, fine, fine, fine, rainy(), rainy(), rainy(), rainy(), rainy(), rainy()])
        #expect(open.week[0].text == "Rainy from Friday, into next week")
        let all = outlook(Array(repeating: rainy(), count: 10))
        #expect(all.week[0].text == "Wet into next week")
    }

    @Test("a spell from today that ends tomorrow")
    func spellTodayAndTomorrow() {
        let o = outlook([rainy(), rainy(), fine, fine, fine, fine, fine])
        #expect(o.week[0].text == "Rain today and tomorrow, then drier")
        let showery = DaySpec(highC: 13.0, rainHours: 0...22, chance: 85)
        let s = TestData.synthetic([showery, showery] + Array(repeating: fine, count: 5), monday)
        let f = s.copy(days: s.days.enumerated().map { i, d in i < 2 ? modified(d) { $0.code = 81 } : d })
        #expect(weekOutlook(f, .c).week[0].text == "Showers today and tomorrow, then drier")
    }

    @Test("a showery spell is showers on and off")
    func showerySpell() {
        let s = TestData.synthetic([fine, fine, fine, rainy(), rainy(), rainy(), fine, fine], monday)
        let f = s.copy(days: s.days.enumerated().map { i, d in (3...5).contains(i) ? modified(d) { $0.code = 80 } : d })
        #expect(weekOutlook(f, .c).week[0].text == "Showers on and off Thursday to Saturday")
    }

    @Test("single wet days aren't a spell")
    func singleWetDays() {
        let o = outlook([fine, rainy(), fine, rainy(), fine, rainy(), fine, rainy(), fine, fine])
        #expect(o.week.allSatisfy { $0.kind != .wetSpell })
    }

    @Test("short daily bursts are rain on and off")
    func shortBursts() {
        let o = outlook([fine, fine, fine, rainy(9...12), rainy(9...12), rainy(9...12), fine, fine])
        #expect(o.week[0].text == "Rain on and off Thursday to Saturday")
    }

    @Test("a snow spell says snow")
    func snowSpell() {
        let snowy = DaySpec(highC: 0.0, lowC: -4.0, rainHours: 6...18, snow: true)
        let o = outlook([DaySpec(highC: 3.0, lowC: -2.0), snowy, snowy, DaySpec(highC: 2.0, lowC: -3.0), fine, fine, fine])
        #expect(o.week[0].text == "Snowy spell from tomorrow until Wednesday")
        #expect(o.days[1].snow)
        #expect(o.days[1].spoken == "Tomorrow, one for staying in, snow likely")
    }

    @Test("a wet day on its own turns dry again")
    func dryAgain() {
        let small = DaySpec(rainHours: 10...10, chance: 30, mmPerHour: 0.3) // possible, not dry
        let o = outlook([rainy(), small, fine, fine, fine, fine, fine])
        #expect(o.today.text == "Better stay in: rain most of the day")
        #expect(o.week[0].text == "Dry again from Wednesday")
        #expect(o.week[0].kind == .dryTurn)
    }

    // MARK: The best day

    @Test("a weekend day within five points is named over the best weekday")
    func weekendWithinFive() {
        let cool = DaySpec(highC: 11.0, lowC: 9.0) // 97
        let o = outlook([breezy, breezy, rainy(), fine, breezy, cool, breezy])
        #expect(o.bestDayLines() == ["Saturday is the best day this week"])
        // Further behind, the best day wins.
        let cold = DaySpec(highC: 8.0, lowC: 6.0) // 88
        let o2 = outlook([breezy, breezy, rainy(), fine, breezy, cold, breezy])
        #expect(o2.bestDayLines() == ["Thursday is the best day this week"])
    }

    @Test("the weekend follows the place's country")
    func countryWeekend() {
        let cool = DaySpec(highC: 11.0, lowC: 9.0)
        let o = outlook([breezy, breezy, rainy(), fine, cool, breezy, breezy], weekend: weekendDays("SA"))
        #expect(o.bestDayLines() == ["Friday is the best day this week"])
    }

    @Test("today can be the best day")
    func todayBest() {
        let o = outlook([fine, breezy, breezy, rainy(), breezy, breezy, breezy])
        #expect(o.bestDayLines() == ["Today's the best day this week"])
        #expect(o.days[0].isBest)
    }

    @Test("no best day when nothing stands out")
    func nothingStandsOut() {
        let o = outlook(Array(repeating: fine, count: 7))
        #expect(o.days.allSatisfy { !$0.isBest })
        #expect(o.lines() == ["Great all week"])
        #expect(outlook(Array(repeating: breezy, count: 7)).lines() == ["Good all week"])
        let blowy = DaySpec(windKmh: 45.0, gustKmh: 65.0) // mixed
        #expect(outlook([fine, fine, blowy, fine, fine, fine, fine]).lines() == ["Dry all week"])
    }

    @Test("with no good days, the least bad is named but not marked best")
    func poorWeek() {
        let gale = DaySpec(windKmh: 50.0, gustKmh: 80.0) // stay in
        let blowy = DaySpec(windKmh: 45.0, gustKmh: 65.0) // mixed
        let o = outlook([gale, gale, gale, blowy, gale, gale, gale])
        #expect(o.week.contains { $0.text == "Thursday is the best of a poor week" })
        #expect(o.days.allSatisfy { !$0.isBest })
    }

    // MARK: The today line

    @Test("the today line follows the main limit")
    func todayLine() {
        let sixFine = Array(repeating: fine, count: 6)
        #expect(outlook(Array(repeating: fine, count: 7)).today.text == "Great day to be outside")
        #expect(outlook(Array(repeating: breezy, count: 7)).today.text == "Good day to be outside")
        #expect(outlook([rainy(13...18)] + sixFine).today.text == "Mixed day: dry until 1 PM, then rain")
        #expect(outlook([rainy(6...13)] + sixFine).today.text == "Mixed day: rain until 2 PM, then drier")
        #expect(outlook([DaySpec(windKmh: 50.0, gustKmh: 85.0)] + sixFine).today.text == "Too windy to enjoy outside: gusts to 85 km/h")
        #expect(outlook([DaySpec(highC: 34.0, lowC: 22.0)] + sixFine).today.text == "Hot day: 34° by 3 PM, best before 12 PM")
        #expect(outlook([DaySpec(highC: 4.0, lowC: 0.0)] + sixFine).today.text == "Cold but good to be outside")
        #expect(outlook([DaySpec(highC: 2.0, lowC: 0.0, windKmh: 38.0, gustKmh: 50.0)] + sixFine).today.text
            == "Blustery day: gusts to 50 km/h")
        #expect(outlook([DaySpec(highC: -6.0, lowC: -12.0)] + sixFine).today.text == "Too cold to enjoy outside: no warmer than \u{2212}6°")
        // Cold but otherwise fine, under polar night: mixed at best, and the cold is why.
        #expect(outlook(Array(repeating: DaySpec(highC: 4.0, lowC: 2.0), count: 7), monday.withHour(10), sun: .polarNight).today.text
            == "Cold day: no warmer than 4°")
        // Tomorrow, in the evening.
        let evening = monday.withHour(20)
        #expect(outlook(Array(repeating: breezy, count: 7), evening).today.text == "Tomorrow looks good outside")
        #expect(outlook([fine, rainy()] + Array(repeating: fine, count: 5), evening).today.text
            == "Better stay in tomorrow: rain most of the day")
        #expect(outlook(Array(repeating: DaySpec(highC: 34.0, lowC: 22.0), count: 7), evening).today.text
            == "Hot day tomorrow: 34° by 3 PM, best before 11 AM")
        // No semicolons anywhere.
        for days in [mixed, Array(repeating: DaySpec(highC: 34.0, lowC: 22.0), count: 7), Array(repeating: DaySpec(highC: 2.0, lowC: -2.0), count: 7)] {
            let o = outlook(days)
            for line in [o.today] + o.week { #expect(!line.text.contains(";"), "\(line.text)") }
        }
    }

    @Test("the today line only counts the daylight still ahead")
    func daylightAhead() {
        let showersLater = [rainy(14...18)] + Array(repeating: fine, count: 6)
        #expect(outlook(showersLater).today.text == "Mixed day: dry until 2 PM, then rain")
        #expect(outlook(showersLater, monday.withHour(14).withMinute(10)).today.text == "Better stay in: rain most of the day")
    }

    @Test("in the evening the today line is about tomorrow")
    func eveningIsTomorrow() {
        let evening = monday.withHour(19).withMinute(20)
        let o = outlook(Array(repeating: fine, count: 7), evening)
        #expect(o.today.text == "Tomorrow looks great outside")
        #expect(o.days[0].score == nil)
        #expect(o.days[0].tier == nil)
        #expect(o.days[0].spoken == "Today, daylight's over, dry")
        #expect(o.focus?.date == LocalDate(2026, 10, 6))
        #expect(outlook(mixed, evening).today.text == "Better stay in tomorrow: rain most of the day")
    }

    @Test("under two daylight hours left today has no score")
    func underTwoHoursLeft() {
        let late = outlook(Array(repeating: fine, count: 7), monday.withHour(17).withMinute(45)) // only 6 PM is left
        #expect(late.days[0].score == nil)
        #expect(late.days[0].spoken == "Today, not enough daylight left, dry")
        #expect(outlook(Array(repeating: fine, count: 7), monday.withHour(16).withMinute(45)).days[0].score == 100) // 5 PM and 6 PM
    }

    @Test("a day with under two hours of daylight is judged like polar night")
    func shortDay() throws {
        func short(_ at: LocalDateTime) -> Forecast {
            let f = TestData.synthetic(Array(repeating: DaySpec(highC: 14.0, lowC: 12.0), count: 7), monday)
            return f.copy(
                current: modified(f.current) { $0.time = at },
                days: f.days.enumerated().map { i, d in
                    i == 0 ? modified(d) { $0.sunrise = d.date.atTime(11, 40); $0.sunset = d.date.atTime(12, 20) } : d
                }
            )
        }
        let morning = weekOutlook(short(monday.withHour(10)), .c)
        let score = try #require(morning.days[0].score)
        #expect(score <= Outlook.goodMin - 1, "\(score)")
        #expect(try #require(morning.focus).shortDay)
        #expect(morning.today.text.hasPrefix("Little daylight today, but dry"), "\(morning.today.text)")
        let after = weekOutlook(short(monday.withHour(12).withMinute(30)), .c)
        #expect(after.days[0].score == nil)
        #expect(after.days[0].spoken == "Today, daylight's over, dry")
        // The explanation gives no hours for a day without daylight. Android checks its sentence ("Today scores
        // \(score) out of 100, from its best 3 waking hours still ahead.", with no hours in brackets); without the
        // Glossary, this checks what it's built from: today's read, from its best 3 waking hours (dim), not the daily
        // figures.
        let read = try #require(morning.focus)
        #expect(read.date == mondayDate && read.dim && !read.fromDaily && read.best.count == 3 && read.score == score)
    }

    @Test("polar night scores the waking hours, never above mixed")
    func polarNight() throws {
        let o = outlook(Array(repeating: DaySpec(highC: 14.0, lowC: 12.0), count: 7), monday.withHour(10), sun: .polarNight)
        #expect(o.days.allSatisfy { $0.tier == .meh })
        #expect(o.today.text == "No daylight today, but dry")
        #expect(outlook(Array(repeating: DaySpec(highC: -6.0, lowC: -12.0), count: 7), monday.withHour(10), sun: .polarNight).today.text
            == "Too cold to enjoy outside: no warmer than \u{2212}6°")
        // Android checks the explanation here: no hours ("PM)") and "It's polar night, so it can't score higher than
        // mixed." at the end. Without the Glossary: the read it describes is a polar night's, from waking hours.
        let night = weekOutlook(TestData.synthetic(Array(repeating: DaySpec(highC: 14.0, lowC: 12.0), count: 7), monday.withHour(19), .polarNight), .c)
        let read = try #require(night.focus)
        #expect(read.polarNight && read.dim && !read.fromDaily)
        #expect(read.tier == .meh)
    }

    @Test("polar day scores the waking hours")
    func polarDay() throws {
        let days = Array(repeating: DaySpec(highC: 14.0, lowC: 6.0), count: 7)
        let night = outlook(days, monday.withHour(23), sun: .midnightSun)
        #expect(night.days[0].score == nil) // still light, but past waking hours
        #expect(night.today.text.hasPrefix("Tomorrow looks great"))
        let read = try #require(night.focus)
        #expect(read.hours.first?.hour.time.hour == 6)
        #expect(read.hours.last?.hour.time.hour == 21)
    }

    // MARK: Week lines

    @Test("a heat spell, and its end isn't a cold snap")
    func heatSpell() {
        let o = outlook([DaySpec(highC: 34.0, lowC: 22.0), DaySpec(highC: 35.0, lowC: 23.0), DaySpec(highC: 31.0, lowC: 20.0), DaySpec(highC: 27.0), fine, fine, fine])
        #expect(o.lines() == ["Hot until Wednesday, up to 35°"])
        let later = outlook([fine, fine, DaySpec(highC: 31.0), DaySpec(highC: 33.0), DaySpec(highC: 30.0), fine, fine])
        #expect(later.lines() == ["Hot spell Wednesday to Friday, up to 33°"])
    }

    @Test("a cold snap and the first frost")
    func coldSnapAndFrost() {
        let o = outlook([DaySpec(highC: 18.0), DaySpec(highC: 16.0), DaySpec(highC: 9.0, lowC: 2.0), DaySpec(highC: 8.0, lowC: -1.0), fine, fine, fine])
        #expect(o.lines() == ["Much colder Wednesday: 9°, down from 18° today"])
        let frost = outlook([DaySpec(highC: 12.0, lowC: 3.0), DaySpec(highC: 10.0, lowC: 1.0), DaySpec(highC: 9.0, lowC: -2.0), fine, fine, fine, fine])
        #expect(frost.lines() == ["Frost by Wednesday morning: down to \u{2212}2°"])
        // Not news when it's already freezing.
        #expect(outlook([DaySpec(highC: 3.0, lowC: -1.0), DaySpec(highC: 3.0, lowC: -3.0), fine, fine, fine, fine, fine]).week
            .allSatisfy { $0.kind != .frost })
    }

    @Test("big wind skips the day the today line already calls too windy")
    func bigWindSkipsToday() {
        let o = outlook([DaySpec(windKmh: 50.0, gustKmh: 85.0), fine, DaySpec(gustKmh: 75.0), fine, fine, fine, fine])
        #expect(o.today.text == "Too windy to enjoy outside: gusts to 85 km/h")
        #expect(o.lines() == ["Very windy Wednesday: gusts to 75 km/h"])
    }

    @Test("at most two week lines, highest priority first")
    func twoLines() {
        let o = outlook([DaySpec(highC: 31.0), DaySpec(highC: 32.0), rainy(), rainy(), DaySpec(gustKmh: 80.0), DaySpec(highC: 12.0, lowC: -1.0), fine])
        #expect(o.week.map(\.kind) == [.wetSpell, .bigWind])
    }

    // MARK: Units and words

    @Test("temperatures and wind follow the unit, and screen readers hear both")
    func units() {
        let sixFine = Array(repeating: fine, count: 6)
        let hot = outlook([DaySpec(highC: 34.0, lowC: 22.0)] + sixFine, unit: .f)
        #expect(hot.today.text == "Hot day: 93° by 3 PM, best before 12 PM")
        #expect(hot.today.spoken == "Hot day: 93°F (34°C) by 3 PM, best before 12 PM")
        let spell = outlook([fine, fine, DaySpec(highC: 31.0), DaySpec(highC: 33.0), DaySpec(highC: 30.0), fine, fine], unit: .f)
        #expect(spell.week[0].text == "Hot spell Wednesday to Friday, up to 91°")
        #expect(spell.week[0].spoken == "Hot spell Wednesday to Friday, up to 91°F (33°C)")
        let windy = outlook([DaySpec(windKmh: 50.0, gustKmh: 85.0)] + sixFine, unit: .f)
        #expect(windy.today.text == "Too windy to enjoy outside: gusts to 53 mph")
        let snap = outlook([DaySpec(highC: 18.0), DaySpec(highC: 16.0), DaySpec(highC: 9.0, lowC: 2.0), fine, fine, fine, fine], unit: .f)
        #expect(snap.week[0].text == "Much colder Wednesday: 48°, down from 64° today")
    }

    @Test("hour spans are compact, and follow the 24-hour clock")
    func spans() {
        let day = LocalDate(2026, 10, 5)
        #expect(formatSpan(day.atTime(13, 0), day.atTime(17, 0)) == "1–5 PM")
        #expect(formatSpan(day.atTime(11, 0), day.atTime(14, 0)) == "11 AM–2 PM")
        #expect(formatSpan(day.atTime(21, 0), day.plusDays(1).atStartOfDay) == "9 PM–12 AM")
        // Android sets ClockFormat.use24Hour for this and puts it back after the test; here the clock is passed in,
        // so tests running alongside never see the 24-hour clock.
        #expect(formatSpan(day.atTime(13, 0), day.atTime(17, 0), use24Hour: true) == "13:00–17:00")
    }

    @Test("day names")
    func dayNames() {
        let today = LocalDate(2026, 10, 5) // a Monday
        #expect(outlookDayName(today, today) == "today")
        #expect(outlookDayName(today.plusDays(1), today) == "tomorrow")
        #expect(outlookDayName(today.plusDays(5), today) == "Saturday")
        #expect(outlookDayName(today.plusDays(6), today) == "Sunday")
        #expect(outlookDayName(today.plusDays(7), today) == "next Monday")
    }

    // MARK: Never contradicting Precip

    /// Every outlook surface agrees with the day page's rules, whatever the forecast and the time.
    private func expectAgreesWithPrecip(_ forecast: Forecast, now: LocalDateTime? = nil,
                                        sourceLocation: SourceLocation = #_sourceLocation) {
        let goodLine = /^(Great day|Good day|Cold but good|Tomorrow looks (great|good|cold but good))/
        let rainWords = /\b(rain|rainy|wet|showers|snow|snowy|thunderstorms|drizzle)\b/.ignoresCase().wordBoundaryKind(.simple)
        let o = weekOutlook(forecast, .c, now: now ?? forecast.current.time)
        for day in o.days {
            let rain = Precip.dayRain(forecast, day.date)
            #expect(day.rain == rain.kind, sourceLocation: sourceLocation)
            // The strip says what the day page's verdict says ("rain likely", "showers possible"), or "dry".
            let head = Precip.verdict(rain, .c).components(separatedBy: " · ")[0]
            let verdict = rain.dry ? "dry" : head.prefix(1).lowercased() + head.dropFirst()
            #expect(day.spoken.hasSuffix(verdict), "\(day.spoken) vs \(verdict)", sourceLocation: sourceLocation)
            // A dry day is never called rainy.
            if rain.dry {
                for line in [o.today] + o.week where line.date == day.date && line.kind != .dryTurn {
                    #expect(!line.text.contains(rainWords), "\(line.text)", sourceLocation: sourceLocation)
                }
            }
        }
        // Every day of a spell is wet.
        let spells = o.week.filter { $0.kind == .wetSpell }
        for spell in spells {
            var d = spell.date!
            while d <= spell.end! {
                #expect(Precip.dayRain(forecast, d).kind == .wet, "\(d) in \(spell.text)", sourceLocation: sourceLocation)
                d = d.plusDays(1)
            }
        }
        func inSpell(_ date: LocalDate) -> Bool { spells.contains { date >= $0.date! && date <= $0.end! } }
        for line in o.week where line.kind == .dryTurn {
            #expect(Precip.dayRain(forecast, line.date!).dry, sourceLocation: sourceLocation)
            // "Dry again" only after a wet today line.
            #expect(o.today.topic == .wet, "\(o.today.text)", sourceLocation: sourceLocation)
        }
        // The best day is never wet, nor inside the spell.
        let bestDates = o.days.filter(\.isBest).map(\.date) + o.week.filter { $0.kind == .bestDay }.map { $0.date! }
        for date in bestDates {
            #expect(Precip.dayRain(forecast, date).kind != .wet, "\(date)", sourceLocation: sourceLocation)
            #expect(!inSpell(date), "\(date)", sourceLocation: sourceLocation)
        }
        // A good or great today line never sits next to a spell over its own day.
        if o.today.text.contains(goodLine) {
            #expect(!inSpell(o.today.date!), "\(o.today.text) vs \(o.lines())", sourceLocation: sourceLocation)
        }
        // "Dry until 2 PM": every hour before then is dry by the classifier.
        if let m = o.today.text.firstMatch(of: /dry until (\d+) (AM|PM)/) {
            let h = Int(m.1)! % 12 + (m.2 == "PM" ? 12 : 0)
            let date = o.today.date!
            for hour in forecast.hoursOf(date) where (1...h).contains(hour.time.hour) && hour.time > forecast.current.time {
                #expect(Precip.classify(hour.precipChance, hour.precipMm).dry, "\(hour)", sourceLocation: sourceLocation)
            }
        }
    }

    @Test("the outlook never contradicts the rain rules")
    func agreesWithPrecip() throws {
        let alps = TestData.alps()
        for h in [3, 9, 12, 15, 18] {
            expectAgreesWithPrecip(alps.copy(current: modified(alps.current) { $0.time = LocalDateTime(2026, 10, 1, h, 15) }))
        }
        expectAgreesWithPrecip(TestData.forecast())
        expectAgreesWithPrecip(TestData.rainyNight())
        expectAgreesWithPrecip(TestData.synthetic(mixed, monday))
        expectAgreesWithPrecip(TestData.synthetic([rainy(13...18)] + Array(repeating: fine, count: 6), monday))
        for days in repros {
            for h in [7, 8, 13, 17, 20] { expectAgreesWithPrecip(TestData.synthetic(days, monday.withHour(h).withMinute(15))) }
        }
    }

    /// The forecasts behind the review's bugs: rain outside daylight, a wet day inside a spell, a wet Saturday.
    private var small: DaySpec { DaySpec(rainHours: 10...10, chance: 30, mmPerHour: 0.3) }
    private var repros: [[DaySpec]] {
        [
            [rainy(0...5), rainy(0...5)] + Array(repeating: fine, count: 5),
            [rainy(0...5), small] + Array(repeating: fine, count: 5),
            [breezy, rainy(), rainy(0...4), rainy()] + Array(repeating: breezy, count: 3),
            [breezy, breezy, rainy(), fine, breezy, rainy(0...4), breezy],
            [rainy(20...22), rainy(0...3)] + Array(repeating: fine, count: 5),
        ]
    }

    // MARK: Lines that agree with each other (B1)

    @Test("rain before sunrise doesn't start a spell next to a great day")
    func rainBeforeSunrise() {
        let o = outlook(repros[0])
        #expect(o.today.text == "Great day to be outside")
        #expect(o.week.allSatisfy { $0.kind != .wetSpell && $0.kind != .dryTurn }, "\(o.lines())")
        // Still wet by the rain rules: the strip keeps its glyphs.
        #expect(o.days[0].rain == .wet)
    }

    @Test("dry again only follows a wet today line")
    func dryAgainAfterWet() {
        #expect(outlook(repros[1]).week.allSatisfy { $0.kind != .dryTurn })
    }

    @Test("the best day is never a wet day or inside the spell")
    func bestNotWet() {
        let o = outlook(repros[2])
        #expect(o.week[0].text == "Rainy spell from tomorrow until Thursday")
        #expect(o.week.allSatisfy { $0.kind != .bestDay }, "\(o.lines())")
        #expect(o.days.allSatisfy { !$0.isBest })
    }

    @Test("a wet Saturday isn't picked by the weekend rule")
    func wetSaturday() {
        let o = outlook(repros[3])
        #expect(o.bestDayLines() == ["Thursday is the best day this week"])
    }

    @Test("the weekend pick has to stand out itself")
    func weekendStandsOut() {
        // Saturday (97) is within five points of Thursday (100), but not ten over the median (88): Thursday it is.
        let cold = DaySpec(highC: 8.0, lowC: 6.0) // 88
        let cool = DaySpec(highC: 11.0, lowC: 9.0) // 97
        let o = outlook([cold, cold, cold, fine, cold, cool, rainy()])
        #expect(o.bestDayLines() == ["Thursday is the best day this week"])
    }

    @Test("tonight's rain doesn't start a spell next to tomorrow's great day")
    func tonightsRain() {
        let o = outlook(repros[4], monday.withHour(20))
        #expect(o.today.text.hasPrefix("Tomorrow looks great"), "\(o.today.text)")
        #expect(o.week.allSatisfy { $0.kind != .wetSpell }, "\(o.lines())")
    }

    // MARK: The clock (R1)

    @Test("at 8 PM a forecast from 2 PM is about tomorrow")
    func clockMovesOn() {
        let f = TestData.synthetic([rainy(9...14)] + Array(repeating: fine, count: 6), monday.withHour(14))
        #expect("Great day to be outside, best 3–6 PM".components(separatedBy: ",")[0]
            == weekOutlook(f, .c).today.text.components(separatedBy: ",")[0])
        let clock = Date(timeIntervalSince1970: TimeInterval(monday.withHour(20).seconds)) // 8 PM UTC
        let later = weekOutlook(f, .c, now: outlookMoment(f, clock))
        #expect(!later.today.text.contains("3–6 PM"), "\(later.today.text)")
        #expect(later.today.text == "Tomorrow looks great outside")
        #expect(later.days[0].score == nil)
    }

    @Test("the outlook's moment is the later of the forecast and the clock, at the place, to the hour")
    func moment() {
        let f = TestData.synthetic(Array(repeating: fine, count: 7), monday.withHour(14).withMinute(20)).copy(utcOffsetSeconds: 7200)
        // 18:40 UTC is 20:40 at the place: 8 PM.
        #expect(outlookMoment(f, instant("2026-10-05T18:40:00Z")) == monday.withHour(20))
        // A clock behind the forecast (a phone that's slow) never takes it back.
        #expect(outlookMoment(f, instant("2026-10-05T10:00:00Z")) == monday.withHour(14).withMinute(20))
    }

    @Test("daylight saving - the moment follows the forecast's own offset, and a short night still scores")
    func daylightSaving() {
        // Fetched in summer time (UTC+2) before the clocks go back on Sunday, October 25; viewed after.
        let sunday = LocalDateTime(2026, 10, 25, 8, 0)
        let f = TestData.synthetic(Array(repeating: fine, count: 7), sunday).copy(utcOffsetSeconds: 7200)
        // 9:30 UTC is 10:30 on the phone (UTC+1 by then), but 11:30 in the forecast's stamps.
        #expect(outlookMoment(f, instant("2026-10-25T09:30:00Z")) == sunday.withHour(11))
        // A day missing its 2 AM stamp (the spring change) is scored as usual, not as a short day.
        let spring = f.copy(hours: f.hours.filter { $0.time != sunday.date.plusDays(1).atTime(2) })
        let read = weekOutlook(spring, .c).days[1]
        #expect(read.tier == .great)
    }

    // MARK: Rain in a good day (R2) and the pattern

    @Test("a good day says where its rain falls")
    func goodDayRain() {
        let morning = TestData.synthetic(Array(repeating: fine, count: 7), monday).rainDuring(mondayDate, 8, 9)
        #expect(weekOutlook(morning, .c).today.text == "Great day to be outside, best from 10 AM after rain")
        let later = TestData.synthetic(Array(repeating: fine, count: 7), monday).rainDuring(mondayDate, 17, 18)
        #expect(weekOutlook(later, .c).today.text == "Great day to be outside, best before 5 PM, then rain")
    }

    @Test("rain in a third of the hours makes a mixed day")
    func thirdWet() {
        let o = outlook([rainy(13...16)] + Array(repeating: fine, count: 6))
        #expect(o.days[0].tier == .meh)
        #expect(o.today.text == "Mixed day: dry until 1 PM, then rain")
    }

    @Test("rain early and late is on and off, not until then drier")
    func earlyAndLate() {
        let f = TestData.synthetic(Array(repeating: fine, count: 7), monday).rainDuring(mondayDate, 8, 9, 15, 16)
        #expect(weekOutlook(f, .c).today.text == "Mixed day: rain on and off")
    }

    // MARK: Codes and wind (R3, R4, R5, B3)

    @Test("a rain code with dry numbers costs nothing, a storm code costs a little and is named")
    func codes() {
        let drizzleCode = TestData.synthetic(Array(repeating: fine, count: 7), monday).editHours(mondayDate, 0...23) { $0.code = 61 }
        #expect(weekOutlook(drizzleCode, .c).days[0].score == 100)
        let stormy = TestData.synthetic(Array(repeating: fine, count: 7), monday).editHours(mondayDate, 13...15) { $0.code = 95 }
        let o = weekOutlook(stormy, .c)
        #expect(o.today.text == "Great day to be outside, best before 1 PM, risk of thunderstorms")
        // Storms with a real chance but no rain worth the name: no rain pattern, still a reason.
        let near = TestData.synthetic(Array(repeating: fine, count: 7), monday).editHours(mondayDate, 0...23) {
            $0.code = 95; $0.precipChance = 35
        }
        #expect(weekOutlook(near, .c).today.text == "Better stay in: risk of thunderstorms")
    }

    @Test("the outlook reads the code at the hour, rain and gusts from the hour after")
    func stamps() throws {
        let f = TestData.synthetic(Array(repeating: fine, count: 7), monday)
            .editHours(mondayDate, 15...15) { $0.code = 95 }
            .editHours(mondayDate, 16...16) { $0.gustKmh = 80.0; $0.precipChance = 60; $0.precipMm = 2.0 }
        let three = withRainDuring(f, try #require(f.hourAt(monday.withHour(15))))
        #expect(three.code == 95)
        #expect(three.gustKmh == 80.0)
        #expect(three.precipChance == 60)
        #expect(withRainDuring(f, try #require(f.hourAt(monday.withHour(14)))).code == 1)
    }

    @Test("wind without gusts says wind")
    func windWithoutGusts() {
        let noGusts = TestData.synthetic(Array(repeating: fine, count: 7), monday).editHours(mondayDate, 0...23) {
            $0.windKmh = 50.0; $0.gustKmh = nil
        }
        #expect(weekOutlook(noGusts, .c).today.text == "Blustery day: wind to 50 km/h")
        let weakGusts = TestData.synthetic(Array(repeating: fine, count: 7), monday).editHours(mondayDate, 0...23) {
            $0.windKmh = 50.0; $0.gustKmh = 30.0
        }
        #expect(weekOutlook(weakGusts, .c).today.text == "Blustery day: wind to 50 km/h")
    }

    @Test("a gale counts only in the scored hours, and not on a today that's over")
    func galeInScoredHours() {
        let wednesday = mondayDate.plusDays(2)
        let windyNight = TestData.synthetic(Array(repeating: fine, count: 7), monday).editHours(wednesday, 0...4) { $0.gustKmh = 90.0 }
        let night = windyNight.copy(days: windyNight.days.map { $0.date == wednesday ? modified($0) { $0.gustMaxKmh = 90.0 } : $0 })
        #expect(weekOutlook(night, .c).week.allSatisfy { $0.kind != .bigWind })
        let day = TestData.synthetic(Array(repeating: fine, count: 7), monday).editHours(wednesday, 12...14) { $0.gustKmh = 90.0 }
        #expect(weekOutlook(day, .c).week.filter { $0.kind == .bigWind }.map(\.text) == ["Very windy Wednesday: gusts to 90 km/h"])
        let evening = monday.withHour(20)
        let today = TestData.synthetic(Array(repeating: fine, count: 7), evening).editHours(mondayDate, 10...14) { $0.gustKmh = 90.0 }
        #expect(weekOutlook(today, .c).week.allSatisfy { $0.kind != .bigWind })
    }

    // MARK: Frost (R8)

    @Test("frost needs a morning that rounds below zero, and first frost needs five frost-free mornings")
    func frostRounding() {
        let nearly = outlook([DaySpec(highC: 12.0, lowC: 3.0), DaySpec(highC: 9.0, lowC: -0.4), fine, fine, fine, fine, fine])
        #expect(nearly.week.allSatisfy { $0.kind != .frost })
        let nearlyF = outlook([DaySpec(highC: 12.0, lowC: 3.0), DaySpec(highC: 9.0, lowC: -0.4), fine, fine, fine, fine, fine], unit: .f)
        #expect(nearlyF.week.allSatisfy { $0.kind != .frost })
        let frostF = outlook([DaySpec(highC: 12.0, lowC: 3.0), DaySpec(highC: 10.0, lowC: 1.0), DaySpec(highC: 9.0, lowC: -2.0), fine, fine, fine, fine], unit: .f)
        #expect(frostF.lines() == ["Frost by Wednesday morning: down to 28°"])
        let first = outlook([fine, fine, fine, fine, fine, DaySpec(highC: 13.0, lowC: -2.0), fine])
        #expect(first.lines() == ["First frost by Saturday morning: down to \u{2212}2°"])
    }

    @Test("the morning low comes from midnight to 9 AM")
    func morningLow() {
        // A cold evening on Tuesday doesn't make Tuesday morning frosty; a cold 3 AM does.
        let base = TestData.synthetic(Array(repeating: DaySpec(highC: 12.0, lowC: 3.0), count: 7), monday)
        let tuesday = mondayDate.plusDays(1)
        let evening = base.editHours(tuesday, 21...23) { $0.tempC = -3.0 }
        #expect(weekOutlook(evening, .c).week.allSatisfy { $0.kind != .frost })
        let small = base.editHours(tuesday, 3...3) { $0.tempC = -3.0 }
        #expect(weekOutlook(small, .c).week.filter { $0.kind == .frost }.map(\.text) == ["Frost by tomorrow morning: down to \u{2212}3°"])
    }

    @Test("a wet day with a chance under 70 percent is possible, not likely")
    func possibleNotLikely() {
        let o = outlook([fine, DaySpec(rainHours: 9...12, chance: 55), fine, fine, fine, fine, fine])
        #expect(o.days[1].rain == .wet)
        #expect(o.days[1].spoken.hasSuffix("rain possible"))
    }

    // MARK: Fixtures

    @Test("the Alps fixture")
    func alpsFixture() {
        let alps = TestData.alps() // Thursday 3:15 AM, 3,200 m: showers today, wet overnight, then dry and near freezing
        let o = weekOutlook(alps, .c)
        #expect(o.today.text == "Mixed day: showers on and off")
        #expect(o.lines() == ["Showers today and tomorrow, then drier", "First frost by Tuesday morning: down to \u{2212}2°"])
        // Friday's rain is overnight: a wet day by the rain rules, a good one for being outside.
        #expect(o.days[1].rain == .wet)
        #expect(o.days[1].tier == .good)
        let evening = weekOutlook(alps.copy(current: modified(alps.current) { $0.time = LocalDateTime(2026, 10, 1, 18, 40) }), .c)
        #expect(evening.today.text == "Tomorrow looks cold but good outside")
    }

    @Test("the San Francisco week is dry and great")
    func sanFranciscoWeek() throws {
        let sf = try parseForecast(TestData.fixture("forecast_sf_week.json"))
        let o = weekOutlook(sf, .f)
        #expect(o.today.text == "Great day to be outside")
        #expect(o.lines() == ["Great all week"])
        #expect(o.days.allSatisfy { $0.tier == .great && $0.rain == .dry })
    }

    @Test("days past the hourly data are scored from their daily figures")
    func dailyFigures() {
        let o = weekOutlook(TestData.forecast(), .f) // 12 hours of hourly data
        #expect(o.today.text == "Mixed day: dry until 5 PM, then rain")
        #expect(o.days[2].tier == .stayIn) // the wet Wednesday
        #expect(o.days[1].tier == .great)
    }

    @Test("the explanation describes the day the today line is about")
    func explanation() throws {
        // Android checks explain(Term.WEEK, …) here: its title, value ("Mixed"), detail ("Today: 59 out of 100"), the
        // sentence "Today scores 59 out of 100, from its best 3 hours of daylight still ahead (10 AM–1 PM)." ending
        // "Rain falls in at least a third of its hours, so it can't score higher than mixed.", the band "outside
        // 12–26°C." (and "54–79°F."), and in the evening "Tomorrow scores 100". The Glossary isn't ported yet, so
        // this checks the outlook figures those come from, with the same values.
        let f = TestData.synthetic([rainy(13...18)] + Array(repeating: fine, count: 6), monday)
        let read = try #require(weekOutlook(f, .c).focus)
        #expect(read.date == mondayDate)
        #expect(read.tier.word == "Mixed")
        #expect(read.score == 59)
        #expect(read.best.count == 3)
        #expect(formatSpan(read.best[0].hour.time, read.best[2].hour.time.plusHours(1)) == "10 AM–1 PM")
        #expect(read.mostlyWet && read.tier == .meh && !read.polarNight && !read.shortDay)
        let profile = WeatherProfile.outdoor
        #expect("\(degrees(profile.idealC.lowerBound, .c))–\(formatTemp(profile.idealC.upperBound, .c))" == "12–26°C")
        #expect("\(degrees(profile.idealC.lowerBound, .f))–\(formatTemp(profile.idealC.upperBound, .f))" == "54–79°F")
        let evening = try #require(weekOutlook(TestData.synthetic(Array(repeating: fine, count: 7), monday.withHour(20)), .f).focus)
        #expect(evening.date == mondayDate.plusDays(1))
        #expect(evening.score == 100)
    }
}

private extension WeekOutlook {
    func lines() -> [String] { week.map(\.text) }

    /// The best-day line's text, as a list so a test can check there's exactly one (Kotlin's `single`).
    func bestDayLines() -> [String] { week.filter { $0.kind == .bestDay }.map(\.text) }
}

private extension Forecast {
    /// [edit] applied to the hours of [date] stamped in [stamps].
    func editHours(_ date: LocalDate, _ stamps: ClosedRange<Int>, _ edit: (inout HourForecast) -> Void) -> Forecast {
        copy(hours: hours.map { $0.time.date == date && stamps.contains($0.time.hour) ? modified($0, edit) : $0 })
    }

    /// Rain (80%, 1.5 mm, code 63) falling during the hours starting at [hours] of [date]: stamped an hour later.
    func rainDuring(_ date: LocalDate, _ hours: Int...) -> Forecast {
        copy(hours: self.hours.map { h in
            h.time.date == date && hours.contains(h.time.hour - 1)
                ? modified(h) { $0.precipChance = 80; $0.precipMm = 1.5; $0.code = 63 } : h
        })
    }
}
