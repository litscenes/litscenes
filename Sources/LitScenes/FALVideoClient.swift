import Foundation

private protocol FALTrackedVideoRequest {
    var projectId: String { get }
    var runId: String { get }
    var traceGroupId: String { get }
    var workflowName: String { get }
    var artifactType: String { get }
    var artifactId: String { get }
    var modelSelection: VideoModelSelection { get }
}

struct FALJoinBridgeRequest: Sendable {
    var projectId: String
    var shotId: String
    var artifactId: String
    var provider: ShotJoinBridgeProvider
    var durationSeconds: Int
    var prompt: String
    var resolution: String
    var outgoingFrameURL: URL
    var incomingFrameURL: URL
    var outputURL: URL
}

struct FALJoinBridgeResult: Sendable {
    var outputURL: URL
    var requestId: String
    var traceId: String
}

struct FALImageToVideoRequest: FALTrackedVideoRequest {
    var projectId: String
    var runId: String
    var traceGroupId: String
    var workflowName: String
    var artifactType: String
    var artifactId: String
    var modelSelection: VideoModelSelection
    var prompt: String
    var negativePrompt: String
    var durationSeconds: Int
    var generateAudio: Bool
    var outputProfile: VideoOutputProfile
    /// nil ⇒ a tail-anchored AI lead-in: `targetEndFrameURL` must be present
    /// and the model must accept an end frame alone (Kling).
    var startFrameURL: URL?
    var targetEndFrameURL: URL?
    var outputURL: URL
    /// See `VideoClipRequest.multiShotPrompts` — Kling v3 only.
    var multiShotPrompts: [ShotCompiledKlingShot]? = nil
    /// See `VideoClipRequest.promptIsStructured`.
    var promptIsStructured: Bool = false
}

struct FALAudioToVideoRequest: FALTrackedVideoRequest {
    var projectId: String
    var runId: String
    var traceGroupId: String
    var parentTraceId: String
    var workflowName: String
    var artifactType: String
    var artifactId: String
    var modelSelection: VideoModelSelection
    var prompt: String
    var audioDriverURL: URL
    var audioDriverDurationSeconds: Double
    var outputProfile: VideoOutputProfile
    var startFrameURL: URL
    var outputURL: URL
    var onSubmitted: (@MainActor (String, String) async -> Void)?
}

struct FALImageToVideoResult {
    var outputURL: URL
    var requestId: String
    var traceId: String
    var traceIds: [String]
    var providerNativeSize: String
    var responseSnapshot: [String: String]
}

typealias FALAudioToVideoResult = FALImageToVideoResult

private struct FALAudioDriverUpload {
    var remoteURL: URL
    var traceIds: [String]
}

struct FALRestyleRequest: Sendable {
    var projectId: String
    var shotId: String
    var artifactId: String
    var prompt: String
    var enhancePrompt: Bool
    var seed: Int
    var sourceURL: URL
    var outputURL: URL
    // Trace identity. Defaults preserve the shipped shot-look labels; the
    // clip-look pipeline overrides so traces name what actually ran.
    var workflowName: String = "shot_look_restyle"
    var artifactType: String = "shot_restyle"
    /// Empty → "shot_look_\(shotId)".
    var traceGroupId: String = ""
}

struct FALRestyleSubmission: Sendable {
    var requestId: String
    var traceId: String
}

struct FALRestyleRemoteResult: Sendable {
    var videoURL: URL
    var traceId: String
}

/// Raw FAL queue/storage transport for the bounded Shot operations currently
/// wired in product: image-to-video, exact razor-join bridges, and Shot Looks.
struct FALVideoClient: @unchecked Sendable {
    let credentialStore: LitScenesCredentialResolving

    /// Kling v3's `multi_prompt` is mutually exclusive with the top-level
    /// `prompt` (verified against the live schema); whether the
    /// top-level `duration` must also be omitted is UNVERIFIED. Omit-first —
    /// a schema 422 bills nothing. Flip to true if the first real multi-shot
    /// submit reports a missing/invalid duration.
    static let klingMultiPromptSendsTopLevelDuration = false

    /// The wire shape of Kling v3's `multi_prompt` array — each element's
    /// duration is a STRING, exactly like the endpoint's top-level duration.
    static func klingMultiPromptPayload(_ shots: [ShotCompiledKlingShot]) -> [[String: Any]] {
        shots.map { ["prompt": $0.prompt, "duration": "\($0.durationSeconds)"] }
    }

    private let queueBaseURL = URL(string: "https://queue.fal.run")!
    private let terminalStates: Set<String> = ["COMPLETED", "FAILED", "CANCELLED", "CANCELED"]
    private let restyleModelId = "decart/lucy-restyle"
    private let privateInputLifecycle = "{\"expiration_duration_seconds\":86400,\"initial_acl\":{\"default\":\"forbid\",\"rules\":[]}}"
    // Marketplace runners own the CDN objects they emit. A deny-all ACL would
    // therefore deny the calling account too. Keep the provider handoff public
    // for one bounded recovery hour, then rely on the durable project-local copy.
    private let publicOutputLifecycle = "{\"expiration_duration_seconds\":3600,\"initial_acl\":{\"default\":\"allow\",\"rules\":[]}}"

