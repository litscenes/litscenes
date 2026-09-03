import Foundation

enum AestheticDirectionSelectionConstants {
    static let evidenceProfileSchemaVersion = "litscenes.project_aesthetic_evidence.v0.2"
    static let evidenceProfileResponseSchemaVersion = "litscenes.project_aesthetic_evidence_response.v0.2"
    static let selectionSchemaVersion = "litscenes.aesthetic_direction_selection.v0.3"
    static let shortlistResponseSchemaVersion = "litscenes.aesthetic_direction_shortlist.v0.1"
    static let rankResponseSchemaVersion = "litscenes.aesthetic_direction_rank.v0.3"
}

enum AestheticDirectionSupportStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case archiveSupported = "archive_supported"
    case goalLedStretch = "goal_led_stretch"
    case conflictRisk = "conflict_risk"
    case exploratory

    var label: String {
        switch self {
        case .archiveSupported:
            return "Archive-supported"
        case .goalLedStretch:
            return "Goal-led stretch"
        case .conflictRisk:
            return "Conflict risk"
        case .exploratory:
            return "Exploratory"
        }
    }
}

struct ProjectAestheticEvidenceCoverage: Codable, Hashable, Sendable {
    var enabledItemCount: Int = 0
    var freshAnalyzedItemCount: Int = 0
    var goalOnlyGapCount: Int = 0
    var contradictionCount: Int = 0
}

struct ProjectAestheticEvidenceProfileResponse: Codable, Hashable, Sendable {
    var schemaVersion: String = AestheticDirectionSelectionConstants.evidenceProfileResponseSchemaVersion
    var summary: String = ""
    var archiveSubjects: [String] = []
    var archiveSettings: [String] = []
    var archiveMaterials: [String] = []
    var archivePaletteTerms: [String] = []
    var archiveMoodTerms: [String] = []
    var archiveMotifTerms: [String] = []
    var archivePlaceCues: [String] = []
    var archiveEraCues: [String] = []
    var archiveEnergyCues: [String] = []
    var archiveCompositionCues: [String] = []
    var archiveNegativeConstraints: [String] = []
    var goalVisualCues: [String] = []
    var goalWorldCues: [String] = []
    var goalTreatmentCues: [String] = []
    var goalPaletteTerms: [String] = []
    var goalMoodTerms: [String] = []
    var goalMotifTerms: [String] = []
    var goalPlaceCues: [String] = []
    var goalEraCues: [String] = []
    var goalEnergyCues: [String] = []
    var goalAvoidTerms: [String] = []
    var goalOnlyGaps: [String] = []
    var contradictions: [String] = []
}

struct ProjectAestheticEvidenceProfile: Codable, Hashable, Sendable {
    var schemaVersion: String = AestheticDirectionSelectionConstants.evidenceProfileSchemaVersion
    var projectId: String = ""
    var goalFingerprint: String = ""
    var analysisFingerprint: String = ""
    var indexVersion: String = ""
    var generatedAt: String = ""
    var status: String = "idle"
    var model: String = ""
    var responseId: String = ""
    var summary: String = ""
    var archiveSubjects: [String] = []
    var archiveSettings: [String] = []
    var archiveMaterials: [String] = []
    var archivePaletteTerms: [String] = []
    var archiveMoodTerms: [String] = []
    var archiveMotifTerms: [String] = []
    var archivePlaceCues: [String] = []
    var archiveEraCues: [String] = []
    var archiveEnergyCues: [String] = []
    var archiveCompositionCues: [String] = []
    var archiveNegativeConstraints: [String] = []
    var goalVisualCues: [String] = []
    var goalWorldCues: [String] = []
    var goalTreatmentCues: [String] = []
    var goalPaletteTerms: [String] = []
    var goalMoodTerms: [String] = []
    var goalMotifTerms: [String] = []
    var goalPlaceCues: [String] = []
    var goalEraCues: [String] = []
    var goalEnergyCues: [String] = []
    var goalAvoidTerms: [String] = []
    var goalOnlyGaps: [String] = []
    var contradictions: [String] = []
    var coverage: ProjectAestheticEvidenceCoverage = ProjectAestheticEvidenceCoverage()
    var errorMessage: String = ""

