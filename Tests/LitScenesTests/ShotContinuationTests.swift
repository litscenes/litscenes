import Foundation
import Testing
@testable import LitScenes

private func continuationClip(
    takeId: String,
    sourceEntryId: String,
    entryId: String,
    path: String
) -> ShotRenderSegmentClip {
    ShotRenderSegmentClip(
        startFrameImageId: "anchor_\(takeId)",
        placementStartEntryId: sourceEntryId,
        placementEndEntryId: entryId,
        clipPath: path,
        requestId: "request_\(takeId)",
        prompt: "Continue the motion.",
        provider: "fal",
        model: "model",
        continuationTakeId: takeId,
        requestedDurationSeconds: 5,
        durationSeconds: 5,
        updatedAt: "2026-01-01T00:00:00Z"
    )
}

private func continuationTake(
    id: String,
    number: Int,
    sourceEntryId: String,
    sourceTakeId: String = "",
    inputFingerprint: String,
    outputFingerprint: String,
    entryId: String
) -> ShotContinuationTake {
    let clip = continuationClip(
        takeId: id,
        sourceEntryId: sourceEntryId,
        entryId: entryId,
        path: "/tmp/\(id).mp4"
    )
    return ShotContinuationTake(
        takeId: id,
        takeNumber: number,
        status: ShotContinuationTakeStatus.ready.rawValue,
        anchor: ShotContinuationAnchor(
            sourceKind: sourceTakeId.isEmpty ? "frame" : "continuation_take",
            sourceEntryId: sourceEntryId,
            sourceTakeId: sourceTakeId,
            framePath: "/tmp/\(id)_anchor.png",
            frameFingerprint: inputFingerprint,
            tailClipPath: sourceTakeId.isEmpty ? "" : "/tmp/\(sourceTakeId).mp4",
            tailClipEndSeconds: sourceTakeId.isEmpty ? 0 : 5
        ).normalized(),
        prompt: "Continue the motion.",
        mode: ShotContinuationMode.outFrame.rawValue,
        stack: ShotRenderStack.wan27Five.rawValue,
        segmentClip: clip,
        finalFramePath: "/tmp/\(id)_end.png",
        outputFingerprint: outputFingerprint,
        requestId: clip.requestId,
        createdAt: "2026-01-01T00:00:00Z",
        updatedAt: "2026-01-01T00:00:00Z"
    )
}

private func continuationRecord(
    entryId: String,
    sourceEntryId: String,
    takes: [ShotContinuationTake],
    selectedTakeId: String
) -> ShotContinuationRecord {
    ShotContinuationRecord(
        entryId: entryId,
        sourceEntryId: sourceEntryId,
        selectedTakeId: selectedTakeId,
        takes: takes,
        createdAt: "2026-01-01T00:00:00Z",
        updatedAt: "2026-01-01T00:00:00Z"
    ).normalized()
}

@Test func continuationLegacyShotDecodeDefaultsToNoRecords() throws {
    let json = """
    {
      "shotId": "shot_legacy",
      "name": "Legacy",
      "entries": [{"entryId": "frame", "frameImageId": "image"}]
    }
    """
    let shot = try JSONDecoder().decode(ProjectShot.self, from: Data(json.utf8))
    #expect(shot.continuationRecords.isEmpty)
    #expect(shot.entries.map(\.entryId) == ["frame"])
}

@Test func continuationSparseRecordsDecodeTolerantly() throws {
    let json = """
    {
      "entryId": "extension",
      "takes": [{"takeId": "take_sparse"}]
    }
    """
    let record = try JSONDecoder().decode(ShotContinuationRecord.self, from: Data(json.utf8))
    #expect(record.entryId == "extension")
    #expect(record.takes.map(\.takeId) == ["take_sparse"])
    #expect(record.takes[0].anchor.sourceKind.isEmpty)
    #expect(record.takes[0].segmentClip == nil)
}

