import Foundation
import CoreLocation
import OSLog

// Fetches active NWS Mesoscale Discussions via the NWS alerts API.
// The SPC-specific ActiveMD.geojson endpoint returned 404 as of 2026-05.
// NWS API endpoint: https://api.weather.gov/alerts/active?event=Mesoscale+Discussion

final class SPCMesoscaleDiscussionFetcher: @unchecked Sendable {
    static let shared = SPCMesoscaleDiscussionFetcher()

    private let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "SPCMDFetcher")
    private let session: URLSession = {
        var cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    func fetchDiscussions() async -> [SPCMesoscaleDiscussion] {
        guard let url = URL(string: "https://api.weather.gov/alerts/active?event=Mesoscale+Discussion") else {
            logger.error("Invalid NWS mesoscale discussion URL")
            return []
        }
        do {
            var req = URLRequest(url: url)
            req.setValue("wxaccess/1.1 (net.ai5os.wxaccess; w9fyi@me.com)", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await session.data(for: req)
            return try parse(data: data)
        } catch {
            logger.error("NWS mesoscale discussions fetch failed: \(error)")
            return []
        }
    }

    // MARK: - Decoding (NWS alerts API format)

    private struct Root: Decodable { let features: [Feature] }

    private struct Feature: Decodable {
        let geometry: Geometry?
        let properties: Properties
    }

    private struct Geometry: Decodable {
        let type: String
        let coordinates: [[[Double]]]?
    }

    private struct Properties: Decodable {
        let id: String?
        let areaDesc: String?
        let effective: String?
        let expires: String?
        let headline: String?
        let description: String?
    }

    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let iso8601NoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return Self.iso8601.date(from: s) ?? Self.iso8601NoFrac.date(from: s)
    }

    // Extract MD number from headline e.g. "Mesoscale Discussion 456 issued..."
    private func mdNumber(from headline: String?) -> Int? {
        guard let headline else { return nil }
        if let match = headline.range(of: #"Mesoscale Discussion (\d+)"#,
                                      options: .regularExpression) {
            let sub = headline[match]
            let digits = sub.filter(\.isNumber)
            return Int(digits)
        }
        return nil
    }

    // Extract "CONCERNING...XXX" line from NWS description text.
    private func concerning(from description: String?) -> String {
        guard let desc = description else { return "" }
        for line in desc.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("CONCERNING...") {
                return String(t.dropFirst("CONCERNING...".count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    private func parse(data: Data) throws -> [SPCMesoscaleDiscussion] {
        let root = try JSONDecoder().decode(Root.self, from: data)
        return root.features.compactMap { feature in
            let p = feature.properties
            guard let number  = mdNumber(from: p.headline),
                  let issued  = parseDate(p.effective),
                  let expires = parseDate(p.expires) else { return nil }

            var polygon: [CLLocationCoordinate2D] = []
            if let geom = feature.geometry,
               geom.type == "Polygon",
               let rings = geom.coordinates,
               let ring  = rings.first {
                polygon = ring.compactMap { pair in
                    guard pair.count == 2 else { return nil }
                    return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                }
            }

            return SPCMesoscaleDiscussion(
                id: "md-\(number)",
                number: number,
                issued: issued,
                expires: expires,
                concerning: concerning(from: p.description),
                affected:   p.areaDesc ?? "",
                polygon:    polygon
            )
        }
        .filter(\.isActive)
        .sorted { $0.number > $1.number }
    }
}
