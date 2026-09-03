import Foundation

struct FALImageReference: Sendable {
    var data: Data
    var mimeType: String
    var fileName: String
    var role: String = "style"
    var title: String = ""

    var dataURI: String {
        "data:\(mimeType.trimmed.isEmpty ? "image/png" : mimeType.trimmed);base64,\(data.base64EncodedString())"
    }

    var traceSummary: [String: Any] {
        let size = imagePixelSize(from: data)
        return [
            "role": role,
            "file_name": fileName,
            "mime_type": mimeType.trimmed.isEmpty ? "image/png" : mimeType.trimmed,
            "title": title,
            "byte_count": data.count,
            "sha256": sha256Hex(data),
            "width": size?.width ?? 0,
            "height": size?.height ?? 0
        ]
    }
}

struct FALImageGenerationRequest: Sendable {
    var artifactId: String
    var stack: RenderStack
    var prompt: String
    var mediaPlan: LensMediaPlan
    var styleMode: LensRenderStyleMode
    /// Reference images riding the request as `image_urls`, in merge order.
    /// The caller has already capped the count at the stack's declared
    /// `nativePromptImageLimit`.
    var styleReferences: [FALImageReference] = []
    var outpaintInput: FALImageOutpaintInput? = nil
    var debugParametersJSON: String = ""
    var projectId: String = ""
    var runId: String = ""
    var traceGroupId: String = ""
    var workflowName: String = "lenses"
}

extension FALImageClient {
    /// The request's input images as trace media refs: reference images in merge
    /// order, then an outpaint source when one rides.
    static func sourceMediaRefs(_ request: FALImageGenerationRequest) -> [[String: Any]] {
        var refs = request.styleReferences.map(\.traceSummary)
        if let outpaint = request.outpaintInput {
            var source = outpaint.source.traceSummary
            source["role"] = "outpaint_source"
            refs.append(source)
        }
        return refs
    }
}

struct FALImageOutpaintInput: Sendable {
    var source: FALImageReference
    var expandLeft: Int
    var expandRight: Int
    var expandTop: Int
    var expandBottom: Int

    var traceSummary: [String: Any] {
        [
            "source": source.traceSummary,
            "expand_left": expandLeft,
            "expand_right": expandRight,
            "expand_top": expandTop,
            "expand_bottom": expandBottom
        ]
    }
}

struct FALImageGenerationResult: Sendable {
    var imageData: Data
    var providerJobId: String
    var traceId: String
    var modelId: String
    var seed: String
    var parameters: [LensRenderRecipeParameter]
}

struct FALWorkflowFailure: LocalizedError {
    var jobId: String
    var traceId: String
    var message: String

    var errorDescription: String? { message }
}

struct FALImageClient {
    let credentialStore: LitScenesCredentialResolving

    private let queueBaseURL = URL(string: "https://queue.fal.run")!
    private let terminalStates: Set<String> = ["COMPLETED", "FAILED", "CANCELLED", "CANCELED"]

