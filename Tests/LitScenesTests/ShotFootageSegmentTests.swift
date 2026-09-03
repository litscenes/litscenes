import Foundation
import Testing
@testable import LitScenes

// MARK: Fixtures

private func footageHeroFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        label: "Frame \(id)",
        imagePath: "/tmp/\(id).png",
        prompt: "A quiet harbor scene \(id)",
        status: "ready"
    )
}

private func footageVideoMedia(_ id: String, durationSeconds: Double? = 10) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: id,
        sourceId: "source_test",
        kind: .video,
        filename: "\(id).mp4",
        path: "/tmp/\(id).mp4",
        relativePath: "\(id).mp4",
        byteCount: 1,
        modifiedAt: "2026-07-16T00:00:00Z",
        width: 1080,
        height: 1920,
        durationSeconds: durationSeconds,
        nominalFrameRate: 24,
        thumbnailPath: "/tmp/\(id)_thumb.jpg",
        videoStripPath: nil,
        scannedAt: "2026-07-16T00:00:00Z",
        scanError: nil
    )
}

private func footageShot(_ entries: [ShotFrameEntry]) -> ProjectShot {
    ProjectShot(shotId: "shot_1", name: "Test", entries: entries)
}

private func frameEntry(_ entryId: String, _ frameImageId: String) -> ShotFrameEntry {
    ShotFrameEntry(entryId: entryId, frameImageId: frameImageId)
}

private func clipEntry(
    _ entryId: String,
    _ mediaId: String,
    start: Double? = nil,
    end: Double? = nil
) -> ShotFrameEntry {
    ShotFrameEntry(entryId: entryId, clipMediaId: mediaId, clipStartSeconds: start, clipEndSeconds: end)
}

private let footageFrameLookup: [String: ProjectLensHeroImage] = [
    "f1": footageHeroFrame("f1"),
    "f2": footageHeroFrame("f2")
]

private let footageMediaLookup: [String: MediaItemRecord] = [
    "vid_1": footageVideoMedia("vid_1"),
    "vid_2": footageVideoMedia("vid_2", durationSeconds: 6)
]

private func footagePlan(_ entries: [ShotFrameEntry]) -> (
    segments: [ShotRenderPlanSegment],
    generatedItems: [ShotSegmentPromptPlanItem],
    skipped: [String],
    strands: [MeaningStrand],
    skippedPlaceholders: [ShotSkippedSegmentPlaceholder]
) {
    shotRenderSegmentPlan(
        shot: footageShot(entries),
        frameLookup: footageFrameLookup,
        mediaLookup: footageMediaLookup,
        meaningNodes: []
    )
}

// MARK: Entry model

@Test func shotFootageLegacyEntryDecodesAsFrameEntry() throws {
    let json = """
    {"entryId": "e1", "frameImageId": "f1"}
    """
    let entry = try JSONDecoder().decode(ShotFrameEntry.self, from: Data(json.utf8))
    #expect(!entry.isClip)
    #expect(entry.frameImageId == "f1")
    #expect(entry.clipMediaId.isEmpty)
    #expect(entry.clipStartSeconds == nil)
    #expect(entry.clipEndSeconds == nil)
}

@Test func shotFootageClipEntryRoundTrips() throws {
    let entry = clipEntry("e1", "vid_1", start: 2.5, end: 8)
    let decoded = try JSONDecoder().decode(ShotFrameEntry.self, from: JSONEncoder().encode(entry))
    #expect(decoded.isClip)
    #expect(decoded.clipMediaId == "vid_1")
    #expect(decoded.clipStartSeconds == 2.5)
    #expect(decoded.clipEndSeconds == 8)
}

@Test func shotFootageNormalizationKeepsClipEntries() {
    // normalized() used to require a frameImageId — clip entries (empty
    // frameImageId) must survive it.
    let shot = footageShot([frameEntry("e1", "f1"), clipEntry("e2", "vid_1")])
    let normalized = shot.normalized()
    #expect(normalized.entries.map(\.entryId) == ["e1", "e2"])
}

// MARK: Mixed segment plan

@Test func shotFootagePlanFrameOnlyMatchesLegacyPlan() {
    let entries = [frameEntry("e1", "f1"), frameEntry("e2", "f2")]
    let mixed = footagePlan(entries)
    let legacy = shotSegmentPromptPlan(
        shot: footageShot(entries),
        frameLookup: footageFrameLookup,
        meaningNodes: []
    )
    #expect(mixed.generatedItems.count == legacy.items.count)
    #expect(mixed.generatedItems.map(\.pair.segmentKey) == legacy.items.map(\.pair.segmentKey))
    #expect(mixed.generatedItems.map(\.generatedPrompt) == legacy.items.map(\.generatedPrompt))
    #expect(mixed.skipped == legacy.skipped)
    #expect(mixed.segments.count == 1)
}

