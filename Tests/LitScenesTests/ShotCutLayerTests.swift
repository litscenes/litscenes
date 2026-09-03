import Foundation
import Testing
@testable import LitScenes

// MARK: Fixtures

private func cutFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        label: "Frame \(id)",
        imagePath: "/tmp/\(id).png",
        prompt: "A quiet harbor scene \(id)",
        status: "ready"
    )
}

private func cutVideoMedia(_ id: String, durationSeconds: Double? = 10) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: id,
        sourceId: "source_test",
        kind: .video,
        filename: "\(id).mp4",
        path: "/tmp/\(id).mp4",
        relativePath: "\(id).mp4",
        byteCount: 1,
        modifiedAt: "2026-07-17T00:00:00Z",
        width: 1080,
        height: 1920,
        durationSeconds: durationSeconds,
        nominalFrameRate: 24,
        thumbnailPath: "/tmp/\(id)_thumb.jpg",
        videoStripPath: nil,
        scannedAt: "2026-07-17T00:00:00Z",
        scanError: nil
    )
}

private let cutFrameLookup: [String: ProjectLensHeroImage] = [
    "f1": cutFrame("f1"),
    "f2": cutFrame("f2"),
    "f3": cutFrame("f3")
]

private let cutMediaLookup: [String: MediaItemRecord] = [
    "vid_1": cutVideoMedia("vid_1")
]

private func cutShot(_ entries: [ShotFrameEntry]) -> ProjectShot {
    ProjectShot(shotId: "shot_cut", name: "Cut layer", entries: entries)
}

private func cutPlanOf(_ shot: ProjectShot) -> (
    segments: [ShotRenderPlanSegment],
    generatedItems: [ShotSegmentPromptPlanItem],
    skipped: [String],
    strands: [MeaningStrand],
    skippedPlaceholders: [ShotSkippedSegmentPlaceholder]
) {
    shotRenderSegmentPlan(
        shot: shot,
        frameLookup: cutFrameLookup,
        mediaLookup: cutMediaLookup,
        meaningNodes: []
    )
}

private func approx(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.001) -> Bool {
    abs(lhs - rhs) <= tolerance
}

// MARK: Skip heal (entry skips)

@Test func cutLayerSkippedFootageHealsSeamsToCutAndNeverInventsPairs() {
    var clip = ShotFrameEntry(entryId: "e2", clipMediaId: "vid_1")
    clip.isSkipped = true
    let plan = cutPlanOf(cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        clip,
        ShotFrameEntry(entryId: "e3", frameImageId: "f2")
    ]))
    // No footage segment, and the healed frame–frame seam must NOT invent a
    // new f1>f2 pair (that would cost a render — skips are free).
    #expect(plan.segments.isEmpty)
    #expect(plan.generatedItems.isEmpty)
    // Both frames are honestly reported as cut off.
    #expect(plan.skipped.filter { $0.contains("cut off") }.count == 2)
    // The skip is a restorable placeholder, not a not-ready report.
    #expect(plan.skippedPlaceholders.count == 1)
    #expect(plan.skippedPlaceholders[0].restore == .entry(entryId: "e2"))
    #expect(plan.skippedPlaceholders[0].isFootage)
    #expect(approx(plan.skippedPlaceholders[0].footageSeconds, 10))
    #expect(!plan.skipped.contains { $0.contains("vid_1") })
}

@Test func cutLayerSkippedMiddleFrameKeepsNeighborPairKeysIntact() {
    let full = cutPlanOf(cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2"),
        ShotFrameEntry(entryId: "e3", frameImageId: "f3")
    ]))
    #expect(full.generatedItems.map(\.pair.segmentKey) == ["f1>f2", "f2>f3"])

    var middle = ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    middle.isSkipped = true
    let skipped = cutPlanOf(cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        middle,
        ShotFrameEntry(entryId: "e3", frameImageId: "f3")
    ]))
    // The healed seam is a cut: no f1>f3 pair appears.
    #expect(skipped.generatedItems.isEmpty)
    #expect(skipped.skippedPlaceholders.map(\.restore) == [.entry(entryId: "e2")])

    // Restoring reproduces the original pair keys exactly.
    let restored = cutPlanOf(cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2"),
        ShotFrameEntry(entryId: "e3", frameImageId: "f3")
    ]))
    #expect(restored.generatedItems.map(\.pair.segmentKey) == full.generatedItems.map(\.pair.segmentKey))
}

// MARK: Skip via explicit frame–frame seam cut

