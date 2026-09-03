import Foundation
import Testing
@testable import LitScenes

// Pure-model coverage for the unified audio-region laws: migrate-on-write
// regionization, the geometry/loop/replace clamps, the combine-time
// precedence fix, and the timing helpers behind direct manipulation.

private let frame = ShotAudioTiming.frameSeconds

private func legacyShot(
    shotId: String = "cut_legacy",
    narration: Bool = true,
    micTakes: [ShotMicrophoneTake] = [],
    ambientBedId: String? = nil,
    clipMediaId: String? = nil
) -> ProjectShot {
    var mix = ShotAudioMix()
        .settingLaneVolume(ShotAudioLaneId.narration, volume: 0.7)
        .settingNarrationStartSeconds(1)
    for take in micTakes {
        mix = mix.appendingMicrophoneTake(take)
    }
    if let ambientBedId {
        mix = mix.settingAmbientBed(bedId: ambientBedId, path: "/audio/\(ambientBedId).m4a")
    }
    if let clipMediaId {
        mix = mix.settingAudioClip(mediaId: clipMediaId, path: "/audio/\(clipMediaId).mp3")
    }
    return ProjectShot(
        shotId: shotId,
        name: "Legacy",
        entries: [ShotFrameEntry(entryId: "e1", frameImageId: "f1")],
        narrationArtifact: narration
            ? ShotNarrationArtifact(status: "ready", audioPath: "/audio/narration.m4a", durationSeconds: 2)
            : nil,
        audioMix: mix,
        createdAt: "t0",
        updatedAt: "t0"
    )
}

private func testFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        label: id.uppercased(),
        provider: "test",
        imagePath: "/frames/\(id).png",
        status: "ready"
    )
}

// MARK: - Regionization

@Test func regionizingLegacyAudioConvertsAllSingletonsAndIsIdempotent() throws {
    let take = ShotMicrophoneTake(
        takeId: "take_active",
        path: "/audio/take_active.m4a",
        startSeconds: 3,
        durationSeconds: 4,
        createdAt: "t0"
    )
    let older = ShotMicrophoneTake(
        takeId: "take_older",
        path: "/audio/take_older.m4a",
        startSeconds: 1,
        durationSeconds: 2,
        createdAt: "s0"
    )
    let shot = legacyShot(
        micTakes: [older, take],
        ambientBedId: "bed_1",
        clipMediaId: "clip_1"
    )
    let regionized = shot.regionizingLegacyAudio(
        now: "t1",
        timelineSeconds: 12,
        ambientBedDurationSeconds: 6,
        clipMediaDurationSeconds: 5
    )

    let narration = try #require(regionized.audioRegions.first { $0.laneId == ShotAudioLaneId.narration })
    #expect(narration.startSeconds == 1)
    #expect(narration.durationSeconds == 2)
    #expect(narration.sourceDurationSeconds == 2)
    #expect(narration.gain == 0.7)
    #expect(narration.provenance == "active_narration")

    let micRegions = regionized.audioRegions.filter { $0.laneId == ShotAudioLaneId.microphone }
    #expect(micRegions.count == 2)
    let active = try #require(micRegions.first { $0.sourceArtifactId == "take_active" })
    #expect(!active.isMuted)
    #expect(active.startSeconds == 3)
    let inactive = try #require(micRegions.first { $0.sourceArtifactId == "take_older" })
    #expect(inactive.isMuted)
    #expect(inactive.provenance == "microphone_take")

    let ambient = try #require(regionized.audioRegions.first { $0.laneId == ShotAudioLaneId.ambient })
    #expect(ambient.loops)
    #expect(ambient.durationSeconds == 12)
    #expect(ambient.sourceDurationSeconds == 6)

    let clip = try #require(regionized.audioRegions.first { $0.laneId == ShotAudioLaneId.clip })
    // Honest length: the clip claims its media's real length, not the
    // timeline fill.
    #expect(clip.durationSeconds == 5)
    #expect(clip.sourceDurationSeconds == 5)

    // Singleton mirrors are never cleared — the precedence law makes them
    // inert instead (the downgrade story for older builds).
    #expect(regionized.narrationArtifact != nil)
    #expect(regionized.audioMix.lane(ShotAudioLaneId.clip).clipMediaId == "clip_1")

    // Idempotent: a second regionize is a no-op, and the preview matches the
    // persisted conversion exactly (the id contract the lane UI relies on).
    let again = regionized.regionizingLegacyAudio(now: "t2", timelineSeconds: 12)
    #expect(again.audioRegions == regionized.audioRegions)
    #expect(regionized.legacyAudioRegionPreview(timelineSeconds: 12).isEmpty)
    let preview = shot.legacyAudioRegionPreview(
        timelineSeconds: 12,
        ambientBedDurationSeconds: 6,
        clipMediaDurationSeconds: 5
    )
    #expect(preview == regionized.audioRegions)

    // Nothing to convert → no-op.
    let empty = ProjectShot(shotId: "cut_empty", name: "Empty")
    #expect(empty.regionizingLegacyAudio(now: "t1", timelineSeconds: 10).audioRegions.isEmpty)
}

