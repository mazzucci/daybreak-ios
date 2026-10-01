import Foundation
import Testing
@testable import Daybreak

/// Ported from Android's OnThisDayTest: the grim filter, scoring, the day's picks, the subject and its picture.
struct OnThisDayTests {
    private struct Pictures { let thumbnail: WikiImage; let original: WikiImage }

    /// A Commons photo, 3264 x 2448 originally, as the feed gives it.
    private func photo(_ name: String = "X.jpg", _ width: Int = 3264, _ height: Int = 2448) -> Pictures {
        Pictures(
            thumbnail: WikiImage(url: "https://thumb.wikimedia.org/wikipedia/commons/thumb/a/ab/\(name)/330px-\(name)", width: 330, height: 330 * height / width),
            original: WikiImage(url: "https://upload.wikimedia.org/wikipedia/commons/a/ab/\(name)", width: width, height: height)
        )
    }

    /// A Commons drawing rendered to PNG (the original's size is the SVG's nominal one).
    private func drawing(_ name: String = "Flag.svg", _ width: Int = 600, _ height: Int = 300) -> Pictures {
        Pictures(
            thumbnail: WikiImage(url: "https://thumb.wikimedia.org/wikipedia/commons/thumb/c/cd/\(name)/330px-\(name).png", width: 330, height: 330 * height / width),
            original: WikiImage(url: "https://thumb.wikimedia.org/wikipedia/commons/thumb/c/cd/\(name)/250px-\(name).png", width: width, height: height)
        )
    }

    /// A non-free picture from English Wikipedia (a film poster, a logo).
    private func nonFree(_ name: String = "Poster.jpg") -> Pictures {
        Pictures(
            thumbnail: WikiImage(url: "https://upload.wikimedia.org/wikipedia/en/e/ef/\(name)", width: 250, height: 375),
            original: WikiImage(url: "https://upload.wikimedia.org/wikipedia/en/e/ef/\(name)", width: 250, height: 375)
        )
    }

    private func page(_ title: String = "Page", extract: String = "", pictures: Pictures? = nil, noPicture: Bool = false) -> WikiPage {
        let p = noPicture ? nil : (pictures ?? photo())
        return WikiPage(title: title, extract: extract, url: "https://en.wikipedia.org/wiki/\(title.replacingOccurrences(of: " ", with: "_"))",
                        thumbnail: p?.thumbnail, original: p?.original)
    }

    private func event(_ text: String, _ year: Int = 1969, _ pages: WikiPage...) -> OnThisDayEvent {
        OnThisDayEvent(year: year, text: text, pages: pages.isEmpty ? [page()] : pages)
    }

    private let date = LocalDate(2026, 10, 1)

    // MARK: The grim filter

    @Test("violence, disasters, death, persecution and war are grim, whatever the case", arguments: [
        "Twelve people were killed in the attack.",
        "The massacre at the village.",
        "A bombing in the city centre.",
        "Rebels attack the capital.",
        "A mass shooting at a festival.",
        "The king was executed.",
        "The king was beheaded.",
        "Two men were hanged at dawn.",
        "The bishop is burned at the stake.",
        "A pogrom in the city.",
        "The abolition of slavery is debated.",
        "The ship carried enslaved people.",
        "The president is assassinated.",
        "A murder trial begins.",
        "The genocide began.",
        "A terrorist group claims it.",
        "Hostages were freed after a week.",
        "The king dies at the age of 80.",
        "The composer died in Vienna.",
        "The death of the emperor.",
        "An aide is found dead on a rooftop.",
        "Forty fatalities were reported.",
        "The victims are remembered.",
        "Dissidents are persecuted and tortured.",
        "Families are deported to a concentration camp.",
        "A fascist government takes power.",
        "The worst disaster in the country's history.",
        "A plane crash in the mountains.",
        "An EARTHQUAKE strikes the coast.",
        "A tsunami hits the islands.",
        "Famine spreads across the region.",
        "A cholera epidemic breaks out.",
        "An explosion at the factory.",
        "The ferry sinks off the coast.",
        "The shipwreck was found.",
        "The Great Fire of London begins.",
        "The Great Chicago Fire breaks out.",
        "The first atomic bomb is ready.",
        "A nuclear test in the desert.",
        "The country detonates its first device.",
        "War is declared.",
        "The Battle of Hastings.",
        "The invasion of Normandy.",
        "Troops enter the city.",
        "A military coup topples the government.",
    ])
    func grim(_ text: String) {
        #expect(OnThisDay.isGrim(event(text)))
    }

