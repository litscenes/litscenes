import Foundation

enum ProjectLensContextStatus: String, Codable, Hashable, Sendable {
    case missing
    case ready
    case failed
}

struct LensContextResolveLimits: Codable, Hashable, Sendable {
    var meaningEdgeNeighbors: Int = 24
    var meaningEvidence: Int = 16
    var perNodeEvidence: Int = 2
    var aestheticCandidates: Int = 8
    var styleCandidates: Int = 45
}

struct LensContextResolveRequest: Codable, Hashable, Sendable {
    var projectId: String
    var goalFingerprint: String
    var meaningNodeRefs: [ProjectGoalMeaningNodeRef]
    var aestheticTermRefs: [ProjectGoalAestheticTermRef]
    var styleTermRefs: [ProjectGoalStyleTermRef] = []
    var limits: LensContextResolveLimits
}

struct LensContextResolveResponse: Codable, Hashable, Sendable {
    var schemaVersion: String
    var userId: String
    var projectId: String
    var goalFingerprint: String
    var selectedMeaningNodes: [LensContextMeaningNode]
    var meaningEdgeNeighbors: [LensContextMeaningEdgeNeighbor]
    var meaningEvidence: [LensContextMeaningEvidence]
    var aestheticCandidates: [LensContextAestheticCandidate]
    var styleCandidates: [LensContextStyleCandidate]
    var warnings: [String]
    var queryStats: LensContextQueryStats

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case userId
        case projectId
        case goalFingerprint
        case selectedMeaningNodes
        case meaningEdgeNeighbors
        case meaningEvidence
        case aestheticCandidates
        case styleCandidates
        case warnings
        case queryStats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = container.lensContextString(forKey: .schemaVersion)
        userId = container.lensContextString(forKey: .userId)
        projectId = container.lensContextString(forKey: .projectId)
        goalFingerprint = container.lensContextString(forKey: .goalFingerprint)
        selectedMeaningNodes = container
            .lensContextLossyArray(LensContextMeaningNode.self, forKey: .selectedMeaningNodes)
            .filter(\.isUsable)
        meaningEdgeNeighbors = container
            .lensContextLossyArray(LensContextMeaningEdgeNeighbor.self, forKey: .meaningEdgeNeighbors)
            .filter(\.isUsable)
        meaningEvidence = container
            .lensContextLossyArray(LensContextMeaningEvidence.self, forKey: .meaningEvidence)
            .filter(\.isUsable)
        aestheticCandidates = container
            .lensContextLossyArray(LensContextAestheticCandidate.self, forKey: .aestheticCandidates)
            .filter(\.isUsable)
        styleCandidates = container
            .lensContextLossyArray(LensContextStyleCandidate.self, forKey: .styleCandidates)
            .filter(\.isUsable)
        warnings = container.lensContextStringArray(forKey: .warnings)
        queryStats = container.lensContextValue(LensContextQueryStats.self, forKey: .queryStats)
            ?? LensContextQueryStats(
                durationMs: 0,
                meaningRefCount: selectedMeaningNodes.count,
                resolvedMeaningNodeCount: selectedMeaningNodes.count,
                meaningEdgeNeighborCount: meaningEdgeNeighbors.count,
                meaningEvidenceCount: meaningEvidence.count,
                aestheticTermRefCount: aestheticCandidates.reduce(0) { $0 + $1.matchedTerms.count },
                aestheticCandidateCount: aestheticCandidates.count
            )
    }
}

struct LensContextQueryStats: Codable, Hashable, Sendable {
    var durationMs: Int
    var meaningRefCount: Int
    var resolvedMeaningNodeCount: Int
    var meaningEdgeNeighborCount: Int
    var meaningEvidenceCount: Int
    var aestheticTermRefCount: Int
    var aestheticCandidateCount: Int

