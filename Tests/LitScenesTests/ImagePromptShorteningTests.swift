import Foundation
import Testing
@testable import LitScenes

private actor RewriteRequests {
    var requests: [ImagePromptRewriteRequest] = []
    func append(_ request: ImagePromptRewriteRequest) { requests.append(request) }
}

@Suite("Bounded image prompt shortening")
struct ImagePromptShorteningTests {
    private func oversized(maximum: Int = 120) -> PreparedImagePrompt {
        var value = ImagePromptPreparationTests.preparation(String(repeating: "A ceramic observatory with rotating rings. ", count: 50))
        value.constraints = [.init(endpoint: value.endpoint, field: "prompt", maximum: maximum, evidence: "fixture schema")]
        return value
    }

    private static func response(_ request: ImagePromptRewriteRequest, text: String = "A ceramic observatory with rotating rings.") throws -> ImagePromptRewriteResult {
        let output = ImagePromptRewriteOutput(sections: request.sections.filter { !$0.locked }.map { .init(id: $0.id, text: text) }, summary: "Removed repeated descriptions.")
        return .init(rawText: String(decoding: try JSONEncoder().encode(output), as: UTF8.self), traceId: "fixture-rewrite-\(request.attempt)", model: "fixture")
    }

    @Test func fittingPromptsNeverInvokeRewriter() async throws {
        let value = ImagePromptPreparationTests.preparation("A complete architectural study.")
        let requests = RewriteRequests()
        let result = try await ImagePromptShortening.shorten(value, rewrite: { request in
            await requests.append(request)
            return try Self.response(request)
        })
        #expect(result == value)
        #expect(await requests.requests.isEmpty)
    }

    @Test func preservesBindingsGeometryLayoutAndUntouchedFields() async throws {
        let geometry = "Camera yaw 35 degrees right; pitch 10 degrees up."
        let layout = "Layout: eight labeled views in one reference sheet."
        let binding = "1. reference.png — reference_sheet for \"Observatory\": "
        var value = oversized(maximum: 400)
        let prompt = geometry + "\n" + value.prompt + "\n" + layout + "\n" + binding + "Established identity evidence."
        value.sourcePrompt = prompt
        value.assembledFields = ["prompt": prompt, "negative_prompt": "Exclude moving vehicles."]
        value.providerFields = value.assembledFields
        value.protectedText = [geometry, layout, binding]
        value.references = [.init(id: "reference_1", filename: "reference.png", role: "prompt_image", title: "Observatory", sha256: "fixture-hash", binding: binding, purpose: .referenceSheet)]
        let result = try await ImagePromptShortening.shorten(value, rewrite: { request in
            #expect(request.budgets["prompt"] == 400 - geometry.unicodeScalars.count - layout.unicodeScalars.count - binding.unicodeScalars.count)
            #expect(request.sections.contains { $0.referenceId == "reference_1" && !$0.locked })
            return try Self.response(request, text: "\nCeramic form; rotating rings.\n")
        })
        #expect(result.wasShortened)
        #expect(result.prompt.contains(geometry) && result.prompt.contains(layout) && result.prompt.contains(binding))
        #expect(result.sourcePrompt == prompt && result.references == value.references)
        #expect(result.providerFields["negative_prompt"] == value.providerFields["negative_prompt"])
        #expect(result.violations.isEmpty)
    }