@Test func cutLayerExplicitFrameFrameCutSkipsThePairAndStaysRestorable() {
    var second = ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    second.leadTransition = "cut"
    let plan = cutPlanOf(cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        second,
        ShotFrameEntry(entryId: "e3", frameImageId: "f3")
    ]))
    // The f1>f2 pair is gone; f2>f3 survives; f1 is honestly orphaned.
    #expect(plan.generatedItems.map(\.pair.segmentKey) == ["f2>f3"])
    #expect(plan.skipped.contains { $0.contains("cut off") })
    // The hidden pair stays visible as a seam-restorable placeholder.
    #expect(plan.skippedPlaceholders.map(\.restore) == [.seam(rightEntryId: "e2")])
    #expect(plan.skippedPlaceholders[0].afterDisplayIndex == -1)
    // Pair segments carry their own skip target (the seam they ride).
    #expect(plan.generatedItems[0].skipTarget == .seam(rightEntryId: "e3"))
}

// MARK: Cut plan math (razor + in/out, material space)

@Test func cutPlanRazorSubtractsInsideOneClipOnly() {
    let cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(segmentKey: "a>b", clipPath: "/tmp/c0.mp4", startSeconds: 3, endSeconds: 5)
    ])
    let plan = shotCutPlan(
        clips: [
            ShotCutPlanClipInput(segmentKey: "a>b", clipPath: "/tmp/c0.mp4", durationSeconds: 8, leadingTrimSeconds: 0),
            ShotCutPlanClipInput(segmentKey: "b>c", clipPath: "/tmp/c1.mp4", durationSeconds: 8, leadingTrimSeconds: 0.125)
        ],
        cutList: cutList
    )
    #expect(plan.clips.count == 2)
    #expect(plan.clips[0].keepRanges == [
        ShotKeepRange(start: 0, end: 3),
        ShotKeepRange(start: 5, end: 8)
    ])
    #expect(plan.clips[1].keepRanges == [ShotKeepRange(start: 0.125, end: 8)])
    #expect(approx(plan.clips[1].materialStartSeconds, 8))
    #expect(approx(plan.clips[1].outputStartSeconds, 6))
    #expect(approx(plan.outputSeconds, 13.875))
    #expect(approx(plan.materialSeconds, 15.875))
}

@Test func cutPlanShotInOutClampOnMaterialTimeline() {
    let cutList = ShotCutList(
        shotInSeconds: 1,
        shotOutSeconds: 14,
        segmentCuts: [
            ShotSegmentCutRange(segmentKey: "a>b", clipPath: "/tmp/c0.mp4", startSeconds: 3, endSeconds: 5)
        ]
    )
    let plan = shotCutPlan(
        clips: [
            ShotCutPlanClipInput(segmentKey: "a>b", clipPath: "/tmp/c0.mp4", durationSeconds: 8, leadingTrimSeconds: 0),
            ShotCutPlanClipInput(segmentKey: "b>c", clipPath: "/tmp/c1.mp4", durationSeconds: 8, leadingTrimSeconds: 0.125)
        ],
        cutList: cutList
    )
    #expect(plan.clips[0].keepRanges == [
        ShotKeepRange(start: 1, end: 3),
        ShotKeepRange(start: 5, end: 8)
    ])
    #expect(plan.clips[1].keepRanges.count == 1)
    #expect(approx(plan.clips[1].keepRanges[0].start, 0.125))
    #expect(approx(plan.clips[1].keepRanges[0].end, 6.125))
    #expect(approx(plan.outputSeconds, 11))
    // Razor dragging never shifts the handles: material length is unchanged.
    #expect(approx(plan.materialSeconds, 15.875))
}

@Test func cutPlanUnrenderedClipOccupiesMaterialButPlaysNothing() {
    let plan = shotCutPlan(
        clips: [
            ShotCutPlanClipInput(segmentKey: "a>b", clipPath: "/tmp/c0.mp4", durationSeconds: 4, leadingTrimSeconds: 0),
            ShotCutPlanClipInput(segmentKey: "b>c", clipPath: "", durationSeconds: 8, leadingTrimSeconds: 0),
            ShotCutPlanClipInput(segmentKey: "c>d", clipPath: "/tmp/c2.mp4", durationSeconds: 4, leadingTrimSeconds: 0)
        ],
        cutList: ShotCutList()
    )
    #expect(plan.clips.count == 3)
    #expect(!plan.clips[1].isPlayable)
    #expect(approx(plan.clips[1].materialSeconds, 8))
    #expect(approx(plan.clips[2].materialStartSeconds, 12))
    #expect(approx(plan.clips[2].outputStartSeconds, 4))
    #expect(approx(plan.outputSeconds, 8))
    #expect(approx(plan.materialSeconds, 16))
}

