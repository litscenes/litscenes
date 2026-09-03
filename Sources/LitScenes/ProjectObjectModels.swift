import Foundation

/// A defined object (prop) of the project: a unique name, a description prompt, and the
/// ordered project media the user has organized under it. Mirrors ProjectCharacter so
/// objects can later attach as name-keyed references without model changes.
struct ProjectObject: Codable, Hashable, Identifiable, Sendable {
    var objectId: String
    var name: String
    var descriptionPrompt: String = ""
    /// Ordered MediaItemRecord.mediaId values; the first entries are the strongest
    /// references.
    var referenceMediaIds: [String] = []
    /// Optional per-reference labels keyed by mediaId ("dented side", "lantern lit").
    /// Organizational only until object references attach at render. Keys not in
    /// referenceMediaIds prune on normalize.
    var referenceLabels: [String: String] = [:]
    var updatedAt: String = DateFormats.now()

    var id: String { objectId }

    func normalized() -> ProjectObject {
        var value = self
        value.objectId = value.objectId.trimmed
        if value.objectId.isEmpty {
            value.objectId = "object_\(shortHash("\(value.name):\(value.updatedAt)", length: 12))"
        }
        value.name = value.name.trimmed
        value.descriptionPrompt = value.descriptionPrompt.trimmed
        value.referenceMediaIds = uniqueNonEmpty(value.referenceMediaIds)
        let knownIds = Set(value.referenceMediaIds)
        value.referenceLabels = value.referenceLabels.reduce(into: [:]) { labels, pair in
            let mediaId = pair.key.trimmed
            let label = pair.value.trimmed
            guard !mediaId.isEmpty, !label.isEmpty, knownIds.contains(mediaId) else { return }
            labels[mediaId] = label
        }
        value.updatedAt = value.updatedAt.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case objectId
        case name
        case descriptionPrompt
        case referenceMediaIds
        case referenceLabels
        case updatedAt
    }

    init(
        objectId: String,
        name: String,
        descriptionPrompt: String = "",
        referenceMediaIds: [String] = [],
        referenceLabels: [String: String] = [:],
        updatedAt: String = DateFormats.now()
    ) {
        self.objectId = objectId
        self.name = name
        self.descriptionPrompt = descriptionPrompt
        self.referenceMediaIds = referenceMediaIds
        self.referenceLabels = referenceLabels
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objectId = try container.decodeIfPresent(String.self, forKey: .objectId) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        descriptionPrompt = try container.decodeIfPresent(String.self, forKey: .descriptionPrompt) ?? ""
        referenceMediaIds = try container.decodeIfPresent([String].self, forKey: .referenceMediaIds) ?? []
        referenceLabels = try container.decodeIfPresent([String: String].self, forKey: .referenceLabels) ?? [:]
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
        self = normalized()
    }
}

/// The project's object roster, persisted as one project document (no table change).
struct ProjectObjectSetDocument: Codable, Hashable {
    static let schemaVersion = "litscenes.project_objects.v0.1"
    static let documentType = "project_objects"

    var schemaVersion: String = ProjectObjectSetDocument.schemaVersion
    var projectId: String = ""
    var objects: [ProjectObject] = []
    var updatedAt: String = ""

    static func empty(projectId: String) -> ProjectObjectSetDocument {
        ProjectObjectSetDocument(projectId: projectId)
    }

    func object(withId objectId: String) -> ProjectObject? {
        objects.first { $0.objectId == objectId }
    }

    /// Case-insensitive uniqueness check for a (possibly renamed) object's name.
    func nameIsAvailable(_ name: String, excludingObjectId: String? = nil) -> Bool {
        let candidate = name.trimmed.lowercased()
        guard !candidate.isEmpty else { return false }
        return !objects.contains {
            $0.objectId != excludingObjectId && $0.name.trimmed.lowercased() == candidate
        }
    }

    func normalized() -> ProjectObjectSetDocument {
        var value = self
        value.schemaVersion = Self.schemaVersion
        value.projectId = value.projectId.trimmed
        var seenIds: Set<String> = []
        var seenNames: Set<String> = []
        value.objects = value.objects
            .map { $0.normalized() }
            .filter { object in
                guard !object.name.isEmpty,
                      !seenIds.contains(object.objectId),
                      !seenNames.contains(object.name.lowercased()) else {
                    return false
                }
                seenIds.insert(object.objectId)
                seenNames.insert(object.name.lowercased())
                return true
            }
        value.updatedAt = value.updatedAt.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case objects
        case updatedAt
    }

    init(schemaVersion: String = ProjectObjectSetDocument.schemaVersion, projectId: String = "", objects: [ProjectObject] = [], updatedAt: String = "") {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.objects = objects
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        objects = try container.decodeIfPresent([ProjectObject].self, forKey: .objects) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        self = normalized()
    }
}