@Test func continuationRecordsRoundTripWithSegmentProvenance() throws {
    let take = continuationTake(
        id: "take_1",
        number: 1,
        sourceEntryId: "frame",
        inputFingerprint: "frame-a",
        outputFingerprint: "output-a",
        entryId: "extension"
    )
    let shot = ProjectShot(
        shotId: "shot",
        entries: [
            ShotFrameEntry(entryId: "frame", frameImageId: "image"),
            ShotFrameEntry(entryId: "extension", isAIExtension: true)
        ],
        continuationRecords: [continuationRecord(
            entryId: "extension",
            sourceEntryId: "frame",
            takes: [take],
            selectedTakeId: take.takeId
        )]
    )
    let decoded = try JSONDecoder().decode(ProjectShot.self, from: JSONEncoder().encode(shot))
    let restored = try #require(decoded.continuationRecord(entryId: "extension")?.selectedTake)
    #expect(restored.takeId == "take_1")
    #expect(restored.segmentClip?.continuationTakeId == "take_1")
    #expect(restored.outputFingerprint == "output-a")
}

@Test func continuationNormalizationPreservesRealizedAdjacentMarkers() {
    let first = continuationTake(
        id: "take_a",
        number: 1,
        sourceEntryId: "frame",
        inputFingerprint: "frame-a",
        outputFingerprint: "output-a",
        entryId: "extension_a"
    )
    let second = continuationTake(
        id: "take_b",
        number: 1,
        sourceEntryId: "extension_a",
        sourceTakeId: "take_a",
        inputFingerprint: "output-a",
        outputFingerprint: "output-b",
        entryId: "extension_b"
    )
    let shot = ProjectShot(
        shotId: "shot",
        entries: [
            ShotFrameEntry(entryId: "frame", frameImageId: "image"),
            ShotFrameEntry(entryId: "extension_a", isAIExtension: true),
            ShotFrameEntry(entryId: "extension_b", isAIExtension: true)
        ],
        continuationRecords: [
            continuationRecord(entryId: "extension_a", sourceEntryId: "frame", takes: [first], selectedTakeId: first.takeId),
            continuationRecord(entryId: "extension_b", sourceEntryId: "extension_a", takes: [second], selectedTakeId: second.takeId)
        ]
    ).normalized()
    #expect(shot.entries.map(\.entryId) == ["frame", "extension_a", "extension_b"])
    #expect(shotHasDependentContinuationChain(shot))
}

@Test func continuationSelectionDerivesDownstreamStaleness() {
    let firstA = continuationTake(
        id: "take_a1",
        number: 1,
        sourceEntryId: "frame",
        inputFingerprint: "frame-a",
        outputFingerprint: "output-a1",
        entryId: "extension_a"
    )
    let firstB = continuationTake(
        id: "take_a2",
        number: 2,
        sourceEntryId: "frame",
        inputFingerprint: "frame-a",
        outputFingerprint: "output-a2",
        entryId: "extension_a"
    )
    let second = continuationTake(
        id: "take_b1",
        number: 1,
        sourceEntryId: "extension_a",
        sourceTakeId: "take_a1",
        inputFingerprint: "output-a1",
        outputFingerprint: "output-b1",
        entryId: "extension_b"
    )
    let base = ProjectShot(
        shotId: "shot",
        entries: [
            ShotFrameEntry(entryId: "frame", frameImageId: "image"),
            ShotFrameEntry(entryId: "extension_a", isAIExtension: true),
            ShotFrameEntry(entryId: "extension_b", isAIExtension: true)
        ],
        continuationRecords: [
            continuationRecord(entryId: "extension_a", sourceEntryId: "frame", takes: [firstA, firstB], selectedTakeId: firstA.takeId),
            continuationRecord(entryId: "extension_b", sourceEntryId: "extension_a", takes: [second], selectedTakeId: second.takeId)
        ]
    )
    #expect(shotContinuationStaleEntryIds(base).isEmpty)
    let branched = base.selectingContinuationTake(
        entryId: "extension_a",
        takeId: "take_a2",
        now: "2026-01-02T00:00:00Z"
    )
    #expect(shotContinuationStaleEntryIds(branched) == ["extension_b"])
}

