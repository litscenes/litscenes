import Foundation
import Testing
@testable import LitScenes

private func span(
    key: String = "f1>f2",
    path: String = "/tmp/take_one.mp4",
    mediaId: String = "",
    range: ClosedRange<Double> = 2...4
) -> ShotPictureSegmentSpanRef {
    ShotPictureSegmentSpanRef(
        segmentKey: key,
        clipPath: path,
        mediaId: mediaId,
        startSeconds: range.lowerBound,
        endSeconds: range.upperBound
    )
}

private func payload(
    spans: [ShotPictureSegmentSpanRef],
    shotId: String = "shot_a",
    projectId: String = "proj_a"
) -> ShotPictureSegmentClipboardPayload {
    ShotPictureSegmentClipboardPayload(
        spans: spans,
        sourceShotId: shotId,
        sourceProjectId: projectId
    )
}

// MARK: Payload tolerance

@Test func picturePayloadDecodeToleratesSparseAndUnknownFields() throws {
    let json = #"{"spans":[{"segmentKey":"f1>f2","clipPath":"/tmp/t.mp4","startSeconds":1,"endSeconds":3,"mystery":1}],"sourceShotId":"shot_a","futureTopLevel":"x"}"#
    let decoded = try JSONDecoder().decode(
        ShotPictureSegmentClipboardPayload.self,
        from: Data(json.utf8)
    )
    #expect(decoded.spans.count == 1)
    #expect(decoded.spans[0].playbackRate == 1)
    #expect(decoded.isPasteable)
    #expect(decoded.context == nil)
}

@Test func picturePayloadGatesJunk() {
    #expect(!payload(spans: []).isPasteable)
    #expect(!payload(spans: [span(path: "", mediaId: "")]).isPasteable)
    #expect(!payload(spans: [span(range: 2...2.01)]).isPasteable)
    #expect(payload(spans: [span(path: "", mediaId: "vid_1")]).isPasteable)
}

@Test func picturePayloadRoundTripsWithContext() throws {
    var value = payload(spans: [span()])
    value.context = ShotSegmentContext(
        authoredPrompt: "The harbor at dusk, @mara walking",
        lookSummary: "Sun-bleached grain",
        castNames: ["Mara"],
        previousSegmentLabel: "1 · GEN",
        nextSegmentLabel: "2 · FOOTAGE",
        copiedAt: "2026-08-04T00:00:00Z"
    )
    let decoded = try JSONDecoder().decode(
        ShotPictureSegmentClipboardPayload.self,
        from: JSONEncoder().encode(value)
    )
    #expect(decoded == value)
    #expect(decoded.context?.authoredPrompt.contains("@mara") == true)
}

// MARK: Paste rungs

@Test func pasteRungsRefuseHonestly() {
    let generated = payload(spans: [span()])
    #expect(shotPictureClipboardPasteRefusal(
        payload: generated, targetShotId: "shot_a", targetProjectId: "proj_a"
    ) == nil)
    #expect(shotPictureClipboardPasteRefusal(
        payload: generated, targetShotId: "shot_b", targetProjectId: "proj_a"
    )?.contains("Send to Footage") == true)
    #expect(shotPictureClipboardPasteRefusal(
        payload: generated, targetShotId: "shot_a", targetProjectId: "proj_b"
    )?.contains("project") == true)

    // Footage spans are file-level: cross-shot is allowed.
    let footage = payload(spans: [span(path: "/tmp/vid.mp4", mediaId: "vid_1")])
    #expect(shotPictureClipboardPasteRefusal(
        payload: footage, targetShotId: "shot_b", targetProjectId: "proj_a"
    ) == nil)

    #expect(shotPictureClipboardPasteRefusal(
        payload: payload(spans: []), targetShotId: "shot_a", targetProjectId: "proj_a"
    ) == "Nothing on the picture clipboard")
}

// MARK: Mint (the LLM seam's committed half)