@Test func cutPlanPinnedRazorOnlyBitesItsOwnTake() {
    let pinnedElsewhere = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(segmentKey: "a>b", clipPath: "/tmp/old_take.mp4", startSeconds: 1, endSeconds: 2)
    ])
    let plan = shotCutPlan(
        clips: [ShotCutPlanClipInput(segmentKey: "a>b", clipPath: "/tmp/new_take.mp4", durationSeconds: 8)],
        cutList: pinnedElsewhere
    )
    #expect(plan.clips[0].keepRanges == [ShotKeepRange(start: 0, end: 8)])

    let unpinned = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(segmentKey: "a>b", clipPath: "", startSeconds: 1, endSeconds: 2)
    ])
    let bitten = shotCutPlan(
        clips: [ShotCutPlanClipInput(segmentKey: "a>b", clipPath: "/tmp/new_take.mp4", durationSeconds: 8)],
        cutList: unpinned
    )
    #expect(bitten.clips[0].keepRanges.count == 2)
}

// MARK: Cut list hygiene

@Test func cutListNormalizeSwapsClampsAndDropsDegenerates() {
    let list = ShotCutList(
        shotInSeconds: 5,
        shotOutSeconds: 5.01,
        segmentCuts: [
            ShotSegmentCutRange(segmentKey: "a>b", startSeconds: 6, endSeconds: 4),
            ShotSegmentCutRange(segmentKey: "a>b", startSeconds: 1, endSeconds: 1.01),
            ShotSegmentCutRange(segmentKey: "", startSeconds: 0, endSeconds: 2)
        ]
    ).normalized()
    // Inverted in/out pair drops entirely.
    #expect(list.shotInSeconds == nil)
    #expect(list.shotOutSeconds == nil)
    // Swapped range survives; degenerate and keyless ranges drop.
    #expect(list.segmentCuts.count == 1)
    #expect(approx(list.segmentCuts[0].startSeconds, 4))
    #expect(approx(list.segmentCuts[0].endSeconds, 6))
}

@Test func cutListPruneKeepsLiveKeysAndDropsDeadOnes() {
    let entries = [
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", clipMediaId: "vid_1")
    ]
    let footageKey = shotFootageKey(mediaId: "vid_1", startSeconds: nil, endSeconds: nil)
    let boundaryIds = shotFootageBoundaryFrameIds(mediaId: "vid_1", startSeconds: nil, endSeconds: nil)
    let list = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(segmentKey: "\(footageKey)>", startSeconds: 1, endSeconds: 2),
        ShotSegmentCutRange(segmentKey: "f1>\(boundaryIds.start)", startSeconds: 1, endSeconds: 2),
        ShotSegmentCutRange(segmentKey: "ghost>f9", startSeconds: 1, endSeconds: 2)
    ]).pruned(entries: entries)
    #expect(list.segmentCuts.count == 2)
    #expect(!list.segmentCuts.contains { $0.segmentKey == "ghost>f9" })
}

// MARK: Runtime summary honesty

@Test func runtimeSummarySubtractsSkipsAndCutLayer() {
    // f1 · clip · f2, fully bridged: 2 bridges + 10s footage @8s segments = 26s.
    let bridgedShot = cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", clipMediaId: "vid_1"),
        ShotFrameEntry(entryId: "e3", frameImageId: "f2")
    ])
    let bridged = shotRuntimeSummary(shot: bridgedShot, frameLookup: cutFrameLookup, mediaLookup: cutMediaLookup)
    #expect(bridged.bridges == 2)
    #expect(bridged.estimatedSeconds(segmentSeconds: 8) == 26)

    // Skip the footage: no clips, healed seams, no bridges at all.
    var skippedClip = ShotFrameEntry(entryId: "e2", clipMediaId: "vid_1")
    skippedClip.isSkipped = true
    let skippedShot = cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        skippedClip,
        ShotFrameEntry(entryId: "e3", frameImageId: "f2")
    ])
    let skipped = shotRuntimeSummary(shot: skippedShot, frameLookup: cutFrameLookup, mediaLookup: cutMediaLookup)
    #expect(skipped.clips == 0)
    #expect(skipped.bridges == 0)
    #expect(approx(skipped.footageSeconds, 0))

    // Razor + in/out subtract from the estimate.
    var cutShotValue = bridgedShot
    cutShotValue.cutList = ShotCutList(
        shotInSeconds: 2,
        segmentCuts: [ShotSegmentCutRange(segmentKey: "x>y", startSeconds: 0, endSeconds: 3)]
    )
    let trimmed = shotRuntimeSummary(shot: cutShotValue, frameLookup: cutFrameLookup, mediaLookup: cutMediaLookup)
    #expect(trimmed.estimatedSeconds(segmentSeconds: 8) == 21)
}

