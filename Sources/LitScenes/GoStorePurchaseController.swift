import Foundation
import StoreKit

@MainActor
final class GoStorePurchaseController: ObservableObject {
    static let shared = GoStorePurchaseController()
    @Published private(set) var products: [String: Product] = [:]
    @Published var message = ""
    private var updates: Task<Void, Never>?

    func start(configuration: GoDocument) async {
        guard GoConnection.isStoreBuild else { return }
        let identifiers = configuration.document("apple_products").object.values.compactMap { $0 as? String }
        do {
            let loaded = try await Product.products(for: identifiers)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch { message = "App Store pricing is temporarily unavailable." }
        if updates == nil {
            updates = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self else { break }
                    do { try await self.deliver(result, restore: false) }
                    catch { self.message = error.localizedDescription }
                }
            }
        }
        await recoverUnfinished()
    }

    func price(_ sku: String, configuration: GoDocument) -> String? {
        products[configuration.document("apple_products").string(sku)]?.displayPrice
    }

    func purchase(_ sku: String, configuration: GoDocument) async throws {
        let productId = configuration.document("apple_products").string(sku)
        guard let product = products[productId] else {
            throw GoServiceError(code: "store_product", message: "Wait for App Store pricing, then try again.")
        }
        let existing = GoVault.read("checkout")
        if let existing, existing.string("sku") != sku {
            throw GoServiceError(code: "store_pending", message: "Finish or restore your pending purchase first.")
        }
        let draft = try existing ?? GoDocument(["sku": sku, "verifier": GoVault.verifier(), "request_key": UUID().uuidString, "provider": "apple"])
        try GoVault.save("checkout", draft)
        let prepared = try await GoAPI.call("store/prepare", method: "POST", body: GoDocument([
            "sku": sku, "offer_version": GoConnection.offerVersion, "verifier_hash": GoVault.hash(draft.string("verifier")), "request_key": draft.string("request_key")]))
        var saved = draft.object
        saved["checkout_id"] = prepared.string("checkout_id")
        saved["account_id"] = prepared.string("account_id")
        saved["product_id"] = productId
        saved["app_account_token"] = prepared.string("app_account_token")
        try GoVault.save("checkout", GoDocument(saved))
        guard let accountId = UUID(uuidString: prepared.string("app_account_token")) else {
            throw GoServiceError(code: "store_account", message: "The purchase account could not be prepared.")
        }
        switch try await product.purchase(options: [.appAccountToken(accountId)]) {
        case .success(let result): try await deliver(result, restore: false)
        case .pending: message = "Waiting for Apple approval. Credits arrive automatically when the purchase is approved."
        case .userCancelled:
            await GoAccountStore.shared.cancelCheckout()
            message = "Purchase canceled. You can continue exploring."
        @unknown default: message = "Check Restore purchases to confirm this purchase."
        }
    }

    func recoverUnfinished() async {
        for await result in Transaction.unfinished {
            do { try await deliver(result, restore: false) }
            catch { message = error.localizedDescription }
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await recoverUnfinished()
            let configuration = GoAccountStore.shared.configuration
            let knownProducts = Set((Array(configuration.document("apple_products").object.values) + Array(configuration.document("apple_restore_products").object.values)).compactMap { $0 as? String })
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result, knownProducts.contains(transaction.productID) else { continue }
                try await deliver(result, restore: true)
            }
            for await result in Transaction.all {
                guard case .verified(let transaction) = result, knownProducts.contains(transaction.productID) else { continue }
                try await deliver(result, restore: true)
            }
            await GoAccountStore.shared.refresh()
            message = "Purchase history checked. Your remaining prepaid credits stay available after the subscription ends."
        } catch { message = error.localizedDescription }
    }

    private func deliver(_ result: VerificationResult<Transaction>, restore: Bool) async throws {
        guard case .verified(let transaction) = result else {
            throw GoServiceError(code: "store_unverified", message: "Apple could not verify this purchase. It has not been finished; try Restore purchases.")
        }
        let pending = GoVault.read("checkout")
        var payload: [String: Any] = ["signed_transaction": result.jwsRepresentation, "restore": restore || pending == nil]
        if let pending, !restore, pending.string("product_id") == transaction.productID, !transaction.isUpgraded,
           (transaction.expirationDate ?? .distantPast) > Date(), transaction.revocationDate == nil, pending.string("provider") == "apple", pending.string("app_account_token").lowercased() == transaction.appAccountToken?.uuidString.lowercased() {
            payload["checkout_id"] = pending.string("checkout_id")
            payload["verifier"] = pending.string("verifier")
        }
        let reply = try await GoAPI.call("store/verify", method: "POST", body: GoDocument(payload), authenticated: GoVault.read("session") != nil)
        guard reply.bool("acknowledged") else {
            throw GoServiceError(code: "store_delivery", message: "Payment is verified but credit delivery is delayed. Try Restore purchases.")
        }
        let confirmed = payload["checkout_id"] != nil && GoVault.read("checkout")?.string("verifier") == pending?.string("verifier")
        let sameAccount = GoVault.read("session")?.string("account_id") == reply.document("session").string("account_id")
        if restore || confirmed || sameAccount {
            try GoAccountStore.shared.acceptSession(reply.document("session"), selectGo: restore || confirmed)
        }
        await transaction.finish()
        if confirmed { GoVault.remove("checkout") }
        message = "Purchase delivered. Your credits are ready."
        await GoAccountStore.shared.refresh()
    }
}
