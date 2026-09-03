import Foundation
import Testing
@testable import LitScenes

private func creationTestItem(_ mediaId: String, kind: MediaKind, derivativeKind: String?, path: String? = nil, sourceMediaId: String? = nil) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: mediaId,
        sourceId: MediaItemRecord.generatedMediaSourceId,
        kind: kind,
        filename: "\(mediaId).\(kind == .image ? "png" : "mp4")",
        path: path ?? "/tmp/\(mediaId)",
        relativePath: mediaId,
        byteCount: 1,
        modifiedAt: "",
        width: 100,
        height: 100,
        durationSeconds: kind == .video ? 4 : nil,
        nominalFrameRate: nil,
        thumbnailPath: "",
        videoStripPath: nil,
        scannedAt: "",
        scanError: nil,
        derivativeKind: derivativeKind,
        sourceMediaId: sourceMediaId
    )
}

private func creationTestTake(_ imageId: String, path: String) -> ProjectLensHeroImage {
    var take = ProjectLensHeroImage(imageId: imageId)
    take.status = "ready"
    take.imagePath = path
    return take
}

private func groupRefIds(_ groups: [CreationGroup], _ kind: CreationGroup.Kind) -> [String] {
    groups.first { $0.kind == kind }?.refs.map(\.id) ?? []
}

@Test func creationsUnionListsTakesAndDedupesAdoptedTwins() {
    let lens = ProjectLens(lensId: "lens_1", heroImages: [creationTestTake("take_1", path: "/tmp/take_1.png")])
    let items = [
        // The adopted twin of take_1 — same file, must not double-list.
        creationTestItem("twin", kind: .image, derivativeKind: MediaItemRecord.frameReferenceDerivativeKind, path: "/tmp/take_1.png"),
        // A frame_reference with its own file — listed.
        creationTestItem("loose_frame", kind: .image, derivativeKind: MediaItemRecord.frameReferenceDerivativeKind)
    ]
    let groups = creationsInventory(items: items, lenses: [lens])
    #expect(groupRefIds(groups, .frames) == ["take_take_1", "media_loose_frame"])
}

@Test func creationsDedupeTakeSharedAcrossLenses() {
    let take = creationTestTake("take_shared", path: "/tmp/shared.png")
    let groups = creationsInventory(
        items: [],
        lenses: [
            ProjectLens(lensId: "lens_1", heroImages: [take]),
            ProjectLens(lensId: "lens_2", heroImages: [take])
        ]
    )
    #expect(groupRefIds(groups, .frames) == ["take_take_shared"])
}

@Test func creationsGroupShotArtifactsIncludingNestedLooks() {
    let items = [
        creationTestItem("look", kind: .video, derivativeKind: MediaItemRecord.shotLookDerivativeKind),
        // A clip look nests under a source in the tray — still a creation here.
        creationTestItem("clip_look", kind: .video, derivativeKind: MediaItemRecord.clipLookDerivativeKind, sourceMediaId: "vid_1"),
        creationTestItem("export", kind: .video, derivativeKind: MediaItemRecord.shotExportDerivativeKind),
        creationTestItem("chain_clip", kind: .video, derivativeKind: MediaItemRecord.videoChainClipDerivativeKind),
        creationTestItem("reel", kind: .video, derivativeKind: MediaItemRecord.videoChainReelDerivativeKind)
    ]
    let groups = creationsInventory(items: items, lenses: [])
    #expect(groupRefIds(groups, .shotArtifacts) == ["media_look", "media_clip_look", "media_export", "media_chain_clip", "media_reel"])
}

@Test func creationsExcludeSourcesAndInternalSupportMedia() {
    let items = [
        // Sources: the Studio's stills and trims belong to Sources, not Creations.
        creationTestItem("still", kind: .image, derivativeKind: MediaItemRecord.videoFrameDerivativeKind, sourceMediaId: "vid_1"),
        creationTestItem("trim", kind: .video, derivativeKind: MediaItemRecord.videoTrimDerivativeKind, sourceMediaId: "vid_1"),
        // Internal support media stays out entirely.
        creationTestItem("keyframe", kind: .image, derivativeKind: MediaItemRecord.videoChainKeyframeDerivativeKind),
        creationTestItem("handoff", kind: .image, derivativeKind: MediaItemRecord.videoChainHandoffFrameDerivativeKind),
        // Plain imports are not creations.
        creationTestItem("import", kind: .image, derivativeKind: nil)
    ]
    let groups = creationsInventory(items: items, lenses: [])
    #expect(groups.isEmpty)
}

@Test func creationsGroupRosterRendersAndCapturesAndDropEmptyGroups() {
    let items = [
        creationTestItem("render", kind: .image, derivativeKind: MediaItemRecord.rosterCharacterRenderDerivativeKind),
        creationTestItem("sheet", kind: .image, derivativeKind: MediaItemRecord.rosterCompositeSheetDerivativeKind),
        creationTestItem("chat", kind: .image, derivativeKind: MediaItemRecord.chatAttachmentDerivativeKind)
    ]
    let groups = creationsInventory(items: items, lenses: [])
    #expect(groups.map(\.kind) == [.rosterRenders, .captures])
    #expect(groupRefIds(groups, .rosterRenders) == ["media_render", "media_sheet"])
    #expect(groupRefIds(groups, .captures) == ["media_chat"])
}

@Test func creationsSkipUnreadyAndDisabledTakes() {
    var pending = creationTestTake("take_pending", path: "/tmp/p.png")
    pending.status = "rendering"
    var disabled = creationTestTake("take_disabled", path: "/tmp/d.png")
    disabled.disabled = true
    let ready = creationTestTake("take_ready", path: "/tmp/r.png")
    let lens = ProjectLens(lensId: "lens_1", heroImages: [pending, disabled, ready])
    let groups = creationsInventory(items: [], lenses: [lens])
    #expect(groupRefIds(groups, .frames) == ["take_take_ready"])
}

@Test func creationsInventoryGroupsMediaRenders() {
    let items = [
        creationTestItem("restyled", kind: .image, derivativeKind: MediaItemRecord.mediaRestyleDerivativeKind, sourceMediaId: "img_src"),
        creationTestItem("motion", kind: .video, derivativeKind: MediaItemRecord.mediaMotionDerivativeKind, sourceMediaId: "img_src"),
        creationTestItem("look", kind: .video, derivativeKind: MediaItemRecord.clipLookDerivativeKind, sourceMediaId: "vid_src"),
        // Unknown kinds still drop.
        creationTestItem("mystery", kind: .video, derivativeKind: "future_kind")
    ]
    let groups = creationsInventory(items: items, lenses: [])
    #expect(groupRefIds(groups, .mediaRenders) == ["media_restyled", "media_motion"])
    // Existing buckets unchanged: the clip look stays a Shot Artifact.
    #expect(groupRefIds(groups, .shotArtifacts) == ["media_look"])
    #expect(groups.allSatisfy { group in !group.refs.contains { $0.id == "media_mystery" } })
}

@Test func creationsExcludeAdoptedPhotos() {
    // An adopted photo is a source, not a creation — Story Inputs list it.
    var adopted = creationTestTake("take_photo", path: "/tmp/harbor.jpg")
    adopted.provider = ProjectLensHeroImage.adoptedPhotoProvider
    adopted.model = ProjectLensHeroImage.adoptedPhotoModel
    let render = creationTestTake("take_render", path: "/tmp/render.png")
    let groups = creationsInventory(
        items: [],
        lenses: [ProjectLens(lensId: "lens_1", heroImages: [adopted, render])]
    )
    #expect(groupRefIds(groups, .frames) == ["take_take_render"])
}
