import Foundation

// MARK: - Wire models for POST /frame-forms/generate
// Wire is snake_case via JSONCoding's key strategies.

struct FrameFormsSelectedForm: Codable, Hashable, Sendable {
    var meaningSlug: String = ""
    var pole: String = ""
    var title: String = ""
    var promptGist: String = ""
}

struct FrameFormsGenerateRequest: Codable, Hashable, Sendable {
    var projectId: String = ""
    var goalFingerprint: String = ""
    var goalSummary: String = ""
    var styleFitLine: String = ""
    var meaningNodeRefs: [ProjectGoalMeaningNodeRef] = []
    var selectedForm: FrameFormsSelectedForm?
    var priorFormGists: [String] = []
}

/// One generated Form option. Serves both the wire response (where `optionId`
/// is absent) and local persistence (where the engine assigns it).
struct LensFrameFormOption: Codable, Hashable, Identifiable, Sendable {
    var optionId: String = ""
    var title: String = ""
    var prompt: String = ""
    var meaningSlug: String = ""
    var meaningName: String = ""
    var pole: String = ""
    var abstractionLevel: String = ""
    var relationToParent: String = ""

    var id: String { optionId.isEmpty ? "\(meaningSlug)#\(pole)#\(title)" : optionId }

    func normalized() -> LensFrameFormOption {
        var value = self
        value.optionId = value.optionId.trimmed
        value.title = value.title.trimmed
        value.prompt = value.prompt.trimmed
        value.meaningSlug = value.meaningSlug.trimmed.lowercased()
        value.meaningName = value.meaningName.trimmed
        value.pole = value.pole.trimmed.lowercased()
        value.abstractionLevel = value.abstractionLevel.trimmed.lowercased()
        value.relationToParent = value.relationToParent.trimmed
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case optionId
        case title
        case prompt
        case meaningSlug
        case meaningName
        case pole
        case abstractionLevel
        case relationToParent
    }

    init(
        optionId: String = "",
        title: String = "",
        prompt: String = "",
        meaningSlug: String = "",
        meaningName: String = "",
        pole: String = "",
        abstractionLevel: String = "",
        relationToParent: String = ""
    ) {
        self.optionId = optionId
        self.title = title
        self.prompt = prompt
        self.meaningSlug = meaningSlug
        self.meaningName = meaningName
        self.pole = pole
        self.abstractionLevel = abstractionLevel
        self.relationToParent = relationToParent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        optionId = try container.decodeIfPresent(String.self, forKey: .optionId) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        meaningSlug = try container.decodeIfPresent(String.self, forKey: .meaningSlug) ?? ""
        meaningName = try container.decodeIfPresent(String.self, forKey: .meaningName) ?? ""
        pole = try container.decodeIfPresent(String.self, forKey: .pole) ?? ""
        abstractionLevel = try container.decodeIfPresent(String.self, forKey: .abstractionLevel) ?? ""
        relationToParent = try container.decodeIfPresent(String.self, forKey: .relationToParent) ?? ""
        self = normalized()
    }
}

struct FrameFormsGenerateResponse: Codable, Hashable, Sendable {
    var schemaVersion: String = ""
    var userId: String = ""
    var projectId: String = ""
    var mode: String = ""
    var generatedAt: String = ""
    var model: String = ""
    var options: [LensFrameFormOption] = []
    var warnings: [String] = []
    var requestId: String = ""
    /// Provider token usage when the generator surfaces it (direct mode does;
    /// hosted responses may omit it). Zero means unreported, never free.
    var usageInputTokens: Int = 0
    var usageOutputTokens: Int = 0

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case userId
        case projectId
        case mode
        case generatedAt
        case model
        case options
        case warnings
        case requestId
        case usageInputTokens
        case usageOutputTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? ""
        userId = try container.decodeIfPresent(String.self, forKey: .userId) ?? ""
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        options = (try container.decodeIfPresent([LensFrameFormOption].self, forKey: .options) ?? [])
            .map { $0.normalized() }
            .filter { !$0.prompt.isEmpty }
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId) ?? ""
        usageInputTokens = try container.decodeIfPresent(Int.self, forKey: .usageInputTokens) ?? 0
        usageOutputTokens = try container.decodeIfPresent(Int.self, forKey: .usageOutputTokens) ?? 0
    }
}

// MARK: - Persisted document (project-level, "hot at all times")

