import Foundation

/// A calendar date with no time zone, like `java.time.LocalDate`. Stored as days since 1970-01-01 (the same
/// "epoch day" Java uses, which seeds On this day's daily shuffle, so both apps pick alike).
struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    let epochDay: Int

    init(epochDay: Int) { self.epochDay = epochDay }

    init(_ year: Int, _ month: Int, _ day: Int) {
        epochDay = Self.daysFromCivil(year, month, day)
    }

    var year: Int { Self.civil(epochDay).year }
    var month: Int { Self.civil(epochDay).month }
    var day: Int { Self.civil(epochDay).day }

    /// ISO day of the week: 1 is Monday, 7 is Sunday.
    var weekday: Int { ((epochDay + 3) % 7 + 7) % 7 + 1 }

    func plusDays(_ n: Int) -> LocalDate { LocalDate(epochDay: epochDay + n) }
    func plusYears(_ n: Int) -> LocalDate {
        let c = Self.civil(epochDay)
        let y = c.year + n
        // Feb 29 in a year without one becomes Feb 28, as in Java.
        let lastDay = Self.daysInMonth(y, c.month)
        return LocalDate(y, c.month, min(c.day, lastDay))
    }

    func atTime(_ hour: Int, _ minute: Int = 0) -> LocalDateTime {
        LocalDateTime(seconds: epochDay * 86_400 + hour * 3_600 + minute * 60)
    }

    var atStartOfDay: LocalDateTime { atTime(0) }

    /// "2026-10-01".
    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    static func < (a: LocalDate, b: LocalDate) -> Bool { a.epochDay < b.epochDay }

    /// Parses "2026-10-01"; nil for anything else.
    static func parse(_ s: String) -> LocalDate? {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...daysInMonth(y, m)).contains(d) else { return nil }
        return LocalDate(y, m, d)
    }

    /// Today in [timeZone] (the phone's own by default).
    static func today(_ now: Date = Date(), in timeZone: TimeZone = .current) -> LocalDate {
        LocalDateTime.from(now, in: timeZone).date
    }

    // Howard Hinnant's civil-calendar algorithms (proleptic Gregorian, as java.time).
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civil(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }

    static func daysInMonth(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

/// A wall-clock date and time with no time zone, like `java.time.LocalDateTime`: what Open-Meteo sends with
/// `timezone=auto` ("2026-09-28T14:30", the place's own local time). Minute precision is all the app needs.
struct LocalDateTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Seconds since 1970-01-01T00:00 on the same wall clock.
    let seconds: Int

    init(seconds: Int) { self.seconds = seconds }

    init(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) {
        self = LocalDate(year, month, day).atTime(hour, minute)
    }

    var date: LocalDate { LocalDate(epochDay: Int((Double(seconds) / 86_400).rounded(.down))) }
    var hour: Int { secondOfDay / 3_600 }
    var minute: Int { secondOfDay % 3_600 / 60 }
    private var secondOfDay: Int { ((seconds % 86_400) + 86_400) % 86_400 }

    func plusHours(_ n: Int) -> LocalDateTime { LocalDateTime(seconds: seconds + n * 3_600) }
    func minusHours(_ n: Int) -> LocalDateTime { plusHours(-n) }
    func plusMinutes(_ n: Int) -> LocalDateTime { LocalDateTime(seconds: seconds + n * 60) }

    /// The start of this hour.
    var truncatedToHour: LocalDateTime { LocalDateTime(seconds: seconds - secondOfDay % 3_600) }

    static func < (a: LocalDateTime, b: LocalDateTime) -> Bool { a.seconds < b.seconds }

    var description: String { "\(date)T" + String(format: "%02d:%02d", hour, minute) }

    /// Parses "2026-09-28T14:30" (seconds, if any, are ignored); nil for anything else.
    static func parse(_ s: String) -> LocalDateTime? {
        let halves = s.split(separator: "T", omittingEmptySubsequences: false)
        guard halves.count == 2, let date = LocalDate.parse(String(halves[0])) else { return nil }
        let time = halves[1].split(separator: ":", omittingEmptySubsequences: false)
        guard time.count >= 2, let h = Int(time[0]), let m = Int(time[1]), (0..<24).contains(h), (0..<60).contains(m)
        else { return nil }
        return date.atTime(h, m)
    }

    /// The wall-clock time of [instant] in [timeZone].
    static func from(_ instant: Date, in timeZone: TimeZone = .current) -> LocalDateTime {
        let offset = timeZone.secondsFromGMT(for: instant)
        return LocalDateTime(seconds: Int((instant.timeIntervalSince1970 + Double(offset)).rounded(.down)))
    }

    /// The wall-clock time [offsetSeconds] from UTC at [instant] (a forecast's own offset).
    static func from(_ instant: Date, utcOffsetSeconds offsetSeconds: Int) -> LocalDateTime {
        LocalDateTime(seconds: Int((instant.timeIntervalSince1970 + Double(offsetSeconds)).rounded(.down)))
    }
}
