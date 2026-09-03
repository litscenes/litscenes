import AppKit
import SwiftUI

@MainActor
final class CaptureOverlayController {
    private var window: NSWindow?

    func show() {
        guard window == nil, let screen = NSScreen.main else { return }
        let overlayWindow = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        overlayWindow.isOpaque = false
        overlayWindow.backgroundColor = .clear
        overlayWindow.ignoresMouseEvents = true
        overlayWindow.level = .floating
        overlayWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlayWindow.contentView = NSHostingView(rootView: RecordingBorderOverlay())
        overlayWindow.orderFrontRegardless()
        window = overlayWindow
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

struct RecordingBorderOverlay: View {
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .stroke(Color.red.opacity(0.9), lineWidth: 1)
                .ignoresSafeArea()
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                Text("Screen Graph")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.72), in: Capsule())
            .padding(.top, 8)
        }
    }
}
