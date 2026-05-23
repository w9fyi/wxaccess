import Foundation

// NEXRAD Archive II / Level 2 binary decoder.
//
// Format reference: ROC ICD Build 19.0 (RDA to RPG), available at
// https://www.roc.noaa.gov/WSR88D/BuildInfo/Files.aspx
//
// File layout:
//   [24 bytes]  Volume Header Record
//   [N blocks]  LDM Compressed Records, each prefixed by a signed 4-byte size:
//                 negative → |size| bytes of bzip2-compressed data
//                 positive → size bytes of uncompressed data
//
// Within each decompressed block, messages are packed in 2432-byte slots.
// Message 31 (Generic Radial Data) may span multiple slots.
// Message header is 16 bytes (8 halfwords per ICD).

enum Level2DecodeError: Error, LocalizedError {
    case fileTooShort
    case badMagic(String)
    case truncatedRecord
    case noRadials

    var errorDescription: String? {
        switch self {
        case .fileTooShort: "File is too short to be a valid NEXRAD Level 2 file"
        case .badMagic(let s): "Unexpected file header: \(s)"
        case .truncatedRecord: "Truncated LDM record"
        case .noRadials: "No radial data found in file"
        }
    }
}

final class Level2Decoder {

    // MARK: - Public API

    /// Decode a NEXRAD Level 2 Archive II file and return one RadarSweep per
    /// elevation tilt found in the file.  Returns the lowest tilt first.
    func decode(data: Data, site: NEXRADSite? = nil) throws -> [RadarSweep] {
        guard data.count >= Offsets.volumeHeaderSize else { throw Level2DecodeError.fileTooShort }

        let header = try parseVolumeHeader(data: data)
        let icao = site?.icao ?? header.icao
        let resolvedSite = site ?? NEXRADSiteCatalog.site(icao: icao)
            ?? NEXRADSite(icao: icao, name: icao, state: "", latitude: 0, longitude: 0, elevationMeters: 0)

        var offset = Offsets.volumeHeaderSize
        // keyed by rounded elevation → moment type → radials
        var allRadials: [Float: [String: [Radial]]] = [:]
        var scanTime: Date = header.date
        var vcpNumber: Int = 0

        while offset < data.count {
            guard offset + 4 <= data.count else { break }
            let controlWord = data.readInt32BE(at: offset)
            offset += 4

            guard controlWord != 0 else { break }  // 0 = end-of-file marker
            let blockSize = Int(abs(controlWord))
            guard offset + blockSize <= data.count else { break }

            // Positive control word = bzip2 compressed; negative = uncompressed.
            let blockData: Data
            if controlWord > 0 {
                let compressed = data[offset ..< offset + blockSize]
                guard let decompressed = try? bzip2Decompress(compressed) else {
                    offset += blockSize
                    continue
                }
                blockData = decompressed
            } else {
                blockData = data[offset ..< offset + blockSize]
            }
            offset += blockSize

            let (pairs, vcp, time) = parseMessages(from: blockData)
            if vcp != 0 { vcpNumber = vcp }
            if time != nil { scanTime = time! }
            for (momentType, radial) in pairs {
                let key = Float((radial.elevation * 10).rounded()) / 10
                allRadials[key, default: [:]][momentType, default: []].append(radial)
            }
        }

        guard !allRadials.isEmpty else { throw Level2DecodeError.noRadials }

        var sweeps: [RadarSweep] = []
        for (elevKey, momentMap) in allRadials {
            for (momentType, radials) in momentMap {
                sweeps.append(RadarSweep(
                    site: resolvedSite,
                    scanTime: scanTime,
                    elevationAngle: Double(elevKey),
                    vcpNumber: vcpNumber,
                    radials: radials.sorted { $0.azimuth < $1.azimuth },
                    momentType: momentType
                ))
            }
        }
        return sweeps.sorted { ($0.elevationAngle, $0.momentType) < ($1.elevationAngle, $1.momentType) }
    }

    // MARK: - Volume Header

    private struct VolumeHeader {
        let icao: String
        let date: Date
    }

