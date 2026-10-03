import Foundation
import Testing
@testable import Daybreak

/// Ported from Android's OutdoorScorerTest: single hours scored against the outdoor profile.
struct OutdoorScoreTests {
    private let base = TestData.forecast() // 2:30 PM, sunrise 7:02, sunset 18:56
    private var noon: LocalDateTime { base.current.time.withHour(12).withMinute(0) }
    private let outdoor = WeatherProfile.outdoor

    private func hour(
        time: LocalDateTime? = nil,
        tempC: Double = 18.0,
        precip: Int = 0,
        code: Int = 1,
        wind: Double? = 10.0,
        gust: Double? = 15.0
    ) -> HourForecast {
        HourForecast(time: time ?? noon, tempC: tempC, precipChance: precip, code: code, windKmh: wind, gustKmh: gust, isDay: nil)
    }

    private func score(_ h: HourForecast) -> HourScore { OutdoorScorer.score(h, base, outdoor) }

    @Test("a dry, mild, calm daylight hour is perfect")
    func perfect() {
        let s = score(hour())
        #expect(s.score == 100)
        #expect(s.limits.isEmpty)
    }

    @Test("storms rule an hour out, snow only dents it")
    func stormsAndSnow() {
        #expect(score(hour(precip: 60, code: 95)).score == 0)
        #expect(score(hour(precip: 60, code: 95)).limits == [.storm, .rain])
        let snow = score(hour(tempC: 2.0, precip: 25, code: 73))
        #expect((1..<Outlook.goodMin).contains(snow.score))
        #expect(snow.limits.contains(.snow))
        // A profile that can't take snow rules it out.
        #expect(OutdoorScorer.score(hour(precip: 25, code: 73), modified(outdoor) { $0.snowOk = false }, dark: false).score == 0)
    }

    @Test("codes only count when the hour's chance and amount aren't dry")
    func dryCodes() {
        // A rain or snow code with a 5% chance and nothing falling costs nothing.
        #expect(score(hour(precip: 5, code: 63)).score == 100)
        #expect(score(hour(precip: 5, code: 73)).score == 100)
        // A storm code with dry numbers costs a little, and is still named.
        let storm = score(hour(precip: 5, code: 95))
        #expect(storm.score == 70)
        #expect(storm.limits == [.storm])
    }

    @Test("each limit lowers the score and is named")
    func eachLimit() {
        #expect(score(hour(precip: 80, code: 63)).limits == [.rain])
        #expect(score(hour(wind: 40.0, gust: 65.0)).limits == [.wind])
        #expect(score(hour(tempC: -3.0)).limits == [.cold])
        #expect(score(hour(tempC: 35.0)).limits == [.heat])
        #expect(score(hour(time: noon.withHour(22))).limits == [.dark])
        for h in [hour(precip: 80, code: 63), hour(tempC: -3.0), hour(tempC: 35.0), hour(time: noon.withHour(22))] {
            #expect(score(h).score < Outlook.mehMin)
        }
        // Slightly cool but acceptable costs a little, not a lot.
        #expect(score(hour(tempC: 9.0)).score >= Outlook.greatMin)
    }

    @Test("missing wind data doesn't count against an hour")
    func missingWind() {
        #expect(score(hour(wind: nil, gust: nil)).score == 100)
    }

    @Test("crossing a wind or rain limit costs a step")
    func limitStep() {
        #expect(score(hour(wind: 38.0, gust: nil)).score < Outlook.greatMin)
        #expect(score(hour(precip: 35)).score >= Outlook.goodMin) // just over: dented, still fine
        #expect(score(hour(precip: 35)).limits == [.rain])
    }

    @Test("daylight is judged mid-hour, and now follows the current conditions")
    func daylight() {
        let sunrise = noon.withHour(7).withMinute(2)
        let sunset = noon.withHour(18).withMinute(5)
        let f = base.copy(days: base.days.map { day in
            modified(day) { $0.sunrise = day.date.atTime(7, 2); $0.sunset = day.date.atTime(18, 5) }
        })
        #expect(!OutdoorScorer.score(hour(time: sunrise.withMinute(0)), f, outdoor).limits.contains(.dark))
        #expect(OutdoorScorer.score(hour(time: sunset.withMinute(0)), f, outdoor).limits.contains(.dark))
        let dawn = f.copy(current: modified(f.current) { $0.time = sunrise.withMinute(30); $0.isDay = true })
        #expect(!OutdoorScorer.score(hour(time: sunrise.withMinute(0)), dawn, outdoor, isNow: true).limits.contains(.dark))
    }

    @Test("a dark hour is never more than poor")
    func darkIsPoor() {
        #expect(OutdoorScorer.score(hour(), outdoor, dark: true).score < Outlook.mehMin)
    }
}
