import Foundation
import Yams

// MARK: - Heterogeneous scalar (preserves Int / Double / Bool / String exactly)

/// The FAL and CivitAI request bodies depend on exact scalar types (a quoted
/// "2" vs the number 2 changes the wire body and the persisted recipe
/// valueType), so YAML values are held in this typed tree, never as loose Any.
enum JSONScalar: Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONScalar])
    case object([String: JSONScalar])

    init?(any value: Any) {
        switch value {
        case let scalar as JSONScalar:
            self = scalar
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            var items: [JSONScalar] = []
            for item in array {
                guard let scalar = JSONScalar(any: item) else { return nil }
                items.append(scalar)
            }
            self = .array(items)
        case let object as [String: Any]:
            var mapped: [String: JSONScalar] = [:]
            for (key, item) in object {
                guard let scalar = JSONScalar(any: item) else { return nil }
                mapped[key] = scalar
            }
            self = .object(mapped)
        default:
            return nil
        }
    }

    var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .array(let value): return value.map(\.anyValue)
        case .object(let value): return value.mapValues(\.anyValue)
        }
    }
}

// MARK: - RenderStack

enum RenderStackKind: String, Hashable, Sendable {
    case openai
    case fal
    case civitai
    case stability
}

/// Product workflows a render stack can execute. This is deliberately more
/// specific than "accepts an image": an edit endpoint is not automatically an
/// honest outpaint endpoint.
enum RenderStackWorkflow: String, Hashable, Sendable {
    case frameCreator = "frame_creator"
    case reframeZoomIn = "reframe_zoom_in"
    case reframeZoomOut = "reframe_zoom_out"
    case reframeViewpoint = "reframe_viewpoint"
}

/// What the Frame Creator can deliver to a stack as prompt-image references —
/// the app-level truth with engine compositing included. The reframe gate is
/// the outer door (a non-reframe stack renders from text alone); behind it,
/// `nativePromptImageLimit` counts the provider's slots, and Stability's single
/// slot is served by the engine's labeled composite sheet.
enum FrameReferenceCapacity: Hashable, Sendable {
    /// Text-only: no prompt-image attachments ride. (Named `textOnly`, not
    /// `none`, so comparisons against optional capacities can't silently mean
    /// `Optional.none`.)
    case textOnly
    /// N native slots; the first N planned references ride individually.
    /// `.slots(1)` is the historical single-slot behavior — the count is a
    /// per-model fact (declared as `prompt_image_limit`), not a provider one.
    case slots(Int)
    /// One native slot fed by a labeled composite sheet of up to
    /// `attachmentBudget` references (see `RenderReferenceComposite.maxCells`).
    case compositeSheet
    /// Up to `attachmentBudget` individual attachments.
    case budget

    /// The Frame Creator's shared attachment budget across every stratum
    /// (clip seed, direct references, @mention images).
    static let attachmentBudget = 6

    /// How many planned references can ride this stack.
    var planningCap: Int {
        switch self {
        case .textOnly: 0
        case .slots(let count): min(max(count, 0), Self.attachmentBudget)
        case .compositeSheet, .budget: Self.attachmentBudget
        }
    }
}

/// How a CivitAI stack seeds: a fixed integer, or the app-random seed the
/// engine supplies per render.
enum RenderStackSeed: Hashable, Sendable {
    case random
    case fixed(Int)

    func resolve(_ requestSeed: Int?) -> Int {
        switch self {
        case .fixed(let value): return value
        case .random: return requestSeed ?? Int.random(in: 1...Int(Int32.max))
        }
    }
}

/// Well-known stack ids used by seed/fallback/recovery logic. User-defined
/// stacks are equal citizens — these are only the shipped defaults.
enum RenderStackID {
    static let openAIBase = "openai_base"
    static let stabilityUltra = "stability_ultra"
    static let wan = "civitai_wan_2_7"
    static let realisticPortrait = "civitai_realistic_portrait"
    static let falFluxSchnell = "fal_flux_schnell"
    static let falFlux2Pro = "fal_flux_2_pro"
    static let falNanoBanana2 = "fal_nano_banana_2"
    static let falReve21 = "fal_reve_2_1"
    static let falMAIImage25 = "fal_mai_image_2_5"
    static let falSeedreamV5Pro = "fal_seedream_v5_pro"
    static let falOutpaint = "fal_image_apps_v2_outpaint"
}

