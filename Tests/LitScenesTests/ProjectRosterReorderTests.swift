import Foundation
import Testing
@testable import LitScenes

@Test
func reorderedReferencesInsertsNewIdAtTarget() {
    let base = ["a", "b", "c"]
    #expect(ProjectRosterView.reorderedReferences(placing: "x", at: 0, in: base) == ["x", "a", "b", "c"])
    #expect(ProjectRosterView.reorderedReferences(placing: "x", at: 2, in: base) == ["a", "b", "x", "c"])
    #expect(ProjectRosterView.reorderedReferences(placing: "x", at: 3, in: base) == ["a", "b", "c", "x"])
}

@Test
func reorderedReferencesMovesExistingIdForward() {
    // Moving an earlier id to a later slot adjusts the target for the removal.
    let base = ["a", "b", "c", "d"]
    #expect(ProjectRosterView.reorderedReferences(placing: "a", at: 2, in: base) == ["b", "a", "c", "d"])
    #expect(ProjectRosterView.reorderedReferences(placing: "a", at: 4, in: base) == ["b", "c", "d", "a"])
}

@Test
func reorderedReferencesMovesExistingIdBackward() {
    let base = ["a", "b", "c", "d"]
    #expect(ProjectRosterView.reorderedReferences(placing: "d", at: 0, in: base) == ["d", "a", "b", "c"])
    #expect(ProjectRosterView.reorderedReferences(placing: "c", at: 1, in: base) == ["a", "c", "b", "d"])
}

@Test
func reorderedReferencesClampsOutOfRangeTargets() {
    let base = ["a", "b"]
    #expect(ProjectRosterView.reorderedReferences(placing: "x", at: -3, in: base) == ["x", "a", "b"])
    #expect(ProjectRosterView.reorderedReferences(placing: "x", at: 99, in: base) == ["a", "b", "x"])
    // Slot 2 while only one reference exists becomes the trailing position.
    #expect(ProjectRosterView.reorderedReferences(placing: "x", at: 1, in: ["a"]) == ["a", "x"])
    #expect(ProjectRosterView.reorderedReferences(placing: "x", at: 0, in: []) == ["x"])
}

@Test
func reorderedReferencesSelfDropIsNoOp() {
    let base = ["a", "b", "c"]
    #expect(ProjectRosterView.reorderedReferences(placing: "b", at: 1, in: base) == base)
    #expect(ProjectRosterView.reorderedReferences(placing: "a", at: 0, in: base) == base)
    // Dropping an id onto the position just after itself is also a stable no-op.
    #expect(ProjectRosterView.reorderedReferences(placing: "a", at: 1, in: base) == base)
}
