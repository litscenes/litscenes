@preconcurrency import AVFoundation
import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit
import SwiftUI

// File > Record Session: the app-walkthrough recorder. By default it records
// only LitScenes windows inside the main app window's bounds. The face-cam
// panel is included on purpose — that is how the face gets into the video —
// while the control bar is excluded. An explicit Settings preference can widen
// capture to the full display. Recordings use one .mov segment per
// Record→Pause/Stop span because ScreenCaptureKit cannot pause. Stop stitches
// the segments and saves one .mov to ~/Downloads, never the project library.

enum SessionCaptureScope: String, CaseIterable, Identifiable {
    case litScenesApp = "litscenes_app"
    case entireDisplay = "entire_display"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .litScenesApp: return "LitScenes Only"
        case .entireDisplay: return "Entire Display"
        }
    }

    var detail: String {
        switch self {
        case .litScenesApp:
            return "Records the LitScenes window, its sheets and popovers, and the face cam. Other apps and notifications stay out."
        case .entireDisplay:
            return "Records everything visible on the display containing LitScenes. Use this only for walkthroughs that leave the app."
        }
    }

    var icon: String {
        switch self {
        case .litScenesApp: return "macwindow"
        case .entireDisplay: return "display"
        }
    }
}

private enum SessionRecordingPreferenceKey {
    static let captureScope = "litscenes.session_recording.capture_scope"
    static let faceCam = "litscenes.session_recording.face_cam"
    static let microphone = "litscenes.session_recording.microphone"
    static let systemAudio = "litscenes.session_recording.system_audio"
    static let cameraDeviceID = "litscenes.session_recording.camera_device_id"
}

enum SessionRecordingPhase: String, Equatable {
    case idle
    case requestingPermissions
    case ready
    case starting
    case recording
    case pausing
    case paused
    case finalizing
    case failed
}

/// Recording-time accumulator. Paused time is excluded: the clock only runs
/// between segmentDidStart and segmentDidEnd, and double transitions are
/// no-ops so delegate races cannot double-count a segment.
struct SessionRecordingClock: Equatable {
    private(set) var accumulatedSeconds: Double = 0
    private(set) var segmentStartedAt: Date?

    var isRunning: Bool { segmentStartedAt != nil }

    mutating func segmentDidStart(at date: Date) {
        guard segmentStartedAt == nil else { return }
        segmentStartedAt = date
    }

    mutating func segmentDidEnd(at date: Date) {
        guard let startedAt = segmentStartedAt else { return }
        accumulatedSeconds += max(0, date.timeIntervalSince(startedAt))
        segmentStartedAt = nil
    }

    func elapsedSeconds(now: Date) -> Double {
        guard let startedAt = segmentStartedAt else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, now.timeIntervalSince(startedAt))
    }

    static func elapsedLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%02d:%02d", minutes, remainder)
    }
}

enum SessionRecordingNaming {
    /// "LitScenes Session 2001-01-31 at 10.32.15.mov" — the operator's wall
    /// clock, not UTC: the filename should read like the moment they recorded.
    static func filename(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "LitScenes Session \(formatter.string(from: date)).mov"
    }

    static func collisionSafeURL(
        in directory: URL,
        date: Date,
        timeZone: TimeZone = .current,
        fileExists: (URL) -> Bool
    ) -> URL {
        let base = filename(for: date, timeZone: timeZone)
        let first = directory.appendingPathComponent(base)
        guard fileExists(first) else { return first }
        let stem = (base as NSString).deletingPathExtension
        var ordinal = 2
        while ordinal < 10_000 {
            let candidate = directory.appendingPathComponent("\(stem) \(ordinal).mov")
            if !fileExists(candidate) { return candidate }
            ordinal += 1
        }
        return first
    }
}

enum SessionFinalizePlan: Equatable {
    case none
    case moveSingle(URL)
    case stitch([URL])

    static func plan(forCompletedSegments urls: [URL]) -> SessionFinalizePlan {
        switch urls.count {
        case 0: return .none
        case 1: return .moveSingle(urls[0])
        default: return .stitch(urls)
        }
    }
}

