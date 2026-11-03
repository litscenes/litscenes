import Foundation
import MeaningGraphCore
import Testing

// Synthetic pack: three concepts, two relationships, evidence on a node and an
// edge, two aesthetics, five terms across four facets, five assignments.
let meaningGraphTestPack = """
schema_version: litscenes.meaning_graph.v1
pack_id: test.pack
version: "1"
title: Test pack
generated_on: '2026-01-01'
license: AGPL-3.0-only
nodes:
- id: n1
  slug: symbol.lantern
  kind: symbol
  name: Lantern
  definition: A carried light.
  abstraction_level: symbolic
  positive_expression: Guidance offered.
  negative_expression: A light that misleads.
  aliases: [lamp, beacon]
  tags: [light]
  confidence_score: 0.9
  reuse_score: 0.8
- id: n2
  slug: theme.wandering
  kind: theme
  name: Wandering
  definition: Movement without a fixed destination.
  abstraction_level: thematic
  aliases: [lamp]
  confidence_score: 0.6
  reuse_score: 0.5
- id: n3
  slug: value_tension.shelter-vs-exposure
  kind: value_tension
  name: Shelter versus exposure
  definition: Safety traded against openness.
  abstraction_level: dramatic
  confidence_score: 0.7
  reuse_score: 0.7
edges:
- id: e1
  source_node_id: n1
  target_node_id: n2
  relation_type: specializes
  strength: 0.9
  confidence_score: 0.9
- id: e2
  source_node_id: n1
  target_node_id: n3
  relation_type: contrasts_with
  strength: 0.4
  confidence_score: 0.5
evidence:
- id: v1
  target_type: node
  target_id: n1
  rationale: The lantern shows guidance.
  weight: 0.8
  confidence_score: 0.8
- id: v2
  target_type: edge
  target_id: e1
  rationale: The lantern specializes wandering.
  weight: 0.5
  confidence_score: 0.5
aesthetics:
- id: a1
  slug: glow
  title: Glow
  primary_rank: 1
- id: a2
  slug: dusk
  title: Dusk
  primary_rank: 2
terms:
- id: t1
  slug: lantern-light
  display_name: lantern light
  normalized_value: lantern light
  facet_type: key_motif
- id: t2
  slug: guidance
  display_name: guidance
  normalized_value: guidance
  facet_type: key_value
- id: t3
  slug: amber
  display_name: Amber
  normalized_value: amber
  facet_type: key_colour
- id: t4
  slug: a-brand
  display_name: A Brand
  normalized_value: a brand
  facet_type: related_brand
- id: t5
  slug: quiet-road
  display_name: quiet road
  normalized_value: quiet road
  facet_type: key_motif
assignments:
- id: s1
  aesthetic_id: a1
  term_id: t1
  facet_type: key_motif
  rank: 0
  weight: 1
- id: s2
  aesthetic_id: a1
  term_id: t2
  facet_type: key_value
  rank: 1
  weight: 1
- id: s3
  aesthetic_id: a2
  term_id: t3
  facet_type: key_colour
  rank: 0
  weight: 1
- id: s4
  aesthetic_id: a2
  term_id: t1
  facet_type: key_motif
  rank: 2
  weight: 1
- id: s5
  aesthetic_id: a2
  term_id: t5
  facet_type: key_motif
  rank: 1
  weight: 1
"""

let meaningGraphTestOverlay = """
schema_version: litscenes.meaning_graph_overlay.v1
pack_id: test.overlay
version: "1"
title: Test overlay
base_pack_id: test.pack
operations:
- table: nodes
  action: add
  id: test.overlay:n4
  fields:
    slug: mood.hush
    name: Hush
    kind: mood
    definition: A quiet held breath.
- table: nodes
  action: override
  id: n2
  fields:
    name: Wandering renamed
    tags: [roam]
- table: nodes
  action: disable
  id: n3
"""

private func overlay(_ operations: String, basePackId: String = "test.pack", packId: String = "test.overlay") -> String {
    """
    schema_version: litscenes.meaning_graph_overlay.v1
    pack_id: \(packId)
    version: "1"
    title: Overlay
    base_pack_id: \(basePackId)
    operations:
    \(operations)
    """
}

private func arrayCount(_ value: GraphValue?) -> Int {
    if case .array(let items)? = value { items.count } else { -1 }
}

private func temporaryDatabase() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("meaning-core-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("graph.sqlite")
}

