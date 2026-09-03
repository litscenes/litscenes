import Foundation

enum AestheticIndexConstants {
    static let packetSchemaVersion = "litscenes.aesthetic_index.v0.1"
    static let wheelSchemaVersion = "litscenes.aesthetic_wheel.v0.1"
    static let wheelResponseSchemaVersion = "litscenes.aesthetic_wheel_response.v0.1"
}

struct AestheticIndexPacket: Codable, Hashable, Sendable {
    var schemaVersion: String = AestheticIndexConstants.packetSchemaVersion
    var indexVersion: String = ""
    var generatedAt: String = ""
    var sourceSummary: String = ""
    var keyVocabulary: AestheticIndexKeyVocabulary = .empty()
    var items: [AestheticIndexItem] = []

    static func empty() -> AestheticIndexPacket {
        AestheticIndexPacket()
    }

    var isUsable: Bool {
        !items.isEmpty
    }
}

struct AestheticIndexKeyVocabulary: Codable, Hashable, Sendable {
    var values: [String] = []
    var moods: [String] = []
    var motifs: [String] = []
    var palettes: [String] = []
    var eras: [String] = []
    var energies: [String] = []
    var styles: [String] = []

    static func empty() -> AestheticIndexKeyVocabulary {
        AestheticIndexKeyVocabulary()
    }

    func compactPromptSummary(limit: Int = 18) -> String {
        var lines: [String] = []
        appendLine("values", values, limit: limit, to: &lines)
        appendLine("moods", moods, limit: limit, to: &lines)
        appendLine("motifs", motifs, limit: limit, to: &lines)
        appendLine("palettes", palettes, limit: limit, to: &lines)
        appendLine("eras", eras, limit: limit, to: &lines)
        appendLine("energies", energies, limit: limit, to: &lines)
        appendLine("styles", styles, limit: limit, to: &lines)
        return lines.joined(separator: "\n")
    }

    private func appendLine(_ label: String, _ values: [String], limit: Int, to lines: inout [String]) {
        let cleaned = uniqueCleanedValues(values, limit: limit)
        guard !cleaned.isEmpty else { return }
        lines.append("- \(label): \(cleaned.joined(separator: ", "))")
    }
}

struct AestheticIndexFacet: Codable, Hashable, Sendable {
    var facetType: String = ""
    var value: String = ""
    var polarity: String = "neutral"
    var weight: Double = 0.5
}

struct AestheticIndexRule: Codable, Hashable, Sendable {
    var area: String = ""
    var instruction: String = ""
    var strength: Double = 0.5
    var rank: Int = 0
}

struct AestheticIndexSwatch: Codable, Hashable, Sendable {
    var colorFamily: String = ""
    var hexColor: String = ""
}

struct AestheticIndexItem: Codable, Identifiable, Hashable, Sendable {
    var aestheticId: String
    var id: String { aestheticId }
    var profileId: String = ""
    var slug: String = ""
    var title: String = ""
    var summary: String = ""
    var description: String = ""
    var profileBasis: String = ""
    var textConfidence: Double = 0
    var visualConfidence: Double = 0
    var overallConfidence: Double = 0
    var isPrimary: Bool = true
    var isActive: Bool = true
    var profileStatus: String = ""
    var qualityFlags: [String] = []
    var sourceArtifactWarnings: [String] = []
    var previewImagePath: String = ""
    var facets: [AestheticIndexFacet] = []
    var rules: [AestheticIndexRule] = []
    var swatches: [AestheticIndexSwatch]? = nil
    var categories: [String] = []
    var aliases: [String] = []
    var paletteKeys: [String] = []
    var motifKeys: [String] = []
    var moodKeys: [String] = []
    var valueKeys: [String] = []
    var eraKeys: [String] = []
    var energyKeys: [String] = []
    var styleKeys: [String] = []
    var rankingKeys: [String] = []
    var signatureTerms: [String] = []
    var treatmentTerms: [String] = []
    var paletteTerms: [String] = []
    var semanticTags: [String] = []
    var broadTaxonomyTerms: [String] = []
    var noiseTerms: [String] = []

    var displaySummary: String {
        let cleanedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedSummary.isEmpty {
            return cleanedSummary
        }
        return description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var catalogItem: AestheticCatalogItem {
        AestheticCatalogItem(
            aestheticId: aestheticId,
            profileId: profileId,
            slug: slug,
            title: title,
            summary: summary,
            description: description,
            profileBasis: profileBasis,
            textConfidence: textConfidence,
            visualConfidence: visualConfidence,
            overallConfidence: overallConfidence,
            isPrimary: isPrimary,
            isActive: isActive,
            profileStatus: profileStatus,
            qualityFlags: qualityFlags,
            sourceArtifactWarnings: sourceArtifactWarnings,
            previewImageUrl: previewImagePath,
            facets: facets.map {
                AestheticCatalogFacet(facetType: $0.facetType, value: $0.value, polarity: $0.polarity, weight: $0.weight)
            },
            rules: rules.map {
                AestheticCatalogRule(area: $0.area, instruction: $0.instruction, strength: $0.strength, rank: $0.rank)
            }
        )
    }

    var allSearchTextValues: [String] {
        var values = [
            title,
            slug,
            summary,
            description,
            profileBasis,
        ]
        values.append(contentsOf: aliases)
        values.append(contentsOf: categories)
        values.append(contentsOf: paletteKeys)
        values.append(contentsOf: motifKeys)
        values.append(contentsOf: moodKeys)
        values.append(contentsOf: valueKeys)
        values.append(contentsOf: eraKeys)
        values.append(contentsOf: energyKeys)
        values.append(contentsOf: styleKeys)
        values.append(contentsOf: rankingKeys)
        values.append(contentsOf: signatureTerms)
        values.append(contentsOf: treatmentTerms)
        values.append(contentsOf: paletteTerms)
        values.append(contentsOf: semanticTags)
        values.append(contentsOf: broadTaxonomyTerms)
        values.append(contentsOf: facets.map(\.value))
        values.append(contentsOf: rules.map(\.instruction))
        return values
    }

    var defaultRankableTerms: [String] {
        signatureTerms + treatmentTerms + paletteTerms + semanticTags
    }

    var directionSignatureTerms: [String] {
        uniqueCleanedValues(signatureTerms, limit: 8)
    }

    var directionTreatmentTerms: [String] {
        uniqueCleanedValues(treatmentTerms, limit: 8)
    }

    var directionPaletteTerms: [String] {
        uniqueCleanedValues(paletteTerms.isEmpty ? paletteKeys : paletteTerms, limit: 6)
    }

    var qualityBadge: String {
        if defaultRankable {
            return "Ready"
        }
        if profileBasis.lowercased() == "weak" || overallConfidence < 0.45 {
            return "Low-confidence profile"
        }
        if previewImagePath.isEmpty {
            return "No preview"
        }
        return "Needs review"
    }

    var defaultRankable: Bool {
        guard isActive, isPrimary else { return false }
        guard profileBasis.lowercased() != "weak" else { return false }
        guard overallConfidence >= 0.45, textConfidence >= 0.50 else { return false }
        guard !previewImagePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !isJunkAestheticSummary(displaySummary) else { return false }
        return uniqueCleanedValues(signatureTerms + treatmentTerms, limit: 4).count >= 3
    }
}

struct AestheticWheelAxis: Codable, Hashable, Identifiable, Sendable {
    var axisId: String = ""
    var id: String { axisId }
    var label: String = ""
    var negativePole: String = ""
    var positivePole: String = ""
    var negativeTerms: [String] = []
    var positiveTerms: [String] = []
    var rationale: String = ""
    var defaultValue: Double = 0
    var weight: Double = 1

    var displayLabel: String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Axis" : label
    }

    static func fallback(
        axisId: String,
        label: String,
        negativePole: String,
        positivePole: String,
        negativeTerms: [String],
        positiveTerms: [String],
        defaultValue: Double = 0
    ) -> AestheticWheelAxis {
        AestheticWheelAxis(
            axisId: axisId,
            label: label,
            negativePole: negativePole,
            positivePole: positivePole,
            negativeTerms: negativeTerms,
            positiveTerms: positiveTerms,
            rationale: "Deterministic fallback axis.",
            defaultValue: defaultValue,
            weight: 1
        )
    }
}

struct AestheticWheelDocument: Codable, Hashable, Sendable {
    var schemaVersion: String = AestheticIndexConstants.wheelSchemaVersion
    var projectId: String = ""
    var goalFingerprint: String = ""
    var indexVersion: String = ""
    var generatedAt: String = ""
    var status: String = "empty"
    var model: String = ""
    var axes: [AestheticWheelAxis] = []
    var defaultPosition: [String: Double] = [:]
    var currentPosition: [String: Double] = [:]
    var summary: String = ""
    var errorMessage: String = ""

    static func empty(projectId: String = "") -> AestheticWheelDocument {
        AestheticWheelDocument(projectId: projectId)
    }

    static func fallback(projectId: String, goalFingerprint: String, indexVersion: String, reason: String = "") -> AestheticWheelDocument {
        let axes = fallbackAxes()
        let position = Dictionary(uniqueKeysWithValues: axes.map { ($0.axisId, $0.defaultValue) })
        return AestheticWheelDocument(
            projectId: projectId,
            goalFingerprint: goalFingerprint,
            indexVersion: indexVersion,
            generatedAt: DateFormats.now(),
            status: "fallback",
            model: "local-fallback",
            axes: axes,
            defaultPosition: position,
            currentPosition: position,
            summary: "Fallback axes keep the Aesthetic browser usable when LLM synthesis is unavailable.",
            errorMessage: reason
        )
    }

