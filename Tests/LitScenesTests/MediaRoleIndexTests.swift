import Foundation
import Testing
@testable import LitScenes

private func roleTestItem(_ mediaId: String, kind: MediaKind, derivativeKind: String? = nil, sourceMediaId: String? = nil) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: mediaId,
        sourceId: "source_1",
        kind: kind,
        filename: "\(mediaId).\(kind == .image ? "jpg" : "mov")",
        path: "/tmp/\(mediaId)",
        relativePath: mediaId,
        byteCount: 1,
        modifiedAt: "",
        width: 100,
        height: 100,
        durationSeconds: kind == .video ? 5 : nil,
        nominalFrameRate: nil,
        thumbnailPath: "",
        videoStripPath: nil,
        scannedAt: "",
        scanError: nil,
        derivativeKind: derivativeKind,
        sourceMediaId: sourceMediaId
    )
}

private func roleTestIndex() -> MediaRoleIndex {
    let characters = [
        ProjectCharacter(characterId: "char_1", name: "Ava", referenceMediaIds: ["img_ref", "img_shared"])
    ]
    let objects = [
        ProjectObject(objectId: "obj_1", name: "Lantern", referenceMediaIds: ["img_shared"])
    ]
    let places = [
        ProjectPlace(placeId: "place_1", name: "Harbor", referenceMediaIds: ["img_place"])
    ]
    let shots = [
        ProjectShot(shotId: "shot_1", entries: [
            ShotFrameEntry(entryId: "e1", frameImageId: "frame_1"),
            ShotFrameEntry(entryId: "e2", clipMediaId: "trim_placed")
        ])
    ]
    var hero = ProjectLensHeroImage(imageId: "hero_1")
    hero.sourceDependencies = [
        LensRenderSourceDependency(dependencyId: "d1", kind: "moodboard_image", sourceId: "img_used", role: "prompt_image_source"),
        // Duplicate stamp on the same render counts once.
        LensRenderSourceDependency(dependencyId: "d2", kind: "moodboard_image", sourceId: "img_used", role: "prompt_image_source"),
        // Style/reframe dependencies never count as frame uses.
        LensRenderSourceDependency(dependencyId: "d3", kind: "lens_render_version", sourceId: "img_used", role: "reframe_parent"),
        LensRenderSourceDependency(dependencyId: "d4", kind: "moodboard_image", sourceId: "img_used_other", role: "style_source")
    ]
    var secondHero = ProjectLensHeroImage(imageId: "hero_2")
    secondHero.sourceDependencies = [
        LensRenderSourceDependency(dependencyId: "d5", kind: "moodboard_image", sourceId: "img_used", role: "prompt_image_source")
    ]
    let lens = ProjectLens(lensId: "lens_1", heroImages: [hero, secondHero])
    return buildMediaRoleIndex(characters: characters, objects: objects, places: places, shots: shots, lenses: [lens])
}

@Test func roleIndexStoryInputRequiresImageAndNotRejected() {
    let index = MediaRoleIndex()
    let image = roleTestItem("img_1", kind: .image)
    let promoted = index.badges(for: image, curation: MediaCurationRecord(mediaId: "img_1", rejected: false))
    #expect(promoted == [.storyInput])
    let libraryOnly = index.badges(for: image, curation: MediaCurationRecord(mediaId: "img_1", rejected: true))
    #expect(libraryOnly.isEmpty)
    // Videos are structurally excluded from Story input regardless of curation.
    let video = roleTestItem("vid_1", kind: .video)
    #expect(index.badges(for: video, curation: MediaCurationRecord(mediaId: "vid_1", rejected: false)).isEmpty)
}

@Test func roleIndexRosterBadgesAcrossKinds() {
    let index = roleTestIndex()
    let shared = roleTestItem("img_shared", kind: .image)
    let badges = index.badges(for: shared, curation: MediaCurationRecord(mediaId: "img_shared", rejected: true))
    #expect(badges.contains(.characterRef(name: "Ava")))
    #expect(badges.contains(.objectRef(name: "Lantern")))
    let place = roleTestItem("img_place", kind: .image)
    #expect(index.badges(for: place, curation: MediaCurationRecord(mediaId: "img_place", rejected: true)) == [.placeRef(name: "Harbor")])
}

@Test func roleIndexFootageBadgesExactPlacedItemOnly() {
    let index = roleTestIndex()
    let placedTrim = roleTestItem("trim_placed", kind: .video, derivativeKind: MediaItemRecord.videoTrimDerivativeKind, sourceMediaId: "vid_parent")
    #expect(index.badges(for: placedTrim, curation: MediaCurationRecord(mediaId: "trim_placed")) == [.footage])
    // The parent video was never placed itself — no badge.
    let parent = roleTestItem("vid_parent", kind: .video)
    #expect(index.badges(for: parent, curation: MediaCurationRecord(mediaId: "vid_parent")).isEmpty)
}

@Test func roleIndexCountsDistinctRendersPerSourceMedia() {
    let index = roleTestIndex()
    let used = roleTestItem("img_used", kind: .image)
    let badges = index.badges(for: used, curation: MediaCurationRecord(mediaId: "img_used", rejected: true))
    // Two renders referenced it (duplicate stamps within one render collapse;
    // reframe/style dependencies don't count).
    #expect(badges == [.usedInFrames(count: 2)])
    let styledOnly = roleTestItem("img_used_other", kind: .image)
    #expect(index.badges(for: styledOnly, curation: MediaCurationRecord(mediaId: "img_used_other", rejected: true)).isEmpty)
}

@Test func roleIndexBadgeOrderIsStoryRosterFootageFrames() {
    var index = roleTestIndex()
    index.footageMediaIds.insert("img_everything")
    index.frameUseCountByMediaId["img_everything"] = 1
    index.characterNamesByMediaId["img_everything"] = ["Ava"]
    let item = roleTestItem("img_everything", kind: .image)
    let badges = index.badges(for: item, curation: MediaCurationRecord(mediaId: "img_everything", rejected: false))
    // Image kind: the footage badge is video-only, so it must not appear even
    // when the id is (impossibly) in the footage set.
    #expect(badges == [.storyInput, .characterRef(name: "Ava"), .usedInFrames(count: 1)])
}

@Test func roleIndexTracksUsedFramesAlongsideFootageWithoutDisturbingExistingFields() {
    let index = roleTestIndex()
    // New field: frames placed in current entries (SCENES v2 "unused" truth).
    #expect(index.usedFrameImageIds == ["frame_1"])
    // Regression: the pre-existing placement/usage fields are untouched by
    // the addition.
    #expect(index.footageMediaIds == ["trim_placed"])
    #expect(index.frameUseCountByMediaId["img_used"] == 2)
    #expect(index.characterNamesByMediaId["img_ref"] == ["Ava"])
}
