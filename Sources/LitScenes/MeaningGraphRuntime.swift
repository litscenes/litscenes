import Foundation
import MeaningGraphCore

/// Identity of one YAML source. The YAML itself is kept once per Mac in
/// `MeaningGraphSourceStore` or read from the app bundle; project documents
/// carry identity only.
struct MeaningGraphSource: Codable, Hashable, Identifiable, Sendable {
    var hash: String
    var packId: String
    var version: String
    var title: String
    var kind: String
    /// Source text from documents written before sources moved to the shared
    /// store. Read for migration, never encoded again.
    var legacyYAML: String? = nil
    var id: String { hash }

    init(hash: String, packId: String, version: String, title: String, kind: String) {
        self.hash = hash; self.packId = packId; self.version = version; self.title = title; self.kind = kind
    }

    private enum CodingKeys: String, CodingKey { case hash, packId, version, title, kind, legacyYAML = "yaml" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hash = try container.decode(String.self, forKey: .hash)
        packId = try container.decode(String.self, forKey: .packId)
        version = try container.decode(String.self, forKey: .version)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(String.self, forKey: .kind)
        legacyYAML = try container.decodeIfPresent(String.self, forKey: .legacyYAML)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hash, forKey: .hash)
        try container.encode(packId, forKey: .packId)
        try container.encode(version, forKey: .version)
        try container.encode(title, forKey: .title)
        try container.encode(kind, forKey: .kind)
    }

    /// Identifies an imported pack or overlay. The caller stores the YAML.
    static func parse(_ data: Data) throws -> (source: Self, yaml: String) {
        guard data.count <= 64 * 1024 * 1024, let yaml = String(data: data, encoding: .utf8) else {
            throw MeaningGraphError("Choose a UTF-8 YAML graph pack smaller than 64 MB.")
        }
        struct Header: Decodable { var schema_version: String }
        let header = try GraphCoding.yaml(Header.self, source: yaml)
        let hash = GraphCoding.hash(data)
        if header.schema_version == "litscenes.meaning_graph_overlay.v1" {
            let overlay = try MeaningGraphOverlay.load(yaml)
            return (Self(hash: hash, packId: overlay.packId, version: overlay.version, title: overlay.title, kind: "overlay"), yaml)
        }
        let pack = try MeaningGraphPack.load(yaml)
        return (Self(hash: hash, packId: pack.packId, version: pack.version, title: pack.title, kind: "base"), yaml)
    }

    static func bundled() throws -> Self {
        let p = try MeaningGraphSourceStore.bundledProvenance()
        return Self(hash: p.baseHash, packId: p.packId, version: p.version, title: p.title, kind: "base")
    }
}

/// Content-addressed YAML store shared by every project on this Mac.
enum MeaningGraphSourceStore {
    static var directory: URL { MeaningGraphProjectStore.libraryURL.appendingPathComponent("sources", isDirectory: true) }
    static func fileURL(_ hash: String) -> URL { directory.appendingPathComponent("\(hash).yaml") }

    static func bundledDatabaseURL() throws -> URL { try packagedResourceURL(named: "MeaningGraph/graph", extension: "sqlite") }
    static func bundledProvenance() throws -> MeaningGraphProvenance { try MeaningGraphSnapshot.open(bundledDatabaseURL()).provenance }

    private static func validHash(_ hash: String) -> Bool {
        hash.count == 64 && hash.allSatisfy { "0123456789abcdef".contains($0) }
    }

    private static func legacyBundledURL(_ hash: String) -> URL? {
        guard validHash(hash) else { return nil }
        return try? packagedResourceURL(named: "MeaningGraph/Legacy/\(hash)", extension: "yaml")
    }

    static func isAvailable(_ source: MeaningGraphSource) -> Bool {
        guard validHash(source.hash) else { return false }
        return (try? bundledProvenance().baseHash) == source.hash || legacyBundledURL(source.hash) != nil
            || FileManager.default.fileExists(atPath: fileURL(source.hash).path)
    }