    @Test("war inside a hyphenated word is still about a war", arguments: [
        "The post-war constitution is adopted.",
        "An anti-war march fills the capital.",
        "War-time rationing ends.",
        "The pre-war borders are restored.",
    ])
    func hyphenatedWar(_ text: String) {
        #expect(OnThisDay.isGrim(event(text)))
    }

    @Test("the filter matches whole words, not parts of them, and lets harmless names through", arguments: [
        "The University of Warsaw opens its doors.",
        "Battlestar Galactica premieres on television.",
        "Star Wars opens in cinemas across the United States.",
        "Orson Welles broadcasts The War of the Worlds on the radio.",
        "Billie Jean King wins the Battle of the Sexes.",
        "The Cold War ends with the Malta Summit.",
        "Die Hard premieres in Los Angeles.",
        "The Metamorphosis by Franz Kafka is published in Die Weissen Blaetter.",
        "The first Coupe de France final is played.",
        "The Bombay Stock Exchange opens.",
        "A skilled crew finishes the bridge, which wins an award.",
        "The warm spring brings the first software release toward the coast.",
        "The Dead Sea Scrolls go on show.",
        "A greater firefly is named.",
    ])
    func notGrim(_ text: String) {
        #expect(!OnThisDay.isGrim(event(text)))
    }

    @Test("only the first sentence of the subject's article counts")
    func firstSentenceOnly() {
        let grimArticle = page("Old Fort", extract: "The Old Fort was the scene of a massacre in 1857. It is now a museum.")
        #expect(OnThisDay.isGrim(event("The Old Fort opens as a museum.", 1920, grimArticle)))
        // A writer's article saying, later on, that he served in a war is no reason to drop his novel.
        let salinger = page("J. D. Salinger", extract: "Jerome David Salinger was an American writer. He served in World War II.")
        #expect(!OnThisDay.isGrim(event("J. D. Salinger publishes a novel.", 1951, salinger)))
        // Only the subject's: another article's opening sentence doesn't count (its title does).
        let other = page("Leopold III", extract: "Leopold III was king during the invasion of Belgium.")
        #expect(!OnThisDay.isGrim(event("J. D. Salinger publishes a novel.", 1951, salinger, other)))
        #expect(OnThisDay.firstSentence(salinger.extract) == "Jerome David Salinger was an American writer.")
        #expect(OnThisDay.firstSentence("J. D. Salinger was born in New York. He wrote.") == "J. D. Salinger was born in New York.")
    }

    @Test("the titles of the linked articles count too")
    func linkedTitles() {
        #expect(OnThisDay.isGrim(event("A festival in Las Vegas.", 2017, page("Route 91 Harvest"), page("2017 Las Vegas shooting"))))
        #expect(OnThisDay.isGrim(event("A test near Alamogordo.", 1945, page("Trinity (nuclear test)"))))
    }

    // MARK: Scoring

    @Test("a good picture, fun and firsts score higher, dry politics lower")
    func scoring() {
        let opening = event("Walt Disney World opens near Orlando, Florida.")
        let noPicture = event("Walt Disney World opens near Orlando, Florida.", 1971, page(noPicture: true))
        let treaty = event("A treaty is signed by the president and parliament.")
        let first = event("Concorde breaks the sound barrier for the first time.")
        #expect(OnThisDay.score(opening) > OnThisDay.score(noPicture))
        #expect(OnThisDay.score(opening) > OnThisDay.score(treaty))
        #expect(OnThisDay.score(treaty) < OnThisDay.score(event("Something happened.")))
        // Space and flight, plus a first, plus the picture.
        #expect(OnThisDay.score(first) == 3 + 2 + 1)
        // Science and culture each count once, however many of their words appear.
        #expect(OnThisDay.score(event("A scientist discovers a comet and publishes a book about it.")) == 3 + 2 + 2)
    }

