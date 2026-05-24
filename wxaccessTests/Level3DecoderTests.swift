import Testing
import Foundation
@testable import wxaccess

// Dummy class for test-bundle resource lookup (mirrors Level2DecoderTestClass pattern)
private final class Level3DecoderTestClass {}

// Tests for Level3Decoder using a synthetic Packet Code 16 binary.
//
// The binary layout (183 bytes):
//   0–17:   Message Header Block (MHB)
//   18–119: Product Description Block (PDB)
//   120–182: Symbology Block → 1 layer → Packet 16 → 3 radials × 5 bins
//
// Radial 0: az 0.0°, delta 1.0°, data [0, 1, 2, 50, 255]
// Radial 1: az 1.0°, delta 1.0°, data [3, 100, 200, 254, 0]
// Radial 2: az 2.0°, delta 1.0°, data [2, 2, 2, 2, 2]
//
// Scan time: Julian 19740, 43200 s → 2024-01-17 12:00:00 UTC
//            timeIntervalSince1970 = 1_705_492_800

struct Level3DecoderTests {

    private let site = NEXRADSiteCatalog.site(icao: "KEWX")!

    // MARK: - Binary factory

    private func makeL3Data(
        packetCode: UInt16 = 16,
        symbOffsetHW: Int32 = 60,
        numBins: UInt16 = 5,
        scaleFactor: UInt16 = 250,   // 0.25 km/bin
        firstBin: UInt16 = 0,
        radials: [(start: UInt16, delta: UInt16, data: [UInt8])]? = nil
    ) -> Data {
        let rads: [(start: UInt16, delta: UInt16, data: [UInt8])] = radials ?? [
            (start: 0,  delta: 10, data: [0, 1, 2, 50, 255]),
            (start: 10, delta: 10, data: [3, 100, 200, 254, 0]),
            (start: 20, delta: 10, data: [2, 2, 2, 2, 2]),
        ]
        let nRadials = UInt16(rads.count)

        // Packet Code 16 header (14 bytes)
        var pkt: [UInt8] = be16(packetCode) + be16(firstBin) + be16(numBins)
                         + [0,0, 0,0]          // I/J center
                         + be16(scaleFactor) + be16(nRadials)
        for r in rads {
            let nb = UInt16(r.data.count)
            pkt += be16(nb) + be16(r.start) + be16(r.delta) + r.data
        }

        let layerLen = UInt32(pkt.count)
        let layer: [UInt8] = [0xFF, 0xFF] + be32(layerLen) + pkt

        let symbLen = UInt32(10 + layer.count)
        let symb: [UInt8] = [0xFF, 0xFF, 0x00, 0x01] + be32(symbLen) + [0x00, 0x01] + layer

        let julDate: UInt16 = 19740
        let secs:    UInt32 = 43200
        let mhb: [UInt8] = [0x00, 0x00] + be16(julDate) + be32(secs) + [UInt8](repeating: 0, count: 10)

        var pdb = [UInt8](repeating: 0, count: 102)
        let jb = be16(julDate); pdb[22] = jb[0]; pdb[23] = jb[1]
        let sb = be32(secs);    pdb[24] = sb[0]; pdb[25] = sb[1]; pdb[26] = sb[2]; pdb[27] = sb[3]
        let ob = be32s(symbOffsetHW); pdb[98] = ob[0]; pdb[99] = ob[1]; pdb[100] = ob[2]; pdb[101] = ob[3]

        return Data(mhb + pdb + symb)
    }

    private func be16(_ v: UInt16) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
    private func be32(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }
    private func be32s(_ v: Int32) -> [UInt8] { be32(UInt32(bitPattern: v)) }

    // MARK: - Structure tests

    @Test("Decodes synthetic EET sweep: 3 radials, 5 bins, 0.25 km resolution")
    func decodesValidSynthetic() throws {
        let data  = makeL3Data()
        let sweep = try Level3Decoder().decode(data: data, site: site, product: .echoTops)
        #expect(sweep.radials.count == 3)
        #expect(sweep.numBins      == 5)
        #expect(abs(sweep.binSizeKm  - 0.25) < 0.001)
        #expect(abs(sweep.firstBinKm - 0.00) < 0.001)
        #expect(sweep.productCode  == .echoTops)
        #expect(sweep.site.icao    == "KEWX")
    }

    @Test("Scan time parses Julian date 19740, 43200 s → 2024-01-17 12:00 UTC")
    func scanTimeParsed() throws {
        let sweep = try Level3Decoder().decode(data: makeL3Data(), site: site, product: .echoTops)
        #expect(abs(sweep.scanTime.timeIntervalSince1970 - 1_705_492_800) < 1)
    }

    @Test("Radial start angles parsed: 0.0°, 1.0°, 2.0°")
    func radialStartAngles() throws {
        let sweep = try Level3Decoder().decode(data: makeL3Data(), site: site, product: .echoTops)
        let angles = sweep.radials.map { $0.startAngle }
        #expect(abs(angles[0] - 0.0) < 0.01)
        #expect(abs(angles[1] - 1.0) < 0.01)
        #expect(abs(angles[2] - 2.0) < 0.01)
    }

