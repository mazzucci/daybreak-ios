import Foundation
import Testing
@testable import Daybreak

/// The day page's own rules: which hours it lists, when the feels-like range earns a pill, and the no-break spaces
/// that keep numbers on the same line as their units.
struct DayPageTests {
    private let date = LocalDate(2026, 9, 28)

    /// [date] and the day after, hour by hour (the temperature is the hour, feels-like two below), with the current
    /// conditions at [nowHour]:30.
    private func forecast(nowHour: Int = 14) -> Forecast {
        let hours = (0..<48).map { i in
            HourForecast(time: date.atStartOfDay.plusHours(i), tempC: Double(i % 24), precipChance: 0, code: 3,
                         feelsLikeC: Double(i % 24) - 2)
        }
        let days = [date, date.plusDays(1)].map { d in
            DaySummary(date: d, highC: 23, lowC: 0, precipChance: 0, code: 3,
                       sunrise: d.atTime(7), sunset: d.atTime(19))
        }
        let current = CurrentConditions(time: date.atTime(nowHour, 30), tempC: 30, feelsLikeC: 28, humidity: 50,
                                        windKmh: 10, code: 0)
        return Forecast(current: current, days: days, hours: hours)
    }

    @Test("today's hours start at the current hour, as Now with the current conditions")
    func todayStartsNow() {
        let cells = HourCell.day(forecast(nowHour: 14), date)
        #expect(cells.count == 10)
        #expect(cells.first?.label == "Now")
        #expect(cells.first?.tempC == 30)
        #expect(cells.first?.code == 0)
        #expect(cells.first?.feelsLikeC == 28)
        #expect(cells.dropFirst().first?.label == formatHour(date.atTime(15)))
        #expect(cells.dropFirst().first?.tempC == 15)
        #expect(cells.allSatisfy { $0.rain == nil })
    }

    @Test("another day lists all 24 hours from midnight, with no Now")
    func otherDayFromMidnight() {
        let cells = HourCell.day(forecast(), date.plusDays(1))
        #expect(cells.count == 24)
        #expect(cells.first?.label == formatHour(date.plusDays(1).atStartOfDay))
        #expect(!cells.contains { $0.label == "Now" })
        #expect(cells.last?.tempC == 23)
    }

    @Test("the Weather tab's next hours still open with Now and carry their rain")
    func nextHoursUnchanged() {
        let f = forecast()
        let cells = HourCell.next(f, nightNow: false)
        #expect(cells.count == f.nextHours.count)
        #expect(cells.first?.label == "Now")
        #expect(cells.first?.tempC == 30)
    }

    @Test("the feels-like pill shows once either end is 3° or more off, in the unit shown")
    func feelsLikePill() {
        let day = DaySummary(date: date, highC: 20, lowC: 10, precipChance: 0, code: 3)
        #expect(!feelsWorthAPill(20, 10, day, .c))
        // 18.4°C is 2° under in Celsius but 3° under in Fahrenheit (65° against 68°).
        #expect(!feelsWorthAPill(18.4, 10, day, .c))
        #expect(feelsWorthAPill(18.4, 10, day, .f))
        #expect(feelsWorthAPill(20, 7, day, .c))
        #expect(feelsWorthAPill(20, 13, day, .c))
    }

    @Test("numbers keep their units on the same line")
    func unitsTogether() {
        let nbsp = "\u{00A0}"
        #expect(keepUnitsTogether("about 12 mm over 5 hours") == "about 12\(nbsp)mm over 5\(nbsp)hours")
        #expect(keepUnitsTogether("90% · 0.65 in · 7 h") == "90% · 0.65\(nbsp)in · 7\(nbsp)h")
        #expect(keepUnitsTogether("7 AM–7 PM") == "7\(nbsp)AM–7\(nbsp)PM")
        #expect(keepUnitsTogether("Up to 20 mph") == "Up to 20\(nbsp)mph")
        // Only a unit right after a number, as a whole word.
        #expect(keepUnitsTogether("in the morning, 3 inches") == "in the morning, 3\(nbsp)inches")
        #expect(keepUnitsTogether("2 hourly") == "2 hourly")
    }
}
