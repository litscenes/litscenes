import Foundation

/// A prompt template for generated character reference sheets, editable per project in
/// Settings. Kept apart from ReframePromptTemplate: that type's normalization coerces
/// modes through the reframe vocabulary and falls back to reframe bodies.
struct CharacterSheetPromptTemplate: Codable, Hashable, Identifiable, Sendable {
    static let workflowName = "character_sheet"
    static let sheetMode = "sheet"

    var templateId: String = ""
    var workflow: String = CharacterSheetPromptTemplate.workflowName
    var mode: String = CharacterSheetPromptTemplate.sheetMode
    /// Empty means the fallback used when no exact model template exists.
    var model: String = ""
    var title: String = ""
    var body: String = ""
    var updatedAt: String = ""

    var id: String { templateId }
    var isFallback: Bool { model.trimmed.isEmpty }

    func normalized(order: Int = 0) -> CharacterSheetPromptTemplate {
        var value = self
        value.workflow = Self.workflowName
        value.mode = Self.sheetMode
        value.model = value.model.trimmed
        value.title = value.title.trimmed
        value.body = value.body.trimmed
        value.updatedAt = value.updatedAt.trimmed
        if value.templateId.trimmed.isEmpty {
            value.templateId = "\(value.workflow):\(value.mode):\(value.model.isEmpty ? "fallback" : value.model)"
        }
        if value.title.isEmpty {
            value.title = value.model.isEmpty ? "Character sheet fallback" : "Character sheet · \(value.model)"
        }
        if value.body.isEmpty {
            value.body = ProjectPromptSettingsDocument.builtInCharacterSheetBody
        }
        return value
    }
}

/// Renders a character sheet template into the prompt a render transmits verbatim.
enum CharacterSheetPrompt {
    static let placeholders = [
        "{{character_name}}",
        "{{visual_description}}",
        "{{signature_props}}",
        "{{story_identity}}",
        "{{sheet_directives}}",
        "{{reference_note}}",
    ]

    /// The story half of a character, from the goal cast's active identity.
    struct StoryIdentityLines: Hashable, Sendable {
        var essence: String = ""
        var publicFunction: String = ""
        var desire: String = ""
        var signature: String = ""

        var isEmpty: Bool {
            [essence, publicFunction, desire, signature].allSatisfy { $0.trimmed.isEmpty }
        }
    }

    struct Fill: Hashable, Sendable {
        var name: String
        var visualDescription: String = ""
        var signatureProps: [String] = []
        var storyIdentity: StoryIdentityLines? = nil
        var sheetDirectives: [String] = []
        var attachesReferences: Bool = false
    }

    /// Substitutes every placeholder; empty values collapse their line so the
    /// transmitted prompt never carries a dangling label or a blank paragraph run.
    static func render(template: String, fill: Fill) -> String {
        let name = fill.name.trimmed.isEmpty ? "the character" : fill.name.trimmed
        let description = fill.visualDescription.trimmed
        let props = uniqueNonEmpty(fill.signatureProps)
        let directives = uniqueNonEmpty(fill.sheetDirectives)

        var identityParts: [String] = []
        if let identity = fill.storyIdentity, !identity.isEmpty {
            if !identity.essence.trimmed.isEmpty { identityParts.append("who they are: \(identity.essence.trimmed)") }
            if !identity.publicFunction.trimmed.isEmpty { identityParts.append("role: \(identity.publicFunction.trimmed)") }
            if !identity.desire.trimmed.isEmpty { identityParts.append("wants: \(identity.desire.trimmed)") }
            if !identity.signature.trimmed.isEmpty { identityParts.append("tell: \(identity.signature.trimmed)") }
        }

        var rendered = template
        rendered = rendered.replacingOccurrences(of: "{{character_name}}", with: name)
        rendered = rendered.replacingOccurrences(
            of: "{{visual_description}}",
            with: description.isEmpty ? "" : "Appearance: \(description)"
        )
        rendered = rendered.replacingOccurrences(
            of: "{{signature_props}}",
            with: props.isEmpty ? "" : "Always with them: \(props.joined(separator: "; "))."
        )
        rendered = rendered.replacingOccurrences(
            of: "{{story_identity}}",
            with: identityParts.isEmpty ? "" : "Story identity — \(identityParts.joined(separator: "; "))."
        )
        rendered = rendered.replacingOccurrences(
            of: "{{sheet_directives}}",
            with: directives.isEmpty
                ? ""
                : "Refinements from the character conversation — apply every one:\n" + directives.map { "- \($0)" }.joined(separator: "\n")
        )
        rendered = rendered.replacingOccurrences(
            of: "{{reference_note}}",
            with: fill.attachesReferences ? " — match the attached reference images exactly" : ""
        )
        return collapsingBlankRuns(rendered)
    }

