import Foundation
import Testing
@testable import LitScenes

// MARK: Fixtures

private func takeFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(imageId: id, label: "Frame \(id)", imagePath: "/tmp/\(id).png",
        prompt: "A quiet harbor scene \(id)", status: "ready")
}

private let takeFrameLookup: [String: ProjectLensHeroImage] = [
    "f1": takeFrame("f1"), "f2": takeFrame("f2"), "f3": takeFrame("f3")
]

private func takeShot(_ entries: [ShotFrameEntry] = [
    ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
    ShotFrameEntry(entryId: "e2", frameImageId: "f2")
]) -> ProjectShot {
    ProjectShot(shotId: "shot_takes", name: "Takes", entries: entries, createdAt: "t0", updatedAt: "t0")
}

private func takeClip(
    start: String = "e1", end: String = "e2",
    startFrame: String = "f1", endFrame: String = "f2",
    request: String, path: String, prompt: String = "She runs"
) -> ShotRenderSegmentClip {
    ShotRenderSegmentClip(
        startFrameImageId: startFrame, endFrameImageId: endFrame,
        placementStartEntryId: start, placementEndEntryId: end,
        clipPath: path, requestId: request, prompt: prompt,
        provider: "fal", model: "minimax/h3-max/image-to-video",
        durationSeconds: 5, updatedAt: "t1"
    )
}

private func takeVersion(_ number: Int, clips: [ShotRenderSegmentClip], status: String = "ready",
                         renderedEntryIds: [String] = []) -> ShotRenderArtifact {
    ShotRenderArtifact(
        versionId: "v\(number)", versionNumber: number, provider: "fal", model: "minimax/h3-max/image-to-video",
        status: status, videoPath: status == "ready" ? "/tmp/v\(number).mp4" : "",
        clipPaths: clips.map(\.clipPath), segmentCount: clips.count, totalSeconds: clips.count * 5,
        segmentClips: clips, renderedEntryIds: renderedEntryIds,
        generatedAt: "t\(number)", updatedAt: "t\(number)"
    )
}

private func takePlanOf(_ shot: ProjectShot) -> [ShotRenderPlanSegment] {
    shotRenderSegmentPlan(shot: shot, frameLookup: takeFrameLookup, mediaLookup: [:], meaningNodes: []).segments
}

private func firstPair(_ shot: ProjectShot) -> ShotRenderPair? {
    for case .generated(let item) in takePlanOf(shot) { return item.pair }
    return nil
}

/// Two takes of one placement: v1 rendered A1, v2 rendered A2 (active).
private func twoTakeShot() -> ProjectShot {
    var shot = takeShot()
    shot = shot.upsertingRenderVersion(takeVersion(1, clips: [takeClip(request: "r1", path: "/tmp/a1.mp4", prompt: "toward camera")]),
        activate: true, now: "t1")
    shot = shot.upsertingRenderVersion(takeVersion(2, clips: [takeClip(request: "r2", path: "/tmp/a2.mp4", prompt: "back straight")]),
        activate: true, now: "t2")
    return shot
}

private func always(_ path: String) -> Bool { true }

// MARK: Take universe