/// One Frame Creator render stack, defined in render_stacks.yaml (bundled
/// defaults + optional user overlay). Replaces the retired LensTakeRenderStack
/// enum: every per-stack constant is data; `kind` selects the executor.
struct RenderStack: Hashable, Sendable, Identifiable {
    let id: String
    let stackId: String
    let label: String
    let detail: String
    /// Informational provider pricing captured with render provenance. The
    /// provider remains authoritative because marketplace pricing can change.
    let priceNote: String
    let kind: RenderStackKind
    let credentialProvider: LitScenesProviderCredential
    let order: Int
    let model: String
    let styleModel: String
    let canAttachStyleImage: Bool
    let workflows: Set<RenderStackWorkflow>
    /// Declared `prompt_image_limit` row override — how many prompt images
    /// this MODEL accepts natively. nil falls back to the provider-kind
    /// default in `nativePromptImageLimit`, so absent means today's behavior.
    let promptImageLimitOverride: Int?
    let promptLimit: Int?
    let outputFormat: String
    /// OpenAI image size string (e.g. "1536x1024"); nil for non-openai kinds.
    let imageSize: String?
    let promptInstructions: String
    // fal
    let falInput: [String: JSONScalar]
    let debugKeys: [String]
    // stability
    let stabilityInput: [String: JSONScalar]
    // civitai
    let civitaiInput: [String: JSONScalar]
    let civitaiTags: [String]
    let civitaiStepPriority: String?
    let civitaiSeed: RenderStackSeed
    let civitaiRecipe: [LensRenderRecipeParameter]

    var isOpenAI: Bool { kind == .openai }
    var isFAL: Bool { kind == .fal }
    var isCivitai: Bool { kind == .civitai }
    var isStability: Bool { kind == .stability }
    var frameCreatorCapable: Bool { workflows.contains(.frameCreator) }
    var reframeCapable: Bool {
        workflows.contains(.reframeZoomIn)
            || workflows.contains(.reframeZoomOut)
            || workflows.contains(.reframeViewpoint)
    }
    func supportsReframe(mode rawMode: String) -> Bool {
        switch LensReframeSpec.normalizedMode(rawMode) {
        case LensReframeSpec.zoomOutMode:
            workflows.contains(.reframeZoomOut)
        case LensReframeSpec.viewpointMode:
            workflows.contains(.reframeViewpoint)
        default:
            workflows.contains(.reframeZoomIn)
        }
    }
    /// Maximum native prompt-image fields this stack accepts — the declared
    /// per-model `prompt_image_limit` when present, else the provider-kind
    /// default. nil means the app does not impose a provider ceiling. This is
    /// the ONLY place the count is known.
    var nativePromptImageLimit: Int? {
        if let promptImageLimitOverride { return max(promptImageLimitOverride, 0) }
        switch kind {
        case .openai: return nil
        case .fal, .stability: return 1
        case .civitai: return 0
        }
    }
    /// The reframe gate composed with the slot count above; Stability's
    /// one slot carries a composite sheet, so it plans like a budget stack.
    var frameReferenceCapacity: FrameReferenceCapacity {
        guard reframeCapable else { return .textOnly }
        switch nativePromptImageLimit {
        case .some(0): return .textOnly
        case .some(let count): return isStability && count == 1 ? .compositeSheet : .slots(count)
        case .none: return .budget
        }
    }
    var usesPNGOutput: Bool { outputFormat == "png" }
    /// Replaces `stack == .openAIBase || stack.canAttachStyleImage`: OpenAI
    /// takes style references natively; others must declare the capability.
    var styleImageAttachSupported: Bool { canAttachStyleImage || kind == .openai }
    var reframePromptModel: String { isFAL ? falModelId(styleMode: .attachStyleImage) : model }

    func falModelId(styleMode: LensRenderStyleMode) -> String {
        guard isFAL else { return "" }
        if styleMode == .attachStyleImage, !styleModel.isEmpty {
            return styleModel
        }
        return model
    }

