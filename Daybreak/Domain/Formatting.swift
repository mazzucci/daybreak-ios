import Foundation

// Formatting shared by every screen, ported from Android's domain/Formatting.kt. The copy is English and numbers are
// written the US way, as on Android.

func cToF(_ c: Double) -> Double { c * 9.0 / 5.0 + 32.0 }

func kmhToMph(_ kmh: Double) -> Double { kmh * 0.621371 }

/// Kotlin's `roundToInt`: halves round up (towards positive infinity), so −2.5 is −2.
func roundToInt(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

/// Rounded whole degrees in [unit].
func degrees(_ c: Double, _ unit: TempUnit) -> Int {
    switch unit {
    case .c: roundToInt(c)
    case .f: roundToInt(cToF(c))
    }
}

/// "72°F" / "22°C" / "−6°C" (a true minus sign, U+2212, as typeset temperatures use).
func formatTemp(_ c: Double, _ unit: TempUnit) -> String { "\(signed(degrees(c, unit)))°\(unit.rawValue)" }

/// "72°", "−6°": for places where the unit is already clear from context.
func formatDegrees(_ c: Double, _ unit: TempUnit) -> String { "\(signed(degrees(c, unit)))°" }

private func signed(_ n: Int) -> String { n < 0 ? "\u{2212}\(-n)" : "\(n)" }

/// "74°F (23°C)": both units, primary first, for VoiceOver.
func formatBothUnits(_ c: Double, _ unit: TempUnit) -> String { "\(formatTemp(c, unit)) (\(formatTemp(c, unit.other)))" }

/// "9 mph" or "14 km/h", following the primary temperature unit.
func formatWind(_ kmh: Double, _ unit: TempUnit) -> String {
    switch unit {
    case .f: "\(roundToInt(kmhToMph(kmh))) mph"
    case .c: "\(roundToInt(kmh)) km/h"
    }
}

/// Whether times are written on the 24-hour clock ("18:00") or the 12-hour one ("6 PM"). Follows the phone's own
/// setting (read at launch and on return to the foreground); false (12-hour) in tests.
enum ClockFormat {
    nonisolated(unsafe) static var use24Hour = false

    /// The phone's preference, from the locale's own short time format.
    static var systemUses24Hour: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "h a"
        return !format.contains("a")
    }
}

let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
                  "November", "December"]
let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

/// "3 PM" style hour label ("15:00" on the 24-hour clock).
func formatHour(_ time: LocalDateTime, use24Hour: Bool = ClockFormat.use24Hour) -> String {
    if use24Hour { return String(format: "%02d:%02d", time.hour, time.minute) }
    let h = time.hour % 12 == 0 ? 12 : time.hour % 12
    return "\(h) \(time.hour < 12 ? "AM" : "PM")"
}

/// "7:02 AM" style clock time, for sunrise and sunset.
func formatClock(_ time: LocalDateTime, use24Hour: Bool = ClockFormat.use24Hour) -> String {
    if use24Hour { return String(format: "%02d:%02d", time.hour, time.minute) }
    let h = time.hour % 12 == 0 ? 12 : time.hour % 12
    return String(format: "%d:%02d %@", h, time.minute, time.hour < 12 ? "AM" : "PM")
}

/// "Tuesday".
func weekdayName(_ date: LocalDate) -> String { weekdayNames[date.weekday - 1] }

/// "Today", then short weekday names ("Tue") for the multi-day list.
func formatDayLabel(_ date: LocalDate, today: LocalDate) -> String {
    date == today ? "Today" : String(weekdayName(date).prefix(3))
}

/// Full weekday name for VoiceOver ("Tuesday").
func formatDayName(_ date: LocalDate, today: LocalDate) -> String { date == today ? "Today" : weekdayName(date) }

/// "Oct 8", under the weekday of the days beyond a week.
func formatShortDate(_ date: LocalDate) -> String { "\(monthNames[date.month - 1].prefix(3)) \(date.day)" }

/// "October 8", for VoiceOver.
func formatLongDate(_ date: LocalDate) -> String { "\(monthNames[date.month - 1]) \(date.day)" }

/// WHO UV index category for a (rounded) UV index.
func describeUv(_ uv: Double) -> String {
    switch roundToInt(uv) {
    case ...2: "Low"
    case 3...5: "Moderate"
    case 6...7: "High"
    case 8...10: "Very high"
    default: "Extreme"
    }
}

