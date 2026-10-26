import Foundation

enum GraphText {
    static func tokens(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 1 })
    }
}

public extension MeaningGraphSnapshot {
    func kinds() throws -> [String] {
        try GraphSQLite(url: url).strings("SELECT DISTINCT json_extract(payload,'$.kind') FROM nodes ORDER BY 1")
    }

    /// The most reusable nodes of one kind, for topping up a retrieval that
    /// under-represents it.
    func nodes(kind: String, limit: Int) throws -> [GraphRecord] {
        try GraphSQLite(url: url).records("""
        SELECT payload FROM nodes WHERE json_extract(payload,'$.kind')=?
        ORDER BY json_extract(payload,'$.reuse_score') + json_extract(payload,'$.confidence_score') DESC,
            json_extract(payload,'$.edge_degree') DESC, json_extract(payload,'$.slug') LIMIT ?
        """, [kind, String(min(max(limit, 0), 120))])
    }

    /// Terms for a choice list: only the supplied facets, each capped. Terms that
    /// share tokens with the query rank first; the rest of each cap is filled by
    /// how many aesthetics use the term, so general vocabulary precedes one-off
    /// labels. Ties fall back to stable identity.
    func termChoices(query: String, caps: [String: Int]) throws -> [GraphRecord] {
        guard caps.values.contains(where: { $0 > 0 }) else { return [] }
        let db = try GraphSQLite(url: url)
        let usage = Dictionary(uniqueKeysWithValues: try db.records("""
        SELECT json_object('term_id', json_extract(payload,'$.term_id'), 'count', count(*))
        FROM assignments GROUP BY json_extract(payload,'$.term_id')
        """).map { ($0.text("term_id"), $0.number("count")) })
        let queryTokens = GraphText.tokens(query)
        var byFacet: [String: [(score: Int, usage: Double, record: GraphRecord)]] = [:]
        for term in try db.records("SELECT payload FROM terms ORDER BY id") {
            let facet = term.text("facet_type")
            guard let cap = caps[facet], cap > 0 else { continue }
            let own = GraphText.tokens([term.text("normalized_value"), term.text("display_name"), term.text("slug")].joined(separator: " "))
            byFacet[facet, default: []].append((own.intersection(queryTokens).count, usage[term.text("id")] ?? 0, term))
        }
        var result: [GraphRecord] = []
        for facet in byFacet.keys.sorted() {
            let ranked = (byFacet[facet] ?? []).sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.usage != $1.usage { return $0.usage > $1.usage }
                return $0.record.text("id") < $1.record.text("id")
            }
            result += ranked.prefix(caps[facet] ?? 0).map(\.record)
        }
        return result
    }
}
