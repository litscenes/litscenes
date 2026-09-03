import Foundation
import SQLite3
import Testing
@testable import LitScenes

@Test
func newStrictSchemasDoNotContainCreativeConfidenceFields() throws {
    for schemaName in [
        "project_goal_v0_3.schema",
        "project_goal_interview_v0_4.schema",
        "project_lens_set_v0_1.schema",
        "project_lens_workbench_interview_v0_1.schema"
    ] {
        let url = try packagedResourceURL(named: schemaName, extension: "json")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("confidence_"))
        #expect(!text.contains("text_confidence"))
        #expect(!text.contains("visual_confidence"))
        #expect(!text.contains("overall_confidence"))
    }
}

@Test
func newStrictSchemasCloseEveryObjectShape() throws {
    for schemaName in [
        "project_goal_v0_3.schema",
        "project_goal_interview_v0_4.schema",
        "project_lens_set_v0_1.schema",
        "project_lens_workbench_interview_v0_1.schema"
    ] {
        let url = try packagedResourceURL(named: schemaName, extension: "json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        #expect(openObjectPaths(in: object).isEmpty)
    }
}

@Test
func goalV2MessagesDoNotCreateSavedReadiness() {
    var goal = ProjectGoalDocumentV2.empty(projectId: "project")

    goal.appendMessage(role: .user, text: "Make this feel like a field note.", now: "2026-06-15T00:00:00.000Z")

    #expect(goal.messages.count == 1)
    #expect(goal.versions.isEmpty)
    #expect(goal.activeVersion == nil)
    #expect(goal.isReady == false)
}

@Test
func goalV2SavedVersionIsReadinessBoundary() {
    var goal = ProjectGoalDocumentV2.empty(projectId: "project")
    goal.appendMessage(role: .user, text: "This is for a narrative short.", now: "2026-06-15T00:00:00.000Z")
    goal.appendMessage(role: .assistant, text: "I updated the Goal.", now: "2026-06-15T00:00:01.000Z")

    goal.appendVersion(
        brief: ProjectGoalBriefV2(
            contentType: .narrative,
            goal: "Turn the archive into a narrative short about returning home.",
            audience: "Family and close collaborators.",
            desiredResponse: "Feel the archive has a clear emotional purpose.",
            viewerExperience: "Warm, reflective, and grounded.",
            successCriteria: ["The viewer understands the emotional turn."],
            constraints: ["Avoid platform planning."],
            openQuestions: [],
            lensSeedSummary: "Soft domestic texture.",
            lensSeedTerms: ["warm light", "quiet rooms"]
        ),
        changeSummary: "Defined the narrative Goal.",
        model: "test",
        now: "2026-06-15T00:00:02.000Z"
    )

    #expect(goal.activeVersion != nil)
    #expect(goal.activeVersion?.turnIndex == 2)
    #expect(goal.isReady)
    #expect(goal.activeBrief.contentType == .narrative)
}

@Test
func legacyGoalV2WithoutRequiredEntitiesDecodesAndReencodes() throws {
    let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    let data = try Data(contentsOf: fixtures.appendingPathComponent("project_goal_v0_2_without_required_entities.json"))
    let document = try ProjectGoalDocumentV2.decode(from: data)

    #expect(document.activeBrief.requiredEntities.isEmpty)
    #expect(document.activeVersion?.validationWarnings.isEmpty == true)

    let encoded = try document.encoded(pretty: false)
    let text = String(decoding: encoded, as: UTF8.self)
    #expect(text.contains("required_entities"))
    #expect(text.contains("validation_warnings"))
    _ = try ProjectGoalDocumentV2.decode(from: encoded)
}

@Test
func goalV2RequiredEntitiesAffectGoalFingerprintSeed() {
    let base = ProjectGoalBriefV2(
        contentType: .narrative,
        goal: "Make a short about a workshop.",
        audience: "Neighbors.",
        desiredResponse: "Curious.",
        viewerExperience: "Grounded."
    )
    var withEntity = base
    withEntity.requiredEntities = [
        ProjectGoalRequiredEntity(name: "Rainforge Tools", role: "mandatory organization", required: true)
    ]
    let baseVersion = ProjectGoalBriefVersionV2(
        versionId: "goal_v2_same",
        turnIndex: 1,
        brief: base.normalized(),
        changeSummary: "base",
        createdAt: "2026-06-24T00:00:00Z",
        model: "test"
    )
    let entityVersion = ProjectGoalBriefVersionV2(
        versionId: "goal_v2_same",
        turnIndex: 1,
        brief: withEntity.normalized(),
        changeSummary: "entity",
        createdAt: "2026-06-24T00:00:00Z",
        model: "test"
    )

    let baseFingerprint = stableHash(LensContextGoalFingerprintSeed(projectId: "project", versionId: baseVersion.versionId, brief: baseVersion.brief))
    let entityFingerprint = stableHash(LensContextGoalFingerprintSeed(projectId: "project", versionId: entityVersion.versionId, brief: entityVersion.brief))
    #expect(baseFingerprint != entityFingerprint)
}

@Test
func goalV2RequiredEntitySanitizerUsesOnlyUserTextProvenance() {
    let current = ProjectGoalBriefV2(
        goal: "Existing goal.",
        requiredEntities: [ProjectGoalRequiredEntity(name: "Existing Studio", role: "mandatory organization", required: true)]
    )
    let emitted = ProjectGoalBriefV2(
        goal: "Updated goal.",
        requiredEntities: [
            ProjectGoalRequiredEntity(name: "Existing Studio", role: "changed role", required: true),
            ProjectGoalRequiredEntity(name: "Mira Chen", role: "mandatory guide", required: true),
            ProjectGoalRequiredEntity(name: "Image Person", role: "image-only person", required: true),
            ProjectGoalRequiredEntity(name: "Optional Hall", role: "optional place", required: false)
        ]
    )
    let messages = [
        ProjectGoalMessageV2(messageId: "one", role: .user, text: "Please make Mira Chen mandatory in the observatory Story.", mediaIds: [], createdAt: "now"),
        ProjectGoalMessageV2(messageId: "two", role: .user, text: "Attached image.", mediaIds: ["media_image"], createdAt: "now")
    ]

    let sanitized = sanitizeInterviewRequiredEntities(brief: emitted, currentBrief: current, userMessages: messages)
    #expect(sanitized.brief.requiredEntities.map(\.name) == ["Existing Studio", "Mira Chen"])
    #expect(sanitized.brief.requiredEntities.first?.role == "mandatory organization")
    #expect(sanitized.warnings.contains { $0.contains("Image Person") })
    #expect(sanitized.warnings.contains { $0.contains("Optional Hall") })
}

@Test
func goalV2RequiredEntityDedupesDeterministically() {
    let result = uniqueRequiredGoalEntities([
        ProjectGoalRequiredEntity(name: "  Luna Observatory  ", role: "mandatory place", required: true),
        ProjectGoalRequiredEntity(name: "luna observatory", role: "conflicting role", required: true),
        ProjectGoalRequiredEntity(name: "", role: "blank", required: true)
    ])

    #expect(result.entities.count == 1)
    #expect(result.entities[0].name == "Luna Observatory")
    #expect(result.entities[0].role == "mandatory place")
    #expect(result.warnings.contains { $0.contains("kept the first role") })
}

@Test
func storyNoveltyPolicyDefaultAndLegacyArchitectureDecodeRemainCompatible() throws {
    #expect(StoryNoveltyPolicy().normalized().minDifferingDimensions == 0)

    let blueprintJSON = """
    {
      "story_form": "dramatic_arc",
      "architecture_family": "unspecified",
      "primary_actor": "Legacy actor",
      "acting_force": "Legacy force",
      "causal_engine": "Legacy engine",
      "setting_progression": [],
      "primary_meaning_move": "Legacy move",
      "compass_destination": "Legacy destination",
      "payoff_mechanism": "Legacy payoff",
      "core_visual_image": "Legacy image"
    }
    """
    let blueprint = try JSONCoding.decoder.decode(StoryBlueprint.self, from: Data(blueprintJSON.utf8))
    #expect(blueprint.architectureFamily == .unspecified)
}

@Test
func sceneStoryDesktopSourceDoesNotHardCodeLegacyNoveltyOrLambdaPromptVersion() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceURL = packageRoot.appendingPathComponent("Sources/LitScenes/LibraryEngine.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(!source.contains("at least four Story Blueprint dimensions"))
    #expect(!source.contains("Realize the requested architecture family"))
    #expect(!source.contains("litscenes.scene_story_prompt.v0.6"))
}

@Test
func readyLensSetHashExcludesScratchAndDraftLenses() {
    let ready = testLens(
        id: "lens_ready",
        status: .ready,
        title: "Ready Lens",
        visualSummary: "Sharp daylight, clean edges, tactile product detail."
    )
    let draft = testLens(
        id: "lens_draft",
        status: .draft,
        title: "Draft Lens",
        visualSummary: "This draft should not affect generation."
    )
    let scratch = LensScratchDraft(
        scratchId: "scratch_one",
        body: LensBody(title: "Scratch", claim: "Workbench only", visualSummary: "Scratch visual language."),
        createdAt: "2026-06-15T00:00:00.000Z",
        updatedAt: "2026-06-15T00:00:00.000Z"
    )
    var mixed = ProjectLensSetDocument.empty(projectId: "project")
    mixed.appendVersion(
        lenses: [ready, draft],
        scratchDrafts: [scratch],
        selectedLensId: nil,
        selectedScratchId: scratch.scratchId,
        changeSummary: "mixed",
        model: "test",
        now: "2026-06-15T00:00:00.000Z"
    )
    var readyOnly = ProjectLensSetDocument.empty(projectId: "project")
    readyOnly.appendVersion(
        lenses: [ready],
        scratchDrafts: [],
        selectedLensId: nil,
        selectedScratchId: nil,
        changeSummary: "ready",
        model: "test",
        now: "2026-06-15T00:00:00.000Z"
    )

    #expect(computeReadyLensSetHash(mixed) == computeReadyLensSetHash(readyOnly))
}

@Test
func readyLensSetHashChangesWhenReadyLensContentChanges() {
    var first = ProjectLensSetDocument.empty(projectId: "project")
    first.appendVersion(
        lenses: [testLens(id: "lens_ready", status: .ready, title: "Ready Lens", visualSummary: "Soft neon kitchen ritual.")],
        scratchDrafts: [],
        selectedLensId: nil,
        selectedScratchId: nil,
        changeSummary: "first",
        model: "test",
        now: "2026-06-15T00:00:00.000Z"
    )
    var second = ProjectLensSetDocument.empty(projectId: "project")
    second.appendVersion(
        lenses: [testLens(id: "lens_ready", status: .ready, title: "Ready Lens", visualSummary: "Hard flash kitchen ritual.")],
        scratchDrafts: [],
        selectedLensId: nil,
        selectedScratchId: nil,
        changeSummary: "second",
        model: "test",
        now: "2026-06-15T00:00:01.000Z"
    )

    #expect(computeReadyLensSetHash(first) != computeReadyLensSetHash(second))
}

@Test
func projectLensHeroImageRoundTripsInLensSetDocument() throws {
    let heroImage = ProjectLensHeroImage(
        imageId: "lens_hero_one",
        imagePath: "/tmp/lens_hero_one.jpg",
        prompt: "Create a square hero image.",
        status: "ready",
        requestId: "req_123",
        sourceRouteKey: "route_abc",
        sourceRecipeId: "recipe_abc",
        sourceRecipeVersion: "v1",
        sourceAestheticIds: ["aesthetic_one"],
        generatedAt: "2026-06-15T00:00:01.000Z",
        updatedAt: "2026-06-15T00:00:01.000Z"
    )
    let lens = testLens(
        id: "lens_draft",
        status: .draft,
        title: "Draft Lens",
        visualSummary: "One generated hero image anchors this draft.",
        heroImage: heroImage
    )
    var document = ProjectLensSetDocument.empty(projectId: "project")
    document.appendVersion(
        lenses: [lens],
        scratchDrafts: [],
        selectedLensId: lens.lensId,
        selectedScratchId: nil,
        changeSummary: "generated draft lenses",
        model: "test",
        now: "2026-06-15T00:00:02.000Z"
    )

    let decoded = try ProjectLensSetDocument.decode(from: document.encoded())

    #expect(decoded.lenses.first?.heroImage?.imageId == "lens_hero_one")
    #expect(decoded.lenses.first?.heroImage?.status == "ready")
    #expect(decoded.lenses.first?.heroImage?.sourceAestheticIds == ["aesthetic_one"])
}

@Test
func initialDraftLensGenerationProgressTracksFractionAndActivity() {
    #expect(InitialDraftLensGenerationProgress.idle.isActive == false)
    #expect(InitialDraftLensGenerationProgress.idle.fractionCompleted == 0)

    let progress = InitialDraftLensGenerationProgress(
        title: "Generating Lens hero 2/3",
        detail: "Draft Lens",
        completedStepCount: 6,
        totalStepCount: 7,
        lensTitles: ["One", "Two", "Three"],
        heroStatuses: ["ready", "generating", "queued"]
    )

    #expect(progress.isActive)
    #expect(progress.fractionCompleted > 0.85)
    #expect(progress.fractionCompleted < 0.86)
    #expect(progress.heroStatuses == ["ready", "generating", "queued"])
}

@Test
func lensRowSnapshotsExposeLensIdsForRelationScanning() {
    let lens = testLens(
        id: "lens_ready",
        status: .ready,
        title: "Ready Lens",
        visualSummary: "Tactile morning light."
    )
    var document = ProjectLensSetDocument.empty(projectId: "project")
    document.appendVersion(
        lenses: [lens],
        scratchDrafts: [],
        selectedLensId: nil,
        selectedScratchId: nil,
        changeSummary: "ready",
        model: "test",
        now: "2026-06-15T00:00:00.000Z"
    )

    let snapshots = lensRowSnapshots(from: document)

    #expect(snapshots.count == 1)
    #expect(snapshots.first?.lensId == "lens_ready")
    #expect(snapshots.first?.snapshotHash.isEmpty == false)
}

@Test
func lensSchemasExposeResolvedVisualLanguageWithoutConfidenceFields() throws {
    let workbenchURL = try packagedResourceURL(named: "project_lens_workbench_interview_v0_1.schema", extension: "json")
    let persistedURL = try packagedResourceURL(named: "project_lens_set_v0_1.schema", extension: "json")
    let workbench = try String(contentsOf: workbenchURL, encoding: .utf8)
    let persisted = try String(contentsOf: persistedURL, encoding: .utf8)

    #expect(workbench.contains("resolved_visual_language"))
    #expect(workbench.contains("product_treatment"))
    #expect(persisted.contains("resolved_visual_language"))
    #expect(!workbench.contains("confidence_"))
    #expect(!persisted.contains("confidence_"))
}

@Test
func lensReadinessBlocksMalformedResolvedProductionLanguage() {
    let body = LensBody(
        title: "Angelcore Aloha",
        claim: "Make tallow feel reassuring.",
        visualSummary: "Soft product imagery.",
        resolvedVisualLanguage: LensResolvedVisualLanguage(
            look: "Archive supports a soft route.",
            palette: ["Angelcore"],
            materials: ["It is typically approached"],
            productTreatment: ["smooth balm"],
            motifs: ["Benevolent aspects of angelic beings"],
            composition: ["website landing visuals"],
            pacingEnergy: ["warm"],
            avoid: ["halos"]
        ),
        styleIngredients: [
            LensStyleIngredient(
                ingredientId: "ingredient_angelcore",
                order: 1,
                title: "Angelcore",
                role: "source",
                narrativeUse: "",
                presentationUse: "",
                notes: ""
            )
        ],
        mustPreserve: ["Center the three stated tallow truths."],
        mustAvoid: ["Center the three stated tallow truths."]
    )

    let report = body.readinessReport

    #expect(!report.isReady)
    #expect(report.blockingIssues.contains(.sourceTaxonomyInResolvedLanguage))
    #expect(report.blockingIssues.contains(.positiveRequirementInMustAvoid))
    #expect(report.blockingIssues.contains(.contradictoryPreserveAvoid))
    #expect(report.blockingIssues.contains(.provenancePhraseInProductionField))
    #expect(report.blockingIssues.contains(.compositionMissingGuidance))
}

@Test
func lensReadinessAllowsCorrectedLensWithoutReferenceMedia() {
    let body = LensBody(
        title: "Soft Tallow Reassurance",
        claim: "Care is demonstrated by purposeful nourishment.",
        visualSummary: "Soft, luminous, cream-and-botanical handmade skincare imagery.",
        resolvedVisualLanguage: LensResolvedVisualLanguage(
            look: "Soft, luminous, cream-and-botanical handmade skincare imagery.",
            palette: ["whipped cream", "warm ivory", "pale sage", "leaf green", "soft gold", "muted amber"],
            materials: ["linen", "warm wood", "amber glass", "round metal tins"],
            productTreatment: ["smooth airy whipped balm", "cloudlike texture", "satin highlights", "never wet or greasy-looking"],
            motifs: ["fine-line botanical details", "rounded tins", "founder-and-dog close-ups"],
            composition: ["intimate founder-and-product framing", "shallow-depth product details", "one dominant visual action per scene"],
            pacingEnergy: ["calm", "warm", "lightly mischievous"],
            avoid: ["halos", "wings", "cherubs", "religious iconography", "fantasy angel characters", "wet greasy shine"]
        ),
        styleIngredients: [
            LensStyleIngredient(
                ingredientId: "ingredient_source",
                order: 1,
                title: "Angelcore",
                role: "source",
                narrativeUse: "Source inspiration only.",
                presentationUse: "Translated into resolved language.",
                notes: ""
            )
        ],
        mustPreserve: ["The three tallow truths remain central."],
        mustAvoid: ["No halos.", "No wings.", "No religious iconography."]
    )

    let report = body.readinessReport

    #expect(report.isReady)
    #expect(report.blockingIssues.isEmpty)
    #expect(report.warnings.contains(.noReferenceMedia))
}

@Test
func legacyLensReadinessUsesLookOnlyFallbackAndRequiresReview() {
    let body = LensBody(
        title: "Legacy",
        claim: "Use legacy visual summary.",
        visualSummary: "Soft product imagery with warm handmade surfaces.",
        mustPreserve: ["Keep the product truthful."],
        mustAvoid: ["No false medical claims."]
    )

    let resolved = body.resolvedVisualLanguageForSceneStory
    let report = body.readinessReport

    #expect(resolved.look == "Soft product imagery with warm handmade surfaces.")
    #expect(resolved.palette.isEmpty)
    #expect(report.blockingIssues.contains(.missingResolvedProductionLanguage))
    #expect(report.warnings.contains(.legacyResolvedFallback))
}

@Test
func generatedDraftLensSanitizesAvoidsAndSourceTaxonomy() {
    let core = AestheticIndexItem(
        aestheticId: "angelcore",
        title: "Angelcore",
        signatureTerms: ["Angelcore", "It is typically approached"],
        paletteTerms: ["cream", "soft gold"]
    )
    let flavor = AestheticIndexItem(
        aestheticId: "cyberpunk",
        title: "Cyberpunk",
        signatureTerms: ["cyberpunk neon signage"],
        paletteTerms: ["electric blue"]
    )
    let card = AestheticDirectionCard(
        cardId: "card_lens",
        lane: .recommended,
        directionLabel: "Angelcore + Cyberpunk",
        coreItem: core,
        flavorItems: [flavor],
        avoidTerms: [
            "Center the product truth.",
            "No halos.",
            "Do not turn the goal into a platform plan, plot outline, shot list, or media generation plan."
        ],
        intensity0To1: 0.6,
        ingredientControls: [],
        signatureTerms: ["Angelcore", "cyberpunk neon signage", "It is typically approached"],
        paletteTerms: ["cream", "electric blue"],
        paletteSwatches: [],
        previewImagePaths: [],
        visualSummary: "Cream product imagery with cyberpunk neon signage as a concrete environmental cue.",
        treatmentNotes: ["soft product close-ups"],
        bestAppliedTo: ["close product frames"],
        fitReason: "A visual route for a product proof.",
        supportStatus: .archiveSupported,
        supportNote: "",
        evidence: ["Archive supports product close-ups."],
        gaps: [],
        conflicts: ["Avoid chrome overload."],
        scoreDebug: [:]
    )

    let lens = draftProjectLens(from: card, projectId: "project")
    let body = lens.body.normalized()

    #expect(body.mustAvoid == ["No halos.", "Avoid chrome overload."])
    #expect(body.resolvedVisualLanguage?.motifs.contains("cyberpunk neon signage") == true)
    #expect(body.resolvedVisualLanguage?.motifs.contains("Angelcore") == false)
    #expect(body.resolvedVisualLanguage?.motifs.contains("It is typically approached") == false)
    #expect(!body.readinessReport.blockingIssues.contains(.positiveRequirementInMustAvoid))
}

@Test
func promptSafeLensPacketOmitsLensAndSourceLabelsButKeepsResolvedDescriptors() throws {
    let lens = promptSafeFixtureLens()
    var set = ProjectLensSetDocument.empty(projectId: "project")
    set.appendVersion(
        lenses: [lens],
        scratchDrafts: [],
        selectedLensId: lens.lensId,
        selectedScratchId: nil,
        changeSummary: "Ready.",
        model: "test",
        now: "2026-06-24T00:00:00.000Z"
    )

    let packet = promptSafeLensSetPacket(set, readyLensSetHash: "ready_hash")
    let text = String(decoding: try JSONCoding.prettyEncoder.encode(packet), as: UTF8.self)

    #expect(!text.contains("Cyberpunk Source Lens"))
    #expect(!text.contains("Cyberpunk Ingredient"))
    #expect(!text.contains("source_recipe"))
    #expect(!text.contains("reference_aesthetic_ids"))
    #expect(text.contains("cyberpunk neon signage"))
    #expect(text.contains("ready_readiness_issues") == false)
}

@Test
func sceneStorylineRequestEncodingOmitsLensTitlesAndStyleIngredients() throws {
    let lens = promptSafeFixtureLens()
    let reference = StoryGenerationLensReference.from(lens: lens, lensVersionId: "lens_set_1", role: "primary")
    let snapshot = SceneStoryLensSnapshot.from(lens: lens)
    let referenceText = String(decoding: try JSONCoding.prettyEncoder.encode(reference), as: UTF8.self)
    let snapshotText = String(decoding: try JSONCoding.prettyEncoder.encode(snapshot), as: UTF8.self)

    #expect(!referenceText.contains("\"title\""))
    #expect(!snapshotText.contains("\"title\""))
    #expect(!snapshotText.contains("style_ingredients"))
    #expect(!snapshotText.contains("Cyberpunk Source Lens"))
    #expect(!snapshotText.contains("Cyberpunk Ingredient"))
    #expect(snapshotText.contains("cyberpunk neon signage"))
}

@Test
func readyLensCanPersistReadinessWarningsWithoutBlocking() {
    var lens = promptSafeFixtureLens()
    lens.readyReadinessIssues = [.missingResolvedProductionLanguage, .noReferenceMedia, .missingResolvedProductionLanguage]
    let normalized = lens.normalized()

    #expect(normalized.readyReadinessIssues == [.missingResolvedProductionLanguage, .noReferenceMedia])
}

@Test
func projectGoalLegacyJSONMigratesIntoTypedSQLiteTables() throws {
    let fixture = try makeGoalLensSQLiteFixture()
    var legacy = ProjectGoalDocumentV2.empty(projectId: fixture.project.projectId)
    legacy.appendMessage(
        role: .user,
        text: "Use the workshop archive as a public-memory documentary.",
        mediaIds: ["media_workshop", "media_workshop", ""],
        now: "2026-06-26T20:00:00.000Z"
    )
    legacy.appendMessage(
        role: .assistant,
        text: "I updated the Goal.",
        now: "2026-06-26T20:00:01.000Z"
    )
    legacy.appendVersion(
        brief: ProjectGoalBriefV2(
            contentType: .documentary,
            goal: "Make a documentary short about a workshop becoming a public memory.",
            audience: "Neighbors and collaborators.",
            desiredResponse: "Feel the archive has a civic purpose.",
            viewerExperience: "Observational, specific, and tactile.",
            successCriteria: ["The workshop arc is clear."],
            constraints: ["Do not invent products."],
            requiredEntities: [
                ProjectGoalRequiredEntity(name: "Rainforge Tools", role: "mandatory organization", required: true)
            ],
            openQuestions: ["Which public launch moment matters most?"],
            lensSeedSummary: "Industrial care and public memory.",
            lensSeedTerms: ["workbench", "red enamel"],
            meaningNodeRefs: [
                ProjectGoalMeaningNodeRef(
                    slug: "craft-as-care",
                    kind: .theme,
                    name: "Craft as care",
                    role: .themeSeed,
                    source: .goal,
                    evidence: "The Goal asks for public memory."
                )
            ],
            aestheticTermRefs: [
                ProjectGoalAestheticTermRef(
                    facetType: .keyColour,
                    slug: "red-enamel",
                    displayName: "Red enamel",
                    role: .palette,
                    source: .goal,
                    evidence: "The lens seed names red enamel."
                )
            ]
        ),
        changeSummary: "Defined workshop memory.",
        model: "test",
        now: "2026-06-26T20:00:02.000Z",
        validationWarnings: ["Confirm permission for public faces."]
    )
    try fixture.documentStore.saveDocument(legacy, for: fixture.project, documentType: "project_goal_v2")

    let loaded = fixture.contextStore.loadProjectGoalV2(for: fixture.project)
    let active = try #require(loaded.activeVersion)
    let databaseURL = LitScenesDesktopDatabase.projectDatabaseURL(for: fixture.project, projectLibrary: fixture.projectLibrary)

    #expect(loaded.messages.count == 2)
    #expect(active.brief.goal == "Make a documentary short about a workshop becoming a public memory.")
    #expect(active.brief.requiredEntities.first?.name == "Rainforge Tools")
    #expect(active.brief.meaningNodeRefs.first?.slug == "craft-as-care")
    #expect(active.brief.aestheticTermRefs.first?.displayName == "Red enamel")
    #expect(active.validationWarnings == ["Confirm permission for public faces."])
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_goal_state WHERE project_id = ?;", [fixture.project.projectId]) == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_goal_messages WHERE project_id = ?;", [fixture.project.projectId]) == 2)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_goal_message_media;") == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_goal_versions WHERE project_id = ?;", [fixture.project.projectId]) == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_goal_required_entities WHERE version_id = ?;", [active.versionId]) == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_goal_meaning_node_refs WHERE version_id = ?;", [active.versionId]) == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_goal_aesthetic_term_refs WHERE version_id = ?;", [active.versionId]) == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_goal_validation_warnings WHERE version_id = ?;", [active.versionId]) == 1)
}

