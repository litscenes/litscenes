import AppKit
import Foundation

/// Shared cell-fitting rule for the contact-sheet composers (RosterCompositeSheet,
/// RenderReferenceComposite, ProjectSheet). Cells letterbox rather than crop: a
/// reference with its head or feet sliced off is worse than one with cream margins,
/// both for the reader and for the image model that gets the sheet as its single
/// attachment. Kept dependency-free (AppKit + Foundation) so the composers stay
/// pure geometry with nothing engine-aware, like their doc comments promise.
enum SheetImageFit {
    /// Largest centered rect inside `cell` that preserves the source's aspect ratio.
    /// Nil when the source has no usable size, so callers can fill a placeholder.
    static func fittedRect(source: CGSize, in cell: CGRect) -> CGRect? {
        guard source.width > 0, source.height > 0 else { return nil }
        let scale = min(cell.width / source.width, cell.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(
            x: cell.midX - size.width / 2,
            y: cell.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Draws `image` fitted into `cell` on a flipped canvas. Returns false when the
    /// source has no usable size, leaving the cell untouched for the caller to fill.
    @discardableResult
    static func draw(_ image: NSImage, in cell: CGRect) -> Bool {
        guard let rect = fittedRect(source: image.size, in: cell) else { return false }
        image.draw(
            in: rect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
        return true
    }
}
