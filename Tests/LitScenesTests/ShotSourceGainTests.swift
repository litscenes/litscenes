import Foundation
import Testing
@testable import LitScenes

// The SOURCE gain law: how loud the picture's own audio is at any moment.
// These pin the behavior that lets one bad generated segment be silenced
// without touching its neighbours.

private func gainFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        label: id.uppercased(),
        imagePath: "/tmp/\(id).png",
        prompt: "Scene \(id)",
        status: "ready"
    )
}

private let gainFrames: [String: ProjectLensHeroImage] = [
    "f1": gainFrame("f1"), "f2": gainFrame("f2"),
    "f3": gainFrame("f3"), "f4": gainFrame("f4")
]

/// A shot of `count` generated segments, each with a saved clip on disk.
private func gainShot(segments count: Int) -> ProjectShot {
    var artifact = ShotRenderArtifact(
        versionId: "v1", versionNumber: 1, status: "ready",
        generatedAt: "t0", updatedAt: "t0"
    )
    var entries: [ShotFrameEntry] = []
    for index in 0...count {
        entries.append(ShotFrameEntry(entryId: "e\(index + 1)", frameImageId: "f\(index + 1)"))
    }
    for index in 0..<count {
        artifact.upsertSegmentClip(ShotRenderSegmentClip(
            startFrameImageId: "f\(index + 1)",
            endFrameImageId: "f\(index + 2)",
            placementStartEntryId: "e\(index + 1)",
            placementEndEntryId: "e\(index + 2)",
            clipPath: "/tmp/seg\(index + 1).mp4",
            updatedAt: "t0"
        ))
    }
    let shot = ProjectShot(
        shotId: "gain_shot", name: "Gain", entries: entries,
        createdAt: "t0", updatedAt: "t0"
    )
    return shot.upsertingRenderVersion(artifact, activate: true, now: "t0")
}

private func gainAssembly(_ shot: ProjectShot, durations: [String: Double]) -> ShotCutAssembly {
    let plan = shotRenderSegmentPlan(
        shot: shot, frameLookup: gainFrames, mediaLookup: [:], meaningNodes: []
    )
    return shotCutAssembly(
        shot: shot, planSegments: plan.segments,
        clipDurationsByPath: durations, fileExists: { _ in true }
    )
}

private func muting(_ shot: ProjectShot, segmentIndex: Int, gain: Double = 1, muted: Bool = true) -> ProjectShot {
    let start = "e\(segmentIndex)"
    let end = "e\(segmentIndex + 1)"
    return shot.settingSourceSegmentAudio(
        segmentKey: shotPlacementSegmentKey(
            startEntryId: start, endEntryId: end, legacyStartId: "", legacyEndId: ""
        ),
        startFrameImageId: "f\(segmentIndex)",
        endFrameImageId: "f\(segmentIndex + 1)",
        placementStartEntryId: start,
        placementEndEntryId: end,
        gain: gain,
        isMuted: muted,
        now: "t1"
    )
}

// MARK: - The empty hand

@Test func noIntentAndNoEnvelopesYieldsNoWindows() {
    let shot = gainShot(segments: 2)
    let assembly = gainAssembly(shot, durations: ["/tmp/seg1.mp4": 4, "/tmp/seg2.mp4": 6])
    #expect(shotSourceGainWindows(shot: shot, assembly: assembly).isEmpty)

    // A non-default LANE volume is still the flat path — it is not per-segment
    // state and must not conjure windows.
    let quieter = shot.settingAudioMix(
        shot.audioMix.settingLaneVolume(ShotAudioLaneId.source, volume: 0.4),
        now: "t1"
    )
    #expect(shotSourceGainWindows(shot: quieter, assembly: assembly).isEmpty)
}

// MARK: - The uncovered-instant law

@Test func mutingOneSegmentEmitsAWindowForEverySegment() throws {
    var shot = gainShot(segments: 3)
    shot = muting(shot, segmentIndex: 2)
    let assembly = gainAssembly(
        shot,
        durations: ["/tmp/seg1.mp4": 4, "/tmp/seg2.mp4": 5, "/tmp/seg3.mp4": 6]
    )
    let windows = shotSourceGainWindows(shot: shot, assembly: assembly)

    // Every segment must be covered — an uncovered instant would be silent.
    try #require(windows.count == assembly.playbackItems.count)
    #expect(windows.filter { $0.gain == 0 }.count == 1)
    #expect(windows.filter { $0.gain > 0 }.count == windows.count - 1)

    let muted = try #require(windows.first { $0.gain == 0 })
    #expect(muted.segmentKey == "entry:e2>e3")
    // The windows tile the whole output with no hole between them.
    for (index, window) in windows.enumerated() where index > 0 {
        #expect(abs(window.startSeconds - windows[index - 1].endSeconds) < 0.000_1)
    }
    #expect(abs(windows[0].startSeconds) < 0.000_1)
    #expect(abs((windows.last?.endSeconds ?? 0) - assembly.outputSeconds) < 0.000_1)
}