@Test
func projectLensesLegacyJSONMigratesIntoTypedSQLiteTables() throws {
    let fixture = try makeGoalLensSQLiteFixture()
    let heroImage = ProjectLensHeroImage(
        imageId: "hero_workshop",
        imageIndex: 0,
        label: "Workbench detail",
        imagePath: "lenses/workshop/hero.png",
        prompt: "Red enamel tools on a workshop bench.",
        status: "ready",
        sourceAestheticIds: ["industrial-care"],
        generatedAt: "2026-06-26T20:01:01.000Z",
        updatedAt: "2026-06-26T20:01:01.000Z"
    )
    let lens = testLens(
        id: "lens_workshop_memory",
        status: .ready,
        title: "Workshop Memory",
        visualSummary: "Red enamel tools, hand-worn workbenches, and patient civic texture.",
        heroImage: heroImage
    )
    let scratch = LensScratchDraft(
        scratchId: "scratch_workshop",
        body: LensBody(
            title: "Raw Workshop Lens",
            claim: "Let the material details carry the public-memory claim.",
            visualSummary: "Loose red enamel and hand-detail notes.",
            paletteTerms: ["red enamel"],
            motifTerms: ["hands"]
        ),
        createdAt: "2026-06-26T20:01:00.000Z",
        updatedAt: "2026-06-26T20:01:00.000Z"
    )
    var legacy = ProjectLensSetDocument.empty(projectId: fixture.project.projectId)
    legacy.appendMessage(
        role: .user,
        text: "Use workshop red and hand detail.",
        targetScratchId: scratch.scratchId,
        targetLensId: nil,
        mediaIds: ["media_lens", "media_lens"],
        now: "2026-06-26T20:01:00.000Z"
    )
    legacy.appendVersion(
        lenses: [lens],
        scratchDrafts: [scratch],
        selectedLensId: lens.lensId,
        selectedScratchId: nil,
        changeSummary: "Ready workshop lens.",
        model: "test",
        now: "2026-06-26T20:01:02.000Z"
    )
    try fixture.documentStore.saveDocument(legacy, for: fixture.project, documentType: "project_lenses")

    let loaded = fixture.contextStore.loadProjectLenses(for: fixture.project)
    let active = try #require(loaded.activeVersion)
    let loadedLens = try #require(active.lenses.first)
    let databaseURL = LitScenesDesktopDatabase.projectDatabaseURL(for: fixture.project, projectLibrary: fixture.projectLibrary)

    #expect(loaded.messages.count == 1)
    #expect(active.selectedLensId == lens.lensId)
    #expect(loadedLens.body.title == "Workshop Memory")
    #expect(loadedLens.primaryHeroImage?.imagePath == "lenses/workshop/hero.png")
    // Single-Lens canonicalization: when a canonical lens exists, scratch
    // drafts are stripped and every scratch pointer is nulled — at decode,
    // read, and write alike.
    #expect(active.scratchDrafts.isEmpty)
    #expect(active.selectedScratchId == nil)
    #expect(loaded.messages.first?.targetScratchId == nil)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_lens_state WHERE project_id = ?;", [fixture.project.projectId]) == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_lens_messages WHERE project_id = ?;", [fixture.project.projectId]) == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_lens_message_media;") == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_lens_versions WHERE project_id = ?;", [fixture.project.projectId]) == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_lens_version_lenses WHERE version_id = ?;", [active.versionId]) == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_lens_terms WHERE version_id = ? AND term_kind = ?;", [active.versionId, "palette_terms"]) == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_lens_style_ingredients WHERE version_id = ?;", [active.versionId]) == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_lens_ingredient_terms WHERE version_id = ?;", [active.versionId]) == 4)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_lens_hero_images WHERE version_id = ?;", [active.versionId]) == 1)
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_lens_scratch_drafts WHERE version_id = ?;", [active.versionId]) == 0)
}

