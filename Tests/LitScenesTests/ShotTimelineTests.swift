import Foundation
import Testing
@testable import LitScenes

private func testShot(_ frameIds: [String]) -> ProjectShot {
    var shot = ProjectShot(shotId: "shot_test", name: "Test", createdAt: "t0", updatedAt: "t0")
    for (index, frameId) in frameIds.enumerated() {
        shot.entries.append(ShotFrameEntry(entryId: "e\(index)", frameImageId: frameId))
    }
    return shot
}

@Test func shotTimelineDocumentRoundTripAndTolerantDecode() throws {
    var document = ProjectShotTimelineDocument.empty(projectId: "p1")
    document.shots = [testShot(["f1", "f2"])]
    document.updatedAt = "t1"
    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(ProjectShotTimelineDocument.self, from: data)
    #expect(decoded == document)

    // A legacy blob missing updatedAt/name still decodes.
    let legacy = """
    {"schemaVersion": "litscenes.shot_timeline.v0.1", "projectId": "p1",
     "shots": [{"shotId": "s1", "entries": [{"entryId": "e1", "frameImageId": "f1"}]}]}
    """
    let old = try JSONDecoder().decode(ProjectShotTimelineDocument.self, from: Data(legacy.utf8))
    #expect(old.shots.count == 1)
    #expect(old.shots[0].entries[0].frameImageId == "f1")
    #expect(old.updatedAt.isEmpty)
}

@Test func shotNormalizedDropsEmptyEntries() {
    var shot = testShot(["f1"])
    shot.entries.append(ShotFrameEntry(entryId: "", frameImageId: "f2"))
    shot.entries.append(ShotFrameEntry(entryId: "e9", frameImageId: " "))
    #expect(shot.normalized().entries.count == 1)
}

@Test func insertingEntryClampsAndAllowsDuplicates() {
    let shot = testShot(["f1", "f2"])
    let appended = shot.insertingEntry(frameImageId: "f1", at: 99, now: "t1")
    #expect(appended.entries.count == 3)
    #expect(appended.entries[2].frameImageId == "f1")
    // Unrestricted reuse: f1 now appears twice.
    #expect(appended.entries.filter { $0.frameImageId == "f1" }.count == 2)

    let front = shot.insertingEntry(frameImageId: "f3", at: -5, now: "t1")
    #expect(front.entries.first?.frameImageId == "f3")
}

@Test func movingEntryReordersWithinRow() {
    let shot = testShot(["f1", "f2", "f3"])
    // Drag e0 into the gap after f3 (index 3 against the pre-removal row).
    let moved = shot.movingEntry(entryId: "e0", toIndex: 3, now: "t1")
    #expect(moved.entries.map(\.frameImageId) == ["f2", "f3", "f1"])
    #expect(moved.entries.count == 3)

    // Drag e2 into the gap before f1 (index 0).
    let front = shot.movingEntry(entryId: "e2", toIndex: 0, now: "t1")
    #expect(front.entries.map(\.frameImageId) == ["f3", "f1", "f2"])
}

@Test func removingEntryAndDocumentMutations() {
    let shot = testShot(["f1", "f2"])
    #expect(shot.removingEntry(entryId: "e0", now: "t1").entries.map(\.frameImageId) == ["f2"])

    var document = ProjectShotTimelineDocument.empty(projectId: "p1")
    let (withShot, shotId) = document.appendingShot(name: "  Opening  ", now: "t1")
    #expect(withShot.shots.count == 1)
    #expect(withShot.shots[0].name == "Opening")
    #expect(!shotId.isEmpty)

    let renamed = withShot.renamingShot(shotId: shotId, name: "Arrival", now: "t2")
    #expect(renamed.shots[0].name == "Arrival")

    let deleted = renamed.deletingShot(shotId: shotId, now: "t3")
    #expect(deleted.shots.isEmpty)
    document = deleted
}

@Test func shotFrameTransferReadsMediaPayloadAsFootageDrag() throws {
    // MediaIDTransfer shares the .json content type, so tray videos dragged
    // onto the timeline arrive as a bare {mediaId} payload — it decodes as a
    // FOOTAGE drag (the timeline validates the media kind on drop).
    let media = try JSONDecoder().decode(
        ShotFrameTransfer.self,
        from: Data("{\"mediaId\": \"m1\"}".utf8)
    )
    #expect(media.isClipDrag)
    #expect(media.clipMediaId == "m1")
    #expect(media.frameImageId.isEmpty)

    // A payload carrying neither a frame nor footage still fails to decode.
    #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(ShotFrameTransfer.self, from: Data("{}".utf8))
    }

    let valid = try JSONDecoder().decode(
        ShotFrameTransfer.self,
        from: Data("{\"frameImageId\": \"f1\"}".utf8)
    )
    #expect(valid.frameImageId == "f1")
    #expect(valid.isFromGrid)
    #expect(!valid.isClipDrag)
}

@Test func shotFrameTransferEmptyPayloadThrows() throws {
    // A payload carrying neither a frame, footage, nor an entry is garbage —
    // it must throw rather than decode into a do-nothing drop. (Retired
    // ghost-drag payloads land here too and are refused.)
    #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(ShotFrameTransfer.self, from: Data("{}".utf8))
    }
    #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(
            ShotFrameTransfer.self,
            from: Data("{\"ghostSourceCutId\": \"shot_1\", \"ghostStillPath\": \"/tmp/g.png\"}".utf8)
        )
    }
}

private func strandNode(slug: String, kind: String, name: String, definition: String) -> LensContextPromptMeaningNode {
    let json = """
    {"slug": "\(slug)", "kind": "\(kind)", "name": "\(name)", "definition": "\(definition)", "tags": [], "edgeDegree": 0}
    """
    return try! JSONDecoder().decode(LensContextPromptMeaningNode.self, from: Data(json.utf8))
}

