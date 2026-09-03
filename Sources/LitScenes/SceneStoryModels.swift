import Foundation

struct SceneStoryGenerateRequest: Codable, Hashable, Sendable {
    var projectId: String
    var goalFingerprint: String
    var lensId: String
    var lensContextFingerprint: String
    var generationSessionId: String = ""
    var generationBatchId: String = ""
    var batchSlot: Int = 0
    var batchSize: Int = 0
    var lensRefs: [StoryGenerationLensReference] = []
    var generationOrigin: StoryGenerationOrigin = .manual
    var goal: ProjectGoalBriefV2
    var goalCast: [SceneStoryGoalCastMemberSnapshot] = []
    var lens: SceneStoryLensSnapshot
    var lensContext: LensContextResolveResponse
    var mediaAnchors: [SceneStoryMediaAnchor] = []
    var outputProfile: SceneStoryOutputProfile = .default
    var storyCount: Int = SceneStoryGenerationSizing.initialStoryCount
    var scenesPerStory: Int = SceneStoryGenerationSizing.initialScenesPerStory
    var beatsPerScene: Int = SceneStoryGenerationSizing.initialBeatsPerScene
    var generationMode: StoryGenerationMode = .avoidOverlap
    var requestedStartingDepth: StoryStartingDepth = .fourSceneArc
    var differenceMode: StoryDifferenceMode = .distinct
    var groundingMode: StoryGroundingMode = .balanced
    var storyMemory: StoryMemoryRequest = .empty
    var generationIntent: StoryGenerationIntent = StoryGenerationIntent()
    var storyGenerationBrief: SceneStoryGenerationBrief = SceneStoryGenerationBrief()
    var toneConstraints: [String] = []
    var operatorInstructions: [String] = []
}

enum StoryGenerationOrigin: String, Codable, Hashable, Sendable {
    case manual
    case goalConversationAutomatic = "goal_conversation_automatic"
}

/// The active GOAL-stage identity that Story generation can actually consume. This is
/// a value snapshot: later cast steers remain non-destructive and do not rewrite the
/// provenance of an already generated Story.
struct SceneStoryGoalCastMemberSnapshot: Codable, Hashable, Sendable {
    var memberId: String = ""
    var characterId: String = ""
    var name: String = ""
    var roleLabel: String = ""
    var activeTakeId: String = ""
    var activeTakeOrigin: String = ""
    var identity: GoalCastIdentity = GoalCastIdentity()

    static func from(member: GoalCastMember) -> SceneStoryGoalCastMemberSnapshot {
        SceneStoryGoalCastMemberSnapshot(
            memberId: member.memberId,
            characterId: member.characterId,
            name: member.name,
            roleLabel: member.roleLabel,
            activeTakeId: member.activeTakeId,
            activeTakeOrigin: member.activeTake?.origin ?? "",
            identity: member.activeIdentity.normalized()
        )
    }
}

enum SceneStoryGenerationSizing {
    static let defaultStoryBatchCount = 3
    static let initialStoryCount = 1
    static let initialScenesPerStory = 4
    static let initialBeatsPerScene = 1
}

func storyUUIDIdentifier(_ prefix: String) -> String {
    "\(prefix)_\(UUID().uuidString.lowercased())"
}

enum StoryGenerationMode: String, Codable, Hashable, Sendable, CaseIterable {
    case avoidOverlap = "avoid_overlap"
    case moreLikeSelected = "more_like_selected"
    case branchSelected = "branch_selected"
    case reflowSelected = "reflow_selected"
    case ignoreHistory = "ignore_history"
}

enum StoryDifferenceMode: String, Codable, Hashable, Sendable, CaseIterable {
    case related
    case distinct
    case farApart = "far_apart"
}

enum StoryGroundingMode: String, Codable, Hashable, Sendable, CaseIterable {
    case mediaBound = "media_bound"
    case balanced
    case inventive
}

enum StoryForm: String, Codable, Hashable, Sendable, CaseIterable {
    case dramaticArc = "dramatic_arc"
    case documentaryPortrait = "documentary_portrait"
    case processExplainer = "process_explainer"
    case productDemo = "product_demo"
    case lyricalMontage = "lyrical_montage"
    case ambientSequence = "ambient_sequence"
    case abstractVisualPoem = "abstract_visual_poem"
    case testimonialInterview = "testimonial_interview"
    case instructionalSequence = "instructional_sequence"
}

enum StoryStartingDepth: String, Codable, Hashable, Sendable, CaseIterable {
    case sketch
    case fourSceneArc = "four_scene_arc"
    case treatment

    var scenesPerStory: Int {
        switch self {
        case .sketch: return 1
        case .fourSceneArc: return 4
        case .treatment: return 6
        }
    }
}

enum StoryGenerationResultSlotStatus: String, Codable, Hashable, Sendable {
    case queued
    case generating
    case complete
    case failed
    case cancelled
}

enum ProjectStoryEditorialState: String, Codable, Hashable, Sendable {
    case suggestion
    case kept
    case dismissed
    case archived
}

enum ProjectStoryProductionState: String, Codable, Hashable, Sendable {
    case notStarted = "not_started"
    case developing
    case inProduction = "in_production"
    case complete
}

enum StoryMemoryContextClass: String, Codable, Hashable, Sendable {
    case currentContext = "current_context"
    case olderContext = "older_context"
    case dismissed
    case archived
    case sameSession = "same_session"
    case positiveReference = "positive_reference"
}

enum StoryArchitectureFamily: String, Codable, Hashable, Sendable, CaseIterable {
    case embodiedChoice = "embodied_choice"
    case systemReconfiguration = "system_reconfiguration"
    case symbolicInversion = "symbolic_inversion"
    case investigationRevelation = "investigation_revelation"
    case obstacleCountermove = "obstacle_countermove"
    case ritualDecision = "ritual_decision"
    case unspecified
}

enum CompassLockScope: String, Codable, Hashable, Sendable {
    case storyStart = "story_start"
    case storyEnd = "story_end"
    case sceneEntry = "scene_entry"
    case sceneExit = "scene_exit"
    case beatEntry = "beat_entry"
    case beatExit = "beat_exit"
}

enum CompassLabelKind: String, Codable, Hashable, Sendable {
    case feeling
    case agencyPosture = "agency_posture"
    case activationPosture = "activation_posture"
    case image
    case label
}

struct CompassCoordinateRange: Codable, Hashable, Sendable {
    var min: Double?
    var max: Double?

    func normalized() -> CompassCoordinateRange {
        CompassCoordinateRange(
            min: min.map { Swift.max(-1, Swift.min(1, $0)) },
            max: max.map { Swift.max(-1, Swift.min(1, $0)) }
        )
    }
}

struct CompassLock: Codable, Hashable, Sendable {
    var scope: CompassLockScope = .storyEnd
    var kind: CompassLabelKind = .label
    var text: String = ""
    var valence: CompassCoordinateRange?
    var activation: CompassCoordinateRange?
    var agency: CompassCoordinateRange?

    func normalized() -> CompassLock {
        var value = self
        value.text = value.text.trimmed
        value.valence = value.valence?.normalized()
        value.activation = value.activation?.normalized()
        value.agency = value.agency?.normalized()
        return value
    }
}

struct StoryStructureAvoidance: Codable, Hashable, Sendable {
    var dimension: String = ""
    var value: String = ""

    func normalized() -> StoryStructureAvoidance {
        StoryStructureAvoidance(dimension: dimension.trimmed, value: value.trimmed)
    }
}

struct BeatGenerationContract: Codable, Hashable, Sendable {
    var maxMajorStateChanges: Int = 2

    func normalized() -> BeatGenerationContract {
        BeatGenerationContract(maxMajorStateChanges: Swift.max(1, maxMajorStateChanges))
    }
}

struct StoryGenerationIntent: Codable, Hashable, Sendable {
    var architectureFamily: StoryArchitectureFamily = .unspecified
    var compassLocks: [CompassLock] = []
    var avoidStructures: [StoryStructureAvoidance] = []
    var beatContract: BeatGenerationContract = BeatGenerationContract()

    func normalized() -> StoryGenerationIntent {
        var value = self
        value.compassLocks = value.compassLocks.map { $0.normalized() }.filter { !$0.text.isEmpty }
        value.avoidStructures = value.avoidStructures.map { $0.normalized() }.filter { !$0.dimension.isEmpty && !$0.value.isEmpty }
        value.beatContract = value.beatContract.normalized()
        return value
    }
}

struct SceneStoryGenerationBrief: Codable, Hashable, Sendable {
    var storyForm: StoryForm = .dramaticArc
    var audienceEffect: String = ""
    var emotionalStart: [CompassLock] = []
    var emotionalDestination: [CompassLock] = []
    var groundingPolicy: String = ""
    var noveltyPolicy: StoryNoveltyPolicy = StoryNoveltyPolicy()
    var tonePolicy: String = ""
    var evidencePolicy: String = ""

    func normalized() -> SceneStoryGenerationBrief {
        var value = self
        value.audienceEffect = value.audienceEffect.trimmed
        value.emotionalStart = value.emotionalStart.map { $0.normalized() }.filter { !$0.text.isEmpty }
        value.emotionalDestination = value.emotionalDestination.map { $0.normalized() }.filter { !$0.text.isEmpty }
        value.groundingPolicy = value.groundingPolicy.trimmed
        value.noveltyPolicy = value.noveltyPolicy.normalized()
        value.tonePolicy = value.tonePolicy.trimmed
        value.evidencePolicy = value.evidencePolicy.trimmed
        return value
    }
}

struct StoryNoveltyPolicy: Codable, Hashable, Sendable {
    // Legacy compatibility only. Novelty is now a preference, not a global
    // minimum-difference requirement. New requests should leave this at zero.
    var minDifferingDimensions: Int = 0
    var preserveDimensions: [String] = []
    var varyDimensions: [String] = []
    var avoidElements: [String] = []

    func normalized() -> StoryNoveltyPolicy {
        StoryNoveltyPolicy(
            minDifferingDimensions: Swift.max(0, minDifferingDimensions),
            preserveDimensions: uniqueNonEmpty(preserveDimensions),
            varyDimensions: uniqueNonEmpty(varyDimensions),
            avoidElements: uniqueNonEmpty(avoidElements)
        )
    }
}

struct StoryBlueprint: Codable, Hashable, Sendable {
    var storyForm: StoryForm = .dramaticArc
    var architectureFamily: StoryArchitectureFamily = .unspecified
    var primaryActor: String = ""
    var actingForce: String = ""
    var causalEngine: String = ""
    var settingProgression: [String] = []
    var primaryMeaningMove: String = ""
    var compassDestination: String = ""
    var payoffMechanism: String = ""
    var coreVisualImage: String = ""

    enum CodingKeys: String, CodingKey {
        case storyForm
        case architectureFamily
        case primaryActor
        case actingForce
        case causalEngine
        case settingProgression
        case primaryMeaningMove
        case compassDestination
        case payoffMechanism
        case coreVisualImage
    }

    init(
        storyForm: StoryForm = .dramaticArc,
        architectureFamily: StoryArchitectureFamily = .unspecified,
        primaryActor: String = "",
        actingForce: String = "",
        causalEngine: String = "",
        settingProgression: [String] = [],
        primaryMeaningMove: String = "",
        compassDestination: String = "",
        payoffMechanism: String = "",
        coreVisualImage: String = ""
    ) {
        self.storyForm = storyForm
        self.architectureFamily = architectureFamily
        self.primaryActor = primaryActor
        self.actingForce = actingForce
        self.causalEngine = causalEngine
        self.settingProgression = settingProgression
        self.primaryMeaningMove = primaryMeaningMove
        self.compassDestination = compassDestination
        self.payoffMechanism = payoffMechanism
        self.coreVisualImage = coreVisualImage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storyForm = try container.decodeIfPresent(StoryForm.self, forKey: .storyForm) ?? .dramaticArc
        architectureFamily = try container.decodeIfPresent(StoryArchitectureFamily.self, forKey: .architectureFamily) ?? .unspecified
        primaryActor = try container.decodeIfPresent(String.self, forKey: .primaryActor) ?? ""
        actingForce = try container.decodeIfPresent(String.self, forKey: .actingForce) ?? ""
        causalEngine = try container.decodeIfPresent(String.self, forKey: .causalEngine) ?? ""
        settingProgression = try container.decodeIfPresent([String].self, forKey: .settingProgression) ?? []
        primaryMeaningMove = try container.decodeIfPresent(String.self, forKey: .primaryMeaningMove) ?? ""
        compassDestination = try container.decodeIfPresent(String.self, forKey: .compassDestination) ?? ""
        payoffMechanism = try container.decodeIfPresent(String.self, forKey: .payoffMechanism) ?? ""
        coreVisualImage = try container.decodeIfPresent(String.self, forKey: .coreVisualImage) ?? ""
    }

