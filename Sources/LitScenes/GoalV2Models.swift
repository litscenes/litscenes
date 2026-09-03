import Foundation

enum ProjectGoalV2Role: String, Codable, Hashable {
    case user
    case assistant
}

enum ProjectGoalMeaningNodeKind: String, Codable, Hashable, Sendable {
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

enum ProjectGoalMeaningNodeRefRole: String, Codable, Hashable, Sendable {
    case literalSymbol = "literal_symbol"
    case visualMotif = "visual_motif"
    case valueTension = "value_tension"
    case meaningClaim = "meaning_claim"
    case themeSeed = "theme_seed"
    case archetypalSituation = "archetypal_situation"
    case transformation
    case mood
    case avoidance
    case other
}

enum ProjectGoalAestheticTermRefRole: String, Codable, Hashable, Sendable {
    case motif
    case value
    case palette
    case era
    case materialOrTexture = "material_or_texture"
    case mood
    case avoidance
    case other
}

enum ProjectGoalMeaningRefSource: String, Codable, Hashable, Sendable {
    case goal
    case media
    case goalAndMedia = "goal_and_media"
    case operatorSelected = "operator"
}

enum ProjectGoalAestheticTermFacetType: String, Codable, Hashable, Sendable {
    case keyMotif = "key_motif"
    case keyValue = "key_value"
    case keyColour = "key_colour"
    case originDecade = "origin_decade"
}

struct ProjectGoalMeaningNodeRef: Codable, Hashable, Sendable {
    var slug: String = ""
    var kind: ProjectGoalMeaningNodeKind = .theme
    var name: String = ""
    var role: ProjectGoalMeaningNodeRefRole = .other
    var source: ProjectGoalMeaningRefSource = .goal
    var evidence: String = ""

    func normalized() -> ProjectGoalMeaningNodeRef {
        var value = self
        value.slug = value.slug.trimmed
        value.name = value.name.trimmed
        value.evidence = value.evidence.trimmed
        return value
    }
}

struct ProjectGoalAestheticTermRef: Codable, Hashable, Sendable {
    var facetType: ProjectGoalAestheticTermFacetType = .keyMotif
    var slug: String = ""
    var displayName: String = ""
    var role: ProjectGoalAestheticTermRefRole = .other
    var source: ProjectGoalMeaningRefSource = .goal
    var evidence: String = ""

    func normalized() -> ProjectGoalAestheticTermRef {
        var value = self
        value.slug = value.slug.trimmed
        value.displayName = value.displayName.trimmed
        value.evidence = value.evidence.trimmed
        return value
    }
}

enum ProjectGoalStyleTermKind: String, Codable, Hashable, Sendable, CaseIterable {
    case mood
    case hue
    case collection
    case medium
    case phrase
}

struct ProjectGoalStyleTermRef: Codable, Hashable, Sendable {
    var term: String = ""
    var kind: ProjectGoalStyleTermKind = .phrase
    var weight: Double = 1
    var rationale: String = ""

    func normalized() -> ProjectGoalStyleTermRef {
        var value = self
        value.term = value.term.trimmed
        value.rationale = value.rationale.trimmed
        if value.weight <= 0 {
            value.weight = 1
        }
        value.weight = min(3, max(0.1, value.weight))
        return value
    }
}

struct ProjectGoalRequiredEntity: Codable, Hashable, Sendable {
    static let maximumCount = 12
    static let maximumNameLength = 120
    static let maximumRoleLength = 120

    var name: String = ""
    var role: String = ""
    var required: Bool = true

    init(name: String = "", role: String = "", required: Bool = true) {
        self.name = name
        self.role = role
        self.required = required
    }