@Test func segmentTakesDedupeByClipPathInFirstAppearanceOrder() throws {
    var shot = takeShot()
    let a1 = takeClip(request: "r1", path: "/tmp/a1.mp4")
    shot = shot.upsertingRenderVersion(takeVersion(1, clips: [a1]), activate: true, now: "t1")
    // v2 reused A1 verbatim (a partial render elsewhere), v3 rendered A3.
    shot = shot.upsertingRenderVersion(takeVersion(2, clips: [a1]), activate: true, now: "t2")
    shot = shot.upsertingRenderVersion(takeVersion(3, clips: [takeClip(request: "r3", path: "/tmp/a3.mp4")]), activate: true, now: "t3")
    let pair = try #require(firstPair(shot))
    let takes = shotSegmentTakes(shot: shot, pair: pair, fileExists: always)
    try #require(takes.count == 2)
    #expect(takes[0].takeNumber == 1)
    #expect(takes[0].clip.clipPath == "/tmp/a1.mp4")
    #expect(takes[0].originVersionId == "v1")
    #expect(takes[0].originVersionNumber == 1)
    #expect(takes[0].carriedByVersionIds == ["v1", "v2"])
    #expect(!takes[0].isSeed)
    #expect(takes[1].takeNumber == 2)
    #expect(takes[1].clip.clipPath == "/tmp/a3.mp4")
    #expect(takes[1].originVersionId == "v3")
    #expect(takes[1].carriedByVersionIds == ["v3"])
    let allOnDisk = takes.allSatisfy { $0.fileExists }
    #expect(allOnDisk)
    // File availability is reported, never used to hide a take.
    let missing = shotSegmentTakes(shot: shot, pair: pair, fileExists: { $0 != "/tmp/a1.mp4" })
    #expect(missing.count == 2)
    #expect(missing[0].fileExists == false)
}

@Test func segmentTakesPutSeedsFirstAndIgnoreOtherPlacements() throws {
    var shot = takeShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2"),
        ShotFrameEntry(entryId: "e3", frameImageId: "f3")
    ])
    shot.seedSegmentClips = [takeClip(request: "seed", path: "/tmp/seed.mp4")]
    shot = shot.upsertingRenderVersion(takeVersion(1, clips: [
        takeClip(request: "r1", path: "/tmp/a1.mp4"),
        takeClip(start: "e2", end: "e3", startFrame: "f2", endFrame: "f3", request: "q1", path: "/tmp/b1.mp4")
    ]), activate: true, now: "t1")
    let takes = shotSegmentTakes(shot: shot, startEntryId: "e1", endEntryId: "e2", startFrameId: "f1", endFrameId: "f2", fileExists: always)
    try #require(takes.count == 2)
    #expect(takes[0].isSeed && takes[0].takeNumber == 1 && takes[0].originVersionNumber == 0)
    #expect(takes[1].clip.clipPath == "/tmp/a1.mp4" && takes[1].takeNumber == 2)
    #expect(!takes.contains { $0.clip.clipPath == "/tmp/b1.mp4" })
}

@Test func segmentTakesAreEmptyForContinuationPlacements() {
    var shot = twoTakeShot()
    shot.continuationRecords = [ShotContinuationRecord(entryId: "e2", sourceEntryId: "e1")]
    #expect(shotSegmentTakes(shot: shot, startEntryId: "e1", endEntryId: "e2", startFrameId: "f1", endFrameId: "f2", fileExists: always).isEmpty)
}

// MARK: Selection model

