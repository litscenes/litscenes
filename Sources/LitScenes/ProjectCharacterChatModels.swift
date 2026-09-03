import Foundation

/// One turn of a character's refinement conversation.
struct CharacterChatTurn: Codable, Hashable, Identifiable, Sendable {
    var turnId: String
    var role: ProjectGoalV2Role
    var text: String
    var mediaIds: [String] = []
    var createdAt: String

    var id: String { turnId }

    enum CodingKeys: String, CodingKey {
        case turnId
        case role
        case text
        case mediaIds
        case createdAt
    }

    init(turnId: String, role: ProjectGoalV2Role, text: String, mediaIds: [String] = [], createdAt: String) {
        self.turnId = turnId
        self.role = role
        self.text = text
        self.mediaIds = mediaIds
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turnId = try container.decodeIfPresent(String.self, forKey: .turnId) ?? ""
        role = try container.decodeIfPresent(ProjectGoalV2Role.self, forKey: .role) ?? .user
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        mediaIds = try container.decodeIfPresent([String].self, forKey: .mediaIds) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }

    func normalized() -> CharacterChatTurn {
        var value = self
        value.turnId = value.turnId.trimmed
        value.text = value.text.trimmed
        value.mediaIds = uniqueNonEmpty(value.mediaIds)
        value.createdAt = value.createdAt.trimmed
        return value
    }
}

/// A character's conversation: capped to the newest turns so the document stays small.
struct CharacterChatThread: Codable, Hashable, Identifiable, Sendable {
    static let maximumTurns = 60

    var characterId: String
    var turns: [CharacterChatTurn] = []
    var updatedAt: String = ""

    var id: String { characterId }

    enum CodingKeys: String, CodingKey {
        case characterId
        case turns
        case updatedAt
    }