private func strandFixture() -> ([ProjectShot], [String: ProjectLensHeroImage], [LensContextPromptMeaningNode]) {
    func frame(_ id: String, prompt: String, styleId: String = "", sceneId: String = "") -> ProjectLensHeroImage {
        var image = ProjectLensHeroImage(imageId: id, status: "ready")
        image.prompt = prompt
        image.sourcePrompt = prompt
        image.sourceAestheticIds = styleId.isEmpty ? [] : [styleId]
        image.sceneId = sceneId
        return image
    }
    let nodes = [
        strandNode(
            slug: "theme.threshold-crossing",
            kind: "theme",
            name: "threshold crossing",
            definition: "Passage between states."
        ),
        strandNode(
            slug: "symbol.beacon",
            kind: "symbol",
            name: "beacon",
            definition: "A guiding signal."
        )
    ]

    let lookup: [String: ProjectLensHeroImage] = [
        "f1": frame("f1", prompt: "A pilgrim pauses at the threshold crossing of the launch gate.", styleId: "s1"),
        "f2": frame("f2", prompt: "The beacon sweeps the fog over the causeway.", styleId: "s1"),
        "f3": frame("f3", prompt: "She steps through the threshold crossing carrying the beacon light.", styleId: "s2"),
        "f4": frame("f4", prompt: "An empty corridor hums.")
    ]
    var shotOne = testShot([])
    shotOne.shotId = "shot_one"
    shotOne.entries = [
        ShotFrameEntry(entryId: "a1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "a2", frameImageId: "f2")
    ]
    var shotTwo = testShot([])
    shotTwo.shotId = "shot_two"
    shotTwo.entries = [
        ShotFrameEntry(entryId: "b1", frameImageId: "f3"),
        ShotFrameEntry(entryId: "b2", frameImageId: "f4")
    ]
    return ([shotOne, shotTwo], lookup, nodes)
}

@Test func strandsMatchLexicallyRequireTwoTouchesAndOrderByTimeline() {
    let (shots, lookup, nodes) = strandFixture()
    let strands = deriveMeaningStrands(shots: shots, frameLookup: lookup, meaningNodes: nodes)

    let threshold = strands.first { $0.slug == "theme.threshold-crossing" }
    #expect(threshold != nil)
    // f1 (shot 0, entry 0) then f3 (shot 1, entry 0) — implied timeline order.
    #expect(threshold?.touches.map { [$0.shotIndex, $0.entryIndex] } == [[0, 0], [1, 0]])

    let beacon = strands.first { $0.slug == "symbol.beacon" }
    #expect(beacon?.touches.count == 2)

    // Style s1 connects f1+f2; s2 touches only f3 so it never becomes a strand.
    #expect(strands.contains { $0.kind == .style && $0.slug == "s1" })
    #expect(!strands.contains { $0.kind == .style && $0.slug == "s2" })
}

@Test func shotRenderStackMappingIsAccurate() {
    #expect(ShotRenderStack.wan27Eight.rawValue == "wan_2_7_8s")
    #expect(ShotRenderStack.klingProFive.rawValue == "kling_pro_5s")
    #expect(ShotRenderStack.wan27Eight.segmentSeconds == 8)
    #expect(ShotRenderStack.klingProFive.segmentSeconds == 5)
    #expect(ShotRenderStack.wan27Eight.pairedModelSelection == .falWan27ImageToVideo)
    #expect(ShotRenderStack.wan27Eight.openEndedModelSelection == .falWan27ImageToVideo)
    #expect(ShotRenderStack.wan27Eight.providerSelection == .falImageToVideo)
    #expect(ShotRenderStack.klingProFive.pairedModelSelection == .klingV26ImageToVideo)
    #expect(ShotRenderStack.wan27Eight.next == .klingProFive)
    #expect(ShotRenderStack.klingProFive.next == .wan27Eight)
    #expect(ProjectShot(preferredRenderStack: "bogus").renderStack == .wan27Eight)
}

@Test func shotAudioDefaultsOnForAudioCapableModels() {
    // Crossing FROM a non-audio model seeds audio ON — there was no choice
    // to preserve (OFF is unrepresentable on WAN).
    let fromWan = ShotRenderStack.fallback.replacingModel(.falKlingV3Pro)
    #expect(fromWan.generateAudio)
    #expect(fromWan.rawValue.hasSuffix("_audio"))
    #expect(ShotRenderStack.fallback.replacingModel(.falSeedance20).generateAudio)

    // Between two audio-capable models the explicit choice carries.
    let explicitOff = fromWan.replacingGeneratedAudio(false)
    #expect(!explicitOff.replacingModel(.falSeedance20).generateAudio)
    let explicitOn = fromWan.replacingGeneratedAudio(true)
    #expect(explicitOn.replacingModel(.falSeedance20).generateAudio)

    // Non-audio targets clamp off — no _audio suffix can appear.
    #expect(!explicitOn.replacingModel(.wan27).generateAudio)
    #expect(!explicitOn.replacingModel(.wan27).rawValue.contains("_audio"))

    // The ratified Kling v2.6 migration stays audio-off.
    #expect(!ShotRenderStack.klingProFive.upgradedForFutureRender.generateAudio)
}

@Test func shotWithoutRenderFieldsStillDecodes() throws {
    let legacy = """
    {"shotId": "s1", "name": "Old", "entries": [{"entryId": "e1", "frameImageId": "f1"}],
     "createdAt": "t0", "updatedAt": "t0"}
    """
    let shot = try JSONDecoder().decode(ProjectShot.self, from: Data(legacy.utf8))
    #expect(shot.renderArtifact == nil)
    #expect(shot.renderStack == .wan27Eight)

    // Artifact round-trip through the shot.
    let artifact = ShotRenderArtifact(
        stack: "wan_2_7_8s", provider: "civitai", model: "wan.v2.7.image-to-video",
        status: "ready", videoPath: "/tmp/shot.mp4", clipPaths: ["/tmp/c1.mp4"],
        segmentCount: 1, totalSeconds: 8, generatedAt: "t1", updatedAt: "t1"
    )
    let stamped = shot.settingRenderArtifact(artifact, now: "t2")
    let data = try JSONEncoder().encode(stamped)
    let decoded = try JSONDecoder().decode(ProjectShot.self, from: data)
    #expect(decoded.renderArtifact?.status == "ready")
    #expect(decoded.renderArtifact?.segmentCount == 1)
}

private func renderVersion(
    _ versionId: String,
    number: Int,
    status: String = "ready",
    videoPath: String = "/tmp/render.mp4",
    generatedAt: String = "t1"
) -> ShotRenderArtifact {
    ShotRenderArtifact(
        versionId: versionId, versionNumber: number,
        stack: "wan_2_7_8s", provider: "civitai", model: "wan.v2.7.image-to-video",
        status: status, videoPath: status == "ready" ? videoPath : "",
        segmentCount: 1, totalSeconds: 8, generatedAt: generatedAt, updatedAt: generatedAt
    )
}

@Test func legacyShotRenderArtifactMigratesToVersionOne() throws {
    let legacy = """
    {"shotId": "s1", "name": "Old", "entries": [{"entryId": "e1", "frameImageId": "f1"}],
     "renderArtifact": {"stack": "wan_2_7_8s", "status": "ready", "videoPath": "/tmp/old.mp4",
                        "segmentCount": 2, "generatedAt": "t1", "updatedAt": "t1"},
     "createdAt": "t0", "updatedAt": "t0"}
    """
    let shot = try JSONDecoder().decode(ProjectShot.self, from: Data(legacy.utf8))
    #expect(shot.renderVersions.count == 1)
    #expect(shot.renderVersions[0].versionNumber == 1)
    #expect(!shot.renderVersions[0].versionId.isEmpty)
    #expect(shot.activeRenderVersionId == shot.renderVersions[0].versionId)
    #expect(shot.activeRenderVersion?.videoPath == "/tmp/old.mp4")
    // The mirror now carries the synthesized version identity.
    #expect(shot.renderArtifact?.versionId == shot.activeRenderVersionId)

    // Deterministic: decoding the same blob twice yields the same versionId.
    let again = try JSONDecoder().decode(ProjectShot.self, from: Data(legacy.utf8))
    #expect(again.renderVersions[0].versionId == shot.renderVersions[0].versionId)
}

@Test func shotRenderVersionsRoundTripWithActivePointer() throws {
    var shot = testShot(["f1"])
    shot = shot.upsertingRenderVersion(renderVersion("v1", number: 1, videoPath: "/tmp/r1.mp4"), activate: true, now: "t1")
    shot = shot.upsertingRenderVersion(renderVersion("v2", number: 2, status: "failed", generatedAt: "t2"), activate: true, now: "t2")
    shot = shot.upsertingRenderVersion(renderVersion("v3", number: 3, videoPath: "/tmp/r3.mp4", generatedAt: "t3"), activate: true, now: "t3")
    // Browse back to the first version — active is NOT the newest.
    shot = shot.activatingRenderVersion("v1", now: "t4")

    let decoded = try JSONDecoder().decode(ProjectShot.self, from: JSONEncoder().encode(shot))
    #expect(decoded.renderVersions.map(\.versionId) == ["v1", "v2", "v3"])
    #expect(decoded.activeRenderVersionId == "v1")
    #expect(decoded.activeRenderVersion?.videoPath == "/tmp/r1.mp4")
    #expect(decoded.renderArtifact?.versionId == "v1")
    // Only ready versions with files are browsable.
    #expect(decoded.browsableRenderVersions.map(\.versionId) == ["v1", "v3"])
    #expect(decoded.isActiveRenderVersion(decoded.renderVersions[0]))
    #expect(!decoded.isActiveRenderVersion(decoded.renderVersions[2]))
}

@Test func upsertingRenderVersionActivatesAndMirrors() {
    var shot = testShot(["f1"])
    shot = shot.upsertingRenderVersion(renderVersion("v1", number: 1), activate: true, now: "t1")
    #expect(shot.activeRenderVersionId == "v1")
    #expect(shot.renderArtifact?.versionId == "v1")

    // Same-id upsert replaces in place — no duplicate.
    var progressed = renderVersion("v1", number: 1, status: "generating")
    progressed.progressText = "SEGMENT 1 OF 2"
    shot = shot.upsertingRenderVersion(progressed, activate: true, now: "t2")
    #expect(shot.renderVersions.count == 1)
    #expect(shot.renderArtifact?.progressText == "SEGMENT 1 OF 2")

    // activate: false leaves the pointer and mirror alone.
    shot = shot.upsertingRenderVersion(renderVersion("v2", number: 2, generatedAt: "t3"), activate: false, now: "t3")
    #expect(shot.renderVersions.count == 2)
    #expect(shot.activeRenderVersionId == "v1")
    #expect(shot.renderArtifact?.versionId == "v1")

    // Versions stay sorted by versionNumber regardless of insert order.
    shot = shot.upsertingRenderVersion(renderVersion("v0", number: 0, generatedAt: "t0"), activate: false, now: "t4")
    #expect(shot.renderVersions.map(\.versionId) == ["v0", "v1", "v2"])

    // Empty versionId is refused.
    let unchanged = shot.upsertingRenderVersion(renderVersion("", number: 9), activate: true, now: "t5")
    #expect(unchanged == shot)
}

@Test func activatingRenderVersionSwitchesPointerAndMirror() {
    var shot = testShot(["f1"])
    shot = shot.upsertingRenderVersion(renderVersion("v1", number: 1, videoPath: "/tmp/r1.mp4"), activate: true, now: "t1")
    shot = shot.upsertingRenderVersion(renderVersion("v2", number: 2, videoPath: "/tmp/r2.mp4", generatedAt: "t2"), activate: true, now: "t2")

    let switched = shot.activatingRenderVersion("v1", now: "t3")
    #expect(switched.activeRenderVersionId == "v1")
    #expect(switched.renderArtifact?.videoPath == "/tmp/r1.mp4")
    #expect(switched.updatedAt == "t3")

    // Unknown ids leave the shot untouched.
    #expect(shot.activatingRenderVersion("nope", now: "t4") == shot)
}

@Test func playableRenderVersionPrefersReadyActive() {
    var shot = testShot(["f1"])
    shot = shot.upsertingRenderVersion(renderVersion("v1", number: 1, videoPath: "/tmp/r1.mp4"), activate: true, now: "t1")
    shot = shot.upsertingRenderVersion(renderVersion("v2", number: 2, videoPath: "/tmp/r2.mp4", generatedAt: "t2"), activate: true, now: "t2")
    // The SELECTED ready version wins even when a newer ready one exists.
    let onV1 = shot.activatingRenderVersion("v1", now: "t3")
    #expect(onV1.playableRenderVersion?.versionId == "v1")
}

@Test func playableRenderVersionSubstitutesWhileActiveGenerating() {
    var shot = testShot(["f1"])
    shot = shot.upsertingRenderVersion(renderVersion("v1", number: 1, videoPath: "/tmp/r1.mp4"), activate: true, now: "t1")
    shot = shot.upsertingRenderVersion(renderVersion("v2", number: 2, status: "generating", generatedAt: "t2"), activate: true, now: "t2")
    // The pointer moved to the generating version at render start — playback
    // substitutes the last finished render, view-only.
    #expect(shot.activeRenderVersion?.versionId == "v2")
    #expect(shot.playableRenderVersion?.versionId == "v1")
}

@Test func playableRenderVersionSubstitutesAfterFailedRender() {
    var shot = testShot(["f1"])
    shot = shot.upsertingRenderVersion(renderVersion("v1", number: 1, videoPath: "/tmp/r1.mp4"), activate: true, now: "t1")
    shot = shot.upsertingRenderVersion(renderVersion("v2", number: 2, status: "failed", generatedAt: "t2"), activate: true, now: "t2")
    #expect(shot.playableRenderVersion?.versionId == "v1")
}

@Test func playableRenderVersionFallsThroughWhenNoReadyVersionExists() {
    var shot = testShot(["f1"])
    shot = shot.upsertingRenderVersion(renderVersion("v1", number: 1, status: "generating"), activate: true, now: "t1")
    // First render: no ready version to substitute — progressive reveal keeps
    // resolving the generating version.
    #expect(shot.playableRenderVersion?.versionId == "v1")
}

@Test func danglingActiveRenderPointerFallsBackToNewest() throws {
    var shot = testShot(["f1"])
    shot = shot.upsertingRenderVersion(renderVersion("v1", number: 1), activate: true, now: "t1")
    shot = shot.upsertingRenderVersion(renderVersion("v2", number: 2, generatedAt: "t2"), activate: true, now: "t2")
    shot.activeRenderVersionId = "gone"
    #expect(shot.activeRenderVersion?.versionId == "v2")

    // Decode repairs the stored pointer (and re-mirrors) via migration.
    let decoded = try JSONDecoder().decode(ProjectShot.self, from: JSONEncoder().encode(shot))
    #expect(decoded.activeRenderVersionId == "v2")
    #expect(decoded.renderArtifact?.versionId == "v2")
}

@Test func segmentClipsDecodeTolerantlyAndRoundTripThroughShot() throws {
    // Legacy artifact JSON without segmentClips decodes to [].
    let legacyArtifact = try JSONDecoder().decode(
        ShotRenderArtifact.self,
        from: Data(#"{"status": "ready", "videoPath": "/tmp/v.mp4"}"#.utf8)
    )
    #expect(legacyArtifact.segmentClips.isEmpty)

    // Partial clip JSON decodes with defaults.
    let partial = try JSONDecoder().decode(
        ShotRenderSegmentClip.self,
        from: Data(#"{"startFrameImageId": "a", "clipPath": "/tmp/c.mp4"}"#.utf8)
    )
    #expect(partial.endFrameImageId == "")
    #expect(partial.pairKey == "a>")

    // normalized() trims and drops records without a clip path.
    var artifact = renderVersion("v1", number: 1)
    artifact.segmentClips = [
        ShotRenderSegmentClip(startFrameImageId: " a ", endFrameImageId: " b ", clipPath: " /tmp/c1.mp4 ", prompt: " p "),
        ShotRenderSegmentClip(startFrameImageId: "a", endFrameImageId: "c", clipPath: "   ")
    ]
    let normalized = artifact.normalized()
    #expect(normalized.segmentClips.count == 1)
    #expect(normalized.segmentClips[0].startFrameImageId == "a")
    #expect(normalized.segmentClips[0].clipPath == "/tmp/c1.mp4")

    // Round-trip through the shot's render versions.
    var shot = testShot(["f1"])
    shot = shot.upsertingRenderVersion(normalized, activate: true, now: "t1")
    let decoded = try JSONDecoder().decode(ProjectShot.self, from: JSONEncoder().encode(shot))
    #expect(decoded.renderVersions[0].segmentClips.count == 1)
    #expect(decoded.renderVersions[0].segmentClips[0].pairKey == "a>b")
}

@Test func segmentClipLookupAndUpsertKeyOnExactPair() {
    var artifact = renderVersion("v1", number: 1)
    artifact.upsertSegmentClip(ShotRenderSegmentClip(startFrameImageId: "a", endFrameImageId: "b", clipPath: "/tmp/ab.mp4"))
    artifact.upsertSegmentClip(ShotRenderSegmentClip(startFrameImageId: "a", endFrameImageId: "", clipPath: "/tmp/open.mp4"))

    // Exact match only — the open-ended "a>" record never matches "a>b".
    #expect(artifact.segmentClip(forStart: "a", end: "b")?.clipPath == "/tmp/ab.mp4")
    #expect(artifact.segmentClip(forStart: "a", end: "")?.clipPath == "/tmp/open.mp4")
    #expect(artifact.segmentClip(forStart: "b", end: "a") == nil)

    // Same-key upsert replaces; different key appends.
    artifact.upsertSegmentClip(ShotRenderSegmentClip(startFrameImageId: "a", endFrameImageId: "b", clipPath: "/tmp/ab_v2.mp4"))
    #expect(artifact.segmentClips.count == 2)
    #expect(artifact.segmentClip(forStart: "a", end: "b")?.clipPath == "/tmp/ab_v2.mp4")
}

@Test func segmentRenderDecisionsReuseOnlyUnderFilterWithSavedClips() {
    let lookup = renderFixtureLookup()
    let shot = testShot(["f1", "f2", "f4"])
    let plan = shotSegmentPromptPlan(shot: shot, frameLookup: lookup, meaningNodes: [])
    #expect(plan.items.count == 2) // f1>f2, f2>f4

    var source = renderVersion("v1", number: 1)
    source.upsertSegmentClip(ShotRenderSegmentClip(startFrameImageId: "f1", endFrameImageId: "f2", clipPath: "/tmp/f1f2.mp4"))
    source.upsertSegmentClip(ShotRenderSegmentClip(startFrameImageId: "f2", endFrameImageId: "f4", clipPath: "/tmp/f2f4.mp4"))

    // No filter → everything generates, even with a fully-populated source.
    #expect(shotSegmentRenderDecisions(items: plan.items, onlySegmentKeys: nil, reuseSource: source, fileExists: { _ in true })
        == [.generate, .generate])

    // Filter on the first segment → it generates, the second reuses.
    let partial = shotSegmentRenderDecisions(
        items: plan.items, onlySegmentKeys: ["f1>f2"], reuseSource: source, fileExists: { _ in true }
    )
    #expect(partial[0] == .generate)
    #expect(partial[1] == .reuse(source.segmentClip(forStart: "f2", end: "f4")!))

    // Legacy source without saved clips → render-missing (all generate).
    #expect(shotSegmentRenderDecisions(items: plan.items, onlySegmentKeys: ["f1>f2"], reuseSource: renderVersion("v0", number: 1), fileExists: { _ in true })
        == [.generate, .generate])

    // Saved record whose file vanished → generate.
    #expect(shotSegmentRenderDecisions(items: plan.items, onlySegmentKeys: ["f1>f2"], reuseSource: source, fileExists: { $0 != "/tmp/f2f4.mp4" })
        == [.generate, .generate])
}

