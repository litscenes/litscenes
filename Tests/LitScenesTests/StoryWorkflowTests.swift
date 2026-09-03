import Foundation
import Testing
@testable import LitScenes

@Test
func storyInputFingerprintChangesWhenGoalAestheticSetupOrPatternChanges() {
    let baseGoal = testGoal(versionId: "goal_a", updatedAt: "2026-06-09T00:00:00Z")
    var changedGoal = baseGoal
    changedGoal.updatedAt = "2026-06-10T00:00:00Z"

    let baseBrief = ProjectAestheticBriefDocument(projectId: "project_test", updatedAt: "2026-06-10T01:00:00Z")
    var changedBrief = baseBrief
    changedBrief.updatedAt = "2026-06-10T02:00:00Z"

    let setup = StorySetupDocument.empty(projectId: "project_test")
    var changedSetup = setup
    changedSetup.inventionLevel = .wildMythology

    let base = StoryInputFingerprint.make(
        goal: baseGoal,
        aestheticBrief: baseBrief,
        storyWorld: StoryWorldDocument.empty(projectId: "project_test"),
        sourceContextRecords: [],
        enabledMedia: [],
        mediaObservationsById: [:],
        storySetup: setup,
        storyPatternIndexVersion: "story_pattern_index.v0.1"
    )

    let goalChanged = StoryInputFingerprint.make(
        goal: changedGoal,
        aestheticBrief: baseBrief,
        storyWorld: StoryWorldDocument.empty(projectId: "project_test"),
        sourceContextRecords: [],
        enabledMedia: [],
        mediaObservationsById: [:],
        storySetup: setup,
        storyPatternIndexVersion: "story_pattern_index.v0.1"
    )
    let aestheticChanged = StoryInputFingerprint.make(
        goal: baseGoal,
        aestheticBrief: changedBrief,
        storyWorld: StoryWorldDocument.empty(projectId: "project_test"),
        sourceContextRecords: [],
        enabledMedia: [],
        mediaObservationsById: [:],
        storySetup: setup,
        storyPatternIndexVersion: "story_pattern_index.v0.1"
    )
    let setupChanged = StoryInputFingerprint.make(
        goal: baseGoal,
        aestheticBrief: baseBrief,
        storyWorld: StoryWorldDocument.empty(projectId: "project_test"),
        sourceContextRecords: [],
        enabledMedia: [],
        mediaObservationsById: [:],
        storySetup: changedSetup,
        storyPatternIndexVersion: "story_pattern_index.v0.1"
    )
    let patternChanged = StoryInputFingerprint.make(
        goal: baseGoal,
        aestheticBrief: baseBrief,
        storyWorld: StoryWorldDocument.empty(projectId: "project_test"),
        sourceContextRecords: [],
        enabledMedia: [],
        mediaObservationsById: [:],
        storySetup: setup,
        storyPatternIndexVersion: "story_pattern_index.v0.2"
    )

    #expect(base.goalUpdatedAt != goalChanged.goalUpdatedAt)
    #expect(base.aestheticBriefUpdatedAt != aestheticChanged.aestheticBriefUpdatedAt)
    #expect(base.storySetupHash != setupChanged.storySetupHash)
    #expect(base.storyPatternIndexVersion != patternChanged.storyPatternIndexVersion)
    #expect(base.stableId != goalChanged.stableId)
    #expect(base.stableId != aestheticChanged.stableId)
    #expect(base.stableId != setupChanged.stableId)
    #expect(base.stableId != patternChanged.stableId)
}

@Test
func storyInputFingerprintIgnoresStorySetupTimestampChurn() {
    let goal = testGoal(versionId: "goal_a", updatedAt: "2026-06-09T00:00:00Z")
    let brief = ProjectAestheticBriefDocument(projectId: "project_test", updatedAt: "2026-06-10T01:00:00Z")
    let storyWorld = StoryWorldDocument.empty(projectId: "project_test")
    var setup = StorySetupDocument.empty(projectId: "project_test")
    setup.updatedAt = "2026-06-10T01:00:00Z"
    var timestampOnlyChange = setup
    timestampOnlyChange.updatedAt = "2026-06-11T02:00:00Z"

    let base = StoryInputFingerprint.make(
        goal: goal,
        aestheticBrief: brief,
        storyWorld: storyWorld,
        sourceContextRecords: [],
        enabledMedia: [],
        mediaObservationsById: [:],
        storySetup: setup,
        storyPatternIndexVersion: "story_pattern_index.v0.1"
    )
    let timestampChanged = StoryInputFingerprint.make(
        goal: goal,
        aestheticBrief: brief,
        storyWorld: storyWorld,
        sourceContextRecords: [],
        enabledMedia: [],
        mediaObservationsById: [:],
        storySetup: timestampOnlyChange,
        storyPatternIndexVersion: "story_pattern_index.v0.1"
    )

    #expect(base.storySetupHash == timestampChanged.storySetupHash)
    #expect(base.stableId == timestampChanged.stableId)
}

@Test
func storyDirectionSetFreshnessUsesSemanticStorySetupHash() {
    let goal = testGoal(versionId: "goal_a", updatedAt: "2026-06-09T00:00:00Z")
    let brief = ProjectAestheticBriefDocument(projectId: "project_test", updatedAt: "2026-06-10T01:00:00Z")
    let storyWorld = StoryWorldDocument.empty(projectId: "project_test")
    var setup = StorySetupDocument.empty(projectId: "project_test")
    setup.updatedAt = "2026-06-10T01:00:00Z"
    let fingerprint = StoryInputFingerprint.make(
        goal: goal,
        aestheticBrief: brief,
        storyWorld: storyWorld,
        sourceContextRecords: [],
        enabledMedia: [],
        mediaObservationsById: [:],
        storySetup: setup,
        storyPatternIndexVersion: "story_pattern_index.v0.1"
    )
    var legacyTimestampFingerprint = fingerprint
    legacyTimestampFingerprint.storySetupHash = stableHash(setup)
    let set = StoryDirectionSet(
        projectId: "project_test",
        inputFingerprint: legacyTimestampFingerprint,
        storySetupSnapshot: setup,
        directions: [testDirection(lane: .recommended)]
    )

    var timestampOnlyChange = setup
    timestampOnlyChange.updatedAt = "2026-06-11T02:00:00Z"
    let current = StoryInputFingerprint.make(
        goal: goal,
        aestheticBrief: brief,
        storyWorld: storyWorld,
        sourceContextRecords: [],
        enabledMedia: [],
        mediaObservationsById: [:],
        storySetup: timestampOnlyChange,
        storyPatternIndexVersion: "story_pattern_index.v0.1"
    )

    var semanticChange = timestampOnlyChange
    semanticChange.customPovOption = ProjectGoalStorySetupOption(
        optionId: "pov_customer",
        label: "Potential customer",
        promptValue: "Potential customer discovering the apothecary",
        rationale: "Derived from the current Goal."
    )

    #expect(set.freshness(against: current, currentStorySetup: timestampOnlyChange) == .fresh)
    #expect(set.freshness(against: current, currentStorySetup: semanticChange) == .stale)
}

