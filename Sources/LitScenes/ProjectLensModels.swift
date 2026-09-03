import CoreGraphics
import Foundation

enum ProjectLensMessageRole: String, Codable, Hashable {
    case user
    case assistant
}

enum ProjectLensStatus: String, Codable, Hashable, CaseIterable, Identifiable {
    case draft
    case ready

    var id: String { rawValue }

    var label: String {
        switch self {
        case .draft: "Draft"
        case .ready: "Ready"
        }
    }
}

enum LensReadinessIssue: String, Codable, Hashable, CaseIterable {
    case missingTitle = "missing_title"
    case missingClaim = "missing_claim"
    case missingVisualHydration = "missing_visual_hydration"
    case missingResolvedLook = "missing_resolved_look"
    case missingResolvedProductionLanguage = "missing_resolved_production_language"
    case sourceTaxonomyInResolvedLanguage = "source_taxonomy_in_resolved_language"
    case incompleteResolvedPhrase = "incomplete_resolved_phrase"
    case positiveRequirementInMustAvoid = "positive_requirement_in_must_avoid"
    case contradictoryPreserveAvoid = "contradictory_preserve_avoid"
    case provenancePhraseInProductionField = "provenance_phrase_in_production_field"
    case compositionMissingGuidance = "composition_missing_guidance"
    case rawScrapedProseInProductionField = "raw_scraped_prose_in_production_field"
    case noMustAvoid = "no_must_avoid"
    case noMustPreserve = "no_must_preserve"
    case noStyleIngredients = "no_style_ingredients"
    case noReferenceMedia = "no_reference_media"
    case openQuestionsRemain = "open_questions_remain"
    case thinVisualSummary = "thin_visual_summary"
    case noPaletteOrMotif = "no_palette_or_motif"
    case legacyResolvedFallback = "legacy_resolved_fallback"
    case noPacingGuidance = "no_pacing_guidance"

    var label: String {
        switch self {
        case .missingTitle: "Blocked by missing title"
        case .missingClaim: "Blocked by missing claim"
        case .missingVisualHydration: "Needs visual hydration"
        case .missingResolvedLook: "Resolved look is missing"
        case .missingResolvedProductionLanguage: "Resolved production language is missing"
        case .sourceTaxonomyInResolvedLanguage: "Source taxonomy leaked into production language"
        case .incompleteResolvedPhrase: "Resolved production phrase is incomplete"
        case .positiveRequirementInMustAvoid: "Must-avoid contains a positive requirement"
        case .contradictoryPreserveAvoid: "Preserve and avoid contain the same requirement"
        case .provenancePhraseInProductionField: "Production fields contain provenance notes"
        case .compositionMissingGuidance: "Composition needs framing or spatial guidance"
        case .rawScrapedProseInProductionField: "Production fields contain raw explanatory prose"
        case .noMustAvoid: "No must-avoid rules"
        case .noMustPreserve: "No must-preserve rules"
        case .noStyleIngredients: "No stock or custom style ingredients"
        case .noReferenceMedia: "No reference media"
        case .openQuestionsRemain: "Open questions remain"
        case .thinVisualSummary: "Visual summary is thin"
        case .noPaletteOrMotif: "No palette or motif language"
        case .legacyResolvedFallback: "Using legacy fallback Scene Plan language"
        case .noPacingGuidance: "No pacing guidance"
        }
    }
}

struct LensResolvedVisualLanguage: Codable, Hashable, Sendable {
    var look: String = ""
    var palette: [String] = []
    var materials: [String] = []
    var productTreatment: [String] = []
    var motifs: [String] = []
    var composition: [String] = []
    var pacingEnergy: [String] = []
    var avoid: [String] = []

    static let empty = LensResolvedVisualLanguage()

    var productionArrays: [[String]] {
        [palette, materials, productTreatment, motifs, composition, pacingEnergy]
    }

    var isEmpty: Bool {
        look.trimmed.isEmpty
            && productionArrays.allSatisfy(\.isEmpty)
            && avoid.isEmpty
    }

    var hasProductionLanguage: Bool {
        productionArrays.contains { !$0.isEmpty }
    }

    func normalized() -> LensResolvedVisualLanguage {
        LensResolvedVisualLanguage(
            look: look.trimmed,
            palette: uniqueNonEmpty(palette),
            materials: uniqueNonEmpty(materials),
            productTreatment: uniqueNonEmpty(productTreatment),
            motifs: uniqueNonEmpty(motifs),
            composition: uniqueNonEmpty(composition),
            pacingEnergy: uniqueNonEmpty(pacingEnergy),
            avoid: uniqueNonEmpty(avoid)
        )
    }
}

struct LensColorSwatch: Codable, Hashable, Identifiable, Sendable {
    static let maximumCount = 6

    var name: String = ""
    var hex: String = ""
    var role: String = ""
    var note: String = ""

    var id: String {
        "\(name.lowercased())|\(hex.uppercased())|\(role.lowercased())"
    }

    func normalized() -> LensColorSwatch {
        LensColorSwatch(
            name: compactLensSwatchText(name, limit: 36),
            hex: normalizedLensHex(hex) ?? "",
            role: compactLensSwatchText(role, limit: 28),
            note: compactLensSwatchText(note, limit: 72)
        )
    }

    static func from(indexSwatch: AestheticIndexSwatch, role: String) -> LensColorSwatch? {
        let swatch = LensColorSwatch(
            name: indexSwatch.colorFamily,
            hex: indexSwatch.hexColor,
            role: role,
            note: ""
        ).normalized()
        return swatch.name.isEmpty || swatch.hex.isEmpty ? nil : swatch
    }
}

func uniqueLensColorSwatches(_ values: [LensColorSwatch], limit: Int = LensColorSwatch.maximumCount) -> [LensColorSwatch] {
    var seen = Set<String>()
    var output: [LensColorSwatch] = []
    for value in values {
        let normalized = value.normalized()
        guard !normalized.name.isEmpty, !normalized.hex.isEmpty else { continue }
        let key = "\(normalized.name.lowercased())|\(normalized.hex.uppercased())"
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        output.append(normalized)
        if output.count >= limit { break }
    }
    return output
}

private func normalizedLensHex(_ value: String) -> String? {
    let cleaned = value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        .uppercased()
    guard cleaned.count == 6 else { return nil }
    guard cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
    return "#\(cleaned)"
}

private func compactLensSwatchText(_ value: String, limit: Int) -> String {
    let compact = value
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
        .trimmed
    guard limit > 0, compact.count > limit else { return compact }
    return String(compact.prefix(limit)).trimmed
}

struct LensReadinessReport: Hashable, Sendable {
    let blockingIssues: [LensReadinessIssue]
    let warnings: [LensReadinessIssue]

    var isReady: Bool {
        blockingIssues.isEmpty
    }
}

func isLensLiteralProhibition(_ value: String) -> Bool {
    let clean = value.trimmed.lowercased()
    guard !clean.isEmpty else { return false }
    return clean.hasPrefix("no ")
        || clean.hasPrefix("avoid ")
        || clean.hasPrefix("never ")
        || clean.hasPrefix("without ")
        || clean.hasPrefix("exclude ")
        || clean.contains("do not")
        || clean.contains("must not")
}

func isLensPositiveRequirement(_ value: String) -> Bool {
    let clean = value.trimmed.lowercased()
    guard !clean.isEmpty else { return false }
    if isLensLiteralProhibition(clean) {
        return false
    }
    return lensContainsAnyToken(
        clean,
        ["include", "center", "show", "feature", "preserve", "use", "keep", "require", "must"]
    )
}

func lensLiteralVisualAvoidTerms(_ values: [String], limit: Int = 12) -> [String] {
    uniqueNonEmpty(values)
        .filter { isLensLiteralProhibition($0) }
        .filter { !isLensWorkflowOnlyConstraint($0) }
        .prefixArray(limit)
}

func uniqueReadinessIssues(_ issues: [LensReadinessIssue]) -> [LensReadinessIssue] {
    var seen: Set<LensReadinessIssue> = []
    var output: [LensReadinessIssue] = []
    for issue in issues where !seen.contains(issue) {
        output.append(issue)
        seen.insert(issue)
    }
    return output
}

func sanitizedGeneratedLensResolvedLanguage(
    _ language: LensResolvedVisualLanguage,
    sourceLabels: [String]
) -> LensResolvedVisualLanguage {
    let labels = Set(sourceLabels.map(lensNormalizedIssueKey).filter { !$0.isEmpty })
    return LensResolvedVisualLanguage(
        look: lensSanitizedProductionString(language.look, sourceLabels: labels),
        palette: lensSanitizedProductionList(language.palette, sourceLabels: labels),
        materials: lensSanitizedProductionList(language.materials, sourceLabels: labels),
        productTreatment: lensSanitizedProductionList(language.productTreatment, sourceLabels: labels),
        motifs: lensSanitizedProductionList(language.motifs, sourceLabels: labels),
        composition: lensSanitizedProductionList(language.composition, sourceLabels: labels),
        pacingEnergy: lensSanitizedProductionList(language.pacingEnergy, sourceLabels: labels),
        avoid: lensLiteralVisualAvoidTerms(language.avoid)
    ).normalized()
}

func sanitizedLensProductionValues(_ values: [String], sourceLabels: [String]) -> [String] {
    let labels = Set(sourceLabels.map(lensNormalizedIssueKey).filter { !$0.isEmpty })
    return lensSanitizedProductionList(values, sourceLabels: labels)
}

func sanitizedLensProductionValue(_ value: String, sourceLabels: [String]) -> String {
    let labels = Set(sourceLabels.map(lensNormalizedIssueKey).filter { !$0.isEmpty })
    return lensSanitizedProductionString(value, sourceLabels: labels)
}

private func lensSanitizedProductionString(_ value: String, sourceLabels: Set<String>) -> String {
    let clean = value.trimmed
    guard !lensShouldDropProductionValue(clean, sourceLabels: sourceLabels) else { return "" }
    return clean
}

private func lensSanitizedProductionList(_ values: [String], sourceLabels: Set<String>) -> [String] {
    uniqueNonEmpty(values)
        .filter { !lensShouldDropProductionValue($0, sourceLabels: sourceLabels) }
}

private func lensShouldDropProductionValue(_ value: String, sourceLabels: Set<String>) -> Bool {
    let clean = value.trimmed
    guard !clean.isEmpty else { return true }
    let key = lensNormalizedIssueKey(clean)
    if sourceLabels.contains(key) {
        return true
    }
    return lensLooksLikeIncompleteProductionPhrase(clean)
        || lensContainsProvenancePhrase(clean)
        || lensLooksLikeRawScrapedProse(clean)
}

private func isLensWorkflowOnlyConstraint(_ value: String) -> Bool {
    let clean = value.trimmed.lowercased()
    return lensContainsAnyToken(
        clean,
        [
            "platform plan",
            "plot outline",
            "shot list",
            "media generation plan",
            "implementation plan",
            "schema",
            "workflow"
        ]
    )
}

private func lensLooksLikeIncompleteProductionPhrase(_ value: String) -> Bool {
    let clean = value.trimmed.lowercased()
    guard clean.count > 3 else { return false }
    let incompleteSuffixes = [
        " of", " and", " or", " with", " to", " for", " by", " from", " into",
        " it is", " typically", " approached"
    ]
    if incompleteSuffixes.contains(where: { clean.hasSuffix($0) }) {
        return true
    }
    return clean.contains("typically approached") || clean.contains("benevolent aspects of")
}

private func lensContainsProvenancePhrase(_ value: String) -> Bool {
    lensContainsAnyToken(
        value.lowercased(),
        [
            "archive supports",
            "shortlist notes",
            "candidate evidence",
            "search result",
            "selected aesthetic says",
            "source aesthetic says"
        ]
    )
}

private func lensLooksLikeRawScrapedProse(_ value: String) -> Bool {
    let clean = value.trimmed.lowercased()
    guard clean.count > 120 || clean.contains(".") else { return false }
    return lensContainsAnyToken(
        clean,
        [
            "is an aesthetic",
            "is a style",
            "refers to",
            "typically",
            "characterized by",
            "involves",
            "it is",
            "the selected aesthetic"
        ]
    )
}

private func lensNormalizedIssueKey(_ value: String) -> String {
    value.lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        .split(separator: " ")
        .joined(separator: " ")
        .trimmed
}

private func lensContainsAnyToken(_ value: String, _ tokens: [String]) -> Bool {
    tokens.contains { value.contains($0) }
}

struct ProjectLensMessage: Codable, Hashable, Identifiable {
    var messageId: String
    var id: String { messageId }
    var role: ProjectLensMessageRole
    var text: String
    var targetScratchId: String?
    var targetLensId: String?
    var mediaIds: [String] = []
    var createdAt: String
}

struct ProjectLensEditMessage: Codable, Hashable, Identifiable {
    var messageId: String
    var id: String { messageId }
    var lensId: String
    var role: ProjectLensMessageRole
    var text: String
    var mediaIds: [String] = []
    var createdAt: String

    func normalized() -> ProjectLensEditMessage {
        ProjectLensEditMessage(
            messageId: messageId.trimmed,
            lensId: lensId.trimmed,
            role: role,
            text: text.trimmed,
            mediaIds: uniqueNonEmpty(mediaIds),
            createdAt: createdAt.trimmed
        )
    }
}

struct ProjectLensBodyVersion: Codable, Hashable, Identifiable {
    var versionId: String
    var id: String { versionId }
    var lensId: String
    var sourceLensSetVersionId: String
    var turnIndex: Int
    var changeSummary: String
    var model: String
    var createdAt: String
    var contentFingerprint: String
    var isActive: Bool

    func normalized() -> ProjectLensBodyVersion {
        ProjectLensBodyVersion(
            versionId: versionId.trimmed,
            lensId: lensId.trimmed,
            sourceLensSetVersionId: sourceLensSetVersionId.trimmed,
            turnIndex: max(0, turnIndex),
            changeSummary: changeSummary.trimmed,
            model: model.trimmed,
            createdAt: createdAt.trimmed,
            contentFingerprint: contentFingerprint.trimmed,
            isActive: isActive
        )
    }
}

struct LensStyleIngredient: Codable, Hashable, Identifiable {
    var ingredientId: String
    var id: String { ingredientId }
    var order: Int
    var enabled: Bool = true
    var title: String
    var role: String
    var narrativeUse: String
    var presentationUse: String
    var notes: String
    var paletteTerms: [String] = []
    var motifTerms: [String] = []
    var avoidTerms: [String] = []
    var referenceAestheticIds: [String] = []
    var sourceRecipeId: String?
    var sourceRecipeVersion: String?
    var sourceReferenceIds: [String] = []
    var updatedAt: String = DateFormats.now()

    static func custom(order: Int, now: String = DateFormats.now()) -> LensStyleIngredient {
        LensStyleIngredient(
            ingredientId: "ingredient_\(shortHash("custom:\(order):\(now)", length: 12))",
            order: order,
            title: "Custom ingredient",
            role: "supporting",
            narrativeUse: "",
            presentationUse: "",
            notes: "",
            updatedAt: now
        )
    }

    func normalized(order fallbackOrder: Int? = nil) -> LensStyleIngredient {
        var value = self
        if let fallbackOrder {
            value.order = fallbackOrder
        }
        value.ingredientId = value.ingredientId.trimmed
        if value.ingredientId.isEmpty {
            value.ingredientId = "ingredient_\(shortHash("\(value.title):\(value.order):\(value.updatedAt)", length: 12))"
        }
        value.title = value.title.trimmed
        value.role = value.role.trimmed
        value.narrativeUse = value.narrativeUse.trimmed
        value.presentationUse = value.presentationUse.trimmed
        value.notes = value.notes.trimmed
        value.paletteTerms = uniqueNonEmpty(value.paletteTerms)
        value.motifTerms = uniqueNonEmpty(value.motifTerms)
        value.avoidTerms = uniqueNonEmpty(value.avoidTerms)
        value.referenceAestheticIds = uniqueNonEmpty(value.referenceAestheticIds)
        value.sourceRecipeId = value.sourceRecipeId?.trimmed.nilIfEmpty
        value.sourceRecipeVersion = value.sourceRecipeVersion?.trimmed.nilIfEmpty
        value.sourceReferenceIds = uniqueNonEmpty(value.sourceReferenceIds)
        return value
    }
}

struct LensStyleIngredientProposal: Codable, Hashable {
    var title: String = ""
    var role: String = ""
    var narrativeUse: String = ""
    var presentationUse: String = ""
    var notes: String = ""
    var paletteTerms: [String] = []
    var motifTerms: [String] = []
    var avoidTerms: [String] = []
    var referenceAestheticIds: [String] = []
    var sourceRecipeId: String?
    var sourceRecipeVersion: String?
    var sourceReferenceIds: [String] = []
}

struct LensBodyProposal: Codable, Hashable {
    var title: String = ""
    var claim: String = ""
    var userNotes: String = ""
    var visualSummary: String = ""
    var resolvedVisualLanguage: LensResolvedVisualLanguage = .empty
    var colorPalette: [LensColorSwatch] = []
    var styleIngredients: [LensStyleIngredientProposal] = []
    var paletteTerms: [String] = []
    var motifTerms: [String] = []
    var textureMaterialTerms: [String] = []
    var compositionTerms: [String] = []
    var pacingEnergyTerms: [String] = []
    var mustPreserve: [String] = []
    var mustAvoid: [String] = []
    var referenceMediaIds: [String] = []
    var openQuestions: [String] = []
    var readinessSummary: String = ""
    var derivedVirtues: [String] = []
}

struct LensStyleTreatmentSlot: Codable, Hashable, Sendable, Identifiable {
    var styleId: String
    var label: String = ""
    var collection: String = ""
    var hueHex: String = ""
    var url: String = ""
    var weight: Int = 60

    var id: String { styleId }

    func normalized() -> LensStyleTreatmentSlot {
        var value = self
        value.styleId = value.styleId.trimmed
        value.label = value.label.trimmed
        value.collection = value.collection.trimmed
        value.hueHex = value.hueHex.trimmed
        value.url = value.url.trimmed
        value.weight = min(90, max(5, value.weight))
        return value
    }
}

struct LensStyleTreatment: Codable, Hashable, Sendable {
    var catalogVersion: String = ""
    var primary: LensStyleTreatmentSlot?
    var accents: [LensStyleTreatmentSlot] = []
    var updatedAt: String = ""

    var isEmpty: Bool {
        primary == nil && accents.isEmpty
    }

    var slots: [LensStyleTreatmentSlot] {
        var value: [LensStyleTreatmentSlot] = []
        if let primary {
            value.append(primary)
        }
        value.append(contentsOf: accents)
        return value
    }

    /// Percentage shares for the slots (primary first, then accents), computed with
    /// largest-remainder rounding so the shares always sum to exactly 100. Every share,
    /// recipe, prompt manifest, and UI readout derives from this one computation.
    func blendShares() -> [Int] {
        let weights = slots.map { max(0, $0.weight) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return weights.map { _ in 0 } }
        let exact = weights.map { Double($0) / Double(total) * 100 }
        var shares = exact.map { Int($0.rounded(.down)) }
        var remainder = 100 - shares.reduce(0, +)
        let byFraction = exact.enumerated()
            .sorted { lhs, rhs in
                let leftFraction = lhs.element - lhs.element.rounded(.down)
                let rightFraction = rhs.element - rhs.element.rounded(.down)
                if leftFraction == rightFraction { return lhs.offset < rhs.offset }
                return leftFraction > rightFraction
            }
            .map(\.offset)
        var cursor = 0
        while remainder > 0, !byFraction.isEmpty {
            shares[byFraction[cursor % byFraction.count]] += 1
            remainder -= 1
            cursor += 1
        }
        return shares
    }

    /// False when an accent outweighs the primary: role words would contradict the shares
    /// ("primary at 5 percent"), so prompts and UI must describe slots by share alone.
    var rolesAreWeightConsistent: Bool {
        guard let primary else { return accents.isEmpty }
        return accents.allSatisfy { $0.weight <= primary.weight }
    }

    /// Which style each frame renders in. Weights are ALLOCATION, not mixing: every image
    /// generation attaches exactly one style reference, and the blend is expressed by how
    /// many frames each style gets. Every style is represented at least once when there
    /// are enough frames ("a Scene Plan needs a few styles"); remaining frames apportion by
    /// weight (D'Hondt highest averages); the result interleaves deterministically with
    /// the primary on frame 1.
    func styleFrameAssignments(frameCount: Int) -> [Int] {
        let slotCount = slots.count
        guard frameCount > 0, slotCount > 0 else { return [] }
        let weights = slots.map { max(1, $0.weight) }

        // Seat counts: min-one representation when possible, then highest averages.
        var counts = [Int](repeating: 0, count: slotCount)
        var remaining = frameCount
        if frameCount >= slotCount {
            counts = [Int](repeating: 1, count: slotCount)
            remaining = frameCount - slotCount
        }
        while remaining > 0 {
            var bestIndex = 0
            var bestAverage = -1.0
            for index in 0..<slotCount {
                let average = Double(weights[index]) / Double(counts[index] + 1)
                if average > bestAverage {
                    bestAverage = average
                    bestIndex = index
                }
            }
            counts[bestIndex] += 1
            remaining -= 1
        }
        // When frames < styles, apportion the scarce frames by largest remainder so a
        // meaningful accent still earns a frame ahead of a second primary frame.
        if frameCount < slotCount {
            let totalWeight = Double(weights.reduce(0, +))
            let exact = weights.map { Double($0) * Double(frameCount) / totalWeight }
            counts = exact.map { Int($0.rounded(.down)) }
            var scarce = frameCount - counts.reduce(0, +)
            let byFraction = exact.enumerated()
                .sorted { lhs, rhs in
                    let leftFraction = lhs.element - lhs.element.rounded(.down)
                    let rightFraction = rhs.element - rhs.element.rounded(.down)
                    if leftFraction == rightFraction { return lhs.offset < rhs.offset }
                    return leftFraction > rightFraction
                }
                .map(\.offset)
            var cursor = 0
            while scarce > 0, !byFraction.isEmpty {
                counts[byFraction[cursor % byFraction.count]] += 1
                scarce -= 1
                cursor += 1
            }
        }

        // Spread the seats across the frame order (largest-remaining-fraction walk) so a
        // strip reads as a mix rather than blocks; the primary always anchors frame 1.
        var assigned = [Int](repeating: 0, count: slotCount)
        var order: [Int] = []
        for frame in 0..<frameCount {
            var bestIndex = -1
            var bestScore = -Double.infinity
            for index in 0..<slotCount where assigned[index] < counts[index] {
                let expected = Double(counts[index]) * Double(frame + 1) / Double(frameCount)
                let score = expected - Double(assigned[index])
                if score > bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }
            if frame == 0, counts[0] > 0 {
                bestIndex = 0
            }
            guard bestIndex >= 0 else { break }
            assigned[bestIndex] += 1
            order.append(bestIndex)
        }
        return order
    }

    var recipeText: String {
        zip(slots, blendShares())
            .map { slot, share in "\(share)% \(slot.label.isEmpty ? slot.styleId : slot.label)" }
            .joined(separator: " · ")
    }

    /// Compact percentage-only form ("60 · 25 · 15") for diffs and change summaries.
    var weightSummary: String {
        blendShares().map(String.init).joined(separator: " · ")
    }