    private func parseVolumeHeader(data: Data) throws -> VolumeHeader {
        // Bytes 0-8:  tape filename (e.g. "AR2V0006.")
        // Bytes 9-11: extension
        // Bytes 12-15: Modified Julian date (uint32 BE)
        // Bytes 16-19: milliseconds past midnight UTC (uint32 BE)
        // Bytes 20-23: ICAO (4 ASCII bytes)
        let magic = String(bytes: data[0..<4], encoding: .ascii) ?? ""
        guard magic == "AR2V" || magic == "ARCH" else {
            throw Level2DecodeError.badMagic(magic)
        }

        let mjd   = data.readUInt32BE(at: 12)
        let msec  = data.readUInt32BE(at: 16)
        let icao  = String(bytes: data[20..<24], encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces) ?? "UNKN"

        // NEXRAD MJD = days since Jan 1 1970, 1-based (day 1 = Jan 1 1970).
        let unixDays = Int(mjd) - 1           // convert 1-based to 0-based
        let seconds  = Double(unixDays) * 86400.0 + Double(msec) / 1000.0
        let date     = Date(timeIntervalSince1970: seconds)

        return VolumeHeader(icao: icao, date: date)
    }

    // MARK: - LDM record message parsing

    private func parseMessages(from data: Data) -> (pairs: [(String, Radial)], vcp: Int, time: Date?) {
        var pairs: [(String, Radial)] = []
        var vcp = 0
        var time: Date? = nil
        var offset = 0

        // Each message is preceded by a 12-byte CTM (Communications and Terminal
        // Manager) header, which is zero-filled in archive files.  The 16-byte
        // message header follows; its first two bytes give the message size in
        // halfwords INCLUDING the header.  Advance by ctmSize + sizeHW*2 per message.
        while offset + Offsets.ctmSize + Offsets.msgHeaderSize <= data.count {
            offset += Offsets.ctmSize  // skip CTM

            let base       = data.startIndex + offset
            let sizeHW     = data.readUInt16BE(at: base)
            let msgType    = data[base + Offsets.msgHeaderType]
            let totalBytes = Int(sizeHW) * 2

            if msgType == 31, totalBytes >= Offsets.msgHeaderSize {
                let (newPairs, t, v) = parseMessage31(data: data, msgBase: offset)
                pairs.append(contentsOf: newPairs)
                if let t { time = t }
                if v != 0 { vcp = v }
            }

            guard totalBytes >= Offsets.msgHeaderSize else { break }
            offset += totalBytes
        }

        return (pairs, vcp, time)
    }

    // MARK: - Message 31: Generic Radial Data

    // Message 31 header offsets (after the 16-byte message wrapper):
    private enum M31 {
        static let icao          = 0   // 4 bytes
        static let collectionMs  = 4   // 4 bytes uint32 BE, ms past midnight
        static let julianDate    = 8   // 2 bytes uint16 BE
        static let azimuthNum    = 10  // 2 bytes uint16 BE
        static let azimuthAngle  = 12  // 4 bytes float32 BE, degrees
        static let compression   = 16  // 1 byte (0=none, 1=bz2, 2=zlib)
        static let spare         = 17  // 1 byte
        static let radialLength  = 18  // 2 bytes uint16 BE
        static let azimuthRes    = 20  // 1 byte (1=0.5°, 2=1.0°)
        static let radialStatus  = 21  // 1 byte
        static let elevNum       = 22  // 1 byte
        static let cutSectorNum  = 23  // 1 byte
        static let elevAngle     = 24  // 4 bytes float32 BE, degrees
        static let blankBits     = 28  // 1 byte
        static let azIndexMode   = 29  // 1 byte
        static let blockCount    = 30  // 2 bytes uint16 BE
        static let blockPtrs     = 32  // 4 bytes × blockCount, byte offsets from start of M31 header
        static let headerSize    = 32  // bytes before block pointers
    }

    // Supported data moment names; "SW " has a trailing space in the ICD 3-char field.
    private static let supportedMoments: Set<String> = ["REF", "VEL", "SW ", "ZDR", "PHI", "RHO"]