@Test
func lensFreeLegacyScratchDraftSurvivesMigration() throws {
    // The one case canonicalization preserves: a legacy project with a draft
    // and NO lens keeps its first draft through the typed-table migration.
    let fixture = try makeGoalLensSQLiteFixture()
    let scratch = LensScratchDraft(
        scratchId: "scratch_workshop",
        body: LensBody(
            title: "Raw Workshop Lens",
            claim: "Let the material details carry the public-memory claim.",
            visualSummary: "Loose red enamel and hand-detail notes.",
            paletteTerms: ["red enamel"],
            motifTerms: ["hands"]
        ),
        createdAt: "2026-06-26T20:01:00.000Z",
        updatedAt: "2026-06-26T20:01:00.000Z"
    )
    var legacy = ProjectLensSetDocument.empty(projectId: fixture.project.projectId)
    legacy.appendVersion(
        lenses: [],
        scratchDrafts: [scratch],
        selectedLensId: nil,
        selectedScratchId: scratch.scratchId,
        changeSummary: "Draft only.",
        model: "test",
        now: "2026-06-26T20:01:02.000Z"
    )
    try fixture.documentStore.saveDocument(legacy, for: fixture.project, documentType: "project_lenses")

    let loaded = fixture.contextStore.loadProjectLenses(for: fixture.project)
    let active = try #require(loaded.activeVersion)
    let databaseURL = LitScenesDesktopDatabase.projectDatabaseURL(for: fixture.project, projectLibrary: fixture.projectLibrary)

    #expect(active.lenses.isEmpty)
    #expect(active.scratchDrafts.count == 1)
    #expect(active.scratchDrafts.first?.body.title == "Raw Workshop Lens")
    #expect(active.selectedScratchId == "scratch_workshop")
    #expect(try sqliteScalarInt(databaseURL, "SELECT COUNT(*) FROM project_lens_scratch_drafts WHERE version_id = ?;", [active.versionId]) == 1)
}