    func normalized() -> StoryBlueprint {
        var value = self
        value.primaryActor = value.primaryActor.trimmed
        value.actingForce = value.actingForce.trimmed
        value.causalEngine = value.causalEngine.trimmed
        value.settingProgression = uniqueNonEmpty(value.settingProgression)
        value.primaryMeaningMove = value.primaryMeaningMove.trimmed
        value.compassDestination = value.compassDestination.trimmed
        value.payoffMechanism = value.payoffMechanism.trimmed
        value.coreVisualImage = value.coreVisualImage.trimmed
        return value
    }
}

struct StoryReasoningSummary: Codable, Hashable, Sendable {
    var whyThisForm: String = ""
    var whyThisArc: String = ""
    var whyThisPayoff: String = ""

    func normalized() -> StoryReasoningSummary {
        StoryReasoningSummary(
            whyThisForm: whyThisForm.trimmed,
            whyThisArc: whyThisArc.trimmed,
            whyThisPayoff: whyThisPayoff.trimmed
        )
    }
}

struct TypedCompassLabel: Codable, Hashable, Sendable {
    var kind: CompassLabelKind = .label
    var text: String = ""

    func normalized() -> TypedCompassLabel {
        TypedCompassLabel(kind: kind, text: text.trimmed)
    }
}

struct StoryGenerationLensReference: Codable, Hashable, Sendable, Identifiable {
    var id: String { lensId }
    var lensId: String = ""
    var lensVersionId: String = ""
    var snapshotHash: String = ""
    var role: String = "primary"

    static func from(lens: ProjectLens, lensVersionId: String, role: String) -> StoryGenerationLensReference {
        StoryGenerationLensReference(
            lensId: lens.lensId,
            lensVersionId: lensVersionId,
            snapshotHash: stableHash(lens.normalized(), length: 20),
            role: role
        )
    }
}

struct StorySignatureDocument: Codable, Hashable, Sendable, Identifiable {
    static let schemaVersion = "litscenes.story_signature.v0.1"

    var schemaVersion: String = Self.schemaVersion
    var storySignatureId: String = storyUUIDIdentifier("story_signature")
    var id: String { storySignatureId }
    var projectId: String = ""
    var storySuggestionId: String = ""
    var projectStoryId: String = ""
    var storyVersionId: String = ""
    var sourceSceneStorySetId: String = ""
    var sourceStoryId: String = ""
    var generationSessionId: String = ""
    var goalFingerprint: String = ""
    var lensContextFingerprint: String = ""
    var lensIds: [String] = []
    var contextClass: StoryMemoryContextClass = .currentContext
    var title: String = ""
    var premise: String = ""
    var storyEngine: String = ""
    var centralSubjectOrActor: String = ""
    var primarySetting: String = ""
    var coreVisualImage: String = ""
    var meaningThesis: String = ""
    var primaryMeaningMove: String = ""
    var emotionalStartLabels: [String] = []
    var emotionalEndLabels: [String] = []
    var arcShape: String = ""
    var sceneFunctionSequence: [String] = []
    var payoffOrEnding: String = ""
    var storyBlueprint: StoryBlueprint = StoryBlueprint()
    var editorialState: ProjectStoryEditorialState = .suggestion
    var productionState: ProjectStoryProductionState = .notStarted
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()

    func normalized() -> StorySignatureDocument {
        var value = self
        value.storySignatureId = value.storySignatureId.trimmed.isEmpty ? storyUUIDIdentifier("story_signature") : value.storySignatureId.trimmed
        value.schemaVersion = Self.schemaVersion
        value.projectId = value.projectId.trimmed
        value.storySuggestionId = value.storySuggestionId.trimmed
        value.projectStoryId = value.projectStoryId.trimmed
        value.storyVersionId = value.storyVersionId.trimmed
        value.sourceSceneStorySetId = value.sourceSceneStorySetId.trimmed
        value.sourceStoryId = value.sourceStoryId.trimmed
        value.generationSessionId = value.generationSessionId.trimmed
        value.goalFingerprint = value.goalFingerprint.trimmed
        value.lensContextFingerprint = value.lensContextFingerprint.trimmed
        value.lensIds = uniqueNonEmpty(value.lensIds)
        value.title = value.title.trimmed
        value.premise = value.premise.trimmed
        value.storyEngine = value.storyEngine.trimmed
        value.centralSubjectOrActor = value.centralSubjectOrActor.trimmed
        value.primarySetting = value.primarySetting.trimmed
        value.coreVisualImage = value.coreVisualImage.trimmed
        value.meaningThesis = value.meaningThesis.trimmed
        value.primaryMeaningMove = value.primaryMeaningMove.trimmed
        value.emotionalStartLabels = uniqueNonEmpty(value.emotionalStartLabels)
        value.emotionalEndLabels = uniqueNonEmpty(value.emotionalEndLabels)
        value.arcShape = value.arcShape.trimmed
        value.sceneFunctionSequence = uniqueNonEmpty(value.sceneFunctionSequence)
        value.payoffOrEnding = value.payoffOrEnding.trimmed
        value.storyBlueprint = value.storyBlueprint.normalized()
        if value.createdAt.trimmed.isEmpty {
            value.createdAt = DateFormats.now()
        }
        value.updatedAt = value.updatedAt.trimmed.isEmpty ? value.createdAt : value.updatedAt.trimmed
        return value
    }
}

struct StoryMemoryReference: Codable, Hashable, Sendable {
    var referenceKind: String = ""
    var storySuggestionId: String = ""
    var projectStoryId: String = ""
    var storyVersionId: String = ""
    var signature: StorySignatureDocument = StorySignatureDocument()
    var storySnapshot: SceneStory?
}

struct StoryMemoryRequest: Codable, Hashable, Sendable {
    var mode: StoryGenerationMode = .avoidOverlap
    var priorStorySignatures: [StorySignatureDocument] = []
    var positiveReferenceStory: StoryMemoryReference?
    var branchParentStory: StoryMemoryReference?
    var reflowSelectedStory: StoryMemoryReference?
    var preserveDimensions: [String] = []
    var varyDimensions: [String] = []
    var avoidElements: [String] = []

    static let empty = StoryMemoryRequest()

    func normalized(limit: Int = 12) -> StoryMemoryRequest {
        var value = self
        value.priorStorySignatures = Array(value.priorStorySignatures.map { $0.normalized() }.prefix(limit))
        value.preserveDimensions = uniqueNonEmpty(value.preserveDimensions)
        value.varyDimensions = uniqueNonEmpty(value.varyDimensions)
        value.avoidElements = uniqueNonEmpty(value.avoidElements)
        return value
    }
}

struct StoryGenerationCreativeContextSnapshot: Codable, Hashable, Sendable {
    var goalVersionId: String = ""
    var goalFingerprint: String = ""
    var lensContextFingerprint: String = ""
    var lensRefs: [StoryGenerationLensReference] = []
    var generationOrigin: StoryGenerationOrigin = .manual
    var goalCast: [SceneStoryGoalCastMemberSnapshot] = []
    var mediaAnalysisFingerprint: String = ""
    var selectedMediaIds: [String] = []
    var outputContextFingerprint: String = ""
    var generationControls: [String: String] = [:]
    var priorStorySignatures: [StorySignatureDocument] = []
    var referenceStories: [StoryMemoryReference] = []
}

struct StoryGenerationResultSlot: Codable, Hashable, Sendable, Identifiable {
    var resultSlotId: String = storyUUIDIdentifier("story_generation_slot")
    var id: String { resultSlotId }
    var index: Int = 0
    var status: StoryGenerationResultSlotStatus = .queued
    var sourceSceneStorySetId: String = ""
    var sourceStoryId: String = ""
    var storySuggestionId: String = ""
    var storySignatureId: String = ""
    var title: String = ""
    var startedAt: String = ""
    var completedAt: String = ""
    var failedAt: String = ""
    var cancelledAt: String = ""
    var errorMessage: String = ""
    var relatedVariantOfStoryId: String = ""
    var relatedVariantReasons: [String] = []
    var requestSnapshotPath: String = ""
    var requestFingerprint: String = ""
    var promptTemplateVersion: String = ""
    var operatorInstructionSnapshot: [String] = []
    var storyMemorySignatureIds: [String] = []
    var storyMemorySnapshotPath: String = ""
    var openaiResponseId: String = ""
    var hostedRequestId: String = ""
    var attemptRecords: [StoryGenerationAttemptRecord] = []
}

struct StoryGenerationAttemptRecord: Codable, Hashable, Sendable, Identifiable {
    var attemptId: String = storyUUIDIdentifier("story_generation_attempt")
    var id: String { attemptId }
    var slotIndex: Int = 0
    var attemptIndex: Int = 0
    var purpose: String = ""
    var status: String = ""
    var requestSnapshotPath: String = ""
    var requestFingerprint: String = ""
    var promptTemplateVersion: String = ""
    var operatorInstructionSnapshot: [String] = []
    var storyMemorySignatureIds: [String] = []
    var openaiResponseId: String = ""
    var hostedRequestId: String = ""
    var model: String = ""
    var startedAt: String = ""
    var completedAt: String = ""
    var errorMessage: String = ""
}

struct StoryGenerationSessionDocument: Codable, Hashable, Sendable, Identifiable {
    static let schemaVersion = "litscenes.story_generation_session.v0.1"

    var schemaVersion: String = Self.schemaVersion
    var generationSessionId: String = storyUUIDIdentifier("story_generation_session")
    var id: String { generationSessionId }
    var projectId: String = ""
    var goalFingerprint: String = ""
    var lensContextFingerprint: String = ""
    var lensRefs: [StoryGenerationLensReference] = []
    var generationOrigin: StoryGenerationOrigin = .manual
    var mode: StoryGenerationMode = .avoidOverlap
    var requestedStoryCount: Int = SceneStoryGenerationSizing.defaultStoryBatchCount
    var requestedStartingDepth: StoryStartingDepth = .fourSceneArc
    var differenceMode: StoryDifferenceMode = .distinct
    var groundingMode: StoryGroundingMode = .balanced
    var priorStorySignatureIds: [String] = []
    var sourceSetIds: [String] = []
    var resultStoryRefs: [String] = []
    var creativeContext: StoryGenerationCreativeContextSnapshot = StoryGenerationCreativeContextSnapshot()
    var slots: [StoryGenerationResultSlot] = []
    var startedAt: String = DateFormats.now()
    var completedAt: String = ""
    var status: String = "queued"
    var warnings: [String] = []

    static func create(
        projectId: String,
        goalFingerprint: String,
        lensContextFingerprint: String,
        lensRefs: [StoryGenerationLensReference],
        generationOrigin: StoryGenerationOrigin,
        mode: StoryGenerationMode,
        requestedStoryCount: Int,
        requestedStartingDepth: StoryStartingDepth,
        differenceMode: StoryDifferenceMode,
        groundingMode: StoryGroundingMode,
        creativeContext: StoryGenerationCreativeContextSnapshot,
        now: String = DateFormats.now()
    ) -> StoryGenerationSessionDocument {
        let count = min(max(requestedStoryCount, 1), 6)
        return StoryGenerationSessionDocument(
            projectId: projectId,
            goalFingerprint: goalFingerprint,
            lensContextFingerprint: lensContextFingerprint,
            lensRefs: lensRefs,
            generationOrigin: generationOrigin,
            mode: mode,
            requestedStoryCount: count,
            requestedStartingDepth: requestedStartingDepth,
            differenceMode: differenceMode,
            groundingMode: groundingMode,
            priorStorySignatureIds: creativeContext.priorStorySignatures.map(\.storySignatureId),
            creativeContext: creativeContext,
            slots: (0..<count).map { StoryGenerationResultSlot(index: $0 + 1) },
            startedAt: now,
            status: "running"
        )
    }

