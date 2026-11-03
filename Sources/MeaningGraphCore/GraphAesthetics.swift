import Foundation

public extension MeaningGraphSnapshot {
    func aestheticCandidates(_ input: [GraphAestheticTerm], limit: Int = 12) throws -> [GraphRecord] {
        let terms = try records("terms")
        let assignments = Dictionary(grouping: try records("assignments")) { $0.text("term_id") }
        let aesthetics = Dictionary(uniqueKeysWithValues: try records("aesthetics").map { ($0.text("id"), $0) })
        var matched: [String: [GraphRecord]] = [:]
        // Resolve each (term, source, facet) once using the strongest supplied
        // weight, matching the hosted resolver's DISTINCT selection.
        var resolved: [String: (GraphRecord, GraphAestheticTerm)] = [:]
        for item in input.prefix(64) {
            let query = item.term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !query.isEmpty else { continue }
            for term in terms where [term.text("slug"), term.text("normalized_value"), term.text("display_name")].contains(where: { $0.lowercased() == query }) {
                let key = [term.text("id"), item.source.lowercased(), item.attributeKey.lowercased()].joined(separator: "|")
                if let old = resolved[key], old.1.weight >= item.weight { continue }
                resolved[key] = (term, item)
            }
        }
        for key in resolved.keys.sorted() {
            guard let (term, item) = resolved[key] else { continue }
            for assignment in assignments[term.text("id")] ?? [] {
                let facet = assignment.text("facet_type")
                let attribute = item.attributeKey.lowercased(), source = item.source.lowercased()
                guard attribute.isEmpty || attribute == facet || attribute == term.text("facet_type") else { continue }
                let weight: Double
                if source == "goal" && ["key_value", "key_motif"].contains(facet) { weight = 1.30 }
                else if source == "goal" && facet != "key_colour" { weight = 1.05 }
                else if source == "media" && facet != "key_colour" { weight = 0.65 }
                else if facet == "key_colour" { weight = 0.16 }
                else { weight = 0.45 }
                let rank = max(assignment.number("rank"), 1)
                let contribution = weight * max(item.weight, 0.1) * assignment.number("weight") / sqrt(rank)
                matched[assignment.text("aesthetic_id"), default: []].append([
                    "input_term": .string(item.term), "term_slug": .string(term.text("slug")),
                    "display_name": .string(term.text("display_name")), "source": .string(source),
                    "facet_type": .string(facet), "rank": .number(assignment.number("rank")),
                    "contribution": .number(contribution)
                ])
            }
        }
        var candidates: [GraphRecord] = []
        for (id, matches) in matched {
            guard let aesthetic = aesthetics[id] else { continue }
            let goalCount = matches.filter { $0.text("source") == "goal" }.count
            let nonColorCount = matches.filter { $0.text("facet_type") != "key_colour" }.count
            guard goalCount >= 1, nonColorCount >= 2 else { continue }
            candidates.append([
                "aesthetic_id": .string(id), "slug": .string(aesthetic.text("slug")),
                "title": .string(aesthetic.text("title")), "description": .string(aesthetic.text("description")),
                "primary_rank": .number(aesthetic.number("primary_rank")),
                "score": .number(matches.reduce(0) { $0 + $1.number("contribution") }),
                "match_count": .number(Double(matches.count)), "goal_match_count": .number(Double(goalCount)),
                "non_color_match_count": .number(Double(nonColorCount)),
                "matched_terms": .array(matches.sorted { $0.number("contribution") > $1.number("contribution") }.map(GraphValue.object))
            ])
        }
        return Array(candidates.sorted {
            if $0.number("score") != $1.number("score") { return $0.number("score") > $1.number("score") }
            if $0.number("primary_rank") != $1.number("primary_rank") { return $0.number("primary_rank") < $1.number("primary_rank") }
            if $0.text("title") != $1.text("title") { return $0.text("title") < $1.text("title") }
            return $0.text("aesthetic_id") < $1.text("aesthetic_id")
        }.prefix(min(max(limit, 0), 40)))
    }
}