    /// Uploads the already-validated local Original edit. The transfer uses a
    /// presigned URL, so the FAL key is sent only to the initiate endpoint.
    /// URLSession streams from disk instead of materializing a large video in
    /// memory; FAL's returned object is private and expires after 24 hours.
    func uploadRestyleSource(_ request: FALRestyleRequest) async throws -> (url: URL, traceId: String) {
        let apiKey = try restyleAPIKey()
        let attributes = try FileManager.default.attributesOfItem(atPath: request.sourceURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let usesMultipart = byteCount > 90 * 1_024 * 1_024
        let initiatePath = usesMultipart ? "initiate-multipart" : "initiate"
        var initiate = URLRequest(
            url: URL(string: "https://rest.fal.ai/storage/upload/\(initiatePath)?storage_type=fal-cdn-v3")!
        )
        initiate.httpMethod = "POST"
        initiate.timeoutInterval = 180
        initiate.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        initiate.setValue("application/json", forHTTPHeaderField: "Content-Type")
        initiate.setValue("application/json", forHTTPHeaderField: "Accept")
        initiate.setValue(privateInputLifecycle, forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference")
        initiate.setValue(privateInputLifecycle, forHTTPHeaderField: "X-Fal-Object-Lifecycle")
        initiate.httpBody = try JSONSerialization.data(withJSONObject: [
            "file_name": request.sourceURL.lastPathComponent,
            "content_type": "video/mp4",
        ], options: [.sortedKeys])
        let traced = try await sendRestyleRequest(
            initiate,
            operation: "cdn_upload_initiate",
            request: request,
            requestTextFields: ["content_type": "video/mp4"]
        )
        guard let object = try JSONSerialization.jsonObject(with: traced.data) as? [String: Any],
              let uploadURL = falVideoFirstURL(in: object, keys: ["upload_url", "uploadUrl"]),
              let fileURL = falVideoFirstURL(in: object, keys: ["file_url", "fileUrl"]) else {
            throw ScreenGraphError.capture("FAL private upload initiation returned no upload URL.")
        }

        if usesMultipart {
            try await uploadRestyleMultipart(sourceURL: request.sourceURL, uploadURL: uploadURL)
        } else {
            var upload = URLRequest(url: uploadURL)
            upload.httpMethod = "PUT"
            upload.timeoutInterval = 1_800
            upload.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.upload(for: upload, fromFile: request.sourceURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw ScreenGraphError.capture("FAL private source upload failed.")
            }
        }
        return (fileURL, traced.traceId)
    }

    private func uploadRestyleMultipart(sourceURL: URL, uploadURL: URL) async throws {
        let handle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? handle.close() }
        let chunkSize = 10 * 1_024 * 1_024
        var partNumber = 1
        var parts: [[String: Any]] = []
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            try Task.checkCancellation()
            let partURL = falMultipartURL(base: uploadURL, suffix: String(partNumber))
            var lastError: Error?
            var partObject: [String: Any]?
            for _ in 0..<3 {
                do {
                    var partRequest = URLRequest(url: partURL)
                    partRequest.httpMethod = "PUT"
                    partRequest.timeoutInterval = 600
                    let (data, response) = try await URLSession.shared.upload(for: partRequest, from: chunk)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw ScreenGraphError.capture("FAL multipart part \(partNumber) failed.")
                    }
                    partObject = object
                    break
                } catch {
                    lastError = error
                }
            }
            guard let partObject else {
                throw lastError ?? ScreenGraphError.capture("FAL multipart part \(partNumber) exhausted retries.")
            }
            let returnedPart = (partObject["partNumber"] as? NSNumber)?.intValue
                ?? (partObject["part_number"] as? NSNumber)?.intValue
                ?? partNumber
            let etag = falVideoFirstString(in: partObject, keys: ["etag", "eTag", "ETag"])
            guard !etag.isEmpty else {
                throw ScreenGraphError.capture("FAL multipart part \(partNumber) returned no ETag.")
            }
            parts.append(["partNumber": returnedPart, "etag": etag])
            partNumber += 1
        }
        guard !parts.isEmpty else { throw ScreenGraphError.capture("The Look source was empty during upload.") }
        var complete = URLRequest(url: falMultipartURL(base: uploadURL, suffix: "complete"))
        complete.httpMethod = "POST"
        complete.timeoutInterval = 600
        complete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        complete.httpBody = try JSONSerialization.data(withJSONObject: ["parts": parts], options: [.sortedKeys])
        let (_, response) = try await URLSession.shared.data(for: complete)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture("FAL multipart upload could not be completed.")
        }
    }

    private func falMultipartURL(base: URL, suffix: String) -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return base.appendingPathComponent(suffix)
        }
        components.path += "/\(suffix)"
        return components.url ?? base.appendingPathComponent(suffix)
    }

    func submitRestyle(_ request: FALRestyleRequest, sourceRemoteURL: URL) async throws -> FALRestyleSubmission {
        let apiKey = try restyleAPIKey()
        // The canonical upload remains default-forbid. Marketplace runners do
        // not execute as the owning account, so give Lucy an ephemeral signed
        // read URL and never persist or trace that credential-bearing value.
        let executableSourceURL = try await signedRestyleSourceURL(
            request,
            privateURL: sourceRemoteURL
        )
        let modelURL = queueBaseURL.appendingPathComponent(restyleModelId)
        let submittedPrompt = restyleProviderPrompt(request)
        let payload: [String: Any] = [
            "prompt": submittedPrompt,
            "video_url": executableSourceURL.absoluteString,
            "seed": max(request.seed, 0),
            "resolution": "720p",
            "enhance_prompt": request.enhancePrompt,
        ]
        var submission = URLRequest(url: modelURL)
        submission.httpMethod = "POST"
        submission.timeoutInterval = 180
        submission.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        submission.setValue("application/json", forHTTPHeaderField: "Content-Type")
        submission.setValue("application/json", forHTTPHeaderField: "Accept")
        submission.setValue("0", forHTTPHeaderField: "X-Fal-Store-IO")
        submission.setValue(publicOutputLifecycle, forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference")
        submission.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let traced = try await sendRestyleRequest(
            submission,
            operation: "queue_submit",
            request: request
        )
        guard let object = try JSONSerialization.jsonObject(with: traced.data) as? [String: Any] else {
            throw ScreenGraphError.capture("FAL Lucy submission returned invalid JSON.")
        }
        let requestId = falVideoFirstString(in: object, keys: ["request_id", "requestId", "id"])
        guard !requestId.isEmpty else {
            throw ScreenGraphError.capture("FAL Lucy submission returned no request id.")
        }
        return FALRestyleSubmission(requestId: requestId, traceId: traced.traceId)
    }

    func waitForRestyle(_ request: FALRestyleRequest, requestId: String) async throws -> FALRestyleRemoteResult {
        let apiKey = try restyleAPIKey()
        let requestRoot = queueBaseURL.appendingPathComponent(restyleModelId)
            .appendingPathComponent("requests").appendingPathComponent(requestId)
        let started = Date()
        var delay: UInt64 = 3
        while true {
            try Task.checkCancellation()
            var components = URLComponents(
                url: requestRoot.appendingPathComponent("status"),
                resolvingAgainstBaseURL: false
            )
            components?.queryItems = [URLQueryItem(name: "logs", value: "1")]
            var statusRequest = URLRequest(url: components?.url ?? requestRoot.appendingPathComponent("status"))
            statusRequest.httpMethod = "GET"
            statusRequest.timeoutInterval = 180
            statusRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
            let statusResponse = try await sendRestyleRequest(
                statusRequest,
                operation: "queue_status",
                request: request,
                requestTextFields: ["provider_request_id": requestId]
            )
            guard let statusObject = try JSONSerialization.jsonObject(with: statusResponse.data) as? [String: Any] else {
                throw ScreenGraphError.capture("FAL Lucy status returned invalid JSON.")
            }
            let status = falVideoFirstString(in: statusObject, keys: ["status"]).uppercased()
            if status == "COMPLETED" {
                if let providerError = falVideoCompletedErrorSummary(in: statusObject) {
                    throw FALWorkflowFailure(
                        jobId: requestId,
                        traceId: statusResponse.traceId,
                        message: "FAL Lucy request failed validation or execution. \(providerError)"
                    )
                }
                // FAL's REST result read is GET /requests/{request_id}. The
                // submit-time /response convenience URL is not a GET route.
                var resultRequest = URLRequest(url: requestRoot)
                resultRequest.httpMethod = "GET"
                resultRequest.timeoutInterval = 180
                resultRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
                let result = try await sendRestyleRequest(
                    resultRequest,
                    operation: "queue_result",
                    request: request,
                    requestTextFields: ["provider_request_id": requestId]
                )
                guard let resultObject = try JSONSerialization.jsonObject(with: result.data) as? [String: Any],
                      let videoURL = falVideoOutputURL(in: resultObject) else {
                    throw ScreenGraphError.capture("FAL Lucy result returned no video URL.")
                }
                return FALRestyleRemoteResult(
                    videoURL: videoURL,
                    traceId: result.traceId.isEmpty ? statusResponse.traceId : result.traceId
                )
            }
            if terminalStates.contains(status) {
                throw FALWorkflowFailure(
                    jobId: requestId,
                    traceId: statusResponse.traceId,
                    message: "FAL Lucy request ended with \(status.isEmpty ? "unknown status" : status). \(falVideoFailureSummary(from: statusObject))".trimmed
                )
            }
            if Date().timeIntervalSince(started) > 10_800 {
                throw ScreenGraphError.capture("FAL Lucy request did not finish within three hours. It can be resumed later.")
            }
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay = min(UInt64(Double(delay) * 1.4), 30)
        }
    }

    func downloadRestyleOutput(_ request: FALRestyleRequest, remoteURL: URL) async throws {
        var downloadRequest = URLRequest(url: remoteURL)
        downloadRequest.timeoutInterval = 1_800
        let (temporaryURL, response) = try await URLSession.shared.download(for: downloadRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let statusText = status > 0 ? "HTTP \(status)" : "an invalid response"
            let recovery = [403, 404, 410].contains(status)
                ? "The provider handoff is no longer accessible; create a new Look instead of retrying this download."
                : "Retry Download can resume the existing paid result while its provider handoff is available."
            throw ScreenGraphError.capture("FAL Lucy output download returned \(statusText). \(recovery)")
        }
        try ensureDirectory(request.outputURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: request.outputURL.path) {
            try FileManager.default.removeItem(at: request.outputURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: request.outputURL)
    }

    private func signedRestyleSourceURL(
        _ request: FALRestyleRequest,
        privateURL: URL
    ) async throws -> URL {
        guard privateURL.scheme?.lowercased() == "https",
              privateURL.host?.lowercased() == "v3b.fal.media" else {
            throw ScreenGraphError.capture("FAL returned an unsupported private input URL.")
        }
        let token = try await restyleCDNToken(
            request,
            expirationSeconds: 3_600,
            operation: "cdn_input_token"
        )
        guard var components = URLComponents(url: privateURL, resolvingAgainstBaseURL: false) else {
            throw ScreenGraphError.capture("The private Look input URL could not be signed.")
        }
        components.query = nil
        components.fragment = nil
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/\(components.path)/sign"
        guard let signingURL = components.url else {
            throw ScreenGraphError.capture("The private Look input signing URL was invalid.")
        }

        var signingRequest = URLRequest(url: signingURL)
        signingRequest.httpMethod = "POST"
        signingRequest.timeoutInterval = 180
        signingRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        signingRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        signingRequest.setValue("text/plain, application/json", forHTTPHeaderField: "Accept")
        signingRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "duration": 86_400,
            "scope": ["read"],
        ], options: [.sortedKeys])
        let signedResponse = try await sendRestyleRequest(
            signingRequest,
            operation: "cdn_sign_input",
            request: request,
            requestTextFields: ["duration_seconds": 86_400, "scope": ["read"]]
        )
        let responseValue = try? JSONSerialization.jsonObject(
            with: signedResponse.data,
            options: [.fragmentsAllowed]
        )
        let signedText: String
        if let value = responseValue as? String {
            signedText = value.trimmed
        } else if let object = responseValue as? [String: Any] {
            signedText = falVideoFirstString(in: object, keys: ["url", "signed_url", "signedUrl"])
        } else {
            signedText = (String(data: signedResponse.data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        guard let signedURL = URL(string: signedText),
              signedURL.scheme?.lowercased() == "https",
              signedURL.host?.lowercased() == privateURL.host?.lowercased(),
              signedURL.absoluteString != privateURL.absoluteString else {
            throw ScreenGraphError.capture("FAL did not return a usable signed Look input URL.")
        }
        return signedURL
    }

    private func restyleCDNToken(
        _ request: FALRestyleRequest,
        expirationSeconds: Int,
        operation: String
    ) async throws -> String {
        let apiKey = try restyleAPIKey()
        var tokenRequest = URLRequest(
            url: URL(string: "https://rest.fal.ai/storage/auth/token?storage_type=fal-cdn-v3")!
        )
        tokenRequest.httpMethod = "POST"
        tokenRequest.timeoutInterval = 180
        tokenRequest.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        tokenRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        tokenRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "expiration_seconds": max(expirationSeconds, 1),
        ], options: [.sortedKeys])
        let tokenResponse = try await sendRestyleRequest(
            tokenRequest,
            operation: operation,
            request: request,
            requestTextFields: ["expiration_seconds": max(expirationSeconds, 1)]
        )
        guard let tokenObject = try JSONSerialization.jsonObject(with: tokenResponse.data) as? [String: Any] else {
            throw ScreenGraphError.capture("FAL CDN token response was invalid.")
        }
        let token = falVideoFirstString(in: tokenObject, keys: ["token"])
        guard !token.isEmpty else { throw ScreenGraphError.capture("FAL CDN returned no download token.") }
        return token
    }

    func cancelRestyle(requestId: String, context request: FALRestyleRequest) async {
        guard !requestId.trimmed.isEmpty, let apiKey = try? restyleAPIKey() else { return }
        let url = queueBaseURL.appendingPathComponent(restyleModelId)
            .appendingPathComponent("requests").appendingPathComponent(requestId)
            .appendingPathComponent("cancel")
        var cancel = URLRequest(url: url)
        cancel.httpMethod = "PUT"
        cancel.timeoutInterval = 60
        cancel.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        _ = try? await sendRestyleRequest(
            cancel,
            operation: "queue_cancel",
            request: request,
            requestTextFields: ["provider_request_id": requestId]
        )
    }

    private func restyleAPIKey() throws -> String {
        let apiKey = credentialStore.resolvedCredential(for: .fal)
        guard !apiKey.trimmed.isEmpty else {
            throw ScreenGraphError.credentials("Add a FAL API key in App Settings to create a Shot Look.")
        }
        return apiKey
    }

    private func sendRestyleRequest(
        _ request: URLRequest,
        operation: String,
        request generationRequest: FALRestyleRequest,
        requestTextFields: [String: Any] = [:]
    ) async throws -> (data: Data, traceId: String) {
        let traced = try await TracedHTTPTransport.send(
            request: request,
            metadata: InferenceTraceRequestMetadata(
                provider: "fal",
                apiFamily: "video",
                operation: operation,
                projectId: generationRequest.projectId,
                runId: generationRequest.artifactId,
                traceGroupId: generationRequest.traceGroupId.trimmed.nilIfEmpty
                    ?? "shot_look_\(generationRequest.shotId)",
                workflowName: generationRequest.workflowName,
                workflowStep: "fal_lucy_\(operation)",
                artifactType: generationRequest.artifactType,
                artifactId: generationRequest.artifactId,
                model: restyleModelId,
                requestBodyFormat: request.httpBody == nil ? "none" : "application/json",
                responseBodyFormatHint: "application/json",
                requestTextJSON: restyleTraceRequestTextJSON(
                    generationRequest,
                    requestTextFields: requestTextFields
                ),
                providerRequestIDHeaderCandidates: ["x-fal-request-id", "x-request-id", "request-id"],
                captureRequestBody: false,
                captureResponseBody: false
            )
        )
        guard let http = traced.response, (200..<300).contains(http.statusCode) else {
            let body = String(data: traced.data.prefix(1_200), encoding: .utf8) ?? ""
            throw ScreenGraphError.capture("FAL Lucy \(operation) failed: \(body)")
        }
        return (traced.data, traced.traceId)
    }

    private func restyleProviderPrompt(_ request: FALRestyleRequest) -> String {
        String(request.prompt.prefix(1_500))
    }

    private func restyleTraceRequestTextJSON(
        _ request: FALRestyleRequest,
        requestTextFields: [String: Any]
    ) -> String {
        let prompt = restyleProviderPrompt(request)
        var fields: [String: Any] = [
            "prompt": prompt,
            "prompt_chars": prompt.count,
            "resolution": "720p",
            "enhance_prompt": request.enhancePrompt,
            "seed": max(request.seed, 0),
        ]
        for (key, value) in requestTextFields {
            fields[key] = value
        }
        return inferenceTraceJSONString(fields)
    }

    func generateImageToVideo(
        from request: FALImageToVideoRequest
    ) async throws -> FALImageToVideoResult {
        let apiKey = credentialStore.resolvedCredential(for: .fal).trimmed
        guard !apiKey.isEmpty else {
            throw ScreenGraphError.credentials(
                "Add a FAL API key in App Settings to render this Shot model."
            )
        }
        let modelId = request.modelSelection.providerModelId
        let durationRange: ClosedRange<Int>
        let startField: String
        let resolution: String
        let providerNativeSize: String
        switch request.modelSelection {
        case .falKlingV3ProImageToVideo:
            durationRange = 3...15
            startField = "start_image_url"
            resolution = "input-derived"
            providerNativeSize = "input-derived \(request.outputProfile.aspectRatio.rawValue)"
        case .falSeedance20ImageToVideo:
            durationRange = 4...15
            startField = "image_url"
            // Same property the cost estimate prices — see falResolutionTier.
            resolution = request.modelSelection.falResolutionTier?.rawValue ?? "1080p"
            providerNativeSize = "\(request.outputProfile.width)x\(request.outputProfile.height)"
        case .falSeedance25ImageToVideo:
            // Endpoint accepts up to 30s; the app caps at 15 for stack parity.
            durationRange = 4...15
            startField = "image_url"
            // Same property the cost estimate prices — see falResolutionTier.
            resolution = request.modelSelection.falResolutionTier?.rawValue ?? "720p"
            providerNativeSize = "\(request.outputProfile.width)x\(request.outputProfile.height)"
        case .falWan27ImageToVideo:
            durationRange = 2...15
            startField = "image_url"
            // Same property the cost estimate prices — see falResolutionTier.
            resolution = request.modelSelection.falResolutionTier?.rawValue ?? "1080p"
            providerNativeSize = "\(request.outputProfile.width)x\(request.outputProfile.height)"
        case .falHailuo3ImageToVideo:
            durationRange = 5...15
            startField = "image_url"
            // USER-CHOSEN, not a fixed tier — the endpoint's own spelling
            // (768P/2K); the cost estimate prices the endpoint's reported
            // per-unit rate regardless (stated approximation).
            resolution = Hailuo3ResolutionPreference.resolution(for: .falHailuo3)
            providerNativeSize = "\(resolution) \(request.outputProfile.aspectRatio.rawValue)"
        case .falHailuo3MaxImageToVideo:
            durationRange = 5...15
            startField = "image_url"
            resolution = Hailuo3ResolutionPreference.resolution(for: .falHailuo3Max)
            providerNativeSize = "\(resolution) \(request.outputProfile.aspectRatio.rawValue)"
        default:
            throw ScreenGraphError.capture(
                "\(request.modelSelection.label) is not a FAL Shot image-to-video model."
            )
        }
        guard durationRange.contains(request.durationSeconds) else {
            throw ScreenGraphError.capture(
                "\(request.modelSelection.label) does not support a \(request.durationSeconds)-second clip."
            )
        }

        let startInput = try request.startFrameURL.map {
            try imageInput(at: $0, role: "start_frame")
        }
        let endInput = try request.targetEndFrameURL.map {
            try imageInput(at: $0, role: "end_frame")
        }
        guard startInput != nil || endInput != nil else {
            throw ScreenGraphError.capture(
                "\(request.modelSelection.label) needs a start or end frame."
            )
        }
        let multiShots = request.multiShotPrompts ?? []
        if !multiShots.isEmpty {
            // The compiler guarantees this is unreachable off-Kling; the
            // throw guards drift, before any spend.
            guard request.modelSelection == .falKlingV3ProImageToVideo else {
                throw ScreenGraphError.capture(
                    "Multi-shot direction is only supported on Kling 3 Pro."
                )
            }
            let shotSum = multiShots.map(\.durationSeconds).reduce(0, +)
            guard multiShots.allSatisfy({ (1...15).contains($0.durationSeconds) }),
                  shotSum == request.durationSeconds else {
                throw ScreenGraphError.capture(
                    "Multi-shot direction needs 1–15 second shots summing to the "
                        + "\(request.durationSeconds)-second segment (got \(shotSum))."
                )
            }
        }
        let providerPrompt = request.prompt.trimmed.nilIfEmpty
            ?? "Animate the supplied image with coherent story motion."
        // The endpoint declares how it spells seconds; see falDurationEncoding.
        let durationEncoding = request.modelSelection.falDurationEncoding ?? .stringSeconds
        var input: [String: Any] = [:]
        if multiShots.isEmpty {
            input["prompt"] = providerPrompt
            input["duration"] = durationEncoding.payloadValue(seconds: request.durationSeconds)
        } else {
            // Kling v3's schema: multi_prompt is mutually exclusive with the
            // top-level prompt (verified against the live schema). Whether the top-level
            // duration must also be omitted is unverified — omit-first; a
            // schema 422 bills nothing, and the flip below is the one-line
            // repair if the endpoint demands the sum.
            input["multi_prompt"] = Self.klingMultiPromptPayload(multiShots)
            if Self.klingMultiPromptSendsTopLevelDuration {
                input["duration"] = "\(request.durationSeconds)"
            }
        }
        if let startInput {
            input[startField] = startInput.dataURI
        }
        if let endInput {
            input["end_image_url"] = endInput.dataURI
        }
        switch request.modelSelection {
        case .falKlingV3ProImageToVideo:
            input["generate_audio"] = request.generateAudio
            if !request.negativePrompt.trimmed.isEmpty {
                input["negative_prompt"] = request.negativePrompt.trimmed
            }
        case .falSeedance20ImageToVideo:
            input["generate_audio"] = request.generateAudio
            input["resolution"] = resolution
            input["aspect_ratio"] = request.outputProfile.aspectRatio.rawValue
            input["bitrate_mode"] = "standard"
        case .falSeedance25ImageToVideo:
            input["generate_audio"] = request.generateAudio
            input["resolution"] = resolution
            // The 2.5 schema pins aspect_ratio to "auto" (frame-derived) and
            // has no bitrate_mode parameter.
            input["aspect_ratio"] = "auto"
        case .falWan27ImageToVideo:
            // WAN's schema has no audio-generation flag — send none. The
            // expansion/safety flags mirror the retired CivitAI payload.
            // Provider-side prompt expansion would rewrite a compiled
            // temporal direction and shred its timing windows — structured
            // prompts turn it off; plan-less renders keep it on, as always.
            if !request.negativePrompt.trimmed.isEmpty {
                input["negative_prompt"] = request.negativePrompt.trimmed
            }
            input["resolution"] = resolution
            input["enable_prompt_expansion"] = !request.promptIsStructured
            input["enable_safety_checker"] = true
        case .falHailuo3ImageToVideo:
            // Hailuo 3 has no audio flag (stereo audio is always in the
            // file) and no expansion OFF switch — THE EXPANSION LAW (WAN
            // precedent) picks the least-rewriting mode for a compiled
            // temporal direction so its timing windows survive.
            input["resolution"] = resolution
            input["prompt_expansion_mode"] = request.promptIsStructured ? "fast" : "balanced"
        case .falHailuo3MaxImageToVideo:
            // H3 Max REQUIRES prompt_expansion_mode and offers no "fast" —
            // "balanced" is its least-rewriting mode either way.
            input["resolution"] = resolution
            input["prompt_expansion_mode"] = "balanced"
        default:
            break
        }

        var traceInput = input
        if startInput != nil {
            traceInput[startField] = "<data URI omitted; see media_refs_json>"
        }
        if endInput != nil {
            traceInput["end_image_url"] = "<data URI omitted; see media_refs_json>"
        }
        if !multiShots.isEmpty {
            // The array itself is text-only and rides traceInput verbatim;
            // the count makes multi-shot renders greppable in traces.
            traceInput["multi_prompt_shots"] = multiShots.count
        }
        let mediaRefs = [startInput?.traceSummary, endInput?.traceSummary].compactMap { $0 }
        let mediaRefsJSON = inferenceTraceJSONString(["inputs": mediaRefs])
        let modelURL = queueURL(modelId: modelId)
        let submitted = try await sendImageToVideoJSON(
            apiKey: apiKey,
            url: modelURL,
            method: "POST",
            payload: input,
            tracePayload: traceInput,
            mediaRefsJSON: mediaRefsJSON,
            operation: "queue_submit",
            workflowStep: "fal_video_submit",
            parentTraceId: "",
            request: request
        )
        let requestId = falVideoFirstString(
            in: submitted.object,
            keys: ["request_id", "requestId", "id"]
        )
        guard !requestId.isEmpty else {
            _ = await recordImageToVideoLifecycleEvent(
                requestId: "",
                outcome: "submission_accepted_without_request_id",
                detail: "The provider response did not include a resumable request id.",
                remoteRequestMayContinue: true,
                parentTraceId: submitted.traceId,
                request: request
            )
            throw ScreenGraphError.capture("FAL video submission returned no request id.")
        }
        await InferenceTraceStore.shared.enrich(
            traceId: submitted.traceId,
            providerRequestId: requestId,
            model: modelId
        )

        let statusURL = falVideoFirstURL(
            in: submitted.object,
            keys: ["status_url", "statusUrl"]
        ) ?? modelURL
            .appendingPathComponent("requests")
            .appendingPathComponent(requestId)
            .appendingPathComponent("status")
        let responseURL = falVideoFirstURL(
            in: submitted.object,
            keys: ["response_url", "responseUrl"]
        ) ?? modelURL
            .appendingPathComponent("requests")
            .appendingPathComponent(requestId)
            .appendingPathComponent("response")

        let polled = try await pollImageToVideoStatus(
            apiKey: apiKey,
            url: statusURL,
            requestId: requestId,
            parentTraceId: submitted.traceId,
            request: request
        )
        let status = falVideoFirstString(in: polled.response.object, keys: ["status"])
            .uppercased()
        if status != "COMPLETED"
            || falVideoCompletedErrorSummary(in: polled.response.object) != nil {
            let detail = falVideoSafeTraceText(
                falVideoCompletedErrorSummary(in: polled.response.object)
                    ?? falVideoFailureSummary(from: polled.response.object)
            )
            let eventTraceId = await recordImageToVideoLifecycleEvent(
                requestId: requestId,
                outcome: "provider_failed",
                detail: detail,
                remoteRequestMayContinue: false,
                parentTraceId: polled.response.traceId,
                request: request
            )
            throw FALWorkflowFailure(
                jobId: requestId,
                traceId: eventTraceId,
                message: "FAL video request \(requestId) ended with \(status.isEmpty ? "unknown status" : status). \(detail)".trimmed
            )
        }

        let response = try await sendImageToVideoJSON(
            apiKey: apiKey,
            url: responseURL,
            method: "GET",
            payload: nil,
            tracePayload: ["provider_request_id": requestId],
            mediaRefsJSON: "",
            operation: "queue_result",
            workflowStep: "fal_video_result",
            parentTraceId: polled.response.traceId,
            request: request
        )
        guard let videoURL = falVideoOutputURL(in: response.object) else {
            let eventTraceId = await recordImageToVideoLifecycleEvent(
                requestId: requestId,
                outcome: "result_invalid",
                detail: "The completed response contained no downloadable video.",
                remoteRequestMayContinue: false,
                parentTraceId: response.traceId,
                request: request
            )
            throw FALWorkflowFailure(
                jobId: requestId,
                traceId: eventTraceId,
                message: "FAL video request \(requestId) returned no downloadable video."
            )
        }

        var downloadRequest = URLRequest(url: videoURL)
        downloadRequest.httpMethod = "GET"
        downloadRequest.timeoutInterval = 1_800
        var recordedDownloadRequest = URLRequest(url: traceSafeMediaURL(videoURL))
        recordedDownloadRequest.httpMethod = "GET"
        let downloaded = try await TracedHTTPTransport.download(
            request: downloadRequest,
            recordedRequest: recordedDownloadRequest,
            metadata: traceMetadata(
                operation: "output_download",
                workflowStep: "fal_video_download",
                parentTraceId: response.traceId,
                requestTextJSON: inferenceTraceJSONString([
                    "provider_request_id": requestId,
                    "source": "provider_result",
                ]),
                mediaRefsJSON: "",
                responseHint: "video/mp4",
                request: request
            )
        )
        guard let http = downloaded.response, (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture("FAL video output download failed.")
        }
        try ensureDirectory(request.outputURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: request.outputURL.path) {
            try FileManager.default.removeItem(at: request.outputURL)
        }
        try FileManager.default.moveItem(
            at: downloaded.temporaryURL,
            to: request.outputURL
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: request.outputURL.path
        )
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        await InferenceTraceStore.shared.enrich(
            traceId: downloaded.traceId,
            providerRequestId: requestId,
            model: modelId,
            parsedOutputJSON: inferenceTraceJSONString([
                "local_artifact_id": request.artifactId,
                "content_type": http.value(forHTTPHeaderField: "content-type") ?? "video/mp4",
                "byte_count": byteCount,
            ])
        )

        let traceIds = falVideoUniqueStrings(
            [submitted.traceId] + polled.traceIds + [response.traceId, downloaded.traceId]
        )
        return FALImageToVideoResult(
            outputURL: request.outputURL,
            requestId: requestId,
            traceId: downloaded.traceId,
            traceIds: traceIds,
            providerNativeSize: providerNativeSize,
            responseSnapshot: [
                "request_id": requestId,
                "model": modelId,
                "duration_seconds": "\(request.durationSeconds)",
                "generate_audio": "\(request.generateAudio)",
                "resolution": resolution,
                "aspect_ratio": request.outputProfile.aspectRatio.rawValue,
                "content_type": http.value(forHTTPHeaderField: "content-type") ?? "video/mp4",
                "bytes": "\(byteCount)",
            ]
        )
    }

    func generateAudioToVideo(
        from request: FALAudioToVideoRequest
    ) async throws -> FALAudioToVideoResult {
        let apiKey = credentialStore.resolvedCredential(for: .fal).trimmed
        guard !apiKey.isEmpty else {
            throw ScreenGraphError.credentials(
                "Add a FAL API key in App Settings to render LTX 2.3."
            )
        }
        guard request.modelSelection == .falLTX23AudioToVideo else {
            throw ScreenGraphError.capture(
                "\(request.modelSelection.label) is not the FAL LTX narration model."
            )
        }
        guard request.audioDriverDurationSeconds >= 2,
              request.audioDriverDurationSeconds <= 20 else {
            throw ScreenGraphError.capture(
                "FAL LTX 2.3 accepts an exact narration duration from 2 to 20 seconds."
            )
        }

        let audioData = try Data(contentsOf: request.audioDriverURL)
        guard !audioData.isEmpty else {
            throw ScreenGraphError.capture("The narration driver was empty.")
        }
        let audioDigest = sha256Hex(audioData)
        let audioFileName = falAudioDriverUploadFileName(sha256: audioDigest)
        let audioUpload = try await uploadAudioDriver(
            request: request,
            apiKey: apiKey,
            audioData: audioData
        )
        let frameInput = try imageInput(at: request.startFrameURL, role: "start_frame")
        let providerPrompt = request.prompt.trimmed.nilIfEmpty
            ?? "Create coherent cinematic motion from the supplied frame, synchronized naturally to the supplied narration."
        let input: [String: Any] = [
            "audio_url": audioUpload.remoteURL.absoluteString,
            "image_url": frameInput.dataURI,
            "prompt": providerPrompt,
            "aspect_ratio": request.outputProfile.aspectRatio.rawValue,
        ]
        let traceInput: [String: Any] = [
            "audio_url": "<ephemeral hosted URL omitted; see media_refs_json>",
            "image_url": "<data URI omitted; see media_refs_json>",
            "prompt": providerPrompt,
            "aspect_ratio": request.outputProfile.aspectRatio.rawValue,
            "audio_duration_seconds": request.audioDriverDurationSeconds,
        ]
        let mediaRefsJSON = inferenceTraceJSONString([
            "inputs": [
                frameInput.traceSummary,
                [
                    "role": "narration_driver",
                    "file_name": audioFileName,
                    "mime_type": "audio/mp4",
                    "byte_count": audioData.count,
                    "sha256": audioDigest,
                    "duration_seconds": request.audioDriverDurationSeconds,
                ],
            ],
        ])
        let modelId = request.modelSelection.providerModelId
        let modelURL = queueURL(modelId: modelId)
        let submitted = try await sendImageToVideoJSON(
            apiKey: apiKey,
            url: modelURL,
            method: "POST",
            payload: input,
            tracePayload: traceInput,
            mediaRefsJSON: mediaRefsJSON,
            operation: "queue_submit",
            workflowStep: "fal_ltx_audio_video_submit",
            parentTraceId: audioUpload.traceIds.last ?? request.parentTraceId,
            request: request
        )
        let requestId = falVideoFirstString(
            in: submitted.object,
            keys: ["request_id", "requestId", "id"]
        )
        guard !requestId.isEmpty else {
            _ = await recordImageToVideoLifecycleEvent(
                requestId: "",
                outcome: "submission_accepted_without_request_id",
                detail: "The provider response did not include a resumable request id.",
                remoteRequestMayContinue: true,
                parentTraceId: submitted.traceId,
                request: request
            )
            throw ScreenGraphError.capture("FAL LTX submission returned no request id.")
        }
        await InferenceTraceStore.shared.enrich(
            traceId: submitted.traceId,
            providerRequestId: requestId,
            model: modelId
        )
        await request.onSubmitted?(requestId, submitted.traceId)

        let statusURL = falVideoFirstURL(
            in: submitted.object,
            keys: ["status_url", "statusUrl"]
        ) ?? modelURL.appendingPathComponent("requests")
            .appendingPathComponent(requestId)
            .appendingPathComponent("status")
        let responseURL = falVideoFirstURL(
            in: submitted.object,
            keys: ["response_url", "responseUrl"]
        ) ?? modelURL.appendingPathComponent("requests")
            .appendingPathComponent(requestId)
            .appendingPathComponent("response")
        let polled = try await pollImageToVideoStatus(
            apiKey: apiKey,
            url: statusURL,
            requestId: requestId,
            parentTraceId: submitted.traceId,
            request: request
        )
        let status = falVideoFirstString(in: polled.response.object, keys: ["status"])
            .uppercased()
        if status != "COMPLETED"
            || falVideoCompletedErrorSummary(in: polled.response.object) != nil {
            let detail = falVideoSafeTraceText(
                falVideoCompletedErrorSummary(in: polled.response.object)
                    ?? falVideoFailureSummary(from: polled.response.object)
            )
            let eventTraceId = await recordImageToVideoLifecycleEvent(
                requestId: requestId,
                outcome: "provider_failed",
                detail: detail,
                remoteRequestMayContinue: false,
                parentTraceId: polled.response.traceId,
                request: request
            )
            throw FALWorkflowFailure(
                jobId: requestId,
                traceId: eventTraceId,
                message: "FAL LTX request \(requestId) ended with \(status.isEmpty ? "unknown status" : status). \(detail)".trimmed
            )
        }

        let response = try await sendImageToVideoJSON(
            apiKey: apiKey,
            url: responseURL,
            method: "GET",
            payload: nil,
            tracePayload: ["provider_request_id": requestId],
            mediaRefsJSON: "",
            operation: "queue_result",
            workflowStep: "fal_ltx_audio_video_result",
            parentTraceId: polled.response.traceId,
            request: request
        )
        guard let videoURL = falVideoOutputURL(in: response.object) else {
            let eventTraceId = await recordImageToVideoLifecycleEvent(
                requestId: requestId,
                outcome: "result_invalid",
                detail: "The completed response contained no downloadable video.",
                remoteRequestMayContinue: false,
                parentTraceId: response.traceId,
                request: request
            )
            throw FALWorkflowFailure(
                jobId: requestId,
                traceId: eventTraceId,
                message: "FAL LTX request \(requestId) returned no downloadable video."
            )
        }

        var downloadRequest = URLRequest(url: videoURL)
        downloadRequest.httpMethod = "GET"
        downloadRequest.timeoutInterval = 1_800
        var recordedDownloadRequest = URLRequest(url: traceSafeMediaURL(videoURL))
        recordedDownloadRequest.httpMethod = "GET"
        let downloaded = try await TracedHTTPTransport.download(
            request: downloadRequest,
            recordedRequest: recordedDownloadRequest,
            metadata: traceMetadata(
                operation: "output_download",
                workflowStep: "fal_ltx_audio_video_download",
                parentTraceId: response.traceId,
                requestTextJSON: inferenceTraceJSONString([
                    "provider_request_id": requestId,
                    "source": "provider_result",
                ]),
                mediaRefsJSON: "",
                responseHint: "video/mp4",
                request: request
            )
        )
        guard let http = downloaded.response, (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture("FAL LTX output download failed.")
        }
        try ensureDirectory(request.outputURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: request.outputURL.path) {
            try FileManager.default.removeItem(at: request.outputURL)
        }
        try FileManager.default.moveItem(
            at: downloaded.temporaryURL,
            to: request.outputURL
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: request.outputURL.path
        )
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        await InferenceTraceStore.shared.enrich(
            traceId: downloaded.traceId,
            providerRequestId: requestId,
            model: modelId,
            parsedOutputJSON: inferenceTraceJSONString([
                "local_artifact_id": request.artifactId,
                "content_type": http.value(forHTTPHeaderField: "content-type") ?? "video/mp4",
                "byte_count": byteCount,
            ])
        )
        let traceIds = falVideoUniqueStrings(
            audioUpload.traceIds
                + [submitted.traceId]
                + polled.traceIds
                + [response.traceId, downloaded.traceId]
        )
        return FALAudioToVideoResult(
            outputURL: request.outputURL,
            requestId: requestId,
            traceId: downloaded.traceId,
            traceIds: traceIds,
            providerNativeSize: "\(request.outputProfile.width)x\(request.outputProfile.height)",
            responseSnapshot: [
                "request_id": requestId,
                "model": modelId,
                "audio_duration_seconds": String(format: "%.3f", request.audioDriverDurationSeconds),
                "aspect_ratio": request.outputProfile.aspectRatio.rawValue,
                "content_type": http.value(forHTTPHeaderField: "content-type") ?? "video/mp4",
                "bytes": "\(byteCount)",
            ]
        )
    }

    /// FAL's LTX worker validates audio by filename extension. A MIME-bearing
    /// data URI is decoded by the queue transport as `.bin`, so upload the
    /// exact driver under an explicit `.m4a` name before the paid submission.
    /// The public capability is random and expires after one hour; neither it
    /// nor the presigned PUT URL is captured in the trace database.
    private func uploadAudioDriver(
        request: FALAudioToVideoRequest,
        apiKey: String,
        audioData: Data
    ) async throws -> FALAudioDriverUpload {
        let digest = sha256Hex(audioData)
        let fileName = falAudioDriverUploadFileName(sha256: digest)
        let contentType = "audio/mp4"
        let mediaRefsJSON = inferenceTraceJSONString([
            "inputs": [[
                "role": "narration_driver",
                "file_name": fileName,
                "mime_type": contentType,
                "byte_count": audioData.count,
                "sha256": digest,
                "duration_seconds": request.audioDriverDurationSeconds,
            ]],
        ])
        let initiateURL = URL(
            string: "https://rest.fal.ai/storage/upload/initiate?storage_type=fal-cdn-v3"
        )!
        var initiate = URLRequest(url: initiateURL)
        initiate.httpMethod = "POST"
        initiate.timeoutInterval = 180
        initiate.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        initiate.setValue("application/json", forHTTPHeaderField: "Content-Type")
        initiate.setValue("application/json", forHTTPHeaderField: "Accept")
        initiate.setValue(
            publicOutputLifecycle,
            forHTTPHeaderField: "X-Fal-Object-Lifecycle-Preference"
        )
        initiate.setValue(
            publicOutputLifecycle,
            forHTTPHeaderField: "X-Fal-Object-Lifecycle"
        )
        initiate.httpBody = try JSONSerialization.data(withJSONObject: [
            "file_name": fileName,
            "content_type": contentType,
        ], options: [.sortedKeys])
        let initiated = try await TracedHTTPTransport.send(
            request: initiate,
            metadata: traceMetadata(
                operation: "cdn_upload_initiate",
                workflowStep: "fal_ltx_audio_upload_initiate",
                parentTraceId: request.parentTraceId,
                requestTextJSON: inferenceTraceJSONString([
                    "file_name": fileName,
                    "content_type": contentType,
                    "byte_count": audioData.count,
                    "sha256": digest,
                    "expiration_seconds": 3_600,
                ]),
                mediaRefsJSON: mediaRefsJSON,
                responseHint: "application/json",
                request: request
            )
        )
        guard let initiateHTTP = initiated.response,
              (200..<300).contains(initiateHTTP.statusCode),
              let object = try? JSONSerialization.jsonObject(
                  with: initiated.data
              ) as? [String: Any],
              let uploadURL = falVideoFirstURL(
                  in: object,
                  keys: ["upload_url", "uploadUrl"]
              ),
              let remoteURL = falVideoFirstURL(
                  in: object,
                  keys: ["file_url", "fileUrl"]
              ) else {
            throw ScreenGraphError.capture(
                "FAL narration upload initiation returned no usable upload URL."
            )
        }
        guard remoteURL.pathExtension.lowercased() == "m4a" else {
            throw ScreenGraphError.capture(
                "FAL narration storage did not preserve the required .m4a extension; no video request was submitted."
            )
        }
        await InferenceTraceStore.shared.enrichContext(
            traceId: initiated.traceId,
            responseTextJSON: inferenceTraceJSONString([
                "upload": "accepted",
                "file_extension": remoteURL.pathExtension.lowercased(),
            ])
        )

        var upload = URLRequest(url: uploadURL)
        upload.httpMethod = "PUT"
        upload.timeoutInterval = 1_800
        upload.setValue(contentType, forHTTPHeaderField: "Content-Type")
        var recordedUpload = URLRequest(
            url: URL(string: "https://fal.media/input-upload")!
        )
        recordedUpload.httpMethod = "PUT"
        recordedUpload.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let uploaded = try await TracedHTTPTransport.upload(
            request: upload,
            fromFile: request.audioDriverURL,
            recordedRequest: recordedUpload,
            metadata: traceMetadata(
                operation: "cdn_upload",
                workflowStep: "fal_ltx_audio_upload",
                parentTraceId: initiated.traceId,
                requestTextJSON: inferenceTraceJSONString([
                    "file_name": fileName,
                    "content_type": contentType,
                    "byte_count": audioData.count,
                    "sha256": digest,
                ]),
                mediaRefsJSON: mediaRefsJSON,
                responseHint: "application/json",
                request: request
            )
        )
        guard let uploadHTTP = uploaded.response,
              (200..<300).contains(uploadHTTP.statusCode) else {
            throw ScreenGraphError.capture("FAL narration-driver upload failed.")
        }
        await InferenceTraceStore.shared.enrich(
            traceId: uploaded.traceId,
            model: request.modelSelection.providerModelId,
            parsedOutputJSON: inferenceTraceJSONString([
                "uploaded": true,
                "file_extension": "m4a",
                "byte_count": audioData.count,
                "sha256": digest,
            ])
        )
        return FALAudioDriverUpload(
            remoteURL: remoteURL,
            traceIds: [initiated.traceId, uploaded.traceId]
        )
    }

    private func pollImageToVideoStatus(
        apiKey: String,
        url: URL,
        requestId: String,
        parentTraceId: String,
        request: any FALTrackedVideoRequest
    ) async throws -> (response: FALVideoJSONResponse, traceIds: [String]) {
        let started = Date()
        var delay: UInt64 = 2
        var parent = parentTraceId
        var traceIds: [String] = []
        do {
            while true {
                try Task.checkCancellation()
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                var queryItems = components?.queryItems ?? []
                if !queryItems.contains(where: { $0.name == "logs" }) {
                    queryItems.append(URLQueryItem(name: "logs", value: "1"))
                    components?.queryItems = queryItems
                }
                let result = try await sendImageToVideoJSON(
                    apiKey: apiKey,
                    url: components?.url ?? url,
                    method: "GET",
                    payload: nil,
                    tracePayload: ["provider_request_id": requestId],
                    mediaRefsJSON: "",
                    operation: "queue_status",
                    workflowStep: "fal_video_status",
                    parentTraceId: parent,
                    request: request
                )
                traceIds.append(result.traceId)
                parent = result.traceId
                let status = falVideoFirstString(in: result.object, keys: ["status"])
                    .uppercased()
                if terminalStates.contains(status) {
                    return (result, traceIds)
                }
                if Date().timeIntervalSince(started) > 1_800 {
                    throw ScreenGraphError.capture(
                        "FAL video request \(requestId) did not finish within 30 minutes."
                    )
                }
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(UInt64(Double(delay) * 1.5), 20)
            }
        } catch {
            _ = await recordImageToVideoLifecycleEvent(
                requestId: requestId,
                outcome: error is CancellationError || Task.isCancelled
                    ? "interrupted"
                    : "polling_stopped",
                detail: falVideoSafeTraceText(error.localizedDescription),
                remoteRequestMayContinue: true,
                parentTraceId: parent,
                request: request
            )
            throw error
        }
    }

    private func sendImageToVideoJSON(
        apiKey: String,
        url: URL,
        method: String,
        payload: [String: Any]?,
        tracePayload: [String: Any],
        mediaRefsJSON: String,
        operation: String,
        workflowStep: String,
        parentTraceId: String,
        request generationRequest: any FALTrackedVideoRequest
    ) async throws -> FALVideoJSONResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 180
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("LitScenes/1.0", forHTTPHeaderField: "User-Agent")
        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys]
            )
        }
        var recordedRequest = request
        recordedRequest.url = traceSafeQueueURL(url)
        let traced = try await TracedHTTPTransport.send(
            request: request,
            recordedRequest: recordedRequest,
            metadata: traceMetadata(
                operation: operation,
                workflowStep: workflowStep,
                parentTraceId: parentTraceId,
                requestTextJSON: inferenceTraceJSONString(tracePayload),
                mediaRefsJSON: mediaRefsJSON,
                responseHint: "application/json",
                request: generationRequest
            )
        )
        let object = try? JSONSerialization.jsonObject(with: traced.data) as? [String: Any]
        let safeResponse = object.map(falVideoTraceResponseSummary) ?? [
            "response": "non_json_body_omitted",
        ]
        await InferenceTraceStore.shared.enrichContext(
            traceId: traced.traceId,
            responseTextJSON: inferenceTraceJSONString(safeResponse)
        )
        guard let http = traced.response, (200..<300).contains(http.statusCode) else {
            let detail = falVideoSafeTraceText(
                object.map(falVideoFailureSummary(from:)) ?? ""
            )
            throw ScreenGraphError.capture(
                "FAL video \(operation) failed\(detail.isEmpty ? "." : ": \(detail)")"
            )
        }
        guard let object else {
            throw ScreenGraphError.capture(
                "FAL video \(operation) returned invalid JSON."
            )
        }
        return FALVideoJSONResponse(object: object, traceId: traced.traceId)
    }

    private func traceMetadata(
        operation: String,
        workflowStep: String,
        parentTraceId: String,
        requestTextJSON: String,
        mediaRefsJSON: String,
        responseHint: String,
        request generationRequest: any FALTrackedVideoRequest
    ) -> InferenceTraceRequestMetadata {
        InferenceTraceRequestMetadata(
            provider: "fal",
            apiFamily: "video",
            operation: operation,
            projectId: generationRequest.projectId,
            runId: generationRequest.runId,
            traceGroupId: generationRequest.traceGroupId,
            parentTraceId: parentTraceId,
            workflowName: generationRequest.workflowName.trimmed.nilIfEmpty
                ?? "shot_render",
            workflowStep: workflowStep,
            artifactType: generationRequest.artifactType.trimmed.nilIfEmpty
                ?? "shot_render_segment",
            artifactId: generationRequest.artifactId,
            model: generationRequest.modelSelection.providerModelId,
            requestBodyFormat: requestTextJSON.isEmpty ? "none" : "application/json",
            responseBodyFormatHint: responseHint,
            requestTextJSON: requestTextJSON,
            mediaRefsJSON: mediaRefsJSON,
            providerRequestIDHeaderCandidates: [
                "x-fal-request-id",
                "x-request-id",
                "request-id",
            ],
            captureRequestBody: false,
            captureResponseBody: false
        )
    }

    private func recordImageToVideoLifecycleEvent(
        requestId: String,
        outcome: String,
        detail: String,
        remoteRequestMayContinue: Bool,
        parentTraceId: String,
        request generationRequest: any FALTrackedVideoRequest
    ) async -> String {
        let safeRequestId = requestId.trimmed.nilIfEmpty ?? "unknown"
        var eventRequest = URLRequest(
            url: queueURL(modelId: generationRequest.modelSelection.providerModelId)
                .appendingPathComponent("requests")
                .appendingPathComponent(safeRequestId)
                .appendingPathComponent("local-lifecycle")
        )
        eventRequest.httpMethod = "EVENT"
        var metadata = traceMetadata(
            operation: outcome,
            workflowStep: "fal_video_\(outcome)",
            parentTraceId: parentTraceId,
            requestTextJSON: inferenceTraceJSONString([
                "provider_request_id": requestId,
                "remote_cancel_requested": false,
                "retry_requires_new_paid_submission": true,
            ]),
            mediaRefsJSON: "",
            responseHint: "application/json",
            request: generationRequest
        )
        metadata.responseTextJSON = inferenceTraceJSONString([
            "outcome": outcome,
            "detail": falVideoSafeTraceText(detail),
            "remote_request_may_continue": remoteRequestMayContinue,
        ])
        return await InferenceTraceStore.shared.recordEvent(
            request: eventRequest,
            metadata: metadata
        )
    }

    private func queueURL(modelId: String) -> URL {
        modelId.split(separator: "/").reduce(queueBaseURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
    }

    private func imageInput(
        at url: URL,
        role: String
    ) throws -> (dataURI: String, traceSummary: [String: Any]) {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw ScreenGraphError.capture("The \(role.replacingOccurrences(of: "_", with: " ")) image was empty.")
        }
        return (
            "data:image/png;base64,\(data.base64EncodedString())",
            [
                "role": role,
                "file_name": url.lastPathComponent,
                "mime_type": "image/png",
                "byte_count": data.count,
                "sha256": sha256Hex(data),
            ]
        )
    }

    private func traceSafeMediaURL(_ url: URL) -> URL {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        components.path = "/provider-output"
        return components.url ?? URL(string: "https://fal.media/provider-output")!
    }

    private func traceSafeQueueURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.user = nil
        components?.password = nil
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? queueBaseURL
    }

    func generateJoinBridge(from request: FALJoinBridgeRequest) async throws -> FALJoinBridgeResult {
        let apiKey = credentialStore.resolvedCredential(for: .fal)
        guard !apiKey.trimmed.isEmpty else {
            throw ScreenGraphError.credentials("Add a FAL API key in App Settings to render this join.")
        }
        guard request.provider.supportedDurations.contains(request.durationSeconds) else {
            throw ScreenGraphError.capture(
                "\(request.provider.label) does not support a \(request.durationSeconds)-second bridge."
            )
        }
        let outgoing = try imageDataURI(at: request.outgoingFrameURL)
        let incoming = try imageDataURI(at: request.incomingFrameURL)
        var input: [String: Any]
        switch request.provider {
        case .falViduQ3:
            input = [
                "prompt": request.prompt,
                "image_url": outgoing,
                "end_image_url": incoming,
                "duration": request.durationSeconds,
                "resolution": request.resolution,
                "audio": false,
            ]
        case .falKlingO1:
            input = [
                "prompt": request.prompt,
                "start_image_url": outgoing,
                "end_image_url": incoming,
                "duration": "\(request.durationSeconds)",
            ]
        }

        let modelURL = queueBaseURL.appendingPathComponent(request.provider.modelId)
        let submitted = try await sendJSON(
            apiKey: apiKey,
            url: modelURL,
            method: "POST",
            payload: input,
            operation: "queue_submit",
            request: request
        )
        let requestId = falVideoFirstString(in: submitted.object, keys: ["request_id", "requestId", "id"])
        guard !requestId.isEmpty else {
            throw ScreenGraphError.capture("FAL join-bridge submission returned no request id.")
        }
        let statusURL = falVideoFirstURL(in: submitted.object, keys: ["status_url", "statusUrl"])
            ?? modelURL.appendingPathComponent("requests").appendingPathComponent(requestId).appendingPathComponent("status")
        let responseURL = falVideoFirstURL(in: submitted.object, keys: ["response_url", "responseUrl"])
            ?? modelURL.appendingPathComponent("requests").appendingPathComponent(requestId).appendingPathComponent("response")

        let final = try await pollStatus(
            apiKey: apiKey,
            url: statusURL,
            requestId: requestId,
            request: request
        )
        let status = falVideoFirstString(in: final.object, keys: ["status"]).uppercased()
        guard status == "COMPLETED" else {
            let detail = falVideoFailureSummary(from: final.object)
            throw FALWorkflowFailure(
                jobId: requestId,
                traceId: final.traceId,
                message: "FAL join bridge \(requestId) ended with \(status.isEmpty ? "unknown status" : status). \(detail)".trimmed
            )
        }

        let response = try await sendJSON(
            apiKey: apiKey,
            url: responseURL,
            method: "GET",
            payload: nil,
            operation: "queue_result",
            request: request
        )
        guard let videoURL = falVideoOutputURL(in: response.object) else {
            throw ScreenGraphError.capture("FAL join bridge \(requestId) returned no downloadable video.")
        }
        try ensureDirectory(request.outputURL.deletingLastPathComponent())
        let (temporaryURL, urlResponse) = try await URLSession.shared.download(from: videoURL)
        guard let http = urlResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture("FAL join-bridge download failed.")
        }
        if FileManager.default.fileExists(atPath: request.outputURL.path) {
            try FileManager.default.removeItem(at: request.outputURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: request.outputURL)
        return FALJoinBridgeResult(
            outputURL: request.outputURL,
            requestId: requestId,
            traceId: response.traceId.isEmpty ? final.traceId : response.traceId
        )
    }

    private func pollStatus(
        apiKey: String,
        url: URL,
        requestId: String,
        request: FALJoinBridgeRequest
    ) async throws -> FALVideoJSONResponse {
        let started = Date()
        var delay: UInt64 = 2
        while true {
            try Task.checkCancellation()
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var queryItems = components?.queryItems ?? []
            if !queryItems.contains(where: { $0.name == "logs" }) {
                queryItems.append(URLQueryItem(name: "logs", value: "1"))
                components?.queryItems = queryItems
            }
            let result = try await sendJSON(
                apiKey: apiKey,
                url: components?.url ?? url,
                method: "GET",
                payload: nil,
                operation: "queue_status",
                request: request
            )
            let status = falVideoFirstString(in: result.object, keys: ["status"]).uppercased()
            if terminalStates.contains(status) { return result }
            if Date().timeIntervalSince(started) > 1_200 {
                throw ScreenGraphError.capture("FAL join bridge \(requestId) did not finish within 20 minutes.")
            }
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay = min(UInt64(Double(delay) * 1.5), 20)
        }
    }

    private func sendJSON(
        apiKey: String,
        url: URL,
        method: String,
        payload: [String: Any]?,
        operation: String,
        request generationRequest: FALJoinBridgeRequest
    ) async throws -> FALVideoJSONResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 180
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("LitScenes/1.0", forHTTPHeaderField: "User-Agent")
        if let payload {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        }
        let traced = try await TracedHTTPTransport.send(
            request: request,
            metadata: InferenceTraceRequestMetadata(
                provider: "fal",
                apiFamily: "video",
                operation: operation,
                projectId: generationRequest.projectId,
                runId: generationRequest.artifactId,
                traceGroupId: "shot_join_\(generationRequest.shotId)",
                workflowName: "shot_join_repair",
                workflowStep: "fal_video_\(operation)",
                artifactType: "shot_join_bridge",
                artifactId: generationRequest.artifactId,
                model: generationRequest.provider.modelId,
                requestBodyFormat: payload == nil ? "none" : "application/json",
                responseBodyFormatHint: "application/json",
                requestTextJSON: "",
                providerRequestIDHeaderCandidates: ["x-fal-request-id", "x-request-id", "request-id"],
                captureRequestBody: false,
                captureResponseBody: false
            )
        )
        guard let http = traced.response, (200..<300).contains(http.statusCode) else {
            let body = String(data: traced.data.prefix(1_200), encoding: .utf8) ?? ""
            throw ScreenGraphError.capture("FAL join bridge \(operation) failed: \(body)")
        }
        guard let object = try JSONSerialization.jsonObject(with: traced.data) as? [String: Any] else {
            throw ScreenGraphError.capture("FAL join bridge \(operation) returned invalid JSON.")
        }
        return FALVideoJSONResponse(object: object, traceId: traced.traceId)
    }

    private func imageDataURI(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else {
            throw ScreenGraphError.capture("A join boundary frame was empty.")
        }
        return "data:image/png;base64,\(data.base64EncodedString())"
    }
}