private func promptSafeFixtureLens() -> ProjectLens {
    ProjectLens(
        lensId: "lens_prompt_safe",
        status: .ready,
        enabled: true,
        body: LensBody(
            title: "Cyberpunk Source Lens",
            claim: "Use clean product proof without leaning on the source label.",
            visualSummary: "A compact product proof with cyberpunk neon signage in the environment.",
            resolvedVisualLanguage: LensResolvedVisualLanguage(
                look: "Clean product proof with rain-slick glass and cyberpunk neon signage.",
                palette: ["black glass", "electric blue", "warm amber"],
                materials: ["rain-slick glass", "brushed metal"],
                productTreatment: ["single clean product silhouette"],
                motifs: ["cyberpunk neon signage", "reflected window grids"],
                composition: ["low-angle product close-up"],
                pacingEnergy: ["precise", "electric"],
                avoid: ["No source-label title cards."]
            ),
            styleIngredients: [
                LensStyleIngredient(
                    ingredientId: "ingredient_cyberpunk",
                    order: 1,
                    title: "Cyberpunk Ingredient",
                    role: "source",
                    narrativeUse: "Source inspiration only.",
                    presentationUse: "Translate into concrete production language.",
                    notes: "No source taxonomy should leak.",
                    referenceAestheticIds: ["cyberpunk"],
                    sourceRecipeId: "recipe_cyberpunk",
                    sourceRecipeVersion: "v1",
                    sourceReferenceIds: ["cyberpunk"]
                )
            ],
            mustPreserve: ["Keep the concrete neon signage descriptor."],
            mustAvoid: ["No source-label title cards."],
            referenceMediaIds: ["media_1"]
        )
    ).normalized()
}

