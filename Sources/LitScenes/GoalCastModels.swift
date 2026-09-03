import Foundation

// GOAL-stage cast: each nascent character articulated as a steerable "unusual character"
// identity (familiar legibility + ONE deep contradiction + a private operating rule +
// visible consequences), stored as per-member take stacks in its own project document.
// Supersedes the unwired StoryCharacterRecord (Models.swift) for goal-stage identity —
// do not wire that dormant type.

// MARK: - Dimensions

/// Canonical dimension keys — the merge/pin vocabulary. Raw values are the snake_case
/// field names used in schemas, prompts, and `GoalCastMember.pinnedDimensions`.
enum GoalCastDimension: String, CaseIterable, Codable, Hashable, Sendable {
    case essence
    case publicFunction = "public_function"
    case desire
    case operatingRule = "operating_rule"
    case cost
    case signature
    case formativePressure = "formative_pressure"
    case strangeness
    case visualDescription = "visual_description"
}

/// Orders pin keys stably (declaration order) and drops unknown keys.
func normalizedGoalCastPinKeys(_ keys: [String]) -> [String] {
    let known = Set(keys.compactMap { GoalCastDimension(rawValue: $0.trimmed) })
    return GoalCastDimension.allCases.filter { known.contains($0) }.map(\.rawValue)
}

// MARK: - Identity

/// One articulated take on who a character is. `strangeness` is the distance between
/// the familiar archetype (`publicFunction`) and the incongruous `desire` — 0 is a
/// legitimate steady state (an entirely ordinary character, no manufactured
/// contradiction). `visualDescription` is the render-facing line that syncs to the
/// roster's `descriptionPrompt`.
struct GoalCastIdentity: Codable, Hashable, Sendable {
    var essence: String = ""
    var publicFunction: String = ""
    var desire: String = ""
    var operatingRule: String = ""
    var cost: String = ""
    var signature: String = ""
    var formativePressure: String = ""
    var strangeness: Double = 0.5
    var visualDescription: String = ""

    func normalized() -> GoalCastIdentity {
        var value = self
        value.essence = value.essence.trimmed
        value.publicFunction = value.publicFunction.trimmed
        value.desire = value.desire.trimmed
        value.operatingRule = value.operatingRule.trimmed
        value.cost = value.cost.trimmed
        value.signature = value.signature.trimmed
        value.formativePressure = value.formativePressure.trimmed
        value.strangeness = min(1, max(0, value.strangeness))
        value.visualDescription = value.visualDescription.trimmed
        return value
    }

    /// String dimension accessor; nil for `.strangeness` (the only numeric dimension).
    func value(for dimension: GoalCastDimension) -> String? {
        switch dimension {
        case .essence: return essence
        case .publicFunction: return publicFunction
        case .desire: return desire
        case .operatingRule: return operatingRule
        case .cost: return cost
        case .signature: return signature
        case .formativePressure: return formativePressure
        case .strangeness: return nil
        case .visualDescription: return visualDescription
        }
    }

    mutating func setValue(_ newValue: String, for dimension: GoalCastDimension) {
        switch dimension {
        case .essence: essence = newValue
        case .publicFunction: publicFunction = newValue
        case .desire: desire = newValue
        case .operatingRule: operatingRule = newValue
        case .cost: cost = newValue
        case .signature: signature = newValue
        case .formativePressure: formativePressure = newValue
        case .strangeness: break
        case .visualDescription: visualDescription = newValue
        }
    }

    /// One-line identity gist ("wants …; rule: …; cost: …; tell: …"), nil when empty —
    /// appended to composition roster lines so scene authoring can stage the contradiction.
    var gist: String? {
        var parts: [String] = []
        if !desire.isEmpty { parts.append("wants \(desire)") }
        if !operatingRule.isEmpty { parts.append("rule: \(operatingRule)") }
        if !cost.isEmpty { parts.append("cost: \(cost)") }
        if !signature.isEmpty { parts.append("tell: \(signature)") }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    enum CodingKeys: String, CodingKey {
        case essence
        case publicFunction
        case desire
        case operatingRule
        case cost
        case signature
        case formativePressure
        case strangeness
        case visualDescription
    }

    init(
        essence: String = "",
        publicFunction: String = "",
        desire: String = "",
        operatingRule: String = "",
        cost: String = "",
        signature: String = "",
        formativePressure: String = "",
        strangeness: Double = 0.5,
        visualDescription: String = ""
    ) {
        self.essence = essence
        self.publicFunction = publicFunction
        self.desire = desire
        self.operatingRule = operatingRule
        self.cost = cost
        self.signature = signature
        self.formativePressure = formativePressure
        self.strangeness = strangeness
        self.visualDescription = visualDescription
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        essence = try container.decodeIfPresent(String.self, forKey: .essence) ?? ""
        publicFunction = try container.decodeIfPresent(String.self, forKey: .publicFunction) ?? ""
        desire = try container.decodeIfPresent(String.self, forKey: .desire) ?? ""
        operatingRule = try container.decodeIfPresent(String.self, forKey: .operatingRule) ?? ""
        cost = try container.decodeIfPresent(String.self, forKey: .cost) ?? ""
        signature = try container.decodeIfPresent(String.self, forKey: .signature) ?? ""
        formativePressure = try container.decodeIfPresent(String.self, forKey: .formativePressure) ?? ""
        strangeness = try container.decodeIfPresent(Double.self, forKey: .strangeness) ?? 0.5
        visualDescription = try container.decodeIfPresent(String.self, forKey: .visualDescription) ?? ""
        self = normalized()
    }
}

// MARK: - Takes

/// One version of a member's identity. `origin` is the gesture provenance shown as the
/// cycler tooltip: "initial", "stranger", "tamer", "new-rule", "raise-cost", "new-tell",
/// "feedback: …", "chat: …", "re-articulated".
struct GoalCastTake: Codable, Hashable, Identifiable, Sendable {
    var takeId: String
    var origin: String = "initial"
    var identity: GoalCastIdentity = GoalCastIdentity()
    var createdAt: String = DateFormats.now()

