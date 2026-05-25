import SwiftUI
import MapKit
import CoreLocation
import UserNotifications
import AppKit

@Observable
@MainActor
final class AppState: NSObject {
    // MARK: - Site selection (multi-site)
    // selectedSites is the ordered list of selected sites; selectedSite is the primary.
    var selectedSites: [NEXRADSite] = [NEXRADSiteCatalog.site(icao: "KEWX") ?? NEXRADSiteCatalog.all[0]]
    var selectedSite: NEXRADSite { selectedSites.first ?? NEXRADSiteCatalog.all[0] }

    func toggleSite(_ site: NEXRADSite) {
        if let idx = selectedSites.firstIndex(of: site) {
            guard selectedSites.count > 1 else { return }  // always keep at least one
            selectedSites.remove(at: idx)
        } else {
            selectedSites.append(site)
        }
    }

    var selectedProduct: RadarProduct = .reflectivity
    // currentSweeps holds one sweep per selected site. currentSweep is the primary (first).
    var currentSweeps: [RadarSweep] = []
    var currentSweep: RadarSweep? { currentSweeps.first }
    var availableScans: [ScanEntry] = []
    var selectedScan: ScanEntry?
    var alerts: [NWSAlert] = []
    var outlooks: [SPCOutlook] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var showAbout: Bool = false
    var showBugReport: Bool = false
    var bugReportURL: URL? = nil
    var tiltIndex: Int = 0
    var showSatellite: Bool = false
    var satelliteProduct: GOESSatelliteProduct = .infrared
    var showModelLayer: Bool = false
    var modelProduct: ModelProduct = .mrmsSeamlessHSR
    var modelForecastOffset: ModelForecastOffset = .now
    var placefileURLs: [URL] = []
    var placefiles: [Placefile] = []

    // MARK: - Archive date
    var selectedDate: Date = .now

    // MARK: - New overlay state
    var stormReports: [SPCStormReport] = []
    var mesoscaleDiscussions: [SPCMesoscaleDiscussion] = []
    var surfaceObs: [SurfaceObs] = []
    var showStormReports: Bool = false
    var showMesoscaleDiscussions: Bool = false
    var showSurfaceObs: Bool = false
    var showCountyBorders: Bool = false
    var showRangeRings: Bool = false
    var colorPalette: ColorPalette = .nwsStandard

    // MARK: - Storm cell tracking (SCIT / NST)
    var stormCells: [StormCell] = []
    var showStormCells: Bool = false

    // MARK: - Animation (primary site only)
    var isAnimating: Bool = false
    var animationFrames: [RadarSweep] = []
    var animationLevel3Frames: [Level3RadialSweep] = []
    var animationFrameIndex: Int = 0
    var animationSpeed: AnimationSpeed = .normal
    var isLoadingAnimation: Bool = false
    private var animationTask: Task<Void, Never>?

    var hasAnimationFrames: Bool { !animationFrames.isEmpty || !animationLevel3Frames.isEmpty }

    // MARK: - Level 3 products
    var level3Sweep: Level3RadialSweep?
    var isLoadingLevel3: Bool = false

    // MARK: - Bearing+range probe (accessible keyboard alternative to map tap)
    var probeBearing: Double = 0
    var probeRangeKm: Double = 50.0
    var probeResult: ProbeResult? = nil

    // MARK: - Auto-refresh
    private var autoRefreshTask: Task<Void, Never>?

    // MARK: - Notifications
    private var notifiedAlertIDs: Set<String> = []

    // All tilts from the latest primary-site scan (used for tilt browsing).
    private var allSweeps: [RadarSweep] = []

    // MARK: - Location
    private var locationManager: CLLocationManager?
    var isLocating: Bool = false

