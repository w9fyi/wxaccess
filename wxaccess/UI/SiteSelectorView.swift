import SwiftUI
import CoreLocation

struct SiteSelectorView: View {
    @Environment(AppState.self) var appState
    @State private var search = ""

    private var filtered: [NEXRADSite] {
        if search.isEmpty { return NEXRADSiteCatalog.all }
        let q = search.lowercased()
        return NEXRADSiteCatalog.all.filter { site in
            site.icao.lowercased().contains(q)
            || site.name.lowercased().contains(q)
            || site.state.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
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

            if appState.selectedSites.count > 1 {
                Text("\(appState.selectedSites.count) sites selected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                    .accessibilityLabel("\(appState.selectedSites.count) radar sites selected")
            }

            Divider()

            List(filtered, id: \.id) { site in
                SiteRow(
                    site: site,
                    isSelected: appState.selectedSites.contains(site),
                    isSoleSelection: appState.selectedSites.count == 1 && appState.selectedSites.contains(site)
                ) {
                    appState.toggleSite(site)
                    Task { await appState.refresh() }
                }
            }
            .searchable(text: $search, prompt: "ICAO, city, or state")
        }
        .navigationTitle("Radar Sites")
    }
}

// MARK: - Row

private struct SiteRow: View {
    let site: NEXRADSite
    let isSelected: Bool
    let isSoleSelection: Bool  // true when this is the only selected site (can't deselect)
    let onTap: () -> Void

    private var rowBackground: Color {
        isSelected ? Color.accentColor.opacity(0.15) : Color.clear
    }

    private var a11yLabel: String {
        if isSelected { return "\(site.displayName), selected" }
        return site.displayName
    }

    private var a11yHint: String {
        if isSoleSelection { return "At least one site must remain selected" }
        if isSelected      { return "Remove from selection" }
        return "Add to selection"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .imageScale(.medium)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(site.icao)
                        .font(.body.monospaced().weight(.semibold))
                    Text(site.name + ", " + site.state)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(rowBackground)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(a11yHint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}