    var falPromptLimit: Int { promptLimit ?? 2_400 }

    var stabilityStrength: Double {
        switch stabilityInput["strength"] {
        case .double(let value): value
        case .int(let value): Double(value)
        default: 0.65
        }
    }

    var stabilityAspectRatio: String {
        guard case .string(let value)? = stabilityInput["aspect_ratio"] else { return "16:9" }
        return value
    }

    /// The FAL request body: the YAML input verbatim plus the prompt. Sizes
    /// are enforced wide in the YAML (no aspect-dependent injection).
    func falBaseInput(prompt: String, mediaPlan: LensMediaPlan, styleMode: LensRenderStyleMode) -> [String: Any] {
        var input = falInput.mapValues(\.anyValue)
        input["prompt"] = prompt
        return input
    }

    func falDebugParameterKeys(styleMode: LensRenderStyleMode) -> [String] {
        debugKeys
    }

    func falDebugParameterTemplate(mediaPlan: LensMediaPlan, styleMode: LensRenderStyleMode) -> String {
        let input = falBaseInput(prompt: "", mediaPlan: mediaPlan, styleMode: styleMode)
            .filter { key, _ in key != "prompt" }
        guard JSONSerialization.isValidJSONObject(input),
              let data = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// The CivitAI workflow payload: the YAML input verbatim plus prompt,
    /// resolved seed, and optional negative prompt. One builder for every
    /// CivitAI stack (WAN, Flux.2 Klein, and any user-defined workflow).
    /// The stack's declared CivitAI canvas, when its YAML input carries one.
    var civitaiDeclaredSize: (width: Int, height: Int)? {
        guard case .int(let width)? = civitaiInput["width"],
              case .int(let height)? = civitaiInput["height"] else { return nil }
        return (width, height)
    }

    func civitaiPayload(
        prompt: String,
        requestSeed: Int?,
        negativePrompt: String,
        widthOverride: Int? = nil,
        heightOverride: Int? = nil
    ) -> (payload: [String: Any], seed: Int) {
        var input = civitaiInput.mapValues(\.anyValue)
        input["prompt"] = prompt
        let seed = civitaiSeed.resolve(requestSeed)
        input["seed"] = seed
        // Roster character studies reorient the stack's declared pixel budget
        // (portrait/square shots must not render the FRAMES 16:9 landscape).
        if let widthOverride, let heightOverride, input["width"] != nil, input["height"] != nil {
            input["width"] = widthOverride
            input["height"] = heightOverride
        }
        let trimmedNegative = negativePrompt.trimmed
        if !trimmedNegative.isEmpty {
            input["negativePrompt"] = trimmedNegative
        }
        var step: [String: Any] = [
            "$type": "imageGen",
            "input": input
        ]
        if let priority = civitaiStepPriority {
            step["priority"] = priority
        }
        let payload: [String: Any] = [
            "tags": civitaiTags,
            "steps": [step]
        ]
        return (payload, seed)
    }

    /// The persisted render-recipe snapshot for a take, per kind. Mirrors the
    /// retired enum + provider snapshots (openai keeps stackId nil so legacy
    /// render-version fingerprints don't shift).
    func renderRecipeSnapshot(
        mediaPlan: LensMediaPlan?,
        styleMode: LensRenderStyleMode,
        isCharacterStudy: Bool = false,
        hasStyleReferences: Bool = false,
        seed: Int? = nil,
        debugParametersJSON: String = "",
        generatedParameters: [LensRenderRecipeParameter] = [],
        imageSizeOverride: String? = nil,
        sourceImageCount: Int = 0,
        usesCompositeImage: Bool = false
    ) -> LensRenderRecipeSnapshot {
        switch kind {
        case .fal:
            let plan = mediaPlan?.normalized() ?? LensMediaPlan()
            var parameters = falBaseInput(prompt: "", mediaPlan: plan, styleMode: styleMode)
                .filter { key, _ in key != "prompt" && key != "image_urls" && key != "image_url" }
                .map { key, value in
                    LensRenderRecipeParameter(key: key, value: renderStackParameterString(value), valueType: renderStackParameterType(value))
                }
            if !debugParametersJSON.trimmed.isEmpty {
                parameters.append(LensRenderRecipeParameter(key: "debug_overrides_json", value: debugParametersJSON.trimmed, valueType: "json"))
            }
            if !generatedParameters.isEmpty {
                parameters = generatedParameters
            }
            if !priceNote.isEmpty,
               !parameters.contains(where: { $0.key == "provider_price_note" }) {
                parameters.append(
                    LensRenderRecipeParameter(
                        key: "provider_price_note",
                        value: priceNote,
                        valueType: "string"
                    )
                )
            }
            return LensRenderRecipeSnapshot(
                label: label,
                provider: kind.rawValue,
                model: falModelId(styleMode: styleMode),
                stackId: stackId,
                parameters: parameters,
                capabilities: workflows.contains(.reframeZoomOut)
                    ? ["imageOutpaint"]
                    : (styleMode == .attachStyleImage ? ["textToImage", "styleImageReference"] : ["textToImage"])
            ).normalized()
        case .openai:
            let plan = mediaPlan?.normalized()
            let outputFormat = isCharacterStudy ? "png" : "jpeg"
            var parameters: [LensRenderRecipeParameter] = [
                LensRenderRecipeParameter(key: "output_format", value: outputFormat),
                LensRenderRecipeParameter(key: "image_size", value: imageSizeOverride ?? imageSize ?? plan?.imageSize ?? "1024x1024"),
                LensRenderRecipeParameter(key: "quality", value: "medium")
            ]
            if !generatedParameters.isEmpty {
                parameters = generatedParameters
            }
            var capabilities = ["textToImage"]
            if hasStyleReferences {
                capabilities.append(contentsOf: ["imageToImage", "styleVariant"])
            }
            if isCharacterStudy {
                capabilities.append("identityPreservation")
            }
            if workflows.contains(.reframeZoomOut) {
                capabilities.append(contentsOf: ["imageOutpaint"])
            }
            return LensRenderRecipeSnapshot(
                label: label,
                provider: kind.rawValue,
                model: model,
                stackId: nil,
                parameters: parameters,
                capabilities: capabilities
            ).normalized()
        case .civitai:
            let seedText = seed.map(String.init) ?? "random"
            let parameters = civitaiRecipe.map { parameter in
                parameter.value == "$runtime_seed"
                    ? LensRenderRecipeParameter(key: parameter.key, value: seedText, valueType: parameter.valueType)
                    : parameter
            }
            return LensRenderRecipeSnapshot(
                label: label,
                provider: kind.rawValue,
                model: model,
                stackId: stackId,
                parameters: parameters,
                capabilities: ["textToImage"]
            ).normalized()
        case .stability:
            var parameters = stabilityInput
                .filter { key, _ in sourceImageCount > 0 || key != "strength" }
                .map { key, value in
                    LensRenderRecipeParameter(key: key, value: renderStackTraceValue(value), valueType: renderStackParameterType(value.anyValue))
                }
            parameters.append(contentsOf: [
                LensRenderRecipeParameter(key: "native_image_count", value: sourceImageCount > 0 ? "1" : "0", valueType: "number"),
                LensRenderRecipeParameter(key: "source_image_count", value: String(sourceImageCount), valueType: "number"),
                LensRenderRecipeParameter(
                    key: "attachment_mode",
                    value: sourceImageCount == 0 ? "none" : (usesCompositeImage ? "composite" : "direct"),
                    valueType: "string"
                )
            ])
            if !generatedParameters.isEmpty {
                parameters = generatedParameters
            }
            var capabilities = ["textToImage"]
            if sourceImageCount > 0 {
                capabilities.append("imageToImage")
            }
            if styleMode == .attachStyleImage {
                capabilities.append("styleImageReference")
            }
            return LensRenderRecipeSnapshot(
                label: label,
                provider: kind.rawValue,
                model: model,
                stackId: stackId,
                parameters: parameters,
                capabilities: capabilities
            ).normalized()
        }
    }

    /// Hardcoded safety net used only if the bundled YAML is missing or
    /// unreadable — the app must never be left without a render stack.
    static let builtInOpenAIFallback = RenderStack(
        id: RenderStackID.openAIBase,
        stackId: "openai.base.v0",
        label: "OpenAI Base",
        detail: "Available · gpt-image-2",
        priceNote: "",
        kind: .openai,
        credentialProvider: .openAI,
        order: 0,
        model: "gpt-image-2",
        styleModel: "",
        canAttachStyleImage: false,
        workflows: [.frameCreator, .reframeZoomIn, .reframeZoomOut, .reframeViewpoint],
        promptImageLimitOverride: nil,
        promptLimit: nil,
        outputFormat: "jpeg",
        imageSize: "1536x1024",
        promptInstructions: "",
        falInput: [:],
        debugKeys: [],
        stabilityInput: [:],
        civitaiInput: [:],
        civitaiTags: [],
        civitaiStepPriority: nil,
        civitaiSeed: .random,
        civitaiRecipe: []
    )
}

/// Human-readable rendering of a stack input value for trace snapshots.
func renderStackTraceValue(_ value: JSONScalar) -> String {
    renderStackParameterString(value.anyValue)
}

private func renderStackParameterString(_ value: Any) -> String {
    if let value = value as? Bool { return value ? "true" : "false" }
    if let value = value as? String { return value }
    if let value = value as? NSNumber { return value.stringValue }
    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        return text
    }
    return "\(value)"
}

