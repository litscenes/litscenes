import Foundation
import Testing
@testable import LitScenes

// THE FINALS REEL's pure laws: tolerant persistence, seam lifecycle
// (adjacency dormancy, reaping with entries), the crossfade/composition
// plan (the handle-manufacture law), and bake-identity fingerprints.

// MARK: - Fixtures

private func stageSet(cuts: [String]) -> ProjectStageSetDocument {
    var doc = ProjectStageSetDocument(projectId: "p1")
    doc.stages = [ProjectStage(stageId: "s1", name: "Stage 1", cutIds: cuts)]
    return doc
}

private func withFinals(_ cuts: [String]) -> ProjectStageSetDocument {
    var doc = stageSet(cuts: cuts)
    for (index, cut) in cuts.enumerated() {
        doc = doc.addingFinal(cutId: cut, now: "t\(index)")
    }
    return doc
}

private func entryId(_ doc: ProjectStageSetDocument, cut: String) -> String {
    doc.finals.first { $0.cutId == cut }?.entryId ?? ""
}

private func clip(_ entry: String, seconds: Double) -> ReelBakedClip {
    ReelBakedClip(
        entryId: entry,
        cutId: "cut_\(entry)",
        url: URL(fileURLWithPath: "/tmp/\(entry).mp4"),
        durationSeconds: seconds
    )
}

private func seam(_ left: String, _ right: String, frames: Int) -> ReelSeamStyle {
    ReelSeamStyle(leftEntryId: left, rightEntryId: right, crossfadeFrames: frames, updatedAt: "t")
}

// MARK: - Persistence

@Test func reelFieldsDecodeTolerantlyAndRoundTrip() throws {
    // An old document without the fields decodes to empty reel state.
    let legacy = #"{"projectId":"p1","stages":[],"finals":[]}"#
    let decoded = try JSONDecoder().decode(
        ProjectStageSetDocument.self,
        from: Data(legacy.utf8)
    )
    #expect(decoded.reelAudio.isEmpty)
    #expect(decoded.reelSeams.isEmpty)

    // And the new fields round-trip.
    var doc = withFinals(["c1", "c2"])
    let left = entryId(doc, cut: "c1")
    let right = entryId(doc, cut: "c2")
    doc.reelSeams = [seam(left, right, frames: 12)]
    doc.reelAudio = [ShotAudioRegion(
        regionId: "reel_r1",
        laneId: reelMusicLaneId,
        label: "Score",
        path: "/audio/score.mp3",
        startSeconds: 0,
        durationSeconds: 30
    )]
    let data = try JSONEncoder().encode(doc)
    let back = try JSONDecoder().decode(ProjectStageSetDocument.self, from: data)
    #expect(back.reelSeams == doc.reelSeams)
    #expect(back.reelAudio.map(\.regionId) == ["reel_r1"])
}

// MARK: - Seam lifecycle

@Test func seamsReapWithTheirEntriesAndSurviveEverythingElse() {
    var doc = withFinals(["c1", "c2", "c3"])
    let e1 = entryId(doc, cut: "c1")
    let e2 = entryId(doc, cut: "c2")
    let e3 = entryId(doc, cut: "c3")
    doc.reelSeams = [seam(e1, e2, frames: 12), seam(e2, e3, frames: 24)]

    // Removing the middle pick kills BOTH seams that touch it.
    let removed = doc.removingFinal(entryId: e2, now: "t9")
    #expect(removed.reelSeams.isEmpty)

    // Trashing an end cut kills only its seam.
    let trashed = doc.trashingCut(cutId: "c1", now: "t9")
    #expect(trashed.reelSeams.map(\.id) == ["\(e2)>\(e3)"])

    // Reordering kills nothing (dormancy is a read-time concern).
    let moved = doc.movingFinal(entryId: e1, toIndex: 3, now: "t9")
    #expect(moved.reelSeams.count == 2)

    // normalized() drops orphans and duplicates but keeps valid seams.
    var dirty = doc
    dirty.reelSeams.append(seam(e1, e2, frames: 6))          // duplicate pair
    dirty.reelSeams.append(seam("ghost", e2, frames: 6))     // orphan side
    let clean = dirty.normalized()
    #expect(clean.reelSeams.map(\.id) == ["\(e1)>\(e2)", "\(e2)>\(e3)"])
    #expect(clean.reelSeams[0].crossfadeFrames == 12)        // first authored wins
}

