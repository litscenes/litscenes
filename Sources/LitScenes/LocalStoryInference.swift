import Foundation
import MeaningGraphCore

// Graph resolution and creative orchestration always run on the Mac. This
// mode identifies only who supplies and pays for the text provider request.
enum StoryInferenceMode: String, CaseIterable, Identifiable, Sendable {
    case direct
    case hosted
    var id: String { rawValue }
    var label: String { self == .direct ? "Your key · local graph" : "Go credits · local graph" }
    static func resolved() -> StoryInferenceMode {
        ProviderBilling.source(for: .story) == .go ? .hosted : .direct
    }
}

struct StoryInferenceService {
    private var client: LocalStoryInferenceClient

    static func fromEnvironment(for project: ProjectRecord? = nil, projectLibrary: ProjectLibrary = ProjectLibrary()) throws -> StoryInferenceService {
        var client = try LocalStoryInferenceClient.fromEnvironment()
        if let project { client.graphSelection = try MeaningGraphProjectStore.load(project: project, library: projectLibrary) }
        return Self(client: client)
    }

    static var isConfigured: Bool { ProviderBilling.isConfigured(.story) }

    func resolve(_ payload: LensContextResolveRequest) async throws -> LensContextResolveResponse {
        try await client.resolve(payload)
    }

    func generateSceneStorySet(_ payload: SceneStoryGenerateRequest) async throws -> SceneStoryGenerateResult {
        try await client.generateSceneStorySet(payload)
    }

    func generateFrameForms(_ payload: FrameFormsGenerateRequest) async throws -> FrameFormsGenerateResponse {
        try await client.generateFrameForms(payload)
    }
}

// MARK: - OpenAI-compatible text endpoint settings

/// Optional OpenAI-compatible base URL (OpenRouter-style services, local
/// gateways). Applies to every text/image call constructed from the
/// environment. Accepts a bare origin or an ".../v1" base.
enum OpenAITextEndpointSettings {
    static let baseURLKeys = ["OPENAI_BASE_URL", "LITSCENES_OPENAI_BASE_URL"]
    static let storyModelKey = "LITSCENES_STORY_MODEL"
    static let frameFormModelKey = "LITSCENES_FRAME_FORM_MODEL"
    static let defaultStoryModel = "gpt-5.5"

    /// A configured base URL either resolves or the call fails loudly — a
    /// malformed value must never silently fall back to api.openai.com, and
    /// plaintext HTTP is loopback-only (local gateways), never a remote host.
    static func baseURL() throws -> URL? {
        let raw = LitScenesCredentialStore()
            .resolvedCredentialValue(forKeys: baseURLKeys)
            .trimmed
        guard !raw.isEmpty else { return nil }
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host else {
            throw ScreenGraphError.credentials(
                "OPENAI_BASE_URL is not a valid HTTP(S) URL: \(raw). Fix or remove it in Settings."
            )
        }
        if scheme == "http" {
            let loopback = ["localhost", "127.0.0.1", "::1", "[::1]"]
            guard loopback.contains(host.lowercased()) else {
                throw ScreenGraphError.credentials(
                    "OPENAI_BASE_URL uses plaintext HTTP for a remote host (\(host)). Use HTTPS, or HTTP only for localhost gateways."
                )
            }
        }
        return url
    }

    /// "<base>/v1/<path>" for a bare origin, "<base>/<path>" when the base
    /// already ends in /v1.
    static func endpoint(base: URL, path: String) -> URL {
        var root = base.absoluteString
        while root.hasSuffix("/") {
            root = String(root.dropLast())
        }
        let prefix = root.hasSuffix("/v1") ? root : root + "/v1"
        return URL(string: "\(prefix)/\(path)") ?? base
    }

    static func responsesURL() throws -> URL {
        if let base = try baseURL() {
            return endpoint(base: base, path: "responses")
        }
        return URL(string: "https://api.openai.com/v1/responses")!
    }

    static func storyModel() -> String {
        let value = LitScenesCredentialStore().resolvedCredentialValue(forKey: storyModelKey).trimmed
        return value.isEmpty ? defaultStoryModel : value
    }

