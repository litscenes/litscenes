import Foundation

// MARK: - Story Inference modes
//
// The story spine (Frame Context resolve → SceneStory generation → Frame Forms)
// can run two ways:
//
//   direct — the app talks straight to an OpenAI-compatible Responses endpoint
//            with the user's own key. Frame Context resolves against the bundled
//            starter meaning vocabulary (no graph edges or corpus evidence), and
//            the SceneStory / Frame Forms prompts and strict schemas run in-app.
//            This mode needs nothing but OPENAI_API_KEY.
//
//   hosted — the existing LitScenes meaning service (endpoint + token): live
//            meaning-graph retrieval (nodes, edge neighbors, corpus evidence,
//            curated aesthetic/style candidates) plus managed inference.
//
// LITSCENES_STORY_INFERENCE selects explicitly ("direct" / "hosted"); when unset,
// a configured meaning service wins and the app otherwise falls back to direct.

enum StoryInferenceMode: String, CaseIterable, Identifiable, Sendable {
    case direct
    case hosted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .direct: "Direct (your key)"
        case .hosted: "LitScenes Hosted"
        }
    }

    static let preferenceKey = "LITSCENES_STORY_INFERENCE"

    static func resolved() -> StoryInferenceMode {
        let raw = LitScenesCredentialStore()
            .resolvedCredentialValue(forKey: preferenceKey)
            .trimmed
            .lowercased()
        if let explicit = StoryInferenceMode(rawValue: raw) {
            return explicit
        }
        if (try? LensContextClient.fromEnvironment()) != nil {
            return .hosted
        }
        return .direct
    }
}

/// The one seam the engine calls for the story spine. Dispatches to the hosted
/// meaning service or the in-app direct implementation by resolved mode.
enum StoryInferenceService {
    case hosted(LensContextClient)
    case direct(LocalStoryInferenceClient)

    static func fromEnvironment() throws -> StoryInferenceService {
        switch StoryInferenceMode.resolved() {
        case .hosted:
            return .hosted(try LensContextClient.fromEnvironment())
        case .direct:
            return .direct(try LocalStoryInferenceClient.fromEnvironment())
        }
    }

    static var isConfigured: Bool {
        (try? fromEnvironment()) != nil
    }

    func resolve(_ payload: LensContextResolveRequest) async throws -> LensContextResolveResponse {
        switch self {
        case .hosted(let client): try await client.resolve(payload)
        case .direct(let client): try await client.resolve(payload)
        }
    }

    func generateSceneStorySet(_ payload: SceneStoryGenerateRequest) async throws -> SceneStoryGenerateResult {
        switch self {
        case .hosted(let client): try await client.generateSceneStorySet(payload)
        case .direct(let client): try await client.generateSceneStorySet(payload)
        }
    }