    func normalized() -> StoryGenerationSessionDocument {
        var value = self
        value.schemaVersion = Self.schemaVersion
        value.generationSessionId = value.generationSessionId.trimmed.isEmpty ? storyUUIDIdentifier("story_generation_session") : value.generationSessionId.trimmed
        value.projectId = value.projectId.trimmed
        value.goalFingerprint = value.goalFingerprint.trimmed
        value.lensContextFingerprint = value.lensContextFingerprint.trimmed
        value.creativeContext.generationOrigin = value.generationOrigin
        value.requestedStoryCount = min(max(value.requestedStoryCount, 1), 6)
        value.priorStorySignatureIds = uniqueNonEmpty(value.priorStorySignatureIds)
        value.sourceSetIds = uniqueNonEmpty(value.sourceSetIds)
        value.resultStoryRefs = uniqueNonEmpty(value.resultStoryRefs)
        value.slots = value.slots.sorted { $0.index < $1.index }
        value.status = value.status.trimmed.isEmpty ? "queued" : value.status.trimmed
        value.warnings = uniqueNonEmpty(value.warnings)
        return value
    }

    var completedSlotCount: Int {
        slots.filter { $0.status == .complete }.count
    }

    var failedSlotCount: Int {
        slots.filter { $0.status == .failed }.count
    }
}

struct ProjectStoryLibraryEntry: Codable, Hashable, Sendable, Identifiable {
    var libraryEntryId: String = storyUUIDIdentifier("story_library_entry")
    var id: String { libraryEntryId }
    var storySuggestionId: String = ""
    var projectStoryId: String = ""
    var sourceSceneStorySetId: String = ""
    var sourceStoryId: String = ""
    var generationSessionId: String = ""
    var parentProjectStoryId: String = ""
    var editorialState: ProjectStoryEditorialState = .suggestion
    var productionState: ProjectStoryProductionState = .notStarted
    var title: String = ""
    var lensIds: [String] = []
    var currentVersionId: String = ""
    var storySignatureId: String = ""
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()

    func normalized() -> ProjectStoryLibraryEntry {
        var value = self
        value.libraryEntryId = value.libraryEntryId.trimmed.isEmpty ? storyUUIDIdentifier("story_library_entry") : value.libraryEntryId.trimmed
        value.storySuggestionId = value.storySuggestionId.trimmed
        value.projectStoryId = value.projectStoryId.trimmed
        value.sourceSceneStorySetId = value.sourceSceneStorySetId.trimmed
        value.sourceStoryId = value.sourceStoryId.trimmed
        value.generationSessionId = value.generationSessionId.trimmed
        value.parentProjectStoryId = value.parentProjectStoryId.trimmed
        value.title = value.title.trimmed
        value.lensIds = uniqueNonEmpty(value.lensIds)
        value.currentVersionId = value.currentVersionId.trimmed
        value.storySignatureId = value.storySignatureId.trimmed
        if value.createdAt.trimmed.isEmpty {
            value.createdAt = DateFormats.now()
        }
        value.updatedAt = value.updatedAt.trimmed.isEmpty ? value.createdAt : value.updatedAt.trimmed
        return value
    }
}

struct ProjectStoryLibraryDocument: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.project_story_library.v0.1"

    var schemaVersion: String = Self.schemaVersion
    var projectId: String = ""
    var entries: [ProjectStoryLibraryEntry] = []
    var activeStoryId: String = ""
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String) -> ProjectStoryLibraryDocument {
        ProjectStoryLibraryDocument(projectId: projectId)
    }

    func normalized() -> ProjectStoryLibraryDocument {
        var value = self
        value.schemaVersion = Self.schemaVersion
        value.projectId = value.projectId.trimmed
        value.entries = value.entries
            .map { $0.normalized() }
            .sorted { lhs, rhs in
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                return lhs.updatedAt > rhs.updatedAt
            }
        value.activeStoryId = value.activeStoryId.trimmed
        value.updatedAt = value.updatedAt.trimmed.isEmpty ? DateFormats.now() : value.updatedAt.trimmed
        return value
    }

    var visibleEntries: [ProjectStoryLibraryEntry] {
        entries.filter { $0.editorialState != .dismissed && $0.editorialState != .archived }
    }

    /// The one story the rest of the app treats as "the" story: the active story
    /// while it is still visible, else the first visible entry. Shared by the
    /// Story Library rail and the Scenes landing hero so both agree.
    var preferredEntry: ProjectStoryLibraryEntry? {
        if !activeStoryId.trimmed.isEmpty,
           let active = visibleEntries.first(where: { $0.projectStoryId == activeStoryId }) {
            return active
        }
        return visibleEntries.first
    }
}

struct ProjectStoryVersionDocument: Codable, Hashable, Sendable, Identifiable {
    static let schemaVersion = "litscenes.project_story_version.v0.1"

    var schemaVersion: String = Self.schemaVersion
    var storyVersionId: String = storyUUIDIdentifier("story_version")
    var id: String { storyVersionId }
    var projectStoryId: String = ""
    var sourceStorySuggestionId: String = ""
    var parentStoryVersionId: String = ""
    var reason: String = ""
    var story: SceneStory = SceneStory.empty()
    var lockManifest: StoryLockManifest = StoryLockManifest()
    var sceneRevisionIds: [String] = []
    var beatRevisionIds: [String] = []
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()
}

struct StoryLockManifest: Codable, Hashable, Sendable {
    var lockedStoryFingerprint: String = ""
    var lockedSceneFingerprints: [String: String] = [:]
    var lockedBeatFingerprints: [String: String] = [:]
}

struct SceneRevisionDocument: Codable, Hashable, Sendable, Identifiable {
    var sceneRevisionId: String = storyUUIDIdentifier("scene_revision")
    var id: String { sceneRevisionId }
    var projectStoryId: String = ""
    var storyVersionId: String = ""
    var sceneId: String = ""
    var scene: SceneStoryScene
    var createdAt: String = DateFormats.now()
}

struct BeatRevisionDocument: Codable, Hashable, Sendable, Identifiable {
    var beatRevisionId: String = storyUUIDIdentifier("beat_revision")
    var id: String { beatRevisionId }
    var projectStoryId: String = ""
    var storyVersionId: String = ""
    var sceneId: String = ""
    var beatId: String = ""
    var beat: SceneStoryBeat
    var beatContentFingerprint: String = ""
    var createdAt: String = DateFormats.now()
}

struct BeatTakeDocument: Codable, Hashable, Sendable, Identifiable {
    var takeId: String = storyUUIDIdentifier("take")
    var id: String { takeId }
    var projectStoryId: String = ""
    var storyVersionId: String = ""
    var sceneRevisionId: String = ""
    var beatRevisionId: String = ""
    var beatContentFingerprint: String = ""
    var productionContractFingerprint: String = ""
    var providerId: String = ""
    var modelId: String = ""
    var status: String = "queued"
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()
}

struct EmotionalCompassPoint: Codable, Hashable, Sendable {
    var labels: [String]
    var typedLabels: [TypedCompassLabel]
    var valence: Double
    var activation: Double
    var agency: Double

    init(labels: [String] = [], typedLabels: [TypedCompassLabel] = [], valence: Double = 0, activation: Double = 0, agency: Double = 0) {
        let normalizedTyped = typedLabels.map { $0.normalized() }.filter { !$0.text.isEmpty }
        self.labels = labels.isEmpty ? normalizedTyped.map(\.text) : labels
        self.typedLabels = normalizedTyped.isEmpty ? labels.map { TypedCompassLabel(kind: .label, text: $0.trimmed) }.filter { !$0.text.isEmpty } : normalizedTyped
        self.valence = valence
        self.activation = activation
        self.agency = agency
    }

    enum CodingKeys: String, CodingKey {
        case labels
        case typedLabels
        case valence
        case activation
        case agency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        typedLabels = try container.decodeIfPresent([TypedCompassLabel].self, forKey: .typedLabels) ?? labels.map { TypedCompassLabel(kind: .label, text: $0.trimmed) }
        valence = try container.decodeIfPresent(Double.self, forKey: .valence) ?? 0
        activation = try container.decodeIfPresent(Double.self, forKey: .activation) ?? 0
        agency = try container.decodeIfPresent(Double.self, forKey: .agency) ?? 0
    }

    func normalized() -> EmotionalCompassPoint {
        EmotionalCompassPoint(
            labels: uniqueNonEmpty(labels, limit: 6),
            typedLabels: typedLabels.map { $0.normalized() }.filter { !$0.text.isEmpty },
            valence: Self.clampCoordinate(valence),
            activation: Self.clampCoordinate(activation),
            agency: Self.clampCoordinate(agency)
        )
    }

    private static func clampCoordinate(_ value: Double) -> Double {
        min(max(value, -1), 1)
    }

    var labelSummary: String {
        labels.map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " / ")
    }

    var isEmpty: Bool {
        labels.allSatisfy { $0.trimmed.isEmpty }
    }
}

struct StoryEmotionalArc: Codable, Hashable, Sendable {
    var start: EmotionalCompassPoint
    var end: EmotionalCompassPoint
    var arcShape: String

    init(start: EmotionalCompassPoint = EmotionalCompassPoint(), end: EmotionalCompassPoint = EmotionalCompassPoint(), arcShape: String = "") {
        self.start = start
        self.end = end
        self.arcShape = arcShape
    }

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case arcShape
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeIfPresent(EmotionalCompassPoint.self, forKey: .start) ?? EmotionalCompassPoint()
        end = try container.decodeIfPresent(EmotionalCompassPoint.self, forKey: .end) ?? EmotionalCompassPoint()
        arcShape = try container.decodeIfPresent(String.self, forKey: .arcShape) ?? ""
    }

    func normalized() -> StoryEmotionalArc {
        StoryEmotionalArc(start: start.normalized(), end: end.normalized(), arcShape: arcShape.trimmed)
    }

    var isEmpty: Bool {
        start.isEmpty && end.isEmpty && arcShape.trimmed.isEmpty
    }
}

struct SceneEmotionalArc: Codable, Hashable, Sendable {
    var entry: EmotionalCompassPoint
    var exit: EmotionalCompassPoint
    var primaryTurn: String
    var inheritedFromStory: Bool
    var overrideNote: String

    init(
        entry: EmotionalCompassPoint = EmotionalCompassPoint(),
        exit: EmotionalCompassPoint = EmotionalCompassPoint(),
        primaryTurn: String = "",
        inheritedFromStory: Bool = true,
        overrideNote: String = ""
    ) {
        self.entry = entry
        self.exit = exit
        self.primaryTurn = primaryTurn
        self.inheritedFromStory = inheritedFromStory
        self.overrideNote = overrideNote
    }

    enum CodingKeys: String, CodingKey {
        case entry
        case exit
        case primaryTurn
        case inheritedFromStory
        case overrideNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entry = try container.decodeIfPresent(EmotionalCompassPoint.self, forKey: .entry) ?? EmotionalCompassPoint()
        exit = try container.decodeIfPresent(EmotionalCompassPoint.self, forKey: .exit) ?? EmotionalCompassPoint()
        primaryTurn = try container.decodeIfPresent(String.self, forKey: .primaryTurn) ?? ""
        inheritedFromStory = try container.decodeIfPresent(Bool.self, forKey: .inheritedFromStory) ?? true
        overrideNote = try container.decodeIfPresent(String.self, forKey: .overrideNote) ?? ""
    }

    func normalized() -> SceneEmotionalArc {
        SceneEmotionalArc(
            entry: entry.normalized(),
            exit: exit.normalized(),
            primaryTurn: primaryTurn.trimmed,
            inheritedFromStory: inheritedFromStory,
            overrideNote: overrideNote.trimmed
        )
    }

    var isEmpty: Bool {
        entry.isEmpty && exit.isEmpty && primaryTurn.trimmed.isEmpty
    }
}

struct BeatEmotionalTurn: Codable, Hashable, Sendable {
    var entry: EmotionalCompassPoint
    var exit: EmotionalCompassPoint
    var turnDescription: String
    var observableEvidence: [String]
    var performanceDirection: [String]
    var avoidEmotionalCliches: [String]

    init(
        entry: EmotionalCompassPoint = EmotionalCompassPoint(),
        exit: EmotionalCompassPoint = EmotionalCompassPoint(),
        turnDescription: String = "",
        observableEvidence: [String] = [],
        performanceDirection: [String] = [],
        avoidEmotionalCliches: [String] = []
    ) {
        self.entry = entry
        self.exit = exit
        self.turnDescription = turnDescription
        self.observableEvidence = observableEvidence
        self.performanceDirection = performanceDirection
        self.avoidEmotionalCliches = avoidEmotionalCliches
    }

