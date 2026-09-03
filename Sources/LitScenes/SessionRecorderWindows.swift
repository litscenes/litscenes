@preconcurrency import AVFoundation
import AppKit
import SwiftUI

// The two floating panels of File > Record Session. Both are nonactivating
// NSPanels so operating the recorder does not steal focus from the walkthrough.
// The face cam is deliberately capturable (it is how the face gets into the
// video); the control bar carries sharingType = .none and never appears in the
// recording. In LitScenes-only mode the face panel is kept inside the app's
// captured bounds, including when an older autosaved position is restored.

@MainActor
final class SessionFaceCamController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var captureBounds: NSRect?
    private var isConstrainingFrame = false

    func show(session: AVCaptureSession, on screen: NSScreen?, within captureBounds: NSRect?) {
        self.captureBounds = captureBounds
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                styleMask: [.nonactivatingPanel, .borderless, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.contentAspectRatio = NSSize(width: 16, height: 9)
            panel.minSize = NSSize(width: 240, height: 135)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: SessionFaceCamView(session: session))
            if !panel.setFrameUsingName(Self.frameAutosaveName) {
                panel.setFrame(Self.defaultFrame(on: screen), display: false)
            }
            panel.setFrameAutosaveName(Self.frameAutosaveName)
            self.panel = panel
        }
        constrainPanelIfNeeded()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        constrainPanelIfNeeded()
    }

    func windowDidResize(_ notification: Notification) {
        constrainPanelIfNeeded()
    }

    private static let frameAutosaveName = "LitScenesSessionFaceCam"

    private static func defaultFrame(on screen: NSScreen?) -> NSRect {
        let size = NSSize(width: 320, height: 180)
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else {
            return NSRect(origin: .zero, size: size)
        }
        return NSRect(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24,
            width: size.width,
            height: size.height
        )
    }

    private static func constrainedFrame(_ frame: NSRect, within bounds: NSRect) -> NSRect {
        let safeBounds = bounds.insetBy(dx: 18, dy: 18)
        guard safeBounds.width > 0, safeBounds.height > 0 else { return frame }

        var result = frame
        if result.width > safeBounds.width || result.height > safeBounds.height {
            let scale = min(safeBounds.width / result.width, safeBounds.height / result.height)
            result.size = NSSize(width: result.width * scale, height: result.height * scale)
        }
        result.origin.x = min(max(result.minX, safeBounds.minX), safeBounds.maxX - result.width)
        result.origin.y = min(max(result.minY, safeBounds.minY), safeBounds.maxY - result.height)
        return result
    }

    private func constrainPanelIfNeeded() {
        guard !isConstrainingFrame, let panel, let captureBounds else { return }
        let constrained = Self.constrainedFrame(panel.frame, within: captureBounds)
        guard constrained != panel.frame else { return }
        isConstrainingFrame = true
        panel.setFrame(constrained, display: true)
        isConstrainingFrame = false
    }
}

@MainActor
final class SessionControlBarController {
    private var panel: NSPanel?

    private static let panelSize = NSSize(width: 560, height: 64)

    var windowNumber: Int? {
        panel.map(\.windowNumber)
    }

    func show(recorder: SessionRecorder, on screen: NSScreen?) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: Self.panelSize),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            panel.sharingType = .none
            let hosting = NSHostingView(
                rootView: SessionControlBarView(recorder: recorder, micMeter: recorder.micMeter)
            )
            // If first-click on the non-key panel ever misbehaves, the known
            // fix is an NSHostingView subclass returning true from
            // acceptsFirstMouse(for:).
            hosting.sizingOptions = [.preferredContentSize]
            panel.contentView = hosting
            if panel.setFrameUsingName(Self.frameAutosaveName) {
                var restoredFrame = panel.frame
                let midpoint = CGPoint(x: restoredFrame.midX, y: restoredFrame.midY)
                restoredFrame.size = Self.panelSize
                restoredFrame.origin = CGPoint(
                    x: midpoint.x - Self.panelSize.width / 2,
                    y: midpoint.y - Self.panelSize.height / 2
                )
                panel.setFrame(restoredFrame, display: false)
            } else {
                panel.setFrame(Self.defaultFrame(on: screen), display: false)
            }
            panel.setFrameAutosaveName(Self.frameAutosaveName)
            self.panel = panel
        }
        keepPanelVisible(on: screen)
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private static let frameAutosaveName = "LitScenesSessionControlBar"

    private static func defaultFrame(on screen: NSScreen?) -> NSRect {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else {
            return NSRect(origin: .zero, size: panelSize)
        }
        return NSRect(
            x: visible.midX - panelSize.width / 2,
            y: visible.maxY - panelSize.height - 24,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    private func keepPanelVisible(on screen: NSScreen?) {
        guard let panel else { return }
        let targetScreen = screen
            ?? NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })
            ?? NSScreen.main
        guard let visible = targetScreen?.visibleFrame else { return }
        let safe = visible.insetBy(dx: 12, dy: 12)
        var frame = panel.frame
        frame.origin.x = min(max(frame.minX, safe.minX), safe.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, safe.minY), safe.maxY - frame.height)
        if frame != panel.frame {
            panel.setFrame(frame, display: true)
        }
    }
}

