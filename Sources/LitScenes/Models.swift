import Foundation

enum ScreenGraphConstants {
    static let draftSchemaVersion = "litscenes.screen_graph_hydration_draft.v0.1"
    static let contextSchemaVersion = "litscenes.screen_graph_hydration_context.v0.1"
    static let promptVersion = "screen_graph.hydration.v0.1"
    static let observerRuntime = "screen-graph-recorder.swift.v0.1"
}

enum CaptureStatus: String, Codable {
    case buffered
    case diffCheck = "diff_check"
    case skipped
    case queued
    case analyzing
    case hydrated
    case erased
    case failed
}

enum DiffDecisionKind: String, Codable {
    case firstFrame = "first_frame"
    case exactDuplicate = "exact_duplicate"
    case cursorOnlyOrTinyChange = "cursor_or_tiny_change"
    case ocrChanged = "ocr_changed"
    case visualChanged = "visual_changed"
    case heartbeat = "heartbeat"
}

enum ImageDetail: String, Codable, CaseIterable, Identifiable {
    case high
    case original

    var id: String { rawValue }
}

enum SubjectScope: String, Codable, CaseIterable {
    case brand
    case business
    case `self`
    case person
    case project
    case product
    case event
    case storyWorld = "story_world"
    case unknown
}

enum SurfaceKind: String, Codable, CaseIterable {
    case website
    case app
    case document
    case deck
    case socialProfile = "social_profile"
    case mediaLibrary = "media_library"
    case canvas
    case codeRepo = "code_repo"
    case fileBrowser = "file_browser"
    case unknown
}

enum EvidenceKind: String, Codable, CaseIterable {
    case onScreenText = "on_screen_text"
    case visibleUI = "visible_ui"
    case visibleMedia = "visible_media"
    case urlOrWindowMetadata = "url_or_window_metadata"
    case userProvided = "user_provided"
    case agentInference = "agent_inference"
}

enum PIIRisk: String, Codable, CaseIterable {
    case none
    case low
    case medium
    case high
}

enum NodeKind: String, Codable, CaseIterable {
    case symbol
    case motif
    case theme
    case meaningClaim = "meaning_claim"
    case valueTension = "value_tension"
    case archetypalSituation = "archetypal_situation"
    case transformation
    case mood
    case genreForce = "genre_force"
    case beatFunction = "beat_function"
    case sceneRole = "scene_role"
}

enum AbstractionLevel: String, Codable, CaseIterable {
    case literal
    case symbolic
    case dramatic
    case thematic
    case mythic
    case philosophical
}

enum EdgeRelation: String, Codable, CaseIterable {
    case specializes
    case expresses
    case symbolizes
    case implies
    case evokes
    case contrastsWith = "contrasts_with"
    case inverts
    case dependsOn = "depends_on"
    case intensifies
    case resolves
    case corrupts
    case foreshadows
    case transformsInto = "transforms_into"
    case isExampleOf = "is_example_of"
    case coOccursWith = "co_occurs_with"
}

enum ClaimStatus: String, Codable, CaseIterable {
    case observed
    case inferred
    case userProvided = "user_provided"
    case needsReview = "needs_review"
}

struct DraftObservedScreenSurface: Codable, Hashable {
    var kind: SurfaceKind
    var appOrSite: String
    var titleOrUrl: String
    var captureRef: String
    var visibleTextSummary: String
    var literalVisualSummary: String
    var piiRisk: PIIRisk
    var redactionNotes: [String]
    var confidence0To1: Double
}

struct DraftScreenEvidence: Codable, Hashable {
    var surfaceIndex: Int?
    var kind: EvidenceKind
    var quoteOrSummary: String
    var whereSeen: String
    var confidence0To1: Double
}

struct DraftObservedSubjectProfile: Codable, Hashable {
    var scope: SubjectScope
    var canonicalName: String
    var aliases: [String]
    var oneLineIdentity: String
    var domains: [String]
    var visibleOfferings: [String]
    var visibleAudiences: [String]
    var peopleOrRoles: [String]
    var places: [String]
    var channels: [String]
    var visualIdentitySignals: [String]
    var voiceToneSignals: [String]
    var evidenceIndices: [Int]
}

struct DraftKnowledgeClaim: Codable, Hashable {
    var claim: String
    var status: ClaimStatus
    var evidenceIndices: [Int]
    var confidence0To1: Double
}

struct NorthStarSignals: Codable, Hashable {
    var literallyShowing: [String]
    var impliedArchetypalSituations: [String]
    var activeSymbols: [String]
    var valueTensions: [String]
    var expressedThoughts: [String]
    var supportedThemes: [String]
    var transformationPotential: [String]
    var likelyBeatFunctions: [String]
    var negativeConstraints: [String]
}

struct DraftScreenGraphSeedNode: Codable, Hashable {
    var kind: NodeKind
    var abstractionLevel: AbstractionLevel
    var name: String
    var definition: String
    var meaningClaim: String
    var positiveExpression: String
    var negativeExpression: String
    var boundary: String
    var aliases: [String]
    var tags: [String]
    var evidenceIndices: [Int]
    var confidenceScore: Double
    var reuseScore: Double
    var reviewNote: String
}

struct DraftScreenGraphSeedEdge: Codable, Hashable {
    var sourceSeedNodeIndex: Int
    var targetSeedNodeIndex: Int
    var relationType: EdgeRelation
    var rationale: String
    var evidenceIndices: [Int]
    var confidenceScore: Double
}

struct ScreenGraphHydrationDraft: Codable, Hashable {
    var schemaVersion: String
    var observationGoal: String
    var subject: DraftObservedSubjectProfile
    var surfaces: [DraftObservedScreenSurface]
    var evidence: [DraftScreenEvidence]
    var claims: [DraftKnowledgeClaim]
    var northStarSignals: NorthStarSignals
    var seedNodes: [DraftScreenGraphSeedNode]
    var seedEdges: [DraftScreenGraphSeedEdge]
    var openQuestionsForUser: [String]
    var uncertaintyNotes: [String]
    var privacyWarnings: [String]
    var operatorSummary: String
}

struct ObservedScreenSurface: Codable, Hashable, Identifiable {
    var surfaceId: String
    var id: String { surfaceId }
    var kind: SurfaceKind
    var appOrSite: String
    var titleOrUrl: String
    var captureRef: String
    var observedAt: String
    var visibleTextSummary: String
    var literalVisualSummary: String
    var piiRisk: PIIRisk
    var redactionNotes: [String]
    var confidence0To1: Double
}

struct ScreenEvidence: Codable, Hashable, Identifiable {
    var evidenceId: String
    var id: String { evidenceId }
    var surfaceId: String
    var kind: EvidenceKind
    var quoteOrSummary: String
    var whereSeen: String
    var confidence0To1: Double
}

struct ObservedSubjectProfile: Codable, Hashable {
    var scope: SubjectScope
    var canonicalName: String
    var aliases: [String]
    var oneLineIdentity: String
    var domains: [String]
    var visibleOfferings: [String]
    var visibleAudiences: [String]
    var peopleOrRoles: [String]
    var places: [String]
    var channels: [String]
    var visualIdentitySignals: [String]
    var voiceToneSignals: [String]
    var evidenceIds: [String]
}

struct KnowledgeClaim: Codable, Hashable, Identifiable {
    var claimId: String
    var id: String { claimId }
    var claim: String
    var status: ClaimStatus
    var evidenceIds: [String]
    var confidence0To1: Double
}

struct ScreenGraphSeedNode: Codable, Hashable, Identifiable {
    var seedNodeId: String
    var id: String { seedNodeId }
    var kind: NodeKind
    var abstractionLevel: AbstractionLevel
    var name: String
    var definition: String
    var meaningClaim: String
    var positiveExpression: String
    var negativeExpression: String
    var boundary: String
    var aliases: [String]
    var tags: [String]
    var evidenceIds: [String]
    var confidenceScore: Double
    var reuseScore: Double
    var reviewNote: String
}

struct ScreenGraphSeedEdge: Codable, Hashable {
    var sourceSeedNodeId: String
    var targetSeedNodeId: String
    var relationType: EdgeRelation
    var rationale: String
    var evidenceIds: [String]
    var confidenceScore: Double
}

struct ScreenGraphHydrationContext: Codable, Hashable, Identifiable {
    var recordId: String?
    var id: String { recordId ?? createdAt }
    var schemaVersion: String
    var promptVersion: String
    var observerRuntime: String
    var observerModel: String
    var createdAt: String
    var observationGoal: String
    var subject: ObservedSubjectProfile
    var surfaces: [ObservedScreenSurface]
    var evidence: [ScreenEvidence]
    var claims: [KnowledgeClaim]
    var northStarSignals: NorthStarSignals
    var seedNodes: [ScreenGraphSeedNode]
    var seedEdges: [ScreenGraphSeedEdge]
    var openQuestionsForUser: [String]
    var uncertaintyNotes: [String]
    var privacyWarnings: [String]
    var operatorSummary: String
}

struct CaptureRecord: Codable, Identifiable, Hashable {
    var captureId: String
    var id: String { captureId }
    var sessionId: String
    var capturedAt: String
    var status: CaptureStatus
    var path: String
    var relPath: String
    var width: Int
    var height: Int
    var byteCount: Int
    var sha256: String
    var perceptualHash: UInt64
    var ocrFingerprint: String
    var diffDecision: DiffDecisionKind
    var diffScore: Int
    var estimatedCostUsd: Double
    var message: String
}

struct UsageRecord: Codable, Hashable {
    var recordId: String
    var sessionId: String
    var captureId: String
    var model: String
    var detail: String
    var inputTokens: Int
    var cachedInputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var estimatedCostUsd: Double
    var actualCostUsd: Double
    var createdAt: String
}

struct EventRecord: Codable, Hashable {
    var eventId: String
    var sessionId: String
    var kind: String
    var message: String
    var createdAt: String
}

struct SummaryRecord: Codable, Identifiable, Hashable {
    var summaryId: String
    var id: String { summaryId }
    var sessionId: String
    var kind: String
    var createdAt: String
    var analyzedCaptureCount: Int
    var summary: String
}

struct AnalysisEnvelope: Codable, Identifiable, Hashable {
    var recordId: String
    var id: String { recordId }
    var recordKind: String
    var sessionId: String
    var captureId: String
    var createdAt: String
    var captureRef: String
    var imageSha256: String
    var model: String
    var promptVersion: String
    var usage: UsageRecord
    var payload: ScreenGraphHydrationContext
}

