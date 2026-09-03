import Foundation
import Testing
@testable import LitScenes

// Direct-mode story inference: bundled-vocabulary resolve, base-URL endpoint
// building, frame-form trio selection, and the local schema/projection builders.

private func emptyLensContextResponse() -> LensContextResolveResponse {
    LensContextResolveResponse(
        schemaVersion: "", userId: "", projectId: "", goalFingerprint: "",
        selectedMeaningNodes: [], meaningEdgeNeighbors: [], meaningEvidence: [],
        aestheticCandidates: [], styleCandidates: [], warnings: [],
        queryStats: LensContextQueryStats()
    )
}

private func emptyLensSnapshot(lensId: String) -> SceneStoryLensSnapshot {
    SceneStoryLensSnapshot(
        lensId: lensId, claim: "", userNotes: "", visualSummary: "",
        resolvedVisualLanguage: nil, mustPreserve: [], mustAvoid: [], referenceMediaIds: []
    )
}

@Test func bundledMeaningIndexLoads() throws {
    let index = try LocalMeaningIndex.loadBundled()
    #expect(index.nodes.count > 100)
    let sample = try #require(index.nodes.first)
    #expect(!sample.slug.isEmpty)
    #expect(!sample.definition.isEmpty)
    #expect(index.node(forSlug: sample.slug) != nil)
}

@Test func localResolveHydratesFromBundledVocabularyAndDisclosesGaps() async throws {
    let index = try LocalMeaningIndex.loadBundled()
    let known = try #require(index.nodes.first)
    let client = LocalStoryInferenceClient(
        apiKey: "test",
        responsesURL: URL(string: "https://api.openai.com/v1/responses")!,
        storyModel: "gpt-5.5",
        frameFormModel: "gpt-5.5"
    )
    var knownRef = ProjectGoalMeaningNodeRef()
    knownRef.slug = known.slug
    var missingRef = ProjectGoalMeaningNodeRef()
    missingRef.slug = "never.a-real-slug"
    missingRef.name = "Invented Ref"
    missingRef.evidence = "carried from the goal"
    let request = LensContextResolveRequest(
        projectId: "project_test",
        goalFingerprint: "fp_test",
        meaningNodeRefs: [knownRef, missingRef],
        aestheticTermRefs: [],
        limits: LensContextResolveLimits()
    )

    let response = try await client.resolve(request)
    #expect(response.projectId == "project_test")
    #expect(response.selectedMeaningNodes.count == 2)
    #expect(response.selectedMeaningNodes[0].slug == known.slug)
    #expect(response.selectedMeaningNodes[0].definition == known.definition)
    #expect(response.selectedMeaningNodes[1].name == "Invented Ref")
    #expect(response.meaningEdgeNeighbors.isEmpty)
    #expect(response.meaningEvidence.isEmpty)
    // Direct mode must be end-to-end: the Scene Plan generator hard-requires
    // style candidates, so the local resolve serves them from the catalog.
    #expect(!response.styleCandidates.isEmpty)
    #expect(response.styleCandidates.allSatisfy { !$0.styleId.isEmpty && !$0.collectionKey.isEmpty })
    #expect(response.warnings.contains { $0.contains("Local mode") })
    #expect(response.warnings.contains { $0.contains("never.a-real-slug") })
    #expect(response.queryStats.resolvedMeaningNodeCount == 2)
}

@Test func baseURLEndpointBuilding() {
    let bare = URL(string: "https://example.com")!
    #expect(
        OpenAITextEndpointSettings.endpoint(base: bare, path: "responses").absoluteString
            == "https://example.com/v1/responses"
    )
    let versioned = URL(string: "https://openrouter.example/api/v1/")!
    #expect(
        OpenAITextEndpointSettings.endpoint(base: versioned, path: "responses").absoluteString
            == "https://openrouter.example/api/v1/responses"
    )
    #expect(
        OpenAITextEndpointSettings.endpoint(base: bare, path: "images/edits").absoluteString
            == "https://example.com/v1/images/edits"
    )
}

@Test func frameFormInitialTrioSelectsThreeDistinctNodes() throws {
    let index = try LocalMeaningIndex.loadBundled()
    var request = FrameFormsGenerateRequest()
    request.projectId = "project_test"
    request.goalSummary = "A goal"
    request.meaningNodeRefs = index.nodes.prefix(6).map { node in
        var ref = ProjectGoalMeaningNodeRef()
        ref.slug = node.slug
        return ref
    }
    let (candidates, warnings) = LocalFrameFormSelection.candidates(request: request, mode: "initial")
    #expect(candidates.count >= 3)
    let slugs = Set(candidates.prefix(3).map { $0.node.slug })
    #expect(slugs.count == 3)
    #expect(candidates[0].roleHint == "grounded_extreme")
    #expect(candidates[1].roleHint == "tension_middle")
    #expect(candidates[2].roleHint == "abstract_extreme")
    #expect(warnings.contains { $0.contains("Local mode") })
    #expect(candidates.prefix(3).allSatisfy { !$0.expression.isEmpty })
}

@Test func frameFormExpansionBranchesFromCatalogWithDisclosure() {
    var request = FrameFormsGenerateRequest()
    request.projectId = "project_test"
    request.goalSummary = "A goal"
    request.selectedForm = FrameFormsSelectedForm(
        meaningSlug: "theme.some-selected",
        pole: "positive",
        title: "Selected",
        promptGist: "gist"
    )
    let (candidates, warnings) = LocalFrameFormSelection.candidates(request: request, mode: "expansion")
    #expect(candidates.count >= 3)
    #expect(candidates[0].pole == "negative")
    #expect(candidates.allSatisfy { $0.relationToParent == "catalog" })
    #expect(warnings.contains { $0.contains("no local graph edges") })
}