    func normalized() -> LensStyleTreatment {
        var value = self
        value.catalogVersion = value.catalogVersion.trimmed
        value.primary = value.primary?.normalized()
        if value.primary?.styleId.isEmpty == true {
            value.primary = nil
        }
        var seen: Set<String> = value.primary.map { [$0.styleId] } ?? []
        value.accents = value.accents
            .map { $0.normalized() }
            .filter { slot in
                guard !slot.styleId.isEmpty, !seen.contains(slot.styleId) else { return false }
                seen.insert(slot.styleId)
                return true
            }
        value.accents = Array(value.accents.prefix(2))
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

/// How a Lens renders its composite media: how many frames, whether they are parallel
/// scenes or one continuous camera journey, the frame shape, the cast mix, how dense the
/// ambient set dressing is, and whether the world may carry readable text. All fields are
/// clamped in normalized(); legacy lenses resolve a default plan equal to prior behavior
/// (3 square collection composites, 2 characters + 1 cast object).
struct LensMediaPlan: Codable, Hashable, Sendable {
    static let modes = ["collection", "sequence"]
    static let aspects = ["square", "landscape", "portrait"]
    static let densities = ["off", "sparse", "standard", "rich"]

    var compositeCount: Int = 3
    var mode: String = "collection"
    var aspect: String = "square"
    var characterCount: Int = 2
    var castObjectCount: Int = 1
    var setDressingDensity: String = "standard"
    var allowReadableText: Bool = false
    /// Ordered beat labels for sequence mode ("establishing", "arrival", "detail"...);
    /// composite k takes beat k. Ignored in collection mode.
    var sequenceBeats: [String] = []
    /// Project roster characters cast into the composites (0-3).
    var selectedCharacterIds: [String] = []

    var isSequence: Bool { mode == "sequence" }

    /// OpenAI image size for this plan's aspect. Landscape is 3:2 (1536x1024), the widest
    /// gpt-image frame, composed for a 16:9 center crop downstream.
    var imageSize: String {
        switch aspect {
        case "landscape": return "1536x1024"
        case "portrait": return "1024x1536"
        default: return "1024x1024"
        }
    }

    var stabilityAspectRatio: String {
        switch aspect {
        case "landscape": return "3:2"
        case "portrait": return "2:3"
        default: return "1:1"
        }
    }

    /// Ambient set-dressing prompts drawn per scenery concept for this density. Kept
    /// small on purpose: the cursor cycles the pool so consecutive scenery frames get
    /// DIFFERENT subsets instead of the whole pool photocopied into every place.
    var setDressingCount: Int {
        switch setDressingDensity {
        case "off": return 0
        case "sparse": return 1
        case "rich": return 3
        default: return 2
        }
    }

    func beatLabel(forCompositeIndex index: Int) -> String {
        guard isSequence else { return "" }
        guard !sequenceBeats.isEmpty else {
            let defaults = ["establishing", "arrival", "detail"]
            return index < defaults.count ? defaults[index] : "continuation"
        }
        return sequenceBeats[min(index, sequenceBeats.count - 1)]
    }

    func normalized() -> LensMediaPlan {
        var value = self
        value.compositeCount = min(6, max(1, value.compositeCount))
        value.mode = Self.modes.contains(value.mode.trimmed) ? value.mode.trimmed : "collection"
        value.aspect = Self.aspects.contains(value.aspect.trimmed) ? value.aspect.trimmed : "square"
        value.characterCount = min(4, max(0, value.characterCount))
        value.castObjectCount = min(3, max(0, value.castObjectCount))
        value.setDressingDensity = Self.densities.contains(value.setDressingDensity.trimmed) ? value.setDressingDensity.trimmed : "standard"
        value.sequenceBeats = value.sequenceBeats.map(\.trimmed).filter { !$0.isEmpty }
        // No scene-level cast cap: the cast is derived from the scene's takes, and
        // character references attach per-frame (a study carries only its own).
        value.selectedCharacterIds = uniqueNonEmpty(value.selectedCharacterIds)
        return value
    }

    enum CodingKeys: String, CodingKey {
        case compositeCount
        case mode
        case aspect
        case characterCount
        case castObjectCount
        case setDressingDensity
        case allowReadableText
        case sequenceBeats
        case selectedCharacterIds
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        compositeCount = try container.decodeIfPresent(Int.self, forKey: .compositeCount) ?? 3
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? "collection"
        aspect = try container.decodeIfPresent(String.self, forKey: .aspect) ?? "square"
        characterCount = try container.decodeIfPresent(Int.self, forKey: .characterCount) ?? 2
        castObjectCount = try container.decodeIfPresent(Int.self, forKey: .castObjectCount) ?? 1
        setDressingDensity = try container.decodeIfPresent(String.self, forKey: .setDressingDensity) ?? "standard"
        allowReadableText = try container.decodeIfPresent(Bool.self, forKey: .allowReadableText) ?? false
        sequenceBeats = try container.decodeIfPresent([String].self, forKey: .sequenceBeats) ?? []
        selectedCharacterIds = try container.decodeIfPresent([String].self, forKey: .selectedCharacterIds) ?? []
        self = normalized()
    }
}

/// A stable, named identity that recurs across a Lens's composites (and, when linked to
/// the project character roster via characterId, across the whole project).
struct LensCastMember: Codable, Hashable, Identifiable, Sendable {
    var castId: String
    var name: String
    var descriptionPrompt: String = ""
    var characterId: String?
    /// Distinctive props this character consistently carries or wears; they appear in
    /// character studies and can headline object studies.
    var signatureProps: [String] = []
    /// The environment this character visually belongs to, as plain content.
    var environmentAffinity: String = ""

    var id: String { castId }

    func normalized() -> LensCastMember {
        var value = self
        value.castId = value.castId.trimmed
        if value.castId.isEmpty {
            value.castId = "cast_\(shortHash("\(value.name):\(value.descriptionPrompt)", length: 12))"
        }
        value.name = value.name.trimmed
        value.descriptionPrompt = value.descriptionPrompt.trimmed
        value.characterId = value.characterId?.trimmed.nilIfEmpty
        value.signatureProps = Array(uniqueNonEmpty(value.signatureProps).prefix(3))
        value.environmentAffinity = value.environmentAffinity.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case castId
        case name
        case descriptionPrompt
        case characterId
        case signatureProps
        case environmentAffinity
    }

    init(
        castId: String,
        name: String,
        descriptionPrompt: String = "",
        characterId: String? = nil,
        signatureProps: [String] = [],
        environmentAffinity: String = ""
    ) {
        self.castId = castId
        self.name = name
        self.descriptionPrompt = descriptionPrompt
        self.characterId = characterId
        self.signatureProps = signatureProps
        self.environmentAffinity = environmentAffinity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        castId = try container.decodeIfPresent(String.self, forKey: .castId) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        descriptionPrompt = try container.decodeIfPresent(String.self, forKey: .descriptionPrompt) ?? ""
        characterId = try container.decodeIfPresent(String.self, forKey: .characterId)
        signatureProps = try container.decodeIfPresent([String].self, forKey: .signatureProps) ?? []
        environmentAffinity = try container.decodeIfPresent(String.self, forKey: .environmentAffinity) ?? ""
        self = normalized()
    }
}

/// Structured content for one scenery concept: world data as fields, with prompt prose
/// assembled at render time. Deliberately carries NO color, palette, lighting-character,
/// or medium fields — the attached style image owns all rendering.
struct LensSceneSetting: Codable, Hashable, Sendable {
    var title: String = ""
    var locationName: String = ""
    var locationType: String = ""
    var timeOfDay: String = ""
    var weather: String = ""
    var spatialLayout: String = ""
    var foregroundDetails: [String] = []
    var backgroundDetails: [String] = []
    var notableFeatures: [String] = []

    var isEmpty: Bool {
        locationName.trimmed.isEmpty && spatialLayout.trimmed.isEmpty && foregroundDetails.isEmpty
    }

    func normalized() -> LensSceneSetting {
        var value = self
        value.title = value.title.trimmed
        value.locationName = value.locationName.trimmed
        value.locationType = value.locationType.trimmed
        value.timeOfDay = value.timeOfDay.trimmed
        value.weather = value.weather.trimmed
        value.spatialLayout = value.spatialLayout.trimmed
        value.foregroundDetails = Array(uniqueNonEmpty(value.foregroundDetails).prefix(6))
        value.backgroundDetails = Array(uniqueNonEmpty(value.backgroundDetails).prefix(6))
        value.notableFeatures = Array(uniqueNonEmpty(value.notableFeatures).prefix(6))
        return value
    }

    /// Compact one-line form for use as a secondary backdrop in character/object studies.
    var condensed: String {
        uniqueNonEmpty([locationName, locationType, timeOfDay, weather])
            .joined(separator: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case title
        case locationName
        case locationType
        case timeOfDay
        case weather
        case spatialLayout
        case foregroundDetails
        case backgroundDetails
        case notableFeatures
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName) ?? ""
        locationType = try container.decodeIfPresent(String.self, forKey: .locationType) ?? ""
        timeOfDay = try container.decodeIfPresent(String.self, forKey: .timeOfDay) ?? ""
        weather = try container.decodeIfPresent(String.self, forKey: .weather) ?? ""
        spatialLayout = try container.decodeIfPresent(String.self, forKey: .spatialLayout) ?? ""
        foregroundDetails = try container.decodeIfPresent([String].self, forKey: .foregroundDetails) ?? []
        backgroundDetails = try container.decodeIfPresent([String].self, forKey: .backgroundDetails) ?? []
        notableFeatures = try container.decodeIfPresent([String].self, forKey: .notableFeatures) ?? []
        self = normalized()
    }
}

/// One character cast into a specific scene view: an exact cast/roster name plus a
/// short subject-matter-only phrase for how they occupy the place. Rendered into
/// the scenery prompt as an @Name mention line.
struct LensSceneCastEntry: Codable, Hashable, Sendable {
    var name: String = ""
    var presence: String = ""

    var isEmpty: Bool { name.trimmed.isEmpty }

    func normalized() -> LensSceneCastEntry {
        var value = self
        value.name = value.name.trimmed
        value.presence = value.presence.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case name
        case presence
    }

    init(name: String = "", presence: String = "") {
        self.name = name
        self.presence = presence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        presence = try container.decodeIfPresent(String.self, forKey: .presence) ?? ""
    }
}

/// Builds the scenery-prompt cast line from a scene's cast entries. Exact
/// case-insensitive matches against `validNames` (goal cast + roster) emit the
/// canonical `@Name` token — the Frame Creator resolves those into attached
/// reference images. Unmatched names render as plain text, never a token: a wrong
/// match would attach the wrong character's references.
enum LensSceneCastPrompt {
    static func mentionLine(cast: [LensSceneCastEntry], validNames: [String]) -> String? {
        let entries = cast.map { $0.normalized() }.filter { !$0.isEmpty }.prefix(2)
        guard !entries.isEmpty else { return nil }
        let names = validNames.map { $0.trimmed }.filter { !$0.isEmpty }
        let sentences = entries.map { entry -> String in
            let canonical = names.first { $0.compare(entry.name, options: [.caseInsensitive]) == .orderedSame }
            let token = canonical.map { "@\($0)" } ?? entry.name
            var sentence = entry.presence.isEmpty ? token : "\(token) \(entry.presence)"
            if let last = sentence.last, !".!?".contains(last) {
                sentence += "."
            }
            return sentence
        }
        return "Present in this scene: " + sentences.joined(separator: " ")
    }
}

/// One authored scene inside an Area. The generated image row for this scene stores
/// the stable area/scene ids so future disable and curation controls do not depend on
/// route-key parsing.
struct LensAreaScene: Codable, Hashable, Identifiable, Sendable {
    var sceneId: String = ""
    var title: String = ""
    var setting: LensSceneSetting = LensSceneSetting()
    var prosePrompt: String = ""
    var cast: [LensSceneCastEntry] = []
    var enabled: Bool = true
    /// The arc position this frame samples (opening / rising / turn / ending, or a
    /// short free label). Empty on plans composed before beats existed.
    var storyBeat: String = ""

    var id: String { sceneId }
    var isEmpty: Bool {
        title.trimmed.isEmpty && setting.normalized().isEmpty && prosePrompt.trimmed.isEmpty
    }

    func normalized(areaId: String = "", order: Int = 0) -> LensAreaScene {
        var value = self
        value.sceneId = value.sceneId.trimmed
        value.title = value.title.trimmed
        value.setting = value.setting.normalized()
        value.prosePrompt = value.prosePrompt.trimmed
        value.cast = Array(value.cast.map { $0.normalized() }.filter { !$0.isEmpty }.prefix(2))
        value.storyBeat = value.storyBeat.trimmed.lowercased()
        if value.title.isEmpty {
            value.title = value.setting.title.nilIfEmpty
                ?? value.setting.locationName.nilIfEmpty
                ?? "Scene \(order + 1)"
        }
        if value.sceneId.isEmpty {
            value.sceneId = "scene_\(shortHash("\(areaId):\(value.title):\(value.setting.locationName):\(order)", length: 12))"
        }
        return value
    }

    enum CodingKeys: String, CodingKey {
        case sceneId
        case title
        case setting
        case prosePrompt
        case cast
        case enabled
        case storyBeat
    }

    init(
        sceneId: String = "",
        title: String = "",
        setting: LensSceneSetting = LensSceneSetting(),
        prosePrompt: String = "",
        cast: [LensSceneCastEntry] = [],
        enabled: Bool = true,
        storyBeat: String = ""
    ) {
        self.sceneId = sceneId
        self.title = title
        self.setting = setting
        self.prosePrompt = prosePrompt
        self.cast = cast
        self.enabled = enabled
        self.storyBeat = storyBeat
    }

    // Tolerant decode: persisted lens docs predating `cast` (and any future
    // partial documents) must keep decoding.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sceneId = try container.decodeIfPresent(String.self, forKey: .sceneId) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        setting = try container.decodeIfPresent(LensSceneSetting.self, forKey: .setting) ?? LensSceneSetting()
        prosePrompt = try container.decodeIfPresent(String.self, forKey: .prosePrompt) ?? ""
        cast = try container.decodeIfPresent([LensSceneCastEntry].self, forKey: .cast) ?? []
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        storyBeat = try container.decodeIfPresent(String.self, forKey: .storyBeat) ?? ""
    }
}

/// A story place that owns multiple generated scene images. Existing flat
/// scene_settings decode into one Area whose scenes are those old settings.
/// `placeId` links the area to its ProjectPlace roster entry (empty on legacy
/// lenses composed before places existed).
struct LensArea: Codable, Hashable, Identifiable, Sendable {
    var areaId: String = ""
    var placeId: String = ""
    var title: String = ""
    var setting: LensSceneSetting = LensSceneSetting()
    var prosePrompt: String = ""
    var scenes: [LensAreaScene] = []
    var enabled: Bool = true

    var id: String { areaId }
    var isEmpty: Bool {
        title.trimmed.isEmpty && setting.normalized().isEmpty && scenes.allSatisfy(\.isEmpty)
    }

    func normalized(order: Int = 0) -> LensArea {
        var value = self
        value.areaId = value.areaId.trimmed
        value.placeId = value.placeId.trimmed
        value.title = value.title.trimmed
        value.setting = value.setting.normalized()
        value.prosePrompt = value.prosePrompt.trimmed
        if value.title.isEmpty {
            value.title = value.setting.title.nilIfEmpty
                ?? value.setting.locationName.nilIfEmpty
                ?? "Area \(order + 1)"
        }
        if value.areaId.isEmpty {
            value.areaId = "area_\(shortHash("\(value.title):\(value.setting.locationName):\(order)", length: 12))"
        }
        let normalizedScenes = value.scenes
            .enumerated()
            .map { index, scene in scene.normalized(areaId: value.areaId, order: index) }
            .filter { !$0.isEmpty }
        if normalizedScenes.isEmpty, !value.setting.isEmpty || !value.prosePrompt.isEmpty {
            value.scenes = [
                LensAreaScene(
                    sceneId: "scene_\(shortHash("\(value.areaId):primary", length: 12))",
                    title: value.title,
                    setting: value.setting,
                    prosePrompt: value.prosePrompt,
                    enabled: true
                ).normalized(areaId: value.areaId, order: 0)
            ]
        } else {
            value.scenes = normalizedScenes
        }
        return value
    }

    enum CodingKeys: String, CodingKey {
        case areaId
        case placeId
        case title
        case setting
        case prosePrompt
        case scenes
        case enabled
    }

    init() {}

    // Tolerant decode: persisted lens docs predating `placeId` (and any future
    // partial documents) must keep decoding.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        areaId = try container.decodeIfPresent(String.self, forKey: .areaId) ?? ""
        placeId = try container.decodeIfPresent(String.self, forKey: .placeId) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        setting = try container.decodeIfPresent(LensSceneSetting.self, forKey: .setting) ?? LensSceneSetting()
        prosePrompt = try container.decodeIfPresent(String.self, forKey: .prosePrompt) ?? ""
        scenes = try container.decodeIfPresent([LensAreaScene].self, forKey: .scenes) ?? []
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

enum LensImageTaxonomyKind {
    static let areaImage = "area_image"
    static let sceneImage = "scene_image"
    static let characterImage = "character_image"
    static let objectImage = "object_image"
    static let legacy = "legacy"

    static func normalized(_ value: String) -> String {
        switch value.trimmed.lowercased() {
        case areaImage: areaImage
        case sceneImage: sceneImage
        case characterImage: characterImage
        case objectImage: objectImage
        case legacy: legacy
        default: ""
        }
    }
}

/// Structured content for one prop study. Content-only, like LensSceneSetting.
struct LensObjectConcept: Codable, Hashable, Sendable {
    var name: String = ""
    var type: String = ""
    var material: String = ""
    var condition: String = ""
    var distinguishingFeatures: [String] = []
    var locationInScene: String = ""

    var isEmpty: Bool {
        name.trimmed.isEmpty
    }

    func normalized() -> LensObjectConcept {
        var value = self
        value.name = value.name.trimmed
        value.type = value.type.trimmed
        value.material = value.material.trimmed
        value.condition = value.condition.trimmed
        value.distinguishingFeatures = Array(uniqueNonEmpty(value.distinguishingFeatures).prefix(5))
        value.locationInScene = value.locationInScene.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case material
        case condition
        case distinguishingFeatures
        case locationInScene
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        material = try container.decodeIfPresent(String.self, forKey: .material) ?? ""
        condition = try container.decodeIfPresent(String.self, forKey: .condition) ?? ""
        distinguishingFeatures = try container.decodeIfPresent([String].self, forKey: .distinguishingFeatures) ?? []
        locationInScene = try container.decodeIfPresent(String.self, forKey: .locationInScene) ?? ""
        self = normalized()
    }
}

/// A literal recurring asset that must appear AS ITSELF in every composite (a map, an
/// emblem, a product). The precise inverse of a style reference: subject matter, never
/// style. Resolved from project media at generation time.
struct LensCanonicalAnchor: Codable, Hashable, Sendable {
    static let placements = ["featured", "recurring-background"]

    var mediaId: String = ""
    var caption: String = ""
    var placement: String = "featured"

    var isEmpty: Bool { mediaId.trimmed.isEmpty }

    func normalized() -> LensCanonicalAnchor {
        var value = self
        value.mediaId = value.mediaId.trimmed
        value.caption = value.caption.trimmed
        value.placement = Self.placements.contains(value.placement.trimmed) ? value.placement.trimmed : "featured"
        return value
    }

    enum CodingKeys: String, CodingKey {
        case mediaId
        case caption
        case placement
    }

    init(mediaId: String = "", caption: String = "", placement: String = "featured") {
        self.mediaId = mediaId
        self.caption = caption
        self.placement = placement
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaId = try container.decodeIfPresent(String.self, forKey: .mediaId) ?? ""
        caption = try container.decodeIfPresent(String.self, forKey: .caption) ?? ""
        placement = try container.decodeIfPresent(String.self, forKey: .placement) ?? "featured"
        self = normalized()
    }
}

struct LensBody: Codable, Hashable {
    var title: String = ""
    var claim: String = ""
    var userNotes: String = ""
    var visualSummary: String = ""
    var resolvedVisualLanguage: LensResolvedVisualLanguage?
    var colorPalette: [LensColorSwatch] = []
    var styleIngredients: [LensStyleIngredient] = []
    var paletteTerms: [String] = []
    var motifTerms: [String] = []
    var textureMaterialTerms: [String] = []
    var compositionTerms: [String] = []
    var pacingEnergyTerms: [String] = []
    var mustPreserve: [String] = []
    var mustAvoid: [String] = []
    var referenceMediaIds: [String] = []
    var openQuestions: [String] = []
    var readinessSummary: String = ""
    var derivedVirtues: [String] = []
    var styleTreatment: LensStyleTreatment?
    var goalSliceTitle: String?
    var goalSliceIntent: String?
    var characterImagePrompts: [String]?
    var sceneImagePrompts: [String]?
    var objectImagePrompts: [String]?
    /// Legacy 3-subject cast split; superseded by mediaPlan.characterCount but kept for
    /// tolerant decode of older lenses.
    var compositeCharacterCount: Int?
    var mediaPlan: LensMediaPlan?
    /// Ambient worldbuilding objects, present in the scene but in no one's hands —
    /// distinct from objectImagePrompts, whose objects the cast uses.
    var setDressingImagePrompts: [String]?
    var castMembers: [LensCastMember]?
    var canonicalAnchor: LensCanonicalAnchor?
    /// Structured scenery concepts (v0.3+); prompt prose assembles from these at render
    /// time. The legacy prose pools above remain as fallbacks for older lenses.
    var sceneSettings: [LensSceneSetting]?
    /// Structured place hierarchy (v0.4+): Areas are broad recurring environments, and
    /// each Area owns renderable Scene children.
    var areas: [LensArea]?
    /// Structured prop-study concepts (v0.3+).
    var objectConcepts: [LensObjectConcept]?
    /// Provenance of the frame plan: the Goal version and lens-context fingerprint the
    /// areas, cast, and objects were composed from. nil on plans composed before
    /// provenance existed.
    var planGoalVersionId: String?
    var planGoalFingerprint: String?

    static func empty() -> LensBody {
        LensBody()
    }

    var hasVisualHydration: Bool {
        !visualSummary.trimmed.isEmpty
            || resolvedVisualLanguage?.normalized().isEmpty == false
            || !colorPalette.isEmpty
            || !styleIngredients.isEmpty
            || !paletteTerms.isEmpty
            || !motifTerms.isEmpty
            || !textureMaterialTerms.isEmpty
            || !compositionTerms.isEmpty
            || !pacingEnergyTerms.isEmpty
    }

    var hasDraftContent: Bool {
        let normalized = normalized()
        return !normalized.title.isEmpty
            || !normalized.claim.isEmpty
            || !normalized.userNotes.isEmpty
            || !normalized.visualSummary.isEmpty
            || normalized.resolvedVisualLanguage?.isEmpty == false
            || !normalized.colorPalette.isEmpty
            || !normalized.styleIngredients.isEmpty
            || !normalized.paletteTerms.isEmpty
            || !normalized.motifTerms.isEmpty
            || !normalized.textureMaterialTerms.isEmpty
            || !normalized.compositionTerms.isEmpty
            || !normalized.pacingEnergyTerms.isEmpty
            || !normalized.mustPreserve.isEmpty
            || !normalized.mustAvoid.isEmpty
            || !normalized.referenceMediaIds.isEmpty
            || !normalized.openQuestions.isEmpty
            || !normalized.readinessSummary.isEmpty
            || !normalized.derivedVirtues.isEmpty
            || normalized.styleTreatment?.isEmpty == false
    }

