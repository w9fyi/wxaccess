import Foundation
import CoreLocation
import OSLog

final class SPCMesoscaleDiscussionFetcher: @unchecked Sendable {
    static let shared = SPCMesoscaleDiscussionFetcher()

    private let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "SPCMDFetcher")
    private let session: URLSession = {
        var cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    func fetchDiscussions() async -> [SPCMesoscaleDiscussion] {
        guard let url = URL(string: "https://www.spc.noaa.gov/products/md/ActiveMD.geojson") else {
            logger.error("Invalid SPC mesoscale discussion URL")
            return []
        }
        do {
            let (data, _) = try await session.data(from: url)
            return try parse(data: data)
        } catch {
            logger.error("SPC mesoscale discussions fetch failed: \(error)")
            return []
        }
    }

    // MARK: - Decoding

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
        let mdnumber: Int?
        let issued: String?
        let expired: String?
        let concerning: String?
        let affected: String?
    }

    // MD timestamps come in two flavours: full ISO-8601 and "YYYY-MM-DDThh:mmZ"
    nonisolated(unsafe) private static let iso8601Full: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    nonisolated(unsafe) private static let iso8601Short: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mmz"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private func parseDate(_ s: String?) -> Date? {
        guard let s else { return nil }
        return Self.iso8601Full.date(from: s) ?? Self.iso8601Short.date(from: s)
    }

    private func parse(data: Data) throws -> [SPCMesoscaleDiscussion] {
        let root = try JSONDecoder().decode(Root.self, from: data)
        return root.features.compactMap { feature in
            let p = feature.properties
            guard let number  = p.mdnumber,
                  let issued  = parseDate(p.issued),
                  let expires = parseDate(p.expired) else { return nil }

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
                concerning: p.concerning ?? "",
                affected:   p.affected   ?? "",
                polygon:    polygon
            )
        }
        .filter(\.isActive)
        .sorted { $0.number > $1.number }
    }
}
