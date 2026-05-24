import SwiftUI

struct SettingsView: View {
    @AppStorage("radarOpacity")    private var opacity:       Double = 0.75
    @AppStorage("autoRefresh")     private var autoRefresh:   Bool   = true
    @AppStorage("refreshInterval") private var refreshMins:   Double = 5.0
    @AppStorage("defaultSite")     private var defaultSite:   String = "KEWX"
    @AppStorage("imageSize")       private var imageSize:     Int    = 1024

    @Environment(AppState.self) var appState
    @State private var newPlacefileURL: String = ""
    @State private var urlError: String?

    var body: some View {
        @Bindable var state = appState
        Form {
            Section("Radar Display") {
                Slider(value: $opacity, in: 0.3...1.0, step: 0.05) {
                    Text("Overlay opacity")
                } minimumValueLabel: {
                    Text("30%")
                } maximumValueLabel: {
                    Text("100%")
                }
                .accessibilityValue(String(format: "%.0f%%", opacity * 100))

                Picker("Image resolution", selection: $imageSize) {
                    Text("512 px (fast)").tag(512)
                    Text("1024 px (default)").tag(1024)
                    Text("2048 px (sharp)").tag(2048)
                }
                .accessibilityLabel("Radar image resolution: \(imageSize) pixels")
            }

            Section("Refresh") {
                Toggle("Auto-refresh", isOn: $autoRefresh)
                if autoRefresh {
                    Picker("Interval", selection: $refreshMins) {
                        Text("2 min").tag(2.0)
                        Text("5 min").tag(5.0)
                        Text("10 min").tag(10.0)
                    }
                }
            }

            Section("Radar Color Palette") {
                Picker("Palette", selection: $state.colorPalette) {
                    ForEach(ColorPalette.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .accessibilityLabel("Radar color palette: \(appState.colorPalette.displayName)")
                Text(appState.colorPalette.accessibilityDescription)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Range Rings") {
                Toggle("Show range rings", isOn: $state.showRangeRings)
                    .accessibilityLabel("Show range rings: \(appState.showRangeRings ? "on" : "off")")
                if appState.showRangeRings {
                    Text("Rings at 50, 100, 150, and 230 km from the selected site.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Default Site") {
                Picker("Site", selection: $defaultSite) {
                    ForEach(NEXRADSiteCatalog.all) { site in
                        Text(site.displayName).tag(site.icao)
                    }
                }
                .frame(maxWidth: 300)
            }

            Section("Placefiles") {
                if appState.placefileURLs.isEmpty {
                    Text("No placefiles configured.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(appState.placefileURLs, id: \.self) { url in
                        HStack {
                            Text(url.absoluteString)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) {
                                appState.placefileURLs.removeAll { $0 == url }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Remove \(url.lastPathComponent)")
                        }
                    }
                }

                HStack {
                    TextField("https://example.com/storms.txt", text: $newPlacefileURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("New placefile URL")
                    Button("Add") {
                        addPlacefileURL()
                    }
                    .disabled(newPlacefileURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let err = urlError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .frame(minWidth: 420, minHeight: 360)
    }

    private func addPlacefileURL() {
        let trimmed = newPlacefileURL.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed),
              url.scheme == "https" || url.scheme == "http" else {
            urlError = "Enter a valid http:// or https:// URL."
            return
        }
        guard !appState.placefileURLs.contains(url) else {
            urlError = "Already in the list."
            return
        }
        urlError = nil
        appState.placefileURLs.append(url)
        newPlacefileURL = ""
        Task { await appState.refresh() }
    }
}
