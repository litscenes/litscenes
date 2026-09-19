import Foundation
import Testing
@testable import LitScenes

@Test func restyleModeUsesExecutableNativeImageCapacity() throws {
    let registry = RenderStackRegistry(includeUserOverlay: false)
    let enabled = ["openai_base", "fal_flux_2_pro", "fal_nano_banana_2", "civitai_wan_2_7", "civitai_realistic_portrait"]
    let disabled = ["stability_ultra", "civitai_animagine_xl", "fal_flux_schnell"]
    for id in enabled + disabled {
        let stack = try #require(registry.stack(id: id))
        let supported = enabled.contains(id)
        #expect(stack.frameStyleMode(hasStyle: false, isRestyle: true, preferred: nil, hasPromptImages: true) == .none)
        #expect(stack.frameStyleMode(hasStyle: true, isRestyle: true, preferred: nil, hasPromptImages: true) == (supported ? .attachStyleImage : .describeStyleInPrompt))
        #expect(stack.frameStyleMode(hasStyle: true, isRestyle: false, preferred: nil, hasPromptImages: true) == .describeStyleInPrompt)
        #expect(stack.frameStyleMode(hasStyle: true, isRestyle: true, preferred: .describeStyleInPrompt, hasPromptImages: true) == .describeStyleInPrompt)
        #expect(stack.frameStyleMode(hasStyle: true, isRestyle: true, preferred: LensRenderStyleMode.none, hasPromptImages: true) == .none)
        #expect((stack.frameStyleRequestError(styleMode: .attachStyleImage, promptImageCount: 1) == nil) == supported)
        if supported, let limit = stack.nativePromptImageLimit {
            #expect(stack.frameStyleRequestError(styleMode: .attachStyleImage, promptImageCount: limit) != nil)
        }
    }
}

/// Unrelated projects exercise the same source/style contract without fixture vocabulary in production.
@Test func restyleCounterFixturesKeepSourceStyleAndReadableProvenance() async throws {
    let registry = RenderStackRegistry(includeUserOverlay: false)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("restyle-contract-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = InferenceTraceStore(databaseURL: directory.appendingPathComponent("traces.sqlite"))
    for (project, subject) in [("botanical-film", "A hillside orchard"), ("museum-study", "A ceramic vessel")] {
        let source = LensPromptImageAttachment(source: .lensRenderVersion, sourceId: project, label: subject,
            detail: variationTemplateAttachmentDescriptor(restyle: true), imagePath: "/fixture/\(project).png")
        let extras = (0..<8).map { LensPromptImageAttachment(sourceId: "extra-\($0)", label: "Reference \($0)", imagePath: "/fixture/extra-\($0).png") }
        for id in ["openai_base", "fal_flux_2_pro", "civitai_wan_2_7", "civitai_realistic_portrait"] {
            let stack = try #require(registry.stack(id: id))
            let references = frameCreatorAttachmentPlan(seed: source, direct: extras, mention: [], stack: stack, styleMode: .attachStyleImage)
            #expect(references.attachments.first?.sourceId == project)
            #expect(references.ridingCount == min(FrameReferenceCapacity.attachmentBudget, (stack.nativePromptImageLimit ?? 7) - 1))
            #expect(!references.notes.isEmpty)
            let style = LensBlendAttachmentEntry(role: .primary, roleIndex: 1, sharePercent: 100,
                reference: nil, localURL: URL(fileURLWithPath: "/fixture/style.png"), characterName: nil,
                caption: nil, attachmentFilename: "style-ref.png", promptDescriptor: "Rendering style")
            let content = LensBlendAttachmentPlan(entries: references.attachments.enumerated().map { index, item in
                LensBlendAttachmentEntry(role: .promptImage, roleIndex: index + 1, sharePercent: 0,
                    reference: nil, localURL: URL(fileURLWithPath: item.imagePath), characterName: nil,
                    caption: item.label, attachmentFilename: "source-\(index).png", promptDescriptor: item.detail)
            })
            let plan = LensBlendAttachmentPlan.combiningStyleAndPromptReferences(
                stylePlan: LensBlendAttachmentPlan(entries: [style]),
                promptPlan: content
            )
            #expect(plan.entries.first?.isStyle == true)
            #expect(plan.entries[1].localURL?.path == source.imagePath)
            #expect(plan.entries.count == references.ridingCount + 1)
            #expect(plan.manifestEntryLinesText.contains("RESTYLE SOURCE"))
            #expect(stack.frameStyleRequestError(styleMode: .attachStyleImage, promptImageCount: references.ridingCount) == nil)
            let prompt = [plan.promptPreamble, subject, plan.manifestText].joined(separator: "\n\n")
            if stack.isCivitai {
                let images = plan.entries.map(\.attachmentFilename)
                let (payload, _) = stack.civitaiPayload(prompt: prompt, requestSeed: 42, negativePrompt: "", images: images)
                let input = try #require((payload["steps"] as? [[String: Any]])?.first?["input"] as? [String: Any])
                #expect(input["images"] as? [String] == images)
                #expect(input["operation"] as? String == "editImage")
            }
            let recipe = stack.renderRecipeSnapshot(mediaPlan: LensMediaPlan(), styleMode: .attachStyleImage)
                .recordingStyleMode(.describeStyleInPrompt)
            #expect(recipe.parameters.filter { $0.key == "style_mode" }.map(\.value) == ["describe_style_in_prompt"])
            var metadata = InferenceTraceRequestMetadata(provider: stack.kind.rawValue, apiFamily: "offline-validation", operation: "restyle_contract")
            metadata.projectId = project
            metadata.runId = "\(project)-\(id)"
            metadata.traceGroupId = metadata.runId
            metadata.workflowName = "offline_restyle_contract"
            metadata.workflowStep = "reference_payload"
            metadata.artifactType = "frame"
            metadata.artifactId = source.sourceId
            metadata.model = stack.model
            metadata.requestTextJSON = inferenceTraceJSONString(["prompt": prompt, "style_mode": "attach_style_image"])
            metadata.mediaRefsJSON = inferenceTraceJSONString(["images": plan.entries.map { ["role": $0.role.rawValue, "filename": $0.attachmentFilename] }])
            let request = URLRequest(url: URL(string: "https://example.invalid/offline-validation")!)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)
            let trace = await store.record(request: request, metadata: metadata, response: response, responseBody: Data("{}".utf8), latencyMs: 1)
            let detail = try await store.workflowTraceDetails(ids: [trace])
            #expect(detail.contains(subject))
            #expect(detail.contains("style-ref.png"))
            #expect(detail.contains("attach_style_image"))
            let failed = await store.record(request: request, metadata: metadata, response: nil, responseBody: nil, latencyMs: 1, error: CancellationError())
            #expect(try await store.workflowTraceRecords(ids: [failed]).count == 1)
        }
    }
}
