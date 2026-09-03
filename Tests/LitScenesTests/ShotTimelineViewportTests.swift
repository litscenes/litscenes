import CoreGraphics
import Foundation
import Testing
@testable import LitScenes

// THE WINDOW COROLLARY's firewall: zoom 1× is bit-identical to the historical
// axis, windows map and invert exactly, and follow/reveal obey their laws.

@Test func fitViewportIsIdenticalToTheHistoricalMapping() {
    let duration = 10.0
    let width: CGFloat = 600
    for seconds in [0.0, 2.5, 5.0, 9.99, 10.0] {
        let legacy = ShotTimelineAxis.contentInset
            + CGFloat(seconds / duration) * ShotTimelineAxis.contentWidth(laneWidth: width)
        let viewported = ShotTimelineAxis.x(
            forSeconds: seconds,
            durationSeconds: duration,
            laneWidth: width,
            viewport: .fit
        )
        #expect(abs(legacy - viewported) < 0.000_1)
    }
    // Inverse round-trips at fit.
    let x = ShotTimelineAxis.x(forSeconds: 3.3, durationSeconds: duration, laneWidth: width)
    let back = ShotTimelineAxis.seconds(forX: x, durationSeconds: duration, laneWidth: width)
    #expect(abs(back - 3.3) < 0.000_1)
}

@Test func zoomedWindowMapsItsEdgesToTheMappedSpanAndInverts() {
    let duration = 10.0
    let width: CGFloat = 600
    let viewport = ShotTimelineViewport(zoom: 2, offsetFraction: 0.25)
    let window = viewport.window(durationSeconds: duration)
    #expect(abs(window.start - 2.5) < 0.000_1)
    #expect(abs(window.length - 5.0) < 0.000_1)

    // Window edges land exactly at the mapped span's edges on every row.
    let startX = ShotTimelineAxis.x(
        forSeconds: 2.5, durationSeconds: duration, laneWidth: width, viewport: viewport
    )
    let endX = ShotTimelineAxis.x(
        forSeconds: 7.5, durationSeconds: duration, laneWidth: width, viewport: viewport
    )
    #expect(abs(startX - ShotTimelineAxis.contentInset) < 0.000_1)
    #expect(abs(endX - (width - ShotTimelineAxis.contentInset)) < 0.000_1)

    // Off-window times pin to the visible edges, like out-of-range always did.
    #expect(ShotTimelineAxis.x(
        forSeconds: 0, durationSeconds: duration, laneWidth: width, viewport: viewport
    ) == ShotTimelineAxis.contentInset)

    // Inverse round-trips inside the window.
    let x = ShotTimelineAxis.x(
        forSeconds: 6.2, durationSeconds: duration, laneWidth: width, viewport: viewport
    )
    let back = ShotTimelineAxis.seconds(
        forX: x, durationSeconds: duration, laneWidth: width, viewport: viewport
    )
    #expect(abs(back - 6.2) < 0.000_1)

    // A drag covers proportionally fewer seconds under zoom.
    let fitDelta = ShotTimelineAxis.secondsDelta(
        forPoints: 100, durationSeconds: duration, laneWidth: width
    )
    let zoomDelta = ShotTimelineAxis.secondsDelta(
        forPoints: 100, durationSeconds: duration, laneWidth: width, viewport: viewport
    )
    #expect(abs(zoomDelta - fitDelta / 2) < 0.000_1)

    // And the snap-radius width scales with zoom.
    #expect(abs(ShotTimelineAxis.mappedWidth(laneWidth: width, viewport: viewport)
        - ShotTimelineAxis.contentWidth(laneWidth: width) * 2) < 0.000_1)
}

@Test func maxZoomIsAPowerOfTwoThatMakesFramesVisible() {
    // 60s over ~574pt of content: fit gives ~9.6 pt/s, one frame ≈ 0.4pt.
    // 4pt per frame needs 96 pt/s → required zoom = 10.03 → 16.
    let maxZoom = ShotTimelineViewport.maxZoom(durationSeconds: 60, contentWidth: 574)
    #expect(maxZoom == 16)
    let framePoints = 574 * maxZoom / 60 * CGFloat(ShotAudioTiming.frameSeconds)
    #expect(framePoints >= 4)
    // A short cut can already be there at fit.
    #expect(ShotTimelineViewport.maxZoom(durationSeconds: 1, contentWidth: 574) == 1)
}

