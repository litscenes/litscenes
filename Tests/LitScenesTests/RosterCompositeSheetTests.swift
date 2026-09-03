import AppKit
import Foundation
import Testing
@testable import LitScenes

@Test
func compositeSheetLayoutShapesFollowCellCount() {
    let one = RosterCompositeSheet.layout(cellCount: 1)
    #expect(one.cells.count == 1)
    let two = RosterCompositeSheet.layout(cellCount: 2)
    #expect(two.cells.count == 2)
    // 2 cells share one row: same y, different x.
    #expect(two.cells[0].image.minY == two.cells[1].image.minY)
    #expect(two.cells[0].image.minX < two.cells[1].image.minX)
    let four = RosterCompositeSheet.layout(cellCount: 4)
    #expect(four.cells.count == 4)
    // 2x2: row two sits below row one, columns align.
    #expect(four.cells[2].image.minY > four.cells[0].image.maxY)
    #expect(four.cells[0].image.minX == four.cells[2].image.minX)
    // Captions sit directly under their images, canvas contains everything.
    for cell in four.cells {
        #expect(cell.caption.minY == cell.image.maxY)
        #expect(cell.caption.maxY <= four.canvasSize.height)
        #expect(cell.image.maxX <= four.canvasSize.width)
    }
    // Counts clamp into 1...maxCells.
    #expect(RosterCompositeSheet.layout(cellCount: 0).cells.count == 1)
    #expect(RosterCompositeSheet.layout(cellCount: 9).cells.count == RosterCompositeSheet.maxCells)
}

@Test
@MainActor
func compositeSheetRendersDecodablePNGAtLayoutSize() {
    func swatch(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 40, height: 60), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
        return image
    }
    let data = RosterCompositeSheet.renderPNG(
        title: "Ava",
        cells: [
            (swatch(.systemRed), "young Ava"),
            (swatch(.systemBlue), ""),
            (swatch(.systemGreen), "Ava with her favorite dog")
        ]
    )
    #expect(data != nil)
    let bitmap = data.flatMap { NSBitmapImageRep(data: $0) }
    #expect(bitmap != nil)
    let layout = RosterCompositeSheet.layout(cellCount: 3)
    #expect(CGFloat(bitmap?.pixelsWide ?? 0) == layout.canvasSize.width)
    #expect(CGFloat(bitmap?.pixelsHigh ?? 0) == layout.canvasSize.height)
    // Empty cell list renders nothing.
    #expect(RosterCompositeSheet.renderPNG(title: "Empty", cells: []) == nil)
}

@Test
func sheetImageFitLetterboxesInsteadOfCropping() {
    let cell = CGRect(x: 100, y: 200, width: 880, height: 880)

    // A 2:3 portrait fills the height and letterboxes left/right — the whole
    // figure survives, which an aspect-FILL crop would not allow.
    let portrait = SheetImageFit.fittedRect(source: CGSize(width: 1_024, height: 1_536), in: cell)
    #expect(portrait?.height == 880)
    #expect(abs((portrait?.width ?? 0) - 586.67) < 0.1)
    #expect(portrait?.midX == cell.midX)
    #expect(portrait?.midY == cell.midY)
    // Nothing spills outside the cell — the defining property of fit.
    #expect(portrait.map { cell.contains($0) } == true)

    // A landscape source fills the width and letterboxes top/bottom.
    let landscape = SheetImageFit.fittedRect(source: CGSize(width: 1_600, height: 900), in: cell)
    #expect(abs((landscape?.width ?? 0) - 880) < 0.001)
    #expect(abs((landscape?.height ?? 0) - 495) < 0.1)
    #expect(landscape.map { cell.insetBy(dx: -0.001, dy: -0.001).contains($0) } == true)

    // A square source uses the whole cell.
    let square = SheetImageFit.fittedRect(source: CGSize(width: 512, height: 512), in: cell)
    #expect(abs((square?.width ?? 0) - cell.width) < 0.001)
    #expect(abs((square?.height ?? 0) - cell.height) < 0.001)

    // No usable size — caller draws a placeholder instead.
    #expect(SheetImageFit.fittedRect(source: .zero, in: cell) == nil)
    #expect(SheetImageFit.fittedRect(source: CGSize(width: 10, height: 0), in: cell) == nil)
}

/// The regression that shipped: full-body references were center-cropped into a
/// square cell, so heads and feet were sliced off the saved sheet — and that
/// sheet is what gets attached when a render stack has a one-image budget.
@Test
@MainActor
func compositeSheetKeepsTopAndBottomOfPortraitReferences() {
    let topBand = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    let middle = NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    let bottomBand = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)

    // A tall 1:3 portrait: banded so a vertical crop is detectable.
    let portrait = NSImage(size: NSSize(width: 40, height: 120), flipped: false) { rect in
        middle.setFill()
        rect.fill()
        topBand.setFill()
        // flipped: false — origin bottom-left, so the "top" band is high y.
        CGRect(x: 0, y: rect.height - 12, width: rect.width, height: 12).fill()
        bottomBand.setFill()
        CGRect(x: 0, y: 0, width: rect.width, height: 12).fill()
        return true
    }

    let data = RosterCompositeSheet.renderPNG(title: "Tall", cells: [(portrait, "full body")])
    let bitmap = try! #require(data.flatMap { NSBitmapImageRep(data: $0) })
    let layout = RosterCompositeSheet.layout(cellCount: 1)
    let image = layout.cells[0].image

    // Layout is top-left origin and the canvas is flipped, so layout points
    // index bitmap pixels directly. Assert on which channel DOMINATES rather
    // than on exact values: the canvas round-trips through a wider color space,
    // which shifts pure red to roughly (1, 0.15, 0) in sRGB.
    enum Band { case red, green, blue, cream, other }
    func band(x: CGFloat, y: CGFloat) -> Band {
        guard let color = bitmap.colorAt(x: Int(x), y: Int(y))?.usingColorSpace(.sRGB) else {
            return .other
        }
        let (r, g, b) = (color.redComponent, color.greenComponent, color.blueComponent)
        if r > 0.75, g > 0.75, b > 0.7, max(r, max(g, b)) - min(r, min(g, b)) < 0.2 { return .cream }
        if r > 0.6, g < 0.5, b < 0.5 { return .red }
        if g > 0.6, r < 0.5, b < 0.5 { return .green }
        if b > 0.6, r < 0.5, g < 0.5 { return .blue }
        return .other
    }

    // The head survives: the top band is present just inside the cell's top edge.
    #expect(band(x: image.midX, y: image.minY + 4) == .red)
    // The feet survive: the bottom band is present just inside the bottom edge.
    #expect(band(x: image.midX, y: image.maxY - 4) == .green)
    // The body is still in between.
    #expect(band(x: image.midX, y: image.midY) == .blue)
    // And it is genuinely FIT, not fill: a 1:3 source in a square cell leaves
    // paper letterbox at mid-height near the left edge.
    #expect(band(x: image.minX + 6, y: image.midY) == .cream)
}
