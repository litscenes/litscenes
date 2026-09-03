import Foundation
import CryptoKit

private func redactedLTXTraceValue(_ value: Any, key: String = "") -> Any {
    let normalizedKey = key.lowercased()
    if normalizedKey.hasSuffix("_uri") || normalizedKey.hasSuffix("_url") {
        return "[redacted-provider-media-capability]"
    }
    if let object = value as? [String: Any] {
        return object.reduce(into: [String: Any]()) { result, field in
            result[field.key] = redactedLTXTraceValue(field.value, key: field.key)
        }
    }
    if let array = value as? [Any] {
        return array.map { redactedLTXTraceValue($0) }
    }
    return value
}

private func redactedLTXTracePayload(_ payload: [String: Any]) -> [String: Any] {
    redactedLTXTraceValue(payload) as? [String: Any] ?? [:]
}

/// CivitAI returns reusable blob/output capabilities in otherwise useful JSON.
/// Preserve prompts, parameters, ids, and statuses while keeping every remote
/// media capability out of the durable trace database.
private func redactedCivitAITraceValue(_ value: Any, key: String = "") -> Any {
    let normalizedKey = key.lowercased()
    let mediaCapabilityKeys: Set<String> = [
        "startimage", "endimage", "url", "publicurl", "video", "videos",
        "outputs", "media", "blob", "source_url", "start_blob_url", "end_blob_url"
    ]
    if mediaCapabilityKeys.contains(normalizedKey) {
        return "[redacted-provider-media-capability]"
    }
    if let object = value as? [String: Any] {
        return object.reduce(into: [String: Any]()) { result, field in
            result[field.key] = redactedCivitAITraceValue(field.value, key: field.key)
        }
    }
    if let array = value as? [Any] {
        return array.map { redactedCivitAITraceValue($0) }
    }
    return value
}

private func redactedCivitAITracePayload(_ payload: [String: Any]) -> [String: Any] {
    redactedCivitAITraceValue(payload) as? [String: Any] ?? [:]
}

struct VideoClipRequest {
    var chainId: String
    var segmentId: String
    var modelSelection: VideoModelSelection
    var prompt: String
    var negativePrompt: String
    var durationSeconds: Int
    /// Kling v3 multi-shot direction: when non-empty, the payload sends the
    /// native `multi_prompt` array INSTEAD of `prompt` (mutually exclusive on
    /// the endpoint). Only ever set for `.falKlingV3ProImageToVideo`.
    var multiShotPrompts: [ShotCompiledKlingShot]? = nil
    /// True when `prompt` was compiled from a temporal direction plan —
    /// providers that rewrite prompts (WAN's expansion) must not shred the
    /// timing windows, so structured prompts disable provider-side expansion.
    var promptIsStructured: Bool = false
    var outputProfile: VideoOutputProfile
    var startFrameURL: URL?
    var targetEndFrameURL: URL?
    var outputURL: URL
    var generateAudio: Bool = false
    var projectId: String = ""
    var runId: String = ""
    var traceGroupId: String = ""
    var workflowName: String = "video_chain"
    var artifactType: String = "video_segment"
    var audioDriverURL: URL?
    var audioDriverDurationSeconds: Double?
    var parentTraceId: String = ""
    var onProviderSubmitted: (@MainActor (String, String) async -> Void)?
}

struct VideoClipExtendRequest {
    var chainId: String
    var segmentId: String
    var modelSelection: VideoModelSelection
    var prompt: String
    var durationSeconds: Int
    var contextSeconds: Double
    var sourceVideoURL: URL
    var sourceKind: String = ""
    var sourceMediaId: String = ""
    var sourceStartSeconds: Double = 0
    var sourceEndSeconds: Double = 0
    var outputURL: URL
    var projectId: String = ""
    var runId: String = ""
    var traceGroupId: String = ""
    var workflowName: String = "video_chain"
    var artifactType: String = "video_segment"
    var parentTraceId: String = ""
    var onProviderSubmitted: (@MainActor (String, String) async -> Void)?
}

struct VideoClipRetakeRequest {
    var chainId: String
    var segmentId: String
    var modelSelection: VideoModelSelection
    var prompt: String
    var outputProfile: VideoOutputProfile
    var sourceVideoURL: URL
    var startSeconds: Double
    var durationSeconds: Double
    var mode: String = ""
    var outputURL: URL
}

struct VideoClipResult {
    var providerId: VideoProviderSelection
    var providerVideoId: String
    var providerJobId: String
    var providerOperation: String
    var traceId: String = ""
    var traceIds: [String] = []
    var providerNativeSize: String
    var outputURL: URL
    var responseSnapshot: [String: String]
}

protocol VideoGenerationProvider {
    var providerId: VideoProviderSelection { get }
    var credentialStore: LitScenesCredentialResolving { get }
    func capability(outputProfile: VideoOutputProfile, durationSeconds: Int) -> VideoProviderCapability
    func generateClip(from request: VideoClipRequest) async throws -> VideoClipResult
}

struct LocalPromptExportProvider: VideoGenerationProvider {
    let credentialStore: LitScenesCredentialResolving
    var providerId: VideoProviderSelection { .localPromptExport }

    func capability(outputProfile: VideoOutputProfile, durationSeconds: Int) -> VideoProviderCapability {
        VideoProviderCapability.capability(for: providerId, outputProfile: outputProfile, durationSeconds: durationSeconds, credentialStore: credentialStore)
    }

    func generateClip(from request: VideoClipRequest) async throws -> VideoClipResult {
        let snapshot = [
            "mode": "prompt_export",
            "chain_id": request.chainId,
            "segment_id": request.segmentId,
            "model": request.modelSelection.providerModelId,
            "duration_seconds": "\(request.durationSeconds)",
            "output_profile": request.outputProfile.label
        ]
        try ensureDirectory(request.outputURL.deletingLastPathComponent())
        try JSONCoding.prettyEncoder.encode(snapshot).write(to: request.outputURL.deletingPathExtension().appendingPathExtension("json"), options: [.atomic])
        return VideoClipResult(
            providerId: providerId,
            providerVideoId: "",
            providerJobId: "",
            providerOperation: "prompt_export",
            providerNativeSize: "",
            outputURL: request.outputURL,
            responseSnapshot: snapshot
        )
    }
}

struct LocalExistingClipProvider: VideoGenerationProvider {
    let credentialStore: LitScenesCredentialResolving
    var providerId: VideoProviderSelection { .localExistingClip }

    func capability(outputProfile: VideoOutputProfile, durationSeconds: Int) -> VideoProviderCapability {
        VideoProviderCapability.capability(for: providerId, outputProfile: outputProfile, durationSeconds: durationSeconds, credentialStore: credentialStore)
    }

    func generateClip(from request: VideoClipRequest) async throws -> VideoClipResult {
        guard FileManager.default.fileExists(atPath: request.outputURL.path) else {
            throw ScreenGraphError.capture("Existing clip is missing for segment \(request.segmentId).")
        }
        return VideoClipResult(
            providerId: providerId,
            providerVideoId: "",
            providerJobId: "",
            providerOperation: "compose_existing_clip",
            providerNativeSize: "",
            outputURL: request.outputURL,
            responseSnapshot: [
                "mode": "local_existing",
                "model": request.modelSelection.providerModelId
            ]
        )
    }
}

struct LTXDirectVideoProvider: VideoGenerationProvider {
    let credentialStore: LitScenesCredentialResolving
    var providerId: VideoProviderSelection { .ltxDirect }

    private static let uploadCreationTimeout: TimeInterval = 60
    private static let uploadPutTimeout: TimeInterval = 300
    private static let generationTimeout: TimeInterval = 900
    private static let asyncExtendPollIntervalNanoseconds: UInt64 = 5_000_000_000
    private static let retryDelayNanoseconds: UInt64 = 3_000_000_000
    private static let retryableStatuses: Set<Int> = [408, 429, 500, 502, 503, 504, 529]
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 900
        configuration.timeoutIntervalForResource = 1_200
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private let uploadURL = URL(string: "https://api.ltx.io/v1/upload")!
    private let imageToVideoURL = URL(string: "https://api.ltx.io/v1/image-to-video")!
    private let asyncExtendURL = URL(string: "https://api.ltx.io/v2/extend")!
    private let retakeURL = URL(string: "https://api.ltx.io/v1/retake")!

    func capability(outputProfile: VideoOutputProfile, durationSeconds: Int) -> VideoProviderCapability {
        VideoProviderCapability.capability(for: providerId, outputProfile: outputProfile, durationSeconds: durationSeconds, credentialStore: credentialStore)
    }

    func generateClip(from request: VideoClipRequest) async throws -> VideoClipResult {
        let apiKey = credentialStore.resolvedCredential(for: .ltx)
        guard !apiKey.isEmpty else { throw ScreenGraphError.credentials("LTX API key is missing.") }
        guard let startFrameURL = request.startFrameURL else {
            throw ScreenGraphError.capture("LTX Direct requires a start frame.")
        }
        let traceGroupId = videoTraceGroupId(chainId: request.chainId, segmentId: request.segmentId)
        let startUpload = try await createAndPutUpload(
            apiKey: apiKey,
            fileURL: startFrameURL,
            traceGroupId: traceGroupId,
            workflowStep: "ltx_start_upload_create"
        )
        let endUpload: LTXUploadResult?
        if let targetEndFrameURL = request.targetEndFrameURL {
            endUpload = try await createAndPutUpload(
                apiKey: apiKey,
                fileURL: targetEndFrameURL,
                traceGroupId: traceGroupId,
                workflowStep: "ltx_end_upload_create"
            )
        } else {
            endUpload = nil
        }
        var payload: [String: Any] = [
            "image_uri": startUpload.storageURI,
            "prompt": request.prompt,
            "model": request.modelSelection.providerModelId,
            "duration": request.durationSeconds,
            "resolution": "\(request.outputProfile.width)x\(request.outputProfile.height)",
            "fps": request.outputProfile.fps,
            "generate_audio": false
        ]
        if let endUpload {
            payload["last_frame_uri"] = endUpload.storageURI
        }

        let output = try await postVideoGenerationPayload(
            apiKey: apiKey,
            url: imageToVideoURL,
            payload: payload,
            outputURL: request.outputURL,
            operation: "image-to-video",
            traceGroupId: traceGroupId,
            artifactId: request.segmentId,
            model: request.modelSelection.providerModelId
        )
        return VideoClipResult(
            providerId: providerId,
            providerVideoId: "",
            providerJobId: output.requestId,
            providerOperation: "image-to-video",
            traceId: output.traceId,
            traceIds: uniqueTraceIds(
                startUpload.traceIds + (endUpload?.traceIds ?? []) + [output.traceId]
            ),
            providerNativeSize: "\(request.outputProfile.width)x\(request.outputProfile.height)",
            outputURL: request.outputURL,
            responseSnapshot: [
                "request_id": output.requestId,
                "content_type": output.contentType,
                "bytes": "\(output.byteCount)",
                "model": request.modelSelection.providerModelId,
                "start_asset_sha256": startUpload.sha256,
                "end_asset_sha256": endUpload?.sha256 ?? ""
            ]
        )
    }

