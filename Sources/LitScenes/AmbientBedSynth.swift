import Foundation

/// Tunable constants for the ambient-bed synthesizer. These are part of the
/// sound and of bake determinism: changing one re-voices every bed baked after
/// the change (stored ids stay valid — identity hashes the spec, not the PCM).
enum AmbientBedDSP {
    static let sampleRate: Double = 48_000
    /// Coefficients, smoothers, and the drift LFO advance once per block, and
    /// the block phase is carried across `render` calls — output depends only
    /// on spec + absolute frame index, never on how callers slice frames.
    static let controlBlockFrames = 64
    static let smoothingTimeConstantSeconds: Double = 0.06
    static let driftMaxDepthOctaves: Double = 0.3
    static let driftCyclesPerSecond: Double = 0.07
    static let modulatedCenterFloorHz: Double = 20
    static let modulatedCenterCeilingHz: Double = 12_000
    static let enbwReferenceHz: Double = 1_000
    static let enbwReferenceBandwidthOctaves: Double = 0.6
    static let enbwMakeupGainRange: ClosedRange<Double> = 0.25...8.0
    static let warmthCutoffMaxHz: Double = 16_000
    static let warmthCutoffMinHz: Double = 1_400
    static let warmthMaxMakeup: Double = 0.25
    static let outputHighPassHz: Double = 30
    static let crackleBaseDensityPerSecond: Double = 0.3
    static let crackleMaxExtraDensityPerSecond: Double = 17.7
    static let crackleHighPassHz: Double = 180
    static let crackleBusGain: Double = 0.55
    static let crackleVoiceCount = 8
    static let washAllpassGain: Float = 0.5
    static let washAllpassDelaysLeft = [241, 613]
    static let washAllpassDelaysRight = [251, 631]
    static let washCombDelaysLeft = [1_427, 1_783, 2_099]
    static let washCombDelaysRight = [1_493, 1_723, 2_153]
    static let washDamping: Float = 0.35
    static let washFeedbackBase: Double = 0.74
    static let washFeedbackSpan: Double = 0.14
    static let washMixArc: Double = 0.62
    static let washWetScale: Float = 0.8 / 3.0
    static let washCrossFeed: Float = 0.3
    static let masterCalibration: Double = 1.6
    static let softClipInputLimit: Float = 3
}

/// SplitMix64 — pure integer ops plus one exact int→float conversion, so noise
/// is bit-deterministic on every machine.
struct AmbientBedSplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Top 24 bits → exactly representable Float in [-1, 1).
    mutating func nextFloat() -> Float {
        Float(next() >> 40) * (2.0 / 16_777_216.0) - 1.0
    }

    /// Top 53 bits → Double in [0, 1).
    mutating func nextUnitDouble() -> Double {
        Double(next() >> 11) * 0x1p-53
    }
}

// MARK: - Pure parameter mappings

/// RBJ analog bandwidth→Q relation (the digital correction is deliberately
/// omitted: WIDTH is a feel control, not a measurement contract).
func ambientBedQ(bandwidthOctaves: Double) -> Double {
    let range = AmbientBedSpec.bandwidthOctavesRange
    let bandwidth = min(max(bandwidthOctaves.isFinite ? bandwidthOctaves : range.upperBound, range.lowerBound), range.upperBound)
    return 1 / (2 * sinh(log(2) / 2 * bandwidth))
}

/// A unity-peak band-pass over white noise outputs power proportional to its
/// equivalent noise bandwidth, ENBW = (π/2)·fc/Q — so sweeping up or widening
/// gets louder. This makeup keeps the tuner sweep at roughly constant loudness,
/// which is what makes fine tuning usable. Clamped to −12…+18 dB.
func ambientBedENBWMakeupGain(centerHz: Double, q: Double) -> Double {
    guard centerHz.isFinite, q.isFinite, centerHz > 0, q > 0 else { return 1 }
    let referenceENBW = (Double.pi / 2) * AmbientBedDSP.enbwReferenceHz
        / ambientBedQ(bandwidthOctaves: AmbientBedDSP.enbwReferenceBandwidthOctaves)
    let enbw = (Double.pi / 2) * centerHz / q
    let gain = (referenceENBW / enbw).squareRoot()
    let range = AmbientBedDSP.enbwMakeupGainRange
    return min(max(gain, range.lowerBound), range.upperBound)
}