    @Test("a logo, seal, emblem or drawing is worth less than a photo, and a non-free picture nothing")
    func pictureScores() {
        let text = "Something happened."
        #expect(OnThisDay.score(event(text, 1969, page(pictures: photo("Crowd.jpg")))) == 3)
        #expect(OnThisDay.score(event(text, 1969, page(pictures: drawing("Flag_of_Tuvalu.svg")))) == 1)
        #expect(OnThisDay.score(event(text, 1969, page(pictures: photo("Club_logo.png")))) == 1)
        #expect(OnThisDay.score(event(text, 1969, page(pictures: photo("Great_Seal_of_Ohio.jpg")))) == 1)
        #expect(OnThisDay.score(event(text, 1969, page(pictures: photo("Coat_of_arms_of_Peru.png")))) == 1)
        #expect(OnThisDay.score(event(text, 1969, page(pictures: nonFree()))) == 0)
    }

    @Test("nature and milestones are fun, police and protests are dry")
    func natureAndDry() {
        let none = page(noPicture: true)
        #expect(OnThisDay.score(event("Yosemite National Park is established.", 1890, none)) == 2)
        #expect(OnThisDay.score(event("Women gain the right to vote in New Zealand.", 1893, none)) == 2)
        #expect(OnThisDay.score(event("Tuvalu becomes independent.", 1978, none)) == 2)
        #expect(OnThisDay.score(event("The Channel Tunnel opens to traffic.", 1994, none)) == 2 + 2) // and an opening
        #expect(OnThisDay.score(event("Police arrest the protesters.", 1968, none)) == -2)
        #expect(OnThisDay.score(event("Workers go on strike.", 1926, none)) == -2)
        #expect(OnThisDay.score(event("A deputation meets the viceroy.", 1906, none)) == -2)
        // "Congress" alone isn't dry: it as often founds a park as passes a tax.
        #expect(OnThisDay.score(event("Congress meets.", 1789, none)) == 0)
    }

    @Test("the picks prefer pictures and fun, and leave the grim ones out")
    func picksPreferFun() {
        let events = [
            event("A treaty is signed.", 1800, page("Treaty")),
            event("Troops invade the city.", 1940, page("Invasion")),
            event("The first television broadcast.", 1936, page("Television", noPicture: true)),
            event("Walt Disney World opens.", 1971, page("Walt Disney World")),
            event("A levy is imposed.", 2003, page("Levy")),
        ]
        let picks = OnThisDay.choose(events, date: date)
        // The opening with its picture, then the first broadcast without one, then a dry one: the other dry one scores
        // no more than 1 and goes, since three are left without it.
        #expect(picks.prefix(2).map(\.year) == [1971, 1936])
        #expect(picks.count == 3)
    }

    @Test("items scoring 1 or less go while at least three others are left")
    func lowScoresGo() {
        let good = (1...3).map { event("A museum opens, number \($0).", 1900 + 10 * $0, page("Museum \($0)")) }
        let dull = (1...3).map { event("Something happened, number \($0).", 1960 + 10 * $0, page("Thing \($0)", noPicture: true)) }
        #expect(Set(OnThisDay.choose(good + dull, date: date).map(\.year)) == Set(good.map(\.year)))
        // With only two good ones, the best of the dull ones stays to make three.
        #expect(OnThisDay.choose(Array(good.prefix(2)) + dull, date: date).count == 3)
        #expect(OnThisDay.choose(Array(good.prefix(2)), date: date).count == 2)
    }

    @Test("no two picks from the same decade while there are others")
    func decades() {
        let sixties = (0...4).map { event("A museum opens, number \($0).", 1960 + $0, page("Sixties \($0)")) }
        let others = [
            event("A bridge opens.", 1932, page("Bridge", noPicture: true)),
            event("A garden opens.", 1890, page("Garden", noPicture: true)),
        ]
        let picks = OnThisDay.choose(sixties + others, date: date)
        #expect(picks.count == 5)
        // The best of the sixties first, then the garden and the bridge, and more sixties only to make up five.
        #expect(picks[0].year >= 1960)
        #expect(picks[1..<3].map(\.year) == [1890, 1932])
        #expect(picks.dropFirst(3).allSatisfy { $0.year >= 1960 })
        // A decade the curated list already has is avoided by the full one's picks too.
        let taken = [OnThisDayPick(year: 1965, text: "", title: "", url: "")]
        let more = OnThisDay.choose(sixties + others, date: date, max: 2, taken: taken)
        #expect(Set(more.map(\.year)) == [1932, 1890])
    }

    // MARK: Choosing for the day

    private var ties: [OnThisDayEvent] { (1...12).map { event("Item \($0) of the day.", 1800 + 10 * $0, page("Page \($0)")) } }

