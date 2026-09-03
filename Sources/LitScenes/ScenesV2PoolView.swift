import SwiftUI

/// The SCENES v2 Source pool's control strip: filter chips + search, split
/// from the grid so the unified page scroll can pin it with the stage while
/// the grid content rides the page scroll beneath. A dumb view — values in,
/// closures out.
struct ScenesV2PoolControlsRow: View {
    @Binding var filter: ScenesV2PoolFilter
    @Binding var searchQuery: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            chipRow
            Spacer(minLength: 12)
            searchField
        }
    }

    // MARK: Chips + search

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(ScenesV2PoolFilter.allCases, id: \.self) { chip in
                let isOn = filter == chip
                Button {
                    filter = chip
                } label: {
                    Text(chip.title)
                        .font(CanonType.archive(7.5, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(isOn ? CanonColor.brass : CanonColor.muted)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        // Ghost on-state: the first suggestion's RENDER is the
                        // page's one filled brass element.
                        .background(Capsule().fill(isOn ? CanonColor.brass.opacity(0.16) : Color.clear))
                        .overlay(Capsule().stroke(isOn ? CanonColor.brass.opacity(0.6) : CanonColor.hairlineDark, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CanonColor.muted)
            TextField("Search all source material", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.bone)
            if !searchQuery.trimmed.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(CanonColor.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 230, height: 26)
        .background(RoundedRectangle(cornerRadius: 7).fill(CanonColor.archiveWell))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlineDark))
    }
}

/// The pool's content: one union inventory (frames + footage) behind the
/// active filter. Characters and Objects replace the grid with grouped roster
/// sections whose takes and identity refs are individually draggable — a
/// character IS a collection of frames here. Deliberately scroller-free: the
/// enclosing page scroll owns the viewport, and the LazyVGrids stay lazy
/// against it. A dumb view — values in, closures out.
struct ScenesV2PoolGridSections: View {
    /// Plain values, not bindings — the grid only reads them.
    let filter: ScenesV2PoolFilter
    let searchQuery: String
    let inputs: [StageInput]
    let usage: ScenesV2PoolUsage
    let frameLookup: [String: ProjectLensHeroImage]
    let mediaLookup: [String: MediaItemRecord]
    let characterGroups: [LensIdentityTakeGroup]
    let objectGroups: [LensIdentityTakeGroup]
    var onOpenFrame: (ProjectLensHeroImage) -> Void
    var onOpenMedia: (String) -> Void
    /// A source photo opens as the Frame it is (adopted on first open); nil
    /// falls back to `onOpenMedia` for a surface without a Scene Plan.
    var onOpenPhotoAsFrame: ((String) -> Void)? = nil
    /// Right-click shortcut: create a Scene with this tile's material as its
    /// first entry, and stage it. The payload is the tile's own drag
    /// transfer, so every tile kind (frame, photo, footage, take, ref)
    /// speaks the same language as its drop.
    var onStartNewScene: (ShotFrameTransfer) -> Void = { _ in }
    /// SUGGESTED FRAMES — the pool's first section under ALL and UNUSED, and each
    /// character's lead under CHARACTERS. Present whenever a Scene Plan exists.
    var showsSuggestions: Bool = false
    var suggestions: [ScenesV2SuggestionCardModel] = []
    var suggestionsByCharacterId: [String: [ScenesV2SuggestionCardModel]] = [:]
    var suggestionRefusals: [String: String] = [:]
    var renderCaption: String = ""
    var renderBlockReason: String = ""
    var moreSuggestionsDisabledReason: String = ""
    var accentSwatches: [LensColorSwatch] = []
    /// What a ready tile offers on hover (and in its menu) beside dragging.
    var tileAction: ScenesV2TileAction = .startScene
    var onRenderSuggestion: (String) -> Void = { _ in }
    var onArtDirectSuggestion: (String) -> Void = { _ in }
    var onMoreSuggestions: () -> Void = {}
    var onNewFrame: () -> Void = {}
    /// The hover CTA's placement at the end of the staged Scene.
    var onPlaceInStagedScene: (ShotFrameTransfer) -> Void = { _ in }
    /// What the section says when it is empty (the way in, a running job, the action).
    var suggestionNotice: ScenesV2SuggestionNotice? = nil
    var onOpenCharacters: () -> Void = {}

    private static let gridColumns = [GridItem(.adaptive(minimum: 132, maximum: 168), spacing: 10)]
    private static let suggestionColumns = [GridItem(.adaptive(minimum: 250, maximum: 340), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch filter {
            case .characters:
                identitySections(characterGroups, emptyText: "No characters yet — cast them from the Story, or add takes in a Frame.")
            case .objects:
                identitySections(objectGroups, emptyText: "No objects yet.")
            case .all, .unused:
                if showsSuggestions {
                    suggestionsSection(suggestions, header: true)
                        .id("v2Suggested")
                }
                filteredGrid
            case .startEnd:
                filteredGrid
            }
        }
    }

    // MARK: Union grid

    private var filteredInputs: [StageInput] {
        inputs.filter { input in
            poolInputMatchesFilter(input, filter: filter, usage: usage)
                && poolInputMatchesQuery(input, query: searchQuery, frameLookup: frameLookup, mediaLookup: mediaLookup)
        }
    }

    @ViewBuilder
    private var filteredGrid: some View {
        let filtered = filteredInputs
        if filtered.isEmpty {
            Text(emptyGridText)
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.muted)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            SourceMaterialSectionHeader(title: filter.title, count: filtered.count)
            LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: 10) {
                ForEach(filtered) { input in
                    tile(for: input)
                }
            }
        }
    }

    private var emptyGridText: String {
        switch filter {
        case .unused:
            return searchQuery.trimmed.isEmpty
                ? "Everything is placed in a Scene."
                : "No unused material matches the search."
        case .startEnd:
            return "No Scene has ready boundary frames yet."
        default:
            if !searchQuery.trimmed.isEmpty { return "Nothing matches the search." }
            return suggestions.isEmpty
                ? "No source material yet — add media or render Frames."
                : "No source material yet — render a suggested Frame above, or add media."
        }
    }

    // MARK: Suggested Frames

    @ViewBuilder
    private func suggestionsSection(_ cards: [ScenesV2SuggestionCardModel], header: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if header {
                HStack(spacing: 10) {
                    Text("SUGGESTED FRAMES · \(cards.count)")
                        .font(CanonType.archive(8.5, weight: .bold))
                        .kerning(2.0)
                        .foregroundStyle(CanonColor.brass)
                        .layoutPriority(1)
                    Rectangle()
                        .fill(CanonColor.hairlinePaper)
                        .frame(height: 1)
                    capsAction(
                        cards.isEmpty ? "SUGGEST FRAMES" : "MORE SUGGESTIONS",
                        disabledReason: moreSuggestionsDisabledReason,
                        help: "Suggests dramatic moments for every character with a sheet or source images — a text call, no image renders",
                        action: onMoreSuggestions
                    )
                    // The pool's own verb wears a pill: the caps link beside it
                    // is a text call, this one opens the Frame Creator.
                    StageBrassPill(
                        title: "NEW FRAME",
                        icon: "plus",
                        style: .ghost,
                        size: .compact,
                        action: onNewFrame
                    )
                    .help("Open the Frame Creator on a blank Frame — it lands in this pool")
                }
            }
            if cards.isEmpty {
                suggestionEmptyState
            } else {
                LazyVGrid(columns: Self.suggestionColumns, alignment: .leading, spacing: 12) {
                    ForEach(cards) { card in
                        ScenesV2SuggestionCardView(
                            model: card,
                            renderCaption: renderCaption,
                            renderBlockReason: renderBlockReason,
                            refusal: suggestionRefusals[card.imageId] ?? "",
                            accentSwatches: accentSwatches,
                            onRender: { onRenderSuggestion(card.imageId) },
                            onArtDirect: { onArtDirectSuggestion(card.imageId) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var suggestionEmptyState: some View {
        switch suggestionNotice {
        case .createCharacter:
            HStack(spacing: 10) {
                Text(scenesV2CreateCharacterNotice)
                    .font(CanonType.interface(11.5))
                    .foregroundStyle(CanonColor.muted)
                capsAction("CHARACTERS →", help: "Open CHARACTERS", action: onOpenCharacters)
            }
        case .suggesting(let line):
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text(line)
                    .font(CanonType.interface(11.5))
                    .foregroundStyle(CanonColor.muted)
            }
        case .suggestNow, .none:
            Text("No Frames suggested yet — SUGGEST FRAMES drafts two dramatic moments for every character with reference images.")
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.muted)
        }
    }

    private func capsAction(
        _ title: String,
        disabledReason: String = "",
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(CanonType.archive(8, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(disabledReason.isEmpty ? CanonColor.brass : CanonColor.muted)
                .lineLimit(1)
        }
        .buttonStyle(.plain)
        .disabled(!disabledReason.isEmpty)
        .pointingHandCursor()
        .help(disabledReason.isEmpty ? help : disabledReason)
    }

    private func place(_ transfer: ShotFrameTransfer) {
        switch tileAction {
        case .startScene:
            onStartNewScene(transfer)
        case .addToScene:
            onPlaceInStagedScene(transfer)
        case .sceneLocked:
            break
        }
    }

    @ViewBuilder
    private func tile(for input: StageInput) -> some View {
        if input.isClip, let media = mediaLookup[input.clipMediaId] {
            if media.kind == .video {
                mediaTile(media, kindLabel: "FOOTAGE")
            } else {
                // THE ADOPTED PHOTO LAW: a source photo is a Frame — it reads as
                // one and opens as one; its caption is the stem an adopted row
                // carries as its label, so adoption changes nothing visible.
                mediaTile(
                    media,
                    kindLabel: "FRAME",
                    caption: scenesV2PhotoCaption(filename: media.filename),
                    onTap: { (onOpenPhotoAsFrame ?? onOpenMedia)(media.mediaId) }
                )
            }
        } else if let frame = frameLookup[input.frameImageId] {
            frameTile(frame)
        }
    }

    private func mediaTile(
        _ media: MediaItemRecord,
        kindLabel: String,
        caption: String? = nil,
        onTap: (() -> Void)? = nil
    ) -> some View {
        PoolTileView(
            thumbPath: media.thumbnailPath.trimmed.isEmpty ? media.path : media.thumbnailPath,
            caption: caption ?? media.filename,
            kindLabel: kindLabel,
            isVideo: media.kind == .video,
            transfer: ShotFrameTransfer(frameImageId: "", clipMediaId: media.mediaId),
            placeAction: tileAction,
            onTap: onTap ?? { onOpenMedia(media.mediaId) },
            onStartNewScene: onStartNewScene,
            onPlace: place(_:)
        )
    }

    private func frameTile(_ frame: ProjectLensHeroImage) -> some View {
        PoolTileView(
            thumbPath: frame.imagePath,
            caption: frame.label.trimmed.nilIfEmpty ?? "Frame",
            kindLabel: "FRAME",
            isVideo: false,
            status: frame.status,
            transfer: ShotFrameTransfer(frameImageId: frame.imageId),
            placeAction: tileAction,
            onTap: { onOpenFrame(frame) },
            onStartNewScene: onStartNewScene,
            onPlace: place(_:)
        )
    }

    // MARK: Characters / Objects

    @ViewBuilder
    private func identitySections(_ groups: [LensIdentityTakeGroup], emptyText: String) -> some View {
        if groups.isEmpty {
            Text(emptyText)
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.muted)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            ForEach(groups) { group in
                identitySection(group)
            }
        }
    }

    @ViewBuilder
    private func identitySection(_ group: LensIdentityTakeGroup) -> some View {
        let query = searchQuery.trimmed.lowercased()
        // Planned studies live on the guided stage, not here — one home per
        // plan, and never a fake spinner in a roster section.
        let takes = group.takes.filter { take in
            !take.isPlanFulfillmentCandidate
                && (query.isEmpty
                    || take.label.lowercased().contains(query)
                    || group.displayName.lowercased().contains(query))
        }
        let refs = group.referenceMediaIds.compactMap { mediaLookup[$0] }.filter { media in
            query.isEmpty
                || media.filename.lowercased().contains(query)
                || group.displayName.lowercased().contains(query)
        }
        if !(takes.isEmpty && refs.isEmpty && !query.isEmpty) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(group.displayName.uppercased())
                        .font(CanonType.archive(8.5, weight: .bold))
                        .kerning(1.2)
                        .foregroundStyle(group.membership == .cast ? CanonColor.brass : CanonColor.muted)
                    if group.membership == .cast {
                        Text("IN THIS SCENE")
                            .font(CanonType.archive(6.5, weight: .bold))
                            .kerning(0.6)
                            .foregroundStyle(CanonColor.brass.opacity(0.8))
                    }
                    Text("\(takes.count) take\(takes.count == 1 ? "" : "s") · \(refs.count) ref\(refs.count == 1 ? "" : "s")")
                        .font(CanonType.archive(7, weight: .semibold))
                        .foregroundStyle(CanonColor.muted.opacity(0.8))
                    Rectangle()
                        .fill(CanonColor.hairlinePaper)
                        .frame(height: 1)
                }
                if let cards = suggestionsByCharacterId[group.characterId], !cards.isEmpty {
                    suggestionsSection(cards, header: false)
                }
                if takes.isEmpty && refs.isEmpty && (suggestionsByCharacterId[group.characterId] ?? []).isEmpty {
                    Text("No frames yet — render a study or attach references from Media.")
                        .font(CanonType.archive(7.5, weight: .medium))
                        .foregroundStyle(CanonColor.muted.opacity(0.8))
                } else {
                    LazyVGrid(columns: Self.gridColumns, alignment: .leading, spacing: 10) {
                        ForEach(takes) { take in
                            frameTile(take)
                        }
                        ForEach(refs, id: \.mediaId) { media in
                            mediaTile(media, kindLabel: "REF")
                        }
                    }
                }
            }
        }
    }
}