@Test func segmentTakeSelectionsDecodeTolerantlyAndRoundTrip() throws {
    // A document written before selections existed decodes to none.
    let legacy = """
    {"shotId":"shot_old","entries":[{"entryId":"e1","frameImageId":"f1"}]}
    """
    let old = try JSONDecoder().decode(ProjectShot.self, from: Data(legacy.utf8))
    #expect(old.segmentTakeSelections.isEmpty)

    // A sparse selection fills its blanks.
    let sparse = try JSONDecoder().decode(ShotSegmentTakeSelection.self,
        from: Data(#"{"placementKey":"entry:e1>e2","clipPath":"/tmp/a1.mp4"}"#.utf8))
    #expect(sparse.placementKey == "entry:e1>e2" && sparse.versionId.isEmpty && sparse.selectedAt.isEmpty)

    var shot = twoTakeShot()
    shot = shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3")
    let decoded = try JSONDecoder().decode(ProjectShot.self, from: JSONEncoder().encode(shot))
    #expect(decoded.segmentTakeSelections == shot.segmentTakeSelections)
    #expect(decoded.segmentTakeSelections.first?.versionId == "v1")
    #expect(decoded.segmentTakeSelections.first?.requestId == "r1")
    #expect(decoded.segmentTakeSelections.first?.selectedAt == "t3")
}

@Test func selectingSegmentTakeRefusesUnknownPathsAndContinuationPlacements() {
    let shot = twoTakeShot()
    #expect(shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/never_rendered.mp4", now: "t3") == shot)
    #expect(shot.selectingSegmentTake(placementKey: "", clipPath: "/tmp/a1.mp4", now: "t3") == shot)
    // A clip from another placement never satisfies this one.
    #expect(shot.selectingSegmentTake(placementKey: "entry:e9>e8", clipPath: "/tmp/a1.mp4", now: "t3") == shot)
    var owned = shot
    owned.continuationRecords = [ShotContinuationRecord(entryId: "e2", sourceEntryId: "e1")]
    #expect(owned.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3") == owned)

    // Re-picking dedupes and keeps provenance honest.
    let picked = shot
        .selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3")
        .selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a2.mp4", now: "t4")
    #expect(picked.segmentTakeSelections.count == 1)
    #expect(picked.segmentTakeSelections[0].clipPath == "/tmp/a2.mp4")
    #expect(picked.segmentTakeSelections[0].versionId == "v2")
    #expect(picked.updatedAt == "t4")
    #expect(picked.clearingSegmentTakeSelection(placementKey: "entry:e1>e2", now: "t5").segmentTakeSelections.isEmpty)
}

@Test func normalizedPrunesDanglingSegmentTakeSelections() {
    var shot = twoTakeShot()
    shot.continuationRecords = [ShotContinuationRecord(entryId: "e7", sourceEntryId: "e2")]
    shot.entries.append(ShotFrameEntry(entryId: "e7", isAIExtension: true))
    shot.segmentTakeSelections = [
        ShotSegmentTakeSelection(placementKey: "entry:e1>e2", clipPath: "/tmp/gone.mp4"),      // unretained path
        ShotSegmentTakeSelection(placementKey: "entry:e2>e7", clipPath: "/tmp/a1.mp4"),        // continuation-owned
        ShotSegmentTakeSelection(placementKey: "entry:e9>e2", clipPath: "/tmp/a1.mp4"),        // names a removed entry
        ShotSegmentTakeSelection(placementKey: "entry:e1>e2", clipPath: "/tmp/a2.mp4"),        // superseded below
        ShotSegmentTakeSelection(placementKey: " entry:e1>e2 ", clipPath: " /tmp/a1.mp4 ")     // kept, trimmed, last wins
    ]
    let normalized = shot.normalized()
    #expect(normalized.segmentTakeSelections == [
        ShotSegmentTakeSelection(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4")
    ])
    // Legacy frame-keyed selections have no entries to check and survive.
    shot.segmentTakeSelections = [ShotSegmentTakeSelection(placementKey: "f1>f2", clipPath: "/tmp/a1.mp4")]
    #expect(shot.normalized().segmentTakeSelections.count == 1)
}

// MARK: The selection law at every resolver

@Test func savedSegmentClipPrefersSelectionOverPlayableAndContinuationOverSelection() {
    var shot = twoTakeShot()
    #expect(shotSavedSegmentClip(shot: shot, startEntryId: "e1", endEntryId: "e2", startFrameId: "f1", endFrameId: "f2")?.clipPath == "/tmp/a2.mp4")
    shot = shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3")
    #expect(shotSavedSegmentClip(shot: shot, startEntryId: "e1", endEntryId: "e2", startFrameId: "f1", endFrameId: "f2")?.clipPath == "/tmp/a1.mp4")
    #expect(previewableSegmentClip(shot: shot, pair: firstPair(shot)!, fileExists: always)?.clipPath == "/tmp/a1.mp4")
    // A continuation record's selected take still outranks a pair selection.
    let take = ShotContinuationTake(takeId: "c1", takeNumber: 1, status: ShotContinuationTakeStatus.ready.rawValue,
        segmentClip: takeClip(request: "rc", path: "/tmp/cont.mp4"))
    shot.continuationRecords = [ShotContinuationRecord(entryId: "e2", sourceEntryId: "e1", selectedTakeId: "c1", takes: [take])]
    #expect(shotSavedSegmentClip(shot: shot, startEntryId: "e1", endEntryId: "e2", startFrameId: "f1", endFrameId: "f2")?.clipPath == "/tmp/cont.mp4")
}

@Test func pictureSourceCatalogActivePathHonorsSelectedTake() {
    var shot = twoTakeShot()
    #expect(shotActiveTakePathsBySegmentKey(shot: shot)["entry:e1>e2"] == "/tmp/a2.mp4")
    shot = shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3")
    let catalog = ShotPictureSourceCatalog(shot: shot)
    #expect(catalog.activePaths["entry:e1>e2"] == "/tmp/a1.mp4")
    // Retention is the wider set — both takes stay pinnable.
    #expect(catalog.retains(key: "entry:e1>e2", path: "/tmp/a2.mp4", scope: nil))
    #expect(catalog.retains(key: "entry:e1>e2", path: "/tmp/a1.mp4", scope: nil))
}

@Test func cutAssemblyBandPlaysSelectedTakeAndReactivatesItsPinnedRazors() throws {
    var shot = twoTakeShot()
    shot.cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(segmentKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", startSeconds: 1, endSeconds: 2),
        ShotSegmentCutRange(segmentKey: "entry:e1>e2", clipPath: "/tmp/a2.mp4", startSeconds: 3, endSeconds: 4)
    ])
    let plan = takePlanOf(shot)
    let durations = ["/tmp/a1.mp4": 5.0, "/tmp/a2.mp4": 5.0]
    let before = shotCutAssembly(shot: shot, planSegments: plan, clipDurationsByPath: durations, fileExists: always)
    try #require(before.bands.count == 1)
    #expect(before.bands[0].clipPath == "/tmp/a2.mp4")
    #expect(before.planClips[0].keepRanges == [ShotKeepRange(start: 0, end: 3), ShotKeepRange(start: 4, end: 5)])

    shot = shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3")
    let after = shotCutAssembly(shot: shot, planSegments: plan, clipDurationsByPath: durations, fileExists: always)
    try #require(after.bands.count == 1)
    #expect(after.bands[0].clipPath == "/tmp/a1.mp4")
    #expect(after.planClips[0].keepRanges == [ShotKeepRange(start: 0, end: 1), ShotKeepRange(start: 2, end: 5)])
    // Retention, not selection, sweeps razors: both pins stay.
    #expect(shotStalePinnedCutIds(shot: shot).isEmpty)
}

