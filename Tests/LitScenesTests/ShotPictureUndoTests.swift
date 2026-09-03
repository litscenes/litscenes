import Foundation
import Testing
@testable import LitScenes

// THE PICTURE SNAPSHOT LAW's firewall: razor→restore is an identity, seam
// restore never eats a boundary, razor blocks restore as one, shed keys and
// pin sweeps follow their laws, and snapshot restore round-trips everything
// a picture edit can touch — including the audio a razor restore ripples.

private func pictureShot(
    entries: [ShotFrameEntry],
    boundaries: [ShotSourceBoundary] = [],
    cutList: ShotCutList = ShotCutList(),
    audioRegions: [ShotAudioRegion] = []
) -> ProjectShot {
    var shot = ProjectShot(shotId: "shot_pic", name: "Picture undo", entries: entries)
    shot.sourceBoundaries = boundaries
    shot = shot.settingCutList(cutList, now: "t0")
    if !audioRegions.isEmpty {
        shot = shot.settingAudioRegions(audioRegions, now: "t0")
    }
    return shot
}

private func planOutputSeconds(_ cutList: ShotCutList) -> Double {
    shotCutPlan(
        clips: [
            ShotCutPlanClipInput(segmentKey: "a>b", clipPath: "/tmp/c0.mp4", durationSeconds: 8, leadingTrimSeconds: 0),
            ShotCutPlanClipInput(segmentKey: "b>c", clipPath: "/tmp/c1.mp4", durationSeconds: 8, leadingTrimSeconds: 0)
        ],
        cutList: cutList
    ).outputSeconds
}

// MARK: Razor → restore round trip (the missing regression pin)

@Test func razorRestoreRoundTripIsIdentity() {
    let clean = ShotCutList()
    let cleanSeconds = planOutputSeconds(clean)

    var razored = clean
    razored.segmentCuts.append(ShotSegmentCutRange(
        segmentKey: "a>b", clipPath: "/tmp/c0.mp4", startSeconds: 3, endSeconds: 5
    ))
    let razoredNormalized = razored.normalized()
    #expect(planOutputSeconds(razoredNormalized) < cleanSeconds - 1.9)

    // Restore = remove the whole block containing the razor.
    let block = shotRazorCutIdsInSameBlock(
        cutList: razoredNormalized,
        cutId: razoredNormalized.segmentCuts[0].id
    )
    var restored = razoredNormalized
    restored.segmentCuts.removeAll { block.contains($0.id) }
    #expect(restored.normalized() == clean.normalized())
    #expect(planOutputSeconds(restored.normalized()) == cleanSeconds)
}

@Test func bladeCutThenSnapshotRestoreRoundTrips() {
    let shot = pictureShot(
        entries: [
            ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
            ShotFrameEntry(entryId: "e2", frameImageId: "f2")
        ],
        audioRegions: [ShotAudioRegion(
            regionId: "r1", laneId: "clip", path: "/tmp/a.mp3", startSeconds: 1, durationSeconds: 2
        )]
    )
    let before = shot.pictureStateSnapshot()

    var list = shot.cutList
    list.segmentCuts.append(ShotSegmentCutRange(
        segmentKey: "f1>f2", clipPath: "/tmp/take.mp4", startSeconds: 1, endSeconds: 2
    ))
    let razored = shot.settingCutList(list, now: "t1")
    #expect(razored.pictureStateSnapshot() != before)

    let restored = razored.restoringPictureState(before, now: "t2")
    #expect(restored.pictureStateSnapshot() == before)
}

// MARK: THE SEAM BOUNDARY LAW

private func boundaryShot() -> ProjectShot {
    pictureShot(
        entries: [
            ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
            ShotFrameEntry(entryId: "e2", frameImageId: "f2")
        ],
        boundaries: [ShotSourceBoundary(
            boundaryId: "b1",
            leftSourceCutId: "cutA",
            rightSourceCutId: "cutB",
            rightEntryId: "e2",
            createdAt: "t0"
        )]
    )
}

@Test func skipRestoreRoundTripPreservesBoundary() {
    let shot = boundaryShot()
    // Seam skip: explicit hard cut (never touches boundaries by construction).
    let skipped = shot.settingSeamStyle(entryId: "e2", style: .cut, intent: .explicit, now: "t1")
    #expect(skipped.sourceBoundaries.count == 1)
    // Restore returns what skip hid — the boundary row survives.
    let restored = skipped.settingSeamStyle(entryId: "e2", style: .bridge, intent: .restoreSkipped, now: "t2")
    #expect(restored.sourceBoundaries == shot.sourceBoundaries)
    #expect(restored.entries.first { $0.entryId == "e2" }?.leadTransition == "bridge")
}

@Test func explicitBridgeRemovesBoundaryAndSnapshotRestoresIt() {
    let shot = boundaryShot()
    let before = shot.pictureStateSnapshot()
    // The operator's explicit ≈ toggle: the rendered bridge re-establishes
    // pixel continuity, so the boundary row honestly goes.
    let bridged = shot.settingSeamStyle(entryId: "e2", style: .bridge, intent: .explicit, now: "t1")
    #expect(bridged.sourceBoundaries.isEmpty)
    // But the deletion rides an undoable edit: the snapshot puts it back.
    let restored = bridged.restoringPictureState(before, now: "t2")
    #expect(restored.pictureStateSnapshot() == before)
    #expect(restored.sourceBoundaries.count == 1)
}

