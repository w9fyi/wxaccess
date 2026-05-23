import MapKit
import CoreLocation
import CoreGraphics

// MKOverlay that holds a rasterized radar sweep image and its bounding region.
final class RadarOverlay: NSObject, MKOverlay, @unchecked Sendable {
    let coordinate: CLLocationCoordinate2D  // radar site
    let boundingMapRect: MKMapRect
    let image: CGImage
    let sweep: RadarSweep

    init(sweep: RadarSweep, imageSize: Int = 1024) {
        self.sweep = sweep
        self.coordinate = sweep.site.coordinate

        let maxRangeKm = max(sweep.maxRangeKm, 1)
        // Build a square bounding box centred on the radar site.
        let originPoint = MKMapPoint(sweep.site.coordinate)
        let metersPerMapPoint = MKMetersPerMapPointAtLatitude(sweep.site.coordinate.latitude)
        let halfSideMapPoints = (maxRangeKm * 1000) / metersPerMapPoint
        self.boundingMapRect = MKMapRect(
            x: originPoint.x - halfSideMapPoints,
            y: originPoint.y - halfSideMapPoints,
            width:  halfSideMapPoints * 2,
            height: halfSideMapPoints * 2
        )

        self.image = RadarOverlay.rasterize(sweep: sweep, size: imageSize, maxRangeKm: maxRangeKm)
        super.init()
    }

    // MARK: - Rasterization

