import AppKit
import AVFoundation
import SwiftUI

// Shared scrub-and-trim building blocks used by the Moodboard Video Studio
// and the SHOTS Clip Inspector.

/// The Trim mode's range scrubber AND frame navigator: the video's filmstrip
/// with draggable in/out handles, dimmed outside the selection. Click or drag
/// anywhere else on the strip to move the playhead marker.
struct TrimRangeBar: View {
    let stripPath: String?
    let durationSeconds: Double
    @Binding var startSeconds: Double
    @Binding var endSeconds: Double
    let playheadSeconds: Double
    var onScrub: (Double) -> Void = { _ in }

    private let handleWidth: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = geometry.size.height
            let startX = xPosition(for: startSeconds, width: width)
            let endX = xPosition(for: endSeconds, width: width)

            ZStack(alignment: .topLeading) {
                stripBackground(width: width, height: height)

                Rectangle()
                    .fill(CanonColor.room.opacity(0.74))
                    .frame(width: max(startX, 0), height: height)
                Rectangle()
                    .fill(CanonColor.room.opacity(0.74))
                    .frame(width: max(width - endX, 0), height: height)
                    .offset(x: endX)

                Rectangle()
                    .stroke(CanonColor.brass, lineWidth: 1.5)
                    .frame(width: max(endX - startX, 1), height: height)
                    .offset(x: startX)

                playheadMarker(atX: xPosition(for: playheadSeconds, width: width), height: height)
                    .allowsHitTesting(false)

                handle(atX: startX - handleWidth / 2, height: height) { locationX in
                    startSeconds = min(seconds(forX: locationX, width: width), endSeconds)
                }
                handle(atX: endX - handleWidth / 2, height: height) { locationX in
                    endSeconds = max(seconds(forX: locationX, width: width), startSeconds)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CanonColor.hairlineDark)
            )
            .coordinateSpace(name: "videoTrimBar")
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("videoTrimBar"))
                    .onChanged { value in
                        onScrub(seconds(forX: value.location.x, width: width))
                    }
            )
        }
    }

    /// The current-frame marker: a bright caret + line that stays legible over
    /// any filmstrip content (the old hairline was invisible).
    private func playheadMarker(atX x: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .frame(width: 5, height: height)
            Rectangle()
                .fill(CanonColor.bone)
                .frame(width: 2.5, height: height)
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(CanonColor.bone)
                .shadow(color: .black.opacity(0.8), radius: 1)
                .offset(y: -1)
        }
        .frame(width: 12, height: height, alignment: .top)
        .offset(x: x - 6)
    }

    private func handle(atX x: CGFloat, height: CGFloat, onDrag: @escaping (CGFloat) -> Void) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(CanonColor.brass)
            .frame(width: handleWidth, height: height)
            .overlay(
                Rectangle()
                    .fill(CanonColor.room.opacity(0.55))
                    .frame(width: 1.5, height: height * 0.4)
            )
            .offset(x: x)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("videoTrimBar"))
                    .onChanged { value in
                        onDrag(value.location.x)
                    }
            )
    }

    @ViewBuilder
    private func stripBackground(width: CGFloat, height: CGFloat) -> some View {
        // Through the decode cache — a raw NSImage(contentsOfFile:) here
        // re-decoded the strip JPEG on every SwiftUI pass.
        if let stripPath, let image = StripThumbnailCache.shared.image(path: stripPath, maxPixel: 1600) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipped()
        } else {
            Rectangle()
                .fill(CanonColor.mediaCardHover)
                .frame(width: width, height: height)
        }
    }

    private func xPosition(for seconds: Double, width: CGFloat) -> CGFloat {
        guard durationSeconds > 0 else { return 0 }
        let fraction = min(max(seconds / durationSeconds, 0), 1)
        return CGFloat(fraction) * width
    }

    private func seconds(forX x: CGFloat, width: CGFloat) -> Double {
        let fraction = min(max(Double(x / width), 0), 1)
        return fraction * durationSeconds
    }
}

