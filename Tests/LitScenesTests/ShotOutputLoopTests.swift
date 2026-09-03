import Foundation
import Testing
@testable import LitScenes

// The whole-output loop law: the ×N output is exactly the ×1 output played N
// times. Expansion happens at the visible-assembly boundary; bands, plan
// clips, insertion cells, and material space stay BASE, because looping what
// you watch does not change what you have.

// MARK: - Fixtures

/// Two spans, 4s then 6s, abutting in both output and material space.
private func loopFixtureItems() -> [ShotCutPlaybackItem] {
    [
        ShotCutPlaybackItem(
            itemId: "a",
            segmentKey: "s1",
            url: URL(fileURLWithPath: "/tmp/a.mp4"),
            keepRange: ShotKeepRange(start: 0, end: 4),
            outputStartSeconds: 0,
            durationSeconds: 4,
            materialStartSeconds: 0,
            materialEndSeconds: 4
        ),
        ShotCutPlaybackItem(
            itemId: "b",
            segmentKey: "s2",
            url: URL(fileURLWithPath: "/tmp/b.mp4"),
            keepRange: ShotKeepRange(start: 0, end: 6),
            outputStartSeconds: 4,
            durationSeconds: 6,
            materialStartSeconds: 4,
            materialEndSeconds: 10
        )
    ]
}

private func loopFixtureAssembly(_ items: [ShotCutPlaybackItem]) -> ShotCutAssembly {
    ShotCutAssembly(
        playbackItems: items,
        outputSeconds: items.reduce(0) { $0 + $1.durationSeconds },
        materialSeconds: 10
    )
}

// MARK: - Expansion

@Test func loopedAssemblyRepeatsSpansWithUniqueItemIdsAndRechainedStarts() {
    let base = loopFixtureAssembly(loopFixtureItems())
    let looped = loopedShotCutAssembly(base, count: 3)

    #expect(looped.playbackItems.count == 6)
    let itemIds = looped.playbackItems.map { $0.itemId }
    #expect(Set(itemIds).count == 6)
    let passes = looped.playbackItems.map { $0.loopPass }
    #expect(passes == [0, 0, 1, 1, 2, 2])
    #expect(abs(looped.outputSeconds - 30) < 1e-9)
    #expect(abs(looped.baseOutputSeconds - 10) < 1e-9)
    #expect(looped.outputLoopCount == 3)
    // Pass 0 stays byte-identical; later passes shift by pass × base.
    #expect(looped.playbackItems[0].itemId == "a")
    let starts = looped.playbackItems.map { $0.outputStartSeconds }
    #expect(starts == [0, 4, 10, 14, 20, 24])
    // Monotone chain with durations preserved.
    for (index, item) in looped.playbackItems.enumerated() where index > 0 {
        let previous = looped.playbackItems[index - 1]
        #expect(abs(previous.outputStartSeconds + previous.durationSeconds - item.outputStartSeconds) < 1e-9)
    }
    // Base spaces stay base: material, bands, cells untouched.
    #expect(abs(looped.materialSeconds - base.materialSeconds) < 1e-9)
    #expect(looped.insertionCells.isEmpty)
    // Repeated spans keep material identity so the strip playhead can cycle.
    #expect(looped.playbackItems[2].materialStartSeconds == 0)
    #expect(looped.playbackItems[2].segmentKey == "s1")
}

@Test func loopCountClampsAndDegenerateAssembliesAreIdentity() {
    let base = loopFixtureAssembly(loopFixtureItems())
    // ×1, ×0, negative: identity.
    #expect(loopedShotCutAssembly(base, count: 1).playbackItems.count == 2)
    #expect(loopedShotCutAssembly(base, count: 0).outputLoopCount == 1)
    #expect(loopedShotCutAssembly(base, count: -3).outputLoopCount == 1)
    // Above the cap: clamps to ×20.
    let capped = loopedShotCutAssembly(base, count: 99)
    #expect(capped.outputLoopCount == ShotCutList.maximumOutputLoopCount)
    #expect(capped.playbackItems.count == 2 * ShotCutList.maximumOutputLoopCount)
    // Empty and zero-duration assemblies never expand.
    #expect(loopedShotCutAssembly(ShotCutAssembly(), count: 4).playbackItems.isEmpty)
    var zero = base
    zero.outputSeconds = 0
    #expect(loopedShotCutAssembly(zero, count: 4).outputLoopCount == 1)
}

// MARK: - Segments, splices, seams

