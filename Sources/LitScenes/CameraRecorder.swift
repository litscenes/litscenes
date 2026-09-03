@preconcurrency import AVFoundation
import AppKit
import Foundation
import SwiftUI

enum CameraRecordingPhase: String, Equatable {
    case idle
    case preparing
    case ready
    case needsCameraPermission
    case recording
    case finalizing
    case failed
}

struct CameraDeviceOption: Identifiable, Hashable {
    var id: String
    var name: String
}

struct CameraRecordingSettings: Hashable {
    var videoDeviceId: String
    var audioDeviceId: String
    var includeMicrophone: Bool
    var captureFrames: Bool
    var framesPerSecond: Int
    var frameCapSeconds: Double
}

struct CameraRecordingResult {
    var url: URL
    var durationSeconds: Double
    var byteCount: Int64
    var settings: CameraRecordingSettings
}

@MainActor
final class CameraRecorder: NSObject, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()

    private let movieOutput = AVCaptureMovieFileOutput()
    private var activeVideoInput: AVCaptureDeviceInput?
    private var activeAudioInput: AVCaptureDeviceInput?
    private var finishContinuation: CheckedContinuation<CameraRecordingResult, Error>?
    private var outputURL: URL?
    private var startedAt: Date?
    private var settings: CameraRecordingSettings?
    private var shouldDeleteFinishedOutput = false

    static func videoDevices() -> [CameraDeviceOption] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        return discovery.devices.map { CameraDeviceOption(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func audioDevices() -> [CameraDeviceOption] {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return discovery.devices.map { CameraDeviceOption(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    static func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    func prepare(settings: CameraRecordingSettings) throws {
        guard let videoDevice = selectedVideoDevice(id: settings.videoDeviceId) else {
            throw ScreenGraphError.capture("No camera was found.")
        }

        var audioDevice: AVCaptureDevice?
        if settings.includeMicrophone {
            audioDevice = selectedAudioDevice(id: settings.audioDeviceId)
            if audioDevice == nil {
                throw ScreenGraphError.capture("No microphone was found.")
            }
        }

        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        if let activeVideoInput {
            session.removeInput(activeVideoInput)
            self.activeVideoInput = nil
        }
        if let activeAudioInput {
            session.removeInput(activeAudioInput)
            self.activeAudioInput = nil
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        guard session.canAddInput(videoInput) else {
            session.commitConfiguration()
            throw ScreenGraphError.capture("The selected camera cannot be added to the recording session.")
        }
        session.addInput(videoInput)
        activeVideoInput = videoInput

        if let audioDevice {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
                activeAudioInput = audioInput
            }
        }

        if !session.outputs.contains(movieOutput) {
            guard session.canAddOutput(movieOutput) else {
                session.commitConfiguration()
                throw ScreenGraphError.capture("The camera recorder cannot write movie output.")
            }
            session.addOutput(movieOutput)
        }

        session.commitConfiguration()
        self.settings = settings

        if !session.isRunning {
            session.startRunning()
        }
    }

    func stopPreview() {
        guard !movieOutput.isRecording else { return }
        if session.isRunning {
            session.stopRunning()
        }
    }

    func startRecording(outputURL: URL, settings: CameraRecordingSettings) throws {
        guard !movieOutput.isRecording else {
            throw ScreenGraphError.capture("A camera recording is already active.")
        }
        self.outputURL = outputURL
        self.startedAt = Date()
        self.settings = settings
        self.shouldDeleteFinishedOutput = false
        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
    }

    func stopRecording() async throws -> CameraRecordingResult {
        guard movieOutput.isRecording else {
            throw ScreenGraphError.capture("No camera recording is active.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            movieOutput.stopRecording()
        }
    }

    func cancelRecording() {
        if movieOutput.isRecording {
            shouldDeleteFinishedOutput = true
            movieOutput.stopRecording()
        }
        finishContinuation?.resume(throwing: ScreenAreaSelectionError.cancelled)
        finishContinuation = nil
        startedAt = nil
        settings = nil
        stopPreview()
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            if shouldDeleteFinishedOutput {
                try? FileManager.default.removeItem(at: outputFileURL)
                shouldDeleteFinishedOutput = false
                finishContinuation = nil
                outputURL = nil
                startedAt = nil
                settings = nil
                stopPreview()
                return
            }

            if let error {
                finishContinuation?.resume(throwing: error)
                finishContinuation = nil
                outputURL = nil
                startedAt = nil
                settings = nil
                return
            }

            guard let settings else {
                finishContinuation?.resume(throwing: ScreenGraphError.capture("Camera recording finished without settings."))
                finishContinuation = nil
                return
            }

            let values = try? outputFileURL.resourceValues(forKeys: [.fileSizeKey])
            let byteCount = Int64(values?.fileSize ?? 0)
            let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
            finishContinuation?.resume(returning: CameraRecordingResult(
                url: outputFileURL,
                durationSeconds: max(duration, 0),
                byteCount: byteCount,
                settings: settings
            ))
            finishContinuation = nil
            outputURL = nil
            startedAt = nil
            self.settings = nil
        }
    }

    private func selectedVideoDevice(id: String) -> AVCaptureDevice? {
        let devices = Self.videoDevices().map(\.id)
        let requestedId = devices.contains(id) ? id : devices.first
        guard let requestedId else { return nil }
        return AVCaptureDevice(uniqueID: requestedId)
    }

    private func selectedAudioDevice(id: String) -> AVCaptureDevice? {
        let devices = Self.audioDevices().map(\.id)
        let requestedId = devices.contains(id) ? id : devices.first
        guard let requestedId else { return nil }
        return AVCaptureDevice(uniqueID: requestedId)
    }
}

@MainActor
final class CameraRecorderWindowController: NSObject, NSWindowDelegate {
    private weak var library: LibraryEngine?
    private var window: NSWindow?

    init(library: LibraryEngine) {
        self.library = library
    }

    func show() {
        guard let library else { return }
        if window == nil {
            let rootView = CameraRecorderWindowView(
                library: library,
                onClose: { [weak self] in
                    self?.closeRequested()
                }
            )
            let hostingView = NSHostingView(rootView: rootView)
            let recorderWindow = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 640, height: 650),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            recorderWindow.title = "Camera Recorder"
            recorderWindow.contentView = hostingView
            recorderWindow.delegate = self
            recorderWindow.isReleasedWhenClosed = false
            recorderWindow.setFrameAutosaveName("LitScenesCameraRecorder")
            window = recorderWindow
        }

        library.beginCameraRecorder()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard library?.cameraRecordingPhase == .recording else {
            library?.closeCameraRecorder()
            return true
        }
        library?.noteCameraRecorderWindowCloseBlocked()
        return false
    }

    private func closeRequested() {
        guard let window else { return }
        if windowShouldClose(window) {
            window.close()
        }
    }
}

private struct CameraRecorderWindowView: View {
    @ObservedObject var library: LibraryEngine
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            preview
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            controls
        }
        .background(CanonColor.sidebar)
        .frame(minWidth: 560, minHeight: 600)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Camera Recorder")
                    .font(CanonType.editorial(27, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text(statusText)
                    .font(CanonType.interface(12, weight: .medium))
                    .foregroundStyle(statusTint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            elapsed
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Close")
        }
        .padding(16)
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            CanonColor.room
            if let session = library.cameraPreviewSession {
                CameraPreviewView(session: session)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: previewIcon)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(statusTint)
                    Text(previewMessage)
                        .font(CanonType.interface(13, weight: .medium))
                        .foregroundStyle(CanonColor.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .padding(16)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            deviceControls
            captureControls
            actionControls
        }
        .padding(16)
    }

    private var deviceControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Camera", selection: Binding(
                get: { library.cameraSelectedVideoDeviceId },
                set: { library.selectCameraVideoDevice($0) }
            )) {
                if library.cameraVideoDevices.isEmpty {
                    Text("No camera").tag("")
                } else {
                    ForEach(library.cameraVideoDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
            }
            .disabled(library.cameraRecordingPhase == .recording || library.cameraRecordingPhase == .finalizing)

            Toggle(isOn: Binding(
                get: { library.cameraIncludeMicrophone },
                set: { library.setCameraIncludeMicrophone($0) }
            )) {
                Label("Microphone", systemImage: "mic")
            }
            .disabled(library.cameraRecordingPhase == .recording || library.cameraRecordingPhase == .finalizing)

            if library.cameraIncludeMicrophone {
                Picker("Input", selection: Binding(
                    get: { library.cameraSelectedAudioDeviceId },
                    set: { library.selectCameraAudioDevice($0) }
                )) {
                    if library.cameraAudioDevices.isEmpty {
                        Text("No microphone").tag("")
                    } else {
                        ForEach(library.cameraAudioDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                }
                .disabled(library.cameraRecordingPhase == .recording || library.cameraRecordingPhase == .finalizing)
            }
        }
        .font(CanonType.interface(12, weight: .medium))
    }

    private var captureControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(
                get: { library.cameraCaptureFrames },
                set: { library.setCameraCaptureFrames($0) }
            )) {
                Label("Save still frames", systemImage: "photo.stack")
            }
            .disabled(library.cameraRecordingPhase == .recording || library.cameraRecordingPhase == .finalizing)

            if library.cameraCaptureFrames {
                HStack(spacing: 12) {
                    Stepper(
                        "Capture \(library.cameraFrameRate) frames every second",
                        value: Binding(
                            get: { library.cameraFrameRate },
                            set: { library.setCameraFrameRate($0) }
                        ),
                        in: 1...10
                    )
                    Stepper(
                        "First \(Int(library.cameraFrameCapSeconds))s",
                        value: Binding(
                            get: { Int(library.cameraFrameCapSeconds) },
                            set: { library.setCameraFrameCapSeconds(Double($0)) }
                        ),
                        in: 1...30
                    )
                }
                .font(CanonType.archive(11, weight: .medium))
                .foregroundStyle(CanonColor.muted)

                Text("Adds up to \(library.cameraFrameBudget) disabled stills to Media.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
            }
        }
        .font(CanonType.interface(12, weight: .medium))
        .foregroundStyle(CanonColor.bone)
    }

    private var actionControls: some View {
        HStack(spacing: 10) {
            switch library.cameraRecordingPhase {
            case .recording:
                Button {
                    library.stopCameraRecording()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(minWidth: 112)
                }
                .buttonStyle(CanonPrimaryButtonStyle())

                Button {
                    library.cancelCameraRecording()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(CanonUtilityButtonStyle())
            case .preparing, .finalizing:
                ProgressView()
                    .controlSize(.small)
                Text(library.cameraRecordingStatus)
                    .font(CanonType.interface(12, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
            default:
                Button {
                    library.startCameraRecording()
                } label: {
                    Label("Record", systemImage: "record.circle")
                        .frame(minWidth: 112)
                }
                .buttonStyle(CanonPrimaryButtonStyle())
                .disabled(!library.canStartCameraRecording)

                Button {
                    library.prepareCameraRecorder()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(CanonUtilityButtonStyle())
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var elapsed: some View {
        if library.cameraRecordingPhase == .recording {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsedText(now: context.date))
                    .font(CanonType.archive(18, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
                    .monospacedDigit()
                    .padding(.top, 2)
            }
        }
    }

    private var statusText: String {
        library.cameraRecordingStatus.isEmpty ? "Camera idle" : library.cameraRecordingStatus
    }

    private var previewIcon: String {
        switch library.cameraRecordingPhase {
        case .needsCameraPermission:
            return "lock.shield.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        default:
            return "video"
        }
    }

    private var previewMessage: String {
        switch library.cameraRecordingPhase {
        case .needsCameraPermission:
            return "Camera permission is required."
        case .failed:
            return library.cameraRecordingStatus
        default:
            return "Preparing camera preview."
        }
    }

    private var statusTint: Color {
        switch library.cameraRecordingPhase {
        case .failed:
            return CanonColor.rust
        case .needsCameraPermission, .recording, .preparing, .finalizing:
            return CanonColor.brass
        case .ready, .idle:
            return CanonColor.olive
        }
    }

    private func elapsedText(now: Date) -> String {
        guard let startedAt = library.cameraRecordingStartedAt else { return "00:00" }
        return cameraElapsedLabel(max(0, now.timeIntervalSince(startedAt)))
    }

    private func cameraElapsedLabel(_ value: Double) -> String {
        let seconds = Int(value.rounded())
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.previewLayer.session = session
    }
}

final class CameraPreviewNSView: NSView {
    override func makeBackingLayer() -> CALayer {
        let layer = AVCaptureVideoPreviewLayer()
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        if let previewLayer = layer as? AVCaptureVideoPreviewLayer {
            return previewLayer
        }
        let previewLayer = AVCaptureVideoPreviewLayer()
        previewLayer.videoGravity = .resizeAspectFill
        layer = previewLayer
        return previewLayer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
