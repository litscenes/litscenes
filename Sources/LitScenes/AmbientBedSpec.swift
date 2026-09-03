import Foundation

/// Parameter record for one locally synthesized ambient bed. The normalized
/// spec is hashed into the bed's identity (`ambientBedId`), so field ranges and
/// quantums are load-bearing: identical normalized specs must keep producing
/// identical ids and bit-identical PCM.
struct AmbientBedSpec: Codable, Hashable, Sendable {
    static let currentSchemaVersion = "litscenes.ambient_bed.v1"

    static let tunerHzRange: ClosedRange<Double> = 40...8_000
    static let bandwidthOctavesRange: ClosedRange<Double> = 0.05...3.0
    static let durationSecondsRange: ClosedRange<Double> = 5...600
    /// Finest addressable tuner step; normalization and the id hash quantize to
    /// this, so a finer readout would be a lie.
    static let tunerQuantumHz: Double = 0.01

    var schemaVersion: String = currentSchemaVersion
    var tunerHz: Double = 432.0
    var bandwidthOctaves: Double = 0.6
    var warmth: Double = 0.35
    var drift: Double = 0.25
    var crackle: Double = 0.10
    var wash: Double = 0.30
    var outputLevel: Double = 0.8
    var seed: UInt64 = 1
    var durationSeconds: Double = 60

    init(
        schemaVersion: String = AmbientBedSpec.currentSchemaVersion,
        tunerHz: Double = 432.0,
        bandwidthOctaves: Double = 0.6,
        warmth: Double = 0.35,
        drift: Double = 0.25,
        crackle: Double = 0.10,
        wash: Double = 0.30,
        outputLevel: Double = 0.8,
        seed: UInt64 = 1,
        durationSeconds: Double = 60
    ) {
        self.schemaVersion = schemaVersion
        self.tunerHz = tunerHz
        self.bandwidthOctaves = bandwidthOctaves
        self.warmth = warmth
        self.drift = drift
        self.crackle = crackle
        self.wash = wash
        self.outputLevel = outputLevel
        self.seed = seed
        self.durationSeconds = durationSeconds
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case tunerHz
        case bandwidthOctaves
        case warmth
        case drift
        case crackle
        case wash
        case outputLevel
        case seed
        case durationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AmbientBedSpec()
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? defaults.schemaVersion
        tunerHz = try container.decodeIfPresent(Double.self, forKey: .tunerHz) ?? defaults.tunerHz
        bandwidthOctaves = try container.decodeIfPresent(Double.self, forKey: .bandwidthOctaves) ?? defaults.bandwidthOctaves
        warmth = try container.decodeIfPresent(Double.self, forKey: .warmth) ?? defaults.warmth
        drift = try container.decodeIfPresent(Double.self, forKey: .drift) ?? defaults.drift
        crackle = try container.decodeIfPresent(Double.self, forKey: .crackle) ?? defaults.crackle
        wash = try container.decodeIfPresent(Double.self, forKey: .wash) ?? defaults.wash
        outputLevel = try container.decodeIfPresent(Double.self, forKey: .outputLevel) ?? defaults.outputLevel
        seed = try container.decodeIfPresent(UInt64.self, forKey: .seed) ?? defaults.seed
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? defaults.durationSeconds
    }

    /// Clamps every field to its range, replaces non-finite values with the
    /// field's default, and quantizes (tuner to 0.01 Hz, everything else to
    /// 3 decimals) so UI float jitter can never mint a new bed id. Idempotent.
    func normalized() -> AmbientBedSpec {
        let defaults = AmbientBedSpec()
        var value = self
        value.schemaVersion = Self.currentSchemaVersion
        value.tunerHz = ambientBedNormalizedField(
            tunerHz, range: Self.tunerHzRange, scale: 100, fallback: defaults.tunerHz
        )
        value.bandwidthOctaves = ambientBedNormalizedField(
            bandwidthOctaves, range: Self.bandwidthOctavesRange, scale: 1_000, fallback: defaults.bandwidthOctaves
        )
        value.warmth = ambientBedNormalizedField(warmth, range: 0...1, scale: 1_000, fallback: defaults.warmth)
        value.drift = ambientBedNormalizedField(drift, range: 0...1, scale: 1_000, fallback: defaults.drift)
        value.crackle = ambientBedNormalizedField(crackle, range: 0...1, scale: 1_000, fallback: defaults.crackle)
        value.wash = ambientBedNormalizedField(wash, range: 0...1, scale: 1_000, fallback: defaults.wash)
        value.outputLevel = ambientBedNormalizedField(
            outputLevel, range: 0...1, scale: 1_000, fallback: defaults.outputLevel
        )
        value.durationSeconds = ambientBedNormalizedField(
            durationSeconds, range: Self.durationSecondsRange, scale: 1_000, fallback: defaults.durationSeconds
        )
        return value
    }

    /// The live-tweakable subset pushed to the preview engine on every control
    /// move. Seed and duration are deliberately absent: both are bake-shaping
    /// (noise voicing, drift-cycle snapping) and require a preview restart.
    var parameters: AmbientBedParameters {
        AmbientBedParameters(
            tunerHz: tunerHz,
            bandwidthOctaves: bandwidthOctaves,
            warmth: warmth,
            drift: drift,
            crackle: crackle,
            wash: wash,
            outputLevel: outputLevel
        )
    }
}

struct AmbientBedParameters: Hashable, Sendable {
    var tunerHz: Double
    var bandwidthOctaves: Double
    var warmth: Double
    var drift: Double
    var crackle: Double
    var wash: Double
    var outputLevel: Double
}

private func ambientBedNormalizedField(
    _ value: Double,
    range: ClosedRange<Double>,
    scale: Double,
    fallback: Double
) -> Double {
    guard value.isFinite else { return fallback }
    let clamped = min(max(value, range.lowerBound), range.upperBound)
    return (clamped * scale).rounded() / scale
}

/// Deterministic per-spec id (`videoTrimMediaId` precedent): identical
/// normalized parameters — seed and duration included — replace the same bed
/// instead of stacking duplicates. Built from formatted properties, not Codable
/// output, so the id can never move with encoding details.
func ambientBedId(spec: AmbientBedSpec) -> String {
    let value = spec.normalized()
    let key = [
        String(format: "%.2f", value.tunerHz),
        String(format: "%.3f", value.bandwidthOctaves),
        String(format: "%.3f", value.warmth),
        String(format: "%.3f", value.drift),
        String(format: "%.3f", value.crackle),
        String(format: "%.3f", value.wash),
        String(format: "%.3f", value.outputLevel),
        String(value.seed),
        String(format: "%.3f", value.durationSeconds)
    ].joined(separator: "|")
    return "ambient_\(shortHash(key, length: 20))"
}

/// Container of a baked bed. `.caf` is the seam-verification fallback: PCM has
/// mathematically perfect loop seams where AAC only has verified ones.
enum AmbientBedBakeFormat: String, Codable, Hashable, Sendable {
    case m4a
    case caf

    var fileExtension: String { rawValue }
}

func ambientBedFileName(bedId: String, format: AmbientBedBakeFormat) -> String {
    "\(bedId).\(format.fileExtension)"
}
