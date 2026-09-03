import Foundation

/// The role badges a Media-surface tile can carry. Roles are DERIVED — each
/// badge's truth lives in the document that owns it (curation's rejected bit,
/// the roster documents' reference lists, placed shot entries, and lens render
/// source dependencies). Nothing here persists.
enum MediaRoleBadge: Hashable {
    /// Promoted: analyzed, and its observation text steers Story/aesthetics.
    case storyInput
    case characterRef(name: String)
    case objectRef(name: String)
    case placeRef(name: String)
    /// A video placed verbatim as a shot segment (the exact placed item — a
    /// placed trim badges the trim, not its parent).
    case footage
    /// Fed at least one frame render as a pixel reference (direct reference,
    /// @mention, clip seed — anything stamped as a moodboard_image dependency).
    case usedInFrames(count: Int)

    var label: String {
        switch self {
        case .storyInput:
            return "Story"
        case .characterRef(let name), .objectRef(let name), .placeRef(let name):
            return name
        case .footage:
            return "In shot"
        case .usedInFrames(let count):
            return count == 1 ? "1 frame" : "\(count) frames"
        }
    }

    var systemImage: String {
        switch self {
        case .storyInput: return "text.book.closed"
        case .characterRef: return "person.crop.circle"
        case .objectRef: return "shippingbox"
        case .placeRef: return "building.2"
        case .footage: return "film"
        case .usedInFrames: return "photo.artframe"
        }
    }
}

/// Precomputed lookups behind the badges — build once per grid pass with
/// `buildMediaRoleIndex`, then ask per tile.
struct MediaRoleIndex: Equatable {
    var characterNamesByMediaId: [String: [String]] = [:]
    var objectNamesByMediaId: [String: [String]] = [:]
    var placeNamesByMediaId: [String: [String]] = [:]
    var footageMediaIds: Set<String> = []
    var frameUseCountByMediaId: [String: Int] = [:]
    /// Frames (by imageId) referenced by any CURRENT entry of the given shots
    /// — the SCENES v2 pool's "used" truth for frames, mirroring
    /// footageMediaIds for clips. Feed visibleShots when "unused" must mean
    /// "not placed anywhere the user can see".
    var usedFrameImageIds: Set<String> = []

    func badges(for item: MediaItemRecord, curation: MediaCurationRecord) -> [MediaRoleBadge] {
        var badges: [MediaRoleBadge] = []
        if item.canBeEnabledContent, !curation.rejected {
            badges.append(.storyInput)
        }
        for name in characterNamesByMediaId[item.mediaId] ?? [] {
            badges.append(.characterRef(name: name))
        }
        for name in objectNamesByMediaId[item.mediaId] ?? [] {
            badges.append(.objectRef(name: name))
        }
        for name in placeNamesByMediaId[item.mediaId] ?? [] {
            badges.append(.placeRef(name: name))
        }
        if item.kind == .video, footageMediaIds.contains(item.mediaId) {
            badges.append(.footage)
        }
        if let count = frameUseCountByMediaId[item.mediaId], count > 0 {
            badges.append(.usedInFrames(count: count))
        }
        return badges
    }
}

func buildMediaRoleIndex(
    characters: [ProjectCharacter],
    objects: [ProjectObject],
    places: [ProjectPlace],
    shots: [ProjectShot],
    lenses: [ProjectLens]
) -> MediaRoleIndex {
    var index = MediaRoleIndex()
    for character in characters {
        let name = character.name.trimmed
        guard !name.isEmpty else { continue }
        for mediaId in character.referenceMediaIds where !mediaId.isEmpty {
            index.characterNamesByMediaId[mediaId, default: []].append(name)
        }
    }
    for object in objects {
        let name = object.name.trimmed
        guard !name.isEmpty else { continue }
        for mediaId in object.referenceMediaIds where !mediaId.isEmpty {
            index.objectNamesByMediaId[mediaId, default: []].append(name)
        }
    }
    for place in places {
        let name = place.name.trimmed
        guard !name.isEmpty else { continue }
        for mediaId in place.referenceMediaIds where !mediaId.isEmpty {
            index.placeNamesByMediaId[mediaId, default: []].append(name)
        }
    }
    for shot in shots {
        for entry in shot.entries {
            let clipMediaId = entry.clipMediaId.trimmed
            if !clipMediaId.isEmpty {
                index.footageMediaIds.insert(clipMediaId)
            }
            let frameImageId = entry.frameImageId.trimmed
            if !frameImageId.isEmpty {
                index.usedFrameImageIds.insert(frameImageId)
            }
        }
    }
    // Every pixel reference into a frame render is stamped as a
    // moodboard_image prompt-image dependency (direct references, @mention
    // refs, clip seeds) — count distinct renders per source media id.
    for lens in lenses {
        for image in lens.heroImages {
            var seenForImage: Set<String> = []
            for dependency in image.sourceDependencies {
                guard dependency.kind == LensPromptImageAttachmentSource.moodboardImage.rawValue,
                      dependency.role == "prompt_image_source" else { continue }
                let sourceId = dependency.sourceId.trimmed
                guard !sourceId.isEmpty, !seenForImage.contains(sourceId) else { continue }
                seenForImage.insert(sourceId)
                index.frameUseCountByMediaId[sourceId, default: 0] += 1
            }
        }
    }
    return index
}
