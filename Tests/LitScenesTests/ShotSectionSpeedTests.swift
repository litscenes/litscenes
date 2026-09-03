import Foundation
import Testing
@testable import LitScenes

// MARK: Fixtures (duplicated per house style)

private func speedFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        label: "Frame \(id)",
        imagePath: "/tmp/\(id).png",
        prompt: "A quiet harbor scene \(id)",
        status: "ready"
    )
}

private let speedFrameLookup: [String: ProjectLensHeroImage] = [
    "f1": speedFrame("f1"),
    "f2": speedFrame("f2")
]

private func speedVideoMedia(_ id: String, durationSeconds: Double = 10) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: id,
        sourceId: "source_test",
        kind: .video,
        filename: "\(id).mp4",
        path: "/tmp/\(id).mp4",
        relativePath: "\(id).mp4",
        byteCount: 1,
        modifiedAt: "2026-08-06T00:00:00Z",
        width: 1920,
        height: 1080,
        durationSeconds: durationSeconds,
        nominalFrameRate: 24,
        thumbnailPath: "/tmp/\(id)_thumb.jpg",
        videoStripPath: nil,
        scannedAt: "2026-08-06T00:00:00Z",
        scanError: nil
    )
}

private func approx(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.001) -> Bool {
    abs(lhs - rhs) <= tolerance
}

private func renderedPairShot(takePath: String = "/tmp/take_one.mp4") -> ProjectShot {
    var artifact = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "ready",
        generatedAt: "2026-08-06T00:00:00Z",
        updatedAt: "2026-08-06T00:00:00Z"
    )
    artifact.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: takePath,
        updatedAt: "2026-08-06T00:00:00Z"
    ))
    var shot = ProjectShot(shotId: "shot_speed", name: "Speed", entries: [
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ])
    shot = shot.upsertingRenderVersion(artifact, activate: true, now: "2026-08-06T00:00:00Z")
    return shot
}

private func assemblyOf(
    _ shot: ProjectShot,
    durations: [String: Double] = ["/tmp/take_one.mp4": 7.9],
    media: [String: MediaItemRecord] = [:],
    fileExists: @escaping (String) -> Bool = { _ in true }
) -> ShotCutAssembly {
    let plan = shotRenderSegmentPlan(
        shot: shot,
        frameLookup: speedFrameLookup,
        mediaLookup: media,
        meaningNodes: []
    )
    return shotCutAssembly(
        shot: shot,
        planSegments: plan.segments,
        clipDurationsByPath: durations,
        fileExists: fileExists
    )
}

/// Applies a section rate over material [low, high] the way the engine op
/// does: spans off the forward assembly, then the pure kernel.
private func appliedSection(
    _ shot: ProjectShot,
    low: Double,
    high: Double,
    rate: Double,
    durations: [String: Double] = ["/tmp/take_one.mp4": 7.9],
    media: [String: MediaItemRecord] = [:]
) -> ProjectShot? {
    let spans = shotCopiedSpans(
        assembly: assemblyOf(shot, durations: durations, media: media),
        materialStart: low,
        materialEnd: high
    )
    return shotApplyingSectionRate(shot, spans: spans, rate: rate, now: "2026-08-06T00:00:01Z")
}

// MARK: 1–3 · The composite

@Test func sectionRateAppliesRazorPlusMutedCarrierInPlace() {
    let shot = renderedPairShot()
    guard let sectioned = appliedSection(shot, low: 2, high: 4, rate: 0.5) else {
        #expect(Bool(false))
        return
    }
    // One razor, pinned to the take (the razor law verbatim).
    #expect(sectioned.cutList.segmentCuts.count == 1)
    #expect(sectioned.cutList.segmentCuts[0].clipPath == "/tmp/take_one.mp4")
    #expect(approx(sectioned.cutList.segmentCuts[0].startSeconds, 2))
    #expect(approx(sectioned.cutList.segmentCuts[0].endSeconds, 4))
    // One carrier: born muted, linked, anchored at the span start.
    #expect(sectioned.pictureInsertions.count == 1)
    let carrier = sectioned.pictureInsertions[0]
    #expect(carrier.muteSourceAudio)
    #expect(carrier.playbackRate == 0.5)
    #expect(carrier.replacesRazorCutIds == [sectioned.cutList.segmentCuts[0].id])
    // The assembly plays keep · carrier-at-rate · keep, exactly in place.
    let assembly = assemblyOf(sectioned)
    #expect(assembly.playbackItems.count == 3)
    #expect(assembly.playbackItems[0].keepRange == ShotKeepRange(start: 0, end: 2))
    #expect(assembly.playbackItems[1].insertionId == carrier.insertionId)
    #expect(approx(assembly.playbackItems[1].durationSeconds, 4))
    #expect(!assembly.playbackItems[1].includeAudio)
    #expect(assembly.playbackItems[2].keepRange == ShotKeepRange(start: 4, end: 7.9))
    #expect(approx(assembly.outputSeconds, 9.9))
}