    var id: String { takeId }

    static func minted(origin: String, identity: GoalCastIdentity, now: String = DateFormats.now()) -> GoalCastTake {
        GoalCastTake(
            takeId: "take_\(shortHash("\(origin):\(now):\(UUID().uuidString)", length: 12))",
            origin: origin,
            identity: identity,
            createdAt: now
        )
    }

    func normalized() -> GoalCastTake {
        var value = self
        value.takeId = value.takeId.trimmed
        if value.takeId.isEmpty {
            value.takeId = "take_\(shortHash("\(value.origin):\(value.createdAt):\(value.identity.essence)", length: 12))"
        }
        value.origin = value.origin.trimmed
        if value.origin.isEmpty { value.origin = "initial" }
        value.identity = value.identity.normalized()
        value.createdAt = value.createdAt.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case takeId
        case origin
        case identity
        case createdAt
    }

    init(takeId: String, origin: String = "initial", identity: GoalCastIdentity = GoalCastIdentity(), createdAt: String = DateFormats.now()) {
        self.takeId = takeId
        self.origin = origin
        self.identity = identity
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        takeId = try container.decodeIfPresent(String.self, forKey: .takeId) ?? ""
        origin = try container.decodeIfPresent(String.self, forKey: .origin) ?? "initial"
        identity = try container.decodeIfPresent(GoalCastIdentity.self, forKey: .identity) ?? GoalCastIdentity()
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? DateFormats.now()
        self = normalized()
    }
}

// MARK: - Members

struct GoalCastMember: Codable, Hashable, Identifiable, Sendable {
    static let maximumTakes = 8

    var memberId: String
    var name: String
    /// From the matching required entity's role when covered; display-only.
    var roleLabel: String = ""
    /// Linked roster ProjectCharacter.characterId once synced.
    var characterId: String = ""
    var takes: [GoalCastTake] = []
    var activeTakeId: String = ""
    /// GoalCastDimension raw values held keep-exactly through steers and re-articulation.
    var pinnedDimensions: [String] = []
    var updatedAt: String = DateFormats.now()

    var id: String { memberId }

    var activeTake: GoalCastTake? {
        takes.first { $0.takeId == activeTakeId } ?? takes.last
    }

    var activeIdentity: GoalCastIdentity { activeTake?.identity ?? GoalCastIdentity() }

    var pinnedDimensionSet: Set<GoalCastDimension> {
        Set(pinnedDimensions.compactMap(GoalCastDimension.init(rawValue:)))
    }

    /// The single mutation path for takes: append, evict oldest past the cap, activate.
    mutating func appendTake(_ take: GoalCastTake, now: String) {
        let normalizedTake = take.normalized()
        takes.append(normalizedTake)
        if takes.count > Self.maximumTakes {
            takes.removeFirst(takes.count - Self.maximumTakes)
        }
        activeTakeId = normalizedTake.takeId
        updatedAt = now
    }

    /// Context line for articulation/interview prompts.
    var contextSummaryLine: String {
        let identity = activeIdentity
        var line = "- \(name)"
        if !roleLabel.isEmpty { line += " (\(roleLabel))" }
        if !identity.essence.isEmpty { line += " — \(identity.essence)" }
        if let gist = identity.gist { line += " | \(gist)" }
        line += String(format: " | strangeness %.2f", identity.strangeness)
        if !pinnedDimensions.isEmpty { line += " | pinned: \(pinnedDimensions.joined(separator: ", "))" }
        return line
    }

    func normalized() -> GoalCastMember {
        var value = self
        value.name = value.name.trimmed
        value.memberId = value.memberId.trimmed
        if value.memberId.isEmpty {
            value.memberId = "castmember_\(shortHash("\(value.name):\(value.updatedAt)", length: 12))"
        }
        value.roleLabel = value.roleLabel.trimmed
        value.characterId = value.characterId.trimmed
        var seenTakeIds: Set<String> = []
        value.takes = value.takes
            .map { $0.normalized() }
            .filter { take in
                guard !seenTakeIds.contains(take.takeId) else { return false }
                seenTakeIds.insert(take.takeId)
                return true
            }
        if value.takes.count > Self.maximumTakes {
            value.takes = Array(value.takes.suffix(Self.maximumTakes))
        }
        value.activeTakeId = value.activeTakeId.trimmed
        if !value.takes.contains(where: { $0.takeId == value.activeTakeId }) {
            value.activeTakeId = value.takes.last?.takeId ?? ""
        }
        value.pinnedDimensions = normalizedGoalCastPinKeys(value.pinnedDimensions)
        value.updatedAt = value.updatedAt.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case memberId
        case name
        case roleLabel
        case characterId
        case takes
        case activeTakeId
        case pinnedDimensions
        case updatedAt
    }

    init(
        memberId: String,
        name: String,
        roleLabel: String = "",
        characterId: String = "",
        takes: [GoalCastTake] = [],
        activeTakeId: String = "",
        pinnedDimensions: [String] = [],
        updatedAt: String = DateFormats.now()
    ) {
        self.memberId = memberId
        self.name = name
        self.roleLabel = roleLabel
        self.characterId = characterId
        self.takes = takes
        self.activeTakeId = activeTakeId
        self.pinnedDimensions = pinnedDimensions
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        memberId = try container.decodeIfPresent(String.self, forKey: .memberId) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        roleLabel = try container.decodeIfPresent(String.self, forKey: .roleLabel) ?? ""
        characterId = try container.decodeIfPresent(String.self, forKey: .characterId) ?? ""
        takes = try container.decodeIfPresent([GoalCastTake].self, forKey: .takes) ?? []
        activeTakeId = try container.decodeIfPresent(String.self, forKey: .activeTakeId) ?? ""
        pinnedDimensions = try container.decodeIfPresent([String].self, forKey: .pinnedDimensions) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
        self = normalized()
    }
}

// MARK: - Document

/// The project's goal cast, persisted as one project document (no table change).
/// Deliberately NOT part of ProjectGoalBriefV2: interview turns replace the brief
/// wholesale, and steered characters must never ride that churn.
struct GoalCastDocument: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.goal_cast.v0.1"
    static let documentType = "project_goal_cast"
    static let maximumMembers = 12

