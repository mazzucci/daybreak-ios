import Foundation
import Testing
@testable import Daybreak

/// One page's weather: its forecast kept on disk and restored at launch, refreshes that don't overlap, failures,
/// and a page removed while it's fetching.
@MainActor
struct PlaceWeatherTests {
    private let lisbon = Place(id: "geo:2267057", name: "Lisbon", region: "Lisbon District", country: "Portugal",
                               latitude: 38.72, longitude: -9.13, countryCode: "PT", zoneId: "Europe/Lisbon")
    private let json = TestData.fixture("forecast_alps_10day.json")

    /// An empty folder of its own for the cached forecasts.
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PlaceWeatherTests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Counts its calls, and answers with the Alps fixture after [delay], or throws [error].
    private final class FakeFetch: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var calls: Int { lock.withLock { count } }
        let json: String
        let delay: Duration
        let error: Error?

        init(json: String, delay: Duration = .zero, error: Error? = nil) {
            self.json = json
            self.delay = delay
            self.error = error
        }

        var fetch: PlaceWeather.Fetch {
            { [self] _, _ in
                lock.withLock { count += 1 }
                try await Task.sleep(for: delay)
                if let error { throw error }
                return (try parseForecast(json), json)
            }
        }
    }

    @Test("a saved page's forecast is kept on disk and shown at the next launch")
    func keptAndRestored() async throws {
        let dir = folder()
        let fake = FakeFetch(json: json)
        let page = PlaceWeather(saved: lisbon, cacheDirectory: dir, fetch: fake.fetch)
        #expect(page.forecast == nil)
        await page.refresh()
        #expect(page.forecast != nil)
        #expect(page.fetchedAt != nil)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("forecast-geo-2267057.json").path))

        let next = PlaceWeather(saved: lisbon, cacheDirectory: dir, fetch: fake.fetch)
        #expect(next.forecast?.days.count == page.forecast?.days.count)
        #expect(next.fetchedAt == page.fetchedAt)
        #expect(next.place == lisbon)
        #expect(next.source == .saved)
    }

    @Test("the current location's forecast from before there were pages still loads")
    func oldCurrentCache() throws {
        let dir = folder()
        // The single-place model's file: forecast.json with "device" or "fallback" as the source.
        let place = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PlaceWeather.defaultPlace))
        let saved: [String: Any] = ["place": place, "source": "fallback", "fetchedAt": 812_345_678.0, "json": json]
        try JSONSerialization.data(withJSONObject: saved).write(to: dir.appendingPathComponent("forecast.json"))

        let page = PlaceWeather(cacheDirectory: dir)
        #expect(page.isCurrentLocation)
        #expect(page.forecast != nil)
        #expect(page.place == PlaceWeather.defaultPlace)
        #expect(page.source == .fallback)
        #expect(page.fetchedAt == Date(timeIntervalSinceReferenceDate: 812_345_678))
    }

    @Test("a saved page keeps its own place, whatever its cached file says")
    func savedKeepsItsPlace() throws {
        let dir = folder()
        let other = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PlaceWeather.defaultPlace))
        let saved: [String: Any] = ["place": other, "source": "saved", "fetchedAt": 0.0, "json": json]
        try JSONSerialization.data(withJSONObject: saved).write(to: dir.appendingPathComponent("forecast-geo-2267057.json"))

        let page = PlaceWeather(saved: lisbon, cacheDirectory: dir)
        #expect(page.place == lisbon)
        #expect(page.forecast != nil)
    }

    @Test("two refreshes at once fetch once; one after that fetches again")
    func coalesced() async {
        let fake = FakeFetch(json: json, delay: .milliseconds(50))
        let page = PlaceWeather(saved: lisbon, cacheDirectory: nil, fetch: fake.fetch)
        async let a: Void = page.refresh()
        async let b: Void = page.refresh()
        _ = await (a, b)
        #expect(fake.calls == 1)
        await page.refresh()
        #expect(fake.calls == 2)
    }

    @Test("a failure says why with nothing to show, and keeps the forecast it has otherwise")
    func failures() async {
        let failing = FakeFetch(json: json, error: ServiceError("The weather service is down"))
        let empty = PlaceWeather(saved: lisbon, cacheDirectory: nil, fetch: failing.fetch)
        await empty.refresh()
        #expect(empty.forecast == nil)
        #expect(empty.failure == "The weather service is down")
        #expect(!empty.refreshFailed)

        let dir = folder()
        let shown = PlaceWeather(saved: lisbon, cacheDirectory: dir, fetch: FakeFetch(json: json).fetch)
        await shown.refresh()
        let restored = PlaceWeather(saved: lisbon, cacheDirectory: dir, fetch: failing.fetch)
        await restored.refresh()
        #expect(restored.forecast != nil)
        #expect(restored.failure == nil)
        #expect(restored.refreshFailed)
    }

    @Test("a page removed while fetching changes nothing and leaves no file behind")
    func removedWhileFetching() async {
        let dir = folder()
        let fake = FakeFetch(json: json, delay: .milliseconds(200))
        let page = PlaceWeather(saved: lisbon, cacheDirectory: dir, fetch: fake.fetch)
        let refresh = Task { await page.refresh() }
        try? await Task.sleep(for: .milliseconds(20))
        page.forget()
        await refresh.value
        #expect(page.forecast == nil)
        #expect(page.failure == nil)
        #expect(!page.refreshFailed)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("forecast-geo-2267057.json").path))
    }
}
