import SwiftUI

/// Decides what launch does about the welcome journey. Pure so the table is
/// pinnable. A user with any configured credential or any project is
/// grandfathered silently — the welcome is for a truly cold install only,
/// and the version constant lets a materially changed welcome re-run once.
enum FirstRunWelcomeEligibility {
    static let currentVersion = 1

    enum Decision: Equatable {
        case showWelcome
        case markSeenSilently
        case none
    }

    static func decide(seenVersion: Int, hasAnyCredential: Bool, hasAnyProject: Bool) -> Decision {
        guard seenVersion < currentVersion else { return .none }
        if hasAnyCredential || hasAnyProject {
            return .markSeenSilently
        }
        return .showWelcome
    }
}

/// First-run welcome plate: what a cold install sees instead of "No Project
/// Selected". Never blocking — the close X, Explore Without Keys, and
/// creating a project all end first-run for good. Reopenable later from App
/// Settings, where it overlays the current workspace instead.
struct FirstRunWelcomeView: View {
    @ObservedObject var library: LibraryEngine
    var onCreateProject: () -> Void
    var onOpenAppSettings: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 24) {
                    masthead
                    heroSection
                    optionalSection
                    if LitScenesReleaseIdentity.current.showsProInterestPromotion {
                        ProComingSoonCard(face: .card, surface: .dark)
                    }
                    exits
                    footnote
                }
                .frame(maxWidth: 560)
                .padding(32)
                .frame(maxWidth: .infinity)
            }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .padding(14)
            .help("Close — reopen anytime from App Settings")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanonColor.archiveWell)
    }

    private var masthead: some View {
        VStack(spacing: 10) {
            LitIconView(icon: .key, size: 48)
                .foregroundStyle(CanonColor.brass)
            Text("Welcome to LitScenes")
                .font(CanonType.editorial(28, weight: .semibold))
                .foregroundStyle(CanonColor.bone)
            Text("LitScenes composes stories from your own media, on your own provider accounts. Add a key to unlock the studio — or explore the rooms first. Everything here can wait.")
                .font(CanonType.editorial(15))
                .foregroundStyle(CanonColor.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("START HERE")
                .font(CanonType.archive(11, weight: .semibold))
                .foregroundStyle(CanonColor.brass)
            WelcomeKeyRow(
                library: library,
                provider: .openAI,
                description: "One key runs the core: media analysis, story, and frames."
            )
            baseURLDisclosure
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @State private var baseURLDraft = ""
    @State private var baseURLMessage = ""

    private var baseURLDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("Route every OpenAI call through an OpenAI-compatible gateway. HTTPS, or plain HTTP on localhost only.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    TextField("https://your-gateway/v1", text: $baseURLDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        saveBaseURL()
                    }
                    .buttonStyle(CanonUtilityButtonStyle())
                    .disabled(baseURLDraft.trimmed.isEmpty)
                }
                if !baseURLMessage.isEmpty {
                    Text(baseURLMessage)
                        .font(CanonType.interface(11, weight: .semibold))
                        .foregroundStyle(CanonColor.muted)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Advanced — custom endpoint")
                .font(CanonType.interface(12, weight: .medium))
                .foregroundStyle(CanonColor.muted)
        }
        .tint(CanonColor.muted)
        .padding(.leading, 2)
    }

    private func saveBaseURL() {
        do {
            try library.saveStoryInferenceSetting(
                key: OpenAITextEndpointSettings.baseURLKeys[0],
                value: baseURLDraft.trimmed
            )
            baseURLMessage = "Saved endpoint"
        } catch {
            baseURLMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    private var optionalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OPTIONAL — ADD ANYTIME")
                .font(CanonType.archive(11, weight: .semibold))
                .foregroundStyle(CanonColor.muted)
            WelcomeKeyRow(
                library: library,
                provider: .fal,
                description: "Video generation — powers most video models."
            )
            WelcomeKeyRow(
                library: library,
                provider: .elevenLabs,
                description: "Voice and sound — narration and story audio."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exits: some View {
        VStack(spacing: 12) {
            Button {
                onCreateProject()
            } label: {
                LitIconLabel(title: "Create Your First Project", icon: .folderAdd)
                    .frame(minWidth: 220)
            }
            .buttonStyle(CanonSecondaryButtonStyle())
            .controlSize(.large)

            Button("Explore Without Keys") {
                onDismiss()
            }
            .buttonStyle(CanonUtilityButtonStyle())

            HStack(spacing: 4) {
                Text("All eight providers and the optional hosted story service live in")
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.muted)
                Button("App Settings.") {
                    onOpenAppSettings()
                }
                .buttonStyle(.plain)
                .font(CanonType.interface(12, weight: .semibold))
                .foregroundStyle(CanonColor.brass)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var footnote: some View {
        Text("Keys are saved to credentials.env in Application Support, readable only by you, and sent only to the provider they belong to.")
            .font(CanonType.interface(11))
            .foregroundStyle(CanonColor.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
    }
}

/// One welcome key card: save + probe in a single gesture, with the probe
/// outcome spelled honestly — a rejected key and an unreachable provider
/// are different sentences, never conflated.
private struct WelcomeKeyRow: View {
    @ObservedObject var library: LibraryEngine
    let provider: LitScenesProviderCredential
    let description: String

    @State private var draft = ""
    @State private var isProbing = false
    @State private var feedback: (text: String, tone: Color)?

    private var status: CredentialStatus? {
        library.videoProviderCredentialStatuses.first { $0.provider == provider }
    }

    private var isConfigured: Bool {
        status?.isConfigured == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(provider.label)
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text(isConfigured ? "Configured" : "Missing")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(isConfigured ? CanonColor.olive : CanonColor.rust)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(CanonColor.paperInset.opacity(0.58), in: Capsule())
                Spacer()
                if isConfigured {
                    Text(status?.source.label ?? "")
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.muted)
                }
            }

            Text(description)
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                SecureField(isConfigured ? "Replace saved key" : provider.primaryWritableKey, text: $draft)
                    .textFieldStyle(.roundedBorder)
                if isProbing {
                    ProgressView()
                        .controlSize(.small)
                } else if isConfigured, draft.trimmed.isEmpty {
                    Button("Test") {
                        runProbe(saveFirst: false)
                    }
                    .buttonStyle(CanonUtilityButtonStyle())
                    .help("Check this key against \(provider.label) without spending anything")
                } else {
                    Button("Save & Test") {
                        runProbe(saveFirst: true)
                    }
                    .buttonStyle(CanonSecondaryButtonStyle())
                    .disabled(draft.trimmed.isEmpty)
                }
            }

            if let feedback {
                Text(feedback.text)
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(feedback.tone)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isConfigured ? CanonColor.olive.opacity(0.35) : CanonColor.rust.opacity(0.45))
        )
    }

    private func runProbe(saveFirst: Bool) {
        if saveFirst {
            do {
                try library.saveProviderCredential(provider, value: draft.trimmed)
                draft = ""
            } catch {
                feedback = ("Could not save: \(error.localizedDescription)", CanonColor.rust)
                return
            }
        }
        isProbing = true
        feedback = nil
        Task { @MainActor in
            let key = LitScenesCredentialStore().resolvedCredential(for: provider)
            let outcome = await CredentialProbe().probe(provider, apiKey: key)
            isProbing = false
            feedback = Self.feedbackLine(for: outcome, provider: provider, savedFirst: saveFirst)
        }
    }

    static func feedbackLine(
        for outcome: CredentialProbeOutcome,
        provider: LitScenesProviderCredential,
        savedFirst: Bool
    ) -> (text: String, tone: Color) {
        switch outcome {
        case .valid:
            let prefix = savedFirst ? "Saved — verified" : "Verified"
            return ("\(prefix), \(provider.label) answered.", CanonColor.olive)
        case .invalidKey(let httpStatus):
            let prefix = savedFirst ? "Saved, but " : ""
            let code = httpStatus > 0 ? " (HTTP \(httpStatus))" : ""
            return ("\(prefix)\(provider.label) rejected this key\(code). Check it and save again.", CanonColor.rust)
        case .unreachable:
            let prefix = savedFirst ? "Saved. " : ""
            return ("\(prefix)Couldn't reach \(provider.label) — a network problem, not a key problem.", CanonColor.muted)
        }
    }
}
