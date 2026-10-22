import Foundation

public enum MeaningGraphCompiler {
    public static let resolverVersion = "litscenes.meaning_graph_engine.v1"
    public static let tableNames = ["nodes", "edges", "evidence", "aesthetics", "terms", "assignments"]

    public static func compile(base: String, overlays: [String], to output: URL) throws -> MeaningGraphSnapshot {
        let pack = try MeaningGraphPack.load(base)
        var tables: [String: [String: GraphRecord]] = [:]
        for name in tableNames {
            var records: [String: GraphRecord] = [:]
            for var row in pack.tables[name] ?? [] {
                let id = row.text("id")
                guard !id.isEmpty, records[id] == nil else { throw MeaningGraphError("Duplicate or missing identity in \(name).") }
                row["origin_pack"] = .string(pack.packId)
                records[id] = row
            }
            tables[name] = records
        }
        var disabled: [String: Set<String>] = [:]
        var added: [(table: String, id: String)] = []
        var overlayIds = Set<String>()
        for source in overlays {
            let overlay = try MeaningGraphOverlay.load(source)
            guard overlay.basePackId == pack.packId, overlayIds.insert(overlay.packId).inserted else {
                throw MeaningGraphError("An overlay targets a different base pack or is enabled more than once.")
            }
            var operated = Set<String>()
            for operation in overlay.operations {
                guard tableNames.contains(operation.table), !operation.id.isEmpty,
                      operated.insert("\(operation.table):\(operation.id)").inserted else {
                    throw MeaningGraphError("Overlay contains an invalid table or duplicate operation identity.")
                }
                let existing = tables[operation.table]?[operation.id]
                switch operation.action {
                case "disable":
                    guard existing != nil else { throw MeaningGraphError("Cannot disable missing \(operation.table) record \(operation.id).") }
                    disabled[operation.table, default: []].insert(operation.id)
                case "add", "override":
                    guard let fields = operation.fields else { throw MeaningGraphError("Add/override operations require fields.") }
                    guard !fields.keys.contains(where: { ["id", "origin_pack", "modified_by"].contains($0) }) else {
                        throw MeaningGraphError("Overlay fields cannot replace record identity or provenance.")
                    }
                    var row: GraphRecord
                    if operation.action == "add" {
                        guard existing == nil, operation.id.hasPrefix(overlay.packId + ":") else {
                            throw MeaningGraphError("Added records need a new identity prefixed with \(overlay.packId):.")
                        }
                        row = ["id": .string(operation.id), "origin_pack": .string(overlay.packId)]
                        added.append((operation.table, operation.id))
                    } else {
                        guard let value = existing else { throw MeaningGraphError("Override target \(operation.id) is absent from this base version.") }
                        if let slug = fields["slug"], slug != value["slug"] {
                            throw MeaningGraphError("Override keeps the existing slug; use aliases or the display name.")
                        }
                        row = value
                    }
                    row.merge(fields) { _, replacement in replacement }
                    row["modified_by"] = .string(overlay.packId)
                    tables[operation.table]?[operation.id] = row
                    disabled[operation.table]?.remove(operation.id)
                default: throw MeaningGraphError("Unknown overlay action \(operation.action).")
                }
            }
        }
        // Validate references before suppression so a disabled target does not
        // disguise an unrelated dangling reference in a supplied record.
        try validate(tables)
        for name in tableNames {
            for id in disabled[name] ?? [] { tables[name]?.removeValue(forKey: id) }
        }
        // A later layer may disable an earlier layer's addition; that is layering.
        // An addition that only loses its target to suppression is a conflict the
        // author must hear about, never a silent omission.
        let retainedAdditions = added.filter { tables[$0.table]?[$0.id] != nil }
        tables["edges"] = tables["edges"]?.filter {
            tables["nodes"]?[$0.value.text("source_node_id")] != nil && tables["nodes"]?[$0.value.text("target_node_id")] != nil
        }
        tables["evidence"] = tables["evidence"]?.filter {
            tables[$0.value.text("target_type") == "edge" ? "edges" : "nodes"]?[$0.value.text("target_id")] != nil
        }
        tables["assignments"] = tables["assignments"]?.filter {
            tables["aesthetics"]?[$0.value.text("aesthetic_id")] != nil && tables["terms"]?[$0.value.text("term_id")] != nil
        }
        for addition in retainedAdditions where tables[addition.table]?[addition.id] == nil {
            throw MeaningGraphError("Overlay record \(addition.id) depends on a record this configuration disables.")
        }
        var degrees: [String: Int] = [:]
        for row in tables["edges"]?.values ?? [:].values {
            degrees[row.text("source_node_id"), default: 0] += 1
            degrees[row.text("target_node_id"), default: 0] += 1
        }
        for id in Array(tables["nodes"]?.keys ?? [:].keys) {
            tables["nodes"]?[id]?["edge_degree"] = .number(Double(degrees[id, default: 0]))
        }
        let baseHash = GraphCoding.hash(Data(base.utf8))
        let overlayHashes = overlays.map { GraphCoding.hash(Data($0.utf8)) }
        let effectiveHash = GraphCoding.hash(try GraphCoding.data([resolverVersion, baseHash] + overlayHashes))
        let provenance = MeaningGraphProvenance(packId: pack.packId, version: pack.version,
            baseHash: baseHash, overlayHashes: overlayHashes, effectiveHash: effectiveHash,
            resolverVersion: resolverVersion, title: pack.title, counts: tables.mapValues(\.count))
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".graph-\(UUID().uuidString).sqlite")
        do {
            do {
                let db = try GraphSQLite(url: temporary, writable: true)
                try db.execute("PRAGMA journal_mode=DELETE; PRAGMA user_version=1; BEGIN IMMEDIATE;")
                try db.execute("CREATE TABLE graph_metadata (key TEXT PRIMARY KEY, payload TEXT NOT NULL);")
                try db.execute("INSERT INTO graph_metadata VALUES ('provenance', ?)", [String(decoding: try GraphCoding.data(provenance), as: UTF8.self)])
                for name in tableNames {
                    try db.execute("CREATE TABLE \(name) (id TEXT PRIMARY KEY, payload TEXT NOT NULL CHECK(json_valid(payload)));")
                    for row in (tables[name] ?? [:]).values.sorted(by: { $0.text("id") < $1.text("id") }) {
                        try db.execute("INSERT INTO \(name) VALUES (?, ?)", [row.text("id"), String(decoding: try GraphCoding.data(row), as: UTF8.self)])
                    }
                }
                try db.execute("""
                CREATE UNIQUE INDEX nodes_slug ON nodes(json_extract(payload, '$.slug'));
                CREATE INDEX edges_source ON edges(json_extract(payload, '$.source_node_id'));
                CREATE INDEX edges_target ON edges(json_extract(payload, '$.target_node_id'));
                CREATE INDEX evidence_node ON evidence(json_extract(payload, '$.target_type'), json_extract(payload, '$.target_id'));
                CREATE INDEX assignments_term ON assignments(json_extract(payload, '$.term_id'));
                CREATE INDEX assignments_aesthetic ON assignments(json_extract(payload, '$.aesthetic_id'));
                CREATE VIRTUAL TABLE node_search USING fts5(id UNINDEXED, name, aliases, tags, definition);
                INSERT INTO node_search SELECT id, json_extract(payload,'$.name'), json_extract(payload,'$.aliases'),
                    json_extract(payload,'$.tags'), json_extract(payload,'$.definition') FROM nodes;
                COMMIT;
                """)
                guard try db.strings("PRAGMA quick_check") == ["ok"] else { throw MeaningGraphError("Compiled graph failed SQLite integrity validation.") }
            }
            if FileManager.default.fileExists(atPath: output.path) {
                _ = try FileManager.default.replaceItemAt(output, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: output)
            }
            return MeaningGraphSnapshot(url: output, provenance: provenance)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func validate(_ tables: [String: [String: GraphRecord]]) throws {
        var slugs = Set<String>()
        for row in (tables["nodes"] ?? [:]).values {
            guard !row.text("slug").isEmpty, slugs.insert(row.text("slug").lowercased()).inserted,
                  !row.text("name").isEmpty, !row.text("kind").isEmpty else {
                throw MeaningGraphError("Nodes require distinct slugs, names, and kinds.")
            }
        }
        var relations = Set<String>()
        for row in (tables["edges"] ?? [:]).values {
            let source = row.text("source_node_id"), target = row.text("target_node_id"), relation = row.text("relation_type")
            guard tables["nodes"]?[source] != nil, tables["nodes"]?[target] != nil, !relation.isEmpty,
                  relations.insert("\(source)|\(relation)|\(target)").inserted else {
                throw MeaningGraphError("A relationship has a missing endpoint/type or duplicate identity.")
            }
        }
        for row in (tables["evidence"] ?? [:]).values {
            let type = row.text("target_type")
            guard ["node", "edge"].contains(type), tables[type == "node" ? "nodes" : "edges"]?[row.text("target_id")] != nil else {
                throw MeaningGraphError("Evidence must reference a retained node or relationship.")
            }
        }
        for row in (tables["assignments"] ?? [:]).values {
            guard tables["aesthetics"]?[row.text("aesthetic_id")] != nil, tables["terms"]?[row.text("term_id")] != nil else {
                throw MeaningGraphError("An aesthetic assignment references a missing aesthetic or term.")
            }
        }
        for rows in tables.values {
            for row in rows.values {
                for key in ["id", "slug", "name", "kind", "definition", "abstraction_level", "positive_expression", "negative_expression", "boundary",
                            "source_node_id", "target_node_id", "relation_type", "target_type", "target_id", "node_id", "aesthetic_id", "term_id", "facet_type"] {
                    if let value = row[key], case .string = value { continue }
                    else if row[key] != nil { throw MeaningGraphError("\(key) must be text.") }
                }
                for key in ["tags", "aliases", "categories"] {
                    if let value = row[key] {
                        guard case .array(let items) = value, items.allSatisfy({ if case .string = $0 { true } else { false } }) else {
                            throw MeaningGraphError("\(key) must be an array of text values.")
                        }
                    }
                }
                for key in ["rank", "primary_rank", "passage_index"] {
                    if let value = row[key] {
                        guard case .number(let number) = value, number.isFinite, number >= 0, number.rounded() == number else {
                            throw MeaningGraphError("\(key) must be a non-negative integer.")
                        }
                    }
                }
                for key in ["confidence_score", "reuse_score", "strength", "weight"] {
                    if let value = row[key] {
                        guard case .number(let number) = value, number.isFinite, (0...1).contains(number) else {
                            throw MeaningGraphError("\(key) must be a finite number between zero and one.")
                        }
                    }
                }
            }
        }
    }
}