    var schemaVersion: String = GoalCastDocument.schemaVersion
    var projectId: String = ""
    /// Goal version the last articulation ran against (staleness display only).
    var goalVersionId: String = ""
    /// Empty until the first successful articulation — the auto-articulate gate.
    /// (Gate on this, not members.isEmpty: a chat-added member before first articulation
    /// must not suppress ensemble completion.)
    var articulatedAt: String = ""
    var members: [GoalCastMember] = []
    var updatedAt: String = ""

    static func empty(projectId: String) -> GoalCastDocument {
        GoalCastDocument(projectId: projectId)
    }

    func member(withId memberId: String) -> GoalCastMember? {
        members.first { $0.memberId == memberId }
    }

    /// Case-insensitive trimmed name match.
    func member(named name: String) -> GoalCastMember? {
        let candidate = name.trimmed.lowercased()
        guard !candidate.isEmpty else { return nil }
        return members.first { $0.name.trimmed.lowercased() == candidate }
    }

    /// Context lines for the interview prompt's "Current cast" section.
    var interviewContextSummary: String {
        members.map(\.contextSummaryLine).joined(separator: "\n")
    }

    func normalized() -> GoalCastDocument {
        var value = self
        value.schemaVersion = Self.schemaVersion
        value.projectId = value.projectId.trimmed
        value.goalVersionId = value.goalVersionId.trimmed
        value.articulatedAt = value.articulatedAt.trimmed
        var seenIds: Set<String> = []
        var seenNames: Set<String> = []
        value.members = value.members
            .map { $0.normalized() }
            .filter { member in
                guard !member.name.isEmpty,
                      !seenIds.contains(member.memberId),
                      !seenNames.contains(member.name.lowercased()) else {
                    return false
                }
                seenIds.insert(member.memberId)
                seenNames.insert(member.name.lowercased())
                return true
            }
        if value.members.count > Self.maximumMembers {
            value.members = Array(value.members.prefix(Self.maximumMembers))
        }
        value.updatedAt = value.updatedAt.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case goalVersionId
        case articulatedAt
        case members
        case updatedAt
    }

    init(
        schemaVersion: String = GoalCastDocument.schemaVersion,
        projectId: String = "",
        goalVersionId: String = "",
        articulatedAt: String = "",
        members: [GoalCastMember] = [],
        updatedAt: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.goalVersionId = goalVersionId
        self.articulatedAt = articulatedAt
        self.members = members
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        goalVersionId = try container.decodeIfPresent(String.self, forKey: .goalVersionId) ?? ""
        articulatedAt = try container.decodeIfPresent(String.self, forKey: .articulatedAt) ?? ""
        members = try container.decodeIfPresent([GoalCastMember].self, forKey: .members) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        self = normalized()
    }
}

// MARK: - Steer gestures

/// A one-tap steering gesture on a member card (or its free-text feedback field).
enum GoalCastSteerGesture: Hashable, Sendable {
    case stranger
    case tamer
    case newRule
    case raiseCost
    case newTell
    case feedback(String)

    /// Keyword handed to the steer prompt's gesture-semantics section.
    var promptKeyword: String {
        switch self {
        case .stranger: return "stranger"
        case .tamer: return "tamer"
        case .newRule: return "new-rule"
        case .raiseCost: return "raise-cost"
        case .newTell: return "new-tell"
        case .feedback: return "feedback"
        }
    }

    /// Take provenance label shown in the cycler tooltip.
    var originLabel: String {
        switch self {
        case .feedback(let text):
            let trimmed = text.trimmed
            guard !trimmed.isEmpty else { return "feedback" }
            let clipped = trimmed.count > 80 ? "\(trimmed.prefix(80))…" : trimmed
            return "feedback: \(clipped)"
        default:
            return promptKeyword
        }
    }

    /// The anti-overfit allowed-change set: fields outside it copy forward verbatim from
    /// the prior take. `visualDescription` rides with `signature` everywhere so the
    /// roster never ships a description that doesn't show the tell. nil for `.feedback`
    /// — its set comes from the response's `changed_fields`.
    var allowedDimensions: Set<GoalCastDimension>? {
        switch self {
        case .stranger, .tamer:
            return [.strangeness, .desire, .essence, .operatingRule, .cost, .signature, .visualDescription]
        case .newRule:
            return [.operatingRule, .cost, .signature, .essence, .visualDescription]
        case .raiseCost:
            return [.cost, .signature, .visualDescription]
        case .newTell:
            return [.signature, .visualDescription]
        case .feedback:
            return nil
        }
    }
}

// MARK: - Field-wise merge

/// THE merge — every identity mutation flows through it. Only dimensions in
/// `(allowed ∖ pinned) ∪ (pinOverride ∩ allowed)` accept the emitted value; everything
/// else copies forward from `prior` verbatim, so the model structurally cannot rewrite
/// fields it wasn't asked to touch. String dimensions additionally keep the prior value
/// when the emitted one is empty (a claimed change with no content). `pinOverride` is
/// the chat-patch user-authored set — direct user text outranks pins; panel gestures
/// never do.
func mergedGoalCastIdentity(
    prior: GoalCastIdentity,
    emitted: GoalCastIdentity,
    allowed: Set<GoalCastDimension>,
    pinned: Set<GoalCastDimension>,
    pinOverride: Set<GoalCastDimension> = []
) -> GoalCastIdentity {
    let effective = allowed.subtracting(pinned).union(pinOverride.intersection(allowed))
    var merged = prior
    for dimension in effective {
        if dimension == .strangeness {
            merged.strangeness = emitted.strangeness
            continue
        }
        let emittedValue = emitted.value(for: dimension)?.trimmed ?? ""
        guard !emittedValue.isEmpty else { continue }
        merged.setValue(emittedValue, for: dimension)
    }
    return merged.normalized()
}

