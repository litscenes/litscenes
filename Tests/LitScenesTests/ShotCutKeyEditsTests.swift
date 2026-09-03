import Foundation
import Testing
@testable import LitScenes

// The picture-parity laws: the two-press B blade, the I/O in-out setters,
// the razor↔material converters behind the popover TIMING, and the strip's
// snap magnets. Keyboard and pointer must commit identical state, so these
// tests derive expectations from the assembly's own plan clips rather than
// hardcoding shave arithmetic.

private func keyFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        label: "Frame \(id)",
        imagePath: "/tmp/\(id).png",
        prompt: "A quiet harbor \(id)",
        status: "ready"
    )
}

private let keyFrames: [String: ProjectLensHeroImage] = [
    "f1": keyFrame("f1"),
    "f2": keyFrame("f2"),
    "f3": keyFrame("f3")
]

private func keyAssembly(_ shot: ProjectShot) -> ShotCutAssembly {
    let plan = shotRenderSegmentPlan(
        shot: shot,
        frameLookup: keyFrames,
        mediaLookup: [:],
        meaningNodes: []
    )
    return shotCutAssembly(
        shot: shot,
        planSegments: plan.segments,
        clipDurationsByPath: ["/tmp/a.mp4": 4, "/tmp/b.mp4": 6],
        fileExists: { _ in true }
    )
}

private func keyShot() -> ProjectShot {
    var artifact = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "ready",
        generatedAt: "t0",
        updatedAt: "t0"
    )
    artifact.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: "/tmp/a.mp4",
        updatedAt: "t0"
    ))
    artifact.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f2",
        endFrameImageId: "f3",
        clipPath: "/tmp/b.mp4",
        updatedAt: "t0"
    ))
    let shot = ProjectShot(
        shotId: "shot_key_edits",
        name: "Key edits",
        entries: [
            ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
            ShotFrameEntry(entryId: "e2", frameImageId: "f2"),
            ShotFrameEntry(entryId: "e3", frameImageId: "f3")
        ]
    )
    return shot.upsertingRenderVersion(artifact, activate: true, now: "t0")
}

@Test func bladeAppendsARazorInClipLocalSecondsMarkOrderFree() throws {
    let assembly = keyAssembly(keyShot())
    let clip = try #require(assembly.planClips.first)
    let band = try #require(assembly.bands.first)
    let inMark = clip.materialStartSeconds + 0.4
    let outMark = clip.materialStartSeconds + 1.6

    let list = try #require(shotBladeCutList(
        markMaterialSeconds: inMark,
        toMaterialSeconds: outMark,
        assembly: assembly,
        cutList: ShotCutList(),
        now: "t1"
    ))
    let cut = try #require(list.segmentCuts.first)
    #expect(cut.segmentKey == band.segmentKey)
    #expect(cut.clipPath == band.clipPath)
    // Persisted in the clip's own local seconds, exactly like the drag razor.
    #expect(abs(cut.startSeconds - (clip.headSeconds + 0.4)) < 0.000_1)
    #expect(abs(cut.endSeconds - (clip.headSeconds + 1.6)) < 0.000_1)

    // The two presses may land in either order (each append mints its own
    // cut id, so compare the range, not the identity).
    let reversed = try #require(shotBladeCutList(
        markMaterialSeconds: outMark,
        toMaterialSeconds: inMark,
        assembly: assembly,
        cutList: ShotCutList(),
        now: "t1"
    ))
    let reversedCut = try #require(reversed.segmentCuts.first)
    #expect(reversedCut.segmentKey == cut.segmentKey)
    #expect(abs(reversedCut.startSeconds - cut.startSeconds) < 0.000_1)
    #expect(abs(reversedCut.endSeconds - cut.endSeconds) < 0.000_1)
}

@Test func bladeRefusesCrossBandAndSliverRanges() throws {
    let assembly = keyAssembly(keyShot())
    try #require(assembly.planClips.count == 2)
    let first = assembly.planClips[0]
    let second = assembly.planClips[1]

    // Marks in two different bands: a razor range never crosses a splice.
    #expect(shotBladeCutList(
        markMaterialSeconds: first.materialStartSeconds + 0.5,
        toMaterialSeconds: second.materialStartSeconds + 0.5,
        assembly: assembly,
        cutList: ShotCutList(),
        now: "t1"
    ) == nil)

    // A range under the razor minimum refuses rather than persisting a sliver.
    #expect(shotBladeCutList(
        markMaterialSeconds: first.materialStartSeconds + 1,
        toMaterialSeconds: first.materialStartSeconds + 1.01,
        assembly: assembly,
        cutList: ShotCutList(),
        now: "t1"
    ) == nil)
}