    /// Pin source bytes before a later application bundle replaces them.
    static func retainAvailableSources(_ selection: ProjectMeaningGraphSelection) throws {
        for source in [selection.base] + selection.overlays.map(\.source) where isAvailable(source) {
            if !FileManager.default.fileExists(atPath: fileURL(source.hash).path) {
                try store(yaml: yaml(for: source), hash: source.hash)
            }
            let metadataURL = MeaningGraphProjectStore.libraryURL.appendingPathComponent(source.hash + ".json")
            if !FileManager.default.fileExists(atPath: metadataURL.path) {
                try JSONCoding.encoder.encode(source).write(to: metadataURL, options: .atomic)
            }
        }
    }

    /// The exact YAML for a source, verified against its hash.
    static func yaml(for source: MeaningGraphSource) throws -> String {
        guard validHash(source.hash) else { throw MeaningGraphError("Invalid graph source identity.") }
        let data: Data
        if try bundledProvenance().baseHash == source.hash {
            data = try Data(contentsOf: packagedResourceURL(named: "MeaningGraph/graph", extension: "yaml"))
        } else if FileManager.default.fileExists(atPath: fileURL(source.hash).path) {
            data = try Data(contentsOf: fileURL(source.hash))
        } else if let bundled = legacyBundledURL(source.hash) {
            data = try Data(contentsOf: bundled)
        } else if let legacy = source.legacyYAML {
            data = Data(legacy.utf8)
        } else {
            throw MeaningGraphError("\(source.title) \(source.version) is not installed on this Mac. Import its YAML or choose another graph; the current graph is unchanged.")
        }
        guard GraphCoding.hash(data) == source.hash, let yaml = String(data: data, encoding: .utf8) else {
            throw MeaningGraphError("A graph source failed its integrity check. Re-import \(source.title) \(source.version).")
        }
        return yaml
    }

    /// Writes YAML once; identical content shares one file.
    static func store(yaml: String, hash: String) throws {
        let data = Data(yaml.utf8)
        guard validHash(hash), GraphCoding.hash(data) == hash else { throw MeaningGraphError("Graph source checksum mismatch.") }
        if let existing = try? Data(contentsOf: fileURL(hash)), GraphCoding.hash(existing) == hash { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(hash), options: .atomic)
    }
}

struct MeaningGraphLayer: Codable, Hashable, Identifiable, Sendable {
    var source: MeaningGraphSource
    var enabled = true
    var id: String { source.hash }
}

struct ProjectMeaningGraphSelection: Codable, Hashable, Sendable {
    var schemaVersion = "litscenes.project_meaning_graph.v1"
    var base: MeaningGraphSource
    var overlays: [MeaningGraphLayer] = []
    var effectiveHash: String {
        let components = [MeaningGraphCompiler.resolverVersion, base.hash] + overlays.filter(\.enabled).map(\.source.hash)
        return GraphCoding.hash((try? GraphCoding.data(components)) ?? Data())
    }

    /// Moves inline YAML from pre-store documents into the shared store.
    /// Returns true when the document should be rewritten without it.
    mutating func migrateLegacySources() throws -> Bool {
        var changed = false
        if let yaml = base.legacyYAML {
            try MeaningGraphSourceStore.store(yaml: yaml, hash: base.hash)
            base.legacyYAML = nil
            changed = true
        }
        for index in overlays.indices {
            guard let yaml = overlays[index].source.legacyYAML else { continue }
            try MeaningGraphSourceStore.store(yaml: yaml, hash: overlays[index].source.hash)
            overlays[index].source.legacyYAML = nil
            changed = true
        }
        return changed
    }
}

enum MeaningGraphProjectStore {
    static let documentType = "meaning_graph_selection"
    static let defaultKey = "LitScenesDefaultMeaningGraphHash"
    static var libraryURL: URL { litScenesApplicationSupportDirectory().appendingPathComponent("meaning-graphs", isDirectory: true) }

