import Foundation
import Testing
@testable import LitScenes

// MARK: Dive spec

@Test func excursionDiveSpecCommitsTheHoverReticle() {
    let imageSize = CGSize(width: 1920, height: 1080)
    let spec = try! #require(excursionDiveSpec(
        clickPoint: CGPoint(x: 0.5, y: 0.5),
        imagePixelSize: imageSize,
        parentImageId: "f1"
    ))
    #expect(spec.mode == LensReframeSpec.zoomMode)
    #expect(spec.rotationDegrees == 0)
    #expect(spec.parentImageId == "f1")
    // Base reticle on a 1920×1080 frame: 160px wide, 16:9 → 90px tall.
    #expect(abs(spec.normalizedWidth - 160.0 / 1920.0) < 0.0001)
    #expect(abs(spec.normalizedHeight - 90.0 / 1080.0) < 0.0001)
    #expect(abs(spec.centerX - 0.5) < 0.0001)
    #expect(abs(spec.centerY - 0.5) < 0.0001)
}

@Test func excursionDiveSpecPinsEdgeClicksInsideTheFrame() {
    let imageSize = CGSize(width: 1920, height: 1080)
    let spec = try! #require(excursionDiveSpec(
        clickPoint: CGPoint(x: 0, y: 0),
        imagePixelSize: imageSize,
        parentImageId: "f1"
    ))
    // The reticle slides fully inside: its center is half the selection in
    // from the corner, exactly the pinned-center law the modal uses.
    #expect(abs(spec.centerX - spec.normalizedWidth / 2) < 0.0001)
    #expect(abs(spec.centerY - spec.normalizedHeight / 2) < 0.0001)
}

@Test func excursionDiveSpecRefusesDegenerateImages() {
    #expect(excursionDiveSpec(
        clickPoint: CGPoint(x: 0.5, y: 0.5),
        imagePixelSize: .zero,
        parentImageId: "f1"
    ) == nil)
}

// MARK: Camera transform + fitted-frame geometry

@Test func excursionCameraTransformIsIdentityAtFullFrame() {
    let transform = excursionCameraTransform(
        visibleRect: CGRect(x: 0, y: 0, width: 1, height: 1),
        fittedImageSize: CGSize(width: 1280, height: 720)
    )
    #expect(transform.scale == 1)
    #expect(transform.offset == .zero)
}

@Test func excursionCameraTransformCentersTheVisibleRect() {
    let fitted = CGSize(width: 1280, height: 720)
    let rect = CGRect(x: 0.3, y: 0.2, width: 0.25, height: 0.25)
    let transform = excursionCameraTransform(visibleRect: rect, fittedImageSize: fitted)
    #expect(transform.scale == 4)
    #expect(abs(transform.offset.width - (0.5 - rect.midX) * fitted.width * 4) < 0.0001)
    #expect(abs(transform.offset.height - (0.5 - rect.midY) * fitted.height * 4) < 0.0001)
}

@Test func excursionFittedFrameLetterboxesAndCenters() {
    // A 16:9 image inside a square container: full width, centered vertically.
    let frame = excursionFittedFrame(
        imagePixelSize: CGSize(width: 1920, height: 1080),
        containerSize: CGSize(width: 1000, height: 1000)
    )
    #expect(abs(frame.minX) < 0.0001)
    #expect(abs(frame.width - 1000) < 0.0001)
    #expect(abs(frame.height - 562.5) < 0.0001)
    #expect(abs(frame.midY - 500) < 0.0001)

    #expect(excursionFittedFrame(imagePixelSize: .zero, containerSize: CGSize(width: 10, height: 10)) == .zero)
}

@Test func excursionNormalizedPointMapsInsideAndRefusesLetterbox() {
    let fitted = CGRect(x: 0, y: 218.75, width: 1000, height: 562.5)
    let inside = try! #require(excursionNormalizedPoint(
        viewPoint: CGPoint(x: 500, y: 500), fittedFrame: fitted
    ))
    #expect(abs(inside.x - 0.5) < 0.0001)
    #expect(abs(inside.y - 0.5) < 0.0001)
    // A letterbox click is a pull-back, never a dive.
    #expect(excursionNormalizedPoint(viewPoint: CGPoint(x: 500, y: 100), fittedFrame: fitted) == nil)
}

// MARK: Material honesty

private func excursionHero(_ id: String, status: String, imagePath: String = "", errorMessage: String = "") -> ProjectLensHeroImage {
    var image = ProjectLensHeroImage(imageId: id, status: status)
    image.imagePath = imagePath
    image.errorMessage = errorMessage
    return image
}