@Test func sectionRateAcrossExistingRazorMintsPerSpanInOrder() {
    var shot = renderedPairShot()
    shot.cutList = ShotCutList(segmentCuts: [
        ShotSegmentCutRange(segmentKey: "f1>f2", clipPath: "/tmp/take_one.mp4", startSeconds: 3, endSeconds: 5)
    ])
    // Selection [2,6] crosses the razored gap: two spans, two linked pairs.
    guard let sectioned = appliedSection(shot, low: 2, high: 6, rate: 2) else {
        #expect(Bool(false))
        return
    }
    #expect(sectioned.cutList.segmentCuts.count == 3)
    #expect(sectioned.pictureInsertions.count == 2)
    #expect(sectioned.pictureInsertions.allSatisfy { $0.replacesRazorCutIds.count == 1 })
    let assembly = assemblyOf(sectioned)
    let carriers = assembly.playbackItems.filter(\.isInsertion)
    #expect(carriers.count == 2)
    // Material order preserved: [2,3] plays before [5,6].
    #expect(carriers[0].keepRange == ShotKeepRange(start: 2, end: 3))
    #expect(carriers[1].keepRange == ShotKeepRange(start: 5, end: 6))
    // 7.9 material − 2 razored (original) − 2 sectioned + 2/2 sped = 4.9 + 1
    #expect(approx(assembly.outputSeconds, 7.9 - 2 - 2 + 1))
}

@Test func sectionRateFootageSpanPinsNoClipPath() {
    var shot = ProjectShot(shotId: "shot_footage", name: "Footage", entries: [
        ShotFrameEntry(entryId: "e1", clipMediaId: "vid_1")
    ])
    shot.seedSegmentClips = [ShotRenderSegmentClip(
        startFrameImageId: shotFootageKey(mediaId: "vid_1", startSeconds: nil, endSeconds: nil),
        endFrameImageId: "",
        placementStartEntryId: "e1",
        placementEndEntryId: "",
        clipPath: "/tmp/vid_1.mp4",
        durationSeconds: 10,
        updatedAt: "2026-08-06T00:00:00Z"
    )]
    let media = ["vid_1": speedVideoMedia("vid_1")]
    let durations = ["/tmp/vid_1.mp4": 10.0]
    guard let sectioned = appliedSection(
        shot, low: 2, high: 4, rate: 0.5, durations: durations, media: media
    ) else {
        #expect(Bool(false))
        return
    }
    // Footage razors carry "" and persist across renders; the carrier keeps
    // the file-level identity (path + mediaId).
    #expect(sectioned.cutList.segmentCuts.count == 1)
    #expect(sectioned.cutList.segmentCuts[0].clipPath.isEmpty)
    #expect(sectioned.pictureInsertions[0].sourceMediaId == "vid_1")
    #expect(sectioned.pictureInsertions[0].sourceClipPath == "/tmp/vid_1.mp4")
    let assembly = assemblyOf(sectioned, durations: durations, media: media)
    #expect(assembly.playbackItems.filter(\.isInsertion).count == 1)
    #expect(approx(assembly.outputSeconds, 10 - 2 + 4))
}

// MARK: 4–5 · Refusal predicates

