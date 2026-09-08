import Foundation
import Testing
@testable import LitScenes

@Suite("Frame references and camera intent")
struct FrameReferenceCameraTurnTests {
    private func media(_ id: String, kind: String? = nil) -> MediaItemRecord {
        MediaItemRecord(mediaId: id, sourceId: "source", kind: .image, filename: "\(id).png", path: "/tmp/\(id).png", relativePath: "\(id).png", byteCount: 1, modifiedAt: "", width: 100, height: 100, thumbnailPath: "", scannedAt: "", derivativeKind: kind)
    }

    @Test("Structured links attach identity without mention syntax, including renamed counter-fixtures")
    func structuredIdentity() throws {
        let stack = try #require(RenderStackRegistry.shared.stack(id: RenderStackID.openAIBase))
        for name in ["Glacier Surveyor", "Ceramic Automaton"] {
            let character = RosterMentionResolver.Entry(id: "stable-id", name: name, kind: .character, referenceMediaIds: ["front", "back"], activeSheetMediaId: "sheet")
            let planned = ProjectLensHeroImage(imageId: "planned", sourcePrompt: "A character study with no mention tokens.", characterId: character.id)
            let lens = ProjectLens(lensId: "plan", heroImages: [planned])
            let items = [media("sheet", kind: "character_sheet"), media("front"), media("back")]
            let request = LensPlannedFrameDefaults.request(planned: planned, lens: lens, stack: stack, styleSlot: nil, styleCatalogVersion: "", mentionEntries: [character], mentionItems: items, fileExists: { _ in true })
            #expect(request.promptImageAttachments?.map(\.sourceId) == ["sheet"])
            let marks = scenesV2PlannedReferenceMarks(planned: planned, lens: lens, stack: stack, entries: [character], items: items, fileExists: { _ in true })
            #expect(marks.first?.avatarImagePath == request.promptImageAttachments?.first?.imagePath)
            #expect(marks.first?.hasSheet == true)
            let fallback = LensPlannedFrameDefaults.referencePlan(planned: planned, lens: lens, stack: stack, available: [character], items: items, fileExists: { !$0.contains("sheet") })
            #expect(fallback.attachments.map(\.sourceId) == ["front", "back"])
            let missing = scenesV2PlannedReferenceMarks(planned: planned, lens: lens, stack: stack, entries: [character], items: items, fileExists: { _ in false })
            #expect(missing.first?.avatarImagePath == "")
            #expect(missing.first?.referenceSummary.contains("text only") == true)
        }
    }

    @Test("Scene cast resolves through saved ids after a rename and avoids duplicate mention images")
    func sceneCastLinks() throws {
        let stack = try #require(RenderStackRegistry.shared.stack(id: RenderStackID.openAIBase))
        let character = RosterMentionResolver.Entry(id: "stable", name: "New Name", kind: .character, referenceMediaIds: ["front"])
        let planned = ProjectLensHeroImage(imageId: "scene-frame", sourcePrompt: "@New Name crosses the landscape.", sceneId: "scene")
        var lens = ProjectLens(lensId: "plan")
        var area = LensArea()
        area.areaId = "area"
        area.scenes = [LensAreaScene(sceneId: "scene", cast: [LensSceneCastEntry(name: "Former Name")])]
        lens.body.areas = [area]
        lens.body.castMembers = [LensCastMember(castId: "cast", name: "Former Name", characterId: "stable")]
        let references = LensPlannedFrameDefaults.referencePlan(planned: planned, lens: lens, stack: stack, available: [character], items: [media("front")], fileExists: { _ in true })
        #expect(references.attachments.map(\.sourceId) == ["front"])
        let merged = frameCreatorAttachmentPlan(seed: nil, direct: references.attachments, mention: references.attachments, stack: stack)
        #expect(merged.attachments.count == 1)
    }