private struct FALVideoJSONResponse {
    var object: [String: Any]
    var traceId: String
}

private func falVideoUniqueStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter {
        let value = $0.trimmed
        guard !value.isEmpty, !seen.contains(value) else { return false }
        seen.insert(value)
        return true
    }
}

/// Internal so the provider-contract test can pin the format identity that
/// LTX validates after FAL storage resolves the URL.
func falAudioDriverUploadFileName(sha256: String) -> String {
    let safeDigest = sha256.lowercased().filter { $0.isHexDigit }
    return "narration_driver_\(safeDigest.prefix(12)).m4a"
}

private func falVideoTraceResponseSummary(
    _ dictionary: [String: Any]
) -> [String: Any] {
    var summary: [String: Any] = [:]
    for key in [
        "status",
        "request_id",
        "requestId",
        "id",
        "error_type",
        "errorType",
        "seed",
    ] {
        if let value = dictionary[key] as? String, !value.trimmed.isEmpty {
            summary[key] = falVideoSafeTraceText(value)
        } else if let value = dictionary[key] as? NSNumber {
            summary[key] = value
        }
    }
    for key in ["error", "message", "detail", "reason"] {
        if let value = dictionary[key] {
            let safeText = falVideoSafeTraceText(falVideoFailureSummary(from: value))
            if !safeText.isEmpty {
                summary[key] = safeText
            }
        }
    }
    if let video = dictionary["video"] as? [String: Any] {
        var videoSummary: [String: Any] = [:]
        for key in ["content_type", "file_name", "file_size"] {
            if let value = video[key] as? String {
                videoSummary[key] = falVideoSafeTraceText(value)
            } else if let value = video[key] as? NSNumber {
                videoSummary[key] = value
            }
        }
        if !videoSummary.isEmpty {
            summary["video"] = videoSummary
        }
    }
    return summary.isEmpty ? ["response": "fields_omitted"] : summary
}