@Test func continuationPlannerEmitsEveryAdjacentRealizedLink() throws {
    let first = continuationTake(
        id: "take_a",
        number: 1,
        sourceEntryId: "frame",
        inputFingerprint: "frame-a",
        outputFingerprint: "output-a",
        entryId: "extension_a"
    )
    let second = continuationTake(
        id: "take_b",
        number: 1,
        sourceEntryId: "extension_a",
        sourceTakeId: "take_a",
        inputFingerprint: "output-a",
        outputFingerprint: "output-b",
        entryId: "extension_b"
    )
    let shot = ProjectShot(
        shotId: "shot",
        entries: [
            ShotFrameEntry(entryId: "frame", frameImageId: "image"),
            ShotFrameEntry(entryId: "extension_a", isAIExtension: true),
            ShotFrameEntry(entryId: "extension_b", isAIExtension: true)
        ],
        continuationRecords: [
            continuationRecord(entryId: "extension_a", sourceEntryId: "frame", takes: [first], selectedTakeId: first.takeId),
            continuationRecord(entryId: "extension_b", sourceEntryId: "extension_a", takes: [second], selectedTakeId: second.takeId)
        ]
    )
    let plan = shotRenderSegmentPlan(
        shot: shot,
        frameLookup: [
            "image": ProjectLensHeroImage(
                imageId: "image",
                label: "A neutral scene",
                imagePath: "/tmp/image.png",
                prompt: "A neutral scene",
                status: "ready"
            )
        ],
        mediaLookup: [:],
        meaningNodes: []
    )
    #expect(plan.generatedItems.count == 2)
    #expect(plan.generatedItems.map(\.continuationTakeId) == ["take_a", "take_b"])
    #expect(plan.generatedItems[1].pair.start?.imagePath == second.anchor.framePath)
}

@Test func continuationOfRenderedSceneKeepsOriginalBeforeNewTake() throws {
    let originalPath = "/tmp/rendered-original.mp4"
    let continuationPath = "/tmp/rendered-continuation.mp4"
    let originalClip = ShotRenderSegmentClip(
        startFrameImageId: "image",
        placementStartEntryId: "frame",
        clipPath: originalPath,
        requestId: "request_original",
        prompt: "A neutral scene.",
        provider: "fal",
        model: "model",
        requestedDurationSeconds: 15,
        durationSeconds: 15.042,
        updatedAt: "2026-01-01T00:00:00Z"
    )
    var take = continuationTake(
        id: "take_extension",
        number: 1,
        sourceEntryId: "frame",
        inputFingerprint: "original-tail",
        outputFingerprint: "continuation-tail",
        entryId: "extension"
    )
    take.anchor = ShotContinuationAnchor(
        sourceKind: "rendered_original",
        sourceEntryId: "frame",
        sourceRenderVersionId: "version_original",
        sourceSegmentPlacementKey: originalClip.placementKey,
        framePath: "/tmp/original-tail.png",
        frameFingerprint: "original-tail",
        tailClipPath: originalPath,
        tailClipStartSeconds: 0,
        tailClipEndSeconds: 15.042
    ).normalized()
    take.segmentClip?.clipPath = continuationPath

    let originalVersion = ShotRenderArtifact(
        versionId: "version_original",
        versionNumber: 1,
        provider: "fal",
        model: "model",
        status: "ready",
        videoPath: originalPath,
        clipPaths: [originalPath],
        segmentCount: 1,
        totalSeconds: 15,
        segmentClips: [originalClip]
    )
    let continuationVersion = ShotRenderArtifact(
        versionId: "version_continuation_only",
        versionNumber: 2,
        provider: "fal",
        model: "model",
        status: "ready",
        videoPath: continuationPath,
        clipPaths: [continuationPath],
        segmentCount: 1,
        totalSeconds: 5,
        segmentClips: [try #require(take.segmentClip)]
    )
    let shot = ProjectShot(
        shotId: "shot",
        entries: [
            ShotFrameEntry(entryId: "frame", frameImageId: "image"),
            ShotFrameEntry(entryId: "extension", isAIExtension: true)
        ],
        renderArtifact: continuationVersion,
        renderVersions: [originalVersion, continuationVersion],
        activeRenderVersionId: continuationVersion.versionId,
        continuationRecords: [continuationRecord(
            entryId: "extension",
            sourceEntryId: "frame",
            takes: [take],
            selectedTakeId: take.takeId
        )]
    )
    let frameLookup = [
        "image": ProjectLensHeroImage(
            imageId: "image",
            imagePath: "/tmp/image.png",
            prompt: "A neutral scene.",
            status: "ready"
        )
    ]
    let plan = shotRenderSegmentPlan(
        shot: shot,
        frameLookup: frameLookup,
        mediaLookup: [:],
        meaningNodes: []
    )

    #expect(plan.segments.count == 2)
    #expect(plan.generatedItems.map(\.continuationTakeId) == [take.takeId])
    guard case .preserved(let original) = plan.segments[0] else {
        Issue.record("The rendered original must remain first in the Scene plan")
        return
    }
    #expect(original.clip.clipPath == originalPath)
    guard case .generated = plan.segments[1] else {
        Issue.record("The continuation must follow the rendered original")
        return
    }

    let assembly = shotCutAssembly(
        shot: shot,
        planSegments: plan.segments,
        clipDurationsByPath: [
            originalPath: 15.042,
            continuationPath: 5
        ],
        fileExists: { _ in true }
    )
    #expect(assembly.playbackItems.map(\.url.path) == [originalPath, continuationPath])
    #expect(abs(assembly.outputSeconds - 19.917) < 0.001)
    #expect(shotRuntimeSummary(
        shot: shot,
        frameLookup: frameLookup,
        mediaLookup: [:]
    ).estimatedSeconds(generatedSeconds: 5) == 20)
}