@Test func regionizingConvertsDisabledLanesAsMutedRegions() throws {
    var shot = legacyShot(clipMediaId: "clip_1")
    shot = shot.settingAudioMix(
        shot.audioMix.settingLaneEnabled(ShotAudioLaneId.clip, enabled: false),
        now: "t0"
    )
    let regionized = shot.regionizingLegacyAudio(
        now: "t1",
        timelineSeconds: 10,
        clipMediaDurationSeconds: 4
    )
    let clip = try #require(regionized.audioRegions.first { $0.laneId == ShotAudioLaneId.clip })
    #expect(clip.isMuted)
    #expect(clip.durationSeconds == 4)
}

@Test func regionizingUnrenderedShotKeepsMediaLengths() throws {
    let shot = legacyShot(clipMediaId: "clip_1")
    let regionized = shot.regionizingLegacyAudio(
        now: "t1",
        timelineSeconds: 0,
        clipMediaDurationSeconds: 7
    )
    let clip = try #require(regionized.audioRegions.first { $0.laneId == ShotAudioLaneId.clip })
    #expect(clip.durationSeconds == 7)
    let narration = try #require(regionized.audioRegions.first { $0.laneId == ShotAudioLaneId.narration })
    #expect(narration.durationSeconds == 2)
}

// MARK: - Combine-time precedence (the unification fix)

@Test func regionizedSourceCombinesWithoutDoubleImportAndKeepsSourceAudible() throws {
    let regionized = legacyShot(shotId: "a", clipMediaId: "clip_1").regionizingLegacyAudio(
        now: "t0",
        timelineSeconds: 8,
        clipMediaDurationSeconds: 3
    )
    #expect(!regionized.audioRegions.isEmpty)
    let second = ProjectShot(
        shotId: "b",
        name: "B",
        entries: [ShotFrameEntry(entryId: "b1", frameImageId: "f2")]
    )
    let result = buildCombinedCut(
        sources: [regionized, second],
        frameLookup: ["f1": testFrame("f1"), "f2": testFrame("f2")],
        mediaLookup: [:],
        meaningNodes: [],
        now: "t1",
        fileExists: { _ in false }
    )
    // One source-lane gain window per section — the regionized source's
    // source audio must NOT go silent just because it carries overlay regions.
    #expect(result.cut.audioRegions.filter { $0.laneId == ShotAudioLaneId.source }.count == 2)
    // And its singleton mirrors must NOT import a second copy of the overlays.
    #expect(result.cut.audioRegions.filter { $0.laneId == ShotAudioLaneId.narration }.count == 1)
    #expect(result.cut.audioRegions.filter { $0.laneId == ShotAudioLaneId.clip }.count == 1)
}

// MARK: - Tolerant decode

@Test func audioRegionDecodesWithoutSourceDurationAndRoundTripsWithIt() throws {
    let legacyJSON = Data("""
    {"regionId":"r1","laneId":"clip","label":"Song","path":"/a.mp3",
     "startSeconds":1,"sourceStartSeconds":0.5,"durationSeconds":3}
    """.utf8)
    let legacy = try JSONDecoder().decode(ShotAudioRegion.self, from: legacyJSON)
    #expect(legacy.sourceDurationSeconds == nil)
    #expect(legacy.maxNonLoopingDurationSeconds == nil)

    var region = legacy
    region.sourceDurationSeconds = 4.5
    let reencoded = try JSONDecoder().decode(
        ShotAudioRegion.self,
        from: JSONEncoder().encode(region)
    )
    #expect(reencoded.sourceDurationSeconds == 4.5)
    #expect(reencoded.maxNonLoopingDurationSeconds == 4.0)
    #expect(reencoded.mediaEndOnTimelineSeconds == 5.0)
}

