import AppKit
@preconcurrency import AVFoundation
import Foundation
@preconcurrency import ScreenCaptureKit

struct ScreenAreaSelection: Hashable {
    var displayId: CGDirectDisplayID
    var sourceRect: CGRect
    var scaleFactor: CGFloat

    var outputPixelWidth: Int {
        max(64, Int((sourceRect.width * scaleFactor).rounded()))
    }

    var outputPixelHeight: Int {
        max(64, Int((sourceRect.height * scaleFactor).rounded()))
    }
}

struct ScreenAreaRecordingResult: Hashable {
    var url: URL
    var durationSeconds: Double
    var byteCount: Int64
}

enum ScreenAreaSelectionError: LocalizedError {
    case cancelled
    case noScreen
    case tooSmall

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Screen area selection cancelled."
        case .noScreen:
            return "No screen is available for selection."
        case .tooSmall:
            return "Select a larger screen area."
        }
    }
}

@MainActor
final class ScreenAreaSelectionController {
    private var window: NSWindow?
    private var continuation: CheckedContinuation<ScreenAreaSelection, Error>?
    private var screen: NSScreen?

    func selectArea() async throws -> ScreenAreaSelection {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            showSelectionWindow()
        }
    }

    private func showSelectionWindow() {
        guard let screen = NSScreen.main else {
            finish(with: .failure(ScreenAreaSelectionError.noScreen))
            return
        }
        self.screen = screen

        let selectionView = ScreenAreaSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        selectionView.onComplete = { [weak self] rect in
            self?.completeSelection(rect)
        }
        selectionView.onCancel = { [weak self] in
            self?.finish(with: .failure(ScreenAreaSelectionError.cancelled))
        }

        let overlayWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.level = .screenSaver
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlayWindow.contentView = selectionView
        overlayWindow.makeKeyAndOrderFront(nil)
        overlayWindow.makeFirstResponder(selectionView)
        window = overlayWindow
    }

    private func completeSelection(_ rect: CGRect) {
        guard let screen else {
            finish(with: .failure(ScreenAreaSelectionError.noScreen))
            return
        }
        let normalized = rect.standardized.integral
        guard normalized.width >= 64, normalized.height >= 64 else {
            finish(with: .failure(ScreenAreaSelectionError.tooSmall))
            return
        }
        let displayId = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) } ?? CGMainDisplayID()
        finish(with: .success(ScreenAreaSelection(
            displayId: displayId,
            sourceRect: normalized,
            scaleFactor: screen.backingScaleFactor
        )))
    }

    private func finish(with result: Result<ScreenAreaSelection, Error>) {
        window?.orderOut(nil)
        window = nil
        screen = nil
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let selection):
            continuation.resume(returning: selection)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private final class ScreenAreaSelectionView: NSView {
    var onComplete: (CGRect) -> Void = { _ in }
    var onCancel: () -> Void = {}

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.34).setFill()
        bounds.fill()

        guard let selectionRect else {
            drawInstruction()
            return
        }

        NSColor.clear.setFill()
        selectionRect.fill(using: .clear)
        NSColor.systemYellow.withAlphaComponent(0.90).setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 2
        path.stroke()

        let label = "\(Int(selectionRect.width)) x \(Int(selectionRect.height))"
        drawPill(label, at: CGPoint(x: selectionRect.minX + 12, y: max(selectionRect.minY - 34, 14)))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragCurrent = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        guard let selectionRect else {
            onCancel()
            return
        }
        onComplete(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        let x = min(dragStart.x, dragCurrent.x)
        let y = min(dragStart.y, dragCurrent.y)
        let width = abs(dragCurrent.x - dragStart.x)
        let height = abs(dragCurrent.y - dragStart.y)
        guard width > 1, height > 1 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height).intersection(bounds)
    }

    private func drawInstruction() {
        drawPill("Drag to select a screen area. Esc cancels.", at: CGPoint(x: 24, y: 24))
    }

    private func drawPill(_ text: String, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributed.size()
        let rect = CGRect(x: point.x, y: point.y, width: textSize.width + 24, height: textSize.height + 14)
        NSColor.black.withAlphaComponent(0.76).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        attributed.draw(at: CGPoint(x: rect.minX + 12, y: rect.minY + 7))
    }
}

@MainActor
final class ScreenAreaRecorder: NSObject, @preconcurrency SCRecordingOutputDelegate, @preconcurrency SCStreamDelegate {
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var finishContinuation: CheckedContinuation<ScreenAreaRecordingResult, Error>?

    func startRecording(selection: ScreenAreaSelection, outputURL: URL) async throws {
        guard stream == nil else {
            throw ScreenGraphError.capture("A screen area recording is already active.")
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == selection.displayId }) ?? content.displays.first else {
            throw ScreenGraphError.capture("No capturable display was found.")
        }

        let ownApplications = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        filter.includeMenuBar = true

        let configuration = SCStreamConfiguration()
        configuration.width = selection.outputPixelWidth
        configuration.height = selection.outputPixelHeight
        configuration.sourceRect = selection.sourceRect
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 6
        configuration.showsCursor = true
        configuration.showMouseClicks = true
        configuration.capturesAudio = false
        configuration.captureMicrophone = false
        configuration.captureResolution = .best

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mp4
        recordingConfiguration.videoCodecType = .h264

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        try stream.addRecordingOutput(recordingOutput)

        self.stream = stream
        self.recordingOutput = recordingOutput
        self.outputURL = outputURL

        do {
            try await startCapture(stream)
        } catch {
            self.stream = nil
            self.recordingOutput = nil
            self.outputURL = nil
            throw error
        }
    }

    func stopRecording() async throws -> ScreenAreaRecordingResult {
        guard let stream, let recordingOutput else {
            throw ScreenGraphError.capture("No screen area recording is active.")
        }

        let result: ScreenAreaRecordingResult = try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            do {
                try stream.removeRecordingOutput(recordingOutput)
            } catch {
                finishContinuation = nil
                continuation.resume(throwing: error)
            }
        }
        try? await stopCapture(stream)
        return result
    }

    func cancelRecording() async {
        let activeStream = stream
        stream = nil
        recordingOutput = nil
        outputURL = nil
        finishContinuation?.resume(throwing: ScreenAreaSelectionError.cancelled)
        finishContinuation = nil
        if let activeStream {
            try? await stopCapture(activeStream)
        }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
        stream = nil
        self.recordingOutput = nil
        outputURL = nil
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        guard let outputURL else {
            finishContinuation?.resume(throwing: ScreenGraphError.capture("Screen recording finished without an output URL."))
            finishContinuation = nil
            return
        }

        let values = try? outputURL.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values?.fileSize ?? 0)
        let duration = recordingOutput.recordedDuration.seconds.isFinite ? recordingOutput.recordedDuration.seconds : 0
        finishContinuation?.resume(returning: ScreenAreaRecordingResult(
            url: outputURL,
            durationSeconds: max(duration, 0),
            byteCount: byteCount
        ))
        finishContinuation = nil
        stream = nil
        self.recordingOutput = nil
        self.outputURL = nil
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        finishContinuation?.resume(throwing: error)
        finishContinuation = nil
        self.stream = nil
        recordingOutput = nil
        outputURL = nil
    }

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

    fileprivate func stopCapture(_ stream: SCStream) async throws {
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
