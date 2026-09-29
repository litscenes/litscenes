import Foundation

/// Provider facts are independent of editable render-stack preferences.
struct ImagePromptConstraint: Codable, Hashable, Sendable {
    var endpoint: String
    var field: String
    var maximum: Int
    var unit = "unicode_scalars"
    var evidence: String

    func count(_ text: String) -> Int { text.unicodeScalars.count }

    static func resolve(provider: String, endpoint: String, model: String, managed: Bool) -> [Self] {
        func limit(_ maximum: Int, _ evidence: String, field: String = "prompt") -> Self {
            Self(endpoint: endpoint, field: field, maximum: maximum, evidence: evidence)
        }
        let address = URL(string: endpoint)
        let path = address?.path ?? endpoint
        if provider == "fal" {
            let maximum: Int?
            switch endpoint {
            case "fal-ai/nano-banana-2", "fal-ai/nano-banana-2/edit": maximum = 50_000
            case "fal-ai/image-apps-v2/outpaint": maximum = 500
            case "reve/2.1/text-to-image": maximum = 4_000
            case "microsoft/mai-image-2.5": maximum = 5_000
            default: maximum = nil
            }
            var result = maximum.map { [limit($0, "https://fal.ai/api/openapi/queue/openapi.json?endpoint_id=" + endpoint)] } ?? []
            if managed { result.append(limit(10_000, "LitScenes Go image request contract")) }
            return result
        }
        if provider == "stability", address?.host == nil || address?.host == "api.stability.ai", path == "/v2beta/stable-image/generate/ultra" {
            return [limit(10_000, "https://api.stability.ai/v2alpha/openapi"),
                    limit(10_000, "https://api.stability.ai/v2alpha/openapi", field: "negative_prompt")]
        }
        if provider == "openai", address?.host == nil || address?.host == "api.openai.com", ["/v1/images/generations", "/v1/images/edits"].contains(path), model.hasPrefix("gpt-image-") {
            return [limit(32_000, "https://developers.openai.com/api/reference/resources/images")]
        }
        return []
    }
}

struct ImagePromptReference: Codable, Hashable, Sendable {
    var id: String
    var filename: String
    var role: String
    var title: String
    var sha256: String
    var binding: String? = nil
    var purpose: ImageReferencePurpose? = nil

    static func sources(_ sources: [OpenAIImageEditSource]) -> [Self] {
        sources.enumerated().map { index, source in
            Self(id: "reference_\(index + 1)", filename: source.fileName, role: source.role,
                 title: source.title, sha256: sha256Hex(source.data), binding: source.promptBinding, purpose: source.referencePurpose)
        }
    }
}

/// An immutable preparation is separate from the editable creative source.
struct PreparedImagePrompt: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var sourcePrompt: String
    var assembledFields: [String: String]
    var providerFields: [String: String]
    var provider: String
    var endpoint: String
    var model: String
    var billingSource: String
    var constraints: [ImagePromptConstraint]
    var references: [ImagePromptReference]
    var protectedText: [String]
    var traceId = ""
    var rewriteTraceIds: [String] = []
    var changeSummary = ""
    var state = "prepared"
    var submittedFields: [String: String]?
    var submittedAt: String?
    var errorMessage = ""
    var inputFingerprint: String?
    var rewriteModel: String?
    var observedConstraints: [ImagePromptConstraint]?

    var prompt: String { providerFields["prompt"] ?? "" }
    var wasShortened: Bool { assembledFields != providerFields }
    var fingerprint: String {
        struct ConstraintInput: Encodable {
            var endpoint: String
            var field: String
            var maximum: Int
            var unit: String
        }
        struct Input: Encodable {
            var revision = 1
            var source: String
            var fields: [String: String]
            var provider: String
            var endpoint: String
            var model: String
            var billing: String
            var constraints: [ConstraintInput]
            var references: [ImagePromptReference]
            var protected: [String]
        }
        let input = Input(source: sourcePrompt, fields: assembledFields, provider: provider, endpoint: endpoint,
                          model: model, billing: billingSource,
                          constraints: constraints.map { ConstraintInput(endpoint: $0.endpoint, field: $0.field, maximum: $0.maximum, unit: $0.unit) },
                          references: references, protected: protectedText)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return sha256Hex((try? encoder.encode(input)) ?? Data())
    }
    var violations: [ImagePromptConstraint] {
        constraints.filter { $0.count(providerFields[$0.field] ?? "") > $0.maximum }
    }
    var limitMessage: String {
        violations.map { "\($0.field.replacingOccurrences(of: "_", with: " ").capitalized) has \($0.count(providerFields[$0.field] ?? "").formatted()) characters; this route accepts \($0.maximum.formatted())." }
            .joined(separator: " ") + " Your full prompt is saved. Edit it or choose another model."
    }
    var shorteningNotice: String {
        let keys = assembledFields.keys.sorted().filter { assembledFields[$0] != providerFields[$0] }
        return keys.map { key in
            let before = (assembledFields[key] ?? "").unicodeScalars.count
            let after = (providerFields[key] ?? "").unicodeScalars.count
            let label = key == "prompt" ? "" : " \(key.replacingOccurrences(of: "_", with: " "))"
            return "Shortened\(label) \(before.formatted()) to \(after.formatted()) characters"
        }.joined(separator: " · ")
    }
    var safe: Self {
        guard let data = try? JSONEncoder().encode(self),
              let value = try? JSONDecoder().decode(Self.self, from: WorkflowPrivacy.body(data)) else { return self }
        return value
    }
}

