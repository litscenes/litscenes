import Foundation

enum StoryArtifactFreshness: String, Codable, Hashable {
    case fresh
    case stale
    case missing
    case legacy
}

struct StoryInputFingerprint: Codable, Hashable {
    var goalVersionId: String = ""
    var goalUpdatedAt: String = ""
    var aestheticBriefUpdatedAt: String = ""
    var chosenRecipeId: String = ""
    var chosenRecipeVersion: String = ""
    var storyWorldHash: String = ""
    var sourceContextHash: String = ""
    var enabledMediaHash: String = ""
    var mediaObservationsHash: String = ""
    var storySetupHash: String = ""
    var storyPatternIndexVersion: String = ""

    static func empty(patternIndexVersion: String = StoryPatternIndexDocument.defaultVersion) -> StoryInputFingerprint {
        StoryInputFingerprint(storyPatternIndexVersion: patternIndexVersion)
    }

    static func make(
        goal: ProjectGoalDocument,
        aestheticBrief: ProjectAestheticBriefDocument,
        storyWorld: StoryWorldDocument,
        sourceContextRecords: [SourceContextRecord],
        enabledMedia: [MediaItemRecord],
        mediaObservationsById: [String: ImageObservationResult],
        storySetup: StorySetupDocument,
        storyPatternIndexVersion: String
    ) -> StoryInputFingerprint {
        let activeVersion = goal.activeVersion
        let recipe = aestheticBrief.chosenDirection
        let mediaFingerprint = enabledMedia
            .sorted { $0.mediaId < $1.mediaId }
            .map {
                StoryEnabledMediaFingerprint(
                    mediaId: $0.mediaId,
                    kind: $0.kind.rawValue,
                    relativePath: $0.relativePath,
                    byteCount: $0.byteCount,
                    modifiedAt: $0.modifiedAt,
                    width: $0.width,
                    height: $0.height,
                    sourceMediaId: $0.sourceMediaId ?? "",
                    sourceTimestampSeconds: $0.sourceTimestampSeconds ?? 0
                )
            }
        let observationFingerprint = mediaObservationsById
            .filter { id, _ in enabledMedia.contains { $0.mediaId == id } }
            .map { id, observation in
                StoryMediaObservationFingerprint(
                    mediaId: id,
                    createdAt: observation.createdAt,
                    model: observation.model,
                    promptVersion: observation.promptVersion,
                    visionInputSha256: observation.visionInputSha256,
                    summaryHash: stableHash([
                        observation.plainCaption,
                        observation.literalDescription,
                        observation.objects.joined(separator: "|"),
                        observation.activities.joined(separator: "|"),
                        observation.setting,
                        observation.possibleMeanings.joined(separator: "|")
                    ])
                )
            }
            .sorted { $0.mediaId < $1.mediaId }

        return StoryInputFingerprint(
            goalVersionId: activeVersion?.versionId ?? "",
            goalUpdatedAt: goal.updatedAt,
            aestheticBriefUpdatedAt: aestheticBrief.updatedAt,
            chosenRecipeId: recipe?.recipeId ?? "",
            chosenRecipeVersion: recipe?.recipeVersion ?? "",
            storyWorldHash: stableHash(storyWorld),
            sourceContextHash: stableHash(sourceContextRecords.sorted { $0.sourceId < $1.sourceId }),
            enabledMediaHash: stableHash(mediaFingerprint),
            mediaObservationsHash: stableHash(observationFingerprint),
            storySetupHash: storySetup.semanticFingerprintHash,
            storyPatternIndexVersion: storyPatternIndexVersion
        )
    }

    var stableId: String {
        stableHash(self)
    }

    func matchesExceptStorySetupHash(_ other: StoryInputFingerprint) -> Bool {
        goalVersionId == other.goalVersionId
            && goalUpdatedAt == other.goalUpdatedAt
            && aestheticBriefUpdatedAt == other.aestheticBriefUpdatedAt
            && chosenRecipeId == other.chosenRecipeId
            && chosenRecipeVersion == other.chosenRecipeVersion
            && storyWorldHash == other.storyWorldHash
            && sourceContextHash == other.sourceContextHash
            && enabledMediaHash == other.enabledMediaHash
            && mediaObservationsHash == other.mediaObservationsHash
            && storyPatternIndexVersion == other.storyPatternIndexVersion
    }
}

struct StoryInputFingerprintV2: Codable, Hashable {
    static let schemaVersion = "litscenes.story_input_fingerprint.v0.2"

    var schemaVersion: String = Self.schemaVersion
    var goalVersionId: String = ""
    var goalUpdatedAt: String = ""
    var readyLensSetHash: String = ""
    var lensRowSnapshotHash: String = ""
    var storyWorldHash: String = ""
    var sourceContextHash: String = ""
    var enabledMediaHash: String = ""
    var mediaObservationsHash: String = ""
    var storySetupHash: String = ""
    var storyPatternIndexVersion: String = ""

    static func empty(patternIndexVersion: String = StoryPatternIndexDocument.defaultVersion) -> StoryInputFingerprintV2 {
        StoryInputFingerprintV2(storyPatternIndexVersion: patternIndexVersion)
    }

    static func make(
        goal: ProjectGoalDocumentV2,
        lensSet: ProjectLensSetDocument,
        storyWorld: StoryWorldDocument,
        sourceContextRecords: [SourceContextRecord],
        enabledMedia: [MediaItemRecord],
        mediaObservationsById: [String: ImageObservationResult],
        storySetup: StorySetupDocument,
        outputContext: ProjectOutputContext,
        storyPatternIndexVersion: String
    ) -> StoryInputFingerprintV2 {
        let activeVersion = goal.activeVersion
        let snapshots = lensRowSnapshots(from: lensSet)
        let mediaFingerprint = enabledMedia
            .sorted { $0.mediaId < $1.mediaId }
            .map {
                StoryEnabledMediaFingerprint(
                    mediaId: $0.mediaId,
                    kind: $0.kind.rawValue,
                    relativePath: $0.relativePath,
                    byteCount: $0.byteCount,
                    modifiedAt: $0.modifiedAt,
                    width: $0.width,
                    height: $0.height,
                    sourceMediaId: $0.sourceMediaId ?? "",
                    sourceTimestampSeconds: $0.sourceTimestampSeconds ?? 0
                )
            }
        let observationFingerprint = mediaObservationsById
            .filter { id, _ in enabledMedia.contains { $0.mediaId == id } }
            .map { id, observation in
                StoryMediaObservationFingerprint(
                    mediaId: id,
                    createdAt: observation.createdAt,
                    model: observation.model,
                    promptVersion: observation.promptVersion,
                    visionInputSha256: observation.visionInputSha256,
                    summaryHash: stableHash([
                        observation.plainCaption,
                        observation.literalDescription,
                        observation.objects.joined(separator: "|"),
                        observation.activities.joined(separator: "|"),
                        observation.setting,
                        observation.possibleMeanings.joined(separator: "|")
                    ])
                )
            }
            .sorted { $0.mediaId < $1.mediaId }
        let setupFingerprint = StorySetupOutputFingerprint(
            storySetupHash: storySetup.semanticFingerprintHash,
            outputContextHash: stableHash(outputContext)
        )

        return StoryInputFingerprintV2(
            goalVersionId: activeVersion?.versionId ?? "",
            goalUpdatedAt: goal.updatedAt,
            readyLensSetHash: computeReadyLensSetHash(lensSet),
            lensRowSnapshotHash: computeLensRowSnapshotHash(snapshots),
            storyWorldHash: stableHash(storyWorld),
            sourceContextHash: stableHash(sourceContextRecords.sorted { $0.sourceId < $1.sourceId }),
            enabledMediaHash: stableHash(mediaFingerprint),
            mediaObservationsHash: stableHash(observationFingerprint),
            storySetupHash: stableHash(setupFingerprint),
            storyPatternIndexVersion: storyPatternIndexVersion
        )
    }

    var stableId: String {
        stableHash(self)
    }

    func matchesExceptStorySetupHash(_ other: StoryInputFingerprintV2) -> Bool {
        goalVersionId == other.goalVersionId
            && goalUpdatedAt == other.goalUpdatedAt
            && readyLensSetHash == other.readyLensSetHash
            && lensRowSnapshotHash == other.lensRowSnapshotHash
            && storyWorldHash == other.storyWorldHash
            && sourceContextHash == other.sourceContextHash
            && enabledMediaHash == other.enabledMediaHash
            && mediaObservationsHash == other.mediaObservationsHash
            && storyPatternIndexVersion == other.storyPatternIndexVersion
    }
}

private struct StorySetupOutputFingerprint: Codable, Hashable {
    var storySetupHash: String
    var outputContextHash: String
}

private struct StoryEnabledMediaFingerprint: Codable, Hashable {
    var mediaId: String
    var kind: String
    var relativePath: String
    var byteCount: Int64
    var modifiedAt: String
    var width: Int
    var height: Int
    var sourceMediaId: String
    var sourceTimestampSeconds: Double
}

private struct StoryMediaObservationFingerprint: Codable, Hashable {
    var mediaId: String
    var createdAt: String
    var model: String
    var promptVersion: String
    var visionInputSha256: String
    var summaryHash: String
}

func stableHash<T: Encodable>(_ value: T, length: Int = 20) -> String {
    guard let data = try? JSONCoding.encoder.encode(value) else {
        return shortHash(String(describing: value), length: length)
    }
    return String(sha256Hex(data).prefix(length))
}

enum StoryOutputType: String, Codable, CaseIterable, Identifiable {
    case cinematicShort = "cinematic_short"
    case trailerTeaser = "trailer_teaser"
    case socialSequence = "social_sequence"
    case productServiceStory = "product_service_story"
    case campaignConcept = "campaign_concept"
    case experimentalSequence = "experimental_sequence"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cinematicShort: "Cinematic short"
        case .trailerTeaser: "Trailer / teaser"
        case .socialSequence: "Social sequence"
        case .productServiceStory: "Product / service story"
        case .campaignConcept: "Campaign concept"
        case .experimentalSequence: "Experimental sequence"
        }
    }
}

enum StoryInventionLevel: String, Codable, CaseIterable, Identifiable {
    case lightInvention = "light_invention"
    case inventFreely = "invent_freely"
    case wildMythology = "wild_mythology"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lightInvention: "Light invention"
        case .inventFreely: "Invent freely"
        case .wildMythology: "Wild mythology"
        }
    }
}

enum StoryCommercialPressure: String, Codable, CaseIterable, Identifiable {
    case none
    case creatorFriendly = "creator_friendly"
    case productService = "product_service"
    case explicitCTA = "explicit_cta"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .creatorFriendly: "Low / creator-friendly"
        case .productService: "Product/service framing"
        case .explicitCTA: "Explicit CTA"
        }
    }

    var scalar: Double {
        switch self {
        case .none: 0
        case .creatorFriendly: 0.4
        case .productService: 0.65
        case .explicitCTA: 0.9
        }
    }
}

enum StoryPOV: String, Codable, CaseIterable, Identifiable {
    case auto
    case witnessObserver = "witness_observer"
    case homeowner
    case investigator
    case narrator
    case creaturePOV = "creature_pov"
    case productBrandVoice = "product_brand_voice"
    case evidenceOnly = "evidence_only"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .witnessObserver: "Witness / observer"
        case .homeowner: "Homeowner"
        case .investigator: "Investigator"
        case .narrator: "Narrator"
        case .creaturePOV: "Creature POV"
        case .productBrandVoice: "Product / brand voice"
        case .evidenceOnly: "No protagonist, only evidence"
        }
    }
}

enum StoryEnginePreference: String, Codable, CaseIterable, Identifiable {
    case auto
    case evidenceEscalates = "evidence_escalates"
    case domesticBreach = "domestic_breach"
    case investigation
    case publicWarning = "public_warning"
    case advertisementTurnsStrange = "advertisement_turns_strange"
    case ritualMythicReveal = "ritual_mythic_reveal"
    case beforeAfterTransformation = "before_after_transformation"
    case productPromiseBecomesSurreal = "product_promise_becomes_surreal"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .evidenceEscalates: "Evidence escalates"
        case .domesticBreach: "Domestic breach"
        case .investigation: "Investigation"
        case .publicWarning: "Public warning"
        case .advertisementTurnsStrange: "Advertisement turns strange"
        case .ritualMythicReveal: "Ritual / mythic reveal"
        case .beforeAfterTransformation: "Before / after transformation"
        case .productPromiseBecomesSurreal: "Product promise becomes surreal"
        }
    }
}

enum StoryEndingStyle: String, Codable, CaseIterable, Identifiable {
    case ambiguousFinalImage = "ambiguous_final_image"
    case twistReveal = "twist_reveal"
    case warningEscalation = "warning_escalation"
    case emotionalResolution = "emotional_resolution"
    case ctaOffer = "cta_offer"
    case mythicTransformation = "mythic_transformation"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ambiguousFinalImage: "Ambiguous final image"
        case .twistReveal: "Twist reveal"
        case .warningEscalation: "Warning / escalation"
        case .emotionalResolution: "Emotional resolution"
        case .ctaOffer: "CTA / offer"
        case .mythicTransformation: "Mythic transformation"
        }
    }
}

struct StoryCommercialDetails: Codable, Hashable {
    var productService: String = ""
    var audience: String = ""
    var offerOrPromise: String = ""
    var cta: String = ""
    var doNotSay: String = ""
    var brandTone: String = ""
}

