import CoreGraphics
import Foundation

// MARK: - Filmstrip tile math (pure — the loader renders, this decides)

/// One thumbnail slot inside a strip band: where it draws and which file
/// frame it shows. Tiles live on a MATERIAL-time grid anchored at the band's
/// material start, so panning and zooming inside one rung never re-phase the
/// grid and cache identity (`rungIndex`) survives every viewport move.
struct ShotFilmstripTile: Equatable {
    var clipPath: String
    /// Frame-quantized sample time in the clip FILE (`headSeconds` applied).
    /// The tile samples its material MIDPOINT: forward and reversed displays
    /// show the identical frame for the identical material stretch — the
    /// mirror is x placement only, like the rest of the strip.
    var fileSeconds: Double
    /// Band-local display x/width (already mirrored when reversed).
    var x: CGFloat
    var width: CGFloat
    /// Tile index on the band's rung grid — the stable cache identity.
    var rungIndex: Int
}

/// The zoom ladder: seconds of material per tile. Zooming swaps rungs instead
/// of regenerating on every pixel of scale change. 32s serves a multi-minute
/// artifact band at fit; the 0.5s floor (12 frames) keeps tiles legible at
/// the strip's max zoom (4pt per 24fps frame ⇒ 96 pt/s ⇒ 48pt tiles) — the
/// player's frame-exact preview owns "which frame exactly", the strip owns
/// neighborhood context.
enum ShotFilmstripLadder {
    static let rungs: [Double] = [32, 16, 8, 4, 2, 1, 0.5]

    /// The smallest rung that still reads as a picture: display width
    /// ≥ 0.75 × the ideal tile width. Between swaps a tile renders at
    /// 0.75×–1.5× ideal. Degenerate scales fall back to the coarsest rung.
    static func rung(scale: CGFloat, tileWidth: CGFloat) -> Double {
        guard scale > 0, tileWidth > 0 else { return rungs[0] }
        let minimumWidth = tileWidth * 0.75
        for rung in rungs.reversed() where CGFloat(rung) * scale >= minimumWidth {
            return rung
        }
        return rungs[0]
    }

    /// Generation tolerance per rung: `min(rung/4, 0.5)`, floored at 3 frames.
    /// Coarse rungs ride keyframe-adjacent fast paths (a half-second drift is
    /// invisible in a tile spanning ≥ 4s); the finest rung stays within a
    /// third of its own span.
    static func tolerance(forRung rung: Double) -> Double {
        max(min(rung / 4, 0.5), 3.0 / 24.0)
    }
}

/// The tiles of one band that intersect `visibleX` (strip-body coordinates —
/// the caller applies the prefetch margin). Pure: geometry in, slots out.
func shotFilmstripTilePlan(
    planClip: ShotCutPlanClip,
    bandFrame: (x: CGFloat, width: CGFloat),
    isReversed: Bool,
    scale: CGFloat,
    rung: Double,
    visibleX: ClosedRange<CGFloat>
) -> [ShotFilmstripTile] {
    guard !planClip.clipPath.isEmpty,
          planClip.materialSeconds > 0,
          rung > 0,
          scale > 0 else { return [] }
    let material = planClip.materialSeconds
    let count = Int(ceil(material / rung))
    guard count > 0 else { return [] }
    var tiles: [ShotFilmstripTile] = []
    for index in 0..<count {
        let materialStart = Double(index) * rung
        let span = min(rung, material - materialStart)
        guard span > 0 else { continue }
        let width = CGFloat(span) * scale
        let x = isReversed
            ? bandFrame.width - CGFloat(materialStart + span) * scale
            : CGFloat(materialStart) * scale
        let absoluteStart = bandFrame.x + x
        guard absoluteStart <= visibleX.upperBound,
              absoluteStart + width >= visibleX.lowerBound else { continue }
        tiles.append(ShotFilmstripTile(
            clipPath: planClip.clipPath,
            fileSeconds: ShotAudioTiming.frameQuantizedStart(
                planClip.headSeconds + materialStart + span / 2
            ),
            x: x,
            width: width,
            rungIndex: index
        ))
    }
    return tiles
}
