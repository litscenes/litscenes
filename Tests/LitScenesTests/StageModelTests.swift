import Foundation
import Testing
@testable import LitScenes

private func timelineWith(_ shots: [ProjectShot]) -> ProjectShotTimelineDocument {
    var timeline = ProjectShotTimelineDocument.empty(projectId: "p1")
    timeline.shots = shots
    return timeline
}

private func shot(_ shotId: String, name: String = "", frameIds: [String] = [], clipIds: [String] = []) -> ProjectShot {
    var value = ProjectShot(shotId: shotId, name: name, createdAt: "t0", updatedAt: "t0")
    for (index, frameId) in frameIds.enumerated() {
        value.entries.append(ShotFrameEntry(entryId: "\(shotId)_f\(index)", frameImageId: frameId))
    }
    for (index, clipId) in clipIds.enumerated() {
        value.entries.append(ShotFrameEntry(entryId: "\(shotId)_c\(index)", clipMediaId: clipId))
    }
    return value
}

@Test func stageSetDocumentRoundTripAndTolerantDecode() throws {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (appended, stageId) = document.appendingStage(name: "Opening", now: "t1")
    document = appended
        .addingInput(stageId: stageId, frameImageId: "f1", now: "t1")
        .addingInput(stageId: stageId, clipMediaId: "m1", now: "t1")
    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(ProjectStageSetDocument.self, from: data)
    #expect(decoded == document)

    // A future/partial blob missing fields still decodes.
    let sparse = """
    {"projectId": "p1", "stages": [{"stageId": "s1", "cutIds": ["cut1"]}]}
    """
    let old = try JSONDecoder().decode(ProjectStageSetDocument.self, from: Data(sparse.utf8))
    #expect(old.stages.count == 1)
    #expect(old.stages[0].cutIds == ["cut1"])
    #expect(old.finals.isEmpty)
    #expect(old.schemaVersion == ProjectStageSetDocument.schemaVersion)
}

@Test func normalizedDedupesStagesByIdFirstRowWins() {
    // Reconcile appends adopted stages; if any path ever minted a colliding
    // stageId, two same-id rows would collide in ForEach and updatingStage
    // would reach only the first — normalize keeps the first and drops the
    // rest, and their cuts fall to the surviving claim law.
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    document = withA.attachingCut(cutId: "cut1", toStage: stageA, now: "t1")
    var twin = ProjectStage(stageId: stageA, name: "A-twin", createdAt: "t2", updatedAt: "t2")
    twin.cutIds = ["cut2"]
    document.stages.append(twin)

    let normalized = document.normalized()
    #expect(normalized.stages.count == 1)
    #expect(normalized.stages[0].name == "A")
    #expect(normalized.stages[0].cutIds == ["cut1"])
}

@Test func stageSetHostileDecodeThrowsRatherThanSilentlyEmptying() {
    // Tolerant decode covers MISSING and NULL fields; a present-but-wrong-
    // typed value must throw. The store maps that throw to .unreadable and
    // the engine refuses to seed + persist over the stored bytes — a corrupt
    // byte must never silently rebuild the operator's stage organization.
    let hostile = """
    {"projectId": "p1", "stages": [{"stageId": "s1", "name": 3, "cutIds": {}}]}
    """
    #expect(throws: (any Error).self) {
        _ = try JSONCoding.decoder.decode(ProjectStageSetDocument.self, from: Data(hostile.utf8))
    }
}

@Test func normalizedDedupesInputsAndEnforcesSingleCutMembership() {
    var stageA = ProjectStage(stageId: "sA", name: "A", createdAt: "t0", updatedAt: "t0")
    stageA.inputs = [
        StageInput(inputId: "i1", frameImageId: "f1"),
        StageInput(inputId: "i2", frameImageId: "f1"), // duplicate asset
        StageInput(inputId: "", frameImageId: "f2"),   // empty row id
        StageInput(inputId: "i3")                       // references nothing
    ]
    stageA.cutIds = ["cut1", "cut1", "cut2"]
    var stageB = ProjectStage(stageId: "sB", name: "B", createdAt: "t0", updatedAt: "t0")
    stageB.cutIds = ["cut2", "cut3"] // cut2 already claimed by A

    var document = ProjectStageSetDocument.empty(projectId: "p1")
    document.stages = [stageA, stageB]
    document.finals = [
        StageFinalsEntry(entryId: "fin1", cutId: "cut1"),
        StageFinalsEntry(entryId: "fin2", cutId: "cut1"), // duplicate cut
        StageFinalsEntry(entryId: "", cutId: "cut3")      // empty row id
    ]

    let normalized = document.normalized()
    #expect(normalized.stages[0].inputs.map(\.inputId) == ["i1"])
    #expect(normalized.stages[0].cutIds == ["cut1", "cut2"])
    #expect(normalized.stages[1].cutIds == ["cut3"])
    #expect(normalized.finals.map(\.entryId) == ["fin1"])
}

@Test func addingInputIsAFriendlyNoOpForHeldAssets() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (appended, stageId) = document.appendingStage(name: "", now: "t1")
    document = appended.addingInput(stageId: stageId, frameImageId: "f1", now: "t1")
    let again = document.addingInput(stageId: stageId, frameImageId: "f1", now: "t2")
    #expect(again == document)
    #expect(document.stage(withId: stageId)?.inputs.count == 1)

    let neither = document.addingInput(stageId: stageId, now: "t3")
    #expect(neither == document)
}