@Test func seamAdjacencyGatesDormancyAndResurrection() {
    var doc = withFinals(["c1", "c2", "c3"])
    let e1 = entryId(doc, cut: "c1")
    let e2 = entryId(doc, cut: "c2")
    doc.reelSeams = [seam(e1, e2, frames: 12)]

    // Adjacent: active.
    #expect(reelActiveSeams(finals: doc.finals, seams: doc.reelSeams).map(\.id) == ["\(e1)>\(e2)"])

    // Reorder c1 to the end: the pair separates, the seam goes dormant —
    // kept in the document, absent from the active set.
    let separated = doc.movingFinal(entryId: e1, toIndex: 3, now: "t9")
    #expect(separated.reelSeams.count == 1)
    #expect(reelActiveSeams(finals: separated.finals, seams: separated.reelSeams).isEmpty)

    // Move it back: resurrection, no re-authoring.
    let restored = separated.movingFinal(entryId: e1, toIndex: 0, now: "t9")
    #expect(reelActiveSeams(finals: restored.finals, seams: restored.reelSeams).map(\.id) == ["\(e1)>\(e2)"])
}

// MARK: - Composition plan

@Test func hardCutsConcatenateKeptSpansExactly() {
    let plan = buildReelCompositionPlan(
        clips: [clip("a", seconds: 4), clip("b", seconds: 6)],
        seams: []
    )
    #expect(plan.specs.count == 2)
    #expect(plan.specs[0].keepRanges == [ShotKeepRange(start: 0, end: 4)])
    #expect(plan.specs[1].keepRanges == [ShotKeepRange(start: 0, end: 6)])
    #expect(plan.specs[1].transitionFramesBefore == 0)
    #expect(abs(plan.totalSeconds - 10) < 0.000_1)
    #expect(plan.cutBands.map(\.startSeconds) == [0, 4])
}

@Test func crossfadeShavesHalfEachSideAndConsumesDuration() {
    // THE REEL CROSSFADE LAW: 12 frames @24fps = 0.5s consumed; each side
    // sheds 0.25s of keepRange, which IS the handle the stitcher will find.
    let plan = buildReelCompositionPlan(
        clips: [clip("a", seconds: 4), clip("b", seconds: 6)],
        seams: [seam("a", "b", frames: 12)]
    )
    #expect(plan.appliedCrossfadeFrames["a>b"] == 12)
    #expect(plan.specs[0].keepRanges == [ShotKeepRange(start: 0, end: 4 - 0.25)])
    #expect(plan.specs[1].keepRanges == [ShotKeepRange(start: 0.25, end: 6)])
    #expect(plan.specs[1].transitionFramesBefore == 12)
    #expect(abs(plan.totalSeconds - 9.5) < 0.000_1)
    #expect(abs((plan.cutBands.last?.startSeconds ?? 0) - 3.75) < 0.000_1)
}

@Test func chainedCrossfadesResolveIndependentlyWhenBudgetsAllow() {
    let plan = buildReelCompositionPlan(
        clips: [clip("a", seconds: 8), clip("b", seconds: 8), clip("c", seconds: 8)],
        seams: [seam("a", "b", frames: 24), seam("b", "c", frames: 24)]
    )
    #expect(plan.appliedCrossfadeFrames["a>b"] == 24)
    #expect(plan.appliedCrossfadeFrames["b>c"] == 24)
    #expect(abs(plan.totalSeconds - (24 - 2)) < 0.000_1)
}