    @Test("the same date always gives the same picks, at most five")
    func sameDateSamePicks() {
        let a = OnThisDay.choose(ties, date: date)
        let b = OnThisDay.choose(ties, date: LocalDate(2026, 10, 1))
        #expect(a.count == 5)
        #expect(a == b)
    }

    @Test("ties are broken by the date, so another year can lead with another pick")
    func tiesByDate() {
        let leads = Set((0...10).map { OnThisDay.choose(ties, date: date.plusYears($0)).first!.year })
        #expect(leads.count > 1)
        #expect(OnThisDay.choose(ties, date: date) != OnThisDay.choose(ties, date: date.plusYears(1)))
    }

    @Test("the same moment told twice is picked once, also across the two lists")
    func sameMomentOnce() {
        let curated = event("Walt Disney World opened near Orlando.", 1971, page("Walt Disney World"), page("Orlando"))
        let again = event("Walt Disney World opens in Florida.", 1971, page("Florida"), page("Walt Disney World"))
        #expect(OnThisDay.choose([curated, again], date: date).count == 1)
        // The full list's telling is left out when the curated one has it.
        #expect(OnThisDay.choose([again], date: date, besides: [curated]).isEmpty)
        // The same article in another year is another moment.
        let later = event("Walt Disney World turns 25.", 1996, page("Walt Disney World"))
        #expect(OnThisDay.choose([later], date: date, besides: [curated]).count == 1)
    }

    @Test("an item without an article to link isn't picked")
    func needsALink() {
        let bare = OnThisDayEvent(year: 1900, text: "A museum opens.", pages: [])
        let blank = OnThisDayEvent(year: 1901, text: "A museum opens.", pages: [WikiPage(title: "", extract: "", url: "")])
        #expect(OnThisDay.choose([bare, blank], date: date).isEmpty)
    }

    // MARK: The subject and its picture

    @Test("the subject is the article named in the text, after any topic lead-in")
    func subject() {
        let apollo = event("Apollo program: NASA launches the unmanned Apollo 4 test spacecraft.", 1967,
                           page("Apollo program"), page("NASA"), page("Apollo 4"))
        // Not the topic in the lead-in: the first article the sentence itself names.
        #expect(OnThisDay.subject(apollo)?.title == "NASA")
        // A "(film)" note isn't in the text; the match is case-sensitive.
        let gone = event("Hattie McDaniel wins for Gone with the Wind.", 1940, page("African Americans"), page("Gone with the Wind (film)"))
        #expect(OnThisDay.subject(gone)?.title == "Gone with the Wind (film)")
        let lower = event("the nasa budget grows.", 1970, page("Budget"), page("NASA"))
        #expect(OnThisDay.subject(lower)?.title == "Budget")
        // None named: the first.
        #expect(OnThisDay.subject(event("A fight.", 1975, page("Joe Frazier"), page("Muhammad Ali")))?.title == "Joe Frazier")
    }

    @Test("a pick links its subject, and takes a photo from another of its articles when the subject has none")
    func pickLinksSubject() throws {
        let picks = OnThisDay.choose([
            event("Muhammad Ali defeats Joe Frazier in the Thrilla in Manila.", 1975,
                  page("Thrilla in Manila", pictures: nonFree("Thrilla_poster.jpg")), page("Joe Frazier", noPicture: true),
                  page("Muhammad Ali", pictures: photo("Ali.jpg"))),
        ], date: date)
        #expect(picks.count == 1)
        let pick = try #require(picks.first)
        #expect(pick.title == "Thrilla in Manila")
        #expect(pick.url == "https://en.wikipedia.org/wiki/Thrilla_in_Manila")
        let picture = try #require(pick.picture)
        #expect(picture.url.contains("/wikipedia/commons/") && picture.url.contains("Ali.jpg"))
        let textOnly = try #require(OnThisDay.choose([event("A first.", 1900, page("Words", noPicture: true))], date: date).first)
        #expect(textOnly.picture == nil)
        #expect(textOnly.title == "Words")
    }

    @Test("only free pictures from Commons, else words only")
    func onlyCommons() throws {
        #expect(OnThisDay.pictureOf(page: page(pictures: nonFree())) == nil)
        #expect(OnThisDay.pictureOf(event("The film premieres.", 1975, page("Film", pictures: nonFree()))) == nil)
        #expect(OnThisDay.isCommons(try #require(OnThisDay.pictureOf(page: page(pictures: photo()))).url))
    }

