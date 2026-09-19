import AppKit
import SwiftUI

extension Image {
    /// A fixed-size thumbnail well that keeps every source pixel inside its chrome.
    func fittedThumbnail(circular: Bool = false) -> some View {
        Color.primary.opacity(0.045)
            .overlay {
                GeometryReader { geometry in
                    let side = min(geometry.size.width, geometry.size.height)
                    let inset: CGFloat = circular ? side * 0.1464466094 + 1 : min(4, side / 8)
                    self.resizable()
                        .scaledToFit()
                        .frame(width: max(0, geometry.size.width - 2 * inset), height: max(0, geometry.size.height - 2 * inset))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
    }
}

enum VideoStripLayout {
    /// The existing stored strip format: five complete, equally sized samples.
    static let sampleFractions = [0.08, 0.28, 0.5, 0.72, 0.92]
}

/// Fit samples independently so the strip still spans the complete time axis.
struct FittedVideoStrip: View {
    let image: NSImage

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(CanonColor.mediaCardHover))
            let count = VideoStripLayout.sampleFractions.count
            let source = CGSize(width: image.size.width / CGFloat(count), height: image.size.height)
            for index in 0..<count {
                let cell = CGRect(x: CGFloat(index) * size.width / CGFloat(count), y: 0, width: size.width / CGFloat(count), height: size.height)
                guard let fitted = SheetImageFit.fittedRect(source: source, in: cell) else { continue }
                var tile = context
                tile.clip(to: Path(fitted))
                tile.draw(Image(nsImage: image), in: CGRect(
                    x: fitted.minX - CGFloat(index) * fitted.width, y: fitted.minY,
                    width: fitted.width * CGFloat(count), height: fitted.height
                ))
            }
        }
    }
}
