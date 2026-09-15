import AppKit
import Foundation

actor GoIntentStore {
    static let shared = GoIntentStore()
    private var directory: URL { litScenesApplicationSupportDirectory().appending(path: "go-actions", directoryHint: .isDirectory) }
    func read(_ key: String) -> GoDocument? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(key + ".json")) else { return nil }
        return GoDocument(data: data)
    }
    func save(_ key: String, _ value: GoDocument) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(key + ".json")
        try value.data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func acknowledge(_ jobId: String) throws {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            guard let data = try? Data(contentsOf: file) else { continue }
            let intent = GoDocument(data: data)
            guard intent.string("job_id") == jobId else { continue }
            var delivered = intent.object
            delivered["delivered"] = true
            try save(intent.string("key"), GoDocument(delivered))
        }
    }
    func pending() -> [GoDocument] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { try? Data(contentsOf: $0) }.map(GoDocument.init(data:)).filter { $0.string("job_id").isEmpty && $0.bool("approved") }
    }
}

@MainActor
enum GoApproval {
    static func ask(title: String, message: String, action: String) async -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        guard let window = NSApp.keyWindow else { return alert.runModal() == .alertFirstButtonReturn }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in continuation.resume(returning: response == .alertFirstButtonReturn) }
        }
    }

    static func requireAccount() async throws {
        guard GoVault.read("session") == nil else { return }
        NotificationCenter.default.post(name: .goAccountRequested, object: nil)
        throw GoServiceError(code: "sign_in", message: "Choose Go now or sign in in Account & usage, then continue this action.")
    }

    static func approve(_ quote: GoDocument) async throws {
        let credits = quote.int("maximum_credits")
        guard credits > 0 else { return }
        let allowed = await ask(title: "Create with LitScenes Go?",
            message: "\(quote.string("operation").replacingOccurrences(of: "_", with: " ").capitalized) · \(quote.string("model"))\nUp to \(credits) credits. Only completed provider usage is charged; unused credits return to your balance. Your reference media and outputs are recoverable for seven days.", action: "Create · up to \(credits) credits")
        guard allowed else { throw CancellationError() }
    }

    static func waitForCredits(_ maximum: Int) async throws {
        await GoAccountStore.shared.refresh()
        if GoAccountStore.shared.account.int("available_credits") >= maximum { return }
        guard await ask(title: "Choose how to continue", message: "This action needs up to \(maximum) credits. Upgrade your monthly plan, wait for renewal, or use your own API key. Its approved prompt and settings will wait.", action: "View account & usage") else { throw CancellationError() }
        NotificationCenter.default.post(name: .goAccountRequested, object: nil)
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(3))
            await GoAccountStore.shared.refresh()
            if GoAccountStore.shared.account.int("available_credits") >= maximum { return }

        }
    }
}

