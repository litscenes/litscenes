import AppKit
import CryptoKit
import Foundation
import Security
import SwiftUI

struct GoDocument: Sendable {
    let data: Data
    init(_ object: [String: Any]) throws { data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) }
    init(data: Data) { self.data = data }
    var object: [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }
    func string(_ key: String) -> String { object[key] as? String ?? "" }
    func int(_ key: String) -> Int { object[key] as? Int ?? 0 }
    func bool(_ key: String) -> Bool { object[key] as? Bool ?? false }
    func document(_ key: String) -> GoDocument { (try? GoDocument(object[key] as? [String: Any] ?? [:])) ?? GoDocument(data: Data("{}".utf8)) }
    func documents(_ key: String) -> [GoDocument] { (object[key] as? [[String: Any]] ?? []).compactMap { try? GoDocument($0) } }
}

struct GoServiceError: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
}

enum GoConnection {
    static let offerVersion = "go_monthly_v2"
    static var baseURL: URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: "LitScenesGoServiceURL") as? String
        let development = LitScenesReleaseIdentity.current.channel == .development
        let raw = (development ? ProcessInfo.processInfo.environment["LITSCENES_GO_SERVICE_URL"] : nil)
            ?? configured ?? "https://api.litscenes.ai/v1/desktop"
        guard let url = URL(string: raw), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.scheme == "https" || (development && url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")) else {
            return URL(string: "https://api.litscenes.ai/v1/desktop")!
        }
        return url
    }
    static var isStoreBuild: Bool { Bundle.main.object(forInfoDictionaryKey: "LitScenesDistribution") as? String == "app-store" }
    static var isManaged: Bool { UserDefaults.standard.string(forKey: "LitScenesFundingMode") == "go" }
    static let marker = "litscenes-managed-routing"
    static func managedCredential(for provider: LitScenesProviderCredential) -> String? {
        ProviderBilling.source(for: ProviderBilling.defaultTarget(for: provider)) == .go ? marker : nil
    }
    static func selectsManaged(_ request: URLRequest) -> Bool {
        (request.allHTTPHeaderFields ?? [:]).values.contains { $0.contains(marker) }
    }
    static func selectManaged(_ enabled: Bool) {
        UserDefaults.standard.set(enabled ? "go" : "personal", forKey: "LitScenesFundingMode")
        NotificationCenter.default.post(name: .goFundingChanged, object: nil)
    }
}

extension Notification.Name {
    static let goFundingChanged = Notification.Name("LitScenesGoFundingChanged")
    static let goAccountRequested = Notification.Name("LitScenesGoAccountRequested")
}

enum GoVault {
    private static var service: String {
        let scope = SHA256.hash(data: Data(GoConnection.baseURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return (Bundle.main.bundleIdentifier ?? "ai.litscenes.development") + ".go." + scope
    }
    static func read(_ name: String) -> GoDocument? {
        var result: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: name,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return GoDocument(data: data)
    }
    static func save(_ name: String, _ value: GoDocument) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: name]
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value.data] as CFDictionary)
        if updated == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = value.data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw GoServiceError(code: "keychain", message: "Allow LitScenes to save this account securely in Keychain, then try again.")
            }
        } else if updated != errSecSuccess {
            throw GoServiceError(code: "keychain", message: "The account could not be saved to Keychain.")
        }
    }
    static func remove(_ name: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                       kSecAttrAccount as String: name] as CFDictionary)
    }
    static func verifier() -> String { UUID().uuidString + UUID().uuidString }
    static func hash(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
}

