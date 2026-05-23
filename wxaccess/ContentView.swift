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
                    if appState.isLoading {
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

                Divider()

                // VoiceOver-first data panel
                AccessibilityPanel()
                    .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    ProductPicker()
                    TiltPicker()
                }
            }
        }
        .task {
            await appState.refresh()
        }
    }
}

// MARK: - Toolbar pickers

private struct ProductPicker: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var state = appState
        Picker("Product", selection: $state.selectedProduct) {
            ForEach(RadarProduct.allCases) { product in
                Text(product.displayName).tag(product)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Radar product: \(appState.selectedProduct.displayName)")
        .frame(width: 160)
        .onChange(of: appState.selectedProduct) { _, _ in
            appState.selectCurrentSweep()
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
