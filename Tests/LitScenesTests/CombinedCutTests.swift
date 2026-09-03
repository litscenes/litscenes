import Foundation
import Testing
@testable import LitScenes

private func combinedFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        label: id.uppercased(),
        provider: "test",
        imagePath: "/frames/\(id).png",
        status: "ready"
    )
}

private func combinedFootage(_ id: String, seconds: Double = 4) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: id,
        sourceId: "source",
        kind: .video,
        filename: "\(id).mov",
        path: "/media/\(id).mov",
        relativePath: "\(id).mov",
        byteCount: 1,
        modifiedAt: "t0",
        width: 1920,
        height: 1080,
        durationSeconds: seconds,
        nominalFrameRate: 24,
        thumbnailPath: "/media/\(id).jpg",
        videoStripPath: nil,
        scannedAt: "t0",
        scanError: nil
    )
}

@Test func placementScopedSegmentClipLookupKeepsDuplicatePairsIndependent() {
    var artifact = ShotRenderArtifact()
    artifact.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        placementStartEntryId: "e1",
        placementEndEntryId: "e2",
        clipPath: "/clips/first.mp4"
    ))
    artifact.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        placementStartEntryId: "e3",
        placementEndEntryId: "e4",
        clipPath: "/clips/second.mp4"
    ))
    #expect(artifact.segmentClips.count == 2)
    #expect(artifact.segmentClip(
        placementStartEntryId: "e1",
        placementEndEntryId: "e2",
        forStart: "f1",
        end: "f2"
    )?.clipPath == "/clips/first.mp4")
    #expect(artifact.segmentClip(
        placementStartEntryId: "e3",
        placementEndEntryId: "e4",
        forStart: "f1",
        end: "f2"
    )?.clipPath == "/clips/second.mp4")
    #expect(artifact.segmentClip(
        placementStartEntryId: "unknown",
        placementEndEntryId: "placement",
        forStart: "f1",
        end: "f2"
    ) == nil)

    var legacy = ShotRenderArtifact()
    legacy.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: "/clips/legacy.mp4"
    ))
    #expect(legacy.segmentClip(
        placementStartEntryId: "e1",
        placementEndEntryId: "e2",
        forStart: "f1",
        end: "f2"
    )?.clipPath == "/clips/legacy.mp4")
}

