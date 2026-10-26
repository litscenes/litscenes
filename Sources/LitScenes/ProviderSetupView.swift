import SwiftUI

struct PersonalKeySetupView: View {
    @ObservedObject var library: LibraryEngine
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Two keys unlock the studio").font(CanonType.interface(16, weight: .semibold))
            Text("Each provider bills your usage directly: add billing with the provider, create a key, and paste it below. A ChatGPT subscription does not include OpenAI API usage.")
                .font(CanonType.interface(12)).foregroundStyle(CanonColor.muted).fixedSize(horizontal: false, vertical: true)
            WelcomeKeyRow(library: library, provider: .openAI, description: "Understands your media — analysis, stories, and frames. Save & Test checks the connection without generating anything.")
            HStack {
                Link("OpenAI API billing", destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
                Link("OpenAI API keys", destination: URL(string: "https://platform.openai.com/api-keys")!)
            }.font(CanonType.interface(12))
            WelcomeKeyRow(library: library, provider: .fal, description: "Renders motion — video models and fast image stacks.")
            Link("FAL API keys", destination: URL(string: "https://fal.ai/dashboard/keys")!)
                .font(CanonType.interface(12))
            Text("OPTIONAL — ADD ANYTIME")
                .font(CanonType.archive(11, weight: .semibold)).foregroundStyle(CanonColor.muted)
                .padding(.top, 4)
            WelcomeKeyRow(library: library, provider: .elevenLabs, description: "Voice and sound — narration and story audio.")
            Link("ElevenLabs API keys", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
                .font(CanonType.interface(12))
            Text("Importing media, browsing projects, local editing, and exporting your files never need a key.")
                .font(CanonType.interface(11)).foregroundStyle(CanonColor.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ProviderSetupHint: View {
    let provider: LitScenesProviderCredential
    @State private var showingSetup = false
    @State private var revision = 0
    var body: some View {
        let _ = revision
        if ProviderBilling.source(for: ProviderBilling.defaultTarget(for: provider)) == .personal && LitScenesCredentialStore().personalCredential(for: provider).isEmpty {
            HStack(spacing: 10) {
                Text(provider == .fal ? "To generate video, connect FAL once." : "To generate narration, connect ElevenLabs once.")
                    .font(.system(size: 12))
                Button("Connect \(provider.label)") { showingSetup = true }.buttonStyle(.bordered)
                Spacer()
            }.padding(12)
            .sheet(isPresented: $showingSetup, onDismiss: { revision += 1 }) {
                ProviderKeySetup(provider: provider)
            }
        }
    }
}

private struct ProviderKeySetup: View {
    let provider: LitScenesProviderCredential
    @State private var key = ""
    @State private var message = ""
    @State private var busy = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect \(provider.label)").font(.title2.weight(.semibold))
            Text("Create an API key and add provider billing. Usage is billed directly to your \(provider.label) account.")
            Link("Open \(provider.label) API keys", destination: URL(string: provider == .fal ? "https://fal.ai/dashboard/keys" : "https://elevenlabs.io/app/settings/api-keys")!)
            SecureField("Paste your API key", text: $key).textFieldStyle(.roundedBorder)
            HStack {
                Button(busy ? "Checking…" : "Save & Test") { Task { await save() } }.disabled(key.trimmed.isEmpty || busy)
                Spacer()
                Button("Done") { dismiss() }
            }
            if !message.isEmpty { Text(message).font(.caption) }
        }.padding(24).frame(width: 460)
    }
    private func save() async {
        busy = true
        defer { busy = false }
        do {
            var values = loadDotEnv(from: OpenAIKeyStore.savedKeyURL)
            values[provider.primaryWritableKey] = key.trimmed
            try OpenAIKeyStore.saveCredentialValues(values)
            let outcome = await CredentialProbe().probe(provider, apiKey: key.trimmed)
            switch outcome {
            case .valid: message = "Connected. You can create now."
            case .validButLimited: message = "Key accepted, but \(provider.label) answered with a limit (HTTP 429). If the account is out of credits, add funds before creating."
            case .invalidKey: message = "The provider rejected this key. Check it and try again."
            case .unreachable: message = "Key saved, but the provider could not be reached. Try again."
            }
            NotificationCenter.default.post(name: .providerCredentialsChanged, object: nil)
        } catch { message = error.localizedDescription }
    }
}