// MARK: - Geometry laws

@Test func geometryLawClampsNonLoopingAtMediaEndAndAllowsLoopedExtend() {
    let region = ShotAudioRegion(
        regionId: "r1",
        laneId: ShotAudioLaneId.clip,
        path: "/a.mp3",
        startSeconds: 2,
        sourceStartSeconds: 1,
        durationSeconds: 3,
        sourceDurationSeconds: 5
    )
    // Extending past the media's remainder (5 − 1 = 4s) clamps honestly.
    let extended = region.applyingGeometry(
        startSeconds: 2,
        sourceStartSeconds: 1,
        durationSeconds: 20,
        timelineSeconds: 30
    )
    #expect(extended.durationSeconds == 4)

    // Looping releases the media clamp; only the timeline bounds it.
    var looping = region
    looping.loops = true
    let tiled = looping.applyingGeometry(
        startSeconds: 2,
        sourceStartSeconds: 1,
        durationSeconds: 20,
        timelineSeconds: 30
    )
    #expect(tiled.durationSeconds == 20)
    let timelineClamped = looping.applyingGeometry(
        startSeconds: 2,
        sourceStartSeconds: 1,
        durationSeconds: 60,
        timelineSeconds: 30
    )
    #expect(timelineClamped.durationSeconds == 28)

    // Unknown media length = no media clamp.
    var unknown = region
    unknown.sourceDurationSeconds = nil
    #expect(unknown.applyingGeometry(
        startSeconds: 2,
        sourceStartSeconds: 1,
        durationSeconds: 20,
        timelineSeconds: 30
    ).durationSeconds == 20)

    // Every clamp floors at one frame — ProjectShot.normalized() silently
    // DROPS zero-duration regions, so a clamp that reached zero would delete.
    let floored = region.applyingGeometry(
        startSeconds: 2,
        sourceStartSeconds: 1,
        durationSeconds: 0,
        timelineSeconds: 30
    )
    #expect(floored.durationSeconds >= frame - 0.000_001)

    // In-point clamps to leave at least one frame of media.
    let deepIn = region.applyingGeometry(
        startSeconds: 2,
        sourceStartSeconds: 99,
        durationSeconds: 1,
        timelineSeconds: 30
    )
    #expect(deepIn.sourceStartSeconds <= 5 - frame + 0.000_001)
}

@Test func movedToIsContinuousAndClampsToTimeline() {
    let region = ShotAudioRegion(
        regionId: "r1",
        laneId: ShotAudioLaneId.clip,
        path: "/a.mp3",
        durationSeconds: 2
    )
    // NOT frame-quantized: a drag's continuous value survives exactly.
    #expect(region.movedTo(startSeconds: 1.2345, timelineSeconds: 10).startSeconds == 1.2345)
    #expect(region.movedTo(startSeconds: -3, timelineSeconds: 10).startSeconds == 0)
    // At least one frame of the region stays inside the timeline.
    #expect(region.movedTo(startSeconds: 99, timelineSeconds: 10).startSeconds == 10 - frame)
    // Unknown timeline (unrendered shot) skips the clamp.
    #expect(region.movedTo(startSeconds: 99, timelineSeconds: 0).startSeconds == 99)
}

@Test func settingLoopsOffClampsDurationHonestly() {
    var region = ShotAudioRegion(
        regionId: "r1",
        laneId: ShotAudioLaneId.ambient,
        path: "/bed.m4a",
        startSeconds: 0,
        sourceStartSeconds: 0,
        durationSeconds: 24,
        sourceDurationSeconds: 6,
        loops: true
    )
    let once = region.settingLoops(false)
    #expect(once.durationSeconds == 6)
    #expect(!once.loops)

    region.durationSeconds = 4
    let on = region.settingLoops(true)
    #expect(on.durationSeconds == 4)
    #expect(on.loops)
}

