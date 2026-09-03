import Foundation
import Testing
@testable import LitScenes

private func trioCandidate(_ index: Int, collection: String) -> LensContextStyleCandidate {
    let json = """
    {
      "style_id": "style-\(index)",
      "title": "Style \(index)",
      "label": "Style \(index) Label",
      "caption": "Caption \(index)",
      "image_url": "https://example.cloudfront.net/\(index).png",
      "collection_key": "\(collection)",
      "collection_name": "\(collection.capitalized)",
      "secondary_collection": "",
      "moods": ["Calm"],
      "hue_name": "Blue",
      "hue_hex": "#3457a8",
      "medium": "Digital painting",
      "scalar_sat": 3, "scalar_con": 2, "scalar_ser": 2, "scalar_lin": 1, "scalar_sty": 2,
      "score": \(100 - index), "match_count": 3, "matched_terms": [],
      "positive_prompt_atoms": [], "negative_prompt_atoms": [], "transferable_traits": []
    }
    """
    return try! JSONCoding.decoder.decode(LensContextStyleCandidate.self, from: Data(json.utf8))
}

private func trioSlice(title: String, primary: Int, accents: [Int], profile: String = "dominant") -> LensTrioSliceResponse {
    var slice = LensTrioSliceResponse()
    slice.sliceTitle = title
    slice.title = "\(title) Lens"
    slice.claim = "Claim for \(title)."
    slice.primaryStyleIndex = primary
    slice.accentStyleIndexes = accents
    slice.blendProfile = profile
    return slice
}

@MainActor
private func makeTrioTestEngine() -> LibraryEngine {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_lens_trio_repair_\(UUID().uuidString)", isDirectory: true)
    return LibraryEngine(projectLibrary: ProjectLibrary(root: root))
}

@Test
@MainActor
func lensTrioRepairAcceptsValidDiverseSelections() {
    let engine = makeTrioTestEngine()
    let candidates = [
        trioCandidate(0, collection: "nocturne"),
        trioCandidate(1, collection: "neon"),
        trioCandidate(2, collection: "anime"),
        trioCandidate(3, collection: "ink"),
        trioCandidate(4, collection: "dream"),
        trioCandidate(5, collection: "pop")
    ]
    let trio = LensTrioResponse(lenses: [
        trioSlice(title: "Vigil", primary: 0, accents: [3, 4]),
        trioSlice(title: "Reverie", primary: 1, accents: [4, 5], profile: "anchored"),
        trioSlice(title: "Alarum", primary: 2, accents: [5, 3], profile: "ensemble")
    ])

    let (repaired, warnings) = engine.repairedLensTrioSelections(trio, candidates: candidates)

    #expect(warnings.isEmpty)
    #expect(repaired.count == 3)
    #expect(repaired.map(\.primaryIndex) == [0, 1, 2])
    #expect(repaired[0].accentIndexes == [3, 4])
    #expect(repaired[1].profile == .anchored)
    #expect(repaired[2].profile == .ensemble)
    #expect(repaired[0].profile.weights.primary == 60)
    #expect(repaired[1].profile.weights.accentTwo == 25)
    #expect(repaired[2].profile.weights.primary == 40)
}

@Test
@MainActor
func lensTrioRepairFixesCollisionsAndInvalidIndexes() {
    let engine = makeTrioTestEngine()
    let candidates = [
        trioCandidate(0, collection: "nocturne"),
        trioCandidate(1, collection: "nocturne"),
        trioCandidate(2, collection: "anime"),
        trioCandidate(3, collection: "ink"),
        trioCandidate(4, collection: "dream")
    ]
    let trio = LensTrioResponse(lenses: [
        trioSlice(title: "One", primary: 0, accents: [1, 2]),
        // Collection collision with lens one; accent 2 (anime) should be promoted.
        trioSlice(title: "Two", primary: 1, accents: [2, 3]),
        // Out-of-range primary and a duplicate accent; both repaired from the slate.
        trioSlice(title: "Three", primary: 99, accents: [3, 3])
    ])

    let (repaired, warnings) = engine.repairedLensTrioSelections(trio, candidates: candidates)

    #expect(!warnings.isEmpty)
    #expect(repaired.count == 3)
    let primaries = repaired.map(\.primaryIndex)
    #expect(Set(primaries).count == 3)
    let primaryCollections = primaries.map { candidates[$0].collectionKey }
    #expect(Set(primaryCollections).count == 3)
    for entry in repaired {
        #expect(entry.accentIndexes.count == 2)
        #expect(!entry.accentIndexes.contains(entry.primaryIndex))
        #expect(Set(entry.accentIndexes).count == 2)
    }
    // Lens two keeps its old primary in the blend as an accent after the promotion.
    #expect(repaired[1].primaryIndex == 2)
    #expect(repaired[1].accentIndexes.contains(1))
}

