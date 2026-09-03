import Foundation
import Testing
@testable import LitScenes

// Pure coverage for the provenance label law: artifact labels resolve from
// persisted clips, never from the next-render default.

private func generatedClip(
    request: String = "req_1",
    model: String = "fal-ai/wan/v2.7/image-to-video",
    provider: String = "fal_image_to_video",
    seconds: Int = 8,
    audio: Bool = false,
    startEntry: String = "",
    endEntry: String = ""
) -> ShotRenderSegmentClip {
    ShotRenderSegmentClip(
        startFrameImageId: "f_\(request)",
        endFrameImageId: "g_\(request)",
        placementStartEntryId: startEntry,
        placementEndEntryId: endEntry,
        clipPath: "/clips/\(request).mp4",
        requestId: request,
        prompt: "prompt \(request)",
        provider: provider,
        model: model,
        generateAudio: audio,
        requestedDurationSeconds: seconds,
        durationSeconds: Double(seconds)
    )
}

private func footageClip(key: String = "footage_1") -> ShotRenderSegmentClip {
    ShotRenderSegmentClip(
        startFrameImageId: key,
        clipPath: "/clips/\(key).mp4",
        provider: "footage",
        model: "source",
        durationSeconds: 3
    )
}

private func version(_ number: Int, clips: [ShotRenderSegmentClip]) -> ShotRenderArtifact {
    var value = ShotRenderArtifact()
    value.versionId = "v\(number)"
    value.versionNumber = number
    value.status = "ready"
    value.videoPath = "/renders/v\(number).mp4"
    value.segmentClips = clips
    return value
}

// MARK: - Clip model labels

@Test func clipModelShortLabelResolvesKnownIdsAndFallsBackHonestly() {
    #expect(shotClipModelShortLabel(
        provider: "fal_image_to_video",
        model: "fal-ai/wan/v2.7/image-to-video"
    ) == "WAN 2.7")
    // Historical CivitAI WAN 2.7 renders are the same model truth.
    #expect(shotClipModelShortLabel(
        provider: "civitai_wan",
        model: "wan.v2.7.image-to-video"
    ) == "WAN 2.7")
    #expect(shotClipModelShortLabel(
        provider: "fal_image_to_video",
        model: "fal-ai/kling-video/v3/pro/image-to-video"
    ) == "Kling 3 Pro")
    #expect(shotClipModelShortLabel(provider: "footage", model: "source") == "Footage")
    // Unrecognized ids name themselves rather than guessing.
    #expect(shotClipModelShortLabel(
        provider: "fal_image_to_video",
        model: "some/new/endpoint"
    ) == "some/new/endpoint")
    #expect(shotClipModelShortLabel(provider: "mystery", model: "") == "mystery")
    #expect(shotClipModelShortLabel(provider: "", model: "") == "Unknown")
}

// MARK: - Version summary

@Test func provenanceSummaryNamesTheActualMix() {
    // One model, uniform duration + audio: comparable to a stack shortLabel.
    let uniform = version(1, clips: [
        generatedClip(request: "a", model: "fal-ai/kling-video/v3/pro/image-to-video", seconds: 5, audio: true),
        generatedClip(request: "b", model: "fal-ai/kling-video/v3/pro/image-to-video", seconds: 5, audio: true),
        footageClip()
    ])
    #expect(shotRenderProvenanceSummary(version: uniform) == "Kling 3 Pro · 5s · Audio")

    // One model, differing durations: the label alone, no false uniformity.
    let varied = version(2, clips: [
        generatedClip(request: "a", seconds: 8),
        generatedClip(request: "b", seconds: 5)
    ])
    #expect(shotRenderProvenanceSummary(version: varied) == "WAN 2.7")

    // Two models are NAMED — the whole point of the mix label.
    let pair = version(3, clips: [
        generatedClip(request: "a", seconds: 8),
        generatedClip(request: "b", model: "fal-ai/kling-video/v3/pro/image-to-video", seconds: 5, audio: true)
    ])
    #expect(shotRenderProvenanceSummary(version: pair) == "WAN 2.7 + Kling 3 Pro")

    // Three or more collapse to an honest count.
    let trio = version(4, clips: [
        generatedClip(request: "a"),
        generatedClip(request: "b", model: "fal-ai/kling-video/v3/pro/image-to-video"),
        generatedClip(request: "c", model: "bytedance/seedance-2.0/image-to-video")
    ])
    #expect(shotRenderProvenanceSummary(version: trio) == "Mixed · 3 models")

    // Footage-only versions say so.
    #expect(shotRenderProvenanceSummary(version: version(5, clips: [footageClip()])) == "Footage")
}

