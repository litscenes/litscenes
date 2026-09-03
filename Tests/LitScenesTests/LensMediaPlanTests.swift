import Foundation
import Testing
@testable import LitScenes

@MainActor
private func makeMediaPlanTestEngine() -> LibraryEngine {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_lens_media_plan_\(UUID().uuidString)", isDirectory: true)
    return LibraryEngine(projectLibrary: ProjectLibrary(root: root))
}

private func mediaPlanLens(
    scenePrompts: [String],
    characterPrompts: [String] = [],
    objectPrompts: [String] = [],
    setDressingPrompts: [String] = [],
    castMembers: [LensCastMember]? = nil,
    plan: LensMediaPlan? = nil,
    anchor: LensCanonicalAnchor? = nil
) -> ProjectLens {
    var body = LensBody()
    body.title = "Plan Lens"
    body.claim = "A world seen through its objects."
    body.visualSummary = "Warm coastal dusk."
    body.sceneImagePrompts = scenePrompts
    body.characterImagePrompts = characterPrompts.isEmpty ? nil : characterPrompts
    body.objectImagePrompts = objectPrompts.isEmpty ? nil : objectPrompts
    body.setDressingImagePrompts = setDressingPrompts.isEmpty ? nil : setDressingPrompts
    body.castMembers = castMembers
    body.mediaPlan = plan
    body.canonicalAnchor = anchor
    body.styleTreatment = LensStyleTreatment(
        catalogVersion: "v-test",
        primary: LensStyleTreatmentSlot(styleId: "s1", label: "Style One", weight: 60),
        accents: [LensStyleTreatmentSlot(styleId: "s2", label: "Style Two", weight: 40)]
    )
    return ProjectLens(
        lensId: "lens_plan_test",
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
func mediaPlanNormalizedClampsAllFields() {
    var plan = LensMediaPlan()
    plan.compositeCount = 99
    plan.mode = "journey"
    plan.aspect = "cinema"
    plan.characterCount = 12
    plan.castObjectCount = -4
    plan.setDressingDensity = "extreme"
    plan.selectedCharacterIds = ["a", "b", "c", "d", "a"]
    let normalized = plan.normalized()
    #expect(normalized.compositeCount == 6)
    #expect(normalized.mode == "collection")
    #expect(normalized.aspect == "square")
    #expect(normalized.characterCount == 4)
    #expect(normalized.castObjectCount == 0)
    #expect(normalized.setDressingDensity == "standard")
    // No scene-level cast cap — the cast is derived from takes and references attach
    // per-frame; normalization only dedupes and drops empties.
    #expect(normalized.selectedCharacterIds == ["a", "b", "c", "d"])
}

@Test
func mediaPlanAspectMapsToImageSizes() {
    var plan = LensMediaPlan()
    #expect(plan.imageSize == "1024x1024")
    #expect(plan.stabilityAspectRatio == "1:1")
    plan.aspect = "landscape"
    #expect(plan.imageSize == "1536x1024")
    #expect(plan.stabilityAspectRatio == "3:2")
    plan.aspect = "portrait"
    #expect(plan.imageSize == "1024x1536")
    #expect(plan.stabilityAspectRatio == "2:3")
}

@Test
func resolvedMediaPlanBackfillsFromLegacyCharacterCount() {
    var body = LensBody()
    body.compositeCharacterCount = 1
    let plan = body.resolvedMediaPlan
    #expect(plan.compositeCount == 3)
    #expect(plan.characterCount == 1)
    #expect(plan.castObjectCount == 2)
    #expect(plan.mode == "collection")
    #expect(plan.aspect == "square")
}

@Test
func legacyLensBodyJSONDecodesWithoutNewKeys() throws {
    // A v0.1-era body payload: none of the Phase 2 keys exist.
    let json = """
    {
      "title": "Vigil",
      "claim": "The night keeps watch.",
      "userNotes": "",
      "visualSummary": "Low-key rainlight.",
      "colorPalette": [],
      "styleIngredients": [],
      "paletteTerms": ["teal"],
      "motifTerms": [],
      "textureMaterialTerms": [],
      "compositionTerms": [],
      "pacingEnergyTerms": [],
      "mustPreserve": [],
      "mustAvoid": [],
      "referenceMediaIds": [],
      "openQuestions": [],
      "readinessSummary": "",
      "derivedVirtues": [],
      "compositeCharacterCount": 2
    }
    """
    let body = try JSONCoding.decoder.decode(LensBody.self, from: Data(json.utf8))
    #expect(body.mediaPlan == nil)
    #expect(body.setDressingImagePrompts == nil)
    #expect(body.castMembers == nil)
    #expect(body.canonicalAnchor == nil)
    #expect(body.resolvedMediaPlan.characterCount == 2)
    #expect(body.resolvedMediaPlan.castObjectCount == 1)
    // Round-trip keeps decoding cleanly.
    let reencoded = try JSONCoding.encoder.encode(body.normalized())
    let redecoded = try JSONCoding.decoder.decode(LensBody.self, from: reencoded)
    #expect(redecoded.normalized() == body.normalized())
}

@Test
@MainActor
func conceptBoardBuildsAreaScenesCharactersAndObjects() throws {
    let engine = makeMediaPlanTestEngine()
    var plan = LensMediaPlan()
    plan.compositeCount = 2
    plan.mode = "sequence"
    plan.sequenceBeats = ["map overview", "descent"]
    plan.characterCount = 1
    plan.castObjectCount = 1
    let cast = [LensCastMember(castId: "cast_kai", name: "Kai", descriptionPrompt: "a wiry operator", signatureProps: ["a woven cord bracelet"])]
    let lens = mediaPlanLens(
        scenePrompts: ["The island map at dawn.", "Coast road at dusk."],
        objectPrompts: ["a scrap solar-mesh node"],
        castMembers: cast,
        plan: plan
    )

    let images = engine.queuedLensConceptImages(
        lens: lens,
        versionId: "v1",
        mediaSummaries: [],
        styleReferenceIds: ["ref"]
    )

    // Area/Scene taxonomy: the scenes ARE the frames (no area rows by
    // default), then 1 character study, 1 object study.
    try #require(images.count == 4)
    #expect(images[0].sourceRouteKey == "lens_media_area_1_scene_1@v1")
    #expect(images[1].sourceRouteKey == "lens_media_area_1_scene_2@v1")
    #expect(images[2].sourceRouteKey == "lens_media_character_1@v1")
    #expect(images[3].sourceRouteKey == "lens_media_object_1@v1")
    #expect(images.map(\.imageKind) == [
        LensImageTaxonomyKind.sceneImage,
        LensImageTaxonomyKind.sceneImage,
        LensImageTaxonomyKind.characterImage,
        LensImageTaxonomyKind.objectImage
    ])
    // Sequence labels carry the beat; studies name their subjects.
    #expect(images[0].label == "Scene 1 · map overview")
    #expect(images[1].label == "Scene 2 · descent")
    #expect(images[2].label == "Character · Kai")
    // The fixture supplies only a prose object prompt (no named concept),
    // so the object title falls back to its ordinal.
    #expect(images[3].label == "Object · Object 1")
    // Only the primary treatment slot renders now — the accent never rides
    // sourceAestheticIds (it survives in the recipe text instead).
    #expect(images.allSatisfy { $0.sourceAestheticIds == ["s1"] })
    // The style reference rides the row as a source dependency (and its
    // presence is what pinned the fan-out to a single provider above).
    #expect(images.allSatisfy { row in row.sourceDependencies.contains { $0.sourceId == "ref" } })
    #expect(images.allSatisfy { $0.sourceRouteKey.hasSuffix("@v1") })
    #expect(images.map(\.imageIndex) == [0, 1, 2, 3])
    // Scene rows belong to the synthesized legacy area and anchor themselves.
    #expect(images[0].areaId == "area_legacy_primary")
    #expect(images[0].sceneId == "scene_legacy_1")
    #expect(images[1].sceneId == "scene_legacy_2")
    #expect(images.allSatisfy { $0.areaImageId.isEmpty })
    #expect(images[0].homeSceneImageId == images[0].imageId)
    #expect(images[1].homeSceneImageId == images[1].imageId)
    #expect(images[2].homeSceneImageId.isEmpty)
    #expect(images[3].homeSceneImageId.isEmpty)
    // Sequence facts reach the scenery prompts; studies carry their subjects.
    #expect(images[0].prompt.contains("Create one square environment concept image."))
    #expect(images[0].prompt.contains("stop 1 of 2"))
    #expect(images[0].prompt.contains("the map overview beat"))
    #expect(images[0].prompt.contains("The island map at dawn."))
    #expect(images[0].prompt.contains("unpopulated"))
    #expect(images[1].prompt.contains("stop 2 of 2"))
    #expect(images[1].prompt.contains("the descent beat"))
    #expect(images[2].prompt.contains("character concept study"))
    #expect(images[2].prompt.contains("Always with them: a woven cord bracelet"))
    #expect(images[3].prompt.contains("prop concept study"))
    #expect(images[3].prompt.contains("a scrap solar-mesh node"))
    // Provenance carries blend and plan facts.
    #expect(images[0].sourceRecipeVersion?.contains("seq") == true)
    #expect(images[0].sourceRecipeVersion?.contains("1C+1O") == true)
    // Category grouping: scenery, characters, objects (no area frames queued).
    let sections = LensConceptCategory.sections(for: images)
    #expect(sections.map(\.category) == [.scenery, .characters, .objects])

    // The compat path still emits the flat Area frame ahead of its scenes.
    let withAreas = engine.queuedLensConceptImages(
        lens: lens,
        versionId: "v1",
        mediaSummaries: [],
        styleReferenceIds: ["ref"],
        includeAreaImages: true
    )
    try #require(withAreas.count == 5)
    #expect(withAreas[0].sourceRouteKey == "lens_media_area_1@v1")
    #expect(withAreas[0].label == "Area · Area 1")
    #expect(withAreas[0].imageKind == LensImageTaxonomyKind.areaImage)
    #expect(LensConceptCategory.sections(for: withAreas).map(\.category) == [.areas, .scenery, .characters, .objects])
}