@Test func zoomingAboutAnAnchorKeepsTheAnchorPut() {
    let duration = 10.0
    let width: CGFloat = 600
    let before = ShotTimelineViewport(zoom: 2, offsetFraction: 0.2)
    let anchor = 5.0
    let anchorXBefore = ShotTimelineAxis.x(
        forSeconds: anchor, durationSeconds: duration, laneWidth: width, viewport: before
    )
    let after = before.zoomed(
        byFactor: 2, anchorSeconds: anchor, durationSeconds: duration, maxZoom: 16
    )
    #expect(after.zoom == 4)
    let anchorXAfter = ShotTimelineAxis.x(
        forSeconds: anchor, durationSeconds: duration, laneWidth: width, viewport: after
    )
    #expect(abs(anchorXBefore - anchorXAfter) < 0.001)

    // Zooming out past fit clamps to fit with a zero offset.
    let out = after.zoomed(byFactor: 0.1, anchorSeconds: anchor, durationSeconds: duration, maxZoom: 16)
    #expect(out.zoom == 1)
    #expect(out.offsetFraction == 0)
}

@Test func followingPagesOnlyWhenCrossingFromInside() {
    let duration = 10.0
    let viewport = ShotTimelineViewport(zoom: 2, offsetFraction: 0)  // window [0, 5]

    // Inside → still inside: untouched.
    #expect(viewport.following(previous: 2, current: 3, durationSeconds: duration) == viewport)

    // Inside → crossed the right edge: page, playhead at the left edge.
    let tight = ShotTimelineViewport(zoom: 4, offsetFraction: 0)  // window [0, 2.5]
    let paged = tight.following(previous: 2.4, current: 2.6, durationSeconds: duration)
    #expect(abs(paged.offsetFraction - 0.26) < 0.000_1)

    // Near the end the page clamps so the window stays inside the duration —
    // the playhead is still revealed.
    let endPage = viewport.following(previous: 4.9, current: 5.2, durationSeconds: duration)
    #expect(abs(endPage.offsetFraction - 0.5) < 0.000_1)
    let endWindow = endPage.window(durationSeconds: duration)
    #expect(5.2 >= endWindow.start && 5.2 <= endWindow.start + endWindow.length)

    // Panned away (previous OUTSIDE): never yanked.
    let pannedAway = ShotTimelineViewport(zoom: 2, offsetFraction: 0.5)  // window [5, 10]
    #expect(pannedAway.following(previous: 1, current: 2, durationSeconds: duration) == pannedAway)

    // Fit never moves.
    #expect(ShotTimelineViewport.fit.following(previous: 1, current: 9, durationSeconds: duration)
        == .fit)
}

@Test func revealingCentersOffscreenTimesAndClampsAtTheEnds() {
    let duration = 10.0
    let viewport = ShotTimelineViewport(zoom: 4, offsetFraction: 0)  // window [0, 2.5]

    // Visible: untouched.
    #expect(viewport.revealing(1, durationSeconds: duration) == viewport)

    // Offscreen: centered.
    let centered = viewport.revealing(6, durationSeconds: duration)
    let window = centered.window(durationSeconds: duration)
    #expect(abs((window.start + window.length / 2) - 6) < 0.000_1)

    // Near the end: clamped so the window stays inside the duration.
    let clamped = viewport.revealing(9.9, durationSeconds: duration)
    #expect(abs(clamped.offsetFraction - 0.75) < 0.000_1)
}

@Test func windowedRulerTicksWalkAbsoluteSeconds() {
    // A 5s window starting at 2.5 over 300pt (60 pt/s → 1s majors): majors
    // land on the ABSOLUTE grid (3, 4, 5, 6, 7), bounds at the window edges.
    let ticks = shotTimelineRulerTicks(
        durationSeconds: 5,
        contentWidth: 300,
        windowStartSeconds: 2.5
    )
    let majors = ticks.filter(\.isMajor).map(\.seconds)
    #expect(abs((majors.first ?? -1) - 2.5) < 0.000_1)
    #expect(abs((majors.last ?? -1) - 7.5) < 0.000_1)
    #expect(majors.contains { abs($0 - 3) < 0.000_1 })
    #expect(majors.contains { abs($0 - 7) < 0.000_1 })
    // Nothing re-gridded from the window's left edge (no 3.5 major).
    #expect(!majors.contains { abs($0 - 3.5) < 0.000_1 })
}

