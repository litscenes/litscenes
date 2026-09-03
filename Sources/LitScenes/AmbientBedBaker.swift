import AVFoundation
import Foundation

struct AmbientBedBakeProgress: Sendable {
    enum Phase: Sendable {
        case renderingTail
        case renderingBody
        case encoding
        case verifying
    }

    var phase: Phase
    var fraction: Double
}

struct AmbientBedBakeResult: Sendable {
    var fileURL: URL
    var format: AmbientBedBakeFormat
    var specHash: String
    /// PCM truth (`loopFrameCount / sampleRate`). Composition loop math must
    /// use this, never container metadata — AAC containers round.
    var durationSeconds: Double
    var loopFrameCount: Int
    var sampleRate: Double
}

/// Numeric seam verdict for a baked loop, comparing the decoded file against
/// the rendered source PCM. Pure so the thresholds are unit-testable.
struct AmbientBedSeamReport: Sendable {
    var decodedFrameCount: Int
    var expectedFrameCount: Int
    var lengthWithinTolerance: Bool
    var edgeLevelBalanced: Bool
    var edgeLevelMatchesSource: Bool
    var junctionClickFree: Bool

    var passes: Bool {
        lengthWithinTolerance && edgeLevelBalanced && edgeLevelMatchesSource && junctionClickFree
    }
}

/// Renders `spec` into a seamlessly loopable bed file.
///
/// The loop seam is inaudible by construction: the render runs `F` frames past
/// the loop end, and that tail — the exact filtered/reverberated successor of
/// the final sample through every piece of synth state — is equal-power
/// crossfaded into the head. Drift's integer-cycle snapping means head and
/// tail share a band center during the fade, so nothing beats.
enum AmbientBedBaker {
    static let chunkFrames = 32_768
    static let crossfadeMaxFrames = 48_000
    /// Level windows are ~1/3 s: crackle ticks are sparse, so short windows
    /// make edge-RMS comparisons a lottery over tick placement.
    static let seamWindowFrames = 16_384
    static let seamClickWindowFrames = 128
    static let seamLengthToleranceFrames = 2_048
    static let seamEdgeToleranceDecibels: Double = 2
    static let seamClickRatioLimit: Double = 6

    static func loopFrameCount(spec: AmbientBedSpec) -> Int {
        Int((spec.normalized().durationSeconds * AmbientBedDSP.sampleRate).rounded())
    }

    static func crossfadeFrames(loopFrameCount: Int) -> Int {
        max(1, min(crossfadeMaxFrames, loopFrameCount / 4))
    }

    /// Single implementation of render + seam crossfade shared by the file
    /// pipeline and tests: streams the final looped PCM in chunks. The emitted
    /// slices alias reused buffers — valid only during the call.
    static func renderLoop(
        spec: AmbientBedSpec,
        emitChunk: (_ left: ArraySlice<Float>, _ right: ArraySlice<Float>) throws -> Void
    ) throws {
        try renderLoop(spec: spec, onProgress: nil, emitChunk: emitChunk)
    }