@Test func sectionRateRefusesIdentityEmptyAndSubFrame() {
    let shot = renderedPairShot()
    // Identity and empty-span refusals live in the kernel.
    #expect(appliedSection(shot, low: 2, high: 4, rate: 1.0) == nil)
    #expect(shotApplyingSectionRate(shot, spans: [], rate: 0.5, now: "t") == nil)
    // THE 2-FRAME OUTPUT LAW: a 0.1s span at 4× would output 0.025s.
    let tiny = [ShotPictureSegmentSpanRef(
        segmentKey: "f1>f2",
        clipPath: "/tmp/take_one.mp4",
        startSeconds: 2,
        endSeconds: 2.1
    )]
    #expect(shotSectionRateSubFrameSpanSeconds(spans: tiny, rate: 4).map { approx($0, 0.1) } == true)
    #expect(shotSectionRateSubFrameSpanSeconds(spans: tiny, rate: 1) == nil)
    let ample = [ShotPictureSegmentSpanRef(
        segmentKey: "f1>f2",
        clipPath: "/tmp/take_one.mp4",
        startSeconds: 2,
        endSeconds: 4
    )]
    #expect(shotSectionRateSubFrameSpanSeconds(spans: ample, rate: 8) == nil)
}

@Test func sectionCarrierIdsAndOverlapDetection() {
    let shot = renderedPairShot()
    guard let sectioned = appliedSection(shot, low: 3, high: 5, rate: 0.5) else {
        #expect(Bool(false))
        return
    }
    let cutId = sectioned.cutList.segmentCuts[0].id
    #expect(shotSectionCarrierIds(insertions: sectioned.pictureInsertions, cutId: cutId)
        == [sectioned.pictureInsertions[0].insertionId])
    #expect(shotSectionCarrierIds(insertions: sectioned.pictureInsertions, cutId: "cut_other").isEmpty)
    // The D4 predicate: a later selection materially overlapping the carrier
    // razor is detectable via its material range.
    let assembly = assemblyOf(sectioned)
    let range = shotRazorCutMaterialRange(cut: sectioned.cutList.segmentCuts[0], assembly: assembly)
    #expect(range != nil)
    #expect(range.map { $0.upperBound > 2 && $0.lowerBound < 4 } == true)   // overlaps [2,4]
    #expect(range.map { $0.upperBound > 5.5 && $0.lowerBound < 6 } == false) // clear of [5.5,6]
}

// MARK: 6–7 · The link law round trips

@Test func removingSectionSpeedRestoresLinkedRazors() {
    let shot = renderedPairShot()
    guard let sectioned = appliedSection(shot, low: 2, high: 4, rate: 0.5) else {
        #expect(Bool(false))
        return
    }
    let carrierId = sectioned.pictureInsertions[0].insertionId
    guard let removed = shotRemovingSectionSpeed(
        sectioned,
        insertionIds: [carrierId],
        now: "2026-08-06T00:00:02Z"
    ) else {
        #expect(Bool(false))
        return
    }
    // R1: back to 1× — no razor, no carrier, original runtime.
    #expect(removed.restoredCutIds.count == 1)
    #expect(removed.shot.cutList.segmentCuts.isEmpty)
    #expect(removed.shot.pictureInsertions.isEmpty)
    #expect(approx(assemblyOf(removed.shot).outputSeconds, 7.9))

    // Dangling link ids are tolerated: a hand-broken link removes only the
    // carrier and touches no unrelated cut.
    var dangling = sectioned
    dangling.pictureInsertions[0].replacesRazorCutIds = ["cut_gone"]
    let tolerant = shotRemovingSectionSpeed(
        dangling,
        insertionIds: [carrierId],
        now: "2026-08-06T00:00:03Z"
    )
    #expect(tolerant?.restoredCutIds.isEmpty == true)
    #expect(tolerant?.shot.cutList.segmentCuts.count == 1)
}

@Test func recopyRepinsLinkedRazorsOntoActiveTake() {
    let shot = renderedPairShot()
    guard let sectioned = appliedSection(shot, low: 2, high: 4, rate: 0.5) else {
        #expect(Bool(false))
        return
    }
    // A re-render lands: active take moves to take_two — razor dead
    // (clipPath pin), carrier inert (olderTake), section absent, ONCE at 1×.
    var v2 = ShotRenderArtifact(
        versionId: "v2",
        versionNumber: 2,
        status: "ready",
        generatedAt: "2026-08-06T00:01:00Z",
        updatedAt: "2026-08-06T00:01:00Z"
    )
    v2.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        clipPath: "/tmp/take_two.mp4",
        updatedAt: "2026-08-06T00:01:00Z"
    ))
    let rerendered = sectioned.upsertingRenderVersion(v2, activate: true, now: "2026-08-06T00:01:00Z")
    let inertAssembly = assemblyOf(rerendered, durations: ["/tmp/take_two.mp4": 7.9])
    #expect(inertAssembly.playbackItems.count == 1)
    #expect(inertAssembly.insertionCells.first?.state == .olderTake)
    #expect(approx(inertAssembly.outputSeconds, 7.9))

    // R3: Re-copy re-pins BOTH halves — the section returns, exactly once.
    guard let recopied = shotRecopyingSectionInsertion(
        rerendered,
        insertionId: sectioned.pictureInsertions[0].insertionId,
        activePath: "/tmp/take_two.mp4",
        now: "2026-08-06T00:02:00Z"
    ) else {
        #expect(Bool(false))
        return
    }
    #expect(recopied.cutList.segmentCuts[0].clipPath == "/tmp/take_two.mp4")
    let revived = assemblyOf(recopied, durations: ["/tmp/take_two.mp4": 7.9])
    #expect(revived.playbackItems.count == 3)
    #expect(revived.playbackItems.filter(\.isInsertion).count == 1)
    #expect(revived.insertionCells.first?.state == .fresh)
    #expect(approx(revived.outputSeconds, 9.9))
}

