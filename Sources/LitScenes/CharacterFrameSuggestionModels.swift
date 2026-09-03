import Foundation

/// Which identity image rides with the suggestion call.
enum CharacterFrameSuggestionIdentityImage: Equatable, Sendable {
    case none
    case sheet
    case sourcePhoto
}

/// THE SUGGESTABLE CHARACTER LAW: a character can drive Frame suggestions when it
/// has an active sheet in the inventory OR at least one source image there.
/// Inventory-based, never disk-based (pure).
struct CharacterSuggestionIdentity: Equatable, Sendable {
    var characterId: String
    /// "" when the active sheet is not in the inventory.
    var sheetMediaId: String
    /// `referenceMediaIds` that exist as image items, in order, composites excluded.
    var sourceMediaIds: [String]

    var isSuggestable: Bool { !sheetMediaId.isEmpty || !sourceMediaIds.isEmpty }
    /// The one image the text call attaches: the sheet, else the first source.
    var visionMediaId: String? { sheetMediaId.nilIfEmpty ?? sourceMediaIds.first }
    var identityImageKind: CharacterFrameSuggestionIdentityImage {
        if !sheetMediaId.isEmpty { return .sheet }
        return sourceMediaIds.isEmpty ? .none : .sourcePhoto
    }
}

func characterSuggestionIdentity(character: ProjectCharacter, items: [MediaItemRecord]) -> CharacterSuggestionIdentity {
    let sheetId = (character.activeSheetMediaId ?? "").trimmed
    let sheet = items.first { $0.mediaId == sheetId && $0.isCharacterSheet }
    let sources = character.referenceMediaIds.filter { id in
        items.contains { $0.mediaId == id && $0.kind == .image && !$0.isRosterCompositeSheet }
    }
    return CharacterSuggestionIdentity(
        characterId: character.characterId,
        sheetMediaId: sheet?.mediaId ?? "",
        sourceMediaIds: uniqueNonEmpty(sources)
    )
}

/// THE ATTEMPT KEY: one automatic suggestion call per session per character and
/// identity fingerprint — a new sheet or a changed source set earns one more.
func characterFrameSuggestionAttemptKey(projectId: String, identity: CharacterSuggestionIdentity) -> String {
    "\(projectId)|\(identity.characterId)|sheet=\(identity.sheetMediaId)|src=\(identity.sourceMediaIds.joined(separator: ","))"
}

/// Everything the character-moment suggestions prompt sees. Fixture-neutral by
/// law: every name arrives as data, never as a rule.
struct CharacterFrameSuggestionContext: Sendable {
    var projectId: String
    var projectName: String
    var characterId: String
    var characterName: String
    var characterAppearance: String
    var characterIdentityGist: String
    var otherCharacterLines: [String]
    var goalSummary: String
    var existingAreaLines: [String]
    var existingSceneLines: [String]
    var mediaObservationLines: [String]
    var sourceImageLines: String
    var attachedIdentityImage: CharacterFrameSuggestionIdentityImage
}

/// One suggested moment: an existing area by id, or a new area (at most one per
/// batch), the scene itself, and the moment — one sentence of visible dramatic
/// action. Tolerant decode: `area` is null when `area_ref` resolves.
struct CharacterFrameSuggestedScene: Codable, Hashable, Sendable {
    var areaRef: String = ""
    var area: LensArea?
    var scene: LensAreaScene = LensAreaScene()
    var moment: String = ""

    enum CodingKeys: String, CodingKey {
        case areaRef
        case area
        case scene
        case moment
    }

    init(areaRef: String = "", area: LensArea? = nil, scene: LensAreaScene = LensAreaScene(), moment: String = "") {
        self.areaRef = areaRef
        self.area = area
        self.scene = scene
        self.moment = moment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        areaRef = try container.decodeIfPresent(String.self, forKey: .areaRef) ?? ""
        area = try container.decodeIfPresent(LensArea.self, forKey: .area)
        scene = try container.decodeIfPresent(LensAreaScene.self, forKey: .scene) ?? LensAreaScene()
        moment = try container.decodeIfPresent(String.self, forKey: .moment) ?? ""
    }
}

struct CharacterFrameSuggestionResponse: Codable, Hashable, Sendable {
    static let currentSchemaVersion = "litscenes.character_frame_suggestions.v0.1"

    var schemaVersion: String = CharacterFrameSuggestionResponse.currentSchemaVersion
    var scenes: [CharacterFrameSuggestedScene] = []
    var castingNote: String = ""

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case scenes
        case castingNote
    }

    init(scenes: [CharacterFrameSuggestedScene] = [], castingNote: String = "") {
        self.scenes = scenes
        self.castingNote = castingNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        scenes = try container.decodeIfPresent([CharacterFrameSuggestedScene].self, forKey: .scenes) ?? []
        castingNote = try container.decodeIfPresent(String.self, forKey: .castingNote) ?? ""
    }

    static func decode(from data: Data) throws -> CharacterFrameSuggestionResponse {
        try JSONCoding.decoder.decode(CharacterFrameSuggestionResponse.self, from: data)
    }
}