@Test func replacingMediaKeepsPlacementAndClampsToShorterFile() {
    let region = ShotAudioRegion(
        regionId: "r1",
        laneId: ShotAudioLaneId.clip,
        label: "Old",
        path: "/old.mp3",
        mediaId: "old",
        sourceCutId: "cut_x",
        sourceArtifactId: "artifact",
        provenance: "imported_audio",
        startSeconds: 3,
        sourceStartSeconds: 2,
        durationSeconds: 6,
        sourceDurationSeconds: 10,
        gain: 0.5,
        isMuted: true
    )
    let replaced = region.replacingMedia(
        path: "/new.mp3",
        mediaId: "new",
        label: "New",
        sourceDurationSeconds: 4,
        provenance: "operator_replaced_media"
    )
    #expect(replaced.regionId == "r1")
    #expect(replaced.startSeconds == 3)
    #expect(replaced.gain == 0.5)
    #expect(replaced.isMuted)
    #expect(replaced.path == "/new.mp3")
    #expect(replaced.mediaId == "new")
    #expect(replaced.label == "New")
    #expect(replaced.sourceCutId.isEmpty)
    #expect(replaced.sourceArtifactId.isEmpty)
    // The shorter file clamps the in-point first, then the duration.
    #expect(replaced.sourceStartSeconds == 2)
    #expect(replaced.durationSeconds == 2)

    var looping = region
    looping.loops = true
    let loopingReplaced = looping.replacingMedia(
        path: "/new.mp3",
        mediaId: "new",
        label: "New",
        sourceDurationSeconds: 1,
        provenance: "operator_replaced_media"
    )
    // Looping geometry is untouched — tiling covers any length.
    #expect(loopingReplaced.durationSeconds == 6)
}

// MARK: - Model-level sync laws

@Test func duplicatedShotClearsAudioRegions() {
    let regionized = legacyShot().regionizingLegacyAudio(now: "t1", timelineSeconds: 10)
    #expect(!regionized.audioRegions.isEmpty)
    #expect(regionized.duplicated(now: "t2").audioRegions.isEmpty)
}

@Test func ripplingMovesRegionizedOverlaysAndSkipsSource() throws {
    var regionized = legacyShot().regionizingLegacyAudio(now: "t1", timelineSeconds: 10)
    regionized.audioRegions.append(ShotAudioRegion(
        regionId: "src",
        laneId: ShotAudioLaneId.source,
        provenance: "combined_source",
        startSeconds: 2,
        durationSeconds: 4
    ))
    let rippled = regionized.ripplingAudioRegions(atOrAfter: 0.5, by: 2, now: "t2")
    let narration = try #require(rippled.audioRegions.first { $0.laneId == ShotAudioLaneId.narration })
    #expect(narration.startSeconds == 3)
    #expect(rippled.audioRegions.first { $0.regionId == "src" }?.startSeconds == 2)
}

@Test func settingNarrationArtifactSyncsTheRegionOnRegionizedShots() throws {
    let regionized = legacyShot().regionizingLegacyAudio(now: "t1", timelineSeconds: 10)
    let moved = try #require(regionized.audioRegions.first { $0.provenance == "active_narration" })

    // Re-narration replaces media in place: the operator's timing survives,
    // the audio and length are the new take's.
    let renarrated = regionized.settingNarrationArtifact(
        ShotNarrationArtifact(
            status: "ready",
            audioPath: "/audio/narration_v2.m4a",
            durationSeconds: 5,
            traceId: "trace_2"
        ),
        now: "t2"
    )
    let synced = try #require(renarrated.audioRegions.first { $0.provenance == "active_narration" })
    #expect(synced.regionId == moved.regionId)
    #expect(synced.path == "/audio/narration_v2.m4a")
    #expect(synced.durationSeconds == 5)
    #expect(synced.startSeconds == moved.startSeconds)

    // Deleting the narration removes its region.
    let cleared = renarrated.settingNarrationArtifact(nil, now: "t3")
    #expect(cleared.audioRegions.first { $0.provenance == "active_narration" } == nil)

    // Non-regionized shots keep the old behavior: no region appears.
    let legacy = legacyShot().settingNarrationArtifact(
        ShotNarrationArtifact(status: "ready", audioPath: "/a.m4a", durationSeconds: 1),
        now: "t2"
    )
    #expect(legacy.audioRegions.isEmpty)
}

// MARK: - Timing helpers behind direct manipulation