@Test func mintLoopsSpansInPasteOrderWithSharedGroup() {
    let intent = ShotSegmentPasteIntent(
        anchor: ShotSegmentPasteAnchor(segmentKey: "f1>f2", anchorSeconds: 4),
        loopCount: 3,
        muteSourceAudio: true
    )
    let minted = mintedPictureInsertions(
        payload: payload(spans: [span()]),
        intent: intent,
        now: "2026-08-04T00:00:00Z"
    )
    #expect(minted.count == 3)
    #expect(minted.allSatisfy { $0.muteSourceAudio })
    #expect(minted.allSatisfy { $0.anchorSegmentKey == "f1>f2" && $0.anchorSeconds == 4 })
    let groups = Set(minted.map(\.loopGroupId))
    #expect(groups.count == 1)
    #expect(!groups.contains(""))
    #expect(Set(minted.map(\.insertionId)).count == 3)
}

@Test func mintHonorsWysiwygModifiersWhenIntentIsSilent() {
    var copied = span()
    copied.playbackRate = 0.5
    copied.muteSourceAudio = true
    let minted = mintedPictureInsertions(
        payload: payload(spans: [copied]),
        intent: ShotSegmentPasteIntent(
            anchor: ShotSegmentPasteAnchor(segmentKey: "f1>f2", anchorSeconds: 4)
        ),
        now: "2026-08-04T00:00:00Z"
    )
    #expect(minted.count == 1)
    #expect(minted[0].playbackRate == 0.5)
    #expect(minted[0].muteSourceAudio)
    #expect(minted[0].loopGroupId.isEmpty)
}

@Test func mintRefusesAnchorlessAndJunkSpans() {
    #expect(mintedPictureInsertions(
        payload: payload(spans: [span()]),
        intent: ShotSegmentPasteIntent(),
        now: "2026-08-04T00:00:00Z"
    ).isEmpty)
    #expect(mintedPictureInsertions(
        payload: payload(spans: [span(range: 2...2.01)]),
        intent: ShotSegmentPasteIntent(
            anchor: ShotSegmentPasteAnchor(segmentKey: "f1>f2", anchorSeconds: 4)
        ),
        now: "2026-08-04T00:00:00Z"
    ).isEmpty)
}

// MARK: Segment cards (structural cross-shot carry)

private func cardFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        label: "Frame \(id)",
        imagePath: "/tmp/\(id).png",
        prompt: "Harbor scene \(id)",
        status: "ready"
    )
}

private let cardFrameLookup: [String: ProjectLensHeroImage] = [
    "fA": cardFrame("fA"),
    "fB": cardFrame("fB"),
    "f1": cardFrame("f1"),
    "f2": cardFrame("f2")
]

private func segmentCard(
    seedPath: String = "/tmp/carried_take.mp4",
    prompt: String = "A glint of arcade lights in the eyes"
) -> ShotPictureSegmentSpanRef {
    ShotPictureSegmentSpanRef(
        segmentKey: "entry:src1>src2",
        clipPath: seedPath,
        endSeconds: 4,
        label: "Segment 12",
        startFrameImageId: "f1",
        endFrameImageId: "f2",
        promptOverride: prompt,
        renderStackRaw: "",
        seedClip: seedPath.isEmpty ? nil : ShotRenderSegmentClip(
            startFrameImageId: "f1",
            endFrameImageId: "f2",
            placementStartEntryId: "src1",
            placementEndEntryId: "src2",
            clipPath: seedPath,
            prompt: prompt,
            provider: "fal",
            model: "seedance_2",
            durationSeconds: 4,
            sourceCutId: "shot_source",
            updatedAt: "2026-08-05T00:00:00Z"
        )
    )
}

@Test func segmentCardSpanDecodesTolerantlyAndGatesPasteable() throws {
    let json = #"{"segmentKey":"k","startFrameImageId":"f1","endFrameImageId":"f2"}"#
    let decoded = try JSONDecoder().decode(ShotPictureSegmentSpanRef.self, from: Data(json.utf8))
    #expect(decoded.isSegmentCard)
    #expect(decoded.seedClip == nil)
    // An unrendered card is pasteable — structural, render-ready.
    #expect(payload(spans: [decoded]).isPasteable)
    // Round-trip keeps the nested seed record whole.
    let full = segmentCard()
    let again = try JSONDecoder().decode(
        ShotPictureSegmentSpanRef.self,
        from: JSONEncoder().encode(full)
    )
    #expect(again == full)
    #expect(again.seedClip?.model == "seedance_2")
}

