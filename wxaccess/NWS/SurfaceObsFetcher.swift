import Foundation
import CoreLocation
import OSLog

// Fetches METAR surface observations from the Aviation Weather Center API.
// Returns stations within ~3° of the given radar site.

final class SurfaceObsFetcher: @unchecked Sendable {
    static let shared = SurfaceObsFetcher()

    private let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "SurfaceObsFetcher")
    private let session: URLSession = {
        var cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    func fetchObs(near site: NEXRADSite) async -> [SurfaceObs] {
        let lat = site.coordinate.latitude
        let lon = site.coordinate.longitude
        let delta = 3.0
        let bbox = "\(lon - delta),\(lat - delta),\(lon + delta),\(lat + delta)"
        let urlStr = "https://aviationweather.gov/api/data/metar?format=json&bbox=\(bbox)"
        guard let url = URL(string: urlStr) else {
            logger.error("Invalid METAR URL for site \(site.icao)")
            return []
        }
        do {
            let (data, _) = try await session.data(from: url)
            return try parseJSON(data: data)
        } catch {
            logger.error("Surface obs fetch failed for \(site.icao): \(error)")
            return []
        }
    }

    // MARK: - JSON decoding

    private struct METARRecord: Decodable {
        let station_id:          String?
        let temp_c:              Float?
        let dewpoint_c:          Float?
        let wind_dir_degrees:    Int?
        let wind_speed_kt:       Int?
        let altim_in_hg:         Float?
        let sky_condition:       [SkyLayer]?
        let flight_category:     String?
        let latitude:            Double?
        let longitude:           Double?
        let observation_time:    String?

        struct SkyLayer: Decodable { let sky_cover: String? }
    }

    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseJSON(data: Data) throws -> [SurfaceObs] {
        let records = try JSONDecoder().decode([METARRecord].self, from: data)
        return records.compactMap { r in
            guard let stationId = r.station_id,
                  let lat = r.latitude,
                  let lon = r.longitude else { return nil }
            let topSky  = r.sky_condition?.last?.sky_cover ?? "CLR"
            let cat     = SurfaceObs.FlightCategory(rawValue: r.flight_category ?? "") ?? .unknown
            let obsTime = r.observation_time.flatMap { Self.iso8601.date(from: $0) } ?? .now
            return SurfaceObs(
                id:              stationId,
                stationId:       stationId,
                coordinate:      CLLocationCoordinate2D(latitude: lat, longitude: lon),
                tempC:           r.temp_c,
                dewpointC:       r.dewpoint_c,
                windDirDeg:      r.wind_dir_degrees,
                windSpeedKt:     r.wind_speed_kt,
                altimInHg:       r.altim_in_hg,
                skyCondition:    topSky,
                flightCategory:  cat,
                observationTime: obsTime
            )
        }
    }
}
