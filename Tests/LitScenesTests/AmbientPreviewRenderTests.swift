import AVFoundation
import Foundation
import Testing
@testable import LitScenes

// First coverage of the LIVE preview path. The bake path was always tested;
// this one never was, which is how a feature that traps on its first audio
// callback shipped alongside a green suite.
//
// The defect: `AmbientPreviewEngine` is `@MainActor`, so a render closure
// written inline inside it inherited main-actor isolation, and CoreAudio
// calling it on the HAL I/O thread trapped with "Incorrect actor executor
// assumption" — an EXC_BREAKPOINT, uncatchable by the `do/catch` around
// `preview.start(spec:)`. These tests call the render body the way CoreAudio
// does: from a task that is not the main actor. If the render body ever
// regains actor isolation, they stop compiling.

/// Mirrors the buffer list AVAudioEngine hands a non-interleaved source node.
/// `@unchecked Sendable` is honest here rather than a shrug: the owned pointers
/// are written by exactly one task at a time — filled by the render task, read
/// back only after that task has been awaited.
private final class AmbientPreviewTestBufferList: @unchecked Sendable {
    let list: UnsafeMutableAudioBufferListPointer
    let frameCount: AVAudioFrameCount
    private let channels: [UnsafeMutablePointer<Float>]

    init(frameCount: AVAudioFrameCount, channelCount: Int = 2) {
        self.frameCount = frameCount
        let count = Int(frameCount)
        channels = (0..<channelCount).map { _ in
            let buffer = UnsafeMutablePointer<Float>.allocate(capacity: count)
            buffer.initialize(repeating: 0, count: count)
            return buffer
        }
        list = AudioBufferList.allocate(maximumBuffers: channelCount)
        let bytes = UInt32(count * MemoryLayout<Float>.size)
        for (index, buffer) in channels.enumerated() {
            list[index] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: bytes,
                mData: UnsafeMutableRawPointer(buffer)
            )
        }
    }

    deinit {
        channels.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }

    func samples(channel: Int) -> [Float] {
        Array(UnsafeBufferPointer(start: channels[channel], count: Int(frameCount)))
    }
}

/// Renders off the main actor, exactly as the audio thread does.
private func ambientPreviewRenderOffMainActor(
    box: AmbientPreviewEngine.RenderBox,
    buffers: AmbientPreviewTestBufferList
) async -> OSStatus {
    await Task.detached {
        AmbientPreviewEngine.renderAudio(
            box: box,
            frameCount: buffers.frameCount,
            audioBufferList: buffers.list.unsafeMutablePointer
        )
    }.value
}

@Test func ambientPreviewRenderBlockRunsOffTheMainActorAndProducesAudio() async {
    let box = AmbientPreviewEngine.RenderBox(synth: AmbientBedSynth(spec: AmbientBedSpec(seed: 13, durationSeconds: 6)))
    let buffers = AmbientPreviewTestBufferList(frameCount: 512)

    let status = await ambientPreviewRenderOffMainActor(box: box, buffers: buffers)

    #expect(status == noErr)
    // The tuner is a noise instrument: silence here means the render never ran.
    #expect(buffers.samples(channel: 0).contains { $0 != 0 })
    #expect(buffers.samples(channel: 1).contains { $0 != 0 })
    // Nothing may leave the audio range, and NaN/Inf would poison the mixer.
    #expect(buffers.samples(channel: 0).allSatisfy { $0.isFinite && abs($0) <= 1.0 })
    #expect(buffers.samples(channel: 1).allSatisfy { $0.isFinite && abs($0) <= 1.0 })
}

@Test func ambientPreviewRenderBlockAppliesPendingParametersFromTheAudioThread() async {
    let box = AmbientPreviewEngine.RenderBox(synth: AmbientBedSynth(spec: AmbientBedSpec(seed: 21, durationSeconds: 6)))
    let buffers = AmbientPreviewTestBufferList(frameCount: 512)

    // What `update(_:)` does from the main actor while audio is running.
    box.pending.withLock { $0 = AmbientBedSpec(warmth: 0.9, wash: 0.8, seed: 21, durationSeconds: 6).parameters }
    let status = await ambientPreviewRenderOffMainActor(box: box, buffers: buffers)

    #expect(status == noErr)
    #expect(buffers.samples(channel: 0).allSatisfy { $0.isFinite })
    // The pickup consumes the handoff so the next callback cannot re-apply it.
    #expect(box.pending.withLock { $0 } == nil)
}

@Test func ambientPreviewRenderBlockStaysQuietWhenTheBufferListIsNotStereo() async {
    // A mono/interleaved surprise must degrade quietly rather than scribble
    // past the end of a buffer it assumed was there.
    let box = AmbientPreviewEngine.RenderBox(synth: AmbientBedSynth(spec: AmbientBedSpec(seed: 5, durationSeconds: 6)))
    let buffers = AmbientPreviewTestBufferList(frameCount: 256, channelCount: 1)

    let status = await ambientPreviewRenderOffMainActor(box: box, buffers: buffers)

    #expect(status == noErr)
    #expect(buffers.samples(channel: 0).allSatisfy { $0 == 0 })
}
