import Foundation

struct DecartRestyleRequest: Sendable {
    var projectId: String
    var shotId: String
    var artifactId: String
    var seed: Int
    var sourceURL: URL
    var sourceSHA256: String
    var styleReference: SREFStyleImageReference
    var outputURL: URL
    var workflowName: String = "shot_look_restyle"
    var artifactType: String = "shot_restyle"
    var traceGroupId: String = ""
}

struct DecartRestyleSubmission: Sendable {
    var jobId: String
    var traceId: String
}

struct DecartRestyleRemoteResult: Sendable {
    var traceId: String
}

private struct DecartWorkflowFailure: LocalizedError {
    var jobId: String
    var traceId: String
    var message: String

    var errorDescription: String? { message }
}

/// Direct, job-based Lucy Restyle 2 transport. The source video and verified
/// catalog image are composed into a temporary multipart body on disk, then
/// streamed by URLSession so source-size bounds do not become memory bounds.
struct DecartVideoClient: @unchecked Sendable {
    let credentialStore: LitScenesCredentialResolving

    private let apiBaseURL = URL(string: "https://api.decart.ai/v1/jobs")!
    private let modelId = "lucy-restyle-2"
    private let terminalFailureStates: Set<String> = ["FAILED", "CANCELLED", "CANCELED"]

    func submitRestyle(_ request: DecartRestyleRequest) async throws -> DecartRestyleSubmission {
        let logRequestId = request.artifactId
        let startedAt = Date()
        var statusCode = 0
        print("[decart_restyle_submit] starting request_id=\(logRequestId) artifact_id=\(request.artifactId)")
        do {
            let apiKey = try restyleAPIKey()
            let reference = request.styleReference.normalized()
            let referenceURL = try await SREFReferenceImageCache.shared.cachedFileURL(for: reference)
            let boundary = "LitScenes-\(UUID().uuidString)"
            let multipartURL = try multipartBodyFile(
                request: request,
                referenceURL: referenceURL,
                boundary: boundary
            )
            defer { try? FileManager.default.removeItem(at: multipartURL) }

            var submission = URLRequest(url: apiBaseURL.appendingPathComponent(modelId))
            submission.httpMethod = "POST"
            submission.timeoutInterval = 1_800
            submission.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
            submission.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            submission.setValue("application/json", forHTTPHeaderField: "Accept")
            let traced = try await TracedHTTPTransport.upload(
                request: submission,
                fromFile: multipartURL,
                metadata: traceMetadata(
                    request,
                    operation: "queue_submit",
                    responseBodyFormatHint: "application/json",
                    captureResponseBody: false
                )
            )
            statusCode = traced.response?.statusCode ?? 0
            guard let http = traced.response, (200..<300).contains(http.statusCode) else {
                throw ScreenGraphError.capture("Decart Lucy submission failed: \(safeResponseText(traced.data))")
            }
            guard let object = try JSONSerialization.jsonObject(with: traced.data) as? [String: Any] else {
                throw ScreenGraphError.capture("Decart Lucy submission returned invalid JSON.")
            }
            let jobId = decartFirstString(in: object, keys: ["job_id", "jobId", "id"])
            guard !jobId.isEmpty else {
                throw ScreenGraphError.capture("Decart Lucy submission returned no job id.")
            }
            await InferenceTraceStore.shared.enrich(
                traceId: traced.traceId,
                providerRequestId: jobId,
                parsedOutputJSON: inferenceTraceJSONString([
                    "provider_request_id": jobId,
                    "job_status": decartFirstString(in: object, keys: ["status", "state"]),
                ])
            )
            print("[decart_restyle_submit] completed request_id=\(jobId) duration_ms=\(durationMs(since: startedAt)) status_code=\(statusCode)")
            return DecartRestyleSubmission(jobId: jobId, traceId: traced.traceId)
        } catch {
            print("[decart_restyle_submit] error request_id=\(logRequestId) duration_ms=\(durationMs(since: startedAt)) status_code=\(statusCode) message=\"\(shortLogMessage(error.localizedDescription))\"")
            throw error
        }
    }