@Test func segmentRenderDecisionsHandleOpenEndedAndDuplicatePairs() {
    let lookup = renderFixtureLookup()

    // Single ready frame → one open-ended pair with key "f1>".
    let single = testShot(["f1"])
    let singlePlan = shotSegmentPromptPlan(shot: single, frameLookup: lookup, meaningNodes: [])
    #expect(singlePlan.items.count == 1)
    #expect(singlePlan.items[0].pair.segmentKey == "f1>")
    var source = renderVersion("v1", number: 1)
    source.upsertSegmentClip(ShotRenderSegmentClip(startFrameImageId: "f1", endFrameImageId: "", clipPath: "/tmp/open.mp4"))
    #expect(shotSegmentRenderDecisions(items: singlePlan.items, onlySegmentKeys: ["f1>"], reuseSource: source, fileExists: { _ in true })
        == [.generate])
    #expect(shotSegmentRenderDecisions(items: singlePlan.items, onlySegmentKeys: ["other>"], reuseSource: source, fileExists: { _ in true })
        == [.reuse(source.segmentClips[0])])

    // Duplicate adjacent pair (f1>f2 twice): both occurrences share one key —
    // filtered together, reused together from the same record.
    let doubled = testShot(["f1", "f2", "f1", "f2"])
    let doubledPlan = shotSegmentPromptPlan(shot: doubled, frameLookup: lookup, meaningNodes: [])
    #expect(doubledPlan.items.count == 3) // f1>f2, f2>f1, f1>f2
    var doubledSource = renderVersion("v1", number: 1)
    doubledSource.upsertSegmentClip(ShotRenderSegmentClip(startFrameImageId: "f1", endFrameImageId: "f2", clipPath: "/tmp/f1f2.mp4"))
    doubledSource.upsertSegmentClip(ShotRenderSegmentClip(startFrameImageId: "f2", endFrameImageId: "f1", clipPath: "/tmp/f2f1.mp4"))
    let onDuplicate = shotSegmentRenderDecisions(
        items: doubledPlan.items, onlySegmentKeys: ["f1>f2"], reuseSource: doubledSource, fileExists: { _ in true }
    )
    #expect(onDuplicate[0] == .generate)
    #expect(onDuplicate[2] == .generate)
    #expect(onDuplicate[1] == .reuse(doubledSource.segmentClip(forStart: "f2", end: "f1")!))
    let onOther = shotSegmentRenderDecisions(
        items: doubledPlan.items, onlySegmentKeys: ["f2>f1"], reuseSource: doubledSource, fileExists: { _ in true }
    )
    let sharedClip = doubledSource.segmentClip(forStart: "f1", end: "f2")!
    #expect(onOther[0] == .reuse(sharedClip))
    #expect(onOther[2] == .reuse(sharedClip))
    #expect(onOther[1] == .generate)
}

