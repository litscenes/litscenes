import AppKit
import Foundation
import OSLog
import SQLite3

struct CivitAIModelCard: Identifiable, Sendable {
    var id: Int
    var name: String
    var creator: String
    var type: String
    var tags: [String]
    var description: String
    var licenseSummary: String
    var supportsGeneration: Bool
    var versions: [CivitAIResource]
    var previews: [CivitAIPreview]

    init(_ json: [String: Any]) {
        id = json["id"] as? Int ?? 0
        name = json["name"] as? String ?? "Untitled model"
        creator = (json["creator"] as? [String: Any])?["username"] as? String ?? ""
        type = json["type"] as? String ?? ""
        tags = json["tags"] as? [String] ?? []
        description = (json["description"] as? String ?? "").replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let commercial = json["allowCommercialUse"].map { String(describing: $0) } ?? "See model page"
        licenseSummary = "Commercial use: " + commercial + ((json["allowNoCredit"] as? Bool == false) ? " · Attribution required" : "")
        supportsGeneration = json["supportsGeneration"] as? Bool ?? false
        let modelId = id, modelName = name, modelType = type
        let entries = json["modelVersions"] as? [[String: Any]] ?? []
        versions = entries.map {
            CivitAIResource(id: $0["id"] as? Int ?? 0, modelId: modelId, name: modelName,
                versionName: $0["name"] as? String ?? "", baseModel: $0["baseModel"] as? String ?? "",
                type: modelType, air: $0["air"] as? String ?? "", trainedWords: $0["trainedWords"] as? [String] ?? [])
        }
        previews = entries.flatMap { $0["images"] as? [[String: Any]] ?? [] }.compactMap(CivitAIPreview.init)
    }
}

struct CivitAIPreview: Identifiable, Sendable {
    var url: URL
    var isVideo: Bool
    var isMature: Bool
    var id: String { url.absoluteString }
    init?(_ json: [String: Any]) {
        guard let text = json["url"] as? String, let url = URL(string: text), url.scheme == "https",
              url.host == "image.civitai.com", URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                .contains(where: { ["token", "signature", "key"].contains($0.name.lowercased()) }) != true else { return nil }
        self.url = url
        isMature = (json["nsfwLevel"] as? Int).map { $0 > 1 }
            ?? (json["nsfw"] as? String).map { $0.lowercased() != "none" } ?? true
        isVideo = (json["type"] as? String) == "video" || url.pathExtension == "mp4"
    }
}

struct CivitAISearch: Equatable, Sendable {
    var query = ""
    var tag = ""
    var creator = ""
    var type = "Checkpoint"
    var baseModel = ""
    var sort = "Most Downloaded"
    var favorites = false
    var mature = true
    var generatable = true
}

