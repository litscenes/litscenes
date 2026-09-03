import Foundation
import Testing
@testable import LitScenes

// MARK: - Shared fixture (one plan, N dialect spellings)

private func fixturePlan(mode: ShotTemporalShotMode = .continuous) -> ShotTemporalDirectionPlan {
    ShotTemporalDirectionPlan(shotMode: mode, beats: [
        ShotTemporalBeat(
            durationWeight: 2,
            action: "The figure approaches the marble meridian",
            camera: "low tracking shot"
        ),
        ShotTemporalBeat(
            durationWeight: 4,
            action: "The figure kneels and places the leaf",
            camera: "camera rises to a medium-wide frame"
        ),
        ShotTemporalBeat(
            durationWeight: 2,
            action: "Dawn light moves across the objects"
        ),
    ])
}

private func fixturePair() -> ShotRenderPair {
    ShotRenderPair(
        start: ProjectLensHeroImage(imageId: "img_a"),
        end: ProjectLensHeroImage(imageId: "img_b"),
        startPlacementEntryId: "e0",
        endPlacementEntryId: "e1"
    )
}

// MARK: - Weight → second allocation

@Test func beatAllocationSplitsWeightsExactly() {
    let windows = shotTemporalBeatAllocation(plan: fixturePlan(), totalSeconds: 8)
    #expect(windows.map { $0.endSecond - $0.startSecond } == [2, 4, 2])
    #expect(windows.first?.startSecond == 0)
    #expect(windows.last?.endSecond == 8)
    // Contiguity.
    for (left, right) in zip(windows, windows.dropFirst()) {
        #expect(left.endSecond == right.startSecond)
    }
}

@Test func beatAllocationRemainderTiesGoToEarlierBeat() {
    let plan = ShotTemporalDirectionPlan(beats: [
        ShotTemporalBeat(action: "a"), ShotTemporalBeat(action: "b"), ShotTemporalBeat(action: "c"),
    ])
    let windows = shotTemporalBeatAllocation(plan: plan, totalSeconds: 8)
    #expect(windows.map { $0.endSecond - $0.startSecond } == [3, 3, 2])
}

@Test func beatAllocationSanitizesJunkWeights() {
    let plan = ShotTemporalDirectionPlan(beats: [
        ShotTemporalBeat(durationWeight: .nan, action: "a"),
        ShotTemporalBeat(durationWeight: -3, action: "b"),
    ])
    let windows = shotTemporalBeatAllocation(plan: plan, totalSeconds: 6)
    #expect(windows.map { $0.endSecond - $0.startSecond } == [3, 3])
}

@Test func beatAllocationGuaranteesEveryBeatOneSecond() {
    let plan = ShotTemporalDirectionPlan(beats: [
        ShotTemporalBeat(durationWeight: 100, action: "a"),
        ShotTemporalBeat(durationWeight: 1, action: "b"),
    ])
    let windows = shotTemporalBeatAllocation(plan: plan, totalSeconds: 5)
    #expect(windows.map { $0.endSecond - $0.startSecond } == [4, 1])
}

@Test func beatAllocationMergesTrailingBeatsWhenOverSubscribed() {
    let plan = ShotTemporalDirectionPlan(beats: [
        ShotTemporalBeat(action: "a"),
        ShotTemporalBeat(action: "b"),
        ShotTemporalBeat(action: "c", camera: "push in"),
        ShotTemporalBeat(action: "d"),
    ])
    let windows = shotTemporalBeatAllocation(plan: plan, totalSeconds: 3)
    #expect(windows.count == 3)
    #expect(windows.map { $0.endSecond - $0.startSecond } == [1, 1, 1])
    #expect(windows[2].beat.action == "c, then d")
    #expect(windows[2].beat.camera == "push in")
}

@Test func beatAllocationRefusesNothingness() {
    #expect(shotTemporalBeatAllocation(plan: fixturePlan(), totalSeconds: 0).isEmpty)
    #expect(shotTemporalBeatAllocation(plan: ShotTemporalDirectionPlan(), totalSeconds: 8).isEmpty)
}