@Test
func projectGoalStorySetupSuggestionsRoundTripAndNormalize() throws {
    let briefJSON = """
    {
      "content_type": "brand",
      "goal": "Create an apothecary brand story for potential customers.",
      "audience": "Wellness customers.",
      "desired_action": "Visit the shop.",
      "distribution_context": "Website and short social video.",
      "success_criteria": ["Feels specific"],
      "story_promise": "A customer discovers the ritual value of the apothecary.",
      "constraints": [],
      "open_questions": [],
      "aesthetic_intent": {
        "emotional_targets": [],
        "narrative_values": [],
        "visual_mood": [],
        "palette_hints": [],
        "motif_hints": [],
        "era_hints": [],
        "energy": [],
        "avoid": [],
        "open_style_questions": [],
        "confidence_0_to_1": 0
      },
      "story_setup_suggestions": {
        "pov_options": [
          {
            "option_id": "pov_customer",
            "label": "Potential customer",
            "prompt_value": "Potential customer deciding whether to trust the apothecary",
            "rationale": "Matches the target audience."
          },
          {
            "option_id": "pov_customer_duplicate",
            "label": "Potential customer",
            "prompt_value": "Potential customer deciding whether to trust the apothecary",
            "rationale": "Duplicate should be removed."
          }
        ],
        "engine_options": [
          {
            "option_id": "engine_ritual",
            "label": "Ritual discovery",
            "prompt_value": "Customer problem becomes a small ritual of care",
            "rationale": "Fits an apothecary brand."
          }
        ],
        "ending_options": [
          {
            "option_id": "ending_invitation",
            "label": "Invitation to return",
            "prompt_value": "End with the customer choosing the apothecary as a repeat ritual",
            "rationale": "Commercial without being hard CTA."
          }
        ]
      },
      "confidence_0_to_1": 0.84
    }
    """

    let decoded = try JSONDecoder().decode(ProjectGoalBrief.self, from: Data(briefJSON.utf8))
    let normalized = decoded.storySetupSuggestions.normalized()
    #expect(normalized.povOptions.map(\.displayLabel) == ["Potential customer"])
    #expect(normalized.engineOptions.first?.displayLabel == "Ritual discovery")
    #expect(normalized.endingOptions.first?.effectivePromptValue.contains("repeat ritual") == true)

    let legacyBrief = try JSONDecoder().decode(ProjectGoalBrief.self, from: Data(#"{"content_type":"brand","goal":"Legacy goal"}"#.utf8))
    #expect(legacyBrief.storySetupSuggestions == .empty())
}

@Test
func storySetupCustomGoalOptionsDriveEffectiveLabelsAndRoundTrip() throws {
    var setup = StorySetupDocument.empty(projectId: "project_test")
    setup.customPovOption = ProjectGoalStorySetupOption(
        optionId: "pov_customer",
        label: "Potential customer",
        promptValue: "Potential customer deciding whether to trust the apothecary",
        rationale: "Derived from Goal."
    )
    setup.customStoryEngineOption = ProjectGoalStorySetupOption(
        optionId: "engine_ritual",
        label: "Ritual discovery",
        promptValue: "Customer problem becomes a ritual of care",
        rationale: "Derived from Goal."
    )
    setup.customEndingOption = ProjectGoalStorySetupOption(
        optionId: "ending_invitation",
        label: "Invitation to return",
        promptValue: "End with a repeat ritual invitation",
        rationale: "Derived from Goal."
    )

    let decoded = try StorySetupDocument.decode(from: setup.encoded())
    #expect(decoded.effectivePOVLabel == "Potential customer")
    #expect(decoded.effectiveStoryEngineLabel == "Ritual discovery")
    #expect(decoded.effectiveEndingStyleLabel == "Invitation to return")
}

@Test
func legacyStorySignalsRemainLegacyAndStaleForGeneration() throws {
    let legacyJSON = """
    {
      "schema_version": "litscenes.project_archive_meaning.v0.1",
      "project_id": "project_test",
      "scope": "all_usable_media",
      "summary": "Old arcade gecko route.",
      "motifs": ["retro hud"],
      "tensions": [],
      "moods": [],
      "scene_forces": [],
      "constraints": [],
      "implications": [],
      "evidence_media_ids": [],
      "confidence_0_to_1": 0.62,
      "generated_at": "2026-06-02T00:00:00Z",
      "updated_at": "2026-06-02T00:00:00Z"
    }
    """
    let legacyGraph = try ProjectArchiveMeaningGraph.decode(from: Data(legacyJSON.utf8))
    let signals = StorySignalSet.fromLegacy(
        legacyGraph,
        rawScope: "all_usable_media",
        projectId: "project_test"
    )

    #expect(signals.artifactStatus == .legacy)
    #expect(signals.legacyRawScope == "all_usable_media")
    #expect(signals.freshness(against: .empty()) == .legacy)
    #expect(signals.summary.contains("arcade"))
}

@Test
func storyValidationRejectsGenericBeatAndAcceptsConcreteVisualBeat() {
    let generic = testBeat(
        event: "The protagonist confronts the truth of their journey.",
        visualMoment: "Everything changes as the final truth is revealed.",
        promptReadyLine: "The protagonist confronts the truth."
    )
    let concrete = testBeat(
        event: "The iPhone camera records the mirror and shows a gecko signal that is not visible in the room.",
        visualMoment: "A warm hallway mirror stays empty while the phone screen shows a colder room with a gecko staring back.",
        promptReadyLine: "Warm domestic mirror shot, iPhone screen reveals a hidden gecko signal, cheerful poster composition corrupted by acid typography."
    )

    #expect(StoryValidation.beatWarnings(generic).contains("generic beat language"))
    #expect(StoryValidation.beatWarnings(concrete).isEmpty)
}

@Test
func storyValidationRejectsDirectionWithoutAestheticBindingAndCommercialCTABloat() {
    var direction = testDirection(lane: .recommended)
    direction.aestheticUse = StoryAestheticUse(narrative: "", presentation: "")

    let directionWarnings = StoryValidation.directionWarnings(direction)
    #expect(directionWarnings.contains("weak narrative aesthetic binding"))
    #expect(directionWarnings.contains("weak presentation aesthetic binding"))

    var board = testBeatBoard()
    board.beats = (1...3).map { index in
        testBeat(
            order: index,
            event: "The visual story pauses to ask viewers to buy now and sign up for the offer.",
            visualMoment: "A direct CTA fills the frame instead of escalating the story.",
            promptReadyLine: "Buy now, sign up, order today."
        )
    }
    let setup = StorySetupDocument(projectId: "project_test", commercialPressure: .creatorFriendly)
    #expect(StoryValidation.commercialWarnings(board: board, setup: setup).contains("too many CTA beats for selected commercial pressure"))
}

@Test
func storylineEnablementDefaultsAndFiltering() throws {
    let legacyDirectionJSON = """
    {
      "direction_id": "dir_legacy",
      "lane": "recommended",
      "title": "Legacy Lens",
      "premise": "A phone and mirror reveal hidden evidence in a domestic archive.",
      "story_engine": "Evidence escalates",
      "what_happens": "The story starts with ordinary evidence and escalates through reflection proof.",
      "why_it_works": "It binds the Goal to visible archive surfaces.",
      "aesthetic_use": {
        "narrative": "domestic normalcy breached",
        "presentation": "poster art, acid typography"
      },
      "invented_elements": [],
      "risk": "Can become too literal.",
      "three_beat_preview": ["Ordinary home", "First reflection", "Final warning"],
      "meaning_moves": ["ordinary object becomes proof"],
      "commercial_pressure": 0.1,
      "weirdness": 0.4,
      "promptability": 0.8,
      "score_debug": {
        "goal_fit": 0.8,
        "aesthetic_narrative_fit": 0.8,
        "aesthetic_presentation_fit": 0.8,
        "story_setup_fit": 0.8,
        "pattern_support": 0.8,
        "specificity": 0.8,
        "promptability": 0.8,
        "novelty": 0.4,
        "lane_fit": 0.8,
        "commercial_fit": 0.1,
        "too_commercial_penalty": 0.0,
        "generic_slop_penalty": 0.0,
        "near_duplicate_penalty": 0.0,
        "final_score": 0.8
      },
      "validation_warnings": []
    }
    """
    let legacyDirection = try JSONCoding.decoder.decode(StoryDirectionCard.self, from: Data(legacyDirectionJSON.utf8))
    #expect(legacyDirection.enabled)

    var disabled = testDirection(lane: .bolder)
    disabled.enabled = false
    let set = StoryDirectionSet(
        projectId: "project_test",
        directions: [testDirection(lane: .recommended), disabled, testDirection(lane: .wildcard)]
    )
    #expect(set.enabledDirections.map(\.directionId) == ["dir_recommended", "dir_wildcard"])
}

@Test
func storylineCommercialNoneDoesNotProduceDefaultCommercialLens() {
    var setup = StorySetupDocument.empty(projectId: "project_test")
    setup.commercialPressure = .none
    let set = StoryLocalDraftFactory.directionSet(
        projectId: "project_test",
        projectName: "Test",
        fingerprint: .empty(),
        setup: setup,
        goalDigest: StoryGoalDigest(summary: "Mirror and phone gecko archive."),
        aestheticCues: StoryAestheticCues(
            narrativeCues: ["domestic normalcy breached"],
            presentationCues: ["poster art", "acid typography"]
        ),
        patternMatches: [],
        generatedAt: "2026-06-10T00:00:00Z"
    )

    #expect(set.directions.count == 3)
    #expect(set.directions.allSatisfy { $0.enabled })
    #expect(!set.directions.contains { $0.lane == .commercial })
}

@Test
func storylineDisplayOrderKeepsEnabledAboveDisabledAndPreservesListOrder() {
    var newest = testDirection(lane: .recommended)
    newest.directionId = "dir_newest"
    var newestDisabled = testDirection(lane: .bolder)
    newestDisabled.directionId = "dir_newest_disabled"
    newestDisabled.enabled = false
    var older = testDirection(lane: .wildcard)
    older.directionId = "dir_older"
    var olderDisabled = testDirection(lane: .commercial)
    olderDisabled.directionId = "dir_older_disabled"
    olderDisabled.enabled = false

    let ordered = StoryDirectionSet.storylineDisplayOrder([newest, newestDisabled, older, olderDisabled])
    #expect(ordered.map(\.directionId) == ["dir_newest", "dir_older", "dir_newest_disabled", "dir_older_disabled"])
}

@Test
func storyWorkflowDocumentsRoundTripThroughJSON() throws {
    let setup = StorySetupDocument.empty(projectId: "project_test")
    let decodedSetup = try StorySetupDocument.decode(from: setup.encoded())
    #expect(decodedSetup.outputType == .cinematicShort)

    let directionSet = StoryDirectionSet(
        projectId: "project_test",
        directionSetId: "directions_test",
        candidateDirections: StoryDirectionLane.allCases.map(testDirection),
        directions: StoryDirectionLane.allCases.map(testDirection),
        selectedDirectionId: "dir_recommended",
        generatedAt: "2026-06-10T00:00:00Z"
    )
    let history = StoryDirectionHistoryDocument.empty(projectId: "project_test").appending(directionSet)
    let decodedHistory = try StoryDirectionHistoryDocument.decode(from: history.encoded())
    #expect(decodedHistory.activeSet.directionSetId == "directions_test")

    let board = testBeatBoard()
    let decodedBoard = try StoryBeatBoard.decode(from: board.encoded())
    #expect(decodedBoard.beats.count == 1)
    #expect(decodedBoard.primaryDirectionId == "dir_recommended")
    #expect(decodedBoard.sourceDirectionIds == ["dir_recommended"])

    var multiSourceBoard = board
    multiSourceBoard.primaryDirectionId = "dir_recommended"
    multiSourceBoard.sourceDirectionIds = ["dir_recommended", "dir_wildcard"]
    let decodedMultiSourceBoard = try StoryBeatBoard.decode(from: multiSourceBoard.encoded())
    #expect(decodedMultiSourceBoard.sourceDirectionIds == ["dir_recommended", "dir_wildcard"])

    let projectStory = ProjectStoryDocument.accepted(
        projectId: "project_test",
        direction: directionSet.directions.first,
        board: board,
        setup: setup,
        aestheticRecipe: nil,
        acceptedAt: "2026-06-10T00:00:00Z"
    )
    let decodedProjectStory = try ProjectStoryDocument.decode(from: projectStory.encoded())
    #expect(decodedProjectStory.hasAcceptedStory)

    let sceneWorkspace = SceneWorkspaceDocument.forContext(
        projectId: "project_test",
        projectStory: projectStory,
        beatBoard: board,
        createdAt: "2026-06-10T00:00:00Z"
    )
    let decodedSceneWorkspace = try SceneWorkspaceDocument.decode(from: sceneWorkspace.encoded())
    #expect(decodedSceneWorkspace.sourceBeatBoardId == "board_test")

    let sceneAsset = SceneAssetDocument(
        assetId: "asset_test",
        projectId: "project_test",
        beatId: "beat_1",
        sourceBeatBoardId: "board_test",
        sourceProjectStoryId: projectStory.acceptedStoryId,
        sourceBeatIds: ["beat_1"],
        sourceBoardFingerprint: board.inputFingerprint.stableId
    )
    let decodedSceneAsset = try SceneAssetDocument.decode(from: sceneAsset.encoded())
    #expect(decodedSceneAsset.layerType == .audio)
}

@Test
func storyOpenAIResponseSchemasCloseAllObjectDefinitions() throws {
    let schemaNames = [
        "project_goal_interview.schema",
        "story_signal_set.schema",
        "story_direction_set.schema",
        "story_beat_board.schema",
        "story_audio_track_draft.schema"
    ]

    for schemaName in schemaNames {
        let url = try packagedResourceURL(named: schemaName, extension: "json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        var failures: [String] = []
        collectOpenObjectSchemaFailures(json, path: schemaName, failures: &failures)
        #expect(failures.isEmpty, "\(schemaName) has OpenAI-incompatible open objects: \(failures.joined(separator: ", "))")
    }
}

@Test
func storyWorkspaceDecodesLegacyRefsIntoPreviewAndAcceptedProjectStory() throws {
    let json = """
    {
      "schema_version": "litscenes.story_workspace.v0.1",
      "project_id": "project_test",
      "selected_scope": "enabled_media",
      "selected_media_ids": [],
      "current_step": "directions",
      "status": "Story Direction selected",
      "active_direction_set_id": "directions_test",
      "active_direction_id": "dir_recommended",
      "active_beat_board_id": "board_test",
      "accepted_story_id": "story_test",
      "updated_at": "2026-06-10T00:00:00Z"
    }
    """
    let workspace = try StoryWorkspaceDocument.decode(from: Data(json.utf8))
    #expect(workspace.previewDirectionId == "dir_recommended")
    #expect(workspace.acceptedProjectStoryId == "story_test")
}

@Test
func storyPersistenceUsesCanonicalBeatBoardsAndBoardKeyedSequenceStrips() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_story_persistence_\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }
    let store = ProjectContextStore(projectLibrary: ProjectLibrary(root: root))
    let project = ProjectRecord(
        projectId: "project_test",
        name: "Test",
        createdAt: "2026-06-10T00:00:00Z",
        updatedAt: "2026-06-10T00:00:00Z",
        sessionCount: 0,
        lastSessionId: nil
    )
    let board = testBeatBoard()
    try store.saveStoryBeatBoard(board, for: project)
    #expect(!FileManager.default.fileExists(atPath: store.storyBeatBoardURL(for: project, beatBoardId: board.beatBoardId).path))
    #expect(store.loadStoryBeatBoard(for: project, beatBoardId: board.beatBoardId).beatBoardId == board.beatBoardId)

    let strip = StorySequenceStripDocument.fromBeatBoard(board, paletteTerms: ["brass"])
    try store.saveStorySequenceStrip(strip, for: project)
    #expect(!FileManager.default.fileExists(atPath: store.storySequenceStripURL(for: project, beatBoardId: board.beatBoardId).path))
    #expect(store.loadStorySequenceStrip(for: project, beatBoardId: board.beatBoardId).beatBoardId == board.beatBoardId)

    try FileManager.default.createDirectory(at: store.legacyStoryBeatBoardsDirectory(for: project), withIntermediateDirectories: true)
    let legacyURL = store.legacyStoryBeatBoardsDirectory(for: project).appendingPathComponent("board_legacy.json")
    var legacyBoard = board
    legacyBoard.beatBoardId = "board_legacy"
    try legacyBoard.encoded().write(to: legacyURL)
    #expect(!store.loadStoryBeatBoards(for: project).contains { $0.beatBoardId == "board_legacy" })
}

@Test
func sceneWorkspaceAndAssetsReportStaleWhenSourceBoardChanges() {
    let board = testBeatBoard()
    let projectStory = ProjectStoryDocument.accepted(
        projectId: "project_test",
        direction: testDirection(lane: .recommended),
        board: board,
        setup: StorySetupDocument.empty(projectId: "project_test"),
        aestheticRecipe: nil,
        acceptedAt: "2026-06-10T00:00:00Z"
    )
    let workspace = SceneWorkspaceDocument.forContext(
        projectId: "project_test",
        projectStory: projectStory,
        beatBoard: board,
        createdAt: "2026-06-10T00:00:00Z"
    )
    #expect(workspace.freshness(activeBoard: board, acceptedStory: projectStory) == .fresh)

    var changedBoard = board
    changedBoard.beatBoardId = "board_other"
    #expect(workspace.freshness(activeBoard: changedBoard, acceptedStory: projectStory) == .stale)
}

@Test
func beatBoardV02DecodesLegacyDefaultsAndPreservesAnchors() throws {
    let legacyJSON = """
    {
      "schema_version": "litscenes.story_beat_board.v0.1",
      "project_id": "project_test",
      "beat_board_id": "board_legacy",
      "parent_direction_set_id": "directions_test",
      "parent_direction_id": "dir_recommended",
      "story_setup_hash": "setup_hash",
      "aesthetic_recipe_version": "recipe_v1",
      "title": "Legacy Board",
      "logline": "A legacy board still decodes.",
      "central_tension": "old vs new",
      "story_engine": "Evidence escalates",
      "format": "cinematic_short",
      "target_duration": "60 seconds",
      "beginning_state": "safe",
      "ending_state": "changed",
      "aesthetic_strategy": {
        "narrative": "domestic breach",
        "presentation": "poster art",
        "aesthetic_risks": []
      },
      "beats": [
        {
          "beat_id": "beat_1",
          "order": 1,
          "locked": false,
          "title": "Legacy Beat",
          "event": "The phone catches hidden evidence.",
          "visual_moment": "A mirror looks normal while a phone sees a colder room.",
          "emotional_turn": "Curiosity becomes dread.",
          "meaning_move": "A household object becomes proof.",
          "story_function": "first proof",
          "aesthetic_narrative_binding": ["domestic breach"],
          "aesthetic_presentation_binding": ["poster art"],
          "prompt_ready_line": "Close mirror shot with phone-reflection evidence.",
          "voice_or_text_overlay": "YOU CAN'T SEE THE WAR",
          "invented_elements": [],
          "risks": [],
          "support_status": "invented_from_goal_and_aesthetic",
          "origin": "goal_aesthetic_invention",
          "meaning_node_refs": [],
          "beat_function_refs": [],
          "archetypal_situation_refs": [],
          "lens_refs": [],
          "graph_support_summary": "Legacy graph summary."
        }
      ]
    }
    """
    let legacy = try StoryBeatBoard.decode(from: Data(legacyJSON.utf8))
    #expect(legacy.beats.first?.sourceMediaIds == [])
    #expect(legacy.beats.first?.avoidMediaIds == [])
    #expect(legacy.beats.first?.referenceMediaIds == [])
    #expect(legacy.beats.first?.mediaAnchors == [])
    #expect(legacy.beats.first?.isDeleted == false)
    #expect(legacy.beats.first?.generationBrief.subject == "")

    var board = testBeatBoard()
    board.beats[0].sourceMediaIds = ["media_source"]
    board.beats[0].avoidMediaIds = ["media_avoid"]
    board.beats[0].referenceMediaIds = ["media_ref"]
    board.beats[0].mediaAnchors = [
        StoryMediaAnchor(
            anchorId: "anchor_media_source",
            mediaId: "media_source",
            kind: .image,
            role: .source,
            note: "Use the warm hallway.",
            thumbnailPath: "/tmp/source.jpg",
            createdBy: "user"
        )
    ]
    board.beats[0].generationBrief.subject = "gecko only visible in reflection"

    let decoded = try StoryBeatBoard.decode(from: board.encoded())
    #expect(decoded.schemaVersion == "litscenes.story_beat_board.v0.3")
    #expect(decoded.readyLensSetHash == "")
    #expect(decoded.lensRowSnapshots == [])
    #expect(decoded.beats[0].lensRowSnapshots == [])
    #expect(decoded.beats[0].mediaAnchors.first?.role == .source)
    #expect(decoded.beats[0].sourceMediaIds == ["media_source"])
    #expect(decoded.beats[0].generationBrief.subject == "gecko only visible in reflection")
}

@MainActor
@Test
func beatEditOperationsProtectLocksAndPreserveStableIds() throws {
    let fixture = try makeEngineFixture(beats: testThreeBeatSequence())
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    fixture.engine.setStoryBeatLocked(beatId: "beat_1", locked: true)
    var lockedEdit = fixture.engine.storyBeatBoard.visibleBeats[0]
    lockedEdit.title = "Should Not Apply"
    fixture.engine.updateStoryBeat(lockedEdit)
    #expect(fixture.engine.storyBeatBoard.visibleBeats[0].title != "Should Not Apply")

    let beforeMoveIds = fixture.engine.storyBeatBoard.visibleBeats.map(\.beatId)
    fixture.engine.moveStoryBeat(beatId: "beat_3", placement: .start)
    #expect(fixture.engine.storyBeatBoard.visibleBeats.first?.beatId == "beat_3")
    #expect(Set(fixture.engine.storyBeatBoard.visibleBeats.map(\.beatId)) == Set(beforeMoveIds))

    fixture.engine.duplicateStoryBeat(beatId: "beat_2")
    let idsAfterDuplicate = fixture.engine.storyBeatBoard.visibleBeats.map(\.beatId)
    #expect(idsAfterDuplicate.count == 4)
    #expect(Set(idsAfterDuplicate).count == idsAfterDuplicate.count)

    fixture.engine.softDeleteStoryBeat(beatId: "beat_1")
    #expect(fixture.engine.storyBeatBoard.beats.first { $0.beatId == "beat_1" }?.isDeleted == false)
}

@MainActor
@Test
func sceneAssetsAreIdempotentAndManualPromptsAreProtected() async throws {
    let fixture = try makeEngineFixture(beats: testThreeBeatSequence())
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.engine.useActiveDraftBoardForScenes()

    guard let beat = fixture.engine.activeSceneSourceBeats.first else {
        throw StoryWorkflowTestError.missingBeat
    }
    let firstVirtual = fixture.engine.sceneAssetForMatrix(beat: beat, layerType: .still)
    let secondVirtual = fixture.engine.sceneAssetForMatrix(beat: beat, layerType: .still)
    #expect(firstVirtual.assetId == secondVirtual.assetId)

    await fixture.engine.prepareSceneLayersForActiveContext()
    let firstCount = fixture.engine.sceneAssets.count
    await fixture.engine.prepareSceneLayersForActiveContext()
    #expect(fixture.engine.sceneAssets.count == firstCount)
    #expect(Set(fixture.engine.sceneAssets.map(\.assetId)).count == fixture.engine.sceneAssets.count)

    fixture.engine.updateSceneAsset(
        assetId: firstVirtual.assetId,
        prompt: "Manual still prompt",
        negativePrompt: "Manual avoid",
        textOverlay: "Manual overlay",
        captionDraft: "Manual caption"
    )
    await fixture.engine.prepareSceneLayersForActiveContext(refreshPrompts: true)
    let edited = fixture.engine.sceneAssets.first { $0.assetId == firstVirtual.assetId }
    #expect(edited?.prompt == "Manual still prompt")
    #expect(edited?.isManuallyEdited == true)
    #expect(edited?.manualEditFields.contains("prompt") == true)
}

@MainActor
@Test
func scenesPreferAcceptedProjectStoryAndCanSwitchToDraftBoard() throws {
    let fixture = try makeEngineFixture(beats: testThreeBeatSequence())
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    fixture.engine.acceptActiveProjectStory()
    #expect(fixture.engine.projectStory.hasAcceptedStory)
    #expect(fixture.engine.sceneWorkspace.sourceArtifactType == .projectStory)
    #expect(fixture.engine.activeSceneSourceBeats.map(\.beatId) == fixture.engine.projectStory.beats.map(\.beatId))

    fixture.engine.useActiveDraftBoardForScenes()
    #expect(fixture.engine.sceneWorkspace.sourceArtifactType == .beatBoard)
    #expect(fixture.engine.sceneWorkspace.sourceBeatBoardId == fixture.engine.storyBeatBoard.beatBoardId)
}

@MainActor
@Test
func legacyStorySuggestionsUpgradeToKeptProjectStoriesOnLoad() throws {
    let fixture = try makeEngineFixture(beats: testThreeBeatSequence())
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let ids = try installLegacyStorySuggestion(fixture)

    fixture.engine.selectProject(fixture.project)

    let entry = try #require(fixture.engine.storyLibrary.entries.first { $0.storySuggestionId == ids.storySuggestionId })
    #expect(entry.editorialState == .kept)
    #expect(!entry.projectStoryId.isEmpty)
    #expect(!entry.currentVersionId.isEmpty)
    #expect(fixture.engine.storyLibrary.activeStoryId == entry.projectStoryId)

    let version = fixture.store.loadProjectStoryVersion(
        for: fixture.project,
        projectStoryId: entry.projectStoryId,
        storyVersionId: entry.currentVersionId
    )
    #expect(version?.sourceStorySuggestionId == ids.storySuggestionId)
    #expect(version?.story.title == ids.title)

    let signature = try #require(fixture.store.loadStorySignature(for: fixture.project, storySignatureId: ids.storySignatureId))
    #expect(signature.editorialState == .kept)
    #expect(signature.projectStoryId == entry.projectStoryId)
    #expect(signature.storyVersionId == entry.currentVersionId)
}

@MainActor
@Test
func removeAndRestoreStoryPreservesGeneratedData() throws {
    let fixture = try makeEngineFixture(beats: testThreeBeatSequence())
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let ids = try installLegacyStorySuggestion(fixture)
    fixture.engine.selectProject(fixture.project)
    let upgraded = try #require(fixture.engine.storyLibrary.entries.first { $0.storySuggestionId == ids.storySuggestionId })

    fixture.engine.removeStoryLibraryEntry(libraryEntryId: upgraded.libraryEntryId)

    let removed = try #require(fixture.engine.storyLibrary.entries.first { $0.libraryEntryId == upgraded.libraryEntryId })
    #expect(removed.editorialState == .dismissed)
    #expect(fixture.engine.storyLibrary.activeStoryId.isEmpty)
    let removedSignature = try #require(fixture.store.loadStorySignature(for: fixture.project, storySignatureId: ids.storySignatureId))
    #expect(removedSignature.editorialState == .dismissed)
    #expect(fixture.store.loadProjectStoryVersion(
        for: fixture.project,
        projectStoryId: removed.projectStoryId,
        storyVersionId: removed.currentVersionId
    ) != nil)

    fixture.engine.restoreStoryLibraryEntry(libraryEntryId: upgraded.libraryEntryId)

    let restored = try #require(fixture.engine.storyLibrary.entries.first { $0.libraryEntryId == upgraded.libraryEntryId })
    #expect(restored.editorialState == .kept)
    #expect(fixture.engine.storyLibrary.activeStoryId == restored.projectStoryId)
    let restoredSignature = try #require(fixture.store.loadStorySignature(for: fixture.project, storySignatureId: ids.storySignatureId))
    #expect(restoredSignature.editorialState == .kept)
    #expect(fixture.store.loadProjectStoryVersion(
        for: fixture.project,
        projectStoryId: restored.projectStoryId,
        storyVersionId: restored.currentVersionId
    ) != nil)
}

