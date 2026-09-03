import Foundation

struct AestheticCatalogFacet: Codable, Hashable, Sendable {
    var facetType: String
    var value: String
    var polarity: String
    var weight: Double
}

struct AestheticCatalogRule: Codable, Hashable, Sendable {
    var area: String
    var instruction: String
    var strength: Double
    var rank: Int
}

struct AestheticCatalogItem: Codable, Identifiable, Hashable, Sendable {
    var aestheticId: String
    var id: String { aestheticId }
    var profileId: String = ""
    var slug: String
    var title: String
    var summary: String = ""
    var description: String = ""
    var profileBasis: String = ""
    var textConfidence: Double = 0
    var visualConfidence: Double = 0
    var overallConfidence: Double = 0
    var isPrimary: Bool = false
    var isActive: Bool = true
    var profileStatus: String = ""
    var qualityFlags: [String] = []
    var sourceArtifactWarnings: [String] = []
    var previewImageUrl: String = ""
    var facets: [AestheticCatalogFacet] = []
    var rules: [AestheticCatalogRule] = []

    var displaySummary: String {
        let cleanedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedSummary.isEmpty {
            return cleanedSummary
        }
        return description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var confidenceLabel: String {
        if overallConfidence >= 0.72 {
            return "High"
        }
        if overallConfidence >= 0.42 {
            return "Medium"
        }
        if overallConfidence > 0 {
            return "Low"
        }
        return "Unprofiled"
    }
}

struct AestheticReferenceCandidate: Codable, Identifiable, Hashable, Sendable {
    var aestheticId: String
    var id: String { aestheticId }
    var profileId: String = ""
    var slug: String
    var title: String
    var plainEnglishEffect: String = ""
    var suggestedRole: String = "reference"
    var score0To1: Double
    var confidenceLabel: String
    var becauseChips: [String] = []
    var whyItFits: String = ""
    var whatItChanges: String = ""
    var caveat: String = ""
    var evidenceMediaIds: [String] = []
    var previewImageUrl: String = ""
    var axisValues: [String: Double] = [:]
}

enum AestheticBriefReferenceRole: String, Codable, CaseIterable, Identifiable, Sendable {
    case core
    case accent
    case texture
    case avoid
    case reference

    var id: String { rawValue }

    var label: String {
        switch self {
        case .core:
            return "Core"
        case .accent:
            return "Accent"
        case .texture:
            return "Texture"
        case .avoid:
            return "Avoid"
        case .reference:
            return "Reference"
        }
    }
}

struct AestheticBriefReference: Codable, Identifiable, Hashable, Sendable {
    var aestheticId: String
    var id: String { aestheticId }
    var profileId: String = ""
    var slug: String = ""
    var title: String
    var summary: String = ""
    var previewImageUrl: String = ""
    var role: AestheticBriefReferenceRole = .reference
    var weight: Double = 0.5
    var notes: String = ""
    var addedAt: String = DateFormats.now()
}

struct AestheticIngredientControl: Codable, Identifiable, Hashable, Sendable {
    var id: String { key }
    var key: String
    var label: String
    var value0To1: Double = 0.5
}

struct ProjectAestheticDirectionRecipe: Codable, Identifiable, Hashable, Sendable {
    var recipeId: String = "recipe_\(UUID().uuidString.lowercased())"
    var id: String { recipeId }
    var recipeVersion: String = "litscenes.direction_recipe.v0.2"
    var title: String
    var lane: String = ""
    var coreReference: AestheticBriefReference
    var flavorReferences: [AestheticBriefReference] = []
    var avoidTerms: [String] = []
    var intensity0To1: Double = 0.65
    var ingredientControls: [AestheticIngredientControl] = []
    var visualSummary: String = ""
    var treatmentNotes: [String] = []
    var bestAppliedTo: [String] = []
    var useFor: [String] = []
    var paletteTerms: [String] = []
    var signatureTerms: [String] = []
    var previewImagePaths: [String] = []
    var selectedCompositeRouteKey: String = ""
    var selectedCompositeVersionId: String = ""
    var selectedCompositeImagePath: String = ""
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()
    var source: String = "direction_card"

    var selectedReferences: [AestheticBriefReference] {
        [coreReference] + flavorReferences
    }

