import AppKit
import SwiftUI

struct GoOfferCard: View {
    @ObservedObject var library: LibraryEngine
    @Binding var showPersonalKey: Bool
    @ObservedObject private var go = GoAccountStore.shared
    @ObservedObject private var store = GoStorePurchaseController.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose how you create").font(CanonType.editorial(25, weight: .semibold))
            Text("Go includes stories, images, video, narration, and the story graph. No API keys to set up.")
                .font(CanonType.interface(13)).foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            offer("go_monthly", name: "Go", credits: 750, price: "$16.80/month")
            offer("go_plus_monthly", name: "Go Plus", credits: 3500, price: "$68/month")
            Text("Same features. More monthly usage with Plus. See the credit cost before you create. Cancel anytime. Monthly credits expire at renewal; no rollover or automatic overages. Applicable taxes are added at direct checkout.")
                .font(CanonType.interface(11)).foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            if go.hasConfiguration && go.configuration.string("offer_version") != GoConnection.offerVersion {
                Text("Update LitScenes to review the current monthly plans.").font(CanonType.interface(12)).foregroundStyle(CanonColor.brass)
            } else if go.hasConfiguration && !go.canPurchase {
                Text(go.configuration.string("message").isEmpty ? "Payments are temporarily unavailable. Use your own API key or explore first." : go.configuration.string("message"))
                    .font(CanonType.interface(12)).foregroundStyle(CanonColor.brass)
            }
            SelfServeOption(library: library, isExpanded: $showPersonalKey)
            HStack {
                Link("Terms", destination: URL(string: "https://litscenes.ai/terms/")!)
                Link("Privacy", destination: URL(string: "https://litscenes.ai/privacy/")!)
            }.font(CanonType.interface(11))
        }
        .foregroundStyle(CanonColor.bone)
        .padding(20)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(CanonColor.brass.opacity(0.7)))
    }
    private func offer(_ sku: String, name: String, credits: Int, price: String) -> some View {
        let display = GoConnection.isStoreBuild ? store.price(sku, configuration: go.configuration).map { $0 + "/month" } : price
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(name) · \(display ?? "App Store price unavailable")").font(CanonType.interface(16, weight: .semibold))
                Text("\(credits.formatted()) credits each month").font(CanonType.interface(12)).foregroundStyle(CanonColor.muted)
            }
            Spacer()
            Button(go.busy ? "Connecting…" : (GoConnection.isStoreBuild && display == nil ? "View price" : "Choose \(name)")) {
                Task {
                    if GoConnection.isStoreBuild && display == nil {
                        guard !go.busy else { return }
                        go.busy = true
                        await go.refresh()
                        await store.start(configuration: go.configuration)
                        go.busy = false
                    } else {
                        await go.purchase(sku)
                    }
                }
            }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(go.busy || (go.hasConfiguration && (!go.canPurchase || display == nil)))
        }.padding(.vertical, 6)
    }

}

struct SelfServeOption: View {
    @ObservedObject var library: LibraryEngine
    @Binding var isExpanded: Bool
    @ObservedObject private var go = GoAccountStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Self serve: use your own vendors").font(CanonType.interface(15, weight: .semibold))
                    Text("No LitScenes subscription. Pay your vendors directly. Start with one OpenAI API key.")
                        .font(CanonType.interface(12)).foregroundStyle(CanonColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(isExpanded ? "Hide setup" : "Choose Self serve") {
                    isExpanded.toggle()
                    if isExpanded { go.choosePersonal() }
                }.buttonStyle(CanonSecondaryButtonStyle())
            }
            if isExpanded {
                PersonalKeySetupView(library: library)
                if go.hasPersonalOpenAIKey {
                    Text("OpenAI key configured. Usage is billed by OpenAI.")
                        .font(CanonType.interface(12)).foregroundStyle(CanonColor.olive)
                }
                if go.hasConfirmedPlan {
                    Text("Switching vendors does not cancel your subscription. Manage billing above to cancel renewal.")
                        .font(CanonType.interface(11)).foregroundStyle(CanonColor.muted)
                }
            }
        }
    }
}