actor CivitAICatalogClient {
    static let shared = CivitAICatalogClient()
    private let session = URLSession(configuration: .ephemeral)
    private let logger = Logger(subsystem: "com.litscenes.desktop", category: "civitai_catalog")

    private func get(_ path: String, query: [URLQueryItem] = [], orchestration: Bool = false) async throws -> [String: Any] {
        let key = LitScenesCredentialStore().personalCredential(for: .civitai)
        guard !key.isEmpty else { throw ScreenGraphError.credentials("Add your Civitai key in Advanced providers.") }
        var url = URLComponents(string: orchestration ? "https://orchestration.civitai.com" : "https://civitai.com")!
        url.path = path; url.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: url.url!); request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let requestId = UUID().uuidString
        let started = Date()
        var statusCode = 0
        var succeeded = false
        logger.info("[civitai_catalog] starting request_id=\(requestId, privacy: .public)")
        defer {
            let duration = Int(Date().timeIntervalSince(started) * 1000)
            logger.info("[civitai_catalog] \(succeeded ? "completed" : "error", privacy: .public) request_id=\(requestId, privacy: .public) duration_ms=\(duration) status_code=\(statusCode)")
        }
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        statusCode = status
        guard (200..<300).contains(status) else {
            let message: String
            switch status {
            case 401, 403: message = "Civitai denied access. Check your key and account access in Advanced providers."
            case 429: message = "Civitai is rate limiting requests. Wait a moment, then Retry."
            case 404: message = "This Civitai resource is no longer available."
            default: message = "Civitai could not load this request (HTTP \(status)). Retry."
            }
            throw ScreenGraphError.capture(message)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScreenGraphError.capture("Civitai returned an unreadable response.") }
        succeeded = true
        return json
    }
    func search(_ filter: CivitAISearch, cursor: String? = nil) async throws -> (items: [CivitAIModelCard], cursor: String?) {
        var pairs = ["limit": "30", "sort": filter.sort, "nsfw": String(filter.mature), "primaryFileOnly": "true"]
        for (key, value) in [("query", filter.query), ("tag", filter.tag), ("username", filter.creator), ("types", filter.type), ("baseModels", filter.baseModel)] where !value.trimmed.isEmpty { pairs[key] = value.trimmed }
        if filter.favorites { pairs["favorites"] = "true" }
        if filter.generatable { pairs["supportsGeneration"] = "true" }
        if let cursor { pairs["cursor"] = cursor }
        let json = try await get("/api/v1/models", query: pairs.map { URLQueryItem(name: $0.key, value: $0.value) })
        let metadata = json["metadata"] as? [String: Any] ?? [:]
        let next = (metadata["nextCursor"] as? String) ?? (metadata["nextCursor"] as? NSNumber)?.stringValue
        let cards = (json["items"] as? [[String: Any]] ?? []).map { item in
            var card = CivitAIModelCard(item)
            if !filter.mature { card.previews.removeAll { $0.isMature } }
            return card
        }
        return (cards, next)
    }
    func version(_ selected: CivitAIResource, mature: Bool) async throws -> (resource: CivitAIResource, canGenerate: Bool, previews: [CivitAIPreview], reason: String) {
        let json = try await get("/api/v1/model-versions/\(selected.id)", query: [.init(name: "nsfw", value: String(mature))])
        let mini = try await get("/api/v1/model-versions/mini/\(selected.id)")
        var resource = selected
        resource.air = json["air"] as? String ?? mini["air"] as? String ?? ""
        resource.baseModel = json["baseModel"] as? String ?? selected.baseModel
        resource.trainedWords = json["trainedWords"] as? [String] ?? []
        let canGenerate = mini["canGenerate"] as? Bool == true && !resource.air.isEmpty
        var reason = canGenerate ? ((mini["additionalResourceCharge"] as? Bool == true) ? "Additional resource fees apply; included in your quote." : "Available to your Civitai account") : "This version is not available for generation with your account."
        if !resource.air.isEmpty, let info = try? await get("/v2/resources/" + resource.air, orchestration: true) {
            if let status = (info["availability"] as? [String: Any])?["status"] as? String { reason += " · Resource " + status }
            if info["hasNSFWContentRestriction"] as? Bool == true || info["hasMatureContentRestriction"] as? Bool == true {
                reason += " · This resource restricts mature generation"
            }
        }
        return (resource, canGenerate, (json["images"] as? [[String: Any]] ?? []).compactMap(CivitAIPreview.init).filter { mature || !$0.isMature }, reason)
    }
    func serviceStatuses(kind: CivitAIMediaKind) async throws -> [CivitAIProfile: String] {
        let json = try await get("/v2/services", query: [.init(name: "category", value: kind.rawValue), .init(name: "limit", value: "100")], orchestration: true)
        var result: [CivitAIProfile: String] = [:]
        for item in json["items"] as? [[String: Any]] ?? [] {
            let p = item["parameters"] as? [String: String] ?? [:]
            for profile in CivitAIProfile.allCases where profile.kind == kind {
                let matches: Bool
                switch profile {
                case .sd1, .sdxl: matches = p["ecosystem"] == profile.rawValue && p["engine"] == "sdcpp"
                case .klein4b, .klein9b: matches = p["engine"] == "flux2" && p["model"] == "klein"
                case .wanImage27: matches = p["engine"] == "wan" && p["version"] == "v2.7"
                case .wanVideo22: matches = p["engine"] == "wan" && p["version"] == "v2.2" && p["provider"] == "comfy"
                case .wanVideo25: matches = p["version"] == "v2.5" && p["operation"] == "image-to-video"
                case .wanVideo27: matches = p["version"] == "v2.7" && p["operation"] == "image-to-video"
                }
                if matches { result[profile] = item["status"] as? String ?? "unknown" }
            }
        }
        return result
    }

    func verify(_ recipe: CivitAIRecipe) async throws {
        if let message = recipe.validationError { throw ScreenGraphError.capture(message) }
        let resources = recipe.checkpoint.map { [$0] } ?? []
        for resource in resources + recipe.loras.map(\.resource) {
            let mini = try await get("/api/v1/model-versions/mini/\(resource.id)")
            guard mini["canGenerate"] as? Bool == true, mini["air"] as? String == resource.air else {
                throw ScreenGraphError.capture("\(resource.name) · \(resource.versionName) is no longer available to this account. Review the recipe.") }
        }
    }
}