@Test func combinedCutCopiesRawEntriesSeedsMediaAndPartitionsSourceBoundary() throws {
    var first = ProjectShot(
        shotId: "cut_a",
        name: "Arrival",
        entries: [
            ShotFrameEntry(entryId: "a1", frameImageId: "f1"),
            ShotFrameEntry(entryId: "a2", frameImageId: "f2")
        ],
        segmentPromptOverrides: [
            ShotSegmentPromptOverride(
                startFrameImageId: "f1",
                endFrameImageId: "f2",
                placementStartEntryId: "a1",
                placementEndEntryId: "a2",
                prompt: "Move with restraint."
            )
        ],
        createdAt: "t0",
        updatedAt: "t0"
    )
    var firstRender = ShotRenderArtifact(
        versionId: "render_a",
        versionNumber: 1,
        status: "ready",
        videoPath: "/clips/a.mp4"
    )
    firstRender.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        placementStartEntryId: "a1",
        placementEndEntryId: "a2",
        clipPath: "/clips/a_segment.mp4",
        provider: "fal",
        model: "model-a",
        traceId: "trace-a",
        durationSeconds: 5
    ))
    first = first.upsertingRenderVersion(firstRender, activate: true, now: "t0")

    var second = ProjectShot(
        shotId: "cut_b",
        name: "Footage",
        entries: [ShotFrameEntry(entryId: "b1", clipMediaId: "m1")],
        createdAt: "t0",
        updatedAt: "t0"
    )
    second.lookVersions = [ShotRestyleArtifact(
        versionId: "look_b",
        versionNumber: 1,
        status: "ready",
        videoPath: "/looks/b.mp4"
    )]
    second.activeLookVersionId = "look_b"

    let result = buildCombinedCut(
        sources: [first, second],
        frameLookup: ["f1": combinedFrame("f1"), "f2": combinedFrame("f2")],
        mediaLookup: ["m1": combinedFootage("m1")],
        meaningNodes: [],
        now: "t1",
        fileExists: { ["/clips/a_segment.mp4", "/media/m1.mov"].contains($0) }
    )

    #expect(result.preflight.canCombine)
    #expect(result.preflight.reusableSegmentCount == 2)
    #expect(result.preflight.missingSegmentCount == 0)
    #expect(result.preflight.activeLookCount == 1)
    #expect(result.cut.renderVersions.isEmpty)
    #expect(result.cut.activeLookVersionId.isEmpty)
    #expect(result.cut.combinedSources.map(\.sourceCutId) == ["cut_a", "cut_b"])
    #expect(result.cut.entries.count == 3)
    #expect(Set(result.cut.entries.map(\.entryId)).isDisjoint(with: ["a1", "a2", "b1"]))
    #expect(result.cut.sourceBoundaries.count == 1)
    #expect(result.cut.sourceBoundaries[0].rightEntryId == result.cut.entries[2].entryId)
    #expect(result.cut.entries[2].leadSeamPreference == .cut)
    #expect(result.cut.segmentPromptOverrides.count == 1)
    #expect(result.cut.segmentPromptOverrides[0].placementStartEntryId == result.cut.entries[0].entryId)
    #expect(result.cut.seedSegmentClips.contains { $0.traceId == "trace-a" && $0.sourceCutId == "cut_a" })

    let parentPlan = shotRenderSegmentPlan(
        shot: result.cut,
        frameLookup: ["f1": combinedFrame("f1"), "f2": combinedFrame("f2")],
        mediaLookup: ["m1": combinedFootage("m1")],
        meaningNodes: []
    )
    #expect(parentPlan.segments.count == 2)
    #expect(parentPlan.generatedItems.count == 1)
}

@Test func combinedCutImportsActiveAudioAsOffsetRegionsAndRipplesOverlays() {
    var firstMix = ShotAudioMix()
        .settingLaneVolume(ShotAudioLaneId.source, volume: 0.4)
        .settingNarrationStartSeconds(1)
    firstMix = firstMix.settingLaneVolume(ShotAudioLaneId.narration, volume: 0.7)
    let narration = ShotNarrationArtifact(
        status: "ready",
        audioPath: "/audio/narration.m4a",
        durationSeconds: 2
    )
    let first = ProjectShot(
        shotId: "a",
        name: "A",
        entries: [ShotFrameEntry(entryId: "a1", frameImageId: "f1")],
        narrationArtifact: narration,
        audioMix: firstMix
    )
    let second = ProjectShot(
        shotId: "b",
        name: "B",
        entries: [ShotFrameEntry(entryId: "b1", frameImageId: "f2")]
    )
    let result = buildCombinedCut(
        sources: [first, second],
        frameLookup: ["f1": combinedFrame("f1"), "f2": combinedFrame("f2")],
        mediaLookup: [:],
        meaningNodes: [],
        now: "t1",
        fileExists: { _ in false }
    )
    let sourceRegions = result.cut.audioRegions.filter { $0.laneId == ShotAudioLaneId.source }
    let narrationRegions = result.cut.audioRegions.filter { $0.laneId == ShotAudioLaneId.narration }
    #expect(sourceRegions.count == 2)
    #expect(sourceRegions[0].gain == 0.4)
    #expect(narrationRegions.count == 1)
    #expect(narrationRegions[0].startSeconds == 1)
    #expect(narrationRegions[0].gain == 0.7)

    let rippled = result.cut.ripplingAudioRegions(atOrAfter: 0.5, by: 2, now: "t2")
    #expect(rippled.audioRegions.first { $0.laneId == ShotAudioLaneId.narration }?.startSeconds == 3)
    #expect(rippled.audioRegions.filter { $0.laneId == ShotAudioLaneId.source }.map(\.startSeconds)
        == sourceRegions.map(\.startSeconds))
}