    static func load(project: ProjectRecord, library: ProjectLibrary) throws -> ProjectMeaningGraphSelection {
        let store = ProjectSQLiteDocumentStore(projectLibrary: library)
        if var selection = try store.loadDocument(ProjectMeaningGraphSelection.self, for: project, documentType: documentType) {
            try MeaningGraphSourceStore.retainAvailableSources(selection)
            if try selection.migrateLegacySources() { try save(selection, project: project, library: library) }
            return selection
        }
        let selection = ProjectMeaningGraphSelection(base: try defaultSource())
        try save(selection, project: project, library: library)
        return selection
    }

    static func defaultSource() throws -> MeaningGraphSource {
        if let hash = UserDefaults.standard.string(forKey: defaultKey), hash.count == 64,
           hash.allSatisfy(\.isHexDigit) {
            let file = libraryURL.appendingPathComponent("\(hash).json")
            if let data = try? Data(contentsOf: file),
               let source = try? JSONCoding.decoder.decode(MeaningGraphSource.self, from: data),
               source.kind == "base", source.hash == hash, MeaningGraphSourceStore.isAvailable(source) {
                return source
            }
        }
        return try .bundled()
    }

    static func save(_ selection: ProjectMeaningGraphSelection, project: ProjectRecord, library: ProjectLibrary) throws {
        try MeaningGraphSourceStore.retainAvailableSources(selection)
        let data = try JSONCoding.encoder.encode(selection)
        let store = ProjectSQLiteDocumentStore(projectLibrary: library)
        var writes = [ProjectDocumentBatchWrite(data: data, documentType: documentType),
            ProjectDocumentBatchWrite(data: data, documentType: "meaning_graph_history", documentId: selection.effectiveHash)]
        if let previous = try store.loadDocument(ProjectMeaningGraphSelection.self, for: project, documentType: documentType) {
            writes.append(ProjectDocumentBatchWrite(data: try JSONCoding.encoder.encode(previous),
                documentType: "meaning_graph_history", documentId: previous.effectiveHash))
        }
        try store.saveDocumentsAtomically(writes, for: project)
    }
}

struct MeaningGraphChangePreview: Sendable {
    var counts: [String: Int]
    var changes: [String]
    var provenance: MeaningGraphProvenance
}

extension ProjectGoalAestheticTermFacetType {
    /// Upper bound of terms offered per facet in the Goal interview choice list.
    var goalChoiceCap: Int {
        switch self {
        case .keyColour: 24
        case .keyMotif: 160
        case .keyValue: 120
        case .originDecade: 40
        }
    }
}

