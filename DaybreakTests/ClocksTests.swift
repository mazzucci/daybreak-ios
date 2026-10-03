import Foundation
import Testing
@testable import Daybreak

/// Ported from Android's ClocksTest (readings, offsets, converting across daylight saving, city names, which places
/// can be clocks) and the clocks part of RepositoriesTest (the saved list).
@MainActor
struct ClocksTests {
    private let la = TimeZone(identifier: "America/Los_Angeles")!
    private let bucharest = TimeZone(identifier: "Europe/Bucharest")!
    private let moment = try! Date("2026-09-28T21:42:00Z", strategy: .iso8601)

    @Test("a clock reads its time, day and offset against yours")
    func reading() {
        // 2:42 PM in Los Angeles is 12:42 AM tomorrow in Bucharest, ten hours ahead (both on summer time).
        let r = readClock(moment, here: la, there: bucharest)
        #expect(r.time.hour == 0 && r.time.minute == 42)
        #expect(r.day == "Tomorrow")
        #expect(r.offset == "+10 h")
        #expect(r.utc == "UTC+3")
        #expect(r.night)
        let back = readClock(moment, here: bucharest, there: la)
        #expect(back.day == "Yesterday")
        #expect(back.offset == "−10 h")
        #expect(readClock(moment, here: la, there: la).offset == "same time as you")
    }

    @Test("offsets show halves and quarters, and UTC shows minutes")
    func offsets() {
        #expect(formatOffset(5 * 3600 + 1800) == "+5½ h")
        #expect(formatOffset(5 * 3600 + 2700) == "+5¾ h")
        #expect(formatOffset(-(3 * 3600 + 1800)) == "−3½ h")
        #expect(formatUtc(5 * 3600 + 1800) == "UTC+5:30")
        #expect(formatUtc(-7 * 3600) == "UTC−7")
        #expect(formatUtc(0) == "UTC")
    }

    @Test("converting follows each place's daylight saving on that date")
    func convertingAcrossDaylightSaving() {
        // 28 October 2026: Europe is back on winter time (25 Oct) but the US isn't until 1 November, so the gap is
        // nine hours for that week.
        let oct = convertTime(hour: 12, minute: 0, on: LocalDate(2026, 10, 28), from: la, to: bucharest)
        #expect(oct.hour == 21 && oct.minute == 0)
        // In summer the gap is ten hours.
        #expect(convertTime(hour: 12, minute: 0, on: LocalDate(2026, 7, 1), from: la, to: bucharest).hour == 22)
        // A mid-January morning in Bucharest is the evening before in Los Angeles.
        let jan = convertTime(hour: 8, minute: 0, on: LocalDate(2027, 1, 15), from: bucharest, to: la)
        #expect(jan.date == LocalDate(2027, 1, 14))
        #expect(jan.hour == 22 && jan.minute == 0)
    }

    @Test("a time skipped by daylight saving moves forward, and a repeated one is the first")
    func gapAndOverlap() {
        let utc = TimeZone(identifier: "UTC")!
        // 2:30 AM on 8 March 2026 doesn't exist in Los Angeles: it's 3:30 AM PDT, 10:30 UTC.
        let gap = convertTime(hour: 2, minute: 30, on: LocalDate(2026, 3, 8), from: la, to: utc)
        #expect(gap.hour == 10 && gap.minute == 30)
        // 1:30 AM on 1 November 2026 happens twice: the first, still on PDT, is 8:30 UTC.
        let overlap = convertTime(hour: 1, minute: 30, on: LocalDate(2026, 11, 1), from: la, to: utc)
        #expect(overlap.hour == 8 && overlap.minute == 30)
    }

    @Test("city names come from the zone id")
    func cityNames() {
        #expect(cityOf(la) == "Los Angeles")
        #expect(cityOf(TimeZone(identifier: "America/Argentina/Buenos_Aires")!) == "Buenos Aires")
    }

    @Test("a place without a time zone can't be a clock")
    func placeWithoutZone() {
        let place = Place(id: "geo:1", name: "Nowhere", latitude: 0, longitude: 0)
        #expect(Clock.of(place) == nil)
        var zoned = place
        zoned.zoneId = "Europe/Bucharest"
        #expect(Clock.of(zoned)?.zoneId == "Europe/Bucharest")
        #expect(!isNightHour(6))
        #expect(isNightHour(18))
    }

