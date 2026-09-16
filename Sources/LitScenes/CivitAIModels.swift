import Foundation

func civitaiRequestSeed(runId: String, artifactId: String) -> Int {
    let hex = sha256Hex(Data((runId + ":" + artifactId).utf8)).prefix(8)
    return Int(hex, radix: 16).map { max(1, $0 % Int(Int32.max)) } ?? 1
}

enum CivitAIMediaKind: String, Codable, Sendable { case image, video }

/// Provider identifiers and user choices only; never credentials or media URLs.
struct CivitAIResource: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var modelId: Int
    var name: String
    var versionName: String
    var baseModel: String
    var type: String
    var air: String
    var trainedWords: [String] = []

    var ecosystem: String {
        let parts = air.replacingOccurrences(of: "urn:", with: "").split(separator: ":")
        return parts.count >= 5 ? String(parts[1]).lowercased() : ""
    }
    var isLoRA: Bool { type.lowercased() == "lora" || type.lowercased() == "locon" }
}

struct CivitAILoRA: Codable, Hashable, Identifiable, Sendable {
    var resource: CivitAIResource
    var strength: Double = 1
    var id: Int { resource.id }
}

enum CivitAIProfile: String, Codable, CaseIterable, Sendable {
    case sd1, sdxl, klein4b, klein9b, wanImage27, wanVideo22, wanVideo25, wanVideo27
    var kind: CivitAIMediaKind {
        switch self { case .wanVideo22, .wanVideo25, .wanVideo27: .video; default: .image }
    }
    var label: String {
        switch self {
        case .sd1: "SD 1.5"
        case .sdxl: "SDXL"
        case .klein4b: "Flux.2 Klein 4B"
        case .klein9b: "Flux.2 Klein 9B"
        case .wanImage27: "WAN 2.7 Image"
        case .wanVideo22: "WAN 2.2 · Custom model / LoRAs"
        case .wanVideo25: "WAN 2.5 Video"
        case .wanVideo27: "WAN 2.7 Video"
        }
    }
    var catalogBase: String {
        switch self {
        case .sd1: "SD 1.5"
        case .sdxl: ""
        case .klein4b: "Flux.2 Klein 4B"
        case .klein9b: "Flux.2 Klein 9B"
        case .wanVideo22, .wanVideo25, .wanVideo27: "Wan Video 2.2 I2V-A14B"
        case .wanImage27: ""
        }
    }
    var needsCheckpoint: Bool { self == .sd1 || self == .sdxl }
    var supportsLoRAs: Bool { ![.wanImage27, .wanVideo25, .wanVideo27].contains(self) }
    var supportsEnding: Bool { self == .wanVideo27 }
    var referenceLimit: Int { self == .wanImage27 ? 4 : (self == .klein4b || self == .klein9b ? 2 : 1) }
    var durations: [Int] { self == .wanVideo27 ? [5, 6, 8, 10] : [5, 10] }

    func accepts(_ resource: CivitAIResource) -> Bool {
        guard !resource.air.isEmpty, resource.isLoRA || resource.type.lowercased() == "checkpoint" else { return false }
        if resource.isLoRA && !supportsLoRAs { return false }
        switch self {
        case .sd1: return resource.ecosystem == "sd1"
        case .sdxl: return resource.ecosystem == "sdxl"
        case .klein4b, .klein9b:
            let base = resource.baseModel.lowercased()
            return resource.isLoRA && ["flux2", "flux2klein"].contains(resource.ecosystem) && base.contains("klein")
                && base.contains(self == .klein4b ? "4b" : "9b")
        case .wanVideo22:
            return resource.baseModel.lowercased().contains("wan video 2.2")
                && resource.baseModel.lowercased().contains("i2v")
        default: return false
        }
    }
}

struct CivitAIRecipe: Codable, Hashable, Sendable {
    // Array storage keeps snapshots compact inside deeply nested Shot values,
    // while retaining Swift's copy-on-write value semantics for independent drafts.
    struct Fields: Codable, Hashable, Sendable {
        var schemaVersion = 1
        var profile: CivitAIProfile
        var checkpoint: CivitAIResource?
        var loras: [CivitAILoRA] = []
        var steps: Int = 25
        var guidance: Double = 5
        var seed: Int?
        var width: Int = 1280
        var height: Int = 720
        var duration: Int = 5
        var strength: Double = 0.7
        var negativePrompt = ""
        var allowMatureContent = true
    
    }
    private var storage: [Fields]
    var schemaVersion: Int { get { storage[0].schemaVersion } set { storage[0].schemaVersion = newValue } }
    var profile: CivitAIProfile { get { storage[0].profile } set { storage[0].profile = newValue } }
    var checkpoint: CivitAIResource? { get { storage[0].checkpoint } set { storage[0].checkpoint = newValue } }
    var loras: [CivitAILoRA] { get { storage[0].loras } set { storage[0].loras = newValue } }
    var steps: Int { get { storage[0].steps } set { storage[0].steps = newValue } }
    var guidance: Double { get { storage[0].guidance } set { storage[0].guidance = newValue } }
    var seed: Int? { get { storage[0].seed } set { storage[0].seed = newValue } }
    var width: Int { get { storage[0].width } set { storage[0].width = newValue } }
    var height: Int { get { storage[0].height } set { storage[0].height = newValue } }
    var duration: Int { get { storage[0].duration } set { storage[0].duration = newValue } }
    var strength: Double { get { storage[0].strength } set { storage[0].strength = newValue } }
    var negativePrompt: String { get { storage[0].negativePrompt } set { storage[0].negativePrompt = newValue } }
    var allowMatureContent: Bool { get { storage[0].allowMatureContent } set { storage[0].allowMatureContent = newValue } }
    init(from decoder: Decoder) throws { storage = [try Fields(from: decoder)] }
    func encode(to encoder: Encoder) throws { try storage[0].encode(to: encoder) }

