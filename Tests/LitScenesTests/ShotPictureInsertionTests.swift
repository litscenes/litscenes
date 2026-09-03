import Foundation
import Testing
@testable import LitScenes

// MARK: Fixtures

private func insertionFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        label: "Frame \(id)",
        imagePath: "/tmp/\(id).png",
        prompt: "A quiet harbor scene \(id)",
        status: "ready"
    )
}

private let insertionFrameLookup: [String: ProjectLensHeroImage] = [
    "f1": insertionFrame("f1"),
    "f2": insertionFrame("f2"),
    "f3": insertionFrame("f3")
]

private func approx(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.001) -> Bool {
    abs(lhs - rhs) <= tolerance
}

/// A shot with one rendered generated pair f1>f2 whose take is
/// `/tmp/take_one.mp4` (7.9s), matching the cut-layer test fixtures.
private func renderedPairShot() -> ProjectShot {
    var artifact = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "ready",
        generatedAt: "2026-08-04T00:00:00Z",
        updatedAt: "2026-08-04T00:00:00Z"
    )
    artifact.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: "/tmp/take_one.mp4",
        updatedAt: "2026-08-04T00:00:00Z"
    ))
    var shot = ProjectShot(shotId: "shot_ins", name: "Insertions", entries: [
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ])
    shot = shot.upsertingRenderVersion(artifact, activate: true, now: "2026-08-04T00:00:00Z")
    return shot
}

private func assemblyOf(
    _ shot: ProjectShot,
    durations: [String: Double] = ["/tmp/take_one.mp4": 7.9],
    fileExists: @escaping (String) -> Bool = { _ in true }
) -> ShotCutAssembly {
    let plan = shotRenderSegmentPlan(
        shot: shot,
        frameLookup: insertionFrameLookup,
        mediaLookup: [:],
        meaningNodes: []
    )
    return shotCutAssembly(
        shot: shot,
        planSegments: plan.segments,
        clipDurationsByPath: durations,
        fileExists: fileExists
    )
}

private func loopInsertion(
    id: String = "pins_1",
    source: ClosedRange<Double> = 2...4,
    anchor: Double = 4,
    rate: Double = 1,
    muted: Bool = false
) -> ShotPictureInsertion {
    ShotPictureInsertion(
        insertionId: id,
        sourceSegmentKey: "f1>f2",
        sourceClipPath: "/tmp/take_one.mp4",
        sourceStartSeconds: source.lowerBound,
        sourceEndSeconds: source.upperBound,
        anchorSegmentKey: "f1>f2",
        anchorSeconds: anchor,
        playbackRate: rate,
        muteSourceAudio: muted
    )
}

// MARK: Model tolerance

@Test func insertionDecodeToleratesMissingAndUnknownFields() throws {
    let json = #"{"insertionId":"pins_x","sourceSegmentKey":"f1>f2","sourceClipPath":"/tmp/t.mp4","sourceStartSeconds":1,"sourceEndSeconds":2,"anchorSegmentKey":"f1>f2","futureField":{"deep":true}}"#
    let decoded = try JSONDecoder().decode(ShotPictureInsertion.self, from: Data(json.utf8))
    #expect(decoded.insertionId == "pins_x")
    #expect(decoded.playbackRate == 1)
    #expect(!decoded.muteSourceAudio)
    #expect(decoded.transformKind.isEmpty)
}

@Test func projectShotDecodeWithoutInsertionsIsToday() throws {
    let json = #"{"shotId":"shot_a","entries":[]}"#
    let decoded = try JSONDecoder().decode(ProjectShot.self, from: Data(json.utf8))
    #expect(decoded.pictureInsertions.isEmpty)
}

@Test func projectShotInsertionsRoundTrip() throws {
    var shot = renderedPairShot()
    shot.pictureInsertions = [loopInsertion()]
    let data = try JSONEncoder().encode(shot)
    let decoded = try JSONDecoder().decode(ProjectShot.self, from: data)
    #expect(decoded.pictureInsertions == shot.pictureInsertions)
}