@Test func previewableSegmentClipResolvesFromActiveVersionOnly() {
    let lookup = renderFixtureLookup()
    let shot = testShot(["f1", "f2"])
    let plan = shotSegmentPromptPlan(shot: shot, frameLookup: lookup, meaningNodes: [])
    let pair = plan.items[0].pair // f1>f2

    // Legacy version without saved clips → nil.
    var withLegacy = shot.upsertingRenderVersion(renderVersion("v1", number: 1), activate: true, now: "t1")
    #expect(previewableSegmentClip(shot: withLegacy, pair: pair, fileExists: { _ in true }) == nil)

    // The ACTIVE version's clip resolves; a non-active version's clip does not.
    var v2 = renderVersion("v2", number: 2, generatedAt: "t2")
    v2.upsertSegmentClip(ShotRenderSegmentClip(startFrameImageId: "f1", endFrameImageId: "f2", clipPath: "/tmp/v2clip.mp4"))
    withLegacy = withLegacy.upsertingRenderVersion(v2, activate: true, now: "t2")
    #expect(previewableSegmentClip(shot: withLegacy, pair: pair, fileExists: { _ in true })?.clipPath == "/tmp/v2clip.mp4")
    let backToV1 = withLegacy.activatingRenderVersion("v1", now: "t3")
    #expect(previewableSegmentClip(shot: backToV1, pair: pair, fileExists: { _ in true }) == nil)

    // Missing file → nil.
    #expect(previewableSegmentClip(shot: withLegacy, pair: pair, fileExists: { _ in false }) == nil)

    // Open-ended pair keys on the "" end.
    let single = testShot(["f1"])
    let singlePair = shotSegmentPromptPlan(shot: single, frameLookup: lookup, meaningNodes: []).items[0].pair
    var openVersion = renderVersion("v1", number: 1)
    openVersion.upsertSegmentClip(ShotRenderSegmentClip(startFrameImageId: "f1", endFrameImageId: "", clipPath: "/tmp/open.mp4"))
    let openShot = single.upsertingRenderVersion(openVersion, activate: true, now: "t1")
    #expect(previewableSegmentClip(shot: openShot, pair: singlePair, fileExists: { _ in true })?.clipPath == "/tmp/open.mp4")
}

@Test func failingInFlightRenderVersionsFlipsOnlyGenerating() {
    var shot = testShot(["f1"])
    shot = shot.upsertingRenderVersion(renderVersion("v1", number: 1, videoPath: "/tmp/r1.mp4"), activate: true, now: "t1")
    var inFlight = renderVersion("v2", number: 2, status: "generating", generatedAt: "t2")
    inFlight.progressText = "SEGMENT 1 OF 2"
    shot = shot.upsertingRenderVersion(inFlight, activate: true, now: "t2")

    let reconciled = shot.failingInFlightRenderVersions(now: "t3")
    #expect(reconciled.changed)
    let versions = reconciled.shot.renderVersions
    #expect(versions.first { $0.versionId == "v1" }?.status == "ready")
    let failed = versions.first { $0.versionId == "v2" }
    #expect(failed?.status == "failed")
    #expect(failed?.errorMessage == "Interrupted before completion")
    #expect(failed?.progressText == "")
    // The active mirror reflects the flipped version.
    #expect(reconciled.shot.renderArtifact?.status == "failed")

    // Nothing generating → unchanged.
    let idle = reconciled.shot.failingInFlightRenderVersions(now: "t4")
    #expect(!idle.changed)
    #expect(idle.shot == reconciled.shot)
}

