import Foundation
import Testing
@testable import LitScenes

@Suite("Project prompt settings round-trip")
struct ProjectPromptSettingsRoundTripTests {
    @Test("An edited template survives the house JSON coder")
    func editedTemplateSurvivesRoundTrip() throws {
        var document = ProjectPromptSettingsDocument.empty(projectId: "p1").normalized(projectId: "p1")
        let index = try #require(document.reframePrompts.firstIndex { $0.mode == LensReframeSpec.zoomMode && $0.isFallback })
        document.reframePrompts[index].body = "Operator zoom body — keep me."
        let encoded = try JSONCoding.encoder.encode(document)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains("\"reframe_prompts\""))
        let decoded = try JSONCoding.decoder.decode(ProjectPromptSettingsDocument.self, from: encoded)
        let restored = decoded.normalized(projectId: "p1")
        #expect(restored.reframeTemplate(mode: LensReframeSpec.zoomMode, model: "").body == "Operator zoom body — keep me.")
        #expect(restored.projectId == "p1")
    }

    @Test("The on-disk snake_case shape decodes")
    func onDiskShapeDecodes() throws {
        let json = """
        {"schema_version":"litscenes.project_prompt_settings.v0.1","project_id":"p1","updated_at":"2026-01-01T00:00:00Z",
         "reframe_prompts":[{"template_id":"reframe:zoom:fallback","workflow":"reframe","mode":"zoom","model":"","title":"Zoom fallback","body":"Saved zoom body.","updated_at":"2026-01-01T00:00:00Z"}]}
        """
        let decoded = try JSONCoding.decoder.decode(ProjectPromptSettingsDocument.self, from: Data(json.utf8))
        #expect(decoded.projectId == "p1")
        #expect(decoded.reframeTemplate(mode: LensReframeSpec.zoomMode, model: "").body == "Saved zoom body.")
    }
}