@Test func insertionNormalizedClampsRateAndOrdersBounds() {
    var raw = loopInsertion(rate: 99)
    raw.sourceStartSeconds = 4
    raw.sourceEndSeconds = 2
    let value = raw.normalized()
    #expect(value.playbackRate == ShotPictureInsertion.maximumRate)
    #expect(value.sourceStartSeconds == 2)
    #expect(value.sourceEndSeconds == 4)
    #expect(loopInsertion(rate: 0.01).normalized().playbackRate == ShotPictureInsertion.minimumRate)
}

@Test func pruningDropsDeadAnchorsAndJunkSources() {
    let entries = [
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ]
    var deadAnchor = loopInsertion(id: "pins_dead")
    deadAnchor.anchorSegmentKey = "f9>f10"
    var placementAnchor = loopInsertion(id: "pins_live")
    placementAnchor.anchorSegmentKey = "entry:e1>e2"
    var tinySource = loopInsertion(id: "pins_tiny", source: 2...2.01)
    var pathless = loopInsertion(id: "pins_none")
    pathless.sourceClipPath = ""
    let kept = pruningPictureInsertions(
        [deadAnchor, placementAnchor, tinySource, pathless, loopInsertion(id: "pins_legacy")],
        entries: entries
    )
    #expect(kept.map(\.insertionId) == ["pins_live", "pins_legacy"])
}

@Test func snapshotCarriesInsertionsAndTwinClearsThem() {
    var shot = renderedPairShot()
    shot.pictureInsertions = [loopInsertion()]
    let snapshot = shot.pictureStateSnapshot()
    #expect(snapshot.pictureInsertions.count == 1)

    var stripped = shot
    stripped.pictureInsertions = []
    let restored = stripped.restoringPictureState(snapshot, now: "2026-08-04T00:00:01Z")
    #expect(restored.pictureInsertions.map(\.insertionId) == ["pins_1"])

    #expect(shot.duplicated(now: "2026-08-04T00:00:02Z").pictureInsertions.isEmpty)
}

// MARK: Splice — position law

@Test func spliceLoopsAfterCopiedSpanWithDerivedSplit() {
    var shot = renderedPairShot()
    shot.pictureInsertions = [loopInsertion()]
    let assembly = assemblyOf(shot)

    // keep(0–4) · copy(2–4) · keep(4–7.9) — the split is derived, the
    // persisted cut list stays empty.
    #expect(shot.cutList.isEmpty)
    #expect(assembly.playbackItems.count == 3)
    #expect(assembly.playbackItems[1].insertionId == "pins_1")
    #expect(assembly.playbackItems[0].keepRange == ShotKeepRange(start: 0, end: 4))
    #expect(assembly.playbackItems[1].keepRange == ShotKeepRange(start: 2, end: 4))
    #expect(assembly.playbackItems[2].keepRange == ShotKeepRange(start: 4, end: 7.9))
    #expect(approx(assembly.playbackItems[1].outputStartSeconds, 4))
    #expect(approx(assembly.playbackItems[2].outputStartSeconds, 6))
    #expect(approx(assembly.outputSeconds, 9.9))
    // The copy honestly revisits its source material on the strip.
    #expect(approx(assembly.playbackItems[1].materialStartSeconds, 2))
    #expect(approx(assembly.playbackItems[1].materialEndSeconds, 4))
    // Cells report the fresh copy at its output position.
    #expect(assembly.insertionCells.count == 1)
    #expect(assembly.insertionCells[0].state == .fresh)
    #expect(approx(assembly.insertionCells[0].outputStartSeconds, 4))
    #expect(assembly.insertionCells[0].afterBandIndex == 0)
}

@Test func spliceSnapsToKeepBoundariesWithoutSplitting() {
    var shot = renderedPairShot()
    shot.pictureInsertions = [loopInsertion(anchor: 7.9)]
    let assembly = assemblyOf(shot)
    #expect(assembly.playbackItems.count == 2)
    #expect(assembly.playbackItems[1].insertionId == "pins_1")
    #expect(approx(assembly.playbackItems[1].outputStartSeconds, 7.9))
    #expect(approx(assembly.outputSeconds, 9.9))
}

