@preconcurrency import AVFoundation
import Foundation

struct ShotAudioCompositionResult: @unchecked Sendable {
    var composition: AVMutableComposition
    var audioMix: AVAudioMix?
}

/// One linear volume ramp on a region's mix input, in composition seconds.
struct ShotAudioVolumeRamp: Equatable, Sendable {
    var fromVolume: Float
    var toVolume: Float
    var startSeconds: Double
    var durationSeconds: Double
}

/// The mix-input tick grid. Every volume instruction is planned in INTEGER
/// ticks at this timescale and applied with exact `CMTime(value:timescale:)`.
/// Planning in seconds and rounding at apply time is what crashed the shot
/// player: a CLAMPED de-zipper ramp is a fractional tick count, rounding its
/// start and duration independently let `round(end−fall)+round(fall)` exceed
/// `round(end)` by one tick, and the closing zero-set then landed strictly
/// inside the just-installed ramp — AVFCore hard-throws on any overlap.
let shotAudioMixTimescale: Int32 = 600

func shotMixTicks(_ seconds: Double) -> Int64 {
    guard seconds.isFinite else { return 0 }
    return Int64((max(seconds, 0) * Double(shotAudioMixTimescale)).rounded())
}

/// One planned mix-input instruction on the tick grid. `durationTicks == 0`
/// is an instantaneous `setVolume(toVolume)`.
struct ShotAudioMixInstruction: Equatable, Sendable {
    var fromVolume: Float
    var toVolume: Float
    var startTicks: Int64
    var durationTicks: Int64
}

/// Repairs a planned instruction list so AVFoundation can never throw,
/// while leaving well-formed plans byte-identical:
/// - spans sort by start and TRIM FORWARD out of earlier spans' coverage;
///   a fully swallowed span lands its target level as a set instead;
/// - a set inside a span's interior lifts to that span's end (a set at a
///   span's exact start or end is legal — the shipped
///   `setVolume(0, at: .zero)` + ramp-at-zero pattern);
/// - same-tick sets dedupe LAST-wins (sequential setVolume semantics).
/// Audibly this moves boundaries by at most one tick (1/600 s) in the
/// degenerate geometries that used to crash.
func shotSanitizedMixInstructions(_ raw: [ShotAudioMixInstruction]) -> [ShotAudioMixInstruction] {
    let ordered = raw.enumerated()
        .sorted { lhs, rhs in
            lhs.element.startTicks == rhs.element.startTicks
                ? lhs.offset < rhs.offset
                : lhs.element.startTicks < rhs.element.startTicks
        }
        .map(\.element)

    var spans: [ShotAudioMixInstruction] = []
    var sets: [ShotAudioMixInstruction] = []
    var coverageEnd: Int64 = 0
    for candidate in ordered {
        var instruction = candidate
        instruction.startTicks = max(instruction.startTicks, 0)
        instruction.durationTicks = max(instruction.durationTicks, 0)
        if instruction.durationTicks > 0 {
            if instruction.startTicks < coverageEnd {
                instruction.durationTicks -= coverageEnd - instruction.startTicks
                instruction.startTicks = coverageEnd
            }
            if instruction.durationTicks > 0 {
                spans.append(instruction)
                coverageEnd = instruction.startTicks + instruction.durationTicks
                continue
            }
            instruction = ShotAudioMixInstruction(
                fromVolume: candidate.toVolume,
                toVolume: candidate.toVolume,
                startTicks: coverageEnd,
                durationTicks: 0
            )
        }
        sets.append(instruction)
    }

    // Lift sets out of span interiors (spans are disjoint and sorted, so one
    // lift lands at a span end — at worst the exact START of the next span,
    // which is the legal shipped pattern).
    for index in sets.indices {
        if let containing = spans.first(where: {
            $0.startTicks < sets[index].startTicks + 1
                && sets[index].startTicks < $0.startTicks + $0.durationTicks
                && sets[index].startTicks > $0.startTicks
        }) {
            sets[index].startTicks = containing.startTicks + containing.durationTicks
        }
    }
    // Same-tick sets: the LAST wins.
    var lastSetIndexByTick: [Int64: Int] = [:]
    for (index, set) in sets.enumerated() {
        lastSetIndexByTick[set.startTicks] = index
    }
    let dedupedSets = sets.enumerated()
        .filter { lastSetIndexByTick[$0.element.startTicks] == $0.offset }
        .map(\.element)

    // Merge in time order; at an equal tick a set installs BEFORE a span
    // (again the shipped-legal ordering).
    var merged: [(instruction: ShotAudioMixInstruction, rank: Int)] = []
    merged.reserveCapacity(dedupedSets.count + spans.count)
    for set in dedupedSets { merged.append((set, 0)) }
    for span in spans { merged.append((span, 1)) }
    merged.sort { lhs, rhs in
        if lhs.instruction.startTicks == rhs.instruction.startTicks {
            return lhs.rank < rhs.rank
        }
        return lhs.instruction.startTicks < rhs.instruction.startTicks
    }
    return merged.map(\.instruction)
}

/// A region's fade envelope as tick instructions. A ramp holds its end value
/// until the next instruction, so one leading level + the ramps state the
/// whole envelope: silence into a fade-in (nothing plays before the
/// placement), constant `volume` otherwise. Durations are end-anchored —
/// clamped fades are fractional and share the rounding hazard the source
/// windows crashed on.
func shotRegionVolumeInstructions(
    ramps: [ShotAudioVolumeRamp],
    volume: Float
) -> [ShotAudioMixInstruction] {
    guard let first = ramps.first else {
        return [ShotAudioMixInstruction(fromVolume: volume, toVolume: volume, startTicks: 0, durationTicks: 0)]
    }
    var instructions: [ShotAudioMixInstruction] = [
        ShotAudioMixInstruction(
            fromVolume: first.fromVolume == 0 ? 0 : volume,
            toVolume: first.fromVolume == 0 ? 0 : volume,
            startTicks: 0,
            durationTicks: 0
        )
    ]
    for ramp in ramps {
        let start = shotMixTicks(ramp.startSeconds)
        instructions.append(ShotAudioMixInstruction(
            fromVolume: ramp.fromVolume,
            toVolume: ramp.toVolume,
            startTicks: start,
            durationTicks: shotMixTicks(ramp.startSeconds + ramp.durationSeconds) - start
        ))
    }
    return instructions
}