actor ImagePromptCapture {
    private(set) var latest: PreparedImagePrompt?
    func set(_ value: PreparedImagePrompt) { latest = value }
}

enum ImagePromptContext {
    @TaskLocal static var sourcePrompt: String?
    @TaskLocal static var protectedText: [String] = []
    @TaskLocal static var capture: ImagePromptCapture?
}

enum ImagePromptPreparation {
    static func prepare(fields: [String: String], provider: String, endpoint: String, model: String,
                        managed: Bool = false, references: [ImagePromptReference] = [],
                        protectedText: [String] = [], metadata: InferenceTraceRequestMetadata) async throws -> PreparedImagePrompt {
        var value = PreparedImagePrompt(id: UUID().uuidString.lowercased(),
            sourcePrompt: ImagePromptContext.sourcePrompt ?? fields["prompt"] ?? "",
            assembledFields: fields, providerFields: fields, provider: provider, endpoint: endpoint,
            model: model, billingSource: managed ? "go" : "personal",
            constraints: ImagePromptConstraint.resolve(provider: provider, endpoint: endpoint, model: model, managed: managed),
            references: references, protectedText: uniqueNonEmpty(ImagePromptContext.protectedText + protectedText + references.flatMap { [$0.binding ?? "", $0.filename, $0.title] }))
        let scoped = WorkflowHTTP.scoped(metadata)
        let observed = try await InferenceTraceStore.shared.observedImagePromptConstraints(
            provider: provider, endpoint: endpoint, model: model, billingSource: value.billingSource, projectId: scoped.projectId)
        value.constraints += observed
        if !value.violations.isEmpty { value.state = "over_limit" }
        try await persist(&value, metadata: metadata)
        let progress = ImagePromptCapture()
        do {
            try Task.checkCancellation()
            guard !value.violations.isEmpty else { return value }
            let scoped = WorkflowHTTP.scoped(metadata)
            if let cached = try await InferenceTraceStore.shared.cachedImagePrompt(fingerprint: value.fingerprint, projectId: scoped.projectId),
               cached.fingerprint == value.fingerprint, cached.wasShortened, cached.violations.isEmpty {
                value.providerFields = cached.providerFields
                value.changeSummary = cached.changeSummary
                value.rewriteTraceIds = cached.rewriteTraceIds
                value.rewriteModel = cached.rewriteModel
                value.state = "prepared"
                try await persist(&value, metadata: metadata)
                try Task.checkCancellation()
                return value
            }
            value.state = "shortening"
            try await persist(&value, metadata: metadata)
            let client = try OpenAIClient.fromEnvironment(billingTarget: .text)
            value = try await ImagePromptShortening.shorten(value, rewrite: { request in
                try await client.shortenImagePrompt(request, metadata: scoped)
            }, record: { updated in
                var updated = updated
                try await persist(&updated, metadata: scoped)
                await progress.set(updated)
            })
            try await persist(&value, metadata: metadata)
            return value
        } catch {
            if let latest = await progress.latest, latest.id == value.id { value = latest }
            if let latest = await ImagePromptContext.capture?.latest, latest.id == value.id { value = latest }
            value.state = error is CancellationError || Task.isCancelled ? "canceled" : "shortening_failed"
            value.errorMessage = WorkflowPrivacy.text(error.localizedDescription)
            try await persist(&value, metadata: metadata)
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            throw ScreenGraphError.capture("Could not prepare a shortened prompt. No image request was sent; your full prompt is saved. Edit it, choose another model, or retry after correcting the text-provider issue. " + value.errorMessage)
        }
    }