// MARK: - Chat delta channel

/// One per-character patch from the interview's `cast_updates` delta channel. Empty
/// strings (and nil strangeness) mean "field not addressed — keep". The interview
/// prompt requires patches only when the user's latest message explicitly asked to
/// change, add, or remove a character.
struct ProjectGoalCastUpdate: Codable, Hashable, Sendable {
    var targetName: String = ""
    /// "add" | "update" | "remove"; decoded as a plain string — unknown actions drop in
    /// the sanitizer instead of failing the whole response decode.
    var action: String = ""
    var essence: String = ""
    var publicFunction: String = ""
    var desire: String = ""
    var operatingRule: String = ""
    var cost: String = ""
    var signature: String = ""
    var formativePressure: String = ""
    var strangeness: Double?
    var visualDescription: String = ""
    /// Dimension raw values whose emitted content restates the user's explicit words
    /// (auto-pinned on apply; may cross an existing pin — the user outranks their past self).
    var userAuthoredFields: [String] = []
    var changeNote: String = ""
    /// media_id values of images that show THIS character (attached this turn, named by
    /// the user, or captioned as clearly depicting them). nil on responses that predate
    /// the field.
    var referenceMediaIds: [String]?

    /// Dimensions this patch actually addressed.
    var emittedDimensions: Set<GoalCastDimension> {
        var dims: Set<GoalCastDimension> = []
        if !essence.trimmed.isEmpty { dims.insert(.essence) }
        if !publicFunction.trimmed.isEmpty { dims.insert(.publicFunction) }
        if !desire.trimmed.isEmpty { dims.insert(.desire) }
        if !operatingRule.trimmed.isEmpty { dims.insert(.operatingRule) }
        if !cost.trimmed.isEmpty { dims.insert(.cost) }
        if !signature.trimmed.isEmpty { dims.insert(.signature) }
        if !formativePressure.trimmed.isEmpty { dims.insert(.formativePressure) }
        if strangeness != nil { dims.insert(.strangeness) }
        if !visualDescription.trimmed.isEmpty { dims.insert(.visualDescription) }
        return dims
    }

    var identityPatch: GoalCastIdentity {
        GoalCastIdentity(
            essence: essence,
            publicFunction: publicFunction,
            desire: desire,
            operatingRule: operatingRule,
            cost: cost,
            signature: signature,
            formativePressure: formativePressure,
            strangeness: strangeness ?? 0.5,
            visualDescription: visualDescription
        )
    }

    var userAuthoredDimensionSet: Set<GoalCastDimension> {
        Set(userAuthoredFields.compactMap { GoalCastDimension(rawValue: $0.trimmed) })
            .intersection(emittedDimensions)
    }

    /// A patch complete enough to stand as a brand-new member.
    var isCompleteForAdd: Bool {
        let core: [GoalCastDimension] = [
            .essence, .publicFunction, .desire, .operatingRule, .cost, .signature, .visualDescription
        ]
        return core.allSatisfy { !(identityPatch.value(for: $0)?.trimmed.isEmpty ?? true) }
    }

    enum CodingKeys: String, CodingKey {
        case targetName
        case action
        case essence
        case publicFunction
        case desire
        case operatingRule
        case cost
        case signature
        case formativePressure
        case strangeness
        case visualDescription
        case userAuthoredFields
        case changeNote
    }

    init(
        targetName: String = "",
        action: String = "",
        essence: String = "",
        publicFunction: String = "",
        desire: String = "",
        operatingRule: String = "",
        cost: String = "",
        signature: String = "",
        formativePressure: String = "",
        strangeness: Double? = nil,
        visualDescription: String = "",
        userAuthoredFields: [String] = [],
        changeNote: String = ""
    ) {
        self.targetName = targetName
        self.action = action
        self.essence = essence
        self.publicFunction = publicFunction
        self.desire = desire
        self.operatingRule = operatingRule
        self.cost = cost
        self.signature = signature
        self.formativePressure = formativePressure
        self.strangeness = strangeness
        self.visualDescription = visualDescription
        self.userAuthoredFields = userAuthoredFields
        self.changeNote = changeNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetName = try container.decodeIfPresent(String.self, forKey: .targetName) ?? ""
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
        essence = try container.decodeIfPresent(String.self, forKey: .essence) ?? ""
        publicFunction = try container.decodeIfPresent(String.self, forKey: .publicFunction) ?? ""
        desire = try container.decodeIfPresent(String.self, forKey: .desire) ?? ""
        operatingRule = try container.decodeIfPresent(String.self, forKey: .operatingRule) ?? ""
        cost = try container.decodeIfPresent(String.self, forKey: .cost) ?? ""
        signature = try container.decodeIfPresent(String.self, forKey: .signature) ?? ""
        formativePressure = try container.decodeIfPresent(String.self, forKey: .formativePressure) ?? ""
        strangeness = try container.decodeIfPresent(Double.self, forKey: .strangeness)
        visualDescription = try container.decodeIfPresent(String.self, forKey: .visualDescription) ?? ""
        userAuthoredFields = try container.decodeIfPresent([String].self, forKey: .userAuthoredFields) ?? []
        changeNote = try container.decodeIfPresent(String.self, forKey: .changeNote) ?? ""
    }
}

struct GoalCastChatSanitizationResult: Hashable, Sendable {
    var updates: [ProjectGoalCastUpdate] = []
    var warnings: [String] = []
}