struct ProjectRecord: Codable, Identifiable, Hashable {
    var projectId: String
    var id: String { projectId }
    var name: String
    var createdAt: String
    var updatedAt: String
    var sessionCount: Int
    var lastSessionId: String?
}

enum VisionTheme: String, Codable, CaseIterable, Identifiable {
    case sageClayBlue = "sage_clay_blue"
    case ivoryGoldBlue = "ivory_gold_blue"
    case mintCoralIndigo = "mint_coral_indigo"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sageClayBlue:
            return "Sage / Clay / Blue"
        case .ivoryGoldBlue:
            return "Ivory / Gold / Blue"
        case .mintCoralIndigo:
            return "Mint / Coral / Indigo"
        }
    }
}

struct VisionUIPreferencesDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.vision_ui.v0.1"
    var projectId: String
    var selectedTheme: VisionTheme = .sageClayBlue
    var updatedAt: String = DateFormats.now()

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case selectedTheme = "selected_theme"
        case updatedAt = "updated_at"
    }

    static func empty(projectId: String = "") -> VisionUIPreferencesDocument {
        VisionUIPreferencesDocument(projectId: projectId)
    }
}

enum StoryDefinitionLevel: String, Codable, CaseIterable, Identifiable {
    case seed
    case usable
    case castReady = "cast_ready"
    case storyReady = "story_ready"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .seed:
            return "Seed"
        case .usable:
            return "Usable"
        case .castReady:
            return "Cast Ready"
        case .storyReady:
            return "Story Ready"
        }
    }

    var progress: Double {
        switch self {
        case .seed:
            return 0.25
        case .usable:
            return 0.5
        case .castReady:
            return 0.75
        case .storyReady:
            return 1
        }
    }
}

enum ProjectIntent: String, Codable, CaseIterable, Identifiable, Sendable {
    case brand
    case product
    case service
    case personalStory = "personal_story"
    case documentary
    case narrative
    case ambient
    case experimental

    var id: String { rawValue }

    var label: String {
        switch self {
        case .brand:
            return "Brand"
        case .product:
            return "Product"
        case .service:
            return "Service"
        case .personalStory:
            return "Personal Story"
        case .documentary:
            return "Documentary"
        case .narrative:
            return "Narrative"
        case .ambient:
            return "Ambient"
        case .experimental:
            return "Experimental"
        }
    }

    var shortDescription: String {
        switch self {
        case .brand:
            return "identity, trust, recognition"
        case .product:
            return "object, offer, proof"
        case .service:
            return "outcome, expertise, desire"
        case .personalStory:
            return "memory, self, transformation"
        case .documentary:
            return "truth, place, evidence"
        case .narrative:
            return "characters, conflict, arc"
        case .ambient:
            return "mood, rhythm, atmosphere"
        case .experimental:
            return "form, surprise, rupture"
        }
    }

    var defaultEndGoal: String {
        switch self {
        case .brand:
            return "Create a clear, memorable brand film that turns the media archive into a coherent expression of identity, trust, and recognition."
        case .product:
            return "Show what the product is, why it matters, and how the archive can prove its value through concrete, visually specific moments."
        case .service:
            return "Communicate the service outcome with credibility and emotional clarity, using the archive to show expertise, transformation, and desire."
        case .personalStory:
            return "Shape the archive into a personal story about memory, change, and the moments that reveal who this is for."
        case .documentary:
            return "Build a truthful, place-aware documentary direction grounded in evidence, atmosphere, and the lived details inside the archive."
        case .narrative:
            return "Develop a story-driven film with character, tension, and transformation, using the archive as source material for a clear emotional arc."
        case .ambient:
            return "Create an atmospheric visual piece driven by mood, rhythm, texture, and the strongest sensory qualities in the archive."
        case .experimental:
            return "Use the archive as material for a surprising formal experiment that explores rupture, pattern, and unexpected meaning."
        }
    }
}

enum ProjectGoalMessageRole: String, Codable, Hashable {
    case user
    case assistant
}

struct ProjectGoalMessage: Codable, Hashable, Identifiable {
    var messageId: String
    var id: String { messageId }
    var role: ProjectGoalMessageRole
    var text: String
    var mediaIds: [String]
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case role
        case text
        case mediaIds = "media_ids"
        case createdAt = "created_at"
    }
}

struct ProjectAestheticIntentSeed: Codable, Hashable, Sendable {
    var emotionalTargets: [String] = []
    var narrativeValues: [String] = []
    var visualMood: [String] = []
    var paletteHints: [String] = []
    var motifHints: [String] = []
    var eraHints: [String] = []
    var energy: [String] = []
    var avoid: [String] = []
    var openStyleQuestions: [String] = []
    var confidence0To1: Double = 0

    enum CodingKeys: String, CodingKey {
        case emotionalTargets = "emotional_targets"
        case narrativeValues = "narrative_values"
        case visualMood = "visual_mood"
        case paletteHints = "palette_hints"
        case motifHints = "motif_hints"
        case eraHints = "era_hints"
        case energy
        case avoid
        case openStyleQuestions = "open_style_questions"
        case confidence0To1 = "confidence_0_to_1"
    }

    static func empty() -> ProjectAestheticIntentSeed {
        ProjectAestheticIntentSeed()
    }

    var hasSignals: Bool {
        !emotionalTargets.isEmpty
            || !narrativeValues.isEmpty
            || !visualMood.isEmpty
            || !paletteHints.isEmpty
            || !motifHints.isEmpty
            || !eraHints.isEmpty
            || !energy.isEmpty
            || !avoid.isEmpty
    }

    func normalized() -> ProjectAestheticIntentSeed {
        var value = self
        value.emotionalTargets = Self.clean(emotionalTargets, limit: 8)
        value.narrativeValues = Self.clean(narrativeValues, limit: 8)
        value.visualMood = Self.clean(visualMood, limit: 8)
        value.paletteHints = Self.clean(paletteHints, limit: 8)
        value.motifHints = Self.clean(motifHints, limit: 8)
        value.eraHints = Self.clean(eraHints, limit: 6)
        value.energy = Self.clean(energy, limit: 6)
        value.avoid = Self.clean(avoid, limit: 8)
        value.openStyleQuestions = Self.clean(openStyleQuestions, limit: 4)
        value.confidence0To1 = min(max(confidence0To1, 0), 1)
        return value
    }

    private static func clean(_ values: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = value.lowercased()
            guard !value.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            return value
        }
        .prefix(limit)
        .map { $0 }
    }
}

struct ProjectGoalStorySetupOption: Codable, Hashable, Identifiable, Sendable {
    var optionId: String = ""
    var id: String { stableId }
    var label: String = ""
    var promptValue: String = ""
    var rationale: String = ""

    private enum SnakeCodingKeys: String, CodingKey {
        case optionId = "option_id"
        case label
        case promptValue = "prompt_value"
        case rationale
    }

    private enum CamelCodingKeys: String, CodingKey {
        case optionId
        case label
        case promptValue
        case rationale
    }

    init(
        optionId: String = "",
        label: String = "",
        promptValue: String = "",
        rationale: String = ""
    ) {
        self.optionId = optionId
        self.label = label
        self.promptValue = promptValue
        self.rationale = rationale
    }

    init(from decoder: Decoder) throws {
        let snake = try decoder.container(keyedBy: SnakeCodingKeys.self)
        let camel = try decoder.container(keyedBy: CamelCodingKeys.self)
        optionId = try snake.decodeIfPresent(String.self, forKey: .optionId)
            ?? camel.decodeIfPresent(String.self, forKey: .optionId)
            ?? ""
        label = try snake.decodeIfPresent(String.self, forKey: .label)
            ?? camel.decodeIfPresent(String.self, forKey: .label)
            ?? ""
        promptValue = try snake.decodeIfPresent(String.self, forKey: .promptValue)
            ?? camel.decodeIfPresent(String.self, forKey: .promptValue)
            ?? ""
        rationale = try snake.decodeIfPresent(String.self, forKey: .rationale)
            ?? camel.decodeIfPresent(String.self, forKey: .rationale)
            ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SnakeCodingKeys.self)
        try container.encode(optionId, forKey: .optionId)
        try container.encode(label, forKey: .label)
        try container.encode(promptValue, forKey: .promptValue)
        try container.encode(rationale, forKey: .rationale)
    }

    var stableId: String {
        let trimmedId = optionId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedId.isEmpty { return trimmedId }
        return shortHash("\(label)|\(promptValue)", length: 12)
    }

    var displayLabel: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? promptValue.trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
    }

    var effectivePromptValue: String {
        let trimmed = promptValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? displayLabel : trimmed
    }

    var hasContent: Bool {
        !displayLabel.isEmpty
    }

    static func empty() -> ProjectGoalStorySetupOption {
        ProjectGoalStorySetupOption()
    }
}

struct ProjectGoalStorySetupSuggestions: Codable, Hashable, Sendable {
    var povOptions: [ProjectGoalStorySetupOption] = []
    var engineOptions: [ProjectGoalStorySetupOption] = []
    var endingOptions: [ProjectGoalStorySetupOption] = []

    private enum SnakeCodingKeys: String, CodingKey {
        case povOptions = "pov_options"
        case engineOptions = "engine_options"
        case endingOptions = "ending_options"
    }

    private enum CamelCodingKeys: String, CodingKey {
        case povOptions
        case engineOptions
        case endingOptions
    }

    init(
        povOptions: [ProjectGoalStorySetupOption] = [],
        engineOptions: [ProjectGoalStorySetupOption] = [],
        endingOptions: [ProjectGoalStorySetupOption] = []
    ) {
        self.povOptions = povOptions
        self.engineOptions = engineOptions
        self.endingOptions = endingOptions
    }

