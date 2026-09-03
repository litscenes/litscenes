import Foundation
import Testing
@testable import LitScenes

@Test func ambientBedSpecNormalizedClampsEveryField() {
    let wild = AmbientBedSpec(
        tunerHz: 39,
        bandwidthOctaves: 9,
        warmth: -0.5,
        drift: 1.5,
        crackle: -1,
        wash: 2,
        outputLevel: 7,
        seed: 0,
        durationSeconds: 4
    )
    let normalized = wild.normalized()
    #expect(normalized.tunerHz == 40)
    #expect(normalized.bandwidthOctaves == 3.0)
    #expect(normalized.warmth == 0)
    #expect(normalized.drift == 1)
    #expect(normalized.crackle == 0)
    #expect(normalized.wash == 1)
    #expect(normalized.outputLevel == 1)
    #expect(normalized.seed == 0)
    #expect(normalized.durationSeconds == 5)

    let high = AmbientBedSpec(tunerHz: 9_000, durationSeconds: 4_000).normalized()
    #expect(high.tunerHz == 8_000)
    #expect(high.durationSeconds == 600)
}

@Test func ambientBedSpecNormalizedReplacesNonFiniteWithDefaults() {
    let defaults = AmbientBedSpec()
    let broken = AmbientBedSpec(
        tunerHz: .nan,
        bandwidthOctaves: .infinity,
        warmth: -.infinity,
        drift: .nan,
        crackle: .nan,
        wash: .nan,
        outputLevel: .nan,
        durationSeconds: .nan
    )
    let normalized = broken.normalized()
    #expect(normalized.tunerHz == defaults.tunerHz)
    #expect(normalized.bandwidthOctaves == defaults.bandwidthOctaves)
    #expect(normalized.warmth == defaults.warmth)
    #expect(normalized.drift == defaults.drift)
    #expect(normalized.crackle == defaults.crackle)
    #expect(normalized.wash == defaults.wash)
    #expect(normalized.outputLevel == defaults.outputLevel)
    #expect(normalized.durationSeconds == defaults.durationSeconds)
}

@Test func ambientBedSpecNormalizedIsIdempotent() {
    let specs = [
        AmbientBedSpec(),
        AmbientBedSpec(tunerHz: 440.004, bandwidthOctaves: 0.0499, warmth: 0.333_4, durationSeconds: 117.300_2),
        AmbientBedSpec(tunerHz: 8_000, bandwidthOctaves: 3.0, warmth: 1, drift: 1, crackle: 1, wash: 1, outputLevel: 0),
        AmbientBedSpec(tunerHz: 40, bandwidthOctaves: 0.05, durationSeconds: 600)
    ]
    for spec in specs {
        let once = spec.normalized()
        #expect(once.normalized() == once)
    }
}

@Test func ambientBedSpecQuantizesToDisplayPrecision() {
    let normalized = AmbientBedSpec(tunerHz: 432.004, warmth: 0.351_23, durationSeconds: 60.000_4).normalized()
    #expect(normalized.tunerHz == 432.0)
    #expect(normalized.warmth == 0.351)
    #expect(normalized.durationSeconds == 60)

    let fine = AmbientBedSpec(tunerHz: 432.01).normalized()
    #expect(fine.tunerHz == 432.01)
}

@Test func ambientBedIdIsDeterministicAndParamSensitive() {
    let base = AmbientBedSpec()
    let baseId = ambientBedId(spec: base)
    #expect(ambientBedId(spec: base) == baseId)
    #expect(baseId.hasPrefix("ambient_"))
    #expect(baseId.count == "ambient_".count + 20)
    #expect(baseId.dropFirst("ambient_".count).allSatisfy { $0.isHexDigit })

    // Quantization-equivalent specs share an id; every real parameter change
    // moves it.
    #expect(ambientBedId(spec: AmbientBedSpec(tunerHz: 432.004)) == baseId)
    var variants: [AmbientBedSpec] = []
    variants.append(AmbientBedSpec(tunerHz: 432.01))
    variants.append(AmbientBedSpec(bandwidthOctaves: 0.7))
    variants.append(AmbientBedSpec(warmth: 0.4))
    variants.append(AmbientBedSpec(drift: 0.3))
    variants.append(AmbientBedSpec(crackle: 0.2))
    variants.append(AmbientBedSpec(wash: 0.4))
    variants.append(AmbientBedSpec(outputLevel: 0.7))
    variants.append(AmbientBedSpec(seed: 2))
    variants.append(AmbientBedSpec(durationSeconds: 120))
    for variant in variants {
        #expect(ambientBedId(spec: variant) != baseId)
    }
}

@Test func ambientBedSpecToleratesSparseAndLegacyJSON() throws {
    let defaults = AmbientBedSpec()

    let empty = try JSONCoding.decoder.decode(AmbientBedSpec.self, from: Data("{}".utf8))
    #expect(empty == defaults)

    let sparse = try JSONCoding.decoder.decode(
        AmbientBedSpec.self,
        from: Data(#"{"tuner_hz": 528.5, "seed": 42}"#.utf8)
    )
    #expect(sparse.tunerHz == 528.5)
    #expect(sparse.seed == 42)
    #expect(sparse.warmth == defaults.warmth)

    // Snake-case round-trip through the house coders.
    let encoded = try JSONCoding.encoder.encode(AmbientBedSpec(tunerHz: 110.25, seed: 9))
    let text = String(decoding: encoded, as: UTF8.self)
    #expect(text.contains("\"tuner_hz\""))
    #expect(text.contains("\"bandwidth_octaves\""))
    let decoded = try JSONCoding.decoder.decode(AmbientBedSpec.self, from: encoded)
    #expect(decoded.tunerHz == 110.25)
    #expect(decoded.seed == 9)
}

@Test func ambientBedFileNameFollowsFormat() {
    #expect(ambientBedFileName(bedId: "ambient_abc", format: .m4a) == "ambient_abc.m4a")
    #expect(ambientBedFileName(bedId: "ambient_abc", format: .caf) == "ambient_abc.caf")
}