    func generateExtension(from request: VideoClipExtendRequest) async throws -> VideoClipResult {
        let apiKey = credentialStore.resolvedCredential(for: .ltx)
        guard !apiKey.isEmpty else { throw ScreenGraphError.credentials("LTX API key is missing.") }
        guard FileManager.default.fileExists(atPath: request.sourceVideoURL.path) else {
            throw ScreenGraphError.capture("LTX extend source video is missing.")
        }
        guard (2...20).contains(request.durationSeconds) else {
            throw ScreenGraphError.capture("LTX Extend duration must be between 2 and 20 seconds.")
        }
        guard request.contextSeconds >= 1,
              request.contextSeconds <= 20,
              (request.contextSeconds + Double(request.durationSeconds)) * 24 <= 505 else {
            throw ScreenGraphError.capture("LTX Extend context and duration exceed the 505-frame request limit.")
        }
        let traceGroupId = request.traceGroupId.trimmed.nilIfEmpty
            ?? videoTraceGroupId(chainId: request.chainId, segmentId: request.segmentId)
        let sourceUpload = try await createAndPutUpload(
            apiKey: apiKey,
            fileURL: request.sourceVideoURL,
            traceGroupId: traceGroupId,
            workflowStep: "ltx_extend_source_upload_create",
            projectId: request.projectId,
            runId: request.runId,
            workflowName: request.workflowName,
            artifactType: "video_input_asset",
            parentTraceId: request.parentTraceId
        )
        await InferenceTraceStore.shared.enrichContext(
            traceId: sourceUpload.traceId,
            mediaRefsJSON: inferenceTraceJSONString([
                "source": [
                    "filename": request.sourceVideoURL.lastPathComponent,
                    "sha256": sourceUpload.sha256,
                    "mime_type": mediaMIMEType(for: request.sourceVideoURL),
                    "source_kind": request.sourceKind,
                    "source_media_id": request.sourceMediaId,
                    "placed_start_seconds": request.sourceStartSeconds,
                    "placed_end_seconds": request.sourceEndSeconds
                ]
            ])
        )
        var payload: [String: Any] = [
            "video_uri": sourceUpload.storageURI,
            "prompt": request.prompt,
            "model": request.modelSelection.providerModelId,
            "duration": request.durationSeconds,
            "mode": "end"
        ]
        if request.contextSeconds > 0 {
            payload["context"] = request.contextSeconds
        }
        let output = try await postAsyncExtendPayload(
            apiKey: apiKey,
            payload: payload,
            outputURL: request.outputURL,
            traceGroupId: traceGroupId,
            artifactId: request.segmentId,
            model: request.modelSelection.providerModelId,
            projectId: request.projectId,
            runId: request.runId,
            workflowName: request.workflowName,
            artifactType: request.artifactType,
            parentTraceId: sourceUpload.traceId,
            onProviderSubmitted: request.onProviderSubmitted
        )
        return VideoClipResult(
            providerId: providerId,
            providerVideoId: "",
            providerJobId: output.jobId,
            providerOperation: "extend",
            traceId: output.traceId,
            traceIds: uniqueTraceIds(sourceUpload.traceIds + output.traceIds),
            providerNativeSize: "",
            outputURL: request.outputURL,
            responseSnapshot: [
                "request_id": output.requestId,
                "job_id": output.jobId,
                "status": output.status,
                "content_type": output.contentType,
                "bytes": "\(output.byteCount)",
                "model": request.modelSelection.providerModelId,
                "source_video_sha256": sourceUpload.sha256,
                "source_kind": request.sourceKind,
                "source_media_id": request.sourceMediaId,
                "source_start_seconds": "\(request.sourceStartSeconds)",
                "source_end_seconds": "\(request.sourceEndSeconds)",
                "context_seconds": "\(request.contextSeconds)",
                "retry_count": "\(output.retryCount)"
            ]
        )
    }