    func waitForRestyle(_ request: DecartRestyleRequest, jobId: String) async throws -> DecartRestyleRemoteResult {
        let apiKey = try restyleAPIKey()
        let started = Date()
        var delay: UInt64 = 3
        while true {
            try Task.checkCancellation()
            let pollStartedAt = Date()
            var statusCode = 0
            print("[decart_restyle_status] starting request_id=\(jobId) artifact_id=\(request.artifactId)")
            do {
                var statusRequest = URLRequest(url: apiBaseURL.appendingPathComponent(jobId))
                statusRequest.httpMethod = "GET"
                statusRequest.timeoutInterval = 180
                statusRequest.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
                statusRequest.setValue("application/json", forHTTPHeaderField: "Accept")
                let traced = try await TracedHTTPTransport.send(
                    request: statusRequest,
                    metadata: traceMetadata(
                        request,
                        operation: "queue_status",
                        requestTextFields: ["provider_request_id": jobId],
                        responseBodyFormatHint: "application/json",
                        captureResponseBody: false
                    )
                )
                statusCode = traced.response?.statusCode ?? 0
                guard let http = traced.response, (200..<300).contains(http.statusCode) else {
                    throw ScreenGraphError.capture("Decart Lucy status failed: \(safeResponseText(traced.data))")
                }
                guard let object = try JSONSerialization.jsonObject(with: traced.data) as? [String: Any] else {
                    throw ScreenGraphError.capture("Decart Lucy status returned invalid JSON.")
                }
                let status = decartFirstString(in: object, keys: ["status", "state"]).uppercased()
                await InferenceTraceStore.shared.enrich(
                    traceId: traced.traceId,
                    providerRequestId: jobId,
                    parsedOutputJSON: inferenceTraceJSONString([
                        "provider_request_id": jobId,
                        "job_status": status,
                        "error": terminalFailureStates.contains(status)
                            ? decartFailureSummary(object)
                            : "",
                    ])
                )
                print("[decart_restyle_status] completed request_id=\(jobId) duration_ms=\(durationMs(since: pollStartedAt)) status_code=\(statusCode) job_status=\(status.nilIfEmpty ?? "UNKNOWN")")
                if status == "COMPLETED" {
                    return DecartRestyleRemoteResult(traceId: traced.traceId)
                }
                if terminalFailureStates.contains(status) {
                    throw DecartWorkflowFailure(
                        jobId: jobId,
                        traceId: traced.traceId,
                        message: "Decart Lucy request ended with \(status). \(decartFailureSummary(object))".trimmed
                    )
                }
                if status.isEmpty {
                    throw ScreenGraphError.capture("Decart Lucy status response did not include a status.")
                }
            } catch {
                print("[decart_restyle_status] error request_id=\(jobId) duration_ms=\(durationMs(since: pollStartedAt)) status_code=\(statusCode) message=\"\(shortLogMessage(error.localizedDescription))\"")
                throw error
            }
            if Date().timeIntervalSince(started) > 10_800 {
                throw ScreenGraphError.capture("Decart Lucy request did not finish within three hours. It can be resumed later without another submission.")
            }
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay = min(UInt64(Double(delay) * 1.4), 30)
        }
    }