struct StorySetupDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.story_setup.v0.1"
    var projectId: String
    var outputType: StoryOutputType = .cinematicShort
    var inventionLevel: StoryInventionLevel = .inventFreely
    var commercialPressure: StoryCommercialPressure = .creatorFriendly
    var pov: StoryPOV = .auto
    var storyEngine: StoryEnginePreference = .auto
    var endingStyle: StoryEndingStyle = .ambiguousFinalImage
    var customPovOption: ProjectGoalStorySetupOption = .empty()
    var customStoryEngineOption: ProjectGoalStorySetupOption = .empty()
    var customEndingOption: ProjectGoalStorySetupOption = .empty()
    var mustInclude: String = ""
    var avoid: String = ""
    var commercialDetails: StoryCommercialDetails = StoryCommercialDetails()
    var updatedAt: String = DateFormats.now()

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case outputType
        case inventionLevel
        case commercialPressure
        case pov
        case storyEngine
        case endingStyle
        case customPovOption
        case customStoryEngineOption
        case customEndingOption
        case mustInclude
        case avoid
        case commercialDetails
        case updatedAt
    }

    init(
        schemaVersion: String = "litscenes.story_setup.v0.1",
        projectId: String,
        outputType: StoryOutputType = .cinematicShort,
        inventionLevel: StoryInventionLevel = .inventFreely,
        commercialPressure: StoryCommercialPressure = .creatorFriendly,
        pov: StoryPOV = .auto,
        storyEngine: StoryEnginePreference = .auto,
        endingStyle: StoryEndingStyle = .ambiguousFinalImage,
        customPovOption: ProjectGoalStorySetupOption = .empty(),
        customStoryEngineOption: ProjectGoalStorySetupOption = .empty(),
        customEndingOption: ProjectGoalStorySetupOption = .empty(),
        mustInclude: String = "",
        avoid: String = "",
        commercialDetails: StoryCommercialDetails = StoryCommercialDetails(),
        updatedAt: String = DateFormats.now()
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.outputType = outputType
        self.inventionLevel = inventionLevel
        self.commercialPressure = commercialPressure
        self.pov = pov
        self.storyEngine = storyEngine
        self.endingStyle = endingStyle
        self.customPovOption = customPovOption
        self.customStoryEngineOption = customStoryEngineOption
        self.customEndingOption = customEndingOption
        self.mustInclude = mustInclude
        self.avoid = avoid
        self.commercialDetails = commercialDetails
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "litscenes.story_setup.v0.1"
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        outputType = try container.decodeIfPresent(StoryOutputType.self, forKey: .outputType) ?? .cinematicShort
        inventionLevel = try container.decodeIfPresent(StoryInventionLevel.self, forKey: .inventionLevel) ?? .inventFreely
        commercialPressure = try container.decodeIfPresent(StoryCommercialPressure.self, forKey: .commercialPressure) ?? .creatorFriendly
        pov = try container.decodeIfPresent(StoryPOV.self, forKey: .pov) ?? .auto
        storyEngine = try container.decodeIfPresent(StoryEnginePreference.self, forKey: .storyEngine) ?? .auto
        endingStyle = try container.decodeIfPresent(StoryEndingStyle.self, forKey: .endingStyle) ?? .ambiguousFinalImage
        customPovOption = try container.decodeIfPresent(ProjectGoalStorySetupOption.self, forKey: .customPovOption) ?? .empty()
        customStoryEngineOption = try container.decodeIfPresent(ProjectGoalStorySetupOption.self, forKey: .customStoryEngineOption) ?? .empty()
        customEndingOption = try container.decodeIfPresent(ProjectGoalStorySetupOption.self, forKey: .customEndingOption) ?? .empty()
        mustInclude = try container.decodeIfPresent(String.self, forKey: .mustInclude) ?? ""
        avoid = try container.decodeIfPresent(String.self, forKey: .avoid) ?? ""
        commercialDetails = try container.decodeIfPresent(StoryCommercialDetails.self, forKey: .commercialDetails) ?? StoryCommercialDetails()
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
    }

    static func empty(projectId: String = "") -> StorySetupDocument {
        StorySetupDocument(projectId: projectId)
    }

    static func decode(from data: Data) throws -> StorySetupDocument {
        try JSONCoding.decoder.decode(StorySetupDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }

    var needsCommercialDetails: Bool {
        outputType == .productServiceStory
            || outputType == .campaignConcept
            || commercialPressure == .productService
            || commercialPressure == .explicitCTA
    }

    var effectivePOVLabel: String {
        effectiveSetupLabel(customPovOption, fallback: pov.label)
    }

    var effectiveStoryEngineLabel: String {
        effectiveSetupLabel(customStoryEngineOption, fallback: storyEngine.label)
    }

    var effectiveEndingStyleLabel: String {
        effectiveSetupLabel(customEndingOption, fallback: endingStyle.label)
    }

    var semanticFingerprintHash: String {
        stableHash(StorySetupSemanticFingerprint(
            outputType: outputType.rawValue,
            inventionLevel: inventionLevel.rawValue,
            commercialPressure: commercialPressure.rawValue,
            pov: pov.rawValue,
            storyEngine: storyEngine.rawValue,
            endingStyle: endingStyle.rawValue,
            customPov: StorySetupSemanticOption(customPovOption),
            customStoryEngine: StorySetupSemanticOption(customStoryEngineOption),
            customEnding: StorySetupSemanticOption(customEndingOption),
            mustInclude: semanticStorySetupText(mustInclude),
            avoid: semanticStorySetupText(avoid),
            commercialDetails: StorySetupSemanticCommercialDetails(commercialDetails)
        ))
    }

    private func effectiveSetupLabel(_ option: ProjectGoalStorySetupOption, fallback: String) -> String {
        let label = option.displayLabel
        return label.isEmpty ? fallback : label
    }
}

private struct StorySetupSemanticFingerprint: Codable, Hashable {
    var outputType: String
    var inventionLevel: String
    var commercialPressure: String
    var pov: String
    var storyEngine: String
    var endingStyle: String
    var customPov: StorySetupSemanticOption
    var customStoryEngine: StorySetupSemanticOption
    var customEnding: StorySetupSemanticOption
    var mustInclude: String
    var avoid: String
    var commercialDetails: StorySetupSemanticCommercialDetails
}

private struct StorySetupSemanticOption: Codable, Hashable {
    var optionId: String
    var label: String
    var promptValue: String

    init(_ option: ProjectGoalStorySetupOption) {
        optionId = semanticStorySetupText(option.optionId)
        label = semanticStorySetupText(option.displayLabel)
        promptValue = semanticStorySetupText(option.effectivePromptValue)
    }
}

private struct StorySetupSemanticCommercialDetails: Codable, Hashable {
    var productService: String
    var audience: String
    var offerOrPromise: String
    var cta: String
    var doNotSay: String
    var brandTone: String

    init(_ details: StoryCommercialDetails) {
        productService = semanticStorySetupText(details.productService)
        audience = semanticStorySetupText(details.audience)
        offerOrPromise = semanticStorySetupText(details.offerOrPromise)
        cta = semanticStorySetupText(details.cta)
        doNotSay = semanticStorySetupText(details.doNotSay)
        brandTone = semanticStorySetupText(details.brandTone)
    }
}

private func semanticStorySetupText(_ value: String) -> String {
    value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

struct StorySignalSet: Codable, Hashable {
    var schemaVersion: String = "litscenes.story_signal_set.v0.2"
    var projectId: String
    var signalSetId: String = "story_signals"
    var scope: String = ProjectStoryScope.enabledMedia.rawValue
    var summary: String = ""
    var friendlyChips: [String] = []
    var motifs: [String] = []
    var tensions: [String] = []
    var moods: [String] = []
    var sceneForces: [String] = []
    var constraints: [String] = []
    var implications: [String] = []
    var evidenceMediaIds: [String] = []
    var confidence0To1: Double = 0
    var inputFingerprint: StoryInputFingerprint = .empty()
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()
    var artifactStatus: StoryArtifactFreshness = .missing
    var legacySourcePath: String = ""
    var legacyRawScope: String = ""

    static func empty(projectId: String = "") -> StorySignalSet {
        StorySignalSet(projectId: projectId)
    }

    static func fromLegacy(
        _ graph: ProjectArchiveMeaningGraph,
        rawScope: String,
        projectId: String
    ) -> StorySignalSet {
        StorySignalSet(
            projectId: projectId,
            signalSetId: "legacy_project_archive_meaning",
            scope: rawScope.isEmpty ? graph.scope.rawValue : rawScope,
            summary: graph.summary,
            friendlyChips: Array((graph.motifs + graph.tensions + graph.sceneForces).prefix(8)),
            motifs: graph.motifs,
            tensions: graph.tensions,
            moods: graph.moods,
            sceneForces: graph.sceneForces,
            constraints: graph.constraints,
            implications: graph.implications,
            evidenceMediaIds: graph.evidenceMediaIds,
            confidence0To1: graph.confidence0To1,
            generatedAt: graph.generatedAt,
            updatedAt: graph.updatedAt,
            artifactStatus: .legacy,
            legacySourcePath: "project_archive_meaning.json",
            legacyRawScope: rawScope
        )
    }

    static func decode(from data: Data) throws -> StorySignalSet {
        try JSONCoding.decoder.decode(StorySignalSet.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }

    var hasSignals: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !friendlyChips.isEmpty
            || !motifs.isEmpty
            || !tensions.isEmpty
            || !moods.isEmpty
            || !sceneForces.isEmpty
            || !constraints.isEmpty
            || !implications.isEmpty
    }

    func freshness(against current: StoryInputFingerprint) -> StoryArtifactFreshness {
        if artifactStatus == .legacy { return .legacy }
        guard hasSignals else { return .missing }
        return inputFingerprint == current ? .fresh : .stale
    }
}

enum StoryDirectionLane: String, Codable, CaseIterable, Identifiable {
    case recommended
    case bolder
    case commercial
    case wildcard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recommended: "Recommended"
        case .bolder: "Bolder"
        case .commercial: "Commercial / Creator-Friendly"
        case .wildcard: "Wildcard"
        }
    }
}

struct StoryAestheticUse: Codable, Hashable {
    var narrative: String = ""
    var presentation: String = ""
}

struct StoryDirectionScore: Codable, Hashable {
    var goalFit: Double = 0
    var aestheticNarrativeFit: Double = 0
    var aestheticPresentationFit: Double = 0
    var storySetupFit: Double = 0
    var patternSupport: Double = 0
    var specificity: Double = 0
    var promptability: Double = 0
    var novelty: Double = 0
    var laneFit: Double = 0
    var commercialFit: Double = 0
    var tooCommercialPenalty: Double = 0
    var genericSlopPenalty: Double = 0
    var nearDuplicatePenalty: Double = 0
    var finalScore: Double = 0
}

struct StoryDirectionCard: Codable, Hashable, Identifiable {
    var directionId: String
    var id: String { directionId }
    var enabled: Bool = true
    var lane: StoryDirectionLane
    var title: String
    var premise: String
    var storyEngine: String
    var whatHappens: String
    var whyItWorks: String
    var aestheticUse: StoryAestheticUse
    var inventedElements: [String]
    var risk: String
    var threeBeatPreview: [String]
    var meaningMoves: [String]
    var commercialPressure: Double
    var weirdness: Double
    var promptability: Double
    var scoreDebug: StoryDirectionScore
    var validationWarnings: [String] = []
}

extension StoryDirectionCard {
    enum CodingKeys: String, CodingKey {
        case directionId
        case enabled
        case lane
        case title
        case premise
        case storyEngine
        case whatHappens
        case whyItWorks
        case aestheticUse
        case inventedElements
        case risk
        case threeBeatPreview
        case meaningMoves
        case commercialPressure
        case weirdness
        case promptability
        case scoreDebug
        case validationWarnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        directionId = try container.decode(String.self, forKey: .directionId)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        lane = try container.decode(StoryDirectionLane.self, forKey: .lane)
        title = try container.decode(String.self, forKey: .title)
        premise = try container.decode(String.self, forKey: .premise)
        storyEngine = try container.decode(String.self, forKey: .storyEngine)
        whatHappens = try container.decode(String.self, forKey: .whatHappens)
        whyItWorks = try container.decode(String.self, forKey: .whyItWorks)
        aestheticUse = try container.decode(StoryAestheticUse.self, forKey: .aestheticUse)
        inventedElements = try container.decode([String].self, forKey: .inventedElements)
        risk = try container.decode(String.self, forKey: .risk)
        threeBeatPreview = try container.decode([String].self, forKey: .threeBeatPreview)
        meaningMoves = try container.decode([String].self, forKey: .meaningMoves)
        commercialPressure = try container.decode(Double.self, forKey: .commercialPressure)
        weirdness = try container.decode(Double.self, forKey: .weirdness)
        promptability = try container.decode(Double.self, forKey: .promptability)
        scoreDebug = try container.decode(StoryDirectionScore.self, forKey: .scoreDebug)
        validationWarnings = try container.decodeIfPresent([String].self, forKey: .validationWarnings) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(directionId, forKey: .directionId)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(lane, forKey: .lane)
        try container.encode(title, forKey: .title)
        try container.encode(premise, forKey: .premise)
        try container.encode(storyEngine, forKey: .storyEngine)
        try container.encode(whatHappens, forKey: .whatHappens)
        try container.encode(whyItWorks, forKey: .whyItWorks)
        try container.encode(aestheticUse, forKey: .aestheticUse)
        try container.encode(inventedElements, forKey: .inventedElements)
        try container.encode(risk, forKey: .risk)
        try container.encode(threeBeatPreview, forKey: .threeBeatPreview)
        try container.encode(meaningMoves, forKey: .meaningMoves)
        try container.encode(commercialPressure, forKey: .commercialPressure)
        try container.encode(weirdness, forKey: .weirdness)
        try container.encode(promptability, forKey: .promptability)
        try container.encode(scoreDebug, forKey: .scoreDebug)
        try container.encode(validationWarnings, forKey: .validationWarnings)
    }
}

struct StoryDirectionSet: Codable, Hashable {
    var schemaVersion: String = "litscenes.story_direction_set.v0.1"
    var projectId: String
    var directionSetId: String = "story_directions"
    var inputFingerprint: StoryInputFingerprint = .empty()
    var storySetupSnapshot: StorySetupDocument = .empty()
    var candidateDirections: [StoryDirectionCard] = []
    var directions: [StoryDirectionCard] = []
    var selectedDirectionId: String = ""
    var status: String = "draft"
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()
    var generator: String = "openai"
    var model: String = ""
    var responseId: String = ""
    var artifactStatus: StoryArtifactFreshness = .missing

    static func empty(projectId: String = "") -> StoryDirectionSet {
        StoryDirectionSet(projectId: projectId)
    }

