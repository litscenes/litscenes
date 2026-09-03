@preconcurrency import AVFoundation
import Foundation

struct ShotNarrationDriver: Sendable {
    var url: URL
    var durationSeconds: Double
    var regionId: String
    var fingerprint: String
    var sourceTraceId: String
}

enum ShotNarrationDriverBuilder {
    /// Source fingerprint used by UI staleness checks. It includes the active
    /// bytes and authored placement/trim geometry, so a speed derivative or a
    /// region edit invalidates an earlier narration-driven video even when the
    /// ElevenLabs trace id itself is unchanged.
    static func currentFingerprint(shot: ProjectShot) -> String? {
        guard let narration = shot.narrationArtifact,
              narration.isReady,
              narration.provider == "elevenlabs_tts" else {
            return nil
        }
        let region = shot.audioRegions.map { $0.normalized() }.first {
            $0.laneId == ShotAudioLaneId.narration
                && $0.provenance == "active_narration"
                && !$0.path.isEmpty
        }
        let path = region?.path ?? narration.audioPath
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)),
              !bytes.isEmpty else {
            return nil
        }
        let geometry = [
            region?.regionId ?? "legacy",
            String(format: "%.6f", region?.startSeconds
                ?? shot.audioMix.lane(ShotAudioLaneId.narration).effectiveStartSeconds),
            String(format: "%.6f", region?.sourceStartSeconds ?? 0),
            String(format: "%.6f", region?.durationSeconds ?? narration.durationSeconds),
            narration.traceId,
        ].joined(separator: "|")
        return sha256Hex(Data(geometry.utf8) + bytes)
    }

    static func export(shot: ProjectShot, outputURL: URL) async throws -> ShotNarrationDriver {
        guard let narration = shot.narrationArtifact,
              narration.isReady,
              narration.provider == "elevenlabs_tts",
              FileManager.default.fileExists(atPath: narration.audioPath) else {
            throw ScreenGraphError.capture(
                "LTX 2.3 needs a ready ElevenLabs narration. Open Narration to create one."
            )
        }

        let activeRegion = shot.audioRegions
            .map { $0.normalized() }
            .first {
                $0.laneId == ShotAudioLaneId.narration
                    && $0.provenance == "active_narration"
                    && !$0.path.isEmpty
            }
        let sourceURL = URL(fileURLWithPath: activeRegion?.path ?? narration.audioPath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ScreenGraphError.capture(
                "The active narration audio file is missing. Open Narration and regenerate it."
            )
        }

        let asset = AVURLAsset(url: sourceURL)
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ScreenGraphError.capture("The active narration has no readable audio track.")
        }
        let sourceRange = try await sourceTrack.load(.timeRange)
        let sourceStart = max(activeRegion?.sourceStartSeconds ?? 0, 0)
        let availableSeconds = max(sourceRange.duration.seconds - sourceStart, 0)
        let selectedSeconds = min(
            activeRegion.map { max($0.durationSeconds, 0) } ?? availableSeconds,
            availableSeconds
        )
        let timelineStart = max(
            activeRegion?.startSeconds
                ?? shot.audioMix.lane(ShotAudioLaneId.narration).effectiveStartSeconds,
            0
        )
        guard selectedSeconds > 0 else {
            throw ScreenGraphError.capture(
                "The active narration region contains no playable audio. Open Narration to repair it."
            )
        }

        let composition = AVMutableComposition()
        guard let outputTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ScreenGraphError.capture("Could not create the narration driver.")
        }
        try outputTrack.insertTimeRange(
            CMTimeRange(
                start: CMTime(
                    seconds: sourceRange.start.seconds + sourceStart,
                    preferredTimescale: 600
                ),
                duration: CMTime(seconds: selectedSeconds, preferredTimescale: 600)
            ),
            of: sourceTrack,
            at: CMTime(seconds: timelineStart, preferredTimescale: 600)
        )
        let outputSeconds = timelineStart + selectedSeconds
        guard outputSeconds >= 2, outputSeconds <= 20 else {
            throw ScreenGraphError.capture(
                "LTX 2.3 accepts 2–20 seconds of narration. This authored narration is \(durationLabel(outputSeconds)); adjust its region or speed in Narration."
            )
        }

        try ensureDirectory(outputURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ScreenGraphError.capture("Could not create the narration-driver exporter.")
        }
        exporter.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: outputSeconds, preferredTimescale: 600)
        )
        try await MediaExportGuard.export(exporter, to: outputURL, as: .m4a, operation: "narration export")
        let fingerprint: String
        if let current = currentFingerprint(shot: shot) {
            fingerprint = current
        } else {
            fingerprint = sha256Hex(try Data(contentsOf: outputURL))
        }
        return ShotNarrationDriver(
            url: outputURL,
            durationSeconds: outputSeconds,
            regionId: activeRegion?.regionId ?? "",
            fingerprint: fingerprint,
            sourceTraceId: narration.traceId
        )
    }

    private static func durationLabel(_ seconds: Double) -> String {
        String(format: "%.1fs", seconds)
    }
}