struct SessionFaceCamView: View {
    let session: AVCaptureSession

    var body: some View {
        CameraPreviewView(session: session)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(CanonColor.hairlineDark, lineWidth: 1)
            )
    }
}

struct SessionControlBarView: View {
    @ObservedObject var recorder: SessionRecorder
    @ObservedObject var micMeter: ShotMicrophoneRecorder

    var body: some View {
        HStack(spacing: 12) {
            switch recorder.phase {
            case .idle:
                EmptyView()
            case .requestingPermissions, .starting, .pausing, .finalizing:
                ProgressView()
                    .controlSize(.small)
                Text(busyLabel)
                    .font(CanonType.interface(12, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
            case .ready:
                readyControls
            case .recording, .paused:
                liveControls
            case .failed:
                failedControls
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .background(CanonColor.sidebar, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderTint.opacity(0.7))
        )
        .fixedSize()
    }

    // MARK: - Ready

    private var readyControls: some View {
        HStack(spacing: 10) {
            recordButton
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready — Not Recording")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text(readyStatusText)
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(2)
            }
            .frame(width: 150, alignment: .leading)
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(width: 1, height: 28)
            toggleButton(
                icon: recorder.faceCamEnabled ? "video.fill" : "video.slash.fill",
                active: recorder.faceCamEnabled,
                help: "Face cam"
            ) {
                recorder.setFaceCamEnabled(!recorder.faceCamEnabled)
            }
            toggleButton(
                icon: recorder.captureMicrophone ? "mic.fill" : "mic.slash.fill",
                active: recorder.captureMicrophone,
                help: "Narration mic"
            ) {
                recorder.setCaptureMicrophoneEnabled(!recorder.captureMicrophone)
            }
            toggleButton(
                icon: recorder.captureSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill",
                active: recorder.captureSystemAudio,
                help: "System audio (app sounds, playback)"
            ) {
                recorder.captureSystemAudio.toggle()
            }
            micLevelBar
            Button {
                recorder.cancelSession()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Cancel session")
        }
    }

    private var recordButton: some View {
        Button {
            recorder.startRecording()
        } label: {
            Label("Start Recording", systemImage: "record.circle")
        }
        .buttonStyle(CanonPrimaryButtonStyle())
        .help("Start recording")
    }

    // MARK: - Recording / paused

    private var liveControls: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(recorder.phase == .recording ? Color(red: 0.86, green: 0.22, blue: 0.18) : CanonColor.brass)
                .frame(width: 10, height: 10)
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                Text(SessionRecordingClock.elapsedLabel(recorder.clock.elapsedSeconds(now: context.date)))
                    .font(CanonType.archive(18, weight: .semibold))
                    .foregroundStyle(recorder.phase == .recording ? CanonColor.bone : CanonColor.brass)
                    .monospacedDigit()
            }
            if recorder.phase == .paused {
                Text("Paused")
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.brass)
            }
            micLevelBar
            Button {
                if recorder.phase == .paused {
                    recorder.resume()
                } else {
                    recorder.pause()
                }
            } label: {
                Label(
                    recorder.phase == .paused ? "Resume" : "Pause",
                    systemImage: recorder.phase == .paused ? "play.fill" : "pause.fill"
                )
            }
            .buttonStyle(CanonUtilityButtonStyle())
            Button {
                recorder.stopAndSave()
            } label: {
                Label("Stop & Save", systemImage: "stop.fill")
            }
            .buttonStyle(CanonPrimaryButtonStyle())
        }
    }

    // MARK: - Failed

    private var failedControls: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CanonColor.rust)
                .padding(.top, 2)
            Text(recorder.status)
                .font(CanonType.interface(11, weight: .medium))
                .foregroundStyle(CanonColor.muted)
                .lineLimit(5)
                .frame(maxWidth: 380, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if recorder.needsScreenPermission {
                Button("Open Settings") {
                    recorder.openScreenRecordingPrivacySettings()
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                Button("Quit LitScenes") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(CanonUtilityButtonStyle())
            }
            if recorder.canSavePartial {
                Button("Save Partial") {
                    recorder.savePartial()
                }
                .buttonStyle(CanonPrimaryButtonStyle())
            }
            Button(recorder.canSavePartial ? "Discard" : "Dismiss") {
                recorder.cancelSession()
            }
            .buttonStyle(CanonUtilityButtonStyle())
        }
    }

    // MARK: - Shared bits

    private func toggleButton(
        icon: String,
        active: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? CanonColor.brass : CanonColor.muted)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(CanonUtilityButtonStyle())
        .help(help)
    }

    @ViewBuilder
    private var micLevelBar: some View {
        if recorder.captureMicrophone {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CanonColor.hairlineDark)
                    Capsule()
                        .fill(CanonColor.olive)
                        .frame(width: max(3, proxy.size.width * micMeter.level))
                }
            }
            .frame(width: 42, height: 5)
            .help("Mic level")
        }
    }

    private var busyLabel: String {
        switch recorder.phase {
        case .requestingPermissions: return "Requesting permissions"
        case .starting: return "Starting"
        case .pausing: return "Pausing"
        case .finalizing: return "Saving to Downloads…"
        default: return ""
        }
    }

    private var readyStatusText: String {
        let scope = recorder.effectiveCaptureScope.title
        if !recorder.faceCamNote.isEmpty { return "\(scope) • \(recorder.faceCamNote)" }
        if !recorder.status.isEmpty { return "\(scope) • \(recorder.status)" }
        let instruction = recorder.faceCamEnabled ? "Position face cam, then Record" : "Ready to record"
        return "\(scope) • \(instruction)"
    }

    private var borderTint: Color {
        switch recorder.phase {
        case .failed: return CanonColor.rust
        case .recording: return Color(red: 0.86, green: 0.22, blue: 0.18)
        case .paused, .finalizing: return CanonColor.brass
        default: return CanonColor.hairlineDark
        }
    }
}

