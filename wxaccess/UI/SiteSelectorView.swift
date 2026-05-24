import SwiftUI
import CoreLocation

struct SiteSelectorView: View {
    @Environment(AppState.self) var appState
    @State private var search = ""

    private var filtered: [NEXRADSite] {
        if search.isEmpty { return NEXRADSiteCatalog.all }
        let q = search.lowercased()
        return NEXRADSiteCatalog.all.filter { site in
            let matchIcao  = site.icao.lowercased().contains(q)
            let matchName  = site.name.lowercased().contains(q)
            let matchState = site.state.lowercased().contains(q)
            return matchIcao || matchName || matchState
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

            Divider()

            // No selection: binding — VoiceOver VO+Space reaches each Button
            // directly without List row-selection interception.
            List(filtered, id: \.id) { site in
                SiteRow(site: site,
                        isActive: appState.selectedSite.id == site.id) {
                    appState.selectedSite = site
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
    let isActive: Bool
    let onSelect: () -> Void

    private var rowBackground: Color {
        isActive ? Color.accentColor.opacity(0.15) : Color.clear
    }
    private var a11yLabel: String {
        isActive ? "\(site.displayName), currently loaded" : site.displayName
    }
    private var a11yHint: String {
        isActive ? "" : "Load radar data for this site"
    }
    private var a11yTraits: AccessibilityTraits {
        var t: AccessibilityTraits = [.isButton]
        if isActive { t.insert(.isSelected) }
        return t
    }

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.icao)
                        .font(.body.monospaced().weight(.semibold))
                    Text(site.name + ", " + site.state)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(rowBackground)
        .accessibilityLabel(a11yLabel)
        .accessibilityAddTraits(a11yTraits)
        .accessibilityHint(a11yHint)
    }
}