@Test func splicePreservesPasteOrderAtOneAnchor() {
    var shot = renderedPairShot()
    shot.pictureInsertions = [
        loopInsertion(id: "pins_first", anchor: 7.9),
        loopInsertion(id: "pins_second", anchor: 7.9)
    ]
    let assembly = assemblyOf(shot)
    #expect(assembly.playbackItems.map(\.insertionId) == ["", "pins_first", "pins_second"])
}

@Test func spliceOrdersMultipleLoopCopiesLikeAudioTiles() {
    var shot = renderedPairShot()
    shot.pictureInsertions = [
        loopInsertion(id: "pins_a"),
        loopInsertion(id: "pins_b")
    ]
    let assembly = assemblyOf(shot)
    // keep(0–4) · a(2–4) · b(2–4) · keep(4–7.9): a 2s beat looped ×2.
    #expect(assembly.playbackItems.map(\.insertionId) == ["", "pins_a", "pins_b", ""])
    #expect(approx(assembly.outputSeconds, 11.9))
}

@Test func spliceRespectsRazorsInTheAnchorBand() {
    var shot = renderedPairShot()
    shot.cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(segmentKey: "f1>f2", clipPath: "/tmp/take_one.mp4", startSeconds: 5, endSeconds: 6)
    ])
    // Anchor inside the razored gap snaps forward to the next kept boundary.
    shot.pictureInsertions = [loopInsertion(source: 2...4, anchor: 5.5)]
    let assembly = assemblyOf(shot)
    #expect(assembly.playbackItems.count == 3)
    #expect(assembly.playbackItems[0].keepRange == ShotKeepRange(start: 0, end: 5))
    #expect(assembly.playbackItems[1].insertionId == "pins_1")
    #expect(assembly.playbackItems[2].keepRange == ShotKeepRange(start: 6, end: 7.9))
}

@Test func spliceReplacePatternPlaysCopyWhereSeamCutBeatWas() {
    // Three frames, two pairs; the first pair is seam-cut away; a copy of it
    // anchored by placement key still plays exactly where the beat was.
    var v1 = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "ready",
        generatedAt: "2026-08-04T00:00:00Z",
        updatedAt: "2026-08-04T00:00:00Z"
    )
    v1.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        placementStartEntryId: "e1",
        placementEndEntryId: "e2",
        clipPath: "/tmp/pair_one.mp4",
        updatedAt: "2026-08-04T00:00:00Z"
    ))
    v1.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f2",
        endFrameImageId: "f3",
        placementStartEntryId: "e2",
        placementEndEntryId: "e3",
        clipPath: "/tmp/pair_two.mp4",
        updatedAt: "2026-08-04T00:00:00Z"
    ))
    var shot = ProjectShot(shotId: "shot_replace", name: "Replace", entries: [
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2"),
        ShotFrameEntry(entryId: "e3", frameImageId: "f3")
    ])
    shot = shot.upsertingRenderVersion(v1, activate: true, now: "2026-08-04T00:00:00Z")

    let durations = ["/tmp/pair_one.mp4": 8.0, "/tmp/pair_two.mp4": 8.0]
    let before = assemblyOf(shot, durations: durations)
    let pairOneKey = before.bands[0].segmentKey
    #expect(pairOneKey == "entry:e1>e2")

    // Copy a beat of pair one, then seam-cut pair one away (skip = free).
    shot.pictureInsertions = [ShotPictureInsertion(
        insertionId: "pins_replace",
        sourceSegmentKey: pairOneKey,
        sourceClipPath: "/tmp/pair_one.mp4",
        sourceStartSeconds: 3,
        sourceEndSeconds: 5,
        anchorSegmentKey: pairOneKey,
        anchorSeconds: 5,
        playbackRate: 0.5
    )]
    shot = shot.settingSeamStyle(
        entryId: "e2",
        style: .cut,
        intent: .explicit,
        now: "2026-08-04T00:00:01Z"
    )
    let after = assemblyOf(shot, durations: durations)
    // Pair one is gone from the plan; the slow-mo copy plays FIRST — exactly
    // where the beat was — followed by pair two. Source stays fresh: the
    // retained take is still the playable version's clip for its key.
    #expect(after.playbackItems.count == 2)
    #expect(after.playbackItems[0].insertionId == "pins_replace")
    #expect(approx(after.playbackItems[0].durationSeconds, 4))  // 2s ÷ 0.5
    #expect(after.playbackItems[0].stitchSpec.rate == 0.5)
    #expect(after.playbackItems[1].insertionId.isEmpty)
}

