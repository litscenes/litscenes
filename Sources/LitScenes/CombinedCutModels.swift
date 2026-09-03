import Foundation

// MARK: - Combined CUT provenance

/// A source snapshot named by an independent combined CUT. The source row
/// remains in the shot timeline unchanged; this value explains which source
/// placement was copied and where it begins in the parent.
struct ShotCombinedSource: Codable, Hashable, Identifiable, Sendable {
    var sourceId: String = ""
    var sourceCutId: String = ""
    var sourceCutName: String = ""
    var sourceEntryIds: [String] = []
    var sourceRenderVersionId: String = ""
    var parentEntryIds: [String] = []
    var outputStartSeconds: Double = 0
    var outputDurationSeconds: Double = 0
    var hadActiveLook: Bool = false

    var id: String { sourceId }

    private enum CodingKeys: String, CodingKey {
        case sourceId, sourceCutId, sourceCutName, sourceEntryIds
        case sourceRenderVersionId, parentEntryIds
        case outputStartSeconds, outputDurationSeconds, hadActiveLook
    }

    init(
        sourceId: String = "",
        sourceCutId: String = "",
        sourceCutName: String = "",
        sourceEntryIds: [String] = [],
        sourceRenderVersionId: String = "",
        parentEntryIds: [String] = [],
        outputStartSeconds: Double = 0,
        outputDurationSeconds: Double = 0,
        hadActiveLook: Bool = false
    ) {
        self.sourceId = sourceId
        self.sourceCutId = sourceCutId
        self.sourceCutName = sourceCutName
        self.sourceEntryIds = sourceEntryIds
        self.sourceRenderVersionId = sourceRenderVersionId
        self.parentEntryIds = parentEntryIds
        self.outputStartSeconds = outputStartSeconds
        self.outputDurationSeconds = outputDurationSeconds
        self.hadActiveLook = hadActiveLook
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceId = try container.decodeIfPresent(String.self, forKey: .sourceId) ?? ""
        sourceCutId = try container.decodeIfPresent(String.self, forKey: .sourceCutId) ?? ""
        sourceCutName = try container.decodeIfPresent(String.self, forKey: .sourceCutName) ?? ""
        sourceEntryIds = try container.decodeIfPresent([String].self, forKey: .sourceEntryIds) ?? []
        sourceRenderVersionId = try container.decodeIfPresent(String.self, forKey: .sourceRenderVersionId) ?? ""
        parentEntryIds = try container.decodeIfPresent([String].self, forKey: .parentEntryIds) ?? []
        outputStartSeconds = try container.decodeIfPresent(Double.self, forKey: .outputStartSeconds) ?? 0
        outputDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .outputDurationSeconds) ?? 0
        hadActiveLook = try container.decodeIfPresent(Bool.self, forKey: .hadActiveLook) ?? false
    }

    func normalized() -> ShotCombinedSource {
        var value = self
        value.sourceId = value.sourceId.trimmed
        value.sourceCutId = value.sourceCutId.trimmed
        value.sourceCutName = value.sourceCutName.trimmed
        value.sourceEntryIds = value.sourceEntryIds.map(\.trimmed).filter { !$0.isEmpty }
        value.sourceRenderVersionId = value.sourceRenderVersionId.trimmed
        value.parentEntryIds = value.parentEntryIds.map(\.trimmed).filter { !$0.isEmpty }
        value.outputStartSeconds = max(value.outputStartSeconds.isFinite ? value.outputStartSeconds : 0, 0)
        value.outputDurationSeconds = max(value.outputDurationSeconds.isFinite ? value.outputDurationSeconds : 0, 0)
        return value
    }
}

/// A hard source seam in the copied raw timeline. It rides the right entry,
/// like ordinary seam state, but remains separately identifiable so planning
/// and duplicate-handoff trimming never infer continuity across two CUTs.
struct ShotSourceBoundary: Codable, Hashable, Identifiable, Sendable {
    var boundaryId: String = ""
    var leftSourceCutId: String = ""
    var rightSourceCutId: String = ""
    var rightEntryId: String = ""
    var createdAt: String = ""

    var id: String { boundaryId }

    private enum CodingKeys: String, CodingKey {
        case boundaryId, leftSourceCutId, rightSourceCutId, rightEntryId, createdAt
    }

    init(
        boundaryId: String = "",
        leftSourceCutId: String = "",
        rightSourceCutId: String = "",
        rightEntryId: String = "",
        createdAt: String = ""
    ) {
        self.boundaryId = boundaryId
        self.leftSourceCutId = leftSourceCutId
        self.rightSourceCutId = rightSourceCutId
        self.rightEntryId = rightEntryId
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        boundaryId = try container.decodeIfPresent(String.self, forKey: .boundaryId) ?? ""
        leftSourceCutId = try container.decodeIfPresent(String.self, forKey: .leftSourceCutId) ?? ""
        rightSourceCutId = try container.decodeIfPresent(String.self, forKey: .rightSourceCutId) ?? ""
        rightEntryId = try container.decodeIfPresent(String.self, forKey: .rightEntryId) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }

    func normalized() -> ShotSourceBoundary {
        var value = self
        value.boundaryId = value.boundaryId.trimmed
        value.leftSourceCutId = value.leftSourceCutId.trimmed
        value.rightSourceCutId = value.rightSourceCutId.trimmed
        value.rightEntryId = value.rightEntryId.trimmed
        value.createdAt = value.createdAt.trimmed
        return value
    }
}

/// Pitch treatment for an audio region whose timeline duration differs from
/// the source span it consumes. Unknown future values decode to `.preserve`
/// through `ShotAudioRegion`'s compatibility decoder.
enum ShotAudioPitchMode: String, Codable, CaseIterable, Hashable, Sendable {
    case preserve
    case tape

    var label: String {
        switch self {
        case .preserve: return "Preserve"
        case .tape: return "Tape"
        }
    }
}

/// One independently editable audio placement. Every CUT uses regions once
/// its audio is edited; legacy singleton lanes convert on first write and the
/// singleton fields stay behind as inert mirrors under the precedence law
/// (see `ShotAudioComposition.applyMix`).
struct ShotAudioRegion: Codable, Hashable, Identifiable, Sendable {
    static let playbackRateRange: ClosedRange<Double> = 0.25...4