    func normalized() -> ProjectGoalRequiredEntity {
        ProjectGoalRequiredEntity(
            name: compactGoalEntityText(name, limit: Self.maximumNameLength),
            role: compactGoalEntityText(role, limit: Self.maximumRoleLength),
            required: required
        )
    }
}

struct ProjectGoalMessageV2: Codable, Hashable, Identifiable {
    var messageId: String
    var id: String { messageId }
    var role: ProjectGoalV2Role
    var text: String
    var mediaIds: [String] = []
    var createdAt: String
}

struct ProjectGoalBriefV2: Codable, Hashable, Sendable {
    var contentType: ProjectIntent?
    var goal: String = ""
    var audience: String = ""
    var desiredResponse: String = ""
    var viewerExperience: String = ""
    var moodboardArticulation: String = ""
    var successCriteria: [String] = []
    var constraints: [String] = []
    var requiredEntities: [ProjectGoalRequiredEntity] = []
    var openQuestions: [String] = []
    var lensSeedSummary: String = ""
    var lensSeedTerms: [String] = []
    var meaningNodeRefs: [ProjectGoalMeaningNodeRef] = []
    var aestheticTermRefs: [ProjectGoalAestheticTermRef] = []
    var styleTermRefs: [ProjectGoalStyleTermRef] = []

    init(
        contentType: ProjectIntent? = nil,
        goal: String = "",
        audience: String = "",
        desiredResponse: String = "",
        viewerExperience: String = "",
        moodboardArticulation: String = "",
        successCriteria: [String] = [],
        constraints: [String] = [],
        requiredEntities: [ProjectGoalRequiredEntity] = [],
        openQuestions: [String] = [],
        lensSeedSummary: String = "",
        lensSeedTerms: [String] = [],
        meaningNodeRefs: [ProjectGoalMeaningNodeRef] = [],
        aestheticTermRefs: [ProjectGoalAestheticTermRef] = [],
        styleTermRefs: [ProjectGoalStyleTermRef] = []
    ) {
        self.contentType = contentType
        self.goal = goal
        self.audience = audience
        self.desiredResponse = desiredResponse
        self.viewerExperience = viewerExperience
        self.moodboardArticulation = moodboardArticulation
        self.successCriteria = successCriteria
        self.constraints = constraints
        self.requiredEntities = requiredEntities
        self.openQuestions = openQuestions
        self.lensSeedSummary = lensSeedSummary
        self.lensSeedTerms = lensSeedTerms
        self.meaningNodeRefs = meaningNodeRefs
        self.aestheticTermRefs = aestheticTermRefs
        self.styleTermRefs = styleTermRefs
    }

    private enum CodingKeys: String, CodingKey {
        case contentType
        case goal
        case audience
        case desiredResponse
        case viewerExperience
        case moodboardArticulation
        case successCriteria
        case constraints
        case requiredEntities
        case openQuestions
        case lensSeedSummary
        case lensSeedTerms
        case legacyThemeSeedSummary = "theme_seed_summary"
        case legacyThemeSeedTerms = "theme_seed_terms"
        case meaningNodeRefs
        case aestheticTermRefs
        case styleTermRefs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentType = try container.decodeIfPresent(ProjectIntent.self, forKey: .contentType)
        goal = try container.decodeIfPresent(String.self, forKey: .goal) ?? ""
        audience = try container.decodeIfPresent(String.self, forKey: .audience) ?? ""
        desiredResponse = try container.decodeIfPresent(String.self, forKey: .desiredResponse) ?? ""
        viewerExperience = try container.decodeIfPresent(String.self, forKey: .viewerExperience) ?? ""
        moodboardArticulation = try container.decodeIfPresent(String.self, forKey: .moodboardArticulation) ?? ""
        successCriteria = try container.decodeIfPresent([String].self, forKey: .successCriteria) ?? []
        constraints = try container.decodeIfPresent([String].self, forKey: .constraints) ?? []
        requiredEntities = try container.decodeIfPresent([ProjectGoalRequiredEntity].self, forKey: .requiredEntities) ?? []
        openQuestions = try container.decodeIfPresent([String].self, forKey: .openQuestions) ?? []
        lensSeedSummary = try container.decodeIfPresent(String.self, forKey: .lensSeedSummary)
            ?? container.decodeIfPresent(String.self, forKey: .legacyThemeSeedSummary)
            ?? ""
        lensSeedTerms = try container.decodeIfPresent([String].self, forKey: .lensSeedTerms)
            ?? container.decodeIfPresent([String].self, forKey: .legacyThemeSeedTerms)
            ?? []
        meaningNodeRefs = try container.decodeIfPresent([ProjectGoalMeaningNodeRef].self, forKey: .meaningNodeRefs) ?? []
        aestheticTermRefs = try container.decodeIfPresent([ProjectGoalAestheticTermRef].self, forKey: .aestheticTermRefs) ?? []
        styleTermRefs = try container.decodeIfPresent([ProjectGoalStyleTermRef].self, forKey: .styleTermRefs) ?? []
    }