    init(characterId: String, turns: [CharacterChatTurn] = [], updatedAt: String = "") {
        self.characterId = characterId
        self.turns = turns
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        characterId = try container.decodeIfPresent(String.self, forKey: .characterId) ?? ""
        turns = try container.decodeIfPresent([CharacterChatTurn].self, forKey: .turns) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    func normalized() -> CharacterChatThread {
        var value = self
        value.characterId = value.characterId.trimmed
        var seen: Set<String> = []
        value.turns = value.turns
            .map { $0.normalized() }
            .filter { turn in
                guard !turn.turnId.isEmpty, !seen.contains(turn.turnId) else { return false }
                seen.insert(turn.turnId)
                return !turn.text.isEmpty || !turn.mediaIds.isEmpty
            }
        if value.turns.count > Self.maximumTurns {
            value.turns.removeFirst(value.turns.count - Self.maximumTurns)
        }
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

/// Every character conversation of a project, one document (no table change).
struct ProjectCharacterChatDocument: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.project_character_chats.v0.1"
    static let documentType = "project_character_chats"
    static let maximumThreads = 64

    var schemaVersion: String = ProjectCharacterChatDocument.schemaVersion
    var projectId: String = ""
    var threads: [CharacterChatThread] = []
    var updatedAt: String = ""

    static func empty(projectId: String) -> ProjectCharacterChatDocument {
        ProjectCharacterChatDocument(projectId: projectId)
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case threads
        case updatedAt
    }

    init(
        schemaVersion: String = ProjectCharacterChatDocument.schemaVersion,
        projectId: String = "",
        threads: [CharacterChatThread] = [],
        updatedAt: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.threads = threads
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        threads = try container.decodeIfPresent([CharacterChatThread].self, forKey: .threads) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        self = normalized()
    }

    func thread(for characterId: String) -> CharacterChatThread? {
        threads.first { $0.characterId == characterId }
    }

    /// Appends a turn to the character's thread (creating it) and returns the minted turn.
    @discardableResult
    mutating func appendTurn(
        characterId: String,
        role: ProjectGoalV2Role,
        text: String,
        mediaIds: [String] = [],
        now: String
    ) -> CharacterChatTurn {
        let index = threads.firstIndex { $0.characterId == characterId }
        let existingCount = index.map { threads[$0].turns.count } ?? 0
        let turn = CharacterChatTurn(
            turnId: "cturn_\(shortHash("\(characterId):\(role.rawValue):\(now):\(existingCount):\(text)", length: 12))",
            role: role,
            text: text.trimmed,
            mediaIds: uniqueNonEmpty(mediaIds),
            createdAt: now
        )
        if let index {
            threads[index].turns.append(turn)
            threads[index].updatedAt = now
            threads[index] = threads[index].normalized()
        } else {
            threads.append(CharacterChatThread(characterId: characterId, turns: [turn], updatedAt: now).normalized())
        }
        updatedAt = now
        return turn
    }

    mutating func removeThread(characterId: String) {
        threads.removeAll { $0.characterId == characterId }
    }

    /// Drops threads whose character left the roster.
    func pruned(keepingCharacterIds known: Set<String>) -> ProjectCharacterChatDocument {
        var value = self
        value.threads.removeAll { !known.contains($0.characterId) }
        return value
    }

    func normalized() -> ProjectCharacterChatDocument {
        var value = self
        value.schemaVersion = Self.schemaVersion
        value.projectId = value.projectId.trimmed
        var seen: Set<String> = []
        // Last thread wins on a duplicate id: it carries the newest turns.
        var deduped: [CharacterChatThread] = []
        for thread in value.threads.reversed().map({ $0.normalized() }) {
            guard !thread.characterId.isEmpty, !seen.contains(thread.characterId) else { continue }
            seen.insert(thread.characterId)
            deduped.append(thread)
        }
        value.threads = Array(deduped.reversed().suffix(Self.maximumThreads))
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

/// A source image the model labeled during a refinement turn.
struct CharacterSheetRefineSourceNote: Codable, Hashable, Sendable {
    var mediaId: String = ""
    var label: String = ""
}

/// The strict JSON a refinement turn returns.
struct CharacterSheetRefineResponse: Codable, Hashable, Sendable {
    var schemaVersion: String = "litscenes.character_sheet_refine_response.v0.1"
    var assistantMessage: String = ""
    /// Full replacement appearance line; empty keeps the current one.
    var visualDescription: String = ""
    /// Full replacement list; empty keeps the current props.
    var signatureProps: [String] = []
    /// The COMPLETE directive list in force after this turn.
    var sheetDirectives: [String] = []
    var sourceImageNotes: [CharacterSheetRefineSourceNote] = []
    var changeSummary: String = ""

    static func decode(from data: Data) throws -> CharacterSheetRefineResponse {
        try JSONCoding.decoder.decode(CharacterSheetRefineResponse.self, from: data)
    }
}

/// What a conversation turn does about the sheet once identity changes land.
enum CharacterChatAutoRenderDecision: Equatable, Sendable {
    case render(status: String)
    case skip(status: String)

    var status: String {
        switch self {
        case .render(let status), .skip(let status): return status
        }
    }
}

/// THE AUTO-RENDER LAW after a conversation turn: nothing changed → nothing renders;
/// a hand-edited prompt swallows identity changes, so the turn reports that instead of
/// spending a render on an unchanged prompt; then the usual gates — the toggle, a
/// stack, its credential, and a free lane.
enum CharacterChatAutoRender {
    static func decision(
        name: String,
        changed: Bool,
        rendersAfterChat: Bool,
        hasOverride: Bool,
        hasStack: Bool,
        stackBlocker: String?,
        isBusy: Bool
    ) -> CharacterChatAutoRenderDecision {
        let subject = name.trimmed.isEmpty ? "the character" : name.trimmed
        guard changed else { return .skip(status: "Nothing about \(subject) changed") }
        if hasOverride {
            return .skip(status: "\(subject)'s identity updated — the hand-edited prompt still renders; reset or edit it to include this change")
        }
        guard rendersAfterChat, hasStack else { return .skip(status: "Sheet prompt updated — render to see it") }
        if let stackBlocker, !stackBlocker.trimmed.isEmpty {
            return .skip(status: "Sheet prompt updated — \(stackBlocker.trimmed)")
        }
        if isBusy {
            return .skip(status: "Sheet prompt updated — a render is already running; render again when it finishes")
        }
        return .render(status: "Sheet prompt updated — rendering \(subject)'s sheet")
    }
}
