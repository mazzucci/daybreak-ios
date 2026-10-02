import Foundation
import Testing
@testable import Daybreak

/// Saved places (Android's SavedPlacesRepositoryTest), the Weather tab's pages, and "Add a place" search.
@MainActor
struct PlacesTests {
    nonisolated private static func place(_ n: Int, _ name: String) -> Place {
        Place(id: Place.geocodingId(Int64(n)), name: name, region: nil, country: "Portugal", latitude: 38.7,
              longitude: -9.1, countryCode: "PT", zoneId: "Europe/Lisbon")
    }

    private let lisbon = place(2267057, "Lisbon")
    private let porto = place(2735943, "Porto")
    private let faro = place(2268339, "Faro")

    /// A store of its own, so tests don't share or touch the app's places.
    private func freshStore() -> SavedPlacesStore {
        let name = "PlacesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return SavedPlacesStore(defaults: defaults)
    }

    // MARK: The list and the store

    @Test("a place is added at the end, once")
    func addOnce() {
        #expect(SavedPlaces.adding(lisbon, to: [])?.map(\.id) == [lisbon.id])
        #expect(SavedPlaces.adding(porto, to: [lisbon])?.map(\.id) == [lisbon.id, porto.id])
        #expect(SavedPlaces.adding(lisbon, to: [lisbon, porto]) == nil)
    }

    @Test("moving ignores out-of-range indices")
    func move() {
        let list = [lisbon, porto, faro]
        #expect(SavedPlaces.moving(list, from: 0, to: 2).map(\.name) == ["Porto", "Faro", "Lisbon"])
        #expect(SavedPlaces.moving(list, from: 2, to: 0).map(\.name) == ["Faro", "Lisbon", "Porto"])
        #expect(SavedPlaces.moving(list, from: 1, to: 1).map(\.name) == ["Lisbon", "Porto", "Faro"])
        #expect(SavedPlaces.moving(list, from: 3, to: 0).map(\.name) == ["Lisbon", "Porto", "Faro"])
        #expect(SavedPlaces.moving(list, from: 0, to: -1).map(\.name) == ["Lisbon", "Porto", "Faro"])
        #expect(SavedPlaces.removing(porto.id, from: list).map(\.name) == ["Lisbon", "Faro"])
    }

    @Test("the store keeps places in order, with every field")
    func storeRoundTrip() {
        let store = freshStore()
        #expect(store.load().isEmpty)
        store.save([porto, lisbon])
        let loaded = store.load()
        #expect(loaded == [porto, lisbon])
        #expect(loaded.first?.zoneId == "Europe/Lisbon")
        #expect(loaded.first?.countryCode == "PT")
    }

    @Test("corrupt stored places read as none rather than failing")
    func corruptStore() {
        let name = "PlacesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(Data("not json".utf8), forKey: "saved_places")
        #expect(SavedPlacesStore(defaults: defaults).load().isEmpty)
        defaults.removePersistentDomain(forName: name)
    }

    // MARK: Pages

    @Test("the current location is always the first page, then the saved places in order")
    func pages() {
        let store = freshStore()
        store.save([lisbon, porto])
        let model = WeatherModel(live: false, store: store)
        #expect(model.pages.map(\.id) == [Place.currentLocationId, lisbon.id, porto.id])
        #expect(model.pages.first?.isCurrentLocation == true)
        #expect(model.page(porto.id)?.place == porto)
        #expect(model.savedIds == [lisbon.id, porto.id])
    }

    @Test("adding a place makes it the last page and saves it; adding it again changes nothing")
    func addPage() {
        let store = freshStore()
        let model = WeatherModel(live: false, store: store)
        #expect(model.add(lisbon) == lisbon.id)
        #expect(model.add(porto) == porto.id)
        #expect(model.add(lisbon) == lisbon.id)
        #expect(model.pages.map(\.id) == [Place.currentLocationId, lisbon.id, porto.id])
        #expect(store.load() == [lisbon, porto])
        // A fresh model (the next launch) has the same pages.
        #expect(WeatherModel(live: false, store: store).pages.map(\.id) == model.pages.map(\.id))
    }

    @Test("removing and moving saved places update the pages and the store")
    func removeAndMove() {
        let store = freshStore()
        store.save([lisbon, porto, faro])
        let model = WeatherModel(live: false, store: store)
        model.move(from: 2, to: 0)
        #expect(model.saved.map(\.id) == [faro.id, lisbon.id, porto.id])
        #expect(store.load() == [faro, lisbon, porto])
        model.remove(lisbon.id)
        #expect(model.pages.map(\.id) == [Place.currentLocationId, faro.id, porto.id])
        #expect(store.load() == [faro, porto])
        // The current location isn't a saved place: removing it does nothing.
        model.remove(Place.currentLocationId)
        #expect(model.pages.count == 3)
    }

    // MARK: Search

    private func search(_ answer: @escaping @Sendable (String) async throws -> [Place]) -> PlaceSearch {
        PlaceSearch(debounce: .zero, search: answer)
    }

    @Test("under two letters there's nothing to search for")
    func shortQuery() async {
        let s = search { _ in Issue.record("searched"); return [] }
        s.setQuery("L")
        await s.settle()
        #expect(s.results.isEmpty)
        #expect(!s.loading)
        #expect(s.error == nil)
        s.setQuery("  ")
        await s.settle()
        #expect(s.results.isEmpty)
    }

    @Test("matches come back as results")
    func results() async {
        let found = [lisbon]
        let s = search { query in query == "Lisbon" ? found : [] }
        s.setQuery("Lisbon")
        await s.settle()
        #expect(s.results == [lisbon])
        #expect(!s.loading)
        #expect(s.error == nil)
    }

    @Test("no matches says so, and a failure gives its reason")
    func noneAndFailure() async {
        let none = search { _ in [] }
        none.setQuery("Xyzzy")
        await none.settle()
        #expect(none.error == "No places found")

        let failing = search { _ in throw ServiceError("The search service is down") }
        failing.setQuery("Lisbon")
        await failing.settle()
        #expect(failing.error == "The search service is down")
        #expect(!failing.loading)
    }

    @Test("a new query replaces the one before it, and clearing empties everything")
    func replaceAndClear() async {
        let s = search { query in query == "Porto" ? [Self.place(2735943, "Porto")] : [Self.place(2267057, "Lisbon")] }
        s.setQuery("Lisbon")
        s.setQuery("Porto")
        await s.settle()
        #expect(s.results.map(\.name) == ["Porto"])
        s.clear()
        #expect(s.query.isEmpty)
        #expect(s.results.isEmpty)
        #expect(s.error == nil)
    }
}