    static func empty() -> ProjectGoalBriefV2 {
        ProjectGoalBriefV2()
    }

    var isReady: Bool {
        contentType != nil && !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func normalized() -> ProjectGoalBriefV2 {
        var value = self
        value.goal = value.goal.trimmed
        value.audience = value.audience.trimmed
        value.desiredResponse = value.desiredResponse.trimmed
        value.viewerExperience = value.viewerExperience.trimmed
        value.moodboardArticulation = value.moodboardArticulation.trimmed
        value.successCriteria = uniqueNonEmpty(value.successCriteria)
        value.constraints = uniqueNonEmpty(value.constraints)
        value.requiredEntities = uniqueRequiredGoalEntities(value.requiredEntities, limit: ProjectGoalRequiredEntity.maximumCount).entities
        value.openQuestions = uniqueNonEmpty(value.openQuestions)
        value.lensSeedSummary = value.lensSeedSummary.trimmed
        value.lensSeedTerms = uniqueNonEmpty(value.lensSeedTerms)
        value.meaningNodeRefs = uniqueMeaningNodeRefs(value.meaningNodeRefs, limit: 18)
        value.aestheticTermRefs = uniqueAestheticTermRefs(value.aestheticTermRefs, limit: 24)
        value.styleTermRefs = uniqueStyleTermRefs(value.styleTermRefs, limit: 24)
        return value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(contentType, forKey: .contentType)
        try container.encode(goal, forKey: .goal)
        try container.encode(audience, forKey: .audience)
        try container.encode(desiredResponse, forKey: .desiredResponse)
        try container.encode(viewerExperience, forKey: .viewerExperience)
        try container.encode(moodboardArticulation, forKey: .moodboardArticulation)
        try container.encode(successCriteria, forKey: .successCriteria)
        try container.encode(constraints, forKey: .constraints)
        try container.encode(requiredEntities, forKey: .requiredEntities)
        try container.encode(openQuestions, forKey: .openQuestions)
        try container.encode(lensSeedSummary, forKey: .lensSeedSummary)
        try container.encode(lensSeedTerms, forKey: .lensSeedTerms)
        try container.encode(meaningNodeRefs, forKey: .meaningNodeRefs)
        try container.encode(aestheticTermRefs, forKey: .aestheticTermRefs)
        try container.encode(styleTermRefs, forKey: .styleTermRefs)
    }
}

struct ProjectGoalRequiredEntityNormalizationResult: Hashable, Sendable {
    var entities: [ProjectGoalRequiredEntity]
    var warnings: [String]
}

struct ProjectGoalRequiredEntitySanitizationResult: Hashable, Sendable {
    var brief: ProjectGoalBriefV2
    var warnings: [String]
}

func sanitizeInterviewRequiredEntities(
    brief emittedBrief: ProjectGoalBriefV2,
    currentBrief: ProjectGoalBriefV2,
    userMessages: [ProjectGoalMessageV2]
) -> ProjectGoalRequiredEntitySanitizationResult {
    let currentNormalization = uniqueRequiredGoalEntities(currentBrief.requiredEntities)
    var output = currentNormalization.entities
    var seen = Set(output.map { $0.name.lowercased() })
    var warnings = currentNormalization.warnings
    let corpus = userAuthoredEntityCorpus(userMessages)

    for entity in emittedBrief.requiredEntities {
        let normalized = entity.normalized()
        guard !normalized.name.isEmpty else { continue }
        guard normalized.required else {
            warnings.append("Removed required_entities entry '\(normalized.name)' because required=false is not supported.")
            continue
        }
        let key = normalized.name.lowercased()
        if seen.contains(key) {
            continue
        }
        guard containsVerbatimGoalEntityName(normalized.name, in: corpus) else {
            warnings.append("Removed unsupported required entity '\(normalized.name)' because the name was not supplied in user-authored Goal text.")
            continue
        }
        output.append(ProjectGoalRequiredEntity(name: normalized.name, role: normalized.role, required: true))
        seen.insert(key)
    }

    let merged = uniqueRequiredGoalEntities(output)
    var sanitized = emittedBrief.normalized()
    sanitized.requiredEntities = merged.entities
    warnings.append(contentsOf: merged.warnings)
    return ProjectGoalRequiredEntitySanitizationResult(
        brief: sanitized,
        warnings: uniqueNonEmpty(warnings)
    )
}

func uniqueRequiredGoalEntities(
    _ entities: [ProjectGoalRequiredEntity],
    limit: Int = ProjectGoalRequiredEntity.maximumCount
) -> ProjectGoalRequiredEntityNormalizationResult {
    var seen: [String: Int] = [:]
    var output: [ProjectGoalRequiredEntity] = []
    var warnings: [String] = []
    for entity in entities {
        let normalized = entity.normalized()
        guard !normalized.name.isEmpty else { continue }
        guard normalized.required else {
            warnings.append("Removed required_entities entry '\(normalized.name)' because required=false is not supported.")
            continue
        }
        let key = normalized.name.lowercased()
        if let existingIndex = seen[key] {
            if output[existingIndex].role.isEmpty, !normalized.role.isEmpty {
                output[existingIndex].role = normalized.role
            } else if !normalized.role.isEmpty,
                      !output[existingIndex].role.isEmpty,
                      output[existingIndex].role.caseInsensitiveCompare(normalized.role) != .orderedSame {
                warnings.append("Merged duplicate required entity '\(normalized.name)' and kept the first role.")
            }
            continue
        }
        seen[key] = output.count
        output.append(normalized)
        if output.count >= limit { break }
    }
    return ProjectGoalRequiredEntityNormalizationResult(
        entities: output,
        warnings: uniqueNonEmpty(warnings)
    )
}

func compactGoalEntityText(_ value: String, limit: Int) -> String {
    let compact = value
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
        .trimmed
    guard limit > 0, compact.count > limit else { return compact }
    return String(compact.prefix(limit)).trimmed
}

private func userAuthoredEntityCorpus(_ messages: [ProjectGoalMessageV2]) -> String {
    messages
        .filter { $0.role == .user }
        .map(\.text)
        .joined(separator: " ")
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
}

func containsVerbatimGoalEntityName(_ name: String, in text: String) -> Bool {
    let needle = compactGoalEntityText(name, limit: ProjectGoalRequiredEntity.maximumNameLength)
    let haystack = text
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
    guard !needle.isEmpty, !haystack.isEmpty else { return false }

    var searchRange = haystack.startIndex..<haystack.endIndex
    while let range = haystack.range(of: needle, options: [.caseInsensitive], range: searchRange) {
        let beforeIsBoundary = range.lowerBound == haystack.startIndex
            || !isGoalEntityNameCharacter(haystack[haystack.index(before: range.lowerBound)])
        let afterIsBoundary = range.upperBound == haystack.endIndex
            || !isGoalEntityNameCharacter(haystack[range.upperBound])
        if beforeIsBoundary && afterIsBoundary {
            return true
        }
        searchRange = range.upperBound..<haystack.endIndex
    }
    return false
}

private func isGoalEntityNameCharacter(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0)
            || $0 == UnicodeScalar("_")
            || $0 == UnicodeScalar("-")
    }
}