    static func persist(_ value: inout PreparedImagePrompt, metadata: InferenceTraceRequestMetadata) async throws {
        value.inputFingerprint = value.fingerprint
        var event = WorkflowHTTP.scoped(metadata)
        event.parentTraceId = value.traceId
        event.apiFamily = "image_prompt"
        event.operation = "image_prompt_preparation"
        event.workflowStep = value.state == "shortening" ? "Shortening image prompt" : "Image prompt " + value.state.replacingOccurrences(of: "_", with: " ")
        event.captureRequestBody = false
        event.captureResponseBody = false
        let safe = value.safe
        event.requestTextJSON = inferenceTraceJSONString([
            "prompt": safe.prompt,
            "operator_prompt": safe.sourcePrompt,
            "prompt_stage": safe.state,
            "image_prompt_preparation": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(safe))) ?? [:]
        ])
        var request = URLRequest(url: URL(string: "litscenes://image-prompt/preparation")!)
        request.httpMethod = "LOCAL"
        let traceId = await InferenceTraceStore.shared.recordEvent(request: request, metadata: event)
        guard !traceId.isEmpty else { throw ScreenGraphError.capture("Could not save image prompt provenance; no image request was sent.") }
        value.traceId = traceId
        await ImagePromptContext.capture?.set(value)
        try await WorkflowCoordinator.shared.saveImagePrompt(value.safe)
    }

    static func submitted(_ metadata: InferenceTraceRequestMetadata) async throws {
        guard var value = metadata.imagePromptPreparation else { return }
        value.submittedFields = value.providerFields
        value.submittedAt = DateFormats.now()
        value.state = "submitted"
        do { try await WorkflowCoordinator.shared.saveImagePrompt(value.safe) }
        catch { throw ImagePromptPersistenceFailure(message: error.localizedDescription) }
        await ImagePromptContext.capture?.set(value)
    }

    static func observedConstraints(data: Data, endpoint: String, traceId: String) -> [ImagePromptConstraint] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let details = object["detail"] as? [[String: Any]] else { return [] }
        return details.compactMap { detail in
            guard let type = detail["type"] as? String,
                  ["string_too_long", "value_error.any_str.max_length"].contains(type),
                  let location = detail["loc"] as? [String], let field = location.last,
                  ["prompt", "negative_prompt"].contains(field),
                  let context = detail["ctx"] as? [String: Any],
                  let maximum = (context["max_length"] ?? context["limit_value"]) as? Int, maximum > 0 else { return nil }
            return ImagePromptConstraint(endpoint: endpoint, field: field, maximum: maximum,
                evidence: "Explicit provider field-length rejection; trace " + traceId)
        }
    }

    /// Retain explicit schema evidence for a future user-initiated retry, never resubmit here.
    static func providerRejected(_ metadata: InferenceTraceRequestMetadata, data: Data, status: Int, traceId: String) async {
        guard [400, 422].contains(status), var value = metadata.imagePromptPreparation else { return }
        let constraints = observedConstraints(data: data, endpoint: value.endpoint, traceId: traceId)
        guard !constraints.isEmpty else { return }
        if let captured = await ImagePromptContext.capture?.latest, captured.id == value.id { value = captured }
        value.observedConstraints = constraints
        value.state = "provider_length_error"
        value.errorMessage = "The provider reported a different field-length limit. Retrying will prepare the saved prompt against that verified limit."
        value.traceId = traceId
        do { try await persist(&value, metadata: metadata) }
        catch { print("[image_prompt] error: could not save provider limit evidence") }
    }
}

struct ImagePromptPersistenceFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

extension InferenceTraceRequestMetadata {
    func recordingImagePrompt(_ value: PreparedImagePrompt?) -> Self {
        guard let value else { return self }
        var result = self
        result.imagePromptPreparation = value
        if result.parentTraceId.isEmpty { result.parentTraceId = value.traceId }
        var fields = (try? JSONSerialization.jsonObject(with: Data(result.requestTextJSON.utf8))) as? [String: Any] ?? [:]
        fields["image_prompt_preparation"] = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(value.safe))) ?? [:]
        result.requestTextJSON = inferenceTraceJSONString(fields)
        return result
    }
}
