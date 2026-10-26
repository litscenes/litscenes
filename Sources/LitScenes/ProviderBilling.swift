import Foundation
import SwiftUI

enum ProviderBillingSource: String, Codable, CaseIterable, Sendable {
    case go
    case personal
    var label: String { self == .go ? "Go credits" : "My API key" }
}

/// Stable target identities preserve funding provenance in saved projects.
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
        // New work always uses vendor keys. Persisted snapshots retain their payer.
        Self(defaultSource: .personal, overrides: [:])
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

    static func defaultTarget(for provider: LitScenesProviderCredential) -> ProviderBillingTarget {
        switch provider {
        case .openAI: return .text
        case .fal: return .fal("fal-ai/nano-banana-2")
        case .elevenLabs: return .audio
        default: return .personal(provider)
        }
    }
    static func credential(for target: ProviderBillingTarget, store: LitScenesCredentialResolving = LitScenesCredentialStore()) -> String {
        source(for: target) == .go ? LegacyManagedWork.marker : store.personalCredential(for: target.provider)
    }
    static func isConfigured(_ target: ProviderBillingTarget, store: LitScenesCredentialResolving = LitScenesCredentialStore()) -> Bool {
        source(for: target) == .personal && store.personalCredentialStatus(for: target.provider).isConfigured
    }
}

struct ProviderBillingControl: View {
    let target: ProviderBillingTarget
    @State private var revision = 0
    var body: some View {
        let _ = revision
        let source = ProviderBilling.source(for: target)
        VStack(alignment: .leading, spacing: 5) {

            Text(source == .go ? "Retired managed job · start a new run with your API key" : "Your \(target.provider.label) account · billed separately")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if source == .personal && !ProviderBilling.isConfigured(target) {
                Text("Add a \(target.provider.label) key in Settings → Advanced providers.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .providerCredentialsChanged)) { _ in revision += 1 }
    }
}
