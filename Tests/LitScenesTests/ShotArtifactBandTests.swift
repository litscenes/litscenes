import Foundation
import Testing
@testable import LitScenes

// MARK: Fixtures

private func artifactFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        label: "Frame \(id)",
        imagePath: "/tmp/\(id).png",
        prompt: "A quiet harbor scene \(id)",
        status: "ready"
    )
}

private let artifactFrameLookup: [String: ProjectLensHeroImage] = [
    "f1": artifactFrame("f1"),
    "f2": artifactFrame("f2")
]

private func artifactShot() -> ProjectShot {
    ProjectShot(shotId: "shot_artifact", name: "Artifact band", entries: [
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ])
}

/// A ready version whose full video exists but whose saved clip belongs to a
/// PAST plan shape — the exact state that used to leave the cut layer inert.
private func staleReadyVersion() -> ShotRenderArtifact {
    var version = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "ready",
        videoPath: "/tmp/full_render.mp4",
        generatedAt: "2026-08-13T00:00:00Z",
        updatedAt: "2026-08-13T00:00:00Z"
    )
    version.totalSeconds = 5
    version.clipPaths = ["/tmp/old_take.mp4"]
    version.segmentCount = 1
    version.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "old_frame",
        endFrameImageId: "",
        placementStartEntryId: "entry_from_another_life",
        placementEndEntryId: "",
        clipPath: "/tmp/old_take.mp4",
        durationSeconds: 5.0,
        updatedAt: "2026-08-13T00:00:00Z"
    ))
    return version
}

private func artifactPlanSegments(_ shot: ProjectShot) -> [ShotRenderPlanSegment] {
    shotRenderSegmentPlan(
        shot: shot,
        frameLookup: artifactFrameLookup,
        mediaLookup: [:],
        meaningNodes: []
    ).segments
}

private func approx(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.001) -> Bool {
    abs(lhs - rhs) <= tolerance
}

// MARK: Key vocabulary

@Test func artifactSegmentKeyRoundTripsAndRejectsBarePrefix() {
    #expect(shotArtifactSegmentKey(versionId: "v1") == "artifact:v1")
    #expect(shotArtifactSegmentKeyVersionId("artifact:v1") == "v1")
    #expect(shotArtifactSegmentKeyVersionId("artifact:") == nil)
    #expect(shotArtifactSegmentKeyVersionId("f1>f2") == nil)
    #expect(shotArtifactSegmentKeyVersionId("entry:a>b") == nil)
}

@Test func artifactKeysAreProducibleAndOtherKeyFormsStayLawful() {
    let identity = ShotSegmentKeyIdentity(entries: [
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ])
    // Well-formed artifact keys are producible regardless of entries —
    // version honesty is the sweep's job.
    #expect(identity.canProduce("artifact:v1"))
    #expect(!identity.canProduce("artifact:"))
    // Existing forms unchanged.
    #expect(identity.canProduce("f1>f2"))
    #expect(!identity.canProduce("f1>zz"))
    #expect(identity.canProduce("entry:e1>e2"))
    #expect(!identity.canProduce("entry:ghost>e2"))
}

// MARK: Geometry

@Test func artifactBandGeometryShavesJoinsAndDegradesHonestly() {
    var artifact = ShotRenderArtifact(versionId: "v1", versionNumber: 1, status: "ready")
    artifact.totalSeconds = 15
    artifact.clipPaths = ["/tmp/c1.mp4", "/tmp/c2.mp4", "/tmp/c3.mp4"]
    for (index, path) in artifact.clipPaths.enumerated() {
        artifact.segmentClips.append(ShotRenderSegmentClip(
            startFrameImageId: "s\(index)",
            endFrameImageId: "e\(index)",
            placementStartEntryId: "p\(index)",
            placementEndEntryId: "q\(index)",
            clipPath: path,
            durationSeconds: 5.0,
            updatedAt: "1"
        ))
    }
    let geometry = shotArtifactBandGeometry(artifact)
    // 3 × 5s minus two 3-frame handoff shaves.
    #expect(approx(geometry.durationSeconds, 15 - 2 * (3.0 / 24.0)))
    #expect(geometry.seamSeconds.count == 2)
    #expect(approx(geometry.seamSeconds[0], 5))
    #expect(approx(geometry.seamSeconds[1], 5 + 5 - 3.0 / 24.0))

    // A clipPath with no matching clip record: rounded total, NO fake seams.
    artifact.segmentClips.removeLast()
    let degraded = shotArtifactBandGeometry(artifact)
    #expect(degraded.durationSeconds == 15)
    #expect(degraded.seamSeconds.isEmpty)
}

