import CoreGraphics
import Foundation

/// THE AXIS CONTRACT
///
/// Every time-mapped row in the shot player is laid out as
/// `[head gutter 132][time area][tail gutter 92]`. Within the time area, t=0
/// sits at `contentInset` and t=end at `width - contentInset`, so THE SHOT'S
/// START AND END LAND AT THE SAME ABSOLUTE X ON EVERY ROW — the picture strip,
/// the ruler, all five audio lanes, and the region inspector.
///
/// Interior mapping is per-block and is NAMED in each block's head gutter: the
/// picture strip is MATERIAL space (it must keep showing razored-out material
/// so cuts stay restorable), while the ruler and the audio lanes are OUTPUT
/// space (what actually plays). The contract deliberately does NOT promise
/// that six seconds in lands at the same x on both, and no part of the UI may
/// imply that it does — which is why the two blocks carry facing brass marks
/// across a declared seam instead of a connecting line.
///
/// Pure geometry only: no SwiftUI, no domain types, so every rule here is
/// unit-testable (the `AmbientTunerMetrics` precedent).
enum ShotTimelineAxis {
    /// Track-header gutter. 132 is the smallest width that renders every
    /// truthful lane summary in full — `MISSING CLIP` is the most important
    /// state on a row and must never truncate.
    static let headWidth: CGFloat = 132
    /// Level gutter. Measured off the controls already there: slider 74 + 4
    /// gap + 12 glyph + 2 trailing, so volume does not move house.
    static let tailWidth: CGFloat = 92
    /// Adopted from the strip's own `handleWidth`, so the strip's interior
    /// math needs zero changes — only its frame moves. It also buys the lanes
    /// a grabbable in-edge at t=0 instead of one clipped by the plate border.
    static let contentInset: CGFloat = 13

    /// Vertical inset of a drawn audio band inside its lane. Shared so a
    /// control placed on a band and the waveform painting that band read one
    /// number — two coordinate systems agreeing by convention is exactly the
    /// defect this axis exists to prevent.
    static let bandVerticalInset: CGFloat = 3

    static let rulerHeight: CGFloat = 14
    static let laneHeight: CGFloat = 30
    static let inspectorHeight: CGFloat = 28
    static let rowSpacing: CGFloat = 4
    static let laneCount = 5

    /// Width of the mapped span inside a time area. Floors at 1 so a
    /// transient zero-width layout pass can never divide by zero.
    static func contentWidth(laneWidth: CGFloat) -> CGFloat {
        max(laneWidth - contentInset * 2, 1)
    }

    /// Seconds → x within a time area's local coordinate space. The viewport
    /// (THE WINDOW COROLLARY, `ShotTimelineViewport`) maps only the visible
    /// window onto the mapped span; `.fit` reduces to the historical whole-
    /// duration mapping verbatim. Times outside the window pin to the edges,
    /// exactly as out-of-range times always pinned to the plate's ends.
    static func x(
        forSeconds seconds: Double,
        durationSeconds: Double,
        laneWidth: CGFloat,
        viewport: ShotTimelineViewport = .fit
    ) -> CGFloat {
        guard durationSeconds > 0, seconds.isFinite else { return contentInset }
        let window = viewport.window(durationSeconds: durationSeconds)
        guard window.length > 0 else { return contentInset }
        let fraction = min(max((seconds - window.start) / window.length, 0), 1)
        return contentInset + CGFloat(fraction) * contentWidth(laneWidth: laneWidth)
    }

    /// x → seconds. Exact inverse of `x(forSeconds:)` inside the mapped span;
    /// x in either gutter clamps to the nearest visible end.
    static func seconds(
        forX x: CGFloat,
        durationSeconds: Double,
        laneWidth: CGFloat,
        viewport: ShotTimelineViewport = .fit
    ) -> Double {
        guard durationSeconds > 0, x.isFinite else { return 0 }
        let window = viewport.window(durationSeconds: durationSeconds)
        let fraction = min(max(Double((x - contentInset) / contentWidth(laneWidth: laneWidth)), 0), 1)
        return window.start + fraction * window.length
    }

