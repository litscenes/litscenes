import AppKit
import SwiftUI

/// THE SCENES MEDIA PANEL — the right-sidebar MEDIA tab: every partition of
/// project media (footage, story inputs, hidden library images, creations)
/// browsable beside the SHOTS canvas, every tile drag-enabled onto shot rows
/// and stage plates. This panel exists because a drag cannot cross a tab
/// switch: the Media tab's grids were unreachable from the shot rows.
/// Footage lives here too (it absorbed the old FOOTAGE tab), keeping one
/// media surface instead of two.
struct ScenesMediaPanel: View {
    @ObservedObject var library: LibraryEngine
    var onOpenMedia: () -> Void

    @State private var filterQuery = ""
    @State private var isHiddenVideosOpen = false
    @State private var isHiddenImagesOpen = false
    /// Footage groups whose extracted-stills disclosure is open.
    @State private var openStillsMediaIds: Set<String> = []

    /// 294pt content width inside the 330pt sidebar: 3 × 92 + 2 × 9.
    private let gridColumns = [GridItem(.adaptive(minimum: 92, maximum: 120), spacing: 9)]

    var body: some View {
        let layout = library.videoTrayLayoutForDisplay
        let inventory = scenesMediaInventory(
            items: library.items,
            isRejected: { library.curation(for: $0).rejected }
        )
        let creations = creationsInventory(items: library.items, lenses: library.projectLenses.lenses)
        let roleIndex = library.mediaRoleIndex
        let isEmpty = layout.visibleGroups.isEmpty && layout.hiddenItems.isEmpty
            && inventory.storyInputs.isEmpty && inventory.hiddenImages.isEmpty
            && creations.isEmpty

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isEmpty {
                    emptyState
                } else {
                    filterField
                    footageSection(layout: layout)
                    storyInputsSection(inventory.storyInputs, roleIndex: roleIndex)
                    hiddenImagesSection(inventory.hiddenImages, roleIndex: roleIndex)
                    creationsSection(creations, roleIndex: roleIndex)
                    Text("Drag anything onto a shot row or a stage. Footage plays verbatim; a photo becomes a Frame the moment it lands.")
                        .font(CanonType.interface(10.5))
                        .foregroundStyle(CanonColor.ink.opacity(0.45))
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: Chrome

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No media yet — import photos, footage, and audio in the Media tab.")
                .font(CanonType.editorial(13))
                .foregroundStyle(CanonColor.ink.opacity(0.50))
            Button("Open the Media tab") {
                onOpenMedia()
            }
            .buttonStyle(.plain)
            .font(CanonType.interface(11, weight: .semibold))
            .foregroundStyle(CanonColor.brass)
        }
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CanonColor.ink.opacity(0.4))
            TextField("Filter by name or tag", text: $filterQuery)
                .textFieldStyle(.plain)
                .font(CanonType.interface(11.5))
            if !filterQuery.trimmed.isEmpty {
                Button {
                    filterQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(CanonColor.ink.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper.opacity(0.8)))
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(title.uppercased()) · \(count)")
                .font(CanonType.interface(10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(CanonColor.ink.opacity(0.55))
            Rectangle()
                .fill(CanonColor.hairlinePaper)
                .frame(height: 1)
        }
    }

    private func matches(_ item: MediaItemRecord) -> Bool {
        scenesMediaFilterMatches(
            filename: item.filename,
            tags: library.curation(for: item).tags,
            query: filterQuery
        )
    }

    // MARK: Footage

    @ViewBuilder
    private func footageSection(layout: VideoTrayLayout) -> some View {
        let visible = layout.visibleGroups.filter { group in
            matches(group.parent)
                || group.trims.contains(where: matches)
                || group.looks.contains(where: matches)
        }
        let hidden = layout.hiddenItems.filter(matches)
        if !visible.isEmpty || !hidden.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                sectionHeader("Footage", count: layout.visibleGroups.count)
                ForEach(visible) { group in
                    ScenesFootageRow(library: library, item: group.parent, isTrim: group.parent.isVideoTrim)
                    ForEach(group.trims) { trim in
                        ScenesFootageRow(library: library, item: trim, isTrim: true)
                            .padding(.leading, 14)
                    }
                    ForEach(group.looks) { look in
                        ScenesFootageRow(library: library, item: look, isTrim: false, isLook: true)
                            .padding(.leading, 14)
                    }
                    stillsDisclosure(for: group.parent)
                }
                if !hidden.isEmpty {
                    disclosureRow(
                        label: "Hidden videos · \(hidden.count)",
                        isOpen: $isHiddenVideosOpen
                    )
                    if isHiddenVideosOpen {
                        ForEach(hidden) { item in
                            ScenesFootageRow(library: library, item: item, isTrim: item.isVideoTrim, isHidden: true)
                                .padding(.leading, 14)
                        }
                    }
                }
            }
        }
    }

    /// Extracted stills nest under their parent footage — their only surface
    /// outside the Video Studio (they are rejected-by-default at creation, so
    /// no grid ever lists them). Dragging one onto a shot row adopts it as a
    /// Frame like any photo.
    @ViewBuilder
    private func stillsDisclosure(for parent: MediaItemRecord) -> some View {
        let stills = library.extractedFrames(for: parent.mediaId).filter(matches)
        if !stills.isEmpty {
            disclosureRow(
                label: "Stills · \(stills.count)",
                isOpen: Binding(
                    get: { openStillsMediaIds.contains(parent.mediaId) },
                    set: { open in
                        if open {
                            openStillsMediaIds.insert(parent.mediaId)
                        } else {
                            openStillsMediaIds.remove(parent.mediaId)
                        }
                    }
                )
            )
            .padding(.leading, 14)
            if openStillsMediaIds.contains(parent.mediaId) {
                mediaGrid(stills, roleIndex: nil)
                    .padding(.leading, 14)
            }
        }
    }

    // MARK: Image sections

    @ViewBuilder
    private func storyInputsSection(_ items: [MediaItemRecord], roleIndex: MediaRoleIndex) -> some View {
        let shown = items.filter(matches)
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                sectionHeader("Story Inputs", count: items.count)
                mediaGrid(shown, roleIndex: roleIndex)
            }
        }
    }

    @ViewBuilder
    private func hiddenImagesSection(_ items: [MediaItemRecord], roleIndex: MediaRoleIndex) -> some View {
        let shown = items.filter(matches)
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                disclosureRow(
                    label: "Library · \(items.count) hidden",
                    isOpen: $isHiddenImagesOpen
                )
                if isHiddenImagesOpen {
                    mediaGrid(shown, roleIndex: roleIndex)
                }
            }
        }
    }

    // MARK: Creations

    @ViewBuilder
    private func creationsSection(_ groups: [CreationGroup], roleIndex: MediaRoleIndex) -> some View {
        ForEach(groups) { group in
            let refs = group.refs.filter { ref in
                switch ref {
                case .media(let item):
                    return matches(item)
                case .lensTake(_, let image):
                    return scenesMediaFilterMatches(filename: image.label, tags: [], query: filterQuery)
                }
            }
            if !refs.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    sectionHeader(group.kind.rawValue, count: group.refs.count)
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 9) {
                        ForEach(refs) { ref in
                            switch ref {
                            case .media(let item):
                                ScenesMediaTile(library: library, item: item, roleIndex: roleIndex)
                            case .lensTake(_, let image):
                                lensTakeTile(image)
                            }
                        }
                    }
                }
            }
        }
    }

    /// A lens take is already a Frame — it drags as one (ShotFrameTransfer)
    /// and skips adoption entirely. This is where "see ALL my frames" lives
    /// regardless of what the BACKLOT has staged away.
    private func lensTakeTile(_ image: ProjectLensHeroImage) -> some View {
        ScenesMediaThumb(path: image.imagePath, cornerBadge: "photo.artframe")
            .draggable(ShotFrameTransfer(frameImageId: image.imageId))
            .help("\(image.label.trimmed.nilIfEmpty ?? "Frame") — drag onto a shot row or a stage")
    }

    // MARK: Grid + disclosure primitives

    private func mediaGrid(_ items: [MediaItemRecord], roleIndex: MediaRoleIndex?) -> some View {
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 9) {
            ForEach(items) { item in
                ScenesMediaTile(library: library, item: item, roleIndex: roleIndex)
            }
        }
    }

    private func disclosureRow(label: String, isOpen: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOpen.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isOpen.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(CanonColor.ink.opacity(0.45))
                Text(label)
                    .font(CanonType.interface(10.5, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.55))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tiles

/// The panel's compact drag-first tile for any media item: thumbnail, one
/// role badge, the Use menu on right-click. Deliberately NOT the Media tab's
/// MediaTileView — no selection or preview state, drag is the point.
private struct ScenesMediaTile: View {
    @ObservedObject var library: LibraryEngine
    let item: MediaItemRecord
    var roleIndex: MediaRoleIndex?

    var body: some View {
        let badge = roleIndex?
            .badges(for: item, curation: library.curation(for: item))
            .first
        ScenesMediaThumb(
            path: item.thumbnailPath.isEmpty ? item.path : item.thumbnailPath,
            cornerBadge: badge?.systemImage,
            durationSeconds: item.kind == .video ? item.durationSeconds : nil
        )
        .draggable(MediaIDTransfer(mediaId: item.mediaId))
        .contextMenu {
            MediaUseMenu(library: library, item: item)
            if item.kind == .video {
                FootageStageMenu(library: library, mediaId: item.mediaId)
            }
        }
        .help("\(item.filename) — drag onto a shot row or a stage\(badge.map { " · \($0.label)" } ?? "")")
    }
}

/// The shared 92×62 thumb plate.
private struct ScenesMediaThumb: View {
    let path: String
    var cornerBadge: String? = nil
    var durationSeconds: Double? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .overlay(
                    Group {
                        if let image = NSImage(contentsOfFile: path) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            CanonColor.paperInset
                        }
                    }
                )
            HStack(spacing: 3) {
                if let cornerBadge {
                    Image(systemName: cornerBadge)
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .padding(3)
                        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 3))
                }
                Spacer(minLength: 0)
                if let durationSeconds {
                    Text(videoTrimTimestampLabel(durationSeconds))
                        .font(CanonType.interface(8, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(3)
        }
        .frame(height: 62)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlinePaper))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// The footage row, moved verbatim from the retired FOOTAGE sidebar tab —