@Test func activatingReadyVersionClearsOnlyFreshPlacementSelections() {
    var shot = takeShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2"),
        ShotFrameEntry(entryId: "e3", frameImageId: "f3")
    ])
    let a1 = takeClip(request: "r1", path: "/tmp/a1.mp4")
    let b1 = takeClip(start: "e2", end: "e3", startFrame: "f2", endFrame: "f3", request: "q1", path: "/tmp/b1.mp4")
    let a2 = takeClip(request: "r2", path: "/tmp/a2.mp4")
    let b2 = takeClip(start: "e2", end: "e3", startFrame: "f2", endFrame: "f3", request: "q2", path: "/tmp/b2.mp4")
    shot = shot.upsertingRenderVersion(takeVersion(1, clips: [a1, b1]), activate: true, now: "t1")
    shot = shot.upsertingRenderVersion(takeVersion(2, clips: [a2, b2]), activate: true, now: "t2")
    shot = shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3")
    shot = shot.selectingSegmentTake(placementKey: "entry:e2>e3", clipPath: "/tmp/b1.mp4", now: "t3")

    // A render still in flight (v3 generating) never clears — playback is
    // substituting the last ready version until it lands.
    let a3 = takeClip(request: "r3", path: "/tmp/a3.mp4")
    let generating = shot.upsertingRenderVersion(takeVersion(3, clips: [a3, b1], status: "generating"), activate: true, now: "t4")
    #expect(generating.segmentTakeSelections.count == 2)
    // Landing ready: A3 is fresh (its file is in no earlier version) so the
    // A pick clears; B1 traveled in verbatim so the B pick survives.
    let landed = generating.upsertingRenderVersion(takeVersion(3, clips: [a3, b1]), activate: true, now: "t5")
    #expect(landed.segmentTakeSelections.map(\.placementKey) == ["entry:e2>e3"])
    #expect(shotSavedSegmentClip(shot: landed, startEntryId: "e1", endEntryId: "e2", startFrameId: "f1", endFrameId: "f2")?.clipPath == "/tmp/a3.mp4")
    #expect(shotSavedSegmentClip(shot: landed, startEntryId: "e2", endEntryId: "e3", startFrameId: "f2", endFrameId: "f3")?.clipPath == "/tmp/b1.mp4")
    // A version recorded without activation changes nothing.
    let recorded = shot.upsertingRenderVersion(takeVersion(4, clips: [takeClip(request: "r4", path: "/tmp/a4.mp4")]), activate: false, now: "t6")
    #expect(recorded.segmentTakeSelections.count == 2)
    // Idempotent under the repeated same-id upserts a render performs.
    #expect(landed.upsertingRenderVersion(takeVersion(3, clips: [a3, b1]), activate: true, now: "t7").segmentTakeSelections == landed.segmentTakeSelections)
}