    /// Stable fingerprint of a rendered prompt; the stage compares it against the
    /// prompt the active sheet rendered from.
    static func promptHash(_ rendered: String) -> String {
        shortHash(rendered.trimmed, length: 16)
    }

    /// A blank hand-edit is no edit.
    static func cleanOverride(_ text: String?) -> String? {
        text?.trimmed.nilIfEmpty
    }

    /// Portrait output for FAL stacks, expressed only through parameters the stack
    /// accepts for this style mode: the FAL client refuses unknown keys, so an
    /// unaccepted key would fail the whole render. Empty for every other provider.
    static func falParameterOverrides(stack: RenderStack, styleMode: LensRenderStyleMode) -> String {
        guard stack.isFAL else { return "" }
        let allowed = Set(stack.falDebugParameterKeys(styleMode: styleMode))
        var parameters: [String: String] = [:]
        if allowed.contains("aspect_ratio") { parameters["aspect_ratio"] = "3:4" }
        if allowed.contains("resolution") { parameters["resolution"] = "2K" }
        if allowed.contains("image_size") { parameters["image_size"] = "portrait_4_3" }
        guard !parameters.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys]) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func collapsingBlankRuns(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var output: [String] = []
        for line in lines {
            if line.isEmpty, output.last?.isEmpty ?? true { continue }
            output.append(line)
        }
        while output.last?.isEmpty == true { output.removeLast() }
        return output.joined(separator: "\n")
    }
}

extension ProjectPromptSettingsDocument {
    static func characterSheetTemplateKey(model: String) -> String {
        "\(CharacterSheetPromptTemplate.sheetMode)|\(model.trimmed)"
    }

    static func builtInCharacterSheetTemplates() -> [CharacterSheetPromptTemplate] {
        [
            CharacterSheetPromptTemplate(
                templateId: "character_sheet:sheet:fallback",
                model: "",
                title: "Character sheet fallback",
                body: builtInCharacterSheetBody
            ),
        ]
    }

    static func builtInCharacterSheetTemplate(model rawModel: String) -> CharacterSheetPromptTemplate {
        let model = rawModel.trimmed
        let builtIns = builtInCharacterSheetTemplates()
        return builtIns.first { $0.model == model }
            ?? builtIns.first { $0.model.isEmpty }
            ?? CharacterSheetPromptTemplate(body: builtInCharacterSheetBody).normalized()
    }

    /// Exact model template, else the fallback, else the built-in.
    func characterSheetTemplate(model rawModel: String) -> CharacterSheetPromptTemplate {
        let model = rawModel.trimmed
        let templates = Self.normalizedCharacterSheetPrompts(characterSheetPrompts)
        if !model.isEmpty, let exact = templates.first(where: { $0.model == model }) {
            return exact
        }
        if let fallback = templates.first(where: { $0.model.isEmpty }) {
            return fallback
        }
        return Self.builtInCharacterSheetTemplate(model: model)
    }

    /// Superseded built-in sheet bodies, keyed like the live templates, so a project
    /// that saved the prompt sheet still receives repaired defaults.
    static let retiredCharacterSheetBodies: [String: Set<String>] = [:]

    /// Built-ins first, stored templates layered on top unless a stored body is a
    /// retired built-in (a stale saved default, not an operator edit).
    static func normalizedCharacterSheetPrompts(_ stored: [CharacterSheetPromptTemplate]) -> [CharacterSheetPromptTemplate] {
        var byKey: [String: CharacterSheetPromptTemplate] = [:]
        for template in builtInCharacterSheetTemplates() {
            let normalized = template.normalized()
            byKey[characterSheetTemplateKey(model: normalized.model)] = normalized
        }
        for (index, template) in stored.enumerated() {
            let normalized = template.normalized(order: index)
            let key = characterSheetTemplateKey(model: normalized.model)
            if let retired = retiredCharacterSheetBodies[key], retired.contains(normalized.body) {
                continue
            }
            byKey[key] = normalized
        }
        return byKey.values.sorted { lhs, rhs in
            if lhs.model.isEmpty != rhs.model.isEmpty { return lhs.model.isEmpty }
            return lhs.model < rhs.model
        }
    }