// MARK: Codable tolerance

@Test func cutLayerEntrySkipAndShotCutListRoundTripAndDefault() throws {
    var entry = ShotFrameEntry(entryId: "e1", frameImageId: "f1")
    entry.isSkipped = true
    let decodedEntry = try JSONDecoder().decode(ShotFrameEntry.self, from: JSONEncoder().encode(entry))
    #expect(decodedEntry.isSkipped)

    let legacyEntry = try JSONDecoder().decode(
        ShotFrameEntry.self,
        from: Data(#"{"entryId": "e1", "frameImageId": "f1"}"#.utf8)
    )
    #expect(!legacyEntry.isSkipped)

    var shot = cutShot([entry])
    shot.cutList = ShotCutList(
        shotInSeconds: 1.5,
        segmentCuts: [ShotSegmentCutRange(segmentKey: "f1>", clipPath: "/tmp/x.mp4", startSeconds: 1, endSeconds: 2)]
    )
    let decodedShot = try JSONDecoder().decode(ProjectShot.self, from: JSONEncoder().encode(shot))
    #expect(decodedShot.cutList.shotInSeconds == 1.5)
    #expect(decodedShot.cutList.segmentCuts.count == 1)

    let legacyShot = try JSONDecoder().decode(
        ProjectShot.self,
        from: Data(#"{"shotId": "s1", "entries": []}"#.utf8)
    )
    #expect(legacyShot.cutList.isEmpty)
}

@Test func cutLayerShotMutationsPersistSkipAndPruneCuts() {
    let shot = cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ])
    let skipped = shot.settingEntrySkipped(entryId: "e2", skipped: true, now: "2026-07-17T00:00:00Z")
    #expect(skipped.entries[1].isSkipped)
    let restored = skipped.settingEntrySkipped(entryId: "e2", skipped: false, now: "2026-07-17T00:00:01Z")
    #expect(!restored.entries[1].isSkipped)

    let withCuts = shot.settingCutList(
        ShotCutList(segmentCuts: [
            ShotSegmentCutRange(segmentKey: "f1>f2", startSeconds: 1, endSeconds: 2),
            ShotSegmentCutRange(segmentKey: "gone>away", startSeconds: 1, endSeconds: 2)
        ]),
        now: "2026-07-17T00:00:02Z"
    )
    #expect(withCuts.cutList.segmentCuts.map(\.segmentKey) == ["f1>f2"])
}

// MARK: Assembly (bands ↔ saved clips)

@Test func cutAssemblyResolvesSavedClipsAndRazorRanges() {
    var artifact = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "ready",
        generatedAt: "2026-07-17T00:00:00Z",
        updatedAt: "2026-07-17T00:00:00Z"
    )
    artifact.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: "/tmp/take_one.mp4",
        updatedAt: "2026-07-17T00:00:00Z"
    ))
    var shot = cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ])
    shot = shot.upsertingRenderVersion(artifact, activate: true, now: "2026-07-17T00:00:00Z")
    shot.cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(segmentKey: "f1>f2", clipPath: "/tmp/take_one.mp4", startSeconds: 2, endSeconds: 3)
    ])
    let plan = cutPlanOf(shot)

    let assembly = shotCutAssembly(
        shot: shot,
        planSegments: plan.segments,
        clipDurationsByPath: ["/tmp/take_one.mp4": 7.9],
        fileExists: { _ in true }
    )
    #expect(assembly.bands.count == 1)
    #expect(assembly.bands[0].clipPath == "/tmp/take_one.mp4")
    #expect(assembly.planClips[0].keepRanges == [
        ShotKeepRange(start: 0, end: 2),
        ShotKeepRange(start: 3, end: 7.9)
    ])
    #expect(approx(assembly.outputSeconds, 6.9))
    #expect(assembly.hasPlayableClips)

    // Without a saved clip the band is honest about it: material, no play.
    let bare = shot.upsertingRenderVersion(
        ShotRenderArtifact(versionId: "v2", versionNumber: 2, status: "ready", generatedAt: "1", updatedAt: "1"),
        activate: true,
        now: "2026-07-17T00:00:01Z"
    )
    let bareAssembly = shotCutAssembly(
        shot: bare,
        planSegments: plan.segments,
        clipDurationsByPath: [:],
        fileExists: { _ in true }
    )
    #expect(!bareAssembly.hasPlayableClips)
    #expect(approx(bareAssembly.materialSeconds, Double(bare.renderStack.segmentSeconds)))
}

