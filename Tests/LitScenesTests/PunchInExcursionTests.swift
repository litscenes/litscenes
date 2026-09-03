import Foundation
import Testing
@testable import LitScenes

// MARK: Fixtures

private func excursionShot(_ frameIds: [String]) -> ProjectShot {
    var shot = ProjectShot(shotId: "shot_excursion", name: "Excursion", createdAt: "t0", updatedAt: "t0")
    for (index, frameId) in frameIds.enumerated() {
        shot.entries.append(ShotFrameEntry(entryId: "e\(index)", frameImageId: frameId))
    }
    return shot
}

private func excursionFrame(
    _ id: String,
    status: String = "ready",
    prompt: String = "A runner watches a nebula storm over the stadium.",
    reframeMode: String? = nil,
    reframeParentImageId: String = "",
    reframeParentRenderVersionId: String = ""
) -> ProjectLensHeroImage {
    var image = ProjectLensHeroImage(imageId: id, status: status)
    image.imagePath = status == "ready" ? "/tmp/\(id).png" : ""
    image.prompt = prompt
    image.sourcePrompt = prompt
    if let reframeMode {
        var spec = LensReframeSpec(mode: reframeMode)
        spec.parentImageId = reframeParentImageId
        spec.parentRenderVersionId = reframeParentRenderVersionId
        image.reframe = spec
    }
    return image
}

private func excursionLookup() -> [String: ProjectLensHeroImage] {
    [
        "f1": excursionFrame("f1"),
        "f2": excursionFrame("f2", prompt: "The empty track under floodlights."),
        // A zoom child of f1 — the punch-in destination.
        "zoomChild": excursionFrame(
            "zoomChild", reframeMode: LensReframeSpec.zoomMode, reframeParentImageId: "f1"
        ),
        // A zoom child of f1 whose parent has since re-rendered (version drift).
        "driftChild": excursionFrame(
            "driftChild", reframeMode: LensReframeSpec.zoomMode,
            reframeParentImageId: "f1", reframeParentRenderVersionId: "rv_stale"
        ),
        // A zoom-out child of f1 — wider than its parent.
        "wideChild": excursionFrame(
            "wideChild", reframeMode: LensReframeSpec.zoomOutMode, reframeParentImageId: "f1"
        ),
        // A viewpoint child of f1.
        "povChild": excursionFrame(
            "povChild", reframeMode: LensReframeSpec.viewpointMode, reframeParentImageId: "f1"
        ),
        // A zoom child of some frame that is NOT in the strip.
        "strayChild": excursionFrame(
            "strayChild", reframeMode: LensReframeSpec.zoomMode, reframeParentImageId: "f_elsewhere"
        )
    ]
}

// MARK: Kernel — insertingPunchInExcursion

@Test func punchInInsertsChildAndReturnAfterAnchor() {
    let shot = excursionShot(["f1", "f2"])
    let result = shot.insertingPunchInExcursion(afterEntryId: "e0", childImageId: "zoomChild", now: "t1")
    let placed = try! #require(result)

    let frames = placed.shot.entries.map(\.frameImageId)
    #expect(frames == ["f1", "zoomChild", "f1", "f2"])

    // The minted ids are fresh, unique, and land where reported.
    #expect(placed.childEntryId != placed.returnEntryId)
    #expect(placed.shot.entries[1].entryId == placed.childEntryId)
    #expect(placed.shot.entries[2].entryId == placed.returnEntryId)
    #expect(!["e0", "e1"].contains(placed.childEntryId))
    #expect(!["e0", "e1"].contains(placed.returnEntryId))

    // Every seam stays AUTO — the motion IS the segment; the follower's lead
    // seam is untouched.
    #expect(placed.shot.entries[1].leadSeamPreference == .auto)
    #expect(placed.shot.entries[2].leadSeamPreference == .auto)
    #expect(placed.shot.entries[3].leadTransition == shot.entries[1].leadTransition)

    #expect(placed.shot.updatedAt == "t1")
}

