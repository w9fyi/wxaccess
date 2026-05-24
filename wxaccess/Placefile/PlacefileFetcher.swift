import Foundation
import OSLog

// Fetches and caches placefiles from remote URLs.
// Refreshes each placefile after its RefreshSeconds window elapses.
final class PlacefileFetcher: @unchecked Sendable {
    static let shared = PlacefileFetcher()

    private let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "PlacefileFetcher")
    private let session: URLSession = {
        var cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    private let parser = PlacefileParser()

    // Fetch a single placefile from a URL, returning nil on any error.
    func fetch(url: URL) async -> Placefile? {
        var request = URLRequest(url: url)
        request.setValue("wxaccess/0.1 (net.ai5os.wxaccess; w9fyi@me.com)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await session.data(for: request)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                logger.error("Non-text data from placefile URL \(url)")
                return nil
            }
            return parser.parse(text: text, sourceURL: url)
        } catch {
            logger.error("Placefile fetch failed for \(url): \(error)")
            return nil
        }
    }

    // Fetch all URLs concurrently, skipping failures.
    func fetchAll(urls: [URL]) async -> [Placefile] {
        await withTaskGroup(of: Placefile?.self) { group in
            for url in urls {
                group.addTask { [weak self] in await self?.fetch(url: url) }
            }
            var results: [Placefile] = []
            for await result in group {
                if let p = result { results.append(p) }
            }
            return results
        }
    }

    // Re-fetch only stale placefiles; return the merged list.
    func refresh(existing: [Placefile], urls: [URL]) async -> [Placefile] {
        let staleURLs = urls.filter { url in
            guard let cached = existing.first(where: { $0.sourceURL == url }) else { return true }
            return cached.isStale
        }
        let freshPlacefiles = await fetchAll(urls: staleURLs)
        // Replace stale entries, preserve fresh ones
        var merged = existing.filter { placefile in
            guard let url = placefile.sourceURL else { return false }
            return !staleURLs.contains(url)
        }
        merged.append(contentsOf: freshPlacefiles)
        return merged.sorted { ($0.title) < ($1.title) }
    }
}
