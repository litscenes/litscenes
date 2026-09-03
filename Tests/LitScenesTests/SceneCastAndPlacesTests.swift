import Foundation
import Testing
@testable import LitScenes

@MainActor
private func makeSceneCastTestEngine() -> LibraryEngine {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_scene_cast_\(UUID().uuidString)", isDirectory: true)
    return LibraryEngine(projectLibrary: ProjectLibrary(root: root))
}

private func sceneCastLens() -> ProjectLens {
    var body = LensBody()
    body.title = "Cast Lens"
    body.claim = "Honest batch work."
    body.visualSummary = "Sun-warmed coastal realism."
    body.castMembers = [
        LensCastMember(castId: "cast_elise", name: "Elise", descriptionPrompt: "a practical maker")
    ]
    var kitchenView = LensAreaScene()
    kitchenView.title = "Batching table with dog bed"
    kitchenView.prosePrompt = "A long table with rows of jars; a dog bed beneath."
    kitchenView.cast = [LensSceneCastEntry(name: "elise", presence: "steadying jars at the batching table")]
    var porchView = LensAreaScene()
    porchView.title = "Garden path to the porch"
    porchView.prosePrompt = "A crushed-shell path between raised beds."
    var kitchen = LensArea()
    kitchen.title = "The Batching Kitchen"
    kitchen.prosePrompt = "Lanai-side work room."
    kitchen.scenes = [kitchenView, porchView]
    body.areas = [kitchen]
    body.styleTreatment = LensStyleTreatment(
        catalogVersion: "v-test",
        primary: LensStyleTreatmentSlot(styleId: "s1", label: "Style One", weight: 60),
        accents: []
    )
    return ProjectLens(
        lensId: "lens_cast_test",
        status: .ready,
        enabled: true,
        body: body,
        heroImage: nil,
        heroImages: [],
        relationSummary: .empty,
        createdAt: DateFormats.now(),
        updatedAt: DateFormats.now()
    ).normalized()
}

@Test
func sceneCastMentionLineCanonicalizesValidatesAndClamps() {
    let validNames = ["Elise", "Marley"]
    let line = LensSceneCastPrompt.mentionLine(
        cast: [
            LensSceneCastEntry(name: "elise", presence: "steadying jars at the batching table"),
            LensSceneCastEntry(name: "Marley", presence: "curled in the dog bed")
        ],
        validNames: validNames
    )
    #expect(line == "Present in this scene: @Elise steadying jars at the batching table. @Marley curled in the dog bed.")

    // Unmatched names render as plain text — never a token that could attach the
    // wrong references.
    let unmatched = LensSceneCastPrompt.mentionLine(
        cast: [LensSceneCastEntry(name: "Elyse", presence: "at the table")],
        validNames: validNames
    )
    #expect(unmatched == "Present in this scene: Elyse at the table.")

    // Empty presence, terminal punctuation, clamping, and the empty cast.
    #expect(LensSceneCastPrompt.mentionLine(cast: [LensSceneCastEntry(name: "Elise")], validNames: validNames)
        == "Present in this scene: @Elise.")
    #expect(LensSceneCastPrompt.mentionLine(cast: [LensSceneCastEntry(name: "Elise", presence: "waves!")], validNames: validNames)
        == "Present in this scene: @Elise waves!")
    let clamped = LensSceneCastPrompt.mentionLine(
        cast: [
            LensSceneCastEntry(name: "Elise", presence: "one"),
            LensSceneCastEntry(name: "Marley", presence: "two"),
            LensSceneCastEntry(name: "Elise", presence: "three")
        ],
        validNames: validNames
    )
    #expect(clamped == "Present in this scene: @Elise one. @Marley two.")
    #expect(LensSceneCastPrompt.mentionLine(cast: [], validNames: validNames) == nil)
    #expect(LensSceneCastPrompt.mentionLine(cast: [LensSceneCastEntry(name: "   ")], validNames: validNames) == nil)
}

@Test
@MainActor
func sceneryPromptCarriesCastMentionsAndDropsUnpopulatedLine() {
    let engine = makeSceneCastTestEngine()
    let lens = sceneCastLens()
    let withCast = engine.lensSceneryConceptPrompt(
        setting: nil,
        prosePrompt: "A long table with rows of jars.",
        sceneCast: [LensSceneCastEntry(name: "Elise", presence: "steadying jars at the batching table")],
        setDressingPrompts: [],
        beatLabel: "",
        sceneryIndex: 0,
        sceneryCount: 1,
        theme: lens
    )
    #expect(withCast.contains("Present in this scene: @Elise steadying jars at the batching table."))
    #expect(withCast.contains("No one else is present"))
    #expect(!withCast.contains("The place is unpopulated"))

    let withoutCast = engine.lensSceneryConceptPrompt(
        setting: nil,
        prosePrompt: "A crushed-shell path between raised beds.",
        setDressingPrompts: [],
        beatLabel: "",
        sceneryIndex: 0,
        sceneryCount: 1,
        theme: lens
    )
    #expect(withoutCast.contains("The place is unpopulated"))
    #expect(!withoutCast.contains("Present in this scene:"))
}

