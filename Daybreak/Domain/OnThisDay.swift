import Foundation

/// An image on Wikimedia, as the feed describes it.
struct WikiImage: Hashable, Sendable {
    let url: String
    let width: Int
    let height: Int
}

/// One Wikipedia article an "On this day" item links to.
struct WikiPage: Hashable, Sendable {
    /// The readable title ("Thrilla in Manila").
    let title: String
    /// The article's opening paragraph, in plain text.
    let extract: String
    /// The article on the mobile site.
    let url: String
    /// About 330 px wide; nil for an article without a picture.
    var thumbnail: WikiImage? = nil
    /// The full-size picture (or, for a small one, the same thumbnail).
    var original: WikiImage? = nil
}

/// One item of Wikipedia's "On this day" feed: what happened in [year] (negative for BC) and the articles it links.
struct OnThisDayEvent: Hashable, Sendable {
    let year: Int
    let text: String
    let pages: [WikiPage]
}

/// A pick's picture, always a free one from Wikimedia Commons. [url] is the size the card asks for (see
/// [OnThisDay.heroUrl]) and [fallbackUrl] the feed's own thumbnail in case that size can't be had. [width] and
/// [height] are the original's, which decide how the card shows it; [fromSvg] marks a drawing rendered to PNG.
struct OnThisDayPicture: Hashable, Sendable, Codable {
    let url: String
    let fallbackUrl: String?
    let width: Int
    let height: Int
    let fromSvg: Bool

    /// A landscape photo fills the card's frame edge to edge; anything else (portraits, squares, flags, seals, maps)
    /// is shown whole as a "poster" over a blurred copy of itself, since cropping would cut it badly.
    var fill: Bool { !fromSvg && Double(width) >= Double(height) * 1.15 && min(width, height) >= 400 }

    /// The picture's page on Commons, with its author and licence.
    var filePage: String? { OnThisDay.commonsFilePage(url) }

    enum CodingKeys: String, CodingKey {
        case url
        case fallbackUrl = "fallback"
        case width, height
        case fromSvg = "svg"
    }
}

/// One of the day's picks, ready for the card: the [text] tidied up, the one article it's shown with (its [title]
/// and link), and a [picture] when there's a good free one.
struct OnThisDayPick: Hashable, Sendable, Codable {
    let year: Int
    let text: String
    let title: String
    let url: String
    var picture: OnThisDayPicture? = nil
}

/// Picks a few pleasant or interesting moments from Wikipedia's "On this day" feed, ported from Android's
/// domain/OnThisDay.kt: grim ones (violence, disasters, deaths, persecution and wars) are dropped, and the rest are
/// scored so that science, culture, sport, space, nature and milestones, firsts, openings and inventions, and anything
/// with a good picture, come first. Everything here is pure and tested.
enum OnThisDay {
    /// The card cycles through at most this many a day.
    static let maxPicks = 5
    /// With fewer survivors than this from the curated list, the full list of events is asked for too.
    static let minSelected = 3

    /// Words that make an item grim, matched case-insensitively as whole words. A hyphen counts as a word break, so
    /// "post-war" and "anti-war" are grim too. Checked in the item's text, in the titles of every article it links,
    /// and in the first sentence of the article it's shown with. ASCII only.
    private static let grimWords = Pattern.words(
        // Violence
        "kill", "kills", "killed", "killing", "killings", "killer", "killers",
        "massacre", "massacres", "massacred",
        "bomb", "bombs", "bombed", "bombing", "bombings", "bomber", "bombers", "atomic bomb",
        "attack", "attacks", "attacked", "attacking",
        "shooting", "shootings", "gunman", "gunmen", "gunfire", "stabbing", "stabbed",
        "executed", "execution", "executions", "beheaded", "hanged", "lynched", "lynching", "crucified", "burned",
        "assassinate", "assassinated", "assassination", "assassinations",
        "murder", "murders", "murdered", "murderer",
        "genocide", "genocides", "pogrom", "pogroms", "terrorist", "terrorists", "terrorism", "hostage", "hostages",
        "hijack", "hijacked", "hijacking", "kidnapped", "kidnapping",
        "riot", "riots", "stampede", "crush", "injured", "injuries", "wounded", "casualties", "fatalities", "victims",
        "dead", "tortured", "persecuted", "deported", "militants",
        // Oppression
        "nazi", "nazis", "holocaust", "fascist", "fascists", "concentration camp", "concentration camps",
        "slavery", "slave", "slaves", "enslaved", "suicide",
        // Disasters
        "disaster", "disasters", "crash", "crashes", "crashed",
        "earthquake", "earthquakes", "tsunami", "tsunamis", "famine", "famines",
        "epidemic", "epidemics", "pandemic", "plague", "explosion", "explosions", "explodes", "exploded",
        "sink", "sinks", "sank", "sunk", "sinking", "shipwreck", "shipwrecks", "shipwrecked",
        "hurricane", "typhoon", "cyclone", "tornado", "landslide", "flood", "floods", "flooding",
        // Weapons
        "nuclear test", "nuclear tests", "detonation", "detonate", "detonates", "detonated",
        // War
        "war", "wars", "warfare", "battle", "battles", "invasion", "invasions", "invade", "invades", "invaded",
        "troops", "coup", "coups", "siege", "besieged", "conquered", "occupation", "annexed", "annexation"
    )

