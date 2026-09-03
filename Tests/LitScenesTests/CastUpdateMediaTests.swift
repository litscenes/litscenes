import Foundation
import Testing
@testable import LitScenes

@Suite("Cast update media association")
struct CastUpdateMediaTests {
    @Test("Listed ids win; new characters inherit the turn's attachments; updates never do")
    func referenceMediaLaw() {
        var add = ProjectGoalCastUpdate(targetName: "Auri", action: "add")
        add.referenceMediaIds = ["m_face", "m_face", ""]
        #expect(castUpdateReferenceMediaIds(update: add, turnMediaIds: ["m_turn"]) == ["m_face"])

        let bareAdd = ProjectGoalCastUpdate(targetName: "Auri", action: "add")
        #expect(castUpdateReferenceMediaIds(update: bareAdd, turnMediaIds: ["m_turn", "m_turn"]) == ["m_turn"])

        let update = ProjectGoalCastUpdate(targetName: "Auri", action: "update", visualDescription: "taller")
        #expect(castUpdateReferenceMediaIds(update: update, turnMediaIds: ["m_landscape"]).isEmpty)
    }

    @Test("The sanitizer keeps only known image ids, capped at eight")
    func sanitizerFiltersUnknownIds() {
        var update = ProjectGoalCastUpdate(
            targetName: "Auri",
            action: "add",
            essence: "e", publicFunction: "f", desire: "d", operatingRule: "r", cost: "c", signature: "s",
            visualDescription: "v"
        )
        update.referenceMediaIds = ["known_1", "ghost", "known_2"] + (0..<9).map { "known_extra_\($0)" }
        var known: Set<String> = ["known_1", "known_2"]
        known.formUnion((0..<9).map { "known_extra_\($0)" })
        let result = sanitizeGoalCastChatUpdates(
            [update],
            currentCast: GoalCastDocument.empty(projectId: "p"),
            latestUserMessage: "Create Auri",
            knownImageMediaIds: known
        )
        let kept = result.updates.first?.referenceMediaIds ?? []
        #expect(kept.count == 8)
        #expect(!kept.contains("ghost"))
        #expect(kept.first == "known_1")
        #expect(result.warnings.contains { $0.contains("unknown reference media") })

        let passThrough = sanitizeGoalCastChatUpdates(
            [update],
            currentCast: GoalCastDocument.empty(projectId: "p"),
            latestUserMessage: "Create Auri"
        )
        #expect(passThrough.updates.first?.referenceMediaIds?.contains("ghost") == true)
    }

    @Test("FAL portrait overrides use only keys the stack accepts")
    func falOverridesRespectDebugKeys() throws {
        let registry = RenderStackRegistry.shared
        let nano = try #require(registry.stack(id: "fal_nano_banana_2"))
        let nanoOverrides = CharacterSheetPrompt.falParameterOverrides(stack: nano, styleMode: .attachStyleImage)
        #expect(nanoOverrides.contains("\"aspect_ratio\":\"3:4\""))
        #expect(nanoOverrides.contains("\"resolution\":\"2K\""))
        #expect(!nanoOverrides.contains("image_size"))
        let flux = try #require(registry.stack(id: "fal_flux_2_pro"))
        let fluxOverrides = CharacterSheetPrompt.falParameterOverrides(stack: flux, styleMode: .none)
        #expect(fluxOverrides.contains("\"image_size\":\"portrait_4_3\""))
        #expect(!fluxOverrides.contains("aspect_ratio"))
        let openai = try #require(registry.stack(id: "openai_base"))
        #expect(CharacterSheetPrompt.falParameterOverrides(stack: openai, styleMode: .none) == "")
    }
}
