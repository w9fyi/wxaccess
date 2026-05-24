import Foundation
import CoreLocation

// State-machine parser for GRLevel3/AllisonHouse placefile format.
//
// Format reference: https://www.grlevelx.com/manuals/gis_data/gis_placefile.htm
//
// Key rules:
//   ; lines are comments
//   Color: R G B [A]        — sets current draw color, carries forward
//   Threshold: N            — display zoom threshold, ignored here
//   Title: text             — sets the placefile title
//   RefreshSeconds: N
//   Icon: lat,lon,angle,"tooltip",iconFile[,iconId]
//   Text: lat,lon,angle,"label"[,"tooltip"]
//   Line: width,style       — followed by lat,lon pairs, terminated by End:
//   Polygon:                — followed by lat,lon pairs, terminated by End:
//   Object: lat,lon         — groups child directives, terminated by End:

struct PlacefileParser {

    func parse(text: String, sourceURL: URL? = nil) -> Placefile {
        var title = sourceURL?.lastPathComponent ?? "Placefile"
        var refreshSeconds = 60
        var items: [PlacefileItem] = []

        var currentColor = PlacefileColor.white
        var lines = text.components(separatedBy: .newlines)
        var idx = 0

        while idx < lines.count {
            let raw = lines[idx].trimmingCharacters(in: .whitespaces)
            idx += 1

            if raw.isEmpty || raw.hasPrefix(";") { continue }

            let lower = raw.lowercased()

            if lower.hasPrefix("title:") {
                title = raw.dropPrefix("Title:").trimmingCharacters(in: .whitespaces)
            } else if lower.hasPrefix("refreshseconds:") {
                refreshSeconds = Int(raw.dropPrefix("RefreshSeconds:").trimmingCharacters(in: .whitespaces)) ?? 60
            } else if lower.hasPrefix("color:") {
                currentColor = parseColor(raw.dropPrefix("Color:")) ?? currentColor
            } else if lower.hasPrefix("icon:") {
                if let item = parseIcon(raw.dropPrefix("Icon:"), color: currentColor) {
                    items.append(item)
                }
            } else if lower.hasPrefix("text:") {
                if let item = parseText(raw.dropPrefix("Text:"), color: currentColor) {
                    items.append(item)
                }
            } else if lower.hasPrefix("line:") {
                let header = raw.dropPrefix("Line:")
                let collected = collectUntilEnd(lines: lines, from: &idx)
                if let item = parseLine(header: header, body: collected, color: currentColor) {
                    items.append(item)
                }
            } else if lower.hasPrefix("polygon:") {
                let collected = collectUntilEnd(lines: lines, from: &idx)
                if let item = parsePolygon(body: collected, color: currentColor) {
                    items.append(item)
                }
            } else if lower.hasPrefix("object:") {
                // Object: lat,lon — contains child Icon/Text/Line/Polygon until End:
                let objCoord = parseCoordPair(raw.dropPrefix("Object:"))
                let body = collectUntilEnd(lines: lines, from: &idx)
                let children = parseObjectBody(body, baseCoord: objCoord, color: currentColor)
                items.append(contentsOf: children)
            }
        }

        return Placefile(
            id: UUID(),
            title: title,
            refreshSeconds: refreshSeconds,
            items: items,
            fetchedAt: .now,
            sourceURL: sourceURL
        )
    }

    // MARK: - Element parsers

    // Icon: lat,lon,angle,"tooltip",iconFile[,iconId]
    private func parseIcon(_ s: Substring, color: PlacefileColor) -> PlacefileItem? {
        let parts = csvSplit(s)
        guard parts.count >= 4,
              let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let lon = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        let tooltip = parts[3].trimmingCharacters(in: .init(charactersIn: " \""))
        return PlacefileItem(
            id: UUID(),
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            label: tooltip,
            detail: "",
            color: color,
            geometry: .point
        )
    }

