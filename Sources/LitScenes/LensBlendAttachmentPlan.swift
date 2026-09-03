import Foundation

/// One image attached to a Lens media generation request: which role it plays, the exact
/// filename it is attached under, and the manifest line that describes it in the prompt.
/// The plan is the single source of truth — attachment order, filenames, and prompt
/// manifest all derive from the same entries, so they cannot desynchronize.
struct LensBlendAttachmentEntry: Hashable, Sendable {
    enum Role: String, Sendable {
        case primary
        case accent
        case subjectAnchor = "subject_anchor"
        case characterReference = "character_reference"
        case continuity
        case promptImage = "prompt_image"
    }

    var role: Role
    /// 1-based index within the role (accent 1 vs 2, continuity 1..n).
    var roleIndex: Int
    /// Normalized blend share for style entries; 0 for non-style entries.
    var sharePercent: Int
    /// Verified remote style reference (style entries).
    var reference: SREFStyleImageReference?
    /// Local file (subject anchor, character reference, and continuity entries).
    var localURL: URL?
    /// Unique character name for character reference entries.
    var characterName: String?
    /// Human caption for subject anchor entries.
    var caption: String?
    /// Exact multipart filename, weight-bearing for style entries
    /// ("style-ref-1-primary-60pct.png").
    var attachmentFilename: String
    /// The manifest sentence for this entry, without its leading index.
    var promptDescriptor: String

    var isStyle: Bool { role == .primary || role == .accent }
}

/// Deterministic resolver from a Lens's style treatment (plus character/continuity inputs)
/// to the ordered attachment list for one image generation call. Pure and testable: no
/// network, no engine state.
struct LensBlendAttachmentPlan: Sendable {
    /// Multipart image inputs beyond this count are dropped by priority (continuity first,
    /// then extra per-character references); the API accepts a bounded image[] list.
    static let maxAttachments = 10

    var entries: [LensBlendAttachmentEntry] = []
    /// Human-readable notes for anything the resolver had to drop or could not resolve.
    var warnings: [String] = []
    /// One-line render-oriented description of the ATTACHED style (the frame's assigned
    /// style), from the catalog's style-reference analysis. Injected verbatim into the
    /// prompt beside the style image — a single disciplined line, never enriched; the
    /// image remains the sole rendering authority.
    var styleSummaryText: String = ""

    var isEmpty: Bool { entries.isEmpty }
    var styleEntries: [LensBlendAttachmentEntry] { entries.filter(\.isStyle) }
    var characterEntries: [LensBlendAttachmentEntry] { entries.filter { $0.role == .characterReference } }
    var continuityEntries: [LensBlendAttachmentEntry] { entries.filter { $0.role == .continuity } }

    /// A named character with its ordered local reference images. `labels` aligns with
    /// `urls` (empty string = unlabeled): a user label like "young Ava" rides the
    /// attachment's manifest descriptor so generation knows what that image shows.
    struct CharacterReferenceInput: Sendable {
        var name: String
        var urls: [URL]
        var labels: [String]

        init(name: String, urls: [URL], labels: [String] = []) {
            self.name = name
            self.urls = urls
            self.labels = labels
        }
    }

