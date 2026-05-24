import Foundation
import OSLog

// Fetches NEXRAD Level 3 NST (Storm Tracking Information) from Unidata THREDDS.
//
// THREDDS uses 3-letter site codes (KEWX → EWX — drop the leading K/P/T).
// Catalog: https://thredds.ucar.edu/thredds/catalog/nexrad/level3/NST/{3-letter-site}/{YYYYMMDD}/catalog.xml
// Download: https://thredds.ucar.edu/thredds/fileServer/{urlPath}
// Filename: Level3_{3-letter-site}_NST_{YYYYMMDD}_{HHMM}.nids

final class SCITFetcher: @unchecked Sendable {
    static let shared = SCITFetcher()

    private let threddsBase = "https://thredds.ucar.edu/thredds"
    private let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "SCITFetcher")
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    // Returns the most recent NST scan for the given site, decoded into StormCells.
    func fetchLatest(site: NEXRADSite) async throws -> [StormCell] {
        let entry = try await fetchLatestEntry(site: site)
        let data  = try await download(entry: entry)
        return try SCITDecoder().decode(data: data, site: site)
    }

    // MARK: - Catalog listing

    private func fetchLatestEntry(site: NEXRADSite) async throws -> NST_ScanEntry {
        let site3 = String(site.icao.dropFirst())   // "KEWX" → "EWX"
        let cal   = Calendar(identifier: .gregorian)

        // Try today, then yesterday (scans near midnight UTC may only appear in yesterday's catalog).
        for daysAgo in 0..<2 {
            guard let date = cal.date(byAdding: .day, value: -daysAgo, to: .now) else { continue }
            let comps    = cal.dateComponents(in: .gmt, from: date)
            let yyyymmdd = String(format: "%04d%02d%02d", comps.year!, comps.month!, comps.day!)

            guard let url = URL(string:
                "\(threddsBase)/catalog/nexrad/level3/NST/\(site3)/\(yyyymmdd)/catalog.xml")
            else { continue }

            guard let (xmlData, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse, http.statusCode == 200
            else { continue }

            let entries = parseNSTCatalog(xmlData: xmlData, site: site)
            if let latest = entries.first { return latest }
        }
        throw URLError(.fileDoesNotExist)
    }

    // MARK: - Download

    private func download(entry: NST_ScanEntry) async throws -> Data {
        guard let url = URL(string: "\(threddsBase)/fileServer/\(entry.urlPath)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - THREDDS catalog parser

    private func parseNSTCatalog(xmlData: Data, site: NEXRADSite) -> [NST_ScanEntry] {
        let parser = NSTCatalogParser(site: site)
        let xp     = XMLParser(data: xmlData)
        xp.delegate = parser
        xp.parse()
        return parser.entries.sorted { $0.scanTime > $1.scanTime }
    }
}

// MARK: - Scan entry

private struct NST_ScanEntry {
    let urlPath: String     // THREDDS urlPath for HTTPServer
    let site: NEXRADSite
    let scanTime: Date
}

// MARK: - XMLParserDelegate

private final class NSTCatalogParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    let site: NEXRADSite
    var entries: [NST_ScanEntry] = []

    init(site: NEXRADSite) { self.site = site }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        guard elementName == "dataset",
              let name    = attributes["name"],
              let urlPath = attributes["urlPath"],
              name.hasSuffix(".nids"),
              !urlPath.isEmpty,
              let date = dateFromFilename(name)
        else { return }
        entries.append(NST_ScanEntry(urlPath: urlPath, site: site, scanTime: date))
    }

    // Filename format: Level3_EWX_NST_20260523_2356.nids
    private func dateFromFilename(_ name: String) -> Date? {
        guard name.hasSuffix(".nids") else { return nil }
        let parts = name.dropLast(5).split(separator: "_")  // drop ".nids"
        guard parts.count >= 5 else { return nil }
        // parts: ["Level3", site, "NST", YYYYMMDD, HHMM]
        let dateStr = String(parts[parts.count - 2]) + String(parts[parts.count - 1])  // "202605232356"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMddHHmm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.date(from: dateStr)
    }
}
