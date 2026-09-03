import AppKit
import Foundation

/// The project's defining sheets: a small set of 16:9 composites that capture
/// what the project IS so far — the Scene Plan's claim, look, and palette
/// (Cover), its style anchors (Style), the cast (Cast), and the rendered
/// frames (Frames). Shareable as images, and paired with a JSON manifest so
/// the set can re-compose the project later. Sibling composer to
/// RosterCompositeSheet / RenderReferenceComposite: pure geometry + one
/// flipped NSImage drawing handler, nothing engine-aware.
enum ProjectSheet {
    enum Kind: String, CaseIterable, Codable {
        case cover
        case style
        case cast
        case frames

        var displayName: String {
            switch self {
            case .cover: return "Cover Sheet"
            case .style: return "Style Sheet"
            case .cast: return "Cast Sheet"
            case .frames: return "Frames Sheet"
            }
        }

        var subtitle: String {
            "LITSCENES PROJECT SHEET · \(rawValue.uppercased())"
        }
    }

    static let canvasSize = CGSize(width: 1_920, height: 1_080)
    static let maxGridCells = 6

    private static let paper = NSColor(srgbRed: 0.957, green: 0.937, blue: 0.894, alpha: 1)
    private static let captionWell = NSColor(srgbRed: 0.906, green: 0.851, blue: 0.737, alpha: 1)
    private static let ink = NSColor(srgbRed: 0.106, green: 0.090, blue: 0.067, alpha: 1)

    struct CoverContent: Equatable {
        var projectTitle = ""
        var claim = ""
        var visualSummary = ""
        /// (label, joined terms) rows — empty rows are skipped.
        var termLines: [(label: String, terms: [String])] = []
        /// (name, hex) — hexes render as swatch squares.
        var palette: [(name: String, hex: String)] = []
        var storyTitle = ""
        var goalSliceTitle = ""

        static func == (lhs: CoverContent, rhs: CoverContent) -> Bool {
            lhs.projectTitle == rhs.projectTitle
                && lhs.claim == rhs.claim
                && lhs.visualSummary == rhs.visualSummary
                && lhs.termLines.count == rhs.termLines.count
                && zip(lhs.termLines, rhs.termLines).allSatisfy { $0.label == $1.label && $0.terms == $1.terms }
                && lhs.palette.count == rhs.palette.count
                && zip(lhs.palette, rhs.palette).allSatisfy { $0.name == $1.name && $0.hex == $1.hex }
                && lhs.storyTitle == rhs.storyTitle
                && lhs.goalSliceTitle == rhs.goalSliceTitle
        }
    }

