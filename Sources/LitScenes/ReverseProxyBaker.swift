import AVFoundation
import CoreMedia
import Foundation
import VideoToolbox

/// How far a bake has got. Phases are ordered and their fractions are local to
/// the phase, not to the whole bake.
struct ReverseProxyBakeProgress: Sendable {
    enum Phase: Sendable {
        case indexing
        case reversingPicture
        case reversingAudio
        case verifying
    }

    var phase: Phase
    var fraction: Double
}

struct ReverseProxyBakeResult: Sendable {
    var fileURL: URL
    /// The source's VISUAL-track duration — the mirror law's `D`, and the only
    /// number the pure transform may reflect kept spans about.
    var sourceDurationSeconds: Double
    /// Measured back off the written file rather than assumed from the source.
    var proxyDurationSeconds: Double
    var frameCount: Int
    var hasReversedAudio: Bool
    var bakerVersion: Int
    /// True when the hardware encoder stalled and the bake completed on the
    /// software encoder instead (THE ENCODER FALLBACK LAW).
    var usedSoftwareEncoder: Bool = false
}

/// Writes a frame-exact reversed copy of a clip.
///
/// AVFoundation cannot play a composition backwards, so a reversed CUT plays by
/// pointing each span at one of these instead. Everything downstream then stays
/// direction-blind: the stitcher plays the proxy forward, and the file is
/// already backwards.
///
/// The whole design is one formula. With visual presentation stamps
/// `p₀ < … < p_{N-1}` measured from the video track's start and the sentinel
/// `p_N := D`, reversed frame `j` shows source frame `i = N-1-j` at
///
///     PTS_out(j)      = D - p_{i+1}
///     duration_out(j) = p_{i+1} - p_i
///
/// so `PTS_out(0) = 0`, the last frame ends exactly at `D`, and frame count,
/// per-frame durations, and total duration are all preserved — variable frame
/// rate included. `mirroredKeepRange` reflects about the same `D`, which is why
/// the picture and the kept spans cannot drift apart.
enum ReverseProxyBaker {
    /// Bump on ANY change to the codec settings, the PTS law, or the audio
    /// anchoring. It rides the cache key, so every existing proxy re-bakes.
    static let bakerVersion = 1

    /// Decoded picture held in memory at once. NV12 is 1.5 bytes per pixel, so
    /// this is ~61 frames of 1080p or ~15 of 4K.
    static let pixelBudgetBytes = 192 * 1_024 * 1_024
    static let maxChunkSeconds: Double = 2.0
    static let maxChunkFrames = 96
    static let minChunkFrames = 8
    /// Raw audio moved per pass while walking the scratch file backwards.
    static let audioChunkFrames = 96_000
    /// 90000 divides the common frame rates exactly (3750 ticks at 24fps), so
    /// stamps and durations survive the round trip through seconds.
    static let videoTimescale: CMTimeScale = 90_000

    // MARK: - Cache key

