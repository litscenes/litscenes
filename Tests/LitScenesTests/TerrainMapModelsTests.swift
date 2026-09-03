import Foundation
import Testing
@testable import LitScenes

// The terrain map document decodes tolerantly at one frozen schema version,
// normalization enforces the one-pin-per-place and capped-history laws, and
// the provider-boundary prompts stay affirmative-form.

@Test func terrainMapDocumentDecodesEmptyJSONTolerantly() throws {
    let document = try JSONDecoder().decode(TerrainMapDocument.self, from: Data("{}".utf8))
    #expect(document.schemaVersion == TerrainMapDocument.schemaVersion)
    #expect(document.currentMediaId.isEmpty)
    #expect(!document.isSeeded)
    #expect(document.pins.isEmpty)
    #expect(document.revisions.isEmpty)
}

@Test func terrainMapDocumentToleratesUnknownKeysAndPartialPins() throws {
    let json = """
    {
        "schemaVersion": "litscenes.terrain_map.v0.1",
        "projectId": "proj_1",
        "currentMediaId": "genmedia_abc",
        "canvasWidth": 1024,
        "canvasHeight": 1024,
        "someFutureField": {"nested": true},
        "pins": [{"placeId": "place_a", "x": 1.7, "y": -0.2, "futurePinField": 3}],
        "revisions": [{"mediaId": "genmedia_abc", "operation": "seed"}]
    }
    """
    let document = try JSONDecoder().decode(TerrainMapDocument.self, from: Data(json.utf8))
    #expect(document.isSeeded)
    let pin = try #require(document.pins.first)
    // Out-of-range coordinates clamp on normalize.
    #expect(pin.x == 1)
    #expect(pin.y == 0)
    #expect(pin.regionWidth == TerrainMapPin.defaultRegionExtent)
    let revision = try #require(document.revisions.first)
    #expect(!revision.revisionId.isEmpty)
    #expect(revision.priorContentRect == CGRect(x: 0, y: 0, width: 1, height: 1))
}

@Test func terrainMapNormalizationDedupesPinsByPlace() {
    let document = TerrainMapDocument(
        projectId: "proj_1",
        pins: [
            TerrainMapPin(placeId: "place_a", x: 0.2, y: 0.2),
            TerrainMapPin(placeId: "place_a", x: 0.9, y: 0.9),
            TerrainMapPin(placeId: "", x: 0.5, y: 0.5),
            TerrainMapPin(placeId: "place_b")
        ]
    ).normalized()
    #expect(document.pins.count == 2)
    #expect(document.pins.first?.x == 0.2)
    #expect(document.pin(forPlaceId: "place_b") != nil)
}

@Test func terrainMapRevisionHistoryKeepsNewest() {
    let revisions = (0..<30).map { index in
        TerrainMapRevision(revisionId: "rev_\(index)", mediaId: "media_\(index)")
    }
    let document = TerrainMapDocument(projectId: "proj_1", revisions: revisions).normalized()
    #expect(document.revisions.count == TerrainMapDocument.maxRevisions)
    #expect(document.revisions.last?.revisionId == "rev_29")
    #expect(document.revisions.first?.revisionId == "rev_10")
}

@Test func terrainGrowthPromptsStayAffirmative() {
    // gpt-image reads negations as content vocabulary; the fixed fragments
    // state everything affirmatively (the Zoom Out preamble convention).
    let banned = ["never", "don't", "do not", "avoid", "no "]
    for fragment in [TerrainMapPrompt.openAIGrowthPreamble, TerrainMapPrompt.seedPreamble] {
        let lowered = fragment.lowercased()
        for word in banned {
            #expect(!lowered.contains(word), "banned wording \(word) in: \(fragment)")
        }
    }
    #expect(TerrainMapPrompt.openAIGrowthPreamble.contains("Top-down orthographic terrain map"))
}

@Test func terrainWirePromptCarriesOperatorBody() {
    let wire = TerrainMapPrompt.openAIWirePrompt(operatorPrompt: "  volcanic islands, ink and wash  ")
    #expect(wire.hasPrefix(TerrainMapPrompt.openAIGrowthPreamble))
    #expect(wire.hasSuffix("volcanic islands, ink and wash"))
    #expect(TerrainMapPrompt.openAIWirePrompt(operatorPrompt: "   ") == TerrainMapPrompt.openAIGrowthPreamble)
}

@Test @MainActor func terrainRegionMediaIdIsDeterministicPerProjectPlace() {
    // One id per (project, place): every crop refresh upserts the same
    // Library item instead of accumulating stale crops.
    let id = LibraryEngine.terrainRegionMediaId(projectId: "proj_1", placeId: "place_a")
    #expect(id == LibraryEngine.terrainRegionMediaId(projectId: "proj_1", placeId: "place_a"))
    #expect(id != LibraryEngine.terrainRegionMediaId(projectId: "proj_1", placeId: "place_b"))
    #expect(id != LibraryEngine.terrainRegionMediaId(projectId: "proj_2", placeId: "place_a"))
    #expect(id.hasPrefix("genmedia_"))
}

@Test func regionReferenceDescriptorNamesPlaceAndRole() {
    let descriptor = TerrainMapPrompt.regionReferenceDescriptor(
        placeName: "Saltmarsh",
        descriptor: "coastal cliffs on the northwest shore"
    )
    #expect(descriptor.contains("TOP-DOWN WORLD MAP region"))
    #expect(descriptor.contains("Saltmarsh"))
    #expect(descriptor.contains("coastal cliffs on the northwest shore"))
    #expect(descriptor.contains("geography, adjacency, and terrain context"))
    let anonymous = TerrainMapPrompt.regionReferenceDescriptor(placeName: "", descriptor: "")
    #expect(anonymous.contains("this place"))
}