/// same thumbnail plate, trim/look glyphs, duration, drag, and stage menu.
struct ScenesFootageRow: View {
    @ObservedObject var library: LibraryEngine
    let item: MediaItemRecord
    var isTrim = false
    var isLook = false
    var isHidden = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.14))
                if let image = NSImage(contentsOfFile: item.thumbnailPath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(0.4))
                }
            }
            .frame(width: 44, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CanonColor.hairlinePaper)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(isHidden ? 0.6 : 1))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if isTrim {
                        Image(systemName: "scissors")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(CanonColor.ink.opacity(0.55))
                    }
                    if isLook {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(CanonColor.ink.opacity(0.55))
                    }
                    Text(videoTrimTimestampLabel(item.durationSeconds ?? 0))
                        .font(CanonType.interface(10.5))
                        .foregroundStyle(CanonColor.ink.opacity(0.55))
                    if item.isPortrait {
                        Text("9:16")
                            .font(CanonType.interface(9, weight: .semibold))
                            .foregroundStyle(CanonColor.ink.opacity(0.45))
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "film")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CanonColor.brass.opacity(0.7))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(isHidden ? 0.35 : 0.55)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.8)))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .draggable(MediaIDTransfer(mediaId: item.mediaId))
        .contextMenu {
            FootageStageMenu(library: library, mediaId: item.mediaId)
            if isHidden {
                Button {
                    library.setRejected(item.mediaId, false)
                } label: {
                    Label("Unhide", systemImage: "eye")
                }
            }
        }
        .help(isHidden
            ? "Hidden from the tray — still drags onto a shot row. Right-click to unhide"
            : "Drag onto a shot row, or right-click to place")
    }
}
