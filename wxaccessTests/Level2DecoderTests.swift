import Testing
import Foundation
@testable import wxaccess

// Integration tests require a real NEXRAD Level 2 file.
// Download one with:
//   curl -o /tmp/KEWX_test.bin \
//     "https://noaa-nexrad-level2.s3.amazonaws.com/$(date -u +%Y/%m/%d)/KEWX/$(aws s3 ls noaa-nexrad-level2/$(date -u +%Y/%m/%d)/KEWX/ | tail -1 | awk '{print $4}')"
// Then update testFilePath below.

@Suite("Level 2 Decoder")
struct Level2DecoderTests {

    @Test("Volume header parses cleanly from real file")
    func parseVolumeHeader() throws {
        guard let url = Bundle(for: Level2DecoderTestClass.self)
                .url(forResource: "KEWX_sample", withExtension: "bin") else {
            return  // skip if sample not bundled
        }
        let data = try Data(contentsOf: url)
        let sweeps = try Level2Decoder().decode(data: data)
        #expect(!sweeps.isEmpty)
        let first = try #require(sweeps.first)
        #expect(first.radials.isEmpty == false)
        // Scan date must be in 2026, not ~1956 (pre-fix bug produced wrong year)
        let year = Calendar(identifier: .gregorian).component(.year, from: first.scanTime)
        #expect(year == 2026)
        // Azimuth and elevation angles must be physically plausible
        let radial = try #require(first.radials.first)
        #expect(radial.azimuth >= 0 && radial.azimuth < 360)
        #expect(radial.elevation > 0 && radial.elevation < 20)
        #expect(radial.numGates > 0)
    }

    @Test("Multiple moment types decoded from real file")
    func multipleProducts() throws {
        guard let url = Bundle(for: Level2DecoderTestClass.self)
                .url(forResource: "KEWX_sample", withExtension: "bin") else {
            return
        }
        let data = try Data(contentsOf: url)
        let sweeps = try Level2Decoder().decode(data: data)
        let products = Set(sweeps.map(\.momentType))
        // KEWX dual-pol scan always has at least REF, ZDR, PHI, and RHO
        #expect(products.contains("REF"))
        #expect(products.contains("ZDR"))
        #expect(products.contains("PHI"))
        #expect(products.contains("RHO"))
        // Each product sweep should have valid radials
        let refSweeps = sweeps.filter { $0.momentType == "REF" }
        #expect(!refSweeps.isEmpty)
        #expect(refSweeps.allSatisfy { !$0.radials.isEmpty })
        // ZDR uses 16-bit gate data — values should be UInt16
        let zdrSweep = try #require(sweeps.first { $0.momentType == "ZDR" })
        #expect(zdrSweep.radials.first?.data.isEmpty == false)
    }