@Test func shortClipsCapSeamsToTheUnfadedMinimum() {
    // Middle clip is 1s = 24 frames. First seam takes the whole budget
    // (24 − 12 unfaded = 12 frames); the second seam caps to a stated hard
    // cut — a cut that is all crossfade is not a cut.
    let plan = buildReelCompositionPlan(
        clips: [clip("a", seconds: 8), clip("b", seconds: 1), clip("c", seconds: 8)],
        seams: [seam("a", "b", frames: 24), seam("b", "c", frames: 24)]
    )
    #expect(plan.appliedCrossfadeFrames["a>b"] == 12)
    #expect(plan.appliedCrossfadeFrames["b>c"] == 0)

    // A sliver clip refuses any fade at all.
    let sliver = buildReelCompositionPlan(
        clips: [clip("a", seconds: 8), clip("b", seconds: 0.5)],
        seams: [seam("a", "b", frames: 6)]
    )
    #expect(sliver.appliedCrossfadeFrames["a>b"] == 0)
    #expect(sliver.specs[1].transitionFramesBefore == 0)
}

@Test func singleClipRidesTheSamePath() {
    let plan = buildReelCompositionPlan(clips: [clip("a", seconds: 5)], seams: [])
    #expect(plan.specs.count == 1)
    #expect(plan.specs[0].keepRanges == [ShotKeepRange(start: 0, end: 5)])
    #expect(abs(plan.totalSeconds - 5) < 0.000_1)
}

// MARK: - Seam kinds & reel fades