    func generateRetake(from request: VideoClipRetakeRequest) async throws -> VideoClipResult {
        let apiKey = credentialStore.resolvedCredential(for: .ltx)
        guard !apiKey.isEmpty else { throw ScreenGraphError.credentials("LTX API key is missing.") }
        guard FileManager.default.fileExists(atPath: request.sourceVideoURL.path) else {
            throw ScreenGraphError.capture("LTX retake source video is missing.")
        }
        let traceGroupId = videoTraceGroupId(chainId: request.chainId, segmentId: request.segmentId)
        let sourceUpload = try await createAndPutUpload(
            apiKey: apiKey,
            fileURL: request.sourceVideoURL,
            traceGroupId: traceGroupId,
            workflowStep: "ltx_retake_source_upload_create"
        )
        var payload: [String: Any] = [
            "video_uri": sourceUpload.storageURI,
            "prompt": request.prompt,
            "model": request.modelSelection.providerModelId,
            "start_time": request.startSeconds,
            "duration": request.durationSeconds,
            "resolution": "\(request.outputProfile.width)x\(request.outputProfile.height)"
        ]
        if !request.mode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["mode"] = request.mode
        }
        let output = try await postVideoGenerationPayload(
            apiKey: apiKey,
            url: retakeURL,
            payload: payload,
            outputURL: request.outputURL,
            operation: "retake",
            traceGroupId: traceGroupId,
            artifactId: request.outputURL.lastPathComponent,
            model: request.modelSelection.providerModelId
        )
        return VideoClipResult(
            providerId: providerId,
            providerVideoId: "",
            providerJobId: output.requestId,
            providerOperation: "retake",
            traceId: output.traceId,
            traceIds: uniqueTraceIds(sourceUpload.traceIds + [output.traceId]),
            providerNativeSize: "\(request.outputProfile.width)x\(request.outputProfile.height)",
            outputURL: request.outputURL,
            responseSnapshot: [
                "request_id": output.requestId,
                "content_type": output.contentType,
                "bytes": "\(output.byteCount)",
                "model": request.modelSelection.providerModelId,
                "source_video_sha256": sourceUpload.sha256,
                "start_seconds": "\(request.startSeconds)",
                "duration_seconds": "\(request.durationSeconds)"
            ]
        )
    }

    private func createAndPutUpload(
        apiKey: String,
        fileURL: URL,
        traceGroupId: String,
        workflowStep: String,
        projectId: String = "",
        runId: String = "",
        workflowName: String = "video_chain",
        artifactType: String = "video_input_asset",
        parentTraceId: String = ""
    ) async throws -> LTXUploadResult {
        var create = URLRequest(url: uploadURL)
        create.httpMethod = "POST"
        create.timeoutInterval = Self.uploadCreationTimeout
        create.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        create.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let http: HTTPURLResponse?
        let createTraceId: String
        do {
            let traced = try await TracedHTTPTransport.send(
                request: create,
                metadata: InferenceTraceRequestMetadata(
                    provider: "ltx",
                    apiFamily: "video",
                    operation: "upload_create",
                    projectId: projectId,
                    runId: runId,
                    traceGroupId: traceGroupId,
                    parentTraceId: parentTraceId,
                    workflowName: workflowName,
                    workflowStep: workflowStep,
                    artifactType: artifactType,
                    artifactId: fileURL.lastPathComponent,
                    requestBodyFormat: "none",
                    responseBodyFormatHint: "application/json",
                    providerRequestIDHeaderCandidates: ["x-request-id", "request-id", "x-correlation-id"],
                    captureRequestBody: false,
                    captureResponseBody: false
                )
            )
            data = traced.data
            http = traced.response
            createTraceId = traced.traceId
        } catch {
            throw translatedLTXTransportError(
                error,
                operation: "upload creation",
                timeout: Self.uploadCreationTimeout,
                expectsVideoResponse: false
            )
        }
        guard let http else {
            throw ScreenGraphError.capture("LTX upload creation returned a non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture(
                formattedLTXProviderError(
                    operation: "upload creation",
                    status: http.statusCode,
                    data: data,
                    requestId: ltxRequestId(from: http)
                )
            )
        }
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uploadURLString = body["upload_url"] as? String,
              let signedUploadURL = URL(string: uploadURLString),
              let storageURI = body["storage_uri"] as? String else {
            throw ScreenGraphError.capture("LTX upload response was missing upload_url or storage_uri.")
        }
        await InferenceTraceStore.shared.enrichContext(
            traceId: createTraceId,
            responseTextJSON: inferenceTraceJSONString(redactedLTXTracePayload(body))
        )
        let fileData = try Data(contentsOf: fileURL)
        let fileSHA256 = sha256Hex(fileData)
        var put = URLRequest(url: signedUploadURL)
        put.httpMethod = "PUT"
        put.timeoutInterval = Self.uploadPutTimeout
        let headers = body["required_headers"] as? [String: String] ?? [:]
        for (key, value) in headers {
            put.setValue(value, forHTTPHeaderField: key)
        }
        if put.value(forHTTPHeaderField: "Content-Type") == nil {
            put.setValue(mediaMIMEType(for: fileURL), forHTTPHeaderField: "Content-Type")
        }
        let putHTTP: HTTPURLResponse?
        let putTraceId: String
        do {
            var recordedPut = URLRequest(url: uploadURL.appendingPathComponent("content"))
            recordedPut.httpMethod = "PUT"
            recordedPut.setValue(mediaMIMEType(for: fileURL), forHTTPHeaderField: "Content-Type")
            let traced = try await TracedHTTPTransport.upload(
                request: put,
                fromFile: fileURL,
                recordedRequest: recordedPut,
                metadata: InferenceTraceRequestMetadata(
                    provider: "ltx",
                    apiFamily: "video",
                    operation: "upload_put",
                    projectId: projectId,
                    runId: runId,
                    traceGroupId: traceGroupId,
                    parentTraceId: createTraceId,
                    workflowName: workflowName,
                    workflowStep: "\(workflowStep)_put",
                    artifactType: artifactType,
                    artifactId: fileURL.lastPathComponent,
                    requestBodyFormat: mediaMIMEType(for: fileURL),
                    responseBodyFormatHint: "none",
                    mediaRefsJSON: inferenceTraceJSONString([
                        "source": [
                            "filename": fileURL.lastPathComponent,
                            "sha256": fileSHA256,
                            "bytes": fileData.count,
                            "mime_type": mediaMIMEType(for: fileURL)
                        ]
                    ]),
                    captureRequestBody: false,
                    captureResponseBody: false
                )
            )
            putHTTP = traced.response
            putTraceId = traced.traceId
        } catch {
            throw translatedLTXTransportError(
                error,
                operation: "signed upload PUT",
                timeout: Self.uploadPutTimeout,
                expectsVideoResponse: false
            )
        }
        guard let putHTTP, (200..<300).contains(putHTTP.statusCode) else {
            throw ScreenGraphError.capture("LTX upload PUT failed.")
        }
        await InferenceTraceStore.shared.enrichContext(
            traceId: putTraceId,
            mediaRefsJSON: inferenceTraceJSONString([
                "source": [
                    "filename": fileURL.lastPathComponent,
                    "sha256": fileSHA256,
                    "bytes": fileData.count,
                    "mime_type": mediaMIMEType(for: fileURL)
                ]
            ])
        )
        return LTXUploadResult(
            storageURI: storageURI,
            sha256: fileSHA256,
            traceId: putTraceId,
            traceIds: [createTraceId, putTraceId]
        )
    }

    private func postVideoGenerationPayload(
        apiKey: String,
        url: URL,
        payload: [String: Any],
        outputURL: URL,
        operation: String,
        traceGroupId: String,
        artifactId: String,
        model: String
    ) async throws -> LTXDirectVideoResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.generationTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("video/mp4,application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let data: Data
        let http: HTTPURLResponse?
        let traceId: String
        do {
            let traced = try await TracedHTTPTransport.send(
                request: request,
                metadata: InferenceTraceRequestMetadata(
                    provider: "ltx",
                    apiFamily: "video",
                    operation: operation,
                    traceGroupId: traceGroupId,
                    workflowName: "video_chain",
                    workflowStep: "ltx_\(operation)",
                    artifactType: "video_segment",
                    artifactId: artifactId,
                    model: model,
                    requestBodyFormat: "application/json",
                    responseBodyFormatHint: "video/mp4",
                    requestTextJSON: inferenceTraceJSONString(redactedLTXTracePayload(payload)),
                    providerRequestIDHeaderCandidates: ["x-request-id", "request-id", "x-correlation-id"],
                    captureResponseBody: false
                )
            )
            data = traced.data
            http = traced.response
            traceId = traced.traceId
        } catch {
            throw translatedLTXTransportError(
                error,
                operation: operation,
                timeout: Self.generationTimeout,
                expectsVideoResponse: true
            )
        }
        guard let http else {
            throw ScreenGraphError.capture("LTX \(operation) returned a non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture(
                formattedLTXProviderError(
                    operation: "\(operation) request",
                    status: http.statusCode,
                    data: data,
                    requestId: ltxRequestId(from: http)
                )
            )
        }
        let contentType = http.value(forHTTPHeaderField: "content-type") ?? ""
        guard !contentType.lowercased().contains("application/json") else {
            throw ScreenGraphError.capture(
                formattedLTXProviderError(
                    operation: "\(operation) response",
                    status: http.statusCode,
                    data: data,
                    requestId: ltxRequestId(from: http)
                )
            )
        }
        try ensureDirectory(outputURL.deletingLastPathComponent())
        try data.write(to: outputURL, options: [.atomic])
        await InferenceTraceStore.shared.enrichContext(
            traceId: traceId,
            responseTextJSON: inferenceTraceJSONString([
                "request_id": ltxRequestId(from: http),
                "content_type": contentType,
                "output_bytes": data.count,
                "output_sha256": sha256Hex(data)
            ]),
            mediaRefsJSON: inferenceTraceJSONString([
                "output": [
                    "filename": outputURL.lastPathComponent,
                    "sha256": sha256Hex(data),
                    "bytes": data.count,
                    "content_type": contentType
                ]
            ])
        )
        return LTXDirectVideoResponse(
            requestId: ltxRequestId(from: http),
            contentType: contentType,
            byteCount: data.count,
            traceId: traceId,
            traceIds: [traceId]
        )
    }

    private func postAsyncExtendPayload(
        apiKey: String,
        payload: [String: Any],
        outputURL: URL,
        traceGroupId: String,
        artifactId: String,
        model: String,
        projectId: String,
        runId: String,
        workflowName: String,
        artifactType: String,
        parentTraceId: String,
        onProviderSubmitted: (@MainActor (String, String) async -> Void)?
    ) async throws -> LTXDirectVideoResponse {
        var retryCount = 0
        let submitted = try await retryingLTXOperation(operation: "extend submit") {
            try await postLTXJSON(
                apiKey: apiKey,
                url: asyncExtendURL,
                payload: payload,
                operation: "extend submit",
                traceGroupId: traceGroupId,
                artifactId: artifactId,
                model: model,
                projectId: projectId,
                runId: runId,
                workflowName: workflowName,
                artifactType: artifactType,
                parentTraceId: parentTraceId
            )
        }
        retryCount += submitted.retryCount
        let jobId = firstString(in: submitted.value.object, keys: ["id", "job_id", "jobId"])
        guard !jobId.isEmpty else {
            throw ScreenGraphError.capture("LTX async extend submit returned no job id.")
        }
        await onProviderSubmitted?(jobId, submitted.value.traceId)

        let polled: LTXAsyncPollResult
        do {
            polled = try await pollAsyncExtendJob(
                apiKey: apiKey,
                jobId: jobId,
                traceGroupId: traceGroupId,
                artifactId: artifactId,
                model: model,
                projectId: projectId,
                runId: runId,
                workflowName: workflowName,
                artifactType: artifactType,
                parentTraceId: submitted.value.traceId
            )
        } catch {
            await InferenceTraceStore.shared.enrichContext(
                traceId: submitted.value.traceId,
                responseTextJSON: inferenceTraceJSONString([
                    "job_id": jobId,
                    "status": (Task.isCancelled || error is CancellationError) ? "canceled" : "poll_failed",
                    "error": String(error.localizedDescription.prefix(400))
                ])
            )
            throw error
        }
        retryCount += polled.retryCount
        let videoURLString = ltxResultVideoURLString(from: polled.response.object)
        guard let videoURL = URL(string: videoURLString), !videoURLString.isEmpty else {
            throw ScreenGraphError.capture("LTX async extend job \(jobId) completed without result.video_url.")
        }

        let downloaded = try await retryingLTXOperation(operation: "extend download") {
            try await downloadLTXVideo(
                url: videoURL,
                outputURL: outputURL,
                traceGroupId: traceGroupId,
                artifactId: artifactId,
                model: model,
                projectId: projectId,
                runId: runId,
                workflowName: workflowName,
                artifactType: artifactType,
                parentTraceId: polled.response.traceId
            )
        }
        retryCount += downloaded.retryCount

        return LTXDirectVideoResponse(
            requestId: polled.response.requestId.isEmpty ? submitted.value.requestId : polled.response.requestId,
            contentType: downloaded.value.contentType,
            byteCount: downloaded.value.byteCount,
            jobId: jobId,
            status: ltxStatus(in: polled.response.object),
            retryCount: retryCount,
            traceId: polled.response.traceId.isEmpty ? submitted.value.traceId : polled.response.traceId,
            traceIds: uniqueTraceIds([
                submitted.value.traceId,
                polled.response.traceId,
                downloaded.value.traceId
            ])
        )
    }

    private func pollAsyncExtendJob(
        apiKey: String,
        jobId: String,
        traceGroupId: String,
        artifactId: String,
        model: String,
        projectId: String,
        runId: String,
        workflowName: String,
        artifactType: String,
        parentTraceId: String
    ) async throws -> LTXAsyncPollResult {
        let deadline = Date().addingTimeInterval(Self.generationTimeout)
        var retryCount = 0
        while Date() < deadline {
            let pollURL = asyncExtendURL.appendingPathComponent(jobId)
            let polled = try await retryingLTXOperation(operation: "extend poll") {
                try await getLTXJSON(
                    apiKey: apiKey,
                    url: pollURL,
                    operation: "extend poll",
                    traceGroupId: traceGroupId,
                    artifactId: artifactId,
                    model: model,
                    projectId: projectId,
                    runId: runId,
                    workflowName: workflowName,
                    artifactType: artifactType,
                    parentTraceId: parentTraceId
                )
            }
            retryCount += polled.retryCount
            let status = ltxStatus(in: polled.value.object)
            if ltxSuccessStatuses.contains(status) {
                return LTXAsyncPollResult(response: polled.value, retryCount: retryCount)
            }
            if ltxFailureStatuses.contains(status) {
                throw ScreenGraphError.capture(ltxTerminalJobError(operation: "extend", jobId: jobId, response: polled.value))
            }
            try await Task.sleep(nanoseconds: Self.asyncExtendPollIntervalNanoseconds)
        }
        throw ScreenGraphError.capture("LTX async extend job \(jobId) timed out after \(Int(Self.generationTimeout.rounded()))s.")
    }

    private func postLTXJSON(
        apiKey: String,
        url: URL,
        payload: [String: Any],
        operation: String,
        traceGroupId: String,
        artifactId: String,
        model: String,
        projectId: String,
        runId: String,
        workflowName: String,
        artifactType: String,
        parentTraceId: String
    ) async throws -> LTXJSONResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.uploadCreationTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return try await performLTXJSONRequest(
            request,
            operation: operation,
            traceGroupId: traceGroupId,
            artifactId: artifactId,
            model: model,
            projectId: projectId,
            runId: runId,
            workflowName: workflowName,
            artifactType: artifactType,
            parentTraceId: parentTraceId,
            requestTextJSON: inferenceTraceJSONString(redactedLTXTracePayload(payload))
        )
    }

    private func getLTXJSON(
        apiKey: String,
        url: URL,
        operation: String,
        traceGroupId: String,
        artifactId: String,
        model: String,
        projectId: String,
        runId: String,
        workflowName: String,
        artifactType: String,
        parentTraceId: String
    ) async throws -> LTXJSONResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.uploadCreationTimeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await performLTXJSONRequest(
            request,
            operation: operation,
            traceGroupId: traceGroupId,
            artifactId: artifactId,
            model: model,
            projectId: projectId,
            runId: runId,
            workflowName: workflowName,
            artifactType: artifactType,
            parentTraceId: parentTraceId
        )
    }

    private func performLTXJSONRequest(
        _ request: URLRequest,
        operation: String,
        traceGroupId: String,
        artifactId: String,
        model: String,
        projectId: String,
        runId: String,
        workflowName: String,
        artifactType: String,
        parentTraceId: String,
        requestTextJSON: String = ""
    ) async throws -> LTXJSONResponse {
        let data: Data
        let http: HTTPURLResponse?
        let traceId: String
        do {
            let traced = try await TracedHTTPTransport.send(
                request: request,
                metadata: InferenceTraceRequestMetadata(
                    provider: "ltx",
                    apiFamily: "video",
                    operation: operation,
                    projectId: projectId,
                    runId: runId,
                    traceGroupId: traceGroupId,
                    parentTraceId: parentTraceId,
                    workflowName: workflowName,
                    workflowStep: "ltx_\(operation.replacingOccurrences(of: " ", with: "_"))",
                    artifactType: artifactType,
                    artifactId: artifactId,
                    model: model,
                    requestBodyFormat: request.httpBody == nil ? "none" : "application/json",
                    responseBodyFormatHint: "application/json",
                    requestTextJSON: requestTextJSON,
                    providerRequestIDHeaderCandidates: ["x-request-id", "request-id", "x-correlation-id"],
                    captureRequestBody: requestTextJSON.isEmpty,
                    captureResponseBody: false
                )
            )
            data = traced.data
            http = traced.response
            traceId = traced.traceId
        } catch {
            if isLTXTimeout(error) {
                throw LTXProviderRequestError(
                    message: "LTX \(operation) timed out after \(Int(Self.uploadCreationTimeout.rounded()))s.",
                    status: 0,
                    requestId: "",
                    retryable: true
                )
            }
            throw error
        }
        guard let http else {
            throw ScreenGraphError.capture("LTX \(operation) returned a non-HTTP response.")
        }
        let requestId = ltxRequestId(from: http)
        let responseObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let responseObject {
            await InferenceTraceStore.shared.enrichContext(
                traceId: traceId,
                responseTextJSON: inferenceTraceJSONString(redactedLTXTracePayload(responseObject))
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LTXProviderRequestError(
                message: formattedLTXProviderError(
                    operation: operation,
                    status: http.statusCode,
                    data: data,
                    requestId: requestId
                ),
                status: http.statusCode,
                requestId: requestId,
                retryable: Self.retryableStatuses.contains(http.statusCode)
            )
        }
        guard let object = responseObject else {
            throw ScreenGraphError.capture("LTX \(operation) response was not JSON.")
        }
        return LTXJSONResponse(object: object, requestId: requestId, traceId: traceId)
    }

    private func downloadLTXVideo(
        url: URL,
        outputURL: URL,
        traceGroupId: String,
        artifactId: String,
        model: String,
        projectId: String,
        runId: String,
        workflowName: String,
        artifactType: String,
        parentTraceId: String
    ) async throws -> LTXDownloadResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.generationTimeout
        request.setValue("video/mp4,application/octet-stream", forHTTPHeaderField: "Accept")
        let data: Data
        let http: HTTPURLResponse?
        let traceId: String
        do {
            var recordedRequest = request
            recordedRequest.url = URL(string: "https://api.ltx.io/v2/extend/result")!
            let traced = try await TracedHTTPTransport.send(
                request: request,
                recordedRequest: recordedRequest,
                metadata: InferenceTraceRequestMetadata(
                    provider: "ltx",
                    apiFamily: "video",
                    operation: "extend_download",
                    projectId: projectId,
                    runId: runId,
                    traceGroupId: traceGroupId,
                    parentTraceId: parentTraceId,
                    workflowName: workflowName,
                    workflowStep: "ltx_extend_download",
                    artifactType: artifactType,
                    artifactId: artifactId,
                    model: model,
                    requestBodyFormat: "none",
                    responseBodyFormatHint: "video/mp4",
                    providerRequestIDHeaderCandidates: ["x-request-id", "request-id", "x-correlation-id"],
                    captureRequestBody: false,
                    captureResponseBody: false
                )
            )
            data = traced.data
            http = traced.response
            traceId = traced.traceId
        } catch {
            if isLTXTimeout(error) {
                throw LTXProviderRequestError(
                    message: "LTX extend download timed out after \(Int(Self.generationTimeout.rounded()))s.",
                    status: 0,
                    requestId: "",
                    retryable: true
                )
            }
            throw error
        }
        guard let http else {
            throw ScreenGraphError.capture("LTX extend download returned a non-HTTP response.")
        }
        let requestId = ltxRequestId(from: http)
        guard (200..<300).contains(http.statusCode) else {
            throw LTXProviderRequestError(
                message: formattedLTXProviderError(
                    operation: "extend download",
                    status: http.statusCode,
                    data: data,
                    requestId: requestId
                ),
                status: http.statusCode,
                requestId: requestId,
                retryable: Self.retryableStatuses.contains(http.statusCode)
            )
        }
        try ensureDirectory(outputURL.deletingLastPathComponent())
        try data.write(to: outputURL, options: [.atomic])
        let outputSHA256 = sha256Hex(data)
        await InferenceTraceStore.shared.enrichContext(
            traceId: traceId,
            responseTextJSON: inferenceTraceJSONString([
                "request_id": requestId,
                "content_type": http.value(forHTTPHeaderField: "content-type") ?? "video/mp4",
                "output_bytes": data.count,
                "output_sha256": outputSHA256
            ]),
            mediaRefsJSON: inferenceTraceJSONString([
                "output": [
                    "filename": outputURL.lastPathComponent,
                    "sha256": outputSHA256,
                    "bytes": data.count
                ]
            ])
        )
        return LTXDownloadResult(
            contentType: http.value(forHTTPHeaderField: "content-type") ?? "video/mp4",
            byteCount: data.count,
            traceId: traceId
        )
    }

    private func retryingLTXOperation<T>(
        operation: String,
        body: () async throws -> T
    ) async throws -> (value: T, retryCount: Int) {
        var retryCount = 0
        while true {
            do {
                return (try await body(), retryCount)
            } catch {
                guard retryCount == 0, isRetryableLTXFailure(error) else {
                    throw error
                }
                retryCount += 1
                try await Task.sleep(nanoseconds: Self.retryDelayNanoseconds)
            }
        }
    }
}