struct OpenAICharacterFrameSuggestionResult: Sendable {
    var response: CharacterFrameSuggestionResponse
    var responseId: String
    var model: String
    var usage: OpenAIUsage
}

extension LensBody {
    /// Folds suggested scenes into the composed world: `areaRef` targets an
    /// existing area by id; at most one new area is minted per batch (a second
    /// new-area scene rides the first); every scene's cast is filtered to known
    /// names and forced to lead with the character. Fresh ids never collide with
    /// reserved ones (the `replannedWorld` re-mint idiom, salted). A minted area
    /// that ends scene-less is dropped — normalization would otherwise
    /// synthesize a frame for it.
    func appendingSuggestedScenes(
        _ suggestions: [CharacterFrameSuggestedScene],
        characterName: String,
        validCastNames: [String],
        salt: String
    ) -> (body: LensBody, newSceneIds: [String], momentsBySceneId: [String: String]) {
        var value = self
        var areas = (areas ?? []).enumerated().map { $0.element.normalized(order: $0.offset) }
        let reservedAreaIds = Set(areas.map(\.areaId))
        var reservedSceneIds = Set(areas.flatMap(\.scenes).map(\.sceneId))
        let canonicalNames = validCastNames.map(\.trimmed).filter { !$0.isEmpty }
        func canonical(_ name: String) -> String? {
            canonicalNames.first { $0.caseInsensitiveCompare(name.trimmed) == .orderedSame }
        }
        let lead = characterName.trimmed
        var mintedAreaIndexes: [Int] = []
        var newSceneIds: [String] = []
        var momentsBySceneId: [String: String] = [:]

        for suggestion in suggestions.prefix(2) {
            var areaIndex: Int?
            let ref = suggestion.areaRef.trimmed
            if !ref.isEmpty, let index = areas.firstIndex(where: { $0.areaId == ref }) {
                areaIndex = index
            } else if let candidate = suggestion.area {
                let title = candidate.title.trimmed.nilIfEmpty ?? candidate.setting.title.trimmed
                if let index = mintedAreaIndexes.first(where: { areas[$0].title.caseInsensitiveCompare(title) == .orderedSame }) {
                    areaIndex = index
                } else if let first = mintedAreaIndexes.first {
                    areaIndex = first
                } else {
                    var minted = LensArea()
                    minted.title = candidate.title
                    minted.setting = candidate.setting
                    minted.prosePrompt = candidate.prosePrompt
                    minted.enabled = true
                    minted = minted.normalized(order: areas.count)
                    // Normalization synthesizes a scene for a scene-less area;
                    // the suggestion's own scene is the only one this area gets.
                    minted.scenes = []
                    if reservedAreaIds.contains(minted.areaId) {
                        minted.areaId = "\(minted.areaId)_\(shortHash("\(salt):\(minted.areaId)", length: 6))"
                    }
                    areas.append(minted)
                    areaIndex = areas.count - 1
                    mintedAreaIndexes.append(areas.count - 1)
                }
            }
            guard let areaIndex else { continue }
            // Emptiness is judged on the raw scene: normalization would title it.
            guard !suggestion.scene.isEmpty else { continue }

            var scene = suggestion.scene
            scene.sceneId = ""
            scene.enabled = true
            var cast: [LensSceneCastEntry] = []
            for entry in scene.cast {
                guard let name = canonical(entry.name) else { continue }
                if cast.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { continue }
                cast.append(LensSceneCastEntry(name: name, presence: entry.presence))
            }
            let moment = suggestion.moment.trimmed
            if !lead.isEmpty {
                if let index = cast.firstIndex(where: { $0.name.caseInsensitiveCompare(lead) == .orderedSame }) {
                    if index != 0 { cast.swapAt(0, index) }
                } else {
                    cast.insert(LensSceneCastEntry(name: lead, presence: ""), at: 0)
                }
                // The lead's presence says what they do; the moment is the
                // fallback when the model left it blank.
                if cast[0].presence.trimmed.isEmpty, !moment.isEmpty {
                    cast[0].presence = moment
                }
            }
            scene.cast = Array(cast.prefix(2))
            scene = scene.normalized(areaId: areas[areaIndex].areaId, order: areas[areaIndex].scenes.count)
            if reservedSceneIds.contains(scene.sceneId) {
                scene.sceneId = "\(scene.sceneId)_\(shortHash("\(salt):\(scene.sceneId)", length: 6))"
            }
            reservedSceneIds.insert(scene.sceneId)
            areas[areaIndex].scenes.append(scene)
            newSceneIds.append(scene.sceneId)
            momentsBySceneId[scene.sceneId] = moment
        }

        let mintedIds = Set(mintedAreaIndexes.map { areas[$0].areaId })
        value.areas = areas.filter { !(mintedIds.contains($0.areaId) && $0.scenes.isEmpty) }
        return (value, newSceneIds, momentsBySceneId)
    }
}