struct CivitAIQuote: Codable, Hashable, Sendable {
    var buzz: Int
    var isCap: Bool
    var currencies: [String]
    var label: String { "\(isCap ? "Up to" : "Estimated") \(buzz) Buzz" }
    init(json: [String: Any]) throws {
        guard let cost = json["cost"] as? [String: Any], let total = cost["total"] as? Int, total >= 0 else {
            throw ScreenGraphError.capture("Civitai did not return a complete quote. No generation was submitted.") }
        if (json["transactions"] as? [String: Any])?["insufficientBuzz"] as? Bool == true { throw ScreenGraphError.capture("Insufficient Civitai Buzz for this recipe.") }
        buzz = total; isCap = cost["variable"] as? Bool ?? false
        currencies = json["currencies"] as? [String] ?? []
    }
}

struct CivitAIWorkflowOutput {
    var data: Data
    var jobId: String
    var traceId: String
    var quote: CivitAIQuote?
}

/// Exact provider-bound payloads are quoted before the only paid POST.
struct CivitAIWorkflowClient {
    static let workflows = URL(string: "https://orchestration.civitai.com/v2/consumer/workflows")!
    var credentialStore: LitScenesCredentialResolving = LitScenesCredentialStore()

    func run(payload original: [String: Any], recipe: CivitAIRecipe, metadata source: InferenceTraceRequestMetadata,
             onSubmitted: (@MainActor (String, String) async -> Void)? = nil, preferenceRecipe: CivitAIRecipe? = nil) async throws -> CivitAIWorkflowOutput {
        let key = credentialStore.personalCredential(for: .civitai)
        guard !key.isEmpty else { throw ScreenGraphError.credentials("Add your personal Civitai key.") }
        var payload = original
        let externalId = "litscenes-" + shortHash(source.projectId + ":" + source.runId + ":" + source.artifactId, length: 40)
        payload["externalId"] = externalId
        var metadata = source
        metadata.provider = "civitai"; metadata.model = recipe.modelId
        metadata.captureRequestBody = false; metadata.captureResponseBody = false
        metadata.requestTextJSON = inferenceTraceJSONString(redactedCivitAITracePayload(payload).merging([
            "recipe": recipe.wireValue, "operator_context": source.requestTextJSON, "billing_source": "personal"
        ]) { _, new in new })
        let fingerprint = sha256Hex(try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
        var safe = (try? JSONSerialization.jsonObject(with: Data(metadata.requestTextJSON.utf8))) as? [String: Any] ?? [:]
        safe["request_fingerprint"] = fingerprint
        metadata.requestTextJSON = inferenceTraceJSONString(safe)
        var jobId = "", parentId = source.parentTraceId
        var quote: CivitAIQuote?
        do {
            if let saved = try await InferenceTraceStore.shared.civitaiSubmission(externalId: externalId) {
                guard saved.fingerprint == fingerprint else { throw ScreenGraphError.capture("The saved Civitai request differs from this draft. Restore its recipe or create a new take.") }
                guard !saved.jobId.isEmpty else { throw ScreenGraphError.capture("A Civitai submission has an unresolved outcome. Check Traces before starting another take.") }
                jobId = saved.jobId; parentId = saved.traceId
            } else {
                try await CivitAICatalogClient.shared.verify(recipe)
                var quotePayload = payload
                quotePayload.removeValue(forKey: "externalId")
                let priced = try await send(url: Self.workflows, method: "POST", payload: quotePayload, key: key, metadata: metadata, stage: "catalog_quote", whatif: true)
                let proposed = try CivitAIQuote(json: priced.json)
                quote = proposed
                try Task.checkCancellation()
                guard await CivitAIPriceConfirmation.confirm(recipe: recipe, quote: proposed) else { throw CancellationError() }
                try Task.checkCancellation()
                guard credentialStore.personalCredential(for: .civitai) == key else { throw ScreenGraphError.credentials("Civitai credentials changed. Review this render again.") }
                CivitAIPreferences.remember(recipe, preference: preferenceRecipe)
                metadata.parentTraceId = priced.traceId
                let submitted = try await send(url: Self.workflows, method: "POST", payload: payload, key: key, metadata: metadata, stage: "catalog_submit")
                jobId = submitted.json["id"] as? String ?? ""
                parentId = submitted.traceId
                guard !jobId.isEmpty else { throw ScreenGraphError.capture("Civitai submission returned no workflow ID. Inspect Traces before retrying.") }
            }
            await onSubmitted?(jobId, parentId)
            let started = Date()
            var delay: UInt64 = 4
            while true {
                try Task.checkCancellation()
                metadata.parentTraceId = parentId
                let result = try await send(url: Self.workflows.appendingPathComponent(jobId), method: "GET", key: key, metadata: metadata, stage: "catalog_poll")
                parentId = result.traceId
                let status = (result.json["status"] as? String ?? "").lowercased()
                if status == "succeeded" {
                    guard let url = outputURL(result.json, kind: recipe.profile.kind) else { throw ScreenGraphError.capture("Civitai completed without a downloadable output. Check the saved workflow.") }
                    var downloadMetadata = metadata
                    downloadMetadata.operation = "catalog_download"; downloadMetadata.workflowStep = "civitai_catalog_download"
                    downloadMetadata.parentTraceId = parentId; downloadMetadata.apiFamily = "media_transfer"
                    downloadMetadata.requestTextJSON = inferenceTraceJSONString(["workflow_id": jobId])
                    var recorded = URLRequest(url: Self.workflows.appendingPathComponent(jobId).appendingPathComponent("output"))
                    recorded.httpMethod = "GET"
                    let downloaded = try await TracedHTTPTransport.send(request: URLRequest(url: url), recordedRequest: recorded, metadata: downloadMetadata)
                    guard let http = downloaded.response, (200..<300).contains(http.statusCode) else { throw ScreenGraphError.capture("Civitai output download failed. Retry recovery of the existing workflow.") }
                    await InferenceTraceStore.shared.enrichContext(traceId: downloaded.traceId,
                        responseTextJSON: inferenceTraceJSONString(["workflow_id": jobId, "sha256": sha256Hex(downloaded.data), "byte_count": downloaded.data.count]))
                    return CivitAIWorkflowOutput(data: downloaded.data, jobId: jobId, traceId: downloaded.traceId, quote: (try? CivitAIQuote(json: result.json)) ?? quote)
                }
                if ["failed", "canceled", "cancelled", "expired", "rejected"].contains(status) {
                    throw ScreenGraphError.capture("Civitai workflow \(jobId) \(status). \(civitaiFailureSummary(from: redactedCivitAITracePayload(result.json)))") }
                guard Date().timeIntervalSince(started) < 1800 else { throw ScreenGraphError.capture("Civitai is still processing. The workflow ID is saved; retry recovery without submitting again.") }
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 30)
            }
        } catch {
            var event = metadata
            event.operation = Task.isCancelled || error is CancellationError ? "catalog_canceled" : "catalog_failed"
            event.workflowStep = event.operation; event.parentTraceId = parentId
            event.responseTextJSON = inferenceTraceJSONString(["workflow_id": jobId, "status": event.operation,
                "error": WorkflowPrivacy.text(error.localizedDescription), "remote_cancel_requested": false])
            _ = await InferenceTraceStore.shared.record(request: URLRequest(url: Self.workflows), metadata: event,
                response: nil, responseBody: nil, latencyMs: 0, error: error)
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw CivitAIWorkflowFailure(jobId: jobId, traceId: parentId, message: error.localizedDescription)
        }
    }

