import Foundation

/// A saved clock: a place and its time zone ([zoneId] is IANA, "Europe/Bucharest"). Ported from Android's Clocks.kt.
struct Clock: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    var detail: String? = nil
    let zoneId: String

    /// Nil if the zone id isn't one this phone knows (never for zones from the geocoder).
    var zone: TimeZone? { TimeZone(identifier: zoneId) }

    /// A place from search as a clock; nil when it has no time zone, or one this phone doesn't know.
    static func of(_ place: Place) -> Clock? {
        guard let zoneId = place.zoneId, TimeZone(identifier: zoneId) != nil else { return nil }
        return Clock(id: place.id, name: place.name, detail: place.detail, zoneId: zoneId)
    }
}

/// One clock at one moment, as the row shows it: the time there, which day that is for you ("Tomorrow"), how far
/// ahead or behind ("+10 h", "same time as you"), the UTC offset ("UTC+3") and whether it's night there.
struct ClockReading: Sendable {
    /// The wall-clock time there.
    let time: LocalDateTime
    /// Its offset from UTC, seconds.
    let utcSeconds: Int
    let day: String
    let offset: String
    let utc: String
    let night: Bool
    /// The offset for screen readers: "10 hours ahead".
    let spoken: String
}

func readClock(_ now: Date, here: TimeZone, there: TimeZone) -> ClockReading {
    let theirOffset = there.secondsFromGMT(for: now)
    let myOffset = here.secondsFromGMT(for: now)
    let local = LocalDateTime.from(now, utcOffsetSeconds: theirOffset)
    let mine = LocalDateTime.from(now, utcOffsetSeconds: myOffset)
    let diff = theirOffset - myOffset
    return ClockReading(
        time: local,
        utcSeconds: theirOffset,
        day: relativeDay(mine.date, local.date),
        offset: diff == 0 ? "same time as you" : formatOffset(diff),
        utc: formatUtc(theirOffset),
        night: isNightHour(local.hour),
        spoken: spokenOffset(diff)
    )
}

/// [hour]:[minute] on [day] where [from] is, as the wall-clock time it is in [to]. A time skipped by daylight saving
/// moves forward.
func convertTime(hour: Int, minute: Int, on day: LocalDate, from: TimeZone, to: TimeZone) -> LocalDateTime {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = from
    let parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)
    // Calendar moves a time in a spring-forward gap on by the gap, and takes the earlier offset in a fall-back
    // overlap, as java.time does. It only fails for an impossible date, which a LocalDate can't be.
    guard let instant = calendar.date(from: parts) else { preconditionFailure("No instant for \(day) \(hour):\(minute)") }
    return LocalDateTime.from(instant, utcOffsetSeconds: to.secondsFromGMT(for: instant))
}

/// "Today", "Tomorrow", "Yesterday", from [mine]'s point of view.
func relativeDay(_ mine: LocalDate, _ theirs: LocalDate) -> String {
    switch theirs.epochDay - mine.epochDay {
    case 0: "Today"
    case 1: "Tomorrow"
    case -1: "Yesterday"
    default: weekdayName(theirs)
    }
}

/// "+10 h", "−3 h", "+5½ h", "+5¾ h": whole hours with the common quarter and half hours as fractions; under an
/// hour, minutes ("+15 min", "−30 min").
func formatOffset(_ seconds: Int) -> String {
    let sign = seconds < 0 ? "−" : "+"
    let minutes = abs(seconds) / 60
    let hours = minutes / 60
    if hours == 0 { return "\(sign)\(minutes) min" }
    let fraction: String
    switch minutes % 60 {
    case 0: fraction = ""
    case 15: fraction = "¼"
    case 30: fraction = "½"
    case 45: fraction = "¾"
    default: fraction = ":" + twoDigits(minutes % 60)
    }
    return "\(sign)\(hours)\(fraction) h"
}

/// "UTC", "UTC+3", "UTC−7", "UTC+5:30".
func formatUtc(_ seconds: Int) -> String {
    if seconds == 0 { return "UTC" }
    let sign = seconds < 0 ? "−" : "+"
    let minutes = abs(seconds) / 60
    return "UTC\(sign)\(minutes / 60)" + (minutes % 60 != 0 ? ":" + twoDigits(minutes % 60) : "")
}

/// "UTC minus 7", "UTC plus 5:30", for screen readers (the minus sign isn't read).
func spokenUtc(_ seconds: Int) -> String {
    formatUtc(seconds).replacingOccurrences(of: "+", with: " plus ").replacingOccurrences(of: "−", with: " minus ")
}