@MainActor
@Test
func audioSceneMappingKeepsGlobalAudioSeparateAndMapsBeatAudio() throws {
    let fixture = try makeEngineFixture(beats: testThreeBeatSequence())
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    var global = StoryAudioTrackDocument.empty(projectId: fixture.project.projectId)
    global.trackId = "audio_global"
    global.title = "Global bed"
    global.status = "drafted"
    global.sourceBeatIds = []
    global.scope = "global_project_audio"

    var multiBeat = StoryAudioTrackDocument.empty(projectId: fixture.project.projectId)
    multiBeat.trackId = "audio_multi"
    multiBeat.title = "Two beat bed"
    multiBeat.status = "drafted"
    multiBeat.sourceBeatIds = ["beat_1", "beat_2"]
    multiBeat.scope = "beat_aware_audio"
    multiBeat.beatPrompt = "A tense signal bed."

    var collection = StoryAudioTrackCollectionDocument.empty(projectId: fixture.project.projectId)
    collection = collection.appending(global, activate: false)
    collection = collection.appending(multiBeat, activate: true)
    try fixture.store.saveStoryAudioTracks(collection, for: fixture.project)
    fixture.engine.selectProject(fixture.project)
    fixture.engine.useActiveDraftBoardForScenes()

    #expect(fixture.engine.globalStoryAudioTracks.map(\.trackId) == ["audio_global"])
    guard let firstBeat = fixture.engine.activeSceneSourceBeats.first(where: { $0.beatId == "beat_1" }) else {
        throw StoryWorkflowTestError.missingBeat
    }
    let audioAsset = fixture.engine.sceneAssetForMatrix(beat: firstBeat, layerType: .audio)
    #expect(audioAsset.assetScope == .multiBeat)
    #expect(audioAsset.sourceBeatIds == ["beat_1", "beat_2"])
    #expect(audioAsset.prompt == "A tense signal bed.")
}