    init(
        schemaVersion: String = AestheticDirectionSelectionConstants.evidenceProfileSchemaVersion,
        projectId: String = "",
        goalFingerprint: String = "",
        analysisFingerprint: String = "",
        indexVersion: String = "",
        generatedAt: String = "",
        status: String = "idle",
        model: String = "",
        responseId: String = "",
        summary: String = "",
        archiveSubjects: [String] = [],
        archiveSettings: [String] = [],
        archiveMaterials: [String] = [],
        archivePaletteTerms: [String] = [],
        archiveMoodTerms: [String] = [],
        archiveMotifTerms: [String] = [],
        archivePlaceCues: [String] = [],
        archiveEraCues: [String] = [],
        archiveEnergyCues: [String] = [],
        archiveCompositionCues: [String] = [],
        archiveNegativeConstraints: [String] = [],
        goalVisualCues: [String] = [],
        goalWorldCues: [String] = [],
        goalTreatmentCues: [String] = [],
        goalPaletteTerms: [String] = [],
        goalMoodTerms: [String] = [],
        goalMotifTerms: [String] = [],
        goalPlaceCues: [String] = [],
        goalEraCues: [String] = [],
        goalEnergyCues: [String] = [],
        goalAvoidTerms: [String] = [],
        goalOnlyGaps: [String] = [],
        contradictions: [String] = [],
        coverage: ProjectAestheticEvidenceCoverage = ProjectAestheticEvidenceCoverage(),
        errorMessage: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.goalFingerprint = goalFingerprint
        self.analysisFingerprint = analysisFingerprint
        self.indexVersion = indexVersion
        self.generatedAt = generatedAt
        self.status = status
        self.model = model
        self.responseId = responseId
        self.summary = summary
        self.archiveSubjects = archiveSubjects
        self.archiveSettings = archiveSettings
        self.archiveMaterials = archiveMaterials
        self.archivePaletteTerms = archivePaletteTerms
        self.archiveMoodTerms = archiveMoodTerms
        self.archiveMotifTerms = archiveMotifTerms
        self.archivePlaceCues = archivePlaceCues
        self.archiveEraCues = archiveEraCues
        self.archiveEnergyCues = archiveEnergyCues
        self.archiveCompositionCues = archiveCompositionCues
        self.archiveNegativeConstraints = archiveNegativeConstraints
        self.goalVisualCues = goalVisualCues
        self.goalWorldCues = goalWorldCues
        self.goalTreatmentCues = goalTreatmentCues
        self.goalPaletteTerms = goalPaletteTerms
        self.goalMoodTerms = goalMoodTerms
        self.goalMotifTerms = goalMotifTerms
        self.goalPlaceCues = goalPlaceCues
        self.goalEraCues = goalEraCues
        self.goalEnergyCues = goalEnergyCues
        self.goalAvoidTerms = goalAvoidTerms
        self.goalOnlyGaps = goalOnlyGaps
        self.contradictions = contradictions
        self.coverage = coverage
        self.errorMessage = errorMessage
    }

    static func empty(projectId: String = "") -> ProjectAestheticEvidenceProfile {
        ProjectAestheticEvidenceProfile(projectId: projectId)
    }

    var fingerprint: String {
        shortHash([
            goalFingerprint,
            analysisFingerprint,
            indexVersion,
            archiveSubjects.joined(separator: "|"),
            goalVisualCues.joined(separator: "|"),
            goalTreatmentCues.joined(separator: "|"),
            goalWorldCues.joined(separator: "|"),
        ].joined(separator: "\n"), length: 20)
    }

