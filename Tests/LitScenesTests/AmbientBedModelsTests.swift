import Foundation
import Testing
@testable import LitScenes

// MARK: - Library document

@Test func ambientBedLibraryDocumentToleratesLegacyAndSparseJSON() throws {
    let empty = try JSONCoding.decoder.decode(ProjectAmbientBedLibraryDocument.self, from: Data("{}".utf8))
    #expect(empty.beds.isEmpty)
    #expect(empty.schemaVersion == ProjectAmbientBedLibraryDocument.currentSchemaVersion)

    let sparse = try JSONCoding.decoder.decode(
        ProjectAmbientBedLibraryDocument.self,
        from: Data(#"{"project_id": "p1", "beds": [{"bed_id": "ambient_a"}, {"bed_id": ""}]}"#.utf8)
    )
    let normalized = sparse.normalized()
    #expect(normalized.projectId == "p1")
    #expect(normalized.beds.count == 1)
    #expect(normalized.beds[0].bedId == "ambient_a")
    #expect(normalized.beds[0].fileName == "ambient_a.m4a")
    #expect(normalized.beds[0].spec == AmbientBedSpec().normalized())

    // Snake-case round-trip through the house coders.
    let document = ProjectAmbientBedLibraryDocument(
        projectId: "p2",
        beds: [AmbientBedRecord(bedId: "ambient_b", displayName: "Bed", fileName: "ambient_b.caf", createdAt: "2026-07-26T00:00:00Z")]
    )
    let encoded = try JSONCoding.encoder.encode(document)
    let text = String(decoding: encoded, as: UTF8.self)
    #expect(text.contains("\"bed_id\""))
    #expect(text.contains("\"schema_version\""))
    let decoded = try JSONCoding.decoder.decode(ProjectAmbientBedLibraryDocument.self, from: encoded)
    #expect(decoded == document)
}

@Test func ambientBedLibraryNormalizedDedupesAndSorts() {
    let duplicate = ProjectAmbientBedLibraryDocument(
        projectId: "p1",
        beds: [
            AmbientBedRecord(bedId: "ambient_b", createdAt: "2026-07-26T02:00:00Z"),
            AmbientBedRecord(bedId: "ambient_a", createdAt: "2026-07-26T01:00:00Z"),
            AmbientBedRecord(bedId: "ambient_b", displayName: "later duplicate", createdAt: "2026-07-26T03:00:00Z")
        ]
    ).normalized()
    #expect(duplicate.beds.map(\.bedId) == ["ambient_a", "ambient_b"])
    #expect(duplicate.beds[1].displayName.isEmpty)
}

@Test func ambientBedUpsertReplacesSameIdAndKeepsRename() {
    let spec = AmbientBedSpec(tunerHz: 528)
    let first = AmbientBedRecord(
        bedId: "ambient_x",
        displayName: ambientBedAutoName(spec: spec),
        spec: spec,
        fileName: "ambient_x.m4a",
        durationSeconds: 60,
        createdAt: "2026-07-26T01:00:00Z",
        updatedAt: "2026-07-26T01:00:00Z"
    )
    var library = ProjectAmbientBedLibraryDocument.empty(projectId: "p1").upserting(first)
    #expect(library.beds.count == 1)

    // User renames, then re-bakes the identical spec: the rename and the
    // original createdAt survive, the count stays 1.
    library = library.renaming(bedId: "ambient_x", displayName: "Night Radio", now: "2026-07-26T02:00:00Z")
    let rebaked = AmbientBedRecord(
        bedId: "ambient_x",
        displayName: "",
        spec: spec,
        fileName: "ambient_x.m4a",
        durationSeconds: 60,
        createdAt: "2026-07-26T03:00:00Z",
        updatedAt: "2026-07-26T03:00:00Z"
    )
    library = library.upserting(rebaked)
    #expect(library.beds.count == 1)
    #expect(library.beds[0].displayName == "Night Radio")
    #expect(library.beds[0].createdAt == "2026-07-26T01:00:00Z")
    #expect(library.beds[0].updatedAt == "2026-07-26T03:00:00Z")

    library = library.removing(bedId: "ambient_x")
    #expect(library.beds.isEmpty)
}

@Test func ambientBedAutoNameDescribesTheStrongestFilters() {
    #expect(ambientBedAutoName(spec: AmbientBedSpec(tunerHz: 432, warmth: 0.6, drift: 0.5, crackle: 0, wash: 0))
        == "432.00 Hz · warm drift")
    #expect(ambientBedAutoName(spec: AmbientBedSpec(tunerHz: 110, warmth: 0.2, drift: 0.1, crackle: 0.3, wash: 0.39))
        == "110.00 Hz · pure band")
    #expect(ambientBedAutoName(spec: AmbientBedSpec(tunerHz: 528.5, warmth: 0.4, drift: 0.9, crackle: 0.8, wash: 0.41))
        == "528.50 Hz · drift crackle")
}

// MARK: - Loop math