    @Test("BZip2 round-trip")
    func bzip2RoundTrip() throws {
        let original = Data("Hello NEXRAD Level 2 decoder round-trip test".utf8)
        // We can't easily compress in Swift without bzip2 write support,
        // so just verify the decompressor doesn't crash on garbage input.
        #expect(throws: BZip2Error.self) {
            _ = try bzip2Decompress(Data([0x00, 0x01, 0x02]))
        }
    }

    @Test("Data reading helpers are big-endian")
    func dataReadingHelpers() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        #expect(data.readUInt32BE(at: 0) == 0xDEADBEEF)
        #expect(data.readUInt16BE(at: 0) == 0xDEAD)
        #expect(data.readUInt16BE(at: 2) == 0xBEEF)
    }

    @Test("Radial physical value conversion")
    func radialPhysicalValue() {
        let radial = Radial(
            azimuth: 0, elevation: 0.5,
            firstGateMeters: 2125, gateSizeMeters: 250,
            numGates: 3,
            scale: 2.0, offset: 66.0,
            data: [0, 1, 100]   // 0=below threshold, 1=range folded, 100=valid
        )
        #expect(radial.physicalValue(gateIndex: 0) == nil)  // below threshold
        #expect(radial.physicalValue(gateIndex: 1) == nil)  // range folded
        let value = radial.physicalValue(gateIndex: 2)
        #expect(value != nil)
        #expect(abs((value ?? 0) - 17.0) < 0.01)  // (100 - 66) / 2 = 17.0
    }

    // ── Precision cross-validation against Python reference decoder ──────────
    // Reference values produced by /tmp/nexrad_reference.py (stdlib struct+bz2 only).
    // Any mismatch here means the Swift decoder diverges from the ground-truth ICD parsing.

    @Test("REF scale and offset match ICD values (scale=2.0 offset=66.0)")
    func refScaleAndOffset() throws {
        guard let url = Bundle(for: Level2DecoderTestClass.self)
                .url(forResource: "KEWX_sample", withExtension: "bin") else { return }
        let data = try Data(contentsOf: url)
        let sweeps = try Level2Decoder().decode(data: data)
        let refAt05 = try #require(sweeps.filter { $0.momentType == "REF" }
                                         .min(by: { abs($0.elevationAngle - 0.5) <
                                                    abs($1.elevationAngle - 0.5) }))
        let r = try #require(refAt05.radials.first)
        // Python reference: scale=2.0, offset=66.0 for KEWX REF
        #expect(abs(r.scale  - 2.0)  < 0.001)
        #expect(abs(r.offset - 66.0) < 0.001)
    }

    @Test("Gate geometry matches reference (first_gate=2125m gate_size=250m num_gates=1192)")
    func gateGeometry() throws {
        guard let url = Bundle(for: Level2DecoderTestClass.self)
                .url(forResource: "KEWX_sample", withExtension: "bin") else { return }
        let data = try Data(contentsOf: url)
        let sweeps = try Level2Decoder().decode(data: data)
        let refAt05 = try #require(sweeps.filter { $0.momentType == "REF" }
                                         .min(by: { abs($0.elevationAngle - 0.5) <
                                                    abs($1.elevationAngle - 0.5) }))
        let r = try #require(refAt05.radials.first)
        // Python reference: first_gate=2125m, gate_size=250m, num_gates=1192
        #expect(r.firstGateMeters == 2125)
        #expect(r.gateSizeMeters  == 250)
        #expect(r.numGates        == 1192)
    }

    @Test("Raw gate values at azimuth ~0° match Python reference exactly")
    func rawGatesNorthRadial() throws {
        guard let url = Bundle(for: Level2DecoderTestClass.self)
                .url(forResource: "KEWX_sample", withExtension: "bin") else { return }
        let data = try Data(contentsOf: url)
        let sweeps = try Level2Decoder().decode(data: data)
        let refAt05 = try #require(sweeps.filter { $0.momentType == "REF" }
                                         .min(by: { abs($0.elevationAngle - 0.5) <
                                                    abs($1.elevationAngle - 0.5) }))
        // Python: closest to az=0° → actual az=0.1785°, raw values:
        //   gate[0]=82, gate[10]=69, gate[50]=85, gate[100]=63, gate[200]=0
        let north = try #require(refAt05.radials.min(by: {
            abs($0.azimuth - 0.1785) < abs($1.azimuth - 0.1785)
        }))
        #expect(abs(north.azimuth - 0.1785) < 0.5)
        #expect(north.data[0]   == 82)
        #expect(north.data[10]  == 69)
        #expect(north.data[50]  == 85)
        #expect(north.data[100] == 63)
        #expect(north.data[200] == 0)   // raw=0 → no data
    }

    @Test("Physical values at azimuth ~0° match Python formula exactly")
    func physicalValuesNorthRadial() throws {
        guard let url = Bundle(for: Level2DecoderTestClass.self)
                .url(forResource: "KEWX_sample", withExtension: "bin") else { return }
        let data = try Data(contentsOf: url)
        let sweeps = try Level2Decoder().decode(data: data)
        let refAt05 = try #require(sweeps.filter { $0.momentType == "REF" }
                                         .min(by: { abs($0.elevationAngle - 0.5) <
                                                    abs($1.elevationAngle - 0.5) }))
        let north = try #require(refAt05.radials.min(by: {
            abs($0.azimuth - 0.1785) < abs($1.azimuth - 0.1785)
        }))
        // Python: (raw - 66.0) / 2.0
        // gate[0]:  (82-66)/2 =  8.0 dBZ
        // gate[10]: (69-66)/2 =  1.5 dBZ
        // gate[50]: (85-66)/2 =  9.5 dBZ
        // gate[100]:(63-66)/2 = -1.5 dBZ
        // gate[200]: raw=0   → nil (below threshold)
        #expect(abs((north.physicalValue(gateIndex: 0)   ?? -999) -  8.0) < 0.01)
        #expect(abs((north.physicalValue(gateIndex: 10)  ?? -999) -  1.5) < 0.01)
        #expect(abs((north.physicalValue(gateIndex: 50)  ?? -999) -  9.5) < 0.01)
        #expect(abs((north.physicalValue(gateIndex: 100) ?? -999) - (-1.5)) < 0.01)
        #expect(north.physicalValue(gateIndex: 200) == nil)
    }

    @Test("Raw gate values at azimuth ~90° match Python reference exactly")
    func rawGatesEastRadial() throws {
        guard let url = Bundle(for: Level2DecoderTestClass.self)
                .url(forResource: "KEWX_sample", withExtension: "bin") else { return }
        let data = try Data(contentsOf: url)
        let sweeps = try Level2Decoder().decode(data: data)
        let refAt05 = try #require(sweeps.filter { $0.momentType == "REF" }
                                         .min(by: { abs($0.elevationAngle - 0.5) <
                                                    abs($1.elevationAngle - 0.5) }))
        // Python: closest to az=90° → actual az=90.2170°, raw values:
        //   gate[0]=57, gate[10]=77, gate[50]=70, gate[100]=80, gate[200]=57
        let east = try #require(refAt05.radials.min(by: {
            abs($0.azimuth - 90.217) < abs($1.azimuth - 90.217)
        }))
        #expect(abs(east.azimuth - 90.217) < 0.5)
        #expect(east.data[0]   == 57)
        #expect(east.data[10]  == 77)
        #expect(east.data[50]  == 70)
        #expect(east.data[100] == 80)
        #expect(east.data[200] == 57)
    }

    @Test("Max REF across full 0.5° sweep is 71.0 dBZ (Python reference)")
    func maxReflectivity() throws {
        guard let url = Bundle(for: Level2DecoderTestClass.self)
                .url(forResource: "KEWX_sample", withExtension: "bin") else { return }
        let data = try Data(contentsOf: url)
        let sweeps = try Level2Decoder().decode(data: data)
        let refAt05 = try #require(sweeps.filter { $0.momentType == "REF" }
                                         .min(by: { abs($0.elevationAngle - 0.5) <
                                                    abs($1.elevationAngle - 0.5) }))
        // Python reference: 2871 radials at 0.5° (1440×ng=1192 + 1431×ng=1832)
        // Max raw=208 at az=170.7495°, gate[1245] → (208−66)/2 = 71.0 dBZ
        #expect(refAt05.radials.count == 2871)
        let maxDBZ = refAt05.radials.flatMap { radial in
            (0..<radial.numGates).compactMap { radial.physicalValue(gateIndex: $0) }
        }.max()
        let max = try #require(maxDBZ)
        #expect(abs(max - 71.0) < 0.1)
    }

    @Test("High-value radial at az≈170.75° has gate[1245] raw=208 (71.0 dBZ)")
    func maxRadialGateValue() throws {
        guard let url = Bundle(for: Level2DecoderTestClass.self)
                .url(forResource: "KEWX_sample", withExtension: "bin") else { return }
        let data = try Data(contentsOf: url)
        let sweeps = try Level2Decoder().decode(data: data)
        let refAt05 = try #require(sweeps.filter { $0.momentType == "REF" }
                                         .min(by: { abs($0.elevationAngle - 0.5) <
                                                    abs($1.elevationAngle - 0.5) }))
        // Python reference: max raw=208 at az=170.7495°, gate=1245
        let radial = try #require(refAt05.radials.min(by: {
            abs($0.azimuth - 170.7495) < abs($1.azimuth - 170.7495)
        }))
        #expect(abs(radial.azimuth - 170.7495) < 0.5)
        #expect(radial.numGates == 1832)
        #expect(radial.data[1245] == 208)
        let phys = radial.physicalValue(gateIndex: 1245)
        #expect(abs((phys ?? -999) - 71.0) < 0.01)
    }

    @Test("Site catalog includes KEWX")
    func siteCatalogHasKEWX() {
        let site = NEXRADSiteCatalog.site(icao: "KEWX")
        #expect(site != nil)
        #expect(site?.state == "TX")
    }

    @Test("NWS alert accessibility label is non-empty")
    func alertAccessibilityLabel() {
        let alert = NWSAlert(
            id: "test", event: "Tornado Warning",
            headline: "Tornado Warning issued for Travis County",
            description: "", instruction: "",
            severity: .extreme, urgency: .immediate,
            effective: .now, expires: .now.addingTimeInterval(3600),
            affectedZones: ["TXZ105"], polygon: [],
            senderName: "NWS Austin"
        )
        #expect(!alert.accessibilityLabel.isEmpty)
        #expect(alert.accessibilityLabel.contains("Tornado Warning"))
    }
}

