import Foundation

/// Ephemeral navigation context: the visible collection owns ordering, not a lens.
struct FrameBrowseSelection: Equatable {
    var id: String
    var index: Int = 0
}

struct FrameBrowseReference: Identifiable, Hashable {
    var id: String
    var imageId: String = ""
    var mediaId: String = ""
    var imagePath: String

    init(frame: ProjectLensHeroImage, prefix: String = "") {
        id = prefix + (frame.adoptedPhotoMediaId.map { "photo_" + $0 } ?? "frame_" + frame.imageId)
        imageId = frame.imageId
        mediaId = frame.adoptedPhotoMediaId ?? ""
        imagePath = frame.imagePath
    }
    init(photo: MediaItemRecord) {
        id = "photo_" + photo.mediaId
        mediaId = photo.mediaId
        imagePath = photo.path
    }
}

func frameBrowseReferences(inputs: [StageInput], frames: [String: ProjectLensHeroImage], media: [String: MediaItemRecord]) -> [FrameBrowseReference] {
    inputs.compactMap { input in
        if let frame = frames[input.frameImageId], frame.status == "ready", !frame.imagePath.isEmpty, !frame.disabled {
            return FrameBrowseReference(frame: frame)
        }
        if let photo = media[input.clipMediaId], photo.kind == .image { return FrameBrowseReference(photo: photo) }
        return nil
    }
}

func poolIdentityBrowseTakes(_ group: LensIdentityTakeGroup, query: String) -> [ProjectLensHeroImage] {
    let query = query.trimmed.lowercased()
    return group.takes.filter { !$0.isPlanFulfillmentCandidate && (query.isEmpty
        || $0.label.lowercased().contains(query) || group.displayName.lowercased().contains(query)) }
}
