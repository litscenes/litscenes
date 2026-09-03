import CoreGraphics
import Foundation

// EXCURSION MODE's pure layer: dive-stack state and the geometry/lookup laws
// the full-screen surface leans on. Nothing here touches SwiftUI or the
// engine — every function is unit-testable with plain values.

/// Workbench-level launch handle: the cut placement the mode opened on (the
/// analog of the frame modal's cut navigation context).
struct ExcursionLaunchRequest: Identifiable, Equatable {
    var cutId: String
    var entryId: String
    var rootImageId: String
    var id: String { "\(cutId)_\(entryId)" }
}

/// One committed dive: the reticle spec that got here plus the minted child
/// identity, back-filled when the engine reports placement.
struct ExcursionDiveNode: Identifiable, Equatable {
    let nodeId: String
    var spec: LensReframeSpec
    var parentImageId: String
    var parentEntryId: String
    var childImageId: String = ""
    var childEntryId: String = ""
    var returnEntryId: String = ""
    /// A REVISIT of an existing rendered reframe (a puzzle-piece click):
    /// nothing was minted or inserted — the dive is view-only unless the
    /// child already has a cut placement to anchor deeper dives.
    var isRevisit = false
    var id: String { nodeId }
}

/// An existing rendered reframe child worn by its parent as an inlaid puzzle
/// piece at the exact region it re-rendered.
struct ExcursionPuzzlePiece: Identifiable, Equatable {
    var imageId: String
    var imagePath: String
    /// Normalized crop rect on the parent (the spec's unrotated footprint).
    var rect: CGRect
    /// The reticle tilt the crop was extracted at; the piece is drawn
    /// re-tilted so it sits back in its true footprint.
    var rotationDegrees: Double
    var id: String { imageId }
}

