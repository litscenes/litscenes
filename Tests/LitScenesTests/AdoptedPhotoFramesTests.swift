import Foundation
import Testing
@testable import LitScenes

// MARK: - Fixtures

private func photoRow(
    _ id: String,
    mediaId: String,
    generatedAt: String = "2026-08-01T00:00:00Z",
    disabled: Bool = false,
    provider: String = ProjectLensHeroImage.adoptedPhotoProvider,
    model: String = ProjectLensHeroImage.adoptedPhotoModel
) -> ProjectLensHeroImage {
    var row = ProjectLensHeroImage(
        imageId: id,
        label: "Harbor \(id)",
        provider: provider,
        model: model,
        imagePath: "/tmp/\(id).jpg",
        status: "ready",
        sourceDependencies: [
            LensRenderSourceDependency(
                dependencyId: "",
                kind: "media_item",
                sourceId: mediaId,
                role: ProjectLensHeroImage.sourcePhotoDependencyRole
            )
        ],
        disabled: disabled
    )
    row.generatedAt = generatedAt
    return row
}

private func renderRow(
    _ id: String,
    generatedAt: String = "2026-08-01T00:00:00Z",
    imageIndex: Int = 0,
    status: String = "ready",
    inheritedFrom mediaId: String? = nil
) -> ProjectLensHeroImage {
    var row = ProjectLensHeroImage(
        imageId: id,
        imageIndex: imageIndex,
        label: "Quince \(id)",
        imagePath: "/tmp/\(id).png",
        status: status,
        sourceDependencies: mediaId.map {
            [LensRenderSourceDependency(dependencyId: "", kind: "media_item", sourceId: $0, role: "source_photo")]
        } ?? []
    )
    row.generatedAt = generatedAt
    return row
}

private func media(_ id: String, kind: MediaKind, modifiedAt: String) -> MediaItemRecord {
    let ext = kind == .video ? "mp4" : "jpg"
    return MediaItemRecord(
        mediaId: id,
        sourceId: "source_test",
        kind: kind,
        filename: "\(id).\(ext)",
        path: "/tmp/\(id).\(ext)",
        relativePath: "\(id).\(ext)",
        byteCount: 1,
        modifiedAt: modifiedAt,
        width: 1920,
        height: 1080,
        durationSeconds: kind == .video ? 8 : nil,
        nominalFrameRate: kind == .video ? 24 : nil,
        thumbnailPath: "",
        videoStripPath: nil,
        scannedAt: modifiedAt,
        scanError: nil
    )
}

private func photo(_ id: String, modifiedAt: String = "2026-08-02T00:00:00Z") -> MediaItemRecord {
    media(id, kind: .image, modifiedAt: modifiedAt)
}

private func video(_ id: String, modifiedAt: String = "2026-08-01T00:00:00Z") -> MediaItemRecord {
    media(id, kind: .video, modifiedAt: modifiedAt)
}

// MARK: - The predicate

@Test func adoptedPhotoPredicateKeysOnProviderAndModelNotProvenance() {
    let adopted = photoRow("fAdopt", mediaId: "pHarbor")
    #expect(adopted.isAdoptedPhoto)
    #expect(adopted.adoptedPhotoMediaId == "pHarbor")

    // A restyle child inherits the dependency and is still a render.
    let child = renderRow("fChild", inheritedFrom: "pHarbor")
    #expect(!child.isAdoptedPhoto)
    #expect(child.adoptedPhotoMediaId == nil)

    // Provider/model tolerate case and whitespace; a missing dependency yields no media id.
    let loose = photoRow("fLoose", mediaId: "", provider: " Media ", model: "Original-Photo")
    #expect(loose.isAdoptedPhoto)
    #expect(loose.adoptedPhotoMediaId == nil)

    // Half the stamp is not adoption.
    #expect(!photoRow("fHalf", mediaId: "pHarbor", model: "gpt-image-2").isAdoptedPhoto)
}