    func generateImage(from request: FALImageGenerationRequest) async throws -> FALImageGenerationResult {
        let apiKey = credentialStore.resolvedCredential(for: .fal)
        guard !apiKey.trimmed.isEmpty else {
            throw ScreenGraphError.credentials("FAL_API_KEY or FAL_KEY is required to generate FAL Lens images.")
        }
        guard request.stack.isFAL else {
            throw ScreenGraphError.capture("Render stack \(request.stack.id) is not a FAL stack.")
        }
        let modelId = request.stack.falModelId(styleMode: request.styleMode)
        guard !modelId.isEmpty else {
            throw ScreenGraphError.capture("FAL model id is missing for \(request.stack.label).")
        }
        let overrides = try Self.parameterOverrides(
            from: request.debugParametersJSON,
            stack: request.stack,
            styleMode: request.styleMode
        )
        let providerPrompt = request.outpaintInput == nil
            ? providerPromptLimited(request.prompt, maxCharacters: request.stack.falPromptLimit)
            : falOutpaintProviderPrompt(request.prompt, maxCharacters: request.stack.falPromptLimit)
        var input = request.stack.falBaseInput(
            prompt: providerPrompt,
            mediaPlan: request.mediaPlan,
            styleMode: request.styleMode
        )
        if let outpaint = request.outpaintInput {
            guard request.stack.id == RenderStackID.falOutpaint else {
                throw ScreenGraphError.capture("FAL outpaint input requires the FAL Outpaint render stack.")
            }
            input["image_url"] = outpaint.source.dataURI
            input["expand_left"] = min(max(outpaint.expandLeft, 0), 700)
            input["expand_right"] = min(max(outpaint.expandRight, 0), 700)
            input["expand_top"] = min(max(outpaint.expandTop, 0), 700)
            input["expand_bottom"] = min(max(outpaint.expandBottom, 0), 700)
        } else if request.styleMode == .attachStyleImage {
            guard !request.styleReferences.isEmpty else {
                throw ScreenGraphError.capture("Attach style image was selected, but no verified style image was available.")
            }
            if !request.stack.canAttachStyleImage {
                // e.g. FLUX Schnell: its Redux variant is image-only; keep
                // prompt-capable generation on the base endpoint.
                throw ScreenGraphError.capture("\(request.stack.label) does not currently support prompt-aware style attachments on FAL. Use Describe style in prompt for this stack.")
            }
            input["image_urls"] = request.styleReferences.map(\.dataURI)
        }
        for (key, value) in overrides {
            input[key] = value
        }
        let traceInput = sanitizedFALInputForTrace(input)
        var tracePayload: [String: Any] = [
            "model": modelId,
            "input": traceInput
        ]
        if !request.styleReferences.isEmpty {
            tracePayload["style_references"] = request.styleReferences.map(\.traceSummary)
        }
        if let outpaint = request.outpaintInput {
            tracePayload["outpaint"] = outpaint.traceSummary
        }
        let submitted = try await postJSON(
            apiKey: apiKey,
            url: queueURL(modelId: modelId),
            payload: input,
            tracePayload: tracePayload,
            operation: "queue_submit",
            workflowStep: workflowStep("submit", request: request),
            modelId: modelId,
            parentTraceId: "",
            request: request
        )
        let jobId = firstString(in: submitted.object, keys: ["request_id", "requestId", "id"])
        guard !jobId.isEmpty else {
            _ = await recordLifecycleEvent(
                requestId: "",
                modelId: modelId,
                outcome: "submission_accepted_without_request_id",
                detail: "The provider response did not include a resumable request id.",
                remoteRequestMayContinue: true,
                parentTraceId: submitted.traceId,
                request: request
            )
            throw ScreenGraphError.capture("FAL image submit returned no request id.")
        }
        await InferenceTraceStore.shared.enrich(
            traceId: submitted.traceId,
            providerRequestId: jobId,
            model: modelId
        )
        // THE TRACE SOURCES LAW: every input image rides the submit row as
        // `sources` (role, file name, sha256, bytes, size) — what the evals read.
        let sourceRefs = Self.sourceMediaRefs(request)
        if !sourceRefs.isEmpty {
            await InferenceTraceStore.shared.enrichContext(
                traceId: submitted.traceId,
                mediaRefsJSON: inferenceTraceJSONString(["sources": sourceRefs])
            )
        }
        let statusURL = firstURL(in: submitted.object, keys: ["status_url", "statusUrl"])
            ?? queueURL(modelId: modelId).appendingPathComponent("requests").appendingPathComponent(jobId).appendingPathComponent("status")
        let responseURL = firstURL(in: submitted.object, keys: ["response_url", "responseUrl"])
            ?? queueURL(modelId: modelId).appendingPathComponent("requests").appendingPathComponent(jobId).appendingPathComponent("response")
        let polled = try await pollStatus(
            apiKey: apiKey,
            url: statusURL,
            jobId: jobId,
            modelId: modelId,
            parentTraceId: submitted.traceId,
            request: request
        )
        let final = polled.response
        let status = firstString(in: final.object, keys: ["status"]).uppercased()
        if status != "COMPLETED" || containsFailure(in: final.object) {
            let detail = safeFALImageTraceText(workflowFailureSummary(from: final.object))
            let message = uniqueNonEmpty([
                "FAL image request \(jobId) ended with status \(status.isEmpty ? "unknown" : status).",
                detail
            ]).joined(separator: " ")
            let eventTraceId = await recordLifecycleEvent(
                requestId: jobId,
                modelId: modelId,
                outcome: "provider_failed",
                detail: detail,
                remoteRequestMayContinue: false,
                parentTraceId: final.traceId,
                request: request
            )
            throw FALWorkflowFailure(jobId: jobId, traceId: eventTraceId, message: message)
        }
        let result: FALJSONResponse
        do {
            result = try await getJSON(
                apiKey: apiKey,
                url: responseURL,
                operation: "queue_result",
                workflowStep: workflowStep("result", request: request),
                modelId: modelId,
                parentTraceId: final.traceId,
                tracePayload: ["provider_request_id": jobId],
                request: request
            )
        } catch {
            _ = await recordLifecycleEvent(
                requestId: jobId,
                modelId: modelId,
                outcome: "result_retrieval_stopped",
                detail: safeFALImageTraceText(error.localizedDescription),
                remoteRequestMayContinue: false,
                parentTraceId: final.traceId,
                request: request
            )
            throw error
        }
        guard let imageURL = outputImageURLs(from: result.object).first else {
            let eventTraceId = await recordLifecycleEvent(
                requestId: jobId,
                modelId: modelId,
                outcome: "result_invalid",
                detail: "The completed response contained no downloadable image.",
                remoteRequestMayContinue: false,
                parentTraceId: result.traceId,
                request: request
            )
            throw FALWorkflowFailure(
                jobId: jobId,
                traceId: eventTraceId,
                message: "FAL image request \(jobId) produced no downloadable image."
            )
        }
        let downloaded: FALImageDownload
        do {
            downloaded = try await downloadData(
                url: imageURL,
                requestId: jobId,
                modelId: modelId,
                parentTraceId: result.traceId,
                request: request
            )
        } catch {
            _ = await recordLifecycleEvent(
                requestId: jobId,
                modelId: modelId,
                outcome: "download_stopped",
                detail: safeFALImageTraceText(error.localizedDescription),
                remoteRequestMayContinue: false,
                parentTraceId: result.traceId,
                request: request
            )
            throw error
        }
        let seed = firstSeed(in: result.object)
        let parameters = recipeParameters(
            modelId: modelId,
            styleMode: request.styleMode,
            input: input,
            seed: seed,
            output: downloaded
        )
        return FALImageGenerationResult(
            imageData: downloaded.data,
            providerJobId: jobId,
            traceId: downloaded.traceId,
            modelId: modelId,
            seed: seed,
            parameters: parameters
        )
    }

