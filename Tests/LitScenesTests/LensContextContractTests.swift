import Foundation
import Testing
@testable import LitScenes

@Test
func lensContextResponseDecodesCanonicalLambdaShape() throws {
    let json = """
    {
      "schema_version": "lens-context.resolve.v0.1",
      "user_id": "desktop-user",
      "project_id": "project",
      "goal_fingerprint": "fingerprint",
      "selected_meaning_nodes": [],
      "meaning_edge_neighbors": [],
      "meaning_evidence": [],
      "aesthetic_candidates": [],
      "warnings": [],
      "query_stats": {
        "duration_ms": 42,
        "meaning_ref_count": 1,
        "resolved_meaning_node_count": 0,
        "meaning_edge_neighbor_count": 0,
        "meaning_evidence_count": 0,
        "aesthetic_term_ref_count": 1,
        "aesthetic_candidate_count": 0
      }
    }
    """

    let decoded = try JSONCoding.decoder.decode(LensContextResolveResponse.self, from: Data(json.utf8))

    #expect(decoded.schemaVersion == "lens-context.resolve.v0.1")
    #expect(decoded.userId == "desktop-user")
    #expect(decoded.projectId == "project")
    #expect(decoded.queryStats.durationMs == 42)
    #expect(decoded.selectedMeaningNodes.isEmpty)
}

@Test
func lensContextResponseDefaultsMissingTopLevelArraysAndStats() throws {
    let json = """
    {
      "schema_version": "theme-context.resolve.v0.1",
      "project_id": "project",
      "goal_fingerprint": "fingerprint"
    }
    """

    let decoded = try JSONCoding.decoder.decode(LensContextResolveResponse.self, from: Data(json.utf8))

    #expect(decoded.userId == "")
    #expect(decoded.selectedMeaningNodes == [])
    #expect(decoded.meaningEdgeNeighbors == [])
    #expect(decoded.meaningEvidence == [])
    #expect(decoded.aestheticCandidates == [])
    #expect(decoded.warnings == [])
    #expect(decoded.queryStats.aestheticCandidateCount == 0)
}

@Test
func lensContextResponseToleratesNullDatabaseDecoration() throws {
    let json = """
    {
      "schema_version": "theme-context.resolve.v0.1",
      "project_id": "project",
      "goal_fingerprint": "fingerprint",
      "selected_meaning_nodes": [
        {
          "id": null,
          "slug": "theme.test",
          "kind": null,
          "abstraction_level": null,
          "name": null,
          "status": null,
          "confidence_score": null,
          "reuse_score": "0.25",
          "definition": null,
          "tags": null,
          "edge_degree": "3"
        },
        {
          "name": "missing slug should be dropped"
        }
      ],
      "meaning_edge_neighbors": [
        {
          "selected_slug": "theme.test",
          "direction": null,
          "relation_type": null,
          "strength": "0.7",
          "confidence_score": null,
          "rationale": null,
          "neighbor": {
            "slug": "theme.neighbor",
            "tags": null
          }
        }
      ],
      "meaning_evidence": [
        {
          "node_slug": "theme.test",
          "weight": "0.5",
          "passage_index": "2"
        }
      ],
      "aesthetic_candidates": [
        {
          "slug": "neon-ritual",
          "title": null,
          "matched_terms": [
            {
              "display_name": "Neon",
              "contribution": "0.4"
            },
            {}
          ]
        }
      ],
      "warnings": null
    }
    """

    let decoded = try JSONCoding.decoder.decode(LensContextResolveResponse.self, from: Data(json.utf8))

    #expect(decoded.selectedMeaningNodes.count == 1)
    #expect(decoded.selectedMeaningNodes[0].id == "theme.test")
    #expect(decoded.selectedMeaningNodes[0].reuseScore == 0.25)
    #expect(decoded.selectedMeaningNodes[0].edgeDegree == 3)
    #expect(decoded.meaningEdgeNeighbors.count == 1)
    #expect(decoded.meaningEdgeNeighbors[0].neighbor.slug == "theme.neighbor")
    #expect(decoded.meaningEvidence[0].passageIndex == 2)
    #expect(decoded.aestheticCandidates.count == 1)
    #expect(decoded.aestheticCandidates[0].aestheticId == "neon-ritual")
    #expect(decoded.aestheticCandidates[0].matchedTerms.count == 1)
}