private func renderFixtureLookup() -> [String: ProjectLensHeroImage] {
    func frame(_ id: String, status: String, prompt: String = "A quiet harbor scene.") -> ProjectLensHeroImage {
        var image = ProjectLensHeroImage(imageId: id, status: status)
        image.imagePath = status == "ready" ? "/tmp/\(id).png" : ""
        image.prompt = prompt
        image.sourcePrompt = prompt
        return image
    }
    return [
        "f1": frame("f1", status: "ready", prompt: "A pilgrim at the causeway gate."),
        "f2": frame("f2", status: "ready", prompt: "The archive threshold glows ahead."),
        "f3": frame("f3", status: "generating"),
        "f4": frame("f4", status: "ready", prompt: "The orb of departure awaits.")
    ]
}

@Test func shotRenderPairsMapAdjacentReadyFramesAndReportSkips() {
    let lookup = renderFixtureLookup()

    // Five entries, one generating + one missing: 3 ready → 2 pairs, 2 skipped.
    let shot = testShot(["f1", "f2", "f3", "f4", "missing"])
    let result = shotRenderPairs(shot: shot, frameLookup: lookup)
    #expect(result.pairs.count == 2)
    #expect(result.pairs[0].start?.imageId == "f1")
    #expect(result.pairs[0].end?.imageId == "f2")
    #expect(result.pairs[1].start?.imageId == "f2")
    #expect(result.pairs[1].end?.imageId == "f4")
    #expect(result.skipped.count == 2)

    // Single ready frame → one open-ended pair.
    let single = shotRenderPairs(shot: testShot(["f1"]), frameLookup: lookup)
    #expect(single.pairs.count == 1)
    #expect(single.pairs[0].end == nil)

    // Nothing ready → no pairs.
    let empty = shotRenderPairs(shot: testShot(["f3"]), frameLookup: lookup)
    #expect(empty.pairs.isEmpty)
    #expect(empty.skipped.count == 1)
}

@Test func shotSegmentPromptIsOneMotionSentenceAndNothingElse() {
    // The generated prompt directs motion and stops. It must NOT restate what
    // the keyframes already carry: no destination gist (which used to echo the
    // frame's own authoring prompt, reframe percentage geometry and all), no
    // meaning-strand motifs, no no-cuts/no-captions tail. Per-segment intent is
    // hand-authored in the render plan and persists as an override.
    let lookup = renderFixtureLookup()
    let pair = ShotRenderPair(start: lookup["f1"]!, end: lookup["f2"]!)

    let prompt = shotSegmentPrompt(pair: pair)
    #expect(prompt == "Smooth continuous camera and subject motion from the first frame to the last frame.")
    #expect(!prompt.contains("archive threshold glows"))
    #expect(!prompt.contains("The scene arrives at"))
    #expect(!prompt.contains("Preserve continuity of"))
    #expect(!prompt.contains("No cuts"))

    // Open-ended segments get the parallel single sentence.
    let openEnded = shotSegmentPrompt(pair: ShotRenderPair(start: lookup["f1"]!, end: nil))
    #expect(openEnded == "Bring this scene to life with gentle, continuous motion true to what is depicted.")
    #expect(!openEnded.contains("causeway gate"))
    #expect(!openEnded.contains("last frame"))
}

// MARK: Segment prompt overrides (Re-render sheet)

@Test func shotWithoutSegmentPromptOverridesDecodesToEmptyAndRoundTrips() throws {
    let legacy = """
    {"shotId": "s1", "name": "Old", "entries": [{"entryId": "e1", "frameImageId": "f1"}]}
    """
    let shot = try JSONDecoder().decode(ProjectShot.self, from: Data(legacy.utf8))
    #expect(shot.segmentPromptOverrides.isEmpty)

    let stamped = testShot(["f1", "f2"]).settingSegmentPromptOverrides(
        [ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "Drift slowly.", updatedAt: "t1")],
        now: "t1"
    )
    let decoded = try JSONDecoder().decode(ProjectShot.self, from: JSONEncoder().encode(stamped))
    #expect(decoded.segmentPromptOverrides.count == 1)
    #expect(decoded.segmentPromptOverrides[0].startFrameImageId == "f1")
    #expect(decoded.segmentPromptOverrides[0].endFrameImageId == "f2")
    #expect(decoded.segmentPromptOverrides[0].prompt == "Drift slowly.")
}

@Test func segmentPromptOverrideMatchesByImagePairIncludingOpenEnded() {
    let lookup = renderFixtureLookup()
    let shot = testShot(["f1", "f2"]).settingSegmentPromptOverrides(
        [
            ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "Paired edit.", updatedAt: "t1"),
            ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "", prompt: "Open-ended edit.", updatedAt: "t1")
        ],
        now: "t1"
    )
    let paired = ShotRenderPair(start: lookup["f1"]!, end: lookup["f2"]!)
    let openEnded = ShotRenderPair(start: lookup["f1"]!, end: nil)
    let unmatched = ShotRenderPair(start: lookup["f2"]!, end: lookup["f4"]!)
    #expect(shot.segmentPromptOverride(for: paired) == "Paired edit.")
    #expect(shot.segmentPromptOverride(for: openEnded) == "Open-ended edit.")
    #expect(shot.segmentPromptOverride(for: unmatched) == nil)

    // An empty stored prompt never overrides (falls back to generated).
    var withEmpty = testShot(["f1", "f2"])
    withEmpty.segmentPromptOverrides = [ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "   ")]
    #expect(withEmpty.segmentPromptOverride(for: paired) == nil)
}

@Test func shotSegmentPromptPlanSeedsOverrideElseGenerated() {
    let lookup = renderFixtureLookup()
    let shot = testShot(["f1", "f2", "f4"]).settingSegmentPromptOverrides(
        [ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "Custom drift.", updatedAt: "t1")],
        now: "t1"
    )
    let plan = shotSegmentPromptPlan(shot: shot, frameLookup: lookup, meaningNodes: [])
    #expect(plan.items.count == 2)
    // First segment carries the override; generated stays what renderShot would send.
    #expect(plan.items[0].overridePrompt == "Custom drift.")
    #expect(plan.items[0].generatedPrompt == shotSegmentPrompt(pair: plan.items[0].pair))
    // Second segment has no override and falls back to the generated sentence.
    #expect(plan.items[1].overridePrompt == nil)
    #expect(plan.items[1].generatedPrompt == shotSegmentPrompt(pair: plan.items[1].pair))
    // Generated prompts ignore frame CONTENT — the destination gist that used
    // to distinguish them is gone, so lineage-free segments read identically.
    // (Reframe-lineage adjacency is the one structural exception; see
    // PunchInExcursionTests.)
    #expect(plan.items[1].generatedPrompt == plan.items[0].generatedPrompt)
}

@Test func segmentPromptOverridesPruneWhenFramesLeaveShotButSurviveReorder() {
    let overrides = [
        ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "Keep me.", updatedAt: "t1"),
        ShotSegmentPromptOverride(startFrameImageId: "f2", endFrameImageId: "f9", prompt: "Frame left.", updatedAt: "t1"),
        ShotSegmentPromptOverride(startFrameImageId: "f9", endFrameImageId: "", prompt: "Also gone.", updatedAt: "t1")
    ]

    // f9 is not in the strip: its overrides drop, the present pair stays —
    // even when f1/f2 are no longer adjacent (reordered strip).
    let reordered = testShot(["f2", "f4", "f1"])
    let pruned = pruningSegmentPromptOverrides(overrides, entries: reordered.entries)
    #expect(pruned.map(\.prompt) == ["Keep me."])

    // A non-adjacent surviving override is retained in storage but never
    // matches a rendered pair until the frames sit together again.
    let lookup = renderFixtureLookup()
    let plan = shotSegmentPromptPlan(
        shot: reordered.settingSegmentPromptOverrides(overrides, now: "t2"),
        frameLookup: lookup,
        meaningNodes: []
    )
    #expect(plan.items.allSatisfy { $0.overridePrompt == nil })

    // Later entries win a duplicated key.
    let duplicated = [
        ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "Older.", updatedAt: "t1"),
        ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "Newer.", updatedAt: "t2")
    ]
    let deduped = pruningSegmentPromptOverrides(duplicated, entries: testShot(["f1", "f2"]).entries)
    #expect(deduped.map(\.prompt) == ["Newer."])
}

