import Foundation

/// A defined character of the project: a unique name, a description prompt, and the
/// ordered project media the user has organized under it. At generation time a selected
/// character's leading reference media attach as name-keyed character reference images.
struct ProjectCharacter: Codable, Hashable, Identifiable, Sendable {
    var characterId: String
    var name: String
    var descriptionPrompt: String = ""
    /// Ordered MediaItemRecord.mediaId values; the first entries are the strongest
    /// references and attach first (up to the per-character attachment budget).
    var referenceMediaIds: [String] = []
    /// Optional per-reference labels keyed by mediaId ("young Ava", "Ava with her
    /// favorite dog"). Labels on attached references also ride the render manifest so
    /// generation knows what each image shows. Keys not in referenceMediaIds prune on
    /// normalize.
    var referenceLabels: [String: String] = [:]
    /// Distinctive props this character consistently carries or wears.
    var signatureProps: [String] = []
    /// The environment this character visually belongs to, as plain content.
    var environmentAffinity: String = ""
    /// The generated character sheet that anchors identity for every render; nil until
    /// the first sheet renders. Sheets are media items of the character-sheet kind.
    var activeSheetMediaId: String?
    /// Refinements accumulated by the character conversation; each one is an
    /// imperative line about how the sheet should render.
    var sheetDirectives: [String] = []
    /// Hash of the sheet prompt the active sheet rendered from — a mismatch means the
    /// prompt moved on and the stage says so.
    var activeSheetPromptHash: String = ""
    /// Whether each conversation turn also renders a new sheet; nil reads as on.
    var autoRenderSheetAfterChat: Bool?
    /// The operator's hand-edited sheet prompt; nil renders the composed prompt.
    /// Never empty after normalization.
    var sheetPromptOverride: String?
    /// Hash of the composed prompt at the moment the override was taken; a mismatch
    /// means the identity moved on underneath the hand-edited text. Empty without an
    /// override.
    var sheetPromptOverrideBaseHash: String = ""
    /// The render stack this character's sheets and studies render on; nil reads as
    /// the default stack.
    var sheetStackId: String?
    /// Prompt hash per rendered sheet (mediaId → hash), so switching versions restores
    /// the currency that sheet was actually rendered with.
    var sheetPromptHashes: [String: String] = [:]
    var updatedAt: String = DateFormats.now()

    /// Safety net for the persisted override, not a UX cap.
    static let sheetPromptOverrideMaxLength = 12_000

    var id: String { characterId }

    var rendersSheetAfterChat: Bool { autoRenderSheetAfterChat ?? true }

    var hasSheetPromptOverride: Bool { sheetPromptOverride != nil }

    /// USE THIS VERSION: the sheet anchors and its own rendered hash returns; a sheet
    /// rendered before hashes were kept per version reads as unknown (not current).
    mutating func activateSheet(mediaId: String) {
        activeSheetMediaId = mediaId
        activeSheetPromptHash = sheetPromptHashes[mediaId] ?? ""
    }

    /// A render landed: the sheet anchors and the prompt it rendered from is remembered.
    mutating func recordRenderedSheet(mediaId: String, promptHash: String) {
        sheetPromptHashes[mediaId] = promptHash
        activeSheetMediaId = mediaId
        activeSheetPromptHash = promptHash
    }

    func normalized() -> ProjectCharacter {
        var value = self
        value.characterId = value.characterId.trimmed
        if value.characterId.isEmpty {
            value.characterId = "character_\(shortHash("\(value.name):\(value.updatedAt)", length: 12))"
        }
        value.name = value.name.trimmed
        value.descriptionPrompt = value.descriptionPrompt.trimmed
        value.referenceMediaIds = uniqueNonEmpty(value.referenceMediaIds)
        let knownIds = Set(value.referenceMediaIds)
        value.referenceLabels = value.referenceLabels.reduce(into: [:]) { labels, pair in
            let mediaId = pair.key.trimmed
            let label = pair.value.trimmed
            guard !mediaId.isEmpty, !label.isEmpty, knownIds.contains(mediaId) else { return }
            labels[mediaId] = label
        }
        value.signatureProps = Array(uniqueNonEmpty(value.signatureProps).prefix(3))
        value.environmentAffinity = value.environmentAffinity.trimmed
        value.activeSheetMediaId = value.activeSheetMediaId?.trimmed.nilIfEmpty
        value.sheetDirectives = Array(
            uniqueNonEmpty(value.sheetDirectives).map { String($0.prefix(240)) }.prefix(12)
        )
        value.activeSheetPromptHash = value.activeSheetPromptHash.trimmed
        value.sheetPromptOverride = value.sheetPromptOverride?.trimmed.nilIfEmpty
            .map { String($0.prefix(Self.sheetPromptOverrideMaxLength)) }
        value.sheetPromptOverrideBaseHash = value.sheetPromptOverride == nil
            ? ""
            : value.sheetPromptOverrideBaseHash.trimmed
        value.sheetStackId = value.sheetStackId?.trimmed.nilIfEmpty
        value.sheetPromptHashes = value.sheetPromptHashes.reduce(into: [:]) { hashes, pair in
            let mediaId = pair.key.trimmed
            let hash = pair.value.trimmed
            guard !mediaId.isEmpty, !hash.isEmpty else { return }
            hashes[mediaId] = hash
        }
        value.updatedAt = value.updatedAt.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case characterId
        case name
        case descriptionPrompt
        case referenceMediaIds
        case referenceLabels
        case signatureProps
        case environmentAffinity
        case activeSheetMediaId
        case sheetDirectives
        case activeSheetPromptHash
        case autoRenderSheetAfterChat
        case sheetPromptOverride
        case sheetPromptOverrideBaseHash
        case sheetStackId
        case sheetPromptHashes
        case updatedAt
    }

