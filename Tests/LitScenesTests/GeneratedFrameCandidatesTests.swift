import Foundation
import Testing
@testable import LitScenes

private func candidateTestTake(
    _ imageId: String,
    path: String? = nil,
    label: String = "",
    status: String = "ready",
    disabled: Bool = false
) -> ProjectLensHeroImage {
    var take = ProjectLensHeroImage(imageId: imageId)
    take.status = status
    take.imagePath = path ?? "/tmp/\(imageId).png"
    take.label = label
    take.disabled = disabled
    return take
}

private func candidateTestItem(
    _ mediaId: String,
    derivativeKind: String? = MediaItemRecord.frameReferenceDerivativeKind,
    path: String? = nil,
    sourceMediaId: String? = nil
) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: mediaId,
        sourceId: MediaItemRecord.generatedMediaSourceId,
        kind: .image,
        filename: "\(mediaId).png",
        path: path ?? "/tmp/\(mediaId).png",
        relativePath: mediaId,
        byteCount: 1,
        modifiedAt: "",
        width: 100,
        height: 100,
        durationSeconds: nil,
        nominalFrameRate: nil,
        thumbnailPath: "",
        videoStripPath: nil,
        scannedAt: "",
        scanError: nil,
        derivativeKind: derivativeKind,
        sourceMediaId: sourceMediaId
    )
}

@Test func candidatesDedupeAcrossLensesAndSkipNonReadyTakes() {
    let shared = candidateTestTake("take_shared")
    var titled = LensBody.empty()
    titled.title = "Harbor Night"
    let lenses = [
        ProjectLens(lensId: "lens_a1b2", body: titled, heroImages: [
            shared,
            candidateTestTake("take_generating", status: "generating"),
            candidateTestTake("take_disabled", disabled: true),
            candidateTestTake("take_pathless", path: "")
        ]),
        ProjectLens(lensId: "lens_c3d4", heroImages: [
            shared,
            candidateTestTake("take_b", label: "Alley chase")
        ])
    ]
    let candidates = generatedFrameReferenceCandidates(lenses: lenses, items: [])
    #expect(candidates.map(\.id) == ["take_shared", "take_b"])
    #expect(candidates[0].lensTitle == "Harbor Night")
    // Untitled lens falls back to the id-suffix scene name (MediaUseMenu idiom).
    #expect(candidates[1].lensTitle == "Scene c3d4")
    #expect(candidates[0].displayLabel == "Generated frame")
    #expect(candidates[1].displayLabel == "Alley chase")
    #expect(candidates[1].caption == "Scene c3d4 · Alley chase")
}

@Test func candidatesResolveAdoptedTwinsBySourceIdThenPath() {
    let lens = ProjectLens(lensId: "lens_a1b2", heroImages: [
        candidateTestTake("take_1"),
        candidateTestTake("take_2", path: "/tmp/shared_path.png"),
        candidateTestTake("take_3")
    ])
    let items = [
        candidateTestItem("twin_by_source", sourceMediaId: "take_1"),
        // Legacy adoption without sourceMediaId — resolved by exact file path.
        candidateTestItem("twin_by_path", path: "/tmp/shared_path.png"),
        // Same sourceMediaId but not a frame_reference — never a twin.
        candidateTestItem("not_a_twin", derivativeKind: nil, sourceMediaId: "take_3")
    ]
    let candidates = generatedFrameReferenceCandidates(lenses: [lens], items: items)
    #expect(candidates.map(\.adoptedMediaId) == ["twin_by_source", "twin_by_path", nil])
    // Adopted takes share their twin's selection identity; unadopted takes get
    // a token media ids can't collide with.
    #expect(candidates.map(\.selectionToken) == ["twin_by_source", "twin_by_path", "take:take_3"])
}