// MARK: 8–9 · Display + tolerance

@Test func carrierNeverConsolidatesWithPlainLoopSiblings() {
    let shot = renderedPairShot()
    guard var sectioned = appliedSection(shot, low: 2, high: 4, rate: 0.5) else {
        #expect(Bool(false))
        return
    }
    // A plain copy shaped identically to the carrier (same span, rate, mute,
    // group) — only the link differs; it must stay its own cell.
    var twin = sectioned.pictureInsertions[0]
    twin.insertionId = "pins_twin"
    twin.replacesRazorCutIds = []
    twin.loopGroupId = "loopg_x"
    sectioned.pictureInsertions[0].loopGroupId = "loopg_x"
    sectioned.pictureInsertions.append(twin)
    let runs = shotInsertionCellRuns(assemblyOf(sectioned).insertionCells)
    #expect(runs.map(\.count) == [1, 1])
}

@Test func replacesRazorCutIdsTolerantDecodeAndNormalize() throws {
    let sparse = #"{"insertionId":"pins_x","sourceSegmentKey":"f1>f2","sourceClipPath":"/tmp/t.mp4","sourceStartSeconds":1,"sourceEndSeconds":2,"anchorSegmentKey":"f1>f2"}"#
    let decoded = try JSONDecoder().decode(ShotPictureInsertion.self, from: Data(sparse.utf8))
    #expect(decoded.replacesRazorCutIds.isEmpty)

    var linked = decoded
    linked.replacesRazorCutIds = [" cut_a ", "", "cut_b"]
    #expect(linked.normalized().replacesRazorCutIds == ["cut_a", "cut_b"])

    var shot = renderedPairShot()
    shot.pictureInsertions = [linked.normalized()]
    let roundTrip = try JSONDecoder().decode(ProjectShot.self, from: JSONEncoder().encode(shot))
    #expect(roundTrip.pictureInsertions[0].replacesRazorCutIds == ["cut_a", "cut_b"])
    #expect(shot.pictureStateSnapshot().pictureInsertions[0].replacesRazorCutIds == ["cut_a", "cut_b"])
}

// MARK: 10–12 · Direction, reverse, twins

@Test func sectionRippleStartIsDirectionFree() {
    let shot = renderedPairShot()
    let forward = assemblyOf(shot)
    // Forward: the section's output start is its low material projection.
    #expect(approx(shotSectionRippleStart(assembly: forward, materialLow: 2, materialHigh: 4), 2))
    // Reversed: the section STARTS in output where its HIGH bound maps.
    let proxies = ["/tmp/take_one.mp4": ShotReverseProxyArtifact(
        proxyId: "p1",
        sourcePath: "/tmp/take_one.mp4",
        sourceDurationSeconds: 7.9,
        proxyDurationSeconds: 7.9,
        proxyPath: "/tmp/rev_take_one.mp4",
        hasReversedAudio: true,
        status: "ready"
    )]
    let reversed = reversedShotCutAssembly(forward, proxies: proxies)
    let start = shotSectionRippleStart(assembly: reversed, materialLow: 2, materialHigh: 4)
    #expect(approx(start, 7.9 - 4))
}

