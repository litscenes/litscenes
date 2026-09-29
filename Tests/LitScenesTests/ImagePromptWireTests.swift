import Foundation
import Testing
@testable import LitScenes

private actor CapturedImageRequests {
    var prompts: [String: String] = [:]
    func save(id: String, prompt: String) { prompts[id] = prompt }
}

private final class ImagePromptOfflineProtocol: URLProtocol, @unchecked Sendable {
    static let captured = CapturedImageRequests()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var bytes = request.httpBody ?? Data()
        if bytes.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
            stream.close()
        }
        let body = ((try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]) ?? [:]
        let prompt = body["prompt"] as? String ?? ""
        let path = request.url!.path
        var status = 200
        let response: [String: Any]
        if path.hasSuffix("/responses"),
           let input = body["input"] as? [[String: Any]],
           let user = input.last?["content"] as? [[String: Any]],
           let text = user.first?["text"] as? String,
           let context = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
           let sections = context["sections"] as? [[String: Any]] {
            let output: [String: Any] = ["sections": sections.filter { $0["locked"] as? Bool == false }.map {
                ["id": $0["id"] as? String ?? "", "text": "A weather station. "]
            }, "summary": "Removed repeated descriptions while keeping the reference binding."]
            let json = String(decoding: try! JSONSerialization.data(withJSONObject: output), as: UTF8.self)
            response = ["id": "fixture-rewrite", "model": body["model"] as? String ?? "fixture", "status": "completed",
                "output": [["type": "message", "role": "assistant", "content": [["type": "output_text", "text": json]]]],
                "usage": ["input_tokens": 100, "output_tokens": 30, "total_tokens": 130]]
        } else if path.contains("images/generations") {
            response = ["model": "gpt-image-2", "data": [["b64_json": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==", "revised_prompt": prompt]]]
        } else if path.hasSuffix("/status") {
            response = ["status": "COMPLETED"]
        } else if path.hasSuffix("/result") {
            status = 422
            response = ["detail": [["loc": ["body", "prompt"], "type": "no_media_generated", "msg": "Offline fixture: no image output."]]]
        } else if path.contains("nano-banana-2") {
            let id = "fixture-" + String(sha256Hex(bytes).prefix(16))
            response = ["request_id": id, "status_url": "https://fixture.invalid/\(id)/status", "response_url": "https://fixture.invalid/\(id)/result"]
        } else {
            status = 400
            response = ["error": ["code": "unexpected_fixture_request", "message": "This offline fixture permits only the intended image request."]]
        }
        let payload = try! JSONSerialization.data(withJSONObject: response)
        let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json", "x-request-id": "fixture-request"])!
        let id = response["request_id"] as? String ?? ""
        Task {
            if !id.isEmpty { await Self.captured.save(id: id, prompt: prompt) }
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: payload)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private struct ImageFixtureCredentials: LitScenesCredentialResolving {
    func resolvedCredential(for provider: LitScenesProviderCredential) -> String { "offline-fixture" }
    func resolvedCredentialValue(forKey key: String) -> String { "offline-fixture" }
    func resolvedCredentialValue(forKeys keys: [String]) -> String { "offline-fixture" }
    func credentialStatus(for provider: LitScenesProviderCredential) -> CredentialStatus {
        .init(provider: provider, source: .environment, isConfigured: true, message: "Offline fixture")
    }
    func lensContextCredentialStatus(for credential: LensContextCredential) -> LensContextCredentialStatus {
        .init(credential: credential, source: .missing, isConfigured: false, message: "Offline fixture")
    }
}

@Suite("Offline image wire and trace provenance")
struct ImagePromptWireTests {
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ImagePromptOfflineProtocol.self]
        return URLSession(configuration: config)
    }

    @Test(arguments: ["A ceramic observatory with rotating rings.", "A tailor with a woven coat."])
    func falReceivesWholePromptAndRetainsResultFailure(subject: String) async throws {
        let manifest = (1...4).map { "\($0). reference-\($0).png — subject identity evidence, preserving the current explicit edits." }.joined(separator: "\n")
        let padding = String(repeating: "x", count: 5145 - subject.unicodeScalars.count - manifest.unicodeScalars.count - 2)
        let prompt = subject + "\n" + padding + "\n" + manifest
        let yaml = try String(contentsOf: packagedResourceURL(named: "render_stacks", extension: "yaml"), encoding: .utf8)
        let stack = try #require(RenderStackRegistry.decodeStacks(yamlText: yaml, source: "fixture").first { $0.id == RenderStackID.falNanoBanana2 })
        let session = session()
        defer { session.invalidateAndCancel() }
        try await ProviderBilling.$snapshot.withValue(.init(defaultSource: .personal, overrides: [:])) {
            try await TracedHTTPTransport.$session.withValue(session) {
                do {
                    _ = try await FALImageClient(credentialStore: ImageFixtureCredentials()).generateImage(from: .init(
                        artifactId: "wire-fixture", stack: stack, prompt: prompt, mediaPlan: .init(), styleMode: .attachStyleImage,
                        styleReferences: (1...4).map { .init(data: Data([1, 2, 3]), mimeType: "image/png", fileName: "reference-\($0).png", role: "subject") },
                        projectId: "image-prompt-wire-fixture", runId: "wire-" + String(sha256Hex(Data(subject.utf8)).prefix(8)), workflowName: "image_prompt_wire_fixture"))
                    Issue.record("The fixture should report the provider's result-retrieval error")
                } catch let error as FALWorkflowFailure {
                    let captured = await ImagePromptOfflineProtocol.captured.prompts[error.jobId]
                    #expect(captured == prompt)
                    #expect(captured?.unicodeScalars.count == 5145)
                    #expect(!error.traceId.isEmpty && !error.jobId.isEmpty)
                    #expect(error.message.contains("HTTP 422"))
                    let traces = try await InferenceTraceStore.shared.workflowTraceRecords(ids: [error.traceId])
                    #expect(traces.first?.rawJSON.contains("no_media_generated") == true)
                    #expect(traces.first?.rawJSON.contains("422") == true)
                }
            }
        }
    }

    @Test func openAIReturnsTheActualTransmittedText() async throws {
        let prompt = "A nonhuman weather station.\n" + String(repeating: "Retain all visible structure. ", count: 220) + "\n4. final-reference.png — this final instruction must survive."
        let session = session()
        defer { session.invalidateAndCancel() }
        let result = try await TracedHTTPTransport.$session.withValue(session) {
            try await OpenAIClient(apiKey: "offline-fixture").generateProofImage(prompt: prompt,
                projectId: "image-prompt-wire-fixture", runId: "openai-wire-fixture", traceWorkflowName: "image_prompt_wire_fixture", traceArtifactId: "weather-station")
        }
        #expect(result.transmittedPrompt == prompt)
        #expect(result.revisedPrompt == prompt)
        #expect(!result.traceId.isEmpty)
    }
    @Test func structuredShorteningHasReadableParentAndOutputTraces() async throws {
        let binding = "4. weather-station.png — subject identity evidence."
        let prompt = String(repeating: "A weather station with repeated structural details. ", count: 30) + "\n" + binding
        var original = ImagePromptPreparationTests.preparation(prompt, endpoint: "fal-ai/image-apps-v2/outpaint")
        original.protectedText = [binding]
        var metadata = InferenceTraceRequestMetadata(provider: "openai", apiFamily: "responses", operation: "image_prompt_shortening")
        metadata.projectId = "image-prompt-wire-fixture"
        metadata.runId = "shortening-wire-fixture"
        metadata.traceGroupId = "shortening-wire-fixture"
        metadata.workflowName = "image_prompt_wire_fixture"
        metadata.artifactType = "image"
        metadata.artifactId = "weather-station-shortened"
        try await ImagePromptPreparation.persist(&original, metadata: metadata)
        let parent = original.traceId
        let session = session()
        defer { session.invalidateAndCancel() }
        let scoped = metadata
        let result = try await TracedHTTPTransport.$session.withValue(session) {
            try await ImagePromptShortening.shorten(original, rewrite: {
                try await OpenAIClient(apiKey: "offline-fixture").shortenImagePrompt($0, metadata: scoped)
            }, record: {
                var value = $0
                try await ImagePromptPreparation.persist(&value, metadata: scoped)
            })
        }
        #expect(result.wasShortened && result.violations.isEmpty)
        #expect(result.prompt.contains(binding))
        #expect(result.rewriteTraceIds.count == 1)
        let traces = try await InferenceTraceStore.shared.workflowTraceRecords(ids: result.rewriteTraceIds)
        #expect(traces.first?.rawJSON.contains(parent) == true)
        #expect(traces.first?.rawJSON.contains("fixture-rewrite") == true)
        #expect(traces.first?.rawJSON.contains("Removed repeated descriptions") == true)
    }

    @Test func cancellationBeforePreparationReturnsIsPersisted() async throws {
        let capture = ImagePromptCapture()
        let task = Task {
            try await ImagePromptContext.$capture.withValue(capture) {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await ImagePromptPreparation.prepare(fields: ["prompt": "A ceramic observatory."],
                    provider: "fal", endpoint: "fal-ai/nano-banana-2", model: "fal-ai/nano-banana-2",
                    metadata: .init(provider: "fal", apiFamily: "image_prompt", operation: "canceled_image_prompt_fixture"))
            }
        }
        do { _ = try await task.value; Issue.record("Canceled preparation must not execute") }
        catch is CancellationError { }
        let preparation = await capture.latest
        #expect(preparation?.state == "canceled")
        #expect(preparation?.submittedFields == nil)
        #expect(preparation?.sourcePrompt == "A ceramic observatory.")
    }

}