    func generateFrameForms(_ payload: FrameFormsGenerateRequest) async throws -> FrameFormsGenerateResponse {
        switch self {
        case .hosted(let client): try await client.generateFrameForms(payload)
        case .direct(let client): try await client.generateFrameForms(payload)
        }
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

// MARK: - Bundled meaning vocabulary

/// One articulated entry of the bundled starter vocabulary
/// (Resources/meaning_choice_index.json). The starter index carries slug,
/// kind, name, definition, tags, and status only — no graph edges, corpus
/// evidence, pole expressions, or abstraction levels; direct mode discloses
/// those gaps as warnings instead of pretending parity with the hosted graph.
struct LocalMeaningIndexNode: Sendable, Hashable {
    var slug: String
    var kind: String
    var name: String
    var definition: String
    var status: String
    var tags: [String]
}

struct LocalMeaningIndex: Sendable {
    let nodes: [LocalMeaningIndexNode]
    private let nodesBySlug: [String: LocalMeaningIndexNode]

    static let shared: LocalMeaningIndex = (try? LocalMeaningIndex.loadBundled()) ?? LocalMeaningIndex(nodes: [])

    init(nodes: [LocalMeaningIndexNode]) {
        self.nodes = nodes
        self.nodesBySlug = Dictionary(uniqueKeysWithValues: nodes.map { ($0.slug, $0) })
    }

    static func loadBundled() throws -> LocalMeaningIndex {
        let url = try packagedResourceURL(named: "meaning_choice_index", extension: "json")
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["meaning_node_choices"] as? [[String: Any]] else {
            return LocalMeaningIndex(nodes: [])
        }
        let nodes = choices.compactMap { entry -> LocalMeaningIndexNode? in
            guard let slug = (entry["slug"] as? String)?.trimmed, !slug.isEmpty else { return nil }
            return LocalMeaningIndexNode(
                slug: slug,
                kind: (entry["kind"] as? String)?.trimmed ?? "",
                name: (entry["name"] as? String)?.trimmed ?? slug,
                definition: (entry["definition"] as? String)?.trimmed ?? "",
                status: (entry["status"] as? String)?.trimmed ?? "",
                tags: (entry["tags"] as? [String])?.map(\.trimmed).filter { !$0.isEmpty } ?? []
            )
        }
        return LocalMeaningIndex(nodes: nodes)
    }

    func node(forSlug slug: String) -> LocalMeaningIndexNode? {
        nodesBySlug[slug.trimmed.lowercased()] ?? nodesBySlug[slug.trimmed]
    }
}

// MARK: - Direct client

struct LocalStoryInferenceClient: Sendable {
    var apiKey: String
    var responsesURL: URL
    var storyModel: String
    var frameFormModel: String
    private static let localUserID = "local"

    static func fromEnvironment() throws -> LocalStoryInferenceClient {
        guard let key = OpenAIKeyStore.resolvedAPIKey(), !key.isEmpty else {
            throw ScreenGraphError.credentials(
                "Direct Story Inference needs an OpenAI-compatible key. Add OPENAI_API_KEY (and optionally OPENAI_BASE_URL) in Settings."
            )
        }
        return LocalStoryInferenceClient(
            apiKey: key,
            responsesURL: try OpenAITextEndpointSettings.responsesURL(),
            storyModel: OpenAITextEndpointSettings.storyModel(),
            frameFormModel: OpenAITextEndpointSettings.frameFormModel()
        )
    }

    // MARK: Frame Context (local resolve)

    /// Hydrates the request's meaning refs from the bundled starter vocabulary
    /// and scores style candidates from the verified local catalog snapshot
    /// (bundled starter, or the full set when the user has fetched it), so the
    /// Goal → Frames → Scene Plan → Story spine completes without any hosted
    /// service. Edge neighbors, corpus evidence, and curated aesthetic
    /// candidates require the hosted meaning graph and stay empty — disclosed
    /// via warnings and degrading gracefully downstream.
    func resolve(_ payload: LensContextResolveRequest) async throws -> LensContextResolveResponse {
        let started = Date()
        let index = LocalMeaningIndex.shared
        var warnings: [String] = [
            "Local mode: resolved against the bundled starter vocabulary. Graph neighbors, corpus evidence, and curated aesthetic candidates require the hosted meaning service."
        ]
        let catalogSnapshot = try await CatalogManifestRuntime.shared.loadSnapshot()
        let styleCandidates = LocalStyleCandidateBuilder.candidates(
            from: catalogSnapshot.styleBrowse,
            styleTermRefs: payload.styleTermRefs,
            limit: max(payload.limits.styleCandidates, 1)
        )
        if catalogSnapshot.origin == .bundled {
            warnings.append("Style candidates come from the bundled starter catalog (\(styleCandidates.count) styles). Refresh the style catalog for the full set.")
        }
        var selected: [LensContextMeaningNode] = []
        var missing: [String] = []
        for ref in payload.meaningNodeRefs {
            let slug = ref.slug.trimmed
            guard !slug.isEmpty else { continue }
            if let node = index.node(forSlug: slug) {
                selected.append(LensContextMeaningNode(
                    id: node.slug,
                    slug: node.slug,
                    kind: node.kind,
                    abstractionLevel: "",
                    name: node.name,
                    status: node.status,
                    confidenceScore: 0,
                    reuseScore: 0,
                    definition: node.definition,
                    tags: node.tags,
                    edgeDegree: 0
                ))
            } else {
                missing.append(slug)
                // Refs authored by the GOAL interview but absent from the starter
                // index still carry their own name/kind — keep them usable.
                selected.append(LensContextMeaningNode(
                    id: slug,
                    slug: slug,
                    kind: ref.kind.rawValue,
                    abstractionLevel: "",
                    name: ref.name.trimmed.isEmpty ? slug : ref.name.trimmed,
                    status: "",
                    confidenceScore: 0,
                    reuseScore: 0,
                    definition: ref.evidence.trimmed,
                    tags: [],
                    edgeDegree: 0
                ))
            }
        }
        if !missing.isEmpty {
            warnings.append("Not in the bundled vocabulary (kept from the Goal refs): \(missing.joined(separator: ", "))")
        }
        let durationMs = Int(Date().timeIntervalSince(started) * 1000)
        return LensContextResolveResponse(
            schemaVersion: "litscenes.lens_context.local.v0.1",
            userId: Self.localUserID,
            projectId: payload.projectId,
            goalFingerprint: payload.goalFingerprint,
            selectedMeaningNodes: selected,
            meaningEdgeNeighbors: [],
            meaningEvidence: [],
            aestheticCandidates: [],
            styleCandidates: styleCandidates,
            warnings: warnings,
            queryStats: LensContextQueryStats(
                durationMs: durationMs,
                meaningRefCount: payload.meaningNodeRefs.count,
                resolvedMeaningNodeCount: selected.count,
                meaningEdgeNeighborCount: 0,
                meaningEvidenceCount: 0,
                aestheticTermRefCount: payload.aestheticTermRefs.count,
                aestheticCandidateCount: 0
            )
        )
    }

    // MARK: SceneStory generation (direct)

    func generateSceneStorySet(_ payload: SceneStoryGenerateRequest) async throws -> SceneStoryGenerateResult {
        let generatedAt = DateFormats.now()
        let request = normalizedLocalSceneStoryRequest(payload)
        var provenance = SceneStoryGenerationProvenance(
            lambdaPromptVersion: "litscenes.scene_story_prompt.v0.7-local",
            desktopInstructionVersion: "litscenes.scene_story_slot_instructions.v0.2",
            validatorVersion: "litscenes.scene_story_validator.v0.3-local",
            dialoguePolicyVersion: "litscenes.dialogue_policy.v0.1"
        )
        let requestId = "local_\(UUID().uuidString.lowercased())"

        do {
            let (document, attempt) = try await sceneStoryAttempt(
                request: request, generatedAt: generatedAt, purpose: "creative_generation"
            )
            provenance.openaiAttempts.append(attempt)
            provenance.warnings.append(contentsOf: document.warnings)
            return SceneStoryGenerateResult(document: document, provenance: provenance, hostedRequestId: requestId)
        } catch let error as LocalStoryInferenceValidationError {
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
            projectId: request.wire.projectId
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
        return (document, attempt)
    }

    // MARK: Frame Forms generation (direct)

    func generateFrameForms(_ payload: FrameFormsGenerateRequest) async throws -> FrameFormsGenerateResponse {
        let mode = payload.selectedForm == nil ? "initial" : "expansion"
        var (candidates, warnings) = LocalFrameFormSelection.candidates(request: payload, mode: mode)
        guard candidates.count >= 3 else {
            throw ScreenGraphError.openAI("Fewer than 3 usable meaning nodes are available in the bundled vocabulary.")
        }
        candidates = Array(candidates.prefix(3))

        var options: [LensFrameFormOption]
        var call: LocalResponsesCallResult
        do {
            (options, call) = try await frameFormsAttempt(payload: payload, candidates: candidates, mode: mode, correction: "")
        } catch let error as LocalStoryInferenceValidationError {
            let correction = "The prior candidate failed validation: \(error.message). Regenerate all three options and satisfy every hard rule exactly."
            (options, call) = try await frameFormsAttempt(payload: payload, candidates: candidates, mode: mode, correction: correction)
        }

        var response = FrameFormsGenerateResponse()
        response.schemaVersion = "litscenes.frame_forms.v0.1"
        response.userId = Self.localUserID
        response.projectId = payload.projectId
        response.mode = mode
        response.generatedAt = DateFormats.now()
        response.model = call.model
        response.options = options
        response.warnings = warnings
        response.requestId = call.responseId
        response.usageInputTokens = call.inputTokens
        response.usageOutputTokens = call.outputTokens
        return response
    }

    private func frameFormsAttempt(
        payload: FrameFormsGenerateRequest,
        candidates: [LocalFrameFormCandidate],
        mode: String,
        correction: String
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
            projectId: payload.projectId
        )
        let options = try LocalFrameFormSelection.decodeAndValidate(text: call.text, candidates: candidates)
        return (options, call)
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
        projectId: String
    ) async throws -> LocalResponsesCallResult {
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
                projectId: projectId,
                model: model,
                requestBodyFormat: "application/json",
                responseBodyFormatHint: "application/json",
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
            model: responseModel
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
    let wire: SceneStoryGenerateRequest
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

struct LocalStoryInferenceValidationError: Error {
    var message: String
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