/// Every ready, on-disk ZOOM child of a frame, as puzzle pieces. Zoom-out and
/// viewpoint children have no in-parent footprint and stay off the board.
/// Sorted oldest-first so newer overlapping pieces draw (and hit-test) on top.
func excursionPuzzlePieces(
    parentImageId: String,
    frameLookup: [String: ProjectLensHeroImage],
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> [ExcursionPuzzlePiece] {
    guard !parentImageId.isEmpty else { return [] }
    return frameLookup.values
        .filter { frame in
            guard let spec = frame.reframe else { return false }
            return spec.parentImageId == parentImageId
                && spec.isZoom
                && spec.normalizedWidth > 0
                && spec.normalizedHeight > 0
                && frame.status == "ready"
                && !frame.imagePath.trimmed.isEmpty
                && fileExists(frame.imagePath)
        }
        .sorted { ($0.imageIndex, $0.imageId) < ($1.imageIndex, $1.imageId) }
        .compactMap { frame in
            guard let spec = frame.reframe else { return nil }
            return ExcursionPuzzlePiece(
                imageId: frame.imageId,
                imagePath: frame.imagePath,
                rect: CGRect(
                    x: spec.centerX - spec.normalizedWidth / 2,
                    y: spec.centerY - spec.normalizedHeight / 2,
                    width: spec.normalizedWidth,
                    height: spec.normalizedHeight
                ),
                rotationDegrees: spec.rotationDegrees
            )
        }
}

/// The topmost piece under a normalized point (draw order = array order, so
/// the last hit wins), or nil when the click should mint a NEW dive.
func excursionPuzzlePieceHit(
    point: CGPoint,
    pieces: [ExcursionPuzzlePiece]
) -> ExcursionPuzzlePiece? {
    pieces.last { $0.rect.contains(point) }
}

/// A revisited child's existing cut placement, best-effort: prefer a
/// [child, parent-return] adjacency (its pull-out segment clip and razor-true
/// return exist), fall back to any frame placement of the child (anchors
/// deeper dives), nil when the child was never placed in this cut.
func excursionExistingPlacement(
    cut: ProjectShot?,
    childImageId: String,
    parentImageId: String
) -> (childEntryId: String, returnEntryId: String)? {
    guard let cut, !childImageId.isEmpty else { return nil }
    for (index, entry) in cut.entries.enumerated()
    where entry.frameImageId == childImageId && !entry.isClip && !entry.isAIExtension {
        guard cut.entries.indices.contains(index + 1) else { continue }
        let next = cut.entries[index + 1]
        if next.frameImageId == parentImageId, !next.isClip, !next.isAIExtension {
            return (entry.entryId, next.entryId)
        }
    }
    if let entry = cut.entries.first(where: {
        $0.frameImageId == childImageId && !$0.isClip && !$0.isAIExtension
    }) {
        return (entry.entryId, "")
    }
    return nil
}

/// What material the surface may honestly show for a settled dive right now.
/// `parentCrop` is the magnified REAL parent still (the child is not ready);
/// it always carries an honest status badge, never a faked frame.
enum ExcursionNodeMaterial: Equatable {
    case parentCrop
    case childStill(path: String)
    case failed(message: String)
}

/// How a push-in / pull-out transition may be performed right now: an
/// animated camera move over the real still, or the actual rendered segment
/// clip once one exists on disk.
enum ExcursionTransitionMedia: Equatable {
    case geometric
    case segmentVideo(path: String)
}

/// The v1 dive spec from a click: Zoom In, base reticle edge, level. Wraps
/// the reticle law so the committed selection is exactly the hover outline —
/// including the pinned center near edges (the reticle slides inside the
/// frame; the spec must describe where the selection actually sits).
func excursionDiveSpec(
    clickPoint: CGPoint,
    imagePixelSize: CGSize,
    edgePixels: CGFloat = LensReframeMetrics.reticleEdgePixels,
    parentImageId: String
) -> LensReframeSpec? {
    let rect = lensReframeFocusRect(
        center: clickPoint,
        imagePixelSize: imagePixelSize,
        edgePixels: edgePixels,
        rotationDegrees: 0
    )
    guard !rect.isEmpty else { return nil }
    return LensReframeSpec(
        mode: LensReframeSpec.zoomMode,
        centerX: rect.midX,
        centerY: rect.midY,
        normalizedWidth: rect.width,
        normalizedHeight: rect.height,
        parentImageId: parentImageId
    ).normalized()
}

/// The camera transform that makes `visibleRect` (normalized, top-left
/// origin) fill a fitted image view: uniform scale (16:9 crop of a 16:9
/// frame) plus a center-anchored offset in view points.
func excursionCameraTransform(
    visibleRect: CGRect,
    fittedImageSize: CGSize
) -> (scale: CGFloat, offset: CGSize) {
    guard visibleRect.width > 0, visibleRect.height > 0 else { return (1, .zero) }
    let scale = 1 / visibleRect.width
    return (scale, CGSize(
        width: (0.5 - visibleRect.midX) * fittedImageSize.width * scale,
        height: (0.5 - visibleRect.midY) * fittedImageSize.height * scale
    ))
}

/// The aspect-fit frame of an image inside a container, centered. Letterbox
/// margins outside this rect are background (and the pull-back click target).
func excursionFittedFrame(imagePixelSize: CGSize, containerSize: CGSize) -> CGRect {
    guard imagePixelSize.width > 0, imagePixelSize.height > 0,
          containerSize.width > 0, containerSize.height > 0 else { return .zero }
    let scale = min(
        containerSize.width / imagePixelSize.width,
        containerSize.height / imagePixelSize.height
    )
    let size = CGSize(width: imagePixelSize.width * scale, height: imagePixelSize.height * scale)
    return CGRect(
        x: (containerSize.width - size.width) / 2,
        y: (containerSize.height - size.height) / 2,
        width: size.width,
        height: size.height
    )
}

/// View-space point → normalized image coordinates; nil outside the fitted
/// frame (a letterbox click is a pull-back, never a dive).
func excursionNormalizedPoint(viewPoint: CGPoint, fittedFrame: CGRect) -> CGPoint? {
    guard fittedFrame.width > 0, fittedFrame.height > 0,
          fittedFrame.contains(viewPoint) else { return nil }
    return CGPoint(
        x: (viewPoint.x - fittedFrame.minX) / fittedFrame.width,
        y: (viewPoint.y - fittedFrame.minY) / fittedFrame.height
    )
}

/// Material honesty resolution: the child still only shows once it is ready
/// AND on disk (the strip's own readiness law); a failed render reports its
/// message; everything else stays the magnified real parent crop.
func excursionNodeMaterial(
    childImageId: String,
    frameLookup: [String: ProjectLensHeroImage],
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> ExcursionNodeMaterial {
    guard !childImageId.isEmpty, let child = frameLookup[childImageId] else {
        return .parentCrop
    }
    if child.status == "failed" {
        let message = child.errorMessage.trimmed
        return .failed(message: message.isEmpty ? "The reframe render failed" : message)
    }
    if child.status == "ready", !child.imagePath.isEmpty, fileExists(child.imagePath) {
        return .childStill(path: child.imagePath)
    }
    return .parentCrop
}

/// Transition media for an entry pair: the playable render version's saved
/// segment clip when it exists on disk (placement-keyed with the legacy
/// image-pair fallback), else the geometric camera move.
func excursionTransitionMedia(
    cut: ProjectShot?,
    startEntryId: String,
    endEntryId: String,
    startImageId: String,
    endImageId: String,
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> ExcursionTransitionMedia {
    guard let artifact = cut?.playableRenderVersion,
          let clip = artifact.segmentClip(
              placementStartEntryId: startEntryId,
              placementEndEntryId: endEntryId,
              forStart: startImageId,
              end: endImageId
          ),
          !clip.clipPath.trimmed.isEmpty,
          fileExists(clip.clipPath) else {
        return .geometric
    }
    return .segmentVideo(path: clip.clipPath)
}