    static func decode(from data: Data) throws -> StoryDirectionSet {
        try JSONCoding.decoder.decode(StoryDirectionSet.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }

    var hasDirections: Bool {
        !directions.isEmpty
    }

    var enabledDirections: [StoryDirectionCard] {
        directions.filter(\.enabled)
    }

    var orderedStorylineDirections: [StoryDirectionCard] {
        StoryDirectionSet.storylineDisplayOrder(directions)
    }

    var selectedDirection: StoryDirectionCard? {
        directions.first { $0.directionId == selectedDirectionId } ?? directions.first
    }

    func freshness(against current: StoryInputFingerprint) -> StoryArtifactFreshness {
        guard hasDirections else { return .missing }
        if artifactStatus == .legacy { return .legacy }
        return inputFingerprint == current ? .fresh : .stale
    }

    func freshness(against current: StoryInputFingerprint, currentStorySetup: StorySetupDocument) -> StoryArtifactFreshness {
        guard hasDirections else { return .missing }
        if artifactStatus == .legacy { return .legacy }
        if inputFingerprint == current { return .fresh }
        if inputFingerprint.matchesExceptStorySetupHash(current),
           storySetupSnapshot.semanticFingerprintHash == currentStorySetup.semanticFingerprintHash {
            return .fresh
        }
        return .stale
    }

    static func storylineDisplayOrder(_ directions: [StoryDirectionCard]) -> [StoryDirectionCard] {
        directions.filter(\.enabled) + directions.filter { !$0.enabled }
    }
}

struct StoryDirectionHistoryDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.story_direction_history.v0.1"
    var projectId: String
    var activeDirectionSetId: String = ""
    var directionSets: [StoryDirectionSet] = []
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String = "") -> StoryDirectionHistoryDocument {
        StoryDirectionHistoryDocument(projectId: projectId)
    }

    static func decode(from data: Data) throws -> StoryDirectionHistoryDocument {
        if let history = try? JSONCoding.decoder.decode(StoryDirectionHistoryDocument.self, from: data) {
            return history
        }
        let legacySet = try StoryDirectionSet.decode(from: data)
        return StoryDirectionHistoryDocument(
            projectId: legacySet.projectId,
            activeDirectionSetId: legacySet.directionSetId,
            directionSets: [legacySet],
            updatedAt: legacySet.updatedAt
        )
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }

    var activeSet: StoryDirectionSet {
        directionSets.first { $0.directionSetId == activeDirectionSetId }
            ?? directionSets.sortedByStoryDirectionRecency.first
            ?? StoryDirectionSet.empty(projectId: projectId)
    }

    func appending(_ set: StoryDirectionSet) -> StoryDirectionHistoryDocument {
        var updated = self
        updated.projectId = projectId.isEmpty ? set.projectId : projectId
        updated.activeDirectionSetId = set.directionSetId
        updated.directionSets.removeAll { $0.directionSetId == set.directionSetId }
        updated.directionSets.append(set)
        updated.directionSets = updated.directionSets.sortedByStoryDirectionRecency
        updated.updatedAt = DateFormats.now()
        return updated
    }
}

struct StorylineCreationDraft: Codable, Hashable {
    var storylineTitle: String = ""
    var storylineIntent: String = ""
    var readinessSummary: String = ""
    var openQuestions: [String] = []
    var isReadyToGenerate: Bool = false
    var confidence0To1: Double = 0

    private enum CodingKeys: String, CodingKey {
        case storylineTitle
        case storylineIntent
        case legacyThemeTitle = "themeTitle"
        case legacyThemeIntent = "themeIntent"
        case readinessSummary
        case openQuestions
        case isReadyToGenerate
        case confidence0To1
    }

    static func empty() -> StorylineCreationDraft {
        StorylineCreationDraft()
    }

    var hasContent: Bool {
        !storylineTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !storylineIntent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !readinessSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !openQuestions.isEmpty
    }

    init(
        storylineTitle: String = "",
        storylineIntent: String = "",
        readinessSummary: String = "",
        openQuestions: [String] = [],
        isReadyToGenerate: Bool = false,
        confidence0To1: Double = 0
    ) {
        self.storylineTitle = storylineTitle
        self.storylineIntent = storylineIntent
        self.readinessSummary = readinessSummary
        self.openQuestions = openQuestions
        self.isReadyToGenerate = isReadyToGenerate
        self.confidence0To1 = confidence0To1
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        storylineTitle = try container.decodeIfPresent(String.self, forKey: .storylineTitle)
            ?? container.decodeIfPresent(String.self, forKey: .legacyThemeTitle)
            ?? ""
        storylineIntent = try container.decodeIfPresent(String.self, forKey: .storylineIntent)
            ?? container.decodeIfPresent(String.self, forKey: .legacyThemeIntent)
            ?? ""
        readinessSummary = try container.decodeIfPresent(String.self, forKey: .readinessSummary) ?? ""
        openQuestions = try container.decodeIfPresent([String].self, forKey: .openQuestions) ?? []
        isReadyToGenerate = try container.decodeIfPresent(Bool.self, forKey: .isReadyToGenerate) ?? false
        confidence0To1 = try container.decodeIfPresent(Double.self, forKey: .confidence0To1) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(storylineTitle, forKey: .storylineTitle)
        try container.encode(storylineIntent, forKey: .storylineIntent)
        try container.encode(readinessSummary, forKey: .readinessSummary)
        try container.encode(openQuestions, forKey: .openQuestions)
        try container.encode(isReadyToGenerate, forKey: .isReadyToGenerate)
        try container.encode(confidence0To1, forKey: .confidence0To1)
    }

    func normalized() -> StorylineCreationDraft {
        var value = self
        value.storylineTitle = value.storylineTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        value.storylineIntent = value.storylineIntent.trimmingCharacters(in: .whitespacesAndNewlines)
        value.readinessSummary = value.readinessSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        value.openQuestions = value.openQuestions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .map { $0 }
        value.confidence0To1 = min(max(value.confidence0To1, 0), 1)
        value.isReadyToGenerate = value.isReadyToGenerate
            && !value.storylineIntent.isEmpty
            && value.confidence0To1 >= 0.55
        return value
    }
}

struct StorylineCreationDocument: Codable, Hashable {
    static let schemaVersion = "litscenes.storyline_creation.v0.1"

    var schemaVersion: String = Self.schemaVersion
    var projectId: String
    var messages: [ProjectGoalMessage] = []
    var draftSetup: StorySetupDocument = .empty()
    var draft: StorylineCreationDraft = .empty()
    var status: String = "draft"
    var lastGeneratedDirectionId: String = ""
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String = "", seedSetup: StorySetupDocument = .empty()) -> StorylineCreationDocument {
        var setup = seedSetup
        if setup.projectId.isEmpty {
            setup.projectId = projectId
        }
        return StorylineCreationDocument(projectId: projectId, draftSetup: setup)
    }

    static func decode(from data: Data) throws -> StorylineCreationDocument {
        try JSONCoding.decoder.decode(StorylineCreationDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }

    var isReadyToGenerate: Bool {
        draft.normalized().isReadyToGenerate
    }

    var hasConversation: Bool {
        !messages.isEmpty || draft.hasContent
    }

    mutating func appendMessage(role: ProjectGoalMessageRole, text: String, mediaIds: [String] = [], now: String) {
        messages.append(ProjectGoalMessage(
            messageId: "storyline_msg_\(shortHash("\(projectId):\(role.rawValue):\(now):\(messages.count)", length: 12))",
            role: role,
            text: text,
            mediaIds: mediaIds,
            createdAt: now
        ))
        updatedAt = now
    }

    mutating func applyInterviewDraft(_ nextDraft: StorylineCreationDraft, status nextStatus: String, now: String) {
        draft = nextDraft.normalized()
        status = nextStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "draft" : nextStatus
        updatedAt = now
    }
}

struct StorylineCreationInterviewResponse: Codable, Hashable {
    var schemaVersion: String = "litscenes.storyline_creation_interview_response.v0.1"
    var assistantMessage: String
    var draft: StorylineCreationDraft
    var changeSummary: String

    static func decode(from data: Data) throws -> StorylineCreationInterviewResponse {
        try JSONCoding.decoder.decode(StorylineCreationInterviewResponse.self, from: data)
    }
}

struct StorySingleStorylineResponse: Codable, Hashable {
    var schemaVersion: String = "litscenes.story_single_storyline_response.v0.1"
    var direction: StoryDirectionCard
    var changeSummary: String

    static func decode(from data: Data) throws -> StorySingleStorylineResponse {
        try JSONCoding.decoder.decode(StorySingleStorylineResponse.self, from: data)
    }
}

extension Array where Element == StoryDirectionSet {
    var sortedByStoryDirectionRecency: [StoryDirectionSet] {
        sorted { lhs, rhs in
            let lhsDate = lhs.generatedAt.isEmpty ? lhs.updatedAt : lhs.generatedAt
            let rhsDate = rhs.generatedAt.isEmpty ? rhs.updatedAt : rhs.generatedAt
            if lhsDate == rhsDate {
                return lhs.directionSetId < rhs.directionSetId
            }
            return lhsDate > rhsDate
        }
    }
}

struct StoryGraphRef: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var kind: String
    var source: String
    var confidence: Double
}

struct StoryGenerationBrief: Codable, Hashable {
    var subject: String = ""
    var setting: String = ""
    var action: String = ""
    var visualFocus: String = ""
    var cameraOrFraming: String = ""
    var lighting: String = ""
    var aestheticTreatment: String = ""
    var textOverlay: String = ""
    var negativeConstraints: [String] = []
    var assetTypeHints: [String] = ["image", "video", "audio"]
}

enum StoryMediaAnchorRole: String, Codable, Hashable, CaseIterable, Identifiable {
    case source
    case avoid
    case reference

    var id: String { rawValue }

    var label: String {
        switch self {
        case .source: "Source"
        case .avoid: "Avoid"
        case .reference: "Reference"
        }
    }
}

enum StoryMediaAnchorKind: String, Codable, Hashable, CaseIterable, Identifiable {
    case image
    case videoFrame = "video_frame"

    var id: String { rawValue }
}

struct StoryMediaAnchor: Codable, Hashable, Identifiable {
    var anchorId: String
    var id: String { anchorId }
    var mediaId: String
    var frameId: String = ""
    var timecode: String = ""
    var kind: StoryMediaAnchorKind = .image
    var role: StoryMediaAnchorRole = .source
    var note: String = ""
    var thumbnailPath: String = ""
    var createdBy: String = "user"

    static func anchorId(mediaId: String, role: StoryMediaAnchorRole) -> String {
        "anchor_\(shortHash("\(mediaId):\(role.rawValue)", length: 14))"
    }
}

struct StoryBeatRevision: Codable, Hashable, Identifiable {
    var revisionId: String
    var id: String { revisionId }
    var operation: String
    var beat: StoryBeatBoardBeatSnapshot
    var createdAt: String = DateFormats.now()
}

struct StoryBeatBoardBeatSnapshot: Codable, Hashable {
    var beatId: String
    var order: Int
    var title: String
    var event: String
    var visualMoment: String
    var emotionalTurn: String
    var meaningMove: String
    var storyFunction: String
    var promptReadyLine: String
    var generationBrief: StoryGenerationBrief
    var voiceOrTextOverlay: String
    var sourceMediaIds: [String]
    var avoidMediaIds: [String]
    var referenceMediaIds: [String]
    var mediaAnchors: [StoryMediaAnchor]

    static func fromBeat(_ beat: StoryBeatBoardBeat) -> StoryBeatBoardBeatSnapshot {
        StoryBeatBoardBeatSnapshot(
            beatId: beat.beatId,
            order: beat.order,
            title: beat.title,
            event: beat.event,
            visualMoment: beat.visualMoment,
            emotionalTurn: beat.emotionalTurn,
            meaningMove: beat.meaningMove,
            storyFunction: beat.storyFunction,
            promptReadyLine: beat.promptReadyLine,
            generationBrief: beat.generationBrief,
            voiceOrTextOverlay: beat.voiceOrTextOverlay,
            sourceMediaIds: beat.sourceMediaIds,
            avoidMediaIds: beat.avoidMediaIds,
            referenceMediaIds: beat.referenceMediaIds,
            mediaAnchors: beat.mediaAnchors
        )
    }
}

enum StoryBeatOrigin: String, Codable, CaseIterable, Identifiable {
    case mediaDerived = "media_derived"
    case goalAestheticInvention = "goal_aesthetic_invention"
    case userSpecified = "user_specified"
    case storyPatternIndex = "story_pattern_index"
    case fromSetup = "from_setup"
    case fromAesthetic = "from_aesthetic"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mediaDerived: "Media-derived"
        case .goalAestheticInvention: "Invented"
        case .userSpecified: "User-specified"
        case .storyPatternIndex: "Pattern"
        case .fromSetup: "From setup"
        case .fromAesthetic: "From aesthetic"
        }
    }
}

enum StoryBeatBoardSupportStatus: String, Codable, CaseIterable, Identifiable {
    case mediaDerived = "media_derived"
    case inventedFromGoalAndAesthetic = "invented_from_goal_and_aesthetic"
    case storyPatternSupported = "story_pattern_supported"
    case weak
    case unsupported

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mediaDerived: "Media-derived"
        case .inventedFromGoalAndAesthetic: "Goal + Aesthetic"
        case .storyPatternSupported: "Pattern-supported"
        case .weak: "Weak"
        case .unsupported: "Unsupported"
        }
    }
}

struct StoryBeatBoardBeat: Codable, Hashable, Identifiable {
    var beatId: String
    var id: String { beatId }
    var order: Int
    var locked: Bool = false
    var title: String
    var event: String
    var visualMoment: String
    var emotionalTurn: String
    var meaningMove: String
    var storyFunction: String
    var aestheticNarrativeBinding: [String]
    var aestheticPresentationBinding: [String]
    var promptReadyLine: String
    var generationBrief: StoryGenerationBrief
    var voiceOrTextOverlay: String
    var sourceMediaIds: [String] = []
    var avoidMediaIds: [String] = []
    var referenceMediaIds: [String] = []
    var mediaAnchors: [StoryMediaAnchor] = []
    var inventedElements: [String]
    var risks: [String]
    var supportStatus: StoryBeatBoardSupportStatus
    var origin: StoryBeatOrigin
    var meaningNodeRefs: [StoryGraphRef]
    var beatFunctionRefs: [StoryGraphRef]
    var archetypalSituationRefs: [StoryGraphRef]
    var lensRefs: [StoryGraphRef]
    var lensRowSnapshots: [LensRowSnapshot] = []
    var graphSupportSummary: String
    var validationWarnings: [String] = []
    var manualEditFields: [String] = []
    var isDeleted: Bool = false
    var deletedAt: String = ""
    var revisionHistory: [StoryBeatRevision] = []
}

