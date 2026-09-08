import Foundation

/// Shared provider dispatch for whole-Shot segments and independent continuations.
/// The caller supplies durable destinations and owns its own persistence identity.
enum ShotClipGenerationInput {
    case frame(VideoClipRequest)
    case native(VideoClipExtendRequest, tailURL: URL)
}

func generateShotClip(provider: VideoGenerationProvider, input: ShotClipGenerationInput, onProviderCompleted: (@MainActor (VideoClipResult) async -> Void)? = nil) async throws -> VideoClipResult {
    switch input {
    case .frame(let request):
        let result = try await provider.generateClip(from: request)
        await onProviderCompleted?(result)
        return result
    case .native(let request, let tailURL):
        guard let native = provider as? LTXDirectVideoProvider else {
            throw ScreenGraphError.capture("The selected provider cannot execute Native Extend")
        }
        var result = try await native.generateExtension(from: request)
        await onProviderCompleted?(result)
        _ = try await VideoChainMedia.extractTailSegment(videoURL: result.outputURL, outputURL: tailURL, durationSeconds: Double(request.durationSeconds))
        result.outputURL = tailURL
        return result
    }
}

func safeShotContinuationError(_ error: Error, phase: String) -> String {
    var message = error.localizedDescription
    for pattern in [#"https?://[^\s\"<>]+"#, #"/Users/[^\s\"<>]+"#, #"(?i)(bearer\s+|(?:api[_-]?key|token|secret)\s*[:=]\s*)[^\s,\"}]+"#] {
        message = message.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
    }
    return "\(phase): \(String(message.prefix(300)))"
}

func recordShotContinuationEvent(take: ShotContinuationTake, projectId: String, shotId: String,
    phase: String, status: String, message: String = "", latencyMs: Int = 0) async {
    guard let url = URL(string: "litscenes://continuation/\(safeIdentifier(take.takeId))") else { return }
    var media: [String: Any] = [
        "anchor_fingerprint": take.anchor.resolvedFingerprint,
        "anchor_frame_fingerprint": take.anchor.frameFingerprint,
        "output_fingerprint": take.outputFingerprint,
        "target_frame_fingerprint": take.targetFrame?.fingerprint ?? "",
        "target_frame_id": take.targetFrame?.imageId ?? "",
        "source_kind": take.anchor.sourceKind,
        "source_take_id": take.anchor.sourceTakeId,
        "source_render_version_id": take.anchor.sourceRenderVersionId
    ]
    if let endpoint = take.anchor.endpointEvidence {
        media["endpoint_revision"] = endpoint.revision
        media["source_video_fingerprint"] = endpoint.sourceFingerprint
        media["source_start_seconds"] = endpoint.sourceStartSeconds
        media["source_end_seconds"] = endpoint.sourceEndSeconds
        media["endpoint_requested_seconds"] = endpoint.requestedSeconds
        media["endpoint_actual_seconds"] = endpoint.actualSeconds
    }
    let metadata = InferenceTraceRequestMetadata(
        provider: take.renderStack.providerSelection.rawValue, apiFamily: "local_workflow",
        operation: status, projectId: projectId, runId: take.takeId,
        traceGroupId: "shot_continuation_\(shotId)", parentTraceId: take.traceId,
        workflowName: "shot_continuation", workflowStep: phase,
        artifactType: "shot_continuation_take", artifactId: take.takeId,
        model: take.renderStack.model.label,
        requestTextJSON: inferenceTraceJSONString(["operator_prompt": take.prompt, "stack": take.stack]),
        responseTextJSON: inferenceTraceJSONString(["status": status, "message": message, "request_id": take.requestId]),
        mediaRefsJSON: inferenceTraceJSONString(media),
        captureRequestBody: false, captureResponseBody: false
    )
    let failure: Error? = ["error", "canceled", "interrupted"].contains(status)
        ? ScreenGraphError.capture(message) : nil
    let traceId = await InferenceTraceStore.shared.record(request: URLRequest(url: url), metadata: metadata,
        response: nil, responseBody: nil, latencyMs: latencyMs, error: failure)
    if let context = WorkflowContext.current, !traceId.isEmpty {
        await WorkflowCoordinator.shared.transition(context.jobId, phase: phase,
            message: message, traceId: traceId)
    }
}