    var label: String {
        (checkpoint.map { "\($0.name) · \($0.versionName)" } ?? profile.label)
            + (loras.isEmpty ? "" : " + \(loras.count) LoRA\(loras.count == 1 ? "" : "s")")
    }
    var modelId: String { checkpoint?.air ?? profile.rawValue }
    var identity: String { "civitai.catalog." + shortHash(wireValue, length: 24) }
    var wireValue: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return "civitai-recipe:" + ((try? encoder.encode(self))?.base64EncodedString() ?? "")
    }
    init(profile: CivitAIProfile) { storage = [Fields(profile: profile)] }
    init?(wireValue: String) {
        guard wireValue.hasPrefix("civitai-recipe:"),
              let data = Data(base64Encoded: String(wireValue.dropFirst("civitai-recipe:".count))),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = value
    }
    var validationError: String? {
        if let seed, seed < 0 || seed > Int(Int32.max) { return "Seed must be between 0 and 2147483647." }
        if schemaVersion != 1 { return "This saved Civitai recipe needs a newer app." }
        if profile.needsCheckpoint && checkpoint == nil { return "Choose a checkpoint version." }
        if let checkpoint, checkpoint.isLoRA || !profile.accepts(checkpoint) { return "This checkpoint does not match the selected family." }
        if loras.contains(where: { !$0.resource.isLoRA || !profile.accepts($0.resource) || !$0.strength.isFinite || abs($0.strength) > 2 }) {
            return "Review incompatible LoRAs or weights outside −2…2." }
        if Set(loras.map(\.id)).count != loras.count { return "Remove duplicate LoRA versions." }
        if !(10...50).contains(steps) || !guidance.isFinite || !(1...20).contains(guidance) { return "Review steps and guidance." }
        if !(512...2048).contains(width) || !(512...2048).contains(height) || width % 8 != 0 || height % 8 != 0 {
            return "Image dimensions must be multiples of 8 between 512 and 2048." }
        if !strength.isFinite || !(0...1).contains(strength) { return "Image change must be between 0 and 1." }
        if profile.kind == .video && !profile.durations.contains(duration) { return "Choose a supported duration." }
        return nil
    }
    func payload(prompt: String, images: [String], endImage: String? = nil, resolvedSeed: Int? = nil) throws -> [String: Any] {
        if let error = validationError { throw ScreenGraphError.capture(error) }
        guard !prompt.trimmed.isEmpty else { throw ScreenGraphError.capture("Enter a prompt.") }
        var input: [String: Any] = ["prompt": prompt, "seed": resolvedSeed ?? seed ?? Int.random(in: 1...Int(Int32.max))]
        if profile.kind == .image {
            guard images.count <= profile.referenceLimit else { throw ScreenGraphError.capture("Too many native image inputs for this recipe.") }
            input.merge(["quantity": 1, "outputFormat": "jpeg", "operation": images.isEmpty ? "createImage" : "editImage"]) { _, b in b }
            switch profile {
            case .sd1, .sdxl:
                input.merge(["engine": "sdcpp", "ecosystem": profile.rawValue, "model": checkpoint!.air,
                    "steps": steps, "cfgScale": guidance, "width": width, "height": height,
                    "sampleMethod": "euler", "schedule": "karras", "loras": Dictionary(uniqueKeysWithValues: loras.map { ($0.resource.air, $0.strength) })]) { _, b in b }
                if let image = images.first { input["operation"] = "createVariant"; input["image"] = image; input["strength"] = strength }
            case .klein4b, .klein9b:
                input.merge(["engine": "flux2", "model": "klein", "modelVersion": profile == .klein4b ? "4b" : "9b",
                    "steps": steps, "cfgScale": guidance, "width": width, "height": height,
                    "loras": Dictionary(uniqueKeysWithValues: loras.map { ($0.resource.air, $0.strength) })]) { _, b in b }
                if !images.isEmpty { input["images"] = images }
            case .wanImage27:
                input.merge(["engine": "wan", "version": "v2.7", "provider": "fal", "imageSize": "landscape_16_9",
                    "guidanceScale": guidance, "enablePromptExpansion": false, "usePro": false]) { _, b in b }
                if !images.isEmpty { input["images"] = images }
            default: break
            }
        } else {
            guard let start = images.first else { throw ScreenGraphError.capture("Civitai video requires a start frame.") }
            guard endImage == nil || profile.supportsEnding else { throw ScreenGraphError.capture("This model cannot constrain the ending frame. Choose WAN 2.7.") }
            input.merge(["engine": "wan", "cfgScale": guidance, "duration": duration]) { _, b in b }
            switch profile {
            case .wanVideo22:
                input.merge(["version": "v2.2", "provider": "comfy", "images": [start], "width": width, "height": height,
                    "steps": steps, "loras": loras.map { ["air": $0.resource.air, "strength": $0.strength] as [String: Any] }]) { _, b in b }
                if let checkpoint { input["model"] = checkpoint.air }
            case .wanVideo25:
                input.merge(["version": "v2.5", "provider": "fal", "operation": "image-to-video", "images": [start],
                    "resolution": height >= 1080 ? "1080p" : "720p", "enablePromptExpansion": false]) { _, b in b }
            case .wanVideo27:
                input.merge(["version": "v2.7", "provider": "fal", "operation": "image-to-video", "startImage": start,
                    "resolution": height >= 1080 ? "1080p" : "720p", "enablePromptExpansion": false]) { _, b in b }
                if let endImage { input["endImage"] = endImage }
            default: break
            }
        }
        if !negativePrompt.trimmed.isEmpty { input["negativePrompt"] = negativePrompt }
        return ["allowMatureContent": allowMatureContent, "currencies": allowMatureContent ? ["yellow"] : ["blue", "green", "yellow"], "tags": ["litscenes", "civitai-browser"], "steps": [["$type": profile.kind == .image ? "imageGen" : "videoGen", "input": input]]]
    }

    func imageStack() -> RenderStack {
        RenderStack(id: identity, stackId: identity, label: label, detail: "Civitai · My API key", priceNote: "Civitai quote before generation",
            kind: .civitai, credentialProvider: .civitai, order: 100, model: modelId, styleModel: "", canAttachStyleImage: false,
            workflows: [.frameCreator], promptImageLimitOverride: profile.referenceLimit, promptLimit: profile == .klein4b || profile == .klein9b ? 1000 : 1800,
            outputFormat: "jpeg", imageSize: nil, promptInstructions: "", falInput: [:], debugKeys: [], stabilityInput: [:],
            civitaiInput: [:], civitaiTags: [], civitaiStepPriority: nil, civitaiSeed: seed.map(RenderStackSeed.fixed) ?? .random,
            civitaiRecipe: [], civitaiImageInputMode: profile == .sd1 || profile == .sdxl ? .variantImage : .editImages, catalogRecipe: self)
    }
}