    init(
        durationMs: Int = 0,
        meaningRefCount: Int = 0,
        resolvedMeaningNodeCount: Int = 0,
        meaningEdgeNeighborCount: Int = 0,
        meaningEvidenceCount: Int = 0,
        aestheticTermRefCount: Int = 0,
        aestheticCandidateCount: Int = 0
    ) {
        self.durationMs = durationMs
        self.meaningRefCount = meaningRefCount
        self.resolvedMeaningNodeCount = resolvedMeaningNodeCount
        self.meaningEdgeNeighborCount = meaningEdgeNeighborCount
        self.meaningEvidenceCount = meaningEvidenceCount
        self.aestheticTermRefCount = aestheticTermRefCount
        self.aestheticCandidateCount = aestheticCandidateCount
    }

    private enum CodingKeys: String, CodingKey {
        case durationMs
        case meaningRefCount
        case resolvedMeaningNodeCount
        case meaningEdgeNeighborCount
        case meaningEvidenceCount
        case aestheticTermRefCount
        case aestheticCandidateCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        durationMs = container.lensContextInt(forKey: .durationMs)
        meaningRefCount = container.lensContextInt(forKey: .meaningRefCount)
        resolvedMeaningNodeCount = container.lensContextInt(forKey: .resolvedMeaningNodeCount)
        meaningEdgeNeighborCount = container.lensContextInt(forKey: .meaningEdgeNeighborCount)
        meaningEvidenceCount = container.lensContextInt(forKey: .meaningEvidenceCount)
        aestheticTermRefCount = container.lensContextInt(forKey: .aestheticTermRefCount)
        aestheticCandidateCount = container.lensContextInt(forKey: .aestheticCandidateCount)
    }
}

struct LensContextMeaningNode: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var slug: String
    var kind: String
    var abstractionLevel: String
    var name: String
    var status: String
    var confidenceScore: Double
    var reuseScore: Double
    var definition: String
    var tags: [String]
    var edgeDegree: Int

    var isUsable: Bool {
        !slug.trimmed.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case slug
        case kind
        case abstractionLevel
        case name
        case status
        case confidenceScore
        case reuseScore
        case definition
        case tags
        case edgeDegree
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = container.lensContextString(forKey: .slug)
        id = container.lensContextString(forKey: .id, defaultValue: slug)
        kind = container.lensContextString(forKey: .kind)
        abstractionLevel = container.lensContextString(forKey: .abstractionLevel)
        name = container.lensContextString(forKey: .name, defaultValue: slug)
        status = container.lensContextString(forKey: .status)
        confidenceScore = container.lensContextDouble(forKey: .confidenceScore)
        reuseScore = container.lensContextDouble(forKey: .reuseScore)
        definition = container.lensContextString(forKey: .definition)
        tags = container.lensContextStringArray(forKey: .tags)
        edgeDegree = container.lensContextInt(forKey: .edgeDegree)
    }
}

struct LensContextMeaningEdgeNeighbor: Codable, Hashable, Sendable {
    var selectedSlug: String
    var direction: String
    var relationType: String
    var strength: Double
    var confidenceScore: Double
    var rationale: String
    var neighbor: LensContextMeaningNeighborNode

    var isUsable: Bool {
        !selectedSlug.trimmed.isEmpty && !neighbor.slug.trimmed.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case selectedSlug
        case direction
        case relationType
        case strength
        case confidenceScore
        case rationale
        case neighbor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selectedSlug = container.lensContextString(forKey: .selectedSlug)
        direction = container.lensContextString(forKey: .direction)
        relationType = container.lensContextString(forKey: .relationType)
        strength = container.lensContextDouble(forKey: .strength)
        confidenceScore = container.lensContextDouble(forKey: .confidenceScore)
        rationale = container.lensContextString(forKey: .rationale)
        neighbor = container.lensContextValue(LensContextMeaningNeighborNode.self, forKey: .neighbor)
            ?? LensContextMeaningNeighborNode()
    }
}

struct LensContextMeaningNeighborNode: Codable, Hashable, Sendable {
    var slug: String
    var kind: String
    var abstractionLevel: String
    var name: String
    var status: String
    var confidenceScore: Double
    var reuseScore: Double
    var definition: String
    var tags: [String]

