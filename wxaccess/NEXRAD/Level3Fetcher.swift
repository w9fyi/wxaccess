import Foundation
import OSLog

// Fetches NEXRAD Level 3 products from Unidata THREDDS (migrated from dead S3 bucket).
// The former unidata-nexrad-level3 S3 bucket only retains data from 2020; THREDDS
// provides the same NIDS format with 14-day rolling retention and free HTTP access.
//
// THREDDS uses 3-letter site codes (KEWX → EWX — drop the leading character).
// Catalog: https://thredds.ucar.edu/thredds/catalog/nexrad/level3/{MNEMONIC}/{site}/{YYYYMMDD}/catalog.xml
// Download: https://thredds.ucar.edu/thredds/fileServer/{urlPath}
// Filename: Level3_{site}_{MNEMONIC}_{YYYYMMDD}_{HHMM}.nids

final class Level3Fetcher: @unchecked Sendable {
    static let shared = Level3Fetcher()

    private let threddsBase = "https://thredds.ucar.edu/thredds"
    private let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "Level3Fetcher")
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    // Returns up to `limit` most-recent scans for a site + product.
    // Searches today and yesterday so scans near midnight UTC are never missed.
    func listScans(site: NEXRADSite, product: Level3ProductCode,
                   limit: Int = 20) async throws -> [Level3ScanEntry] {
        let site3 = String(site.icao.dropFirst())   // "KEWX" → "EWX"
        let cal   = Calendar(identifier: .gregorian)
        var entries: [Level3ScanEntry] = []

        for daysAgo in 0..<2 {
            guard let date = cal.date(byAdding: .day, value: -daysAgo, to: .now) else { continue }
            let comps    = cal.dateComponents(in: .gmt, from: date)
            let yyyymmdd = String(format: "%04d%02d%02d", comps.year!, comps.month!, comps.day!)

            guard let url = URL(string:
                "\(threddsBase)/catalog/nexrad/level3/\(product.mnemonic)/\(site3)/\(yyyymmdd)/catalog.xml")
            else { continue }

            guard let (xmlData, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse, http.statusCode == 200
            else { continue }

            let dayEntries = parseThreddsCatalog(xmlData: xmlData, site: site, product: product)
            entries.append(contentsOf: dayEntries)
            if entries.count >= limit { break }
        }

        guard !entries.isEmpty else { throw URLError(.fileDoesNotExist) }
        return Array(entries.sorted { $0.scanTime > $1.scanTime }.prefix(limit))
    }

    func download(entry: Level3ScanEntry) async throws -> Data {
        guard let url = URL(string: "\(threddsBase)/fileServer/\(entry.id)") else {
            throw URLError(.badURL)
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            return data
        } catch {
            logger.error("Level 3 download failed for \(entry.fileName): \(error)")
            throw error
        }
    }

    // MARK: - THREDDS InvCatalog XML parser

    private func parseThreddsCatalog(xmlData: Data, site: NEXRADSite,
                                      product: Level3ProductCode) -> [Level3ScanEntry] {
        let parser = Level3CatalogParser(site: site, product: product)
        let xp     = XMLParser(data: xmlData)
        xp.delegate = parser
        xp.parse()
        return parser.entries.sorted { $0.scanTime > $1.scanTime }
    }
}

// MARK: - Scan entry

struct Level3ScanEntry: Sendable, Identifiable, Hashable {
    let id: String                  // THREDDS urlPath, e.g. "nexrad/level3/EET/EWX/20260523/Level3_EWX_EET_20260523_2356.nids"
    let site: NEXRADSite
    let product: Level3ProductCode
    let scanTime: Date
    let fileName: String
}

// MARK: - XMLParserDelegate

private final class Level3CatalogParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    let site: NEXRADSite
    let product: Level3ProductCode
    var entries: [Level3ScanEntry] = []

    init(site: NEXRADSite, product: Level3ProductCode) {
        self.site = site; self.product = product
    }

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
        entries.append(Level3ScanEntry(id: urlPath, site: site, product: product,
                                       scanTime: date, fileName: name))
    }

    // Filename format: Level3_EWX_EET_20260523_2356.nids
    private func dateFromFilename(_ name: String) -> Date? {
        guard name.hasSuffix(".nids") else { return nil }
        let parts = name.dropLast(5).split(separator: "_")
        guard parts.count >= 5 else { return nil }
        let dateStr = String(parts[parts.count - 2]) + String(parts[parts.count - 1])
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMddHHmm"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.date(from: dateStr)
    }
}