@Test func ambientBedLoopChunkMathCoversTargetExactly() {
    let exact = ambientBedLoopChunkSeconds(bedSeconds: 30, targetSeconds: 90)
    #expect(exact == [30, 30, 30])

    let partial = ambientBedLoopChunkSeconds(bedSeconds: 60, targetSeconds: 150)
    #expect(partial == [60, 60, 30])

    let longBed = ambientBedLoopChunkSeconds(bedSeconds: 120, targetSeconds: 8)
    #expect(longBed == [8])

    let messy = ambientBedLoopChunkSeconds(bedSeconds: 7.3, targetSeconds: 41.05)
    #expect(abs(messy.reduce(0, +) - 41.05) < 1e-9)
    #expect(messy.dropLast().allSatisfy { $0 == 7.3 })

    #expect(ambientBedLoopChunkSeconds(bedSeconds: 0, targetSeconds: 10).isEmpty)
    #expect(ambientBedLoopChunkSeconds(bedSeconds: 10, targetSeconds: 0).isEmpty)
    #expect(ambientBedLoopChunkSeconds(bedSeconds: -1, targetSeconds: .nan).isEmpty)
}

// MARK: - Tuner metrics

@Test func ambientTunerSnapDetentsMagneticsAndClamp() {
    // Shift always lands on the nearest detent — nearest in log space, so the
    // boundary between 432 and 440 is their geometric midpoint (~435.98).
    #expect(ambientTunerSnappedHz(rawHz: 435.9, shiftDown: true) == 432)
    #expect(ambientTunerSnappedHz(rawHz: 436.2, shiftDown: true) == 440)

    // Inside the magnetic log band the detent captures the raw value…
    #expect(ambientTunerSnappedHz(rawHz: 432.9, shiftDown: false) == 432)
    #expect(ambientTunerSnappedHz(rawHz: 439.1, shiftDown: false) == 440)
    // …outside it, the value quantizes to the display quantum.
    #expect(ambientTunerSnappedHz(rawHz: 436.184, shiftDown: false) == 436.18)

    // Clamps and the non-finite fallback.
    #expect(ambientTunerSnappedHz(rawHz: 5, shiftDown: false) == 40)
    #expect(ambientTunerSnappedHz(rawHz: 90_000, shiftDown: false) == 8_000)
    #expect(ambientTunerSnappedHz(rawHz: .nan, shiftDown: false) == 432)
}

@Test func ambientTunerSteppingAndDetentJumps() {
    #expect(ambientTunerSteppedHz(fromHz: 432, direction: 1, stepHz: AmbientTunerMetrics.stepPlainHz) == 433)
    #expect(ambientTunerSteppedHz(fromHz: 432, direction: -1, stepHz: AmbientTunerMetrics.stepFineHz) == 431.9)
    #expect(ambientTunerSteppedHz(fromHz: 432, direction: 1, stepHz: AmbientTunerMetrics.stepHairHz) == 432.01)
    #expect(ambientTunerSteppedHz(fromHz: 40, direction: -1, stepHz: 1) == 40)
    #expect(ambientTunerSteppedHz(fromHz: 8_000, direction: 1, stepHz: 1) == 8_000)

    #expect(ambientTunerNextDetentHz(fromHz: 432, direction: 1) == 440)
    #expect(ambientTunerNextDetentHz(fromHz: 432, direction: -1) == 400)
    #expect(ambientTunerNextDetentHz(fromHz: 436, direction: 1) == 440)
    #expect(ambientTunerNextDetentHz(fromHz: 8_000, direction: 1) == 8_000)
    #expect(ambientTunerNextDetentHz(fromHz: 40, direction: -1) == 40)
}

@Test func ambientTunerRulerMappingRoundTrips() {
    #expect(ambientTunerHz(atRulerFraction: 0) == AmbientTunerMetrics.minHz)
    #expect(abs(ambientTunerHz(atRulerFraction: 1) - AmbientTunerMetrics.maxHz) < 1e-9)
    for detent in AmbientTunerMetrics.detentsHz {
        let roundTrip = ambientTunerHz(atRulerFraction: ambientTunerRulerFraction(forHz: detent))
        #expect(abs(roundTrip - detent) < AmbientTunerMetrics.displayQuantumHz)
    }
    // Non-finite input routes to the 432 fallback, matching the snap function.
    #expect(ambientTunerRulerFraction(forHz: .infinity) == ambientTunerRulerFraction(forHz: 432))
}

@Test func ambientTunerWidthFractionRoundTrips() {
    let range = AmbientBedSpec.bandwidthOctavesRange
    #expect(ambientTunerBandwidthOctaves(atWidthFraction: 0) == range.lowerBound)
    #expect(abs(ambientTunerBandwidthOctaves(atWidthFraction: 1) - range.upperBound) < 1e-9)
    for fraction in stride(from: 0.0, through: 1.0, by: 0.125) {
        let octaves = ambientTunerBandwidthOctaves(atWidthFraction: fraction)
        #expect(abs(ambientTunerWidthFraction(forBandwidthOctaves: octaves) - fraction) < 1e-9)
    }
}
