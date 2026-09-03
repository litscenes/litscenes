import AVFoundation
import Foundation
import Testing
@testable import LitScenes

private func ambientBakeTestLoop(spec: AmbientBedSpec) throws -> (left: [Float], right: [Float]) {
    var left: [Float] = []
    var right: [Float] = []
    try AmbientBedBaker.renderLoop(spec: spec) { chunkLeft, chunkRight in
        left.append(contentsOf: chunkLeft)
        right.append(contentsOf: chunkRight)
    }
    return (left, right)
}

private func ambientBakeTestRMSDecibels(_ samples: ArraySlice<Float>) -> Double {
    guard !samples.isEmpty else { return -120 }
    let sum = samples.reduce(into: 0.0) { $0 += Double($1) * Double($1) }
    return 20 * log10(max((sum / Double(samples.count)).squareRoot(), 1e-9))
}

private func ambientBakeTestLargestStep(_ samples: [Float]) -> Double {
    guard samples.count > 1 else { return 0 }
    var largest = 0.0
    for index in 1..<samples.count {
        largest = max(largest, abs(Double(samples[index]) - Double(samples[index - 1])))
    }
    return largest
}

@Test func ambientBedRenderLoopIsDeterministicAndExactLength() throws {
    let spec = AmbientBedSpec(seed: 13, durationSeconds: 6)
    let first = try ambientBakeTestLoop(spec: spec)
    let second = try ambientBakeTestLoop(spec: spec)
    #expect(first.left.map(\.bitPattern) == second.left.map(\.bitPattern))
    #expect(first.right.map(\.bitPattern) == second.right.map(\.bitPattern))
    #expect(first.left.count == AmbientBedBaker.loopFrameCount(spec: spec))
    #expect(first.left.count == 6 * 48_000)
}

@Test func ambientBedLoopSeamIsContinuous() throws {
    // Deliberately seam-hostile: full drift (band center moving), audible
    // crackle (decaying ticks may straddle the seam), heavy wash (reverb tail
    // must carry across).
    let spec = AmbientBedSpec(
        tunerHz: 640, drift: 1, crackle: 0.6, wash: 0.7, seed: 17, durationSeconds: 6
    )
    let loop = try ambientBakeTestLoop(spec: spec)
    // Half a second: long enough to average the sparse crackle ticks out of
    // the RMS estimate.
    let window = 24_000

    // Level continuity across the junction of [loop ++ loop].
    let endDecibels = ambientBakeTestRMSDecibels(loop.left.suffix(window))
    let startDecibels = ambientBakeTestRMSDecibels(loop.left.prefix(window))
    #expect(abs(endDecibels - startDecibels) < 1.5)

    // No hard step at the junction: the largest sample-to-sample move in a
    // short straddling window stays comparable to mid-loop movement.
    let straddle = Array(loop.left.suffix(128)) + Array(loop.left.prefix(128))
    let mid = Array(loop.left[loop.left.count / 2..<(loop.left.count / 2 + 256)])
    let junctionStep = ambientBakeTestLargestStep(straddle)
    let midStep = ambientBakeTestLargestStep(mid)
    #expect(junctionStep <= 3 * max(midStep, 1e-6))
}

@Test func ambientBedSeamReportCatchesInjectedClick() {
    let window = AmbientBedBaker.seamWindowFrames
    // An integer number of cycles across the window, so tail→head wraps with
    // genuine loop continuity (an arbitrary-phase sine would step at the seam).
    let omega = 2 * Float.pi * 131 / Float(window)
    var smooth = [Float](repeating: 0, count: window)
    for index in 0..<window {
        smooth[index] = sin(Float(index) * omega) * 0.1
    }
    let clean = ambientBedSeamReport(
        sourceHead: smooth,
        sourceTail: smooth,
        decodedHead: smooth,
        decodedMid: smooth,
        decodedTail: smooth,
        decodedFrameCount: 288_000,
        loopFrameCount: 288_000
    )
    #expect(clean.passes)

    // A 0.5-amplitude step right at the junction must fail the click check.
    var stepped = smooth
    stepped[0] += 0.5
    let clicked = ambientBedSeamReport(
        sourceHead: smooth,
        sourceTail: smooth,
        decodedHead: stepped,
        decodedMid: smooth,
        decodedTail: smooth,
        decodedFrameCount: 288_000,
        loopFrameCount: 288_000
    )
    #expect(!clicked.junctionClickFree)
    #expect(!clicked.passes)

    // A truncated decode (AAC priming mis-trim territory) fails the length check.
    let short = ambientBedSeamReport(
        sourceHead: smooth,
        sourceTail: smooth,
        decodedHead: smooth,
        decodedMid: smooth,
        decodedTail: smooth,
        decodedFrameCount: 288_000 - 4_000,
        loopFrameCount: 288_000
    )
    #expect(!short.lengthWithinTolerance)
    #expect(!short.passes)

    // An encoder edge fade (quiet head) fails the level checks.
    let faded = smooth.map { $0 * 0.05 }
    let fade = ambientBedSeamReport(
        sourceHead: smooth,
        sourceTail: smooth,
        decodedHead: faded,
        decodedMid: smooth,
        decodedTail: smooth,
        decodedFrameCount: 288_000,
        loopFrameCount: 288_000
    )
    #expect(!fade.edgeLevelBalanced || !fade.edgeLevelMatchesSource)
    #expect(!fade.passes)
}

@Test func ambientBedBakeProducesDecodableLoopFile() async throws {
    let spec = AmbientBedSpec(seed: 23, durationSeconds: 6)
    let result = try await AmbientBedBaker.bake(spec: spec)
    defer { try? FileManager.default.removeItem(at: result.fileURL.deletingLastPathComponent()) }

    #expect(FileManager.default.fileExists(atPath: result.fileURL.path))
    #expect(result.specHash == ambientBedId(spec: spec))
    #expect(result.loopFrameCount == 6 * 48_000)
    #expect(result.durationSeconds == 6)
    #expect(result.sampleRate == 48_000)
    #expect(result.fileURL.pathExtension == result.format.fileExtension)

    let file = try AVAudioFile(forReading: result.fileURL)
    #expect(file.processingFormat.channelCount == 2)
    #expect(abs(Double(file.length) - Double(result.loopFrameCount)) <= Double(AmbientBedBaker.seamLengthToleranceFrames))
}

@Test func ambientBedBakeCancellationLeavesNoScratch() async throws {
    let scratchParent = FileManager.default.temporaryDirectory
    func ambientScratchNames() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: scratchParent.path)) ?? []
        return Set(names.filter { $0.hasPrefix("ambient_bake_") })
    }
    let before = ambientScratchNames()

    let task = Task {
        try await AmbientBedBaker.bake(spec: AmbientBedSpec(seed: 29, durationSeconds: 120))
    }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("Cancelled bake unexpectedly completed")
    } catch {
        #expect(error is CancellationError)
    }
    // Cleanup is asynchronous, and sibling tests bake into the same temp root
    // while the full suite runs in parallel — so poll: transient scratch dirs
    // (in-flight sibling bakes, slow defer-cleanup) vanish on their own, while
    // a genuine cancellation leak persists past the deadline.
    var leaked = ambientScratchNames().subtracting(before)
    let deadline = Date().addingTimeInterval(5)
    while !leaked.isEmpty, Date() < deadline {
        try await Task.sleep(nanoseconds: 100_000_000)
        leaked = ambientScratchNames().subtracting(before)
    }
    #expect(leaked.isEmpty)
}