// MARK: - Compiler dialects (golden)

@Test func seedance25CompilesIntegerSecondIntervals() throws {
    let compiled = try #require(compileTemporalDirection(
        plan: fixturePlan(), modelSelection: .falSeedance25ImageToVideo, durationSeconds: 8
    ))
    #expect(compiled.dialect == "seedance25_intervals")
    #expect(compiled.canonicalText == "0-2 seconds: The figure approaches the marble meridian — low tracking shot. "
        + "2-6 seconds: The figure kneels and places the leaf — camera rises to a medium-wide frame. "
        + "6-8 seconds: Dawn light moves across the objects. "
        + "One continuous take — no cuts.")
}

@Test func klingContinuousNeverEmitsMultiShot() throws {
    let compiled = try #require(compileTemporalDirection(
        plan: fixturePlan(mode: .continuous), modelSelection: .falKlingV3ProImageToVideo, durationSeconds: 8
    ))
    // The beats ≠ shots law: three actions in one unbroken take stay ONE prompt.
    #expect(compiled.klingShots == nil)
    #expect(compiled.dialect == "kling_timed_prose")
    #expect(compiled.canonicalText == "For the first 2 seconds, The figure approaches the marble meridian — low tracking shot. "
        + "From 2 to 6 seconds, The figure kneels and places the leaf — camera rises to a medium-wide frame. "
        + "From 6 to 8 seconds, Dawn light moves across the objects. "
        + "One continuous take — no cuts.")
}

@Test func klingMultiShotCompilesNativeShotArray() throws {
    let compiled = try #require(compileTemporalDirection(
        plan: fixturePlan(mode: .multiShot), modelSelection: .falKlingV3ProImageToVideo, durationSeconds: 8
    ))
    #expect(compiled.dialect == "kling_multi_prompt")
    let shots = try #require(compiled.klingShots)
    #expect(shots.map(\.durationSeconds) == [2, 4, 2])
    #expect(shots.map(\.durationSeconds).reduce(0, +) == 8)
    #expect(shots.allSatisfy { (1...15).contains($0.durationSeconds) })
    #expect(shots[0].prompt == "The figure approaches the marble meridian — low tracking shot.")
    #expect(compiled.canonicalText == "Shot 1 (2s): The figure approaches the marble meridian — low tracking shot.\n"
        + "Shot 2 (4s): The figure kneels and places the leaf — camera rises to a medium-wide frame.\n"
        + "Shot 3 (2s): Dawn light moves across the objects.")
}

@Test func wanCompilesOverallPlusShotStamps() throws {
    let compiled = try #require(compileTemporalDirection(
        plan: fixturePlan(), modelSelection: .falWan27ImageToVideo, durationSeconds: 8
    ))
    #expect(compiled.dialect == "wan_shots")
    #expect(compiled.canonicalText == "Single continuous take, no cuts — The figure approaches the marble meridian, "
        + "then The figure kneels and places the leaf, then Dawn light moves across the objects. "
        + "Shot 1 [0-2 s]: The figure approaches the marble meridian — low tracking shot. "
        + "Shot 2 [2-6 s]: The figure kneels and places the leaf — camera rises to a medium-wide frame. "
        + "Shot 3 [6-8 s]: Dawn light moves across the objects.")
}

@Test func seedance20CompilesOrderedProseWithoutTimestamps() throws {
    let compiled = try #require(compileTemporalDirection(
        plan: fixturePlan(), modelSelection: .falSeedance20ImageToVideo, durationSeconds: 8
    ))
    #expect(compiled.dialect == "seedance20_ordered")
    #expect(compiled.canonicalText == "First, The figure approaches the marble meridian — low tracking shot. "
        + "Then, The figure kneels and places the leaf — camera rises to a medium-wide frame. "
        + "Finally, Dawn light moves across the objects. "
        + "All in one continuous take.")
    // Seedance 2.0's guidance: no exact second markers, ever.
    let hasDigits = compiled.canonicalText.contains { $0.isNumber }
    #expect(!hasDigits)
}