@Test func laneVolumeAndSegmentGainMultiply() throws {
    var shot = gainShot(segments: 2)
    shot = muting(shot, segmentIndex: 1, gain: 0.4, muted: false)
    shot = shot.settingAudioMix(
        shot.audioMix.settingLaneVolume(ShotAudioLaneId.source, volume: 0.5),
        now: "t1"
    )
    let assembly = gainAssembly(shot, durations: ["/tmp/seg1.mp4": 4, "/tmp/seg2.mp4": 4])
    let windows = shotSourceGainWindows(shot: shot, assembly: assembly)
    let first = try #require(windows.first { $0.segmentKey == "entry:e1>e2" })
    let second = try #require(windows.first { $0.segmentKey == "entry:e2>e3" })
    #expect(abs(first.gain - 0.2) < 0.000_1)     // 0.5 lane × 0.4 intent
    #expect(abs(second.gain - 0.5) < 0.000_1)    // 0.5 lane × no intent
}

@Test func disablingTheLaneVetoesEverySegment() {
    var shot = gainShot(segments: 2)
    shot = muting(shot, segmentIndex: 1, gain: 0.8, muted: false)
    shot = shot.settingAudioMix(
        shot.audioMix.settingLaneEnabled(ShotAudioLaneId.source, enabled: false),
        now: "t1"
    )
    let assembly = gainAssembly(shot, durations: ["/tmp/seg1.mp4": 4, "/tmp/seg2.mp4": 4])
    #expect(shotSourceGainWindows(shot: shot, assembly: assembly).allSatisfy { $0.gain == 0 })
}

// MARK: - Envelopes (combined cuts) compose with intent

@Test func combinedEnvelopeAndSegmentIntentMultiply() throws {
    var shot = gainShot(segments: 2)
    let assembly = gainAssembly(shot, durations: ["/tmp/seg1.mp4": 4, "/tmp/seg2.mp4": 4])
    // One envelope over the whole output at 0.4, as buildCombinedCut writes.
    shot.audioRegions = [ShotAudioRegion(
        regionId: "env", laneId: ShotAudioLaneId.source,
        provenance: "combined_source",
        startSeconds: 0, durationSeconds: assembly.outputSeconds, gain: 0.4
    )]
    shot = muting(shot, segmentIndex: 1, gain: 0.5, muted: false)
    let windows = shotSourceGainWindows(shot: shot, assembly: assembly)
    let first = try #require(windows.first { $0.segmentKey == "entry:e1>e2" })
    let second = try #require(windows.first { $0.segmentKey == "entry:e2>e3" })
    #expect(abs(first.gain - 0.2) < 0.000_1)   // 0.4 envelope × 0.5 intent
    #expect(abs(second.gain - 0.4) < 0.000_1)  // 0.4 envelope × no intent
}

/// The older law survives: once ANY source window exists, an instant outside
/// every envelope is silent.
@Test func anInstantOutsideEveryEnvelopeStaysSilent() throws {
    var shot = gainShot(segments: 2)
    let assembly = gainAssembly(shot, durations: ["/tmp/seg1.mp4": 4, "/tmp/seg2.mp4": 4])
    // An envelope covering only the first second — everything later is uncovered.
    shot.audioRegions = [ShotAudioRegion(
        regionId: "env", laneId: ShotAudioLaneId.source,
        provenance: "combined_source",
        startSeconds: 0, durationSeconds: 1, gain: 1
    )]
    let windows = shotSourceGainWindows(shot: shot, assembly: assembly)
    try #require(!windows.isEmpty)
    #expect(windows.last?.gain == 0)
}

// MARK: - Carriage