    @Test("Legacy compass viewpoints and custom templates retain their original meaning")
    func legacyCompatibility() throws {
        let legacy = LensReframeSpec(mode: "viewpoint", centerX: 0.2, centerY: 0.8, viewDirection: "west", parentImageId: "parent", rotationDegrees: 15)
        let copy = try JSONCoding.decoder.decode(LensReframeSpec.self, from: JSONCoding.encoder.encode(legacy))
        #expect(copy.cameraTurn == nil)
        #expect(copy.viewDirection == "west")
        #expect(copy.rotationDegrees == 15)
        var settings = ProjectPromptSettingsDocument.empty()
        settings.reframePrompts = [ReframePromptTemplate(templateId: "custom", mode: "viewpoint", model: "", title: "Custom", body: "Keep this legacy compass wording.")]
        #expect(settings.reframeTemplate(mode: "viewpoint", model: "").body == "Keep this legacy compass wording.")
        #expect(settings.reframeTemplate(mode: LensCameraTurn.templateMode, model: "").body != "Keep this legacy compass wording.")
    }

    @Test("Camera angles normalize and persist independently of crop and roll")
    func cameraPersistence() throws {
        let spec = LensReframeSpec(mode: "viewpoint", centerX: 0.99, centerY: 0.01, parentImageId: "parent", rotationDegrees: 20, cameraTurn: LensCameraTurn(yawDegrees: 999, pitchDegrees: -999, operatorNotes: "Keep the weather." )).normalized()
        #expect(spec.centerX == 0.99 && spec.centerY == 0.01)
        #expect(spec.rotationDegrees == 0)
        #expect(spec.cameraTurn?.yawDegrees == 180 && spec.cameraTurn?.pitchDegrees == -90)
        let copy = try JSONCoding.decoder.decode(LensReframeSpec.self, from: JSONCoding.encoder.encode(spec))
        #expect(copy == spec)
        #expect(LensCameraTurn(yawDegrees: .nan, pitchDegrees: .infinity).normalized() == LensCameraTurn())
        #expect(LensCameraTurn(yawDegrees: 43, pitchDegrees: -18).normalized().yawDegrees == 45)
    }

    @Test("Map heading agrees with signed camera controls at source edges")
    func cameraMap() {
        for (yaw, dx, dy) in [(-90.0, -1.0, 0.0), (0, 0, -1), (90, 1, 0), (180, 0, 1)] {
            let spec = LensReframeSpec(mode: "viewpoint", centerX: 0.99, centerY: 0.01, parentImageId: "parent", cameraTurn: LensCameraTurn(yawDegrees: yaw, pitchDegrees: -45))
            let map = lensViewpointSchematicPlan(spec: spec)
            #expect(abs(map.headingVector.dx - dx) < 0.00001)
            #expect(abs(map.headingVector.dy - dy) < 0.00001)
            #expect(abs(map.vantageB.x - (map.frameRect.minX + 0.99 * map.frameRect.width)) < 0.00001)
            #expect(map.legend.joined().contains("tilt: -45°"))
        }
    }

    @Test("Controls lead the prompt and remain authoritative across unrelated scenes and long notes")
    func cameraPromptCounterFixtures() {
        let spec = LensReframeSpec(mode: "viewpoint", centerX: 0.01, centerY: 0.99, parentImageId: "parent", cameraTurn: LensCameraTurn(yawDegrees: -45, pitchDegrees: 30, operatorNotes: String(repeating: "Retain atmosphere. ", count: 500)))
        for scene in ["An ice research station at dawn.", "A miniature mechanical theater in a ceramic vessel."] {
            let parent = ProjectLensHeroImage(imageId: "parent", sourcePrompt: scene)
            let prompt = LensCameraTurn.prompt(spec: spec, parent: parent, settings: .empty(), model: "", limit: 2400)
            #expect(prompt.count <= 2400)
            #expect(prompt.hasPrefix(LensCameraTurn.instructions(spec: spec)))
            #expect(prompt.contains("45 degrees left and tilt 30 degrees up"))
            #expect(prompt.contains("1% from the source image's left edge and 99% from its top"))
            #expect(prompt.contains("Keep this selected camera position fixed"))
            #expect(prompt.contains("additional direction cannot override them"))
        }
    }
}