    static func make(
        treatment: LensStyleTreatment?,
        ingredients: [LensStyleIngredient],
        catalog: StyleBrowseCatalog? = nil,
        assignedStyleId: String? = nil,
        subjectAnchor: (caption: String, url: URL)? = nil,
        characterReferences: [CharacterReferenceInput] = [],
        continuityURLs: [URL] = [],
        sequenceContinuity: Bool = false
    ) -> LensBlendAttachmentPlan {
        var plan = LensBlendAttachmentPlan()
        let normalizedTreatment = treatment?.normalized()

        // ONE style reference per generation — the image model follows a single "in the
        // style of the attached image" example but ignores prose-weighted multi-style
        // blending. The treatment's weights allocate WHICH style each frame gets
        // (styleFrameAssignments); this plan attaches only the assigned style.
        if let normalizedTreatment, !normalizedTreatment.isEmpty {
            let slots = normalizedTreatment.slots
            let shares = normalizedTreatment.blendShares()
            let assignedIndex: Int
            if let assignedStyleId, let found = slots.firstIndex(where: { $0.styleId == assignedStyleId }) {
                assignedIndex = found
            } else {
                if let assignedStyleId {
                    plan.warnings.append("Assigned style \(assignedStyleId) is no longer in the treatment; using the primary instead.")
                }
                assignedIndex = 0
            }
            let slot = slots[assignedIndex]
            let ingredientReferences = decodedIngredientReferences(ingredients)
            if let reference = resolveStyleReference(
                slot: slot,
                ingredientReferences: ingredientReferences,
                catalog: catalog
            ) {
                plan.entries.append(LensBlendAttachmentEntry(
                    role: assignedIndex == 0 ? .primary : .accent,
                    roleIndex: assignedIndex == 0 ? 1 : assignedIndex,
                    sharePercent: shares.indices.contains(assignedIndex) ? shares[assignedIndex] : 0,
                    reference: reference,
                    localURL: nil,
                    characterName: nil,
                    caption: nil,
                    attachmentFilename: "style-ref.\(fileExtension(forMimeType: reference.mimeType))",
                    promptDescriptor: "THE STYLE — this generation renders entirely in this image's style."
                ))
                plan.styleSummaryText = catalog?.style(withId: slot.styleId)?.styleSummaryLine ?? ""
            } else {
                plan.warnings.append(
                    "Style \"\(slot.label.isEmpty ? slot.styleId : slot.label)\" has no verifiable reference image; generation proceeds prompt-only."
                )
            }
        } else {
            // Treatmentless lenses (legacy scratch drafts built from reference cards
            // alone) attach their first decodable reference as the single style.
            if let reference = decodedIngredientReferences(ingredients).first {
                plan.entries.append(LensBlendAttachmentEntry(
                    role: .primary,
                    roleIndex: 1,
                    sharePercent: 0,
                    reference: reference,
                    localURL: nil,
                    characterName: nil,
                    caption: nil,
                    attachmentFilename: "style-ref.\(fileExtension(forMimeType: reference.mimeType))",
                    promptDescriptor: "THE STYLE — this generation renders entirely in this image's style."
                ))
                plan.styleSummaryText = catalog?.style(withId: reference.itemId)?.styleSummaryLine ?? ""
            }
        }

        // Canonical subject anchor: a literal asset that appears AS ITSELF, between the
        // styles (whose rule it inverts) and the character references.
        if let subjectAnchor {
            let caption = subjectAnchor.caption.trimmed.isEmpty ? "canonical subject" : subjectAnchor.caption.trimmed
            plan.entries.append(LensBlendAttachmentEntry(
                role: .subjectAnchor,
                roleIndex: 1,
                sharePercent: 0,
                reference: nil,
                localURL: subjectAnchor.url,
                characterName: nil,
                caption: caption,
                attachmentFilename: "subject-anchor-1.\(fileExtension(forURL: subjectAnchor.url))",
                promptDescriptor: "SUBJECT anchor — this exact \(caption) must appear as itself in the scene. It is subject matter, not a style reference: keep its recognizable form and features while rendering it in this treatment's style."
            ))
        }

        // Character references, in selection order, keyed by unique name.
        var usedCharacterSlugs: Set<String> = []
        for character in characterReferences {
            let name = character.name.trimmed
            guard !name.isEmpty, !character.urls.isEmpty else { continue }
            var slug = Self.slug(name)
            var dedupe = 1
            while usedCharacterSlugs.contains(slug) {
                dedupe += 1
                slug = "\(Self.slug(name))-\(dedupe)"
            }
            usedCharacterSlugs.insert(slug)
            for (urlIndex, url) in character.urls.enumerated() {
                let filename = "character-ref-\(slug)-\(urlIndex + 1).\(fileExtension(forURL: url))"
                let label = character.labels.indices.contains(urlIndex) ? character.labels[urlIndex].trimmed : ""
                var descriptor = "CHARACTER reference for \"\(name)\": this exact figure appears in the scene; match their appearance, build, and distinguishing features from this image. It is subject matter, not a style reference — render \"\(name)\" in this treatment's style."
                if !label.isEmpty {
                    descriptor += " This particular reference shows: \(label)."
                }
                plan.entries.append(LensBlendAttachmentEntry(
                    role: .characterReference,
                    roleIndex: urlIndex + 1,
                    sharePercent: 0,
                    reference: nil,
                    localURL: url,
                    characterName: name,
                    caption: nil,
                    attachmentFilename: filename,
                    promptDescriptor: descriptor
                ))
            }
        }

        // Continuity images from earlier renders in the same run, always last. They carry
        // WORLD continuity only — geography, recurring subjects, staging. Rendering and
        // palette language is forbidden here: the style image alone governs rendering,
        // and continuity frames may have rendered in a different allocated style.
        for (index, url) in continuityURLs.enumerated() {
            let isImmediatePredecessor = sequenceContinuity && index == continuityURLs.count - 1
            let descriptor: String
            if isImmediatePredecessor {
                descriptor = "the immediately preceding frame of this same continuous journey: keep the location's geography, recurring subjects, and staging consistent, and advance the camera per this frame's beat. Take NO palette, lighting character, or rendering from it — the style image alone governs rendering."
            } else if sequenceContinuity {
                descriptor = "an earlier frame of this same continuous journey at this location: keep its geography, recurring subjects, and staging consistent. Take NO palette or rendering from it — the style image alone governs rendering."
            } else {
                descriptor = "this same world already rendered: keep its geography, recurring subjects, and staging consistent; this image depicts a different scene. Take NO palette, lighting character, or rendering from it — the style image alone governs rendering."
            }
            plan.entries.append(LensBlendAttachmentEntry(
                role: .continuity,
                roleIndex: index + 1,
                sharePercent: 0,
                reference: nil,
                localURL: url,
                characterName: nil,
                caption: nil,
                attachmentFilename: "continuity-\(index + 1)-rendered-world.\(fileExtension(forURL: url))",
                promptDescriptor: descriptor
            ))
        }

        plan.enforceAttachmentCap()
        return plan
    }