    static func fallbackAxes() -> [AestheticWheelAxis] {
        [
            .fallback(
                axisId: "reality",
                label: "Reality",
                negativePole: "Archive-native",
                positivePole: "Mythic",
                negativeTerms: ["documentary", "real", "archive", "literal", "observed", "natural"],
                positiveTerms: ["mythic", "surreal", "dream", "fantasy", "symbolic", "legend"]
            ),
            .fallback(
                axisId: "energy",
                label: "Energy",
                negativePole: "Quiet",
                positivePole: "Kinetic",
                negativeTerms: ["quiet", "restrained", "minimal", "calm", "subtle", "still"],
                positiveTerms: ["kinetic", "urgent", "punchy", "dynamic", "high energy", "intense"]
            ),
            .fallback(
                axisId: "texture",
                label: "Texture",
                negativePole: "Polished",
                positivePole: "Tactile",
                negativeTerms: ["clean", "polished", "glossy", "smooth", "minimal", "refined"],
                positiveTerms: ["grain", "raw", "tactile", "degraded", "analog", "textured"]
            ),
        ]
    }

    var usableAxes: [AestheticWheelAxis] {
        let cleaned = axes.filter { !$0.axisId.isEmpty }.prefix(3)
        if cleaned.count == 3 {
            return Array(cleaned)
        }
        return Self.fallbackAxes()
    }

    func positionValue(for axis: AestheticWheelAxis) -> Double {
        let value = currentPosition[axis.axisId] ?? defaultPosition[axis.axisId] ?? axis.defaultValue
        return min(max(value, -1), 1)
    }

    func withPosition(_ position: [String: Double]) -> AestheticWheelDocument {
        var updated = self
        updated.currentPosition = position.mapValues { min(max($0, -1), 1) }
        return updated
    }
}

struct AestheticWheelSynthesisResponse: Codable, Hashable {
    var schemaVersion: String = AestheticIndexConstants.wheelResponseSchemaVersion
    var summary: String = ""
    var axes: [AestheticWheelAxis] = []
}

struct AestheticWheelGenerationContext {
    var projectId: String
    var projectName: String
    var goalBriefSummary: String
    var aestheticIntentSummary: String
    var mediaSummary: String
    var indexVersion: String
    var indexKeySummary: String
    var generatedAt: String
}

struct OpenAIAestheticWheelResult {
    var response: AestheticWheelSynthesisResponse
    var responseId: String
    var model: String
    var usage: OpenAIUsage
    var rawText: String
}

enum AestheticIndexStore {
    static func loadBundledIndex() throws -> AestheticIndexPacket {
        let url = try packagedResourceURL(named: "aesthetic_index", extension: "json")
        return try JSONCoding.decoder.decode(AestheticIndexPacket.self, from: Data(contentsOf: url))
    }

    static func localImageURL(for path: String) -> URL? {
        let prefix = "aesthetic-index://"
        guard path.hasPrefix(prefix) else { return nil }
        let relativePath = String(path.dropFirst(prefix.count))
        guard !relativePath.isEmpty else { return nil }
        let candidates = localResourceCandidates(for: relativePath)
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func localResourceCandidates(for relativePath: String) -> [URL] {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(relativePath))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent(relativePath))
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(relativePath))
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(cwd.appendingPathComponent("Sources/LitScenes/Resources").appendingPathComponent(relativePath))
        // Development runs outside the package directory point here instead
        // of relying on any particular checkout layout.
        if let override = ProcessInfo.processInfo.environment["LITSCENES_AESTHETIC_INDEX_DIR"],
           !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override, isDirectory: true).appendingPathComponent(relativePath))
        }
        return candidates
    }
}

struct AestheticIndexRuntimeSnapshot: Sendable {
    var index: AestheticIndexPacket
    var directionCards: [AestheticDirectionCard]
    var candidates: [AestheticReferenceCandidate]
    var catalogItems: [AestheticCatalogItem]
    var status: String
}

actor AestheticIndexRuntime {
    static let shared = AestheticIndexRuntime()

    private var cachedIndex: AestheticIndexPacket?

    func loadIndex(force: Bool = false) throws -> AestheticIndexPacket {
        if !force, let cachedIndex {
            return cachedIndex
        }
        let startedAt = Date()
        let index = try AestheticIndexStore.loadBundledIndex()
        cachedIndex = index
        logPerformance("index_load", startedAt: startedAt, detail: "\(index.items.count) items · \(index.indexVersion)")
        return index
    }

    func snapshot(
        forceReload: Bool = false,
        wheel: AestheticWheelDocument,
        goalBrief: ProjectGoalBrief,
        mediaSummaries: [String],
        mediaObservations: [[String: CodableValue]],
        selectedReferences: [AestheticBriefReference],
        query: String,
        directionLimit: Int = 4,
        candidateLimit: Int = 8,
        catalogLimit: Int = 60
    ) throws -> AestheticIndexRuntimeSnapshot {
        let index = try loadIndex(force: forceReload)
        return snapshot(
            index: index,
            wheel: wheel,
            goalBrief: goalBrief,
            mediaSummaries: mediaSummaries,
            mediaObservations: mediaObservations,
            selectedReferences: selectedReferences,
            query: query,
            directionLimit: directionLimit,
            candidateLimit: candidateLimit,
            catalogLimit: catalogLimit
        )
    }

    func directionSnapshot(
        forceReload: Bool = false,
        wheel: AestheticWheelDocument,
        goalBrief: ProjectGoalBrief,
        mediaSummaries: [String],
        mediaObservations: [[String: CodableValue]],
        selectedReferences: [AestheticBriefReference],
        directionLimit: Int = 4
    ) throws -> AestheticIndexRuntimeSnapshot {
        let index = try loadIndex(force: forceReload)
        return snapshot(
            index: index,
            wheel: wheel,
            goalBrief: goalBrief,
            mediaSummaries: mediaSummaries,
            mediaObservations: mediaObservations,
            selectedReferences: selectedReferences,
            query: "",
            directionLimit: directionLimit,
            candidateLimit: 0,
            catalogLimit: 0
        )
    }

    func snapshot(
        index: AestheticIndexPacket,
        wheel: AestheticWheelDocument,
        goalBrief: ProjectGoalBrief,
        mediaSummaries: [String],
        mediaObservations: [[String: CodableValue]],
        selectedReferences: [AestheticBriefReference],
        query: String,
        directionLimit: Int = 4,
        candidateLimit: Int = 8,
        catalogLimit: Int = 60
    ) -> AestheticIndexRuntimeSnapshot {
        let startedAt = Date()
        let directionCards = directionLimit > 0 ? aestheticDirectionCards(
            index: index,
            wheel: wheel,
            goalBrief: goalBrief,
            mediaSummaries: mediaSummaries,
            mediaObservations: mediaObservations,
            selectedReferences: selectedReferences,
            query: "",
            limit: directionLimit
        ) : []
        let ranked = candidateLimit > 0 ? rankedAestheticOptions(
            index: index,
            wheel: wheel,
            goalBrief: goalBrief,
            mediaSummaries: mediaSummaries,
            mediaObservations: mediaObservations,
            selectedReferences: selectedReferences,
            query: query,
            limit: candidateLimit
        ) : []
        let catalogItems = catalogLimit > 0 ? LitScenes.catalogItems(from: index, query: query, limit: catalogLimit) : []
        logPerformance(
            "rank_snapshot",
            startedAt: startedAt,
            detail: "\(directionCards.count) cards · \(ranked.count) candidates · query=\(query.isEmpty ? "<empty>" : query)"
        )
        return AestheticIndexRuntimeSnapshot(
            index: index,
            directionCards: directionCards,
            candidates: ranked.map(\.candidate),
            catalogItems: catalogItems,
            status: "\(index.items.count) bundled aesthetic\(index.items.count == 1 ? "" : "s") · \(index.indexVersion)"
        )
    }

    private func logPerformance(_ name: String, startedAt: Date, detail: String) {
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        print("[aesthetic_performance] \(name) completed duration_ms=\(durationMs) \(detail)")
    }
}

struct RankedAestheticOption: Identifiable, Hashable, Sendable {
    var id: String { item.aestheticId }
    var item: AestheticIndexItem
    var score: Double
    var candidate: AestheticReferenceCandidate
}

struct RetrievedAestheticDirectionCandidate: Identifiable, Hashable, Sendable {
    var id: String { item.aestheticId }
    var item: AestheticIndexItem
    var score: Double
    var supportStatus: AestheticDirectionSupportStatus
    var goalMatches: [String]
    var archiveMatches: [String]
    var conflictTerms: [String]
    var supportNote: String

    var promptSummary: String {
        let goal = goalMatches.isEmpty ? "none" : goalMatches.joined(separator: ", ")
        let archive = archiveMatches.isEmpty ? "none" : archiveMatches.joined(separator: ", ")
        let conflicts = conflictTerms.isEmpty ? "none" : conflictTerms.joined(separator: ", ")
        let key = item.slug.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? safeIdentifier(item.title).lowercased()
            : item.slug
        return [
            "key=\(key)",
            "id=\(item.aestheticId)",
            "title=\(item.title)",
            "fit=\(String(format: "%.2f", score))",
            "support=\(supportStatus.rawValue)",
            "goal_matches=\(goal)",
            "archive_matches=\(archive)",
            "conflicts=\(conflicts)",
            "summary=\(shortAestheticSummary(item.displaySummary, limit: 180))",
        ].joined(separator: " | ")
    }
}

enum AestheticDirectionLane: String, CaseIterable, Identifiable, Sendable {
    case recommended
    case bolderStretch
    case commercial
    case wildcard

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recommended:
            return "Recommended Direction"
        case .bolderStretch:
            return "Bolder Stretch"
        case .commercial:
            return "Commercial / Creator-Friendly"
        case .wildcard:
            return "Wildcard"
        }
    }
}

struct AestheticDirectionCard: Identifiable, Hashable, Sendable {
    var cardId: String
    var id: String { cardId }
    var lane: AestheticDirectionLane
    var laneLabel: String = ""
    var selectionRank: Int = 0
    var directionLabel: String
    var coreItem: AestheticIndexItem
    var flavorItems: [AestheticIndexItem]
    var avoidTerms: [String]
    var intensity0To1: Double
    var ingredientControls: [AestheticIngredientControl]
    var signatureTerms: [String]
    var paletteTerms: [String]
    var paletteSwatches: [AestheticIndexSwatch]
    var previewImagePaths: [String]
    var visualSummary: String
    var treatmentNotes: [String]
    var bestAppliedTo: [String]
    var fitReason: String
    var supportStatus: AestheticDirectionSupportStatus = .archiveSupported
    var supportNote: String = ""
    var evidence: [String] = []
    var gaps: [String] = []
    var conflicts: [String] = []
    var scoreDebug: [String: Double]

