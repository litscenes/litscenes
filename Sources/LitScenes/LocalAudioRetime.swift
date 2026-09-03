import AVFoundation
import Foundation

enum LocalAudioRetime {
    static let processorId = "local_avfoundation_time_domain"

    /// Exports a pitch-preserving M4A at `playbackRate` and returns its duration.
    /// Callers provide a temporary output and own atomic promotion to the active
    /// derivative path.
    static func export(sourceURL: URL, outputURL: URL, playbackRate: Double) async throws -> Double {
        let rate = min(max(playbackRate, 0.25), 4.0)
        let sourceAsset = AVURLAsset(url: sourceURL)
        let sourceTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
        let sourceDuration = try await sourceAsset.load(.duration)
        guard let sourceTrack = sourceTracks.first, sourceDuration.seconds > 0 else {
            throw ScreenGraphError.capture("Narration source has no readable audio track.")
        }

        let composition = AVMutableComposition()
        guard let outputTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ScreenGraphError.capture("Could not create the narration speed composition.")
        }
        let sourceRange = CMTimeRange(start: .zero, duration: sourceDuration)
        try outputTrack.insertTimeRange(sourceRange, of: sourceTrack, at: .zero)

        let outputDuration = CMTime(
            seconds: sourceDuration.seconds / rate,
            preferredTimescale: 600
        )
        if abs(rate - 1.0) > 0.001 {
            outputTrack.scaleTimeRange(sourceRange, toDuration: outputDuration)
        }

        let parameters = AVMutableAudioMixInputParameters(track: outputTrack)
        parameters.audioTimePitchAlgorithm = .timeDomain
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [parameters]

        try ensureDirectory(outputURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw ScreenGraphError.capture("Could not create the narration speed exporter.")
        }
        exporter.audioMix = audioMix
        exporter.timeRange = CMTimeRange(start: .zero, duration: outputDuration)
        try await MediaExportGuard.export(exporter, to: outputURL, as: .m4a, operation: "audio retime")
        return outputDuration.seconds
    }
}
