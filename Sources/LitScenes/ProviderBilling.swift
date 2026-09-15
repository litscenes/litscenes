import Foundation
import SwiftUI

enum ProviderBillingSource: String, Codable, CaseIterable, Sendable {
    case go
    case personal
    var label: String { self == .go ? "Go credits" : "My API key" }
}

/// A billing choice belongs to an executable model or workflow, never just a vendor.
struct ProviderBillingTarget: Hashable, Sendable {
    var id: String
    var provider: LitScenesProviderCredential
    var supportsGo: Bool = false

    static let text = Self(id: "openai.text", provider: .openAI, supportsGo: true)
    static let story = Self(id: "story", provider: .openAI, supportsGo: true)
    static let audio = Self(id: "elevenlabs.audio", provider: .elevenLabs, supportsGo: true)
    static func personal(_ provider: LitScenesProviderCredential) -> Self {
        Self(id: provider.rawValue, provider: provider)
    }
    static func fal(_ model: String) -> Self {
        let canonical = model == "fal-ai/nano-banana-2/edit" ? "fal-ai/nano-banana-2" : model
        return Self(id: canonical, provider: .fal, supportsGo: [
            "fal-ai/nano-banana-2", "fal-ai/kling-video/v3/pro/image-to-video"
        ].contains(canonical))
    }
    static func image(_ stack: RenderStack) -> Self {
        stack.isFAL ? .fal(stack.falModelId(styleMode: .none)) : .personal(stack.credentialProvider)
    }
    static func video(_ model: ShotRenderModel) -> Self {
        switch model.providerSelection {
        case .falImageToVideo, .falAudioToVideo:
            return .fal(ShotRenderStack.recipe(model: model, durationSeconds: model.defaultDuration).pairedModelSelection.providerModelId)
        case .ltxDirect: return .personal(.ltx)
        case .klingImageToVideo: return .personal(.kling)
        default: return .personal(.civitai)
        }
    }
}

struct ProviderBillingSnapshot: Codable, Sendable {
    var defaultSource: ProviderBillingSource
    var overrides: [String: ProviderBillingSource]

    static func capture() -> Self {
        let values = UserDefaults.standard.dictionary(forKey: ProviderBilling.preferenceKey) ?? [:]
        return Self(defaultSource: GoConnection.isManaged ? .go : .personal,
            overrides: values.reduce(into: [:]) { result, pair in
                if let raw = pair.value as? String, let source = ProviderBillingSource(rawValue: raw) { result[pair.key] = source }
            })
    }
    func source(for target: ProviderBillingTarget) -> ProviderBillingSource {
        guard target.supportsGo else { return .personal }
        return overrides[target.id] ?? defaultSource
    }
    func including(in recipe: String) -> String {
        var object = (try? JSONSerialization.jsonObject(with: Data(recipe.utf8))) as? [String: Any] ?? [:]
        if object.isEmpty && !recipe.isEmpty { object["source_recipe"] = recipe }
        if let data = try? JSONEncoder().encode(self), let snapshot = try? JSONSerialization.jsonObject(with: data) {
            object["billing_snapshot"] = snapshot
        }
        return inferenceTraceJSONString(object)
    }
}

enum ProviderBilling {
    static let preferenceKey = "LitScenesProviderBillingSources"
    @TaskLocal static var snapshot: ProviderBillingSnapshot?
    static func source(for target: ProviderBillingTarget) -> ProviderBillingSource {
        (snapshot ?? ProviderBillingSnapshot.capture()).source(for: target)
    }
    static func select(_ source: ProviderBillingSource, for target: ProviderBillingTarget) {
        guard target.supportsGo else { return }
        var values = UserDefaults.standard.dictionary(forKey: preferenceKey) ?? [:]
        values[target.id] = source.rawValue
        UserDefaults.standard.set(values, forKey: preferenceKey)
        NotificationCenter.default.post(name: .goFundingChanged, object: nil)
    }
    static func defaultTarget(for provider: LitScenesProviderCredential) -> ProviderBillingTarget {
        switch provider {
        case .openAI: return .text
        case .fal: return .fal("fal-ai/nano-banana-2")
        case .elevenLabs: return .audio
        default: return .personal(provider)
        }
    }
    static func credential(for target: ProviderBillingTarget, store: LitScenesCredentialResolving = LitScenesCredentialStore()) -> String {
        source(for: target) == .go ? GoConnection.marker : store.personalCredential(for: target.provider)
    }
    static func isConfigured(_ target: ProviderBillingTarget, store: LitScenesCredentialResolving = LitScenesCredentialStore()) -> Bool {
        source(for: target) == .go || store.personalCredentialStatus(for: target.provider).isConfigured
    }
}

struct ProviderBillingControl: View {
    let target: ProviderBillingTarget
    @State private var revision = 0
    var body: some View {
        let _ = revision
        let source = ProviderBilling.source(for: target)
        VStack(alignment: .leading, spacing: 5) {
            if target.supportsGo {
                Picker("Pay with", selection: Binding(get: { source }, set: { ProviderBilling.select($0, for: target); revision += 1 })) {
                    ForEach(ProviderBillingSource.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 290)
            }
            Text(source == .go ? "Go credits · quote before generation" : "Your \(target.provider.label) account · billed separately")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if source == .personal && !ProviderBilling.isConfigured(target) {
                Text("Add a \(target.provider.label) key in Settings → Advanced providers.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goFundingChanged)) { _ in revision += 1 }
    }
}
