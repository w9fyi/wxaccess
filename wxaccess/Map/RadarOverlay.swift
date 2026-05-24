import MapKit
import CoreLocation
import CoreGraphics
import OSLog

// MKOverlay that holds a rasterized radar sweep image and its bounding region.
// Supports single or multiple radar sites; values in overlap zones are blended
// using inverse-distance² weighting so the nearest site dominates naturally.
final class RadarOverlay: NSObject, MKOverlay, @unchecked Sendable {
    let coordinate: CLLocationCoordinate2D  // centroid of all sites
    let boundingMapRect: MKMapRect
    let image: CGImage
    let sweeps: [RadarSweep]
    let palette: ColorPalette
    // Stable key for change-detection in MainMapView.
    // Combines sorted site/time pairs and palette so rebuilds happen iff data or palette changes.
    let sweepKey: String

    init(sweeps: [RadarSweep], imageSize: Int = 0, palette: ColorPalette = .nwsStandard) {
        self.sweeps  = sweeps
        self.palette = palette

        let sz = imageSize > 0 ? imageSize
            : (UserDefaults.standard.integer(forKey: "imageSize") > 0
               ? UserDefaults.standard.integer(forKey: "imageSize") : 1024)

        self.sweepKey = sweeps
            .map { "\($0.site.icao)-\(Int($0.scanTime.timeIntervalSince1970))" }
            .sorted()
            .joined(separator: ",")
            + "/\(palette)"

        guard !sweeps.isEmpty else {
            self.coordinate     = CLLocationCoordinate2D()
            self.boundingMapRect = .world
            let cs = CGColorSpaceCreateDeviceRGB()
            let bi = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            self.image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
                                 bytesPerRow: 4, space: cs, bitmapInfo: bi,
                                 provider: CGDataProvider(data: Data([0,0,0,0]) as CFData)!,
                                 decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
            super.init()
            return
        }

        // Centroid of all site coordinates
        let avgLat = sweeps.map { $0.site.coordinate.latitude  }.reduce(0, +) / Double(sweeps.count)
        let avgLon = sweeps.map { $0.site.coordinate.longitude }.reduce(0, +) / Double(sweeps.count)
        self.coordinate = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)

        // Union of each site's bounding box (square of radius maxRangeKm)
        var unionRect = MKMapRect.null
        for sweep in sweeps {
            let origin = MKMapPoint(sweep.site.coordinate)
            let mpp    = MKMetersPerMapPointAtLatitude(sweep.site.coordinate.latitude)
            let half   = (max(sweep.maxRangeKm, 1) * 1000) / mpp
            let rect   = MKMapRect(x: origin.x - half, y: origin.y - half,
                                   width: half * 2, height: half * 2)
            unionRect  = unionRect.isNull ? rect : unionRect.union(rect)
        }
        self.boundingMapRect = unionRect