    private func send(url: URL, method: String, payload: [String: Any]? = nil, key: String,
                      metadata: InferenceTraceRequestMetadata, stage: String, whatif: Bool = false) async throws -> (json: [String: Any], traceId: String) {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "hideMatureContent", value: "false")]
        if whatif { components.queryItems?.append(.init(name: "whatif", value: "true")) }
        var request = URLRequest(url: components.url!); request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let payload { request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) }
        var trace = metadata; trace.operation = stage; trace.workflowStep = "civitai_" + stage
        if whatif {
            trace.apiFamily = "pricing"
            var safe = (try? JSONSerialization.jsonObject(with: Data(trace.requestTextJSON.utf8))) as? [String: Any] ?? [:]
            safe.removeValue(forKey: "externalId")
            if let body = request.httpBody { safe["request_fingerprint"] = sha256Hex(body) }
            trace.requestTextJSON = inferenceTraceJSONString(safe)
        }
        let result = try await TracedHTTPTransport.send(request: request, metadata: trace)
        let json = (try? JSONSerialization.jsonObject(with: result.data)) as? [String: Any] ?? [:]
        await InferenceTraceStore.shared.enrichContext(traceId: result.traceId, responseTextJSON: inferenceTraceJSONString(redactedCivitAITracePayload(json)))
        if let id = json["id"] as? String { await InferenceTraceStore.shared.enrich(traceId: result.traceId, providerRequestId: id) }
        guard let http = result.response, (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture("Civitai \(stage) failed (HTTP \(result.response?.statusCode ?? 0)). \(civitaiFailureSummary(from: redactedCivitAITracePayload(json)))") }
        return (json, result.traceId)
    }

    private func outputURL(_ workflow: [String: Any], kind: CivitAIMediaKind) -> URL? {
        for step in workflow["steps"] as? [[String: Any]] ?? [] where (step["status"] as? String)?.lowercased() == "succeeded" {
            guard let output = step["output"] as? [String: Any] else { continue }
            let blobs: [[String: Any]] = kind == .image ? (output["images"] as? [[String: Any]] ?? []) : (output["video"] as? [String: Any]).map { [$0] } ?? []
            for blob in blobs {
                if let text = blob["url"] as? String, let url = URL(string: text), url.scheme == "https" { return url }
            }
        }
        return nil
    }
}

