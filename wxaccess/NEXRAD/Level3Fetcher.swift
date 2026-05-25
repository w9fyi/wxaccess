import Foundation
import OSLog

// Fetches NEXRAD Level 3 products.
//
// Primary source — NWS TGFTP (tgftp.nws.noaa.gov):
//   Free, no auth, ~2-3 min latency. No catalog step: sn.last is always the newest scan.
//   URL: https://tgftp.nws.noaa.gov/SL.us008001/DF.of/DC.radar/DS.{ds}/SI.{site4}/sn.last
//   History: directory listing of sn.NNNN files (circular buffer, ~30 scans).
//
// Fallback — Unidata THREDDS:
//   Used only for products blocked on TGFTP (Digital VIL DS.134dv, 1-hr precip DS.65ohp).
//   Requires XML catalog parse per request; 14-day retention.

final class Level3Fetcher: @unchecked Sendable {
    static let shared = Level3Fetcher()

    private let tgftpBase   = "https://tgftp.nws.noaa.gov/SL.us008001/DF.of/DC.radar"
    private let threddsBase = "https://thredds.ucar.edu/thredds"
    private let logger      = Logger(subsystem: "net.ai5os.wxaccess", category: "Level3Fetcher")

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    // Returns up to `limit` most-recent scan entries, newest first.
    // Level3ScanEntry.id is a full download URL (TGFTP or THREDDS fileServer).
    func listScans(site: NEXRADSite, product: Level3ProductCode,
                   limit: Int = 20) async throws -> [Level3ScanEntry] {
        if let ds = product.tgftpDataStream {
            return try await listTGFTPScans(site: site, product: product, ds: ds, limit: limit)
        } else {
            return try await listThreddsScans(site: site, product: product, limit: limit)
        }
    }

    func download(entry: Level3ScanEntry) async throws -> Data {
        guard let url = URL(string: entry.id) else { throw URLError(.badURL) }
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

    // MARK: - TGFTP

    private func listTGFTPScans(site: NEXRADSite, product: Level3ProductCode,
                                 ds: String, limit: Int) async throws -> [Level3ScanEntry] {
        let site4 = site.icao.lowercased()

        if limit == 1 {
            // Fast path: single HEAD on sn.last — no directory parse needed.
            let urlStr = "\(tgftpBase)/DS.\(ds)/SI.\(site4)/sn.last"
            guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            let (_, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.fileDoesNotExist)
            }
            let scanTime = http.value(forHTTPHeaderField: "Last-Modified")
                .flatMap { parseHTTPDate($0) } ?? .now
            return [Level3ScanEntry(id: urlStr, site: site, product: product,
                                    scanTime: scanTime, fileName: "sn.last")]
        }

        // Multi-scan path: parse (seqNum, timestamp) pairs from the directory HTML, sort
        // by timestamp (TGFTP uses a circular buffer — sequence number order is NOT reliable
        // after a wrap, so timestamp sort is the only correct approach).
        // Timestamps are embedded in the HTML so no per-file HEAD requests are needed.
        let dirURL = URL(string: "\(tgftpBase)/DS.\(ds)/SI.\(site4)/")!
        let (htmlData, _) = try await session.data(from: dirURL)
        let html    = String(data: htmlData, encoding: .utf8) ?? ""
        let dirEntries = parseDirectoryEntries(from: html)
            .sorted { $0.scanTime > $1.scanTime }   // newest first
            .prefix(limit)

        guard !dirEntries.isEmpty else { throw URLError(.fileDoesNotExist) }

        return dirEntries.map { e in
            let seqStr = String(format: "%04d", e.seqNum)
            let urlStr = "\(tgftpBase)/DS.\(ds)/SI.\(site4)/sn.\(seqStr)"
            return Level3ScanEntry(id: urlStr, site: site, product: product,
                                   scanTime: e.scanTime, fileName: "sn.\(seqStr)")
        }
    }

    // Parses Apache-style directory listing HTML into (seqNum, scanTime) pairs.
    // Each row looks like:
    //   <a href="sn.0042">sn.0042</a></td><td align="right">25-May-2026 01:08  </td>
    // Timestamps are UTC. "sn.last" rows are excluded (digits-only filter).
    private struct DirEntry { let seqNum: Int; let scanTime: Date }

