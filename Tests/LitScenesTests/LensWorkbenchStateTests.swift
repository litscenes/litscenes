import Foundation
import Testing
@testable import LitScenes

private func stateTestLens(
    treatment: LensStyleTreatment,
    imageStatus: String = "ready",
    snapshotRecipe: String? = nil,
    provenanceSuffix: String = ""
) -> ProjectLens {
    var body = LensBody()
    body.title = "State Lens"
    body.claim = "Claim."
    body.styleTreatment = treatment
    var image = ProjectLensHeroImage(
        imageId: "lens_hero_state_test",
        imageIndex: 0,
        label: "Composite 1",
        provider: "openai",
        model: "gpt-image-2",
        imagePath: "",
        prompt: "prompt",
        sourcePrompt: "prompt",
        negativePrompt: "",
        promptEnrichmentModel: "",
        promptEnrichmentResponseId: "",
        promptEnrichmentTraceId: "",
        promptEnrichmentSummary: "",
        status: "queued",
        requestId: "",
        traceId: "",
        errorMessage: "",
        sourceRouteKey: "lens_media_composite_1@v1",
        sourceRecipeId: nil,
        sourceRecipeVersion: nil,
        sourceAestheticIds: [],
        generatedAt: "",
        updatedAt: DateFormats.now()
    )
    image.status = imageStatus
    image.imagePath = imageStatus == "ready" ? "/tmp/composite.jpg" : ""
    if let snapshotRecipe {
        image.sourceRecipeVersion = provenanceSuffix.isEmpty ? snapshotRecipe : "\(snapshotRecipe) | \(provenanceSuffix)"
    }
    return ProjectLens(
        lensId: "lens_state",
        status: .ready,
        enabled: true,
        body: body,
        heroImage: nil,
        heroImages: [image],
        relationSummary: .empty,
        createdAt: DateFormats.now(),
        updatedAt: DateFormats.now()
    ).normalized()
}

private func stateTreatment(weights: [Int]) -> LensStyleTreatment {
    LensStyleTreatment(
        catalogVersion: "v-test",
        primary: LensStyleTreatmentSlot(styleId: "p", label: "P", weight: weights[0]),
        accents: weights.dropFirst().enumerated().map { index, weight in
            LensStyleTreatmentSlot(styleId: "a\(index)", label: "A\(index)", weight: weight)
        }
    ).normalized()
}

@Test
func treatmentStateDerivesCleanEditedRenderingAndChangedSinceRender() {
    let treatment = stateTreatment(weights: [60, 25, 15])

    // Clean: drafts match, image ready with matching snapshot.
    let cleanLens = stateTestLens(treatment: treatment, snapshotRecipe: treatment.recipeText)
    #expect(LensTreatmentState.derive(
        lens: cleanLens, treatment: treatment, draftedTreatment: treatment, isEngineBusy: false
    ).phase == .clean)

    // Edited: drafted weights differ.
    let drafted = stateTreatment(weights: [45, 30, 25])
    let editedState = LensTreatmentState.derive(
        lens: cleanLens, treatment: treatment, draftedTreatment: drafted, isEngineBusy: false
    )
    #expect(editedState.phase == .edited(diff: "60 · 25 · 15 → 45 · 30 · 25"))

    // Rendering wins over everything.
    let renderingLens = stateTestLens(treatment: treatment, imageStatus: "generating")
    #expect(LensTreatmentState.derive(
        lens: renderingLens, treatment: treatment, draftedTreatment: drafted, isEngineBusy: false
    ).phase == .rendering)

    // Changed since render: snapshot recipe differs from the saved treatment.
    let staleLens = stateTestLens(treatment: treatment, snapshotRecipe: "50% P · 50% A0")
    #expect(LensTreatmentState.derive(
        lens: staleLens, treatment: treatment, draftedTreatment: treatment, isEngineBusy: false
    ).phase == .changedSinceRender)
}

@Test
func treatmentStateComparesRecipePartOfPlanSuffixedProvenance() {
    let treatment = stateTreatment(weights: [60, 25, 15])
    // Provenance carries a plan suffix; only the recipe part should be compared.
    let lens = stateTestLens(
        treatment: treatment,
        snapshotRecipe: treatment.recipeText,
        provenanceSuffix: "seq · 3:2 · 2C+1O"
    )
    #expect(LensTreatmentState.derive(
        lens: lens, treatment: treatment, draftedTreatment: treatment, isEngineBusy: false
    ).phase == .clean)
}

@Test
func treatmentSnapshotIdentifierRoundTripsLosslessly() {
    let treatment = stateTreatment(weights: [55, 30, 15])
    let identifier = treatment.snapshotIdentifier
    #expect(identifier.hasPrefix(LensStyleTreatment.snapshotPrefix))
    let restored = LensStyleTreatment.fromSnapshotIdentifier(identifier)
    #expect(restored == treatment)
    #expect(LensStyleTreatment.fromSnapshotIdentifier("garbage") == nil)
    #expect(LensStyleTreatment.fromSnapshotIdentifier(nil) == nil)
}

@Test
@MainActor
func queuedCompositesCarryLosslessTreatmentSnapshots() {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_snapshot_\(UUID().uuidString)", isDirectory: true)
    let engine = LibraryEngine(projectLibrary: ProjectLibrary(root: root))
    let treatment = stateTreatment(weights: [70, 30])
    var body = LensBody()
    body.title = "Snapshot Lens"
    body.claim = "Claim."
    body.visualSummary = "Summary."
    body.sceneImagePrompts = ["A scene."]
    body.characterImagePrompts = ["A figure."]
    body.styleTreatment = treatment
    let lens = ProjectLens(
        lensId: "lens_snapshot",
        status: .ready,
        enabled: true,
        body: body,
        heroImage: nil,
        heroImages: [],
        relationSummary: .empty,
        createdAt: DateFormats.now(),
        updatedAt: DateFormats.now()
    ).normalized()

    let images = engine.queuedLensConceptImages(
        lens: lens,
        versionId: "v9",
        mediaSummaries: [],
        styleReferenceIds: ["ref"]
    )

    #expect(!images.isEmpty)
    for image in images {
        let restored = LensStyleTreatment.fromSnapshotIdentifier(image.sourceRecipeId)
        #expect(restored?.weightSummary == lens.body.styleTreatment?.weightSummary)
    }
}

@Test
func heroImageKeptFlagRoundTripsAndDefaultsNil() throws {
    var image = ProjectLensHeroImage(imageId: "img_kept_test")
    image.kept = true
    let data = try JSONCoding.encoder.encode(image)
    let decoded = try JSONCoding.decoder.decode(ProjectLensHeroImage.self, from: data)
    #expect(decoded.kept == true)

    // Legacy payloads without the key decode with kept == nil.
    let legacy = try JSONCoding.decoder.decode(
        ProjectLensHeroImage.self,
        from: Data(#"{"imageId": "img_legacy"}"#.utf8)
    )
    #expect(legacy.kept == nil)
}