@Test func excursionNodeMaterialIsHonest() {
    let lookup = [
        "generating": excursionHero("generating", status: "generating"),
        "ready": excursionHero("ready", status: "ready", imagePath: "/tmp/child.png"),
        "readyGone": excursionHero("readyGone", status: "ready", imagePath: "/tmp/missing.png"),
        "failed": excursionHero("failed", status: "failed", errorMessage: "Provider refused"),
        "failedQuiet": excursionHero("failedQuiet", status: "failed")
    ]
    let onDisk: (String) -> Bool = { $0 == "/tmp/child.png" }

    // No child reported yet, unknown child, generating child, and a ready
    // child whose file vanished all HOLD on the real parent crop.
    #expect(excursionNodeMaterial(childImageId: "", frameLookup: lookup, fileExists: onDisk) == .parentCrop)
    #expect(excursionNodeMaterial(childImageId: "unknown", frameLookup: lookup, fileExists: onDisk) == .parentCrop)
    #expect(excursionNodeMaterial(childImageId: "generating", frameLookup: lookup, fileExists: onDisk) == .parentCrop)
    #expect(excursionNodeMaterial(childImageId: "readyGone", frameLookup: lookup, fileExists: onDisk) == .parentCrop)

    #expect(excursionNodeMaterial(childImageId: "ready", frameLookup: lookup, fileExists: onDisk)
        == .childStill(path: "/tmp/child.png"))
    #expect(excursionNodeMaterial(childImageId: "failed", frameLookup: lookup, fileExists: onDisk)
        == .failed(message: "Provider refused"))
    #expect(excursionNodeMaterial(childImageId: "failedQuiet", frameLookup: lookup, fileExists: onDisk)
        == .failed(message: "The reframe render failed"))
}

// MARK: Puzzle pieces

private func excursionReframeChild(
    _ id: String,
    parentImageId: String,
    mode: String = LensReframeSpec.zoomMode,
    status: String = "ready",
    imagePath: String? = nil,
    imageIndex: Int = 0,
    centerX: Double = 0.5,
    centerY: Double = 0.5,
    width: Double = 0.1,
    height: Double = 0.1,
    rotationDegrees: Double = 0
) -> ProjectLensHeroImage {
    var image = ProjectLensHeroImage(imageId: id, status: status)
    image.imagePath = imagePath ?? (status == "ready" ? "/tmp/\(id).png" : "")
    image.imageIndex = imageIndex
    var spec = LensReframeSpec(
        mode: mode, centerX: centerX, centerY: centerY,
        normalizedWidth: width, normalizedHeight: height
    )
    spec.parentImageId = parentImageId
    spec.rotationDegrees = rotationDegrees
    image.reframe = spec
    return image
}

@Test func excursionPuzzlePiecesAreReadyZoomChildrenOnly() {
    let lookup: [String: ProjectLensHeroImage] = [
        "plain": excursionHero("plain", status: "ready", imagePath: "/tmp/plain.png"),
        "zoomA": excursionReframeChild("zoomA", parentImageId: "f1", imageIndex: 2, centerX: 0.3, centerY: 0.4, rotationDegrees: 12),
        "zoomB": excursionReframeChild("zoomB", parentImageId: "f1", imageIndex: 5, centerX: 0.7, centerY: 0.6),
        "otherParent": excursionReframeChild("otherParent", parentImageId: "f9"),
        "wide": excursionReframeChild("wide", parentImageId: "f1", mode: LensReframeSpec.zoomOutMode),
        "pov": excursionReframeChild("pov", parentImageId: "f1", mode: LensReframeSpec.viewpointMode),
        "cooking": excursionReframeChild("cooking", parentImageId: "f1", status: "generating"),
        "gone": excursionReframeChild("gone", parentImageId: "f1", imagePath: "/tmp/vanished.png")
    ]
    let onDisk: (String) -> Bool = { $0 != "/tmp/vanished.png" }

    let pieces = excursionPuzzlePieces(parentImageId: "f1", frameLookup: lookup, fileExists: onDisk)
    // Only the ready on-disk ZOOM children of f1, oldest-first by imageIndex.
    #expect(pieces.map(\.imageId) == ["zoomA", "zoomB"])
    #expect(abs(pieces[0].rect.midX - 0.3) < 0.0001)
    #expect(abs(pieces[0].rect.midY - 0.4) < 0.0001)
    #expect(pieces[0].rotationDegrees == 12)

    #expect(excursionPuzzlePieces(parentImageId: "", frameLookup: lookup, fileExists: onDisk).isEmpty)
}