@Test func provenanceSummaryDegradesToVersionStampsOnLegacyVersions() {
    var legacyStack = version(1, clips: [])
    legacyStack.stack = ShotRenderStack.wan27Eight.rawValue
    #expect(shotRenderProvenanceSummary(version: legacyStack) == "WAN 2.7")

    var legacyMixed = version(2, clips: [])
    legacyMixed.model = "mixed"
    #expect(shotRenderProvenanceSummary(version: legacyMixed) == "Mixed")

    var bare = version(3, clips: [])
    bare.model = "legacy"
    #expect(shotRenderProvenanceSummary(version: bare) == "Rendered")
}

// MARK: - Reuse origin

@Test func clipFirstVersionNumberFindsThePayingVersion() {
    let paid = generatedClip(request: "req_paid")
    let versions = [
        version(1, clips: [paid]),
        version(2, clips: [paid, generatedClip(request: "req_new")]),
        version(3, clips: [paid])
    ]
    #expect(shotClipFirstVersionNumber(requestId: "req_paid", versions: versions) == 1)
    #expect(shotClipFirstVersionNumber(requestId: "req_new", versions: versions) == 2)
    // Footage/legacy clips carry no request id and never mark.
    #expect(shotClipFirstVersionNumber(requestId: "", versions: versions) == nil)
    #expect(shotClipFirstVersionNumber(requestId: "req_unknown", versions: versions) == nil)
}

// MARK: - As-rendered delta

@Test func asRenderedDescriptorAppearsOnlyWhenTheNextRenderWouldChangeTheSegment() {
    let wanEight = ShotRenderStack.wan27Eight

    // A clip matching the stack stays quiet.
    #expect(shotSegmentAsRenderedDescriptor(
        clip: generatedClip(seconds: 8),
        nextStack: wanEight
    ) == nil)

    // Model difference names the rendered truth.
    #expect(shotSegmentAsRenderedDescriptor(
        clip: generatedClip(model: "fal-ai/kling-video/v3/pro/image-to-video", seconds: 5, audio: true),
        nextStack: wanEight
    ) == "Kling 3 Pro · 5s · Audio")

    // Duration difference alone is a delta too.
    #expect(shotSegmentAsRenderedDescriptor(
        clip: generatedClip(seconds: 5),
        nextStack: wanEight
    ) == "WAN 2.7 · 5s")

    // A legacy clip with no recorded duration makes no duration claim.
    #expect(shotSegmentAsRenderedDescriptor(
        clip: generatedClip(seconds: 0),
        nextStack: wanEight
    ) == nil)

    // Footage never deltas — it re-extracts identically for free.
    #expect(shotSegmentAsRenderedDescriptor(
        clip: footageClip(),
        nextStack: wanEight
    ) == nil)
}

// MARK: - Plate ordering

@Test func versionClipsFollowTheCurrentPlanOrderWithOrphansAppended() {
    let first = generatedClip(request: "a", startEntry: "e1", endEntry: "e2")
    let second = generatedClip(request: "b", startEntry: "e2", endEntry: "e3")
    let orphan = generatedClip(request: "old", startEntry: "gone", endEntry: "gone2")
    let held = version(1, clips: [orphan, second, first])
    let ordered = shotVersionClipsInPlanOrder(
        version: held,
        planPlacementKeys: ["entry:e1>e2", "entry:e2>e3"]
    )
    #expect(ordered.map(\.requestId) == ["a", "b", "old"])
}