// MARK: The fallback

@Test func assemblyEmitsArtifactBandWhenPlanResolvesNothing() {
    var shot = artifactShot()
    shot = shot.upsertingRenderVersion(staleReadyVersion(), activate: true, now: "2026-08-13T00:00:00Z")
    let assembly = shotCutAssembly(
        shot: shot,
        planSegments: artifactPlanSegments(shot),
        clipDurationsByPath: [:],
        fileExists: { _ in true }
    )
    #expect(assembly.bands.count == 1)
    #expect(assembly.bands[0].segmentKey == "artifact:v1")
    #expect(assembly.bands[0].clipPath == "/tmp/full_render.mp4")
    #expect(assembly.bands[0].skipTarget == nil)
    #expect(assembly.bands[0].label == "RENDER I · 1 SEGMENT")
    #expect(assembly.hasPlayableClips)
    // Duration from the geometry (single clip: no shave).
    #expect(approx(assembly.materialSeconds, 5))
    // The probed duration wins once loaded.
    let probed = shotCutAssembly(
        shot: shot,
        planSegments: artifactPlanSegments(shot),
        clipDurationsByPath: ["/tmp/full_render.mp4": 5.042],
        fileExists: { _ in true }
    )
    #expect(approx(probed.materialSeconds, 5.042))
}

@Test func artifactFallbackGatesOnVersionVideoAndResolution() {
    var shot = artifactShot()
    shot = shot.upsertingRenderVersion(staleReadyVersion(), activate: true, now: "2026-08-13T00:00:00Z")
    let segments = artifactPlanSegments(shot)

    // Missing file: no fallback, cut layer honestly inert.
    let missingFile = shotCutAssembly(
        shot: shot,
        planSegments: segments,
        clipDurationsByPath: [:],
        fileExists: { $0 != "/tmp/full_render.mp4" }
    )
    #expect(!missingFile.hasPlayableClips)
    #expect(!missingFile.bands.contains { $0.segmentKey.hasPrefix(shotArtifactSegmentKeyPrefix) })

    // A resolving plan never falls back: give the version a clip that
    // matches the live pair placement.
    var resolving = staleReadyVersion()
    resolving.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        placementStartEntryId: "e1",
        placementEndEntryId: "e2",
        clipPath: "/tmp/pair_take.mp4",
        durationSeconds: 5.0,
        updatedAt: "2"
    ))
    var resolvingShot = artifactShot()
    resolvingShot = resolvingShot.upsertingRenderVersion(resolving, activate: true, now: "2026-08-13T00:00:01Z")
    let resolved = shotCutAssembly(
        shot: resolvingShot,
        planSegments: artifactPlanSegments(resolvingShot),
        clipDurationsByPath: [:],
        fileExists: { _ in true }
    )
    #expect(resolved.hasPlayableClips)
    #expect(resolved.bands.first?.clipPath == "/tmp/pair_take.mp4")
    #expect(!resolved.bands.contains { $0.segmentKey.hasPrefix(shotArtifactSegmentKeyPrefix) })
}

// MARK: Razor over the synthetic band