    var statusDescription: String {
        if isLoading || isLoadingAnimation || isLoadingLevel3 { return "Loading…" }
        if let l3 = level3Sweep, selectedProduct.isLevel3 {
            return "\(l3.site.icao) \(l3.productCode.displayName) — \(l3.scanTime.formatted(date: .omitted, time: .shortened)) UTC"
        }
        if isAnimating, !animationLevel3Frames.isEmpty {
            let sweep = animationLevel3Frames[animationFrameIndex]
            let frame = "\(animationFrameIndex + 1)/\(animationLevel3Frames.count)"
            return "\(sweep.site.icao) \(sweep.productCode.displayName) — frame \(frame) \(sweep.scanTime.formatted(date: .omitted, time: .shortened)) UTC"
        }
        if isAnimating, !animationFrames.isEmpty {
            let sweep = animationFrames[animationFrameIndex]
            let frame = "\(animationFrameIndex + 1)/\(animationFrames.count)"
            return "\(sweep.site.icao) \(selectedProduct.displayName) \(String(format: "%.1f", sweep.elevationAngle))° — frame \(frame) \(sweep.scanTime.formatted(date: .omitted, time: .shortened)) UTC"
        }
        if currentSweeps.count > 1 {
            let names = currentSweeps.map { $0.site.icao }.joined(separator: ", ")
            let time = currentSweeps.first.map { $0.scanTime.formatted(date: .omitted, time: .shortened) } ?? ""
            return "\(names) — \(time) UTC"
        }
        if let sweep = currentSweep {
            return "\(sweep.site.icao) \(selectedProduct.displayName) \(String(format: "%.1f", sweep.elevationAngle))° — \(sweep.scanTime.formatted(date: .omitted, time: .shortened))"
        }
        return "No data loaded"
    }

    // MARK: - Refresh

    func refresh() async {
        isLoading = true
        errorMessage = nil
        // Old sweeps remain visible during fetch for stable display.
        do {
            async let alertsTask   = AlertsFetcher.shared.fetchAlerts(near: selectedSite.coordinate)
            async let outlooksTask = SPCOutlookFetcher.shared.fetchOutlooks()
            async let mdsTask      = SPCMesoscaleDiscussionFetcher.shared.fetchDiscussions()
            async let reportsTask  = SPCStormReportFetcher.shared.fetchReports()
            async let obsTask      = SurfaceObsFetcher.shared.fetchObs(near: selectedSite)
            async let pfilesTask   = PlacefileFetcher.shared.refresh(existing: placefiles, urls: placefileURLs)
            async let cellsTask    = SCITFetcher.shared.fetchLatest(site: selectedSite)

            // Fetch radar data for all selected sites concurrently.
            let capturedSites = selectedSites
            let capturedDate  = selectedDate
            let capturedTilt  = tiltAngle(for: tiltIndex)
            let capturedProd  = selectedProduct.rawValue

            var fetchedSweeps: [Int: RadarSweep] = [:]
            var primaryScans:  [ScanEntry]       = []
            var primaryAllSweeps: [RadarSweep]   = []

            await withTaskGroup(of: (Int, [RadarSweep], [ScanEntry]).self) { group in
                for (idx, site) in capturedSites.enumerated() {
                    group.addTask {
                        guard let scans = try? await Level2Fetcher.shared.listScans(site: site, date: capturedDate),
                              !scans.isEmpty
                        else { return (idx, [], []) }
                        guard let data = try? await Level2Fetcher.shared.download(entry: scans[0])
                        else { return (idx, [], idx == 0 ? scans : []) }
                        let sweeps = (try? Level2Decoder().decode(data: data)) ?? []
                        return (idx, sweeps, idx == 0 ? scans : [])
                    }
                }
                for await (idx, sweeps, scans) in group {
                    if idx == 0 {
                        primaryScans     = scans
                        primaryAllSweeps = sweeps
                    }
                    let sweep = sweeps.first { $0.momentType == capturedProd && abs($0.elevationAngle - capturedTilt) < 0.5 }
                        ?? sweeps.first { $0.momentType == capturedProd }
                        ?? sweeps.first
                    if let s = sweep { fetchedSweeps[idx] = s }
                }
            }

            // Atomic display update — only change what's shown when new data is ready.
            availableScans = primaryScans
            selectedScan   = primaryScans.first
            allSweeps      = primaryAllSweeps

            let newSweeps = capturedSites.indices.compactMap { fetchedSweeps[$0] }
            if !newSweeps.isEmpty { currentSweeps = newSweeps }

            self.alerts               = try await alertsTask
            self.outlooks             = await outlooksTask
            self.mesoscaleDiscussions = await mdsTask
            self.stormReports         = await reportsTask
            self.surfaceObs           = await obsTask
            self.placefiles           = await pfilesTask
            self.stormCells           = (try? await cellsTask) ?? []
            notifyNewAlerts(self.alerts)
            announceSweepSummary()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        scheduleAutoRefresh()
    }

    // Loads a specific scan entry (user-selected from the scan list).
    // Only affects the primary site; secondary sites keep their existing sweeps.
    func loadScan(_ entry: ScanEntry) async {
        selectedScan = entry
        isLoading    = true
        errorMessage = nil
        do {
            let data = try await Level2Fetcher.shared.download(entry: entry)
            allSweeps = try Level2Decoder().decode(data: data)
            selectCurrentSweep()
            announceSweepSummary()
        } catch {
            errorMessage = error.localizedDescription
            NSAccessibility.post(element: NSApp as AnyObject, notification: .announcementRequested,
                                 userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: "Failed to load radar data: \(error.localizedDescription)"])
        }
        isLoading = false
    }