    /// OpenAI can execute the selected style and prompt-image controls together. The
    /// style remains first so the preamble and manifest positions describe the payload
    /// exactly; prompt references follow in their original order.
    static func combiningStyleAndPromptReferences(
        stylePlan: LensBlendAttachmentPlan,
        promptPlan: LensBlendAttachmentPlan
    ) -> LensBlendAttachmentPlan {
        var plan = stylePlan
        plan.entries.append(contentsOf: promptPlan.entries)
        plan.warnings.append(contentsOf: promptPlan.warnings)
        plan.enforceAttachmentCap()
        return plan
    }

    /// The verbatim opener prepended to the prompt (before the enriched description):
    /// the single-style directive the image model actually follows.
    var promptPreamble: String {
        guard !styleEntries.isEmpty else { return "" }
        if entries.count == 1 {
            return "In the style of the attached image, generate the following:"
        }
        return "In the style of the first attached image, generate the following:"
    }

    /// The verbatim prompt manifest for the NON-style attachments (anchor, characters,
    /// continuity), numbered by their true positions in the attachment order. Appended to
    /// the prompt AFTER any LLM enrichment so filenames and order survive untouched. The
    /// style image itself is covered by the preamble, plus a hard style-only rule here.
    func manifestLines() -> [String] {
        manifestEntryLines() + (manifestPolicyText.isEmpty ? [] : [manifestPolicyText])
    }

    /// The per-job (dynamic) manifest lines: the attachment list with filenames and
    /// descriptors. On the Responses path these stay in the USER prompt while the static
    /// policy moves to the system instructions.
    func manifestEntryLines() -> [String] {
        guard !entries.isEmpty else { return [] }
        var lines: [String] = []
        let nonStyle = entries.enumerated().filter { !$0.element.isStyle }
        if !nonStyle.isEmpty {
            lines.append(styleEntries.isEmpty
                ? "Attached reference images, in this exact order:"
                : "Additional attached images, after the style image, in this exact order:")
            for (position, entry) in nonStyle {
                lines.append("\(position + 1). \(entry.attachmentFilename) — \(entry.promptDescriptor)")
            }
        }
        return lines
    }

    /// The static style-only rule — identical for every style-backed generation.
    var manifestPolicyText: String {
        guard !styleEntries.isEmpty else { return "" }
        return "Match the style image's rendering technique, palette behavior, surface texture, and lighting character exactly. Never copy its subject matter, its composition, or any internal panel borders it contains."
    }

    var manifestText: String {
        manifestLines().joined(separator: "\n")
    }

    var manifestEntryLinesText: String {
        manifestEntryLines().joined(separator: "\n")
    }

    static func slug(_ value: String) -> String {
        let lowered = value.lowercased()
        var out = ""
        var lastWasDash = true
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar), scalar.isASCII {
                out.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") {
            out.removeLast()
        }
        return out.isEmpty ? "unnamed" : out
    }

    // MARK: - Private

    private mutating func enforceAttachmentCap() {
        guard entries.count > Self.maxAttachments else { return }
        // Drop trailing continuity first.
        while entries.count > Self.maxAttachments,
              let lastContinuity = entries.lastIndex(where: { $0.role == .continuity }) {
            warnings.append("Dropped \(entries[lastContinuity].attachmentFilename): attachment limit of \(Self.maxAttachments) images.")
            entries.remove(at: lastContinuity)
        }
        // Then extra per-character references (keep each character's first).
        while entries.count > Self.maxAttachments,
              let extraCharacter = entries.lastIndex(where: { $0.role == .characterReference && $0.roleIndex > 1 }) {
            warnings.append("Dropped \(entries[extraCharacter].attachmentFilename): attachment limit of \(Self.maxAttachments) images.")
            entries.remove(at: extraCharacter)
        }
        while entries.count > Self.maxAttachments {
            warnings.append("Dropped \(entries[entries.count - 1].attachmentFilename): attachment limit of \(Self.maxAttachments) images.")
            entries.removeLast()
        }
    }

    private static func decodedIngredientReferences(_ ingredients: [LensStyleIngredient]) -> [SREFStyleImageReference] {
        uniqueNonEmpty(ingredients.flatMap(\.sourceReferenceIds))
            .compactMap { SREFStyleImageReference.decodeSourceReferenceId($0) }
    }

    private static func resolveStyleReference(
        slot: LensStyleTreatmentSlot,
        ingredientReferences: [SREFStyleImageReference],
        catalog: StyleBrowseCatalog?
    ) -> SREFStyleImageReference? {
        if let match = ingredientReferences.first(where: { $0.itemId == slot.styleId }) {
            return match
        }
        if let catalog,
           let style = catalog.style(withId: slot.styleId),
           let reference = style.styleImageReference(catalogVersion: catalog.version) {
            return reference
        }
        return nil
    }

    private static func fileExtension(forMimeType mimeType: String) -> String {
        let lowered = mimeType.lowercased()
        return lowered.contains("jpeg") || lowered.contains("jpg") ? "jpg" : "png"
    }

    private static func fileExtension(forURL url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ext == "png" ? "png" : "jpg"
    }
}