    @Test("a picture from an article about the same thing comes before the others")
    func relatedPictureFirst() throws {
        // ALH84001: the subject is "Allan Hills" (named in the text), which has no picture; the meteorite's own article
        // does, and comes before the general one about meteorites.
        let alh = event(
            "Researchers announced that the meteorite ALH84001, discovered in the Allan Hills, may contain evidence of life.", 1996,
            page("Meteorite", pictures: photo("Hoba.jpg")), page("Allan Hills 84001", pictures: photo("ALH84001.jpg")),
            page("Allan Hills", noPicture: true)
        )
        #expect(OnThisDay.subject(alh)?.title == "Allan Hills")
        #expect(try #require(OnThisDay.pictureOf(alh)).url.contains("ALH84001.jpg"))
    }

    @Test("a photo is preferred to a drawing, the subject's first")
    func photoOverDrawing() throws {
        let flag = page("Tuvalu", pictures: drawing("Flag_of_Tuvalu.svg"))
        let crowd = page("Funafuti", pictures: photo("Funafuti.jpg"))
        #expect(try #require(OnThisDay.pictureOf(event("Tuvalu becomes independent.", 1978, flag, crowd))).url.contains("Funafuti.jpg"))
        // With no photo anywhere, the subject's drawing.
        #expect(try #require(OnThisDay.pictureOf(event("Tuvalu becomes independent.", 1978, flag, page("Funafuti", noPicture: true)))).fromSvg)
        let portrait = page("Tuvalu", pictures: photo("Leader.jpg", 600, 800))
        #expect(try #require(OnThisDay.pictureOf(event("Tuvalu becomes independent.", 1978, portrait, crowd))).url.contains("Leader.jpg"))
    }

    @Test("a picture under 150 px on its shorter side isn't shown")
    func minimumSize() {
        #expect(OnThisDay.pictureOf(page: page(pictures: photo("Tiny.jpg", 400, 149))) == nil)
        #expect(OnThisDay.pictureOf(page: page(pictures: photo("Small.jpg", 400, 150)))?.height == 150)
    }

    @Test("landscape photos fill the frame, the rest are posters")
    func fillOrPoster() {
        #expect(OnThisDay.pictureOf(page: page(pictures: photo("Wide.jpg", 3264, 2448)))?.fill == true)
        #expect(OnThisDay.pictureOf(page: page(pictures: photo("Square.jpg", 1000, 1000)))?.fill == false)
        #expect(OnThisDay.pictureOf(page: page(pictures: photo("Portrait.jpg", 600, 800)))?.fill == false)
        #expect(OnThisDay.pictureOf(page: page(pictures: photo("Small.jpg", 500, 300)))?.fill == false) // under 400 px tall
        #expect(OnThisDay.pictureOf(page: page(pictures: drawing("Flag.svg", 1200, 600)))?.fill == false)
    }

    @Test("the picture is asked for at a size Wikimedia makes that suits the frame")
    func heroSize() throws {
        let base = "https://thumb.wikimedia.org/wikipedia/commons/thumb/a/ab"
        // Big enough: 960 px, with the feed's 330 px as the fallback.
        let big = try #require(OnThisDay.pictureOf(page: page(pictures: photo("X.jpg", 3264, 2448))))
        #expect(big.url == "\(base)/X.jpg/960px-X.jpg")
        #expect(big.fallbackUrl == "\(base)/X.jpg/330px-X.jpg")
        // A smaller photo: the original itself.
        #expect(OnThisDay.pictureOf(page: page(pictures: photo("Y.jpg", 800, 600)))?.url == "https://upload.wikimedia.org/wikipedia/commons/a/ab/Y.jpg")
        // A drawing: rendered at 500 px.
        #expect(OnThisDay.pictureOf(page: page(pictures: drawing("Flag.svg", 600, 300)))?.url.hasSuffix("/500px-Flag.svg.png") == true)
        // An original that can't be shown as itself (a TIFF): the largest standard width under it.
        let tiff = Pictures(thumbnail: WikiImage(url: "\(base)/Z.tif/330px-Z.tif.jpg", width: 330, height: 248),
                            original: WikiImage(url: "https://upload.wikimedia.org/wikipedia/commons/a/ab/Z.tif", width: 800, height: 600))
        #expect(OnThisDay.pictureOf(page: page(pictures: tiff))?.url == "\(base)/Z.tif/500px-Z.tif.jpg")
    }