@Test func loopSeamNeverMergesPictureSegmentsInASingleBandShot() {
    // One band, one span: without the pass guard the three passes are band-
    // adjacent and output-contiguous, and would fuse into one segment.
    let single = ShotCutPlaybackItem(
        itemId: "only",
        segmentKey: "s1",
        url: URL(fileURLWithPath: "/tmp/a.mp4"),
        keepRange: ShotKeepRange(start: 0, end: 10),
        outputStartSeconds: 0,
        durationSeconds: 10,
        materialStartSeconds: 0,
        materialEndSeconds: 10
    )
    var base = loopFixtureAssembly([single])
    base.planClips = [ShotCutPlanClip(
        segmentKey: "s1",
        clipPath: "/tmp/a.mp4",
        keepRanges: [ShotKeepRange(start: 0, end: 10)],
        materialStartSeconds: 0,
        materialSeconds: 10,
        outputStartSeconds: 0,
        headSeconds: 0
    )]
    let looped = loopedShotCutAssembly(base, count: 3)

    let segments = looped.outputPictureSegments
    #expect(segments.count == 3)
    let segmentStarts = segments.map { $0.outputStartSeconds }
    #expect(segmentStarts == [0, 10, 20])
    // Splice ids are unique because repeated itemIds are pass-suffixed.
    let splices = looped.outputSplices
    let spliceIds = splices.map { $0.id }
    #expect(Set(spliceIds).count == splices.count)
    // The pass seam is a deterministic hard cut: no dissolve rides across.
    #expect(looped.playbackItems[1].transitionFramesBefore == 0)
    #expect(looped.playbackItems[1].loopPass == 1)
}

// MARK: - Mapping

@Test func loopedMappingCyclesMaterialAndPinsStripSeeksToPassOne() {
    let looped = loopedShotCutAssembly(loopFixtureAssembly(loopFixtureItems()), count: 3)
    // Output → material cycles: the playhead sweeps the strip N times.
    for t in stride(from: 0.0, to: 10.0, by: 0.5) {
        let first = looped.materialSeconds(forOutputSeconds: t)
        let second = looped.materialSeconds(forOutputSeconds: t + 10)
        let third = looped.materialSeconds(forOutputSeconds: t + 20)
        #expect(abs(first - second) < 1e-9)
        #expect(abs(first - third) < 1e-9)
    }
    // Material → output pins to the first pass: a strip click seeks there.
    for s in stride(from: 0.0, through: 10.0, by: 0.5) {
        #expect(looped.outputSeconds(forMaterialSeconds: s) <= 10 + 1e-9)
    }
    // Source capture resolves the on-screen file in every pass.
    #expect(looped.sourceCapture(forOutputSeconds: 15)?.url.path == "/tmp/b.mp4")
}

@Test func reversedThenLoopedAssemblyPlaysEachPassBackwards() {
    // Compose over a reversed assembly: order = looped(reversed(base)).
    var b = loopFixtureItems()[1]
    var a = loopFixtureItems()[0]
    b.outputStartSeconds = 0
    b.playsReversed = true
    a.outputStartSeconds = 6
    a.playsReversed = true
    var reversed = loopFixtureAssembly([b, a])
    reversed.isReversed = true
    let looped = loopedShotCutAssembly(reversed, count: 2)

    #expect(looped.isReversed)
    #expect(looped.playbackItems.count == 4)
    let allReversed = looped.playbackItems.allSatisfy { $0.playsReversed }
    #expect(allReversed)
    // Each pass walks the material backwards, identically.
    for t in stride(from: 0.0, to: 10.0, by: 0.5) {
        let first = looped.materialSeconds(forOutputSeconds: t)
        let second = looped.materialSeconds(forOutputSeconds: t + 10)
        #expect(abs(first - second) < 1e-9)
    }
    #expect(abs(looped.materialSeconds(forOutputSeconds: 0) - 10) < 1e-9)
    #expect(abs(looped.materialSeconds(forOutputSeconds: 10) - 10) < 1e-9)
}

// MARK: - Fingerprints

@Test func loopKeepsLookVisualFingerprintStableWhileReelSpanIdentityMoves() {
    let shot = ProjectShot(shotId: "shot_loop_fp", createdAt: "t0", updatedAt: "t0")
    let base = loopFixtureAssembly(loopFixtureItems())
    let looped = loopedShotCutAssembly(base, count: 3)

    // The Look's visual identity is the BASE edit — pass-0 filter law.
    #expect(shotLookVisualFingerprint(shot: shot, assembly: base)
        == shotLookVisualFingerprint(shot: shot, assembly: looped))
    // The reel bake caches the flattened OUTPUT — a loop must re-bake.
    let profile = VideoOutputProfile.standard(.landscape16x9, fitPolicy: .fitWithBlurFill)
    #expect(shotReelBakeFingerprint(shot: shot, assembly: base, profile: profile)
        != shotReelBakeFingerprint(shot: shot, assembly: looped, profile: profile))
}

// MARK: - Cut list model

