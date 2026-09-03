import Foundation

struct StabilityAIImageGenerationResult {
    var imageData: Data
    var requestId: String
    var traceId: String
    var model: String
}

private struct StabilityAIMultipartFile {
    var fieldName: String
    var fileName: String
    var mimeType: String
    var data: Data
}

private func stabilityMultipartFormData(
    fields: [(String, String)],
    files: [StabilityAIMultipartFile] = [],
    boundary: String
) -> Data {
    var body = Data()
    for (name, value) in fields {
        body.appendStabilityUTF8("--\(boundary)\r\n")
        body.appendStabilityUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.appendStabilityUTF8("\(value)\r\n")
    }
    for file in files {
        body.appendStabilityUTF8("--\(boundary)\r\n")
        body.appendStabilityUTF8("Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\r\n")
        body.appendStabilityUTF8("Content-Type: \(file.mimeType)\r\n\r\n")
        body.append(file.data)
        body.appendStabilityUTF8("\r\n")
    }
    body.appendStabilityUTF8("--\(boundary)--\r\n")
    return body
}

private extension Data {
    mutating func appendStabilityUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}

private func formattedStabilityAIProviderError(operation: String, status: Int, data: Data, requestId: String) -> String {
    let bodyText = String(data: data.prefix(1200), encoding: .utf8) ?? ""
    var message = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    var code = ""
    var name = ""
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        message = (object["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? message
        code = (object["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (object["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if message.isEmpty, let errors = object["errors"] as? [String] {
            message = errors.joined(separator: " ")
        }
    }
    let stableCode = code.isEmpty ? name : code
    let codePart = stableCode.isEmpty ? "" : ", code=\(stableCode)"
    let requestPart = requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : ", request_id=\(requestId)"
    let fallback = message.isEmpty ? "No provider error body was returned." : message
    return "\(operation) failed (\(status)\(codePart)\(requestPart)): \(fallback)"
}

private func stabilityProviderRequestId(from response: HTTPURLResponse?) -> String {
    response?.value(forHTTPHeaderField: "x-request-id")
        ?? response?.value(forHTTPHeaderField: "request-id")
        ?? response?.value(forHTTPHeaderField: "x-correlation-id")
        ?? ""
}

struct StabilityAIClient: Sendable {
    var apiKey: String
    var endpoint: URL = URL(string: "https://api.stability.ai/v2beta/stable-image/generate/ultra")!

    static let ultraModel = "stable-image-ultra"

    static func fromEnvironment(credentialStore: LitScenesCredentialResolving = LitScenesCredentialStore()) throws -> StabilityAIClient {
        let key = credentialStore
            .resolvedCredential(for: .stability)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw ScreenGraphError.credentials("STABILITY_AI_API_KEY is required to generate Stability AI Lens heroes.")
        }
        return StabilityAIClient(apiKey: key)
    }

    func generateLensHero(
        prompt: String,
        negativePrompt: String = "",
        aspectRatio: String = "1:1",
        outputFormat: String = "jpeg",
        source: OpenAIImageEditSource? = nil,
        strength: Double = 0.65,
        projectId: String = "",
        runId: String = "",
        traceWorkflowName: String = "themes"
    ) async throws -> StabilityAIImageGenerationResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        let normalizedFormat = outputFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "jpeg" : outputFormat
        var fields = [
            ("prompt", prompt),
            ("aspect_ratio", aspectRatio),
            ("output_format", normalizedFormat),
        ]
        let normalizedNegativePrompt = negativePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedNegativePrompt.isEmpty {
            fields.append(("negative_prompt", normalizedNegativePrompt))
        }
        var files: [StabilityAIMultipartFile] = []
        if let source {
            fields.append(("strength", String(min(max(strength, 0), 1))))
            files.append(StabilityAIMultipartFile(
                fieldName: "image",
                fileName: source.fileName,
                mimeType: source.mimeType,
                data: source.data
            ))
        }
        let body = stabilityMultipartFormData(fields: fields, files: files, boundary: boundary)
        guard body.count < 10 * 1_024 * 1_024 else {
            throw ScreenGraphError.capture("Stability Ultra requests must remain under 10 MiB. The selected reference could not be prepared within that limit.")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = body

        let startedAt = Date()
        print("[stability_ultra] starting request_id= duration_ms=0 status_code=0 input_image_count=\(source == nil ? 0 : 1)")
        let result: TracedHTTPResult
        do {
            result = try await TracedHTTPTransport.send(
                request: request,
                metadata: InferenceTraceRequestMetadata(
                    provider: "stability",
                    apiFamily: "stable-image",
                    operation: "lens_hero",
                    projectId: projectId,
                    runId: runId,
                    model: Self.ultraModel,
                    requestBodyFormat: "multipart/form-data",
                    responseBodyFormatHint: "image/\(normalizedFormat)",
                    requestTextJSON: inferenceTraceJSONString([
                        "model": Self.ultraModel,
                        "prompt": prompt,
                        "negative_prompt": normalizedNegativePrompt,
                        "aspect_ratio": aspectRatio,
                        "output_format": normalizedFormat,
                        "strength": source == nil ? NSNull() : min(max(strength, 0), 1),
                        "input_image_count": source == nil ? 0 : 1,
                        "input_image_bytes": source?.data.count ?? 0,
                        "input_image_sha256": source.map { sha256Hex($0.data) } ?? ""
                    ]),
                    providerRequestIDHeaderCandidates: ["x-request-id", "request-id", "x-correlation-id"],
                    captureRequestBody: false,
                    captureResponseBody: false
                )
            )
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
            print("[stability_ultra] error request_id= duration_ms=\(durationMs) status_code=0 message=\"\(error.localizedDescription)\"")
            throw error
        }
        let data = result.data
        let status = result.response?.statusCode ?? 0
        let requestId = stabilityProviderRequestId(from: result.response)
        guard (200..<300).contains(status) else {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
            print("[stability_ultra] error request_id=\(requestId) duration_ms=\(durationMs) status_code=\(status)")
            throw ScreenGraphError.openAI(
                formattedStabilityAIProviderError(
                    operation: "Stability AI image request",
                    status: status,
                    data: data,
                    requestId: requestId
                )
            )
        }
        guard !data.isEmpty else {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
            print("[stability_ultra] error request_id=\(requestId) duration_ms=\(durationMs) status_code=\(status) message=\"empty response\"")
            throw ScreenGraphError.openAI("Stability AI image response did not include image data.")
        }
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
        print("[stability_ultra] completed request_id=\(requestId) duration_ms=\(durationMs) status_code=\(status) output_bytes=\(data.count)")
        let outputSize = imagePixelSize(from: data)
        await InferenceTraceStore.shared.enrich(
            traceId: result.traceId,
            providerRequestId: requestId,
            model: Self.ultraModel
        )
        await InferenceTraceStore.shared.enrichContext(
            traceId: result.traceId,
            traceGroupId: runId.isEmpty ? projectId : runId,
            workflowName: traceWorkflowName,
            workflowStep: "lens_hero",
            artifactType: "lens_hero",
            artifactId: runId,
            responseTextJSON: inferenceTraceJSONString([
                "model": Self.ultraModel,
                "request_id": requestId,
                "output_format": normalizedFormat,
                "output_bytes": data.count,
                "output_sha256": sha256Hex(data),
                "output_width": outputSize?.width ?? 0,
                "output_height": outputSize?.height ?? 0
            ]),
            mediaRefsJSON: inferenceTraceJSONString([
                "input": source.map {
                    [
                        "sha256": sha256Hex($0.data),
                        "bytes": $0.data.count,
                        "mime_type": $0.mimeType,
                        "role": $0.role,
                        "label": $0.label
                    ] as [String: Any]
                } ?? [:],
                "output": [
                    "sha256": sha256Hex(data),
                    "bytes": data.count,
                    "width": outputSize?.width ?? 0,
                    "height": outputSize?.height ?? 0,
                    "format": normalizedFormat
                ]
            ])
        )
        return StabilityAIImageGenerationResult(
            imageData: data,
            requestId: requestId,
            traceId: result.traceId,
            model: Self.ultraModel
        )
    }
}
