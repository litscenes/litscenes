import Foundation
import Testing
@testable import LitScenes

// The cross-project analysis memory answers by the vision input's hash and, since
// copied sources may re-encode their thumbnails, by the original file's hash too.

private func memoryObservation(visionSha: String, sourceSha: String, caption: String) -> ImageObservationResult {
    var observation = ImageObservationResult()
    observation.mediaId = "media_x"
    observation.plainCaption = caption
    observation.visionInputKind = "thumbnail_base"
    observation.visionInputSha256 = visionSha
    observation.sourceImageSha256 = sourceSha
    observation.createdAt = "2026-01-01T00:00:00Z"
    return observation
}

@Suite("Media analysis memory")
struct MediaAnalysisMemoryStoreTests {
    @Test("Observations load by vision hash and fall back to the source hash")
    func lookupByBothKeys() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("litscenes_analysis_memory_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var store = MediaAnalysisMemoryStore()
        store.databaseURL = root.appendingPathComponent("memory.db")

        let observation = memoryObservation(visionSha: "vision_a", sourceSha: "source_a", caption: "a person on a pier")
        let key = MediaAnalysisMemoryKey.current(visionInputSha256: "vision_a")
        try store.saveObservation(observation, for: key, sourceSha256: "source_a")

        #expect(try store.loadObservation(for: key)?.plainCaption == "a person on a pier")
        #expect(try store.loadObservation(sourceSha256: "source_a")?.plainCaption == "a person on a pier")
        #expect(try store.loadObservation(sourceSha256: "source_other") == nil)
        #expect(try store.loadObservation(sourceSha256: "") == nil)
        #expect(try store.loadObservation(for: MediaAnalysisMemoryKey.current(visionInputSha256: "vision_other")) == nil)

        // A later save without a source hash keeps the one already on record.
        try store.saveObservation(observation, for: key)
        #expect(try store.loadObservation(sourceSha256: "source_a") != nil)

        // Bootstrapping a project's observations carries their source hashes along.
        var bootstrapped = memoryObservation(visionSha: "vision_b", sourceSha: "source_b", caption: "a market stall")
        bootstrapped.mediaId = "media_b"
        let imported = try store.bootstrapNeutralObservations(["media_b": bootstrapped])
        #expect(imported == 1)
        #expect(try store.loadObservation(sourceSha256: "source_b")?.plainCaption == "a market stall")
    }
}