@Test func continuationVersionActivationRestoresItsTakeSelection() {
    let first = continuationTake(
        id: "take_1",
        number: 1,
        sourceEntryId: "frame",
        inputFingerprint: "frame-a",
        outputFingerprint: "output-1",
        entryId: "extension"
    )
    let second = continuationTake(
        id: "take_2",
        number: 2,
        sourceEntryId: "frame",
        inputFingerprint: "frame-a",
        outputFingerprint: "output-2",
        entryId: "extension"
    )
    let version = ShotRenderArtifact(
        versionId: "version_1",
        versionNumber: 1,
        status: "ready",
        videoPath: "/tmp/scene.mp4",
        segmentClips: [second.segmentClip!]
    )
    let shot = ProjectShot(
        shotId: "shot",
        entries: [
            ShotFrameEntry(entryId: "frame", frameImageId: "image"),
            ShotFrameEntry(entryId: "extension", isAIExtension: true)
        ],
        renderVersions: [version],
        continuationRecords: [continuationRecord(
            entryId: "extension",
            sourceEntryId: "frame",
            takes: [first, second],
            selectedTakeId: first.takeId
        )]
    )
    let activated = shot.activatingRenderVersion("version_1", now: "now")
    #expect(activated.continuationRecord(entryId: "extension")?.selectedTakeId == "take_2")
}

@Test func continuationNativeSourceAcceptsRenderedTail() {
    let anchor = ShotContinuationAnchor(
        sourceKind: "continuation_take",
        sourceEntryId: "extension_a",
        sourceTakeId: "take_a",
        framePath: "/tmp/end.png",
        frameFingerprint: "end-a",
        tailClipPath: "/tmp/take_a.mp4",
        tailClipStartSeconds: 0,
        tailClipEndSeconds: 5
    ).normalized()
    let source = ShotNativeExtendSource.anchor(anchor)
    #expect(source?.path == "/tmp/take_a.mp4")
    #expect(source?.sourceTakeId == "take_a")
    #expect(ltxShotExtendContextSeconds(
        sourceDurationSeconds: source?.durationSeconds ?? 0,
        extensionDurationSeconds: 5
    ) == 2)
}

