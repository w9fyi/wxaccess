import Foundation

enum ColorPalette: String, CaseIterable, Identifiable, Sendable {
    case nwsStandard = "NWS Standard"
    case grDefault   = "GRLevel3 Default"
    case colorblind  = "Colorblind-Friendly"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var accessibilityDescription: String {
        switch self {
        case .nwsStandard: return "Standard NWS color table, green through red."
        case .grDefault:   return "GRLevel3-style table with enhanced storm-core contrast."
        case .colorblind:  return "Blue-to-orange scale, avoids red-green confusion."
        }
    }

    func reflectivityColor(dbz: Float) -> UInt32 {
        switch self {
        case .nwsStandard: return nwsColor(dbz: dbz)
        case .grDefault:   return grColor(dbz: dbz)
        case .colorblind:  return cbColor(dbz: dbz)
        }
    }

    private func rgba(_ r: UInt32, _ g: UInt32, _ b: UInt32, a: UInt32 = 210) -> UInt32 {
        (r << 24) | (g << 16) | (b << 8) | a
    }

    // Current NWS standard table
    private func nwsColor(dbz: Float) -> UInt32 {
        switch dbz {
        case ..<5:    return 0
        case 5..<10:  return rgba(0x00, 0xEC, 0xEC)
        case 10..<15: return rgba(0x01, 0x9F, 0xF4)
        case 15..<20: return rgba(0x03, 0x00, 0xF4)
        case 20..<25: return rgba(0x02, 0xFD, 0x02)
        case 25..<30: return rgba(0x01, 0xC5, 0x01)
        case 30..<35: return rgba(0x00, 0x8E, 0x00)
        case 35..<40: return rgba(0xFD, 0xF8, 0x02)
        case 40..<45: return rgba(0xE5, 0xBC, 0x00)
        case 45..<50: return rgba(0xFD, 0x95, 0x00)
        case 50..<55: return rgba(0xFD, 0x00, 0x00)
        case 55..<60: return rgba(0xD4, 0x00, 0x00)
        case 60..<65: return rgba(0xBC, 0x00, 0x00)
        case 65..<70: return rgba(0xF8, 0x00, 0xFD)
        case 70..<75: return rgba(0x98, 0x54, 0xC6)
        default:      return rgba(0xFF, 0xFF, 0xFF)
        }
    }

    // GRLevel3-style: more color steps, enhanced contrast in the 50–65 dBZ range
    private func grColor(dbz: Float) -> UInt32 {
        switch dbz {
        case ..<5:    return 0
        case 5..<10:  return rgba(0x40, 0xE0, 0xD0)
        case 10..<15: return rgba(0x00, 0xBF, 0xFF)
        case 15..<20: return rgba(0x00, 0x00, 0xFF)
        case 20..<25: return rgba(0x00, 0xFF, 0x00)
        case 25..<30: return rgba(0x00, 0xC0, 0x00)
        case 30..<35: return rgba(0x00, 0x80, 0x00)
        case 35..<40: return rgba(0xFF, 0xFF, 0x00)
        case 40..<45: return rgba(0xFF, 0xC0, 0x00)
        case 45..<50: return rgba(0xFF, 0x80, 0x00)
        case 50..<55: return rgba(0xFF, 0x00, 0x00)
        case 55..<60: return rgba(0xC0, 0x00, 0x00)
        case 60..<65: return rgba(0xFF, 0x00, 0xFF)
        case 65..<70: return rgba(0xC0, 0x00, 0xC0)
        case 70..<75: return rgba(0xFF, 0xFF, 0xFF)
        default:      return rgba(0xFF, 0xFF, 0xFF, a: 255)
        }
    }

    // Colorblind-friendly: blue → amber/orange scale (avoids red-green ambiguity)
    private func cbColor(dbz: Float) -> UInt32 {
        switch dbz {
        case ..<5:    return 0
        case 5..<10:  return rgba(0xCA, 0xCC, 0xE4)
        case 10..<15: return rgba(0x74, 0x8E, 0xA4)
        case 15..<20: return rgba(0x22, 0x55, 0x8C)
        case 20..<25: return rgba(0x0F, 0x80, 0xB8)
        case 25..<30: return rgba(0x00, 0xBF, 0xD0)
        case 30..<35: return rgba(0xA2, 0xD4, 0x45)
        case 35..<40: return rgba(0xF9, 0xE5, 0x00)
        case 40..<45: return rgba(0xF6, 0xAA, 0x00)
        case 45..<50: return rgba(0xEF, 0x7B, 0x00)
        case 50..<55: return rgba(0xE4, 0x40, 0x00)
        case 55..<60: return rgba(0xC8, 0x00, 0x00)
        case 60..<65: return rgba(0x96, 0x00, 0x64)
        case 65..<70: return rgba(0xF0, 0xE6, 0xFF)
        case 70..<75: return rgba(0xFF, 0xFF, 0xFF)
        default:      return rgba(0xFF, 0xFF, 0xFF, a: 255)
        }
    }
}