@Test func cutAssemblyResolvesLastReadyVersionWhileNewOneRenders() {
    // v1: ready with a video file and a saved clip.
    var v1 = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "ready",
        videoPath: "/tmp/v1.mp4",
        generatedAt: "2026-07-27T00:00:00Z",
        updatedAt: "2026-07-27T00:00:00Z"
    )
    v1.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: "/tmp/v1_take.mp4",
        updatedAt: "2026-07-27T00:00:00Z"
    ))
    var shot = cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ])
    shot = shot.upsertingRenderVersion(v1, activate: true, now: "2026-07-27T00:00:00Z")

    // A re-render starts: the generating v2 takes the pointer (as renderShot
    // does) — playback must keep resolving v1's clips.
    let v2 = ShotRenderArtifact(
        versionId: "v2",
        versionNumber: 2,
        status: "generating",
        generatedAt: "2026-07-27T00:01:00Z",
        updatedAt: "2026-07-27T00:01:00Z"
    )
    shot = shot.upsertingRenderVersion(v2, activate: true, now: "2026-07-27T00:01:00Z")
    #expect(shot.activeRenderVersion?.versionId == "v2")

    let plan = cutPlanOf(shot)
    let assembly = shotCutAssembly(
        shot: shot,
        planSegments: plan.segments,
        clipDurationsByPath: ["/tmp/v1_take.mp4": 7.9],
        fileExists: { _ in true }
    )
    #expect(assembly.hasPlayableClips)
    #expect(assembly.bands.first?.clipPath == "/tmp/v1_take.mp4")

    // v2 completes with its own clip and stays active — playback flips to it.
    var readyV2 = v2
    readyV2.status = "ready"
    readyV2.videoPath = "/tmp/v2.mp4"
    readyV2.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: "/tmp/v2_take.mp4",
        updatedAt: "2026-07-27T00:02:00Z"
    ))
    let completed = shot.upsertingRenderVersion(readyV2, activate: true, now: "2026-07-27T00:02:00Z")
    let completedAssembly = shotCutAssembly(
        shot: completed,
        planSegments: cutPlanOf(completed).segments,
        clipDurationsByPath: ["/tmp/v2_take.mp4": 7.9],
        fileExists: { _ in true }
    )
    #expect(completedAssembly.bands.first?.clipPath == "/tmp/v2_take.mp4")
}

// MARK: Suffix appends (watermark tail + missing-keys law)

private func suffixReadyVersion(
    _ versionId: String,
    number: Int,
    renderedEntryIds: [String],
    clips: [ShotRenderSegmentClip] = []
) -> ShotRenderArtifact {
    var artifact = ShotRenderArtifact(
        versionId: versionId,
        versionNumber: number,
        status: "ready",
        videoPath: "/tmp/\(versionId).mp4",
        renderedEntryIds: renderedEntryIds,
        generatedAt: "t",
        updatedAt: "t"
    )
    for clip in clips { artifact.upsertSegmentClip(clip) }
    return artifact
}