    var hardBlocks: [LensReadinessIssue] {
        readinessReport.blockingIssues
    }

    var warnings: [LensReadinessIssue] {
        readinessReport.warnings
    }

    var readinessReport: LensReadinessReport {
        LensReadinessReport.make(for: self)
    }

    var resolvedVisualLanguageForSceneStory: LensResolvedVisualLanguage {
        if let resolved = resolvedVisualLanguage?.normalized(), !resolved.isEmpty {
            return resolved
        }
        return LensResolvedVisualLanguage(look: visualSummary.trimmed).normalized()
    }

    func normalized() -> LensBody {
        var value = self
        value.title = value.title.trimmed
        value.claim = value.claim.trimmed
        value.userNotes = value.userNotes.trimmed
        value.visualSummary = value.visualSummary.trimmed
        if let resolved = value.resolvedVisualLanguage?.normalized(), !resolved.isEmpty {
            value.resolvedVisualLanguage = resolved
        } else {
            value.resolvedVisualLanguage = nil
        }
        value.colorPalette = uniqueLensColorSwatches(value.colorPalette)
        value.styleIngredients = value.styleIngredients
            .sorted { $0.order < $1.order }
            .enumerated()
            .map { index, ingredient in
                ingredient.normalized(order: index + 1)
            }
        value.paletteTerms = uniqueNonEmpty(value.paletteTerms)
        value.motifTerms = uniqueNonEmpty(value.motifTerms)
        value.textureMaterialTerms = uniqueNonEmpty(value.textureMaterialTerms)
        value.compositionTerms = uniqueNonEmpty(value.compositionTerms)
        value.pacingEnergyTerms = uniqueNonEmpty(value.pacingEnergyTerms)
        value.mustPreserve = uniqueNonEmpty(value.mustPreserve)
        value.mustAvoid = uniqueNonEmpty(value.mustAvoid)
        value.referenceMediaIds = uniqueNonEmpty(value.referenceMediaIds)
        value.openQuestions = uniqueNonEmpty(value.openQuestions)
        value.readinessSummary = value.readinessSummary.trimmed
        value.derivedVirtues = uniqueNonEmpty(value.derivedVirtues)
        if let treatment = value.styleTreatment?.normalized(), !treatment.isEmpty {
            value.styleTreatment = treatment
        } else {
            value.styleTreatment = nil
        }
        value.goalSliceTitle = value.goalSliceTitle?.trimmed.nilIfEmpty
        value.goalSliceIntent = value.goalSliceIntent?.trimmed.nilIfEmpty
        value.characterImagePrompts = value.characterImagePrompts.flatMap { uniqueNonEmpty($0).isEmpty ? nil : uniqueNonEmpty($0) }
        value.sceneImagePrompts = value.sceneImagePrompts.flatMap { uniqueNonEmpty($0).isEmpty ? nil : uniqueNonEmpty($0) }
        value.objectImagePrompts = value.objectImagePrompts.flatMap { uniqueNonEmpty($0).isEmpty ? nil : uniqueNonEmpty($0) }
        value.compositeCharacterCount = value.compositeCharacterCount.map { min(3, max(0, $0)) }
        value.mediaPlan = value.mediaPlan?.normalized()
        value.setDressingImagePrompts = value.setDressingImagePrompts.flatMap { uniqueNonEmpty($0).isEmpty ? nil : uniqueNonEmpty($0) }
        value.castMembers = value.castMembers.flatMap { members in
            let normalizedMembers = members.map { $0.normalized() }.filter { !$0.name.isEmpty }
            return normalizedMembers.isEmpty ? nil : normalizedMembers
        }
        if let anchor = value.canonicalAnchor?.normalized(), !anchor.isEmpty {
            value.canonicalAnchor = anchor
        } else {
            value.canonicalAnchor = nil
        }
        value.sceneSettings = value.sceneSettings.flatMap { settings in
            let normalizedSettings = settings.map { $0.normalized() }.filter { !$0.isEmpty }
            return normalizedSettings.isEmpty ? nil : normalizedSettings
        }
        value.areas = value.areas.flatMap { areas in
            let normalizedAreas = areas
                .enumerated()
                .map { index, area in area.normalized(order: index) }
                .filter { !$0.isEmpty }
            return normalizedAreas.isEmpty ? nil : normalizedAreas
        }
        if value.areas == nil {
            let legacyAreas = LensBody.legacyAreas(
                sceneSettings: value.sceneSettings ?? [],
                scenePrompts: value.sceneImagePrompts ?? []
            )
            value.areas = legacyAreas.isEmpty ? nil : legacyAreas
        }
        let areaSceneSettings = (value.areas ?? [])
            .flatMap(\.scenes)
            .map(\.setting)
            .filter { !$0.isEmpty }
        if !areaSceneSettings.isEmpty {
            value.sceneSettings = areaSceneSettings
        }
        value.objectConcepts = value.objectConcepts.flatMap { concepts in
            let normalizedConcepts = concepts.map { $0.normalized() }.filter { !$0.isEmpty }
            return normalizedConcepts.isEmpty ? nil : normalizedConcepts
        }
        value.planGoalVersionId = value.planGoalVersionId?.trimmed.nilIfEmpty
        value.planGoalFingerprint = value.planGoalFingerprint?.trimmed.nilIfEmpty
        return value
    }

    /// How many of a composite's three subjects are characters (the rest are objects).
    /// Defaults to 2 characters + 1 object when unset.
    var resolvedCompositeCharacterCount: Int {
        min(3, max(0, compositeCharacterCount ?? 2))
    }

    /// The media plan driving composite generation. Lenses that predate plans resolve to
    /// the legacy behavior: 3 square collection composites whose cast honors the old
    /// compositeCharacterCount split (characters + objects summing to 3).
    var resolvedMediaPlan: LensMediaPlan {
        if let mediaPlan {
            return mediaPlan.normalized()
        }
        var plan = LensMediaPlan()
        plan.characterCount = resolvedCompositeCharacterCount
        plan.castObjectCount = 3 - resolvedCompositeCharacterCount
        return plan.normalized()
    }

    /// The Lens's media prompt sets in generation order: the scene establishes the world,
    /// the character inhabits that scene, the object is what those characters use.
    /// Empty for lenses that predate media-prompt generation.
    var lensMediaPromptCategories: [(key: String, label: String, prompts: [String])] {
        [
            ("scene", "Scene", sceneImagePrompts ?? []),
            ("character", "Character", characterImagePrompts ?? []),
            ("object", "Object", objectImagePrompts ?? [])
        ]
    }

    /// True when the lens carries at least one scenery source — structured scene settings
    /// (v0.3+) or a legacy scene prose pool. Mirrors queuedLensConceptImages, which anchors
    /// every media version on a scenery frame and queues nothing without one; structured
    /// lenses keep their legacy prose pools empty, so gating on those alone is wrong.
    var hasRenderableMediaSources: Bool {
        !(areas ?? []).isEmpty || !(sceneSettings ?? []).isEmpty || !(sceneImagePrompts ?? []).isEmpty
    }

    func sanitizedForGeneratedDraft(sourceLabels: [String]) -> LensBody {
        var value = normalized()
        if let resolved = value.resolvedVisualLanguage?.normalized() {
            value.resolvedVisualLanguage = sanitizedGeneratedLensResolvedLanguage(
                resolved,
                sourceLabels: sourceLabels
            )
        }
        value.mustAvoid = lensLiteralVisualAvoidTerms(value.mustAvoid)
        value.styleIngredients = value.styleIngredients.map { ingredient in
            var updated = ingredient
            updated.avoidTerms = lensLiteralVisualAvoidTerms(updated.avoidTerms)
            return updated.normalized()
        }
        return value.normalized()
    }

    func replacing(with proposal: LensBodyProposal, now: String = DateFormats.now()) -> LensBody {
        let existingByKey = Dictionary(uniqueKeysWithValues: styleIngredients.map { (LensBody.ingredientKey($0.title, role: $0.role), $0) })
        var proposedIngredients: [LensStyleIngredient] = []
        for (index, proposalIngredient) in proposal.styleIngredients.enumerated() {
            let key = LensBody.ingredientKey(proposalIngredient.title, role: proposalIngredient.role)
            let existing = existingByKey[key]
            proposedIngredients.append(LensStyleIngredient(
                ingredientId: existing?.ingredientId ?? "ingredient_\(shortHash("\(key):\(now):\(index)", length: 12))",
                order: index + 1,
                enabled: existing?.enabled ?? true,
                title: proposalIngredient.title,
                role: proposalIngredient.role,
                narrativeUse: proposalIngredient.narrativeUse,
                presentationUse: proposalIngredient.presentationUse,
                notes: proposalIngredient.notes,
                paletteTerms: proposalIngredient.paletteTerms,
                motifTerms: proposalIngredient.motifTerms,
                avoidTerms: proposalIngredient.avoidTerms,
                referenceAestheticIds: proposalIngredient.referenceAestheticIds,
                sourceRecipeId: proposalIngredient.sourceRecipeId,
                sourceRecipeVersion: proposalIngredient.sourceRecipeVersion,
                sourceReferenceIds: proposalIngredient.sourceReferenceIds,
                updatedAt: now
            ))
        }
        return LensBody(
            title: proposal.title,
            claim: proposal.claim,
            userNotes: proposal.userNotes,
            visualSummary: proposal.visualSummary,
            resolvedVisualLanguage: proposal.resolvedVisualLanguage,
            colorPalette: proposal.colorPalette,
            styleIngredients: proposedIngredients,
            paletteTerms: proposal.paletteTerms,
            motifTerms: proposal.motifTerms,
            textureMaterialTerms: proposal.textureMaterialTerms,
            compositionTerms: proposal.compositionTerms,
            pacingEnergyTerms: proposal.pacingEnergyTerms,
            mustPreserve: proposal.mustPreserve,
            mustAvoid: proposal.mustAvoid,
            referenceMediaIds: proposal.referenceMediaIds,
            openQuestions: proposal.openQuestions,
            readinessSummary: proposal.readinessSummary,
            derivedVirtues: proposal.derivedVirtues,
            styleTreatment: styleTreatment
        ).normalized()
    }

    private static func ingredientKey(_ title: String, role: String) -> String {
        "\(title.trimmed.lowercased())|\(role.trimmed.lowercased())"
    }

    private static func legacyAreas(sceneSettings: [LensSceneSetting], scenePrompts: [String]) -> [LensArea] {
        let normalizedSettings = sceneSettings.map { $0.normalized() }.filter { !$0.isEmpty }
        let normalizedPrompts = uniqueNonEmpty(scenePrompts)
        let count = max(normalizedSettings.count, normalizedPrompts.count)
        guard count > 0 else { return [] }

        let areaSetting = normalizedSettings.first ?? LensSceneSetting()
        var scenes: [LensAreaScene] = []
        for index in 0..<count {
            let setting = index < normalizedSettings.count ? normalizedSettings[index] : areaSetting
            let prompt = index < normalizedPrompts.count ? normalizedPrompts[index] : ""
            var scene = LensAreaScene()
            scene.sceneId = "scene_legacy_\(index + 1)"
            scene.title = setting.title.nilIfEmpty ?? setting.locationName.nilIfEmpty ?? "Scene \(index + 1)"
            scene.setting = setting
            scene.prosePrompt = prompt
            scenes.append(scene)
        }

        var area = LensArea()
        area.areaId = "area_legacy_primary"
        area.title = areaSetting.title.nilIfEmpty ?? areaSetting.locationName.nilIfEmpty ?? "Area 1"
        area.setting = areaSetting
        area.prosePrompt = normalizedPrompts.first ?? ""
        area.scenes = scenes
        return [area.normalized(order: 0)]
    }
}

extension LensReadinessReport {
    static func make(for body: LensBody) -> LensReadinessReport {
        let normalized = body.normalizedForReadiness()
        let resolved = normalized.resolvedVisualLanguageForSceneStory
        var blocking: [LensReadinessIssue] = []
        var warnings: [LensReadinessIssue] = []

        if normalized.title.trimmed.isEmpty { blocking.append(.missingTitle) }
        if normalized.claim.trimmed.isEmpty { blocking.append(.missingClaim) }
        if !normalized.hasVisualHydration { blocking.append(.missingVisualHydration) }
        if resolved.look.trimmed.isEmpty { blocking.append(.missingResolvedLook) }
        if !resolved.hasProductionLanguage { blocking.append(.missingResolvedProductionLanguage) }
        if resolvedContainsSourceTaxonomy(resolved, ingredients: normalized.styleIngredients) {
            blocking.append(.sourceTaxonomyInResolvedLanguage)
        }
        if resolvedProductionValues(resolved).contains(where: isIncompleteResolvedPhrase) {
            blocking.append(.incompleteResolvedPhrase)
        }
        if normalized.mustAvoid.contains(where: isLensPositiveRequirement) {
            blocking.append(.positiveRequirementInMustAvoid)
        }
        if hasPreserveAvoidContradiction(preserve: normalized.mustPreserve, avoid: normalized.mustAvoid) {
            blocking.append(.contradictoryPreserveAvoid)
        }
        if resolvedProductionValues(resolved).contains(where: containsProvenancePhrase) {
            blocking.append(.provenancePhraseInProductionField)
        }
        if compositionHasOnlyUseCases(resolved.composition) {
            blocking.append(.compositionMissingGuidance)
        }
        if resolvedProductionValues(resolved).contains(where: looksLikeRawScrapedProse) {
            blocking.append(.rawScrapedProseInProductionField)
        }

        if normalized.mustAvoid.isEmpty { warnings.append(.noMustAvoid) }
        if normalized.mustPreserve.isEmpty { warnings.append(.noMustPreserve) }
        if normalized.styleIngredients.isEmpty { warnings.append(.noStyleIngredients) }
        if normalized.referenceMediaIds.isEmpty { warnings.append(.noReferenceMedia) }
        if !normalized.openQuestions.isEmpty { warnings.append(.openQuestionsRemain) }
        if normalized.visualSummary.trimmed.split(separator: " ").count < 8 { warnings.append(.thinVisualSummary) }
        if resolved.palette.isEmpty || resolved.motifs.isEmpty { warnings.append(.noPaletteOrMotif) }
        if normalized.resolvedVisualLanguage?.normalized().isEmpty != false { warnings.append(.legacyResolvedFallback) }
        if resolved.pacingEnergy.isEmpty { warnings.append(.noPacingGuidance) }

        return LensReadinessReport(
            blockingIssues: uniqueIssues(blocking),
            warnings: uniqueIssues(warnings)
        )
    }

    private static func uniqueIssues(_ issues: [LensReadinessIssue]) -> [LensReadinessIssue] {
        var seen: Set<LensReadinessIssue> = []
        var output: [LensReadinessIssue] = []
        for issue in issues where !seen.contains(issue) {
            output.append(issue)
            seen.insert(issue)
        }
        return output
    }

    private static func resolvedProductionValues(_ resolved: LensResolvedVisualLanguage) -> [String] {
        uniqueNonEmpty(
            [resolved.look]
                + resolved.palette
                + resolved.materials
                + resolved.productTreatment
                + resolved.motifs
                + resolved.composition
                + resolved.pacingEnergy
                + resolved.avoid
        )
    }

    private static func resolvedContainsSourceTaxonomy(
        _ resolved: LensResolvedVisualLanguage,
        ingredients: [LensStyleIngredient]
    ) -> Bool {
        let labels = Set(ingredients.map(\.title).map(normalizedIssueKey).filter { !$0.isEmpty })
        guard !labels.isEmpty else { return false }
        return resolvedProductionValues(resolved)
            .map(normalizedIssueKey)
            .contains { labels.contains($0) }
    }

    private static func hasPreserveAvoidContradiction(preserve: [String], avoid: [String]) -> Bool {
        let preserveKeys = Set(preserve.map(normalizedIssueKey).filter { !$0.isEmpty })
        let avoidKeys = Set(avoid.map(normalizedIssueKey).filter { !$0.isEmpty })
        return !preserveKeys.intersection(avoidKeys).isEmpty
    }

    private static func isIncompleteResolvedPhrase(_ value: String) -> Bool {
        lensLooksLikeIncompleteProductionPhrase(value)
    }

    private static func containsProvenancePhrase(_ value: String) -> Bool {
        lensContainsProvenancePhrase(value)
    }

    private static func compositionHasOnlyUseCases(_ values: [String]) -> Bool {
        let clean = uniqueNonEmpty(values).map { $0.lowercased() }
        guard !clean.isEmpty else { return false }
        return clean.allSatisfy { value in
            lensContainsAnyToken(
                value,
                [
                    "website landing",
                    "landing visuals",
                    "product cards",
                    "social posts",
                    "education cards",
                    "style handoff",
                    "prompt grounding",
                    "image prompts",
                    "poster concepts",
                    "deliverable"
                ]
            )
        }
    }

    private static func looksLikeRawScrapedProse(_ value: String) -> Bool {
        lensLooksLikeRawScrapedProse(value)
    }

    private static func normalizedIssueKey(_ value: String) -> String {
        lensNormalizedIssueKey(value)
    }
}

private extension LensBody {
    func normalizedForReadiness() -> LensBody {
        normalized()
    }
}

struct LensRelationSummary: Codable, Hashable {
    var storylineCount: Int = 0
    var beatBoardCount: Int = 0
    var projectStoryCount: Int = 0
    var sceneWorkspaceCount: Int = 0
    var sceneAssetCount: Int = 0
    var audioTrackCount: Int = 0
    var updatedAt: String = ""

    static let empty = LensRelationSummary()

    var hasDownstreamUsage: Bool {
        storylineCount > 0
            || beatBoardCount > 0
            || projectStoryCount > 0
            || sceneWorkspaceCount > 0
            || sceneAssetCount > 0
            || audioTrackCount > 0
    }

