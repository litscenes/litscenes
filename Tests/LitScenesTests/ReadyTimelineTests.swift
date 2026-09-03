import Foundation
import Testing
@testable import LitScenes

// The Ready Timeline's pure laws: Output-sequence membership mutations
// (append/move beside the existing remove) and the SCENES v2 conveyor.

private let now = "2026-08-24T00:00:00Z"

private func sequence(_ shotIds: [String]) -> ProjectOutputSequenceDocument {
    var doc = ProjectOutputSequenceDocument.empty(projectId: "proj")
    for shotId in shotIds {
        doc = doc.appendingShot(shotId, now: now)
    }
    return doc
}

// MARK: - appendingShot

@Test func appendMintsAFreshNonEmptyEntryIdThatSurvivesNormalize() throws {
    let doc = sequence(["a", "b"])
    #expect(doc.shots.map(\.shotId) == ["a", "b"])
    for entry in doc.shots {
        #expect(entry.entryId.hasPrefix("output_"))
        #expect(!entry.entryId.trimmed.isEmpty)
        #expect(entry.addedAt == now)
    }
    #expect(Set(doc.shots.map(\.entryId)).count == 2)
    // normalized() prunes empty-entryId entries — minted entries must survive.
    #expect(doc.normalized().shots.count == 2)
}

@Test func appendIsIdempotentPerShot() {
    let doc = sequence(["a"])
    let again = doc.appendingShot("a", now: "2026-08-24T01:00:00Z")
    #expect(again == doc)
}

@Test func appendRefusesAnEmptyShotId() {
    let doc = sequence([]).appendingShot("   ", now: now)
    #expect(doc.shots.isEmpty)
}

@Test func reAddingAShotMintsANewEntryIdSoOldSeamsStayDead() throws {
    var doc = sequence(["a", "b"])
    let originalEntryId = try #require(doc.shots.first?.entryId)
    doc = doc.removingShot("a", now: now)
    doc = doc.appendingShot("a", now: now)
    let newEntryId = try #require(doc.shots.first(where: { $0.shotId == "a" })?.entryId)
    #expect(newEntryId != originalEntryId)
}

// MARK: - movingShot

@Test func moveForwardReadsTheTargetAgainstThePreRemovalOrder() {
    let doc = sequence(["a", "b", "c", "d"])
    #expect(doc.movingShot("a", toIndex: 2, now: now).shots.map(\.shotId) == ["b", "a", "c", "d"])
    #expect(doc.movingShot("a", toIndex: 4, now: now).shots.map(\.shotId) == ["b", "c", "d", "a"])
}

@Test func moveBackwardLandsBeforeTheTargetCard() {
    let doc = sequence(["a", "b", "c", "d"])
    #expect(doc.movingShot("d", toIndex: 1, now: now).shots.map(\.shotId) == ["a", "d", "b", "c"])
    #expect(doc.movingShot("c", toIndex: 0, now: now).shots.map(\.shotId) == ["c", "a", "b", "d"])
}

@Test func moveClampsOutOfRangeIndexes() {
    let doc = sequence(["a", "b"])
    #expect(doc.movingShot("b", toIndex: -3, now: now).shots.map(\.shotId) == ["b", "a"])
    #expect(doc.movingShot("a", toIndex: 99, now: now).shots.map(\.shotId) == ["b", "a"])
}

@Test func moveToTheSamePlaceOrOfAMissingShotIsANoOp() {
    let doc = sequence(["a", "b"])
    #expect(doc.movingShot("a", toIndex: 0, now: "2026-08-24T02:00:00Z") == doc)
    #expect(doc.movingShot("ghost", toIndex: 1, now: "2026-08-24T02:00:00Z") == doc)
}

// MARK: - Seams across membership changes

@Test func seamsGoDormantOnReorderButPruneOnRemoval() throws {
    var doc = sequence(["a", "b", "c"])
    let left = try #require(doc.shots.first(where: { $0.shotId == "a" })?.entryId)
    let right = try #require(doc.shots.first(where: { $0.shotId == "b" })?.entryId)
    doc.reelSeams = [ReelSeamStyle(leftEntryId: left, rightEntryId: right, crossfadeFrames: 12, updatedAt: now)]

    // Reorder displaces the pair — the seam survives dormant (adjacency is
    // resolved at read time), and normalized() keeps it.
    let reordered = doc.movingShot("b", toIndex: 3, now: now)
    #expect(reordered.normalized().reelSeams.count == 1)

    // Removing a member kills the seam structurally.
    let removed = doc.removingShot("b", now: now)
    #expect(removed.reelSeams.isEmpty)
}

// MARK: - Conveyor

@Test func conveyorPicksTheNextUnreadyUnboxedSceneForward() {
    let next = nextConveyorSceneId(
        visibleShotIds: ["a", "b", "c", "d"],
        departedShotId: "b",
        readyShotIds: ["b", "c"],
        boxedShotIds: ["b", "d"]
    )
    // c is ready, d is boxed → wraps past them to a.
    #expect(next == "a")
}

@Test func conveyorWrapsPastTheEnd() {
    let next = nextConveyorSceneId(
        visibleShotIds: ["a", "b", "c"],
        departedShotId: "c",
        readyShotIds: ["c", "b"],
        boxedShotIds: ["c"]
    )
    #expect(next == "a")
}

@Test func conveyorReturnsNilWhenEveryoneIsReadyOrBoxed() {
    #expect(nextConveyorSceneId(
        visibleShotIds: ["a", "b"],
        departedShotId: "a",
        readyShotIds: ["a", "b"],
        boxedShotIds: ["a"]
    ) == nil)
    #expect(nextConveyorSceneId(
        visibleShotIds: [],
        departedShotId: "a",
        readyShotIds: [],
        boxedShotIds: []
    ) == nil)
}

@Test func conveyorNeverReturnsTheDepartedSceneEvenWhenUnready() {
    // The departed scene is (transiently) neither ready nor boxed-elsewhere —
    // it must still be skipped.
    #expect(nextConveyorSceneId(
        visibleShotIds: ["a"],
        departedShotId: "a",
        readyShotIds: [],
        boxedShotIds: []
    ) == nil)
}

@Test func conveyorToleratesADepartedSceneMissingFromVisibleOrder() {
    #expect(nextConveyorSceneId(
        visibleShotIds: ["a", "b"],
        departedShotId: "ghost",
        readyShotIds: ["a"],
        boxedShotIds: []
    ) == "b")
}
