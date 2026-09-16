import Foundation
import Testing
@testable import LitScenes

// MARK: Fixtures

private func optionFrame(_ id: String) -> ProjectLensHeroImage {
    ProjectLensHeroImage(imageId: id, label: "Frame \(id)", imagePath: "/tmp/\(id).png", prompt: "Scene \(id)", status: "ready")
}

private let optionFrameLookup: [String: ProjectLensHeroImage] = ["f1": optionFrame("f1"), "f2": optionFrame("f2")]

private func optionClip(request: String, path: String, prompt: String) -> ShotRenderSegmentClip {
    ShotRenderSegmentClip(startFrameImageId: "f1", endFrameImageId: "f2", placementStartEntryId: "e1", placementEndEntryId: "e2",
        clipPath: path, requestId: request, prompt: prompt, provider: "fal", model: "minimax/h3-max/image-to-video",
        durationSeconds: 5.2, updatedAt: "t1")
}

private func optionVersion(_ number: Int, clip: ShotRenderSegmentClip) -> ShotRenderArtifact {
    ShotRenderArtifact(versionId: "v\(number)", versionNumber: number, provider: "fal", model: "minimax/h3-max/image-to-video",
        status: "ready", videoPath: "/tmp/v\(number).mp4", clipPaths: [clip.clipPath], segmentCount: 1, totalSeconds: 5,
        segmentClips: [clip], generatedAt: "t\(number)", updatedAt: "t\(number)")
}

