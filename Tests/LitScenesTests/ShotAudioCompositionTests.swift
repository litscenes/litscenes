import Foundation
import Testing
@testable import LitScenes

// The Look duration law: Lucy re-emits frames on its own clock, so a picture
// that drifted beyond tolerance from the recorded source duration is retimed
// back to the source; audio then covers the full picture.

@Test func lookRetimeTargetAppliesOnlyBeyondTolerance() {
    // Within the 0.5 s tolerance (inclusive): play as returned.
    #expect(ShotAudioComposition.lookRetimeTargetSeconds(lookSeconds: 8.2, sourceSeconds: 8.0) == nil)
    #expect(ShotAudioComposition.lookRetimeTargetSeconds(lookSeconds: 8.5, sourceSeconds: 8.0) == nil)
    #expect(ShotAudioComposition.lookRetimeTargetSeconds(lookSeconds: 7.5, sourceSeconds: 8.0) == nil)
    // The observed field failure: a ~30 fps source returned 24 fps at ~2× length.
    #expect(ShotAudioComposition.lookRetimeTargetSeconds(lookSeconds: 16.2, sourceSeconds: 8.1) == 8.1)
    // Short returns retime back up to the source as well.
    #expect(ShotAudioComposition.lookRetimeTargetSeconds(lookSeconds: 5.0, sourceSeconds: 8.0) == 8.0)
    #expect(ShotAudioComposition.lookRetimeTargetSeconds(lookSeconds: 8.51, sourceSeconds: 8.0) == 8.0)
}

@Test func lookRetimeTargetRequiresBothDurations() {
    // Legacy artifacts tolerant-decode sourceDurationSeconds to 0: never retime.
    #expect(ShotAudioComposition.lookRetimeTargetSeconds(lookSeconds: 16.0, sourceSeconds: 0) == nil)
    #expect(ShotAudioComposition.lookRetimeTargetSeconds(lookSeconds: 0, sourceSeconds: 8.0) == nil)
    #expect(ShotAudioComposition.lookRetimeTargetSeconds(lookSeconds: -1, sourceSeconds: -2) == nil)
}

@Test func effectiveLookDurationFollowsRetimeLaw() {
    let drifted = ShotRestyleArtifact(sourceDurationSeconds: 8.1, outputDurationSeconds: 16.2)
    #expect(ShotAudioComposition.effectiveLookDurationSeconds(drifted) == 8.1)

    let aligned = ShotRestyleArtifact(sourceDurationSeconds: 8.0, outputDurationSeconds: 8.2)
    #expect(ShotAudioComposition.effectiveLookDurationSeconds(aligned) == 8.2)

    let legacy = ShotRestyleArtifact(sourceDurationSeconds: 0, outputDurationSeconds: 16.0)
    #expect(ShotAudioComposition.effectiveLookDurationSeconds(legacy) == 16.0)
}

// MARK: - Region fade ramps

@Test func regionFadeRampsProduceRiseConstantFallOverPlacedWindow() {
    let ramps = shotAudioRegionFadeRamps(
        fadeInSeconds: 1,
        fadeOutSeconds: 2,
        volume: 0.8,
        placedStartSeconds: 3,
        placedDurationSeconds: 10
    )
    #expect(ramps == [
        ShotAudioVolumeRamp(fromVolume: 0, toVolume: 0.8, startSeconds: 3, durationSeconds: 1),
        ShotAudioVolumeRamp(fromVolume: 0.8, toVolume: 0, startSeconds: 11, durationSeconds: 2)
    ])
}

@Test func regionFadeRampsReclampToTruncatedPlacedDurationAndZeroFadesAreConstant() {
    // The composition truncated a 10s region to 3s at the timeline end: the
    // persisted (2, 2) envelope re-clamps to the ACTUAL window, fade-in first.
    let truncated = shotAudioRegionFadeRamps(
        fadeInSeconds: 2,
        fadeOutSeconds: 2,
        volume: 1,
        placedStartSeconds: 57,
        placedDurationSeconds: 3
    )
    #expect(truncated == [
        ShotAudioVolumeRamp(fromVolume: 0, toVolume: 1, startSeconds: 57, durationSeconds: 2),
        ShotAudioVolumeRamp(fromVolume: 1, toVolume: 0, startSeconds: 59, durationSeconds: 1)
    ])

    // No fades → empty plan → callers keep the historical setVolume path.
    #expect(shotAudioRegionFadeRamps(
        fadeInSeconds: 0, fadeOutSeconds: 0, volume: 1,
        placedStartSeconds: 0, placedDurationSeconds: 10
    ).isEmpty)

    // A degenerate placement plans nothing.
    #expect(shotAudioRegionFadeRamps(
        fadeInSeconds: 1, fadeOutSeconds: 1, volume: 1,
        placedStartSeconds: 0, placedDurationSeconds: 0
    ).isEmpty)
}

