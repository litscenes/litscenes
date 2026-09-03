import AppKit
import Foundation

/// Renders a character/object "reference sheet": up to four reference images on one
/// labeled contact sheet, so a single attachment can carry several views when a render
/// stack only accepts one or two images. Panel captions come from the roster's
/// per-reference labels ("young Ava"), making the sheet self-describing to the model.
enum RosterCompositeSheet {
    static let maxCells = 4

    struct Layout: Equatable {
        var canvasSize: CGSize
        var header: CGRect
        var cells: [(image: CGRect, caption: CGRect)]

        static func == (lhs: Layout, rhs: Layout) -> Bool {
            lhs.canvasSize == rhs.canvasSize
                && lhs.header == rhs.header
                && lhs.cells.count == rhs.cells.count
                && zip(lhs.cells, rhs.cells).allSatisfy { $0.image == $1.image && $0.caption == $1.caption }
        }
    }

    /// Pure grid geometry (top-left origin): 1 cell = 1×1, 2 = 2×1, 3-4 = 2×2.
    static func layout(
        cellCount: Int,
        cellSide: CGFloat = 880,
        captionHeight: CGFloat = 96,
        gutter: CGFloat = 24,
        headerHeight: CGFloat = 120
    ) -> Layout {
        let count = max(1, min(maxCells, cellCount))
        let columns = count <= 1 ? 1 : 2
        let rows = Int(ceil(Double(count) / Double(columns)))
        let cellHeight = cellSide + captionHeight
        let width = gutter + CGFloat(columns) * (cellSide + gutter)
        let height = headerHeight + CGFloat(rows) * (cellHeight + gutter) + gutter
        let header = CGRect(x: gutter, y: 0, width: width - gutter * 2, height: headerHeight)
        var cells: [(image: CGRect, caption: CGRect)] = []
        for index in 0..<count {
            let column = index % columns
            let row = index / columns
            let x = gutter + CGFloat(column) * (cellSide + gutter)
            let y = headerHeight + CGFloat(row) * (cellHeight + gutter)
            cells.append((
                image: CGRect(x: x, y: y, width: cellSide, height: cellSide),
                caption: CGRect(x: x, y: y + cellSide, width: cellSide, height: captionHeight)
            ))
        }
        return Layout(canvasSize: CGSize(width: width, height: height), header: header, cells: cells)
    }

    private static let paper = NSColor(srgbRed: 0.957, green: 0.937, blue: 0.894, alpha: 1)
    private static let captionWell = NSColor(srgbRed: 0.906, green: 0.851, blue: 0.737, alpha: 1)
    private static let ink = NSColor(srgbRed: 0.106, green: 0.090, blue: 0.067, alpha: 1)

