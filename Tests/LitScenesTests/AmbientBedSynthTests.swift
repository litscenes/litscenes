import Foundation
import Testing
@testable import LitScenes

private func ambientTestRMS(_ samples: [Float]) -> Double {
    guard !samples.isEmpty else { return 0 }
    let sum = samples.reduce(into: 0.0) { $0 += Double($1) * Double($1) }
    return (sum / Double(samples.count)).squareRoot()
}

private func ambientTestDecibels(_ rms: Double) -> Double {
    20 * log10(max(rms, 1e-12))
}

@Test func ambientBedSynthIsBitDeterministic() {
    let spec = AmbientBedSpec(seed: 7)
    let first = AmbientBedSynth(spec: spec).renderChunk(frameCount: 144_000)
    let second = AmbientBedSynth(spec: spec).renderChunk(frameCount: 144_000)
    #expect(first.left.map(\.bitPattern) == second.left.map(\.bitPattern))
    #expect(first.right.map(\.bitPattern) == second.right.map(\.bitPattern))
}

@Test func ambientBedSynthOutputIsIndependentOfCallerChunking() {
    let spec = AmbientBedSpec(seed: 3)
    let whole = AmbientBedSynth(spec: spec).renderChunk(frameCount: 144_000)

    let sliced = AmbientBedSynth(spec: spec)
    var left: [Float] = []
    var right: [Float] = []
    left.reserveCapacity(144_000)
    right.reserveCapacity(144_000)
    // 480 is deliberately not a multiple of the 64-frame control block.
    for _ in 0..<300 {
        let chunk = sliced.renderChunk(frameCount: 480)
        left.append(contentsOf: chunk.left)
        right.append(contentsOf: chunk.right)
    }
    #expect(whole.left.map(\.bitPattern) == left.map(\.bitPattern))
    #expect(whole.right.map(\.bitPattern) == right.map(\.bitPattern))
}

@Test func ambientBedSynthStaysStableAtExtremeSettings() {
    let spec = AmbientBedSpec(
        tunerHz: 8_000,
        bandwidthOctaves: 0.05,
        warmth: 1,
        drift: 1,
        crackle: 1,
        wash: 1,
        outputLevel: 1,
        seed: 11,
        durationSeconds: 30
    )
    let synth = AmbientBedSynth(spec: spec)
    var peak: Float = 0
    var sum = 0.0
    var count = 0
    for _ in 0..<45 {
        let chunk = synth.renderChunk(frameCount: 32_000)
        for sample in chunk.left {
            #expect(sample.isFinite)
            peak = max(peak, abs(sample))
            sum += Double(sample) * Double(sample)
        }
        for sample in chunk.right {
            #expect(sample.isFinite)
            peak = max(peak, abs(sample))
            sum += Double(sample) * Double(sample)
        }
        count += chunk.left.count + chunk.right.count
    }
    let decibels = ambientTestDecibels((sum / Double(count)).squareRoot())
    #expect(peak <= 1)
    #expect(decibels > -60)
    #expect(decibels < -6)
}

@Test func ambientBedSynthSurvivesTunerJumpMidRender() {
    let synth = AmbientBedSynth(spec: AmbientBedSpec(tunerHz: 200, seed: 5))
    _ = synth.renderChunk(frameCount: 48_000)
    synth.setTargets(AmbientBedSpec(tunerHz: 4_000).parameters)
    let after = synth.renderChunk(frameCount: 96_000)
    for sample in after.left {
        #expect(sample.isFinite)
        #expect(abs(sample) <= 1)
    }
    // Non-finite targets are absorbed, not propagated.
    synth.setTargets(AmbientBedParameters(
        tunerHz: .nan, bandwidthOctaves: .nan, warmth: .nan, drift: .nan,
        crackle: .nan, wash: .nan, outputLevel: .nan
    ))
    let cleaned = synth.renderChunk(frameCount: 24_000)
    for sample in cleaned.left {
        #expect(sample.isFinite)
    }
}