    var isReady: Bool {
        status == "ready" && errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func matches(goalFingerprint: String, analysisFingerprint: String, indexVersion: String) -> Bool {
        self.goalFingerprint == goalFingerprint
            && self.analysisFingerprint == analysisFingerprint
            && self.indexVersion == indexVersion
            && isReady
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case goalFingerprint
        case analysisFingerprint
        case indexVersion
        case generatedAt
        case status
        case model
        case responseId
        case summary
        case archiveSubjects
        case archiveSettings
        case archiveMaterials
        case archivePaletteTerms
        case archiveMoodTerms
        case archiveMotifTerms
        case archivePlaceCues
        case archiveEraCues
        case archiveEnergyCues
        case archiveCompositionCues
        case archiveNegativeConstraints
        case goalVisualCues
        case goalWorldCues
        case goalTreatmentCues
        case goalPaletteTerms
        case goalMoodTerms
        case goalMotifTerms
        case goalPlaceCues
        case goalEraCues
        case goalEnergyCues
        case goalAvoidTerms
        case goalOnlyGaps
        case contradictions
        case coverage
        case errorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? AestheticDirectionSelectionConstants.evidenceProfileSchemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        goalFingerprint = try container.decodeIfPresent(String.self, forKey: .goalFingerprint) ?? ""
        analysisFingerprint = try container.decodeIfPresent(String.self, forKey: .analysisFingerprint) ?? ""
        indexVersion = try container.decodeIfPresent(String.self, forKey: .indexVersion) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "idle"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        responseId = try container.decodeIfPresent(String.self, forKey: .responseId) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
        archiveSubjects = try container.decodeIfPresent([String].self, forKey: .archiveSubjects) ?? []
        archiveSettings = try container.decodeIfPresent([String].self, forKey: .archiveSettings) ?? []
        archiveMaterials = try container.decodeIfPresent([String].self, forKey: .archiveMaterials) ?? []
        archivePaletteTerms = try container.decodeIfPresent([String].self, forKey: .archivePaletteTerms) ?? []
        archiveMoodTerms = try container.decodeIfPresent([String].self, forKey: .archiveMoodTerms) ?? []
        archiveMotifTerms = try container.decodeIfPresent([String].self, forKey: .archiveMotifTerms) ?? []
        archivePlaceCues = try container.decodeIfPresent([String].self, forKey: .archivePlaceCues) ?? []
        archiveEraCues = try container.decodeIfPresent([String].self, forKey: .archiveEraCues) ?? []
        archiveEnergyCues = try container.decodeIfPresent([String].self, forKey: .archiveEnergyCues) ?? []
        archiveCompositionCues = try container.decodeIfPresent([String].self, forKey: .archiveCompositionCues) ?? []
        archiveNegativeConstraints = try container.decodeIfPresent([String].self, forKey: .archiveNegativeConstraints) ?? []
        goalVisualCues = try container.decodeIfPresent([String].self, forKey: .goalVisualCues) ?? []
        goalWorldCues = try container.decodeIfPresent([String].self, forKey: .goalWorldCues) ?? []
        goalTreatmentCues = try container.decodeIfPresent([String].self, forKey: .goalTreatmentCues) ?? []
        goalPaletteTerms = try container.decodeIfPresent([String].self, forKey: .goalPaletteTerms) ?? []
        goalMoodTerms = try container.decodeIfPresent([String].self, forKey: .goalMoodTerms) ?? []
        goalMotifTerms = try container.decodeIfPresent([String].self, forKey: .goalMotifTerms) ?? []
        goalPlaceCues = try container.decodeIfPresent([String].self, forKey: .goalPlaceCues) ?? []
        goalEraCues = try container.decodeIfPresent([String].self, forKey: .goalEraCues) ?? []
        goalEnergyCues = try container.decodeIfPresent([String].self, forKey: .goalEnergyCues) ?? []
        goalAvoidTerms = try container.decodeIfPresent([String].self, forKey: .goalAvoidTerms) ?? []
        goalOnlyGaps = try container.decodeIfPresent([String].self, forKey: .goalOnlyGaps) ?? []
        contradictions = try container.decodeIfPresent([String].self, forKey: .contradictions) ?? []
        coverage = try container.decodeIfPresent(ProjectAestheticEvidenceCoverage.self, forKey: .coverage) ?? ProjectAestheticEvidenceCoverage()
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
    }
}

struct AestheticDirectionShortlistChoice: Codable, Hashable, Sendable {
    var aestheticId: String
    var rationale: String = ""
}

struct AestheticDirectionShortlistResponse: Codable, Hashable, Sendable {
    var schemaVersion: String = AestheticDirectionSelectionConstants.shortlistResponseSchemaVersion
    var candidates: [AestheticDirectionShortlistChoice] = []
}

struct AestheticDirectionRankedChoice: Codable, Hashable, Sendable {
    var primaryAestheticId: String
    var supportingAestheticIds: [String] = []
    var visualSummary: String = ""
    var treatmentNotes: [String] = []
    var bestAppliedTo: [String] = []
    var fitReason: String = ""
    var supportStatus: AestheticDirectionSupportStatus = .archiveSupported
    var supportNote: String = ""
    var evidence: [String] = []
    var gaps: [String] = []
    var conflicts: [String] = []