@Test
func lensCompositionResponseDecodesWithoutTrioEraFields() throws {
    let json = """
    {
      "schema_version": "litscenes.lens_composition.v0.1",
      "lens": {
        "title": "Vigil Lens",
        "claim": "The night keeps what the day trades away.",
        "visual_summary": "Low-key stillness.",
        "look": "Rain-lit dark with warm practical glow.",
        "palette": ["teal", "amber"],
        "materials": ["wet asphalt"],
        "motifs": ["mirror thresholds"],
        "composition": ["cramped frames"],
        "pacing_energy": ["slow"],
        "avoid": ["flat daylight"],
        "must_preserve": ["low-key values"],
        "must_avoid": ["pastel haze"],
        "scene_image_prompts": ["A rain-slick lanai at night.", "An empty arcade doorway at dusk."],
        "character_image_prompts": ["A gecko on the lanai rail.", "A figure in the doorway glow."],
        "object_image_prompts": ["A phone face-down on the rail.", "A hand mirror catching neon."],
        "primary_style_index": 0,
        "accent_style_indexes": [1, 2],
        "blend_profile": "anchored",
        "style_rationale": "Nocturne carries the vigil."
      }
    }
    """
    let decoded = try JSONCoding.decoder.decode(LensCompositionResponse.self, from: Data(json.utf8))
    #expect(decoded.lens.title == "Vigil Lens")
    #expect(decoded.lens.sliceTitle.isEmpty)
    #expect(decoded.lens.sceneImagePrompts.count == 2)
    #expect(decoded.lens.primaryStyleIndex == 0)
    #expect(decoded.lens.blendProfile == "anchored")
}

@Test
func lensMediaVersionsGroupByRouteKeySuffix() {
    var lens = ProjectLens(
        lensId: "lens_test",
        status: .ready,
        enabled: true,
        body: LensBody.empty(),
        heroImage: nil,
        heroImages: [],
        relationSummary: .empty,
        createdAt: DateFormats.now(),
        updatedAt: DateFormats.now()
    )
    func image(_ id: String, routeKey: String, index: Int) -> ProjectLensHeroImage {
        ProjectLensHeroImage(
            imageId: id, imageIndex: index, label: "", provider: "openai", model: "gpt-image-2",
            imagePath: "", prompt: "p", sourcePrompt: "p", negativePrompt: "",
            promptEnrichmentModel: "", promptEnrichmentResponseId: "", promptEnrichmentTraceId: "",
            promptEnrichmentSummary: "", status: "ready", requestId: "", traceId: "",
            errorMessage: "", sourceRouteKey: routeKey, sourceRecipeId: nil, sourceRecipeVersion: nil,
            sourceAestheticIds: [], generatedAt: "", updatedAt: DateFormats.now()
        )
    }
    lens.heroImages = [
        image("a", routeKey: "lens_media_scene", index: 0),
        image("b", routeKey: "lens_media_character", index: 1),
        image("c", routeKey: "lens_media_object", index: 2),
        image("d", routeKey: "lens_media_scene@v2abc", index: 0),
        image("e", routeKey: "lens_media_character@v2abc", index: 1)
    ]

    #expect(lens.mediaVersionIds == ["", "v2abc"])
    #expect(lens.heroImages(mediaVersion: "").map(\.imageId) == ["a", "b", "c"])
    #expect(lens.heroImages(mediaVersion: "v2abc").map(\.imageId) == ["d", "e"])
    #expect(ProjectLens.mediaVersionId(fromRouteKey: "lens_media_scene") == "")
    #expect(ProjectLens.mediaVersionId(fromRouteKey: "lens_media_object@zz99") == "zz99")
}

@Test
func updateActiveVersionPersistsImagesWithoutGrowingHistory() {
    var document = ProjectLensSetDocument.bootstrap(projectId: "project_test")
    var lens = ProjectLens(
        lensId: "lens_v",
        status: .ready,
        enabled: true,
        body: LensBody.empty(),
        heroImage: nil,
        heroImages: [],
        relationSummary: .empty,
        createdAt: DateFormats.now(),
        updatedAt: DateFormats.now()
    )
    var image = ProjectLensHeroImage(
        imageId: "img_1", imageIndex: 0, label: "Scene", provider: "openai", model: "gpt-image-2",
        imagePath: "", prompt: "p", sourcePrompt: "p", negativePrompt: "",
        promptEnrichmentModel: "", promptEnrichmentResponseId: "", promptEnrichmentTraceId: "",
        promptEnrichmentSummary: "", status: "queued", requestId: "", traceId: "",
        errorMessage: "", sourceRouteKey: "lens_media_scene", sourceRecipeId: nil,
        sourceRecipeVersion: "60% A · 25% B · 15% C",
        sourceAestheticIds: [], generatedAt: "", updatedAt: DateFormats.now()
    )
    lens.heroImages = [image]
    document.appendVersion(
        lenses: [lens],
        scratchDrafts: [],
        selectedLensId: lens.lensId,
        selectedScratchId: nil,
        changeSummary: "Generated a Lens.",
        model: "test",
        now: DateFormats.now()
    )
    let versionCount = document.versions.count
    let activeId = document.activeVersionId

    image.status = "ready"
    image.imagePath = "/tmp/x.jpg"
    lens.heroImages = [image]
    document.updateActiveVersion(lenses: [lens], now: DateFormats.now())

    #expect(document.versions.count == versionCount)
    #expect(document.activeVersionId == activeId)
    #expect(document.lenses.first?.heroImages.first?.status == "ready")
    #expect(document.lenses.first?.blendSnapshot(mediaVersion: "") == "60% A · 25% B · 15% C")
}

