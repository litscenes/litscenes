import AVFoundation
import Foundation

enum StoryAudioMixer {
    static func mixVoiceOverBeat(
        voiceURL: URL,
        beatURL: URL,
        outputURL: URL,
        durationSeconds: Double,
        voiceStartSeconds: Double,
        beatVolume: Double = 0.55,
        voiceVolume: Double = 1.0,
        voicePlaybackRate: Double = 1.0
    ) async throws {
        let duration = CMTime(seconds: max(durationSeconds, 0.5), preferredTimescale: 600)
        let voiceStart = CMTime(seconds: max(voiceStartSeconds, 0), preferredTimescale: 600)
        let clampedVoiceRate = min(max(voicePlaybackRate, 0.25), 4.0)
        let beatAsset = AVURLAsset(url: beatURL)
        let voiceAsset = AVURLAsset(url: voiceURL)
        let beatTracks = try await beatAsset.loadTracks(withMediaType: .audio)
        let voiceTracks = try await voiceAsset.loadTracks(withMediaType: .audio)
        guard let sourceBeatTrack = beatTracks.first else {
            throw ScreenGraphError.capture("Generated beat bed has no audio track.")
        }
        guard let sourceVoiceTrack = voiceTracks.first else {
            throw ScreenGraphError.capture("Generated voice file has no audio track.")
        }

        let composition = AVMutableComposition()
        guard let beatTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let voiceTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ScreenGraphError.capture("Could not create the story audio mix.")
        }

        let beatDuration = try await beatAsset.load(.duration)
        let voiceDuration = try await voiceAsset.load(.duration)
        try insertLoopedBeat(
            sourceTrack: sourceBeatTrack,
            sourceDuration: beatDuration,
            targetTrack: beatTrack,
            targetDuration: duration
        )

        let availableVoiceDuration = max(CMTimeSubtract(duration, voiceStart).seconds, 0)
        if availableVoiceDuration > 0 {
            let sourceVoiceSeconds = max(voiceDuration.seconds, 0)
            let sourceSecondsToInsert = min(sourceVoiceSeconds, availableVoiceDuration * clampedVoiceRate)
            let outputVoiceSeconds = min(sourceSecondsToInsert / clampedVoiceRate, availableVoiceDuration)
            let sourceVoiceDuration = CMTime(
                seconds: max(sourceSecondsToInsert, 0),
                preferredTimescale: 600
            )
            let outputVoiceDuration = CMTime(
                seconds: max(outputVoiceSeconds, 0),
                preferredTimescale: 600
            )
            if sourceVoiceDuration.seconds > 0, outputVoiceDuration.seconds > 0 {
                try voiceTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: sourceVoiceDuration),
                    of: sourceVoiceTrack,
                    at: voiceStart
                )
                if abs(clampedVoiceRate - 1.0) > 0.001 {
                    voiceTrack.scaleTimeRange(
                        CMTimeRange(start: voiceStart, duration: sourceVoiceDuration),
                        toDuration: outputVoiceDuration
                    )
                }
            }
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [
            volumeParameters(for: beatTrack, duration: duration, volume: beatVolume, startsAt: .zero),
            volumeParameters(
                for: voiceTrack,
                duration: duration,
                volume: voiceVolume,
                startsAt: voiceStart,
                timePitchAlgorithm: .timeDomain
            )
        ]

        try ensureDirectory(outputURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw ScreenGraphError.capture("Could not create the story audio exporter.")
        }
        exportSession.audioMix = audioMix
        exportSession.timeRange = CMTimeRange(start: .zero, duration: duration)
        try await MediaExportGuard.export(exportSession, to: outputURL, as: .m4a, operation: "story audio mix")
    }

    private static func insertLoopedBeat(
        sourceTrack: AVAssetTrack,
        sourceDuration: CMTime,
        targetTrack: AVMutableCompositionTrack,
        targetDuration: CMTime
    ) throws {
        let sourceSeconds = max(sourceDuration.seconds, 0)
        guard sourceSeconds > 0 else {
            throw ScreenGraphError.capture("Generated beat bed duration could not be read.")
        }
        var cursor = CMTime.zero
        while cursor < targetDuration {
            let remaining = CMTimeSubtract(targetDuration, cursor)
            let chunkDuration = minTime(sourceDuration, remaining)
            try targetTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: chunkDuration),
                of: sourceTrack,
                at: cursor
            )
            cursor = CMTimeAdd(cursor, chunkDuration)
        }
    }

    private static func minTime(_ lhs: CMTime, _ rhs: CMTime) -> CMTime {
        lhs <= rhs ? lhs : rhs
    }

    private static func volumeParameters(
        for track: AVCompositionTrack,
        duration: CMTime,
        volume: Double,
        startsAt: CMTime,
        timePitchAlgorithm: AVAudioTimePitchAlgorithm? = nil
    ) -> AVMutableAudioMixInputParameters {
        let parameters = AVMutableAudioMixInputParameters(track: track)
        if let timePitchAlgorithm {
            parameters.audioTimePitchAlgorithm = timePitchAlgorithm
        }
        let clampedVolume = Float(min(max(volume, 0), 1))
        let fade = CMTime(seconds: 0.18, preferredTimescale: 600)
        parameters.setVolume(clampedVolume, at: startsAt)
        parameters.setVolumeRamp(
            fromStartVolume: 0,
            toEndVolume: clampedVolume,
            timeRange: CMTimeRange(start: startsAt, duration: fade)
        )
        let fadeStartSeconds = max(duration.seconds - 0.28, startsAt.seconds)
        parameters.setVolumeRamp(
            fromStartVolume: clampedVolume,
            toEndVolume: 0,
            timeRange: CMTimeRange(
                start: CMTime(seconds: fadeStartSeconds, preferredTimescale: 600),
                duration: fade
            )
        )
        return parameters
    }

}