    var displayLaneLabel: String {
        let trimmed = laneLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? lane.label : trimmed
    }

    var coreReference: AestheticBriefReference {
        AestheticBriefReference(
            aestheticId: coreItem.aestheticId,
            profileId: coreItem.profileId,
            slug: coreItem.slug,
            title: coreItem.title,
            summary: coreItem.displaySummary,
            previewImageUrl: coreItem.previewImagePath,
            role: .core,
            weight: 0.85
        )
    }

    var flavorReferences: [AestheticBriefReference] {
        flavorItems.enumerated().map { index, item in
            AestheticBriefReference(
                aestheticId: item.aestheticId,
                profileId: item.profileId,
                slug: item.slug,
                title: item.title,
                summary: item.displaySummary,
                previewImageUrl: item.previewImagePath,
                role: index == 0 ? .texture : .accent,
                weight: index == 0 ? 0.35 : 0.25
            )
        }
    }

    func recipe(projectId: String) -> ProjectAestheticDirectionRecipe {
        ProjectAestheticDirectionRecipe(
            title: directionLabel,
            lane: lane.rawValue,
            coreReference: coreReference,
            flavorReferences: flavorReferences,
            avoidTerms: avoidTerms,
            intensity0To1: intensity0To1,
            ingredientControls: ingredientControls,
            visualSummary: visualSummary,
            treatmentNotes: treatmentNotes,
            bestAppliedTo: bestAppliedTo,
            useFor: ["project-wide aesthetic direction", "image prompts", "scene treatments", "poster concepts"],
            paletteTerms: paletteTerms,
            signatureTerms: signatureTerms,
            previewImagePaths: previewImagePaths,
            source: "direction_card"
        )
    }
}

func rankedAestheticOptions(
    index: AestheticIndexPacket,
    wheel: AestheticWheelDocument,
    goalBrief: ProjectGoalBrief,
    mediaSummaries: [String],
    mediaObservations: [[String: CodableValue]],
    selectedReferences: [AestheticBriefReference],
    query: String,
    limit: Int = 24
) -> [RankedAestheticOption] {
    let selectedIds = Set(selectedReferences.map(\.aestheticId))
    let observed = aestheticObservedTokens(goalBrief: goalBrief, mediaSummaries: mediaSummaries, mediaObservations: mediaObservations)
    let queryTokens = tokenSet([query])
    let axes = wheel.usableAxes
    let ranked = index.items.compactMap { item -> RankedAestheticOption? in
        guard item.isActive, !selectedIds.contains(item.aestheticId) else { return nil }
        let itemTokens = tokenSet(item.allSearchTextValues)
        if !queryTokens.isEmpty && itemTokens.isDisjoint(with: queryTokens) {
            let text = item.allSearchTextValues.joined(separator: " ").lowercased()
            guard text.contains(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else { return nil }
        }

        let scoreBreakdown = aestheticScore(item: item, itemTokens: itemTokens, observed: observed, axes: axes, wheel: wheel)
        let score = scoreBreakdown["overall"] ?? 0
        guard score > 0 else { return nil }
        let chips = aestheticBecauseChips(item: item, scoreBreakdown: scoreBreakdown)
        let catalogItem = item.catalogItem
        let candidate = AestheticReferenceCandidate(
            aestheticId: item.aestheticId,
            profileId: item.profileId,
            slug: item.slug,
            title: item.title,
            plainEnglishEffect: String(item.displaySummary.prefix(180)),
            suggestedRole: suggestedRoleForAesthetic(score: score, item: item),
            score0To1: score,
            confidenceLabel: confidenceLabelForAesthetic(score: score, item: catalogItem),
            becauseChips: chips,
            whyItFits: candidateReason(chips),
            whatItChanges: whatItChanges(item: item),
            caveat: caveatForAesthetic(item: catalogItem),
            evidenceMediaIds: [],
            previewImageUrl: item.previewImagePath,
            axisValues: scoreBreakdown
        )
        return RankedAestheticOption(item: item, score: score, candidate: candidate)
    }
    .sorted {
        if $0.score == $1.score {
            return $0.item.title.localizedStandardCompare($1.item.title) == .orderedAscending
        }
        return $0.score > $1.score
    }
    return Array(ranked.prefix(max(1, limit)))
}

func aestheticDirectionCards(
    index: AestheticIndexPacket,
    wheel: AestheticWheelDocument,
    goalBrief: ProjectGoalBrief,
    mediaSummaries: [String],
    mediaObservations: [[String: CodableValue]],
    selectedReferences: [AestheticBriefReference],
    query: String = "",
    limit: Int = 4
) -> [AestheticDirectionCard] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let queryTokens = tokenSet([trimmedQuery])
    let observed = aestheticObservedTokens(goalBrief: goalBrief, mediaSummaries: mediaSummaries, mediaObservations: mediaObservations)
    let idf = AestheticTermIDF(items: index.items)
    let selectedIds = Set(selectedReferences.map(\.aestheticId))
    let pool = index.items.filter { item in
        guard item.defaultRankable else { return false }
        guard selectedIds.contains(item.aestheticId) || !isNearSelectedDuplicate(item, selectedReferences: selectedReferences) else { return false }
        guard !trimmedQuery.isEmpty else { return true }
        let searchTokens = tokenSet(item.allSearchTextValues)
        return !searchTokens.isDisjoint(with: queryTokens)
            || item.allSearchTextValues.joined(separator: " ").localizedCaseInsensitiveContains(trimmedQuery)
    }
    let scored = pool.map { item in
        DirectionScoredItem(item: item, scores: directionScores(item: item, observed: observed, wheel: wheel, idf: idf))
    }
    guard !scored.isEmpty else { return [] }

    var cards: [AestheticDirectionCard] = []
    var usedIds = Set<String>()
    var usedClusters = Set<String>()
    for lane in AestheticDirectionLane.allCases {
        guard cards.count < limit else { break }
        guard let picked = pickDirectionCandidate(for: lane, scored: scored, usedIds: usedIds, usedClusters: usedClusters)
            ?? pickDirectionCandidate(for: lane, scored: scored, usedIds: usedIds, usedClusters: []) else {
            continue
        }
        let flavorItems = flavorItems(for: picked, lane: lane, scored: scored, selectedReferences: selectedReferences)
        let card = directionCard(
            lane: lane,
            picked: picked,
            flavorItems: flavorItems,
            goalBrief: goalBrief
        )
        cards.append(card)
        usedIds.insert(picked.item.aestheticId)
        usedIds.formUnion(flavorItems.map(\.aestheticId))
        usedClusters.insert(directionClusterKey(for: picked.item))
    }
    return cards
}

func aestheticDirectionCards(
    from selection: AestheticDirectionSelectionDocument,
    index: AestheticIndexPacket,
    goalBrief: ProjectGoalBrief,
    limit: Int = 3
) -> [AestheticDirectionCard] {
    let itemsById = Dictionary(uniqueKeysWithValues: index.items.map { ($0.aestheticId, $0) })
    return selection.directions
        .sorted { lhs, rhs in
            if lhs.rank == rhs.rank {
                return lhs.routeKey.localizedStandardCompare(rhs.routeKey) == .orderedAscending
            }
            return lhs.rank < rhs.rank
        }
        .compactMap { directionCard(from: $0, itemsById: itemsById, goalBrief: goalBrief) }
        .prefix(max(1, limit))
        .map { $0 }
}

func migratedDirectionRecipe(
    from references: [AestheticBriefReference],
    projectId: String,
    avoidTerms: [String]
) -> ProjectAestheticDirectionRecipe? {
    guard let core = references.first(where: { $0.role == .core }) ?? references.first else { return nil }
    let flavors = references
        .filter { $0.aestheticId != core.aestheticId }
        .sorted { lhs, rhs in lhs.weight > rhs.weight }
    let controls = references.prefix(5).map { reference in
        AestheticIngredientControl(
            key: normalizedControlKey(reference.title),
            label: ingredientLabel(reference.title),
            value0To1: min(max(reference.weight, 0), 1)
        )
    }
    return ProjectAestheticDirectionRecipe(
        title: "Current draft from selected references",
        lane: "current_draft",
        coreReference: core,
        flavorReferences: flavors,
        avoidTerms: avoidTerms,
        intensity0To1: max(0.45, references.map(\.weight).max() ?? 0.65),
        ingredientControls: controls,
        visualSummary: "Keeps the currently selected references as the working visual treatment.",
        treatmentNotes: references.map(\.title),
        bestAppliedTo: ["direction alignment", "style handoff", "prompt grounding"],
        useFor: ["project-wide aesthetic direction", "image prompts", "scene treatments"],
        paletteTerms: [],
        signatureTerms: references.map(\.title),
        previewImagePaths: references.map(\.previewImageUrl).filter { !$0.isEmpty },
        source: "selected_reference_migration"
    )
}