private func openObjectPaths(in value: Any, path: String = "$") -> [String] {
    if let dictionary = value as? [String: Any] {
        var paths: [String] = []
        if dictionary["type"] as? String == "object",
           (dictionary["additionalProperties"] as? Bool) != false {
            paths.append(path)
        }
        for (key, child) in dictionary {
            paths.append(contentsOf: openObjectPaths(in: child, path: "\(path).\(key)"))
        }
        return paths
    }
    if let array = value as? [Any] {
        return array.enumerated().flatMap { index, child in
            openObjectPaths(in: child, path: "\(path)[\(index)]")
        }
    }
    return []
}

private func testLens(
    id: String,
    status: ProjectLensStatus,
    title: String,
    visualSummary: String,
    heroImage: ProjectLensHeroImage? = nil
) -> ProjectLens {
    ProjectLens(
        lensId: id,
        status: status,
        enabled: status == .ready,
        body: LensBody(
            title: title,
            claim: "Make the archive feel intentional.",
            visualSummary: visualSummary,
            styleIngredients: [
                LensStyleIngredient(
                    ingredientId: "ingredient_\(id)",
                    order: 1,
                    title: title,
                    role: "primary",
                    narrativeUse: "Frames the emotional promise.",
                    presentationUse: "Guides color and composition.",
                    notes: "",
                    paletteTerms: ["red"],
                    motifTerms: ["hands"],
                    avoidTerms: ["generic gloss"],
                    referenceAestheticIds: ["stock_aesthetic"],
                    sourceRecipeId: nil,
                    sourceRecipeVersion: nil,
                    sourceReferenceIds: [],
                    updatedAt: "2026-06-15T00:00:00.000Z"
                )
            ],
            paletteTerms: ["red"],
            motifTerms: ["hands"]
        ),
        heroImage: heroImage,
        relationSummary: .empty,
        createdAt: "2026-06-15T00:00:00.000Z",
        updatedAt: "2026-06-15T00:00:00.000Z"
    )
}

