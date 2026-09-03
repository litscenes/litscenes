import Foundation
import Testing
@testable import LitScenes

// Engine-level pins for THE ADOPTED PHOTO LAW: the raw lookup keeps the
// deterministic row (disabled included), the placeable lookup hides a deleted
// adoption, and the next use re-enables instead of re-minting.

private struct AdoptedPhotoEngineFixture {
    let engine: LibraryEngine
    let project: ProjectRecord
    let lensId: String
    let photo: MediaItemRecord
}

private enum AdoptedPhotoFixtureError: Error {
    case missingProject
}

@MainActor
private func makeAdoptedPhotoFixture() throws -> AdoptedPhotoEngineFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_adopted_photo_\(UUID().uuidString)", isDirectory: true)
    let projectLibrary = ProjectLibrary(root: root)
    let engine = LibraryEngine(projectLibrary: projectLibrary)
    #expect(engine.createProject(named: "Adopted Photo \(UUID().uuidString.prefix(6))"))
    guard let project = engine.currentProject else { throw AdoptedPhotoFixtureError.missingProject }

    let store = ProjectContextStore(projectLibrary: projectLibrary)
    var document = ProjectLensSetDocument.bootstrap(projectId: project.projectId, now: "2026-09-01T00:00:00Z")
    var body = LensBody.empty()
    body.title = "Harbor Plan"
    document.appendVersion(
        lenses: [ProjectLens(lensId: "lens_harbor", body: body)],
        scratchDrafts: [],
        selectedLensId: "lens_harbor",
        selectedScratchId: nil,
        changeSummary: "seed",
        model: "test",
        now: "2026-09-01T00:00:01Z"
    )
    try store.saveProjectLenses(document, for: project)
    engine.selectProject(project)

    let photoURL = root.appendingPathComponent("harbor-dawn.jpg")
    try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: photoURL)
    let photo = MediaItemRecord(
        mediaId: "pHarbor",
        sourceId: "source_test",
        kind: .image,
        filename: "harbor-dawn.jpg",
        path: photoURL.path,
        relativePath: "harbor-dawn.jpg",
        byteCount: 4,
        modifiedAt: "2026-09-01T00:00:00Z",
        width: 1920,
        height: 1080,
        durationSeconds: nil,
        nominalFrameRate: nil,
        thumbnailPath: "",
        videoStripPath: nil,
        scannedAt: "2026-09-01T00:00:00Z",
        scanError: nil
    )
    return AdoptedPhotoEngineFixture(engine: engine, project: project, lensId: "lens_harbor", photo: photo)
}

@Test
@MainActor
func adoptionMintsOneStrictRowAndTheOpenGestureReturnsItSilently() throws {
    let fixture = try makeAdoptedPhotoFixture()
    let engine = fixture.engine
    #expect(engine.adoptedPhotoFrame(lensId: fixture.lensId, mediaId: "pHarbor") == nil)

    #expect(engine.addMediaImageAsFrame(fixture.photo, lensId: fixture.lensId))
    let adopted = try #require(engine.adoptedPhotoFrame(lensId: fixture.lensId, mediaId: "pHarbor"))
    #expect(adopted.isAdoptedPhoto)
    #expect(adopted.adoptedPhotoMediaId == "pHarbor")
    #expect(adopted.label == "harbor-dawn")
    #expect(adopted.status == "ready")
    #expect(FileManager.default.fileExists(atPath: adopted.imagePath))

    // The open gesture: same row, no status noise.
    let statusBefore = engine.aestheticStatus
    let opened = engine.adoptMediaImageAsFrame(mediaId: "pHarbor", lensId: fixture.lensId)
    #expect(opened?.imageId == adopted.imageId)
    #expect(engine.aestheticStatus == statusBefore)

    let rows = engine.projectLenses.lenses.first { $0.lensId == fixture.lensId }?.heroImages ?? []
    #expect(rows.filter { $0.imageId == adopted.imageId }.count == 1)
}

@Test
@MainActor
func deletedAdoptionIsNotPlaceableAndTheNextUseReEnablesIt() throws {
    let fixture = try makeAdoptedPhotoFixture()
    let engine = fixture.engine
    #expect(engine.addMediaImageAsFrame(fixture.photo, lensId: fixture.lensId))
    let adopted = try #require(engine.adoptedPhotoFrame(lensId: fixture.lensId, mediaId: "pHarbor"))

    #expect(engine.disableLensHeroImage(lensId: fixture.lensId, imageId: adopted.imageId))
    // The raw row survives, disabled; the placeable lookup hides it, so a
    // drop plans an adoption instead of placing a deleted frame.
    #expect(engine.mediaImageFrame(lensId: fixture.lensId, mediaId: "pHarbor")?.disabled == true)
    #expect(engine.adoptedPhotoFrame(lensId: fixture.lensId, mediaId: "pHarbor") == nil)
    let plan = shotMediaInsertPlan(
        media: fixture.photo,
        adoptedFrameImageId: engine.adoptedPhotoFrame(lensId: fixture.lensId, mediaId: "pHarbor")?.imageId
    )
    guard case .adoptImageAsFrame = plan else {
        Issue.record("expected the planner to adopt, got \(plan)")
        return
    }

    // Re-adoption re-enables the same deterministic row — never a twin.
    #expect(engine.addMediaImageAsFrame(fixture.photo, lensId: fixture.lensId))
    let restored = try #require(engine.adoptedPhotoFrame(lensId: fixture.lensId, mediaId: "pHarbor"))
    #expect(restored.imageId == adopted.imageId)
    #expect(!restored.disabled)
    let rows = engine.projectLenses.lenses.first { $0.lensId == fixture.lensId }?.heroImages ?? []
    #expect(rows.filter { $0.imageId == adopted.imageId }.count == 1)
    #expect(engine.aestheticStatus.hasPrefix("Restored harbor-dawn"))
}
