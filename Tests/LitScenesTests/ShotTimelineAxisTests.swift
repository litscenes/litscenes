import CoreGraphics
import Foundation
import Testing
@testable import LitScenes

// The shared time axis: the geometry that makes the picture strip, the ruler,
// and all five audio lanes start and end at the same absolute x.

private let laneWidth: CGFloat = 613
private let inset = ShotTimelineAxis.contentInset

@Test func axisPinsTimeZeroAndTimeEndToTheContentInset() {
    #expect(ShotTimelineAxis.x(forSeconds: 0, durationSeconds: 12, laneWidth: laneWidth) == inset)
    #expect(
        ShotTimelineAxis.x(forSeconds: 12, durationSeconds: 12, laneWidth: laneWidth)
            == laneWidth - inset
    )
    // Midpoint is centred within the mapped span.
    let middle = ShotTimelineAxis.x(forSeconds: 6, durationSeconds: 12, laneWidth: laneWidth)
    #expect(abs(middle - (inset + (laneWidth - inset * 2) / 2)) < 0.000_1)
    // Out-of-range clamps to the ends rather than running into a gutter.
    #expect(ShotTimelineAxis.x(forSeconds: -5, durationSeconds: 12, laneWidth: laneWidth) == inset)
    #expect(
        ShotTimelineAxis.x(forSeconds: 99, durationSeconds: 12, laneWidth: laneWidth)
            == laneWidth - inset
    )
}

@Test func axisSecondsIsTheExactInverseOfX() {
    for seconds in [0.0, 0.25, 3.5, 6, 11.75, 12] {
        let x = ShotTimelineAxis.x(forSeconds: seconds, durationSeconds: 12, laneWidth: laneWidth)
        let back = ShotTimelineAxis.seconds(forX: x, durationSeconds: 12, laneWidth: laneWidth)
        #expect(abs(back - seconds) < 1e-9)
    }
    // A point in either gutter reads as the nearest bound.
    #expect(ShotTimelineAxis.seconds(forX: 0, durationSeconds: 12, laneWidth: laneWidth) == 0)
    #expect(
        ShotTimelineAxis.seconds(forX: laneWidth, durationSeconds: 12, laneWidth: laneWidth) == 12
    )
}

@Test func axisSurvivesDegenerateGeometry() {
    // A zero-duration (unrendered) shot pins to the start; no NaN, no crash.
    #expect(ShotTimelineAxis.x(forSeconds: 5, durationSeconds: 0, laneWidth: laneWidth) == inset)
    #expect(ShotTimelineAxis.seconds(forX: 40, durationSeconds: 0, laneWidth: laneWidth) == 0)
    // A lane narrower than its own gutters must not divide by zero.
    let narrow = ShotTimelineAxis.x(forSeconds: 3, durationSeconds: 12, laneWidth: 4)
    #expect(narrow.isFinite)
    #expect(ShotTimelineAxis.contentWidth(laneWidth: 0) >= 1)
    #expect(ShotTimelineAxis.seconds(forX: .nan, durationSeconds: 12, laneWidth: laneWidth) == 0)
}

/// The regression pin for the snap-radius bug: drags must scale by the MAPPED
/// width. Feeding the full lane width made moves run fast and widened the
/// 8-pixel snap radius by the same factor.
@Test func secondsDeltaScalesByContentWidthNotLaneWidth() {
    let delta = ShotTimelineAxis.secondsDelta(
        forPoints: 100,
        durationSeconds: 12,
        laneWidth: laneWidth
    )
    let expected = 100.0 / Double(laneWidth - inset * 2) * 12
    #expect(abs(delta - expected) < 1e-9)
    #expect(delta > 100.0 / Double(laneWidth) * 12)
    #expect(ShotTimelineAxis.secondsDelta(forPoints: 50, durationSeconds: 0, laneWidth: laneWidth) == 0)
}

@Test func playheadRunSpansRulerThroughLastLaneAndStopsBeforeTheInspector() {
    let height = ShotTimelineAxis.playheadHeight()
    let stack = ShotTimelineAxis.stackHeight()
    // It covers the ruler and every lane, including the gaps between them...
    #expect(height > ShotTimelineAxis.rulerHeight + ShotTimelineAxis.laneHeight)
    // ...and stops short of the inspector, which has no time mapping.
    #expect(stack - height == ShotTimelineAxis.rowSpacing + ShotTimelineAxis.inspectorHeight)
    #expect(ShotTimelineAxis.playheadHeight(laneCount: 0) == ShotTimelineAxis.rulerHeight)
}