@Test func aBridgeIsSilentButNeverCreatesWindowsOnItsOwn() throws {
    var shot = gainShot(segments: 2)
    // These clips carry placement entry ids, so the durable key is the
    // placement form — the legacy image-pair key would never match.
    let segmentKey = "entry:e1>e2"
    let cut = ShotSegmentCutRange(
        cutId: "cut_1", segmentKey: segmentKey, clipPath: "/tmp/seg1.mp4",
        startSeconds: 1, endSeconds: 2,
        joinRepair: ShotRazorJoinRepair(mode: .generatedBridge, activeBridgeVersionId: "bridge_1")
    )
    shot.cutList = ShotCutList(segmentCuts: [cut])
    shot.joinBridgeVersions = [ShotJoinBridgeArtifact(
        versionId: "bridge_1", cutId: cut.id, sourceSegmentKey: segmentKey,
        sourceClipPath: "/tmp/seg1.mp4", cutStartSeconds: 1, cutEndSeconds: 2,
        durationSeconds: 2, status: "ready", videoPath: "/tmp/bridge.mp4"
    )]
    let durations = ["/tmp/seg1.mp4": 4.0, "/tmp/seg2.mp4": 4.0, "/tmp/bridge.mp4": 2.0]
    let assembly = gainAssembly(shot, durations: durations)
    try #require(assembly.playbackItems.contains { $0.isBridge })

    // A bridge alone conjures nothing — its silence comes from the track gap.
    #expect(shotSourceGainWindows(shot: shot, assembly: assembly).isEmpty)

    // With intent present, the bridge STATES its silence.
    let muted = muting(shot, segmentIndex: 2)
    let windows = shotSourceGainWindows(shot: muted, assembly: assembly)
    let bridgeItem = try #require(assembly.playbackItems.first { $0.isBridge })
    let bridgeWindow = try #require(windows.first {
        abs($0.startSeconds - bridgeItem.outputStartSeconds) < 0.000_1
    })
    #expect(bridgeWindow.gain == 0)
    #expect(bridgeWindow.segmentKey.isEmpty)
}

// MARK: - No assembly

@Test func absentAssemblyFallsBackToEnvelopeWindows() throws {
    var shot = gainShot(segments: 2)
    #expect(shotSourceGainWindows(shot: shot, assembly: nil).isEmpty)
    shot.audioRegions = [ShotAudioRegion(
        regionId: "env", laneId: ShotAudioLaneId.source,
        startSeconds: 2, durationSeconds: 3, gain: 0.5
    )]
    let windows = shotSourceGainWindows(shot: shot, assembly: nil)
    try #require(windows.count == 1)
    #expect(windows[0].startSeconds == 2)
    #expect(windows[0].endSeconds == 5)
    #expect(abs(windows[0].gain - 0.5) < 0.000_1)
}

// MARK: - Coalescing

@Test func coalescingMergesAbuttingEqualGainsButNeverAcrossAGap() throws {
    let equal = coalescedSourceGainWindows([
        ShotSourceGainWindow(startSeconds: 0, endSeconds: 2, gain: 1, segmentKey: "a"),
        ShotSourceGainWindow(startSeconds: 2, endSeconds: 5, gain: 1, segmentKey: "b")
    ])
    try #require(equal.count == 1)
    #expect(equal[0].endSeconds == 5)

    let differing = coalescedSourceGainWindows([
        ShotSourceGainWindow(startSeconds: 0, endSeconds: 2, gain: 1, segmentKey: "a"),
        ShotSourceGainWindow(startSeconds: 2, endSeconds: 5, gain: 0, segmentKey: "b"),
        ShotSourceGainWindow(startSeconds: 5, endSeconds: 7, gain: 1, segmentKey: "c")
    ])
    #expect(differing.count == 3)

    // A real gap is never merged away, even at equal gain.
    let gapped = coalescedSourceGainWindows([
        ShotSourceGainWindow(startSeconds: 0, endSeconds: 2, gain: 1, segmentKey: "a"),
        ShotSourceGainWindow(startSeconds: 4, endSeconds: 6, gain: 1, segmentKey: "b")
    ])
    #expect(gapped.count == 2)

    // Out-of-order input still coalesces correctly — the mixer's window order
    // is a silent-dropout hazard, so ordering is this function's job.
    let shuffled = coalescedSourceGainWindows([
        ShotSourceGainWindow(startSeconds: 5, endSeconds: 7, gain: 1, segmentKey: "c"),
        ShotSourceGainWindow(startSeconds: 0, endSeconds: 2, gain: 1, segmentKey: "a"),
        ShotSourceGainWindow(startSeconds: 2, endSeconds: 5, gain: 0, segmentKey: "b")
    ])
    #expect(shuffled.map(\.startSeconds) == [0, 2, 5])
}