    private static func serifFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.serif),
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return base
    }

    private static func swatchColor(_ hex: String) -> NSColor {
        let cleaned = hex.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let intValue = Int(cleaned, radix: 16) else { return captionWell }
        return NSColor(
            srgbRed: CGFloat((intValue >> 16) & 0xFF) / 255,
            green: CGFloat((intValue >> 8) & 0xFF) / 255,
            blue: CGFloat(intValue & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func drawHeader(title: String, subtitle: String) {
        let headline = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
            .foregroundColor: ink,
            .kern: 2.2
        ])
        headline.draw(at: CGPoint(x: 48, y: 20))
        NSAttributedString(string: subtitle, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium),
            .foregroundColor: ink.withAlphaComponent(0.58),
            .kern: 2.4
        ]).draw(at: CGPoint(x: 48, y: 56))
        ink.withAlphaComponent(0.35).setFill()
        CGRect(x: 48, y: 84, width: canvasSize.width - 96, height: 2).fill()
    }

    private static func encodePNG(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// The text-led Cover: claim, look paragraph, term rows, palette band, and
    /// a story/slice footer. Fixed vertical zones keep the drawing dependable
    /// for arbitrary content lengths (long text truncates, never overflows).
    static func renderCoverPNG(content: CoverContent) -> Data? {
        guard !content.claim.trimmed.isEmpty || !content.projectTitle.trimmed.isEmpty else { return nil }
        let image = NSImage(size: canvasSize, flipped: true) { _ in
            paper.setFill()
            CGRect(origin: .zero, size: canvasSize).fill()
            drawHeader(
                title: content.projectTitle.trimmed.isEmpty ? "LitScenes Project" : content.projectTitle,
                subtitle: Kind.cover.subtitle
            )

            let bodyParagraph = NSMutableParagraphStyle()
            bodyParagraph.lineBreakMode = .byTruncatingTail

            if !content.claim.trimmed.isEmpty {
                NSAttributedString(string: content.claim, attributes: [
                    .font: serifFont(size: 54, weight: .semibold),
                    .foregroundColor: ink,
                    .paragraphStyle: bodyParagraph
                ]).draw(in: CGRect(x: 48, y: 128, width: canvasSize.width - 96, height: 290))
            }

            if !content.visualSummary.trimmed.isEmpty {
                NSAttributedString(string: content.visualSummary, attributes: [
                    .font: serifFont(size: 24, weight: .regular),
                    .foregroundColor: ink.withAlphaComponent(0.75),
                    .paragraphStyle: bodyParagraph
                ]).draw(in: CGRect(x: 48, y: 436, width: canvasSize.width - 96, height: 160))
            }

            let termParagraph = NSMutableParagraphStyle()
            termParagraph.lineBreakMode = .byTruncatingTail
            var termY: CGFloat = 622
            for line in content.termLines where !line.terms.isEmpty {
                guard termY < 790 else { break }
                let text = NSMutableAttributedString()
                text.append(NSAttributedString(string: line.label.uppercased() + "   ", attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .semibold),
                    .foregroundColor: ink.withAlphaComponent(0.5),
                    .kern: 1.6,
                    .paragraphStyle: termParagraph
                ]))
                text.append(NSAttributedString(string: line.terms.joined(separator: " · "), attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 17, weight: .medium),
                    .foregroundColor: ink.withAlphaComponent(0.82),
                    .kern: 0.4,
                    .paragraphStyle: termParagraph
                ]))
                text.draw(in: CGRect(x: 48, y: termY, width: canvasSize.width - 96, height: 30))
                termY += 42
            }

            let swatches = Array(content.palette.prefix(8))
            if !swatches.isEmpty {
                let swatchWidth: CGFloat = 120
                let swatchHeight: CGFloat = 90
                let spacing: CGFloat = 24
                for (index, swatch) in swatches.enumerated() {
                    let x = 48 + CGFloat(index) * (swatchWidth + spacing)
                    let rect = CGRect(x: x, y: 812, width: swatchWidth, height: swatchHeight)
                    swatchColor(swatch.hex).setFill()
                    NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
                    ink.withAlphaComponent(0.25).setStroke()
                    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
                    border.lineWidth = 1
                    border.stroke()
                    let hexParagraph = NSMutableParagraphStyle()
                    hexParagraph.lineBreakMode = .byTruncatingTail
                    NSAttributedString(string: swatch.hex.uppercased(), attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium),
                        .foregroundColor: ink.withAlphaComponent(0.62),
                        .paragraphStyle: hexParagraph
                    ]).draw(in: CGRect(x: x, y: 912, width: swatchWidth, height: 22))
                    NSAttributedString(string: swatch.name, attributes: [
                        .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                        .foregroundColor: ink.withAlphaComponent(0.5),
                        .paragraphStyle: hexParagraph
                    ]).draw(in: CGRect(x: x, y: 936, width: swatchWidth, height: 22))
                }
            }

            let footerParts = [
                content.storyTitle.trimmed.isEmpty ? "" : "STORY · \(content.storyTitle)",
                content.goalSliceTitle.trimmed.isEmpty ? "" : "SLICE · \(content.goalSliceTitle)"
            ].filter { !$0.isEmpty }
            if !footerParts.isEmpty {
                let footerParagraph = NSMutableParagraphStyle()
                footerParagraph.lineBreakMode = .byTruncatingTail
                NSAttributedString(string: footerParts.joined(separator: "      "), attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium),
                    .foregroundColor: ink.withAlphaComponent(0.55),
                    .kern: 1.2,
                    .paragraphStyle: footerParagraph
                ]).draw(in: CGRect(x: 48, y: 1_030, width: canvasSize.width - 96, height: 24))
            }
            return true
        }
        return encodePNG(image)
    }

    /// Shared 16:9 labeled grid for the Style / Cast / Frames sheets. Same
    /// column math as RenderReferenceComposite (1-2 across, 2×2, 3-wide) with
    /// the project-sheet header, PNG output.
    static func renderGridPNG(kind: Kind, title: String, cells rawCells: [(image: NSImage, caption: String)]) -> Data? {
        let cells = Array(rawCells.prefix(maxGridCells))
        guard !cells.isEmpty else { return nil }
        let columns = cells.count <= 2 ? cells.count : (cells.count <= 4 ? 2 : 3)
        let rows = Int(ceil(Double(cells.count) / Double(columns)))
        let gutter: CGFloat = 24
        let headerHeight: CGFloat = 86
        let captionHeight: CGFloat = 46
        let usableWidth = canvasSize.width - gutter * CGFloat(columns + 1)
        let usableHeight = canvasSize.height - headerHeight - gutter * CGFloat(rows + 1)
        let cellWidth = usableWidth / CGFloat(columns)
        let cellHeight = usableHeight / CGFloat(rows)
        let imageHeight = max(1, cellHeight - captionHeight)

        let image = NSImage(size: canvasSize, flipped: true) { _ in
            paper.setFill()
            CGRect(origin: .zero, size: canvasSize).fill()
            drawHeader(title: title, subtitle: "\(kind.subtitle) · \(cells.count) PANELS")

            for (index, cell) in cells.enumerated() {
                let column = index % columns
                let row = index / columns
                let x = gutter + CGFloat(column) * (cellWidth + gutter)
                let y = headerHeight + gutter + CGFloat(row) * (cellHeight + gutter)
                let imageRect = CGRect(x: x, y: y, width: cellWidth, height: imageHeight)
                let captionRect = CGRect(x: x, y: imageRect.maxY, width: cellWidth, height: captionHeight)

                // Fit, never crop — the same rule the roster sheets follow.
                NSGraphicsContext.current?.saveGraphicsState()
                NSBezierPath(rect: imageRect).addClip()
                if !SheetImageFit.draw(cell.image, in: imageRect) {
                    captionWell.setFill()
                    imageRect.fill()
                }
                NSGraphicsContext.current?.restoreGraphicsState()

                captionWell.setFill()
                captionRect.fill()
                ink.withAlphaComponent(0.5).setStroke()
                let border = NSBezierPath(rect: CGRect(x: x, y: y, width: cellWidth, height: cellHeight).insetBy(dx: 1, dy: 1))
                border.lineWidth = 2
                border.stroke()

                let caption = cell.caption.trimmed.isEmpty ? "PANEL \(index + 1)" : cell.caption.trimmed
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byTruncatingTail
                NSAttributedString(string: caption, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium),
                    .foregroundColor: ink,
                    .kern: 0.8,
                    .paragraphStyle: paragraph
                ]).draw(in: captionRect.insetBy(dx: 12, dy: 12))
            }
            return true
        }
        return encodePNG(image)
    }
}

