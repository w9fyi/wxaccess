import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("wxaccess")
                    .font(.largeTitle.weight(.bold))
                Text("VoiceOver-first NEXRAD radar viewer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("Version \(version) (\(build))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 20)
            .padding(.horizontal, 24)

            Divider()

            // Data sources
            VStack(alignment: .leading, spacing: 6) {
                Text("Data Sources")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                sourceRow("NOAA NEXRAD",  "Level 2 Archive II via S3")
                sourceRow("Unidata",      "Level 3 products via S3")
                sourceRow("NWS API",      "Active alerts and warnings")
                sourceRow("SPC",          "Outlooks, MDs, storm reports")
                sourceRow("GOES-East",    "Satellite imagery via IEM tiles")
                sourceRow("HRRR / MRMS",  "Model and analysis layers via IEM")
                sourceRow("ASOS / AWOS",  "Surface observations via NWS API")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            // Close button
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 340, minHeight: 400)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("About wxaccess")
    }

    private func sourceRow(_ name: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(name)
                .font(.caption.weight(.medium))
                .frame(width: 110, alignment: .leading)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(detail)")
    }
}
