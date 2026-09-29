import Foundation
import Testing
@testable import LitScenes

@Suite("Image prompt preservation")
struct ImagePromptPreparationTests {
    static func preparation(_ prompt: String, provider: String = "fal", endpoint: String = "fal-ai/nano-banana-2/edit", managed: Bool = false) -> PreparedImagePrompt {
        PreparedImagePrompt(id: "fixture", sourcePrompt: prompt, assembledFields: ["prompt": prompt], providerFields: ["prompt": prompt],
            provider: provider, endpoint: endpoint, model: endpoint, billingSource: managed ? "go" : "personal",
            constraints: ImagePromptConstraint.resolve(provider: provider, endpoint: endpoint, model: endpoint, managed: managed),
            references: [], protectedText: [])
    }

    @Test func verifiedBoundariesAndRoutes() {
        for (length, personalValid, managedValid) in [(9_999, true, true), (10_000, true, true), (10_001, true, false), (50_000, true, false), (50_001, false, false)] {
            let text = String(repeating: "x", count: length)
            #expect(Self.preparation(text).violations.isEmpty == personalValid)
            #expect(Self.preparation(text, managed: true).violations.isEmpty == managedValid)
        }
        #expect(Self.preparation(String(repeating: "x", count: 90_000), endpoint: "fal-ai/flux-2-pro/edit").violations.isEmpty)
        #expect(Self.preparation("", endpoint: "fal-ai/image-apps-v2/outpaint").violations.isEmpty)
        let openAI = ImagePromptConstraint.resolve(provider: "openai", endpoint: "/v1/images/edits", model: "gpt-image-2", managed: false)
        #expect(openAI.first?.maximum == 32_000)
        #expect(ImagePromptConstraint.resolve(provider: "openai", endpoint: "/v1/responses", model: "gpt-image-2", managed: false).isEmpty)
    }

    @Test func unicodeCountsAndNegativeFields() {
        let constraint = ImagePromptConstraint(endpoint: "fixture", field: "prompt", maximum: 500, evidence: "fixture")
        let text = String(repeating: "e\u{301}", count: 250)
        #expect(text.count == 250)
        #expect(constraint.count(text) == 500)
        #expect(constraint.count("🧑🏽‍🚀") == 4)
        var value = Self.preparation("Unchanged sculpture.", provider: "stability", endpoint: "/v2beta/stable-image/generate/ultra")
        value.providerFields["negative_prompt"] = String(repeating: "x", count: 10_001)
        #expect(value.violations.map(\.field) == ["negative_prompt"])
    }

    @Test func fullReferenceInstructionsAndCounterFixtureSurvive() throws {
        for subject in ["A ceramic observatory with three rotating rings.", "A tailor wearing a woven coat."] {
            let manifest = (1...4).map { "\($0). reference-\($0).png — preserve the mapped subject; apply the current explicit edits." }.joined(separator: "\n")
            let prompt = subject + "\n" + String(repeating: "Detailed view. ", count: 370) + "\n" + manifest
            let value = Self.preparation(prompt)
            #expect(value.prompt == prompt)
            #expect(value.prompt.hasSuffix(manifest))
            #expect(value.violations.isEmpty)
            let renamed = Self.preparation(prompt.replacingOccurrences(of: subject, with: "Renamed subject."))
            #expect(renamed.prompt.hasSuffix(manifest))
            #expect(renamed.violations.isEmpty)
            let decoded = try JSONDecoder().decode(PreparedImagePrompt.self, from: JSONEncoder().encode(value))
            #expect(decoded == value)
            #expect(decoded.submittedFields == nil)
        }
    }

    @Test func fingerprintsIncludeReferencesRouteAndFields() {
        let value = Self.preparation("Architectural study")
        var changed = value
        changed.references = [.init(id: "reference_1", filename: "source.png", role: "subject", title: "", sha256: "hash")]
        #expect(changed.fingerprint != value.fingerprint)
        changed = value; changed.billingSource = "go"
        #expect(changed.fingerprint != value.fingerprint)
        changed = value; changed.assembledFields["prompt"] = "Revised architectural study"
        #expect(changed.fingerprint != value.fingerprint)
    }

    @Test func safeTraceRedactionDoesNotInvalidateProviderConstraintIdentity() {
        let value = Self.preparation(String(repeating: "Describe the structure. ", count: 600))
        #expect(value.safe.fingerprint == value.fingerprint)
        #expect(ImagePromptConstraint.resolve(provider: "openai", endpoint: "https://gateway.invalid/v1/images/edits", model: "gpt-image-2", managed: false).isEmpty)
    }

    @Test func workflowStorageRetainsPromptsAndReadsLegacyJobs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = InferenceTraceStore(databaseURL: directory.appendingPathComponent("traces.sqlite"))
        var job = WorkflowJob(projectId: "counter-project", projectName: "Observatory", workflow: "character_sheet", artifactType: "character", artifactId: "subject", lane: .image)
        let legacyData = try JSONEncoder().encode(job)
        #expect(try JSONDecoder().decode(WorkflowJob.self, from: legacyData).imagePrompts == nil)
        var value = Self.preparation(String(repeating: "Complete original prose. ", count: 1_000))
        value.submittedFields = value.providerFields
        job.imagePrompts = [value]
        try await store.saveWorkflow(job)
        let stored = try await store.workflows()
        #expect(stored.first?.imagePrompts == [value])
    }
}
