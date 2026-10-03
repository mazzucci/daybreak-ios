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
    // Calendar moves a time in a spring-forward gap on by the gap, as java.time does.
    let instant = calendar.date(from: parts) ?? Date()
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