@Test func removingAndMovingInputsPreserveIdentity() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    let (withB, stageB) = withA.appendingStage(name: "B", now: "t1")
    document = withB
        .addingInput(stageId: stageA, frameImageId: "f1", now: "t1")
        .addingInput(stageId: stageA, clipMediaId: "m1", now: "t1")
    let inputId = document.stage(withId: stageA)!.inputs[0].inputId

    let moved = document.movingInput(inputId: inputId, toStage: stageB, now: "t2")
    #expect(moved.stage(withId: stageA)?.inputs.count == 1)
    #expect(moved.stage(withId: stageB)?.containsAsset(frameImageId: "f1") == true)

    let removed = moved.removingInput(stageId: stageB, inputId: moved.stage(withId: stageB)!.inputs[0].inputId, now: "t3")
    #expect(removed.stage(withId: stageB)?.inputs.isEmpty == true)

    // Moving to a vanished stage is a no-op.
    #expect(document.movingInput(inputId: inputId, toStage: "ghost", now: "t2") == document)
}

@Test func attachingCutClaimsAndReleasesOwnership() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    let (withB, stageB) = withA.appendingStage(name: "B", now: "t1")
    document = withB.attachingCut(cutId: "cut1", toStage: stageA, now: "t1")
    document = document.addingFinal(cutId: "cut1", now: "t1")
    #expect(document.stage(containingCut: "cut1")?.stageId == stageA)
    #expect(document.finals.count == 1)

    // Re-homing the cut releases it from A — and its finals pick drops with
    // the detach (the shelf only holds cuts that live somewhere).
    let rehomed = document.attachingCut(cutId: "cut1", toStage: stageB, now: "t2")
    #expect(rehomed.stage(containingCut: "cut1")?.stageId == stageB)
    #expect(rehomed.stage(withId: stageA)?.cutIds.isEmpty == true)
    #expect(rehomed.finals.isEmpty)
}

@Test func deletingStageReportsItsCutsAndPrunesFinals() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    document = withA
        .attachingCut(cutId: "cut1", toStage: stageA, now: "t1")
        .attachingCut(cutId: "cut2", toStage: stageA, now: "t1")
        .addingFinal(cutId: "cut2", now: "t1")

    // removedCutIds is informational — the engine trashes these cuts BEFORE
    // deleting the stage; the pure report is never a license to hard-delete
    // shot rows (renders are paid artifacts).
    let (deleted, removedCutIds) = document.deletingStage(stageId: stageA, now: "t2")
    #expect(removedCutIds == ["cut1", "cut2"])
    #expect(deleted.stages.isEmpty)
    #expect(deleted.finals.isEmpty)

    let (untouched, none) = document.deletingStage(stageId: "ghost", now: "t2")
    #expect(untouched == document)
    #expect(none.isEmpty)
}

@Test func movingStageUsesSeamDropSemantics() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    var stageIds: [String] = []
    for name in ["A", "B", "C"] {
        let (next, stageId) = document.appendingStage(name: name, now: "t1")
        document = next
        stageIds.append(stageId)
    }
    // Drag A into the seam after C (index 3 against the pre-removal array).
    let moved = document.movingStage(stageId: stageIds[0], toIndex: 3, now: "t2")
    #expect(moved.stages.map(\.name) == ["B", "C", "A"])
    let front = document.movingStage(stageId: stageIds[2], toIndex: 0, now: "t2")
    #expect(front.stages.map(\.name) == ["C", "A", "B"])
}

@Test func finalsRequireAnOwnedCutAndDedupe() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    document = withA

    // Unowned cut: refused.
    #expect(document.addingFinal(cutId: "cutX", now: "t1") == document)

    document = document.attachingCut(cutId: "cut1", toStage: stageA, now: "t1")
    document = document.addingFinal(cutId: "cut1", now: "t1")
    #expect(document.addingFinal(cutId: "cut1", now: "t2") == document)

    let entryId = document.finals[0].entryId
    let removed = document.removingFinal(entryId: entryId, now: "t3")
    #expect(removed.finals.isEmpty)
}

@Test func movingFinalUsesSeamDropSemantics() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    document = withA
    for cutId in ["cut1", "cut2", "cut3"] {
        document = document
            .attachingCut(cutId: cutId, toStage: stageA, now: "t1")
            .addingFinal(cutId: cutId, now: "t1")
    }
    let first = document.finals[0].entryId
    let moved = document.movingFinal(entryId: first, toIndex: 3, now: "t2")
    #expect(moved.finals.map(\.cutId) == ["cut2", "cut3", "cut1"])
}