@Test func repeatedCombinePreservesAndRekeysInheritedAudioRegions() throws {
    let narration = ShotNarrationArtifact(
        status: "ready",
        audioPath: "/audio/a.m4a",
        durationSeconds: 2
    )
    let first = ProjectShot(
        shotId: "a",
        name: "A",
        entries: [ShotFrameEntry(entryId: "a1", frameImageId: "f1")],
        narrationArtifact: narration
    )
    let second = ProjectShot(
        shotId: "b",
        name: "B",
        entries: [ShotFrameEntry(entryId: "b1", frameImageId: "f2")]
    )
    let frames = [
        "f1": combinedFrame("f1"),
        "f2": combinedFrame("f2"),
        "f3": combinedFrame("f3")
    ]
    let firstParent = buildCombinedCut(
        sources: [first, second],
        frameLookup: frames,
        mediaLookup: [:],
        meaningNodes: [],
        now: "t1",
        fileExists: { _ in false }
    ).cut
    let inheritedNarration = try #require(
        firstParent.audioRegions.first { $0.laneId == ShotAudioLaneId.narration }
    )
    let third = ProjectShot(
        shotId: "c",
        name: "C",
        entries: [ShotFrameEntry(entryId: "c1", frameImageId: "f3")]
    )
    let grown = buildCombinedCut(
        sources: [firstParent, third],
        frameLookup: frames,
        mediaLookup: [:],
        meaningNodes: [],
        now: "t2",
        fileExists: { _ in false }
    ).cut

    let grownNarration = try #require(
        grown.audioRegions.first { $0.laneId == ShotAudioLaneId.narration }
    )
    #expect(grownNarration.regionId != inheritedNarration.regionId)
    #expect(grownNarration.sourceCutId == "a")
    #expect(grownNarration.startSeconds == inheritedNarration.startSeconds)
    #expect(grownNarration.durationSeconds == inheritedNarration.durationSeconds)
    #expect(grown.audioRegions.filter { $0.laneId == ShotAudioLaneId.source }.count == 3)
    #expect(grown.sourceBoundaries.count == 2)
    let grownPlan = shotRenderSegmentPlan(
        shot: grown,
        frameLookup: frames,
        mediaLookup: [:],
        meaningNodes: []
    )
    #expect(grownPlan.generatedItems.count == 3)
}

@Test func sourceBoundaryNeverLetsAnIsolatedExtensionAnchorAcrossCuts() throws {
    let extensionSource = ProjectShot(
        shotId: "extension",
        name: "Extension",
        entries: [ShotFrameEntry(entryId: "x1", isAIExtension: true)]
    )
    let frameSource = ProjectShot(
        shotId: "frame",
        name: "Frame",
        entries: [ShotFrameEntry(entryId: "f1", frameImageId: "frame_1")]
    )
    let result = buildCombinedCut(
        sources: [extensionSource, frameSource],
        frameLookup: ["frame_1": combinedFrame("frame_1")],
        mediaLookup: [:],
        meaningNodes: [],
        now: "t1",
        fileExists: { _ in false }
    )
    let plan = shotRenderSegmentPlan(
        shot: result.cut,
        frameLookup: ["frame_1": combinedFrame("frame_1")],
        mediaLookup: [:],
        meaningNodes: []
    )

    #expect(plan.generatedItems.count == 1)
    let only = try #require(plan.generatedItems.first)
    #expect(only.pair.start?.imageId == "frame_1")
    #expect(only.pair.end == nil)
    #expect(plan.skipped.contains { $0.contains("AI extension") })
}