    init(
        slug: String = "",
        kind: String = "",
        abstractionLevel: String = "",
        name: String = "",
        status: String = "",
        confidenceScore: Double = 0,
        reuseScore: Double = 0,
        definition: String = "",
        tags: [String] = []
    ) {
        self.slug = slug
        self.kind = kind
        self.abstractionLevel = abstractionLevel
        self.name = name
        self.status = status
        self.confidenceScore = confidenceScore
        self.reuseScore = reuseScore
        self.definition = definition
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case slug
        case kind
        case abstractionLevel
        case name
        case status
        case confidenceScore
        case reuseScore
        case definition
        case tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = container.lensContextString(forKey: .slug)
        kind = container.lensContextString(forKey: .kind)
        abstractionLevel = container.lensContextString(forKey: .abstractionLevel)
        name = container.lensContextString(forKey: .name, defaultValue: slug)
        status = container.lensContextString(forKey: .status)
        confidenceScore = container.lensContextDouble(forKey: .confidenceScore)
        reuseScore = container.lensContextDouble(forKey: .reuseScore)
        definition = container.lensContextString(forKey: .definition)
        tags = container.lensContextStringArray(forKey: .tags)
    }
}

struct LensContextMeaningEvidence: Codable, Hashable, Sendable {
    var nodeSlug: String
    var contextType: String
    var contextId: String
    var role: String
    var weight: Double
    var confidenceScore: Double
    var rationale: String
    var passageId: String?
    var sectionTitle: String?
    var passageIndex: Int?
    var workId: String?
    var workTitle: String?
    var workAuthor: String?

    var isUsable: Bool {
        !nodeSlug.trimmed.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case nodeSlug
        case contextType
        case contextId
        case role
        case weight
        case confidenceScore
        case rationale
        case passageId
        case sectionTitle
        case passageIndex
        case workId
        case workTitle
        case workAuthor
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodeSlug = container.lensContextString(forKey: .nodeSlug)
        contextType = container.lensContextString(forKey: .contextType)
        contextId = container.lensContextString(forKey: .contextId)
        role = container.lensContextString(forKey: .role)
        weight = container.lensContextDouble(forKey: .weight)
        confidenceScore = container.lensContextDouble(forKey: .confidenceScore)
        rationale = container.lensContextString(forKey: .rationale)
        passageId = container.lensContextOptionalString(forKey: .passageId)
        sectionTitle = container.lensContextOptionalString(forKey: .sectionTitle)
        passageIndex = container.lensContextOptionalInt(forKey: .passageIndex)
        workId = container.lensContextOptionalString(forKey: .workId)
        workTitle = container.lensContextOptionalString(forKey: .workTitle)
        workAuthor = container.lensContextOptionalString(forKey: .workAuthor)
    }
}

struct LensContextAestheticCandidate: Codable, Hashable, Identifiable, Sendable {
    var aestheticId: String
    var id: String { aestheticId }
    var slug: String
    var title: String
    var description: String?
    var primaryRank: Int
    var score: Double
    var matchCount: Int
    var goalMatchCount: Int
    var nonColorMatchCount: Int
    var matchedTerms: [LensContextAestheticMatchedTerm]

    var isUsable: Bool {
        !aestheticId.trimmed.isEmpty || !slug.trimmed.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case aestheticId
        case slug
        case title
        case description
        case primaryRank
        case score
        case matchCount
        case goalMatchCount
        case nonColorMatchCount
        case matchedTerms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = container.lensContextString(forKey: .slug)
        aestheticId = container.lensContextString(forKey: .aestheticId, defaultValue: slug)
        title = container.lensContextString(forKey: .title, defaultValue: slug)
        description = container.lensContextOptionalString(forKey: .description)
        primaryRank = container.lensContextInt(forKey: .primaryRank)
        score = container.lensContextDouble(forKey: .score)
        matchCount = container.lensContextInt(forKey: .matchCount)
        goalMatchCount = container.lensContextInt(forKey: .goalMatchCount)
        nonColorMatchCount = container.lensContextInt(forKey: .nonColorMatchCount)
        matchedTerms = container
            .lensContextLossyArray(LensContextAestheticMatchedTerm.self, forKey: .matchedTerms)
            .filter(\.isUsable)
    }
}