/// Warmth 0 → 16 kHz (transparent), 1 → 1.4 kHz (soft wash), exponential.
func ambientBedWarmthCutoffHz(_ warmth: Double) -> Double {
    let amount = min(max(warmth.isFinite ? warmth : 0, 0), 1)
    return AmbientBedDSP.warmthCutoffMaxHz
        * pow(AmbientBedDSP.warmthCutoffMinHz / AmbientBedDSP.warmthCutoffMaxHz, amount)
}

/// Drift rate snapped to an integer number of cycles over the loop duration —
/// the loop-seam keystone: modulation phase at the loop end equals the phase at
/// the start regardless of the seeded initial phase.
func ambientBedDriftRateHz(durationSeconds: Double) -> Double {
    let range = AmbientBedSpec.durationSecondsRange
    let duration = min(max(durationSeconds.isFinite ? durationSeconds : range.lowerBound, range.lowerBound), range.upperBound)
    let cycles = max(1, (AmbientBedDSP.driftCyclesPerSecond * duration).rounded())
    return cycles / duration
}

/// Superlinear so low settings stay sparse: 0.3…18 ticks per second.
func ambientBedCrackleDensityPerSecond(_ amount: Double) -> Double {
    let clamped = min(max(amount.isFinite ? amount : 0, 0), 1)
    return AmbientBedDSP.crackleBaseDensityPerSecond
        + AmbientBedDSP.crackleMaxExtraDensityPerSecond * clamped * clamped
}

/// tanh-shaped Padé rational — transparent below |0.5|, asymptotic to ±1,
/// polynomial only (deterministic, libm-free), NaN-free for finite input.
func ambientBedSoftClip(_ x: Float) -> Float {
    let limit = AmbientBedDSP.softClipInputLimit
    let clamped = min(max(x, -limit), limit)
    let squared = clamped * clamped
    return clamped * (27 + squared) / (27 + 9 * squared)
}

// MARK: - Filter state

private struct AmbientTPTBandPass {
    var ic1: Float = 0
    var ic2: Float = 0

    /// Simper's trapezoidal (TPT) state-variable filter, band output ×k so the
    /// peak gain at fc is unity for any Q. Chosen over Chamberlin/RBJ because
    /// it stays stable for any fc < fs/2 and any Q under per-block coefficient
    /// modulation — which the drift LFO does continuously.
    mutating func band(_ input: Float, a1: Float, a2: Float, a3: Float, k: Float) -> Float {
        let v3 = input - ic2
        let v1 = a1 * ic1 + a2 * v3
        let v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2 * v1 - ic1
        ic2 = 2 * v2 - ic2
        return k * v1
    }
}

private struct AmbientOnePoleLowPass {
    var y: Float = 0

    mutating func process(_ x: Float, coefficient: Float) -> Float {
        y += (1 - coefficient) * (x - y)
        return y
    }
}

private struct AmbientOnePoleHighPass {
    var y: Float = 0
    var x1: Float = 0

    mutating func process(_ x: Float, coefficient: Float) -> Float {
        y = coefficient * (y + x - x1)
        x1 = x
        return y
    }
}

private struct AmbientSchroederAllpass {
    var buffer: [Float]
    var index = 0

    init(delay: Int) {
        buffer = [Float](repeating: 0, count: max(delay, 1))
    }

    mutating func process(_ x: Float) -> Float {
        let delayed = buffer[index]
        let output = delayed - AmbientBedDSP.washAllpassGain * x
        buffer[index] = x + AmbientBedDSP.washAllpassGain * delayed
        index += 1
        if index == buffer.count { index = 0 }
        return output
    }
}

private struct AmbientDampedComb {
    var buffer: [Float]
    var index = 0
    var filterStore: Float = 0

    init(delay: Int) {
        buffer = [Float](repeating: 0, count: max(delay, 1))
    }

    mutating func process(_ input: Float, feedback: Float) -> Float {
        let output = buffer[index]
        filterStore = output * (1 - AmbientBedDSP.washDamping) + filterStore * AmbientBedDSP.washDamping
        buffer[index] = input + filterStore * feedback
        index += 1
        if index == buffer.count { index = 0 }
        return output
    }
}

private struct AmbientWashChannel {
    var allpass1: AmbientSchroederAllpass
    var allpass2: AmbientSchroederAllpass
    var comb1: AmbientDampedComb
    var comb2: AmbientDampedComb
    var comb3: AmbientDampedComb