// MARK: - The inventory law

@Test func poolInputsSubstituteAdoptedPhotosInTheirOwnSlot() {
    let adoptedOld = photoRow("fAdoptOld", mediaId: "pOld", generatedAt: "2026-08-05T00:00:00Z")
    let render = renderRow("fRender", generatedAt: "2026-08-02T00:00:00Z")
    let displayed = [render, adoptedOld]
    let projectWide = displayed + [renderRow("fOther", generatedAt: "2026-07-30T00:00:00Z")]
    let items = [
        photo("pNew", modifiedAt: "2026-08-03T00:00:00Z"),
        photo("pOld", modifiedAt: "2026-08-01T00:00:00Z"),
        video("vClip")
    ]
    let inputs = scenesV2PoolInputs(displayedFrames: displayed, projectWideFrames: projectWide, items: items)
    // The adopted photo keeps its second-by-date slot as a FRAME input and
    // leaves the frames group; the newest photo stays a media input.
    #expect(inputs.map(\.assetKey) == [
        "clip:pNew",
        "frame:fAdoptOld",
        "frame:fRender",
        "frame:fOther",
        "clip:vClip"
    ])
    #expect(inputs[1].inputId == "source_frame_fAdoptOld")
    #expect(inputs[1].addedAt == "2026-08-01T00:00:00Z")
    #expect(Set(inputs.map(\.inputId)).count == inputs.count)
}

@Test func poolInputsFindAdoptionOnNonDisplayedRowsAndEmitOneTile() {
    // Adopted on an older media version: absent from the displayed frames,
    // present project-wide. The shared V1 law would show PHOTO + FRAME here.
    let adopted = photoRow("fAdopt", mediaId: "pHarbor")
    let displayed = [renderRow("fRender")]
    let inputs = scenesV2PoolInputs(
        displayedFrames: displayed,
        projectWideFrames: displayed + [adopted],
        items: [photo("pHarbor")]
    )
    #expect(inputs.map(\.assetKey) == ["frame:fAdopt", "frame:fRender"])
}

@Test func poolInputsIgnoreDisabledAdoptionsAndDropDisabledRows() {
    let disabled = photoRow("fGone", mediaId: "pHarbor", disabled: true)
    let inputs = scenesV2PoolInputs(
        displayedFrames: [disabled, renderRow("fRender")],
        projectWideFrames: [disabled, renderRow("fRender")],
        items: [photo("pHarbor")]
    )
    // The photo is back to a media input (the next open re-adopts); the
    // disabled row is not inventory anywhere.
    #expect(inputs.map(\.assetKey) == ["clip:pHarbor", "frame:fRender"])
}

@Test func poolInputsKeepOrphanAdoptedRowsInTheFramesGroup() {
    // Adopted from a kind the v2 hygiene filter keeps out of `items` (or a
    // photo since removed): the row stays placeable in its usual place.
    let orphan = photoRow("fOrphan", mediaId: "charsrc_quince", generatedAt: "2026-08-04T00:00:00Z")
    let displayed = [renderRow("fRender", generatedAt: "2026-08-02T00:00:00Z"), orphan]
    let inputs = scenesV2PoolInputs(displayedFrames: displayed, projectWideFrames: displayed, items: [photo("pOther")])
    #expect(inputs.map(\.assetKey) == ["clip:pOther", "frame:fRender", "frame:fOrphan"])
}