@Test func pasteRungsLetSegmentCardsTravelCrossShot() {
    let cardPayload = payload(spans: [segmentCard()])
    #expect(shotPictureClipboardPasteRefusal(
        payload: cardPayload, targetShotId: "shot_b", targetProjectId: "proj_a"
    ) == nil)
    // A mixed payload with a plain generated span still refuses.
    let mixed = payload(spans: [segmentCard(), span()])
    #expect(shotPictureClipboardPasteRefusal(
        payload: mixed, targetShotId: "shot_b", targetProjectId: "proj_a"
    )?.contains("segment card") == true)
    // Cross-project stays refused even for cards.
    #expect(shotPictureClipboardPasteRefusal(
        payload: cardPayload, targetShotId: "shot_b", targetProjectId: "proj_b"
    )?.contains("project") == true)
}

@Test func structuralPasteLandsPairOverridesAndSeedAtEnd() {
    let target = ProjectShot(shotId: "shot_target", name: "Target", entries: [
        ShotFrameEntry(entryId: "eA", frameImageId: "fA"),
        ShotFrameEntry(entryId: "eB", frameImageId: "fB")
    ])
    let pasted = shotAppendingSegmentCards(
        target,
        cards: [segmentCard()],
        afterEntryId: nil,
        fileExists: { _ in true },
        now: "2026-08-05T00:00:01Z"
    )
    guard let pasted else {
        #expect(pasted != nil)
        return
    }
    #expect(pasted.entries.count == 4)
    #expect(pasted.entries[2].frameImageId == "f1")
    #expect(pasted.entries[3].frameImageId == "f2")
    // Boundary law: the pasted pair CUTS against the material before it (no
    // implied bridge render); its own seam stays auto — it IS the segment.
    #expect(pasted.entries[2].leadSeamPreference == .cut)
    #expect(pasted.entries[3].leadSeamPreference == .auto)
    // Overrides and the seed re-keyed onto the NEW placement, provenance kept.
    let newStart = pasted.entries[2].entryId
    let newEnd = pasted.entries[3].entryId
    #expect(pasted.segmentPromptOverrides.contains {
        $0.placementStartEntryId == newStart && $0.placementEndEntryId == newEnd
            && $0.prompt.contains("arcade lights")
    })
    #expect(pasted.seedSegmentClips.contains {
        $0.placementStartEntryId == newStart && $0.placementEndEntryId == newEnd
            && $0.clipPath == "/tmp/carried_take.mp4"
            && $0.sourceCutId == "shot_source"
    })

    // The carried take PLAYS: the plan pairs the pasted frames and the
    // assembly resolves the seed clip into a rendered band.
    let plan = shotRenderSegmentPlan(
        shot: pasted,
        frameLookup: cardFrameLookup,
        mediaLookup: [:],
        meaningNodes: []
    )
    let assembly = shotCutAssembly(
        shot: pasted,
        planSegments: plan.segments,
        clipDurationsByPath: ["/tmp/carried_take.mp4": 4],
        fileExists: { _ in true }
    )
    let pastedBand = assembly.bands.first { $0.segmentKey == "entry:\(newStart)>\(newEnd)" }
    #expect(pastedBand?.isRendered == true)
    #expect(pastedBand?.clipPath == "/tmp/carried_take.mp4")
    // The pasted segment's prompt override resolves in the target's plan.
    let pastedItem = plan.generatedItems.first { $0.pair.placementKey == "entry:\(newStart)>\(newEnd)" }
    #expect(pastedItem?.overridePrompt?.contains("arcade lights") == true)
}