@Test
@MainActor
func sceneOnlyLensQueuesOneSceneConcept() throws {
    let engine = makeMediaPlanTestEngine()
    var plan = LensMediaPlan()
    plan.characterCount = 0
    plan.castObjectCount = 0
    plan.setDressingDensity = "off"
    let lens = mediaPlanLens(scenePrompts: ["An empty shoreline settlement at dawn."], plan: plan)

    let images = engine.queuedLensConceptImages(
        lens: lens,
        versionId: "",
        mediaSummaries: [],
        styleReferenceIds: ["ref"]
    )

    // One scene → one scene frame: no style bake-off, and a non-empty
    // styleReferenceIds keeps the fan-out to a single provider.
    try #require(images.count == 1)
    #expect(LensConceptCategory.category(forRouteKey: images[0].sourceRouteKey) == .scenery)
    #expect(images[0].sourceRouteKey == "lens_media_area_1_scene_1")
    #expect(images[0].prompt.contains("unpopulated"))
}

@Test
@MainActor
func legacyCompositeRouteKeysGroupIntoLegacySection() {
    let categories = [
        "lens_media_composite_1@v2",
        "lens_media_hero",
        "lens_media_scenery_1_s1@v3",
        "lens_media_scenery_2@v3",
        "lens_media_character_1@v3",
        "lens_media_object_1@v3"
    ].map { LensConceptCategory.category(forRouteKey: $0) }
    #expect(categories == [.legacy, .legacy, .areas, .scenery, .characters, .objects])
}