    /// Bakes the spec to `<scratch>/bed.m4a` (or `bed.caf` when seam
    /// verification rejects the AAC encode). The caller owns atomic promotion
    /// of the returned file and deletes its parent directory afterwards; every
    /// failure path cleans the scratch directory here.
    static func bake(
        spec: AmbientBedSpec,
        progress: (@MainActor (AmbientBedBakeProgress) -> Void)? = nil
    ) async throws -> AmbientBedBakeResult {
        let normalized = spec.normalized()
        let frameCount = loopFrameCount(spec: normalized)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("ambient_bake_\(UUID().uuidString)", isDirectory: true)
        try ensureDirectory(scratch)
        var succeeded = false
        defer {
            if !succeeded { try? FileManager.default.removeItem(at: scratch) }
        }

        func report(_ phase: AmbientBedBakeProgress.Phase, _ fraction: Double) {
            guard let progress else { return }
            let state = AmbientBedBakeProgress(phase: phase, fraction: fraction)
            Task { @MainActor in progress(state) }
        }

        // Render the loop into Float32 PCM, capturing the seam-verification
        // windows on the way through.
        let cafURL = scratch.appendingPathComponent("loop.caf")
        var capture = AmbientSeamCapture(loopFrameCount: frameCount)
        try writePCM(to: cafURL, spec: normalized, bitDepth: .float32) { left, right, position in
            capture.absorb(left: left, position: position)
        } onProgress: { phase, fraction in
            report(phase, fraction)
        }

        report(.encoding, 0.9)
        let m4aURL = scratch.appendingPathComponent("bed.m4a")
        try await exportM4A(from: cafURL, to: m4aURL)

        report(.verifying, 0.98)
        let verified: Bool
        if let decoded = try? decodeForVerification(url: m4aURL, expectedFrameCount: frameCount) {
            let seam = ambientBedSeamReport(
                sourceHead: capture.head,
                sourceTail: capture.tail,
                decodedHead: decoded.head,
                decodedMid: decoded.mid,
                decodedTail: decoded.tail,
                decodedFrameCount: decoded.frameCount,
                loopFrameCount: frameCount
            )
            verified = seam.passes
        } else {
            verified = false
        }

        let result: AmbientBedBakeResult
        if verified {
            try? FileManager.default.removeItem(at: cafURL)
            result = AmbientBedBakeResult(
                fileURL: m4aURL,
                format: .m4a,
                specHash: ambientBedId(spec: normalized),
                durationSeconds: Double(frameCount) / AmbientBedDSP.sampleRate,
                loopFrameCount: frameCount,
                sampleRate: AmbientBedDSP.sampleRate
            )
        } else {
            // PCM fallback: mathematically perfect seams, deterministic bytes
            // (TPDF dither stream derived from the spec seed), ~11.5 MB/min.
            let fallbackURL = scratch.appendingPathComponent("bed.caf")
            try writePCM(to: fallbackURL, spec: normalized, bitDepth: .int16Dithered) { _, _, _ in } onProgress: { _, _ in }
            try? FileManager.default.removeItem(at: m4aURL)
            try? FileManager.default.removeItem(at: cafURL)
            result = AmbientBedBakeResult(
                fileURL: fallbackURL,
                format: .caf,
                specHash: ambientBedId(spec: normalized),
                durationSeconds: Double(frameCount) / AmbientBedDSP.sampleRate,
                loopFrameCount: frameCount,
                sampleRate: AmbientBedDSP.sampleRate
            )
        }
        report(.verifying, 1)
        succeeded = true
        return result
    }

    // MARK: - Loop rendering