@Test func structuralPasteInsertsAfterEntryAndCutsTheFollower() {
    let target = ProjectShot(shotId: "shot_target", name: "Target", entries: [
        ShotFrameEntry(entryId: "eA", frameImageId: "fA"),
        ShotFrameEntry(entryId: "eB", frameImageId: "fB")
    ])
    let pasted = shotAppendingSegmentCards(
        target,
        cards: [segmentCard()],
        afterEntryId: "eA",
        fileExists: { _ in true },
        now: "2026-08-05T00:00:01Z"
    )
    #expect(pasted?.entries.map(\.frameImageId) == ["fA", "f1", "f2", "fB"])
    // The follower must lead with a hard cut too, or the paste implies a
    // bridge render from the pasted tail into it.
    #expect(pasted?.entries[3].leadSeamPreference == .cut)
}

@Test func structuralPasteDropsDeadSeedsAndRefusesNonCards() {
    let target = ProjectShot(shotId: "shot_target", name: "Target", entries: [])
    let missingFile = shotAppendingSegmentCards(
        target,
        cards: [segmentCard()],
        afterEntryId: nil,
        fileExists: { _ in false },
        now: "2026-08-05T00:00:01Z"
    )
    #expect(missingFile?.entries.count == 2)
    #expect(missingFile?.seedSegmentClips.isEmpty == true)

    #expect(shotAppendingSegmentCards(
        target,
        cards: [span()],
        afterEntryId: nil,
        fileExists: { _ in true },
        now: "2026-08-05T00:00:01Z"
    ) == nil)
}

@Test func renderCTATreatsAPastedSeedDraftLikeACombinedOne() throws {
    // A real file, because cutReadableSeedKeys checks the disk.
    let seedURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("cta_seed_\(UUID().uuidString).mp4")
    try Data("x".utf8).write(to: seedURL)
    defer { try? FileManager.default.removeItem(at: seedURL) }

    var target = ProjectShot(shotId: "shot_cta", name: "CTA", entries: [])
    let pasted = shotAppendingSegmentCards(
        target,
        cards: [segmentCard(seedPath: seedURL.path)],
        afterEntryId: nil,
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        now: "2026-08-05T00:00:01Z"
    )
    guard let pasted else {
        #expect(pasted != nil)
        return
    }
    // One pasted pair, fully covered: the rail must offer OPEN ($0), never a
    // re-pay RENDER for pixels the row already carries.
    #expect(cutRenderCTA(cut: pasted, segmentCount: 1) == .finalizeFree)
    #expect(cutRenderCTA(cut: pasted, segmentCount: 1).railLabel == "OPEN")
    #expect(cutRenderCTA(cut: pasted, segmentCount: 1).isSeedDraft)
    // Add an uncovered second segment's worth: partial coverage bills only
    // the gap.
    #expect(cutRenderCTA(cut: pasted, segmentCount: 2) == .renderMissing)
    // A seedless ordinary draft keeps the plain RENDER vocabulary.
    target.entries = pasted.entries
    #expect(cutRenderCTA(cut: target, segmentCount: 1) == .render)
    // A rendered cut never re-enters the seed vocabulary.
    var rendered = pasted
    rendered = rendered.upsertingRenderVersion(
        ShotRenderArtifact(
            versionId: "v1",
            versionNumber: 1,
            status: "ready",
            videoPath: seedURL.path,
            generatedAt: "2026-08-05T00:00:02Z",
            updatedAt: "2026-08-05T00:00:02Z"
        ),
        activate: true,
        now: "2026-08-05T00:00:02Z"
    )
    #expect(cutRenderCTA(cut: rendered, segmentCount: 1) == .render)
}

@Test func pasteIntentDecodesTolerantly() throws {
    let json = #"{"anchor":{"segmentKey":"f1>f2"},"loopCount":2,"futureKnob":"x"}"#
    let intent = try JSONDecoder().decode(ShotSegmentPasteIntent.self, from: Data(json.utf8))
    #expect(intent.anchor.segmentKey == "f1>f2")
    #expect(intent.loopCount == 2)
    #expect(intent.playbackRate == nil)
    #expect(intent.muteSourceAudio == nil)
    #expect(intent.transformKind.isEmpty)
}

// MARK: Look rail vocabulary (where a finished restyle is visible)

private func readyLook(_ number: Int, style: String = "", versionId: String = "look_1") -> ShotRestyleArtifact {
    ShotRestyleArtifact(
        versionId: versionId,
        versionNumber: number,
        status: "ready",
        videoPath: "/tmp/look_\(number).mp4",
        styleLabel: style,
        generatedAt: "2026-08-05T00:00:00Z",
        updatedAt: "2026-08-05T00:00:00Z"
    )
}

