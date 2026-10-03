import Foundation

/// Days of forecast fetched per place (today included). Open-Meteo allows up to 16.
let forecastDays = 10

/// Length of the hourly strip and of the window the summary describes.
let nextHoursCount = 12

/// Length of the multi-day list (today included).
let listDays = 10

/// Days in the list from this one on (0 = today) are further out than a week, so they're drawn as less certain.
let lessCertainFrom = 7

/// A place the app can show weather for: the device's current location, or a place found by name.
struct Place: Hashable, Sendable, Codable {
    var id: String
    var name: String
    var region: String?
    var country: String?
    var latitude: Double
    var longitude: Double
    /// ISO 3166-1 alpha-2 code ("US"); nil if unknown.
    var countryCode: String?
    /// IANA time zone ("Europe/Bucharest"); nil if unknown.
    var zoneId: String?

    /// "Region, Country" shown under the name; nil if there's nothing to add.
    var detail: String? {
        let joined = [region, country].compactMap { $0 }.joined(separator: ", ")
        return joined.trimmingCharacters(in: .whitespaces).isEmpty ? nil : joined
    }

    static let currentLocationId = "current"
    static let geocodingPrefix = "geo:"
    static func geocodingId(_ id: Int64) -> String { "\(geocodingPrefix)\(id)" }
}

/// Everything the UI needs about one place's weather. All temperatures in °C, wind in km/h.
struct Forecast: Sendable {
    let current: CurrentConditions
    /// One entry per day, starting with the place's today (up to [forecastDays]). Never empty.
    let days: [DaySummary]
    /// Hourly forecast for the same range as [days], in the place's local time.
    let hours: [HourForecast]
    /// The place's offset from UTC now.
    let utcOffsetSeconds: Int

    /// The day containing the current conditions' time.
    let today: DaySummary
    /// The current hour and the [nextHoursCount] - 1 after it.
    let nextHours: [HourForecast]
    private let byTime: [LocalDateTime: HourForecast]

    init(current: CurrentConditions, days: [DaySummary], hours: [HourForecast], utcOffsetSeconds: Int = 0) {
        precondition(!days.isEmpty, "A forecast needs at least one day")
        self.current = current
        self.days = days
        self.hours = hours
        self.utcOffsetSeconds = utcOffsetSeconds
        let todayDate = current.time.date
        today = days.first { $0.date == todayDate } ?? days[0]
        let thisHour = current.time.truncatedToHour
        nextHours = Array(hours.filter { $0.time >= thisHour }.prefix(nextHoursCount))
        var map: [LocalDateTime: HourForecast] = [:]
        for h in hours where map[h.time] == nil { map[h.time] = h }
        byTime = map
    }

    /// Today and the days after it, for the multi-day list (at most [count]).
    func upcomingDays(_ count: Int = listDays) -> [DaySummary] {
        Array(days.filter { $0.date >= today.date }.prefix(count))
    }

    /// The hours of [date], stamped midnight to 11 PM (fewer if the data starts or ends that day). Their rain covers
    /// 11 PM the evening before to 11 PM, the same hours as Open-Meteo's daily sums (see [Precip]).
    func hoursOf(_ date: LocalDate) -> [HourForecast] { hours.filter { $0.time.date == date } }

    /// The hour stamped [time], if the forecast has it.
    func hourAt(_ time: LocalDateTime) -> HourForecast? { byTime[time] }

    /// The hour whose precipitation, snowfall and chance fall during [hour]: Open-Meteo stamps them at the end of the
    /// hour they cover, so it's the one stamped an hour later. Nil past the end of the data.
    func rainDuring(_ hour: HourForecast) -> HourForecast? { hourAt(hour.time.plusHours(1)) }

    /// The day with this date, if the forecast has it.
    func day(_ date: LocalDate) -> DaySummary? { days.first { $0.date == date } }

    /// Whether it's dark now at the place, from Open-Meteo's is_day flag or else from sunrise and sunset.
    var isNightNow: Bool { current.isDay.map { !$0 } ?? isNight(current.time) }