struct LensContextStyleCandidate: Codable, Hashable, Identifiable, Sendable {
    var styleId: String
    var id: String { styleId }
    var title: String
    var label: String
    var caption: String
    var imageUrl: String
    var collectionKey: String
    var collectionName: String
    var secondaryCollection: String
    var moods: [String]
    var hueName: String
    var hueHex: String
    var medium: String
    var scalarSat: Int
    var scalarCon: Int
    var scalarSer: Int
    var scalarLin: Int
    var scalarSty: Int
    var score: Double
    var matchCount: Int
    var matchedTerms: [LensContextStyleMatchedTerm]
    var positivePromptAtoms: [String]
    var negativePromptAtoms: [String]
    var transferableTraits: [String]

    var isUsable: Bool {
        !styleId.trimmed.isEmpty && !collectionKey.trimmed.isEmpty
    }

    var displayLabel: String {
        label.trimmed.isEmpty ? title.trimmed : label.trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case styleId
        case title
        case label
        case caption
        case imageUrl
        case collectionKey
        case collectionName
        case secondaryCollection
        case moods
        case hueName
        case hueHex
        case medium
        case scalarSat
        case scalarCon
        case scalarSer
        case scalarLin
        case scalarSty
        case score
        case matchCount
        case matchedTerms
        case positivePromptAtoms
        case negativePromptAtoms
        case transferableTraits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        styleId = container.lensContextString(forKey: .styleId)
        title = container.lensContextString(forKey: .title)
        label = container.lensContextString(forKey: .label, defaultValue: title)
        caption = container.lensContextString(forKey: .caption)
        imageUrl = container.lensContextString(forKey: .imageUrl)
        collectionKey = container.lensContextString(forKey: .collectionKey)
        collectionName = container.lensContextString(forKey: .collectionName, defaultValue: collectionKey)
        secondaryCollection = container.lensContextString(forKey: .secondaryCollection)
        moods = container.lensContextStringArray(forKey: .moods)
        hueName = container.lensContextString(forKey: .hueName)
        hueHex = container.lensContextString(forKey: .hueHex)
        medium = container.lensContextString(forKey: .medium)
        scalarSat = container.lensContextInt(forKey: .scalarSat)
        scalarCon = container.lensContextInt(forKey: .scalarCon)
        scalarSer = container.lensContextInt(forKey: .scalarSer)
        scalarLin = container.lensContextInt(forKey: .scalarLin)
        scalarSty = container.lensContextInt(forKey: .scalarSty)
        score = container.lensContextDouble(forKey: .score)
        matchCount = container.lensContextInt(forKey: .matchCount)
        matchedTerms = container
            .lensContextLossyArray(LensContextStyleMatchedTerm.self, forKey: .matchedTerms)
            .filter(\.isUsable)
        positivePromptAtoms = container.lensContextStringArray(forKey: .positivePromptAtoms)
        negativePromptAtoms = container.lensContextStringArray(forKey: .negativePromptAtoms)
        transferableTraits = container.lensContextStringArray(forKey: .transferableTraits)
    }
}

struct LensContextStyleMatchedTerm: Codable, Hashable, Sendable {
    var inputTerm: String
    var kind: String
    var fieldName: String
    var value: String
    var contribution: Double

    var isUsable: Bool {
        !inputTerm.trimmed.isEmpty || !value.trimmed.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case inputTerm
        case kind
        case fieldName
        case value
        case contribution
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTerm = container.lensContextString(forKey: .inputTerm)
        kind = container.lensContextString(forKey: .kind)
        fieldName = container.lensContextString(forKey: .fieldName)
        value = container.lensContextString(forKey: .value)
        contribution = container.lensContextDouble(forKey: .contribution)
    }
}

struct LensContextAestheticMatchedTerm: Codable, Hashable, Sendable {
    var inputTerm: String
    var termSlug: String
    var displayName: String
    var source: String
    var facetType: String
    var rank: Int
    var contribution: Double