    init(allpassDelays: [Int], combDelays: [Int]) {
        allpass1 = AmbientSchroederAllpass(delay: allpassDelays[0])
        allpass2 = AmbientSchroederAllpass(delay: allpassDelays[1])
        comb1 = AmbientDampedComb(delay: combDelays[0])
        comb2 = AmbientDampedComb(delay: combDelays[1])
        comb3 = AmbientDampedComb(delay: combDelays[2])
    }

    mutating func process(_ input: Float, feedback: Float) -> Float {
        let diffused = allpass2.process(allpass1.process(input))
        return comb1.process(diffused, feedback: feedback)
            + comb2.process(diffused, feedback: feedback)
            + comb3.process(diffused, feedback: feedback)
    }
}

private struct AmbientCrackleVoice {
    var amplitude: Float = 0
    var decay: Float = 0
    var gainLeft: Float = 0
    var gainRight: Float = 0
}

// MARK: - Synth

/// The ambient-bed voice: seeded dual-mono noise → tunable TPT band-pass with
/// equal-loudness makeup → crackle ticks → warmth low-pass → 30 Hz rumble
/// high-pass → Schroeder wash → level → soft clip. A class on purpose: the wash
/// delay lines are ~55 KB of storage, and value-typed copies would mean CoW
/// allocation on the audio render thread.
///
/// NOT Sendable — single-owner. Once handed to a preview engine's render block,
/// only that thread may touch it (including `setTargets`).
final class AmbientBedSynth {
    private let driftRateHz: Double

    private var noiseLeft: AmbientBedSplitMix64
    private var noiseRight: AmbientBedSplitMix64
    private var crackleRandom: AmbientBedSplitMix64

    private var targetTunerLog2: Double
    private var targetBandwidthOctaves: Double
    private var targetWarmth: Double
    private var targetDrift: Double
    private var targetCrackle: Double
    private var targetWash: Double
    private var targetLevel: Double

    private var smoothedTunerLog2: Double
    private var smoothedBandwidthOctaves: Double
    private var smoothedWarmth: Double
    private var smoothedDrift: Double
    private var smoothedCrackle: Double
    private var smoothedWash: Double
    private var smoothedLevel: Double

    private var lfoPhase: Double
    private var framesIntoBlock = 0

    private var svfA1: Float = 0
    private var svfA2: Float = 0
    private var svfA3: Float = 0
    private var svfK: Float = 1
    private var makeupGain: Float = 1
    private var warmthCoefficient: Float = 0
    private var warmthMakeup: Float = 1
    private var crackleSpawnThreshold: Double = 0
    private var crackleGain: Float = 0
    private var washFeedback: Float = 0
    private var washDryGain: Float = 1
    private var washWetGain: Float = 0
    private var outputGain: Float = 0

    private var bandLeft = AmbientTPTBandPass()
    private var bandRight = AmbientTPTBandPass()
    private var warmthLeft = AmbientOnePoleLowPass()
    private var warmthRight = AmbientOnePoleLowPass()
    private var rumbleLeft = AmbientOnePoleHighPass()
    private var rumbleRight = AmbientOnePoleHighPass()
    private var crackleHighLeft = AmbientOnePoleHighPass()
    private var crackleHighRight = AmbientOnePoleHighPass()
    private var crackleVoices = [AmbientCrackleVoice](
        repeating: AmbientCrackleVoice(), count: AmbientBedDSP.crackleVoiceCount
    )
    private var crackleNextVoice = 0
    private var washLeft: AmbientWashChannel
    private var washRight: AmbientWashChannel

    private let rumbleCoefficient: Float
    private let crackleHighCoefficient: Float
    private let smoothingAlpha: Double