@Test
@MainActor
func conceptPromptsAssembleFromStructuredFields() {
    let engine = makeMediaPlanTestEngine()
    var plan = LensMediaPlan()
    plan.aspect = "landscape"
    plan.allowReadableText = true
    var setting = LensSceneSetting()
    setting.title = "Roadside work yard"
    setting.locationName = "a coastal work yard on Farrington Highway"
    setting.locationType = "exterior, coastal"
    setting.timeOfDay = "late afternoon"
    setting.weather = "salt haze after a passing shower"
    setting.spatialLayout = "a folding work table in the foreground, the road behind it, the seawall and ocean beyond"
    setting.foregroundDetails = ["a folding work table", "stacked mesh panels"]
    setting.backgroundDetails = ["a low seawall", "fishing poles against the guardrail"]
    setting.notableFeatures = ["a faded federal-era road sign patched with hand lettering"]
    let anchor = LensCanonicalAnchor(mediaId: "media_map", caption: "Oʻahu ahupuaʻa map", placement: "featured")
    var lens = mediaPlanLens(
        scenePrompts: ["fallback prose"],
        setDressingPrompts: ["coiled salvaged cable on a pallet"],
        plan: plan,
        anchor: anchor
    )
    lens.body.sceneSettings = [setting]
    lens = lens.normalized()

    let sceneryPrompt = engine.lensSceneryConceptPrompt(
        setting: lens.body.sceneSettings?.first,
        prosePrompt: "fallback prose",
        setDressingPrompts: lens.body.setDressingImagePrompts ?? [],
        beatLabel: "",
        sceneryIndex: 0,
        sceneryCount: 1,
        theme: lens
    )
    #expect(sceneryPrompt.contains("Create one wide cinematic environment concept image."))
    #expect(sceneryPrompt.contains("The place: a coastal work yard on Farrington Highway — exterior, coastal."))
    #expect(sceneryPrompt.contains("Time: late afternoon."))
    #expect(sceneryPrompt.contains("Weather: salt haze after a passing shower."))
    #expect(sceneryPrompt.contains("Spatial layout:"))
    #expect(sceneryPrompt.contains("In the foreground: a folding work table; stacked mesh panels."))
    #expect(sceneryPrompt.contains("In the background: a low seawall; fishing poles against the guardrail."))
    #expect(sceneryPrompt.contains("Notable features: a faded federal-era road sign patched with hand lettering."))
    #expect(sceneryPrompt.contains("Ambient set dressing"))
    #expect(sceneryPrompt.contains("unpopulated"))
    #expect(sceneryPrompt.contains("Feature the Oʻahu ahupuaʻa map prominently"))
    // Register-neutral: environmental text follows the world's condition, never a decay default.
    #expect(sceneryPrompt.contains("Environmental text is welcome where the world implies it"))
    #expect(!sceneryPrompt.contains("Weathered, degraded"))
    #expect(!sceneryPrompt.contains("fallback prose"))
    #expect(!sceneryPrompt.contains("Do not render readable text"))

    let characterPrompt = engine.lensCharacterConceptPrompt(
        name: "Kai",
        descriptionPrompt: "a patient wiry operator, weathered cap",
        signatureProps: ["a woven cord bracelet"],
        environmentAffinity: "",
        settings: lens.body.sceneSettings ?? [],
        anchorProse: "",
        theme: lens,
        mediaSummaries: []
    )
    #expect(characterPrompt.contains("character concept study"))
    #expect(characterPrompt.contains("\"Kai\" — a patient wiry operator, weathered cap"))
    #expect(characterPrompt.contains("Always with them: a woven cord bracelet."))
    #expect(characterPrompt.contains("Show the full figure"))
    // Character studies render as isolated cut-outs with no environment lines.
    #expect(characterPrompt.contains("clean isolated character study"))
    #expect(!characterPrompt.contains("kept secondary"))

    var concept = LensObjectConcept()
    concept.name = "scrap solar-mesh node"
    concept.type = "salvaged equipment"
    concept.material = "aluminum frame, woven conductive mesh"
    concept.condition = "field-patched, sun-faded"
    concept.distinguishingFeatures = ["hand-tied repair knots"]
    concept.locationInScene = "on the folding work table"
    let objectPrompt = engine.lensObjectConceptPrompt(
        concept: concept,
        prosePrompt: "",
        anchorSetting: lens.body.sceneSettings?.first,
        anchorProse: "",
        theme: lens
    )
    #expect(objectPrompt.contains("prop concept study"))
    #expect(objectPrompt.contains("scrap solar-mesh node — salvaged equipment, aluminum frame, woven conductive mesh, field-patched, sun-faded."))
    #expect(objectPrompt.contains("Distinguishing features: hand-tied repair knots."))
    #expect(objectPrompt.contains("It lives here: on the folding work table."))
    #expect(objectPrompt.contains("clear sense of scale"))
}