// MARK: Splice — freshness ladder

@Test func spliceGoesInertOnOlderTakeAndRecovers() {
    var shot = renderedPairShot()
    shot.pictureInsertions = [loopInsertion()]

    // A re-render lands: the active take moves to take_two.
    var v2 = ShotRenderArtifact(
        versionId: "v2",
        versionNumber: 2,
        status: "ready",
        generatedAt: "2026-08-04T00:01:00Z",
        updatedAt: "2026-08-04T00:01:00Z"
    )
    v2.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: "/tmp/take_two.mp4",
        updatedAt: "2026-08-04T00:01:00Z"
    ))
    let rerendered = shot.upsertingRenderVersion(v2, activate: true, now: "2026-08-04T00:01:00Z")
    let assembly = assemblyOf(rerendered, durations: ["/tmp/take_two.mp4": 7.9])

    // The copy contributes nothing (never silently swaps pixels) and is
    // badged for the operator; no derived split is left behind.
    #expect(assembly.playbackItems.count == 1)
    #expect(assembly.playbackItems[0].insertionId.isEmpty)
    #expect(assembly.insertionCells.count == 1)
    #expect(assembly.insertionCells[0].state == .olderTake)
    #expect(assembly.insertionCells[0].state.badge == "OLDER TAKE")
    #expect(approx(assembly.outputSeconds, 7.9))
}

@Test func spliceReportsMissingSourceFileAndUnsupportedTransform() {
    var shot = renderedPairShot()
    var future = loopInsertion(id: "pins_future")
    future.transformKind = "restyle"
    shot.pictureInsertions = [loopInsertion(id: "pins_gone"), future]
    let assembly = assemblyOf(shot, fileExists: { $0 != "/tmp/take_one.mp4" })
    // take_one is the active take but its file is gone: base band is honest
    // (plays nothing) and both copies are inert with their own reasons.
    #expect(assembly.insertionCells.map(\.state) == [.sourceMissing, .unsupportedTransform])
    #expect(assembly.playbackItems.allSatisfy { $0.insertionId.isEmpty })
}

// MARK: Splice — modifiers

@Test func spliceAppliesRateAndMuteToTheCopyOnly() {
    var shot = renderedPairShot()
    shot.pictureInsertions = [loopInsertion(rate: 0.5, muted: true)]
    let assembly = assemblyOf(shot)
    let copy = assembly.playbackItems[1]
    #expect(copy.insertionId == "pins_1")
    #expect(approx(copy.durationSeconds, 4))  // 2s at half speed
    #expect(!copy.includeAudio)
    #expect(copy.playbackRate == 0.5)
    #expect(copy.stitchSpec.rate == 0.5)
    // Base spans are untouched.
    #expect(assembly.playbackItems[0].includeAudio)
    #expect(assembly.playbackItems[0].playbackRate == 1)
    #expect(approx(assembly.outputSeconds, 7.9 + 4))
}

@Test func outputSegmentsNeverMergeACopyWithItsSource() {
    var shot = renderedPairShot()
    shot.pictureInsertions = [loopInsertion()]
    let assembly = assemblyOf(shot)
    let segments = assembly.outputPictureSegments
    // keep · copy · keep — three spans, the copy flagged, no fusion.
    #expect(segments.count == 3)
    #expect(!segments[0].isInsertion)
    #expect(segments[1].isInsertion)
    #expect(!segments[2].isInsertion)
}

// MARK: Reverse rides free