    var regionId: String = ""
    var laneId: String = ""
    var label: String = ""
    var path: String = ""
    var mediaId: String = ""
    var sourceCutId: String = ""
    var sourceArtifactId: String = ""
    var provenance: String = ""
    var startSeconds: Double = 0
    var sourceStartSeconds: Double = 0
    var durationSeconds: Double = 0
    /// The media file's natural length. nil on regions persisted before this
    /// field existed (lazy-backfilled on first edit) and on synthesized
    /// source-lane gain windows. Optional — never 0-default — so "unknown"
    /// stays distinguishable from "empty file"; nil means no media clamp.
    var sourceDurationSeconds: Double?
    /// Playback offset within a looping file. Existing regions decode to 0,
    /// preserving the established file-start loop law. Splitting a looped
    /// region advances only the right child's phase so the edit is inaudible.
    var loopPhaseSeconds: Double = 0
    /// Source seconds consumed by one timeline second. Playback is assembled
    /// non-destructively; this never rewrites the file at `path`.
    var playbackRate: Double = 1
    var pitchMode: ShotAudioPitchMode = .preserve
    var gain: Double = 1
    var isMuted: Bool = false
    var loops: Bool = false
    /// Fade envelope in OUTPUT seconds: a rise from silence over the region's
    /// first `fadeInSeconds` and a fall to silence over its last
    /// `fadeOutSeconds`. Zero = the historical hard in/out. Fades ride the
    /// placed region — for loops they span the whole placement across tiles,
    /// and under `playbackRate` they measure timeline time, not source time.
    var fadeInSeconds: Double = 0
    var fadeOutSeconds: Double = 0

    var id: String { regionId }
    var endSeconds: Double { startSeconds + durationSeconds }
    var selectedSourceDurationSeconds: Double { durationSeconds * playbackRate }

    /// Longest honest non-looping duration from the current in-point.
    /// nil = unknown media length, so no clamp applies.
    var maxNonLoopingDurationSeconds: Double? {
        sourceDurationSeconds.map {
            max($0 - sourceStartSeconds, 0) / max(playbackRate, Self.playbackRateRange.lowerBound)
        }
    }

    /// Timeline second where the media naturally runs out — the "MEDIA END"
    /// tick the trim UI draws. nil = unknown.
    var mediaEndOnTimelineSeconds: Double? {
        maxNonLoopingDurationSeconds.map { startSeconds + $0 }
    }

    private enum CodingKeys: String, CodingKey {
        case regionId, laneId, label, path, mediaId, sourceCutId
        case sourceArtifactId, provenance, startSeconds, sourceStartSeconds
        case durationSeconds, sourceDurationSeconds, loopPhaseSeconds
        case playbackRate, pitchMode, gain, isMuted, loops
        case fadeInSeconds, fadeOutSeconds
    }