    init(
        recipeId: String = "recipe_\(UUID().uuidString.lowercased())",
        recipeVersion: String = "litscenes.direction_recipe.v0.2",
        title: String,
        lane: String = "",
        coreReference: AestheticBriefReference,
        flavorReferences: [AestheticBriefReference] = [],
        avoidTerms: [String] = [],
        intensity0To1: Double = 0.65,
        ingredientControls: [AestheticIngredientControl] = [],
        visualSummary: String = "",
        treatmentNotes: [String] = [],
        bestAppliedTo: [String] = [],
        useFor: [String] = [],
        paletteTerms: [String] = [],
        signatureTerms: [String] = [],
        previewImagePaths: [String] = [],
        selectedCompositeRouteKey: String = "",
        selectedCompositeVersionId: String = "",
        selectedCompositeImagePath: String = "",
        createdAt: String = DateFormats.now(),
        updatedAt: String = DateFormats.now(),
        source: String = "direction_card"
    ) {
        self.recipeId = recipeId
        self.recipeVersion = recipeVersion
        self.title = title
        self.lane = lane
        self.coreReference = coreReference
        self.flavorReferences = flavorReferences
        self.avoidTerms = avoidTerms
        self.intensity0To1 = intensity0To1
        self.ingredientControls = ingredientControls
        self.visualSummary = visualSummary
        self.treatmentNotes = treatmentNotes
        self.bestAppliedTo = bestAppliedTo
        self.useFor = useFor
        self.paletteTerms = paletteTerms
        self.signatureTerms = signatureTerms
        self.previewImagePaths = previewImagePaths
        self.selectedCompositeRouteKey = selectedCompositeRouteKey
        self.selectedCompositeVersionId = selectedCompositeVersionId
        self.selectedCompositeImagePath = selectedCompositeImagePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case recipeId
        case recipeVersion
        case title
        case lane
        case coreReference
        case flavorReferences
        case avoidTerms
        case intensity0To1
        case ingredientControls
        case visualSummary
        case treatmentNotes
        case bestAppliedTo
        case makesFeelLike
        case adds
        case bestFor
        case useFor
        case paletteTerms
        case signatureTerms
        case previewImagePaths
        case selectedCompositeRouteKey
        case selectedCompositeVersionId
        case selectedCompositeImagePath
        case createdAt
        case updatedAt
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let now = DateFormats.now()
        recipeId = try container.decodeIfPresent(String.self, forKey: .recipeId) ?? "recipe_\(UUID().uuidString.lowercased())"
        recipeVersion = try container.decodeIfPresent(String.self, forKey: .recipeVersion) ?? "litscenes.direction_recipe.v0.2"
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        lane = try container.decodeIfPresent(String.self, forKey: .lane) ?? ""
        coreReference = try container.decodeIfPresent(AestheticBriefReference.self, forKey: .coreReference)
            ?? AestheticBriefReference(aestheticId: "", title: "")
        flavorReferences = try container.decodeIfPresent([AestheticBriefReference].self, forKey: .flavorReferences) ?? []
        avoidTerms = try container.decodeIfPresent([String].self, forKey: .avoidTerms) ?? []
        intensity0To1 = try container.decodeIfPresent(Double.self, forKey: .intensity0To1) ?? 0.65
        ingredientControls = try container.decodeIfPresent([AestheticIngredientControl].self, forKey: .ingredientControls) ?? []
        let legacyVisualSummary = try container.decodeIfPresent(String.self, forKey: .makesFeelLike)
        visualSummary = try container.decodeIfPresent(String.self, forKey: .visualSummary) ?? legacyVisualSummary ?? ""
        let legacyTreatmentNotes = try container.decodeIfPresent([String].self, forKey: .adds)
        treatmentNotes = try container.decodeIfPresent([String].self, forKey: .treatmentNotes) ?? legacyTreatmentNotes ?? []
        let legacyBestAppliedTo = try container.decodeIfPresent([String].self, forKey: .bestFor)
        bestAppliedTo = try container.decodeIfPresent([String].self, forKey: .bestAppliedTo) ?? legacyBestAppliedTo ?? []
        useFor = try container.decodeIfPresent([String].self, forKey: .useFor) ?? []
        paletteTerms = try container.decodeIfPresent([String].self, forKey: .paletteTerms) ?? []
        signatureTerms = try container.decodeIfPresent([String].self, forKey: .signatureTerms) ?? []
        previewImagePaths = try container.decodeIfPresent([String].self, forKey: .previewImagePaths) ?? []
        selectedCompositeRouteKey = try container.decodeIfPresent(String.self, forKey: .selectedCompositeRouteKey) ?? ""
        selectedCompositeVersionId = try container.decodeIfPresent(String.self, forKey: .selectedCompositeVersionId) ?? ""
        selectedCompositeImagePath = try container.decodeIfPresent(String.self, forKey: .selectedCompositeImagePath) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? now
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "direction_card"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(recipeId, forKey: .recipeId)
        try container.encode(recipeVersion, forKey: .recipeVersion)
        try container.encode(title, forKey: .title)
        try container.encode(lane, forKey: .lane)
        try container.encode(coreReference, forKey: .coreReference)
        try container.encode(flavorReferences, forKey: .flavorReferences)
        try container.encode(avoidTerms, forKey: .avoidTerms)
        try container.encode(intensity0To1, forKey: .intensity0To1)
        try container.encode(ingredientControls, forKey: .ingredientControls)
        try container.encode(visualSummary, forKey: .visualSummary)
        try container.encode(treatmentNotes, forKey: .treatmentNotes)
        try container.encode(bestAppliedTo, forKey: .bestAppliedTo)
        try container.encode(useFor, forKey: .useFor)
        try container.encode(paletteTerms, forKey: .paletteTerms)
        try container.encode(signatureTerms, forKey: .signatureTerms)
        try container.encode(previewImagePaths, forKey: .previewImagePaths)
        try container.encode(selectedCompositeRouteKey, forKey: .selectedCompositeRouteKey)
        try container.encode(selectedCompositeVersionId, forKey: .selectedCompositeVersionId)
        try container.encode(selectedCompositeImagePath, forKey: .selectedCompositeImagePath)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(source, forKey: .source)
    }
}

struct AestheticCompositePromptFields: Codable, Hashable, Sendable {
    var subjectCapsule: String = ""
    var directionLabel: String = ""
    var core: String = ""
    var flavor: String = ""
    var visualSummary: String = ""
    var treatmentNotes: String = ""
    var palette: String = ""
    var frameApplication: String = "one representative comparison frame"
    var avoidTerms: String = ""