@Test func reversedItemsCarryTheCopyAndItsRate() {
    var shot = renderedPairShot()
    shot.pictureInsertions = [loopInsertion(rate: 0.5)]
    let forward = assemblyOf(shot)
    let proxies = [
        "/tmp/take_one.mp4": ShotReverseProxyArtifact(
            proxyId: "p1",
            sourcePath: "/tmp/take_one.mp4",
            sourceDurationSeconds: 7.9,
            proxyDurationSeconds: 7.9,
            proxyPath: "/tmp/rev_take_one.mp4",
            hasReversedAudio: true,
            status: "ready"
        )
    ]
    let reversed = reversedShotCutAssembly(forward, proxies: proxies)
    #expect(reversed.isReversed)
    let copy = reversed.playbackItems.first { $0.isInsertion }
    #expect(copy != nil)
    #expect(copy?.playsReversed == true)
    #expect(copy?.playbackRate == 0.5)
    #expect(approx(reversed.outputSeconds, forward.outputSeconds))
    // Mirrored into proxy coordinates: 7.9 − [2,4] = [3.9, 5.9].
    #expect(copy.flatMap(\.keepRange).map { approx($0.start, 3.9) && approx($0.end, 5.9) } == true)
}

// MARK: WYSIWYG copy + paste anchors

@Test func copiedSpansCaptureKeptMaterialOnly() {
    var shot = renderedPairShot()
    shot.cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(segmentKey: "f1>f2", clipPath: "/tmp/take_one.mp4", startSeconds: 3, endSeconds: 5)
    ])
    let assembly = assemblyOf(shot)
    // Selection [2, 6] material crosses the razored gap [3, 5): two spans,
    // the removed material never captured.
    let spans = shotCopiedSpans(assembly: assembly, materialStart: 2, materialEnd: 6)
    #expect(spans.count == 2)
    #expect(approx(spans[0].startSeconds, 2) && approx(spans[0].endSeconds, 3))
    #expect(approx(spans[1].startSeconds, 5) && approx(spans[1].endSeconds, 6))
    #expect(spans.allSatisfy { $0.segmentKey == "f1>f2" && $0.mediaId.isEmpty })
}

@Test func copiedSpansSkipArrangedCopiesSoLoopsCopyOnce() {
    var shot = renderedPairShot()
    shot.pictureInsertions = [loopInsertion()]
    let assembly = assemblyOf(shot)
    // Selecting all material over a looped shot captures the base once.
    let spans = shotCopiedSpans(assembly: assembly, materialStart: 0, materialEnd: 7.9)
    #expect(spans.count == 1)
    #expect(approx(spans[0].startSeconds, 0) && approx(spans[0].endSeconds, 7.9))
}

@Test func pasteAnchorResolvesBaseCopyAndPastEnd() {
    var shot = renderedPairShot()
    shot.pictureInsertions = [loopInsertion()]
    let assembly = assemblyOf(shot)
    // Inside the base head: anchors into the segment at file-local seconds.
    let base = shotPasteAnchor(assembly: assembly, outputSeconds: 1)
    #expect(base?.segmentKey == "f1>f2")
    #expect(base.map { approx($0.anchorSeconds, 1) } == true)
    // Inside the arranged copy (output 4–6): adopts the copy's own anchor,
    // so the paste lands after the run.
    let inCopy = shotPasteAnchor(assembly: assembly, outputSeconds: 5)
    #expect(inCopy?.segmentKey == "f1>f2")
    #expect(inCopy.map { approx($0.anchorSeconds, 4) } == true)
    // Past the end: after the last base span.
    let pastEnd = shotPasteAnchor(assembly: assembly, outputSeconds: 99)
    #expect(pastEnd.map { approx($0.anchorSeconds, 7.9) } == true)
}

@Test func insertionRunsConsolidateUniformSiblingsOnly() {
    var shot = renderedPairShot()
    var a = loopInsertion(id: "pins_a")
    var b = loopInsertion(id: "pins_b")
    var c = loopInsertion(id: "pins_c", rate: 0.5)
    a.loopGroupId = "loopg_1"
    b.loopGroupId = "loopg_1"
    c.loopGroupId = "loopg_1"
    shot.pictureInsertions = [a, b, c]
    let assembly = assemblyOf(shot)
    let runs = shotInsertionCellRuns(assembly.insertionCells)
    // a+b consolidate (uniform); c differs in rate and stands alone.
    #expect(runs.map(\.count) == [2, 1])
    #expect(shotInsertionRun(in: assembly.insertionCells, leaderId: "pins_a")?.count == 2)
    #expect(shotInsertionRun(in: assembly.insertionCells, leaderId: "pins_c")?.count == 1)
    // A non-leader id fronts no run.
    #expect(shotInsertionRun(in: assembly.insertionCells, leaderId: "pins_b") == nil)
}