@Test func seedingMigratesEachShotIntoAStage() {
    var extensionEntry = ShotFrameEntry(entryId: "ext1")
    extensionEntry.isAIExtension = true
    var mixed = shot("shot2", name: "", frameIds: ["f2", "f3"], clipIds: ["m1"])
    mixed.entries.append(extensionEntry)
    mixed.entries.append(ShotFrameEntry(entryId: "dup", frameImageId: "f2")) // reused frame

    let timeline = timelineWith([
        shot("shot1", name: "Into the abyss", frameIds: ["f1"]),
        mixed
    ])
    let seeded = ProjectStageSetDocument.seeded(from: timeline, now: "t1")

    #expect(seeded.stages.count == 2)
    #expect(seeded.stages[0].name == "Into the abyss")
    #expect(seeded.stages[0].cutIds == ["shot1"])
    #expect(seeded.stages[0].inputs.map(\.frameImageId) == ["f1"])

    // Unnamed shot falls back to a positional stage name; inputs are the
    // DISTINCT assets (reused frame collapses, extension entries contribute
    // nothing), and the clip rides along as footage.
    #expect(seeded.stages[1].name == "Stage 2")
    #expect(seeded.stages[1].inputs.map(\.assetKey) == ["frame:f2", "frame:f3", "clip:m1"])
    #expect(seeded.stages[1].cutIds == ["shot2"])
    #expect(seeded.finals.isEmpty)

    // Seeding is deterministic — same timeline, same ids.
    let again = ProjectStageSetDocument.seeded(from: timeline, now: "t9")
    #expect(again.stages.map(\.stageId) == seeded.stages.map(\.stageId))
}

@Test func reconcilingPrunesDeadCutsAndAdoptsOrphans() {
    let timeline = timelineWith([
        shot("shot1", name: "Kept", frameIds: ["f1"]),
        shot("shot2", name: "Orphan", frameIds: ["f2"])
    ])
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    document = withA
        .attachingCut(cutId: "shot1", toStage: stageA, now: "t1")
        .attachingCut(cutId: "ghost", toStage: stageA, now: "t1")
        .addingFinal(cutId: "ghost", now: "t1")

    let (reconciled, changed) = document.reconciled(with: timeline, now: "t2")
    #expect(changed)
    #expect(reconciled.stage(withId: stageA)?.cutIds == ["shot1"])
    // The orphan shot got its own stage, named after itself, owning it.
    let adopted = reconciled.stage(containingCut: "shot2")
    #expect(adopted != nil)
    #expect(adopted?.name == "Orphan")
    #expect(adopted?.inputs.map(\.frameImageId) == ["f2"])
    // Finals pointing at dead cuts drop.
    #expect(reconciled.finals.isEmpty)

    // A faithful document reports changed == false and is untouched.
    let (again, changedAgain) = reconciled.reconciled(with: timeline, now: "t3")
    #expect(!changedAgain)
    #expect(again == reconciled)
}

@Test func trashingCutDetachesFromStageAndFinalsAndRemembersHome() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "Opening", now: "t1")
    document = withA
        .attachingCut(cutId: "cut1", toStage: stageA, now: "t1")
        .addingFinal(cutId: "cut1", now: "t1")

    let trashed = document.trashingCut(cutId: "cut1", now: "t2")
    #expect(trashed.stage(containingCut: "cut1") == nil)
    #expect(trashed.finals.isEmpty)
    #expect(trashed.trashedCuts.count == 1)
    #expect(trashed.trashedCuts[0].cutId == "cut1")
    #expect(trashed.trashedCuts[0].formerStageId == stageA)
    #expect(trashed.trashedCuts[0].formerStageName == "Opening")

    // Trashing again is a no-op; a trashed cut cannot be picked for FINALS.
    #expect(trashed.trashingCut(cutId: "cut1", now: "t3") == trashed)
    #expect(trashed.addingFinal(cutId: "cut1", now: "t3") == trashed)
}

@Test func restoringCutPrefersFormerStageThenFirstThenReportsHomeless() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    let (withB, stageB) = withA.appendingStage(name: "B", now: "t1")
    document = withB.attachingCut(cutId: "cut1", toStage: stageB, now: "t1")
    document = document.trashingCut(cutId: "cut1", now: "t2")
    let trashEntryId = document.trashedCuts[0].entryId

    // Former stage still exists → restored there.
    let (restored, cutId, target) = document.restoringCut(trashEntryId: trashEntryId, now: "t3")
    #expect(cutId == "cut1")
    #expect(target == stageB)
    #expect(restored.stage(containingCut: "cut1")?.stageId == stageB)
    #expect(restored.trashedCuts.isEmpty)

    // Former stage gone → falls back to the first stage.
    let (formerGone, _) = document.deletingStage(stageId: stageB, now: "t3")
    let (fallback, _, fallbackTarget) = formerGone.restoringCut(trashEntryId: trashEntryId, now: "t4")
    #expect(fallbackTarget == stageA)
    #expect(fallback.stage(containingCut: "cut1")?.stageId == stageA)

    // No stages at all → trash row clears, caller must found a stage.
    let (noStagesDoc, _) = formerGone.deletingStage(stageId: stageA, now: "t4")
    let (homeless, homelessCut, homelessTarget) = noStagesDoc.restoringCut(trashEntryId: trashEntryId, now: "t5")
    #expect(homelessCut == "cut1")
    #expect(homelessTarget == nil)
    #expect(homeless.trashedCuts.isEmpty)
}