    enum CodingKeys: String, CodingKey {
        case subjectCapsule
        case directionLabel
        case core
        case flavor
        case visualSummary
        case treatmentNotes
        case palette
        case frameApplication
        case avoidTerms
        case directionTitle
        case makesFeelLike
        case adds
        case frameType
    }

    init(
        subjectCapsule: String = "",
        directionLabel: String = "",
        core: String = "",
        flavor: String = "",
        visualSummary: String = "",
        treatmentNotes: String = "",
        palette: String = "",
        frameApplication: String = "one representative comparison frame",
        avoidTerms: String = ""
    ) {
        self.subjectCapsule = subjectCapsule
        self.directionLabel = directionLabel
        self.core = core
        self.flavor = flavor
        self.visualSummary = visualSummary
        self.treatmentNotes = treatmentNotes
        self.palette = palette
        self.frameApplication = frameApplication
        self.avoidTerms = avoidTerms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subjectCapsule = try container.decodeIfPresent(String.self, forKey: .subjectCapsule) ?? ""
        let legacyDirectionLabel = try container.decodeIfPresent(String.self, forKey: .directionTitle)
        directionLabel = try container.decodeIfPresent(String.self, forKey: .directionLabel) ?? legacyDirectionLabel ?? ""
        core = try container.decodeIfPresent(String.self, forKey: .core) ?? ""
        flavor = try container.decodeIfPresent(String.self, forKey: .flavor) ?? ""
        let legacyVisualSummary = try container.decodeIfPresent(String.self, forKey: .makesFeelLike)
        visualSummary = try container.decodeIfPresent(String.self, forKey: .visualSummary) ?? legacyVisualSummary ?? ""
        let legacyTreatmentNotes = try container.decodeIfPresent(String.self, forKey: .adds)
        treatmentNotes = try container.decodeIfPresent(String.self, forKey: .treatmentNotes) ?? legacyTreatmentNotes ?? ""
        palette = try container.decodeIfPresent(String.self, forKey: .palette) ?? ""
        let legacyFrameApplication = try container.decodeIfPresent(String.self, forKey: .frameType)
        frameApplication = try container.decodeIfPresent(String.self, forKey: .frameApplication) ?? legacyFrameApplication ?? "one representative comparison frame"
        avoidTerms = try container.decodeIfPresent(String.self, forKey: .avoidTerms) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subjectCapsule, forKey: .subjectCapsule)
        try container.encode(directionLabel, forKey: .directionLabel)
        try container.encode(core, forKey: .core)
        try container.encode(flavor, forKey: .flavor)
        try container.encode(visualSummary, forKey: .visualSummary)
        try container.encode(treatmentNotes, forKey: .treatmentNotes)
        try container.encode(palette, forKey: .palette)
        try container.encode(frameApplication, forKey: .frameApplication)
        try container.encode(avoidTerms, forKey: .avoidTerms)
    }
}

