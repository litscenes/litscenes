import AppKit
import SwiftUI

/// Trackpad pan + pinch for the sound editor's lane area.
///
/// The catcher is an overlay whose NSView answers `hitTest` with nil, so it
/// NEVER enters click routing — the Canvas drag gestures and the same-box
/// law (`ShotTimelineWaveformView`) are untouched. Events arrive through a
/// LOCAL NSEvent monitor instead, geometrically gated to this view's own
/// frame in its own window:
/// - horizontal-dominant scroll → `onPan(points)` and the event is consumed;
/// - vertical scroll passes through untouched, so the lane area's vertical
///   ScrollView keeps scrolling;
/// - pinch → `onMagnify(factor, localX)` for cursor-anchored zoom.
struct ShotTimelinePanZoomCatcher: NSViewRepresentable {
    /// Horizontal pan in on-screen points; positive = later in time (the
    /// natural-scrolling direction is resolved before this fires).
    var onPan: (CGFloat) -> Void
    /// (zoom factor for this event, cursor x in the catcher's local space).
    var onMagnify: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> ShotTimelinePanZoomCatcherView {
        let view = ShotTimelinePanZoomCatcherView()
        view.onPan = onPan
        view.onMagnify = onMagnify
        return view
    }

    func updateNSView(_ view: ShotTimelinePanZoomCatcherView, context: Context) {
        view.onPan = onPan
        view.onMagnify = onMagnify
    }
}

final class ShotTimelinePanZoomCatcherView: NSView {
    var onPan: ((CGFloat) -> Void)?
    var onMagnify: ((CGFloat, CGFloat) -> Void)?
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self else { return event }
            return self.consumed(event) ? nil : event
        }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func consumed(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        let localPoint = convert(event.locationInWindow, from: nil)
        guard bounds.contains(localPoint) else { return false }
        switch event.type {
        case .scrollWheel:
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            // Vertical-dominant scroll belongs to the enclosing ScrollView.
            guard abs(dx) > abs(dy), abs(dx) > 0.01 else { return false }
            // Natural scrolling: fingers left (dx < 0) pulls later material
            // into view, i.e. the window pans later.
            onPan?(-dx)
            return true
        case .magnify:
            onMagnify?(1 + event.magnification, localPoint.x)
            return true
        default:
            return false
        }
    }
}