@Test func deletingStageTrashPathAndReconcileRespectTrash() {
    let timeline = timelineWith([
        shot("cut1", name: "Kept", frameIds: ["f1"]),
        shot("cut2", name: "Trashed", frameIds: ["f2"])
    ])
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    document = withA
        .attachingCut(cutId: "cut1", toStage: stageA, now: "t1")
        .attachingCut(cutId: "cut2", toStage: stageA, now: "t1")
        .trashingCut(cutId: "cut2", now: "t2")

    // Reconcile must NOT re-adopt the trashed cut as an orphan…
    let (reconciled, changed) = document.reconciled(with: timeline, now: "t3")
    #expect(!changed)
    #expect(reconciled.stage(containingCut: "cut2") == nil)
    #expect(reconciled.trashedCuts.map(\.cutId) == ["cut2"])

    // …and a trash row whose timeline row vanished drops.
    let shrunk = timelineWith([shot("cut1", name: "Kept", frameIds: ["f1"])])
    let (pruned, prunedChanged) = document.reconciled(with: shrunk, now: "t4")
    #expect(prunedChanged)
    #expect(pruned.trashedCuts.isEmpty)

    // normalized(): a cut both staged and trashed resolves to staged.
    var conflicted = document
    conflicted = conflicted.updatingStage(stageId: stageA, now: "t5") { stage in
        var value = stage
        value.cutIds.append("cut2")
        value.updatedAt = "t5"
        return value
    }
    let normalized = conflicted.normalized()
    #expect(normalized.stage(containingCut: "cut2")?.stageId == stageA)
    #expect(normalized.trashedCuts.isEmpty)
}

@Test func attachingCutAfterAnchorSeatsTheNewVersionBesideItsOriginal() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    document = withA
        .attachingCut(cutId: "cut1", toStage: stageA, now: "t1")
        .attachingCut(cutId: "cut2", toStage: stageA, now: "t1")

    let seated = document.attachingCut(cutId: "cut1b", toStage: stageA, afterCutId: "cut1", now: "t2")
    #expect(seated.stage(withId: stageA)?.cutIds == ["cut1", "cut1b", "cut2"])

    // Absent anchor appends at the end.
    let appended = document.attachingCut(cutId: "cut9", toStage: stageA, afterCutId: "ghost", now: "t2")
    #expect(appended.stage(withId: stageA)?.cutIds == ["cut1", "cut2", "cut9"])
}

// MARK: Re-arranging cuts (vertical order + cross-stage moves)

@Test func movingCutUsesSeamDropSemanticsWithinItsStage() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    document = withA
        .attachingCut(cutId: "cut1", toStage: stageA, now: "t1")
        .attachingCut(cutId: "cut2", toStage: stageA, now: "t1")
        .attachingCut(cutId: "cut3", toStage: stageA, now: "t1")

    // Drag the first cut into the seam past the last (index 3 against the
    // pre-removal order), then pull the last one to the top.
    let moved = document.movingCut(cutId: "cut1", toStage: stageA, toVisibleIndex: 3, now: "t2")
    #expect(moved.stage(withId: stageA)?.cutIds == ["cut2", "cut3", "cut1"])
    let front = document.movingCut(cutId: "cut3", toStage: stageA, toVisibleIndex: 0, now: "t2")
    #expect(front.stage(withId: stageA)?.cutIds == ["cut3", "cut1", "cut2"])

    // Dropping a cut onto its own position changes nothing — and a no-op
    // document must stay equal so the engine can skip the persist.
    #expect(document.movingCut(cutId: "cut2", toStage: stageA, toVisibleIndex: 1, now: "t2") == document)
    #expect(document.movingCut(cutId: "cut2", toStage: stageA, toVisibleIndex: 2, now: "t2") == document)
}

/// The deliberate delta from `attachingCutClaimsAndReleasesOwnership`, which
/// asserts the pick DROPS. Detaching clears finals because a detached cut is
/// homeless; a move never is, so silently un-picking one would be a bug.
@Test func movingCutAcrossStagesKeepsItsFinalsPick() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    let (withB, stageB) = withA.appendingStage(name: "B", now: "t1")
    document = withB
        .attachingCut(cutId: "cut1", toStage: stageA, now: "t1")
        .attachingCut(cutId: "cut2", toStage: stageB, now: "t1")
        .attachingCut(cutId: "cut3", toStage: stageB, now: "t1")
        .addingFinal(cutId: "cut1", now: "t1")

    let moved = document.movingCut(cutId: "cut1", toStage: stageB, toVisibleIndex: 1, now: "t2")
    #expect(moved.stage(withId: stageA)?.cutIds.isEmpty == true)
    #expect(moved.stage(withId: stageB)?.cutIds == ["cut2", "cut1", "cut3"])
    #expect(moved.finals.map(\.cutId) == ["cut1"])
}

