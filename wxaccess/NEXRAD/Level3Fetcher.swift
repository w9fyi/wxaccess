import Foundation
import OSLog

// Fetches NEXRAD Level 3 products from the Unidata public AWS S3 bucket.
// Bucket: unidata-nexrad-level3 (anonymous access OK, no requester-pays)
// Key format (flat): {ICAO}_{MNEMONIC}_{YYYY}_{MM}_{DD}_{HH}_{mm}_{SS}
// Example:           KEWX_N0Q_2024_05_17_12_03_45

final class Level3Fetcher: @unchecked Sendable {
    static let shared = Level3Fetcher()

    private let base = "https://unidata-nexrad-level3.s3.amazonaws.com"
    private let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "Level3Fetcher")
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    // Returns up to `limit` most-recent scans for a site + product.
    func listScans(site: NEXRADSite, product: Level3ProductCode,
                   limit: Int = 20) async throws -> [Level3ScanEntry] {
        // Flat prefix: "KEWX_N0Q_" matches all keys for that site+product
        let prefix = "\(site.icao)_\(product.mnemonic)_"
        guard let listURL = URL(string: "\(base)?prefix=\(prefix)&list-type=2") else {
            throw URLError(.badURL)
        }
        let (xmlData, _) = try await session.data(from: listURL)
        let entries = try parseS3Listing(xmlData: xmlData, site: site, product: product)
        return Array(entries.prefix(limit))
    }

    func download(entry: Level3ScanEntry) async throws -> Data {
        guard let url = URL(string: "\(base)/\(entry.id)") else {
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

    // MARK: - S3 XML listing

    private func parseS3Listing(xmlData: Data, site: NEXRADSite,
                                 product: Level3ProductCode) throws -> [Level3ScanEntry] {
        let parser = Level3S3Parser(site: site, product: product)
        let xmlParser = XMLParser(data: xmlData)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.entries.sorted { $0.scanTime > $1.scanTime }
    }
}

// MARK: - Scan entry

struct Level3ScanEntry: Sendable, Identifiable, Hashable {
    let id: String                  // S3 key, e.g. "KEWX/N0Q/KEWX_20240517_120345"
    let site: NEXRADSite
    let product: Level3ProductCode
    let scanTime: Date
    let fileName: String
}

// MARK: - XMLParserDelegate

private final class Level3S3Parser: NSObject, XMLParserDelegate, @unchecked Sendable {
    let site: NEXRADSite
    let product: Level3ProductCode
    var entries: [Level3ScanEntry] = []

    private var currentKey = ""
    private var inKey = false

    init(site: NEXRADSite, product: Level3ProductCode) {
        self.site = site
        self.product = product
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if elementName == "Key" { inKey = true; currentKey = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inKey { currentKey += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard elementName == "Key" else { return }
        inKey = false
        // Key format: KEWX_N0Q_2024_05_17_12_03_45  (8 underscore-delimited parts)
        let parts = currentKey.split(separator: "_")
        guard parts.count == 8,
              String(parts[0]) == site.icao,
              String(parts[1]) == product.mnemonic else { return }
        guard let date = dateFromParts(parts) else { return }
        entries.append(Level3ScanEntry(
            id: currentKey, site: site, product: product,
            scanTime: date, fileName: currentKey
        ))
    }

    // Parts: [ICAO, MNEMONIC, YYYY, MM, DD, HH, mm, SS]
    private func dateFromParts(_ parts: [Substring]) -> Date? {
        guard parts.count == 8 else { return nil }
        let dateStr = "\(parts[2])\(parts[3])\(parts[4])\(parts[5])\(parts[6])\(parts[7])"
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMddHHmmss"
        fmt.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)
        return fmt.date(from: dateStr)
    }
}