    /// A drag translation in points → a duration in seconds. Scales by the
    /// MAPPED width, not the lane width: feeding the full width here is what
    /// made drags run ~4% fast and the snap radius ~4% wide. Under zoom a
    /// point covers proportionally fewer seconds.
    static func secondsDelta(
        forPoints points: CGFloat,
        durationSeconds: Double,
        laneWidth: CGFloat,
        viewport: ShotTimelineViewport = .fit
    ) -> Double {
        guard durationSeconds > 0, points.isFinite else { return 0 }
        let window = viewport.window(durationSeconds: durationSeconds)
        return Double(points / contentWidth(laneWidth: laneWidth)) * window.length
    }

    /// The width the WHOLE duration would occupy at this zoom — what the
    /// pixel-radius snap helpers must receive as their `timelineWidth`, so an
    /// 8px magnet stays 8 PIXELS at any zoom instead of 8 pixels of fit-space.
    static func mappedWidth(laneWidth: CGFloat, viewport: ShotTimelineViewport = .fit) -> CGFloat {
        contentWidth(laneWidth: laneWidth) * max(viewport.normalized().zoom, 1)
    }

    /// How far down the lane stack the single continuous playhead draws, in
    /// the stack's own coordinate space: from the top of the ruler through the
    /// bottom of the last lane, INCLUDING the inter-row spacing, so the line
    /// is unbroken across the gaps that fragment it today.
    ///
    /// It stops short of the reserved inspector row, which is a control row
    /// with no time mapping. Because that slot is unconditional and always
    /// last, the run is a single band whose height never depends on the
    /// selection — which is the same invariant that keeps lanes from shifting.
    static func playheadHeight(laneCount: Int = laneCount) -> CGFloat {
        let lanes = max(laneCount, 0)
        guard lanes > 0 else { return rulerHeight }
        return rulerHeight + rowSpacing + CGFloat(lanes) * laneHeight + CGFloat(lanes - 1) * rowSpacing
    }

    /// Total height of the lane stack, which by construction never depends on
    /// the current selection.
    static func stackHeight(laneCount: Int = laneCount) -> CGFloat {
        let lanes = max(laneCount, 0)
        let laneRun = lanes > 0
            ? CGFloat(lanes) * laneHeight + CGFloat(lanes - 1) * rowSpacing
            : 0
        return rulerHeight + rowSpacing + laneRun + rowSpacing + inspectorHeight
    }
}

/// THE METRICS COROLLARY (extends THE AXIS CONTRACT): the lane stack's
/// VERTICAL numbers are a parameter, not a constant, because the same stack
/// now renders at two sizes — inline in the shot player and enlarged in the
/// sound editor sheet. `.inline` reproduces the axis statics verbatim (pinned
/// by test), so every existing construction site keeps its exact geometry
/// without naming metrics at all. Horizontal numbers (gutters, insets) stay
/// on the axis: both sizes must keep t=0 and t=end at the same absolute x.
struct ShotTimelineMetrics: Equatable, Sendable {
    var rulerHeight: CGFloat = ShotTimelineAxis.rulerHeight
    var laneHeight: CGFloat = ShotTimelineAxis.laneHeight
    /// The waveform's own frame inside a lane row — historically a hardcoded
    /// 28 beside the 30pt lane.
    var waveformHeight: CGFloat = 28
    var inspectorHeight: CGFloat = ShotTimelineAxis.inspectorHeight
    var rowSpacing: CGFloat = ShotTimelineAxis.rowSpacing

    /// The shot player's historical geometry, exactly.
    static let inline = ShotTimelineMetrics()