        self.image = RadarOverlay.rasterize(sweeps: sweeps, size: sz,
                                            boundingRect: unionRect, palette: palette)
        super.init()
    }

    // MARK: - Rasterization

    private static let logger = Logger(subsystem: "net.ai5os.wxaccess", category: "RadarOverlay")

    // Pre-computed per-sweep rendering data.
    private struct SweepInfo {
        let radialMap: [Int: Radial]
        let siteMapX: Double
        let siteMapY: Double
        // Approximate meters-per-map-point at the site's latitude.
        // Error is <1% within a 460 km radius — visually indistinguishable.
        let mpp: Double
        let maxRangeKm: Double
        let momentType: String
    }

    // Converts polar radial data to a square CGImage via inverse-mapping.
    // For each pixel the (azimuth, range) relative to every site is computed in
    // MKMapPoint space (fast, no trig projection needed) and gate values are
    // blended with inverse-distance² weights.
    private static func rasterize(sweeps: [RadarSweep], size: Int,
                                  boundingRect: MKMapRect, palette: ColorPalette) -> CGImage {
        let width  = size
        let height = size
        var pixels = [UInt32](repeating: 0, count: width * height)

        let infos: [SweepInfo] = sweeps.map { sweep in
            var rmap: [Int: Radial] = [:]
            for radial in sweep.radials {
                let key = Int((radial.azimuth * 2).rounded())
                rmap[key] = radial
            }
            let pt = MKMapPoint(sweep.site.coordinate)
            return SweepInfo(
                radialMap:   rmap,
                siteMapX:    pt.x,
                siteMapY:    pt.y,
                mpp:         MKMetersPerMapPointAtLatitude(sweep.site.coordinate.latitude),
                maxRangeKm:  max(sweep.maxRangeKm, 1),
                momentType:  sweep.momentType
            )
        }

        let minX    = boundingRect.minX
        let minY    = boundingRect.minY
        let rWidth  = boundingRect.width
        let rHeight = boundingRect.height
        let dw      = Double(width)
        let dh      = Double(height)

        for row in 0..<height {
            let mapY = minY + (Double(row) + 0.5) / dh * rHeight

            for col in 0..<width {
                let mapX = minX + (Double(col) + 0.5) / dw * rWidth

                var weightedSum = 0.0
                var totalWeight = 0.0
                var momentType  = infos.first?.momentType ?? "REF"

                for info in infos {
                    // Displacement from site in MKMapPoint space.
                    // y is flipped because map-y increases southward.
                    let dmpX = mapX - info.siteMapX
                    let dmpY = -(mapY - info.siteMapY)

                    let distSq   = dmpX * dmpX + dmpY * dmpY
                    let rangeKm  = distSq.squareRoot() * info.mpp / 1000.0
                    guard rangeKm <= info.maxRangeKm else { continue }

                    // Clockwise azimuth from north
                    var az = atan2(dmpX, dmpY) * 180.0 / .pi
                    if az < 0 { az += 360.0 }

                    let azKey = Int((az * 2).rounded()) % 720
                    guard let radial = info.radialMap[azKey]
                        ?? info.radialMap[(azKey + 1) % 720]
                        ?? info.radialMap[(azKey - 1 + 720) % 720],
                          radial.gateSizeMeters > 0
                    else { continue }

                    let gateIdx = Int((rangeKm * 1000 - Double(radial.firstGateMeters))
                                      / Double(radial.gateSizeMeters))
                    guard let value = radial.physicalValue(gateIndex: gateIdx) else { continue }

                    // Inverse-distance² weight: closer site dominates, equidistant sites blend.
                    let weight    = 1.0 / max(distSq, 1.0)
                    weightedSum  += Double(value) * weight
                    totalWeight  += weight
                    momentType    = info.momentType
                }

                guard totalWeight > 0 else { continue }
                let blended = Float(weightedSum / totalWeight)
                pixels[row * width + col] = momentColor(value: blended,
                                                        momentType: momentType,
                                                        palette: palette)
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
            logger.error("CGContext creation failed for multi-site overlay (\(sweeps.map { $0.site.icao }))")
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

    private static func momentColor(value: Float, momentType: String, palette: ColorPalette) -> UInt32 {
        switch momentType {
        case "VEL": return velocityColor(ms: value)
        case "ZDR": return zdrColor(db: value)
        case "RHO": return rhoColor(cc: value)
        case "PHI": return phiColor(deg: value)
        case "SW":  return swColor(ms: value)
        default:    return palette.reflectivityColor(dbz: value)
        }
    }

    // NWS velocity color table (m/s; negative = toward radar)
    private static func velocityColor(ms: Float) -> UInt32 {
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

    // Differential reflectivity (dB)
    private static func zdrColor(db: Float) -> UInt32 {
        switch db {
        case ..<(-1):  return rgba(0x00, 0x00, 0xC8)
        case -1 ..< 0: return rgba(0x00, 0x96, 0xFF)
        case 0  ..< 1: return rgba(0x00, 0xC8, 0x96)
        case 1  ..< 2: return rgba(0x00, 0xC8, 0x00)
        case 2  ..< 3: return rgba(0xC8, 0xC8, 0x00)
        case 3  ..< 4: return rgba(0xFF, 0x96, 0x00)
        case 4  ..< 5: return rgba(0xFF, 0x00, 0x00)
        default:       return rgba(0xFF, 0x00, 0xFF)
        }
    }

    // Correlation coefficient (0–1)
    private static func rhoColor(cc: Float) -> UInt32 {
        switch cc {
        case ..<0.7:        return rgba(0x00, 0x00, 0x00)
        case 0.7  ..< 0.85: return rgba(0x96, 0x32, 0x96)
        case 0.85 ..< 0.90: return rgba(0x00, 0x00, 0xFF)
        case 0.90 ..< 0.95: return rgba(0x00, 0xC8, 0xFF)
        case 0.95 ..< 0.97: return rgba(0x00, 0xC8, 0x00)
        case 0.97 ..< 0.99: return rgba(0xFF, 0xFF, 0x00)
        default:            return rgba(0xFF, 0xFF, 0xFF)
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
        case ..<2:    return rgba(0x00, 0x00, 0x96)
        case 2..<4:   return rgba(0x00, 0x64, 0xFF)
        case 4..<6:   return rgba(0x00, 0xC8, 0x96)
        case 6..<8:   return rgba(0x00, 0xC8, 0x00)
        case 8..<10:  return rgba(0xC8, 0xC8, 0x00)
        case 10..<13: return rgba(0xFF, 0x96, 0x00)
        case 13..<16: return rgba(0xFF, 0x00, 0x00)
        default:      return rgba(0xFF, 0xFF, 0xFF)
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
