import Foundation
import AVFoundation

// Maps radar gate values along a single radial to an audio tone sequence.
//
// Algorithm:
//   Gates are bucketed into 5-km range bins. Each bin plays a 30-ms sine
//   wave whose frequency encodes the max physical value found in that bin.
//   Invalid/below-threshold gates produce silence.  A half-sine envelope
//   is applied per bin to eliminate clicks at bin boundaries.
//
// Frequency table (REF):
//   0 dBZ → 200 Hz   |  25 dBZ → 400 Hz
//  50 dBZ → 800 Hz   |  75 dBZ → 1600 Hz   (log2 scale, 3 octaves)

final class SonificationEngine: @unchecked Sendable {

    static let shared = SonificationEngine()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44100

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: nil)
        try? engine.start()
    }

    // MARK: - Public API

    /// Play a tone sequence for the radial closest to `bearing` degrees in `sweep`.
    /// Returns a text description of the significant echoes found, for VoiceOver.
    @discardableResult
    func sonify(sweep: RadarSweep, bearing: Double) -> String {
        guard let radial = closestRadial(sweep: sweep, bearing: bearing) else {
            return "No radial data near bearing \(Int(bearing.rounded()))°."
        }
        let (buffer, echoes) = buildBuffer(radial: radial, momentType: sweep.momentType)
        player.stop()
        player.scheduleBuffer(buffer)
        player.play()
        return echoDescription(bearing: bearing, echoes: echoes)
    }

    // MARK: - Radial selection

    private func closestRadial(sweep: RadarSweep, bearing: Double) -> Radial? {
        sweep.radials.min(by: { angularDiff($0.azimuth, bearing) < angularDiff($1.azimuth, bearing) })
    }

    private func angularDiff(_ a: Double, _ b: Double) -> Double {
        var d = abs(a - b)
        if d > 180 { d = 360 - d }
        return d
    }

    // MARK: - PCM buffer generation

    private struct EchoSummary {
        let rangeKm: Double
        let value: Float
    }

    private func buildBuffer(radial: Radial, momentType: String) -> (AVAudioPCMBuffer, [EchoSummary]) {
        let binKm     = 5.0
        let binMs     = 0.030        // 30 ms per bin
        let maxRangeKm = radial.rangeToGate(index: max(0, radial.numGates - 1))
        let binCount  = max(1, Int(ceil(maxRangeKm / binKm)))

        // Accumulate max physical value per range bin
        var binMax = [Float?](repeating: nil, count: binCount)
        for i in 0..<radial.numGates {
            let km  = radial.rangeToGate(index: i)
            let bin = min(binCount - 1, Int(km / binKm))
            if let val = radial.physicalValue(gateIndex: i) {
                binMax[bin] = max(binMax[bin] ?? -Float.infinity, val)
            }
        }

        let samplesPerBin = Int(binMs * sampleRate)
        let totalSamples  = binCount * samplesPerBin

        let format  = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buf     = AVAudioPCMBuffer(pcmFormat: format,
                                       frameCapacity: AVAudioFrameCount(totalSamples))!
        buf.frameLength = AVAudioFrameCount(totalSamples)

        let L = buf.floatChannelData![0]
        let R = buf.floatChannelData![1]
        var phase = 0.0

        for bin in 0..<binCount {
            let s0 = bin * samplesPerBin
            let s1 = min(s0 + samplesPerBin, totalSamples)

            let (freq, amp): (Double, Float)
            if let val = binMax[bin] {
                freq = frequencyFor(value: val, momentType: momentType)
                amp  = 0.38
            } else {
                freq = 0; amp = 0
            }

            let phaseInc = freq > 0 ? 2.0 * .pi * freq / sampleRate : 0.0
            for s in s0..<s1 {
                let t = Double(s - s0) / Double(s1 - s0)
                let envelope = Float(sin(.pi * t))         // half-sine per bin
                let sample   = Float(sin(phase)) * amp * envelope
                L[s] = sample; R[s] = sample
                phase += phaseInc
            }
        }

        // Collect echoes ≥ 20 dBZ (or velocity ≠ nil) for text description
        var echoes: [EchoSummary] = []
        let threshold: Float = momentType == "REF" ? 20 : -Float.infinity
        for (bin, val) in binMax.enumerated() {
            guard let v = val, v >= threshold else { continue }
            echoes.append(EchoSummary(rangeKm: Double(bin) * binKm + binKm / 2, value: v))
        }

        return (buf, echoes)
    }

    // MARK: - Frequency mapping

    private func frequencyFor(value: Float, momentType: String) -> Double {
        switch momentType {
        case "REF":
            // 0–75 dBZ → 200–1600 Hz (3 octaves, log2)
            let clamped = Double(max(0, min(75, value)))
            return 200.0 * pow(2.0, clamped / 25.0)
        case "VEL":
            // –30…+30 m/s → 220–1100 Hz
            let norm = (Double(value) + 30.0) / 60.0
            return 220.0 + norm.clamped(to: 0...1) * 880.0
        case "ZDR":
            // –2…+5 dB → 300–900 Hz
            let norm = (Double(value) + 2.0) / 7.0
            return 300.0 + norm.clamped(to: 0...1) * 600.0
        case "RHO":
            // 0.7…1.0 → 200–1200 Hz
            let norm = (Double(value) - 0.7) / 0.3
            return 200.0 + norm.clamped(to: 0...1) * 1000.0
        default:
            let norm = Double(max(0, value)) / 100.0
            return 220.0 + norm.clamped(to: 0...1) * 660.0
        }
    }

    // MARK: - Text description

    private func echoDescription(bearing: Double, echoes: [EchoSummary]) -> String {
        let bearingStr = "\(Int(bearing.rounded()))°"
        guard !echoes.isEmpty else {
            return "Bearing \(bearingStr): no significant echoes."
        }
        let top = echoes.sorted { $0.value > $1.value }.prefix(3)
        let parts = top.map { e in
            String(format: "%.0f km (%.0f)", e.rangeKm, e.value)
        }
        return "Bearing \(bearingStr): echoes at \(parts.joined(separator: ", "))."
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