@Test func snappedSecondsPicksNearestTargetInsideRadiusAndHonorsBypass() {
    // 100px over 10s → 10px/s; radius is 8px = 0.8s.
    let snapped = ShotAudioTiming.snappedSeconds(
        candidate: 4.5,
        targets: [4.0, 5.1],
        timelineWidth: 100,
        timelineDuration: 10,
        bypass: false
    )
    #expect(snapped.seconds == 4.0)
    #expect(snapped.snapped)

    let outOfRange = ShotAudioTiming.snappedSeconds(
        candidate: 4.5,
        targets: [6.0],
        timelineWidth: 100,
        timelineDuration: 10,
        bypass: false
    )
    #expect(outOfRange.seconds == 4.5)
    #expect(!outOfRange.snapped)

    let bypassed = ShotAudioTiming.snappedSeconds(
        candidate: 4.5,
        targets: [4.4],
        timelineWidth: 100,
        timelineDuration: 10,
        bypass: true
    )
    #expect(bypassed.seconds == 4.5)
    #expect(!bypassed.snapped)
}

@Test func snappedMoveStartSnapsHeadAndTailAndWearsTheCommitClamp() {
    // 100px over 10s → 10px/s; radius is 8px = 0.8s. A neighbour edge at 6.0
    // should catch the dragged region's TAIL: start 3.8 + duration 2 = end
    // 5.8, within radius of 6.0, so the start lands at 4.0.
    let tail = ShotAudioTiming.snappedMoveStart(
        candidateStart: 3.8,
        regionDurationSeconds: 2,
        targets: [6.0],
        timelineWidth: 100,
        timelineDuration: 10,
        bypass: false
    )
    #expect(abs(tail.seconds - 4.0) < 0.000_1)
    #expect(tail.snapped)

    // Nearest alignment wins: head→4.0 is 0.1s away, tail→(4.3−2)=2.3 is
    // 1.6s away, so the head magnet takes it.
    let nearest = ShotAudioTiming.snappedMoveStart(
        candidateStart: 4.1,
        regionDurationSeconds: 2,
        targets: [4.0, 4.3],
        timelineWidth: 100,
        timelineDuration: 10,
        bypass: false
    )
    #expect(nearest.seconds == 4.0)
    #expect(nearest.snapped)

    // The timeline end as a target aligns the TAIL (start = end − duration),
    // never rests the START on the end.
    let end = ShotAudioTiming.snappedMoveStart(
        candidateStart: 7.9,
        regionDurationSeconds: 2,
        targets: [10.0],
        timelineWidth: 100,
        timelineDuration: 10,
        bypass: false
    )
    #expect(abs(end.seconds - 8.0) < 0.000_1)
    #expect(end.snapped)

    // A head snap onto the timeline end is clamped by the same law the
    // commit applies (`movedTo`: last frame), and honestly reports itself
    // UNSNAPPED — this is the fix for the visible post-drop jump.
    let clamped = ShotAudioTiming.snappedMoveStart(
        candidateStart: 9.97,
        regionDurationSeconds: 0.5,
        targets: [10.0],
        timelineWidth: 300,
        timelineDuration: 10,
        bypass: false
    )
    #expect(abs(clamped.seconds - (10 - frame)) < 0.000_1)
    #expect(!clamped.snapped)

    // Bypass still clamps — the draft may never rest where the commit won't.
    let bypassed = ShotAudioTiming.snappedMoveStart(
        candidateStart: 11.5,
        regionDurationSeconds: 1,
        targets: [4.0],
        timelineWidth: 100,
        timelineDuration: 10,
        bypass: true
    )
    #expect(abs(bypassed.seconds - (10 - frame)) < 0.000_1)
    #expect(!bypassed.snapped)
}

// MARK: - Split law

@Test func splittingKeepsLeftIdentityMintsRightAndPreservesIntent() throws {
    let region = ShotAudioRegion(
        regionId: "region_left",
        laneId: ShotAudioLaneId.clip,
        label: "Voice",
        path: "/audio/voice.mp3",
        mediaId: "media_voice",
        provenance: "operator_audio_clip",
        startSeconds: 2,
        sourceStartSeconds: 0.5,
        durationSeconds: 4,
        sourceDurationSeconds: 30,
        pitchMode: .tape,
        gain: 0.8,
        isMuted: true,
        loops: false
    )
    let split = try #require(region.splitting(atSeconds: 4, rightRegionId: "region_right"))
    #expect(split.left.regionId == "region_left")
    #expect(split.right.regionId == "region_right")
    #expect(split.left.startSeconds == 2)
    #expect(split.left.durationSeconds == 2)
    #expect(split.right.startSeconds == 4)
    #expect(split.right.durationSeconds == 2)
    // Continuous source timing: the right child resumes where the left ends.
    #expect(abs(split.right.sourceStartSeconds - 2.5) < 0.000_1)
    for child in [split.left, split.right] {
        #expect(child.path == region.path)
        #expect(child.mediaId == region.mediaId)
        #expect(child.provenance == region.provenance)
        #expect(child.gain == region.gain)
        #expect(child.isMuted == region.isMuted)
        #expect(child.loops == region.loops)
        #expect(child.pitchMode == region.pitchMode)
    }
}