    static func parameterOverrides(
        from json: String,
        stack: RenderStack,
        styleMode: LensRenderStyleMode
    ) throws -> [String: Any] {
        let cleaned = json.trimmed
        guard !cleaned.isEmpty else { return [:] }
        guard let data = cleaned.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScreenGraphError.capture("FAL debug parameters must be a JSON object.")
        }
        let allowed = Set(stack.falDebugParameterKeys(styleMode: styleMode))
        var sanitized: [String: Any] = [:]
        for (key, value) in object {
            let normalizedKey = key.trimmed
            guard allowed.contains(normalizedKey) else {
                throw ScreenGraphError.capture("FAL debug parameter \"\(normalizedKey)\" is not supported for \(stack.label).")
            }
            guard isSupportedJSONValue(value) else {
                throw ScreenGraphError.capture("FAL debug parameter \"\(normalizedKey)\" has an unsupported value.")
            }
            sanitized[normalizedKey] = value
        }
        return sanitized
    }

    static func validateDebugParameters(_ json: String, stack: RenderStack, styleMode: LensRenderStyleMode) -> String {
        do {
            _ = try parameterOverrides(from: json, stack: stack, styleMode: styleMode)
            return ""
        } catch {
            return error.localizedDescription
        }
    }

    private func queueURL(modelId: String) -> URL {
        modelId.split(separator: "/").reduce(queueBaseURL) { partial, component in
            partial.appendingPathComponent(String(component))
        }
    }

    private func workflowStep(_ phase: String, request: FALImageGenerationRequest) -> String {
        "\(request.outpaintInput == nil ? "fal_image" : "fal_outpaint")_\(phase)"
    }

    private func postJSON(
        apiKey: String,
        url: URL,
        payload: [String: Any],
        tracePayload: [String: Any],
        operation: String,
        workflowStep: String,
        modelId: String,
        parentTraceId: String,
        request generationRequest: FALImageGenerationRequest
    ) async throws -> FALJSONResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("LitScenes/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        var recordedRequest = request
        recordedRequest.url = traceSafeFALQueueURL(url)
        let traced = try await TracedHTTPTransport.send(
            request: request,
            recordedRequest: recordedRequest,
            metadata: traceMetadata(
                operation: operation,
                workflowStep: workflowStep,
                modelId: modelId,
                parentTraceId: parentTraceId,
                generationRequest: generationRequest,
                requestTextJSON: inferenceTraceJSONString(tracePayload),
                responseHint: "application/json"
            )
        )
        let data = traced.data
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        await InferenceTraceStore.shared.enrichContext(
            traceId: traced.traceId,
            responseTextJSON: inferenceTraceJSONString(
                object.map(falImageTraceResponseSummary) ?? ["response": "non_json_body_omitted"]
            )
        )
        guard let http = traced.response, (200..<300).contains(http.statusCode) else {
            let detail = safeFALImageTraceText(object.map(workflowFailureSummary(from:)) ?? "")
            throw ScreenGraphError.capture("FAL image \(operation) failed\(detail.isEmpty ? "." : ": \(detail)")")
        }
        guard let object else {
            throw ScreenGraphError.capture("FAL image \(operation) response was not JSON.")
        }
        return FALJSONResponse(object: object, traceId: traced.traceId)
    }

    private func getJSON(
        apiKey: String,
        url: URL,
        operation: String,
        workflowStep: String,
        modelId: String,
        parentTraceId: String,
        tracePayload: [String: Any],
        request generationRequest: FALImageGenerationRequest
    ) async throws -> FALJSONResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 180
        request.setValue("Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("LitScenes/1.0", forHTTPHeaderField: "User-Agent")
        var recordedRequest = request
        recordedRequest.url = traceSafeFALQueueURL(url)
        let traced = try await TracedHTTPTransport.send(
            request: request,
            recordedRequest: recordedRequest,
            metadata: traceMetadata(
                operation: operation,
                workflowStep: workflowStep,
                modelId: modelId,
                parentTraceId: parentTraceId,
                generationRequest: generationRequest,
                requestTextJSON: inferenceTraceJSONString(tracePayload),
                responseHint: "application/json"
            )
        )
        let data = traced.data
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        await InferenceTraceStore.shared.enrichContext(
            traceId: traced.traceId,
            responseTextJSON: inferenceTraceJSONString(
                object.map(falImageTraceResponseSummary) ?? ["response": "non_json_body_omitted"]
            )
        )
        guard let http = traced.response, (200..<300).contains(http.statusCode) else {
            let detail = safeFALImageTraceText(object.map(workflowFailureSummary(from:)) ?? "")
            throw ScreenGraphError.capture("FAL image \(operation) failed\(detail.isEmpty ? "." : ": \(detail)")")
        }
        guard let object else {
            throw ScreenGraphError.capture("FAL image \(operation) response was not JSON.")
        }
        return FALJSONResponse(object: object, traceId: traced.traceId)
    }

    private func pollStatus(
        apiKey: String,
        url: URL,
        jobId: String,
        modelId: String,
        parentTraceId: String,
        request generationRequest: FALImageGenerationRequest
    ) async throws -> (response: FALJSONResponse, traceIds: [String]) {
        let started = Date()
        var delay: UInt64 = 2
        var parent = parentTraceId
        var traceIds: [String] = []
        do {
            while true {
                try Task.checkCancellation()
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                if components?.queryItems?.contains(where: { $0.name == "logs" }) != true {
                    var queryItems = components?.queryItems ?? []
                    queryItems.append(URLQueryItem(name: "logs", value: "1"))
                    components?.queryItems = queryItems
                }
                let statusURL = components?.url ?? url
                let response = try await getJSON(
                    apiKey: apiKey,
                    url: statusURL,
                    operation: "queue_status",
                    workflowStep: workflowStep("status", request: generationRequest),
                    modelId: modelId,
                    parentTraceId: parent,
                    tracePayload: ["provider_request_id": jobId],
                    request: generationRequest
                )
                traceIds.append(response.traceId)
                parent = response.traceId
                let status = firstString(in: response.object, keys: ["status"]).uppercased()
                if terminalStates.contains(status) {
                    return (response, traceIds)
                }
                if Date().timeIntervalSince(started) > 900 {
                    throw ScreenGraphError.capture("FAL image request \(jobId) did not finish within 15 minutes.")
                }
                try await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(UInt64(Double(delay) * 1.5), 20)
            }
        } catch {
            _ = await recordLifecycleEvent(
                requestId: jobId,
                modelId: modelId,
                outcome: error is CancellationError || Task.isCancelled
                    ? "interrupted"
                    : "polling_stopped",
                detail: safeFALImageTraceText(error.localizedDescription),
                remoteRequestMayContinue: true,
                parentTraceId: parent,
                request: generationRequest
            )
            throw error
        }
    }

    private func traceMetadata(
        operation: String,
        workflowStep: String,
        modelId: String,
        parentTraceId: String,
        generationRequest: FALImageGenerationRequest,
        requestTextJSON: String,
        responseHint: String
    ) -> InferenceTraceRequestMetadata {
        InferenceTraceRequestMetadata(
            provider: "fal",
            apiFamily: "image",
            operation: operation,
            projectId: generationRequest.projectId,
            runId: generationRequest.runId,
            traceGroupId: generationRequest.traceGroupId,
            parentTraceId: parentTraceId,
            workflowName: generationRequest.workflowName.trimmed.isEmpty ? "lenses" : generationRequest.workflowName.trimmed,
            workflowStep: workflowStep,
            artifactType: "lens_hero",
            artifactId: generationRequest.artifactId,
            model: modelId,
            requestBodyFormat: requestTextJSON.isEmpty ? "none" : "application/json",
            responseBodyFormatHint: responseHint,
            requestTextJSON: requestTextJSON,
            providerRequestIDHeaderCandidates: ["x-fal-request-id", "x-request-id", "request-id"],
            captureRequestBody: false,
            captureResponseBody: false
        )
    }

    private func recipeParameters(
        modelId: String,
        styleMode: LensRenderStyleMode,
        input: [String: Any],
        seed: String,
        output: FALImageDownload
    ) -> [LensRenderRecipeParameter] {
        var parameters = [
            LensRenderRecipeParameter(key: "endpoint", value: modelId),
            LensRenderRecipeParameter(key: "style_mode", value: styleMode.rawValue),
            LensRenderRecipeParameter(key: "output_sha256", value: output.sha256),
            LensRenderRecipeParameter(key: "output_bytes", value: String(output.data.count), valueType: "number"),
            LensRenderRecipeParameter(key: "output_content_type", value: output.contentType),
        ]
        let sortedKeys = input.keys.sorted()
        for key in sortedKeys where key != "prompt" && key != "image_urls" && key != "image_url" {
            parameters.append(LensRenderRecipeParameter(key: key, value: recipeStringValue(input[key] ?? ""), valueType: recipeValueType(input[key] ?? "")))
        }
        if !seed.isEmpty {
            parameters.append(LensRenderRecipeParameter(key: "seed", value: seed, valueType: "integer"))
        }
        return parameters.map { $0.normalized() }
    }

    private func downloadData(
        url: URL,
        requestId: String,
        modelId: String,
        parentTraceId: String,
        request generationRequest: FALImageGenerationRequest
    ) async throws -> FALImageDownload {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 600
        request.setValue("image/*,application/octet-stream", forHTTPHeaderField: "Accept")
        var recordedRequest = URLRequest(url: traceSafeFALMediaURL(url))
        recordedRequest.httpMethod = "GET"
        let downloaded = try await TracedHTTPTransport.download(
            request: request,
            recordedRequest: recordedRequest,
            metadata: traceMetadata(
                operation: "output_download",
                workflowStep: workflowStep("download", request: generationRequest),
                modelId: modelId,
                parentTraceId: parentTraceId,
                generationRequest: generationRequest,
                requestTextJSON: inferenceTraceJSONString([
                    "provider_request_id": requestId,
                    "source": "provider_result",
                ]),
                responseHint: "image/*"
            )
        )
        defer { try? FileManager.default.removeItem(at: downloaded.temporaryURL) }
        guard let http = downloaded.response, (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture("FAL image download failed.")
        }
        let data = try Data(contentsOf: downloaded.temporaryURL)
        let sha256 = sha256Hex(data)
        let contentType = http.value(forHTTPHeaderField: "content-type") ?? "image/jpeg"
        let parsedOutput = inferenceTraceJSONString([
            "provider_request_id": requestId,
            "local_artifact_id": generationRequest.artifactId,
            "content_type": contentType,
            "byte_count": data.count,
            "sha256": sha256,
        ])
        await InferenceTraceStore.shared.enrich(
            traceId: downloaded.traceId,
            providerRequestId: requestId,
            model: modelId,
            parsedOutputJSON: parsedOutput
        )
        var downloadRefs: [String: Any] = [
            "output": [
                "artifact_id": generationRequest.artifactId,
                "content_type": contentType,
                "byte_count": data.count,
                "sha256": sha256,
            ],
        ]
        let downloadSources = Self.sourceMediaRefs(generationRequest)
        if !downloadSources.isEmpty {
            downloadRefs["sources"] = downloadSources
        }
        await InferenceTraceStore.shared.enrichContext(
            traceId: downloaded.traceId,
            responseTextJSON: parsedOutput,
            mediaRefsJSON: inferenceTraceJSONString(downloadRefs)
        )
        return FALImageDownload(
            data: data,
            traceId: downloaded.traceId,
            contentType: contentType,
            sha256: sha256
        )
    }

    private func recordLifecycleEvent(
        requestId: String,
        modelId: String,
        outcome: String,
        detail: String,
        remoteRequestMayContinue: Bool,
        parentTraceId: String,
        request generationRequest: FALImageGenerationRequest
    ) async -> String {
        let safeRequestId = requestId.trimmed.nilIfEmpty ?? "unknown"
        var eventRequest = URLRequest(
            url: queueURL(modelId: modelId)
                .appendingPathComponent("requests")
                .appendingPathComponent(safeRequestId)
                .appendingPathComponent("local-lifecycle")
        )
        eventRequest.httpMethod = "EVENT"
        var metadata = traceMetadata(
            operation: outcome,
            workflowStep: workflowStep(outcome, request: generationRequest),
            modelId: modelId,
            parentTraceId: parentTraceId,
            generationRequest: generationRequest,
            requestTextJSON: inferenceTraceJSONString([
                "provider_request_id": requestId,
                "remote_cancel_requested": false,
                "existing_request_resumable": !requestId.trimmed.isEmpty,
                "new_paid_submission_required": requestId.trimmed.isEmpty,
            ]),
            responseHint: "application/json"
        )
        metadata.responseTextJSON = inferenceTraceJSONString([
            "outcome": outcome,
            "detail": safeFALImageTraceText(detail),
            "remote_request_may_continue": remoteRequestMayContinue,
        ])
        return await InferenceTraceStore.shared.recordEvent(
            request: eventRequest,
            metadata: metadata
        )
    }
}

