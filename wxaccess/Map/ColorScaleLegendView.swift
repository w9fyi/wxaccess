import SwiftUI

// Floating color-scale key for the active radar product.
// Sighted users see color swatches + value labels; VoiceOver reads the
// textual legend in AccessibilityPanel instead (this view is hidden from the a11y tree).
struct ColorScaleLegendView: View {
    let product: RadarProduct
    let palette: ColorPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(legendTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.bottom, 3)
            ForEach(entries.indices, id: \.self) { i in
                HStack(spacing: 4) {
                    entries[i].color
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    Text(entries[i].label)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityHidden(true)
    }

    // MARK: - Entry model

    private struct Entry { let color: Color; let label: String }

    private var legendTitle: String {
        switch product {
        case .reflectivity:             return "dBZ"
        case .velocity:                 return "m/s"
        case .spectrumWidth:            return "SW m/s"
        case .differentialReflectivity: return "ZDR dB"
        case .correlationCoefficient:   return "RHO"
        case .differentialPhase:        return "PHI °"
        case .echoTops:                 return "EET kft"
        case .vil:                      return "VIL kg/m²"
        case .stormTotalPrecip:         return "STP in"
        }
    }

    private var entries: [Entry] {
        switch product {
        case .reflectivity:             return refEntries
        case .velocity:                 return velEntries
        case .spectrumWidth:            return swEntries
        case .differentialReflectivity: return zdrEntries
        case .correlationCoefficient:   return rhoEntries
        case .differentialPhase:        return phiEntries
        case .echoTops:                 return etEntries
        case .vil:                      return vilEntries
        case .stormTotalPrecip:         return precipEntries
        }
    }

    // MARK: - REF (palette-dependent, highest first)

    private var refEntries: [Entry] {
        switch palette {
        case .nwsStandard:
            return [
                e(0xFF, 0xFF, 0xFF, "75+ dBZ"),
                e(0x98, 0x54, 0xC6, "70–75"),
                e(0xF8, 0x00, 0xFD, "65–70"),
                e(0xBC, 0x00, 0x00, "55–65"),
                e(0xFD, 0x95, 0x00, "45–55"),
                e(0xFD, 0xF8, 0x02, "35–45"),
                e(0x01, 0xC5, 0x01, "20–35"),
                e(0x00, 0xEC, 0xEC, "5–20"),
            ]
        case .grDefault:
            return [
                e(0xFF, 0xFF, 0xFF, "75+ dBZ"),
                e(0xFF, 0xFF, 0xFF, "70–75"),
                e(0xC0, 0x00, 0xC0, "65–70"),
                e(0xFF, 0x00, 0xFF, "60–65"),
                e(0xC0, 0x00, 0x00, "55–60"),
                e(0xFF, 0x80, 0x00, "45–55"),
                e(0xFF, 0xFF, 0x00, "35–45"),
                e(0x00, 0xC0, 0x00, "20–35"),
                e(0x40, 0xE0, 0xD0, "5–20"),
            ]
        case .colorblind:
            return [
                e(0xFF, 0xFF, 0xFF, "75+ dBZ"),
                e(0xF0, 0xE6, 0xFF, "65–75"),
                e(0x96, 0x00, 0x64, "60–65"),
                e(0xE4, 0x40, 0x00, "50–60"),
                e(0xEF, 0x7B, 0x00, "45–50"),
                e(0xF9, 0xE5, 0x00, "35–45"),
                e(0x00, 0xBF, 0xD0, "20–35"),
                e(0xCA, 0xCC, 0xE4, "5–20"),
            ]
        }
    }

    // MARK: - Fixed-color products

    private var velEntries: [Entry] { [
        e(0x7F, 0x00, 0x00, "30+ m/s"),
        e(0xFF, 0x00, 0x00, "20–30"),
        e(0xFF, 0x96, 0x00, "10–20"),
        e(0xC8, 0xC8, 0x00, "0–10"),
        e(0x00, 0xC8, 0x00, "−10–0"),
        e(0x00, 0xF0, 0xF0, "−20 – −10"),
        e(0x00, 0x9E, 0xFF, "−30 – −20"),
        e(0x00, 0x00, 0xEC, "−50 – −30"),
        e(0x00, 0x00, 0x7F, "< −50"),
    ] }

    private var swEntries: [Entry] { [
        e(0xFF, 0xFF, 0xFF, "> 16 m/s"),
        e(0xFF, 0x00, 0x00, "13–16"),
        e(0xFF, 0x96, 0x00, "10–13"),
        e(0xC8, 0xC8, 0x00, "8–10"),
        e(0x00, 0xC8, 0x00, "6–8"),
        e(0x00, 0xC8, 0x96, "4–6"),
        e(0x00, 0x64, 0xFF, "2–4"),
        e(0x00, 0x00, 0x96, "< 2"),
    ] }

    private var zdrEntries: [Entry] { [
        e(0xFF, 0x00, 0xFF, "> 5 dB"),
        e(0xFF, 0x00, 0x00, "4–5"),
        e(0xFF, 0x96, 0x00, "3–4"),
        e(0xC8, 0xC8, 0x00, "2–3"),
        e(0x00, 0xC8, 0x00, "1–2"),
        e(0x00, 0xC8, 0x96, "0–1"),
        e(0x00, 0x96, 0xFF, "−1–0"),
        e(0x00, 0x00, 0xC8, "< −1"),
    ] }

    private var rhoEntries: [Entry] { [
        e(0xFF, 0xFF, 0xFF, "> 0.99"),
        e(0xFF, 0xFF, 0x00, "0.97–0.99"),
        e(0x00, 0xC8, 0x00, "0.95–0.97"),
        e(0x00, 0xC8, 0xFF, "0.90–0.95"),
        e(0x00, 0x00, 0xFF, "0.85–0.90"),
        e(0x96, 0x32, 0x96, "0.70–0.85"),
        e(0x40, 0x40, 0x40, "< 0.70"),
    ] }

    // PHI is a continuous HSV rainbow; show 5 sample hues
    private var phiEntries: [Entry] { [
        e(0xE5, 0x22, 0x22, "0°  (red)"),
        e(0x84, 0xE5, 0x22, "90° (yellow-green)"),
        e(0x22, 0xE5, 0xE5, "180° (cyan)"),
        e(0x84, 0x22, 0xE5, "270° (violet)"),
        e(0xE5, 0x22, 0x22, "360° (red)"),
    ] }

    private var etEntries: [Entry] { [
        e(0xFF, 0xFF, 0xFF, "> 70 kft"),
        e(0xCC, 0x00, 0xCC, "60–70"),
        e(0xFF, 0x00, 0x00, "50–60"),
        e(0xFF, 0xA5, 0x00, "40–50"),
        e(0xFF, 0xFF, 0x00, "30–40"),
        e(0x00, 0xCC, 0x00, "20–30"),
        e(0x00, 0x80, 0x00, "10–20"),
        e(0x00, 0x40, 0x00, "< 10"),
    ] }

    private var vilEntries: [Entry] { [
        e(0xFF, 0xFF, 0xFF, "> 70 kg/m²"),
        e(0xC8, 0x00, 0xC8, "60–70"),
        e(0xFF, 0x00, 0x00, "50–60"),
        e(0xFF, 0x80, 0x00, "40–50"),
        e(0xFF, 0xFF, 0x00, "30–40"),
        e(0x00, 0xFF, 0x80, "20–30"),
        e(0x00, 0xD0, 0xFF, "10–20"),
        e(0x00, 0x80, 0xFF, "5–10"),
        e(0x00, 0x40, 0xFF, "< 5"),
    ] }

    private var precipEntries: [Entry] { [
        e(0xFF, 0xFF, 0xFF, "> 4 in"),
        e(0xF0, 0x00, 0xF0, "3–4"),
        e(0xBC, 0x00, 0x00, "2.5–3"),
        e(0xFC, 0x00, 0x00, "1.5–2.5"),
        e(0xE8, 0x90, 0x00, "1.0–1.5"),
        e(0xF0, 0xF0, 0x00, "0.5–1.0"),
        e(0x04, 0xB4, 0x04, "0.25–0.5"),
        e(0x04, 0xE4, 0x14, "0.1–0.25"),
        e(0x04, 0x94, 0xF4, "< 0.1"),
    ] }

    // MARK: - Helpers

    private func e(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ label: String) -> Entry {
        Entry(color: Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255),
              label: label)
    }
}