@Test func continuationLegacyClipMigrationIsDeterministicAndVersionAware() throws {
    let legacyClip = ShotRenderSegmentClip(
        startFrameImageId: "anchor",
        placementStartEntryId: "frame",
        placementEndEntryId: "extension",
        clipPath: "/tmp/legacy-extension.mp4",
        requestId: "legacy-request",
        prompt: "Continue naturally.",
        provider: ShotRenderStack.wan27Five.providerSelection.rawValue,
        model: ShotRenderStack.wan27Five.openEndedModelSelection.providerModelId,
        requestedDurationSeconds: 5,
        durationSeconds: 5,
        updatedAt: "2026-01-01T00:00:00Z"
    )
    let version = ShotRenderArtifact(
        versionId: "version_legacy",
        versionNumber: 1,
        status: "ready",
        videoPath: "/tmp/legacy-scene.mp4",
        segmentClips: [legacyClip],
        generatedAt: "2026-01-01T00:00:00Z"
    )
    let shot = ProjectShot(
        shotId: "shot",
        entries: [
            ShotFrameEntry(entryId: "frame", frameImageId: "image"),
            ShotFrameEntry(entryId: "extension", isAIExtension: true)
        ],
        renderArtifact: version,
        renderVersions: [version],
        activeRenderVersionId: version.versionId
    )

    let first = shot.normalized()
    let second = first.normalized()
    let takeId = try #require(first.continuationRecord(entryId: "extension")?.selectedTakeId.nilIfEmpty)
    #expect(second.continuationRecord(entryId: "extension")?.selectedTakeId == takeId)
    #expect(first.renderVersions[0].segmentClips[0].continuationTakeId == takeId)
    #expect(first.continuationRecord(entryId: "extension")?.selectedTake?.renderStack == .wan27Five)
    #expect(second.activatingRenderVersion(version.versionId, now: "now")
        .continuationRecord(entryId: "extension")?.selectedTakeId == takeId)
}

@Test func continuationLegacyAdjacentClipsRecoverTheirLineage() throws {
    let firstClip = ShotRenderSegmentClip(
        startFrameImageId: "anchor",
        placementStartEntryId: "frame",
        placementEndEntryId: "extension_a",
        clipPath: "/tmp/legacy-extension-a.mp4",
        requestId: "legacy-request-a",
        prompt: "Continue naturally.",
        provider: ShotRenderStack.wan27Five.providerSelection.rawValue,
        model: ShotRenderStack.wan27Five.openEndedModelSelection.providerModelId,
        requestedDurationSeconds: 5,
        durationSeconds: 5,
        updatedAt: "2026-01-01T00:00:00Z"
    )
    let secondClip = ShotRenderSegmentClip(
        startFrameImageId: "legacy-output-a",
        placementStartEntryId: "extension_a",
        placementEndEntryId: "extension_b",
        clipPath: "/tmp/legacy-extension-b.mp4",
        requestId: "legacy-request-b",
        prompt: "Continue once more.",
        provider: ShotRenderStack.wan27Five.providerSelection.rawValue,
        model: ShotRenderStack.wan27Five.openEndedModelSelection.providerModelId,
        requestedDurationSeconds: 5,
        durationSeconds: 5,
        updatedAt: "2026-01-01T00:01:00Z"
    )
    let version = ShotRenderArtifact(
        versionId: "version_legacy_chain",
        versionNumber: 1,
        status: "ready",
        videoPath: "/tmp/legacy-chain.mp4",
        segmentClips: [firstClip, secondClip],
        generatedAt: "2026-01-01T00:01:00Z"
    )
    let migrated = ProjectShot(
        shotId: "shot",
        entries: [
            ShotFrameEntry(entryId: "frame", frameImageId: "image"),
            ShotFrameEntry(entryId: "extension_a", isAIExtension: true),
            ShotFrameEntry(entryId: "extension_b", isAIExtension: true)
        ],
        renderArtifact: version
    ).normalized()

    let firstTake = try #require(migrated.continuationRecord(entryId: "extension_a")?.selectedTake)
    let secondTake = try #require(migrated.continuationRecord(entryId: "extension_b")?.selectedTake)
    #expect(secondTake.anchor.sourceTakeId == firstTake.takeId)
    #expect(secondTake.anchor.frameFingerprint == firstTake.outputFingerprint)
    #expect(secondTake.anchor.tailClipPath == firstClip.clipPath)
    #expect(secondTake.anchor.sourceSegmentPlacementKey == firstClip.placementKey)
    #expect(shotContinuationStaleEntryIds(migrated).isEmpty)
}

