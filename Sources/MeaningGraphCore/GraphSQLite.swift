import Foundation
import SQLite3

final class GraphSQLite {
    private var handle: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL, writable: Bool = false) throws {
        let flags = writable ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            handle = nil
            throw MeaningGraphError("Unable to open the local meaning graph database.")
        }
        sqlite3_busy_timeout(handle, 5000)
        if !writable { try execute("PRAGMA query_only=ON;") }
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String, _ bindings: [String] = []) throws {
        if bindings.isEmpty {
            guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
            return
        }
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func strings(_ sql: String, _ bindings: [String] = []) throws -> [String] {
        let statement = try prepare(sql, bindings)
        defer { sqlite3_finalize(statement) }
        var result: [String] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return result }
            guard status == SQLITE_ROW else { throw failure() }
            if let text = sqlite3_column_text(statement, 0) { result.append(String(cString: text)) }
        }
    }

    func records(_ sql: String, _ bindings: [String] = []) throws -> [GraphRecord] {
        try strings(sql, bindings).map { try JSONDecoder().decode(GraphRecord.self, from: Data($0.utf8)) }
    }

    private func prepare(_ sql: String, _ bindings: [String]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        for (index, value) in bindings.enumerated() {
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else {
                sqlite3_finalize(statement)
                throw failure()
            }
        }
        return statement
    }

    private func failure() -> MeaningGraphError {
        MeaningGraphError("Local graph query failed: \(String(cString: sqlite3_errmsg(handle)))")
    }
}

public struct MeaningGraphSnapshot: Sendable {
    public let url: URL
    public let provenance: MeaningGraphProvenance

    public init(url: URL, provenance: MeaningGraphProvenance) {
        self.url = url; self.provenance = provenance
    }

    public static func open(_ url: URL) throws -> Self {
        let db = try GraphSQLite(url: url)
        guard let json = try db.strings("SELECT payload FROM graph_metadata WHERE key='provenance'").first else {
            throw MeaningGraphError("The graph database is missing its manifest.")
        }
        let provenance = try JSONDecoder().decode(MeaningGraphProvenance.self, from: Data(json.utf8))
        guard provenance.resolverVersion == MeaningGraphCompiler.resolverVersion else {
            throw MeaningGraphError("The graph cache needs rebuilding with this engine version.")
        }
        return Self(url: url, provenance: provenance)
    }

    public func records(_ table: String) throws -> [GraphRecord] {
        guard MeaningGraphCompiler.tableNames.contains(table) else { throw MeaningGraphError("Unknown graph table.") }
        return try GraphSQLite(url: url).records("SELECT payload FROM \(table) ORDER BY id")
    }

    public func node(_ reference: String) throws -> GraphRecord? {
        let db = try GraphSQLite(url: url)
        let ref = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = try db.records("SELECT payload FROM nodes WHERE id=? OR lower(json_extract(payload,'$.slug'))=lower(?)", [ref, ref])
        if exact.count == 1 { return exact[0] }
        let aliases = try db.records("SELECT DISTINCT n.payload FROM nodes n, json_each(n.payload,'$.aliases') a WHERE lower(a.value)=lower(?) LIMIT 2", [ref])
        return aliases.count == 1 ? aliases[0] : nil
    }

    public func search(_ query: String, limit: Int = 48) throws -> [GraphRecord] {
        let db = try GraphSQLite(url: url)
        var seen = Set<String>()
        let tokens = query.lowercased().split { !$0.isLetter && !$0.isNumber }
            .map(String.init).filter { $0.count > 1 && seen.insert($0).inserted }.prefix(32)
        let count = min(max(limit, 1), 120)
        if tokens.isEmpty {
            return try db.records("SELECT payload FROM nodes ORDER BY json_extract(payload,'$.reuse_score') DESC, json_extract(payload,'$.edge_degree') DESC, json_extract(payload,'$.slug') LIMIT ?", [String(count)])
        }
        let match = tokens.map { "\"\($0)\"" }.joined(separator: " OR ")
        return try db.records("SELECT n.payload FROM node_search s JOIN nodes n ON n.id=s.id WHERE node_search MATCH ? ORDER BY bm25(node_search,0,8,6,4,1), n.id LIMIT ?", [match, String(count)])
    }

    public func neighbors(of slug: String, limit: Int = 48, divergent: Bool = false) throws -> [GraphRecord] {
        guard let selected = try node(slug) else { return [] }
        let id = selected.text("id")
        let db = try GraphSQLite(url: url)
        let direction = "CASE WHEN json_extract(e.payload,'$.source_node_id')=? THEN 'outgoing' ELSE 'incoming' END"
        let divergence = divergent ? "CASE json_extract(e.payload,'$.relation_type') WHEN 'contrasts_with' THEN 0 WHEN 'inverts' THEN 1 WHEN 'corrupts' THEN 2 WHEN 'intensifies' THEN 3 WHEN 'resolves' THEN 4 WHEN 'transforms_into' THEN 5 WHEN 'foreshadows' THEN 6 ELSE 9 END," : ""
        return try db.records("""
        SELECT json_object('selected_slug', ?, 'direction', \(direction),
            'relation_type', json_extract(e.payload,'$.relation_type'),
            'strength', json_extract(e.payload,'$.strength'), 'confidence_score', json_extract(e.payload,'$.confidence_score'),
            'rationale', json_extract(e.payload,'$.rationale'), 'neighbor', json(n.payload))
        FROM edges e JOIN nodes n ON n.id=CASE WHEN json_extract(e.payload,'$.source_node_id')=?
            THEN json_extract(e.payload,'$.target_node_id') ELSE json_extract(e.payload,'$.source_node_id') END
        WHERE json_extract(e.payload,'$.source_node_id')=? OR json_extract(e.payload,'$.target_node_id')=?
        ORDER BY \(divergence) json_extract(e.payload,'$.strength') DESC, json_extract(e.payload,'$.confidence_score') DESC,
            json_extract(n.payload,'$.slug') LIMIT ?
        """, [selected.text("slug"), id, id, id, id, String(min(max(limit, 0), 120))])
    }

    public func evidence(for slug: String, limit: Int = 2) throws -> [GraphRecord] {
        guard let node = try node(slug) else { return [] }
        return try GraphSQLite(url: url).records("""
        SELECT json_set(ev.payload,'$.node_slug',?) FROM evidence ev
        WHERE (json_extract(ev.payload,'$.target_type')='node' AND json_extract(ev.payload,'$.target_id')=?)
            OR (json_extract(ev.payload,'$.target_type')='edge' AND EXISTS (
                SELECT 1 FROM edges e WHERE e.id=json_extract(ev.payload,'$.target_id')
                    AND (json_extract(e.payload,'$.source_node_id')=? OR json_extract(e.payload,'$.target_node_id')=?)))
        ORDER BY json_extract(ev.payload,'$.confidence_score') DESC, json_extract(ev.payload,'$.weight') DESC, ev.id LIMIT ?
        """, [node.text("slug"), node.text("id"), node.text("id"), node.text("id"), String(min(max(limit, 0), 5))])
    }
}