@Test func loopedRegionFadePlanSpansTilesViaThePlacedWindow() {
    // A 2s file tiling an 8s placement: fades measure OUTPUT time over the
    // whole placed window (all tiles ride ONE track), so the fall lands in
    // the last tile, not at each tile boundary.
    let ramps = shotAudioRegionFadeRamps(
        fadeInSeconds: 0.5,
        fadeOutSeconds: 1,
        volume: 0.6,
        placedStartSeconds: 4,
        placedDurationSeconds: 8
    )
    #expect(ramps.count == 2)
    #expect(ramps[1].startSeconds == 11)
    #expect(ramps[1].durationSeconds == 1)
}

// MARK: - Mix instruction planning (the AVFCore ramp-overlap firewall)

/// AVFoundation's throw condition, restated as a testable property: a
/// positive-duration span overlapping another span, or a set strictly
/// inside a span's interior.
private func mixOverlapViolations(_ plan: [ShotAudioMixInstruction]) -> Int {
    var violations = 0
    for (i, a) in plan.enumerated() where a.durationTicks > 0 {
        for (j, b) in plan.enumerated() where i != j {
            if b.durationTicks > 0 {
                if i < j,
                   max(a.startTicks, b.startTicks)
                       < min(a.startTicks + a.durationTicks, b.startTicks + b.durationTicks) {
                    violations += 1
                }
            } else if b.startTicks > a.startTicks,
                      b.startTicks < a.startTicks + a.durationTicks {
                violations += 1
            }
        }
    }
    return violations
}

@Test func sourceGainInstructionsMatchTheHistoricalPlanOnNormalWindows() {
    let plan = shotSanitizedMixInstructions(shotSourceGainInstructions([
        ShotSourceGainWindow(startSeconds: 1, endSeconds: 3, gain: 0.8, segmentKey: "a"),
        ShotSourceGainWindow(startSeconds: 5, endSeconds: 8, gain: 0.5, segmentKey: "b")
    ]))
    #expect(mixOverlapViolations(plan) == 0)
    #expect(plan == [
        ShotAudioMixInstruction(fromVolume: 0, toVolume: 0, startTicks: 0, durationTicks: 0),
        ShotAudioMixInstruction(fromVolume: 0, toVolume: 0.8, startTicks: 600, durationTicks: 6),
        ShotAudioMixInstruction(fromVolume: 0.8, toVolume: 0, startTicks: 1794, durationTicks: 6),
        ShotAudioMixInstruction(fromVolume: 0, toVolume: 0, startTicks: 1800, durationTicks: 0),
        ShotAudioMixInstruction(fromVolume: 0, toVolume: 0.5, startTicks: 3000, durationTicks: 6),
        ShotAudioMixInstruction(fromVolume: 0.5, toVolume: 0, startTicks: 4794, durationTicks: 6),
        ShotAudioMixInstruction(fromVolume: 0, toVolume: 0, startTicks: 4800, durationTicks: 0)
    ])
}

@Test func theFieldCrashGeometryPlansWithoutOverlap() {
    // The exact rounding overflow that crashed the shot player: a sub-20ms
    // window with off-grid edges clamps its fall ramp to a FRACTIONAL tick
    // count (4.9 ticks). The legacy applier rounded start and duration
    // independently — round(6000.4 − 4.9) = 5996 start + round(4.9) = 5
    // ticks = a span ending at 6001, one tick PAST the closing zero-set at
    // round(6000.4) = 6000 → AVFCore threw. End-anchored tick durations
    // make the span end exactly at the set's tick.
    let fall = 4.9 / 600.0
    let end = 6000.4 / 600.0
    let window = ShotSourceGainWindow(
        startSeconds: end - fall * 2,
        endSeconds: end,
        gain: 1,
        segmentKey: "sliver"
    )
    let plan = shotSanitizedMixInstructions(shotSourceGainInstructions([window]))
    #expect(mixOverlapViolations(plan) == 0)
    let closingSet = plan.last { $0.durationTicks == 0 && $0.toVolume == 0 && $0.startTicks > 0 }
    let fallSpan = plan.last { $0.durationTicks > 0 }
    #expect(closingSet?.startTicks == 6000)
    if let fallSpan, let closingSet {
        #expect(fallSpan.startTicks + fallSpan.durationTicks <= closingSet.startTicks)
    }
}

