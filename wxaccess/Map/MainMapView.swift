import SwiftUI
import MapKit
import CoreLocation

// NSViewRepresentable wrapper around MKMapView for full overlay control.
struct MainMapView: NSViewRepresentable {
    @Environment(AppState.self) var appState

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = true
        map.isRotateEnabled = false
        map.setRegion(
            MKCoordinateRegion(center: appState.selectedSite.coordinate,
                               latitudinalMeters: 800_000, longitudinalMeters: 800_000),
            animated: false
        )
        map.setAccessibilityLabel("Weather radar map")
        map.setAccessibilityHelp("Click to probe radar value at a location. Use the data panel below for VoiceOver navigation.")
        let tap = NSClickGestureRecognizer(target: context.coordinator,
                                           action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {

        // ── GOES Satellite ─────────────────────────────────────────────
        map.removeOverlays(map.overlays.filter { $0 is GOESTileOverlay })
        if appState.showSatellite {
            map.addOverlay(GOESTileOverlay(product: appState.satelliteProduct), level: .aboveRoads)
        }

        // ── Model layer ────────────────────────────────────────────────
        map.removeOverlays(map.overlays.filter { $0 is ModelTileOverlay })
        if appState.showModelLayer {
            map.addOverlay(
                ModelTileOverlay(product: appState.modelProduct,
                                 forecastMinutes: appState.modelForecastOffset.rawValue),
                level: .aboveRoads
            )
        }

        // ── County / state borders ──────────────────────────────────────
        map.removeOverlays(map.overlays.filter { $0 is CountyBorderTileOverlay })
        if appState.showCountyBorders {
            map.addOverlay(CountyBorderTileOverlay(), level: .aboveRoads)
        }

        // ── Radar sweep (Level 2) ──────────────────────────────────────
        map.removeOverlays(map.overlays.filter { $0 is RadarOverlay })
        if !appState.selectedProduct.isLevel3, let sweep = appState.currentSweep {
            map.addOverlay(RadarOverlay(sweep: sweep, palette: appState.colorPalette),
                           level: .aboveRoads)
        }

        // ── Radar sweep (Level 3) ──────────────────────────────────────
        map.removeOverlays(map.overlays.filter { $0 is Level3Overlay })
        if appState.selectedProduct.isLevel3, let l3 = appState.level3Sweep {
            map.addOverlay(Level3Overlay(sweep: l3), level: .aboveRoads)
        }

        // ── SPC outlooks ───────────────────────────────────────────────
        map.removeOverlays(map.overlays.filter { $0 is SPCOutlookPolygonOverlay })
        for outlook in appState.outlooks {
            for poly in outlook.polygons {
                map.addOverlay(SPCOutlookPolygonOverlay(polygonData: poly), level: .aboveRoads)
            }
        }

        // ── Mesoscale discussions ──────────────────────────────────────
        map.removeOverlays(map.overlays.filter { $0 is SPCMDPolygonOverlay })
        if appState.showMesoscaleDiscussions {
            for md in appState.mesoscaleDiscussions where !md.polygon.isEmpty {
                map.addOverlay(SPCMDPolygonOverlay(discussion: md), level: .aboveRoads)
            }
        }

        // ── Placefiles (lines + polygons) ─────────────────────────────
        map.removeOverlays(map.overlays.filter { $0 is PlacefilePolylineOverlay || $0 is PlacefilePolygonOverlay })
        for placefile in appState.placefiles {
            for item in placefile.items {
                switch item.geometry {
                case .line(let pts, let w) where pts.count >= 2:
                    map.addOverlay(PlacefilePolylineOverlay(item: item, points: pts, width: w), level: .aboveRoads)
                case .polygon(let pts) where pts.count >= 3:
                    map.addOverlay(PlacefilePolygonOverlay(item: item, points: pts), level: .aboveRoads)
                default: break
                }
            }
        }

        // ── Alert polygons ─────────────────────────────────────────────
        map.removeOverlays(map.overlays.filter { $0 is AlertPolygon })
        for alert in appState.alerts where !alert.polygon.isEmpty {
            map.addOverlay(AlertPolygon(alert: alert), level: .aboveLabels)
        }

        // ── Range rings ────────────────────────────────────────────────
        map.removeOverlays(map.overlays.filter { $0 is RangeRingOverlay })
        if appState.showRangeRings {
            let center = appState.selectedSite.coordinate
            for km in [50.0, 100.0, 150.0, 230.0] {
                map.addOverlay(RangeRingOverlay.make(center: center, distanceKm: km),
                               level: .aboveRoads)
            }
        }

        // ── Storm cell tracks ──────────────────────────────────────
        map.removeOverlays(map.overlays.filter { $0 is StormCellTrackOverlay })
        if appState.showStormCells {
            for cell in appState.stormCells {
                if cell.past.count >= 2 {
                    let pts = cell.past + [cell.current]
                    map.addOverlay(StormCellTrackOverlay(coords: pts, type: .past),
                                   level: .aboveLabels)
                }
                if let f30 = cell.forecast30min {
                    var pts = [cell.current, f30]
                    if let f60 = cell.forecast60min { pts.append(f60) }
                    map.addOverlay(StormCellTrackOverlay(coords: pts, type: .forecast),
                                   level: .aboveLabels)
                }
            }
        }

        // ── Storm cell annotations ─────────────────────────────────
        map.removeAnnotations(map.annotations.filter { $0 is StormCellAnnotation })
        if appState.showStormCells {
            map.addAnnotations(appState.stormCells.map { StormCellAnnotation(cell: $0) })
        }

        // ── Probe pin ─────────────────────────────────────────────────
        map.removeAnnotations(map.annotations.filter { $0 is ProbeAnnotation })
        if let probe = appState.probeResult {
            map.addAnnotation(ProbeAnnotation(probe: probe))
        }

        // ── Annotations ────────────────────────────────────────────────
        map.removeAnnotations(map.annotations.filter { $0 is StormReportAnnotation })
        if appState.showStormReports {
            map.addAnnotations(appState.stormReports.map { StormReportAnnotation(report: $0) })
        }

        map.removeAnnotations(map.annotations.filter { $0 is SurfaceObsAnnotation })
        if appState.showSurfaceObs {
            map.addAnnotations(appState.surfaceObs.map { SurfaceObsAnnotation(obs: $0) })
        }

        map.removeAnnotations(map.annotations.filter { $0 is PlacefileAnnotation })
        for placefile in appState.placefiles {
            for item in placefile.items {
                if case .point = item.geometry {
                    map.addAnnotation(PlacefileAnnotation(item: item))
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(appState: appState) }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, NSGestureRecognizerDelegate, @unchecked Sendable {
        private let appState: AppState

        init(appState: AppState) {
            self.appState = appState
            super.init()
        }

        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                               shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
            guard let map = gestureRecognizer.view else { return true }
            let point = map.convert(event.locationInWindow, from: nil)
            var view: NSView? = map.hitTest(point)
            while let v = view {
                if v is MKAnnotationView { return false }
                view = v.superview
            }
            return true
        }

        @objc func handleTap(_ recognizer: NSClickGestureRecognizer) {
            guard let map = recognizer.view as? MKMapView else { return }
            let coord = map.convert(recognizer.location(in: map), toCoordinateFrom: map)
            Task { @MainActor [appState] in appState.probe(at: coord) }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? GOESTileOverlay         { return MKTileOverlayRenderer(tileOverlay: tile) }
            if let tile = overlay as? ModelTileOverlay        { return MKTileOverlayRenderer(tileOverlay: tile) }
            if let tile = overlay as? CountyBorderTileOverlay { return MKTileOverlayRenderer(tileOverlay: tile) }
            if let radar = overlay as? RadarOverlay           { return RadarOverlayRenderer(overlay: radar) }
            if let l3    = overlay as? Level3Overlay          { return Level3OverlayRenderer(overlay: l3) }

            if let pfLine = overlay as? PlacefilePolylineOverlay {
                let r = MKPolylineRenderer(polyline: pfLine.polyline)
                r.strokeColor = pfLine.nsColor
                r.lineWidth   = CGFloat(pfLine.lineWidth)
                return r
            }
            if let pfPoly = overlay as? PlacefilePolygonOverlay {
                let r = MKPolygonRenderer(polygon: pfPoly.polygon)
                r.strokeColor = pfPoly.nsStrokeColor
                r.fillColor   = pfPoly.nsFillColor
                r.lineWidth   = 1.5
                return r
            }
            if let outlookPoly = overlay as? SPCOutlookPolygonOverlay {
                let r = MKPolygonRenderer(polygon: outlookPoly.polygon)
                r.strokeColor = outlookPoly.strokeNSColor
                r.fillColor   = outlookPoly.fillNSColor
                r.lineWidth   = 1.5
                return r
            }
            if let mdPoly = overlay as? SPCMDPolygonOverlay {
                let r = MKPolygonRenderer(polygon: mdPoly.polygon)
                r.strokeColor = NSColor(red: 0.9, green: 0.7, blue: 0, alpha: 0.9)
                r.fillColor   = NSColor(red: 0.9, green: 0.7, blue: 0, alpha: 0.08)
                r.lineWidth   = 1.5
                r.lineDashPattern = [6, 4]
                return r
            }
            if let track = overlay as? StormCellTrackOverlay {
                let r = MKPolylineRenderer(polyline: track.polyline)
                switch track.trackType {
                case .past:
                    r.strokeColor    = NSColor.white.withAlphaComponent(0.6)
                    r.lineWidth      = 1.5
                    r.lineDashPattern = [6, 4]
                case .forecast:
                    r.strokeColor    = NSColor.systemOrange.withAlphaComponent(0.8)
                    r.lineWidth      = 1.5
                    r.lineDashPattern = [3, 4]
                }
                return r
            }
            if let ring = overlay as? RangeRingOverlay {
                let r = MKCircleRenderer(circle: ring)
                r.strokeColor    = NSColor.white.withAlphaComponent(0.55)
                r.fillColor      = .clear
                r.lineWidth      = 1
                r.lineDashPattern = [4, 4]
                return r
            }
            if let alertPoly = overlay as? AlertPolygon {
                let r = MKPolygonRenderer(polygon: alertPoly.polygon)
                r.strokeColor = alertPoly.strokeColor
                r.fillColor   = alertPoly.fillColor
                r.lineWidth   = alertPoly.strokeLineWidth
                if alertPoly.isDashed { r.lineDashPattern = [8, 5] }
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let report = annotation as? StormReportAnnotation {
                let id   = "stormReport"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation      = annotation
                view.displayPriority = .required
                view.titleVisibility = .hidden
                switch report.report.kind {
                case .tornado:  view.glyphText = "T"; view.markerTintColor = .red
                case .hail:     view.glyphText = "H"; view.markerTintColor = .systemGreen
                case .wind:     view.glyphText = "W"; view.markerTintColor = .systemBlue
                }
                view.setAccessibilityLabel(report.report.accessibilityLabel)
                return view
            }

            if let obsAnnot = annotation as? SurfaceObsAnnotation {
                let id   = "surfaceObs"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation      = annotation
                view.displayPriority = .defaultLow
                view.titleVisibility = .visible
                let c = obsAnnot.obs.flightCategory.color
                view.markerTintColor = NSColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
                view.glyphText       = obsAnnot.obs.stationId.prefix(3).description
                view.setAccessibilityLabel(obsAnnot.obs.accessibilityLabel)
                return view
            }

            if let pfAnnot = annotation as? PlacefileAnnotation {
                let id   = "placefile"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation      = annotation
                view.displayPriority = .defaultLow
                view.titleVisibility = .hidden
                let c = pfAnnot.item.color
                view.markerTintColor = NSColor(red: Double(c.r)/255, green: Double(c.g)/255,
                                               blue:  Double(c.b)/255, alpha: Double(c.a)/255)
                view.setAccessibilityLabel(pfAnnot.item.accessibilityLabel)
                return view
            }

            if let cellAnnot = annotation as? StormCellAnnotation {
                let id   = "stormCell"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation      = cellAnnot
                view.displayPriority = .required
                view.titleVisibility = .hidden
                view.markerTintColor = NSColor.systemOrange
                view.glyphText       = cellAnnot.cell.id
                view.setAccessibilityLabel(cellAnnot.cell.accessibilityDescription)
                return view
            }
            if let probeAnnot = annotation as? ProbeAnnotation {
                let id   = "probe"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view.annotation      = probeAnnot
                view.displayPriority = .required
                view.titleVisibility = .hidden
                view.markerTintColor = NSColor(white: 1, alpha: 0.9)
                view.glyphText       = "+"
                view.setAccessibilityLabel(probeAnnot.probe.description)
                return view
            }

            return nil
        }
    }
}

// MARK: - County border tile overlay

final class CountyBorderTileOverlay: MKTileOverlay, @unchecked Sendable {
    init() {
        super.init(urlTemplate:
            "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/uscounties/{z}/{x}/{y}.png")
        canReplaceMapContent = false
        minimumZ = 4
        maximumZ = 12
    }
}

// MARK: - SPC Mesoscale Discussion polygon overlay

final class SPCMDPolygonOverlay: NSObject, MKOverlay, @unchecked Sendable {
    let discussion: SPCMesoscaleDiscussion
    let polygon: MKPolygon

    var coordinate: CLLocationCoordinate2D { polygon.coordinate }
    var boundingMapRect: MKMapRect          { polygon.boundingMapRect }

    init(discussion: SPCMesoscaleDiscussion) {
        self.discussion = discussion
        var pts = discussion.polygon
        self.polygon = MKPolygon(coordinates: &pts, count: pts.count)
        super.init()
    }
}

// MARK: - Range ring overlay

final class RangeRingOverlay: MKCircle, @unchecked Sendable {
    var distanceKm: Double = 0

    static func make(center: CLLocationCoordinate2D, distanceKm: Double) -> RangeRingOverlay {
        let ring = RangeRingOverlay(center: center, radius: distanceKm * 1000)
        ring.distanceKm = distanceKm
        return ring
    }
}

// MARK: - Placefile overlays

final class PlacefilePolylineOverlay: NSObject, MKOverlay, @unchecked Sendable {
    let item: PlacefileItem
    let polyline: MKPolyline
    let lineWidth: Int

    var coordinate: CLLocationCoordinate2D { polyline.coordinate }
    var boundingMapRect: MKMapRect          { polyline.boundingMapRect }

    var nsColor: NSColor {
        let c = item.color
        return NSColor(red: Double(c.r)/255, green: Double(c.g)/255,
                       blue: Double(c.b)/255, alpha: Double(c.a)/255)
    }

    init(item: PlacefileItem, points: [CLLocationCoordinate2D], width: Int) {
        self.item = item; self.lineWidth = width
        var pts = points
        self.polyline = MKPolyline(coordinates: &pts, count: pts.count)
        super.init()
    }
}

final class PlacefilePolygonOverlay: NSObject, MKOverlay, @unchecked Sendable {
    let item: PlacefileItem
    let polygon: MKPolygon

    var coordinate: CLLocationCoordinate2D { polygon.coordinate }
    var boundingMapRect: MKMapRect          { polygon.boundingMapRect }

    var nsStrokeColor: NSColor {
        let c = item.color
        return NSColor(red: Double(c.r)/255, green: Double(c.g)/255,
                       blue: Double(c.b)/255, alpha: Double(c.a)/255)
    }
    var nsFillColor: NSColor { nsStrokeColor.withAlphaComponent(0.15) }

    init(item: PlacefileItem, points: [CLLocationCoordinate2D]) {
        self.item = item
        var pts = points
        self.polygon = MKPolygon(coordinates: &pts, count: pts.count)
        super.init()
    }
}

// MARK: - SPC outlook polygon overlay

final class SPCOutlookPolygonOverlay: NSObject, MKOverlay, @unchecked Sendable {
    let polygonData: SPCOutlookPolygonData
    let polygon: MKPolygon

    var coordinate: CLLocationCoordinate2D { polygon.coordinate }
    var boundingMapRect: MKMapRect          { polygon.boundingMapRect }

    var strokeNSColor: NSColor {
        let c = polygonData.category.color
        return NSColor(red: c.r, green: c.g, blue: c.b, alpha: 0.9)
    }
    var fillNSColor: NSColor {
        let c = polygonData.category.color
        return NSColor(red: c.r, green: c.g, blue: c.b, alpha: 0.12)
    }

    init(polygonData: SPCOutlookPolygonData) {
        self.polygonData = polygonData
        let coords = polygonData.rings.first ?? []
        self.polygon = MKPolygon(coordinates: coords, count: coords.count)
        super.init()
    }
}

// MARK: - Alert polygon overlay

final class AlertPolygon: NSObject, MKOverlay, @unchecked Sendable {
    let alert: NWSAlert
    let polygon: MKPolygon

    var coordinate: CLLocationCoordinate2D { polygon.coordinate }
    var boundingMapRect: MKMapRect          { polygon.boundingMapRect }

    var strokeColor: NSColor {
        switch alert.kind {
        case .tornadoWarning:             return .red
        case .severeThunderstormWarning:  return NSColor(red: 1,   green: 0.84, blue: 0,    alpha: 1)
        case .tornadoWatch:               return NSColor(red: 1,   green: 0.4,  blue: 0.4,  alpha: 1)
        case .severeThunderstormWatch:    return .yellow
        case .flashFloodWarning:          return NSColor(red: 0,   green: 0.7,  blue: 0,    alpha: 1)
        case .flashFloodWatch:            return NSColor(red: 0,   green: 0.45, blue: 0.1,  alpha: 1)
        case .other:
            switch alert.severity {
            case .extreme:  return .red
            case .severe:   return .orange
            case .moderate: return .yellow
            default:        return .white
            }
        }
    }

    var fillColor: NSColor { strokeColor.withAlphaComponent(0.12) }

    var strokeLineWidth: CGFloat {
        switch alert.kind {
        case .tornadoWarning, .severeThunderstormWarning: return 2.5
        default: return 1.5
        }
    }

    var isDashed: Bool {
        switch alert.kind {
        case .tornadoWatch, .severeThunderstormWatch, .flashFloodWatch: return true
        default: return false
        }
    }

    init(alert: NWSAlert) {
        self.alert = alert
        self.polygon = MKPolygon(coordinates: alert.polygon, count: alert.polygon.count)
        super.init()
    }
}

// MARK: - Annotation models

final class ProbeAnnotation: NSObject, MKAnnotation, @unchecked Sendable {
    let probe: ProbeResult
    var coordinate: CLLocationCoordinate2D { probe.coordinate }
    var title: String? { probe.description }
    init(probe: ProbeResult) { self.probe = probe; super.init() }
}

final class StormReportAnnotation: NSObject, MKAnnotation, @unchecked Sendable {
    let report: SPCStormReport
    var coordinate: CLLocationCoordinate2D { report.coordinate }
    var title:    String? { report.shortTitle }
    var subtitle: String? { "\(report.location), \(report.state) \(report.time) UTC" }
    init(report: SPCStormReport) { self.report = report; super.init() }
}

final class SurfaceObsAnnotation: NSObject, MKAnnotation, @unchecked Sendable {
    let obs: SurfaceObs
    var coordinate: CLLocationCoordinate2D { obs.coordinate }
    var title:    String? { obs.stationId }
    var subtitle: String? { obs.accessibilityLabel }
    init(obs: SurfaceObs) { self.obs = obs; super.init() }
}

final class PlacefileAnnotation: NSObject, MKAnnotation, @unchecked Sendable {
    let item: PlacefileItem
    var coordinate: CLLocationCoordinate2D
    var title:    String? { item.label.isEmpty ? nil : item.label }
    var subtitle: String? { item.detail.isEmpty ? nil : item.detail }
    init(item: PlacefileItem) {
        self.item = item
        self.coordinate = item.coordinate
        super.init()
    }
}

// MARK: - Storm cell annotations and overlays

final class StormCellAnnotation: NSObject, MKAnnotation, @unchecked Sendable {
    let cell: StormCell
    var coordinate: CLLocationCoordinate2D { cell.current }
    var title: String? { cell.id }
    init(cell: StormCell) { self.cell = cell; super.init() }
}

final class StormCellTrackOverlay: NSObject, MKOverlay, @unchecked Sendable {
    enum TrackType { case past, forecast }
    let trackType: TrackType
    let polyline: MKPolyline

    var coordinate: CLLocationCoordinate2D { polyline.coordinate }
    var boundingMapRect: MKMapRect          { polyline.boundingMapRect }

    init(coords: [CLLocationCoordinate2D], type: TrackType) {
        self.trackType = type
        var pts = coords
        self.polyline = MKPolyline(coordinates: &pts, count: pts.count)
        super.init()
    }
}