    static func frameFormModel() -> String {
        let value = LitScenesCredentialStore().resolvedCredentialValue(forKey: frameFormModelKey).trimmed
        return value.isEmpty ? storyModel() : value
    }
}

// MARK: - Local graph vocabulary projection

struct LocalMeaningIndexNode: Sendable, Hashable {
    var slug: String
    var kind: String
    var name: String
    var definition: String
    var status: String
    var tags: [String]
    var id: String = ""
    var abstractionLevel: String = ""
    var positiveExpression: String = ""
    var negativeExpression: String = ""
    var boundary: String = ""
    var confidenceScore: Double = 0
    var reuseScore: Double = 0
    var edgeDegree: Int = 0
}

extension LocalMeaningIndexNode {
    init(record: GraphRecord) {
        self.init(slug: record.text("slug"), kind: record.text("kind"), name: record.text("name"),
            definition: record.text("definition"), status: record.text("status"), tags: record.strings("tags"),
            id: record.text("id"), abstractionLevel: record.text("abstraction_level"),
            positiveExpression: record.text("positive_expression"), negativeExpression: record.text("negative_expression"),
            boundary: record.text("boundary"), confidenceScore: record.number("confidence_score"),
            reuseScore: record.number("reuse_score"), edgeDegree: Int(record.number("edge_degree")))
    }
}

struct LocalMeaningIndex: Sendable {
    let nodes: [LocalMeaningIndexNode]
    private let nodesBySlug: [String: LocalMeaningIndexNode]