@Test func shotFootagePlanFrameThenClip() {
    let plan = footagePlan([frameEntry("e1", "f1"), clipEntry("e2", "vid_1")])
    #expect(plan.segments.count == 2)
    guard case .generated(let item) = plan.segments[0],
          case .footage(let footage) = plan.segments[1] else {
        Issue.record("Unexpected segment shapes")
        return
    }
    #expect(item.pair.start?.imageId == "f1")
    #expect(item.pair.end?.imageId == footage.clip.boundaryFrameIds.start)
    #expect(item.displayIndex == 0)
    #expect(footage.displayIndex == 1)
    // No open-ended segment sneaks in for the lone frame.
    #expect(plan.generatedItems.count == 1)
}

@Test func shotFootagePlanClipThenFrame() {
    let plan = footagePlan([clipEntry("e1", "vid_1"), frameEntry("e2", "f1")])
    #expect(plan.segments.count == 2)
    guard case .footage(let footage) = plan.segments[0],
          case .generated(let item) = plan.segments[1] else {
        Issue.record("Unexpected segment shapes")
        return
    }
    #expect(footage.displayIndex == 0)
    #expect(item.pair.start?.imageId == footage.clip.boundaryFrameIds.end)
    #expect(item.pair.end?.imageId == "f1")
    #expect(item.displayIndex == 1)
}

@Test func shotFootagePlanFrameClipFrameBridgesBothSides() {
    let plan = footagePlan([frameEntry("e1", "f1"), clipEntry("e2", "vid_1"), frameEntry("e3", "f2")])
    #expect(plan.segments.count == 3)
    #expect(plan.generatedItems.count == 2)
    guard case .generated(let intro) = plan.segments[0],
          case .footage(let footage) = plan.segments[1],
          case .generated(let outro) = plan.segments[2] else {
        Issue.record("Unexpected segment shapes")
        return
    }
    #expect(intro.pair.start?.imageId == "f1")
    #expect(intro.pair.end?.imageId == footage.clip.boundaryFrameIds.start)
    #expect(outro.pair.start?.imageId == footage.clip.boundaryFrameIds.end)
    #expect(outro.pair.end?.imageId == "f2")
    // Generated-only ordinals stay decision-aligned; display ordinals are global.
    #expect(intro.index == 0)
    #expect(outro.index == 1)
    #expect(outro.displayIndex == 2)
}

@Test func shotFootagePlanAdjacentClipsHardCut() {
    let plan = footagePlan([clipEntry("e1", "vid_1"), clipEntry("e2", "vid_2")])
    #expect(plan.segments.count == 2)
    #expect(plan.generatedItems.isEmpty)
    for segment in plan.segments {
        guard case .footage = segment else {
            Issue.record("Expected footage-only segments")
            return
        }
    }
}

@Test func shotFootagePlanLoneClipIsFootageOnly() {
    let plan = footagePlan([clipEntry("e1", "vid_1")])
    #expect(plan.segments.count == 1)
    #expect(plan.generatedItems.isEmpty)
    guard case .footage(let footage) = plan.segments[0] else {
        Issue.record("Expected a footage segment")
        return
    }
    #expect(footage.clip.mediaId == "vid_1")
}

@Test func shotFootagePlanSkipsMissingMedia() {
    let plan = footagePlan([clipEntry("e1", "vid_missing")])
    #expect(plan.segments.isEmpty)
    #expect(plan.skipped == ["missing footage"])
}

// MARK: Keys & boundary endpoints

@Test func shotFootageKeysAreDeterministic() {
    #expect(shotFootageKey(mediaId: "vid_1", startSeconds: nil, endSeconds: nil) == "footage:vid_1:asset_start-asset_end")
    #expect(shotFootageKey(mediaId: "vid_1", startSeconds: 2.5, endSeconds: 8) == "footage:vid_1:2.500-8.000")

    let ids = shotFootageBoundaryFrameIds(mediaId: "vid_1", startSeconds: nil, endSeconds: nil)
    #expect(ids.start == "footage:vid_1:asset_start-asset_end@start")
    #expect(ids.end == "footage:vid_1:asset_start-asset_end@end")
}

@Test func shotFootageBoundaryFrameCarriesDurableKeyAndHonestProvider() {
    let clip = ShotFootageClip(
        entryId: "e1",
        mediaId: "vid_1",
        sourceId: "source_test",
        path: "/tmp/vid_1.mp4",
        filename: "vid_1.mp4",
        thumbnailPath: "/tmp/vid_1_thumb.jpg",
        videoStripPath: nil,
        clipStartSeconds: nil,
        clipEndSeconds: nil,
        assetDurationSeconds: 10
    )
    let start = shotFootageBoundaryFrame(clip: clip, edge: .start)
    #expect(start.imageId == clip.boundaryFrameIds.start)
    #expect(start.provider == "footage")
    #expect(start.status == "ready")
    #expect(start.prompt.contains("opening frame"))
    let end = shotFootageBoundaryFrame(clip: clip, edge: .end)
    #expect(end.imageId == clip.boundaryFrameIds.end)
    #expect(end.prompt.contains("final frame"))
}