struct CivitAIWANImageRequest {
    var artifactId: String
    var prompt: String
    var negativePrompt: String = ""
    var seed: Int?
    /// The CivitAI stack whose YAML `input` map becomes this workflow's body.
    var stack: RenderStack
    /// Reorients the stack's declared canvas (roster character studies render
    /// portrait/square, never the FRAMES 16:9 policy). Both or neither.
    var widthOverride: Int? = nil
    var heightOverride: Int? = nil
    var traceGroupId: String
}

struct CivitAIWANImageResult {
    var imageData: Data
    var providerJobId: String
    var traceId: String
    var responseSnapshot: [String: String]
}

struct CivitAIWorkflowFailure: LocalizedError {
    var jobId: String
    var traceId: String
    var message: String

    var errorDescription: String? { message }
}

struct CivitAIWANImageProvider {
    let credentialStore: LitScenesCredentialResolving

    private let workflowsURL = URL(string: "https://orchestration-new.civitai.com/v2/consumer/workflows")!
    private let terminalStates: Set<String> = ["succeeded", "failed", "canceled", "cancelled", "expired", "rejected"]

    func generateImage(from request: CivitAIWANImageRequest) async throws -> CivitAIWANImageResult {
        let stack = request.stack
        let apiKey = credentialStore.resolvedCredential(for: .civitai)
        guard !apiKey.isEmpty else { throw ScreenGraphError.credentials("CivitAI API key is missing.") }
        let prompt = providerPromptLimited(request.prompt, maxCharacters: stack.promptLimit ?? 1_800)
        let (payload, seed) = stack.civitaiPayload(
            prompt: prompt,
            requestSeed: request.seed,
            negativePrompt: request.negativePrompt,
            widthOverride: request.widthOverride,
            heightOverride: request.heightOverride
        )
        let submitted = try await postJSON(
            apiKey: apiKey,
            url: workflowsURL,
            payload: payload,
            traceGroupId: request.traceGroupId,
            artifactId: request.artifactId,
            model: stack.model
        )
        let jobId = firstString(in: submitted.object, keys: ["id", "workflowId", "jobId"])
        guard !jobId.isEmpty else {
            throw ScreenGraphError.capture("CivitAI \(stack.label) image submit returned no job id.")
        }
        let final = try await pollWorkflow(
            apiKey: apiKey,
            jobId: jobId,
            traceGroupId: request.traceGroupId,
            artifactId: request.artifactId,
            model: stack.model
        )
        let status = (final.object["status"] as? String ?? "").lowercased()
        guard status == "succeeded" else {
            let traceId = final.traceId.isEmpty ? submitted.traceId : final.traceId
            let statusText = status.isEmpty ? "unknown" : status
            let detail = workflowFailureSummary(from: final.object)
            let message = uniqueNonEmpty([
                "CivitAI \(stack.label) workflow \(jobId) ended with status \(statusText).",
                detail
            ]).joined(separator: " ")
            throw CivitAIWorkflowFailure(jobId: jobId, traceId: traceId, message: message)
        }
        guard let imageURL = outputImageURLs(from: final.object).first else {
            throw ScreenGraphError.capture("CivitAI \(stack.label) workflow \(jobId) produced no downloadable image.")
        }
        let imageData = try await downloadData(url: imageURL)
        var snapshot: [String: String] = [
            "job_id": jobId,
            "status": status,
            "model": stack.model,
            "stack_id": stack.stackId,
            "source_url": imageURL.absoluteString,
            "seed": "\(seed)",
            "prompt_characters": "\(prompt.count)",
            "prompt_truncated": "\(prompt != request.prompt)"
        ]
        // Echo the stack's own input map (minus the prompt) for the trace log.
        for (key, value) in stack.civitaiInput {
            snapshot["input_\(key)"] = renderStackTraceValue(value)
        }
        if let width = request.widthOverride, let height = request.heightOverride {
            snapshot["input_width"] = "\(width)"
            snapshot["input_height"] = "\(height)"
        }
        return CivitAIWANImageResult(
            imageData: imageData,
            providerJobId: jobId,
            traceId: final.traceId.isEmpty ? submitted.traceId : final.traceId,
            responseSnapshot: snapshot
        )
    }

    private func postJSON(
        apiKey: String,
        url: URL,
        payload: [String: Any],
        traceGroupId: String,
        artifactId: String,
        model: String
    ) async throws -> CivitAIJSONResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("LitScenes/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let traced = try await TracedHTTPTransport.send(
            request: request,
            metadata: InferenceTraceRequestMetadata(
                provider: "civitai",
                apiFamily: "image",
                operation: "workflow_submit",
                traceGroupId: traceGroupId,
                workflowName: "lenses",
                workflowStep: "civitai_wan_image_submit",
                artifactType: "lens_hero",
                artifactId: artifactId,
                model: model,
                requestBodyFormat: "application/json",
                responseBodyFormatHint: "application/json",
                requestTextJSON: inferenceTraceJSONString(payload),
                providerRequestIDHeaderCandidates: ["x-request-id", "request-id", "x-correlation-id"],
                captureRequestBody: false
            )
        )
        let data = traced.data
        guard let http = traced.response, (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(1200), encoding: .utf8) ?? ""
            throw ScreenGraphError.capture("CivitAI WAN image submit failed: \(body)")
        }
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScreenGraphError.capture("CivitAI WAN image submit response was not JSON.")
        }
        return CivitAIJSONResponse(object: body, traceId: traced.traceId)
    }

    private func pollWorkflow(
        apiKey: String,
        jobId: String,
        traceGroupId: String,
        artifactId: String,
        model: String
    ) async throws -> CivitAIJSONResponse {
        let url = workflowsURL.appendingPathComponent(jobId)
        let started = Date()
        var delay: UInt64 = 4
        while true {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("LitScenes/1.0", forHTTPHeaderField: "User-Agent")
            let traced = try await TracedHTTPTransport.send(
                request: request,
                metadata: InferenceTraceRequestMetadata(
                    provider: "civitai",
                    apiFamily: "image",
                    operation: "workflow_poll",
                    traceGroupId: traceGroupId,
                    workflowName: "lenses",
                    workflowStep: "civitai_wan_image_poll",
                    artifactType: "lens_hero",
                    artifactId: artifactId,
                    model: model,
                    requestBodyFormat: "none",
                    responseBodyFormatHint: "application/json",
                    providerRequestIDHeaderCandidates: ["x-request-id", "request-id", "x-correlation-id"],
                    captureRequestBody: false
                )
            )
            let data = traced.data
            guard let http = traced.response, (200..<300).contains(http.statusCode) else {
                let body = String(data: data.prefix(800), encoding: .utf8) ?? ""
                throw ScreenGraphError.capture("CivitAI WAN image poll failed: \(body)")
            }
            guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ScreenGraphError.capture("CivitAI WAN image poll response was not JSON.")
            }
            let status = (body["status"] as? String ?? "").lowercased()
            if terminalStates.contains(status) {
                return CivitAIJSONResponse(object: body, traceId: traced.traceId)
            }
            if Date().timeIntervalSince(started) > 900 {
                throw ScreenGraphError.capture("CivitAI WAN image workflow \(jobId) did not finish within 15 minutes.")
            }
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay = min(UInt64(Double(delay) * 1.5), 20)
        }
    }

    private func downloadData(url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture("CivitAI WAN image download failed.")
        }
        return data
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
            for (nestedKey, nested) in dictionary {
                collectImageURLs(from: nested, key: nestedKey, into: &urls)
            }
            return
        }
        if let array = value as? [Any] {
            for nested in array {
                collectImageURLs(from: nested, key: key, into: &urls)
            }
        }
    }

    private func isLikelyImageURL(_ url: URL, key: String) -> Bool {
        if ["png", "jpg", "jpeg", "webp"].contains(url.pathExtension.lowercased()) {
            return true
        }
        let normalizedKey = key.lowercased()
        return ["url", "imageurl", "previewurl", "bloburl"].contains(normalizedKey)
            && ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    private func workflowFailureSummary(from body: [String: Any]) -> String {
        var parts: [String] = []
        if let cost = body["cost"] as? [String: Any] {
            if let total = cost["total"] {
                parts.append("cost=\(total)")
            } else if let base = cost["base"] {
                parts.append("cost_base=\(base)")
            }
        }
        if let steps = body["steps"] as? [[String: Any]] {
            for step in steps.prefix(3) {
                let stepType = step["$type"] as? String ?? "step"
                let name = step["name"] as? String ?? ""
                let status = step["status"] as? String ?? ""
                if !status.isEmpty {
                    parts.append("step \(stepType)\(name.isEmpty ? "" : " \(name)") \(status)")
                }
                for detail in failureDetails(in: step).prefix(3) {
                    parts.append(detail)
                }
                if let output = step["output"] as? [String: Any],
                   let images = output["images"] as? [[String: Any]],
                   !images.isEmpty {
                    let availableCount = images.filter { ($0["available"] as? Bool) == true }.count
                    parts.append("images=\(images.count), available=\(availableCount)")
                    for detail in failureDetails(in: output).prefix(3) {
                        parts.append(detail)
                    }
                }
                if let jobs = step["jobs"] as? [[String: Any]] {
                    for job in jobs.prefix(3) {
                        let jobId = job["id"] as? String ?? ""
                        let jobStatus = job["status"] as? String ?? ""
                        if !jobStatus.isEmpty {
                            parts.append("job \(jobId.isEmpty ? "unknown" : jobId) \(jobStatus)")
                        }
                        for detail in failureDetails(in: job).prefix(3) {
                            parts.append(detail)
                        }
                    }
                }
            }
        }
        return uniqueNonEmpty(parts, limit: 10).joined(separator: "; ")
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
            prefix = String(prefix[..<boundary])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let boundary = prefix.lastIndex(where: { $0 == " " || $0 == "\n" }),
                  prefix.distance(from: prefix.startIndex, to: boundary) > maxCharacters / 2 {
            prefix = String(prefix[..<boundary])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return prefix
    }

    private func failureDetails(in dictionary: [String: Any]) -> [String] {
        let keys = ["error", "errors", "message", "messages", "reason", "failureReason", "failedReason", "exception"]
        return keys.compactMap { key in
            guard let value = dictionary[key] else { return nil }
            if let text = value as? String, !text.trimmed.isEmpty {
                return "\(key)=\(text.trimmed)"
            }
            if JSONSerialization.isValidJSONObject(value),
               let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8),
               !text.trimmed.isEmpty {
                return "\(key)=\(text.trimmed)"
            }
            return nil
        }
    }
}