actor MeaningGraphRuntime {
    static let shared = MeaningGraphRuntime()
    private var snapshots: [String: MeaningGraphSnapshot] = [:]
    private var bundledSnapshot: MeaningGraphSnapshot?

    /// Facets the Goal brief can hold, each with its choice-list cap.
    static var goalTermCaps: [String: Int] {
        Dictionary(uniqueKeysWithValues: ProjectGoalAestheticTermFacetType.allCases.map { ($0.rawValue, $0.goalChoiceCap) })
    }

    private func bundled() throws -> MeaningGraphSnapshot {
        if let bundledSnapshot { return bundledSnapshot }
        let snapshot = try MeaningGraphSnapshot.open(MeaningGraphSourceStore.bundledDatabaseURL())
        bundledSnapshot = snapshot
        return snapshot
    }

    private func cacheURL(_ effectiveHash: String) -> URL {
        MeaningGraphProjectStore.libraryURL.appendingPathComponent("compiled", isDirectory: true)
            .appendingPathComponent("\(effectiveHash).sqlite")
    }

    func snapshot(_ selection: ProjectMeaningGraphSelection?) throws -> MeaningGraphSnapshot {
        guard let selection else { return try bundled() }
        guard selection.schemaVersion == "litscenes.project_meaning_graph.v1", selection.base.kind == "base",
              selection.overlays.allSatisfy({ $0.source.kind == "overlay" }) else { throw MeaningGraphError("Unsupported project graph configuration.") }
        let hash = selection.effectiveHash
        if let snapshot = snapshots[hash] { return snapshot }
        let bundled = try bundled()
        if selection.overlays.allSatisfy({ !$0.enabled }), bundled.provenance.baseHash == selection.base.hash {
            snapshots[hash] = bundled
            return bundled
        }
        let cache = cacheURL(hash)
        if let existing = try? MeaningGraphSnapshot.open(cache), existing.provenance.effectiveHash == hash {
            snapshots[hash] = existing
            return existing
        }
        let base = try MeaningGraphSourceStore.yaml(for: selection.base)
        let overlays = try selection.overlays.filter(\.enabled).map { try MeaningGraphSourceStore.yaml(for: $0.source) }
        let compiled = try MeaningGraphCompiler.compile(base: base, overlays: overlays, to: cache)
        snapshots[hash] = compiled
        return compiled
    }

    func preview(_ selection: ProjectMeaningGraphSelection, replacing previous: ProjectMeaningGraphSelection?) throws -> MeaningGraphChangePreview {
        let next = try snapshot(selection)
        var changes: [String] = []
        if let previous {
            let old = try snapshot(previous)
            for table in MeaningGraphCompiler.tableNames {
                let before = Dictionary(uniqueKeysWithValues: try old.records(table).map { ($0.text("id"), $0) })
                let after = Dictionary(uniqueKeysWithValues: try next.records(table).map { ($0.text("id"), $0) })
                let added = Set(after.keys).subtracting(before.keys).count
                let removed = Set(before.keys).subtracting(after.keys).count
                let changed = after.filter { before[$0.key] != nil && before[$0.key] != $0.value }.count
                if added + removed + changed > 0 { changes.append("\(table.capitalized): \(added) added, \(changed) changed, \(removed) disabled or removed") }
            }
        }
        return MeaningGraphChangePreview(counts: next.provenance.counts, changes: changes, provenance: next.provenance)
    }

    /// Installed sources whose YAML is present on this Mac. Metadata files that
    /// still carry inline YAML are migrated to the shared store on the way.
    func installedSources() throws -> [MeaningGraphSource] {
        var result = [try MeaningGraphSource.bundled()]
        let files = (try? FileManager.default.contentsOfDirectory(at: MeaningGraphProjectStore.libraryURL, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  var source = try? JSONCoding.decoder.decode(MeaningGraphSource.self, from: data) else { continue }
            if let yaml = source.legacyYAML {
                guard (try? MeaningGraphSourceStore.store(yaml: yaml, hash: source.hash)) != nil else { continue }
                source.legacyYAML = nil
                try? JSONCoding.encoder.encode(source).write(to: file, options: .atomic)
            }
            guard MeaningGraphSourceStore.isAvailable(source), !result.contains(where: { $0.hash == source.hash }) else { continue }
            result.append(source)
        }
        return result.sorted { ($0.title, $0.version) < ($1.title, $1.version) }
    }

    /// Validates, stores the YAML once, and records the source in the library.
    func install(_ source: MeaningGraphSource, yaml: String) throws {
        guard GraphCoding.hash(Data(yaml.utf8)) == source.hash else { throw MeaningGraphError("Graph source checksum mismatch.") }
        if source.kind == "base" {
            let selection = ProjectMeaningGraphSelection(base: source)
            if try bundled().provenance.baseHash != source.hash {
                snapshots[selection.effectiveHash] = try MeaningGraphCompiler.compile(base: yaml, overlays: [], to: cacheURL(selection.effectiveHash))
            }
        } else {
            _ = try MeaningGraphOverlay.load(yaml)
        }
        try MeaningGraphSourceStore.store(yaml: yaml, hash: source.hash)
        try FileManager.default.createDirectory(at: MeaningGraphProjectStore.libraryURL, withIntermediateDirectories: true)
        try JSONCoding.encoder.encode(source).write(to: MeaningGraphProjectStore.libraryURL.appendingPathComponent("\(source.hash).json"), options: .atomic)
    }

    func importSource(_ url: URL) throws -> MeaningGraphSource {
        let allowed = url.startAccessingSecurityScopedResource()
        defer { if allowed { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 64 * 1024 * 1024 else { throw MeaningGraphError("Graph YAML exceeds 64 MB.") }
        let parsed = try MeaningGraphSource.parse(Data(contentsOf: url))
        try install(parsed.source, yaml: parsed.yaml)
        return parsed.source
    }

    func downloadOfficialUpdate() async throws -> MeaningGraphSource {
        struct Manifest: Decodable {
            var schemaVersion: String; var packId: String; var version: String
            var sha256: String; var byteSize: Int; var url: String
        }
        let manifestURL = URL(string: "https://raw.githubusercontent.com/litscenes/litscenes/main/Sources/LitScenes/Resources/MeaningGraph/manifest.json")!
        var request = URLRequest(url: manifestURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 100_000 else {
            throw MeaningGraphError("The official graph update manifest is unavailable. Your installed graph is unchanged.")
        }
        let manifest = try JSONCoding.decoder.decode(Manifest.self, from: data)
        guard manifest.schemaVersion == "litscenes.meaning_graph_manifest.v1", manifest.packId == "litscenes.meaning",
              manifest.byteSize > 0, manifest.byteSize <= 64 * 1024 * 1024,
              manifest.sha256.count == 64, manifest.sha256.allSatisfy(\.isHexDigit),
              let url = URL(string: manifest.url), url.scheme == "https", url.user == nil, url.password == nil,
              url.host == "github.com", url.path.hasPrefix("/litscenes/litscenes/releases/download/") else {
            throw MeaningGraphError("The official graph update manifest is invalid.")
        }
        var download = URLRequest(url: url)
        download.timeoutInterval = 90
        let (file, result) = try await URLSession.shared.download(for: download)
        defer { try? FileManager.default.removeItem(at: file) }
        guard (result as? HTTPURLResponse)?.statusCode == 200,
              try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == manifest.byteSize else {
            throw MeaningGraphError("The published graph pack is unavailable or incomplete. Your installed graph is unchanged.")
        }
        let bytes = try Data(contentsOf: file)
        guard GraphCoding.hash(bytes) == manifest.sha256.lowercased() else { throw MeaningGraphError("Downloaded graph checksum mismatch.") }
        let parsed = try MeaningGraphSource.parse(bytes)
        guard parsed.source.packId == manifest.packId, parsed.source.version == manifest.version else { throw MeaningGraphError("Downloaded graph identity mismatch.") }
        try install(parsed.source, yaml: parsed.yaml)
        return parsed.source
    }

    /// Bounded choice packet for the Goal interview: the brief's own concepts,
    /// concepts matched to the conversation, at least three of every concept
    /// kind, and capped Goal-facet terms ranked by relevance then breadth of use.
    func choiceContext(selection: ProjectMeaningGraphSelection?, query: String, selectedSlugs: [String], termCaps: [String: Int]) throws -> String {
        let graph = try snapshot(selection)
        var rows: [GraphRecord] = []
        var seen = Set<String>()
        func add(_ row: GraphRecord) {
            if seen.insert(row.text("id")).inserted { rows.append(row) }
        }
        for slug in selectedSlugs.prefix(32) {
            if let row = try graph.node(slug) { add(row) }
        }
        for row in try graph.search(query, limit: 64) { add(row) }
        for kind in try graph.kinds() where rows.filter({ $0.text("kind") == kind }).count < 3 {
            for row in try graph.nodes(kind: kind, limit: 3) { add(row) }
        }
        let choices = rows.map { row in
            row.filter { ["id", "slug", "kind", "name", "definition", "aliases", "tags", "status"].contains($0.key) }
        }
        let terms = try graph.termChoices(query: query, caps: termCaps).map { row in
            row.filter { ["slug", "display_name", "normalized_value", "facet_type"].contains($0.key) }
        }
        let packet: GraphRecord = ["schema_version": .string("litscenes.meaning_choice_index_goal.v0.1"),
            "index_version": .string(graph.provenance.effectiveHash),
            "meaning_node_choices": .array(choices.map(GraphValue.object)),
            "aesthetic_term_choices": .array(terms.map(GraphValue.object)),
            "source_summary": .string("Relevant choices from the project's local meaning graph: concepts matched to this conversation with every kind represented, and Goal-facet aesthetic terms ranked by relevance then breadth of use. A bounded retrieval, not the whole vocabulary.")]
        return String(decoding: try GraphCoding.data(packet), as: UTF8.self)
    }
}