    private static func renderLoop(
        spec: AmbientBedSpec,
        onProgress: ((AmbientBedBakeProgress.Phase, Double) -> Void)?,
        emitChunk: (_ left: ArraySlice<Float>, _ right: ArraySlice<Float>) throws -> Void
    ) throws {
        let normalized = spec.normalized()
        let frameCount = loopFrameCount(spec: normalized)
        let crossfade = crossfadeFrames(loopFrameCount: frameCount)

        // Pass 1: run the synth through the loop plus the crossfade tail,
        // keeping only the tail (and, in DEBUG, the head — to assert the
        // determinism this two-pass scheme rests on).
        var tailLeft = [Float](repeating: 0, count: crossfade)
        var tailRight = [Float](repeating: 0, count: crossfade)
        #if DEBUG
        var debugHeadLeft = [Float](repeating: 0, count: crossfade)
        #endif
        let tailStart = frameCount
        let totalFrames = frameCount + crossfade
        let firstPass = AmbientBedSynth(spec: normalized)
        var position = 0
        while position < totalFrames {
            try Task.checkCancellation()
            let count = min(chunkFrames, totalFrames - position)
            let chunk = firstPass.renderChunk(frameCount: count)
            let chunkEnd = position + count
            if chunkEnd > tailStart {
                for frame in max(position, tailStart)..<chunkEnd {
                    tailLeft[frame - tailStart] = chunk.left[frame - position]
                    tailRight[frame - tailStart] = chunk.right[frame - position]
                }
            }
            #if DEBUG
            if position < crossfade {
                for frame in position..<min(crossfade, chunkEnd) {
                    debugHeadLeft[frame] = chunk.left[frame - position]
                }
            }
            #endif
            onProgress?(.renderingTail, 0.5 * Double(chunkEnd) / Double(totalFrames))
            position = chunkEnd
        }

        // Pass 2: fresh synth, same spec — bit-identical by construction —
        // blending the tail into the head, then streaming the body untouched.
        let secondPass = AmbientBedSynth(spec: normalized)
        position = 0
        while position < frameCount {
            try Task.checkCancellation()
            let count = min(chunkFrames, frameCount - position)
            var chunk = secondPass.renderChunk(frameCount: count)
            if position < crossfade {
                for frame in position..<min(crossfade, position + count) {
                    let local = frame - position
                    #if DEBUG
                    assert(
                        chunk.left[local].bitPattern == debugHeadLeft[frame].bitPattern,
                        "AmbientBedSynth render is not deterministic — the two-pass bake is unsound"
                    )
                    #endif
                    let t = (Double(frame) + 0.5) / Double(crossfade)
                    let headGain = Float(sin(t * Double.pi / 2))
                    let tailGain = Float(cos(t * Double.pi / 2))
                    chunk.left[local] = chunk.left[local] * headGain + tailLeft[frame] * tailGain
                    chunk.right[local] = chunk.right[local] * headGain + tailRight[frame] * tailGain
                }
            }
            try emitChunk(chunk.left[...], chunk.right[...])
            position += count
            onProgress?(.renderingBody, 0.5 + 0.4 * Double(position) / Double(frameCount))
        }
    }

    // MARK: - PCM file writing

    private enum AmbientBedBitDepth {
        case float32
        case int16Dithered
    }