extension StoryBeatBoardBeat {
    enum CodingKeys: String, CodingKey {
        case beatId
        case order
        case locked
        case title
        case event
        case visualMoment
        case emotionalTurn
        case meaningMove
        case storyFunction
        case aestheticNarrativeBinding
        case aestheticPresentationBinding
        case promptReadyLine
        case generationBrief
        case voiceOrTextOverlay
        case sourceMediaIds
        case avoidMediaIds
        case referenceMediaIds
        case mediaAnchors
        case inventedElements
        case risks
        case supportStatus
        case origin
        case meaningNodeRefs
        case beatFunctionRefs
        case archetypalSituationRefs
        case lensRefs
        case lensRowSnapshots
        case legacyThemeRefs = "themeRefs"
        case legacyThemeRowSnapshots = "themeRowSnapshots"
        case graphSupportSummary
        case validationWarnings
        case manualEditFields
        case isDeleted
        case deletedAt
        case revisionHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beatId = try container.decode(String.self, forKey: .beatId)
        order = try container.decode(Int.self, forKey: .order)
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        title = try container.decode(String.self, forKey: .title)
        event = try container.decode(String.self, forKey: .event)
        visualMoment = try container.decode(String.self, forKey: .visualMoment)
        emotionalTurn = try container.decode(String.self, forKey: .emotionalTurn)
        meaningMove = try container.decode(String.self, forKey: .meaningMove)
        storyFunction = try container.decode(String.self, forKey: .storyFunction)
        aestheticNarrativeBinding = try container.decodeIfPresent([String].self, forKey: .aestheticNarrativeBinding) ?? []
        aestheticPresentationBinding = try container.decodeIfPresent([String].self, forKey: .aestheticPresentationBinding) ?? []
        promptReadyLine = try container.decode(String.self, forKey: .promptReadyLine)
        generationBrief = try container.decodeIfPresent(StoryGenerationBrief.self, forKey: .generationBrief) ?? StoryGenerationBrief()
        voiceOrTextOverlay = try container.decodeIfPresent(String.self, forKey: .voiceOrTextOverlay) ?? ""
        sourceMediaIds = try container.decodeIfPresent([String].self, forKey: .sourceMediaIds) ?? []
        avoidMediaIds = try container.decodeIfPresent([String].self, forKey: .avoidMediaIds) ?? []
        referenceMediaIds = try container.decodeIfPresent([String].self, forKey: .referenceMediaIds) ?? []
        mediaAnchors = try container.decodeIfPresent([StoryMediaAnchor].self, forKey: .mediaAnchors) ?? []
        inventedElements = try container.decodeIfPresent([String].self, forKey: .inventedElements) ?? []
        risks = try container.decodeIfPresent([String].self, forKey: .risks) ?? []
        supportStatus = try container.decodeIfPresent(StoryBeatBoardSupportStatus.self, forKey: .supportStatus) ?? .weak
        origin = try container.decodeIfPresent(StoryBeatOrigin.self, forKey: .origin) ?? .goalAestheticInvention
        meaningNodeRefs = try container.decodeIfPresent([StoryGraphRef].self, forKey: .meaningNodeRefs) ?? []
        beatFunctionRefs = try container.decodeIfPresent([StoryGraphRef].self, forKey: .beatFunctionRefs) ?? []
        archetypalSituationRefs = try container.decodeIfPresent([StoryGraphRef].self, forKey: .archetypalSituationRefs) ?? []
        lensRefs = try container.decodeIfPresent([StoryGraphRef].self, forKey: .lensRefs)
            ?? container.decodeIfPresent([StoryGraphRef].self, forKey: .legacyThemeRefs)
            ?? []
        lensRowSnapshots = try container.decodeIfPresent([LensRowSnapshot].self, forKey: .lensRowSnapshots)
            ?? container.decodeIfPresent([LensRowSnapshot].self, forKey: .legacyThemeRowSnapshots)
            ?? []
        graphSupportSummary = try container.decodeIfPresent(String.self, forKey: .graphSupportSummary) ?? ""
        validationWarnings = try container.decodeIfPresent([String].self, forKey: .validationWarnings) ?? []
        manualEditFields = try container.decodeIfPresent([String].self, forKey: .manualEditFields) ?? []
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt) ?? ""
        revisionHistory = try container.decodeIfPresent([StoryBeatRevision].self, forKey: .revisionHistory) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(beatId, forKey: .beatId)
        try container.encode(order, forKey: .order)
        try container.encode(locked, forKey: .locked)
        try container.encode(title, forKey: .title)
        try container.encode(event, forKey: .event)
        try container.encode(visualMoment, forKey: .visualMoment)
        try container.encode(emotionalTurn, forKey: .emotionalTurn)
        try container.encode(meaningMove, forKey: .meaningMove)
        try container.encode(storyFunction, forKey: .storyFunction)
        try container.encode(aestheticNarrativeBinding, forKey: .aestheticNarrativeBinding)
        try container.encode(aestheticPresentationBinding, forKey: .aestheticPresentationBinding)
        try container.encode(promptReadyLine, forKey: .promptReadyLine)
        try container.encode(generationBrief, forKey: .generationBrief)
        try container.encode(voiceOrTextOverlay, forKey: .voiceOrTextOverlay)
        try container.encode(sourceMediaIds, forKey: .sourceMediaIds)
        try container.encode(avoidMediaIds, forKey: .avoidMediaIds)
        try container.encode(referenceMediaIds, forKey: .referenceMediaIds)
        try container.encode(mediaAnchors, forKey: .mediaAnchors)
        try container.encode(inventedElements, forKey: .inventedElements)
        try container.encode(risks, forKey: .risks)
        try container.encode(supportStatus, forKey: .supportStatus)
        try container.encode(origin, forKey: .origin)
        try container.encode(meaningNodeRefs, forKey: .meaningNodeRefs)
        try container.encode(beatFunctionRefs, forKey: .beatFunctionRefs)
        try container.encode(archetypalSituationRefs, forKey: .archetypalSituationRefs)
        try container.encode(lensRefs, forKey: .lensRefs)
        try container.encode(lensRowSnapshots, forKey: .lensRowSnapshots)
        try container.encode(graphSupportSummary, forKey: .graphSupportSummary)
        try container.encode(validationWarnings, forKey: .validationWarnings)
        try container.encode(manualEditFields, forKey: .manualEditFields)
        try container.encode(isDeleted, forKey: .isDeleted)
        try container.encode(deletedAt, forKey: .deletedAt)
        try container.encode(revisionHistory, forKey: .revisionHistory)
    }
}

struct StoryBeatBoardAestheticStrategy: Codable, Hashable {
    var narrative: String = ""
    var presentation: String = ""
}

enum StoryBeatExpansionMode: String, Codable, Hashable {
    case openExisting
    case generateNewVersion
}

enum StoryBeatOperationPhase: String, Codable, Hashable {
    case idle
    case rewriting
    case splitting
    case replacing
    case regenerating
    case failed
    case cancelled
}

enum StoryBeatMovePlacement: String, Codable, Hashable, CaseIterable, Identifiable {
    case earlier
    case later
    case start
    case end

    var id: String { rawValue }
}

struct StoryBeatOperationState: Codable, Hashable {
    var beatId: String = ""
    var phase: StoryBeatOperationPhase = .idle
    var startedAt: String = ""
    var errorMessage: String = ""

    var isRunning: Bool {
        switch phase {
        case .rewriting, .splitting, .replacing, .regenerating:
            return true
        case .idle, .failed, .cancelled:
            return false
        }
    }
}

struct StoryBeatBoard: Codable, Hashable {
    var schemaVersion: String = "litscenes.story_beat_board.v0.3"
    var projectId: String
    var beatBoardId: String
    var parentDirectionSetId: String
    var parentDirectionId: String
    var primaryDirectionId: String = ""
    var sourceDirectionIds: [String] = []
    var storySetupHash: String
    var readyLensSetHash: String = ""
    var lensRowSnapshots: [LensRowSnapshot] = []
    var aestheticRecipeVersion: String
    var isActiveDraft: Bool = true
    var inputFingerprint: StoryInputFingerprint = .empty()
    var title: String
    var logline: String
    var centralTension: String
    var storyEngine: String
    var format: String
    var targetDuration: String
    var beginningState: String
    var endingState: String
    var aestheticStrategy: StoryBeatBoardAestheticStrategy
    var beats: [StoryBeatBoardBeat]
    var status: String = "draft"
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()
    var generator: String = "openai"
    var model: String = ""
    var responseId: String = ""
    var artifactStatus: StoryArtifactFreshness = .missing
    var validationWarnings: [String] = []

    static func empty(projectId: String = "") -> StoryBeatBoard {
        StoryBeatBoard(
            projectId: projectId,
            beatBoardId: "",
            parentDirectionSetId: "",
            parentDirectionId: "",
            storySetupHash: "",
            aestheticRecipeVersion: "",
            title: "",
            logline: "",
            centralTension: "",
            storyEngine: "",
            format: StoryOutputType.cinematicShort.rawValue,
            targetDuration: "60-90 seconds",
            beginningState: "",
            endingState: "",
            aestheticStrategy: StoryBeatBoardAestheticStrategy(),
            beats: []
        )
    }