private func renderStackParameterType(_ value: Any) -> String {
    if value is Bool { return "boolean" }
    if value is NSNumber { return "number" }
    if value is [String: Any] || value is [Any] { return "json" }
    return "string"
}

// MARK: - Codable (wire = the id string, resolved through the registry)

extension RenderStack: Codable {
    init(from decoder: Decoder) throws {
        let id = try decoder.singleValueContainer().decode(String.self)
        self = RenderStackRegistry.shared.stack(id: id) ?? RenderStackRegistry.shared.fallback
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}

// MARK: - Registry

/// Loads render stacks from the bundled render_stacks.yaml plus an optional
/// user overlay in Application Support (merged by id). A class (not an actor)
/// because RenderStack's Codable decode must resolve synchronously.
final class RenderStackRegistry: @unchecked Sendable {
    static let shared = RenderStackRegistry()
    static let userFileName = "render_stacks.yaml"

    static var userFileURL: URL {
        litScenesApplicationSupportDirectory().appendingPathComponent(userFileName)
    }

    private let lock = NSLock()
    private var cache: [RenderStack]?
    private let includeUserOverlay: Bool

    init(includeUserOverlay: Bool = true) {
        self.includeUserOverlay = includeUserOverlay
    }

    /// Historical public surface: stacks available to create a frame. Workflow-
    /// only providers such as Outpaint stay out of every ordinary stack picker.
    func stacks() -> [RenderStack] {
        registeredStacks().filter(\.frameCreatorCapable)
    }

