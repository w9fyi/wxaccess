import MapKit
import CoreLocation
import CoreGraphics
import OSLog

// MKOverlay that holds a rasterized NEXRAD Level 3 radial product image.
// Mirrors RadarOverlay but works with Level3RadialSweep instead of RadarSweep.
final class Level3Overlay: NSObject, MKOverlay, @unchecked Sendable {
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect
    let image: CGImage
    let sweep: Level3RadialSweep

    init(sweep: Level3RadialSweep, imageSize: Int = 0) {
        self.sweep = sweep
        self.coordinate = sweep.site.coordinate

        let sz = imageSize > 0 ? imageSize
            : (UserDefaults.standard.integer(forKey: "imageSize") > 0
               ? UserDefaults.standard.integer(forKey: "imageSize") : 1024)

        let maxRangeKm = max(sweep.maxRangeKm, 1)
        let originPoint = MKMapPoint(sweep.site.coordinate)
        let metersPerMapPoint = MKMetersPerMapPointAtLatitude(sweep.site.coordinate.latitude)
        let halfSideMapPoints = (maxRangeKm * 1000) / metersPerMapPoint
        self.boundingMapRect = MKMapRect(
            x: originPoint.x - halfSideMapPoints,
            y: originPoint.y - halfSideMapPoints,
            width:  halfSideMapPoints * 2,
            height: halfSideMapPoints * 2
        )

        self.image = Level3Overlay.rasterize(sweep: sweep, size: sz, maxRangeKm: maxRangeKm)
        super.init()
    }

    // MARK: - Rasterization