@Test func suffixWatermarkDecodesTolerantly() throws {
    let legacy = try JSONDecoder().decode(
        ShotRenderArtifact.self,
        from: Data(#"{"versionId": "v1", "status": "ready", "videoPath": "/tmp/v.mp4"}"#.utf8)
    )
    #expect(legacy.renderedEntryIds.isEmpty)

    let decoded = try JSONDecoder().decode(
        ShotRenderArtifact.self,
        from: JSONEncoder().encode(suffixReadyVersion("v2", number: 2, renderedEntryIds: ["e1", "e2"]))
    )
    #expect(decoded.renderedEntryIds == ["e1", "e2"])
}

@Test func suffixTailStartIndexLaw() {
    let rendered = [
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ]
    // No version → nil (the cut is not even locked).
    #expect(shotSuffixTailStartIndex(shot: cutShot(rendered)) == nil)

    // Legacy watermark-less ready version → nil: full freeze stands.
    var legacy = cutShot(rendered)
    legacy = legacy.upsertingRenderVersion(suffixReadyVersion("v0", number: 1, renderedEntryIds: []), activate: true, now: "t")
    #expect(shotSuffixTailStartIndex(shot: legacy) == nil)

    // Generating active version → nil even with a watermark.
    var generating = cutShot(rendered)
    var inFlight = suffixReadyVersion("v1", number: 1, renderedEntryIds: ["e1", "e2"])
    inFlight.status = "generating"
    inFlight.videoPath = ""
    generating = generating.upsertingRenderVersion(inFlight, activate: true, now: "t")
    #expect(shotSuffixTailStartIndex(shot: generating) == nil)

    // Watermarked ready version: tail opens after the last rendered entry.
    var appended = cutShot(rendered + [ShotFrameEntry(entryId: "e3", frameImageId: "f3")])
    appended = appended.upsertingRenderVersion(
        suffixReadyVersion("v1", number: 1, renderedEntryIds: ["e1", "e2"]),
        activate: true,
        now: "t"
    )
    #expect(shotSuffixTailStartIndex(shot: appended) == 2)

    // Appending a DUPLICATE of a rendered frame stays in the tail — the
    // watermark is entryId-based, not key-based.
    var duplicated = cutShot(rendered + [ShotFrameEntry(entryId: "e3", frameImageId: "f1")])
    duplicated = duplicated.upsertingRenderVersion(
        suffixReadyVersion("v1", number: 1, renderedEntryIds: ["e1", "e2"]),
        activate: true,
        now: "t"
    )
    #expect(shotSuffixTailStartIndex(shot: duplicated) == 2)

    // No watermarked entry survives in the strip → everything is tail.
    var replaced = cutShot([ShotFrameEntry(entryId: "e9", frameImageId: "f1")])
    replaced = replaced.upsertingRenderVersion(
        suffixReadyVersion("v1", number: 1, renderedEntryIds: ["e1", "e2"]),
        activate: true,
        now: "t"
    )
    #expect(shotSuffixTailStartIndex(shot: replaced) == 0)
}

@Test func suffixRenderPlanMissingKeysForAppendedPair() {
    var shot = cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2"),
        ShotFrameEntry(entryId: "e3", frameImageId: "f3")
    ])
    shot = shot.upsertingRenderVersion(
        suffixReadyVersion(
            "v1",
            number: 1,
            renderedEntryIds: ["e1", "e2"],
            clips: [ShotRenderSegmentClip(startFrameImageId: "f1", endFrameImageId: "f2", clipPath: "/tmp/f1f2.mp4")]
        ),
        activate: true,
        now: "t"
    )
    let plan = cutPlanOf(shot)
    let suffix = shotSuffixRenderPlan(
        shot: shot,
        segments: plan.segments,
        generatedItems: plan.generatedItems,
        fileExists: { _ in true }
    )
    #expect(suffix.missingKeys == ["entry:e2>e3"])
    #expect(suffix.reusableSegmentCount == 1)
    #expect(suffix.missingGeneratedItems.map(\.pair.segmentKey) == ["f2>f3"])

    // A saved record whose file is gone counts as missing — never reused.
    let goneSuffix = shotSuffixRenderPlan(
        shot: shot,
        segments: plan.segments,
        generatedItems: plan.generatedItems,
        fileExists: { _ in false }
    )
    #expect(goneSuffix.missingKeys == ["entry:e2>e3", "entry:e1>e2"])
    #expect(goneSuffix.reusableSegmentCount == 0)
}

@Test func suffixRenderPlanUsesPlacementKeysAndFindsSkipHoles() {
    // Footage suffix: missing keys use placement identity so repeated use of
    // the same media remains independently addressable by render controls.
    var footageShot = cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "c1", clipMediaId: "vid_1")
    ])
    footageShot = footageShot.upsertingRenderVersion(
        suffixReadyVersion("v1", number: 1, renderedEntryIds: ["e1"]),
        activate: true,
        now: "t"
    )
    let footagePlan = cutPlanOf(footageShot)
    let footageSuffix = shotSuffixRenderPlan(
        shot: footageShot,
        segments: footagePlan.segments,
        generatedItems: footagePlan.generatedItems,
        fileExists: { _ in true }
    )
    #expect(footageSuffix.missingKeys == ["entry:e1>c1", "entry:c1>"])

    // A skipped middle entry heals its seams to hard CUTS — the plan emits
    // no pair across the gap, so a skip creates NOTHING new to render (and
    // the old pair clips stop matching the live plan, so nothing is
    // "reusable" either — restoring the entry brings both back).
    var skipShot = cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2", isSkipped: true),
        ShotFrameEntry(entryId: "e3", frameImageId: "f3")
    ])
    skipShot = skipShot.upsertingRenderVersion(
        suffixReadyVersion(
            "v1",
            number: 1,
            renderedEntryIds: ["e1", "e2", "e3"],
            clips: [
                ShotRenderSegmentClip(startFrameImageId: "f1", endFrameImageId: "f2", clipPath: "/tmp/a.mp4"),
                ShotRenderSegmentClip(startFrameImageId: "f2", endFrameImageId: "f3", clipPath: "/tmp/b.mp4")
            ]
        ),
        activate: true,
        now: "t"
    )
    let skipPlan = cutPlanOf(skipShot)
    let skipSuffix = shotSuffixRenderPlan(
        shot: skipShot,
        segments: skipPlan.segments,
        generatedItems: skipPlan.generatedItems,
        fileExists: { _ in true }
    )
    #expect(skipSuffix.missingKeys.isEmpty)
    #expect(skipSuffix.reusableSegmentCount == 0)
    #expect(!skipSuffix.hasNewMaterial)
}

