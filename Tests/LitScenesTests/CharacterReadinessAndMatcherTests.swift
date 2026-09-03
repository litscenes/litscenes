import Foundation
import Testing
@testable import LitScenes

@Suite("Character readiness band and source-image matcher")
struct CharacterReadinessAndMatcherTests {
    @Test("Readiness is silent for an empty roster or a fully sheeted one")
    func readinessSilentWhenSatisfied() {
        #expect(scenesV2CharacterSheetReadiness(characters: []) == nil)
        #expect(scenesV2CharacterSheetReadiness(characters: [("Auri", true), ("Senn", true)]) == nil)
        #expect(scenesV2CharacterSheetReadiness(characters: [("  ", false)]) == nil)
    }

    @Test("Readiness names who still renders from text")
    func readinessCopy() throws {
        let none = try #require(scenesV2CharacterSheetReadiness(characters: [("Auri", false), ("Senn", false), ("Veyr", false), ("Father Oru", false), ("Mara", false)]))
        #expect(none.headline == "No character sheets yet")
        #expect(none.detail == "Frames will render Auri, Senn, Veyr and 2 more from text alone.")
        #expect(none.missingNames.count == 5)

        let partial = try #require(scenesV2CharacterSheetReadiness(characters: [("Auri", true), ("Senn", false), ("Veyr", true), ("Mara", false)]))
        #expect(partial.headline == "2 of 4 characters have sheets")
        #expect(partial.detail == "Senn, Mara still render from text.")
    }

    @Test("Matcher requires a visible person and scores name tokens above description words")
    func matcherScoring() {
        let candidates = [
            CharacterMediaCandidate(mediaId: "portrait", peopleVisible: true, caption: "A youthful feminine character with large furry animal ears and silver-gray hair", roles: []),
            CharacterMediaCandidate(mediaId: "owl", peopleVisible: false, caption: "A mirror-tiled owl with wings spread"),
            CharacterMediaCandidate(mediaId: "gallery", peopleVisible: true, caption: "A lone person in dark clothing stands in a wood-paneled gallery", roles: ["visitor"]),
            CharacterMediaCandidate(mediaId: "named", peopleVisible: true, caption: "Auri waits by the shore", roles: []),
        ]
        let suggestions = characterSourceImageSuggestions(
            name: "Auri of the Soft Ears",
            description: "Youthful feminine hybrid with very large pale furry ears, long silver-gray hair",
            candidates: candidates,
            excluding: []
        )
        // "ears" is part of the name, so the portrait's caption earns a name hit too;
        // both real matches lead, in either order.
        #expect(Set(suggestions.prefix(2)) == ["portrait", "named"])
        #expect(!suggestions.contains("owl"))
        #expect(!suggestions.contains("gallery"))

        let excluded = characterSourceImageSuggestions(name: "Auri", description: "", candidates: candidates, excluding: ["named"])
        #expect(!excluded.contains("named"))

        let limited = characterSourceImageSuggestions(name: "Auri", description: "silver ears furry", candidates: candidates, excluding: [], limit: 1)
        #expect(limited.count == 1)

        #expect(characterSourceImageSuggestions(name: "", description: "", candidates: candidates, excluding: []).isEmpty)
    }

    @Test("Matcher stays quiet on a different project's people")
    func matcherCounterFixture() {
        let candidates = [
            CharacterMediaCandidate(mediaId: "crew", peopleVisible: true, caption: "Three engineers inspect a seawall at dawn", roles: ["engineer"]),
            CharacterMediaCandidate(mediaId: "market", peopleVisible: true, caption: "A vendor arranges jars at a batching table"),
        ]
        let suggestions = characterSourceImageSuggestions(
            name: "Kellan",
            description: "Weathered fisherman with a rope belt",
            candidates: candidates,
            excluding: []
        )
        #expect(suggestions.isEmpty)
    }
}