@Test func restoreSkippedSeamNeverTouchesBoundaries() {
    let shot = boundaryShot()
    for style in [ShotSeamStyle.bridge, .cut, .auto] {
        let restored = shot.settingSeamStyle(entryId: "e2", style: style, intent: .restoreSkipped, now: "t1")
        #expect(restored.sourceBoundaries == shot.sourceBoundaries)
    }
}

// MARK: THE RAZOR BLOCK LAW

@Test func overlappingRazorBlockRestoresAsOne() {
    let list = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(cutId: "c1", segmentKey: "a>b", startSeconds: 1, endSeconds: 3),
        ShotSegmentCutRange(cutId: "c2", segmentKey: "a>b", startSeconds: 2, endSeconds: 5),
        ShotSegmentCutRange(cutId: "c3", segmentKey: "a>b", startSeconds: 4.99, endSeconds: 6),
        ShotSegmentCutRange(cutId: "c4", segmentKey: "a>b", startSeconds: 8, endSeconds: 9)
    ]).normalized()
    let block = shotRazorCutIdsInSameBlock(cutList: list, cutId: "c2")
    #expect(block == ["c1", "c2", "c3"])
    // The disjoint cut is its own block.
    #expect(shotRazorCutIdsInSameBlock(cutList: list, cutId: "c4") == ["c4"])
    // Unknown ids answer empty, not a guess.
    #expect(shotRazorCutIdsInSameBlock(cutList: list, cutId: "nope").isEmpty)
}

@Test func abuttingAndCrossSegmentBlockEdges() {
    let list = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(cutId: "c1", segmentKey: "a>b", clipPath: "", startSeconds: 1, endSeconds: 3),
        ShotSegmentCutRange(cutId: "c2", segmentKey: "a>b", clipPath: "/tmp/take.mp4", startSeconds: 3, endSeconds: 5),
        ShotSegmentCutRange(cutId: "c3", segmentKey: "b>c", clipPath: "", startSeconds: 1, endSeconds: 3),
        ShotSegmentCutRange(cutId: "c4", segmentKey: "a>b", clipPath: "/tmp/other.mp4", startSeconds: 4.5, endSeconds: 7)
    ]).normalized()
    // Exact abutment joins; "" pin matches any pin.
    let block = shotRazorCutIdsInSameBlock(cutList: list, cutId: "c1")
    #expect(block.contains("c1"))
    #expect(block.contains("c2"))
    // Another segment never joins, whatever the range.
    #expect(!block.contains("c3"))
    // Two different non-empty pins are different takes: c4 ("other") joins
    // via c1's "" pin — but from c2's perspective ("take"), c4 is
    // incompatible. The block is seeded by the CLICKED cut.
    let fromC2 = shotRazorCutIdsInSameBlock(cutList: list, cutId: "c2")
    #expect(!fromC2.contains("c3"))
}

// MARK: Shed keys + pin sweep laws

@Test func clipRangeChangeShedsModernPlacementRazors() {
    var entry = ShotFrameEntry(entryId: "e1", clipMediaId: "vid_1")
    entry.clipStartSeconds = 1
    entry.clipEndSeconds = 6
    let keys = shotClipRangeShedKeys(entry: entry)
    let footageKey = shotFootageKey(mediaId: "vid_1", startSeconds: 1, endSeconds: 6)
    #expect(keys.contains("\(footageKey)>"))
    #expect(keys.contains("entry:e1>"))

    // Applying the shed law removes both key forms and spares other entries.
    let list = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(cutId: "legacy", segmentKey: "\(footageKey)>", startSeconds: 1, endSeconds: 2),
        ShotSegmentCutRange(cutId: "modern", segmentKey: "entry:e1>", startSeconds: 2, endSeconds: 3),
        ShotSegmentCutRange(cutId: "other", segmentKey: "entry:e2>", startSeconds: 1, endSeconds: 2)
    ])
    let survivors = list.segmentCuts.filter { !keys.contains($0.segmentKey) }
    #expect(survivors.map(\.cutId) == ["other"])

    // A frame entry sheds nothing (no clip range to change).
    #expect(shotClipRangeShedKeys(entry: ShotFrameEntry(entryId: "e9", frameImageId: "f1")).isEmpty)
}