@MainActor
@Test
func scenePromptExportWritesMarkdownAndJSONWithSourceMetadata() async throws {
    let fixture = try makeEngineFixture(beats: testThreeBeatSequence())
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    fixture.engine.useActiveDraftBoardForScenes()
    await fixture.engine.prepareSceneLayersForActiveContext()
    await fixture.engine.exportScenePromptsForActiveContext()

    let exportDirectory = fixture.store.sceneExportsDirectory(for: fixture.project)
    let exported = try FileManager.default.contentsOfDirectory(at: exportDirectory, includingPropertiesForKeys: nil)
    let markdownFiles = exported.filter { $0.pathExtension == "md" }
    let jsonFiles = exported.filter { $0.pathExtension == "json" }
    #expect(markdownFiles.count == 1)
    #expect(jsonFiles.count == 1)

    let jsonData = try Data(contentsOf: jsonFiles[0])
    let document = try JSONCoding.decoder.decode(ScenePromptExportDocument.self, from: jsonData)
    #expect(document.projectId == fixture.project.projectId)
    #expect(document.sourceArtifactType == .beatBoard)
    #expect(document.sourceBeatBoardId == fixture.engine.storyBeatBoard.beatBoardId)
    #expect(document.layers.contains { $0.layerType == .still && !$0.layerId.isEmpty })
    #expect(document.layers.allSatisfy { !$0.promptTemplateVersion.isEmpty })
}

