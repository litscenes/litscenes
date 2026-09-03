import SwiftUI

/// The SCENES v2 stage dress: a cream plate floating in the dark archive
/// well. The Shot card and its render plan print on the same stock as the
/// suggested-frame cards below them, so the whole page reads as one set of
/// plates in one room. Solid hairlines mark a real Shot; the dashed variant
/// stays reserved for planned and suggested Frames (intentions, not material).
enum ScenesV2StageDress {
    static let well = CanonColor.archiveWell
    static let wellHairline = CanonColor.hairlineDark
    static let cardFill = PlateColor.cream
    static let insetFill = PlateColor.creamDeep
    static let hairline = PlateColor.hairline
    static let ink = PlateColor.ink
    static let inkFaint = PlateColor.inkFaint
    static let cardRadius: CGFloat = 10
}

/// Cream stock, a hairline (solid) or dashed brass border, and registration
/// ticks in the corners — the plate recipe shared by the stage card and the
/// pool's suggestion cards.
struct GildedPlateBackground: ViewModifier {
    var cornerRadius: CGFloat = ScenesV2StageDress.cardRadius
    var tint: Color = CanonColor.brass
    var dashed = false
    var tickInset: CGFloat = 6
    var tickLength: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(ScenesV2StageDress.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        dashed ? tint.opacity(0.7) : ScenesV2StageDress.hairline,
                        style: dashed
                            ? StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                            : StrokeStyle(lineWidth: 1)
                    )
            )
            .overlay(
                PlateCornerTicks(inset: tickInset, length: tickLength)
                    .stroke(tint.opacity(0.7), lineWidth: 1.5)
            )
    }
}

extension View {
    func gildedPlate(
        cornerRadius: CGFloat = ScenesV2StageDress.cardRadius,
        tint: Color = CanonColor.brass,
        dashed: Bool = false,
        tickInset: CGFloat = 6,
        tickLength: CGFloat = 8
    ) -> some View {
        modifier(GildedPlateBackground(
            cornerRadius: cornerRadius,
            tint: tint,
            dashed: dashed,
            tickInset: tickInset,
            tickLength: tickLength
        ))
    }
}
