import Foundation
import Observation

/// The Weather tab's pages: where you are first (unless that's turned off), then the places you've added (Android's
/// WeatherViewModel pages). Home's glance shows the first page, so the model also answers for it directly
/// ([forecast], [place], …); with no pages at all there's nothing to answer.
@MainActor
@Observable
final class WeatherModel {
    /// Where you are (or its stand-in), the first page while [useCurrentLocation].
    let current: PlaceWeather
    /// The places you've added, in order.
    private(set) var saved: [PlaceWeather]
    /// Whether where you are is a page (Places' "Current location" switch).
    private(set) var useCurrentLocation: Bool
    /// The unit shown large; the other one is shown small next to it (Settings → Temperature). Applies everywhere.
    var unit: TempUnit {
        didSet { settings.unit = unit }
    }

    private let store: SavedPlacesStore
    private let settings: SettingsStore
    /// False in tests: no forecasts read from or written to disk, and nothing fetched when a place is added.
    private let live: Bool

    init(live: Bool = true, store: SavedPlacesStore = SavedPlacesStore(), settings: SettingsStore = SettingsStore()) {
        self.store = store
        self.settings = settings
        unit = settings.unit
        self.live = live
        let cache = live ? PlaceWeather.cacheDirectory : nil
        current = PlaceWeather(cacheDirectory: cache)
        saved = store.load().map { PlaceWeather(saved: $0, cacheDirectory: cache) }
        useCurrentLocation = store.useCurrentLocation
    }

    var pages: [PlaceWeather] { useCurrentLocation ? [current] + saved : saved }

    func page(_ id: String) -> PlaceWeather? { pages.first { $0.id == id } }

    var savedIds: Set<String> { Set(saved.map(\.id)) }

    // MARK: The first page, for Home

    /// The page Home's glance shows: the first; nil with no pages at all.
    var glance: PlaceWeather? { pages.first }

    var place: Place? { glance?.place }
    var placeSource: PlaceWeather.Source { glance?.source ?? .saved }
    var locationDenied: Bool { glance?.locationDenied ?? false }
    var forecast: Forecast? { glance?.forecast }
    var fetchedAt: Date? { glance?.fetchedAt }
    var refreshing: Bool { glance?.refreshing ?? false }
    var refreshFailed: Bool { glance?.refreshFailed ?? false }
    var failure: String? { glance?.failure }

    /// Refreshes the first page (Home's pull to refresh).
    func refresh() async { await glance?.refresh() }

    // MARK: Every page

    /// The first load after launch: every page at once.
    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for page in pages { group.addTask { await page.refresh() } }
        }
    }

    /// On return to the app: the pages whose forecast is more than [age] seconds old.
    func refreshAll(olderThan age: TimeInterval) async {
        await withTaskGroup(of: Void.self) { group in
            for page in pages { group.addTask { await page.refreshIfOlder(than: age) } }
        }
    }

    // MARK: Saved places

    /// Saves [place] as the last page and starts loading it; returns its page id (the existing page's if it's
    /// already saved), so the pager can turn to it.
    @discardableResult
    func add(_ place: Place) -> String {
        guard let places = SavedPlaces.adding(place, to: saved.compactMap(\.place)) else { return place.id }
        let page = PlaceWeather(saved: place, cacheDirectory: live ? PlaceWeather.cacheDirectory : nil)
        saved.append(page)
        store.save(places)
        if live { Task { await page.refresh() } }
        return page.id
    }

    func remove(_ id: String) {
        guard let page = saved.first(where: { $0.id == id }) else { return }
        saved.removeAll { $0.id == id }
        store.save(saved.compactMap(\.place))
        page.forget()
    }

    /// Turns the current-location page on (loading it) or off (it stops loading; its last forecast stays on disk).
    func setUseCurrentLocation(_ on: Bool) {
        guard on != useCurrentLocation else { return }
        useCurrentLocation = on
        store.useCurrentLocation = on
        if on {
            if live { Task { await current.refresh() } }
        } else {
            current.stop()
        }
    }

    /// Moves the saved place at [from] to [to] (indices among the saved places, not the pages).
    func move(from: Int, to: Int) {
        let moved = SavedPlaces.moving(saved.compactMap(\.place), from: from, to: to)
        saved = moved.compactMap { place in saved.first { $0.id == place.id } }
        store.save(moved)
    }
}

/// One page's weather: finds its place (for the current location, the phone's location or a stand-in when location
/// is off; a saved place is fixed), fetches its forecast from Open-Meteo, and keeps the last one on disk so a launch
/// shows something at once.
@MainActor
@Observable
final class PlaceWeather: Identifiable {
    enum Source: String, Codable {
        /// The phone's own location.
        case device
        /// Location is off or unavailable: a city from the phone's time zone, or a default one.
        case fallback
        /// A place you added.
        case saved
    }

    /// "current" for where you are, else the place's id ("geo:2267057").
    let id: String
    private(set) var place: Place?
    private(set) var source: Source
    /// Location permission was refused (or isn't allowed), so the current place is a stand-in.
    private(set) var locationDenied = false
    private(set) var forecast: Forecast?
    /// When the app fetched the forecast (not the model's run time), for "Updated 8 min ago".
    private(set) var fetchedAt: Date?
    private(set) var refreshing = false
    /// The last refresh failed while an older forecast stays up: "Couldn't refresh · updated 2 hours ago".
    private(set) var refreshFailed = false
    /// Why there's no forecast to show; nil while loading or once there is one.
    private(set) var failure: String?

