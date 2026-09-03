import Foundation
import Testing
@testable import LitScenes

@MainActor
private func makeLaneLawTestEngine() -> LibraryEngine {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_lane_law_\(UUID().uuidString)", isDirectory: true)
    return LibraryEngine(projectLibrary: ProjectLibrary(root: root))
}

// The lane law around whole-lens flows: the initial Scene Plan hero render
// (a whole-lens FLOW) must not block row-scoped Frame starts, while Scene
// Plan media regeneration (the exclusive hold) still does.

@Test
@MainActor
func takeStartsAllowedDuringWholeLensFlow() {
    let engine = makeLaneLawTestEngine()
    engine.beginLensHeroWholeLensFlow(lensId: "lens_a")
    defer { engine.endLensHeroWholeLensFlow() }

    #expect(engine.isGeneratingLensHero)
    #expect(engine.lensHeroTakeStartBlockReason == nil)
    #expect(engine.registerLensHeroTakeOperation(imageId: "img_take", lensId: "lens_b"))
    engine.unregisterLensHeroTakeOperation(imageId: "img_take")
}

@Test
@MainActor
func busyStaysTrueAcrossWholeLensFlowRowClaims() {
    let engine = makeLaneLawTestEngine()
    engine.beginLensHeroWholeLensFlow(lensId: "lens_a")
    engine.registerLensHeroWholeLensRowClaim(imageId: "img_hero_1")
    #expect(engine.isGeneratingLensHero)
    engine.unregisterLensHeroTakeOperation(imageId: "img_hero_1")
    // Between row claims the flow count alone keeps the pipeline busy and
    // the generating-lens id stable.
    #expect(engine.isGeneratingLensHero)
    #expect(engine.activeLensHeroGenerationLensId == "lens_a")
    engine.endLensHeroWholeLensFlow()
    #expect(!engine.isGeneratingLensHero)
    #expect(engine.activeLensHeroGenerationLensId.isEmpty)
}

@Test
@MainActor
func sameRowClaimsRefuse() {
    let engine = makeLaneLawTestEngine()
    #expect(engine.registerLensHeroTakeOperation(imageId: "img_1", lensId: "lens_a"))
    #expect(!engine.registerLensHeroTakeOperation(imageId: "img_1", lensId: "lens_a"))
    #expect(engine.aestheticStatus == "This frame is already rendering")
    engine.unregisterLensHeroTakeOperation(imageId: "img_1")

    engine.registerLensHeroWholeLensRowClaim(imageId: "img_hero")
    #expect(!engine.registerLensHeroTakeOperation(imageId: "img_hero", lensId: "lens_a"))
    #expect(engine.aestheticStatus == "This frame is already rendering")
    engine.unregisterLensHeroTakeOperation(imageId: "img_hero")
}

@Test
@MainActor
func exclusiveHoldStillBlocksRowStarts() {
    let engine = makeLaneLawTestEngine()
    engine.beginLensHeroExclusiveHold(lensId: "lens_regen")
    defer { engine.endLensHeroExclusiveHold() }

    #expect(engine.isGeneratingLensHero)
    #expect(engine.lensHeroTakeStartBlockReason
        == "Wait for the Scene Plan media regeneration to finish before starting another still render")
    #expect(!engine.registerLensHeroTakeOperation(imageId: "img_take", lensId: "lens_a"))
    #expect(!engine.lensHeroReframeBlockReason.isEmpty)
}

@Test
@MainActor
func capRefusesInteractiveStartsButNotWholeLensClaims() {
    let engine = makeLaneLawTestEngine()
    for index in 0..<engine.lensHeroTakeLaneCap {
        #expect(engine.registerLensHeroTakeOperation(imageId: "img_\(index)", lensId: "lens_a"))
    }
    #expect(engine.lensHeroTakeLaneFreeSlots == 0)
    #expect(!engine.registerLensHeroTakeOperation(imageId: "img_overflow", lensId: "lens_a"))
    #expect(engine.aestheticStatus
        == "All \(engine.lensHeroTakeLaneCap) Frame render lanes are busy — wait for one to finish")

    engine.registerLensHeroWholeLensRowClaim(imageId: "img_hero")
    #expect(engine.activeLensHeroTakeImageIds.contains("img_hero"))
    #expect(engine.lensHeroTakeLaneFreeSlots == 0)

    for index in 0..<engine.lensHeroTakeLaneCap {
        engine.unregisterLensHeroTakeOperation(imageId: "img_\(index)")
    }
    engine.unregisterLensHeroTakeOperation(imageId: "img_hero")
    #expect(!engine.isGeneratingLensHero)
    #expect(engine.lensHeroTakeLaneFreeSlots == engine.lensHeroTakeLaneCap)
}

@Test
@MainActor
func pauseOutranksExclusiveAndCap() {
    let engine = makeLaneLawTestEngine()
    engine.setGenerationPaused(true)
    engine.beginLensHeroExclusiveHold(lensId: "lens_regen")
    defer {
        engine.endLensHeroExclusiveHold()
        engine.setGenerationPaused(false)
    }
    #expect(engine.lensHeroTakeStartBlockReason
        == "Resume the paused generation before starting a new still render")
}

@Test
@MainActor
func reframesAllowedDuringWholeLensFlow() {
    let engine = makeLaneLawTestEngine()
    engine.beginLensHeroWholeLensFlow(lensId: "lens_a")
    defer { engine.endLensHeroWholeLensFlow() }
    #expect(engine.lensHeroReframeBlockReason.isEmpty)
}