@Test func shotFootageClipResolutionClampsRanges() {
    var clip = ShotFootageClip(
        entryId: "e1",
        mediaId: "vid_1",
        sourceId: "source_test",
        path: "/tmp/vid_1.mp4",
        filename: "vid_1.mp4",
        thumbnailPath: "/tmp/vid_1_thumb.jpg",
        videoStripPath: nil,
        clipStartSeconds: nil,
        clipEndSeconds: nil,
        assetDurationSeconds: 10
    )
    #expect(clip.resolvedStartSeconds == 0)
    #expect(clip.resolvedEndSeconds == 10)
    #expect(clip.resolvedDurationSeconds == 10)
    #expect(!clip.hasSubRange)

    clip.clipStartSeconds = 2
    clip.clipEndSeconds = 30
    #expect(clip.hasSubRange)
    #expect(clip.resolvedEndSeconds == 10)
    #expect(clip.resolvedDurationSeconds == 8)

    clip.clipStartSeconds = 8
    clip.clipEndSeconds = 2
    #expect(clip.resolvedDurationSeconds == 0)
}

@Test func shotFootagePlanSkipsZeroDurationSubRange() {
    let plan = footagePlan([clipEntry("e1", "vid_1", start: 8, end: 2)])
    #expect(plan.segments.isEmpty)
    #expect(plan.skipped == ["vid_1.mp4"])
}

// MARK: Overrides & saved clips

@Test func shotFootageOverridePruningKeepsBoundaryKeys() {
    let entries = [frameEntry("e1", "f1"), clipEntry("e2", "vid_1")]
    let boundary = shotFootageBoundaryFrameIds(mediaId: "vid_1", startSeconds: nil, endSeconds: nil)
    let overrides = [
        ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: boundary.start, prompt: "Ease in.", updatedAt: "t")
    ]

    let kept = pruningSegmentPromptOverrides(overrides, entries: entries)
    #expect(kept.count == 1)

    let withoutClip = pruningSegmentPromptOverrides(overrides, entries: [frameEntry("e1", "f1")])
    #expect(withoutClip.isEmpty)
}

@Test func shotFootageOverrideAppliesToBoundaryAdjacentSegment() {
    let boundary = shotFootageBoundaryFrameIds(mediaId: "vid_1", startSeconds: nil, endSeconds: nil)
    var shot = footageShot([frameEntry("e1", "f1"), clipEntry("e2", "vid_1")])
    shot.segmentPromptOverrides = [
        ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: boundary.start, prompt: "Drift toward the footage.", updatedAt: "t")
    ]
    let plan = shotRenderSegmentPlan(
        shot: shot,
        frameLookup: footageFrameLookup,
        mediaLookup: footageMediaLookup,
        meaningNodes: []
    )
    #expect(plan.generatedItems.first?.overridePrompt == "Drift toward the footage.")
}

@Test func shotFootageSavedClipMatchesByFootageKey() {
    let key = shotFootageKey(mediaId: "vid_1", startSeconds: nil, endSeconds: nil)
    var artifact = ShotRenderArtifact(versionId: "v1", versionNumber: 1)
    artifact.upsertSegmentClip(ShotRenderSegmentClip(
        startFrameImageId: key,
        endFrameImageId: "",
        clipPath: "/tmp/footage.mp4"
    ))
    #expect(artifact.segmentClip(forStart: key, end: "")?.clipPath == "/tmp/footage.mp4")
    #expect(artifact.segmentClip(forStart: "footage:vid_2:asset_start-asset_end", end: "") == nil)
}

// MARK: Seam grammar (BRIDGE / CUT)

@Test func shotSeamLeadTransitionDecodesTolerantly() throws {
    let legacy = try JSONDecoder().decode(
        ShotFrameEntry.self,
        from: Data("{\"entryId\": \"e1\", \"clipMediaId\": \"vid_1\"}".utf8)
    )
    #expect(legacy.leadSeamPreference == .auto)

    var entry = clipEntry("e1", "vid_1")
    entry.leadTransition = "cut"
    let decoded = try JSONDecoder().decode(ShotFrameEntry.self, from: JSONEncoder().encode(entry))
    #expect(decoded.leadSeamPreference == .cut)
}

