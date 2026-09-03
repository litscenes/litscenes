import AVFoundation
import Foundation
import Synchronization

/// Live audition of an ambient-bed spec — the app's first AVAudioEngine.
///
/// The synth always runs at the fixed 48 kHz bake rate; AVAudioEngine converts
/// to the hardware rate downstream. What the operator auditions IS the bake,
/// minus only the AAC encode and the loop-seam crossfade.
@MainActor
final class AmbientPreviewEngine {
    /// Carries exactly what the realtime render block may touch across the
    /// thread boundary (the CarriedExportSession pattern). Invariant: after
    /// `start`, the synth is touched only inside the render block — the main
    /// actor communicates exclusively through `pending`.
    final class RenderBox: @unchecked Sendable {
        let synth: AmbientBedSynth
        let pending = Mutex<AmbientBedParameters?>(nil)

        init(synth: AmbientBedSynth) {
            self.synth = synth
        }
    }

    private var engine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var box: RenderBox?
    private var configurationObserver: NSObjectProtocol?

    private(set) var isRunning = false

    /// Nonisolated so a SwiftUI `@State` initializer (which runs outside the
    /// main actor) can own an instance; nothing actor-protected is touched.
    nonisolated init() {}

    /// Builds the engine graph and starts rendering. Throws when the engine
    /// cannot start (typically: no output device).
    func start(spec: AmbientBedSpec) throws {
        stop()
        let box = RenderBox(synth: AmbientBedSynth(spec: spec))
        try startEngine(with: box)
        self.box = box
        isRunning = true
    }

    /// Pushes new knob values while running; a no-op when stopped. Seed and
    /// duration changes need a restart instead — they shape the noise voicing
    /// and the drift-cycle snapping, which live outside the live parameters.
    func update(_ parameters: AmbientBedParameters) {
        guard isRunning, let box else { return }
        box.pending.withLock { $0 = parameters }
    }

    /// Idempotent full teardown. The tuner sheet MUST call this on dismiss.
    func stop() {
        removeConfigurationObserver()
        tearDownEngine()
        box = nil
        isRunning = false
    }

    /// The realtime render body. MUST stay `nonisolated`: CoreAudio calls it on
    /// the HAL I/O thread, and a main-actor-isolated render block traps with
    /// "Incorrect actor executor assumption" on the first callback (SE-0423
    /// executor check) — an EXC_BREAKPOINT no `do/catch` can see. Kept out of the
    /// closure literal so the isolation is stated in the signature rather than
    /// inferred from whatever context builds the node, and so it is reachable
    /// from a test that calls it off the main actor.
    nonisolated static func renderAudio(
        box: RenderBox,
        frameCount: AVAudioFrameCount,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        guard buffers.count >= 2,
              let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else {
            return noErr
        }
        // Never block the render thread: a contended pickup is skipped and
        // the smoothers absorb the one-callback delay.
        let picked = box.pending.withLockIfAvailable { pending -> AmbientBedParameters? in
            let value = pending
            pending = nil
            return value
        }
        if let parameters = picked ?? nil {
            box.synth.setTargets(parameters)
        }
        box.synth.render(left: left, right: right, frameCount: Int(frameCount))
        return noErr
    }

    private func startEngine(with box: RenderBox) throws {
        // Build the engine BEFORE the format: `mainMixerNode` is created lazily on
        // first access and internally connects itself to the output node using the
        // hardware format, which hard-asserts when no output device is available
        // (0 Hz / 0 channels). Reading the output format first turns that
        // uncatchable assert into the throw this function already documents.
        let engine = AVAudioEngine()
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            throw ScreenGraphError.capture("No audio output device is available.")
        }
        // The synth's own 48 kHz — NOT the hardware rate. The mixer resamples;
        // matching the hardware here would detune the instrument by
        // 48000/hwRate and break preview==bake.
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: AmbientBedDSP.sampleRate, channels: 2
        ) else {
            throw ScreenGraphError.capture("Could not create the ambient preview format.")
        }
        // `@Sendable` is load-bearing: without it this closure inherits the
        // enclosing main-actor isolation and every callback traps. See renderAudio.
        let node = AVAudioSourceNode(format: format) { @Sendable _, _, frameCount, audioBufferList -> OSStatus in
            AmbientPreviewEngine.renderAudio(box: box, frameCount: frameCount, audioBufferList: audioBufferList)
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try engine.start()
        self.engine = engine
        self.sourceNode = node
        // Output-device changes (AirPods connecting is the everyday case):
        // rebuild the graph and reattach the SAME box, so the synth state —
        // the texture — survives the hop.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recoverFromConfigurationChange()
            }
        }
    }

    private func recoverFromConfigurationChange() {
        guard isRunning, let box else { return }
        removeConfigurationObserver()
        tearDownEngine()
        do {
            try startEngine(with: box)
        } catch {
            stop()
        }
    }

    private func tearDownEngine() {
        engine?.stop()
        if let engine, let sourceNode {
            engine.detach(sourceNode)
        }
        engine = nil
        sourceNode = nil
    }

    private func removeConfigurationObserver() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
    }
}