    /// Draws the sheet and returns PNG data. `cells` pair each reference image with
    /// its caption (empty captions render as "VIEW n").
    static func renderPNG(title: String, cells rawCells: [(image: NSImage, caption: String)]) -> Data? {
        let cells = Array(rawCells.prefix(maxCells))
        guard !cells.isEmpty else { return nil }
        let layout = layout(cellCount: cells.count)
        let image = NSImage(size: layout.canvasSize, flipped: true) { _ in
            paper.setFill()
            CGRect(origin: .zero, size: layout.canvasSize).fill()

            let headline = title.uppercased()
            let titleFont = NSFont.systemFont(ofSize: 52, weight: .semibold)
            let subtitleFont = NSFont.monospacedSystemFont(ofSize: 24, weight: .medium)
            let titleAttributes: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: ink, .kern: 2.5]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [.font: subtitleFont, .foregroundColor: ink.withAlphaComponent(0.62), .kern: 4]
            let titleText = NSAttributedString(string: headline, attributes: titleAttributes)
            let subtitleText = NSAttributedString(string: "REFERENCE SHEET", attributes: subtitleAttributes)
            let titleSize = titleText.size()
            titleText.draw(at: CGPoint(x: layout.header.minX, y: layout.header.minY + 18))
            subtitleText.draw(at: CGPoint(x: layout.header.minX, y: layout.header.minY + 18 + titleSize.height + 6))
            ink.withAlphaComponent(0.35).setFill()
            CGRect(x: layout.header.minX, y: layout.header.maxY - 6, width: layout.header.width, height: 2).fill()

            for (index, cell) in cells.enumerated() {
                let rects = layout.cells[index]

                // Aspect-FIT the reference into its square: a full-body reference must
                // arrive with its head and feet intact, so portraits letterbox on the
                // paper rather than lose their extremities to a center crop.
                NSGraphicsContext.current?.saveGraphicsState()
                NSBezierPath(rect: rects.image).addClip()
                if !SheetImageFit.draw(cell.image, in: rects.image) {
                    captionWell.setFill()
                    rects.image.fill()
                }
                NSGraphicsContext.current?.restoreGraphicsState()

                ink.withAlphaComponent(0.55).setStroke()
                let border = NSBezierPath(rect: rects.image.insetBy(dx: 1, dy: 1))
                border.lineWidth = 2
                border.stroke()

                // Caption bar: the label names what this view shows.
                captionWell.setFill()
                rects.caption.fill()
                let caption = cell.caption.trimmed.isEmpty ? "VIEW \(index + 1)" : cell.caption.trimmed
                let captionFont = NSFont.monospacedSystemFont(ofSize: 30, weight: .medium)
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byTruncatingTail
                let captionText = NSAttributedString(string: caption, attributes: [
                    .font: captionFont,
                    .foregroundColor: ink,
                    .kern: 1.2,
                    .paragraphStyle: paragraph
                ])
                let captionHeight = captionText.size().height
                captionText.draw(in: CGRect(
                    x: rects.caption.minX + 16,
                    y: rects.caption.midY - captionHeight / 2,
                    width: rects.caption.width - 32,
                    height: captionHeight + 4
                ))
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

/// Provider-ready 16:9 sheet used when a render API exposes only one native image
/// field. Unlike the roster-owned four-view sheet, this artifact is scoped to one
/// render request and can carry the Frame Creator's full six-reference budget.
enum RenderReferenceComposite {
    static let maxCells = 6
    static let canvasSize = CGSize(width: 1_920, height: 1_080)

    static func renderJPEG(title: String, cells rawCells: [(image: NSImage, caption: String)]) -> Data? {
        let cells = Array(rawCells.prefix(maxCells))
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

        let paper = NSColor(srgbRed: 0.957, green: 0.937, blue: 0.894, alpha: 1)
        let captionWell = NSColor(srgbRed: 0.906, green: 0.851, blue: 0.737, alpha: 1)
        let ink = NSColor(srgbRed: 0.106, green: 0.090, blue: 0.067, alpha: 1)
        let image = NSImage(size: canvasSize, flipped: true) { _ in
            paper.setFill()
            CGRect(origin: .zero, size: canvasSize).fill()

            let headline = NSAttributedString(string: title.uppercased(), attributes: [
                .font: NSFont.systemFont(ofSize: 34, weight: .semibold),
                .foregroundColor: ink,
                .kern: 2.2
            ])
            headline.draw(at: CGPoint(x: gutter, y: 20))
            let subtitle = NSAttributedString(string: "LITSCENES REFERENCE INPUT · \(cells.count) SOURCES", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .medium),
                .foregroundColor: ink.withAlphaComponent(0.58),
                .kern: 2.4
            ])
            subtitle.draw(at: CGPoint(x: gutter, y: 56))

            for (index, cell) in cells.enumerated() {
                let column = index % columns
                let row = index / columns
                let x = gutter + CGFloat(column) * (cellWidth + gutter)
                let y = headerHeight + gutter + CGFloat(row) * (cellHeight + gutter)
                let imageRect = CGRect(x: x, y: y, width: cellWidth, height: imageHeight)
                let captionRect = CGRect(x: x, y: imageRect.maxY, width: cellWidth, height: captionHeight)

                // Fit, never crop: these wide cells would otherwise decapitate every
                // portrait reference on its way to the render API.
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

                let caption = cell.caption.trimmed.isEmpty ? "REFERENCE \(index + 1)" : cell.caption.trimmed
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
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
    }
}
