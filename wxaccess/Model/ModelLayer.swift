import Foundation
import MapKit

// Available model/analysis tile products served by IEM.
// Tile URL: https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/{layerName}/{z}/{x}/{y}.png
//
// HRRR forecast offset is expressed as zero-padded minutes: F0060 = +1h, F0120 = +2h, etc.
// "0" suffix = latest model run; a specific YYYYMMDDHHMI timestamp selects archived runs.

enum ModelProduct: String, CaseIterable, Identifiable, Sendable {
    case hrrrReflectivity         = "hrrr_refd"
    case hrrrReflectivityPrecip   = "hrrr_refp"
    case mrmsSeamlessHSR          = "mrms_lcref"
    case mrmsPrecip1h             = "mrms_p1h"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hrrrReflectivity:       "HRRR Simulated Reflectivity"
        case .hrrrReflectivityPrecip: "HRRR Reflectivity + Precip Type"
        case .mrmsSeamlessHSR:        "MRMS Composite Radar"
        case .mrmsPrecip1h:           "MRMS 1-h Precipitation"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .hrrrReflectivity:
            "HRRR simulated radar reflectivity, updated hourly, forecasts to +18 hours"
        case .hrrrReflectivityPrecip:
            "HRRR simulated reflectivity with precipitation type overlaid, forecasts to +18 hours"
        case .mrmsSeamlessHSR:
            "MRMS seamless hybrid-scan radar composite, near real-time merged from all CONUS sites"
        case .mrmsPrecip1h:
            "MRMS 1-hour quantitative precipitation estimate, near real-time"
        }
    }

    // Whether this product supports a forecast time offset.
    var supportsForecast: Bool {
        switch self {
        case .hrrrReflectivity, .hrrrReflectivityPrecip: true
        case .mrmsSeamlessHSR, .mrmsPrecip1h: false
        }
    }

    // Build the IEM layer name for the given forecast offset (in minutes).
    func layerName(forecastMinutes: Int) -> String {
        switch self {
        case .hrrrReflectivity:
            return "hrrr::REFD-F\(String(format: "%04d", forecastMinutes))-0"
        case .hrrrReflectivityPrecip:
            return "hrrr::REFP-F\(String(format: "%04d", forecastMinutes))-0"
        case .mrmsSeamlessHSR:
            return "mrms::lcref-0"
        case .mrmsPrecip1h:
            return "mrms::p1h-0"
        }
    }
}

// Named forecast offsets shown in the picker (HRRR products only).
enum ModelForecastOffset: Int, CaseIterable, Identifiable, Sendable {
    case now    = 0
    case plus1h = 60
    case plus2h = 120
    case plus3h = 180
    case plus6h = 360
    case plus12h = 720
    case plus18h = 1080

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .now:     "Analysis (Now)"
        case .plus1h:  "+1 hour"
        case .plus2h:  "+2 hours"
        case .plus3h:  "+3 hours"
        case .plus6h:  "+6 hours"
        case .plus12h: "+12 hours"
        case .plus18h: "+18 hours"
        }
    }
}

// MKTileOverlay backed by an IEM model/analysis product.
final class ModelTileOverlay: MKTileOverlay, @unchecked Sendable {
    let product: ModelProduct
    let forecastMinutes: Int

    init(product: ModelProduct, forecastMinutes: Int = 0) {
        self.product = product
        self.forecastMinutes = forecastMinutes
        let layer = product.layerName(forecastMinutes: forecastMinutes)
        let template = "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/\(layer)/{z}/{x}/{y}.png"
        super.init(urlTemplate: template)
        canReplaceMapContent = false
        minimumZ = 2
        maximumZ = 8
    }
}