    enum CodingKeys: String, CodingKey {
        case entry
        case exit
        case turnDescription
        case observableEvidence
        case performanceDirection
        case avoidEmotionalCliches
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entry = try container.decodeIfPresent(EmotionalCompassPoint.self, forKey: .entry) ?? EmotionalCompassPoint()
        exit = try container.decodeIfPresent(EmotionalCompassPoint.self, forKey: .exit) ?? EmotionalCompassPoint()
        turnDescription = try container.decodeIfPresent(String.self, forKey: .turnDescription) ?? ""
        observableEvidence = try container.decodeIfPresent([String].self, forKey: .observableEvidence) ?? []
        performanceDirection = try container.decodeIfPresent([String].self, forKey: .performanceDirection) ?? []
        avoidEmotionalCliches = try container.decodeIfPresent([String].self, forKey: .avoidEmotionalCliches) ?? []
    }

    func normalized() -> BeatEmotionalTurn {
        BeatEmotionalTurn(
            entry: entry.normalized(),
            exit: exit.normalized(),
            turnDescription: turnDescription.trimmed,
            observableEvidence: uniqueNonEmpty(observableEvidence),
            performanceDirection: uniqueNonEmpty(performanceDirection),
            avoidEmotionalCliches: uniqueNonEmpty(avoidEmotionalCliches)
        )
    }

    var isEmpty: Bool {
        entry.isEmpty && exit.isEmpty && turnDescription.trimmed.isEmpty && observableEvidence.isEmpty
    }
}

struct SceneStoryLensSnapshot: Codable, Hashable, Sendable {
    var lensId: String
    var claim: String
    var userNotes: String
    var visualSummary: String
    var resolvedVisualLanguage: LensResolvedVisualLanguage?
    var mustPreserve: [String]
    var mustAvoid: [String]
    var referenceMediaIds: [String]

    static func from(lens: ProjectLens) -> SceneStoryLensSnapshot {
        let normalized = lens.normalized()
        let promptSafe = PromptSafeLensSnapshot.from(lens: normalized)
        return SceneStoryLensSnapshot(
            lensId: normalized.lensId,
            claim: promptSafe.claim,
            userNotes: "",
            visualSummary: promptSafe.visualSummary,
            resolvedVisualLanguage: promptSafe.resolvedVisualLanguage,
            mustPreserve: promptSafe.mustPreserve,
            mustAvoid: promptSafe.mustAvoid,
            referenceMediaIds: promptSafe.referenceMediaIds
        )
    }
}

struct SceneStoryMediaAnchor: Codable, Hashable, Sendable {
    var mediaId: String = ""
    var frameId: String = ""
    var kind: String = ""
    var role: String = ""
    var summary: String = ""
    var observedSymbols: [String] = []
    var aestheticTerms: [String] = []
    var negativeConstraints: [String] = []
    var notes: String = ""
}

struct SceneStoryOutputProfile: Codable, Hashable, Sendable {
    var aspectRatio: String = ""
    var durationTargetSeconds: Int = 0
    var chainStrategy: String = ""
    var destination: String = ""
    var providerHint: String = ""

    static let `default` = SceneStoryOutputProfile(
        aspectRatio: "16:9",
        durationTargetSeconds: 50,
        chainStrategy: "scene_to_segment",
        destination: "",
        providerHint: ""
    )
}

struct SceneStorySetDocument: Codable, Hashable, Identifiable, Sendable {
    static let schemaVersion = "litscenes.scene_story_set.v0.4"

    var schemaVersion: String = Self.schemaVersion
    var id: String { sceneStorySetId }
    var sceneStorySetId: String = ""
    var userId: String = ""
    var projectId: String = ""
    var goalFingerprint: String = ""
    var lensId: String = ""
    var lensContextFingerprint: String = ""
    var storyCount: Int = 0
    var scenesPerStory: Int = 0
    var beatsPerScene: Int = 0
    var generatedAt: String = ""
    var generator: String = ""
    var model: String = ""
    var sceneStories: [SceneStory] = []
    var operatorFeedback: [SceneStoryOperatorFeedback] = []
    var warnings: [String] = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sceneStorySetId
        case userId
        case projectId
        case goalFingerprint
        case lensId
        case lensContextFingerprint
        case legacyThemeId = "themeId"
        case legacyThemeContextFingerprint = "themeContextFingerprint"
        case storyCount
        case scenesPerStory
        case beatsPerScene
        case generatedAt
        case generator
        case model
        case sceneStories
        case operatorFeedback
        case warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        sceneStorySetId = try container.decodeIfPresent(String.self, forKey: .sceneStorySetId) ?? ""
        userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? ""
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        goalFingerprint = try container.decodeIfPresent(String.self, forKey: .goalFingerprint) ?? ""
        lensId = try container.decodeIfPresent(String.self, forKey: .lensId)
            ?? container.decodeIfPresent(String.self, forKey: .legacyThemeId)
            ?? ""
        lensContextFingerprint = try container.decodeIfPresent(String.self, forKey: .lensContextFingerprint)
            ?? container.decodeIfPresent(String.self, forKey: .legacyThemeContextFingerprint)
            ?? ""
        storyCount = try container.decodeIfPresent(Int.self, forKey: .storyCount) ?? 0
        scenesPerStory = try container.decodeIfPresent(Int.self, forKey: .scenesPerStory) ?? 0
        beatsPerScene = try container.decodeIfPresent(Int.self, forKey: .beatsPerScene) ?? 0
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        generator = try container.decodeIfPresent(String.self, forKey: .generator) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        sceneStories = try container.decodeIfPresent([SceneStory].self, forKey: .sceneStories) ?? []
        operatorFeedback = try container.decodeIfPresent([SceneStoryOperatorFeedback].self, forKey: .operatorFeedback) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(sceneStorySetId, forKey: .sceneStorySetId)
        try container.encode(userId, forKey: .userId)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(goalFingerprint, forKey: .goalFingerprint)
        try container.encode(lensId, forKey: .lensId)
        try container.encode(lensContextFingerprint, forKey: .lensContextFingerprint)
        try container.encode(storyCount, forKey: .storyCount)
        try container.encode(scenesPerStory, forKey: .scenesPerStory)
        try container.encode(beatsPerScene, forKey: .beatsPerScene)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(generator, forKey: .generator)
        try container.encode(model, forKey: .model)
        try container.encode(sceneStories, forKey: .sceneStories)
        try container.encode(operatorFeedback, forKey: .operatorFeedback)
        try container.encode(warnings, forKey: .warnings)
    }

    static func decode(from data: Data) throws -> SceneStorySetDocument {
        if let envelope = try? JSONCoding.decoder.decode(SceneStorySetEnvelope.self, from: data),
           !envelope.document.sceneStories.isEmpty {
            return envelope.document.normalized()
        }

        do {
            let document = try JSONCoding.decoder.decode(SceneStorySetDocument.self, from: data)
            return document.normalized()
        } catch {
            if let envelope = try? JSONCoding.decoder.decode(SceneStorySetEnvelope.self, from: data) {
                return envelope.document.normalized()
            }
            if let envelope = try? JSONCoding.decoder.decode(LegacySceneStorySetEnvelope.self, from: data) {
                return envelope.body.normalized()
            }
            throw error
        }
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(normalized())
    }

    func normalized() -> SceneStorySetDocument {
        var value = self
        value.sceneStorySetId = value.sceneStorySetId.trimmed
        if value.generatedAt.trimmed.isEmpty {
            value.generatedAt = DateFormats.now()
        }
        if value.sceneStorySetId.isEmpty {
            value.sceneStorySetId = "scene_story_set_\(shortHash("\(projectId):\(goalFingerprint):\(lensId):\(generatedAt)", length: 16))"
        }
        value.schemaVersion = Self.schemaVersion
        value.sceneStories = value.sceneStories
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.storyId < rhs.storyId
                }
                return lhs.order < rhs.order
            }
            .enumerated()
            .map { index, story in
                var normalized = story.normalized()
                if normalized.order <= 0 {
                    normalized.order = index + 1
                }
                if normalized.storyId.isEmpty {
                    normalized.storyId = String(format: "story_%03d", normalized.order)
                }
                return normalized
            }
        if value.storyCount <= 0 {
            value.storyCount = value.sceneStories.count
        }
        if value.scenesPerStory <= 0 {
            value.scenesPerStory = value.sceneStories.map { $0.scenes.count }.max() ?? 0
        }
        if value.beatsPerScene <= 0 {
            value.beatsPerScene = value.sceneStories
                .flatMap(\.scenes)
                .map { $0.sceneBeats.count }
                .max() ?? 0
        }
        value.operatorFeedback = value.operatorFeedback.map { $0.normalized() }
        value.warnings = uniqueNonEmpty(value.warnings)
        return value
    }
}

struct SceneStoryOpenAIAttemptProvenance: Codable, Hashable, Sendable {
    var responseId: String = ""
    var purpose: String = ""
    var model: String = ""
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var startedAt: String = ""
    var completedAt: String = ""

    func normalized() -> SceneStoryOpenAIAttemptProvenance {
        var value = self
        value.responseId = value.responseId.trimmed
        value.purpose = value.purpose.trimmed
        value.model = value.model.trimmed
        value.startedAt = value.startedAt.trimmed
        value.completedAt = value.completedAt.trimmed
        return value
    }
}

struct SceneStoryGenerationProvenance: Codable, Hashable, Sendable {
    var lambdaPromptVersion: String = ""
    var desktopInstructionVersion: String = ""
    var validatorVersion: String = ""
    var dialoguePolicyVersion: String = ""
    var openaiAttempts: [SceneStoryOpenAIAttemptProvenance] = []
    var warnings: [String] = []

    func normalized() -> SceneStoryGenerationProvenance {
        var value = self
        value.lambdaPromptVersion = value.lambdaPromptVersion.trimmed
        value.desktopInstructionVersion = value.desktopInstructionVersion.trimmed
        value.validatorVersion = value.validatorVersion.trimmed
        value.dialoguePolicyVersion = value.dialoguePolicyVersion.trimmed
        value.openaiAttempts = value.openaiAttempts.map { $0.normalized() }
        value.warnings = uniqueNonEmpty(value.warnings)
        return value
    }
}

struct SceneStorySetEnvelope: Decodable, Hashable, Sendable {
    var document: SceneStorySetDocument
    var provenance: SceneStoryGenerationProvenance

    enum CodingKeys: String, CodingKey {
        case document
        case body
        case provenance
    }

    init(document: SceneStorySetDocument, provenance: SceneStoryGenerationProvenance = SceneStoryGenerationProvenance()) {
        self.document = document
        self.provenance = provenance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        document = try container.decodeIfPresent(SceneStorySetDocument.self, forKey: .document)
            ?? container.decodeIfPresent(SceneStorySetDocument.self, forKey: .body)
            ?? SceneStorySetDocument()
        provenance = try container.decodeIfPresent(SceneStoryGenerationProvenance.self, forKey: .provenance) ?? SceneStoryGenerationProvenance()
    }
}

struct SceneStoryGenerateResult: Hashable, Sendable {
    var document: SceneStorySetDocument
    var provenance: SceneStoryGenerationProvenance
    var hostedRequestId: String
}

private struct LegacySceneStorySetEnvelope: Decodable {
    var body: SceneStorySetDocument
}

extension StoryGenerationLensReference {
    private enum LensReferenceCodingKeys: String, CodingKey {
        case lensId
        case lensVersionId
        case snapshotHash
        case role
        case legacyThemeId = "themeId"
        case legacyThemeVersionId = "themeVersionId"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: LensReferenceCodingKeys.self)
        self.init()
        lensId = try container.decodeIfPresent(String.self, forKey: .lensId)
            ?? container.decodeIfPresent(String.self, forKey: .legacyThemeId)
            ?? ""
        lensVersionId = try container.decodeIfPresent(String.self, forKey: .lensVersionId)
            ?? container.decodeIfPresent(String.self, forKey: .legacyThemeVersionId)
            ?? ""
        snapshotHash = try container.decodeIfPresent(String.self, forKey: .snapshotHash) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "primary"
    }
}