    /// The default sheet body: an eight-section production continuity sheet. Output
    /// size is provider-parameterized, so the body names no aspect ratio.
    static let builtInCharacterSheetBody = """
    Create a professional AI Video Production — Character Reference Sheet for {{character_name}}{{reference_note}}. Create a polished portrait continuity sheet focused exclusively on the character.

    {{visual_description}}
    {{signature_props}}
    {{story_identity}}

    1. CHARACTER PROFILE — name, role, approximate age, height, body type, personality, distinctive traits, and signature colors.
    2. FULL-BODY TURNAROUND — front, 3/4, side, and back views of the exact same character at matching scale, with identical facial features, hairstyle, body proportions, costume, colors, and accessories.
    3. FACE AND IDENTITY DETAILS — front, profile, and 3/4 head-and-shoulder close-ups showing facial structure, eyes, eyebrows, nose, lips, hairstyle, skin tone, makeup, scars, tattoos, and other defining features.
    4. EXPRESSION SHEET — neutral, happy, angry, sad, surprised, worried, confident, and determined expressions. Preserve the exact same facial structure and identity in every expression.
    5. POSE AND BODY LANGUAGE — neutral standing, walking, sitting, relaxed, tense, and action-ready poses. Maintain consistent anatomy, proportions, posture, and silhouette.
    6. COSTUME DETAILS — close-ups of clothing layers, fabrics, seams, fasteners, footwear, jewelry, eyewear, markings, logos, and other character-defining wardrobe elements.
    7. COLOR AND MATERIAL PALETTE — include 4-6 key colors with HEX codes, plus references for skin, hair, fabric, leather, metal, plastic, armor, or other visible materials.
    8. DO NOT CHANGE — lock the character's face, identity, skin tone, age, hair, eye color, body shape, proportions, costume, accessories, markings, colors, and defining features. Do not redesign, beautify, age, stylize, simplify, or create alternate versions.

    {{sheet_directives}}

    Use a clean white or neutral studio background, soft controlled lighting, realistic materials, sharp details, subtle shadows, clean typography, thin dividers, balanced spacing, and a sophisticated editorial production-design grid.
    Every panel must depict the exact same character with absolute visual consistency. Focus only on the character. Do not include props, additional characters, environments, unrelated objects, or alternate outfits.
    """
}

/// What the stage, the render lane, and the conversation agree on about a
/// character's sheet prompt: the composed text, the operator's hand-edited text when
/// one exists, whether the composition moved on underneath that edit, and whether the
/// active sheet still matches what would render now.
struct CharacterSheetPromptState: Hashable, Sendable {
    var composed: String
    /// The hand-edited prompt; nil renders the composed one.
    var handEdited: String?
    /// The composed prompt changed after the hand edit was taken.
    var hasDrift: Bool
    /// The active sheet rendered from the effective prompt (vacuously true without a sheet).
    var isCurrent: Bool

    var effective: String { handEdited ?? composed }
    var isHandEdited: Bool { handEdited != nil }
    var effectiveHash: String { CharacterSheetPrompt.promptHash(effective) }

    static func resolve(
        composed: String,
        override handEdited: String?,
        overrideBaseHash: String,
        activeSheetMediaId: String?,
        activeSheetPromptHash: String
    ) -> CharacterSheetPromptState {
        let edited = CharacterSheetPrompt.cleanOverride(handEdited)
        let baseHash = overrideBaseHash.trimmed
        let hasDrift = edited != nil && !baseHash.isEmpty && baseHash != CharacterSheetPrompt.promptHash(composed)
        let effective = edited ?? composed
        let isCurrent = activeSheetMediaId?.trimmed.nilIfEmpty == nil
            || CharacterSheetPrompt.promptHash(effective) == activeSheetPromptHash.trimmed
        return CharacterSheetPromptState(composed: composed, handEdited: edited, hasDrift: hasDrift, isCurrent: isCurrent)
    }
}