@Test func renderReuseSourceCarriesSelectedPairTake() {
    var shot = takeShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2"),
        ShotFrameEntry(entryId: "e3", frameImageId: "f3")
    ])
    let b2 = takeClip(start: "e2", end: "e3", startFrame: "f2", endFrame: "f3", request: "q2", path: "/tmp/b2.mp4")
    shot = shot.upsertingRenderVersion(takeVersion(1, clips: [takeClip(request: "r1", path: "/tmp/a1.mp4")]), activate: true, now: "t1")
    shot = shot.upsertingRenderVersion(takeVersion(2, clips: [takeClip(request: "r2", path: "/tmp/a2.mp4"), b2]), activate: true, now: "t2")
    shot = shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3")
    let source = shotRenderReuseSource(shot: shot, fileExists: always)
    #expect(source.segmentClip(placementStartEntryId: "e1", placementEndEntryId: "e2", forStart: "f1", end: "f2")?.clipPath == "/tmp/a1.mp4")
    #expect(source.segmentClip(placementStartEntryId: "e2", placementEndEntryId: "e3", forStart: "f2", end: "f3")?.clipPath == "/tmp/b2.mp4")
    // A missing file falls back to the active version's clip — never re-bought, never faked.
    let degraded = shotRenderReuseSource(shot: shot, fileExists: { $0 != "/tmp/a1.mp4" })
    #expect(degraded.segmentClip(placementStartEntryId: "e1", placementEndEntryId: "e2", forStart: "f1", end: "f2")?.clipPath == "/tmp/a2.mp4")
    // The decision layer reuses exactly what plays when the filter excludes it.
    let plan = shotRenderSegmentPlan(shot: shot, frameLookup: takeFrameLookup, mediaLookup: [:], meaningNodes: [])
    let decisions = shotSegmentRenderDecisions(items: plan.generatedItems, onlySegmentKeys: ["entry:e2>e3"],
        reuseSource: source, fileExists: always)
    #expect(decisions.first == .reuse(source.segmentClip(placementStartEntryId: "e1", placementEndEntryId: "e2", forStart: "f1", end: "f2")!))
    #expect(decisions.last == .generate)
}