enum GoTransport {
    static func send(_ request: URLRequest, metadata: InferenceTraceRequestMetadata) async throws -> TracedHTTPResult {
        try await GoApproval.requireAccount()
        guard let address = request.url else { throw URLError(.badURL) }
        let path = address.path
        if address.host == "queue.fal.run", let range = path.range(of: "/requests/job_") {
            let suffix = String(path[range.upperBound...])
            let id = "job_" + String(suffix.split(separator: "/").first ?? "")
            let cached = await GoOutputStore.shared.read(id)
            let job: GoDocument
            if let cached { job = cached } else { job = try await GoAPI.call("jobs/" + id) }
            let object: [String: Any]
            if path.hasSuffix("/status") {
                let state: String
                switch job.string("status") {
                case "succeeded": state = "COMPLETED"
                case "failed", "canceled":
                    state = "FAILED"
                    try await GoIntentStore.shared.acknowledge(id)
                case "uncertain": throw GoServiceError(code: "outcome_unknown", message: job.string("message"))
                default: state = "IN_PROGRESS"
                }
                object = ["status": state, "request_id": id]
            } else {
                guard job.string("status") == "succeeded" else { throw GoServiceError(code: "not_complete", message: job.string("message")) }
                let local = try await GoOutputStore.shared.persist(job)
                object = local.document("result").object
            }
            return try await result(request, metadata: metadata, object: object, job: job)
        }
        guard request.httpMethod == "POST" || address.host == "api.elevenlabs.io" else {
            throw GoServiceError(code: "unsupported", message: "This provider operation requires your own API key.")
        }
        let operation: String
        var payload = GoDocument(data: request.httpBody ?? Data("{}".utf8)).object
        switch address.host {
        case "api.openai.com":
            guard path == "/v1/responses", payload["tools"] == nil else {
                throw GoServiceError(code: "unsupported", message: "Choose Nano Banana 2 for images with Go, or use your own API key for this tool.")
            }
            operation = "text"
        case "queue.fal.run":
            if path == "/fal-ai/nano-banana-2" || path == "/fal-ai/nano-banana-2/edit" { operation = "image" }
            else if path == "/fal-ai/kling-video/v3/pro/image-to-video" { operation = "video" }
            else { throw GoServiceError(code: "unsupported", message: "Go includes Nano Banana 2 and Kling 3 Pro. Choose one of those models or use your own API key.") }
        case "api.elevenlabs.io":
            if path.contains("/text-to-speech/") { operation = "speech"; payload["voice_id"] = address.lastPathComponent }
            else if path.contains("/sound-generation") { operation = "sound" }
            else if path.hasSuffix("/voices") { operation = "voices" }
            else { throw GoServiceError(code: "unsupported", message: "This audio operation requires your own API key.") }
        case "go.litscenes.invalid":
            if path.hasSuffix("/lens-context/resolve") { operation = "context" }
            else if path.hasSuffix("/scene-story/generate") { operation = "story" }
            else if path.hasSuffix("/frame-forms/generate") { operation = "frame_forms" }
            else { throw URLError(.unsupportedURL) }
        default:
            // A routing marker is never transmitted to a provider or a custom gateway.
            throw GoServiceError(code: "unsupported", message: "This custom provider is available with your own API key.")
        }
        let context: [String: Any] = ["project_id": metadata.projectId, "run_id": metadata.runId,
            "trace_group_id": metadata.traceGroupId, "parent_trace_id": metadata.parentTraceId,
            "workflow_name": metadata.workflowName.isEmpty ? "desktop_go" : metadata.workflowName,
            "workflow_step": metadata.workflowStep, "artifact_type": metadata.artifactType, "artifact_id": metadata.artifactId,
            "source_prompt": metadata.requestTextJSON]
        let original = try GoDocument(["operation": operation, "payload": payload, "context": context])
        let accountId = GoVault.read("session")?.string("account_id") ?? ""
        let fingerprint = GoVault.hash(accountId + String(decoding: original.data, as: UTF8.self))
        let saved = await GoIntentStore.shared.read(fingerprint)
        var existing = saved
        if let saved, saved.string("job_id").isEmpty, saved.bool("approved") {
            do {
                let recovered = try await GoAPI.call("jobs/by-request/" + saved.string("request_key"))
                var updated = saved.object
                updated["job_id"] = recovered.string("job_id")
                let recoveredIntent = try GoDocument(updated)
                try await GoIntentStore.shared.save(fingerprint, recoveredIntent)
                existing = recoveredIntent
            } catch let error as GoServiceError where error.code == "job_missing" { }
        }
        let job: GoDocument
        if let existing, !existing.string("job_id").isEmpty {
            if let cached = await GoOutputStore.shared.read(existing.string("job_id")) { job = cached }
            else { job = try await GoAPI.call("jobs/" + existing.string("job_id")) }
        } else {
            let prepared = try await prepareMedia(GoDocument(payload))
            let body = try GoDocument(["operation": operation, "payload": prepared.object, "context": context])
            let quote = try await GoAPI.call("quotes", method: "POST", body: body)
            if existing?.bool("approved") != true || existing?.string("fingerprint") != quote.string("fingerprint") || quote.int("maximum_credits") > (existing?.int("maximum_credits") ?? -1) {
                try await GoApproval.approve(quote)
            }
            let intent = try GoDocument(["key": fingerprint, "body": body.object, "approved": true,
                "maximum_credits": quote.int("maximum_credits"), "fingerprint": quote.string("fingerprint"),
                "request_key": existing?.string("request_key") ?? UUID().uuidString, "quote_id": quote.string("quote_id"),
                "account_id": GoVault.read("session")?.string("account_id") ?? ""])
            try await GoIntentStore.shared.save(fingerprint, intent)
            do {
                try await GoApproval.waitForCredits(quote.int("maximum_credits"))
                job = try await submit(intent)
            } catch is CancellationError {
                var canceled = intent.object
                canceled["approved"] = false
                try await GoIntentStore.shared.save(fingerprint, GoDocument(canceled))
                throw CancellationError()
            }
        }
        if address.host == "queue.fal.run" {
            return try await result(request, metadata: metadata, object: ["request_id": job.string("job_id"),
                "status_url": "https://queue.fal.run/fal-ai/managed/requests/\(job.string("job_id"))/status",
                "response_url": "https://queue.fal.run/fal-ai/managed/requests/\(job.string("job_id"))/response"], job: job)
        }
        let jobId = job.string("job_id")
        let completed = try await withTaskCancellationHandler {
            try await wait(jobId)
        } onCancel: {
            Task { _ = try? await GoAPI.call("jobs/" + jobId + "/cancel", method: "POST", body: GoDocument([:])) }
        }
        let local = try await GoOutputStore.shared.persist(completed)
        if operation == "speech" || operation == "sound" {
            guard let artifact = local.documents("artifacts").first else { throw URLError(.badServerResponse) }
            let data = try await GoOutputStore.shared.data(artifact)
            let reply = try await result(request, metadata: metadata, object: [:], job: completed, audio: data)
            return reply
        }
        let reply = try await result(request, metadata: metadata, object: local.document("result").object, job: completed)
        return reply
    }

