import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        NavigationSplitView {
            SiteSelectorView()
                .frame(minWidth: 220)
        } detail: {
            VStack(spacing: 0) {
                // Status bar
                HStack {
                    if appState.isLoading || appState.isLoadingLevel3 {
                        ProgressView().scaleEffect(0.7)
                    }
                    Text(appState.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Radar status: \(appState.statusDescription)")
                    Spacer()
                    if let error = appState.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: \(error)")
                    }
                    Button {
                        Task { await appState.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r")
                    .accessibilityLabel("Refresh radar data")
                    .disabled(appState.isLoading)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.bar)

                // Map
                MainMapView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)  // map canvas; data in AccessibilityPanel
                    .overlay(alignment: .bottomTrailing) {
                        if appState.currentSweep != nil ||
                           (appState.level3Sweep != nil && appState.selectedProduct.isLevel3) {
                            ColorScaleLegendView(product: appState.selectedProduct,
                                                 palette: appState.colorPalette)
                                .padding([.bottom, .trailing], 12)
                        }
                    }

                Divider()

                // VoiceOver-first data panel
                AccessibilityPanel()
                    .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    ArchiveDatePicker()
                    ScanTimePicker()
                    AnimationControls()
                    OverlaysPicker()
                    ModelLayerPicker()
                    SatellitePicker()
                    ProductPicker()
                    TiltPicker()
                }
            }
        }
        .sheet(isPresented: $state.showAbout) {
            AboutView()
        }
        .task {
            appState.requestNotificationPermission()
            await appState.refresh()
        }
    }
}

// MARK: - Overlays menu

private struct OverlaysPicker: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        Menu {
            Toggle("County Borders",        isOn: $state.showCountyBorders)
            Toggle("Range Rings",           isOn: $state.showRangeRings)
            Divider()
            Toggle("Storm Reports",         isOn: $state.showStormReports)
            Toggle("Storm Cells",           isOn: $state.showStormCells)
            Toggle("Mesoscale Discussions", isOn: $state.showMesoscaleDiscussions)
            Divider()
            Toggle("Surface Observations",  isOn: $state.showSurfaceObs)
        } label: {
            Label("Overlays", systemImage: "map.fill")
        }
        .accessibilityLabel("Overlay layers menu")
    }
}

// MARK: - Toolbar pickers

private struct AnimationControls: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        HStack(spacing: 4) {
            // Step back
            Button {
                appState.stepAnimation(by: -1)
            } label: {
                Image(systemName: "backward.frame")
            }
            .disabled(!appState.hasAnimationFrames)
            .accessibilityLabel("Previous frame")

            // Play / Stop
            Button {
                Task { await appState.toggleAnimation() }
            } label: {
                if appState.isLoadingAnimation {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Image(systemName: appState.isAnimating ? "stop.fill" : "play.fill")
                }
            }
            .accessibilityLabel(appState.isAnimating ? "Stop animation" : "Play loop animation")
            .disabled(appState.isLoadingAnimation)

            // Step forward
            Button {
                appState.stepAnimation(by: 1)
            } label: {
                Image(systemName: "forward.frame")
            }
            .disabled(!appState.hasAnimationFrames)
            .accessibilityLabel("Next frame")

            if appState.isAnimating || appState.hasAnimationFrames {
                Picker("Speed", selection: $state.animationSpeed) {
                    ForEach(AnimationSpeed.allCases) { speed in
                        Text(speed.displayName).tag(speed)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 80)
                .accessibilityLabel("Animation speed: \(appState.animationSpeed.displayName)")
            }
        }
    }
}

