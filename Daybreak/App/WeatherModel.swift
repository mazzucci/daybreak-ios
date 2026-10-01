import Foundation
import Observation

/// The weather for where you are: finds the place (the phone's location, or a stand-in when location is off), fetches
/// its forecast from Open-Meteo, and keeps the last one on disk so a launch shows something at once. Home's glance
/// and the Weather tab both read it.
@MainActor
@Observable
final class WeatherModel {
    enum PlaceSource: String, Codable {
        /// The phone's own location.
        case device
        /// Location is off or unavailable: a city from the phone's time zone, or a default one.
        case fallback
    }

    private(set) var place: Place?
    private(set) var placeSource: PlaceSource = .device
    /// Location permission was refused (or isn't allowed), so the place is a stand-in.
    private(set) var locationDenied = false
    private(set) var forecast: Forecast?
    /// When the app fetched the forecast (not the model's run time), for "Updated 8 min ago".
    private(set) var fetchedAt: Date?
    private(set) var refreshing = false
    /// The last refresh failed while an older forecast stays up: "Couldn't refresh · updated 2 hours ago".
    private(set) var refreshFailed = false
    /// Why there's no forecast to show; nil while loading or once there is one.
    private(set) var failure: String?
    /// The unit shown large; the other one is shown small next to it. °F first, as Android's default.
    var unit: TempUnit = .f

    private let location = LocationService()
    private var refreshTask: Task<Void, Never>?

    init(loadCache: Bool = true) {
        if loadCache { restore() }
    }

    /// The first load after launch, or a refresh: one at a time, a second caller waits for the first.
    func refresh() async {
        if let refreshTask { return await refreshTask.value }
        let task = Task { await self.load() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// Refreshes when the forecast is older than [age] seconds (on return to the app).
    func refreshIfOlder(than age: TimeInterval) async {
        guard let fetchedAt, Date().timeIntervalSince(fetchedAt) < age else { return await refresh() }
    }

    private func load() async {
        refreshing = forecast != nil
        defer { refreshing = false }
        let found = await findPlace()
        guard let found else {
            if forecast == nil { failure = "Couldn't find where you are. Check your connection and try again." }
            refreshFailed = forecast != nil
            return
        }
        do {
            let (fresh, json) = try await OpenMeteo.forecast(latitude: found.place.latitude, longitude: found.place.longitude)
            place = found.place
            placeSource = found.source
            forecast = fresh
            fetchedAt = Date()
            failure = nil
            refreshFailed = false
            save(json: json)
        } catch {
            if forecast == nil {
                place = found.place
                placeSource = found.source
                failure = message(for: error)
            }
            refreshFailed = forecast != nil
        }
    }

    /// The phone's location; else the city of the phone's time zone, found with Open-Meteo's geocoding; else
    /// [defaultPlace]. Nil only when even the stand-in can't be had and there's nothing to keep.
    private func findPlace() async -> (place: Place, source: PlaceSource)? {
        switch await location.currentPlace() {
        case .place(let p):
            locationDenied = false
            return (p, .device)
        case .denied:
            locationDenied = true
        case .unavailable:
            locationDenied = false
            // Keep the last place we had rather than jumping to another city.
            if let place { return (place, placeSource) }
        }
        if let place, placeSource == .fallback { return (place, .fallback) }
        return (await timeZoneCity() ?? Self.defaultPlace, .fallback)
    }

    /// "America/New_York" → New York, looked up by name and checked against the zone.
    private func timeZoneCity() async -> Place? {
        let zone = TimeZone.current.identifier
        guard let city = zone.split(separator: "/").last.map({ $0.replacingOccurrences(of: "_", with: " ") }),
              zone.contains("/") else { return nil }
        guard let results = try? await OpenMeteo.searchPlaces(city) else { return nil }
        return results.first { $0.zoneId == zone } ?? results.first
    }

    static let defaultPlace = Place(id: "geo:5128581", name: "New York", region: "New York", country: "United States",
                                    latitude: 40.71427, longitude: -74.00597, countryCode: "US", zoneId: "America/New_York")

    private func message(for error: Error) -> String {
        if let service = error as? ServiceError { return service.message }
        if (error as? URLError)?.code == .notConnectedToInternet { return "You're offline. Connect and pull to refresh." }
        return "Couldn't reach the weather service. Check your connection and try again."
    }

    // MARK: The last forecast, kept on disk

    private struct Saved: Codable {
        let place: Place
        let source: PlaceSource
        let fetchedAt: Date
        let json: String
    }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("forecast.json")
    }

    private func save(json: String) {
        guard let place, let fetchedAt else { return }
        let saved = Saved(place: place, source: placeSource, fetchedAt: fetchedAt, json: json)
        try? JSONEncoder().encode(saved).write(to: Self.cacheURL, options: .atomic)
    }

    private func restore() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              let forecast = try? parseForecast(saved.json) else { return }
        place = saved.place
        placeSource = saved.source
        fetchedAt = saved.fetchedAt
        self.forecast = forecast
    }
}

/// The "On this day" card's day: its picks and the one showing, or nil while there's nothing to show (not loaded
/// yet, or offline), which hides the card. [load] is cheap to call often: it does nothing while today's picks are in
/// hand or on their way. Ported from Android's OnThisDayViewModel.
@MainActor
@Observable
final class OnThisDayModel {
    private(set) var day: OnThisDayToday?

    private let store: OnThisDayStore
    private let today: () -> LocalDate
    private var loading: Task<Void, Never>?
    private var loadingDate: LocalDate?

    init(store: OnThisDayStore = OnThisDayStore(), today: @escaping () -> LocalDate = { LocalDate.today() }) {
        self.store = store
        self.today = today
    }

    /// Fetches today's picks unless they're in hand (or on their way). [force] (pull to refresh) tries at once rather
    /// than after the few minutes' wait a failure sets.
    func load(force: Bool = false) async {
        let date = today()
        if let shown = day, shown.date == date, shown.complete { return }
        if let loading, !loading.isCancelled {
            if loadingDate == date && !force { return await loading.value }
            loading.cancel()
        }
        loadingDate = date
        let task = Task { [store] in
            let fresh = await store.today(date, force: force)
            guard !Task.isCancelled else { return }
            let before = self.day?.date == date ? self.day : nil
            // Yesterday's never stands in for today's. Today's few stay up if asking again for the rest fails; when
            // the rest arrive, the pick showing stays.
            var next: OnThisDayToday?
            if let fresh {
                next = fresh
                if let current = before?.current, let i = fresh.picks.firstIndex(of: current) { next?.index = i }
            } else {
                next = before
            }
            #if DEBUG
            // `-onThisDayIndex 2`: start on another pick, for screenshots.
            if UserDefaults.standard.object(forKey: "onThisDayIndex") != nil, let n = next?.picks.count, n > 0 {
                let i = UserDefaults.standard.integer(forKey: "onThisDayIndex")
                next?.index = i % n
            }
            #endif
            self.day = next
            if let fresh, let next, next.index != fresh.index { await store.setIndex(date, next.index) }
        }
        loading = task
        await task.value
        if loading == task { loading = nil }
    }

    /// "Another": the next of the day's picks, round to the first again; kept for the rest of the day.
    func another() {
        guard var day, day.picks.count > 1 else { return }
        day.index = (day.index + 1) % day.picks.count
        self.day = day
        let (date, index) = (day.date, day.index)
        Task { [store] in await store.setIndex(date, index) }
    }
}