/// The source gain envelope as tick instructions — the same rise/seam/fall
/// grammar `applySourceGainWindows` always drew, with every span's duration
/// END-ANCHORED (`ticks(end) − ticks(start)`) so a ramp's tick end can never
/// spill past the boundary its closing zero-set sits on.
func shotSourceGainInstructions(_ windows: [ShotSourceGainWindow]) -> [ShotAudioMixInstruction] {
    var plan: [ShotAudioMixInstruction] = [
        ShotAudioMixInstruction(fromVolume: 0, toVolume: 0, startTicks: 0, durationTicks: 0)
    ]
    func span(from fromVolume: Float, to toVolume: Float, startSeconds: Double, endSeconds: Double) {
        let start = shotMixTicks(startSeconds)
        let duration = shotMixTicks(endSeconds) - start
        if duration > 0 {
            plan.append(ShotAudioMixInstruction(
                fromVolume: fromVolume,
                toVolume: toVolume,
                startTicks: start,
                durationTicks: duration
            ))
        } else {
            // Sub-tick ramp: an honest step at the boundary.
            plan.append(ShotAudioMixInstruction(
                fromVolume: toVolume,
                toVolume: toVolume,
                startTicks: start,
                durationTicks: 0
            ))
        }
    }
    func set(_ volume: Float, atSeconds seconds: Double) {
        plan.append(ShotAudioMixInstruction(
            fromVolume: volume,
            toVolume: volume,
            startTicks: shotMixTicks(seconds),
            durationTicks: 0
        ))
    }

    for (index, window) in windows.enumerated() {
        let previous = index > 0 ? windows[index - 1] : nil
        let next = index + 1 < windows.count ? windows[index + 1] : nil
        let abutsPrevious = previous.map {
            abs($0.endSeconds - window.startSeconds) <= 1.0 / 240.0
        } ?? false
        let abutsNext = next.map {
            abs(window.endSeconds - $0.startSeconds) <= 1.0 / 240.0
        } ?? false
        let gain = Float(window.gain)

        if abutsPrevious, let previous {
            // One ramp across the seam, centered on it.
            let half = sourceGainRampSeconds(
                windowSeconds: window.durationSeconds,
                neighbourSeconds: previous.durationSeconds,
                fadeSeconds: ShotAudioComposition.sourceGainFadeSeconds
            )
            if half > 0 {
                span(
                    from: Float(previous.gain),
                    to: gain,
                    startSeconds: window.startSeconds - half,
                    endSeconds: window.startSeconds + half
                )
            } else {
                set(gain, atSeconds: window.startSeconds)
            }
        } else {
            // The track is already at zero here; ramp inward only, which
            // also keeps the ramp inside the timeline at t=0.
            let rise = sourceGainRampSeconds(
                windowSeconds: window.durationSeconds,
                neighbourSeconds: nil,
                fadeSeconds: ShotAudioComposition.sourceGainFadeSeconds
            )
            if rise > 0 {
                span(
                    from: 0,
                    to: gain,
                    startSeconds: window.startSeconds,
                    endSeconds: window.startSeconds + rise
                )
            } else {
                set(gain, atSeconds: window.startSeconds)
            }
        }

        guard !abutsNext else { continue }
        let fall = sourceGainRampSeconds(
            windowSeconds: window.durationSeconds,
            neighbourSeconds: nil,
            fadeSeconds: ShotAudioComposition.sourceGainFadeSeconds
        )
        if fall > 0 {
            span(
                from: gain,
                to: 0,
                startSeconds: window.endSeconds - fall,
                endSeconds: window.endSeconds
            )
        }
        set(0, atSeconds: window.endSeconds)
    }
    return plan
}

/// The fade plan for one PLACED region: a rise from silence over the leading
/// `fadeInSeconds`, a fall to silence over the trailing `fadeOutSeconds`.
/// Pure and testable. Windows re-clamp to the ACTUAL placed duration with
/// fade-in priority — compositions truncate at their end, so a persisted
/// fade may exceed what really landed. Empty = constant volume, which the
/// callers keep applying through the historical `setVolume` path.
///
/// Looped regions tile all their chunks onto ONE track, so this single plan
/// spans every tile; and the plan measures OUTPUT seconds, so `playbackRate`
/// needs no correction here.
func shotAudioRegionFadeRamps(
    fadeInSeconds: Double,
    fadeOutSeconds: Double,
    volume: Float,
    placedStartSeconds: Double,
    placedDurationSeconds: Double
) -> [ShotAudioVolumeRamp] {
    guard placedDurationSeconds > 0 else { return [] }
    var fadeIn = max(fadeInSeconds.isFinite ? fadeInSeconds : 0, 0)
    var fadeOut = max(fadeOutSeconds.isFinite ? fadeOutSeconds : 0, 0)
    guard fadeIn > 0 || fadeOut > 0 else { return [] }
    fadeIn = min(fadeIn, placedDurationSeconds)
    fadeOut = min(fadeOut, placedDurationSeconds - fadeIn)
    var ramps: [ShotAudioVolumeRamp] = []
    if fadeIn > 0 {
        ramps.append(ShotAudioVolumeRamp(
            fromVolume: 0,
            toVolume: volume,
            startSeconds: placedStartSeconds,
            durationSeconds: fadeIn
        ))
    }
    if fadeOut > 0 {
        ramps.append(ShotAudioVolumeRamp(
            fromVolume: volume,
            toVolume: 0,
            startSeconds: placedStartSeconds + placedDurationSeconds - fadeOut,
            durationSeconds: fadeOut
        ))
    }
    return ramps
}

