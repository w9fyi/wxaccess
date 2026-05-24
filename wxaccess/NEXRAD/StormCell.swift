import CoreLocation
import Foundation

struct StormCell: Sendable, Identifiable {
    let id: String                              // "A1", "K2", etc.
    let radarSite: CLLocationCoordinate2D
    let current: CLLocationCoordinate2D
    let past: [CLLocationCoordinate2D]          // oldest → most recent
    let forecast: [CLLocationCoordinate2D]      // nearest → farthest future

    var forecast30min: CLLocationCoordinate2D? { forecast.first }
    var forecast60min: CLLocationCoordinate2D? { forecast.count > 1 ? forecast[1] : nil }

    var rangeFromRadarKm: Double { haversineKm(radarSite, current) }
    var bearingFromRadarDeg: Double { bearingDeg(from: radarSite, to: current) }

    var motionBearingDeg: Double? {
        guard let f = forecast30min else { return nil }
        return bearingDeg(from: current, to: f)
    }
    var motionSpeedKph: Double? {
        guard let f = forecast30min else { return nil }
        return haversineKm(current, f) * 2.0   // 30 min = 0.5 hr → km / 0.5 hr = km/h * 2
    }

    var accessibilityDescription: String {
        let dir   = compassPoint(bearingFromRadarDeg)
        let range = Int(rangeFromRadarKm.rounded())
        var desc  = "Cell \(id): \(dir) \(range) km from radar"
        if let bearing = motionBearingDeg, let speed = motionSpeedKph {
            desc += ", moving \(compassPoint(bearing)) at \(Int(speed.rounded())) km/h"
        } else {
            desc += ", slow-moving or stationary"
        }
        return desc
    }

    private func haversineKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let R    = 6371.0
        let dLat = (b.latitude  - a.latitude)  * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let sLat = sin(dLat / 2), sLon = sin(dLon / 2)
        let h    = sLat*sLat + cos(a.latitude * .pi/180) * cos(b.latitude * .pi/180) * sLon*sLon
        return R * 2 * asin(sqrt(h))
    }

    private func bearingDeg(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y    = sin(dLon) * cos(lat2)
        let x    = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func compassPoint(_ bearing: Double) -> String {
        let dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        return dirs[Int((bearing + 11.25) / 22.5) % 16]
    }
}