    init(spec: AmbientBedSpec) {
        let normalized = spec.normalized()
        driftRateHz = ambientBedDriftRateHz(durationSeconds: normalized.durationSeconds)

        var master = AmbientBedSplitMix64(state: normalized.seed)
        noiseLeft = AmbientBedSplitMix64(state: master.next())
        noiseRight = AmbientBedSplitMix64(state: master.next())
        crackleRandom = AmbientBedSplitMix64(state: master.next())
        var lfoRandom = AmbientBedSplitMix64(state: master.next())
        lfoPhase = lfoRandom.nextUnitDouble()

        targetTunerLog2 = log2(normalized.tunerHz)
        targetBandwidthOctaves = normalized.bandwidthOctaves
        targetWarmth = normalized.warmth
        targetDrift = normalized.drift
        targetCrackle = normalized.crackle
        targetWash = normalized.wash
        targetLevel = normalized.outputLevel

        // Smoothers pinned at their targets: bakes are steady-state from
        // sample 0 (no fade-in artifact in the loop head), and the preview
        // sounds right immediately.
        smoothedTunerLog2 = targetTunerLog2
        smoothedBandwidthOctaves = targetBandwidthOctaves
        smoothedWarmth = targetWarmth
        smoothedDrift = targetDrift
        smoothedCrackle = targetCrackle
        smoothedWash = targetWash
        smoothedLevel = targetLevel

        washLeft = AmbientWashChannel(
            allpassDelays: AmbientBedDSP.washAllpassDelaysLeft,
            combDelays: AmbientBedDSP.washCombDelaysLeft
        )
        washRight = AmbientWashChannel(
            allpassDelays: AmbientBedDSP.washAllpassDelaysRight,
            combDelays: AmbientBedDSP.washCombDelaysRight
        )

        rumbleCoefficient = Float(exp(-2 * Double.pi * AmbientBedDSP.outputHighPassHz / AmbientBedDSP.sampleRate))
        crackleHighCoefficient = Float(exp(-2 * Double.pi * AmbientBedDSP.crackleHighPassHz / AmbientBedDSP.sampleRate))
        let blockSeconds = Double(AmbientBedDSP.controlBlockFrames) / AmbientBedDSP.sampleRate
        smoothingAlpha = 1 - exp(-blockSeconds / AmbientBedDSP.smoothingTimeConstantSeconds)
    }

