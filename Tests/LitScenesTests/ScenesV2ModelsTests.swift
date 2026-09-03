import Foundation
import Testing
@testable import LitScenes

// MARK: Fixtures

private func v2Frame(
    _ id: String,
    status: String = "ready",
    path: String? = nil,
    generatedAt: String = "2026-08-01T00:00:00Z",
    imageIndex: Int = 0
) -> ProjectLensHeroImage {
    var frame = ProjectLensHeroImage(
        imageId: id,
        imageIndex: imageIndex,
        label: "Frame \(id)",
        imagePath: path ?? "/tmp/\(id).png",
        status: status
    )
    frame.generatedAt = generatedAt
    return frame
}

private func v2Photo(_ id: String, modifiedAt: String) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: id,
        sourceId: "source_test",
        kind: .image,
        filename: "\(id).jpg",
        path: "/tmp/\(id).jpg",
        relativePath: "\(id).jpg",
        byteCount: 1,
        modifiedAt: modifiedAt,
        width: 1920,
        height: 1080,
        durationSeconds: nil,
        nominalFrameRate: nil,
        thumbnailPath: "",
        videoStripPath: nil,
        scannedAt: modifiedAt,
        scanError: nil
    )
}

private func v2Video(_ id: String, modifiedAt: String = "2026-08-01T00:00:00Z") -> MediaItemRecord {
    MediaItemRecord(
        mediaId: id,
        sourceId: "source_test",
        kind: .video,
        filename: "\(id).mp4",
        path: "/tmp/\(id).mp4",
        relativePath: "\(id).mp4",
        byteCount: 1,
        modifiedAt: modifiedAt,
        width: 1920,
        height: 1080,
        durationSeconds: 8,
        nominalFrameRate: 24,
        thumbnailPath: "/tmp/\(id)_thumb.jpg",
        videoStripPath: nil,
        scannedAt: modifiedAt,
        scanError: nil
    )
}

private func v2FrameEntry(_ entryId: String, _ frameImageId: String, skipped: Bool = false) -> ShotFrameEntry {
    var entry = ShotFrameEntry(entryId: entryId, frameImageId: frameImageId)
    entry.isSkipped = skipped
    return entry
}

private func v2ClipEntry(_ entryId: String, _ mediaId: String) -> ShotFrameEntry {
    ShotFrameEntry(entryId: entryId, clipMediaId: mediaId)
}

private func v2Shot(_ shotId: String, name: String = "", entries: [ShotFrameEntry] = []) -> ProjectShot {
    ProjectShot(shotId: shotId, name: name, entries: entries)
}

private func v2Artifact(_ versionId: String, number: Int, status: String, videoPath: String = "") -> ShotRenderArtifact {
    var artifact = ShotRenderArtifact()
    artifact.versionId = versionId
    artifact.versionNumber = number
    artifact.status = status
    artifact.videoPath = videoPath
    return artifact
}

// MARK: - Display name

@Test func sceneDisplayNameFallsBackToOneBasedIndex() {
    #expect(sceneDisplayName(shot: v2Shot("s1"), index: 0) == "Scene 1")
    #expect(sceneDisplayName(shot: v2Shot("s1", name: "   "), index: 4) == "Scene 5")
    #expect(sceneDisplayName(shot: v2Shot("s1", name: " Harbor Dawn "), index: 0) == "Harbor Dawn")
}

// MARK: - Usage

@Test func usedFrameIdsCountSkippedEntriesAndExcludeClips() {
    let shots = [
        v2Shot("s1", entries: [
            v2FrameEntry("e1", "f1"),
            v2FrameEntry("e2", "f2", skipped: true),
            v2ClipEntry("e3", "m1"),
            v2FrameEntry("e4", "f1")
        ]),
        v2Shot("s2", entries: [v2FrameEntry("e5", "f3")])
    ]
    #expect(usedFrameImageIds(in: shots) == ["f1", "f2", "f3"])
    #expect(usedClipMediaIds(in: shots) == ["m1"])
}