func compareDirectionsProofSheet(
    projectId: String,
    cards: [AestheticDirectionCard],
    goalBrief: ProjectGoalBrief,
    mediaSummaries: [String],
    indexVersion: String,
    goalFingerprint: String
) -> AestheticProofSheetDocument {
    let capsule = projectCapsule(goalBrief: goalBrief, mediaSummaries: mediaSummaries)
    let model = "gpt-image-2"
    let size = "1024x1024"
    let quality = "medium"
    let format = "jpeg"
    let compression = 70
    let applications = [
        ("representative_frame", "Representative frame", "one representative comparison frame"),
        ("poster_key_image", "Poster / key image", "one social, poster, or title-card-ready key image"),
        ("archive_evidence_frame", "Archive / evidence frame", "one found-footage evidence artifact, screenshot, or recovered document frame"),
    ]
    let batchCards = Array(cards.prefix(3))
    let slots = applications.flatMap { application in
        batchCards.map { card in
            let fields = AestheticCompositePromptFields(
                subjectCapsule: capsule,
                directionLabel: card.directionLabel,
                core: card.coreItem.title,
                flavor: card.flavorItems.map(\.title).joined(separator: ", "),
                visualSummary: card.visualSummary,
                treatmentNotes: card.treatmentNotes.joined(separator: ", "),
                palette: card.paletteTerms.joined(separator: ", "),
                frameApplication: application.2,
                avoidTerms: card.avoidTerms.joined(separator: ", ")
            )
            return AestheticProofSheetSlot(
                slotId: "\(aestheticDirectionCompareSlotId(card))_\(application.0)",
                label: "\(card.displayLaneLabel) · \(application.1)",
                prompt: aestheticCompositePrompt(from: fields)
            )
        }
    }
    if slots.isEmpty {
        return AestheticProofSheetDocument(
            proofId: "proof_empty_\(shortHash(projectId, length: 12))",
            projectId: projectId,
            mode: "compare_directions",
            cacheKey: "empty_\(shortHash(projectId, length: 12))",
            directionIds: [],
            model: model,
            size: size,
            quality: quality,
            outputFormat: format,
            outputCompression: compression,
            slots: [],
            status: "draft"
        )
    }
    let promptHash = shortHash(slots.map(\.prompt).joined(separator: "\n---\n"), length: 20)
    let cacheKey = proofCacheKey(
        projectId: projectId,
        goalFingerprint: goalFingerprint,
        indexVersion: indexVersion,
        directionIds: cards.map(\.cardId),
        recipeVersion: "compare",
        promptHash: promptHash,
        model: model,
        size: size,
        quality: quality,
        format: format,
        compression: compression
    )
    return AestheticProofSheetDocument(
        proofId: "proof_\(cacheKey)",
        projectId: projectId,
        mode: "compare_directions",
        cacheKey: cacheKey,
        directionIds: cards.map(\.cardId),
        model: model,
        size: size,
        quality: quality,
        outputFormat: format,
        outputCompression: compression,
        slots: slots,
        status: "queued"
    )
}

func aestheticDirectionRouteKey(_ card: AestheticDirectionCard) -> String {
    if card.cardId.hasPrefix("selection_") {
        return card.cardId
    }
    return shortHash([
        card.lane.rawValue,
        card.coreItem.aestheticId,
        card.flavorItems.map(\.aestheticId).sorted().joined(separator: ","),
    ].joined(separator: "|"), length: 20)
}

func aestheticDirectionCompareSlotId(_ card: AestheticDirectionCard) -> String {
    "compare_\(safeIdentifier(card.cardId))"
}

func aestheticCompositePromptFields(
    card: AestheticDirectionCard,
    goalBrief: ProjectGoalBrief,
    mediaSummaries: [String]
) -> AestheticCompositePromptFields {
    AestheticCompositePromptFields(
        subjectCapsule: projectCapsule(goalBrief: goalBrief, mediaSummaries: mediaSummaries),
        directionLabel: card.directionLabel,
        core: card.coreItem.title,
        flavor: card.flavorItems.map(\.title).joined(separator: ", "),
        visualSummary: card.visualSummary,
        treatmentNotes: card.treatmentNotes.joined(separator: ", "),
        palette: card.paletteTerms.joined(separator: ", "),
        frameApplication: "one representative comparison frame",
        avoidTerms: card.avoidTerms.joined(separator: ", ")
    )
}

func aestheticCompositePrompt(from fields: AestheticCompositePromptFields) -> String {
    """
    Create one square visual proof for this LitScenes aesthetic direction.
    Use the same project subject capsule for every direction so the comparison is fair.
    Do not include readable paragraphs of text. If typography appears, keep it graphic and minimal.

    Project subject capsule:
    \(fields.subjectCapsule)

    Direction:
    - label: \(fields.directionLabel)
    - core: \(fields.core)
    - flavor: \(fields.flavor)
    - visual summary: \(fields.visualSummary)
    - treatment notes: \(fields.treatmentNotes)
    - palette: \(fields.palette)
    - avoid: \(fields.avoidTerms)

    Frame application: \(fields.frameApplication).
    """
}

func selectedDirectionProofSheet(
    projectId: String,
    recipe: ProjectAestheticDirectionRecipe,
    goalBrief: ProjectGoalBrief,
    mediaSummaries: [String],
    indexVersion: String,
    goalFingerprint: String
) -> AestheticProofSheetDocument {
    let capsule = projectCapsule(goalBrief: goalBrief, mediaSummaries: mediaSummaries)
    let model = "gpt-image-2"
    let size = "1024x1024"
    let quality = "medium"
    let format = "jpeg"
    let compression = 70
    let applications = [
        ("film_still", "Film still", "a representative cinematic frame"),
        ("poster_thumbnail", "Poster / thumbnail", "a social or poster-ready key image"),
        ("archive_evidence", "Archive / evidence frame", "a found-footage evidence artifact, screenshot, or recovered document frame"),
        ("creator_commercial", "Creator / commercial frame", "a creator-friendly campaign, product, service, or launch asset interpretation"),
    ]
    let slots = applications.map { application in
        let prompt = """
        Create one square visual proof for the selected LitScenes project aesthetic.
        Do not include readable paragraphs of text. If typography appears, keep it graphic and minimal.

        Project subject capsule:
        \(capsule)

        Chosen direction:
        - label: \(recipe.title)
        - core: \(recipe.coreReference.title)
        - flavor: \(recipe.flavorReferences.map(\.title).joined(separator: ", "))
        - intensity: \(Int((recipe.intensity0To1 * 100).rounded()))%
        - ingredients: \(recipe.ingredientControls.map { "\($0.label) \(Int(($0.value0To1 * 100).rounded()))%" }.joined(separator: ", "))
        - avoid: \(recipe.avoidTerms.joined(separator: ", "))
        - visual summary: \(recipe.visualSummary)
        - treatment notes: \(recipe.treatmentNotes.joined(separator: ", "))

        Frame application: \(application.2).
        """
        return AestheticProofSheetSlot(slotId: application.0, label: application.1, prompt: prompt)
    }
    let promptHash = shortHash(slots.map(\.prompt).joined(separator: "\n---\n"), length: 20)
    let cacheKey = proofCacheKey(
        projectId: projectId,
        goalFingerprint: goalFingerprint,
        indexVersion: indexVersion,
        directionIds: [recipe.recipeId],
        recipeVersion: recipe.recipeVersion,
        promptHash: promptHash,
        model: model,
        size: size,
        quality: quality,
        format: format,
        compression: compression
    )
    return AestheticProofSheetDocument(
        proofId: "proof_\(cacheKey)",
        projectId: projectId,
        mode: "selected_direction",
        cacheKey: cacheKey,
        directionIds: [recipe.recipeId],
        model: model,
        size: size,
        quality: quality,
        outputFormat: format,
        outputCompression: compression,
        slots: slots,
        status: "queued"
    )
}

private func proofCacheKey(
    projectId: String,
    goalFingerprint: String,
    indexVersion: String,
    directionIds: [String],
    recipeVersion: String,
    promptHash: String,
    model: String,
    size: String,
    quality: String,
    format: String,
    compression: Int
) -> String {
    shortHash([
        "project=\(projectId)",
        "goal=\(goalFingerprint)",
        "index=\(indexVersion)",
        "directions=\(directionIds.sorted().joined(separator: ","))",
        "recipe=\(recipeVersion)",
        "template=aesthetic_proof_sheet.v0.1",
        "prompt=\(promptHash)",
        "model=\(model)",
        "size=\(size)",
        "quality=\(quality)",
        "format=\(format)",
        "compression=\(compression)",
    ].joined(separator: "|"), length: 24)
}

private func projectCapsule(goalBrief: ProjectGoalBrief, mediaSummaries: [String]) -> String {
    let intent = goalBrief.aestheticIntent.normalized()
    let pieces = [
        goalBrief.storyPromise,
        goalBrief.goal,
        "motifs: \(intent.motifHints.prefix(6).joined(separator: ", "))",
        "mood: \((intent.visualMood + intent.emotionalTargets).prefix(6).joined(separator: ", "))",
        "palette: \(intent.paletteHints.prefix(6).joined(separator: ", "))",
        "archive evidence: \(mediaSummaries.prefix(4).joined(separator: " / "))",
    ]
    return pieces
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
}

func safeIdentifier(_ value: String) -> String {
    let cleaned = value.map { character in
        character.isLetter || character.isNumber ? character : "_"
    }
    return String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
}

func catalogItems(
    from index: AestheticIndexPacket,
    query: String,
    limit: Int
) -> [AestheticCatalogItem] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let queryTokens = tokenSet([trimmed])
    let filtered = index.items.filter { item in
        guard item.isActive else { return false }
        guard !trimmed.isEmpty else { return true }
        let tokens = tokenSet(item.allSearchTextValues)
        if !tokens.isDisjoint(with: queryTokens) {
            return true
        }
        return item.allSearchTextValues.joined(separator: " ").lowercased().contains(trimmed.lowercased())
    }
    .sorted { lhs, rhs in
        if lhs.overallConfidence == rhs.overallConfidence {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.overallConfidence > rhs.overallConfidence
    }
    return filtered.prefix(max(1, limit)).map(\.catalogItem)
}

func aestheticGoalFingerprint(
    brief: ProjectGoalBrief,
    mediaSummaries: [String],
    mediaObservations: [[String: CodableValue]],
    indexVersion: String
) -> String {
    let briefText: String
    if let data = try? JSONCoding.encoder.encode(brief),
       let encoded = String(data: data, encoding: .utf8) {
        briefText = encoded
    } else {
        briefText = brief.goal
    }
    let packet = [
        "index=\(indexVersion)",
        "brief=\(briefText)",
        "media=\(mediaSummaries.joined(separator: "|"))",
        "observations=\(mediaObservations.description)",
    ].joined(separator: "\n")
    return shortHash(packet, length: 20)
}