    // Picks the sweep from allSweeps that best matches the current product and tilt,
    // then stores it as currentSweeps[0] without disturbing secondary-site sweeps.
    func selectCurrentSweep() {
        let target  = tiltAngle(for: tiltIndex)
        let product = selectedProduct.rawValue
        let best    = allSweeps.first { $0.momentType == product && abs($0.elevationAngle - target) < 0.5 }
                   ?? allSweeps.first { $0.momentType == product }
                   ?? allSweeps.first
        guard let sweep = best else { return }

        if currentSweeps.isEmpty {
            currentSweeps = [sweep]
        } else {
            currentSweeps[0] = sweep
        }
    }

    // MARK: - Level 3 products

    func loadLevel3Product(_ product: RadarProduct) async {
        guard let code = product.level3ProductCode else { return }
        isLoadingLevel3 = true
        errorMessage    = nil
        do {
            let entries = try await Level3Fetcher.shared.listScans(site: selectedSite,
                                                                    product: code, limit: 1)
            guard let entry = entries.first else { throw URLError(.fileDoesNotExist) }
            let data     = try await Level3Fetcher.shared.download(entry: entry)
            level3Sweep  = try Level3Decoder().decode(data: data, site: selectedSite, product: code)
            announceSweepSummary()
        } catch {
            errorMessage = error.localizedDescription
            level3Sweep  = nil
        }
        isLoadingLevel3 = false
    }

    // MARK: - Animation (primary site only)

    func toggleAnimation() async {
        if isAnimating { stopAnimation() } else { await startAnimation() }
    }