@Test func inOutSettersClampExactlyLikeTheHandles() throws {
    let assembly = keyAssembly(keyShot())
    let material = assembly.materialSeconds

    // IN at a plain interior point stores it.
    var list = shotCutListSettingIn(ShotCutList(), materialSeconds: 1, assemblyMaterialSeconds: material)
    #expect(list.shotInSeconds == 1)

    // IN at zero is "no head trim" — nil, not a stored zero.
    list = shotCutListSettingIn(list, materialSeconds: 0, assemblyMaterialSeconds: material)
    #expect(list.shotInSeconds == nil)

    // IN can never pass the out point's minimum clearance.
    var trimmed = ShotCutList()
    trimmed.shotOutSeconds = 2
    trimmed = shotCutListSettingIn(trimmed, materialSeconds: 5, assemblyMaterialSeconds: material)
    #expect(abs((trimmed.shotInSeconds ?? 0) - (2 - ShotCutList.minimumRangeSeconds)) < 0.000_1)

    // OUT at (or past) the material end clears honestly — nil, never a copy
    // of the duration that would go stale on re-render.
    var out = shotCutListSettingOut(ShotCutList(), materialSeconds: material, assemblyMaterialSeconds: material)
    #expect(out.shotOutSeconds == nil)

    // An interior OUT stores; one under IN's clearance clamps up.
    out.shotInSeconds = 3
    out = shotCutListSettingOut(out, materialSeconds: 1, assemblyMaterialSeconds: material)
    #expect(abs((out.shotOutSeconds ?? 0) - (3 + ShotCutList.minimumRangeSeconds)) < 0.000_1)

    // nil clears both ways.
    #expect(shotCutListSettingIn(out, materialSeconds: nil, assemblyMaterialSeconds: material).shotInSeconds == nil)
    #expect(shotCutListSettingOut(out, materialSeconds: nil, assemblyMaterialSeconds: material).shotOutSeconds == nil)
}

@Test func razorMaterialRangeRoundTripsThroughThePopoverCommit() throws {
    let assembly = keyAssembly(keyShot())
    let clip = try #require(assembly.planClips.first)
    let blade = try #require(shotBladeCutList(
        markMaterialSeconds: clip.materialStartSeconds + 0.5,
        toMaterialSeconds: clip.materialStartSeconds + 1.5,
        assembly: assembly,
        cutList: ShotCutList(),
        now: "t1"
    ))
    let cut = try #require(blade.segmentCuts.first)

    // The material range reads back what the blade meant.
    let range = try #require(shotRazorCutMaterialRange(cut: cut, assembly: assembly))
    #expect(abs(range.lowerBound - (clip.materialStartSeconds + 0.5)) < 0.000_1)
    #expect(abs(range.upperBound - (clip.materialStartSeconds + 1.5)) < 0.000_1)

    // Nudging the range through the popover commit moves it and keeps identity.
    let moved = try #require(shotCutListReplacingRazorRange(
        blade,
        cutId: cut.id,
        materialStart: clip.materialStartSeconds + 0.75,
        materialEnd: clip.materialStartSeconds + 1.75,
        assembly: assembly,
        now: "t2"
    ))
    let movedCut = try #require(moved.segmentCuts.first)
    #expect(movedCut.id == cut.id)
    let movedRange = try #require(shotRazorCutMaterialRange(cut: movedCut, assembly: assembly))
    #expect(abs(movedRange.lowerBound - (clip.materialStartSeconds + 0.75)) < 0.000_1)

    // A degenerate replacement floors at the razor minimum instead of
    // persisting a sliver the drop filter would erase.
    let floored = try #require(shotCutListReplacingRazorRange(
        blade,
        cutId: cut.id,
        materialStart: clip.materialStartSeconds + 1,
        materialEnd: clip.materialStartSeconds + 1,
        assembly: assembly,
        now: "t2"
    ))
    let flooredCut = try #require(floored.segmentCuts.first)
    #expect(flooredCut.seconds >= ShotCutList.minimumRangeSeconds - 0.000_1)
}

@Test func stripSnapTargetsCarryEveryHonestMagnet() throws {
    let assembly = keyAssembly(keyShot())
    let clip = try #require(assembly.planClips.first)
    var cutList = try #require(shotBladeCutList(
        markMaterialSeconds: clip.materialStartSeconds + 0.5,
        toMaterialSeconds: clip.materialStartSeconds + 1.5,
        assembly: assembly,
        cutList: ShotCutList(),
        now: "t1"
    ))
    cutList.shotInSeconds = 0.25

    let targets = shotStripSnapTargets(
        assembly: assembly,
        cutList: cutList,
        playheadMaterialSeconds: 2.2
    )
    func holds(_ value: Double) -> Bool { targets.contains { abs($0 - value) < 0.000_1 } }
    #expect(holds(0))
    #expect(holds(assembly.materialSeconds))
    #expect(holds(2.2))
    #expect(holds(clip.materialStartSeconds + 0.5))
    #expect(holds(clip.materialStartSeconds + 1.5))
    #expect(holds(0.25))
    for planClip in assembly.planClips {
        #expect(holds(planClip.materialStartSeconds))
        #expect(holds(planClip.materialStartSeconds + planClip.materialSeconds))
    }
}