    init(from decoder: Decoder) throws {
        let snake = try decoder.container(keyedBy: SnakeCodingKeys.self)
        let camel = try decoder.container(keyedBy: CamelCodingKeys.self)
        povOptions = try snake.decodeIfPresent([ProjectGoalStorySetupOption].self, forKey: .povOptions)
            ?? camel.decodeIfPresent([ProjectGoalStorySetupOption].self, forKey: .povOptions)
            ?? []
        engineOptions = try snake.decodeIfPresent([ProjectGoalStorySetupOption].self, forKey: .engineOptions)
            ?? camel.decodeIfPresent([ProjectGoalStorySetupOption].self, forKey: .engineOptions)
            ?? []
        endingOptions = try snake.decodeIfPresent([ProjectGoalStorySetupOption].self, forKey: .endingOptions)
            ?? camel.decodeIfPresent([ProjectGoalStorySetupOption].self, forKey: .endingOptions)
            ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: SnakeCodingKeys.self)
        try container.encode(povOptions, forKey: .povOptions)
        try container.encode(engineOptions, forKey: .engineOptions)
        try container.encode(endingOptions, forKey: .endingOptions)
    }

    static func empty() -> ProjectGoalStorySetupSuggestions {
        ProjectGoalStorySetupSuggestions()
    }

    func normalized() -> ProjectGoalStorySetupSuggestions {
        ProjectGoalStorySetupSuggestions(
            povOptions: Self.clean(povOptions, limit: 6),
            engineOptions: Self.clean(engineOptions, limit: 6),
            endingOptions: Self.clean(endingOptions, limit: 6)
        )
    }

    private static func clean(_ options: [ProjectGoalStorySetupOption], limit: Int) -> [ProjectGoalStorySetupOption] {
        var seen = Set<String>()
        return options.compactMap { option in
            var cleaned = option
            cleaned.optionId = cleaned.optionId.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.label = cleaned.label.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.promptValue = cleaned.promptValue.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.rationale = cleaned.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = cleaned.displayLabel
            let key = "\(label.lowercased())|\(cleaned.effectivePromptValue.lowercased())"
            guard !label.isEmpty, !seen.contains(key) else { return nil }
            seen.insert(key)
            if cleaned.optionId.isEmpty {
                cleaned.optionId = "goal_setup_\(shortHash(key, length: 12))"
            }
            return cleaned
        }
        .prefix(limit)
        .map { $0 }
    }
}

struct ProjectGoalBrief: Codable, Hashable, Sendable {
    var contentType: ProjectIntent?
    var goal: String = ""
    var audience: String = ""
    var desiredAction: String = ""
    var distributionContext: String = ""
    var successCriteria: [String] = []
    var storyPromise: String = ""
    var constraints: [String] = []
    var openQuestions: [String] = []
    var aestheticIntent: ProjectAestheticIntentSeed = .empty()
    var storySetupSuggestions: ProjectGoalStorySetupSuggestions = .empty()
    var confidence0To1: Double = 0

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case goal
        case audience
        case desiredAction = "desired_action"
        case distributionContext = "distribution_context"
        case successCriteria = "success_criteria"
        case storyPromise = "story_promise"
        case constraints
        case openQuestions = "open_questions"
        case aestheticIntent = "aesthetic_intent"
        case storySetupSuggestions = "story_setup_suggestions"
        case confidence0To1 = "confidence_0_to_1"
    }

    init(
        contentType: ProjectIntent? = nil,
        goal: String = "",
        audience: String = "",
        desiredAction: String = "",
        distributionContext: String = "",
        successCriteria: [String] = [],
        storyPromise: String = "",
        constraints: [String] = [],
        openQuestions: [String] = [],
        aestheticIntent: ProjectAestheticIntentSeed = .empty(),
        storySetupSuggestions: ProjectGoalStorySetupSuggestions = .empty(),
        confidence0To1: Double = 0
    ) {
        self.contentType = contentType
        self.goal = goal
        self.audience = audience
        self.desiredAction = desiredAction
        self.distributionContext = distributionContext
        self.successCriteria = successCriteria
        self.storyPromise = storyPromise
        self.constraints = constraints
        self.openQuestions = openQuestions
        self.aestheticIntent = aestheticIntent
        self.storySetupSuggestions = storySetupSuggestions
        self.confidence0To1 = confidence0To1
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentType = try container.decodeIfPresent(ProjectIntent.self, forKey: .contentType)
        goal = try container.decodeIfPresent(String.self, forKey: .goal) ?? ""
        audience = try container.decodeIfPresent(String.self, forKey: .audience) ?? ""
        desiredAction = try container.decodeIfPresent(String.self, forKey: .desiredAction) ?? ""
        distributionContext = try container.decodeIfPresent(String.self, forKey: .distributionContext) ?? ""
        successCriteria = try container.decodeIfPresent([String].self, forKey: .successCriteria) ?? []
        storyPromise = try container.decodeIfPresent(String.self, forKey: .storyPromise) ?? ""
        constraints = try container.decodeIfPresent([String].self, forKey: .constraints) ?? []
        openQuestions = try container.decodeIfPresent([String].self, forKey: .openQuestions) ?? []
        aestheticIntent = try container.decodeIfPresent(ProjectAestheticIntentSeed.self, forKey: .aestheticIntent) ?? .empty()
        storySetupSuggestions = try container.decodeIfPresent(ProjectGoalStorySetupSuggestions.self, forKey: .storySetupSuggestions) ?? .empty()
        confidence0To1 = try container.decodeIfPresent(Double.self, forKey: .confidence0To1) ?? 0
    }

    static func empty() -> ProjectGoalBrief {
        ProjectGoalBrief()
    }

    var isReadyForAesthetic: Bool {
        contentType != nil && !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ProjectGoalBriefVersion: Codable, Hashable, Identifiable {
    var versionId: String
    var id: String { versionId }
    var turnIndex: Int
    var brief: ProjectGoalBrief
    var changeSummary: String
    var createdAt: String
    var model: String

    enum CodingKeys: String, CodingKey {
        case versionId = "version_id"
        case turnIndex = "turn_index"
        case brief
        case changeSummary = "change_summary"
        case createdAt = "created_at"
        case model
    }
}

struct ProjectGoalDocument: Codable, Hashable {
    static let schemaVersion = "litscenes.project_goal.v0.1"
    static let maximumVersionCount = 21

    var schemaVersion: String = Self.schemaVersion
    var projectId: String
    var messages: [ProjectGoalMessage] = []
    var versions: [ProjectGoalBriefVersion] = []
    var activeVersionId: String = ""
    var updatedAt: String = DateFormats.now()

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case messages
        case versions
        case activeVersionId = "active_version_id"
        case updatedAt = "updated_at"
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func empty(projectId: String = "") -> ProjectGoalDocument {
        ProjectGoalDocument(projectId: projectId)
    }

    static func fromLegacyAesthetic(_ aesthetic: ProjectAestheticDocument, projectId: String) -> ProjectGoalDocument {
        var document = ProjectGoalDocument.empty(projectId: projectId)
        var brief = ProjectGoalBrief.empty()
        brief.contentType = aesthetic.projectIntent
        brief.goal = aesthetic.endGoal
        brief.openQuestions = aesthetic.openQuestions
        brief.confidence0To1 = aesthetic.endGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 0.35
        if brief.isReadyForAesthetic || !brief.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            document.appendVersion(
                brief: brief,
                changeSummary: "Initialized from existing Goal and Content type.",
                model: "local-legacy",
                now: DateFormats.now()
            )
        }
        return document
    }

    static func decode(from data: Data) throws -> ProjectGoalDocument {
        try decoder.decode(ProjectGoalDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? Self.prettyEncoder : Self.encoder).encode(self)
    }

    var activeVersion: ProjectGoalBriefVersion? {
        versions.first { $0.versionId == activeVersionId } ?? versions.last
    }

    var activeBrief: ProjectGoalBrief {
        activeVersion?.brief ?? ProjectGoalBrief.empty()
    }

    var isReadyForAesthetic: Bool {
        activeBrief.isReadyForAesthetic
    }

    mutating func appendMessage(role: ProjectGoalMessageRole, text: String, mediaIds: [String], now: String) {
        messages.append(ProjectGoalMessage(
            messageId: "goal_msg_\(shortHash("\(projectId):\(role.rawValue):\(now):\(messages.count)", length: 12))",
            role: role,
            text: text,
            mediaIds: mediaIds,
            createdAt: now
        ))
        updatedAt = now
    }

    mutating func appendVersion(
        brief: ProjectGoalBrief,
        changeSummary: String,
        model: String,
        now: String
    ) {
        let version = ProjectGoalBriefVersion(
            versionId: "goal_ver_\(shortHash("\(projectId):\(now):\(versions.count):\(brief.goal)", length: 12))",
            turnIndex: messages.count,
            brief: normalizedBrief(brief),
            changeSummary: changeSummary,
            createdAt: now,
            model: model
        )
        versions.append(version)
        if versions.count > Self.maximumVersionCount {
            versions.removeFirst(versions.count - Self.maximumVersionCount)
        }
        activeVersionId = versions.last?.versionId ?? ""
        updatedAt = now
    }

    private func normalizedBrief(_ brief: ProjectGoalBrief) -> ProjectGoalBrief {
        var normalized = brief
        normalized.goal = normalized.goal.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.audience = normalized.audience.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.desiredAction = normalized.desiredAction.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.distributionContext = normalized.distributionContext.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.storyPromise = normalized.storyPromise.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.successCriteria = normalized.successCriteria.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        normalized.constraints = normalized.constraints.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        normalized.openQuestions = normalized.openQuestions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        normalized.aestheticIntent = normalized.aestheticIntent.normalized()
        normalized.storySetupSuggestions = normalized.storySetupSuggestions.normalized()
        normalized.confidence0To1 = min(max(normalized.confidence0To1, 0), 1)
        return normalized
    }
}

struct ProjectGoalInterviewResponse: Codable, Hashable {
    var schemaVersion: String = "litscenes.project_goal_interview_response.v0.2"
    var assistantMessage: String
    var brief: ProjectGoalBrief
    var changeSummary: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case assistantMessage = "assistant_message"
        case brief
        case changeSummary = "change_summary"
    }

    static let decoder = JSONDecoder()

    static func decode(from data: Data) throws -> ProjectGoalInterviewResponse {
        try decoder.decode(ProjectGoalInterviewResponse.self, from: data)
    }
}

