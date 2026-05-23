import CoreLocation
import Foundation

struct RadarSweep: Sendable {
    let site: NEXRADSite
    let scanTime: Date
    let elevationAngle: Double
    let vcpNumber: Int
    let radials: [Radial]
    let momentType: String

    var maxRangeKm: Double {
        Double(radials.map(\.numGates).max() ?? 0) * Double(radials.first?.gateSizeMeters ?? 250) / 1000.0
    }
}

struct Radial: Sendable {
    let azimuth: Double        // degrees clockwise from north, 0–360
    let elevation: Double      // degrees above horizon
    let firstGateMeters: Int   // range to first gate center, meters
    let gateSizeMeters: Int    // range between successive gates, meters
    let numGates: Int
    let scale: Float           // raw → physical: physical = (raw - offset) / scale
    let offset: Float
    // Gate values: 0 = below threshold, 1 = range folded, 2+ = valid.
    // UInt16 covers both 8-bit (REF, RHO) and 16-bit (VEL, ZDR, PHI) NEXRAD moments.
    let data: [UInt16]

    func physicalValue(gateIndex: Int) -> Float? {
        guard gateIndex < data.count else { return nil }
        let raw = data[gateIndex]
        guard raw > 1 else { return nil }
        return (Float(raw) - offset) / scale
    }

    func rangeToGate(index: Int) -> Double {
        Double(firstGateMeters + index * gateSizeMeters) / 1000.0  // km
    }
}

struct ScanEntry: Sendable, Identifiable, Hashable {
    let id: String        // S3 key
    let site: NEXRADSite
    let scanTime: Date
    let fileName: String
}