@Test func cutListOutputLoopCountDecodesTolerantlyClampsAndRoundTrips() throws {
    // Absent key ⇒ 1, bit-identical to pre-loop documents.
    let absent = try JSONDecoder().decode(
        ShotCutList.self,
        from: Data("{}".utf8)
    )
    #expect(absent.outputLoopCount == 1)
    #expect(absent.isEmpty)

    let explicit = try JSONDecoder().decode(
        ShotCutList.self,
        from: Data(#"{"outputLoopCount": 3}"#.utf8)
    )
    #expect(explicit.outputLoopCount == 3)
    #expect(!explicit.isEmpty)

    // normalized() clamps into 1...maximumOutputLoopCount.
    var list = ShotCutList()
    list.outputLoopCount = 0
    #expect(list.normalized().outputLoopCount == 1)
    list.outputLoopCount = -4
    #expect(list.normalized().outputLoopCount == 1)
    list.outputLoopCount = 99
    #expect(list.normalized().outputLoopCount == ShotCutList.maximumOutputLoopCount)

    // Encode → decode round trip preserves the count.
    list.outputLoopCount = 5
    let decoded = try JSONDecoder().decode(ShotCutList.self, from: JSONEncoder().encode(list))
    #expect(decoded.outputLoopCount == 5)
}

@Test func settingLoopCountIsOnePictureEditAndSnapshotRestoreRoundTrips() {
    var shot = ProjectShot(shotId: "shot_loop_undo", createdAt: "t0", updatedAt: "t0")
    let before = shot.pictureStateSnapshot()

    var list = shot.cutList
    list.outputLoopCount = 4
    shot = shot.settingCutList(list, now: "t1")
    let after = shot.pictureStateSnapshot()
    #expect(before != after)
    #expect(after.cutList.outputLoopCount == 4)

    // Restore returns the exact pre-loop picture state.
    let restored = shot.restoringPictureState(before, now: "t2")
    #expect(restored.pictureStateSnapshot() == before)
    #expect(restored.cutList.outputLoopCount == 1)

    // Re-applying the same count is a no-op in snapshot terms.
    var same = shot.cutList
    same.outputLoopCount = 4
    let reapplied = shot.settingCutList(same, now: "t3")
    #expect(reapplied.pictureStateSnapshot() == after)
}

@Test func cutListEditActionNameNamesLoopEdits() {
    var before = ShotCutList()
    var after = ShotCutList()
    after.outputLoopCount = 3
    #expect(shotCutListEditActionName(before: before, after: after) == "Loop Output ×3")
    before.outputLoopCount = 3
    after.outputLoopCount = 1
    #expect(shotCutListEditActionName(before: before, after: after) == "Remove Output Loop")
}

// MARK: - Audio

@Test func loopPassOffsetsReplicatePerPassAndCollapseUnlooped() {
    #expect(shotLoopPassOffsets(loopCount: 1, baseOutputSeconds: 10) == [0])
    #expect(shotLoopPassOffsets(loopCount: 3, baseOutputSeconds: 0) == [0])
    #expect(shotLoopPassOffsets(loopCount: 3, baseOutputSeconds: 4) == [0, 4, 8])
    // Clamped with the same cap as the expansion.
    #expect(shotLoopPassOffsets(loopCount: 99, baseOutputSeconds: 1).count
        == ShotCutList.maximumOutputLoopCount)
}

@Test func sourceGainWindowsRepeatPerPassFromTheLoopedAssembly() {
    var shot = ProjectShot(shotId: "shot_loop_gain", createdAt: "t0", updatedAt: "t0")
    // One authored envelope over the first 4 material-output seconds.
    shot.audioRegions = [ShotAudioRegion(
        regionId: "env1",
        laneId: ShotAudioLaneId.source,
        path: "/tmp/env.m4a",
        startSeconds: 0,
        durationSeconds: 4,
        gain: 0.5
    )]
    let looped = loopedShotCutAssembly(loopFixtureAssembly(loopFixtureItems()), count: 3)
    let windows = shotSourceGainWindows(shot: shot, assembly: looped)

    // One window per playback item — six items, six windows.
    #expect(windows.count == 6)
    // Every pass hears the SAME authored geometry: the 4s span is enveloped
    // to 0.5, the 6s span is uncovered ⇒ 0 — in pass 1 AND pass 3.
    #expect(abs(windows[0].gain - 0.5) < 1e-9)
    #expect(abs(windows[1].gain - 0) < 1e-9)
    #expect(abs(windows[4].gain - 0.5) < 1e-9)
    #expect(abs(windows[5].gain - 0) < 1e-9)
    // Windows land at the pass's real output seconds.
    #expect(abs(windows[4].startSeconds - 20) < 1e-9)
}

// MARK: - Rail honesty

@Test func runtimeSummaryRailShowsLoopMultiplicationWhileEstimateStaysBase() {
    var summary = ShotRuntimeSummary()
    summary.frames = 2
    summary.bridges = 1
    summary.outputLoopCount = 3
    // Planners keep the base runtime.
    #expect(summary.estimatedSeconds(segmentSeconds: 8) == 8)
    // The rail multiplies it out honestly.
    #expect(summary.railLabel(segmentSeconds: 8).contains("~8S ×3=24S"))
    summary.outputLoopCount = 1
    #expect(summary.railLabel(segmentSeconds: 8).contains("~8S"))
    #expect(!summary.railLabel(segmentSeconds: 8).contains("×"))
}