struct ProjectAestheticDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.project_aesthetic.v0.1"
    var projectId: String
    var projectIntent: ProjectIntent?
    var endGoal: String = ""
    var name: String = ""
    var summary: String = ""
    var visualStyle: [String] = []
    var mood: [String] = []
    var colorPalette: [String] = []
    var texture: [String] = []
    var composition: [String] = []
    var pacing: [String] = []
    var mustPreserve: [String] = []
    var mustAvoid: [String] = []
    var referenceSignals: [String] = []
    var archiveSignalsUsed: [String] = []
    var confidence0To1: Double = 0
    var openQuestions: [String] = []
    var locked: Bool = false
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case projectIntent = "project_intent"
        case endGoal = "end_goal"
        case name
        case summary
        case visualStyle = "visual_style"
        case mood
        case colorPalette = "color_palette"
        case texture
        case composition
        case pacing
        case mustPreserve = "must_preserve"
        case mustAvoid = "must_avoid"
        case referenceSignals = "reference_signals"
        case archiveSignalsUsed = "archive_signals_used"
        case confidence0To1 = "confidence_0_to_1"
        case openQuestions = "open_questions"
        case locked
        case generatedAt = "generated_at"
        case updatedAt = "updated_at"
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func decode(from data: Data) throws -> ProjectAestheticDocument {
        try decoder.decode(ProjectAestheticDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? Self.prettyEncoder : Self.encoder).encode(self)
    }

    static func empty(projectId: String = "") -> ProjectAestheticDocument {
        ProjectAestheticDocument(projectId: projectId)
    }

    var hasDraft: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var readinessLabel: String {
        if locked {
            return "Locked"
        }
        if hasDraft {
            return "Draft"
        }
        if projectIntent != nil {
            return "Content type"
        }
        return "Open"
    }
}

enum ProjectAestheticLoopLimits {
    static let maxClarificationRounds = 2
    static let initialQuestionLimit = 3
    static let followUpQuestionLimit = 2
}

enum ProjectAestheticClarificationAnswerKind: String, Codable, CaseIterable, Identifiable {
    case text
    case mediaSelection = "media_selection"
    case textAndMedia = "text_and_media"

    var id: String { rawValue }

    var requiresText: Bool {
        self == .text || self == .textAndMedia
    }

    var requiresMedia: Bool {
        self == .mediaSelection || self == .textAndMedia
    }

    var label: String {
        switch self {
        case .text:
            return "Text"
        case .mediaSelection:
            return "Media"
        case .textAndMedia:
            return "Text + Media"
        }
    }

    var suggestionLabel: String {
        switch self {
        case .text:
            return "Suggested: text"
        case .mediaSelection:
            return "Suggested: media examples"
        case .textAndMedia:
            return "Suggested: text + media"
        }
    }
}

struct ProjectAestheticClarificationQuestion: Codable, Identifiable, Hashable {
    var questionId: String
    var id: String { questionId }
    var prompt: String
    var answerKind: ProjectAestheticClarificationAnswerKind
    var required: Bool

    enum CodingKeys: String, CodingKey {
        case questionId = "question_id"
        case prompt
        case answerKind = "answer_kind"
        case required
    }

    static func legacyTextQuestion(projectId: String, prompt: String) -> ProjectAestheticClarificationQuestion {
        ProjectAestheticClarificationQuestion(
            questionId: "legacy_\(shortHash("\(projectId):\(prompt)", length: 12))",
            prompt: prompt,
            answerKind: .text,
            required: true
        )
    }
}

struct ProjectAestheticDraftResponse: Codable, Hashable {
    var schemaVersion: String = "litscenes.project_aesthetic_draft_response.v0.1"
    var aesthetic: ProjectAestheticDocument
    var questions: [ProjectAestheticClarificationQuestion]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case aesthetic
        case questions
    }

    static let decoder = JSONDecoder()

    static func decode(from data: Data) throws -> ProjectAestheticDraftResponse {
        try decoder.decode(ProjectAestheticDraftResponse.self, from: data)
    }
}

enum ProjectAestheticInterviewStatus: String, Codable, Hashable {
    case open
    case answered
    case applied
    case accepted
}

struct ProjectAestheticClarificationAnswer: Codable, Identifiable, Hashable {
    var questionId: String
    var id: String { questionId }
    var answerText: String = ""
    var mediaIds: [String] = []
    var answeredAt: String = ""

    enum CodingKeys: String, CodingKey {
        case questionId = "question_id"
        case answerText = "answer_text"
        case mediaIds = "media_ids"
        case answeredAt = "answered_at"
    }

    var hasContent: Bool {
        !answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !mediaIds.isEmpty
    }
}

struct ProjectAestheticInterviewDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.project_aesthetic_interview.v0.1"
    var projectId: String
    var questions: [ProjectAestheticClarificationQuestion] = []
    var answers: [ProjectAestheticClarificationAnswer] = []
    var status: ProjectAestheticInterviewStatus = .applied
    var currentRound: Int = 0
    var maxRounds: Int = ProjectAestheticLoopLimits.maxClarificationRounds
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()
    var appliedAt: String = ""
    var acceptedAt: String = ""

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case questions
        case answers
        case status
        case currentRound = "current_round"
        case maxRounds = "max_rounds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case appliedAt = "applied_at"
        case acceptedAt = "accepted_at"
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder = JSONDecoder()

    init(
        schemaVersion: String = "litscenes.project_aesthetic_interview.v0.1",
        projectId: String,
        questions: [ProjectAestheticClarificationQuestion] = [],
        answers: [ProjectAestheticClarificationAnswer] = [],
        status: ProjectAestheticInterviewStatus = .applied,
        currentRound: Int = 0,
        maxRounds: Int = ProjectAestheticLoopLimits.maxClarificationRounds,
        createdAt: String = DateFormats.now(),
        updatedAt: String = DateFormats.now(),
        appliedAt: String = "",
        acceptedAt: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.questions = questions
        self.answers = answers
        self.status = status
        self.currentRound = currentRound
        self.maxRounds = maxRounds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.appliedAt = appliedAt
        self.acceptedAt = acceptedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion)
            ?? "litscenes.project_aesthetic_interview.v0.1"
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        questions = try container.decodeIfPresent([ProjectAestheticClarificationQuestion].self, forKey: .questions) ?? []
        answers = try container.decodeIfPresent([ProjectAestheticClarificationAnswer].self, forKey: .answers) ?? []
        status = try container.decodeIfPresent(ProjectAestheticInterviewStatus.self, forKey: .status)
            ?? (questions.isEmpty ? .applied : .open)
        currentRound = try container.decodeIfPresent(Int.self, forKey: .currentRound)
            ?? (questions.isEmpty ? 0 : 1)
        maxRounds = try container.decodeIfPresent(Int.self, forKey: .maxRounds)
            ?? ProjectAestheticLoopLimits.maxClarificationRounds
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? DateFormats.now()
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
        appliedAt = try container.decodeIfPresent(String.self, forKey: .appliedAt) ?? ""
        acceptedAt = try container.decodeIfPresent(String.self, forKey: .acceptedAt) ?? ""
    }

    static func empty(projectId: String = "") -> ProjectAestheticInterviewDocument {
        ProjectAestheticInterviewDocument(projectId: projectId)
    }

    static func fromQuestions(
        projectId: String,
        questions: [ProjectAestheticClarificationQuestion],
        now: String = DateFormats.now()
    ) -> ProjectAestheticInterviewDocument {
        ProjectAestheticInterviewDocument(
            projectId: projectId,
            questions: questions,
            answers: questions.map { ProjectAestheticClarificationAnswer(questionId: $0.questionId) },
            status: questions.isEmpty ? .applied : .open,
            currentRound: questions.isEmpty ? 0 : 1,
            maxRounds: ProjectAestheticLoopLimits.maxClarificationRounds,
            createdAt: now,
            updatedAt: now,
            appliedAt: questions.isEmpty ? now : ""
        )
    }

    static func fromLegacyOpenQuestions(
        projectId: String,
        questions: [String],
        now: String = DateFormats.now()
    ) -> ProjectAestheticInterviewDocument {
        fromQuestions(
            projectId: projectId,
            questions: questions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { ProjectAestheticClarificationQuestion.legacyTextQuestion(projectId: projectId, prompt: $0) },
            now: now
        )
    }

    static func decode(from data: Data) throws -> ProjectAestheticInterviewDocument {
        try decoder.decode(ProjectAestheticInterviewDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? Self.prettyEncoder : Self.encoder).encode(self)
    }

    func answer(for questionId: String) -> ProjectAestheticClarificationAnswer {
        answers.first { $0.questionId == questionId } ?? ProjectAestheticClarificationAnswer(questionId: questionId)
    }

    func isAnswered(_ question: ProjectAestheticClarificationQuestion) -> Bool {
        guard question.required else { return true }
        return answer(for: question.questionId).hasContent
    }

    var allRequiredAnswered: Bool {
        questions.allSatisfy { isAnswered($0) }
    }

    var hasOpenQuestions: Bool {
        !questions.isEmpty && status != .applied && status != .accepted
    }

    var answeredRequiredCount: Int {
        questions.filter { isAnswered($0) }.count
    }

    var hasAnyAnswerContent: Bool {
        answers.contains { $0.hasContent }
    }

    var clampedCurrentRound: Int {
        min(max(currentRound, 0), maxRounds)
    }

    var remainingRoundsAfterCurrent: Int {
        max(maxRounds - clampedCurrentRound, 0)
    }
}

struct StoryRawContextRecord: Codable, Hashable {
    var path: String = "./context"
    var sourceOfTruth: String = "context_folder"
}

struct StoryCharacterRecord: Codable, Identifiable, Hashable {
    var characterId: String
    var id: String { characterId }
    var name: String
    var pronouns: String = ""
    var groups: [String] = []
    var otherNames: [String] = []
    var personality: String = ""
    var motivations: [String] = []
    var internalConflict: String = ""
    var strengths: [String] = []
    var weaknesses: [String] = []
    var characterArc: String = ""
    var physicalDescription: String = ""
    var dialogueStyle: String = ""
    var updatedAt: String = DateFormats.now()