/// The single highest-value pin in this slice: a future slot edit that
/// overflowed the gutter would push one lane's time area right and silently
/// re-break the alignment this whole refactor exists to create.
@Test func headGutterSlotsSumToTheSharedGutterWidth() {
    #expect(ShotAudioLaneHeadLayout.totalWidth == ShotTimelineAxis.headWidth)
}

// MARK: - Ruler ticks

@Test func rulerMajorsNeverCrowdAndAlwaysStateTheBounds() throws {
    let widths: [CGFloat] = [200, 600, 1200]
    let durations: [Double] = [0.4, 3, 12, 90, 720]
    for width in widths {
        for duration in durations {
            let ticks = shotTimelineRulerTicks(durationSeconds: duration, contentWidth: width)
            let majors = ticks.filter(\.isMajor)
            #expect(majors.first?.seconds == 0)
            #expect(abs((majors.last?.seconds ?? -1) - duration) < 0.000_1)
            #expect(majors.first?.numeral != nil)
            #expect(majors.last?.numeral != nil)

            // Interior majors keep their minimum on-screen spacing.
            let pointsPerSecond = width / CGFloat(duration)
            for (index, major) in majors.enumerated() where index > 0 && index < majors.count - 1 {
                let previous = majors[index - 1]
                let gap = CGFloat(major.seconds - previous.seconds) * pointsPerSecond
                #expect(gap >= 52 - 0.001)
            }
            // Ticks arrive in time order, and none escape the span.
            #expect(ticks == ticks.sorted { $0.seconds < $1.seconds })
            #expect(ticks.allSatisfy { $0.seconds >= 0 && $0.seconds <= duration + 0.000_1 })
        }
    }
}

@Test func rulerSuppressesNumeralsThatWouldCollideWithTheBounds() {
    // 12s over 600pt puts majors every 1s = 50pt... so the ladder picks 2s.
    let ticks = shotTimelineRulerTicks(durationSeconds: 12, contentWidth: 600)
    let pointsPerSecond = 600.0 / 12.0
    for tick in ticks where tick.isMajor && tick.seconds > 0 && tick.seconds < 12 {
        let x = tick.seconds * pointsPerSecond
        if x < 24 || (600 - x) < 24 {
            #expect(tick.numeral == nil)
        }
    }
}

@Test func rulerDegeneratesHonestly() {
    #expect(shotTimelineRulerTicks(durationSeconds: 0, contentWidth: 600).isEmpty)
    #expect(shotTimelineRulerTicks(durationSeconds: 12, contentWidth: 0).isEmpty)
    // Too long for even the coarsest interval: state the two bounds and stop.
    let extreme = shotTimelineRulerTicks(durationSeconds: 100_000, contentWidth: 200)
    #expect(extreme.count == 2)
    #expect(extreme.allSatisfy { $0.isMajor && $0.numeral != nil })
}

// MARK: - Per-segment SOURCE audio control metrics
//
// The highest-value pins in this feature: the control tab and the waveform band
// it sits on are drawn by two different views in two different files, agreeing
// only by way of `ShotTimelineAxis.bandVerticalInset`.

@Test func segmentControlTabSitsInsideTheBandTheWaveformPaints() throws {
    let laneHeight = ShotTimelineAxis.laneHeight
    let rect = try #require(
        ShotSourceSegmentControlMetrics.tabRect(startX: 13, endX: 200, laneHeight: laneHeight)
    )
    let bandTop = ShotTimelineAxis.bandVerticalInset
    let bandBottom = laneHeight - ShotTimelineAxis.bandVerticalInset
    #expect(rect.minY >= bandTop)
    #expect(rect.maxY <= bandBottom)
    // And on the segment, never straddling its leading splice notch.
    #expect(rect.minX > 13)
    #expect(rect.maxX < 200)
}

@Test func segmentControlIsSuppressedOnASliverAndOnDegenerateGeometry() {
    #expect(ShotSourceSegmentControlMetrics.tabRect(startX: 13, endX: 30, laneHeight: 30) == nil)
    // Exactly at the threshold it appears; one point under, it does not.
    let threshold = ShotSourceSegmentControlMetrics.minimumSegmentWidth
    #expect(ShotSourceSegmentControlMetrics.tabRect(startX: 13, endX: 13 + threshold, laneHeight: 30) != nil)
    #expect(ShotSourceSegmentControlMetrics.tabRect(startX: 13, endX: 13 + threshold - 1, laneHeight: 30) == nil)
    // A lane too short to hold the tab inside its band refuses rather than
    // drawing a tab that overhangs the waveform.
    #expect(ShotSourceSegmentControlMetrics.tabRect(startX: 13, endX: 200, laneHeight: 12) == nil)
    #expect(ShotSourceSegmentControlMetrics.tabRect(startX: .nan, endX: 200, laneHeight: 30) == nil)
    #expect(ShotSourceSegmentControlMetrics.tabRect(startX: 100, endX: 100, laneHeight: 30) == nil)
}