    init(nodes: [LocalMeaningIndexNode]) {
        self.nodes = nodes
        nodesBySlug = Dictionary(nodes.map { ($0.slug.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func loadBundled() throws -> LocalMeaningIndex {
        let graph = try MeaningGraphSnapshot.open(packagedResourceURL(named: "MeaningGraph/graph", extension: "sqlite"))
        return LocalMeaningIndex(nodes: try graph.records("nodes").map(LocalMeaningIndexNode.init(record:)))
    }

    func node(forSlug slug: String) -> LocalMeaningIndexNode? { nodesBySlug[slug.trimmed.lowercased()] }
}

// MARK: - Direct client

struct LocalStoryInferenceClient: Sendable {
    var apiKey: String
    var responsesURL: URL
    var storyModel: String
    var frameFormModel: String
    var graphSelection: ProjectMeaningGraphSelection? = nil
    var runId = WorkflowContext.current?.jobId ?? UUID().uuidString.lowercased()
    var endpointConfigurationError: String? = nil
    private static let localUserID = "local"

    static func fromEnvironment() throws -> LocalStoryInferenceClient {
        let managed = ProviderBilling.source(for: .story) == .go
        let key = ProviderBilling.credential(for: .story)
        var url = URL(string: "https://api.openai.com/v1/responses")!
        var endpointError: String?
        if !managed {
            do { url = try OpenAITextEndpointSettings.responsesURL() }
            catch { endpointError = error.localizedDescription }
        }
        return LocalStoryInferenceClient(apiKey: key, responsesURL: url,
            storyModel: managed ? OpenAITextEndpointSettings.defaultStoryModel : OpenAITextEndpointSettings.storyModel(),
            frameFormModel: managed ? OpenAITextEndpointSettings.defaultStoryModel : OpenAITextEndpointSettings.frameFormModel(),
            endpointConfigurationError: endpointError)
    }

    // MARK: Local graph context

    func resolve(_ payload: LensContextResolveRequest) async throws -> LensContextResolveResponse {
        let started = Date()
        let traceId = "itrace_\(UUID().uuidString.lowercased())"
        var request = URLRequest(url: URL(string: "litscenes-local://meaning/resolve")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONCoding.encoder.encode(payload)
        var metadata = WorkflowHTTP.scoped(InferenceTraceRequestMetadata(provider: "local", apiFamily: "meaning_graph", operation: "resolve",
            projectId: payload.projectId, runId: runId, traceGroupId: runId,
            workflowName: "story", workflowStep: "meaning_resolve", artifactType: "lens_context", artifactId: payload.goalFingerprint,
            requestBodyFormat: "application/json", responseBodyFormatHint: "application/json"))
        do {
            let graph = try await MeaningGraphRuntime.shared.snapshot(graphSelection)
            var response = try await Task.detached { try LocalMeaningGraphResolver.resolve(payload, graph: graph) }.value
            let catalog = try await CatalogManifestRuntime.shared.loadSnapshot()
            response.styleCandidates = LocalStyleCandidateBuilder.candidates(from: catalog.styleBrowse,
                styleTermRefs: payload.styleTermRefs, limit: min(max(payload.limits.styleCandidates, 0), 80))
            try Task.checkCancellation()
            response.graphTraceId = traceId
            metadata.requestTextJSON = inferenceTraceJSONString([
                "graph_provenance": try JSONSerialization.jsonObject(with: GraphCoding.data(graph.provenance)),
                "request": try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(payload))])
            let body = try JSONCoding.encoder.encode(response)
            metadata.responseTextJSON = String(decoding: body, as: UTF8.self)
            _ = await InferenceTraceStore.shared.record(request: request, metadata: metadata,
                response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "LOCAL", headerFields: nil),
                responseBody: body, latencyMs: Int(Date().timeIntervalSince(started) * 1000), traceId: traceId)
            await InferenceTraceStore.shared.enrich(traceId: traceId, parsedOutputJSON: String(decoding: body, as: UTF8.self))
            return response
        } catch {
            _ = await InferenceTraceStore.shared.record(request: request, metadata: metadata, response: nil,
                responseBody: nil, latencyMs: Int(Date().timeIntervalSince(started) * 1000), error: error, traceId: traceId)
            throw error
        }
    }

    // MARK: SceneStory generation (direct)

    func generateSceneStorySet(_ payload: SceneStoryGenerateRequest) async throws -> SceneStoryGenerateResult {
        let generatedAt = DateFormats.now()
        let request = normalizedLocalSceneStoryRequest(payload)
        let graph = try await MeaningGraphRuntime.shared.snapshot(graphSelection)
        if request.wire.lensContext.graphProvenance?.effectiveHash != graph.provenance.effectiveHash {
            request.wire.lensContext = try await resolve(LensContextResolveRequest(projectId: payload.projectId,
                goalFingerprint: payload.goalFingerprint, meaningNodeRefs: payload.goal.meaningNodeRefs,
                aestheticTermRefs: payload.goal.aestheticTermRefs, styleTermRefs: payload.goal.styleTermRefs,
                limits: LensContextResolveLimits()))
        }
        var provenance = SceneStoryGenerationProvenance(
            lambdaPromptVersion: "litscenes.scene_story_prompt.v0.7-local",
            desktopInstructionVersion: "litscenes.scene_story_slot_instructions.v0.2",
            validatorVersion: "litscenes.scene_story_validator.v0.3-local",
            dialoguePolicyVersion: "litscenes.dialogue_policy.v0.1"
        )
        provenance.graphProvenance = graph.provenance
        let requestId = "local_\(UUID().uuidString.lowercased())"

        do {
            let (document, attempt) = try await sceneStoryAttempt(
                request: request, generatedAt: generatedAt, purpose: "creative_generation"
            )
            provenance.openaiAttempts.append(attempt)
            provenance.warnings.append(contentsOf: document.warnings)
            return SceneStoryGenerateResult(document: document, provenance: provenance, hostedRequestId: requestId)
        } catch let error as LocalStoryInferenceValidationError {
            if let attempt = error.attempt { provenance.openaiAttempts.append(attempt) }
            let retry = request.withRetryCorrection(
                "The prior candidate failed structural validation: \(error.message). Regenerate the full Story and satisfy task_controls exactly."
            )
            let (document, attempt) = try await sceneStoryAttempt(
                request: retry, generatedAt: generatedAt, purpose: "structural_regeneration"
            )
            provenance.openaiAttempts.append(attempt)
            provenance.warnings.append(contentsOf: document.warnings)
            return SceneStoryGenerateResult(document: document, provenance: provenance, hostedRequestId: requestId)
        }
    }

    private func sceneStoryAttempt(
        request: LocalSceneStoryRequest,
        generatedAt: String,
        purpose: String
    ) async throws -> (SceneStorySetDocument, SceneStoryOpenAIAttemptProvenance) {
        let startedAt = DateFormats.now()
        let schema = LocalStoryInferenceSchemas.sceneStorySet(
            request: request, userId: Self.localUserID, generatedAt: generatedAt, model: storyModel
        )
        let input = LocalSceneStoryProjection.modelInput(request: request)
        let call = try await performResponsesCall(
            model: storyModel,
            instructions: LocalStoryInferencePrompts.sceneStoryInstructions(request: request),
            schemaName: "scene_story_set",
            schema: schema,
            input: input,
            reasoningEffort: "medium",
            verbosity: "medium",
            label: "SceneStory",
            operation: "scene_story_generate",
            projectId: request.wire.projectId, parentTraceId: request.wire.lensContext.graphTraceId ?? ""
        )
        let attempt = SceneStoryOpenAIAttemptProvenance(
            responseId: call.responseId,
            purpose: purpose,
            model: call.model,
            inputTokens: call.inputTokens,
            outputTokens: call.outputTokens,
            startedAt: startedAt,
            completedAt: DateFormats.now()
        )
        do {
            guard let data = call.text.data(using: .utf8) else {
                throw ScreenGraphError.openAI("SceneStory response was not UTF-8 text.")
            }
            var document = try SceneStorySetDocument.decode(from: data)
            if document.model.isEmpty || document.model == storyModel {
                document.model = call.model
            }
            LocalSceneStoryPostProcessing.repairTerminology(&document)
            LocalSceneStoryPostProcessing.sanitizeDialogue(&document, request: request)
            LocalSceneStoryPostProcessing.appendCompassHandoffWarnings(&document)
            document = document.normalized()
            try LocalSceneStoryValidation.validate(
                document: document, request: request, userId: Self.localUserID, generatedAt: generatedAt
            )
            await InferenceTraceStore.shared.enrich(traceId: call.traceId,
                parsedOutputJSON: String(decoding: try JSONCoding.encoder.encode(document), as: UTF8.self))
            await InferenceTraceStore.shared.enrichContext(traceId: call.traceId,
                parentTraceId: request.wire.lensContext.graphTraceId, artifactType: "scene_story_set", artifactId: document.sceneStorySetId)
            return (document, attempt)
        } catch {
            await recordValidation(call: call, projectId: request.wire.projectId, artifactType: "scene_story_set", error: error)
            if var validation = error as? LocalStoryInferenceValidationError {
                validation.attempt = attempt
                validation.call = call
                throw validation
            }
            throw error
        }
    }

    // MARK: Frame Forms generation (direct)

    func generateFrameForms(_ payload: FrameFormsGenerateRequest) async throws -> FrameFormsGenerateResponse {
        let mode = payload.selectedForm == nil ? "initial" : "expansion"
        let graph = try await MeaningGraphRuntime.shared.snapshot(graphSelection)
        var (candidates, warnings) = await Task.detached { LocalFrameFormSelection.candidates(request: payload, mode: mode, graph: graph) }.value
        guard candidates.count >= 3 else {
            throw ScreenGraphError.openAI("The selected graph has no usable frame concepts. Review its graph configuration.")
        }
        candidates = Array(candidates.prefix(3))
        var selectionRequest = URLRequest(url: URL(string: "litscenes-local://meaning/frame-selection")!)
        selectionRequest.httpMethod = "POST"
        selectionRequest.httpBody = try JSONCoding.encoder.encode(payload)
        let selectionJSON = inferenceTraceJSONString(LocalFrameFormSelection.modelInput(request: payload, candidates: candidates, mode: mode, retryCorrection: ""))
        let selectionTrace = await InferenceTraceStore.shared.recordEvent(request: selectionRequest,
            metadata: InferenceTraceRequestMetadata(provider: "local", apiFamily: "meaning_graph", operation: "frame_selection",
                projectId: payload.projectId, runId: runId, traceGroupId: runId,
                workflowName: "story", workflowStep: "frame_selection", artifactType: "frame_forms", artifactId: runId,
                requestTextJSON: inferenceTraceJSONString(["graph_provenance": try JSONSerialization.jsonObject(with: GraphCoding.data(graph.provenance))]),
                responseTextJSON: selectionJSON))
        await InferenceTraceStore.shared.enrich(traceId: selectionTrace, parsedOutputJSON: selectionJSON)

        var priorUsage = (input: 0, output: 0)
        var options: [LensFrameFormOption]
        var call: LocalResponsesCallResult
        do {
            (options, call) = try await frameFormsAttempt(payload: payload, candidates: candidates, mode: mode, correction: "", parentTraceId: selectionTrace)
        } catch let error as LocalStoryInferenceValidationError {
            priorUsage = (error.call?.inputTokens ?? 0, error.call?.outputTokens ?? 0)
            let correction = "The prior candidate failed validation: \(error.message). Regenerate all three options and satisfy every hard rule exactly."
            (options, call) = try await frameFormsAttempt(payload: payload, candidates: candidates, mode: mode, correction: correction, parentTraceId: selectionTrace)
        }

        var response = FrameFormsGenerateResponse()
        response.graphProvenance = graph.provenance
        response.traceId = call.traceId
        response.schemaVersion = "litscenes.frame_forms.v0.1"
        response.userId = Self.localUserID
        response.projectId = payload.projectId
        response.mode = mode
        response.generatedAt = DateFormats.now()
        response.model = call.model
        response.options = options
        response.warnings = warnings
        response.requestId = call.responseId
        response.usageInputTokens = priorUsage.input + call.inputTokens
        response.usageOutputTokens = priorUsage.output + call.outputTokens
        return response
    }

    private func frameFormsAttempt(
        payload: FrameFormsGenerateRequest,
        candidates: [LocalFrameFormCandidate],
        mode: String,
        correction: String, parentTraceId: String
    ) async throws -> ([LensFrameFormOption], LocalResponsesCallResult) {
        let call = try await performResponsesCall(
            model: frameFormModel,
            instructions: LocalStoryInferencePrompts.frameFormsInstructions(expansion: mode == "expansion"),
            schemaName: "frame_forms",
            schema: LocalStoryInferenceSchemas.frameForms(candidates: candidates),
            input: LocalFrameFormSelection.modelInput(
                request: payload, candidates: candidates, mode: mode, retryCorrection: correction
            ),
            reasoningEffort: "low",
            verbosity: "low",
            label: "Frame Forms",
            operation: "frame_forms_generate",
            projectId: payload.projectId, parentTraceId: parentTraceId
        )
        do {
            let options = try LocalFrameFormSelection.decodeAndValidate(text: call.text, candidates: candidates)
            await InferenceTraceStore.shared.enrich(traceId: call.traceId,
                parsedOutputJSON: String(decoding: try JSONCoding.encoder.encode(options), as: UTF8.self))
            return (options, call)
        } catch {
            await recordValidation(call: call, projectId: payload.projectId, artifactType: "frame_forms", error: error)
            if var validation = error as? LocalStoryInferenceValidationError {
                validation.call = call
                throw validation
            }
            throw error
        }
    }

    private func recordValidation(call: LocalResponsesCallResult, projectId: String, artifactType: String, error: Error) async {
        var request = URLRequest(url: URL(string: "litscenes-local://meaning/validate")!)
        request.httpMethod = "POST"
        let metadata = InferenceTraceRequestMetadata(provider: "local", apiFamily: "meaning_graph", operation: "validation",
            projectId: projectId, runId: runId, traceGroupId: runId, parentTraceId: call.traceId,
            workflowName: "story", workflowStep: "validation_failed", artifactType: artifactType, artifactId: runId,
            responseTextJSON: inferenceTraceJSONString(["provider_response_id": call.responseId, "error": error.localizedDescription]))
        _ = await InferenceTraceStore.shared.record(request: request, metadata: metadata, response: nil,
            responseBody: nil, latencyMs: 0, error: error)
    }

    // MARK: Shared Responses transport

    private func performResponsesCall(
        model: String,
        instructions: String,
        schemaName: String,
        schema: [String: Any],
        input: [String: Any],
        reasoningEffort: String,
        verbosity: String,
        label: String,
        operation: String,
        projectId: String, parentTraceId: String = ""
    ) async throws -> LocalResponsesCallResult {
        if let error = endpointConfigurationError { throw ScreenGraphError.credentials(error) }
        guard !apiKey.isEmpty else { throw ScreenGraphError.credentials("Add a personal OpenAI-compatible key or select Go credits to generate. Graph exploration works without a key.") }
        try Task.checkCancellation()
        let graph = try await MeaningGraphRuntime.shared.snapshot(graphSelection)
        let inputData = try JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .prettyPrinted])
        let inputText = String(data: inputData, encoding: .utf8) ?? "{}"
        // store:false — direct mode runs on the user's own account and keeps
        // nothing server-side that it does not have to.
        let body: [String: Any] = [
            "model": model,
            "store": false,
            "instructions": instructions,
            "reasoning": ["effort": reasoningEffort],
            "text": [
                "verbosity": verbosity,
                "format": [
                    "type": "json_schema",
                    "name": schemaName,
                    "strict": true,
                    "schema": schema
                ]
            ],
            "input": [
                [
                    "role": "user",
                    "content": [["type": "input_text", "text": inputText]]
                ]
            ]
        ]
        var request = URLRequest(url: responsesURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // The canonical traced transport: persists the provider-bound request
        // and response envelope, latency, and failures like every other
        // inference call in the app.
        let result = try await TracedHTTPTransport.send(
            request: request,
            metadata: InferenceTraceRequestMetadata(
                provider: "openai",
                apiFamily: "responses",
                operation: operation,
                projectId: projectId, runId: runId, traceGroupId: runId, parentTraceId: parentTraceId,
                workflowName: "story", workflowStep: operation,
                artifactType: schemaName, artifactId: runId,
                model: model,
                requestBodyFormat: "application/json",
                responseBodyFormatHint: "application/json",
                requestTextJSON: inferenceTraceJSONString([
                    "prompt": instructions + "\n\n" + inputText,
                    "provider_request": body,
                    "graph_provenance": try JSONSerialization.jsonObject(with: GraphCoding.data(graph.provenance))
                ]),
                providerRequestIDHeaderCandidates: ["x-request-id"]
            )
        )
        let data = result.data
        guard let httpResponse = result.response else {
            throw ScreenGraphError.openAI("\(label) response was not HTTP.")
        }
        let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = localResponsesErrorMessage(decoded: decoded, data: data)
            throw ScreenGraphError.openAI("\(label) request failed (\(httpResponse.statusCode)): \(message)")
        }
        if let error = decoded["error"] as? [String: Any],
           let message = (error["message"] as? String)?.trimmed, !message.isEmpty {
            throw ScreenGraphError.openAI("\(label): \(message)")
        }
        guard let text = localResponsesOutputText(decoded), !text.trimmed.isEmpty else {
            throw ScreenGraphError.openAI("\(label) response did not include output text.")
        }
        let responseModel = ((decoded["model"] as? String)?.trimmed).flatMap { $0.isEmpty ? nil : $0 } ?? model
        let responseId = ((decoded["id"] as? String)?.trimmed) ?? ""
        var usage = (input: 0, output: 0)
        if let usageBody = decoded["usage"] as? [String: Any] {
            usage.input = usageBody["input_tokens"] as? Int ?? 0
            usage.output = usageBody["output_tokens"] as? Int ?? 0
        }
        await InferenceTraceStore.shared.enrich(
            traceId: result.traceId,
            providerRequestId: responseId,
            model: responseModel,
            usage: InferenceTraceUsage(inputTokens: usage.input, outputTokens: usage.output, totalTokens: usage.input + usage.output),
            parsedOutputJSON: text
        )
        return LocalResponsesCallResult(
            text: text,
            model: responseModel,
            responseId: responseId,
            inputTokens: usage.input,
            outputTokens: usage.output,
            traceId: result.traceId
        )
    }
}

/// One traced Responses call: the structured-output text plus the identity and
/// usage the ledger and provenance records need.
struct LocalResponsesCallResult: Sendable {
    var text: String
    var model: String
    var responseId: String
    var inputTokens: Int
    var outputTokens: Int
    var traceId: String
}

private func localResponsesOutputText(_ decoded: [String: Any]) -> String? {
    guard let output = decoded["output"] as? [[String: Any]] else { return nil }
    for item in output {
        guard let content = item["content"] as? [[String: Any]] else { continue }
        for part in content {
            if let refusal = (part["refusal"] as? String)?.trimmed, !refusal.isEmpty {
                return nil
            }
            if let text = (part["text"] as? String), !text.trimmed.isEmpty {
                return text
            }
        }
    }
    return nil
}

private func localResponsesErrorMessage(decoded: [String: Any], data: Data) -> String {
    if let error = decoded["error"] as? [String: Any],
       let message = (error["message"] as? String)?.trimmed, !message.isEmpty {
        return String(message.prefix(900))
    }
    let text = (String(data: data, encoding: .utf8) ?? "").trimmed
    return text.isEmpty ? "empty response" : String(text.prefix(900))
}

// MARK: - Extension inits for locally constructed wire models

extension LensContextResolveResponse {
    init(
        schemaVersion: String,
        userId: String,
        projectId: String,
        goalFingerprint: String,
        selectedMeaningNodes: [LensContextMeaningNode],
        meaningEdgeNeighbors: [LensContextMeaningEdgeNeighbor],
        meaningEvidence: [LensContextMeaningEvidence],
        aestheticCandidates: [LensContextAestheticCandidate],
        styleCandidates: [LensContextStyleCandidate],
        warnings: [String],
        queryStats: LensContextQueryStats
    ) {
        self.schemaVersion = schemaVersion
        self.userId = userId
        self.projectId = projectId
        self.goalFingerprint = goalFingerprint
        self.selectedMeaningNodes = selectedMeaningNodes
        self.meaningEdgeNeighbors = meaningEdgeNeighbors
        self.meaningEvidence = meaningEvidence
        self.aestheticCandidates = aestheticCandidates
        self.styleCandidates = styleCandidates
        self.warnings = warnings
        self.queryStats = queryStats
    }
}

extension LensContextMeaningNode {
    init(
        id: String,
        slug: String,
        kind: String,
        abstractionLevel: String,
        name: String,
        status: String,
        confidenceScore: Double,
        reuseScore: Double,
        definition: String,
        tags: [String],
        edgeDegree: Int
    ) {
        self.id = id
        self.slug = slug
        self.kind = kind
        self.abstractionLevel = abstractionLevel
        self.name = name
        self.status = status
        self.confidenceScore = confidenceScore
        self.reuseScore = reuseScore
        self.definition = definition
        self.tags = tags
        self.edgeDegree = edgeDegree
    }
}

extension LensContextStyleCandidate {
    init(
        styleId: String,
        title: String,
        label: String,
        caption: String,
        imageUrl: String,
        collectionKey: String,
        collectionName: String,
        secondaryCollection: String,
        moods: [String],
        hueName: String,
        hueHex: String,
        medium: String,
        scalarSat: Int,
        scalarCon: Int,
        scalarSer: Int,
        scalarLin: Int,
        scalarSty: Int,
        score: Double,
        matchCount: Int,
        matchedTerms: [LensContextStyleMatchedTerm],
        positivePromptAtoms: [String],
        negativePromptAtoms: [String],
        transferableTraits: [String]
    ) {
        self.styleId = styleId
        self.title = title
        self.label = label
        self.caption = caption
        self.imageUrl = imageUrl
        self.collectionKey = collectionKey
        self.collectionName = collectionName
        self.secondaryCollection = secondaryCollection
        self.moods = moods
        self.hueName = hueName
        self.hueHex = hueHex
        self.medium = medium
        self.scalarSat = scalarSat
        self.scalarCon = scalarCon
        self.scalarSer = scalarSer
        self.scalarLin = scalarLin
        self.scalarSty = scalarSty
        self.score = score
        self.matchCount = matchCount
        self.matchedTerms = matchedTerms
        self.positivePromptAtoms = positivePromptAtoms
        self.negativePromptAtoms = negativePromptAtoms
        self.transferableTraits = transferableTraits
    }
}

extension LensContextStyleMatchedTerm {
    init(inputTerm: String, kind: String, fieldName: String, value: String, contribution: Double) {
        self.inputTerm = inputTerm
        self.kind = kind
        self.fieldName = fieldName
        self.value = value
        self.contribution = contribution
    }
}

extension FrameFormsGenerateResponse {
    init(
        schemaVersion: String = "",
        userId: String = "",
        projectId: String = "",
        mode: String = "",
        generatedAt: String = "",
        model: String = "",
        options: [LensFrameFormOption] = [],
        warnings: [String] = [],
        requestId: String = "",
        usageInputTokens: Int = 0,
        usageOutputTokens: Int = 0
    ) {
        self.schemaVersion = schemaVersion
        self.userId = userId
        self.projectId = projectId
        self.mode = mode
        self.generatedAt = generatedAt
        self.model = model
        self.options = options
        self.warnings = warnings
        self.requestId = requestId
        self.usageInputTokens = usageInputTokens
        self.usageOutputTokens = usageOutputTokens
    }
}

// MARK: - Local request normalization (port of the service's request contract)

/// Class on purpose: SceneStoryGenerateRequest is a large inline value struct,
/// and passing it by value through the projection/schema/validation pipeline
/// builds debug-mode stack frames big enough to overflow a cooperative-task
/// stack. The box keeps one normalized copy on the heap; everything downstream
/// carries a reference.
final class LocalSceneStoryRequest {
    var wire: SceneStoryGenerateRequest
    let retryCorrection: String
    let warnings: [String]

