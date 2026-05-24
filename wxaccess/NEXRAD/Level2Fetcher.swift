import Foundation
import OSLog

// Fetches NEXRAD Level 2 scan files from NOAA's public AWS S3 bucket.
// Bucket:  noaa-nexrad-level2  (requester-pays=false, anonymous access OK)
// URL pattern:
//   https://noaa-nexrad-level2.s3.amazonaws.com/{YYYY}/{MM}/{DD}/{ICAO}/{ICAO}{YYYYMMDD}_{HHMMSS}_V06

final class Level2Fetcher: @unchecked Sendable {
    static let shared = Level2Fetcher()

    private let base = "https://noaa-nexrad-level2.s3.amazonaws.com"
    private let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "Level2Fetcher")
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 120
        return URLSession(configuration: cfg)
    }()

    // MARK: - List scans

    /// Returns the most recent scans for a site on today's date (up to 20).
    func listScans(site: NEXRADSite, date: Date = .now) async throws -> [ScanEntry] {
        let cal  = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: .gmt, from: date)
        let yyyy = String(format: "%04d", comps.year!)
        let mm   = String(format: "%02d", comps.month!)
        let dd   = String(format: "%02d", comps.day!)
        let prefix = "\(yyyy)/\(mm)/\(dd)/\(site.icao)/"

        guard let listURL = URL(string: "\(base)?prefix=\(prefix)&list-type=2") else {
            throw URLError(.badURL)
        }
        let (xmlData, _) = try await session.data(from: listURL)
        return try parseS3Listing(xmlData: xmlData, site: site)
    }

    // MARK: - Download

    func download(entry: ScanEntry) async throws -> Data {
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
            logger.error("Level 2 download failed for \(entry.fileName): \(error)")
            throw error
        }
    }

    // MARK: - S3 XML listing parser

    private func parseS3Listing(xmlData: Data, site: NEXRADSite) throws -> [ScanEntry] {
        let parser = S3ListingParser(site: site)
        let xmlParser = XMLParser(data: xmlData)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.entries.sorted { $0.scanTime > $1.scanTime }  // newest first
    }
}

// MARK: - XMLParserDelegate for S3 ListObjectsV2 response

private final class S3ListingParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    let site: NEXRADSite
    var entries: [ScanEntry] = []
    private var currentKey = ""
    private var inKey = false

    init(site: NEXRADSite) { self.site = site }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if elementName == "Key" { inKey = true; currentKey = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inKey { currentKey += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        guard elementName == "Key" else { return }
        inKey = false
        // Key looks like: 2024/05/17/KEWX/KEWX20240517_120345_V06
        // or with MDM suffix: …_V06.gz (skip compressed variants for now)
        let key = currentKey
        guard key.hasSuffix("_V06") || key.hasSuffix("_V08") else { return }
        guard let date = dateFromKey(key) else { return }
        let entry = ScanEntry(id: key, site: site, scanTime: date, fileName: String(key.split(separator: "/").last ?? ""))
        entries.append(entry)
    }

    // Filename component: KEWX20240517_120345_V06
    private func dateFromKey(_ key: String) -> Date? {
        guard let filename = key.split(separator: "/").last.map(String.init) else { return nil }
        // filename = ICAO + YYYYMMDD + _ + HHMMSS + _ + Vxx
        let body = filename.dropFirst(4)  // drop ICAO
        let parts = body.split(separator: "_")
        guard parts.count >= 2 else { return nil }
        let dateStr = String(parts[0]) + String(parts[1])  // "YYYYMMDDHHMMSS"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: dateStr)
    }
}