    private func registeredStacks() -> [RenderStack] {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        let loaded = load()
        cache = loaded
        return loaded
    }

    func stack(id: String) -> RenderStack? {
        registeredStacks().first { $0.id == id }
    }

    func stack(stackId: String) -> RenderStack? {
        let trimmed = stackId.trimmed
        guard !trimmed.isEmpty else { return nil }
        return registeredStacks().first { $0.stackId == trimmed }
    }

    func reframeStacks() -> [RenderStack] {
        registeredStacks().filter(\.reframeCapable)
    }

    func frameCreatorStacks() -> [RenderStack] {
        stacks()
    }

    func reframeStacks(mode: String) -> [RenderStack] {
        registeredStacks().filter { $0.supportsReframe(mode: mode) }
    }

    /// The first stack (in order) whose credential is satisfied — reproduces
    /// the old seeded-default chain (openai → civitai WAN → nil).
    func defaultStack(hasOpenAI: Bool, hasCivitai: Bool, hasFAL: Bool, hasStability: Bool = false) -> RenderStack? {
        frameCreatorStacks().first { stack in
            switch stack.credentialProvider {
            case .openAI: return hasOpenAI
            case .civitai: return hasCivitai
            case .fal: return hasFAL && hasOpenAI
            case .stability: return hasStability && hasOpenAI
            default: return false
            }
        }
    }