extension StorySignatureDocument {
    private enum SignatureCodingKeys: String, CodingKey {
        case schemaVersion
        case storySignatureId
        case projectId
        case storySuggestionId
        case projectStoryId
        case storyVersionId
        case sourceSceneStorySetId
        case sourceStoryId
        case generationSessionId
        case goalFingerprint
        case lensContextFingerprint
        case lensIds
        case legacyThemeContextFingerprint = "themeContextFingerprint"
        case legacyThemeIds = "themeIds"
        case contextClass
        case title
        case premise
        case storyEngine
        case centralSubjectOrActor
        case primarySetting
        case coreVisualImage
        case meaningThesis
        case primaryMeaningMove
        case emotionalStartLabels
        case emotionalEndLabels
        case arcShape
        case sceneFunctionSequence
        case payoffOrEnding
        case storyBlueprint
        case editorialState
        case productionState
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SignatureCodingKeys.self)
        self.init()
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        storySignatureId = try container.decodeIfPresent(String.self, forKey: .storySignatureId) ?? storySignatureId
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        storySuggestionId = try container.decodeIfPresent(String.self, forKey: .storySuggestionId) ?? ""
        projectStoryId = try container.decodeIfPresent(String.self, forKey: .projectStoryId) ?? ""
        storyVersionId = try container.decodeIfPresent(String.self, forKey: .storyVersionId) ?? ""
        sourceSceneStorySetId = try container.decodeIfPresent(String.self, forKey: .sourceSceneStorySetId) ?? ""
        sourceStoryId = try container.decodeIfPresent(String.self, forKey: .sourceStoryId) ?? ""
        generationSessionId = try container.decodeIfPresent(String.self, forKey: .generationSessionId) ?? ""
        goalFingerprint = try container.decodeIfPresent(String.self, forKey: .goalFingerprint) ?? ""
        lensContextFingerprint = try container.decodeIfPresent(String.self, forKey: .lensContextFingerprint)
            ?? container.decodeIfPresent(String.self, forKey: .legacyThemeContextFingerprint)
            ?? ""
        lensIds = try container.decodeIfPresent([String].self, forKey: .lensIds)
            ?? container.decodeIfPresent([String].self, forKey: .legacyThemeIds)
            ?? []
        contextClass = try container.decodeIfPresent(StoryMemoryContextClass.self, forKey: .contextClass) ?? .currentContext
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        premise = try container.decodeIfPresent(String.self, forKey: .premise) ?? ""
        storyEngine = try container.decodeIfPresent(String.self, forKey: .storyEngine) ?? ""
        centralSubjectOrActor = try container.decodeIfPresent(String.self, forKey: .centralSubjectOrActor) ?? ""
        primarySetting = try container.decodeIfPresent(String.self, forKey: .primarySetting) ?? ""
        coreVisualImage = try container.decodeIfPresent(String.self, forKey: .coreVisualImage) ?? ""
        meaningThesis = try container.decodeIfPresent(String.self, forKey: .meaningThesis) ?? ""
        primaryMeaningMove = try container.decodeIfPresent(String.self, forKey: .primaryMeaningMove) ?? ""
        emotionalStartLabels = try container.decodeIfPresent([String].self, forKey: .emotionalStartLabels) ?? []
        emotionalEndLabels = try container.decodeIfPresent([String].self, forKey: .emotionalEndLabels) ?? []
        arcShape = try container.decodeIfPresent(String.self, forKey: .arcShape) ?? ""
        sceneFunctionSequence = try container.decodeIfPresent([String].self, forKey: .sceneFunctionSequence) ?? []
        payoffOrEnding = try container.decodeIfPresent(String.self, forKey: .payoffOrEnding) ?? ""
        storyBlueprint = try container.decodeIfPresent(StoryBlueprint.self, forKey: .storyBlueprint) ?? StoryBlueprint()
        editorialState = try container.decodeIfPresent(ProjectStoryEditorialState.self, forKey: .editorialState) ?? .suggestion
        productionState = try container.decodeIfPresent(ProjectStoryProductionState.self, forKey: .productionState) ?? .notStarted
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? createdAt
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? updatedAt
    }
}

extension StoryGenerationCreativeContextSnapshot {
    private enum CreativeContextCodingKeys: String, CodingKey {
        case goalVersionId
        case goalFingerprint
        case lensContextFingerprint
        case lensRefs
        case generationOrigin
        case goalCast
        case legacyThemeContextFingerprint = "themeContextFingerprint"
        case legacyThemeRefs = "themeRefs"
        case mediaAnalysisFingerprint
        case selectedMediaIds
        case outputContextFingerprint
        case generationControls
        case priorStorySignatures
        case referenceStories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CreativeContextCodingKeys.self)
        self.init()
        goalVersionId = try container.decodeIfPresent(String.self, forKey: .goalVersionId) ?? ""
        goalFingerprint = try container.decodeIfPresent(String.self, forKey: .goalFingerprint) ?? ""
        lensContextFingerprint = try container.decodeIfPresent(String.self, forKey: .lensContextFingerprint)
            ?? container.decodeIfPresent(String.self, forKey: .legacyThemeContextFingerprint)
            ?? ""
        lensRefs = try container.decodeIfPresent([StoryGenerationLensReference].self, forKey: .lensRefs)
            ?? container.decodeIfPresent([StoryGenerationLensReference].self, forKey: .legacyThemeRefs)
            ?? []
        generationOrigin = try container.decodeIfPresent(StoryGenerationOrigin.self, forKey: .generationOrigin) ?? .manual
        goalCast = try container.decodeIfPresent([SceneStoryGoalCastMemberSnapshot].self, forKey: .goalCast) ?? []
        mediaAnalysisFingerprint = try container.decodeIfPresent(String.self, forKey: .mediaAnalysisFingerprint) ?? ""
        selectedMediaIds = try container.decodeIfPresent([String].self, forKey: .selectedMediaIds) ?? []
        outputContextFingerprint = try container.decodeIfPresent(String.self, forKey: .outputContextFingerprint) ?? ""
        generationControls = try container.decodeIfPresent([String: String].self, forKey: .generationControls) ?? [:]
        priorStorySignatures = try container.decodeIfPresent([StorySignatureDocument].self, forKey: .priorStorySignatures) ?? []
        referenceStories = try container.decodeIfPresent([StoryMemoryReference].self, forKey: .referenceStories) ?? []
    }
}

extension StoryGenerationSessionDocument {
    private enum SessionCodingKeys: String, CodingKey {
        case schemaVersion
        case generationSessionId
        case projectId
        case goalFingerprint
        case lensContextFingerprint
        case lensRefs
        case generationOrigin
        case legacyThemeContextFingerprint = "themeContextFingerprint"
        case legacyThemeRefs = "themeRefs"
        case mode
        case requestedStoryCount
        case requestedStartingDepth
        case differenceMode
        case groundingMode
        case priorStorySignatureIds
        case sourceSetIds
        case resultStoryRefs
        case creativeContext
        case slots
        case startedAt
        case completedAt
        case status
        case warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: SessionCodingKeys.self)
        self.init()
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        generationSessionId = try container.decodeIfPresent(String.self, forKey: .generationSessionId) ?? generationSessionId
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        goalFingerprint = try container.decodeIfPresent(String.self, forKey: .goalFingerprint) ?? ""
        lensContextFingerprint = try container.decodeIfPresent(String.self, forKey: .lensContextFingerprint)
            ?? container.decodeIfPresent(String.self, forKey: .legacyThemeContextFingerprint)
            ?? ""
        lensRefs = try container.decodeIfPresent([StoryGenerationLensReference].self, forKey: .lensRefs)
            ?? container.decodeIfPresent([StoryGenerationLensReference].self, forKey: .legacyThemeRefs)
            ?? []
        let decodedGenerationOrigin = try container.decodeIfPresent(StoryGenerationOrigin.self, forKey: .generationOrigin)
        mode = try container.decodeIfPresent(StoryGenerationMode.self, forKey: .mode) ?? .avoidOverlap
        requestedStoryCount = try container.decodeIfPresent(Int.self, forKey: .requestedStoryCount) ?? SceneStoryGenerationSizing.defaultStoryBatchCount
        requestedStartingDepth = try container.decodeIfPresent(StoryStartingDepth.self, forKey: .requestedStartingDepth) ?? .fourSceneArc
        differenceMode = try container.decodeIfPresent(StoryDifferenceMode.self, forKey: .differenceMode) ?? .distinct
        groundingMode = try container.decodeIfPresent(StoryGroundingMode.self, forKey: .groundingMode) ?? .balanced
        priorStorySignatureIds = try container.decodeIfPresent([String].self, forKey: .priorStorySignatureIds) ?? []
        sourceSetIds = try container.decodeIfPresent([String].self, forKey: .sourceSetIds) ?? []
        resultStoryRefs = try container.decodeIfPresent([String].self, forKey: .resultStoryRefs) ?? []
        creativeContext = try container.decodeIfPresent(StoryGenerationCreativeContextSnapshot.self, forKey: .creativeContext) ?? StoryGenerationCreativeContextSnapshot()
        generationOrigin = decodedGenerationOrigin ?? creativeContext.generationOrigin
        slots = try container.decodeIfPresent([StoryGenerationResultSlot].self, forKey: .slots) ?? []
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt) ?? startedAt
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "queued"
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

extension ProjectStoryLibraryEntry {
    private enum LibraryEntryCodingKeys: String, CodingKey {
        case libraryEntryId
        case storySuggestionId
        case projectStoryId
        case sourceSceneStorySetId
        case sourceStoryId
        case generationSessionId
        case parentProjectStoryId
        case editorialState
        case productionState
        case title
        case lensIds
        case legacyThemeIds = "themeIds"
        case currentVersionId
        case storySignatureId
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: LibraryEntryCodingKeys.self)
        self.init()
        libraryEntryId = try container.decodeIfPresent(String.self, forKey: .libraryEntryId) ?? libraryEntryId
        storySuggestionId = try container.decodeIfPresent(String.self, forKey: .storySuggestionId) ?? ""
        projectStoryId = try container.decodeIfPresent(String.self, forKey: .projectStoryId) ?? ""
        sourceSceneStorySetId = try container.decodeIfPresent(String.self, forKey: .sourceSceneStorySetId) ?? ""
        sourceStoryId = try container.decodeIfPresent(String.self, forKey: .sourceStoryId) ?? ""
        generationSessionId = try container.decodeIfPresent(String.self, forKey: .generationSessionId) ?? ""
        parentProjectStoryId = try container.decodeIfPresent(String.self, forKey: .parentProjectStoryId) ?? ""
        editorialState = try container.decodeIfPresent(ProjectStoryEditorialState.self, forKey: .editorialState) ?? .suggestion
        productionState = try container.decodeIfPresent(ProjectStoryProductionState.self, forKey: .productionState) ?? .notStarted
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        lensIds = try container.decodeIfPresent([String].self, forKey: .lensIds)
            ?? container.decodeIfPresent([String].self, forKey: .legacyThemeIds)
            ?? []
        currentVersionId = try container.decodeIfPresent(String.self, forKey: .currentVersionId) ?? ""
        storySignatureId = try container.decodeIfPresent(String.self, forKey: .storySignatureId) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? createdAt
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? updatedAt
    }
}

struct SceneStory: Codable, Hashable, Identifiable, Sendable {
    var storyId: String
    var id: String { storyId }
    var order: Int
    var title: String
    var premise: String
    var meaningThesis: String
    var tone: String
    var visualWorld: String
    var emotionalArc: StoryEmotionalArc
    var storyBlueprint: StoryBlueprint
    var reasoningSummary: StoryReasoningSummary
    var meaningEdgesUsed: [SceneStoryMeaningEdgeRef]
    var meaningRelationSequence: [SceneStoryMeaningRelationMove]
    var compassFingerprint: String
    var inventedElements: [String]
    var concerns: [String]
    var scenes: [SceneStoryScene]

    init(
        storyId: String = "",
        order: Int = 0,
        title: String = "",
        premise: String = "",
        meaningThesis: String = "",
        tone: String = "",
        visualWorld: String = "",
        emotionalArc: StoryEmotionalArc = StoryEmotionalArc(),
        storyBlueprint: StoryBlueprint = StoryBlueprint(),
        reasoningSummary: StoryReasoningSummary = StoryReasoningSummary(),
        meaningEdgesUsed: [SceneStoryMeaningEdgeRef] = [],
        meaningRelationSequence: [SceneStoryMeaningRelationMove] = [],
        compassFingerprint: String = "",
        inventedElements: [String] = [],
        concerns: [String] = [],
        scenes: [SceneStoryScene] = []
    ) {
        self.storyId = storyId
        self.order = order
        self.title = title
        self.premise = premise
        self.meaningThesis = meaningThesis
        self.tone = tone
        self.visualWorld = visualWorld
        self.emotionalArc = emotionalArc
        self.storyBlueprint = storyBlueprint
        self.reasoningSummary = reasoningSummary
        self.meaningEdgesUsed = meaningEdgesUsed
        self.meaningRelationSequence = meaningRelationSequence
        self.compassFingerprint = compassFingerprint
        self.inventedElements = inventedElements
        self.concerns = concerns
        self.scenes = scenes
    }