    init(wire: SceneStoryGenerateRequest, retryCorrection: String = "", warnings: [String] = []) {
        self.wire = wire
        self.retryCorrection = retryCorrection
        self.warnings = warnings
    }

    func withRetryCorrection(_ correction: String) -> LocalSceneStoryRequest {
        LocalSceneStoryRequest(wire: wire, retryCorrection: correction, warnings: warnings)
    }
}

struct LocalStoryInferenceValidationError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
    var attempt: SceneStoryOpenAIAttemptProvenance? = nil
    var call: LocalResponsesCallResult? = nil
}

func normalizedLocalSceneStoryRequest(_ payload: SceneStoryGenerateRequest) -> LocalSceneStoryRequest {
    var warnings: [String] = []
    var wire = payload
    wire.storyCount = clampLocalCount(wire.storyCount, fallback: 1, maximum: 6, name: "story_count", warnings: &warnings)
    wire.scenesPerStory = clampLocalCount(wire.scenesPerStory, fallback: 4, maximum: 8, name: "scenes_per_story", warnings: &warnings)
    wire.beatsPerScene = clampLocalCount(wire.beatsPerScene, fallback: 1, maximum: 5, name: "beats_per_scene", warnings: &warnings)
    wire.goal = wire.goal.normalized()
    wire.storyMemory = wire.storyMemory.normalized(limit: 12)
    wire.generationIntent = wire.generationIntent.normalized()
    wire.storyGenerationBrief = wire.storyGenerationBrief.normalized()
    wire.toneConstraints = uniqueNonEmpty(wire.toneConstraints, limit: 32)
    wire.operatorInstructions = uniqueNonEmpty(wire.operatorInstructions, limit: 32)
    if wire.lensContext.meaningEdgeNeighbors.isEmpty {
        warnings.append("no meaning edges were supplied; SceneStory will rely on Goal and Lens context")
    }
    if wire.mediaAnchors.isEmpty {
        warnings.append("no media anchors were supplied; invented visual material must be disclosed")
    }
    return LocalSceneStoryRequest(wire: wire, warnings: warnings)
}

private func clampLocalCount(_ value: Int, fallback: Int, maximum: Int, name: String, warnings: inout [String]) -> Int {
    if value <= 0 { return fallback }
    if value > maximum {
        warnings.append("\(name) clamped to \(maximum)")
        return maximum
    }
    return value
}