func aestheticBriefFingerprint(_ brief: ProjectGoalBrief) -> String {
    if let data = try? JSONCoding.encoder.encode(brief),
       let encoded = String(data: data, encoding: .utf8) {
        return shortHash(encoded, length: 20)
    }
    return shortHash(brief.goal, length: 20)
}

func aestheticAnalysisFingerprint(
    contentItems: [MediaItemRecord],
    observationsById: [String: ImageObservationResult],
    requiredCount: Int = 10
) -> String {
    let lines = contentItems.compactMap { item -> String? in
        guard let observation = observationsById[item.mediaId] else { return nil }
        return [
            item.mediaId,
            item.path,
            item.modifiedAt,
            observation.visionInputSha256,
            observation.schemaVersion,
            observation.sourceImageSha256,
        ].joined(separator: "|")
    }
    .sorted()
    let prefix = Array(lines.prefix(max(requiredCount, lines.count)))
    return shortHash(prefix.joined(separator: "\n"), length: 20)
}

func retrieveAestheticDirectionCandidates(
    index: AestheticIndexPacket,
    evidenceProfile: ProjectAestheticEvidenceProfile,
    limit: Int = 40
) -> [RetrievedAestheticDirectionCandidate] {
    let goalSignalSets: [Set<String>] = [
        tokenSet(evidenceProfile.goalVisualCues),
        tokenSet(evidenceProfile.goalTreatmentCues),
        tokenSet(evidenceProfile.goalMoodTerms),
        tokenSet(evidenceProfile.goalMotifTerms),
        tokenSet(evidenceProfile.goalPaletteTerms),
        tokenSet(evidenceProfile.goalPlaceCues),
        tokenSet(evidenceProfile.goalEraCues),
        tokenSet(evidenceProfile.goalEnergyCues),
    ]
    let archiveSignalSets: [Set<String>] = [
        tokenSet(evidenceProfile.archiveSubjects),
        tokenSet(evidenceProfile.archiveSettings),
        tokenSet(evidenceProfile.archiveMaterials),
        tokenSet(evidenceProfile.archiveMoodTerms),
        tokenSet(evidenceProfile.archiveMotifTerms),
        tokenSet(evidenceProfile.archivePaletteTerms),
        tokenSet(evidenceProfile.archivePlaceCues),
        tokenSet(evidenceProfile.archiveEraCues),
        tokenSet(evidenceProfile.archiveEnergyCues),
        tokenSet(evidenceProfile.archiveCompositionCues),
    ]
    let goalTerms = goalSignalSets.reduce(into: Set<String>()) { $0.formUnion($1) }
    let storyGoalTerms = tokenSet(evidenceProfile.goalWorldCues).subtracting(goalTerms)
    let archiveTerms = archiveSignalSets.reduce(into: Set<String>()) { $0.formUnion($1) }
    let avoidTerms = tokenSet(evidenceProfile.goalAvoidTerms + evidenceProfile.archiveNegativeConstraints)
    let contradictionTerms = tokenSet(evidenceProfile.contradictions)

    let scored = index.items.compactMap { item -> RetrievedAestheticDirectionCandidate? in
        guard item.defaultRankable else { return nil }
        let itemTerms = retrievalItemTerms(item)
        let archiveMatchTerms = overlapTerms(observed: archiveTerms, candidate: itemTerms, limit: 8)
        let goalMatchTerms = overlapTerms(observed: goalTerms, candidate: itemTerms, limit: 8)
        let storyGoalMatchTerms = overlapTerms(observed: storyGoalTerms, candidate: itemTerms, limit: 4)
        let avoidMatchTerms = overlapTerms(observed: avoidTerms.union(contradictionTerms), candidate: itemTerms, limit: 6)
        let goalScore = ratioScore(goalTerms, itemTerms)
        let storyGoalScore = ratioScore(storyGoalTerms, itemTerms)
        let archiveScore = ratioScore(archiveTerms, itemTerms)
        let paletteScore = ratioScore(
            tokenSet(evidenceProfile.goalPaletteTerms + evidenceProfile.archivePaletteTerms),
            tokenSet(item.paletteTerms + item.paletteKeys)
        )
        let motifScore = ratioScore(
            tokenSet(evidenceProfile.goalMotifTerms + evidenceProfile.archiveMotifTerms),
            tokenSet(item.motifKeys + item.signatureTerms)
        )
        let avoidPenalty = ratioScore(avoidTerms.union(contradictionTerms), itemTerms)
        var score = (0.40 * goalScore)
            + (0.28 * archiveScore)
            + (0.10 * paletteScore)
            + (0.08 * motifScore)
            + (0.04 * storyGoalScore)
            + (0.10 * min(max((item.overallConfidence * 0.65) + (item.textConfidence * 0.35), 0), 1))
            - (0.34 * avoidPenalty)
        if !item.sourceArtifactWarnings.isEmpty || !item.qualityFlags.isEmpty {
            score *= 0.9
        }
        score = min(max(score, 0), 1)
        guard score > 0.08 else { return nil }

        let supportStatus: AestheticDirectionSupportStatus
        if avoidPenalty >= 0.16 || !avoidMatchTerms.isEmpty {
            supportStatus = .conflictRisk
        } else if !archiveMatchTerms.isEmpty && archiveScore >= max(0.14, goalScore * 0.55) {
            supportStatus = .archiveSupported
        } else if goalScore >= 0.16 || (!storyGoalMatchTerms.isEmpty && storyGoalScore >= 0.12) {
            supportStatus = .goalLedStretch
        } else {
            supportStatus = .exploratory
        }
        return RetrievedAestheticDirectionCandidate(
            item: item,
            score: roundedScore(score),
            supportStatus: supportStatus,
            goalMatches: goalMatchTerms,
            archiveMatches: archiveMatchTerms,
            conflictTerms: avoidMatchTerms,
            supportNote: supportNote(
                status: supportStatus,
                goalMatches: goalMatchTerms,
                archiveMatches: archiveMatchTerms,
                conflicts: avoidMatchTerms
            )
        )
    }
    .sorted {
        if $0.score == $1.score {
            return $0.item.title.localizedStandardCompare($1.item.title) == .orderedAscending
        }
        return $0.score > $1.score
    }
    return Array(scored.prefix(max(1, limit)))
}

func selectionDirectionCards(
    from selection: AestheticDirectionSelectionDocument,
    index: AestheticIndexPacket,
    goalBrief: ProjectGoalBrief
) -> [AestheticDirectionCard] {
    guard selection.isUsable else { return [] }
    let itemsById = Dictionary(uniqueKeysWithValues: index.items.map { ($0.aestheticId, $0) })
    return selection.directions.compactMap { direction in
        directionCard(from: direction, itemsById: itemsById, goalBrief: goalBrief)
    }
}

private func aestheticObservedTokens(
    goalBrief: ProjectGoalBrief,
    mediaSummaries: [String],
    mediaObservations: [[String: CodableValue]]
) -> [String: Set<String>] {
    let intent = goalBrief.aestheticIntent.normalized()
    var mediaValues = mediaSummaries
    mediaValues.append(contentsOf: mediaObservations.flatMap(flattenCodableValues))
    var goalValues = [
        goalBrief.goal,
        goalBrief.audience,
        goalBrief.desiredAction,
        goalBrief.distributionContext,
        goalBrief.storyPromise,
    ]
    goalValues.append(contentsOf: goalBrief.successCriteria)
    goalValues.append(contentsOf: goalBrief.constraints)
    goalValues.append(contentsOf: intent.emotionalTargets)
    goalValues.append(contentsOf: intent.narrativeValues)
    goalValues.append(contentsOf: intent.visualMood)
    goalValues.append(contentsOf: intent.energy)
    var valueValues = intent.emotionalTargets
    valueValues.append(contentsOf: intent.narrativeValues)
    valueValues.append(contentsOf: intent.energy)
    var moodValues = intent.visualMood
    moodValues.append(contentsOf: intent.emotionalTargets)
    moodValues.append(contentsOf: intent.energy)
    var motifValues = intent.motifHints
    motifValues.append(contentsOf: mediaValues)
    return [
        "goal": tokenSet(goalValues),
        "values": tokenSet(valueValues),
        "mood": tokenSet(moodValues),
        "palette": tokenSet(intent.paletteHints),
        "motif": tokenSet(motifValues),
        "era": tokenSet(intent.eraHints),
        "avoid": tokenSet(intent.avoid),
        "media": tokenSet(mediaValues),
    ]
}

private struct DirectionScoredItem {
    var item: AestheticIndexItem
    var scores: [String: Double]
}

private struct AestheticTermIDF {
    var total: Double
    var documentFrequency: [String: Int]

    init(items: [AestheticIndexItem]) {
        let rankable = items.filter(\.defaultRankable)
        total = Double(max(rankable.count, 1))
        var counts: [String: Int] = [:]
        for item in rankable {
            for token in tokenSet(item.defaultRankableTerms) {
                counts[token, default: 0] += 1
            }
        }
        documentFrequency = counts
    }

    func weight(for token: String) -> Double {
        let count = Double(documentFrequency[token] ?? 0)
        return min(3.2, max(0.2, log((1 + total) / (1 + count)) + 1))
    }
}