    static func decode(from data: Data) throws -> StoryBeatBoard {
        try JSONCoding.decoder.decode(StoryBeatBoard.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }

    var hasBeats: Bool {
        !beats.isEmpty
    }

    func freshness(against current: StoryInputFingerprint) -> StoryArtifactFreshness {
        guard hasBeats else { return .missing }
        if artifactStatus == .legacy { return .legacy }
        return inputFingerprint == current ? .fresh : .stale
    }
}

extension StoryBeatBoard {
    var visibleBeats: [StoryBeatBoardBeat] {
        beats
            .filter { !$0.isDeleted }
            .sorted { $0.order < $1.order }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case beatBoardId
        case parentDirectionSetId
        case parentDirectionId
        case primaryDirectionId
        case sourceDirectionIds
        case storySetupHash
        case readyLensSetHash
        case lensRowSnapshots
        case legacyThemeRowSnapshots = "themeRowSnapshots"
        case aestheticRecipeVersion
        case isActiveDraft
        case inputFingerprint
        case title
        case logline
        case centralTension
        case storyEngine
        case format
        case targetDuration
        case beginningState
        case endingState
        case aestheticStrategy
        case beats
        case status
        case generatedAt
        case updatedAt
        case generator
        case model
        case responseId
        case artifactStatus
        case validationWarnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "litscenes.story_beat_board.v0.1"
        projectId = try container.decode(String.self, forKey: .projectId)
        beatBoardId = try container.decode(String.self, forKey: .beatBoardId)
        parentDirectionSetId = try container.decode(String.self, forKey: .parentDirectionSetId)
        parentDirectionId = try container.decode(String.self, forKey: .parentDirectionId)
        primaryDirectionId = try container.decodeIfPresent(String.self, forKey: .primaryDirectionId) ?? parentDirectionId
        sourceDirectionIds = try container.decodeIfPresent([String].self, forKey: .sourceDirectionIds) ?? [parentDirectionId].filter { !$0.isEmpty }
        storySetupHash = try container.decode(String.self, forKey: .storySetupHash)
        readyLensSetHash = try container.decodeIfPresent(String.self, forKey: .readyLensSetHash) ?? ""
        lensRowSnapshots = try container.decodeIfPresent([LensRowSnapshot].self, forKey: .lensRowSnapshots)
            ?? container.decodeIfPresent([LensRowSnapshot].self, forKey: .legacyThemeRowSnapshots)
            ?? []
        aestheticRecipeVersion = try container.decode(String.self, forKey: .aestheticRecipeVersion)
        isActiveDraft = try container.decodeIfPresent(Bool.self, forKey: .isActiveDraft) ?? true
        inputFingerprint = try container.decodeIfPresent(StoryInputFingerprint.self, forKey: .inputFingerprint) ?? .empty()
        title = try container.decode(String.self, forKey: .title)
        logline = try container.decode(String.self, forKey: .logline)
        centralTension = try container.decode(String.self, forKey: .centralTension)
        storyEngine = try container.decode(String.self, forKey: .storyEngine)
        format = try container.decode(String.self, forKey: .format)
        targetDuration = try container.decode(String.self, forKey: .targetDuration)
        beginningState = try container.decode(String.self, forKey: .beginningState)
        endingState = try container.decode(String.self, forKey: .endingState)
        aestheticStrategy = try container.decode(StoryBeatBoardAestheticStrategy.self, forKey: .aestheticStrategy)
        beats = try container.decode([StoryBeatBoardBeat].self, forKey: .beats)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "draft"
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
        generator = try container.decodeIfPresent(String.self, forKey: .generator) ?? "openai"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        responseId = try container.decodeIfPresent(String.self, forKey: .responseId) ?? ""
        artifactStatus = try container.decodeIfPresent(StoryArtifactFreshness.self, forKey: .artifactStatus) ?? .missing
        validationWarnings = try container.decodeIfPresent([String].self, forKey: .validationWarnings) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("litscenes.story_beat_board.v0.3", forKey: .schemaVersion)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(beatBoardId, forKey: .beatBoardId)
        try container.encode(parentDirectionSetId, forKey: .parentDirectionSetId)
        try container.encode(parentDirectionId, forKey: .parentDirectionId)
        let encodedPrimaryDirectionId = primaryDirectionId.isEmpty ? parentDirectionId : primaryDirectionId
        let encodedSourceDirectionIds = sourceDirectionIds.isEmpty && !encodedPrimaryDirectionId.isEmpty
            ? [encodedPrimaryDirectionId]
            : sourceDirectionIds
        try container.encode(encodedPrimaryDirectionId, forKey: .primaryDirectionId)
        try container.encode(encodedSourceDirectionIds, forKey: .sourceDirectionIds)
        try container.encode(storySetupHash, forKey: .storySetupHash)
        try container.encode(readyLensSetHash, forKey: .readyLensSetHash)
        try container.encode(lensRowSnapshots, forKey: .lensRowSnapshots)
        try container.encode(aestheticRecipeVersion, forKey: .aestheticRecipeVersion)
        try container.encode(isActiveDraft, forKey: .isActiveDraft)
        try container.encode(inputFingerprint, forKey: .inputFingerprint)
        try container.encode(title, forKey: .title)
        try container.encode(logline, forKey: .logline)
        try container.encode(centralTension, forKey: .centralTension)
        try container.encode(storyEngine, forKey: .storyEngine)
        try container.encode(format, forKey: .format)
        try container.encode(targetDuration, forKey: .targetDuration)
        try container.encode(beginningState, forKey: .beginningState)
        try container.encode(endingState, forKey: .endingState)
        try container.encode(aestheticStrategy, forKey: .aestheticStrategy)
        try container.encode(beats, forKey: .beats)
        try container.encode(status, forKey: .status)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(generator, forKey: .generator)
        try container.encode(model, forKey: .model)
        try container.encode(responseId, forKey: .responseId)
        try container.encode(artifactStatus, forKey: .artifactStatus)
        try container.encode(validationWarnings, forKey: .validationWarnings)
    }
}

struct StorySequenceStripTile: Codable, Hashable, Identifiable {
    var beatId: String
    var id: String { beatId }
    var order: Int
    var title: String = ""
    var storyFunction: String = ""
    var meaningMove: String = ""
    var visualCaption: String
    var emotionalState: String
    var generationStatus: String = "local"
    var thumbnailPath: String = ""
    var paletteTerms: [String] = []
    var isLocked: Bool = false
}

extension StorySequenceStripTile {
    enum CodingKeys: String, CodingKey {
        case beatId
        case order
        case title
        case storyFunction
        case meaningMove
        case visualCaption
        case emotionalState
        case generationStatus
        case thumbnailPath
        case paletteTerms
        case isLocked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beatId = try container.decode(String.self, forKey: .beatId)
        order = try container.decode(Int.self, forKey: .order)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        storyFunction = try container.decodeIfPresent(String.self, forKey: .storyFunction) ?? ""
        meaningMove = try container.decodeIfPresent(String.self, forKey: .meaningMove) ?? ""
        visualCaption = try container.decodeIfPresent(String.self, forKey: .visualCaption) ?? ""
        emotionalState = try container.decodeIfPresent(String.self, forKey: .emotionalState) ?? ""
        generationStatus = try container.decodeIfPresent(String.self, forKey: .generationStatus) ?? "local"
        thumbnailPath = try container.decodeIfPresent(String.self, forKey: .thumbnailPath) ?? ""
        paletteTerms = try container.decodeIfPresent([String].self, forKey: .paletteTerms) ?? []
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(beatId, forKey: .beatId)
        try container.encode(order, forKey: .order)
        try container.encode(title, forKey: .title)
        try container.encode(storyFunction, forKey: .storyFunction)
        try container.encode(meaningMove, forKey: .meaningMove)
        try container.encode(visualCaption, forKey: .visualCaption)
        try container.encode(emotionalState, forKey: .emotionalState)
        try container.encode(generationStatus, forKey: .generationStatus)
        try container.encode(thumbnailPath, forKey: .thumbnailPath)
        try container.encode(paletteTerms, forKey: .paletteTerms)
        try container.encode(isLocked, forKey: .isLocked)
    }
}

struct StorySequenceStripDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.story_sequence_strip.v0.1"
    var projectId: String
    var beatBoardId: String = ""
    var inputFingerprint: StoryInputFingerprint = .empty()
    var tiles: [StorySequenceStripTile] = []
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String = "") -> StorySequenceStripDocument {
        StorySequenceStripDocument(projectId: projectId)
    }

    static func fromBeatBoard(_ board: StoryBeatBoard, paletteTerms: [String]) -> StorySequenceStripDocument {
        StorySequenceStripDocument(
            projectId: board.projectId,
            beatBoardId: board.beatBoardId,
            inputFingerprint: board.inputFingerprint,
            tiles: board.visibleBeats.map { beat in
                StorySequenceStripTile(
                    beatId: beat.beatId,
                    order: beat.order,
                    title: beat.title,
                    storyFunction: beat.storyFunction,
                    meaningMove: beat.meaningMove,
                    visualCaption: beat.generationBrief.visualFocus.isEmpty
                        ? String(beat.visualMoment.prefix(72))
                        : beat.generationBrief.visualFocus,
                    emotionalState: beat.emotionalTurn.isEmpty ? beat.storyFunction : beat.emotionalTurn,
                    paletteTerms: paletteTerms,
                    isLocked: beat.locked
                )
            },
            updatedAt: DateFormats.now()
        )
    }

    static func decode(from data: Data) throws -> StorySequenceStripDocument {
        try JSONCoding.decoder.decode(StorySequenceStripDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }
}

struct ProjectStoryDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.project_story.v0.1"
    var projectId: String
    var acceptedStoryId: String = ""
    var projectStoryId: String?
    var acceptedAt: String = ""
    var title: String = ""
    var logline: String = ""
    var centralTension: String?
    var storyEngine: String?
    var aestheticStrategy: StoryBeatBoardAestheticStrategy?
    var storyDirectionId: String = ""
    var sourceDirectionIds: [String] = []
    var beatBoardId: String = ""
    var storySetupSnapshot: StorySetupDocument = .empty()
    var aestheticRecipeSnapshot: ProjectAestheticDirectionRecipe?
    var inputFingerprint: StoryInputFingerprint = .empty()
    var promptReadySummary: String = ""
    var beats: [StoryBeatBoardBeat] = []
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String = "") -> ProjectStoryDocument {
        ProjectStoryDocument(projectId: projectId)
    }

    static func accepted(
        projectId: String,
        direction: StoryDirectionCard?,
        board: StoryBeatBoard,
        setup: StorySetupDocument,
        aestheticRecipe: ProjectAestheticDirectionRecipe?,
        acceptedAt: String
    ) -> ProjectStoryDocument {
        ProjectStoryDocument(
            projectId: projectId,
            acceptedStoryId: "story_\(shortHash("\(projectId):\(board.beatBoardId):\(acceptedAt)", length: 16))",
            projectStoryId: "story_\(shortHash("\(projectId):\(board.beatBoardId):\(acceptedAt)", length: 16))",
            acceptedAt: acceptedAt,
            title: board.title,
            logline: board.logline,
            centralTension: board.centralTension,
            storyEngine: board.storyEngine,
            aestheticStrategy: board.aestheticStrategy,
            storyDirectionId: direction?.directionId ?? (board.primaryDirectionId.isEmpty ? board.parentDirectionId : board.primaryDirectionId),
            sourceDirectionIds: board.sourceDirectionIds,
            beatBoardId: board.beatBoardId,
            storySetupSnapshot: setup,
            aestheticRecipeSnapshot: aestheticRecipe,
            inputFingerprint: board.inputFingerprint,
            promptReadySummary: [
                board.logline,
                board.visibleBeats.map { "\($0.order). \($0.promptReadyLine)" }.joined(separator: "\n")
            ].filter { !$0.isEmpty }.joined(separator: "\n\n"),
            beats: board.visibleBeats,
            updatedAt: acceptedAt
        )
    }

    static func decode(from data: Data) throws -> ProjectStoryDocument {
        try JSONCoding.decoder.decode(ProjectStoryDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }

    var hasAcceptedStory: Bool {
        (!(projectStoryId ?? acceptedStoryId).isEmpty) && !beats.isEmpty
    }

    func freshness(against current: StoryInputFingerprint) -> StoryArtifactFreshness {
        guard hasAcceptedStory else { return .missing }
        return inputFingerprint == current ? .fresh : .stale
    }
}

extension ProjectStoryDocument {
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case acceptedStoryId
        case projectStoryId
        case acceptedAt
        case title
        case logline
        case centralTension
        case storyEngine
        case aestheticStrategy
        case storyDirectionId
        case sourceDirectionIds
        case beatBoardId
        case storySetupSnapshot
        case aestheticRecipeSnapshot
        case inputFingerprint
        case promptReadySummary
        case beats
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "litscenes.project_story.v0.1"
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        acceptedStoryId = try container.decodeIfPresent(String.self, forKey: .acceptedStoryId) ?? ""
        projectStoryId = try container.decodeIfPresent(String.self, forKey: .projectStoryId)
        acceptedAt = try container.decodeIfPresent(String.self, forKey: .acceptedAt) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        logline = try container.decodeIfPresent(String.self, forKey: .logline) ?? ""
        centralTension = try container.decodeIfPresent(String.self, forKey: .centralTension)
        storyEngine = try container.decodeIfPresent(String.self, forKey: .storyEngine)
        aestheticStrategy = try container.decodeIfPresent(StoryBeatBoardAestheticStrategy.self, forKey: .aestheticStrategy)
        storyDirectionId = try container.decodeIfPresent(String.self, forKey: .storyDirectionId) ?? ""
        sourceDirectionIds = try container.decodeIfPresent([String].self, forKey: .sourceDirectionIds) ?? [storyDirectionId].filter { !$0.isEmpty }
        beatBoardId = try container.decodeIfPresent(String.self, forKey: .beatBoardId) ?? ""
        storySetupSnapshot = try container.decodeIfPresent(StorySetupDocument.self, forKey: .storySetupSnapshot) ?? .empty(projectId: projectId)
        aestheticRecipeSnapshot = try container.decodeIfPresent(ProjectAestheticDirectionRecipe.self, forKey: .aestheticRecipeSnapshot)
        inputFingerprint = try container.decodeIfPresent(StoryInputFingerprint.self, forKey: .inputFingerprint) ?? .empty()
        promptReadySummary = try container.decodeIfPresent(String.self, forKey: .promptReadySummary) ?? ""
        beats = try container.decodeIfPresent([StoryBeatBoardBeat].self, forKey: .beats) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(acceptedStoryId, forKey: .acceptedStoryId)
        try container.encodeIfPresent(projectStoryId, forKey: .projectStoryId)
        try container.encode(acceptedAt, forKey: .acceptedAt)
        try container.encode(title, forKey: .title)
        try container.encode(logline, forKey: .logline)
        try container.encodeIfPresent(centralTension, forKey: .centralTension)
        try container.encodeIfPresent(storyEngine, forKey: .storyEngine)
        try container.encodeIfPresent(aestheticStrategy, forKey: .aestheticStrategy)
        try container.encode(storyDirectionId, forKey: .storyDirectionId)
        try container.encode(sourceDirectionIds, forKey: .sourceDirectionIds)
        try container.encode(beatBoardId, forKey: .beatBoardId)
        try container.encode(storySetupSnapshot, forKey: .storySetupSnapshot)
        try container.encodeIfPresent(aestheticRecipeSnapshot, forKey: .aestheticRecipeSnapshot)
        try container.encode(inputFingerprint, forKey: .inputFingerprint)
        try container.encode(promptReadySummary, forKey: .promptReadySummary)
        try container.encode(beats, forKey: .beats)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

enum SceneLayerType: String, Codable, Hashable, CaseIterable, Identifiable {
    case audio
    case still
    case video
    case textOverlay = "text_overlay"
    case caption
    case reference

    var id: String { rawValue }

    var label: String {
        switch self {
        case .audio: "Audio"
        case .still: "Still"
        case .video: "Video"
        case .textOverlay: "Text"
        case .caption: "Caption"
        case .reference: "Reference"
        }
    }

    static let productionMatrixOrder: [SceneLayerType] = [
        .still,
        .video,
        .audio,
        .textOverlay,
        .caption,
        .reference
    ]
}

enum SceneAssetStatus: String, Codable, Hashable {
    case missing
    case draft
    case edited
    case ready
    case exported
    case generated
    case failed
    case stale
    case unavailable
    case global
}

enum SceneSourceArtifactType: String, Codable, Hashable, CaseIterable, Identifiable {
    case projectStory = "project_story"
    case beatBoard = "beat_board"
    case sceneStory = "scene_story"

    var id: String { rawValue }
}

enum SceneAssetScope: String, Codable, Hashable, CaseIterable, Identifiable {
    case beat
    case multiBeat = "multi_beat"
    case global

    var id: String { rawValue }
}

enum ScenePromptSource: String, Codable, Hashable {
    case generationBrief = "generation_brief"
    case manual
    case audioDirection = "audio_direction"
}

struct SceneAssetDocument: Codable, Hashable, Identifiable {
    static let promptTemplateVersion = "litscenes.scene_prompt_template.v0.1"

    var schemaVersion: String = "litscenes.scene_asset.v0.2"
    var assetId: String
    var id: String { assetId }
    var projectId: String
    var beatId: String = ""
    var sourceArtifactType: SceneSourceArtifactType = .beatBoard
    var sourceArtifactId: String = ""
    var sourceBeatBoardId: String = ""
    var layerType: SceneLayerType = .audio
    var status: SceneAssetStatus = .draft
    var assetScope: SceneAssetScope = .beat
    var targetBeatId: String = ""
    var prompt: String = ""
    var negativePrompt: String = ""
    var textOverlay: String = ""
    var captionDraft: String = ""
    var promptSource: ScenePromptSource = .generationBrief
    var outputPaths: [String] = []
    var settings: [String: CodableValue] = [:]
    var sourceProjectStoryId: String = ""
    var sourceBeatIds: [String] = []
    var sourceMediaIds: [String] = []
    var avoidMediaIds: [String] = []
    var referenceMediaIds: [String] = []
    var mediaAnchors: [StoryMediaAnchor] = []
    var isManuallyEdited: Bool = false
    var manualEditFields: [String] = []
    var lastAutoPrompt: String = ""
    var promptTemplateVersion: String = SceneAssetDocument.promptTemplateVersion
    var sourceBeatFingerprint: String = ""
    var sourceBoardFingerprint: String = ""
    var sourceFingerprint: String = ""
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()