    private static func writePCM(
        to url: URL,
        spec: AmbientBedSpec,
        bitDepth: AmbientBedBitDepth,
        onChunk: (_ left: ArraySlice<Float>, _ right: ArraySlice<Float>, _ position: Int) -> Void,
        onProgress: @escaping (AmbientBedBakeProgress.Phase, Double) -> Void
    ) throws {
        let sampleRate = AmbientBedDSP.sampleRate
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2
        ]
        let processingFormat: AVAudioFormat
        switch bitDepth {
        case .float32:
            settings[AVLinearPCMBitDepthKey] = 32
            settings[AVLinearPCMIsFloatKey] = true
            processingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false
            )!
        case .int16Dithered:
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            processingFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 2, interleaved: false
            )!
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: processingFormat.commonFormat,
            interleaved: false
        )
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat, frameCapacity: AVAudioFrameCount(chunkFrames)
        ) else {
            throw ScreenGraphError.capture("Could not allocate the ambient bake buffer.")
        }
        // Deterministic 1-LSB TPDF dither stream, derived from the spec seed so
        // fallback bytes are as reproducible as the PCM itself.
        var dither = AmbientBedSplitMix64(state: spec.normalized().seed &+ 0xA5A5_A5A5_A5A5_A5A5)

        try renderLoop(spec: spec, onProgress: onProgress) { left, right, currentPosition in
            let count = left.count
            buffer.frameLength = AVAudioFrameCount(count)
            switch bitDepth {
            case .float32:
                guard let channels = buffer.floatChannelData else {
                    throw ScreenGraphError.capture("The ambient bake buffer has no float channels.")
                }
                for frame in 0..<count {
                    channels[0][frame] = left[left.startIndex + frame]
                    channels[1][frame] = right[right.startIndex + frame]
                }
            case .int16Dithered:
                guard let channels = buffer.int16ChannelData else {
                    throw ScreenGraphError.capture("The ambient bake buffer has no int16 channels.")
                }
                for frame in 0..<count {
                    channels[0][frame] = ambientBedDitheredInt16(left[left.startIndex + frame], random: &dither)
                    channels[1][frame] = ambientBedDitheredInt16(right[right.startIndex + frame], random: &dither)
                }
            }
            try file.write(from: buffer)
            onChunk(left, right, currentPosition)
        }
    }

    // The render callback needs the absolute position for window capture, so
    // thread it through a small adapter.
    private static func renderLoop(
        spec: AmbientBedSpec,
        onProgress: @escaping (AmbientBedBakeProgress.Phase, Double) -> Void,
        emitChunk: (_ left: ArraySlice<Float>, _ right: ArraySlice<Float>, _ position: Int) throws -> Void
    ) throws {
        var position = 0
        try renderLoop(spec: spec, onProgress: onProgress) { left, right in
            try emitChunk(left, right, position)
            position += left.count
        }
    }

    // MARK: - Encoding + verification

    private static func exportM4A(from sourceURL: URL, to outputURL: URL) async throws {
        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration)
        guard let track = tracks.first, duration.seconds > 0 else {
            throw ScreenGraphError.capture("The rendered ambient loop has no readable audio track.")
        }
        let composition = AVMutableComposition()
        guard let outputTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ScreenGraphError.capture("Could not create the ambient bed composition.")
        }
        try outputTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw ScreenGraphError.capture("Could not create the ambient bed exporter.")
        }
        try await MediaExportGuard.export(exporter, to: outputURL, as: .m4a, operation: "ambient bed bake")
    }

    private static func decodeForVerification(
        url: URL,
        expectedFrameCount: Int
    ) throws -> (head: [Float], mid: [Float], tail: [Float], frameCount: Int) {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.processingFormat.sampleRate,
            channels: file.processingFormat.channelCount,
            interleaved: false
        )!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkFrames)) else {
            throw ScreenGraphError.capture("Could not allocate the ambient verification buffer.")
        }
        let window = seamWindowFrames
        let midStart = max(0, expectedFrameCount / 2 - window / 2)
        var head: [Float] = []
        var mid: [Float] = []
        var tail: [Float] = []
        var position = 0
        while true {
            try file.read(into: buffer)
            let count = Int(buffer.frameLength)
            if count == 0 { break }
            guard let channel = buffer.floatChannelData?[0] else { break }
            if head.count < window {
                for frame in 0..<min(count, window - head.count) {
                    head.append(channel[frame])
                }
            }
            let chunkEnd = position + count
            if chunkEnd > midStart, position < midStart + window {
                for frame in max(position, midStart)..<min(chunkEnd, midStart + window) {
                    mid.append(channel[frame - position])
                }
            }
            if count >= window {
                tail = (0..<window).map { channel[count - window + $0] }
            } else {
                tail.append(contentsOf: (0..<count).map { channel[$0] })
                if tail.count > window { tail.removeFirst(tail.count - window) }
            }
            position = chunkEnd
        }
        return (head, mid, tail, position)
    }
}

/// Left-channel edge/mid windows of the source loop, gathered while streaming.
private struct AmbientSeamCapture {
    let loopFrameCount: Int
    var head: [Float] = []
    var mid: [Float] = []
    var tail: [Float] = []

    init(loopFrameCount: Int) {
        self.loopFrameCount = loopFrameCount
    }

