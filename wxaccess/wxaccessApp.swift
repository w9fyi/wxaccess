import SwiftUI

@main
struct wxaccessApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About wxaccess") {
                    appState.showAbout = true
                }
            }
            CommandMenu("Radar") {
                Button("Refresh") {
                    Task { await appState.refresh() }
                }
                .keyboardShortcut("r")

                Button("Animate Loop") {
                    Task { await appState.toggleAnimation() }
                }
                .keyboardShortcut("l")
            }
        }

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