/// Guards the chat delta channel the way sanitizeInterviewRequiredEntities guards
/// entities. `remove` is destructive, so it holds to a stricter corpus than entity adds:
/// the name must appear verbatim in the LATEST user message, not anywhere in history.
/// Which images a cast patch ties to its character: the model's listed ids when it
/// named any; for a brand-new character with none listed, the turn's own attachments
/// (the photos that introduced them). Updates never inherit turn images blindly — a
/// landscape attached to "make Auri taller" must not become Auri's face.
func castUpdateReferenceMediaIds(update: ProjectGoalCastUpdate, turnMediaIds: [String]) -> [String] {
    let listed = uniqueNonEmpty(update.referenceMediaIds ?? [])
    if !listed.isEmpty { return listed }
    if update.action.trimmed.lowercased() == "add" { return uniqueNonEmpty(turnMediaIds) }
    return []
}

func sanitizeGoalCastChatUpdates(
    _ updates: [ProjectGoalCastUpdate],
    currentCast: GoalCastDocument,
    latestUserMessage: String,
    knownImageMediaIds: Set<String>? = nil
) -> GoalCastChatSanitizationResult {
    let maximumUpdates = 6
    var output: [ProjectGoalCastUpdate] = []
    var warnings: [String] = []
    var seenNames: Set<String> = []

    for update in updates {
        guard output.count < maximumUpdates else {
            warnings.append("Dropped surplus cast updates past \(maximumUpdates).")
            break
        }
        var sanitized = update
        sanitized.targetName = update.targetName.trimmed
        sanitized.action = update.action.trimmed.lowercased()
        guard !sanitized.targetName.isEmpty else {
            warnings.append("Dropped a cast update with no target name.")
            continue
        }
        let nameKey = sanitized.targetName.lowercased()
        guard !seenNames.contains(nameKey) else { continue }
        let existingMember = currentCast.member(named: sanitized.targetName)

        switch sanitized.action {
        case "remove":
            guard containsVerbatimGoalEntityName(sanitized.targetName, in: latestUserMessage) else {
                warnings.append("Ignored cast remove for '\(sanitized.targetName)' — the name was not in the latest user message.")
                continue
            }
        case "update":
            if existingMember == nil {
                guard sanitized.isCompleteForAdd else {
                    warnings.append("Ignored cast update for unknown character '\(sanitized.targetName)'.")
                    continue
                }
                sanitized.action = "add"
            }
        case "add":
            if existingMember != nil {
                sanitized.action = "update"
            }
        default:
            warnings.append("Dropped cast update for '\(sanitized.targetName)' with unsupported action '\(sanitized.action)'.")
            continue
        }

        sanitized.userAuthoredFields = normalizedGoalCastPinKeys(
            sanitized.userAuthoredFields.filter { key in
                guard let dimension = GoalCastDimension(rawValue: key.trimmed) else { return false }
                return sanitized.emittedDimensions.contains(dimension)
            }
        )
        if let knownImageMediaIds {
            let listed = uniqueNonEmpty(sanitized.referenceMediaIds ?? [])
            let kept = listed.filter { knownImageMediaIds.contains($0) }
            if kept.count < listed.count {
                warnings.append("Dropped \(listed.count - kept.count) unknown reference media id(s) for '\(sanitized.targetName)'.")
            }
            sanitized.referenceMediaIds = Array(kept.prefix(8))
        }
        seenNames.insert(nameKey)
        output.append(sanitized)
    }

    return GoalCastChatSanitizationResult(updates: output, warnings: uniqueNonEmpty(warnings))
}

struct GoalCastChatApplication: Hashable, Sendable {
    var document: GoalCastDocument
    /// Members whose new take must roster-sync (adds + updates; never removes).
    var syncMemberIds: [String] = []
    var warnings: [String] = []
}

func goalCastChatOriginLabel(_ changeNote: String) -> String {
    let trimmed = changeNote.trimmed
    guard !trimmed.isEmpty else { return "chat" }
    let clipped = trimmed.count > 80 ? "\(trimmed.prefix(80))…" : trimmed
    return "chat: \(clipped)"
}

/// Pure apply of SANITIZED chat updates. Adds mint a member with one take; updates land
/// as a new take built by the field-wise merge (user-authored fields may cross pins and
/// then re-pin); removes drop the member and never touch the roster character.
func appliedGoalCastChatUpdates(
    document: GoalCastDocument,
    updates: [ProjectGoalCastUpdate],
    now: String
) -> GoalCastChatApplication {
    var output = document
    var syncMemberIds: [String] = []
    var warnings: [String] = []

    for update in updates {
        switch update.action {
        case "remove":
            guard let member = output.member(named: update.targetName) else {
                warnings.append("Ignored cast remove for '\(update.targetName)' — no such cast member.")
                continue
            }
            output.members.removeAll { $0.memberId == member.memberId }

        case "add":
            guard output.member(named: update.targetName) == nil else {
                warnings.append("Ignored duplicate cast add for '\(update.targetName)'.")
                continue
            }
            guard output.members.count < GoalCastDocument.maximumMembers else {
                warnings.append("Cast is full (\(GoalCastDocument.maximumMembers)) — dropped '\(update.targetName)'.")
                continue
            }
            var member = GoalCastMember(
                memberId: "castmember_\(shortHash("\(output.projectId):\(update.targetName):\(now)", length: 12))",
                name: update.targetName,
                pinnedDimensions: normalizedGoalCastPinKeys(Array(update.userAuthoredDimensionSet).map(\.rawValue)),
                updatedAt: now
            )
            member.appendTake(
                GoalCastTake.minted(origin: goalCastChatOriginLabel(update.changeNote), identity: update.identityPatch, now: now),
                now: now
            )
            // Newest first: a character the story just introduced leads the
            // STORY cast list instead of landing below the established ones.
            output.members.insert(member, at: 0)
            syncMemberIds.append(member.memberId)

        case "update":
            guard var member = output.member(named: update.targetName),
                  let index = output.members.firstIndex(where: { $0.memberId == member.memberId }) else {
                warnings.append("Ignored cast update for unknown character '\(update.targetName)'.")
                continue
            }
            let merged = mergedGoalCastIdentity(
                prior: member.activeIdentity,
                emitted: update.identityPatch,
                allowed: update.emittedDimensions,
                pinned: member.pinnedDimensionSet,
                pinOverride: update.userAuthoredDimensionSet
            )
            member.appendTake(
                GoalCastTake.minted(origin: goalCastChatOriginLabel(update.changeNote), identity: merged, now: now),
                now: now
            )
            member.pinnedDimensions = normalizedGoalCastPinKeys(
                member.pinnedDimensions + update.userAuthoredDimensionSet.map(\.rawValue)
            )
            output.members[index] = member
            syncMemberIds.append(member.memberId)

        default:
            continue
        }
    }

    output.updatedAt = now
    return GoalCastChatApplication(
        document: output.normalized(),
        syncMemberIds: syncMemberIds,
        warnings: uniqueNonEmpty(warnings)
    )
}