    var isUsable: Bool {
        !displayName.trimmed.isEmpty || !termSlug.trimmed.isEmpty || !inputTerm.trimmed.isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case inputTerm
        case termSlug
        case displayName
        case source
        case facetType
        case rank
        case contribution
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTerm = container.lensContextString(forKey: .inputTerm)
        termSlug = container.lensContextString(forKey: .termSlug, defaultValue: inputTerm)
        displayName = container.lensContextString(forKey: .displayName, defaultValue: termSlug)
        source = container.lensContextString(forKey: .source)
        facetType = container.lensContextString(forKey: .facetType)
        rank = container.lensContextInt(forKey: .rank)
        contribution = container.lensContextDouble(forKey: .contribution)
    }
}

struct ProjectLensContextDocument: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.lens_context.v0.1"

    var schemaVersion: String = Self.schemaVersion
    var projectId: String
    var goalVersionId: String = ""
    var goalFingerprint: String = ""
    var status: ProjectLensContextStatus = .missing
    var retrievedAt: String = ""
    var request: LensContextResolveRequest?
    var response: LensContextResolveResponse?
    var failureMessage: String = ""
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String = "") -> ProjectLensContextDocument {
        ProjectLensContextDocument(projectId: projectId)
    }

    static func ready(
        projectId: String,
        goalVersionId: String,
        goalFingerprint: String,
        request: LensContextResolveRequest,
        response: LensContextResolveResponse,
        now: String = DateFormats.now()
    ) -> ProjectLensContextDocument {
        ProjectLensContextDocument(
            projectId: projectId,
            goalVersionId: goalVersionId,
            goalFingerprint: goalFingerprint,
            status: .ready,
            retrievedAt: now,
            request: request,
            response: response,
            failureMessage: "",
            updatedAt: now
        )
    }

    static func failed(
        projectId: String,
        goalVersionId: String,
        goalFingerprint: String,
        request: LensContextResolveRequest?,
        message: String,
        now: String = DateFormats.now()
    ) -> ProjectLensContextDocument {
        ProjectLensContextDocument(
            projectId: projectId,
            goalVersionId: goalVersionId,
            goalFingerprint: goalFingerprint,
            status: .failed,
            retrievedAt: "",
            request: request,
            response: nil,
            failureMessage: message.trimmed,
            updatedAt: now
        )
    }

    static func decode(from data: Data) throws -> ProjectLensContextDocument {
        try JSONCoding.decoder.decode(ProjectLensContextDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }

    func isReady(forGoalVersionId expectedGoalVersionId: String, goalFingerprint expectedGoalFingerprint: String) -> Bool {
        status == .ready
            && goalVersionId == expectedGoalVersionId
            && goalFingerprint == expectedGoalFingerprint
            && response != nil
    }

    func promptPacket() -> LensContextPromptPacket {
        guard let response else {
            return LensContextPromptPacket(
                goalFingerprint: goalFingerprint,
                status: status.rawValue,
                warnings: failureMessage.isEmpty ? [] : [failureMessage],
                meaningNodes: [],
                meaningEdges: [],
                meaningEvidence: [],
                aestheticCandidates: []
            )
        }
        return LensContextPromptPacket(
            goalFingerprint: response.goalFingerprint,
            status: status.rawValue,
            warnings: response.warnings,
            meaningNodes: response.selectedMeaningNodes.prefix(12).map(LensContextPromptMeaningNode.init),
            meaningEdges: response.meaningEdgeNeighbors.prefix(18).map(LensContextPromptMeaningEdge.init),
            meaningEvidence: response.meaningEvidence.prefix(12).map(LensContextPromptMeaningEvidence.init),
            aestheticCandidates: response.aestheticCandidates.prefix(8).map(LensContextPromptAestheticCandidate.init)
        )
    }
}

struct LensContextPromptPacket: Codable, Hashable, Sendable {
    var goalFingerprint: String
    var status: String
    var warnings: [String]
    var meaningNodes: [LensContextPromptMeaningNode]
    var meaningEdges: [LensContextPromptMeaningEdge]
    var meaningEvidence: [LensContextPromptMeaningEvidence]
    var aestheticCandidates: [LensContextPromptAestheticCandidate]
}

struct LensContextPromptMeaningNode: Codable, Hashable, Sendable {
    var slug: String
    var kind: String
    var name: String
    var definition: String
    var tags: [String]
    var edgeDegree: Int