struct CivitAIWANVideoProvider: VideoGenerationProvider {
    let credentialStore: LitScenesCredentialResolving
    var providerId: VideoProviderSelection { .civitaiWan }

    private let workflowsURL = URL(string: "https://orchestration.civitai.com/v2/consumer/workflows")!
    private let blobsURL = URL(string: "https://orchestration.civitai.com/v2/consumer/blobs")!
    private let terminalStates: Set<String> = ["succeeded", "failed", "canceled", "cancelled", "expired", "rejected"]

    func capability(outputProfile: VideoOutputProfile, durationSeconds: Int) -> VideoProviderCapability {
        VideoProviderCapability.capability(for: providerId, outputProfile: outputProfile, durationSeconds: durationSeconds, credentialStore: credentialStore)
    }

    func generateClip(from request: VideoClipRequest) async throws -> VideoClipResult {
        let apiKey = credentialStore.resolvedCredential(for: .civitai)
        guard !apiKey.isEmpty else { throw ScreenGraphError.credentials("CivitAI API key is missing.") }
        guard let startFrameURL = request.startFrameURL else {
            throw ScreenGraphError.capture("CivitAI WAN requires a start frame.")
        }
        let isOpenEndedWan25 = request.modelSelection == .civitaiWanV25ImageToVideo
        if !isOpenEndedWan25, request.targetEndFrameURL == nil {
            throw ScreenGraphError.capture("CivitAI WAN requires a target end frame.")
        }
        let traceGroupId = request.traceGroupId.trimmed.nilIfEmpty
            ?? videoTraceGroupId(chainId: request.chainId, segmentId: request.segmentId)
        let startURL = try await uploadBlob(
            apiKey: apiKey,
            fileURL: startFrameURL,
            role: "start_frame",
            traceGroupId: traceGroupId,
            requestContext: request
        )
        let endURL: String?
        if let targetEndFrameURL = request.targetEndFrameURL {
            endURL = try await uploadBlob(
                apiKey: apiKey,
                fileURL: targetEndFrameURL,
                role: "end_frame",
                traceGroupId: traceGroupId,
                requestContext: request
            )
        } else {
            endURL = nil
        }
        var input: [String: Any] = [
            "engine": "wan",
            "version": isOpenEndedWan25 ? "v2.5" : "v2.7",
            "provider": "fal",
            "operation": "image-to-video",
            "prompt": request.prompt,
            "negativePrompt": request.negativePrompt.isEmpty ? NSNull() : request.negativePrompt,
            "startImage": startURL,
            "resolution": request.outputProfile.height >= 1080 ? "1080p" : "720p",
            "aspectRatio": request.outputProfile.aspectRatio.rawValue,
            "duration": request.durationSeconds,
            "enablePromptExpansion": true,
            "enableSafetyChecker": true
        ]
        if let endURL {
            input["endImage"] = endURL
        }
        let payload: [String: Any] = [
            "steps": [
                [
                    "$type": "videoGen",
                    "input": input
                ]
            ]
        ]
        let submitted = try await postJSON(
            apiKey: apiKey,
            url: workflowsURL,
            payload: payload,
            traceGroupId: traceGroupId,
            artifactId: request.segmentId,
            model: request.modelSelection.providerModelId,
            requestContext: request
        )
        let jobId = firstString(in: submitted.object, keys: ["id", "workflowId", "jobId"])
        guard !jobId.isEmpty else {
            throw ScreenGraphError.capture("CivitAI WAN submit returned no job id.")
        }
        let final = try await pollWorkflow(
            apiKey: apiKey,
            jobId: jobId,
            traceGroupId: traceGroupId,
            artifactId: request.segmentId,
            model: request.modelSelection.providerModelId,
            requestContext: request
        )
        let status = (final.object["status"] as? String ?? "").lowercased()
        guard status == "succeeded" else {
            throw ScreenGraphError.capture("CivitAI WAN workflow \(jobId) ended with status \(status.isEmpty ? "unknown" : status).")
        }
        guard let videoURL = outputVideoURLs(from: final.object).first else {
            throw ScreenGraphError.capture("CivitAI WAN workflow \(jobId) produced no downloadable video.")
        }
        let downloadTraceId = try await download(
            url: videoURL,
            to: request.outputURL,
            traceGroupId: traceGroupId,
            requestContext: request
        )
        return VideoClipResult(
            providerId: providerId,
            providerVideoId: "",
            providerJobId: jobId,
            providerOperation: request.modelSelection.providerModelId,
            traceId: final.traceId.isEmpty ? submitted.traceId : final.traceId,
            traceIds: uniqueTraceIds([submitted.traceId, final.traceId, downloadTraceId]),
            providerNativeSize: "\(request.outputProfile.width)x\(request.outputProfile.height)",
            outputURL: request.outputURL,
            responseSnapshot: [
                "job_id": jobId,
                "status": status,
                "model": request.modelSelection.providerModelId,
                "source_url": "[redacted-provider-media-capability]",
                "start_blob_url": "[redacted-provider-media-capability]",
                "end_blob_url": endURL == nil ? "" : "[redacted-provider-media-capability]"
            ]
        )
    }

    private func uploadBlob(
        apiKey: String,
        fileURL: URL,
        role: String,
        traceGroupId: String,
        requestContext: VideoClipRequest
    ) async throws -> String {
        var request = URLRequest(url: blobsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(mediaMIMEType(for: fileURL), forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let fileData = try Data(contentsOf: fileURL)
        let traced = try await TracedHTTPTransport.upload(
            request: request,
            fromFile: fileURL,
            metadata: InferenceTraceRequestMetadata(
                provider: "civitai",
                apiFamily: "video",
                operation: "blob_upload",
                projectId: requestContext.projectId,
                runId: requestContext.runId.trimmed.nilIfEmpty ?? requestContext.chainId,
                traceGroupId: traceGroupId,
                parentTraceId: requestContext.parentTraceId,
                workflowName: requestContext.workflowName.trimmed.nilIfEmpty ?? "video_chain",
                workflowStep: "civitai_\(role)_upload",
                artifactType: "video_input_asset",
                artifactId: requestContext.segmentId,
                model: requestContext.modelSelection.providerModelId,
                requestBodyFormat: mediaMIMEType(for: fileURL),
                responseBodyFormatHint: "application/json",
                requestTextJSON: inferenceTraceJSONString([
                    "role": role,
                    "mime_type": mediaMIMEType(for: fileURL),
                    "sha256": sha256Hex(fileData)
                ]),
                mediaRefsJSON: inferenceTraceJSONString([
                    role: [
                        "filename": fileURL.lastPathComponent,
                        "sha256": sha256Hex(fileData),
                        "mime_type": mediaMIMEType(for: fileURL)
                    ]
                ]),
                providerRequestIDHeaderCandidates: ["x-request-id", "request-id", "x-correlation-id"],
                captureRequestBody: false,
                captureResponseBody: false
            )
        )
        let data = traced.data
        guard let http = traced.response, (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(800), encoding: .utf8) ?? ""
            throw ScreenGraphError.capture("CivitAI blob upload failed: \(body)")
        }
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScreenGraphError.capture("CivitAI blob upload response was not JSON.")
        }
        await InferenceTraceStore.shared.enrichContext(
            traceId: traced.traceId,
            responseTextJSON: inferenceTraceJSONString(redactedCivitAITracePayload(body))
        )
        let blobURL = firstString(in: body, keys: ["url", "publicUrl"])
        if !blobURL.isEmpty {
            return blobURL
        }
        if let blob = body["blob"] as? [String: Any] {
            return firstString(in: blob, keys: ["url", "publicUrl"])
        }
        throw ScreenGraphError.capture("CivitAI blob upload returned no URL.")
    }

