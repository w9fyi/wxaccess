import Foundation

enum EchoInterpretation {

    // Standard 4/3 Earth-radius beam height model (km AGL).
    static func beamHeightKm(rangeKm: Double, elevationDeg: Double) -> Double {
        let re43  = 6371.0 * 4.0 / 3.0
        let elRad = elevationDeg * .pi / 180.0
        return sqrt(rangeKm * rangeKm + re43 * re43 + 2 * rangeKm * re43 * sin(elRad)) - re43
    }

    // Returns (reading, assessment, confidence) for a VoiceOver announcement.
    // `reading` is the raw numbers; `assessment` is the plain-English interpretation;
    // `confidence` qualifies how much to trust the assessment at this range/altitude.
    static func interpret(
        ref: Float?, zdr: Float?, rho: Float?, vel: Float?, sw: Float?,
        rangeKm: Double, elevationDeg: Double
    ) -> (reading: String, assessment: String, confidence: String) {

        guard let ref else {
            return ("No echo", "Clear air or precipitation below detection threshold.", "N/A")
        }

        let beamH    = beamHeightKm(rangeKm: rangeKm, elevationDeg: elevationDeg)
        let conf     = confidenceLabel(beamH: beamH)
        let beamNote = String(format: "Beam at %.1f km altitude.", beamH)

        // Build numeric reading string
        var parts: [String] = [String(format: "%.0f dBZ", ref)]
        if let z = zdr { parts.append(String(format: "ZDR %.1f dB", z)) }
        if let r = rho { parts.append(String(format: "correlation %.2f", r)) }
        if let v = vel {
            let dir = v < 0 ? "toward radar" : "away"
            parts.append(String(format: "velocity %.0f m/s %@", abs(v), dir))
        }
        if let s = sw  { parts.append(String(format: "spectrum width %.1f m/s", s)) }
        let reading = parts.joined(separator: ", ")

        let assessment: String

        // Tornado debris signature — only meaningful at close range on a low tilt.
        if let rho, rho < 0.80, ref > 20, rangeKm < 150 {
            assessment = "Tornado debris signature — very low correlation with detectable " +
                         "reflectivity suggests lofted debris. Only reliable at close range on " +
                         "a low tilt. \(beamNote)"
            return (reading, assessment, "High if debris present")
        }

        // Large hail
        if ref >= 55, let zdr, zdr <= 0.5, let rho, rho > 0.92 {
            assessment = "Large hail likely — very high reflectivity with near-zero ZDR indicates " +
                         "tumbling ice particles. High correlation confirms meteorological origin. " +
                         "Hail aloft may melt before reaching ground. \(beamNote)"
            return (reading, assessment, conf)
        }

        // Possible hail or rain/hail mix
        if ref >= 45, let zdr, zdr < 1.0 {
            assessment = "Possible hail or heavy rain/hail mix — elevated reflectivity with " +
                         "reduced ZDR suggests ice presence in the precipitation. \(beamNote)"
            return (reading, assessment, conf)
        }

        // Low RHO — melting layer or non-meteorological
        if let rho, rho < 0.85, ref >= 10 {
            if let zdr, zdr > 1.5 {
                assessment = "Melting precipitation layer — snow converting to rain. Reflectivity, " +
                             "ZDR, and correlation values are typical of the bright band. " +
                             "Surface precipitation may differ significantly. \(beamNote)"
            } else {
                assessment = "Non-meteorological returns — low correlation suggests ground clutter, " +
                             "biological echoes, or other non-precipitation target. \(beamNote)"
            }
            return (reading, assessment, conf)
        }

        // Heavy rain with large drops (high ZDR confirms oblate drops, not hail)
        if ref >= 40, let zdr, zdr >= 3.0, let rho, rho > 0.97 {
            assessment = "Heavy rain with large drops — high ZDR indicates large oblate raindrops; " +
                         "high correlation confirms uniform rain. \(beamNote)"
            return (reading, assessment, conf)
        }

        // Heavy rain
        if ref >= 35, let rho, rho > 0.95 {
            assessment = "Heavy rain. \(beamNote)"
            return (reading, assessment, conf)
        }

        // Moderate rain
        if ref >= 20, let rho, rho > 0.95 {
            assessment = "Moderate rain. \(beamNote)"
            return (reading, assessment, conf)
        }

        // Biological echoes (insects/birds: low dBZ, very high ZDR, moderate RHO)
        if ref < 25, let zdr, zdr > 3.0, let rho, rho < 0.97 {
            assessment = "Likely biological echoes — high ZDR with moderate reflectivity " +
                         "suggests insects or birds. \(beamNote)"
            return (reading, assessment, "Moderate")
        }

        // Light precipitation or drizzle
        if ref >= 5 {
            assessment = "Light precipitation or drizzle. \(beamNote)"
            return (reading, assessment, conf)
        }

        // Very weak / trace
        assessment = "Very weak echo — trace return only. \(beamNote)"
        return (reading, assessment, "Low")
    }

    private static func confidenceLabel(beamH: Double) -> String {
        if beamH < 2.0 { return "High" }
        if beamH < 4.0 { return String(format: "Moderate — beam sampling at %.1f km altitude", beamH) }
        return String(format: "Low — beam at %.1f km altitude; surface conditions may differ significantly", beamH)
    }
}
