import Foundation

/// Lens-free prompt composer for roster character reference renders — the
/// manage-character modal's "smart prompt" seed. Mirrors lensCharacterConceptPrompt's
/// isolated-study language without any lens coupling (no style treatment, no media
/// plan, no closing lines): these are subject-only renders whose output feeds the
/// character's reference pool.
enum RosterCharacterRenderPrompt {
    enum Shot: String, CaseIterable, Identifiable {
        case fullFigure
        case threeQuarter
        case portrait

        var id: String { rawValue }

        var label: String {
            switch self {
            case .fullFigure: return "FULL FIGURE"
            case .threeQuarter: return "THREE-QUARTER"
            case .portrait: return "PORTRAIT"
            }
        }

        /// OpenAI image size; FAL sizes are static per stack, CivitAI reorients
        /// the stack's declared canvas via `civitaiSize(declared:)`.
        var openAIImageSize: String {
            switch self {
            case .fullFigure, .threeQuarter: return "1024x1536"
            case .portrait: return "1024x1024"
            }
        }

        /// Reorients a CivitAI stack's declared pixel budget to this shot —
        /// never invents a new one. A tall study turns the declared long edge
        /// vertical; a portrait study squares on the short edge. Without this,
        /// the FRAMES 16:9 landscape fought the "tall vertical" prompt and the
        /// model split the difference badly.
        func civitaiSize(declared: (width: Int, height: Int)) -> (width: Int, height: Int) {
            let long = max(declared.width, declared.height)
            let short = min(declared.width, declared.height)
            switch self {
            case .fullFigure, .threeQuarter: return (short, long)
            case .portrait: return (short, short)
            }
        }

        /// LensMediaPlan aspect the job carries for provider parameter builders.
        var aspect: String {
            switch self {
            case .fullFigure, .threeQuarter: return "portrait"
            case .portrait: return "square"
            }
        }

        fileprivate var opener: String {
            switch self {
            case .fullFigure, .threeQuarter:
                return "Create one tall vertical character concept study."
            case .portrait:
                return "Create one square character portrait study."
            }
        }

        fileprivate var framingLine: String {
            switch self {
            case .fullFigure:
                return "Show the full figure head to toe, prominent in the frame. One figure only — no lineup, no panels."
            case .threeQuarter:
                return "Frame the figure from head to mid-thigh — a three-quarter view, prominent in the frame. One figure only — no lineup, no panels."
            case .portrait:
                return "Frame head and shoulders — a close portrait study, the face sharply resolved. One figure only — no lineup, no panels."
            }
        }
    }

    static func prompt(name: String, description: String, signatureProps: [String], shot: Shot) -> String {
        var lines: [String] = [shot.opener]
        let subject = name.trimmed.isEmpty ? "the character" : "\"\(name.trimmed)\""
        let trimmedDescription = description.trimmed
        lines.append(trimmedDescription.isEmpty ? "The subject: \(subject)." : "The subject: \(subject) — \(trimmedDescription)")
        let props = uniqueNonEmpty(signatureProps)
        if !props.isEmpty {
            lines.append("Always with them: \(props.joined(separator: "; ")).")
        }
        lines.append(shot.framingLine)
        lines.append("The figure stands alone as a clean isolated character study: no environment, no floor plane, no backdrop, no cast scenery — only the figure, their clothing, and what they carry.")
        lines.append("Do not render readable text; any typography stays graphic and minimal.")
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Which of a character's references anchor a generation, mirroring the Frame
    /// Creator's @mention preference: the active generated character sheet alone when
    /// one exists, else the composite sheet alone (several labeled views in one slot),
    /// else the leading two loose references; `capOne` (FAL's single reference slot)
    /// keeps only the first. On-disk images only.
    static func identityAnchorPicks(
        referenced: [MediaItemRecord],
        referenceLabels: [String: String],
        capOne: Bool,
        activeSheet: MediaItemRecord? = nil,
        looseReferenceFallback: Bool = true,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [(item: MediaItemRecord, label: String, isSheet: Bool)] {
        if let activeSheet, activeSheet.kind == .image, fileExists(activeSheet.path) {
            return [(activeSheet, "character sheet", true)]
        }
        // Sheet-only identity: without a rendered sheet nothing anchors — the
        // composite is the loose references tiled into one slot, so it is skipped too.
        guard looseReferenceFallback else { return [] }
        let onDisk = referenced.filter { $0.kind == .image && fileExists($0.path) }
        if let sheet = onDisk.first(where: { $0.isRosterCompositeSheet }) {
            return [(sheet, referenceLabels[sheet.mediaId] ?? "reference sheet", true)]
        }
        let leading = onDisk.filter { !$0.isRosterCompositeSheet }.prefix(capOne ? 1 : 2)
        return leading.map { ($0, referenceLabels[$0.mediaId] ?? "", false) }
    }

    /// THE SHEET RENDER INPUT LAW: what a character SHEET render attaches — the active
    /// sheet first (continuity), then the leading source images in the operator's
    /// order, `capacity` images in all. Composite sheets never ride (their sources do);
    /// zero capacity attaches nothing; on-disk images only.
    static func sheetRenderPicks(
        activeSheet: MediaItemRecord?,
        sources: [MediaItemRecord],
        referenceLabels: [String: String],
        capacity: Int,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [CharacterSheetRenderPick] {
        guard capacity > 0 else { return [] }
        var picks: [CharacterSheetRenderPick] = []
        if let activeSheet, activeSheet.kind == .image, fileExists(activeSheet.path) {
            picks.append(CharacterSheetRenderPick(item: activeSheet, label: "character sheet", role: .activeSheet))
        }
        for source in sources {
            guard picks.count < capacity else { break }
            guard source.kind == .image,
                  !source.isRosterCompositeSheet,
                  source.mediaId != activeSheet?.mediaId,
                  !picks.contains(where: { $0.item.mediaId == source.mediaId }),
                  fileExists(source.path) else { continue }
            picks.append(CharacterSheetRenderPick(item: source, label: referenceLabels[source.mediaId] ?? "", role: .sourceImage))
        }
        return picks
    }
}

/// One image a character sheet render attaches, with the role the manifest states.
struct CharacterSheetRenderPick: Hashable {
    enum Role: Hashable {
        case activeSheet
        case sourceImage
    }

    var item: MediaItemRecord
    var label: String
    var role: Role

    var isSheet: Bool { role == .activeSheet }
}