    private static let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "Level3Overlay")

    private static func rasterize(sweep: Level3RadialSweep,
                                   size: Int, maxRangeKm: Double) -> CGImage {
        let width = size, height = size
        var pixels = [UInt32](repeating: 0, count: width * height)

        // Build azimuth → Level3Radial lookup at 0.5° resolution.
        var radialMap: [Int: Level3Radial] = [:]
        for radial in sweep.radials {
            let key = Int((radial.startAngle * 2).rounded()) % 720
            radialMap[key] = radial
        }

        let half = Double(size) / 2.0

        for row in 0..<height {
            for col in 0..<width {
                let dx = (Double(col) - half) / half   // east positive
                let dy = (half - Double(row)) / half   // north positive
                let distNorm = sqrt(dx * dx + dy * dy)
                guard distNorm <= 1.0 else { continue }

                let rangeKm = distNorm * maxRangeKm
                guard rangeKm >= sweep.firstBinKm else { continue }

                var az = atan2(dx, dy) * 180.0 / .pi
                if az < 0 { az += 360.0 }

                let azKey = Int((az * 2).rounded()) % 720
                guard let radial = radialMap[azKey]
                               ?? radialMap[(azKey + 1) % 720]
                               ?? radialMap[(azKey - 1 + 720) % 720]
                else { continue }

                let binIndex = Int((rangeKm - sweep.firstBinKm) / sweep.binSizeKm)
                guard let value = radial.physicalValue(binIndex: binIndex,
                                                        product: sweep.productCode)
                else { continue }

                pixels[row * width + col] = productColor(value: value, product: sweep.productCode)
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(data: &pixels,
                                   width: width, height: height,
                                   bitsPerComponent: 8, bytesPerRow: width * 4,
                                   space: colorSpace, bitmapInfo: bitmapInfo.rawValue),
              let image = ctx.makeImage()
        else {
            logger.error("CGContext creation failed for \(sweep.site.icao) \(sweep.productCode.mnemonic)")
            guard let provider = CGDataProvider(data: Data([0, 0, 0, 0]) as CFData),
                  let fallback = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                                        bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo,
                                        provider: provider, decode: nil, shouldInterpolate: false,
                                        intent: .defaultIntent)
            else { fatalError("Cannot create fallback CGImage — graphics subsystem failure") }
            return fallback
        }
        return image
    }

    // MARK: - Color tables

    private static func productColor(value: Float, product: Level3ProductCode) -> UInt32 {
        switch product {
        case .baseReflectivity:              return reflColor(dbz: value)
        case .baseVelocity:                  return velColor(ms: value)
        case .echoTops:                      return etColor(kft: value)
        case .digitalVIL:                    return vilColor(kgm2: value)
        case .stormTotalPrecip, .oneHourPrecip: return precipColor(inches: value)
        }
    }

    // NWS standard reflectivity (dBZ)
    private static func reflColor(dbz: Float) -> UInt32 {
        switch dbz {
        case ..<5:    return rgba(0x04, 0x04, 0xC8)
        case 5..<10:  return rgba(0x04, 0x94, 0xF4)
        case 10..<15: return rgba(0x00, 0xE8, 0x14)
        case 15..<20: return rgba(0x00, 0xBD, 0x00)
        case 20..<25: return rgba(0x00, 0x8C, 0x00)
        case 25..<30: return rgba(0xF0, 0xF0, 0x00)
        case 30..<35: return rgba(0xE8, 0xC0, 0x00)
        case 35..<40: return rgba(0xFC, 0x90, 0x00)
        case 40..<45: return rgba(0xFC, 0x00, 0x00)
        case 45..<50: return rgba(0xD4, 0x00, 0x00)
        case 50..<55: return rgba(0xBC, 0x00, 0x00)
        case 55..<60: return rgba(0xF0, 0x00, 0xF0)
        case 60..<65: return rgba(0x99, 0x55, 0xC9)
        default:      return rgba(0xFF, 0xFF, 0xFF)
        }
    }

    // NWS velocity (m/s, negative = toward radar)
    private static func velColor(ms: Float) -> UInt32 {
        switch ms {
        case ..<(-50):    return rgba(0x00, 0x00, 0x7F)
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

    // Echo tops (kft)
    private static func etColor(kft: Float) -> UInt32 {
        switch kft {
        case ..<10:    return rgba(0x00, 0x40, 0x00)
        case 10..<20:  return rgba(0x00, 0x80, 0x00)
        case 20..<30:  return rgba(0x00, 0xCC, 0x00)
        case 30..<40:  return rgba(0xFF, 0xFF, 0x00)
        case 40..<50:  return rgba(0xFF, 0xA5, 0x00)
        case 50..<60:  return rgba(0xFF, 0x00, 0x00)
        case 60..<70:  return rgba(0xCC, 0x00, 0xCC)
        default:       return rgba(0xFF, 0xFF, 0xFF)
        }
    }

    // Digital VIL (kg/m²)
    private static func vilColor(kgm2: Float) -> UInt32 {
        switch kgm2 {
        case ..<5:    return rgba(0x00, 0x40, 0xFF)
        case 5..<10:  return rgba(0x00, 0x80, 0xFF)
        case 10..<20: return rgba(0x00, 0xD0, 0xFF)
        case 20..<30: return rgba(0x00, 0xFF, 0x80)
        case 30..<40: return rgba(0xFF, 0xFF, 0x00)
        case 40..<50: return rgba(0xFF, 0x80, 0x00)
        case 50..<60: return rgba(0xFF, 0x00, 0x00)
        case 60..<70: return rgba(0xC8, 0x00, 0xC8)
        default:      return rgba(0xFF, 0xFF, 0xFF)
        }
    }

    // Precipitation (inches): storm total or 1-hour
    private static func precipColor(inches: Float) -> UInt32 {
        switch inches {
        case ..<0.1:    return rgba(0x04, 0x94, 0xF4)
        case 0.1..<0.25: return rgba(0x04, 0xE4, 0x14)
        case 0.25..<0.5: return rgba(0x04, 0xB4, 0x04)
        case 0.5..<1.0:  return rgba(0xF0, 0xF0, 0x00)
        case 1.0..<1.5:  return rgba(0xE8, 0x90, 0x00)
        case 1.5..<2.0:  return rgba(0xFC, 0x00, 0x00)
        case 2.0..<2.5:  return rgba(0xD4, 0x00, 0x00)
        case 2.5..<3.0:  return rgba(0xBC, 0x00, 0x00)
        case 3.0..<4.0:  return rgba(0xF0, 0x00, 0xF0)
        default:         return rgba(0xFF, 0xFF, 0xFF)
        }
    }

    private static func rgba(_ r: UInt32, _ g: UInt32, _ b: UInt32, a: UInt32 = 210) -> UInt32 {
        (r << 24) | (g << 16) | (b << 8) | a
    }
}

// MARK: - Renderer

final class Level3OverlayRenderer: MKOverlayRenderer {
    private let l3Overlay: Level3Overlay

    init(overlay: Level3Overlay) {
        self.l3Overlay = overlay
        super.init(overlay: overlay)
        self.alpha = 0.75
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        let drawRect = rect(for: l3Overlay.boundingMapRect)
        ctx.draw(l3Overlay.image, in: drawRect)
    }

    override func canDraw(_ mapRect: MKMapRect, zoomScale: MKZoomScale) -> Bool {
        l3Overlay.boundingMapRect.intersects(mapRect)
    }
}