@Test
@MainActor
func queuedSceneryFramesCarryCastTokensInStoredPrompts() {
    let engine = makeSceneCastTestEngine()
    let lens = sceneCastLens()
    let images = engine.queuedLensConceptImages(
        lens: lens,
        versionId: "v1",
        mediaSummaries: [],
        styleReferenceIds: ["ref"]
    )
    let sceneFrames = images.filter { $0.imageKind == LensImageTaxonomyKind.sceneImage }
    #expect(sceneFrames.count == 2)
    let castFrame = sceneFrames.first { $0.label.contains("Batching table") }
    #expect(castFrame != nil)
    #expect(castFrame?.prompt.contains("@Elise") == true)
    #expect(castFrame?.sourcePrompt.contains("@Elise") == true)
    // Scene frames never stamp characterId — @mentions are the control.
    #expect(castFrame?.characterId.isEmpty == true)
    let quietFrame = sceneFrames.first { $0.label.contains("Garden path") }
    #expect(quietFrame?.prompt.contains("unpopulated") == true)
}

@Test
func lensAreaSceneDecodesTolerantlyAcrossCastAndPlaceId() throws {
    // A pre-cast persisted scene (and pre-placeId area) keeps decoding.
    let legacySceneJSON = """
    {"sceneId": "scene_1", "title": "Old view", "prosePrompt": "An old view.", "enabled": true}
    """
    let legacyScene = try JSONCoding.decoder.decode(LensAreaScene.self, from: Data(legacySceneJSON.utf8))
    #expect(legacyScene.cast.isEmpty)
    #expect(legacyScene.title == "Old view")

    let legacyAreaJSON = """
    {"areaId": "area_1", "title": "Old place", "prosePrompt": "An old place.", "scenes": [], "enabled": true}
    """
    let legacyArea = try JSONCoding.decoder.decode(LensArea.self, from: Data(legacyAreaJSON.utf8))
    #expect(legacyArea.placeId.isEmpty)
    #expect(legacyArea.title == "Old place")

    // v0.5-shaped payloads round-trip the new fields.
    var scene = LensAreaScene()
    scene.sceneId = "scene_2"
    scene.title = "New view"
    scene.cast = [LensSceneCastEntry(name: "Elise", presence: "at the table")]
    var area = LensArea()
    area.areaId = "area_2"
    area.placeId = "place_abc"
    area.title = "New place"
    area.prosePrompt = "A new place."
    area.scenes = [scene]
    let data = try JSONCoding.encoder.encode(area)
    let decoded = try JSONCoding.decoder.decode(LensArea.self, from: data)
    #expect(decoded.placeId == "place_abc")
    #expect(decoded.scenes.first?.cast.first?.name == "Elise")
}

@Test
func projectPlaceSetDocumentNormalizesAndDecodesTolerantly() throws {
    var document = ProjectPlaceSetDocument.empty(projectId: "p1")
    document.places = [
        ProjectPlace(placeId: "place_1", name: "The Batching Kitchen"),
        ProjectPlace(placeId: "place_2", name: "the batching kitchen"),
        ProjectPlace(placeId: "place_3", name: "   ")
    ]
    let normalized = document.normalized()
    #expect(normalized.places.count == 1)
    #expect(normalized.places.first?.placeId == "place_1")

    let legacyJSON = """
    {"projectId": "p1"}
    """
    let decoded = try JSONCoding.decoder.decode(ProjectPlaceSetDocument.self, from: Data(legacyJSON.utf8))
    #expect(decoded.places.isEmpty)
    #expect(decoded.schemaVersion == ProjectPlaceSetDocument.schemaVersion)
}

@Test
@MainActor
func lensPlacesFromCompositionCreatesAndReusesRosterPlaces() {
    let engine = makeSceneCastTestEngine()
    var draft = ProjectPlaceSetDocument.empty(projectId: "p1")
    draft.places = [ProjectPlace(placeId: "place_existing", name: "Roadside Stand")]

    var kitchen = LensArea()
    kitchen.title = "The Batching Kitchen"
    kitchen.prosePrompt = "Lanai-side work room."
    var stand = LensArea()
    stand.title = "roadside stand"
    stand.prosePrompt = "Weathered plank stand."

    let now = DateFormats.now()
    let stamped = engine.lensPlacesFromComposition([kitchen, stand], placesDraft: &draft, now: now)
    #expect(stamped?.count == 2)
    // New title → a new roster place, stamped onto the area.
    #expect(draft.places.count == 2)
    let kitchenPlaceId = stamped?.first?.placeId ?? ""
    #expect(!kitchenPlaceId.isEmpty)
    #expect(draft.places.contains { $0.placeId == kitchenPlaceId && $0.name == "The Batching Kitchen" })
    // Case-insensitive title match reuses the existing entry.
    #expect(stamped?.last?.placeId == "place_existing")
}