// MARK: - Boundary frames vs shotRenderPairs

private func pairsBoundary(_ shot: ProjectShot, frameLookup: [String: ProjectLensHeroImage]) -> Set<String> {
    let (pairs, _) = shotRenderPairs(shot: shot, frameLookup: frameLookup)
    var boundary: Set<String> = []
    if let firstStart = pairs.first?.start?.imageId {
        boundary.insert(firstStart)
    }
    if let last = pairs.last, let lastOuter = (last.end ?? last.start)?.imageId {
        boundary.insert(lastOuter)
    }
    return boundary
}

@Test func boundaryFrameIdsMatchShotRenderPairsBoundary() {
    let lookup: [String: ProjectLensHeroImage] = [
        "f1": v2Frame("f1"),
        "f2": v2Frame("f2"),
        "f3": v2Frame("f3"),
        "fPending": v2Frame("fPending", status: "generating"),
        "fEmpty": v2Frame("fEmpty", path: " ")
    ]
    let readyIds = Set(lookup.values.filter { $0.status == "ready" && !$0.imagePath.trimmed.isEmpty }.map(\.imageId))
    let fixtures: [ProjectShot] = [
        // All ready.
        v2Shot("all", entries: [v2FrameEntry("e1", "f1"), v2FrameEntry("e2", "f2"), v2FrameEntry("e3", "f3")]),
        // Not-ready frames at the edges.
        v2Shot("gaps", entries: [v2FrameEntry("e1", "fPending"), v2FrameEntry("e2", "f2"), v2FrameEntry("e3", "fEmpty")]),
        // Skipped boundary entries step inward.
        v2Shot("skips", entries: [v2FrameEntry("e1", "f1", skipped: true), v2FrameEntry("e2", "f2"), v2FrameEntry("e3", "f3")]),
        // Clips interleaved never join the ready sequence.
        v2Shot("clips", entries: [v2ClipEntry("e1", "m1"), v2FrameEntry("e2", "f2"), v2ClipEntry("e3", "m2")]),
        // Single ready frame is both boundaries.
        v2Shot("lone", entries: [v2FrameEntry("e1", "f3")]),
        // Zero ready frames.
        v2Shot("none", entries: [v2FrameEntry("e1", "fPending"), v2ClipEntry("e2", "m1")])
    ]
    for shot in fixtures {
        let derived = boundaryFrameImageIds(shots: [shot], readyFrameImageIds: readyIds)
        let expected = pairsBoundary(shot, frameLookup: lookup)
        #expect(derived == expected, "shot \(shot.shotId)")
    }
    // Union across shots.
    let all = boundaryFrameImageIds(shots: fixtures, readyFrameImageIds: readyIds)
    let expectedUnion = fixtures.reduce(into: Set<String>()) { union, shot in
        union.formUnion(pairsBoundary(shot, frameLookup: lookup))
    }
    #expect(all == expectedUnion)
}

// MARK: - Badges

@Test func documentBadgePrecedence() {
    var shot = v2Shot("s1")
    #expect(sceneRenderBadgeFromDocument(shot: shot) == .draft)

    shot.renderVersions = [v2Artifact("v1", number: 1, status: "ready", videoPath: "/tmp/v1.mp4")]
    shot.activeRenderVersionId = "v1"
    #expect(sceneRenderBadgeFromDocument(shot: shot) == .ready)

    shot.renderVersions.append(v2Artifact("v2", number: 2, status: "failed"))
    shot.activeRenderVersionId = "v2"
    #expect(sceneRenderBadgeFromDocument(shot: shot) == .failed)

    // A persisted "generating" in an unloaded project is PARKED, and outranks
    // failed/ready — nothing is running, and the next load will reconcile it.
    shot.renderVersions.append(v2Artifact("v3", number: 3, status: "generating"))
    #expect(sceneRenderBadgeFromDocument(shot: shot) == .parked)
}