    static func submit(_ intent: GoDocument) async throws -> GoDocument {
        guard intent.string("account_id") == GoVault.read("session")?.string("account_id") else {
            throw GoServiceError(code: "account_changed", message: "This action belongs to another account. Sign in to that account to continue.")
        }
        var current = intent.object
        do {
            let job = try await GoAPI.call("jobs", method: "POST", body: GoDocument([
                "quote_id": intent.string("quote_id"), "request_key": intent.string("request_key"),
                "approved_maximum_credits": intent.int("maximum_credits")]))
            current["job_id"] = job.string("job_id")
            try await GoIntentStore.shared.save(intent.string("key"), GoDocument(current))
            return job
        } catch let error as GoServiceError where error.code == "quote_expired" {
            let updated = try await GoAPI.call("quotes", method: "POST", body: intent.document("body"))
            guard updated.string("fingerprint") == intent.string("fingerprint"), updated.int("maximum_credits") <= intent.int("maximum_credits") else {
                throw GoServiceError(code: "quote_changed", message: "The quote changed while checkout was open. Review this action again before creating.")
            }
            current["quote_id"] = updated.string("quote_id")
            let renewed = try GoDocument(current)
            try await GoIntentStore.shared.save(intent.string("key"), renewed)
            return try await submit(renewed)
        }
    }

    static func resumePending() async {
        guard let account = GoVault.read("session")?.string("account_id") else { return }
        for intent in await GoIntentStore.shared.pending() where intent.string("account_id") == account {
            do {
                let balance = try await GoAPI.call("account")
                guard balance.int("available_credits") >= intent.int("maximum_credits") else { continue }
                _ = try await submit(intent)
            } catch {
                await MainActor.run { GoAccountStore.shared.message = error.localizedDescription }
            }
        }
    }