    static func blank(name: String) -> StoryCharacterRecord {
        StoryCharacterRecord(
            characterId: "character_\(stableSlug(name, fallback: "character"))",
            name: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct StoryDefinitionReport: Hashable {
    var level: StoryDefinitionLevel
    var missing: [String]
    var warnings: [String]
    var nextQuestions: [String]
}

struct StoryWorldDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.story_world.v0.1"
    var projectId: String
    var rawContext: StoryRawContextRecord = StoryRawContextRecord()
    var summary: String = ""
    var genre: String = ""
    var style: String = ""
    var characters: [StoryCharacterRecord] = []
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String = "") -> StoryWorldDocument {
        StoryWorldDocument(projectId: projectId)
    }

    var characterNames: String {
        characters.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var definitionReport: StoryDefinitionReport {
        var missing: [String] = []
        var warnings: [String] = []
        var questions: [String] = []

        if rawContext.path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append("raw_context.path")
            questions.append("Choose a context folder")
        }
        for field in [
            ("summary", summary, "Add a project premise"),
            ("genre", genre, "Choose a genre"),
            ("style", style, "Name a style or lens")
        ] where field.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            missing.append(field.0)
            questions.append(field.2)
        }

        if characters.isEmpty {
            warnings.append("No characters named")
            questions.append("Name the first important character")
        }

        for character in characters {
            let prefix = "characters.\(character.characterId)"
            if character.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append("\(prefix).name")
            }
            if character.pronouns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append("\(prefix).pronouns")
            }
            if character.motivations.isEmpty {
                missing.append("\(prefix).motivations")
            }
            if character.internalConflict.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append("\(prefix).internal_conflict")
            }
            if character.physicalDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append("\(prefix).physical_description")
            }
            if character.dialogueStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                missing.append("\(prefix).dialogue_style")
            }
        }

        var level: StoryDefinitionLevel = .seed
        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !genre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !style.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            level = .usable
        }

        let castReady = level == .usable && !characters.isEmpty && characters.allSatisfy { character in
            !character.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !character.pronouns.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !character.motivations.isEmpty
                && !character.internalConflict.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !character.physicalDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !character.dialogueStyle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if castReady {
            level = .castReady
        }
        if castReady,
           characters.contains(where: { !$0.characterArc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
           summary.split(separator: " ").count >= 12 {
            level = .storyReady
        }

        return StoryDefinitionReport(
            level: level,
            missing: missing,
            warnings: warnings,
            nextQuestions: Array(questions.prefix(6))
        )
    }
}

enum ProjectStoryScope: String, Codable, Identifiable {
    case enabledMedia = "enabled_media"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        self = .enabledMedia
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var label: String {
        "Enabled media"
    }

    var shortDescription: String {
        "all media that has not been disabled"
    }
}

enum StoryWorkspaceStep: String, Codable, Hashable {
    case scope
    case audio
    case signals
    case directions
    case beats
    case sequence
    case scenes
}

struct StoryWorkspaceDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.story_workspace.v0.1"
    var projectId: String
    var selectedScope: ProjectStoryScope = .enabledMedia
    var selectedMediaIds: [String] = []
    var currentStep: StoryWorkspaceStep = .audio
    var status: String = "Generate Story Audio"
    var activeDirectionSetId: String?
    var activeDirectionId: String?
    var previewDirectionId: String?
    var activeBeatBoardId: String?
    var acceptedStoryId: String?
    var acceptedProjectStoryId: String?
    var activeSceneWorkspaceId: String?
    var activeVideoChainId: String?
    var updatedAt: String = DateFormats.now()

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case selectedScope = "selected_scope"
        case selectedMediaIds = "selected_media_ids"
        case currentStep = "current_step"
        case status
        case activeDirectionSetId = "active_direction_set_id"
        case activeDirectionId = "active_direction_id"
        case previewDirectionId = "preview_direction_id"
        case activeBeatBoardId = "active_beat_board_id"
        case acceptedStoryId = "accepted_story_id"
        case acceptedProjectStoryId = "accepted_project_story_id"
        case activeSceneWorkspaceId = "active_scene_workspace_id"
        case activeVideoChainId = "active_video_chain_id"
        case updatedAt = "updated_at"
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func empty(projectId: String = "") -> StoryWorkspaceDocument {
        StoryWorkspaceDocument(projectId: projectId)
    }

    static func decode(from data: Data) throws -> StoryWorkspaceDocument {
        var document = try decoder.decode(StoryWorkspaceDocument.self, from: data)
        if document.previewDirectionId == nil {
            document.previewDirectionId = document.activeDirectionId
        }
        if document.acceptedProjectStoryId == nil {
            document.acceptedProjectStoryId = document.acceptedStoryId
        }
        return document
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? Self.prettyEncoder : Self.encoder).encode(self)
    }
}

struct ProjectArchiveMeaningGraph: Codable, Hashable {
    var schemaVersion: String = "litscenes.project_archive_meaning.v0.1"
    var projectId: String
    var scope: ProjectStoryScope = .enabledMedia
    var summary: String = ""
    var motifs: [String] = []
    var tensions: [String] = []
    var moods: [String] = []
    var sceneForces: [String] = []
    var constraints: [String] = []
    var implications: [String] = []
    var evidenceMediaIds: [String] = []
    var confidence0To1: Double = 0
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case scope
        case summary
        case motifs
        case tensions
        case moods
        case sceneForces = "scene_forces"
        case constraints
        case implications
        case evidenceMediaIds = "evidence_media_ids"
        case confidence0To1 = "confidence_0_to_1"
        case generatedAt = "generated_at"
        case updatedAt = "updated_at"
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func empty(projectId: String = "") -> ProjectArchiveMeaningGraph {
        ProjectArchiveMeaningGraph(projectId: projectId)
    }

    static func decode(from data: Data) throws -> ProjectArchiveMeaningGraph {
        try decoder.decode(ProjectArchiveMeaningGraph.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? Self.prettyEncoder : Self.encoder).encode(self)
    }

    var hasSignals: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !motifs.isEmpty
            || !tensions.isEmpty
            || !moods.isEmpty
            || !sceneForces.isEmpty
            || !constraints.isEmpty
            || !implications.isEmpty
    }
}

enum StoryBeatSupportStatus: String, Codable, CaseIterable, Identifiable {
    case unsupported
    case weak
    case possible
    case strong

    var id: String { rawValue }

    var label: String {
        switch self {
        case .unsupported:
            return "Unsupported"
        case .weak:
            return "Weak"
        case .possible:
            return "Possible"
        case .strong:
            return "Strong"
        }
    }
}

struct StoryBeatCard: Codable, Identifiable, Hashable {
    var beatId: String
    var id: String { beatId }
    var order: Int
    var title: String
    var narrativeFunction: String
    var emotionalTurn: String
    var visualOpportunity: String
    var supportStatus: StoryBeatSupportStatus
    var meaningRefs: [String] = []
    var constraints: [String] = []

    enum CodingKeys: String, CodingKey {
        case beatId = "beat_id"
        case order
        case title
        case narrativeFunction = "narrative_function"
        case emotionalTurn = "emotional_turn"
        case visualOpportunity = "visual_opportunity"
        case supportStatus = "support_status"
        case meaningRefs = "meaning_refs"
        case constraints
    }
}

struct StoryBeatSheet: Codable, Hashable {
    var schemaVersion: String = "litscenes.story_beat_sheet.v0.1"
    var projectId: String
    var beatSheetId: String = "story_beat_sheet"
    var scope: ProjectStoryScope = .enabledMedia
    var title: String = ""
    var summary: String = ""
    var beats: [StoryBeatCard] = []
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case beatSheetId = "beat_sheet_id"
        case scope
        case title
        case summary
        case beats
        case generatedAt = "generated_at"
        case updatedAt = "updated_at"
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func empty(projectId: String = "") -> StoryBeatSheet {
        StoryBeatSheet(projectId: projectId)
    }

    static func decode(from data: Data) throws -> StoryBeatSheet {
        try decoder.decode(StoryBeatSheet.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? Self.prettyEncoder : Self.encoder).encode(self)
    }

    var hasBeats: Bool {
        !beats.isEmpty
    }
}

struct StoryAudioVoiceOption: Hashable, Identifiable {
    var id: String
    var name: String
    var descriptor: String
    var voiceId: String?