@Test @MainActor func lookRailChipNamesActiveLookAndOriginalState() {
    // Active Look: the row states that its OUTPUT is that Look.
    #expect(shotLookRailChipLabel(active: readyLook(2, style: "Neon Arcade"), readyLookCount: 3)
        == "LOOK II · NEON ARCADE")
    // A styleless Look still names its version.
    #expect(shotLookRailChipLabel(active: readyLook(1), readyLookCount: 1) == "LOOK I")
    // Looks exist but Original is showing — the count, and which is playing.
    #expect(shotLookRailChipLabel(active: nil, readyLookCount: 3) == "3 LOOKS · ORIGINAL")
    #expect(shotLookRailChipLabel(active: nil, readyLookCount: 1) == "1 LOOK · ORIGINAL")
    // The help states the law both ways: a Look is a version, not a row.
    #expect(shotLookRailChipHelp(active: readyLook(2), readyLookCount: 2).contains("not a row of its own"))
    #expect(shotLookRailChipHelp(active: nil, readyLookCount: 2).contains("versions of this row"))
}

@Test @MainActor func activeLookResolvesOnlyWhenReadyAndPointed() {
    var shot = ProjectShot(shotId: "shot_look", name: "Look row")
    let ready = readyLook(1, style: "Neon", versionId: "look_a")
    shot = shot.upsertingLookVersion(ready, activate: true, now: "2026-08-05T00:00:01Z")
    #expect(shot.browsableLookVersions.count == 1)
    #expect(shot.activeLookVersion?.versionId == "look_a")
    #expect(shotLookRailChipLabel(active: shot.activeLookVersion, readyLookCount: 1) == "LOOK I · NEON")
    // EDIT ORIGINAL clears the pointer: the Look survives, the chip flips.
    let original = shot.activatingLookVersion("", now: "2026-08-05T00:00:02Z")
    #expect(original.activeLookVersion == nil)
    #expect(original.browsableLookVersions.count == 1)
    #expect(shotLookRailChipLabel(active: original.activeLookVersion, readyLookCount: 1) == "1 LOOK · ORIGINAL")
}

// MARK: Narration-driven prompt (lip-sync must be asked for)

@Test func narrationDrivenDefaultPromptAsksForSpeech() {
    let prompt = shotNarrationDrivenSegmentPrompt()
    #expect(prompt.contains("speaks the narration"))
    #expect(prompt.contains("lip-sync"))
    // The generic open-ended fallback stays motion-only — the two defaults
    // serve different render paths and must not converge.
    let generic = shotSegmentPrompt(pair: ShotRenderPair(
        start: ProjectLensHeroImage(imageId: "f1", label: "", imagePath: "/tmp/f1.png", prompt: "", status: "ready"),
        end: nil,
        startPlacementEntryId: "e1",
        endPlacementEntryId: ""
    ))
    #expect(!generic.contains("lip-sync"))
}

// MARK: Narration carry (the sentence travels with its picture)

