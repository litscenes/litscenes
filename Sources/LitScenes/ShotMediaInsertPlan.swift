import Foundation

// THE SCENES MEDIA PANEL's pure half: what a media drop onto a shot row (or a
// stage palette) should DO, and how the panel sections the project's media.
// A media drag reaches the drop targets as a clip drag — ShotFrameTransfer's
// alias decode reads a bare {"mediaId"} payload into clipMediaId, and that
// ordering is load-bearing for the entry fallback — so the branch here
// runs on the RESOLVED MEDIA KIND, never on the payload shape.

/// What one media drop should do. `placeFrame` fires when the image was
/// already adopted as a Frame for this lens (adoption is idempotent by
/// source_photo provenance); `adoptImageAsFrame` mints the Frame first.
/// `refuse` always carries the honest status line — never a silent no-op.
enum ShotMediaInsertPlan: Equatable {
    case placeClip(mediaId: String)
    case placeFrame(frameImageId: String)
    case adoptImageAsFrame(mediaId: String)
    case refuse(reason: String)
}

func shotMediaInsertPlan(
    media: MediaItemRecord?,
    adoptedFrameImageId: String?
) -> ShotMediaInsertPlan {
    guard let media else {
        return .refuse(reason: "That media item is gone from the library")
    }
    switch media.kind {
    case .video:
        return .placeClip(mediaId: media.mediaId)
    case .image:
        if let adopted = adoptedFrameImageId?.trimmed.nilIfEmpty {
            return .placeFrame(frameImageId: adopted)
        }
        return .adoptImageAsFrame(mediaId: media.mediaId)
    case .audio:
        return .refuse(reason: "Audio attaches from the Voice & Audio tab, not the picture row")
    }
}

/// What a media drop actually placed — the caller gathers the stage palette
/// by this, so an image drop stages its Frame, never a bogus clip reference.
enum ShotMediaPlacement: Equatable {
    case clip(mediaId: String)
    case frame(frameImageId: String)
}

// MARK: - Panel inventory

/// The image sections of the Scenes MEDIA panel. Footage and Creations are
/// deliberately NOT here — they already have their own pure laws
/// (`videoTrayLayout`, `creationsInventory`) and the panel delegates to them.
/// This law owns what those two do not: the image grids, and the
/// each-image-exactly-once rule between them.
struct ScenesMediaInventory: Equatable {
    /// Images in play (not rejected) — mirrors the Media tab's Story Inputs.
    var storyInputs: [MediaItemRecord] = []
    /// Operator-hidden images, shown behind a collapsed disclosure. Excludes
    /// extracted video stills (they surface under their parent footage group)
    /// and generated media (those live in Creations — adopted/generated
    /// images are rejected-by-default, so without this clause they would
    /// double-list here).
    var hiddenImages: [MediaItemRecord] = []
}

func scenesMediaInventory(
    items: [MediaItemRecord],
    isRejected: (MediaItemRecord) -> Bool
) -> ScenesMediaInventory {
    var inventory = ScenesMediaInventory()
    for item in items where item.kind == .image {
        if !isRejected(item) {
            inventory.storyInputs.append(item)
        } else if !item.isExtractedVideoFrame && !item.isGeneratedMedia {
            inventory.hiddenImages.append(item)
        }
    }
    return inventory
}

/// The panel's one filter law: filename or curation tag contains the query
/// (case-insensitive). An empty query matches everything.
func scenesMediaFilterMatches(
    filename: String,
    tags: [String],
    query: String
) -> Bool {
    let needle = query.trimmed.lowercased()
    guard !needle.isEmpty else { return true }
    if filename.lowercased().contains(needle) { return true }
    return tags.contains { $0.lowercased().contains(needle) }
}