private func compile(_ base: String = meaningGraphTestPack, overlays: [String] = [], to url: URL = temporaryDatabase()) throws -> MeaningGraphSnapshot {
    try MeaningGraphCompiler.compile(base: base, overlays: overlays, to: url)
}

struct MeaningGraphCoreTests {
    @Test func compileRecordsCountsDegreesAndReproducibleProvenance() throws {
        let graph = try compile()
        #expect(graph.provenance.counts == ["nodes": 3, "edges": 2, "evidence": 2, "aesthetics": 2, "terms": 5, "assignments": 5])
        #expect(graph.provenance.packId == "test.pack")
        #expect(graph.provenance.baseHash == GraphCoding.hash(Data(meaningGraphTestPack.utf8)))
        let expected = GraphCoding.hash(try GraphCoding.data([MeaningGraphCompiler.resolverVersion, graph.provenance.baseHash]))
        #expect(graph.provenance.effectiveHash == expected)
        #expect(try compile().provenance == graph.provenance)
        let degrees = Dictionary(uniqueKeysWithValues: try graph.records("nodes").map { ($0.text("id"), Int($0.number("edge_degree"))) })
        #expect(degrees == ["n1": 2, "n2": 1, "n3": 1])
        #expect(try graph.records("nodes").allSatisfy { $0.text("origin_pack") == "test.pack" })
        #expect(try MeaningGraphSnapshot.open(graph.url).provenance == graph.provenance)
    }

    @Test func lookupResolvesIdThenSlugThenUnambiguousAlias() throws {
        let graph = try compile()
        #expect(try graph.node("n1")?.text("slug") == "symbol.lantern")
        #expect(try graph.node(" SYMBOL.Lantern ")?.text("id") == "n1")
        #expect(try graph.node("beacon")?.text("id") == "n1")
        #expect(try graph.node("lamp") == nil, "an alias shared by two nodes never resolves")
        #expect(try graph.node("nothing-here") == nil)
    }

    @Test func searchUsesNameAliasesTagsAndDefinitionWithReuseFallback() throws {
        let graph = try compile()
        #expect(try graph.search("lantern").first?.text("id") == "n1")
        #expect(try graph.search("roam destination").map { $0.text("id") } == ["n2"])
        #expect(try graph.search("").map { $0.text("id") } == ["n1", "n3", "n2"], "an empty query ranks by reuse")
        #expect(try graph.search("zzzz-unknown").isEmpty)
    }

    @Test func traversalOrdersByStrengthUnlessDivergent() throws {
        let graph = try compile()
        let plain = try graph.neighbors(of: "symbol.lantern")
        #expect(plain.map { $0.text("relation_type") } == ["specializes", "contrasts_with"])
        #expect(plain.first?.text("direction") == "outgoing")
        #expect(plain.first?["neighbor"]?.object.text("slug") == "theme.wandering")
        let divergent = try graph.neighbors(of: "symbol.lantern", divergent: true)
        #expect(divergent.map { $0.text("relation_type") } == ["contrasts_with", "specializes"])
        let incoming = try graph.neighbors(of: "theme.wandering")
        #expect(incoming.count == 1)
        #expect(incoming.first?.text("direction") == "incoming")
        #expect(incoming.first?["neighbor"]?.object.text("slug") == "symbol.lantern")
        #expect(try graph.neighbors(of: "missing").isEmpty)
    }

    @Test func evidenceCoversTheNodeAndItsIncidentRelationships() throws {
        let graph = try compile()
        let evidence = try graph.evidence(for: "symbol.lantern", limit: 5)
        #expect(evidence.map { $0.text("id") } == ["v1", "v2"])
        #expect(evidence.allSatisfy { $0.text("node_slug") == "symbol.lantern" })
        #expect(try graph.evidence(for: "value_tension.shelter-vs-exposure", limit: 5).isEmpty)
    }

    @Test func kindsAndPerKindTopNodes() throws {
        let graph = try compile()
        #expect(try graph.kinds() == ["symbol", "theme", "value_tension"])
        #expect(try graph.nodes(kind: "symbol", limit: 5).map { $0.text("id") } == ["n1"])
        #expect(try graph.nodes(kind: "mood", limit: 5).isEmpty)
    }