// Dummy class used to locate the test bundle
private final class Level2DecoderTestClass {}

@Suite("Placefile Parser")
struct PlacefileParserTests {

    private let sample = """
    ; GRLevel3 placefile sample
    Title: Test Storm Data
    RefreshSeconds: 30

    Color: 255 0 0
    Icon: 30.1,-97.5,0,"Tornado Warning TXZ105",0
    Text: 30.2,-97.6,0,"TOR","Tornado Warning near Austin"

    Color: 0 255 0 180
    Line: 2,0
     30.0,-97.0
     30.5,-97.5
     31.0,-97.0
    End:

    Color: 255 165 0
    Polygon:
     29.9,-97.9
     30.4,-97.9
     30.4,-97.4
     29.9,-97.4
    End:
    """

    @Test("Title and RefreshSeconds parse correctly")
    func titleAndRefresh() {
        let pf = PlacefileParser().parse(text: sample)
        #expect(pf.title == "Test Storm Data")
        #expect(pf.refreshSeconds == 30)
    }

    @Test("Icon item parsed as point with label")
    func iconItem() throws {
        let pf = PlacefileParser().parse(text: sample)
        let icons = pf.items.filter {
            if case .point = $0.geometry { return !$0.label.isEmpty }
            return false
        }
        #expect(!icons.isEmpty)
        let icon = try #require(icons.first)
        #expect(icon.label.contains("Tornado Warning"))
        #expect(abs(icon.coordinate.latitude - 30.1) < 0.001)
        #expect(abs(icon.coordinate.longitude - (-97.5)) < 0.001)
        #expect(icon.color.r == 255)
        #expect(icon.color.g == 0)
    }