private struct FALJSONResponse {
    var object: [String: Any]
    var traceId: String
}

private struct FALImageDownload {
    var data: Data
    var traceId: String
    var contentType: String
    var sha256: String
}

private func isSupportedJSONValue(_ value: Any) -> Bool {
    if value is String || value is Bool || value is Int || value is Double || value is NSNumber {
        return true
    }
    if let dict = value as? [String: Any] {
        return dict.values.allSatisfy(isSupportedJSONValue)
    }
    if let array = value as? [Any] {
        return array.allSatisfy(isSupportedJSONValue)
    }
    return false
}

private func sanitizedFALInputForTrace(_ input: [String: Any]) -> [String: Any] {
    var sanitized = input
    if let urls = input["image_urls"] as? [String] {
        sanitized["image_urls"] = urls.map(sanitizedFALURLForTrace)
    }
    if let url = input["image_url"] as? String {
        sanitized["image_url"] = sanitizedFALURLForTrace(url)
    }
    return sanitized
}

private func sanitizedFALURLForTrace(_ value: String) -> String {
    guard value.hasPrefix("data:") else { return value }
    let prefix = value.components(separatedBy: ";base64,").first ?? "data:image"
    return "\(prefix);base64,<omitted \(value.count) chars>"
}

private func traceSafeFALQueueURL(_ url: URL) -> URL {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.user = nil
    components?.password = nil
    components?.query = nil
    components?.fragment = nil
    return components?.url ?? URL(string: "https://queue.fal.run")!
}