@Test func liveBadgeNeverShowsRenderingForSomethingNotRunning() {
    var shot = v2Shot("s1")
    shot.renderVersions = [v2Artifact("v1", number: 1, status: "generating")]
    shot.activeRenderVersionId = "v1"

    #expect(sceneRenderBadgeLive(shot: shot, activeShotRenderId: "s1") == .rendering)
    // Generating on disk with no live render id is a straggler → FAILED.
    #expect(sceneRenderBadgeLive(shot: shot, activeShotRenderId: "") == .failed)
    #expect(sceneRenderBadgeLive(shot: shot, activeShotRenderId: "other") == .failed)

    var ready = v2Shot("s2")
    ready.renderVersions = [v2Artifact("v1", number: 1, status: "ready", videoPath: "/tmp/v1.mp4")]
    ready.activeRenderVersionId = "v1"
    #expect(sceneRenderBadgeLive(shot: ready, activeShotRenderId: "") == .ready)
    #expect(sceneRenderBadgeLive(shot: v2Shot("s3"), activeShotRenderId: "") == .draft)
}

// MARK: - Poster candidates

@Test func posterCandidatesFollowCutPosterPrecedenceWithFallThrough() {
    let entries = [
        v2FrameEntry("e1", "fPending"),      // no ready still, not a clip → contributes nothing
        v2ClipEntry("e2", "m1"),             // footage thumb
        v2FrameEntry("e3", "f1"),            // ready still
        v2ClipEntry("e4", "mNoThumb")        // no thumb → nothing
    ]
    let paths = scenePosterCandidatePaths(
        entries: entries,
        frameStillPathById: ["f1": "/tmp/f1.png"],
        footageThumbnailPathByMediaId: ["m1": "/tmp/m1_thumb.jpg", "mNoThumb": " "]
    )
    #expect(paths == ["/tmp/m1_thumb.jpg", "/tmp/f1.png"])
}

// MARK: - Pool inventory law

@Test func projectPoolInputsKeepDeterministicOrderAndScopeAdoptionToDisplayedFrames() {
    var adoptedFrame = v2Frame("fAdopted", generatedAt: "2026-08-02T00:00:00Z")
    adoptedFrame.sourceDependencies = [
        LensRenderSourceDependency(dependencyId: "d1", kind: "externalImport", sourceId: "pAdopted", role: "source_photo")
    ]
    let displayed = [adoptedFrame, v2Frame("fShown", generatedAt: "2026-08-01T00:00:00Z")]
    let projectWide = displayed + [
        v2Frame("fOld", generatedAt: "2026-07-01T00:00:00Z", imageIndex: 2),
        v2Frame("fNew", generatedAt: "2026-07-30T00:00:00Z", imageIndex: 1)
    ]
    let items = [
        v2Photo("pAdopted", modifiedAt: "2026-08-03T00:00:00Z"),
        v2Photo("pElsewhere", modifiedAt: "2026-08-02T00:00:00Z"),
        v2Video("vClip")
    ]
    let inputs = projectPoolInputs(
        displayedFrames: displayed,
        projectWideFrames: projectWide,
        items: items
    )
    // A photo adopted into a DISPLAYED frame hides; any other photo stays,
    // then displayed frames in given order, then other frames newest-first,
    // then footage.
    #expect(inputs.map(\.assetKey) == [
        "clip:pElsewhere",
        "frame:fAdopted",
        "frame:fShown",
        "frame:fNew",
        "frame:fOld",
        "clip:vClip"
    ])
}

// MARK: - Pool filters