/// The File-menu body. Menu shortcuts only fire while LitScenes is frontmost;
/// the floating control bar is the always-available surface during demos.
struct SessionRecorderCommands: View {
    @ObservedObject var recorder: SessionRecorder

    var body: some View {
        Button(primaryActionTitle) {
            performPrimaryAction()
        }
        .keyboardShortcut("r", modifiers: [.command, .option])
        .disabled(!canPerformPrimaryAction)

        Button("Show Recording Controls") {
            recorder.showControls()
        }
        .disabled(recorder.phase == .idle)

        Button("Cancel Recording Setup") {
            recorder.cancelSession()
        }
        .disabled(recorder.phase != .ready && !(recorder.phase == .failed && !recorder.canSavePartial))

        Button(recorder.phase == .paused ? "Resume Recording" : "Pause Recording") {
            if recorder.phase == .paused {
                recorder.resume()
            } else {
                recorder.pause()
            }
        }
        .keyboardShortcut("p", modifiers: [.command, .option])
        .disabled(recorder.phase != .recording && recorder.phase != .paused)

        Button("Stop & Save Recording") {
            recorder.stopAndSave()
        }
        .keyboardShortcut("r", modifiers: [.command, .option, .shift])
        .disabled(recorder.phase != .recording && recorder.phase != .paused)
    }

    private var primaryActionTitle: String {
        switch recorder.phase {
        case .ready: return "Start Session Recording"
        case .failed where !recorder.canSavePartial: return "Retry Session Setup…"
        default: return "Record Session…"
        }
    }

    private var canPerformPrimaryAction: Bool {
        recorder.phase == .idle
            || recorder.phase == .ready
            || (recorder.phase == .failed && !recorder.canSavePartial)
    }

    private func performPrimaryAction() {
        if recorder.phase == .ready {
            recorder.startRecording()
        } else {
            recorder.beginSession()
        }
    }
}