@Test func railLabelAppendsUnrenderedMarker() {
    var summary = ShotRuntimeSummary()
    summary.frames = 3
    summary.bridges = 2
    #expect(!summary.railLabel(generatedSeconds: 8).contains("UNRENDERED"))
    #expect(summary.railLabel(generatedSeconds: 8, unrenderedCount: 2).hasSuffix("+2 UNRENDERED"))
}

// MARK: Collect Frame (output time → source file mapping)

@Test func sourceCaptureMapsOutputTimeIntoSourceFiles() {
    var v1 = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "ready",
        videoPath: "/tmp/v1.mp4",
        generatedAt: "t",
        updatedAt: "t"
    )
    v1.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: "/tmp/take.mp4",
        updatedAt: "t"
    ))
    var shot = cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ])
    shot = shot.upsertingRenderVersion(v1, activate: true, now: "t")
    // Razor 2–3s out of the 7.9s clip: keep [0,2] then [3,7.9].
    shot.cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(segmentKey: "f1>f2", clipPath: "/tmp/take.mp4", startSeconds: 2, endSeconds: 3)
    ])
    let plan = cutPlanOf(shot)
    let assembly = shotCutAssembly(
        shot: shot,
        planSegments: plan.segments,
        clipDurationsByPath: ["/tmp/take.mp4": 7.9],
        fileExists: { _ in true }
    )

    // Inside the first keep range: identity.
    let early = assembly.sourceCapture(forOutputSeconds: 1.0)
    #expect(early?.url.path == "/tmp/take.mp4")
    #expect(abs((early?.fileSeconds ?? -1) - 1.0) < 0.05)

    // After the razor: output 3.0 lands in the SECOND keep range, whose
    // clip-local head is 3.0 — the cut-out span never appears.
    let afterRazor = assembly.sourceCapture(forOutputSeconds: 3.0)
    #expect(afterRazor?.url.path == "/tmp/take.mp4")
    #expect((afterRazor?.fileSeconds ?? 0) >= 3.0 - 0.05)

    // Beyond the end: clamps into the final item, never past its duration.
    let clamped = assembly.sourceCapture(forOutputSeconds: 999)
    #expect(clamped != nil)
    if let clamped, let last = assembly.playbackItems.last {
        #expect(clamped.fileSeconds <= (last.keepRange?.end ?? 999))
    }
}

// MARK: Reference markers (inert-by-law)