private func twoTakeShot() -> ProjectShot {
    var shot = ProjectShot(shotId: "shot_options", entries: [
        ShotFrameEntry(entryId: "e1", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2")
    ])
    shot = shot.upsertingRenderVersion(optionVersion(1, clip: optionClip(request: "r1", path: "/tmp/a1.mp4", prompt: "toward camera")), activate: true, now: "t1")
    shot = shot.upsertingRenderVersion(optionVersion(2, clip: optionClip(request: "r2", path: "/tmp/a2.mp4", prompt: "back straight")), activate: true, now: "t2")
    return shot
}

private func planSegment(_ shot: ProjectShot) -> ShotRenderPlanSegment? {
    shotRenderSegmentPlan(shot: shot, frameLookup: optionFrameLookup, mediaLookup: [:], meaningNodes: []).segments.first
}

private func always(_ path: String) -> Bool { true }

// MARK: Adapters

@Test func ordinaryTakeOptionsMarkThePlayingClipInFilm() throws {
    let shot = twoTakeShot()
    let segment = try #require(planSegment(shot))
    let options = shotTakeOptions(shot: shot, segment: segment, fileExists: always)
    try #require(options.count == 2)
    #expect(options[0].id == "entry:e1>e2#1")
    #expect(options[0].takeNumber == 1 && !options[0].isInFilm)
    #expect(options[1].takeNumber == 2 && options[1].isInFilm)
    #expect(options[1].source == .render(versionId: "v2"))
    #expect(options[1].caption == "TAKE 2 · HAILUO 3 MAX · 5.2s")
    #expect(options[1].prompt == "back straight")
    #expect(shotInFilmTake(options)?.takeNumber == 2)

    // The operator's pick moves IN FILM; a missing file is named, not hidden.
    let picked = shot.selectingSegmentTake(placementKey: "entry:e1>e2", clipPath: "/tmp/a1.mp4", now: "t3")
    let repicked = shotTakeOptions(shot: picked, segment: segment, fileExists: { $0 != "/tmp/a2.mp4" })
    #expect(repicked[0].isInFilm && !repicked[1].isInFilm)
    #expect(repicked[1].status == .fileMissing && !repicked[1].isReady)
    #expect(repicked[1].caption == "TAKE 2 · HAILUO 3 MAX · VIDEO FILE UNAVAILABLE")
}

@Test func continuationTakeOptionsFollowTheRecord() {
    let ready = ShotContinuationTake(takeId: "c1", takeNumber: 1, status: ShotContinuationTakeStatus.ready.rawValue,
        prompt: "keep walking", stack: ShotRenderStack.wan27Five.rawValue,
        segmentClip: ShotRenderSegmentClip(placementStartEntryId: "e2", placementEndEntryId: "e3", clipPath: "/tmp/c1.mp4",
            provider: "fal", model: "wan.v2.7", durationSeconds: 5))
    let failed = ShotContinuationTake(takeId: "c2", takeNumber: 2, status: ShotContinuationTakeStatus.failed.rawValue, errorMessage: "boom")
    let rendering = ShotContinuationTake(takeId: "c3", takeNumber: 3, status: ShotContinuationTakeStatus.generating.rawValue,
        stack: ShotRenderStack.wan27Five.rawValue)
    let record = ShotContinuationRecord(entryId: "e3", sourceEntryId: "e2", selectedTakeId: "c1", takes: [ready, failed, rendering])
    let options = shotTakeOptions(record: record, placementKey: "entry:e2>e3", fileExists: always)
    #expect(options.map(\.takeNumber) == [1, 3])
    #expect(options[0].isInFilm && options[0].isReady)
    #expect(options[0].source == .continuation(entryId: "e3", takeId: "c1"))
    #expect(options[1].status == .rendering && !options[1].isReady && options[1].clip == nil)
    #expect(options[1].caption.hasSuffix("· RENDERING"))
}

@Test func steppingTakesStaysWithinReadyOnes() {
    let shot = twoTakeShot()
    guard let segment = planSegment(shot) else { #expect(Bool(false)); return }
    let options = shotTakeOptions(shot: shot, segment: segment, fileExists: always)
    #expect(shotSteppedTake(options: options, currentId: "entry:e1>e2#2", delta: -1)?.takeNumber == 1)
    #expect(shotSteppedTake(options: options, currentId: "entry:e1>e2#1", delta: -1) == nil)
    #expect(shotSteppedTake(options: options, currentId: "entry:e1>e2#1", delta: 1)?.takeNumber == 2)
    #expect(shotSteppedTake(options: options, currentId: "unknown", delta: 1)?.takeNumber == 1)
    let oneMissing = shotTakeOptions(shot: shot, segment: segment, fileExists: { $0 != "/tmp/a1.mp4" })
    #expect(shotSteppedTake(options: oneMissing, currentId: "entry:e1>e2#2", delta: -1) == nil)
}

// MARK: Player vocabulary

@Test func compareLeaderIsTheLongerTake() {
    #expect(shotCompareLoopLeaderIsLeft(leftSeconds: 5.2, rightSeconds: 5.0))
    #expect(!shotCompareLoopLeaderIsLeft(leftSeconds: 4.9, rightSeconds: 5.0))
    #expect(shotCompareLoopLeaderIsLeft(leftSeconds: 5, rightSeconds: 5))
}

@Test func takeChipAndFooterNameTheTakeAndItsStanding() {
    let context = ShotTakePreviewContext(placementKey: "entry:e1>e2", label: "SEGMENT 1", takeNumber: 1, takeCount: 2, isInFilm: false, source: .render(versionId: "v1"))
    #expect(shotTakeChipTitle(context) == "SEGMENT 1 · TAKE 1 OF 2 · NOT IN FILM")
    var inFilm = context
    inFilm.isInFilm = true
    inFilm.takeNumber = 2
    #expect(shotTakeChipTitle(inFilm) == "SEGMENT 1 · TAKE 2 OF 2 · IN FILM")
    let wholeFile = ShotTakePreviewContext(placementKey: "artifact:v1", label: "RENDER I · WHOLE-SHOT FILE", takeNumber: 0, takeCount: 0, isInFilm: false, source: nil)
    #expect(shotTakeChipTitle(wholeFile) == "RENDER I · WHOLE-SHOT FILE")
    #expect(shotTakeFooterLabel(context: context, compare: nil, seconds: 5.2) == "SEGMENT 1 · TAKE 1 OF 2 · ~5s")
    #expect(shotTakeFooterLabel(context: wholeFile, compare: nil, seconds: 10.4) == "RENDER I · WHOLE-SHOT FILE · ~10s")
    #expect(shotTakeFooterLabel(context: nil, compare: nil, seconds: 5) == "SEGMENT · ~5s")
}

@Test func previewRequestsCarryTheirOwnPlacementKey() {
    let clip = ShotRenderSegmentClip(clipPath: "/tmp/v1.mp4", provider: "fal", model: "m", durationSeconds: 10)
    let plain = ShotVideoRequest(shotId: "shot", intent: .preview(ShotSegmentPreview(clip: clip)))
    #expect(plain.focusedSegmentKey == clip.placementKey)
    let wholeFile = ShotVideoRequest(shotId: "shot", intent: .preview(ShotSegmentPreview(clip: clip, take: ShotTakePreviewContext(
        placementKey: shotArtifactSegmentKey(versionId: "v1"), label: "RENDER I · WHOLE-SHOT FILE",
        takeNumber: 0, takeCount: 0, isInFilm: true, source: nil))))
    #expect(wholeFile.focusedSegmentKey == shotArtifactSegmentKey(versionId: "v1"))
    #expect(wholeFile.autoplay)
}

@Test func takeRenderCTASpeaksInTakesNotVersions() {
    let single = shotTakeRenderCTA(isArmed: false, stackLabel: "Hailuo 3 Max · 5s", nextTakeNumber: 3,
        missingOtherCount: 0, isSingleSegment: true, billLabel: "EST. $0.12")
    #expect(single.title == "Render new take · EST. $0.12")
    #expect(single.help.contains("lands as take 3 of this segment"))
    #expect(!single.help.contains("other segments"))
    let armed = shotTakeRenderCTA(isArmed: true, stackLabel: "WAN 2.7 · 8s", nextTakeNumber: 2,
        missingOtherCount: 2, isSingleSegment: false, billLabel: "")
    #expect(armed.title == "Confirm +2 unsaved")
    #expect(armed.help.contains("this spends"))
    #expect(armed.help.contains("2 other segments have no saved clip"))
    let covered = shotTakeRenderCTA(isArmed: false, stackLabel: "WAN 2.7 · 8s", nextTakeNumber: 2,
        missingOtherCount: 0, isSingleSegment: false, billLabel: "EST. $0.60")
    #expect(covered.help.hasSuffix("the other segments' clips travel in at $0"))
}

@Test func keymapCarriesTheTakesScope() {
    let takes = ShotTransportKeymap.all.filter { $0.scope == ShotTransportKeymap.takesScope }
    #expect(takes.map(\.keys) == ["← / →", "↩ / U", "1 / 2", "Space"])
    let ids = ShotTransportKeymap.all.map(\.id)
    #expect(Set(ids).count == ids.count)
}