@Test func splittingAdvancesSourceInPointByRateAndLoopPhaseForLoops() throws {
    let fast = ShotAudioRegion(
        regionId: "fast",
        laneId: ShotAudioLaneId.clip,
        path: "/audio/fast.mp3",
        startSeconds: 0,
        sourceStartSeconds: 1,
        durationSeconds: 4,
        sourceDurationSeconds: 30,
        playbackRate: 2
    )
    let fastSplit = try #require(fast.splitting(atSeconds: 1, rightRegionId: "fast_right"))
    // One timeline second at 2× consumes two source seconds.
    #expect(abs(fastSplit.right.sourceStartSeconds - 3) < 0.000_1)

    let looped = ShotAudioRegion(
        regionId: "looped",
        laneId: ShotAudioLaneId.ambient,
        path: "/audio/bed.m4a",
        startSeconds: 0,
        sourceStartSeconds: 0,
        durationSeconds: 8,
        sourceDurationSeconds: 3,
        loops: true
    )
    let loopSplit = try #require(looped.splitting(atSeconds: 5, rightRegionId: "looped_right"))
    // A looped right child advances PHASE (mod the file), never the in-point,
    // so the repeat cadence carries across the cut without restarting.
    #expect(loopSplit.right.sourceStartSeconds == 0)
    #expect(abs(loopSplit.right.loopPhaseSeconds - 2) < 0.000_1)
    #expect(loopSplit.left.loopPhaseSeconds == 0)
}

@Test func splittingRefusesEdgesSliversAndEmptyIdentity() {
    let region = ShotAudioRegion(
        regionId: "r",
        laneId: ShotAudioLaneId.clip,
        path: "/audio/a.mp3",
        startSeconds: 2,
        durationSeconds: 1
    )
    // On either boundary there is nothing to divide.
    #expect(region.splitting(atSeconds: 2, rightRegionId: "x") == nil)
    #expect(region.splitting(atSeconds: 3, rightRegionId: "x") == nil)
    // Outside the region entirely.
    #expect(region.splitting(atSeconds: 5, rightRegionId: "x") == nil)
    // Less than one frame on a side (frame-quantized to the region edge).
    #expect(region.splitting(atSeconds: 2 + frame / 4, rightRegionId: "x") == nil)
    // A fresh identity is required — without it the pair could collide.
    #expect(region.splitting(atSeconds: 2.5, rightRegionId: "  ") == nil)
    // And the happy path right beside those refusals still divides.
    #expect(region.splitting(atSeconds: 2.5, rightRegionId: "x") != nil)
}

@Test func parseTimecodeAcceptsAllThreeForms() {
    #expect(ShotAudioTiming.parseTimecode("7.5") == 7.5)
    #expect(ShotAudioTiming.parseTimecode("01:30") == 90)
    let framesForm = ShotAudioTiming.parseTimecode("01:30:12")
    #expect(framesForm != nil)
    #expect(abs((framesForm ?? 0) - (90 + 12.0 / 24.0)) < 0.000_001)
    #expect(ShotAudioTiming.parseTimecode("") == nil)
    #expect(ShotAudioTiming.parseTimecode("nonsense") == nil)
    #expect(ShotAudioTiming.parseTimecode("1:2:3:4") == nil)
}

// MARK: - Render CTA vocabulary

@Test func cutRenderCTAFollowsSeedCoverage() {
    let ordinary = ProjectShot(shotId: "plain", name: "Plain")
    #expect(cutRenderCTA(cut: ordinary, segmentCount: 3) == .render)

    var combined = ProjectShot(
        shotId: "combined",
        name: "Combined",
        combinedSources: [ShotCombinedSource(sourceId: "s1", sourceCutId: "a")]
    )
    #expect(cutRenderCTA(cut: combined, segmentCount: 2) == .renderMissing)

    // Readable seeds are FileManager-checked, so a fake path stays "missing".
    combined.seedSegmentClips = [
        ShotRenderSegmentClip(placementStartEntryId: "e1", placementEndEntryId: "e2", clipPath: "/nope.mp4")
    ]
    #expect(cutRenderCTA(cut: combined, segmentCount: 1) == .renderMissing)
}