@Test func frameFormDecodeValidatesLengthAndStyleLeaks() throws {
    let index = try LocalMeaningIndex.loadBundled()
    let nodes = Array(index.nodes.prefix(3))
    let candidates = nodes.map {
        LocalFrameFormCandidate(node: $0, pole: "positive", expression: $0.definition, roleHint: "branch")
    }
    let longPrompt = String(repeating: "A concrete subject acts in a specific place. ", count: 4)
    func payload(prompt2: String) throws -> String {
        let options = [
            ["title": "First Title", "prompt": longPrompt],
            ["title": "Second Title", "prompt": prompt2],
            ["title": "Third Title", "prompt": longPrompt]
        ]
        var body: [String: Any] = ["schema_version": "litscenes.frame_forms.v0.1"]
        for (index, option) in options.enumerated() {
            var stamped: [String: Any] = option
            stamped["meaning_slug"] = candidates[index].node.slug
            stamped["pole"] = candidates[index].pole
            stamped["relation_to_parent"] = ""
            body["option_\(index + 1)"] = stamped
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    let good = try LocalFrameFormSelection.decodeAndValidate(text: payload(prompt2: longPrompt), candidates: candidates)
    #expect(good.count == 3)
    #expect(good[0].meaningSlug == candidates[0].node.slug)

    #expect(throws: (any Error).self) {
        _ = try LocalFrameFormSelection.decodeAndValidate(text: try payload(prompt2: "too short"), candidates: candidates)
    }
    #expect(throws: (any Error).self) {
        _ = try LocalFrameFormSelection.decodeAndValidate(
            text: try payload(prompt2: longPrompt + " rendered in a cinematic golden hour glow"),
            candidates: candidates
        )
    }
}

@Test func sceneStorySchemaPinsRequestIdentity() throws {
    var wire = SceneStoryGenerateRequest(
        projectId: "project_x",
        goalFingerprint: "fp_x",
        lensId: "lens_x",
        lensContextFingerprint: "ctx_x",
        goal: ProjectGoalBriefV2(goal: "Test goal"),
        lens: emptyLensSnapshot(lensId: "lens_x"),
        lensContext: emptyLensContextResponse()
    )
    wire.storyCount = 2
    wire.scenesPerStory = 3
    wire.beatsPerScene = 1
    let request = normalizedLocalSceneStoryRequest(wire)
    let schema = LocalStoryInferenceSchemas.sceneStorySet(
        request: request, userId: "local", generatedAt: "NOW", model: "gpt-5.5"
    )
    let properties = try #require(schema["properties"] as? [String: Any])
    #expect((properties["project_id"] as? [String: Any])?["const"] as? String == "project_x")
    #expect((properties["story_count"] as? [String: Any])?["const"] as? Int == 2)
    let stories = try #require(properties["scene_stories"] as? [String: Any])
    #expect(stories["minItems"] as? Int == 2)
    #expect(stories["maxItems"] as? Int == 2)
    // The whole schema and the projected input must serialize — they are sent inline.
    _ = try JSONSerialization.data(withJSONObject: schema)
    let input = LocalSceneStoryProjection.modelInput(request: request)
    _ = try JSONSerialization.data(withJSONObject: input)
    #expect(input["creative_brief"] != nil)
    #expect(input["task_controls"] != nil)
}

@Test func storyInferenceInstructionsCarryModeAndArchitectureContracts() {
    var wire = SceneStoryGenerateRequest(
        projectId: "p", goalFingerprint: "f", lensId: "l", lensContextFingerprint: "c",
        goal: ProjectGoalBriefV2(goal: "g"),
        lens: emptyLensSnapshot(lensId: "l"),
        lensContext: emptyLensContextResponse()
    )
    wire.generationMode = .branchSelected
    wire.generationIntent.architectureFamily = .symbolicInversion
    let request = normalizedLocalSceneStoryRequest(wire)
    let instructions = LocalStoryInferencePrompts.sceneStoryInstructions(request: request)
    #expect(instructions.contains("MODE: BRANCH"))
    #expect(instructions.contains("SYMBOLIC INVERSION"))
    #expect(instructions.contains("GROUNDING AND DIALOGUE"))
}


@Test func localStyleCandidatesScoreTypedTermMatches() async throws {
    let snapshot = try await CatalogManifestRuntime.shared.loadSnapshot()
    let styles = snapshot.styleBrowse.styles
    let mood = try #require(styles.first { !$0.moods.isEmpty }?.moods.first)
    var moodRef = ProjectGoalStyleTermRef()
    moodRef.term = mood
    moodRef.kind = .mood
    moodRef.weight = 2
    let candidates = LocalStyleCandidateBuilder.candidates(
        from: snapshot.styleBrowse,
        styleTermRefs: [moodRef],
        limit: 45
    )
    #expect(candidates.count == min(styles.count, 45))
    let top = try #require(candidates.first)
    #expect(top.score > 0)
    #expect(top.matchedTerms.contains { $0.fieldName == "moods" && $0.contribution == 2 })
    // Zero-score styles still appear (never an empty candidate list), sorted last.
    #expect(candidates.last?.score ?? -1 <= top.score)
}

@Test func catalogFetchPolicyDefaultsToBundledFirst() {
    // With no LITSCENES_LIVE_CATALOG configured, an unconfigured install must
    // make no catalog requests on its own.
    if LitScenesCredentialStore().resolvedCredentialValue(forKey: CatalogFetchPolicy.preferenceKey).isEmpty {
        #expect(!CatalogFetchPolicy.liveCatalogEnabled())
    }
}