/// One pool tile: a 16:9 thumbnail card that previews on tap and drags as
/// placeable material. Thumbnails always decode through StripThumbnailCache.
/// In-flight and failed frames state themselves (the StageInputCard idiom) —
/// a transform child that lands in the pool must be findable, not a dead
/// grey card.
struct PoolTileView: View {
    let thumbPath: String
    let caption: String
    let kindLabel: String
    let isVideo: Bool
    /// Hero-image status for frame tiles ("generating"/"queued"/"failed"
    /// render honestly); media tiles are always "ready".
    var status: String = "ready"
    let transfer: ShotFrameTransfer
    /// The hover CTA (and its menu twin); nil hides both.
    var placeAction: ScenesV2TileAction? = nil
    var onTap: () -> Void
    var onStartNewScene: (ShotFrameTransfer) -> Void = { _ in }
    var onPlace: (ShotFrameTransfer) -> Void = { _ in }

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack(alignment: .bottomLeading) {
                if status == "generating" || status == "queued" {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(CanonColor.paperInset.opacity(0.5))
                        .frame(height: 76)
                        .overlay(
                            VStack(spacing: 5) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(status == "generating" ? "RENDERING" : "QUEUED")
                                    .font(CanonType.archive(7, weight: .semibold))
                                    .kerning(0.6)
                                    .foregroundStyle(CanonColor.muted)
                            }
                        )
                } else if status == "failed" {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(CanonColor.rust.opacity(0.08))
                        .frame(height: 76)
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CanonColor.rust.opacity(0.8))
                                Text("FAILED")
                                    .font(CanonType.archive(7, weight: .semibold))
                                    .kerning(0.6)
                                    .foregroundStyle(CanonColor.rust.opacity(0.85))
                            }
                        )
                } else if let image = StripThumbnailCache.shared.image(path: thumbPath, maxPixel: 340) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .frame(height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(CanonColor.paperInset.opacity(0.5))
                        .frame(height: 76)
                        .overlay(
                            Image(systemName: isVideo ? "film" : "photo")
                                .font(.system(size: 13, weight: .light))
                                .foregroundStyle(CanonColor.muted.opacity(0.5))
                        )
                }
                Text(kindLabel)
                    .font(CanonType.archive(6, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(CanonColor.ink.opacity(0.7))
                    .padding(.horizontal, 4)
                    .frame(height: 12)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.8)))
                    .padding(4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CanonColor.hairlinePaper.opacity(0.9), lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                if isHovering, status == "ready", let placeAction {
                    hoverButton(placeAction)
                }
            }
            Text(caption)
                .font(CanonType.archive(7.5, weight: .semibold))
                .foregroundStyle(CanonColor.bone.opacity(0.78))
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onTap)
        .draggable(transfer) {
            Text(caption)
                .font(CanonType.archive(8.5, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(CanonColor.paperInset))
                .overlay(Capsule().stroke(CanonColor.brass.opacity(0.6), lineWidth: 1))
        }
        .contextMenu {
            if let placeAction, placeAction != .startScene {
                Button(placeAction.menuTitle) {
                    onPlace(transfer)
                }
                .disabled(!placeAction.isEnabled)
            }
            Button("Start New Scene with This") {
                onStartNewScene(transfer)
            }
        }
        .help(status == "ready"
            ? "Drag into a Scene box — click to preview — hover for the one-click place — right-click for more"
            : (status == "failed"
                ? "Failed — click to open it"
                : "Rendering — it can be placed once ready"))
    }

    /// The hover CTA: one caps verb over a bottom gradient. Disabled states its
    /// reason in the tooltip instead of vanishing.
    private func hoverButton(_ action: ScenesV2TileAction) -> some View {
        Button {
            onPlace(transfer)
        } label: {
            Text(action.title)
                .font(CanonType.archive(7, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(action.isEnabled ? CanonColor.brass : CanonColor.muted)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.66)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!action.isEnabled)
        .help(action.isEnabled
            ? "Places it at the end of the staged Scene — dragging works too"
            : "A rendered Scene is immutable — NEW VERSION on the Scene duplicates it for editing")
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