    /// The sound editor's enlarged geometry: lanes tall enough for fade
    /// handles and comfortable trim grips, a ruler tall enough for numerals
    /// at reading size.
    static let editor = ShotTimelineMetrics(
        rulerHeight: 22,
        laneHeight: 72,
        waveformHeight: 68,
        inspectorHeight: 40,
        rowSpacing: 6
    )

    /// Mirror of `ShotTimelineAxis.playheadHeight` over these metrics.
    func playheadHeight(laneCount: Int) -> CGFloat {
        let lanes = max(laneCount, 0)
        guard lanes > 0 else { return rulerHeight }
        return rulerHeight + rowSpacing + CGFloat(lanes) * laneHeight + CGFloat(lanes - 1) * rowSpacing
    }

    /// Mirror of `ShotTimelineAxis.stackHeight` over these metrics.
    func stackHeight(laneCount: Int) -> CGFloat {
        let lanes = max(laneCount, 0)
        let laneRun = lanes > 0
            ? CGFloat(lanes) * laneHeight + CGFloat(lanes - 1) * rowSpacing
            : 0
        return rulerHeight + rowSpacing + laneRun + rowSpacing + inspectorHeight
    }
}

/// Where a per-segment audio control sits on a SOURCE band, and what the
/// picture reference must move out of its way.
///
/// Two views draw into the same band from two different files — the control
/// overlay and `ShotSourcePictureOverlay`'s ordinal — so both read THIS rather
/// than each carrying its own constants. A control drawn over the numeral it
/// belongs to is the exact failure this prevents.
enum ShotSourceSegmentControlMetrics {
    static let tabWidth: CGFloat = 14
    static let tabHeight: CGFloat = 22
    /// Clears the 2pt splice notch drawn at a segment's leading edge, so the
    /// tab reads as sitting ON the segment rather than straddling its seam.
    static let leadingOffset: CGFloat = 2
    /// Matches the trim-handle threshold: below this a band is a sliver and
    /// gets no affordance at all rather than an unhittable one.
    static let minimumSegmentWidth: CGFloat = 24
    /// Where the picture reference's ordinal moves when a control is present.
    static let ordinalInsetWithControl: CGFloat = 19
    /// Below this the ordinal is dropped rather than drawn under the control —
    /// it is recoverable from the chip list, the inspector, and the notches.
    static let minimumOrdinalWidthWithControl: CGFloat = 41
    /// The ordinal's normal home when no control is drawn.
    static let ordinalInset: CGFloat = 5
    static let minimumOrdinalWidth: CGFloat = 22

    /// The tab's rect in the lane's local space, or nil when the segment is too
    /// narrow or the geometry is degenerate. Vertically centered, which by
    /// construction lands inside `bandVerticalInset` — the same band the
    /// waveform paints.
    static func tabRect(startX: CGFloat, endX: CGFloat, laneHeight: CGFloat) -> CGRect? {
        guard startX.isFinite, endX.isFinite, laneHeight.isFinite else { return nil }
        guard endX - startX >= minimumSegmentWidth else { return nil }
        guard laneHeight >= tabHeight + ShotTimelineAxis.bandVerticalInset * 2 else { return nil }
        return CGRect(
            x: startX + leadingOffset,
            y: ((laneHeight - tabHeight) / 2).rounded(),
            width: tabWidth,
            height: tabHeight
        )
    }

    /// The ordinal's x inset and whether it may be drawn at all, given whether
    /// this segment carries a control.
    static func ordinalPlacement(
        startX: CGFloat,
        endX: CGFloat,
        hasControl: Bool
    ) -> CGFloat? {
        let width = endX - startX
        guard width.isFinite else { return nil }
        if hasControl {
            return width >= minimumOrdinalWidthWithControl ? ordinalInsetWithControl : nil
        }
        return width >= minimumOrdinalWidth ? ordinalInset : nil
    }
}

/// One ruler mark. `numeral` is nil on minor ticks and on majors suppressed
/// for crowding the ends.
struct ShotTimelineTick: Equatable, Sendable {
    var seconds: Double
    var isMajor: Bool
    var numeral: String?
}