enum CivitAIPreferences {
    static func last(_ kind: CivitAIMediaKind) -> CivitAIRecipe? {
        guard let data = LitScenesPreferences.store.data(forKey: "civitai.last.\(kind.rawValue)") else { return nil }
        return try? JSONDecoder().decode(CivitAIRecipe.self, from: data)
    }
    static func remember(_ recipe: CivitAIRecipe, preference: CivitAIRecipe? = nil) {
        guard let data = try? JSONEncoder().encode(recipe) else { return }
        LitScenesPreferences.store.set((try? JSONEncoder().encode(preference ?? recipe)) ?? data, forKey: "civitai.last.\(recipe.profile.kind.rawValue)")
        var archive = LitScenesPreferences.store.dictionary(forKey: "civitai.recipes") as? [String: Data] ?? [:]
        archive[recipe.identity] = data
        if let preference, let preferred = try? JSONEncoder().encode(preference) { archive[preference.identity] = preferred }
        LitScenesPreferences.store.set(archive, forKey: "civitai.recipes")
    }
    static func archive(_ recipe: CivitAIRecipe) {
        guard let data = try? JSONEncoder().encode(recipe) else { return }
        var archive = LitScenesPreferences.store.dictionary(forKey: "civitai.recipes") as? [String: Data] ?? [:]
        archive[recipe.identity] = data
        LitScenesPreferences.store.set(archive, forKey: "civitai.recipes")
    }
    static func archived(_ identity: String) -> CivitAIRecipe? {
        guard let data = LitScenesPreferences.store.dictionary(forKey: "civitai.recipes")?[identity] as? Data else { return nil }
        return try? JSONDecoder().decode(CivitAIRecipe.self, from: data)
    }
    static var isConfigured: Bool { LitScenesCredentialStore().personalCredentialStatus(for: .civitai).isConfigured }
}
