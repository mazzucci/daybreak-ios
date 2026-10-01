import Foundation

/// Wikipedia's lists of what happened on a date: the curated few, or every event it knows.
enum OnThisDayFeed: String, Sendable {
    case selected
    case events
}

enum Wikimedia {
    /// Who's calling, as Wikimedia asks every client to say, with a way to reach the project. Sent on the feed and
    /// on the pictures.
    static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Daybreak/\(version) (https://github.com/mazzucci/Daybreak)"
    }()

    static let base = "https://en.wikipedia.org/api/rest_v1/feed/onthisday"

    static func url(_ feed: OnThisDayFeed, month: Int, day: Int) -> URL {
        URL(string: String(format: "%@/%@/%02d/%02d", base, feed.rawValue, month, day))!
    }

    /// English Wikipedia's "On this day" feed (free, no key, CC BY-SA). The request carries only the month and day.
    static func events(month: Int, day: Int, feed: OnThisDayFeed, session: URLSession = .shared) async throws -> [OnThisDayEvent] {
        var request = URLRequest(url: url(feed, month: month, day: day), timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError("Wikipedia returned HTTP \(http.statusCode)")
        }
        // Half a megabyte for the full list: parsed off the main thread.
        return try await Task.detached(priority: .utility) { try parseOnThisDay(data, feed: feed) }.value
    }
}

/// The [feed]'s items: each one's year, text and the ordinary articles it links (a disambiguation page or one without
/// a link is left out). An item that doesn't parse is skipped rather than losing the rest.
func parseOnThisDay(_ data: Data, feed: OnThisDayFeed) throws -> [OnThisDayEvent] {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let items = root[feed.rawValue] as? [Any] else { return [] }
    return items.compactMap { item in
        guard let o = item as? [String: Any], let year = (o["year"] as? NSNumber)?.intValue, let text = o["text"] as? String
        else { return nil }
        let pages = (o["pages"] as? [Any] ?? []).compactMap { ($0 as? [String: Any]).flatMap(parsePage) }
        return OnThisDayEvent(year: year, text: text, pages: pages)
    }
}

func parseOnThisDay(_ json: String, feed: OnThisDayFeed) throws -> [OnThisDayEvent] {
    try parseOnThisDay(Data(json.utf8), feed: feed)
}

private func parsePage(_ o: [String: Any]) -> WikiPage? {
    if (o["type"] as? String ?? "standard") != "standard" { return nil }
    let urls = o["content_urls"] as? [String: Any]
    let mobile = (urls?["mobile"] as? [String: Any])?["page"] as? String ?? ""
    let url = mobile.isBlank ? (urls?["desktop"] as? [String: Any])?["page"] as? String ?? "" : mobile
    if url.isBlank { return nil }
    let normalized = (o["titles"] as? [String: Any])?["normalized"] as? String ?? ""
    let title = normalized.isBlank ? (o["title"] as? String ?? "").replacingOccurrences(of: "_", with: " ") : normalized
    if title.isBlank { return nil }
    return WikiPage(
        title: title,
        extract: o["extract"] as? String ?? "",
        url: url,
        thumbnail: parseImage(o["thumbnail"]),
        original: parseImage(o["originalimage"])
    )
}

private func parseImage(_ v: Any?) -> WikiImage? {
    guard let o = v as? [String: Any], let source = o["source"] as? String, !source.isBlank else { return nil }
    return WikiImage(url: source, width: (o["width"] as? NSNumber)?.intValue ?? 0, height: (o["height"] as? NSNumber)?.intValue ?? 0)
}