// MARK: - Fades

@Test func rampLengthClampsToHalfTheShorterWindow() {
    let fade = 0.010
    // Roomy on both sides ⇒ the full fade.
    #expect(sourceGainRampSeconds(windowSeconds: 4, neighbourSeconds: 4, fadeSeconds: fade) == fade)
    // A 20ms window ⇒ 10ms; a 4ms window ⇒ 2ms.
    #expect(abs(sourceGainRampSeconds(windowSeconds: 0.020, neighbourSeconds: 4, fadeSeconds: fade) - 0.010) < 1e-9)
    #expect(abs(sourceGainRampSeconds(windowSeconds: 0.004, neighbourSeconds: 4, fadeSeconds: fade) - 0.002) < 1e-9)
    // A short NEIGHBOUR clamps it too — a ramp may never reach past a
    // neighbour's midpoint and smear into the segment beyond.
    #expect(abs(sourceGainRampSeconds(windowSeconds: 4, neighbourSeconds: 0.006, fadeSeconds: fade) - 0.003) < 1e-9)
    // Degenerate input is a step, not a negative ramp.
    #expect(sourceGainRampSeconds(windowSeconds: 0, neighbourSeconds: 4, fadeSeconds: fade) == 0)
    #expect(sourceGainRampSeconds(windowSeconds: 4, neighbourSeconds: nil, fadeSeconds: 0) == 0)
}

// MARK: - Model lifecycle

@Test func sourceSegmentAudioDecodesTolerantly() throws {
    let sparse = try JSONDecoder().decode(
        ShotSourceSegmentAudio.self, from: Data("{}".utf8)
    )
    #expect(sparse.gain == 1)
    #expect(!sparse.isMuted)
    #expect(sparse.isNoOp)

    // A ProjectShot written before the field existed decodes to [].
    let old = try JSONDecoder().decode(
        ProjectShot.self,
        from: Data("{\"shotId\":\"s1\",\"name\":\"Old\"}".utf8)
    )
    #expect(old.sourceSegmentAudio.isEmpty)

    // A junk-typed value must not throw the whole shot away.
    let junk = try JSONDecoder().decode(
        ProjectShot.self,
        from: Data("{\"shotId\":\"s1\",\"sourceSegmentAudio\":\"nope\"}".utf8)
    )
    #expect(junk.sourceSegmentAudio.isEmpty)
    #expect(junk.shotId == "s1")
}

@Test func settingSourceSegmentAudioUpsertsAndDropsNoOps() throws {
    let shot = gainShot(segments: 2)
    let muted = muting(shot, segmentIndex: 1)
    try #require(muted.sourceSegmentAudio.count == 1)
    #expect(muted.sourceSegmentAudio(forSegmentKey: "entry:e1>e2")?.isMuted == true)

    // Muting the same segment again replaces rather than stacking.
    let again = muting(muted, segmentIndex: 1, gain: 0.3, muted: false)
    #expect(again.sourceSegmentAudio.count == 1)
    #expect(abs((again.sourceSegmentAudio(forSegmentKey: "entry:e1>e2")?.gain ?? 0) - 0.3) < 0.000_1)

    // Back to audible at full gain is ABSENCE, not a row saying nothing.
    let restored = muting(muted, segmentIndex: 1, gain: 1, muted: false)
    #expect(restored.sourceSegmentAudio.isEmpty)
}

@Test func normalizingPrunesIntentWhoseEntryIsGone() throws {
    var shot = gainShot(segments: 2)
    shot = muting(shot, segmentIndex: 2)
    try #require(shot.normalized().sourceSegmentAudio.count == 1)

    // Remove the entry the intent's placement points at.
    var orphaned = shot
    orphaned.entries.removeAll { $0.entryId == "e3" }
    #expect(orphaned.normalized().sourceSegmentAudio.isEmpty)
}

@Test func duplicatedShotClearsSourceSegmentAudio() {
    let shot = muting(gainShot(segments: 2), segmentIndex: 1)
    #expect(shot.duplicated(now: "t2").sourceSegmentAudio.isEmpty)
}