@Test func degenerateWindowGeometriesAlwaysPlanSafely() {
    let geometries: [[ShotSourceGainWindow]] = [
        // Zero-duration window.
        [ShotSourceGainWindow(startSeconds: 2, endSeconds: 2, gain: 1, segmentKey: "z")],
        // Sub-tick window with fractional edges.
        [ShotSourceGainWindow(startSeconds: 3.00051, endSeconds: 3.00119, gain: 0.7, segmentKey: "t")],
        // Duplicate windows (same range twice).
        [
            ShotSourceGainWindow(startSeconds: 1, endSeconds: 2, gain: 1, segmentKey: "d1"),
            ShotSourceGainWindow(startSeconds: 1, endSeconds: 2, gain: 1, segmentKey: "d2")
        ],
        // Overlapping windows sharing an end.
        [
            ShotSourceGainWindow(startSeconds: 1, endSeconds: 4, gain: 1, segmentKey: "o1"),
            ShotSourceGainWindow(startSeconds: 3.999, endSeconds: 4, gain: 0.5, segmentKey: "o2")
        ],
        // Abutting pair whose right window is a fractional sliver (the seam
        // ramp + closing zero interplay).
        [
            ShotSourceGainWindow(startSeconds: 0, endSeconds: 5.0003, gain: 1, segmentKey: "l"),
            ShotSourceGainWindow(startSeconds: 5.0003, endSeconds: 5.0125, gain: 0.4, segmentKey: "r")
        ],
        // Out-of-order input.
        [
            ShotSourceGainWindow(startSeconds: 6, endSeconds: 7, gain: 0.9, segmentKey: "late"),
            ShotSourceGainWindow(startSeconds: 1, endSeconds: 2, gain: 0.9, segmentKey: "early")
        ]
    ]
    for windows in geometries {
        let plan = shotSanitizedMixInstructions(shotSourceGainInstructions(windows))
        #expect(mixOverlapViolations(plan) == 0)
    }
}

@Test func sanitizerTrimsSwallowedSpansAndDedupesSets() {
    let raw = [
        // Base span.
        ShotAudioMixInstruction(fromVolume: 0, toVolume: 1, startTicks: 100, durationTicks: 10),
        // Overlapping span: trims forward to start at 110.
        ShotAudioMixInstruction(fromVolume: 1, toVolume: 0.5, startTicks: 105, durationTicks: 10),
        // Fully swallowed span: becomes a set of its target at coverage end.
        ShotAudioMixInstruction(fromVolume: 0.5, toVolume: 0.2, startTicks: 112, durationTicks: 2),
        // Set strictly inside the first span: lifts to its end.
        ShotAudioMixInstruction(fromVolume: 0, toVolume: 0, startTicks: 104, durationTicks: 0),
        // Same-tick sets: last wins.
        ShotAudioMixInstruction(fromVolume: 0.9, toVolume: 0.9, startTicks: 300, durationTicks: 0),
        ShotAudioMixInstruction(fromVolume: 0.3, toVolume: 0.3, startTicks: 300, durationTicks: 0)
    ]
    let plan = shotSanitizedMixInstructions(raw)
    #expect(mixOverlapViolations(plan) == 0)
    #expect(plan.contains(ShotAudioMixInstruction(fromVolume: 1, toVolume: 0.5, startTicks: 110, durationTicks: 5)))
    #expect(plan.contains(ShotAudioMixInstruction(fromVolume: 0.2, toVolume: 0.2, startTicks: 115, durationTicks: 0)))
    #expect(plan.contains(ShotAudioMixInstruction(fromVolume: 0, toVolume: 0, startTicks: 110, durationTicks: 0)))
    #expect(plan.contains(ShotAudioMixInstruction(fromVolume: 0.3, toVolume: 0.3, startTicks: 300, durationTicks: 0)))
    #expect(!plan.contains(ShotAudioMixInstruction(fromVolume: 0.9, toVolume: 0.9, startTicks: 300, durationTicks: 0)))
    // A well-formed plan passes through byte-identical.
    let clean = [
        ShotAudioMixInstruction(fromVolume: 0, toVolume: 0, startTicks: 0, durationTicks: 0),
        ShotAudioMixInstruction(fromVolume: 0, toVolume: 1, startTicks: 600, durationTicks: 6),
        ShotAudioMixInstruction(fromVolume: 1, toVolume: 0, startTicks: 1194, durationTicks: 6),
        ShotAudioMixInstruction(fromVolume: 0, toVolume: 0, startTicks: 1200, durationTicks: 0)
    ]
    #expect(shotSanitizedMixInstructions(clean) == clean)
}

@Test func regionFadeInstructionsStayDisjointUnderClampedFades() {
    // Fades meeting exactly in the middle of an off-grid placed range — the
    // region-side cousin of the source-window crash.
    let placedStart = 1.00072
    let placedDuration = 0.03341
    let ramps = shotAudioRegionFadeRamps(
        fadeInSeconds: placedDuration / 2,
        fadeOutSeconds: placedDuration,
        volume: 0.8,
        placedStartSeconds: placedStart,
        placedDurationSeconds: placedDuration
    )
    let plan = shotSanitizedMixInstructions(
        shotRegionVolumeInstructions(ramps: ramps, volume: 0.8)
    )
    #expect(mixOverlapViolations(plan) == 0)

    // No fades: the historical constant-volume single set.
    #expect(shotRegionVolumeInstructions(ramps: [], volume: 0.6) == [
        ShotAudioMixInstruction(fromVolume: 0.6, toVolume: 0.6, startTicks: 0, durationTicks: 0)
    ])
}