@Test
@MainActor
func styleBackedPromptsCarrySubjectMatterOnly() {
    let engine = makeMediaPlanTestEngine()

    // Style-backed lens (has a treatment): no lens style language in the core prompt —
    // the attached style image is the sole authority on rendering.
    let styledLens = mediaPlanLens(scenePrompts: ["A coastal work yard at dusk."])
    let styledPrompt = engine.lensSceneryConceptPrompt(
        setting: nil,
        prosePrompt: "A coastal work yard at dusk.",
        setDressingPrompts: [],
        beatLabel: "",
        sceneryIndex: 0,
        sceneryCount: 1,
        theme: styledLens
    )
    #expect(!styledPrompt.contains("Visual style:"))
    #expect(styledPrompt.contains("The place: A coastal work yard at dusk."))

    // Prompt-only lens (no treatment, no reference ingredients): text is the only style
    // channel, so the visual language block stays.
    var promptOnlyBody = LensBody()
    promptOnlyBody.title = "Prompt Only"
    promptOnlyBody.claim = "A quiet claim."
    promptOnlyBody.visualSummary = "Warm dusk realism."
    promptOnlyBody.sceneImagePrompts = ["A coastal work yard at dusk."]
    let promptOnlyLens = ProjectLens(
        lensId: "lens_prompt_only",
        status: .ready,
        enabled: true,
        body: promptOnlyBody,
        heroImage: nil,
        heroImages: [],
        relationSummary: .empty,
        createdAt: DateFormats.now(),
        updatedAt: DateFormats.now()
    ).normalized()
    let promptOnlyPrompt = engine.lensSceneryConceptPrompt(
        setting: nil,
        prosePrompt: "A coastal work yard at dusk.",
        setDressingPrompts: [],
        beatLabel: "",
        sceneryIndex: 0,
        sceneryCount: 1,
        theme: promptOnlyLens
    )
    #expect(promptOnlyPrompt.contains("Visual style:"))
}