@Test func seamKindDecodesTolerantlyAndRoundTrips() throws {
    // Pre-kind documents keep their exact meaning: crossfade.
    let legacy = try JSONDecoder().decode(
        ReelSeamStyle.self,
        from: Data(#"{"leftEntryId":"a","rightEntryId":"b","crossfadeFrames":12}"#.utf8)
    )
    #expect(legacy.kind == .crossfade)

    // Unknown kinds degrade to crossfade rather than dropping the seam.
    let unknown = try JSONDecoder().decode(
        ReelSeamStyle.self,
        from: Data(#"{"leftEntryId":"a","rightEntryId":"b","kind":"page_turn"}"#.utf8)
    )
    #expect(unknown.kind == .crossfade)

    // The dip round-trips under its stable raw value.
    let dip = ReelSeamStyle(
        leftEntryId: "a",
        rightEntryId: "b",
        kind: .dipToBlack,
        crossfadeFrames: 12,
        updatedAt: "t"
    )
    let back = try JSONDecoder().decode(ReelSeamStyle.self, from: JSONEncoder().encode(dip))
    #expect(back.kind == .dipToBlack)
}

@Test func dipConsumesExactlyWhatACrossfadeWouldAndThreadsItsStyle() {
    let crossfade = buildReelCompositionPlan(
        clips: [clip("a", seconds: 4), clip("b", seconds: 6)],
        seams: [seam("a", "b", frames: 12)]
    )
    var dipSeam = seam("a", "b", frames: 12)
    dipSeam.kind = .dipToBlack
    let dip = buildReelCompositionPlan(
        clips: [clip("a", seconds: 4), clip("b", seconds: 6)],
        seams: [dipSeam]
    )
    // Same frames, same shaves, same duration — only the style differs, so
    // the composer's plan-vs-stitcher duration assert can never learn about
    // kinds.
    #expect(dip.appliedCrossfadeFrames == crossfade.appliedCrossfadeFrames)
    #expect(dip.specs[0].keepRanges == crossfade.specs[0].keepRanges)
    #expect(dip.specs[1].keepRanges == crossfade.specs[1].keepRanges)
    #expect(abs(dip.totalSeconds - crossfade.totalSeconds) < 0.000_1)
    // The style rides the INCOMING spec only; the first spec never dips.
    #expect(dip.specs[1].transitionStyle == .dipThroughBlack)
    #expect(dip.specs[0].transitionStyle == .dissolve)
    #expect(crossfade.specs[1].transitionStyle == .dissolve)
}

@Test func reelFadesSnapAndClampIntoThePlan() {
    #expect(reelFadeSnappedFrames(10) == 12)
    #expect(reelFadeSnappedFrames(-3) == 0)
    #expect(reelFadeSnappedFrames(0) == 0)

    let plan = buildReelCompositionPlan(
        clips: [clip("a", seconds: 4), clip("b", seconds: 6)],
        seams: [],
        fadeInFrames: 10,
        fadeOutFrames: 24
    )
    #expect(plan.fadeInFrames == 12)
    #expect(plan.fadeOutFrames == 24)
    // Fades never move a band — duration-neutral by construction.
    #expect(abs(plan.totalSeconds - 10) < 0.000_1)

    // A tiny reel clamps each fade to half of itself (1s @24 → 12 frames).
    let tiny = buildReelCompositionPlan(
        clips: [clip("a", seconds: 1)],
        seams: [],
        fadeInFrames: 24,
        fadeOutFrames: 24
    )
    #expect(tiny.fadeInFrames == 12)
    #expect(tiny.fadeOutFrames == 12)
}

@Test func planFrameMathRidesTheGivenFps() {
    // 12 frames @30fps = 0.4s consumed — no /24 literal in the math.
    let plan = buildReelCompositionPlan(
        clips: [clip("a", seconds: 4), clip("b", seconds: 6)],
        seams: [seam("a", "b", frames: 12)],
        fps: 30
    )
    #expect(abs(plan.totalSeconds - 9.6) < 0.000_1)
}

@Test func outputSequenceReapsSeamsAndSnapsFadesOnNormalize() throws {
    // Tolerant decode: a doc written before fades reads them as off.
    let legacy = try JSONDecoder().decode(
        ProjectOutputSequenceDocument.self,
        from: Data(#"{"projectId":"p1","shots":[]}"#.utf8)
    )
    #expect(legacy.reelFadeInFrames == 0)
    #expect(legacy.reelFadeOutFrames == 0)

    var doc = ProjectOutputSequenceDocument(projectId: "p1")
    doc = doc.appendingShot("s1", now: "t1")
    doc = doc.appendingShot("s2", now: "t2")
    let e1 = doc.shots[0].entryId
    let e2 = doc.shots[1].entryId
    doc.reelSeams = [
        seam(e1, e2, frames: 12),
        seam(e1, e2, frames: 6),        // duplicate pair — first authored wins
        seam("ghost", e2, frames: 6),   // orphan side — reaped
        seam(e1, e1, frames: 6)         // self seam — reaped
    ]
    doc.reelFadeInFrames = 10
    doc.reelFadeOutFrames = -2
    let clean = doc.normalized()
    #expect(clean.reelSeams.map(\.id) == ["\(e1)>\(e2)"])
    #expect(clean.reelSeams[0].crossfadeFrames == 12)
    #expect(clean.reelFadeInFrames == 12)
    #expect(clean.reelFadeOutFrames == 0)

    // Round-trip keeps the fades.
    let back = try JSONDecoder().decode(
        ProjectOutputSequenceDocument.self,
        from: JSONEncoder().encode(clean)
    )
    #expect(back.reelFadeInFrames == 12)
}

// MARK: - Fingerprints

private func reelFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        label: "Frame \(id)",
        imagePath: "/tmp/\(id).png",
        prompt: "A quiet harbor \(id)",
        status: "ready"
    )
}

private let reelFrames: [String: ProjectLensHeroImage] = [
    "f1": reelFrame("f1"),
    "f2": reelFrame("f2")
]

private func reelShot() -> ProjectShot {
    var artifact = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "ready",
        generatedAt: "t0",
        updatedAt: "t0"
    )
    artifact.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: "/tmp/a.mp4",
        updatedAt: "t0"
    ))
    let shot = ProjectShot(
        shotId: "shot_reel_fp",
        name: "Reel FP",
        entries: [
            ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
            ShotFrameEntry(entryId: "e2", frameImageId: "f2")
        ]
    )
    return shot.upsertingRenderVersion(artifact, activate: true, now: "t0")
}

private func reelAssembly(_ shot: ProjectShot, durations: [String: Double]) -> ShotCutAssembly {
    let plan = shotRenderSegmentPlan(
        shot: shot,
        frameLookup: reelFrames,
        mediaLookup: [:],
        meaningNodes: []
    )
    return shotCutAssembly(
        shot: shot,
        planSegments: plan.segments,
        clipDurationsByPath: durations,
        fileExists: { _ in true }
    )
}