@Test func poolFilterPredicates() {
    let usage = ScenesV2PoolUsage(
        usedFrameIds: ["fUsed"],
        usedClipIds: ["mUsed"],
        boundaryFrameIds: ["fBoundary"]
    )
    let usedFrame = StageInput(inputId: "i1", frameImageId: "fUsed")
    let freshFrame = StageInput(inputId: "i2", frameImageId: "fFree")
    let boundaryFrame = StageInput(inputId: "i3", frameImageId: "fBoundary")
    let usedClip = StageInput(inputId: "i4", clipMediaId: "mUsed")
    let freshClip = StageInput(inputId: "i5", clipMediaId: "mFree")

    for input in [usedFrame, freshFrame, boundaryFrame, usedClip, freshClip] {
        #expect(poolInputMatchesFilter(input, filter: .all, usage: usage))
        #expect(!poolInputMatchesFilter(input, filter: .characters, usage: usage))
        #expect(!poolInputMatchesFilter(input, filter: .objects, usage: usage))
    }
    #expect(!poolInputMatchesFilter(usedFrame, filter: .unused, usage: usage))
    #expect(poolInputMatchesFilter(freshFrame, filter: .unused, usage: usage))
    #expect(!poolInputMatchesFilter(usedClip, filter: .unused, usage: usage))
    #expect(poolInputMatchesFilter(freshClip, filter: .unused, usage: usage))
    #expect(poolInputMatchesFilter(boundaryFrame, filter: .startEnd, usage: usage))
    #expect(!poolInputMatchesFilter(freshFrame, filter: .startEnd, usage: usage))
    #expect(!poolInputMatchesFilter(freshClip, filter: .startEnd, usage: usage))
}

// MARK: - Stage selection (Option A)

@Test func selectionKeepsAVisibleSceneAndSweepsAGoneOne() {
    #expect(scenesV2ReconciledSelection("b", against: ["a", "b", "c"]) == "b")
    // A trashed selection reseeds with the first scene that needs work.
    #expect(scenesV2ReconciledSelection("gone", against: ["a", "b"]) == "a")
    #expect(scenesV2ReconciledSelection("", against: ["a", "b"]) == "a")
}

@Test func selectionSeedPrefersUnreadyScenes() {
    #expect(scenesV2ReconciledSelection("", against: ["x", "y", "z"], readySceneIds: ["x", "y"]) == "z")
    // Everything ready: still show SOMETHING rather than an empty stage.
    #expect(scenesV2ReconciledSelection("", against: ["x", "y"], readySceneIds: ["x", "y"]) == "x")
    // A deliberately selected ready scene is respected — the preference only
    // governs seeding, never an explicit click.
    #expect(scenesV2ReconciledSelection("x", against: ["x", "y"], readySceneIds: ["x", "y"]) == "x")
    #expect(scenesV2ReconciledSelection("gone", against: []) == "")
}

// MARK: - Ledger card derivations

@Test func ledgerLineAbbreviatesTheRuntimeSummary() {
    var shot = ProjectShot(shotId: "shot_l", name: "Ledger", entries: [
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ])
    let frames = [
        "f1": ledgerFrame("f1"),
        "f2": ledgerFrame("f2")
    ]
    let line = sceneLedgerLine(shot: shot, frameLookup: frames, mediaLookup: [:])
    #expect(line.hasPrefix("2 FR"))
    #expect(line.contains("~"))

    // An empty shot reads bare, never crashes.
    shot.entries = []
    #expect(sceneLedgerLine(shot: shot, frameLookup: [:], mediaLookup: [:]) == "0 FR")
}

@Test func renderProgressOnlyReportsTheActiveRender() {
    var artifact = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "generating",
        generatedAt: "2026-08-26T00:00:00Z",
        updatedAt: "2026-08-26T00:00:00Z"
    )
    artifact.segmentCount = 4
    artifact.clipPaths = ["/tmp/a.mp4", "/tmp/b.mp4"]
    artifact.progressText = "SEGMENT 3 OF 4"
    var shot = ProjectShot(shotId: "shot_p", name: "Progress", entries: [])
    shot = shot.upsertingRenderVersion(artifact, activate: true, now: "2026-08-26T00:00:00Z")

    // Not the active render: nil, whatever the persisted status says.
    #expect(sceneRenderProgress(shot: shot, activeShotRenderId: "") == nil)
    #expect(sceneRenderProgress(shot: shot, activeShotRenderId: "other") == nil)

    let progress = sceneRenderProgress(shot: shot, activeShotRenderId: "shot_p")
    #expect(progress?.fraction == 0.5)
    #expect(progress?.label == "SEGMENT 3 OF 4")
}