@Test func stalePinSweepSparesRetainedTakes() {
    var shot = pictureShot(
        entries: [
            ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
            ShotFrameEntry(entryId: "e2", frameImageId: "f2")
        ],
        cutList: ShotCutList(segmentCuts: [
            ShotSegmentCutRange(cutId: "pin_old", segmentKey: "f1>f2", clipPath: "/tmp/old.mp4", startSeconds: 1, endSeconds: 2),
            ShotSegmentCutRange(cutId: "pin_seed", segmentKey: "f1>f2", clipPath: "/tmp/seed.mp4", startSeconds: 3, endSeconds: 4),
            ShotSegmentCutRange(cutId: "pin_gone", segmentKey: "f1>f2", clipPath: "/tmp/gone.mp4", startSeconds: 5, endSeconds: 6),
            ShotSegmentCutRange(cutId: "footage", segmentKey: "entry:e1>", clipPath: "", startSeconds: 1, endSeconds: 2)
        ])
    )
    var oldVersion = ShotRenderArtifact()
    oldVersion.versionId = "v_old"
    var oldClip = ShotRenderSegmentClip()
    oldClip.clipPath = "/tmp/old.mp4"
    oldVersion.segmentClips = [oldClip]
    var seedClip = ShotRenderSegmentClip()
    seedClip.clipPath = "/tmp/seed.mp4"
    shot.renderVersions = [oldVersion]
    shot.seedSegmentClips = [seedClip]

    // Only the pin whose file no retained take carries is stale; unpinned
    // footage razors are never stale here.
    #expect(shotStalePinnedCutIds(shot: shot) == ["pin_gone"])
}

// MARK: Snapshot round trips

@Test func razorRestoreRipplesAudioBackSymmetrically() {
    let shot = pictureShot(
        entries: [ShotFrameEntry(entryId: "e1", frameImageId: "f1")],
        audioRegions: [
            ShotAudioRegion(regionId: "r1", laneId: "clip", path: "/tmp/a.mp3", startSeconds: 5, durationSeconds: 2),
            ShotAudioRegion(regionId: "r2", laneId: "narration", path: "/tmp/n.m4a", startSeconds: 0.5, durationSeconds: 1)
        ]
    )
    let before = shot.pictureStateSnapshot()

    // The razor-restore ripple: everything at/after the removed bridge moves
    // earlier — the compound half a picture undo must reverse.
    let rippled = shot
        .settingAudioMix(shot.audioMix.ripplingPlacements(atOrAfter: 2, by: -1.5), now: "t1")
        .ripplingAudioRegions(atOrAfter: 2, by: -1.5, now: "t1")
    #expect(rippled.pictureStateSnapshot() != before)
    #expect(rippled.audioRegions.first { $0.regionId == "r1" }?.startSeconds == 3.5)

    let restored = rippled.restoringPictureState(before, now: "t2")
    #expect(restored.pictureStateSnapshot() == before)
    #expect(restored.audioRegions.first { $0.regionId == "r1" }?.startSeconds == 5)
}

@Test func pictureSnapshotEqualityDetectsNoOp() {
    let shot = pictureShot(
        entries: [ShotFrameEntry(entryId: "e1", frameImageId: "f1")],
        cutList: ShotCutList(segmentCuts: [
            ShotSegmentCutRange(segmentKey: "f1>f2", startSeconds: 1, endSeconds: 2)
        ])
    )
    let snapshot = shot.pictureStateSnapshot()
    let restored = shot.restoringPictureState(snapshot, now: "t9")
    #expect(restored.pictureStateSnapshot() == snapshot)
}

@Test func reverseToggleRoundTripsThroughSnapshot() {
    let shot = pictureShot(entries: [ShotFrameEntry(entryId: "e1", frameImageId: "f1")])
    let before = shot.pictureStateSnapshot()
    #expect(!before.cutList.isReversed)

    var list = shot.cutList
    list.isReversed = true
    let reversed = shot.settingCutList(list, now: "t1")
    #expect(reversed.pictureStateSnapshot().cutList.isReversed)

    let restored = reversed.restoringPictureState(before, now: "t2")
    #expect(restored.pictureStateSnapshot() == before)
    #expect(!restored.cutList.isReversed)
}

// MARK: Action-name diff law

@Test func cutListEditActionNameDiffLaw() {
    let base = ShotCutList()
    var razored = base
    razored.segmentCuts.append(ShotSegmentCutRange(cutId: "c1", segmentKey: "a>b", startSeconds: 1, endSeconds: 2))
    #expect(shotCutListEditActionName(before: base, after: razored) == "Razor Cut")
    #expect(shotCutListEditActionName(before: razored, after: base) == "Restore Razor Cut")

    var adjusted = razored
    adjusted.segmentCuts[0].endSeconds = 3
    #expect(shotCutListEditActionName(before: razored, after: adjusted) == "Adjust Razor Timing")

    var trimmedIn = base
    trimmedIn.shotInSeconds = 1
    #expect(shotCutListEditActionName(before: base, after: trimmedIn) == "Trim Shot IN")
    #expect(shotCutListEditActionName(before: trimmedIn, after: base) == "Clear Shot IN")

    var trimmedOut = base
    trimmedOut.shotOutSeconds = 5
    #expect(shotCutListEditActionName(before: base, after: trimmedOut) == "Trim Shot OUT")
    #expect(shotCutListEditActionName(before: trimmedOut, after: base) == "Clear Shot OUT")

    var reversed = base
    reversed.isReversed = true
    #expect(shotCutListEditActionName(before: base, after: reversed) == "Reverse CUT")
    #expect(shotCutListEditActionName(before: reversed, after: base) == "Play CUT Forward")
}