/// Ruler tick plan for an output-time span. Pure and testable: the ladder is
/// walked for the smallest interval whose on-screen spacing still fits a
/// timecode numeral, minors subdivide only while they stay legible, and the
/// span's bounds are always majors so the ruler states its own bounds.
///
/// Windowed (THE WINDOW COROLLARY): `durationSeconds` is the VISIBLE window's
/// length and `windowStartSeconds` its absolute start — majors walk absolute
/// multiples of the interval, so zooming in reveals finer real timecodes
/// rather than re-gridding from the window's left edge. The default
/// (`windowStartSeconds: 0`) is the historical whole-duration behavior,
/// tick for tick.
func shotTimelineRulerTicks(
    durationSeconds: Double,
    contentWidth: CGFloat,
    minimumMajorSpacingPoints: CGFloat = 52,
    minimumMinorSpacingPoints: CGFloat = 7,
    endNumeralClearancePoints: CGFloat = 24,
    windowStartSeconds: Double = 0
) -> [ShotTimelineTick] {
    guard durationSeconds > 0, contentWidth > 0 else { return [] }

    let ladder: [Double] = [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600]
    let windowStart = max(windowStartSeconds.isFinite ? windowStartSeconds : 0, 0)
    let windowEnd = windowStart + durationSeconds
    let pointsPerSecond = contentWidth / CGFloat(durationSeconds)
    let majorInterval = ladder.first { CGFloat($0) * pointsPerSecond >= minimumMajorSpacingPoints }

    func numeral(_ seconds: Double) -> String { ShotAudioTiming.timecode(seconds) }

    // Too long or too narrow for any interval: state the bounds and stop.
    guard let majorInterval else {
        return [
            ShotTimelineTick(seconds: windowStart, isMajor: true, numeral: numeral(windowStart)),
            ShotTimelineTick(seconds: windowEnd, isMajor: true, numeral: numeral(windowEnd))
        ]
    }

    let minorDivisor: Int? = [5, 2].first {
        CGFloat(majorInterval / Double($0)) * pointsPerSecond >= minimumMinorSpacingPoints
    }

    var ticks: [ShotTimelineTick] = [
        ShotTimelineTick(seconds: windowStart, isMajor: true, numeral: numeral(windowStart))
    ]
    // Majors sit on ABSOLUTE multiples of the interval.
    var seconds = (windowStart / majorInterval).rounded(.up) * majorInterval
    if seconds <= windowStart + 0.000_1 { seconds += majorInterval }
    while seconds < windowEnd - 0.000_1 {
        // A numeral too close to either end would collide with the bound
        // numerals, which are the two that must always be readable.
        let x = CGFloat(seconds - windowStart) * pointsPerSecond
        let crowdsAnEnd = x < endNumeralClearancePoints
            || (contentWidth - x) < endNumeralClearancePoints
        ticks.append(ShotTimelineTick(
            seconds: seconds,
            isMajor: true,
            numeral: crowdsAnEnd ? nil : numeral(seconds)
        ))
        seconds += majorInterval
    }
    ticks.append(ShotTimelineTick(
        seconds: windowEnd,
        isMajor: true,
        numeral: numeral(windowEnd)
    ))

    if let minorDivisor {
        let minorInterval = majorInterval / Double(minorDivisor)
        var minor = (windowStart / minorInterval).rounded(.up) * minorInterval
        if minor <= windowStart + 0.000_1 { minor += minorInterval }
        while minor < windowEnd - 0.000_1 {
            if abs(minor.truncatingRemainder(dividingBy: majorInterval)) > 0.000_1 {
                ticks.append(ShotTimelineTick(seconds: minor, isMajor: false, numeral: nil))
            }
            minor += minorInterval
        }
    }

    return ticks.sorted { $0.seconds < $1.seconds }
}