    private func parseMessage31(data: Data, msgBase: Int) -> (pairs: [(String, Radial)], time: Date?, vcp: Int) {
        // msgBase is the byte offset of the 16-byte message header within `data`.
        // Message 31 body begins immediately after the header.
        let bodyBase = data.startIndex + msgBase + Offsets.msgHeaderSize

        guard bodyBase + M31.blockPtrs + 4 <= data.endIndex else { return ([], nil, 0) }

        let azimuth    = data.readFloat32BE(at: bodyBase + M31.azimuthAngle)
        let elevation  = data.readFloat32BE(at: bodyBase + M31.elevAngle)
        let blockCount = Int(data.readUInt16BE(at: bodyBase + M31.blockCount))

        guard blockCount > 0, blockCount <= 12 else { return ([], nil, 0) }

        var pairs: [(String, Radial)] = []

        for i in 0..<blockCount {
            let ptrOffset = bodyBase + M31.blockPtrs + i * 4
            guard ptrOffset + 4 <= data.endIndex else { break }
            let blockOffset = Int(data.readUInt32BE(at: ptrOffset))
            let blockBase   = bodyBase + blockOffset

            guard blockBase + 28 <= data.endIndex else { continue }

            // Data Block header (4 bytes): block type 'D' + 3-char moment name
            guard data[blockBase] == UInt8(ascii: "D") else { continue }
            let rawName = String(bytes: data[(blockBase + 1)..<(blockBase + 4)], encoding: .ascii) ?? ""
            guard Level2Decoder.supportedMoments.contains(rawName) else { continue }
            let momentType = rawName.trimmingCharacters(in: .whitespaces)

            // Moment Data Block (offsets relative to blockBase):
            //   [4-7]:   reserved
            //   [8-9]:   number of gates (uint16 BE)
            //   [10-11]: range to first gate (uint16 BE, meters)
            //   [12-13]: gate interval (uint16 BE, meters)
            //   [14-15]: SNR threshold (int16 BE, x0.125 dB) — skip
            //   [16-17]: control flags — skip
            //   [18]:    control flags byte 2 — skip
            //   [19]:    data word size (8 or 16 bits)
            //   [20-23]: scale (float32 BE)
            //   [24-27]: offset (float32 BE)
            //   [28+]:   gate data (wordSize/8 bytes per gate)
            let wordSize  = Int(data[blockBase + 19])  // 8 or 16
            let numGates  = Int(data.readUInt16BE(at: blockBase + 8))
            let firstGate = Int(data.readUInt16BE(at: blockBase + 10))
            let gateSize  = Int(data.readUInt16BE(at: blockBase + 12))
            let scale     = data.readFloat32BE(at: blockBase + 20)
            let offset    = data.readFloat32BE(at: blockBase + 24)
            let dataStart = blockBase + 28

            let bytesNeeded = numGates * (wordSize == 16 ? 2 : 1)
            guard dataStart + bytesNeeded <= data.endIndex, numGates > 0 else { continue }

            let gateValues: [UInt16]
            if wordSize == 16 {
                gateValues = (0..<numGates).map { data.readUInt16BE(at: dataStart + $0 * 2) }
            } else {
                gateValues = data[dataStart..<(dataStart + numGates)].map { UInt16($0) }
            }

            pairs.append((momentType, Radial(
                azimuth: Double(azimuth),
                elevation: Double(elevation),
                firstGateMeters: firstGate,
                gateSizeMeters: gateSize,
                numGates: numGates,
                scale: scale,
                offset: offset,
                data: gateValues
            )))
        }

        // Time from M31 radial header; NEXRAD MJD is 1-based days since Jan 1 1970.
        let ms  = data.readUInt32BE(at: bodyBase + M31.collectionMs)
        let mjd = Int(data.readUInt16BE(at: bodyBase + M31.julianDate))
        let t   = Date(timeIntervalSince1970: Double(mjd - 1) * 86400.0 + Double(ms) / 1000.0)

        return (pairs, t, 0)
    }

    // MARK: - Offsets

    private enum Offsets {
        static let volumeHeaderSize = 24
        static let ctmSize          = 12  // CTM header preceding each message (zero in archives)
        static let msgHeaderSize    = 16
        static let msgHeaderType    = 3   // byte offset of message type within the 16-byte header
    }
}

// MARK: - Data reading helpers (big-endian)

extension Data {
    func readUInt16BE(at index: Index) -> UInt16 {
        guard index + 2 <= endIndex else { return 0 }
        return UInt16(self[index]) << 8 | UInt16(self[index + 1])
    }

    func readUInt32BE(at index: Index) -> UInt32 {
        guard index + 4 <= endIndex else { return 0 }
        return UInt32(self[index]) << 24
             | UInt32(self[index + 1]) << 16
             | UInt32(self[index + 2]) << 8
             | UInt32(self[index + 3])
    }

    func readInt32BE(at index: Index) -> Int32 {
        Int32(bitPattern: readUInt32BE(at: index))
    }

    func readFloat32BE(at index: Index) -> Float {
        Float(bitPattern: readUInt32BE(at: index))
    }
}