private func ledgerFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        label: "Frame \(id)",
        imagePath: "/tmp/\(id).png",
        prompt: "scene \(id)",
        status: "ready"
    )
}

@Test func durableEmptySelectionSurvivesReconcile() {
    // THE DURABLE EMPTY STAGE: a deliberately empty selection is not reseeded…
    #expect(scenesV2ReconciledSelection("", against: ["a", "b"], seedsWhenEmpty: false) == "")
    // …but a swept NON-empty selection (its scene trashed) reseeds regardless.
    #expect(scenesV2ReconciledSelection("gone", against: ["a", "b"], seedsWhenEmpty: false) == "a")
}

@Test func deletingTheStagedSceneReturnsToTheLastSelectedOne() {
    // The history fallback outranks the seed: deleting the staged scene
    // returns the operator to the most recent STILL-VISIBLE prior selection,
    // never to the top of the rail.
    #expect(scenesV2ReconciledSelection(
        "deleted",
        against: ["a", "b", "c"],
        recentSceneIds: ["b", "a"]
    ) == "b")
    // History entries that are themselves gone (or the deleted scene) skip.
    #expect(scenesV2ReconciledSelection(
        "deleted",
        against: ["a", "c"],
        recentSceneIds: ["deleted", "gone", "c"]
    ) == "c")
    // An empty history falls back to the seed law unchanged.
    #expect(scenesV2ReconciledSelection(
        "deleted",
        against: ["x", "y"],
        readySceneIds: ["x"]
    ) == "y")
    // A visible current selection never consults the history.
    #expect(scenesV2ReconciledSelection(
        "a",
        against: ["a", "b"],
        recentSceneIds: ["b"]
    ) == "a")
    // The durable empty stage still outranks the history.
    #expect(scenesV2ReconciledSelection(
        "",
        against: ["a", "b"],
        seedsWhenEmpty: false,
        recentSceneIds: ["b"]
    ) == "")
}

@Test func legacyMigrationSkipsTheEmptyMruHole() {
    // The two-box blob could persist an MRU pointing at a "" hole (the old
    // conveyor's exhaustion state) — migration must not eat the remembered
    // scene, and an all-empty blob migrates as never-visited.
    #expect(scenesV2MigratedLegacySelection(sceneIds: ["", "b"], mruIndex: 0) == "b")
    #expect(scenesV2MigratedLegacySelection(sceneIds: ["a", "b"], mruIndex: 1) == "b")
    #expect(scenesV2MigratedLegacySelection(sceneIds: ["", ""], mruIndex: 1) == "")
    #expect(scenesV2MigratedLegacySelection(sceneIds: [], mruIndex: 0) == "")
}

@Test func renderProgressIsNilWithoutAnArtifactAndStartsAtZeroWithoutATotal() {
    var shot = ProjectShot(shotId: "shot_b", name: "Bare", entries: [])
    // Active render but no persisted artifact row yet: nothing honest to draw.
    #expect(sceneRenderProgress(shot: shot, activeShotRenderId: "shot_b") == nil)

    var artifact = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "generating",
        generatedAt: "2026-08-26T00:00:00Z",
        updatedAt: "2026-08-26T00:00:00Z"
    )
    artifact.clipPaths = ["/tmp/a.mp4", "/tmp/b.mp4"]
    shot = shot.upsertingRenderVersion(artifact, activate: true, now: "2026-08-26T00:00:00Z")
    // No segment total: report 0 (starting) — never a pinned full bar.
    #expect(sceneRenderProgress(shot: shot, activeShotRenderId: "shot_b")?.fraction == 0)
}

@Test func compactRailLabelSharesTheOneFormatter() {
    var summary = ShotRuntimeSummary()
    summary.frames = 4
    summary.clips = 1
    summary.footageSeconds = 9
    #expect(summary.railLabel(segmentSeconds: 8, compact: true).hasPrefix("4 FR · 1 CL"))
    #expect(summary.railLabel(segmentSeconds: 8).hasPrefix("4 FRAMES · 1 CLIP"))
}

