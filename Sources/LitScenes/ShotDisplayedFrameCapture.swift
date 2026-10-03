import AppKit
@preconcurrency import AVFoundation
import CoreImage
import CryptoKit

/// Pixel payload from the active item, including its composition and retiming.
struct ShotDisplayedFrame: Sendable {
    let pngData: Data
    let outputSeconds: Double
    let sourcePath: String
    let pixelIdentity: String
}

@MainActor
final class ShotDisplayedFrameCapture {
    private weak var item: AVPlayerItem?
    private var output: AVPlayerItemVideoOutput?
    private var transform = CGAffineTransform.identity
    private var seekRevision = 0
    private var isSeeking = false

    func attach(to item: AVPlayerItem) async throws {
        detach()
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        self.item = item
        self.output = output
        item.seekingWaitsForVideoCompositionRendering = true
        if item.videoComposition == nil,
           let track = try await item.asset.loadTracks(withMediaType: .video).first {
            transform = try await track.load(.preferredTransform)
        }
        item.add(output)
    }

    func detach() {
        if let output { item?.remove(output) }
        item = nil
        output = nil
        transform = .identity
        seekRevision += 1
        isSeeking = false
    }

    func seek(_ player: AVPlayer, to time: CMTime) {
        seekRevision += 1
        let revision = seekRevision
        isSeeking = true
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.seekRevision == revision else { return }
                self.isSeeking = !finished
            }
        }
    }

    func capture(player: AVPlayer, sourcePath: String) async -> ShotDisplayedFrame? {
        player.pause()
        guard !isSeeking, let item, player.currentItem === item,
              item.status == .readyToPlay, let output else { return nil }
        var requestedTime = player.currentTime()
        guard requestedTime.isValid, requestedTime.seconds.isFinite else { return nil }
        let boundary = item.forwardPlaybackEndTime.isValid && item.forwardPlaybackEndTime.seconds.isFinite && item.forwardPlaybackEndTime.seconds > 0
            ? item.forwardPlaybackEndTime : item.duration
        let hasBoundary = boundary.isValid && boundary.seconds.isFinite && boundary.seconds > 0
        if hasBoundary && requestedTime >= boundary {
            // End times are exclusive. Query the final representable instant of
            // this output, without guessing a frame rate or extracting a source.
            let preciseEnd = CMTimeConvertScale(boundary, timescale: 1_000_000_000, method: .roundTowardZero)
            requestedTime = CMTimeSubtract(preciseEnd, CMTime(value: 1, timescale: 1_000_000_000))
            if let composition = item.videoComposition {
                // A composition declares its actual output sample grid. At its
                // exclusive end, settle on that grid's last frame; some Apple
                // compositors otherwise expose the following source sample.
                let interval = composition.frameDuration
                guard interval.isValid, interval.seconds.isFinite, interval.seconds > 0 else { return nil }
                let frameIndex = floor(requestedTime.seconds / interval.seconds)
                guard frameIndex >= 0, frameIndex < Double(Int32.max) else { return nil }
                requestedTime = CMTimeMultiply(interval, multiplier: Int32(frameIndex))
                seekRevision += 1
                let revision = seekRevision
                isSeeking = true
                let finished = await player.seek(to: requestedTime, toleranceBefore: .zero, toleranceAfter: .zero)
                guard seekRevision == revision, self.item === item, player.currentItem === item else { return nil }
                isSeeking = false
                guard finished else { return nil }
            }
        }
        let revision = seekRevision
        let pausedTime = player.currentTime()
        var displayedTime = CMTime.invalid
        // Ask the active output for its displayed sample. No source extraction,
        // frame-rate estimate, or old-item buffer may substitute for these pixels.
        var capturedBuffer: CVPixelBuffer?
        for attempt in 0..<10 {
            guard seekRevision == revision, !isSeeking, self.item === item, player.currentItem === item,
                  player.rate == 0, player.currentTime() == pausedTime else { return nil }
            capturedBuffer = output.copyPixelBuffer(forItemTime: requestedTime, itemTimeForDisplay: &displayedTime)
            if capturedBuffer != nil, displayedTime.isValid, displayedTime.seconds.isFinite,
               !hasBoundary || displayedTime < boundary { break }
            capturedBuffer = nil
            if attempt < 9 { try? await Task.sleep(for: .milliseconds(25)) }
        }
        guard let buffer = capturedBuffer else { return nil }
        let image = CIImage(cvPixelBuffer: buffer).transformed(by: transform)
        guard let cgImage = CIContext().createCGImage(image, from: image.extent),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { return nil }
        return ShotDisplayedFrame(
            pngData: png,
            outputSeconds: max(displayedTime.seconds, 0),
            sourcePath: sourcePath,
            pixelIdentity: SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        )
    }
}