private func falVideoSafeTraceText(_ value: String) -> String {
    String(
        value
            .replacingOccurrences(
                of: #"https?://\S+"#,
                with: "<url omitted>",
                options: .regularExpression
            )
            .prefix(1_000)
    )
}

private func falVideoFirstString(in dictionary: [String: Any], keys: [String]) -> String {
    for key in keys {
        if let value = dictionary[key] as? String, !value.trimmed.isEmpty { return value.trimmed }
        if let value = dictionary[key] as? NSNumber { return value.stringValue }
    }
    return ""
}

private func falVideoFirstURL(in dictionary: [String: Any], keys: [String]) -> URL? {
    for key in keys {
        if let value = dictionary[key] as? String, let url = URL(string: value) { return url }
    }
    return nil
}

private func falVideoOutputURL(in value: Any) -> URL? {
    if let dictionary = value as? [String: Any] {
        if let video = dictionary["video"] as? String, let url = URL(string: video) {
            return url
        }
        if let video = dictionary["video"] as? [String: Any],
           let url = falVideoFirstURL(in: video, keys: ["url"]) {
            return url
        }
        for nested in dictionary.values {
            if let url = falVideoOutputURL(in: nested) { return url }
        }
    } else if let array = value as? [Any] {
        for nested in array {
            if let url = falVideoOutputURL(in: nested) { return url }
        }
    }
    return nil
}