@MainActor
final class SessionRecorder: NSObject, ObservableObject,
    @preconcurrency SCRecordingOutputDelegate, @preconcurrency SCStreamDelegate {

    @Published private(set) var phase: SessionRecordingPhase = .idle
    @Published private(set) var status = ""
    @Published private(set) var faceCamNote = ""
    @Published private(set) var needsScreenPermission = false
    @Published private(set) var clock = SessionRecordingClock()
    @Published private(set) var lastSavedURL: URL?
    @Published private(set) var completedSegmentCount = 0
    @Published var captureScope: SessionCaptureScope {
        didSet {
            LitScenesPreferences.store.set(captureScope.rawValue, forKey: SessionRecordingPreferenceKey.captureScope)
        }
    }
    @Published var captureSystemAudio: Bool {
        didSet {
            LitScenesPreferences.store.set(captureSystemAudio, forKey: SessionRecordingPreferenceKey.systemAudio)
        }
    }
    @Published private(set) var captureMicrophone: Bool {
        didSet {
            LitScenesPreferences.store.set(captureMicrophone, forKey: SessionRecordingPreferenceKey.microphone)
        }
    }
    @Published private(set) var faceCamEnabled: Bool {
        didSet {
            LitScenesPreferences.store.set(faceCamEnabled, forKey: SessionRecordingPreferenceKey.faceCam)
        }
    }
    @Published var preferredCameraDeviceID: String {
        didSet {
            LitScenesPreferences.store.set(preferredCameraDeviceID, forKey: SessionRecordingPreferenceKey.cameraDeviceID)
        }
    }
    @Published var preferredMicrophoneDeviceID: String {
        didSet {
            CaptureAudioInputPreference.deviceId = preferredMicrophoneDeviceID
        }
    }

    let micMeter = ShotMicrophoneRecorder()

    private let cameraSession = AVCaptureSession()
    private let faceCam = SessionFaceCamController()
    private let controlBar = SessionControlBarController()

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var segmentContinuation: CheckedContinuation<Void, Error>?
    private var currentSegmentURL: URL?
    private var completedSegmentURLs: [URL] = [] {
        didSet { completedSegmentCount = completedSegmentURLs.count }
    }
    private var segmentCounter = 0
    private var scratchDirectory: URL?
    private var pinnedDisplayID: CGDirectDisplayID?
    private var pinnedAppWindowID: CGWindowID?
    private var pinnedPixelSize: (width: Int, height: Int)?
    private var activeCaptureScope: SessionCaptureScope?
    private var microphoneGranted = false
    private var cameraGranted = false
    private var finalizeTask: Task<Void, Never>?

    override init() {
        let defaults = LitScenesPreferences.store
        captureScope = defaults.string(forKey: SessionRecordingPreferenceKey.captureScope)
            .flatMap(SessionCaptureScope.init(rawValue:)) ?? .litScenesApp
        captureSystemAudio = defaults.object(forKey: SessionRecordingPreferenceKey.systemAudio) as? Bool ?? true
        captureMicrophone = defaults.object(forKey: SessionRecordingPreferenceKey.microphone) as? Bool ?? true
        faceCamEnabled = defaults.object(forKey: SessionRecordingPreferenceKey.faceCam) as? Bool ?? true

        let cameras = CameraRecorder.videoDevices()
        let savedCameraID = defaults.string(forKey: SessionRecordingPreferenceKey.cameraDeviceID) ?? ""
        preferredCameraDeviceID = cameras.contains(where: { $0.id == savedCameraID })
            ? savedCameraID
            : cameras.first?.id ?? ""

        let microphones = CameraRecorder.audioDevices()
        preferredMicrophoneDeviceID = CaptureAudioInputPreference.resolvedDeviceId(in: microphones)
        super.init()
    }

    var isActive: Bool {
        switch phase {
        case .idle: return false
        case .failed: return completedSegmentURLs.isEmpty == false
        default: return true
        }
    }

    var canSavePartial: Bool {
        phase == .failed && !completedSegmentURLs.isEmpty
    }

    var effectiveCaptureScope: SessionCaptureScope {
        activeCaptureScope ?? captureScope
    }

    var cameraDevices: [CameraDeviceOption] {
        CameraRecorder.videoDevices()
    }

    var microphoneDevices: [CameraDeviceOption] {
        CameraRecorder.audioDevices()
    }

    // MARK: - Session lifecycle

    func beginSession() {
        // From .failed only when nothing is salvageable — a failed session
        // holding completed segments keeps its Save Partial offer instead.
        guard phase == .idle || (phase == .failed && completedSegmentURLs.isEmpty) else { return }
        if phase == .failed {
            cleanupSession()
            phase = .idle
        }
        Task { await beginSessionFlow() }
    }

    private func beginSessionFlow() async {
        phase = .requestingPermissions
        status = "Requesting permissions"
        needsScreenPermission = false
        faceCamNote = ""
        lastSavedURL = nil

        let appWindow = recordingContentWindow()
        pinnedAppWindowID = appWindow.map { CGWindowID($0.windowNumber) }
        pinnedDisplayID = displayID(for: appWindow?.screen ?? pinnedScreen())
        activeCaptureScope = captureScope
        let screen = pinnedScreen()

        if effectiveCaptureScope == .litScenesApp, pinnedAppWindowID == nil {
            phase = .failed
            status = "The LitScenes window is not available to record. Reopen the main window and try again."
            controlBar.show(recorder: self, on: screen)
            return
        }

        // Surface setup before any TCC prompt. The panel is intentionally
        // omitted from screenshots and recordings (`sharingType = .none`),
        // but it remains the operator's visible recorder-state indicator.
        controlBar.show(recorder: self, on: screen)

        guard requestScreenRecordingPermission() else {
            needsScreenPermission = true
            phase = .failed
            status = "macOS has not granted Screen Recording to this running copy of LitScenes. "
                + "Turn LitScenes on in System Settings, then quit and reopen the app. "
                + "If it is already on, quit and reopen; if it still fails, remove stale "
                + "duplicate LitScenes entries and add the current app again."
            controlBar.show(recorder: self, on: screen)
            return
        }

        if captureMicrophone {
            await prepareMicrophoneForCurrentSession()
        } else {
            microphoneGranted = false
        }

        if faceCamEnabled {
            await prepareFaceCamForCurrentSession()
        } else {
            cameraGranted = false
        }
        if cameraGranted, faceCamEnabled, !cameraSession.inputs.isEmpty {
            cameraSession.startRunning()
            faceCam.show(
                session: cameraSession,
                on: screen,
                within: effectiveCaptureScope == .litScenesApp ? appWindow?.frame : nil
            )
        }

        controlBar.show(recorder: self, on: screen)
        phase = .ready
        if status.isEmpty || status == "Requesting permissions" {
            status = faceCamEnabled ? "Position your face cam, then hit Record" : "Ready to record"
        }
    }

    func setFaceCamEnabled(_ enabled: Bool) {
        faceCamEnabled = enabled
        guard phase == .ready else { return }
        guard enabled else {
            faceCam.hide()
            if cameraSession.isRunning { cameraSession.stopRunning() }
            faceCamNote = ""
            if status.isEmpty || status == "Position your face cam, then hit Record" {
                status = "Ready to record"
            }
            return
        }
        Task { await prepareAndShowFaceCam() }
    }

    func setCaptureMicrophoneEnabled(_ enabled: Bool) {
        captureMicrophone = enabled
        guard phase == .ready else { return }
        guard enabled else {
            microphoneGranted = false
            micMeter.shutdown()
            status = ""
            return
        }
        Task { await prepareMicrophoneForCurrentSession() }
    }

    func selectCameraDevice(_ deviceID: String) {
        preferredCameraDeviceID = deviceID
    }

    func selectMicrophoneDevice(_ deviceID: String) {
        preferredMicrophoneDeviceID = deviceID
    }

    func showControls() {
        guard phase != .idle else { return }
        controlBar.show(recorder: self, on: pinnedScreen())
    }

    func startRecording() {
        guard phase == .ready else { return }
        phase = .starting
        status = "Starting"
        Task {
            do {
                try await startSegment()
                phase = .recording
                status = ""
            } catch {
                phase = .failed
                status = error.localizedDescription
            }
        }
    }

    func pause() {
        guard phase == .recording else { return }
        phase = .pausing
        Task {
            do {
                try await finishSegment()
                phase = .paused
                status = "Paused"
            } catch {
                phase = .failed
                status = error.localizedDescription
            }
        }
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .starting
        status = "Resuming"
        Task {
            do {
                try await startSegment()
                phase = .recording
                status = ""
            } catch {
                phase = .failed
                status = error.localizedDescription
            }
        }
    }

    func stopAndSave() {
        guard phase == .recording || phase == .paused else { return }
        let wasRecording = phase == .recording
        phase = .finalizing
        status = "Saving to Downloads…"
        let task = Task {
            if wasRecording {
                do {
                    try await finishSegment()
                } catch {
                    // The live segment is lost, but completed ones may remain.
                    status = error.localizedDescription
                }
            }
            await finalize()
            finalizeTask = nil
        }
        finalizeTask = task
    }

    func savePartial() {
        guard canSavePartial else { return }
        phase = .finalizing
        status = "Saving to Downloads…"
        let task = Task {
            await finalize()
            finalizeTask = nil
        }
        finalizeTask = task
    }

    func cancelSession() {
        let activeStream = stream
        stream = nil
        recordingOutput = nil
        let continuation = segmentContinuation
        segmentContinuation = nil
        continuation?.resume(throwing: CancellationError())
        if let activeStream {
            Task { try? await self.stopCapture(activeStream) }
        }
        cleanupSession()
        phase = .idle
        status = ""
    }

    /// ⌘Q path (SessionAppDelegate): finish the live segment and save whatever
    /// exists — a hard kill would leave the current .mov without a moov atom.
    func stopForTermination() async {
        if let finalizeTask {
            await finalizeTask.value
            return
        }
        switch phase {
        case .recording, .pausing, .starting:
            try? await finishSegment()
            await finalize()
        case .paused, .failed:
            if !completedSegmentURLs.isEmpty {
                await finalize()
            } else {
                cancelSession()
            }
        case .ready, .requestingPermissions:
            cancelSession()
        case .idle, .finalizing:
            break
        }
    }

    // MARK: - Segments

    private func startSegment() async throws {
        guard stream == nil else {
            throw ScreenGraphError.capture("A session recording segment is already active.")
        }

        // Fresh shareable content every segment — SCWindow/SCDisplay references
        // from an earlier snapshot go stale across a pause.
        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == pinnedDisplayID })
            ?? content.displays.first else {
            throw ScreenGraphError.capture("No capturable display was found.")
        }

        // The control bar carries sharingType == .none, which normally keeps it
        // out of shareable content entirely. If it does surface, exclude it.
        let excludedWindows = content.windows.filter { window in
            guard let number = controlBar.windowNumber else { return false }
            return window.windowID == CGWindowID(number)
        }

        let filter: SCContentFilter
        var sourceRect: CGRect?
        switch effectiveCaptureScope {
        case .litScenesApp:
            guard let application = content.applications.first(where: { $0.processID == getpid() }) else {
                throw ScreenGraphError.capture("LitScenes is not available in the screen-capture window list.")
            }
            guard let windowID = pinnedAppWindowID,
                  let appWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenGraphError.capture("The LitScenes window closed before recording began.")
            }
            filter = SCContentFilter(
                display: display,
                including: [application],
                exceptingWindows: excludedWindows
            )
            filter.includeMenuBar = false
            let localRect = CGRect(
                x: appWindow.frame.minX - display.frame.minX,
                y: appWindow.frame.minY - display.frame.minY,
                width: appWindow.frame.width,
                height: appWindow.frame.height
            )
            let displayBounds = CGRect(origin: .zero, size: display.frame.size)
            let clippedRect = localRect.intersection(displayBounds)
            guard !clippedRect.isNull, clippedRect.width >= 64, clippedRect.height >= 64 else {
                throw ScreenGraphError.capture("The LitScenes window is outside the selected display.")
            }
            sourceRect = clippedRect
        case .entireDisplay:
            filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            filter.includeMenuBar = true
        }

        // Dimensions are pinned to segment 1: the passthrough stitch cannot
        // scale, so every segment must match even if the window/display changed.
        if pinnedPixelSize == nil {
            let scale = CGFloat(filter.pointPixelScale)
            let pointSize = sourceRect?.size ?? display.frame.size
            pinnedPixelSize = (
                width: evenPixelDimension(pointSize.width, scale: scale),
                height: evenPixelDimension(pointSize.height, scale: scale)
            )
        }
        guard let pixelSize = pinnedPixelSize else {
            throw ScreenGraphError.capture("Could not determine the display size.")
        }

        let configuration = SCStreamConfiguration()
        configuration.width = pixelSize.width
        configuration.height = pixelSize.height
        if let sourceRect {
            configuration.sourceRect = sourceRect
        }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 6
        configuration.showsCursor = true
        configuration.showMouseClicks = true
        configuration.captureResolution = .best
        configuration.capturesAudio = captureSystemAudio
        configuration.captureMicrophone = microphoneGranted && captureMicrophone
        if configuration.captureMicrophone {
            let deviceId = CaptureAudioInputPreference.resolvedDeviceId(in: CameraRecorder.audioDevices())
            if !deviceId.isEmpty {
                configuration.microphoneCaptureDeviceID = deviceId
            }
        }

        segmentCounter += 1
        let segmentURL = try ensureScratchDirectory()
            .appendingPathComponent(String(format: "segment-%03d.mov", segmentCounter))

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = segmentURL
        // .mov, not .mp4: AVAssetExportPresetPassthrough over a composition
        // routinely fails with -11838 when the output is .mp4.
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .h264

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        try stream.addRecordingOutput(recordingOutput)

        self.stream = stream
        self.recordingOutput = recordingOutput
        self.currentSegmentURL = segmentURL

        do {
            try await startCapture(stream)
        } catch {
            self.stream = nil
            self.recordingOutput = nil
            self.currentSegmentURL = nil
            throw error
        }
        clock.segmentDidStart(at: Date())
    }

    private func finishSegment() async throws {
        guard let stream, let recordingOutput else { return }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                segmentContinuation = continuation
                do {
                    try stream.removeRecordingOutput(recordingOutput)
                } catch {
                    segmentContinuation = nil
                    continuation.resume(throwing: error)
                }
            }
        } catch {
            self.stream = nil
            self.recordingOutput = nil
            clock.segmentDidEnd(at: Date())
            if let url = currentSegmentURL {
                try? FileManager.default.removeItem(at: url)
                currentSegmentURL = nil
            }
            try? await stopCapture(stream)
            throw error
        }
        self.stream = nil
        self.recordingOutput = nil
        clock.segmentDidEnd(at: Date())
        if let url = currentSegmentURL {
            completedSegmentURLs.append(url)
            currentSegmentURL = nil
        }
        try? await stopCapture(stream)
    }

    /// Disk full, display disconnect, TCC revoked mid-segment. The partial
    /// file may lack its moov atom — never stitch it; completed segments are
    /// kept and offered via Save Partial.
    private func handleMidSegmentFailure(_ error: Error) {
        let failedStream = stream
        stream = nil
        recordingOutput = nil
        clock.segmentDidEnd(at: Date())
        if let url = currentSegmentURL {
            try? FileManager.default.removeItem(at: url)
            currentSegmentURL = nil
        }
        if let failedStream {
            Task { try? await self.stopCapture(failedStream) }
        }
        phase = .failed
        status = error.localizedDescription
    }

    // MARK: - SCRecordingOutputDelegate / SCStreamDelegate

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let continuation = segmentContinuation
        segmentContinuation = nil
        continuation?.resume(returning: ())
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        if let continuation = segmentContinuation {
            segmentContinuation = nil
            continuation.resume(throwing: error)
            return
        }
        handleMidSegmentFailure(error)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard self.stream != nil else { return }
        if let continuation = segmentContinuation {
            segmentContinuation = nil
            continuation.resume(throwing: error)
            return
        }
        handleMidSegmentFailure(error)
    }

    // MARK: - Finalize

    private func finalize() async {
        phase = .finalizing
        status = "Saving to Downloads…"
        switch SessionFinalizePlan.plan(forCompletedSegments: completedSegmentURLs) {
        case .none:
            cleanupSession()
            phase = .idle
            status = "Nothing was recorded."
        case .moveSingle(let url):
            do {
                let target = collisionSafeDownloadsURL()
                try moveIntoPlace(from: url, to: target)
                completeSave(target)
            } catch {
                phase = .failed
                status = error.localizedDescription
            }
        case .stitch(let urls):
            do {
                let target = collisionSafeDownloadsURL()
                try await stitch(urls, to: target)
                completeSave(target)
            } catch {
                phase = .failed
                status = error.localizedDescription
            }
        }
    }

    private func completeSave(_ target: URL) {
        lastSavedURL = target
        NSWorkspace.shared.activateFileViewerSelecting([target])
        cleanupSession()
        phase = .idle
        status = ""
    }

    private func cleanupSession() {
        if let scratchDirectory {
            try? FileManager.default.removeItem(at: scratchDirectory)
        }
        scratchDirectory = nil
        completedSegmentURLs = []
        currentSegmentURL = nil
        segmentCounter = 0
        pinnedDisplayID = nil
        pinnedAppWindowID = nil
        pinnedPixelSize = nil
        activeCaptureScope = nil
        clock = SessionRecordingClock()
        needsScreenPermission = false
        faceCam.hide()
        controlBar.hide()
        micMeter.shutdown()
        if cameraSession.isRunning { cameraSession.stopRunning() }
    }

    /// Sequential concat of identically configured segments. Passthrough keeps
    /// this a remux, not a re-encode; if the AAC priming click at joins ever
    /// proves audible, the fallback is AVAssetExportPresetHighestQuality here.
    private func stitch(_ urls: [URL], to outputURL: URL) async throws {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ScreenGraphError.capture("Could not assemble the session recording.")
        }
        var audioTracks: [AVMutableCompositionTrack] = []
        var cursor = CMTime.zero

        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first else {
                continue
            }
            let videoRange = try await sourceVideo.load(.timeRange)
            try videoTrack.insertTimeRange(videoRange, of: sourceVideo, at: cursor)

            let sourceAudioTracks = try await asset.loadTracks(withMediaType: .audio)
            for (index, sourceAudio) in sourceAudioTracks.enumerated() {
                if audioTracks.count <= index {
                    guard let track = composition.addMutableTrack(
                        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
                    ) else { continue }
                    if cursor > .zero {
                        // A track that first appears mid-session (e.g. system
                        // audio toggled on while paused) pads its head to stay
                        // in sync with the segments before it.
                        track.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: cursor))
                    }
                    audioTracks.append(track)
                }
                let audioRange = try await sourceAudio.load(.timeRange)
                let clipped = CMTimeRange(
                    start: audioRange.start,
                    duration: CMTimeMinimum(audioRange.duration, videoRange.duration)
                )
                try audioTracks[index].insertTimeRange(clipped, of: sourceAudio, at: cursor)
            }
            for index in sourceAudioTracks.count..<audioTracks.count {
                audioTracks[index].insertEmptyTimeRange(CMTimeRange(start: cursor, duration: videoRange.duration))
            }
            // CMTime arithmetic only: summing Double seconds drifts the insert
            // points by a frame and flashes black at the joins.
            cursor = CMTimeAdd(cursor, videoRange.duration)
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetPassthrough
        ) else {
            throw ScreenGraphError.capture("Could not assemble the session recording.")
        }
        try await MediaExportGuard.export(exportSession, to: outputURL, as: .mov, operation: "session recording export")
    }

    private func collisionSafeDownloadsURL() -> URL {
        SessionRecordingNaming.collisionSafeURL(in: downloadsDirectory(), date: Date()) {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private func downloadsDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    }

    private func moveIntoPlace(from source: URL, to target: URL) throws {
        do {
            try FileManager.default.moveItem(at: source, to: target)
        } catch {
            // Cross-volume temp dirs can refuse a rename; fall back to copy.
            try FileManager.default.copyItem(at: source, to: target)
            try? FileManager.default.removeItem(at: source)
        }
    }

    private func ensureScratchDirectory() throws -> URL {
        if let scratchDirectory { return scratchDirectory }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("litscenes-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        scratchDirectory = directory
        return directory
    }

    // MARK: - Permissions, display, camera

    private func requestScreenRecordingPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGRequestScreenCaptureAccess()
    }

    func openScreenRecordingPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func recordingContentWindow() -> NSWindow? {
        let windows = NSApplication.shared.windows.filter { !$0.isMiniaturized && $0.isVisible }
        return windows.first { $0.styleMask.contains(.titled) && $0.canBecomeKey }
            ?? windows.first { $0.canBecomeKey && !$0.ignoresMouseEvents }
    }

    private func pinnedScreen() -> NSScreen? {
        recordingContentWindow()?.screen ?? NSScreen.main
    }

    private func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        guard let screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return CGMainDisplayID()
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    private func evenPixelDimension(_ points: CGFloat, scale: CGFloat) -> Int {
        let pixels = max(64, Int((points * scale).rounded()))
        return pixels.isMultiple(of: 2) ? pixels : pixels - 1
    }

    private func prepareMicrophoneForCurrentSession() async {
        let permissionGranted = await CameraRecorder.requestMicrophoneAccess()
        guard captureMicrophone else {
            microphoneGranted = false
            micMeter.shutdown()
            return
        }
        microphoneGranted = permissionGranted
        guard microphoneGranted else {
            status = "Narration off — microphone permission denied"
            return
        }
        do {
            try micMeter.prepare(deviceId: preferredMicrophoneDeviceID)
            status = ""
        } catch {
            microphoneGranted = false
            status = "Narration off — \(error.localizedDescription)"
        }
    }

    private func prepareFaceCamForCurrentSession() async {
        let permissionGranted = await CameraRecorder.requestCameraAccess()
        guard faceCamEnabled else {
            cameraGranted = false
            return
        }
        cameraGranted = permissionGranted
        guard cameraGranted else {
            faceCamNote = "Face cam off — camera permission denied"
            return
        }
        configureCameraPreview()
    }

    private func prepareAndShowFaceCam() async {
        await prepareFaceCamForCurrentSession()
        guard cameraGranted, faceCamEnabled, !cameraSession.inputs.isEmpty else { return }
        if !cameraSession.isRunning { cameraSession.startRunning() }
        faceCam.show(
            session: cameraSession,
            on: pinnedScreen(),
            within: effectiveCaptureScope == .litScenesApp ? recordingContentWindow()?.frame : nil
        )
        if status.isEmpty || status == "Ready to record" {
            status = "Position your face cam, then hit Record"
        }
    }

    private func configureCameraPreview() {
        let cameras = CameraRecorder.videoDevices()
        let option = cameras.first(where: { $0.id == preferredCameraDeviceID }) ?? cameras.first
        guard let option,
              let device = AVCaptureDevice(uniqueID: option.id) else {
            faceCamNote = "No camera was found"
            return
        }
        cameraSession.beginConfiguration()
        if cameraSession.canSetSessionPreset(.hd1280x720) {
            cameraSession.sessionPreset = .hd1280x720
        }
        do {
            for input in cameraSession.inputs {
                cameraSession.removeInput(input)
            }
            let input = try AVCaptureDeviceInput(device: device)
            if cameraSession.canAddInput(input) {
                cameraSession.addInput(input)
                preferredCameraDeviceID = option.id
                faceCamNote = ""
            }
        } catch {
            faceCamNote = error.localizedDescription
        }
        cameraSession.commitConfiguration()
    }

    // MARK: - Capture bridging

    private func startCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func stopCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

/// ⌘Q guard: without it, terminating mid-recording kills SCRecordingOutput
/// before it writes the moov atom and the segment is unreadable.
@MainActor
final class SessionAppDelegate: NSObject, NSApplicationDelegate {
    weak var sessionRecorder: SessionRecorder?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let sessionRecorder, sessionRecorder.isActive else { return .terminateNow }
        Task { @MainActor in
            await sessionRecorder.stopForTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