// MARK: - Fades

@Test func settingFadesClampsToDurationWithFadeInPriority() {
    let region = ShotAudioRegion(
        regionId: "r1", laneId: "clip", path: "/a.mp3", startSeconds: 0, durationSeconds: 4
    )
    let both = region.settingFades(fadeInSeconds: 3, fadeOutSeconds: 3)
    #expect(both.fadeInSeconds == 3)
    #expect(both.fadeOutSeconds == 1)

    let negative = region.settingFades(fadeInSeconds: -1, fadeOutSeconds: 2)
    #expect(negative.fadeInSeconds == 0)
    #expect(negative.fadeOutSeconds == 2)

    let oversized = region.settingFades(fadeInSeconds: 10, fadeOutSeconds: 10)
    #expect(oversized.fadeInSeconds == 4)
    #expect(oversized.fadeOutSeconds == 0)
}

@Test func trimShrinkReclampsFadesThroughNormalized() {
    let region = ShotAudioRegion(
        regionId: "r1", laneId: "clip", path: "/a.mp3", startSeconds: 0, durationSeconds: 10
    ).settingFades(fadeInSeconds: 2, fadeOutSeconds: 2)
    let shrunk = region.applyingGeometry(
        startSeconds: 0, sourceStartSeconds: 0, durationSeconds: 3, timelineSeconds: 60
    )
    #expect(shrunk.durationSeconds == 3)
    #expect(shrunk.fadeInSeconds == 2)
    #expect(shrunk.fadeOutSeconds == 1)
}

@Test func splittingSendsFadeInLeftFadeOutRightHardCutAtBoundary() throws {
    let region = ShotAudioRegion(
        regionId: "r1", laneId: "clip", path: "/a.mp3", startSeconds: 0, durationSeconds: 10
    ).settingFades(fadeInSeconds: 1, fadeOutSeconds: 1)
    let halves = try #require(region.splitting(atSeconds: 5, rightRegionId: "r2"))
    #expect(halves.left.fadeInSeconds == 1)
    #expect(halves.left.fadeOutSeconds == 0)
    #expect(halves.right.fadeInSeconds == 0)
    #expect(halves.right.fadeOutSeconds == 1)
}

@Test func fadeFieldsDecodeAbsentAsZeroAndRoundTrip() throws {
    // A pre-fade document decodes with hard in/out — the tolerant law.
    let legacy = """
    {"regionId": "r1", "laneId": "clip", "path": "/a.mp3", "durationSeconds": 5}
    """
    let decoded = try JSONDecoder().decode(ShotAudioRegion.self, from: Data(legacy.utf8))
    #expect(decoded.fadeInSeconds == 0)
    #expect(decoded.fadeOutSeconds == 0)

    let faded = decoded.settingFades(fadeInSeconds: 1.5, fadeOutSeconds: 0.5)
    let round = try JSONDecoder().decode(
        ShotAudioRegion.self,
        from: JSONEncoder().encode(faded)
    )
    #expect(round == faded)
}

// MARK: - Paste / duplicate

@Test func pastedCopyMintsIdentityRetargetsLaneAndKeepsOperatorFields() {
    let region = ShotAudioRegion(
        regionId: "r1", laneId: "clip", label: "Music", path: "/a.mp3", mediaId: "m1",
        provenance: "operator_audio_clip",
        startSeconds: 2, sourceStartSeconds: 1, durationSeconds: 4,
        sourceDurationSeconds: 30,
        playbackRate: 2, pitchMode: .tape, gain: 0.5, isMuted: true,
        fadeInSeconds: 1, fadeOutSeconds: 1
    )
    let copy = region.pastedCopy(
        regionId: "r2", laneId: "clip_2", startSeconds: 6, timelineSeconds: 60
    )
    #expect(copy.regionId == "r2")
    #expect(copy.laneId == "clip_2")
    #expect(copy.startSeconds == 6)
    #expect(copy.sourceStartSeconds == 1)
    #expect(copy.durationSeconds == 4)
    #expect(copy.playbackRate == 2)
    #expect(copy.pitchMode == .tape)
    #expect(copy.gain == 0.5)
    #expect(copy.isMuted)
    #expect(copy.fadeInSeconds == 1)
    #expect(copy.fadeOutSeconds == 1)
    #expect(copy.path == "/a.mp3")
    #expect(copy.mediaId == "m1")
}