    init(_ node: LensContextMeaningNode) {
        slug = node.slug
        kind = node.kind
        name = node.name
        definition = lensContextShortSummaryText(node.definition, limit: 220)
        tags = Array(node.tags.prefix(8))
        edgeDegree = node.edgeDegree
    }
}

struct LensContextPromptMeaningEdge: Codable, Hashable, Sendable {
    var selectedSlug: String
    var direction: String
    var relationType: String
    var neighborSlug: String
    var neighborName: String
    var strength: Double
    var rationale: String

    init(_ edge: LensContextMeaningEdgeNeighbor) {
        selectedSlug = edge.selectedSlug
        direction = edge.direction
        relationType = edge.relationType
        neighborSlug = edge.neighbor.slug
        neighborName = edge.neighbor.name
        strength = edge.strength
        rationale = lensContextShortSummaryText(edge.rationale, limit: 220)
    }
}

struct LensContextPromptMeaningEvidence: Codable, Hashable, Sendable {
    var nodeSlug: String
    var role: String
    var weight: Double
    var workTitle: String
    var sectionTitle: String
    var rationale: String

    init(_ evidence: LensContextMeaningEvidence) {
        nodeSlug = evidence.nodeSlug
        role = evidence.role
        weight = evidence.weight
        workTitle = evidence.workTitle ?? ""
        sectionTitle = evidence.sectionTitle ?? ""
        rationale = lensContextShortSummaryText(evidence.rationale, limit: 240)
    }
}

struct LensContextPromptAestheticCandidate: Codable, Hashable, Sendable {
    var aestheticId: String
    var title: String
    var score: Double
    var matchedTerms: [String]

    init(_ candidate: LensContextAestheticCandidate) {
        aestheticId = candidate.aestheticId
        title = candidate.title
        score = candidate.score
        matchedTerms = candidate.matchedTerms.prefix(8).map { term in
            "\(term.displayName) [\(term.facetType), \(term.source)]"
        }
    }
}

struct LensContextGoalFingerprintSeed: Codable, Hashable, Sendable {
    var projectId: String
    var versionId: String
    var brief: ProjectGoalBriefV2
}

private func lensContextShortSummaryText(_ value: String, limit: Int) -> String {
    let compact = value
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
    guard compact.count > limit else { return compact }
    return String(compact.prefix(max(0, limit - 1))) + "..."
}

private struct LensContextLossyDecodable<Value: Decodable>: Decodable {
    var value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

private extension KeyedDecodingContainer {
    func lensContextValue<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> Value? {
        try? decodeIfPresent(type, forKey: key)
    }

    func lensContextLossyArray<Value: Decodable>(_ type: Value.Type, forKey key: Key) -> [Value] {
        guard let wrapped = try? decodeIfPresent([LensContextLossyDecodable<Value>].self, forKey: key) else {
            return []
        }
        return wrapped.compactMap(\.value)
    }

    func lensContextString(forKey key: Key, defaultValue: String = "") -> String {
        guard let value = lensContextOptionalString(forKey: key) else { return defaultValue }
        return value
    }

    func lensContextOptionalString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let trimmed = value.trimmed
            return trimmed.isEmpty ? nil : trimmed
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) {
            return value ? "true" : "false"
        }
        return nil
    }

    func lensContextStringArray(forKey key: Key) -> [String] {
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values.map(\.trimmed).filter { !$0.isEmpty }
        }
        if let single = lensContextOptionalString(forKey: key) {
            return [single]
        }
        return []
    }

    func lensContextDouble(forKey key: Key, defaultValue: Double = 0) -> Double {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value.isFinite ? value : defaultValue
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let string = lensContextOptionalString(forKey: key),
           let value = Double(string),
           value.isFinite {
            return value
        }
        return defaultValue
    }

    func lensContextInt(forKey key: Key, defaultValue: Int = 0) -> Int {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value)
        }
        if let string = lensContextOptionalString(forKey: key),
           let value = Int(string) {
            return value
        }
        return defaultValue
    }

    func lensContextOptionalInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value)
        }
        if let string = lensContextOptionalString(forKey: key),
           let value = Int(string) {
            return value
        }
        return nil
    }
}