    /// Whether it's dark at the start of [hour].
    func isNight(_ hour: HourForecast) -> Bool { hour.isDay.map { !$0 } ?? isNight(hour.time) }

    /// Whether [time] falls outside that day's sunrise–sunset, allowing for a previous day's sunset after midnight.
    /// Polar night is always night and midnight sun never is; without sun times, 8 PM to 6 AM is night.
    func isNight(_ time: LocalDateTime) -> Bool {
        let date = time.date
        if let yesterday = days.first(where: { $0.date == date.plusDays(-1) }), yesterday.daylight == .normal,
           let lateSunset = yesterday.sunset, time < lateSunset {
            return false
        }
        let day = days.first { $0.date == date }
        switch day?.daylight {
        case .polarNight: return true
        case .midnightSun: return false
        case .normal: return time < day!.sunrise! || time >= day!.sunset!
        case .unknown, nil: return time.hour < 6 || time.hour >= 20
        }
    }
}

struct CurrentConditions: Sendable {
    var time: LocalDateTime
    var tempC: Double
    var feelsLikeC: Double
    var humidity: Int
    var windKmh: Double
    var code: Int
    /// Open-Meteo's is_day flag; nil if the response didn't include it.
    var isDay: Bool? = nil
    /// Direction the wind blows from now, degrees clockwise from north; nil if missing.
    var windDirectionDeg: Double? = nil

    var description: String { describeWeatherCode(code) }
}

struct DaySummary: Sendable {
    var date: LocalDate
    var highC: Double
    var lowC: Double
    /// Highest hourly chance of precipitation on [date], 0–100.
    var precipChance: Int
    var code: Int
    /// Local sunrise and sunset; nil when the sun doesn't rise or set that day, or the field is missing.
    var sunrise: LocalDateTime? = nil
    var sunset: LocalDateTime? = nil
    /// Highest sustained wind and gust of the day, km/h.
    var windMaxKmh: Double? = nil
    var gustMaxKmh: Double? = nil
    /// Total rain, showers and snow water equivalent, mm.
    var precipSumMm: Double? = nil
    /// Highest UV index of the day.
    var uvIndexMax: Double? = nil
    /// Hours with any precipitation (Open-Meteo's precipitation_hours).
    var precipHours: Double? = nil
    /// Total snowfall, cm (not water equivalent).
    var snowSumCm: Double? = nil
    /// Direction the wind mostly blows from, degrees clockwise from north.
    var windDirectionDeg: Double? = nil

    /// How the sun behaves on [date]. Open-Meteo marks polar night with sunrise == sunset and midnight sun with a
    /// sunset 24 hours after sunrise.
    var daylight: Daylight {
        guard let sunrise, let sunset else { return .unknown }
        if !(sunset > sunrise) { return .polarNight }
        if !(sunset < sunrise.plusHours(24)) { return .midnightSun }
        return .normal
    }
}

enum Daylight: Sendable { case normal, polarNight, midnightSun, unknown }

struct HourForecast: Equatable, Sendable {
    var time: LocalDateTime
    var tempC: Double
    /// Chance of at least 0.1 mm in the hour ending at [time], 0–100.
    var precipChance: Int
    var code: Int
    /// Sustained wind and gusts at 10 m, km/h; nil if missing.
    var windKmh: Double? = nil
    var gustKmh: Double? = nil
    /// Open-Meteo's is_day flag for the start of the hour; nil if missing.
    var isDay: Bool? = nil
    /// Apparent ("feels like") temperature, °C; nil if missing.
    var feelsLikeC: Double? = nil
    /// Precipitation over the hour ending at [time], mm; nil if missing (see [Precip]).
    var precipMm: Double? = nil
    /// Snowfall over the hour ending at [time], cm; nil if missing.
    var snowCm: Double? = nil
    /// Direction the wind blows from, degrees clockwise from north; nil if missing.
    var windDirectionDeg: Double? = nil
}

enum TempUnit: String, Sendable, Codable {
    case f = "F"
    case c = "C"

    var other: TempUnit { self == .f ? .c : .f }
}