private func testGoal(versionId: String, updatedAt: String) -> ProjectGoalDocument {
    let brief = ProjectGoalBrief(
        contentType: .narrative,
        goal: "Create a surreal gecko-war archive story.",
        audience: "Experimental short viewers.",
        desiredAction: "Watch through the end.",
        distributionContext: "Short film.",
        successCriteria: ["Feels intentional."],
        storyPromise: "The phone and mirror reveal a hidden conflict.",
        constraints: ["Do not claim the war is real."],
        openQuestions: [],
        confidence0To1: 0.8
    )
    return ProjectGoalDocument(
        projectId: "project_test",
        messages: [],
        versions: [
            ProjectGoalBriefVersion(
                versionId: versionId,
                turnIndex: 1,
                brief: brief,
                changeSummary: "test",
                createdAt: updatedAt,
                model: "test"
            )
        ],
        activeVersionId: versionId,
        updatedAt: updatedAt
    )
}

private func collectOpenObjectSchemaFailures(_ value: Any, path: String, failures: inout [String]) {
    if let dictionary = value as? [String: Any] {
        if dictionary["type"] as? String == "object" {
            if (dictionary["additionalProperties"] as? Bool) != false {
                failures.append(path)
            }
        }
        for key in dictionary.keys.sorted() {
            if let child = dictionary[key] {
                collectOpenObjectSchemaFailures(child, path: "\(path).\(key)", failures: &failures)
            }
        }
    } else if let array = value as? [Any] {
        for (index, child) in array.enumerated() {
            collectOpenObjectSchemaFailures(child, path: "\(path)[\(index)]", failures: &failures)
        }
    }
}