    @Test("Bin data parsed: radial 0 bin [2,3] = codes 2 and 50")
    func binDataParsed() throws {
        let sweep = try Level3Decoder().decode(data: makeL3Data(), site: site, product: .echoTops)
        #expect(sweep.radials[0].data[2] == 2)
        #expect(sweep.radials[0].data[3] == 50)
        #expect(sweep.radials[1].data[0] == 3)
        #expect(sweep.radials[1].data[3] == 254)
    }

    // MARK: - Physical value formula tests

    @Test("Echo Tops: (code − 2) × 1.0 + 5.0 kft")
    func physicalValueEchoTops() {
        let p = Level3ProductCode.echoTops
        #expect(p.physicalValue(code: 0)   == nil)        // below threshold
        #expect(p.physicalValue(code: 1)   == nil)        // range folded
        #expect(p.physicalValue(code: 2)   == 5.0)        // minimum
        #expect(p.physicalValue(code: 50)  == 53.0)
        #expect(p.physicalValue(code: 200) == 203.0)
        #expect(p.physicalValue(code: 254) == 257.0)
        #expect(p.physicalValue(code: 255) == nil)        // beyond max range
    }

    @Test("Base Reflectivity L3: (code − 2) × 0.5 − 32.5 dBZ")
    func physicalValueBaseReflectivity() {
        let p = Level3ProductCode.baseReflectivity
        #expect(p.physicalValue(code: 2)   ==  -32.5)
        #expect(p.physicalValue(code: 100) ==   16.5)
        #expect(p.physicalValue(code: 200) ==   66.5)
        #expect(p.physicalValue(code: 254) ==   93.5)
    }

    @Test("Base Velocity L3: (code − 2) × 0.5 − 63.5 m/s")
    func physicalValueBaseVelocity() {
        let p = Level3ProductCode.baseVelocity
        #expect(p.physicalValue(code: 2)   == -63.5)
        #expect(p.physicalValue(code: 128) ==  -0.5)
        #expect(p.physicalValue(code: 130) ==   0.5)
        #expect(p.physicalValue(code: 254) ==  62.5)
    }

    @Test("Digital VIL: (code − 2) × 1.0 kg/m²")
    func physicalValueDigitalVIL() {
        let p = Level3ProductCode.digitalVIL
        #expect(p.physicalValue(code: 2)   ==   0.0)
        #expect(p.physicalValue(code: 52)  ==  50.0)
        #expect(p.physicalValue(code: 102) == 100.0)
    }

    @Test("Storm Total Precip: (code − 2) × 0.05 inches")
    func physicalValuePrecip() {
        let stp = Level3ProductCode.stormTotalPrecip
        let ohp = Level3ProductCode.oneHourPrecip
        #expect(abs((stp.physicalValue(code: 2)   ?? 99) - 0.00) < 0.001)
        #expect(abs((stp.physicalValue(code: 22)  ?? 99) - 1.00) < 0.001)
        #expect(abs((stp.physicalValue(code: 102) ?? 99) - 5.00) < 0.001)
        #expect(abs((ohp.physicalValue(code: 22)  ?? 99) - 1.00) < 0.001)
    }

    @Test("Threshold codes 0, 1, 255 return nil for all products")
    func thresholdCodesReturnNil() {
        for product in Level3ProductCode.allCases {
            #expect(product.physicalValue(code: 0)   == nil, "code 0 should be nil for \(product)")
            #expect(product.physicalValue(code: 1)   == nil, "code 1 should be nil for \(product)")
            #expect(product.physicalValue(code: 255) == nil, "code 255 should be nil for \(product)")
        }
    }

    @Test("Boundary code 2 and 254 return non-nil for all products")
    func boundaryCodesNonNil() {
        for product in Level3ProductCode.allCases {
            #expect(product.physicalValue(code: 2)   != nil, "code 2 should be non-nil for \(product)")
            #expect(product.physicalValue(code: 254) != nil, "code 254 should be non-nil for \(product)")
        }
    }

    // MARK: - Error handling tests