    /// Smoothed retarget of the live parameters. Values are clamped here; the
    /// ~60 ms one-pole smoothers glide toward them per control block (tuner in
    /// log2 domain, so sweeps travel octaves, not raw Hz).
    func setTargets(_ parameters: AmbientBedParameters) {
        let hzRange = AmbientBedSpec.tunerHzRange
        let hz = min(max(parameters.tunerHz.isFinite ? parameters.tunerHz : 432, hzRange.lowerBound), hzRange.upperBound)
        targetTunerLog2 = log2(hz)
        let bandwidthRange = AmbientBedSpec.bandwidthOctavesRange
        targetBandwidthOctaves = min(
            max(parameters.bandwidthOctaves.isFinite ? parameters.bandwidthOctaves : 0.6, bandwidthRange.lowerBound),
            bandwidthRange.upperBound
        )
        targetWarmth = ambientBedUnitClamp(parameters.warmth)
        targetDrift = ambientBedUnitClamp(parameters.drift)
        targetCrackle = ambientBedUnitClamp(parameters.crackle)
        targetWash = ambientBedUnitClamp(parameters.wash)
        targetLevel = ambientBedUnitClamp(parameters.outputLevel)
    }

    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frameCount: Int) {
        var written = 0
        while written < frameCount {
            if framesIntoBlock == 0 {
                updateControlBlock()
            }
            let framesThisSlice = min(AmbientBedDSP.controlBlockFrames - framesIntoBlock, frameCount - written)
            renderSlice(left: left + written, right: right + written, frameCount: framesThisSlice)
            framesIntoBlock += framesThisSlice
            if framesIntoBlock == AmbientBedDSP.controlBlockFrames {
                framesIntoBlock = 0
            }
            written += framesThisSlice
        }
    }

    /// Array convenience for the baker and tests.
    func renderChunk(frameCount: Int) -> (left: [Float], right: [Float]) {
        var left = [Float](repeating: 0, count: frameCount)
        var right = [Float](repeating: 0, count: frameCount)
        left.withUnsafeMutableBufferPointer { leftBuffer in
            right.withUnsafeMutableBufferPointer { rightBuffer in
                guard let leftBase = leftBuffer.baseAddress, let rightBase = rightBuffer.baseAddress else { return }
                render(left: leftBase, right: rightBase, frameCount: frameCount)
            }
        }
        return (left, right)
    }

    private func updateControlBlock() {
        smoothedTunerLog2 += smoothingAlpha * (targetTunerLog2 - smoothedTunerLog2)
        smoothedBandwidthOctaves += smoothingAlpha * (targetBandwidthOctaves - smoothedBandwidthOctaves)
        smoothedWarmth += smoothingAlpha * (targetWarmth - smoothedWarmth)
        smoothedDrift += smoothingAlpha * (targetDrift - smoothedDrift)
        smoothedCrackle += smoothingAlpha * (targetCrackle - smoothedCrackle)
        smoothedWash += smoothingAlpha * (targetWash - smoothedWash)
        smoothedLevel += smoothingAlpha * (targetLevel - smoothedLevel)

        lfoPhase += driftRateHz * Double(AmbientBedDSP.controlBlockFrames) / AmbientBedDSP.sampleRate
        lfoPhase -= lfoPhase.rounded(.down)
        let depth = smoothedDrift * AmbientBedDSP.driftMaxDepthOctaves
        let modulatedCenter = min(
            max(
                pow(2, smoothedTunerLog2 + depth * sin(2 * Double.pi * lfoPhase)),
                AmbientBedDSP.modulatedCenterFloorHz
            ),
            AmbientBedDSP.modulatedCenterCeilingHz
        )
        let q = ambientBedQ(bandwidthOctaves: smoothedBandwidthOctaves)
        let g = tan(Double.pi * modulatedCenter / AmbientBedDSP.sampleRate)
        let k = 1 / q
        let a1 = 1 / (1 + g * (g + k))
        svfA1 = Float(a1)
        svfA2 = Float(g * a1)
        svfA3 = Float(g * g * a1)
        svfK = Float(k)
        // Loudness compensation tracks the tuned center, not the drift-modulated
        // one, so drift reads as a spectral move rather than a volume wobble.
        makeupGain = Float(ambientBedENBWMakeupGain(centerHz: pow(2, smoothedTunerLog2), q: q))

        warmthCoefficient = Float(exp(-2 * Double.pi * ambientBedWarmthCutoffHz(smoothedWarmth) / AmbientBedDSP.sampleRate))
        warmthMakeup = Float(1 + AmbientBedDSP.warmthMaxMakeup * smoothedWarmth)

        crackleSpawnThreshold = ambientBedCrackleDensityPerSecond(smoothedCrackle) / AmbientBedDSP.sampleRate
        crackleGain = Float(smoothedCrackle * AmbientBedDSP.crackleBusGain)

        washFeedback = Float(AmbientBedDSP.washFeedbackBase + AmbientBedDSP.washFeedbackSpan * smoothedWash)
        let mixAngle = AmbientBedDSP.washMixArc * smoothedWash * Double.pi / 2
        washDryGain = Float(cos(mixAngle))
        washWetGain = Float(sin(mixAngle)) * AmbientBedDSP.washWetScale

        outputGain = Float(smoothedLevel * smoothedLevel * AmbientBedDSP.masterCalibration)

        sanitizeStates()
    }

    private func renderSlice(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frameCount: Int) {
        for frame in 0..<frameCount {
            var sampleLeft = bandLeft.band(noiseLeft.nextFloat(), a1: svfA1, a2: svfA2, a3: svfA3, k: svfK) * makeupGain
            var sampleRight = bandRight.band(noiseRight.nextFloat(), a1: svfA1, a2: svfA2, a3: svfA3, k: svfK) * makeupGain

            if crackleRandom.nextUnitDouble() < crackleSpawnThreshold {
                let amplitudeDraw = crackleRandom.nextUnitDouble()
                let signDraw = crackleRandom.nextUnitDouble()
                let decayDraw = crackleRandom.nextUnitDouble()
                let panDraw = crackleRandom.nextUnitDouble()
                var voice = AmbientCrackleVoice()
                voice.amplitude = Float(0.08 + 0.6 * amplitudeDraw * amplitudeDraw) * (signDraw < 0.5 ? -1 : 1)
                voice.decay = Float(0.985 + 0.0115 * decayDraw)
                let panLeft = Float(0.5 + 0.3 * (2 * panDraw - 1))
                voice.gainLeft = panLeft
                voice.gainRight = 1 - panLeft
                crackleVoices[crackleNextVoice] = voice
                crackleNextVoice += 1
                if crackleNextVoice == crackleVoices.count { crackleNextVoice = 0 }
            }
            var tickLeft: Float = 0
            var tickRight: Float = 0
            for index in 0..<crackleVoices.count {
                crackleVoices[index].amplitude *= crackleVoices[index].decay
                tickLeft += crackleVoices[index].amplitude * crackleVoices[index].gainLeft
                tickRight += crackleVoices[index].amplitude * crackleVoices[index].gainRight
            }
            // Ticks join after the band-pass (they must not ring a Q≈29
            // resonator) and before warmth (vinyl through a dark radio).
            sampleLeft += crackleHighLeft.process(tickLeft, coefficient: crackleHighCoefficient) * crackleGain
            sampleRight += crackleHighRight.process(tickRight, coefficient: crackleHighCoefficient) * crackleGain

            sampleLeft = warmthLeft.process(sampleLeft, coefficient: warmthCoefficient) * warmthMakeup
            sampleRight = warmthRight.process(sampleRight, coefficient: warmthCoefficient) * warmthMakeup
            sampleLeft = rumbleLeft.process(sampleLeft, coefficient: rumbleCoefficient)
            sampleRight = rumbleRight.process(sampleRight, coefficient: rumbleCoefficient)

            let crossFeed = AmbientBedDSP.washCrossFeed
            let feedLeft = sampleLeft + crossFeed * (sampleRight - sampleLeft)
            let feedRight = sampleRight + crossFeed * (sampleLeft - sampleRight)
            let wetLeft = washLeft.process(feedLeft, feedback: washFeedback)
            let wetRight = washRight.process(feedRight, feedback: washFeedback)
            sampleLeft = sampleLeft * washDryGain + wetLeft * washWetGain
            sampleRight = sampleRight * washDryGain + wetRight * washWetGain

            left[frame] = ambientBedSoftClip(sampleLeft * outputGain)
            right[frame] = ambientBedSoftClip(sampleRight * outputGain)
        }
    }

    /// Per-block scrub of every recursive scalar state: non-finite → 0 (a live
    /// engine can never latch NaN forever) and sub-1e-15 → 0 (denormal drag).
    /// Delay-line contents recirculate through these states, so the buffers
    /// themselves are deliberately not scanned.
    private func sanitizeStates() {
        bandLeft.ic1 = ambientBedFlushed(bandLeft.ic1)
        bandLeft.ic2 = ambientBedFlushed(bandLeft.ic2)
        bandRight.ic1 = ambientBedFlushed(bandRight.ic1)
        bandRight.ic2 = ambientBedFlushed(bandRight.ic2)
        warmthLeft.y = ambientBedFlushed(warmthLeft.y)
        warmthRight.y = ambientBedFlushed(warmthRight.y)
        rumbleLeft.y = ambientBedFlushed(rumbleLeft.y)
        rumbleLeft.x1 = ambientBedFlushed(rumbleLeft.x1)
        rumbleRight.y = ambientBedFlushed(rumbleRight.y)
        rumbleRight.x1 = ambientBedFlushed(rumbleRight.x1)
        crackleHighLeft.y = ambientBedFlushed(crackleHighLeft.y)
        crackleHighLeft.x1 = ambientBedFlushed(crackleHighLeft.x1)
        crackleHighRight.y = ambientBedFlushed(crackleHighRight.y)
        crackleHighRight.x1 = ambientBedFlushed(crackleHighRight.x1)
        washLeft.comb1.filterStore = ambientBedFlushed(washLeft.comb1.filterStore)
        washLeft.comb2.filterStore = ambientBedFlushed(washLeft.comb2.filterStore)
        washLeft.comb3.filterStore = ambientBedFlushed(washLeft.comb3.filterStore)
        washRight.comb1.filterStore = ambientBedFlushed(washRight.comb1.filterStore)
        washRight.comb2.filterStore = ambientBedFlushed(washRight.comb2.filterStore)
        washRight.comb3.filterStore = ambientBedFlushed(washRight.comb3.filterStore)
        for index in 0..<crackleVoices.count {
            crackleVoices[index].amplitude = ambientBedFlushed(crackleVoices[index].amplitude)
        }
    }
}

private func ambientBedUnitClamp(_ value: Double) -> Double {
    min(max(value.isFinite ? value : 0, 0), 1)
}

private func ambientBedFlushed(_ value: Float) -> Float {
    guard value.isFinite else { return 0 }
    return abs(value) < 1e-15 ? 0 : value
}