@Test func normalizedDropsEmptySegmentPromptOverrides() {
    var shot = testShot(["f1", "f2"])
    shot.segmentPromptOverrides = [
        ShotSegmentPromptOverride(startFrameImageId: " f1 ", endFrameImageId: " f2 ", prompt: "  Trim me.  "),
        ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "   "),
        // Empty start is a LEAD-IN key (">f2") — legitimate since lead-ins.
        ShotSegmentPromptOverride(startFrameImageId: "", endFrameImageId: "f2", prompt: "Lead-in override."),
        // No frame on either side is junk.
        ShotSegmentPromptOverride(startFrameImageId: "", endFrameImageId: "", prompt: "No frames at all.")
    ]
    let normalized = shot.normalized()
    #expect(normalized.segmentPromptOverrides.map(\.prompt) == ["Trim me.", "Lead-in override."])
    #expect(normalized.segmentPromptOverrides[0].startFrameImageId == "f1")
}

@Test func autosaveMergeIsUpsertOnlyUnion() {
    let existing = [
        ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "Keep me.", updatedAt: "t1"),
        ShotSegmentPromptOverride(startFrameImageId: "", endFrameImageId: "f3", prompt: "Lead-in.", updatedAt: "t1")
    ]
    let computed = [
        ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "Updated.", updatedAt: "t2"),
        ShotSegmentPromptOverride(startFrameImageId: "f2", endFrameImageId: "f3", prompt: "New.", updatedAt: "t2")
    ]
    let merged = mergedAutosavePromptOverrides(existing: existing, computed: computed)
    #expect(merged.map(\.prompt) == ["Updated.", "Lead-in.", "New."])

    // A computed set that OMITS a key (draft momentarily empty or equal to
    // the generated prompt) leaves the existing override untouched —
    // autosave never deletes; RESET/confirm stay the explicit paths.
    let unchanged = mergedAutosavePromptOverrides(existing: existing, computed: [])
    #expect(unchanged.map(\.prompt) == ["Keep me.", "Lead-in."])
}

@Test func autosaveAgreementIgnoresTimestamps() {
    let a = [ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "Same.", updatedAt: "t1")]
    let b = [ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "Same.", updatedAt: "t9")]
    #expect(promptOverridesAgree(a, b))
    let c = [ShotSegmentPromptOverride(startFrameImageId: "f1", endFrameImageId: "f2", prompt: "Different.", updatedAt: "t9")]
    #expect(!promptOverridesAgree(a, c))
}

@Test func jovilabePlateAnglesDistributeUniformly() {
    #expect(JovilabeGeometry.plateAngle(index: 0, count: 4) == 0)
    #expect(JovilabeGeometry.plateAngle(index: 1, count: 4) == 90)
    #expect(JovilabeGeometry.plateAngle(index: 3, count: 4) == 270)
    #expect(JovilabeGeometry.plateAngle(index: 0, count: 0) == 0)
}

@Test func jovilabePointerIndexSnapsToNearestDetentWithWrap() {
    // 5 plates, step 72°. Rotation 0 → plate 0 under the pointer.
    #expect(JovilabeGeometry.pointerIndex(rotationDegrees: 0, count: 5) == 0)
    // Rotating the dial -72° brings plate 1 under the pointer.
    #expect(JovilabeGeometry.pointerIndex(rotationDegrees: -72, count: 5) == 1)
    // Positive rotation wraps backward.
    #expect(JovilabeGeometry.pointerIndex(rotationDegrees: 72, count: 5) == 4)
    // Mid-detent rounds to nearest; multiple turns normalize.
    #expect(JovilabeGeometry.pointerIndex(rotationDegrees: -100, count: 5) == 1)
    #expect(JovilabeGeometry.pointerIndex(rotationDegrees: -72 - 720, count: 5) == 1)
}

@Test func jovilabeRotationBringingIsShortestArcAndRoundTrips() {
    for count in [2, 3, 5, 8] {
        for index in 0..<count {
            for current in [0.0, 45.0, -160.0, 359.0, -720.0] {
                let target = JovilabeGeometry.rotation(bringing: index, count: count, from: current)
                #expect(abs(target - current) <= 180.000001)
                #expect(JovilabeGeometry.pointerIndex(rotationDegrees: target, count: count) == index)
            }
        }
    }
}

@Test func jovilabeInsertionIndexRespectsRotationAndWraps() {
    // No rotation: screen angle 90° over 4 plates → position 1.
    #expect(JovilabeGeometry.insertionIndex(atScreenAngle: 90, rotationDegrees: 0, count: 4) == 1)
    // Dial rotated -90°: the plate slots shifted; screen 0° now maps to position 1.
    #expect(JovilabeGeometry.insertionIndex(atScreenAngle: 0, rotationDegrees: -90, count: 4) == 1)
    // Near-360 rounds back to position 0.
    #expect(JovilabeGeometry.insertionIndex(atScreenAngle: 359, rotationDegrees: 0, count: 4) == 0)
}

@Test func jovilabeMoveGapIndexMatchesMovingEntrySemantics() {
    let shot = testShot(["f1", "f2", "f3", "f4", "f5"])
    // Move plate 0 to FINAL position 3 → [f2,f3,f4,f1,f5].
    let forwardGap = JovilabeGeometry.moveGapIndex(finalIndex: 3, sourceIndex: 0)
    let forward = shot.movingEntry(entryId: "e0", toIndex: forwardGap, now: "t1")
    #expect(forward.entries.map(\.frameImageId) == ["f2", "f3", "f4", "f1", "f5"])
    #expect(forward.entries[3].frameImageId == "f1")

    // Move plate 4 to FINAL position 1 → [f1,f5,f2,f3,f4].
    let backwardGap = JovilabeGeometry.moveGapIndex(finalIndex: 1, sourceIndex: 4)
    let backward = shot.movingEntry(entryId: "e4", toIndex: backwardGap, now: "t1")
    #expect(backward.entries.map(\.frameImageId) == ["f1", "f5", "f2", "f3", "f4"])
    #expect(backward.entries[1].frameImageId == "f5")
}

@Test func strandsAreDeterministicAndCapped() {
    let (shots, lookup, nodes) = strandFixture()
    let first = deriveMeaningStrands(shots: shots, frameLookup: lookup, meaningNodes: nodes)
    let second = deriveMeaningStrands(shots: shots, frameLookup: lookup, meaningNodes: nodes)
    #expect(first == second)

    let capped = deriveMeaningStrands(shots: shots, frameLookup: lookup, meaningNodes: nodes, maxStrands: 1)
    #expect(capped.count == 1)
    // Hue indices are stable positions in the ranked order.
    #expect(first.enumerated().allSatisfy { $0.element.hueIndex == $0.offset })
}

@Test func movingShotReordersDocument() {
    let now = "2026-07-12T00:00:00Z"
    var document = ProjectShotTimelineDocument(projectId: "proj")
    for name in ["one", "two", "three"] {
        document = document.appendingShot(name: name, now: now).document
    }
    let ids = document.shots.map(\.shotId)

    // Move first to the end (seam index == count).
    let toEnd = document.movingShot(shotId: ids[0], toIndex: 3, now: now)
    #expect(toEnd.shots.map(\.shotId) == [ids[1], ids[2], ids[0]])

    // Move last to the front.
    let toFront = document.movingShot(shotId: ids[2], toIndex: 0, now: now)
    #expect(toFront.shots.map(\.shotId) == [ids[2], ids[0], ids[1]])

    // Adjacent seam below self is a no-op (source 0 < 1 → target 0).
    let noop = document.movingShot(shotId: ids[0], toIndex: 1, now: now)
    #expect(noop.shots.map(\.shotId) == ids)

    // Out-of-range indices clamp.
    #expect(document.movingShot(shotId: ids[0], toIndex: 99, now: now).shots.last?.shotId == ids[0])
    #expect(document.movingShot(shotId: ids[2], toIndex: -5, now: now).shots.first?.shotId == ids[2])

    // Unknown id leaves the document untouched.
    #expect(document.movingShot(shotId: "missing", toIndex: 1, now: now) == document)
}