/// Both `normalized()` and `reconciled(with:)` delete a group whose named
/// stage no longer holds parent + every source, so a parent that travelled
/// without its sources — or without its group's stage claim — would destroy
/// its own group and strand the sources permanently visible.
@Test func movingACombinedParentCarriesItsSourcesAndItsGroupClaim() throws {
    var document = ProjectStageSetDocument(
        projectId: "p1",
        stages: [
            ProjectStage(stageId: "s1", name: "A", cutIds: ["a", "b", "c"]),
            ProjectStage(stageId: "s2", name: "B", cutIds: ["z"])
        ]
    )
    document = document.groupingCombinedCut(
        parentCutId: "parent",
        sourceCutIds: ["a", "b"],
        inStage: "s1",
        now: "t1"
    )
    #expect(document.stage(withId: "s1")?.cutIds == ["parent", "a", "b", "c"])

    // Same-stage move: the block stays contiguous at its new position.
    let reordered = document.movingCut(cutId: "parent", toStage: "s1", toVisibleIndex: 2, now: "t2")
    #expect(reordered.stage(withId: "s1")?.cutIds == ["c", "parent", "a", "b"])

    // Cross-stage move: sources travel AND the group's stage claim follows,
    // so a normalize cannot drop the group.
    let rehomed = document.movingCut(cutId: "parent", toStage: "s2", toVisibleIndex: 0, now: "t2")
    #expect(rehomed.stage(withId: "s2")?.cutIds == ["parent", "a", "b", "z"])
    #expect(rehomed.stage(withId: "s1")?.cutIds == ["c"])
    #expect(rehomed.group(parentCutId: "parent")?.stageId == "s2")
    #expect(rehomed.normalized().cutGroups.count == 1)
    let rehomedStage = try #require(rehomed.stage(withId: "s2"))
    #expect(rehomed.visibleCutIds(in: rehomedStage) == ["parent", "z"])
}

@Test func movingCutNeverLandsInsideACombinedGroup() throws {
    var document = ProjectStageSetDocument(
        projectId: "p1",
        stages: [ProjectStage(stageId: "s1", name: "A", cutIds: ["x", "a", "b", "y"])]
    )
    document = document.groupingCombinedCut(
        parentCutId: "parent",
        sourceCutIds: ["a", "b"],
        inStage: "s1",
        now: "t1"
    )
    let stage = try #require(document.stage(withId: "s1"))
    #expect(document.visibleCutIds(in: stage) == ["x", "parent", "y"])

    // Every visible anchor is a group boundary, so inserting "before the
    // anchor" can never split a parent from its sources.
    let after = document.movingCut(cutId: "x", toStage: "s1", toVisibleIndex: 2, now: "t2")
    #expect(after.stage(withId: "s1")?.cutIds == ["parent", "a", "b", "x", "y"])
    let before = document.movingCut(cutId: "y", toStage: "s1", toVisibleIndex: 1, now: "t2")
    #expect(before.stage(withId: "s1")?.cutIds == ["x", "y", "parent", "a", "b"])
}

@Test func movingCutRefusesHiddenSourcesGhostStagesAndUnownedCuts() {
    var document = ProjectStageSetDocument(
        projectId: "p1",
        stages: [
            ProjectStage(stageId: "s1", name: "A", cutIds: ["a", "b", "c"]),
            ProjectStage(stageId: "s2", name: "B", cutIds: [])
        ]
    )
    document = document.groupingCombinedCut(
        parentCutId: "parent",
        sourceCutIds: ["a", "b"],
        inStage: "s1",
        now: "t1"
    )
    // A hidden source has no independent position to move to.
    #expect(document.movingCut(cutId: "a", toStage: "s2", toVisibleIndex: 0, now: "t2") == document)
    #expect(document.movingCut(cutId: "c", toStage: "ghost", toVisibleIndex: 0, now: "t2") == document)
    #expect(document.movingCut(cutId: "unowned", toStage: "s1", toVisibleIndex: 0, now: "t2") == document)
    #expect(document.movingCut(cutId: "", toStage: "s1", toVisibleIndex: 0, now: "t2") == document)
}

/// Removal and insertion happen in one pass, so the cut is never momentarily
/// unclaimed — which is what keeps the orphan sweep (run on every timeline
/// persist) from adopting it into a brand-new stage.
@Test func movingCutIsAtomicSoReconcileNeverAdoptsIt() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    let (withB, stageB) = withA.appendingStage(name: "B", now: "t1")
    document = withB
        .attachingCut(cutId: "cut1", toStage: stageA, now: "t1")
        .attachingCut(cutId: "cut2", toStage: stageB, now: "t1")

    let moved = document.movingCut(cutId: "cut1", toStage: stageB, toVisibleIndex: 0, now: "t2")
    let timeline = timelineWith([shot("cut1"), shot("cut2")])
    let (reconciled, changed) = moved.reconciled(with: timeline, now: "t3")
    #expect(!changed)
    #expect(reconciled.stages.count == 2)
    #expect(reconciled.stage(withId: stageB)?.cutIds == ["cut1", "cut2"])
}

@Test func movingCutIntoAnEmptyStageAppends() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    let (withB, stageB) = withA.appendingStage(name: "B", now: "t1")
    document = withB.attachingCut(cutId: "cut1", toStage: stageA, now: "t1")

    #expect(
        document.movingCut(cutId: "cut1", toStage: stageB, toVisibleIndex: 0, now: "t2")
            .stage(withId: stageB)?.cutIds == ["cut1"]
    )
    // A past-the-end index clamps to an append — the menu path passes one.
    #expect(
        document.movingCut(cutId: "cut1", toStage: stageB, toVisibleIndex: 99, now: "t2")
            .stage(withId: stageB)?.cutIds == ["cut1"]
    )
    #expect(
        document.movingCut(cutId: "cut1", toStage: stageB, now: "t2")
            .stage(withId: stageB)?.cutIds == ["cut1"]
    )
}