// MARK: - Guided stage

/// A planned frame that has never rendered: empty path, empty generatedAt.
private func v2PlannedFrame(
    _ id: String,
    status: String = "queued",
    imageIndex: Int = 0
) -> ProjectLensHeroImage {
    var frame = ProjectLensHeroImage(
        imageId: id,
        imageIndex: imageIndex,
        label: "Planned \(id)",
        imagePath: "",
        status: status
    )
    frame.generatedAt = ""
    return frame
}

@Test func poolSourceFramesDropDisabledAndPlanCandidatesButKeepLiveWork() {
    var disabled = v2Frame("fDisabled")
    disabled.disabled = true
    let queuedPlan = v2PlannedFrame("fPlan")
    let failedPlan = v2PlannedFrame("fFailedPlan", status: "failed")
    // A generating take is live work, not a plan — it stays with its spinner.
    var generating = v2Frame("fGenerating", status: "generating", path: "")
    generating.generatedAt = ""
    generating.status = "generating"
    // A failed take that DID render once (has a path) is a record, not a plan.
    let failedRender = v2Frame("fFailedRender", status: "failed")
    let ready = v2Frame("fReady")

    let kept = scenesV2PoolSourceFrames([disabled, queuedPlan, failedPlan, generating, failedRender, ready])
    #expect(kept.map(\.imageId) == ["fGenerating", "fFailedRender", "fReady"])
}

@Test func plannedFramesSortInPlanOrder() {
    let frames = [
        v2PlannedFrame("b", imageIndex: 2),
        v2PlannedFrame("z", imageIndex: 1),
        v2PlannedFrame("a", imageIndex: 2),
        v2Frame("ready"),
        v2PlannedFrame("failed", status: "failed", imageIndex: 0)
    ]
    #expect(scenesV2PlannedFramesInPlanOrder(frames).map(\.imageId) == ["failed", "z", "a", "b"])
}

@Test func spotlightStatePrecedence() {
    // Planning outranks everything.
    #expect(scenesV2StageSpotlightState(
        hasLens: false, isGoalReady: true, isPlanningActive: true, planFailed: false,
        plannedImageIdsInPlanOrder: [], renderedFrameCount: 0, sceneCount: 0
    ) == .planning(refresh: false))
    // No lens: goal readiness decides, and a failed run offers retry.
    #expect(scenesV2StageSpotlightState(
        hasLens: false, isGoalReady: false, isPlanningActive: false, planFailed: false,
        plannedImageIdsInPlanOrder: [], renderedFrameCount: 0, sceneCount: 0
    ) == .storyNotReady)
    #expect(scenesV2StageSpotlightState(
        hasLens: false, isGoalReady: true, isPlanningActive: false, planFailed: true,
        plannedImageIdsInPlanOrder: [], renderedFrameCount: 0, sceneCount: 0
    ) == .readyToPlan(retry: true))
    // Scenes exist: the spotlight never returns, whatever remains planned.
    #expect(scenesV2StageSpotlightState(
        hasLens: true, isGoalReady: true, isPlanningActive: false, planFailed: false,
        plannedImageIdsInPlanOrder: ["p1"], renderedFrameCount: 3, sceneCount: 1
    ) == .normalStage)
    // Rendered work with zero scenes: build the first Scene.
    #expect(scenesV2StageSpotlightState(
        hasLens: true, isGoalReady: true, isPlanningActive: false, planFailed: false,
        plannedImageIdsInPlanOrder: ["p1"], renderedFrameCount: 1, sceneCount: 0
    ) == .startFirstScene)
    // Plans and nothing rendered: art-direct, focused on plan #1.
    #expect(scenesV2StageSpotlightState(
        hasLens: true, isGoalReady: true, isPlanningActive: false, planFailed: false,
        plannedImageIdsInPlanOrder: ["p1", "p2"], renderedFrameCount: 0, sceneCount: 0
    ) == .artDirect(focusImageId: "p1"))
    // Degenerate lens with no plans and no renders.
    #expect(scenesV2StageSpotlightState(
        hasLens: true, isGoalReady: true, isPlanningActive: false, planFailed: false,
        plannedImageIdsInPlanOrder: [], renderedFrameCount: 0, sceneCount: 0
    ) == .emptyPlan)
}

