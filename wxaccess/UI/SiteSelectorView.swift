import SwiftUI
import CoreLocation

struct SiteSelectorView: View {
    @Environment(AppState.self) var appState
    @State private var search = ""
    @State private var selectionId: String? = nil

    private var filtered: [NEXRADSite] {
        guard !search.isEmpty else { return NEXRADSiteCatalog.all }
        let q = search.lowercased()
        return NEXRADSiteCatalog.all.filter {
            $0.icao.lowercased().contains(q)
            || $0.name.lowercased().contains(q)
            || $0.state.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Nearest-site button
            Button {
                appState.selectNearestSite()
            } label: {
                HStack {
                    if appState.isLocating {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "location.fill")
                    }
                    Text(appState.isLocating ? "Locating…" : "Use My Location")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isLocating)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .accessibilityLabel("Select nearest radar site to my current location")
            .accessibilityHint("Requires location permission")

            Divider()

            List(filtered, id: \.id, selection: $selectionId) { site in
                let isActive = appState.selectedSite.id == site.id
                Button {
                    selectionId = site.id
                    appState.selectedSite = site
                    Task { await appState.refresh() }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(site.icao)
                            .font(.body.monospaced().weight(.semibold))
                        Text(site.name + ", " + site.state)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isActive
                    ? "\(site.displayName), currently loaded"
                    : site.displayName)
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(isActive ? "" : "Load radar data for this site")
            }
            .searchable(text: $search, prompt: "ICAO, city, or state")
        }
        .navigationTitle("Radar Sites")
        .onAppear { selectionId = appState.selectedSite.id }
        .onChange(of: appState.selectedSite.id) { _, newId in
            selectionId = newId
        }
    }
}