struct GoConnectionNotice: View {
    @ObservedObject private var go = GoAccountStore.shared
    @State private var retrying = false
    var body: some View {
        if !go.connectionIssue.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(go.connectionIssue).font(CanonType.interface(12)).foregroundStyle(CanonColor.brass)
                Button(retrying ? "Connecting…" : "Try again") {
                    Task {
                        retrying = true
                        await go.refresh()
                        await GoStorePurchaseController.shared.start(configuration: go.configuration)
                        retrying = false
                    }
                }.buttonStyle(CanonUtilityButtonStyle()).disabled(retrying || go.busy)
            }
        }
    }
}

struct GoAccountView: View {
    @ObservedObject var library: LibraryEngine
    @ObservedObject private var go = GoAccountStore.shared
    @ObservedObject private var store = GoStorePurchaseController.shared
    @State private var showSignIn = false
    @State private var requestedProvider = LitScenesProviderCredential(rawValue: UserDefaults.standard.string(forKey: "LitScenesRequestedProvider") ?? "")
    @State private var showPersonalKey = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GoConnectionNotice()
                if go.isSignedIn {
                    if go.hasAccount {
                        balanceCard
                    } else {
                        Text("Your LitScenes account").font(CanonType.interface(16, weight: .semibold))
                        Text("Connect to Go to check your plan and credit balance. Your saved sign-in is still here.")
                            .font(CanonType.interface(12)).foregroundStyle(CanonColor.muted)
                    }
                    if go.hasAccount && !["active", "trialing", "past_due", "unpaid", "incomplete", "paused"].contains(go.account.string("subscription_status")) && !go.account.bool("subscription_active") {
                        GoOfferCard(library: library, showPersonalKey: $showPersonalKey)
                    } else {
                        SelfServeOption(library: library, isExpanded: $showPersonalKey)
                    }
                    if go.account.bool("generation_suspended") {
                        Text("Generation is paused. You can still manage billing, recover outputs, or use your own API key.").font(CanonType.interface(12)).foregroundStyle(CanonColor.brass)
                    }
                    if go.hasAccount && !go.account.bool("email_verified") {
                        Text("Add a recovery email to use your account on another Mac.")
                            .font(CanonType.interface(13, weight: .semibold))
                        signIn
                    }
                    jobs
                } else {
                    GoOfferCard(library: library, showPersonalKey: $showPersonalKey)
                    Button("Already subscribed? Sign in") { showSignIn.toggle() }
                        .buttonStyle(CanonUtilityButtonStyle())
                    if showSignIn { signIn }
                }
                if go.pendingCheckout {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your checkout is waiting").font(CanonType.interface(13, weight: .semibold))
                        Text("You can close this window. Payment connects automatically when you return.")
                            .font(CanonType.interface(12)).foregroundStyle(CanonColor.muted)
                        HStack {
                            Button("Check payment") { Task { await go.checkCheckout() } }
                            Button("Cancel checkout") { Task { await go.cancelCheckout() } }
                            Button("Return to checkout") { Task { await go.purchase(GoVault.read("checkout")?.string("sku") ?? "go_monthly") } }
                        }.buttonStyle(CanonUtilityButtonStyle())
                    }
                }
                if let requestedProvider {
                    WelcomeKeyRow(library: library, provider: requestedProvider,
                        description: requestedProvider == .fal ? "FAL bills video generation directly. Add billing and copy an API key from fal.ai/dashboard/keys." : "ElevenLabs bills narration directly. Create a key with text-to-speech and voices access.")
                    Link("Create a \(requestedProvider.label) API key", destination: URL(string: requestedProvider == .fal ? "https://fal.ai/dashboard/keys" : "https://elevenlabs.io/app/settings/api-keys")!)
                }
                if !go.hasPersonalOpenAIKey && !go.hasConfirmedPlan {
                    Text("Choose a plan or add your OpenAI key to finish setup. You can close Settings to explore; we’ll remind you next launch if setup is unfinished.")
                        .font(CanonType.interface(11)).foregroundStyle(CanonColor.muted)
                }
                if GoConnection.isStoreBuild {
                    Button("Restore purchases") { Task { await store.restore() } }.buttonStyle(CanonUtilityButtonStyle())
                }
                if !go.message.isEmpty { Text(go.message).font(CanonType.interface(12)).foregroundStyle(CanonColor.brass).textSelection(.enabled) }
                if !store.message.isEmpty { Text(store.message).font(CanonType.interface(12)).foregroundStyle(CanonColor.brass) }
            }.padding(20)
        }
        .background(CanonColor.room)
        .onChange(of: go.fundingManaged) { _, managed in
            if managed { showPersonalKey = false }
        }
        .task {
            showPersonalKey = !go.fundingManaged && go.hasPersonalOpenAIKey
            guard go.shouldReconnect || go.hasConfiguration else { return }
            await go.refresh()
            await store.start(configuration: go.configuration)
        }
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(go.fundingManaged ? "LitScenes Go account" : (go.hasPersonalOpenAIKey ? "Self serve · OpenAI key configured" : "Self serve · Add your OpenAI key"))
                    .font(CanonType.interface(16, weight: .semibold))
                Spacer()
                if !go.fundingManaged { Button("Use Go") { go.chooseGo() }.buttonStyle(CanonSecondaryButtonStyle()) }
            }
            HStack(spacing: 30) {
                creditCount(go.account.int("monthly_remaining"), label: "Monthly credits")
                if go.account.int("purchased_remaining") > 0 { creditCount(go.account.int("purchased_remaining"), label: "Previously purchased credits") }
            }
            if go.account.int("renewal_at") > 0 {
                Text("\(go.account.bool("cancel_at_period_end") ? "Monthly allowance ends" : "Monthly allowance renews") \(Date(timeIntervalSince1970: Double(go.account.int("renewal_at"))).formatted(date: .abbreviated, time: .omitted)).")
                    .font(CanonType.interface(12)).foregroundStyle(CanonColor.muted)
            }
            ForEach(go.account.documents("subscriptions"), id: \.data) { subscription in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(subscription.string("sku") == "go_plus_monthly" ? "Go Plus" : "Go") · \(subscription.string("provider") == "apple" ? "App Store" : "Stripe") · \(subscription.string("status"))").font(CanonType.interface(13, weight: .semibold))
                    Button(subscription.string("provider") == "apple" ? "Manage in App Store" : "Manage Stripe billing") {
                        Task { await go.manageSubscription(subscription.string("provider")) }
                    }.buttonStyle(CanonUtilityButtonStyle())
                    if subscription.string("provider") == "stripe", ["active", "past_due", "unpaid", "paused"].contains(subscription.string("status")), !subscription.bool("cancel_at_period_end") {
                        Button("Cancel at renewal") { Task { await go.cancelRenewal(subscription) } }.buttonStyle(CanonUtilityButtonStyle()).disabled(go.busy)
                    }
                    if !subscription.string("next_sku").isEmpty {
                        Text("Plan change scheduled for renewal.").font(CanonType.interface(12))
                    } else if subscription.string("status") == "active" && subscription.string("provider") == "stripe" && go.account.documents("subscriptions").filter({ $0.string("status") != "expired" }).count == 1 {
                        Button(subscription.string("sku") == "go_plus_monthly" ? "Switch to Go at renewal" : "Upgrade to Go Plus") {
                            Task { await go.changePlan(subscription.string("sku") == "go_plus_monthly" ? "go_monthly" : "go_plus_monthly") }
                        }.buttonStyle(CanonSecondaryButtonStyle()).disabled(go.busy || (subscription.string("sku") != "go_plus_monthly" && go.account.bool("generation_suspended")))
                    }
                }
            }
            if GoVault.read("plan_change") != nil {
                Button("Check pending plan change") { Task { await go.changePlan("go_plus_monthly") } }.disabled(go.busy)
            }
            if go.account.documents("subscriptions").filter({ $0.string("status") != "expired" }).count > 1 {
                Text("More than one subscription is active. Manage or cancel one before changing plans.").font(CanonType.interface(12)).foregroundStyle(CanonColor.brass)
            }
            Text("At your limit? Upgrade, wait for renewal, or use your own API key.").font(CanonType.interface(11)).foregroundStyle(CanonColor.muted)
            HStack {
                Button("Manage subscription") { Task { await go.manageSubscription() } }
                Button("Refresh balance") { Task { await go.refresh() } }
                Spacer()
                Button("Sign out") { Task { await go.signOut() } }
            }.buttonStyle(CanonUtilityButtonStyle())
            Text("This balance is for LitScenes Desktop. SMS and mobile app credits are separate.")
                .font(CanonType.interface(11)).foregroundStyle(CanonColor.muted)
        }.padding(16).background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 10))
    }

    private func creditCount(_ count: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(count.formatted()).font(CanonType.editorial(32, weight: .semibold)).foregroundStyle(CanonColor.bone)
            Text(label).font(CanonType.interface(11)).foregroundStyle(CanonColor.muted)
        }
    }

    private var signIn: some View {
        VStack(alignment: .leading, spacing: 8) {
            if go.awaitingCode {
                HStack {
                    TextField("Six-digit email code", text: $go.code).textFieldStyle(.roundedBorder)
                    Button("Sign in") { Task { await go.verifyCode() } }.disabled(go.busy || go.code.count != 6)
                }
                Button("Send a new code") { Task { await go.sendCode() } }.disabled(go.busy || go.email.isEmpty)
            } else {
                Text("Use the email from checkout. We’ll send a sign-in code; there’s no password.")
                    .font(CanonType.interface(12)).foregroundStyle(CanonColor.muted)
                HStack {
                    TextField("Email address", text: $go.email).textFieldStyle(.roundedBorder)
                    Button("Send code") { Task { await go.sendCode() } }.disabled(go.busy || !go.email.contains("@"))
                }
            }
        }.buttonStyle(CanonSecondaryButtonStyle())
    }

    private var jobs: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !go.recentJobs.isEmpty {
                Text("Recent creations").font(CanonType.interface(14, weight: .semibold))
                ForEach(go.recentJobs, id: \.data) { job in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(job.string("operation").replacingOccurrences(of: "_", with: " ").capitalized)
                            Spacer()
                            Text(job.string("status").capitalized)
                            Text("\(job.int(job.bool("settled") ? "charged_credits" : "maximum_credits")) credits\(job.bool("settled") ? "" : " reserved")")
                        }.font(CanonType.interface(12))
                        if job.bool("artifacts_expired") { Text("Server copy expired. Your saved project files are unchanged.").font(CanonType.interface(11)).foregroundStyle(CanonColor.muted) }
                        if !job.string("message").isEmpty { Text(job.string("message")).font(CanonType.interface(11)).foregroundStyle(CanonColor.muted) }
                        HStack {
                            ForEach(job.documents("artifacts"), id: \.data) { artifact in
                                Button("Save recovered output") { Task { await save(artifact) } }
                            }
                            if job.string("status") == "uncertain" {
                                Button("Recover status") { Task { await recover(job) } }
                            } else if ["queued", "running", "submitted"].contains(job.string("status")) {
                                Button("Cancel action") { Task { await cancel(job) } }
                            }
                        }.buttonStyle(CanonUtilityButtonStyle())
                    }.padding(12).background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func recover(_ job: GoDocument) async {
        do { _ = try await GoAPI.call("jobs/\(job.string("job_id"))/recover", method: "POST"); await go.refresh() }
        catch { go.message = error.localizedDescription }
    }
    private func cancel(_ job: GoDocument) async {
        do { _ = try await GoAPI.call("jobs/\(job.string("job_id"))/cancel", method: "POST"); await go.refresh() }
        catch { go.message = error.localizedDescription }
    }
    private func save(_ artifact: GoDocument) async {
        let panel = NSSavePanel()
        let suffix = artifact.string("mime_type").contains("video") ? "mp4" : artifact.string("mime_type").contains("audio") ? "mp3" : "png"
        panel.nameFieldStringValue = "LitScenes-\(artifact.string("media_id")).\(suffix)"
        guard await panel.begin() == .OK, let destination = panel.url else { return }
        do {
            let data = try await GoOutputStore.shared.data(artifact)
            try data.write(to: destination, options: .atomic)
            go.message = "Recovered output saved."
        } catch { go.message = "The output could not be recovered. Refresh and try again." }
    }
}

