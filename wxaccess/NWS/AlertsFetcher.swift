import Foundation
import CoreLocation
import OSLog

// Fetches active NWS watches/warnings/advisories from api.weather.gov.
// Documentation: https://www.weather.gov/documentation/services-web-api

final class AlertsFetcher: @unchecked Sendable {
    static let shared = AlertsFetcher()

    private let base = "https://api.weather.gov"
    private let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "AlertsFetcher")
    private let session: URLSession = {
        var cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    // Fetch all active alerts whose area overlaps a 400 km radius around the given coordinate.
    func fetchAlerts(near coordinate: CLLocationCoordinate2D) async throws -> [NWSAlert] {
        let urlStr = "\(base)/alerts/active?point=\(coordinate.latitude),\(coordinate.longitude)&status=actual&message_type=alert"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("wxaccess/0.1 (net.ai5os.wxaccess; w9fyi@me.com)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await session.data(for: request)
            return try parseGeoJSON(data: data)
        } catch {
            logger.error("NWS alerts fetch failed: \(error)")
            throw error
        }
    }

    // Fetch all active alerts for a specific NWS zone (e.g. "TXZ105")
    func fetchAlerts(zone: String) async throws -> [NWSAlert] {
        let urlStr = "\(base)/alerts/active/zone/\(zone)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("wxaccess/0.1 (net.ai5os.wxaccess; w9fyi@me.com)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        do {
            let (data, _) = try await session.data(for: request)
            return try parseGeoJSON(data: data)
        } catch {
            logger.error("NWS zone alerts fetch failed for \(zone): \(error)")
            throw error
        }
    }

    // MARK: - GeoJSON parsing

    private struct GeoJSONResponse: Decodable {
        let features: [Feature]
    }

    private struct Feature: Decodable {
        let id: String
        let geometry: Geometry?
        let properties: Properties
    }

    private struct Geometry: Decodable {
        let type: String
        let coordinates: [[[Double]]]?        // GeoJSON Polygon: array of rings (outer + holes)
    }

    private struct Properties: Decodable {
        let event: String
        let headline: String?
        let description: String?
        let instruction: String?
        let severity: String
        let urgency: String
        let effective: String
        let expires: String
        let affectedZones: [String]
        let senderName: String
    }

    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseGeoJSON(data: Data) throws -> [NWSAlert] {
        let response = try JSONDecoder().decode(GeoJSONResponse.self, from: data)
        return response.features.compactMap { feature in
            let p = feature.properties
            guard let effective = Self.iso8601.date(from: p.effective),
                  let expires   = Self.iso8601.date(from: p.expires) else { return nil }

            var polygon: [CLLocationCoordinate2D] = []
            if let geom = feature.geometry,
               geom.type == "Polygon",
               let rings = geom.coordinates,
               let ring = rings.first {
                polygon = ring.compactMap { pair in
                    guard pair.count == 2 else { return nil }
                    return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                }
            }

            return NWSAlert(
                id: feature.id,
                event: p.event,
                headline: p.headline ?? p.event,
                description: p.description ?? "",
                instruction: p.instruction ?? "",
                severity: NWSAlert.Severity(rawValue: p.severity.lowercased()) ?? .unknown,
                urgency: NWSAlert.Urgency(rawValue: p.urgency.lowercased()) ?? .unknown,
                effective: effective,
                expires: expires,
                affectedZones: p.affectedZones,
                polygon: polygon,
                senderName: p.senderName
            )
        }
        .filter(\.isActive)
        .sorted { $0.severity.sortOrder < $1.severity.sortOrder }
    }
}