/// The Studio's foreground player: a clear-background AVPlayerLayer host so
/// aspect-fit letterbox regions show whatever sits BEHIND it (the portrait
/// blur-fill backdrop) instead of AVPlayerView's opaque bars. Supports the
/// Trim mode's [in, out] loop preview.
struct ScrubVideoPreview: NSViewRepresentable {
    let path: String
    @Binding var timestampSeconds: Double
    var loopRange: ClosedRange<Double>? = nil
    var isLoopPlaying: Bool = false
    /// Free playback (the transport play/pause), exclusive with loop preview.
    var isFreePlaying: Bool = false
    /// Reports live playback time while playing (loop or free) so the
    /// playhead marker tracks honestly instead of freezing.
    var onPlaybackTime: ((Double) -> Void)? = nil
    /// Free playback ran off the end of the video.
    var onPlaybackEnded: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(path: path)
    }

    func makeNSView(context: Context) -> ScrubPlayerHostView {
        let view = ScrubPlayerHostView()
        context.coordinator.attach(to: view, path: path)
        context.coordinator.onPlaybackTime = onPlaybackTime
        context.coordinator.onPlaybackEnded = onPlaybackEnded
        context.coordinator.seek(to: timestampSeconds)
        return view
    }

    func updateNSView(_ nsView: ScrubPlayerHostView, context: Context) {
        if context.coordinator.path != path {
            context.coordinator.attach(to: nsView, path: path)
        }
        context.coordinator.onPlaybackTime = onPlaybackTime
        context.coordinator.onPlaybackEnded = onPlaybackEnded
        context.coordinator.updateLoop(range: loopRange, isPlaying: isLoopPlaying)
        context.coordinator.updateFreePlay(isPlaying: isFreePlaying, fromSeconds: timestampSeconds)
        if !isLoopPlaying && !isFreePlaying {
            context.coordinator.seek(to: timestampSeconds)
        }
    }

    static func dismantleNSView(_ nsView: ScrubPlayerHostView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator {
        var path: String
        var onPlaybackTime: ((Double) -> Void)?
        var onPlaybackEnded: (() -> Void)?
        private var player: AVPlayer?
        private var lastSeekSeconds: Double?
        private var boundaryObserver: Any?
        private var periodicObserver: Any?
        private var endObserver: NSObjectProtocol?
        private var observedRange: ClosedRange<Double>?
        private var isLooping = false
        private var isFreePlaying = false

        nonisolated init(path: String) {
            self.path = path
        }

        func attach(to view: ScrubPlayerHostView, path: String) {
            removeBoundaryObserver()
            removePeriodicObserver()
            removeEndObserver()
            player?.pause()
            let player = AVPlayer(url: URL(fileURLWithPath: path))
            player.isMuted = true
            player.pause()
            self.path = path
            self.player = player
            lastSeekSeconds = nil
            isLooping = false
            isFreePlaying = false
            view.playerLayer.player = player
            endObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.didPlayToEndTimeNotification,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handlePlaybackEnded()
                }
            }
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
                installPeriodicObserver()
                restartLoopFromStart()
            } else {
                if !isFreePlaying {
                    removePeriodicObserver()
                    player.pause()
                }
                // Force the next scrub-seek to land even if the binding value
                // hasn't changed — playback moved the player under it.
                lastSeekSeconds = nil
            }
        }

        /// Transport play/pause: plays from `fromSeconds` (seeking first only
        /// when the player sits elsewhere), pauses in place on stop.
        func updateFreePlay(isPlaying: Bool, fromSeconds: Double) {
            guard let player else { return }
            // Reconcile against the player's real state, not just the mirrored
            // flag: if the two ever disagree, trusting the flag alone would
            // make play a permanent silent no-op while seeking kept working.
            // `.waitingToPlayAtSpecifiedRate` counts as running (it is buffering
            // toward playback), and the loop preview drives the player on its
            // own — don't fight it.
            let playerIsRunning = player.timeControlStatus != .paused
            let alreadyInRequestedState = isPlaying == isFreePlaying
                && (isLooping || playerIsRunning == isPlaying)
            guard !alreadyInRequestedState else { return }
            isFreePlaying = isPlaying
            if isPlaying {
                installPeriodicObserver()
                let current = player.currentTime().seconds
                if current.isFinite, abs(current - fromSeconds) > 0.05 {
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
                if !isLooping {
                    removePeriodicObserver()
                }
                player.pause()
                // Playback moved the player under the binding — let the next
                // scrub-seek land even on an unchanged value.
                lastSeekSeconds = nil
            }
        }

        func teardown() {
            removeBoundaryObserver()
            removePeriodicObserver()
            removeEndObserver()
            player?.pause()
            player = nil
        }

        private func handlePlaybackEnded() {
            if isLooping {
                restartLoopFromStart()
                return
            }
            guard isFreePlaying else { return }
            isFreePlaying = false
            removePeriodicObserver()
            lastSeekSeconds = nil
            onPlaybackEnded?()
        }

        private func installPeriodicObserver() {
            guard periodicObserver == nil, let player else { return }
            periodicObserver = player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
                queue: .main
            ) { [weak self] time in
                Task { @MainActor [weak self] in
                    guard let self, self.isLooping || self.isFreePlaying else { return }
                    self.onPlaybackTime?(time.seconds)
                }
            }
        }

        private func removePeriodicObserver() {
            if let periodicObserver {
                player?.removeTimeObserver(periodicObserver)
            }
            periodicObserver = nil
        }

        private func removeEndObserver() {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            endObserver = nil
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

final class ScrubPlayerHostView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