@Test func legacyModelsCompileCollapsedOrdering() throws {
    let compiled = try #require(compileTemporalDirection(
        plan: fixturePlan(), modelSelection: .klingV26ImageToVideo, durationSeconds: 8
    ))
    #expect(compiled.dialect == "collapsed")
    #expect(compiled.canonicalText == "The figure approaches the marble meridian — low tracking shot, "
        + "then The figure kneels and places the leaf — camera rises to a medium-wide frame, "
        + "then Dawn light moves across the objects. "
        + "One continuous motion — no cuts, no captions.")
    #expect(compiled.canonicalText.count <= 1_200)
}

@Test func compilerIsDeterministicAndRefusesEmptiness() {
    let first = compileTemporalDirection(plan: fixturePlan(), modelSelection: .falWan27ImageToVideo, durationSeconds: 8)
    let second = compileTemporalDirection(plan: fixturePlan(), modelSelection: .falWan27ImageToVideo, durationSeconds: 8)
    #expect(first == second)
    #expect(compileTemporalDirection(
        plan: ShotTemporalDirectionPlan(), modelSelection: .falWan27ImageToVideo, durationSeconds: 8
    ) == nil)
    let blank = ShotTemporalDirectionPlan(beats: [ShotTemporalBeat(durationWeight: 3)])
    #expect(compileTemporalDirection(
        plan: blank, modelSelection: .falWan27ImageToVideo, durationSeconds: 8
    ) == nil)
}

// MARK: - Plan model + record laws

@Test func directionPlanDecodesTolerantly() throws {
    let json = """
    {"startFrameImageId":"a","endFrameImageId":"b",
     "plan":{"shotMode":"never_heard_of_it","beats":[{"action":"x"}]}}
    """
    let record = try JSONDecoder().decode(ShotSegmentDirectionPlanRecord.self, from: Data(json.utf8))
    #expect(record.plan.shotMode == .continuous)
    #expect(record.plan.beats.count == 1)
    #expect(record.plan.beats[0].durationWeight == 1)
    #expect(record.mode == .beats)
    #expect(record.source == "user")

    let unknownMode = ShotSegmentDirectionPlanRecord(promptMode: "sideways")
    #expect(unknownMode.mode == .beats)
}

@Test func legacyShotDecodesToNoDirectionPlans() throws {
    let legacy = """
    {"shotId": "s1", "entries": [{"entryId": "e1", "frameImageId": "f1"}]}
    """
    let shot = try JSONDecoder().decode(ProjectShot.self, from: Data(legacy.utf8))
    #expect(shot.segmentDirectionPlans.isEmpty)
}

@Test func directionPlanRecordRoundTrips() throws {
    let record = ShotSegmentDirectionPlanRecord(
        startFrameImageId: "a",
        endFrameImageId: "b",
        placementStartEntryId: "e0",
        placementEndEntryId: "e1",
        plan: fixturePlan(mode: .multiShot),
        promptMode: "beats",
        source: "llm",
        llmDraftPlan: fixturePlan(),
        inputsFingerprint: "fp1",
        responseId: "resp1",
        updatedAt: "t1"
    )
    let data = try JSONEncoder().encode(record)
    let decoded = try JSONDecoder().decode(ShotSegmentDirectionPlanRecord.self, from: data)
    #expect(decoded == record)
}