    var fallback: RenderStack {
        stack(id: RenderStackID.openAIBase) ?? RenderStack.builtInOpenAIFallback
    }

    func reload() {
        lock.lock()
        defer { lock.unlock() }
        cache = nil
    }

    // MARK: Loading

    private func load() -> [RenderStack] {
        var lists: [[RenderStack]] = []
        if let bundled = try? packagedResourceURL(named: "render_stacks", extension: "yaml"),
           let text = try? String(contentsOf: bundled, encoding: .utf8) {
            lists.append(Self.decodeStacks(yamlText: text, source: "bundled"))
        } else {
            print("[render_stacks] bundled render_stacks.yaml missing — using built-in fallback stack")
        }
        if includeUserOverlay,
           FileManager.default.fileExists(atPath: Self.userFileURL.path),
           let text = try? String(contentsOf: Self.userFileURL, encoding: .utf8) {
            lists.append(Self.decodeStacks(yamlText: text, source: "user"))
        }
        let merged = Self.merged(lists)
        return merged.isEmpty ? [RenderStack.builtInOpenAIFallback] : merged
    }

    /// Later lists override earlier ones by id (user overlay beats bundled);
    /// new ids append. Result sorts by `order`, original position breaking ties.
    static func merged(_ lists: [[RenderStack]]) -> [RenderStack] {
        var ordered: [RenderStack] = []
        var indexById: [String: Int] = [:]
        for list in lists {
            for stack in list {
                if let existing = indexById[stack.id] {
                    ordered[existing] = stack
                } else {
                    indexById[stack.id] = ordered.count
                    ordered.append(stack)
                }
            }
        }
        return ordered.enumerated()
            .sorted { lhs, rhs in
                lhs.element.order == rhs.element.order
                    ? lhs.offset < rhs.offset
                    : lhs.element.order < rhs.element.order
            }
            .map(\.element)
    }

    /// Parses one YAML document's `stacks:` list; malformed entries are logged
    /// and skipped so a bad user entry never takes out the defaults.
    static func decodeStacks(yamlText: String, source: String) -> [RenderStack] {
        do {
            guard let root = try Yams.load(yaml: yamlText) as? [String: Any],
                  let entries = root["stacks"] as? [Any] else {
                print("[render_stacks] \(source): no `stacks:` list found — skipped")
                return []
            }
            return entries.compactMap { entry in
                guard let raw = entry as? [String: Any] else { return nil }
                if let stack = decodeStack(raw) {
                    return stack
                }
                let badId = (raw["id"] as? String) ?? "<missing id>"
                print("[render_stacks] \(source): entry \(badId) is malformed — skipped")
                return nil
            }
        } catch {
            print("[render_stacks] \(source): YAML parse failed — \(error.localizedDescription)")
            return []
        }
    }

