import Foundation

/// The places you've added, in order (Android's SavedPlacesRepository), kept in UserDefaults as JSON. The current
/// location isn't one of them: it's always the first page.
struct SavedPlacesStore {
    private let defaults: UserDefaults
    private static let key = "saved_places"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved places; none when there are none yet or what's stored can't be read (corrupt data shouldn't brick
    /// the app: the places can be added again).
    func load() -> [Place] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([Place].self, from: data)) ?? []
    }

    func save(_ places: [Place]) {
        guard let data = try? JSONEncoder().encode(places) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

/// The list operations behind the store, kept pure so they can be tested on their own.
enum SavedPlaces {
    /// [place] added at the end; nil if it's already saved.
    static func adding(_ place: Place, to places: [Place]) -> [Place]? {
        places.contains { $0.id == place.id } ? nil : places + [place]
    }

    static func removing(_ id: String, from places: [Place]) -> [Place] {
        places.filter { $0.id != id }
    }

    /// The place at [from] moved to index [to]; out-of-range indices change nothing.
    static func moving(_ places: [Place], from: Int, to: Int) -> [Place] {
        guard places.indices.contains(from), places.indices.contains(to), from != to else { return places }
        var list = places
        list.insert(list.remove(at: from), at: to)
        return list
    }
}