@Test func duplicatedCutIsAFreshUnrenderedTimelineTwin() {
    var original = shot("cut1", name: "Causeway", frameIds: ["f1", "f2"], clipIds: ["m1"])
    original.entries[1].leadTransition = "cut"
    original.entries[2].clipStartSeconds = 1.5
    original.entries[2].clipEndSeconds = 3.0
    original.entries[0].isSkipped = true
    original.preferredRenderStack = "wan_2_7:8"
    original.segmentPromptOverrides = [ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "hold the dusk", updatedAt: "t0")]
    var render = ShotRenderArtifact()
    render.versionId = "v1"
    render.status = "ready"
    render.videoPath = "/tmp/x.mp4"
    original.renderVersions = [render]
    original.activeRenderVersionId = "v1"
    original.renderArtifact = render

    let copy = original.duplicated(now: "t9")
    #expect(copy.shotId != original.shotId)
    #expect(!copy.shotId.isEmpty)
    #expect(copy.name == "Causeway")
    #expect(copy.entries.count == 3)
    #expect(Set(copy.entries.map(\.entryId)).isDisjoint(with: Set(original.entries.map(\.entryId))))
    #expect(copy.entries.map(\.frameImageId) == original.entries.map(\.frameImageId))
    #expect(copy.entries.map(\.clipMediaId) == original.entries.map(\.clipMediaId))
    #expect(copy.entries[1].leadTransition == "cut")
    #expect(copy.entries[2].clipStartSeconds == 1.5)
    #expect(copy.entries[0].isSkipped)
    #expect(copy.preferredRenderStack == original.preferredRenderStack)
    #expect(copy.segmentPromptOverrides == original.segmentPromptOverrides)
    #expect(copy.renderVersions.isEmpty)
    #expect(copy.renderArtifact == nil)
    #expect(copy.activeRenderVersionId.isEmpty)
    #expect(copy.narrationArtifact == nil)
}

private func planItem(_ startId: String, _ endId: String?, stack: ShotRenderStack, index: Int = 0, override: String? = nil) -> ShotSegmentPromptPlanItem {
    ShotSegmentPromptPlanItem(
        index: index,
        pair: ShotRenderPair(
            start: ProjectLensHeroImage(imageId: startId),
            end: endId.map { ProjectLensHeroImage(imageId: $0) }
        ),
        generatedPrompt: "generated \(startId)",
        overridePrompt: override,
        renderStack: stack,
        hasRenderOverride: false,
        displayIndex: index
    )
}

@Test func costEstimateTreatsZeroRatesAsUnpriced() {
    // A zero unit_price from the pricing API must never render "EST. $0.00"
    // for a render that bills — the model falls to the unpriced bucket.
    let kling = ShotRenderStack.fallback.replacingModel(.falKlingV3Pro).replacingDuration(5)
    let klingId = kling.pairedModelSelection.providerModelId
    let pricing = FALPricingSnapshot(
        fetchedAt: Date(),
        prices: [klingId: FALModelPrice(endpointId: klingId, unitPrice: 0, unit: "video", currency: "USD")]
    )
    #expect(ShotRenderCostEstimate.segmentUSD(stack: kling, pricing: pricing) == nil)
    let estimate = ShotRenderCostEstimate.estimate(
        items: [planItem("f1", "f2", stack: kling, index: 0)],
        pricing: pricing
    )
    #expect(estimate.pricedSegmentCount == 0)
    #expect(estimate.headlineLabel == nil)
    #expect(estimate.unpricedModelLabels == [kling.model.label])
}

@Test func costEstimateScalesPerSecondUnitsAndFlatUnits() {
    let seedance = ShotRenderStack.fallback.replacingModel(.falSeedance20).replacingDuration(15)
    let kling = ShotRenderStack.fallback.replacingModel(.falKlingV3Pro).replacingDuration(5)
    let seedanceId = seedance.pairedModelSelection.providerModelId
    let klingId = kling.pairedModelSelection.providerModelId
    let pricing = FALPricingSnapshot(
        fetchedAt: Date(),
        prices: [
            seedanceId: FALModelPrice(endpointId: seedanceId, unitPrice: 0.05, unit: "video_second", currency: "USD"),
            klingId: FALModelPrice(endpointId: klingId, unitPrice: 0.40, unit: "video", currency: "USD")
        ]
    )

    // Per-second unit scales by segment duration: 0.05 × 15 = 0.75.
    #expect(ShotRenderCostEstimate.segmentUSD(stack: seedance, pricing: pricing) == 0.75)
    // A genuinely flat unit is per segment regardless of duration.
    #expect(ShotRenderCostEstimate.segmentUSD(stack: kling, pricing: pricing) == 0.40)
    // Audio flag never alters the math (billing caveat rides the tooltip).
    #expect(ShotRenderCostEstimate.segmentUSD(stack: seedance.replacingGeneratedAudio(true), pricing: pricing) == 0.75)
    // WAN rides FAL now; with no WAN rate in this snapshot it stays unpriced.
    #expect(ShotRenderCostEstimate.segmentUSD(stack: .fallback.replacingModel(.wan27), pricing: pricing) == nil)

    let items = [
        planItem("f1", "f2", stack: seedance, index: 0),
        planItem("f2", "f3", stack: kling, index: 1),
        planItem("f3", "f4", stack: .fallback.replacingModel(.wan27), index: 2)
    ]
    let estimate = ShotRenderCostEstimate.estimate(items: items, pricing: pricing)
    #expect(abs(estimate.totalUSD - 1.15) < 0.0001)
    #expect(estimate.pricedSegmentCount == 2)
    #expect(estimate.totalGeneratedCount == 3)
    #expect(estimate.unpricedModelLabels == ["WAN 2.7"])
    #expect(!estimate.isComplete)
    #expect(estimate.headlineLabel == "EST. ≥ $1.15")

    let complete = ShotRenderCostEstimate.estimate(items: Array(items.prefix(2)), pricing: pricing)
    #expect(complete.isComplete)
    #expect(complete.headlineLabel == "EST. $1.15")

    // No pricing at all → nothing priced, no headline.
    let unpriced = ShotRenderCostEstimate.estimate(items: items, pricing: nil)
    #expect(unpriced.pricedSegmentCount == 0)
    #expect(unpriced.headlineLabel == nil)
}