    var badgeText: String {
        if !hasDownstreamUsage { return "No downstream usage" }
        var parts: [String] = []
        if storylineCount > 0 { parts.append("Used by \(storylineCount) Storyline\(storylineCount == 1 ? "" : "s")") }
        if beatBoardCount > 0 { parts.append("Used by \(beatBoardCount) Beat Board\(beatBoardCount == 1 ? "" : "s")") }
        if sceneAssetCount > 0 { parts.append("Used by \(sceneAssetCount) Scene Asset\(sceneAssetCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}

struct LensRowSnapshot: Codable, Hashable, Identifiable {
    var lensId: String
    var lensTitle: String
    var lensStatusAtGeneration: ProjectLensStatus
    var ingredientId: String
    var ingredientTitle: String
    var narrativeUse: String
    var presentationUse: String
    var paletteTerms: [String]
    var motifTerms: [String]
    var avoidTerms: [String]
    var sourceAestheticIds: [String]
    var sourceRecipeId: String?
    var sourceRecipeVersion: String?
    var snapshotHash: String

    var id: String {
        snapshotHash
    }

    static func make(lens: ProjectLens, ingredient: LensStyleIngredient) -> LensRowSnapshot {
        let seed = LensRowSnapshotSeed(
            lensId: lens.lensId,
            lensTitle: lens.body.title,
            lensStatusAtGeneration: lens.status.rawValue,
            ingredientId: ingredient.ingredientId,
            ingredientTitle: ingredient.title,
            narrativeUse: ingredient.narrativeUse,
            presentationUse: ingredient.presentationUse,
            paletteTerms: ingredient.paletteTerms,
            motifTerms: ingredient.motifTerms,
            avoidTerms: ingredient.avoidTerms,
            sourceAestheticIds: ingredient.referenceAestheticIds,
            sourceRecipeId: ingredient.sourceRecipeId ?? "",
            sourceRecipeVersion: ingredient.sourceRecipeVersion ?? ""
        )
        return LensRowSnapshot(
            lensId: seed.lensId,
            lensTitle: seed.lensTitle,
            lensStatusAtGeneration: lens.status,
            ingredientId: seed.ingredientId,
            ingredientTitle: seed.ingredientTitle,
            narrativeUse: seed.narrativeUse,
            presentationUse: seed.presentationUse,
            paletteTerms: seed.paletteTerms,
            motifTerms: seed.motifTerms,
            avoidTerms: seed.avoidTerms,
            sourceAestheticIds: seed.sourceAestheticIds,
            sourceRecipeId: ingredient.sourceRecipeId,
            sourceRecipeVersion: ingredient.sourceRecipeVersion,
            snapshotHash: stableHash(seed)
        )
    }
}

enum LensGeneratedSubjectKind: String, Codable, Hashable {
    case scene
    case character
    case object
}

enum LensCanonRoleCandidate: String, Codable, Hashable {
    case plate
    case actor
    case prop
    case style
    case shot
}

struct LensStageEligibility: Codable, Hashable {
    var canBecomePlate: Bool = false
    var canBecomeActor: Bool = false
    var canBecomeProp: Bool = false
    var canBecomeStyleAuthority: Bool = false

    var isEmpty: Bool {
        !canBecomePlate && !canBecomeActor && !canBecomeProp && !canBecomeStyleAuthority
    }
}

struct LensGeneratedSubject: Codable, Hashable {
    var kind: LensGeneratedSubjectKind = .scene
    var description: String = ""
    var canonRoleCandidate: LensCanonRoleCandidate?
    var stageEligibility: LensStageEligibility?

    func normalized() -> LensGeneratedSubject {
        var value = self
        value.description = value.description.trimmed
        if value.stageEligibility?.isEmpty == true {
            value.stageEligibility = nil
        }
        return value
    }
}

enum LensStyleAuthoritySource: String, Codable, Hashable {
    case sref
    case styleCatalog = "style_catalog"
    case uploadedReference = "uploaded_reference"
    case unknown
}

struct LensStyleAuthoritySnapshot: Codable, Hashable, Identifiable {
    var authorityId: String
    var id: String { authorityId }
    var role: String = "primary"
    var source: LensStyleAuthoritySource = .unknown
    var referenceId: String = ""
    var sourceReferenceId: String = ""
    var title: String = ""
    var imageUrl: String = ""
    var imagePath: String = ""
    var oneLineStyleSummary: String = ""
    var weight: Int?

    func normalized(order: Int? = nil) -> LensStyleAuthoritySnapshot {
        var value = self
        value.role = value.role.trimmed.isEmpty ? "primary" : value.role.trimmed.lowercased()
        value.referenceId = value.referenceId.trimmed
        value.sourceReferenceId = value.sourceReferenceId.trimmed
        value.title = value.title.trimmed
        value.imageUrl = value.imageUrl.trimmed
        value.imagePath = value.imagePath.trimmed
        value.oneLineStyleSummary = value.oneLineStyleSummary.trimmed
        if let weight = value.weight {
            value.weight = min(100, max(0, weight))
        }
        value.authorityId = value.authorityId.trimmed
        if value.authorityId.isEmpty {
            let fallbackOrder = order ?? 0
            value.authorityId = "style_authority_\(shortHash("\(value.role):\(value.referenceId):\(value.sourceReferenceId):\(fallbackOrder)", length: 12))"
        }
        return value
    }
}

struct LensRenderRecipeParameter: Codable, Hashable, Identifiable, Sendable {
    var key: String
    var value: String
    var valueType: String = "string"
    var id: String { key }

    func normalized() -> LensRenderRecipeParameter {
        var value = self
        value.key = value.key.trimmed
        value.value = value.value.trimmed
        value.valueType = value.valueType.trimmed.isEmpty ? "string" : value.valueType.trimmed
        return value
    }
}

struct LensRenderRecipeSnapshot: Codable, Hashable, Sendable {
    var label: String = ""
    var provider: String = ""
    var model: String = ""
    var stackId: String?
    var parameters: [LensRenderRecipeParameter] = []
    var capabilities: [String] = []

    static func legacy(provider: String, model: String, label: String = "") -> LensRenderRecipeSnapshot {
        LensRenderRecipeSnapshot(
            label: label.trimmed.isEmpty ? provider.capitalized : label,
            provider: provider,
            model: model,
            stackId: nil,
            parameters: [],
            capabilities: []
        ).normalized()
    }

    func normalized() -> LensRenderRecipeSnapshot {
        var value = self
        value.label = value.label.trimmed
        value.provider = value.provider.trimmed.lowercased()
        value.model = value.model.trimmed
        value.stackId = value.stackId?.trimmed.nilIfEmpty
        value.parameters = value.parameters
            .map { $0.normalized() }
            .filter { !$0.key.isEmpty }
        value.capabilities = uniqueNonEmpty(value.capabilities.map { $0.trimmed })
        if value.label.isEmpty {
            value.label = value.provider.isEmpty ? "Render Recipe" : value.provider.capitalized
        }
        return value
    }
}

struct LensRenderVersionMetadata: Codable, Hashable, Sendable {
    var renderVersionId: String = ""
    var renderTargetId: String = ""
    var renderStackFingerprint: String = ""
    var renderVersionGroupId: String = ""
    var versionNumber: Int = 0
    var seed: String = ""
    var finalPromptFingerprint: String = ""
    var renderParamsFingerprint: String = ""
    var isActive: Bool = false

    func normalized() -> LensRenderVersionMetadata {
        var value = self
        value.renderVersionId = value.renderVersionId.trimmed
        value.renderTargetId = value.renderTargetId.trimmed
        value.renderStackFingerprint = value.renderStackFingerprint.trimmed
        value.renderVersionGroupId = value.renderVersionGroupId.trimmed
        value.versionNumber = max(0, value.versionNumber)
        value.seed = value.seed.trimmed
        value.finalPromptFingerprint = value.finalPromptFingerprint.trimmed
        value.renderParamsFingerprint = value.renderParamsFingerprint.trimmed
        return value
    }
}

enum LensRenderStyleMode: String, Codable, Hashable, CaseIterable, Identifiable, Sendable {
    case none = "none"
    case describeStyleInPrompt = "describe_style_in_prompt"
    case attachStyleImage = "attach_style_image"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "No style"
        case .describeStyleInPrompt: "Describe style in prompt"
        case .attachStyleImage: "Attach style image directly"
        }
    }

    var shortLabel: String {
        switch self {
        case .none: "No style"
        case .describeStyleInPrompt: "Describe"
        case .attachStyleImage: "Attach"
        }
    }
}

struct LensTakeRenderRequest: Codable, Hashable, Sendable {
    var stack: RenderStack
    var styleMode: LensRenderStyleMode = .describeStyleInPrompt
    var debugParametersJSON: String = ""

    func normalized() -> LensTakeRenderRequest {
        var value = self
        value.debugParametersJSON = value.debugParametersJSON.trimmed
        return value
    }
}

enum LensPromptImageAttachmentSource: String, Codable, Hashable, Sendable {
    case moodboardImage = "moodboard_image"
    case lensRenderVersion = "lens_render_version"
}

struct LensPromptImageAttachment: Codable, Hashable, Identifiable, Sendable {
    var attachmentId: String = ""
    var id: String { attachmentId }
    var source: LensPromptImageAttachmentSource = .moodboardImage
    var sourceId: String = ""
    var label: String = ""
    var detail: String = ""
    var imagePath: String = ""

    func normalized() -> LensPromptImageAttachment {
        var value = self
        value.attachmentId = value.attachmentId.trimmed
        value.sourceId = value.sourceId.trimmed
        value.label = value.label.trimmed
        value.detail = value.detail.trimmed
        value.imagePath = value.imagePath.trimmed
        if value.attachmentId.isEmpty {
            value.attachmentId = "prompt_image_\(shortHash("\(value.source.rawValue):\(value.sourceId):\(value.imagePath)", length: 12))"
        }
        return value
    }
}

enum LensReframeMetrics {
    /// The reticle and generation crop are 16:9 so the zoom selection matches
    /// the wide frames the render stacks produce.
    static let reticleAspect: CGFloat = 16.0 / 9.0
    /// Base WIDTH of the click-focus reticle, in source-image pixels (height is
    /// width ÷ reticleAspect). The corner grip grows it from here.
    static let reticleEdgePixels: CGFloat = 160
    /// The generation crop expands the reticle by this factor for surrounding context.
    static let cropContextScale: CGFloat = 2.0
    /// Reticle rotation is clamped to ±45°; beyond that the selection reads as
    /// portrait and the straightened 16:9 output stops matching intent.
    static let reticleMaxRotationDegrees: Double = 45
    /// Hygiene snap in `normalized()`: angles this close to level are level.
    static let reticleRotationZeroSnapDegrees: Double = 0.5
    /// Interactive magnetic zero — releasing the handle near upright lands level.
    static let reticleRotationMagneticSnapDegrees: Double = 1.5
    /// Shift-drag rotation detents.
    static let reticleRotationDetentDegrees: Double = 15
    /// Rotated crops keep this many source pixels off the image edge so the
    /// straightened render never interpolates past the bitmap.
    static let reticleRotatedEdgeInsetPixels: CGFloat = 1
    static let zoomOutDefaultSourceScale = 0.75
    /// Slider floor. Below ~35% the surviving source is too small a subject
    /// and even chained passes are dominated by invention.
    static let zoomOutMinimumSelectableSourceScale = 0.35
    static let zoomOutMaximumSelectableSourceScale = 0.75
    /// Spec-clamp floor kept at the historical minimum so persisted 10-30%
    /// artifacts keep decoding and rendering with their original geometry.
    static let zoomOutMinimumSourceScale = 0.10
    static let zoomOutLegacyMaximumSourceScale = 0.85
    static let zoomOutSourceScaleStep = 0.05
}

/// "Don't make me think" zoom fidelity: how much surrounding context the
/// generation crop keeps and how strictly the prompt holds the crop.
/// TIGHT = crop-true recompose, TRUE = the historical balanced behavior,
/// WIDE = creative latitude.
enum LensReframeFidelity: String, Codable, CaseIterable, Hashable, Sendable {
    case tight
    case balanced = "true"
    case wide

    static let fallback: LensReframeFidelity = .balanced

    var label: String {
        switch self {
        case .tight: return "TIGHT"
        case .balanced: return "TRUE"
        case .wide: return "WIDE"
        }
    }

    var help: String {
        switch self {
        case .tight: return "Crop-true: the result is exactly the selected region recomposed as the full image."
        case .balanced: return "Balanced: the selection leads, with some surrounding context kept."
        case .wide: return "Creative: the selection anchors the image but the model may widen for context."
        }
    }

    /// How far the generation crop expands beyond the reticle.
    var contextScale: CGFloat {
        switch self {
        case .tight: return 1.3
        case .balanced: return LensReframeMetrics.cropContextScale
        case .wide: return 3.0
        }
    }

    /// Fidelity sentence appended to the reframe prompt body ("" for balanced —
    /// the historical prompt already reads balanced).
    var promptLine: String {
        switch self {
        case .tight:
            return "Zoom fidelity: strict. The result is exactly the focus crop recomposed as the full image — hold its composition and framing; do not pull back, widen, or reinvent the scene."
        case .balanced:
            return ""
        case .wide:
            return "Zoom fidelity: loose. Let the focus region lead, but you may widen beyond it where that strengthens the composition."
        }
    }

    static func normalized(_ raw: String?) -> LensReframeFidelity {
        guard let raw = raw?.trimmed.lowercased(), !raw.isEmpty else { return fallback }
        return LensReframeFidelity(rawValue: raw) ?? fallback
    }
}

struct LensReframeSpec: Codable, Hashable, Sendable {
    static let zoomMode = "zoom"
    static let zoomOutMode = "zoom_out"
    static let viewpointMode = "viewpoint"
    static let observerZoomMode = "observer_zoom"
    static let characterPOVMode = "character_pov"

    var mode: String = LensReframeSpec.zoomMode
    var centerX: Double = 0.5
    var centerY: Double = 0.5
    var normalizedWidth: Double = 0
    var normalizedHeight: Double = 0
    var viewDirection: String = LensReframeViewDirection.north.rawValue
    var parentImageId: String = ""
    var parentRenderVersionId: String = ""
    var characterId: String = ""
    var characterName: String = ""
    var characterPrompt: String = ""
    /// Raw LensReframeFidelity value; tolerant — unknown normalizes to balanced.
    var fidelity: String = LensReframeFidelity.fallback.rawValue
    /// Reticle tilt in degrees, clockwise-positive in image space (top-left
    /// origin). The generated frame straightens the selection: its top edge
    /// becomes the output's top. Zoom + viewpoint only; zoom_out forces 0.
    var rotationDegrees: Double = 0
    /// Viewpoint only: ride a locally-drawn top-down camera-map schematic to
    /// the model alongside the source attachments. Defaults on; tolerant —
    /// absent decodes true. When the map fails to write, the engine flips
    /// this false on the persisted spec so descriptors stay truthful.
    var includeCameraMap: Bool = true

    var resolvedFidelity: LensReframeFidelity {
        LensReframeFidelity.normalized(fidelity)
    }

    var isZoom: Bool { mode == LensReframeSpec.zoomMode }
    var isZoomOut: Bool { mode == LensReframeSpec.zoomOutMode }
    var isViewpoint: Bool { mode == LensReframeSpec.viewpointMode }
    var isCharacterPOV: Bool { isViewpoint }

    var resolvedViewDirection: LensReframeViewDirection {
        LensReframeViewDirection.normalized(viewDirection)
    }

    var modeLabel: String {
        if isZoomOut {
            return "Zoom Out"
        }
        if isViewpoint {
            return characterName.isEmpty ? "Viewpoint" : "\(characterName) Viewpoint"
        }
        return "Zoom In"
    }

    var zoomOutSourceScale: Double {
        guard isZoomOut else { return 1 }
        return min(
            LensReframeMetrics.zoomOutLegacyMaximumSourceScale,
            max(LensReframeMetrics.zoomOutMinimumSourceScale, normalizedWidth)
        )
    }

    var zoomOutAmount: Double {
        1 - zoomOutSourceScale
    }

    var zoomOutSourceRect: CGRect {
        guard isZoomOut else { return .zero }
        let scale = zoomOutSourceScale
        return CGRect(
            x: centerX - scale / 2,
            y: centerY - scale / 2,
            width: scale,
            height: scale
        )
    }

    init(
        mode: String = LensReframeSpec.zoomMode,
        centerX: Double = 0.5,
        centerY: Double = 0.5,
        normalizedWidth: Double = 0,
        normalizedHeight: Double = 0,
        viewDirection: String = LensReframeViewDirection.north.rawValue,
        parentImageId: String = "",
        parentRenderVersionId: String = "",
        characterId: String = "",
        characterName: String = "",
        characterPrompt: String = "",
        fidelity: String = LensReframeFidelity.fallback.rawValue,
        rotationDegrees: Double = 0,
        includeCameraMap: Bool = true
    ) {
        self.mode = mode
        self.centerX = centerX
        self.centerY = centerY
        self.normalizedWidth = normalizedWidth
        self.normalizedHeight = normalizedHeight
        self.viewDirection = viewDirection
        self.parentImageId = parentImageId
        self.parentRenderVersionId = parentRenderVersionId
        self.characterId = characterId
        self.characterName = characterName
        self.characterPrompt = characterPrompt
        self.fidelity = fidelity
        self.rotationDegrees = rotationDegrees
        self.includeCameraMap = includeCameraMap
    }

    func normalized() -> LensReframeSpec {
        var value = self
        value.mode = LensReframeSpec.normalizedMode(value.mode)
        value.centerX = min(1, max(0, value.centerX))
        value.centerY = min(1, max(0, value.centerY))
        value.normalizedWidth = min(1, max(0, value.normalizedWidth))
        value.normalizedHeight = min(1, max(0, value.normalizedHeight))
        if value.mode == LensReframeSpec.zoomOutMode {
            let requestedScale = value.normalizedWidth > 0
                ? value.normalizedWidth
                : (value.normalizedHeight > 0
                    ? value.normalizedHeight
                    : LensReframeMetrics.zoomOutDefaultSourceScale)
            let scale = min(
                LensReframeMetrics.zoomOutLegacyMaximumSourceScale,
                max(LensReframeMetrics.zoomOutMinimumSourceScale, requestedScale)
            )
            value.normalizedWidth = scale
            value.normalizedHeight = scale
            value.centerX = min(1 - scale / 2, max(scale / 2, value.centerX))
            value.centerY = min(1 - scale / 2, max(scale / 2, value.centerY))
        }
        value.viewDirection = LensReframeViewDirection.normalized(value.viewDirection).rawValue
        value.parentImageId = value.parentImageId.trimmed
        value.parentRenderVersionId = value.parentRenderVersionId.trimmed
        value.characterId = value.characterId.trimmed
        value.characterName = value.characterName.trimmed
        value.characterPrompt = value.characterPrompt.trimmed
        value.fidelity = LensReframeFidelity.normalized(value.fidelity).rawValue
        value.rotationDegrees = min(
            LensReframeMetrics.reticleMaxRotationDegrees,
            max(-LensReframeMetrics.reticleMaxRotationDegrees, value.rotationDegrees)
        )
        if !value.rotationDegrees.isFinite
            || abs(value.rotationDegrees) < LensReframeMetrics.reticleRotationZeroSnapDegrees
            || value.mode == LensReframeSpec.zoomOutMode {
            value.rotationDegrees = 0
        }
        return value
    }

    static func normalizedMode(_ rawMode: String) -> String {
        switch rawMode.trimmed {
        case LensReframeSpec.zoomOutMode:
            return LensReframeSpec.zoomOutMode
        case LensReframeSpec.viewpointMode, LensReframeSpec.characterPOVMode:
            return LensReframeSpec.viewpointMode
        case LensReframeSpec.zoomMode, LensReframeSpec.observerZoomMode:
            return LensReframeSpec.zoomMode
        default:
            return LensReframeSpec.zoomMode
        }
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case centerX
        case centerY
        case normalizedWidth
        case normalizedHeight
        case viewDirection
        case parentImageId
        case parentRenderVersionId
        case characterId
        case characterName
        case characterPrompt
        case fidelity
        case rotationDegrees
        case includeCameraMap
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? LensReframeSpec.zoomMode
        centerX = try container.decodeIfPresent(Double.self, forKey: .centerX) ?? 0.5
        centerY = try container.decodeIfPresent(Double.self, forKey: .centerY) ?? 0.5
        normalizedWidth = try container.decodeIfPresent(Double.self, forKey: .normalizedWidth) ?? 0
        normalizedHeight = try container.decodeIfPresent(Double.self, forKey: .normalizedHeight) ?? 0
        viewDirection = try container.decodeIfPresent(String.self, forKey: .viewDirection) ?? LensReframeViewDirection.north.rawValue
        parentImageId = try container.decodeIfPresent(String.self, forKey: .parentImageId) ?? ""
        parentRenderVersionId = try container.decodeIfPresent(String.self, forKey: .parentRenderVersionId) ?? ""
        characterId = try container.decodeIfPresent(String.self, forKey: .characterId) ?? ""
        characterName = try container.decodeIfPresent(String.self, forKey: .characterName) ?? ""
        characterPrompt = try container.decodeIfPresent(String.self, forKey: .characterPrompt) ?? ""
        fidelity = try container.decodeIfPresent(String.self, forKey: .fidelity) ?? LensReframeFidelity.fallback.rawValue
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        includeCameraMap = try container.decodeIfPresent(Bool.self, forKey: .includeCameraMap) ?? true
        self = normalized()
    }
}

enum LensReframeViewDirection: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case northwest
    case north
    case northeast
    case west
    case east
    case southwest
    case south
    case southeast

    var id: String { rawValue }

    var label: String {
        switch self {
        case .northwest: "Up left"
        case .north: "Up"
        case .northeast: "Up right"
        case .west: "Left"
        case .east: "Right"
        case .southwest: "Down left"
        case .south: "Down"
        case .southeast: "Down right"
        }
    }

    var promptPhrase: String {
        switch self {
        case .northwest: "toward the upper-left of the source frame"
        case .north: "toward the top of the source frame"
        case .northeast: "toward the upper-right of the source frame"
        case .west: "toward the left side of the source frame"
        case .east: "toward the right side of the source frame"
        case .southwest: "toward the lower-left of the source frame"
        case .south: "toward the bottom of the source frame"
        case .southeast: "toward the lower-right of the source frame"
        }
    }

    var systemImage: String {
        switch self {
        case .northwest: "arrow.up.left"
        case .north: "arrow.up"
        case .northeast: "arrow.up.right"
        case .west: "arrow.left"
        case .east: "arrow.right"
        case .southwest: "arrow.down.left"
        case .south: "arrow.down"
        case .southeast: "arrow.down.right"
        }
    }

    static func normalized(_ value: String) -> LensReframeViewDirection {
        LensReframeViewDirection(rawValue: value.trimmed) ?? .north
    }
}

/// Normalized (0-1, top-left origin) reticle square centered on the click, pinned inside the frame.
/// `edgePixels` is the source-pixel edge length; it is clamped so the reticle never shrinks below
/// the base size and never exceeds the shorter image dimension (keeping it square on screen).
/// The normalized (0–1, top-left) 16:9 focus reticle. `edgePixels` is the
/// reticle WIDTH in source pixels; height is width ÷ reticleAspect. Width is
/// floored at the base and capped so the rectangle fits inside the image.
func lensReframeFocusRect(
    center: CGPoint,
    imagePixelSize: CGSize,
    edgePixels: CGFloat = LensReframeMetrics.reticleEdgePixels,
    rotationDegrees: Double = 0
) -> CGRect {
    guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return .zero }
    let aspect = LensReframeMetrics.reticleAspect
    let maxWidth = lensReframeMaxWidthPixels(
        imagePixelSize: imagePixelSize,
        rotationDegrees: rotationDegrees
    )
    let widthPixels = min(max(edgePixels, LensReframeMetrics.reticleEdgePixels), maxWidth)
    let heightPixels = widthPixels / aspect
    let width = min(1, widthPixels / imagePixelSize.width)
    let height = min(1, heightPixels / imagePixelSize.height)
    // Pin the center by the ROTATED selection's bounding box so every corner of
    // the tilted rectangle stays inside the image (reduces to width/2 × height/2
    // when level).
    let factors = lensReframeRotatedAABBFactors(rotationDegrees: rotationDegrees)
    let inset = lensReframeRotatedEdgeInset(rotationDegrees: rotationDegrees)
    let halfX = (widthPixels * factors.x / 2 + inset) / imagePixelSize.width
    let halfY = (widthPixels * factors.y / 2 + inset) / imagePixelSize.height
    let centerX = min(max(center.x, halfX), 1 - halfX)
    let centerY = min(max(center.y, halfY), 1 - halfY)
    return CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
}

/// Pixel-space (top-left origin) 16:9 crop around the reticle, expanded for
/// context and pinned inside the frame. Matches the wide render output aspect.
/// The rect is the crop's UNROTATED footprint; with `spec.rotationDegrees` the
/// actual crop is this rect rotated about its center, and the width cap keeps
/// that tilted crop fully inside the image (the effective context scale is
/// "as much of the fidelity scale as fits" — the reticle itself always fits).
func lensReframeCropRect(
    imagePixelSize: CGSize,
    spec: LensReframeSpec,
    contextScale: CGFloat? = nil
) -> CGRect {
    guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return .zero }
    let aspect = LensReframeMetrics.reticleAspect
    // Context expansion follows the spec's zoom fidelity unless explicitly overridden.
    let resolvedScale = contextScale ?? spec.resolvedFidelity.contextScale
    // The reticle width follows the spec's selection (normalizedWidth is the
    // width fraction, driving axis for both new 16:9 specs and legacy square
    // ones), never dropping below the base reticle.
    let reticleWidth = max(
        LensReframeMetrics.reticleEdgePixels,
        CGFloat(spec.normalizedWidth) * imagePixelSize.width
    )
    let rotationDegrees = spec.rotationDegrees
    let maxWidth = lensReframeMaxWidthPixels(
        imagePixelSize: imagePixelSize,
        rotationDegrees: rotationDegrees
    )
    let cropWidth = min(reticleWidth * max(1, resolvedScale), maxWidth)
    let cropHeight = cropWidth / aspect
    let factors = lensReframeRotatedAABBFactors(rotationDegrees: rotationDegrees)
    let inset = lensReframeRotatedEdgeInset(rotationDegrees: rotationDegrees)
    let halfX = cropWidth * factors.x / 2 + inset
    let halfY = cropWidth * factors.y / 2 + inset
    let centerX = min(max(CGFloat(spec.centerX) * imagePixelSize.width, halfX), imagePixelSize.width - halfX)
    let centerY = min(max(CGFloat(spec.centerY) * imagePixelSize.height, halfY), imagePixelSize.height - halfY)
    let rect = CGRect(x: centerX - cropWidth / 2, y: centerY - cropHeight / 2, width: cropWidth, height: cropHeight)
    // `.integral` predates rotation and keeps historical level crops
    // byte-identical; a rotated footprint pushed to whole pixels could poke
    // its tilted corners past the safety inset, so it stays fractional.
    return rotationDegrees == 0 ? rect.integral : rect
}

/// Axis-aligned bounding-box factors of a 16:9 rect rotated about its center:
/// the AABB measures rectWidth × x by rectWidth × y.
private func lensReframeRotatedAABBFactors(rotationDegrees: Double) -> (x: CGFloat, y: CGFloat) {
    let aspect = LensReframeMetrics.reticleAspect
    let radians = CGFloat(rotationDegrees) * .pi / 180
    let cosA = abs(cos(radians))
    let sinA = abs(sin(radians))
    return (cosA + sinA / aspect, sinA + cosA / aspect)
}

private func lensReframeRotatedEdgeInset(rotationDegrees: Double) -> CGFloat {
    rotationDegrees == 0 ? 0 : LensReframeMetrics.reticleRotatedEdgeInsetPixels
}

/// Widest 16:9 rect (by its own width) whose rotated bounding box fits the
/// image, less the rotation safety inset. Reduces to min(W, H·aspect) level.
private func lensReframeMaxWidthPixels(imagePixelSize: CGSize, rotationDegrees: Double) -> CGFloat {
    let factors = lensReframeRotatedAABBFactors(rotationDegrees: rotationDegrees)
    let inset = lensReframeRotatedEdgeInset(rotationDegrees: rotationDegrees)
    let availableWidth = max(0, imagePixelSize.width - 2 * inset)
    let availableHeight = max(0, imagePixelSize.height - 2 * inset)
    return min(availableWidth / factors.x, availableHeight / factors.y)
}

/// Interactive rotation snapping for the reticle handle: Shift quantizes to
/// 15° detents; otherwise angles within the magnetic band land level. Always
/// clamped to the ±45° range.
func lensReframeSnappedRotation(rawDegrees: Double, shiftDown: Bool) -> Double {
    guard rawDegrees.isFinite else { return 0 }
    let limit = LensReframeMetrics.reticleMaxRotationDegrees
    let clamped = min(limit, max(-limit, rawDegrees))
    if shiftDown {
        let detent = LensReframeMetrics.reticleRotationDetentDegrees
        return (clamped / detent).rounded() * detent
    }
    if abs(clamped) < LensReframeMetrics.reticleRotationMagneticSnapDegrees {
        return 0
    }
    return clamped
}

/// Pixels of `cropRect` (top-left-origin image space) tilted `rotationDegrees`
/// clockwise about its center, returned STRAIGHTENED — the tilted rectangle's
/// top edge becomes the output's top. Level crops take the exact
/// `CGImage.cropping` path so historical outputs stay byte-identical.
func lensReframeExtractCrop(
    from image: CGImage,
    cropRect: CGRect,
    rotationDegrees: Double
) -> CGImage? {
    if abs(rotationDegrees) < 0.01 {
        return image.cropping(to: cropRect)
    }
    let outputWidth = Int(cropRect.width.rounded())
    let outputHeight = Int(cropRect.height.rounded())
    guard outputWidth > 0, outputHeight > 0,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: outputWidth,
              height: outputHeight,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return nil
    }
    context.interpolationQuality = .high
    // The context is y-up while the crop is stated y-down, so the selection's
    // image-space clockwise tilt appears counterclockwise here and rotating by
    // +θ straightens it: center the output, undo the tilt, then move the crop
    // center (converted to y-up) to the origin and draw the full source 1:1.
    let radians = CGFloat(rotationDegrees) * .pi / 180
    context.translateBy(x: CGFloat(outputWidth) / 2, y: CGFloat(outputHeight) / 2)
    context.rotate(by: radians)
    context.translateBy(
        x: -cropRect.midX,
        y: -(CGFloat(image.height) - cropRect.midY)
    )
    context.draw(
        image,
        in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
    )
    return context.makeImage()
}