private struct GoalLensSQLiteFixture {
    let root: URL
    let projectLibrary: ProjectLibrary
    let project: ProjectRecord
    let contextStore: ProjectContextStore
    let documentStore: ProjectSQLiteDocumentStore
}

private enum GoalLensSQLiteTestError: Error {
    case sqliteOpen(String)
    case sqlitePrepare(String)
}

private func makeGoalLensSQLiteFixture() throws -> GoalLensSQLiteFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_goal_lens_sqlite_\(UUID().uuidString)", isDirectory: true)
    let projectLibrary = ProjectLibrary(root: root)
    let project = try projectLibrary.createProject(named: "Goal Lens SQLite")
    return GoalLensSQLiteFixture(
        root: root,
        projectLibrary: projectLibrary,
        project: project,
        contextStore: ProjectContextStore(projectLibrary: projectLibrary),
        documentStore: ProjectSQLiteDocumentStore(projectLibrary: projectLibrary)
    )
}

private func sqliteScalarInt(_ databaseURL: URL, _ sql: String, _ bindings: [String] = []) throws -> Int {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(databaseURL.path, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        throw GoalLensSQLiteTestError.sqliteOpen(sqliteErrorMessage(connection))
    }
    defer {
        sqlite3_close(connection)
    }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
        throw GoalLensSQLiteTestError.sqlitePrepare(sqliteErrorMessage(connection))
    }
    defer {
        sqlite3_finalize(statement)
    }

    for (index, value) in bindings.enumerated() {
        sqlite3_bind_text(statement, Int32(index + 1), value, -1, litScenesSQLiteTransient)
    }
    guard sqlite3_step(statement) == SQLITE_ROW else {
        return 0
    }
    return Int(sqlite3_column_int(statement, 0))
}

private func sqliteErrorMessage(_ connection: OpaquePointer?) -> String {
    guard let connection else { return "unknown SQLite error" }
    return String(cString: sqlite3_errmsg(connection))
}

@Test
func conceptCategoryTaxonomyImageKindRoundTripsThroughCategoryResolution() {
    // A blank frame stamped with its category's imageKind must bucket back into
    // that category without any route-key fallback.
    for category in LensConceptCategory.allCases where category != .legacy {
        var image = ProjectLensHeroImage(imageId: "img_test")
        image.imageKind = category.taxonomyImageKind
        image.sourceRouteKey = "lens_media_custom_zzz@v9"
        let resolved = LensConceptCategory.category(for: image.normalized())
        // areaImage folds into .areas; all others map 1:1.
        #expect(resolved == category)
    }
    #expect(LensConceptCategory.legacy.taxonomyImageKind.isEmpty)
}
