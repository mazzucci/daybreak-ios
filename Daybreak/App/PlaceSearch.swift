import Foundation
import Observation

/// "Add a place": the query as you type it and Open-Meteo's matches, asked for once you pause (Android's
/// WeatherViewModel search). Under two letters there's nothing to ask; no matches says so.
@MainActor
@Observable
final class PlaceSearch {
    private(set) var query = ""
    private(set) var results: [Place] = []
    private(set) var loading = false
    private(set) var error: String?

    private let search: @Sendable (String) async throws -> [Place]
    private let debounce: Duration
    private var task: Task<Void, Never>?

    init(debounce: Duration = .milliseconds(350),
         search: @escaping @Sendable (String) async throws -> [Place] = { try await OpenMeteo.searchPlaces($0) }) {
        self.debounce = debounce
        self.search = search
    }

    func setQuery(_ text: String) {
        query = text
        error = nil
        task?.cancel()
        if text.trimmingCharacters(in: .whitespaces).count < 2 {
            results = []
            loading = false
            return
        }
        task = Task { [debounce, search] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            loading = true
            do {
                let found = try await search(text)
                guard !Task.isCancelled else { return }
                results = found
                loading = false
                error = found.isEmpty ? "No places found" : nil
            } catch {
                guard !Task.isCancelled else { return }
                loading = false
                self.error = Self.message(for: error)
            }
        }
    }

    /// Why the search failed, in words (Android shows the exception's message, else "Search failed").
    private static func message(for error: Error) -> String {
        if let service = error as? ServiceError { return service.message }
        if (error as? URLError)?.code == .notConnectedToInternet { return "You're offline. Connect and try again." }
        return "Search failed"
    }

    /// Waits for the search in flight, if any (for tests).
    func settle() async { await task?.value }

    func clear() {
        task?.cancel()
        query = ""
        results = []
        loading = false
        error = nil
    }
}
