import Foundation
import CoreLocation
import OSLog

// Fetches SPC categorical convective outlooks (Day 1, 2, 3) from the SPC GeoJSON endpoints.
// Endpoint pattern: https://www.spc.noaa.gov/products/outlook/day{N}otlk_cat.lyr.geojson
final class SPCOutlookFetcher: @unchecked Sendable {
    static let shared = SPCOutlookFetcher()

    private let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "SPCOutlookFetcher")
    private let session: URLSession = {
        var cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    private let base = "https://www.spc.noaa.gov/products/outlook"

    func fetchOutlooks() async -> [SPCOutlook] {
        await withTaskGroup(of: SPCOutlook?.self) { group in
            for day in 1...3 {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    do {
                        return try await fetchOutlook(day: day)
                    } catch {
                        logger.error("SPC Day \(day) outlook fetch failed: \(error)")
                        return nil
                    }
                }
            }
            var results: [SPCOutlook] = []
            for await result in group {
                if let r = result { results.append(r) }
            }
            return results.sorted { $0.day < $1.day }
        }
    }

    private func fetchOutlook(day: Int) async throws -> SPCOutlook {
        let urlStr = "\(base)/day\(day)otlk_cat.lyr.geojson"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("wxaccess/0.1 (net.ai5os.wxaccess; w9fyi@me.com)", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await session.data(for: request)
        return try parseGeoJSON(data: data, day: day)
    }

    // MARK: - GeoJSON parsing

    private struct FeatureCollection: Decodable {
        let features: [Feature]
    }

    private struct Feature: Decodable {
        let geometry: Geometry?
        let properties: Properties
    }

    private struct Geometry: Decodable {
        let type: String
        // Polygon:      [ring][point][lon,lat]
        // MultiPolygon: [polygon][ring][point][lon,lat]
        let coordinates: AnyCodable
    }

    private struct Properties: Decodable {
        let LABEL: String?      // "TSTM", "MRGL", "SLGT", "ENH", "MDT", "HIGH"
        let VALID_ISO: String?
        let EXPIRE_ISO: String?
    }

    // Decode coordinates as raw JSON and walk the structure manually since
    // Polygon and MultiPolygon have different nesting depths.
    private struct AnyCodable: Decodable {
        let value: Any
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let arr = try? c.decode([[[Double]]].self) {
                value = arr   // Polygon
            } else if let arr = try? c.decode([[[[Double]]]].self) {
                value = arr   // MultiPolygon
            } else {
                value = []
            }
        }
    }

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate,
                           .withColonSeparatorInTime, .withTimeZone]
        return f
    }()

    private func parseGeoJSON(data: Data, day: Int) throws -> SPCOutlook {
        let fc = try JSONDecoder().decode(FeatureCollection.self, from: data)
        var polygonDatas: [SPCOutlookPolygonData] = []

        for (idx, feature) in fc.features.enumerated() {
            guard let label = feature.properties.LABEL,
                  let category = SPCOutlook.Category(rawValue: label),
                  let geom = feature.geometry else { continue }

            let valid   = feature.properties.VALID_ISO.flatMap { Self.iso.date(from: $0) } ?? .now
            let expires = feature.properties.EXPIRE_ISO.flatMap { Self.iso.date(from: $0) } ?? .now

            let rings = extractRings(from: geom)
            guard !rings.isEmpty else { continue }

            for (ringIdx, ring) in rings.enumerated() {
                polygonDatas.append(SPCOutlookPolygonData(
                    id: "day\(day)-\(label)-\(idx)-\(ringIdx)",
                    day: day,
                    category: category,
                    rings: [ring],
                    valid: valid,
                    expires: expires
                ))
            }
        }

        return SPCOutlook(day: day, fetched: .now, polygons: polygonDatas)
    }

    // Returns one flat coordinate ring per polygon/multi-polygon ring.
    private func extractRings(from geom: Geometry) -> [[CLLocationCoordinate2D]] {
        if geom.type == "Polygon", let rings = geom.coordinates.value as? [[[Double]]] {
            return rings.map { coordsToCoordinates($0) }
        } else if geom.type == "MultiPolygon", let polys = geom.coordinates.value as? [[[[Double]]]] {
            return polys.flatMap { poly in poly.map { coordsToCoordinates($0) } }
        }
        return []
    }

    private func coordsToCoordinates(_ ring: [[Double]]) -> [CLLocationCoordinate2D] {
        ring.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }
}