private struct ModelLayerPicker: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        HStack(spacing: 4) {
            Toggle(isOn: $state.showModelLayer) {
                Label("Model", systemImage: "chart.xyaxis.line")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Model layer: \(appState.showModelLayer ? "on" : "off")")

            if appState.showModelLayer {
                Picker("Model product", selection: $state.modelProduct) {
                    ForEach(ModelProduct.allCases) { product in
                        Text(product.displayName).tag(product)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                .accessibilityLabel("Model product: \(appState.modelProduct.displayName)")

                if appState.modelProduct.supportsForecast {
                    Picker("Forecast time", selection: $state.modelForecastOffset) {
                        ForEach(ModelForecastOffset.allCases) { offset in
                            Text(offset.displayName).tag(offset)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .accessibilityLabel("Forecast time: \(appState.modelForecastOffset.displayName)")
                }
            }
        }
    }
}

private struct SatellitePicker: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        HStack(spacing: 4) {
            Toggle(isOn: $state.showSatellite) {
                Label("Satellite", systemImage: "satellite")
            }
            .toggleStyle(.button)
            .accessibilityLabel("Satellite layer: \(appState.showSatellite ? "on" : "off")")

            if appState.showSatellite {
                Picker("Satellite product", selection: $state.satelliteProduct) {
                    ForEach(GOESSatelliteProduct.allCases) { product in
                        Text(product.displayName).tag(product)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .accessibilityLabel("Satellite product: \(appState.satelliteProduct.displayName)")
            }
        }
    }
}

private struct ProductPicker: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        Picker("Product", selection: $state.selectedProduct) {
            Section("Level 2") {
                ForEach(RadarProduct.allCases.filter { !$0.isLevel3 }) { product in
                    Text(product.displayName).tag(product)
                }
            }
            Section("Level 3") {
                ForEach(RadarProduct.allCases.filter { $0.isLevel3 }) { product in
                    Text(product.displayName).tag(product)
                }
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Radar product: \(appState.selectedProduct.displayName)")
        .frame(width: 170)
        .onChange(of: appState.selectedProduct) { _, newProduct in
            appState.clearAnimationFrames()
            if newProduct.isLevel3 {
                Task { await appState.loadLevel3Product(newProduct) }
            } else {
                appState.level3Sweep = nil
                appState.selectCurrentSweep()
            }
        }
    }
}

private struct TiltPicker: View {
    @Environment(AppState.self) var appState

    private let tilts = ["0.5°", "1.5°", "2.4°", "3.4°", "4.3°"]

    var body: some View {
        @Bindable var state = appState
        Picker("Tilt", selection: $state.tiltIndex) {
            ForEach(tilts.indices, id: \.self) { i in
                Text(tilts[i]).tag(i)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Elevation tilt: \(tilts[appState.tiltIndex])")
        .frame(width: 80)
        .onChange(of: appState.tiltIndex) { _, _ in
            appState.selectCurrentSweep()
        }
    }
}

// MARK: - Archive date + scan time controls

private struct ArchiveDatePicker: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        DatePicker(
            "Date",
            selection: $state.selectedDate,
            in: ...Date.now,
            displayedComponents: .date
        )
        .labelsHidden()
        .datePickerStyle(.compact)
        .frame(width: 115)
        .accessibilityLabel("Archive date: \(appState.selectedDate.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityHint("Change to load scans for a different date")
        .onChange(of: appState.selectedDate) { _, _ in
            Task { await appState.refresh() }
        }
    }
}

private struct ScanTimePicker: View {
    @Environment(AppState.self) var appState

    // Custom binding: reading uses selectedScan for display; writing calls loadScan
    // so the Picker's set-side (user action only) triggers the actual download
    // without the double-load that onChange would cause when refresh() sets selectedScan.
    private var scanBinding: Binding<ScanEntry?> {
        Binding(
            get: { appState.selectedScan },
            set: { newScan in
                guard let scan = newScan else { return }
                Task { await appState.loadScan(scan) }
            }
        )
    }

    var body: some View {
        Picker("Scan time", selection: scanBinding) {
            ForEach(appState.availableScans) { scan in
                Text(scan.scanTime.formatted(date: .omitted, time: .shortened) + " UTC")
                    .tag(Optional(scan))
            }
        }
        .pickerStyle(.menu)
        .frame(width: 110)
        .disabled(appState.isLoading || appState.availableScans.isEmpty)
        .accessibilityLabel("Scan time: \(appState.selectedScan.map { $0.scanTime.formatted(date: .omitted, time: .shortened) + " UTC" } ?? "none")")
        .accessibilityHint("Select a scan time to load")
    }
}
