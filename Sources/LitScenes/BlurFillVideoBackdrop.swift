import AppKit
import AVFoundation
import SwiftUI

/// A muted, blurred, dimmed copy of a video meant to sit BEHIND an aspect-fit
/// player on a 16:9 canvas — the "low fidelity moving background" treatment for
/// portrait footage. Owns its own AVPlayer (a shared player only guarantees
/// rendering into its most recently attached layer) and mirrors the foreground
/// player's scrub position and loop playback; under the blur, small drift is
/// invisible.
struct BlurFillVideoBackdropView: NSViewRepresentable {
    let path: String
    var timestampSeconds: Double = 0
    var loopRange: ClosedRange<Double>? = nil
    var isLoopPlaying: Bool = false
    /// Mirrors the foreground transport's free playback.
    var isFreePlaying: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(path: path)
    }

    func makeNSView(context: Context) -> BlurFillBackdropNSView {
        let view = BlurFillBackdropNSView()
        context.coordinator.attach(to: view, path: path)
        context.coordinator.seek(to: timestampSeconds)
        return view
    }

    func updateNSView(_ nsView: BlurFillBackdropNSView, context: Context) {
        if context.coordinator.path != path {
            context.coordinator.attach(to: nsView, path: path)
        }
        context.coordinator.updateLoop(range: loopRange, isPlaying: isLoopPlaying)
        context.coordinator.updateFreePlay(isPlaying: isFreePlaying, fromSeconds: timestampSeconds)
        if !isLoopPlaying && !isFreePlaying {
            context.coordinator.seek(to: timestampSeconds)
        }
    }

    static func dismantleNSView(_ nsView: BlurFillBackdropNSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator {
        var path: String
        private var player: AVPlayer?
        private var lastSeekSeconds: Double?
        private var boundaryObserver: Any?
        private var observedRange: ClosedRange<Double>?
        private var isLooping = false
        private var isFreePlaying = false

        nonisolated init(path: String) {
            self.path = path
        }

        func attach(to view: BlurFillBackdropNSView, path: String) {
            removeBoundaryObserver()
            player?.pause()
            let item = AVPlayerItem(url: URL(fileURLWithPath: path))
            // The backdrop is blurred anyway — cap decode resolution so a 4K
            // source doesn't cost a second full-size decode session.
            item.preferredMaximumResolution = CGSize(width: 640, height: 640)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.pause()
            self.path = path
            self.player = player
            lastSeekSeconds = nil
            observedRange = nil
            isLooping = false
            isFreePlaying = false
            view.playerLayer.player = player
        }

        func seek(to seconds: Double) {
            guard let player else { return }
            guard lastSeekSeconds.map({ abs($0 - seconds) > 0.01 }) ?? true else { return }
            lastSeekSeconds = seconds
            player.pause()
            player.seek(
                to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }

        func updateLoop(range: ClosedRange<Double>?, isPlaying: Bool) {
            guard let player else { return }
            if observedRange != range {
                removeBoundaryObserver()
                observedRange = range
                if let range {
                    let boundary = NSValue(time: CMTime(seconds: range.upperBound, preferredTimescale: 600))
                    boundaryObserver = player.addBoundaryTimeObserver(forTimes: [boundary], queue: .main) { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.restartLoopFromStart()
                        }
                    }
                }
            }
            guard isPlaying != isLooping else { return }
            isLooping = isPlaying
            if isPlaying, range != nil {
                lastSeekSeconds = nil
                restartLoopFromStart()
            } else if !isFreePlaying {
                player.pause()
                if let range {
                    lastSeekSeconds = range.lowerBound
                    player.seek(
                        to: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    )
                }
            }
        }

        /// Mirrors the foreground transport: play from `fromSeconds` (seeking
        /// first only when parked elsewhere), pause in place on stop. Under
        /// the blur, minor drift against the foreground is invisible.
        func updateFreePlay(isPlaying: Bool, fromSeconds: Double) {
            guard let player else { return }
            // Same reconciliation as the foreground player: converge on the
            // player's real state so a stale mirror flag can't strand the
            // backdrop paused under a moving foreground.
            let playerIsRunning = player.timeControlStatus != .paused
            let alreadyInRequestedState = isPlaying == isFreePlaying
                && (isLooping || playerIsRunning == isPlaying)
            guard !alreadyInRequestedState else { return }
            isFreePlaying = isPlaying
            if isPlaying {
                let current = player.currentTime().seconds
                if current.isFinite, abs(current - fromSeconds) > 0.05 {
                    lastSeekSeconds = nil
                    player.seek(
                        to: CMTime(seconds: max(fromSeconds, 0), preferredTimescale: 600),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    ) { [weak self] _ in
                        Task { @MainActor [weak self] in
                            guard let self, self.isFreePlaying else { return }
                            self.player?.play()
                        }
                    }
                } else {
                    player.play()
                }
            } else {
                player.pause()
                // Playback moved the player under the mirrored timestamp —
                // let the next seek land even on an unchanged value.
                lastSeekSeconds = nil
            }
        }

        func teardown() {
            removeBoundaryObserver()
            player?.pause()
            player = nil
        }

        private func restartLoopFromStart() {
            guard isLooping, let range = observedRange else { return }
            player?.seek(
                to: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isLooping else { return }
                    self.player?.play()
                }
            }
        }

        private func removeBoundaryObserver() {
            if let boundaryObserver {
                player?.removeTimeObserver(boundaryObserver)
            }
            boundaryObserver = nil
            observedRange = nil
        }
    }
}

/// Layer-backed host: an aspect-fill player layer blurred via Core Image (the
/// view MUST set `layerUsesCoreImageFilters`, or the filter silently no-ops on
/// macOS) under a dim scrim, overscanned so the blur's edge fringe falls
/// outside the clipped bounds.
final class BlurFillBackdropNSView: NSView {
    let playerLayer = AVPlayerLayer()
    private let dimLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        if let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 36]) {
            blur.name = "backdropBlur"
            playerLayer.filters = [blur]
        }
        dimLayer.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        layer?.addSublayer(playerLayer)
        layer?.addSublayer(dimLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds.insetBy(dx: -bounds.width * 0.1, dy: -bounds.height * 0.1)
        dimLayer.frame = bounds
        CATransaction.commit()
    }
}