    private static func decodeStack(_ raw: [String: Any]) -> RenderStack? {
        guard let id = (raw["id"] as? String)?.trimmed, !id.isEmpty,
              let kindRaw = (raw["kind"] as? String)?.trimmed.lowercased(),
              let kind = RenderStackKind(rawValue: kindRaw) else {
            return nil
        }
        let credentialRaw = ((raw["credential_provider"] as? String) ?? kindRaw).trimmed.lowercased()
        guard let credential = LitScenesProviderCredential(rawValue: credentialRaw) else {
            return nil
        }
        let label = (raw["label"] as? String)?.trimmed ?? id
        guard !label.isEmpty else { return nil }

        var falInput: [String: JSONScalar] = [:]
        var debugKeys: [String] = []
        if let fal = raw["fal"] as? [String: Any] {
            if let input = fal["input"] as? [String: Any] {
                guard case .object(let scalars)? = JSONScalar(any: input) else { return nil }
                falInput = scalars
            }
            debugKeys = (fal["debug_keys"] as? [Any])?.compactMap { $0 as? String } ?? []
        }

        var stabilityInput: [String: JSONScalar] = [:]
        if let stability = raw["stability"] as? [String: Any],
           let input = stability["input"] as? [String: Any] {
            guard case .object(let scalars)? = JSONScalar(any: input) else { return nil }
            stabilityInput = scalars
        }

        var civitaiInput: [String: JSONScalar] = [:]
        var civitaiTags: [String] = []
        var civitaiStepPriority: String?
        var civitaiSeed: RenderStackSeed = .random
        var civitaiRecipe: [LensRenderRecipeParameter] = []
        if let civitai = raw["civitai"] as? [String: Any] {
            if let input = civitai["input"] as? [String: Any] {
                guard case .object(let scalars)? = JSONScalar(any: input) else { return nil }
                civitaiInput = scalars
            }
            civitaiTags = (civitai["tags"] as? [Any])?.compactMap { $0 as? String } ?? []
            civitaiStepPriority = (civitai["step_priority"] as? String)?.trimmed.nilIfEmpty
            if let fixed = civitai["seed"] as? Int {
                civitaiSeed = .fixed(fixed)
            }
            if let recipe = civitai["recipe"] as? [Any] {
                civitaiRecipe = recipe.compactMap { entry in
                    guard let entry = entry as? [String: Any],
                          let key = (entry["key"] as? String)?.trimmed, !key.isEmpty else {
                        return nil
                    }
                    let value = renderStackParameterString(entry["value"] ?? "")
                    let valueType = (entry["value_type"] as? String)?.trimmed.nilIfEmpty ?? "string"
                    return LensRenderRecipeParameter(key: key, value: value, valueType: valueType)
                }
            }
        }

        // Kind-specific sanity: a civitai stack without an input map can't render.
        if kind == .civitai, civitaiInput.isEmpty { return nil }
        if kind == .fal, falInput.isEmpty { return nil }
        if kind == .stability, stabilityInput.isEmpty { return nil }

        let declaredWorkflows = (raw["workflows"] as? [Any])?
            .compactMap { ($0 as? String)?.trimmed.lowercased() }
            .compactMap(RenderStackWorkflow.init(rawValue:))
        var workflows = Set(declaredWorkflows ?? [])
        if declaredWorkflows == nil {
            workflows.insert(.frameCreator)
            if raw["reframe_capable"] as? Bool ?? false {
                workflows.formUnion([.reframeZoomIn, .reframeViewpoint])
            }
            // Older user overlays for the shipped OpenAI stack predate
            // workflow-specific capabilities; keep Zoom Out available.
            if id == RenderStackID.openAIBase {
                workflows.insert(.reframeZoomOut)
            }
        }

        return RenderStack(
            id: id,
            stackId: (raw["stack_id"] as? String)?.trimmed.nilIfEmpty ?? id,
            label: label,
            detail: (raw["detail"] as? String)?.trimmed ?? "",
            priceNote: (raw["price_note"] as? String)?.trimmed ?? "",
            kind: kind,
            credentialProvider: credential,
            order: raw["order"] as? Int ?? 1_000,
            model: (raw["model"] as? String)?.trimmed ?? "",
            styleModel: (raw["style_model"] as? String)?.trimmed ?? "",
            canAttachStyleImage: raw["can_attach_style_image"] as? Bool ?? false,
            workflows: workflows,
            promptImageLimitOverride: (raw["prompt_image_limit"] as? Int).map { max($0, 0) },
            promptLimit: raw["prompt_limit"] as? Int,
            outputFormat: ((raw["output_format"] as? String)?.trimmed.lowercased()).flatMap { $0 == "png" ? "png" : "jpeg" } ?? "jpeg",
            imageSize: (raw["image_size"] as? String)?.trimmed.nilIfEmpty,
            promptInstructions: (raw["prompt_instructions"] as? String)?.trimmed ?? "",
            falInput: falInput,
            debugKeys: debugKeys,
            stabilityInput: stabilityInput,
            civitaiInput: civitaiInput,
            civitaiTags: civitaiTags,
            civitaiStepPriority: civitaiStepPriority,
            civitaiSeed: civitaiSeed,
            civitaiRecipe: civitaiRecipe
        )
    }
}
