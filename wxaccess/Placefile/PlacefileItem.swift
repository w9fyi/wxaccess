import Foundation
import CoreLocation

// One parsed item from a GRLevel3/AllisonHouse-format placefile.
struct PlacefileItem: Sendable, Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D  // primary position (icon/text) or centroid (line/poly)
    let label: String                        // displayed label (Text: field) or tooltip (Icon: field)
    let detail: String                       // secondary hover text, may be empty
    let color: PlacefileColor
    let geometry: Geometry

    enum Geometry: Sendable {
        case point                                      // icon or text label
        case line(points: [CLLocationCoordinate2D], width: Int)
        case polygon(points: [CLLocationCoordinate2D])
    }

    var accessibilityLabel: String {
        var parts = [label]
        if !detail.isEmpty { parts.append(detail) }
        parts.append(String(format: "%.4f°N, %.4f°W", coordinate.latitude, abs(coordinate.longitude)))
        return parts.joined(separator: ". ")
    }
}

struct PlacefileColor: Sendable {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

    static let white = PlacefileColor(r: 255, g: 255, b: 255, a: 220)

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 220) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

struct Placefile: Sendable, Identifiable {
    let id: UUID
    let title: String
    let refreshSeconds: Int
    let items: [PlacefileItem]
    let fetchedAt: Date
    let sourceURL: URL?

    var nextRefreshAt: Date {
        fetchedAt.addingTimeInterval(Double(max(refreshSeconds, 30)))
    }

    var isStale: Bool { .now >= nextRefreshAt }
}