    /// "The Great Fire of London", "the Great Boston Fire": a city's great fire, with or without its name between.
    private static let greatFire = Pattern(#"\bgreat\s+(?:[a-z]+\s+)?fire\b"#, ignoreCase: true)

    /// Death, only in the item's own text. Not "die", which is as often German or a film ("Die Hard").
    private static let death = Pattern.words("dies", "died", "dying", "death", "deaths")

    /// Names that would trip the list but aren't grim at all. Taken out before the list is checked.
    private static let harmless = Pattern.words(
        "star wars", "war of the worlds", "battle of the sexes", "cold war ends",
        "dead sea", "grateful dead", "day of the dead"
    )

    /// True when [event] is about violence, disaster, death, persecution or war, and shouldn't be on a cheerful Home.
    static func isGrim(_ event: OnThisDayEvent) -> Bool {
        let text = harmless.replace(event.text, with: "")
        if grim(text) || death.matches(text) { return true }
        let subject = subjectOf(event).map { firstSentence(event.pages[$0].extract) } ?? ""
        return (event.pages.map(\.title) + [subject]).contains { grim(harmless.replace($0, with: "")) }
    }

    private static func grim(_ s: String) -> Bool { grimWords.matches(s) || greatFire.matches(s) }

    /// What makes an item fun to read over breakfast, each worth [boost] once.
    private static let boosts: [Pattern] = [
        // Science and discovery, and inventions
        Pattern.words(
            "discover", "discovers", "discovered", "discovery", "scientist", "scientists", "scientific", "science",
            "telescope", "comet", "planet", "element", "vaccine", "fossil", "dinosaur", "experiment", "laboratory",
            "invent", "invents", "invented", "invention", "patent", "patented", "prototype", "scanner", "computer",
            "nobel", "physics", "chemistry", "meteorite"
        ),
        // Culture
        Pattern.words(
            "film", "films", "movie", "premiere", "premieres", "premiered", "album", "song", "single", "novel",
            "book", "published", "publishes", "opera", "ballet", "museum", "gallery", "painting", "art", "music",
            "musical", "concert", "theatre", "theater", "television", "broadcast", "disney", "comic", "cartoon",
            "flag", "academy award", "oscar"
        ),
        // Sport
        Pattern.words(
            "olympic", "olympics", "world cup", "world series", "championship", "champion", "record", "marathon",
            "match", "tournament", "baseball", "football", "boxing", "tennis", "cricket", "game"
        ),
        // Space and flight
        Pattern.words(
            "space", "spacecraft", "spaceflight", "nasa", "orbit", "orbits", "satellite", "astronaut", "astronauts",
            "rocket", "moon", "lunar", "apollo", "sputnik", "flies", "flight", "sound barrier"
        ),
        // Openings and beginnings
        Pattern.words(
            "open", "opens", "opened", "opening", "inaugurated", "unveiled", "unveils", "debut", "debuts",
            "launch", "launches", "launched", "founded", "railway", "bridge", "zoo", "university"
        ),
        // Nature and milestones
        Pattern.words(
            "national park", "park", "garden", "gardens", "island", "mountain", "summit", "expedition", "lighthouse",
            "canal", "tunnel", "tower", "cathedral", "independence", "independent", "legalised", "legalized",
            "suffrage", "right to vote"
        ),
    ]

    /// Firsts are fun, but "first" is a common word, so it's worth a little less than a category.
    private static let first = Pattern.words("first")

    /// Dry politics, law and unrest: fine, but not what the card is for.
    private static let dry = Pattern.words(
        "treaty", "parliament", "court", "tribunal", "constitution", "constitutional", "legislature", "legislative",
        "government", "political", "president", "minister", "chancellor", "election", "referendum", "party",
        "agency", "levy", "tax", "communist", "military", "sentenced", "abdicate",
        "police", "arrest", "arrested", "protest", "protests", "protesters", "strike", "ruled", "ruling",
        "deputation", "viceroy"
    )

    /// Words in a picture's file name that mean a logo or an emblem rather than a photo or a painting.
    private static let emblem = Pattern("logo|seal|emblem|coat_of_arms", ignoreCase: true)

    private static let goodPicture = 3
    private static let plainPicture = 1
    private static let boost = 2
    private static let firstBoost = 1
    private static let dryPenalty = 2
    /// At or under this, an item is dropped as long as at least [minSelected] better ones are left.
    private static let lowScore = 1

    /// How much the card wants [event]: 3 for a good picture (a photo or a painting) or 1 for a logo, seal, emblem or
    /// drawing; 2 for each kind of fun; 1 for a first; and 2 off for dry politics, law or unrest.
    static func score(_ event: OnThisDayEvent) -> Int {
        let text = event.text
        var score: Int
        if let picture = pictureOf(event) {
            score = picture.fromSvg || emblem.matches(fileName(picture.url) ?? "") ? plainPicture : goodPicture
        } else {
            score = 0
        }
        score += boosts.filter { $0.matches(text) }.count * boost
        if first.matches(text) { score += firstBoost }
        if dry.matches(text) { score -= dryPenalty }
        return score
    }

    /// The day's picks, best first, at most [max]:
    /// - items without an article to link are dropped, and so are the grim ones;
    /// - an item told twice (the same year, and an article in common) is kept once, and one already among [besides]
    ///   not at all;
    /// - the rest are ordered by [score], ties ordered by a shuffle seeded with [date] (Kotlin's generator, as on
    ///   Android), so the same day always gives the same picks;
    /// - items scoring 1 or less are dropped as long as at least 3 others are left;
    /// - no two picks are from the same decade (including those in [taken]) while there are others to choose.
    static func choose(
        _ events: [OnThisDayEvent],
        date: LocalDate,
        max: Int = maxPicks,
        besides: [OnThisDayEvent] = [],
        taken: [OnThisDayPick] = []
    ) -> [OnThisDayPick] {
        let linkable = events.filter { e in
            guard let s = subjectOf(e) else { return false }
            return !e.pages[s].title.isBlank && !e.pages[s].url.isBlank
        }
        var random = KotlinRandom(seed: Int64(date.epochDay))
        let shuffled = linkable.filter { !isGrim($0) }.kotlinShuffled(&random)
        // A stable sort, best first: the shuffle only breaks ties.
        let ranked = shuffled.enumerated()
            .map { (offset: $0.offset, event: $0.element, score: score($0.element)) }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
        var unique: [(event: OnThisDayEvent, score: Int)] = []
        for item in ranked where !(besides + unique.map(\.event)).contains(where: { sameMoment($0, item.event) }) {
            unique.append((item.event, item.score))
        }
        while unique.count > minSelected, let last = unique.last, last.score <= lowScore { unique.removeLast() }
        // One per decade first, then the best of the rest if that leaves too few, after them.
        var decades = Set(taken.map { decade($0.year) })
        var spreadIndices: [Int] = []
        for (i, item) in unique.enumerated() where decades.insert(decade(item.event.year)).inserted {
            if spreadIndices.count < max { spreadIndices.append(i) }
        }
        let extra = unique.indices.filter { !spreadIndices.contains($0) }.prefix(Swift.max(0, max - spreadIndices.count))
        return (spreadIndices + extra).map { pickOf(unique[$0].event) }
    }

    private static func decade(_ year: Int) -> Int { Int((Double(year) / 10).rounded(.down)) }

    /// The same moment, told twice: the same year, and an article in common.
    private static func sameMoment(_ a: OnThisDayEvent, _ b: OnThisDayEvent) -> Bool {
        a.year == b.year && a.pages.contains { p in b.pages.contains { $0.title == p.title } }
    }

    /// The index of the article an item is about, for its link and title: the first one whose title (without a
    /// "(film)" note) appears, with its capitals, in the text after any "Topic:" lead-in; else the first named
    /// anywhere; else the first.
    static func subjectIndex(_ event: OnThisDayEvent) -> Int? {
        let lead = leadIn.firstMatch(event.text) ?? ""
        let body = event.text.removingPrefix(lead)
        func firstIn(_ s: String) -> Int? {
            event.pages.firstIndex { page in
                let n = name(page)
                return !n.isBlank && s.contains(n)
            }
        }
        return firstIn(body) ?? firstIn(event.text) ?? (event.pages.isEmpty ? nil : 0)
    }

    private static func subjectOf(_ event: OnThisDayEvent) -> Int? { subjectIndex(event) }

    /// The article an item is about (see [subjectIndex]).
    static func subject(_ event: OnThisDayEvent) -> WikiPage? { subjectIndex(event).map { event.pages[$0] } }

    private static func name(_ page: WikiPage) -> String { disambiguation.replace(page.title, with: "") }

    private static let leadIn = Pattern(#"^[^.:]{1,60}:\s"#)
    private static let disambiguation = Pattern(#"\s*\([^()]*\)$"#)

    /// The picture an item is shown with: always from Commons, at least 150 px on its shorter side. A photo or
    /// painting from the subject's article first; else one from another of the item's articles, those about the same
    /// thing first; else a drawing (a flag, a seal) from the subject, then from the others; else none.
    static func pictureOf(_ event: OnThisDayEvent) -> OnThisDayPicture? {
        let subjectIndex = subjectOf(event)
        let subject = subjectIndex.map { event.pages[$0] }
        // After the subject, the articles about the same thing ("Allan Hills 84001" for "Allan Hills"), then the rest.
        let others = event.pages.indices.filter { $0 != subjectIndex }.map { event.pages[$0] }
        let related: (WikiPage) -> Bool = { p in
            guard let subject else { return false }
            return name(subject).contains(name(p)) || name(p).contains(name(subject))
        }
        let ordered = others.filter(related) + others.filter { !related($0) }
        let pictures = ([subject].compactMap { $0 } + ordered).compactMap(pictureOf(page:))
        return pictures.first { !$0.fromSvg } ?? pictures.first
    }

    /// [page]'s picture if it's a free one, big enough; nil otherwise.
    static func pictureOf(page: WikiPage) -> OnThisDayPicture? {
        guard let thumb = page.thumbnail, isCommons(thumb.url) else { return nil }
        let original = page.original ?? thumb
        if min(original.width, original.height) < minPictureSide { return nil }
        let svg = svgPattern.matches(thumb.url)
        let url = heroUrl(thumb, original, svg: svg)
        return OnThisDayPicture(url: url, fallbackUrl: thumb.url != url ? thumb.url : nil,
                                width: original.width, height: original.height, fromSvg: svg)
    }

    /// Smaller than this on its shorter side, a picture would only look blurry.
    private static let minPictureSide = 150

    private static let svgPattern = Pattern(#"\.svg(?:/|\.png|$|\?)"#, ignoreCase: true)
    private static let thumbWidth = Pattern(#"/(\d+)px-"#)
    private static let raster = Pattern(#"\.(?:jpe?g|png|webp)(?:\?|$)"#, ignoreCase: true)

    static func isCommons(_ url: String) -> Bool { url.contains("/wikipedia/commons/") }

    /// Wikimedia makes thumbnails only at standard widths and answers HTTP 400 for others.
    private static let thumbSteps = [3840, 1920, 1280, 960, 500, 330, 250, 120, 60, 40, 20]
    /// The card's frame is about a phone's width, so 960 px suits it.
    private static let heroWidth = 960
    /// The largest original shown as itself.
    private static let maxOriginal = 1280

    /// The picture's address at a size that suits the card's frame: an original at least 960 px wide at 960; a
    /// drawing at 500; a smaller JPEG, PNG or WebP as the original itself; anything else at the largest standard width
    /// no wider than the original; and the feed's own thumbnail when its address can't be resized.
    static func heroUrl(_ thumb: WikiImage, _ original: WikiImage, svg: Bool) -> String {
        if !thumbWidth.matches(thumb.url) { return thumb.url }
        func sized(_ width: Int) -> String { thumbWidth.replace(thumb.url, with: "/\(width)px-") }
        if original.width >= heroWidth { return sized(heroWidth) }
        if svg { return sized(500) }
        if isCommons(original.url) && !thumbWidth.matches(original.url) && raster.matches(original.url)
            && original.width <= maxOriginal {
            return original.url
        }
        return thumbSteps.first { $0 <= original.width }.map(sized) ?? thumb.url
    }

    /// The Commons page of the file at [url], a thumbnail's or the original's address; nil for any other address.
    static func commonsFilePage(_ url: String) -> String? {
        guard isCommons(url), let name = fileName(url) else { return nil }
        return "https://commons.wikimedia.org/wiki/File:\(name)"
    }

    private static let file = Pattern(#"/wikipedia/[a-z]+/(?:thumb/)?[0-9a-f]/[0-9a-f]{2}/([^/?#]+)"#)

    private static func fileName(_ url: String) -> String? { file.firstGroup(url) }

    private static func pickOf(_ event: OnThisDayEvent) -> OnThisDayPick {
        let page = subject(event)
        return OnThisDayPick(year: event.year, text: cleanText(event.text), title: page?.title ?? "",
                             url: page?.url ?? "", picture: pictureOf(event))
    }

    /// Past this the text keeps only its first sentence (or clause), when that alone says enough.
    private static let longText = 160
    private static let minSentence = 40

    /// Abbreviations that end in a full stop without ending the sentence ("U.S. Congress", "St. Pancras").
    private static let notAnEnd = Pattern(
        #"(?:\b[A-Z]|\b(?:St|Mt|Dr|Mr|Mrs|Jr|Sr|No|vs|c|ca|Co|Corp|Gen|Lt|Capt|Rev|Prof|Inc|Ltd)|\b[ap]\.m)$"#
    )
    private static let pictured = Pattern(#"\s*\([^()]*\bpictured\)"#)
    private static let spaces = Pattern(#"\s+"#)
    private static let spaceBeforeStop = Pattern(#"\s+([,.;:])"#)

    /// The item's text for the card: "(pictured)" notes dropped, spaces tidied, and a very long text cut to its first
    /// sentence or clause when that's long enough on its own.
    static func cleanText(_ text: String) -> String {
        let tidy = spaceBeforeStop.replace(spaces.replace(pictured.replace(text, with: ""), with: " "), with: "$1")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = tidy as NSString
        if ns.length <= longText { return tidy }
        guard let end = sentenceEnd(ns, from: minSentence, clauses: true) else { return tidy }
        return ns.substring(to: end).trimmingTrailingWhitespace + "."
    }

    /// An article's first sentence ("Jerome David Salinger was an American writer."), for the grim check.
    static func firstSentence(_ text: String) -> String {
        let ns = text as NSString
        guard let end = sentenceEnd(ns, from: 0, clauses: false) else { return text }
        return ns.substring(to: end + 1)
    }

    /// Where the first sentence (or, with [clauses], clause) of [s] ends, from [from] on; nil if it doesn't.
    private static func sentenceEnd(_ s: NSString, from: Int, clauses: Bool) -> Int? {
        let space = unichar(32), dot = unichar(46), semicolon = unichar(59)
        var i = from
        while i < s.length - 1 {
            let c = s.character(at: i)
            if s.character(at: i + 1) == space {
                if clauses && c == semicolon { return i }
                if c == dot && !notAnEnd.matches(s.substring(to: i)) { return i }
            }
            i += 1
        }
        return nil
    }

    /// "1969", or "331 BC" for the feed's negative years.
    static func formatYear(_ year: Int) -> String { year > 0 ? "\(year)" : "\(-year) BC" }

    /// How long ago [year] was in [today]'s year: "51 years ago", "last year", "this year", or "2,356 years ago" for
    /// 331 BC (there was no year 0).
    static func yearsAgo(_ year: Int, today: LocalDate) -> String {
        let years = year > 0 ? today.year - year : today.year - year - 1
        if years <= 0 { return "this year" }
        if years == 1 { return "last year" }
        return "\(groupedThousands(years)) years ago"
    }
}

/// A compiled regular expression with Java's semantics for the patterns used here (ICU and java.util.regex agree on
/// `\b`, `\s` and `$`).
struct Pattern: @unchecked Sendable {
    private let regex: NSRegularExpression

    init(_ pattern: String, ignoreCase: Bool = false) {
        // The patterns are constants, so a bad one is a programming error.
        regex = try! NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
    }

    /// Plain words and phrases (letters and spaces only) as one case-insensitive whole-word pattern.
    static func words(_ words: String...) -> Pattern {
        Pattern(#"\b(?:"# + words.map { $0.replacingOccurrences(of: " ", with: #"\s+"#) }.joined(separator: "|") + #")\b"#,
                ignoreCase: true)
    }

    func matches(_ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    func replace(_ s: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length),
                                       withTemplate: template)
    }

    func firstMatch(_ s: String) -> String? {
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) else { return nil }
        return (s as NSString).substring(with: m.range)
    }

    func firstGroup(_ s: String) -> String? {
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)),
              m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound else { return nil }
        return (s as NSString).substring(with: m.range(at: 1))
    }
}

extension String {
    /// Kotlin's `isBlank`: empty or only whitespace.
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var trimmingTrailingWhitespace: String {
        var s = self
        while let last = s.last, last.isWhitespace { s.removeLast() }
        return s
    }
}