@Test func settingSegmentDirectionPlansPrunesDepartedFrames() {
    var shot = ProjectShot(shotId: "s1", createdAt: "t0", updatedAt: "t0")
    shot.entries = [
        ShotFrameEntry(entryId: "e0", frameImageId: "img_a"),
        ShotFrameEntry(entryId: "e1", frameImageId: "img_b"),
    ]
    let present = ShotSegmentDirectionPlanRecord(
        startFrameImageId: "img_a", endFrameImageId: "img_b",
        placementStartEntryId: "e0", placementEndEntryId: "e1",
        plan: fixturePlan(), updatedAt: "t1"
    )
    let departed = ShotSegmentDirectionPlanRecord(
        startFrameImageId: "img_x", endFrameImageId: "img_y",
        placementStartEntryId: "gone0", placementEndEntryId: "gone1",
        plan: fixturePlan(), updatedAt: "t1"
    )
    let empty = ShotSegmentDirectionPlanRecord(
        startFrameImageId: "img_a", endFrameImageId: "img_b",
        placementStartEntryId: "e0", placementEndEntryId: "e1",
        plan: ShotTemporalDirectionPlan(), updatedAt: "t1"
    )
    let saved = shot.settingSegmentDirectionPlans([present, departed], now: "t2")
    #expect(saved.segmentDirectionPlans.count == 1)
    #expect(saved.segmentDirectionPlans[0].directionKey == "entry:e0>e1")
    #expect(saved.updatedAt == "t2")
    let cleared = shot.settingSegmentDirectionPlans([empty], now: "t3")
    #expect(cleared.segmentDirectionPlans.isEmpty)
}

@Test func segmentDirectionPlanMatchesPlacementFirstThenLegacy() {
    var shot = ProjectShot(shotId: "s1", createdAt: "t0", updatedAt: "t0")
    shot.entries = [
        ShotFrameEntry(entryId: "e0", frameImageId: "img_a"),
        ShotFrameEntry(entryId: "e1", frameImageId: "img_b"),
    ]
    shot.segmentDirectionPlans = [
        ShotSegmentDirectionPlanRecord(
            startFrameImageId: "img_a", endFrameImageId: "img_b",
            placementStartEntryId: "e0", placementEndEntryId: "e1",
            plan: fixturePlan(), updatedAt: "t1"
        ),
    ]
    #expect(shot.segmentDirectionPlan(for: fixturePair()) != nil)
    // Legacy record (no placement ids) still matches by image pair.
    shot.segmentDirectionPlans = [
        ShotSegmentDirectionPlanRecord(
            startFrameImageId: "img_a", endFrameImageId: "img_b",
            plan: fixturePlan(), updatedAt: "t1"
        ),
    ]
    #expect(shot.segmentDirectionPlan(for: fixturePair()) != nil)
    shot.segmentDirectionPlans = []
    #expect(shot.segmentDirectionPlan(for: fixturePair()) == nil)
}

@Test func mergedAutosaveDirectionPlansIsUpsertOnly() {
    let existing = ShotSegmentDirectionPlanRecord(
        startFrameImageId: "img_a", endFrameImageId: "img_b",
        placementStartEntryId: "e0", placementEndEntryId: "e1",
        plan: fixturePlan(), updatedAt: "t1"
    )
    var replacement = existing
    replacement.plan = ShotTemporalDirectionPlan(beats: [ShotTemporalBeat(action: "changed")])
    let other = ShotSegmentDirectionPlanRecord(
        startFrameImageId: "img_c", endFrameImageId: "img_d",
        placementStartEntryId: "e2", placementEndEntryId: "e3",
        plan: fixturePlan(), updatedAt: "t1"
    )
    // Computed omitting `other` keeps it; computed replacing `existing` wins.
    let merged = mergedAutosaveDirectionPlans(existing: [existing, other], computed: [replacement])
    #expect(merged.count == 2)
    #expect(merged[0].plan.beats[0].action == "changed")
    #expect(merged[1].directionKey == "entry:e2>e3")
}

@Test func directionPlansAgreeIgnoresBookkeeping() {
    let record = ShotSegmentDirectionPlanRecord(
        startFrameImageId: "img_a", endFrameImageId: "img_b",
        placementStartEntryId: "e0", placementEndEntryId: "e1",
        plan: fixturePlan(), updatedAt: "t1"
    )
    var bookkeepingOnly = record
    bookkeepingOnly.updatedAt = "t9"
    bookkeepingOnly.inputsFingerprint = "different"
    bookkeepingOnly.responseId = "resp_new"
    #expect(directionPlansAgree([record], [bookkeepingOnly]))
    var changed = record
    changed.plan.beats[0].action = "something else"
    #expect(!directionPlansAgree([record], [changed]))
    var modeFlip = record
    modeFlip.promptMode = ShotSegmentPromptMode.raw.rawValue
    #expect(!directionPlansAgree([record], [modeFlip]))
}