@Test func shotFrameTransferRefusesRowShapedPayloads() throws {
    // The whole-row drag payload died with the shots band; the frame
    // transfer must still refuse a bare {"shotId":…} blob so no future
    // row-shaped drag can activate a frame drop target.
    let rowJSON = Data(#"{"shotId":"s1"}"#.utf8)
    #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(ShotFrameTransfer.self, from: rowJSON)
    }
    let frameJSON = Data(#"{"frameImageId":"f1","sourceShotId":"s","sourceEntryId":"e"}"#.utf8)
    let frame = try JSONDecoder().decode(ShotFrameTransfer.self, from: frameJSON)
    #expect(frame.frameImageId == "f1")
}

@Test func shotAudioTimingLegacyDecodePreservesRecordedOrigin() throws {
    let legacy = """
    {
      "lanes": [{
        "laneId": "microphone",
        "kind": "microphone",
        "label": "Mic",
        "isEnabled": true,
        "volume": 1,
        "activeTakeId": "take_1",
        "microphoneTakes": [{
          "takeId": "take_1",
          "path": "/tmp/take_1.m4a",
          "startSeconds": 2.5,
          "durationSeconds": 4,
          "inputDeviceId": "input",
          "inputDeviceName": "Mic",
          "createdAt": "t0"
        }]
      }]
    }
    """
    let mix = try JSONDecoder().decode(ShotAudioMix.self, from: Data(legacy.utf8))
    let take = try #require(mix.activeMicrophoneTake)
    #expect(take.startSeconds == 2.5)
    #expect(take.recordedStartSeconds == nil)
    #expect(take.effectiveRecordedStartSeconds == 2.5)
    #expect(mix.lane(ShotAudioLaneId.narration).effectiveStartSeconds == 0)

    let moved = mix.settingMicrophoneTakeStartSeconds("take_1", startSeconds: 3)
    #expect(moved.activeMicrophoneTake?.startSeconds == 3)
    #expect(moved.activeMicrophoneTake?.effectiveRecordedStartSeconds == 2.5)
}

@Test func shotAudioMixAmbientAttachDetachAndFirstAttachVolume() {
    let attached = ShotAudioMix().settingAmbientBed(bedId: "ambient_a", path: "/tmp/ambient_a.m4a")
    var lane = attached.lane(ShotAudioLaneId.ambient)
    #expect(lane.hasAmbientBed)
    #expect(lane.ambientBedId == "ambient_a")
    #expect(lane.ambientBedPath == "/tmp/ambient_a.m4a")
    #expect(lane.isEnabled)
    #expect(lane.volume == AmbientTunerMetrics.defaultAttachVolume)
    #expect(lane.label == "Ambient")

    // The user's level survives a bed swap: only the FIRST attach applies the
    // default volume.
    let leveled = attached.settingLaneVolume(ShotAudioLaneId.ambient, volume: 0.8)
    let swapped = leveled.settingAmbientBed(bedId: "ambient_b", path: "/tmp/ambient_b.caf")
    lane = swapped.lane(ShotAudioLaneId.ambient)
    #expect(lane.ambientBedId == "ambient_b")
    #expect(lane.ambientBedPath == "/tmp/ambient_b.caf")
    #expect(lane.volume == 0.8)

    // The lane survives mix normalization.
    #expect(swapped.normalized().lane(ShotAudioLaneId.ambient).hasAmbientBed)

    // Detach disables the lane and clears both pointers.
    let detached = swapped.settingAmbientBed(bedId: nil, path: nil)
    lane = detached.lane(ShotAudioLaneId.ambient)
    #expect(!lane.hasAmbientBed)
    #expect(lane.ambientBedId == nil)
    #expect(lane.ambientBedPath == nil)
    #expect(!lane.isEnabled)
}

@Test func shotAudioMixAmbientLaneTolerantDecode() throws {
    // A lane written before the ambient fields existed decodes with nils.
    // This is the whole-mix-reset guard: the ambient fields are Optional
    // because a lane decode failure would silently reset the user's entire
    // audio mix at the ProjectShot decode (`try?` ?? empty).
    let legacy = """
    {
      "lanes": [{
        "laneId": "ambient",
        "kind": "ambient",
        "label": "Ambient",
        "isEnabled": true,
        "volume": 0.5,
        "activeTakeId": "",
        "microphoneTakes": []
      }]
    }
    """
    let mix = try JSONDecoder().decode(ShotAudioMix.self, from: Data(legacy.utf8))
    let lane = mix.lane(ShotAudioLaneId.ambient)
    #expect(lane.ambientBedId == nil)
    #expect(lane.ambientBedPath == nil)
    #expect(!lane.hasAmbientBed)
    #expect(lane.volume == 0.5)

    // A mix carrying an attached bed round-trips through encode/decode.
    let attached = ShotAudioMix().settingAmbientBed(bedId: "ambient_a", path: "/tmp/a.m4a")
    let data = try JSONEncoder().encode(attached)
    let decoded = try JSONDecoder().decode(ShotAudioMix.self, from: data)
    #expect(decoded.lane(ShotAudioLaneId.ambient).ambientBedId == "ambient_a")
    #expect(decoded.lane(ShotAudioLaneId.ambient).ambientBedPath == "/tmp/a.m4a")

    // A path without a bed id is meaningless and normalizes away.
    var orphan = ShotAudioLane.canonical(ShotAudioLaneId.ambient)
    orphan.ambientBedPath = "/tmp/orphan.m4a"
    #expect(orphan.normalized().ambientBedPath == nil)
}

@Test func shotAudioTimingMovesOnePlacementWithoutChangingItsOrigin() {
    let first = ShotMicrophoneTake(
        takeId: "take_1",
        path: "/tmp/one.m4a",
        startSeconds: 1,
        recordedStartSeconds: 1,
        durationSeconds: 3
    )
    let second = ShotMicrophoneTake(
        takeId: "take_2",
        path: "/tmp/two.m4a",
        startSeconds: 4,
        recordedStartSeconds: 4,
        durationSeconds: 2
    )
    let base = ShotAudioMix().appendingMicrophoneTake(first).appendingMicrophoneTake(second)
    let moved = base
        .settingMicrophoneTakeStartSeconds("take_1", startSeconds: 2.25)
        .settingNarrationStartSeconds(1.5)
    let mic = moved.lane(ShotAudioLaneId.microphone)
    #expect(mic.microphoneTakes.first { $0.takeId == "take_1" }?.startSeconds == 2.25)
    #expect(mic.microphoneTakes.first { $0.takeId == "take_1" }?.effectiveRecordedStartSeconds == 1)
    #expect(mic.microphoneTakes.first { $0.takeId == "take_2" }?.startSeconds == 4)
    #expect(moved.lane(ShotAudioLaneId.narration).effectiveStartSeconds == 1.5)
}

@Test func shotAudioTimingQuantizesSnapsAndNudgesAtTwentyFourFPS() {
    let snapped = ShotAudioTiming.movedStart(
        initialStart: 1,
        translationPixels: 20,
        timelineWidth: 1_000,
        timelineDuration: 10,
        playheadSeconds: 1.25,
        bypassesPlayheadSnap: false
    )
    #expect(snapped.snappedToPlayhead)
    #expect(snapped.startSeconds == 1.25)

    let free = ShotAudioTiming.movedStart(
        initialStart: 1,
        translationPixels: 20,
        timelineWidth: 1_000,
        timelineDuration: 10,
        playheadSeconds: 1.25,
        bypassesPlayheadSnap: true
    )
    #expect(!free.snappedToPlayhead)
    #expect(abs(free.startSeconds - (29.0 / 24.0)) < 0.000_1)
    #expect(ShotAudioTiming.nudgedStart(1, frames: 1, timelineDuration: 10) == 25.0 / 24.0)
    #expect(ShotAudioTiming.nudgedStart(1, frames: -10, timelineDuration: 10) == 14.0 / 24.0)
    #expect(ShotAudioTiming.normalizedStart(20, timelineDuration: 10) == 239.0 / 24.0)
    #expect(ShotAudioTiming.timecode(61.5) == "01:01:12")
}

@Test @MainActor func shotAudioRegionUndoRegistersSymmetricRedo() {
    let undoManager = UndoManager()
    let coordinator = ShotAudioRegionUndoCoordinator()
    var appliedStarts: [Double] = []
    var deletedIds: [String] = []
    coordinator.applyRegion = { region in appliedStarts.append(region.startSeconds) }
    coordinator.deleteRegion = { regionId in deletedIds.append(regionId) }

    var old = ShotAudioRegion(
        regionId: "r1",
        laneId: ShotAudioLaneId.clip,
        path: "/a.mp3",
        startSeconds: 1,
        durationSeconds: 2
    )
    var new = old
    new.startSeconds = 2
    coordinator.registerEdit(old: old, new: new, actionName: "Move Audio Region", undoManager: undoManager)
    undoManager.undo()
    #expect(appliedStarts == [1])
    undoManager.redo()
    #expect(appliedStarts == [1, 2])

    // Delete → undo restores wholesale → redo deletes again.
    old.startSeconds = 1
    coordinator.registerDelete(old, undoManager: undoManager)
    undoManager.undo()
    #expect(appliedStarts == [1, 2, 1])
    undoManager.redo()
    #expect(deletedIds == ["r1"])
}

@Test func shotRestyleArtifactTolerantDecodeDefaultsStyleFields() throws {
    let legacyJSON = """
    {"versionId": "shotlook_a", "versionNumber": 2, "status": "ready", "prompt": "Painterly dusk", "videoPath": "/tmp/look.mp4"}
    """
    let legacy = try JSONDecoder().decode(ShotRestyleArtifact.self, from: Data(legacyJSON.utf8))
    #expect(legacy.versionId == "shotlook_a")
    #expect(legacy.styleId.isEmpty)
    #expect(legacy.styleLabel.isEmpty)
    #expect(legacy.styleCollection.isEmpty)
    #expect(legacy.styleHueHex.isEmpty)
    #expect(legacy.styleSummary.isEmpty)
    #expect(legacy.styleCatalogVersion.isEmpty)

    var styled = legacy
    styled.styleId = "sref_042"
    styled.styleLabel = "Gilded Noir"
    styled.styleCollection = "Nocturnes"
    styled.styleHueHex = "#B08D2F"
    styled.styleSummary = "Gilded noir: lacquered shadows with brass rim light"
    styled.styleCatalogVersion = "v7"
    let data = try JSONEncoder().encode(styled)
    let decoded = try JSONDecoder().decode(ShotRestyleArtifact.self, from: data)
    #expect(decoded == styled)

    var padded = styled
    padded.styleLabel = "  Gilded Noir  "
    let normalized = padded.normalized()
    #expect(normalized.styleLabel == "Gilded Noir")
    #expect(normalized.styleSummary == styled.styleSummary)
}

@Test func shotLookComposedPromptShapes() {
    #expect(
        shotLookComposedPrompt(styleSummary: "Sun-bleached gouache", userText: "Keep the gecko emerald")
            == "Style direction: Sun-bleached gouache\n\nKeep the gecko emerald"
    )
    #expect(
        shotLookComposedPrompt(styleSummary: "  Sun-bleached gouache  ", userText: "  ")
            == "Style direction: Sun-bleached gouache"
    )
    #expect(
        shotLookComposedPrompt(styleSummary: "", userText: "Keep the gecko emerald")
            == "Keep the gecko emerald"
    )
    #expect(shotLookComposedPrompt(styleSummary: " ", userText: "").isEmpty)

    let long = shotLookComposedPrompt(
        styleSummary: "Etched brass daylight",
        userText: String(repeating: "n", count: 3_000)
    )
    #expect(long.count > 1_500)
    #expect(String(long.prefix(1_500)).hasPrefix("Style direction: Etched brass daylight"))
}

