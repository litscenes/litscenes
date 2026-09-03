import CoreGraphics
import Foundation

/// THE WINDOW COROLLARY (extends THE AXIS CONTRACT in `ShotTimelineAxis`):
/// at any zoom, the visible window's start and end land at the same absolute
/// x on every row; each block maps its OWN time (strip = material, ruler and
/// lanes = output) through the same fractional window
/// `[offsetFraction, offsetFraction + 1/zoom]`. Zoom 1× reduces to the
/// existing contract verbatim — pinned by test. Gutters never scroll; only
/// the time area maps through the window.
///
/// A consequence the contract already wears at 1×: with large razors the
/// strip's material playhead projection can sit elsewhere in the window than
/// the output playhead. The window changes nothing about that honesty.
struct ShotTimelineViewport: Equatable, Sendable {
    /// 1 = the whole duration fits the time area (the historical behavior).
    var zoom: CGFloat = 1
    /// The window's start as a fraction of the block's own duration.
    var offsetFraction: Double = 0

    static let fit = ShotTimelineViewport()

    var isFit: Bool { zoom <= 1.000_001 }

    /// Invariants: zoom ≥ 1, offset keeps the whole window inside [0, 1].
    func normalized() -> ShotTimelineViewport {
        var value = self
        value.zoom = max(value.zoom.isFinite ? value.zoom : 1, 1)
        let maxOffset = 1 - 1 / Double(value.zoom)
        value.offsetFraction = min(
            max(value.offsetFraction.isFinite ? value.offsetFraction : 0, 0),
            max(maxOffset, 0)
        )
        return value
    }

    /// The visible span of a block's own duration.
    func window(durationSeconds: Double) -> (start: Double, length: Double) {
        guard durationSeconds > 0 else { return (0, 0) }
        let clean = normalized()
        let length = durationSeconds / Double(clean.zoom)
        return (clean.offsetFraction * durationSeconds, length)
    }

    /// The smallest power-of-two zoom at which one 24fps frame spans at least
    /// `pointsPerFrame` points — the level where frame work stops being
    /// sub-pixel. Floors at 1 (a short cut may already be there at fit).
    static func maxZoom(
        durationSeconds: Double,
        contentWidth: CGFloat,
        pointsPerFrame: CGFloat = 4
    ) -> CGFloat {
        guard durationSeconds > 0, contentWidth > 0 else { return 1 }
        let fitPointsPerSecond = contentWidth / CGFloat(durationSeconds)
        let neededPointsPerSecond = pointsPerFrame * CGFloat(ShotAudioTiming.framesPerSecond)
        let required = neededPointsPerSecond / fitPointsPerSecond
        guard required > 1 else { return 1 }
        return pow(2, ceil(log2(required)))
    }

    /// Zoom about an anchor: the anchor's on-screen x stays put (its fraction
    /// of the window is preserved), so zooming in at the playhead dives into
    /// the playhead, not into the window's left edge.
    func zoomed(
        byFactor factor: CGFloat,
        anchorSeconds: Double,
        durationSeconds: Double,
        maxZoom: CGFloat
    ) -> ShotTimelineViewport {
        guard durationSeconds > 0, factor.isFinite, factor > 0 else { return normalized() }
        let clean = normalized()
        let newZoom = min(max(clean.zoom * factor, 1), max(maxZoom, 1))
        let current = clean.window(durationSeconds: durationSeconds)
        guard current.length > 0 else { return ShotTimelineViewport(zoom: newZoom).normalized() }
        let anchor = min(max(anchorSeconds, 0), durationSeconds)
        let anchorFraction = (anchor - current.start) / current.length
        let newLength = durationSeconds / Double(newZoom)
        let newStart = anchor - min(max(anchorFraction, 0), 1) * newLength
        return ShotTimelineViewport(
            zoom: newZoom,
            offsetFraction: newStart / durationSeconds
        ).normalized()
    }