@Test func computedSegmentDirectionPlansFollowsDraftLaw() {
    let pair = fixturePair()
    let item = ShotSegmentPromptPlanItem(
        index: 0,
        pair: pair,
        generatedPrompt: shotSegmentPrompt(pair: pair),
        overridePrompt: nil
    )
    let existing = ShotSegmentDirectionPlanRecord(
        startFrameImageId: "img_a", endFrameImageId: "img_b",
        placementStartEntryId: "e0", placementEndEntryId: "e1",
        plan: fixturePlan(), source: "llm", llmDraftPlan: fixturePlan(),
        inputsFingerprint: "fp", responseId: "resp", updatedAt: "t1"
    )

    // Absent draft carries the existing record forward, timestamp untouched.
    let carried = computedSegmentDirectionPlans(
        planDrafts: [:], modeDrafts: [:], items: [item], existing: [existing], now: "t2"
    )
    #expect(carried.count == 1)
    #expect(carried[0].updatedAt == "t1")
    #expect(carried[0].source == "llm")
    #expect(carried[0].inputsFingerprint == "fp")

    // A hand edit flips source to user and advances the timestamp.
    var edited = fixturePlan()
    edited.beats[0].action = "The figure sprints instead"
    let userEdited = computedSegmentDirectionPlans(
        planDrafts: [item.pairKey: edited], modeDrafts: [:], items: [item], existing: [existing], now: "t2"
    )
    #expect(userEdited[0].source == "user")
    #expect(userEdited[0].updatedAt == "t2")
    #expect(userEdited[0].llmDraftPlan == fixturePlan().normalized())

    // No existing record + a raw-mode draft equal to the fallback stores nothing.
    let fallbackDraft = shotFallbackDirectionPlan(pair: pair)
    let nothing = computedSegmentDirectionPlans(
        planDrafts: [item.pairKey: fallbackDraft],
        modeDrafts: [item.pairKey: .raw],
        items: [item], existing: [], now: "t2"
    )
    #expect(nothing.isEmpty)

    // The same fallback draft in BEATS mode persists (the user chose beats).
    let kept = computedSegmentDirectionPlans(
        planDrafts: [item.pairKey: fallbackDraft],
        modeDrafts: [item.pairKey: .beats],
        items: [item], existing: [], now: "t2"
    )
    #expect(kept.count == 1)
    #expect(kept[0].mode == .beats)
}

@Test func fallbackDirectionPlanWrapsClassicSentence() {
    let pair = fixturePair()
    let fallback = shotFallbackDirectionPlan(pair: pair)
    #expect(fallback.shotMode == .continuous)
    #expect(fallback.beats.count == 1)
    #expect(fallback.beats[0].action == shotSegmentPrompt(pair: pair))
}

// MARK: - Seedance 2.5 stack parsing

@Test func seedance25StackParsesWithoutCollidingWithSeedance20() throws {
    let stack25 = try #require(ShotRenderStack(rawValue: "fal_seedance_2_5_8s_audio"))
    #expect(stack25.model == .falSeedance25)
    #expect(stack25.segmentSeconds == 8)
    #expect(stack25.generateAudio)
    let stack20 = try #require(ShotRenderStack(rawValue: "fal_seedance_2_0_8s"))
    #expect(stack20.model == .falSeedance20)
    #expect(stack25.rawValue == "fal_seedance_2_5_8s_audio")
    #expect(stack25.pairedModelSelection == .falSeedance25ImageToVideo)
    #expect(stack25.pairedModelSelection.providerModelId == "bytedance/seedance-2.5/image-to-video")
    #expect(stack25.pairedModelSelection.falResolutionTier == .p720)
    #expect(stack25.tailAnchoredModelSelection == nil)
}

// MARK: - Mode-flag law on plan items (preview == render, by construction)

