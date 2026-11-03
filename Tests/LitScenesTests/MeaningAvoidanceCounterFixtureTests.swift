import Foundation
import MeaningGraphCore
import Testing
@testable import LitScenes

struct MeaningAvoidanceCounterFixtureTests {
    @Test func exclusionsSurviveAliasesAndEntityRenamingWithoutProviderSpend() async throws {
        // Distinct projects exercise the same structured contract without production keywords.
        for (prefix, title, allowed, avoided) in [
            ("rehearsal", "Orchestra rehearsal", "Shared rhythm", "Solo competition"),
            ("wetland", "Wetland restoration", "Collective stewardship", "Territorial conquest"),
            ("renamed", "Renamed project", "Concept A", "Concept B")
        ] {
            let yaml = """
            schema_version: litscenes.meaning_graph.v1
            pack_id: counter.\(prefix)
            version: "1"
            title: \(title)
            generated_on: '2026-01-01'
            license: AGPL-3.0-only
            nodes:
            - {id: a, slug: theme.\(prefix)-a, name: \(allowed), kind: theme, definition: Cooperation through shared effort.}
            - {id: b, slug: theme.\(prefix)-b, name: \(avoided), kind: theme, definition: Advancement through rivalry., aliases: [\(prefix)-alias]}
            edges:
            - {id: ab, source_node_id: a, target_node_id: b, relation_type: contrasts_with}
            evidence:
            - {id: edge-proof, target_type: edge, target_id: ab, rationale: Contrasting approaches.}
            aesthetics: []
            terms: []
            assignments: []
            """
            let parsed = try MeaningGraphSource.parse(Data(yaml.utf8))
            try await MeaningGraphRuntime.shared.install(parsed.source, yaml: yaml)
            let selection = ProjectMeaningGraphSelection(base: parsed.source)
            let graph = try await MeaningGraphRuntime.shared.snapshot(selection)
            let positive = ProjectGoalMeaningNodeRef(slug: "theme.\(prefix)-a", name: allowed, role: .themeSeed)
            let conflict = ProjectGoalMeaningNodeRef(slug: "theme.\(prefix)-b", name: avoided, role: .themeSeed)
            let exclusion = ProjectGoalMeaningNodeRef(slug: "\(prefix)-alias", name: avoided, role: .avoidance)
            for refs in [[positive, conflict, exclusion], [exclusion, conflict, positive]] {
                let resolved = try LocalMeaningGraphResolver.resolve(LensContextResolveRequest(
                    projectId: prefix, goalFingerprint: "counter-fixture", meaningNodeRefs: refs,
                    aestheticTermRefs: [], limits: LensContextResolveLimits()), graph: graph)
                #expect(resolved.selectedMeaningNodes.map(\.slug) == [positive.slug])
                #expect(resolved.meaningEdgeNeighbors.isEmpty)
                #expect(resolved.meaningEvidence.isEmpty)
                #expect(resolved.excludedMeaningNodeRefs.map(\.slug) == [conflict.slug])
                let guidance = LocalSceneStoryProjection.meaningGuidance(resolved)
                #expect((guidance["concepts"] as? [[String: Any]])?.count == 1)
                var forms = FrameFormsGenerateRequest()
                forms.meaningNodeRefs = refs
                for mode in ["initial", "expansion"] {
                    forms.selectedForm = mode == "expansion" ? FrameFormsSelectedForm(
                        meaningSlug: conflict.slug, pole: "positive", title: avoided, promptGist: "Historical form") : nil
                    let (candidates, _) = LocalFrameFormSelection.candidates(request: forms, mode: mode, graph: graph)
                    #expect(candidates.count == 3)
                    #expect(candidates.allSatisfy { $0.node.slug == positive.slug })
                }
            }
            var allExcluded = FrameFormsGenerateRequest()
            allExcluded.projectId = prefix
            var excludePositive = positive
            excludePositive.role = .avoidance
            allExcluded.meaningNodeRefs = [excludePositive, exclusion]
            let client = LocalStoryInferenceClient(apiKey: "", responsesURL: URL(string: "https://invalid.invalid")!,
                storyModel: "unused", frameFormModel: "unused", graphSelection: selection)
            for mode in ["initial", "expansion"] {
                allExcluded.selectedForm = mode == "expansion" ? FrameFormsSelectedForm(
                    meaningSlug: conflict.slug, pole: "positive", title: avoided, promptGist: "Historical form") : nil
                let result = try await client.generateFrameForms(allExcluded)
                #expect(result.options.isEmpty)
                #expect(!result.warnings.isEmpty)
                #expect(result.usageInputTokens == 0 && result.usageOutputTokens == 0)
                #expect(result.traceId?.isEmpty == false)
                #expect(result.mode == mode)
            }
            var brief = ProjectGoalBriefV2()
            var sameSlugExclusion = conflict
            sameSlugExclusion.role = .avoidance
            brief.meaningNodeRefs = [conflict, sameSlugExclusion]
            #expect(brief.normalized().meaningNodeRefs.first?.role == .avoidance)
            brief.meaningNodeRefs.reverse()
            #expect(brief.normalized().meaningNodeRefs.first?.role == .avoidance)
        }
    }
}