struct PersonalKeySetupView: View {
    @ObservedObject var library: LibraryEngine
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start with one OpenAI API key").font(CanonType.interface(16, weight: .semibold))
            Text("Add billing to your OpenAI API account, create a key, then paste it below. OpenAI bills your usage directly; a ChatGPT subscription does not include API usage.")
                .font(CanonType.interface(12)).foregroundStyle(CanonColor.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Link("1. Set up API billing", destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
                Link("2. Create an API key", destination: URL(string: "https://platform.openai.com/api-keys")!)
            }.font(CanonType.interface(12))
            WelcomeKeyRow(library: library, provider: .openAI, description: "This runs media analysis, stories, and images. Save & Test checks the connection without generating anything.")
            Text("We’ll ask for a video or narration key when you use those features. Importing media, browsing projects, local editing, and exporting your files stay available without a subscription.")
                .font(CanonType.interface(11)).foregroundStyle(CanonColor.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GoLifecycleModifier: ViewModifier {
    @ObservedObject var library: LibraryEngine
    @Binding var showingAccount: Bool
    func body(content: Content) -> some View {
        content
            .task {
                guard GoAccountStore.shared.shouldReconnect else { return }
                await GoAccountStore.shared.refresh()
                await GoStorePurchaseController.shared.start(configuration: GoAccountStore.shared.configuration)
                await GoTransport.resumePending()
            }
            .onReceive(NotificationCenter.default.publisher(for: .goAccountRequested)) { _ in showingAccount = true }
            .onReceive(NotificationCenter.default.publisher(for: .goFundingChanged)) { _ in
                library.reloadProviderCredentials()
                library.reloadRenderStacks()
                Task { await GoTransport.resumePending() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                Task {
                    guard GoAccountStore.shared.shouldReconnect else { return }
                    await GoAccountStore.shared.refresh()
                    await GoStorePurchaseController.shared.recoverUnfinished()
                    await GoTransport.resumePending()
                }
            }
    }
}

struct GoProviderSetupHint: View {
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
                GoProviderKeySetup(provider: provider)
            }
        }
    }
}

private struct GoProviderKeySetup: View {
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
            case .invalidKey: message = "The provider rejected this key. Check it and try again."
            case .unreachable: message = "Key saved, but the provider could not be reached. Try again."
            }
            NotificationCenter.default.post(name: .goFundingChanged, object: nil)
        } catch { message = error.localizedDescription }
    }
}

struct GoUpgradeBanner: View {
    @AppStorage("LitScenesGoOfferDismissed") private var dismissed = false
    @ObservedObject private var go = GoAccountStore.shared
    var onOpenAccount: () -> Void
    var body: some View {
        if !dismissed && !go.fundingManaged {
            HStack(spacing: 12) {
                Text("Create without API keys. LitScenes Go starts with 750 credits each month.")
                    .font(CanonType.interface(11)).foregroundStyle(CanonColor.muted)
                Button("Explore Go") { onOpenAccount() }.buttonStyle(CanonUtilityButtonStyle())
                Spacer()
                Button { dismissed = true } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Dismiss Go offer")
            }.padding(.horizontal, 18).padding(.vertical, 8).background(CanonColor.sidebar)
        }
    }
}
