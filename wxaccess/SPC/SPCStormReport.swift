import Foundation
import CoreLocation

struct SPCStormReport: Sendable, Identifiable {
    let id: String
    let time: String          // "1430" UTC
    let location: String
    let county: String
    let state: String
    let coordinate: CLLocationCoordinate2D
    let comments: String
    let kind: Kind

    enum Kind: Sendable {
        case tornado(fScale: String)
        case hail(sizeInches: Float)
        case wind(speedMph: Int)
    }

    var accessibilityLabel: String {
        switch kind {
        case .tornado(let f):
            return "\(f) tornado at \(location), \(state) at \(formattedTime). \(comments)"
        case .hail(let s):
            return String(format: "%.2f inch hail at \(location), \(state) at \(formattedTime). \(comments)", s)
        case .wind(let spd):
            return "\(spd) mph wind at \(location), \(state) at \(formattedTime). \(comments)"
        }
    }

    var shortTitle: String {
        switch kind {
        case .tornado(let f):  return "Tornado (\(f))"
        case .hail(let s):     return String(format: "Hail (%.2f\")", s)
        case .wind(let spd):   return "Wind (\(spd) mph)"
        }
    }

    private var formattedTime: String {
        guard time.count == 4,
              let h = Int(time.prefix(2)),
              let m = Int(time.suffix(2)) else { return time }
        return String(format: "%02d:%02d UTC", h, m)
    }
}