@Test func outputFingerprintChangesForNewTakeAndIsStableForEffectiveTake() {
    let shot = twoTakeShot()
    let base = shotOutputFingerprint(shot)
    #expect(shotOutputFingerprint(shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a2.mp4", now: "t3")) == base)
    #expect(shotOutputFingerprint(shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3")) != base)
    // A projection that no longer holds the entries a selection names ignores it.
    var picked = shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3")
    picked.entries.append(ShotFrameEntry(entryId: "e3", frameImageId: "f3"))
    var unpicked = shot
    unpicked.entries.append(ShotFrameEntry(entryId: "e3", frameImageId: "f3"))
    #expect(shotOutputFingerprint(shotOutputPrefix(picked, before: "e2")) == shotOutputFingerprint(shotOutputPrefix(unpicked, before: "e2")))
}

@Test func scopeProjectionFingerprintFollowsSelectionInsideTheScope() {
    var shot = takeShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2"),
        ShotFrameEntry(entryId: "e3", frameImageId: "f3")
    ])
    let b1 = takeClip(start: "e2", end: "e3", startFrame: "f2", endFrame: "f3", request: "q1", path: "/tmp/b1.mp4")
    let b2 = takeClip(start: "e2", end: "e3", startFrame: "f2", endFrame: "f3", request: "q2", path: "/tmp/b2.mp4")
    shot = shot.upsertingRenderVersion(takeVersion(1, clips: [takeClip(request: "r1", path: "/tmp/a1.mp4"), b1]), activate: true, now: "t1")
    shot = shot.upsertingRenderVersion(takeVersion(2, clips: [takeClip(request: "r2", path: "/tmp/a2.mp4"), b2]), activate: true, now: "t2")
    var prefix = shot
    prefix.entries = Array(shot.entries.prefix(2))
    let scope = ShotOutputScope(shot: prefix, segmentKeys: ["entry:e1>e2"], scopeId: "scope_test")
    let base = shotOutputFingerprint(scope.project(from: shot))
    let inside = shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3")
    #expect(shotOutputFingerprint(scope.project(from: inside)) != base)
    let outside = shot.selectingSegmentTake(placementKey: "entry:e2>e3", clipPath: "/tmp/b1.mp4", now: "t3")
    #expect(shotOutputFingerprint(scope.project(from: outside)) == base)
}

@Test func segmentTakeStaleEntryIdsFlagDependentContinuation() {
    var shot = takeShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2"),
        ShotFrameEntry(entryId: "e3", isAIExtension: true)
    ])
    shot = shot.upsertingRenderVersion(takeVersion(1, clips: [takeClip(request: "r1", path: "/tmp/a1.mp4")], renderedEntryIds: ["e1", "e2"]), activate: true, now: "t1")
    shot = shot.upsertingRenderVersion(takeVersion(2, clips: [takeClip(request: "r2", path: "/tmp/a2.mp4")], renderedEntryIds: ["e1", "e2"]), activate: true, now: "t2")
    // The continuation grew from the rendered tail that plays today (A2).
    let take = ShotContinuationTake(takeId: "c1", takeNumber: 1, status: ShotContinuationTakeStatus.ready.rawValue,
        anchor: ShotContinuationAnchor(sourceKind: "rendered_original", sourceEntryId: "e2",
            sourceRenderVersionId: "v2", sourceSegmentPlacementKey: "entry:e1>e2",
            tailClipPath: "/tmp/a2.mp4", tailClipEndSeconds: 5).normalized(),
        segmentClip: takeClip(start: "e2", end: "e3", startFrame: "f2", endFrame: "", request: "rc", path: "/tmp/cont.mp4"))
    shot.continuationRecords = [ShotContinuationRecord(entryId: "e3", sourceEntryId: "e2", selectedTakeId: "c1", takes: [take])]
    #expect(shotContinuationStaleEntryIds(shot).isEmpty)
    #expect(shotSegmentTakeStaleEntryIds(shot: shot, placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4") == ["e3"])
    #expect(shotSegmentTakeStaleEntryIds(shot: shot, placementKey: "entry:e1>e2", clipPath: "/tmp/a2.mp4").isEmpty)
}