@Test func shotSeamResolverLaw() {
    // An explicit preference always wins — a frame→frame explicit cut IS
    // "skip this generated segment" (2026-07 cut layer); auto still bridges.
    #expect(resolvedShotSeamStyle(leftIsClip: false, rightIsClip: false, rightPreference: .cut) == .cut)
    #expect(resolvedShotSeamStyle(leftIsClip: false, rightIsClip: false, rightPreference: .auto) == .bridge)
    // Auto defaults: frame↔clip bridge, clip→clip cut.
    #expect(resolvedShotSeamStyle(leftIsClip: false, rightIsClip: true, rightPreference: .auto) == .bridge)
    #expect(resolvedShotSeamStyle(leftIsClip: true, rightIsClip: false, rightPreference: .auto) == .bridge)
    #expect(resolvedShotSeamStyle(leftIsClip: true, rightIsClip: true, rightPreference: .auto) == .cut)
    // Explicit preferences win on footage-touching seams.
    #expect(resolvedShotSeamStyle(leftIsClip: false, rightIsClip: true, rightPreference: .cut) == .cut)
    #expect(resolvedShotSeamStyle(leftIsClip: true, rightIsClip: true, rightPreference: .bridge) == .bridge)
    #expect(shotSeamIsToggleable(leftIsClip: false, rightIsClip: true))
    #expect(!shotSeamIsToggleable(leftIsClip: false, rightIsClip: false))
    #expect(ShotSeamStyle.cut.toggled == .bridge)
    #expect(ShotSeamStyle.bridge.toggled == .cut)
    #expect(ShotSeamStyle.auto.toggled == .cut)
}

@Test func shotSeamCutBeforeClipDropsBridgeAndReportsOrphanFrame() {
    var cutClip = clipEntry("e2", "vid_1")
    cutClip.leadTransition = "cut"
    let plan = footagePlan([frameEntry("e1", "f1"), cutClip])
    #expect(plan.generatedItems.isEmpty)
    #expect(plan.segments.count == 1)
    guard case .footage(let footage) = plan.segments[0] else {
        Issue.record("Expected a footage segment")
        return
    }
    #expect(!footage.joinsPrevious)
    #expect(plan.skipped.contains { $0.contains("cut off — no bridge reaches it") })
}

@Test func shotSeamClipToClipBridgeGeneratesTransition() {
    var bridged = clipEntry("e2", "vid_2")
    bridged.leadTransition = "bridge"
    let plan = footagePlan([clipEntry("e1", "vid_1"), bridged])
    #expect(plan.segments.count == 3)
    guard case .footage(let first) = plan.segments[0],
          case .generated(let bridge) = plan.segments[1],
          case .footage(let second) = plan.segments[2] else {
        Issue.record("Unexpected segment shapes")
        return
    }
    #expect(!first.joinsPrevious)
    #expect(second.joinsPrevious)
    #expect(bridge.pair.start?.imageId == first.clip.boundaryFrameIds.end)
    #expect(bridge.pair.end?.imageId == second.clip.boundaryFrameIds.start)
    #expect(bridge.pair.segmentKey == "\(first.clip.boundaryFrameIds.end)>\(second.clip.boundaryFrameIds.start)")
}

@Test func shotSeamAutoGrammarMatchesLegacyMixedPlan() {
    // All-auto [F, C, F] is byte-identical to the pre-grammar plan: bridge in,
    // footage joins, bridge out.
    let plan = footagePlan([frameEntry("e1", "f1"), clipEntry("e2", "vid_1"), frameEntry("e3", "f2")])
    #expect(plan.segments.count == 3)
    #expect(plan.generatedItems.count == 2)
    guard case .footage(let footage) = plan.segments[1] else {
        Issue.record("Expected footage mid-plan")
        return
    }
    #expect(footage.joinsPrevious)
    #expect(!plan.skipped.contains { $0.contains("cut off") })
}

@Test func shotSeamCutOutOfClipOrphansTrailingFrame() {
    var cutFrame = frameEntry("e2", "f1")
    cutFrame.leadTransition = "cut"
    let plan = footagePlan([clipEntry("e1", "vid_1"), cutFrame])
    #expect(plan.generatedItems.isEmpty)
    #expect(plan.segments.count == 1)
    #expect(plan.skipped.contains { $0.contains("cut off — no bridge reaches it") })
}

@Test func shotSeamRuntimeSummaryMath() {
    let mixed = shotRuntimeSummary(
        shot: footageShot([frameEntry("e1", "f1"), clipEntry("e2", "vid_1"), frameEntry("e3", "f2")]),
        frameLookup: footageFrameLookup,
        mediaLookup: footageMediaLookup
    )
    #expect(mixed.frames == 2)
    #expect(mixed.clips == 1)
    #expect(mixed.bridges == 2)
    #expect(mixed.footageSeconds == 10)
    #expect(mixed.estimatedSeconds(segmentSeconds: 8) == 26)
    #expect(mixed.railLabel(segmentSeconds: 8) == "2 FRAMES · 1 CLIP · ~26S")

    let loneFrame = shotRuntimeSummary(
        shot: footageShot([frameEntry("e1", "f1")]),
        frameLookup: footageFrameLookup,
        mediaLookup: [:]
    )
    #expect(loneFrame.bridges == 1)
    #expect(loneFrame.railLabel(segmentSeconds: 8) == "1 FRAME · ~8S")

    let empty = shotRuntimeSummary(shot: footageShot([]), frameLookup: [:], mediaLookup: [:])
    #expect(empty.railLabel(segmentSeconds: 8) == "0 FRAMES")

    // A narrowed entry counts its RANGE, and a cut lead drops a bridge.
    var narrowed = clipEntry("e2", "vid_1", start: 2, end: 8)
    narrowed.leadTransition = "cut"
    let cutIn = shotRuntimeSummary(
        shot: footageShot([frameEntry("e1", "f1"), narrowed]),
        frameLookup: footageFrameLookup,
        mediaLookup: footageMediaLookup
    )
    #expect(cutIn.footageSeconds == 6)
    #expect(cutIn.bridges == 0)
}