private func testDirection(lane: StoryDirectionLane) -> StoryDirectionCard {
    StoryDirectionCard(
        directionId: "dir_\(lane.rawValue)",
        lane: lane,
        title: "\(lane.label) Direction",
        premise: "A phone and mirror reveal hidden evidence in a domestic archive.",
        storyEngine: lane == .wildcard ? "Ritual archive" : (lane == .commercial ? "False commercial" : "Evidence escalates"),
        whatHappens: "The story begins as ordinary home evidence, then escalates through reflections and screen proof until the final image reframes the archive.",
        whyItWorks: "It binds the Goal to visible media surfaces and current Aesthetic treatment.",
        aestheticUse: StoryAestheticUse(
            narrative: "domestic normalcy breached, loss of control",
            presentation: "poster art, acid typography"
        ),
        inventedElements: ["warning copy"],
        risk: "Can become too literal if the final beats overexplain the conflict.",
        threeBeatPreview: ["Ordinary home", "First reflection", "Final warning"],
        meaningMoves: ["ordinary object becomes proof", "screen sees hidden layer"],
        commercialPressure: lane == .commercial ? 0.45 : 0.1,
        weirdness: lane == .wildcard ? 0.9 : 0.4,
        promptability: 0.8,
        scoreDebug: StoryDirectionScore(finalScore: lane == .recommended ? 0.9 : 0.75)
    )
}