    static func decode(from data: Data) throws -> SceneAssetDocument {
        try JSONCoding.decoder.decode(SceneAssetDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }

    func freshness(activeBoard: StoryBeatBoard, acceptedStory: ProjectStoryDocument) -> StoryArtifactFreshness {
        guard !assetId.isEmpty else { return .missing }
        let expectedStoryId = sourceProjectStoryId.trimmingCharacters(in: .whitespacesAndNewlines)
        if sourceArtifactType == .projectStory, !expectedStoryId.isEmpty, expectedStoryId != acceptedStory.acceptedStoryId {
            return .stale
        }
        let expectedBoardId = sourceBeatBoardId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !expectedBoardId.isEmpty, expectedBoardId != activeBoard.beatBoardId {
            return .stale
        }
        if !sourceBoardFingerprint.isEmpty, sourceBoardFingerprint != activeBoard.inputFingerprint.stableId {
            return .stale
        }
        if !sourceFingerprint.isEmpty, sourceFingerprint != activeBoard.inputFingerprint.stableId {
            return .stale
        }
        return .fresh
    }
}

extension SceneAssetDocument {
    static func deterministicAssetId(sourceArtifactId: String, beatId: String, layerType: SceneLayerType) -> String {
        let safeSource = safeIdentifier(sourceArtifactId.isEmpty ? "draft_source" : sourceArtifactId)
        let safeBeat = safeIdentifier(beatId.isEmpty ? "global" : beatId)
        let safeLayer = safeIdentifier(layerType.rawValue)
        return "asset_\(safeSource)_\(safeBeat)_\(safeLayer)"
    }

    static func defaultPrompt(for beat: StoryBeatBoardBeat, layerType: SceneLayerType) -> String {
        let brief = beat.generationBrief
        switch layerType {
        case .still:
            return [
                "Subject: \(brief.subject)",
                "Setting: \(brief.setting)",
                "Action: \(brief.action)",
                "Visual focus: \(brief.visualFocus)",
                "Camera/framing: \(brief.cameraOrFraming)",
                "Lighting: \(brief.lighting)",
                "Treatment: \(brief.aestheticTreatment)",
                beat.promptReadyLine.isEmpty ? "" : "Prompt line: \(beat.promptReadyLine)"
            ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
        case .video:
            return [
                "Generate a short shot from this beat without changing story facts.",
                "Event: \(beat.event)",
                "Visual moment: \(beat.visualMoment)",
                "Action: \(brief.action)",
                "Camera/framing: \(brief.cameraOrFraming)",
                "Treatment: \(brief.aestheticTreatment)"
            ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
        case .audio:
            return [
                "Audio direction for beat \(beat.order): \(beat.title)",
                "Emotional turn: \(beat.emotionalTurn)",
                "Meaning move: \(beat.meaningMove)",
                beat.voiceOrTextOverlay.isEmpty ? "" : "Voice/text phrase: \(beat.voiceOrTextOverlay)"
            ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
        case .textOverlay:
            return beat.voiceOrTextOverlay.isEmpty ? brief.textOverlay : beat.voiceOrTextOverlay
        case .caption:
            return [
                beat.title,
                beat.meaningMove.isEmpty ? beat.visualMoment : beat.meaningMove
            ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " - ")
        case .reference:
            return [
                "Use source/reference media anchors for this beat.",
                beat.visualMoment
            ].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
        }
    }

    static func draft(
        projectId: String,
        sourceArtifactType: SceneSourceArtifactType,
        sourceArtifactId: String,
        sourceProjectStoryId: String,
        beatBoard: StoryBeatBoard,
        beat: StoryBeatBoardBeat,
        layerType: SceneLayerType
    ) -> SceneAssetDocument {
        let autoPrompt = defaultPrompt(for: beat, layerType: layerType)
        let status: SceneAssetStatus
        switch layerType {
        case .textOverlay:
            status = autoPrompt.isEmpty ? .missing : .draft
        case .reference:
            status = beat.mediaAnchors.isEmpty ? .missing : .draft
        default:
            status = .draft
        }
        return SceneAssetDocument(
            assetId: deterministicAssetId(
                sourceArtifactId: sourceArtifactId,
                beatId: beat.beatId,
                layerType: layerType
            ),
            projectId: projectId,
            beatId: beat.beatId,
            sourceArtifactType: sourceArtifactType,
            sourceArtifactId: sourceArtifactId,
            sourceBeatBoardId: beatBoard.beatBoardId,
            layerType: layerType,
            status: status,
            assetScope: .beat,
            targetBeatId: beat.beatId,
            prompt: autoPrompt,
            negativePrompt: beat.generationBrief.negativeConstraints.joined(separator: "\n"),
            textOverlay: beat.voiceOrTextOverlay.isEmpty ? beat.generationBrief.textOverlay : beat.voiceOrTextOverlay,
            captionDraft: defaultPrompt(for: beat, layerType: .caption),
            sourceProjectStoryId: sourceProjectStoryId,
            sourceBeatIds: [beat.beatId],
            sourceMediaIds: beat.sourceMediaIds,
            avoidMediaIds: beat.avoidMediaIds,
            referenceMediaIds: beat.referenceMediaIds,
            mediaAnchors: beat.mediaAnchors,
            lastAutoPrompt: autoPrompt,
            sourceBeatFingerprint: stableHash(StoryBeatBoardBeatSnapshot.fromBeat(beat)),
            sourceBoardFingerprint: beatBoard.inputFingerprint.stableId,
            sourceFingerprint: beatBoard.inputFingerprint.stableId
        )
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case assetId
        case projectId
        case beatId
        case sourceArtifactType
        case sourceArtifactId
        case sourceBeatBoardId
        case layerType
        case status
        case assetScope
        case targetBeatId
        case prompt
        case negativePrompt
        case textOverlay
        case captionDraft
        case promptSource
        case outputPaths
        case settings
        case sourceProjectStoryId
        case sourceBeatIds
        case sourceMediaIds
        case avoidMediaIds
        case referenceMediaIds
        case mediaAnchors
        case isManuallyEdited
        case manualEditFields
        case lastAutoPrompt
        case promptTemplateVersion
        case sourceBeatFingerprint
        case sourceBoardFingerprint
        case sourceFingerprint
        case generatedAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "litscenes.scene_asset.v0.1"
        assetId = try container.decode(String.self, forKey: .assetId)
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        beatId = try container.decodeIfPresent(String.self, forKey: .beatId) ?? ""
        sourceProjectStoryId = try container.decodeIfPresent(String.self, forKey: .sourceProjectStoryId) ?? ""
        sourceBeatBoardId = try container.decodeIfPresent(String.self, forKey: .sourceBeatBoardId) ?? ""
        sourceArtifactType = try container.decodeIfPresent(SceneSourceArtifactType.self, forKey: .sourceArtifactType)
            ?? (sourceProjectStoryId.isEmpty ? .beatBoard : .projectStory)
        sourceArtifactId = try container.decodeIfPresent(String.self, forKey: .sourceArtifactId)
            ?? (sourceArtifactType == .projectStory ? sourceProjectStoryId : sourceBeatBoardId)
        layerType = try container.decodeIfPresent(SceneLayerType.self, forKey: .layerType) ?? .audio
        status = try container.decodeIfPresent(SceneAssetStatus.self, forKey: .status) ?? .draft
        assetScope = try container.decodeIfPresent(SceneAssetScope.self, forKey: .assetScope) ?? (beatId.isEmpty ? .global : .beat)
        targetBeatId = try container.decodeIfPresent(String.self, forKey: .targetBeatId) ?? beatId
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        negativePrompt = try container.decodeIfPresent(String.self, forKey: .negativePrompt) ?? ""
        textOverlay = try container.decodeIfPresent(String.self, forKey: .textOverlay) ?? ""
        captionDraft = try container.decodeIfPresent(String.self, forKey: .captionDraft) ?? ""
        promptSource = try container.decodeIfPresent(ScenePromptSource.self, forKey: .promptSource) ?? .generationBrief
        outputPaths = try container.decodeIfPresent([String].self, forKey: .outputPaths) ?? []
        settings = try container.decodeIfPresent([String: CodableValue].self, forKey: .settings) ?? [:]
        sourceBeatIds = try container.decodeIfPresent([String].self, forKey: .sourceBeatIds) ?? []
        sourceMediaIds = try container.decodeIfPresent([String].self, forKey: .sourceMediaIds) ?? []
        avoidMediaIds = try container.decodeIfPresent([String].self, forKey: .avoidMediaIds) ?? []
        referenceMediaIds = try container.decodeIfPresent([String].self, forKey: .referenceMediaIds) ?? []
        mediaAnchors = try container.decodeIfPresent([StoryMediaAnchor].self, forKey: .mediaAnchors) ?? []
        isManuallyEdited = try container.decodeIfPresent(Bool.self, forKey: .isManuallyEdited) ?? false
        manualEditFields = try container.decodeIfPresent([String].self, forKey: .manualEditFields) ?? []
        lastAutoPrompt = try container.decodeIfPresent(String.self, forKey: .lastAutoPrompt) ?? ""
        promptTemplateVersion = try container.decodeIfPresent(String.self, forKey: .promptTemplateVersion) ?? SceneAssetDocument.promptTemplateVersion
        sourceBeatFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceBeatFingerprint) ?? ""
        sourceBoardFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceBoardFingerprint) ?? ""
        sourceFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceFingerprint) ?? sourceBoardFingerprint
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("litscenes.scene_asset.v0.2", forKey: .schemaVersion)
        try container.encode(assetId, forKey: .assetId)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(beatId, forKey: .beatId)
        try container.encode(sourceArtifactType, forKey: .sourceArtifactType)
        try container.encode(sourceArtifactId, forKey: .sourceArtifactId)
        try container.encode(sourceBeatBoardId, forKey: .sourceBeatBoardId)
        try container.encode(layerType, forKey: .layerType)
        try container.encode(status, forKey: .status)
        try container.encode(assetScope, forKey: .assetScope)
        try container.encode(targetBeatId, forKey: .targetBeatId)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(negativePrompt, forKey: .negativePrompt)
        try container.encode(textOverlay, forKey: .textOverlay)
        try container.encode(captionDraft, forKey: .captionDraft)
        try container.encode(promptSource, forKey: .promptSource)
        try container.encode(outputPaths, forKey: .outputPaths)
        try container.encode(settings, forKey: .settings)
        try container.encode(sourceProjectStoryId, forKey: .sourceProjectStoryId)
        try container.encode(sourceBeatIds, forKey: .sourceBeatIds)
        try container.encode(sourceMediaIds, forKey: .sourceMediaIds)
        try container.encode(avoidMediaIds, forKey: .avoidMediaIds)
        try container.encode(referenceMediaIds, forKey: .referenceMediaIds)
        try container.encode(mediaAnchors, forKey: .mediaAnchors)
        try container.encode(isManuallyEdited, forKey: .isManuallyEdited)
        try container.encode(manualEditFields, forKey: .manualEditFields)
        try container.encode(lastAutoPrompt, forKey: .lastAutoPrompt)
        try container.encode(promptTemplateVersion, forKey: .promptTemplateVersion)
        try container.encode(sourceBeatFingerprint, forKey: .sourceBeatFingerprint)
        try container.encode(sourceBoardFingerprint, forKey: .sourceBoardFingerprint)
        try container.encode(sourceFingerprint, forKey: .sourceFingerprint)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct ScenePromptExportLayer: Codable, Hashable, Identifiable {
    var layerId: String
    var id: String { layerId }
    var beatId: String
    var layerType: SceneLayerType
    var status: SceneAssetStatus
    var prompt: String
    var negativePrompt: String
    var textOverlay: String
    var captionDraft: String
    var sourceMediaIds: [String]
    var avoidMediaIds: [String]
    var referenceMediaIds: [String]
    var isManuallyEdited: Bool
    var manualEditFields: [String]
    var promptTemplateVersion: String
    var sourceBeatFingerprint: String
    var sourceBoardFingerprint: String
}

struct ScenePromptExportDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.scene_prompt_export.v0.1"
    var projectId: String
    var exportId: String
    var exportedAt: String
    var sourceArtifactType: SceneSourceArtifactType
    var sourceArtifactId: String
    var sourceProjectStoryId: String
    var sourceBeatBoardId: String
    var sourceBoardFingerprint: String
    var layers: [ScenePromptExportLayer]
}

struct SceneWorkspaceDocument: Codable, Hashable, Identifiable {
    var schemaVersion: String = "litscenes.scene_workspace.v0.2"
    var sceneWorkspaceId: String
    var id: String { sceneWorkspaceId }
    var projectId: String
    var sourceArtifactType: SceneSourceArtifactType = .beatBoard
    var sourceArtifactId: String = ""
    var sourceProjectStoryId: String = ""
    var sourceBeatBoardId: String = ""
    var sourceBoardFingerprint: String = ""
    var status: String = "draft"
    var assetIds: [String] = []
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String = "") -> SceneWorkspaceDocument {
        SceneWorkspaceDocument(
            sceneWorkspaceId: "",
            projectId: projectId
        )
    }