@Test
func continuityDescriptorsCarryWorldContinuityNeverPalette() {
    let sequencePlan = LensBlendAttachmentPlan.make(
        treatment: nil,
        ingredients: [],
        continuityURLs: [URL(fileURLWithPath: "/tmp/f1.jpg"), URL(fileURLWithPath: "/tmp/f2.jpg")],
        sequenceContinuity: true
    )
    let lines = sequencePlan.manifestLines().joined(separator: "\n")
    #expect(lines.contains("immediately preceding frame"))
    #expect(lines.contains("earlier frame of this same continuous journey"))
    // Continuity must never instruct palette/rendering matching: the style image rules.
    #expect(lines.contains("Take NO palette"))
    #expect(!lines.contains("match its palette"))

    let collectionPlan = LensBlendAttachmentPlan.make(
        treatment: nil,
        ingredients: [],
        continuityURLs: [URL(fileURLWithPath: "/tmp/f1.jpg")]
    )
    #expect(collectionPlan.manifestText.contains("depicts a different scene"))
    #expect(collectionPlan.manifestText.contains("Take NO palette"))
}

@Test
func subjectAnchorEntersManifestBetweenStylesAndCharacters() {
    let treatment = LensStyleTreatment(
        catalogVersion: "v-test",
        primary: LensStyleTreatmentSlot(styleId: "a", label: "Style A", weight: 100)
    )
    let reference = SREFStyleImageReference(
        catalogKind: "style_browse_catalog",
        catalogVersion: "v-test",
        itemId: "a",
        title: "Style A",
        srefCode: "sref-a",
        sourceKey: "sref-a",
        variantName: "generated_1024",
        url: "https://example.cloudfront.net/a.png",
        sha256: String(repeating: "d", count: 64),
        width: 1024,
        height: 1024,
        byteSize: 10,
        mimeType: "image/png"
    )
    let ingredient = LensStyleIngredient(
        ingredientId: "ingredient_a",
        order: 1,
        title: "Style A",
        role: "style_reference",
        narrativeUse: "",
        presentationUse: "",
        notes: "",
        sourceReferenceIds: [reference.sourceReferenceId]
    )

    let plan = LensBlendAttachmentPlan.make(
        treatment: treatment,
        ingredients: [ingredient],
        subjectAnchor: (caption: "Oʻahu ahupuaʻa map", url: URL(fileURLWithPath: "/tmp/map.png")),
        characterReferences: [.init(name: "Kai", urls: [URL(fileURLWithPath: "/tmp/kai.jpg")])],
        continuityURLs: [URL(fileURLWithPath: "/tmp/prior.jpg")]
    )

    let roles = plan.entries.map(\.role)
    #expect(roles == [.primary, .subjectAnchor, .characterReference, .continuity])
    #expect(plan.entries[1].attachmentFilename == "subject-anchor-1.png")
    #expect(plan.manifestText.contains("SUBJECT anchor — this exact Oʻahu ahupuaʻa map must appear as itself"))
}

@Test
func compositionResponseDecodesV02FieldsAndLegacyPayloads() throws {
    let v02JSON = """
    {
      "schema_version": "litscenes.lens_composition.v0.2",
      "lens": {
        "title": "Steady Hands",
        "claim": "Resilience looks like maintenance.",
        "visual_summary": "Golden coastal work light.",
        "look": "Sun-worn realism.",
        "palette": ["salt white"], "materials": [], "motifs": [], "composition": [], "pacing_energy": [], "avoid": [],
        "must_preserve": [], "must_avoid": [],
        "scene_image_prompts": ["The map.", "The yard."],
        "character_image_prompts": ["Kai checking mesh nodes.", "Noe at the grill."],
        "object_image_prompts": ["A mesh node.", "A grill."],
        "set_dressing_image_prompts": ["A faded road sign.", "Coiled cable."],
        "cast_members": [
          {"name": "Kai", "description": "wiry, patient, weathered cap"},
          {"name": "Noe", "description": "broad-shouldered welder"}
        ],
        "suggested_media_plan": {
          "mode": "sequence",
          "aspect": "landscape",
          "character_count": 2,
          "cast_object_count": 1,
          "set_dressing_density": "rich",
          "allow_readable_text": true,
          "sequence_beats": ["map overview", "descent", "arrival"]
        },
        "primary_style_index": 0,
        "accent_style_indexes": [1, 2],
        "blend_profile": "dominant",
        "style_rationale": "Grounded warmth."
      }
    }
    """
    let response = try JSONCoding.decoder.decode(LensCompositionResponse.self, from: Data(v02JSON.utf8))
    #expect(response.lens.setDressingImagePrompts.count == 2)
    #expect(response.lens.castMembers.map(\.name) == ["Kai", "Noe"])
    let plan = try #require(response.lens.suggestedMediaPlan).mediaPlan
    #expect(plan.isSequence)
    #expect(plan.aspect == "landscape")
    #expect(plan.setDressingDensity == "rich")
    #expect(plan.allowReadableText)
    #expect(plan.compositeCount == 3)

    // Legacy v0.1 payload without the new keys still decodes.
    let v01JSON = """
    {
      "schema_version": "litscenes.lens_composition.v0.1",
      "lens": {
        "title": "Vigil",
        "claim": "The night keeps watch.",
        "primary_style_index": 0,
        "accent_style_indexes": [1, 2],
        "blend_profile": "anchored"
      }
    }
    """
    let legacy = try JSONCoding.decoder.decode(LensCompositionResponse.self, from: Data(v01JSON.utf8))
    #expect(legacy.lens.setDressingImagePrompts.isEmpty)
    #expect(legacy.lens.castMembers.isEmpty)
    #expect(legacy.lens.suggestedMediaPlan == nil)
}