@Test func ambientBedENBWMakeupKeepsSweepLoudnessRoughlyConstant() {
    // Pure-function shape: makeup falls monotonically as the band widens or
    // rises, and clamps at the documented range.
    let narrow = ambientBedENBWMakeupGain(centerHz: 1_000, q: ambientBedQ(bandwidthOctaves: 0.05))
    let reference = ambientBedENBWMakeupGain(centerHz: 1_000, q: ambientBedQ(bandwidthOctaves: 0.6))
    let wide = ambientBedENBWMakeupGain(centerHz: 1_000, q: ambientBedQ(bandwidthOctaves: 3.0))
    #expect(narrow > reference)
    #expect(reference > wide)
    #expect(abs(reference - 1) < 1e-9)
    #expect(ambientBedENBWMakeupGain(centerHz: 8_000, q: 30) <= 8.0)
    #expect(ambientBedENBWMakeupGain(centerHz: 40, q: 0.4) >= 0.25)

    // End to end: a low band and a high band land within a few dB of each
    // other (drift/crackle/wash off so only the tuner moves).
    func rms(atHz hz: Double) -> Double {
        let spec = AmbientBedSpec(
            tunerHz: hz, warmth: 0, drift: 0, crackle: 0, wash: 0, seed: 21
        )
        let synth = AmbientBedSynth(spec: spec)
        _ = synth.renderChunk(frameCount: 24_000)
        return ambientTestRMS(synth.renderChunk(frameCount: 96_000).left)
    }
    let low = ambientTestDecibels(rms(atHz: 200))
    let high = ambientTestDecibels(rms(atHz: 4_000))
    #expect(abs(low - high) < 4)
}

@Test func ambientBedSynthSeedsAreIndependent() {
    let first = AmbientBedSynth(spec: AmbientBedSpec(seed: 1)).renderChunk(frameCount: 48_000)
    let second = AmbientBedSynth(spec: AmbientBedSpec(seed: 2)).renderChunk(frameCount: 48_000)
    #expect(first.left != second.left)

    // Band character survives a seed change: with crackle/wash off, the two
    // seeds' band RMS match within a dB even though the PCM differs.
    func bandRMS(seed: UInt64) -> Double {
        let spec = AmbientBedSpec(warmth: 0, drift: 0, crackle: 0, wash: 0, seed: seed)
        let synth = AmbientBedSynth(spec: spec)
        _ = synth.renderChunk(frameCount: 24_000)
        return ambientTestRMS(synth.renderChunk(frameCount: 96_000).left)
    }
    let difference = abs(ambientTestDecibels(bandRMS(seed: 31)) - ambientTestDecibels(bandRMS(seed: 32)))
    #expect(difference < 1)
}

@Test func ambientBedDriftRateIsIntegerCyclesOverDuration() {
    for duration in [5.0, 30, 60, 117.3, 240, 600] {
        let cycles = ambientBedDriftRateHz(durationSeconds: duration) * duration
        #expect(abs(cycles - cycles.rounded()) < 1e-9)
        #expect(cycles >= 1)
    }
}

@Test func ambientBedMappingFunctionsClampTheirInputs() {
    #expect(ambientBedQ(bandwidthOctaves: 0.05) > 28)
    #expect(ambientBedQ(bandwidthOctaves: 0.05) < 30)
    #expect(ambientBedQ(bandwidthOctaves: 3.0) > 0.3)
    #expect(ambientBedQ(bandwidthOctaves: 3.0) < 0.5)
    #expect(ambientBedQ(bandwidthOctaves: -4) == ambientBedQ(bandwidthOctaves: 0.05))
    #expect(ambientBedQ(bandwidthOctaves: .nan).isFinite)

    #expect(ambientBedWarmthCutoffHz(0) == 16_000)
    #expect(abs(ambientBedWarmthCutoffHz(1) - 1_400) < 1e-6)
    #expect(ambientBedWarmthCutoffHz(0.5) > 1_400)
    #expect(ambientBedWarmthCutoffHz(0.5) < 16_000)
    #expect(ambientBedWarmthCutoffHz(.nan) == 16_000)

    #expect(ambientBedCrackleDensityPerSecond(0) == 0.3)
    #expect(abs(ambientBedCrackleDensityPerSecond(1) - 18.0) < 1e-9)
    #expect(ambientBedCrackleDensityPerSecond(0.5) < 9)

    #expect(ambientBedSoftClip(0) == 0)
    #expect(abs(ambientBedSoftClip(0.25)) < 0.26)
    #expect(ambientBedSoftClip(100) <= 1)
    #expect(ambientBedSoftClip(-100) >= -1)
    #expect(ambientBedSoftClip(3) <= 1)
}