struct ReframePromptTemplate: Codable, Hashable, Identifiable, Sendable {
    static let workflowName = "reframe"

    var templateId: String = ""
    var workflow: String = ReframePromptTemplate.workflowName
    var mode: String = LensReframeSpec.zoomMode
    /// Empty means the mode-level fallback used when no exact model template exists.
    var model: String = ""
    var title: String = ""
    var body: String = ""
    var updatedAt: String = ""

    var id: String { templateId }
    var isFallback: Bool { model.trimmed.isEmpty }

    func normalized(order: Int = 0) -> ReframePromptTemplate {
        var value = self
        value.workflow = value.workflow.trimmed.isEmpty ? ReframePromptTemplate.workflowName : value.workflow.trimmed
        value.mode = LensReframeSpec.normalizedMode(value.mode)
        value.model = value.model.trimmed
        value.title = value.title.trimmed
        value.body = value.body.trimmed
        value.updatedAt = value.updatedAt.trimmed
        if value.templateId.trimmed.isEmpty {
            let modelKey = value.model.isEmpty ? "fallback" : value.model
            value.templateId = "\(value.workflow):\(value.mode):\(modelKey)"
        } else {
            value.templateId = value.templateId.trimmed
        }
        if value.title.isEmpty {
            value.title = value.model.isEmpty ? "\(value.mode.capitalized) fallback" : value.model
        }
        if value.body.isEmpty {
            value.body = ProjectPromptSettingsDocument.builtInTemplate(
                mode: value.mode,
                model: value.model
            ).body
        }
        return value
    }
}

struct ProjectPromptSettingsDocument: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.project_prompt_settings.v0.1"

    var schemaVersion: String = ProjectPromptSettingsDocument.schemaVersion
    var projectId: String = ""
    var reframePrompts: [ReframePromptTemplate] = ProjectPromptSettingsDocument.builtInReframeTemplates()
    var characterSheetPrompts: [CharacterSheetPromptTemplate] = ProjectPromptSettingsDocument.builtInCharacterSheetTemplates()
    var updatedAt: String = DateFormats.now()

    // Keys stay camelCase: the house coder converts to and from snake_case itself,
    // so a raw snake_case key never matches after that conversion — the stored
    // document then decoded as empty and every saved prompt edit vanished on relaunch.
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case reframePrompts
        case characterSheetPrompts
        case updatedAt
    }

    init(
        schemaVersion: String = ProjectPromptSettingsDocument.schemaVersion,
        projectId: String = "",
        reframePrompts: [ReframePromptTemplate] = ProjectPromptSettingsDocument.builtInReframeTemplates(),
        characterSheetPrompts: [CharacterSheetPromptTemplate] = ProjectPromptSettingsDocument.builtInCharacterSheetTemplates(),
        updatedAt: String = DateFormats.now()
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.reframePrompts = reframePrompts
        self.characterSheetPrompts = characterSheetPrompts
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        reframePrompts = try container.decodeIfPresent([ReframePromptTemplate].self, forKey: .reframePrompts)
            ?? Self.builtInReframeTemplates()
        characterSheetPrompts = try container.decodeIfPresent([CharacterSheetPromptTemplate].self, forKey: .characterSheetPrompts)
            ?? Self.builtInCharacterSheetTemplates()
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
    }

    static func empty(projectId: String = "") -> ProjectPromptSettingsDocument {
        ProjectPromptSettingsDocument(projectId: projectId)
    }

    func normalized(projectId fallbackProjectId: String = "") -> ProjectPromptSettingsDocument {
        var value = self
        value.schemaVersion = ProjectPromptSettingsDocument.schemaVersion
        value.projectId = value.projectId.trimmed.nilIfEmpty ?? fallbackProjectId.trimmed
        value.updatedAt = value.updatedAt.trimmed.isEmpty ? DateFormats.now() : value.updatedAt.trimmed
        let normalizedPrompts = value.reframePrompts.enumerated().map { index, template in
            template.normalized(order: index)
        }
        var promptsByKey: [String: ReframePromptTemplate] = [:]
        for template in ProjectPromptSettingsDocument.builtInReframeTemplates() {
            let normalized = template.normalized()
            promptsByKey[ProjectPromptSettingsDocument.templateKey(mode: normalized.mode, model: normalized.model)] = normalized
        }
        for template in normalizedPrompts {
            let normalized = template.normalized()
            let key = ProjectPromptSettingsDocument.templateKey(mode: normalized.mode, model: normalized.model)
            // A stored body identical to a retired built-in is a stale saved
            // default, not an operator edit; the current built-in wins so
            // prompt repairs reach projects that once saved the settings sheet.
            if let retired = ProjectPromptSettingsDocument.retiredBuiltInBodies[key],
               retired.contains(normalized.body) {
                continue
            }
            promptsByKey[key] = normalized
        }
        value.reframePrompts = promptsByKey.values.sorted { lhs, rhs in
            let lhsSort = ProjectPromptSettingsDocument.sortKey(lhs)
            let rhsSort = ProjectPromptSettingsDocument.sortKey(rhs)
            return lhsSort < rhsSort
        }
        value.characterSheetPrompts = Self.normalizedCharacterSheetPrompts(value.characterSheetPrompts)
        return value
    }

    func reframeTemplate(mode rawMode: String, model rawModel: String) -> ReframePromptTemplate {
        let mode = LensReframeSpec.normalizedMode(rawMode)
        let model = rawModel.trimmed
        let normalized = normalized(projectId: projectId)
        if !model.isEmpty,
           let exact = normalized.reframePrompts.first(where: {
               $0.workflow == ReframePromptTemplate.workflowName && $0.mode == mode && $0.model == model
           }) {
            return exact
        }
        if let fallback = normalized.reframePrompts.first(where: {
            $0.workflow == ReframePromptTemplate.workflowName && $0.mode == mode && $0.model.isEmpty
        }) {
            return fallback
        }
        return ProjectPromptSettingsDocument.builtInTemplate(mode: mode, model: "")
    }

    static func builtInTemplate(mode rawMode: String, model rawModel: String) -> ReframePromptTemplate {
        let mode = LensReframeSpec.normalizedMode(rawMode)
        let model = rawModel.trimmed
        return builtInReframeTemplates().first {
            $0.mode == mode && $0.model == model
        } ?? builtInReframeTemplates().first {
            $0.mode == mode && $0.model.isEmpty
        } ?? builtInReframeTemplates()[0]
    }

    static func builtInReframeTemplates() -> [ReframePromptTemplate] {
        [
            ReframePromptTemplate(
                templateId: "reframe:zoom:fallback",
                mode: LensReframeSpec.zoomMode,
                model: "",
                title: "Zoom fallback",
                // Zoom bodies are deliberately terse: coordinates, extent, and
                // scene context already ride the attachment descriptors the
                // runner appends verbatim, so the editable body carries only
                // the instructions the operator might actually want to change.
                body: """
                Zoom in: the selected focus region becomes the entire new frame, edge-to-edge — match its framing and magnification exactly, never pulled back wider. {{focus_rotation_clause}}

                Same scene, same subjects, light, palette, and rendering style. Reveal finer detail naturally; add nothing foreign.
                """
            ),
            ReframePromptTemplate(
                templateId: "reframe:zoom:gpt-image-2",
                mode: LensReframeSpec.zoomMode,
                model: "gpt-image-2",
                title: "Zoom · GPT Image 2",
                body: """
                The new image IS the selected focus region, edge-to-edge — match its framing and magnification exactly, not a small detail and not pulled back wider. {{focus_rotation_clause}}

                Keep the scene's subjects, palette, lighting, and rendering style; sharpen and complete detail without inventing anything foreign.
                """
            ),
            ReframePromptTemplate(
                templateId: "reframe:zoom:fal-ai/flux-2-pro/edit",
                mode: LensReframeSpec.zoomMode,
                model: "fal-ai/flux-2-pro/edit",
                title: "Zoom · FLUX 2 Pro Edit",
                body: """
                Reframe: the selected focus region becomes the complete full-frame image at matching magnification. {{focus_rotation_clause}}

                Stay literal to the source — same environment, materials, lighting, palette, and style. Add only the natural detail a closer view reveals.
                """
            ),
            ReframePromptTemplate(
                templateId: "reframe:zoom:fal-ai/nano-banana-2/edit",
                mode: LensReframeSpec.zoomMode,
                model: "fal-ai/nano-banana-2/edit",
                title: "Zoom · Nano Banana 2 Edit",
                body: """
                Recompose the selected focus region as the entire new frame, holding its exact framing and magnification. {{focus_rotation_clause}}

                Same world, same light, same materials, same rendering style. Reveal plausible finer detail — no new objects, signage, or story events.
                """
            ),
            ReframePromptTemplate(
                templateId: "reframe:zoom_out:fallback",
                mode: LensReframeSpec.zoomOutMode,
                model: "",
                title: "Zoom Out fallback",
                body: """
                Zoom out to a wider view of this exact scene. Continue the scene past every edge of the source picture — same place, same moment, same perspective and horizon, same light, palette, materials, weather, and rendering style. Everything in the scene is already inside the source picture; the new area shows only the surrounding scenery, and the picture's edge stays invisible.

                Original scene context: {{original_scene_context}}
                """
            ),
            ReframePromptTemplate(
                templateId: "reframe:zoom_out:gpt-image-2",
                mode: LensReframeSpec.zoomOutMode,
                model: "gpt-image-2",
                title: "Zoom Out · GPT Image 2",
                body: """
                Zoom out to a wider camera view of this exact scene. The supplied picture is the middle of the new frame; fill the transparent surroundings by continuing the same scene past the picture's edges in every direction.

                One continuous image of one place: extend the ground, sky, structures, and terrain across the boundary with the same perspective and horizon line, the same light direction, palette, grain, and rendering style. Every person, creature, and distinct object is already inside the supplied picture, so the new area shows only the surrounding scenery and the picture's edge stays invisible.

                Original scene context: {{original_scene_context}}
                """
            ),
            ReframePromptTemplate(
                templateId: "reframe:zoom_out:fal-ai/image-apps-v2/outpaint",
                mode: LensReframeSpec.zoomOutMode,
                model: "fal-ai/image-apps-v2/outpaint",
                title: "Zoom Out · FAL Outpaint",
                // FAL Outpaint appends this text to its own outpaint
                // instruction as CONTENT. Scenery words only: naming a person
                // or creature paints a second copy of it into the expansion.
                body: """
                More of the same surroundings continuing in every direction.
                """
            ),
            ReframePromptTemplate(
                templateId: "reframe:viewpoint:fallback",
                mode: LensReframeSpec.viewpointMode,
                model: "",
                title: "Viewpoint fallback",
                body: """
                Viewpoint reframe from inside the source render. Place the camera at the selected point centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top, then look {{view_direction}}. {{focus_rotation_clause}}

                The output is a new camera angle from that point, not a crop of the original frame. Preserve source-world geography, time of day, weather, lighting, palette, and rendering style.{{character_context}}

                Original scene context: {{original_scene_context}}
                """
            ),
            ReframePromptTemplate(
                templateId: "reframe:viewpoint:gpt-image-2",
                mode: LensReframeSpec.viewpointMode,
                model: "gpt-image-2",
                title: "Viewpoint · GPT Image 2",
                body: """
                Move the camera into the source scene at the selected point centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top, then look {{view_direction}}. {{focus_rotation_clause}}

                Generate the scene from that new position with coherent local geography and consistent rendering style. Do not crop the original camera view. Preserve time of day, weather, lighting, palette, materials, and active subjects.{{character_context}}

                Original scene context: {{original_scene_context}}
                """
            ),
            ReframePromptTemplate(
                templateId: "reframe:viewpoint:fal-ai/flux-2-pro/edit",
                mode: LensReframeSpec.viewpointMode,
                model: "fal-ai/flux-2-pro/edit",
                title: "Viewpoint · FLUX 2 Pro Edit",
                body: """
                Edit the source into a new viewpoint. The camera begins at the clicked point centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top, looking {{view_direction}}. {{focus_rotation_clause}}

                Maintain the source scene's structure, lighting, materials, and style while changing the camera position. This should feel like a plausible shot taken from inside the same world.{{character_context}}

                Original scene context: {{original_scene_context}}
                """
            ),
            ReframePromptTemplate(
                templateId: "reframe:viewpoint:fal-ai/nano-banana-2/edit",
                mode: LensReframeSpec.viewpointMode,
                model: "fal-ai/nano-banana-2/edit",
                title: "Viewpoint · Nano Banana 2 Edit",
                body: """
                Create a semantic viewpoint shift from the source render. Put the camera at the selected point centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top, looking {{view_direction}}. {{focus_rotation_clause}}

                Keep object relationships, room/world geography, lighting direction, weather, palette, and style consistent. The image should be a new view from that origin point, with no contradictory props, text, or story action.{{character_context}}

                Original scene context: {{original_scene_context}}
                """
            )
        ].map { $0.normalized() }
    }

    private static func templateKey(mode rawMode: String, model rawModel: String) -> String {
        "\(LensReframeSpec.normalizedMode(rawMode))|\(rawModel.trimmed)"
    }

    /// Superseded built-in bodies, keyed like the live templates. Stored
    /// documents persist whole template lists, so projects that ever saved the
    /// prompt sheet would shadow repaired built-ins with these forever.
    static let retiredBuiltInBodies: [String: Set<String>] = {
        [
            templateKey(mode: LensReframeSpec.zoomOutMode, model: ""): [
                """
                Extend the source scene into the empty perimeter around the locked original frame. The original occupies {{source_scale_percent}}% of the result and is centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top. Generate only the surrounding {{zoom_out_percent}}% pull-back area: {{margin_left_percent}}% left, {{margin_right_percent}}% right, {{margin_top_percent}}% above, and {{margin_bottom_percent}}% below.

                Continue perspective, sight lines, geography, lighting, palette, materials, weather, depth, and rendering style naturally across every edge. Do not redraw, crop, cover, duplicate, border, or place a frame around the locked source.

                Original scene context: {{original_scene_context}}
                """,
                """
                Zoom out to a wider view of this exact scene. Continue the scene naturally past every edge of the source picture — same place, same moment, same perspective and horizon, same light, palette, materials, weather, and rendering style. Every subject and object appears exactly once; never draw a frame or border where the source picture ends.

                Original scene context: {{original_scene_context}}
                """
            ],
            templateKey(mode: LensReframeSpec.zoomOutMode, model: "gpt-image-2"): [
                """
                Outpaint the transparent masked perimeter around the locked source image. The protected source occupies {{source_scale_percent}}% of the result and is centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top. Fill only the new area beyond it: {{margin_left_percent}}% left, {{margin_right_percent}}% right, {{margin_top_percent}}% above, and {{margin_bottom_percent}}% below.

                Make the wider view a seamless continuation of the exact source: continue perspective, geometry, subjects, light direction, palette, materials, weather, depth, and rendering style. Do not alter, duplicate, cover, border, or reframe the protected source.

                Original scene context: {{original_scene_context}}
                """,
                """
                Zoom out to a wider camera view of this exact scene. The supplied picture is the middle of the new frame; fill the transparent surroundings by continuing the same scene past the picture's edges in every direction.

                One continuous image of one place: extend the ground, sky, structures, and objects across the boundary with the same perspective and horizon line, the same light direction, palette, grain, and rendering style. Every subject and object appears exactly once — never a second copy, and never a frame, border, or edge line where the picture ends.

                Original scene context: {{original_scene_context}}
                """
            ],
            templateKey(mode: LensReframeSpec.zoomOutMode, model: "fal-ai/image-apps-v2/outpaint"): [
                """
                Extend the source image outward into a coherent wider scene. The locked source occupies {{source_scale_percent}}% of the result and is centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top. Generate the new perimeter implied by these margins: {{margin_left_percent}}% left, {{margin_right_percent}}% right, {{margin_top_percent}}% above, and {{margin_bottom_percent}}% below.

                Continue the source's perspective, world geography, subjects, lighting, palette, materials, weather, depth, and rendering style without seams. Generate only beyond the source; do not redraw, cover, duplicate, crop, or add a border around it.

                Original scene context: {{original_scene_context}}
                """,
                """
                A wider view of this exact scene: {{original_scene_context}}

                The camera pulls back to reveal more of the same place at the same moment. Continue the scenery naturally past every edge of the picture — same light, palette, weather, and rendering style throughout.
                """
            ],
            // Zoom bodies, two retired generations each: pre-rotation
            // (superseded when {{focus_rotation_clause}} joined
            // every reticle-bearing template) and the verbose rotation-era
            // bodies (superseded when coordinates and the inline
            // scene-context dump moved out of the editable body — the
            // attachment descriptors already carry both).
            templateKey(mode: LensReframeSpec.zoomMode, model: ""): [
                """
                Zoom reframe of the source render. The selected region is a 16:9 rectangle spanning {{focus_width_percent}}% of the source width and {{focus_height_percent}}% of its height, centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top. Make exactly that region become the entire new frame — the output framing matches the selection edge-to-edge.

                Preserve the same place, subjects, materials, weather, lighting, palette, and rendering style. Reveal finer detail naturally and do not add anything that contradicts the source.

                Original scene context: {{original_scene_context}}
                """,
                """
                Zoom reframe of the source render. The selected region is a 16:9 rectangle spanning {{focus_width_percent}}% of the source width and {{focus_height_percent}}% of its height, centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top. Make exactly that region become the entire new frame — the output framing matches the selection edge-to-edge. {{focus_rotation_clause}}

                Preserve the same place, subjects, materials, weather, lighting, palette, and rendering style. Reveal finer detail naturally and do not add anything that contradicts the source.

                Original scene context: {{original_scene_context}}
                """
            ],
            templateKey(mode: LensReframeSpec.zoomMode, model: "gpt-image-2"): [
                """
                Zoom into the selected source region. The selected region is a 16:9 rectangle spanning {{focus_width_percent}}% of the source width and {{focus_height_percent}}% of its height, centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top. The new image IS that rectangle, edge-to-edge — match its framing and magnification exactly, not as a small detail and not pulled back wider.

                Preserve source-world geography, recurring subjects, palette, lighting, material texture, and rendering style. Sharpen and complete visible detail without inventing foreign objects or changing the scene premise.

                Original scene context: {{original_scene_context}}
                """,
                """
                Zoom into the selected source region. The selected region is a 16:9 rectangle spanning {{focus_width_percent}}% of the source width and {{focus_height_percent}}% of its height, centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top. The new image IS that rectangle, edge-to-edge — match its framing and magnification exactly, not as a small detail and not pulled back wider. {{focus_rotation_clause}}

                Preserve source-world geography, recurring subjects, palette, lighting, material texture, and rendering style. Sharpen and complete visible detail without inventing foreign objects or changing the scene premise.

                Original scene context: {{original_scene_context}}
                """
            ],
            templateKey(mode: LensReframeSpec.zoomMode, model: "fal-ai/flux-2-pro/edit"): [
                """
                Professional edit reframe. The selected region is a 16:9 rectangle spanning {{focus_width_percent}}% of the source width and {{focus_height_percent}}% of its height, centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top. That exact rectangle becomes the complete full-frame image at matching magnification.

                Stay literal to the source reference. Keep the same subject placement logic, environment, materials, weather, lighting, palette, and style. Add only natural detail needed to make the closer view complete.

                Original scene context: {{original_scene_context}}
                """,
                """
                Professional edit reframe. The selected region is a 16:9 rectangle spanning {{focus_width_percent}}% of the source width and {{focus_height_percent}}% of its height, centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top. That exact rectangle becomes the complete full-frame image at matching magnification. {{focus_rotation_clause}}

                Stay literal to the source reference. Keep the same subject placement logic, environment, materials, weather, lighting, palette, and style. Add only natural detail needed to make the closer view complete.

                Original scene context: {{original_scene_context}}
                """
            ],
            templateKey(mode: LensReframeSpec.zoomMode, model: "fal-ai/nano-banana-2/edit"): [
                """
                Recompose the selected source detail as the entire new frame. The selected region is a 16:9 rectangle spanning {{focus_width_percent}}% of the source width and {{focus_height_percent}}% of its height, centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top — hold that exact framing and magnification.

                Keep all visible relationships semantically consistent with the source: same world, same local geography, same light, same materials, same rendering style. Reveal plausible finer detail, but avoid new story events, new signage, or contradictory objects.

                Original scene context: {{original_scene_context}}
                """,
                """
                Recompose the selected source detail as the entire new frame. The selected region is a 16:9 rectangle spanning {{focus_width_percent}}% of the source width and {{focus_height_percent}}% of its height, centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top — hold that exact framing and magnification. {{focus_rotation_clause}}

                Keep all visible relationships semantically consistent with the source: same world, same local geography, same light, same materials, same rendering style. Reveal plausible finer detail, but avoid new story events, new signage, or contradictory objects.

                Original scene context: {{original_scene_context}}
                """
            ],
            // Pre-rotation viewpoint bodies (superseded when
            // {{focus_rotation_clause}} joined every reticle-bearing template).
            templateKey(mode: LensReframeSpec.viewpointMode, model: ""): [
                """
                Viewpoint reframe from inside the source render. Place the camera at the selected point centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top, then look {{view_direction}}.

                The output is a new camera angle from that point, not a crop of the original frame. Preserve source-world geography, time of day, weather, lighting, palette, and rendering style.{{character_context}}

                Original scene context: {{original_scene_context}}
                """
            ],
            templateKey(mode: LensReframeSpec.viewpointMode, model: "gpt-image-2"): [
                """
                Move the camera into the source scene at the selected point centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top, then look {{view_direction}}.

                Generate the scene from that new position with coherent local geography and consistent rendering style. Do not crop the original camera view. Preserve time of day, weather, lighting, palette, materials, and active subjects.{{character_context}}

                Original scene context: {{original_scene_context}}
                """
            ],
            templateKey(mode: LensReframeSpec.viewpointMode, model: "fal-ai/flux-2-pro/edit"): [
                """
                Edit the source into a new viewpoint. The camera begins at the clicked point centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top, looking {{view_direction}}.

                Maintain the source scene's structure, lighting, materials, and style while changing the camera position. This should feel like a plausible shot taken from inside the same world.{{character_context}}

                Original scene context: {{original_scene_context}}
                """
            ],
            templateKey(mode: LensReframeSpec.viewpointMode, model: "fal-ai/nano-banana-2/edit"): [
                """
                Create a semantic viewpoint shift from the source render. Put the camera at the selected point centered {{focus_x_percent}}% from the left and {{focus_y_percent}}% from the top, looking {{view_direction}}.

                Keep object relationships, room/world geography, lighting direction, weather, palette, and style consistent. The image should be a new view from that origin point, with no contradictory props, text, or story action.{{character_context}}

                Original scene context: {{original_scene_context}}
                """
            ]
        ]
    }()

    private static func sortKey(_ template: ReframePromptTemplate) -> String {
        let modeRank: String
        switch template.mode {
        case LensReframeSpec.zoomMode: modeRank = "0"
        case LensReframeSpec.zoomOutMode: modeRank = "1"
        default: modeRank = "2"
        }
        let modelRank = template.model.isEmpty ? "0" : "1"
        return "\(modeRank)|\(modelRank)|\(template.title)|\(template.model)"
    }
}