@Test func narrationCarrySliceWindowLaw() {
    // Narration 0–3.6s; segment at 1–5s: the audible tail carries, in-point 1.
    let tail = shotNarrationCarrySlice(
        narrationStartSeconds: 0,
        narrationDurationSeconds: 3.6,
        segmentOutputStartSeconds: 1,
        segmentDurationSeconds: 4
    )
    #expect(tail == ShotNarrationCarrySlice(
        sourceStartSeconds: 1, sliceSeconds: 2.6, offsetIntoSegmentSeconds: 0
    ))

    // Segment fully inside the narration: whole segment covered.
    let inside = shotNarrationCarrySlice(
        narrationStartSeconds: 0,
        narrationDurationSeconds: 10,
        segmentOutputStartSeconds: 2,
        segmentDurationSeconds: 3
    )
    #expect(inside == ShotNarrationCarrySlice(
        sourceStartSeconds: 2, sliceSeconds: 3, offsetIntoSegmentSeconds: 0
    ))

    // Narration ends before the segment begins: nothing to carry.
    #expect(shotNarrationCarrySlice(
        narrationStartSeconds: 0,
        narrationDurationSeconds: 3.6,
        segmentOutputStartSeconds: 8,
        segmentDurationSeconds: 4
    ) == nil)

    // Narration starting mid-segment lands OFFSET, never stretched.
    let offset = shotNarrationCarrySlice(
        narrationStartSeconds: 6,
        narrationDurationSeconds: 4,
        segmentOutputStartSeconds: 5,
        segmentDurationSeconds: 5
    )
    #expect(offset == ShotNarrationCarrySlice(
        sourceStartSeconds: 0, sliceSeconds: 4, offsetIntoSegmentSeconds: 1
    ))

    // A sub-perceptible overlap is no carry at all.
    #expect(shotNarrationCarrySlice(
        narrationStartSeconds: 0,
        narrationDurationSeconds: 2.02,
        segmentOutputStartSeconds: 2,
        segmentDurationSeconds: 4
    ) == nil)
}

@Test func carriedNarrationRegionIsClipLaneBornAudible() {
    var card = segmentCard()
    card.narrationPath = "/audio/narration.m4a"
    card.narrationSourceStartSeconds = 1.5
    card.narrationSliceSeconds = 2.1
    card.narrationOffsetIntoSegmentSeconds = 0.5
    card.narrationLabel = "Narration · Opening"
    card.seedClip?.sourceCutId = "shot_source"

    let region = shotCarriedNarrationRegion(
        card: card,
        targetSegmentOutputStartSeconds: 8,
        sourceCutId: card.seedClip?.sourceCutId ?? "",
        regionId: "audio_region_test"
    )
    // THE CLOBBER TRAP: the narration lane's active_narration region is
    // owned by settingNarrationArtifact — a carried slice must live on the
    // CLIP lane under its own provenance or the target's narration
    // lifecycle deletes it.
    #expect(region?.laneId == ShotAudioLaneId.clip)
    #expect(region?.provenance == shotCarriedNarrationProvenance)
    // Born audible — a muted carry re-creates the complaint this answers.
    #expect(region?.isMuted == false)
    #expect(region?.gain == 1)
    // Placed at the pasted segment plus the mid-segment offset; the slice
    // rides as in-point + duration, no file surgery.
    #expect(region?.startSeconds == 8.5)
    #expect(region?.sourceStartSeconds == 1.5)
    #expect(region?.durationSeconds == 2.1)
    #expect(region?.label == "Narration · Opening")

    // A card with no carry mints nothing.
    #expect(shotCarriedNarrationRegion(
        card: segmentCard(),
        targetSegmentOutputStartSeconds: 8,
        sourceCutId: "",
        regionId: "audio_region_none"
    ) == nil)
}

@Test func spanNarrationCarryFieldsDecodeTolerantly() throws {
    // A pre-carry clipboard payload (no narration keys) decodes to no carry.
    let legacy = Data("""
    {"segmentKey":"k","startFrameImageId":"f1","endFrameImageId":"f2"}
    """.utf8)
    let decoded = try JSONDecoder().decode(ShotPictureSegmentSpanRef.self, from: legacy)
    #expect(!decoded.carriesNarration)
    #expect(decoded.narrationPath == "")

    let carrying = Data("""
    {"segmentKey":"k","startFrameImageId":"f1","endFrameImageId":"f2",
     "narrationPath":"/audio/n.m4a","narrationSourceStartSeconds":1.25,
     "narrationSliceSeconds":2.5,"narrationOffsetIntoSegmentSeconds":0.75,
     "narrationLabel":"Narration · Opening"}
    """.utf8)
    let carried = try JSONDecoder().decode(ShotPictureSegmentSpanRef.self, from: carrying)
    #expect(carried.carriesNarration)
    #expect(carried.narrationSourceStartSeconds == 1.25)
    #expect(carried.narrationSliceSeconds == 2.5)
    #expect(carried.narrationOffsetIntoSegmentSeconds == 0.75)
    #expect(carried.narrationLabel == "Narration · Opening")
}