/// Builds the same non-destructive audio graph for modal playback and export.
/// Existing composition audio is always the Source lane; generated overlays
/// are separate tracks so lane enable/volume changes remain reversible.
enum ShotAudioComposition {
    /// Duration law (ported from the mobile AudioMux): Lucy re-emits frames on
    /// its own clock — a ~30 fps source can come back 24 fps at ~2× length
    /// (slow motion). The user paid for a restyle of THEIR clip at ITS
    /// duration, so when the returned picture drifts beyond this tolerance
    /// from the recorded source duration, it is retimed back to the source
    /// duration; the audio then covers the full picture.
    static let retimeToleranceSeconds = 0.5

    /// The duration the Look picture must be retimed to, or nil when it plays
    /// as returned (aligned within tolerance, or no recorded source duration).
    static func lookRetimeTargetSeconds(lookSeconds: Double, sourceSeconds: Double) -> Double? {
        guard lookSeconds > 0, sourceSeconds > 0 else { return nil }
        guard abs(lookSeconds - sourceSeconds) > retimeToleranceSeconds else { return nil }
        return sourceSeconds
    }

    /// Playback duration of a ready Look once the retime law is applied — for
    /// UI that reads the artifact without building the composition.
    static func effectiveLookDurationSeconds(_ look: ShotRestyleArtifact) -> Double {
        lookRetimeTargetSeconds(
            lookSeconds: look.outputDurationSeconds,
            sourceSeconds: look.sourceDurationSeconds
        ) ?? look.outputDurationSeconds
    }

    /// PRECEDENCE LAW: a shot with any persisted `audioRegions` plays ONLY
    /// regions. The four singleton overlay branches below (narration,
    /// microphone, ambient, clip) fire only when `audioRegions` is empty —
    /// regionization keeps the singleton fields as inert mirrors, so without
    /// this gate every converted overlay would play twice. The source lane is
    /// independent: gain windows apply when source regions exist, else the
    /// plain source lane volume. `buildCombinedCut`'s singleton import and
    /// the lane views' overlay builders enforce the same law.
    /// Writes the source gain envelope onto one track's mix parameters.
    ///
    /// Abutting windows share ONE ramp centered on their seam — a fall to zero
    /// followed by a rise would punch an audible notch into a join the operator
    /// never edited. Windows separated by a gap each ramp inward instead, so
    /// the gap stays genuinely silent, and every window still closes on a hard
    /// zero: that is what keeps "an instant no window covers is silent" true.
    private static func applySourceGainWindows(
        _ windows: [ShotSourceGainWindow],
        to input: AVMutableAudioMixInputParameters
    ) {
        applyMixInstructions(shotSourceGainInstructions(windows), to: input)
    }

    /// The ONLY writer of ramps/sets onto a mix input: sanitized tick
    /// instructions, applied with exact-tick CMTimes. Every path (source
    /// gain windows, region fades) funnels here so the AVFCore overlap throw
    /// is unreachable by construction.
    static func applyMixInstructions(
        _ instructions: [ShotAudioMixInstruction],
        to input: AVMutableAudioMixInputParameters
    ) {
        for instruction in shotSanitizedMixInstructions(instructions) {
            if instruction.durationTicks <= 0 {
                input.setVolume(
                    instruction.toVolume,
                    at: CMTime(value: instruction.startTicks, timescale: shotAudioMixTimescale)
                )
            } else {
                input.setVolumeRamp(
                    fromStartVolume: instruction.fromVolume,
                    toEndVolume: instruction.toVolume,
                    timeRange: CMTimeRange(
                        start: CMTime(value: instruction.startTicks, timescale: shotAudioMixTimescale),
                        duration: CMTime(value: instruction.durationTicks, timescale: shotAudioMixTimescale)
                    )
                )
            }
        }
    }

    /// De-zipper ramp at a source gain boundary. 10 ms is the standard de-click
    /// constant and is under a quarter of a frame at 24fps, so a gain change
    /// never smears across the cut it belongs to. Deliberately far shorter than
    /// `StoryAudioMixer`'s 0.18 s bed fade, which is a musical gesture rather
    /// than a discontinuity fix.
    static let sourceGainFadeSeconds = 0.010