    static func forContext(
        projectId: String,
        projectStory: ProjectStoryDocument,
        beatBoard: StoryBeatBoard,
        createdAt: String = DateFormats.now()
    ) -> SceneWorkspaceDocument {
        let storyId = projectStory.acceptedStoryId
        let boardId = beatBoard.beatBoardId
        let sourceId = storyId.isEmpty ? boardId : storyId
        let sourceType: SceneSourceArtifactType = storyId.isEmpty ? .beatBoard : .projectStory
        return SceneWorkspaceDocument(
            sceneWorkspaceId: "scene_workspace_\(shortHash("\(projectId):\(sourceId):\(createdAt)", length: 16))",
            projectId: projectId,
            sourceArtifactType: sourceType,
            sourceArtifactId: sourceId,
            sourceProjectStoryId: storyId,
            sourceBeatBoardId: boardId,
            sourceBoardFingerprint: beatBoard.inputFingerprint.stableId,
            status: storyId.isEmpty ? "draft_context" : "accepted_story",
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    static func decode(from data: Data) throws -> SceneWorkspaceDocument {
        try JSONCoding.decoder.decode(SceneWorkspaceDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }

    func freshness(activeBoard: StoryBeatBoard, acceptedStory: ProjectStoryDocument) -> StoryArtifactFreshness {
        guard !sceneWorkspaceId.isEmpty else { return .missing }
        if !sourceProjectStoryId.isEmpty, sourceProjectStoryId != acceptedStory.acceptedStoryId {
            return .stale
        }
        if !sourceBeatBoardId.isEmpty, sourceBeatBoardId != activeBoard.beatBoardId {
            return .stale
        }
        if !sourceBoardFingerprint.isEmpty, sourceBoardFingerprint != activeBoard.inputFingerprint.stableId {
            return .stale
        }
        return .fresh
    }
}

extension SceneWorkspaceDocument {
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case sceneWorkspaceId
        case projectId
        case sourceArtifactType
        case sourceArtifactId
        case sourceProjectStoryId
        case sourceBeatBoardId
        case sourceBoardFingerprint
        case status
        case assetIds
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "litscenes.scene_workspace.v0.1"
        sceneWorkspaceId = try container.decodeIfPresent(String.self, forKey: .sceneWorkspaceId) ?? ""
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        sourceProjectStoryId = try container.decodeIfPresent(String.self, forKey: .sourceProjectStoryId) ?? ""
        sourceBeatBoardId = try container.decodeIfPresent(String.self, forKey: .sourceBeatBoardId) ?? ""
        sourceArtifactType = try container.decodeIfPresent(SceneSourceArtifactType.self, forKey: .sourceArtifactType)
            ?? (sourceProjectStoryId.isEmpty ? .beatBoard : .projectStory)
        sourceArtifactId = try container.decodeIfPresent(String.self, forKey: .sourceArtifactId)
            ?? (sourceArtifactType == .projectStory ? sourceProjectStoryId : sourceBeatBoardId)
        sourceBoardFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceBoardFingerprint) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "draft"
        assetIds = try container.decodeIfPresent([String].self, forKey: .assetIds) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? DateFormats.now()
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("litscenes.scene_workspace.v0.2", forKey: .schemaVersion)
        try container.encode(sceneWorkspaceId, forKey: .sceneWorkspaceId)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(sourceArtifactType, forKey: .sourceArtifactType)
        try container.encode(sourceArtifactId, forKey: .sourceArtifactId)
        try container.encode(sourceProjectStoryId, forKey: .sourceProjectStoryId)
        try container.encode(sourceBeatBoardId, forKey: .sourceBeatBoardId)
        try container.encode(sourceBoardFingerprint, forKey: .sourceBoardFingerprint)
        try container.encode(status, forKey: .status)
        try container.encode(assetIds, forKey: .assetIds)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct StoryGenerationRunDocument: Codable, Hashable, Identifiable {
    var schemaVersion: String = "litscenes.story_generation_run.v0.1"
    var runId: String
    var id: String { runId }
    var artifactType: String
    var model: String
    var responseId: String
    var outputSchemaVersion: String
    var inputFingerprint: StoryInputFingerprint
    var compactPromptPacket: CodableValue
    var artifactId: String
    var createdAt: String

    static func decode(from data: Data) throws -> StoryGenerationRunDocument {
        try JSONCoding.decoder.decode(StoryGenerationRunDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }
}

struct StoryGenerationRunIndexEntry: Codable, Hashable, Identifiable {
    var runId: String
    var id: String { runId }
    var artifactType: String
    var artifactId: String
    var model: String
    var relativePath: String
    var createdAt: String
}

struct StoryGenerationRunIndexDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.story_generation_run_index.v0.1"
    var projectId: String
    var runs: [StoryGenerationRunIndexEntry] = []
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String = "") -> StoryGenerationRunIndexDocument {
        StoryGenerationRunIndexDocument(projectId: projectId)
    }

    static func decode(from data: Data) throws -> StoryGenerationRunIndexDocument {
        try JSONCoding.decoder.decode(StoryGenerationRunIndexDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }
}

struct StoryPatternAffinity: Codable, Hashable {
    var recommended: Double = 0
    var bolder: Double = 0
    var commercial: Double = 0
    var wildcard: Double = 0

    func value(for lane: StoryDirectionLane) -> Double {
        switch lane {
        case .recommended: recommended
        case .bolder: bolder
        case .commercial: commercial
        case .wildcard: wildcard
        }
    }
}

struct StoryPatternNode: Codable, Hashable, Identifiable {
    var id: String
    var kind: String
    var label: String
    var friendlyLabel: String
    var description: String
    var laneAffinities: StoryPatternAffinity = StoryPatternAffinity()
    var setupAffinities: [String: Double] = [:]
    var typicalBeatFunctions: [String] = []
    var compatibleWith: [String] = []
    var contrastsWith: [String] = []
    var promptFragments: [String] = []
    var antiPatterns: [String] = []
    var keywords: [String] = []
}

struct StoryPatternEdge: Codable, Hashable {
    var sourceId: String
    var targetId: String
    var relation: String
    var weight: Double = 0.5
}

struct StoryPatternIndexDocument: Codable, Hashable {
    static let defaultVersion = "story_pattern_index.v0.1"

    var schemaVersion: String = "litscenes.story_pattern_index.v0.1"
    var version: String = StoryPatternIndexDocument.defaultVersion
    var meaningMoves: [StoryPatternNode] = []
    var storyEngines: [StoryPatternNode] = []
    var beatFunctions: [StoryPatternNode] = []
    var archetypalSituations: [StoryPatternNode] = []
    var tensions: [StoryPatternNode] = []
    var transformations: [StoryPatternNode] = []
    var edges: [StoryPatternEdge] = []

    static func decode(from data: Data) throws -> StoryPatternIndexDocument {
        try JSONCoding.decoder.decode(StoryPatternIndexDocument.self, from: data)
    }

    var allNodes: [StoryPatternNode] {
        meaningMoves + storyEngines + beatFunctions + archetypalSituations + tensions + transformations
    }
}

struct StoryPatternMatch: Codable, Hashable, Identifiable {
    var nodeId: String
    var id: String { nodeId }
    var kind: String
    var label: String
    var friendlyLabel: String
    var score: Double
    var promptFragments: [String]
}

enum StoryPatternMatcher {
    static func matches(
        index: StoryPatternIndexDocument,
        text: String,
        setup: StorySetupDocument,
        limit: Int = 12
    ) -> [StoryPatternMatch] {
        let haystack = text.lowercased()
        return index.allNodes.compactMap { node in
            let labels = ([node.id, node.label, node.friendlyLabel, node.description] + node.keywords + node.promptFragments)
                .map { $0.lowercased() }
            let textHits = labels.reduce(0.0) { score, label in
                guard !label.isEmpty else { return score }
                return haystack.contains(label) ? score + 1.0 : score
            }
            let tokenHits = node.keywords.reduce(0.0) { score, keyword in
                haystack.contains(keyword.lowercased()) ? score + 0.4 : score
            }
            let setupScore = node.setupAffinities[setup.outputType.rawValue] ?? 0
            let total = textHits + tokenHits + setupScore
            guard total > 0 else { return nil }
            return StoryPatternMatch(
                nodeId: node.id,
                kind: node.kind,
                label: node.label,
                friendlyLabel: node.friendlyLabel,
                score: min(total / 4.0, 1.0),
                promptFragments: node.promptFragments
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.label < rhs.label
            }
            return lhs.score > rhs.score
        }
        .prefix(limit)
        .map { $0 }
    }
}

struct StoryAestheticCues: Codable, Hashable {
    var narrativeCues: [String] = []
    var presentationCues: [String] = []
    var paletteCues: [String] = []
    var avoidCues: [String] = []
}

struct StoryGoalDigest: Codable, Hashable {
    var summary: String = ""
    var mood: [String] = []
    var values: [String] = []
    var motifs: [String] = []
    var avoid: [String] = []
    var desiredStoryResult: String = ""
}

struct StoryPromptPacket: Codable, Hashable {
    var goalDigest: StoryGoalDigest
    var aestheticNarrativeCues: [String]
    var aestheticPresentationCues: [String]
    var paletteCues: [String]
    var avoidCues: [String]
    var storySetup: StorySetupDocument
    var storySignals: StorySignalSet
    var sourceContext: String
    var enabledMediaDigest: String
    var storyPatternMatches: [StoryPatternMatch]
}

enum StoryValidation {
    static let genericPhrases = [
        "confronts the truth",
        "discovers who they really are",
        "learns a lesson",
        "faces their destiny",
        "journey comes full circle",
        "must decide what matters",
        "the stakes are raised",
        "everything changes"
    ]

    static func directionWarnings(_ direction: StoryDirectionCard) -> [String] {
        var warnings: [String] = []
        if direction.premise.trimmedWordCount < 8 { warnings.append("premise too thin") }
        if direction.storyEngine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { warnings.append("missing story engine") }
        if direction.aestheticUse.narrative.trimmedWordCount < 4 { warnings.append("weak narrative aesthetic binding") }
        if direction.aestheticUse.presentation.trimmedWordCount < 4 { warnings.append("weak presentation aesthetic binding") }
        if direction.whatHappens.trimmedWordCount < 8 { warnings.append("missing concrete escalation") }
        if direction.risk.trimmedWordCount < 3 { warnings.append("missing risk") }
        if direction.threeBeatPreview.count < 3 { warnings.append("missing 3-beat preview") }
        if containsGenericSlop(direction.premise) || containsGenericSlop(direction.whatHappens) {
            warnings.append("generic story language")
        }
        return warnings
    }

    static func beatWarnings(_ beat: StoryBeatBoardBeat) -> [String] {
        var warnings: [String] = []
        if beat.event.trimmedWordCount < 8 { warnings.append("event too thin") }
        if beat.visualMoment.trimmedWordCount < 8 { warnings.append("visual moment too thin") }
        if beat.emotionalTurn.trimmedWordCount < 3 { warnings.append("missing emotional turn") }
        if beat.meaningMove.trimmedWordCount < 3 { warnings.append("missing meaning move") }
        if beat.storyFunction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { warnings.append("missing story function") }
        if beat.promptReadyLine.trimmedWordCount < 8 { warnings.append("prompt line too thin") }
        if beat.aestheticPresentationBinding.isEmpty { warnings.append("missing presentation binding") }
        if beat.generationBrief.subject.isEmpty || beat.generationBrief.action.isEmpty || beat.generationBrief.visualFocus.isEmpty {
            warnings.append("incomplete generation brief")
        }
        if containsGenericSlop(beat.event) || containsGenericSlop(beat.visualMoment) {
            warnings.append("generic beat language")
        }
        return warnings
    }

    static func laneDifferentiationWarnings(_ directions: [StoryDirectionCard]) -> [String] {
        guard directions.count >= 3 else { return ["fewer than three public Storylines"] }
        var warnings: [String] = []
        let distinctEngines = Set(directions.map { $0.storyEngine.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        if distinctEngines.count < min(3, directions.count) {
            warnings.append("public Storylines use too few distinct story engines")
        }
        for lhs in directions {
            for rhs in directions where lhs.directionId < rhs.directionId {
                let lhsMoves = Set(lhs.meaningMoves.map { $0.lowercased() })
                let rhsMoves = Set(rhs.meaningMoves.map { $0.lowercased() })
                if !lhsMoves.isEmpty || !rhsMoves.isEmpty {
                    let shared = lhsMoves.intersection(rhsMoves).count
                    let maxCount = max(lhsMoves.count, rhsMoves.count, 1)
                    if Double(shared) / Double(maxCount) > 0.6 {
                        warnings.append("\(lhs.lane.rawValue) and \(rhs.lane.rawValue) share too many meaning moves")
                    }
                }
                if textOverlap(lhs.premise, rhs.premise) > 0.7 || textOverlap(lhs.whatHappens, rhs.whatHappens) > 0.7 {
                    warnings.append("\(lhs.lane.rawValue) and \(rhs.lane.rawValue) are near-duplicates")
                }
            }
        }
        if let commercial = directions.first(where: { $0.lane == .commercial }),
           commercial.commercialPressure < 0.35 || commercial.commercialPressure > 0.60 {
            warnings.append("commercial lane pressure outside default guardrail")
        }
        if let recommended = directions.first(where: { $0.lane == .recommended }),
           let wildcard = directions.first(where: { $0.lane == .wildcard }),
           wildcard.weirdness <= recommended.weirdness || wildcard.promptability < 0.45 {
            warnings.append("wildcard is not distinct enough")
        }
        return warnings
    }

    static func commercialWarnings(board: StoryBeatBoard, setup: StorySetupDocument) -> [String] {
        var warnings: [String] = []
        let ctaTerms = ["buy", "subscribe", "sign up", "book now", "order", "call now", "get yours"]
        let directCTACount = board.beats.filter { beat in
            let text = [beat.title, beat.event, beat.voiceOrTextOverlay, beat.promptReadyLine].joined(separator: " ").lowercased()
            return ctaTerms.contains { text.contains($0) }
        }.count
        if directCTACount > 2 && setup.commercialPressure.scalar <= 0.75 {
            warnings.append("too many CTA beats for selected commercial pressure")
        }
        let title = board.title.lowercased()
        if title.contains("unlock your") || title.contains("transform your") || title.contains("solution for") {
            warnings.append("title reads like generic marketing copy")
        }
        return warnings
    }

    static func aestheticMismatchWarnings(board: StoryBeatBoard, cues: StoryAestheticCues) -> [String] {
        let narrativeCoverage = coverage(cues.narrativeCues, in: board.beats.flatMap(\.aestheticNarrativeBinding))
        let presentationCoverage = coverage(cues.presentationCues, in: board.beats.flatMap(\.aestheticPresentationBinding))
        var warnings: [String] = []
        if !cues.narrativeCues.isEmpty && narrativeCoverage < 0.25 {
            warnings.append("weak narrative aesthetic binding")
        }
        if !cues.presentationCues.isEmpty && presentationCoverage < 0.25 {
            warnings.append("weak presentation aesthetic binding")
        }
        return warnings
    }

    static func containsGenericSlop(_ value: String) -> Bool {
        let text = value.lowercased()
        return genericPhrases.contains { text.contains($0) }
    }

    private static func coverage(_ required: [String], in provided: [String]) -> Double {
        let requiredTokens = Set(required.flatMap(tokens))
        guard !requiredTokens.isEmpty else { return 1 }
        let providedTokens = Set(provided.flatMap(tokens))
        let hits = requiredTokens.intersection(providedTokens).count
        return Double(hits) / Double(requiredTokens.count)
    }

    private static func textOverlap(_ lhs: String, _ rhs: String) -> Double {
        let lhsTokens = Set(tokens(lhs))
        let rhsTokens = Set(tokens(rhs))
        guard !lhsTokens.isEmpty || !rhsTokens.isEmpty else { return 0 }
        let shared = lhsTokens.intersection(rhsTokens).count
        return Double(shared) / Double(max(lhsTokens.count, rhsTokens.count, 1))
    }

    private static func tokens(_ value: String) -> [String] {
        value
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 }
    }
}

enum StoryLocalDraftFactory {
    static func directionSet(
        projectId: String,
        projectName: String,
        fingerprint: StoryInputFingerprint,
        setup: StorySetupDocument,
        goalDigest: StoryGoalDigest,
        aestheticCues: StoryAestheticCues,
        patternMatches: [StoryPatternMatch],
        generatedAt: String
    ) -> StoryDirectionSet {
        let lanes = StoryDirectionLane.allCases
        let primaryPatterns = patternMatches.prefix(6).map(\.friendlyLabel)
        let titleBase = goalDigest.summary.isEmpty ? projectName : goalDigest.summary
        let cards = lanes.enumerated().map { index, lane in
            let engine = engineForLane(lane, setup: setup, matches: patternMatches)
            let directionId = "dir_\(shortHash("\(projectId):\(lane.rawValue):\(fingerprint.stableId):\(index)", length: 14))"
            let pressure: Double = lane == .commercial ? min(max(setup.commercialPressure.scalar, 0.35), 0.60) : setup.commercialPressure.scalar
            let weirdness: Double = lane == .wildcard ? 0.82 : (lane == .bolder ? 0.64 : 0.36)
            let title = localTitle(for: lane, titleBase: titleBase, engine: engine)
            var card = StoryDirectionCard(
                directionId: directionId,
                lane: lane,
                title: title,
                premise: localPremise(for: lane, goalDigest: goalDigest, engine: engine),
                storyEngine: engine,
                whatHappens: localWhatHappens(for: lane, matches: primaryPatterns, goalDigest: goalDigest),
                whyItWorks: "It binds the current Goal to \(primaryPatterns.prefix(3).joined(separator: ", ")) while staying prompt-ready from the enabled archive.",
                aestheticUse: StoryAestheticUse(
                    narrative: aestheticCues.narrativeCues.prefix(4).joined(separator: ", "),
                    presentation: aestheticCues.presentationCues.prefix(4).joined(separator: ", ")
                ),
                inventedElements: setup.inventionLevel == .lightInvention ? [] : ["story route", "warning copy"],
                risk: lane == .commercial ? "Can flatten into ad copy if the beats lose escalation." : "Needs concrete media evidence in each beat to avoid synopsis.",
                threeBeatPreview: previewBeats(for: engine),
                meaningMoves: Array(primaryPatterns.prefix(5)),
                commercialPressure: pressure,
                weirdness: weirdness,
                promptability: 0.72,
                scoreDebug: StoryDirectionScore(
                    goalFit: 0.7,
                    aestheticNarrativeFit: aestheticCues.narrativeCues.isEmpty ? 0.4 : 0.75,
                    aestheticPresentationFit: aestheticCues.presentationCues.isEmpty ? 0.4 : 0.75,
                    storySetupFit: 0.7,
                    patternSupport: patternMatches.isEmpty ? 0.35 : 0.7,
                    specificity: 0.62,
                    promptability: 0.72,
                    novelty: weirdness,
                    laneFit: 0.7,
                    commercialFit: lane == .commercial ? 0.72 : 0.3,
                    finalScore: 0.68
                )
            )
            card.validationWarnings = StoryValidation.directionWarnings(card)
            return card
        }

        let publicCards = publicStorylineCards(from: cards, setup: setup)
        return StoryDirectionSet(
            projectId: projectId,
            directionSetId: "directions_\(shortHash("\(projectId):\(fingerprint.stableId):\(generatedAt)", length: 14))",
            inputFingerprint: fingerprint,
            storySetupSnapshot: setup,
            candidateDirections: cards,
            directions: publicCards,
            selectedDirectionId: publicCards.first?.directionId ?? "",
            status: "local_draft",
            generatedAt: generatedAt,
            updatedAt: generatedAt,
            generator: "local_pattern_index",
            artifactStatus: .fresh
        )
    }

    static func beatBoard(
        projectId: String,
        directionSetId: String,
        direction: StoryDirectionCard,
        fingerprint: StoryInputFingerprint,
        setup: StorySetupDocument,
        aestheticCues: StoryAestheticCues,
        generatedAt: String
    ) -> StoryBeatBoard {
        let functions = direction.threeBeatPreview.isEmpty
            ? previewBeats(for: direction.storyEngine)
            : direction.threeBeatPreview
        let expandedFunctions = Array((functions + ["Escalation", "Public breach", "Final image"]).prefix(6))
        let boardId = "board_\(shortHash("\(projectId):\(direction.directionId):\(fingerprint.stableId):\(generatedAt)", length: 14))"
        let beats = expandedFunctions.enumerated().map { index, function in
            localBeat(
                projectId: projectId,
                boardId: boardId,
                direction: direction,
                function: function,
                index: index,
                aestheticCues: aestheticCues
            )
        }
        var board = StoryBeatBoard(
            projectId: projectId,
            beatBoardId: boardId,
            parentDirectionSetId: directionSetId,
            parentDirectionId: direction.directionId,
            storySetupHash: fingerprint.storySetupHash,
            aestheticRecipeVersion: fingerprint.chosenRecipeVersion,
            inputFingerprint: fingerprint,
            title: direction.title,
            logline: direction.premise,
            centralTension: direction.meaningMoves.first ?? "ordinary surface vs hidden meaning",
            storyEngine: direction.storyEngine,
            format: setup.outputType.rawValue,
            targetDuration: "60-90 seconds",
            beginningState: "The archive appears ordinary.",
            endingState: "The final image changes what the earlier images meant.",
            aestheticStrategy: StoryBeatBoardAestheticStrategy(
                narrative: direction.aestheticUse.narrative,
                presentation: direction.aestheticUse.presentation
            ),
            beats: beats,
            status: "local_draft",
            generatedAt: generatedAt,
            updatedAt: generatedAt,
            generator: "local_pattern_index",
            artifactStatus: .fresh
        )
        board.primaryDirectionId = direction.directionId
        board.sourceDirectionIds = [direction.directionId]
        board.validationWarnings = StoryValidation.commercialWarnings(board: board, setup: setup)
            + StoryValidation.aestheticMismatchWarnings(board: board, cues: aestheticCues)
        return board
    }

    private static func publicStorylineCards(from cards: [StoryDirectionCard], setup: StorySetupDocument) -> [StoryDirectionCard] {
        let sorted = cards.sorted { $0.scoreDebug.finalScore > $1.scoreDebug.finalScore }
        var selected: [StoryDirectionCard] = []
        func appendBest(_ predicate: (StoryDirectionCard) -> Bool) {
            guard selected.count < 3,
                  let card = sorted.first(where: { candidate in
                      predicate(candidate) && !selected.contains(where: { $0.directionId == candidate.directionId })
                  }) else {
                return
            }
            selected.append(card)
        }

        if let recommended = sorted.first(where: { $0.lane == .recommended }) {
            selected.append(recommended)
        }
        appendBest { $0.lane == .bolder }
        if setup.commercialPressure != .none {
            appendBest { $0.lane == .commercial }
        }
        appendBest { $0.lane == .wildcard }
        for card in sorted where selected.count < 3 && !selected.contains(where: { $0.directionId == card.directionId }) {
            if setup.commercialPressure == .none, card.lane == .commercial {
                continue
            }
            selected.append(card)
        }
        return selected.prefix(3).map { card in
            var updated = card
            updated.enabled = true
            return updated
        }
    }

    private static func engineForLane(
        _ lane: StoryDirectionLane,
        setup: StorySetupDocument,
        matches: [StoryPatternMatch]
    ) -> String {
        if setup.customStoryEngineOption.hasContent {
            return setup.effectiveStoryEngineLabel
        }
        if setup.storyEngine != .auto {
            return setup.storyEngine.label
        }
        switch lane {
        case .recommended:
            return matches.first(where: { $0.kind == "story_engine" })?.friendlyLabel ?? "Evidence escalates"
        case .bolder:
            return "Domestic breach"
        case .commercial:
            return "Advertisement turns strange"
        case .wildcard:
            return "Ritual archive"
        }
    }

    private static func localTitle(for lane: StoryDirectionLane, titleBase: String, engine: String) -> String {
        switch lane {
        case .recommended: "The Proof Breaks Open"
        case .bolder: "They Were Already Inside"
        case .commercial: "The Mirror Test"
        case .wildcard: "The House Becomes an Archive"
        }
    }

    private static func localPremise(
        for lane: StoryDirectionLane,
        goalDigest: StoryGoalDigest,
        engine: String
    ) -> String {
        let base = goalDigest.desiredStoryResult.isEmpty ? goalDigest.summary : goalDigest.desiredStoryResult
        switch lane {
        case .recommended:
            return "A familiar archive begins as ordinary evidence, then \(engine.lowercased()) until the hidden story can no longer be dismissed. \(base)"
        case .bolder:
            return "The project declares the hidden conflict impossible while each image proves the opposite through stranger, more invented escalation. \(base)"
        case .commercial:
            return "A creator-friendly proof story uses ordinary tools and surfaces to show what viewers usually miss, without turning the sequence into a hard sell. \(base)"
        case .wildcard:
            return "The archive itself becomes the narrator, arranging repeated surfaces into a mythic record of what has been hidden in plain sight. \(base)"
        }
    }

    private static func localWhatHappens(
        for lane: StoryDirectionLane,
        matches: [String],
        goalDigest: StoryGoalDigest
    ) -> String {
        let moves = matches.isEmpty ? "ordinary objects, hidden proof, and a final image" : matches.joined(separator: ", ")
        return "The sequence starts with a readable hook, introduces a wrong detail, escalates through \(moves), then ends on a final image that reinterprets the earlier archive."
    }

    private static func previewBeats(for engine: String) -> [String] {
        let text = engine.lowercased()
        if text.contains("advertisement") {
            return ["Perfect claim", "Contradicting proof", "Final warning"]
        }
        if text.contains("domestic") {
            return ["Safe home", "First breach", "Room turns against itself"]
        }
        if text.contains("ritual") || text.contains("archive") {
            return ["Repeated sign", "Pattern awakens", "Archive speaks"]
        }
        return ["Hook image", "First anomaly", "First proof"]
    }

    private static func localBeat(
        projectId: String,
        boardId: String,
        direction: StoryDirectionCard,
        function: String,
        index: Int,
        aestheticCues: StoryAestheticCues
    ) -> StoryBeatBoardBeat {
        let order = index + 1
        let title = function
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        let treatment = aestheticCues.presentationCues.prefix(3).joined(separator: ", ")
        let narrative = aestheticCues.narrativeCues.prefix(3).joined(separator: ", ")
        let subject = direction.meaningMoves.first ?? "ordinary archive evidence"
        let action = order == 1
            ? "establishes the visible world before anything breaks"
            : "reveals a stronger contradiction in the evidence"
        let prompt = "\(subject), \(function.lowercased()), \(direction.storyEngine.lowercased()), \(treatment), concrete archive-based visual moment."
        let beat = StoryBeatBoardBeat(
            beatId: "beat_\(String(format: "%02d", order))_\(shortHash("\(boardId):\(function):\(order)", length: 8))",
            order: order,
            title: title,
            event: "The story beat \(action), using a specific visible object or surface as proof rather than abstract narration.",
            visualMoment: "A concrete archive frame is treated as \(function.lowercased()), with the visible surface carrying the turn instead of explanatory dialogue.",
            emotionalTurn: order == 1 ? "Ordinary confidence becomes curiosity." : "Curiosity becomes harder to dismiss.",
            meaningMove: direction.meaningMoves.dropFirst(index % max(direction.meaningMoves.count, 1)).first ?? "The proof gets harder to deny",
            storyFunction: function,
            aestheticNarrativeBinding: Array(aestheticCues.narrativeCues.prefix(4)),
            aestheticPresentationBinding: Array(aestheticCues.presentationCues.prefix(4)),
            promptReadyLine: prompt,
            generationBrief: StoryGenerationBrief(
                subject: subject,
                setting: "archive-native setting from enabled media",
                action: action,
                visualFocus: function,
                cameraOrFraming: "clear evidence frame, readable subject, sequence-strip composition",
                lighting: aestheticCues.paletteCues.prefix(3).joined(separator: ", "),
                aestheticTreatment: treatment,
                textOverlay: order == 1 ? "" : "THE PROOF GETS HARDER TO DENY",
                negativeConstraints: aestheticCues.avoidCues,
                assetTypeHints: ["image", "video", "audio"]
            ),
            voiceOrTextOverlay: order == 1 ? "" : "THE PROOF GETS HARDER TO DENY",
            inventedElements: direction.inventedElements,
            risks: [direction.risk],
            supportStatus: .storyPatternSupported,
            origin: .storyPatternIndex,
            meaningNodeRefs: [
                StoryGraphRef(
                    id: "local_\(shortHash(subject, length: 8))",
                    label: subject,
                    kind: "meaning_move",
                    source: "story_pattern_index",
                    confidence: 0.66
                )
            ],
            beatFunctionRefs: [
                StoryGraphRef(
                    id: stableSlug(function),
                    label: function,
                    kind: "beat_function",
                    source: "story_pattern_index",
                    confidence: 0.72
                )
            ],
            archetypalSituationRefs: [],
            lensRefs: [],
            graphSupportSummary: "Local draft uses \(direction.storyEngine), \(narrative), and \(treatment)."
        )
        var validated = beat
        validated.validationWarnings = StoryValidation.beatWarnings(beat)
        return validated
    }
}

private extension String {
    var trimmedWordCount: Int {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .split { $0.isWhitespace || $0.isNewline }
            .count
    }
}

extension Array {
    func prefixArray(_ maxLength: Int) -> [Element] {
        Array(prefix(maxLength))
    }
}