private func directionScores(
    item: AestheticIndexItem,
    observed: [String: Set<String>],
    wheel: AestheticWheelDocument,
    idf: AestheticTermIDF
) -> [String: Double] {
    let signatureScore = weightedTermScore(
        observed: (observed["goal"] ?? []).union(observed["values"] ?? []).union(observed["mood"] ?? []),
        candidateTerms: item.signatureTerms,
        idf: idf
    )
    let treatmentScore = weightedTermScore(
        observed: (observed["media"] ?? []).union(observed["motif"] ?? []),
        candidateTerms: item.treatmentTerms,
        idf: idf
    )
    let semanticScore = weightedTermScore(
        observed: (observed["goal"] ?? []).union(observed["mood"] ?? []),
        candidateTerms: item.semanticTags,
        idf: idf
    )
    let paletteScore = weightedTermScore(observed: observed["palette"] ?? [], candidateTerms: item.paletteTerms, idf: idf)
    let avoidPenalty = weightedTermScore(
        observed: observed["avoid"] ?? [],
        candidateTerms: item.signatureTerms + item.treatmentTerms + item.semanticTags + item.paletteTerms,
        idf: idf
    )
    let rankTokens = tokenSet(item.defaultRankableTerms)
    let wheelScore = axisAlignmentScore(itemTokens: rankTokens, axes: wheel.usableAxes, wheel: wheel)
    let qualityScore = min(max((item.overallConfidence * 0.65) + (item.textConfidence * 0.35), 0), 1)
    let commercialScore = commercialSignalScore(item: item, idf: idf)
    let fitScore = min(1, (0.36 * signatureScore) + (0.24 * treatmentScore) + (0.16 * semanticScore) + (0.10 * paletteScore) + (0.14 * wheelScore))
    let transformationScore = min(1, (0.48 * treatmentScore) + (0.24 * commercialScore) + (0.18 * signatureScore) + (0.10 * wheelScore))
    let noveltyScore = max(0, min(1, 1 - ((signatureScore + semanticScore) / 2)))
    let recommended = min(1, (0.58 * fitScore) + (0.26 * qualityScore) + (0.16 * transformationScore) - (0.18 * avoidPenalty))
    let bolder = min(1, (0.38 * transformationScore) + (0.28 * noveltyScore) + (0.20 * fitScore) + (0.14 * qualityScore) - (0.14 * avoidPenalty))
    let commercial = min(1, (0.46 * commercialScore) + (0.24 * treatmentScore) + (0.18 * fitScore) + (0.12 * qualityScore) - (0.10 * avoidPenalty))
    let wildcard = min(1, (0.42 * noveltyScore) + (0.24 * transformationScore) + (0.20 * qualityScore) + (0.14 * max(signatureScore, semanticScore)) - (0.08 * avoidPenalty))
    return [
        "recommended": roundedScore(recommended),
        "bolder": roundedScore(bolder),
        "commercial": roundedScore(commercial),
        "wildcard": roundedScore(wildcard),
        "fit": roundedScore(fitScore),
        "signature": roundedScore(signatureScore),
        "treatment": roundedScore(treatmentScore),
        "semantic": roundedScore(semanticScore),
        "palette": roundedScore(paletteScore),
        "wheel": roundedScore(wheelScore),
        "quality": roundedScore(qualityScore),
        "novelty": roundedScore(noveltyScore),
        "avoid": roundedScore(avoidPenalty),
    ]
}

private func weightedTermScore(observed: Set<String>, candidateTerms: [String], idf: AestheticTermIDF) -> Double {
    guard !observed.isEmpty else { return 0 }
    let candidateTokens = tokenSet(candidateTerms)
    guard !candidateTokens.isEmpty else { return 0 }
    let overlap = observed.intersection(candidateTokens)
    guard !overlap.isEmpty else { return 0 }
    let numerator = overlap.reduce(0.0) { $0 + idf.weight(for: $1) }
    let observedWeights = observed.map { idf.weight(for: $0) }.sorted(by: >)
    let denominator = max(3.0, observedWeights.prefix(14).reduce(0.0, +))
    let phraseBoost = phraseMatchBoost(observed: observed, candidateTerms: candidateTerms, idf: idf)
    return min(1, (numerator + phraseBoost) / denominator)
}

private func phraseMatchBoost(observed: Set<String>, candidateTerms: [String], idf: AestheticTermIDF) -> Double {
    var boost = 0.0
    for term in candidateTerms {
        let termTokens = tokenSet([term])
        guard termTokens.count >= 2, termTokens.isSubset(of: observed) else { continue }
        boost += min(1.2, termTokens.reduce(0.0) { $0 + idf.weight(for: $1) } * 0.28)
    }
    return boost
}

private func commercialSignalScore(item: AestheticIndexItem, idf: AestheticTermIDF) -> Double {
    let terms = item.treatmentTerms + item.semanticTags + item.signatureTerms
    let tokens = tokenSet(terms)
    let overlap = tokens.intersection(commercialSignalTokens)
    guard !overlap.isEmpty else { return 0 }
    return min(1, overlap.reduce(0.0) { $0 + idf.weight(for: $1) } / 8.0)
}

private func pickDirectionCandidate(
    for lane: AestheticDirectionLane,
    scored: [DirectionScoredItem],
    usedIds: Set<String>,
    usedClusters: Set<String>
) -> DirectionScoredItem? {
    let key = scoreKey(for: lane)
    let eligible = scored
        .filter { !usedIds.contains($0.item.aestheticId) }
        .filter { usedClusters.isEmpty || !usedClusters.contains(directionClusterKey(for: $0.item)) }
        .filter { ($0.scores[key] ?? 0) > 0.08 }
        .sorted {
            let lhs = $0.scores[key] ?? 0
            let rhs = $1.scores[key] ?? 0
            if lhs == rhs {
                return $0.item.title.localizedStandardCompare($1.item.title) == .orderedAscending
            }
            return lhs > rhs
        }
    return eligible.first
}

private func scoreKey(for lane: AestheticDirectionLane) -> String {
    switch lane {
    case .recommended:
        return "recommended"
    case .bolderStretch:
        return "bolder"
    case .commercial:
        return "commercial"
    case .wildcard:
        return "wildcard"
    }
}

private func flavorItems(
    for picked: DirectionScoredItem,
    lane: AestheticDirectionLane,
    scored: [DirectionScoredItem],
    selectedReferences: [AestheticBriefReference]
) -> [AestheticIndexItem] {
    let selectedIds = Set(selectedReferences.map(\.aestheticId))
    let coreTokens = tokenSet(picked.item.signatureTerms + picked.item.semanticTags)
    let scoredFlavors = scored.compactMap { candidate -> (Double, AestheticIndexItem)? in
        guard candidate.item.aestheticId != picked.item.aestheticId else { return nil }
        guard selectedIds.contains(candidate.item.aestheticId) || !sameAestheticFamily(candidate.item, picked.item) else { return nil }
        let candidateTokens = tokenSet(candidate.item.signatureTerms + candidate.item.semanticTags)
        let overlap = ratioScore(coreTokens, candidateTokens)
        let treatment = candidate.scores["treatment"] ?? 0
        let commercial = candidate.scores["commercial"] ?? 0
        let fit = candidate.scores["fit"] ?? 0
        let selectedBoost = selectedIds.contains(candidate.item.aestheticId) ? 0.16 : 0
        let score = (0.46 * treatment) + (0.24 * fit) + (0.14 * commercial) + selectedBoost - (0.18 * overlap)
        return score > 0.08 ? (score, candidate.item) : nil
    }
    .sorted {
        if $0.0 == $1.0 {
            return $0.1.title.localizedStandardCompare($1.1.title) == .orderedAscending
        }
        return $0.0 > $1.0
    }
    return Array(scoredFlavors.prefix(lane == .commercial ? 2 : 1).map(\.1))
}

private func directionCard(
    lane: AestheticDirectionLane,
    picked: DirectionScoredItem,
    flavorItems: [AestheticIndexItem],
    goalBrief: ProjectGoalBrief
) -> AestheticDirectionCard {
    let core = picked.item
    let flavorNames = flavorItems.map(\.title)
    let signatureTerms = uniqueCleanedValues(core.directionSignatureTerms + flavorItems.flatMap(\.directionSignatureTerms), limit: 5)
    let treatmentTerms = uniqueCleanedValues(core.directionTreatmentTerms + flavorItems.flatMap(\.directionTreatmentTerms), limit: 6)
    let paletteTerms = uniqueCleanedValues(core.directionPaletteTerms + flavorItems.flatMap(\.directionPaletteTerms), limit: 5)
    let paletteSwatches = combinedPaletteSwatches(core: core, flavorItems: flavorItems)
    let avoid = uniqueCleanedValues(goalBrief.aestheticIntent.normalized().avoid, limit: 4)
    let directionLabel = visualDirectionLabel(core: core, flavorItems: flavorItems)
    let previews = uniqueCleanedValues([core.previewImagePath] + flavorItems.map(\.previewImagePath), limit: 4)
    return AestheticDirectionCard(
        cardId: "\(lane.rawValue)_\(core.aestheticId)",
        lane: lane,
        directionLabel: directionLabel,
        coreItem: core,
        flavorItems: flavorItems,
        avoidTerms: avoid,
        intensity0To1: directionIntensity(lane: lane, scores: picked.scores),
        ingredientControls: ingredientControls(core: core, flavorItems: flavorItems, lane: lane),
        signatureTerms: signatureTerms,
        paletteTerms: paletteTerms,
        paletteSwatches: paletteSwatches,
        previewImagePaths: previews,
        visualSummary: directionSummary(lane: lane, core: core, signatureTerms: signatureTerms),
        treatmentNotes: Array(treatmentTerms.prefix(5)),
        bestAppliedTo: bestAppliedToValues(lane: lane),
        fitReason: directionFitReason(lane: lane, core: core, flavorNames: flavorNames),
        scoreDebug: picked.scores
    )
}

private func combinedPaletteSwatches(core: AestheticIndexItem, flavorItems: [AestheticIndexItem]) -> [AestheticIndexSwatch] {
    var seen: Set<String> = []
    var out: [AestheticIndexSwatch] = []
    for swatch in ([core] + flavorItems).flatMap({ $0.swatches ?? [] }) {
        let key = "\(swatch.colorFamily.lowercased())|\(swatch.hexColor.lowercased())"
        guard !key.trimmingCharacters(in: CharacterSet(charactersIn: "|")).isEmpty, !seen.contains(key) else { continue }
        seen.insert(key)
        out.append(swatch)
        if out.count >= 6 { break }
    }
    return out
}

