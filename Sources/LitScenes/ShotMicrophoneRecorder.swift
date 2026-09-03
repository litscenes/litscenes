@preconcurrency import AVFoundation
import Combine
import Foundation

enum ShotMicrophoneRecordingPhase: String, Equatable {
    case idle
    case preparing
    case ready
    case recording
    case finalizing
    case failed
}

struct ShotMicrophoneRecordingResult {
    var url: URL
    var durationSeconds: Double
    var inputDeviceId: String
    var inputDeviceName: String
}

enum CaptureAudioInputPreference {
    static let deviceIdKey = "litscenes.capture.preferred_audio_input_id"

    static var deviceId: String {
        get { LitScenesPreferences.store.string(forKey: deviceIdKey) ?? "" }
        set { LitScenesPreferences.store.set(newValue, forKey: deviceIdKey) }
    }

    static func resolvedDeviceId(in devices: [CameraDeviceOption]) -> String {
        if devices.contains(where: { $0.id == deviceId }) { return deviceId }
        return devices.first?.id ?? ""
    }
}

enum ShotVoiceoverPreference {
    static let playbackWhileRecordingKey = "litscenes.shot_voiceover.playback_while_recording"
}

@MainActor
final class ShotMicrophoneRecorder: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published private(set) var phase: ShotMicrophoneRecordingPhase = .idle
    @Published private(set) var status = ""
    @Published private(set) var level: Double = 0
    @Published private(set) var elapsedSeconds: Double = 0

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioFileOutput()
    private var activeInput: AVCaptureDeviceInput?
    private var selectedDevice: CameraDeviceOption?
    private var outputURL: URL?
    private var startedAt: Date?
    private var finishContinuation: CheckedContinuation<ShotMicrophoneRecordingResult, Error>?
    private var shouldDiscardFinishedOutput = false
    private var shouldShutdownAfterFinish = false
    private var levelTimer: Timer?

    static func devices() -> [CameraDeviceOption] {
        CameraRecorder.audioDevices()
    }

    static func requestAccess() async -> Bool {
        await CameraRecorder.requestMicrophoneAccess()
    }

    func prepare(deviceId: String) throws {
        guard phase != .recording, phase != .finalizing else {
            throw ScreenGraphError.capture("Stop the microphone recording before changing inputs.")
        }
        let devices = Self.devices()
        let resolvedId = devices.contains(where: { $0.id == deviceId })
            ? deviceId
            : CaptureAudioInputPreference.resolvedDeviceId(in: devices)
        guard let option = devices.first(where: { $0.id == resolvedId }),
              let device = selectedAudioDevice(id: resolvedId) else {
            phase = .failed
            status = "No microphone was found"
            throw ScreenGraphError.capture("No microphone was found.")
        }

        phase = .preparing
        status = "Preparing microphone"
        session.beginConfiguration()
        var didCommitConfiguration = false
        defer {
            if !didCommitConfiguration {
                session.commitConfiguration()
            }
        }
        if let activeInput {
            session.removeInput(activeInput)
            self.activeInput = nil
        }
        if session.outputs.contains(output) {
            session.removeOutput(output)
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                didCommitConfiguration = true
                phase = .failed
                status = "Microphone input is unavailable"
                throw ScreenGraphError.capture("The selected microphone cannot be added to the recording session.")
            }
            session.addInput(input)
            activeInput = input
            session.addOutput(output)
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ]
            session.commitConfiguration()
            didCommitConfiguration = true
        } catch {
            if session.isRunning { session.stopRunning() }
            phase = .failed
            status = error.localizedDescription
            throw error
        }

        selectedDevice = option
        CaptureAudioInputPreference.deviceId = option.id
        if !session.isRunning { session.startRunning() }
        startLevelMeter()
        phase = .ready
        status = option.name
    }

    func startRecording(outputURL: URL) throws {
        guard phase == .ready, !output.isRecording else {
            throw ScreenGraphError.capture("The microphone is not ready to record.")
        }
        guard AVCaptureAudioFileOutput.availableOutputFileTypes().contains(.m4a) else {
            throw ScreenGraphError.capture("This Mac cannot write an AAC microphone recording.")
        }
        self.outputURL = outputURL
        startedAt = Date()
        elapsedSeconds = 0
        shouldDiscardFinishedOutput = false
        shouldShutdownAfterFinish = false
        status = "Recording"
        phase = .recording
        output.startRecording(to: outputURL, outputFileType: .m4a, recordingDelegate: self)
    }

    func stopRecording(discard: Bool = false) async throws -> ShotMicrophoneRecordingResult {
        guard output.isRecording else {
            throw ScreenGraphError.capture("No microphone recording is active.")
        }
        shouldDiscardFinishedOutput = discard
        phase = .finalizing
        status = discard ? "Discarding take" : "Finishing take"
        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            output.stopRecording()
        }
    }

    func stopAndDiscardWithoutWaiting() {
        guard output.isRecording else {
            resetSession()
            return
        }
        shouldDiscardFinishedOutput = true
        output.stopRecording()
    }

    func shutdown() {
        if output.isRecording {
            shouldDiscardFinishedOutput = true
            shouldShutdownAfterFinish = true
            output.stopRecording()
        } else {
            resetSession()
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            finishRecording(outputFileURL: outputFileURL, error: error)
        }
    }

    private func finishRecording(outputFileURL: URL, error: Error?) {
        let continuation = finishContinuation
        finishContinuation = nil
        let discard = shouldDiscardFinishedOutput
        let shutdown = shouldShutdownAfterFinish
        let duration = max(Date().timeIntervalSince(startedAt ?? Date()), 0)
        let option = selectedDevice
        outputURL = nil
        startedAt = nil
        elapsedSeconds = 0
        shouldDiscardFinishedOutput = false
        shouldShutdownAfterFinish = false

        if discard {
            try? FileManager.default.removeItem(at: outputFileURL)
            phase = .ready
            status = option?.name ?? "Microphone ready"
            continuation?.resume(throwing: CancellationError())
            if shutdown { resetSession() }
            return
        }
        if let error {
            try? FileManager.default.removeItem(at: outputFileURL)
            phase = .failed
            status = error.localizedDescription
            continuation?.resume(throwing: error)
            if shutdown { resetSession() }
            return
        }
        phase = .ready
        status = option?.name ?? "Microphone ready"
        continuation?.resume(returning: ShotMicrophoneRecordingResult(
            url: outputFileURL,
            durationSeconds: duration,
            inputDeviceId: option?.id ?? "",
            inputDeviceName: option?.name ?? ""
        ))
        if shutdown { resetSession() }
    }

    private func selectedAudioDevice(id: String) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.first { $0.uniqueID == id } ?? discovery.devices.first
    }

    private func startLevelMeter() {
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollLevel() }
        }
    }

    private func pollLevel() {
        let decibels = output.connection(with: .audio)?.audioChannels
            .map(\.averagePowerLevel)
            .max() ?? -60
        level = min(max((Double(decibels) + 60) / 60, 0), 1)
        if let startedAt { elapsedSeconds = max(Date().timeIntervalSince(startedAt), 0) }
    }

    private func resetSession() {
        levelTimer?.invalidate()
        levelTimer = nil
        level = 0
        elapsedSeconds = 0
        if session.isRunning { session.stopRunning() }
        phase = .idle
        status = ""
    }
}