    init(
        regionId: String = "",
        laneId: String = "",
        label: String = "",
        path: String = "",
        mediaId: String = "",
        sourceCutId: String = "",
        sourceArtifactId: String = "",
        provenance: String = "",
        startSeconds: Double = 0,
        sourceStartSeconds: Double = 0,
        durationSeconds: Double = 0,
        sourceDurationSeconds: Double? = nil,
        loopPhaseSeconds: Double = 0,
        playbackRate: Double = 1,
        pitchMode: ShotAudioPitchMode = .preserve,
        gain: Double = 1,
        isMuted: Bool = false,
        loops: Bool = false,
        fadeInSeconds: Double = 0,
        fadeOutSeconds: Double = 0
    ) {
        self.regionId = regionId
        self.laneId = laneId
        self.label = label
        self.path = path
        self.mediaId = mediaId
        self.sourceCutId = sourceCutId
        self.sourceArtifactId = sourceArtifactId
        self.provenance = provenance
        self.startSeconds = startSeconds
        self.sourceStartSeconds = sourceStartSeconds
        self.durationSeconds = durationSeconds
        self.sourceDurationSeconds = sourceDurationSeconds
        self.loopPhaseSeconds = loopPhaseSeconds
        self.playbackRate = playbackRate
        self.pitchMode = pitchMode
        self.gain = gain
        self.isMuted = isMuted
        self.loops = loops
        self.fadeInSeconds = fadeInSeconds
        self.fadeOutSeconds = fadeOutSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        regionId = try container.decodeIfPresent(String.self, forKey: .regionId) ?? ""
        laneId = try container.decodeIfPresent(String.self, forKey: .laneId) ?? ""
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        mediaId = try container.decodeIfPresent(String.self, forKey: .mediaId) ?? ""
        sourceCutId = try container.decodeIfPresent(String.self, forKey: .sourceCutId) ?? ""
        sourceArtifactId = try container.decodeIfPresent(String.self, forKey: .sourceArtifactId) ?? ""
        provenance = try container.decodeIfPresent(String.self, forKey: .provenance) ?? ""
        startSeconds = try container.decodeIfPresent(Double.self, forKey: .startSeconds) ?? 0
        sourceStartSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceStartSeconds) ?? 0
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        sourceDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceDurationSeconds)
        loopPhaseSeconds = try container.decodeIfPresent(Double.self, forKey: .loopPhaseSeconds) ?? 0
        playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate) ?? 1
        pitchMode = (try? container.decodeIfPresent(ShotAudioPitchMode.self, forKey: .pitchMode)) ?? .preserve
        gain = try container.decodeIfPresent(Double.self, forKey: .gain) ?? 1
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        loops = try container.decodeIfPresent(Bool.self, forKey: .loops) ?? false
        fadeInSeconds = try container.decodeIfPresent(Double.self, forKey: .fadeInSeconds) ?? 0
        fadeOutSeconds = try container.decodeIfPresent(Double.self, forKey: .fadeOutSeconds) ?? 0
    }

    func normalized() -> ShotAudioRegion {
        var value = self
        value.regionId = value.regionId.trimmed
        value.laneId = value.laneId.trimmed.lowercased()
        value.label = value.label.trimmed
        value.path = value.path.trimmed
        value.mediaId = value.mediaId.trimmed
        value.sourceCutId = value.sourceCutId.trimmed
        value.sourceArtifactId = value.sourceArtifactId.trimmed
        value.provenance = value.provenance.trimmed
        value.startSeconds = max(value.startSeconds.isFinite ? value.startSeconds : 0, 0)
        value.sourceStartSeconds = max(value.sourceStartSeconds.isFinite ? value.sourceStartSeconds : 0, 0)
        value.durationSeconds = max(value.durationSeconds.isFinite ? value.durationSeconds : 0, 0)
        value.sourceDurationSeconds = value.sourceDurationSeconds.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }
        value.loopPhaseSeconds = max(value.loopPhaseSeconds.isFinite ? value.loopPhaseSeconds : 0, 0)
        if let sourceDurationSeconds = value.sourceDurationSeconds {
            value.loopPhaseSeconds = value.loopPhaseSeconds
                .truncatingRemainder(dividingBy: sourceDurationSeconds)
        }
        value.playbackRate = min(
            max(value.playbackRate.isFinite ? value.playbackRate : 1, Self.playbackRateRange.lowerBound),
            Self.playbackRateRange.upperBound
        )
        value.gain = min(max(value.gain.isFinite ? value.gain : 1, 0), 1)
        // Fades share the duration with fade-in priority, so any edit that
        // shrinks the region (trim, split, rate change) re-clamps its
        // envelope here instead of letting the ramps overlap.
        value.fadeInSeconds = max(value.fadeInSeconds.isFinite ? value.fadeInSeconds : 0, 0)
        value.fadeOutSeconds = max(value.fadeOutSeconds.isFinite ? value.fadeOutSeconds : 0, 0)
        value.fadeInSeconds = min(value.fadeInSeconds, value.durationSeconds)
        value.fadeOutSeconds = min(value.fadeOutSeconds, value.durationSeconds - value.fadeInSeconds)
        return value
    }

    // MARK: Geometry laws
    //
    // Every clamp lives here so gestures, inspector fields, and engine ops
    // share one truth. Each law floors durationSeconds at one frame —
    // `ProjectShot.normalized()` silently drops zero-duration regions, so a
    // clamp that reaches zero would delete the region instead of pinning it.

    /// Continuous move — deliberately NOT frame-quantized (drags are
    /// continuous; playhead placement quantizes at the call site). Keeps at
    /// least one frame of the region inside the timeline when the timeline
    /// length is known.
    func movedTo(startSeconds: Double, timelineSeconds: Double) -> ShotAudioRegion {
        var value = self
        let candidate = startSeconds.isFinite ? max(startSeconds, 0) : self.startSeconds
        if timelineSeconds > 0 {
            value.startSeconds = min(candidate, max(timelineSeconds - ShotAudioTiming.frameSeconds, 0))
        } else {
            value.startSeconds = candidate
        }
        return value.normalized()
    }

    /// Single commit for trim-in / trim-out / extend edits. Non-looping
    /// regions clamp honestly against the media's natural length when known;
    /// looping regions tile, so only the timeline bounds them. A looping
    /// region's in-point is ignored by playback (loops tile from the file
    /// start), so it passes through untouched.
    func applyingGeometry(
        startSeconds: Double,
        sourceStartSeconds: Double,
        durationSeconds: Double,
        timelineSeconds: Double
    ) -> ShotAudioRegion {
        var value = self
        let start = startSeconds.isFinite ? max(startSeconds, 0) : self.startSeconds
        var sourceStart = sourceStartSeconds.isFinite ? max(sourceStartSeconds, 0) : self.sourceStartSeconds
        var duration = durationSeconds.isFinite ? durationSeconds : self.durationSeconds
        if !loops, let mediaSeconds = self.sourceDurationSeconds {
            let minimumSourceSeconds = ShotAudioTiming.frameSeconds * playbackRate
            sourceStart = min(sourceStart, max(mediaSeconds - minimumSourceSeconds, 0))
            duration = min(
                duration,
                max((mediaSeconds - sourceStart) / playbackRate, ShotAudioTiming.frameSeconds)
            )
        }
        if timelineSeconds > 0 {
            duration = min(duration, max(timelineSeconds - start, ShotAudioTiming.frameSeconds))
        }
        value.startSeconds = start
        value.sourceStartSeconds = sourceStart
        value.durationSeconds = max(duration, ShotAudioTiming.frameSeconds)
        return value.normalized()
    }

    /// Divides one placement without changing what is heard. The left child
    /// retains the placement identity; the right child receives a fresh one.
    /// Non-looping media advances its source in-point, while looping media
    /// advances an internal phase so the next repeat does not restart at the
    /// edit boundary.
    func splitting(
        atSeconds: Double,
        rightRegionId: String
    ) -> (left: ShotAudioRegion, right: ShotAudioRegion)? {
        let split = ShotAudioTiming.frameQuantizedStart(atSeconds)
        let leftDuration = split - startSeconds
        let rightDuration = endSeconds - split
        guard rightRegionId.trimmed.nilIfEmpty != nil,
              split.isFinite,
              leftDuration >= ShotAudioTiming.frameSeconds,
              rightDuration >= ShotAudioTiming.frameSeconds else {
            return nil
        }

        var left = self
        left.durationSeconds = leftDuration
        // The split point is a hard cut: the outer fades stay with their
        // edges and the new boundary gets none.
        left.fadeOutSeconds = 0

        var right = self
        right.regionId = rightRegionId
        right.startSeconds = split
        right.durationSeconds = rightDuration
        right.fadeInSeconds = 0
        if loops {
            right.loopPhaseSeconds += leftDuration * playbackRate
        } else {
            right.sourceStartSeconds += leftDuration * playbackRate
        }
        return (left.normalized(), right.normalized())
    }

    /// Loop toggle. Turning loops OFF clamps the claimed duration back to the
    /// honest media remainder when the media length is known; turning it ON
    /// preserves geometry (tiling covers any length).
    func settingLoops(_ loops: Bool) -> ShotAudioRegion {
        var value = self
        value.loops = loops
        if !loops, let mediaSeconds = sourceDurationSeconds {
            let minimumSourceSeconds = ShotAudioTiming.frameSeconds * playbackRate
            value.sourceStartSeconds = min(
                value.sourceStartSeconds,
                max(mediaSeconds - minimumSourceSeconds, 0)
            )
            value.durationSeconds = min(
                value.durationSeconds,
                max(
                    (mediaSeconds - value.sourceStartSeconds) / playbackRate,
                    ShotAudioTiming.frameSeconds
                )
            )
        }
        return value.normalized()
    }

    /// Replace-media-in-place: the region keeps its placement (start, gain,
    /// mute, loops) and swaps identity. When the new file is shorter than the
    /// current trim and the region doesn't loop, the trim clamps honestly.
    /// This is also the relink-missing-file path: re-pick the asset and the
    /// path re-resolves from its record.
    func replacingMedia(
        path: String,
        mediaId: String,
        label: String,
        sourceDurationSeconds: Double?,
        provenance: String
    ) -> ShotAudioRegion {
        var value = self
        value.path = path
        value.mediaId = mediaId
        value.label = label
        value.sourceDurationSeconds = sourceDurationSeconds
        value.provenance = provenance
        value.sourceCutId = ""
        value.sourceArtifactId = ""
        if !loops, let newLength = sourceDurationSeconds {
            let minimumSourceSeconds = ShotAudioTiming.frameSeconds * playbackRate
            value.sourceStartSeconds = min(
                value.sourceStartSeconds,
                max(newLength - minimumSourceSeconds, 0)
            )
            value.durationSeconds = min(
                value.durationSeconds,
                max(
                    (newLength - value.sourceStartSeconds) / playbackRate,
                    ShotAudioTiming.frameSeconds
                )
            )
        }
        return value.normalized()
    }

    /// Sets the fade envelope. Values clamp non-negative and to the duration
    /// with fade-in priority — the same law `normalized()` re-applies after
    /// every geometry edit, so a fade can never outlive a later trim.
    func settingFades(fadeInSeconds: Double, fadeOutSeconds: Double) -> ShotAudioRegion {
        var value = self
        value.fadeInSeconds = fadeInSeconds
        value.fadeOutSeconds = fadeOutSeconds
        return value.normalized()
    }

    /// A paste or duplicate lands a CLONE: fresh identity, the target lane,
    /// the requested placement — and every clamp law applied through the
    /// existing geometry ops, so a cross-shot paste honestly re-clamps
    /// against the DESTINATION timeline while trim, gain, loops, rate,
    /// pitch, and fades all survive the trip.
    func pastedCopy(
        regionId: String,
        laneId: String,
        startSeconds: Double,
        timelineSeconds: Double
    ) -> ShotAudioRegion {
        var value = self
        value.regionId = regionId
        value.laneId = laneId
        let placed = value.movedTo(startSeconds: startSeconds, timelineSeconds: timelineSeconds)
        return placed.applyingGeometry(
            startSeconds: placed.startSeconds,
            sourceStartSeconds: placed.sourceStartSeconds,
            durationSeconds: placed.durationSeconds,
            timelineSeconds: timelineSeconds
        )
    }

    /// Changes playback without changing the selected source material. The
    /// start and in-point stay anchored; a non-looping region's endpoint moves
    /// inversely with rate. No timeline clamp applies here: slowed material may
    /// retain recoverable overhang beyond the CUT while playback/export remain
    /// bounded by the picture composition. Loops have no finite source out, so
    /// their authored placement length stays fixed and only cadence changes.
    func settingPlayback(rate: Double, pitchMode: ShotAudioPitchMode) -> ShotAudioRegion {
        var value = self
        let oldRate = playbackRate
        let clampedRate = min(
            max(rate.isFinite ? rate : oldRate, Self.playbackRateRange.lowerBound),
            Self.playbackRateRange.upperBound
        )
        if !loops {
            value.durationSeconds = max(
                selectedSourceDurationSeconds / clampedRate,
                ShotAudioTiming.frameSeconds
            )
        }
        value.playbackRate = clampedRate
        value.pitchMode = pitchMode
        return value.normalized()
    }
}