@Test func renderedTailClipUsesSelectedTakeForTailPlacement() {
    var shot = takeShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2"),
        ShotFrameEntry(entryId: "e3", frameImageId: "f3")
    ])
    shot = shot.upsertingRenderVersion(takeVersion(1, clips: [takeClip(request: "r1", path: "/tmp/a1.mp4")], renderedEntryIds: ["e1", "e2"]), activate: true, now: "t1")
    shot = shot.upsertingRenderVersion(takeVersion(2, clips: [takeClip(request: "r2", path: "/tmp/a2.mp4")], renderedEntryIds: ["e1", "e2"]), activate: true, now: "t2")
    let base = shot.playableRenderVersion!.segmentClips[0]
    #expect(shotResolvedTailClip(shot: shot, base: base, versionId: "v2", fileExists: always).clip.clipPath == "/tmp/a2.mp4")
    let picked = shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3")
    let resolved = shotResolvedTailClip(shot: picked, base: base, versionId: "v2", fileExists: always)
    #expect(resolved.clip.clipPath == "/tmp/a1.mp4")
    #expect(resolved.versionId == "v1")
    // A missing selected file keeps the rendered tail honest.
    #expect(shotResolvedTailClip(shot: picked, base: base, versionId: "v2", fileExists: { $0 != "/tmp/a1.mp4" }).clip.clipPath == "/tmp/a2.mp4")
    // The ending anchor for the appended Frame grows from the selected take.
    let anchor = shotEndingSourceAnchor(shot: picked, entryId: "e3", fileExists: always)
    #expect(anchor?.tailClipPath == "/tmp/a1.mp4")
    #expect(anchor?.sourceRenderVersionId == "v1")
    #expect(shotEndingSourceAnchor(shot: shot, entryId: "e3", fileExists: always)?.tailClipPath == "/tmp/a2.mp4")
}

@Test func pictureSnapshotRestoresSegmentTakeSelections() {
    let shot = twoTakeShot()
    let before = shot.pictureStateSnapshot()
    let picked = shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3")
    let after = picked.pictureStateSnapshot()
    #expect(before != after)
    #expect(after.segmentTakeSelections?.first?.clipPath == "/tmp/a1.mp4")
    let restored = picked.restoringPictureState(before, now: "t4")
    #expect(restored.segmentTakeSelections.isEmpty)
    #expect(restored.pictureStateSnapshot() == before)
    #expect(restored.restoringPictureState(after, now: "t5").segmentTakeSelections == picked.segmentTakeSelections)
    // A snapshot that never carried selections leaves them alone.
    var bare = after
    bare.segmentTakeSelections = nil
    #expect(picked.restoringPictureState(bare, now: "t6").segmentTakeSelections == picked.segmentTakeSelections)
}

// MARK: Segment editor rows

@Test func unrepresentedWorkTilesExcludePlannedPlacements() {
    let shot = twoTakeShot()
    let plan = takePlanOf(shot)
    let planned = ShotRowVideoTile(
        result: ShotSegmentPresentation(id: "entry:e1>e2", title: "Generated")
            .withProgress(WorkflowSegmentProgress(placementKey: "entry:e1>e2"), shot: shot),
        ordinal: 1, count: 1)
    let stray = ShotRowVideoTile(
        result: ShotSegmentPresentation(id: "entry:e9>", title: "Generated")
            .withProgress(WorkflowSegmentProgress(placementKey: "entry:e9>"), shot: shot),
        ordinal: 2, count: 2)
    let idle = ShotRowVideoTile(result: ShotSegmentPresentation(id: "entry:e8>", title: "Generated"), ordinal: 3, count: 3)
    let tiles = shotUnrepresentedWorkTiles([planned, stray, idle], planSegments: plan, unplannedRecords: [])
    #expect(tiles.map(\.id) == ["entry:e9>"])
}
