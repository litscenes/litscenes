import CryptoKit
import Foundation
import Yams

public enum GraphValue: Codable, Hashable, Sendable {
    case string(String), number(Double), bool(Bool), array([GraphValue]), object([String: GraphValue]), null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([GraphValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: GraphValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var string: String { if case .string(let value) = self { value } else { "" } }
    public var number: Double { if case .number(let value) = self { value } else { 0 } }
    public var strings: [String] { if case .array(let values) = self { values.map(\.string) } else { [] } }
    public var object: GraphRecord { if case .object(let value) = self { value } else { [:] } }
}

public typealias GraphRecord = [String: GraphValue]

public extension Dictionary where Key == String, Value == GraphValue {
    func text(_ key: String) -> String { self[key]?.string ?? "" }
    func number(_ key: String) -> Double { self[key]?.number ?? 0 }
    func strings(_ key: String) -> [String] { self[key]?.strings ?? [] }
}

public struct MeaningGraphError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum GraphCoding {
    public static func data<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func yaml<T: Decodable>(_ type: T.Type, source: String) throws -> T {
        guard source.utf8.count <= 64 * 1024 * 1024 else { throw MeaningGraphError("Graph YAML exceeds 64 MB.") }
        guard let node = try Yams.compose(yaml: source) else { throw MeaningGraphError("Graph YAML is empty.") }
        try validate(node, depth: 0)
        return try YAMLDecoder().decode(type, from: node)
    }

    private static func validate(_ node: Node, depth: Int) throws {
        guard depth < 32 else { throw MeaningGraphError("Graph YAML is nested too deeply.") }
        switch node {
        case .alias: throw MeaningGraphError("Graph packs use literal data; YAML aliases are unsupported.")
        case .mapping(let map):
            var keys = Set<String>()
            for item in map {
                guard let key = item.key.string, keys.insert(key).inserted, key != "<<" else {
                    throw MeaningGraphError("Graph YAML contains a duplicate, complex, or merged key.")
                }
                try validate(item.value, depth: depth + 1)
            }
        case .sequence(let items):
            for item in items { try validate(item, depth: depth + 1) }
        case .scalar: break
        }
    }
}

public struct MeaningGraphPack: Codable, Sendable {
    public var schemaVersion: String
    public var packId: String
    public var version: String
    public var title: String
    public var generatedOn: String
    public var license: String
    public var nodes: [GraphRecord]
    public var edges: [GraphRecord]
    public var evidence: [GraphRecord]
    public var aesthetics: [GraphRecord]
    public var terms: [GraphRecord]
    public var assignments: [GraphRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", packId = "pack_id", generatedOn = "generated_on"
        case version, title, license, nodes, edges, evidence, aesthetics, terms, assignments
    }

    public var tables: [String: [GraphRecord]] {
        ["nodes": nodes, "edges": edges, "evidence": evidence,
         "aesthetics": aesthetics, "terms": terms, "assignments": assignments]
    }

    public static func load(_ source: String) throws -> Self {
        let pack = try GraphCoding.yaml(Self.self, source: source)
        guard pack.schemaVersion == "litscenes.meaning_graph.v1", !pack.packId.isEmpty,
              !pack.version.isEmpty, !pack.title.isEmpty else {
            throw MeaningGraphError("Unsupported graph pack format or missing pack identity.")
        }
        return pack
    }
}

public struct MeaningGraphOverlay: Codable, Sendable {
    public var schemaVersion: String
    public var packId: String
    public var version: String
    public var title: String
    public var basePackId: String
    public var operations: [Operation]

    public struct Operation: Codable, Sendable {
        public var table: String
        public var action: String
        public var id: String
        public var fields: GraphRecord?
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", packId = "pack_id", basePackId = "base_pack_id"
        case version, title, operations
    }

    public static func load(_ source: String) throws -> Self {
        let pack = try GraphCoding.yaml(Self.self, source: source)
        guard pack.schemaVersion == "litscenes.meaning_graph_overlay.v1",
              !pack.packId.isEmpty, !pack.version.isEmpty, !pack.title.isEmpty else {
            throw MeaningGraphError("Unsupported overlay format or missing identity.")
        }
        return pack
    }
}

public struct MeaningGraphProvenance: Codable, Hashable, Sendable {
    public var packId: String
    public var version: String
    public var baseHash: String
    public var overlayHashes: [String]
    public var effectiveHash: String
    public var resolverVersion: String
    public var title: String
    public var counts: [String: Int]
}

public struct GraphAestheticTerm: Sendable {
    public var term: String
    public var attributeKey: String
    public var source: String
    public var weight: Double
    public init(term: String, attributeKey: String, source: String, weight: Double) {
        self.term = term; self.attributeKey = attributeKey; self.source = source; self.weight = weight
    }
}