    var hasVoiceId: Bool {
        voiceId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

struct StoryAudioSpeedPreset: Hashable, Identifiable {
    var id: String
    var label: String
    var speed: Double
}

enum StoryAudioVoiceCatalog {
    static let customPresetId = "custom"
    /// Mapped to `customPresetId` on document load; never written back as-is.
    static let legacyCustomPresetId = "kevin"  // legacy persisted slug for the custom-voice preset
    static let archerPresetId = "archer"
    static let lucerPresetId = "lucer"
    static let defaultSpeed = 1.0
    static let speedRange: ClosedRange<Double> = 0.7...2.0
    static let providerSpeedRange: ClosedRange<Double> = 0.7...1.2

    static let speedPresets: [StoryAudioSpeedPreset] = [
        StoryAudioSpeedPreset(id: "slow_burn", label: "Slow Burn", speed: 0.82),
        StoryAudioSpeedPreset(id: "measured", label: "Measured", speed: 0.92),
        StoryAudioSpeedPreset(id: "natural", label: "Natural", speed: 1.0),
        StoryAudioSpeedPreset(id: "brisk", label: "Brisk", speed: 1.2),
        StoryAudioSpeedPreset(id: "double", label: "2x", speed: 2.0)
    ]

    /// Catalog presets plus any account voices (fetched from ElevenLabs);
    /// extras whose voiceId duplicates a preset are dropped.
    static func voiceOptions(customVoiceId: String?, extraVoices: [StoryAudioVoiceOption] = []) -> [StoryAudioVoiceOption] {
        let base = [
            StoryAudioVoiceOption(
                id: archerPresetId,
                name: "Archer",
                descriptor: "British male",
                voiceId: "L0Dsvb3SLTyegXwtm47J"
            ),
            StoryAudioVoiceOption(
                id: lucerPresetId,
                name: "Lucy",
                descriptor: "British female",
                voiceId: "lcMyyd2HUfFzxdCaC4Ta"
            ),
            StoryAudioVoiceOption(
                id: customPresetId,
                name: "My Voice",
                descriptor: "Manual local voice",
                voiceId: cleanedVoiceId(customVoiceId)
            )
        ]
        let knownVoiceIds = Set(base.compactMap { cleanedVoiceId($0.voiceId) })
        let extras = extraVoices.filter { option in
            guard let id = cleanedVoiceId(option.voiceId) else { return false }
            return !knownVoiceIds.contains(id)
        }
        return base + extras
    }

    /// Account voices use their raw voiceId as the preset id, so exact matches
    /// win first. THE RAW-ID PRESET LAW: a preset that isn't one of the three
    /// legacy slugs but is SHAPED like an ElevenLabs voice id resolves as that
    /// voice directly, whether or not the account list happens to be loaded —
    /// folding it to the custom preset made the narration voice depend on a lazily-warmed
    /// cache (observed: narration with the custom voice clone on a fresh launch
    /// because the Voices tab hadn't opened yet). Only true legacy junk still
    /// folds.
    static func option(for presetId: String?, customVoiceId: String?, extraVoices: [StoryAudioVoiceOption] = []) -> StoryAudioVoiceOption {
        let raw = presetId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty {
            let all = voiceOptions(customVoiceId: customVoiceId, extraVoices: extraVoices)
            if let exact = all.first(where: { $0.id == raw }) {
                return exact
            }
            let isLegacySlug = [archerPresetId, lucerPresetId, customPresetId, legacyCustomPresetId]
                .contains(raw.lowercased())
            let looksLikeVoiceId = raw.count >= 12
                && raw.allSatisfy { $0.isLetter || $0.isNumber }
            if !isLegacySlug, looksLikeVoiceId {
                return StoryAudioVoiceOption(
                    id: raw,
                    name: "Account voice",
                    descriptor: "Resolved by id",
                    voiceId: raw
                )
            }
        }
        let normalized = normalizedPresetId(presetId)
        return voiceOptions(customVoiceId: customVoiceId).first { $0.id == normalized }
            ?? voiceOptions(customVoiceId: customVoiceId)[0]
    }

    /// THE VOICE CURATION LAW: hiding a voice is DISPLAY-ONLY — it shortens
    /// the render-time menus and never changes what a saved narration
    /// resolves to. Two clauses keep it honest:
    /// 1. a menu always shows its OWN current value, even when hidden
    ///    (`keepingVoiceId`), so a shot narrated with a since-hidden voice
    ///    still reads correctly and can still re-render;
    /// 2. hiding everything leaves the full list rather than an empty menu.
    /// Resolution paths (`option(for:)`, `startShotNarration`) read the
    /// unfiltered list and must keep doing so.
    static func visibleOptions(
        _ options: [StoryAudioVoiceOption],
        hiddenVoiceIds: Set<String>,
        keepingVoiceId keptVoiceId: String? = nil
    ) -> [StoryAudioVoiceOption] {
        guard !hiddenVoiceIds.isEmpty else { return options }
        let kept = cleanedVoiceId(keptVoiceId)
        let visible = options.filter { option in
            guard let id = cleanedVoiceId(option.voiceId) else { return true }
            if let kept, id == kept { return true }
            return !hiddenVoiceIds.contains(id)
        }
        return visible.isEmpty ? options : visible
    }

    /// ElevenLabs' stock catalog voices — the 20-odd `premade` entries every
    /// account carries. The Voices tab's one-click bulk hide targets these.
    static func stockVoiceIds(in options: [StoryAudioVoiceOption]) -> Set<String> {
        Set(options.compactMap { option in
            guard option.descriptor.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "premade",
                  let id = cleanedVoiceId(option.voiceId) else { return nil }
            return id
        })
    }

    static func defaultOption(customVoiceId: String?, extraVoices: [StoryAudioVoiceOption] = []) -> StoryAudioVoiceOption {
        // A default chosen in the Voices tab wins; fall back to the custom voice, then Archer.
        if let stored = ElevenLabsSettingsStore.resolvedDefaultNarrationVoice(),
           !stored.voiceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let all = voiceOptions(customVoiceId: customVoiceId, extraVoices: extraVoices)
            if let match = all.first(where: { $0.voiceId == stored.voiceId || $0.id == stored.voiceId }) {
                return match
            }
            return StoryAudioVoiceOption(
                id: stored.voiceId,
                name: stored.name.isEmpty ? "Default voice" : stored.name,
                descriptor: "Account voice",
                voiceId: stored.voiceId
            )
        }
        if cleanedVoiceId(customVoiceId) != nil {
            return option(for: customPresetId, customVoiceId: customVoiceId)
        }
        return option(for: archerPresetId, customVoiceId: customVoiceId)
    }

    static func clampedSpeed(_ speed: Double?) -> Double {
        let value = speed ?? defaultSpeed
        return min(max(value, speedRange.lowerBound), speedRange.upperBound)
    }

    static func clampedProviderSpeed(_ speed: Double?) -> Double {
        let value = speed ?? defaultSpeed
        return min(max(value, providerSpeedRange.lowerBound), providerSpeedRange.upperBound)
    }

    static func speedLabel(for speed: Double?) -> String {
        let value = clampedSpeed(speed)
        let closest = speedPresets.min { lhs, rhs in
            abs(lhs.speed - value) < abs(rhs.speed - value)
        }
        if let closest, abs(closest.speed - value) <= 0.025 {
            return closest.label
        }
        return String(format: "%.2fx", value)
    }

    private static func normalizedPresetId(_ presetId: String?) -> String {
        let lowered = presetId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch lowered {
        case archerPresetId, lucerPresetId, customPresetId:
            return lowered
        case legacyCustomPresetId:
            return customPresetId
        default:
            return customPresetId
        }
    }

    /// Load-time upgrade for persisted preset ids: the legacy custom slug
    /// becomes the neutral one; everything else passes through untouched.
    static func migratedPresetId(_ presetId: String?) -> String? {
        guard let presetId, presetId.lowercased() == legacyCustomPresetId else { return presetId }
        return customPresetId
    }

    private static func cleanedVoiceId(_ voiceId: String?) -> String? {
        guard let cleaned = voiceId?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else {
            return nil
        }
        return cleaned
    }
}

struct StoryAudioTrackDraft: Codable, Hashable {
    var schemaVersion: String = "litscenes.story_audio_track_draft.v0.1"
    var projectId: String
    var trackId: String = "story_audio_track"
    var title: String = ""
    var voiceText: String = ""
    var beatPrompt: String = ""
    var mixNotes: String = ""
    var tags: [String] = []
    var targetBeatId: String?
    var sourceBeatIds: [String]?
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case trackId = "track_id"
        case title
        case voiceText = "voice_text"
        case beatPrompt = "beat_prompt"
        case mixNotes = "mix_notes"
        case tags
        case targetBeatId = "target_beat_id"
        case sourceBeatIds = "source_beat_ids"
        case generatedAt = "generated_at"
        case updatedAt = "updated_at"
    }

    static let decoder = JSONDecoder()

    static func decode(from data: Data) throws -> StoryAudioTrackDraft {
        try decoder.decode(StoryAudioTrackDraft.self, from: data)
    }
}

struct StoryAudioTimelineItem: Codable, Hashable, Identifiable {
    var kind: String
    var startSeconds: Double
    var durationSeconds: Double
    var volume: Double
    var id: String { kind }

    enum CodingKeys: String, CodingKey {
        case kind
        case startSeconds = "start_seconds"
        case durationSeconds = "duration_seconds"
        case volume
    }
}

struct StoryAudioAsset: Codable, Hashable {
    var kind: String
    var path: String
    var relativePath: String
    var sha256: String
    var bytes: Int
    var contentType: String
    var provider: String
    var modelId: String
    var outputFormat: String
    var requestId: String = ""
    var characterCost: String = ""
    var characterCount: String = ""
    var generatedAt: String = DateFormats.now()

    enum CodingKeys: String, CodingKey {
        case kind
        case path
        case relativePath = "relative_path"
        case sha256
        case bytes
        case contentType = "content_type"
        case provider
        case modelId = "model_id"
        case outputFormat = "output_format"
        case requestId = "request_id"
        case characterCost = "character_cost"
        case characterCount = "character_count"
        case generatedAt = "generated_at"
    }
}

struct StoryAudioTrackDocument: Codable, Hashable, Identifiable {
    var schemaVersion: String = "litscenes.story_audio_track.v0.1"
    var projectId: String
    var trackId: String = "story_audio_track"
    var id: String { trackId }
    var title: String = ""
    var durationSeconds: Double = 7
    var voiceStartSeconds: Double = 0.65
    var voiceText: String = ""
    var beatPrompt: String = ""
    var mixNotes: String = ""
    var tags: [String] = []
    var targetBeatId: String?
    var sourceBeatIds: [String]?
    var sourceProjectStoryId: String?
    var sourceBeatBoardId: String?
    var sourceBoardFingerprint: String?
    var scope: String?
    var operatorDirection: String?
    var draftProvider: String?
    var draftModelId: String?
    var draftResponseId: String?
    var provider: String = "elevenlabs"
    var voiceProvider: String = "elevenlabs_tts"
    var beatProvider: String = "elevenlabs_sound_effects"
    var voicePresetId: String?
    var voiceName: String?
    var voiceDescription: String?
    var voiceId: String?
    var voiceModelId: String = ElevenLabsSpeechModels.defaultModelId
    var beatModelId: String = "eleven_text_to_sound_v2"
    var voiceSpeed: Double?
    var generatedVoiceSpeed: Double?
    var isBeatEnabled: Bool?
    var outputFormat: String = "mp3_44100_128"
    var promptInfluence: Double = 0.3
    var loop: Bool = true
    var timeline: [StoryAudioTimelineItem] = []
    var voiceAsset: StoryAudioAsset?
    var beatAsset: StoryAudioAsset?
    var mixAsset: StoryAudioAsset?
    var status: String = "empty"
    var errorMessage: String = ""
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case trackId = "track_id"
        case title
        case durationSeconds = "duration_seconds"
        case voiceStartSeconds = "voice_start_seconds"
        case voiceText = "voice_text"
        case beatPrompt = "beat_prompt"
        case mixNotes = "mix_notes"
        case tags
        case targetBeatId = "target_beat_id"
        case sourceBeatIds = "source_beat_ids"
        case sourceProjectStoryId = "source_project_story_id"
        case sourceBeatBoardId = "source_beat_board_id"
        case sourceBoardFingerprint = "source_board_fingerprint"
        case scope
        case operatorDirection = "operator_direction"
        case draftProvider = "draft_provider"
        case draftModelId = "draft_model_id"
        case draftResponseId = "draft_response_id"
        case provider
        case voiceProvider = "voice_provider"
        case beatProvider = "beat_provider"
        case voicePresetId = "voice_preset_id"
        case voiceName = "voice_name"
        case voiceDescription = "voice_description"
        case voiceId = "voice_id"
        case voiceModelId = "voice_model_id"
        case beatModelId = "beat_model_id"
        case voiceSpeed = "voice_speed"
        case generatedVoiceSpeed = "generated_voice_speed"
        case isBeatEnabled = "is_beat_enabled"
        case outputFormat = "output_format"
        case promptInfluence = "prompt_influence"
        case loop
        case timeline
        case voiceAsset = "voice_asset"
        case beatAsset = "beat_asset"
        case mixAsset = "mix_asset"
        case status
        case errorMessage = "error_message"
        case generatedAt = "generated_at"
        case updatedAt = "updated_at"
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func empty(projectId: String = "") -> StoryAudioTrackDocument {
        StoryAudioTrackDocument(projectId: projectId)
    }