@Test func whisperLineComposesHonestCountsAndFallsBack() {
    #expect(scenesV2WhisperLine(
        hasLens: false, claim: "A claim", fallbackTitle: "T",
        plannedCount: 6, renderedCount: 0, sceneCount: 0
    ) == "")
    #expect(scenesV2WhisperLine(
        hasLens: true, claim: "Survival becomes initiation", fallbackTitle: "",
        plannedCount: 6, renderedCount: 0, sceneCount: 0
    ) == "Survival becomes initiation · 6 suggested · 0 rendered")
    #expect(scenesV2WhisperLine(
        hasLens: true, claim: "  ", fallbackTitle: "The Living Threshold",
        plannedCount: 0, renderedCount: 4, sceneCount: 2
    ) == "The Living Threshold · 4 rendered · 2 Scenes")
    #expect(scenesV2WhisperLine(
        hasLens: true, claim: "", fallbackTitle: " ",
        plannedCount: 0, renderedCount: 1, sceneCount: 1
    ) == "Scene Plan · 1 rendered · 1 Scene")
}

@Test func chapterTitlesPreferTheSnapshotAndFallBackToTheSignature() {
    #expect(scenesV2StoryChapterTitles(
        snapshotTitlesInOrder: ["The Palm ", "", "The Refusal"],
        signatureSceneFunctions: ["opening"]
    ) == ["The Palm", "The Refusal"])
    #expect(scenesV2StoryChapterTitles(
        snapshotTitlesInOrder: ["  ", ""],
        signatureSceneFunctions: ["opening", " turn "]
    ) == ["opening", "turn"])
    #expect(scenesV2StoryChapterTitles(snapshotTitlesInOrder: [], signatureSceneFunctions: []) == [])
}

@Test func emptyStagePlateCopySpeaksOnlyForScenesExistStates() {
    #expect(scenesV2EmptyStagePlateCopy(allScenesMarkedReady: true)
        == "Every Scene is marked ready — click a rail card to revisit one")
    #expect(scenesV2EmptyStagePlateCopy(allScenesMarkedReady: false)
        == "Click a Scene in the rail to stage it")
}

@Test func stageAccentSwatchesFilterCapAndDedupe() {
    func swatch(_ name: String, _ hex: String) -> LensColorSwatch {
        LensColorSwatch(name: name, hex: hex, role: "", note: "")
    }
    let palette = [
        swatch("teal", "#2E5D55"),
        swatch("not-a-color", "oxidized"),
        swatch("short", "#FFF"),
        swatch("teal again", "2e5d55"),
        swatch("amber", "B67A2E"),
        swatch("wet stone", "#3A3F41"),
        swatch("fourth", "#111111")
    ]
    let accents = scenesV2StageAccentSwatches(palette)
    #expect(accents.map(\.name) == ["teal", "amber", "wet stone"])
    #expect(scenesV2StageAccentSwatches([]).isEmpty)
    #expect(scenesV2StageAccentSwatches([swatch("bad", "zzz")]).isEmpty)
}

@Test func analyzeButtonStateMatrix() {
    #expect(mediaAnalyzeButtonState(hasObservation: false, isCurrentVersion: false) == .analyze)
    #expect(mediaAnalyzeButtonState(hasObservation: false, isCurrentVersion: true) == .analyze)
    #expect(mediaAnalyzeButtonState(hasObservation: true, isCurrentVersion: false) == .reanalyze)
    #expect(mediaAnalyzeButtonState(hasObservation: true, isCurrentVersion: true) == .hidden)
}
