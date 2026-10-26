import Foundation
import MeaningGraphCore

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    if arguments.first == "--verify", arguments.count == 3 {
        let baseURL = URL(fileURLWithPath: arguments[1])
        let bytes = try Data(contentsOf: baseURL)
        let manifest = try JSONDecoder().decode(GraphRecord.self, from: Data(contentsOf: baseURL.deletingLastPathComponent().appendingPathComponent("manifest.json")))
        guard manifest.text("schema_version") == "litscenes.meaning_graph_manifest.v1",
              manifest.text("sha256") == GraphCoding.hash(bytes), Int(manifest.number("byte_size")) == bytes.count else {
            throw MeaningGraphError("Graph release manifest does not match its YAML source.")
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("meaning-verify-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let rebuilt = try MeaningGraphCompiler.compile(base: String(decoding: bytes, as: UTF8.self), overlays: [], to: temporary)
        let shipped = try MeaningGraphSnapshot.open(URL(fileURLWithPath: arguments[2]))
        guard rebuilt.provenance == shipped.provenance, manifest.text("pack_id") == rebuilt.provenance.packId,
              manifest.text("version") == rebuilt.provenance.version else { throw MeaningGraphError("Bundled graph provenance is stale. Recompile graph.sqlite.") }
        for table in MeaningGraphCompiler.tableNames {
            guard try rebuilt.records(table) == shipped.records(table) else { throw MeaningGraphError("Bundled graph table \(table) is stale.") }
        }
        print("Verified graph source, release manifest, and all SQLite records: \(shipped.provenance.effectiveHash)")
    } else if arguments.first == "--inspect", arguments.count >= 2 {
        let graph = try MeaningGraphSnapshot.open(URL(fileURLWithPath: arguments[1]))
        let nodes = try graph.search(arguments.dropFirst(2).joined(separator: " "), limit: 8)
        let slug = nodes.first?.text("slug") ?? ""
        let packet: GraphRecord = ["effective_hash": .string(graph.provenance.effectiveHash),
            "nodes": .array(nodes.map(GraphValue.object)),
            "neighbors": .array(try graph.neighbors(of: slug, limit: 8).map(GraphValue.object)),
            "evidence": .array(try graph.evidence(for: slug, limit: 2).map(GraphValue.object))]
        print(String(decoding: try GraphCoding.data(packet), as: UTF8.self))
    } else {
        guard arguments.count >= 2 else {
            throw MeaningGraphError("Usage: MeaningGraphCompiler base.yaml output.sqlite [overlay.yaml ...]\n       MeaningGraphCompiler --verify base.yaml graph.sqlite\n       MeaningGraphCompiler --inspect graph.sqlite [query]")
        }
        let base = try String(contentsOfFile: arguments[0], encoding: .utf8)
        let overlays = try arguments.dropFirst(2).map { try String(contentsOfFile: $0, encoding: .utf8) }
        let snapshot = try MeaningGraphCompiler.compile(base: base, overlays: overlays, to: URL(fileURLWithPath: arguments[1]))
        print(String(decoding: try GraphCoding.data(snapshot.provenance), as: UTF8.self))
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