    static func document(
        from draft: StoryAudioTrackDraft,
        durationSeconds: Double = 7,
        operatorDirection: String = ""
    ) -> StoryAudioTrackDocument {
        let voiceStartSeconds = 0.65
        let trimmedDirection = operatorDirection.trimmingCharacters(in: .whitespacesAndNewlines)
        return StoryAudioTrackDocument(
            projectId: draft.projectId,
            trackId: draft.trackId,
            title: draft.title,
            durationSeconds: durationSeconds,
            voiceStartSeconds: voiceStartSeconds,
            voiceText: draft.voiceText,
            beatPrompt: draft.beatPrompt,
            mixNotes: draft.mixNotes,
            tags: draft.tags,
            targetBeatId: draft.targetBeatId,
            sourceBeatIds: draft.sourceBeatIds,
            scope: draft.sourceBeatIds?.isEmpty == false ? "beat_aware_audio" : "global_project_audio",
            operatorDirection: trimmedDirection.isEmpty ? nil : trimmedDirection,
            voiceSpeed: StoryAudioVoiceCatalog.defaultSpeed,
            timeline: [
                StoryAudioTimelineItem(kind: "beat", startSeconds: 0, durationSeconds: durationSeconds, volume: 0.55),
                StoryAudioTimelineItem(kind: "voice", startSeconds: voiceStartSeconds, durationSeconds: max(durationSeconds - voiceStartSeconds, 0), volume: 1.0)
            ],
            status: "drafted",
            generatedAt: draft.generatedAt,
            updatedAt: draft.updatedAt
        )
    }

    static func decode(from data: Data) throws -> StoryAudioTrackDocument {
        try decoder.decode(StoryAudioTrackDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? Self.prettyEncoder : Self.encoder).encode(self)
    }

    var hasMix: Bool {
        guard status == "ready", let path = mixAsset?.path else { return false }
        return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasVoiceAssetReference: Bool {
        guard let path = voiceAsset?.path else { return false }
        return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasBeatAssetReference: Bool {
        guard let path = beatAsset?.path else { return false }
        return !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canBuildLocalMix: Bool {
        hasVoiceAssetReference && hasBeatAssetReference
    }

    var effectiveBeatEnabled: Bool {
        isBeatEnabled ?? true
    }

    var effectiveBeatVolume: Double {
        effectiveBeatEnabled ? (timeline.first(where: { $0.kind == "beat" })?.volume ?? 0.55) : 0
    }

    var isEditableDraft: Bool {
        status == "drafted" || status == "failed"
    }

    var effectiveVoiceSpeed: Double {
        StoryAudioVoiceCatalog.clampedSpeed(voiceSpeed)
    }

    var effectiveGeneratedVoiceSpeed: Double {
        StoryAudioVoiceCatalog.clampedSpeed(generatedVoiceSpeed ?? voiceSpeed)
    }

    var localVoiceSpeedRatio: Double {
        let generated = max(effectiveGeneratedVoiceSpeed, 0.01)
        return effectiveVoiceSpeed / generated
    }

    var voiceDisplayName: String {
        if let voiceName = voiceName?.trimmingCharacters(in: .whitespacesAndNewlines), !voiceName.isEmpty {
            if voiceName == "Lucer" {
                return "Lucy"
            }
            return voiceName
        }
        return StoryAudioVoiceCatalog.option(for: voicePresetId, customVoiceId: nil).name
    }

    var voiceSpeedDisplayLabel: String {
        StoryAudioVoiceCatalog.speedLabel(for: voiceSpeed)
    }
}

struct StoryAudioTrackCollectionDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.story_audio_tracks.v0.1"
    var projectId: String
    var operatorDirection: String?
    var activeTrackId: String = ""
    var tracks: [StoryAudioTrackDocument] = []
    var updatedAt: String = DateFormats.now()

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case operatorDirection = "operator_direction"
        case activeTrackId = "active_track_id"
        case tracks
        case updatedAt = "updated_at"
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let prettyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func empty(projectId: String = "") -> StoryAudioTrackCollectionDocument {
        StoryAudioTrackCollectionDocument(projectId: projectId)
    }

    static func fromLegacyTrack(_ track: StoryAudioTrackDocument, projectId: String) -> StoryAudioTrackCollectionDocument {
        let hasLegacyContent = track.status != "empty"
            || track.hasMix
            || !track.voiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !track.beatPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasLegacyContent else {
            return .empty(projectId: projectId)
        }
        var migratedTrack = track
        if migratedTrack.projectId.isEmpty {
            migratedTrack.projectId = projectId
        }
        if migratedTrack.trackId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            migratedTrack.trackId = "story_audio_track_legacy"
        }
        return StoryAudioTrackCollectionDocument(
            projectId: projectId,
            activeTrackId: migratedTrack.trackId,
            tracks: [migratedTrack],
            updatedAt: DateFormats.now()
        )
    }

    static func decode(from data: Data) throws -> StoryAudioTrackCollectionDocument {
        try decoder.decode(StoryAudioTrackCollectionDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? Self.prettyEncoder : Self.encoder).encode(self)
    }

    var activeTrack: StoryAudioTrackDocument {
        if let active = tracks.first(where: { $0.trackId == activeTrackId }) {
            return active
        }
        return tracks.sortedByStoryAudioRecency.first ?? .empty(projectId: projectId)
    }

    var hasTracks: Bool {
        !tracks.isEmpty
    }

    func appending(_ track: StoryAudioTrackDocument, activate: Bool = true) -> StoryAudioTrackCollectionDocument {
        var updated = self
        var normalized = track
        if normalized.projectId.isEmpty {
            normalized.projectId = projectId
        }
        updated.tracks.removeAll { $0.trackId == normalized.trackId }
        updated.tracks.append(normalized)
        if activate {
            updated.activeTrackId = normalized.trackId
        } else if updated.activeTrackId.isEmpty {
            updated.activeTrackId = normalized.trackId
        }
        updated.tracks = updated.tracks.sortedByStoryAudioRecency
        updated.updatedAt = DateFormats.now()
        return updated
    }

    func activating(trackId: String) -> StoryAudioTrackCollectionDocument {
        guard tracks.contains(where: { $0.trackId == trackId }) else { return self }
        var updated = self
        updated.activeTrackId = trackId
        updated.updatedAt = DateFormats.now()
        return updated
    }
}

extension Array where Element == StoryAudioTrackDocument {
    var sortedByStoryAudioRecency: [StoryAudioTrackDocument] {
        sorted { lhs, rhs in
            let left = lhs.generatedAt.isEmpty ? lhs.updatedAt : lhs.generatedAt
            let right = rhs.generatedAt.isEmpty ? rhs.updatedAt : rhs.generatedAt
            if left == right {
                return lhs.trackId > rhs.trackId
            }
            return left > right
        }
    }
}

enum SourceContextKind: String, Codable, CaseIterable, Identifiable {
    case folder
    case document
    case note

    var id: String { rawValue }

    var label: String {
        switch self {
        case .folder:
            return "Folder"
        case .document:
            return "Document"
        case .note:
            return "Note"
        }
    }

    var systemImage: String {
        switch self {
        case .folder:
            return "folder"
        case .document:
            return "doc.text"
        case .note:
            return "note.text"
        }
    }
}

struct SourceContextRecord: Codable, Identifiable, Hashable {
    var sourceId: String
    var id: String { sourceId }
    var kind: SourceContextKind
    var title: String
    var path: String = ""
    var bookmarkDataBase64: String = ""
    var notes: String = ""
    var addedAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()
}

struct SourceContextDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.desktop.source_context.v0.1"
    var projectId: String
    var records: [SourceContextRecord] = []
}

struct SessionConfig: Codable, Hashable {
    var captureIntervalSeconds: Double = 2
    var bufferDelaySeconds: Double = 5
    var heartbeatSeconds: Double = 30
    var model: String = "gpt-5.5"
    var detail: ImageDetail = .original
    var concurrencyLimit: Int = 1
    var excludeOwnWindows: Bool = true
}

struct SessionTotals: Codable, Hashable {
    var captured: Int = 0
    var skipped: Int = 0
    var queued: Int = 0
    var analyzing: Int = 0
    var hydrated: Int = 0
    var erased: Int = 0
    var failed: Int = 0
    var estimatedCostUsd: Double = 0
    var actualCostUsd: Double = 0
}

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case image
    case video
    /// Audio files the user brings in (music, stems, field recordings). Added
    /// with the audio-kind migration — before that, audio could only reach a project by being
    /// synthesized (narration TTS, microphone takes, ambient beds), so an mp3
    /// on disk had no way in. Audio items carry a duration but no thumbnail and
    /// no dimensions; anything that renders a media item must tolerate an empty
    /// `thumbnailPath`, and vision analysis skips them.
    case audio

    var id: String { rawValue }

    var isVisual: Bool { self != .audio }
}

enum MediaSourceKind: String, Codable, Hashable, Sendable {
    case folder
    case file
}

/// Whether LitScenes owns a durable project-local file or only references a
/// file at an operator-controlled location. `missing` is deliberately not
/// persisted: it is live filesystem state derived from the active path.
enum MediaStorageMode: String, Codable, Hashable, Sendable {
    case managed
    case linked
}

enum MediaStorageStatus: String, Hashable, Sendable {
    case managed
    case linked
    case missing

    var label: String { rawValue.capitalized }
}

struct MediaSourceRecord: Codable, Identifiable, Hashable, Sendable {
    var sourceId: String
    var id: String { sourceId }
    var displayName: String
    var path: String
    var sourceKind: MediaSourceKind? = nil
    var bookmarkDataBase64: String
    var storageMode: MediaStorageMode? = nil
    /// The operator-selected location, retained for provenance after the
    /// active `path` moves into project-owned storage.
    var originalPath: String? = nil
    var originalBookmarkDataBase64: String? = nil
    var addedAt: String
    var lastScannedAt: String?
}

extension MediaSourceRecord {
    var resolvedSourceKind: MediaSourceKind {
        sourceKind ?? .folder
    }

    var resolvedStorageMode: MediaStorageMode {
        storageMode ?? .linked
    }

    var resolvedOriginalPath: String {
        originalPath?.trimmed.nilIfEmpty ?? path
    }
}