    var isCurrentLocation: Bool { id == Place.currentLocationId }

    typealias Fetch = @Sendable (_ latitude: Double, _ longitude: Double) async throws -> (Forecast, String)

    /// Where each page's last forecast is kept: the app's caches folder.
    static var cacheDirectory: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] }

    private let location: LocationService?
    /// Nil keeps nothing on disk (tests).
    private let cacheDirectory: URL?
    private let fetch: Fetch
    private var refreshTask: Task<Void, Never>?
    /// Which refresh [refreshTask] is, so a stopped one finishing late can't clear its successor.
    private var refreshNumber = 0

    /// The current-location page.
    init(cacheDirectory: URL? = PlaceWeather.cacheDirectory,
         fetch: @escaping Fetch = { try await OpenMeteo.forecast(latitude: $0, longitude: $1) }) {
        id = Place.currentLocationId
        source = .device
        location = LocationService()
        self.cacheDirectory = cacheDirectory
        self.fetch = fetch
        restore()
    }

    /// A saved place's page.
    init(saved place: Place, cacheDirectory: URL? = PlaceWeather.cacheDirectory,
         fetch: @escaping Fetch = { try await OpenMeteo.forecast(latitude: $0, longitude: $1) }) {
        id = place.id
        self.place = place
        source = .saved
        location = nil
        self.cacheDirectory = cacheDirectory
        self.fetch = fetch
        restore()
    }

    /// The first load, or a refresh: one at a time, a second caller waits for the first.
    func refresh() async {
        if let refreshTask { return await refreshTask.value }
        refreshNumber += 1
        let number = refreshNumber
        let task = Task {
            await self.load()
            // Cleared here, before any waiter resumes, so a refresh straight after this one starts a new fetch.
            if self.refreshNumber == number { self.refreshTask = nil }
        }
        refreshTask = task
        await task.value
    }

    /// Refreshes when the forecast is older than [age] seconds (on return to the app).
    func refreshIfOlder(than age: TimeInterval) async {
        guard let fetchedAt, Date().timeIntervalSince(fetchedAt) < age else { return await refresh() }
    }

    /// The page is gone: stop loading and drop its cached forecast.
    func forget() {
        stop()
        if let cacheURL { try? FileManager.default.removeItem(at: cacheURL) }
    }

    /// The page is hidden: stop loading, keeping what it has.
    func stop() {
        refreshTask?.cancel()
        // The next refresh starts afresh rather than joining the cancelled one.
        refreshTask = nil
        refreshNumber += 1
    }

    private func load() async {
        refreshing = forecast != nil
        defer { refreshing = false }
        let found: (place: Place, source: Source)?
        if location != nil { found = await findPlace() } else { found = place.map { ($0, .saved) } }
        guard let found else {
            if forecast == nil { failure = "Couldn't find where you are. Check your connection and try again." }
            refreshFailed = forecast != nil
            return
        }
        do {
            let (fresh, json) = try await fetch(found.place.latitude, found.place.longitude)
            guard !Task.isCancelled else { return }
            place = found.place
            source = found.source
            forecast = fresh
            fetchedAt = Date()
            failure = nil
            refreshFailed = false
            save(json: json)
        } catch {
            // The page was removed while fetching: nothing to report.
            if Task.isCancelled { return }
            if forecast == nil {
                place = found.place
                source = found.source
                failure = message(for: error)
            }
            refreshFailed = forecast != nil
        }
    }

    /// The phone's location; else the city of the phone's time zone, found with Open-Meteo's geocoding; else
    /// [defaultPlace]. Nil only when even the stand-in can't be had and there's nothing to keep.
    private func findPlace() async -> (place: Place, source: Source)? {
        switch await location?.currentPlace() {
        case .place(let p):
            locationDenied = false
            return (p, .device)
        case .denied:
            locationDenied = true
        case .unavailable, nil:
            locationDenied = false
            // Keep the last place we had rather than jumping to another city.
            if let place { return (place, source) }
        }
        if let place, source == .fallback { return (place, .fallback) }
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
        let source: Source
        let fetchedAt: Date
        let json: String
    }

    /// "forecast.json" for where you are (as before there were pages), "forecast-geo-2267057.json" for a saved place.
    private var cacheURL: URL? {
        let name = isCurrentLocation ? "forecast.json" : "forecast-\(id.replacingOccurrences(of: ":", with: "-")).json"
        return cacheDirectory?.appendingPathComponent(name)
    }

    private func save(json: String) {
        guard let place, let fetchedAt, let cacheURL else { return }
        let saved = Saved(place: place, source: source, fetchedAt: fetchedAt, json: json)
        try? JSONEncoder().encode(saved).write(to: cacheURL, options: .atomic)
    }

    private func restore() {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              let forecast = try? parseForecast(saved.json) else { return }
        // A saved page keeps its own place; only the current location's comes from the cache.
        if isCurrentLocation {
            place = saved.place
            source = saved.source
        }
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