    init(
        characterId: String,
        name: String,
        descriptionPrompt: String = "",
        referenceMediaIds: [String] = [],
        referenceLabels: [String: String] = [:],
        signatureProps: [String] = [],
        environmentAffinity: String = "",
        activeSheetMediaId: String? = nil,
        sheetDirectives: [String] = [],
        activeSheetPromptHash: String = "",
        autoRenderSheetAfterChat: Bool? = nil,
        sheetPromptOverride: String? = nil,
        sheetPromptOverrideBaseHash: String = "",
        sheetStackId: String? = nil,
        sheetPromptHashes: [String: String] = [:],
        updatedAt: String = DateFormats.now()
    ) {
        self.characterId = characterId
        self.name = name
        self.descriptionPrompt = descriptionPrompt
        self.referenceMediaIds = referenceMediaIds
        self.referenceLabels = referenceLabels
        self.signatureProps = signatureProps
        self.environmentAffinity = environmentAffinity
        self.activeSheetMediaId = activeSheetMediaId
        self.sheetDirectives = sheetDirectives
        self.activeSheetPromptHash = activeSheetPromptHash
        self.autoRenderSheetAfterChat = autoRenderSheetAfterChat
        self.sheetPromptOverride = sheetPromptOverride
        self.sheetPromptOverrideBaseHash = sheetPromptOverrideBaseHash
        self.sheetStackId = sheetStackId
        self.sheetPromptHashes = sheetPromptHashes
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        characterId = try container.decodeIfPresent(String.self, forKey: .characterId) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        descriptionPrompt = try container.decodeIfPresent(String.self, forKey: .descriptionPrompt) ?? ""
        referenceMediaIds = try container.decodeIfPresent([String].self, forKey: .referenceMediaIds) ?? []
        referenceLabels = try container.decodeIfPresent([String: String].self, forKey: .referenceLabels) ?? [:]
        signatureProps = try container.decodeIfPresent([String].self, forKey: .signatureProps) ?? []
        environmentAffinity = try container.decodeIfPresent(String.self, forKey: .environmentAffinity) ?? ""
        activeSheetMediaId = try container.decodeIfPresent(String.self, forKey: .activeSheetMediaId)
        sheetDirectives = try container.decodeIfPresent([String].self, forKey: .sheetDirectives) ?? []
        activeSheetPromptHash = try container.decodeIfPresent(String.self, forKey: .activeSheetPromptHash) ?? ""
        autoRenderSheetAfterChat = try container.decodeIfPresent(Bool.self, forKey: .autoRenderSheetAfterChat)
        sheetPromptOverride = try container.decodeIfPresent(String.self, forKey: .sheetPromptOverride)
        sheetPromptOverrideBaseHash = try container.decodeIfPresent(String.self, forKey: .sheetPromptOverrideBaseHash) ?? ""
        sheetStackId = try container.decodeIfPresent(String.self, forKey: .sheetStackId)
        sheetPromptHashes = try container.decodeIfPresent([String: String].self, forKey: .sheetPromptHashes) ?? [:]
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
        self = normalized()
    }
}

/// The project's character roster, persisted as one project document (no table change).
struct ProjectCharacterSetDocument: Codable, Hashable {
    static let schemaVersion = "litscenes.project_characters.v0.1"
    static let documentType = "project_characters"

    var schemaVersion: String = ProjectCharacterSetDocument.schemaVersion
    var projectId: String = ""
    var characters: [ProjectCharacter] = []
    var updatedAt: String = ""

    static func empty(projectId: String) -> ProjectCharacterSetDocument {
        ProjectCharacterSetDocument(projectId: projectId)
    }

    func character(withId characterId: String) -> ProjectCharacter? {
        characters.first { $0.characterId == characterId }
    }

    /// Case-insensitive uniqueness check for a (possibly renamed) character's name.
    func nameIsAvailable(_ name: String, excludingCharacterId: String? = nil) -> Bool {
        let candidate = name.trimmed.lowercased()
        guard !candidate.isEmpty else { return false }
        return !characters.contains {
            $0.characterId != excludingCharacterId && $0.name.trimmed.lowercased() == candidate
        }
    }

    func normalized() -> ProjectCharacterSetDocument {
        var value = self
        value.schemaVersion = Self.schemaVersion
        value.projectId = value.projectId.trimmed
        var seenIds: Set<String> = []
        var seenNames: Set<String> = []
        value.characters = value.characters
            .map { $0.normalized() }
            .filter { character in
                guard !character.name.isEmpty,
                      !seenIds.contains(character.characterId),
                      !seenNames.contains(character.name.lowercased()) else {
                    return false
                }
                seenIds.insert(character.characterId)
                seenNames.insert(character.name.lowercased())
                return true
            }
        value.updatedAt = value.updatedAt.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case characters
        case updatedAt
    }

    init(schemaVersion: String = ProjectCharacterSetDocument.schemaVersion, projectId: String = "", characters: [ProjectCharacter] = [], updatedAt: String = "") {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.characters = characters
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        characters = try container.decodeIfPresent([ProjectCharacter].self, forKey: .characters) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        self = normalized()
    }
}