// MARK: Sweep predicate (THE PIN SWEEP LAW for copies)

@Test func staleInsertionIdsMirrorTheRazorPinSweep() {
    var shot = renderedPairShot()
    var orphan = loopInsertion(id: "pins_orphan")
    orphan.sourceClipPath = "/tmp/take_zero.mp4"  // in no retained take
    var footage = loopInsertion(id: "pins_footage")
    footage.sourceMediaId = "vid_1"
    footage.sourceClipPath = "/tmp/gone.mp4"      // footage: never swept here
    shot.pictureInsertions = [loopInsertion(id: "pins_live"), orphan, footage]
    #expect(shotStalePictureInsertionIds(shot: shot) == ["pins_orphan"])
}

// MARK: Runtime mirror

@Test func runtimeSummaryCountsFreshLoopSecondsOnly() {
    var shot = renderedPairShot()
    shot.pictureInsertions = [loopInsertion(rate: 0.5)]
    #expect(approx(shotPictureInsertionRuntimeSeconds(shot: shot), 4))
    let summary = shotRuntimeSummary(shot: shot, frameLookup: insertionFrameLookup, mediaLookup: [:])
    #expect(approx(summary.loopSeconds, 4))
    #expect(summary.railLabel(generatedSeconds: 7.9).contains("⟳+4S"))

    // After a re-render the copy is inert — the rail must not count it.
    var v2 = ShotRenderArtifact(
        versionId: "v2",
        versionNumber: 2,
        status: "ready",
        generatedAt: "2026-08-04T00:01:00Z",
        updatedAt: "2026-08-04T00:01:00Z"
    )
    v2.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: "/tmp/take_two.mp4",
        updatedAt: "2026-08-04T00:01:00Z"
    ))
    let rerendered = shot.upsertingRenderVersion(v2, activate: true, now: "2026-08-04T00:01:00Z")
    #expect(shotPictureInsertionRuntimeSeconds(shot: rerendered) == 0)
}

// MARK: Splice — THE MATERIAL-WINDOW LAW (shot IN/OUT vs arranged copies)

@Test func outTrimClampsCopyOfTailMaterial() {
    // Copy of [5, 7.9] anchored at 5, OUT at 6: the copy plays only the
    // window's share of its material, exactly like a base keep would.
    var shot = renderedPairShot()
    shot.cutList.shotOutSeconds = 6
    shot.pictureInsertions = [loopInsertion(id: "pins_tail", source: 5...7.9, anchor: 5, rate: 2)]
    let assembly = assemblyOf(shot)
    let copy = assembly.playbackItems.first { $0.insertionId == "pins_tail" }
    #expect(copy?.keepRange == ShotKeepRange(start: 5, end: 6))
    #expect(copy.map { approx($0.durationSeconds, 0.5) } == true)
    #expect(assembly.insertionCells.first?.state == .fresh)
    // The cell reports the PLACED seconds — strip geometry must shrink with
    // the OUT handle, not draw the authored 1.45s.
    #expect(assembly.insertionCells.first.map { approx($0.placedOutputSeconds, 0.5) } == true)
    // Base [0, 5] + copy 0.5 + base [5, 6].
    #expect(approx(assembly.outputSeconds, 6.5))
}

