import AppKit
import SwiftUI

/// Context/action menu content for one media item — the "Use…" verbs that put
/// library media one gesture away from powering something. Usable inside both
/// `Menu { }` and `.contextMenu { }` (the FootageStageMenu pattern). Verbs that
/// need view-level presentation (tag editor, Video Studio) ride as closures;
/// engine-global verbs call the engine directly.
struct MediaUseMenu: View {
    @ObservedObject var library: LibraryEngine
    let item: MediaItemRecord
    /// Opens the tag/notes editor anchored at the presenting view.
    var onEditTags: (() -> Void)? = nil
    /// Opens the Video Studio for this item (videos only).
    var onOpenStudio: (() -> Void)? = nil
    /// Restyles this photo as a Frame — opens the Frame Creator, style wheel
    /// first (images; nil hides the verb).
    var onRestyle: (() -> Void)? = nil
    /// Opens the viewer's Start Video popover (images; same anchor rule).
    var onStartVideo: (() -> Void)? = nil

    var body: some View {
        if item.kind == .image {
            imageVerbs
        } else if item.kind == .audio {
            audioVerbs
        } else {
            videoVerbs
        }
    }

    // MARK: - Audio

    /// Audio never gets video verbs. The operator chooses the semantic lane:
    /// Clip plays once, while Ambient loops from the CUT start.
    @ViewBuilder
    private var audioVerbs: some View {
        let trashedCutIds = Set(library.stageSet.trashedCuts.map(\.cutId))
        let cuts = library.shotTimeline.shots.filter { !trashedCutIds.contains($0.shotId) }
        if cuts.isEmpty {
            Button {} label: {
                Label("Attach as Clip…", systemImage: "waveform")
            }
            .disabled(true)
            .help("Create a CUT first")
        } else {
            audioAttachMenu(
                title: "Attach as Clip…",
                systemImage: "waveform",
                laneId: ShotAudioLaneId.clip,
                cuts: cuts
            )
            audioAttachMenu(
                title: "Attach as Narration…",
                systemImage: "quote.bubble",
                laneId: ShotAudioLaneId.narration,
                cuts: cuts
            )
            audioAttachMenu(
                title: "Attach as Ambient…",
                systemImage: "speaker.wave.2",
                laneId: ShotAudioLaneId.ambient,
                cuts: cuts
            )
        }
        Divider()
        if let onEditTags {
            Button {
                onEditTags()
            } label: {
                Label("Tag…", systemImage: "tag")
            }
        }
        hideToggle
        Button {
            library.revealInFinder(item)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        Divider()
        storageVerbs
    }

    private func audioAttachMenu(
        title: String,
        systemImage: String,
        laneId: String,
        cuts: [ProjectShot]
    ) -> some View {
        Menu {
            ForEach(Array(cuts.enumerated()), id: \.element.shotId) { index, cut in
                Button(cut.name.trimmed.nilIfEmpty ?? "CUT \(index + 1)") {
                    _ = library.addShotAudioRegion(
                        shotId: cut.shotId,
                        laneId: laneId,
                        asset: .projectAudio(mediaId: item.mediaId),
                        startSeconds: 0
                    )
                }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    // MARK: - Images

    @ViewBuilder
    private var imageVerbs: some View {
        if let onRestyle {
            Button {
                onRestyle()
            } label: {
                Label("Restyle…", systemImage: "paintpalette")
            }
        }
        if let onStartVideo {
            Button {
                onStartVideo()
            } label: {
                Label("Start Video…", systemImage: "video.badge.plus")
            }
        }
        useInFrameCreator
        rosterSubmenu(
            title: "Add to Character",
            systemImage: "person.crop.circle",
            targets: library.projectCharacters.characters.map {
                RosterTarget(id: $0.characterId, name: $0.name, referenceMediaIds: $0.referenceMediaIds)
            },
            apply: { target, mediaIds in
                _ = library.setCharacterReferenceMedia(characterId: target.id, mediaIds: mediaIds)
            }
        )
        rosterSubmenu(
            title: "Add to Object",
            systemImage: "shippingbox",
            targets: library.projectObjects.objects.map {
                RosterTarget(id: $0.objectId, name: $0.name, referenceMediaIds: $0.referenceMediaIds)
            },
            apply: { target, mediaIds in
                _ = library.setObjectReferenceMedia(objectId: target.id, mediaIds: mediaIds)
            }
        )
        rosterSubmenu(
            title: "Add to Place",
            systemImage: "building.2",
            targets: library.projectPlaces.places.map {
                RosterTarget(id: $0.placeId, name: $0.name, referenceMediaIds: $0.referenceMediaIds)
            },
            apply: { target, mediaIds in
                _ = library.setPlaceReferenceMedia(placeId: target.id, mediaIds: mediaIds)
            }
        )
        Divider()
        storyInputToggle
        if let onEditTags {
            Button {
                onEditTags()
            } label: {
                Label("Tag…", systemImage: "tag")
            }
        }
        if item.isProjectSheet {
            Button {
                ShareServices.presentPicker(for: [URL(fileURLWithPath: item.path)])
            } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
        }
        Button {
            library.revealInFinder(item)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        Divider()
        storageVerbs
    }

    /// A project has one Scene Plan, so this is one item — enabled once the
    /// plan exists, a disabled explainer before that. (Previously this
    /// also carried a per-lens submenu for the several-lenses case, which had
    /// been unreachable since the plan became singular.)
    @ViewBuilder
    private var useInFrameCreator: some View {
        if let lens = library.readyLenses.first {
            Button {
                library.requestFrameCreatorSeed(lensId: lens.lensId, mediaIds: [item.mediaId])
            } label: {
                Label("Use in Frame Creator", systemImage: "photo.artframe")
            }
            .help("Open the Frame Creator with this image attached as a reference")
        } else {
            Button {} label: {
                Label("Use in Frame Creator", systemImage: "photo.artframe")
            }
            .disabled(true)
            .help("Plan your Scenes first")
        }
    }

    private struct RosterTarget: Identifiable {
        let id: String
        let name: String
        let referenceMediaIds: [String]
    }

    /// Attach/detach toggle per roster entry — a checkmark marks entries already
    /// holding this image; tapping again removes it. Hidden when the roster has
    /// no entries of that kind (menu noise beats a dead submenu).
    @ViewBuilder
    private func rosterSubmenu(
        title: String,
        systemImage: String,
        targets: [RosterTarget],
        apply: @escaping (RosterTarget, [String]) -> Void
    ) -> some View {
        if !targets.isEmpty {
            Menu {
                ForEach(targets) { target in
                    let isAttached = target.referenceMediaIds.contains(item.mediaId)
                    Button {
                        let updated = isAttached
                            ? target.referenceMediaIds.filter { $0 != item.mediaId }
                            : target.referenceMediaIds + [item.mediaId]
                        apply(target, updated)
                    } label: {
                        if isAttached {
                            Label(target.name, systemImage: "checkmark")
                        } else {
                            Text(target.name)
                        }
                    }
                }
            } label: {
                Label(title, systemImage: systemImage)
            }
        }
    }

    @ViewBuilder
    private var storyInputToggle: some View {
        if item.canBeEnabledContent {
            let isStoryInput = !library.curation(for: item).rejected
            Button {
                if isStoryInput {
                    library.setRejected(item.mediaId, true)
                } else {
                    _ = library.enableContentItem(item.mediaId)
                }
            } label: {
                if isStoryInput {
                    Label("Return to Library", systemImage: "arrow.uturn.backward.circle")
                } else {
                    Label("Promote to Story Input", systemImage: "arrow.up.circle")
                }
            }
        }
    }

    // MARK: - Videos

    @ViewBuilder
    private var videoVerbs: some View {
        Menu {
            FootageStageMenu(library: library, mediaId: item.mediaId)
        } label: {
            Label("Place in Shot", systemImage: "film")
        }
        if let onOpenStudio {
            Button {
                onOpenStudio()
            } label: {
                Label("Open in Video Studio", systemImage: "rectangle.stack.badge.play")
            }
        }
        Divider()
        hideToggle
        Button {
            library.revealInFinder(item)
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        Divider()
        storageVerbs
    }

    @ViewBuilder
    private var storageVerbs: some View {
        let status = library.mediaStorageStatus(for: item)
        Label("Storage: \(status.label)", systemImage: storageIcon(for: status))
        if library.canMakeMediaManaged(item) {
            Button {
                library.makeMediaManaged(item)
            } label: {
                Label("Make Managed", systemImage: "internaldrive.badge.plus")
            }
        }
        if library.canRelinkMedia(item) {
            Button {
                library.relinkMedia(item)
            } label: {
                Label("Relink…", systemImage: "link.badge.plus")
            }
        }
    }

    private func storageIcon(for status: MediaStorageStatus) -> String {
        switch status {
        case .managed: "internaldrive.fill"
        case .linked: "link"
        case .missing: "exclamationmark.triangle.fill"
        }
    }

    @ViewBuilder
    private var hideToggle: some View {
        let isHidden = library.curation(for: item).rejected
        Button {
            library.setRejected(item.mediaId, !isHidden)
        } label: {
            if isHidden {
                Label("Unhide", systemImage: "eye")
            } else {
                Label("Hide from tray", systemImage: "eye.slash")
            }
        }
    }
}

/// Tag/notes editor for one media item — the first UI over the long-dormant
/// curation `tags`/`notes` fields. Tags are comma-separated and immediately
/// searchable through the library filter.
struct MediaTagEditorPopover: View {
    @ObservedObject var library: LibraryEngine
    let item: MediaItemRecord
    var onDone: () -> Void = {}

    @State private var tagsText = ""
    @State private var notesText = ""
    @State private var didSeed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(item.filename)
                .font(CanonType.interface(12, weight: .semibold))
                .foregroundStyle(CanonColor.bone)
                .lineLimit(1)
            Text("TAGS")
                .font(CanonType.archive(9, weight: .semibold))
                .foregroundStyle(CanonColor.muted)
            TextField("comma, separated, tags", text: $tagsText)
                .textFieldStyle(.roundedBorder)
                .font(CanonType.interface(12))
            Text("NOTES")
                .font(CanonType.archive(9, weight: .semibold))
                .foregroundStyle(CanonColor.muted)
            TextEditor(text: $notesText)
                .font(CanonType.interface(12))
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(height: 64)
                .background(CanonColor.paperInset, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(CanonColor.hairlineDark))
            HStack(alignment: .center, spacing: 8) {
                Text("Tags are searchable in the library filter.")
                    .font(CanonType.archive(9))
                    .foregroundStyle(CanonColor.muted)
                Spacer(minLength: 0)
                Button("Save") {
                    library.setTags(item.mediaId, tagsText)
                    library.setNotes(item.mediaId, notesText)
                    onDone()
                }
                .buttonStyle(CanonPrimaryButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(CanonColor.room)
        .onAppear {
            guard !didSeed else { return }
            didSeed = true
            let curation = library.curation(for: item)
            tagsText = curation.tags.joined(separator: ", ")
            notesText = curation.notes
        }
    }
}