struct MediaItemRecord: Codable, Identifiable, Hashable {
    var mediaId: String
    var id: String { mediaId }
    var sourceId: String
    var kind: MediaKind
    var filename: String
    var path: String
    var relativePath: String
    var byteCount: Int64
    var modifiedAt: String
    var width: Int
    var height: Int
    var durationSeconds: Double?
    var nominalFrameRate: Double?
    var thumbnailPath: String
    var videoStripPath: String?
    var scannedAt: String
    var scanError: String?
    var derivativeKind: String? = nil
    var sourceMediaId: String? = nil
    var sourceTimestampSeconds: Double? = nil
    var frameIndex: Int? = nil
    /// sha256 of the ORIGINAL file bytes — the identity that survives a copy, a
    /// rename, or a second import. Empty for legacy rows and plain folder scans;
    /// stamped for derived and copied items, and backfilled when a duplicate check
    /// hashes a candidate.
    var contentSha256: String = ""
}

/// Tolerant decode lives in an extension so the synthesized memberwise init (and
/// every call site leaning on its implicit nil defaults) survives untouched. Legacy
/// inventories that predate `content_sha256` must decode — the legacy import path
/// swallows a throw into an EMPTY inventory.
extension MediaItemRecord {
    enum CodingKeys: String, CodingKey {
        case mediaId
        case sourceId
        case kind
        case filename
        case path
        case relativePath
        case byteCount
        case modifiedAt
        case width
        case height
        case durationSeconds
        case nominalFrameRate
        case thumbnailPath
        case videoStripPath
        case scannedAt
        case scanError
        case derivativeKind
        case sourceMediaId
        case sourceTimestampSeconds
        case frameIndex
        case contentSha256
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            mediaId: try container.decodeIfPresent(String.self, forKey: .mediaId) ?? "",
            sourceId: try container.decodeIfPresent(String.self, forKey: .sourceId) ?? "",
            kind: try container.decodeIfPresent(MediaKind.self, forKey: .kind) ?? .image,
            filename: try container.decodeIfPresent(String.self, forKey: .filename) ?? "",
            path: try container.decodeIfPresent(String.self, forKey: .path) ?? "",
            relativePath: try container.decodeIfPresent(String.self, forKey: .relativePath) ?? "",
            byteCount: try container.decodeIfPresent(Int64.self, forKey: .byteCount) ?? 0,
            modifiedAt: try container.decodeIfPresent(String.self, forKey: .modifiedAt) ?? "",
            width: try container.decodeIfPresent(Int.self, forKey: .width) ?? 0,
            height: try container.decodeIfPresent(Int.self, forKey: .height) ?? 0,
            durationSeconds: try container.decodeIfPresent(Double.self, forKey: .durationSeconds),
            nominalFrameRate: try container.decodeIfPresent(Double.self, forKey: .nominalFrameRate),
            thumbnailPath: try container.decodeIfPresent(String.self, forKey: .thumbnailPath) ?? "",
            videoStripPath: try container.decodeIfPresent(String.self, forKey: .videoStripPath),
            scannedAt: try container.decodeIfPresent(String.self, forKey: .scannedAt) ?? "",
            scanError: try container.decodeIfPresent(String.self, forKey: .scanError),
            derivativeKind: try container.decodeIfPresent(String.self, forKey: .derivativeKind),
            sourceMediaId: try container.decodeIfPresent(String.self, forKey: .sourceMediaId),
            sourceTimestampSeconds: try container.decodeIfPresent(Double.self, forKey: .sourceTimestampSeconds),
            frameIndex: try container.decodeIfPresent(Int.self, forKey: .frameIndex),
            contentSha256: try container.decodeIfPresent(String.self, forKey: .contentSha256) ?? ""
        )
    }
}

extension MediaItemRecord {
    static let videoFrameDerivativeKind = "video_frame"
    /// A playhead still the user deliberately collected from the shot player.
    /// Unlike `video_frame` — an automatic extraction that belongs to its source
    /// clip in the Sources tray — this one is a creative act with no footage
    /// parent, so it lists in Creations with the rest of the project's output.
    static let collectedShotFrameDerivativeKind = "collected_shot_frame"
    static let videoTrimDerivativeKind = "video_trim"
    static let videoChainKeyframeDerivativeKind = "video_chain_keyframe"
    static let videoChainHandoffFrameDerivativeKind = "video_chain_handoff_frame"
    static let videoChainClipDerivativeKind = "video_chain_clip"
    static let videoChainReelDerivativeKind = "video_chain_reel"
    static let chatAttachmentDerivativeKind = "chat_attachment"
    static let frameReferenceDerivativeKind = "frame_reference"
    static let rosterCompositeSheetDerivativeKind = "roster_composite_sheet"
    static let rosterCharacterRenderDerivativeKind = "roster_character_render"
    /// A generated character reference sheet (turnaround, face, expressions, poses,
    /// costume, palette) — the identity anchor for every render of that character.
    static let characterSheetDerivativeKind = "character_sheet"
    /// A photo or artwork copied into the project as a character's source image —
    /// project-owned bytes, identified by content hash, an input the sheet is
    /// built from.
    static let characterSourceDerivativeKind = "character_source"
    static let shotLookDerivativeKind = "shot_look"
    static let clipLookDerivativeKind = "clip_look"
    static let shotExportDerivativeKind = "shot_export"
    /// A prompt-driven restyle of one Media image, generated from the media
    /// viewer — lens-free, lands beside its source in the Library.
    static let mediaRestyleDerivativeKind = "media_restyle"
    /// A video rendered FROM one Media image (image-to-video), generated from
    /// the media viewer — no shot, no lens; a top-level tray asset.
    static let mediaMotionDerivativeKind = "media_motion"
    /// One of the project's defining sheets (Cover/Style/Cast/Frames): 16:9
    /// composites that capture the project so far, share-ready, paired with a
    /// JSON re-composition manifest beside them on disk.
    static let projectSheetDerivativeKind = "project_sheet"
    /// A revision of the project's grown terrain map canvas; chained by
    /// sourceMediaId (each grow's source is the previous canvas).
    static let terrainMapDerivativeKind = "terrain_map"
    /// A place's region crop of the terrain map, auto-refreshed after growth
    /// and pin edits; rides the place's reference media into generation.
    static let terrainMapRegionDerivativeKind = "terrain_map_region"
    static let generatedMediaSourceId = "source_generated_media"

    var isExtractedVideoFrame: Bool {
        derivativeKind == Self.videoFrameDerivativeKind && sourceMediaId != nil
    }

    /// A user-cut range of a source video, saved as a NEW source-like asset.
    /// Like `video_frame` it stays OUT of `isGeneratedMedia`: rescans preserve
    /// it via its own clause in the scan preservation filter.
    var isVideoTrim: Bool {
        derivativeKind == Self.videoTrimDerivativeKind && sourceMediaId != nil
    }

    var isPortrait: Bool {
        height > width
    }

    /// A Lucy restyle of one placed-footage range, archived as a derived tray
    /// asset nested under its source clip. Unlike video_trim it IS generated
    /// media: rescans preserve it via the isGeneratedMedia clause.
    var isClipLookMedia: Bool {
        derivativeKind == Self.clipLookDerivativeKind && sourceMediaId != nil
    }

    var isGeneratedMedia: Bool {
        [
            Self.videoChainKeyframeDerivativeKind,
            Self.videoChainHandoffFrameDerivativeKind,
            Self.videoChainClipDerivativeKind,
            Self.videoChainReelDerivativeKind,
            Self.chatAttachmentDerivativeKind,
            Self.frameReferenceDerivativeKind,
            Self.rosterCompositeSheetDerivativeKind,
            Self.rosterCharacterRenderDerivativeKind,
            Self.characterSheetDerivativeKind,
            Self.characterSourceDerivativeKind,
            Self.shotLookDerivativeKind,
            Self.clipLookDerivativeKind,
            Self.shotExportDerivativeKind,
            Self.mediaRestyleDerivativeKind,
            Self.mediaMotionDerivativeKind,
            Self.projectSheetDerivativeKind,
            Self.terrainMapDerivativeKind,
            Self.terrainMapRegionDerivativeKind,
            // Load-bearing: collected frames have no footage parent, so this is
            // the only clause in the scan preservation filter that keeps them.
            // Drop it and a rescan deletes every frame the user ever collected.
            Self.collectedShotFrameDerivativeKind
        ].contains(derivativeKind ?? "")
    }

    /// A playhead still collected from the shot player.
    var isCollectedShotFrame: Bool {
        derivativeKind == Self.collectedShotFrameDerivativeKind
    }

    /// A terrain map canvas revision.
    var isTerrainMapCanvas: Bool {
        derivativeKind == Self.terrainMapDerivativeKind
    }

    /// A place's terrain-map region crop.
    var isTerrainMapRegion: Bool {
        derivativeKind == Self.terrainMapRegionDerivativeKind
    }

    /// A project defining sheet (Cover/Style/Cast/Frames composite).
    var isProjectSheet: Bool {
        derivativeKind == Self.projectSheetDerivativeKind
    }

    /// A roster reference sheet: several of a character/object's references composed
    /// into one labeled image, so one attachment slot can carry multiple views.
    var isRosterCompositeSheet: Bool {
        derivativeKind == Self.rosterCompositeSheetDerivativeKind
    }

    /// A generated character reference sheet.
    var isCharacterSheet: Bool {
        derivativeKind == Self.characterSheetDerivativeKind
    }

    /// A character source image copied into the project.
    var isCharacterSource: Bool {
        derivativeKind == Self.characterSourceDerivativeKind
    }

    var canBeEnabledContent: Bool {
        kind == .image
    }
}

struct MediaCurationRecord: Codable, Hashable {
    var mediaId: String
    var rejected: Bool = false
    var tags: [String] = []
    var notes: String = ""
    var updatedAt: String = DateFormats.now()
}

struct VideoFrameExtractionState: Hashable {
    var isExtracting: Bool = false
    var completedCount: Int = 0
    var totalCount: Int = 0
    var status: String = ""
    var errorMessage: String = ""

    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return min(max(Double(completedCount) / Double(totalCount), 0), 1)
    }
}

struct MediaInventoryDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.desktop.media_inventory.v0.1"
    var projectId: String
    var scannedAt: String
    var items: [MediaItemRecord]
}

struct MediaSourceDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.desktop.media_sources.v0.1"
    var projectId: String
    var sources: [MediaSourceRecord]
}

struct MediaCurationDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.desktop.curation.v0.2"
    var projectId: String
    var records: [MediaCurationRecord]
}

struct LibraryStats: Hashable {
    var sourceCount: Int = 0
    var imageCount: Int = 0
    var videoCount: Int = 0
    var rejectedCount: Int = 0
    var screenSessionCount: Int = 0
    var hydratedRecordCount: Int = 0
}