private func shotWithPair(record: ShotSegmentDirectionPlanRecord?) -> (ProjectShot, ShotRenderPair) {
    var shot = ProjectShot(shotId: "s1", createdAt: "t0", updatedAt: "t0")
    shot.entries = [
        ShotFrameEntry(entryId: "e0", frameImageId: "img_a"),
        ShotFrameEntry(entryId: "e1", frameImageId: "img_b"),
    ]
    if let record { shot.segmentDirectionPlans = [record] }
    return (shot, fixturePair())
}

@Test func planItemWithoutRecordIsByteIdenticalToClassicPath() {
    let (shot, pair) = shotWithPair(record: nil)
    let item = makeShotSegmentPromptPlanItem(shot: shot, pair: pair, index: 0)
    #expect(item.generatedPrompt == shotSegmentPrompt(pair: pair))
    #expect(item.compiledDirection == nil)
    #expect(item.promptMode == .raw)
    #expect(item.effectivePrompt == shotSegmentPrompt(pair: pair))
}

@Test func beatsModeCompilesAndIgnoresFlatOverride() {
    let record = ShotSegmentDirectionPlanRecord(
        startFrameImageId: "img_a", endFrameImageId: "img_b",
        placementStartEntryId: "e0", placementEndEntryId: "e1",
        plan: fixturePlan(), promptMode: "beats", updatedAt: "t1"
    )
    var (shot, pair) = shotWithPair(record: record)
    shot.segmentPromptOverrides = [ShotSegmentPromptOverride(
        startFrameImageId: "img_a", endFrameImageId: "img_b",
        placementStartEntryId: "e0", placementEndEntryId: "e1",
        prompt: "an old flat override", updatedAt: "t0"
    )]
    let item = makeShotSegmentPromptPlanItem(shot: shot, pair: pair, index: 0)
    let compiled = item.compiledDirection
    #expect(compiled != nil)
    #expect(item.generatedPrompt == compiled?.canonicalText)
    // The mode-flag law: beats wins, the flat override is ignored.
    #expect(item.effectivePrompt == compiled?.canonicalText)
    #expect(item.overridePrompt == "an old flat override")
    // Default stack is WAN 2.7 — the compiled dialect follows the model.
    #expect(compiled?.dialect == "wan_shots")
}

@Test func rawModeRecordKeepsClassicPathAndRetainsPlan() {
    let record = ShotSegmentDirectionPlanRecord(
        startFrameImageId: "img_a", endFrameImageId: "img_b",
        placementStartEntryId: "e0", placementEndEntryId: "e1",
        plan: fixturePlan(), promptMode: "raw", updatedAt: "t1"
    )
    var (shot, pair) = shotWithPair(record: record)
    shot.segmentPromptOverrides = [ShotSegmentPromptOverride(
        startFrameImageId: "img_a", endFrameImageId: "img_b",
        placementStartEntryId: "e0", placementEndEntryId: "e1",
        prompt: "the raw text wins", updatedAt: "t0"
    )]
    let item = makeShotSegmentPromptPlanItem(shot: shot, pair: pair, index: 0)
    #expect(item.compiledDirection == nil)
    #expect(item.generatedPrompt == shotSegmentPrompt(pair: pair))
    #expect(item.effectivePrompt == "the raw text wins")
    #expect(item.promptMode == .raw)
    // The plan is retained for the mode switch back to beats.
    #expect(item.directionPlan?.plan.isEmpty == false)
}

// MARK: - Direction provenance on segment clips