@Test func punchInRefusesBadAnchorsAndEmptyChild() {
    var shot = excursionShot(["f1"])
    shot.entries.append(ShotFrameEntry(entryId: "clip0", clipMediaId: "media_1"))
    shot.entries.append(ShotFrameEntry(entryId: "ext0", isAIExtension: true))

    #expect(shot.insertingPunchInExcursion(afterEntryId: "missing", childImageId: "zoomChild", now: "t1") == nil)
    #expect(shot.insertingPunchInExcursion(afterEntryId: "clip0", childImageId: "zoomChild", now: "t1") == nil)
    #expect(shot.insertingPunchInExcursion(afterEntryId: "ext0", childImageId: "zoomChild", now: "t1") == nil)
    #expect(shot.insertingPunchInExcursion(afterEntryId: "e0", childImageId: "   ", now: "t1") == nil)
}

@Test func punchInOnLastEntryAppendsAtTail() {
    let shot = excursionShot(["f1", "f2"])
    let result = shot.insertingPunchInExcursion(afterEntryId: "e1", childImageId: "zoomChild", now: "t1")
    let placed = try! #require(result)
    #expect(placed.shot.entries.map(\.frameImageId) == ["f1", "f2", "zoomChild", "f2"])
}

@Test func punchInNestsForChainedDives() {
    let shot = excursionShot(["f1"])
    let first = try! #require(
        shot.insertingPunchInExcursion(afterEntryId: "e0", childImageId: "c1", now: "t1")
    )
    // A nested dive anchors on the CHILD entry; the return derives from the
    // anchor entry, so the chain folds back level by level.
    let second = try! #require(
        first.shot.insertingPunchInExcursion(afterEntryId: first.childEntryId, childImageId: "c2", now: "t2")
    )
    #expect(second.shot.entries.map(\.frameImageId) == ["f1", "c1", "c2", "c1", "f1"])
}

// MARK: Prompt law — lineage-derived segment defaults

@Test func lineagePairYieldsPushInAndReturnYieldsPullOut() {
    let lookup = excursionLookup()
    // The canonical punch-in strip: source, zoom child, source again.
    let shot = excursionShot(["f1", "zoomChild", "f1"])
    let plan = shotSegmentPromptPlan(shot: shot, frameLookup: lookup, meaningNodes: [])
    #expect(plan.items.count == 2)
    #expect(plan.items[0].generatedPrompt == shotReframePushInPrompt)
    #expect(plan.items[1].generatedPrompt == shotReframePullOutPrompt)
    // No overrides were written to get there — the wording is the DEFAULT.
    #expect(plan.items[0].overridePrompt == nil)
    #expect(plan.items[1].overridePrompt == nil)
}

@Test func lineageIgnoresParentRenderVersionMismatch() {
    let lookup = excursionLookup()
    let pair = ShotRenderPair(start: lookup["f1"]!, end: lookup["driftChild"]!)
    #expect(shotSegmentPrompt(pair: pair) == shotReframePushInPrompt)
}

@Test func zoomOutChildInverts() {
    let lookup = excursionLookup()
    // A wider child forward is a pull-out; returning to its parent pushes in.
    let forward = ShotRenderPair(start: lookup["f1"]!, end: lookup["wideChild"]!)
    let reverse = ShotRenderPair(start: lookup["wideChild"]!, end: lookup["f1"]!)
    #expect(shotSegmentPrompt(pair: forward) == shotReframePullOutPrompt)
    #expect(shotSegmentPrompt(pair: reverse) == shotReframePushInPrompt)
}

@Test func viewpointChildGetsVantageSentences() {
    let lookup = excursionLookup()
    let forward = ShotRenderPair(start: lookup["f1"]!, end: lookup["povChild"]!)
    let reverse = ShotRenderPair(start: lookup["povChild"]!, end: lookup["f1"]!)
    #expect(shotSegmentPrompt(pair: forward) == shotReframeVantagePrompt)
    #expect(shotSegmentPrompt(pair: reverse) == shotReframeVantageReturnPrompt)
}