    static func applyMix(
        to composition: AVMutableComposition,
        shot: ProjectShot,
        /// LAW: this must be the SAME assembly whose `playableSpecs` produced
        /// this composition's audio. A different one puts the windows at the
        /// wrong seconds. nil = no cut assembly available, and source gain
        /// falls back to the historical region-or-flat behavior.
        assembly: ShotCutAssembly? = nil
    ) async -> AVAudioMix? {
        let narrationLane = shot.audioMix.lane(ShotAudioLaneId.narration)
        let microphoneLane = shot.audioMix.lane(ShotAudioLaneId.microphone)
        let ambientLane = shot.audioMix.lane(ShotAudioLaneId.ambient)
        let clipLane = shot.audioMix.lane(ShotAudioLaneId.clip)
        // Match the persisted filter in ProjectShot.normalized(): a region
        // without an id or with zero duration is not playable state.
        let regions = shot.audioRegions.map { $0.normalized() }
            .filter { !$0.regionId.isEmpty && $0.durationSeconds > 0 }
        let usesLegacyOverlays = regions.isEmpty
        // One law decides source loudness; coalescing guarantees that adjacent
        // windows either differ in gain or have a real gap, and SORTS them —
        // out of order, a later window's closing zero can land on an earlier
        // one's opening gain at the same timestamp and silently win.
        let sourceWindows = coalescedSourceGainWindows(
            shotSourceGainWindows(shot: shot, assembly: assembly)
        )
        // THE LOOP REPLICATION LAW: overlays and regions persist at BASE
        // output seconds; a looped assembly re-places them per pass so every
        // pass sounds like the first. Each placement is capped at its own
        // pass boundary — at ×1 the composition end performed that clip, at
        // ×N the next pass's copy takes over. The ambient bed stays out of
        // the replication: it tiles to composition duration already and
        // wrapping it would double-tile. Source gain needs nothing here —
        // its windows are derived per playback item, which the looped
        // assembly repeats by construction.
        let loopOffsets = shotLoopPassOffsets(
            loopCount: assembly?.outputLoopCount ?? 1,
            baseOutputSeconds: assembly?.baseOutputSeconds ?? 0
        )
        let loopBaseSeconds = assembly?.baseOutputSeconds ?? 0
        let isLoopReplicated = loopOffsets.count > 1
        func passCap(startSeconds: Double) -> Double? {
            guard isLoopReplicated else { return nil }
            return max(loopBaseSeconds - startSeconds, 0)
        }
        var parameters: [AVMutableAudioMixInputParameters] = []

        for track in composition.tracks(withMediaType: .audio) {
            let input = AVMutableAudioMixInputParameters(track: track)
            if sourceWindows.isEmpty {
                input.setVolume(laneVolume(shot.audioMix.lane(ShotAudioLaneId.source)), at: .zero)
            } else {
                applySourceGainWindows(sourceWindows, to: input)
            }
            parameters.append(input)
        }

        if usesLegacyOverlays,
           narrationLane.isEnabled,
           let narration = shot.narrationArtifact,
           narration.isReady,
           FileManager.default.fileExists(atPath: narration.audioPath) {
            for passOffset in loopOffsets {
                guard let track = await addOverlay(
                    to: composition,
                    url: URL(fileURLWithPath: narration.audioPath),
                    startSeconds: narrationLane.effectiveStartSeconds + passOffset,
                    maxDurationSeconds: passCap(startSeconds: narrationLane.effectiveStartSeconds)
                ) else { continue }
                let input = AVMutableAudioMixInputParameters(track: track)
                input.setVolume(laneVolume(narrationLane), at: .zero)
                parameters.append(input)
            }
        }

        if usesLegacyOverlays,
           microphoneLane.isEnabled,
           let take = microphoneLane.activeMicrophoneTake,
           FileManager.default.fileExists(atPath: take.path) {
            for passOffset in loopOffsets {
                guard let track = await addOverlay(
                    to: composition,
                    url: URL(fileURLWithPath: take.path),
                    startSeconds: take.startSeconds + passOffset,
                    maxDurationSeconds: passCap(startSeconds: take.startSeconds)
                ) else { continue }
                let input = AVMutableAudioMixInputParameters(track: track)
                input.setVolume(laneVolume(microphoneLane), at: .zero)
                parameters.append(input)
            }
        }

        // Ambient bed: loops seamlessly under the whole shot from t=0 — beds
        // have no timing handle. Rides every applyMix caller (modal playback,
        // Look flatten, Send to Footage, YouTube export). By design it never reaches
        // buildBareLookOverOriginalAudio (lane-less: that output must behave
        // like raw footage) or the reel stitch (no audioMix) — beds reach
        // reels by flattening the shot via Send to Footage first. A missing
        // file means the lane is silently absent, like the other overlays.
        if usesLegacyOverlays,
           ambientLane.isEnabled,
           let bedPath = ambientLane.ambientBedPath,
           FileManager.default.fileExists(atPath: bedPath),
           let track = await addLoopedOverlay(to: composition, url: URL(fileURLWithPath: bedPath)) {
            let input = AVMutableAudioMixInputParameters(track: track)
            input.setVolume(laneVolume(ambientLane), at: .zero)
            parameters.append(input)
        }

        // Imported audio clip: plays ONCE from its lane offset, unlike the
        // ambient bed above, which loops because a synthesized bed has no
        // natural length. A clip is a real recording with its own beginning and
        // end, so looping it would be a lie about the material. It rides the
        // same applyMix callers and the same missing-file rule: absent file,
        // silently absent lane.
        if usesLegacyOverlays,
           clipLane.isEnabled,
           let clipPath = clipLane.clipPath,
           FileManager.default.fileExists(atPath: clipPath) {
            for passOffset in loopOffsets {
                guard let track = await addOverlay(
                    to: composition,
                    url: URL(fileURLWithPath: clipPath),
                    startSeconds: clipLane.effectiveStartSeconds + passOffset,
                    maxDurationSeconds: passCap(startSeconds: clipLane.effectiveStartSeconds)
                ) else { continue }
                let input = AVMutableAudioMixInputParameters(track: track)
                input.setVolume(laneVolume(clipLane), at: .zero)
                parameters.append(input)
            }
        }

        for region in regions where region.laneId != ShotAudioLaneId.source {
            let lane = shot.audioMix.lane(region.laneId)
            guard lane.isEnabled,
                  !region.isMuted,
                  FileManager.default.fileExists(atPath: region.path) else {
                continue
            }
            // A `.loops` region repeats its WINDOW per pass; each window still
            // tiles internally, so there is no double-tile — the window
            // duration is the region's own, capped at the pass boundary.
            let cappedDuration = isLoopReplicated
                ? min(region.durationSeconds, max(loopBaseSeconds - region.startSeconds, 0))
                : region.durationSeconds
            guard cappedDuration > 0 else { continue }
            for passOffset in loopOffsets {
                let placement: (track: AVMutableCompositionTrack, placedRange: CMTimeRange)?
                if region.loops {
                    placement = await addLoopedRegion(
                        to: composition,
                        url: URL(fileURLWithPath: region.path),
                        startSeconds: region.startSeconds + passOffset,
                        durationSeconds: cappedDuration,
                        phaseSeconds: region.loopPhaseSeconds,
                        playbackRate: region.playbackRate
                    )
                } else {
                    placement = await addRegionOverlay(
                        to: composition,
                        url: URL(fileURLWithPath: region.path),
                        startSeconds: region.startSeconds + passOffset,
                        sourceStartSeconds: region.sourceStartSeconds,
                        durationSeconds: cappedDuration,
                        playbackRate: region.playbackRate
                    )
                }
                if let placement {
                    let input = AVMutableAudioMixInputParameters(track: placement.track)
                    input.audioTimePitchAlgorithm = region.pitchMode == .tape ? .varispeed : .timeDomain
                    applyRegionVolume(
                        input,
                        volume: Float(lane.volume * region.gain),
                        region: region,
                        placedRange: placement.placedRange
                    )
                    parameters.append(input)
                }
            }
        }

        guard !parameters.isEmpty else { return nil }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = parameters
        return audioMix
    }

