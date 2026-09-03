import Foundation
import Testing
@testable import LitScenes

// THE SCENES MEDIA PANEL's pure laws: what a media drop does (kind-branching,
// never payload-shape-branching) and how the panel sections images.

private func mediaFixture(
    _ id: String,
    kind: MediaKind,
    derivativeKind: String? = nil,
    sourceMediaId: String? = nil
) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: id,
        sourceId: "source_test",
        kind: kind,
        filename: "\(id).\(kind == .video ? "mp4" : kind == .audio ? "mp3" : "jpg")",
        path: "/tmp/\(id)",
        relativePath: id,
        byteCount: 1,
        modifiedAt: "2026-08-08T00:00:00Z",
        width: 1920,
        height: 1080,
        durationSeconds: kind == .image ? nil : 8,
        nominalFrameRate: nil,
        thumbnailPath: "",
        videoStripPath: nil,
        scannedAt: "2026-08-08T00:00:00Z",
        scanError: nil,
        derivativeKind: derivativeKind,
        sourceMediaId: sourceMediaId
    )
}

// MARK: - Insert plan (the drop law)

@Test func mediaInsertPlanBranchesOnResolvedKind() {
    // Video → footage, exactly as before.
    #expect(
        shotMediaInsertPlan(media: mediaFixture("vid", kind: .video), adoptedFrameImageId: nil)
            == .placeClip(mediaId: "vid")
    )
    // Image already adopted for this lens → place the existing Frame.
    #expect(
        shotMediaInsertPlan(media: mediaFixture("pic", kind: .image), adoptedFrameImageId: "lens_hero_abc")
            == .placeFrame(frameImageId: "lens_hero_abc")
    )
    // A blank adopted id is absence, not a frame.
    #expect(
        shotMediaInsertPlan(media: mediaFixture("pic", kind: .image), adoptedFrameImageId: "  ")
            == .adoptImageAsFrame(mediaId: "pic")
    )
    // Un-adopted image → mint the Frame first.
    #expect(
        shotMediaInsertPlan(media: mediaFixture("pic", kind: .image), adoptedFrameImageId: nil)
            == .adoptImageAsFrame(mediaId: "pic")
    )
}

@Test func mediaInsertPlanRefusalsCarryReasons() {
    // Missing media and audio both refuse with an honest reason — the drop
    // must never silently no-op.
    for plan in [
        shotMediaInsertPlan(media: nil, adoptedFrameImageId: nil),
        shotMediaInsertPlan(media: mediaFixture("song", kind: .audio), adoptedFrameImageId: nil)
    ] {
        guard case .refuse(let reason) = plan else {
            Issue.record("expected refusal, got \(plan)")
            continue
        }
        #expect(!reason.trimmed.isEmpty)
    }
}

@Test func extractedStillPlansLikeAnyPhoto() {
    // A video_frame still is an image — dragging it adopts it as a Frame.
    let still = mediaFixture(
        "still",
        kind: .image,
        derivativeKind: MediaItemRecord.videoFrameDerivativeKind,
        sourceMediaId: "vid"
    )
    #expect(shotMediaInsertPlan(media: still, adoptedFrameImageId: nil) == .adoptImageAsFrame(mediaId: "still"))
}

// MARK: - Panel inventory (each image exactly once)

@Test func scenesInventoryPartitionsImagesExactlyOnce() {
    let items = [
        mediaFixture("promoted", kind: .image),
        mediaFixture("hidden", kind: .image),
        mediaFixture("still", kind: .image, derivativeKind: MediaItemRecord.videoFrameDerivativeKind, sourceMediaId: "vid"),
        mediaFixture("restyle", kind: .image, derivativeKind: MediaItemRecord.mediaRestyleDerivativeKind),
        mediaFixture("vid", kind: .video),
        mediaFixture("song", kind: .audio)
    ]
    let rejected: Set<String> = ["hidden", "still", "restyle"]
    let inventory = scenesMediaInventory(items: items, isRejected: { rejected.contains($0.mediaId) })

    #expect(inventory.storyInputs.map(\.mediaId) == ["promoted"])
    // The hidden section excludes extracted stills (they nest under their
    // parent footage) and generated media (Creations owns those — the
    // rejected-by-default double-listing trap).
    #expect(inventory.hiddenImages.map(\.mediaId) == ["hidden"])
}

@Test func scenesInventoryKeepsPromotedGeneratedImagesInStoryInputs() {
    // An explicitly promoted (un-rejected) generated image reads as a Story
    // Input — parity with the Media tab's enabledContentItems.
    let restyle = mediaFixture("restyle", kind: .image, derivativeKind: MediaItemRecord.mediaRestyleDerivativeKind)
    let inventory = scenesMediaInventory(items: [restyle], isRejected: { _ in false })
    #expect(inventory.storyInputs.map(\.mediaId) == ["restyle"])
    #expect(inventory.hiddenImages.isEmpty)
}

// MARK: - Filter law

@Test func scenesMediaFilterMatchesNameAndTags() {
    #expect(scenesMediaFilterMatches(filename: "Track_Night.jpg", tags: [], query: ""))
    #expect(scenesMediaFilterMatches(filename: "Track_Night.jpg", tags: [], query: "night"))
    #expect(scenesMediaFilterMatches(filename: "IMG_0042.jpg", tags: ["athlete", "dusk"], query: "DUSK"))
    #expect(!scenesMediaFilterMatches(filename: "IMG_0042.jpg", tags: ["athlete"], query: "harbor"))
}
