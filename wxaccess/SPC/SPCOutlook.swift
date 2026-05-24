import Foundation
import CoreLocation

// One categorical risk polygon from an SPC Day 1/2/3 outlook GeoJSON feature.
struct SPCOutlookPolygonData: Sendable, Identifiable {
    let id: String                          // "day\(day)-\(label)"
    let day: Int                            // 1, 2, or 3
    let category: SPCOutlook.Category
    let rings: [[CLLocationCoordinate2D]]   // outer ring + holes; usually one ring
    let valid: Date
    let expires: Date
}

// Container for all polygons fetched for a given day's outlook.
struct SPCOutlook: Sendable {
    let day: Int
    let fetched: Date
    let polygons: [SPCOutlookPolygonData]

    // Highest risk category present (for badge labeling).
    var highestCategory: SPCOutlook.Category? {
        polygons.map(\.category).max(by: { $0.sortOrder < $1.sortOrder })
    }

    enum Category: String, Sendable, CaseIterable {
        case generalThunderstorm = "TSTM"
        case marginal  = "MRGL"
        case slight    = "SLGT"
        case enhanced  = "ENH"
        case moderate  = "MDT"
        case high      = "HIGH"

        var displayName: String {
            switch self {
            case .generalThunderstorm: "General Thunderstorm"
            case .marginal:  "Marginal"
            case .slight:    "Slight"
            case .enhanced:  "Enhanced"
            case .moderate:  "Moderate"
            case .high:      "High"
            }
        }

        var sortOrder: Int {
            switch self {
            case .generalThunderstorm: 0
            case .marginal:  1
            case .slight:    2
            case .enhanced:  3
            case .moderate:  4
            case .high:      5
            }
        }

        // Standard SPC stroke hex colors, matching the GeoJSON `stroke` field.
        var color: (r: Double, g: Double, b: Double) {
            switch self {
            case .generalThunderstorm: (0.30, 0.60, 0.30)
            case .marginal:  (0.12, 0.73, 0.12)
            case .slight:    (1.00, 1.00, 0.00)
            case .enhanced:  (1.00, 0.50, 0.00)
            case .moderate:  (1.00, 0.00, 0.00)
            case .high:      (1.00, 0.00, 1.00)
            }
        }
    }
}