    /// `assembly` rides through to `applyMix`; nil is correct for a legacy
    /// single-file shot, which has no cut assembly to derive windows from.
    static func buildLegacy(
        videoURL: URL,
        shot: ProjectShot,
        assembly: ShotCutAssembly? = nil
    ) async -> ShotAudioCompositionResult? {
        let asset = AVURLAsset(url: videoURL)
        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard let sourceVideo = videoTracks.first else { return nil }
            let videoRange = try await sourceVideo.load(.timeRange)
            guard videoRange.isValid, videoRange.duration > .zero else { return nil }

            let composition = AVMutableComposition()
            guard let destinationVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                return nil
            }
            try destinationVideo.insertTimeRange(videoRange, of: sourceVideo, at: .zero)
            destinationVideo.preferredTransform = try await sourceVideo.load(.preferredTransform)

            if let sourceAudio = audioTracks.first,
               let sourceRange = try? await sourceAudio.load(.timeRange),
               let destinationAudio = composition.addMutableTrack(
                   withMediaType: .audio,
                   preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let sharedStart = max(sourceRange.start, videoRange.start)
                let sharedEnd = min(CMTimeRangeGetEnd(sourceRange), CMTimeRangeGetEnd(videoRange))
                if sharedEnd > sharedStart {
                    try destinationAudio.insertTimeRange(
                        CMTimeRange(start: sharedStart, end: sharedEnd),
                        of: sourceAudio,
                        at: CMTimeSubtract(sharedStart, videoRange.start)
                    )
                }
            }

