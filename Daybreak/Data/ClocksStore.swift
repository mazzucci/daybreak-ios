import Foundation
import Observation

/// The saved clocks, in order (Android's ClocksRepository), kept in UserDefaults as JSON. Entries that don't read are
/// dropped rather than losing the rest.
struct ClocksStore {
    private let defaults: UserDefaults
    private static let key = "clocks"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [Clock] {
        guard let data = defaults.data(forKey: Self.key),
              let entries = try? JSONDecoder().decode([Lenient].self, from: data) else { return [] }
        return entries.compactMap(\.clock)
    }

    func save(_ clocks: [Clock]) {
        guard let data = try? JSONEncoder().encode(clocks) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// One stored entry, or nil when it doesn't read as a clock.
    private struct Lenient: Decodable {
        let clock: Clock?
        init(from decoder: Decoder) throws { clock = try? Clock(from: decoder) }
    }
}

/// The Clocks tab's list (Android's ClocksViewModel); the converter's picks are view state.
@MainActor
@Observable
final class ClocksModel {
    private(set) var clocks: [Clock]
    private let store: ClocksStore

    init(store: ClocksStore = ClocksStore()) {
        self.store = store
        clocks = store.load()
    }

    var ids: Set<String> { Set(clocks.map(\.id)) }

    /// Adds [place] as the last clock; false when it has no time zone this phone knows, or is already there.
    @discardableResult
    func add(_ place: Place) -> Bool {
        guard let clock = Clock.of(place), !clocks.contains(where: { $0.id == clock.id }) else { return false }
        clocks.append(clock)
        store.save(clocks)
        return true
    }

    func remove(_ id: String) {
        clocks.removeAll { $0.id == id }
        store.save(clocks)
    }

    /// Moves the clock at [from] to index [to]; out-of-range indices are ignored.
    func move(from: Int, to: Int) {
        guard clocks.indices.contains(from), clocks.indices.contains(to), from != to else { return }
        clocks.insert(clocks.remove(at: from), at: to)
        store.save(clocks)
    }
}