enum GoAPI {
    static func call(_ path: String, method: String = "GET", body: GoDocument? = nil, authenticated: Bool = true) async throws -> GoDocument {
        var request = URLRequest(url: GoConnection.baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))))
        request.httpMethod = method
        request.timeoutInterval = 60
        request.httpBody = body?.data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let session = GoVault.read("session") {
            request.setValue("Bearer " + session.string("access_token"), forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw error }
            throw GoServiceError(code: "connection_unavailable", message: error.code == .notConnectedToInternet
                ? "You’re offline. Reconnect to use LitScenes Go. Your saved setup and projects are still here."
                : "We couldn’t connect to LitScenes Go. Try again shortly. You can also choose Self serve and use your own vendors.")
        }
        let result = GoDocument(data: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoServiceError(code: result.string("error"), message: result.string("message").isEmpty
                ? "Go is temporarily unavailable. Check your connection and try again." : result.string("message"))
        }
        return result
    }
    static func upload(_ data: Data, mimeType: String) async throws -> String {
        let prepared = try await call("media", method: "POST", body: GoDocument([
            "mime_type": mimeType, "byte_count": data.count, "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]))
        let direct = !prepared.string("upload_url").isEmpty
        let destination: URL
        if direct {
            guard let url = URL(string: prepared.string("upload_url")), url.scheme == "https",
                  url.user == nil, url.password == nil, url.host?.hasSuffix(".amazonaws.com") == true,
                  url.host?.contains(".s3.") == true || url.host?.contains(".s3-") == true || url.host?.hasSuffix(".s3.amazonaws.com") == true else {
                throw GoServiceError(code: "upload_destination", message: "The service returned an invalid media destination.")
            }
            destination = url
        } else {
            destination = GoConnection.baseURL.appending(path: prepared.string("upload_path").trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }
        var request = URLRequest(url: destination)
        request.httpMethod = "PUT"
        request.timeoutInterval = 300
        if direct {
            for (name, value) in prepared.document("upload_headers").object {
                guard ["content-type", "x-amz-checksum-sha256", "x-amz-server-side-encryption"].contains(name.lowercased()), let text = value as? String else { continue }
                request.setValue(text, forHTTPHeaderField: name)
            }
        } else {
            request.setValue("Bearer " + (GoVault.read("session")?.string("access_token") ?? ""), forHTTPHeaderField: "Authorization")
            request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        }
        let (_, response) = try await GoMediaTransfer.session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw GoServiceError(code: "upload", message: "Media upload was interrupted. Retry to resume your action.")
        }
        if direct {
            let completed = try await call(prepared.string("complete_path"), method: "POST")
            guard completed.bool("ready"), completed.string("reference") == prepared.string("reference") else { throw URLError(.badServerResponse) }
        }
        return prepared.string("reference")
    }
}

@MainActor
final class GoAccountStore: ObservableObject {
    static let shared = GoAccountStore()
    @Published var configuration = GoDocument(data: Data("{}".utf8))
    @Published var account = GoDocument(data: Data("{}".utf8))
    @Published var recentJobs: [GoDocument] = []
    @Published var message = ""
    @Published var connectionIssue = ""
    @Published var busy = false
    @Published var email = ""
    @Published var code = ""
    @Published var awaitingCode = false
    @Published var pendingCheckout = GoVault.read("checkout") != nil
    @Published var fundingManaged = GoConnection.isManaged
    private var sessionRevision = 0
    private var checkedLaunchSetup = false

    var hasPersonalOpenAIKey: Bool {
        let key = LitScenesCredentialStore().resolvedCredentialValue(forKeys: LitScenesProviderCredential.openAI.keyCandidates)
        return !key.isEmpty && key != GoConnection.marker
    }

    // This hint controls onboarding only. Every paid action still requires server authorization.
    var hasConfirmedPlan: Bool {
        guard let session = GoVault.read("session"), !session.string("account_id").isEmpty else { return false }
        return GoVault.read("setup")?.string("account_id") == session.string("account_id")
    }

    func needsSetupOnLaunch() -> Bool {
        guard !checkedLaunchSetup else { return false }
        checkedLaunchSetup = true
        return !hasPersonalOpenAIKey && !hasConfirmedPlan
    }

    private var polling: Task<Void, Never>?
    var isSignedIn: Bool { GoVault.read("session") != nil }
    var hasAccount: Bool { !account.string("account_id").isEmpty }
    var hasConfiguration: Bool { !configuration.string("name").isEmpty }
    var shouldReconnect: Bool { isSignedIn || pendingCheckout || fundingManaged }
    var canPurchase: Bool { configuration.string("offer_version") == GoConnection.offerVersion && configuration.bool(GoConnection.isStoreBuild ? "store_available" : "checkout_available") }

    func refresh() async {
        let revision = sessionRevision
        do {
            configuration = try await GoAPI.call("config", authenticated: false)
            guard revision == sessionRevision else { return }
            if let session = GoVault.read("session"), session.int("expires_at") < Int(Date().timeIntervalSince1970) + 300 {
                let renewed = try await GoAPI.call("auth/refresh", method: "POST",
                    body: GoDocument(["refresh_token": session.string("refresh_token")]), authenticated: false)
                guard revision == sessionRevision else { return }
                try GoVault.save("session", renewed)
            }
            if isSignedIn {
                let updated = try await GoAPI.call("account")
                guard revision == sessionRevision else { return }
                account = updated
                if updated.bool("subscription_active") || ["active", "trialing"].contains(updated.string("subscription_status")) {
                    if let session = GoVault.read("session") {
                        try GoVault.save("setup", GoDocument(["account_id": session.string("account_id")]))
                    }
                } else {
                    GoVault.remove("setup")
                }
                let jobs = try await GoAPI.call("jobs").documents("jobs")
                guard revision == sessionRevision else { return }
                var recovered: [GoDocument] = []
                for job in jobs {
                    let cached = await GoOutputStore.shared.read(job.string("job_id"))
                    recovered.append(cached ?? job)
                }
                guard revision == sessionRevision else { return }
                recentJobs = recovered
            }
            connectionIssue = ""
        } catch {
            guard revision == sessionRevision else { return }
            if let error = error as? GoServiceError, error.code == "connection_unavailable" {
                connectionIssue = error.message
            } else if (error as? URLError)?.code != .cancelled {
                connectionIssue = ""
                message = error.localizedDescription
            }
        }
        fundingManaged = GoConnection.isManaged
        awaitingCode = GoVault.read("email_challenge") != nil
        pendingCheckout = GoVault.read("checkout") != nil
        if pendingCheckout { resumeCheckoutPolling() }
    }

    func choosePersonal() { GoConnection.selectManaged(false); fundingManaged = false }
    func chooseGo() {
        if !GoConnection.isManaged { GoConnection.selectManaged(true) }
        fundingManaged = true
    }

    func purchase(_ sku: String = "go_monthly") async {
        let revision = sessionRevision
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            await refresh()
            guard revision == sessionRevision, connectionIssue.isEmpty else { return }
            guard canPurchase else { throw GoServiceError(code: "unavailable", message: "Go is temporarily unavailable. You can use your own API key or explore first.") }
            if GoConnection.isStoreBuild {
                await GoStorePurchaseController.shared.start(configuration: configuration)
                try await GoStorePurchaseController.shared.purchase(sku, configuration: configuration)
                await refresh()
                return
            }
            let existing = GoVault.read("checkout")
            if let existing, existing.string("sku") != sku {
                throw GoServiceError(code: "pending_checkout", message: "Finish your existing checkout before starting another purchase.")
            }
            let draft = try existing ?? GoDocument(["sku": sku, "verifier": GoVault.verifier(), "request_key": UUID().uuidString])
            try GoVault.save("checkout", draft)
            let result = try await GoAPI.call("checkout", method: "POST", body: GoDocument([
                "sku": sku, "offer_version": GoConnection.offerVersion, "verifier_hash": GoVault.hash(draft.string("verifier")), "request_key": draft.string("request_key")]))
            guard revision == sessionRevision else { return }
            var saved = draft.object
            saved["checkout_id"] = result.string("checkout_id")
            saved["url"] = result.string("url")
            try GoVault.save("checkout", GoDocument(saved))
            pendingCheckout = true
            if let url = URL(string: result.string("url")), url.scheme == "https", url.host == "checkout.stripe.com" {
                NSWorkspace.shared.open(url)
            }
            message = "Finish checkout in your browser. This app connects automatically when payment is confirmed."
            resumeCheckoutPolling()
        } catch { message = error.localizedDescription }
    }

    func cancelCheckout() async {
        guard let pending = GoVault.read("checkout"), !pending.string("checkout_id").isEmpty else {
            GoVault.remove("checkout"); pendingCheckout = false; return
        }
        do {
            let result = try await GoAPI.call("checkout/cancel", method: "POST", body: GoDocument([
                "checkout_id": pending.string("checkout_id"), "verifier": pending.string("verifier")]), authenticated: false)
            if result.string("status") == "complete" { await checkCheckout(); return }
            GoVault.remove("checkout")
            pendingCheckout = false
            message = "Checkout canceled."
        } catch { message = error.localizedDescription }
    }

    func checkCheckout() async {
        guard let pending = GoVault.read("checkout"), !pending.string("checkout_id").isEmpty else { return }
        do {
            let result = try await GoAPI.call("checkout/claim", method: "POST", body: GoDocument([
                "checkout_id": pending.string("checkout_id"), "verifier": pending.string("verifier")]), authenticated: false)
            guard GoVault.read("checkout")?.string("verifier") == pending.string("verifier") else { return }
            if result.string("status") == "complete" {
                try acceptSession(result.document("session"))
                GoVault.remove("checkout")
                pendingCheckout = false
                message = "You’re connected. Your credits are ready."
                await refresh()
                await GoTransport.resumePending()
            } else if result.string("status") == "expired" {
                GoVault.remove("checkout")
                pendingCheckout = false
                message = "Checkout expired. You can start again."
            }
        } catch { message = error.localizedDescription }
    }

    private func resumeCheckoutPolling() {
        guard polling == nil, !GoConnection.isStoreBuild else { return }
        polling = Task { [weak self] in
            for _ in 0..<600 {
                guard !Task.isCancelled, let self, self.pendingCheckout else { break }
                await self.checkCheckout()
                try? await Task.sleep(for: .seconds(3))
            }
            self?.polling = nil
        }
    }

    func acceptSession(_ value: GoDocument, selectGo: Bool = true) throws {
        guard !value.string("access_token").isEmpty, !value.string("account_id").isEmpty else {
            throw GoServiceError(code: "session", message: "Account confirmation is delayed. Try again safely.")
        }
        try GoVault.save("session", value)
        if selectGo { chooseGo() }
    }

    func sendCode() async {
        let revision = sessionRevision
        busy = true
        defer { busy = false }
        do {
            let verifier = GoVault.verifier()
            let result = try await GoAPI.call("auth/email", method: "POST", body: GoDocument([
                "email": email, "verifier_hash": GoVault.hash(verifier), "link_account": isSignedIn]))
            guard revision == sessionRevision else { return }
            try GoVault.save("email_challenge", GoDocument(["challenge_id": result.string("challenge_id"), "verifier": verifier]))
            awaitingCode = true
            message = "Check your email for a six-digit code."
        } catch { message = error.localizedDescription }
    }

    func verifyCode() async {
        guard let challenge = GoVault.read("email_challenge") else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await GoAPI.call("auth/verify", method: "POST", body: GoDocument([
                "challenge_id": challenge.string("challenge_id"), "verifier": challenge.string("verifier"), "code": code]), authenticated: false)
            guard GoVault.read("email_challenge")?.string("verifier") == challenge.string("verifier") else { return }
            try acceptSession(result)
            GoVault.remove("email_challenge")
            awaitingCode = false
            code = ""
            message = "Signed in."
            await refresh()
        } catch { message = error.localizedDescription }
    }

    func cancelRenewal(_ subscription: GoDocument) async {
        guard !busy else { return }
        let date = Date(timeIntervalSince1970: Double(subscription.int("period_end"))).formatted(date: .abbreviated, time: .omitted)
        guard await GoApproval.ask(title: "Cancel subscription at renewal?", message: "Your paid allowance stays available through \(date). Any scheduled plan change will be removed. Your saved projects stay available.", action: "Cancel at renewal") else { return }
        busy = true
        defer { busy = false }
        do {
            let id = subscription.string("subscription_id")
            let key = "cancel_subscription:" + id
            let intent = try GoVault.read(key) ?? GoDocument(["request_key": UUID().uuidString])
            try GoVault.save(key, intent)
            _ = try await GoAPI.call("billing/cancel", method: "POST", body: GoDocument(["subscription_id": id, "request_key": intent.string("request_key")]))
            GoVault.remove(key)
            GoVault.remove("plan_change")
            message = "Subscription canceled at renewal. Your paid allowance remains available through \(date)."
            await refresh()
        } catch { message = error.localizedDescription }
    }

    func changePlan(_ sku: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            if account.string("billing_provider") == "apple" {
                await manageSubscription()
                return
            }
            let pending = GoVault.read("plan_change")
            if let pending, pending.string("account_id") != account.string("account_id") { GoVault.remove("plan_change") }
            let saved = GoVault.read("plan_change")
            if let saved, !saved.string("change_id").isEmpty {
                let result = try await GoAPI.call("billing/changes/confirm", method: "POST", body: GoDocument(["change_id": saved.string("change_id")]))
                try handlePlanChange(result)
                await refresh()
                return
            }
            let preview = try await GoAPI.call("billing/changes/preview", method: "POST", body: GoDocument([
                "sku": sku, "offer_version": GoConnection.offerVersion, "request_key": UUID().uuidString]))
            let currency = preview.string("currency").uppercased()
            let price = (Double(preview.int("amount_due")) / 100).formatted(.currency(code: currency))
            let date = Date(timeIntervalSince1970: Double(preview.int("period_end"))).formatted(date: .abbreviated, time: .omitted)
            let nextPrice = (Double(preview.int("next_price_cents")) / 100).formatted(.currency(code: "USD"))
            let renewal = "Then \(nextPrice)/month for \(preview.int("next_monthly_credits").formatted()) credits, plus applicable tax. Stripe confirms the billing currency. "
            let detail = preview.string("kind") == "upgrade"
                ? "Pay \(price) now, including applicable tax, for \(preview.int("additional_credits")) additional credits through \(date). Your renewal date stays the same. The plan changes only after payment. Currency conversion may change the final amount shown by Stripe."
                : "Your current allowance stays available through \(date). The lower plan starts at renewal; there is no charge now."
            guard await GoApproval.ask(title: "Review plan change", message: renewal + detail, action: preview.string("kind") == "upgrade" ? "Confirm upgrade" : "Change at renewal") else { return }
            try GoVault.save("plan_change", GoDocument(["change_id": preview.string("change_id"), "account_id": account.string("account_id")]))
            let result = try await GoAPI.call("billing/changes/confirm", method: "POST", body: GoDocument(["change_id": preview.string("change_id")]))
            try handlePlanChange(result)
            await refresh()
        } catch {
            if let service = error as? GoServiceError, ["preview_expired", "subscription_changed"].contains(service.code) { GoVault.remove("plan_change") }
            message = error.localizedDescription
        }
    }

    private func handlePlanChange(_ result: GoDocument) throws {
        if ["complete", "scheduled", "canceled"].contains(result.string("status")) {
            GoVault.remove("plan_change")
            message = result.string("status") == "complete" ? "Plan updated. Your additional credits are ready." : result.string("status") == "scheduled" ? "Plan change scheduled for renewal." : "Plan change canceled."
        } else {
            message = "Payment confirmation is pending. Your current plan stays in place. Check the plan change again to recover it safely."
            if let url = URL(string: result.string("payment_url")), url.scheme == "https", ["invoice.stripe.com", "pay.stripe.com"].contains(url.host ?? "") { NSWorkspace.shared.open(url) }
        }
    }

    func manageSubscription(_ provider: String? = nil) async {
        do {
            let payload = try provider.map { try GoDocument(["provider": $0]) }
            let result = try await GoAPI.call("billing/portal", method: "POST", body: payload)
            if let url = URL(string: result.string("url")), url.scheme == "https", ["billing.stripe.com", "apps.apple.com"].contains(url.host ?? "") {
                NSWorkspace.shared.open(url)
            }
        } catch { message = error.localizedDescription }
    }

    func signOut() async {
        sessionRevision += 1
        polling?.cancel()
        polling = nil
        GoVault.remove("checkout")
        GoVault.remove("email_challenge")
        GoVault.remove("plan_change")
        pendingCheckout = false
        awaitingCode = false
        email = ""
        code = ""
        _ = try? await GoAPI.call("auth/logout", method: "POST")
        GoVault.remove("session")
        GoVault.remove("setup")
        choosePersonal()
        account = GoDocument(data: Data("{}".utf8))
        recentJobs = []
    }
}