    static func wait(_ jobId: String) async throws -> GoDocument {
        if let cached = await GoOutputStore.shared.read(jobId) { return cached }
        while true {
            try Task.checkCancellation()
            let job = try await GoAPI.call("jobs/" + jobId)
            if job.string("status") == "succeeded" { return job }
            if ["failed", "canceled", "uncertain"].contains(job.string("status")) {
                if job.string("status") != "uncertain" { try await GoIntentStore.shared.acknowledge(jobId) }
                throw GoServiceError(code: job.string("error_code"), message: job.string("message").isEmpty ? "This action was canceled." : job.string("message"))
            }
            try await Task.sleep(for: .seconds(2))
        }
    }

    private static func prepareMedia(_ payload: GoDocument) async throws -> GoDocument {
        let data = payload.data
        let source = try JSONSerialization.jsonObject(with: data)
        let updated = try await replaceMedia(source)
        return GoDocument(data: try JSONSerialization.data(withJSONObject: updated, options: [.sortedKeys]))
    }

    private static func replaceMedia(_ value: Any) async throws -> Any {
        if let object = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, item) in object { result[key] = try await replaceMedia(item) }
            return result
        }
        if let array = value as? [Any] {
            var result: [Any] = []
            for item in array { result.append(try await replaceMedia(item)) }
            return result
        }
        if let string = value as? String, string.hasPrefix("data:"), let separator = string.firstIndex(of: ",") {
            let header = string[..<separator]
            let mimeType = header.dropFirst(5).split(separator: ";").first.map(String.init) ?? "image/png"
            guard header.hasSuffix(";base64"), let bytes = Data(base64Encoded: String(string[string.index(after: separator)...])) else { throw URLError(.cannotDecodeContentData) }
            let key = "upload:" + GoVault.hash(string)
            if let cached = GoVault.read(key), cached.int("expires_at") > Int(Date().timeIntervalSince1970), cached.string("account_id") == GoVault.read("session")?.string("account_id") { return cached.string("reference") }
            let reference = try await GoAPI.upload(bytes, mimeType: mimeType)
            try GoVault.save(key, GoDocument(["reference": reference, "expires_at": Int(Date().timeIntervalSince1970) + 6 * 86400, "account_id": GoVault.read("session")?.string("account_id") ?? ""]))
            return reference
        }
        return value
    }

    private static func result(_ request: URLRequest, metadata: InferenceTraceRequestMetadata, object: [String: Any], job: GoDocument, audio: Data? = nil) async throws -> TracedHTTPResult {
        let data = try audio ?? JSONSerialization.data(withJSONObject: object)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["content-type": audio == nil ? "application/json" : "audio/mpeg", "x-request-id": job.string("job_id"), "x-litscenes-trace-id": job.string("trace_id")])
        var safeRequest = request
        safeRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        safeRequest.setValue(nil, forHTTPHeaderField: "xi-api-key")
        safeRequest.url = GoConnection.baseURL.appending(path: "jobs/" + job.string("job_id"))
        safeRequest.httpBody = nil
        var trace = metadata
        trace.provider = "litscenes"
        trace.apiFamily = "desktop_go"
        trace.captureRequestBody = false
        trace.captureResponseBody = false
        trace.responseTextJSON = try String(decoding: GoDocument(["job_id": job.string("job_id"), "canonical_trace_id": job.string("trace_id"), "charged_credits": job.int("charged_credits"), "status": job.string("status")]).data, as: UTF8.self)
        let traceId = await InferenceTraceStore.shared.record(request: safeRequest, metadata: trace, response: response, responseBody: nil, latencyMs: 0)
        return TracedHTTPResult(traceId: traceId, data: data, response: response, latencyMs: 0)
    }
}
