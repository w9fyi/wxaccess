import Foundation
import MapKit

// GOES-East CONUS satellite products served as pre-rendered tiles by IEM.
// Tile URL: https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/{layer}/{z}/{x}/{y}.png
// Tiles update every ~5 minutes and carry Cache-Control: max-age=300.

enum GOESSatelliteProduct: String, CaseIterable, Identifiable, Sendable {
    case visible     = "goes_east_conus_ch02"  // 0.64 µm — daytime only
    case infrared    = "goes_east_conus_ch13"  // 10.3 µm clean IR longwave
    case waterVapor  = "goes_east_conus_ch09"  // 6.9 µm mid-level water vapor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .visible:    "Visible"
        case .infrared:   "Infrared"
        case .waterVapor: "Water Vapor"
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .visible:    "GOES-East visible (0.64 µm), daytime only, 5-minute updates"
        case .infrared:   "GOES-East infrared longwave (10.3 µm), 24-hour, 5-minute updates"
        case .waterVapor: "GOES-East mid-level water vapor (6.9 µm), 24-hour, 5-minute updates"
        }
    }
}

// MKTileOverlay backed by the IEM GOES tile cache.
final class GOESTileOverlay: MKTileOverlay, @unchecked Sendable {
    let product: GOESSatelliteProduct

    init(product: GOESSatelliteProduct) {
        self.product = product
        let template = "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/\(product.rawValue)/{z}/{x}/{y}.png"
        super.init(urlTemplate: template)
        canReplaceMapContent = false
        minimumZ = 2
        maximumZ = 8
    }
}