    @Test("Empty data throws fileTooShort")
    func fileTooShortThrows() throws {
        #expect(throws: Level3DecodeError.fileTooShort) {
            try Level3Decoder().decode(data: Data(), site: site, product: .echoTops)
        }
    }

    @Test("Zero symbology offset throws noSymbologyBlock")
    func noSymbologyBlockThrows() throws {
        let data = makeL3Data(symbOffsetHW: 0)
        #expect(throws: Level3DecodeError.noSymbologyBlock) {
            try Level3Decoder().decode(data: data, site: site, product: .echoTops)
        }
    }

    @Test("Non-16 packet code throws noPacket16")
    func noPacket16Throws() throws {
        let data = makeL3Data(packetCode: 17)
        #expect(throws: Level3DecodeError.noPacket16) {
            try Level3Decoder().decode(data: data, site: site, product: .echoTops)
        }
    }

    @Test("WMO text header (20-byte prefix) is skipped; sweep decodes correctly")
    func wmoHeaderSkipped() throws {
        let header = Array("SDUS53 KEWX 012345\r\r\n".utf8)  // 20 printable/CR bytes (all > 0x00)
        let payload = makeL3Data()
        // findMessageStart scans forward for first 0x00; that's byte 20 (MHB high byte of msg code)
        let wmoData = Data(header) + payload
        let sweep = try Level3Decoder().decode(data: wmoData, site: site, product: .echoTops)
        #expect(sweep.radials.count == 3)
        #expect(abs(sweep.scanTime.timeIntervalSince1970 - 1_705_492_800) < 1)
    }

    @Test("maxRangeKm = firstBinKm + numBins × binSizeKm = 1.25 km")
    func maxRangeKm() throws {
        let sweep = try Level3Decoder().decode(data: makeL3Data(), site: site, product: .echoTops)
        // firstBinKm=0, numBins=5, binSizeKm=0.25 → maxRange = 1.25
        #expect(abs(sweep.maxRangeKm - 1.25) < 0.001)
    }
}

// MARK: - Live data integration tests

@Suite("Level 3 Decoder — Live Data")
struct Level3DecoderLiveDataTests {

    // KEWX_N0Q_sample.bin is a real N0Q (Super-Res Base Reflectivity) product file
    // downloaded from the unidata-nexrad-level3 S3 bucket (ABC site, 2020-03-30).
    // Key format: {ICAO}_{MNEMONIC}_{YYYY}_{MM}_{DD}_{HH}_{mm}_{SS}
    // File has a WMO text header prefix, exercising the findMessageStart path.

    private let site = NEXRADSiteCatalog.site(icao: "KEWX")!

    private func loadSampleData() -> Data? {
        Bundle(for: Level3DecoderTestClass.self)
            .url(forResource: "KEWX_N0Q_sample", withExtension: "bin")
            .flatMap { try? Data(contentsOf: $0) }
    }

    @Test("Real N0Q file decodes without error")
    func decodeRealFile() throws {
        guard let data = loadSampleData() else { return }
        let sweep = try Level3Decoder().decode(data: data, site: site, product: .baseReflectivity)
        #expect(!sweep.radials.isEmpty)
        #expect(sweep.numBins > 0)
        #expect(sweep.productCode == .baseReflectivity)
    }

    @Test("Real N0Q file: scan time is a plausible date")
    func scanTimePlausible() throws {
        guard let data = loadSampleData() else { return }
        let sweep = try Level3Decoder().decode(data: data, site: site, product: .baseReflectivity)
        let year = Calendar(identifier: .gregorian).component(.year, from: sweep.scanTime)
        #expect(year >= 2000 && year <= 2030)
    }

    @Test("Real N0Q file: all radials have plausible azimuth angles")
    func radialAzimuths() throws {
        guard let data = loadSampleData() else { return }
        let sweep = try Level3Decoder().decode(data: data, site: site, product: .baseReflectivity)
        for radial in sweep.radials {
            #expect(radial.startAngle >= 0 && radial.startAngle < 360)
            #expect(radial.deltaAngle > 0 && radial.deltaAngle <= 2)
        }
    }

    @Test("Real N0Q file: bin data contains valid level codes")
    func binDataValid() throws {
        guard let data = loadSampleData() else { return }
        let sweep = try Level3Decoder().decode(data: data, site: site, product: .baseReflectivity)
        let first = try #require(sweep.radials.first)
        #expect(first.data.count == sweep.numBins)
    }

    @Test("Real N0Q file: physical value conversion produces finite dBZ values")
    func physicalValuesFinite() throws {
        guard let data = loadSampleData() else { return }
        let sweep = try Level3Decoder().decode(data: data, site: site, product: .baseReflectivity)
        let values = sweep.radials.flatMap { r in
            r.data.compactMap { Level3ProductCode.baseReflectivity.physicalValue(code: $0) }
        }
        #expect(!values.isEmpty)
        #expect(values.allSatisfy { $0.isFinite })
        // N0Q reflectivity should be in physically plausible range: -32.5 to 94.5 dBZ
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 0
        #expect(minVal >= -33 && maxVal <= 95)
    }

    @Test("Real N0Q file: WMO header is skipped; correct radial count for full volume")
    func wmoHeaderSkippedInRealFile() throws {
        guard let data = loadSampleData() else { return }
        // If WMO header skip fails, decode would throw or produce no radials
        let sweep = try Level3Decoder().decode(data: data, site: site, product: .baseReflectivity)
        // N0Q produces 360 radials at 1° resolution (some sites use 720 at 0.5°)
        #expect(sweep.radials.count == 360 || sweep.radials.count == 720)
    }
}