    static func empty() -> SceneStory {
        SceneStory()
    }

    enum CodingKeys: String, CodingKey {
        case storyId
        case order
        case title
        case premise
        case meaningThesis
        case tone
        case visualWorld
        case emotionalArc
        case storyBlueprint
        case reasoningSummary
        case meaningEdgesUsed
        case meaningRelationSequence
        case compassFingerprint
        case inventedElements
        case concerns
        case scenes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storyId = try container.decodeIfPresent(String.self, forKey: .storyId) ?? ""
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        premise = try container.decodeIfPresent(String.self, forKey: .premise) ?? ""
        meaningThesis = try container.decodeIfPresent(String.self, forKey: .meaningThesis) ?? ""
        tone = try container.decodeIfPresent(String.self, forKey: .tone) ?? ""
        visualWorld = try container.decodeIfPresent(String.self, forKey: .visualWorld) ?? ""
        emotionalArc = try container.decodeIfPresent(StoryEmotionalArc.self, forKey: .emotionalArc) ?? StoryEmotionalArc()
        storyBlueprint = try container.decodeIfPresent(StoryBlueprint.self, forKey: .storyBlueprint) ?? StoryBlueprint()
        reasoningSummary = try container.decodeIfPresent(StoryReasoningSummary.self, forKey: .reasoningSummary) ?? StoryReasoningSummary()
        meaningEdgesUsed = try container.decodeIfPresent([SceneStoryMeaningEdgeRef].self, forKey: .meaningEdgesUsed) ?? []
        meaningRelationSequence = try container.decodeIfPresent([SceneStoryMeaningRelationMove].self, forKey: .meaningRelationSequence) ?? []
        compassFingerprint = try container.decodeIfPresent(String.self, forKey: .compassFingerprint) ?? ""
        inventedElements = try container.decodeIfPresent([String].self, forKey: .inventedElements) ?? []
        concerns = try container.decodeIfPresent([String].self, forKey: .concerns) ?? []
        scenes = try container.decodeIfPresent([SceneStoryScene].self, forKey: .scenes) ?? []
    }

    func normalized() -> SceneStory {
        var value = self
        value.storyId = value.storyId.trimmed
        value.title = value.title.trimmed
        value.premise = value.premise.trimmed
        value.meaningThesis = value.meaningThesis.trimmed
        value.tone = value.tone.trimmed
        value.visualWorld = value.visualWorld.trimmed
        value.emotionalArc = value.emotionalArc.normalized()
        value.storyBlueprint = value.storyBlueprint.normalized()
        value.reasoningSummary = value.reasoningSummary.normalized()
        value.meaningRelationSequence = value.meaningRelationSequence.map { $0.normalized() }
        value.compassFingerprint = value.compassFingerprint.trimmed
        if value.compassFingerprint.isEmpty, !value.emotionalArc.isEmpty {
            value.compassFingerprint = "compass_\(stableHash(value.emotionalArc, length: 16))"
        }
        value.inventedElements = uniqueNonEmpty(value.inventedElements)
        value.concerns = uniqueNonEmpty(value.concerns)
        value.scenes = value.scenes
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.sceneId < rhs.sceneId
                }
                return lhs.order < rhs.order
            }
            .enumerated()
            .map { index, scene in
                var normalized = scene.normalized()
                if normalized.order <= 0 {
                    normalized.order = index + 1
                }
                if normalized.sceneId.isEmpty {
                    normalized.sceneId = String(format: "scene_%03d", normalized.order)
                }
                return normalized
            }
        return value
    }
}

struct SceneStoryMeaningEdgeRef: Codable, Hashable, Sendable {
    var selectedSlug: String
    var direction: String
    var relationType: String
    var neighborSlug: String
    var naturalLanguage: String

    init(
        selectedSlug: String = "",
        direction: String = "",
        relationType: String = "",
        neighborSlug: String = "",
        naturalLanguage: String = ""
    ) {
        self.selectedSlug = selectedSlug
        self.direction = direction
        self.relationType = relationType
        self.neighborSlug = neighborSlug
        self.naturalLanguage = naturalLanguage
    }

    enum CodingKeys: String, CodingKey {
        case selectedSlug
        case direction
        case relationType
        case neighborSlug
        case naturalLanguage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedSlug = try container.decodeIfPresent(String.self, forKey: .selectedSlug) ?? ""
        direction = try container.decodeIfPresent(String.self, forKey: .direction) ?? ""
        relationType = try container.decodeIfPresent(String.self, forKey: .relationType) ?? ""
        neighborSlug = try container.decodeIfPresent(String.self, forKey: .neighborSlug) ?? ""
        naturalLanguage = try container.decodeIfPresent(String.self, forKey: .naturalLanguage) ?? ""
    }
}

struct SceneStoryMeaningRelationMove: Codable, Hashable, Sendable {
    var relationType: String
    var selectedSlug: String
    var neighborSlug: String
    var storyStage: String
    var dramaticOperation: String
    var sceneId: String
    var beatId: String
    var naturalLanguage: String

    init(
        relationType: String = "",
        selectedSlug: String = "",
        neighborSlug: String = "",
        storyStage: String = "",
        dramaticOperation: String = "",
        sceneId: String = "",
        beatId: String = "",
        naturalLanguage: String = ""
    ) {
        self.relationType = relationType
        self.selectedSlug = selectedSlug
        self.neighborSlug = neighborSlug
        self.storyStage = storyStage
        self.dramaticOperation = dramaticOperation
        self.sceneId = sceneId
        self.beatId = beatId
        self.naturalLanguage = naturalLanguage
    }

    enum CodingKeys: String, CodingKey {
        case relationType
        case selectedSlug
        case neighborSlug
        case storyRole
        case storyStage
        case dramaticOperation
        case sceneId
        case beatId
        case naturalLanguage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relationType = try container.decodeIfPresent(String.self, forKey: .relationType) ?? ""
        selectedSlug = try container.decodeIfPresent(String.self, forKey: .selectedSlug) ?? ""
        neighborSlug = try container.decodeIfPresent(String.self, forKey: .neighborSlug) ?? ""
        storyStage = try container.decodeIfPresent(String.self, forKey: .storyStage)
            ?? container.decodeIfPresent(String.self, forKey: .storyRole)
            ?? ""
        dramaticOperation = try container.decodeIfPresent(String.self, forKey: .dramaticOperation) ?? ""
        sceneId = try container.decodeIfPresent(String.self, forKey: .sceneId) ?? ""
        beatId = try container.decodeIfPresent(String.self, forKey: .beatId) ?? ""
        naturalLanguage = try container.decodeIfPresent(String.self, forKey: .naturalLanguage) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(relationType, forKey: .relationType)
        try container.encode(selectedSlug, forKey: .selectedSlug)
        try container.encode(neighborSlug, forKey: .neighborSlug)
        try container.encode(storyStage, forKey: .storyStage)
        try container.encode(dramaticOperation, forKey: .dramaticOperation)
        try container.encode(sceneId, forKey: .sceneId)
        try container.encode(beatId, forKey: .beatId)
        try container.encode(naturalLanguage, forKey: .naturalLanguage)
    }

    func normalized() -> SceneStoryMeaningRelationMove {
        SceneStoryMeaningRelationMove(
            relationType: relationType.trimmed,
            selectedSlug: selectedSlug.trimmed,
            neighborSlug: neighborSlug.trimmed,
            storyStage: storyStage.trimmed,
            dramaticOperation: dramaticOperation.trimmed,
            sceneId: sceneId.trimmed,
            beatId: beatId.trimmed,
            naturalLanguage: naturalLanguage.trimmed
        )
    }
}

struct SceneStoryScene: Codable, Hashable, Identifiable, Sendable {
    var sceneId: String
    var id: String { sceneId }
    var order: Int
    var title: String
    var sceneFunction: String
    var sceneDescription: String
    var meaningFocus: String
    var emotionalArc: SceneEmotionalArc
    var primaryMeaningMove: String
    var locked: Bool
    var sourceMediaRefs: [SceneStoryMediaRef]
    var supportStatus: String
    var concerns: [String]
    var sceneBeats: [SceneStoryBeat]

    enum CodingKeys: String, CodingKey {
        case sceneId
        case order
        case title
        case sceneFunction
        case sceneDescription
        case meaningFocus
        case emotionalArc
        case primaryMeaningMove
        case locked
        case sourceMediaRefs
        case supportStatus
        case concerns
        case sceneBeats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sceneId = try container.decodeIfPresent(String.self, forKey: .sceneId) ?? ""
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        sceneFunction = try container.decodeIfPresent(String.self, forKey: .sceneFunction) ?? ""
        sceneDescription = try container.decodeIfPresent(String.self, forKey: .sceneDescription) ?? ""
        meaningFocus = try container.decodeIfPresent(String.self, forKey: .meaningFocus) ?? ""
        emotionalArc = try container.decodeIfPresent(SceneEmotionalArc.self, forKey: .emotionalArc) ?? SceneEmotionalArc()
        primaryMeaningMove = try container.decodeIfPresent(String.self, forKey: .primaryMeaningMove) ?? ""
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        sourceMediaRefs = try container.decodeIfPresent([SceneStoryMediaRef].self, forKey: .sourceMediaRefs) ?? []
        supportStatus = try container.decodeIfPresent(String.self, forKey: .supportStatus) ?? ""
        concerns = try container.decodeIfPresent([String].self, forKey: .concerns) ?? []
        sceneBeats = try container.decodeIfPresent([SceneStoryBeat].self, forKey: .sceneBeats) ?? []
    }

    func normalized() -> SceneStoryScene {
        var value = self
        value.sceneId = value.sceneId.trimmed
        value.title = value.title.trimmed
        value.sceneFunction = value.sceneFunction.trimmed
        value.sceneDescription = value.sceneDescription.trimmed
        value.meaningFocus = value.meaningFocus.trimmed
        value.emotionalArc = value.emotionalArc.normalized()
        value.primaryMeaningMove = value.primaryMeaningMove.trimmed
        value.sourceMediaRefs = value.sourceMediaRefs.map { $0.normalized() }
        value.supportStatus = value.supportStatus.trimmed
        value.concerns = uniqueNonEmpty(value.concerns)
        value.sceneBeats = value.sceneBeats
            .sorted { lhs, rhs in
                if lhs.order == rhs.order {
                    return lhs.beatId < rhs.beatId
                }
                return lhs.order < rhs.order
            }
            .enumerated()
            .map { index, beat in
                var normalized = beat.normalized()
                if normalized.order <= 0 {
                    normalized.order = index + 1
                }
                if normalized.beatId.isEmpty {
                    normalized.beatId = String(format: "beat_%03d", normalized.order)
                }
                return normalized
            }
        return value
    }
}

struct SceneStoryMediaRef: Codable, Hashable, Sendable {
    var mediaId: String
    var frameId: String
    var role: String
    var rationale: String

    init(mediaId: String = "", frameId: String = "", role: String = "", rationale: String = "") {
        self.mediaId = mediaId
        self.frameId = frameId
        self.role = role
        self.rationale = rationale
    }

    enum CodingKeys: String, CodingKey {
        case mediaId
        case frameId
        case role
        case rationale
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaId = try container.decodeIfPresent(String.self, forKey: .mediaId) ?? ""
        frameId = try container.decodeIfPresent(String.self, forKey: .frameId) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        rationale = try container.decodeIfPresent(String.self, forKey: .rationale) ?? ""
    }

    func normalized() -> SceneStoryMediaRef {
        SceneStoryMediaRef(
            mediaId: mediaId.trimmed,
            frameId: frameId.trimmed,
            role: role.trimmed,
            rationale: rationale.trimmed
        )
    }
}

struct SceneBeatEntityRef: Codable, Hashable, Sendable {
    var entityId: String = ""
    var referenceSetId: String = ""
    var role: String = ""
    var displayLabel: String = ""
    var appearanceInvariants: [String] = []
    var forbiddenTransformations: [String] = []
}