@Test func pastedCopyClampsIntoTheDestinationTimeline() {
    let region = ShotAudioRegion(
        regionId: "r1", laneId: "clip", path: "/a.mp3",
        startSeconds: 0, durationSeconds: 10
    )
    let copy = region.pastedCopy(
        regionId: "r2", laneId: "clip", startSeconds: 58, timelineSeconds: 60
    )
    #expect(copy.startSeconds == 58)
    #expect(copy.durationSeconds == 2)

    // A paste beyond the end keeps one frame inside the timeline.
    let far = region.pastedCopy(
        regionId: "r3", laneId: "clip", startSeconds: 500, timelineSeconds: 60
    )
    #expect(far.startSeconds == 60 - frame)
}

@Test func pastedCopyOfLoopingRegionKeepsPhaseAndClampsOnlyToTimeline() {
    let region = ShotAudioRegion(
        regionId: "r1", laneId: "ambient", path: "/bed.m4a",
        startSeconds: 0, durationSeconds: 8,
        sourceDurationSeconds: 2, loopPhaseSeconds: 1.5, loops: true
    )
    let copy = region.pastedCopy(
        regionId: "r2", laneId: "ambient", startSeconds: 5, timelineSeconds: 20
    )
    // Loops tile: the short file never clamps the placed duration.
    #expect(copy.durationSeconds == 8)
    #expect(copy.loopPhaseSeconds == 1.5)
    #expect(copy.loops)
}

@Test func duplicatePlacementIsExactRegionEndUnquantized() {
    // The butt joint is the drag family: NO frame quantization at the seam.
    let region = ShotAudioRegion(
        regionId: "r1", laneId: "clip", path: "/a.mp3",
        startSeconds: 0.37, durationSeconds: 1.111
    )
    let copy = region.pastedCopy(
        regionId: "r2", laneId: region.laneId,
        startSeconds: region.endSeconds, timelineSeconds: 60
    )
    #expect(abs(copy.startSeconds - 1.481) < 0.000_001)
}

@Test func clipboardPayloadRoundTripsAndDecodesTolerantly() throws {
    let payload = ShotAudioRegionClipboardPayload(
        region: ShotAudioRegion(
            regionId: "r1", laneId: "clip", label: "Music", path: "/a.mp3",
            startSeconds: 2, durationSeconds: 4,
            fadeInSeconds: 0.5, fadeOutSeconds: 0.5
        ),
        sourceShotId: "cut_1",
        sourceProjectId: "proj_1"
    )
    let round = try JSONDecoder().decode(
        ShotAudioRegionClipboardPayload.self,
        from: JSONEncoder().encode(payload)
    )
    #expect(round == payload)
    #expect(round.isPasteable)

    // An empty or foreign payload decodes without throwing and reads as an
    // empty clipboard rather than a crash or a junk paste.
    let empty = try JSONDecoder().decode(
        ShotAudioRegionClipboardPayload.self,
        from: Data("{}".utf8)
    )
    #expect(!empty.isPasteable)
    let foreign = try JSONDecoder().decode(
        ShotAudioRegionClipboardPayload.self,
        from: Data(#"{"version": 9, "region": {"regionId": "x"}, "futureField": true}"#.utf8)
    )
    #expect(foreign.version == 9)
    #expect(!foreign.isPasteable)
}

@Test func pasteLaneResolutionPrefersCompatibleFocusThenOriginalRowThenBaseKind() {
    let rows = ["source", "narration", "microphone", "ambient", "clip", "clip_2"]

    // Rung 1: a kind-compatible focused lane wins.
    #expect(shotAudioPasteLaneId(
        payloadLaneId: "clip_2", preferredLaneId: "clip", rows: rows
    ) == "clip")

    // Rung 2: an incompatible focus falls back to the payload's own row.
    #expect(shotAudioPasteLaneId(
        payloadLaneId: "clip_2", preferredLaneId: "ambient", rows: rows
    ) == "clip_2")

    // Rung 3: a missing row lands on the base row of the kind.
    #expect(shotAudioPasteLaneId(
        payloadLaneId: "clip_3", preferredLaneId: nil, rows: rows
    ) == "clip")

    // SOURCE never travels.
    #expect(shotAudioPasteLaneId(
        payloadLaneId: "source", preferredLaneId: "clip", rows: rows
    ) == nil)
}
