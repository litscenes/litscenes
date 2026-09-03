import Foundation

enum MediaObservationConstants {
    static let schemaVersion = "litscenes.image_observation.v0.2"
    static let promptVersion = "litscenes.image_observer.project_neutral.v0.2"
    static let thumbnailPolicyVersion = "litscenes.vision_thumbnail_policy.v0.1"
    static let desktopDocumentSchemaVersion = "litscenes.desktop.media_observations.v0.1"
}

enum MediaAnalysisRunState: String, Codable, Hashable {
    case idle
    case running
    case succeeded
    case cancelled
    case failed

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .running:
            return "Running"
        case .succeeded:
            return "Completed"
        case .cancelled:
            return "Cancelled"
        case .failed:
            return "Failed"
        }
    }
}

struct MediaAnalysisLogEntry: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var timestamp: String
    var kind: String
    var message: String
}

struct VisibleTextObservation: Codable, Hashable {
    var text: String = ""
    var whereSeen: String = ""
    var confidence0To1: Double = 0
}

struct DomainEntity: Codable, Hashable {
    var name: String = ""
    var kind: String = "unknown"
    var visibleEvidence: String = ""
    var confidence0To1: Double = 0
}

struct FlagSymbolSignage: Codable, Hashable {
    var name: String = ""
    var kind: String = "other"
    var visibleEvidence: String = ""
    var confidence0To1: Double = 0
}

struct EventContext: Codable, Hashable {
    var eventType: String = "unknown"
    var eventNameGuess: String = ""
    var competitionOrProgramGuess: String = ""
    var why: String = ""
    var confidence0To1: Double = 0
}

struct ObservationUncertainty: Codable, Hashable {
    var field: String = ""
    var question: String = ""
    var whyUncertain: String = ""
}

struct MediaRoleAssessment: Codable, Hashable {
    var mediaRole: String = "unknown"
    var why: String = ""
    var confidence0To1: Double = 0
}

struct HumanOverride: Codable, Hashable {
    var needsReview: Bool = false
    var reviewReason: String = ""
    var suggestedQuestion: String = ""
}

struct UserProvidedContext: Codable, Hashable {
    var knownContext: String = ""
    var domainTags: [String] = []
    var preferredMediaRole: String = ""
    var notes: String = ""
}

struct ImageObjectDescription: Codable, Hashable {
    var accurateTitle: String = ""
    var thoroughDescription: String = ""
}

struct ImageObservationResult: Codable, Hashable, Identifiable {
    var schemaVersion: String = MediaObservationConstants.schemaVersion
    var mediaId: String = ""
    var id: String { mediaId }
    var frameId: String = ""
    var sourcePath: String = ""
    var imageHash: String = ""
    var observationProvider: String = ""
    var model: String = ""
    var promptVersion: String = MediaObservationConstants.promptVersion
    var createdAt: String = ""

    var plainCaption: String = ""
    var literalDescription: String = ""
    var objects: [String] = []
    var objectDescriptions: [ImageObjectDescription] = []
    var peopleVisible: Bool = false
    var peopleCountEstimate: Int?
    var peopleRolesVisible: [String] = []
    var activities: [String] = []
    var setting: String = ""
    var lighting: String = ""
    var mood: [String] = []
    var materials: [String] = []
    var visualSpecificity: [String] = []
    var paletteTerms: [String] = []
    var placeCues: [String] = []
    var eraCues: [String] = []
    var motifCues: [String] = []
    var energyCues: [String] = []
    var compositionCues: [String] = []

    var visibleText: [VisibleTextObservation] = []
    var logosBrandsOrganizations: [DomainEntity] = []
    var flagsSymbolsSignage: [FlagSymbolSignage] = []
    var eventContext: EventContext = EventContext()
    var mediaRole: String = "unknown"
    var mediaRoleAssessment: MediaRoleAssessment = MediaRoleAssessment()

    var sourceKindNotes: String = ""
    var domainTags: [String] = []
    var localContextTags: [String] = []
    var technicalContextTags: [String] = []
    var storyObservationTags: [String] = []

    var possibleMeanings: [String] = []
    var negativeConstraints: [String] = []
    var uncertainties: [ObservationUncertainty] = []
    var humanReview: HumanOverride = HumanOverride()

    var detailPassUsed: Bool = false
    var detailPassReason: String = ""
    var detailObservationNotes: String = ""
    var objectDescriptionPassUsed: Bool = false
    var objectDescriptionPromptVersion: String = ""
    var userProvidedContext: UserProvidedContext = UserProvidedContext()

    var sourceImagePath: String = ""
    var sourceImageSha256: String = ""
    var visionInputKind: String = ""
    var visionInputPath: String = ""
    var visionInputSha256: String = ""
    var visionInputWidth: Int = 0
    var visionInputHeight: Int = 0
    var visionInputBytes: Int = 0
    var visionThumbnailProfile: String = ""
    var fullresVisionAllowed: Bool = false
    var thumbnailPolicyVersion: String = MediaObservationConstants.thumbnailPolicyVersion
    var detailVisionInputKind: String = ""
    var detailVisionInputPath: String = ""
    var detailVisionInputSha256: String = ""
    var detailVisionInputWidth: Int = 0
    var detailVisionInputHeight: Int = 0
    var detailVisionInputBytes: Int = 0
    var detailVisionThumbnailProfile: String = ""

    static func decode(from data: Data) throws -> ImageObservationResult {
        try JSONCoding.decoder.decode(ImageObservationResult.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }

    var isCurrentAestheticObservationVersion: Bool {
        schemaVersion == MediaObservationConstants.schemaVersion
            && promptVersion == MediaObservationConstants.promptVersion
            && thumbnailPolicyVersion == MediaObservationConstants.thumbnailPolicyVersion
    }
}

struct MediaObservationDocument: Codable, Hashable {
    var schemaVersion: String = MediaObservationConstants.desktopDocumentSchemaVersion
    var projectId: String
    var generatedAt: String
    var observations: [ImageObservationResult]
}

/// Compact one-line mood-influence description for a moodboard image, injected
/// verbatim into take render prompts. Same field recipe as the GOAL interview's
/// moodboard packet, scoped to render-relevant cues; per-field truncation keeps
/// three lines comfortably inside provider prompt limits.
func moodInfluenceLine(filename: String, observation: ImageObservationResult) -> String {
    func truncated(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmed
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)).trimmed + "…"
    }

    var parts: [String] = []
    let caption = observation.plainCaption.trimmed
    if !caption.isEmpty {
        parts.append("caption=\(truncated(caption, limit: 140))")
    }
    if !observation.mood.isEmpty {
        parts.append("mood=\(observation.mood.prefix(3).joined(separator: ", "))")
    }
    if !observation.paletteTerms.isEmpty {
        parts.append("palette=\(observation.paletteTerms.prefix(4).joined(separator: ", "))")
    }
    let setting = observation.setting.trimmed
    if !setting.isEmpty {
        parts.append("setting=\(truncated(setting, limit: 90))")
    }
    let lighting = observation.lighting.trimmed
    if !lighting.isEmpty {
        parts.append("lighting=\(truncated(lighting, limit: 90))")
    }
    guard !parts.isEmpty else { return "" }
    return "\(filename.trimmed): \(parts.joined(separator: " | "))"
}
