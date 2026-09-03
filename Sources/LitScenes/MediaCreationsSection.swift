import AppKit
import SwiftUI

/// One creation: a generated media row, or a lens take (embedded in the lens
/// document, not a media record — unioning the two is what makes Creations an
/// honest inventory).
enum CreationRef: Identifiable, Hashable {
    case media(MediaItemRecord)
    case lensTake(lensId: String, image: ProjectLensHeroImage)

    var id: String {
        switch self {
        case .media(let item): return "media_\(item.mediaId)"
        case .lensTake(_, let image): return "take_\(image.imageId)"
        }
    }
}

struct CreationGroup: Identifiable {
    enum Kind: String, CaseIterable {
        case frames = "Frames"
        case shotArtifacts = "Shot Artifacts"
        case mediaRenders = "Media Renders"
        case rosterRenders = "Roster Renders"
        case sheets = "Sheets"
        case captures = "Captures"
    }

    let kind: Kind
    var refs: [CreationRef]
    var id: String { kind.rawValue }
}

/// Everything LitScenes has produced in this project, grouped for the Media
/// page. Sources stay out (video_frame stills and video_trim cuts belong to
/// the Sources grid and tray), and internal support media (chain keyframes,
/// handoff frames) stay out entirely. Collected shot frames are the exception
/// that proves the rule: they look like stills but have no footage parent to
/// nest under, so they list here as shot artifacts instead of vanishing.
/// One-time repair for frames collected before they had their own derivative
/// kind. They were archived as `video_frame` with an empty source, a pairing
/// that nests under no footage parent (the stills tray matches on sourceMediaId)
/// and lists in no Creations group — so they were written to disk and then
/// invisible everywhere. The signature is unambiguous: an automatic extraction
/// always carries the media id of the clip it came from. Idempotent.
func migratingCollectedShotFrames(_ items: [MediaItemRecord]) -> [MediaItemRecord] {
    items.map { item in
        guard item.derivativeKind == MediaItemRecord.videoFrameDerivativeKind,
              (item.sourceMediaId ?? "").trimmed.isEmpty else { return item }
        var migrated = item
        migrated.derivativeKind = MediaItemRecord.collectedShotFrameDerivativeKind
        return migrated
    }
}

func creationsInventory(items: [MediaItemRecord], lenses: [ProjectLens]) -> [CreationGroup] {
    var seenTakeIds = Set<String>()
    // An adopted photo is a source, not a creation — Story Inputs and the
    // library already list it.
    let takes: [CreationRef] = lenses.flatMap { lens in
        lens.readyHeroImages
            .filter { !$0.isAdoptedPhoto }
            .filter { seenTakeIds.insert($0.imageId).inserted }
            .map { CreationRef.lensTake(lensId: lens.lensId, image: $0) }
    }
    let takePaths = Set(takes.compactMap { ref -> String? in
        if case .lensTake(_, let image) = ref { return image.imagePath.trimmed.nilIfEmpty }
        return nil
    })

    var frames = takes
    var shotArtifacts: [CreationRef] = []
    var mediaRenders: [CreationRef] = []
    var rosterRenders: [CreationRef] = []
    var sheets: [CreationRef] = []
    var captures: [CreationRef] = []
    for item in items {
        switch item.derivativeKind {
        case MediaItemRecord.frameReferenceDerivativeKind:
            // An adopted take gets a frame_reference media twin; list the take,
            // not the twin, when both resolve to the same file.
            if !takePaths.contains(item.path.trimmed) {
                frames.append(.media(item))
            }
        case MediaItemRecord.shotLookDerivativeKind,
             MediaItemRecord.clipLookDerivativeKind,
             MediaItemRecord.shotExportDerivativeKind,
             MediaItemRecord.videoChainClipDerivativeKind,
             MediaItemRecord.videoChainReelDerivativeKind,
             MediaItemRecord.collectedShotFrameDerivativeKind:
            shotArtifacts.append(.media(item))
        case MediaItemRecord.mediaRestyleDerivativeKind,
             MediaItemRecord.mediaMotionDerivativeKind,
             MediaItemRecord.terrainMapDerivativeKind,
             MediaItemRecord.terrainMapRegionDerivativeKind:
            mediaRenders.append(.media(item))
        case MediaItemRecord.rosterCharacterRenderDerivativeKind,
             MediaItemRecord.rosterCompositeSheetDerivativeKind:
            rosterRenders.append(.media(item))
        case MediaItemRecord.projectSheetDerivativeKind:
            sheets.append(.media(item))
        case MediaItemRecord.chatAttachmentDerivativeKind:
            captures.append(.media(item))
        default:
            break
        }
    }

    let groups: [CreationGroup] = [
        CreationGroup(kind: .frames, refs: frames),
        CreationGroup(kind: .shotArtifacts, refs: shotArtifacts),
        CreationGroup(kind: .mediaRenders, refs: mediaRenders),
        CreationGroup(kind: .rosterRenders, refs: rosterRenders),
        CreationGroup(kind: .sheets, refs: sheets),
        CreationGroup(kind: .captures, refs: captures)
    ]
    return groups.filter { !$0.refs.isEmpty }
}