private func directionCard(
    from selection: AestheticDirectionSelectionDirection,
    itemsById: [String: AestheticIndexItem],
    goalBrief: ProjectGoalBrief
) -> AestheticDirectionCard? {
    guard let core = itemsById[selection.primaryAestheticId] else { return nil }
    let flavorItems = selection.supportingAestheticIds.compactMap { itemsById[$0] }
    let lane: AestheticDirectionLane = selection.rank == 1 ? .recommended : selection.rank == 2 ? .bolderStretch : selection.rank == 3 ? .commercial : .wildcard
    let signatureTerms = uniqueCleanedValues(core.directionSignatureTerms + flavorItems.flatMap(\.directionSignatureTerms), limit: 6)
    let paletteTerms = uniqueCleanedValues(core.directionPaletteTerms + flavorItems.flatMap(\.directionPaletteTerms), limit: 6)
    let treatmentNotes = uniqueCleanedValues(selection.treatmentNotes + core.directionTreatmentTerms + flavorItems.flatMap(\.directionTreatmentTerms), limit: 6)
    let bestAppliedTo = uniqueCleanedValues(selection.bestAppliedTo, limit: 5)
    let previewImagePaths = uniqueCleanedValues([core.previewImagePath] + flavorItems.map(\.previewImagePath), limit: 4)
    return AestheticDirectionCard(
        cardId: selection.routeKey,
        lane: lane,
        laneLabel: selection.laneLabel,
        selectionRank: selection.rank,
        directionLabel: selection.directionLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? visualDirectionLabel(core: core, flavorItems: flavorItems)
            : selection.directionLabel,
        coreItem: core,
        flavorItems: flavorItems,
        avoidTerms: uniqueCleanedValues(goalBrief.aestheticIntent.normalized().avoid, limit: 5),
        intensity0To1: selection.isHero ? 0.66 : 0.58,
        ingredientControls: ingredientControls(core: core, flavorItems: flavorItems, lane: lane),
        signatureTerms: signatureTerms,
        paletteTerms: paletteTerms,
        paletteSwatches: combinedPaletteSwatches(core: core, flavorItems: flavorItems),
        previewImagePaths: previewImagePaths,
        visualSummary: selection.visualSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? directionSummary(lane: lane, core: core, signatureTerms: signatureTerms)
            : selection.visualSummary,
        treatmentNotes: treatmentNotes,
        bestAppliedTo: bestAppliedTo.isEmpty ? bestAppliedToValues(lane: lane) : bestAppliedTo,
        fitReason: selection.fitReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? directionFitReason(lane: lane, core: core, flavorNames: flavorItems.map(\.title))
            : selection.fitReason,
        supportStatus: selection.supportStatus,
        supportNote: selection.supportNote,
        evidence: uniqueCleanedValues(selection.evidence, limit: 5),
        gaps: uniqueCleanedValues(selection.gaps, limit: 4),
        conflicts: uniqueCleanedValues(selection.conflicts, limit: 4),
        scoreDebug: [:]
    )
}

func visualDirectionLabel(core: AestheticIndexItem, flavorItems: [AestheticIndexItem]) -> String {
    let labels = [core.title] + flavorItems.map(\.title)
    return labels.prefix(3).joined(separator: " + ")
}

private func directionSummary(lane: AestheticDirectionLane, core: AestheticIndexItem, signatureTerms: [String]) -> String {
    let terms = signatureTerms.isEmpty ? core.title : signatureTerms.prefix(3).joined(separator: ", ")
    switch lane {
    case .recommended:
        return "Anchors the project in a coherent \(terms) visual treatment."
    case .bolderStretch:
        return "Pushes the look toward a sharper, more memorable \(terms) finish."
    case .commercial:
        return "Shapes the project into a usable creator-facing \(terms) visual system."
    case .wildcard:
        return "Introduces a more unexpected \(terms) treatment while staying promptable."
    }
}

private func directionFitReason(lane: AestheticDirectionLane, core: AestheticIndexItem, flavorNames: [String]) -> String {
    let flavor = flavorNames.isEmpty ? "" : " with \(flavorNames.joined(separator: ", ")) as supporting treatment"
    switch lane {
    case .recommended:
        return "\(core.title)\(flavor) is the clearest visual fit for the current archive and Goal."
    case .bolderStretch:
        return "\(core.title)\(flavor) increases visual novelty without discarding the project subject."
    case .commercial:
        return "\(core.title)\(flavor) has strong treatment value for promotional and creator-facing frames."
    case .wildcard:
        return "\(core.title)\(flavor) is a credible wildcard with enough visual logic to test safely."
    }
}

private func bestAppliedToValues(lane: AestheticDirectionLane) -> [String] {
    switch lane {
    case .recommended:
        return ["hero still", "archive sequence wrapper", "steady prompt grounding"]
    case .bolderStretch:
        return ["memorable visual hook", "poster frame", "stylized title frame"]
    case .commercial:
        return ["poster", "thumbnail", "campaign asset", "social teaser"]
    case .wildcard:
        return ["contrast direction", "experimental wrapper", "visual side-path"]
    }
}

private func directionIntensity(lane: AestheticDirectionLane, scores: [String: Double]) -> Double {
    switch lane {
    case .recommended:
        return min(max(0.58 + ((scores["fit"] ?? 0) * 0.18), 0), 1)
    case .bolderStretch:
        return min(max(0.72 + ((scores["novelty"] ?? 0) * 0.18), 0), 1)
    case .commercial:
        return min(max(0.62 + ((scores["commercial"] ?? 0) * 0.16), 0), 1)
    case .wildcard:
        return min(max(0.66 + ((scores["novelty"] ?? 0) * 0.18), 0), 1)
    }
}

private func ingredientControls(core: AestheticIndexItem, flavorItems: [AestheticIndexItem], lane: AestheticDirectionLane) -> [AestheticIngredientControl] {
    let raw = uniqueCleanedValues(
        core.directionTreatmentTerms + flavorItems.flatMap(\.directionTreatmentTerms) + core.directionSignatureTerms,
        limit: 6
    )
    let base = raw.isEmpty ? [core.title] : raw
    return base.prefix(6).map { value in
        AestheticIngredientControl(
            key: normalizedControlKey(value),
            label: ingredientLabel(value),
            value0To1: lane == .bolderStretch ? 0.7 : lane == .wildcard ? 0.62 : 0.55
        )
    }
}

private func retrievalItemTerms(_ item: AestheticIndexItem) -> Set<String> {
    tokenSet(
        item.signatureTerms
            + item.treatmentTerms
            + item.paletteTerms
            + item.semanticTags
            + item.paletteKeys
            + item.motifKeys
            + item.moodKeys
            + item.valueKeys
            + item.eraKeys
            + item.energyKeys
            + item.styleKeys
            + item.facets.map(\.value)
            + item.categories
            + item.aliases
            + [item.title, item.slug, item.summary, item.description]
    )
}

private func overlapTerms(observed: Set<String>, candidate: Set<String>, limit: Int) -> [String] {
    Array(observed.intersection(candidate).sorted().prefix(max(0, limit)))
}

private func supportNote(
    status: AestheticDirectionSupportStatus,
    goalMatches: [String],
    archiveMatches: [String],
    conflicts: [String]
) -> String {
    switch status {
    case .archiveSupported:
        let value = archiveMatches.isEmpty ? goalMatches : archiveMatches
        return value.isEmpty ? "Supported by current archive evidence." : "Supported by archive cues like \(value.prefix(3).joined(separator: ", "))."
    case .goalLedStretch:
        let value = goalMatches.isEmpty ? archiveMatches : goalMatches
        return value.isEmpty ? "Goal-led treatment stretch." : "Goal-led stretch toward \(value.prefix(3).joined(separator: ", "))."
    case .conflictRisk:
        return conflicts.isEmpty ? "Carries conflict risk against stated avoids." : "Conflict risk around \(conflicts.prefix(3).joined(separator: ", "))."
    case .exploratory:
        return "Exploratory fit from the retrieved pool."
    }
}

private func shortAestheticSummary(_ value: String, limit: Int) -> String {
    let compact = value
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
    guard compact.count > limit else { return compact }
    return String(compact.prefix(max(0, limit - 1))) + "..."
}

private func directionClusterKey(for item: AestheticIndexItem) -> String {
    let semantic = tokenSet(item.semanticTags + item.signatureTerms)
    if let first = semantic.sorted().first {
        return first
    }
    return item.slug.split(separator: "-").first.map(String.init) ?? item.aestheticId
}

private func sameAestheticFamily(_ lhs: AestheticIndexItem, _ rhs: AestheticIndexItem) -> Bool {
    if lhs.aestheticId == rhs.aestheticId {
        return true
    }
    let lhsHead = lhs.slug.split(separator: "-").first.map(String.init) ?? lhs.slug
    let rhsHead = rhs.slug.split(separator: "-").first.map(String.init) ?? rhs.slug
    if !lhsHead.isEmpty, lhsHead == rhsHead {
        return true
    }
    let lhsTokens = tokenSet(lhs.signatureTerms + lhs.semanticTags)
    let rhsTokens = tokenSet(rhs.signatureTerms + rhs.semanticTags)
    return ratioScore(lhsTokens, rhsTokens) >= 0.34
}

private func isNearSelectedDuplicate(_ item: AestheticIndexItem, selectedReferences: [AestheticBriefReference]) -> Bool {
    for reference in selectedReferences where reference.aestheticId != item.aestheticId {
        let referenceHead = reference.slug.split(separator: "-").first.map(String.init) ?? reference.slug
        let itemHead = item.slug.split(separator: "-").first.map(String.init) ?? item.slug
        if !referenceHead.isEmpty, referenceHead == itemHead {
            return true
        }
        let overlap = ratioScore(tokenSet([reference.title, reference.slug]), tokenSet(item.signatureTerms + item.semanticTags + [item.title, item.slug]))
        if overlap >= 0.42 {
            return true
        }
    }
    return false
}

func normalizedControlKey(_ value: String) -> String {
    let key = tokenSet([value]).sorted().joined(separator: "_")
    return key.isEmpty ? shortHash(value, length: 10) : key
}

func ingredientLabel(_ value: String) -> String {
    value
        .replacingOccurrences(of: "_", with: " ")
        .split(separator: " ")
        .prefix(3)
        .map { word in
            word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }
        .joined(separator: " ")
}