/// "10 hours ahead", "1 hour behind", "5 and a half hours ahead", "15 minutes behind", for screen readers.
func spokenOffset(_ seconds: Int) -> String {
    if seconds == 0 { return "same time as you" }
    let way = seconds > 0 ? "ahead" : "behind"
    let minutes = abs(seconds) / 60
    let hours = minutes / 60
    let rest = minutes % 60
    if hours == 0 { return "\(minutes) minutes \(way)" }
    let fraction: String
    switch rest {
    case 0: fraction = ""
    case 15: fraction = " and a quarter"
    case 30: fraction = " and a half"
    case 45: fraction = " and three quarters"
    default: fraction = " and \(rest) minutes"
    }
    return "\(hours)\(fraction) \(hours == 1 && rest == 0 ? "hour" : "hours") \(way)"
}

/// How [theirs] relates to [from] for a converted time: nil the same day, "next day", "day before", or the weekday.
func dayNote(_ from: LocalDate, _ theirs: LocalDate) -> String? {
    switch theirs.epochDay - from.epochDay {
    case 0: nil
    case 1: "next day"
    case -1: "day before"
    default: weekdayName(theirs)
    }
}

/// Without a forecast's sunrise and sunset, night is 6 PM to 6 AM.
func isNightHour(_ hour: Int) -> Bool { hour < 6 || hour >= 18 }

/// The city part of a zone id: "America/Los_Angeles" → "Los Angeles", "America/Argentina/Buenos_Aires" →
/// "Buenos Aires".
func cityOf(_ zone: TimeZone) -> String {
    String(zone.identifier.split(separator: "/").last ?? Substring(zone.identifier)).replacingOccurrences(of: "_", with: " ")
}

private func twoDigits(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

/// The converter's answer (Android's Converter): the picked moment where it's picked, and the same moment in every
/// other clock, and in your phone when the time is a clock's.
struct Conversion: Sendable {
    /// The picked moment, wall-clock where it's picked.
    let moment: LocalDateTime
    /// Where the time is: the clock's zone, or the phone's.
    let fromZone: TimeZone
    /// "12:00 PM".
    let timeLabel: String
    /// "Today" or "Tomorrow".
    let dayLabel: String
    /// "New York" or the clock's name.
    let fromName: String
    /// "At 12:00 PM on Wednesday in New York it's…".
    let heading: String
    let rows: [ConvertedRow]
}

/// One clock at the converted moment: its name, the time there, and "Thu · next day" when it's another day there.
struct ConvertedRow: Sendable, Identifiable {
    let id: String
    let name: String
    let time: LocalDateTime
    let timeLabel: String
    let note: String?
    let night: Bool
    /// "Tokyo, 1:00 AM, Thu, next day".
    var spoken: String { [name, timeLabel, note?.replacingOccurrences(of: " ·", with: ",")].compactMap { $0 }.joined(separator: ", ") }
}

/// The converter at [now]: [minutes] past midnight (nil for the time now there), [dayOffset] days after today there
/// (0 or 1), where the time is [fromId]'s clock (nil, or a clock that's gone or whose zone is unknown, for the phone).
func convert(clocks: [Clock], now: Date, here: TimeZone, fromId: String?, minutes: Int?, dayOffset: Int,
             use24Hour: Bool = ClockFormat.use24Hour) -> Conversion {
    let from = clocks.first { $0.id == fromId && $0.zone != nil }
    let fromZone = from?.zone ?? here
    let phoneName = "\(cityOf(here)) (your phone)"
    let fromName = from?.name ?? cityOf(here)
    let nowThere = LocalDateTime.from(now, utcOffsetSeconds: fromZone.secondsFromGMT(for: now))
    let hour = minutes.map { $0 / 60 } ?? nowThere.hour
    let minute = minutes.map { $0 % 60 } ?? nowThere.minute
    let day = nowThere.date.plusDays(dayOffset)
    // Through the zone, so a time skipped by daylight saving moves forward.
    let moment = convertTime(hour: hour, minute: minute, on: day, from: fromZone, to: fromZone)
    let timeLabel = formatClock(moment, use24Hour: use24Hour)
    func row(_ id: String, _ name: String, _ zone: TimeZone) -> ConvertedRow {
        let there = convertTime(hour: hour, minute: minute, on: day, from: fromZone, to: zone)
        let note = dayNote(moment.date, there.date).map { n in
            n.hasSuffix("day") && n.contains(" ") ? "\(weekdayName(there.date).prefix(3)) · \(n)" : n
        }
        return ConvertedRow(id: id, name: name, time: there, timeLabel: formatClock(there, use24Hour: use24Hour),
                            note: note, night: isNightHour(there.hour))
    }
    var rows: [ConvertedRow] = []
    if from != nil { rows.append(row("phone", phoneName, here)) }
    for clock in clocks where clock.id != from?.id {
        if let zone = clock.zone { rows.append(row(clock.id, clock.name, zone)) }
    }
    return Conversion(
        moment: moment,
        fromZone: fromZone,
        timeLabel: timeLabel,
        dayLabel: dayOffset == 0 ? "Today" : "Tomorrow",
        fromName: fromName,
        heading: "At \(timeLabel) on \(weekdayName(moment.date)) in \(fromName) it's…",
        rows: rows
    )
}
