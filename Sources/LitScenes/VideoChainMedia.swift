import AppKit
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum VideoChainMedia {
    static func normalizeImageFrame(
        sourceURL: URL,
        outputURL: URL,
        profile: VideoOutputProfile,
        fitPolicy: VideoFitPolicy
    ) throws -> URL {
        guard let image = NSImage(contentsOf: sourceURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ScreenGraphError.capture("Could not load keyframe image at \(sourceURL.path).")
        }
        let target = CGSize(width: profile.width, height: profile.height)
        guard let context = CGContext(
            data: nil,
            width: profile.width,
            height: profile.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScreenGraphError.capture("Could not create keyframe normalization canvas.")
        }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: target))

        if fitPolicy == .fitWithBlurFill {
            let fillRect = fittedRect(source: CGSize(width: cgImage.width, height: cgImage.height), target: target, mode: .fill)
            context.saveGState()
            context.setAlpha(0.34)
            context.interpolationQuality = .low
            context.draw(cgImage, in: fillRect)
            context.restoreGState()
        }

        let mode: FitMode = fitPolicy == .centerCrop ? .fill : .fit
        let foregroundRect = fittedRect(source: CGSize(width: cgImage.width, height: cgImage.height), target: target, mode: mode)
        context.interpolationQuality = .high
        context.draw(cgImage, in: foregroundRect)
        guard let normalized = context.makeImage() else {
            throw ScreenGraphError.capture("Could not create normalized keyframe image.")
        }
        try ensureDirectory(outputURL.deletingLastPathComponent())
        _ = try writePNG(normalized, to: outputURL)
        return outputURL
    }

    static func extractFinalFrame(videoURL: URL, outputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let visualRange = try await videoTrackTimeRange(asset: asset)
        let seconds = max(
            visualRange.start.seconds,
            CMTimeRangeGetEnd(visualRange).seconds - (1.0 / 24.0)
        )
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        let image = try await generateImage(generator: generator, at: CMTime(seconds: seconds, preferredTimescale: 600))
        try ensureDirectory(outputURL.deletingLastPathComponent())
        _ = try writePNG(image, to: outputURL)
        return outputURL
    }

    /// A frame-exact still at an arbitrary timestamp — used for footage
    /// boundary keyframes, where generated neighbors must hand off on the
    /// clip's true first/last frames (zero tolerance, unlike the poster paths).
    static func extractFrameStill(videoURL: URL, atSeconds seconds: Double, outputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let visualRange = try await videoTrackTimeRange(asset: asset)
        let localSeconds = min(
            max(seconds, 0),
            max(visualRange.duration.seconds - (1.0 / 48.0), 0)
        )
        let clamped = visualRange.start.seconds + localSeconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 1920, height: 1920)
        let image = try await generateImage(generator: generator, at: CMTime(seconds: clamped, preferredTimescale: 600))
        try ensureDirectory(outputURL.deletingLastPathComponent())
        _ = try writePNG(image, to: outputURL)
        return outputURL
    }

    static func extractTailSegment(
        videoURL: URL,
        outputURL: URL,
        durationSeconds requestedDurationSeconds: Double
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let visualRange = try await videoTrackTimeRange(asset: asset)
        let segmentSeconds = max(0.1, min(requestedDurationSeconds, visualRange.duration.seconds))
        let startSeconds = max(visualRange.duration.seconds - segmentSeconds, 0)
        return try await extractTimeRange(
            videoURL: videoURL,
            outputURL: outputURL,
            startSeconds: startSeconds,
            durationSeconds: segmentSeconds
        )
    }

    static func extractTimeRange(
        videoURL: URL,
        outputURL: URL,
        startSeconds: Double,
        durationSeconds: Double
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let visualRange = try await videoTrackTimeRange(asset: asset)
        let visualDuration = max(visualRange.duration.seconds, 0)
        let localStart = min(max(startSeconds, 0), max(visualDuration - 0.1, 0))
        let rangeSeconds = min(max(durationSeconds, 0.1), max(visualDuration - localStart, 0))
        guard rangeSeconds > 0 else {
            throw ScreenGraphError.capture("The requested video range contains no visual frames.")
        }
        let sourceStart = visualRange.start.seconds + localStart
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ScreenGraphError.capture("Could not create video range exporter.")
        }
        try ensureDirectory(outputURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: sourceStart, preferredTimescale: 600),
            duration: CMTime(seconds: rangeSeconds, preferredTimescale: 600)
        )
        try await MediaExportGuard.export(exportSession, to: outputURL, as: .mp4, operation: "clip trim export")
        return outputURL
    }

    /// The visual timeline length. Container duration is not authoritative:
    /// embedded audio commonly extends a few frames past the picture.
    static func videoDurationSeconds(videoURL: URL) async throws -> Double {
        let asset = AVURLAsset(url: videoURL)
        let range = try await videoTrackTimeRange(asset: asset)
        return max(range.duration.seconds, 0)
    }

    /// Produces the canonical silent visual track used by Shot playback/export.
    /// Provider-embedded audio is deliberately omitted because the authored
    /// narration lane is the single audio authority.
    static func stripAudio(videoURL: URL, outputURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let source = try await asset.loadTracks(withMediaType: .video).first else {
            throw ScreenGraphError.capture("The generated media contains no video track.")
        }
        let sourceRange = try await source.load(.timeRange)
        let preferredTransform = try await source.load(.preferredTransform)
        let composition = AVMutableComposition()
        guard let destination = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ScreenGraphError.capture("Could not create the silent Shot video track.")
        }
        try destination.insertTimeRange(sourceRange, of: source, at: .zero)
        destination.preferredTransform = preferredTransform
        try ensureDirectory(outputURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ScreenGraphError.capture("Could not create the silent video exporter.")
        }
        exporter.timeRange = CMTimeRange(start: .zero, duration: sourceRange.duration)
        try await MediaExportGuard.export(exporter, to: outputURL, as: .mp4, operation: "silent clip export")
        return outputURL
    }

    private static func videoTrackTimeRange(asset: AVURLAsset) async throws -> CMTimeRange {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ScreenGraphError.capture("The media contains no video track.")
        }
        let range = try await track.load(.timeRange)
        guard range.isValid, range.duration > .zero else {
            throw ScreenGraphError.capture("The media's video track has no playable duration.")
        }
        return range
    }

    /// How a transition INTO a spec draws its overlap window.
    enum StitchTransitionStyle: Hashable, Sendable {
        /// Paired opacity ramps — outgoing and incoming overlap (the default,
        /// byte-identical to the pre-style stitcher).
        case dissolve
        /// Two SINGLE-layer ramps through the composition's black background:
        /// outgoing 1→0 over the first half of the window, incoming 0→1 over
        /// the second — the clips never overlap on screen.
        case dipThroughBlack
    }

    /// One clip of a stitch/playback assembly. `keepRanges` (clip-local
    /// seconds, ascending) plays exactly those spans — the cut layer's shape;
    /// nil plays the whole clip after the `trimFrames` handoff shave.
    struct StitchClipSpec {
        var url: URL
        var trimFrames: Int = 0
        var keepRanges: [ShotKeepRange]? = nil
        /// Visual-only transition into this spec. The compositor borrows
        /// source handles around the edit and keeps nominal duration fixed.
        var transitionFramesBefore: Int = 0
        /// Read only when `transitionFramesBefore` resolves above zero.
        var transitionStyle: StitchTransitionStyle = .dissolve
        var includeAudio: Bool = true
        /// Playback rate: output duration = source span ÷ rate, applied via
        /// `scaleTimeRange` on the inserted spans (video AND audio). Rated
        /// specs never carry transitions — arrangement seams are hard cuts.
        var rate: Double = 1
    }

    private struct PreparedStitchSpan {
        var sourceAsset: AVURLAsset
        var sourceTrack: AVAssetTrack
        var sourceAudioTrack: AVAssetTrack?
        var sourceAudioTimeRange: CMTimeRange?
        var sourceVideoTimeRange: CMTimeRange
        var sourceRange: CMTimeRange
        var transform: CGAffineTransform
        var requestedTransitionFramesBefore: Int
        var transitionStyle: StitchTransitionStyle
        var includeAudio: Bool
        var rate: Double = 1

        /// Where this span's time lands on the OUTPUT timeline.
        var outputDuration: CMTime {
            guard rate != 1 else { return sourceRange.duration }
            return CMTime(seconds: sourceRange.duration.seconds / rate, preferredTimescale: 600)
        }
    }

    /// The single assembly law behind the stitched export AND the player's
    /// cut-aware preview: inserts each clip's playable spans on one video
    /// track with the profile's fit transform per span. Both surfaces read
    /// the same composition, so what plays is what exports, by construction.
    /// `fadeInFrames`/`fadeOutFrames` ramp the whole picture from/to the
    /// composition's black background at the head/tail — duration-neutral,
    /// clamped into the first/last uncontested instruction.
    static func buildStitchComposition(
        specs: [StitchClipSpec],
        profile: VideoOutputProfile,
        fadeInFrames: Int = 0,
        fadeOutFrames: Int = 0
    ) async throws -> sending (
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        durationSeconds: Double
    ) {
        guard !specs.isEmpty else {
            throw ScreenGraphError.capture("No clips are available to stitch.")
        }
        let composition = AVMutableComposition()
        guard let firstVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let secondVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ScreenGraphError.capture("Could not create video composition tracks.")
        }
        var compositionAudioTrack: AVMutableCompositionTrack?

        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(profile.fps, 1)))
        var spans: [PreparedStitchSpan] = []

        for spec in specs {
            let asset = AVURLAsset(url: spec.url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceTrack = tracks.first else {
                throw ScreenGraphError.capture("Clip has no video track: \(spec.url.lastPathComponent)")
            }
            let sourceVideoTimeRange = try await sourceTrack.load(.timeRange)
            guard sourceVideoTimeRange.isValid, sourceVideoTimeRange.duration > .zero else {
                throw ScreenGraphError.capture("Clip has no playable visual range: \(spec.url.lastPathComponent)")
            }
            let transform = try await renderTransform(for: sourceTrack, profile: profile)
            let sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first
            let sourceAudioTimeRange = try await sourceAudioTrack?.load(.timeRange)
            let visualStart = sourceVideoTimeRange.start.seconds
            let visualDuration = max(sourceVideoTimeRange.duration.seconds, 0)

            let ranges: [CMTimeRange]
            if let keepRanges = spec.keepRanges {
                ranges = keepRanges.compactMap { keep in
                    let localStart = min(max(keep.start, 0), visualDuration)
                    let localEnd = min(max(keep.end, localStart), visualDuration)
                    let rangeDuration = CMTime(seconds: localEnd - localStart, preferredTimescale: 600)
                    guard rangeDuration >= frameDuration else { return nil }
                    return CMTimeRange(
                        start: CMTime(seconds: visualStart + localStart, preferredTimescale: 600),
                        duration: rangeDuration
                    )
                }
            } else {
                let trim = CMTimeMultiply(frameDuration, multiplier: Int32(max(0, spec.trimFrames)))
                let localTrim = min(max(trim.seconds, 0), visualDuration)
                let sourceDuration = CMTime(
                    seconds: max(visualDuration - localTrim, 0),
                    preferredTimescale: 600
                )
                guard sourceDuration >= frameDuration else { continue }
                ranges = [CMTimeRange(
                    start: CMTime(seconds: visualStart + localTrim, preferredTimescale: 600),
                    duration: sourceDuration
                )]
            }

            for (rangeIndex, range) in ranges.enumerated() {
                spans.append(PreparedStitchSpan(
                    sourceAsset: asset,
                    sourceTrack: sourceTrack,
                    sourceAudioTrack: sourceAudioTrack,
                    sourceAudioTimeRange: sourceAudioTimeRange,
                    sourceVideoTimeRange: sourceVideoTimeRange,
                    sourceRange: range,
                    transform: transform,
                    requestedTransitionFramesBefore: rangeIndex == 0 ? max(spec.transitionFramesBefore, 0) : 0,
                    transitionStyle: spec.transitionStyle,
                    includeAudio: spec.includeAudio,
                    rate: spec.rate > 0 ? spec.rate : 1
                ))
            }
        }

        guard !spans.isEmpty else {
            throw ScreenGraphError.capture("The cut layer leaves nothing to play.")
        }

        // Resolve each requested transition against real source handles. A
        // centered transition needs half its duration after the outgoing edit
        // and half before the incoming edit; insufficient handles cap it.
        var transitionFramesBefore = Array(repeating: 0, count: spans.count)
        if spans.count > 1 {
            for index in 1..<spans.count {
                let requested = spans[index].requestedTransitionFramesBefore
                guard requested > 0 else { continue }
                let outgoing = spans[index - 1]
                let incoming = spans[index]
                let outgoingTail = max(
                    CMTimeSubtract(
                        CMTimeRangeGetEnd(outgoing.sourceVideoTimeRange),
                        CMTimeRangeGetEnd(outgoing.sourceRange)
                    ).seconds,
                    0
                )
                let incomingHead = max(
                    CMTimeSubtract(incoming.sourceRange.start, incoming.sourceVideoTimeRange.start).seconds,
                    0
                )
                let maximumSeconds = min(
                    Double(requested) / Double(max(profile.fps, 1)),
                    outgoingTail * 2,
                    incomingHead * 2,
                    outgoing.sourceRange.duration.seconds * 2,
                    incoming.sourceRange.duration.seconds * 2
                )
                transitionFramesBefore[index] = max(
                    Int(floor(maximumSeconds * Double(max(profile.fps, 1)) + 0.000_1)),
                    0
                )
                // Centered transitions stay frame-symmetric. The visible
                // presets are even, but real source handles can cap on an odd
                // boundary; dropping that last frame avoids a one-frame gap
                // or instruction overlap around the nominal edit.
                transitionFramesBefore[index] -= transitionFramesBefore[index] % 2
            }

            // A very short retained sliver can sit between two repaired
            // joins. Cap the later transition so its head does not overlap
            // the earlier transition's tail inside that shared span.
            if spans.count > 2 {
                for index in 1..<(spans.count - 1) {
                    let availableFrames = max(
                        Int(floor(
                            spans[index].sourceRange.duration.seconds
                                * Double(max(profile.fps, 1))
                                + 0.000_1
                        )),
                        0
                    )
                    let consumedByIncoming = transitionFramesBefore[index] / 2
                    let remainingForOutgoing = max(availableFrames - consumedByIncoming, 0)
                    transitionFramesBefore[index + 1] = min(
                        transitionFramesBefore[index + 1],
                        remainingForOutgoing * 2
                    )
                }
            }
        }

        var nominalStarts: [CMTime] = []
        var cursor = CMTime.zero
        for span in spans {
            nominalStarts.append(cursor)
            cursor = CMTimeAdd(cursor, span.outputDuration)
        }

        let videoTracks = [firstVideoTrack, secondVideoTrack]
        for index in spans.indices {
            let span = spans[index]
            let headFrames = index > 0 ? transitionFramesBefore[index] / 2 : 0
            let tailFrames = index + 1 < spans.count ? transitionFramesBefore[index + 1] - transitionFramesBefore[index + 1] / 2 : 0
            let head = CMTimeMultiply(frameDuration, multiplier: Int32(headFrames))
            let tail = CMTimeMultiply(frameDuration, multiplier: Int32(tailFrames))
            let extendedRange = CMTimeRange(
                start: CMTimeSubtract(span.sourceRange.start, head),
                duration: CMTimeAdd(CMTimeAdd(span.sourceRange.duration, head), tail)
            )
            let insertionTime = CMTimeSubtract(nominalStarts[index], head)
            try withExtendedLifetime(span.sourceAsset) {
                try videoTracks[index % 2].insertTimeRange(
                    extendedRange,
                    of: span.sourceTrack,
                    at: insertionTime
                )
                if span.rate != 1 {
                    // Scale in place, immediately after inserting: nothing
                    // later exists on this track yet, and every later span's
                    // insertion time was pre-chained from output durations —
                    // so the scale shifts nothing it shouldn't. Rated spans
                    // carry no transitions, so extendedRange == sourceRange.
                    videoTracks[index % 2].scaleTimeRange(
                        CMTimeRange(start: insertionTime, duration: span.sourceRange.duration),
                        toDuration: span.outputDuration
                    )
                }

                if span.includeAudio, let sourceAudioTrack = span.sourceAudioTrack,
                   let sourceAudioTimeRange = span.sourceAudioTimeRange {
                    let range = span.sourceRange
                    let videoRangeStart = range.start.seconds
                    let videoRangeEnd = CMTimeRangeGetEnd(range).seconds
                    let audioRangeStart = sourceAudioTimeRange.start.seconds
                    let audioRangeEnd = CMTimeRangeGetEnd(sourceAudioTimeRange).seconds
                    let sharedStart = max(videoRangeStart, audioRangeStart)
                    let sharedEnd = min(videoRangeEnd, audioRangeEnd)
                    if sharedEnd - sharedStart >= frameDuration.seconds {
                        if compositionAudioTrack == nil {
                            compositionAudioTrack = composition.addMutableTrack(
                                withMediaType: .audio,
                                preferredTrackID: kCMPersistentTrackID_Invalid
                            )
                        }
                        if let compositionAudioTrack {
                            let sharedRange = CMTimeRange(
                                start: CMTime(seconds: sharedStart, preferredTimescale: 600),
                                duration: CMTime(seconds: sharedEnd - sharedStart, preferredTimescale: 600)
                            )
                            // Source-second offsets land in output seconds
                            // through the same rate the picture scales by.
                            let insertionOffset = CMTime(
                                seconds: (sharedStart - videoRangeStart) / span.rate,
                                preferredTimescale: 600
                            )
                            let audioInsertAt = CMTimeAdd(nominalStarts[index], insertionOffset)
                            try compositionAudioTrack.insertTimeRange(
                                sharedRange,
                                of: sourceAudioTrack,
                                at: audioInsertAt
                            )
                            if span.rate != 1 {
                                compositionAudioTrack.scaleTimeRange(
                                    CMTimeRange(start: audioInsertAt, duration: sharedRange.duration),
                                    toDuration: CMTime(
                                        seconds: sharedRange.duration.seconds / span.rate,
                                        preferredTimescale: 600
                                    )
                                )
                            }
                        }
                    }
                }
            }
        }

        var instructions: [AVMutableVideoCompositionInstruction] = []
        for index in spans.indices {
            let incomingFrames = index > 0 ? transitionFramesBefore[index] : 0
            let outgoingFrames = index + 1 < spans.count ? transitionFramesBefore[index + 1] : 0
            let incomingHead = CMTimeMultiply(frameDuration, multiplier: Int32(incomingFrames / 2))
            let outgoingTail = CMTimeMultiply(
                frameDuration,
                multiplier: Int32(outgoingFrames - outgoingFrames / 2)
            )
            let singleStart = CMTimeAdd(nominalStarts[index], incomingHead)
            let singleEnd = CMTimeSubtract(
                CMTimeAdd(nominalStarts[index], spans[index].outputDuration),
                outgoingTail
            )
            if singleEnd > singleStart {
                let instruction = AVMutableVideoCompositionInstruction()
                instruction.timeRange = CMTimeRange(
                    start: singleStart,
                    duration: CMTimeSubtract(singleEnd, singleStart)
                )
                let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTracks[index % 2])
                layer.setTransform(spans[index].transform, at: singleStart)
                // Whole-composition head/tail fades: ramps against the black
                // background inside the first/last single-layer instruction.
                // A one-span composition shares that instruction, so each
                // fade caps at half of it. After a ramp, opacity persists at
                // the ramp's end value — the head ends at 1, the tail at 0.
                let instructionSeconds = CMTimeSubtract(singleEnd, singleStart).seconds
                let sharesInstruction = spans.count == 1 && fadeInFrames > 0 && fadeOutFrames > 0
                if index == 0, fadeInFrames > 0 {
                    let seconds = min(
                        Double(fadeInFrames) / Double(max(profile.fps, 1)),
                        sharesInstruction ? instructionSeconds / 2 : instructionSeconds
                    )
                    if seconds > 0 {
                        layer.setOpacityRamp(
                            fromStartOpacity: 0,
                            toEndOpacity: 1,
                            timeRange: CMTimeRange(
                                start: singleStart,
                                duration: CMTime(seconds: seconds, preferredTimescale: 600)
                            )
                        )
                    }
                }
                if index == spans.count - 1, fadeOutFrames > 0 {
                    let seconds = min(
                        Double(fadeOutFrames) / Double(max(profile.fps, 1)),
                        sharesInstruction ? instructionSeconds / 2 : instructionSeconds
                    )
                    if seconds > 0 {
                        let rampDuration = CMTime(seconds: seconds, preferredTimescale: 600)
                        layer.setOpacityRamp(
                            fromStartOpacity: 1,
                            toEndOpacity: 0,
                            timeRange: CMTimeRange(
                                start: CMTimeSubtract(singleEnd, rampDuration),
                                duration: rampDuration
                            )
                        )
                    }
                }
                instruction.layerInstructions = [layer]
                instructions.append(instruction)
            }

            guard index + 1 < spans.count, outgoingFrames > 0 else { continue }
            let transitionDuration = CMTimeMultiply(frameDuration, multiplier: Int32(outgoingFrames))
            let transitionStart = CMTimeSubtract(
                nominalStarts[index + 1],
                CMTimeMultiply(frameDuration, multiplier: Int32(outgoingFrames / 2))
            )
            let transitionRange = CMTimeRange(start: transitionStart, duration: transitionDuration)
            if spans[index + 1].transitionStyle == .dipThroughBlack {
                // THE DIP: no overlap drawn — each side ramps alone against
                // the composition's black background, half the window each.
                // Frames are even by the symmetry law above, so the halves
                // meet exactly at the nominal edit.
                let halfDuration = CMTimeMultiply(frameDuration, multiplier: Int32(outgoingFrames / 2))
                let outgoingLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTracks[index % 2])
                outgoingLayer.setTransform(spans[index].transform, at: transitionStart)
                outgoingLayer.setOpacityRamp(
                    fromStartOpacity: 1,
                    toEndOpacity: 0,
                    timeRange: CMTimeRange(start: transitionStart, duration: halfDuration)
                )
                let outgoingInstruction = AVMutableVideoCompositionInstruction()
                outgoingInstruction.timeRange = CMTimeRange(start: transitionStart, duration: halfDuration)
                outgoingInstruction.layerInstructions = [outgoingLayer]
                instructions.append(outgoingInstruction)

                let incomingStart = CMTimeAdd(transitionStart, halfDuration)
                let incomingRange = CMTimeRange(
                    start: incomingStart,
                    duration: CMTimeSubtract(transitionDuration, halfDuration)
                )
                let incomingLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTracks[(index + 1) % 2])
                incomingLayer.setTransform(spans[index + 1].transform, at: incomingStart)
                incomingLayer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: incomingRange)
                let incomingInstruction = AVMutableVideoCompositionInstruction()
                incomingInstruction.timeRange = incomingRange
                incomingInstruction.layerInstructions = [incomingLayer]
                instructions.append(incomingInstruction)
                continue
            }
            let outgoingLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTracks[index % 2])
            outgoingLayer.setTransform(spans[index].transform, at: transitionStart)
            outgoingLayer.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: transitionRange)
            let incomingLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTracks[(index + 1) % 2])
            incomingLayer.setTransform(spans[index + 1].transform, at: transitionStart)
            incomingLayer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: transitionRange)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = transitionRange
            instruction.layerInstructions = [incomingLayer, outgoingLayer]
            instructions.append(instruction)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: profile.width, height: profile.height)
        videoComposition.frameDuration = frameDuration
        videoComposition.instructions = instructions.sorted {
            $0.timeRange.start < $1.timeRange.start
        }
        return (composition, videoComposition, cursor.seconds)
    }

    /// `perClipTrimFrames` overrides the uniform duplicate-start trim per clip
    /// index (seam-aware callers: 0 after hard cuts so real footage keeps its
    /// first frames, 3 after keyframe handoffs). Index 0 is never trimmed.
    static func stitchClips(
        clipURLs: [URL],
        outputURL: URL,
        workDirectory: URL,
        profile: VideoOutputProfile,
        trimDuplicateStartFrames: Int = 3,
        perClipTrimFrames: [Int]? = nil
    ) async throws -> URL {
        guard !clipURLs.isEmpty else {
            throw ScreenGraphError.capture("No clips are available to stitch.")
        }
        try ensureDirectory(workDirectory)
        try ensureDirectory(outputURL.deletingLastPathComponent())
        let specs = clipURLs.enumerated().map { index, url in
            let trimFrames: Int
            if index == 0 {
                trimFrames = 0
            } else if let perClipTrimFrames, perClipTrimFrames.indices.contains(index) {
                trimFrames = perClipTrimFrames[index]
            } else {
                trimFrames = trimDuplicateStartFrames
            }
            return StitchClipSpec(url: url, trimFrames: max(0, trimFrames))
        }
        let built = try await buildStitchComposition(specs: specs, profile: profile)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        guard let exportSession = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ScreenGraphError.capture("Could not create stitched video exporter.")
        }
        exportSession.videoComposition = built.videoComposition
        exportSession.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: built.durationSeconds, preferredTimescale: 600)
        )
        try await MediaExportGuard.export(exportSession, to: outputURL, as: .mp4, operation: "render stitch")
        return outputURL
    }

    private static func renderTransform(for track: AVAssetTrack, profile: VideoOutputProfile) async throws -> CGAffineTransform {
        let naturalSize = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferred)
        let orientedSize = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))
        let target = CGSize(width: profile.width, height: profile.height)
        let scale: CGFloat
        switch profile.fitPolicy {
        case .centerCrop:
            scale = max(target.width / max(orientedSize.width, 1), target.height / max(orientedSize.height, 1))
        case .fitWithBlurFill, .fitWithBlackBars:
            scale = min(target.width / max(orientedSize.width, 1), target.height / max(orientedSize.height, 1))
        }
        let scaledSize = CGSize(width: orientedSize.width * scale, height: orientedSize.height * scale)
        let dx = (target.width - scaledSize.width) / 2
        let dy = (target.height - scaledSize.height) / 2
        return preferred
            .concatenating(CGAffineTransform(translationX: -orientedRect.minX, y: -orientedRect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: dx, y: dy))
    }

    private static func generateImage(generator: AVAssetImageGenerator, at time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { image, _, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? ScreenGraphError.capture("Could not extract video frame."))
                }
            }
        }
    }

    private static func fittedRect(source: CGSize, target: CGSize, mode: FitMode) -> CGRect {
        let sourceWidth = max(source.width, 1)
        let sourceHeight = max(source.height, 1)
        let scale: CGFloat = mode == .fill
            ? max(target.width / sourceWidth, target.height / sourceHeight)
            : min(target.width / sourceWidth, target.height / sourceHeight)
        let width = sourceWidth * scale
        let height = sourceHeight * scale
        return CGRect(
            x: (target.width - width) / 2,
            y: (target.height - height) / 2,
            width: width,
            height: height
        )
    }

    private enum FitMode {
        case fit
        case fill
    }
}