private func aestheticScore(
    item: AestheticIndexItem,
    itemTokens: Set<String>,
    observed: [String: Set<String>],
    axes: [AestheticWheelAxis],
    wheel: AestheticWheelDocument
) -> [String: Double] {
    var valueValues = item.valueKeys
    valueValues.append(contentsOf: item.facets.filter { $0.facetType.contains("value") }.map(\.value))
    var moodValues = item.moodKeys
    moodValues.append(contentsOf: item.energyKeys)
    moodValues.append(contentsOf: [item.summary, item.description])
    var motifValues = item.motifKeys
    motifValues.append(contentsOf: item.styleKeys)
    motifValues.append(contentsOf: item.facets.filter { $0.facetType.contains("motif") }.map(\.value))
    var paletteValues = item.paletteKeys
    paletteValues.append(contentsOf: item.facets.filter { $0.facetType.contains("colour") || $0.facetType.contains("palette") }.map(\.value))
    var eraValues = item.eraKeys
    eraValues.append(contentsOf: item.categories)
    let valueTokens = tokenSet(valueValues)
    let moodTokens = tokenSet(moodValues)
    let motifTokens = tokenSet(motifValues)
    let paletteTokens = tokenSet(paletteValues)
    let eraTokens = tokenSet(eraValues)
    let qualityScore = max(0.18, item.overallConfidence > 0 ? item.overallConfidence : max(item.textConfidence, 0.35))
    let goalScore = ratioScore(observed["goal"] ?? [], itemTokens.union(valueTokens))
    let mediaScore = ratioScore(observed["media"] ?? [], itemTokens.union(motifTokens).union(paletteTokens))
    let valueScore = ratioScore(observed["values"] ?? [], valueTokens.union(itemTokens))
    let moodScore = ratioScore(observed["mood"] ?? [], moodTokens.union(itemTokens))
    let motifScore = ratioScore(observed["motif"] ?? [], motifTokens.union(itemTokens))
    let paletteScore = ratioScore(observed["palette"] ?? [], paletteTokens)
    let eraScore = ratioScore(observed["era"] ?? [], eraTokens)
    let avoidOverlap = ratioScore(observed["avoid"] ?? [], itemTokens.union(valueTokens).union(motifTokens))
    let axisScore = axisAlignmentScore(itemTokens: itemTokens, axes: axes, wheel: wheel)

    let observedHasSignals = observed.values.contains { !$0.isEmpty }
    let base = observedHasSignals
        ? (0.23 * goalScore)
            + (0.16 * mediaScore)
            + (0.13 * valueScore)
            + (0.12 * moodScore)
            + (0.12 * motifScore)
            + (0.08 * paletteScore)
            + (0.04 * eraScore)
            + (0.22 * axisScore)
        : (0.54 * qualityScore) + (0.46 * axisScore)
    var overall = min(1, (0.84 * base) + (0.16 * qualityScore)) - (0.22 * avoidOverlap)
    if !item.qualityFlags.isEmpty || !item.sourceArtifactWarnings.isEmpty {
        overall *= 0.88
    }
    if isBoilerplateAestheticDescription(item.description) {
        overall *= 0.82
    }
    overall = min(max(overall, 0), 1)
    return [
        "overall": roundedScore(overall),
        "goal": roundedScore(goalScore),
        "media": roundedScore(mediaScore),
        "values": roundedScore(valueScore),
        "mood": roundedScore(moodScore),
        "motif": roundedScore(motifScore),
        "palette": roundedScore(paletteScore),
        "era": roundedScore(eraScore),
        "quality": roundedScore(qualityScore),
        "wheel": roundedScore(axisScore),
        "avoid_overlap": roundedScore(avoidOverlap),
    ]
}

private func axisAlignmentScore(itemTokens: Set<String>, axes: [AestheticWheelAxis], wheel: AestheticWheelDocument) -> Double {
    guard !axes.isEmpty else { return 0.5 }
    var weighted = 0.0
    var totalWeight = 0.0
    for axis in axes {
        let positive = tokenSet(axis.positiveTerms + [axis.positivePole])
        let negative = tokenSet(axis.negativeTerms + [axis.negativePole])
        let positiveOverlap = ratioScore(positive, itemTokens)
        let negativeOverlap = ratioScore(negative, itemTokens)
        let itemValue = min(max(positiveOverlap - negativeOverlap, -1), 1)
        let desired = wheel.positionValue(for: axis)
        let closeness = 1 - min(abs(itemValue - desired), 2) / 2
        let weight = max(0.2, axis.weight)
        weighted += closeness * weight
        totalWeight += weight
    }
    return totalWeight > 0 ? weighted / totalWeight : 0.5
}

private func aestheticBecauseChips(item: AestheticIndexItem, scoreBreakdown: [String: Double]) -> [String] {
    var chips: [String] = []
    if (scoreBreakdown["goal"] ?? 0) >= 0.18 { chips.append("Goal fit") }
    if (scoreBreakdown["media"] ?? 0) >= 0.18 { chips.append("Archive fit") }
    if (scoreBreakdown["wheel"] ?? 0) >= 0.62 { chips.append("Wheel fit") }
    if (scoreBreakdown["mood"] ?? 0) >= 0.18 { chips.append("Mood") }
    if (scoreBreakdown["motif"] ?? 0) >= 0.18 { chips.append("Motif") }
    if (scoreBreakdown["palette"] ?? 0) >= 0.18 { chips.append("Palette") }
    if chips.isEmpty {
        chips.append(contentsOf: uniqueCleanedValues(item.valueKeys + item.moodKeys + item.motifKeys, limit: 3))
    }
    return Array(chips.prefix(5))
}

private func candidateReason(_ chips: [String]) -> String {
    guard !chips.isEmpty else { return "Matches the current Aesthetic direction." }
    return "Fits through \(chips.prefix(4).joined(separator: ", ").lowercased())."
}

private func whatItChanges(item: AestheticIndexItem) -> String {
    if let rule = item.rules.sorted(by: { $0.rank < $1.rank }).first(where: { !$0.instruction.isEmpty }) {
        return rule.instruction
    }
    if !item.styleKeys.isEmpty {
        return "Pulls the story toward \(item.styleKeys.prefix(3).joined(separator: ", "))."
    }
    return ""
}

private func caveatForAesthetic(item: AestheticCatalogItem) -> String {
    if let flag = (item.qualityFlags + item.sourceArtifactWarnings).first {
        return flag
    }
    if item.overallConfidence > 0 && item.overallConfidence < 0.42 {
        return "Weak canon profile"
    }
    return ""
}

private func suggestedRoleForAesthetic(score: Double, item: AestheticIndexItem) -> String {
    if tokenSet(item.rankingKeys + item.valueKeys).contains("avoid") {
        return "avoid"
    }
    if score >= 0.74 {
        return "core"
    }
    if item.motifKeys.count + item.paletteKeys.count > item.valueKeys.count {
        return "texture"
    }
    if score >= 0.52 {
        return "accent"
    }
    return "reference"
}

private func confidenceLabelForAesthetic(score: Double, item: AestheticCatalogItem) -> String {
    if score >= 0.72 && item.overallConfidence >= 0.42 {
        return "high"
    }
    if score >= 0.42 {
        return "medium"
    }
    return "low"
}

private func tokenSet(_ values: [String]) -> Set<String> {
    var tokens = Set<String>()
    for value in values {
        var current = ""
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else {
                if current.count >= 2 {
                    tokens.insert(current)
                }
                current = ""
            }
        }
        if current.count >= 2 {
            tokens.insert(current)
        }
    }
    return tokens
}

private func ratioScore(_ observed: Set<String>, _ candidate: Set<String>) -> Double {
    guard !observed.isEmpty, !candidate.isEmpty else { return 0 }
    let overlap = observed.intersection(candidate).count
    let denominator = max(3, min(observed.count, 18))
    return min(1, Double(overlap) / Double(denominator))
}

private func roundedScore(_ value: Double) -> Double {
    (min(max(value, 0), 1) * 10_000).rounded() / 10_000
}

private func uniqueCleanedValues(_ values: [String], limit: Int) -> [String] {
    var seen = Set<String>()
    var cleaned: [String] = []
    for raw in values {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = value.lowercased()
        guard !value.isEmpty, !seen.contains(key) else { continue }
        seen.insert(key)
        cleaned.append(value)
        if cleaned.count >= limit { break }
    }
    return cleaned
}

private func flattenCodableValues(_ object: [String: CodableValue]) -> [String] {
    object.flatMap { key, value in
        flattenCodableValue(value, label: key)
    }
}

private func flattenCodableValue(_ value: CodableValue, label: String = "") -> [String] {
    switch value {
    case .string(let string):
        return [string]
    case .number(let number):
        return [String(number)]
    case .bool(let bool):
        return [String(bool)]
    case .array(let values):
        return values.flatMap { flattenCodableValue($0, label: label) }
    case .object(let object):
        return object.flatMap { flattenCodableValue($0.value, label: $0.key) }
    case .null:
        return []
    }
}

private func isBoilerplateAestheticDescription(_ value: String) -> Bool {
    let lowered = value.lowercased()
    return lowered.contains("this article") || lowered.contains("needs cleanup") || lowered.count < 16
}

private func isJunkAestheticSummary(_ value: String) -> Bool {
    let lowered = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard lowered.count >= 24 else { return true }
    let junkMarkers = [
        "log in",
        "sign in",
        "navigation",
        "page was last edited",
        "this article",
        "needs cleanup",
        "community content",
        "fandom apps",
        "explore properties",
    ]
    return junkMarkers.contains { lowered.contains($0) }
}

private let commercialSignalTokens: Set<String> = [
    "advertising",
    "brand",
    "branding",
    "campaign",
    "commercial",
    "cover",
    "editorial",
    "graphic",
    "launch",
    "logo",
    "marketing",
    "poster",
    "product",
    "service",
    "social",
    "teaser",
    "thumbnail",
    "typography",
]