@Test func costEstimatePricesWANThroughFAL() {
    // Since the CivitAI→FAL orchestration switch the .wan27 stack bills
    // against fal-ai/wan/v2.7/image-to-video like any other FAL endpoint —
    // a WAN-only plan estimates COMPLETE, no "≥".
    let wan = ShotRenderStack.fallback.replacingModel(.wan27)
    let wanId = wan.pairedModelSelection.providerModelId
    #expect(wanId == "fal-ai/wan/v2.7/image-to-video")
    let pricing = FALPricingSnapshot(
        fetchedAt: Date(),
        prices: [wanId: FALModelPrice(endpointId: wanId, unitPrice: 0.05, unit: "video_second", currency: "USD")]
    )
    #expect(ShotRenderCostEstimate.segmentUSD(stack: wan, pricing: pricing) == 0.40)
    let estimate = ShotRenderCostEstimate.estimate(
        items: [planItem("f1", "f2", stack: wan, index: 0)],
        pricing: pricing
    )
    #expect(estimate.isComplete)
    #expect(estimate.unpricedModelLabels.isEmpty)
    #expect(estimate.headlineLabel == "EST. $0.40")
}

@Test func costEstimatePricesSeedanceTokenUnitsRatherThanFlat() {
    // FAL reports Seedance's token-bucket pricing as the opaque unit "units"
    // at $0.014 per 1,000 tokens. Reading that as a flat per-render fee billed
    // $0.014 for a 4s 1080p segment that actually costs $2.72 — a 194.4×
    // understatement printed next to a button that spends money.
    let seedance = ShotRenderStack.fallback.replacingModel(.falSeedance20).replacingDuration(4)
    let seedanceId = seedance.pairedModelSelection.providerModelId
    let pricing = FALPricingSnapshot(
        fetchedAt: Date(),
        prices: [seedanceId: FALModelPrice(
            endpointId: seedanceId, unitPrice: 0.014, unit: "units", currency: "USD"
        )]
    )

    // tokens = (1920 × 1080 × 4 × 24) / 1024 = 194,400 → 194.4 billed units.
    #expect(ShotRenderCostEstimate.billedUnits(stack: seedance, unit: "units") == 194.4)
    let segment = try! #require(ShotRenderCostEstimate.segmentUSD(stack: seedance, pricing: pricing))
    #expect(abs(segment - 2.7216) < 0.0001)

    // The reported plan: four 4s segments read $0.06 and actually cost $10.89.
    let items = (0..<4).map { planItem("f\($0)", "f\($0 + 1)", stack: seedance, index: $0) }
    let estimate = ShotRenderCostEstimate.estimate(items: items, pricing: pricing)
    #expect(abs(estimate.totalUSD - 10.8864) < 0.001)
    #expect(estimate.isComplete)
    #expect(estimate.headlineLabel == "EST. $10.89")

    // Duration scales the token count linearly.
    let long = seedance.replacingDuration(8)
    let longSegment = try! #require(ShotRenderCostEstimate.segmentUSD(stack: long, pricing: pricing))
    #expect(abs(longSegment - 5.4432) < 0.0001)

    // Cross-check against FAL's own published per-second figure: 720p @ 24fps
    // is 21,600 tokens/sec, which at $0.014/1k is exactly $0.3024/sec.
    let sevenTwenty = FALTokenBilling(tier: .p720, fps: 24)
    let oneSecond = try! #require(sevenTwenty.billedUnits(durationSeconds: 1))
    #expect(abs(oneSecond * 0.014 - 0.3024) < 0.000001)
}