@Test func continuationInFlightAttemptReconcilesAsInterrupted() throws {
    var take = continuationTake(
        id: "take_in_flight",
        number: 1,
        sourceEntryId: "frame",
        inputFingerprint: "frame-a",
        outputFingerprint: "",
        entryId: "extension"
    )
    take.status = ShotContinuationTakeStatus.generating.rawValue
    take.segmentClip = nil
    take.finalFramePath = ""
    let record = ShotContinuationRecord(
        entryId: "extension",
        sourceEntryId: "frame",
        renderingTakeId: take.takeId,
        takes: [take]
    )
    let shot = ProjectShot(
        shotId: "shot",
        entries: [
            ShotFrameEntry(entryId: "frame", frameImageId: "image"),
            ShotFrameEntry(entryId: "extension", isAIExtension: true)
        ],
        continuationRecords: [record]
    )

    let reconciled = shot.failingInFlightRenderVersions(now: "now")
    let restored = try #require(reconciled.shot.continuationRecord(entryId: "extension"))
    #expect(reconciled.changed)
    #expect(restored.renderingTakeId.isEmpty)
    #expect(restored.takes[0].takeStatus == .interrupted)
    #expect(restored.takes[0].errorMessage == "Interrupted before completion")
}

@Test func continuationStrictRenderNeverGeneratesUnpricedEarlierSegments() throws {
    var generating = continuationTake(
        id: "take_extension",
        number: 1,
        sourceEntryId: "frame_b",
        inputFingerprint: "frame-b",
        outputFingerprint: "",
        entryId: "extension"
    )
    generating.status = ShotContinuationTakeStatus.generating.rawValue
    generating.segmentClip = nil
    let record = ShotContinuationRecord(
        entryId: "extension",
        sourceEntryId: "frame_b",
        renderingTakeId: generating.takeId,
        takes: [generating]
    )
    let shot = ProjectShot(
        shotId: "shot",
        entries: [
            ShotFrameEntry(entryId: "frame_a", frameImageId: "image_a"),
            ShotFrameEntry(entryId: "frame_b", frameImageId: "image_b"),
            ShotFrameEntry(entryId: "extension", isAIExtension: true)
        ],
        continuationRecords: [record]
    )
    let frameLookup = [
        "image_a": ProjectLensHeroImage(
            imageId: "image_a",
            imagePath: "/tmp/image-a.png",
            prompt: "A neutral starting frame.",
            status: "ready"
        ),
        "image_b": ProjectLensHeroImage(
            imageId: "image_b",
            imagePath: generating.anchor.framePath,
            prompt: "A neutral endpoint frame.",
            status: "ready"
        )
    ]
    let plan = shotRenderSegmentPlan(
        shot: shot,
        frameLookup: frameLookup,
        mediaLookup: [:],
        meaningNodes: []
    )
    #expect(plan.generatedItems.count == 2)
    let targetKey = try #require(plan.generatedItems.last?.pair.placementKey)
    let decisions = shotSegmentRenderDecisions(
        items: plan.generatedItems,
        onlySegmentKeys: [targetKey],
        reuseSource: ShotRenderArtifact(),
        fileExists: { _ in false },
        omitUnselectedMissing: true
    )
    #expect(decisions == [.omit, .generate])
}