    // Convert polar radial data to a square CGImage via inverse-mapping.
    // Each pixel's (azimuth, range) is computed and the nearest gate value looked up.
    private static func rasterize(sweep: RadarSweep, size: Int, maxRangeKm: Double) -> CGImage {
        let width  = size
        let height = size
        var pixels = [UInt32](repeating: 0, count: width * height)

        // Build a lookup: azimuth (rounded to nearest 0.5°) → Radial
        var radialMap: [Int: Radial] = [:]
        for radial in sweep.radials {
            let key = Int((radial.azimuth * 2).rounded())  // half-degree resolution
            radialMap[key] = radial
        }

        let half = Double(size) / 2.0

        for row in 0..<height {
            for col in 0..<width {
                let dx = (Double(col) - half) / half  // -1…+1, east positive
                let dy = (half - Double(row)) / half  // -1…+1, north positive
                let distNorm = sqrt(dx * dx + dy * dy)
                guard distNorm <= 1.0 else { continue }

                let rangeKm = distNorm * maxRangeKm
                // Azimuth: clockwise from north
                var az = atan2(dx, dy) * 180.0 / .pi
                if az < 0 { az += 360.0 }

                let azKey = Int((az * 2).rounded()) % 720
                guard let radial = radialMap[azKey] ?? radialMap[(azKey + 1) % 720] ?? radialMap[(azKey - 1 + 720) % 720],
                      radial.gateSizeMeters > 0 else { continue }

                let gateIndex = Int((rangeKm * 1000 - Double(radial.firstGateMeters)) / Double(radial.gateSizeMeters))
                guard let value = radial.physicalValue(gateIndex: gateIndex) else { continue }

                pixels[row * width + col] = momentColor(value: value, momentType: sweep.momentType)
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo.rawValue),
              let image = ctx.makeImage()
        else {
            return CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo,
                           provider: CGDataProvider(data: Data([0,0,0,0]) as CFData)!,
                           decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        }
        return image
    }

    private static func momentColor(value: Float, momentType: String) -> UInt32 {
        switch momentType {
        case "VEL": return velocityColor(ms: value)
        case "ZDR": return zdrColor(db: value)
        case "RHO": return rhoColor(cc: value)
        case "PHI": return phiColor(deg: value)
        case "SW":  return swColor(ms: value)
        default:    return reflectivityColor(dbz: value)
        }
    }

    // Standard NWS reflectivity color table (dBZ)
    private static func reflectivityColor(dbz: Float) -> UInt32 {
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

    // NWS velocity color table (m/s; negative = toward radar)
    private static func velocityColor(ms: Float) -> UInt32 {
        switch ms {
        case ..<(-50):  return rgba(0x00, 0x00, 0x7F)
        case -50 ..< -30: return rgba(0x00, 0x00, 0xEC)
        case -30 ..< -20: return rgba(0x00, 0x9E, 0xFF)
        case -20 ..< -10: return rgba(0x00, 0xF0, 0xF0)
        case -10 ..< 0:   return rgba(0x00, 0xC8, 0x00)
        case 0   ..< 10:  return rgba(0xC8, 0xC8, 0x00)
        case 10  ..< 20:  return rgba(0xFF, 0x96, 0x00)
        case 20  ..< 30:  return rgba(0xFF, 0x00, 0x00)
        case 30  ..< 50:  return rgba(0xC8, 0x00, 0x00)
        default:          return rgba(0x7F, 0x00, 0x00)
        }
    }

    // Differential reflectivity (dB)
    private static func zdrColor(db: Float) -> UInt32 {
        switch db {
        case ..<(-1):   return rgba(0x00, 0x00, 0xC8)
        case -1 ..< 0:  return rgba(0x00, 0x96, 0xFF)
        case 0  ..< 1:  return rgba(0x00, 0xC8, 0x96)
        case 1  ..< 2:  return rgba(0x00, 0xC8, 0x00)
        case 2  ..< 3:  return rgba(0xC8, 0xC8, 0x00)
        case 3  ..< 4:  return rgba(0xFF, 0x96, 0x00)
        case 4  ..< 5:  return rgba(0xFF, 0x00, 0x00)
        default:        return rgba(0xFF, 0x00, 0xFF)
        }
    }

    // Correlation coefficient (0–1)
    private static func rhoColor(cc: Float) -> UInt32 {
        switch cc {
        case ..<0.7:    return rgba(0x00, 0x00, 0x00)
        case 0.7 ..< 0.85: return rgba(0x96, 0x32, 0x96)
        case 0.85 ..< 0.90: return rgba(0x00, 0x00, 0xFF)
        case 0.90 ..< 0.95: return rgba(0x00, 0xC8, 0xFF)
        case 0.95 ..< 0.97: return rgba(0x00, 0xC8, 0x00)
        case 0.97 ..< 0.99: return rgba(0xFF, 0xFF, 0x00)
        default:        return rgba(0xFF, 0xFF, 0xFF)
        }
    }

    // Differential phase (degrees, 0–360)
    private static func phiColor(deg: Float) -> UInt32 {
        let hue = (deg / 360.0).truncatingRemainder(dividingBy: 1.0)
        let (r, g, b) = hsvToRgb(h: hue, s: 0.85, v: 0.90)
        return rgba(r, g, b)
    }

    // Spectrum width (m/s, 0–~20)
    private static func swColor(ms: Float) -> UInt32 {
        switch ms {
        case ..<2:   return rgba(0x00, 0x00, 0x96)
        case 2..<4:  return rgba(0x00, 0x64, 0xFF)
        case 4..<6:  return rgba(0x00, 0xC8, 0x96)
        case 6..<8:  return rgba(0x00, 0xC8, 0x00)
        case 8..<10: return rgba(0xC8, 0xC8, 0x00)
        case 10..<13: return rgba(0xFF, 0x96, 0x00)
        case 13..<16: return rgba(0xFF, 0x00, 0x00)
        default:     return rgba(0xFF, 0xFF, 0xFF)
        }
    }

    private static func rgba(_ r: UInt32, _ g: UInt32, _ b: UInt32, a: UInt32 = 210) -> UInt32 {
        (r << 24) | (g << 16) | (b << 8) | a
    }

    private static func hsvToRgb(h: Float, s: Float, v: Float) -> (UInt32, UInt32, UInt32) {
        let i = Int(h * 6)
        let f = h * 6 - Float(i)
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        let (r, g, b): (Float, Float, Float)
        switch i % 6 {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
        return (UInt32(r * 255), UInt32(g * 255), UInt32(b * 255))
    }
}
