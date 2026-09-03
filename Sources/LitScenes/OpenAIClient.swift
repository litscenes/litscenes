import Foundation

struct OpenAIAnalysisResult {
    var draft: ScreenGraphHydrationDraft
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIProjectGoalInterviewResult {
    var assistantMessage: String
    var brief: ProjectGoalBrief
    var changeSummary: String
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIProjectGoalInterviewV3Result {
    var assistantMessage: String
    var brief: ProjectGoalBriefV2
    var changeSummary: String
    var castUpdates: [ProjectGoalCastUpdate] = []
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIGoalCastResult {
    var members: [GoalCastArticulatedMember]
    var castingNote: String
    var responseId: String
    var model: String
    var usage: OpenAIUsage
}

struct OpenAIVisionImageInput {
    var mediaId: String
    var filename: String
    var mimeType: String
    var data: Data
    var detail: String = "high"
}

struct OpenAIProjectLensWorkbenchInterviewResult {
    var assistantMessage: String
    var body: LensBodyProposal
    var changeSummary: String
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIProjectArchiveMeaningResult {
    var graph: ProjectArchiveMeaningGraph
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIStorySignalSetResult {
    var signalSet: StorySignalSet
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIStoryDirectionSetResult {
    var directionSet: StoryDirectionSet
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIStorylineCreationInterviewResult {
    var assistantMessage: String
    var draft: StorylineCreationDraft
    var changeSummary: String
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIStorySingleStorylineResult {
    var direction: StoryDirectionCard
    var changeSummary: String
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIStoryBeatBoardResult {
    var beatBoard: StoryBeatBoard
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIStoryBeatSheetResult {
    var beatSheet: StoryBeatSheet
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIStoryAudioTrackDraftResult {
    var draft: StoryAudioTrackDraft
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAIMediaObservationResult {
    var observation: ImageObservationResult
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

struct OpenAILensNarrationResult {
    var script: String
    var responseId: String
    var model: String
    var traceId: String
}

struct OpenAIShotNarrationChipsResult {
    var statements: [String]
    var responseId: String
    var model: String
    var traceId: String
}

/// Neutral primitives on purpose — the engine maps these onto the shot
/// timeline's plan types, so this client stays free of that dependency.
struct OpenAIDirectionBeat {
    var durationWeight: Int
    var action: String
    var camera: String
}

struct OpenAIShotDirectionPlanResult {
    var shotMode: String            // "continuous" | "multi_shot"
    var beats: [OpenAIDirectionBeat]
    var responseId: String
    var model: String
    var traceId: String
}

struct OpenAIFormPromptTransformResult {
    var transformedPrompt: String
    var changeNote: String
    var responseId: String
    var model: String
}

// Decoded via JSONCoding.decoder (convertFromSnakeCase): transformed_prompt /
// change_note map onto the synthesized keys.
private struct FormPromptTransformResponse: Codable {
    var transformedPrompt: String
    var changeNote: String
}

struct OpenAIYouTubePublishCopyResult {
    var title: String
    var descriptionMarkdown: String
    var responseId: String
    var model: String
}

// Decoded via JSONCoding.decoder (convertFromSnakeCase): youtube_title /
// description_markdown map onto the synthesized keys.
private struct YouTubePublishCopyResponse: Codable {
    var youtubeTitle: String
    var descriptionMarkdown: String
}

private struct ShotNarrationChipsResponse: Codable {
    var statements: [String]
}

// Decoded via JSONCoding.decoder (convertFromSnakeCase): shot_mode /
// duration_weight map onto the synthesized keys.
private struct ShotDirectionPlanResponse: Codable {
    struct Beat: Codable {
        var durationWeight: Int
        var action: String
        var camera: String
    }

    var shotMode: String
    var beats: [Beat]
}

private struct LensNarrationDraftResponse: Codable {
    var narrationText: String

    private enum CodingKeys: String, CodingKey {
        case narrationText
        case script
        case text
        case narration
        case scriptText
        case voiceoverText
    }

    init(narrationText: String) {
        self.narrationText = narrationText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let candidates = [
            try container.decodeIfPresent(String.self, forKey: .narrationText),
            try container.decodeIfPresent(String.self, forKey: .script),
            try container.decodeIfPresent(String.self, forKey: .text),
            try container.decodeIfPresent(String.self, forKey: .narration),
            try container.decodeIfPresent(String.self, forKey: .scriptText),
            try container.decodeIfPresent(String.self, forKey: .voiceoverText)
        ]
        if let script = candidates.compactMap({ $0?.trimmed.nilIfEmpty }).first {
            narrationText = script
            return
        }
        throw DecodingError.keyNotFound(
            CodingKeys.narrationText,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected a non-empty narration script field."
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(narrationText, forKey: .narrationText)
    }
}

struct OpenAIImagePromptEnrichmentResult {
    var enhancedPrompt: String
    var negativePrompt: String
    var changeSummary: String
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
    var traceId: String
}

struct OpenAIImageGenerationResult {
    var imageData: Data
    var requestId: String
    var traceId: String
    var model: String
    var revisedPrompt: String
}

private func formattedOpenAIProviderError(operation: String, status: Int, data: Data, requestId: String) -> String {
    let bodyText = String(data: data.prefix(1200), encoding: .utf8) ?? ""
    var message = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    var code = ""
    var type = ""
    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let error = object["error"] as? [String: Any] {
        message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? message
        code = (error["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        type = (error["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    let stableCode = code.isEmpty ? type : code
    let codePart = stableCode.isEmpty ? "" : ", code=\(stableCode)"
    let requestPart = requestId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : ", request_id=\(requestId)"
    return "\(operation) failed (\(status)\(codePart)\(requestPart)): \(message)"
}

struct MediaObservationGenerationContext {
    var projectId: String
    var mediaId: String
    var visionInputSha256: String
    var visionInputWidth: Int
    var visionInputHeight: Int
    var visionInputBytes: Int
    var generatedAt: String
}

struct ProjectGoalInterviewContext {
    var projectId: String
    var projectName: String
    var currentBriefJSON: String
    var recentMessagesSummary: String
    var selectedMediaSummary: String
    var mediaArchiveSummary: String
    var userMessage: String
    var generatedAt: String
}

struct ProjectGoalInterviewV3Context {
    var projectId: String
    var projectName: String
    var currentBriefJSON: String
    var recentMessagesSummary: String
    var selectedMediaSummary: String
    var mediaArchiveSummary: String
    /// Per-asset MOODBOARD analysis lines (mood, palette, motifs, place/era cues,
    /// possible meanings) — the evidence the agent reasons against the meaning choice
    /// index when hydrating meaning_node_refs and aesthetic_term_refs.
    var moodboardAnalysisContext: String = ""
    var meaningChoiceContextJSON: String
    /// Current goal-cast member lines ("- Name — essence | wants …; rule: … | strangeness …").
    /// The interview patches cast only through the cast_updates delta channel.
    var currentCastSummary: String = ""
    var userMessage: String
    var generatedAt: String
}

/// One refinement turn of a character's reference sheet conversation.
struct CharacterSheetRefineContext {
    var projectId: String
    var projectName: String
    var characterName: String
    var visualDescription: String
    var signatureProps: [String]
    var storyIdentityLines: String
    var currentDirectives: [String]
    var renderedSheetPrompt: String
    var sourceImageLines: String
    var hasActiveSheet: Bool
    var recentTurnsSummary: String
    var userMessage: String
    var generatedAt: String
    /// The transmitted prompt is the user's hand edit, so identity changes recorded
    /// this turn do not enter it until they reset or edit the prompt.
    var promptIsHandEdited: Bool = false
}

struct OpenAICharacterIdentityDraftResult: Sendable {
    var response: CharacterIdentityDraftResponse
    var responseId: String
    var model: String
    var usage: OpenAIUsage
}

struct OpenAICharacterSheetRefineResult: Sendable {
    var response: CharacterSheetRefineResponse
    var responseId: String
    var model: String
    var usage: OpenAIUsage
}

struct ProjectLensWorkbenchInterviewContext {
    var projectId: String
    var projectName: String
    var targetKind: String
    var targetId: String
    var currentBodyJSON: String
    var recentMessagesSummary: String
    var readyLensSetSummary: String
    var aestheticLibraryContext: String
    var selectedMediaSummary: String
    var goalSummary: String
    var userMessage: String
    var generatedAt: String
}

struct ProjectStoryGenerationContext {
    var projectId: String
    var projectName: String
    var scope: ProjectStoryScope
    var selectedMediaIds: [String]
    var mediaScopeSummary: String
    var storyWorldSummary: String
    var storyGenre: String
    var storyStyle: String
    var sourceContextSummary: String
    var aestheticJSON: String
    var generatedAt: String
}

struct StoryBeatGenerationContext {
    var projectId: String
    var projectName: String
    var scope: ProjectStoryScope
    var mediaScopeSummary: String
    var storyWorldSummary: String
    var storyGenre: String
    var storyStyle: String
    var sourceContextSummary: String
    var aestheticJSON: String
    var archiveMeaningJSON: String
    var generatedAt: String
}

struct StoryAudioTrackGenerationContext {
    var projectId: String
    var projectName: String
    var trackId: String
    var targetBeatId: String
    var sourceBeatIds: [String]
    var durationSeconds: Double
    var voiceDurationRange: String
    var mediaScopeSummary: String
    var storyWorldSummary: String
    var storyGenre: String
    var storyStyle: String
    var sourceContextSummary: String
    var aestheticJSON: String
    var goalBriefSummary: String
    var operatorDirection: String
    var beatBoardJSON: String
    var generatedAt: String
}

struct StorySignalSetGenerationContext {
    var projectId: String
    var projectName: String
    var signalSetId: String
    var scope: String
    var selectedMediaIds: [String]
    var promptPacketJSON: String
    var inputFingerprint: StoryInputFingerprint
    var generatedAt: String
}

struct StoryDirectionSetGenerationContext {
    var projectId: String
    var projectName: String
    var directionSetId: String
    var promptPacketJSON: String
    var inputFingerprint: StoryInputFingerprint
    var generatedAt: String
}

struct StorylineCreationInterviewContext {
    var projectId: String
    var projectName: String
    var currentDraftJSON: String
    var recentMessagesSummary: String
    var draftSetupJSON: String
    var existingDirectionsJSON: String
    var promptPacketJSON: String
    var userMessage: String
    var generatedAt: String
}

struct StorySingleStorylineGenerationContext {
    var projectId: String
    var projectName: String
    var expectedDirectionId: String
    var draftJSON: String
    var draftSetupJSON: String
    var existingDirectionsJSON: String
    var promptPacketJSON: String
    var inputFingerprint: StoryInputFingerprint
    var generatedAt: String
}

struct StoryBeatBoardGenerationContext {
    var projectId: String
    var projectName: String
    var beatBoardId: String
    var parentDirectionSetId: String
    var parentDirectionId: String
    var sourceDirectionIds: [String]
    var storySetupHash: String
    var aestheticRecipeVersion: String
    var promptPacketJSON: String
    var selectedDirectionJSON: String
    var inputFingerprint: StoryInputFingerprint
    var generatedAt: String
}

struct StoryBeatBoardEditContext {
    var projectId: String
    var projectName: String
    var operation: String
    var intent: String
    var selectedBeatId: String
    var outputBeatBoardId: String
    var generatedAt: String
    var activeBoardJSON: String
    var sourceDirectionsJSON: String
    var promptPacketJSON: String
}

struct OpenAIUsage: Codable, Hashable, Sendable {
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var inputTokensDetails: OpenAIInputTokensDetails?
    var outputTokensDetails: OpenAIOutputTokensDetails?

    var cachedInputTokens: Int {
        inputTokensDetails?.cachedTokens ?? 0
    }
}

struct OpenAIInputTokensDetails: Codable, Hashable, Sendable {
    var cachedTokens: Int?
}

struct OpenAIOutputTokensDetails: Codable, Hashable, Sendable {
    var reasoningTokens: Int?
}

private struct OpenAIResponseBody: Codable {
    var id: String
    var model: String?
    var output: [OpenAIOutputItem]
    var usage: OpenAIUsage?
    var error: OpenAIErrorBody?
}

private struct OpenAIOutputItem: Codable {
    var type: String
    var content: [OpenAIContentItem]?
}

struct OpenAIContentItem: Codable {
    var type: String
    var text: String?
    var refusal: String?
}

struct OpenAIErrorBody: Codable {
    var message: String
    var type: String?
    var code: String?
}

private struct OpenAIHTTPResult: @unchecked Sendable {
    var data: Data
    var statusCode: Int
    var response: HTTPURLResponse?
    var traceId: String
    var latencyMs: Int
}

private struct OpenAIResponseRequestResult {
    var decoded: OpenAIResponseBody
    var rawText: String
    var traceId: String
}

private struct OpenAIImageGenerationResponse: Codable {
    struct ImageData: Codable {
        var b64Json: String?
        var revisedPrompt: String?
    }

    var data: [ImageData]
    var model: String?
}

/// Feature gate for rendering reference-backed Lens media through /v1/responses with the
/// image_generation tool (references as input_image context) instead of /v1/images/edits
/// (references as edit bases). Defaults ON; set LITSCENES_RESPONSES_IMAGE_API=0 (or
/// false/no/off) to fall back to the edits endpoint.
enum ResponsesImageAPISettings {
    static func isEnabled() -> Bool {
        if let override = environmentValue("LITSCENES_RESPONSES_IMAGE_API")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !override.isEmpty {
            return !["0", "false", "no", "off"].contains(override)
        }
        return true
    }
}

/// Decode shape for /v1/responses when the image_generation tool runs: the image arrives
/// as an output item of type "image_generation_call" with base64 in `result`. Message
/// items are kept so refusals surface as readable errors.
struct OpenAIResponsesImageBody: Codable {
    struct OutputItem: Codable {
        var type: String
        var result: String?
        var revisedPrompt: String?
        var status: String?
        var content: [OpenAIContentItem]?
    }

    /// Why a 200 carried no finished output — e.g. `max_output_tokens`,
    /// `content_filter`. Absent on completed responses.
    struct IncompleteDetails: Codable {
        var reason: String?
    }

    var id: String?
    var model: String?
    var status: String?
    var incompleteDetails: IncompleteDetails?
    var output: [OutputItem]?
    var usage: OpenAIUsage?
    var error: OpenAIErrorBody?
}

private struct ImagePromptEnrichmentResponse: Codable {
    var schemaVersion: String
    var provider: String
    var model: String
    var enhancedPrompt: String
    var negativePrompt: String
    var changeSummary: String
}

struct OpenAIImageEditSource: Sendable {
    var data: Data
    var mimeType: String
    var fileName: String
    var label: String
    /// Attachment role for trace verification ("primary", "accent", "character_reference",
    /// "continuity"); empty for callers that do not plan attachments.
    var role: String
    /// Normalized blend share for style sources; 0 otherwise.
    var sharePercent: Int
    /// Human title (style card name, character name) — trace-only, never sent to the API.
    var title: String

    init(
        data: Data,
        mimeType: String,
        fileName: String,
        label: String = "",
        role: String = "",
        sharePercent: Int = 0,
        title: String = ""
    ) {
        self.data = data
        self.mimeType = mimeType.trimmed.isEmpty ? "image/png" : mimeType.trimmed
        self.fileName = fileName.trimmed.isEmpty ? "source.png" : fileName.trimmed
        self.label = label.trimmed
        self.role = role.trimmed
        self.sharePercent = max(0, sharePercent)
        self.title = title.trimmed
    }
}

private struct OpenAIMultipartFile {
    var fieldName: String
    var fileName: String
    var mimeType: String
    var data: Data
}

private func multipartFormData(
    fields: [(String, String)],
    files: [OpenAIMultipartFile],
    boundary: String
) -> Data {
    var body = Data()
    for (name, value) in fields {
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.appendUTF8("\(value)\r\n")
    }
    for file in files {
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\r\n")
        body.appendUTF8("Content-Type: \(file.mimeType)\r\n\r\n")
        body.append(file.data)
        body.appendUTF8("\r\n")
    }
    body.appendUTF8("--\(boundary)--\r\n")
    return body
}

private func openAIImageBackgroundValue(_ background: String, models: [String]) -> String? {
    let value = background.trimmed
    guard !value.isEmpty else { return nil }
    if value.lowercased() == "transparent",
       models.contains(where: openAIImageModelRejectsTransparentBackground) {
        return nil
    }
    return value
}

private func openAIImageModelRejectsTransparentBackground(_ model: String) -> Bool {
    let normalized = model.trimmed.lowercased()
    return normalized == "gpt-5.5" || normalized == "gpt-image-1.5" || normalized == "gpt-image-2"
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        append(Data(string.utf8))
    }
}

struct OpenAIClient: Sendable {
    var apiKey: String
    var endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!
    var imageEndpoint: URL = URL(string: "https://api.openai.com/v1/images/generations")!
    var imageEditEndpoint: URL = URL(string: "https://api.openai.com/v1/images/edits")!

    static func fromEnvironment() throws -> OpenAIClient {
        guard let key = OpenAIKeyStore.resolvedAPIKey(), !key.isEmpty else {
            throw ScreenGraphError.missingAPIKey
        }
        var client = OpenAIClient(apiKey: key)
        // OPENAI_BASE_URL points every environment-constructed call at an
        // OpenAI-compatible service (OpenRouter-style gateways, local servers).
        if let base = try OpenAITextEndpointSettings.baseURL() {
            client.endpoint = OpenAITextEndpointSettings.endpoint(base: base, path: "responses")
            client.imageEndpoint = OpenAITextEndpointSettings.endpoint(base: base, path: "images/generations")
            client.imageEditEndpoint = OpenAITextEndpointSettings.endpoint(base: base, path: "images/edits")
        }
        return client
    }

    func generateProofImage(
        prompt: String,
        model: String = "gpt-image-2",
        size: String = "1024x1024",
        quality: String = "medium",
        outputFormat: String = "jpeg",
        outputCompression: Int = 70,
        background: String = "",
        projectId: String = "",
        runId: String = "",
        traceOperation: String = "proof_image",
        traceWorkflowName: String = "video_chain",
        traceWorkflowStep: String = "proof_image",
        traceArtifactType: String = "proof_image",
        traceArtifactId: String? = nil
    ) async throws -> OpenAIImageGenerationResult {
        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": 1,
            "size": size,
            "quality": quality,
            "output_format": outputFormat
        ]
        // output_compression is only valid for lossy formats; sending it with png
        // (the transparent character-study path) is rejected by the API.
        if outputFormat == "jpeg" || outputFormat == "webp" {
            body["output_compression"] = min(max(outputCompression, 0), 100)
        }
        let requestBackground = openAIImageBackgroundValue(background, models: [model])
        if let requestBackground {
            body["background"] = requestBackground
        }
        let requestData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: imageEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = requestData

        let result = try await TracedHTTPTransport.send(
            request: request,
            metadata: InferenceTraceRequestMetadata(
                provider: "openai",
                apiFamily: "images",
                operation: traceOperation,
                projectId: projectId,
                runId: runId,
                model: model,
                requestBodyFormat: "application/json",
                responseBodyFormatHint: "application/json",
                providerRequestIDHeaderCandidates: ["x-request-id"],
                captureResponseBody: false
            )
        )
        let data = result.data
        let httpResponse = result.response
        let status = httpResponse?.statusCode ?? 0
        let requestId = httpResponse?.value(forHTTPHeaderField: "x-request-id") ?? ""
        guard (200..<300).contains(status) else {
            throw ScreenGraphError.openAI(
                formattedOpenAIProviderError(
                    operation: "OpenAI image request",
                    status: status,
                    data: data,
                    requestId: requestId
                )
            )
        }
        let decoded = try JSONCoding.decoder.decode(OpenAIImageGenerationResponse.self, from: data)
        guard let first = decoded.data.first,
              let encoded = first.b64Json,
              let imageData = Data(base64Encoded: encoded) else {
            throw ScreenGraphError.openAI("OpenAI image response did not include image data.")
        }
        await InferenceTraceStore.shared.enrich(
            traceId: result.traceId,
            providerRequestId: requestId,
            model: decoded.model ?? model
        )
        let outputSize = imagePixelSize(from: imageData)
        await InferenceTraceStore.shared.enrichContext(
            traceId: result.traceId,
            traceGroupId: runId.isEmpty ? projectId : runId,
            workflowName: traceWorkflowName,
            workflowStep: traceWorkflowStep,
            artifactType: traceArtifactType,
            artifactId: traceArtifactId ?? runId,
            requestTextJSON: inferenceTraceJSONString([
                "model": model,
                "prompt": prompt,
                "size": size,
                "quality": quality,
                "output_format": outputFormat,
                "output_compression": min(max(outputCompression, 0), 100),
                "background": requestBackground ?? ""
            ]),
            responseTextJSON: inferenceTraceJSONString([
                "model": decoded.model ?? model,
                "request_id": requestId,
                "revised_prompt": first.revisedPrompt ?? "",
                "output_format": outputFormat,
                "output_bytes": imageData.count,
                "output_sha256": sha256Hex(imageData),
                "output_width": outputSize?.width ?? 0,
                "output_height": outputSize?.height ?? 0
            ]),
            mediaRefsJSON: inferenceTraceJSONString([
                "output": [
                    "sha256": sha256Hex(imageData),
                    "bytes": imageData.count,
                    "width": outputSize?.width ?? 0,
                    "height": outputSize?.height ?? 0,
                    "format": outputFormat
                ]
            ])
        )
        return OpenAIImageGenerationResult(
            imageData: imageData,
            requestId: requestId,
            traceId: result.traceId,
            model: decoded.model ?? model,
            revisedPrompt: first.revisedPrompt ?? ""
        )
    }

    func generateImageEdit(
        prompt: String,
        sourceImageData: Data,
        sourceImageMimeType: String,
        sourceFilename: String,
        additionalSourceImages: [OpenAIImageEditSource] = [],
        model: String = "gpt-image-1.5",
        size: String = "1024x1024",
        quality: String = "medium",
        outputFormat: String = "png",
        projectId: String = "",
        runId: String = "",
        traceWorkflowName: String = "video_chain",
        traceWorkflowStep: String = "image_edit",
        traceArtifactType: String = "image_edit",
        traceArtifactId: String = ""
    ) async throws -> OpenAIImageGenerationResult {
        let primarySource = OpenAIImageEditSource(
            data: sourceImageData,
            mimeType: sourceImageMimeType,
            fileName: sourceFilename,
            label: "primary"
        )
        return try await generateImageEdit(
            prompt: prompt,
            sources: [primarySource] + additionalSourceImages,
            model: model,
            size: size,
            quality: quality,
            outputFormat: outputFormat,
            projectId: projectId,
            runId: runId,
            traceWorkflowName: traceWorkflowName,
            traceWorkflowStep: traceWorkflowStep,
            traceArtifactType: traceArtifactType,
            traceArtifactId: traceArtifactId
        )
    }

    /// Image edit with fully caller-described sources: each source keeps its own filename,
    /// role, share, and title so traces mirror the attachment plan exactly instead of a
    /// hardcoded "primary" label on the first file.
    func generateImageEdit(
        prompt: String,
        sources: [OpenAIImageEditSource],
        mask: OpenAIImageEditSource? = nil,
        model: String = "gpt-image-1.5",
        size: String = "1024x1024",
        quality: String = "medium",
        outputFormat: String = "png",
        background: String = "",
        projectId: String = "",
        runId: String = "",
        traceWorkflowName: String = "video_chain",
        traceWorkflowStep: String = "image_edit",
        traceArtifactType: String = "image_edit",
        traceArtifactId: String = ""
    ) async throws -> OpenAIImageGenerationResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        let sourceImages = sources.filter { !$0.data.isEmpty }
        var fields: [(String, String)] = [
            ("model", model),
            ("prompt", prompt),
            ("size", size),
            ("quality", quality),
            ("output_format", outputFormat)
        ]
        let requestBackground = openAIImageBackgroundValue(background, models: [model])
        if let requestBackground {
            fields.append(("background", requestBackground))
        }
        var files = sourceImages.map { source in
            OpenAIMultipartFile(
                fieldName: "image[]",
                fileName: source.fileName,
                mimeType: source.mimeType,
                data: source.data
            )
        }
        if let mask, !mask.data.isEmpty {
            files.append(OpenAIMultipartFile(
                fieldName: "mask",
                fileName: mask.fileName,
                mimeType: mask.mimeType,
                data: mask.data
            ))
        }
        let body = multipartFormData(
            fields: fields,
            files: files,
            boundary: boundary
        )
        var request = URLRequest(url: imageEditEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = body

        let result = try await TracedHTTPTransport.send(
            request: request,
            metadata: InferenceTraceRequestMetadata(
                provider: "openai",
                apiFamily: "images",
                operation: "image_edit",
                projectId: projectId,
                runId: runId,
                model: model,
                requestBodyFormat: "multipart/form-data",
                responseBodyFormatHint: "application/json",
                providerRequestIDHeaderCandidates: ["x-request-id"],
                captureRequestBody: false,
                captureResponseBody: false
            )
        )
        let data = result.data
        let status = result.response?.statusCode ?? 0
        let requestId = result.response?.value(forHTTPHeaderField: "x-request-id") ?? ""
        guard (200..<300).contains(status) else {
            throw ScreenGraphError.openAI(
                formattedOpenAIProviderError(
                    operation: "OpenAI image edit",
                    status: status,
                    data: data,
                    requestId: requestId
                )
            )
        }
        let decoded = try JSONCoding.decoder.decode(OpenAIImageGenerationResponse.self, from: data)
        guard let first = decoded.data.first,
              let encoded = first.b64Json,
              let imageData = Data(base64Encoded: encoded) else {
            throw ScreenGraphError.openAI("OpenAI image edit response did not include image data.")
        }
        await InferenceTraceStore.shared.enrich(
            traceId: result.traceId,
            providerRequestId: requestId,
            model: decoded.model ?? model
        )
        let sourceTraceValues = sourceImages.enumerated().map { index, source -> [String: Any] in
            let sourceSize = imagePixelSize(from: source.data)
            return [
                "index": index,
                "label": source.label.isEmpty ? "source_\(index + 1)" : source.label,
                "filename": source.fileName,
                "role": source.role,
                "share_percent": source.sharePercent,
                "title": source.title,
                "mime_type": source.mimeType,
                "sha256": sha256Hex(source.data),
                "bytes": source.data.count,
                "width": sourceSize?.width ?? 0,
                "height": sourceSize?.height ?? 0
            ]
        }
        let maskTraceValue: [String: Any]? = mask.flatMap { value in
            guard !value.data.isEmpty else { return nil }
            let size = imagePixelSize(from: value.data)
            return [
                "filename": value.fileName,
                "mime_type": value.mimeType,
                "sha256": sha256Hex(value.data),
                "bytes": value.data.count,
                "width": size?.width ?? 0,
                "height": size?.height ?? 0
            ]
        }
        let outputSize = imagePixelSize(from: imageData)
        await InferenceTraceStore.shared.enrichContext(
            traceId: result.traceId,
            traceGroupId: runId.isEmpty ? projectId : runId,
            workflowName: traceWorkflowName.trimmed.isEmpty ? "video_chain" : traceWorkflowName.trimmed,
            workflowStep: traceWorkflowStep.trimmed.isEmpty ? "image_edit" : traceWorkflowStep.trimmed,
            artifactType: traceArtifactType.trimmed.isEmpty ? "image_edit" : traceArtifactType.trimmed,
            artifactId: traceArtifactId.trimmed.isEmpty ? runId : traceArtifactId.trimmed,
            requestTextJSON: inferenceTraceJSONString([
                "model": model,
                "prompt": prompt,
                "size": size,
                "quality": quality,
                "output_format": outputFormat,
                "background": requestBackground ?? "",
                "source_count": sourceImages.count,
                "sources": sourceTraceValues,
                "mask": maskTraceValue ?? [:]
            ]),
            responseTextJSON: inferenceTraceJSONString([
                "model": decoded.model ?? model,
                "request_id": requestId,
                "revised_prompt": first.revisedPrompt ?? "",
                "output_format": outputFormat,
                "output_bytes": imageData.count,
                "output_sha256": sha256Hex(imageData),
                "output_width": outputSize?.width ?? 0,
                "output_height": outputSize?.height ?? 0
            ]),
            mediaRefsJSON: inferenceTraceJSONString([
                "sources": sourceTraceValues,
                "mask": maskTraceValue ?? [:],
                "output": [
                    "sha256": sha256Hex(imageData),
                    "bytes": imageData.count,
                    "width": outputSize?.width ?? 0,
                    "height": outputSize?.height ?? 0,
                    "format": outputFormat
                ]
            ])
        )
        return OpenAIImageGenerationResult(
            imageData: imageData,
            requestId: requestId,
            traceId: result.traceId,
            model: decoded.model ?? model,
            revisedPrompt: first.revisedPrompt ?? ""
        )
    }

    /// Renders an image through /v1/responses with the image_generation tool. Reference
    /// images travel as input_image CONTEXT parts (each preceded by a one-line anchor
    /// naming its attachment position and filename so the prompt's manifest keeps its
    /// anchors), not as edit bases — the mainline model reads them and drives the image
    /// tool, which lifts the fidelity ceiling the edits endpoint imposes on
    /// reference-backed renders. Returns the same OpenAIImageGenerationResult as the
    /// Image API paths so callers persist identically.
    func generateImageViaResponses(
        prompt: String,
        instructions: String = "",
        sources: [OpenAIImageEditSource],
        model: String = SessionConfig().model,
        imageModel: String = "gpt-image-2",
        size: String = "1024x1024",
        quality: String = "medium",
        outputFormat: String = "jpeg",
        outputCompression: Int = 70,
        background: String = "",
        projectId: String = "",
        runId: String = "",
        traceWorkflowName: String = "video_chain",
        traceWorkflowStep: String = "image_responses",
        traceArtifactType: String = "image_responses",
        traceArtifactId: String = ""
    ) async throws -> OpenAIImageGenerationResult {
        let sourceImages = sources.filter { !$0.data.isEmpty }
        var tool: [String: Any] = [
            "type": "image_generation",
            "model": imageModel,
            "size": size,
            "quality": quality,
            "output_format": outputFormat
        ]
        if outputFormat == "jpeg" || outputFormat == "webp" {
            tool["output_compression"] = min(max(outputCompression, 0), 100)
        }
        let requestBackground = openAIImageBackgroundValue(background, models: [model, imageModel])
        if let requestBackground {
            tool["background"] = requestBackground
        }
        // input_fidelity is a gpt-image-1-family knob; gpt-image-2 rejects it with
        // "invalid input_fidelity parameter" and preserves reference fidelity natively.
        if !sourceImages.isEmpty, imageModel.hasPrefix("gpt-image-1") {
            tool["input_fidelity"] = "high"
        }
        var content: [[String: Any]] = [["type": "input_text", "text": prompt]]
        for source in sourceImages {
            // Anchor each image to the prompt's attachment vocabulary by FILENAME only —
            // the manifest numbers entries by full-plan position, and a skipped unreadable
            // local file would desync any ordinal written here. Style entries stay
            // title-free: any style words in text would override the style image.
            let roleNote: String
            switch source.role {
            case "primary", "accent": roleNote = "style reference"
            case "character_reference": roleNote = source.title.isEmpty ? "character reference" : "character reference: \(source.title)"
            case "continuity": roleNote = "world continuity"
            case "subject_anchor": roleNote = "subject anchor"
            default: roleNote = source.role
            }
            content.append([
                "type": "input_text",
                "text": "Attached image: \(source.fileName) (\(roleNote))"
            ])
            content.append([
                "type": "input_image",
                "image_url": "data:\(source.mimeType);base64,\(source.data.base64EncodedString())",
                "detail": "high"
            ])
        }
        var body: [String: Any] = [
            "model": model,
            "store": true,
            "reasoning": ["effort": "low"],
            "tools": [tool],
            "tool_choice": ["type": "image_generation"],
            "input": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ]
        // Static, job-independent directives (single-style rule, style-only policy)
        // ride as system-level instructions so the user prompt stays pure content.
        if !instructions.trimmed.isEmpty {
            body["instructions"] = instructions
        }
        let requestData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = requestData

        let result = try await TracedHTTPTransport.send(
            request: request,
            metadata: InferenceTraceRequestMetadata(
                provider: "openai",
                apiFamily: "responses",
                operation: "image_generation",
                projectId: projectId,
                runId: runId,
                model: model,
                requestBodyFormat: "application/json",
                responseBodyFormatHint: "application/json",
                providerRequestIDHeaderCandidates: ["x-request-id"],
                // Inline base64 data URLs and base64 output: never write bodies to traces.
                captureRequestBody: false,
                captureResponseBody: false
            )
        )
        let data = result.data
        let status = result.response?.statusCode ?? 0
        let requestId = result.response?.value(forHTTPHeaderField: "x-request-id") ?? ""
        guard (200..<300).contains(status) else {
            throw ScreenGraphError.openAI(
                formattedOpenAIProviderError(
                    operation: "OpenAI Responses image generation",
                    status: status,
                    data: data,
                    requestId: requestId
                )
            )
        }
        let decoded = try JSONCoding.decoder.decode(OpenAIResponsesImageBody.self, from: data)
        if let error = decoded.error {
            throw ScreenGraphError.openAI(error.message)
        }
        let outputItems = decoded.output ?? []
        // Resolved but NOT unwrapped: a failure has to reach the trace with
        // the same prompt and provenance a success gets, so both enrichment
        // calls below run before anything throws. Enriching only on success
        // is what left every failed image call in the Traces app with no
        // prompt, no response, no workflow, and no usage.
        let imageCall = outputItems.first { $0.type == "image_generation_call" && !($0.result ?? "").isEmpty }
        let imageData = imageCall?.result.flatMap { Data(base64Encoded: $0) }
        let failure = imageData == nil ? OpenAIImageFailureClassifier.failure(from: decoded) : nil
        await InferenceTraceStore.shared.enrich(
            traceId: result.traceId,
            providerRequestId: requestId,
            providerResponseId: decoded.id ?? "",
            model: decoded.model ?? model,
            usage: decoded.usage.map {
                InferenceTraceUsage(
                    inputTokens: $0.inputTokens,
                    outputTokens: $0.outputTokens,
                    totalTokens: $0.totalTokens
                )
            }
        )
        let sourceTraceValues = sourceImages.enumerated().map { index, source -> [String: Any] in
            let sourceSize = imagePixelSize(from: source.data)
            return [
                "index": index,
                "label": source.label.isEmpty ? "source_\(index + 1)" : source.label,
                "filename": source.fileName,
                "role": source.role,
                "share_percent": source.sharePercent,
                "title": source.title,
                "mime_type": source.mimeType,
                "sha256": sha256Hex(source.data),
                "bytes": source.data.count,
                "width": sourceSize?.width ?? 0,
                "height": sourceSize?.height ?? 0
            ]
        }
        let outputSize = imageData.flatMap { imagePixelSize(from: $0) }
        // The response half describes either the picture we got or the reason
        // we got none. Image bytes never ride here — sources are recorded as
        // hashes and sizes — which is why this channel is safe to write on
        // the failure path even though the raw bodies are never captured.
        let responseTextValues: [String: Any]
        if let imageData {
            responseTextValues = [
                "model": decoded.model ?? model,
                "response_id": decoded.id ?? "",
                "request_id": requestId,
                "revised_prompt": imageCall?.revisedPrompt ?? "",
                "output_format": outputFormat,
                "output_bytes": imageData.count,
                "output_sha256": sha256Hex(imageData),
                "output_width": outputSize?.width ?? 0,
                "output_height": outputSize?.height ?? 0
            ]
        } else {
            responseTextValues = [
                "model": decoded.model ?? model,
                "response_id": decoded.id ?? "",
                "request_id": requestId,
                "status": decoded.status ?? "",
                "incomplete_reason": decoded.incompleteDetails?.reason ?? "",
                "output_item_types": outputItems.map(\.type),
                "failure_kind": failure.map(failureKindLabel) ?? "",
                "failure_message": failure?.message ?? "",
                "failure_is_terminal": failure?.isTerminal ?? false
            ]
        }
        var mediaRefsValues: [String: Any] = ["sources": sourceTraceValues]
        if let imageData {
            mediaRefsValues["output"] = [
                "sha256": sha256Hex(imageData),
                "bytes": imageData.count,
                "width": outputSize?.width ?? 0,
                "height": outputSize?.height ?? 0,
                "format": outputFormat
            ]
        }
        await InferenceTraceStore.shared.enrichContext(
            traceId: result.traceId,
            traceGroupId: runId.isEmpty ? projectId : runId,
            workflowName: traceWorkflowName.trimmed.isEmpty ? "video_chain" : traceWorkflowName.trimmed,
            workflowStep: traceWorkflowStep.trimmed.isEmpty ? "image_responses" : traceWorkflowStep.trimmed,
            artifactType: traceArtifactType.trimmed.isEmpty ? "image_responses" : traceArtifactType.trimmed,
            artifactId: traceArtifactId.trimmed.isEmpty ? runId : traceArtifactId.trimmed,
            requestTextJSON: inferenceTraceJSONString([
                "model": model,
                "image_model": imageModel,
                "prompt": prompt,
                "instructions": instructions,
                "size": size,
                "quality": quality,
                "output_format": outputFormat,
                "background": requestBackground ?? "",
                "source_count": sourceImages.count,
                "sources": sourceTraceValues
            ]),
            responseTextJSON: inferenceTraceJSONString(responseTextValues),
            mediaRefsJSON: inferenceTraceJSONString(mediaRefsValues)
        )
        guard let imageData else {
            throw ScreenGraphError.openAI(
                (failure ?? .resultless(summary: "the response carried no output items")).message
            )
        }
        return OpenAIImageGenerationResult(
            imageData: imageData,
            requestId: requestId,
            traceId: result.traceId,
            model: decoded.model ?? model,
            revisedPrompt: imageCall?.revisedPrompt ?? ""
        )
    }

    /// Stable trace vocabulary for the failure shape, so no-image outcomes
    /// can be counted and compared across runs.
    private func failureKindLabel(_ failure: OpenAIImageFailure) -> String {
        switch failure {
        case .refused: return "refused"
        case .incomplete: return "incomplete"
        case .resultless: return "resultless"
        }
    }

    func enhanceImagePrompt(
        originalPrompt: String,
        provider: String,
        imageModel: String,
        providerInstructions: String,
        referenceMode: ImagePromptReferenceMode = .textOnly,
        model: String = SessionConfig().model,
        projectId: String = "",
        runId: String = "",
        traceGroupId: String = "",
        traceWorkflowName: String = "",
        traceWorkflowStep: String = "",
        traceArtifactType: String = "",
        traceArtifactId: String = ""
    ) async throws -> OpenAIImagePromptEnrichmentResult {
        let schema = try loadImagePromptEnrichmentSchema()
        let prompt: String
        switch referenceMode {
        case .styleReference:
            prompt = imagePromptStyleScrubPrompt(
                originalPrompt: originalPrompt,
                provider: provider,
                imageModel: imageModel
            )
        case .subjectReference(let count):
            prompt = imagePromptSubjectReferencePrompt(
                originalPrompt: originalPrompt,
                provider: provider,
                imageModel: imageModel,
                providerInstructions: providerInstructions,
                referenceCount: count
            )
        case .textOnly:
            prompt = imagePromptEnrichmentPrompt(
                originalPrompt: originalPrompt,
                provider: provider,
                imageModel: imageModel,
                providerInstructions: providerInstructions
            )
        }
        let body: [String: Any] = [
            "model": model,
            "store": true,
            "reasoning": ["effort": "low"],
            "text": [
                "verbosity": "medium",
                "format": [
                    "type": "json_schema",
                    "name": "image_prompt_enrichment",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt]
                    ]
                ]
            ]
        ]
        let result = try await responsesRequest(
            operationName: "image_prompt_enrichment",
            body: body,
            model: model,
            timeoutInterval: 90,
            projectId: projectId,
            runId: runId,
            traceGroupId: traceGroupId,
            traceWorkflowName: traceWorkflowName,
            traceWorkflowStep: traceWorkflowStep,
            traceArtifactType: traceArtifactType,
            traceArtifactId: traceArtifactId
        )
        let text = result.rawText
        let response: ImagePromptEnrichmentResponse
        do {
            response = try JSONCoding.decoder.decode(ImagePromptEnrichmentResponse.self, from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Image prompt enrichment response could not be read: \(error.localizedDescription)")
        }
        let enhancedPrompt = response.enhancedPrompt.trimmed
        guard !enhancedPrompt.isEmpty else {
            throw ScreenGraphError.openAI("Image prompt enrichment returned an empty prompt.")
        }
        return OpenAIImagePromptEnrichmentResult(
            enhancedPrompt: enhancedPrompt,
            negativePrompt: response.negativePrompt.trimmed,
            changeSummary: response.changeSummary.trimmed,
            responseId: result.decoded.id,
            model: result.decoded.model ?? model,
            usage: result.decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text,
            traceId: result.traceId
        )
    }

    func analyze(
        imageData: Data,
        capture: CaptureRecord,
        config: SessionConfig,
        rollingContext: String
    ) async throws -> OpenAIAnalysisResult {
        let schema = try loadDraftSchema()
        let prompt = hydrationPrompt(capture: capture, rollingContext: rollingContext)
        let body: [String: Any] = [
            "model": config.model,
            "store": true,
            "reasoning": ["effort": "low"],
            "text": [
                "verbosity": "low",
                "format": [
                    "type": "json_schema",
                    "name": "screen_graph_hydration_draft",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt],
                        [
                            "type": "input_image",
                            "image_url": "data:image/png;base64,\(imageData.base64EncodedString())",
                            "detail": config.detail.rawValue
                        ]
                    ]
                ]
            ]
        ]

        let result = try await responsesRequest(
            operationName: "screen_graph_hydration_draft",
            body: body,
            model: config.model,
            timeoutInterval: 180,
            runId: capture.sessionId
        )
        let text = result.rawText
        let draft = try JSONCoding.decoder.decode(ScreenGraphHydrationDraft.self, from: Data(text.utf8))
        return OpenAIAnalysisResult(
            draft: draft,
            responseId: result.decoded.id,
            model: result.decoded.model ?? config.model,
            usage: result.decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func analyzeMedia(
        imageData: Data,
        imageMimeType: String,
        context: MediaObservationGenerationContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIMediaObservationResult {
        let schema = try loadImageObservationSchema()
        let prompt = mediaObservationPrompt(context: context)
        let body: [String: Any] = [
            "model": model,
            "store": true,
            "reasoning": ["effort": "low"],
            "text": [
                "verbosity": "medium",
                "format": [
                    "type": "json_schema",
                    "name": "image_observation",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt],
                        [
                            "type": "input_image",
                            "image_url": "data:\(imageMimeType);base64,\(imageData.base64EncodedString())",
                            "detail": "high"
                        ]
                    ]
                ]
            ]
        ]

        let result = try await responsesRequest(
            operationName: "image_observation",
            body: body,
            model: model,
            timeoutInterval: 180,
            projectId: context.projectId,
            runId: context.mediaId
        )
        let text = result.rawText
        let observation: ImageObservationResult
        do {
            observation = try ImageObservationResult.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Media observation response could not be read: \(error.localizedDescription)")
        }
        return OpenAIMediaObservationResult(
            observation: observation,
            responseId: result.decoded.id,
            model: result.decoded.model ?? model,
            usage: result.decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func generateProjectAestheticEvidenceProfile(
        context: ProjectAestheticEvidenceGenerationContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIAestheticEvidenceProfileResult {
        let schema = try loadProjectAestheticEvidenceSchema()
        let prompt = projectAestheticEvidencePrompt(context: context)
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "project_aesthetic_evidence",
            prompt: prompt,
            model: model,
            verbosity: "medium",
            timeoutInterval: 180,
            projectId: context.projectId
        )
        let response: ProjectAestheticEvidenceProfileResponse
        do {
            response = try JSONCoding.decoder.decode(ProjectAestheticEvidenceProfileResponse.self, from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Project Aesthetic evidence response could not be read: \(error.localizedDescription)")
        }
        return OpenAIAestheticEvidenceProfileResult(
            profile: response,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func generateLensComposition(
        context: LensTrioContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAILensCompositionResult {
        let schema = try loadLensCompositionSchema()
        let prompt = Self.lensCompositionPrompt(context: context)
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "lens_composition",
            prompt: prompt,
            model: model,
            verbosity: "medium",
            timeoutInterval: 240,
            projectId: context.projectId
        )
        let response: LensCompositionResponse
        do {
            response = try JSONCoding.decoder.decode(LensCompositionResponse.self, from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Lens composition response could not be read: \(error.localizedDescription)")
        }
        return OpenAILensCompositionResult(
            composition: response,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0)
        )
    }

    func authorGoalStyleTaxonomyRefs(
        context: GoalStyleTaxonomyRefsContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIGoalStyleTaxonomyRefsResult {
        let schema = try loadGoalStyleTaxonomyRefsSchema()
        let prompt = goalStyleTaxonomyRefsPrompt(context: context)
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "goal_style_taxonomy_refs",
            prompt: prompt,
            model: model,
            verbosity: "low",
            timeoutInterval: 120,
            projectId: context.projectId
        )
        let response: GoalStyleTaxonomyRefsResponse
        do {
            response = try JSONCoding.decoder.decode(GoalStyleTaxonomyRefsResponse.self, from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Goal style taxonomy refs response could not be read: \(error.localizedDescription)")
        }
        return OpenAIGoalStyleTaxonomyRefsResult(
            refs: uniqueStyleTermRefs(response.styleTermRefs, limit: 24),
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0)
        )
    }

    func articulateGoalCast(
        context: GoalCastArticulationContext,
        visionInputs: [OpenAIVisionImageInput] = [],
        model: String = SessionConfig().model
    ) async throws -> OpenAIGoalCastResult {
        let schema = try loadGoalCastArticulationSchema()
        let prompt = Self.goalCastArticulationPrompt(context: context)
        var content: [[String: Any]] = [
            ["type": "input_text", "text": prompt]
        ]
        for input in visionInputs.prefix(4) {
            content.append([
                "type": "input_image",
                "image_url": "data:\(input.mimeType);base64,\(input.data.base64EncodedString())",
                "detail": input.detail
            ])
        }
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "goal_cast_articulation",
            content: content,
            model: model,
            verbosity: "low",
            timeoutInterval: 180,
            projectId: context.projectId
        )
        let response: GoalCastArticulationResponse
        do {
            response = try JSONCoding.decoder.decode(GoalCastArticulationResponse.self, from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Goal cast articulation response could not be read: \(error.localizedDescription)")
        }
        return OpenAIGoalCastResult(
            members: response.members,
            castingNote: response.castingNote.trimmed,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0)
        )
    }

    func steerGoalCastMember(
        context: GoalCastSteerContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIGoalCastResult {
        let schema = try loadGoalCastArticulationSchema()
        let prompt = goalCastSteerPrompt(context: context)
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "goal_cast_articulation",
            prompt: prompt,
            model: model,
            verbosity: "low",
            timeoutInterval: 120,
            projectId: context.projectId
        )
        let response: GoalCastArticulationResponse
        do {
            response = try JSONCoding.decoder.decode(GoalCastArticulationResponse.self, from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Goal cast steer response could not be read: \(error.localizedDescription)")
        }
        guard response.members.count == 1 else {
            throw ScreenGraphError.openAI("Goal cast steer returned \(response.members.count) members; expected exactly 1.")
        }
        return OpenAIGoalCastResult(
            members: response.members,
            castingNote: response.castingNote.trimmed,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0)
        )
    }

    func shortlistAestheticDirections(
        context: AestheticDirectionShortlistContext,
        validationError: String = "",
        model: String = SessionConfig().model
    ) async throws -> OpenAIAestheticDirectionShortlistResult {
        let schema = try loadAestheticDirectionShortlistSchema()
        let prompt = aestheticDirectionShortlistPrompt(context: context, validationError: validationError)
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "aesthetic_direction_shortlist",
            prompt: prompt,
            model: model,
            verbosity: "medium",
            timeoutInterval: 180,
            projectId: context.projectId
        )
        let response: AestheticDirectionShortlistResponse
        do {
            response = try JSONCoding.decoder.decode(AestheticDirectionShortlistResponse.self, from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Aesthetic shortlist response could not be read: \(error.localizedDescription)")
        }
        return OpenAIAestheticDirectionShortlistResult(
            shortlist: response,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func rankAestheticDirections(
        context: AestheticDirectionRankContext,
        validationError: String = "",
        model: String = SessionConfig().model
    ) async throws -> OpenAIAestheticDirectionRankResult {
        let schema = try loadAestheticDirectionRankSchema()
        let prompt = aestheticDirectionRankPrompt(context: context, validationError: validationError)
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "aesthetic_direction_rank",
            prompt: prompt,
            model: model,
            verbosity: "medium",
            timeoutInterval: 180,
            projectId: context.projectId
        )
        let response: AestheticDirectionRankResponse
        do {
            response = try JSONCoding.decoder.decode(AestheticDirectionRankResponse.self, from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Aesthetic rank response could not be read: \(error.localizedDescription)")
        }
        return OpenAIAestheticDirectionRankResult(
            ranking: response,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func interviewProjectGoal(
        context: ProjectGoalInterviewContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIProjectGoalInterviewResult {
        let schema = try loadProjectGoalInterviewSchema()
        let prompt = projectGoalInterviewPrompt(context: context)
        let body: [String: Any] = [
            "model": model,
            "store": true,
            "reasoning": ["effort": "low"],
            "text": [
                "verbosity": "medium",
                "format": [
                    "type": "json_schema",
                    "name": "project_goal_interview",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt]
                    ]
                ]
            ]
        ]

        let result = try await responsesRequest(
            operationName: "project_goal_interview",
            body: body,
            model: model,
            timeoutInterval: 180,
            projectId: context.projectId
        )
        let text = result.rawText
        let interviewResponse: ProjectGoalInterviewResponse
        do {
            interviewResponse = try ProjectGoalInterviewResponse.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Project Goal response could not be read: \(error.localizedDescription)")
        }
        return OpenAIProjectGoalInterviewResult(
            assistantMessage: interviewResponse.assistantMessage,
            brief: interviewResponse.brief,
            changeSummary: interviewResponse.changeSummary,
            responseId: result.decoded.id,
            model: result.decoded.model ?? model,
            usage: result.decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func interviewProjectGoalV3(
        context: ProjectGoalInterviewV3Context,
        visionInputs: [OpenAIVisionImageInput] = [],
        model: String = SessionConfig().model
    ) async throws -> OpenAIProjectGoalInterviewV3Result {
        let schema = try loadProjectGoalInterviewV3Schema()
        let prompt = projectGoalInterviewV3Prompt(context: context)
        var content: [[String: Any]] = [
            ["type": "input_text", "text": prompt]
        ]
        for input in visionInputs.prefix(8) {
            content.append([
                "type": "input_image",
                "image_url": "data:\(input.mimeType);base64,\(input.data.base64EncodedString())",
                "detail": input.detail
            ])
        }
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "project_goal_interview_v3",
            content: content,
            model: model,
            verbosity: "medium",
            timeoutInterval: 300,
            projectId: context.projectId
        )
        let interviewResponse: ProjectGoalInterviewResponseV3
        do {
            interviewResponse = try ProjectGoalInterviewResponseV3.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Project Goal V3 response could not be read: \(error.localizedDescription)")
        }
        return OpenAIProjectGoalInterviewV3Result(
            assistantMessage: interviewResponse.assistantMessage,
            brief: interviewResponse.brief.normalized(),
            changeSummary: interviewResponse.changeSummary,
            castUpdates: interviewResponse.castUpdates,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    /// One turn of a character's sheet conversation: the model sees the identity, the
    /// exact prompt the next render transmits, the current sheet and source images,
    /// and the recent turns, and returns the revised identity plus the complete list
    /// of sheet directives in force. Text-only: no ledger row.
    func refineCharacterSheet(
        context: CharacterSheetRefineContext,
        visionInputs: [OpenAIVisionImageInput] = [],
        model: String = SessionConfig().model
    ) async throws -> OpenAICharacterSheetRefineResult {
        let schema = try loadCharacterSheetRefineSchema()
        let prompt = Self.characterSheetRefinePrompt(context: context)
        var content: [[String: Any]] = [
            ["type": "input_text", "text": prompt]
        ]
        for input in visionInputs.prefix(8) {
            content.append([
                "type": "input_image",
                "image_url": "data:\(input.mimeType);base64,\(input.data.base64EncodedString())",
                "detail": input.detail
            ])
        }
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "character_sheet_refine",
            content: content,
            model: model,
            verbosity: "low",
            timeoutInterval: 180,
            projectId: context.projectId
        )
        let response: CharacterSheetRefineResponse
        do {
            response = try CharacterSheetRefineResponse.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Character sheet refinement response could not be read: \(error.localizedDescription)")
        }
        return OpenAICharacterSheetRefineResult(
            response: response,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0)
        )
    }

    func deriveStorySignalSet(
        context: StorySignalSetGenerationContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIStorySignalSetResult {
        let schema = try loadStorySignalSetSchema()
        let prompt = storySignalSetPrompt(context: context)
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "story_signal_set",
            prompt: prompt,
            model: model,
            verbosity: "medium",
            timeoutInterval: 180,
            projectId: context.projectId,
            runId: context.signalSetId
        )
        let signalSet: StorySignalSet
        do {
            signalSet = try StorySignalSet.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Story Signal Set response could not be read: \(error.localizedDescription)")
        }
        return OpenAIStorySignalSetResult(
            signalSet: signalSet,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func generateStoryDirections(
        context: StoryDirectionSetGenerationContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIStoryDirectionSetResult {
        let schema = try loadStoryDirectionSetSchema()
        let prompt = storyDirectionSetPrompt(context: context)
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "story_direction_set",
            prompt: prompt,
            model: model,
            verbosity: "medium",
            timeoutInterval: 240,
            projectId: context.projectId,
            runId: context.directionSetId
        )
        let directionSet: StoryDirectionSet
        do {
            directionSet = try StoryDirectionSet.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Story Direction Set response could not be read: \(error.localizedDescription)")
        }
        return OpenAIStoryDirectionSetResult(
            directionSet: directionSet,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func interviewStorylineCreation(
        context: StorylineCreationInterviewContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIStorylineCreationInterviewResult {
        let schema = try loadStorylineCreationInterviewSchema()
        let prompt = storylineCreationInterviewPrompt(context: context)
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "storyline_creation_interview",
            prompt: prompt,
            model: model,
            verbosity: "medium",
            timeoutInterval: 180,
            projectId: context.projectId
        )
        let response: StorylineCreationInterviewResponse
        do {
            response = try StorylineCreationInterviewResponse.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Storyline creation response could not be read: \(error.localizedDescription)")
        }
        return OpenAIStorylineCreationInterviewResult(
            assistantMessage: response.assistantMessage,
            draft: response.draft.normalized(),
            changeSummary: response.changeSummary,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func interviewProjectLensWorkbench(
        context: ProjectLensWorkbenchInterviewContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIProjectLensWorkbenchInterviewResult {
        let schema = try loadProjectLensWorkbenchInterviewSchema()
        let prompt = projectLensWorkbenchInterviewPrompt(context: context)
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "project_lens_workbench_interview",
            prompt: prompt,
            model: model,
            verbosity: "medium",
            timeoutInterval: 180,
            projectId: context.projectId
        )
        let response: ProjectLensWorkbenchInterviewResponseV1
        do {
            response = try ProjectLensWorkbenchInterviewResponseV1.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Project Lens Workbench response could not be read: \(error.localizedDescription)")
        }
        return OpenAIProjectLensWorkbenchInterviewResult(
            assistantMessage: response.assistantMessage,
            body: response.body,
            changeSummary: response.changeSummary,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func generateSingleStoryline(
        context: StorySingleStorylineGenerationContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIStorySingleStorylineResult {
        let schema = try loadStorySingleStorylineSchema()
        let prompt = storySingleStorylinePrompt(context: context)
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "story_single_storyline",
            prompt: prompt,
            model: model,
            verbosity: "medium",
            timeoutInterval: 240,
            projectId: context.projectId,
            runId: context.expectedDirectionId
        )
        let response: StorySingleStorylineResponse
        do {
            response = try StorySingleStorylineResponse.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Storyline response could not be read: \(error.localizedDescription)")
        }
        return OpenAIStorySingleStorylineResult(
            direction: response.direction,
            changeSummary: response.changeSummary,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func generateStoryBeatBoard(
        context: StoryBeatBoardGenerationContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIStoryBeatBoardResult {
        let schema = try loadStoryBeatBoardSchema()
        let prompt = storyBeatBoardPrompt(context: context)
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "story_beat_board",
            prompt: prompt,
            model: model,
            verbosity: "medium",
            timeoutInterval: 240,
            projectId: context.projectId,
            runId: context.beatBoardId
        )
        let beatBoard: StoryBeatBoard
        do {
            beatBoard = try StoryBeatBoard.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Story Beat Board response could not be read: \(error.localizedDescription)")
        }
        return OpenAIStoryBeatBoardResult(
            beatBoard: beatBoard,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func editStoryBeatBoard(
        context: StoryBeatBoardEditContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIStoryBeatBoardResult {
        let schema = try loadStoryBeatBoardSchema()
        let prompt = storyBeatBoardEditPrompt(context: context)
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "story_beat_board",
            prompt: prompt,
            model: model,
            verbosity: "medium",
            timeoutInterval: 240,
            projectId: context.projectId,
            runId: context.outputBeatBoardId
        )
        let beatBoard: StoryBeatBoard
        do {
            beatBoard = try StoryBeatBoard.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Story Beat Board edit response could not be read: \(error.localizedDescription)")
        }
        return OpenAIStoryBeatBoardResult(
            beatBoard: beatBoard,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func draftStoryBeats(
        context: StoryBeatGenerationContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIStoryBeatSheetResult {
        let schema = try loadStoryBeatSheetSchema()
        let prompt = storyBeatSheetPrompt(context: context)
        let body: [String: Any] = [
            "model": model,
            "store": true,
            "reasoning": ["effort": "low"],
            "text": [
                "verbosity": "medium",
                "format": [
                    "type": "json_schema",
                    "name": "story_beat_sheet",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt]
                    ]
                ]
            ]
        ]

        let result = try await responsesRequest(
            operationName: "story_beat_sheet",
            body: body,
            model: model,
            timeoutInterval: 240,
            projectId: context.projectId
        )
        let text = result.rawText
        let beatSheet: StoryBeatSheet
        do {
            beatSheet = try StoryBeatSheet.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Story Beat Sheet response could not be read: \(error.localizedDescription)")
        }
        return OpenAIStoryBeatSheetResult(
            beatSheet: beatSheet,
            responseId: result.decoded.id,
            model: result.decoded.model ?? model,
            usage: result.decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func draftStoryAudioTrack(
        context: StoryAudioTrackGenerationContext,
        model: String = SessionConfig().model
    ) async throws -> OpenAIStoryAudioTrackDraftResult {
        let schema = try loadStoryAudioTrackDraftSchema()
        let prompt = storyAudioTrackPrompt(context: context)
        let body: [String: Any] = [
            "model": model,
            "store": true,
            "reasoning": ["effort": "low"],
            "text": [
                "verbosity": "low",
                "format": [
                    "type": "json_schema",
                    "name": "story_audio_track_draft",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt]
                    ]
                ]
            ]
        ]

        let result = try await responsesRequest(
            operationName: "story_audio_track_draft",
            body: body,
            model: model,
            timeoutInterval: 240,
            projectId: context.projectId,
            runId: context.trackId
        )
        let text = result.rawText
        let draft: StoryAudioTrackDraft
        do {
            draft = try StoryAudioTrackDraft.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Story Audio Track response could not be read: \(error.localizedDescription)")
        }
        return OpenAIStoryAudioTrackDraftResult(
            draft: draft,
            responseId: result.decoded.id,
            model: result.decoded.model ?? model,
            usage: result.decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            rawText: text
        )
    }

    func draftLensNarration(
        prompt: String,
        model: String = SessionConfig().model,
        projectId: String = "",
        runId: String = ""
    ) async throws -> OpenAILensNarrationResult {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["narration_text"],
            "properties": [
                "narration_text": [
                    "type": "string",
                    "description": "The spoken narration script, plain prose with no quotes or markup."
                ]
            ]
        ]
        let body: [String: Any] = [
            "model": model,
            "store": true,
            "reasoning": ["effort": "low"],
            "text": [
                "verbosity": "low",
                "format": [
                    "type": "json_schema",
                    "name": "lens_narration_draft",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt]
                    ]
                ]
            ]
        ]
        let result = try await responsesRequest(
            operationName: "lens_narration_draft",
            body: body,
            model: model,
            timeoutInterval: 120,
            projectId: projectId,
            runId: runId
        )
        let text = result.rawText
        let response: LensNarrationDraftResponse
        do {
            response = try JSONCoding.decoder.decode(LensNarrationDraftResponse.self, from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI(
                "Lens narration response could not be read: \(error.localizedDescription). Output preview: \(responsePreview(text))"
            )
        }
        let script = response.narrationText.trimmed
        guard !script.isEmpty else {
            throw ScreenGraphError.openAI("Lens narration returned an empty script.")
        }
        return OpenAILensNarrationResult(
            script: script,
            responseId: result.decoded.id,
            model: result.decoded.model ?? model,
            traceId: result.traceId
        )
    }

    func draftShotNarrationChips(
        prompt: String,
        model: String = SessionConfig().model,
        projectId: String = "",
        runId: String = ""
    ) async throws -> OpenAIShotNarrationChipsResult {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["statements"],
            "properties": [
                "statements": [
                    "type": "array",
                    "items": [
                        "type": "string",
                        "description": "One candidate meaning message: a single plain sentence, no quotes or numbering."
                    ]
                ]
            ]
        ]
        let body: [String: Any] = [
            "model": model,
            "store": true,
            "reasoning": ["effort": "low"],
            "text": [
                "verbosity": "low",
                "format": [
                    "type": "json_schema",
                    "name": "shot_narration_chips",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt]
                    ]
                ]
            ]
        ]
        let result = try await responsesRequest(
            operationName: "shot_narration_chips_draft",
            body: body,
            model: model,
            timeoutInterval: 120,
            projectId: projectId,
            runId: runId
        )
        let text = result.rawText
        let response: ShotNarrationChipsResponse
        do {
            response = try JSONCoding.decoder.decode(ShotNarrationChipsResponse.self, from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI(
                "Shot narration chips response could not be read: \(error.localizedDescription). Output preview: \(responsePreview(text))"
            )
        }
        let statements = Array(
            response.statements
                .map { $0.trimmed }
                .filter { !$0.isEmpty }
                .prefix(5)
        )
        guard !statements.isEmpty else {
            throw ScreenGraphError.openAI("Shot narration chips returned no usable statements.")
        }
        return OpenAIShotNarrationChipsResult(
            statements: statements,
            responseId: result.decoded.id,
            model: result.decoded.model ?? model,
            traceId: result.traceId
        )
    }

    /// Drafts one segment's temporal direction plan: 2–4 weighted motion
    /// beats between two keyframes. Strict schema; client-side clamps (beat
    /// cap, weight range, blank-beat drop) exactly like the chips draft —
    /// strict structured outputs cannot be trusted with min/max items.
    func draftShotSegmentDirectionPlan(
        prompt: String,
        model: String = SessionConfig().model,
        projectId: String = "",
        runId: String = ""
    ) async throws -> OpenAIShotDirectionPlanResult {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["shot_mode", "beats"],
            "properties": [
                "shot_mode": [
                    "type": "string",
                    "enum": ["continuous", "multi_shot"],
                    "description": "continuous = one unbroken take; multi_shot ONLY when the two keyframes cannot plausibly be one continuous camera move."
                ],
                "beats": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["duration_weight", "action", "camera"],
                        "properties": [
                            "duration_weight": [
                                "type": "integer",
                                "description": "Relative share of the segment, 1-4."
                            ],
                            "action": [
                                "type": "string",
                                "description": "One sentence of subject/scene MOTION only — never re-describe what the keyframes already depict, no timing numbers."
                            ],
                            "camera": [
                                "type": "string",
                                "description": "The camera move for this beat, or an empty string for none."
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let body: [String: Any] = [
            "model": model,
            "store": true,
            "reasoning": ["effort": "low"],
            "text": [
                "verbosity": "low",
                "format": [
                    "type": "json_schema",
                    "name": "shot_segment_direction_plan",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt]
                    ]
                ]
            ]
        ]
        let result = try await responsesRequest(
            operationName: "shot_segment_direction_plan_draft",
            body: body,
            model: model,
            timeoutInterval: 120,
            projectId: projectId,
            runId: runId
        )
        let text = result.rawText
        let response: ShotDirectionPlanResponse
        do {
            response = try JSONCoding.decoder.decode(ShotDirectionPlanResponse.self, from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI(
                "Shot direction plan response could not be read: \(error.localizedDescription). Output preview: \(responsePreview(text))"
            )
        }
        let beats = Array(
            response.beats
                .map {
                    OpenAIDirectionBeat(
                        durationWeight: min(max($0.durationWeight, 1), 4),
                        action: $0.action.trimmed,
                        camera: $0.camera.trimmed
                    )
                }
                .filter { !$0.action.isEmpty || !$0.camera.isEmpty }
                .prefix(4)
        )
        guard !beats.isEmpty else {
            throw ScreenGraphError.openAI("Shot direction plan returned no usable beats.")
        }
        return OpenAIShotDirectionPlanResult(
            shotMode: response.shotMode.trimmed,
            beats: beats,
            responseId: result.decoded.id,
            model: result.decoded.model ?? model,
            traceId: result.traceId
        )
    }

    func draftShotNarration(
        prompt: String,
        model: String = SessionConfig().model,
        projectId: String = "",
        runId: String = ""
    ) async throws -> OpenAILensNarrationResult {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["narration_text"],
            "properties": [
                "narration_text": [
                    "type": "string",
                    "description": "The spoken narration script, plain prose with no quotes or markup."
                ]
            ]
        ]
        let body: [String: Any] = [
            "model": model,
            "store": true,
            "reasoning": ["effort": "low"],
            "text": [
                "verbosity": "low",
                "format": [
                    "type": "json_schema",
                    "name": "shot_narration_draft",
                    "strict": true,
                    "schema": schema
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt]
                    ]
                ]
            ]
        ]
        let result = try await responsesRequest(
            operationName: "shot_narration_draft",
            body: body,
            model: model,
            timeoutInterval: 120,
            projectId: projectId,
            runId: runId
        )
        let text = result.rawText
        let response: LensNarrationDraftResponse
        do {
            response = try JSONCoding.decoder.decode(LensNarrationDraftResponse.self, from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI(
                "Shot narration response could not be read: \(error.localizedDescription). Output preview: \(responsePreview(text))"
            )
        }
        let script = response.narrationText.trimmed
        guard !script.isEmpty else {
            throw ScreenGraphError.openAI("Shot narration returned an empty script.")
        }
        return OpenAILensNarrationResult(
            script: script,
            responseId: result.decoded.id,
            model: result.decoded.model ?? model,
            traceId: result.traceId
        )
    }

    private func loadDraftSchema() throws -> Any {
        let url = try packagedResourceURL(named: "screen_graph_hydration_draft.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadProjectAestheticEvidenceSchema() throws -> Any {
        let url = try packagedResourceURL(named: "project_aesthetic_evidence.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadAestheticDirectionShortlistSchema() throws -> Any {
        let url = try packagedResourceURL(named: "aesthetic_direction_shortlist.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadAestheticDirectionRankSchema() throws -> Any {
        let url = try packagedResourceURL(named: "aesthetic_direction_rank.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadLensCompositionSchema() throws -> Any {
        let url = try packagedResourceURL(named: "lens_composition_v0_6.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadGoalStyleTaxonomyRefsSchema() throws -> Any {
        let url = try packagedResourceURL(named: "goal_style_taxonomy_refs_v0_1.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadProjectGoalInterviewSchema() throws -> Any {
        let url = try packagedResourceURL(named: "project_goal_interview.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadCharacterSheetRefineSchema() throws -> Any {
        let url = try packagedResourceURL(named: "character_sheet_refine_v0_1.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadProjectGoalInterviewV3Schema() throws -> Any {
        let url = try packagedResourceURL(named: "project_goal_interview_v0_7.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadGoalCastArticulationSchema() throws -> Any {
        let url = try packagedResourceURL(named: "goal_cast_articulation_v0_2.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadCharacterIdentityDraftSchema() throws -> Any {
        let url = try packagedResourceURL(named: "character_identity_draft_v0_1.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadCharacterFrameSuggestionsSchema() throws -> Any {
        let url = try packagedResourceURL(named: "character_frame_suggestions_v0_1.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadProjectLensWorkbenchInterviewSchema() throws -> Any {
        let url = try packagedResourceURL(named: "project_lens_workbench_interview_v0_1.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadProjectLensSetSchema() throws -> Any {
        let url = try packagedResourceURL(named: "project_lens_set_v0_1.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadImagePromptEnrichmentSchema() throws -> Any {
        let url = try packagedResourceURL(named: "image_prompt_enrichment.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadImageObservationSchema() throws -> Any {
        let url = try packagedResourceURL(named: "image_observation.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadProjectArchiveMeaningSchema() throws -> Any {
        let url = try packagedResourceURL(named: "project_archive_meaning.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadStorySignalSetSchema() throws -> Any {
        let url = try packagedResourceURL(named: "story_signal_set.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadStoryDirectionSetSchema() throws -> Any {
        let url = try packagedResourceURL(named: "story_direction_set.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadStorylineCreationInterviewSchema() throws -> Any {
        let url = try packagedResourceURL(named: "storyline_creation_interview.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadStorySingleStorylineSchema() throws -> Any {
        let url = try packagedResourceURL(named: "story_single_storyline.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadStoryBeatBoardSchema() throws -> Any {
        let url = try packagedResourceURL(named: "story_beat_board.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadStoryBeatSheetSchema() throws -> Any {
        let url = try packagedResourceURL(named: "story_beat_sheet.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func loadStoryAudioTrackDraftSchema() throws -> Any {
        let url = try packagedResourceURL(named: "story_audio_track_draft.schema", extension: "json")
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    }

    private func outputText(from response: OpenAIResponseBody) throws -> String {
        for output in response.output where output.type == "message" {
            for content in output.content ?? [] {
                if content.type == "refusal", let refusal = content.refusal {
                    throw ScreenGraphError.openAI("OpenAI refused the request: \(refusal)")
                }
                if (content.type == "output_text" || content.type == "text"), let text = content.text {
                    return text
                }
            }
        }
        throw ScreenGraphError.openAI("OpenAI response did not include output text.")
    }

    private func responsesRequest(
        operationName: String,
        body: [String: Any],
        model: String,
        timeoutInterval: TimeInterval,
        projectId: String = "",
        runId: String = "",
        traceGroupId: String = "",
        traceWorkflowName: String = "",
        traceWorkflowStep: String = "",
        traceArtifactType: String = "",
        traceArtifactId: String = ""
    ) async throws -> OpenAIResponseRequestResult {
        var storedBody = body
        storedBody["store"] = true
        let requestData = try JSONSerialization.data(withJSONObject: storedBody)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeoutInterval
        request.httpBody = requestData

        let result = try await timedData(
            for: request,
            operationName: operationName,
            timeoutInterval: timeoutInterval,
            traceMetadata: InferenceTraceRequestMetadata(
                provider: "openai",
                apiFamily: "responses",
                operation: operationName,
                projectId: projectId,
                runId: runId,
                traceGroupId: traceGroupId,
                workflowName: traceWorkflowName,
                workflowStep: traceWorkflowStep,
                artifactType: traceArtifactType,
                artifactId: traceArtifactId,
                model: model,
                requestBodyFormat: "application/json",
                responseBodyFormatHint: "application/json",
                providerRequestIDHeaderCandidates: ["x-request-id"]
            )
        )
        guard (200..<300).contains(result.statusCode) else {
            let bodyText = String(data: result.data, encoding: .utf8) ?? ""
            throw ScreenGraphError.openAI("OpenAI request failed (\(result.statusCode)): \(bodyText)")
        }
        let decoded = try JSONCoding.decoder.decode(OpenAIResponseBody.self, from: result.data)
        let rawText = try? outputText(from: decoded)
        await enrichTrace(
            traceId: result.traceId,
            decoded: decoded,
            rawText: rawText
        )
        if let error = decoded.error {
            throw ScreenGraphError.openAI(error.message)
        }
        guard let rawText else {
            throw ScreenGraphError.openAI("OpenAI response did not include output text.")
        }
        return OpenAIResponseRequestResult(
            decoded: decoded,
            rawText: rawText,
            traceId: result.traceId
        )
    }

    /// The Frame Creator's refine chat: rewrite the current form text per a
    /// directive, preserving its sentiment. Returns the rewrite + a change note.
    func transformFormPrompt(
        prompt: String,
        model: String = SessionConfig().model,
        projectId: String = "",
        runId: String = ""
    ) async throws -> OpenAIFormPromptTransformResult {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["transformed_prompt", "change_note"],
            "properties": [
                "transformed_prompt": [
                    "type": "string",
                    "description": "The rewritten frame description, plain prose, no headings or quotes."
                ],
                "change_note": [
                    "type": "string",
                    "description": "One line describing what changed."
                ]
            ]
        ]
        let (rawText, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "form_prompt_transform",
            prompt: prompt,
            model: model,
            verbosity: "low",
            timeoutInterval: 120,
            projectId: projectId,
            runId: runId
        )
        let response: FormPromptTransformResponse
        do {
            response = try JSONCoding.decoder.decode(FormPromptTransformResponse.self, from: Data(rawText.utf8))
        } catch {
            throw ScreenGraphError.openAI(
                "Form transform response could not be read: \(error.localizedDescription). Output preview: \(responsePreview(rawText))"
            )
        }
        let transformed = response.transformedPrompt.trimmed
        guard !transformed.isEmpty else {
            throw ScreenGraphError.openAI("Form transform returned an empty prompt.")
        }
        return OpenAIFormPromptTransformResult(
            transformedPrompt: transformed,
            changeNote: response.changeNote.trimmed,
            responseId: decoded.id,
            model: decoded.model ?? model
        )
    }

    func draftYouTubePublishCopy(
        prompt: String,
        model: String = SessionConfig().model,
        projectId: String = "",
        runId: String = ""
    ) async throws -> OpenAIYouTubePublishCopyResult {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["youtube_title", "description_markdown"],
            "properties": [
                "youtube_title": [
                    "type": "string",
                    "description": "The YouTube video title: plain text, at most 70 characters, no quotes or emoji."
                ],
                "description_markdown": [
                    "type": "string",
                    "description": "The YouTube description: 2 to 4 short plain-prose paragraphs separated by blank lines; no headings, links, hashtags, or attribution line."
                ]
            ]
        ]
        let (rawText, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "youtube_publish_copy",
            prompt: prompt,
            model: model,
            verbosity: "low",
            timeoutInterval: 120,
            projectId: projectId,
            runId: runId
        )
        let response: YouTubePublishCopyResponse
        do {
            response = try JSONCoding.decoder.decode(YouTubePublishCopyResponse.self, from: Data(rawText.utf8))
        } catch {
            throw ScreenGraphError.openAI(
                "YouTube copy response could not be read: \(error.localizedDescription). Output preview: \(responsePreview(rawText))"
            )
        }
        let title = response.youtubeTitle.trimmed
        let description = response.descriptionMarkdown.trimmed
        guard !title.isEmpty, !description.isEmpty else {
            throw ScreenGraphError.openAI("YouTube copy returned an empty title or description.")
        }
        return OpenAIYouTubePublishCopyResult(
            title: title,
            descriptionMarkdown: description,
            responseId: decoded.id,
            model: decoded.model ?? model
        )
    }

    private func strictJSONResponse(
        schema: Any,
        name: String,
        prompt: String,
        model: String,
        verbosity: String,
        timeoutInterval: TimeInterval,
        projectId: String = "",
        runId: String = ""
    ) async throws -> (String, OpenAIResponseBody) {
        let body: [String: Any] = [
            "model": model,
            "store": true,
            "reasoning": ["effort": "low"],
            "text": [
                "verbosity": verbosity,
                "format": [
                    "type": "json_schema",
                    "name": name,
                    "strict": true,
                    "schema": schema
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": prompt]
                    ]
                ]
            ]
        ]
        let result = try await responsesRequest(
            operationName: name,
            body: body,
            model: model,
            timeoutInterval: timeoutInterval,
            projectId: projectId,
            runId: runId
        )
        return (result.rawText, result.decoded)
    }

    private func strictJSONResponse(
        schema: Any,
        name: String,
        content: [[String: Any]],
        model: String,
        verbosity: String,
        timeoutInterval: TimeInterval,
        projectId: String = "",
        runId: String = ""
    ) async throws -> (String, OpenAIResponseBody) {
        let body: [String: Any] = [
            "model": model,
            "store": true,
            "reasoning": ["effort": "low"],
            "text": [
                "verbosity": verbosity,
                "format": [
                    "type": "json_schema",
                    "name": name,
                    "strict": true,
                    "schema": schema
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": content
                ]
            ]
        ]
        let result = try await responsesRequest(
            operationName: name,
            body: body,
            model: model,
            timeoutInterval: timeoutInterval,
            projectId: projectId,
            runId: runId
        )
        return (result.rawText, result.decoded)
    }

    private func timedData(
        for request: URLRequest,
        operationName: String,
        timeoutInterval: TimeInterval,
        traceMetadata: InferenceTraceRequestMetadata
    ) async throws -> OpenAIHTTPResult {
        do {
            let result = try await TracedHTTPTransport.send(
                request: request,
                metadata: traceMetadata
            )
            return OpenAIHTTPResult(
                data: result.data,
                statusCode: result.response?.statusCode ?? 0,
                response: result.response,
                traceId: result.traceId,
                latencyMs: result.latencyMs
            )
        } catch let error as URLError where error.code == .timedOut {
            throw ScreenGraphError.openAI("\(operationName) timed out after \(Int(timeoutInterval)) seconds.")
        } catch {
            throw error
        }
    }

    private func enrichTrace(
        traceId: String,
        decoded: OpenAIResponseBody,
        rawText: String?
    ) async {
        await InferenceTraceStore.shared.enrich(
            traceId: traceId,
            providerResponseId: decoded.id,
            model: decoded.model ?? "",
            usage: decoded.usage.map {
                InferenceTraceUsage(
                    inputTokens: $0.inputTokens,
                    outputTokens: $0.outputTokens,
                    totalTokens: $0.totalTokens
                )
            },
            parsedOutputJSON: parsedOutputJSON(rawText)
        )
    }

    private func parsedOutputJSON(_ rawText: String?) -> String {
        guard let rawText else { return "" }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            return ""
        }
        return trimmed
    }

    private func responsePreview(_ text: String, limit: Int = 360) -> String {
        let compact = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        guard !compact.isEmpty else { return "empty output" }
        if compact.count <= limit {
            return compact
        }
        return String(compact.prefix(limit)).trimmed + "..."
    }

    private func hydrationPrompt(capture: CaptureRecord, rollingContext: String) -> String {
        """
        Analyze this screen capture as the next keyframe in a guided knowledge-graph hydration session.

        Return only JSON that matches the provided schema. Do not create durable IDs. Use evidence_indices and surface_index only when helpful; the app will assign stable IDs after validation.

        Primary purpose:
        - Infer useful workflow and root-context signals from the visible screen.
        - Describe literal visual facts first, then cautious claims and meaning seeds.
        - Prefer facts visible in the screenshot over assumptions from prior context.
        - Keep privacy warnings explicit when the screen appears to contain credentials, private messages, financial data, health data, or other sensitive personal information.

        Important constraints:
        - Do not identify real people by name unless their name is explicitly visible as public page text.
        - Do not infer sensitive attributes.
        - Put empty arrays where there is no evidence.
        - Keep operator_summary concise and useful for a live sidebar.

        Current capture:
        - capture_id: \(capture.captureId)
        - captured_at: \(capture.capturedAt)
        - image_ref: \(capture.relPath)
        - image_sha256: \(capture.sha256)
        - diff_reason: \(capture.message)

        Rolling session context from already-analyzed frames:
        \(rollingContext.isEmpty ? "No prior analyzed context." : rollingContext)
        """
    }

    private func mediaObservationPrompt(context: MediaObservationGenerationContext) -> String {
        return """
        Observe one LitScenes media frame. Return only JSON matching the provided ImageObservationResult schema.

        This is a literal media observation pass for a local personal archive. Use the image as the source of truth.
        Do not invent people, brands, places, events, chronology, injuries, claims, or outcomes that are not visibly supported.
        Do not identify private people by name. Describe visible roles and relationships only when the image supports them.
        Use concise concrete phrases. Put uncertainty into uncertainties and human_review rather than overclaiming.
        Fill object_descriptions with useful object titles and short descriptions for a chat memory system.
        Fill palette_terms, place_cues, era_cues, motif_cues, energy_cues, and composition_cues with concise aesthetic-retrieval phrases grounded in the visible frame.
        Those retrieval arrays must stay observational. Do not invent a future direction the archive does not show.
        Keep all metadata fields exactly as provided below; the app will validate and persist the result.
        Set observation_provider to "openai", prompt_version to "\(MediaObservationConstants.promptVersion)", and thumbnail_policy_version to "\(MediaObservationConstants.thumbnailPolicyVersion)".
        Set detail_pass_used and object_description_pass_used to false; this Desktop pass is one native observation request.
        Set detail vision fields to empty strings or zero values.
        This prompt is project-neutral and cacheable across LitScenes projects. Do not use project names, file paths, folder names, curation tags, user notes, or future story intent because none are provided.
        Set project-specific metadata fields to empty strings; the app will restamp them after analysis is reused in a project.

        Media metadata:
        - schema_version: \(MediaObservationConstants.schemaVersion)
        - media_id: ""
        - frame_id: ""
        - source_path: ""
        - source_image_sha256: ""
        - image_hash: \(context.visionInputSha256)
        - created_at: \(context.generatedAt)
        - source_image_path: ""
        - vision_input_kind: thumbnail_base
        - vision_input_path: ""
        - vision_input_sha256: \(context.visionInputSha256)
        - vision_input_width: \(context.visionInputWidth)
        - vision_input_height: \(context.visionInputHeight)
        - vision_input_bytes: \(context.visionInputBytes)
        - vision_thumbnail_profile: base
        - fullres_vision_allowed: false
        """
    }

    private func projectAestheticEvidencePrompt(context: ProjectAestheticEvidenceGenerationContext) -> String {
        """
        You are building a normalized retrieval profile for LitScenes AESTHETIC direction selection.

        Return only JSON matching the provided ProjectAestheticEvidenceProfileResponse schema.
        Separate archive truth from goal intent.
        Missing media support for a goal cue is a gap, not a contradiction.
        Only use contradictions when the archive visibly argues against a goal cue or when the goal itself contains conflicting asks.

        Requirements:
        - Keep every cue concise and reusable for retrieval.
        - Prefer short phrases, not sentences.
        - archive_* arrays must come from analyzed media evidence only.
        - goal_visual_cues must describe visible treatment implications from the Goal, not plot.
        - goal_world_cues may hold explicit story/world asks, but only when they are not already captured as visible treatment cues.
        - goal_* arrays must come from the Goal Brief and early aesthetic intent only.
        - goal_only_gaps should name desired treatment/world cues that are explicit in the Goal but weak or absent in the archive evidence.
        - contradictions should stay empty unless there is real tension.
        - Do not choose named aesthetics, references, or render prompts.
        - Do not ask questions.

        Project:
        - project_id: \(context.projectId)
        - project_name: \(context.projectName)
        - generated_at: \(context.generatedAt)
        - enabled_item_count: \(context.enabledItemCount)
        - analyzed_item_count: \(context.analyzedItemCount)

        Goal Brief:
        \(context.goalBriefSummary.isEmpty ? "No Goal Brief summary was provided." : context.goalBriefSummary)

        Early Aesthetic Intent:
        \(context.aestheticIntentSummary.isEmpty ? "No early aesthetic intent was provided." : context.aestheticIntentSummary)

        Analyzed media observation summary:
        \(context.mediaObservationSummary.isEmpty ? "No analyzed media observations were provided." : context.mediaObservationSummary)
        """
    }

    static func lensCompositionPrompt(context: LensTrioContext) -> String {
        let validationNote = context.validationError.trimmed.isEmpty
            ? ""
            : "\nA previous attempt failed validation: \(context.validationError). Correct this in the new response.\n"
        let rosterNote = context.rosterCharacterLines.isEmpty
            ? ""
            : """

        Defined project characters (the ONLY people this world may cast — use these EXACT names in cast_members, in every scene's cast, and inside character prompts; never rename or invent):
        \(context.rosterCharacterLines.joined(separator: "\n"))
        """
        return """
        Compose one saved Scene for this project: a distinct way of seeing the saved Goal, expressed as FRAME recommendations the user will review per department — scenery frames, one character study, and one object study. You author structured WORLD DATA, not finished image prompts: prompt text is assembled from your fields later, and every image renders with a style reference image attached. Ground everything in the Saved Goal, the Story Input media observations, and the defined characters below. Never import a genre register the Goal does not state: the world's condition, era, and mood follow the Goal — a pristine world has pristine places; a thriving one has living ones.

        HARD RULE for every content field (areas, cast_members, object_concepts, set_dressing): \(contentFieldHardRuleCore) The Scene's style language belongs ONLY in visual_summary, look, palette, materials, motifs, composition, pacing_energy, and avoid.

        Step 1 — the Scene itself:
        - title: a short evocative Scene name.
        - claim: one sentence stating what this Scene asserts about the Goal.
        - visual_summary and look: concrete appearance language — light, palette behavior, surface, framing, energy. Style lives here and only here.
        - palette/materials/motifs/composition/pacing_energy/avoid: short concrete visual terms.
        - must_preserve / must_avoid: the non-negotiables of this look.

        Step 2 — areas (2 to 4), authored FIRST as internal grouping. An Area is one of this world's PLACES: a broad recurring environment the camera can return to, large enough to own child Scenes. Each Area has: area_id ("area_1", "area_2", …), title, setting, prose_prompt, enabled true, and 1 or 2 scenes. Across ALL Areas there are EXACTLY 4 child Scenes in total; those four are the four renderable scenery FRAME recommendations. Each child Scene is a specific renderable view, corner, vantage, interior pocket, or moment inside that Area and has scene_id ("scene_1_1", "scene_1_2", etc.), title, setting, prose_prompt, cast, story_beat, enabled true. Per setting: title (short handle), location_name (specific), location_type (interior/exterior, urban/coastal/rural...), time_of_day, weather, spatial_layout (how the space is arranged relative to the viewer), foreground_details (2-6 concrete things near the viewer), background_details (2-6 distant things), notable_features (1-6 distinctive physical features of THIS place — landmarks, structures, natural forms, fixtures — whatever this Goal's world actually has). Be a location scout: specific, physical, verifiable details, like "a folding work table across the road from a low seawall" — never generic filler. THE SPREAD RULE: the four Scenes are four DISPARATE story moments spread across the story's arc — distinct places and/or distinct beats, never four stops on one path, never consecutive shots of one approach, and no two Scenes from the same beat. story_beat names the arc position each Scene samples — "opening", "rising", "turn", "ending" — each used exactly once across the four.
        Each child Scene's cast (0-2 entries) names the people naturally present in that view, drawn ONLY from cast_members or the defined project characters below, by their EXACT names — never invent a new person here. Per cast entry: name (the exact name) and presence (a short subject-matter-only phrase for what they are doing or how they occupy the place — "steadying jars at the batching table", "curled in the dog bed"). The presence phrase is world data: actions, posture, position — zero art direction, and no appearance re-description (cast_members descriptions own appearance). Cast someone only when the Scene implies them; an empty cast [] is correct for unpopulated establishing views, and not every Scene needs people.

        Step 3 — cast_members (exactly 1): the recurring named character of this world. When defined project characters are listed below, cast_members[0] MUST be one of them by EXACT name and every scene cast entry MUST name a listed character — invent no one. Invent a character only when no project characters exist. Per member: name; description (25-60 words: species, build, age, dress, gear, bearing — identical across every appearance); signature_props (0-3 distinctive objects they always carry or wear); environment_affinity (the setting they belong to, by title or plain phrase).

        Step 4 — object_concepts (exactly 1 structured prop study): the object that carries this world's story, including a cast signature prop where fitting. Per concept: name, type, material, condition (pristine/new/well-kept/worn/patched — as the Goal's world dictates, never assumed), distinguishing_features (1-5), location_in_scene (where it lives in this world's places).

        Step 5 — set_dressing (2-4 short strings): ambient environment objects nobody uses, drawn from THIS Goal's world — the furniture, tools, growth, vessels, fixtures, or markers a place like this actually holds. Condition follows the Goal: never default to decay, ruin, remnants, or abandonment unless the Goal states them. These fold into scenery concepts.

        Step 6 — suggested_media_plan: mode is always "collection" (each Frame is its own moment), aspect ("landscape" for cinematic or video-first goals, "portrait" for vertical formats, else "square"), set_dressing_density ("off"/"sparse"/"standard"/"rich" — rich when ambient objects carry the Goal's meaning), allow_readable_text (true only when the Goal makes environmental text — signs, labels, inscriptions — part of the story), sequence_beats always []. Always set character_count to 1 and cast_object_count to 1.

        Step 7 — cast styles from the numbered slate below. Choose primary_style_index and exactly two accent_style_indexes:
        - Refer to styles ONLY by their [number]; never invent styles or copy names as identifiers.
        - Area and Scene concept renders use the primary style. Pick accent styles for blend identity and later exploration, not as automatic duplicate renders.
        - blend_profile: dominant, anchored, or ensemble — the scene's stated identity balance.
        - style_rationale: one line on why these styles serve this Scene.
        \(validationNote)\(rosterNote)
        Project: \(context.projectName)

        Saved Goal:
        \(context.goalSummary)

        Story Input media observations (what the author's own material shows — subject matter only):
        \(context.mediaObservationLines.isEmpty ? "(no analyzed Story Input media)" : context.mediaObservationLines.joined(separator: "\n"))

        Goal meaning context JSON with selected meaning nodes, edge neighbors, evidence, and aesthetic candidates:
        \(context.meaningContext.trimmed.isEmpty ? "(none retrieved)" : context.meaningContext)

        Style slate (choose by [number]):
        \(context.slateLines.joined(separator: "\n"))
        """
    }

    static func characterSheetRefinePrompt(context: CharacterSheetRefineContext) -> String {
        let props = context.signatureProps.map(\.trimmed).filter { !$0.isEmpty }
        let directives = context.currentDirectives.map(\.trimmed).filter { !$0.isEmpty }
        let sheetLine = context.hasActiveSheet
            ? "The FIRST attached image is the character's CURRENT reference sheet: treat it as the present state and describe what the next render should change. Any further attached images are source images."
            : "No sheet has rendered yet; any attached images are source images of the character."
        let editedLine = context.promptIsHandEdited
            ? "This prompt is HAND-EDITED by the user and renders verbatim: your changes to the appearance, props, and refinements are recorded on the character but do NOT enter the prompt until the user resets it to the composed prompt or edits it by hand. Say so in assistant_message in one short clause."
            : ""
        return """
        You refine one character's reference sheet through conversation. Return only JSON matching the schema.

        Project: \(context.projectName)
        The character: "\(context.characterName)"
        Appearance today: \(context.visualDescription.trimmed.isEmpty ? "(nothing written yet)" : context.visualDescription.trimmed)
        Always with them: \(props.isEmpty ? "(nothing recorded)" : props.joined(separator: "; "))
        Story identity: \(context.storyIdentityLines.trimmed.isEmpty ? "(none)" : context.storyIdentityLines.trimmed)
        Sheet refinements currently in force:
        \(directives.isEmpty ? "(none)" : directives.map { "- \($0)" }.joined(separator: "\n"))

        The exact prompt the next sheet render transmits today:
        \"\"\"
        \(context.renderedSheetPrompt)
        \"\"\"
        \(editedLine)

        Source images on file (media_id — what it shows):
        \(context.sourceImageLines.trimmed.isEmpty ? "(none)" : context.sourceImageLines)
        \(sheetLine)

        Recent conversation:
        \(context.recentTurnsSummary.trimmed.isEmpty ? "(first message)" : context.recentTurnsSummary)

        The user now says: "\(context.userMessage)"

        Rules:
        - assistant_message: short and conversational — say what changed and, in a phrase, what the next render will show. Describe appearance only; never identify a real private person by name.
        - visual_description: the FULL replacement appearance line when the user changed how the character looks; "" to keep the current one.
        - signature_props: the full replacement list (at most 3) when props changed; [] to keep the current ones.
        - sheet_directives: the COMPLETE list in force after this turn — carry forward every earlier directive the user did not retract, add the new ones, drop what they reversed; at most 12, each one imperative line about how the sheet renders. No story or frame style words.
        - source_image_notes: for attached source images that clearly show this character, a short label of what the image shows ("face, three-quarter"); [] otherwise. Use media_id values exactly as listed.
        - change_summary: one line, or "" when nothing about the character changed (the user only asked a question).
        """
    }

    private func goalStyleTaxonomyRefsPrompt(context: GoalStyleTaxonomyRefsContext) -> String {
        let collections = context.collections
            .map { "- \($0.key): \($0.name) — \($0.description)" }
            .joined(separator: "\n")
        return """
        Map this project's saved Goal onto the LitScenes style taxonomy so a style catalog can be searched for fitting visual styles.

        Return schema_version "litscenes.goal_style_taxonomy_refs.v0.1" and 6-20 style_term_refs. Rules:
        - kind "mood": choose only from these display moods: \(context.moods.joined(separator: ", ")). Pick 2-4 that the finished work should feel like.
        - kind "hue": choose only from these hue names: \(context.hues.joined(separator: ", ")). Pick 1-3 only when the Goal implies a palette direction.
        - kind "collection": choose only from these collection keys. Pick 1-3 whose lane serves the Goal's intent:
        \(collections)
        - kind "medium": optional, at most 1, only from: \(context.mediums.joined(separator: ", ")).
        - kind "phrase": 4-8 short concrete visual retrieval keywords (1-3 words each, lowercase) describing light, place, texture, weather, or motif the Goal evokes. Describe appearance, never plot or subjects' names.
        - weight: 0.5-1.5 by importance to the Goal's intent; the strongest signal gets the highest weight.
        - rationale: one short clause tying the term to the Goal.
        - Serve the Goal's intent and desired viewer response, not a literal inventory of what media already exists.

        Saved Goal:
        \(context.goalSummary)
        """
    }

    /// The unusual-character contract shared by the articulation and steer prompts.
    static func goalCastIdentityContractBlock() -> String {
        Self.identityContractBlock()
    }

    /// The subject-matter-only law shared by every prompt that authors world data
    /// (the composition prompt and the sheet → suggestions prompt).
    static let contentFieldHardRuleCore = "SUBJECT MATTER ONLY — places, people, things, spatial facts. Zero art direction: no color or palette words, no rendering technique or medium words (ink, neon, painterly, photographic, halftone...), no lighting-character adjectives, no texture-treatment or art-style words. Time of day and weather are plain facts (\"11:47 p.m.\", \"humid rain squall\"), never palette descriptions. Style words in content fields override the attached style image and ruin renders."

    /// Two character-moment suggestions for one character: frames in which the
    /// character ACTS. Fixture-neutral: distinct from every listed scene, existing
    /// areas preferred, the character present by exact name, subject matter only.
    static func characterFrameSuggestionsPrompt(context: CharacterFrameSuggestionContext) -> String {
        let name = context.characterName
        let identityLine: String
        switch context.attachedIdentityImage {
        case .sheet:
            identityLine = "The attached image is \"\(name)\"'s rendered reference sheet — that IS the character's appearance; never re-describe it in any field."
        case .sourcePhoto:
            identityLine = "The attached image is a source photo of \"\(name)\" — appearance reference only; never re-describe it in any field."
        case .none:
            identityLine = "No reference image is attached; the appearance line below is the character."
        }
        let appearance = context.characterAppearance.trimmed
        let gist = context.characterIdentityGist.trimmed
        return """
        Compose exactly 2 NEW dramatic MOMENTS for one character of this project — frames in which "\(name)" ACTS: an action, a confrontation, a decision, or a tell — in a specific place. Each moment is a character-action frame, never an empty environment view and never a portrait or study. You author structured WORLD DATA plus one moment line, not finished image prompts: prompt text is assembled from your fields later, and every image renders with a style reference image attached. Ground everything in the Saved Goal, the character's identity, the existing plan, and the Story Input observations below. Never import a genre register the Goal does not state.

        HARD RULE for every content field (area, scene, setting, cast presence, moment): \(contentFieldHardRuleCore)

        Rules:
        - moment: ONE sentence, present tense, the visible dramatic action — who does what, to whom or to what, with what object, right here. Physical and legible in a single still. No camera, lens, lighting, or style words.
        - Both moments must be DISTINCT from every existing scene listed below and from each other — a different place, action, or decision; never a re-shoot of a listed scene.
        - Prefer the existing areas: set area_ref to that area's area_id and area to null. Add at most ONE new area across both scenes; for a new area set area_ref to "" and fill area (title, setting, prose_prompt). When no areas exist yet, both scenes share the one new area (repeat the same title).
        - Per scene: title, setting, prose_prompt, cast, story_beat. Setting fields: title (short handle), location_name (specific), location_type (interior/exterior, urban/coastal/rural...), time_of_day, weather, spatial_layout (how the space is arranged relative to the viewer), foreground_details (2-6 concrete things near the viewer), background_details (2-6 distant things), notable_features (1-6 distinctive physical features of THIS place). Be a location scout: specific, physical, verifiable details — never generic filler.
        - cast (1-2 entries) MUST lead with "\(name)" by that exact name; presence = what they are physically doing in this moment — subject matter only, no appearance re-description. A second entry names one of the other characters listed below by EXACT name, only when the moment needs them (a confrontation, a hand-off, a witness); never invent a person.
        - scene title: the moment's name (two to five words), not the place's name.
        - story_beat: the arc position this frame samples — opening, rising, turn, or ending. Pick the beats this character most needs; repeating a beat an existing scene already carries is allowed.
        - casting_note: one line on why these two moments belong to this character.

        Project: \(context.projectName)
        The character: "\(name)"
        Appearance: \(appearance.isEmpty ? "(none written)" : appearance)
        Story identity: \(gist.isEmpty ? "(none)" : gist)
        \(identityLine)

        Other characters (castable by exact name):
        \(context.otherCharacterLines.isEmpty ? "None." : context.otherCharacterLines.joined(separator: "\n"))

        Saved Goal:
        \(context.goalSummary)

        Existing areas (area_id · title · place):
        \(context.existingAreaLines.isEmpty ? "(none yet)" : context.existingAreaLines.joined(separator: "\n"))

        Existing scenes (do not repeat these):
        \(context.existingSceneLines.isEmpty ? "(none)" : context.existingSceneLines.joined(separator: "\n"))

        Story Input media observations (what the author's own material shows — subject matter only):
        \(context.mediaObservationLines.isEmpty ? "(no analyzed Story Input media)" : context.mediaObservationLines.joined(separator: "\n"))

        Source images on file for this character (media_id — what it shows):
        \(context.sourceImageLines.trimmed.isEmpty ? "(none)" : context.sourceImageLines)
        """
    }

    /// Two character-moment suggestions for one character: text with the sheet
    /// (else a source photo) as the one optional image. No ledger row, no pause guard.
    func suggestCharacterFrames(
        context: CharacterFrameSuggestionContext,
        visionInputs: [OpenAIVisionImageInput] = [],
        model: String = SessionConfig().model
    ) async throws -> OpenAICharacterFrameSuggestionResult {
        let schema = try loadCharacterFrameSuggestionsSchema()
        let prompt = Self.characterFrameSuggestionsPrompt(context: context)
        var content: [[String: Any]] = [
            ["type": "input_text", "text": prompt]
        ]
        for input in visionInputs.prefix(1) {
            content.append([
                "type": "input_image",
                "image_url": "data:\(input.mimeType);base64,\(input.data.base64EncodedString())",
                "detail": input.detail
            ])
        }
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "character_frame_suggestions",
            content: content,
            model: model,
            verbosity: "medium",
            timeoutInterval: 180,
            projectId: context.projectId
        )
        let response: CharacterFrameSuggestionResponse
        do {
            response = try CharacterFrameSuggestionResponse.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Character frame suggestions response could not be read: \(error.localizedDescription)")
        }
        return OpenAICharacterFrameSuggestionResult(
            response: response,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0)
        )
    }

    static func identityContractBlock() -> String {
        """
        An UNUSUAL CHARACTER = familiar human legibility + ONE deep contradiction + one nonstandard operating rule + visible consequences. Fields:
        - essence: a one-line logline of the person.
        - public_function: a recognizable archetype or role — the familiar handle.
        - desire: the dominant desire, apparently incongruous with that role.
        - operating_rule: the private rule they consistently follow in pursuit of the desire.
        - cost: what following the rule visibly costs — relationship, status, or safety.
        - signature: ONE recurring action, object, or silhouette that expresses the contradiction on screen. Never explanatory biography.
        - formative_pressure: an optional one-line why behind the rule; "" when unearned.
        - strangeness: 0-1, the DISTANCE between the archetype and the desire. 0 means an entirely ordinary character with no manufactured contradiction — a legitimate steady state.
        - visual_description: a render-facing physical description embodying the signature (species, build, age, dress, gear, bearing) — identical across every appearance, plain content words.
        Constraints:
        - Exactly ONE primary contradiction per character; stacking quirks reads as fake.
        - The weirdness must alter choices, not just decorate a costume.
        - Unusualness must carry a visible cost.
        - Express strangeness through the signature, not backstory.
        - Calibrate strangeness and tone to the Goal contract: furious satire licenses grotesque comic exaggeration; a personal story dramatizes only what the Goal states — never invent biography for real people.
        - THE FORMULA IS A GAP-FILLER, NOT A VALIDATOR: fill only the dimensions the user has not specified, calibrated to the Goal. Never intensify, quirk-ify, "improve", or complete what the user stated. If the user or Goal wants a plain character, plain is correct.
        """
    }

    /// One character, named by the user, cast to fit the Goal and stand apart from the
    /// ensemble — with the source images as the person. Fills only the blanks it is
    /// handed; everything already written comes back empty.
    static func characterIdentityDraftPrompt(context: CharacterIdentityDraftContext) -> String {
        let blankList = CharacterIdentityBlank.allCases
            .filter { context.blanks.contains($0) }
            .map(CharacterIdentityDraft.promptLabel(for:))
        let keepRule = context.keepLines.isEmpty
            ? "- Nothing else is written yet."
            : "- Already written — keep exactly, return these parts empty (\"\" or []):\n" + context.keepLines.map { "  - \($0)" }.joined(separator: "\n")
        let imageRule = context.sourceCount > 0
            ? "- The attached images ARE this person. Derive face, hair, build, skin, and clothing from them, then reconcile with the Goal's world. Never identify a real person by name."
            : "- No images are attached: invent the appearance within the Goal's world."
        let labelRule = context.sourceCount > 0
            ? "- source_image_notes: one short label per attached image naming what it shows (angle, age, context), using the media_id values listed below; [] when source_image_notes is not requested."
            : "- source_image_notes: []."
        return """
        You are casting ONE character of a LitScenes project so their reference sheet renders well on the first try.

        Return only JSON matching the provided CharacterIdentityDraftResponse schema.
        The character is named exactly "\(context.characterName)".
        - Fill ONLY these parts: \(blankList.joined(separator: "; ")).
        \(keepRule)
        \(identityContractBlock())

        Drafting rules:
        - Fit the saved Goal's world, era, and register; never import a genre the Goal does not state.
        - Make this character DISTINCT from every other listed character — silhouette, palette, age, build, gear, bearing — and coherent with the ensemble.
        - visual_description is render-facing: species, age, build, face, hair, skin, dress, gear, bearing — plain content words, identical across appearances, 40 to 90 words. No style, medium, or camera words.
        \(imageRule)
        - signature_props: up to three physical objects or wearables they always carry; [] when not requested.
        - environment_affinity: the place they visually belong to, plain content words; "" when not requested.
        \(labelRule)
        - casting_note: one sentence, for the character's conversation, on what you drew from.

        Saved Goal:
        \(context.goalSummary.trimmed.isEmpty ? "(no saved Goal yet — cast from the name, the other characters, and the images)" : context.goalSummary)

        Required entities:
        \(context.requiredEntityLines.isEmpty ? "None declared." : context.requiredEntityLines.joined(separator: "\n"))

        Other characters (be distinct from these):
        \(context.otherCharacterLines.isEmpty ? "None yet." : context.otherCharacterLines.joined(separator: "\n"))

        Current cast (ensemble coherence):
        \(context.castLines.isEmpty ? "None yet." : context.castLines.joined(separator: "\n"))

        Story Input observations (world, era, palette):
        \(context.moodboardLines.trimmed.isEmpty ? "(none analyzed yet)" : context.moodboardLines)

        Source images on file (media_id — what it shows):
        \(context.sourceImageLines.trimmed.isEmpty ? "(none)" : context.sourceImageLines)
        """
    }

    /// Drafts one character's identity from the Goal, the ensemble, and the source
    /// images. Text-only with vision: no ledger row.
    func draftCharacterIdentity(
        context: CharacterIdentityDraftContext,
        visionInputs: [OpenAIVisionImageInput] = [],
        model: String = SessionConfig().model
    ) async throws -> OpenAICharacterIdentityDraftResult {
        let schema = try loadCharacterIdentityDraftSchema()
        let prompt = Self.characterIdentityDraftPrompt(context: context)
        var content: [[String: Any]] = [
            ["type": "input_text", "text": prompt]
        ]
        for input in visionInputs.prefix(6) {
            content.append([
                "type": "input_image",
                "image_url": "data:\(input.mimeType);base64,\(input.data.base64EncodedString())",
                "detail": input.detail
            ])
        }
        let (text, decoded) = try await strictJSONResponse(
            schema: schema,
            name: "character_identity_draft",
            content: content,
            model: model,
            verbosity: "low",
            timeoutInterval: 180,
            projectId: context.projectId
        )
        let response: CharacterIdentityDraftResponse
        do {
            response = try CharacterIdentityDraftResponse.decode(from: Data(text.utf8))
        } catch {
            throw ScreenGraphError.openAI("Character identity draft response could not be read: \(error.localizedDescription)")
        }
        return OpenAICharacterIdentityDraftResult(
            response: response,
            responseId: decoded.id,
            model: decoded.model ?? model,
            usage: decoded.usage ?? OpenAIUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0)
        )
    }

    /// THE MEDIA-FIRST CASTING LAW: at most `castCap` members, anchored to the
    /// Story Input photos that show people when there are any; invent only when
    /// there are none (and then one). Static so tests can pin the register.
    static func goalCastArticulationPrompt(context: GoalCastArticulationContext) -> String {
        let countRule: String
        if let desired = context.desiredCount {
            countRule = "- Return exactly \(desired) new member\(desired == 1 ? "" : "s")."
        } else {
            countRule = "- Return at most \(context.castCap) members in total — the one or two people this Goal's story turns on. Fewer is correct when the Goal needs fewer; 0 only when it involves no person-like subject. Required entities count toward the total; when more are required than fit, cast the ones the story turns on first."
        }
        let inventCount = context.desiredCount == nil
            ? " Return 1 member, or 2 only when the Goal clearly needs two people."
            : ""
        let mediaRule = context.peoplePhotoLines.isEmpty
            ? "- No Story Input photo shows a person: invent the cast within the Goal's world and set reference_media_ids to [] on every member.\(inventCount)"
            : "- MEDIA FIRST: the Story Input photos below show real people. Every member you return MUST be one of them who is not already a cast member: set reference_media_ids to the media_id values of the photos showing that person (1-8 ids, clearest first) and write visual_description from what those photos show (face, hair, build, skin, age, dress), reconciled with the Goal's world. Do not invent anyone while a photographed person fits the Goal; when only one person appears across the photos, return one member; if every photographed person is already cast, invent one and set reference_media_ids to []. Never identify a real person by name — use the name the Goal gives them, else a plain role name."
        let excludeRule = context.excludeNames.isEmpty
            ? ""
            : "\n- Never emit these already-cast names: \(context.excludeNames.joined(separator: ", "))."
        return """
        You are casting the ensemble for a LitScenes project from its saved GOAL contract.

        Return only JSON matching the provided GoalCastArticulationResponse schema.
        \(Self.goalCastIdentityContractBlock())

        Casting rules:
        - Cast only person-like subjects: people, personified beings, named creatures. Organizations, brands, and places are never cast members — they inform context only.
        - Every person-like required entity below marked [required] MUST be cast under its exact name; carry its stated role into the character's public_function.
        \(countRule)\(excludeRule)
        \(mediaRule)
        - reference_media_ids: only media_id values listed below; [] when none apply. Each photo anchors exactly ONE member — never the same media_id for two members; a photo showing two people goes to the member it shows best, and the other member takes a different photo.
        - Return 0 members only when the Goal involves no person-like subjects, and say why in casting_note.
        - Existing roster characters: reuse their EXACT names when casting them and keep visual_description consistent with their current descriptions.
        - Set changed_fields to every field you authored (all nine for a new member).
        - casting_note: one short line on the casting logic (or the reason for zero members).

        Saved Goal:
        \(context.goalSummary)

        Required entities:
        \(context.requiredEntityLines.isEmpty ? "None declared." : context.requiredEntityLines.joined(separator: "\n"))

        Story Input photos with people (media_id — what it shows; the attached images are the first of these, in this order):
        \(context.peoplePhotoLines.isEmpty ? "(none)" : context.peoplePhotoLines.joined(separator: "\n"))

        Existing roster characters (name + appearance continuity):
        \(context.rosterCharacterLines.isEmpty ? "None yet." : context.rosterCharacterLines.joined(separator: "\n"))

        Current cast members (ensemble coherence — do not re-emit):
        \(context.existingMemberSummaries.isEmpty ? "None yet." : context.existingMemberSummaries.joined(separator: "\n"))
        """
    }

    private func goalCastSteerPrompt(context: GoalCastSteerContext) -> String {
        let gestureRule: String
        switch context.gesture {
        case "stranger":
            gestureRule = "STRANGER: raise strangeness by roughly +0.15 to +0.25 and widen the distance between public_function and desire. Same soul — same person, same essence core; the consequences amplify."
        case "tamer":
            gestureRule = "TAMER: lower strangeness by roughly -0.15 to -0.25; the contradiction persists but reads subtler and the costs get quieter. Tamer bottoms out at plain: at low values converge on an ordinary, credible person — do not preserve quirk for its own sake."
        case "new-rule":
            gestureRule = "NEW RULE: keep public_function and desire; replace operating_rule with a DIFFERENT private rule expressing the same contradiction. cost and signature follow the new rule."
        case "raise-cost":
            gestureRule = "RAISE COST: keep the rule; escalate what it visibly costs (relationship → status → safety). The consequences become more visible in the signature."
        case "new-tell":
            gestureRule = "NEW TELL: keep everything else; invent a DIFFERENT recurring action, object, or silhouette that expresses the same contradiction, and update visual_description to embody it."
        default:
            gestureRule = """
            FEEDBACK — apply the user's directive: "\(context.feedbackText)". Same soul, but — preserve the identity core except where the directive says otherwise. This is direct user text: obey it literally; do not reinterpret it toward the formula.
            """
        }
        let pinsRule = context.pinnedDimensions.isEmpty
            ? ""
            : "\n- PINNED — keep these fields EXACTLY as they are in the current identity, verbatim: \(context.pinnedDimensions.joined(separator: ", "))."
        let priorRule = context.priorTakeEssences.isEmpty
            ? ""
            : "\n- Do not repeat these earlier takes on the character:\n\(context.priorTakeEssences.map { "  - \($0)" }.joined(separator: "\n"))"
        let appearanceRule = context.rosterAppearanceLine.isEmpty
            ? ""
            : "\n- Current roster appearance (keep visual continuity unless the gesture demands otherwise): \(context.rosterAppearanceLine)"
        return """
        You are steering ONE existing cast member of a LitScenes project.

        Return only JSON matching the provided GoalCastArticulationResponse schema, with exactly ONE member named "\(context.memberName)". Set casting_note to "".
        \(Self.goalCastIdentityContractBlock())

        The gesture:
        - \(gestureRule)\(pinsRule)\(priorRule)\(appearanceRule)
        - Return the COMPLETE identity (all fields) for the member; copy fields the gesture does not touch from the current identity unchanged.
        - List in changed_fields only the fields you meaningfully changed.
        - reference_media_ids: always [].

        Saved Goal (calibrate tone and strangeness to it):
        \(context.goalSummary)

        Current identity:
        \(context.currentIdentityJSON)
        """
    }

    private func aestheticDirectionShortlistPrompt(
        context: AestheticDirectionShortlistContext,
        validationError: String
    ) -> String {
        let validationSection = validationError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\nValidation fix required from the previous attempt:\n\(validationError)\n"
        return """
        You are choosing candidate AESTHETIC directions for LitScenes from a retrieved local catalog pool.

        Return only JSON matching the provided AestheticDirectionShortlistResponse schema.
        Choose exactly 20 unique catalog keys from the retrieved pool.
        Set each candidate's aesthetic_id field to the exact `key=` value from the retrieved pool when available.
        Use `id=` only when a row has no key.
        Do not invent keys or IDs.
        Prefer candidates that fit the intended visual treatment, respect archive truth, and keep goal-led stretch available when the archive is lopsided.
        Missing archive evidence is not a penalty by itself when the Goal clearly asks for a treatment or world cue.
        Avoid generic trend labels unless the evidence strongly supports them.
        Do not optimize for plot concepts or micro-premises.
        \(validationSection)
        Project:
        - project_id: \(context.projectId)
        - project_name: \(context.projectName)
        - generated_at: \(context.generatedAt)
        - index_version: \(context.indexVersion)

        Goal Brief:
        \(context.goalBriefSummary.isEmpty ? "No Goal Brief summary was provided." : context.goalBriefSummary)

        Evidence profile JSON:
        \(context.evidenceProfileJSON)

        Frame Context JSON:
        \(context.lensContextJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No Frame Context retrieval packet was provided." : context.lensContextJSON)

        Retrieved candidate pool:
        \(context.retrievedCandidateSummary)
        """
    }

    private func aestheticDirectionRankPrompt(
        context: AestheticDirectionRankContext,
        validationError: String
    ) -> String {
        let validationSection = validationError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "\nValidation fix required from the previous attempt:\n\(validationError)\n"
        return """
        You are ranking candidate AESTHETIC directions for LitScenes and writing operator-facing visual treatment specs.

        Return only JSON matching the provided AestheticDirectionRankResponse schema.
        Return exactly \(context.requestedPrimaryAestheticIds.count) directions in the exact requested order.
        These directions will become ranks \(context.rankStart)-\(context.rankStart + max(context.requestedPrimaryAestheticIds.count - 1, 0)).
        The primary_aesthetic_id values must exactly match this requested ordered batch: \(context.requestedPrimaryAestheticIds.joined(separator: ", ")).
        Use one unique primary_aesthetic_id per ranked direction, chosen only from the requested batch.
        supporting_aesthetic_ids must come from the same shortlist and must not repeat the primary ID.
        The requested ordered batch defines the primary anchors only; it is not a closed support pool.
        For supporting_aesthetic_ids, use the full Shortlist JSON and Shortlisted candidate details.
        Prefer supporting IDs outside the requested ordered batch whenever they add a coherent visual treatment.
        Do not make directions by rotating the same requested-batch aesthetics through primary/support roles.
        For diversity, treat primary_aesthetic_id plus supporting_aesthetic_ids as one unordered route set; avoid repeating the same route set across returned directions or existing hydrated directions.
        Only reuse another requested-batch aesthetic as support when it contributes a distinct visual treatment better than any non-requested shortlist option.
        support_status must be one of: archive_supported, goal_led_stretch, conflict_risk, exploratory.
        visual_summary must describe how the generations should land visually.
        treatment_notes must be concrete visual/treatment additions, not story beats.
        best_applied_to must name visual use surfaces.
        fit_reason must explain the visual fit briefly.
        evidence should name the strongest fit signals.
        gaps should name missing-but-desired support when relevant.
        conflicts should name real visual risks only.
        conflicts must not contain positive requirements, success criteria, workflow instructions, platform plans, plot guidance, shot lists, or task-control language.
        avoid_terms and Lens must_avoid fields downstream are literal prohibitions only, so write risks as concise visual cautions instead of "include/show/center/use/keep" instructions.
        Do not write titles, premises, lore, conspiracies, invasions, wars, coups, broadcasts, or character situations.
        Describe appearance, not plot.
        Use aesthetic language such as palette, lighting, texture, materials, finish, distortion, framing, polish, graphic treatment, and visual energy.
        Do not invent IDs outside the shortlist.
        \(validationSection)
        Project:
        - project_id: \(context.projectId)
        - project_name: \(context.projectName)
        - generated_at: \(context.generatedAt)
        - index_version: \(context.indexVersion)

        Goal Brief:
        \(context.goalBriefSummary.isEmpty ? "No Goal Brief summary was provided." : context.goalBriefSummary)

        Evidence profile JSON:
        \(context.evidenceProfileJSON)

        Frame Context JSON:
        \(context.lensContextJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No Frame Context retrieval packet was provided." : context.lensContextJSON)

        Existing hydrated directions:
        \(context.existingDirectionSummary.isEmpty ? "No directions have been hydrated yet." : context.existingDirectionSummary)

        Requested ordered batch:
        \(context.requestedPrimaryAestheticIds.enumerated().map { offset, id in "Rank \(context.rankStart + offset): \(id)" }.joined(separator: "\n"))

        Shortlist JSON:
        \(context.shortlistJSON)

        Shortlisted candidate details:
        \(context.shortlistedDetailSummary)
        """
    }

    private func projectGoalInterviewPrompt(context: ProjectGoalInterviewContext) -> String {
        """
        You are interviewing the user to define the durable Goal Brief for a LitScenes project.

        Return only JSON matching the provided ProjectGoalInterviewResponse schema.
        This is not the Aesthetic, shot list, storyboard, or final render plan.
        The Goal Brief should clarify what the project is trying to accomplish, for whom, and what success means.
        The Goal Brief must also include aesthetic_intent: early root-level style signals that are beginning to harden from the user's goal.
        aesthetic_intent is a search compass for later Aesthetic reference suggestions, not the accepted project Aesthetic.

        Requirements:
        - Return one concise assistant_message that responds naturally to the user's latest message.
        - Return a complete replacement brief every turn, not a partial patch.
        - Infer content_type when the evidence supports it; use null only when genuinely unclear.
        - Use content_type values only from: brand, product, service, personal_story, documentary, narrative, ambient, experimental.
        - Keep goal as the durable project outcome in one or two clear sentences.
        - Keep audience, desired_action, distribution_context, and story_promise concise.
        - Preserve archive truth. Do not invent people, places, brands, claims, events, or success metrics not provided by the user or media context.
        - Always fill aesthetic_intent with concise, grounded signals, even when confidence is low.
        - Keep aesthetic_intent emotional_targets, narrative_values, visual_mood, palette_hints, motif_hints, era_hints, energy, avoid, and open_style_questions distinct.
        - Use aesthetic_intent.open_style_questions for unresolved taste/style questions, and use brief.open_questions for outcome/audience/success questions.
        - Do not turn aesthetic_intent into a final style contract; avoid over-specific named aesthetics unless the user directly names them.
        - Fill story_setup_suggestions with project-specific Story Setup choices derived from the Goal. These are operator-facing options for the later Story tab, not a story outline.
        - story_setup_suggestions.pov_options should include concrete audience/brand/user roles when supported, such as customer, potential customer, founder, practitioner, guide, witness, or narrator.
        - story_setup_suggestions.engine_options should include concrete story mechanisms that fit the project, such as transformation, discovery, ritual use, before/after proof, customer problem-to-relief, or brand myth.
        - story_setup_suggestions.ending_options should include concrete ending moves that fit the project, such as invitation, sensory resolution, product promise, final image, customer decision, or ritual close.
        - Keep every story_setup_suggestions option label under 32 characters and every prompt_value under 80 characters.
        - Ask at most two open_questions. Prefer asking one useful next question over many.
        - If the brief is strong enough to continue to Aesthetic, use an empty open_questions array and confidence above 0.72.
        - Keep change_summary short and describe how the brief changed.
        - Do not discuss implementation details, schemas, or hidden system behavior in assistant_message.

        Project:
        - project_id: \(context.projectId)
        - project_name: \(context.projectName)
        - generated_at: \(context.generatedAt)

        Current Goal Brief JSON:
        \(context.currentBriefJSON.isEmpty ? "No current Goal Brief." : context.currentBriefJSON)

        Recent Goal conversation:
        \(context.recentMessagesSummary.isEmpty ? "No prior messages." : context.recentMessagesSummary)

        Selected media evidence for this turn:
        \(context.selectedMediaSummary.isEmpty ? "No selected media evidence." : context.selectedMediaSummary)

        Media archive context:
        \(context.mediaArchiveSummary.isEmpty ? "No indexed media yet." : context.mediaArchiveSummary)

        User message for this turn:
        \(context.userMessage)
        """
    }

    private func projectGoalInterviewV3Prompt(context: ProjectGoalInterviewV3Context) -> String {
        """
        You are interviewing the user to define the durable GOAL for a LitScenes project.

        Return only JSON matching the provided ProjectGoalInterviewResponseV3 schema.
        GOAL is the project intent contract. It answers what the project should do for the viewer, maker, brand, or story world.
        GOAL is not a platform plan, plot outline, chosen Lens, Storyline, Beat Board, shot list, or media generation plan.

        Requirements:
        - Return one concise assistant_message that responds naturally to the user's latest message.
        - Return a complete replacement brief every turn, not a patch.
        - Infer content_type when supported; use null only when genuinely unclear.
        - Use content_type values only from: brand, product, service, personal_story, documentary, narrative, ambient, experimental.
        - Keep goal as a durable outcome in one or two clear sentences.
        - Keep audience, desired_response, and viewer_experience concise.
        - Fill moodboard_articulation with 1-2 concise, human-readable sentences when Moodboard analyses are provided. It should summarize the recurring mood, visual forces, symbolic pull, and emotional direction implied by the user's curated reference archive.
        - Return moodboard_articulation as an empty string when no analyzed Moodboard assets are provided. Do not treat the absence of Moodboard evidence as a problem.
        - Do not copy the example wording from instructions or user chat into moodboard_articulation unless it is independently supported by the provided Moodboard analyses.
        - Keep success_criteria and constraints grounded in user/media evidence.
        - required_entities contains only mandatory people, organizations, characters, or places that the user explicitly says must appear or actively participate.
        - Every required_entities item must set required to true. Use [] when the user has not made an entity mandatory.
        - Do not add entities from image-only evidence, media archive summaries, Lens text, project name, or your own generated Goal fields.
        - Preserve existing required_entities from Current Goal V2 JSON unless the user explicitly changes the structured entity contract.
        - cast_updates is a per-character patch channel for the project's separately managed cast (the structured character identities shown beside the Goal). Emit cast_updates ONLY when the user's latest message explicitly asks to change, add, or remove a character; otherwise return [].
        - Each cast_updates patch sets ONLY the fields the user's message addressed; every other field must be "" (and strangeness null). Never re-emit untouched fields, and never adjust a character the user did not mention.
        - In each patch, user_authored_fields lists the emitted fields whose content restates the user's explicit words, as opposed to fields you composed to satisfy the request.
        - Use cast_updates action remove only when the user explicitly asked to remove that named character in this turn's message.
        - Each cast_updates patch lists reference_media_ids: the media_id values (exactly as given in the media sections) of images that show THIS character — attached this turn, named by the user, or captioned as clearly depicting them. Never media showing other people or no people; [] otherwise.
        - Patch field meanings: essence (one-line logline), public_function (recognizable role), desire (dominant desire in tension with the role), operating_rule (private rule), cost (what the rule costs), signature (recurring action/object/silhouette), formative_pressure (why), strangeness 0-1 (archetype-desire distance; 0 = an ordinary character, which is valid), visual_description (physical render description).
        - The unusual-character pattern behind those fields is a gap-filler, not a validator: never intensify, quirk-ify, or "complete" what the user stated; a plain character is a legitimate request.
        - If image inputs are attached to this request, treat them as concrete selected media evidence for the latest user turn.
        - Use attached images to clarify visible subject matter, mood, audience implications, and lens seeds, but do not identify private people by name.
        - Use lens_seed_summary and lens_seed_terms only as early visual Lens seeds. Do not choose an aesthetic or recipe.
        - Hydrate meaning_node_refs and aesthetic_term_refs only from the provided Meaning choice context.
        - Copy meaning node slug, kind, and name exactly from meaning_node_choices.
        - Copy aesthetic term facet_type, slug, and display_name exactly from aesthetic_term_choices.
        - Use refs only when they are supported by the Goal conversation, current brief, selected media evidence, moodboard analyses, or media archive context.
        - The MOODBOARD is the user's curated visual reference archive; treat the moodboard analyses below as first-class evidence of intended meaning and look.
        - Reason about the moodboard when hydrating refs: match recurring moods, palettes, motifs, settings, era cues, and possible meanings across moodboard assets against meaning_node_choices and aesthetic_term_choices, and prefer choices corroborated by several assets over choices seen once.
        - For a ref supported by moodboard analyses, set source to media, or goal_and_media when the conversation also supports it, and name the supporting asset filename(s) in evidence.
        - When moodboard evidence and the user's stated intent conflict, the stated intent wins; note the tension in assistant_message or open_questions instead of encoding it as refs.
        - Preserve existing refs from Current Goal V2 JSON only when they are still supported; remove unsupported refs.
        - Leave meaning_node_refs or aesthetic_term_refs empty when no provided choice fits.
        - Never invent slugs, facet types, names, display names, freeform meaning query terms, or natural-language meaning edges.
        - Keep meaning_node_refs to at most 18 and aesthetic_term_refs to at most 24.
        - Do not include platform, channel, distribution, plot, storyline, beat, scene, shot, or generation-provider instructions.
        - Do not include any readiness score or numeric certainty field.
        - Ask at most two open_questions. Prefer one useful next question.
        - Keep change_summary short and describe how the brief changed.
        - Do not discuss implementation details, schemas, or hidden system behavior in assistant_message.

        Project:
        - project_id: \(context.projectId)
        - project_name: \(context.projectName)
        - generated_at: \(context.generatedAt)

        Current Goal V2 JSON:
        \(context.currentBriefJSON.isEmpty ? "No current Goal." : context.currentBriefJSON)

        Recent Goal conversation:
        \(context.recentMessagesSummary.isEmpty ? "No prior messages." : context.recentMessagesSummary)

        Selected media evidence for this turn:
        \(context.selectedMediaSummary.isEmpty ? "No selected media evidence." : context.selectedMediaSummary)

        Media archive context:
        \(context.mediaArchiveSummary.isEmpty ? "No indexed media yet." : context.mediaArchiveSummary)

        Moodboard analyses (per-asset vision observations of the user's curated reference archive):
        \(context.moodboardAnalysisContext.isEmpty ? "No analyzed moodboard assets yet — the moodboard is optional; do not treat its absence as a gap." : context.moodboardAnalysisContext)

        Meaning choice context for exact GOAL ref hydration:
        \(context.meaningChoiceContextJSON.isEmpty ? "No static meaning choices available. Return empty meaning_node_refs and aesthetic_term_refs." : context.meaningChoiceContextJSON)

        Current cast (separately managed; change it only via cast_updates):
        \(context.currentCastSummary.isEmpty ? "No cast yet." : context.currentCastSummary)

        User message for this turn:
        \(context.userMessage)
        """
    }

    private func projectLensWorkbenchInterviewPrompt(context: ProjectLensWorkbenchInterviewContext) -> String {
        """
        You are helping the user edit one project-local visual Lens in the LitScenes FRAMES workbench.

        Return only JSON matching the provided ProjectLensWorkbenchInterviewResponseV1 schema.
        Return a full replacement LensBody proposal and a concise assistant_message. Do not return status, durable IDs, relation data, readiness booleans, scores, patches, or operations.

        Lens boundaries:
        - FRAMES are generated from one project-local visual Lens; they are visual interpretation documents, not plot, platform, Storyline, Beat Board, or Scene documents.
        - A Lens has a claim, visual summary, source style ingredients, resolved visual language, preserve/avoid rules, reference media, notes, open questions, readiness summary, and derived virtues.
        - Stock aesthetics can be source ingredients, but this is not a single chosen aesthetic.
        - Translate selected aesthetic styles into project-specific production language.
        - The user can use zero stock aesthetics if the custom visual language is hydrated.
        - The assistant may recommend improvements, but the client decides whether a Lens can be marked Ready.

        Resolved visual language:
        - Return resolved_visual_language as the user-facing production contract.
        - Return color_palette as 4 to 6 named swatches for the Lens detail UI.
        - Each color_palette item needs a short human-readable name, a valid #RRGGBB hex value, a role such as primary, support, accent, ground, or warning, and a short note.
        - color_palette is for visual display and palette continuity; palette_terms and resolved_visual_language.palette remain concise production-language phrases.
        - Style names and taxonomy labels are source inspiration, not production motifs.
        - Do not place source style names, catalog taxonomy labels, or style-family labels into palette, motif, material, composition, product-treatment, or avoid fields.
        - Every resolved field must contain complete, atomic, production-usable phrases.
        - Do not emit sentence fragments, article fragments, scraped description fragments, provenance commentary, search notes, or incomplete clauses.
        - Palette must express the palette selected for this project. Do not blindly copy generic colors from a source aesthetic when the project-specific treatment calls for a different palette.
        - Motifs must be visible things or repeatable visual devices, not abstract style names, definitions, sentence fragments, or source descriptions.
        - Materials must contain tangible materials or surfaces, not full directing paragraphs.
        - Composition must contain framing or spatial guidance. Deliverable types and use cases such as website landing visuals, product cards, social posts, or education cards belong in use-case metadata and not in composition.
        - must_preserve contains positive requirements.
        - must_avoid contains literal prohibitions only.
        - Tone boundaries and contrast guidance must not be placed in must_avoid unless they describe something that must literally not appear.
        - Do not write provenance phrases such as Archive supports, Shortlist notes, Candidate evidence, Search result, or The selected aesthetic says.
        - Return the resolved visual language itself.

        Requirements:
        - Modify only the selected \(context.targetKind) with id \(context.targetId).
        - Preserve useful existing user language unless the user asks to replace it.
        - Keep style_ingredients as named source visual ingredients, not rows of scoring or final production motif fields.
        - Use source_recipe_id/source_recipe_version only when they are already present in the current body or library context.
        - Keep source_recipe_id/source_recipe_version null for custom ingredients.
        - Do not include any readiness score or numeric certainty field.
        - Keep change_summary short and describe what changed.
        - Do not discuss implementation details, schemas, or hidden system behavior in assistant_message.

        Project:
        - project_id: \(context.projectId)
        - project_name: \(context.projectName)
        - generated_at: \(context.generatedAt)

        Goal summary:
        \(context.goalSummary.isEmpty ? "No Goal summary yet." : context.goalSummary)

        Current Lens body JSON:
        \(context.currentBodyJSON.isEmpty ? "No current body." : context.currentBodyJSON)

        Recent Lens conversation for this target:
        \(context.recentMessagesSummary.isEmpty ? "No prior messages." : context.recentMessagesSummary)

        Planned Frames summary:
        \(context.readyLensSetSummary.isEmpty ? "No planned Frames yet." : context.readyLensSetSummary)

        Aesthetic library context:
        \(context.aestheticLibraryContext.isEmpty ? "No catalog items selected for this turn." : context.aestheticLibraryContext)

        Selected media evidence for this turn:
        \(context.selectedMediaSummary.isEmpty ? "No selected media evidence." : context.selectedMediaSummary)

        User message for this turn:
        \(context.userMessage)
        """
    }

    private func encodedJSON<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONCoding.prettyEncoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func imagePromptEnrichmentPrompt(
        originalPrompt: String,
        provider: String,
        imageModel: String,
        providerInstructions: String
    ) -> String {
        """
        You rewrite image-generation prompts for a specific image provider and model. The rewritten prompt is sent directly to the image model with no other context, so it must be complete and self-contained.

        Return only JSON matching the provided ImagePromptEnrichmentResponse schema.

        Make this a precise, faithful, production-ready image prompt for \(provider) \(imageModel), which has these instructions for generating prompts with it:
        \(providerInstructions)

        Requirements:
        - Keep schema_version exactly "litscenes.image_prompt_enrichment_response.v0.1".
        - Keep provider exactly "\(provider)".
        - Keep model exactly "\(imageModel)".
        - Preserve the original subject, story world, stylistic intent, visual constraints, and avoid terms.
        - If the original prompt describes attached reference images and how to use them, or mandates a panel/grid layout, preserve those instructions completely — they are hard requirements, not flavor.
        - Never escalate saturation, density, or detail beyond what the original states. Stated restraint — negative space, quiet framing, muted passages, value structure — is a hard constraint to preserve, not empty space to fill.
        - Do not invent unsupported people, real events, locations, brands, text, logos, chronology, or source facts.
        - Do not mention any product, app, tool, or workflow names; the image model has no such context.
        - Do not include file names, identifiers, pixel dimensions, aspect ratios, output resolution, crop instructions, or metadata notation from the original prompt. Output shape is controlled by API parameters outside the prompt.
        - Make the image prompt concrete, visual, compositional, and production-ready.
        - Include framing, spatial layout, materials/textures, color, light, camera/rendering language, and mood when supported by the original prompt.
        - If the provider benefits from a negative prompt, put concise exclusions in negative_prompt; otherwise return an empty string.
        - The enhanced_prompt must be directly usable as the provider prompt.
        - Do not mention that you rewrote a prompt, and do not include markdown.

        Original prompt:
        \(originalPrompt)
        """
    }

    /// The subject-reference rewrite: reference images ride WITH this text and
    /// carry the subject's identity. The default rewrite is wrong here — it is
    /// told the text travels alone and must be self-contained, so it fills the
    /// silence by inventing a setting, and that invented setting competes with
    /// the very references it was supposed to describe.
    ///
    /// The correction is a demotion: the text stops being the whole picture and
    /// becomes the instruction for what to DO with the pictures already in hand.
    private func imagePromptSubjectReferencePrompt(
        originalPrompt: String,
        provider: String,
        imageModel: String,
        providerInstructions: String,
        referenceCount: Int
    ) -> String {
        let referencePhrase = referenceCount == 1
            ? "1 reference image"
            : "\(referenceCount) reference images"
        return """
        You rewrite image-generation prompts. The rewritten prompt is sent to \(provider) \(imageModel) TOGETHER WITH \(referencePhrase.uppercased()) that travel in the same request. The references are already visible to the image model. They — not your text — establish the subject, the characters, their identity and appearance, and the setting they are in.

        Return only JSON matching the provided ImagePromptEnrichmentResponse schema.

        Your job is to describe WHAT TO DO with those references, not to describe a scene from scratch. The original instruction is often short and relational ("the next frame", "the moment after this", "same subject, new angle"). Shortness is not a gap to fill — it is the whole instruction, and it depends on images you cannot see.

        Requirements:
        - Keep schema_version exactly "litscenes.image_prompt_enrichment_response.v0.1".
        - Keep provider exactly "\(provider)".
        - Keep model exactly "\(imageModel)".
        - NEVER invent a setting, location, backdrop, time of day, wardrobe, or cast that the original prompt did not state. If the original does not say where this happens, your rewrite must not say either — the references already answer it.
        - NEVER describe the subject's appearance, age, build, clothing, or ethnicity unless the original prompt states it. The references carry identity; competing description overrides them.
        - Preserve any relational or temporal instruction exactly: which reference is first, what precedes or follows, what continues, what changes. Order is meaning.
        - Preserve the original action, pose, camera move, and framing intent, and make only those concrete.
        - It is correct for the rewrite to stay short when the original is short. Do not pad toward a "complete" scene description.
        - Do not invent unsupported people, real events, locations, brands, text, logos, chronology, or source facts.
        - Do not mention any product, app, tool, or workflow names; the image model has no such context.
        - Do not include file names, identifiers, pixel dimensions, aspect ratios, output resolution, crop instructions, or metadata notation. Output shape is controlled by API parameters outside the prompt.
        - If the provider benefits from a negative prompt, put concise exclusions in negative_prompt; otherwise return an empty string.
        - The enhanced_prompt must be directly usable as the provider prompt.
        - Do not mention that you rewrote a prompt, and do not include markdown.

        Provider guidance for \(provider) \(imageModel):
        \(providerInstructions)

        Original prompt:
        \(originalPrompt)
        """
    }

    /// The style-reference rewrite: the image call attaches a style image that is the SOLE
    /// authority on rendering, so the text must carry pure subject matter. Any style word
    /// left in the text overrides the attached image and breaks the render.
    private func imagePromptStyleScrubPrompt(
        originalPrompt: String,
        provider: String,
        imageModel: String
    ) -> String {
        """
        You rewrite image-generation prompts. The rewritten prompt is sent to \(provider) \(imageModel) TOGETHER WITH AN ATTACHED STYLE IMAGE that alone controls the artistic style. Detailed style language in text overrides attached style images, so your single most important job is to remove every trace of art direction from the text.

        Return only JSON matching the provided ImagePromptEnrichmentResponse schema.

        Rewrite the original prompt below into a PURE SUBJECT-MATTER description:
        - KEEP: who and what is in the scene (people, creatures, objects, their physical features — species, build, age, clothing, gear), what they are doing, where everything is relative to everything else, the environment's geography and contents, weather, and time of day stated as plain fact.
        - KEEP: any instructions about attached reference images, layout mandates, and "no readable text" rules — verbatim in meaning.
        - REMOVE: pixel dimensions, aspect ratios, output resolution, and crop instructions. Output shape is controlled by API parameters outside the prompt.
        - REMOVE COMPLETELY: every color name and palette word, every rendering-technique or medium word (ink, neon, halftone, painterly, photographic, illustration, contour, posterized, splatter, grit, and their kin), lighting-character adjectives (rim light, glare, glow colors), texture treatments, mood-as-style phrasing, art-movement references, and any "visual treatment" or "visual style" passage. Do not replace them with softer synonyms; delete them.
        - Do not add any new style, color, light, or mood language of your own. If the original says "cyan glare spills across the table", write "light spills across the table" or drop it.
        - Composition facts (camera angle, framing, negative space, what is near or far) are subject matter — keep them, stripped of style adjectives.
        - Do not invent unsupported people, real events, locations, brands, text, logos, chronology, or source facts.
        - Do not mention any product, app, tool, or workflow names; do not include file names, identifiers, pixel dimensions, aspect ratios, output resolution, crop instructions, or metadata notation.
        - Keep schema_version exactly "litscenes.image_prompt_enrichment_response.v0.1", provider exactly "\(provider)", model exactly "\(imageModel)".
        - Return an empty negative_prompt.
        - Do not mention that you rewrote a prompt, and do not include markdown.

        Original prompt:
        \(originalPrompt)
        """
    }

    private func storySignalSetPrompt(context: StorySignalSetGenerationContext) -> String {
        """
        You are deriving Story Signals for a LitScenes project from current, fingerprinted Story context.

        Return only JSON matching the provided StorySignalSet schema.
        This is not a beat board, route list, shot list, render plan, or canonical Meaning Graph.
        It is a compact set of friendly, reusable Story Signals for current enabled media and current Goal/Aesthetic context.

        Requirements:
        - Keep schema_version exactly "litscenes.story_signal_set.v0.2".
        - Keep project_id exactly "\(context.projectId)".
        - Keep signal_set_id exactly "\(context.signalSetId)".
        - Keep scope exactly "\(context.scope)".
        - Copy input_fingerprint exactly:
        \(encodedJSON(context.inputFingerprint))
        - Use generated_at and updated_at exactly "\(context.generatedAt)".
        - Set artifact_status to "fresh".
        - Set legacy_source_path and legacy_raw_scope to empty strings.
        - Preserve archive truth. Do not invent people, injuries, places, chronology, causality, claims, or real events not supported by the context.
        - Treat Aesthetic narrative cues as event/turn guidance and Aesthetic presentation cues as visual/prompt treatment guidance.
        - Keep friendly_chips readable and non-academic, e.g. "The screen sees what people cannot".
        - Put only media ids from selected_media_ids into evidence_media_ids.
        - Use empty arrays where the current context does not support a category.

        Project:
        - project_id: \(context.projectId)
        - name: \(context.projectName)
        - selected_media_ids: \(context.selectedMediaIds.joined(separator: ", "))

        Current Story prompt packet:
        \(context.promptPacketJSON)
        """
    }

    private func storyDirectionSetPrompt(context: StoryDirectionSetGenerationContext) -> String {
        """
        You are generating Storyline cards for a LitScenes project.

        Return only JSON matching the provided StoryDirectionSet schema.
        The output is a set of storyline cards, not a beat board.
        Generate 6-8 internal candidates, then select exactly 3 public Storylines.

        Requirements:
        - Keep schema_version exactly "litscenes.story_direction_set.v0.1".
        - Keep project_id exactly "\(context.projectId)".
        - Keep direction_set_id exactly "\(context.directionSetId)".
        - Copy input_fingerprint exactly:
        \(encodedJSON(context.inputFingerprint))
        - Copy story_setup_snapshot exactly from the prompt packet.
        - Use generated_at and updated_at exactly "\(context.generatedAt)".
        - Set generator to "openai".
        - Leave model and response_id empty; the app will stamp them.
        - Set artifact_status to "fresh".
        - direction_id must be stable-looking ids like dir_<short_slug_or_hash>; do not use lane names as ids.
        - Set enabled to true on generated public Storylines and candidates unless context explicitly says to disable.
        - Public storylines must include the strongest Recommended storyline and one Bolder/Stranger storyline.
        - If commercial_pressure is "none", do not include a default Commercial public Storyline.
        - If commercial_pressure is creator-friendly or stronger, include a Commercial / Creator-Friendly public Storyline when it is useful and still story-first.
        - The third public Storyline can be wildcard, commercial, mythic, or experimental depending on setup.
        - A card should feel like a complete storyline route, not a beat list.
        - Separate aesthetic_use.narrative from aesthetic_use.presentation.
        - Avoid generic synopsis language.

        Current Story prompt packet:
        \(context.promptPacketJSON)
        """
    }

    private func storylineCreationInterviewPrompt(context: StorylineCreationInterviewContext) -> String {
        """
        You are helping the operator create one additional Storyline for a LitScenes project.

        Return only JSON matching the provided StorylineCreationInterviewResponse schema.
        This is a conversational intake turn, not Storyline generation.
        The draft should capture a single storyline route the operator may later generate.

        Requirements:
        - Return one concise assistant_message that responds naturally to the user's latest message.
        - Be informative about whether there is enough information to proceed.
        - Ask at most two useful open_questions when the storyline is still ambiguous.
        - Set is_ready_to_generate to true only when storyline_intent is specific enough to generate one Storyline card.
        - If ready, use an empty open_questions array and confidence above 0.65.
        - Preserve archive truth. Do not invent people, brands, events, claims, or media evidence.
        - Use the per-storyline Draft Setup as steering for this storyline only.
        - Avoid duplicating existing Storylines; clarify the intended distinction when needed.
        - Keep storyline_title short. Use "Untitled Storyline" only when the title is genuinely unclear.
        - Keep storyline_intent to one clear paragraph describing the route, constraints, and desired difference from existing storylines.
        - Do not discuss implementation details, schemas, or hidden system behavior in assistant_message.

        Project:
        - project_id: \(context.projectId)
        - project_name: \(context.projectName)
        - generated_at: \(context.generatedAt)

        Current Create Storyline Draft:
        \(context.currentDraftJSON.isEmpty ? "No current Create Storyline draft." : context.currentDraftJSON)

        Recent Create Storyline conversation:
        \(context.recentMessagesSummary.isEmpty ? "No prior Create Storyline messages." : context.recentMessagesSummary)

        Per-storyline Draft Setup:
        \(context.draftSetupJSON.isEmpty ? "No per-storyline setup." : context.draftSetupJSON)

        Existing Storylines:
        \(context.existingDirectionsJSON.isEmpty ? "No existing Storylines." : context.existingDirectionsJSON)

        Current Story prompt packet:
        \(context.promptPacketJSON)

        User message for this turn:
        \(context.userMessage)
        """
    }

    private func storySingleStorylinePrompt(context: StorySingleStorylineGenerationContext) -> String {
        """
        You are generating exactly one additional Storyline card for a LitScenes project.

        Return only JSON matching the provided StorySingleStorylineResponse schema.
        The output is one Story Direction card, not a beat board and not a three-storyline set.

        Requirements:
        - Keep schema_version exactly "litscenes.story_single_storyline_response.v0.1".
        - Create exactly one direction object.
        - Set direction.direction_id exactly "\(context.expectedDirectionId)".
        - Set direction.enabled to true.
        - Choose the best lane for this one storyline: recommended, bolder, commercial, or wildcard.
        - Do not duplicate any existing Storyline title, premise, story_engine, or meaning_moves.
        - The card should feel like a complete storyline route, not a beat list.
        - Separate aesthetic_use.narrative from aesthetic_use.presentation.
        - Base the storyline on the Create Storyline Draft and per-storyline Draft Setup.
        - Preserve archive truth. Do not invent concrete people, brands, events, claims, or media evidence.
        - Include three concrete beat previews, but do not expand into a full board.
        - Keep all score_debug values between 0 and 1 and make final_score reflect overall fitness.
        - Use validation_warnings as an empty array unless there is a concrete weakness the operator should see.
        - Avoid generic synopsis language.

        Project:
        - project_id: \(context.projectId)
        - project_name: \(context.projectName)
        - generated_at: \(context.generatedAt)

        Copy input_fingerprint context exactly for reasoning:
        \(encodedJSON(context.inputFingerprint))

        Create Storyline Draft:
        \(context.draftJSON.isEmpty ? "No draft was provided." : context.draftJSON)

        Per-storyline Draft Setup:
        \(context.draftSetupJSON.isEmpty ? "No per-storyline setup." : context.draftSetupJSON)

        Existing Storylines:
        \(context.existingDirectionsJSON.isEmpty ? "No existing Storylines." : context.existingDirectionsJSON)

        Current Story prompt packet:
        \(context.promptPacketJSON)
        """
    }

    private func storyBeatBoardPrompt(context: StoryBeatBoardGenerationContext) -> String {
        """
        You are expanding one selected Story Direction into a prompt-ready Beat Board.

        Return only JSON matching the provided StoryBeatBoard schema.
        This is not a literary outline. Each beat must be a concrete event with a visible moment and structured generation brief.

        Requirements:
        - Keep schema_version exactly "litscenes.story_beat_board.v0.2".
        - Keep project_id exactly "\(context.projectId)".
        - Keep beat_board_id exactly "\(context.beatBoardId)".
        - Keep parent_direction_set_id exactly "\(context.parentDirectionSetId)".
        - Keep parent_direction_id exactly "\(context.parentDirectionId)".
        - Keep primary_direction_id exactly "\(context.parentDirectionId)".
        - Keep source_direction_ids exactly:
        \(encodedJSON(context.sourceDirectionIds))
        - Keep story_setup_hash exactly "\(context.storySetupHash)".
        - Keep aesthetic_recipe_version exactly "\(context.aestheticRecipeVersion)".
        - Set is_active_draft to true.
        - Copy input_fingerprint exactly:
        \(encodedJSON(context.inputFingerprint))
        - Use generated_at and updated_at exactly "\(context.generatedAt)".
        - Set generator to "openai".
        - Leave model and response_id empty; the app will stamp them.
        - Set artifact_status to "fresh".
        - Generate 5-7 beats.
        - Every beat needs event, visual_moment, emotional_turn, meaning_move, story_function, prompt_ready_line, and generation_brief.
        - generation_brief must be usable by downstream image/video/audio layers.
        - Include source_media_ids, avoid_media_ids, reference_media_ids, media_anchors, manual_edit_fields, revision_history as arrays on every beat; use empty arrays when none are explicit.
        - Set is_deleted to false and deleted_at to an empty string on every generated beat.
        - Store graph-like refs using local/story-signal ids before canonical graph wiring exists; do not invent canonical ids.
        - Include origin disclosure for each beat.
        - Avoid direct CTA language unless commercial pressure clearly supports it.
        - Do not use generic filler such as "the protagonist confronts the truth".
        - Prefer observable beats such as "the phone camera shows a reflection the room does not contain".

        Selected Story Direction:
        \(context.selectedDirectionJSON)

        Current Story prompt packet:
        \(context.promptPacketJSON)
        """
    }

    private func storyBeatBoardEditPrompt(context: StoryBeatBoardEditContext) -> String {
        """
        You are editing a LitScenes Beat Board while preserving sequence continuity.

        Return only JSON matching the provided StoryBeatBoard schema.
        This is a full replacement Beat Board document, not prose commentary.

        Requirements:
        - Keep schema_version exactly "litscenes.story_beat_board.v0.2".
        - Keep project_id exactly "\(context.projectId)".
        - Keep beat_board_id exactly "\(context.outputBeatBoardId)".
        - Use generated_at and updated_at exactly "\(context.generatedAt)".
        - Set is_active_draft to true and artifact_status to "fresh".
        - Preserve the board spine, story engine, source direction ids, story setup hash, aesthetic recipe version, and input fingerprint unless the active board JSON explicitly makes them empty.
        - Preserve all locked beats exactly: beat_id, title, content fields, anchors, generation_brief, manual_edit_fields, and revision_history.
        - Do not contradict locked beats or neighboring beats.
        - Every changed beat must stay concrete, visual, prompt-ready, and sequence-aware.
        - Every beat needs event, visual_moment, emotional_turn, meaning_move, story_function, prompt_ready_line, generation_brief, and media anchor arrays.
        - Keep source_media_ids, avoid_media_ids, reference_media_ids, media_anchors, manual_edit_fields, and revision_history arrays on every beat.
        - Set is_deleted and deleted_at according to the active board; do not restore deleted beats unless the operation explicitly requires an insert/split.
        - Avoid generic filler such as "the protagonist confronts the truth".

        Operation:
        - operation: \(context.operation)
        - selected_beat_id: \(context.selectedBeatId.isEmpty ? "none" : context.selectedBeatId)
        - intent: \(context.intent.isEmpty ? "Preserve the board while improving the requested beat operation." : context.intent)

        Source Storylines:
        \(context.sourceDirectionsJSON.isEmpty ? "No source Storyline JSON was provided." : context.sourceDirectionsJSON)

        Current Story prompt packet:
        \(context.promptPacketJSON)

        Active Beat Board:
        \(context.activeBoardJSON)
        """
    }

    private func projectArchiveMeaningPrompt(context: ProjectStoryGenerationContext) -> String {
        """
        You are deriving Story Signals for a LitScenes project from local archive context.

        Return only JSON matching the provided ProjectArchiveMeaningGraph schema.
        This is not a beat sheet, shot list, marketing plan, or render plan.
        It is a compact meaning graph for enabled project media.

        Requirements:
        - Keep project_id exactly "\(context.projectId)".
        - Keep scope exactly "\(context.scope.rawValue)".
        - Use generated_at and updated_at exactly "\(context.generatedAt)".
        - Preserve archive truth. Do not invent people, injuries, places, chronology, causality, claims, or events not supported by the context.
        - Treat the accepted Aesthetic as the creative lens, not as permission to fabricate facts.
        - Extract reusable motifs, value tensions, moods, scene forces, constraints, and implications that could guide later story beats.
        - Keep every phrase concise and readable in a UI.
        - Put only media ids from selected_media_ids into evidence_media_ids.
        - Use empty arrays where the context does not support a category.
        - Set confidence_0_to_1 according to how much the enabled media and notes support the signals.

        Request description:
        derive_project_archive_meaning -> ProjectArchiveMeaningGraph: Extracts reusable archive-native motifs, tensions, moods, scene forces, constraints, and implications from enabled project media.

        Project:
        - project_id: \(context.projectId)
        - name: \(context.projectName)
        - scope: \(context.scope.rawValue)
        - selected_media_ids: \(context.selectedMediaIds.joined(separator: ", "))

        Accepted Aesthetic:
        \(context.aestheticJSON.isEmpty ? "No accepted Aesthetic JSON was provided." : context.aestheticJSON)

        Story World:
        - summary: \(context.storyWorldSummary.isEmpty ? "Not stated." : context.storyWorldSummary)
        - genre: \(context.storyGenre.isEmpty ? "Not stated." : context.storyGenre)
        - style/lens: \(context.storyStyle.isEmpty ? "Not stated." : context.storyStyle)

        Source Context:
        \(context.sourceContextSummary.isEmpty ? "No source context records yet." : context.sourceContextSummary)

        Enabled Media:
        \(context.mediaScopeSummary.isEmpty ? "No enabled media summaries were provided." : context.mediaScopeSummary)
        """
    }

    private func storyBeatSheetPrompt(context: StoryBeatGenerationContext) -> String {
        """
        You are drafting Story Beats for a LitScenes project.

        Return only JSON matching the provided StoryBeatSheet schema.
        This is not a shot list, render plan, media assignment plan, or final script.
        It is a compact sequence of visual story beats grounded in the accepted Aesthetic and Story Signals.

        Requirements:
        - Keep project_id exactly "\(context.projectId)".
        - Keep scope exactly "\(context.scope.rawValue)".
        - Use generated_at and updated_at exactly "\(context.generatedAt)".
        - Return 3-7 beats.
        - Each beat must be actionable, visual, and useful for later media curation.
        - Do not invent unsupported facts, characters, places, dates, property damage, rescues, injuries, or outcomes.
        - Use support_status honestly: strong when the archive signals clearly support it, possible when plausible but not yet proved, weak when thin, unsupported only for an intentional gap.
        - Use meaning_refs for exact phrases from the Story Signals, not invented ontology ids.
        - Use constraints for beat-specific cautions that should protect truth, taste, or source limits.
        - Keep titles short and readable in a card UI.

        Request description:
        draft_story_beats -> StoryBeatSheet: Creates 3-7 visual, actionable story beats grounded in the accepted Aesthetic and current Story Signals.

        Project:
        - project_id: \(context.projectId)
        - name: \(context.projectName)
        - scope: \(context.scope.rawValue)

        Accepted Aesthetic:
        \(context.aestheticJSON.isEmpty ? "No accepted Aesthetic JSON was provided." : context.aestheticJSON)

        Story Signals:
        \(context.archiveMeaningJSON.isEmpty ? "No Story Signals JSON was provided." : context.archiveMeaningJSON)

        Story World:
        - summary: \(context.storyWorldSummary.isEmpty ? "Not stated." : context.storyWorldSummary)
        - genre: \(context.storyGenre.isEmpty ? "Not stated." : context.storyGenre)
        - style/lens: \(context.storyStyle.isEmpty ? "Not stated." : context.storyStyle)

        Source Context:
        \(context.sourceContextSummary.isEmpty ? "No source context records yet." : context.sourceContextSummary)

        Enabled Media:
        \(context.mediaScopeSummary.isEmpty ? "No enabled media summaries were provided." : context.mediaScopeSummary)
        """
    }

    private func storyAudioTrackPrompt(context: StoryAudioTrackGenerationContext) -> String {
        """
        You are drafting the first production audio line for a LitScenes Story workspace.

        Return only JSON matching the provided StoryAudioTrackDraft schema.
        This is not a final mix, video render, beat sheet, or full narration script.
        It is a compact spec for one short voice phrase over one punchy non-vocal beat bed.

        Requirements:
        - Keep schema_version exactly "litscenes.story_audio_track_draft.v0.1".
        - Keep project_id exactly "\(context.projectId)".
        - Keep track_id exactly "\(context.trackId)".
        - Keep target_beat_id exactly "\(context.targetBeatId)".
        - Copy source_beat_ids exactly: \(context.sourceBeatIds.isEmpty ? "[]" : context.sourceBeatIds.joined(separator: ", ")).
        - Use generated_at and updated_at exactly "\(context.generatedAt)".
        - Make voice_text a single spoken phrase designed to last \(context.voiceDurationRange), with no stage directions.
        - Make beat_prompt a direct ElevenLabs Sound Generation prompt for a \(String(format: "%.0f", context.durationSeconds))-second loopable, punchy, non-vocal bed.
        - The beat bed must contain no speech, no lyrics, and no copyrighted artist or song references.
        - Keep the audio grounded in the accepted Aesthetic, Goal, Story World, Source Context, and enabled media summaries.
        - Treat Operator Audio Direction as the top creative modifier when present, while preserving factual constraints.
        - Do not invent unsupported facts, people, events, injuries, places, chronology, or claims.
        - Prefer crisp editorial energy over generic trailer language.
        - Keep title, tags, and mix_notes readable in a compact Desktop card.

        Request description:
        draft_story_audio_track -> StoryAudioTrackDraft: Creates a short voice line and loopable punchy beat-bed prompt for direct Desktop audio generation.

        Project:
        - project_id: \(context.projectId)
        - name: \(context.projectName)
        - track_id: \(context.trackId)
        - target_beat_id: \(context.targetBeatId.isEmpty ? "none" : context.targetBeatId)
        - source_beat_ids: \(context.sourceBeatIds.isEmpty ? "none" : context.sourceBeatIds.joined(separator: ", "))
        - duration_seconds: \(String(format: "%.1f", context.durationSeconds))

        Goal Brief:
        \(context.goalBriefSummary.isEmpty ? "No Goal Brief summary was provided." : context.goalBriefSummary)

        Operator Audio Direction:
        \(context.operatorDirection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No extra operator direction was provided." : context.operatorDirection)

        Accepted Aesthetic:
        \(context.aestheticJSON.isEmpty ? "No accepted Aesthetic JSON was provided." : context.aestheticJSON)

        Active Beat Board:
        \(context.beatBoardJSON.isEmpty ? "No active Beat Board JSON was provided." : context.beatBoardJSON)

        Story World:
        - summary: \(context.storyWorldSummary.isEmpty ? "Not stated." : context.storyWorldSummary)
        - genre: \(context.storyGenre.isEmpty ? "Not stated." : context.storyGenre)
        - style/lens: \(context.storyStyle.isEmpty ? "Not stated." : context.storyStyle)

        Source Context:
        \(context.sourceContextSummary.isEmpty ? "No source context records yet." : context.sourceContextSummary)

        Enabled Media:
        \(context.mediaScopeSummary.isEmpty ? "No enabled media summaries were provided." : context.mediaScopeSummary)
        """
    }
}
