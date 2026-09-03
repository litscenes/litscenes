import AppKit
import SwiftUI

@main
struct LitScenesApp: App {
    private static let activationDelays: [TimeInterval] = [0.05, 0.2, 0.5, 1.0]

    @StateObject private var engine = RecorderEngine()
    @StateObject private var library = LibraryEngine()
    @StateObject private var sessionRecorder = SessionRecorder()
    @NSApplicationDelegateAdaptor(SessionAppDelegate.self) private var sessionAppDelegate
    private let overlay = CaptureOverlayController()

    init() {
        CanonFontRegistration.registerBundledFonts()
        NSApplication.shared.setActivationPolicy(.regular)
        if !LitScenesReleaseIdentity.current.usesOfficialBranding {
            NSApplication.shared.applicationIconImage = LitScenesAppIcon.image()
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            LibraryRootView(library: library, recorder: engine, sessionRecorder: sessionRecorder)
                .frame(minWidth: 1180, idealWidth: 1360, minHeight: 760, idealHeight: 860)
                .onAppear {
                    sessionAppDelegate.sessionRecorder = sessionRecorder
                    activateMainWindow()
                }
                .onChange(of: engine.isRecording) { _, isRecording in
                    if isRecording {
                        overlay.show()
                    } else {
                        overlay.hide()
                    }
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                SessionRecorderCommands(recorder: sessionRecorder)
            }
            LitScenesLicensingCommands()
        }

        Window("Licensing & Source", id: "licensing-source") {
            LicensingSourceView()
        }
    }

    private func activateMainWindow(attempt: Int = 0) {
        let delay = Self.activationDelays[min(attempt, Self.activationDelays.count - 1)]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)

            guard let window = primaryContentWindow() else {
                if attempt + 1 < Self.activationDelays.count {
                    activateMainWindow(attempt: attempt + 1)
                }
                return
            }

            app.activate(ignoringOtherApps: true)
            position(window)
            window.makeKeyAndOrderFront(nil)
            app.activate(ignoringOtherApps: true)

            if !window.isKeyWindow, attempt + 1 < Self.activationDelays.count {
                activateMainWindow(attempt: attempt + 1)
            }
        }
    }

    private func position(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        // Open maximized to the usable screen area (menu bar + Dock excluded) —
        // the largest windowed size, never true fullscreen.
        window.setFrame(screen.visibleFrame, display: true, animate: true)
    }
}

@MainActor
private func primaryContentWindow() -> NSWindow? {
    let windows = NSApplication.shared.windows.filter { !$0.isMiniaturized && $0.isVisible }
    return windows.first { window in
        window.styleMask.contains(.titled) && window.canBecomeKey
    } ?? windows.first { window in
        window.canBecomeKey && !window.ignoresMouseEvents
    }
}