@Test func razorOnTheArtifactBandSurvivesSaveAndSplitsPlayback() {
    var shot = artifactShot()
    shot = shot.upsertingRenderVersion(staleReadyVersion(), activate: true, now: "2026-08-13T00:00:00Z")
    var list = shot.cutList
    list.segmentCuts.append(ShotSegmentCutRange(
        segmentKey: "artifact:v1",
        clipPath: "/tmp/full_render.mp4",
        startSeconds: 2,
        endSeconds: 3,
        updatedAt: "2026-08-13T00:00:00Z"
    ))
    // The persistence funnel: normalized().pruned(entries:) must keep it.
    shot = shot.settingCutList(list, now: "2026-08-13T00:00:01Z")
    #expect(shot.cutList.segmentCuts.map(\.segmentKey) == ["artifact:v1"])

    let assembly = shotCutAssembly(
        shot: shot,
        planSegments: artifactPlanSegments(shot),
        clipDurationsByPath: [:],
        fileExists: { _ in true }
    )
    #expect(assembly.planClips[0].keepRanges == [
        ShotKeepRange(start: 0, end: 2),
        ShotKeepRange(start: 3, end: 5)
    ])
    #expect(approx(assembly.outputSeconds, 4))

    // In/out trims clamp in the same artifact-material space.
    var trimmed = shot
    var trimmedList = trimmed.cutList
    trimmedList.shotInSeconds = 0.5
    trimmedList.shotOutSeconds = 4.5
    trimmed = trimmed.settingCutList(trimmedList, now: "2026-08-13T00:00:02Z")
    let trimmedAssembly = shotCutAssembly(
        shot: trimmed,
        planSegments: artifactPlanSegments(trimmed),
        clipDurationsByPath: [:],
        fileExists: { _ in true }
    )
    #expect(approx(trimmedAssembly.outputSeconds, 3))
}

// MARK: Supersede / sweep

@Test func artifactCutsAreSweptOnlyWhenTheirVersionDies() {
    var shot = artifactShot()
    shot = shot.upsertingRenderVersion(staleReadyVersion(), activate: true, now: "2026-08-13T00:00:00Z")
    shot.cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(cutId: "live", segmentKey: "artifact:v1", clipPath: "/tmp/full_render.mp4", startSeconds: 1, endSeconds: 2),
        ShotSegmentCutRange(cutId: "orphan", segmentKey: "artifact:v_gone", clipPath: "/tmp/gone.mp4", startSeconds: 1, endSeconds: 2)
    ])
    // Retained version + matching path lives; a versionless key is stale.
    #expect(shotStalePinnedCutIds(shot: shot) == ["orphan"])

    // A newer resolving version does NOT sweep the old version's cuts — they
    // merely go inert while unshown (the take-pin doctrine).
    var newer = ShotRenderArtifact(versionId: "v2", versionNumber: 2, status: "ready", videoPath: "/tmp/v2.mp4", generatedAt: "2", updatedAt: "2")
    newer.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        placementStartEntryId: "e1",
        placementEndEntryId: "e2",
        clipPath: "/tmp/v2_take.mp4",
        durationSeconds: 5.0,
        updatedAt: "2"
    ))
    var superseded = shot
    superseded = superseded.upsertingRenderVersion(newer, activate: true, now: "2026-08-13T00:01:00Z")
    #expect(shotStalePinnedCutIds(shot: superseded) == ["orphan"])

    // The version's video re-pointed: its artifact cuts are stale.
    var repointed = superseded
    repointed.renderVersions = repointed.renderVersions.map { version in
        var value = version
        if value.versionId == "v1" { value.videoPath = "/tmp/rebuilt.mp4" }
        return value
    }
    #expect(Set(shotStalePinnedCutIds(shot: repointed)) == Set(["live", "orphan"]))

    // Ordinary pinned cuts keep the existing retained-take law.
    var ordinary = artifactShot()
    ordinary.cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(cutId: "pinned", segmentKey: "f1>f2", clipPath: "/tmp/unretained.mp4", startSeconds: 1, endSeconds: 2)
    ])
    #expect(shotStalePinnedCutIds(shot: ordinary) == ["pinned"])
}

// MARK: Fingerprint motion

@Test func reelBakeFingerprintMovesWithArtifactCuts() {
    var shot = artifactShot()
    shot = shot.upsertingRenderVersion(staleReadyVersion(), activate: true, now: "2026-08-13T00:00:00Z")
    let profile = VideoOutputProfile.standard(.landscape16x9, fitPolicy: .fitWithBlurFill)
    func fingerprint(_ shot: ProjectShot) -> String {
        shotReelBakeFingerprint(
            shot: shot,
            assembly: shotCutAssembly(
                shot: shot,
                planSegments: artifactPlanSegments(shot),
                clipDurationsByPath: [:],
                fileExists: { _ in true }
            ),
            profile: profile
        )
    }
    let base = fingerprint(shot)
    var cutShot = shot
    cutShot.cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(segmentKey: "artifact:v1", clipPath: "/tmp/full_render.mp4", startSeconds: 1, endSeconds: 2)
    ])
    #expect(base != fingerprint(cutShot))
}