@Test func shotSeamSettingClipRangeNormalizes() {
    let entry = clipEntry("e1", "vid_1")

    let fullAsset = entry.settingClipRange(startSeconds: 0, endSeconds: 10, assetDurationSeconds: 10)
    #expect(fullAsset.clipStartSeconds == nil)
    #expect(fullAsset.clipEndSeconds == nil)

    let overshoot = entry.settingClipRange(startSeconds: 2, endSeconds: 30, assetDurationSeconds: 10)
    #expect(overshoot.clipStartSeconds == 2)
    #expect(overshoot.clipEndSeconds == nil)

    let inverted = entry.settingClipRange(startSeconds: 8, endSeconds: 2, assetDurationSeconds: 10)
    #expect(inverted.clipStartSeconds == 2)
    #expect(inverted.clipEndSeconds == 8)

    // Non-clip entries refuse the mutation.
    let frame = frameEntry("e2", "f1").settingClipRange(startSeconds: 1, endSeconds: 2, assetDurationSeconds: 10)
    #expect(frame.clipStartSeconds == nil)
}

// MARK: Clip-moment seeds & AI extensions

@Test func clipSeedDescriptorSpeaksContentOnly() {
    let continueText = clipMomentAttachmentDescriptor(intent: .continueFrom, clipFilename: "gecko.mp4")
    #expect(continueText == "This reference is the exact final frame of preceding real footage (gecko.mp4). Generate the moment that follows it — same scene, same subject, continuous action.")
    let precedeText = clipMomentAttachmentDescriptor(intent: .precede, clipFilename: "gecko.mp4")
    #expect(precedeText.contains("exact first frame of following real footage"))
    let transformText = clipMomentAttachmentDescriptor(intent: .transform, clipFilename: "gecko.mp4")
    #expect(transformText == "Recreate this reference frame's exact composition, scene, and subject.")
    // Style rides the style slot, never descriptor words.
    for text in [continueText, precedeText, transformText] {
        #expect(!text.lowercased().contains("style"))
        #expect(!text.lowercased().contains("aesthetic"))
    }
}

@Test func clipSeedIdIsDeterministic() {
    let seed = ClipMomentSeed(
        shotId: "shot_1", entryId: "e1", clipMediaId: "vid_1", clipFilename: "vid_1.mp4",
        stillMediaId: "frame_1", stillPath: "/tmp/f.jpg", timestampSeconds: 10.456,
        intent: .continueFrom, placeIntoShot: true
    )
    #expect(seed.id == "e1|continue|10.46")
}

@Test func clipSeedExtensionEntryDecodesTolerantly() throws {
    let legacy = try JSONDecoder().decode(
        ShotFrameEntry.self,
        from: Data("{\"entryId\": \"e1\", \"frameImageId\": \"f1\"}".utf8)
    )
    #expect(!legacy.isAIExtension)

    let extended = ShotFrameEntry(entryId: "e2", isAIExtension: true)
    let decoded = try JSONDecoder().decode(ShotFrameEntry.self, from: JSONEncoder().encode(extended))
    #expect(decoded.isAIExtension)

    // normalized() keeps frame-less, clip-less extension entries.
    let shot = footageShot([extended]).normalized()
    #expect(shot.entries.map(\.entryId) == ["e2"])
}