@Test func shotLookStyleSelectionUsability() {
    #expect(ShotLookStyleSelection(styleId: "sref_042", summary: "Gilded noir").isUsable)
    #expect(!ShotLookStyleSelection(styleId: "", summary: "Gilded noir").isUsable)
    #expect(!ShotLookStyleSelection(styleId: "sref_042", summary: "  ").isUsable)
    #expect(!ShotLookStyleSelection().isUsable)
}

@Test func shotRestyleArtifactClipFieldsTolerantDecode() throws {
    let legacyJSON = """
    {"versionId": "shotlook_a", "status": "ready", "prompt": "Painterly dusk"}
    """
    let legacy = try JSONDecoder().decode(ShotRestyleArtifact.self, from: Data(legacyJSON.utf8))
    #expect(legacy.sourceClipMediaId.isEmpty)
    #expect(legacy.sourceClipStartSeconds == 0)
    #expect(legacy.sourceClipEndSeconds == 0)
    #expect(legacy.outputMediaId.isEmpty)
    #expect(!legacy.isClipLook)

    var clipLook = legacy
    clipLook.versionId = "cliplook_b"
    clipLook.sourceClipMediaId = "trim_1"
    clipLook.sourceClipStartSeconds = 2.5
    clipLook.sourceClipEndSeconds = 7
    clipLook.outputMediaId = "genmedia_x"
    let data = try JSONEncoder().encode(clipLook)
    let decoded = try JSONDecoder().decode(ShotRestyleArtifact.self, from: data)
    #expect(decoded == clipLook)
    #expect(decoded.isClipLook)
    #expect(abs(decoded.clipRangeSeconds - 4.5) < 0.000_1)

    var padded = clipLook
    padded.sourceClipMediaId = "  trim_1  "
    padded.sourceClipStartSeconds = -3
    let normalized = padded.normalized()
    #expect(normalized.sourceClipMediaId == "trim_1")
    #expect(normalized.sourceClipStartSeconds == 0)
}

@Test func projectShotClipLookVersionsTolerantDecodeAndRoundTrip() throws {
    let legacyJSON = """
    {"shotId": "shot_1", "name": "Test", "lookVersions": [{"versionId": "shotlook_a", "status": "ready", "videoPath": "/tmp/a.mp4"}], "activeLookVersionId": "shotlook_a"}
    """
    let legacy = try JSONDecoder().decode(ProjectShot.self, from: Data(legacyJSON.utf8))
    #expect(legacy.clipLookVersions.isEmpty)
    #expect(legacy.activeLookVersionId == "shotlook_a")

    var shot = legacy
    shot.clipLookVersions = [
        ShotRestyleArtifact(
            versionId: "cliplook_1",
            versionNumber: 1,
            status: "failed",
            sourceClipMediaId: "trim_1",
            sourceClipStartSeconds: 1,
            sourceClipEndSeconds: 5
        )
    ]
    let data = try JSONEncoder().encode(shot)
    let decoded = try JSONDecoder().decode(ProjectShot.self, from: data)
    #expect(decoded.clipLookVersions.map(\.versionId) == ["cliplook_1"])

    var withEmpty = decoded
    withEmpty.clipLookVersions.append(ShotRestyleArtifact(versionId: "  "))
    let normalized = withEmpty.normalized()
    #expect(normalized.clipLookVersions.map(\.versionId) == ["cliplook_1"])
    #expect(normalized.lookVersions.map(\.versionId) == ["shotlook_a"])
    #expect(normalized.activeLookVersionId == "shotlook_a")
}

@Test func upsertingClipLookVersionReplacesByIdAndNeverActivates() {
    var shot = ProjectShot(shotId: "shot_1", name: "Test", createdAt: "t0", updatedAt: "t0")
    shot.activeLookVersionId = ""
    let first = ShotRestyleArtifact(
        versionId: "cliplook_1",
        versionNumber: 1,
        status: "queued",
        sourceClipMediaId: "trim_1",
        sourceClipStartSeconds: 0,
        sourceClipEndSeconds: 4,
        generatedAt: "t1"
    )
    shot = shot.upsertingClipLookVersion(first, now: "t1")
    #expect(shot.clipLookVersions.count == 1)

    var ready = first
    ready.status = "ready"
    ready.videoPath = "/tmp/look.mp4"
    ready.outputMediaId = "genmedia_1"
    shot = shot.upsertingClipLookVersion(ready, now: "t2")
    #expect(shot.clipLookVersions.count == 1)
    #expect(shot.clipLookVersions[0].status == "ready")
    #expect(shot.activeLookVersionId.isEmpty)
    #expect(shot.updatedAt == "t2")
}