@Test
func characterSetDocumentEnforcesUniqueNamesAndRoundTrips() throws {
    var document = ProjectCharacterSetDocument.empty(projectId: "project_test")
    document.characters = [
        ProjectCharacter(characterId: "c1", name: "Kai", descriptionPrompt: "wiry operator", referenceMediaIds: ["m1", "m2"]),
        ProjectCharacter(characterId: "c2", name: "kai", descriptionPrompt: "duplicate name, dropped"),
        ProjectCharacter(characterId: "c3", name: "Noe")
    ]
    let normalized = document.normalized()
    #expect(normalized.characters.map(\.name) == ["Kai", "Noe"])
    #expect(normalized.nameIsAvailable("Leilani"))
    #expect(!normalized.nameIsAvailable("KAI"))
    #expect(normalized.nameIsAvailable("Kai", excludingCharacterId: "c1"))

    let data = try JSONCoding.encoder.encode(normalized)
    let decoded = try JSONCoding.decoder.decode(ProjectCharacterSetDocument.self, from: data)
    #expect(decoded == normalized)

    // Tolerant decode of a minimal payload.
    let minimal = try JSONCoding.decoder.decode(
        ProjectCharacterSetDocument.self,
        from: Data(#"{"characters": [{"name": "Solo"}]}"#.utf8)
    )
    #expect(minimal.characters.count == 1)
    #expect(!minimal.characters[0].characterId.isEmpty)
}

@Test
func characterReferenceLabelsTrimPruneOrphansAndRoundTrip() throws {
    let character = ProjectCharacter(
        characterId: "c1",
        name: "Ava",
        referenceMediaIds: ["m1", "m2"],
        referenceLabels: [
            "m1": "  young Ava  ",
            "m2": "   ",           // empty label drops
            "m_gone": "orphaned"   // not a reference — prunes
        ]
    ).normalized()
    #expect(character.referenceLabels == ["m1": "young Ava"])

    // Removing the reference prunes its label on the next normalize.
    var edited = character
    edited.referenceMediaIds = ["m2"]
    #expect(edited.normalized().referenceLabels.isEmpty)

    let data = try JSONCoding.encoder.encode(character)
    let decoded = try JSONCoding.decoder.decode(ProjectCharacter.self, from: data)
    #expect(decoded.referenceLabels == ["m1": "young Ava"])

    // Legacy payloads without the key decode to an empty map.
    let legacy = try JSONCoding.decoder.decode(
        ProjectCharacter.self,
        from: Data(#"{"characterId": "c9", "name": "Noe", "referenceMediaIds": ["m1"]}"#.utf8)
    )
    #expect(legacy.referenceLabels.isEmpty)
}

@Test
func compositionResponseDecodesV03StructuredFields() throws {
    let v03JSON = """
    {
      "schema_version": "litscenes.lens_composition.v0.3",
      "lens": {
        "title": "Steady Hands",
        "claim": "Resilience looks like maintenance.",
        "scene_settings": [
          {
            "title": "Roadside work yard",
            "location_name": "a coastal work yard on Farrington Highway",
            "location_type": "exterior, coastal",
            "time_of_day": "late afternoon",
            "weather": "salt haze",
            "spatial_layout": "table in front, road behind, ocean beyond",
            "foreground_details": ["a folding work table", "stacked mesh panels"],
            "background_details": ["a low seawall"],
            "notable_features": ["a faded road sign"]
          }
        ],
        "cast_members": [
          {"name": "Kai", "description": "wiry, patient", "signature_props": ["a woven cord bracelet"], "environment_affinity": "the work yard"}
        ],
        "object_concepts": [
          {
            "name": "scrap solar-mesh node",
            "type": "salvaged equipment",
            "material": "aluminum and mesh",
            "condition": "field-patched",
            "distinguishing_features": ["hand-tied repair knots"],
            "location_in_scene": "on the work table"
          }
        ],
        "set_dressing": ["coiled salvaged cable"],
        "primary_style_index": 0,
        "accent_style_indexes": [1, 2],
        "blend_profile": "dominant"
      }
    }
    """
    let response = try JSONCoding.decoder.decode(LensCompositionResponse.self, from: Data(v03JSON.utf8))
    #expect(response.lens.sceneSettings.count == 1)
    #expect(response.lens.sceneSettings[0].locationName == "a coastal work yard on Farrington Highway")
    #expect(response.lens.sceneSettings[0].foregroundDetails.count == 2)
    #expect(response.lens.castMembers[0].signatureProps == ["a woven cord bracelet"])
    #expect(response.lens.objectConcepts[0].name == "scrap solar-mesh node")
    #expect(response.lens.objectConcepts[0].distinguishingFeatures == ["hand-tied repair knots"])
    #expect(response.lens.setDressing == ["coiled salvaged cable"])
}

@Test
func conceptContinuitySelectsSameStyleSceneryOnlyCappedAtTwo() {
    let chain: [LensConceptChainEntry] = [
        LensConceptChainEntry(styleId: "s1", category: .areas, url: URL(fileURLWithPath: "/tmp/anchor-s1.jpg")),
        LensConceptChainEntry(styleId: "s2", category: .areas, url: URL(fileURLWithPath: "/tmp/anchor-s2.jpg")),
        LensConceptChainEntry(styleId: "s1", category: .scenery, url: URL(fileURLWithPath: "/tmp/scenery-2.jpg")),
        LensConceptChainEntry(styleId: "s1", category: .scenery, url: URL(fileURLWithPath: "/tmp/scenery-3.jpg")),
        LensConceptChainEntry(styleId: "s1", category: .characters, url: URL(fileURLWithPath: "/tmp/char-1.jpg")),
        LensConceptChainEntry(styleId: "s1", category: .objects, url: URL(fileURLWithPath: "/tmp/object-1.jpg"))
    ]

    // Primary-style frame: same-style scenery only, most recent two — never studies.
    let primary = lensConceptContinuityURLs(assignedStyleId: "s1", chain: chain)
    #expect(primary.map(\.lastPathComponent) == ["scenery-2.jpg", "scenery-3.jpg"])

    // Accent-style frame: only the accent's own anchor take qualifies.
    let accent = lensConceptContinuityURLs(assignedStyleId: "s2", chain: chain)
    #expect(accent.map(\.lastPathComponent) == ["anchor-s2.jpg"])

    // No assignment (legacy): any scenery, still capped at two, still no studies.
    let legacy = lensConceptContinuityURLs(assignedStyleId: nil, chain: chain)
    #expect(legacy.count == 2)
    #expect(!legacy.map(\.lastPathComponent).contains("char-1.jpg"))
}

@Test
@MainActor
func objectStudyWithOwnLocationDropsAnchorSurroundings() {
    let engine = makeMediaPlanTestEngine()
    let lens = mediaPlanLens(scenePrompts: ["A civic lobby at dusk."])
    var sited = LensObjectConcept()
    sited.name = "pact mirror"
    sited.type = "hand mirror"
    sited.locationInScene = "leaning beside the dumpster in the Waikīkī alley"

    let sitedPrompt = engine.lensObjectConceptPrompt(
        concept: sited,
        prosePrompt: "",
        anchorSetting: nil,
        anchorProse: "A civic lobby at dusk.",
        theme: lens
    )
    #expect(sitedPrompt.contains("It lives here: leaning beside the dumpster"))
    #expect(!sitedPrompt.contains("The surroundings, kept secondary:"))

    var unsited = LensObjectConcept()
    unsited.name = "threshold phone"
    unsited.type = "smartphone"
    let unsitedPrompt = engine.lensObjectConceptPrompt(
        concept: unsited,
        prosePrompt: "",
        anchorSetting: nil,
        anchorProse: "A civic lobby at dusk.",
        theme: lens
    )
    #expect(unsitedPrompt.contains("The surroundings, kept secondary: A civic lobby at dusk."))
}

@Test
@MainActor
func structuredOnlyLensIsRenderableWithoutLegacyPromptArrays() {
    // v0.3 lenses carry structured world data and keep their legacy prose pools empty;
    // the regenerate gate must accept them (the old lensMediaPromptCategories-based
    // guard produced the false "no media prompts" error).
    let engine = makeMediaPlanTestEngine()
    var lens = mediaPlanLens(scenePrompts: ["placeholder"])
    var setting = LensSceneSetting()
    setting.title = "Coastal Work Yard"
    setting.locationName = "Farrington Highway"
    lens.body.sceneImagePrompts = nil
    lens.body.characterImagePrompts = nil
    lens.body.objectImagePrompts = nil
    lens.body.sceneSettings = [setting]
    var concept = LensObjectConcept()
    concept.name = "solar-mesh node"
    lens.body.objectConcepts = [concept]
    lens = lens.normalized()

    #expect(lens.body.sceneImagePrompts == nil)
    #expect(lens.body.hasRenderableMediaSources)

    let images = engine.queuedLensConceptImages(
        lens: lens,
        versionId: "v1",
        mediaSummaries: [],
        styleReferenceIds: []
    )
    #expect(!images.isEmpty)

    // normalized() synthesizes areas from the settings, and areas are a
    // renderable source in their own right — dropping the settings afterwards
    // must NOT strand the lens.
    var settingsFree = lens
    settingsFree.body.sceneSettings = nil
    #expect(settingsFree.body.hasRenderableMediaSources)

    // Only a lens with no areas, no settings, and no legacy scene prose has
    // nothing to anchor a media version on.
    var empty = lens
    empty.body.areas = nil
    empty.body.sceneSettings = nil
    #expect(!empty.body.hasRenderableMediaSources)
}

@Test
@MainActor
func characterStudyIsIsolatedFromAllSettings() {
    let engine = makeMediaPlanTestEngine()
    let lens = mediaPlanLens(scenePrompts: ["fallback"])
    var lobby = LensSceneSetting()
    lobby.title = "Leak Lobby"
    lobby.locationName = "Honolulu Hale entry lobby"
    lobby.timeOfDay = "afternoon"
    var alley = LensSceneSetting()
    alley.title = "Mirror Alley"
    alley.locationName = "rear alley behind a Waikīkī campaign office"
    alley.timeOfDay = "night"
    let settings = [lobby, alley]

    // Character studies are isolated, so NO setting may leak into the prompt —
    // not even an affinity-matched one.
    let matched = engine.lensCharacterConceptPrompt(
        name: "Rex",
        descriptionPrompt: "a rumpled fixer",
        signatureProps: [],
        environmentAffinity: "Mirror Alley",
        settings: settings,
        anchorProse: "A civic lobby at dusk.",
        theme: lens,
        mediaSummaries: []
    )
    #expect(matched.contains("clean isolated character study"))
    #expect(!matched.contains("rear alley behind a Waikīkī campaign office"))
    #expect(!matched.contains("Honolulu Hale entry lobby"))
    #expect(!matched.contains("A civic lobby at dusk."))
}

@Test
@MainActor
func setDressingCyclesDifferentSubsetsAcrossSceneryFrames() {
    let engine = makeMediaPlanTestEngine()
    var plan = LensMediaPlan()
    plan.compositeCount = 2
    plan.characterCount = 0
    plan.castObjectCount = 0
    plan.setDressingDensity = "rich"
    let lens = mediaPlanLens(
        scenePrompts: ["Place one.", "Place two."],
        setDressingPrompts: ["dressing A", "dressing B", "dressing C", "dressing D"],
        plan: plan
    )

    let images = engine.queuedLensConceptImages(
        lens: lens,
        versionId: "",
        mediaSummaries: [],
        styleReferenceIds: ["ref"]
    )
    // Rich = 3 per frame from a pool of 4, cycling: the two scene prompts must not
    // carry identical dressing lists.
    let sceneFrames = images.filter { $0.imageKind == LensImageTaxonomyKind.sceneImage }
    let anchorPrompt = sceneFrames.first { $0.sourceRouteKey.hasPrefix("lens_media_area_1_scene_1") }?.prompt ?? ""
    let secondPrompt = sceneFrames.first { $0.sourceRouteKey.hasPrefix("lens_media_area_1_scene_2") }?.prompt ?? ""
    #expect(anchorPrompt.contains("dressing A"))
    #expect(anchorPrompt.contains("dressing C"))
    #expect(!anchorPrompt.contains("dressing D"))
    #expect(secondPrompt.contains("dressing D"))
    #expect(anchorPrompt != secondPrompt)
}
