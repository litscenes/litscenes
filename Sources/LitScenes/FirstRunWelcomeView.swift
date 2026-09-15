import SwiftUI

/// Legacy welcome-version policy retained for existing preference compatibility.
/// Account setup at launch is decided by GoAccountStore, independently of this tour.
enum FirstRunWelcomeEligibility {
    static let currentVersion = 2

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

/// Optional welcome tour, reopenable from Settings. Launch setup uses the
/// Account & usage modal until a subscription or personal OpenAI key is configured.
struct FirstRunWelcomeView: View {
    @ObservedObject var library: LibraryEngine
    var onCreateProject: () -> Void
    var onOpenAppSettings: () -> Void
    var onDismiss: () -> Void
    @ObservedObject private var go = GoAccountStore.shared
    @State private var showingPersonalKey = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Text("Welcome to LitScenes")
                            .font(CanonType.editorial(30, weight: .semibold))
                        Text("Turn your media into a story worth sharing.")
                            .font(CanonType.editorial(17)).foregroundStyle(CanonColor.muted)
                    }.padding(.top, 24)
                    if go.isSignedIn && go.account.bool("managed_access") {
                        Text("You’re ready. \(go.account.int("available_credits")) credits available.")
                            .font(CanonType.interface(17, weight: .semibold))
                        Button("Create your first project", action: onCreateProject)
                            .buttonStyle(CanonSecondaryButtonStyle())
                        SelfServeOption(library: library, isExpanded: $showingPersonalKey)
                    } else {
                        GoOfferCard(library: library, showPersonalKey: $showingPersonalKey)
                    }
                    if showingPersonalKey {
                        Button("Continue to my project", action: onCreateProject)
                            .buttonStyle(CanonSecondaryButtonStyle())
                    }
                    Button("Already subscribed? Sign in", action: onOpenAppSettings)
                        .buttonStyle(CanonUtilityButtonStyle())
                    Button("Explore first", action: onDismiss)
                        .buttonStyle(CanonUtilityButtonStyle())
                    GoConnectionNotice()
                    if !go.message.isEmpty {
                        Text(go.message).font(CanonType.interface(12)).foregroundStyle(CanonColor.brass)
                    }
                    Text("Your projects stay on your Mac. Open Account & usage anytime to change how you create.")
                        .font(CanonType.interface(11)).foregroundStyle(CanonColor.muted)
                }
                .foregroundStyle(CanonColor.bone)
                .frame(maxWidth: 560).padding(32).frame(maxWidth: .infinity)
            }
            Button(action: onDismiss) { Image(systemName: "xmark").frame(width: 30, height: 30) }
                .buttonStyle(CanonUtilityButtonStyle()).padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanonColor.archiveWell)
        .onChange(of: go.fundingManaged) { _, managed in
            if managed { showingPersonalKey = false }
        }
        .task {
            guard go.shouldReconnect else { return }
            await go.refresh()
            await GoStorePurchaseController.shared.start(configuration: go.configuration)
        }
    }
}

/// One welcome key card: save + probe in a single gesture, with the probe
/// outcome spelled honestly — a rejected key and an unreachable provider
/// are different sentences, never conflated.
struct WelcomeKeyRow: View {
    @ObservedObject var library: LibraryEngine
    let provider: LitScenesProviderCredential
    let description: String

    @State private var draft = ""
    @State private var isProbing = false
    @State private var feedback: (text: String, tone: Color)?

    private var status: CredentialStatus? {
        LitScenesCredentialStore().personalCredentialStatus(for: provider)
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
            let key = LitScenesCredentialStore().personalCredential(for: provider)
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
