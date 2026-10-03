import CoreGraphics
import Foundation
import Testing
@testable import Daybreak

/// What the This week card and Home's today line rely on: the outlook follows the day rains the page hands it (the
/// same ones its 10-day list shows), the best day it marks is one of the strip's, and the strip's names thin out to
/// fit their columns.
struct ThisWeekWiringTests {
    /// Monday, October 5, 2026, 8 AM: a breezy Monday, rain Tuesday to Thursday, a cool Friday, then a fine weekend
    /// (WeekOutlookTests' mixed week, whose best day is Saturday).
    private let monday = LocalDateTime(2026, 10, 5, 8, 0)
    private var mixed: Forecast {
        let rainy = { (hours: ClosedRange<Int>) in TestData.DaySpec(highC: 13.0, rainHours: hours, chance: 85) }
        let specs = [TestData.DaySpec(windKmh: 38.0, gustKmh: 50.0), rainy(8...20), rainy(0...22), rainy(5...15),
                     TestData.DaySpec(highC: 10.0, lowC: 5.0), TestData.DaySpec(highC: 21.0),
                     TestData.DaySpec(highC: 19.0)] + Array(repeating: TestData.DaySpec(), count: 3)
        return TestData.synthetic(specs, monday)
    }

    @Test("the outlook follows the rains the page hands it, not its own")
    func followsThePagesRains() {
        let forecast = mixed
        let own = forecast.upcomingDays().map { Precip.dayRain(forecast, $0.date) }
        #expect(weekOutlook(forecast, .c, now: monday).days.map(\.rain) == [.dry, .wet, .wet, .wet, .dry, .dry, .dry])

        // The same days, read as if Tuesday to Thursday were dry: the strip and the lines follow.
        let dry = Precip.dayRain(forecast, forecast.today.date)
        let handed = own.enumerated().map { i, rain in (1...3).contains(i) ? Self.redated(dry, rain.date) : rain }
        let outlook = weekOutlook(forecast, .c, now: monday, rains: handed)
        #expect(outlook.days.map(\.rain) == Array(repeating: DayKind.dry, count: 7))
        #expect(!outlook.week.contains { $0.kind == .wetSpell })

        // Rains for other days than the forecast's are set aside for its own.
        let shifted = own.map { Self.redated($0, $0.date.plusDays(30)) }
        #expect(weekOutlook(forecast, .c, now: monday, rains: shifted).days.map(\.rain)
            == weekOutlook(forecast, .c, now: monday).days.map(\.rain))
    }

    @Test("the best day it marks is one of the strip's days, and only one")
    func bestIsInTheStrip() {
        let outlook = weekOutlook(mixed, .c, now: monday)
        let best = try! #require(outlook.bestDate)
        #expect(best == LocalDate(2026, 10, 10))
        #expect(outlook.days.filter(\.isBest).map(\.date) == [best])
        #expect(mixed.upcomingDays().contains { $0.date == best })
    }

    @Test("day names thin from Today to three letters to initials as the columns narrow")
    func dayNames() {
        let dates = (0..<7).map { LocalDate(2026, 10, 5).plusDays($0) }
        let today = dates[0]
        // A stand-in for the font: ten points a letter.
        let width = { (s: String) in CGFloat(s.count * 10) }
        #expect(dayStripLabels(dates, today: today, room: 60, widthOf: width)
            == ["Today", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(dayStripLabels(dates, today: today, room: 40, widthOf: width)
            == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(dayStripLabels(dates, today: today, room: 20, widthOf: width)
            == ["M", "T", "W", "T", "F", "S", "S"])
        // Before the first layout (no width yet): the long names.
        #expect(dayStripLabels(dates, today: today, room: -4, widthOf: width).first == "Today")
    }

    /// [rain] as if it were [date]'s.
    private static func redated(_ rain: DayRain, _ date: LocalDate) -> DayRain {
        DayRain(date: date, code: rain.code, chance: rain.chance, totalMm: rain.totalMm, rainMm: rain.rainMm,
                snowCm: rain.snowCm, wetHours: rain.wetHours, call: rain.call, mix: rain.mix, complete: rain.complete,
                parts: rain.parts, hours: rain.hours, periods: rain.periods, counted: rain.counted, timing: rain.timing,
                carryOn: rain.carryOn)
    }
}