/// WMO weather interpretation codes, as used by Open-Meteo.
func describeWeatherCode(_ code: Int) -> String {
    switch code {
    case 0: "Clear sky"
    case 1: "Mainly clear"
    case 2: "Partly cloudy"
    case 3: "Overcast"
    case 45, 48: "Fog"
    case 51, 53, 55: "Drizzle"
    case 56, 57: "Freezing drizzle"
    case 61, 63, 65: "Rain"
    case 66, 67: "Freezing rain"
    case 71, 73, 75, 77: "Snow"
    case 80, 81, 82: "Rain showers"
    case 85, 86: "Snow showers"
    case 95: "Thunderstorm"
    case 96, 99: "Thunderstorm with hail"
    default: "Unknown"
    }
}

/// Feels-like is worth a line of its own once it's this many degrees (in the unit shown) from the actual temperature.
let feelsLikeGap = 3

/// The feels-like temperature when it differs enough from [tempC] to mention, else nil.
func feelsLikeWorthShowing(_ tempC: Double, _ feelsLikeC: Double?, _ unit: TempUnit) -> Double? {
    guard let feelsLikeC, abs(degrees(feelsLikeC, unit) - degrees(tempC, unit)) >= feelsLikeGap else { return nil }
    return feelsLikeC
}

/// Joins each number to its unit with a no-break space, so "12 mm" or "7 PM" never splits across lines.
func keepUnitsTogether(_ text: String) -> String {
    text.replacing(/(\d) (mm|cm|in|inch|inches|km\/h|mph|h|hour|hours|AM|PM)\b/) { "\($0.1)\u{00A0}\($0.2)" }
}

private let compassShort = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
private let compassLong = ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]

private func compassIndex(_ degrees: Double) -> Int {
    let d = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    return Int((d + 22.5) / 45) % 8
}

/// "SW" for a direction in degrees clockwise from north.
func compassPoint(_ degrees: Double) -> String { compassShort[compassIndex(degrees)] }

/// "from the SW": where the wind comes from, as forecasts say it.
func formatWindFrom(_ degrees: Double) -> String { "from the \(compassPoint(degrees))" }

/// "from the southwest", for VoiceOver.
func formatWindFromSpoken(_ degrees: Double) -> String { "from the \(compassLong[compassIndex(degrees)])" }

/// Below this the wind is calm (Beaufort 0): it has no direction worth giving.
let calmKmh = 2.0
func isCalm(_ kmh: Double) -> Bool { kmh < calmKmh }

/// Past this, a forecast counts as stale: the "updated" line turns amber and suggests a refresh.
let staleAfter: TimeInterval = 90 * 60

/// "Updated just now", "Updated 8 min ago", "Updated over an hour ago" (60 to 119 minutes), "Updated 2 hours ago",
/// "Updated 3 days ago".
func formatUpdated(_ fetchedAt: Date, now: Date) -> String {
    let minutes = max(0, Int(now.timeIntervalSince(fetchedAt) / 60))
    let ago: String
    switch minutes {
    case ..<1: return "Updated just now"
    case ..<60: ago = "\(minutes) min"
    case ..<120: ago = "over an hour"
    case ..<(48 * 60): ago = "\(minutes / 60) hours"
    default: ago = "\(minutes / (24 * 60)) days"
    }
    return "Updated \(ago) ago"
}

func isStale(_ fetchedAt: Date, now: Date) -> Bool { now.timeIntervalSince(fetchedAt) > staleAfter }

// MARK: - Numbers the Java way

/// `String.format(Locale.US, "%.Nf", v)`: like printf, except that an exact tie rounds away from zero (Java's
/// HALF_UP) rather than to even, so amounts read the same as on Android.
func formatFixed(_ v: Double, _ digits: Int) -> String {
    let exact = String(format: "%.40f", abs(v))
    if let dot = exact.firstIndex(of: ".") {
        let tail = exact[exact.index(after: dot)...]
        let rest = tail.dropFirst(digits)
        if rest.first == "5" && rest.dropFirst().allSatisfy({ $0 == "0" }) {
            let nudged = abs(v) + pow(10, -Double(digits)) / 2
            return (v < 0 ? "-" : "") + String(format: "%.\(digits)f", nudged)
        }
    }
    return String(format: "%.\(digits)f", v)
}

/// "1,067": a whole number with US thousands separators.
func groupedThousands(_ n: Int) -> String {
    let digits = String(abs(n))
    var out = ""
    for (i, c) in digits.enumerated() {
        if i > 0 && (digits.count - i) % 3 == 0 { out.append(",") }
        out.append(c)
    }
    return (n < 0 ? "-" : "") + out
}

extension String {
    func removingSuffix(_ suffix: String) -> String { hasSuffix(suffix) ? String(dropLast(suffix.count)) : self }
    func removingPrefix(_ prefix: String) -> String { hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self }
    func trimmingTrailing(_ c: Character) -> String {
        var s = self
        while s.last == c { s.removeLast() }
        return s
    }
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
