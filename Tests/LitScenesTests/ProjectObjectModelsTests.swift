import Foundation
import Testing
@testable import LitScenes

@Test
func objectSetDocumentEnforcesUniqueNamesAndRoundTrips() throws {
    var document = ProjectObjectSetDocument.empty(projectId: "project_test")
    document.objects = [
        ProjectObject(objectId: "o1", name: "Lantern", descriptionPrompt: "dented brass, cracked pane", referenceMediaIds: ["m1", "m2", "m1", ""]),
        ProjectObject(objectId: "o2", name: "lantern", descriptionPrompt: "duplicate name, dropped"),
        ProjectObject(objectId: "o3", name: "Rope Coil"),
        ProjectObject(objectId: "o4", name: "   ")
    ]
    let normalized = document.normalized()
    #expect(normalized.objects.map(\.name) == ["Lantern", "Rope Coil"])
    #expect(normalized.objects[0].referenceMediaIds == ["m1", "m2"])
    #expect(normalized.nameIsAvailable("Sextant"))
    #expect(!normalized.nameIsAvailable("LANTERN"))
    #expect(normalized.nameIsAvailable("Lantern", excludingObjectId: "o1"))
    #expect(normalized.object(withId: "o3")?.name == "Rope Coil")

    let data = try JSONCoding.encoder.encode(normalized)
    let decoded = try JSONCoding.decoder.decode(ProjectObjectSetDocument.self, from: data)
    #expect(decoded == normalized)

    // Tolerant decode of a minimal payload generates a fallback objectId.
    let minimal = try JSONCoding.decoder.decode(
        ProjectObjectSetDocument.self,
        from: Data(#"{"objects": [{"name": "Lantern"}]}"#.utf8)
    )
    #expect(minimal.objects.count == 1)
    #expect(!minimal.objects[0].objectId.isEmpty)
    #expect(minimal.schemaVersion == ProjectObjectSetDocument.schemaVersion)
}

@Test
func objectReferenceLabelsTrimPruneOrphansAndRoundTrip() throws {
    let object = ProjectObject(
        objectId: "o1",
        name: "Lantern",
        referenceMediaIds: ["m1", "m2"],
        referenceLabels: [
            "m1": "  lantern lit  ",
            "m2": "   ",            // empty label drops
            "m_gone": "orphaned"    // not a reference — prunes
        ]
    ).normalized()
    #expect(object.referenceLabels == ["m1": "lantern lit"])

    // Removing the reference prunes its label on the next normalize.
    var edited = object
    edited.referenceMediaIds = ["m2"]
    #expect(edited.normalized().referenceLabels.isEmpty)

    let data = try JSONCoding.encoder.encode(object)
    let decoded = try JSONCoding.decoder.decode(ProjectObject.self, from: data)
    #expect(decoded.referenceLabels == ["m1": "lantern lit"])

    // Legacy payloads without the key decode to an empty map.
    let legacy = try JSONCoding.decoder.decode(
        ProjectObject.self,
        from: Data(#"{"objectId": "o9", "name": "Rope", "referenceMediaIds": ["m1"]}"#.utf8)
    )
    #expect(legacy.referenceLabels.isEmpty)
}