@Test func clipSeedExtensionEmitsOpenEndedSegmentFromLeftNeighbor() {
    let plan = footagePlan([clipEntry("e1", "vid_1"), ShotFrameEntry(entryId: "e2", isAIExtension: true)])
    #expect(plan.segments.count == 2)
    guard case .footage(let footage) = plan.segments[0],
          case .generated(let openEnded) = plan.segments[1] else {
        Issue.record("Unexpected segment shapes")
        return
    }
    #expect(openEnded.pair.start?.imageId == footage.clip.boundaryFrameIds.end)
    #expect(openEnded.pair.end == nil)
    #expect(openEnded.pair.segmentKey == "\(footage.clip.boundaryFrameIds.end)>")
    #expect(openEnded.isAIExtension)
    #expect(openEnded.nativeExtendSourceClip?.entryId == "e1")
    #expect(openEnded.canUseNativeFootageExtend)

    let fromFrame = footagePlan([frameEntry("e1", "f1"), ShotFrameEntry(entryId: "e2", isAIExtension: true)])
    guard case .generated(let frameOpen) = fromFrame.segments.first(where: {
        if case .generated = $0 { return true }
        return false
    }) else {
        Issue.record("Expected an open-ended segment")
        return
    }
    #expect(frameOpen.pair.start?.imageId == "f1")
    #expect(frameOpen.pair.end == nil)
    // Counter-fixture: a still-frame extension retains the out-frame path
    // and is never made native merely because its segment is open-ended.
    #expect(frameOpen.isAIExtension)
    #expect(frameOpen.nativeExtendSourceClip == nil)
    #expect(!frameOpen.canUseNativeFootageExtend)
}

@Test func nativeExtendContractUsesPlacedFootageAndProviderFrameBudget() {
    #expect(ltxShotExtendContextSeconds(sourceDurationSeconds: 10, extensionDurationSeconds: 8) == 2)
    #expect(ltxShotExtendContextSeconds(sourceDurationSeconds: 3, extensionDurationSeconds: 8) == nil)
    let twentySecondContext = ltxShotExtendContextSeconds(
        sourceDurationSeconds: 12,
        extensionDurationSeconds: 20
    )
    #expect(twentySecondContext != nil)
    #expect(abs((twentySecondContext ?? 0) - (505.0 / 24.0 - 20.0)) < 0.0001)

    let stack = ShotRenderStack.recipe(model: .ltx23NativeExtend, durationSeconds: 8)
    #expect(stack.generateAudio)
    #expect(stack.providerSelection == .ltxDirect)
    #expect(stack.modelSelection(for: ShotRenderPair(start: footageHeroFrame("counter"), end: nil)) == .ltxDirectDefault)
    #expect(ShotRenderStack(rawValue: stack.rawValue) == stack)
}

@Test func consecutiveExtensionMarkersCollapseToOnePendingIntent() {
    let entries = [
        clipEntry("source", "vid_2"),
        ShotFrameEntry(entryId: "pending_a", isAIExtension: true),
        ShotFrameEntry(entryId: "pending_b", isAIExtension: true),
        frameEntry("arrival", "f2")
    ]
    #expect(collapsingConsecutiveAIExtensionEntries(entries).map(\.entryId) == [
        "source", "pending_a", "arrival"
    ])
}

@Test func clipSeedLoneExtensionIsSkipped() {
    let plan = footagePlan([ShotFrameEntry(entryId: "e1", isAIExtension: true)])
    #expect(plan.segments.isEmpty)
    #expect(plan.skipped.contains { $0.contains("AI extension") })
}

@Test func clipSeedNothingBridgesAcrossAnExtension() {
    // [C, EXT, F]: the extension's final frame is unknown until rendered, so
    // the trailing frame gets no bridge and is honestly reported.
    let plan = footagePlan([
        clipEntry("e1", "vid_1"),
        ShotFrameEntry(entryId: "e2", isAIExtension: true),
        frameEntry("e3", "f1")
    ])
    #expect(plan.segments.count == 2)
    #expect(plan.generatedItems.count == 1)
    #expect(plan.skipped.contains { $0.contains("cut off — no bridge reaches it") })

    // [C, EXT, C]: the second clip plays via hard cut and keeps its frames.
    let clips = footagePlan([
        clipEntry("e1", "vid_1"),
        ShotFrameEntry(entryId: "e2", isAIExtension: true),
        clipEntry("e3", "vid_2")
    ])
    #expect(clips.segments.count == 3)
    guard case .footage(let second) = clips.segments[2] else {
        Issue.record("Expected trailing footage")
        return
    }
    #expect(!second.joinsPrevious)
}

@Test func clipSeedRuntimeSummaryCountsExtensions() {
    let summary = shotRuntimeSummary(
        shot: footageShot([clipEntry("e1", "vid_1"), ShotFrameEntry(entryId: "e2", isAIExtension: true)]),
        frameLookup: footageFrameLookup,
        mediaLookup: footageMediaLookup
    )
    #expect(summary.clips == 1)
    #expect(summary.frames == 0)
    #expect(summary.bridges == 1)
    #expect(summary.estimatedSeconds(segmentSeconds: 8) == 18)
}

// MARK: AI lead-in (extension at the strip's front, end-anchored)