struct SceneBeatWorldStateDelta: Codable, Hashable, Sendable {
    var entityId: String = ""
    var propertyPath: String = ""
    var from: CodableValue = .null
    var to: CodableValue = .null
    var source: String = ""
}

struct SceneProductionConstraint: Codable, Hashable, Sendable {
    var rule: String = ""
    var strength: String = "soft"
    var priority: Int = 50
    var scope: String = "shot"
    var source: String = "generated"
    var failureAction: String = "review"
}

struct SceneAcceptanceCriterion: Codable, Hashable, Sendable {
    var criterion: String = ""
    var severity: String = "advisory"
    var method: String = "human_review"
    var repairAction: String = ""
}

struct SceneBeatEvent: Codable, Hashable, Sendable {
    var eventId: String = ""
    var startValue: Int = 0
    var durationValue: Int = 24
    var rateNum: Int = 24
    var rateDen: Int = 1
    var actorEntityId: String = ""
    var objectEntityId: String = ""
    var action: String = ""
    var dependsOn: [String] = []
    var attentionTrack: String = ""
    var holdDurationValue: Int = 0
    var easing: String = ""
}

struct SceneEditorialShotContract: Codable, Hashable, Sendable {
    var shotId: String = ""
    var order: Int = 1
    var durationValue: Int = 120
    var rateNum: Int = 24
    var rateDen: Int = 1
    var continuityMode: String = ""
    var eventIds: [String] = []
    var camera: [String: CodableValue] = [:]
    var lighting: [String: CodableValue] = [:]
    var audio: [String: CodableValue] = [:]
    var performance: [String: CodableValue] = [:]
    var spatialBlocking: [String: CodableValue] = [:]
    var fieldPolicies: [String: CodableValue] = [:]
    var generationPolicy: [String: CodableValue] = [:]
    var constraints: [SceneProductionConstraint] = []
    var acceptanceCriteria: [SceneAcceptanceCriterion] = []
}

struct SceneBeatProductionContract: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.scene_beat_production_contract.v0.1"

    var schemaVersion: String = Self.schemaVersion
    var durationValue: Int = 120
    var rateNum: Int = 24
    var rateDen: Int = 1
    var creativeLatitude: Double = 0.5
    var continuityMode: String = ""
    var entityRefs: [SceneBeatEntityRef] = []
    var worldStateDelta: [SceneBeatWorldStateDelta] = []
    var events: [SceneBeatEvent] = []
    var editorialShots: [SceneEditorialShotContract] = []
    var constraints: [SceneProductionConstraint] = []
    var generationPolicy: [String: CodableValue] = [:]
}

struct SceneStoryBeat: Codable, Hashable, Identifiable, Sendable {
    var beatId: String
    var id: String { beatId }
    var order: Int
    var beatDescription: String
    var shotType: String
    var camera: String
    var action: String
    var subjects: [String]
    var setting: String
    var emotionalTurn: BeatEmotionalTurn
    var meaningProof: String
    var supportStatus: String
    var evidenceBasis: String
    var locked: Bool
    var dialogue: [SceneStoryDialogueLine]
    var majorStateChanges: [String]
    var motion: String
    var lighting: String
    var composition: String
    var continuityIn: String
    var continuityOut: String
    var promptSeed: String
    var promptIntent: String
    var negativeConstraints: [String]
    var compassFingerprint: String
    var productionContract: SceneBeatProductionContract?
    var entityRefs: [SceneBeatEntityRef]
    var worldStateDelta: [SceneBeatWorldStateDelta]
    var editorialShots: [SceneEditorialShotContract]
    var acceptanceCriteria: [SceneAcceptanceCriterion]

    enum CodingKeys: String, CodingKey {
        case beatId
        case order
        case beatDescription
        case shotType
        case camera
        case action
        case subjects
        case setting
        case emotionalTurn
        case meaningProof
        case supportStatus
        case evidenceBasis
        case locked
        case dialogue
        case majorStateChanges
        case motion
        case lighting
        case composition
        case continuityIn
        case continuityOut
        case promptSeed
        case promptIntent
        case negativeConstraints
        case compassFingerprint
        case productionContract
        case entityRefs
        case worldStateDelta
        case editorialShots
        case acceptanceCriteria
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beatId = try container.decodeIfPresent(String.self, forKey: .beatId) ?? ""
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        beatDescription = try container.decodeIfPresent(String.self, forKey: .beatDescription) ?? ""
        shotType = try container.decodeIfPresent(String.self, forKey: .shotType) ?? ""
        camera = try container.decodeIfPresent(String.self, forKey: .camera) ?? ""
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
        subjects = try container.decodeIfPresent([String].self, forKey: .subjects) ?? []
        setting = try container.decodeIfPresent(String.self, forKey: .setting) ?? ""
        emotionalTurn = try container.decodeIfPresent(BeatEmotionalTurn.self, forKey: .emotionalTurn) ?? BeatEmotionalTurn()
        meaningProof = try container.decodeIfPresent(String.self, forKey: .meaningProof) ?? ""
        supportStatus = try container.decodeIfPresent(String.self, forKey: .supportStatus) ?? ""
        evidenceBasis = try container.decodeIfPresent(String.self, forKey: .evidenceBasis) ?? ""
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        dialogue = try container.decodeIfPresent([SceneStoryDialogueLine].self, forKey: .dialogue) ?? []
        majorStateChanges = try container.decodeIfPresent([String].self, forKey: .majorStateChanges) ?? []
        motion = try container.decodeIfPresent(String.self, forKey: .motion) ?? ""
        lighting = try container.decodeIfPresent(String.self, forKey: .lighting) ?? ""
        composition = try container.decodeIfPresent(String.self, forKey: .composition) ?? ""
        continuityIn = try container.decodeIfPresent(String.self, forKey: .continuityIn) ?? ""
        continuityOut = try container.decodeIfPresent(String.self, forKey: .continuityOut) ?? ""
        promptSeed = try container.decodeIfPresent(String.self, forKey: .promptSeed) ?? ""
        promptIntent = try container.decodeIfPresent(String.self, forKey: .promptIntent) ?? promptSeed
        negativeConstraints = try container.decodeIfPresent([String].self, forKey: .negativeConstraints) ?? []
        compassFingerprint = try container.decodeIfPresent(String.self, forKey: .compassFingerprint) ?? ""
        productionContract = try container.decodeIfPresent(SceneBeatProductionContract.self, forKey: .productionContract)
        entityRefs = try container.decodeIfPresent([SceneBeatEntityRef].self, forKey: .entityRefs) ?? []
        worldStateDelta = try container.decodeIfPresent([SceneBeatWorldStateDelta].self, forKey: .worldStateDelta) ?? []
        editorialShots = try container.decodeIfPresent([SceneEditorialShotContract].self, forKey: .editorialShots) ?? []
        acceptanceCriteria = try container.decodeIfPresent([SceneAcceptanceCriterion].self, forKey: .acceptanceCriteria) ?? []
    }

    func normalized() -> SceneStoryBeat {
        var value = self
        value.beatId = value.beatId.trimmed
        value.beatDescription = value.beatDescription.trimmed
        value.shotType = value.shotType.trimmed
        value.camera = value.camera.trimmed
        value.action = value.action.trimmed
        value.subjects = uniqueNonEmpty(value.subjects)
        value.setting = value.setting.trimmed
        value.emotionalTurn = value.emotionalTurn.normalized()
        value.meaningProof = value.meaningProof.trimmed
        value.supportStatus = value.supportStatus.trimmed
        value.evidenceBasis = value.evidenceBasis.trimmed
        value.dialogue = value.dialogue.map { $0.normalized() }
        value.majorStateChanges = uniqueNonEmpty(value.majorStateChanges)
        value.motion = value.motion.trimmed
        value.lighting = value.lighting.trimmed
        value.composition = value.composition.trimmed
        value.continuityIn = value.continuityIn.trimmed
        value.continuityOut = value.continuityOut.trimmed
        value.promptSeed = value.promptSeed.trimmed
        value.promptIntent = value.promptIntent.trimmed.isEmpty ? value.promptSeed : value.promptIntent.trimmed
        value.negativeConstraints = uniqueNonEmpty(value.negativeConstraints)
        value.compassFingerprint = value.compassFingerprint.trimmed
        if value.compassFingerprint.isEmpty, !value.emotionalTurn.isEmpty {
            value.compassFingerprint = "compass_\(stableHash(value.emotionalTurn, length: 16))"
        }
        return value
    }
}

struct SceneStoryDialogueLine: Codable, Hashable, Sendable {
    var speaker: String
    var line: String
    var delivery: String
    var provenance: String

    init(speaker: String = "", line: String = "", delivery: String = "", provenance: String = "generated_plain") {
        self.speaker = speaker
        self.line = line
        self.delivery = delivery
        self.provenance = provenance
    }

    enum CodingKeys: String, CodingKey {
        case speaker
        case line
        case delivery
        case provenance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        speaker = try container.decodeIfPresent(String.self, forKey: .speaker) ?? ""
        line = try container.decodeIfPresent(String.self, forKey: .line) ?? ""
        delivery = try container.decodeIfPresent(String.self, forKey: .delivery) ?? ""
        provenance = try container.decodeIfPresent(String.self, forKey: .provenance) ?? "generated_plain"
    }

    func normalized() -> SceneStoryDialogueLine {
        SceneStoryDialogueLine(
            speaker: speaker.trimmed,
            line: line.trimmed,
            delivery: delivery.trimmed,
            provenance: provenance.trimmed.isEmpty ? "generated_plain" : provenance.trimmed
        )
    }
}

struct SceneStoryOperatorFeedback: Codable, Hashable, Sendable {
    var severity: String
    var subject: String
    var message: String
    var recommendation: String

    init(severity: String = "", subject: String = "", message: String = "", recommendation: String = "") {
        self.severity = severity
        self.subject = subject
        self.message = message
        self.recommendation = recommendation
    }

    enum CodingKeys: String, CodingKey {
        case severity
        case subject
        case message
        case recommendation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decodeIfPresent(String.self, forKey: .severity) ?? ""
        subject = try container.decodeIfPresent(String.self, forKey: .subject) ?? ""
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        recommendation = try container.decodeIfPresent(String.self, forKey: .recommendation) ?? ""
    }

    func normalized() -> SceneStoryOperatorFeedback {
        SceneStoryOperatorFeedback(
            severity: severity.trimmed,
            subject: subject.trimmed,
            message: message.trimmed,
            recommendation: recommendation.trimmed
        )
    }
}

