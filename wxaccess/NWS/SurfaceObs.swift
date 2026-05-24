import Foundation
import CoreLocation

struct SurfaceObs: Sendable, Identifiable {
    let id: String              // station identifier
    let stationId: String
    let coordinate: CLLocationCoordinate2D
    let tempC: Float?
    let dewpointC: Float?
    let windDirDeg: Int?
    let windSpeedKt: Int?
    let altimInHg: Float?
    let skyCondition: String    // top-most sky cover: "CLR", "FEW", "SCT", "BKN", "OVC"
    let flightCategory: FlightCategory
    let observationTime: Date

    enum FlightCategory: String, Sendable {
        case vfr   = "VFR"
        case mvfr  = "MVFR"
        case ifr   = "IFR"
        case lifr  = "LIFR"
        case unknown = ""

        var color: (r: Double, g: Double, b: Double) {
            switch self {
            case .vfr:     return (0,    0.7,  0)
            case .mvfr:    return (0,    0,    1)
            case .ifr:     return (0.7,  0,    0)
            case .lifr:    return (0.6,  0,    0.6)
            case .unknown: return (0.45, 0.45, 0.45)
            }
        }

        var displayName: String { rawValue.isEmpty ? "Unknown" : rawValue }
    }

    var tempF:      Float? { tempC.map     { $0 * 9 / 5 + 32 } }
    var dewpointF:  Float? { dewpointC.map { $0 * 9 / 5 + 32 } }

    var accessibilityLabel: String {
        var parts = [stationId]
        if let t = tempF     { parts.append(String(format: "%.0f°F", t)) }
        if let d = dewpointF { parts.append(String(format: "dew %.0f°F", d)) }
        if let dir = windDirDeg, let spd = windSpeedKt {
            parts.append("\(dir)° at \(spd) kt")
        }
        parts.append(flightCategory.displayName)
        return parts.joined(separator: ", ")
    }
}