@Test func leadInBeforeFrameEmitsEndAnchoredSegment() {
    let plan = footagePlan([ShotFrameEntry(entryId: "e1", isAIExtension: true), frameEntry("e2", "f1")])
    #expect(plan.generatedItems.count == 1)
    guard let item = plan.generatedItems.first else { return }
    #expect(item.pair.start == nil)
    #expect(item.pair.end?.imageId == "f1")
    #expect(item.pair.segmentKey == ">f1")
    #expect(item.generatedPrompt == "Begin in motion and arrive naturally on the final frame exactly as depicted.")
    if case .entry(let entryId)? = item.skipTarget {
        #expect(entryId == "e1")
    } else {
        Issue.record("Lead-in should be skippable via its entry")
    }
    // The anchor frame is bridged — never falsely reported cut off.
    #expect(!plan.skipped.contains { $0.contains("cut off") })
}

@Test func leadInBeforeFootageJoinsOnBoundaryStart() {
    let plan = footagePlan([ShotFrameEntry(entryId: "e1", isAIExtension: true), clipEntry("e2", "vid_1")])
    #expect(plan.segments.count == 2)
    guard case .generated(let leadIn) = plan.segments[0],
          case .footage(let footage) = plan.segments[1] else {
        Issue.record("Expected [lead-in, footage]")
        return
    }
    #expect(leadIn.pair.start == nil)
    #expect(leadIn.pair.end?.imageId == footage.clip.boundaryFrameIds.start)
    #expect(leadIn.pair.segmentKey == ">footage:vid_1:asset_start-asset_end@start")
    // The lead-in arrives on the footage's real first frame — the footage
    // joins by construction and sheds the duplicated arrival frame.
    #expect(footage.joinsPrevious)
}

@Test func leadInReanchorsAcrossSkippedFirstEntry() {
    var skippedFrame = frameEntry("e0", "f1")
    skippedFrame.isSkipped = true
    let plan = footagePlan([skippedFrame, ShotFrameEntry(entryId: "e1", isAIExtension: true), frameEntry("e2", "f2")])
    #expect(plan.generatedItems.first?.pair.segmentKey == ">f2")
    #expect(plan.skippedPlaceholders.contains { placeholder in
        if case .entry(let entryId) = placeholder.restore { return entryId == "e0" }
        return false
    })

    // Footage variant: the join is the lead-in's arrival, not a seam ruling —
    // it holds even though the surviving strip begins after a skip.
    var skippedClip = clipEntry("c0", "vid_2")
    skippedClip.isSkipped = true
    let clipPlan = footagePlan([skippedClip, ShotFrameEntry(entryId: "e1", isAIExtension: true), clipEntry("c1", "vid_1")])
    guard case .footage(let footage)? = clipPlan.segments.last else {
        Issue.record("Expected trailing footage")
        return
    }
    #expect(footage.joinsPrevious)
}

@Test func leadInStackedExtensionsAtFrontAreHonestlySkipped() {
    let plan = footagePlan([
        ShotFrameEntry(entryId: "e1", isAIExtension: true),
        ShotFrameEntry(entryId: "e2", isAIExtension: true),
        frameEntry("e3", "f1")
    ])
    #expect(plan.generatedItems.isEmpty)
    #expect(plan.skipped.contains("AI lead-in (needs a frame or clip after it)"))
    #expect(plan.skipped.contains("AI extension (needs a frame or clip before it)"))
    #expect(plan.skipped.contains { $0.contains("cut off") })
}

@Test func leadInMidStripExtensionPrecedenceUnchanged() {
    // [F1, EXT, F2]: an extension with a real left neighbor still anchors
    // LEFT — position 0 is the only place the right-anchor rule applies.
    let plan = footagePlan([
        frameEntry("e1", "f1"),
        ShotFrameEntry(entryId: "e2", isAIExtension: true),
        frameEntry("e3", "f2")
    ])
    #expect(plan.generatedItems.count == 1)
    #expect(plan.generatedItems.first?.pair.segmentKey == "f1>")
    #expect(plan.skipped.contains { $0.contains("cut off") })
}

@Test func leadInOverridesSurviveNormalizeAndPruning() {
    var shot = footageShot([ShotFrameEntry(entryId: "e1", isAIExtension: true), frameEntry("e2", "f1")])
    shot.segmentPromptOverrides = [
        ShotSegmentPromptOverride(startFrameImageId: "", endFrameImageId: "f1", prompt: "Arrive slowly.", updatedAt: "t")
    ]
    shot.segmentRenderOverrides = [
        ShotSegmentRenderOverride(startFrameImageId: "", endFrameImageId: "f1", stack: ShotRenderStack.fallback.rawValue, updatedAt: "t")
    ]
    let normalized = shot.normalized()
    #expect(normalized.segmentPromptOverrides.count == 1)
    #expect(normalized.segmentRenderOverrides.count == 1)

    let plan = shotRenderSegmentPlan(
        shot: normalized,
        frameLookup: footageFrameLookup,
        mediaLookup: footageMediaLookup,
        meaningNodes: []
    )
    #expect(plan.generatedItems.first?.overridePrompt == "Arrive slowly.")
    #expect(plan.generatedItems.first?.hasRenderOverride == true)

    // A both-empty key is junk and never survives.
    let junk = pruningSegmentPromptOverrides(
        [ShotSegmentPromptOverride(startFrameImageId: "", endFrameImageId: "", prompt: "x", updatedAt: "t")],
        entries: shot.entries
    )
    #expect(junk.isEmpty)

    // Anchor gone → the lead-in override drops.
    let withoutAnchor = pruningSegmentPromptOverrides(
        normalized.segmentPromptOverrides,
        entries: [ShotFrameEntry(entryId: "e1", isAIExtension: true)]
    )
    #expect(withoutAnchor.isEmpty)
}