            let audioMix = await applyMix(to: composition, shot: shot, assembly: assembly)
            return ShotAudioCompositionResult(composition: composition, audioMix: audioMix)
        } catch {
            return nil
        }
    }

    /// Replaces picture with a flattened Look while retaining the Original's
    /// source-audio graph. Lucy output audio is intentionally ignored; the
    /// operator's Source, Narration, and Mic lanes remain authoritative. A
    /// picture that drifted beyond tolerance from the Look's recorded source
    /// duration is retimed back to it, so the audio graph covers the full
    /// picture instead of falling silent partway.
    /// `assembly` must be the one whose audio was laid into
    /// `originalAudioAsset`, so the source windows land at the right seconds.
    static func buildLook(
        videoURL: URL,
        originalAudioAsset: AVAsset?,
        sourceDurationSeconds: Double,
        shot: ProjectShot,
        assembly: ShotCutAssembly? = nil,
        /// Whole-output loop: the baked Look file is ONE pass (source prep is
        /// always base-length), so Look-active playback and flatten tile the
        /// look video here. The caller's `originalAudioAsset` is already
        /// N×-long when built from looped specs, and `pictureDuration` grows
        /// with the tiling, so the audio clamp below needs no branch.
        loopCount: Int = 1
    ) async -> ShotAudioCompositionResult? {
        let lookAsset = AVURLAsset(url: videoURL)
        do {
            guard let lookVideo = try await lookAsset.loadTracks(withMediaType: .video).first else { return nil }
            let lookRange = try await lookVideo.load(.timeRange)
            guard lookRange.isValid, lookRange.duration > .zero else { return nil }
            let composition = AVMutableComposition()
            guard let destinationVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { return nil }
            let passes = min(max(loopCount, 1), ShotCutList.maximumOutputLoopCount)
            var lookCursor = CMTime.zero
            for _ in 0..<passes {
                try destinationVideo.insertTimeRange(lookRange, of: lookVideo, at: lookCursor)
                lookCursor = CMTimeAdd(lookCursor, lookRange.duration)
            }
            destinationVideo.preferredTransform = try await lookVideo.load(.preferredTransform)
            let pictureDuration = retimedPictureDuration(
                of: destinationVideo,
                lookRange: lookRange,
                sourceDurationSeconds: sourceDurationSeconds,
                loopCount: passes
            )

            if let originalAudioAsset {
                let sourceTracks = try await originalAudioAsset.loadTracks(withMediaType: .audio)
                for sourceTrack in sourceTracks {
                    let sourceRange = try await sourceTrack.load(.timeRange)
                    let sharedDuration = min(sourceRange.duration, pictureDuration)
                    guard sharedDuration > .zero,
                          let destination = composition.addMutableTrack(
                              withMediaType: .audio,
                              preferredTrackID: kCMPersistentTrackID_Invalid
                          ) else { continue }
                    try destination.insertTimeRange(
                        CMTimeRange(start: sourceRange.start, duration: sharedDuration),
                        of: sourceTrack,
                        at: .zero
                    )
                }
            }
            let audioMix = await applyMix(to: composition, shot: shot, assembly: assembly)
            return ShotAudioCompositionResult(composition: composition, audioMix: audioMix)
        } catch {
            return nil
        }
    }

    /// Lucy picture over the source range's OWN embedded audio — no shot
    /// lanes, no mix: the result must behave like raw footage (its file audio
    /// becomes the Source lane wherever it is placed). A picture that drifted
    /// beyond tolerance from the recorded source duration is retimed back to
    /// it, so the range audio covers the full picture; sub-tolerance drift
    /// still clamps the audio insert to the shorter of the two tracks.
    static func buildBareLookOverOriginalAudio(
        videoURL: URL,
        audioSourceURL: URL,
        sourceDurationSeconds: Double
    ) async -> ShotAudioCompositionResult? {
        let lookAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioSourceURL)
        do {
            guard let lookVideo = try await lookAsset.loadTracks(withMediaType: .video).first else { return nil }
            let lookRange = try await lookVideo.load(.timeRange)
            guard lookRange.isValid, lookRange.duration > .zero else { return nil }
            let composition = AVMutableComposition()
            guard let destinationVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { return nil }
            try destinationVideo.insertTimeRange(lookRange, of: lookVideo, at: .zero)
            destinationVideo.preferredTransform = try await lookVideo.load(.preferredTransform)
            let pictureDuration = retimedPictureDuration(
                of: destinationVideo,
                lookRange: lookRange,
                sourceDurationSeconds: sourceDurationSeconds
            )

            for sourceTrack in try await audioAsset.loadTracks(withMediaType: .audio) {
                let sourceRange = try await sourceTrack.load(.timeRange)
                let sharedDuration = min(sourceRange.duration, pictureDuration)
                guard sharedDuration > .zero,
                      let destination = composition.addMutableTrack(
                          withMediaType: .audio,
                          preferredTrackID: kCMPersistentTrackID_Invalid
                      ) else { continue }
                try destination.insertTimeRange(
                    CMTimeRange(start: sourceRange.start, duration: sharedDuration),
                    of: sourceTrack,
                    at: .zero
                )
            }
            return ShotAudioCompositionResult(composition: composition, audioMix: nil)
        } catch {
            return nil
        }
    }

    /// Applies the duration law to the just-inserted Look video track: retimes
    /// it to the recorded source duration when drift exceeds tolerance, and
    /// returns the resulting picture duration for the audio clamps.
    ///
    /// The drift judgment is PER PASS (one look file against one source pass);
    /// with a whole-output loop the scale is applied once across the whole
    /// tiled track so every pass retimes identically.
    private static func retimedPictureDuration(
        of track: AVMutableCompositionTrack,
        lookRange: CMTimeRange,
        sourceDurationSeconds: Double,
        loopCount: Int = 1
    ) -> CMTime {
        let passes = max(loopCount, 1)
        let insertedDuration = CMTimeMultiply(lookRange.duration, multiplier: Int32(passes))
        guard let target = lookRetimeTargetSeconds(
            lookSeconds: lookRange.duration.seconds,
            sourceSeconds: sourceDurationSeconds
        ) else { return insertedDuration }
        let targetTime = CMTime(seconds: target * Double(passes), preferredTimescale: 600)
        track.scaleTimeRange(
            CMTimeRange(start: .zero, duration: insertedDuration),
            toDuration: targetTime
        )
        return targetTime
    }

    private static func addOverlay(
        to composition: AVMutableComposition,
        url: URL,
        startSeconds: Double,
        /// Loop-pass seam cap: at ×1 the composition end truncates an
        /// overhanging overlay; at ×N each pass's placement must stop at its
        /// own pass boundary or it would bleed over the next pass's copy.
        maxDurationSeconds: Double? = nil
    ) async -> AVMutableCompositionTrack? {
        let compositionDuration = composition.duration
        let insertionTime = CMTime(
            seconds: min(max(startSeconds, 0), max(compositionDuration.seconds, 0)),
            preferredTimescale: 600
        )
        let remaining = CMTimeSubtract(compositionDuration, insertionTime)
        guard remaining > .zero else { return nil }

        let asset = AVURLAsset(url: url)
        guard let source = try? await asset.loadTracks(withMediaType: .audio).first,
              let sourceRange = try? await source.load(.timeRange),
              let destination = composition.addMutableTrack(
                  withMediaType: .audio,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            return nil
        }
        var duration = min(sourceRange.duration, remaining)
        if let maxDurationSeconds {
            duration = min(duration, CMTime(seconds: max(maxDurationSeconds, 0), preferredTimescale: 600))
        }
        guard duration > .zero else {
            composition.removeTrack(destination)
            return nil
        }
        do {
            try destination.insertTimeRange(
                CMTimeRange(start: sourceRange.start, duration: duration),
                of: source,
                at: insertionTime
            )
            return destination
        } catch {
            composition.removeTrack(destination)
            return nil
        }
    }

    /// Writes one region's level onto its mix input: constant volume when the
    /// region has no fades (the historical `setVolume`, byte-identical), else
    /// the ramp plan over the ACTUAL placed window. Internal (not private)
    /// since the Finals Reel composer levels its music bed through the same
    /// law.
    static func applyRegionVolume(
        _ input: AVMutableAudioMixInputParameters,
        volume: Float,
        region: ShotAudioRegion,
        placedRange: CMTimeRange
    ) {
        let ramps = shotAudioRegionFadeRamps(
            fadeInSeconds: region.fadeInSeconds,
            fadeOutSeconds: region.fadeOutSeconds,
            volume: volume,
            placedStartSeconds: placedRange.start.seconds,
            placedDurationSeconds: placedRange.duration.seconds
        )
        guard !ramps.isEmpty else {
            input.setVolume(volume, at: .zero)
            return
        }
        applyMixInstructions(
            shotRegionVolumeInstructions(ramps: ramps, volume: volume),
            to: input
        )
    }

    /// Internal (not private) since the Finals Reel composer lays its music
    /// bed through these same inserters — one clamp law for every overlay.
    /// Returns the track AND the range it actually occupies in composition
    /// time, so fade ramps land on what really placed rather than on what
    /// was asked for.
    static func addRegionOverlay(
        to composition: AVMutableComposition,
        url: URL,
        startSeconds: Double,
        sourceStartSeconds: Double,
        durationSeconds: Double,
        playbackRate: Double
    ) async -> (track: AVMutableCompositionTrack, placedRange: CMTimeRange)? {
        let compositionDuration = composition.duration
        let insertionTime = CMTime(
            seconds: min(max(startSeconds, 0), max(compositionDuration.seconds, 0)),
            preferredTimescale: 600
        )
        let remaining = CMTimeSubtract(compositionDuration, insertionTime)
        guard remaining > .zero, durationSeconds > 0 else { return nil }
        let asset = AVURLAsset(url: url)
        guard let source = try? await asset.loadTracks(withMediaType: .audio).first,
              let sourceRange = try? await source.load(.timeRange),
              let destination = composition.addMutableTrack(
                  withMediaType: .audio,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            return nil
        }
        let requestedStart = CMTime(
            seconds: max(sourceStartSeconds, 0),
            preferredTimescale: sourceRange.duration.timescale
        )
        let sourceStart = min(CMTimeAdd(sourceRange.start, requestedStart), CMTimeRangeGetEnd(sourceRange))
        let available = CMTimeSubtract(CMTimeRangeGetEnd(sourceRange), sourceStart)
        let rate = min(
            max(playbackRate, ShotAudioRegion.playbackRateRange.lowerBound),
            ShotAudioRegion.playbackRateRange.upperBound
        )
        let outputSeconds = min(durationSeconds, remaining.seconds)
        let requestedSourceDuration = CMTime(
            seconds: outputSeconds * rate,
            preferredTimescale: 600
        )
        let sourceDuration = min(available, requestedSourceDuration)
        let actualOutputDuration = CMTime(
            seconds: sourceDuration.seconds / rate,
            preferredTimescale: 600
        )
        guard sourceDuration > .zero, actualOutputDuration > .zero else {
            composition.removeTrack(destination)
            return nil
        }
        do {
            try destination.insertTimeRange(
                CMTimeRange(start: sourceStart, duration: sourceDuration),
                of: source,
                at: insertionTime
            )
            if abs(rate - 1) > 0.001 {
                destination.scaleTimeRange(
                    CMTimeRange(start: insertionTime, duration: sourceDuration),
                    toDuration: actualOutputDuration
                )
            }
            return (destination, CMTimeRange(start: insertionTime, duration: actualOutputDuration))
        } catch {
            composition.removeTrack(destination)
            return nil
        }
    }

    /// Tiles a looping region from its internal phase. Ordinary regions have
    /// phase 0 and retain the established file-start behavior; split regions
    /// advance the phase so playback crosses the edit cleanly.
    /// `sourceStartSeconds` remains deliberately ignored while looping.
    /// Every tile lands on ONE track, so the returned placed range spans all
    /// of them and a single fade plan covers the whole placement.
    static func addLoopedRegion(
        to composition: AVMutableComposition,
        url: URL,
        startSeconds: Double,
        durationSeconds: Double,
        phaseSeconds: Double,
        playbackRate: Double
    ) async -> (track: AVMutableCompositionTrack, placedRange: CMTimeRange)? {
        let compositionDuration = composition.duration
        let insertionStart = min(max(startSeconds, 0), max(compositionDuration.seconds, 0))
        let targetSeconds = min(
            max(durationSeconds, 0),
            max(compositionDuration.seconds - insertionStart, 0)
        )
        guard targetSeconds > 0 else { return nil }
        let asset = AVURLAsset(url: url)
        guard let source = try? await asset.loadTracks(withMediaType: .audio).first,
              let sourceRange = try? await source.load(.timeRange),
              sourceRange.duration > .zero,
              let destination = composition.addMutableTrack(
                  withMediaType: .audio,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            return nil
        }
        let sourceSeconds = sourceRange.duration.seconds
        let rate = min(
            max(playbackRate, ShotAudioRegion.playbackRateRange.lowerBound),
            ShotAudioRegion.playbackRateRange.upperBound
        )
        let phase = max(phaseSeconds.isFinite ? phaseSeconds : 0, 0)
            .truncatingRemainder(dividingBy: sourceSeconds)
        var cursor = CMTime(seconds: insertionStart, preferredTimescale: 600)
        var remainingSourceSeconds = targetSeconds * rate
        var sourceOffset = phase
        do {
            while remainingSourceSeconds > 0.000_1 {
                let chunk = min(sourceSeconds - sourceOffset, remainingSourceSeconds)
                let chunkDuration = CMTime(seconds: chunk, preferredTimescale: 600)
                try destination.insertTimeRange(
                    CMTimeRange(
                        start: CMTimeAdd(
                            sourceRange.start,
                            CMTime(seconds: sourceOffset, preferredTimescale: 600)
                        ),
                        duration: chunkDuration
                    ),
                    of: source,
                    at: cursor
                )
                cursor = CMTimeAdd(cursor, chunkDuration)
                remainingSourceSeconds -= chunk
                sourceOffset = 0
            }
            if abs(rate - 1) > 0.001 {
                let insertionTime = CMTime(seconds: insertionStart, preferredTimescale: 600)
                let insertedSourceDuration = CMTimeSubtract(cursor, insertionTime)
                destination.scaleTimeRange(
                    CMTimeRange(
                        start: insertionTime,
                        duration: insertedSourceDuration
                    ),
                    toDuration: CMTime(seconds: targetSeconds, preferredTimescale: 600)
                )
            }
            return (destination, CMTimeRange(
                start: CMTime(seconds: insertionStart, preferredTimescale: 600),
                duration: CMTime(seconds: targetSeconds, preferredTimescale: 600)
            ))
        } catch {
            composition.removeTrack(destination)
            return nil
        }
    }

    /// Tiles a seamless bed from t=0 across the full composition duration
    /// using the pure chunk plan (`StoryAudioMixer.insertLoopedBeat`
    /// precedent). On any insert failure the track is removed, so a torn loop
    /// never ships.
    private static func addLoopedOverlay(
        to composition: AVMutableComposition,
        url: URL
    ) async -> AVMutableCompositionTrack? {
        let target = composition.duration
        guard target > .zero else { return nil }
        let asset = AVURLAsset(url: url)
        guard let source = try? await asset.loadTracks(withMediaType: .audio).first,
              let sourceRange = try? await source.load(.timeRange),
              sourceRange.duration > .zero,
              let destination = composition.addMutableTrack(
                  withMediaType: .audio,
                  preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            return nil
        }
        let chunks = ambientBedLoopChunkSeconds(
            bedSeconds: sourceRange.duration.seconds,
            targetSeconds: target.seconds
        )
        guard !chunks.isEmpty else {
            composition.removeTrack(destination)
            return nil
        }
        var cursor = CMTime.zero
        do {
            for chunk in chunks {
                let chunkDuration = CMTime(seconds: chunk, preferredTimescale: 600)
                try destination.insertTimeRange(
                    CMTimeRange(start: sourceRange.start, duration: chunkDuration),
                    of: source,
                    at: cursor
                )
                cursor = CMTimeAdd(cursor, chunkDuration)
            }
            return destination
        } catch {
            composition.removeTrack(destination)
            return nil
        }
    }

    private static func laneVolume(_ lane: ShotAudioLane) -> Float {
        lane.isEnabled ? Float(min(max(lane.volume, 0), 1)) : 0
    }

    /// BAKE HONESTY LAW: live playback may skip an unreadable file silently —
    /// a player must keep playing — but a flatten that would BAKE silence
    /// where the document promises audio must refuse with the file's name,
    /// because the baked file is cached and replayed long after the cause is
    /// gone. A muted region, disabled lane, or zero level is intentional
    /// silence and never refuses; an unmuted region whose file is gone or
    /// unreadable (a cloud placeholder that was never downloaded stats as
    /// present but has no bytes) always does. Callers surface the thrown
    /// message directly: the reel bake board's `.failed` row, Send to
    /// Footage's status line, and the YouTube export status.
    static func verifyExpectedAudibleFilesReadable(
        _ requirements: [ShotAudioFileRequirement]
    ) async throws {
        for requirement in requirements {
            let url = URL(fileURLWithPath: requirement.path)
            let fileName = url.lastPathComponent
            guard FileManager.default.fileExists(atPath: requirement.path) else {
                throw ScreenGraphError.capture(
                    "Audio file missing: \(fileName) (\(requirement.label)) — REPLACE relinks it, or mute the region to bake without it"
                )
            }
            let audioTracks = try? await AVURLAsset(url: url)
                .loadTracks(withMediaType: .audio)
            guard audioTracks?.isEmpty == false else {
                throw ScreenGraphError.capture(
                    "Audio file unreadable: \(fileName) (\(requirement.label)) — likely offline in cloud storage; open it once in Finder to download it, or mute the region"
                )
            }
        }
    }
}