/// The ratified requirement: a mute is about the SEGMENT, not the take, so it
/// survives a re-render that replaces the segment's pixels.
@Test func intentSurvivesAReRenderOfItsSegment() throws {
    var shot = gainShot(segments: 2)
    shot = muting(shot, segmentIndex: 2)

    var reRendered = ShotRenderArtifact(
        versionId: "v2", versionNumber: 2, status: "ready",
        generatedAt: "t2", updatedAt: "t2"
    )
    for index in 0..<2 {
        reRendered.upsertSegmentClip(ShotRenderSegmentClip(
            startFrameImageId: "f\(index + 1)",
            endFrameImageId: "f\(index + 2)",
            placementStartEntryId: "e\(index + 1)",
            placementEndEntryId: "e\(index + 2)",
            clipPath: "/tmp/take2_seg\(index + 1).mp4",   // new pixels
            updatedAt: "t2"
        ))
    }
    shot = shot.upsertingRenderVersion(reRendered, activate: true, now: "t2").normalized()
    #expect(shot.sourceSegmentAudio.count == 1)

    let assembly = gainAssembly(
        shot, durations: ["/tmp/take2_seg1.mp4": 4, "/tmp/take2_seg2.mp4": 4]
    )
    let windows = shotSourceGainWindows(shot: shot, assembly: assembly)
    let muted = try #require(windows.first { $0.segmentKey == "entry:e2>e3" })
    #expect(muted.gain == 0)
    #expect(windows.first { $0.segmentKey == "entry:e1>e2" }?.gain == 1)
}

// MARK: - Detach

@Test func detachDerivesItsInPointFromTheKeepRangeAndYieldsOneRegionPerRazorPiece() throws {
    var shot = gainShot(segments: 2)
    // A razor through the middle of segment 1, hard-cut (no bridge): the
    // segment now plays as TWO pieces with a hole between them.
    let segmentKey = "entry:e1>e2"
    shot.cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(
            cutId: "cut_1", segmentKey: segmentKey, clipPath: "/tmp/seg1.mp4",
            startSeconds: 1, endSeconds: 2
        )
    ])
    let assembly = gainAssembly(shot, durations: ["/tmp/seg1.mp4": 4.0, "/tmp/seg2.mp4": 4.0])
    let pieces = assembly.playbackItems.filter { $0.segmentKey == segmentKey && !$0.isBridge }
    try #require(pieces.count == 2)

    let regions = shotDetachedSourceRegions(
        pieces: pieces,
        baseLabel: "Segment 1 audio",
        regionId: { "detached_\($0)" }
    )
    #expect(regions.count == 2)
    #expect(regions.allSatisfy { $0.laneId == ShotAudioLaneId.clip })
    #expect(regions.allSatisfy { $0.provenance == "detached_source_audio" })
    #expect(regions.allSatisfy { $0.path == "/tmp/seg1.mp4" })
    // Numbered, because two regions named the same thing are unpickable.
    #expect(regions.map(\.label) == ["Segment 1 audio · 1", "Segment 1 audio · 2"])

    // Each region lands at its piece's OUTPUT position with its piece's own
    // in-point — the same head `sourceCapture` reads, so a detached region and
    // a captured still agree about where in the file they are.
    for (region, piece) in zip(regions, pieces) {
        #expect(abs(region.startSeconds - piece.outputStartSeconds) < 0.000_1)
        #expect(abs(region.durationSeconds - piece.durationSeconds) < 0.000_1)
        #expect(abs(region.sourceStartSeconds - piece.sourceHeadSeconds) < 0.000_1)
    }
    // The second piece begins AFTER the razor, not at the file's head — this is
    // the whole reason one spanning region would be wrong.
    #expect(regions[1].sourceStartSeconds >= 2 - 0.000_1)
    // And the removed second of material appears in neither region.
    #expect(regions.reduce(0) { $0 + $1.durationSeconds } < 4)
}

@Test func detachOfAnUncutSegmentIsASingleUnnumberedRegion() throws {
    let shot = gainShot(segments: 2)
    let assembly = gainAssembly(shot, durations: ["/tmp/seg1.mp4": 4.0, "/tmp/seg2.mp4": 4.0])
    let pieces = assembly.playbackItems.filter { $0.segmentKey == "entry:e2>e3" }
    try #require(pieces.count == 1)

    let regions = shotDetachedSourceRegions(
        pieces: pieces,
        baseLabel: "Segment 2 audio",
        regionId: { "detached_\($0)" }
    )
    #expect(regions.count == 1)
    #expect(regions[0].label == "Segment 2 audio")
    #expect(regions[0].path == "/tmp/seg2.mp4")
    // Position on the OUTPUT timeline, so the region sits exactly under the
    // picture it came from.
    #expect(abs(regions[0].startSeconds - pieces[0].outputStartSeconds) < 0.000_1)
}