    mutating func absorb(left: ArraySlice<Float>, position: Int) {
        let window = AmbientBedBaker.seamWindowFrames
        let count = left.count
        let base = left.startIndex
        if head.count < window {
            for frame in 0..<min(count, window - head.count) {
                head.append(left[base + frame])
            }
        }
        let midStart = max(0, loopFrameCount / 2 - window / 2)
        let chunkEnd = position + count
        if chunkEnd > midStart, position < midStart + window {
            for frame in max(position, midStart)..<min(chunkEnd, midStart + window) {
                mid.append(left[base + frame - position])
            }
        }
        let tailStart = max(0, loopFrameCount - window)
        if chunkEnd > tailStart {
            for frame in max(position, tailStart)..<chunkEnd {
                let value = left[base + frame - position]
                tail.append(value)
            }
            if tail.count > window { tail.removeFirst(tail.count - window) }
        }
    }
}

/// Pure seam verdict. `decodedTail ++ decodedHead` simulates the loop junction
/// exactly as a composition will play it.
func ambientBedSeamReport(
    sourceHead: [Float],
    sourceTail: [Float],
    decodedHead: [Float],
    decodedMid: [Float],
    decodedTail: [Float],
    decodedFrameCount: Int,
    loopFrameCount: Int
) -> AmbientBedSeamReport {
    let lengthOK = abs(decodedFrameCount - loopFrameCount) <= AmbientBedBaker.seamLengthToleranceFrames
        && !decodedHead.isEmpty && !decodedTail.isEmpty

    let tolerance = AmbientBedBaker.seamEdgeToleranceDecibels
    let headDecibels = ambientSeamDecibels(decodedHead)
    let tailDecibels = ambientSeamDecibels(decodedTail)
    let balanced = abs(headDecibels - tailDecibels) <= tolerance
    let matchesSource = abs(headDecibels - ambientSeamDecibels(sourceHead)) <= tolerance
        && abs(tailDecibels - ambientSeamDecibels(sourceTail)) <= tolerance

    // Click check on a short window straddling the junction: its largest
    // sample-to-sample step must stay comparable to mid-file activity.
    let half = AmbientBedBaker.seamClickWindowFrames / 2
    let junction = Array(decodedTail.suffix(half)) + Array(decodedHead.prefix(half))
    let junctionStep = ambientSeamLargestStep(junction)
    let midStep = ambientSeamMedianStep(decodedMid)
    let clickFree = junctionStep <= AmbientBedBaker.seamClickRatioLimit * max(midStep, 1e-6)

    return AmbientBedSeamReport(
        decodedFrameCount: decodedFrameCount,
        expectedFrameCount: loopFrameCount,
        lengthWithinTolerance: lengthOK,
        edgeLevelBalanced: balanced,
        edgeLevelMatchesSource: matchesSource,
        junctionClickFree: clickFree
    )
}

private func ambientSeamDecibels(_ samples: [Float]) -> Double {
    guard !samples.isEmpty else { return -120 }
    let sum = samples.reduce(into: 0.0) { $0 += Double($1) * Double($1) }
    let rms = (sum / Double(samples.count)).squareRoot()
    return 20 * log10(max(rms, 1e-9))
}

private func ambientSeamLargestStep(_ samples: [Float]) -> Double {
    guard samples.count > 1 else { return 0 }
    var largest = 0.0
    for index in 1..<samples.count {
        largest = max(largest, abs(Double(samples[index]) - Double(samples[index - 1])))
    }
    return largest
}

private func ambientSeamMedianStep(_ samples: [Float]) -> Double {
    guard samples.count > 1 else { return 0 }
    var steps: [Double] = []
    steps.reserveCapacity(samples.count - 1)
    for index in 1..<samples.count {
        steps.append(abs(Double(samples[index]) - Double(samples[index - 1])))
    }
    steps.sort()
    return steps[steps.count / 2]
}

private func ambientBedDitheredInt16(_ value: Float, random: inout AmbientBedSplitMix64) -> Int16 {
    let clamped = min(max(Double(value), -1), 1)
    let dither = random.nextUnitDouble() + random.nextUnitDouble() - 1
    let scaled = clamped * 32_767 + dither
    return Int16(clamping: Int(scaled.rounded()))
}