@Test func segmentClipCarriesDirectionProvenanceAndDecodesLegacy() throws {
    let clip = ShotRenderSegmentClip(
        startFrameImageId: "img_a", endFrameImageId: "img_b",
        clipPath: "/tmp/x.mp4", prompt: "canonical text",
        provider: "fal_image_to_video", model: "fal-ai/kling-video/v3/pro/image-to-video",
        directionPlan: fixturePlan(mode: .multiShot),
        compiledMultiShots: [ShotCompiledKlingShot(prompt: "a.", durationSeconds: 8)],
        compiledDialect: "kling_multi_prompt",
        compilerVersion: shotTemporalCompilerVersion,
        updatedAt: "t1"
    )
    let data = try JSONEncoder().encode(clip)
    let decoded = try JSONDecoder().decode(ShotRenderSegmentClip.self, from: data)
    #expect(decoded == clip)

    let legacy = """
    {"startFrameImageId":"img_a","endFrameImageId":"img_b","clipPath":"/tmp/x.mp4","prompt":"old"}
    """
    let old = try JSONDecoder().decode(ShotRenderSegmentClip.self, from: Data(legacy.utf8))
    #expect(old.directionPlan == nil)
    #expect(old.compiledMultiShots == nil)
    #expect(old.compiledDialect.isEmpty)
    #expect(old.compilerVersion == 0)
}

@Test func directionDeltaDistinguishesBeatsFromCompiler() throws {
    let plan = fixturePlan()
    let compiled = try #require(compileTemporalDirection(
        plan: plan, modelSelection: .falWan27ImageToVideo, durationSeconds: 8
    ))
    var clip = ShotRenderSegmentClip(
        prompt: compiled.canonicalText,
        directionPlan: plan,
        compiledDialect: compiled.dialect,
        compilerVersion: compiled.compilerVersion
    )
    // Same beats, same compiler → no delta.
    #expect(shotSegmentDirectionDelta(clip: clip, nextPlan: plan, nextCompiled: compiled) == nil)
    // Beat content changed → new beats.
    var changed = plan
    changed.beats[0].action = "The figure flees"
    let changedCompiled = try #require(compileTemporalDirection(
        plan: changed, modelSelection: .falWan27ImageToVideo, durationSeconds: 8
    ))
    #expect(shotSegmentDirectionDelta(clip: clip, nextPlan: changed, nextCompiled: changedCompiled) == "New beats")
    // Same beats, moved compiler → new compiler.
    clip.compilerVersion = shotTemporalCompilerVersion - 1
    #expect(shotSegmentDirectionDelta(clip: clip, nextPlan: plan, nextCompiled: compiled) == "New direction compiler")
    clip.compilerVersion = shotTemporalCompilerVersion
    // Same beats, model change spelled a different dialect → new compiler.
    let klingCompiled = try #require(compileTemporalDirection(
        plan: plan, modelSelection: .falKlingV3ProImageToVideo, durationSeconds: 8
    ))
    #expect(shotSegmentDirectionDelta(clip: clip, nextPlan: plan, nextCompiled: klingCompiled) == "New direction compiler")
    // Direction appearing / disappearing names itself.
    let planless = ShotRenderSegmentClip(prompt: "classic sentence")
    #expect(shotSegmentDirectionDelta(clip: planless, nextPlan: nil, nextCompiled: nil) == nil)
    #expect(shotSegmentDirectionDelta(clip: planless, nextPlan: plan, nextCompiled: compiled) == "Beats added")
    #expect(shotSegmentDirectionDelta(clip: clip, nextPlan: nil, nextCompiled: nil) == "Beats removed")
}

// MARK: - Kling multi_prompt wire shape

@Test func klingMultiPromptPayloadSpellsStringDurations() throws {
    let payload = FALVideoClient.klingMultiPromptPayload([
        ShotCompiledKlingShot(prompt: "First shot.", durationSeconds: 3),
        ShotCompiledKlingShot(prompt: "Second shot.", durationSeconds: 5),
    ])
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(text == "[{\"duration\":\"3\",\"prompt\":\"First shot.\"},{\"duration\":\"5\",\"prompt\":\"Second shot.\"}]")
    // The omit-first probe stance: no top-level duration rides multi_prompt
    // until the live endpoint proves it must.
    #expect(!FALVideoClient.klingMultiPromptSendsTopLevelDuration)
}