@MainActor
enum CivitAIPriceConfirmation {
    private static var presenting = false

    static func confirm(recipe: CivitAIRecipe, quote: CivitAIQuote) async -> Bool {
        // Batch renders review one price at a time; cancellation also dismisses its sheet.
        while presenting {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
        }
        guard !Task.isCancelled, let window = NSApp.keyWindow ?? NSApp.mainWindow else { return false }
        presenting = true
        defer { presenting = false }
        let alert = NSAlert()
        alert.messageText = "Render with Civitai?"
        alert.informativeText = "\(recipe.label)\n\(quote.label), including resource fees.\n\(recipe.allowMatureContent ? "Mature generation · Yellow Buzz" : "SFW generation · available Buzz balances")\nCharged to your personal Civitai account."
        alert.addButton(withTitle: "Render · \(quote.buzz) Buzz")
        alert.addButton(withTitle: "Cancel")
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response == .alertFirstButtonReturn)
                }
                if Task.isCancelled { window.endSheet(alert.window, returnCode: .cancel) }
            }
        } onCancel: {
            Task { @MainActor in window.endSheet(alert.window, returnCode: .cancel) }
        }
    }
}

extension InferenceTraceStore {
    /// Recovery uses the canonical trace ledger; unknown acceptance never becomes a second spend.
    func civitaiSubmission(externalId: String) throws -> (jobId: String, traceId: String, fingerprint: String)? {
        try ensureReady()
        let sql = "SELECT provider_request_id, trace_id, response_text_json, json_extract(request_text_json, '$.request_fingerprint') FROM inference_calls WHERE provider = 'civitai' AND operation IN ('catalog_submit', 'catalog_submit.request_prepared') AND json_extract(request_text_json, '$.externalId') = ? ORDER BY created_at DESC LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else { throw ScreenGraphError.capture("Could not check Civitai submission history.") }
        defer { sqlite3_finalize(statement) }
        _ = externalId.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        func string(_ index: Int32) -> String { sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "" }
        let response = (try? JSONSerialization.jsonObject(with: Data(string(2).utf8))) as? [String: Any]
        return (response?["id"] as? String ?? string(0), string(1), string(3))
    }
}

func civitaiFailureSummary(from body: [String: Any]) -> String {
    var messages: [String] = []
    if let message = body["message"] as? String { messages.append(message) }
    if let error = body["error"] as? String { messages.append(error) }
    if let error = body["error"] as? [String: Any] { messages.append(civitaiFailureSummary(from: error)) }
    if let errors = body["errors"] as? [String] { messages += errors }
    for step in (body["steps"] as? [[String: Any]] ?? []).prefix(5) {
        if let error = step["error"] as? [String: Any] { messages.append(civitaiFailureSummary(from: error)) }
        if let output = step["output"] as? [String: Any] { messages += output["errors"] as? [String] ?? [] }
    }
    return WorkflowPrivacy.text(messages.filter { !$0.isEmpty }.joined(separator: "; "))
}