/// A moodboard image chosen as a text-only influence on a take render. The
/// `line` is the compact analysis description injected verbatim into the
/// render prompt; `mediaId`/`label` are provenance only.
struct LensMoodInfluence: Codable, Hashable, Sendable {
    var mediaId: String = ""
    var label: String = ""
    var line: String = ""

    func normalized() -> LensMoodInfluence {
        var value = self
        value.mediaId = value.mediaId.trimmed
        value.label = value.label.trimmed
        value.line = value.line.trimmed
        return value
    }
}

/// "Don't make me think" medium presets for frame renders: one chip picks the
/// physical medium and injects its verbatim language into the final prompt
/// (outside enrichment, like mood influences).
enum LensMediumPreset: String, Codable, CaseIterable, Hashable, Sendable {
    case filmed
    case animated
    case illustrated
    case painted

    var label: String {
        switch self {
        case .filmed: return "FILMED"
        case .animated: return "ANIMATED"
        case .illustrated: return "ILLUSTRATED"
        case .painted: return "PAINTED"
        }
    }

    var promptBlock: String {
        switch self {
        case .filmed:
            return "Medium: a photographic live-action film still. Real optics and true lens depth of field, natural imperfect lighting, physically plausible materials and skin, subtle film grain, believable motion blur where movement exists. Not an illustration, not a 3D render, no painterly or stylized surfaces."
        case .animated:
            return "Medium: a frame from an animated feature. Deliberate shape language, clean silhouettes, coherent cel or painterly shading with intentional color design and simplified physically-consistent lighting. Not a photograph, not photorealistic."
        case .illustrated:
            return "Medium: a hand-drawn illustration. Visible linework and drawn textures, deliberate hatching or ink discipline, flat or limited-depth shading, printed-page character. Not a photograph, not a 3D render."
        case .painted:
            return "Medium: a painting. Visible brushwork and pigment texture, painterly edges that lose and find form, a coherent traditional palette and canvas or panel surface character. Not a photograph, not a digital-smooth render."
        }
    }
}

struct LensNewTakeRenderRequest: Codable, Hashable, Sendable {
    static let maxMoodInfluences = 3

    var stack: RenderStack
    var styleMode: LensRenderStyleMode = .describeStyleInPrompt
    var prompt: String = ""
    /// The raw editor text at submit, @mention tokens intact. `prompt` is the
    /// mention-cleaned render text; this persists into the take's sourcePrompt so
    /// re-opening the frame in the creator re-lights its mentions. Optional for
    /// tolerant decode of pre-field request blobs.
    var authoredPrompt: String?
    var label: String = ""
    var debugParametersJSON: String = ""
    var promptImageAttachment: LensPromptImageAttachment?
    var promptImageAttachments: [LensPromptImageAttachment]?
    var moodInfluences: [LensMoodInfluence]?
    /// Raw LensMediumPreset value; tolerant — unknown strings normalize to nil.
    var medium: String?
    var styleOverrideSlot: LensStyleTreatmentSlot?
    var styleOverrideCatalogVersion: String = ""
    var reframe: LensReframeSpec?
    var reframeFocusCropPath: String?
    /// The drawn top-down camera-map schematic for viewpoint reframes;
    /// optional for tolerant decode of pre-field request blobs.
    var reframeCameraMapPath: String?
    /// true = send the authored scene text VERBATIM — skip the LLM prompt
    /// rewrite (the deterministic segments still ride). nil/false = enabled.
    /// Optional for tolerant decode of pre-field request blobs.
    var promptEnrichmentDisabled: Bool?
    /// Per-render Stability reference fidelity (0 ≈ identical to the input
    /// image, 1 ≈ prompt only); nil = the stack default. Clamped on
    /// normalize; ignored by non-Stability stacks.
    var stabilityStrength: Double?

    var mediumPreset: LensMediumPreset? {
        medium.flatMap { LensMediumPreset(rawValue: $0) }
    }

    func normalized() -> LensNewTakeRenderRequest {
        var value = self
        value.prompt = value.prompt.trimmed
        value.authoredPrompt = value.authoredPrompt?.trimmed.nilIfEmpty
        value.label = value.label.trimmed
        value.debugParametersJSON = value.debugParametersJSON.trimmed
        value.promptImageAttachment = value.promptImageAttachment?.normalized()
        let normalizedAttachments = (value.promptImageAttachments ?? [])
            .map { $0.normalized() }
            .filter { !$0.imagePath.isEmpty }
        value.promptImageAttachments = normalizedAttachments.isEmpty ? nil : normalizedAttachments
        let normalizedMoods = (value.moodInfluences ?? [])
            .map { $0.normalized() }
            .filter { !$0.line.isEmpty }
            .prefix(Self.maxMoodInfluences)
        value.moodInfluences = normalizedMoods.isEmpty ? nil : Array(normalizedMoods)
        value.medium = value.medium.flatMap { LensMediumPreset(rawValue: $0.trimmed)?.rawValue }
        value.styleOverrideSlot = value.styleOverrideSlot?.normalized()
        value.styleOverrideCatalogVersion = value.styleOverrideCatalogVersion.trimmed
        value.reframe = value.reframe?.normalized()
        value.reframeFocusCropPath = value.reframeFocusCropPath?.trimmed.nilIfEmpty
        value.reframeCameraMapPath = value.reframeCameraMapPath?.trimmed.nilIfEmpty
        value.stabilityStrength = value.stabilityStrength.flatMap {
            $0.isFinite ? min(max($0, 0.05), 0.95) : nil
        }
        return value
    }
}


private func lensRecipeParameterString(_ value: Any) -> String {
    if let value = value as? Bool { return value ? "true" : "false" }
    if let value = value as? String { return value }
    if let value = value as? NSNumber { return value.stringValue }
    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        return text
    }
    return "\(value)"
}

private func lensRecipeParameterType(_ value: Any) -> String {
    if value is Bool { return "boolean" }
    if value is NSNumber { return "number" }
    if value is [String: Any] || value is [Any] { return "json" }
    return "string"
}

struct LensRenderSourceDependency: Codable, Hashable, Identifiable {
    var dependencyId: String
    var id: String { dependencyId }
    var kind: String = "externalImport"
    var sourceId: String = ""
    var required: Bool = true
    var role: String = ""
    var label: String = ""
    var imagePathOrUrl: String = ""

    func normalized(order: Int? = nil) -> LensRenderSourceDependency {
        var value = self
        value.kind = value.kind.trimmed.isEmpty ? "externalImport" : value.kind.trimmed
        value.sourceId = value.sourceId.trimmed
        value.role = value.role.trimmed
        value.label = value.label.trimmed
        value.imagePathOrUrl = value.imagePathOrUrl.trimmed
        value.dependencyId = value.dependencyId.trimmed
        if value.dependencyId.isEmpty {
            let fallbackOrder = order ?? 0
            value.dependencyId = "render_source_\(shortHash("\(value.kind):\(value.role):\(value.sourceId):\(fallbackOrder)", length: 12))"
        }
        return value
    }
}

struct LensMotionArtifact: Codable, Hashable {
    var provider: String = "civitai"
    var model: String = "wan.v2.5.image-to-video"
    var status: String = ""
    var videoPath: String = ""
    var prompt: String = ""
    var requestId: String = ""
    var traceId: String = ""
    var errorMessage: String = ""
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()

    func normalized() -> LensMotionArtifact {
        var value = self
        value.provider = value.provider.trimmed.isEmpty ? "civitai" : value.provider.trimmed.lowercased()
        value.model = value.model.trimmed.isEmpty ? "wan.v2.5.image-to-video" : value.model.trimmed
        value.status = value.status.trimmed
        value.videoPath = value.videoPath.trimmed
        value.prompt = value.prompt.trimmed
        value.requestId = value.requestId.trimmed
        value.traceId = value.traceId.trimmed
        value.errorMessage = value.errorMessage.trimmed
        value.generatedAt = value.generatedAt.trimmed
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

/// A row-attached spoken voice-over for a rendered Lens take: an OpenAI-drafted
/// script spoken by ElevenLabs. Mirrors the LensMotionArtifact shape — one narration
/// per row; regenerating replaces it.
struct LensNarrationArtifact: Codable, Hashable, Sendable {
    var provider: String = "elevenlabs_tts"
    var model: String = ElevenLabsSpeechModels.defaultModelId
    var status: String = ""
    var audioPath: String = ""
    var script: String = ""
    var voicePresetId: String = ""
    var voiceName: String = ""
    var voiceId: String = ""
    var durationSeconds: Double = 0
    var scriptResponseId: String = ""
    var requestId: String = ""
    var traceId: String = ""
    var errorMessage: String = ""
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()

    var isReady: Bool {
        status == "ready" && !audioPath.isEmpty
    }

    func normalized() -> LensNarrationArtifact {
        var value = self
        value.provider = value.provider.trimmed.isEmpty ? "elevenlabs_tts" : value.provider.trimmed.lowercased()
        value.model = value.model.trimmed.isEmpty ? ElevenLabsSpeechModels.defaultModelId : value.model.trimmed
        value.status = value.status.trimmed
        value.audioPath = value.audioPath.trimmed
        value.script = value.script.trimmed
        value.voicePresetId = value.voicePresetId.trimmed
        value.voiceName = value.voiceName.trimmed
        value.voiceId = value.voiceId.trimmed
        value.durationSeconds = max(0, value.durationSeconds)
        value.scriptResponseId = value.scriptResponseId.trimmed
        value.requestId = value.requestId.trimmed
        value.traceId = value.traceId.trimmed
        value.errorMessage = value.errorMessage.trimmed
        value.generatedAt = value.generatedAt.trimmed
        value.updatedAt = value.updatedAt.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case model
        case status
        case audioPath
        case script
        case voicePresetId
        case voiceName
        case voiceId
        case durationSeconds
        case scriptResponseId
        case requestId
        case traceId
        case errorMessage
        case generatedAt
        case updatedAt
    }

    init(
        provider: String = "elevenlabs_tts",
        model: String = ElevenLabsSpeechModels.defaultModelId,
        status: String = "",
        audioPath: String = "",
        script: String = "",
        voicePresetId: String = "",
        voiceName: String = "",
        voiceId: String = "",
        durationSeconds: Double = 0,
        scriptResponseId: String = "",
        requestId: String = "",
        traceId: String = "",
        errorMessage: String = "",
        generatedAt: String = "",
        updatedAt: String = DateFormats.now()
    ) {
        self.provider = provider
        self.model = model
        self.status = status
        self.audioPath = audioPath
        self.script = script
        self.voicePresetId = voicePresetId
        self.voiceName = voiceName
        self.voiceId = voiceId
        self.durationSeconds = durationSeconds
        self.scriptResponseId = scriptResponseId
        self.requestId = requestId
        self.traceId = traceId
        self.errorMessage = errorMessage
        self.generatedAt = generatedAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "elevenlabs_tts"
        model = try container.decodeIfPresent(String.self, forKey: .model)
            ?? ElevenLabsSpeechModels.legacyMissingModelId
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        audioPath = try container.decodeIfPresent(String.self, forKey: .audioPath) ?? ""
        script = try container.decodeIfPresent(String.self, forKey: .script) ?? ""
        voicePresetId = try container.decodeIfPresent(String.self, forKey: .voicePresetId) ?? ""
        voiceName = try container.decodeIfPresent(String.self, forKey: .voiceName) ?? ""
        voiceId = try container.decodeIfPresent(String.self, forKey: .voiceId) ?? ""
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        scriptResponseId = try container.decodeIfPresent(String.self, forKey: .scriptResponseId) ?? ""
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId) ?? ""
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId) ?? ""
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
        self = normalized()
    }
}

struct ProjectLensHeroImage: Codable, Hashable, Identifiable {
    var imageId: String
    var id: String { imageId }
    var imageIndex: Int = 0
    var label: String = ""
    var provider: String = "openai"
    var model: String = "gpt-image-2"
    var imagePath: String = ""
    var prompt: String = ""
    var sourcePrompt: String = ""
    var negativePrompt: String = ""
    /// Prompt-rewrite provenance for the transmitted scene text: all four are
    /// EMPTY when the rewrite was skipped (reframes, CivitAI, or the
    /// per-frame verbatim choice below). `prompt` = provider-bound text;
    /// `sourcePrompt` = the authored text.
    var promptEnrichmentModel: String = ""
    var promptEnrichmentResponseId: String = ""
    var promptEnrichmentTraceId: String = ""
    var promptEnrichmentSummary: String = ""
    /// The operator turned the prompt transform OFF for this frame — retries,
    /// siblings, and regenerates must stay verbatim too.
    var promptEnrichmentDisabled: Bool = false
    /// The Stability reference-fidelity strength this frame rendered with —
    /// retries and siblings reuse it. nil on non-Stability frames.
    var stabilityStrength: Double?
    var status: String = "idle"
    var requestId: String = ""
    var traceId: String = ""
    var errorMessage: String = ""
    var sourceRouteKey: String = ""
    var sourceRecipeId: String?
    var sourceRecipeVersion: String?
    var sourceAestheticIds: [String] = []
    var subject: LensGeneratedSubject?
    var styleAuthorities: [LensStyleAuthoritySnapshot] = []
    var renderRecipe: LensRenderRecipeSnapshot?
    var renderVersion: LensRenderVersionMetadata?
    var sourceDependencies: [LensRenderSourceDependency] = []
    var motionArtifact: LensMotionArtifact?
    var reframe: LensReframeSpec?
    var narrationArtifact: LensNarrationArtifact?
    var imageKind: String = ""
    /// Roster link for character studies: the ProjectCharacter this take portrays.
    /// Empty for non-character takes and for takes queued before the stamp existed
    /// (those resolve by label/route-key heuristics at display time).
    var characterId: String = ""
    var areaId: String = ""
    var sceneId: String = ""
    var areaImageId: String = ""
    var homeSceneImageId: String = ""
    var taxonomyEnabled: Bool = true
    /// User adoption: a kept concept is one the user chose to follow for downstream work.
    var kept: Bool?
    /// Soft delete: a disabled render is hidden from every board and downstream use but
    /// stays persisted so it can be recovered. Never hard-deleted from the project.
    var disabled: Bool = false
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()
    /// Sheet-driven suggestion provenance: the roster character whose new sheet
    /// minted this planned row, and when. Empty on every other row.
    var suggestedForCharacterId: String?
    var suggestedAt: String = ""

    init(
        imageId: String,
        imageIndex: Int = 0,
        label: String = "",
        provider: String = "openai",
        model: String = "gpt-image-2",
        imagePath: String = "",
        prompt: String = "",
        sourcePrompt: String = "",
        negativePrompt: String = "",
        promptEnrichmentModel: String = "",
        promptEnrichmentResponseId: String = "",
        promptEnrichmentTraceId: String = "",
        promptEnrichmentSummary: String = "",
        status: String = "idle",
        requestId: String = "",
        traceId: String = "",
        errorMessage: String = "",
        sourceRouteKey: String = "",
        sourceRecipeId: String? = nil,
        sourceRecipeVersion: String? = nil,
        sourceAestheticIds: [String] = [],
        subject: LensGeneratedSubject? = nil,
        styleAuthorities: [LensStyleAuthoritySnapshot] = [],
        renderRecipe: LensRenderRecipeSnapshot? = nil,
        renderVersion: LensRenderVersionMetadata? = nil,
        sourceDependencies: [LensRenderSourceDependency] = [],
        motionArtifact: LensMotionArtifact? = nil,
        reframe: LensReframeSpec? = nil,
        narrationArtifact: LensNarrationArtifact? = nil,
        imageKind: String = "",
        characterId: String = "",
        areaId: String = "",
        sceneId: String = "",
        areaImageId: String = "",
        homeSceneImageId: String = "",
        taxonomyEnabled: Bool = true,
        kept: Bool? = nil,
        disabled: Bool = false,
        generatedAt: String = "",
        updatedAt: String = DateFormats.now(),
        suggestedForCharacterId: String? = nil,
        suggestedAt: String = ""
    ) {
        self.imageId = imageId
        self.imageIndex = imageIndex
        self.label = label
        self.provider = provider
        self.model = model
        self.imagePath = imagePath
        self.prompt = prompt
        self.sourcePrompt = sourcePrompt
        self.negativePrompt = negativePrompt
        self.promptEnrichmentModel = promptEnrichmentModel
        self.promptEnrichmentResponseId = promptEnrichmentResponseId
        self.promptEnrichmentTraceId = promptEnrichmentTraceId
        self.promptEnrichmentSummary = promptEnrichmentSummary
        self.status = status
        self.requestId = requestId
        self.traceId = traceId
        self.errorMessage = errorMessage
        self.sourceRouteKey = sourceRouteKey
        self.sourceRecipeId = sourceRecipeId
        self.sourceRecipeVersion = sourceRecipeVersion
        self.sourceAestheticIds = sourceAestheticIds
        self.subject = subject
        self.styleAuthorities = styleAuthorities
        self.renderRecipe = renderRecipe
        self.renderVersion = renderVersion
        self.sourceDependencies = sourceDependencies
        self.motionArtifact = motionArtifact
        self.reframe = reframe
        self.narrationArtifact = narrationArtifact
        self.imageKind = imageKind
        self.characterId = characterId
        self.areaId = areaId
        self.sceneId = sceneId
        self.areaImageId = areaImageId
        self.homeSceneImageId = homeSceneImageId
        self.taxonomyEnabled = taxonomyEnabled
        self.kept = kept
        self.disabled = disabled
        self.generatedAt = generatedAt
        self.updatedAt = updatedAt
        self.suggestedForCharacterId = suggestedForCharacterId
        self.suggestedAt = suggestedAt
    }

    static func queued(
        lensId: String,
        routeKey: String,
        recipe: ProjectAestheticDirectionRecipe,
        prompt: String,
        provider: String = "openai",
        model: String = "gpt-image-2",
        imageIndex: Int = 0,
        label: String = "OpenAI",
        imageKind: String = "",
        characterId: String = "",
        areaId: String = "",
        sceneId: String = "",
        areaImageId: String = "",
        homeSceneImageId: String = "",
        now: String = DateFormats.now()
    ) -> ProjectLensHeroImage {
        let providerKey = provider.trimmed.isEmpty ? "openai" : provider.trimmed
        return ProjectLensHeroImage(
            imageId: "lens_hero_\(shortHash("\(lensId):\(routeKey):\(providerKey):\(now)", length: 14))",
            imageIndex: imageIndex,
            label: label,
            provider: providerKey,
            model: model,
            imagePath: "",
            prompt: prompt,
            sourcePrompt: prompt,
            negativePrompt: "",
            promptEnrichmentModel: "",
            promptEnrichmentResponseId: "",
            promptEnrichmentTraceId: "",
            promptEnrichmentSummary: "",
            status: "queued",
            requestId: "",
            traceId: "",
            errorMessage: "",
            sourceRouteKey: routeKey,
            sourceRecipeId: recipe.recipeId,
            sourceRecipeVersion: recipe.recipeVersion,
            sourceAestheticIds: recipe.selectedReferences.map(\.aestheticId),
            renderRecipe: LensRenderRecipeSnapshot.legacy(provider: provider, model: model, label: label),
            imageKind: imageKind,
            characterId: characterId,
            areaId: areaId,
            sceneId: sceneId,
            areaImageId: areaImageId,
            homeSceneImageId: homeSceneImageId,
            generatedAt: "",
            updatedAt: now
        )
    }

    /// A pure plan is a queued take that has never started rendering: it can be
    /// hard-removed (dropping a plan is undoing an intention, not deleting a record).
    /// Anything that ever rendered is only ever soft-disabled.
    var isPurePlan: Bool {
        status == "queued"
            && generatedAt.trimmed.isEmpty
            && renderVersion == nil
            && reframe == nil
    }

    /// A planned frame the Frame Creator may fulfill IN PLACE: still queued, or a
    /// fulfillment attempt that failed/cancelled before ever producing an image.
    /// Anything that ever rendered (imagePath, generatedAt, renderVersion, reframe)
    /// only spawns siblings/variations.
    var isPlanFulfillmentCandidate: Bool {
        (status == "queued" || status == "failed" || status == "cancelled")
            && generatedAt.trimmed.isEmpty
            && imagePath.trimmed.isEmpty
            && renderVersion == nil
            && reframe == nil
    }
    /// A planned row minted from a rendered character sheet. Provenance survives
    /// fulfillment; the suggestion set is this AND `isPlanFulfillmentCandidate`.
    var isSheetSuggestion: Bool {
        !suggestedAt.trimmed.isEmpty
    }

