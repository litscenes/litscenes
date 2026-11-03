import Foundation
import MeaningGraphCore

struct LocalMeaningSelection {
    var positive: [ProjectGoalMeaningNodeRef] = []
    var excluded: [ProjectGoalMeaningNodeRef] = []
    var warnings: [String] = []
    var excludedSlugs: Set<String> { Set(excluded.map { $0.slug.lowercased() }) }

    init(_ refs: [ProjectGoalMeaningNodeRef], graph: MeaningGraphSnapshot) throws {
        var resolved: [ProjectGoalMeaningNodeRef] = []
        for source in refs {
            var ref = source.normalized()
            if let node = try graph.node(ref.slug) {
                ref.slug = node.text("slug")
                ref.name = node.text("name")
            } else {
                warnings.append("Meaning reference \(ref.slug) is not in this graph version; its saved Goal wording remains available.")
            }
            resolved.append(ref)
        }
        var seen = Set<String>()
        excluded = resolved.filter { $0.role == .avoidance && seen.insert($0.slug.lowercased()).inserted }
        let blocked = excludedSlugs
        seen = []
        positive = resolved.filter { $0.role != .avoidance && !blocked.contains($0.slug.lowercased()) && seen.insert($0.slug.lowercased()).inserted }
    }

    static func promptExclusions(_ refs: [ProjectGoalMeaningNodeRef]) -> [[String: String]] {
        refs.map { ["slug": $0.slug, "name": String($0.name.prefix(100)), "constraint": String($0.evidence.prefix(400))] }
    }
}

enum LocalMeaningGraphResolver {
    static let schemaVersion = "litscenes.lens_context.local.v2"
    static func resolve(_ payload: LensContextResolveRequest, graph: MeaningGraphSnapshot) throws -> LensContextResolveResponse {
        let started = Date()
        var selected: [LensContextMeaningNode] = []
        var neighbors: [LensContextMeaningEdgeNeighbor] = []
        var evidence: [LensContextMeaningEvidence] = []
        var warnings: [String] = []
        var seen = Set<String>()
        var neighborQueues: [[LensContextMeaningEdgeNeighbor]] = []
        let selection = try LocalMeaningSelection(payload.meaningNodeRefs, graph: graph)
        warnings += selection.warnings
        let edgeLimit = min(max(payload.limits.meaningEdgeNeighbors, 0), 120)
        let excludedIDs = Set(try selection.excluded.compactMap { try graph.node($0.slug)?.text("id") })
        let excludedEdgeIDs = Set(try graph.records("edges").filter {
            excludedIDs.contains($0.text("source_node_id")) || excludedIDs.contains($0.text("target_node_id"))
        }.map { $0.text("id") })
        let evidenceLimit = min(max(payload.limits.meaningEvidence, 0), 40)
        for ref in selection.positive.prefix(32) {
            guard let node = try graph.node(ref.slug) else { continue }
            guard seen.insert(node.text("id")).inserted else { continue }
            selected.append(try decode(LensContextMeaningNode.self, node))
            neighborQueues.append(try graph.neighbors(of: node.text("slug"), limit: edgeLimit)
                .map { try decode(LensContextMeaningEdgeNeighbor.self, $0) }
                .filter { !selection.excludedSlugs.contains($0.neighbor.slug.lowercased()) })
            if evidence.count < evidenceLimit {
                evidence += try graph.evidence(for: node.text("slug"), limit: min(payload.limits.perNodeEvidence, evidenceLimit - evidence.count))
                    .filter { $0.text("target_type") != "edge" || !excludedEdgeIDs.contains($0.text("target_id")) }
                    .map { try decode(LensContextMeaningEvidence.self, $0) }
            }
        }
        // Each selected concept gets a turn before another consumes the budget.
        for offset in 0..<(neighborQueues.map(\.count).max() ?? 0) {
            for queue in neighborQueues where offset < queue.count && neighbors.count < edgeLimit {
                neighbors.append(queue[offset])
            }
            if neighbors.count == edgeLimit { break }
        }
        if neighbors.isEmpty && !selected.isEmpty { warnings.append("These concepts have no relationships in the selected graph. Continue with their definitions and available evidence.") }
        let terms = payload.aestheticTermRefs.filter { $0.role != .avoidance }.map { ref in
            let source = [ProjectGoalMeaningRefSource.media, .goalAndMedia].contains(ref.source) ? "media" : "goal"
            let facet = ref.facetType.rawValue
            let weight: Double
            if ref.role == .palette || facet == "key_colour" { weight = 0.2 }
            else if source == "media" { weight = 0.65 }
            else if facet == "key_value" { weight = 1.25 }
            else if facet == "key_motif" { weight = 1.15 }
            else { weight = 1 }
            return GraphAestheticTerm(term: ref.slug.isEmpty ? ref.displayName : ref.slug,
                attributeKey: facet, source: source, weight: weight)
        }
        let aesthetics = try graph.aestheticCandidates(terms, limit: payload.limits.aestheticCandidates)
            .map { try decode(LensContextAestheticCandidate.self, $0) }
        if !terms.isEmpty && aesthetics.isEmpty { warnings.append("No aesthetic meets the matching criteria; your saved style choices remain usable.") }
        var response = LensContextResolveResponse(schemaVersion: schemaVersion, userId: "local",
            projectId: payload.projectId, goalFingerprint: payload.goalFingerprint,
            selectedMeaningNodes: selected, meaningEdgeNeighbors: neighbors, meaningEvidence: evidence,
            aestheticCandidates: aesthetics, styleCandidates: [], warnings: warnings,
            queryStats: LensContextQueryStats(durationMs: Int(Date().timeIntervalSince(started) * 1000),
                meaningRefCount: payload.meaningNodeRefs.count, resolvedMeaningNodeCount: selected.count,
                meaningEdgeNeighborCount: neighbors.count, meaningEvidenceCount: evidence.count,
                aestheticTermRefCount: terms.count, aestheticCandidateCount: aesthetics.count))
        response.excludedMeaningNodeRefs = selection.excluded
        response.graphProvenance = graph.provenance
        return response
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ row: GraphRecord) throws -> T {
        try JSONCoding.decoder.decode(type, from: GraphCoding.data(row))
    }
}
