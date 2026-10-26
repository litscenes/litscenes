import Foundation
import MeaningGraphCore

enum LocalMeaningGraphResolver {
    static func resolve(_ payload: LensContextResolveRequest, graph: MeaningGraphSnapshot) throws -> LensContextResolveResponse {
        let started = Date()
        var selected: [LensContextMeaningNode] = []
        var neighbors: [LensContextMeaningEdgeNeighbor] = []
        var evidence: [LensContextMeaningEvidence] = []
        var warnings: [String] = []
        var seen = Set<String>()
        var neighborQueues: [[LensContextMeaningEdgeNeighbor]] = []
        let edgeLimit = min(max(payload.limits.meaningEdgeNeighbors, 0), 120)
        let evidenceLimit = min(max(payload.limits.meaningEvidence, 0), 40)
        for ref in payload.meaningNodeRefs.prefix(32) {
            guard let node = try graph.node(ref.slug) else {
                warnings.append("Meaning reference \(ref.slug) is not in this graph version; its saved Goal wording remains available.")
                continue
            }
            guard seen.insert(node.text("id")).inserted else { continue }
            selected.append(try decode(LensContextMeaningNode.self, node))
            neighborQueues.append(try graph.neighbors(of: node.text("slug"), limit: edgeLimit)
                .map { try decode(LensContextMeaningEdgeNeighbor.self, $0) })
            if evidence.count < evidenceLimit {
                evidence += try graph.evidence(for: node.text("slug"), limit: min(payload.limits.perNodeEvidence, evidenceLimit - evidence.count))
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
        var response = LensContextResolveResponse(schemaVersion: "litscenes.lens_context.local.v1", userId: "local",
            projectId: payload.projectId, goalFingerprint: payload.goalFingerprint,
            selectedMeaningNodes: selected, meaningEdgeNeighbors: neighbors, meaningEvidence: evidence,
            aestheticCandidates: aesthetics, styleCandidates: [], warnings: warnings,
            queryStats: LensContextQueryStats(durationMs: Int(Date().timeIntervalSince(started) * 1000),
                meaningRefCount: payload.meaningNodeRefs.count, resolvedMeaningNodeCount: selected.count,
                meaningEdgeNeighborCount: neighbors.count, meaningEvidenceCount: evidence.count,
                aestheticTermRefCount: terms.count, aestheticCandidateCount: aesthetics.count))
        response.graphProvenance = graph.provenance
        return response
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ row: GraphRecord) throws -> T {
        try JSONCoding.decoder.decode(type, from: GraphCoding.data(row))
    }
}