private func testBeat(
    order: Int = 1,
    event: String,
    visualMoment: String,
    promptReadyLine: String
) -> StoryBeatBoardBeat {
    StoryBeatBoardBeat(
        beatId: "beat_\(order)",
        order: order,
        title: "The Phone Sees Proof",
        event: event,
        visualMoment: visualMoment,
        emotionalTurn: "Curiosity becomes dread.",
        meaningMove: "The ordinary object becomes proof.",
        storyFunction: "first proof",
        aestheticNarrativeBinding: ["domestic normalcy breached"],
        aestheticPresentationBinding: ["acid typography"],
        promptReadyLine: promptReadyLine,
        generationBrief: StoryGenerationBrief(
            subject: "iPhone and mirror evidence",
            setting: "warm domestic room",
            action: "records a hidden gecko signal",
            visualFocus: "phone screen reflection",
            cameraOrFraming: "close evidence frame",
            lighting: "warm yellow interior with cold screen light",
            aestheticTreatment: "American Kitsch poster layout with Acid typography",
            textOverlay: "YOU CAN'T SEE THE WAR",
            negativeConstraints: ["do not claim the war is real"],
            assetTypeHints: ["image", "video", "audio"]
        ),
        voiceOrTextOverlay: "YOU CAN'T SEE THE WAR",
        inventedElements: ["warning copy"],
        risks: ["avoid overexplaining"],
        supportStatus: .inventedFromGoalAndAesthetic,
        origin: .goalAestheticInvention,
        meaningNodeRefs: [
            StoryGraphRef(id: "local_proof", label: "ordinary object becomes proof", kind: "meaning_move", source: "story_pattern_index", confidence: 0.8)
        ],
        beatFunctionRefs: [
            StoryGraphRef(id: "first_proof", label: "first proof", kind: "beat_function", source: "story_pattern_index", confidence: 0.8)
        ],
        archetypalSituationRefs: [],
        lensRefs: [],
        graphSupportSummary: "Uses evidence escalation and domestic breach."
    )
}