@Test func excursionPuzzlePieceHitPrefersTopmost() {
    let pieces = [
        ExcursionPuzzlePiece(imageId: "older", imagePath: "/tmp/a.png",
                             rect: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3), rotationDegrees: 0),
        ExcursionPuzzlePiece(imageId: "newer", imagePath: "/tmp/b.png",
                             rect: CGRect(x: 0.4, y: 0.4, width: 0.3, height: 0.3), rotationDegrees: 0)
    ]
    // Overlap region: draw order = array order, so the LAST hit wins.
    #expect(excursionPuzzlePieceHit(point: CGPoint(x: 0.45, y: 0.45), pieces: pieces)?.imageId == "newer")
    #expect(excursionPuzzlePieceHit(point: CGPoint(x: 0.25, y: 0.25), pieces: pieces)?.imageId == "older")
    #expect(excursionPuzzlePieceHit(point: CGPoint(x: 0.9, y: 0.9), pieces: pieces) == nil)
}

@Test func excursionExistingPlacementPrefersReturnAdjacency() {
    var shot = ProjectShot(shotId: "shot_p", name: "P", createdAt: "t0", updatedAt: "t0")
    shot.entries = [
        ShotFrameEntry(entryId: "e0", frameImageId: "f1"),
        // A lone child placement (no return beside it)…
        ShotFrameEntry(entryId: "e1", frameImageId: "c1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f2"),
        // …and the true excursion pair further along.
        ShotFrameEntry(entryId: "e3", frameImageId: "c1"),
        ShotFrameEntry(entryId: "e4", frameImageId: "f1")
    ]
    let placed = try! #require(excursionExistingPlacement(cut: shot, childImageId: "c1", parentImageId: "f1"))
    #expect(placed.childEntryId == "e3")
    #expect(placed.returnEntryId == "e4")

    // No adjacency anywhere → any placement anchors, with no return.
    let loneOnly = try! #require(excursionExistingPlacement(cut: shot, childImageId: "c1", parentImageId: "f9"))
    #expect(loneOnly.childEntryId == "e1")
    #expect(loneOnly.returnEntryId.isEmpty)

    #expect(excursionExistingPlacement(cut: shot, childImageId: "never", parentImageId: "f1") == nil)
    #expect(excursionExistingPlacement(cut: nil, childImageId: "c1", parentImageId: "f1") == nil)
}

// MARK: Transition media

@Test func excursionTransitionMediaPrefersRealSegmentClips() {
    var shot = ProjectShot(shotId: "shot_x", name: "X", createdAt: "t0", updatedAt: "t0")
    shot.entries = [
        ShotFrameEntry(entryId: "e0", frameImageId: "f1"),
        ShotFrameEntry(entryId: "e1", frameImageId: "c1"),
        ShotFrameEntry(entryId: "e2", frameImageId: "f1")
    ]
    var artifact = ShotRenderArtifact(versionId: "v1", versionNumber: 1, status: "ready", videoPath: "/tmp/full.mp4")
    var placementClip = ShotRenderSegmentClip()
    placementClip.startFrameImageId = "f1"
    placementClip.endFrameImageId = "c1"
    placementClip.placementStartEntryId = "e0"
    placementClip.placementEndEntryId = "e1"
    placementClip.clipPath = "/tmp/push_in.mp4"
    var legacyClip = ShotRenderSegmentClip()
    legacyClip.startFrameImageId = "c1"
    legacyClip.endFrameImageId = "f1"
    legacyClip.clipPath = "/tmp/pull_out.mp4"
    artifact.segmentClips = [placementClip, legacyClip]
    shot = shot.upsertingRenderVersion(artifact, activate: true, now: "t1")
    let onDisk: (String) -> Bool = { ["/tmp/push_in.mp4", "/tmp/pull_out.mp4"].contains($0) }

    // Placement-keyed clip resolves for its exact pair.
    #expect(excursionTransitionMedia(
        cut: shot, startEntryId: "e0", endEntryId: "e1",
        startImageId: "f1", endImageId: "c1", fileExists: onDisk
    ) == .segmentVideo(path: "/tmp/push_in.mp4"))
    // Legacy image-keyed clip still resolves.
    #expect(excursionTransitionMedia(
        cut: shot, startEntryId: "e1", endEntryId: "e2",
        startImageId: "c1", endImageId: "f1", fileExists: onDisk
    ) == .segmentVideo(path: "/tmp/pull_out.mp4"))
    // No cut, no matching clip, or a stale file → geometric.
    #expect(excursionTransitionMedia(
        cut: nil, startEntryId: "e0", endEntryId: "e1",
        startImageId: "f1", endImageId: "c1", fileExists: onDisk
    ) == .geometric)
    #expect(excursionTransitionMedia(
        cut: shot, startEntryId: "e9", endEntryId: "e8",
        startImageId: "f9", endImageId: "f8", fileExists: onDisk
    ) == .geometric)
    #expect(excursionTransitionMedia(
        cut: shot, startEntryId: "e0", endEntryId: "e1",
        startImageId: "f1", endImageId: "c1", fileExists: { _ in false }
    ) == .geometric)
}