    @discardableResult
    func downloadRestyleOutput(_ request: DecartRestyleRequest, jobId: String) async throws -> String {
        let startedAt = Date()
        var statusCode = 0
        print("[decart_restyle_content] starting request_id=\(jobId) artifact_id=\(request.artifactId)")
        do {
            let apiKey = try restyleAPIKey()
            var contentRequest = URLRequest(
                url: apiBaseURL.appendingPathComponent(jobId).appendingPathComponent("content")
            )
            contentRequest.httpMethod = "GET"
            contentRequest.timeoutInterval = 1_800
            contentRequest.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
            contentRequest.setValue("video/mp4", forHTTPHeaderField: "Accept")
            let traced = try await TracedHTTPTransport.download(
                request: contentRequest,
                metadata: traceMetadata(
                    request,
                    operation: "queue_content",
                    requestTextFields: ["provider_request_id": jobId],
                    responseTextJSON: inferenceTraceJSONString([
                        "provider_request_id": jobId,
                        "content": "binary video response",
                    ]),
                    responseBodyFormatHint: "video/mp4",
                    captureResponseBody: false
                )
            )
            statusCode = traced.response?.statusCode ?? 0
            guard let http = traced.response, (200..<300).contains(http.statusCode) else {
                throw ScreenGraphError.capture("Decart Lucy content download failed with HTTP \(statusCode). Resume Look can retry this completed job without another submission.")
            }
            try ensureDirectory(request.outputURL.deletingLastPathComponent())
            if FileManager.default.fileExists(atPath: request.outputURL.path) {
                try FileManager.default.removeItem(at: request.outputURL)
            }
            try FileManager.default.moveItem(at: traced.temporaryURL, to: request.outputURL)
            let attributes = try FileManager.default.attributesOfItem(atPath: request.outputURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard byteCount > 0 else {
                throw ScreenGraphError.capture("Decart Lucy content download was empty.")
            }
            let outputData = try Data(contentsOf: request.outputURL, options: [.mappedIfSafe])
            let outputSHA256 = sha256Hex(outputData)
            await InferenceTraceStore.shared.enrich(
                traceId: traced.traceId,
                providerRequestId: jobId,
                parsedOutputJSON: inferenceTraceJSONString([
                    "provider_request_id": jobId,
                    "content_type": http.value(forHTTPHeaderField: "content-type") ?? "video/mp4",
                    "byte_count": byteCount,
                    "output_sha256": outputSHA256,
                ])
            )
            print("[decart_restyle_content] completed request_id=\(jobId) duration_ms=\(durationMs(since: startedAt)) status_code=\(statusCode) bytes=\(byteCount)")
            return traced.traceId
        } catch {
            print("[decart_restyle_content] error request_id=\(jobId) duration_ms=\(durationMs(since: startedAt)) status_code=\(statusCode) message=\"\(shortLogMessage(error.localizedDescription))\"")
            throw error
        }
    }

    @discardableResult
    func recordStopWaiting(_ request: DecartRestyleRequest, jobId: String) async -> String {
        print("[decart_restyle_stop_waiting] starting request_id=\(jobId) artifact_id=\(request.artifactId)")
        var eventRequest = URLRequest(url: apiBaseURL.appendingPathComponent(jobId))
        eventRequest.httpMethod = "LOCAL"
        let traceId = await InferenceTraceStore.shared.recordEvent(
            request: eventRequest,
            metadata: traceMetadata(
                request,
                operation: "local_stop_waiting",
                requestTextFields: [
                    "provider_request_id": jobId,
                    "action": "stop_waiting",
                    "remote_cancel_requested": false,
                ],
                responseTextJSON: inferenceTraceJSONString([
                    "local_status": "paused",
                    "remote_job_may_continue": true,
                    "remote_charges_may_continue": true,
                    "resume_reuses_provider_request_id": true,
                ]),
                responseBodyFormatHint: "application/json",
                captureResponseBody: false
            )
        )
        await InferenceTraceStore.shared.enrich(traceId: traceId, providerRequestId: jobId)
        print("[decart_restyle_stop_waiting] completed request_id=\(jobId) duration_ms=0 status_code=200 trace_id=\(traceId)")
        return traceId
    }

    private func traceMetadata(
        _ request: DecartRestyleRequest,
        operation: String,
        requestTextFields: [String: Any] = [:],
        responseTextJSON: String = "",
        responseBodyFormatHint: String,
        captureResponseBody: Bool
    ) -> InferenceTraceRequestMetadata {
        var requestFields: [String: Any] = [
            "input_mode": "reference_image",
            "prompt_source": "reference_image",
            "text_prompt_present": false,
            "prompt_character_count": 0,
            "seed": max(request.seed, 0),
            "resolution": "720p",
            "enhance_prompt": false,
            "source_video_sha256": request.sourceSHA256,
            "style_reference_sha256": request.styleReference.sha256,
            "style_reference_id": request.styleReference.itemId,
            "request_body_captured": false,
        ]
        for (key, value) in requestTextFields {
            requestFields[key] = value
        }
        return InferenceTraceRequestMetadata(
            provider: "decart",
            apiFamily: "video",
            operation: operation,
            projectId: request.projectId,
            runId: request.artifactId,
            traceGroupId: request.traceGroupId.trimmed.nilIfEmpty ?? "shot_look_\(request.shotId)",
            workflowName: request.workflowName,
            workflowStep: "decart_lucy_\(operation)",
            artifactType: request.artifactType,
            artifactId: request.artifactId,
            model: modelId,
            requestBodyFormat: operation == "queue_submit" ? "multipart/form-data" : "none",
            responseBodyFormatHint: responseBodyFormatHint,
            requestTextJSON: inferenceTraceJSONString(requestFields),
            responseTextJSON: responseTextJSON,
            mediaRefsJSON: styleMediaRefsJSON(request.styleReference),
            providerRequestIDHeaderCandidates: ["x-request-id", "request-id"],
            captureRequestBody: false,
            captureResponseBody: captureResponseBody
        )
    }

    private func styleMediaRefsJSON(_ reference: SREFStyleImageReference) -> String {
        let normalized = reference.normalized()
        return inferenceTraceJSONString([
            "sources": [[
                "label": "style reference",
                "title": normalized.title,
                "filename": normalized.filename,
                "sha256": normalized.sha256,
                "mime_type": normalized.mimeType,
                "width": normalized.width,
                "height": normalized.height,
                "catalog_kind": normalized.catalogKind,
                "catalog_version": normalized.catalogVersion,
                "item_id": normalized.itemId,
            ]],
        ])
    }

    private func multipartBodyFile(
        request: DecartRestyleRequest,
        referenceURL: URL,
        boundary: String
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("litscenes-decart-multipart", isDirectory: true)
        try ensureDirectory(directory)
        let outputURL = directory.appendingPathComponent("\(safeIdentifier(request.artifactId))-\(UUID().uuidString).body")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputURL) else {
            throw ScreenGraphError.capture("The Decart upload body could not be created.")
        }
        defer { try? output.close() }

        func write(_ text: String) throws {
            try output.write(contentsOf: Data(text.utf8))
        }
        func writeFile(_ fileURL: URL) throws {
            let input = try FileHandle(forReadingFrom: fileURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 1_024 * 1_024), !chunk.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: chunk)
            }
        }
        func writeFilePart(name: String, filename: String, mimeType: String, fileURL: URL) throws {
            let safeFilename = filename.replacingOccurrences(of: "\"", with: "_")
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(safeFilename)\"\r\n")
            try write("Content-Type: \(mimeType)\r\n\r\n")
            try writeFile(fileURL)
            try write("\r\n")
        }
        func writeTextPart(name: String, value: String) throws {
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            try write("\(value)\r\n")
        }

        try writeFilePart(
            name: "data",
            filename: request.sourceURL.lastPathComponent,
            mimeType: "video/mp4",
            fileURL: request.sourceURL
        )
        try writeFilePart(
            name: "reference_image",
            filename: referenceURL.lastPathComponent,
            mimeType: request.styleReference.mimeType,
            fileURL: referenceURL
        )
        try writeTextPart(name: "seed", value: String(max(request.seed, 0)))
        try writeTextPart(name: "resolution", value: "720p")
        try writeTextPart(name: "enhance_prompt", value: "false")
        try write("--\(boundary)--\r\n")
        return outputURL
    }

    private func restyleAPIKey() throws -> String {
        let apiKey = credentialStore.resolvedCredential(for: .decart)
        guard !apiKey.trimmed.isEmpty else {
            throw ScreenGraphError.credentials("Add a Decart API key in App Settings to use image-input restyling.")
        }
        return apiKey
    }

    private func safeResponseText(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "provider response body omitted"
        }
        return decartFailureSummary(object)
    }

    private func durationMs(since date: Date) -> Int {
        max(Int(Date().timeIntervalSince(date) * 1_000), 0)
    }

    private func shortLogMessage(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ").prefix(240).description
    }
}

private func decartFirstString(in object: [String: Any], keys: [String]) -> String {
    for key in keys {
        if let value = object[key] as? String, !value.trimmed.isEmpty {
            return value.trimmed
        }
    }
    return ""
}

private func decartFailureSummary(_ object: [String: Any]) -> String {
    let direct = decartFirstString(in: object, keys: ["error", "error_message", "message", "detail"])
    if !direct.isEmpty { return String(direct.prefix(1_000)) }
    if let detail = object["detail"] as? [[String: Any]] {
        let messages = detail.compactMap { entry in
            decartFirstString(in: entry, keys: ["msg", "message", "type"]).nilIfEmpty
        }
        if !messages.isEmpty {
            return String(messages.joined(separator: "; ").prefix(1_000))
        }
    }
    return "No provider error detail was returned."
}
