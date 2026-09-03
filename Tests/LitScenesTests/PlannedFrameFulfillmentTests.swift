import Foundation
import Testing
@testable import LitScenes

@MainActor
private func makeFulfillmentTestEngine() -> LibraryEngine {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_plan_fulfillment_\(UUID().uuidString)", isDirectory: true)
    return LibraryEngine(projectLibrary: ProjectLibrary(root: root))
}

private func plannedFrame(
    imageId: String = "img_planned",
    status: String = "queued",
    generatedAt: String = "",
    imagePath: String = ""
) -> ProjectLensHeroImage {
    var image = ProjectLensHeroImage(imageId: imageId, status: status)
    image.imageIndex = 3
    image.label = "Batching Table With Dog Bed"
    image.sourceRouteKey = "lens_media_area_1_scene_1@v1"
    image.prompt = "The place: a batching kitchen."
    image.sourcePrompt = "The place: a batching kitchen.\nPresent in this scene: @Elise steadying jars."
    image.imageKind = LensImageTaxonomyKind.sceneImage
    image.areaId = "area_1"
    image.sceneId = "scene_1_1"
    image.generatedAt = generatedAt
    image.imagePath = imagePath
    return image
}

@Test
func plannedFrameContextIdentity() {
    let image = plannedFrame()
    let context = FrameCreationContext.plannedFrame(image)
    #expect(context.id == "planned_img_planned")
    #expect(context.templateImage?.imageId == "img_planned")
}

@Test
func planFulfillmentCandidateMatrix() {
    #expect(plannedFrame(status: "queued").isPlanFulfillmentCandidate)
    #expect(plannedFrame(status: "failed").isPlanFulfillmentCandidate)
    #expect(plannedFrame(status: "cancelled").isPlanFulfillmentCandidate)
    #expect(!plannedFrame(status: "ready").isPlanFulfillmentCandidate)
    #expect(!plannedFrame(status: "generating").isPlanFulfillmentCandidate)
    #expect(!plannedFrame(status: "queued", generatedAt: DateFormats.now()).isPlanFulfillmentCandidate)
    #expect(!plannedFrame(status: "failed", imagePath: "/tmp/frame.png").isPlanFulfillmentCandidate)

    var withVersion = plannedFrame()
    withVersion.renderVersion = LensRenderVersionMetadata()
    #expect(!withVersion.isPlanFulfillmentCandidate)

    var withReframe = plannedFrame()
    withReframe.reframe = LensReframeSpec()
    #expect(!withReframe.isPlanFulfillmentCandidate)
}

@Test
@MainActor
func fulfilledTakePreservesIdentityAndKeepsRenderedPayload() {
    let engine = makeFulfillmentTestEngine()
    var planned = plannedFrame()
    planned.kept = true

    var rendered = ProjectLensHeroImage(imageId: "img_new", status: "generating")
    rendered.imageIndex = 9
    rendered.label = "OpenAI Base custom take"
    rendered.sourceRouteKey = "lens_media_custom_abc@v2"
    rendered.prompt = "Elise steadying jars at the batching table."
    rendered.sourcePrompt = "@Elise steadying jars at the batching table."
    rendered.imageKind = LensImageTaxonomyKind.sceneImage
    rendered.areaId = "area_1"
    rendered.sceneId = "scene_1_1"
    rendered.styleAuthorities = [LensStyleAuthoritySnapshot(authorityId: "auth_s9", referenceId: "s9", title: "Sunlit Reverie Realism")]

    let fulfilled = engine.lensPlanFulfilledTake(planned: planned, rendered: rendered)
    #expect(fulfilled.imageId == planned.imageId)
    #expect(fulfilled.imageIndex == planned.imageIndex)
    #expect(fulfilled.label == planned.label)
    #expect(fulfilled.sourceRouteKey == planned.sourceRouteKey)
    #expect(fulfilled.homeSceneImageId == planned.homeSceneImageId)
    #expect(fulfilled.kept == true)
    // The rendered payload survives: prompt fields, status, and style selection.
    #expect(fulfilled.status == "generating")
    #expect(fulfilled.prompt == "Elise steadying jars at the batching table.")
    #expect(fulfilled.sourcePrompt == "@Elise steadying jars at the batching table.")
    #expect(fulfilled.styleAuthorities.first?.referenceId == "s9")
}

@Test
@MainActor
func fulfilledTakeKeepsSuggestionProvenance() {
    let engine = makeFulfillmentTestEngine()
    var planned = plannedFrame()
    planned.suggestedForCharacterId = "char_elise"
    planned.suggestedAt = "2026-09-03T02:00:00Z"
    let rendered = ProjectLensHeroImage(imageId: "img_new", status: "generating")
    let fulfilled = engine.lensPlanFulfilledTake(planned: planned, rendered: rendered)
    #expect(fulfilled.suggestedForCharacterId == "char_elise")
    #expect(fulfilled.isSheetSuggestion)
    #expect(!fulfilled.isPlanFulfillmentCandidate)
}