// MARK: - Expected-audible files

/// One audio file the shot's DOCUMENT expects to be audible in a flatten.
struct ShotAudioFileRequirement: Equatable, Sendable {
    var path: String
    var label: String
}

/// Enumerates every file `applyMix` would place audibly, mirroring its gates
/// exactly (same lane/mute/level vetoes, same legacy-overlay switch). Pure so
/// the mirror is pinned by tests; drift between this list and `applyMix`'s
/// guards would either fail bakes for silent files or re-cache silence.
///
/// `outputDurationSeconds` is the BASE pass length: a region starting at or
/// past it is arithmetically silent (the inserters place nothing), so it is
/// deliberately NOT required — a stranded region must not fail a bake it
/// cannot be heard in. Pass `.infinity` when no duration is known.
func shotExpectedAudibleAudioFiles(
    shot: ProjectShot,
    outputDurationSeconds: Double
) -> [ShotAudioFileRequirement] {
    var requirements: [ShotAudioFileRequirement] = []
    func add(_ path: String?, _ label: String) {
        guard let path = path?.trimmed.nilIfEmpty else { return }
        guard !requirements.contains(where: { $0.path == path }) else { return }
        requirements.append(ShotAudioFileRequirement(path: path, label: label))
    }

    let narrationLane = shot.audioMix.lane(ShotAudioLaneId.narration)
    let microphoneLane = shot.audioMix.lane(ShotAudioLaneId.microphone)
    let ambientLane = shot.audioMix.lane(ShotAudioLaneId.ambient)
    let clipLane = shot.audioMix.lane(ShotAudioLaneId.clip)
    let regions = shot.audioRegions.map { $0.normalized() }
        .filter { !$0.regionId.isEmpty && $0.durationSeconds > 0 }

    guard !regions.isEmpty else {
        // Legacy singleton overlays — the same four `applyMix` places when
        // the shot has no regions.
        if narrationLane.isEnabled, narrationLane.volume > 0,
           let narration = shot.narrationArtifact, narration.isReady {
            add(narration.audioPath, "Narration")
        }
        if microphoneLane.isEnabled, microphoneLane.volume > 0,
           let take = microphoneLane.activeMicrophoneTake {
            add(take.path, "Microphone take")
        }
        if ambientLane.isEnabled, ambientLane.volume > 0 {
            add(ambientLane.ambientBedPath, "Ambient bed")
        }
        if clipLane.isEnabled, clipLane.volume > 0 {
            add(clipLane.clipPath, "Audio clip")
        }
        return requirements
    }

    for region in regions where region.laneId != ShotAudioLaneId.source {
        let lane = shot.audioMix.lane(region.laneId)
        guard lane.isEnabled, lane.volume > 0,
              !region.isMuted, region.gain > 0,
              region.startSeconds < outputDurationSeconds else { continue }
        let fileName = URL(fileURLWithPath: region.path).lastPathComponent
        add(region.path, region.label.trimmed.nilIfEmpty ?? fileName)
    }
    return requirements
}