@Test
func treatmentWeightSummaryIsCompactPercentages() {
    let treatment = LensStyleTreatment(
        catalogVersion: "v1",
        primary: LensStyleTreatmentSlot(styleId: "a", label: "Alpha", weight: 60),
        accents: [
            LensStyleTreatmentSlot(styleId: "b", label: "Beta", weight: 25),
            LensStyleTreatmentSlot(styleId: "c", label: "Gamma", weight: 15)
        ]
    ).normalized()
    #expect(treatment.weightSummary == "60 · 25 · 15")
    #expect(treatment.recipeText.contains("60% Alpha"))
}

@Test
@MainActor
func interruptedGeneratingMediaReconcilesToRetryableFailures() {
    var lens = ProjectLens(
        lensId: "lens_r",
        status: .ready,
        enabled: true,
        body: LensBody.empty(),
        heroImage: nil,
        heroImages: [],
        relationSummary: .empty,
        createdAt: DateFormats.now(),
        updatedAt: DateFormats.now()
    )
    func image(_ id: String, status: String) -> ProjectLensHeroImage {
        ProjectLensHeroImage(
            imageId: id, imageIndex: 0, label: "Composite 1", provider: "openai", model: "gpt-image-2",
            imagePath: "", prompt: "p", sourcePrompt: "p", negativePrompt: "",
            promptEnrichmentModel: "", promptEnrichmentResponseId: "", promptEnrichmentTraceId: "",
            promptEnrichmentSummary: "", status: status, requestId: "", traceId: "",
            errorMessage: "", sourceRouteKey: "lens_media_composite_1", sourceRecipeId: nil,
            sourceRecipeVersion: nil, sourceAestheticIds: [], generatedAt: "", updatedAt: DateFormats.now()
        )
    }
    lens.heroImages = [
        image("stuck_queued", status: "queued"),
        image("stuck_generating", status: "generating"),
        image("done", status: "ready"),
        image("already_failed", status: "failed")
    ]
    lens.generationPhase = "hero_generating"
    lens.generationError = "Rendering was interrupted."

    let (reconciled, changedCount) = LibraryEngine.lensesWithInterruptedMediaReconciled([lens], now: DateFormats.now())

    #expect(changedCount == 1)
    let repaired = reconciled[0]
    let statusById = Dictionary(uniqueKeysWithValues: repaired.heroImages.map { ($0.imageId, $0.status) })
    // Only generating rows were interrupted mid-flight; queued rows are the
    // planned frame slate and must survive a relaunch untouched.
    #expect(statusById["stuck_queued"] == "queued")
    #expect(statusById["stuck_generating"] == "failed")
    #expect(statusById["done"] == "ready")
    #expect(statusById["already_failed"] == "failed")
    let interrupted = repaired.heroImages.first { $0.imageId == "stuck_generating" }
    #expect(interrupted?.errorMessage == "Rendering was interrupted for this media.")
    let planned = repaired.heroImages.first { $0.imageId == "stuck_queued" }
    #expect(planned?.errorMessage == "")
    // Hero phases clear the lens-level error rather than stamping one.
    #expect(repaired.generationError == "")

    // A second pass is a no-op: no generating rows remain (the surviving
    // queued row is legitimate planned work, not an interruption).
    let (untouched, noChanges) = LibraryEngine.lensesWithInterruptedMediaReconciled(reconciled, now: DateFormats.now())
    #expect(noChanges == 0)
    #expect(untouched[0].heroImages.map(\.status) == repaired.heroImages.map(\.status))
}

@Test
func compositeCharacterCountClampsAndDefaults() {
    var body = LensBody.empty()
    #expect(body.resolvedCompositeCharacterCount == 2)
    body.compositeCharacterCount = 7
    #expect(body.normalized().compositeCharacterCount == 3)
    body.compositeCharacterCount = -1
    #expect(body.normalized().compositeCharacterCount == 0)
    body.compositeCharacterCount = nil
    #expect(body.normalized().resolvedCompositeCharacterCount == 2)
}