@Test func combinedStageGroupCollapsesSourcesUncombinePreservesFinalsAndRestoreRebuildsGroup() throws {
    var document = ProjectStageSetDocument(
        projectId: "p1",
        stages: [ProjectStage(stageId: "stage", name: "Stage", cutIds: ["a", "b", "c"])],
        finals: [StageFinalsEntry(entryId: "final_a", cutId: "a")]
    )
    document = document.groupingCombinedCut(
        parentCutId: "parent",
        sourceCutIds: ["a", "b"],
        inStage: "stage",
        now: "t1"
    )
    let stage = try #require(document.stage(withId: "stage"))
    #expect(stage.cutIds == ["parent", "a", "b", "c"])
    #expect(document.visibleCutIds(in: stage) == ["parent", "c"])
    #expect(document.finals.map(\.cutId) == ["a"])

    let uncombined = document.ungroupingCombinedCut(parentCutId: "parent", now: "t2")
    let revealedStage = try #require(uncombined.stage(withId: "stage"))
    #expect(uncombined.visibleCutIds(in: revealedStage) == ["a", "b", "c"])
    #expect(uncombined.finals.map(\.cutId) == ["a"])
    let trash = try #require(uncombined.trashedCuts.first { $0.cutId == "parent" })
    #expect(trash.combinedSourceCutIds == ["a", "b"])

    let restored = uncombined.restoringCut(trashEntryId: trash.entryId, now: "t3").document
    let restoredStage = try #require(restored.stage(withId: "stage"))
    #expect(restored.visibleCutIds(in: restoredStage) == ["parent", "c"])
    #expect(restored.group(parentCutId: "parent")?.sourceCutIds == ["a", "b"])
}

@Test func atomicProjectDocumentBatchRollsBackEarlierWriteWhenLaterIdentityIsInvalid() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_combined_cut_atomic_\(UUID().uuidString)", isDirectory: true)
    let library = ProjectLibrary(root: root)
    let project = try library.createProject(named: "Combined Cut Atomic")
    let store = ProjectSQLiteDocumentStore(projectLibrary: library)
    let original = ProjectShotTimelineDocument(
        projectId: project.projectId,
        shots: [ProjectShot(shotId: "original")]
    )
    try store.saveDocument(
        original,
        for: project,
        documentType: ProjectShotTimelineDocument.documentType
    )
    let replacement = ProjectShotTimelineDocument(
        projectId: project.projectId,
        shots: [ProjectShot(shotId: "replacement")]
    )
    #expect(throws: (any Error).self) {
        try store.saveDocumentsAtomically([
            ProjectDocumentBatchWrite(
                data: try JSONCoding.encoder.encode(replacement),
                documentType: ProjectShotTimelineDocument.documentType
            ),
            ProjectDocumentBatchWrite(
                data: Data("{}".utf8),
                documentType: ""
            )
        ], for: project)
    }
    let loaded = try store.loadDocument(
        ProjectShotTimelineDocument.self,
        for: project,
        documentType: ProjectShotTimelineDocument.documentType
    )
    #expect(loaded?.shots.map(\.shotId) == ["original"])
}

/// A whole-output loop is an assembly-time repeat; a combined CUT copies
/// MATERIAL. The build carries the looped source's material once and says so.
@Test func combinedCutCarriesALoopedSourceOnceAndWarns() {
    var first = ProjectShot(
        shotId: "cut_looped",
        name: "Looped",
        entries: [ShotFrameEntry(entryId: "l1", clipMediaId: "m1")],
        createdAt: "t0",
        updatedAt: "t0"
    )
    first.cutList.outputLoopCount = 3
    let second = ProjectShot(
        shotId: "cut_plain",
        name: "Plain",
        entries: [ShotFrameEntry(entryId: "p1", clipMediaId: "m2")],
        createdAt: "t0",
        updatedAt: "t0"
    )

    let result = buildCombinedCut(
        sources: [first, second],
        frameLookup: [:],
        mediaLookup: ["m1": combinedFootage("m1"), "m2": combinedFootage("m2")],
        meaningNodes: [],
        now: "t1",
        fileExists: { ["/media/m1.mov", "/media/m2.mov"].contains($0) }
    )

    // The combined CUT starts unlooped — the fresh cut list drops the repeat.
    #expect(result.cut.cutList.outputLoopCount == 1)
    // And the preflight names what was left behind, once per looped source.
    #expect(result.preflight.warnings.contains { $0.contains("loops ×3") })
    #expect(result.preflight.warnings.filter { $0.contains("loops ×") }.count == 1)
}