@Test func markersDecodeTolerantlyAndStayOutOfIsEmpty() throws {
    // Legacy cut lists carry no markers key at all.
    let legacy = try JSONDecoder().decode(
        ShotCutList.self,
        from: Data(#"{"segmentCuts": []}"#.utf8)
    )
    #expect(legacy.markers.isEmpty)

    // Round trip keeps them.
    let list = ShotCutList(markers: [
        ShotStripMarker(markerId: "m1", materialSeconds: 2.5, updatedAt: "t")
    ])
    let decoded = try JSONDecoder().decode(ShotCutList.self, from: JSONEncoder().encode(list))
    #expect(decoded.markers.map(\.id) == ["m1"])
    #expect(decoded.markers.first?.materialSeconds == 2.5)

    // THE INERT LAW's model half: a marker-only list still reads as "no cut
    // edits" — markers must never flip export naming or has-edits checks.
    #expect(list.isEmpty)
    #expect(list.normalized().isEmpty)
}

@Test func markersNormalizeClampSortAndDedupe() {
    let list = ShotCutList(markers: [
        ShotStripMarker(markerId: "late", materialSeconds: 6, updatedAt: "t"),
        ShotStripMarker(markerId: "negative", materialSeconds: -1, updatedAt: "t"),
        ShotStripMarker(markerId: "late", materialSeconds: 6, updatedAt: "t"),
        ShotStripMarker(markerId: "early", materialSeconds: 1.5, updatedAt: "t")
    ]).normalized()
    #expect(list.markers.map(\.id) == ["negative", "early", "late"])
    #expect(list.markers.first?.materialSeconds == 0)

    // A blank id mints one, so removal always has a stable handle.
    let minted = ShotStripMarker(materialSeconds: 3)
    #expect(!minted.markerId.isEmpty)
}

@Test func markersSurviveEntryPruning() {
    // Razors keyed to vanished segments prune; markers are material-space
    // reference pins with no segment identity, so pruning never eats them.
    let list = ShotCutList(
        segmentCuts: [
            ShotSegmentCutRange(segmentKey: "f1>f2", startSeconds: 1, endSeconds: 2)
        ],
        markers: [ShotStripMarker(markerId: "m1", materialSeconds: 4, updatedAt: "t")]
    ).pruned(entries: [])
    #expect(list.segmentCuts.isEmpty)
    #expect(list.markers.map(\.id) == ["m1"])
}

@Test func markerToggleLawFindsOnlyNearbyMarkers() {
    let list = ShotCutList(markers: [
        ShotStripMarker(markerId: "a", materialSeconds: 2, updatedAt: "t"),
        ShotStripMarker(markerId: "b", materialSeconds: 5, updatedAt: "t")
    ])
    // Within tolerance → the nearest marker lifts.
    #expect(shotMarkerAtPlayhead(cutList: list, playheadMaterialSeconds: 2.05)?.id == "a")
    #expect(shotMarkerAtPlayhead(cutList: list, playheadMaterialSeconds: 4.95)?.id == "b")
    // Clear of every marker → Mark drops a new one.
    #expect(shotMarkerAtPlayhead(cutList: list, playheadMaterialSeconds: 3.5) == nil)
    #expect(shotMarkerAtPlayhead(cutList: ShotCutList(), playheadMaterialSeconds: 0) == nil)
}

@Test func markerEditsNameTheirUndoActions() {
    let before = ShotCutList()
    let added = ShotCutList(markers: [ShotStripMarker(markerId: "m1", materialSeconds: 2, updatedAt: "t")])
    #expect(shotCutListEditActionName(before: before, after: added) == "Add Marker")
    #expect(shotCutListEditActionName(before: added, after: before) == "Remove Marker")

    // A razor landing in the same commit still names the razor — markers are
    // the quietest edit in the funnel.
    var razored = added
    razored.segmentCuts = [ShotSegmentCutRange(segmentKey: "f1>f2", startSeconds: 1, endSeconds: 2)]
    #expect(shotCutListEditActionName(before: before, after: razored) == "Razor Cut")
}

// MARK: Strip snap targets — audio landmarks across the seam

@Test func stripSnapTargetsCarryAudioLandmarksPulledBackThroughTheCut() {
    // The screenshot failure: "cut where the audio ends" needs a MATERIAL
    // magnet for an OUTPUT-space audio edge. A razor [2,3] on a 7.9s clip
    // makes material and output diverge by exactly 1s past the cut — the
    // landmark must ride the projection, not the eyeball.
    var artifact = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "ready",
        generatedAt: "2026-07-17T00:00:00Z",
        updatedAt: "2026-07-17T00:00:00Z"
    )
    artifact.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: "/tmp/take_one.mp4",
        updatedAt: "2026-07-17T00:00:00Z"
    ))
    var shot = cutShot([
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ])
    shot = shot.upsertingRenderVersion(artifact, activate: true, now: "2026-07-17T00:00:00Z")
    shot.cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(segmentKey: "f1>f2", clipPath: "/tmp/take_one.mp4", startSeconds: 2, endSeconds: 3)
    ])
    let plan = cutPlanOf(shot)
    let assembly = shotCutAssembly(
        shot: shot,
        planSegments: plan.segments,
        clipDurationsByPath: ["/tmp/take_one.mp4": 7.9],
        fileExists: { _ in true }
    )

    // An audio edge at OUTPUT 5.0 sits past the razor: material = 6.0.
    let landmarkMaterial = assembly.materialSeconds(forOutputSeconds: 5.0)
    #expect(approx(landmarkMaterial, 6.0))

    let targets = shotStripSnapTargets(
        assembly: assembly,
        cutList: shot.cutList,
        playheadMaterialSeconds: 0,
        audioLandmarkMaterialSeconds: [landmarkMaterial]
    )
    #expect(targets.contains { approx($0, 6.0) })

    // Without landmarks the target list is unchanged from the old law.
    let bare = shotStripSnapTargets(
        assembly: assembly,
        cutList: shot.cutList,
        playheadMaterialSeconds: 0
    )
    #expect(!bare.contains { approx($0, 6.0) })
    #expect(targets.count == bare.count + 1)
}