/// A provider validation failure names the field it rejected, in Pydantic's
/// `loc`. Keeping it is the whole difference between "Input should be 2, 3, …
/// or 15" and "duration: Input should be 2, 3, … or 15" — the first cost an
/// afternoon of reading provider schemas by hand to work out which of a dozen
/// fields was wrong, and by what.
/// Internal rather than private only so a test can pin it: dropping the field
/// name is a silent regression that costs its next reader an afternoon.
func falVideoValidationSummary(from dictionary: [String: Any]) -> String? {
    guard let message = (dictionary["msg"] as? String)?.trimmed.nilIfEmpty else { return nil }
    let field = (dictionary["loc"] as? [Any])?
        .compactMap { $0 as? String }
        .filter { $0 != "body" }
        .joined(separator: ".")
    guard let field, !field.isEmpty else { return message }
    return "\(field): \(message)"
}

private func falVideoFailureSummary(from value: Any) -> String {
    if let dictionary = value as? [String: Any] {
        if let validation = falVideoValidationSummary(from: dictionary) {
            return validation
        }
        for key in ["error", "message", "detail", "reason", "msg"] {
            if let message = dictionary[key] as? String, !message.trimmed.isEmpty {
                return message.trimmed
            }
        }
        for nested in dictionary.values {
            let summary = falVideoFailureSummary(from: nested)
            if !summary.isEmpty { return summary }
        }
    } else if let array = value as? [Any] {
        for nested in array {
            let summary = falVideoFailureSummary(from: nested)
            if !summary.isEmpty { return summary }
        }
    }
    return ""
}

/// FAL reports validation/execution failures as a terminal COMPLETED queue
/// state with top-level error fields. Inspect only those fields so ordinary
/// success logs such as "Done" are never mistaken for an error.
private func falVideoCompletedErrorSummary(in dictionary: [String: Any]) -> String? {
    let errorType = falVideoFirstString(in: dictionary, keys: ["error_type", "errorType"])
    let errorSummary = dictionary["error"].map(falVideoFailureSummary(from:)) ?? ""
    guard !errorType.isEmpty || !errorSummary.isEmpty else { return nil }
    if errorType.isEmpty { return errorSummary }
    if errorSummary.isEmpty { return errorType }
    return "\(errorType): \(errorSummary)"
}