@Test
func lensContextResponseDecodesStyleCandidates() throws {
    let json = """
    {
      "schema_version": "lens-context.resolve.v0.1",
      "user_id": "desktop-user",
      "project_id": "project",
      "goal_fingerprint": "fingerprint",
      "selected_meaning_nodes": [],
      "meaning_edge_neighbors": [],
      "meaning_evidence": [],
      "aesthetic_candidates": [],
      "style_candidates": [
        {
          "style_id": "07ac09f9-25fa-4232-a52a-303f9c1aed2a",
          "title": "Vibrant Anime",
          "label": "Vermilion Teal Anime Noir",
          "caption": "Bold anime-graphic illustration.",
          "image_url": "https://example.cloudfront.net/card.png",
          "collection_key": "anime",
          "collection_name": "Anime & Cel",
          "secondary_collection": "nocturne",
          "moods": ["Energetic", "Mysterious"],
          "hue_name": "Crimson",
          "hue_hex": "#c0392b",
          "medium": "Digital painting",
          "scalar_sat": 5,
          "scalar_con": 4,
          "scalar_ser": 3,
          "scalar_lin": 4,
          "scalar_sty": 3,
          "score": 12.4,
          "match_count": 9,
          "matched_terms": [
            {"input_term": "mysterious", "kind": "mood", "field_name": "categorization", "value": "mysterious", "contribution": 1.68}
          ],
          "positive_prompt_atoms": ["crisp ink lines", "blazing orange light"],
          "negative_prompt_atoms": ["washed-out haze"],
          "transferable_traits": ["poster-like value blocking"]
        },
        {
          "style_id": "",
          "title": "unusable",
          "label": "",
          "caption": "",
          "image_url": "",
          "collection_key": "",
          "collection_name": "",
          "secondary_collection": "",
          "moods": [],
          "hue_name": "",
          "hue_hex": "",
          "medium": "",
          "scalar_sat": 0, "scalar_con": 0, "scalar_ser": 0, "scalar_lin": 0, "scalar_sty": 0,
          "score": 0, "match_count": 0, "matched_terms": [],
          "positive_prompt_atoms": [], "negative_prompt_atoms": [], "transferable_traits": []
        }
      ],
      "warnings": [],
      "query_stats": {
        "duration_ms": 300,
        "meaning_ref_count": 0,
        "resolved_meaning_node_count": 0,
        "meaning_edge_neighbor_count": 0,
        "meaning_evidence_count": 0,
        "aesthetic_term_ref_count": 0,
        "aesthetic_candidate_count": 0,
        "style_term_ref_count": 7,
        "style_candidate_count": 2
      }
    }
    """

    let decoded = try JSONCoding.decoder.decode(LensContextResolveResponse.self, from: Data(json.utf8))

    #expect(decoded.styleCandidates.count == 1)
    let candidate = try #require(decoded.styleCandidates.first)
    #expect(candidate.styleId == "07ac09f9-25fa-4232-a52a-303f9c1aed2a")
    #expect(candidate.collectionKey == "anime")
    #expect(candidate.secondaryCollection == "nocturne")
    #expect(candidate.hueHex == "#c0392b")
    #expect(candidate.scalarSat == 5)
    #expect(candidate.matchedTerms.first?.kind == "mood")
    #expect(candidate.positivePromptAtoms.count == 2)
    #expect(candidate.displayLabel == "Vermilion Teal Anime Noir")
}

@Test
func lensContextRequestEncodesStyleTermRefsAsSnakeCase() throws {
    let request = LensContextResolveRequest(
        projectId: "project",
        goalFingerprint: "fingerprint",
        meaningNodeRefs: [],
        aestheticTermRefs: [],
        styleTermRefs: [
            ProjectGoalStyleTermRef(term: "Mysterious", kind: .mood, weight: 1.2, rationale: "night vigil tone")
        ],
        limits: LensContextResolveLimits()
    )
    let data = try JSONCoding.encoder.encode(request)
    let payload = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let refs = try #require(payload["style_term_refs"] as? [[String: Any]])
    #expect(refs.first?["term"] as? String == "Mysterious")
    #expect(refs.first?["kind"] as? String == "mood")
    let limits = try #require(payload["limits"] as? [String: Any])
    #expect(limits["style_candidates"] as? Int == 45)
}

@Test
func goalBriefRoundTripsStyleTermRefsAndFingerprintChanges() throws {
    var brief = ProjectGoalBriefV2.empty()
    brief.contentType = .documentary
    brief.goal = "Night shift stories"
    let before = try JSONCoding.encoder.encode(brief.normalized())

    brief.styleTermRefs = [
        ProjectGoalStyleTermRef(term: "nocturne", kind: .collection, weight: 1.3, rationale: "dark vigil"),
        ProjectGoalStyleTermRef(term: "nocturne", kind: .collection, weight: 0.5, rationale: "duplicate"),
        ProjectGoalStyleTermRef(term: "rain", kind: .phrase, weight: 9, rationale: "")
    ]
    let normalized = brief.normalized()
    #expect(normalized.styleTermRefs.count == 2)
    #expect(normalized.styleTermRefs.last?.weight == 3)

    let after = try JSONCoding.encoder.encode(normalized)
    #expect(before != after)

    let decoded = try JSONCoding.decoder.decode(ProjectGoalBriefV2.self, from: after)
    #expect(decoded.styleTermRefs == normalized.styleTermRefs)

    let legacy = try JSONCoding.decoder.decode(ProjectGoalBriefV2.self, from: before)
    #expect(legacy.styleTermRefs.isEmpty)
}
