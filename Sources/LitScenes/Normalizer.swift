import Foundation

struct ScreenGraphNormalizer {
    let sessionId: String
    let captureId: String
    let captureRef: String
    let observedAt: String
    let model: String

    func normalize(_ draft: ScreenGraphHydrationDraft) -> ScreenGraphHydrationContext {
        let surfaces = draft.surfaces.enumerated().map { index, surface in
            ObservedScreenSurface(
                surfaceId: id(prefix: "surface", index: index, label: surface.titleOrUrl.isEmpty ? surface.appOrSite : surface.titleOrUrl),
                kind: surface.kind,
                appOrSite: surface.appOrSite,
                titleOrUrl: surface.titleOrUrl,
                captureRef: surface.captureRef.isEmpty ? captureRef : surface.captureRef,
                observedAt: observedAt,
                visibleTextSummary: surface.visibleTextSummary,
                literalVisualSummary: surface.literalVisualSummary,
                piiRisk: surface.piiRisk,
                redactionNotes: surface.redactionNotes,
                confidence0To1: clamp(surface.confidence0To1)
            )
        }

        let fallbackSurfaceId = surfaces.first?.surfaceId ?? id(prefix: "surface", index: 0, label: "screen")
        let evidence = draft.evidence.enumerated().map { index, item in
            let surfaceId = item.surfaceIndex.flatMap { surfaces[safe: $0]?.surfaceId } ?? fallbackSurfaceId
            return ScreenEvidence(
                evidenceId: id(prefix: "evidence", index: index, label: item.quoteOrSummary),
                surfaceId: surfaceId,
                kind: item.kind,
                quoteOrSummary: item.quoteOrSummary,
                whereSeen: item.whereSeen,
                confidence0To1: clamp(item.confidence0To1)
            )
        }

        let subject = ObservedSubjectProfile(
            scope: draft.subject.scope,
            canonicalName: draft.subject.canonicalName,
            aliases: draft.subject.aliases,
            oneLineIdentity: draft.subject.oneLineIdentity,
            domains: draft.subject.domains,
            visibleOfferings: draft.subject.visibleOfferings,
            visibleAudiences: draft.subject.visibleAudiences,
            peopleOrRoles: draft.subject.peopleOrRoles,
            places: draft.subject.places,
            channels: draft.subject.channels,
            visualIdentitySignals: draft.subject.visualIdentitySignals,
            voiceToneSignals: draft.subject.voiceToneSignals,
            evidenceIds: evidenceIds(from: draft.subject.evidenceIndices, evidence: evidence)
        )

        let claims = draft.claims.enumerated().map { index, claim in
            KnowledgeClaim(
                claimId: id(prefix: "claim", index: index, label: claim.claim),
                claim: claim.claim,
                status: claim.status,
                evidenceIds: evidenceIds(from: claim.evidenceIndices, evidence: evidence),
                confidence0To1: clamp(claim.confidence0To1)
            )
        }

        let nodes = draft.seedNodes.enumerated().map { index, node in
            ScreenGraphSeedNode(
                seedNodeId: id(prefix: "node", index: index, label: node.name),
                kind: node.kind,
                abstractionLevel: node.abstractionLevel,
                name: node.name,
                definition: node.definition,
                meaningClaim: node.meaningClaim,
                positiveExpression: node.positiveExpression,
                negativeExpression: node.negativeExpression,
                boundary: node.boundary,
                aliases: node.aliases,
                tags: node.tags,
                evidenceIds: evidenceIds(from: node.evidenceIndices, evidence: evidence),
                confidenceScore: clamp(node.confidenceScore),
                reuseScore: clamp(node.reuseScore),
                reviewNote: node.reviewNote
            )
        }

        let edges = draft.seedEdges.compactMap { edge -> ScreenGraphSeedEdge? in
            guard let sourceId = nodes[safe: edge.sourceSeedNodeIndex]?.seedNodeId,
                  let targetId = nodes[safe: edge.targetSeedNodeIndex]?.seedNodeId else {
                return nil
            }
            return ScreenGraphSeedEdge(
                sourceSeedNodeId: sourceId,
                targetSeedNodeId: targetId,
                relationType: edge.relationType,
                rationale: edge.rationale,
                evidenceIds: evidenceIds(from: edge.evidenceIndices, evidence: evidence),
                confidenceScore: clamp(edge.confidenceScore)
            )
        }

        let recordId = id(prefix: "analysis", index: 0, label: draft.operatorSummary)
        return ScreenGraphHydrationContext(
            recordId: recordId,
            schemaVersion: ScreenGraphConstants.contextSchemaVersion,
            promptVersion: ScreenGraphConstants.promptVersion,
            observerRuntime: ScreenGraphConstants.observerRuntime,
            observerModel: model,
            createdAt: observedAt,
            observationGoal: draft.observationGoal,
            subject: subject,
            surfaces: surfaces,
            evidence: evidence,
            claims: claims,
            northStarSignals: draft.northStarSignals,
            seedNodes: nodes,
            seedEdges: edges,
            openQuestionsForUser: draft.openQuestionsForUser,
            uncertaintyNotes: draft.uncertaintyNotes,
            privacyWarnings: draft.privacyWarnings,
            operatorSummary: draft.operatorSummary
        )
    }

    private func evidenceIds(from indices: [Int], evidence: [ScreenEvidence]) -> [String] {
        indices.compactMap { evidence[safe: $0]?.evidenceId }
    }

    private func id(prefix: String, index: Int, label: String) -> String {
        let slug = stableSlug(label, fallback: prefix)
        let basis = "\(sessionId)|\(captureId)|\(prefix)|\(index)|\(slug)"
        return "\(prefix)_\(slug)_\(shortHash(basis))"
    }

    private func clamp(_ value: Double) -> Double {
        max(0, min(1, value))
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
