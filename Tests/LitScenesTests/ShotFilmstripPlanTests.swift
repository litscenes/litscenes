import CoreGraphics
import Foundation
import Testing
@testable import LitScenes

// MARK: Fixtures

private func filmClip(
    clipPath: String = "/tmp/film_take.mp4",
    material: Double,
    head: Double = 0
) -> ShotCutPlanClip {
    ShotCutPlanClip(
        segmentKey: "f1>f2",
        clipPath: clipPath,
        keepRanges: [ShotKeepRange(start: head, end: head + material)],
        materialStartSeconds: 0,
        materialSeconds: material,
        outputStartSeconds: 0,
        headSeconds: head
    )
}

private let wideOpen: ClosedRange<CGFloat> = -10_000...10_000

// MARK: Ladder

@Test func filmstripLadderPicksSmallestLegibleRungAndNeverRephases() {
    let tileWidth: CGFloat = 64 * 16 / 9
    // Fit-ish scale over a long band: coarse rung.
    #expect(ShotFilmstripLadder.rung(scale: 2.7, tileWidth: tileWidth) == 32)
    // The strip's max zoom (4pt per 24fps frame = 96 pt/s): 1s tiles read;
    // 0.5s tiles (48pt) would fall under the 0.75× legibility floor.
    #expect(ShotFilmstripLadder.rung(scale: 96, tileWidth: tileWidth) == 1)
    // 0.5 exists for even denser scales.
    #expect(ShotFilmstripLadder.rung(scale: 200, tileWidth: tileWidth) == 0.5)
    // Monotone: more zoom never coarsens the rung.
    var previous = Double.infinity
    for scale in stride(from: CGFloat(0.5), through: 220, by: 0.5) {
        let rung = ShotFilmstripLadder.rung(scale: scale, tileWidth: tileWidth)
        #expect(rung <= previous)
        previous = rung
    }
    // Degenerate inputs fall back to the coarsest rung.
    #expect(ShotFilmstripLadder.rung(scale: 0, tileWidth: tileWidth) == 32)
    #expect(ShotFilmstripLadder.rung(scale: 10, tileWidth: 0) == 32)
}

@Test func filmstripTolerancesArePinned() {
    #expect(ShotFilmstripLadder.tolerance(forRung: 32) == 0.5)
    #expect(ShotFilmstripLadder.tolerance(forRung: 16) == 0.5)
    #expect(ShotFilmstripLadder.tolerance(forRung: 8) == 0.5)
    #expect(ShotFilmstripLadder.tolerance(forRung: 4) == 0.5)
    #expect(ShotFilmstripLadder.tolerance(forRung: 2) == 0.5)
    #expect(ShotFilmstripLadder.tolerance(forRung: 1) == 0.25)
    #expect(ShotFilmstripLadder.tolerance(forRung: 0.5) == 0.125)
}

// MARK: Tile plan, forward

@Test func filmstripForwardPlanTilesTheBandOnTheMaterialGrid() {
    let clip = filmClip(material: 10, head: 0.125)
    let tiles = shotFilmstripTilePlan(
        planClip: clip,
        bandFrame: (x: 13, width: 100),
        isReversed: false,
        scale: 10,
        rung: 4,
        visibleX: wideOpen
    )
    #expect(tiles.count == 3)
    #expect(tiles.map(\.rungIndex) == [0, 1, 2])
    #expect(tiles.map(\.x) == [0, 40, 80])
    #expect(tiles.map(\.width) == [40, 40, 20])
    // Widths cover the band exactly; the last tile clamps to the band end.
    #expect(tiles.map(\.width).reduce(0, +) == 100)
    // Midpoint sampling with headSeconds applied, frame-quantized:
    // material midpoints 2, 6, 9 → file 2.125, 6.125, 9.125 (all on the
    // 24fps grid already).
    #expect(tiles.map(\.fileSeconds) == [2.125, 6.125, 9.125])
    #expect(tiles.allSatisfy { $0.clipPath == clip.clipPath })
}