    private func postJSON(
        apiKey: String,
        url: URL,
        payload: [String: Any],
        traceGroupId: String,
        artifactId: String,
        model: String,
        requestContext: VideoClipRequest
    ) async throws -> CivitAIJSONResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let traced = try await TracedHTTPTransport.send(
            request: request,
            metadata: InferenceTraceRequestMetadata(
                provider: "civitai",
                apiFamily: "video",
                operation: "workflow_submit",
                projectId: requestContext.projectId,
                runId: requestContext.runId.trimmed.nilIfEmpty ?? requestContext.chainId,
                traceGroupId: traceGroupId,
                parentTraceId: requestContext.parentTraceId,
                workflowName: requestContext.workflowName.trimmed.nilIfEmpty ?? "video_chain",
                workflowStep: "civitai_workflow_submit",
                artifactType: requestContext.artifactType.trimmed.nilIfEmpty ?? "video_segment",
                artifactId: artifactId,
                model: model,
                requestBodyFormat: "application/json",
                responseBodyFormatHint: "application/json",
                requestTextJSON: inferenceTraceJSONString(redactedCivitAITracePayload(payload)),
                providerRequestIDHeaderCandidates: ["x-request-id", "request-id", "x-correlation-id"],
                captureRequestBody: false,
                captureResponseBody: false
            )
        )
        let data = traced.data
        guard let http = traced.response, (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(1200), encoding: .utf8) ?? ""
            throw ScreenGraphError.capture("CivitAI workflow submit failed: \(body)")
        }
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScreenGraphError.capture("CivitAI workflow submit response was not JSON.")
        }
        await InferenceTraceStore.shared.enrichContext(
            traceId: traced.traceId,
            responseTextJSON: inferenceTraceJSONString(redactedCivitAITracePayload(body))
        )
        return CivitAIJSONResponse(object: body, traceId: traced.traceId)
    }

    private func pollWorkflow(
        apiKey: String,
        jobId: String,
        traceGroupId: String,
        artifactId: String,
        model: String,
        requestContext: VideoClipRequest
    ) async throws -> CivitAIJSONResponse {
        let url = workflowsURL.appendingPathComponent(jobId)
        let started = Date()
        var delay: UInt64 = 4
        while true {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let traced = try await TracedHTTPTransport.send(
                request: request,
                metadata: InferenceTraceRequestMetadata(
                    provider: "civitai",
                    apiFamily: "video",
                    operation: "workflow_poll",
                    projectId: requestContext.projectId,
                    runId: requestContext.runId.trimmed.nilIfEmpty ?? requestContext.chainId,
                    traceGroupId: traceGroupId,
                    parentTraceId: requestContext.parentTraceId,
                    workflowName: requestContext.workflowName.trimmed.nilIfEmpty ?? "video_chain",
                    workflowStep: "civitai_workflow_poll",
                    artifactType: requestContext.artifactType.trimmed.nilIfEmpty ?? "video_segment",
                    artifactId: artifactId,
                    model: model,
                    requestBodyFormat: "none",
                    responseBodyFormatHint: "application/json",
                    providerRequestIDHeaderCandidates: ["x-request-id", "request-id", "x-correlation-id"],
                    captureRequestBody: false,
                    captureResponseBody: false
                )
            )
            let data = traced.data
            guard let http = traced.response, (200..<300).contains(http.statusCode) else {
                let body = String(data: data.prefix(800), encoding: .utf8) ?? ""
                throw ScreenGraphError.capture("CivitAI workflow poll failed: \(body)")
            }
            guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ScreenGraphError.capture("CivitAI workflow poll response was not JSON.")
            }
            await InferenceTraceStore.shared.enrichContext(
                traceId: traced.traceId,
                responseTextJSON: inferenceTraceJSONString(redactedCivitAITracePayload(body))
            )
            let status = (body["status"] as? String ?? "").lowercased()
            if terminalStates.contains(status) {
                return CivitAIJSONResponse(object: body, traceId: traced.traceId)
            }
            if Date().timeIntervalSince(started) > 1800 {
                throw ScreenGraphError.capture("CivitAI workflow \(jobId) did not finish within 30 minutes.")
            }
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            delay = min(UInt64(Double(delay) * 1.5), 30)
        }
    }

    private func download(
        url: URL,
        to outputURL: URL,
        traceGroupId: String,
        requestContext: VideoClipRequest
    ) async throws -> String {
        try ensureDirectory(outputURL.deletingLastPathComponent())
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        var recordedRequest = URLRequest(url: workflowsURL.appendingPathComponent("redacted-output-capability"))
        recordedRequest.httpMethod = "GET"
        let traced = try await TracedHTTPTransport.download(
            request: request,
            recordedRequest: recordedRequest,
            metadata: InferenceTraceRequestMetadata(
                provider: "civitai",
                apiFamily: "video",
                operation: "output_download",
                projectId: requestContext.projectId,
                runId: requestContext.runId.trimmed.nilIfEmpty ?? requestContext.chainId,
                traceGroupId: traceGroupId,
                parentTraceId: requestContext.parentTraceId,
                workflowName: requestContext.workflowName.trimmed.nilIfEmpty ?? "video_chain",
                workflowStep: "civitai_output_download",
                artifactType: requestContext.artifactType.trimmed.nilIfEmpty ?? "video_segment",
                artifactId: requestContext.segmentId,
                model: requestContext.modelSelection.providerModelId,
                requestBodyFormat: "none",
                responseBodyFormatHint: "video/mp4",
                requestTextJSON: inferenceTraceJSONString([
                    "source": "[redacted-provider-media-capability]"
                ]),
                providerRequestIDHeaderCandidates: ["x-request-id", "request-id", "x-correlation-id"],
                captureRequestBody: false,
                captureResponseBody: false
            )
        )
        guard let http = traced.response, (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture("CivitAI output download failed.")
        }
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: traced.temporaryURL, to: outputURL)
        let outputData = try Data(contentsOf: outputURL)
        await InferenceTraceStore.shared.enrichContext(
            traceId: traced.traceId,
            mediaRefsJSON: inferenceTraceJSONString([
                "output": [
                    "filename": outputURL.lastPathComponent,
                    "sha256": sha256Hex(outputData),
                    "mime_type": "video/mp4"
                ]
            ])
        )
        return traced.traceId
    }

    private func outputVideoURLs(from body: [String: Any]) -> [URL] {
        guard let steps = body["steps"] as? [[String: Any]] else { return [] }
        var urls: [URL] = []
        for step in steps {
            guard let output = step["output"] as? [String: Any] else { continue }
            for key in ["video", "videos", "outputs", "media", "blob"] {
                let value = output[key]
                let items: [Any]
                if let array = value as? [Any] {
                    items = array
                } else if let value {
                    items = [value]
                } else {
                    items = []
                }
                for item in items {
                    if let text = item as? String, let url = URL(string: text) {
                        urls.append(url)
                    } else if let dict = item as? [String: Any] {
                        let text = firstString(in: dict, keys: ["url", "previewUrl"])
                        if let url = URL(string: text), !text.isEmpty {
                            urls.append(url)
                        } else if let blob = dict["blob"] as? [String: Any],
                                  let url = URL(string: firstString(in: blob, keys: ["url"])) {
                            urls.append(url)
                        }
                    }
                }
            }
        }
        return urls
    }
}

struct FALImageToVideoProvider: VideoGenerationProvider {
    let credentialStore: LitScenesCredentialResolving
    var providerId: VideoProviderSelection { .falImageToVideo }

    func capability(
        outputProfile: VideoOutputProfile,
        durationSeconds: Int
    ) -> VideoProviderCapability {
        VideoProviderCapability.capability(
            for: providerId,
            outputProfile: outputProfile,
            durationSeconds: durationSeconds,
            credentialStore: credentialStore
        )
    }

    func generateClip(from request: VideoClipRequest) async throws -> VideoClipResult {
        // Every wired FAL i2v schema marks its start image REQUIRED (Kling 3
        // Pro included, last checked) — tail-only lead-ins are refused
        // here until a FAL endpoint verifiably accepts an end frame alone.
        guard request.startFrameURL != nil else {
            throw ScreenGraphError.capture("FAL Image-to-Video requires a start frame.")
        }
        let result = try await FALVideoClient(credentialStore: credentialStore)
            .generateImageToVideo(from: FALImageToVideoRequest(
                projectId: request.projectId,
                runId: request.runId.trimmed.nilIfEmpty ?? request.chainId,
                traceGroupId: request.traceGroupId.trimmed.nilIfEmpty ?? request.chainId,
                workflowName: request.workflowName,
                artifactType: request.artifactType,
                artifactId: request.segmentId,
                modelSelection: request.modelSelection,
                prompt: request.prompt,
                negativePrompt: request.negativePrompt,
                durationSeconds: request.durationSeconds,
                generateAudio: request.generateAudio,
                outputProfile: request.outputProfile,
                startFrameURL: request.startFrameURL,
                targetEndFrameURL: request.targetEndFrameURL,
                outputURL: request.outputURL,
                multiShotPrompts: request.multiShotPrompts,
                promptIsStructured: request.promptIsStructured
            ))
        return VideoClipResult(
            providerId: providerId,
            providerVideoId: "",
            providerJobId: result.requestId,
            providerOperation: "image-to-video",
            traceId: result.traceId,
            traceIds: result.traceIds,
            providerNativeSize: result.providerNativeSize,
            outputURL: result.outputURL,
            responseSnapshot: result.responseSnapshot
        )
    }
}

struct FALAudioToVideoProvider: VideoGenerationProvider {
    let credentialStore: LitScenesCredentialResolving
    var providerId: VideoProviderSelection { .falAudioToVideo }

    func capability(
        outputProfile: VideoOutputProfile,
        durationSeconds: Int
    ) -> VideoProviderCapability {
        VideoProviderCapability.capability(
            for: providerId,
            outputProfile: outputProfile,
            durationSeconds: durationSeconds,
            credentialStore: credentialStore
        )
    }

    func generateClip(from request: VideoClipRequest) async throws -> VideoClipResult {
        guard let audioDriverURL = request.audioDriverURL,
              let exactDuration = request.audioDriverDurationSeconds,
              let startFrameURL = request.startFrameURL else {
            throw ScreenGraphError.capture(
                "FAL LTX Audio-to-Video needs an authored narration driver and a start frame."
            )
        }
        let result = try await FALVideoClient(credentialStore: credentialStore)
            .generateAudioToVideo(from: FALAudioToVideoRequest(
                projectId: request.projectId,
                runId: request.runId.trimmed.nilIfEmpty ?? request.chainId,
                traceGroupId: request.traceGroupId.trimmed.nilIfEmpty ?? request.chainId,
                parentTraceId: request.parentTraceId,
                workflowName: request.workflowName,
                artifactType: request.artifactType,
                artifactId: request.segmentId,
                modelSelection: request.modelSelection,
                prompt: request.prompt,
                audioDriverURL: audioDriverURL,
                audioDriverDurationSeconds: exactDuration,
                outputProfile: request.outputProfile,
                startFrameURL: startFrameURL,
                outputURL: request.outputURL,
                onSubmitted: request.onProviderSubmitted
            ))
        return VideoClipResult(
            providerId: providerId,
            providerVideoId: "",
            providerJobId: result.requestId,
            providerOperation: "audio-to-video",
            traceId: result.traceId,
            traceIds: result.traceIds,
            providerNativeSize: result.providerNativeSize,
            outputURL: result.outputURL,
            responseSnapshot: result.responseSnapshot
        )
    }
}

struct KlingImageToVideoProvider: VideoGenerationProvider {
    let credentialStore: LitScenesCredentialResolving
    var providerId: VideoProviderSelection { .klingImageToVideo }

    private static let requestTimeout: TimeInterval = 120
    private static let pollTimeout: TimeInterval = 1_800
    private static let promptCharacterLimit = 2_500
    private static let pollIntervalNanoseconds: UInt64 = 5_000_000_000
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 1_800
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    private let imageToVideoURL = URL(string: "https://api.klingai.com/v1/videos/image2video")!
    private let successStatuses: Set<String> = ["succeed", "succeeded", "success", "completed", "complete"]
    private let failureStatuses: Set<String> = ["failed", "failure", "error", "canceled", "cancelled", "rejected", "expired"]

    func capability(outputProfile: VideoOutputProfile, durationSeconds: Int) -> VideoProviderCapability {
        VideoProviderCapability.capability(for: providerId, outputProfile: outputProfile, durationSeconds: durationSeconds, credentialStore: credentialStore)
    }

    func generateClip(from request: VideoClipRequest) async throws -> VideoClipResult {
        let credential = try resolvedCredential()
        // Kling's API takes image and/or image_tail — at least one. A missing
        // start frame is valid only as a tail-anchored lead-in.
        guard request.startFrameURL != nil || request.targetEndFrameURL != nil else {
            throw ScreenGraphError.capture("Kling Image-to-Video requires a start or tail frame.")
        }
        let providerDurationSeconds = try klingProviderDurationSeconds(for: request.durationSeconds)
        let providerPrompt = klingProviderText(
            request.prompt,
            fallback: "Animate the supplied image with coherent story motion."
        )
        let providerNegativePrompt = klingProviderText(request.negativePrompt, fallback: "")

        var payload: [String: Any] = [
            "model_name": request.modelSelection.providerModelId,
            "mode": request.targetEndFrameURL == nil ? "std" : "pro",
            "prompt": providerPrompt.sentText,
            "duration": "\(providerDurationSeconds)"
        ]
        if let startFrameURL = request.startFrameURL {
            payload["image"] = try base64Image(at: startFrameURL)
        }
        if !providerNegativePrompt.sentText.isEmpty {
            payload["negative_prompt"] = providerNegativePrompt.sentText
        }
        if let targetEndFrameURL = request.targetEndFrameURL {
            payload["image_tail"] = try base64Image(at: targetEndFrameURL)
        }

        let traceGroupId = videoTraceGroupId(chainId: request.chainId, segmentId: request.segmentId)
        let submitted = try await postJSON(
            token: credential.bearerToken(),
            url: imageToVideoURL,
            payload: payload,
            operation: "submit",
            traceGroupId: traceGroupId,
            artifactId: request.segmentId,
            model: request.modelSelection.providerModelId
        )
        let submitData = submitted.object["data"] as? [String: Any] ?? submitted.object
        let taskId = firstString(in: submitData, keys: ["task_id", "taskId", "id", "job_id", "jobId"])
        guard !taskId.isEmpty else {
            throw ScreenGraphError.capture("Kling submit returned no task id.")
        }

        let final = try await pollTask(
            token: credential.bearerToken(),
            taskId: taskId,
            traceGroupId: traceGroupId,
            artifactId: request.segmentId,
            model: request.modelSelection.providerModelId
        )
        let finalData = final.object["data"] as? [String: Any] ?? final.object
        let status = klingTaskStatus(in: finalData)
        guard successStatuses.contains(status) else {
            throw ScreenGraphError.capture(klingTerminalTaskError(taskId: taskId, response: final))
        }
        guard let video = firstKlingVideo(in: finalData) else {
            throw ScreenGraphError.capture("Kling task \(taskId) completed without video metadata.")
        }
        let videoURLString = firstString(in: video, keys: ["url", "video_url", "videoUrl", "download_url", "downloadUrl", "resource"])
        guard let videoURL = URL(string: videoURLString), !videoURLString.isEmpty else {
            throw ScreenGraphError.capture("Kling task \(taskId) completed without a downloadable video URL.")
        }

        let needsLocalTrim = providerDurationSeconds != request.durationSeconds
        let nativeOutputURL = needsLocalTrim
            ? klingNativeOutputURL(finalOutputURL: request.outputURL, providerDurationSeconds: providerDurationSeconds)
            : request.outputURL
        let downloaded = try await downloadVideo(url: videoURL, outputURL: nativeOutputURL)
        if needsLocalTrim {
            _ = try await VideoChainMedia.extractTimeRange(
                videoURL: nativeOutputURL,
                outputURL: request.outputURL,
                startSeconds: 0,
                durationSeconds: Double(request.durationSeconds)
            )
        }
        return VideoClipResult(
            providerId: providerId,
            providerVideoId: firstString(in: video, keys: ["id", "video_id", "videoId"]),
            providerJobId: taskId,
            providerOperation: "image2video",
            traceId: final.traceId.isEmpty ? submitted.traceId : final.traceId,
            traceIds: uniqueTraceIds([submitted.traceId, final.traceId]),
            providerNativeSize: "\(request.outputProfile.width)x\(request.outputProfile.height)",
            outputURL: request.outputURL,
            responseSnapshot: [
                "request_id": final.requestId.isEmpty ? submitted.requestId : final.requestId,
                "task_id": taskId,
                "status": status,
                "model": request.modelSelection.providerModelId,
                "mode": payload["mode"] as? String ?? "",
                "provider_duration_seconds": "\(providerDurationSeconds)",
                "local_duration_seconds": "\(request.durationSeconds)",
                "trimmed_locally": needsLocalTrim ? "true" : "false",
                "prompt_original_characters": "\(providerPrompt.originalCharacterCount)",
                "prompt_sent_characters": "\(providerPrompt.sentCharacterCount)",
                "prompt_truncated": providerPrompt.wasTruncated ? "true" : "false",
                "negative_prompt_original_characters": "\(providerNegativePrompt.originalCharacterCount)",
                "negative_prompt_sent_characters": "\(providerNegativePrompt.sentCharacterCount)",
                "negative_prompt_truncated": providerNegativePrompt.wasTruncated ? "true" : "false",
                "content_type": downloaded.contentType,
                "bytes": "\(downloaded.byteCount)",
                "source_url": videoURL.absoluteString
            ]
        )
    }