@Test func reversedAssemblyCarriesSectionCarrier() {
    let shot = renderedPairShot()
    guard let sectioned = appliedSection(shot, low: 2, high: 4, rate: 0.5) else {
        #expect(Bool(false))
        return
    }
    let forward = assemblyOf(sectioned)
    let proxies = ["/tmp/take_one.mp4": ShotReverseProxyArtifact(
        proxyId: "p1",
        sourcePath: "/tmp/take_one.mp4",
        sourceDurationSeconds: 7.9,
        proxyDurationSeconds: 7.9,
        proxyPath: "/tmp/rev_take_one.mp4",
        hasReversedAudio: true,
        status: "ready"
    )]
    let reversed = reversedShotCutAssembly(forward, proxies: proxies)
    #expect(reversed.isReversed)
    let carrier = reversed.playbackItems.first(where: \.isInsertion)
    #expect(carrier?.playsReversed == true)
    #expect(carrier?.playbackRate == 0.5)
    #expect(approx(reversed.outputSeconds, forward.outputSeconds))
}

@Test func duplicatedShotDropsCarriersKeepsCutList() {
    let shot = renderedPairShot()
    guard let sectioned = appliedSection(shot, low: 2, high: 4, rate: 0.5) else {
        #expect(Bool(false))
        return
    }
    // D7 documented: the twin keeps the cut list (orphan carrier razors go
    // inert/pruned by existing laws) and drops the carriers — dangling links
    // never form because the insertions are gone entirely.
    let twin = sectioned.duplicated(now: "2026-08-06T00:03:00Z")
    #expect(twin.pictureInsertions.isEmpty)
    #expect(twin.cutList.segmentCuts.count == 1)
}

// MARK: Seed-covered shots (combined CUTs / pasted segment cards)

/// SHOT 35's shape: a pair playing from a SEED clip, no render version — the
/// combined-CUT reality where the "speed deleted my section" bug
/// lived (freshness judged by version clips alone = carrier inert at birth).
private func seededPairShot() -> ProjectShot {
    var shot = ProjectShot(shotId: "shot_seeded", name: "CUT + CUT", entries: [
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ])
    shot.seedSegmentClips = [ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        placementStartEntryId: "e1",
        placementEndEntryId: "e2",
        clipPath: "/tmp/seed_take.mp4",
        durationSeconds: 7.9,
        updatedAt: "2026-08-06T00:00:00Z"
    )]
    return shot
}

@Test func sectionRateOnASeededShotPlaysTheCarrierNotJustTheRazor() {
    let shot = seededPairShot()
    let durations = ["/tmp/seed_take.mp4": 7.9]
    guard let sectioned = appliedSection(shot, low: 2, high: 4, rate: 0.5, durations: durations) else {
        #expect(Bool(false))
        return
    }
    let assembly = assemblyOf(sectioned, durations: durations)
    // The whole point: keep · FRESH carrier at rate · keep — never a bare cut.
    #expect(assembly.playbackItems.count == 3)
    #expect(assembly.insertionCells.first?.state == .fresh)
    #expect(assembly.playbackItems[1].insertionId == sectioned.pictureInsertions[0].insertionId)
    #expect(approx(assembly.playbackItems[1].durationSeconds, 4))
    #expect(approx(assembly.outputSeconds, 7.9 + 2))
    // The rail counts it too (the runtime mirror shares the authority).
    #expect(approx(shotPictureInsertionRuntimeSeconds(shot: sectioned), 4))
}

@Test func activeTakeAuthorityPrefersVersionClipsOverSeeds() {
    var shot = seededPairShot()
    // Seed alone: the seed IS the active take.
    #expect(shotActiveTakePathsBySegmentKey(shot: shot)["entry:e1>e2"] == "/tmp/seed_take.mp4")
    // A ready version's clip for the same placement takes precedence — the
    // same `saved ?? seedClip` order band resolution uses.
    var v1 = ShotRenderArtifact(
        versionId: "v1",
        versionNumber: 1,
        status: "ready",
        videoPath: "/tmp/v1.mp4",
        generatedAt: "2026-08-06T00:01:00Z",
        updatedAt: "2026-08-06T00:01:00Z"
    )
    v1.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        placementStartEntryId: "e1",
        placementEndEntryId: "e2",
        clipPath: "/tmp/version_take.mp4",
        updatedAt: "2026-08-06T00:01:00Z"
    ))
    shot = shot.upsertingRenderVersion(v1, activate: true, now: "2026-08-06T00:01:00Z")
    #expect(shotActiveTakePathsBySegmentKey(shot: shot)["entry:e1>e2"] == "/tmp/version_take.mp4")
}