// MARK: - LLM call contexts

/// Context for the initial/ensemble articulation call (and "+ Add" with desiredCount 1).
struct GoalCastArticulationContext: Sendable {
    var projectId: String
    var goalSummary: String
    /// "- <name> (<role>) [required]" lines — goalBriefV2StyleSummary omits entities.
    var requiredEntityLines: [String]
    /// Existing roster "- Name — descriptionPrompt" lines for name/appearance continuity.
    var rosterCharacterLines: [String]
    /// Current cast member context lines (ensemble coherence).
    var existingMemberSummaries: [String]
    /// Names the response must never re-emit.
    var excludeNames: [String]
    /// nil = model decides within `castCap`; 1 for "+ Add character".
    var desiredCount: Int?
    /// Story Input photos that show people, one prompt line each (media_id first).
    /// Empty = invent within the Goal's world.
    var peoplePhotoLines: [String]
    /// The automatic casting ceiling, members in total.
    var castCap: Int

    init(
        projectId: String,
        goalSummary: String,
        requiredEntityLines: [String] = [],
        rosterCharacterLines: [String] = [],
        existingMemberSummaries: [String] = [],
        excludeNames: [String] = [],
        desiredCount: Int? = nil,
        peoplePhotoLines: [String] = [],
        castCap: Int = GoalCastDocument.automaticCastCap
    ) {
        self.projectId = projectId
        self.goalSummary = goalSummary
        self.requiredEntityLines = requiredEntityLines
        self.rosterCharacterLines = rosterCharacterLines
        self.existingMemberSummaries = existingMemberSummaries
        self.excludeNames = excludeNames
        self.desiredCount = desiredCount
        self.peoplePhotoLines = peoplePhotoLines
        self.castCap = castCap
    }
}

/// THE MEDIA-FIRST CASTING LAW's evidence: Story Input photos with people, one
/// prompt line each, in the order given (newest first upstream), capped.
func goalCastPeoplePhotoLines(
    _ entries: [(mediaId: String, observation: ImageObservationResult)],
    limit: Int = 8
) -> [String] {
    entries
        .filter { $0.observation.peopleVisible && !$0.mediaId.trimmed.isEmpty }
        .prefix(limit)
        .map { entry in
            let observation = entry.observation
            let count = observation.peopleCountEstimate.map { String($0) } ?? "some"
            let roles = observation.peopleRolesVisible.map(\.trimmed).filter { !$0.isEmpty }.prefix(4).joined(separator: ", ")
            let caption = String(observation.plainCaption.trimmed.prefix(160))
            let literal = String(observation.literalDescription.trimmed.prefix(200))
            var line = "- media_id=\(entry.mediaId) people=\(count)"
            if !roles.isEmpty { line += " (\(roles))" }
            if !caption.isEmpty { line += " caption=\(caption)" }
            if !literal.isEmpty { line += " literal=\(literal)" }
            return line
        }
}

/// Known image ids only, deduped, capped — the chat sanitizer's law applied to
/// articulated members.
func sanitizedGoalCastReferenceMediaIds(
    _ ids: [String],
    knownImageMediaIds: Set<String>,
    limit: Int = 8
) -> [String] {
    Array(uniqueNonEmpty(ids).filter { knownImageMediaIds.contains($0) }.prefix(limit))
}

/// THE ONE-PHOTO-ONE-CHARACTER LAW: a source photo anchors at most one character.
/// Photos already held by roster characters drop out; a photo two new members both
/// claim goes to the member with fewer photos of its own (ties → the earlier
/// member). Order within each member is preserved.
func allocatedGoalCastReferenceMediaIds(_ refsByMember: [[String]], alreadyClaimed: Set<String>) -> [[String]] {
    var cleaned = refsByMember.map { uniqueNonEmpty($0).filter { !alreadyClaimed.contains($0) } }
    var claimants: [String: [Int]] = [:]
    for (index, refs) in cleaned.enumerated() {
        for id in refs { claimants[id, default: []].append(index) }
    }
    for id in claimants.keys.sorted() {
        guard let members = claimants[id], members.count > 1 else { continue }
        let winner = members.min { lhs, rhs in
            if cleaned[lhs].count == cleaned[rhs].count { return lhs < rhs }
            return cleaned[lhs].count < cleaned[rhs].count
        }
        for member in members where member != winner {
            cleaned[member].removeAll { $0 == id }
        }
    }
    return cleaned
}

extension GoalCastDocument {
    /// Automatic casting (first articulation, re-cast) stops at this many members
    /// in total; the explicit "+ Add" still runs one at a time up to `maximumMembers`.
    static let automaticCastCap = 2