    @Test("offsets under an hour are minutes, and screen readers hear words")
    func minutesAndWords() {
        #expect(formatOffset(900) == "+15 min")
        #expect(formatOffset(-1800) == "−30 min")
        #expect(formatUtc(-(3 * 3600 + 1800)) == "UTC−3:30")
        #expect(spokenOffset(3600) == "1 hour ahead")
        #expect(spokenOffset(-36000) == "10 hours behind")
        #expect(spokenOffset(5 * 3600 + 1800) == "5 and a half hours ahead")
        #expect(spokenOffset(900) == "15 minutes ahead")
        #expect(spokenUtc(-7 * 3600) == "UTC minus 7")
        #expect(spokenUtc(5 * 3600 + 1800) == "UTC plus 5:30")
    }

    @Test("converted days say next day, day before, or the weekday when two apart")
    func dayNotes() {
        let mon = LocalDate(2026, 9, 28)
        #expect(dayNote(mon, mon) == nil)
        #expect(dayNote(mon, mon.plusDays(1)) == "next day")
        #expect(dayNote(mon, mon.plusDays(-1)) == "day before")
        #expect(dayNote(mon, mon.plusDays(-2)) == "Saturday")
    }

    @Test("a zone this phone doesn't know can't be a clock")
    func unknownZone() {
        let atlantis = Place(id: "geo:1", name: "Atlantis", latitude: 0, longitude: 0, zoneId: "Atlantis/Lost_City")
        #expect(Clock.of(atlantis) == nil)
        #expect(Clock(id: "x", name: "Atlantis", zoneId: "Atlantis/Lost_City").zone == nil)
    }

    // MARK: The converter

    private let clocks = [
        Clock(id: "geo:683506", name: "Bucharest", zoneId: "Europe/Bucharest"),
        Clock(id: "geo:1850147", name: "Tokyo", zoneId: "Asia/Tokyo"),
        Clock(id: "x", name: "Atlantis", zoneId: "Atlantis/Lost_City"),
    ]

    @Test("by default it's now, today, on your phone, shown in every clock whose zone is known")
    func convertNow() {
        // 2:42 PM on Monday 28 September in Los Angeles.
        let c = convert(clocks: clocks, now: moment, here: la, fromId: nil, minutes: nil, dayOffset: 0, use24Hour: false)
        #expect(c.timeLabel == "2:42 PM")
        #expect(c.dayLabel == "Today")
        #expect(c.fromName == "Los Angeles")
        #expect(c.heading == "At 2:42 PM on Monday in Los Angeles it's…")
        #expect(c.rows.map(\.name) == ["Bucharest", "Tokyo"])
        #expect(c.rows.map(\.timeLabel) == ["12:42 AM", "6:42 AM"])
        #expect(c.rows.map(\.note) == ["Tue · next day", "Tue · next day"])
        #expect(c.rows[0].night && !c.rows[1].night)
        #expect(c.rows[0].spoken == "Bucharest, 12:42 AM, Tue, next day")
    }

    @Test("a time picked in a clock shows your phone too, and leaves that clock out")
    func convertFromAClock() {
        // Noon tomorrow in Tokyo: it's already 6:42 AM on Tuesday 29 September there, so tomorrow is Wednesday
        // (today and tomorrow are the clock's, not the phone's).
        let c = convert(clocks: clocks, now: moment, here: la, fromId: "geo:1850147", minutes: 12 * 60, dayOffset: 1,
                        use24Hour: false)
        #expect(c.heading == "At 12:00 PM on Wednesday in Tokyo it's…")
        #expect(c.dayLabel == "Tomorrow")
        #expect(c.rows.map(\.name) == ["Los Angeles (your phone)", "Bucharest"])
        #expect(c.rows.map(\.timeLabel) == ["8:00 PM", "6:00 AM"])
        #expect(c.rows.map(\.note) == ["day before", nil])
    }

    @Test("a removed clock, or one with an unknown zone, falls back to your phone")
    func convertFromGone() {
        for id in ["gone", "x"] {
            let c = convert(clocks: clocks, now: moment, here: la, fromId: id, minutes: 9 * 60, dayOffset: 0,
                            use24Hour: false)
            #expect(c.fromName == "Los Angeles")
            #expect(!c.rows.contains { $0.name.hasSuffix("(your phone)") })
        }
    }

