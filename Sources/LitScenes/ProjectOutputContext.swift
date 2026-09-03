import Foundation

struct ProjectOutputContext: Codable, Hashable {
    static let schemaVersion = "litscenes.project_output_context.v0.1"

    var schemaVersion: String = Self.schemaVersion
    var projectId: String
    var intendedMedium: String = ""
    var durationHint: String = ""
    var aspectRatio: String = ""
    var destinationOrChannel: String = ""
    var providerConstraints: [String] = []
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String = "") -> ProjectOutputContext {
        ProjectOutputContext(projectId: projectId)
    }

    static func decode(from data: Data) throws -> ProjectOutputContext {
        try JSONCoding.decoder.decode(ProjectOutputContext.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }
}