@Test func unrelatedReframeAdjacencyStaysGeneric() {
    let lookup = excursionLookup()
    // A reframe child adjacent to a frame that is NOT its parent: generic.
    let pair = ShotRenderPair(start: lookup["f2"]!, end: lookup["strayChild"]!)
    #expect(shotSegmentPrompt(pair: pair)
        == "Smooth continuous camera and subject motion from the first frame to the last frame.")
}

@Test func lineageSentencesCarryNoGeometry() {
    // The banned echo: digits, percentages, reframe-descriptor phrasing. One
    // sentence each, matching the generic defaults' shape.
    for sentence in [
        shotReframePushInPrompt, shotReframePullOutPrompt,
        shotReframeVantagePrompt, shotReframeVantageReturnPrompt
    ] {
        #expect(sentence.rangeOfCharacter(from: .decimalDigits) == nil)
        #expect(!sentence.contains("%"))
        #expect(sentence.filter { $0 == "." }.count == 1)
        #expect(sentence.hasSuffix("."))
        #expect(!sentence.contains("selection"))
        #expect(!sentence.contains("crop"))
    }
}

@Test func overrideStillWinsOnLineagePair() {
    let lookup = excursionLookup()
    var shot = excursionShot(["f1", "zoomChild", "f1"])
    shot.segmentPromptOverrides = [
        // Placement-keyed edit on the push-in pair.
        ShotSegmentPromptOverride(
            startFrameImageId: "f1", endFrameImageId: "zoomChild",
            placementStartEntryId: "e0", placementEndEntryId: "e1",
            prompt: "shaky camera motion as it zooms into the storm", updatedAt: "t1"
        ),
        // Legacy image-keyed edit (no placement ids) on the pull-out pair.
        ShotSegmentPromptOverride(
            startFrameImageId: "zoomChild", endFrameImageId: "f1",
            prompt: "shaky camera motion as it zooms out of the storm", updatedAt: "t1"
        )
    ]
    let plan = shotSegmentPromptPlan(shot: shot, frameLookup: lookup, meaningNodes: [])
    #expect(plan.items[0].overridePrompt == "shaky camera motion as it zooms into the storm")
    #expect(plan.items[1].overridePrompt == "shaky camera motion as it zooms out of the storm")
    // The lineage sentence stays the generated baseline underneath.
    #expect(plan.items[0].generatedPrompt == shotReframePushInPrompt)
    #expect(plan.items[1].generatedPrompt == shotReframePullOutPrompt)

    // The RESET law: a draft equal to the lineage default stores nothing.
    let clean = excursionShot(["f1", "zoomChild", "f1"])
    let cleanPlan = shotSegmentPromptPlan(shot: clean, frameLookup: lookup, meaningNodes: [])
    let stored = computedSegmentPromptOverrides(
        drafts: [cleanPlan.items[0].pairKey: shotReframePushInPrompt],
        items: cleanPlan.items,
        now: "t2"
    )
    #expect(stored.isEmpty)
}

@Test func openEndedAndLeadInPairsNeverLineage() {
    let lookup = excursionLookup()
    // Even when the lone frame IS a reframe child, open-ended and lead-in
    // segments keep their own sentences — lineage needs both keyframes.
    let openEnded = ShotRenderPair(start: lookup["zoomChild"]!, end: nil)
    let leadIn = ShotRenderPair(start: nil, end: lookup["zoomChild"]!)
    #expect(shotSegmentPrompt(pair: openEnded)
        == "Bring this scene to life with gentle, continuous motion true to what is depicted.")
    #expect(shotSegmentPrompt(pair: leadIn)
        == "Begin in motion and arrive naturally on the final frame exactly as depicted.")
}