    func startAnimation() async {
        if selectedProduct.isLevel3 {
            if animationLevel3Frames.isEmpty { await loadLevel3AnimationFrames() }
            guard !animationLevel3Frames.isEmpty else { return }
            isAnimating = true
            animationTask?.cancel()
            animationTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let next = (self.animationFrameIndex + 1) % self.animationLevel3Frames.count
                    self.animationFrameIndex = next
                    self.level3Sweep = self.animationLevel3Frames[next]
                    self.announceAnimationFrameL3(index: next, total: self.animationLevel3Frames.count,
                                                  sweep: self.animationLevel3Frames[next])
                    try? await Task.sleep(nanoseconds: UInt64(self.animationSpeed.interval * 1_000_000_000))
                }
            }
        } else {
            if animationFrames.isEmpty { await loadAnimationFrames() }
            guard !animationFrames.isEmpty else { return }
            isAnimating = true
            animationTask?.cancel()
            animationTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    let next = (self.animationFrameIndex + 1) % self.animationFrames.count
                    self.animationFrameIndex = next
                    // Update only the primary sweep; secondary sites remain fixed.
                    if self.currentSweeps.isEmpty {
                        self.currentSweeps = [self.animationFrames[next]]
                    } else {
                        self.currentSweeps[0] = self.animationFrames[next]
                    }
                    self.announceAnimationFrame(index: next, total: self.animationFrames.count,
                                                sweep: self.animationFrames[next])
                    try? await Task.sleep(nanoseconds: UInt64(self.animationSpeed.interval * 1_000_000_000))
                }
            }
        }
    }

    func stopAnimation() {
        animationTask?.cancel()
        animationTask = nil
        isAnimating   = false
        if !selectedProduct.isLevel3 {
            selectCurrentSweep()
        }
    }

    func stepAnimation(by delta: Int) {
        if selectedProduct.isLevel3, !animationLevel3Frames.isEmpty {
            animationFrameIndex = (animationFrameIndex + delta + animationLevel3Frames.count) % animationLevel3Frames.count
            level3Sweep = animationLevel3Frames[animationFrameIndex]
        } else if !animationFrames.isEmpty {
            animationFrameIndex = (animationFrameIndex + delta + animationFrames.count) % animationFrames.count
            if currentSweeps.isEmpty {
                currentSweeps = [animationFrames[animationFrameIndex]]
            } else {
                currentSweeps[0] = animationFrames[animationFrameIndex]
            }
        }
    }

    func clearAnimationFrames() {
        if isAnimating { stopAnimation() }
        animationFrames        = []
        animationLevel3Frames  = []
        animationFrameIndex    = 0
    }

    private func loadAnimationFrames() async {
        isLoadingAnimation = true
        errorMessage       = nil
        do {
            let scans   = try await Level2Fetcher.shared.listScans(site: selectedSite)
            let recent  = Array(scans.prefix(10).reversed())
            let product = selectedProduct.rawValue
            let target  = tiltAngle(for: tiltIndex)

            var ordered: [(Int, RadarSweep)] = []
            await withTaskGroup(of: (Int, RadarSweep?).self) { group in
                for (idx, scan) in recent.enumerated() {
                    group.addTask {
                        guard let data = try? await Level2Fetcher.shared.download(entry: scan) else { return (idx, nil) }
                        let sweeps = (try? Level2Decoder().decode(data: data)) ?? []
                        let sweep  = sweeps.first { $0.momentType == product && abs($0.elevationAngle - target) < 0.5 }
                            ?? sweeps.first { $0.momentType == product }
                            ?? sweeps.first
                        return (idx, sweep)
                    }
                }
                for await result in group {
                    if let sweep = result.1 { ordered.append((result.0, sweep)) }
                }
            }
            animationFrames     = ordered.sorted { $0.0 < $1.0 }.map { $0.1 }
            animationFrameIndex = max(0, animationFrames.count - 1)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingAnimation = false
    }

    private func loadLevel3AnimationFrames() async {
        guard let code = selectedProduct.level3ProductCode else { return }
        isLoadingAnimation = true
        errorMessage       = nil
        do {
            let entries = try await Level3Fetcher.shared.listScans(site: selectedSite, product: code, limit: 10)
            let recent  = Array(entries.prefix(10).reversed())
            let site    = selectedSite

            var ordered: [(Int, Level3RadialSweep)] = []
            await withTaskGroup(of: (Int, Level3RadialSweep?).self) { group in
                for (idx, entry) in recent.enumerated() {
                    group.addTask {
                        guard let data = try? await Level3Fetcher.shared.download(entry: entry) else { return (idx, nil) }
                        let sweep = try? Level3Decoder().decode(data: data, site: site, product: code)
                        return (idx, sweep)
                    }
                }
                for await result in group {
                    if let sweep = result.1 { ordered.append((result.0, sweep)) }
                }
            }
            animationLevel3Frames = ordered.sorted { $0.0 < $1.0 }.map { $0.1 }
            animationFrameIndex   = max(0, animationLevel3Frames.count - 1)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingAnimation = false
    }

    // MARK: - Gate probe

    func probe(at coordinate: CLLocationCoordinate2D) {
        // Level 3 single-site probe
        if currentSweeps.isEmpty, let l3 = level3Sweep, !l3.radials.isEmpty {
            let (bearing, rangeKm) = bearingAndRangeKm(from: l3.site.coordinate, to: coordinate)
            let cp = compassPoint(bearing)
            guard let radial = l3.radials.min(by: {
                angularDiff($0.startAngle, bearing) < angularDiff($1.startAngle, bearing)
            }) else { return }
            let binIdx = Int((rangeKm - l3.firstBinKm) / l3.binSizeKm)
            let loc    = "\(cp) \(String(format: "%.0f", rangeKm)) km from \(l3.site.icao)"
            if binIdx < 0 || binIdx >= radial.data.count {
                let desc = "Outside radar coverage — \(loc)"
                probeResult = ProbeResult(coordinate: coordinate, bearing: bearing, rangeKm: rangeKm, description: desc)
                announceProbe(desc); return
            }
            let phys   = l3.productCode.physicalValue(code: radial.data[binIdx])
            let valStr = phys.map { String(format: "%.1f \(l3.productCode.physicalUnit)", $0) } ?? "No echo"
            let desc   = "\(l3.productCode.displayName): \(valStr), \(loc)"
            probeResult = ProbeResult(coordinate: coordinate, bearing: bearing, rangeKm: rangeKm, description: desc)
            announceProbe(desc); return
        }

        // Level 2 multi-site probe
        guard !currentSweeps.isEmpty else {
            let desc = "No radar data loaded."
            probeResult = ProbeResult(coordinate: coordinate, bearing: 0, rangeKm: 0, description: desc)
            announceProbe(desc); return
        }
        let primaryCoord = currentSweeps[0].site.coordinate
        let (bearing, rangeKm) = bearingAndRangeKm(from: primaryCoord, to: coordinate)
        let cp = compassPoint(bearing)
        let readings = currentSweeps.map { siteReading(sweep: $0, at: coordinate) }
        let loc  = "\(cp) \(String(format: "%.0f", rangeKm)) km from \(currentSweeps[0].site.icao)"
        let desc = readings.joined(separator: ". ") + ". " + loc
        probeResult = ProbeResult(coordinate: coordinate, bearing: bearing, rangeKm: rangeKm, description: desc)
        announceProbe(desc)
    }

    private func siteReading(sweep: RadarSweep, at coordinate: CLLocationCoordinate2D) -> String {
        guard !sweep.radials.isEmpty else { return "\(sweep.site.icao): no data" }
        let (bearing, rangeKm) = bearingAndRangeKm(from: sweep.site.coordinate, to: coordinate)
        guard let radial = sweep.radials.min(by: {
            angularDiff($0.azimuth, bearing) < angularDiff($1.azimuth, bearing)
        }) else { return "\(sweep.site.icao): no data" }
        let gateIdx = Int(round((rangeKm * 1000 - Double(radial.firstGateMeters)) / Double(radial.gateSizeMeters)))
        if gateIdx < 0 || gateIdx >= radial.numGates {
            return "\(sweep.site.icao): outside coverage"
        }
        let phys   = radial.physicalValue(gateIndex: gateIdx)
        let valStr = phys.map { String(format: "%.1f \(momentUnit(sweep.momentType))", $0) } ?? "no echo"
        return "\(sweep.site.icao): \(valStr)"
    }

    private func announceProbe(_ text: String) {
        NSAccessibility.post(
            element: NSApp as AnyObject,
            notification: .announcementRequested,
            userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: text]
        )
    }

    // MARK: - Sweep summary announcement

    func announceSweepSummary() {
        var parts: [String] = []

        if let sweep = currentSweep, !sweep.radials.isEmpty {
            let timeStr = sweep.scanTime.formatted(date: .omitted, time: .shortened)
            parts.append("\(sweep.site.icao) \(momentLabel(sweep.momentType)) \(String(format: "%.1f", sweep.elevationAngle))° loaded, \(timeStr) UTC")
            if let (maxVal, maxBearing, maxRangeKm) = sweepMaxEcho(sweep: sweep) {
                let cp   = compassPoint(maxBearing)
                let unit = momentUnit(sweep.momentType)
                parts.append("Maximum \(String(format: "%.0f", maxVal)) \(unit) at \(cp) \(Int(maxRangeKm.rounded())) km")
            } else {
                parts.append("No significant echoes")
            }
        } else if let l3 = level3Sweep, !l3.radials.isEmpty {
            let timeStr = l3.scanTime.formatted(date: .omitted, time: .shortened)
            parts.append("\(l3.site.icao) \(l3.productCode.displayName) loaded, \(timeStr) UTC")
            if let (maxVal, maxBearing, maxRangeKm) = level3MaxEcho(sweep: l3) {
                let cp = compassPoint(maxBearing)
                parts.append("Maximum \(String(format: "%.1f", maxVal)) \(l3.productCode.physicalUnit) at \(cp) \(Int(maxRangeKm.rounded())) km")
            } else {
                parts.append("No significant echoes")
            }
        } else {
            return
        }

        if !stormCells.isEmpty {
            parts.append("\(stormCells.count) storm cell\(stormCells.count == 1 ? "" : "s") tracked")
        }

        let warnings = alerts.filter { $0.severity == .extreme || $0.severity == .severe }
        if !warnings.isEmpty {
            parts.append("\(warnings.count) active warning\(warnings.count == 1 ? "" : "s")")
        } else if !alerts.isEmpty {
            parts.append("\(alerts.count) active alert\(alerts.count == 1 ? "" : "s")")
        }

        let text = parts.joined(separator: ". ") + "."
        NSAccessibility.post(element: NSApp as AnyObject, notification: .announcementRequested,
                             userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: text])
    }

    private func sweepMaxEcho(sweep: RadarSweep) -> (value: Float, bearing: Double, rangeKm: Double)? {
        var maxVal: Float?
        var maxBearing = 0.0
        var maxRangeKm = 0.0
        for radial in sweep.radials {
            for i in 0..<radial.numGates {
                guard let v = radial.physicalValue(gateIndex: i) else { continue }
                if maxVal == nil || v > maxVal! {
                    maxVal     = v
                    maxBearing = radial.azimuth
                    maxRangeKm = radial.rangeToGate(index: i)
                }
            }
        }
        guard let v = maxVal else { return nil }
        return (v, maxBearing, maxRangeKm)
    }

    private func level3MaxEcho(sweep: Level3RadialSweep) -> (value: Float, bearing: Double, rangeKm: Double)? {
        var maxVal: Float?
        var maxBearing = 0.0
        var maxRangeKm = 0.0
        for radial in sweep.radials {
            for i in 0..<radial.data.count {
                guard let v = sweep.productCode.physicalValue(code: radial.data[i]) else { continue }
                if maxVal == nil || v > maxVal! {
                    maxVal     = v
                    maxBearing = radial.startAngle
                    maxRangeKm = sweep.firstBinKm + Double(i) * sweep.binSizeKm
                }
            }
        }
        guard let v = maxVal else { return nil }
        return (v, maxBearing, maxRangeKm)
    }

    // MARK: - Bearing+range probe

    func probeAllSites() {
        guard !currentSweeps.isEmpty || level3Sweep != nil else {
            let desc = "No radar data loaded."
            probeResult = ProbeResult(coordinate: selectedSite.coordinate,
                                      bearing: probeBearing, rangeKm: probeRangeKm,
                                      description: desc)
            announceProbe(desc); return
        }
        let primaryCoord = currentSweeps.first?.site.coordinate ?? level3Sweep!.site.coordinate
        let target = destinationCoordinate(from: primaryCoord, bearing: probeBearing, rangeKm: probeRangeKm)
        probe(at: target)
    }

    func jumpToMaxEcho() {
        if let sweep = currentSweeps.first,
           let (_, bearing, rangeKm) = sweepMaxEcho(sweep: sweep) {
            probeBearing = (bearing / 5).rounded() * 5
            probeRangeKm = max(5, (rangeKm / 10).rounded() * 10)
            probeAllSites()
            return
        }
        if let l3 = level3Sweep,
           let (_, bearing, rangeKm) = level3MaxEcho(sweep: l3) {
            probeBearing = (bearing / 5).rounded() * 5
            probeRangeKm = max(5, (rangeKm / 10).rounded() * 10)
            let target = destinationCoordinate(from: l3.site.coordinate,
                                               bearing: probeBearing, rangeKm: probeRangeKm)
            probe(at: target)
            return
        }
        let desc = "No significant echoes detected."
        probeResult = ProbeResult(coordinate: selectedSite.coordinate,
                                  bearing: probeBearing, rangeKm: probeRangeKm, description: desc)
        announceProbe(desc)
    }

    private func destinationCoordinate(from site: CLLocationCoordinate2D,
                                        bearing: Double, rangeKm: Double) -> CLLocationCoordinate2D {
        let R  = 6371.0
        let d  = rangeKm / R
        let b  = bearing * .pi / 180
        let φ1 = site.latitude  * .pi / 180
        let λ1 = site.longitude * .pi / 180
        let φ2 = asin(sin(φ1) * cos(d) + cos(φ1) * sin(d) * cos(b))
        let λ2 = λ1 + atan2(sin(b) * sin(d) * cos(φ1), cos(d) - sin(φ1) * sin(φ2))
        return CLLocationCoordinate2D(latitude: φ2 * 180 / .pi, longitude: λ2 * 180 / .pi)
    }

    private func bearingAndRangeKm(from site: CLLocationCoordinate2D,
                                    to pt: CLLocationCoordinate2D) -> (Double, Double) {
        let lat1 = site.latitude  * .pi / 180
        let lat2 = pt.latitude    * .pi / 180
        let dLon = (pt.longitude  - site.longitude) * .pi / 180
        let dLat = (pt.latitude   - site.latitude)  * .pi / 180
        let y    = sin(dLon) * cos(lat2)
        let x    = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        let R = 6371.0
        let a = sin(dLat/2)*sin(dLat/2) + cos(lat1)*cos(lat2)*sin(dLon/2)*sin(dLon/2)
        return (bearing, R * 2 * atan2(sqrt(a), sqrt(1 - a)))
    }

    private func angularDiff(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    private func compassPoint(_ b: Double) -> String {
        let d = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        return d[Int((b + 11.25) / 22.5) % 16]
    }

    private func momentLabel(_ t: String) -> String {
        switch t {
        case "REF": return "Reflectivity"
        case "VEL": return "Velocity"
        case "SW":  return "Spectrum Width"
        case "ZDR": return "Diff. Reflectivity"
        case "PHI": return "Diff. Phase"
        case "RHO": return "Corr. Coefficient"
        default:    return t
        }
    }

    private func momentUnit(_ t: String) -> String {
        switch t {
        case "REF":       return "dBZ"
        case "VEL", "SW": return "m/s"
        case "ZDR":       return "dB"
        case "PHI":       return "°"
        default:          return ""
        }
    }

    // MARK: - Auto-refresh

    private func scheduleAutoRefresh() {
        autoRefreshTask?.cancel()
        guard UserDefaults.standard.bool(forKey: "autoRefresh") else { return }
        let mins    = UserDefaults.standard.double(forKey: "refreshInterval")
        let seconds = mins > 0 ? mins * 60 : 5 * 60
        autoRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: - VoiceOver frame announcements

    private func announceAnimationFrame(index: Int, total: Int, sweep: RadarSweep) {
        let timeStr = sweep.scanTime.formatted(date: .omitted, time: .shortened)
        let text    = "Frame \(index + 1) of \(total), \(timeStr) UTC"
        NSAccessibility.post(
            element: NSApp as AnyObject,
            notification: .announcementRequested,
            userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: text]
        )
    }

    private func announceAnimationFrameL3(index: Int, total: Int, sweep: Level3RadialSweep) {
        let timeStr = sweep.scanTime.formatted(date: .omitted, time: .shortened)
        let text    = "Frame \(index + 1) of \(total), \(timeStr) UTC"
        NSAccessibility.post(
            element: NSApp as AnyObject,
            notification: .announcementRequested,
            userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: text]
        )
    }

    // MARK: - Alert notifications

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyNewAlerts(_ newAlerts: [NWSAlert]) {
        let highPriority = newAlerts.filter {
            $0.kind == .tornadoWarning || $0.kind == .severeThunderstormWarning
        }
        for alert in highPriority where !notifiedAlertIDs.contains(alert.id) {
            notifiedAlertIDs.insert(alert.id)
            let content       = UNMutableNotificationContent()
            content.title     = alert.event
            content.body      = alert.headline
            content.sound     = .default
            let request       = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    // MARK: - Auto-location

    func selectNearestSite() {
        isLocating = true
        let mgr = CLLocationManager()
        locationManager = mgr
        mgr.delegate = self
        switch mgr.authorizationStatus {
        case .notDetermined:
            mgr.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorized:
            mgr.requestLocation()
        default:
            isLocating    = false
            errorMessage  = "Location access denied. Change in System Settings → Privacy."
        }
    }

    private func didReceiveLocation(_ coordinate: CLLocationCoordinate2D) {
        let nearest = NEXRADSiteCatalog.all.min { a, b in
            haversineKm(a.coordinate, coordinate) < haversineKm(b.coordinate, coordinate)
        }
        if let site = nearest {
            selectedSites = [site]
            Task { await refresh() }
        }
        isLocating = false
    }

    private func haversineKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let R    = 6371.0
        let dLat = (b.latitude  - a.latitude)  * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let sinLat = sin(dLat / 2), sinLon = sin(dLon / 2)
        let h = sinLat * sinLat + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sinLon * sinLon
        return R * 2 * asin(sqrt(h))
    }

    // MARK: - Helpers

    private func tiltAngle(for index: Int) -> Double {
        let tilts: [Double] = [0.5, 1.45, 2.4, 3.35, 4.3]
        return index < tilts.count ? tilts[index] : tilts[0]
    }
}

