import Foundation
import CoreLocation

struct NWSAlert: Sendable, Identifiable, Hashable {
    let id: String
    let event: String           // e.g. "Tornado Warning"
    let headline: String
    let description: String
    let instruction: String
    let severity: Severity
    let urgency: Urgency
    let effective: Date
    let expires: Date
    let affectedZones: [String]
    let polygon: [CLLocationCoordinate2D]  // empty if zone-based only
    let senderName: String

    var isActive: Bool { expires > .now }

    static func == (lhs: NWSAlert, rhs: NWSAlert) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    enum AlertKind: Sendable {
        case tornadoWarning
        case severeThunderstormWarning
        case tornadoWatch
        case severeThunderstormWatch
        case flashFloodWarning
        case flashFloodWatch
        case other
    }

    var kind: AlertKind {
        switch event {
        case "Tornado Warning":             return .tornadoWarning
        case "Severe Thunderstorm Warning": return .severeThunderstormWarning
        case "Tornado Watch":               return .tornadoWatch
        case "Severe Thunderstorm Watch":   return .severeThunderstormWatch
        case "Flash Flood Warning":         return .flashFloodWarning
        case "Flash Flood Watch":           return .flashFloodWatch
        default:                            return .other
        }
    }

    var accessibilityLabel: String {
        "\(severity.label) – \(event). \(headline). Expires \(expires.formatted(date: .omitted, time: .shortened))."
    }

    enum Severity: String, Sendable {
        case extreme, severe, moderate, minor, unknown
        var label: String { rawValue.capitalized }
        var sortOrder: Int {
            switch self {
            case .extreme: 0; case .severe: 1; case .moderate: 2; case .minor: 3; case .unknown: 4
            }
        }
    }

    enum Urgency: String, Sendable {
        case immediate, expected, future, past, unknown
    }
}