@Test func outTrimAtTheCarrierAnchorGatesItWhole() {
    // The screenshot case's boundary: OUT exactly at the carrier's splice
    // point. The gate's bounds are CLOSED (a paste at the boundary plays),
    // so what kills the carrier is the SOURCE clamp — its span [5.5, 7.9] is
    // entirely out-of-window material — and it says why instead of vanishing.
    var shot = renderedPairShot()
    shot.cutList.segmentCuts = [
        ShotSegmentCutRange(segmentKey: "f1>f2", clipPath: "/tmp/take_one.mp4", startSeconds: 5.5, endSeconds: 7.9)
    ]
    shot.cutList.shotOutSeconds = 5.5
    shot.pictureInsertions = [loopInsertion(id: "pins_carrier", source: 5.5...7.9, anchor: 5.5, rate: 2)]
    let assembly = assemblyOf(shot)
    #expect(!assembly.playbackItems.contains { $0.insertionId == "pins_carrier" })
    #expect(assembly.insertionCells.first?.state == .trimmedOut)
    #expect(approx(assembly.outputSeconds, 5.5))

    // Nudge OUT past the anchor and the carrier returns, clipped to the window.
    var nudged = shot
    nudged.cutList.shotOutSeconds = 5.7
    let nudgedAssembly = assemblyOf(nudged)
    let carrier = nudgedAssembly.playbackItems.first { $0.insertionId == "pins_carrier" }
    #expect(carrier?.keepRange == ShotKeepRange(start: 5.5, end: 5.7))
    #expect(carrier.map { approx($0.durationSeconds, 0.1) } == true)
    #expect(approx(nudgedAssembly.outputSeconds, 5.6))
}

@Test func outTrimGatesCopyAnchoredPastOut() {
    // A copy of EARLY material pasted at the tail lives at the tail: trimming
    // the tail away trims the copy, whatever material it shows.
    var shot = renderedPairShot()
    shot.cutList.shotOutSeconds = 4
    shot.pictureInsertions = [loopInsertion(id: "pins_late", source: 1...2, anchor: 7.9)]
    let assembly = assemblyOf(shot)
    #expect(!assembly.playbackItems.contains { $0.insertionId == "pins_late" })
    #expect(assembly.insertionCells.first?.state == .trimmedOut)
    #expect(approx(assembly.outputSeconds, 4))
}

@Test func inTrimGatesCopyAnchoredBeforeIn() {
    var shot = renderedPairShot()
    shot.cutList.shotInSeconds = 3
    shot.pictureInsertions = [loopInsertion(id: "pins_early", source: 5...6, anchor: 1)]
    let assembly = assemblyOf(shot)
    #expect(!assembly.playbackItems.contains { $0.insertionId == "pins_early" })
    #expect(assembly.insertionCells.first?.state == .trimmedOut)
    #expect(approx(assembly.outputSeconds, 4.9))
}

@Test func windowClampBelowRazorMinimumGoesTrimmedOut() {
    // Inside the window by an eyelash, but the clamped span is a sub-minimum
    // sliver: honest TRIMMED OUT, never a 20ms blip.
    var shot = renderedPairShot()
    shot.cutList.shotOutSeconds = 5.02
    shot.pictureInsertions = [loopInsertion(id: "pins_sliver", source: 5...7, anchor: 5)]
    let assembly = assemblyOf(shot)
    #expect(!assembly.playbackItems.contains { $0.insertionId == "pins_sliver" })
    #expect(assembly.insertionCells.first?.state == .trimmedOut)
    #expect(approx(assembly.outputSeconds, 5.02))
}

@Test func untrimmedSpliceIsUntouchedByTheWindowLaw() {
    // Regression pin: with no IN/OUT set, the window law is inert — same
    // items, same keeps, same output as the position-law tests above.
    var shot = renderedPairShot()
    shot.pictureInsertions = [loopInsertion()]
    let assembly = assemblyOf(shot)
    #expect(assembly.playbackItems.count == 3)
    #expect(assembly.playbackItems[1].keepRange == ShotKeepRange(start: 2, end: 4))
    #expect(approx(assembly.outputSeconds, 9.9))
    #expect(assembly.insertionCells.first?.state == .fresh)
}