/// The Media page's CREATIONS section: the produced-media inventory as a
/// working surface. Image creations carry the full Use menu (a generated still
/// is a first-class reference candidate — the palette loop closes here);
/// lens takes deep-link back into Scenes.
struct MediaCreationsSection: View {
    @ObservedObject var library: LibraryEngine
    var onOpenImage: (MediaItemRecord) -> Void
    /// Click-primary for videos: watch immediately (Video Studio, playing).
    var onOpenVideo: (MediaItemRecord) -> Void
    /// Restyle an image creation as a Frame (Frame Creator, style wheel first).
    var onRestyle: ((MediaItemRecord) -> Void)? = nil
    /// Click-primary for lens takes: enlarge in place (no tab switch).
    var onOpenTake: (String, ProjectLensHeroImage) -> Void
    /// Context-menu deep link back to the Scenes workbench.
    var onRevealLensTake: (String, String) -> Void

    var body: some View {
        let groups = creationsInventory(items: library.items, lenses: library.projectLenses.lenses)
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Creations")
                        .font(CanonType.interface(11, weight: .semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(CanonColor.muted)
                    Rectangle()
                        .fill(CanonColor.hairlineDark)
                        .frame(height: 1)
                }
                Text("Everything LitScenes has made here. Right-click a still to use it as a reference — creations are palette too.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(group.kind.rawValue.uppercased()) · \(group.refs.count)")
                            .font(CanonType.archive(10, weight: .semibold))
                            .foregroundStyle(CanonColor.olive)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 10) {
                            ForEach(group.refs) { ref in
                                creationTile(ref)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func creationTile(_ ref: CreationRef) -> some View {
        switch ref {
        case .lensTake(let lensId, let image):
            lensTakeTile(lensId: lensId, image: image)
        case .media(let item):
            mediaCreationTile(item)
        }
    }

    private func lensTakeTile(lensId: String, image: ProjectLensHeroImage) -> some View {
        Button {
            onOpenTake(lensId, image)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                creationThumbnail(path: image.imagePath)
                Text(image.label.trimmed.isEmpty ? "Take" : image.label)
                    .font(CanonType.archive(9.5, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .help("Enlarge this frame — right-click to reveal it in Scenes")
        .contextMenu {
            Button {
                onRevealLensTake(lensId, image.imageId)
            } label: {
                Label("Reveal in Scenes", systemImage: "arrow.up.forward.square")
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: image.imagePath)])
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        }
    }

    private func mediaCreationTile(_ item: MediaItemRecord) -> some View {
        Button {
            if item.kind == .image {
                onOpenImage(item)
            } else {
                onOpenVideo(item)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .bottomTrailing) {
                    creationThumbnail(path: item.thumbnailPath.isEmpty ? item.path : item.thumbnailPath)
                        .overlay {
                            if item.kind == .video {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(CanonColor.bone)
                                    .padding(7)
                                    .background(CanonColor.room.opacity(0.7), in: Circle())
                            }
                        }
                    if item.kind == .video {
                        Text(creationDurationLabel(item.durationSeconds))
                            .font(CanonType.archive(8, weight: .semibold))
                            .foregroundStyle(CanonColor.bone)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(CanonColor.room.opacity(0.78), in: RoundedRectangle(cornerRadius: 3))
                            .padding(3)
                    }
                }
                Text(item.filename)
                    .font(CanonType.archive(9.5, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .draggable(MediaIDTransfer(mediaId: item.mediaId))
        .contextMenu {
            MediaUseMenu(
                library: library,
                item: item,
                onRestyle: item.kind == .image ? onRestyle.map { restyle in { restyle(item) } } : nil
            )
        }
        .help(item.kind == .video ? "Watch in Video Studio" : item.filename)
    }

    private func creationDurationLabel(_ durationSeconds: Double?) -> String {
        guard let durationSeconds else { return "Video" }
        let seconds = Int(durationSeconds.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func creationThumbnail(path: String) -> some View {
        Color.clear
            .overlay(
                Group {
                    if let nsImage = NSImage(contentsOfFile: path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        CanonColor.paperInset
                    }
                }
            )
            .frame(width: 112, height: 74)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlineDark))
    }
}