    @Test func overlayAddsOverridesAndDisablesReversibly() throws {
        let layered = try compile(overlays: [meaningGraphTestOverlay])
        #expect(layered.provenance.counts == ["nodes": 3, "edges": 1, "evidence": 2, "aesthetics": 2, "terms": 5, "assignments": 5])
        #expect(layered.provenance.overlayHashes == [GraphCoding.hash(Data(meaningGraphTestOverlay.utf8))])
        #expect(try layered.node("n3") == nil, "a disabled node is gone")
        #expect(try layered.neighbors(of: "symbol.lantern").map { $0.text("relation_type") } == ["specializes"], "its incident edge is suppressed")
        let renamed = try #require(try layered.node("n2"))
        #expect(renamed.text("name") == "Wandering renamed")
        #expect(renamed.strings("tags") == ["roam"])
        #expect(renamed.text("slug") == "theme.wandering")
        #expect(renamed.text("origin_pack") == "test.pack")
        #expect(renamed.text("modified_by") == "test.overlay")
        let added = try #require(try layered.node("mood.hush"))
        #expect(added.text("origin_pack") == "test.overlay")
        #expect(added.text("id") == "test.overlay:n4")
        #expect(try layered.kinds().contains("mood"))
        let later = overlay("- table: nodes\n  action: disable\n  id: test.overlay:n4", packId: "test.later")
        let stacked = try compile(overlays: [meaningGraphTestOverlay, later])
        #expect(try stacked.node("mood.hush") == nil, "a later layer may disable an earlier layer's addition")
        #expect(stacked.provenance.counts["nodes"] == 2)
        let restored = try compile()
        #expect(try restored.node("n3") != nil, "removing the overlay recompiles from original data")
        #expect(restored.provenance.effectiveHash != layered.provenance.effectiveHash)
    }

    @Test func overlayRejectsEveryStructuralConflict() throws {
        let rejected: [(String, [String])] = [
            ("add without namespace prefix", [overlay("- table: nodes\n  action: add\n  id: n9\n  fields: {slug: x.y, name: X, kind: theme}")]),
            ("override changing the slug", [overlay("- table: nodes\n  action: override\n  id: n2\n  fields: {slug: theme.other}")]),
            ("override replacing identity", [overlay("- table: nodes\n  action: override\n  id: n2\n  fields: {id: n7}")]),
            ("override of an absent target", [overlay("- table: nodes\n  action: override\n  id: n99\n  fields: {name: Ghost}")]),
            ("disable of an absent target", [overlay("- table: nodes\n  action: disable\n  id: n99")]),
            ("two operations on one record", [overlay("- table: nodes\n  action: disable\n  id: n3\n- table: nodes\n  action: override\n  id: n3\n  fields: {name: Twice}")]),
            ("unknown action", [overlay("- table: nodes\n  action: rename\n  id: n2\n  fields: {name: X}")]),
            ("unknown table", [overlay("- table: moods\n  action: disable\n  id: n2")]),
            ("different base pack", [overlay("- table: nodes\n  action: disable\n  id: n3", basePackId: "other.pack")]),
            ("same overlay enabled twice", [meaningGraphTestOverlay, meaningGraphTestOverlay]),
            ("added node duplicating a slug", [overlay("- table: nodes\n  action: add\n  id: test.overlay:dup\n  fields: {slug: SYMBOL.LANTERN, name: Dup, kind: symbol}")]),
            ("added edge to a missing node", [overlay("- table: edges\n  action: add\n  id: test.overlay:e9\n  fields: {source_node_id: n1, target_node_id: n99, relation_type: evokes}")]),
            ("added evidence whose node this configuration disables", [overlay("- table: nodes\n  action: disable\n  id: n3\n- table: evidence\n  action: add\n  id: test.overlay:v9\n  fields: {target_type: node, target_id: n3}")]),
            ("out-of-range score", [overlay("- table: nodes\n  action: override\n  id: n2\n  fields: {confidence_score: 1.5}")]),
            ("non-text tags", [overlay("- table: nodes\n  action: override\n  id: n2\n  fields: {tags: [1, 2]}")])
        ]
        for (reason, overlays) in rejected {
            #expect(throws: (any Error).self, "\(reason) must be rejected") { try compile(overlays: overlays) }
        }
    }