@Test func poolInputsNeverSubstituteRestyleChildren() {
    let adopted = photoRow("fAdopt", mediaId: "pHarbor")
    let child = renderRow("fChild", generatedAt: "2026-08-09T00:00:00Z", inheritedFrom: "pHarbor")
    let lonelyChild = renderRow("fLonely", generatedAt: "2026-08-08T00:00:00Z", inheritedFrom: "pQuiet")
    let displayed = [child, adopted, lonelyChild]
    let inputs = scenesV2PoolInputs(
        displayedFrames: displayed,
        projectWideFrames: displayed,
        items: [photo("pHarbor", modifiedAt: "2026-08-03T00:00:00Z"), photo("pQuiet", modifiedAt: "2026-08-01T00:00:00Z")]
    )
    // pHarbor substitutes its true adoption; pQuiet has none and stays a media
    // input; both children remain renders in the frames group.
    #expect(inputs.map(\.assetKey) == ["frame:fAdopt", "clip:pQuiet", "frame:fChild", "frame:fLonely"])
}

@Test func poolInputsOwnEveryAdoptionOfASubstitutedPhoto() {
    // A legacy multi-lens project adopted the same photo twice: one tile.
    let first = photoRow("fAdoptA", mediaId: "pHarbor", generatedAt: "2026-08-02T00:00:00Z")
    let second = photoRow("fAdoptB", mediaId: "pHarbor", generatedAt: "2026-08-03T00:00:00Z")
    let inputs = scenesV2PoolInputs(
        displayedFrames: [first],
        projectWideFrames: [first, second],
        items: [photo("pHarbor")]
    )
    #expect(inputs.map(\.assetKey) == ["frame:fAdoptA"])
}

@Test func poolInputsDeduplicateDisplayedRowsRepeatedProjectWide() {
    let render = renderRow("fRender")
    let inputs = scenesV2PoolInputs(displayedFrames: [render], projectWideFrames: [render, render], items: [])
    #expect(inputs.map(\.assetKey) == ["frame:fRender"])
}

@Test func unusedFilterIsHonestForAdoptedPhotos() throws {
    let adopted = photoRow("fAdopt", mediaId: "pHarbor")
    let inputs = scenesV2PoolInputs(
        displayedFrames: [adopted],
        projectWideFrames: [adopted],
        items: [photo("pHarbor", modifiedAt: "2026-08-03T00:00:00Z"), photo("pLoose", modifiedAt: "2026-08-01T00:00:00Z")]
    )
    let usage = ScenesV2PoolUsage(usedFrameIds: ["fAdopt"], usedClipIds: [], boundaryFrameIds: ["fAdopt"])
    let placed = try #require(inputs.first { $0.assetKey == "frame:fAdopt" })
    let loose = try #require(inputs.first { $0.assetKey == "clip:pLoose" })
    #expect(!poolInputMatchesFilter(placed, filter: .unused, usage: usage))
    #expect(poolInputMatchesFilter(placed, filter: .startEnd, usage: usage))
    #expect(poolInputMatchesFilter(loose, filter: .unused, usage: usage))
    #expect(!poolInputMatchesFilter(loose, filter: .startEnd, usage: usage))
}

// MARK: - Guided stage + captions

@Test func renderedFramesExcludeAdoptedPhotosAndUnreadyRows() {
    let frames = [
        renderRow("fReady"),
        photoRow("fAdopt", mediaId: "pHarbor"),
        renderRow("fQueued", status: "queued"),
        renderRow("fPathless", status: "ready").with { $0.imagePath = "" }
    ]
    #expect(scenesV2RenderedFrames(frames).map(\.imageId) == ["fReady"])
}

@Test func photoCaptionIsTheFilenameStem() {
    #expect(scenesV2PhotoCaption(filename: "IMG_7898.JPG") == "IMG_7898")
    #expect(scenesV2PhotoCaption(filename: " harbor-dawn.heic ") == "harbor-dawn")
    #expect(scenesV2PhotoCaption(filename: "noext") == "noext")
    #expect(scenesV2PhotoCaption(filename: "   ") == "Photo")
}

private extension ProjectLensHeroImage {
    func with(_ edit: (inout ProjectLensHeroImage) -> Void) -> ProjectLensHeroImage {
        var copy = self
        edit(&copy)
        return copy
    }
}