private func traceSafeFALMediaURL(_ url: URL) -> URL {
    var components = URLComponents()
    components.scheme = url.scheme
    components.host = url.host
    components.port = url.port
    components.path = "/provider-output"
    return components.url ?? URL(string: "https://fal.media/provider-output")!
}

private func falImageTraceResponseSummary(_ dictionary: [String: Any]) -> [String: Any] {
    var summary: [String: Any] = [:]
    for key in [
        "status",
        "request_id",
        "requestId",
        "id",
        "error_type",
        "errorType",
        "seed",
        "description",
    ] {
        if let value = dictionary[key] as? String, !value.trimmed.isEmpty {
            summary[key] = safeFALImageTraceText(value)
        } else if let value = dictionary[key] as? NSNumber {
            summary[key] = value
        }
    }
    for key in ["error", "message", "detail", "reason"] {
        if let value = dictionary[key] {
            let safeText = safeFALImageTraceText(workflowFailureSummary(from: value))
            if !safeText.isEmpty {
                summary[key] = safeText
            }
        }
    }
    if let images = dictionary["images"] as? [[String: Any]] {
        summary["images"] = images.map(falImageOutputMetadata)
    } else if let image = dictionary["image"] as? [String: Any] {
        summary["images"] = [falImageOutputMetadata(image)]
    }
    return summary.isEmpty ? ["response": "fields_omitted"] : summary
}