    /// THE FOLLOW LAW: during playback the window pages forward only when the
    /// playhead crosses an edge FROM INSIDE — a deliberately panned-away
    /// window is never yanked back. Paging puts the playhead at the window's
    /// left edge so a page shows what plays next.
    func following(
        previous: Double,
        current: Double,
        durationSeconds: Double
    ) -> ShotTimelineViewport {
        guard durationSeconds > 0, !isFit else { return normalized() }
        let clean = normalized()
        let window = clean.window(durationSeconds: durationSeconds)
        let end = window.start + window.length
        let wasInside = previous >= window.start - 0.000_1 && previous <= end + 0.000_1
        let isInside = current >= window.start - 0.000_1 && current <= end + 0.000_1
        guard wasInside, !isInside else { return clean }
        return ShotTimelineViewport(
            zoom: clean.zoom,
            offsetFraction: current / durationSeconds
        ).normalized()
    }

    /// Transport actions always reveal the playhead: already visible = no
    /// change; otherwise center the window on it (clamped).
    func revealing(_ seconds: Double, durationSeconds: Double) -> ShotTimelineViewport {
        guard durationSeconds > 0, !isFit else { return normalized() }
        let clean = normalized()
        let window = clean.window(durationSeconds: durationSeconds)
        let end = window.start + window.length
        if seconds >= window.start - 0.000_1, seconds <= end + 0.000_1 { return clean }
        let newStart = seconds - window.length / 2
        return ShotTimelineViewport(
            zoom: clean.zoom,
            offsetFraction: newStart / durationSeconds
        ).normalized()
    }

    /// Two-finger pan: the window slides by an on-screen point distance.
    /// Positive points move the window LATER in time. A point covers
    /// proportionally fewer seconds under zoom (the `secondsDelta` law), fit
    /// is a no-op (there is nowhere to pan), and both ends clamp via
    /// `normalized()`.
    func panned(
        byPoints points: CGFloat,
        laneWidth: CGFloat,
        durationSeconds: Double
    ) -> ShotTimelineViewport {
        guard durationSeconds > 0, points.isFinite else { return normalized() }
        let clean = normalized()
        guard !clean.isFit else { return clean }
        let window = clean.window(durationSeconds: durationSeconds)
        let delta = ShotTimelineAxis.secondsDelta(
            forPoints: points,
            durationSeconds: durationSeconds,
            laneWidth: laneWidth,
            viewport: clean
        )
        return ShotTimelineViewport(
            zoom: clean.zoom,
            offsetFraction: (window.start + delta) / durationSeconds
        ).normalized()
    }

    /// Minimap click/drag: center the window at a fraction of the duration.
    /// Fit is a no-op; the window clamps at both ends via `normalized()`.
    func centered(atFraction fraction: Double) -> ShotTimelineViewport {
        let clean = normalized()
        guard !clean.isFit, fraction.isFinite else { return clean }
        let windowFraction = 1 / Double(clean.zoom)
        return ShotTimelineViewport(
            zoom: clean.zoom,
            offsetFraction: fraction - windowFraction / 2
        ).normalized()
    }

    /// Opening onto a selection: the window is the range padded to twice its
    /// length, centered on its midpoint, zoom clamped to [1, maxZoom]. A
    /// degenerate or absent range answers `.fit` — the honest whole-shot
    /// framing. Because zoom only ever clamps DOWN, the resulting window
    /// always contains the range.
    static func framing(
        start: Double,
        end: Double,
        durationSeconds: Double,
        maxZoom: CGFloat
    ) -> ShotTimelineViewport {
        guard durationSeconds > 0, start.isFinite, end.isFinite else { return .fit }
        let lo = min(max(min(start, end), 0), durationSeconds)
        let hi = min(max(max(start, end), 0), durationSeconds)
        let rangeLength = hi - lo
        guard rangeLength > 0.000_1 else { return .fit }
        let windowLength = min(rangeLength * 2, durationSeconds)
        let zoom = min(max(CGFloat(durationSeconds / windowLength), 1), max(maxZoom, 1))
        let mid = (lo + hi) / 2
        let newStart = mid - (durationSeconds / Double(zoom)) / 2
        return ShotTimelineViewport(
            zoom: zoom,
            offsetFraction: newStart / durationSeconds
        ).normalized()
    }
}
