import Foundation

/// The day's picks for the "On this day" card, and which one is showing ("Another" moves it on). [complete] is false
/// for a day made of the curated list alone because the full list that should have made it up couldn't be fetched:
/// shown, but not kept, and asked for again later.
struct OnThisDayToday: Equatable, Sendable, Codable {
    let date: LocalDate
    let picks: [OnThisDayPick]
    var index: Int = 0
    var complete: Bool = true

    var current: OnThisDayPick? {
        picks.isEmpty ? nil : picks[((index % picks.count) + picks.count) % picks.count]
    }

    enum CodingKeys: String, CodingKey { case date, picks, index }

    init(date: LocalDate, picks: [OnThisDayPick], index: Int = 0, complete: Bool = true) {
        self.date = date
        self.picks = picks
        self.index = index
        self.complete = complete
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let date = LocalDate.parse(try c.decode(String.self, forKey: .date)) else {
            throw DecodingError.dataCorruptedError(forKey: .date, in: c, debugDescription: "Not a date")
        }
        self.date = date
        picks = try c.decode([OnThisDayPick].self, forKey: .picks)
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        complete = true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date.description, forKey: .date)
        try c.encode(picks, forKey: .picks)
        try c.encode(index, forKey: .index)
    }
}

/// Fetches "On this day" once per local date and keeps the day's picks (and the one showing), so the card is the
/// same all day, across launches, and costs one request a day: the curated list, plus the full list of events only
/// when too few of the curated ones are cheerful enough. A failed fetch gives nil (Home hides the card), or the
/// curated few when only the full list failed, and is remembered for 10 minutes so a flaky connection isn't retried
/// on every return to the app; pull to refresh asks with `force` and skips that wait. Ported from Android's
/// OnThisDayRepository.
actor OnThisDayStore {
    typealias Fetch = @Sendable (_ month: Int, _ day: Int, _ feed: OnThisDayFeed) async throws -> [OnThisDayEvent]

    private let fetch: Fetch
    /// Where the day is kept: the app's own defaults, or a named suite (tests).
    private let suiteName: String?
    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }
    private let now: @Sendable () -> Date
    private var failed: (date: LocalDate, at: Date, partial: OnThisDayToday?)?

    /// One entry, replaced each day, so yesterday's never lingers.
    static let key = "on_this_day_v2"
    static let retryAfter: TimeInterval = 10 * 60

    init(
        suiteName: String? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        fetch: @escaping Fetch = { try await Wikimedia.events(month: $0, day: $1, feed: $2) }
    ) {
        self.suiteName = suiteName
        self.now = now
        self.fetch = fetch
    }

    /// Today's picks (empty when nothing that day was cheerful enough), or nil when they couldn't be fetched. Within
    /// a few minutes of a failure for [date] it doesn't ask again (giving what it had then) unless [force].
    func today(_ date: LocalDate, force: Bool = false) async -> OnThisDayToday? {
        if let cached = cached(date) { return cached }
        if let failed, !force, failed.date == date, now().timeIntervalSince(failed.at) < Self.retryAfter {
            return failed.partial
        }
        do {
            let selected = try await fetch(date.month, date.day, .selected)
            let first = OnThisDay.choose(selected, date: date)
            if first.count >= OnThisDay.minSelected { return done(OnThisDayToday(date: date, picks: first)) }
            if let more = await more(date, selected, first) {
                return done(OnThisDayToday(date: date, picks: first + more))
            }
            // The few stand for now, unsaved, and the full list is asked for again later.
            let partial = OnThisDayToday(date: date, picks: first, complete: false)
            failed = (date, now(), partial)
            return partial
        } catch {
            failed = (date, now(), nil)
            return nil
        }
    }

    /// Shows the pick at [index] for the rest of [date] (from "Another"); nothing for another day, or an unkept one.
    func setIndex(_ date: LocalDate, _ index: Int) {
        guard var day = cached(date) else { return }
        day.index = index
        save(day)
    }

    private func done(_ day: OnThisDayToday) -> OnThisDayToday {
        save(day)
        failed = nil
        return day
    }

    /// From the full list, to make up the curated one's few; nil when it can't be had.
    private func more(_ date: LocalDate, _ selected: [OnThisDayEvent], _ have: [OnThisDayPick]) async -> [OnThisDayPick]? {
        guard let events = try? await fetch(date.month, date.day, .events) else { return nil }
        return OnThisDay.choose(events, date: date, max: OnThisDay.maxPicks - have.count, besides: selected, taken: have)
    }

    /// The stored day if it's [date]'s; nil for another day's, or anything unreadable.
    private func cached(_ date: LocalDate) -> OnThisDayToday? {
        guard let data = defaults.data(forKey: Self.key),
              let day = try? JSONDecoder().decode(OnThisDayToday.self, from: data), day.date == date else { return nil }
        return day
    }

    private func save(_ day: OnThisDayToday) {
        if let data = try? JSONEncoder().encode(day) { defaults.set(data, forKey: Self.key) }
    }
}
