import Foundation
import CoreGraphics
import ImageIO
import Vision

// MARK: - Narration anchor resolution + lip-sync face preflight
//
// THE LIP-SYNC ANCHOR LAW (locked): a narration-driven (LTX)
// render is refused BEFORE any spend when its anchor frame cannot carry a
// mouth — the provider has no sync knobs, so a face the model cannot resolve
// yields ambient motion and a frozen mouth. The verdict is a pure threshold
// over a local Vision face report; detector failure fails OPEN (a broken
// detector must never block a legitimate render).

/// What the local face detector saw in the anchor frame.
struct ShotAnchorFaceReport: Equatable {
    var faceCount: Int = 0
    /// Height of the LARGEST detected face as a fraction of image height.
    var largestFaceHeightFraction: Double = 0
}

enum ShotAnchorLipSyncVerdict: Equatable {
    /// A face large enough to articulate.
    case ready(faceHeightFraction: Double)
    /// A face exists but is too small for visible lip-sync.
    case small(faceHeightFraction: Double)
    /// No face detected at all.
    case noFace
    /// The detector or image read failed — render proceeds, honestly noted.
    case unavailable

    var blocksRender: Bool {
        switch self {
        case .small, .noFace: return true
        case .ready, .unavailable: return false
        }
    }
}

/// Below this fraction of frame height a mouth is too small for the model to
/// articulate visibly (both observed frozen-mouth anchors measured ≈0.04).
let shotAnchorLipSyncMinimumFaceHeightFraction = 0.12

/// The pure threshold law — kept detector-free so tests pin it directly.
func shotAnchorLipSyncVerdict(report: ShotAnchorFaceReport?) -> ShotAnchorLipSyncVerdict {
    guard let report else { return .unavailable }
    guard report.faceCount > 0 else { return .noFace }
    let fraction = report.largestFaceHeightFraction
    guard fraction >= shotAnchorLipSyncMinimumFaceHeightFraction else {
        return .small(faceHeightFraction: fraction)
    }
    return .ready(faceHeightFraction: fraction)
}

/// The refusal sentence for a blocking verdict; nil when the render may run.
func shotAnchorLipSyncRefusal(verdict: ShotAnchorLipSyncVerdict) -> String? {
    switch verdict {
    case .noFace:
        return "No face in the anchor frame — LTX lip-sync needs a frontal close-up. Pick a closer ANCHOR or Reframe one."
    case .small(let fraction):
        return "The speaker's face is ≈\(Int((fraction * 100).rounded()))% of frame height — too small for lip-sync. Pick a closer ANCHOR or Reframe one."
    case .ready, .unavailable:
        return nil
    }
}

/// Runs the local detector over an image. Nil when the file cannot be read
/// or Vision errors — the caller's verdict then fails open as .unavailable.
func shotAnchorFaceReport(imagePath: String) -> ShotAnchorFaceReport? {
    let url = URL(fileURLWithPath: imagePath)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return nil
    }
    return shotAnchorFaceReport(cgImage: image)
}

func shotAnchorFaceReport(cgImage: CGImage) -> ShotAnchorFaceReport? {
    let request = VNDetectFaceRectanglesRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
        try handler.perform([request])
    } catch {
        return nil
    }
    let faces = request.results ?? []
    // Vision bounding boxes are normalized to the image, so height is already
    // the fraction of frame height.
    let largest = faces.map(\.boundingBox.height).max() ?? 0
    return ShotAnchorFaceReport(
        faceCount: faces.count,
        largestFaceHeightFraction: Double(largest)
    )
}

/// The operator's vouch against the face check: non-empty and naming exactly
/// the resolved anchor entry. One law for engine and strip — never two
/// spellings of the skip.
func shotAnchorFaceOverrideApplies(overrideEntryId: String, anchorEntryId: String) -> Bool {
    let vouched = overrideEntryId.trimmed
    return !vouched.isEmpty && vouched == anchorEntryId.trimmed && !anchorEntryId.trimmed.isEmpty
}

// MARK: - Anchor entry resolution (one law, engine + strip)

/// The narration-driven render's visual anchor: the picked entry when
/// `narrationAnchorEntryId` names a ready, non-skipped, non-clip frame whose
/// file exists — otherwise the first such entry. A stale pick silently falls
/// back rather than refusing.
func shotNarrationAnchorEntry(
    shot: ProjectShot,
    frameLookup: [String: ProjectLensHeroImage],
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> (entry: ShotFrameEntry, frame: ProjectLensHeroImage)? {
    let candidates: [(entry: ShotFrameEntry, frame: ProjectLensHeroImage)] = shot.entries.compactMap { entry in
        guard !entry.isSkipped, !entry.isClip,
              let frame = frameLookup[entry.frameImageId],
              fileExists(frame.imagePath) else {
            return nil
        }
        return (entry, frame)
    }
    let pickedId = shot.narrationAnchorEntryId.trimmed
    if !pickedId.isEmpty, let picked = candidates.first(where: { $0.entry.entryId == pickedId }) {
        return picked
    }
    return candidates.first
}
