import Foundation
import MeaningGraphCore
import Testing
@testable import LitScenes

// Desktop-side graph runtime: sources by content hash with legacy migration,
// bundled selection reuse, overlay compilation through the shared store, and
// the curated Goal choice packet.

struct MeaningGraphRuntimeTests {
    @Test func legacySourceDocumentsMigrateInlineYAMLIntoTheSharedStore() throws {
        let hash = GraphCoding.hash(Data(meaningGraphTestPack.utf8))
        let legacy = try JSONSerialization.data(withJSONObject: [
            "schema_version": "litscenes.project_meaning_graph.v1",
            "base": ["hash": hash, "pack_id": "test.pack", "version": "1", "title": "Test pack", "kind": "base", "yaml": meaningGraphTestPack],
            "overlays": []
        ])
        var selection = try JSONCoding.decoder.decode(ProjectMeaningGraphSelection.self, from: legacy)
        #expect(selection.base.legacyYAML == meaningGraphTestPack)
        #expect(try selection.migrateLegacySources() == true)
        #expect(selection.base.legacyYAML == nil)
        #expect(try selection.migrateLegacySources() == false)
        #expect(MeaningGraphSourceStore.isAvailable(selection.base))
        #expect(try MeaningGraphSourceStore.yaml(for: selection.base) == meaningGraphTestPack)
        let encoded = try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(selection)) as? [String: Any]
        let base = encoded?["base"] as? [String: Any]
        #expect(base?["yaml"] == nil, "project documents carry identity only")
        #expect(base?["hash"] as? String == hash)
        var tampered = selection.base
        tampered.hash = String(repeating: "0", count: 64)
        #expect(throws: (any Error).self, "an uninstalled source is reported, never guessed") { try MeaningGraphSourceStore.yaml(for: tampered) }
        #expect(throws: (any Error).self) { try MeaningGraphSourceStore.store(yaml: meaningGraphTestPack, hash: tampered.hash) }
    }

    @Test func bundledSelectionReusesTheShippedDatabaseWithoutReadingYAML() async throws {
        let bundled = try MeaningGraphSource.bundled()
        #expect(bundled.kind == "base")
        #expect(bundled.legacyYAML == nil)
        let snapshot = try await MeaningGraphRuntime.shared.snapshot(ProjectMeaningGraphSelection(base: bundled))
        #expect(snapshot.provenance == (try MeaningGraphSourceStore.bundledProvenance()))
        #expect(snapshot.url == (try MeaningGraphSourceStore.bundledDatabaseURL()))
        #expect(try await MeaningGraphRuntime.shared.snapshot(nil).provenance == snapshot.provenance)
    }

    @Test func installedSourcesCompileOverlaysThroughTheStore() async throws {
        let base = try MeaningGraphSource.parse(Data(meaningGraphTestPack.utf8))
        let overlay = try MeaningGraphSource.parse(Data(meaningGraphTestOverlay.utf8))
        try await MeaningGraphRuntime.shared.install(base.source, yaml: base.yaml)
        try await MeaningGraphRuntime.shared.install(overlay.source, yaml: overlay.yaml)
        let installed = try await MeaningGraphRuntime.shared.installedSources()
        #expect(installed.contains { $0.hash == base.source.hash && $0.kind == "base" })
        #expect(installed.contains { $0.hash == overlay.source.hash && $0.kind == "overlay" })
        var selection = ProjectMeaningGraphSelection(base: base.source, overlays: [MeaningGraphLayer(source: overlay.source)])
        let layered = try await MeaningGraphRuntime.shared.snapshot(selection)
        #expect(layered.provenance.counts["nodes"] == 3)
        #expect(try layered.node("mood.hush") != nil)
        #expect(layered.provenance.effectiveHash == selection.effectiveHash)
        selection.overlays[0].enabled = false
        let plain = try await MeaningGraphRuntime.shared.snapshot(selection)
        #expect(try plain.node("mood.hush") == nil)
        #expect(try plain.node("n3") != nil)
        #expect(plain.provenance.effectiveHash == selection.effectiveHash)
        let preview = try await MeaningGraphRuntime.shared.preview(ProjectMeaningGraphSelection(base: base.source, overlays: [MeaningGraphLayer(source: overlay.source)]), replacing: selection)
        #expect(preview.changes.contains("Nodes: 1 added, 2 changed, 1 disabled or removed"), "the override and the degree lost with the suppressed edge")
        #expect(preview.changes.contains("Edges: 0 added, 0 changed, 1 disabled or removed"))
        await #expect(throws: (any Error).self, "an overlay cannot stand in for a base") {
            try await MeaningGraphRuntime.shared.snapshot(ProjectMeaningGraphSelection(base: overlay.source))
        }
    }

    @Test func goalChoiceContextCapsFacetsAndCoversEveryKind() async throws {
        let graph = try await MeaningGraphRuntime.shared.snapshot(nil)
        let motif = try #require(try graph.records("terms").first {
            $0.text("facet_type") == "key_motif" && $0.text("normalized_value").count > 3 && !$0.text("normalized_value").contains(" ")
        })
        let json = try await MeaningGraphRuntime.shared.choiceContext(selection: nil,
            query: "a story about \(motif.text("normalized_value")) at the shore", selectedSlugs: [], termCaps: MeaningGraphRuntime.goalTermCaps)
        let packet = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(packet["index_version"] as? String == graph.provenance.effectiveHash)
        let terms = try #require(packet["aesthetic_term_choices"] as? [[String: Any]])
        let perFacet = Dictionary(grouping: terms) { $0["facet_type"] as? String ?? "" }
        for (facet, rows) in perFacet {
            let cap = try #require(MeaningGraphRuntime.goalTermCaps[facet], "only Goal facets are offered, not \(facet)")
            #expect(rows.count <= cap)
        }
        #expect(perFacet.keys.count == MeaningGraphRuntime.goalTermCaps.count, "every Goal facet is represented")
        #expect(terms.contains { $0["slug"] as? String == motif.text("slug") }, "a term named in the conversation is offered")
        #expect(terms.allSatisfy { ($0["facet_type"] as? String) != "related_brand" })
        let nodes = try #require(packet["meaning_node_choices"] as? [[String: Any]])
        let perKind = Dictionary(grouping: nodes) { $0["kind"] as? String ?? "" }
        for kind in try graph.kinds() {
            let available = try graph.nodes(kind: kind, limit: 3).count
            #expect((perKind[kind]?.count ?? 0) >= min(3, available), "kind \(kind) stays visible")
        }
        #expect(nodes.count <= 64 + 32 + 3 * perKind.count)
        #expect(nodes.allSatisfy { ($0["slug"] as? String)?.isEmpty == false && ($0["definition"] as? String) != nil })
    }
}