    @Test("a time skipped by daylight saving moves forward, in the heading and every row")
    func convertInAGap() {
        // 2:30 AM on 8 March 2026 doesn't exist in Los Angeles; the phone's day is the 8th, after the change.
        let gapDay = try! Date("2026-03-08T12:00:00Z", strategy: .iso8601)
        let c = convert(clocks: clocks, now: gapDay, here: la, fromId: nil, minutes: 150, dayOffset: 0, use24Hour: false)
        #expect(c.timeLabel == "3:30 AM")
        #expect(c.moment.hour == 3 && c.moment.minute == 30)
        #expect(c.heading == "At 3:30 AM on Sunday in Los Angeles it's…")
        // 3:30 AM PDT is 10:30 UTC: 12:30 PM in Bucharest (UTC+2 in March), 7:30 PM in Tokyo.
        #expect(c.rows.map(\.timeLabel) == ["12:30 PM", "7:30 PM"])
        let h24 = convert(clocks: clocks, now: gapDay, here: la, fromId: nil, minutes: 150, dayOffset: 0, use24Hour: true)
        #expect(h24.timeLabel == "03:30")
        #expect(h24.rows.map(\.timeLabel) == ["12:30", "19:30"])
        #expect(h24.heading == "At 03:30 on Sunday in Los Angeles it's…")
    }

    @Test("two days apart reads the weekday")
    func convertTwoDaysApart() {
        // Kiritimati (UTC+14) and Pago Pago (UTC−11) are 25 hours apart: 12:30 AM on Tuesday in Kiritimati is
        // 11:30 PM on Sunday in Pago Pago; 11 PM on Tuesday there is 10 PM on Monday, the day before.
        let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!
        let pagoPago = Clock(id: "pp", name: "Pago Pago", zoneId: "Pacific/Pago_Pago")
        let early = convert(clocks: [pagoPago], now: moment, here: kiritimati, fromId: nil, minutes: 30, dayOffset: 0,
                            use24Hour: false)
        #expect(early.heading == "At 12:30 AM on Tuesday in Kiritimati it's…")
        #expect(early.rows.first?.timeLabel == "11:30 PM")
        #expect(early.rows.first?.note == "Sunday")
        let late = convert(clocks: [pagoPago], now: moment, here: kiritimati, fromId: nil, minutes: 23 * 60,
                           dayOffset: 0, use24Hour: false)
        #expect(late.rows.first?.timeLabel == "10:00 PM")
        #expect(late.rows.first?.note == "day before")
    }

    // MARK: The saved list

    private func freshStore() -> ClocksStore {
        let name = "ClocksTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return ClocksStore(defaults: defaults)
    }

    private let bucharestPlace = Place(id: "geo:683506", name: "Bucharest", region: "Bucharest", country: "Romania",
                                       latitude: 44.43, longitude: 26.1, zoneId: "Europe/Bucharest")
    private let tokyoPlace = Place(id: "geo:1850147", name: "Tokyo", latitude: 35.69, longitude: 139.69,
                                   zoneId: "Asia/Tokyo")

    @Test("clocks are added once, kept in order, moved and removed")
    func savedList() {
        let store = freshStore()
        let model = ClocksModel(store: store)
        #expect(model.add(bucharestPlace))
        #expect(model.add(tokyoPlace))
        #expect(!model.add(tokyoPlace))
        #expect(!model.add(Place(id: "geo:1", name: "Nowhere", latitude: 0, longitude: 0)))
        #expect(ClocksModel(store: store).clocks.map(\.name) == ["Bucharest", "Tokyo"])
        #expect(ClocksModel(store: store).clocks.first?.detail == "Bucharest, Romania")
        model.move(from: 1, to: 0)
        #expect(ClocksModel(store: store).clocks.map(\.name) == ["Tokyo", "Bucharest"])
        model.move(from: 0, to: 5)
        #expect(model.clocks.map(\.name) == ["Tokyo", "Bucharest"])
        model.remove("geo:1850147")
        #expect(ClocksModel(store: store).clocks.map(\.name) == ["Bucharest"])
        model.remove("geo:683506")
        #expect(ClocksModel(store: store).clocks.isEmpty)
    }

    @Test("a stored entry that doesn't read is dropped, not the rest")
    func lenientLoad() {
        let name = "ClocksTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let json = #"[{"id":"geo:1850147","name":"Tokyo","zoneId":"Asia/Tokyo"},{"oops":1}]"#
        defaults.set(Data(json.utf8), forKey: "clocks")
        #expect(ClocksStore(defaults: defaults).load().map(\.name) == ["Tokyo"])
        defaults.set(Data("not json".utf8), forKey: "clocks")
        #expect(ClocksStore(defaults: defaults).load().isEmpty)
        defaults.removePersistentDomain(forName: name)
    }
}