private func uniqueMeaningNodeRefs(_ refs: [ProjectGoalMeaningNodeRef], limit: Int) -> [ProjectGoalMeaningNodeRef] {
    var seen = Set<String>()
    var output: [ProjectGoalMeaningNodeRef] = []
    for ref in refs {
        let normalized = ref.normalized()
        let key = normalized.slug.lowercased()
        guard !normalized.slug.isEmpty, !normalized.name.isEmpty, !seen.contains(key) else { continue }
        seen.insert(key)
        output.append(normalized)
        if output.count >= limit { break }
    }
    return output
}

private func uniqueAestheticTermRefs(_ refs: [ProjectGoalAestheticTermRef], limit: Int) -> [ProjectGoalAestheticTermRef] {
    var seen = Set<String>()
    var output: [ProjectGoalAestheticTermRef] = []
    for ref in refs {
        let normalized = ref.normalized()
        let key = "\(normalized.facetType.rawValue):\(normalized.slug.lowercased())"
        guard !normalized.slug.isEmpty, !normalized.displayName.isEmpty, !seen.contains(key) else { continue }
        seen.insert(key)
        output.append(normalized)
        if output.count >= limit { break }
    }
    return output
}

func uniqueStyleTermRefs(_ refs: [ProjectGoalStyleTermRef], limit: Int) -> [ProjectGoalStyleTermRef] {
    var seen = Set<String>()
    var output: [ProjectGoalStyleTermRef] = []
    for ref in refs {
        let normalized = ref.normalized()
        let key = "\(normalized.kind.rawValue):\(normalized.term.lowercased())"
        guard !normalized.term.isEmpty, !seen.contains(key) else { continue }
        seen.insert(key)
        output.append(normalized)
        if output.count >= limit { break }
    }
    return output
}