extension VideoChainDocument {
    static func draft(
        projectId: String,
        sceneStorySet: SceneStorySetDocument,
        story: SceneStory,
        preset: VideoChainPreset = .cinematicProof,
        providerSelection: VideoProviderSelection = .bestAvailable,
        modelSelection: VideoModelSelection = .auto,
        createdAt: String = DateFormats.now()
    ) -> VideoChainDocument {
        let normalizedStory = story.normalized()
        let sourceArtifactId = "\(sceneStorySet.sceneStorySetId):\(normalizedStory.storyId)"
        let selectedProvider = resolvedProvider(
            requested: providerSelection,
            outputProfile: preset.outputProfile,
            durationSeconds: preset.durationSeconds,
            segmentsHaveTargetFrames: false
        )
        let selectedModel = VideoModelSelection.resolved(requested: modelSelection, provider: selectedProvider)
        let chainId = "chain_\(shortHash("\(projectId):scene_story:\(sourceArtifactId):\(preset.rawValue):\(createdAt)", length: 16))"
        let segments = normalizedStory.scenes.map { scene in
            sceneStorySegment(
                chainId: chainId,
                story: normalizedStory,
                scene: scene,
                preset: preset
            )
        }
        return VideoChainDocument(
            chainId: chainId,
            projectId: projectId,
            title: "\(normalizedStory.title.isEmpty ? "SceneStory" : normalizedStory.title) \(preset.label)",
            sourceArtifactType: .sceneStory,
            sourceArtifactId: sourceArtifactId,
            sourceProjectStoryId: "",
            sourceBeatBoardId: "",
            sourceBoardFingerprint: stableHash(sceneStorySet),
            preset: preset,
            providerSelection: providerSelection,
            selectedProviderId: selectedProvider,
            modelSelection: modelSelection,
            selectedModelId: selectedModel,
            continuityMode: selectedProvider.continuityMode,
            outputProfile: preset.outputProfile,
            targetTotalSeconds: segments.reduce(0) { $0 + $1.durationSeconds },
            status: segments.isEmpty ? .draft : .planned,
            segments: segments,
            seams: sceneStorySeams(segments: segments),
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    static func draft(
        projectId: String,
        sceneStorySet: SceneStorySetDocument,
        story: SceneStory,
        arrangement: SceneSoundArrangement,
        preset: VideoChainPreset = .cinematicProof,
        providerSelection: VideoProviderSelection = .bestAvailable,
        modelSelection: VideoModelSelection = .auto,
        createdAt: String = DateFormats.now()
    ) -> VideoChainDocument {
        let normalizedStory = story.normalized()
        let sortedCards = arrangement.sortedCards
        let sourceArtifactId = "\(sceneStorySet.sceneStorySetId):\(normalizedStory.storyId):\(arrangement.arrangementId)"
        let providerDuration = sortedCards.first
            .map { max(1, Int($0.durationSeconds.rounded())) }
            ?? preset.durationSeconds
        let selectedProvider = resolvedProvider(
            requested: providerSelection,
            outputProfile: preset.outputProfile,
            durationSeconds: providerDuration,
            segmentsHaveTargetFrames: false
        )
        let selectedModel = VideoModelSelection.resolved(requested: modelSelection, provider: selectedProvider)
        let chainId = "chain_\(shortHash("\(projectId):scene_sound_arrangement:\(sourceArtifactId):\(preset.rawValue):\(createdAt)", length: 16))"
        let scenesById = Dictionary(uniqueKeysWithValues: normalizedStory.scenes.map { ($0.sceneId, $0) })
        let segments = sortedCards.enumerated().compactMap { index, card -> VideoSegmentDocument? in
            guard let scene = scenesById[card.sceneId] else { return nil }
            return sceneStoryArrangementSegment(
                chainId: chainId,
                story: normalizedStory,
                scene: scene,
                card: card,
                order: index + 1,
                preset: preset
            )
        }
        return VideoChainDocument(
            chainId: chainId,
            projectId: projectId,
            title: "\(normalizedStory.title.isEmpty ? "Sound-timed SceneStory" : normalizedStory.title) \(preset.label)",
            sourceArtifactType: .sceneStory,
            sourceArtifactId: sourceArtifactId,
            sourceProjectStoryId: "",
            sourceBeatBoardId: "",
            sourceBoardFingerprint: stableHash(["scene_story_set": sceneStorySet.sceneStorySetId, "arrangement": arrangement.arrangementId]),
            preset: preset,
            providerSelection: providerSelection,
            selectedProviderId: selectedProvider,
            modelSelection: modelSelection,
            selectedModelId: selectedModel,
            continuityMode: selectedProvider.continuityMode,
            outputProfile: preset.outputProfile,
            targetTotalSeconds: segments.reduce(0) { $0 + $1.durationSeconds },
            status: segments.isEmpty ? .draft : .planned,
            segments: segments,
            seams: sceneStorySeams(segments: segments),
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private static func sceneStorySegment(
        chainId: String,
        story: SceneStory,
        scene: SceneStoryScene,
        preset: VideoChainPreset
    ) -> VideoSegmentDocument {
        let beatIds = scene.sceneBeats.map(\.beatId)
        let isFirst = scene.order <= 1
        return VideoSegmentDocument(
            segmentId: "seg_\(String(format: "%02d", max(scene.order, 1)))_\(shortHash("\(chainId):\(scene.sceneId):\(beatIds.joined(separator: ","))", length: 8))",
            order: max(scene.order, 1),
            sourceBeatIds: beatIds,
            title: "Scene \(max(scene.order, 1)): \(scene.title.isEmpty ? story.title : scene.title)",
            durationSeconds: preset.durationSeconds,
            prompt: sceneStoryPrompt(story: story, scene: scene, outputProfile: preset.outputProfile),
            negativePrompt: sceneStoryNegativePrompt(scene: scene),
            motionDirective: sceneStoryMotionDirective(scene: scene),
            startFrameSource: isFirst
                ? VideoFrameSourceDocument(type: .none, note: "Select a project image, source-media still, or attach a start frame.")
                : VideoFrameSourceDocument(type: .previousSegmentEnd, note: "Will use previous clip actual final frame."),
            status: isFirst ? .needsStartFrame : .draft,
            fitPolicy: preset.outputProfile.fitPolicy,
            sourceFingerprint: stableHash(scene)
        )
    }

    private static func sceneStoryArrangementSegment(
        chainId: String,
        story: SceneStory,
        scene: SceneStoryScene,
        card: SceneSoundArrangementCard,
        order: Int,
        preset: VideoChainPreset
    ) -> VideoSegmentDocument {
        let beatIds = card.beatIds.isEmpty ? scene.sceneBeats.map(\.beatId) : card.beatIds
        let isFirst = order <= 1
        let duration = max(1, Int(card.durationSeconds.rounded()))
        return VideoSegmentDocument(
            segmentId: "seg_\(String(format: "%02d", order))_\(shortHash("\(chainId):\(card.cardId):\(scene.sceneId):\(beatIds.joined(separator: ","))", length: 8))",
            order: order,
            sourceBeatIds: beatIds,
            title: "Scene \(order): \(card.title.isEmpty ? scene.title : card.title)",
            durationSeconds: duration,
            prompt: sceneStoryArrangementPrompt(story: story, scene: scene, card: card, outputProfile: preset.outputProfile),
            negativePrompt: sceneStoryNegativePrompt(scene: scene),
            motionDirective: sceneStoryMotionDirective(scene: scene),
            startFrameSource: isFirst
                ? VideoFrameSourceDocument(type: .none, note: "Select a project image, source-media still, or attach a start frame.")
                : VideoFrameSourceDocument(type: .previousSegmentEnd, note: "Will use previous clip actual final frame."),
            status: isFirst ? .needsStartFrame : .draft,
            fitPolicy: preset.outputProfile.fitPolicy,
            sourceFingerprint: stableHash(["scene": stableHash(scene), "card": stableHash(card)])
        )
    }

    private static func sceneStorySeams(segments: [VideoSegmentDocument]) -> [VideoSeamDocument] {
        zip(segments, segments.dropFirst()).map { previous, next in
            VideoSeamDocument(
                seamId: "seam_\(previous.segmentId)_\(next.segmentId)",
                fromSegmentId: previous.segmentId,
                toSegmentId: next.segmentId
            )
        }
    }

    private static func sceneStoryPrompt(story: SceneStory, scene: SceneStoryScene, outputProfile: VideoOutputProfile) -> String {
        let beats = scene.sceneBeats.map { beat in
            [
                "Beat \(beat.order): \(beat.beatDescription)",
                "Shot: \(beat.shotType)",
                sceneStoryBeatCompassSummary(beat),
                beat.meaningProof.isEmpty ? "" : "Meaning proof: \(beat.meaningProof)",
                beat.emotionalTurn.observableEvidence.isEmpty ? "" : "Observable evidence: \(beat.emotionalTurn.observableEvidence.joined(separator: "; "))",
                beat.emotionalTurn.performanceDirection.isEmpty ? "" : "Performance direction: \(beat.emotionalTurn.performanceDirection.joined(separator: "; "))",
                "Camera: \(beat.camera)",
                "Action: \(beat.action)",
                "Motion: \(beat.motion)",
                "Lighting: \(beat.lighting)",
                "Composition: \(beat.composition)",
                "Prompt seed: \(beat.promptSeed)",
                beat.dialogue.isEmpty ? "" : "Dialogue: " + beat.dialogue.map { "\($0.speaker): \($0.line) (\($0.delivery))" }.joined(separator: " / ")
            ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        }
        return [
            "Create an \(outputProfile.aspectRatio.rawValue) video segment from a SceneStory.",
            "Story: \(story.title)",
            "Premise: \(story.premise)",
            "Meaning thesis: \(story.meaningThesis)",
            "Tone: \(story.tone)",
            sceneStoryStoryCompassSummary(story),
            "Visual world: \(story.visualWorld)",
            "Scene: \(scene.title)",
            scene.sceneDescription,
            "Meaning focus: \(scene.meaningFocus)",
            scene.primaryMeaningMove.isEmpty ? "" : "Primary meaning move: \(scene.primaryMeaningMove)",
            sceneStorySceneCompassSummary(scene),
            sceneStoryRelationSequenceSummary(story),
            beats.joined(separator: "\n\n"),
            "Preserve continuity into the next segment. Do not invent unsupported factual claims about real people, places, businesses, or events."
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private static func sceneStoryArrangementPrompt(
        story: SceneStory,
        scene: SceneStoryScene,
        card: SceneSoundArrangementCard,
        outputProfile: VideoOutputProfile
    ) -> String {
        [
            sceneStoryPrompt(story: story, scene: scene, outputProfile: outputProfile),
            "Sound timing: start \(soundSceneTimecode(card.startSeconds)), duration \(String(format: "%.1f", card.durationSeconds)) seconds.",
            "Timed setup: \(card.setup)",
            "Timed turn: \(card.turn)",
            "Timed resolution: \(card.resolution)",
            "Timing notes: \(card.notes)",
            "Match the emotional shape of this sound range without requiring literal audio visualization."
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private static func sceneStoryMotionDirective(scene: SceneStoryScene) -> String {
        let motions = scene.sceneBeats.map(\.motion).filter { !$0.isEmpty }.prefix(2)
        if !motions.isEmpty {
            return motions.joined(separator: "; ")
        }
        let cameras = scene.sceneBeats.map(\.camera).filter { !$0.isEmpty }.prefix(2)
        if !cameras.isEmpty {
            return cameras.joined(separator: "; ")
        }
        let actions = scene.sceneBeats.map(\.action).filter { !$0.isEmpty }.prefix(2)
        if !actions.isEmpty {
            return actions.joined(separator: "; ")
        }
        return "cinematic readable motion with clear continuity"
    }

    private static func sceneStoryNegativePrompt(scene: SceneStoryScene) -> String {
        let constraints = scene.sceneBeats.flatMap(\.negativeConstraints)
            + scene.sceneBeats.flatMap(\.emotionalTurn.avoidEmotionalCliches)
        return constraints.uniqued().joined(separator: "\n")
    }

    private static func sceneStoryStoryCompassSummary(_ story: SceneStory) -> String {
        let arc = story.emotionalArc.normalized()
        guard !arc.isEmpty else { return "" }
        let shape = arc.arcShape.isEmpty ? "" : " (\(arc.arcShape))"
        return "Story compass: \(compassPointSummary(arc.start)) -> \(compassPointSummary(arc.end))\(shape)"
    }

    private static func sceneStorySceneCompassSummary(_ scene: SceneStoryScene) -> String {
        let arc = scene.emotionalArc.normalized()
        guard !arc.isEmpty else { return "" }
        let inheritance = arc.inheritedFromStory ? "inherited from Story" : "local override"
        return "Scene compass: \(compassPointSummary(arc.entry)) -> \(compassPointSummary(arc.exit)); \(arc.primaryTurn); \(inheritance)"
    }

    private static func sceneStoryBeatCompassSummary(_ beat: SceneStoryBeat) -> String {
        let turn = beat.emotionalTurn.normalized()
        guard !turn.isEmpty else { return "" }
        return "Beat compass: \(compassPointSummary(turn.entry)) -> \(compassPointSummary(turn.exit)); \(turn.turnDescription)"
    }

    private static func sceneStoryRelationSequenceSummary(_ story: SceneStory) -> String {
        let moves = story.meaningRelationSequence
            .map { move -> String in
                [
                    move.storyStage,
                    move.dramaticOperation,
                    move.relationType,
                    move.selectedSlug.isEmpty ? "" : "\(move.selectedSlug)->\(move.neighborSlug)",
                    move.naturalLanguage
                ]
                .map(\.trimmed)
                .filter { !$0.isEmpty }
                .joined(separator: " / ")
            }
            .filter { !$0.isEmpty }
            .prefix(6)
        guard !moves.isEmpty else { return "" }
        return "Meaning relation sequence: \(moves.joined(separator: " | "))"
    }

    private static func compassPointSummary(_ point: EmotionalCompassPoint) -> String {
        let normalized = point.normalized()
        let label = normalized.labelSummary.isEmpty ? "unspecified" : normalized.labelSummary
        return "\(label) [v \(String(format: "%.2f", normalized.valence)), a \(String(format: "%.2f", normalized.activation)), agency \(String(format: "%.2f", normalized.agency))]"
    }
}
