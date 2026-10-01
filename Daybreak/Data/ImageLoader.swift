import UIKit

/// Loads On this day's pictures from Wikimedia: with the app's User-Agent (as Wikimedia asks), only answers that are
/// images, the feed's own thumbnail when the size asked for can't be had, a small memory cache and the system's disk
/// cache, and a failed address left alone for 10 minutes. One load per address at a time.
actor ImageLoader {
    static let shared = ImageLoader()

    private let session: URLSession
    private let memory = NSCache<NSString, UIImage>()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var failedAt: [String: Date] = [:]

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": Wikimedia.userAgent]
        config.urlCache = URLCache(memoryCapacity: 4 << 20, diskCapacity: 60 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
        memory.totalCostLimit = 24 << 20
    }

    /// The picture already in memory, if it is (so a pick seen before shows at once).
    nonisolated func cached(_ url: String) -> UIImage? { MemoryPeek.shared.image(url) }

    /// The picture at [url], or at [fallback] if that fails; nil when neither can be had.
    func load(_ url: String, fallback: String?) async -> UIImage? {
        if let image = await one(url) { return image }
        if let fallback { return await one(fallback) }
        return nil
    }

    private func one(_ url: String) async -> UIImage? {
        if let image = memory.object(forKey: url as NSString) { return image }
        if let at = failedAt[url], Date().timeIntervalSince(at) < 600 { return nil }
        if let task = inFlight[url] { return await task.value }
        let session = self.session
        let task = Task<UIImage?, Never> {
            guard let u = URL(string: url), let (data, response) = try? await session.data(from: u),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  (http.mimeType ?? "").hasPrefix("image/"),
                  let image = UIImage(data: data) else { return nil }
            // Decoded now, off the main thread, rather than on first draw.
            return await image.byPreparingForDisplay() ?? image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            memory.setObject(image, forKey: url as NSString, cost: cost)
            MemoryPeek.shared.set(image, for: url)
        } else {
            failedAt[url] = Date()
        }
        return image
    }
}

/// A synchronous peek at the last few pictures, for the first frame of a card.
final class MemoryPeek: @unchecked Sendable {
    static let shared = MemoryPeek()
    private let lock = NSLock()
    private var images: [(String, UIImage)] = []

    func image(_ url: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return images.first { $0.0 == url }?.1
    }

    func set(_ image: UIImage, for url: String) {
        lock.lock(); defer { lock.unlock() }
        images.removeAll { $0.0 == url }
        images.insert((url, image), at: 0)
        if images.count > 6 { images.removeLast() }
    }
}