struct ProjectGoalBriefVersionV2: Codable, Hashable, Identifiable {
    var versionId: String
    var id: String { versionId }
    var turnIndex: Int
    var brief: ProjectGoalBriefV2
    var changeSummary: String
    var createdAt: String
    var model: String

    // Optional migration-safe warnings from deterministic post-decode validation.
    var validationWarnings: [String] = []

    init(
        versionId: String,
        turnIndex: Int,
        brief: ProjectGoalBriefV2,
        changeSummary: String,
        createdAt: String,
        model: String,
        validationWarnings: [String] = []
    ) {
        self.versionId = versionId
        self.turnIndex = turnIndex
        self.brief = brief
        self.changeSummary = changeSummary
        self.createdAt = createdAt
        self.model = model
        self.validationWarnings = validationWarnings
    }

    private enum CodingKeys: String, CodingKey {
        case versionId
        case turnIndex
        case brief
        case changeSummary
        case createdAt
        case model
        case validationWarnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        versionId = try container.decodeIfPresent(String.self, forKey: .versionId) ?? ""
        turnIndex = try container.decodeIfPresent(Int.self, forKey: .turnIndex) ?? 0
        brief = try container.decodeIfPresent(ProjectGoalBriefV2.self, forKey: .brief) ?? .empty()
        changeSummary = try container.decodeIfPresent(String.self, forKey: .changeSummary) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        validationWarnings = try container.decodeIfPresent([String].self, forKey: .validationWarnings) ?? []
    }
}

struct ProjectGoalDocumentV2: Codable, Hashable {
    static let schemaVersion = "litscenes.project_goal.v0.4"
    static let maximumVersionCount = 21

