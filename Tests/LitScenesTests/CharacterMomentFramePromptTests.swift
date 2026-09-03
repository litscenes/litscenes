import Foundation
import Testing
@testable import LitScenes

private func momentScene() -> LensAreaScene {
    var setting = LensSceneSetting()
    setting.title = "Salt"
    setting.locationName = "The Salt House"
    setting.locationType = "interior"
    setting.timeOfDay = "dawn"
    setting.weather = "dry"
    setting.spatialLayout = "a low room seen from the door"
    setting.foregroundDetails = ["a ledger", "a lamp"]
    setting.backgroundDetails = ["shelves", "a shuttered window"]
    setting.notableFeatures = ["salt crust on the beams"]
    return LensAreaScene(
        sceneId: "scene_ledger",
        title: "The Ledger",
        setting: setting,
        prosePrompt: "unused when the setting is full",
        cast: [
            LensSceneCastEntry(name: "Auri", presence: "Auri tears the ledger page"),
            LensSceneCastEntry(name: "mara", presence: "watches from the door"),
            LensSceneCastEntry(name: "Nobody Real", presence: "lurks"),
        ],
        enabled: true,
        storyBeat: "turn"
    )
}

@Suite("Character-moment frame prompt law")
struct CharacterMomentFramePromptTests {
    @Test("The composed prompt is a moment with mention tokens, the place, and the closing lines — never an environment plate")
    func goldenComposition() {
        let copy = CharacterMomentFramePrompt.compose(
            characterName: "Auri",
            scene: momentScene(),
            moment: "Auri tears the ledger page",
            validCastNames: ["Auri", "Mara"],
            aspect: "landscape",
            closingLines: ["Strictly avoid: neon.", "Do not render readable text; any typography stays graphic and minimal."]
        )
        #expect(copy.label == "The Ledger · turn")
        let lines = copy.sourcePrompt.components(separatedBy: "\n")
        #expect(lines.first == "Create one wide cinematic frame of a dramatic moment.")
        #expect(lines.contains("The moment: Auri tears the ledger page."))
        // The lead's presence repeated the moment, so the cast line names them plainly.
        #expect(lines.contains("Present in this scene: @Auri. @Mara watches from the door."))
        #expect(lines.contains("The place: The Salt House — interior."))
        #expect(lines.contains("Time: dawn."))
        #expect(lines.contains("In the foreground: a ledger; a lamp."))
        #expect(lines.contains("Notable features: salt crust on the beams."))
        #expect(lines.suffix(2) == ["Strictly avoid: neon.", "Do not render readable text; any typography stays graphic and minimal."])
        #expect(copy.sourcePrompt.components(separatedBy: "@").count == 3)
        #expect(copy.sourcePrompt.range(of: "@Auri")!.lowerBound < copy.sourcePrompt.range(of: "@Mara")!.lowerBound)
        #expect(!copy.sourcePrompt.contains("Nobody Real"))
        #expect(!copy.sourcePrompt.contains("environment concept"))
        #expect(!copy.sourcePrompt.contains("unpopulated"))
        #expect(!copy.sourcePrompt.contains("Ambient set dressing"))
        #expect(copy.sourcePrompt.contains("The characters are the subject of this frame"))
    }

    @Test("Aspect drives the opener; an empty setting falls back to the prose; a blank moment is omitted")
    func openerAndFallbacks() {
        #expect(CharacterMomentFramePrompt.opener(aspect: "portrait").hasPrefix("Create one tall vertical"))
        #expect(CharacterMomentFramePrompt.opener(aspect: "square").hasPrefix("Create one square"))
        #expect(CharacterMomentFramePrompt.opener(aspect: "").hasPrefix("Create one square"))
        var scene = momentScene()
        scene.setting = LensSceneSetting()
        scene.prosePrompt = "a pier at night"
        scene.cast = []
        scene.storyBeat = ""
        let copy = CharacterMomentFramePrompt.compose(
            characterName: "Auri",
            scene: scene,
            moment: "",
            validCastNames: ["Auri"],
            aspect: "square",
            closingLines: []
        )
        #expect(copy.label == "The Ledger")
        #expect(!copy.sourcePrompt.contains("The moment:"))
        #expect(copy.sourcePrompt.contains("Present in this scene: @Auri."))
        #expect(copy.sourcePrompt.contains("The place: a pier at night"))
    }
}
