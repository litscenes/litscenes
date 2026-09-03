import Foundation
import Testing
@testable import LitScenes

// MARK: - Landing condensation heuristic

@Test
func landingCondensesOnAccumulatedWorkbenchState() {
    // Fresh arrival: nothing staged, nothing rendered — full hero.
    #expect(!lensLandingIsCondensed(stageCount: 0, finalsCount: 0, readyFrameCount: 0))
    // Any staged or finaled work is unambiguous workbench mode.
    #expect(lensLandingIsCondensed(stageCount: 1, finalsCount: 0, readyFrameCount: 0))
    #expect(lensLandingIsCondensed(stageCount: 0, finalsCount: 1, readyFrameCount: 0))
    // The hero survives the first arriving renders, then yields at a working set.
    #expect(!lensLandingIsCondensed(stageCount: 0, finalsCount: 0, readyFrameCount: 2))
    #expect(lensLandingIsCondensed(stageCount: 0, finalsCount: 0, readyFrameCount: 3))
}

// MARK: - Preferred story resolution

private func storyEntry(
    _ libraryEntryId: String,
    projectStoryId: String,
    state: ProjectStoryEditorialState = .suggestion
) -> ProjectStoryLibraryEntry {
    var entry = ProjectStoryLibraryEntry(libraryEntryId: libraryEntryId)
    entry.projectStoryId = projectStoryId
    entry.editorialState = state
    entry.title = libraryEntryId
    return entry
}

@Test
func preferredEntryFavorsVisibleActiveStory() {
    var document = ProjectStoryLibraryDocument(projectId: "p1")
    document.entries = [
        storyEntry("entry_a", projectStoryId: "story_a"),
        storyEntry("entry_b", projectStoryId: "story_b")
    ]
    document.activeStoryId = "story_b"
    #expect(document.preferredEntry?.libraryEntryId == "entry_b")
}

@Test
func preferredEntryFallsBackWhenActiveIsRemovedOrMissing() {
    var document = ProjectStoryLibraryDocument(projectId: "p1")
    document.entries = [
        storyEntry("entry_a", projectStoryId: "story_a", state: .dismissed),
        storyEntry("entry_b", projectStoryId: "story_b")
    ]
    // Active points at a dismissed entry — fall to the first visible one.
    document.activeStoryId = "story_a"
    #expect(document.preferredEntry?.libraryEntryId == "entry_b")
    // Active points at nothing — same fallback.
    document.activeStoryId = "story_zzz"
    #expect(document.preferredEntry?.libraryEntryId == "entry_b")
}

@Test
func preferredEntryFiltersRemovedStatesAndHandlesEmpty() {
    var document = ProjectStoryLibraryDocument(projectId: "p1")
    document.entries = [
        storyEntry("entry_a", projectStoryId: "story_a", state: .dismissed),
        storyEntry("entry_b", projectStoryId: "story_b", state: .archived)
    ]
    #expect(document.visibleEntries.isEmpty)
    #expect(document.preferredEntry == nil)
    #expect(ProjectStoryLibraryDocument(projectId: "p1").preferredEntry == nil)
}

// MARK: - Render-all CTA predicate

private func landingFrame(_ imageId: String, index: Int, status: String) -> ProjectLensHeroImage {
    var image = ProjectLensHeroImage(imageId: imageId, status: status)
    image.imageIndex = index
    image.label = imageId
    image.imageKind = LensImageTaxonomyKind.sceneImage
    return image
}

@Test
func pendingRenderableFramesMirrorsEngineTargetPredicate() {
    let lens = ProjectLens(lensId: "lens_1", heroImages: [
        landingFrame("img_ready", index: 0, status: "ready"),
        landingFrame("img_generating", index: 1, status: "generating"),
        landingFrame("img_queued", index: 2, status: "queued"),
        landingFrame("img_failed", index: 3, status: "failed"),
        landingFrame("img_cancelled", index: 4, status: "cancelled")
    ])
    let pending = lensPendingRenderableFrames(lens)
    // Exactly what renderLensMedia(scope: .all) would target: everything not
    // already ready or in flight, ordered by imageIndex.
    #expect(pending.map(\.imageId) == ["img_queued", "img_failed", "img_cancelled"])
}

// MARK: - Continue destination

@Test
@MainActor
func continueDestinationForwardsOnceGoalIsReady() {
    #expect(LibraryRootView.continueDestination(from: .goal, isGoalReady: false, hasCharacterSheet: false) == .goal)
    #expect(LibraryRootView.continueDestination(from: .media, isGoalReady: false, hasCharacterSheet: true) == .goal)
    // Story → Characters once, then Scenes. Characters never blocks: from it,
    // Continue moves on even without a sheet.
    #expect(LibraryRootView.continueDestination(from: .goal, isGoalReady: true, hasCharacterSheet: false) == .characters)
    #expect(LibraryRootView.continueDestination(from: .goal, isGoalReady: true, hasCharacterSheet: true) == .scenesV2)
    #expect(LibraryRootView.continueDestination(from: .characters, isGoalReady: true, hasCharacterSheet: false) == .scenesV2)
    // Scenes is terminal: Output has no tab, and the old bounce back to
    // Story once a scene existed is exactly the dead-end this pins against.
    // "Scenes" is the v2 workbench since the tab swap.
    #expect(LibraryRootView.continueDestination(from: .scenesV2, isGoalReady: true, hasCharacterSheet: true) == .scenesV2)
    #expect(LibraryRootView.continueDestination(from: .aesthetic, isGoalReady: true, hasCharacterSheet: false) == .scenesV2)
}

@Test
func workspaceTabSwapKeepsPersistedMeanings() {
    // The tab swap: v2 owns the plain "Scenes" name and the leading
    // position; the old tab reads "Scenes v1" to its right.
    #expect(LibraryWorkspaceTab.scenesV2.rawValue == "Scenes")
    #expect(LibraryWorkspaceTab.aesthetic.rawValue == "Scenes v1")
    #expect(LibraryWorkspaceTab.allCases == [.media, .goal, .characters, .scenesV2, .aesthetic])
    #expect(LibraryWorkspaceTab.fromPersisted("Characters") == .characters)
    // Persisted legacy labels keep meaning: "Scenes v2" maps to the v2
    // workbench; a legacy "Scenes" (once v1) deliberately reopens the tab
    // NAMED Scenes — v2; the ancient "Frames" still reopens v1.
    #expect(LibraryWorkspaceTab.fromPersisted("Scenes v2") == .scenesV2)
    #expect(LibraryWorkspaceTab.fromPersisted("Scenes") == .scenesV2)
    #expect(LibraryWorkspaceTab.fromPersisted("Scenes v1") == .aesthetic)
    #expect(LibraryWorkspaceTab.fromPersisted("Frames") == .aesthetic)
    #expect(LibraryWorkspaceTab.fromPersisted("Moodboard") == .media)
    // The retired Storylines/Beats tabs are gone from the enum: their
    // persisted labels resolve to nil and the restore path falls back to
    // Media rather than reviving an unreachable tab.
    #expect(LibraryWorkspaceTab.fromPersisted("Storylines") == nil)
    #expect(LibraryWorkspaceTab.fromPersisted("Beat / Scene Plan") == nil)
}