/// The machine-readable half of the sheet set: everything a future importer
/// needs to re-compose the project — the Scene Plan's language, palette,
/// guardrails, cast, style ingredients, and frame prompts, plus pointers to
/// the sheet images themselves. Written beside the PNGs; tolerant decode so
/// older manifests keep opening as the shape grows.
struct ProjectSheetManifest: Codable, Hashable {
    static let currentSchemaVersion = "litscenes.project_sheet_manifest.v0.1"

    struct PaletteSwatch: Codable, Hashable {
        var name = ""
        var hex = ""
    }

    struct StyleIngredientRef: Codable, Hashable {
        var ingredientId = ""
        var title = ""
        var role = ""
    }

    struct CastRef: Codable, Hashable {
        var characterId = ""
        var name = ""
        var referenceMediaIds: [String] = []
    }

    struct FrameRef: Codable, Hashable {
        var imageId = ""
        var label = ""
        var sourcePrompt = ""
    }

    struct SheetRef: Codable, Hashable {
        var kind = ""
        var mediaId = ""
        var filename = ""
    }

    var schemaVersion = ProjectSheetManifest.currentSchemaVersion
    var projectId = ""
    var projectTitle = ""
    var generatedAt = ""
    var claim = ""
    var visualSummary = ""
    var motifTerms: [String] = []
    var textureMaterialTerms: [String] = []
    var compositionTerms: [String] = []
    var pacingEnergyTerms: [String] = []
    var paletteSwatches: [PaletteSwatch] = []
    var mustPreserve: [String] = []
    var mustAvoid: [String] = []
    var goalSliceTitle = ""
    var storyTitle = ""
    var storyPremise = ""
    var styleIngredients: [StyleIngredientRef] = []
    var cast: [CastRef] = []
    var frames: [FrameRef] = []
    var sheets: [SheetRef] = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case projectTitle
        case generatedAt
        case claim
        case visualSummary
        case motifTerms
        case textureMaterialTerms
        case compositionTerms
        case pacingEnergyTerms
        case paletteSwatches
        case mustPreserve
        case mustAvoid
        case goalSliceTitle
        case storyTitle
        case storyPremise
        case styleIngredients
        case cast
        case frames
        case sheets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        projectTitle = try container.decodeIfPresent(String.self, forKey: .projectTitle) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        claim = try container.decodeIfPresent(String.self, forKey: .claim) ?? ""
        visualSummary = try container.decodeIfPresent(String.self, forKey: .visualSummary) ?? ""
        motifTerms = try container.decodeIfPresent([String].self, forKey: .motifTerms) ?? []
        textureMaterialTerms = try container.decodeIfPresent([String].self, forKey: .textureMaterialTerms) ?? []
        compositionTerms = try container.decodeIfPresent([String].self, forKey: .compositionTerms) ?? []
        pacingEnergyTerms = try container.decodeIfPresent([String].self, forKey: .pacingEnergyTerms) ?? []
        paletteSwatches = try container.decodeIfPresent([PaletteSwatch].self, forKey: .paletteSwatches) ?? []
        mustPreserve = try container.decodeIfPresent([String].self, forKey: .mustPreserve) ?? []
        mustAvoid = try container.decodeIfPresent([String].self, forKey: .mustAvoid) ?? []
        goalSliceTitle = try container.decodeIfPresent(String.self, forKey: .goalSliceTitle) ?? ""
        storyTitle = try container.decodeIfPresent(String.self, forKey: .storyTitle) ?? ""
        storyPremise = try container.decodeIfPresent(String.self, forKey: .storyPremise) ?? ""
        styleIngredients = try container.decodeIfPresent([StyleIngredientRef].self, forKey: .styleIngredients) ?? []
        cast = try container.decodeIfPresent([CastRef].self, forKey: .cast) ?? []
        frames = try container.decodeIfPresent([FrameRef].self, forKey: .frames) ?? []
        sheets = try container.decodeIfPresent([SheetRef].self, forKey: .sheets) ?? []
    }
}