    private func parseDirectoryEntries(from html: String) -> [DirEntry] {
        var entries: [DirEntry] = []
        var search = html[...]
        let hrefPrefix = #"href="sn."#
        let dateParser = makeDirDateFormatter()

        while let hrefRange = search.range(of: hrefPrefix, options: .literal) {
            let afterHref = search[hrefRange.upperBound...]
            guard let endQuote = afterHref.firstIndex(of: "\"") else { break }

            let seqStr    = String(afterHref[afterHref.startIndex..<endQuote])
            search        = afterHref[endQuote...]

            guard seqStr.allSatisfy(\.isNumber), let seqNum = Int(seqStr) else { continue }

            // After the href, find the next table cell with the timestamp.
            // Format: </td><td align="right">24-May-2026 22:39  </td>
            guard let tdRange = search.range(of: #"align="right">"#, options: .literal) else { break }
            let afterTd = search[tdRange.upperBound...]
            guard let endTd = afterTd.range(of: "</td>") else { break }
            let dateStr = String(afterTd[afterTd.startIndex..<endTd.lowerBound]).trimmingCharacters(in: .whitespaces)
            search = afterTd[endTd.upperBound...]

            if let date = dateParser.date(from: dateStr) {
                entries.append(DirEntry(seqNum: seqNum, scanTime: date))
            }
        }
        return entries
    }

    private func makeDirDateFormatter() -> DateFormatter {
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "en_US_POSIX")
        fmt.timeZone   = TimeZone(identifier: "UTC")
        fmt.dateFormat = "dd-MMM-yyyy HH:mm"
        return fmt
    }

    private func parseHTTPDate(_ str: String) -> Date? {
        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "en_US_POSIX")
        fmt.timeZone   = TimeZone(identifier: "GMT")
        fmt.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return fmt.date(from: str)
    }

    // MARK: - THREDDS fallback

    private func listThreddsScans(site: NEXRADSite, product: Level3ProductCode,
                                   limit: Int) async throws -> [Level3ScanEntry] {
        let site3    = String(site.icao.dropFirst())
        let calendar = Calendar(identifier: .gregorian)
        var entries: [Level3ScanEntry] = []

        for daysAgo in 0..<2 {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: .now) else { continue }
            let comps    = calendar.dateComponents(in: .gmt, from: date)
            let yyyymmdd = String(format: "%04d%02d%02d", comps.year!, comps.month!, comps.day!)

            guard let url = URL(string:
                "\(threddsBase)/catalog/nexrad/level3/\(product.mnemonic)/\(site3)/\(yyyymmdd)/catalog.xml")
            else { continue }

            guard let (xmlData, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse, http.statusCode == 200
            else { continue }

            entries.append(contentsOf: parseThreddsCatalog(xmlData: xmlData, site: site, product: product))
            if entries.count >= limit { break }
        }

        guard !entries.isEmpty else { throw URLError(.fileDoesNotExist) }
        return Array(entries.sorted { $0.scanTime > $1.scanTime }.prefix(limit))
    }

    private func parseThreddsCatalog(xmlData: Data, site: NEXRADSite,
                                      product: Level3ProductCode) -> [Level3ScanEntry] {
        let parser = Level3CatalogParser(site: site, product: product, threddsBase: threddsBase)
        let xp     = XMLParser(data: xmlData)
        xp.delegate = parser
        xp.parse()
        return parser.entries.sorted { $0.scanTime > $1.scanTime }
    }
}

// MARK: - Scan entry

struct Level3ScanEntry: Sendable, Identifiable, Hashable {
    let id: String              // Full download URL (TGFTP or THREDDS fileServer)
    let site: NEXRADSite
    let product: Level3ProductCode
    let scanTime: Date
    let fileName: String
}

// MARK: - THREDDS XML parser

private final class Level3CatalogParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    let site: NEXRADSite
    let product: Level3ProductCode
    let threddsBase: String
    var entries: [Level3ScanEntry] = []

    init(site: NEXRADSite, product: Level3ProductCode, threddsBase: String) {
        self.site = site; self.product = product; self.threddsBase = threddsBase
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
        let downloadURL = "\(threddsBase)/fileServer/\(urlPath)"
        entries.append(Level3ScanEntry(id: downloadURL, site: site, product: product,
                                       scanTime: date, fileName: name))
    }

    private func dateFromFilename(_ name: String) -> Date? {
        guard name.hasSuffix(".nids") else { return nil }
        let parts = name.dropLast(5).split(separator: "_")
        guard parts.count >= 5 else { return nil }
        let dateStr = String(parts[parts.count - 2]) + String(parts[parts.count - 1])
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMddHHmm"
        fmt.timeZone   = TimeZone(identifier: "UTC")
        return fmt.date(from: dateStr)
    }
}
