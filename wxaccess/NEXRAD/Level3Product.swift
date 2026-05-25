import CoreLocation
import Foundation

// NEXRAD Level 3 product definitions.
// ICD reference: ICD 2620001 (RPG to Class 1 User ICD)
// S3 bucket: unidata-nexrad-level3 (anonymous access, no requester-pays)
// Key format (flat): {ICAO}_{MNEMONIC}_{YYYY}_{MM}_{DD}_{HH}_{mm}_{SS}

enum Level3ProductCode: Int, CaseIterable, Identifiable, Sendable {
    case baseReflectivity = 94    // N0Q — Super-res base reflectivity (dBZ)
    case baseVelocity     = 99    // N0U — Super-res base velocity (m/s)
    case echoTops         = 135   // EET — Enhanced echo tops (kft)
    case digitalVIL       = 134   // DVL — Digital VIL (kg/m²)
    case stormTotalPrecip = 80    // STP — Storm total precipitation (in)
    case oneHourPrecip    = 65    // OHP — One-hour precipitation (in)

    var id: Int { rawValue }

    var mnemonic: String {
        switch self {
        case .baseReflectivity:  "N0Q"
        case .baseVelocity:      "N0U"
        case .echoTops:          "EET"
        case .digitalVIL:        "DVL"
        case .stormTotalPrecip:  "STP"
        case .oneHourPrecip:     "OHP"
        }
    }

    var displayName: String {
        switch self {
        case .baseReflectivity:  "Base Reflectivity (L3)"
        case .baseVelocity:      "Base Velocity (L3)"
        case .echoTops:          "Echo Tops"
        case .digitalVIL:        "Digital VIL"
        case .stormTotalPrecip:  "Storm Total Precip"
        case .oneHourPrecip:     "1-Hour Precip"
        }
    }

    // NWS TGFTP DS data-stream code. nil = product not accessible on TGFTP; use THREDDS.
    var tgftpDataStream: String? {
        switch self {
        case .baseReflectivity:  return "p94r0"
        case .baseVelocity:      return "p99v0"
        case .echoTops:          return "135et"
        case .digitalVIL:        return nil       // DS.134dv → 403 on TGFTP
        case .stormTotalPrecip:  return "80stp"
        case .oneHourPrecip:     return nil       // DS.65ohp → 403 on TGFTP
        }
    }

    var physicalUnit: String {
        switch self {
        case .baseReflectivity:  "dBZ"
        case .baseVelocity:      "m/s"
        case .echoTops:          "kft"
        case .digitalVIL:        "kg/m²"
        case .stormTotalPrecip,
             .oneHourPrecip:     "in"
        }
    }

    // Convert ICD data level code to physical value.
    // code 0 = below threshold, 1 = range folded, 2–254 = valid, 255 = beyond max range.
    // Formulas from ICD 2620001 product-specific appendices.
    func physicalValue(code: UInt8) -> Float? {
        guard code >= 2, code != 255 else { return nil }
        let level = Float(code)
        switch self {
        case .baseReflectivity:  return (level - 2) * 0.5 - 32.5
        case .baseVelocity:      return (level - 2) * 0.5 - 63.5
        case .echoTops:          return (level - 2) * 1.0 + 5.0
        case .digitalVIL:        return (level - 2) * 1.0
        case .stormTotalPrecip,
             .oneHourPrecip:     return (level - 2) * 0.05
        }
    }
}

// One Level 3 radial sweep decoded from a Packet Code 16 product file.
struct Level3RadialSweep: Sendable {
    let site: NEXRADSite
    let scanTime: Date
    let elevationAngle: Double    // 0 for composite products (EET, DVL, precip)
    let productCode: Level3ProductCode
    let radials: [Level3Radial]
    let numBins: Int
    let firstBinKm: Double        // range to center of first bin
    let binSizeKm: Double         // range resolution per bin

    var maxRangeKm: Double { firstBinKm + Double(numBins) * binSizeKm }
    var momentType: String { productCode.mnemonic }
}

// A single Level 3 radial from a Packet Code 16 product.
struct Level3Radial: Sendable {
    let startAngle: Double    // degrees clockwise from north (0–360)
    let deltaAngle: Double    // angular width (degrees)
    let data: [UInt8]         // data level codes per range bin

    func physicalValue(binIndex: Int, product: Level3ProductCode) -> Float? {
        guard binIndex < data.count else { return nil }
        return product.physicalValue(code: data[binIndex])
    }
}