private func falImageOutputMetadata(_ image: [String: Any]) -> [String: Any] {
    var summary: [String: Any] = [:]
    for key in ["width", "height", "file_size"] {
        if let value = image[key] as? NSNumber {
            summary[key] = value
        } else if let value = image[key] as? String, !value.trimmed.isEmpty {
            summary[key] = safeFALImageTraceText(value)
        }
    }
    for key in ["content_type", "file_name"] {
        if let value = image[key] as? String, !value.trimmed.isEmpty {
            summary[key] = safeFALImageTraceText(value)
        }
    }
    return summary
}

private func safeFALImageTraceText(_ value: String) -> String {
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

private func firstString(in dictionary: [String: Any], keys: [String]) -> String {
    for key in keys {
        if let value = dictionary[key] as? String, !value.trimmed.isEmpty {
            return value.trimmed
        }
        if let value = dictionary[key] as? NSNumber {
            return value.stringValue
        }
    }
    return ""
}

private func firstURL(in dictionary: [String: Any], keys: [String]) -> URL? {
    for key in keys {
        if let text = dictionary[key] as? String,
           let url = URL(string: text) {
            return url
        }
    }
    return nil
}

private func firstSeed(in value: Any) -> String {
    if let dictionary = value as? [String: Any] {
        if let seed = dictionary["seed"] as? NSNumber {
            return seed.stringValue
        }
        if let seed = dictionary["seed"] as? String, !seed.trimmed.isEmpty {
            return seed.trimmed
        }
        for nested in dictionary.values {
            let seed = firstSeed(in: nested)
            if !seed.isEmpty { return seed }
        }
    } else if let array = value as? [Any] {
        for nested in array {
            let seed = firstSeed(in: nested)
            if !seed.isEmpty { return seed }
        }
    }
    return ""
}

private func outputImageURLs(from body: [String: Any]) -> [URL] {
    var urls: [URL] = []
    collectImageURLs(from: body, into: &urls)
    var seen = Set<String>()
    return urls.filter { url in
        let value = url.absoluteString
        guard !seen.contains(value) else { return false }
        seen.insert(value)
        return true
    }
}

private func collectImageURLs(from value: Any, key: String = "", into urls: inout [URL]) {
    if let text = value as? String,
       let url = URL(string: text),
       isLikelyImageURL(url, key: key) {
        urls.append(url)
        return
    }
    if let dictionary = value as? [String: Any] {
        for preferredKey in ["url", "image", "images", "outputs", "media", "blob", "blobs"] {
            if let nested = dictionary[preferredKey] {
                collectImageURLs(from: nested, key: preferredKey, into: &urls)
            }
        }
        for (nestedKey, nested) in dictionary where !["url", "image", "images", "outputs", "media", "blob", "blobs"].contains(nestedKey) {
            collectImageURLs(from: nested, key: nestedKey, into: &urls)
        }
    } else if let array = value as? [Any] {
        for nested in array {
            collectImageURLs(from: nested, key: key, into: &urls)
        }
    }
}

private func isLikelyImageURL(_ url: URL, key: String) -> Bool {
    let loweredKey = key.lowercased()
    let loweredPath = url.path.lowercased()
    return loweredKey.contains("image")
        || loweredKey == "url"
        || loweredPath.hasSuffix(".png")
        || loweredPath.hasSuffix(".jpg")
        || loweredPath.hasSuffix(".jpeg")
        || loweredPath.hasSuffix(".webp")
}

private func containsFailure(in dictionary: [String: Any]) -> Bool {
    for key in ["error", "error_type", "errorType"] {
        if let value = dictionary[key] as? String, !value.trimmed.isEmpty {
            return true
        }
    }
    return false
}

private func workflowFailureSummary(from value: Any) -> String {
    if let dictionary = value as? [String: Any] {
        let keys = ["error", "errors", "message", "messages", "msg", "reason", "failureReason", "failedReason", "exception", "error_type", "errorType"]
        let parts = keys.compactMap { key -> String? in
            guard let entry = dictionary[key] else { return nil }
            if let text = entry as? String, !text.trimmed.isEmpty {
                return "\(key)=\(text.trimmed)"
            }
            if JSONSerialization.isValidJSONObject(entry),
               let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8),
               !text.trimmed.isEmpty {
                return "\(key)=\(text.trimmed)"
            }
            return nil
        }
        if !parts.isEmpty {
            return uniqueNonEmpty(parts, limit: 8).joined(separator: "; ")
        }
        for nested in dictionary.values {
            let summary = workflowFailureSummary(from: nested)
            if !summary.isEmpty { return summary }
        }
    } else if let array = value as? [Any] {
        for nested in array {
            let summary = workflowFailureSummary(from: nested)
            if !summary.isEmpty { return summary }
        }
    }
    return ""
}