    // Text: lat,lon,angle,"label"[,"tooltip"]
    private func parseText(_ s: Substring, color: PlacefileColor) -> PlacefileItem? {
        let parts = csvSplit(s)
        guard parts.count >= 4,
              let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let lon = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        let label   = parts[3].trimmingCharacters(in: .init(charactersIn: " \""))
        let tooltip = parts.count >= 5 ? parts[4].trimmingCharacters(in: .init(charactersIn: " \"")) : ""
        return PlacefileItem(
            id: UUID(),
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            label: label,
            detail: tooltip,
            color: color,
            geometry: .point
        )
    }

    // Line: width,style / lat,lon pairs / End:
    private func parseLine(header: Substring, body: [String], color: PlacefileColor) -> PlacefileItem? {
        let hParts = header.split(separator: ",")
        let width = Int(hParts.first?.trimmingCharacters(in: .whitespaces) ?? "1") ?? 1
        let coords = body.compactMap { parseCoordLine($0) }
        guard coords.count >= 2 else { return nil }
        let center = coords[coords.count / 2]
        return PlacefileItem(
            id: UUID(),
            coordinate: center,
            label: "",
            detail: "",
            color: color,
            geometry: .line(points: coords, width: width)
        )
    }

    // Polygon: / lat,lon pairs / End:
    private func parsePolygon(body: [String], color: PlacefileColor) -> PlacefileItem? {
        let coords = body.compactMap { parseCoordLine($0) }
        guard coords.count >= 3 else { return nil }
        let center = coords[coords.count / 2]
        return PlacefileItem(
            id: UUID(),
            coordinate: center,
            label: "",
            detail: "",
            color: color,
            geometry: .polygon(points: coords)
        )
    }

    // Object body — same directives as top-level but nested
    private func parseObjectBody(_ lines: [String], baseCoord: CLLocationCoordinate2D?, color: PlacefileColor) -> [PlacefileItem] {
        let text = lines.joined(separator: "\n")
        // Re-parse as mini placefile; items inherit parent object's base color
        let sub = PlacefileParser().parse(text: text)
        // Override coordinates with base coord if items have no meaningful position
        return sub.items
    }

    // MARK: - Helpers

    private func collectUntilEnd(lines: [String], from idx: inout Int) -> [String] {
        var collected: [String] = []
        while idx < lines.count {
            let line = lines[idx].trimmingCharacters(in: .whitespaces)
            idx += 1
            if line.lowercased() == "end:" { break }
            if !line.isEmpty && !line.hasPrefix(";") {
                collected.append(line)
            }
        }
        return collected
    }

    // Parse "R G B [A]" into a PlacefileColor
    private func parseColor(_ s: Substring) -> PlacefileColor? {
        let parts = s.trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .compactMap { UInt8(exactly: Int($0) ?? 256) }
        guard parts.count >= 3 else { return nil }
        return PlacefileColor(r: parts[0], g: parts[1], b: parts[2],
                              a: parts.count >= 4 ? parts[3] : 220)
    }

    // Parse "lat,lon" coordinate pair
    private func parseCoordPair(_ s: Substring) -> CLLocationCoordinate2D? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ",")
        guard parts.count >= 2,
              let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let lon = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // Parse a single "lat,lon" body line
    private func parseCoordLine(_ s: String) -> CLLocationCoordinate2D? {
        parseCoordPair(Substring(s))
    }

    // Minimal CSV split that respects quoted fields
    private func csvSplit(_ s: Substring) -> [String] {
        var results: [String] = []
        var current = ""
        var inQuotes = false
        for ch in s {
            if ch == "\"" { inQuotes.toggle() }
            else if ch == "," && !inQuotes { results.append(current); current = "" }
            else { current.append(ch) }
        }
        results.append(current)
        return results
    }
}

// MARK: - String helpers

private extension String {
    func dropPrefix(_ prefix: String) -> Substring {
        if lowercased().hasPrefix(prefix.lowercased()) {
            return self.dropFirst(prefix.count)
        }
        return Substring(self)
    }
}

private extension Substring {
    func dropPrefix(_ prefix: String) -> Substring {
        if self.lowercased().hasPrefix(prefix.lowercased()) {
            return self.dropFirst(prefix.count)
        }
        return self
    }
}