    private func resolvedCredential() throws -> KlingCredential {
        let combined = credentialStore.resolvedCredential(for: .kling)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if combined.split(separator: ".").count == 3 {
            return KlingCredential(bearerTokenValue: combined)
        }
        if let separator = combined.firstIndex(of: ":") {
            let accessKey = String(combined[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let secretKey = String(combined[combined.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !accessKey.isEmpty, !secretKey.isEmpty {
                return KlingCredential(accessKey: accessKey, secretKey: secretKey)
            }
        }
        let accessKey = firstNonEmptyCredential(keys: ["KLING_ACCESS_KEY", "KLINGAI_ACCESS_KEY"])
        let secretKey = firstNonEmptyCredential(keys: ["KLING_SECRET_KEY", "KLINGAI_SECRET_KEY"])
        if !accessKey.isEmpty, !secretKey.isEmpty {
            return KlingCredential(accessKey: accessKey, secretKey: secretKey)
        }
        throw ScreenGraphError.credentials("Kling expects KLING_API_KEY as ACCESS_KEY:SECRET_KEY, or KLING_ACCESS_KEY plus KLING_SECRET_KEY.")
    }

    private func klingProviderText(_ text: String, fallback: String) -> KlingProviderText {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackText = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = cleaned.isEmpty ? fallbackText : cleaned
        guard source.count > Self.promptCharacterLimit else {
            return KlingProviderText(
                sentText: source,
                originalCharacterCount: cleaned.count,
                sentCharacterCount: source.count,
                wasTruncated: false
            )
        }

        let marker = "\n\n[trimmed for Kling prompt limit]\n\n"
        let available = max(Self.promptCharacterLimit - marker.count, 0)
        let tailBudget = min(520, max(0, available / 4))
        let headBudget = max(0, available - tailBudget)
        let head = String(source.prefix(headBudget)).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(source.suffix(tailBudget)).trimmingCharacters(in: .whitespacesAndNewlines)
        var sent = "\(head)\(marker)\(tail)"
        if sent.count > Self.promptCharacterLimit {
            sent = String(sent.prefix(Self.promptCharacterLimit))
        }
        return KlingProviderText(
            sentText: sent,
            originalCharacterCount: cleaned.count,
            sentCharacterCount: sent.count,
            wasTruncated: true
        )
    }

    private func klingProviderDurationSeconds(for requestedDurationSeconds: Int) throws -> Int {
        let supported = [5, 10]
        if supported.contains(requestedDurationSeconds) {
            return requestedDurationSeconds
        }
        if let next = supported.first(where: { requestedDurationSeconds > 0 && $0 >= requestedDurationSeconds }) {
            return next
        }
        throw ScreenGraphError.capture("Kling Image-to-Video supports 5s or 10s native clips; \(requestedDurationSeconds)s is too long for this provider.")
    }

    private func klingNativeOutputURL(finalOutputURL: URL, providerDurationSeconds: Int) -> URL {
        let base = finalOutputURL.deletingPathExtension().lastPathComponent
        return finalOutputURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(base)_kling_native_\(providerDurationSeconds)s.mp4")
    }

    private func firstNonEmptyCredential(keys: [String]) -> String {
        for key in keys {
            let value = credentialStore.resolvedCredentialValue(forKey: key)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private func base64Image(at url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ScreenGraphError.capture("Kling image input is missing.")
        }
        return try Data(contentsOf: url).base64EncodedString()
    }

    private func postJSON(
        token: String,
        url: URL,
        payload: [String: Any],
        operation: String,
        traceGroupId: String,
        artifactId: String,
        model: String
    ) async throws -> KlingJSONResponse {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = Self.requestTimeout
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return try await performJSONRequest(
            urlRequest,
            operation: operation,
            traceGroupId: traceGroupId,
            artifactId: artifactId,
            model: model,
            requestTextJSON: inferenceTraceJSONString(redactedKlingPayload(payload))
        )
    }

    private func getJSON(
        token: String,
        url: URL,
        operation: String,
        traceGroupId: String,
        artifactId: String,
        model: String
    ) async throws -> KlingJSONResponse {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.timeoutInterval = Self.requestTimeout
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await performJSONRequest(
            urlRequest,
            operation: operation,
            traceGroupId: traceGroupId,
            artifactId: artifactId,
            model: model
        )
    }

    private func performJSONRequest(
        _ request: URLRequest,
        operation: String,
        traceGroupId: String,
        artifactId: String,
        model: String,
        requestTextJSON: String = ""
    ) async throws -> KlingJSONResponse {
        let data: Data
        let http: HTTPURLResponse?
        let traceId: String
        do {
            let traced = try await TracedHTTPTransport.send(
                request: request,
                metadata: InferenceTraceRequestMetadata(
                    provider: "kling",
                    apiFamily: "video",
                    operation: operation,
                    traceGroupId: traceGroupId,
                    workflowName: "video_chain",
                    workflowStep: "kling_\(operation)",
                    artifactType: "video_segment",
                    artifactId: artifactId,
                    model: model,
                    requestBodyFormat: request.httpBody == nil ? "none" : "application/json",
                    responseBodyFormatHint: "application/json",
                    requestTextJSON: requestTextJSON,
                    providerRequestIDHeaderCandidates: ["x-request-id", "request-id", "x-log-id"],
                    captureRequestBody: false
                )
            )
            data = traced.data
            http = traced.response
            traceId = traced.traceId
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw ScreenGraphError.capture("Kling \(operation) timed out after \(Int(Self.requestTimeout))s.")
            }
            throw error
        }
        guard let http else {
            throw ScreenGraphError.capture("Kling \(operation) returned a non-HTTP response.")
        }
        let requestId = providerRequestId(from: http)
        guard (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture(formattedKlingProviderError(operation: operation, status: http.statusCode, data: data, requestId: requestId))
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScreenGraphError.capture("Kling \(operation) response was not JSON.")
        }
        if let code = object["code"] as? Int, code != 0 {
            throw ScreenGraphError.capture(formattedKlingProviderError(operation: operation, status: http.statusCode, data: data, requestId: requestId))
        }
        if let code = object["code"] as? String, !code.isEmpty, code != "0" {
            throw ScreenGraphError.capture(formattedKlingProviderError(operation: operation, status: http.statusCode, data: data, requestId: requestId))
        }
        return KlingJSONResponse(
            object: object,
            requestId: requestId.isEmpty ? firstString(in: object, keys: ["request_id", "requestId"]) : requestId,
            traceId: traceId
        )
    }

    private func pollTask(
        token: String,
        taskId: String,
        traceGroupId: String,
        artifactId: String,
        model: String
    ) async throws -> KlingJSONResponse {
        let deadline = Date().addingTimeInterval(Self.pollTimeout)
        let url = imageToVideoURL.appendingPathComponent(taskId)
        while Date() < deadline {
            let response = try await getJSON(
                token: token,
                url: url,
                operation: "poll",
                traceGroupId: traceGroupId,
                artifactId: artifactId,
                model: model
            )
            let data = response.object["data"] as? [String: Any] ?? response.object
            let status = klingTaskStatus(in: data)
            if successStatuses.contains(status) || failureStatuses.contains(status) {
                return response
            }
            try await Task.sleep(nanoseconds: Self.pollIntervalNanoseconds)
        }
        throw ScreenGraphError.capture("Kling task \(taskId) timed out after \(Int(Self.pollTimeout))s.")
    }

    private func downloadVideo(url: URL, outputURL: URL) async throws -> KlingDownloadResult {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.pollTimeout
        request.setValue("video/mp4,application/octet-stream", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                throw ScreenGraphError.capture("Kling output download timed out after \(Int(Self.pollTimeout))s.")
            }
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw ScreenGraphError.capture("Kling output download returned a non-HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ScreenGraphError.capture(formattedKlingProviderError(operation: "download", status: http.statusCode, data: data, requestId: providerRequestId(from: http)))
        }
        try ensureDirectory(outputURL.deletingLastPathComponent())
        try data.write(to: outputURL, options: [.atomic])
        return KlingDownloadResult(contentType: http.value(forHTTPHeaderField: "content-type") ?? "video/mp4", byteCount: data.count)
    }
}

struct VideoProviderRegistry {
    let credentialStore: LitScenesCredentialResolving

    func provider(for selection: VideoProviderSelection) -> VideoGenerationProvider {
        switch selection {
        case .bestAvailable, .localPromptExport:
            return LocalPromptExportProvider(credentialStore: credentialStore)
        case .localExistingClip:
            return LocalExistingClipProvider(credentialStore: credentialStore)
        case .ltxDirect:
            return LTXDirectVideoProvider(credentialStore: credentialStore)
        case .civitaiWan:
            return CivitAIWANVideoProvider(credentialStore: credentialStore)
        case .klingImageToVideo:
            return KlingImageToVideoProvider(credentialStore: credentialStore)
        case .falImageToVideo:
            return FALImageToVideoProvider(credentialStore: credentialStore)
        case .falAudioToVideo:
            return FALAudioToVideoProvider(credentialStore: credentialStore)
        }
    }
}

private struct LTXUploadResult {
    var storageURI: String
    var sha256: String
    var traceId: String = ""
    var traceIds: [String] = []
}

private struct LTXDirectVideoResponse {
    var requestId: String
    var contentType: String
    var byteCount: Int
    var jobId: String = ""
    var status: String = ""
    var retryCount: Int = 0
    var traceId: String = ""
    var traceIds: [String] = []
}

private struct LTXJSONResponse {
    var object: [String: Any]
    var requestId: String
    var traceId: String = ""
}

private struct LTXAsyncPollResult {
    var response: LTXJSONResponse
    var retryCount: Int
}

private struct LTXDownloadResult {
    var contentType: String
    var byteCount: Int
    var traceId: String = ""
}

private struct KlingCredential {
    var accessKey: String = ""
    var secretKey: String = ""
    var bearerTokenValue: String = ""

    func bearerToken() throws -> String {
        if !bearerTokenValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return bearerTokenValue
        }
        let accessKey = accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessKey.isEmpty, !secretKey.isEmpty else {
            throw ScreenGraphError.credentials("Kling access key and secret key are required.")
        }
        let now = Int(Date().timeIntervalSince1970)
        let header: [String: Any] = ["alg": "HS256", "typ": "JWT"]
        let payload: [String: Any] = ["iss": accessKey, "exp": now + 1_800, "nbf": now - 5]
        let headerText = try base64URLJSON(header)
        let payloadText = try base64URLJSON(payload)
        let signingInput = "\(headerText).\(payloadText)"
        let key = SymmetricKey(data: Data(secretKey.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: key)
        return "\(signingInput).\(base64URL(Data(signature)))"
    }
}

private struct CivitAIJSONResponse {
    var object: [String: Any]
    var traceId: String = ""
}

private struct KlingJSONResponse {
    var object: [String: Any]
    var requestId: String
    var traceId: String = ""
}

private struct KlingDownloadResult {
    var contentType: String
    var byteCount: Int
}

private struct KlingProviderText {
    var sentText: String
    var originalCharacterCount: Int
    var sentCharacterCount: Int
    var wasTruncated: Bool
}

private func base64URLJSON(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return base64URL(data)
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func providerRequestId(from response: HTTPURLResponse?) -> String {
    response?.value(forHTTPHeaderField: "x-request-id")
        ?? response?.value(forHTTPHeaderField: "request-id")
        ?? response?.value(forHTTPHeaderField: "x-correlation-id")
        ?? response?.value(forHTTPHeaderField: "x-log-id")
        ?? ""
}

private func videoTraceGroupId(chainId: String, segmentId: String) -> String {
    let cleanedChainId = chainId.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanedSegmentId = segmentId.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleanedChainId.isEmpty {
        return cleanedSegmentId
    }
    if cleanedSegmentId.isEmpty {
        return cleanedChainId
    }
    return "\(cleanedChainId):\(cleanedSegmentId)"
}

private func uniqueTraceIds(_ ids: [String]) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for id in ids {
        let cleaned = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !seen.contains(cleaned) else { continue }
        seen.insert(cleaned)
        result.append(cleaned)
    }
    return result
}

private func redactedKlingPayload(_ payload: [String: Any]) -> [String: Any] {
    var redacted: [String: Any] = payload
    for key in ["image", "image_tail"] {
        guard let encoded = payload[key] as? String else {
            redacted.removeValue(forKey: key)
            continue
        }
        redacted.removeValue(forKey: key)
        if let data = Data(base64Encoded: encoded) {
            redacted["\(key)_sha256"] = sha256Hex(data)
            redacted["\(key)_bytes"] = data.count
        } else {
            redacted["\(key)_base64_characters"] = encoded.count
        }
    }
    return redacted
}

private func klingTaskStatus(in dictionary: [String: Any]) -> String {
    let direct = firstString(in: dictionary, keys: ["task_status", "taskStatus", "status", "state"])
    if !direct.isEmpty {
        return direct.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    if let data = dictionary["data"] as? [String: Any] {
        return klingTaskStatus(in: data)
    }
    return ""
}

private func firstKlingVideo(in dictionary: [String: Any]) -> [String: Any]? {
    if let taskResult = dictionary["task_result"] as? [String: Any],
       let video = firstVideoDictionary(in: taskResult) {
        return video
    }
    if let taskResult = dictionary["taskResult"] as? [String: Any],
       let video = firstVideoDictionary(in: taskResult) {
        return video
    }
    return firstVideoDictionary(in: dictionary)
}

private func firstVideoDictionary(in dictionary: [String: Any]) -> [String: Any]? {
    for key in ["videos", "video", "outputs", "media", "result"] {
        guard let value = dictionary[key] else { continue }
        if let array = value as? [[String: Any]], let first = array.first {
            return first
        }
        if let dictionary = value as? [String: Any] {
            if firstString(in: dictionary, keys: ["url", "video_url", "videoUrl", "download_url", "downloadUrl", "resource"]).isEmpty,
               let nested = firstVideoDictionary(in: dictionary) {
                return nested
            }
            return dictionary
        }
        if let text = value as? String, !text.isEmpty {
            return ["url": text]
        }
    }
    return nil
}

private func klingTerminalTaskError(taskId: String, response: KlingJSONResponse) -> String {
    let data = response.object["data"] as? [String: Any] ?? response.object
    var message = firstString(in: data, keys: ["task_status_msg", "taskStatusMsg", "message", "msg", "error_message", "errorMessage"])
    var code = firstString(in: data, keys: ["task_status_code", "taskStatusCode", "code", "error_code", "errorCode"])
    if let error = data["error"] as? [String: Any] {
        message = firstString(in: error, keys: ["message", "msg", "error_message", "errorMessage"])
        code = firstString(in: error, keys: ["code", "error_code", "errorCode"])
    }
    if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        message = "The provider marked the task as \(klingTaskStatus(in: data))."
    }
    let codePart = code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : ", code=\(code)"
    let requestPart = response.requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : ", request_id=\(response.requestId)"
    return "Kling task failed (task_id=\(taskId)\(codePart)\(requestPart)): \(message)"
}

private func formattedKlingProviderError(operation: String, status: Int, data: Data, requestId: String) -> String {
    let bodyText = String(data: data.prefix(1200), encoding: .utf8) ?? ""
    var message = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    var code = ""
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        message = firstString(in: object, keys: ["message", "msg", "error_message", "errorMessage"])
        code = firstString(in: object, keys: ["code", "error_code", "errorCode"])
        if let data = object["data"] as? [String: Any], message.isEmpty {
            message = firstString(in: data, keys: ["message", "msg", "task_status_msg", "taskStatusMsg"])
            code = code.isEmpty ? firstString(in: data, keys: ["code", "task_status_code", "taskStatusCode"]) : code
        }
        if let error = object["error"] as? [String: Any], message.isEmpty {
            message = firstString(in: error, keys: ["message", "msg", "error_message", "errorMessage"])
            code = code.isEmpty ? firstString(in: error, keys: ["code", "error_code", "errorCode"]) : code
        }
    }
    if message.isEmpty {
        message = "The provider did not return an error message."
    }
    let codePart = code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : ", code=\(code)"
    let requestPart = requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : ", request_id=\(requestId)"
    return "Kling \(operation) failed (\(status)\(codePart)\(requestPart)): \(message)"
}

private struct LTXProviderRequestError: LocalizedError {
    var message: String
    var status: Int
    var requestId: String
    var retryable: Bool

    var errorDescription: String? { message }
}

private let ltxSuccessStatuses: Set<String> = ["completed", "complete", "succeeded", "success", "ready"]
private let ltxFailureStatuses: Set<String> = ["failed", "error", "canceled", "cancelled", "expired", "rejected"]

private func ltxRequestId(from response: HTTPURLResponse?) -> String {
    response?.value(forHTTPHeaderField: "x-request-id")
        ?? response?.value(forHTTPHeaderField: "request-id")
        ?? response?.value(forHTTPHeaderField: "x-correlation-id")
        ?? ""
}

private func translatedLTXTransportError(
    _ error: Error,
    operation: String,
    timeout: TimeInterval,
    expectsVideoResponse: Bool
) -> Error {
    if let urlError = error as? URLError, urlError.code == .timedOut {
        return ltxTimeoutError(operation: operation, timeout: timeout, expectsVideoResponse: expectsVideoResponse)
    }
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut {
        return ltxTimeoutError(operation: operation, timeout: timeout, expectsVideoResponse: expectsVideoResponse)
    }
    return error
}

private func isLTXTimeout(_ error: Error) -> Bool {
    if let urlError = error as? URLError, urlError.code == .timedOut {
        return true
    }
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
}

private func isRetryableLTXFailure(_ error: Error) -> Bool {
    if let providerError = error as? LTXProviderRequestError {
        return providerError.retryable
    }
    return isLTXTimeout(error)
}

private func ltxTimeoutError(operation: String, timeout: TimeInterval, expectsVideoResponse: Bool) -> ScreenGraphError {
    let seconds = Int(timeout.rounded())
    if expectsVideoResponse {
        return .capture("LTX \(operation) timed out after \(seconds)s; the provider may still be processing, but LitScenes did not receive the MP4.")
    }
    return .capture("LTX \(operation) timed out after \(seconds)s; LitScenes did not receive a provider response.")
}

private func formattedLTXProviderError(operation: String, status: Int, data: Data, requestId: String) -> String {
    let bodyText = String(data: data.prefix(1200), encoding: .utf8) ?? ""
    var message = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    var code = ""
    var type = ""
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let error = object["error"] as? [String: Any] {
            message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? message
            code = (error["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            type = (error["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } else {
            message = (object["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? message
            code = (object["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            type = (object["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }
    if message.isEmpty {
        message = "The provider did not return an error message."
    }
    let stableCode = code.isEmpty ? type : code
    let codePart = stableCode.isEmpty ? "" : ", code=\(stableCode)"
    let requestPart = requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : ", request_id=\(requestId)"
    return "LTX \(operation) failed (\(status)\(codePart)\(requestPart)): \(message)"
}

private func ltxStatus(in dictionary: [String: Any]) -> String {
    let direct = firstString(in: dictionary, keys: ["status", "state"])
    if !direct.isEmpty {
        return direct.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    if let job = dictionary["job"] as? [String: Any] {
        return ltxStatus(in: job)
    }
    return ""
}

private func ltxResultVideoURLString(from dictionary: [String: Any]) -> String {
    if let result = dictionary["result"] as? [String: Any] {
        let direct = firstString(in: result, keys: ["video_url", "videoUrl", "url", "download_url", "downloadUrl"])
        if !direct.isEmpty {
            return direct
        }
        if let videos = result["videos"] as? [[String: Any]] {
            for video in videos {
                let videoURL = firstString(in: video, keys: ["video_url", "videoUrl", "url", "download_url", "downloadUrl"])
                if !videoURL.isEmpty {
                    return videoURL
                }
            }
        }
    }
    let direct = firstString(in: dictionary, keys: ["video_url", "videoUrl", "url", "download_url", "downloadUrl"])
    if !direct.isEmpty {
        return direct
    }
    if let outputs = dictionary["outputs"] as? [[String: Any]] {
        for output in outputs {
            let outputURL = firstString(in: output, keys: ["video_url", "videoUrl", "url", "download_url", "downloadUrl"])
            if !outputURL.isEmpty {
                return outputURL
            }
        }
    }
    return ""
}

private func ltxTerminalJobError(operation: String, jobId: String, response: LTXJSONResponse) -> String {
    var message = firstString(in: response.object, keys: ["message", "error_message", "errorMessage"])
    var code = firstString(in: response.object, keys: ["code", "type"])
    if let error = response.object["error"] as? [String: Any] {
        message = firstString(in: error, keys: ["message", "error_message", "errorMessage"])
        code = firstString(in: error, keys: ["code", "type"])
    }
    if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        message = "The provider marked the job as \(ltxStatus(in: response.object))."
    }
    let codePart = code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : ", code=\(code)"
    let requestPart = response.requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : ", request_id=\(response.requestId)"
    return "LTX \(operation) job failed (job_id=\(jobId)\(codePart)\(requestPart)): \(message)"
}

private func firstString(in dictionary: [String: Any], keys: [String]) -> String {
    for key in keys {
        if let value = dictionary[key] as? String, !value.isEmpty {
            return value
        }
    }
    return ""
}

private func mediaMIMEType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg": "image/jpeg"
    case "png": "image/png"
    case "webp": "image/webp"
    case "mp4": "video/mp4"
    default: "application/octet-stream"
    }
}