@Test func panningMovesTheWindowByOnScreenPointsAndClampsAtBothEnds() {
    let duration = 10.0
    let width: CGFloat = 600
    let viewport = ShotTimelineViewport(zoom: 4, offsetFraction: 0.25)  // window [2.5, 5]

    // A pan of one full content width moves exactly one window length.
    let paged = viewport.panned(byPoints: ShotTimelineAxis.contentWidth(laneWidth: width),
                                laneWidth: width, durationSeconds: duration)
    #expect(abs(paged.offsetFraction - 0.5) < 0.000_1)
    #expect(paged.zoom == viewport.zoom)

    // Negative points pan earlier.
    let back = paged.panned(byPoints: -ShotTimelineAxis.contentWidth(laneWidth: width),
                            laneWidth: width, durationSeconds: duration)
    #expect(abs(back.offsetFraction - 0.25) < 0.000_1)

    // Fit has nowhere to pan.
    #expect(ShotTimelineViewport.fit.panned(byPoints: 500, laneWidth: width, durationSeconds: duration)
        == .fit)

    // Both ends clamp.
    let left = viewport.panned(byPoints: -10_000, laneWidth: width, durationSeconds: duration)
    #expect(left.offsetFraction == 0)
    let right = viewport.panned(byPoints: 10_000, laneWidth: width, durationSeconds: duration)
    #expect(abs(right.offsetFraction - 0.75) < 0.000_1)
}

@Test func centeringPlacesTheWindowAtAFractionAndClamps() {
    let viewport = ShotTimelineViewport(zoom: 4, offsetFraction: 0)  // window length 1/4

    let mid = viewport.centered(atFraction: 0.5)
    #expect(abs(mid.offsetFraction - 0.375) < 0.000_1)

    // Ends clamp rather than overshoot.
    #expect(viewport.centered(atFraction: 0).offsetFraction == 0)
    #expect(abs(viewport.centered(atFraction: 1).offsetFraction - 0.75) < 0.000_1)

    // Fit is a no-op.
    #expect(ShotTimelineViewport.fit.centered(atFraction: 0.9) == .fit)
}

@Test func framingContainsAndCentersTheRangeAndRespectsMaxZoom() {
    let duration = 40.0

    // A 5s range → 10s window centered on the range's midpoint → zoom 4.
    let framed = ShotTimelineViewport.framing(start: 10, end: 15, durationSeconds: duration, maxZoom: 16)
    #expect(abs(framed.zoom - 4) < 0.000_1)
    let window = framed.window(durationSeconds: duration)
    #expect(abs((window.start + window.length / 2) - 12.5) < 0.000_1)
    #expect(window.start <= 10 + 0.000_1)
    #expect(window.start + window.length >= 15 - 0.000_1)

    // maxZoom clamps DOWN only, so the window still contains the range.
    let clamped = ShotTimelineViewport.framing(start: 10, end: 10.5, durationSeconds: duration, maxZoom: 8)
    #expect(clamped.zoom == 8)
    let clampedWindow = clamped.window(durationSeconds: duration)
    #expect(clampedWindow.start <= 10 + 0.000_1)
    #expect(clampedWindow.start + clampedWindow.length >= 10.5 - 0.000_1)

    // A range near an edge clamps its window inside the duration and still
    // contains the range.
    let edge = ShotTimelineViewport.framing(start: 0, end: 2, durationSeconds: duration, maxZoom: 16)
    let edgeWindow = edge.window(durationSeconds: duration)
    #expect(edgeWindow.start == 0)
    #expect(edgeWindow.start + edgeWindow.length >= 2 - 0.000_1)

    // Degenerate or absent ranges answer the honest whole-shot framing.
    #expect(ShotTimelineViewport.framing(start: 5, end: 5, durationSeconds: duration, maxZoom: 16) == .fit)
    #expect(ShotTimelineViewport.framing(start: 3, end: 7, durationSeconds: 0, maxZoom: 16) == .fit)

    // A range longer than half the duration fits the whole shot.
    #expect(ShotTimelineViewport.framing(start: 0, end: 30, durationSeconds: duration, maxZoom: 16).isFit)
}