// MARK: - CLLocationManagerDelegate

extension AppState: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.first?.coordinate else { return }
        Task { @MainActor in self.didReceiveLocation(coord) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "Location failed: \(error.localizedDescription)"
            self.isLocating   = false
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedAlways, .authorized:
                self.locationManager?.requestLocation()
            case .denied, .restricted:
                self.errorMessage = "Location access denied."
                self.isLocating   = false
            default: break
            }
        }
    }
}

// MARK: - Supporting enums

enum RadarProduct: String, CaseIterable, Identifiable {
    // Level 2 moment products
    case reflectivity             = "REF"
    case velocity                 = "VEL"
    case spectrumWidth            = "SW"
    case differentialReflectivity = "ZDR"
    case correlationCoefficient   = "RHO"
    case differentialPhase        = "PHI"
    // Level 3-only composite/derived products
    case echoTops                 = "EET"
    case vil                      = "DVL"
    case stormTotalPrecip         = "STP"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .reflectivity:             "Reflectivity"
        case .velocity:                 "Velocity"
        case .spectrumWidth:            "Spectrum Width"
        case .differentialReflectivity: "Diff. Reflectivity"
        case .correlationCoefficient:   "Corr. Coefficient"
        case .differentialPhase:        "Diff. Phase"
        case .echoTops:                 "Echo Tops"
        case .vil:                      "Digital VIL"
        case .stormTotalPrecip:         "Storm Total Precip"
        }
    }

    var isLevel3: Bool {
        switch self {
        case .echoTops, .vil, .stormTotalPrecip: return true
        default: return false
        }
    }

    var level3ProductCode: Level3ProductCode? {
        switch self {
        case .echoTops:         return .echoTops
        case .vil:              return .digitalVIL
        case .stormTotalPrecip: return .stormTotalPrecip
        default:                return nil
        }
    }

}

// MARK: - Probe result

struct ProbeResult: Sendable {
    let coordinate: CLLocationCoordinate2D
    let bearing: Double
    let rangeKm: Double
    let description: String
}

enum AnimationSpeed: Double, CaseIterable, Identifiable {
    case slow   = 1.2
    case normal = 0.6
    case fast   = 0.25

    var id: Double { rawValue }
    var interval: Double { rawValue }

    var displayName: String {
        switch self {
        case .slow:   "Slow"
        case .normal: "Normal"
        case .fast:   "Fast"
        }
    }
}