    func normalized() -> ProjectLensHeroImage {
        var value = self
        value.imageId = value.imageId.trimmed
        value.imageIndex = max(0, value.imageIndex)
        value.label = value.label.trimmed
        value.provider = value.provider.trimmed.isEmpty ? "openai" : value.provider.trimmed.lowercased()
        value.model = value.model.trimmed.isEmpty ? (value.provider == "stability" ? "stable-image-ultra" : "gpt-image-2") : value.model.trimmed
        value.imagePath = value.imagePath.trimmed
        value.prompt = value.prompt.trimmed
        value.sourcePrompt = value.sourcePrompt.trimmed.isEmpty ? value.prompt : value.sourcePrompt.trimmed
        value.negativePrompt = value.negativePrompt.trimmed
        value.promptEnrichmentModel = value.promptEnrichmentModel.trimmed
        value.promptEnrichmentResponseId = value.promptEnrichmentResponseId.trimmed
        value.promptEnrichmentTraceId = value.promptEnrichmentTraceId.trimmed
        value.promptEnrichmentSummary = value.promptEnrichmentSummary.trimmed
        value.status = value.status.trimmed.isEmpty ? "idle" : value.status.trimmed
        value.requestId = value.requestId.trimmed
        value.traceId = value.traceId.trimmed
        value.errorMessage = value.errorMessage.trimmed
        value.sourceRouteKey = value.sourceRouteKey.trimmed
        value.sourceRecipeId = value.sourceRecipeId?.trimmed.nilIfEmpty
        value.sourceRecipeVersion = value.sourceRecipeVersion?.trimmed.nilIfEmpty
        value.sourceAestheticIds = uniqueNonEmpty(value.sourceAestheticIds)
        value.subject = value.subject?.normalized()
        value.styleAuthorities = value.styleAuthorities
            .enumerated()
            .map { index, authority in authority.normalized(order: index) }
        if let recipe = value.renderRecipe?.normalized() {
            value.renderRecipe = recipe
        } else {
            value.renderRecipe = LensRenderRecipeSnapshot.legacy(provider: value.provider, model: value.model, label: value.label)
        }
        value.renderVersion = value.renderVersion?.normalized()
        value.sourceDependencies = value.sourceDependencies
            .enumerated()
            .map { index, dependency in dependency.normalized(order: index) }
            .filter { !$0.sourceId.isEmpty || !$0.imagePathOrUrl.isEmpty }
        value.motionArtifact = value.motionArtifact?.normalized()
        value.reframe = value.reframe?.normalized()
        value.narrationArtifact = value.narrationArtifact?.normalized()
        value.imageKind = LensImageTaxonomyKind.normalized(value.imageKind)
        value.characterId = value.characterId.trimmed
        value.areaId = value.areaId.trimmed
        value.sceneId = value.sceneId.trimmed
        value.areaImageId = value.areaImageId.trimmed
        value.homeSceneImageId = value.homeSceneImageId.trimmed
        value.generatedAt = value.generatedAt.trimmed
        value.updatedAt = value.updatedAt.trimmed
        value.suggestedForCharacterId = value.suggestedForCharacterId?.trimmed.nilIfEmpty
        value.suggestedAt = value.suggestedAt.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case imageId
        case imageIndex
        case label
        case provider
        case model
        case imagePath
        case prompt
        case sourcePrompt
        case negativePrompt
        case promptEnrichmentModel
        case promptEnrichmentResponseId
        case promptEnrichmentTraceId
        case promptEnrichmentSummary
        case promptEnrichmentDisabled
        case stabilityStrength
        case status
        case requestId
        case traceId
        case errorMessage
        case sourceRouteKey
        case sourceRecipeId
        case sourceRecipeVersion
        case sourceAestheticIds
        case subject
        case styleAuthorities
        case renderRecipe
        case renderVersion
        case sourceDependencies
        case motionArtifact
        case reframe
        case narrationArtifact
        case imageKind
        case characterId
        case areaId
        case sceneId
        case areaImageId
        case homeSceneImageId
        case taxonomyEnabled
        case kept
        case disabled
        case generatedAt
        case updatedAt
        case suggestedForCharacterId
        case suggestedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        imageId = try container.decodeIfPresent(String.self, forKey: .imageId)
            ?? "lens_hero_\(UUID().uuidString.lowercased())"
        imageIndex = try container.decodeIfPresent(Int.self, forKey: .imageIndex) ?? 0
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "openai"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "gpt-image-2"
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath) ?? ""
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        sourcePrompt = try container.decodeIfPresent(String.self, forKey: .sourcePrompt) ?? ""
        negativePrompt = try container.decodeIfPresent(String.self, forKey: .negativePrompt) ?? ""
        promptEnrichmentModel = try container.decodeIfPresent(String.self, forKey: .promptEnrichmentModel) ?? ""
        promptEnrichmentResponseId = try container.decodeIfPresent(String.self, forKey: .promptEnrichmentResponseId) ?? ""
        promptEnrichmentTraceId = try container.decodeIfPresent(String.self, forKey: .promptEnrichmentTraceId) ?? ""
        promptEnrichmentSummary = try container.decodeIfPresent(String.self, forKey: .promptEnrichmentSummary) ?? ""
        promptEnrichmentDisabled = try container.decodeIfPresent(Bool.self, forKey: .promptEnrichmentDisabled) ?? false
        stabilityStrength = try container.decodeIfPresent(Double.self, forKey: .stabilityStrength)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "idle"
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId) ?? ""
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId) ?? ""
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
        sourceRouteKey = try container.decodeIfPresent(String.self, forKey: .sourceRouteKey) ?? ""
        sourceRecipeId = try container.decodeIfPresent(String.self, forKey: .sourceRecipeId)
        sourceRecipeVersion = try container.decodeIfPresent(String.self, forKey: .sourceRecipeVersion)
        sourceAestheticIds = try container.decodeIfPresent([String].self, forKey: .sourceAestheticIds) ?? []
        subject = try container.decodeIfPresent(LensGeneratedSubject.self, forKey: .subject)
        styleAuthorities = try container.decodeIfPresent([LensStyleAuthoritySnapshot].self, forKey: .styleAuthorities) ?? []
        renderRecipe = try container.decodeIfPresent(LensRenderRecipeSnapshot.self, forKey: .renderRecipe)
        renderVersion = try container.decodeIfPresent(LensRenderVersionMetadata.self, forKey: .renderVersion)
        sourceDependencies = try container.decodeIfPresent([LensRenderSourceDependency].self, forKey: .sourceDependencies) ?? []
        motionArtifact = try container.decodeIfPresent(LensMotionArtifact.self, forKey: .motionArtifact)
        reframe = (try? container.decodeIfPresent(LensReframeSpec.self, forKey: .reframe)) ?? nil
        narrationArtifact = (try? container.decodeIfPresent(LensNarrationArtifact.self, forKey: .narrationArtifact)) ?? nil
        imageKind = try container.decodeIfPresent(String.self, forKey: .imageKind) ?? ""
        characterId = try container.decodeIfPresent(String.self, forKey: .characterId) ?? ""
        areaId = try container.decodeIfPresent(String.self, forKey: .areaId) ?? ""
        sceneId = try container.decodeIfPresent(String.self, forKey: .sceneId) ?? ""
        areaImageId = try container.decodeIfPresent(String.self, forKey: .areaImageId) ?? ""
        homeSceneImageId = try container.decodeIfPresent(String.self, forKey: .homeSceneImageId) ?? ""
        taxonomyEnabled = try container.decodeIfPresent(Bool.self, forKey: .taxonomyEnabled) ?? true
        kept = try container.decodeIfPresent(Bool.self, forKey: .kept)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
        suggestedForCharacterId = try container.decodeIfPresent(String.self, forKey: .suggestedForCharacterId)
        suggestedAt = try container.decodeIfPresent(String.self, forKey: .suggestedAt) ?? ""
        self = normalized()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(imageId, forKey: .imageId)
        try container.encode(imageIndex, forKey: .imageIndex)
        try container.encode(label, forKey: .label)
        try container.encode(provider, forKey: .provider)
        try container.encode(model, forKey: .model)
        try container.encode(imagePath, forKey: .imagePath)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(sourcePrompt, forKey: .sourcePrompt)
        try container.encode(negativePrompt, forKey: .negativePrompt)
        try container.encode(promptEnrichmentModel, forKey: .promptEnrichmentModel)
        try container.encode(promptEnrichmentResponseId, forKey: .promptEnrichmentResponseId)
        try container.encode(promptEnrichmentTraceId, forKey: .promptEnrichmentTraceId)
        try container.encode(promptEnrichmentSummary, forKey: .promptEnrichmentSummary)
        try container.encode(promptEnrichmentDisabled, forKey: .promptEnrichmentDisabled)
        try container.encodeIfPresent(stabilityStrength, forKey: .stabilityStrength)
        try container.encode(status, forKey: .status)
        try container.encode(requestId, forKey: .requestId)
        try container.encode(traceId, forKey: .traceId)
        try container.encode(errorMessage, forKey: .errorMessage)
        try container.encode(sourceRouteKey, forKey: .sourceRouteKey)
        try container.encode(sourceRecipeId, forKey: .sourceRecipeId)
        try container.encode(sourceRecipeVersion, forKey: .sourceRecipeVersion)
        try container.encode(sourceAestheticIds, forKey: .sourceAestheticIds)
        try container.encodeIfPresent(subject, forKey: .subject)
        try container.encode(styleAuthorities, forKey: .styleAuthorities)
        try container.encodeIfPresent(renderRecipe, forKey: .renderRecipe)
        try container.encodeIfPresent(renderVersion, forKey: .renderVersion)
        try container.encode(sourceDependencies, forKey: .sourceDependencies)
        try container.encodeIfPresent(motionArtifact, forKey: .motionArtifact)
        try container.encodeIfPresent(reframe, forKey: .reframe)
        try container.encodeIfPresent(narrationArtifact, forKey: .narrationArtifact)
        try container.encode(imageKind, forKey: .imageKind)
        try container.encode(characterId, forKey: .characterId)
        try container.encode(areaId, forKey: .areaId)
        try container.encode(sceneId, forKey: .sceneId)
        try container.encode(areaImageId, forKey: .areaImageId)
        try container.encode(homeSceneImageId, forKey: .homeSceneImageId)
        try container.encode(taxonomyEnabled, forKey: .taxonomyEnabled)
        try container.encode(kept, forKey: .kept)
        try container.encode(disabled, forKey: .disabled)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        // Encoded only when set: every row that is not a suggestion keeps its
        // exact prior JSON shape.
        try container.encodeIfPresent(suggestedForCharacterId, forKey: .suggestedForCharacterId)
        if !suggestedAt.isEmpty {
            try container.encode(suggestedAt, forKey: .suggestedAt)
        }
    }
}

/// Implicit casting: the scene cast is derived from its takes, never toggled. This is
/// the pure core of that derivation — first-appearance order over the resolved
/// character ids of a version's takes, restricted to characters that still exist.
enum LensCastDerivation {
    static func derivedCharacterIds(resolvedIds: [String], knownIds: Set<String>) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in resolvedIds {
            guard !id.isEmpty, knownIds.contains(id), seen.insert(id).inserted else { continue }
            result.append(id)
        }
        return result
    }
}

private struct LensRenderVersionParamsSeed: Codable, Hashable {
    var parameters: [LensRenderVersionParameterSeed]
}

private struct LensRenderVersionParameterSeed: Codable, Hashable {
    var key: String
    var value: String
    var valueType: String
}

private struct LensRenderVersionStackSeed: Codable, Hashable {
    var provider: String
    var model: String
    var stackId: String
    var paramsFingerprint: String
    var capabilities: [String]
    var styleReferences: [String]
    var sourceDependencies: [String]
}

private struct LensRenderVersionGroupSeed: Codable, Hashable {
    var targetId: String
    var stackFingerprint: String
}

private func lensHeroImagesWithRenderVersionMetadata(
    lensId: String,
    heroImages: [ProjectLensHeroImage]
) -> [ProjectLensHeroImage] {
    var values = heroImages.map { $0.normalized() }
    var groupIndexes: [String: [Int]] = [:]
    for index in values.indices {
        guard lensHeroImageIsSubmittedGeneration(values[index]) else {
            values[index].renderVersion = nil
            continue
        }
        let targetId = lensRenderTargetId(lensId: lensId, image: values[index])
        let paramsFingerprint = lensRenderParamsFingerprint(values[index])
        let stackFingerprint = lensRenderStackFingerprint(image: values[index], paramsFingerprint: paramsFingerprint)
        let groupId = "rvgrp_\(stableHash(LensRenderVersionGroupSeed(targetId: targetId, stackFingerprint: stackFingerprint), length: 20))"
        values[index].renderVersion = LensRenderVersionMetadata(
            renderVersionId: lensRenderVersionId(lensId: lensId, image: values[index]),
            renderTargetId: targetId,
            renderStackFingerprint: stackFingerprint,
            renderVersionGroupId: groupId,
            versionNumber: 0,
            seed: lensRenderSeed(values[index]),
            finalPromptFingerprint: lensFinalPromptFingerprint(values[index]),
            renderParamsFingerprint: paramsFingerprint,
            isActive: values[index].renderVersion?.isActive == true
        ).normalized()
        groupIndexes[groupId, default: []].append(index)
    }
    for groupId in groupIndexes.keys.sorted() {
        let sortedIndexes = (groupIndexes[groupId] ?? []).sorted { lhs, rhs in
            if values[lhs].imageIndex == values[rhs].imageIndex {
                let lhsTime = lensRenderVersionSortTime(values[lhs])
                let rhsTime = lensRenderVersionSortTime(values[rhs])
                if lhsTime == rhsTime {
                    return values[lhs].imageId < values[rhs].imageId
                }
                return lhsTime < rhsTime
            }
            return values[lhs].imageIndex < values[rhs].imageIndex
        }
        for (offset, index) in sortedIndexes.enumerated() {
            values[index].renderVersion?.versionNumber = offset + 1
        }
        let explicitActiveIndex = sortedIndexes.first {
            values[$0].renderVersion?.isActive == true && lensHeroImageCanBeActiveRenderVersion(values[$0])
        }
        let newestReadyIndex = sortedIndexes.reversed().first {
            lensHeroImageCanBeActiveRenderVersion(values[$0])
        }
        let activeIndex = explicitActiveIndex ?? newestReadyIndex ?? sortedIndexes.first
        for index in sortedIndexes {
            values[index].renderVersion?.isActive = index == activeIndex
        }
    }
    return values.map { $0.normalized() }
}

private func lensHeroImageIsSubmittedGeneration(_ image: ProjectLensHeroImage) -> Bool {
    switch image.status.trimmed.lowercased() {
    case "ready", "generating", "failed", "cancelled", "canceled":
        return true
    default:
        return false
    }
}

private func lensHeroImageCanBeActiveRenderVersion(_ image: ProjectLensHeroImage) -> Bool {
    image.status.trimmed.lowercased() == "ready" && !image.imagePath.trimmed.isEmpty
}

private func lensRenderVersionId(lensId: String, image: ProjectLensHeroImage) -> String {
    if let existing = image.renderVersion?.renderVersionId.trimmed.nilIfEmpty {
        return existing
    }
    return "rendver_\(stableHash(["lens_id": lensId, "image_id": image.imageId], length: 20))"
}

private func lensRenderTargetId(lensId: String, image: ProjectLensHeroImage) -> String {
    let route = lensRenderTargetRouteKey(image.sourceRouteKey)
    let subject = image.subject?.normalized()
    let seed = [
        "lens_id": lensId,
        "route": route,
        "subject_kind": subject?.kind.rawValue ?? "",
        "subject": subject?.description ?? ""
    ]
    return "rtgt_\(stableHash(seed, length: 20))"
}

private func lensRenderTargetRouteKey(_ routeKey: String) -> String {
    let withoutMediaVersion = routeKey.trimmed.split(separator: "@", maxSplits: 1).first.map(String.init) ?? routeKey.trimmed
    let parts = withoutMediaVersion.split(separator: "_")
    guard let last = parts.last,
          last.hasPrefix("s"),
          last.dropFirst().allSatisfy(\.isNumber),
          parts.count > 1 else {
        return withoutMediaVersion
    }
    return parts.dropLast().joined(separator: "_")
}

private func lensRenderStackFingerprint(image: ProjectLensHeroImage, paramsFingerprint: String) -> String {
    let recipe = image.renderRecipe?.normalized()
    let styleReferences = image.styleAuthorities
        .map { $0.normalized() }
        .map { authority in
            [
                authority.role,
                authority.source.rawValue,
                authority.referenceId,
                authority.sourceReferenceId,
                authority.imageUrl,
                authority.imagePath,
                authority.weight.map { String($0) } ?? ""
            ].joined(separator: "|")
        }
        .sorted()
    let dependencies = image.sourceDependencies
        .map { $0.normalized() }
        .map { dependency in
            [
                dependency.kind,
                dependency.role,
                dependency.sourceId,
                dependency.required ? "required" : "optional",
                dependency.imagePathOrUrl
            ].joined(separator: "|")
        }
        .sorted()
    let seed = LensRenderVersionStackSeed(
        provider: recipe?.provider.nilIfEmpty ?? image.provider,
        model: recipe?.model.nilIfEmpty ?? image.model,
        stackId: recipe?.stackId ?? "",
        paramsFingerprint: paramsFingerprint,
        capabilities: recipe?.capabilities ?? [],
        styleReferences: styleReferences,
        sourceDependencies: dependencies
    )
    return "rstk_\(stableHash(seed, length: 20))"
}

private func lensRenderParamsFingerprint(_ image: ProjectLensHeroImage) -> String {
    let parameters = lensRenderVersionParameters(image)
    return "rpar_\(stableHash(LensRenderVersionParamsSeed(parameters: parameters), length: 20))"
}

private func lensRenderVersionParameters(_ image: ProjectLensHeroImage) -> [LensRenderVersionParameterSeed] {
    let omittedKeys: Set<String> = [
        "seed",
        "source_url",
        "output_url",
        "image_url",
        "image_path",
        "request_id",
        "trace_id",
        "provider_job_id",
        "job_id",
        "output_sha256",
        "output_bytes",
        "output_content_type",
        "provider_price_note"
    ]
    var outputByKey: [String: LensRenderVersionParameterSeed] = [:]
    for parameter in image.renderRecipe?.normalized().parameters ?? [] {
        let key = parameter.key.trimmed.lowercased()
        guard !key.isEmpty, !omittedKeys.contains(key) else { continue }
        if key == "debug_overrides_json" {
            for override in lensRenderVersionDebugParameters(from: parameter.value) {
                outputByKey[override.key] = override
            }
            continue
        }
        outputByKey[key] = LensRenderVersionParameterSeed(key: key, value: parameter.value, valueType: parameter.valueType)
    }
    return Array(outputByKey.values).sorted {
        if $0.key == $1.key {
            return $0.value < $1.value
        }
        return $0.key < $1.key
    }
}

private func lensRenderVersionDebugParameters(from json: String) -> [LensRenderVersionParameterSeed] {
    guard let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return []
    }
    return object.compactMap { key, value in
        let normalizedKey = key.trimmed.lowercased()
        guard !normalizedKey.isEmpty, normalizedKey != "seed" else { return nil }
        return LensRenderVersionParameterSeed(
            key: normalizedKey,
            value: lensRecipeParameterString(value),
            valueType: lensRecipeParameterType(value)
        )
    }
    .sorted {
        if $0.key == $1.key {
            return $0.value < $1.value
        }
        return $0.key < $1.key
    }
}

private func lensRenderSeed(_ image: ProjectLensHeroImage) -> String {
    for parameter in image.renderRecipe?.normalized().parameters ?? [] {
        guard parameter.key.trimmed.lowercased() == "seed" else { continue }
        let value = parameter.value.trimmed
        if !value.isEmpty, value.lowercased() != "random" {
            return value
        }
    }
    if let existing = image.renderVersion?.seed.trimmed.nilIfEmpty {
        return existing
    }
    return ""
}

private func lensFinalPromptFingerprint(_ image: ProjectLensHeroImage) -> String {
    let prompt = image.prompt.trimmed.isEmpty ? image.sourcePrompt : image.prompt
    guard !prompt.trimmed.isEmpty else { return "" }
    return "fpmt_\(stableHash(prompt.trimmed, length: 20))"
}

private func lensRenderVersionSortTime(_ image: ProjectLensHeroImage) -> String {
    image.generatedAt.trimmed.nilIfEmpty
        ?? image.updatedAt.trimmed.nilIfEmpty
        ?? image.renderVersion?.renderVersionId
        ?? image.imageId
}

private struct LensRowSnapshotSeed: Codable, Hashable {
    var lensId: String
    var lensTitle: String
    var lensStatusAtGeneration: String
    var ingredientId: String
    var ingredientTitle: String
    var narrativeUse: String
    var presentationUse: String
    var paletteTerms: [String]
    var motifTerms: [String]
    var avoidTerms: [String]
    var sourceAestheticIds: [String]
    var sourceRecipeId: String
    var sourceRecipeVersion: String
}

struct ProjectLens: Codable, Hashable, Identifiable {
    var lensId: String
    var id: String { lensId }
    var status: ProjectLensStatus = .ready
    var enabled: Bool = true
    var body: LensBody = .empty()
    var heroImage: ProjectLensHeroImage?
    var heroImages: [ProjectLensHeroImage] = []
    var relationSummary: LensRelationSummary = .empty
    var readyReadinessIssues: [LensReadinessIssue] = []
    var generationRunId: String = ""
    var generationPhase: String = ""
    var generationError: String = ""
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()