    @Test func failedCompileLeavesThePreviousDatabaseIntact() throws {
        let url = temporaryDatabase()
        let first = try compile(to: url)
        let dangling = meaningGraphTestPack.replacingOccurrences(of: "evidence:\n",
            with: "- id: e3\n  source_node_id: n1\n  target_node_id: n99\n  relation_type: evokes\nevidence:\n")
        #expect(throws: (any Error).self) { try compile(dangling, to: url) }
        let reopened = try MeaningGraphSnapshot.open(url)
        #expect(reopened.provenance == first.provenance)
        #expect(try reopened.records("edges").count == 2)
        let directory = url.deletingLastPathComponent()
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".graph-") }
        #expect(leftovers.isEmpty, "temporary build files are removed after a failure")
    }

    @Test func yamlHardeningRejectsAliasesMergeKeysDuplicatesAndBadHeaders() throws {
        #expect(throws: (any Error).self) { try MeaningGraphPack.load("schema_version: litscenes.meaning_graph.v1\na: &x 1\nb: *x") }
        #expect(throws: (any Error).self) { try MeaningGraphPack.load("schema_version: litscenes.meaning_graph.v1\nbase: &b {k: v}\nother:\n  <<: *b") }
        #expect(throws: (any Error).self) { try MeaningGraphPack.load(meaningGraphTestPack + "\ntitle: Duplicate\n") }
        #expect(throws: (any Error).self) { try MeaningGraphPack.load(meaningGraphTestPack.replacingOccurrences(of: "litscenes.meaning_graph.v1", with: "someone.else.v9")) }
        #expect(throws: (any Error).self) { try MeaningGraphPack.load(meaningGraphTestPack.replacingOccurrences(of: "pack_id: test.pack", with: "pack_id: ''")) }
        #expect(throws: (any Error).self, "every table is required, even when empty") {
            try MeaningGraphPack.load(meaningGraphTestPack.replacingOccurrences(of: "terms:\n", with: "terms_renamed:\n"))
        }
        #expect(throws: (any Error).self) { try MeaningGraphPack.load("") }
        #expect(throws: (any Error).self) { try MeaningGraphOverlay.load(meaningGraphTestPack) }
        #expect(try MeaningGraphOverlay.load(meaningGraphTestOverlay).operations.count == 3)
    }

    @Test func aestheticCandidatesNeedAGoalMatchAndTwoNonColourMatches() throws {
        let graph = try compile()
        func term(_ value: String, facet: String, source: String = "goal", weight: Double = 1) -> GraphAestheticTerm {
            GraphAestheticTerm(term: value, attributeKey: facet, source: source, weight: weight)
        }
        let matched = try graph.aestheticCandidates([term("lantern light", facet: "key_motif"), term("Guidance", facet: "key_value")])
        #expect(matched.map { $0.text("slug") } == ["glow"], "dusk shares only one non-colour term")
        #expect(matched.first?.number("match_count") == 2)
        #expect(matched.first?.number("goal_match_count") == 2)
        #expect(arrayCount(matched.first?["matched_terms"]) == 2)
        #expect(try graph.aestheticCandidates([term("lantern light", facet: "key_motif")]).isEmpty, "one term is never enough")
        #expect(try graph.aestheticCandidates([term("lantern light", facet: "key_motif", source: "media"), term("guidance", facet: "key_value", source: "media")]).isEmpty, "media-only evidence cannot propose an aesthetic")
        let colour = try graph.aestheticCandidates([term("lantern light", facet: "key_motif"), term("amber", facet: "key_colour"), term("quiet road", facet: "key_motif")])
        #expect(colour.map { $0.text("slug") } == ["dusk"], "colour counts toward the score but not the non-colour gate")
        #expect(try graph.aestheticCandidates([term("lantern light", facet: "key_motif"), term("guidance", facet: "key_value")], limit: 0).isEmpty)
        #expect(try graph.aestheticCandidates([term("nothing", facet: "key_motif")]).isEmpty)
    }

    @Test func termChoicesHonourFacetCapsRelevanceThenBreadthOfUse() throws {
        let graph = try compile()
        let caps = ["key_motif": 1, "key_value": 5, "key_colour": 5, "origin_decade": 5]
        let byUse = try graph.termChoices(query: "", caps: caps)
        #expect(byUse.map { $0.text("slug") } == ["amber", "lantern-light", "guidance"], "within a capped facet the term used by more aesthetics wins")
        #expect(!byUse.contains { $0.text("facet_type") == "related_brand" }, "facets outside the caps never appear")
        let relevant = try graph.termChoices(query: "a quiet road at dusk", caps: caps)
        #expect(relevant.first { $0.text("facet_type") == "key_motif" }?.text("slug") == "quiet-road", "a query match outranks breadth of use")
        #expect(try graph.termChoices(query: "anything", caps: ["key_motif": 0]).isEmpty)
        #expect(try graph.termChoices(query: "anything", caps: [:]).isEmpty)
        #expect(try graph.termChoices(query: "", caps: ["key_motif": 10]).count == 2)
    }
}