@Test func bakeFingerprintExcludesDurationsAndTracksTheMix() {
    let shot = reelShot()
    let profile = VideoOutputProfile.standard(.landscape16x9, fitPolicy: .fitWithBlurFill)

    // Deterministic: the bake lane fingerprints the duration-RESOLVED
    // assembly for both the staleness check and the bake itself, so the same
    // inputs must always produce the same identity.
    let early = shotReelBakeFingerprint(
        shot: shot,
        assembly: reelAssembly(shot, durations: ["/tmp/a.mp4": 4]),
        profile: profile
    )
    let again = shotReelBakeFingerprint(
        shot: shot,
        assembly: reelAssembly(shot, durations: ["/tmp/a.mp4": 4]),
        profile: profile
    )
    #expect(early == again)

    // Any mix change invalidates — the bake carries the audio.
    var withAudio = shot
    withAudio.audioRegions = [ShotAudioRegion(
        regionId: "r1",
        laneId: ShotAudioLaneId.clip,
        path: "/audio/a.mp3",
        startSeconds: 0,
        durationSeconds: 2
    )]
    let changed = shotReelBakeFingerprint(
        shot: withAudio,
        assembly: reelAssembly(withAudio, durations: ["/tmp/a.mp4": 4]),
        profile: profile
    )
    #expect(changed != early)

    // The shared audio fingerprint moves with a gain edit — the same
    // function feeds the player's reload key, so the two cannot drift.
    var quieter = withAudio
    quieter.audioRegions[0].gain = 0.5
    #expect(shotAudioMixFingerprint(shot: quieter) != shotAudioMixFingerprint(shot: withAudio))
}

@Test func bakeFingerprintTracksReferencedAudioFileIdentity() {
    // The Dropbox lesson: a bake made while a music file was unreadable
    // cached silence forever, because nothing about the FILE was part of the
    // cache identity. Size+mtime tokens now ride the fingerprint — but only
    // for files the document expects to hear, so a muted region's file can
    // churn without invalidating anything.
    var shot = reelShot()
    shot.audioRegions = [ShotAudioRegion(
        regionId: "r1",
        laneId: ShotAudioLaneId.clip,
        path: "/audio/a.mp3",
        startSeconds: 0,
        durationSeconds: 2
    )]
    let profile = VideoOutputProfile.standard(.landscape16x9, fitPolicy: .fitWithBlurFill)
    let before = shotReelBakeFingerprint(
        shot: shot,
        assembly: reelAssembly(shot, durations: ["/tmp/a.mp4": 4]),
        profile: profile,
        fileToken: { _ in "100:1.000" }
    )
    let same = shotReelBakeFingerprint(
        shot: shot,
        assembly: reelAssembly(shot, durations: ["/tmp/a.mp4": 4]),
        profile: profile,
        fileToken: { _ in "100:1.000" }
    )
    #expect(before == same)
    let swappedContent = shotReelBakeFingerprint(
        shot: shot,
        assembly: reelAssembly(shot, durations: ["/tmp/a.mp4": 4]),
        profile: profile,
        fileToken: { _ in "100:2.000" }
    )
    #expect(swappedContent != before)

    var muted = shot
    muted.audioRegions[0].isMuted = true
    let mutedEarly = shotReelBakeFingerprint(
        shot: muted,
        assembly: reelAssembly(muted, durations: ["/tmp/a.mp4": 4]),
        profile: profile,
        fileToken: { _ in "100:1.000" }
    )
    let mutedLate = shotReelBakeFingerprint(
        shot: muted,
        assembly: reelAssembly(muted, durations: ["/tmp/a.mp4": 4]),
        profile: profile,
        fileToken: { _ in "100:2.000" }
    )
    #expect(mutedEarly == mutedLate)
}

@Test func bakeSidecarDecodesTolerantly() throws {
    let decoded = try JSONDecoder().decode(
        ReelBakeSidecar.self,
        from: Data(#"{"fingerprint":"abc"}"#.utf8)
    )
    #expect(decoded.fingerprint == "abc")
    #expect(decoded.durationSeconds == 0)
}