@Test func abuttingSegmentControlsNeverOverlap() throws {
    // Two segments meeting at x=113, each the narrowest that still carries a tab.
    let width = ShotSourceSegmentControlMetrics.minimumSegmentWidth
    let left = try #require(
        ShotSourceSegmentControlMetrics.tabRect(startX: 113 - width, endX: 113, laneHeight: 30)
    )
    let right = try #require(
        ShotSourceSegmentControlMetrics.tabRect(startX: 113, endX: 113 + width, laneHeight: 30)
    )
    #expect(left.maxX <= right.minX)
}

@Test func segmentControlNeverEntersEitherGutter() throws {
    // The first segment starts at t=0, which is the content inset itself.
    let startX = ShotTimelineAxis.x(forSeconds: 0, durationSeconds: 8, laneWidth: laneWidth)
    let endX = ShotTimelineAxis.x(forSeconds: 4, durationSeconds: 8, laneWidth: laneWidth)
    let rect = try #require(
        ShotSourceSegmentControlMetrics.tabRect(startX: startX, endX: endX, laneHeight: 30)
    )
    #expect(rect.minX >= inset)
    #expect(rect.maxX <= laneWidth - inset)
}

@Test func theOrdinalIsNeverDrawnUnderAControl() {
    let controlled = ShotSourceSegmentControlMetrics.ordinalPlacement(
        startX: 13,
        endX: 13 + ShotSourceSegmentControlMetrics.minimumOrdinalWidthWithControl,
        hasControl: true
    )
    // Where it lands, it clears the tab's trailing edge entirely.
    #expect(controlled == ShotSourceSegmentControlMetrics.ordinalInsetWithControl)
    #expect(
        ShotSourceSegmentControlMetrics.ordinalInsetWithControl
            >= ShotSourceSegmentControlMetrics.leadingOffset
                + ShotSourceSegmentControlMetrics.tabWidth
    )
    // Too narrow to hold both: the ordinal is dropped, not stacked.
    #expect(
        ShotSourceSegmentControlMetrics.ordinalPlacement(
            startX: 13,
            endX: 13 + ShotSourceSegmentControlMetrics.minimumOrdinalWidthWithControl - 1,
            hasControl: true
        ) == nil
    )
    // Without a control it keeps its historical home and threshold.
    #expect(
        ShotSourceSegmentControlMetrics.ordinalPlacement(startX: 13, endX: 40, hasControl: false)
            == ShotSourceSegmentControlMetrics.ordinalInset
    )
    #expect(
        ShotSourceSegmentControlMetrics.ordinalPlacement(startX: 13, endX: 34, hasControl: false) == nil
    )
}

// THE METRICS COROLLARY's firewall: `.inline` IS the historical geometry.

@Test func inlineMetricsReproduceTheAxisConstantsExactly() {
    let inline = ShotTimelineMetrics.inline
    #expect(inline.rulerHeight == ShotTimelineAxis.rulerHeight)
    #expect(inline.laneHeight == ShotTimelineAxis.laneHeight)
    #expect(inline.waveformHeight == 28)
    #expect(inline.inspectorHeight == ShotTimelineAxis.inspectorHeight)
    #expect(inline.rowSpacing == ShotTimelineAxis.rowSpacing)
    for laneCount in [0, 1, 5, 6] {
        #expect(inline.playheadHeight(laneCount: laneCount)
            == ShotTimelineAxis.playheadHeight(laneCount: laneCount))
        #expect(inline.stackHeight(laneCount: laneCount)
            == ShotTimelineAxis.stackHeight(laneCount: laneCount))
    }
}

@Test func editorMetricsKeepTheStackArithmetic() {
    let editor = ShotTimelineMetrics.editor
    // Adding a lane grows both heights by exactly one lane + one gap.
    let laneDelta = editor.laneHeight + editor.rowSpacing
    #expect(editor.playheadHeight(laneCount: 6) - editor.playheadHeight(laneCount: 5) == laneDelta)
    #expect(editor.stackHeight(laneCount: 6) - editor.stackHeight(laneCount: 5) == laneDelta)
    // The waveform must fit inside its lane row.
    #expect(editor.waveformHeight < editor.laneHeight)
    // Zero lanes still measures the ruler (playhead) and the full chrome (stack).
    #expect(editor.playheadHeight(laneCount: 0) == editor.rulerHeight)
    #expect(editor.stackHeight(laneCount: 0)
        == editor.rulerHeight + editor.rowSpacing * 2 + editor.inspectorHeight)
}
