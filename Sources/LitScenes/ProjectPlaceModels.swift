import Foundation

/// A defined place (location) of the project: a unique name, a description prompt, and
/// the ordered project media the user has organized under it. Mirrors ProjectObject so
/// places attach as name-keyed @mention references without model changes. Places are
/// auto-proposed from the lens composition's areas — the two areas ARE the scene's two
/// places.
struct ProjectPlace: Codable, Hashable, Identifiable, Sendable {
    var placeId: String
    var name: String
    var descriptionPrompt: String = ""
    /// Ordered MediaItemRecord.mediaId values; the first entries are the strongest
    /// references.
    var referenceMediaIds: [String] = []
    /// Optional per-reference labels keyed by mediaId ("porch side", "at low tide").
    /// Keys not in referenceMediaIds prune on normalize.
    var referenceLabels: [String: String] = [:]
    var updatedAt: String = DateFormats.now()

    var id: String { placeId }

    func normalized() -> ProjectPlace {
        var value = self
        value.placeId = value.placeId.trimmed
        if value.placeId.isEmpty {
            value.placeId = "place_\(shortHash("\(value.name):\(value.updatedAt)", length: 12))"
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
        case placeId
        case name
        case descriptionPrompt
        case referenceMediaIds
        case referenceLabels
        case updatedAt
    }

    init(
        placeId: String,
        name: String,
        descriptionPrompt: String = "",
        referenceMediaIds: [String] = [],
        referenceLabels: [String: String] = [:],
        updatedAt: String = DateFormats.now()
    ) {
        self.placeId = placeId
        self.name = name
        self.descriptionPrompt = descriptionPrompt
        self.referenceMediaIds = referenceMediaIds
        self.referenceLabels = referenceLabels
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        placeId = try container.decodeIfPresent(String.self, forKey: .placeId) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        descriptionPrompt = try container.decodeIfPresent(String.self, forKey: .descriptionPrompt) ?? ""
        referenceMediaIds = try container.decodeIfPresent([String].self, forKey: .referenceMediaIds) ?? []
        referenceLabels = try container.decodeIfPresent([String: String].self, forKey: .referenceLabels) ?? [:]
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
        self = normalized()
    }
}

/// The project's place roster, persisted as one project document (no table change).
struct ProjectPlaceSetDocument: Codable, Hashable {
    static let schemaVersion = "litscenes.project_places.v0.1"
    static let documentType = "project_places"

    var schemaVersion: String = ProjectPlaceSetDocument.schemaVersion
    var projectId: String = ""
    var places: [ProjectPlace] = []
    var updatedAt: String = ""

    static func empty(projectId: String) -> ProjectPlaceSetDocument {
        ProjectPlaceSetDocument(projectId: projectId)
    }

    func place(withId placeId: String) -> ProjectPlace? {
        places.first { $0.placeId == placeId }
    }

    /// Case-insensitive uniqueness check for a (possibly renamed) place's name.
    func nameIsAvailable(_ name: String, excludingPlaceId: String? = nil) -> Bool {
        let candidate = name.trimmed.lowercased()
        guard !candidate.isEmpty else { return false }
        return !places.contains {
            $0.placeId != excludingPlaceId && $0.name.trimmed.lowercased() == candidate
        }
    }

    func normalized() -> ProjectPlaceSetDocument {
        var value = self
        value.schemaVersion = Self.schemaVersion
        value.projectId = value.projectId.trimmed
        var seenIds: Set<String> = []
        var seenNames: Set<String> = []
        value.places = value.places
            .map { $0.normalized() }
            .filter { place in
                guard !place.name.isEmpty,
                      !seenIds.contains(place.placeId),
                      !seenNames.contains(place.name.lowercased()) else {
                    return false
                }
                seenIds.insert(place.placeId)
                seenNames.insert(place.name.lowercased())
                return true
            }
        value.updatedAt = value.updatedAt.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case places
        case updatedAt
    }

    init(schemaVersion: String = ProjectPlaceSetDocument.schemaVersion, projectId: String = "", places: [ProjectPlace] = [], updatedAt: String = "") {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.places = places
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        places = try container.decodeIfPresent([ProjectPlace].self, forKey: .places) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        self = normalized()
    }
}
