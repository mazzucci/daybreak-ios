import Foundation

/// Open-Meteo's forecast and geocoding APIs (free, no API key, HTTPS). Always requested in °C and km/h; the request
/// is the same as Android's OpenMeteoApi.
enum OpenMeteo {
    static func forecastURL(latitude: Double, longitude: Double) -> URL {
        URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)" +
            "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_direction_10m," +
            "weather_code,is_day" +
            "&hourly=temperature_2m,apparent_temperature,precipitation_probability,precipitation,snowfall," +
            "weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,is_day" +
            "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max," +
            "weather_code,sunrise,sunset,wind_speed_10m_max,wind_gusts_10m_max," +
            "wind_direction_10m_dominant,precipitation_sum,precipitation_hours,snowfall_sum,uv_index_max" +
            "&timezone=auto&forecast_days=\(forecastDays)")!
    }

    static func searchURL(_ query: String) -> URL {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [
            URLQueryItem(name: "name", value: query.trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        return c.url!
    }

    static func forecast(latitude: Double, longitude: Double, session: URLSession = .shared) async throws -> (Forecast, String) {
        let json = try await get(forecastURL(latitude: latitude, longitude: longitude), service: "Weather service", session: session)
        return (try parseForecast(json), json)
    }

    static func searchPlaces(_ query: String, session: URLSession = .shared) async throws -> [Place] {
        try parseGeocoding(try await get(searchURL(query), service: "Place search", session: session))
    }

    private static func get(_ url: URL, service: String, session: URLSession) async throws -> String {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(Wikimedia.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError("\(service) returned HTTP \(http.statusCode)")
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// A failure with a message fit to show ("Weather service returned HTTP 503").
struct ServiceError: LocalizedError, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Parses an Open-Meteo /v1/forecast response requested with `timezone=auto` and the fields in
/// [OpenMeteo.forecastURL]. The core fields are required; the detail fields (wind and its direction, gusts, sun times,
/// UV, is_day, feels-like, precipitation amounts, hours and snow) are optional, and a missing array or a null value
/// becomes nil rather than failing the whole forecast.
func parseForecast(_ json: String) throws -> Forecast {
    guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
        throw ServiceError("Weather service sent something unreadable")
    }
    let cur = try object(root, "current")
    guard let now = LocalDateTime.parse(try string(cur, "time")) else { throw ServiceError("Weather service sent a bad time") }
    let current = CurrentConditions(
        time: now,
        tempC: try double(cur, "temperature_2m"),
        feelsLikeC: try double(cur, "apparent_temperature"),
        humidity: Int(try double(cur, "relative_humidity_2m")),
        windKmh: try double(cur, "wind_speed_10m"),
        code: Int(try double(cur, "weather_code")),
        isDay: flag(cur["is_day"]),
        windDirectionDeg: number(cur["wind_direction_10m"])
    )

    let hourly = try object(root, "hourly")
    let hourTimes = try array(hourly, "time")
    let hourTemps = try array(hourly, "temperature_2m")
    let hourPrecip = try array(hourly, "precipitation_probability")
    let hourCodes = try array(hourly, "weather_code")
    let hourWind = hourly["wind_speed_10m"] as? [Any]
    let hourGusts = hourly["wind_gusts_10m"] as? [Any]
    let hourIsDay = hourly["is_day"] as? [Any]
    let hourFeels = hourly["apparent_temperature"] as? [Any]
    let hourPrecipMm = hourly["precipitation"] as? [Any]
    let hourSnow = hourly["snowfall"] as? [Any]
    let hourWindDir = hourly["wind_direction_10m"] as? [Any]
    let hours: [HourForecast] = try hourTimes.indices.map { i in
        guard let time = (hourTimes[i] as? String).flatMap(LocalDateTime.parse) else { throw ServiceError("Weather service sent a bad time") }
        return HourForecast(
            time: time,
            tempC: try required(hourTemps, i),
            precipChance: Int(at(hourPrecip, i) ?? 0),
            code: Int(try required(hourCodes, i)),
            windKmh: at(hourWind, i),
            gustKmh: at(hourGusts, i),
            isDay: at(hourIsDay, i).map { $0 != 0 },
            feelsLikeC: at(hourFeels, i),
            precipMm: at(hourPrecipMm, i),
            snowCm: at(hourSnow, i),
            windDirectionDeg: at(hourWindDir, i)
        )
    }

    let daily = try object(root, "daily")
    let dayDates = try array(daily, "time")
    if dayDates.isEmpty { throw ServiceError("Weather service returned no daily forecast") }
    let highs = try array(daily, "temperature_2m_max")
    let lows = try array(daily, "temperature_2m_min")
    let dayPrecip = try array(daily, "precipitation_probability_max")
    let dayCodes = try array(daily, "weather_code")
    let sunrises = daily["sunrise"] as? [Any]
    let sunsets = daily["sunset"] as? [Any]
    let windMax = daily["wind_speed_10m_max"] as? [Any]
    let gustMax = daily["wind_gusts_10m_max"] as? [Any]
    let precipSum = daily["precipitation_sum"] as? [Any]
    let uvMax = daily["uv_index_max"] as? [Any]
    let precipHours = daily["precipitation_hours"] as? [Any]
    let snowSum = daily["snowfall_sum"] as? [Any]
    let windDir = daily["wind_direction_10m_dominant"] as? [Any]
    let days: [DaySummary] = try dayDates.indices.map { i in
        guard let date = (dayDates[i] as? String).flatMap(LocalDate.parse) else { throw ServiceError("Weather service sent a bad date") }
        return DaySummary(
            date: date,
            highC: try required(highs, i),
            lowC: try required(lows, i),
            precipChance: Int(at(dayPrecip, i) ?? 0),
            code: Int(try required(dayCodes, i)),
            sunrise: time(sunrises, i),
            sunset: time(sunsets, i),
            windMaxKmh: at(windMax, i),
            gustMaxKmh: at(gustMax, i),
            precipSumMm: at(precipSum, i),
            uvIndexMax: at(uvMax, i),
            precipHours: at(precipHours, i),
            snowSumCm: at(snowSum, i),
            windDirectionDeg: at(windDir, i)
        )
    }

    return Forecast(current: current, days: days, hours: hours, utcOffsetSeconds: Int(number(root["utc_offset_seconds"]) ?? 0))
}

/// Parses an Open-Meteo geocoding /v1/search response. No matches gives an empty list (the API omits "results").
func parseGeocoding(_ json: String) throws -> [Place] {
    guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return [] }
    guard let results = root["results"] as? [[String: Any]] else { return [] }
    return try results.map { r in
        guard let id = number(r["id"]), let name = r["name"] as? String,
              let latitude = number(r["latitude"]), let longitude = number(r["longitude"]) else {
            throw ServiceError("Place search sent an unreadable place")
        }
        return Place(
            id: Place.geocodingId(Int64(id)),
            name: name,
            region: nonBlank(r["admin1"]),
            country: nonBlank(r["country"]),
            latitude: latitude,
            longitude: longitude,
            countryCode: nonBlank(r["country_code"])?.uppercased(),
            zoneId: nonBlank(r["timezone"])
        )
    }
}

// MARK: - JSON helpers

private func object(_ o: [String: Any], _ key: String) throws -> [String: Any] {
    guard let v = o[key] as? [String: Any] else { throw ServiceError("Weather service left out \(key)") }
    return v
}

private func array(_ o: [String: Any], _ key: String) throws -> [Any] {
    guard let v = o[key] as? [Any] else { throw ServiceError("Weather service left out \(key)") }
    return v
}

private func string(_ o: [String: Any], _ key: String) throws -> String {
    guard let v = o[key] as? String else { throw ServiceError("Weather service left out \(key)") }
    return v
}

private func double(_ o: [String: Any], _ key: String) throws -> Double {
    guard let v = number(o[key]) else { throw ServiceError("Weather service left out \(key)") }
    return v
}

/// A JSON number (not a boolean, not null) as a Double.
private func number(_ v: Any?) -> Double? {
    guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    let d = n.doubleValue
    return d.isNaN ? nil : d
}

/// Open-Meteo's 0/1 is_day flag (a JSON boolean is accepted too); nil if missing or anything else.
private func flag(_ v: Any?) -> Bool? {
    guard let n = v as? NSNumber else { return nil }
    if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
    return n.intValue != 0
}

/// Value at [i] of an optional array; nil if the array is missing, too short, or holds null there.
private func at(_ a: [Any]?, _ i: Int) -> Double? {
    guard let a, i < a.count else { return nil }
    if let n = a[i] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? 1 : 0 }
    return number(a[i])
}

private func required(_ a: [Any], _ i: Int) throws -> Double {
    guard let v = at(a, i) else { throw ServiceError("Weather service left out a value") }
    return v
}

private func time(_ a: [Any]?, _ i: Int) -> LocalDateTime? {
    guard let a, i < a.count, let s = a[i] as? String else { return nil }
    return LocalDateTime.parse(s)
}

private func nonBlank(_ v: Any?) -> String? {
    guard let s = v as? String, !s.isBlank else { return nil }
    return s
}