@Test func costEstimateRefusesUnitsItCannotConvert() {
    // An unrecognized unit is unpriced, never a confident wrong number: the
    // strip shows "≥" instead of quoting a dimension it failed to read.
    let kling = ShotRenderStack.fallback.replacingModel(.falKlingV3Pro).replacingDuration(5)
    #expect(ShotRenderCostEstimate.billedUnits(stack: kling, unit: "megapixels") == nil)
    #expect(ShotRenderCostEstimate.billedUnits(stack: kling, unit: "") == nil)
    // Kling declares no token rule, so a token-shaped unit stays unpriced
    // rather than silently borrowing another model's frame size.
    #expect(kling.pairedModelSelection.falTokenBilling == nil)
    #expect(ShotRenderCostEstimate.billedUnits(stack: kling, unit: "units") == nil)

    let klingId = kling.pairedModelSelection.providerModelId
    let pricing = FALPricingSnapshot(
        fetchedAt: Date(),
        prices: [klingId: FALModelPrice(
            endpointId: klingId, unitPrice: 0.14, unit: "megapixels", currency: "USD"
        )]
    )
    #expect(ShotRenderCostEstimate.segmentUSD(stack: kling, pricing: pricing) == nil)
    let estimate = ShotRenderCostEstimate.estimate(
        items: [planItem("f1", "f2", stack: kling, index: 0)],
        pricing: pricing
    )
    #expect(estimate.pricedSegmentCount == 0)
    #expect(estimate.headlineLabel == nil)
    #expect(estimate.unpricedModelLabels == [kling.model.label])
}

@Test func seedanceRenderResolutionMatchesTheTierItIsPricedAt() {
    // The estimate's frame size and the resolution the client requests are the
    // same property — this pins them together so neither can drift alone.
    let seedance = ShotRenderStack.fallback.replacingModel(.falSeedance20)
    let tier = try! #require(seedance.pairedModelSelection.falResolutionTier)
    #expect(tier.rawValue == "1080p")
    #expect(tier.frameWidth == 1920)
    #expect(tier.frameHeight == 1080)
    let billing = try! #require(seedance.pairedModelSelection.falTokenBilling)
    #expect(billing.tier == tier)
    #expect(billing.fps == 24)
}

@Test func computedSegmentPromptOverridesEmitsOnlyMeaningfulEdits() {
    let stack = ShotRenderStack.fallback
    let paired = planItem("f1", "f2", stack: stack, index: 0)
    let openEnded = planItem("f3", nil, stack: stack, index: 1)
    let duplicatePair = planItem("f1", "f2", stack: stack, index: 2)
    let items = [paired, openEnded, duplicatePair]

    let drafts = [
        paired.pairKey: "hold the dusk",   // edited → override (duplicate pair shares it, emitted once)
        openEnded.pairKey: "generated f3"  // equals generated → dropped
    ]
    let overrides = computedSegmentPromptOverrides(drafts: drafts, items: items, now: "t1")
    #expect(overrides.count == 1)
    #expect(overrides[0].startFrameImageId == "f1")
    #expect(overrides[0].endFrameImageId == "f2")
    #expect(overrides[0].prompt == "hold the dusk")

    // Open-ended edits key with an empty end id.
    let openDrafts = [openEnded.pairKey: "drift slowly upward"]
    let openOverrides = computedSegmentPromptOverrides(drafts: openDrafts, items: items, now: "t1")
    #expect(openOverrides.count == 1)
    #expect(openOverrides[0].startFrameImageId == "f3")
    #expect(openOverrides[0].endFrameImageId.isEmpty)

    // Emptied drafts store nothing — the generated prompt renders.
    let emptied = [paired.pairKey: "   "]
    #expect(computedSegmentPromptOverrides(drafts: emptied, items: items, now: "t1").isEmpty)
}

@Test func computedSegmentPromptOverridesSurviveReorderAndPreserveUnshownOverrides() {
    let stack = ShotRenderStack.fallback

    // The strip-open-during-drag regression: a draft captured while the pair
    // sat at index 0 must still apply after an insert shifts it to index 5 —
    // pair keys are positional-id-proof.
    let shifted = planItem("f1", "f2", stack: stack, index: 5)
    let moved = computedSegmentPromptOverrides(
        drafts: [shifted.pairKey: "hold the dusk"],
        items: [shifted],
        now: "t1"
    )
    #expect(moved.count == 1)
    #expect(moved[0].prompt == "hold the dusk")

    // A pair the editor never touched (no draft entry) carries its persisted
    // override through the save instead of being wiped by omission…
    let kept = planItem("f4", "f5", stack: stack, index: 0, override: "keep me")
    let carried = computedSegmentPromptOverrides(drafts: [:], items: [kept], now: "t1")
    #expect(carried.count == 1)
    #expect(carried[0].prompt == "keep me")

    // …while a present-but-empty draft remains a deliberate clear.
    let cleared = computedSegmentPromptOverrides(
        drafts: [kept.pairKey: ""],
        items: [kept],
        now: "t1"
    )
    #expect(cleared.isEmpty)
}

@Test func backlotMembershipIsDerivedFromStagedFrameIds() {
    var document = ProjectStageSetDocument.empty(projectId: "p1")
    let (withA, stageA) = document.appendingStage(name: "A", now: "t1")
    document = withA
        .addingInput(stageId: stageA, frameImageId: "f1", now: "t1")
        .addingInput(stageId: stageA, clipMediaId: "m1", now: "t1")
    #expect(document.stagedFrameImageIds == ["f1"])
    #expect(document.stages(containingFrame: "f1").map(\.stageId) == [stageA])
    #expect(document.stages(containingFrame: "f9").isEmpty)
}