struct AestheticCompositeHeroImage: Codable, Identifiable, Hashable, Sendable {
    var imageId: String = "hero_image_\(UUID().uuidString.lowercased())"
    var id: String { imageId }
    var imageIndex: Int = 0
    var label: String = ""
    var imagePath: String = ""
    var prompt: String = ""
    var status: String = "draft"
    var requestId: String = ""
    var sourceSlotId: String = ""
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()
}

struct AestheticDirectionCompositeVersion: Codable, Identifiable, Hashable, Sendable {
    var versionId: String = "composite_version_\(UUID().uuidString.lowercased())"
    var id: String { versionId }
    var versionNumber: Int = 1
    var routeKey: String = ""
    var imagePath: String = ""
    var heroImages: [AestheticCompositeHeroImage] = []
    var prompt: String = ""
    var promptFields: AestheticCompositePromptFields = AestheticCompositePromptFields()
    var status: String = "draft"
    var requestId: String = ""
    var sourceProofCacheKey: String = ""
    var sourceSlotId: String = ""
    var editedByUser: Bool = false
    var createdAt: String = DateFormats.now()
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()

    var sortedHeroImages: [AestheticCompositeHeroImage] {
        let sorted = heroImages.sorted {
            if $0.imageIndex == $1.imageIndex {
                return $0.updatedAt < $1.updatedAt
            }
            return $0.imageIndex < $1.imageIndex
        }
        guard sorted.isEmpty,
              !imagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return sorted
        }
        return [
            AestheticCompositeHeroImage(
                imageId: "legacy_\(versionId)",
                imageIndex: 0,
                label: "Preview",
                imagePath: imagePath,
                prompt: prompt,
                status: status,
                requestId: requestId,
                sourceSlotId: sourceSlotId,
                generatedAt: generatedAt,
                updatedAt: updatedAt
            )
        ]
    }

    var readyHeroImages: [AestheticCompositeHeroImage] {
        sortedHeroImages.filter {
            $0.status == "ready"
                && !$0.imagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var primaryImagePath: String {
        let primaryHeroPath = readyHeroImages.first?.imagePath.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !primaryHeroPath.isEmpty {
            return primaryHeroPath
        }
        return imagePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasSelectablePreviewImage: Bool {
        !primaryImagePath.isEmpty
    }

    var isCompletePreviewSet: Bool {
        guard status == "ready" else { return false }
        if heroImages.isEmpty {
            return !primaryImagePath.isEmpty
        }
        return readyHeroImages.count >= 3
    }

    init(
        versionId: String = "composite_version_\(UUID().uuidString.lowercased())",
        versionNumber: Int = 1,
        routeKey: String = "",
        imagePath: String = "",
        heroImages: [AestheticCompositeHeroImage] = [],
        prompt: String = "",
        promptFields: AestheticCompositePromptFields = AestheticCompositePromptFields(),
        status: String = "draft",
        requestId: String = "",
        sourceProofCacheKey: String = "",
        sourceSlotId: String = "",
        editedByUser: Bool = false,
        createdAt: String = DateFormats.now(),
        generatedAt: String = "",
        updatedAt: String = DateFormats.now()
    ) {
        self.versionId = versionId
        self.versionNumber = versionNumber
        self.routeKey = routeKey
        self.imagePath = imagePath
        self.heroImages = heroImages
        self.prompt = prompt
        self.promptFields = promptFields
        self.status = status
        self.requestId = requestId
        self.sourceProofCacheKey = sourceProofCacheKey
        self.sourceSlotId = sourceSlotId
        self.editedByUser = editedByUser
        self.createdAt = createdAt
        self.generatedAt = generatedAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case versionId
        case versionNumber
        case routeKey
        case imagePath
        case heroImages
        case prompt
        case promptFields
        case status
        case requestId
        case sourceProofCacheKey
        case sourceSlotId
        case editedByUser
        case createdAt
        case generatedAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let now = DateFormats.now()
        versionId = try container.decodeIfPresent(String.self, forKey: .versionId) ?? "composite_version_\(UUID().uuidString.lowercased())"
        versionNumber = try container.decodeIfPresent(Int.self, forKey: .versionNumber) ?? 1
        routeKey = try container.decodeIfPresent(String.self, forKey: .routeKey) ?? ""
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath) ?? ""
        heroImages = try container.decodeIfPresent([AestheticCompositeHeroImage].self, forKey: .heroImages) ?? []
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        promptFields = try container.decodeIfPresent(AestheticCompositePromptFields.self, forKey: .promptFields)
            ?? AestheticCompositePromptFields()
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "draft"
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId) ?? ""
        sourceProofCacheKey = try container.decodeIfPresent(String.self, forKey: .sourceProofCacheKey) ?? ""
        sourceSlotId = try container.decodeIfPresent(String.self, forKey: .sourceSlotId) ?? ""
        editedByUser = try container.decodeIfPresent(Bool.self, forKey: .editedByUser) ?? false
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? now
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(versionId, forKey: .versionId)
        try container.encode(versionNumber, forKey: .versionNumber)
        try container.encode(routeKey, forKey: .routeKey)
        try container.encode(imagePath, forKey: .imagePath)
        try container.encode(heroImages, forKey: .heroImages)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(promptFields, forKey: .promptFields)
        try container.encode(status, forKey: .status)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(sourceProofCacheKey, forKey: .sourceProofCacheKey)
        try container.encode(sourceSlotId, forKey: .sourceSlotId)
        try container.encode(editedByUser, forKey: .editedByUser)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct AestheticDirectionComposite: Codable, Identifiable, Hashable, Sendable {
    var routeKey: String
    var id: String { routeKey }
    var cardId: String = ""
    var lane: String = ""
    var title: String = ""
    var coreTitle: String = ""
    var flavorTitles: [String] = []
    var promptDraft: String = ""
    var promptFieldsDraft: AestheticCompositePromptFields = AestheticCompositePromptFields()
    var currentVersionId: String = ""
    var versions: [AestheticDirectionCompositeVersion] = []
    var updatedAt: String = DateFormats.now()

    var currentVersion: AestheticDirectionCompositeVersion? {
        versions.first { $0.versionId == currentVersionId } ?? versions.sorted { $0.versionNumber > $1.versionNumber }.first
    }
}

struct AestheticDirectionCompositeDocument: Codable, Hashable, Sendable {
    var schemaVersion: String = "litscenes.aesthetic_direction_composites.v0.1"
    var projectId: String = ""
    var composites: [AestheticDirectionComposite] = []
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String = "") -> AestheticDirectionCompositeDocument {
        AestheticDirectionCompositeDocument(projectId: projectId)
    }

    func composite(routeKey: String) -> AestheticDirectionComposite? {
        composites.first { $0.routeKey == routeKey }
    }
}

struct AestheticProofSheetSlot: Codable, Identifiable, Hashable, Sendable {
    var slotId: String
    var id: String { slotId }
    var label: String
    var prompt: String
    var imagePath: String = ""
    var status: String = "idle"
    var errorMessage: String = ""
    var queuedAt: String?
    var startedAt: String?
    var generatedAt: String = ""
    var updatedAt: String?
    var requestId: String = ""
}

struct AestheticProofSheetDocument: Codable, Hashable, Sendable {
    var schemaVersion: String = "litscenes.aesthetic_proof_sheet.v0.1"
    var proofId: String
    var projectId: String
    var mode: String
    var cacheKey: String
    var directionIds: [String] = []
    var model: String = ""
    var size: String = ""
    var quality: String = ""
    var outputFormat: String = "jpeg"
    var outputCompression: Int = 70
    var promptTemplateVersion: String = "aesthetic_proof_sheet.v0.1"
    var slots: [AestheticProofSheetSlot] = []
    var status: String = "idle"
    var startedAt: String?
    var completedAt: String?
    var activeSlotId: String?
    var progressMessage: String?
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()
}

struct ProjectAestheticBriefDocument: Codable, Hashable {
    var schemaVersion: String = "litscenes.project_aesthetic_brief.v0.1"
    var projectId: String
    var selectedReferences: [AestheticBriefReference] = []
    var chosenDirection: ProjectAestheticDirectionRecipe?
    var operatorNotes: String = ""
    var styleContract: String = ""
    var axisValues: [String: Double] = [:]
    var locked: Bool = false
    var status: String = "draft"
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String = "") -> ProjectAestheticBriefDocument {
        ProjectAestheticBriefDocument(projectId: projectId)
    }

    var hasBrief: Bool {
        chosenDirection != nil
            || !selectedReferences.isEmpty
            || !operatorNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !styleContract.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isAccepted: Bool {
        locked || status == "accepted"
    }

    var readinessLabel: String {
        if isAccepted {
            return "Accepted"
        }
        if hasBrief {
            return "Brief draft"
        }
        return "Choose references"
    }

    func reference(for aestheticId: String) -> AestheticBriefReference? {
        selectedReferences.first { $0.aestheticId == aestheticId }
    }
}