    /// Content address for a source file: two shots using the same take share
    /// one bake, and a re-render's new clip paths simply stop matching, so no
    /// invalidation pass is needed to keep stale picture off the screen.
    static func cacheKey(sourcePath: String) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: sourcePath)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "revx_" + shortHash(
            "\(sourcePath)|\(size)|\(String(format: "%.3f", modified))|\(bakerVersion)",
            length: 20
        )
    }

    // MARK: - Bake

    /// Reverses `sourceURL` into `outputURL`.
    ///
    /// The caller owns `outputURL`'s directory and its cleanup; every failure
    /// path here removes the partial file, because a truncated proxy reads as
    /// corrupt media long after the failure is forgotten.
    static func bake(
        sourceURL: URL,
        outputURL: URL,
        progress: (@Sendable @MainActor (ReverseProxyBakeProgress) -> Void)? = nil
    ) async throws -> ReverseProxyBakeResult {
        let report: @Sendable (ReverseProxyBakeProgress.Phase, Double) -> Void = { phase, fraction in
            guard let progress else { return }
            let state = ReverseProxyBakeProgress(phase: phase, fraction: fraction)
            Task { @MainActor in progress(state) }
        }

        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("litscenes-reverse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var succeeded = false
        defer {
            try? FileManager.default.removeItem(at: scratch)
            if !succeeded { try? FileManager.default.removeItem(at: outputURL) }
        }

        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ScreenGraphError.capture(
                "\(sourceURL.lastPathComponent) has no video track, so there is nothing to reverse."
            )
        }

        let visualRange = try await videoTrack.load(.timeRange)
        let visualDuration = visualRange.duration.seconds
        guard visualRange.duration.isValid, visualDuration > 0 else {
            throw ScreenGraphError.capture(
                "\(sourceURL.lastPathComponent) reports no picture duration, so it cannot be reversed."
            )
        }

        // MARK: Index pass

        report(.indexing, 0)
        let stamps = try await presentationStamps(
            asset: asset,
            track: videoTrack,
            visualRange: visualRange
        )
        let boundaries = frameBoundaries(stamps: stamps, visualDurationSeconds: visualDuration)
        guard boundaries.count > 2 else {
            throw ScreenGraphError.capture(
                "\(sourceURL.lastPathComponent) has too few frames to reverse."
            )
        }
        let frameCount = boundaries.count - 1
        report(.indexing, 1)

        // MARK: Track facts shared by both encode attempts

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let estimatedDataRate = try await videoTrack.load(.estimatedDataRate)
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)

        // MARK: Audio pre-pass (raw, so the reversal can seek exactly)

        let audioPlan = try await stageReversibleAudio(
            asset: asset,
            visualRange: visualRange,
            scratch: scratch
        )

        // THE ENCODER FALLBACK LAW: the write pass encodes on the shared
        // hardware encoder, which another process (a screen recording, most
        // days) can hold for minutes. A stalled hardware attempt is retried
        // ONCE on the software encoder — slower, but immune to that
        // contention, and a proxy is a cache where existing beats fast.
        // Cancellation is the operator's and never retried.
        var usedSoftwareEncoder = false
        var verified: (durationSeconds: Double, hasAudio: Bool)
        do {
            verified = try await writeProxy(
                asset: asset,
                track: videoTrack,
                visualRange: visualRange,
                boundaries: boundaries,
                audioPlan: audioPlan,
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                estimatedDataRate: estimatedDataRate,
                formatDescription: formatDescriptions.first,
                outputURL: outputURL,
                forceSoftwareEncoder: false,
                report: report
            )
        } catch let error where shouldRetryWithSoftwareEncoder(error) {
            try Task.checkCancellation()
            usedSoftwareEncoder = true
            report(.reversingPicture, 0)
            verified = try await writeProxy(
                asset: asset,
                track: videoTrack,
                visualRange: visualRange,
                boundaries: boundaries,
                audioPlan: audioPlan,
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                estimatedDataRate: estimatedDataRate,
                formatDescription: formatDescriptions.first,
                outputURL: outputURL,
                forceSoftwareEncoder: true,
                report: report
            )
        }

        succeeded = true
        return ReverseProxyBakeResult(
            fileURL: outputURL,
            sourceDurationSeconds: visualDuration,
            proxyDurationSeconds: verified.durationSeconds,
            frameCount: frameCount,
            hasReversedAudio: verified.hasAudio,
            bakerVersion: bakerVersion,
            usedSoftwareEncoder: usedSoftwareEncoder
        )
    }

    /// A failure worth one software-encoder retry: the watchdog's stall (with
    /// or without an underlying error) or VideoToolbox's own contention codes.
    /// Never a cancellation — that is the operator, not the encoder.
    static func shouldRetryWithSoftwareEncoder(_ error: Error) -> Bool {
        if MediaExportGuard.isCancellation(error) { return false }
        if error is MediaExportFailure { return true }
        return MediaExportGuard.isEncoderContentionFailure(error)
    }

    /// One complete write attempt: writer setup, the guarded reversal pass,
    /// finish, and verification. `forceSoftwareEncoder` is the only thing the
    /// two attempts disagree about.
    private static func writeProxy(
        asset: AVURLAsset,
        track: AVAssetTrack,
        visualRange: CMTimeRange,
        boundaries: [Double],
        audioPlan: StagedAudio?,
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        estimatedDataRate: Float,
        formatDescription: CMFormatDescription?,
        outputURL: URL,
        forceSoftwareEncoder: Bool,
        report: @escaping @Sendable (ReverseProxyBakeProgress.Phase, Double) -> Void
    ) async throws -> (durationSeconds: Double, hasAudio: Bool) {
        let visualDuration = boundaries[boundaries.count - 1]
        let frameCount = boundaries.count - 1

        // `AVAssetWriter` refuses a URL that already exists, and a crash mid-bake
        // leaves a truncated proxy at exactly this path — so without this, one
        // interrupted bake would make every future bake of that clip fail
        // forever. Removing it is safe by construction: the only thing that can
        // be here is a proxy, which is a cache. (This also clears the previous
        // attempt's partial file on the software retry.)
        try? FileManager.default.removeItem(at: outputURL)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = false

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: videoOutputSettings(
                naturalSize: naturalSize,
                estimatedDataRate: estimatedDataRate,
                formatDescription: formatDescription,
                forceSoftwareEncoder: forceSoftwareEncoder
            )
        )
        videoInput.expectsMediaDataInRealTime = false
        // Without this a reversed portrait or rotated clip would orient
        // differently from its forward neighbours: the composition's render
        // transform reads `preferredTransform` off whatever file it is handed.
        videoInput.transform = preferredTransform
        guard writer.canAdd(videoInput) else {
            throw ScreenGraphError.capture("Could not prepare the reversed picture track.")
        }
        writer.add(videoInput)

        let audioInput: AVAssetWriterInput? = audioPlan.flatMap { plan in
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: plan.sampleRate,
                    AVNumberOfChannelsKey: plan.channelCount,
                    AVEncoderBitRateKey: 128_000
                ]
            )
            input.expectsMediaDataInRealTime = false
            guard writer.canAdd(input) else { return nil }
            writer.add(input)
            return input
        }

        guard writer.startWriting() else {
            throw writer.error ?? ScreenGraphError.capture("Could not start the reverse bake.")
        }
        writer.startSession(atSourceTime: .zero)

        let carried = CarriedBakeContext(
            writer: writer,
            asset: asset,
            track: track,
            videoInput: videoInput,
            audioInput: audioInput
        )
        try await MediaExportGuard.watchdog(
            contentSeconds: visualDuration,
            operationName: "reverse bake",
            onStall: { carried.writer.cancelWriting() }
        ) {
            try await writeReversedPicture(
                asset: carried.asset,
                track: carried.track,
                visualRange: visualRange,
                boundaries: boundaries,
                input: carried.videoInput,
                report: report
            )
            if let input = carried.audioInput, let audioPlan {
                try await writeReversedAudio(plan: audioPlan, input: input, report: report)
            }
        }

        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw writer.error ?? ScreenGraphError.capture("The reverse bake failed to finish writing.")
        }
        try Task.checkCancellation()

        report(.verifying, 0)
        let verified = try await verify(
            outputURL: outputURL,
            expectedDurationSeconds: visualDuration,
            expectedFrameCount: frameCount,
            expectedAudio: audioPlan != nil
        )
        report(.verifying, 1)
        return verified
    }

    /// The sample's position on the TRACK timeline.
    ///
    /// Output timestamps are the ones an edit list has been applied to, so they
    /// are what the index pass and the decode pass must both read — reading raw
    /// presentation stamps in one and output stamps in the other is how the two
    /// end up describing different timelines by a couple of frames.
    private static func presentationSeconds(_ sample: CMSampleBuffer) -> Double? {
        let output = CMSampleBufferGetOutputPresentationTimeStamp(sample)
        if output.isNumeric { return output.seconds }
        let raw = CMSampleBufferGetPresentationTimeStamp(sample)
        return raw.isNumeric ? raw.seconds : nil
    }

    /// Frame boundaries from raw stamps: `[p₀ … p_{N-1}, D]`, the table the
    /// mirror law reads.
    ///
    /// Pure, because the invariant it carries is worth testing directly — the
    /// telescoping sum of the gaps must equal `D` exactly, or the proxy comes
    /// out a different length from its source.
    static func frameBoundaries(stamps: [Double], visualDurationSeconds: Double) -> [Double] {
        guard visualDurationSeconds > 0 else { return [] }
        // Real files hand back samples the picture timeline cannot contain: a
        // 60-frame fixture yields 64, including NaN stamps, a duplicate of frame
        // zero, and one sitting exactly on the track's end.
        var ticksSeen = Set<Int64>()
        var kept: [Double] = []
        for value in stamps {
            guard value.isFinite,
                  value > -0.000_001,
                  value < visualDurationSeconds - 0.000_000_001 else { continue }
            let ticks = Int64((max(value, 0) * Double(videoTimescale)).rounded())
            guard ticksSeen.insert(ticks).inserted else { continue }
            kept.append(Double(ticks) / Double(videoTimescale))
        }
        guard !kept.isEmpty else { return [] }
        kept.sort()
        // The first frame displays from the START of the track, whatever its own
        // stamp says. A file whose picture begins a couple of frames in — an
        // edit list, or a leading stamp the reader declined to report — would
        // otherwise produce a proxy short by exactly that offset, since the
        // gaps telescope to `D − p₀`.
        kept[0] = 0
        return kept + [visualDurationSeconds]
    }

    // MARK: - Index

    /// Every visual presentation stamp, measured from the track's start.
    ///
    /// Read through a PASSTHROUGH track output (`outputSettings: nil`), which
    /// vends samples exactly as stored — so nothing is decoded and the stamps
    /// are the file's own, exact even when the source is variable frame rate.
    /// Forcing constant frame rate by index instead would silently retime such
    /// a clip.
    ///
    /// `AVAssetReaderSampleReferenceOutput` looks like the natural fit here and
    /// is not: its sample buffers carry reference timing rather than
    /// presentation timing, and it reported 64 stamps beginning at 0.083s for a
    /// 60-frame file written at 24fps from zero.
    private static func presentationStamps(
        asset: AVURLAsset,
        track: AVAssetTrack,
        visualRange: CMTimeRange
    ) async throws -> [Double] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw ScreenGraphError.capture("Could not index the clip's frames for reversal.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? ScreenGraphError.capture("Could not read the clip for reversal.")
        }
        defer { reader.cancelReading() }

        let start = visualRange.start.seconds
        var stamps: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let seconds = presentationSeconds(sample) else { continue }
            stamps.append(seconds - start)
        }
        if reader.status == .failed {
            throw reader.error ?? ScreenGraphError.capture("Indexing the clip for reversal failed.")
        }
        // Samples arrive in decode order; cleaning and ordering is the pure
        // boundary builder's job.
        return stamps
    }

    // MARK: - Picture

    private static func writeReversedPicture(
        asset: AVURLAsset,
        track: AVAssetTrack,
        visualRange: CMTimeRange,
        boundaries: [Double],
        input: AVAssetWriterInput,
        report: (ReverseProxyBakeProgress.Phase, Double) -> Void
    ) async throws {
        let frameCount = boundaries.count - 1
        let duration = boundaries[frameCount]
        let chunks = chunkRanges(frameCount: frameCount, boundaries: boundaries, track: track)
        var written = 0
        // Every decoded frame shares dimensions and pixel format, so one
        // description serves the whole pass.
        var format: CMVideoFormatDescription?
        /// The last frame written, held for any index the decoder skipped.
        var heldPixels: CVPixelBuffer?

        // Chunks are walked last to first, and reversed inside each, so the
        // writer only ever sees increasing stamps while one chunk is resident.
        for chunk in chunks.reversed() {
            try Task.checkCancellation()
            let decoded = try decodeChunk(
                asset: asset,
                track: track,
                visualStart: visualRange.start,
                boundaries: boundaries,
                chunk: chunk
            )
            for index in stride(from: chunk.upperBound - 1, through: chunk.lowerBound, by: -1) {
                // A frame the decoder did not hand back must still occupy its
                // time. Skipping it drops its DURATION too, which silently
                // shortens the whole proxy by a frame and fails verification
                // far from the cause — so the adjacent frame is held instead.
                // Reverse order means the held frame is the one just written,
                // i.e. this frame's immediate neighbour.
                guard let pixels = decoded[index] ?? heldPixels else {
                    throw ScreenGraphError.capture(
                        "The clip's opening frames could not be decoded for reversal."
                    )
                }
                heldPixels = pixels
                if format == nil {
                    var created: CMVideoFormatDescription?
                    CMVideoFormatDescriptionCreateForImageBuffer(
                        allocator: kCFAllocatorDefault,
                        imageBuffer: pixels,
                        formatDescriptionOut: &created
                    )
                    format = created
                }
                guard let format else {
                    throw ScreenGraphError.capture("Could not describe the reversed picture format.")
                }
                // Both halves of the law, stated explicitly. The writer would
                // otherwise have to GUESS the final frame's length — and it
                // guesses generously, which is how a frame-exact reversal ends
                // up running two frames long.
                var timing = CMSampleTimingInfo(
                    duration: CMTime(
                        seconds: max(boundaries[index + 1] - boundaries[index], 0),
                        preferredTimescale: videoTimescale
                    ),
                    presentationTimeStamp: CMTime(
                        seconds: max(duration - boundaries[index + 1], 0),
                        preferredTimescale: videoTimescale
                    ),
                    decodeTimeStamp: .invalid
                )
                var sample: CMSampleBuffer?
                guard CMSampleBufferCreateReadyWithImageBuffer(
                    allocator: kCFAllocatorDefault,
                    imageBuffer: pixels,
                    formatDescription: format,
                    sampleTiming: &timing,
                    sampleBufferOut: &sample
                ) == noErr, let sample else {
                    throw ScreenGraphError.capture("Could not package a reversed frame.")
                }
                try await waitUntilReady(input)
                try Task.checkCancellation()
                guard input.append(sample) else {
                    throw ScreenGraphError.capture("The reversed picture track stopped accepting frames.")
                }
                written += 1
            }
            report(.reversingPicture, Double(written) / Double(max(frameCount, 1)))
        }
        guard written == frameCount else {
            throw ScreenGraphError.capture(
                "Reversal wrote \(written) of \(frameCount) frames."
            )
        }
    }

    /// Frame index ranges, bounded by both the memory budget and a wall-clock
    /// span so a very high frame rate cannot blow either.
    private static func chunkRanges(
        frameCount: Int,
        boundaries: [Double],
        track: AVAssetTrack
    ) -> [Range<Int>] {
        let size = track.naturalSize
        let bytesPerFrame = max(Int(size.width * size.height * 3 / 2), 1)
        let budgetFrames = min(max(pixelBudgetBytes / bytesPerFrame, minChunkFrames), maxChunkFrames)

        var ranges: [Range<Int>] = []
        var lower = 0
        while lower < frameCount {
            var upper = min(lower + budgetFrames, frameCount)
            // Also cap the chunk's span in seconds.
            while upper > lower + 1, boundaries[upper] - boundaries[lower] > maxChunkSeconds {
                upper -= 1
            }
            ranges.append(lower..<upper)
            lower = upper
        }
        return ranges
    }

    /// Decodes one chunk into pixel buffers keyed by frame index.
    ///
    /// Retaining the sample buffers retains their pixel buffers, so no copy is
    /// needed and resident memory is exactly what the budget allowed.
    private static func decodeChunk(
        asset: AVURLAsset,
        track: AVAssetTrack,
        visualStart: CMTime,
        boundaries: [Double],
        chunk: Range<Int>
    ) throws -> [Int: CVPixelBuffer] {
        let lowerSeconds = boundaries[chunk.lowerBound]
        let upperSeconds = boundaries[chunk.upperBound]
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: CMTimeAdd(visualStart, CMTime(seconds: lowerSeconds, preferredTimescale: 600)),
            duration: CMTime(seconds: max(upperSeconds - lowerSeconds, 0), preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw ScreenGraphError.capture("Could not decode a chunk of the clip for reversal.")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? ScreenGraphError.capture("Could not decode the clip for reversal.")
        }
        defer { reader.cancelReading() }

        var samples: [CMSampleBuffer] = []
        while let sample = output.copyNextSampleBuffer() {
            samples.append(sample)
        }
        if reader.status == .failed {
            throw reader.error ?? ScreenGraphError.capture("Decoding the clip for reversal failed.")
        }

        let start = visualStart.seconds
        let frames = samples
            .compactMap { sample -> (seconds: Double, pixels: CVPixelBuffer)? in
                guard let pixels = CMSampleBufferGetImageBuffer(sample),
                      let seconds = presentationSeconds(sample) else { return nil }
                return (seconds - start, pixels)
            }
            .sorted { $0.seconds < $1.seconds }

        var decoded: [Int: CVPixelBuffer] = [:]
        // When the decoder returns exactly the frames the index expects, trust
        // presentation ORDER. It is the common case, and it cannot be defeated
        // by the two passes rounding a stamp differently — which is precisely
        // how frames used to go missing.
        if frames.count == chunk.count {
            for (offset, frame) in frames.enumerated() {
                decoded[chunk.lowerBound + offset] = frame.pixels
            }
            return decoded
        }
        // Otherwise bind each frame to the indexed stamp it actually matches.
        for frame in frames {
            guard let index = nearestFrameIndex(
                toSeconds: frame.seconds,
                boundaries: boundaries,
                within: chunk
            ) else { continue }
            decoded[index] = frame.pixels
        }
        return decoded
    }

    /// The frame in `chunk` whose indexed stamp is closest to `seconds`.
    ///
    /// Deliberately unconditional: an earlier version rejected anything more
    /// than half a frame from an indexed stamp, and a rejected frame is a HOLE —
    /// its duration went unwritten and the proxy came out short. Landing a frame
    /// one slot from where it belongs is a far smaller error than losing it.
    private static func nearestFrameIndex(
        toSeconds seconds: Double,
        boundaries: [Double],
        within chunk: Range<Int>
    ) -> Int? {
        var best: Int?
        var bestDistance = Double.infinity
        for index in chunk {
            let distance = abs(boundaries[index] - seconds)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private static func waitUntilReady(_ input: AVAssetWriterInput) async throws {
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: - Audio

    struct StagedAudio: Sendable {
        var rawURL: URL
        var sampleRate: Double
        var channelCount: Int
        var frameCount: Int
    }

    /// Writes the source's audio, over exactly the PICTURE's span, to a raw
    /// interleaved Float32 scratch file.
    ///
    /// Anchoring on picture rather than on the audio track is what keeps the
    /// proxy's audio starting at zero and ending at `D`. The composition
    /// builder span-aligns audio to the video range, so that alignment then
    /// becomes a no-op. Reversing the whole audio track instead would slide
    /// everything by the audio overhang — silently, and only on the files that
    /// have one.
    ///
    /// Staging to disk (rather than reversing in memory) is what makes the
    /// reversal exact: reading the raw file backwards seeks to exact sample
    /// offsets, so no chunk boundary can drop or duplicate a sample.
    private static func stageReversibleAudio(
        asset: AVURLAsset,
        visualRange: CMTimeRange,
        scratch: URL
    ) async throws -> StagedAudio? {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let audioRange = try await track.load(.timeRange)
        let shared = CMTimeRangeGetIntersection(audioRange, otherRange: visualRange)
        guard shared.duration.isValid, shared.duration.seconds > 0 else { return nil }

        let descriptions = try await track.load(.formatDescriptions)
        guard let basic = descriptions.first.flatMap({
            CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee
        }) else { return nil }
        let sampleRate = basic.mSampleRate > 0 ? basic.mSampleRate : 48_000
        let channelCount = max(min(Int(basic.mChannelsPerFrame), 2), 1)

        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = shared
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }

        let rawURL = scratch.appendingPathComponent("audio.f32")
        FileManager.default.createFile(atPath: rawURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: rawURL) else { return nil }
        defer { try? handle.close() }

        let bytesPerFrame = 4 * channelCount
        var totalBytes = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &pointer
            ) == kCMBlockBufferNoErr, let pointer, length > 0 else { continue }
            handle.write(Data(bytes: pointer, count: length))
            totalBytes += length
        }
        if reader.status == .failed { return nil }
        try? handle.synchronize()

        let frameCount = totalBytes / bytesPerFrame
        guard frameCount > Int(sampleRate / 24) else { return nil }
        return StagedAudio(
            rawURL: rawURL,
            sampleRate: sampleRate,
            channelCount: channelCount,
            frameCount: frameCount
        )
    }

    /// Walks the staged raw audio backwards and feeds it to the writer.
    private static func writeReversedAudio(
        plan: StagedAudio,
        input: AVAssetWriterInput,
        report: (ReverseProxyBakeProgress.Phase, Double) -> Void
    ) async throws {
        let handle = try FileHandle(forReadingFrom: plan.rawURL)
        defer { try? handle.close() }

        let channels = plan.channelCount
        let bytesPerFrame = 4 * channels
        var remaining = plan.frameCount
        var written = 0

        var description = AudioStreamBasicDescription(
            mSampleRate: plan.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bytesPerFrame),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerFrame),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &description,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &format
        ) == noErr, let format else {
            throw ScreenGraphError.capture("Could not describe the reversed audio format.")
        }

        while remaining > 0 {
            try Task.checkCancellation()
            let frames = min(audioChunkFrames, remaining)
            let offset = (remaining - frames) * bytesPerFrame
            try handle.seek(toOffset: UInt64(offset))
            guard let data = try handle.read(upToCount: frames * bytesPerFrame), !data.isEmpty else { break }

            var samples = data.withUnsafeBytes { raw -> [Float] in
                Array(raw.bindMemory(to: Float.self))
            }
            // Reverse whole FRAMES, never the flat sample array: interleaved
            // stereo is L R L R, so reversing samples one at a time would swap
            // the channels on every frame.
            samples = reversedByFrame(samples, channelCount: channels)

            let buffer = try sampleBuffer(
                samples: samples,
                format: format,
                frameCount: frames,
                startFrame: written,
                sampleRate: plan.sampleRate,
                bytesPerFrame: bytesPerFrame
            )
            try await waitUntilReady(input)
            guard input.append(buffer) else {
                throw ScreenGraphError.capture("The reversed audio track stopped accepting samples.")
            }
            written += frames
            remaining -= frames
            report(.reversingAudio, Double(written) / Double(max(plan.frameCount, 1)))
        }
    }

    /// Reverses interleaved audio a frame at a time, preserving channel order
    /// inside each frame.
    static func reversedByFrame(_ samples: [Float], channelCount: Int) -> [Float] {
        guard channelCount > 1 else { return samples.reversed() }
        let frames = samples.count / channelCount
        var out = [Float](repeating: 0, count: frames * channelCount)
        for frame in 0..<frames {
            let source = (frames - 1 - frame) * channelCount
            let destination = frame * channelCount
            for channel in 0..<channelCount {
                out[destination + channel] = samples[source + channel]
            }
        }
        return out
    }

    private static func sampleBuffer(
        samples: [Float],
        format: CMAudioFormatDescription,
        frameCount: Int,
        startFrame: Int,
        sampleRate: Double,
        bytesPerFrame: Int
    ) throws -> CMSampleBuffer {
        let byteCount = frameCount * bytesPerFrame
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &block
        ) == kCMBlockBufferNoErr, let block else {
            throw ScreenGraphError.capture("Could not allocate the reversed audio buffer.")
        }
        let status = samples.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        guard status == kCMBlockBufferNoErr else {
            throw ScreenGraphError.capture("Could not fill the reversed audio buffer.")
        }

        // A running frame counter, so the stamps cannot accumulate drift.
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: CMTime(
                value: CMTimeValue(startFrame),
                timescale: CMTimeScale(sampleRate)
            ),
            decodeTimeStamp: .invalid
        )
        var buffer: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: [bytesPerFrame],
            sampleBufferOut: &buffer
        ) == noErr, let buffer else {
            throw ScreenGraphError.capture("Could not package the reversed audio samples.")
        }
        return buffer
    }

    // MARK: - Verification

    /// Reopens the written file and checks it against what was asked for.
    ///
    /// Audio that failed to land where it belongs is STRIPPED rather than
    /// shipped: a silent proxy is honest and the pure transform already knows
    /// how to silence a span, whereas an out-of-sync one is a defect that only
    /// shows up on playback.
    private static func verify(
        outputURL: URL,
        expectedDurationSeconds: Double,
        expectedFrameCount: Int,
        expectedAudio: Bool
    ) async throws -> (durationSeconds: Double, hasAudio: Bool) {
        let asset = AVURLAsset(url: outputURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ScreenGraphError.capture("The reversed proxy came back with no picture.")
        }
        let range = try await videoTrack.load(.timeRange)
        let duration = range.duration.seconds
        let frameTolerance = expectedDurationSeconds / Double(max(expectedFrameCount, 1))
        guard abs(duration - expectedDurationSeconds) <= max(frameTolerance, 1.0 / 24.0) else {
            let frameDelta = (expectedDurationSeconds - duration) * Double(expectedFrameCount)
                / max(expectedDurationSeconds, 0.000_1)
            throw ScreenGraphError.capture(
                "The reversed proxy is \(String(format: "%.3f", duration))s "
                    + "against \(String(format: "%.3f", expectedDurationSeconds))s of source picture "
                    + "(\(String(format: "%.1f", frameDelta)) frames of \(expectedFrameCount))."
            )
        }

        guard expectedAudio else { return (duration, false) }
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            return (duration, false)
        }
        let audioRange = try await audioTrack.load(.timeRange)
        let startsAtZero = abs(audioRange.start.seconds) <= 0.001
        let lengthMatches = abs(audioRange.duration.seconds - expectedDurationSeconds)
            <= max(frameTolerance, 1.0 / 24.0)
        return (duration, startsAtZero && lengthMatches)
    }

    // MARK: - Settings

    private static func videoOutputSettings(
        naturalSize: CGSize,
        estimatedDataRate: Float,
        formatDescription: CMFormatDescription?,
        forceSoftwareEncoder: Bool = false
    ) -> [String: Any] {
        let width = max(Int(naturalSize.width.rounded()), 2)
        let height = max(Int(naturalSize.height.rounded()), 2)
        // A floor so a low-bitrate source does not compound its own artifacts
        // through another generation.
        let bitrate = max(Int(estimatedDataRate), width * height * 4)

        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: bitrate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            // Decode order then equals presentation order, and short GOPs keep
            // the compositor's seeks into arbitrary kept spans cheap and exact
            // — which matters far more for a proxy than its file size does.
            AVVideoAllowFrameReorderingKey: false,
            AVVideoMaxKeyFrameIntervalKey: 12
        ]

        var settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            // Natural size, NOT the playback profile: a proxy stands in for a
            // SOURCE file, and the composition's render transform must see the
            // same geometry it saw going forward.
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compression
        ]
        if forceSoftwareEncoder {
            // The fallback attempt must not queue behind the same held AVE
            // block that stalled the first one.
            settings[AVVideoEncoderSpecificationKey] = [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: false
            ]
        }
        if let colors = colorProperties(from: formatDescription) {
            // Carrying colour across stops the proxy shifting hue against the
            // unreversed clips it is cut against.
            settings[AVVideoColorPropertiesKey] = colors
        }
        return settings
    }

    private static func colorProperties(from description: CMFormatDescription?) -> [String: Any]? {
        guard let description else { return nil }
        func extension_(_ key: CFString) -> String? {
            CMFormatDescriptionGetExtension(description, extensionKey: key) as? String
        }
        guard let primaries = extension_(kCMFormatDescriptionExtension_ColorPrimaries),
              let transfer = extension_(kCMFormatDescriptionExtension_TransferFunction),
              let matrix = extension_(kCMFormatDescriptionExtension_YCbCrMatrix) else {
            return nil
        }
        return [
            AVVideoColorPrimariesKey: primaries,
            AVVideoTransferFunctionKey: transfer,
            AVVideoYCbCrMatrixKey: matrix
        ]
    }
}

/// None of AVFoundation's reader/writer types are `Sendable`, but the bake owns
/// all of them outright: they are created, driven, and finished inside one call,
/// and the only reason they cross a task boundary at all is that the stall
/// watchdog runs the write pass as a child task. This carries them over
/// together, so exactly one place makes that promise instead of six.
private struct CarriedBakeContext: @unchecked Sendable {
    let writer: AVAssetWriter
    let asset: AVURLAsset
    let track: AVAssetTrack
    let videoInput: AVAssetWriterInput
    let audioInput: AVAssetWriterInput?
}
