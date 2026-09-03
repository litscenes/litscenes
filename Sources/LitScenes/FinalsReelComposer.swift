@preconcurrency import AVFoundation
import Foundation

/// THE REEL COMPOSITION LAW's AVFoundation half: one live composition built
/// from the plan's baked-clip specs (each cut's mixed audio riding the
/// stitcher's single shared audio track at unity) plus the music bed as
/// extra tracks with a small AVAudioMix. The SAME value backs the preview
/// player item and the export session — preview == export by construction.
enum FinalsReelComposer {
    struct Result: @unchecked Sendable {
        var composition: AVMutableComposition
        var videoComposition: AVMutableVideoComposition
        var audioMix: AVAudioMix?
        var durationSeconds: Double
    }

    static func buildReelComposition(
        plan: ReelCompositionPlan,
        musicRegions: [ShotAudioRegion],
        profile: VideoOutputProfile
    ) async throws -> Result {
        let built = try await VideoChainMedia.buildStitchComposition(
            specs: plan.specs,
            profile: profile,
            fadeInFrames: plan.fadeInFrames,
            fadeOutFrames: plan.fadeOutFrames
        )
        // The plan's arithmetic and the stitcher's timeline must agree to the
        // frame, or something upstream (a sidecar duration, the crossfade
        // shave math) is lying — stop loudly rather than play a reel whose
        // bands and music land at the wrong seconds.
        let frameSlack = 1.0 / Double(max(profile.fps, 1)) + 0.002
        guard abs(built.durationSeconds - plan.totalSeconds) <= frameSlack else {
            throw ScreenGraphError.capture(String(
                format: "Reel assembly disagrees with its plan by %.3fs — a baked clip's probed duration is stale.",
                abs(built.durationSeconds - plan.totalSeconds)
            ))
        }

        // The music bed: reel-output-time regions through the SAME inserters
        // and clamp law as every shot overlay. Muted regions and missing
        // files stay silent here and are reported by the lane UI, not the
        // composer.
        var parameters: [AVMutableAudioMixInputParameters] = []
        for region in musicRegions.map({ $0.normalized() }) {
            guard !region.isMuted,
                  region.durationSeconds > 0,
                  FileManager.default.fileExists(atPath: region.path) else {
                continue
            }
            let placement: (track: AVMutableCompositionTrack, placedRange: CMTimeRange)?
            if region.loops {
                placement = await ShotAudioComposition.addLoopedRegion(
                    to: built.composition,
                    url: URL(fileURLWithPath: region.path),
                    startSeconds: region.startSeconds,
                    durationSeconds: region.durationSeconds,
                    phaseSeconds: region.loopPhaseSeconds,
                    playbackRate: region.playbackRate
                )
            } else {
                placement = await ShotAudioComposition.addRegionOverlay(
                    to: built.composition,
                    url: URL(fileURLWithPath: region.path),
                    startSeconds: region.startSeconds,
                    sourceStartSeconds: region.sourceStartSeconds,
                    durationSeconds: region.durationSeconds,
                    playbackRate: region.playbackRate
                )
            }
            if let placement {
                let input = AVMutableAudioMixInputParameters(track: placement.track)
                input.audioTimePitchAlgorithm = region.pitchMode == .tape ? .varispeed : .timeDomain
                ShotAudioComposition.applyRegionVolume(
                    input,
                    volume: Float(region.gain),
                    region: region,
                    placedRange: placement.placedRange
                )
                applyReelFadeRamps(
                    input,
                    placedRange: placement.placedRange,
                    gain: Float(region.gain),
                    fadeInSeconds: Double(plan.fadeInFrames) / Double(max(profile.fps, 1)),
                    fadeOutSeconds: Double(plan.fadeOutFrames) / Double(max(profile.fps, 1)),
                    totalSeconds: built.durationSeconds
                )
                parameters.append(input)
            }
        }

        var audioMix: AVAudioMix?
        if !parameters.isEmpty {
            let mix = AVMutableAudioMix()
            mix.inputParameters = parameters
            audioMix = mix
        }

        return Result(
            composition: built.composition,
            videoComposition: built.videoComposition,
            audioMix: audioMix,
            durationSeconds: built.durationSeconds
        )
    }

    /// THE REEL FADE's audio half: music under the head/tail picture fades
    /// ramps with the picture. Applied AFTER the region's own volume
    /// instructions and clipped to its placed range — a ramp's level persists
    /// past its window, so the head ramp lands on the region's gain and the
    /// tail ramp lands on silence.
    private static func applyReelFadeRamps(
        _ input: AVMutableAudioMixInputParameters,
        placedRange: CMTimeRange,
        gain: Float,
        fadeInSeconds: Double,
        fadeOutSeconds: Double,
        totalSeconds: Double
    ) {
        let start = placedRange.start.seconds
        let end = CMTimeRangeGetEnd(placedRange).seconds
        if fadeInSeconds > 0, start < fadeInSeconds {
            let rampEnd = min(fadeInSeconds, end)
            if rampEnd - start > 0.001 {
                input.setVolumeRamp(
                    fromStartVolume: 0,
                    toEndVolume: gain,
                    timeRange: CMTimeRange(
                        start: placedRange.start,
                        duration: CMTime(seconds: rampEnd - start, preferredTimescale: 600)
                    )
                )
            }
        }
        if fadeOutSeconds > 0 {
            let windowStart = totalSeconds - fadeOutSeconds
            let rampStart = max(windowStart, start)
            if end - rampStart > 0.001 {
                input.setVolumeRamp(
                    fromStartVolume: gain,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(
                        start: CMTime(seconds: rampStart, preferredTimescale: 600),
                        duration: CMTime(seconds: end - rampStart, preferredTimescale: 600)
                    )
                )
            }
        }
    }
}