@Test func seedance25DeclaresItsEndpointFacts() {
    #expect(VideoModelSelection.falSeedance25ImageToVideo.falDurationEncoding == .stringSeconds)
    #expect(VideoModelSelection.falSeedance25ImageToVideo.falResolutionTier == .p720)
    #expect(VideoModelSelection.falSeedance25ImageToVideo.falTokenBilling != nil)
    #expect(ShotRenderModel.falSeedance25.supportedDurations == Array(4...15))
    #expect(ShotRenderModel.falSeedance25.supportsGeneratedAudio)
    #expect(ShotRenderModel.allCases.contains(.falSeedance25))
}

// MARK: - LLM drafting: composer + fingerprint laws

@Test func draftContextDerivesFromShotAndPairAlone() {
    var start = ProjectLensHeroImage(imageId: "img_a")
    start.sourcePrompt = "A figure by the marble meridian at dawn"
    var end = ProjectLensHeroImage(imageId: "img_b")
    end.prompt = "The same figure kneeling, placing a leaf"
    var reframe = LensReframeSpec()
    reframe.parentImageId = "img_a"
    end.reframe = reframe
    let pair = ShotRenderPair(
        start: start, end: end,
        startPlacementEntryId: "e0", endPlacementEntryId: "e1"
    )
    var shot = ProjectShot(shotId: "s1", createdAt: "t0", updatedAt: "t0")
    var narration = ShotNarrationArtifact()
    narration.messagingText = "The offering completes the doorway"
    shot.narrationArtifact = narration

    let context = shotDirectionPlanDraftContext(
        shot: shot, pair: pair, segmentSeconds: 8, strandLines: ["leaf — recurs"]
    )
    #expect(context.startFrameGist == "A figure by the marble meridian at dawn")
    #expect(context.endFrameGist == "The same figure kneeling, placing a leaf")
    #expect(!context.lineageSentence.isEmpty)
    #expect(context.narrationTitle == "The offering completes the doorway")

    let prompt = ShotDirectionPlanComposer.draftPrompt(context: context)
    // The anti-echo law and the lineage constraint both reach the model.
    #expect(prompt.contains("do NOT restate"))
    #expect(prompt.contains("STRUCTURAL FACT"))
    #expect(prompt.contains(context.lineageSentence))
    // Dialect-free by contract: no provider timing syntax is suggested.
    #expect(!prompt.contains("Seedance"))
    #expect(!prompt.contains("Kling"))
    #expect(!prompt.contains("WAN"))
}

@Test func draftFingerprintTracksInputsButNotStrands() {
    let pair = fixturePair()
    let shot = ProjectShot(shotId: "s1", createdAt: "t0", updatedAt: "t0")
    let base = shotDirectionPlanDraftContext(shot: shot, pair: pair, segmentSeconds: 8)
    let withStrands = shotDirectionPlanDraftContext(
        shot: shot, pair: pair, segmentSeconds: 8, strandLines: ["motif — anything"]
    )
    // Strands garnish the prompt but never flip STALE.
    #expect(shotDirectionPlanInputsFingerprint(context: base)
        == shotDirectionPlanInputsFingerprint(context: withStrands))
    // A duration change is a real input change.
    let longer = shotDirectionPlanDraftContext(shot: shot, pair: pair, segmentSeconds: 10)
    #expect(shotDirectionPlanInputsFingerprint(context: base)
        != shotDirectionPlanInputsFingerprint(context: longer))
    var narrated = shot
    var narration = ShotNarrationArtifact()
    narration.messagingText = "New intent"
    narrated.narrationArtifact = narration
    let narratedContext = shotDirectionPlanDraftContext(shot: narrated, pair: pair, segmentSeconds: 8)
    #expect(shotDirectionPlanInputsFingerprint(context: base)
        != shotDirectionPlanInputsFingerprint(context: narratedContext))
}

@Test func beatCountGuidanceScalesWithSegmentLength() {
    #expect(ShotDirectionPlanComposer.beatCountGuidance(segmentSeconds: 5) == "exactly 2 beats")
    #expect(ShotDirectionPlanComposer.beatCountGuidance(segmentSeconds: 8) == "2 or 3 beats")
    #expect(ShotDirectionPlanComposer.beatCountGuidance(segmentSeconds: 12) == "3 or 4 beats")
}
