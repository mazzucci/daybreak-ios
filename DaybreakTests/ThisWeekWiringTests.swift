import Foundation
import Testing
@testable import Daybreak

/// What the This week card and Home's today line rely on: the outlook given the rains the page has already worked
/// out reads the same as one working them out itself, and its best day is one of the strip's days.
struct ThisWeekWiringTests {
    @Test("the outlook reads the same with the page's rains as without them")
    func rainsShared() {
        for forecast in [TestData.alps(), TestData.forecast()] {
            let rains = forecast.upcomingDays().map { Precip.dayRain(forecast, $0.date) }
            for unit in [TempUnit.f, .c] {
                let own = weekOutlook(forecast, unit)
                let shared = weekOutlook(forecast, unit, rains: rains)
                #expect(own.today == shared.today)
                #expect(own.week == shared.week)
                #expect(own.spoken == shared.spoken)
                #expect(own.bestDate == shared.bestDate)
            }
        }
    }

    @Test("the best day, when there is one, is one of the strip's days and only one")
    func bestIsInTheStrip() {
        for forecast in [TestData.alps(), TestData.forecast()] {
            let outlook = weekOutlook(forecast, .f)
            #expect(outlook.days.filter(\.isBest).count <= 1)
            if let best = outlook.bestDate {
                #expect(outlook.days.contains { $0.date == best })
                #expect(forecast.upcomingDays().contains { $0.date == best })
            }
        }
    }

    @Test("the outlook's moment is the forecast's own time until the clock passes it, then the clock's hour")
    func moment() {
        let forecast = TestData.forecast()
        // A clock behind the forecast (1970): the forecast's own time.
        #expect(outlookMoment(forecast, Date(timeIntervalSince1970: 0)) == forecast.current.time)
        // A clock a day and a half ahead: that moment at the place, to the hour.
        let later = Date(timeIntervalSince1970: 0).addingTimeInterval(
            TimeInterval(forecast.current.time.seconds - forecast.utcOffsetSeconds + 36 * 3_600 + 25 * 60))
        let moment = outlookMoment(forecast, later)
        #expect(moment == forecast.current.time.plusHours(36).truncatedToHour)
        #expect(moment.minute == 0)
    }
}