@Test func leadInCutListPruning() {
    let entries = [ShotFrameEntry(entryId: "e1", isAIExtension: true), frameEntry("e2", "f1")]
    var list = ShotCutList()
    list.segmentCuts = [
        ShotSegmentCutRange(cutId: "c1", segmentKey: ">f1", startSeconds: 1, endSeconds: 2, updatedAt: "t"),
        ShotSegmentCutRange(cutId: "c2", segmentKey: ">", startSeconds: 1, endSeconds: 2, updatedAt: "t"),
        ShotSegmentCutRange(cutId: "c3", segmentKey: "f1>", startSeconds: 1, endSeconds: 2, updatedAt: "t")
    ]
    let pruned = list.pruned(entries: entries)
    #expect(pruned.segmentCuts.map(\.cutId) == ["c1", "c3"])
    let withoutAnchor = list.pruned(entries: [entries[0]])
    #expect(withoutAnchor.segmentCuts.isEmpty)
}

@Test func leadInRuntimeSummaryCountsBridge() {
    let summary = shotRuntimeSummary(
        shot: footageShot([ShotFrameEntry(entryId: "e1", isAIExtension: true), clipEntry("e2", "vid_1")]),
        frameLookup: footageFrameLookup,
        mediaLookup: footageMediaLookup
    )
    #expect(summary.clips == 1)
    #expect(summary.frames == 0)
    #expect(summary.bridges == 1)
    #expect(summary.estimatedSeconds(segmentSeconds: 8) == 18)
}

@Test func leadInTailAnchoredModelSelectionPerStack() {
    // FAL's Kling 3 Pro schema requires start_image_url (last checked),
    // so every SELECTABLE stack currently refuses tail-only — flip these pins
    // deliberately when a probe proves an endpoint accepts an end frame alone.
    #expect(ShotRenderStack.fallback.replacingModel(.wan27).tailAnchoredModelSelection == nil)
    #expect(ShotRenderStack.fallback.replacingModel(.falSeedance20).tailAnchoredModelSelection == nil)
    #expect(ShotRenderStack.fallback.replacingModel(.falKlingV3Pro).tailAnchoredModelSelection == nil)
    // Native Kling documents image and/or image_tail — capable, but retired
    // from future renders (upgradedForFutureRender), so not selectable.
    #expect(ShotRenderStack.fallback.replacingModel(.klingV26Pro).tailAnchoredModelSelection == .klingV26ImageToVideo)
    #expect(!ShotRenderModel.anyLeadInCapable)

    let anchor = footageHeroFrame("f1")
    let kling = ShotRenderStack.fallback.replacingModel(.falKlingV3Pro)
    #expect(kling.modelSelection(for: ShotRenderPair(start: nil, end: anchor)) == nil)
    #expect(kling.modelSelection(for: ShotRenderPair(start: anchor, end: nil)) == .falKlingV3ProImageToVideo)
    // WAN pairs and open-ends but honestly refuses a lead-in.
    #expect(ShotRenderStack.fallback.modelSelection(for: ShotRenderPair(start: anchor, end: anchor)) == .falWan27ImageToVideo)
    #expect(ShotRenderStack.fallback.modelSelection(for: ShotRenderPair(start: nil, end: anchor)) == nil)
    // The legacy-but-capable stack routes tail-anchored pairs to native Kling.
    let legacyKling = ShotRenderStack.fallback.replacingModel(.klingV26Pro)
    #expect(legacyKling.modelSelection(for: ShotRenderPair(start: nil, end: anchor)) == .klingV26ImageToVideo)
}

@Test func leadInSegmentClipRecordIsDistinctFromTrailing() {
    var artifact = ShotRenderArtifact(versionId: "v1", versionNumber: 1)
    artifact.upsertSegmentClip(ShotRenderSegmentClip(startFrameImageId: "", endFrameImageId: "f1", clipPath: "/tmp/leadin.mp4"))
    artifact.upsertSegmentClip(ShotRenderSegmentClip(startFrameImageId: "f1", endFrameImageId: "", clipPath: "/tmp/trailing.mp4"))
    #expect(artifact.segmentClip(forStart: "", end: "f1")?.clipPath == "/tmp/leadin.mp4")
    #expect(artifact.segmentClip(forStart: "f1", end: "")?.clipPath == "/tmp/trailing.mp4")
}