@Test func windowClampBelowMinimumLeavesNoDerivedSplitBehind() {
    // The verdict must be total BEFORE position resolution: a copy the clamp
    // excludes, anchored strictly INSIDE a kept span (where a fresh copy
    // would derive a split), must leave the base items untouched — no orphan
    // _a/_b halves, no phantom hard cut.
    var shot = renderedPairShot()
    shot.cutList.shotOutSeconds = 5.02
    shot.pictureInsertions = [loopInsertion(id: "pins_ghost", source: 5...7, anchor: 2)]
    let assembly = assemblyOf(shot)
    #expect(assembly.playbackItems.count == 1)
    #expect(!assembly.playbackItems.contains { $0.itemId.hasSuffix("_a") || $0.itemId.hasSuffix("_b") })
    #expect(assembly.insertionCells.first?.state == .trimmedOut)
    #expect(assembly.insertionCells.first.map { approx($0.placedOutputSeconds, 0) } == true)
    #expect(approx(assembly.outputSeconds, 5.02))
}

@Test func copyOfOutOfWindowMaterialIsTrimmedWhereverPasted() {
    // THE MATERIAL-WINDOW LAW's ratified half: the window hides material
    // everywhere, copies included. A copy pasted INSIDE the window whose
    // source span is entirely outside it plays nothing — badged, not silent.
    var shot = renderedPairShot()
    shot.cutList.shotInSeconds = 3
    shot.pictureInsertions = [loopInsertion(id: "pins_flashback", source: 0.5...2, anchor: 5)]
    let assembly = assemblyOf(shot)
    #expect(!assembly.playbackItems.contains { $0.insertionId == "pins_flashback" })
    #expect(assembly.insertionCells.first?.state == .trimmedOut)
    #expect(approx(assembly.outputSeconds, 4.9))
}

@Test func pasteAtTheTrimmedTailStillPlays() {
    // The gate's bounds are CLOSED: the tail of a trimmed shot's kept output
    // — exactly where shotPasteAnchor lands a paste — is a legal home for a
    // copy of in-window material.
    var shot = renderedPairShot()
    shot.cutList.shotOutSeconds = 6
    shot.pictureInsertions = [loopInsertion(id: "pins_tailpaste", source: 1...2, anchor: 6)]
    let assembly = assemblyOf(shot)
    let copy = assembly.playbackItems.first { $0.insertionId == "pins_tailpaste" }
    #expect(copy?.keepRange == ShotKeepRange(start: 1, end: 2))
    #expect(copy.map { approx($0.outputStartSeconds, 6) } == true)
    #expect(assembly.insertionCells.first?.state == .fresh)
    #expect(assembly.insertionCells.first.map { approx($0.placedOutputSeconds, 1) } == true)
    #expect(approx(assembly.outputSeconds, 7))
}

@Test func highRateCarrierClampedBelowTwoOutputFramesIsTrimmed() {
    // THE 2-FRAME OUTPUT LAW's floor rides the clamp: a rate-8 carrier whose
    // clamped source span would play under two output frames goes TRIMMED
    // OUT instead of surviving as an invisible sub-frame sliver.
    var shot = renderedPairShot()
    shot.cutList.shotOutSeconds = 5.06
    shot.pictureInsertions = [loopInsertion(id: "pins_sliver8", source: 5...7.9, anchor: 5, rate: 8)]
    let assembly = assemblyOf(shot)
    #expect(!assembly.playbackItems.contains { $0.insertionId == "pins_sliver8" })
    #expect(assembly.insertionCells.first?.state == .trimmedOut)
    #expect(approx(assembly.outputSeconds, 5.06))
}

@Test func deadAnchorCopiesGateDeterministicallyAtTheStripEnd() {
    // The last-resort gate position is the PLAN's material end — stable, so
    // one copy's verdict can never depend on another copy having spliced
    // first. Two dead-anchor copies, judged identically.
    var early = loopInsertion(id: "pins_dead_early", source: 1...2)
    early.anchorSegmentKey = "f9>f10"
    var late = loopInsertion(id: "pins_dead_late", source: 5...7.9)
    late.anchorSegmentKey = "f9>f10"
    var shot = renderedPairShot()
    shot.cutList.shotOutSeconds = 6
    shot.pictureInsertions = [early, late]
    let assembly = assemblyOf(shot)
    #expect(!assembly.playbackItems.contains { $0.isInsertion })
    #expect(assembly.insertionCells.map(\.state) == [.trimmedOut, .trimmedOut])
    #expect(approx(assembly.outputSeconds, 6))
}