    var schemaVersion: String = Self.schemaVersion
    var projectId: String
    var messages: [ProjectGoalMessageV2] = []
    var versions: [ProjectGoalBriefVersionV2] = []
    var activeVersionId: String = ""
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String = "") -> ProjectGoalDocumentV2 {
        ProjectGoalDocumentV2(projectId: projectId)
    }

    static func decode(from data: Data) throws -> ProjectGoalDocumentV2 {
        try JSONCoding.decoder.decode(ProjectGoalDocumentV2.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }

    var activeVersion: ProjectGoalBriefVersionV2? {
        versions.first { $0.versionId == activeVersionId } ?? versions.last
    }

    var activeBrief: ProjectGoalBriefV2 {
        activeVersion?.brief ?? .empty()
    }

    var isReady: Bool {
        activeBrief.isReady
    }

    mutating func appendMessage(role: ProjectGoalV2Role, text: String, mediaIds: [String] = [], now: String) {
        messages.append(ProjectGoalMessageV2(
            messageId: "goal_msg_\(shortHash("\(projectId):\(role.rawValue):\(now):\(messages.count)", length: 12))",
            role: role,
            text: text.trimmed,
            mediaIds: uniqueNonEmpty(mediaIds),
            createdAt: now
        ))
        updatedAt = now
    }

    mutating func appendVersion(
        brief: ProjectGoalBriefV2,
        changeSummary: String,
        model: String,
        now: String,
        validationWarnings: [String] = []
    ) {
        let normalized = brief.normalized()
        let briefHash = stableHash(normalized, length: 16)
        let version = ProjectGoalBriefVersionV2(
            versionId: "goal_v2_\(shortHash("\(projectId):\(now):\(versions.count):\(briefHash)", length: 12))",
            turnIndex: messages.count,
            brief: normalized,
            changeSummary: changeSummary.trimmed,
            createdAt: now,
            model: model,
            validationWarnings: uniqueNonEmpty(validationWarnings)
        )
        versions.append(version)
        if versions.count > Self.maximumVersionCount {
            versions.removeFirst(versions.count - Self.maximumVersionCount)
        }
        activeVersionId = version.versionId
        updatedAt = now
    }

    mutating func restore(versionId: String, now: String) {
        guard versions.contains(where: { $0.versionId == versionId }) else { return }
        activeVersionId = versionId
        updatedAt = now
    }
}

struct ProjectGoalInterviewResponseV3: Codable, Hashable {
    var schemaVersion: String = "litscenes.project_goal_interview_response.v0.7"
    var assistantMessage: String
    var brief: ProjectGoalBriefV2
    var changeSummary: String
    /// Per-character cast patches (the delta channel to the separately-managed goal
    /// cast). Empty on turns that don't explicitly change characters; v0.5-shaped
    /// payloads without the key decode tolerantly to [].
    var castUpdates: [ProjectGoalCastUpdate] = []

    static func decode(from data: Data) throws -> ProjectGoalInterviewResponseV3 {
        try JSONCoding.decoder.decode(ProjectGoalInterviewResponseV3.self, from: data)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case assistantMessage
        case brief
        case changeSummary
        case castUpdates
    }

    init(
        schemaVersion: String = "litscenes.project_goal_interview_response.v0.7",
        assistantMessage: String,
        brief: ProjectGoalBriefV2,
        changeSummary: String,
        castUpdates: [ProjectGoalCastUpdate] = []
    ) {
        self.schemaVersion = schemaVersion
        self.assistantMessage = assistantMessage
        self.brief = brief
        self.changeSummary = changeSummary
        self.castUpdates = castUpdates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion)
            ?? "litscenes.project_goal_interview_response.v0.7"
        assistantMessage = try container.decodeIfPresent(String.self, forKey: .assistantMessage) ?? ""
        brief = try container.decodeIfPresent(ProjectGoalBriefV2.self, forKey: .brief) ?? ProjectGoalBriefV2()
        changeSummary = try container.decodeIfPresent(String.self, forKey: .changeSummary) ?? ""
        castUpdates = try container.decodeIfPresent([ProjectGoalCastUpdate].self, forKey: .castUpdates) ?? []
    }
}
