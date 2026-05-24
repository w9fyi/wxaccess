import Foundation
import CoreLocation
import OSLog

final class SPCStormReportFetcher: @unchecked Sendable {
    static let shared = SPCStormReportFetcher()

    private let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "SPCStormReports")
    private let session: URLSession = {
        var cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    func fetchReports() async -> [SPCStormReport] {
        async let tornadoes = fetch(type: "torn")
        async let hail      = fetch(type: "hail")
        async let wind      = fetch(type: "wind")
        return await tornadoes + hail + wind
    }

    private func fetch(type: String) async -> [SPCStormReport] {
        let urlStr = "https://www.spc.noaa.gov/climo/reports/today_filtered_\(type).csv"
        guard let url = URL(string: urlStr) else {
            logger.error("Invalid storm report URL for type \(type)")
            return []
        }
        let data: Data
        do {
            (data, _) = try await session.data(from: url)
        } catch {
            logger.error("Storm reports fetch failed (\(type)): \(error)")
            return []
        }
        guard let text = String(data: data, encoding: .utf8) else {
            logger.error("Non-UTF8 storm report data for type \(type)")
            return []
        }

        var reports: [SPCStormReport] = []
        let lines = text.components(separatedBy: "\n").dropFirst()  // skip header row
        for line in lines {
            let fields = csvSplit(line)
            guard fields.count >= 7 else { continue }
            let timeStr  = fields[0].trimmingCharacters(in: .whitespaces)
            let col1     = fields[1].trimmingCharacters(in: .whitespaces)
            let location = fields[2].trimmingCharacters(in: .whitespaces)
            let county   = fields[3].trimmingCharacters(in: .whitespaces)
            let state    = fields[4].trimmingCharacters(in: .whitespaces)
            guard let lat = Double(fields[5].trimmingCharacters(in: .whitespaces)),
                  let lon = Double(fields[6].trimmingCharacters(in: .whitespaces)),
                  abs(lat) > 0.001 || abs(lon) > 0.001 else { continue }
            let comments = fields.count > 7 ? fields[7].trimmingCharacters(in: .whitespaces) : ""

            let kind: SPCStormReport.Kind
            switch type {
            case "torn": kind = .tornado(fScale: col1.isEmpty ? "EF?" : col1)
            case "hail": kind = .hail(sizeInches: Float(col1) ?? 0)
            default:     kind = .wind(speedMph: Int(col1) ?? 0)
            }

            reports.append(SPCStormReport(
                id: "\(type)-\(timeStr)-\(lat)-\(lon)",
                time: timeStr,
                location: location,
                county: county,
                state: state,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                comments: comments,
                kind: kind
            ))
        }
        return reports
    }

    private func csvSplit(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" { inQuotes.toggle() }
            else if ch == "," && !inQuotes { fields.append(current); current = "" }
            else { current.append(ch) }
        }
        fields.append(current)
        return fields
    }
}