struct CombinedCutPreflight: Hashable, Sendable {
    var sourceCutIds: [String] = []
    var sourceNames: [String] = []
    var frameCount: Int = 0
    var footageCount: Int = 0
    var reusableSegmentCount: Int = 0
    var missingSegmentCount: Int = 0
    var audioRegionCount: Int = 0
    var activeLookCount: Int = 0
    var estimatedSeconds: Double = 0
    var warnings: [String] = []
    var hardFailures: [String] = []

    var canCombine: Bool { sourceCutIds.count >= 2 && hardFailures.isEmpty }
    var hasCompleteReusableVideo: Bool {
        reusableSegmentCount > 0 && missingSegmentCount == 0
    }
}

struct CombinedCutBuildResult {
    var cut: ProjectShot
    var preflight: CombinedCutPreflight
}

private struct CombinedCutSourcePlan {
    var shot: ProjectShot
    var plan: (
        segments: [ShotRenderPlanSegment],
        generatedItems: [ShotSegmentPromptPlanItem],
        skipped: [String],
        strands: [MeaningStrand],
        skippedPlaceholders: [ShotSkippedSegmentPlaceholder]
    )
    var assembly: ShotCutAssembly
    var outputSeconds: Double
}

/// Pure copy engine. Every entry and placement gets a fresh id; readable
/// segment media becomes a seed clip, never a ready render version.
func buildCombinedCut(
    sources: [ProjectShot],
    frameLookup: [String: ProjectLensHeroImage],
    mediaLookup: [String: MediaItemRecord],
    meaningNodes: [LensContextPromptMeaningNode],
    now: String,
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> CombinedCutBuildResult {
    var preflight = CombinedCutPreflight(
        sourceCutIds: sources.map(\.shotId),
        sourceNames: sources.map { $0.name.trimmed.nilIfEmpty ?? "Untitled CUT" }
    )
    guard sources.count >= 2 else {
        preflight.hardFailures = ["Choose two adjacent CUTs."]
        return CombinedCutBuildResult(cut: ProjectShot(), preflight: preflight)
    }
    if sources.contains(where: { $0.shotId.trimmed.isEmpty }) {
        preflight.hardFailures.append("A source CUT record is invalid.")
    }

    let sourcePlans: [CombinedCutSourcePlan] = sources.map { source in
        let plan = shotRenderSegmentPlan(
            shot: source,
            frameLookup: frameLookup,
            mediaLookup: mediaLookup,
            meaningNodes: meaningNodes
        )
        let assembly = shotCutAssembly(
            shot: source,
            planSegments: plan.segments,
            clipDurationsByPath: [:],
            fileExists: fileExists
        )
        let generatedSeconds = plan.generatedItems.reduce(0.0) {
            $0 + Double($1.renderStack.segmentSeconds)
        }
        let estimate = Double(
            shotRuntimeSummary(
                shot: source,
                frameLookup: frameLookup,
                mediaLookup: mediaLookup
            ).estimatedSeconds(generatedSeconds: generatedSeconds)
        )
        return CombinedCutSourcePlan(
            shot: source,
            plan: plan,
            assembly: assembly,
            outputSeconds: max(assembly.outputSeconds, estimate)
        )
    }

    let parentCutId = "shot_\(shortHash("combined:\(sources.map(\.shotId).joined(separator: ":")):\(now):\(UUID().uuidString)", length: 12))"
    var parentEntries: [ShotFrameEntry] = []
    var combinedSources: [ShotCombinedSource] = []
    var sourceBoundaries: [ShotSourceBoundary] = []
    var seedClips: [ShotRenderSegmentClip] = []
    var promptOverrides: [ShotSegmentPromptOverride] = []
    var renderOverrides: [ShotSegmentRenderOverride] = []
    var audioRegions: [ShotAudioRegion] = []
    var parentCuts: [ShotSegmentCutRange] = []
    var parentJoinBridges: [ShotJoinBridgeArtifact] = []
    var outputCursor = 0.0

    for (sourceIndex, sourcePlan) in sourcePlans.enumerated() {
        let source = sourcePlan.shot
        var entryMap: [String: String] = [:]
        var copiedEntries: [ShotFrameEntry] = []
        for sourceEntry in source.entries {
            var copy = sourceEntry
            copy.entryId = "entry_\(shortHash("\(parentCutId):\(source.shotId):\(sourceEntry.entryId):\(UUID().uuidString)", length: 12))"
            entryMap[sourceEntry.entryId] = copy.entryId
            copiedEntries.append(copy)
        }
        for inheritedBoundary in source.sourceBoundaries {
            guard let rightEntryId = entryMap[inheritedBoundary.rightEntryId] else { continue }
            var copy = inheritedBoundary
            let identity = "\(parentCutId):\(source.shotId):\(inheritedBoundary.boundaryId)"
            copy.boundaryId = "boundary_\(shortHash(identity, length: 12))"
            copy.rightEntryId = rightEntryId
            copy.createdAt = now
            sourceBoundaries.append(copy.normalized())
        }
        if sourceIndex > 0, !copiedEntries.isEmpty {
            copiedEntries[0].leadTransition = ShotSeamStyle.cut.rawValue
            let firstVisibleIndex = copiedEntries.firstIndex(where: { !$0.isSkipped }) ?? 0
            copiedEntries[firstVisibleIndex].leadTransition = ShotSeamStyle.cut.rawValue
            let firstVisibleEntryId = copiedEntries[firstVisibleIndex].entryId
            sourceBoundaries.append(ShotSourceBoundary(
                boundaryId: "boundary_\(shortHash("\(parentCutId):\(sources[sourceIndex - 1].shotId):\(source.shotId)", length: 12))",
                leftSourceCutId: sources[sourceIndex - 1].shotId,
                rightSourceCutId: source.shotId,
                rightEntryId: firstVisibleEntryId,
                createdAt: now
            ))
        }
        parentEntries.append(contentsOf: copiedEntries)

        combinedSources.append(ShotCombinedSource(
            sourceId: "combined_source_\(shortHash("\(parentCutId):\(source.shotId)", length: 12))",
            sourceCutId: source.shotId,
            sourceCutName: source.name,
            sourceEntryIds: source.entries.map(\.entryId),
            sourceRenderVersionId: source.playableRenderVersion?.versionId ?? "",
            parentEntryIds: copiedEntries.map(\.entryId),
            outputStartSeconds: outputCursor,
            outputDurationSeconds: sourcePlan.outputSeconds,
            hadActiveLook: source.activeLookVersion != nil
        ))

        preflight.frameCount += source.entries.filter { !$0.isClip && !$0.isAIExtension }.count
        preflight.footageCount += source.entries.filter(\.isClip).count
        if source.activeLookVersion != nil {
            preflight.activeLookCount += 1
        }
        if source.entries.isEmpty {
            preflight.warnings.append("\(source.name.trimmed.nilIfEmpty ?? "A source CUT") is empty.")
        }
        if !sourcePlan.plan.skipped.isEmpty {
            preflight.warnings.append("\(source.name.trimmed.nilIfEmpty ?? "A source CUT") has \(sourcePlan.plan.skipped.count) unavailable item\(sourcePlan.plan.skipped.count == 1 ? "" : "s").")
        }
        // A combined CUT is always a new forward edit: the fresh cut list drops
        // the reverse flag, and the reversed proxies belong to the source's own
        // clip paths. Say so, because the source's audio placements were made
        // against reversed playback and arrive here at those positions.
        if source.cutList.isReversed {
            preflight.warnings.append("\(source.name.trimmed.nilIfEmpty ?? "A source CUT") combines as its forward edit; its audio placements were made against the reversed playback.")
        }
        // A combined CUT copies MATERIAL (entries, razors, regions); the
        // whole-output loop is an assembly-time repeat and cannot ride along —
        // the fresh cut list at the end of this build drops it with reverse.
        if source.cutList.normalized().outputLoopCount > 1 {
            preflight.warnings.append("\(source.name.trimmed.nilIfEmpty ?? "A source CUT") loops ×\(source.cutList.normalized().outputLoopCount) — the combined CUT carries its material once.")
        }

        func parentPlacement(for pair: ShotRenderPair) -> (String, String) {
            (
                entryMap[pair.startPlacementEntryId] ?? "",
                entryMap[pair.endPlacementEntryId] ?? ""
            )
        }

        func reusableSourceClip(
            placementStartEntryId: String,
            placementEndEntryId: String,
            startFrameImageId: String,
            endFrameImageId: String
        ) -> ShotRenderSegmentClip? {
            if let rendered = source.playableRenderVersion?.segmentClip(
                placementStartEntryId: placementStartEntryId,
                placementEndEntryId: placementEndEntryId,
                forStart: startFrameImageId,
                end: endFrameImageId
            ) {
                return rendered
            }
            if !placementStartEntryId.isEmpty || !placementEndEntryId.isEmpty,
               let exact = source.seedSegmentClips.first(where: {
                   $0.placementStartEntryId == placementStartEntryId
                       && $0.placementEndEntryId == placementEndEntryId
               }) {
                return exact
            }
            return source.seedSegmentClips.first {
                $0.placementStartEntryId.isEmpty
                    && $0.placementEndEntryId.isEmpty
                    && $0.startFrameImageId == startFrameImageId
                    && $0.endFrameImageId == endFrameImageId
            }
        }

        var parentKeyBySourceKey: [String: String] = [:]
        for segment in sourcePlan.plan.segments {
            switch segment {
            // Never in plan-generator output (assembly-only fallback band).
            case .artifactFallback:
                break
            case .generated(let item):
                let placement = parentPlacement(for: item.pair)
                let parentKey = shotPlacementSegmentKey(
                    startEntryId: placement.0,
                    endEntryId: placement.1,
                    legacyStartId: item.pair.start?.imageId ?? "",
                    legacyEndId: item.pair.end?.imageId ?? ""
                )
                parentKeyBySourceKey[item.pair.placementKey] = parentKey
                parentKeyBySourceKey[item.pair.segmentKey] = parentKey
                let saved = reusableSourceClip(
                    placementStartEntryId: item.pair.startPlacementEntryId,
                    placementEndEntryId: item.pair.endPlacementEntryId,
                    startFrameImageId: item.pair.start?.imageId ?? "",
                    endFrameImageId: item.pair.end?.imageId ?? ""
                )
                if var saved, fileExists(saved.clipPath) {
                    saved.placementStartEntryId = placement.0
                    saved.placementEndEntryId = placement.1
                    if saved.sourceCutId.isEmpty { saved.sourceCutId = source.shotId }
                    if saved.sourceRenderVersionId.isEmpty {
                        saved.sourceRenderVersionId = source.playableRenderVersion?.versionId ?? ""
                    }
                    seedClips.append(saved)
                    preflight.reusableSegmentCount += 1
                } else {
                    preflight.missingSegmentCount += 1
                }
                if let override = item.overridePrompt?.trimmed.nilIfEmpty {
                    promptOverrides.append(ShotSegmentPromptOverride(
                        startFrameImageId: item.pair.start?.imageId ?? "",
                        endFrameImageId: item.pair.end?.imageId ?? "",
                        placementStartEntryId: placement.0,
                        placementEndEntryId: placement.1,
                        prompt: override,
                        updatedAt: now
                    ))
                }
                if item.hasRenderOverride {
                    renderOverrides.append(ShotSegmentRenderOverride(
                        startFrameImageId: item.pair.start?.imageId ?? "",
                        endFrameImageId: item.pair.end?.imageId ?? "",
                        placementStartEntryId: placement.0,
                        placementEndEntryId: placement.1,
                        stack: item.renderStack.rawValue,
                        updatedAt: now
                    ))
                }
            case .footage(let footage):
                let parentEntryId = entryMap[footage.clip.entryId] ?? ""
                let parentKey = shotPlacementSegmentKey(
                    startEntryId: parentEntryId,
                    endEntryId: "",
                    legacyStartId: footage.clip.footageKey,
                    legacyEndId: ""
                )
                parentKeyBySourceKey["entry:\(footage.clip.entryId)>"] = parentKey
                parentKeyBySourceKey["\(footage.clip.footageKey)>"] = parentKey
                let saved = reusableSourceClip(
                    placementStartEntryId: footage.clip.entryId,
                    placementEndEntryId: "",
                    startFrameImageId: footage.clip.footageKey,
                    endFrameImageId: ""
                )
                if var saved, fileExists(saved.clipPath) {
                    saved.placementStartEntryId = parentEntryId
                    saved.placementEndEntryId = ""
                    if saved.sourceCutId.isEmpty { saved.sourceCutId = source.shotId }
                    if saved.sourceRenderVersionId.isEmpty {
                        saved.sourceRenderVersionId = source.playableRenderVersion?.versionId ?? ""
                    }
                    seedClips.append(saved)
                    preflight.reusableSegmentCount += 1
                } else if fileExists(footage.clip.path) {
                    seedClips.append(ShotRenderSegmentClip(
                        startFrameImageId: footage.clip.footageKey,
                        endFrameImageId: "",
                        placementStartEntryId: parentEntryId,
                        placementEndEntryId: "",
                        clipPath: footage.clip.path,
                        provider: "footage",
                        model: "source",
                        requestedDurationSeconds: 0,
                        durationSeconds: footage.clip.resolvedDurationSeconds,
                        sourceCutId: source.shotId,
                        sourceRenderVersionId: source.playableRenderVersion?.versionId ?? "",
                        updatedAt: now
                    ))
                    preflight.reusableSegmentCount += 1
                } else {
                    preflight.missingSegmentCount += 1
                }
            }
        }

        for sourceCut in source.cutList.segmentCuts {
            guard let parentKey = parentKeyBySourceKey[sourceCut.segmentKey] else { continue }
            var copy = sourceCut
            copy.cutId = "cut_\(shortHash("\(parentCutId):\(sourceCut.cutId):\(UUID().uuidString)", length: 14))"
            copy.segmentKey = parentKey
            if sourceCut.joinRepair.mode == .generatedBridge,
               let sourceBridge = source.joinBridgeVersion(sourceCut.joinRepair.activeBridgeVersionId),
               sourceBridge.isReady,
               fileExists(sourceBridge.videoPath) {
                var bridge = sourceBridge
                bridge.versionId = "join_\(shortHash("\(parentCutId):\(sourceBridge.versionId):\(UUID().uuidString)", length: 14))"
                bridge.cutId = copy.cutId
                bridge.sourceSegmentKey = parentKey
                bridge.updatedAt = now
                parentJoinBridges.append(bridge)
                copy.joinRepair.activeBridgeVersionId = bridge.versionId
            } else if sourceCut.joinRepair.mode == .generatedBridge {
                copy.joinRepair = ShotRazorJoinRepair(
                    mode: .hardCut,
                    dissolveFrames: sourceCut.joinRepair.dissolveFrames
                )
            }
            copy.updatedAt = now
            parentCuts.append(copy)
        }

        // Convert source-level in/out handles into placement-local razor
        // ranges so each source section keeps its visible edit after the
        // parent drops the source shot's global handle pair.
        let sourceIn = source.cutList.shotInSeconds ?? 0
        let sourceOut = source.cutList.shotOutSeconds ?? .infinity
        for clip in sourcePlan.assembly.planClips {
            guard let parentKey = parentKeyBySourceKey[clip.segmentKey] else { continue }
            let materialStart = clip.materialStartSeconds
            let materialEnd = materialStart + clip.materialSeconds
            let allowedStart = min(max(sourceIn, materialStart), materialEnd)
            let allowedEnd = min(max(sourceOut, materialStart), materialEnd)
            let localStart = clip.headSeconds
            let localEnd = clip.headSeconds + clip.materialSeconds
            let keepStart = localStart + max(allowedStart - materialStart, 0)
            let keepEnd = localStart + max(allowedEnd - materialStart, 0)
            func appendTrim(start: Double, end: Double, suffix: String) {
                guard end - start >= ShotCutList.minimumRangeSeconds else { return }
                parentCuts.append(ShotSegmentCutRange(
                    cutId: "cut_\(shortHash("\(parentCutId):\(source.shotId):\(parentKey):\(suffix)", length: 14))",
                    segmentKey: parentKey,
                    clipPath: "",
                    startSeconds: start,
                    endSeconds: end,
                    updatedAt: now
                ))
            }
            appendTrim(start: localStart, end: keepStart, suffix: "source_in")
            appendTrim(start: max(keepEnd, keepStart), end: localEnd, suffix: "source_out")
        }

        // Precedence law at combine time: a regionized ordinary source has
        // overlay regions but its source audio is still the composition
        // tracks, so the source-lane gain window keys off the SOURCE lane
        // alone; and its singleton fields are inert mirrors, so the singleton
        // import runs only for fully legacy sources — otherwise every overlay
        // would arrive twice.
        let sourceLane = source.audioMix.lane(ShotAudioLaneId.source)
        if !source.audioRegions.contains(where: { $0.laneId == ShotAudioLaneId.source }),
           sourcePlan.outputSeconds > 0 {
            audioRegions.append(ShotAudioRegion(
                regionId: "audio_region_\(shortHash("\(parentCutId):\(source.shotId):source", length: 12))",
                laneId: ShotAudioLaneId.source,
                label: source.name.trimmed.nilIfEmpty ?? "Source",
                sourceCutId: source.shotId,
                sourceArtifactId: source.playableRenderVersion?.versionId ?? "",
                provenance: "combined_source",
                startSeconds: outputCursor,
                durationSeconds: sourcePlan.outputSeconds,
                gain: sourceLane.volume,
                isMuted: !sourceLane.isEnabled
            ))
        }
        for inherited in source.audioRegions {
            let localStart = max(inherited.startSeconds, 0)
            let duration = min(
                inherited.durationSeconds,
                max(sourcePlan.outputSeconds - localStart, 0)
            )
            guard duration > 0 else { continue }
            var copy = inherited
            let identity = "\(parentCutId):\(source.shotId):\(inherited.regionId)"
            copy.regionId = "audio_region_\(shortHash(identity, length: 12))"
            copy.sourceCutId = copy.sourceCutId.trimmed.nilIfEmpty ?? source.shotId
            copy.startSeconds = outputCursor + localStart
            copy.durationSeconds = duration
            audioRegions.append(copy.normalized())
        }
        if source.audioRegions.isEmpty {
            audioRegions.append(contentsOf: legacySingletonAudioRegions(
                from: source,
                idSeed: parentCutId,
                outputOffset: outputCursor,
                sourceDuration: sourcePlan.outputSeconds,
                startingIndex: audioRegions.count,
                clipMediaDurationSeconds: source.audioMix.lane(ShotAudioLaneId.clip).clipMediaId
                    .flatMap { mediaLookup[$0]?.durationSeconds }
            ))
        }
        outputCursor += sourcePlan.outputSeconds
    }

    if preflight.activeLookCount > 0 {
        preflight.warnings.append("Active source Looks stay on their source CUTs; the combined CUT starts on Original.")
    }
    if preflight.reusableSegmentCount == 0 {
        preflight.warnings.append("No rendered video can be reused. The combined timeline remains editable and can be rendered later.")
    }
    preflight.audioRegionCount = audioRegions.filter { $0.laneId != ShotAudioLaneId.source }.count
    preflight.estimatedSeconds = outputCursor

    var parentMix = ShotAudioMix()
    for laneId in [
        ShotAudioLaneId.source,
        ShotAudioLaneId.narration,
        ShotAudioLaneId.microphone,
        ShotAudioLaneId.ambient,
        ShotAudioLaneId.clip
    ] {
        let hasAudible = audioRegions.contains { $0.laneId == laneId && !$0.isMuted }
        parentMix = parentMix
            .settingLaneEnabled(laneId, enabled: hasAudible)
            .settingLaneVolume(laneId, volume: 1)
    }

    let parent = ProjectShot(
        shotId: parentCutId,
        name: sources.map { $0.name.trimmed.nilIfEmpty ?? "CUT" }.joined(separator: " + "),
        entries: parentEntries,
        audioMix: parentMix,
        preferredRenderStack: sources.first?.preferredRenderStack ?? "",
        segmentPromptOverrides: promptOverrides,
        segmentRenderOverrides: renderOverrides,
        joinBridgeVersions: parentJoinBridges,
        cutList: ShotCutList(segmentCuts: parentCuts),
        combinedSources: combinedSources,
        sourceBoundaries: sourceBoundaries,
        seedSegmentClips: seedClips,
        audioRegions: audioRegions,
        createdAt: now,
        updatedAt: now
    ).normalized()
    return CombinedCutBuildResult(cut: parent, preflight: preflight)
}

/// The four singleton overlays (narration artifact, active mic take, ambient
/// bed, imported clip) expressed as regions. Shared by combine-time import
/// and migrate-on-write regionization so the two conversions can never
/// drift. `sourceDuration <= 0` means "section length unknown" (regionizing
/// an unrendered shot): each overlay then keeps its own media length.
/// `includeDisabledAsMuted` converts disabled lanes as muted regions —
/// regionization must not lose attached material; combine keeps its
/// audible-snapshot behavior and skips them. `stableIds` keys each region by
/// its stable artifact/media identity instead of the running index, so
/// regionization is deterministic and the lane UI can preview the exact
/// regions a first edit will persist.
func legacySingletonAudioRegions(
    from source: ProjectShot,
    idSeed: String,
    outputOffset: Double,
    sourceDuration: Double,
    startingIndex: Int = 0,
    includeDisabledAsMuted: Bool = false,
    ambientBedDurationSeconds: Double? = nil,
    clipMediaDurationSeconds: Double? = nil,
    stableIds: Bool = false
) -> [ShotAudioRegion] {
    var regions: [ShotAudioRegion] = []
    func append(
        laneId: String,
        label: String,
        path: String,
        mediaId: String = "",
        artifactId: String = "",
        provenance: String,
        localStart: Double,
        duration: Double,
        mediaSeconds: Double?,
        loops: Bool = false
    ) {
        let lane = source.audioMix.lane(laneId)
        guard lane.isEnabled || includeDisabledAsMuted else { return }
        let sectionRemaining = sourceDuration > 0
            ? max(sourceDuration - max(localStart, 0), 0)
            : Double.infinity
        let clamped = min(duration, sectionRemaining)
        guard !path.trimmed.isEmpty, clamped > 0, clamped.isFinite else { return }
        let identity = stableIds
            ? "\(idSeed):\(laneId):\(artifactId.trimmed.nilIfEmpty ?? mediaId.trimmed.nilIfEmpty ?? "")"
            : "\(idSeed):\(source.shotId):\(laneId):\(startingIndex + regions.count)"
        regions.append(ShotAudioRegion(
            regionId: "audio_region_\(shortHash(identity, length: 12))",
            laneId: laneId,
            label: label,
            path: path,
            mediaId: mediaId,
            sourceCutId: source.shotId,
            sourceArtifactId: artifactId,
            provenance: provenance,
            startSeconds: outputOffset + max(localStart, 0),
            durationSeconds: clamped,
            sourceDurationSeconds: mediaSeconds,
            gain: lane.volume,
            isMuted: !lane.isEnabled,
            loops: loops
        ))
    }

    // An unnamed shot gets the bare lane name — a "· CUT" suffix reads as a
    // mysterious state (it was mistaken for the cut layer), not as a name.
    let sourceNameSuffix = source.name.trimmed.isEmpty ? "" : " · \(source.name.trimmed)"
    if let narration = source.narrationArtifact, narration.isReady {
        append(
            laneId: ShotAudioLaneId.narration,
            label: "Narration\(sourceNameSuffix)",
            path: narration.audioPath,
            artifactId: narration.traceId,
            provenance: "active_narration",
            localStart: source.audioMix.lane(ShotAudioLaneId.narration).effectiveStartSeconds,
            duration: narration.durationSeconds,
            mediaSeconds: narration.durationSeconds > 0 ? narration.durationSeconds : nil
        )
    }
    if let take = source.audioMix.activeMicrophoneTake {
        append(
            laneId: ShotAudioLaneId.microphone,
            label: "Mic\(sourceNameSuffix)",
            path: take.path,
            artifactId: take.takeId,
            provenance: "active_microphone_take",
            localStart: take.startSeconds,
            duration: take.durationSeconds,
            mediaSeconds: take.durationSeconds > 0 ? take.durationSeconds : nil
        )
    }
    let ambient = source.audioMix.lane(ShotAudioLaneId.ambient)
    if let path = ambient.ambientBedPath {
        append(
            laneId: ShotAudioLaneId.ambient,
            label: "Ambient\(sourceNameSuffix)",
            path: path,
            artifactId: ambient.ambientBedId ?? "",
            provenance: "ambient_bed",
            localStart: 0,
            duration: sourceDuration > 0 ? sourceDuration : (ambientBedDurationSeconds ?? 0),
            mediaSeconds: ambientBedDurationSeconds,
            loops: true
        )
    }
    let clip = source.audioMix.lane(ShotAudioLaneId.clip)
    if let path = clip.clipPath {
        // Honest length: a known media duration bounds the region instead of
        // painting it to the end of the section. The mixer always clamped
        // playback at the file's real length; now the model agrees with it.
        let fillToEnd = sourceDuration > 0
            ? max(sourceDuration - clip.effectiveStartSeconds, 0)
            : (clipMediaDurationSeconds ?? 0)
        append(
            laneId: ShotAudioLaneId.clip,
            label: "Clip\(sourceNameSuffix)",
            path: path,
            mediaId: clip.clipMediaId ?? "",
            provenance: "imported_audio",
            localStart: clip.effectiveStartSeconds,
            duration: min(clipMediaDurationSeconds ?? fillToEnd, fillToEnd),
            mediaSeconds: clipMediaDurationSeconds
        )
    }
    return regions
}

extension ProjectShot {
    /// The exact regions `regionizingLegacyAudio` would persist — pure and
    /// deterministic (stable ids keyed on artifact/media identity), so the
    /// lane UI can PREVIEW legacy singleton overlays as gesture-capable
    /// regions before the first edit: a gesture commit references the
    /// previewed regionId, the engine regionizes first, and the ids match by
    /// construction. Empty once the shot carries persisted regions. Beyond
    /// the shared active-overlay conversion, every INACTIVE microphone take
    /// converts as a muted region so the take chooser keeps working
    /// (activation = swapping mutes) and no recorded material is stranded.
    func legacyAudioRegionPreview(
        timelineSeconds: Double,
        ambientBedDurationSeconds: Double? = nil,
        clipMediaDurationSeconds: Double? = nil
    ) -> [ShotAudioRegion] {
        guard audioRegions.isEmpty else { return [] }
        var converted = legacySingletonAudioRegions(
            from: self,
            idSeed: "regionize:\(shotId)",
            outputOffset: 0,
            sourceDuration: timelineSeconds,
            includeDisabledAsMuted: true,
            ambientBedDurationSeconds: ambientBedDurationSeconds,
            clipMediaDurationSeconds: clipMediaDurationSeconds,
            stableIds: true
        )
        let microphoneLane = audioMix.lane(ShotAudioLaneId.microphone)
        let activeTakeId = microphoneLane.activeMicrophoneTake?.takeId ?? ""
        for take in microphoneLane.microphoneTakes
            where take.takeId != activeTakeId && !take.path.trimmed.isEmpty && take.durationSeconds > 0 {
            converted.append(ShotAudioRegion(
                regionId: "audio_region_\(shortHash("regionize:\(shotId):\(ShotAudioLaneId.microphone):\(take.takeId)", length: 12))",
                laneId: ShotAudioLaneId.microphone,
                label: "Mic take",
                path: take.path,
                sourceCutId: shotId,
                sourceArtifactId: take.takeId,
                provenance: "microphone_take",
                startSeconds: take.startSeconds,
                durationSeconds: take.durationSeconds,
                sourceDurationSeconds: take.durationSeconds,
                gain: microphoneLane.volume,
                isMuted: true
            ).normalized())
        }
        return converted
    }

    /// Migrate-on-write: expresses the shot's singleton audio overlays as
    /// regions so a region edit can proceed on ANY cut. No-op when regions
    /// already exist or nothing converts. Never clears the singleton fields —
    /// the precedence law (`applyMix`) makes them inert, which is also the
    /// downgrade story for older builds. Singleton lane mute/level transfers
    /// into each converted region, then those lanes reset to neutral so the
    /// same control is not multiplied at both layers.
    func regionizingLegacyAudio(
        now: String,
        timelineSeconds: Double,
        ambientBedDurationSeconds: Double? = nil,
        clipMediaDurationSeconds: Double? = nil
    ) -> ProjectShot {
        guard audioRegions.isEmpty else { return self }
        let converted = legacyAudioRegionPreview(
            timelineSeconds: timelineSeconds,
            ambientBedDurationSeconds: ambientBedDurationSeconds,
            clipMediaDurationSeconds: clipMediaDurationSeconds
        )
        guard !converted.isEmpty else { return self }
        var value = settingAudioRegions(converted, now: now)
        let convertedLaneIds = Set(converted.map(\.laneId))
        value.audioMix = value.audioMix.neutralizingLanes(convertedLaneIds)
        return value
    }

    func settingAudioRegions(_ regions: [ShotAudioRegion], now: String) -> ProjectShot {
        var value = self
        value.audioRegions = regions.map { $0.normalized() }
        value.updatedAt = now
        return value
    }

    func sourceSegmentAudio(forSegmentKey segmentKey: String) -> ShotSourceSegmentAudio? {
        sourceSegmentAudio.first { $0.segmentKey == segmentKey }
    }

    /// Upsert-or-drop: intent equal to the default is absence, so setting a
    /// segment back to audible at full gain removes its row rather than
    /// persisting a row that says nothing.
    func settingSourceSegmentAudio(
        segmentKey: String,
        startFrameImageId: String,
        endFrameImageId: String,
        placementStartEntryId: String,
        placementEndEntryId: String,
        gain: Double,
        isMuted: Bool,
        now: String
    ) -> ProjectShot {
        guard !segmentKey.isEmpty else { return self }
        var value = self
        value.sourceSegmentAudio.removeAll { $0.segmentKey == segmentKey }
        let row = ShotSourceSegmentAudio(
            startFrameImageId: startFrameImageId,
            endFrameImageId: endFrameImageId,
            placementStartEntryId: placementStartEntryId,
            placementEndEntryId: placementEndEntryId,
            gain: gain,
            isMuted: isMuted,
            updatedAt: now
        ).normalized()
        if !row.isNoOp {
            value.sourceSegmentAudio.append(row)
        }
        guard value.sourceSegmentAudio != sourceSegmentAudio else { return self }
        value.updatedAt = now
        return value
    }

    /// Wholesale restore — the undo primitive, mirroring `settingAudioRegions`.
    func settingAllSourceSegmentAudio(_ rows: [ShotSourceSegmentAudio], now: String) -> ProjectShot {
        var value = self
        value.sourceSegmentAudio = rows.map { $0.normalized() }.filter { !$0.isNoOp }
        value.updatedAt = now
        return value
    }

    func ripplingAudioRegions(
        atOrAfter thresholdSeconds: Double,
        by deltaSeconds: Double,
        now: String
    ) -> ProjectShot {
        guard abs(deltaSeconds) >= ShotAudioTiming.frameSeconds / 2 else { return self }
        var value = self
        let threshold = max(thresholdSeconds, 0)
        for index in value.audioRegions.indices
            where value.audioRegions[index].laneId != ShotAudioLaneId.source
                && value.audioRegions[index].startSeconds + 0.000_1 >= threshold {
            value.audioRegions[index].startSeconds = max(
                value.audioRegions[index].startSeconds + deltaSeconds,
                0
            )
        }
        value.updatedAt = now
        return value
    }

    func updatingAudioRegion(
        regionId: String,
        now: String,
        _ transform: (inout ShotAudioRegion) -> Void
    ) -> ProjectShot {
        guard let index = audioRegions.firstIndex(where: { $0.regionId == regionId }) else { return self }
        var value = self
        transform(&value.audioRegions[index])
        value.audioRegions[index] = value.audioRegions[index].normalized()
        value.updatedAt = now
        return value
    }

    func removingAudioRegion(regionId: String, now: String) -> ProjectShot {
        var value = self
        value.audioRegions.removeAll { $0.regionId == regionId }
        value.updatedAt = now
        return value
    }
}