    @Test(arguments: ["malformed", "missing", "duplicate", "oversized"])
    func exactlyOneCorrection(reason: String) async throws {
        let value = oversized()
        let requests = RewriteRequests()
        let result = try await ImagePromptShortening.shorten(value, rewrite: { request in
            await requests.append(request)
            if request.attempt == 2 {
                #expect(!request.feedback.isEmpty && !request.previousOutput.isEmpty)
                return try Self.response(request)
            }
            switch reason {
            case "malformed": return .init(rawText: "invalid JSON", traceId: "first", model: "fixture")
            case "missing": return .init(rawText: #"{"sections":[],"summary":"missing"}"#, traceId: "first", model: "fixture")
            case "duplicate":
                let id = request.sections.first(where: { !$0.locked })!.id
                let output = ImagePromptRewriteOutput(sections: [.init(id: id, text: "A"), .init(id: id, text: "B")], summary: "Duplicate")
                return .init(rawText: String(decoding: try JSONEncoder().encode(output), as: UTF8.self), traceId: "first", model: "fixture")
            default: return try Self.response(request, text: String(repeating: "Still oversized. ", count: 60))
            }
        })
        #expect(await requests.requests.count == 2)
        #expect(result.violations.isEmpty && result.rewriteTraceIds.count == 2)
        #expect(result.sourcePrompt == value.sourcePrompt)
    }

    @Test func secondInvalidOutputStopsWithoutClipping() async {
        let value = oversized()
        let requests = RewriteRequests()
        do {
            _ = try await ImagePromptShortening.shorten(value, rewrite: { request in
                await requests.append(request)
                return try Self.response(request, text: value.prompt)
            })
            Issue.record("An invalid second response must stop before image submission")
        } catch {
            #expect(error is ImagePromptRewriteValidationError)
            #expect(await requests.requests.count == 2)
            #expect(value.sourcePrompt == value.prompt && value.submittedFields == nil)
        }
    }

    @Test func unavailableTextProviderDoesNotTriggerCorrection() async {
        let requests = RewriteRequests()
        do {
            _ = try await ImagePromptShortening.shorten(oversized(), rewrite: { request in
                await requests.append(request)
                throw ScreenGraphError.missingAPIKey
            })
            Issue.record("Missing text credentials must remain recoverable")
        } catch { #expect(await requests.requests.count == 1) }
    }

    @Test func impossibleFixedStructureStopsBeforeTextSpend() async {
        var value = oversized(maximum: 5)
        value.protectedText = [value.prompt]
        let requests = RewriteRequests()
        do {
            _ = try await ImagePromptShortening.shorten(value, rewrite: { request in
                await requests.append(request)
                return try Self.response(request)
            })
            Issue.record("Fixed structure must not be rewritten")
        } catch { #expect(await requests.requests.isEmpty) }
    }

    @Test func cancellationAfterPreparationDoesNotReturnAnExecutableResult() async {
        let value = oversized()
        let task = Task {
            try await ImagePromptShortening.shorten(value, rewrite: { request in try Self.response(request) }, record: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }
        do { _ = try await task.value; Issue.record("Canceled preparation must not reach image submission") }
        catch { #expect(error is CancellationError) }
    }

    @Test func explicitLengthEvidenceOnly() {
        let explicit = Data(#"{"detail":[{"loc":["body","prompt"],"type":"string_too_long","ctx":{"max_length":8500},"msg":"too long"}]}"#.utf8)
        #expect(ImagePromptPreparation.observedConstraints(data: explicit, endpoint: "fixture", traceId: "trace").first?.maximum == 8500)
        for text in [#"{"detail":"The model did not generate an image. Prompt length or safety may be involved."}"#,
                     #"{"detail":[{"loc":["body","prompt"],"type":"no_media_generated","ctx":{"max_length":8500}}]}"#,
                     #"{"detail":[{"loc":["body","image_urls"],"type":"string_too_long","ctx":{"max_length":8500}}]}"#] {
            #expect(ImagePromptPreparation.observedConstraints(data: Data(text.utf8), endpoint: "fixture", traceId: "trace").isEmpty)
        }
    }

    @Test func validRewriteSurvivesRestartAndNewPreparation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("traces.sqlite")
        let store = InferenceTraceStore(databaseURL: path)
        let original = oversized()
        var ready = try await ImagePromptShortening.shorten(original, rewrite: { request in try Self.response(request) })
        ready.inputFingerprint = ready.fingerprint
        var old = WorkflowJob(projectId: "counter-project", projectName: "Architecture", workflow: "frame", artifactType: "frame", artifactId: "first", lane: .image)
        old.imagePrompts = [ready]
        try await store.saveWorkflow(old)
        var next = old
        next.id = "new-preparation"
        var unshortened = original
        unshortened.inputFingerprint = unshortened.fingerprint
        unshortened.state = "over_limit"
        next.imagePrompts = [unshortened]
        try await store.saveWorkflow(next)
        let reopened = InferenceTraceStore(databaseURL: path)
        let cached = try await reopened.cachedImagePrompt(fingerprint: original.fingerprint, projectId: old.projectId)
        #expect(cached?.providerFields == ready.providerFields)
        #expect(try await reopened.cachedImagePrompt(fingerprint: original.fingerprint, projectId: "different-project") == nil)
        var changed = original; changed.billingSource = "go"
        #expect(try await reopened.cachedImagePrompt(fingerprint: changed.fingerprint, projectId: old.projectId) == nil)
    }

    @Test func referenceRenameDoesNotAlterGenericShorteningBehavior() async throws {
        for name in ["Stone Observatory", "Glass Surveyor"] {
            var value = oversized(maximum: 100)
            let binding = "1. source.png — source_image for \"\(name)\": "
            value.assembledFields["prompt"] = binding + value.prompt
            value.providerFields = value.assembledFields
            value.protectedText = [binding]
            value.references = [.init(id: "reference_1", filename: "source.png", role: "prompt_image", title: name, sha256: "hash", binding: binding, purpose: .sourceImage)]
            let result = try await ImagePromptShortening.shorten(value, rewrite: { request in try Self.response(request, text: "Visible structural details.") })
            #expect(result.prompt == binding + "Visible structural details.")
            #expect(result.violations.isEmpty)
        }
    }
}