    private enum CodingKeys: String, CodingKey {
        case primaryAestheticId
        case supportingAestheticIds
        case visualSummary
        case treatmentNotes
        case bestAppliedTo
        case fitReason
        case supportStatus
        case supportNote
        case evidence
        case gaps
        case conflicts
        case title
        case makesFeelLike
        case adds
        case bestFor
        case whyThisRoute
    }

    init(
        primaryAestheticId: String,
        supportingAestheticIds: [String] = [],
        visualSummary: String = "",
        treatmentNotes: [String] = [],
        bestAppliedTo: [String] = [],
        fitReason: String = "",
        supportStatus: AestheticDirectionSupportStatus = .archiveSupported,
        supportNote: String = "",
        evidence: [String] = [],
        gaps: [String] = [],
        conflicts: [String] = []
    ) {
        self.primaryAestheticId = primaryAestheticId
        self.supportingAestheticIds = supportingAestheticIds
        self.visualSummary = visualSummary
        self.treatmentNotes = treatmentNotes
        self.bestAppliedTo = bestAppliedTo
        self.fitReason = fitReason
        self.supportStatus = supportStatus
        self.supportNote = supportNote
        self.evidence = evidence
        self.gaps = gaps
        self.conflicts = conflicts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryAestheticId = try container.decode(String.self, forKey: .primaryAestheticId)
        supportingAestheticIds = try container.decodeIfPresent([String].self, forKey: .supportingAestheticIds) ?? []
        visualSummary = try container.decodeIfPresent(String.self, forKey: .visualSummary)
            ?? container.decodeIfPresent(String.self, forKey: .makesFeelLike)
            ?? ""
        treatmentNotes = try container.decodeIfPresent([String].self, forKey: .treatmentNotes)
            ?? container.decodeIfPresent([String].self, forKey: .adds)
            ?? []
        bestAppliedTo = try container.decodeIfPresent([String].self, forKey: .bestAppliedTo)
            ?? container.decodeIfPresent([String].self, forKey: .bestFor)
            ?? []
        fitReason = try container.decodeIfPresent(String.self, forKey: .fitReason)
            ?? container.decodeIfPresent(String.self, forKey: .whyThisRoute)
            ?? ""
        supportStatus = try container.decodeIfPresent(AestheticDirectionSupportStatus.self, forKey: .supportStatus) ?? .archiveSupported
        supportNote = try container.decodeIfPresent(String.self, forKey: .supportNote) ?? ""
        evidence = try container.decodeIfPresent([String].self, forKey: .evidence) ?? []
        gaps = try container.decodeIfPresent([String].self, forKey: .gaps) ?? []
        conflicts = try container.decodeIfPresent([String].self, forKey: .conflicts) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(primaryAestheticId, forKey: .primaryAestheticId)
        try container.encode(supportingAestheticIds, forKey: .supportingAestheticIds)
        try container.encode(visualSummary, forKey: .visualSummary)
        try container.encode(treatmentNotes, forKey: .treatmentNotes)
        try container.encode(bestAppliedTo, forKey: .bestAppliedTo)
        try container.encode(fitReason, forKey: .fitReason)
        try container.encode(supportStatus, forKey: .supportStatus)
        try container.encode(supportNote, forKey: .supportNote)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(gaps, forKey: .gaps)
        try container.encode(conflicts, forKey: .conflicts)
    }
}

struct AestheticDirectionRankResponse: Codable, Hashable, Sendable {
    var schemaVersion: String = AestheticDirectionSelectionConstants.rankResponseSchemaVersion
    var directions: [AestheticDirectionRankedChoice] = []
}

struct AestheticDirectionSelectionDirection: Codable, Identifiable, Hashable, Sendable {
    var routeKey: String
    var id: String { routeKey }
    var rank: Int = 0
    var primaryAestheticId: String
    var supportingAestheticIds: [String] = []
    var directionLabel: String = ""
    var visualSummary: String = ""
    var treatmentNotes: [String] = []
    var bestAppliedTo: [String] = []
    var fitReason: String = ""
    var supportStatus: AestheticDirectionSupportStatus = .archiveSupported
    var supportNote: String = ""
    var evidence: [String] = []
    var gaps: [String] = []
    var conflicts: [String] = []
    var isFavorite: Bool = false
    var updatedAt: String = DateFormats.now()

