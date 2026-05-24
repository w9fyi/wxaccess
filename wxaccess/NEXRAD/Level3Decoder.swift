import Foundation

// NEXRAD Level 3 binary decoder.
//
// Format reference: ICD 2620001Z (RPG to Class 1 User)
//
// File layout (unidata-nexrad-level3 bucket — no WMO text header):
//   [18 bytes]  Message Header Block (MHB)
//   [102 bytes] Product Description Block (PDB)
//   [variable]  Symbology Block, Graphic Attribute Table, Tabular Attribute Table
//
// Within the Symbology Block, packet code 16 (Digital Radial Data Array)
// is used for all radial products (N0Q, N0U, EET, DVL, STP, OHP).

enum Level3DecodeError: Error, LocalizedError, Equatable {
    case fileTooShort
    case noSymbologyBlock
    case noPacket16
    case unsupportedPacketCode(Int)

    var errorDescription: String? {
        switch self {
        case .fileTooShort:              "File is too short to be a valid Level 3 product"
        case .noSymbologyBlock:          "No symbology block found in Level 3 product"
        case .noPacket16:                "No Packet Code 16 (radial data) found in product"
        case .unsupportedPacketCode(let c): "Unsupported packet code \(c)"
        }
    }
}

final class Level3Decoder {

    // MARK: - Public API

    func decode(data: Data, site: NEXRADSite,
                product: Level3ProductCode) throws -> Level3RadialSweep {
        // Some archives prepend a WMO/AWIPS text header (ASCII lines ending in \r\r\n).
        // unidata-nexrad-level3 files typically have no such header, but handle it anyway.
        let msgStart = findMessageStart(in: data)

        // ── Message Header Block (18 bytes) ──────────────────────────────
        guard msgStart + 18 <= data.count else { throw Level3DecodeError.fileTooShort }
        // bytes 2-3: modified Julian date; bytes 4-7: seconds past midnight
        let mhbDate    = Int(data.readUInt16BE(at: msgStart + 2))
        let mhbSeconds = Int(data.readUInt32BE(at: msgStart + 4))
        let msgTime    = Date(timeIntervalSince1970: Double(max(0, mhbDate - 1)) * 86400.0
                                                   + Double(mhbSeconds))

        // ── Product Description Block (102 bytes at offset 18) ────────────
        let pdbBase = msgStart + 18
        guard pdbBase + 102 <= data.count else { throw Level3DecodeError.fileTooShort }

        // Volume scan date + time (PDB bytes 22-27 = HW 12-14)
        let scanJulian  = Int(data.readUInt16BE(at: pdbBase + 22))
        let scanSeconds = Int(data.readUInt32BE(at: pdbBase + 24))
        let scanTime    = scanJulian > 0
            ? Date(timeIntervalSince1970: Double(scanJulian - 1) * 86400.0 + Double(scanSeconds))
            : msgTime

        // Symbology block offset in halfwords from the start of the message (PDB bytes 98-101 = HW 50-51)
        let symbOffsetHW = Int(data.readInt32BE(at: pdbBase + 98))

        if symbOffsetHW > 0 {
            // Standard uncompressed path.
            let symbStart = msgStart + symbOffsetHW * 2  // halfwords → bytes
            return try parseSymbologyBlock(data: data, at: symbStart,
                                           site: site, product: product, scanTime: scanTime)
        } else {
            // Unidata archives compress the Symbology Block with bzip2.
            // PDB offset is 0; the bzip2 stream begins immediately after the PDB.
            let searchBase = pdbBase + 102
            guard let bzStart = findBzip2Start(in: data, from: searchBase) else {
                throw Level3DecodeError.noSymbologyBlock
            }
            let decompressed = try bzip2Decompress(Data(data[bzStart...]))
            return try parseSymbologyBlock(data: decompressed, at: 0,
                                           site: site, product: product, scanTime: scanTime)
        }
    }

    // MARK: - Symbology Block parser

    // ── Symbology Block ───────────────────────────────────────────────
    // [0-1] Block divider (-1)
    // [2-3] Block ID (1 = Symbology)
    // [4-7] Block length (bytes, including header)
    // [8-9] Number of layers
    private func parseSymbologyBlock(data: Data, at symbStart: Int,
                                     site: NEXRADSite, product: Level3ProductCode,
                                     scanTime: Date) throws -> Level3RadialSweep {
        guard symbStart + 10 <= data.count else { throw Level3DecodeError.fileTooShort }
        let numLayers = Int(data.readUInt16BE(at: symbStart + 8))
        guard numLayers > 0 else { throw Level3DecodeError.noPacket16 }

        // Walk layers (each layer: 2-byte divider + 4-byte length + packet data)
        var layerCursor = symbStart + 10
        for _ in 0..<numLayers {
            guard layerCursor + 6 <= data.count else { break }
            let layerLength = Int(data.readUInt32BE(at: layerCursor + 2))
            let packetBase  = layerCursor + 6

            if let sweep = tryPacket16(data: data, at: packetBase, layerLength: layerLength,
                                        site: site, product: product, scanTime: scanTime) {
                return sweep
            }
            layerCursor += 6 + layerLength
        }

        throw Level3DecodeError.noPacket16
    }