private func providerPromptLimited(_ prompt: String, maxCharacters: Int) -> String {
    let cleaned = prompt
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { String($0).trimmed }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard cleaned.count > maxCharacters else { return cleaned }
    var prefix = String(cleaned.prefix(maxCharacters))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if let boundary = prefix.lastIndex(where: { $0 == "." || $0 == ";" || $0 == "," || $0 == "\n" }),
       prefix.distance(from: prefix.startIndex, to: boundary) > maxCharacters / 2 {
        prefix = String(prefix[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
    } else if let boundary = prefix.lastIndex(where: { $0 == " " || $0 == "\n" }),
              prefix.distance(from: prefix.startIndex, to: boundary) > maxCharacters / 2 {
        prefix = String(prefix[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return prefix
}

/// FAL Outpaint appends this text to its own base outpaint instruction and
/// reads it as content, not instructions — so the wire carries only bounded
/// operator content. An empty prompt is valid and lets the endpoint's visual
/// continuation drive; instruction or negation vocabulary ("never duplicate",
/// "no borders") acts as content tokens and conjures the named artifacts.
func falOutpaintProviderPrompt(_ operatorPrompt: String, maxCharacters: Int) -> String {
    providerPromptLimited(operatorPrompt, maxCharacters: maxCharacters)
}

private func recipeStringValue(_ value: Any) -> String {
    if let value = value as? String { return value }
    if let value = value as? Bool { return value ? "true" : "false" }
    if let value = value as? NSNumber { return value.stringValue }
    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        return text
    }
    return "\(value)"
}

private func recipeValueType(_ value: Any) -> String {
    if value is Bool { return "boolean" }
    if let number = value as? NSNumber {
        return CFGetTypeID(number) == CFBooleanGetTypeID() ? "boolean" : "number"
    }
    if value is [String: Any] || value is [Any] { return "json" }
    return "string"
}