private func testBeatBoard() -> StoryBeatBoard {
    StoryBeatBoard(
        projectId: "project_test",
        beatBoardId: "board_test",
        parentDirectionSetId: "directions_test",
        parentDirectionId: "dir_recommended",
        storySetupHash: "setup_hash",
        aestheticRecipeVersion: "recipe_v1",
        title: "The Proof Breaks the Advertisement",
        logline: "A phone and mirror reveal hidden evidence inside a cheerful domestic-commercial world.",
        centralTension: "ordinary home vs hidden proof",
        storyEngine: "Evidence escalates",
        format: StoryOutputType.cinematicShort.rawValue,
        targetDuration: "60-90 seconds",
        beginningState: "The home appears safe.",
        endingState: "The final image becomes a warning.",
        aestheticStrategy: StoryBeatBoardAestheticStrategy(narrative: "domestic breach", presentation: "poster art"),
        beats: [
            testBeat(
                event: "The iPhone camera records the mirror and shows a gecko signal that is not visible in the room.",
                visualMoment: "A warm hallway mirror stays empty while the phone screen shows a colder room with a gecko staring back.",
                promptReadyLine: "Warm domestic mirror shot, iPhone screen reveals hidden gecko signal, poster composition corrupted by acid typography."
            )
        ],
        generatedAt: "2026-06-10T00:00:00Z"
    )
}

private func testBeatBoard(beats: [StoryBeatBoardBeat]) -> StoryBeatBoard {
    var board = testBeatBoard()
    board.beats = beats
    return board
}

private func testThreeBeatSequence() -> [StoryBeatBoardBeat] {
    [
        testBeat(
            order: 1,
            event: "The iPhone camera records the mirror and shows a gecko signal that is not visible in the room.",
            visualMoment: "A warm hallway mirror stays empty while the phone screen shows a colder room with a gecko staring back.",
            promptReadyLine: "Warm domestic mirror shot, iPhone screen reveals hidden gecko signal, poster composition corrupted by acid typography."
        ),
        testBeat(
            order: 2,
            event: "A second image proves the signal repeats from another household surface.",
            visualMoment: "A blue warning mark crawls across a drink container while the room remains cheerful.",
            promptReadyLine: "Close kitchen surface, bright drink container, blue warning mark, kitsch commercial lighting under corrupted signal overlays."
        ),
        testBeat(
            order: 3,
            event: "The final reflection turns the household archive into a warning poster.",
            visualMoment: "The phone, mirror, and gecko align into a flat final warning image.",
            promptReadyLine: "Final poster-like reflection, phone and mirror aligned, tiny gecko signal becomes warning typography."
        )
    ]
}

private struct StoryWorkflowEngineFixture {
    let engine: LibraryEngine
    let store: ProjectContextStore
    let project: ProjectRecord
    let root: URL
}

private struct LegacyStorySuggestionIds {
    let storySuggestionId: String
    let storySignatureId: String
    let title: String
}

private enum StoryWorkflowTestError: Error {
    case missingProject
    case missingBeat
}

private func installLegacyStorySuggestion(_ fixture: StoryWorkflowEngineFixture) throws -> LegacyStorySuggestionIds {
    let now = DateFormats.now()
    let storySuggestionId = "story_suggestion_legacy"
    let story = SceneStory(
        storyId: "story_legacy",
        order: 1,
        title: "Legacy Generated Story",
        premise: "A generated Story that predates kept-by-default persistence.",
        meaningThesis: "Kept by default preserves generated Story intent.",
        tone: "clear",
        visualWorld: "warm archive",
        scenes: []
    )
    var set = SceneStorySetDocument()
    set.sceneStorySetId = "scene_story_set_legacy"
    set.projectId = fixture.project.projectId
    set.storyCount = 1
    set.scenesPerStory = 0
    set.beatsPerScene = 0
    set.generatedAt = now
    set.sceneStories = [story]
    try fixture.store.saveSceneStorySet(set, for: fixture.project)

    var signature = StorySignatureDocument()
    signature.projectId = fixture.project.projectId
    signature.storySuggestionId = storySuggestionId
    signature.sourceSceneStorySetId = set.sceneStorySetId
    signature.sourceStoryId = story.storyId
    signature.title = story.title
    signature.premise = story.premise
    signature.meaningThesis = story.meaningThesis
    signature.editorialState = .suggestion
    signature.productionState = .notStarted
    signature.createdAt = now
    signature.updatedAt = now
    signature = signature.normalized()
    try fixture.store.saveStorySignature(signature, for: fixture.project)

    var library = ProjectStoryLibraryDocument.empty(projectId: fixture.project.projectId)
    library.entries = [
        ProjectStoryLibraryEntry(
            storySuggestionId: storySuggestionId,
            sourceSceneStorySetId: set.sceneStorySetId,
            sourceStoryId: story.storyId,
            generationSessionId: "story_generation_session_legacy",
            editorialState: .suggestion,
            productionState: .notStarted,
            title: story.title,
            storySignatureId: signature.storySignatureId,
            createdAt: now,
            updatedAt: now
        ).normalized()
    ]
    library.updatedAt = now
    try fixture.store.saveProjectStoryLibrary(library, for: fixture.project)
    return LegacyStorySuggestionIds(
        storySuggestionId: storySuggestionId,
        storySignatureId: signature.storySignatureId,
        title: story.title
    )
}

@MainActor
private func makeEngineFixture(beats: [StoryBeatBoardBeat]) throws -> StoryWorkflowEngineFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_story_engine_\(UUID().uuidString)", isDirectory: true)
    let projectLibrary = ProjectLibrary(root: root)
    let engine = LibraryEngine(projectLibrary: projectLibrary)
    let projectName = "Test \(UUID().uuidString.prefix(8))"
    #expect(engine.createProject(named: projectName))
    guard let project = engine.currentProject else {
        throw StoryWorkflowTestError.missingProject
    }
    let store = ProjectContextStore(projectLibrary: projectLibrary)
    var board = testBeatBoard(beats: beats)
    board.projectId = project.projectId
    board.inputFingerprint = engine.currentStoryInputFingerprint
    board.beats = board.beats.map { beat in
        var updated = beat
        updated.validationWarnings = StoryValidation.beatWarnings(updated)
        return updated
    }
    try store.saveStoryBeatBoard(board, for: project)
    try store.saveStorySequenceStrip(StorySequenceStripDocument.fromBeatBoard(board, paletteTerms: ["brass"]), for: project)
    engine.selectProject(project)
    return StoryWorkflowEngineFixture(engine: engine, store: store, project: project, root: root)
}