    // Scan forward from `start` for the BZh magic bytes (0x42 0x5A 0x68).
    private func findBzip2Start(in data: Data, from start: Int) -> Int? {
        let end = data.count - 2
        guard start < end else { return nil }
        for i in start..<end {
            if data[data.startIndex + i]     == 0x42 &&   // B
               data[data.startIndex + i + 1] == 0x5A &&   // Z
               data[data.startIndex + i + 2] == 0x68 {    // h
                return i
            }
        }
        return nil
    }

    // MARK: - Packet Code 16 (Digital Radial Data Array)

    // Packet 16 header (14 bytes):
    //   HW 1 (0-1):  Packet code = 16
    //   HW 2 (2-3):  Index of first range bin
    //   HW 3 (4-5):  Number of range bins
    //   HW 4 (6-7):  I center (km)
    //   HW 5 (8-9):  J center (km)
    //   HW 6 (10-11): Scale factor (range resolution × 1000, in km)
    //   HW 7 (12-13): Number of radials
    //
    // Per radial (immediately after header):
    //   HW 1 (0-1):  Bytes in this radial
    //   HW 2 (2-3):  Start angle (tenths of a degree, 0-3599)
    //   HW 3 (4-5):  Delta angle (tenths of a degree)
    //   [data bytes]

    private func tryPacket16(data: Data, at base: Int, layerLength: Int,
                              site: NEXRADSite, product: Level3ProductCode,
                              scanTime: Date) -> Level3RadialSweep? {
        guard base + 14 <= data.count else { return nil }
        let code = Int(data.readUInt16BE(at: base))
        guard code == 16 else { return nil }

        let firstBin    = Int(data.readUInt16BE(at: base + 2))
        let numBins     = Int(data.readUInt16BE(at: base + 4))
        let scaleFactor = Int(data.readUInt16BE(at: base + 10))
        let numRadials  = Int(data.readUInt16BE(at: base + 12))

        guard numBins > 0, numRadials > 0, scaleFactor > 0 else { return nil }

        // Scale factor is range resolution in km × 1000 (e.g. 250 = 0.25 km/bin).
        let binSizeKm  = Double(scaleFactor) / 1000.0
        let firstBinKm = Double(firstBin) * binSizeKm

        var radials: [Level3Radial] = []
        radials.reserveCapacity(numRadials)
        var cursor = base + 14

        for _ in 0..<numRadials {
            guard cursor + 6 <= data.count else { break }
            let numBytes   = Int(data.readUInt16BE(at: cursor))
            let rawStart   = Int(Int16(bitPattern: data.readUInt16BE(at: cursor + 2)))
            let rawDelta   = Int(Int16(bitPattern: data.readUInt16BE(at: cursor + 4)))
            cursor += 6

            guard numBytes > 0, cursor + numBytes <= data.count else {
                cursor += numBytes
                continue
            }
            let binData = Array(data[cursor ..< cursor + numBytes])
            cursor += numBytes

            var startAngle = Double(rawStart) / 10.0
            if startAngle < 0 { startAngle += 360.0 }
            let deltaAngle = abs(Double(rawDelta) / 10.0)

            radials.append(Level3Radial(startAngle: startAngle,
                                         deltaAngle: deltaAngle,
                                         data: binData))
        }

        guard !radials.isEmpty else { return nil }

        return Level3RadialSweep(
            site:           site,
            scanTime:       scanTime,
            elevationAngle: elevationForProduct(product),
            productCode:    product,
            radials:        radials,
            numBins:        numBins,
            firstBinKm:     firstBinKm,
            binSizeKm:      binSizeKm
        )
    }

    // MARK: - Helpers

    // Nominal elevation angle for each Level 3 product code.
    // N0Q/N0U are lowest-tilt (0.5°); composite products have no tilt.
    private func elevationForProduct(_ product: Level3ProductCode) -> Double {
        switch product {
        case .baseReflectivity, .baseVelocity: return 0.5
        default:                               return 0.0
        }
    }

    // If the file begins with ASCII characters (WMO/AWIPS text header),
    // scan forward for the first 0x00 byte, which is the high byte of the
    // message code (all L3 product codes fit in one byte, high byte = 0x00).
    private func findMessageStart(in data: Data) -> Int {
        guard data.count >= 2 else { return 0 }
        let first = data[data.startIndex]
        // WMO header bytes: 0x0D (CR), 0x0A (LF), 0x20-0x7E (printable ASCII)
        guard first != 0x00 else { return 0 }
        for i in 0..<min(60, data.count) {
            if data[data.startIndex + i] == 0x00 { return i }
        }
        return 0
    }
}