    var isHero: Bool {
        rank > 0 && rank <= 3
    }

    var laneLabel: String {
        isHero ? "Rank \(rank)" : "Aligned Alternative"
    }

    private enum CodingKeys: String, CodingKey {
        case routeKey
        case rank
        case primaryAestheticId
        case supportingAestheticIds
        case directionLabel
        case visualSummary
        case treatmentNotes
        case bestAppliedTo
        case fitReason
        case supportStatus
        case supportNote
        case evidence
        case gaps
        case conflicts
        case isFavorite
        case updatedAt
        case title
        case makesFeelLike
        case adds
        case bestFor
        case whyThisRoute
    }

    init(
        routeKey: String,
        rank: Int = 0,
        primaryAestheticId: String,
        supportingAestheticIds: [String] = [],
        directionLabel: String = "",
        visualSummary: String = "",
        treatmentNotes: [String] = [],
        bestAppliedTo: [String] = [],
        fitReason: String = "",
        supportStatus: AestheticDirectionSupportStatus = .archiveSupported,
        supportNote: String = "",
        evidence: [String] = [],
        gaps: [String] = [],
        conflicts: [String] = [],
        isFavorite: Bool = false,
        updatedAt: String = DateFormats.now()
    ) {
        self.routeKey = routeKey
        self.rank = rank
        self.primaryAestheticId = primaryAestheticId
        self.supportingAestheticIds = supportingAestheticIds
        self.directionLabel = directionLabel
        self.visualSummary = visualSummary
        self.treatmentNotes = treatmentNotes
        self.bestAppliedTo = bestAppliedTo
        self.fitReason = fitReason
        self.supportStatus = supportStatus
        self.supportNote = supportNote
        self.evidence = evidence
        self.gaps = gaps
        self.conflicts = conflicts
        self.isFavorite = isFavorite
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        routeKey = try container.decode(String.self, forKey: .routeKey)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank) ?? 0
        primaryAestheticId = try container.decode(String.self, forKey: .primaryAestheticId)
        supportingAestheticIds = try container.decodeIfPresent([String].self, forKey: .supportingAestheticIds) ?? []
        directionLabel = try container.decodeIfPresent(String.self, forKey: .directionLabel) ?? ""
        visualSummary = try container.decodeIfPresent(String.self, forKey: .visualSummary)
            ?? container.decodeIfPresent(String.self, forKey: .makesFeelLike)
            ?? ""
        treatmentNotes = try container.decodeIfPresent([String].self, forKey: .treatmentNotes)
            ?? container.decodeIfPresent([String].self, forKey: .adds)
            ?? []
        bestAppliedTo = try container.decodeIfPresent([String].self, forKey: .bestAppliedTo)
            ?? container.decodeIfPresent([String].self, forKey: .bestFor)
            ?? []
        fitReason = try container.decodeIfPresent(String.self, forKey: .fitReason)
            ?? container.decodeIfPresent(String.self, forKey: .whyThisRoute)
            ?? ""
        supportStatus = try container.decodeIfPresent(AestheticDirectionSupportStatus.self, forKey: .supportStatus) ?? .archiveSupported
        supportNote = try container.decodeIfPresent(String.self, forKey: .supportNote) ?? ""
        evidence = try container.decodeIfPresent([String].self, forKey: .evidence) ?? []
        gaps = try container.decodeIfPresent([String].self, forKey: .gaps) ?? []
        conflicts = try container.decodeIfPresent([String].self, forKey: .conflicts) ?? []
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(routeKey, forKey: .routeKey)
        try container.encode(rank, forKey: .rank)
        try container.encode(primaryAestheticId, forKey: .primaryAestheticId)
        try container.encode(supportingAestheticIds, forKey: .supportingAestheticIds)
        try container.encode(directionLabel, forKey: .directionLabel)
        try container.encode(visualSummary, forKey: .visualSummary)
        try container.encode(treatmentNotes, forKey: .treatmentNotes)
        try container.encode(bestAppliedTo, forKey: .bestAppliedTo)
        try container.encode(fitReason, forKey: .fitReason)
        try container.encode(supportStatus, forKey: .supportStatus)
        try container.encode(supportNote, forKey: .supportNote)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(gaps, forKey: .gaps)
        try container.encode(conflicts, forKey: .conflicts)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct AestheticDirectionSelectionDocument: Codable, Hashable, Sendable {
    static let maximumDirectionCount = 20

    var schemaVersion: String = AestheticDirectionSelectionConstants.selectionSchemaVersion
    var projectId: String = ""
    var goalFingerprint: String = ""
    var analysisFingerprint: String = ""
    var evidenceFingerprint: String = ""
    var indexVersion: String = ""
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()
    var status: String = "idle"
    var model: String = ""
    var responseId: String = ""
    var retrievedAestheticIds: [String] = []
    var directions: [AestheticDirectionSelectionDirection] = []
    var stale: Bool = false
    var errorMessage: String = ""

    static func empty(projectId: String = "") -> AestheticDirectionSelectionDocument {
        AestheticDirectionSelectionDocument(projectId: projectId)
    }

    var heroDirections: [AestheticDirectionSelectionDirection] {
        directions.filter(\.isHero).sorted { $0.rank < $1.rank }
    }

    var alternativeDirections: [AestheticDirectionSelectionDirection] {
        directions.filter { !$0.isHero }
    }

    var isReady: Bool {
        status == "ready"
            && !directions.isEmpty
            && errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isUsable: Bool {
        (status == "ready" || status == "partial")
            && !directions.isEmpty
            && errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canHydrateMoreDirections: Bool {
        !retrievedAestheticIds.isEmpty && directions.count < min(Self.maximumDirectionCount, retrievedAestheticIds.count)
    }

    func matches(
        goalFingerprint: String,
        analysisFingerprint: String,
        evidenceFingerprint: String,
        indexVersion: String
    ) -> Bool {
        self.goalFingerprint == goalFingerprint
            && self.analysisFingerprint == analysisFingerprint
            && self.evidenceFingerprint == evidenceFingerprint
            && self.indexVersion == indexVersion
            && isUsable
    }

    func direction(routeKey: String) -> AestheticDirectionSelectionDirection? {
        directions.first { $0.routeKey == routeKey }
    }
}

struct OpenAIAestheticEvidenceProfileResult: Sendable {
    var profile: ProjectAestheticEvidenceProfileResponse
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIAestheticDirectionShortlistResult: Sendable {
    var shortlist: AestheticDirectionShortlistResponse
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIAestheticDirectionRankResult: Sendable {
    var ranking: AestheticDirectionRankResponse
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct ProjectAestheticEvidenceGenerationContext {
    var projectId: String
    var projectName: String
    var goalBriefSummary: String
    var aestheticIntentSummary: String
    var mediaObservationSummary: String
    var enabledItemCount: Int
    var analyzedItemCount: Int
    var generatedAt: String
}

struct AestheticDirectionShortlistContext {
    var projectId: String
    var projectName: String
    var goalBriefSummary: String
    var evidenceProfileJSON: String
    var lensContextJSON: String = ""
    var indexVersion: String
    var retrievedCandidateSummary: String
    var generatedAt: String
}

struct AestheticDirectionRankContext {
    var projectId: String
    var projectName: String
    var goalBriefSummary: String
    var evidenceProfileJSON: String
    var lensContextJSON: String = ""
    var indexVersion: String
    var shortlistJSON: String
    var shortlistedDetailSummary: String
    var rankStart: Int = 1
    var requestedPrimaryAestheticIds: [String] = []
    var existingDirectionSummary: String = ""
    var generatedAt: String
}

struct GoalStyleTaxonomyRefsContext: Sendable {
    var projectId: String
    var goalSummary: String
    var moods: [String]
    var hues: [String]
    var collections: [StyleBrowseCollection]
    var mediums: [String]
}

struct GoalStyleTaxonomyRefsResponse: Codable, Hashable, Sendable {
    var schemaVersion: String = "litscenes.goal_style_taxonomy_refs.v0.1"
    var styleTermRefs: [ProjectGoalStyleTermRef] = []
}

struct OpenAIGoalStyleTaxonomyRefsResult: Sendable {
    var refs: [ProjectGoalStyleTermRef]
    var responseId: String
    var model: String
    var usage: OpenAIUsage
}

struct LensTrioContext: Sendable {
    var projectId: String
    var projectName: String
    var goalSummary: String
    var meaningContext: String
    var slateLines: [String]
    var validationError: String = ""
    /// Existing project roster characters as "Name — description" lines; when present the
    /// composition model casts them by exact name so cast_members auto-link to the roster.
    var rosterCharacterLines: [String] = []
    /// Content-only observations of the analyzed Story Input media — subject matter the
    /// composition may build on, never style words.
    var mediaObservationLines: [String] = []
}

struct LensTrioSliceResponse: Codable, Hashable, Sendable {
    var sliceTitle: String = ""
    var sliceIntent: String = ""
    var title: String = ""
    var claim: String = ""
    var visualSummary: String = ""
    var look: String = ""
    var palette: [String] = []
    var materials: [String] = []
    var motifs: [String] = []
    var composition: [String] = []
    var pacingEnergy: [String] = []
    var avoid: [String] = []
    var mustPreserve: [String] = []
    var mustAvoid: [String] = []
    var characterImagePrompts: [String] = []
    var sceneImagePrompts: [String] = []
    var objectImagePrompts: [String] = []
    var setDressingImagePrompts: [String] = []
    var castMembers: [LensTrioCastMemberResponse] = []
    var suggestedMediaPlan: LensTrioMediaPlanResponse?
    var sceneSettings: [LensSceneSetting] = []
    var areas: [LensArea] = []
    var objectConcepts: [LensObjectConcept] = []
    var setDressing: [String] = []
    var primaryStyleIndex: Int = -1
    var accentStyleIndexes: [Int] = []
    var blendProfile: String = "dominant"
    var styleRationale: String = ""

    init() {}

    private enum CodingKeys: String, CodingKey {
        case sliceTitle
        case sliceIntent
        case title
        case claim
        case visualSummary
        case look
        case palette
        case materials
        case motifs
        case composition
        case pacingEnergy
        case avoid
        case mustPreserve
        case mustAvoid
        case characterImagePrompts
        case sceneImagePrompts
        case objectImagePrompts
        case setDressingImagePrompts
        case castMembers
        case suggestedMediaPlan
        case sceneSettings
        case areas
        case objectConcepts
        case setDressing
        case primaryStyleIndex
        case accentStyleIndexes
        case blendProfile
        case styleRationale
    }

    /// Tolerant decoding: the composition schema intentionally omits trio-era fields
    /// (slice_title/slice_intent), and synthesized decoding would fail on any absent key.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sliceTitle = try container.decodeIfPresent(String.self, forKey: .sliceTitle) ?? ""
        sliceIntent = try container.decodeIfPresent(String.self, forKey: .sliceIntent) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        claim = try container.decodeIfPresent(String.self, forKey: .claim) ?? ""
        visualSummary = try container.decodeIfPresent(String.self, forKey: .visualSummary) ?? ""
        look = try container.decodeIfPresent(String.self, forKey: .look) ?? ""
        palette = try container.decodeIfPresent([String].self, forKey: .palette) ?? []
        materials = try container.decodeIfPresent([String].self, forKey: .materials) ?? []
        motifs = try container.decodeIfPresent([String].self, forKey: .motifs) ?? []
        composition = try container.decodeIfPresent([String].self, forKey: .composition) ?? []
        pacingEnergy = try container.decodeIfPresent([String].self, forKey: .pacingEnergy) ?? []
        avoid = try container.decodeIfPresent([String].self, forKey: .avoid) ?? []
        mustPreserve = try container.decodeIfPresent([String].self, forKey: .mustPreserve) ?? []
        mustAvoid = try container.decodeIfPresent([String].self, forKey: .mustAvoid) ?? []
        characterImagePrompts = try container.decodeIfPresent([String].self, forKey: .characterImagePrompts) ?? []
        sceneImagePrompts = try container.decodeIfPresent([String].self, forKey: .sceneImagePrompts) ?? []
        objectImagePrompts = try container.decodeIfPresent([String].self, forKey: .objectImagePrompts) ?? []
        setDressingImagePrompts = try container.decodeIfPresent([String].self, forKey: .setDressingImagePrompts) ?? []
        castMembers = try container.decodeIfPresent([LensTrioCastMemberResponse].self, forKey: .castMembers) ?? []
        suggestedMediaPlan = try container.decodeIfPresent(LensTrioMediaPlanResponse.self, forKey: .suggestedMediaPlan)
        sceneSettings = try container.decodeIfPresent([LensSceneSetting].self, forKey: .sceneSettings) ?? []
        areas = try container.decodeIfPresent([LensArea].self, forKey: .areas) ?? []
        objectConcepts = try container.decodeIfPresent([LensObjectConcept].self, forKey: .objectConcepts) ?? []
        setDressing = try container.decodeIfPresent([String].self, forKey: .setDressing) ?? []
        primaryStyleIndex = try container.decodeIfPresent(Int.self, forKey: .primaryStyleIndex) ?? -1
        accentStyleIndexes = try container.decodeIfPresent([Int].self, forKey: .accentStyleIndexes) ?? []
        blendProfile = try container.decodeIfPresent(String.self, forKey: .blendProfile) ?? "dominant"
        styleRationale = try container.decodeIfPresent(String.self, forKey: .styleRationale) ?? ""
    }
}

/// A named recurring character proposed by the composition model (v0.2+).
struct LensTrioCastMemberResponse: Codable, Hashable, Sendable {
    var name: String = ""
    var description: String = ""
    var signatureProps: [String] = []
    var environmentAffinity: String = ""

    init() {}

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case signatureProps
        case environmentAffinity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        signatureProps = try container.decodeIfPresent([String].self, forKey: .signatureProps) ?? []
        environmentAffinity = try container.decodeIfPresent(String.self, forKey: .environmentAffinity) ?? ""
    }
}

/// The media plan the composition model proposes from the goal (v0.2+); the user owns it
/// after generation.
struct LensTrioMediaPlanResponse: Codable, Hashable, Sendable {
    var mode: String = "collection"
    var aspect: String = "square"
    var characterCount: Int = 1
    var castObjectCount: Int = 1
    var setDressingDensity: String = "standard"
    var allowReadableText: Bool = false
    var sequenceBeats: [String] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case mode
        case aspect
        case characterCount
        case castObjectCount
        case setDressingDensity
        case allowReadableText
        case sequenceBeats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "collection"
        aspect = try container.decodeIfPresent(String.self, forKey: .aspect) ?? "square"
        characterCount = try container.decodeIfPresent(Int.self, forKey: .characterCount) ?? 1
        castObjectCount = try container.decodeIfPresent(Int.self, forKey: .castObjectCount) ?? 1
        setDressingDensity = try container.decodeIfPresent(String.self, forKey: .setDressingDensity) ?? "standard"
        allowReadableText = try container.decodeIfPresent(Bool.self, forKey: .allowReadableText) ?? false
        sequenceBeats = try container.decodeIfPresent([String].self, forKey: .sequenceBeats) ?? []
    }

    /// The concrete LensMediaPlan this suggestion resolves to (clamped).
    var mediaPlan: LensMediaPlan {
        var plan = LensMediaPlan()
        plan.mode = mode
        plan.aspect = aspect
        plan.characterCount = characterCount
        plan.castObjectCount = castObjectCount
        plan.setDressingDensity = setDressingDensity
        plan.allowReadableText = allowReadableText
        plan.sequenceBeats = sequenceBeats
        if plan.mode == "sequence", !plan.sequenceBeats.isEmpty {
            plan.compositeCount = min(6, max(1, plan.sequenceBeats.count))
        }
        return plan.normalized()
    }
}

struct LensTrioResponse: Codable, Hashable, Sendable {
    var schemaVersion: String = "litscenes.lens_composition.v0.1"
    var lenses: [LensTrioSliceResponse] = []
}

struct OpenAILensTrioResult: Sendable {
    var trio: LensTrioResponse
    var responseId: String
    var model: String
    var usage: OpenAIUsage
}

enum LensTrioBlendProfile: String, CaseIterable, Sendable {
    case dominant
    case anchored
    case ensemble

    var weights: (primary: Int, accentOne: Int, accentTwo: Int) {
        switch self {
        case .dominant: return (60, 25, 15)
        case .anchored: return (50, 25, 25)
        case .ensemble: return (40, 30, 30)
        }
    }
}

struct LensCompositionResponse: Codable, Hashable, Sendable {
    var schemaVersion: String = "litscenes.lens_composition.v0.6"
    var lens: LensTrioSliceResponse = LensTrioSliceResponse()
}

struct OpenAILensCompositionResult: Sendable {
    var composition: LensCompositionResponse
    var responseId: String
    var model: String
    var usage: OpenAIUsage
}