@Test func filmstripPlanRefusesDegenerateInputs() {
    #expect(shotFilmstripTilePlan(
        planClip: filmClip(clipPath: "", material: 10),
        bandFrame: (x: 0, width: 100),
        isReversed: false,
        scale: 10,
        rung: 4,
        visibleX: wideOpen
    ).isEmpty)
    #expect(shotFilmstripTilePlan(
        planClip: filmClip(material: 0),
        bandFrame: (x: 0, width: 100),
        isReversed: false,
        scale: 10,
        rung: 4,
        visibleX: wideOpen
    ).isEmpty)
    #expect(shotFilmstripTilePlan(
        planClip: filmClip(material: 10),
        bandFrame: (x: 0, width: 100),
        isReversed: false,
        scale: 0,
        rung: 4,
        visibleX: wideOpen
    ).isEmpty)
}

// MARK: Tile plan, reversed

@Test func filmstripReversedPlanMirrorsPlacementButSamplesTheSameFrames() {
    let clip = filmClip(material: 10, head: 0.125)
    let forward = shotFilmstripTilePlan(
        planClip: clip,
        bandFrame: (x: 13, width: 100),
        isReversed: false,
        scale: 10,
        rung: 4,
        visibleX: wideOpen
    )
    let reversed = shotFilmstripTilePlan(
        planClip: clip,
        bandFrame: (x: 13, width: 100),
        isReversed: true,
        scale: 10,
        rung: 4,
        visibleX: wideOpen
    )
    // Identical tile set — same file frames, same cache identity — so a
    // direction flip redraws instantly from cache.
    #expect(reversed.map(\.rungIndex) == forward.map(\.rungIndex))
    #expect(reversed.map(\.fileSeconds) == forward.map(\.fileSeconds))
    #expect(reversed.map(\.width) == forward.map(\.width))
    // Mirrored placement: tile 0 (material start) draws at the display end.
    #expect(reversed.map(\.x) == [60, 20, 0])

    // Round-trip against the real layout law: each tile's display center
    // maps back inside the tile's own material span, both directions.
    for (tiles, isReversed) in [(forward, false), (reversed, true)] {
        var layout = ShotStripLayout()
        layout.bandFrames[0] = (x: 13, width: 100)
        layout.scale = 10
        layout.isReversed = isReversed
        layout.planClips = [clip]
        layout.materialSeconds = clip.materialSeconds
        layout.contentStart = 13
        layout.contentEnd = 113
        for tile in tiles {
            let center = 13 + tile.x + tile.width / 2
            let material = layout.materialSeconds(atX: center)
            let spanStart = Double(tile.rungIndex) * 4
            let spanEnd = min(spanStart + 4, clip.materialSeconds)
            #expect(material >= spanStart - 0.001 && material <= spanEnd + 0.001)
        }
    }
}

// MARK: Culling

@Test func filmstripCullingKeepsIdentityAndDropsOffscreenTiles() {
    let clip = filmClip(material: 10)
    let visible = shotFilmstripTilePlan(
        planClip: clip,
        bandFrame: (x: 13, width: 100),
        isReversed: false,
        scale: 10,
        rung: 4,
        visibleX: 0...50
    )
    // Only the tile intersecting [0, 50] in strip-body x survives.
    #expect(visible.map(\.rungIndex) == [0])

    // A panned window keeps the grid: overlapping tiles carry the SAME
    // rungIndex and fileSeconds (no re-phase, cache identity survives).
    let panned = shotFilmstripTilePlan(
        planClip: clip,
        bandFrame: (x: -27, width: 100),
        isReversed: false,
        scale: 10,
        rung: 4,
        visibleX: 0...60
    )
    let all = shotFilmstripTilePlan(
        planClip: clip,
        bandFrame: (x: -27, width: 100),
        isReversed: false,
        scale: 10,
        rung: 4,
        visibleX: wideOpen
    )
    for tile in panned {
        let match = all.first { $0.rungIndex == tile.rungIndex }
        #expect(match?.fileSeconds == tile.fileSeconds)
        #expect(match?.x == tile.x)
    }
}