    /// Delete-character symmetry: the member linked by characterId, else by
    /// case-insensitive name, leaves the cast — otherwise the next roster sync
    /// re-creates the character. `removed` is nil when nothing was linked.
    func removingMember(linkedTo characterId: String, name: String) -> (document: GoalCastDocument, removed: GoalCastMember?) {
        let byId = members.first { !$0.characterId.isEmpty && $0.characterId == characterId }
        guard let target = byId ?? member(named: name) else { return (self, nil) }
        var value = self
        value.members.removeAll { $0.memberId == target.memberId }
        return (value, target)
    }
}

/// Context for a single-member steer call.
struct GoalCastSteerContext: Sendable {
    var projectId: String
    var goalSummary: String
    var memberName: String
    /// The active take's identity as pretty JSON.
    var currentIdentityJSON: String
    /// Earlier take essences ("do not repeat these").
    var priorTakeEssences: [String]
    /// GoalCastSteerGesture.promptKeyword.
    var gesture: String
    /// Populated for feedback gestures only.
    var feedbackText: String
    /// Keep-exactly dimension raw values (also enforced post-hoc by the merge).
    var pinnedDimensions: [String]
    /// Current roster descriptionPrompt for visual continuity.
    var rosterAppearanceLine: String

    init(
        projectId: String,
        goalSummary: String,
        memberName: String,
        currentIdentityJSON: String,
        priorTakeEssences: [String] = [],
        gesture: String,
        feedbackText: String = "",
        pinnedDimensions: [String] = [],
        rosterAppearanceLine: String = ""
    ) {
        self.projectId = projectId
        self.goalSummary = goalSummary
        self.memberName = memberName
        self.currentIdentityJSON = currentIdentityJSON
        self.priorTakeEssences = priorTakeEssences
        self.gesture = gesture
        self.feedbackText = feedbackText
        self.pinnedDimensions = pinnedDimensions
        self.rosterAppearanceLine = rosterAppearanceLine
    }
}

// MARK: - LLM response

/// One member as the articulation/steer schema emits it (flat identity fields).
struct GoalCastArticulatedMember: Codable, Hashable, Sendable {
    var name: String = ""
    var essence: String = ""
    var publicFunction: String = ""
    var desire: String = ""
    var operatingRule: String = ""
    var cost: String = ""
    var signature: String = ""
    var formativePressure: String = ""
    var strangeness: Double = 0.5
    var visualDescription: String = ""
    /// Dimension keys the model says it meaningfully changed; consumed only by feedback
    /// steers (as the merge's allowed set) — fixed gesture sets ignore it.
    var changedFields: [String] = []
    /// MEDIA FIRST: the Story Input photos showing this person (media_id values).
    var referenceMediaIds: [String] = []

    var identity: GoalCastIdentity {
        GoalCastIdentity(
            essence: essence,
            publicFunction: publicFunction,
            desire: desire,
            operatingRule: operatingRule,
            cost: cost,
            signature: signature,
            formativePressure: formativePressure,
            strangeness: strangeness,
            visualDescription: visualDescription
        ).normalized()
    }

    var changedDimensions: Set<GoalCastDimension> {
        Set(changedFields.compactMap { GoalCastDimension(rawValue: $0.trimmed) })
    }

    enum CodingKeys: String, CodingKey {
        case name
        case essence
        case publicFunction
        case desire
        case operatingRule
        case cost
        case signature
        case formativePressure
        case strangeness
        case visualDescription
        case changedFields
        case referenceMediaIds
    }

    init(
        name: String = "",
        essence: String = "",
        publicFunction: String = "",
        desire: String = "",
        operatingRule: String = "",
        cost: String = "",
        signature: String = "",
        formativePressure: String = "",
        strangeness: Double = 0.5,
        visualDescription: String = "",
        changedFields: [String] = [],
        referenceMediaIds: [String] = []
    ) {
        self.name = name
        self.essence = essence
        self.publicFunction = publicFunction
        self.desire = desire
        self.operatingRule = operatingRule
        self.cost = cost
        self.signature = signature
        self.formativePressure = formativePressure
        self.strangeness = strangeness
        self.visualDescription = visualDescription
        self.changedFields = changedFields
        self.referenceMediaIds = referenceMediaIds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        essence = try container.decodeIfPresent(String.self, forKey: .essence) ?? ""
        publicFunction = try container.decodeIfPresent(String.self, forKey: .publicFunction) ?? ""
        desire = try container.decodeIfPresent(String.self, forKey: .desire) ?? ""
        operatingRule = try container.decodeIfPresent(String.self, forKey: .operatingRule) ?? ""
        cost = try container.decodeIfPresent(String.self, forKey: .cost) ?? ""
        signature = try container.decodeIfPresent(String.self, forKey: .signature) ?? ""
        formativePressure = try container.decodeIfPresent(String.self, forKey: .formativePressure) ?? ""
        strangeness = try container.decodeIfPresent(Double.self, forKey: .strangeness) ?? 0.5
        visualDescription = try container.decodeIfPresent(String.self, forKey: .visualDescription) ?? ""
        changedFields = try container.decodeIfPresent([String].self, forKey: .changedFields) ?? []
        referenceMediaIds = try container.decodeIfPresent([String].self, forKey: .referenceMediaIds) ?? []
    }
}

struct GoalCastArticulationResponse: Codable, Hashable, Sendable {
    var schemaVersion: String = "litscenes.goal_cast_articulation.v0.2"
    var members: [GoalCastArticulatedMember] = []
    var castingNote: String = ""

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case members
        case castingNote
    }

    init(
        schemaVersion: String = "litscenes.goal_cast_articulation.v0.2",
        members: [GoalCastArticulatedMember] = [],
        castingNote: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.members = members
        self.castingNote = castingNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "litscenes.goal_cast_articulation.v0.2"
        members = try container.decodeIfPresent([GoalCastArticulatedMember].self, forKey: .members) ?? []
        castingNote = try container.decodeIfPresent(String.self, forKey: .castingNote) ?? ""
    }
}

