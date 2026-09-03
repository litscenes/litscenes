import Foundation

// THE ADOPTED PHOTO LAW. A Media photo becomes a Frame by adoption: its pixels
// are copied into the project and a lens row is stamped provider "media" /
// model "original-photo" with one `source_photo` dependency naming the media
// item. The predicate keys on provider + model, never on provenance alone — a
// variation or restyle rendered FROM an adopted photo inherits that dependency
// and is a render, not a photo.

extension ProjectLensHeroImage {
    static let adoptedPhotoProvider = "media"
    static let adoptedPhotoModel = "original-photo"
    static let sourcePhotoDependencyRole = "source_photo"

    /// True only for rows minted by photo adoption.
    var isAdoptedPhoto: Bool {
        provider.trimmed.lowercased() == Self.adoptedPhotoProvider
            && model.trimmed.lowercased() == Self.adoptedPhotoModel
    }

    /// The media item an adopted photo came from; nil for renders, even ones
    /// carrying an inherited `source_photo` dependency.
    var adoptedPhotoMediaId: String? {
        guard isAdoptedPhoto else { return nil }
        return sourceDependencies
            .lazy
            .map { $0.normalized() }
            .first { $0.role == Self.sourcePhotoDependencyRole && !$0.sourceId.isEmpty }?
            .sourceId
    }
}

// MARK: - SCENES v2 inventory

/// SCENES v2's pool inventory — every source photo is ONE Frame tile:
/// - a photo whose enabled adopted row exists anywhere project-wide is emitted
///   as that FRAME input in the photo group, at the photo's own position, so
///   opening or adopting never moves a tile and a re-plan's new media version
///   never doubles it;
/// - a photo without an enabled adoption stays a media input (drops adopt it
///   lazily, as they always did);
/// - the frames group carries every other frame — displayed first in the given
///   order, then the rest newest-first — including adopted rows whose photo is
///   not in `items`, so nothing ever vanishes from the pool;
/// - disabled rows are not inventory; footage comes last.
/// The shared `projectPoolInputs` law is V1's and stays untouched.
func scenesV2PoolInputs(
    displayedFrames: [ProjectLensHeroImage],
    projectWideFrames: [ProjectLensHeroImage],
    items: [MediaItemRecord]
) -> [StageInput] {
    // Displayed rows win over project-wide duplicates so a substituted tile is
    // the row the stage shows.
    var adoptedByMediaId: [String: ProjectLensHeroImage] = [:]
    for frame in projectWideFrames + displayedFrames {
        guard !frame.disabled, let mediaId = frame.adoptedPhotoMediaId else { continue }
        adoptedByMediaId[mediaId] = frame
    }

    let photos = items
        .filter { $0.kind == .image }
        .sorted { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt { return lhs.filename < rhs.filename }
            return lhs.modifiedAt > rhs.modifiedAt
        }
    var substitutedMediaIds = Set<String>()
    var photoInputs: [StageInput] = []
    for photo in photos {
        if let frame = adoptedByMediaId[photo.mediaId] {
            substitutedMediaIds.insert(photo.mediaId)
            photoInputs.append(
                StageInput(
                    inputId: "source_frame_\(frame.imageId)",
                    frameImageId: frame.imageId,
                    addedAt: photo.modifiedAt
                )
            )
        } else {
            photoInputs.append(
                StageInput(
                    inputId: "source_media_\(photo.mediaId)",
                    clipMediaId: photo.mediaId,
                    addedAt: photo.modifiedAt
                )
            )
        }
    }

    // A substituted photo owns every enabled adoption of itself — one tile per
    // photo even when a legacy multi-lens project adopted it twice.
    func belongsToFramesGroup(_ frame: ProjectLensHeroImage) -> Bool {
        guard !frame.disabled else { return false }
        if let mediaId = frame.adoptedPhotoMediaId, substitutedMediaIds.contains(mediaId) {
            return false
        }
        return true
    }
    func frameInput(_ frame: ProjectLensHeroImage) -> StageInput {
        StageInput(
            inputId: "source_frame_\(frame.imageId)",
            frameImageId: frame.imageId,
            addedAt: frame.generatedAt
        )
    }

    var seenFrameIds = Set<String>()
    let visibleFrames = displayedFrames
        .filter { belongsToFramesGroup($0) && seenFrameIds.insert($0.imageId).inserted }
        .map(frameInput)
    let otherFrames = projectWideFrames
        .filter { belongsToFramesGroup($0) && !seenFrameIds.contains($0.imageId) }
        .sorted { lhs, rhs in
            if lhs.generatedAt == rhs.generatedAt {
                if lhs.imageIndex == rhs.imageIndex { return lhs.imageId < rhs.imageId }
                return lhs.imageIndex < rhs.imageIndex
            }
            return lhs.generatedAt > rhs.generatedAt
        }
        .filter { seenFrameIds.insert($0.imageId).inserted }
        .map(frameInput)

    let footage = items
        .filter { $0.kind == .video }
        .sorted { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt { return lhs.filename < rhs.filename }
            return lhs.modifiedAt > rhs.modifiedAt
        }
        .map {
            StageInput(
                inputId: "source_media_\($0.mediaId)",
                clipMediaId: $0.mediaId,
                addedAt: $0.modifiedAt
            )
        }
    return photoInputs + visibleFrames + otherFrames + footage
}

/// Rendered frames for the guided stage and the whisper's honest count: ready
/// rows with a file, minus adopted photos — a photo is source material, not a
/// render, and opening one must never move the cold-start journey.
func scenesV2RenderedFrames(_ frames: [ProjectLensHeroImage]) -> [ProjectLensHeroImage] {
    frames.filter {
        $0.status == "ready" && !$0.imagePath.trimmed.isEmpty && !$0.isAdoptedPhoto
    }
}

/// The photo tile's caption: the filename stem, which is also the label an
/// adopted row carries — so adoption changes nothing the eye can see.
func scenesV2PhotoCaption(filename: String) -> String {
    let stem = (filename.trimmed as NSString).deletingPathExtension.trimmed
    if !stem.isEmpty { return stem }
    return filename.trimmed.nilIfEmpty ?? "Photo"
}
