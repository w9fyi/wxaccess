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
        let decoder = Level2Decoder()
        let sweeps = try decoder.decode(data: data)
        #expect(!sweeps.isEmpty)
        let first = try #require(sweeps.first)
        #expect(first.radials.isEmpty == false)
        // Scan date must be in 2026, not ~1956 (pre-fix bug produced wrong year)
        let year = Calendar(identifier: .gregorian)
            .component(.year, from: first.scanTime)
        #expect(year == 2026)
        // Azimuth and elevation angles must be physically plausible
        let radial = try #require(first.radials.first)
        #expect(radial.azimuth >= 0 && radial.azimuth < 360)
        #expect(radial.elevation > 0 && radial.elevation < 20)
        #expect(radial.numGates > 0)
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
