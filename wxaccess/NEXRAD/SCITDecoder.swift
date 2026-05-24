import CoreLocation
import Foundation

// Decodes NEXRAD Level 3 NST (Storm Tracking Information, product code 58) binary files.
//
// File layout (from THREDDS .nids):
//   ASCII WMO header  → zlib-compressed block (magic 78 xx at ~byte 41)
//   Decompressed block → second WMO header → NEXRAD product at ~byte 54
//   NEXRAD product: Message Header Block (18 B) + PDB (102 B) + Symbology Block
//   Symbology Block: 1 layer, per-cell groups of Packet 0x0002 / 0x000F / 0x0017 / 0x0018
//
// Packet 0x000F (Storm ID) record layout: I (2B) · J (2B) · ID (2 ASCII chars)
// I/J units: 1/4 km east/north of radar center (signed).

struct SCITDecoder {

    enum DecodeError: Error {
        case noZlibData, decompressionFailed(Error), invalidFormat
    }

    func decode(data: Data, site: NEXRADSite) throws -> [StormCell] {
        let bytes = [UInt8](data)

        guard let zlibOffset = findZlibOffset(bytes) else { throw DecodeError.noZlibData }

        let compressed = data.subdata(in: zlibOffset..<data.count)
        let decompressed: Data
        do {
            decompressed = try (compressed as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw DecodeError.decompressionFailed(error)
        }

        let dec = [UInt8](decompressed)

        // Skip the second WMO header embedded in the decompressed block.
        // Find "NST" marker, then advance past the trailing \r\r\n.
        let nst = Array("NST".utf8)
        guard let nstPos = findSequence(nst, in: dec) else { throw DecodeError.invalidFormat }
        var prodStart = nstPos + 3
        for i in prodStart..<min(prodStart + 12, dec.count - 2) {
            if dec[i] == 0x0d && dec[i+1] == 0x0d && dec[i+2] == 0x0a {
                prodStart = i + 3
                break
            }
        }

        // Symbology Block is at product_start + 18 (msg header) + 102 (PDB) = +120
        let symStart = prodStart + 120
        guard symStart + 10 <= dec.count else { throw DecodeError.invalidFormat }
        guard readInt16(dec, at: symStart) == -1,     // block divider
              readInt16(dec, at: symStart + 2) == 1   // block ID = Symbology
        else { throw DecodeError.invalidFormat }

        let numLayers = Int(readUInt16(dec, at: symStart + 8))
        guard numLayers >= 1 else { return [] }

        let layerStart   = symStart + 10
        guard layerStart + 6 <= dec.count else { return [] }
        let layerLen     = Int(readUInt32(dec, at: layerStart + 2))
        let layerData    = layerStart + 6
        let layerEnd     = min(layerData + layerLen, dec.count)

        return parseLayer(dec, from: layerData, to: layerEnd, site: site)
    }

    // MARK: - Layer parser

    private func parseLayer(_ dec: [UInt8], from start: Int, to end: Int,
                             site: NEXRADSite) -> [StormCell] {
        var cells:           [StormCell]             = []
        var pendingID:       String?                 = nil
        var pendingCurrent:  CLLocationCoordinate2D? = nil
        var pendingPast:     [CLLocationCoordinate2D] = []
        var pendingForecast: [CLLocationCoordinate2D] = []

        func emitPending() {
            guard let id = pendingID, let cur = pendingCurrent else { return }
            cells.append(StormCell(id: id, radarSite: site.coordinate,
                                   current: cur,
                                   past: pendingPast.reversed(),   // stored most-recent-first → flip to oldest-first
                                   forecast: pendingForecast))
            pendingID = nil; pendingCurrent = nil
            pendingPast = []; pendingForecast = []
        }

        var off = start
        while off + 4 <= end {
            let code     = Int(readUInt16(dec, at: off))
            let pktLen   = Int(readUInt16(dec, at: off + 2))
            let dataStart = off + 4
            let dataEnd   = min(dataStart + pktLen, dec.count)
            off = dataStart + pktLen

            switch code {
            case 0x0002:    // current-position marker (starts each cell group)
                emitPending()
                if pktLen >= 6 {
                    pendingCurrent = ij2coord(i: readInt16(dec, at: dataStart),
                                             j: readInt16(dec, at: dataStart + 2),
                                             site: site)
                }
            case 0x000F:    // Storm ID: I(2) J(2) ID(2)
                if pktLen >= 6 {
                    pendingID = String(bytes: [dec[dataStart+4], dec[dataStart+5]],
                                      encoding: .ascii)?
                                      .trimmingCharacters(in: .whitespaces) ?? "??"
                    if pendingCurrent == nil {
                        pendingCurrent = ij2coord(i: readInt16(dec, at: dataStart),
                                                  j: readInt16(dec, at: dataStart + 2),
                                                  site: site)
                    }
                }
            case 0x0017:    // SCIT past-track sub-packets
                parseSubpackets(dec, from: dataStart, to: dataEnd,
                                into: &pendingPast, site: site)
            case 0x0018:    // SCIT forecast sub-packets
                parseSubpackets(dec, from: dataStart, to: dataEnd,
                                into: &pendingForecast, site: site)
            default:
                break
            }
        }
        emitPending()
        return cells
    }

    private func parseSubpackets(_ dec: [UInt8], from start: Int, to end: Int,
                                  into positions: inout [CLLocationCoordinate2D],
                                  site: NEXRADSite) {
        var off = start
        while off + 4 <= end {
            let code = Int(readUInt16(dec, at: off))
            let len  = Int(readUInt16(dec, at: off + 2))
            let ds   = off + 4
            off = ds + len
            if off > dec.count { break }
            if code == 0x0002 && len >= 6 {
                positions.append(ij2coord(i: readInt16(dec, at: ds),
                                          j: readInt16(dec, at: ds + 2),
                                          site: site))
            }
        }
    }

    // MARK: - Coordinate conversion

    private func ij2coord(i: Int16, j: Int16, site: NEXRADSite) -> CLLocationCoordinate2D {
        let iKm = Double(i) * 0.25
        let jKm = Double(j) * 0.25
        let lat = site.coordinate.latitude  + jKm / 111.1
        let lon = site.coordinate.longitude + iKm / (111.1 * cos(site.coordinate.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Binary helpers

    private func findZlibOffset(_ bytes: [UInt8]) -> Int? {
        for i in 0..<(bytes.count - 1) {
            if bytes[i] == 0x78 &&
               (bytes[i+1] == 0x01 || bytes[i+1] == 0x5E ||
                bytes[i+1] == 0x9C || bytes[i+1] == 0xDA) { return i }
        }
        return nil
    }

    private func findSequence(_ seq: [UInt8], in bytes: [UInt8]) -> Int? {
        guard seq.count <= bytes.count else { return nil }
        for i in 0...(bytes.count - seq.count) {
            if bytes[i..<i+seq.count].elementsEqual(seq) { return i }
        }
        return nil
    }

    private func readUInt16(_ b: [UInt8], at i: Int) -> UInt16 {
        UInt16(b[i]) << 8 | UInt16(b[i+1])
    }
    private func readInt16(_ b: [UInt8], at i: Int) -> Int16 {
        Int16(bitPattern: readUInt16(b, at: i))
    }
    private func readUInt32(_ b: [UInt8], at i: Int) -> UInt32 {
        UInt32(b[i]) << 24 | UInt32(b[i+1]) << 16 | UInt32(b[i+2]) << 8 | UInt32(b[i+3])
    }
}