    init(
        lensId: String,
        status: ProjectLensStatus = .ready,
        enabled: Bool = true,
        body: LensBody = .empty(),
        heroImage: ProjectLensHeroImage? = nil,
        heroImages: [ProjectLensHeroImage] = [],
        relationSummary: LensRelationSummary = .empty,
        readyReadinessIssues: [LensReadinessIssue] = [],
        generationRunId: String = "",
        generationPhase: String = "",
        generationError: String = "",
        createdAt: String = DateFormats.now(),
        updatedAt: String = DateFormats.now()
    ) {
        self.lensId = lensId
        self.status = status
        self.enabled = enabled
        self.body = body
        self.heroImage = heroImage
        self.heroImages = heroImages
        self.relationSummary = relationSummary
        self.readyReadinessIssues = readyReadinessIssues
        self.generationRunId = generationRunId
        self.generationPhase = generationPhase
        self.generationError = generationError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isGenerationEligible: Bool {
        enabled
    }

    var readinessBlocks: [LensReadinessIssue] {
        body.hardBlocks
    }

    var readinessWarnings: [LensReadinessIssue] {
        body.warnings
    }

    func normalized() -> ProjectLens {
        var value = self
        value.lensId = value.lensId.trimmed
        if value.lensId.isEmpty {
            value.lensId = "lens_\(shortHash("\(body.title):\(createdAt)", length: 12))"
        }
        value.body = value.body.normalized()
        value.heroImage = value.heroImage?.normalized()
        value.heroImages = lensHeroImagesWithRenderVersionMetadata(
            lensId: value.lensId,
            heroImages: value.heroImages
        )
        if value.heroImages.isEmpty, let heroImage = value.heroImage {
            value.heroImages = lensHeroImagesWithRenderVersionMetadata(
                lensId: value.lensId,
                heroImages: [heroImage.normalized()]
            )
        }
        value.heroImages = value.heroImages.sorted {
            if $0.imageIndex == $1.imageIndex {
                return $0.provider < $1.provider
            }
            return $0.imageIndex < $1.imageIndex
        }
        value.heroImage = value.primaryHeroImage
        value.readyReadinessIssues = uniqueReadinessIssues(value.readyReadinessIssues)
        value.generationRunId = value.generationRunId.trimmed
        value.generationPhase = value.generationPhase.trimmed
        value.generationError = value.generationError.trimmed
        value.status = .ready
        return value
    }

    var sortedHeroImages: [ProjectLensHeroImage] {
        let images = heroImages.isEmpty ? heroImage.map { [$0] } ?? [] : heroImages
        return images.map { $0.normalized() }.sorted {
            if $0.imageIndex == $1.imageIndex {
                return $0.provider < $1.provider
            }
            return $0.imageIndex < $1.imageIndex
        }
    }

    var readyHeroImages: [ProjectLensHeroImage] {
        sortedHeroImages.filter { $0.status == "ready" && !$0.imagePath.trimmed.isEmpty && !$0.disabled }
    }

    var primaryHeroImage: ProjectLensHeroImage? {
        readyHeroImages.first { $0.renderVersion?.isActive == true }
            ?? readyHeroImages.first
            ?? sortedHeroImages.first { $0.renderVersion?.isActive == true && !$0.disabled }
            ?? sortedHeroImages.first { !$0.disabled }
    }

    /// Media versions are encoded in each hero image's sourceRouteKey as an "@versionId"
    /// suffix ("lens_media_scene@a1b2c3"); no suffix is the initial generation. This keeps
    /// versioning inside the already-persisted payload without a storage change.
    static func mediaVersionId(fromRouteKey routeKey: String) -> String {
        guard let atIndex = routeKey.lastIndex(of: "@") else { return "" }
        return String(routeKey[routeKey.index(after: atIndex)...])
    }

    /// Ordered media version ids, oldest first ("" = the initial generation when present).
    var mediaVersionIds: [String] {
        var seen: [String] = []
        for image in heroImages {
            let versionId = Self.mediaVersionId(fromRouteKey: image.sourceRouteKey)
            if !seen.contains(versionId) {
                seen.append(versionId)
            }
        }
        return seen
    }

    /// Hidden (disabled) renders are excluded: this is the board-facing view of a
    /// media version. The raw `heroImages` array still holds them for persistence.
    func heroImages(mediaVersion versionId: String) -> [ProjectLensHeroImage] {
        sortedHeroImages.filter { Self.mediaVersionId(fromRouteKey: $0.sourceRouteKey) == versionId && !$0.disabled }
    }

    /// The treatment blend a media version was rendered with, stored on its images'
    /// sourceRecipeVersion at queue time. Empty for versions that predate blend provenance.
    func blendSnapshot(mediaVersion versionId: String) -> String {
        heroImages(mediaVersion: versionId)
            .compactMap { $0.sourceRecipeVersion?.trimmed.nilIfEmpty }
            .first ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case lensId
        case status
        case enabled
        case body
        case heroImage
        case heroImages
        case relationSummary
        case readyReadinessIssues
        case generationRunId
        case generationPhase
        case generationError
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lensId = try container.decodeIfPresent(String.self, forKey: .lensId) ?? ""
        status = try container.decodeIfPresent(ProjectLensStatus.self, forKey: .status) ?? .ready
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        body = try container.decodeIfPresent(LensBody.self, forKey: .body) ?? .empty()
        heroImage = try container.decodeIfPresent(ProjectLensHeroImage.self, forKey: .heroImage)
        heroImages = try container.decodeIfPresent([ProjectLensHeroImage].self, forKey: .heroImages) ?? []
        relationSummary = try container.decodeIfPresent(LensRelationSummary.self, forKey: .relationSummary) ?? .empty
        readyReadinessIssues = try container.decodeIfPresent([LensReadinessIssue].self, forKey: .readyReadinessIssues) ?? []
        generationRunId = try container.decodeIfPresent(String.self, forKey: .generationRunId) ?? ""
        generationPhase = try container.decodeIfPresent(String.self, forKey: .generationPhase) ?? ""
        generationError = try container.decodeIfPresent(String.self, forKey: .generationError) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? DateFormats.now()
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
        self = normalized()
    }

    func encode(to encoder: Encoder) throws {
        let value = normalized()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.lensId, forKey: .lensId)
        try container.encode(value.status, forKey: .status)
        try container.encode(value.enabled, forKey: .enabled)
        try container.encode(value.body, forKey: .body)
        try container.encode(value.heroImage, forKey: .heroImage)
        try container.encode(value.heroImages, forKey: .heroImages)
        try container.encode(value.relationSummary, forKey: .relationSummary)
        if !value.readyReadinessIssues.isEmpty {
            try container.encode(value.readyReadinessIssues, forKey: .readyReadinessIssues)
        }
        if !value.generationRunId.isEmpty {
            try container.encode(value.generationRunId, forKey: .generationRunId)
        }
        if !value.generationPhase.isEmpty {
            try container.encode(value.generationPhase, forKey: .generationPhase)
        }
        if !value.generationError.isEmpty {
            try container.encode(value.generationError, forKey: .generationError)
        }
        try container.encode(value.createdAt, forKey: .createdAt)
        try container.encode(value.updatedAt, forKey: .updatedAt)
    }
}

struct LensScratchDraft: Codable, Hashable, Identifiable {
    var scratchId: String
    var id: String { scratchId }
    var body: LensBody = .empty()
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String, now: String = DateFormats.now()) -> LensScratchDraft {
        LensScratchDraft(
            scratchId: "scratch_\(shortHash("\(projectId):scratch:\(now):\(UUID().uuidString)", length: 12))",
            body: .empty(),
            createdAt: now,
            updatedAt: now
        )
    }

    func normalized() -> LensScratchDraft {
        var value = self
        value.body = value.body.normalized()
        return value
    }
}

struct ProjectLensSetVersion: Codable, Hashable, Identifiable {
    var versionId: String
    var id: String { versionId }
    var turnIndex: Int
    var lenses: [ProjectLens] = []
    var scratchDrafts: [LensScratchDraft] = []
    var selectedLensId: String?
    var selectedScratchId: String?
    var changeSummary: String
    var createdAt: String
    var model: String
}

struct ProjectLensSetDocument: Codable, Hashable {
    static let schemaVersion = "litscenes.project_lens_set.v0.1"
    static let maximumVersionCount = 35
    static let maximumLensBodyVersionsPerLens = 35

    var schemaVersion: String = Self.schemaVersion
    var projectId: String
    var messages: [ProjectLensMessage] = []
    var lensEditMessages: [ProjectLensEditMessage] = []
    var lensBodyVersions: [ProjectLensBodyVersion] = []
    var versions: [ProjectLensSetVersion] = []
    var activeVersionId: String = ""
    var updatedAt: String = DateFormats.now()

    /// Versions whose lens snapshots were deliberately NOT decoded at load.
    ///
    /// Only the SQLite loader populates this, and only for rows it skipped:
    /// the UI reads one lens (`lenses` resolves to `activeVersion`), so
    /// decoding the whole history cost ~11 MB of JSON on the main actor at
    /// project open.
    ///
    /// The set names the exception, never the rule. Empty — the default for
    /// every other construction path, and for any version appended after a
    /// load — means "fully in memory", which is the reading that is safe to
    /// write. Naming the hydrated side instead was a real bug: a version
    /// created fresh by `appendVersion` was absent from that set and so looked
    /// unloaded, and the save path refused to persist it (hit while
    /// generating a frame).
    ///
    /// This is load state, not content: absent from `CodingKeys`, so it never
    /// reaches JSON and never perturbs a version fingerprint. Anything that
    /// mutates or persists `versions` MUST consult `hasHydratedLenses` — a
    /// skipped version's empty `lenses` means "not loaded", never "no lens",
    /// and writing it back as empty would erase real history.
    var versionIdsWithoutLoadedLenses: Set<String> = []

    func hasHydratedLenses(_ versionId: String) -> Bool {
        !versionIdsWithoutLoadedLenses.contains(versionId)
    }

    init(
        schemaVersion: String = Self.schemaVersion,
        projectId: String,
        messages: [ProjectLensMessage] = [],
        lensEditMessages: [ProjectLensEditMessage] = [],
        lensBodyVersions: [ProjectLensBodyVersion] = [],
        versions: [ProjectLensSetVersion] = [],
        activeVersionId: String = "",
        updatedAt: String = DateFormats.now()
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.messages = messages
        self.lensEditMessages = lensEditMessages.map { $0.normalized() }
        self.lensBodyVersions = lensBodyVersions.map { $0.normalized() }
        self.versions = versions
        self.activeVersionId = activeVersionId
        self.updatedAt = updatedAt
        backfillLensBodyVersionsFromSetVersions()
        canonicalizeToSingleLens()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case messages
        case lensEditMessages
        case lensBodyVersions
        case versions
        case activeVersionId
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        messages = try container.decodeIfPresent([ProjectLensMessage].self, forKey: .messages) ?? []
        lensEditMessages = (try container.decodeIfPresent([ProjectLensEditMessage].self, forKey: .lensEditMessages) ?? [])
            .map { $0.normalized() }
        lensBodyVersions = (try container.decodeIfPresent([ProjectLensBodyVersion].self, forKey: .lensBodyVersions) ?? [])
            .map { $0.normalized() }
        versions = try container.decodeIfPresent([ProjectLensSetVersion].self, forKey: .versions) ?? []
        activeVersionId = try container.decodeIfPresent(String.self, forKey: .activeVersionId) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
        backfillLensBodyVersionsFromSetVersions()
        canonicalizeToSingleLens()
    }

    static func empty(projectId: String = "") -> ProjectLensSetDocument {
        ProjectLensSetDocument(projectId: projectId)
    }

    static func bootstrap(projectId: String, now: String = DateFormats.now()) -> ProjectLensSetDocument {
        var document = ProjectLensSetDocument.empty(projectId: projectId)
        document.appendVersion(
            lenses: [],
            scratchDrafts: [],
            selectedLensId: nil,
            selectedScratchId: nil,
            changeSummary: "Initialized Scene Plan workbench.",
            model: "local-bootstrap",
            now: now
        )
        return document
    }

    static func decode(from data: Data) throws -> ProjectLensSetDocument {
        try JSONCoding.decoder.decode(ProjectLensSetDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }

    func canonicalizedToSingleLens() -> ProjectLensSetDocument {
        var value = self
        value.canonicalizeToSingleLens()
        return value
    }

    var activeVersion: ProjectLensSetVersion? {
        versions.first { $0.versionId == activeVersionId } ?? versions.last
    }

    var lenses: [ProjectLens] {
        activeVersion?.lenses ?? []
    }

    var scratchDrafts: [LensScratchDraft] {
        activeVersion?.scratchDrafts ?? []
    }

    var selectedLensId: String? {
        activeVersion?.selectedLensId
    }

    var selectedScratchId: String? {
        activeVersion?.selectedScratchId
    }

    var readyLenses: [ProjectLens] {
        lenses.filter(\.isGenerationEligible)
    }

    func bodyVersions(for lensId: String) -> [ProjectLensBodyVersion] {
        lensBodyVersions
            .filter { $0.lensId == lensId.trimmed }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var activeScratch: LensScratchDraft? {
        if selectedLensId != nil {
            return nil
        }
        if let selectedScratchId {
            return scratchDrafts.first { $0.scratchId == selectedScratchId }
        }
        return scratchDrafts.first
    }

    mutating func appendMessage(
        role: ProjectLensMessageRole,
        text: String,
        targetScratchId: String?,
        targetLensId: String?,
        mediaIds: [String] = [],
        now: String
    ) {
        messages.append(ProjectLensMessage(
            messageId: "lens_msg_\(shortHash("\(projectId):\(role.rawValue):\(now):\(messages.count)", length: 12))",
            role: role,
            text: text.trimmed,
            targetScratchId: targetScratchId?.trimmed.nilIfEmpty,
            targetLensId: targetLensId?.trimmed.nilIfEmpty,
            mediaIds: uniqueNonEmpty(mediaIds),
            createdAt: now
        ))
        updatedAt = now
    }

    mutating func appendVersion(
        lenses: [ProjectLens],
        scratchDrafts: [LensScratchDraft],
        selectedLensId: String?,
        selectedScratchId: String?,
        changeSummary: String,
        model: String,
        now: String
    ) {
        let normalizedLenses = lenses.map { $0.normalized() }
        let normalizedScratchDrafts = scratchDrafts.map { $0.normalized() }
        let version = ProjectLensSetVersion(
            versionId: "lens_set_\(shortHash("\(projectId):\(now):\(versions.count):\(changeSummary)", length: 12))",
            turnIndex: messages.count,
            lenses: normalizedLenses,
            scratchDrafts: normalizedScratchDrafts,
            selectedLensId: selectedLensId?.trimmed.nilIfEmpty,
            selectedScratchId: selectedScratchId?.trimmed.nilIfEmpty
                ?? (selectedLensId?.trimmed.nilIfEmpty == nil ? normalizedScratchDrafts.first?.scratchId : nil),
            changeSummary: changeSummary.trimmed,
            createdAt: now,
            model: model
        )
        versions.append(version)
        if versions.count > Self.maximumVersionCount {
            versions.removeFirst(versions.count - Self.maximumVersionCount)
        }
        appendLensBodyVersions(
            for: normalizedLenses,
            sourceLensSetVersionId: version.versionId,
            turnIndex: version.turnIndex,
            changeSummary: version.changeSummary,
            model: version.model,
            now: now
        )
        pruneLensBodyVersions(retainedLensSetVersionIds: Set(versions.map(\.versionId)))
        activeVersionId = version.versionId
        updatedAt = now
    }

    /// Updates the active version's lens snapshots in place, preserving its versionId and
    /// changeSummary. For mechanical persistence (image statuses landing during a media run)
    /// that should not add entries to the creative version history. Falls back to
    /// appendVersion semantics when no active version exists.
    mutating func updateActiveVersion(lenses: [ProjectLens], now: String) {
        let normalizedLenses = lenses.map { $0.normalized() }
        guard let index = versions.firstIndex(where: { $0.versionId == activeVersionId }) else {
            appendVersion(
                lenses: normalizedLenses,
                scratchDrafts: scratchDrafts,
                selectedLensId: normalizedLenses.first?.lensId,
                selectedScratchId: nil,
                changeSummary: "Updated Scene Plan media.",
                model: "local-edit",
                now: now
            )
            return
        }
        versions[index].lenses = normalizedLenses
        updatedAt = now
    }

    mutating func restore(versionId: String, now: String) {
        guard versions.contains(where: { $0.versionId == versionId }) else { return }
        activeVersionId = versionId
        markLensBodyVersionsActive(forLensSetVersionId: versionId)
        updatedAt = now
    }

    private mutating func backfillLensBodyVersionsFromSetVersions() {
        guard lensBodyVersions.isEmpty, !versions.isEmpty else { return }
        let originalActiveVersionId = activeVersionId
        let originalUpdatedAt = updatedAt
        for version in versions {
            appendLensBodyVersions(
                for: version.lenses,
                sourceLensSetVersionId: version.versionId,
                turnIndex: version.turnIndex,
                changeSummary: version.changeSummary,
                model: version.model,
                now: version.createdAt
            )
        }
        pruneLensBodyVersions(retainedLensSetVersionIds: Set(versions.map(\.versionId)))
        activeVersionId = originalActiveVersionId
        if !activeVersionId.isEmpty {
            markLensBodyVersionsActive(forLensSetVersionId: activeVersionId)
        }
        updatedAt = originalUpdatedAt
    }

    private mutating func appendLensBodyVersions(
        for lenses: [ProjectLens],
        sourceLensSetVersionId: String,
        turnIndex: Int,
        changeSummary: String,
        model: String,
        now: String
    ) {
        for lens in lenses {
            let normalized = lens.normalized()
            let contentFingerprint = stableHash(normalized, length: 64)
            let latest = lensBodyVersions
                .filter { $0.lensId == normalized.lensId }
                .sorted { $0.createdAt < $1.createdAt }
                .last
            guard latest?.contentFingerprint != contentFingerprint else {
                continue
            }
            for index in lensBodyVersions.indices where lensBodyVersions[index].lensId == normalized.lensId {
                lensBodyVersions[index].isActive = false
            }
            lensBodyVersions.append(ProjectLensBodyVersion(
                versionId: "lens_body_\(shortHash("\(projectId):\(normalized.lensId):\(sourceLensSetVersionId):\(contentFingerprint)", length: 14))",
                lensId: normalized.lensId,
                sourceLensSetVersionId: sourceLensSetVersionId,
                turnIndex: turnIndex,
                changeSummary: changeSummary,
                model: model,
                createdAt: now,
                contentFingerprint: contentFingerprint,
                isActive: true
            ))
        }
    }

    private mutating func pruneLensBodyVersions(retainedLensSetVersionIds: Set<String>) {
        let grouped = Dictionary(grouping: lensBodyVersions.map { $0.normalized() }) { $0.lensId }
        var output: [ProjectLensBodyVersion] = []
        for lensId in grouped.keys.sorted() {
            let versions = (grouped[lensId] ?? [])
                .filter { retainedLensSetVersionIds.contains($0.sourceLensSetVersionId) }
                .sorted { $0.createdAt < $1.createdAt }
            output.append(contentsOf: versions.suffix(Self.maximumLensBodyVersionsPerLens))
        }
        lensBodyVersions = output.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.versionId < $1.versionId
            }
            return $0.createdAt < $1.createdAt
        }
    }

    private mutating func markLensBodyVersionsActive(forLensSetVersionId versionId: String) {
        let activeLensIds = Set(
            lensBodyVersions
                .filter { $0.sourceLensSetVersionId == versionId }
                .map(\.lensId)
        )
        for index in lensBodyVersions.indices where activeLensIds.contains(lensBodyVersions[index].lensId) {
            lensBodyVersions[index].isActive = lensBodyVersions[index].sourceLensSetVersionId == versionId
        }
    }

    private mutating func canonicalizeToSingleLens() {
        let canonicalLensId = activeVersion?.lenses.first?.lensId.trimmed.nilIfEmpty
            ?? versions.flatMap(\.lenses).first?.lensId.trimmed.nilIfEmpty

        if let canonicalLensId {
            // Unhydrated versions are skipped, not cleared: their empty
            // `lenses` means "not loaded", and rewriting them here would make
            // the emptiness look authoritative to the save path.
            for index in versions.indices where hasHydratedLenses(versions[index].versionId) {
                let retainedLenses = versions[index].lenses
                    .map { $0.normalized() }
                    .filter { $0.lensId == canonicalLensId }
                    .prefix(1)
                versions[index].lenses = Array(retainedLenses)
                versions[index].scratchDrafts = []
                versions[index].selectedLensId = versions[index].lenses.first?.lensId
                versions[index].selectedScratchId = nil
            }
            if activeVersion?.lenses.isEmpty != false,
               let fallback = versions.last(where: { !$0.lenses.isEmpty && hasHydratedLenses($0.versionId) }) {
                activeVersionId = fallback.versionId
            }
            lensEditMessages = lensEditMessages
                .map { $0.normalized() }
                .filter { $0.lensId == canonicalLensId }
            lensBodyVersions = lensBodyVersions
                .map { $0.normalized() }
                .filter { $0.lensId == canonicalLensId }
            messages = messages.map { message in
                var updated = message
                if updated.targetLensId?.trimmed != canonicalLensId {
                    updated.targetLensId = nil
                }
                updated.targetScratchId = nil
                return updated
            }
            if !activeVersionId.isEmpty {
                markLensBodyVersionsActive(forLensSetVersionId: activeVersionId)
            }
        } else {
            // No lens anywhere. Under lazy loading this is trustworthy because
            // the loader always hydrates the newest lens-bearing version, so a
            // nil canonical id means the stored history has no lens either.
            for index in versions.indices where hasHydratedLenses(versions[index].versionId) {
                versions[index].lenses = []
                let scratch = versions[index].scratchDrafts.first?.normalized()
                versions[index].scratchDrafts = scratch.map { [$0] } ?? []
                versions[index].selectedLensId = nil
                versions[index].selectedScratchId = scratch?.scratchId
            }
            lensEditMessages = []
            lensBodyVersions = []
        }
    }
}

struct ProjectLensWorkbenchInterviewResponseV1: Codable, Hashable {
    var schemaVersion: String = "litscenes.project_lens_workbench_interview_response.v0.1"
    var assistantMessage: String
    var body: LensBodyProposal
    var changeSummary: String

    static func decode(from data: Data) throws -> ProjectLensWorkbenchInterviewResponseV1 {
        try JSONCoding.decoder.decode(ProjectLensWorkbenchInterviewResponseV1.self, from: data)
    }
}

extension ProjectAestheticDirectionRecipe {
    func lensStyleIngredient(order: Int, now: String = DateFormats.now()) -> LensStyleIngredient {
        LensStyleIngredient(
            ingredientId: "ingredient_\(shortHash("\(recipeId):\(order):\(now)", length: 12))",
            order: order,
            enabled: true,
            title: title,
            role: lane.isEmpty ? "ingredient" : lane,
            narrativeUse: visualSummary,
            presentationUse: treatmentNotes.joined(separator: ", "),
            notes: "",
            paletteTerms: paletteTerms,
            motifTerms: signatureTerms,
            avoidTerms: avoidTerms,
            referenceAestheticIds: selectedReferences.map(\.aestheticId),
            sourceRecipeId: recipeId,
            sourceRecipeVersion: recipeVersion,
            sourceReferenceIds: selectedReferences.map(\.aestheticId),
            updatedAt: now
        )
    }
}

func draftProjectLens(
    from card: AestheticDirectionCard,
    projectId: String,
    heroImage: ProjectLensHeroImage? = nil,
    heroImages: [ProjectLensHeroImage] = [],
    now: String = DateFormats.now()
) -> ProjectLens {
    let recipe = card.recipe(projectId: projectId)
    let ingredient = recipe.lensStyleIngredient(order: 1, now: now)
    let claim = card.fitReason.trimmed.isEmpty
        ? "A project-local visual route built from \(card.coreItem.title)."
        : card.fitReason
    let sourceLabels = uniqueNonEmpty(
        [card.directionLabel, card.coreItem.title] + card.flavorItems.map(\.title)
    )
    let colorPalette = uniqueLensColorSwatches(card.paletteSwatches.enumerated().compactMap { index, swatch in
        LensColorSwatch.from(indexSwatch: swatch, role: index == 0 ? "primary" : "supporting")
    })
    let body = LensBody(
        title: card.directionLabel,
        claim: claim,
        userNotes: "",
        visualSummary: card.visualSummary,
        resolvedVisualLanguage: LensResolvedVisualLanguage(
            look: card.visualSummary,
            palette: uniqueNonEmpty(card.paletteTerms),
            materials: [],
            productTreatment: [],
            motifs: uniqueNonEmpty(card.signatureTerms),
            composition: [],
            pacingEnergy: [],
            avoid: lensLiteralVisualAvoidTerms(card.avoidTerms)
        ),
        colorPalette: colorPalette,
        styleIngredients: [ingredient],
        paletteTerms: uniqueNonEmpty(card.paletteTerms + card.paletteSwatches.map(\.colorFamily)),
        motifTerms: uniqueNonEmpty(card.signatureTerms),
        textureMaterialTerms: uniqueNonEmpty(card.treatmentNotes),
        compositionTerms: uniqueNonEmpty(card.bestAppliedTo),
        pacingEnergyTerms: [],
        mustPreserve: uniqueNonEmpty(card.evidence),
        mustAvoid: lensLiteralVisualAvoidTerms(card.avoidTerms + card.conflicts),
        referenceMediaIds: [],
        openQuestions: uniqueNonEmpty(card.gaps),
        readinessSummary: "Scene Plan generated from the Goal. Review any warnings before it guides Scenes.",
        derivedVirtues: uniqueNonEmpty(card.bestAppliedTo)
    ).sanitizedForGeneratedDraft(sourceLabels: sourceLabels)
    return ProjectLens(
        lensId: "lens_\(shortHash("\(projectId):\(card.cardId):\(now)", length: 12))",
        status: .ready,
        enabled: true,
        body: body,
        heroImage: heroImage,
        heroImages: heroImages,
        relationSummary: .empty,
        createdAt: now,
        updatedAt: now
    ).normalized()
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