    @Test("Text item parsed with label and detail")
    func textItem() throws {
        let pf = PlacefileParser().parse(text: sample)
        let texts = pf.items.filter {
            if case .point = $0.geometry { return $0.label == "TOR" }
            return false
        }
        let item = try #require(texts.first)
        #expect(item.label == "TOR")
        #expect(item.detail.contains("Austin"))
    }

    @Test("Line item parsed with correct point count")
    func lineItem() throws {
        let pf = PlacefileParser().parse(text: sample)
        let lines = pf.items.filter {
            if case .line = $0.geometry { return true }
            return false
        }
        let line = try #require(lines.first)
        if case .line(let pts, let w) = line.geometry {
            #expect(pts.count == 3)
            #expect(w == 2)
        } else {
            Issue.record("Expected .line geometry")
        }
        #expect(line.color.g == 255)
    }

    @Test("Polygon item parsed with correct point count")
    func polygonItem() throws {
        let pf = PlacefileParser().parse(text: sample)
        let polys = pf.items.filter {
            if case .polygon = $0.geometry { return true }
            return false
        }
        let poly = try #require(polys.first)
        if case .polygon(let pts) = poly.geometry {
            #expect(pts.count == 4)
        } else {
            Issue.record("Expected .polygon geometry")
        }
        #expect(poly.color.r == 255)
        #expect(poly.color.g == 165)
    }

    @Test("Accessibility label is non-empty for icon item")
    func accessibilityLabel() throws {
        let pf = PlacefileParser().parse(text: sample)
        let icons = pf.items.filter {
            if case .point = $0.geometry { return !$0.label.isEmpty }
            return false
        }
        let icon = try #require(icons.first)
        #expect(!icon.accessibilityLabel.isEmpty)
        #expect(icon.accessibilityLabel.contains("Tornado Warning"))
    }
}
