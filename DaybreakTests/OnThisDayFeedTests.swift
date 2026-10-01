import Foundation
import Testing
@testable import Daybreak

/// Ported from Android's OnThisDayApiTest: the real feed, parsed, and the filter on real items it used to get wrong.
struct OnThisDayFeedTests {
    private func feed(_ date: String, _ feed: OnThisDayFeed) throws -> [OnThisDayEvent] {
        try parseOnThisDay(TestData.fixture("onthisday_\(feed.rawValue)_\(date).json"), feed: feed)
    }

    @Test("parses the real feed for October 1st")
    func parses() throws {
        let items = try feed("10_01", .selected)
        #expect(items.count == 25)
        let tuvalu = try #require(items.first { $0.year == 1978 })
        #expect(tuvalu.text == "Tuvalu adopted its national flag (pictured) on the day that the country gained its independence.")
        #expect(tuvalu.pages.count == 1)
        let flag = tuvalu.pages[0]
        #expect(flag.title == "Flag of Tuvalu")
        #expect(flag.url == "https://en.wikipedia.org/wiki/Flag_of_Tuvalu")
        #expect(flag.thumbnail?.width == 330)
        #expect(flag.thumbnail?.height == 165)
        #expect(flag.thumbnail?.url.contains("/330px-Flag_of_Tuvalu.svg.png") == true)
        #expect(flag.extract.hasPrefix("The national flag of Tuvalu"))
        // An article without a picture parses without one.
        #expect(items.first { $0.year == 1989 }?.pages.first?.thumbnail == nil)
        #expect(try feed("10_01", .events).count == 25)
        // Asked for the other list, there's nothing.
        #expect(try parseOnThisDay(TestData.fixture("onthisday_selected_10_01.json"), feed: .events).isEmpty)
    }

    /// Real items from the feed that an earlier version of the filter got wrong: cheerful ones it dropped because an
    /// article's life story mentioned a war or a shooting star, and grim ones its word list missed.
    @Test("the filter gets real items right that it used to get wrong", arguments: [
        // Cheerful: must survive.
        ("11_09", OnThisDayFeed.events, 1967, "Apollo 4", false),
        ("07_16", .selected, 1951, "The Catcher in the Rye", false),
        ("07_16", .events, 1951, "The Catcher in the Rye", false),
        ("02_29", .selected, 1940, "Hattie McDaniel", false),
        ("02_29", .events, 1940, "Hattie McDaniel", false),
        ("10_01", .events, 1947, "F-86 Sabre", false),
        ("08_06", .selected, 1996, "ALH84001", false),
        // Grim: must be caught.
        ("08_06", .events, 258, "beheaded", true),
        ("07_16", .events, 2009, "found dead", true),
        ("11_09", .events, 1872, "Great Boston Fire", true),
        ("11_09", .events, 1307, "persecuted", true),
        ("07_16", .selected, 1945, "Trinity test", true),
        ("07_16", .events, 1945, "nuclear weapon", true),
    ])
    func regressions(_ date: String, _ list: OnThisDayFeed, _ year: Int, _ snippet: String, _ grim: Bool) throws {
        let matching = try feed(date, list).filter { $0.year == year && $0.text.contains(snippet) }
        #expect(matching.count == 1)
        let item = try #require(matching.first)
        #expect(OnThisDay.isGrim(item) == grim)
    }

    @Test("December 7th's picks leave out Pearl Harbor")
    func pearlHarbor() throws {
        let picks = OnThisDay.choose(try feed("12_07", .selected), date: LocalDate(2026, 12, 7))
        #expect(!picks.isEmpty)
        #expect(!picks.contains { $0.text.contains("Pearl Harbor") })
    }

    @Test("October 1st's picks leave out the stampede, the shooting, the wars and the murders")
    func octoberFirst() throws {
        let items = try feed("10_01", .selected)
        let picks = OnThisDay.choose(items, date: LocalDate(2026, 10, 1))
        #expect(picks.count == 5)
        let years = picks.map(\.year)
        for grim in [2022, 2017, 2012, 1991, 1965, 1918] { #expect(!years.contains(grim)) }
        #expect(picks == OnThisDay.choose(items, date: LocalDate(2026, 10, 1)))
        // No two from the same decade, and every picture a free one from Commons.
        #expect(Set(picks.map { $0.year / 10 }).count == picks.count)
        #expect(picks.compactMap(\.picture).allSatisfy { OnThisDay.isCommons($0.url) && ($0.fallbackUrl.map(OnThisDay.isCommons) ?? true) })
    }

    @Test("the Thrilla in Manila never shows its non-free poster")
    func thrilla() throws {
        let ali = try #require(try feed("10_01", .selected).first { $0.year == 1975 })
        #expect(ali.pages.contains { $0.thumbnail?.url.contains("/wikipedia/en/") == true })
        let picture = OnThisDay.pictureOf(ali)
        #expect(picture == nil || OnThisDay.isCommons(picture!.url))
        // The 1975 fight in the full list links only the poster's article: words only.
        let fight = try #require(try feed("10_01", .events).first { $0.year == 1975 && $0.text.contains("Frazier") })
        #expect(OnThisDay.pictureOf(fight) == nil)
    }

    @Test("asks for the date's list at Wikipedia's address, with Wikimedia's User-Agent")
    func request() {
        #expect(Wikimedia.url(.selected, month: 3, day: 5).absoluteString
            == "https://en.wikipedia.org/api/rest_v1/feed/onthisday/selected/03/05")
        #expect(Wikimedia.userAgent.hasPrefix("Daybreak/"))
        #expect(Wikimedia.userAgent.hasSuffix(" (https://github.com/mazzucci/Daybreak)"))
    }
}

/// The day's picks are kept for the day: fetched once, then served from the store, and a new day fetches again.
struct OnThisDayStoreTests {
    private func store(_ defaults: String, counter: Counter, fail: Bool = false) -> OnThisDayStore {
        OnThisDayStore(suiteName: defaults, fetch: { month, day, feed in
            await counter.add()
            if fail { throw ServiceError("offline") }
            let text = TestData.fixture("onthisday_\(feed.rawValue)_10_01.json")
            return try parseOnThisDay(text, feed: feed)
        })
    }

    actor Counter {
        var count = 0
        func add() { count += 1 }
    }

    /// A defaults suite of its own for each test.
    private func freshDefaults() -> String { "test-\(UUID().uuidString)" }

    @Test("fetches once a day, then serves the day from the store, with the pick showing")
    func cached() async throws {
        let defaults = freshDefaults()
        let counter = Counter()
        let date = LocalDate(2026, 10, 1)
        let first = try #require(await store(defaults, counter: counter).today(date))
        #expect(first.picks.count == 5)
        await store(defaults, counter: counter).setIndex(date, 2)
        let again = try #require(await store(defaults, counter: counter).today(date))
        #expect(again.picks == first.picks)
        #expect(again.index == 2)
        #expect(await counter.count == 1)
        // A new day asks again.
        _ = await store(defaults, counter: counter).today(date.plusDays(1))
        #expect(await counter.count >= 2)
    }

    @Test("offline gives nothing to show, and waits a few minutes before trying again unless forced")
    func offline() async {
        let defaults = freshDefaults()
        let counter = Counter()
        let s = store(defaults, counter: counter, fail: true)
        let date = LocalDate(2026, 10, 1)
        #expect(await s.today(date) == nil)
        #expect(await s.today(date) == nil)
        #expect(await counter.count == 1)
        #expect(await s.today(date, force: true) == nil)
        #expect(await counter.count == 2)
    }
}