// MARK: - Identity draft (one-click casting)

/// The parts of a character's identity the draft may fill.
enum CharacterIdentityBlank: String, CaseIterable, Hashable, Sendable {
    case appearance
    case storyIdentity
    case props
    case sourceLabels
}

enum CharacterIdentityDraftDecision: Equatable, Sendable {
    case draft(blanks: Set<CharacterIdentityBlank>)
    case skip
}

/// THE DRAFT GATE: a render drafts first only when the appearance or the story
/// identity is blank; props and source labels ride along when blank; a failed draft
/// is not retried implicitly; a filled character never drafts by itself.
enum CharacterIdentityDraft {
    static func decision(
        hasAppearance: Bool,
        hasCastIdentity: Bool,
        hasSignatureProps: Bool,
        sourceCount: Int,
        unlabeledSourceCount: Int,
        lastDraftFailed: Bool
    ) -> CharacterIdentityDraftDecision {
        guard !lastDraftFailed else { return .skip }
        var blanks: Set<CharacterIdentityBlank> = []
        if !hasAppearance { blanks.insert(.appearance) }
        if !hasCastIdentity { blanks.insert(.storyIdentity) }
        guard !blanks.isEmpty else { return .skip }
        if !hasSignatureProps { blanks.insert(.props) }
        if sourceCount > 0, unlabeledSourceCount > 0 { blanks.insert(.sourceLabels) }
        return .draft(blanks: blanks)
    }

    /// The cast dimensions a set of blanks may write.
    static func allowedDimensions(for blanks: Set<CharacterIdentityBlank>) -> Set<GoalCastDimension> {
        var dimensions: Set<GoalCastDimension> = []
        if blanks.contains(.appearance) { dimensions.insert(.visualDescription) }
        if blanks.contains(.storyIdentity) {
            dimensions.formUnion([.essence, .publicFunction, .desire, .operatingRule, .cost, .signature, .formativePressure, .strangeness])
        }
        return dimensions
    }

    /// Fill blanks only, through THE merge, so pins and written text survive.
    static func mergedIdentity(
        prior: GoalCastIdentity,
        emitted: GoalCastIdentity,
        blanks: Set<CharacterIdentityBlank>,
        pinned: Set<GoalCastDimension>
    ) -> GoalCastIdentity {
        mergedGoalCastIdentity(prior: prior, emitted: emitted, allowed: allowedDimensions(for: blanks), pinned: pinned)
    }

    /// Prompt words for a blank.
    static func promptLabel(for blank: CharacterIdentityBlank) -> String {
        switch blank {
        case .appearance: return "appearance (identity.visual_description)"
        case .storyIdentity: return "story identity (identity.essence, public_function, desire, operating_rule, cost, signature, formative_pressure, strangeness)"
        case .props: return "signature_props"
        case .sourceLabels: return "source_image_notes"
        }
    }
}

struct CharacterIdentityDraftSourceNote: Codable, Hashable, Sendable {
    var mediaId: String = ""
    var label: String = ""

    enum CodingKeys: String, CodingKey {
        case mediaId
        case label
    }

    init(mediaId: String = "", label: String = "") {
        self.mediaId = mediaId
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaId = try container.decodeIfPresent(String.self, forKey: .mediaId) ?? ""
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

/// The strict JSON an identity draft returns.
struct CharacterIdentityDraftResponse: Codable, Hashable, Sendable {
    var schemaVersion: String = "litscenes.character_identity_draft.v0.1"
    var identity: GoalCastIdentity = GoalCastIdentity()
    var signatureProps: [String] = []
    var environmentAffinity: String = ""
    var sourceImageNotes: [CharacterIdentityDraftSourceNote] = []
    var castingNote: String = ""

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case identity
        case signatureProps
        case environmentAffinity
        case sourceImageNotes
        case castingNote
    }

    init(
        schemaVersion: String = "litscenes.character_identity_draft.v0.1",
        identity: GoalCastIdentity = GoalCastIdentity(),
        signatureProps: [String] = [],
        environmentAffinity: String = "",
        sourceImageNotes: [CharacterIdentityDraftSourceNote] = [],
        castingNote: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.identity = identity
        self.signatureProps = signatureProps
        self.environmentAffinity = environmentAffinity
        self.sourceImageNotes = sourceImageNotes
        self.castingNote = castingNote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "litscenes.character_identity_draft.v0.1"
        identity = (try container.decodeIfPresent(GoalCastIdentity.self, forKey: .identity) ?? GoalCastIdentity()).normalized()
        signatureProps = try container.decodeIfPresent([String].self, forKey: .signatureProps) ?? []
        environmentAffinity = try container.decodeIfPresent(String.self, forKey: .environmentAffinity) ?? ""
        sourceImageNotes = try container.decodeIfPresent([CharacterIdentityDraftSourceNote].self, forKey: .sourceImageNotes) ?? []
        castingNote = try container.decodeIfPresent(String.self, forKey: .castingNote) ?? ""
    }

    static func decode(from data: Data) throws -> CharacterIdentityDraftResponse {
        try JSONCoding.decoder.decode(CharacterIdentityDraftResponse.self, from: data)
    }
}

/// Everything the draft prompt sees.
struct CharacterIdentityDraftContext: Sendable {
    var projectId: String
    var projectName: String
    var characterName: String
    var blanks: Set<CharacterIdentityBlank>
    /// Filled parts, verbatim, that must come back empty.
    var keepLines: [String]
    var goalSummary: String
    var requiredEntityLines: [String]
    var castLines: [String]
    var otherCharacterLines: [String]
    var moodboardLines: String
    var sourceImageLines: String
    var sourceCount: Int
}