/// One trio of Form options: the GOAL-time initial generation, or an expansion
/// branched from a selected option (route exploration).
struct LensFrameFormGeneration: Codable, Hashable, Identifiable, Sendable {
    var generationId: String = ""
    var mode: String = ""
    var parentOptionId: String = ""
    var options: [LensFrameFormOption] = []
    var generatedAt: String = ""

    var id: String { generationId }

    private enum CodingKeys: String, CodingKey {
        case generationId
        case mode
        case parentOptionId
        case options
        case generatedAt
    }

    init(
        generationId: String = "",
        mode: String = "",
        parentOptionId: String = "",
        options: [LensFrameFormOption] = [],
        generatedAt: String = ""
    ) {
        self.generationId = generationId
        self.mode = mode
        self.parentOptionId = parentOptionId
        self.options = options
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        generationId = try container.decodeIfPresent(String.self, forKey: .generationId) ?? ""
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? ""
        parentOptionId = try container.decodeIfPresent(String.self, forKey: .parentOptionId) ?? ""
        options = try container.decodeIfPresent([LensFrameFormOption].self, forKey: .options) ?? []
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
    }
}

struct ProjectFrameFormsDocument: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.frame_forms_doc.v0.1"
    static let documentType = "frame_forms"

    var schemaVersion: String = ProjectFrameFormsDocument.schemaVersion
    var projectId: String = ""
    var goalFingerprint: String = ""
    var status: String = "missing"
    var generations: [LensFrameFormGeneration] = []
    var updatedAt: String = ""

    static func empty(projectId: String) -> ProjectFrameFormsDocument {
        ProjectFrameFormsDocument(projectId: projectId)
    }

    var hasInitialGeneration: Bool {
        generations.contains { $0.mode == "initial" && !$0.options.isEmpty }
    }

    var allOptions: [LensFrameFormOption] {
        generations.flatMap(\.options)
    }

    func hasExpansion(fromOptionId optionId: String) -> Bool {
        !optionId.isEmpty && generations.contains { $0.parentOptionId == optionId }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case goalFingerprint
        case status
        case generations
        case updatedAt
    }

    init(
        schemaVersion: String = ProjectFrameFormsDocument.schemaVersion,
        projectId: String = "",
        goalFingerprint: String = "",
        status: String = "missing",
        generations: [LensFrameFormGeneration] = [],
        updatedAt: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.goalFingerprint = goalFingerprint
        self.status = status
        self.generations = generations
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        goalFingerprint = try container.decodeIfPresent(String.self, forKey: .goalFingerprint) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "missing"
        generations = try container.decodeIfPresent([LensFrameFormGeneration].self, forKey: .generations) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

// MARK: - Form refine chat (ephemeral — editor-only, never persisted)

/// One refine-chat rewrite: the transformed prompt plus a one-line note of
/// what changed. Lives only while the Frame Creator is open.
struct LensFormPromptTransform: Hashable, Sendable {
    var prompt: String
    var note: String
}

/// Composes the OpenAI request behind the Frame Creator's refine chat: rewrite
/// the current form text per a new direction while preserving its sentiment.
enum FormRefineComposer {
    static func transformPrompt(
        current: String,
        directive: String,
        priorDirectives: [String]
    ) -> String {
        var lines: [String] = []
        lines.append("Rewrite this frame description per the new direction, preserving its exact sentiment — the emotional arc, the narrative spine, the relationships, and the stakes.")
        lines.append("")
        lines.append("New direction: \(directive.trimmed)")
        let prior = priorDirectives.map { $0.trimmed }.filter { !$0.isEmpty }
        if !prior.isEmpty {
            lines.append("Directions already applied — keep honoring them:")
            for direction in prior {
                lines.append("- \(direction)")
            }
        }
        lines.append("")
        lines.append("The current description:")
        lines.append(current.trimmed)
        lines.append("")
        lines.append("Rules:")
        lines.append("- Keep the beat structure and roughly the original length; every beat in the original should have a counterpart in the rewrite.")
        lines.append("- Change only what the direction requires: time, place, actors, objects, world. Everything the direction does not touch stays as it was.")
        lines.append("- Subject matter only — zero art direction: no color or palette words, no rendering-technique or medium words (ink, neon, painterly, photographic, halftone), no lighting-character adjectives, no art-movement references.")
        lines.append("- Preserve any \"@Name\" mention tokens exactly as written, including the \"@\"; they bind characters to reference images.")
        lines.append("- Plain prose only: no headings, no quotation marks, no lists.")
        lines.append("- Also produce a one-line note of what changed.")
        return lines.joined(separator: "\n")
    }
}