    @Test("the picture's page on Commons, for its author and licence")
    func commonsPage() {
        #expect(OnThisDay.commonsFilePage("https://thumb.wikimedia.org/wikipedia/commons/thumb/d/de/GBT_May_2018.jpg/960px-GBT_May_2018.jpg?utm_source=x")
            == "https://commons.wikimedia.org/wiki/File:GBT_May_2018.jpg")
        #expect(OnThisDay.commonsFilePage("https://upload.wikimedia.org/wikipedia/commons/9/9c/Las_Vegas%2C_Mandalay_Bay.jpg?utm_source=x")
            == "https://commons.wikimedia.org/wiki/File:Las_Vegas%2C_Mandalay_Bay.jpg")
        #expect(OnThisDay.commonsFilePage("https://thumb.wikimedia.org/wikipedia/commons/thumb/3/38/Flag_of_Tuvalu.svg/500px-Flag_of_Tuvalu.svg.png")
            == "https://commons.wikimedia.org/wiki/File:Flag_of_Tuvalu.svg")
        #expect(OnThisDay.commonsFilePage("https://upload.wikimedia.org/wikipedia/en/9/98/Poster.jpg") == nil)
    }

    // MARK: Text

    @Test("the text is tidied, without notes about the main page's picture")
    func tidied() {
        #expect(OnThisDay.cleanText("  Tuvalu adopted its national flag (pictured) on the day that the country\n gained its independence. ")
            == "Tuvalu adopted its national flag on the day that the country gained its independence.")
        #expect(OnThisDay.cleanText("The first political gathering of colonists (president pictured) in Mexican Texas convened.")
            == "The first political gathering of colonists in Mexican Texas convened.")
        // A note just before a comma or a full stop leaves no space behind.
        #expect(OnThisDay.cleanText("The comet (pictured) , seen from Earth (pictured) , was named .") == "The comet, seen from Earth, was named.")
    }

    @Test("a very long text keeps its first sentence or clause, not stopping at an abbreviation")
    func longText() {
        let long = "At the encouragement of John Muir, the U.S. Congress established Yosemite National Park in California. " +
            "It was the third national park in the country, after Yellowstone and Sequoia, and remains one of the most visited."
        #expect(OnThisDay.cleanText(long) == "At the encouragement of John Muir, the U.S. Congress established Yosemite National Park in California.")
        let clauses = "Sony and Philips launch the compact disc in Japan; on the same day, Sony releases the CDP-101, " +
            "the first compact disc player of its kind, which went on sale for the equivalent of several hundred dollars."
        #expect(OnThisDay.cleanText(clauses) == "Sony and Philips launch the compact disc in Japan.")
        let abbreviations = "At 9 a.m. local time, Gen. Motors Corp. and Apple Computer Inc. unveil a joint prototype that Prof. Smith built. " +
            "The machine was later shown at a fair, where it drew large crowds all week."
        #expect(OnThisDay.cleanText(abbreviations)
            == "At 9 a.m. local time, Gen. Motors Corp. and Apple Computer Inc. unveil a joint prototype that Prof. Smith built.")
        let short = "Walt Disney World opens near Orlando, Florida. It is an instant hit."
        #expect(OnThisDay.cleanText(short) == short)
    }

    @Test("years before the common era read as BC")
    func bc() {
        #expect(OnThisDay.formatYear(1969) == "1969")
        #expect(OnThisDay.formatYear(959) == "959")
        #expect(OnThisDay.formatYear(-331) == "331 BC")
    }

    @Test("how long ago, with BC years counted without a year 0")
    func yearsAgo() {
        #expect(OnThisDay.yearsAgo(1975, today: date) == "51 years ago")
        #expect(OnThisDay.yearsAgo(2025, today: date) == "last year")
        #expect(OnThisDay.yearsAgo(2026, today: date) == "this year")
        #expect(OnThisDay.yearsAgo(959, today: date) == "1,067 years ago")
        #expect(OnThisDay.yearsAgo(-331, today: date) == "2,356 years ago")
        #expect(OnThisDay.yearsAgo(-1, today: LocalDate(2025, 1, 1)) == "2,025 years ago")
    }
}
