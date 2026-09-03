import SwiftUI

/// The concept board's category grouping. New images carry explicit taxonomy metadata;
/// route keys remain the fallback for older project data.
enum LensConceptCategory: String, CaseIterable {
    case areas
    case scenery
    case characters
    case objects
    case legacy

    static func category(for image: ProjectLensHeroImage) -> LensConceptCategory {
        switch LensImageTaxonomyKind.normalized(image.imageKind) {
        case LensImageTaxonomyKind.areaImage:
            return .areas
        case LensImageTaxonomyKind.sceneImage:
            return .scenery
        case LensImageTaxonomyKind.characterImage:
            return .characters
        case LensImageTaxonomyKind.objectImage:
            return .objects
        default:
            return category(forRouteKey: image.sourceRouteKey)
        }
    }

    /// The imageKind stamped on a blank frame of this category, so section bucketing
    /// works without a route-key fallback.
    var taxonomyImageKind: String {
        switch self {
        case .areas: return LensImageTaxonomyKind.areaImage
        case .scenery: return LensImageTaxonomyKind.sceneImage
        case .characters: return LensImageTaxonomyKind.characterImage
        case .objects: return LensImageTaxonomyKind.objectImage
        case .legacy: return ""
        }
    }

    static func category(forRouteKey routeKey: String) -> LensConceptCategory {
        let base = routeKey.split(separator: "@").first.map(String.init) ?? routeKey
        if base.hasPrefix("lens_media_area") && !base.contains("_scene_") { return .areas }
        if base.hasPrefix("lens_media_area") && base.contains("_scene_") { return .scenery }
        if base.hasPrefix("lens_media_scenery_1_s") { return .areas }
        if base.hasPrefix("lens_media_scenery") { return .scenery }
        if base.hasPrefix("lens_media_character") { return .characters }
        if base.hasPrefix("lens_media_object") { return .objects }
        return .legacy
    }

    var title: String {
        switch self {
        case .areas: return "AREAS"
        case .scenery: return "FRAMES"
        case .characters: return "CHARACTERS"
        case .objects: return "OBJECTS"
        case .legacy: return "COMPOSITES (LEGACY)"
        }
    }

    /// Groups a version's frames into ordered, non-empty sections.
    static func sections(for images: [ProjectLensHeroImage]) -> [(category: LensConceptCategory, images: [ProjectLensHeroImage])] {
        var buckets: [LensConceptCategory: [ProjectLensHeroImage]] = [:]
        for image in images {
            buckets[category(for: image), default: []].append(image)
        }
        return allCases.compactMap { category in
            guard let bucket = buckets[category], !bucket.isEmpty else { return nil }
            return (category, bucket.sorted { $0.imageIndex < $1.imageIndex })
        }
    }
}

enum LensMediaRenderScope: String, CaseIterable, Identifiable {
    case scene
    case characters
    case objects
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .scene: "Scene"
        case .characters: "Characters"
        case .objects: "Objects"
        case .all: "All Planned"
        }
    }

    func includes(_ category: LensConceptCategory) -> Bool {
        switch self {
        case .scene:
            return category == .areas || category == .scenery || category == .legacy
        case .characters:
            return category == .characters
        case .objects:
            return category == .objects
        case .all:
            return true
        }
    }
}

/// One rendered frame available as a continuity source for later frames in the same run.
struct LensConceptChainEntry: Sendable {
    var styleId: String
    var category: LensConceptCategory
    var url: URL
}

/// Selects the continuity attachments for a frame: same-style SCENERY only (anchor takes
/// included), most recent two. Studies never serve as continuity — chaining studies off
/// studies homogenizes their compositions and piles up uploads; world continuity comes
/// from places, likeness comes from character references.
func lensConceptContinuityURLs(assignedStyleId: String?, chain: [LensConceptChainEntry]) -> [URL] {
    chain
        .filter { entry in
            (entry.category == .areas || entry.category == .scenery)
                && (assignedStyleId == nil || entry.styleId == assignedStyleId)
        }
        .suffix(2)
        .map(\.url)
}

private struct LensReframeCardBoundsPreferenceKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Staged progress for a lens's concept board, driven entirely off persisted per-image
/// state and grouped by department: the anchor-scene style bake-off, scenery concepts,
/// character studies, and object studies (legacy composites keep their own section).
/// Queued = dotted skeleton, generating = shimmer with a continuity caption, ready = the
/// image with a Keep star and optional motion setup, failed = rust card with the same
/// play/setup affordance as planned rows.
struct LensGenerationTheaterView: View {
    let lens: ProjectLens
    let versionId: String
    let isSequence: Bool
    var workspaceSize: CGSize = .zero
    /// Which frame categories this instance renders. Lets the main board show scenes
    /// while the sidebar shows characters or objects, from the same component.
    var displayCategories: Set<LensConceptCategory> = Set(LensConceptCategory.allCases)
    /// Shared Source Material search. It filters generated Frames by the
    /// operator-facing label and prompt without changing their persisted set.
    var filterQuery: String = ""
    /// The main Source Material surface owns the single FRAMES heading, while
    /// sidebar instances retain the theater's category headings.
    var showsSectionHeaders: Bool = true
    /// Identity-first grouping for the OBJECTS sidebar tab: when provided, takes
    /// render under per-identity headers (roster face, name) instead of a flat grid.
    /// Takes not covered by any group still render in a residual grid — grouping
    /// never hides work. (Characters left the theater: they render in the
    /// scene-first SceneCharactersPanel.)
    var identityGroups: [LensIdentityTakeGroup] = []
    /// Media pool that resolves identity-group reference thumbnails (the full image
    /// inventory, so adopted generated frames resolve too).
    var identityReferenceCandidates: [MediaItemRecord] = []
    /// Place captions for the FRAMES strip, keyed by the lens area that owns each
    /// scenery frame. Empty keeps the strip flat (legacy lenses without areas).
    var placeCaptionsByAreaId: [String: String] = [:]
    /// Frames hidden from this board because another surface owns their
    /// display (the BACKLOT board excludes frames gathered onto stages).
    var excludedImageIds: Set<String> = []
    /// Stage targets for the card right-click "Gather on …" menu. Empty plus
    /// nil gather closures keeps cards menu-free (sidebar boards).
    var stageGatherTargets: [StageGatherTarget] = []
    var onGatherFrame: ((ProjectLensHeroImage, String) -> Void)? = nil
    var onGatherFrameToNewStage: ((ProjectLensHeroImage) -> Void)? = nil
    /// Duplicates a ready frame as an independent copy (backlot cards keep
    /// their copies in the backlot; staged sources land beside the original).
    var onDuplicateFrame: ((ProjectLensHeroImage) -> Void)? = nil
    var moodboardItems: [MediaItemRecord] = []
    /// Analysis descriptions keyed by mediaId; the Frame Creator turns selected
    /// moodboard images into text-only mood influences from these.
    var moodObservationsById: [String: ImageObservationResult] = [:]
    /// Roster characters/objects the Frame Creator can @mention to attach references.
    var mentionEntries: [RosterMentionResolver.Entry] = []
    /// Full image inventory backing mention reference resolution.
    var mentionReferenceItems: [MediaItemRecord] = []
    /// Builds a mentioned entry's composite sheet on demand at submit time (passed
    /// through to the Frame Creator).
    var onEnsureMentionSheet: ((RosterMentionResolver.Entry) async -> MediaItemRecord?)? = nil
    /// Library images the Frame Creator's reference well can attach directly
    /// (passed through; empty hides the well).
    var referenceLibraryItems: [MediaItemRecord] = []
    /// Generated frames (lens takes) the reference picker can offer, plus the
    /// adopt-on-pick callback (both passed through to the Frame Creator).
    var generatedFrameCandidates: [GeneratedFrameCandidate] = []
    var onAdoptGeneratedFrame: ((ProjectLensHeroImage) async -> MediaItemRecord?)? = nil
    /// Forwarded to the Frame Creator's reference well "Upload…" button.
    var onUploadReferences: (() async -> [MediaItemRecord])? = nil
    /// True while the library's media analysis pass runs (Frame Creator tiles
    /// show spinners); paired with the auto-analyze callback below.
    var isAnalyzingMoods: Bool = false
    var onAutoAnalyzeMoods: () -> Void = {}
    /// Fires when the versions slice opens/closes, so a bounded host viewport
    /// can reserve room beneath the grid (the slice overlay extends past the
    /// last row and would otherwise clip inside a nested ScrollView).
    var onVersionsSliceVisibilityChanged: ((Bool) -> Void)? = nil
    /// Story-route Form option trios for the Frame Creator's cycler.
    var formGenerations: [[LensFrameFormOption]] = []
    var onExpandFormOption: ((LensFrameFormOption, String?) async -> [LensFrameFormOption])? = nil
    /// The Frame Creator's refine chat: (currentPrompt, directive, priorDirectives).
    var onTransformFormPrompt: ((String, String, [String]) async -> LensFormPromptTransform?)? = nil
    var onOpenImage: (ProjectLensHeroImage) -> Void
    var onToggleKept: (ProjectLensHeroImage) -> Void = { _ in }
    var onRenderScope: ((LensMediaRenderScope) -> Void)? = nil
    var onRenderImage: ((ProjectLensHeroImage, LensTakeRenderRequest) -> Void)? = nil
    var onRenderNewTake: ((ProjectLensHeroImage, LensNewTakeRenderRequest) -> Void)? = nil
    /// Fulfills a planned scene frame IN PLACE via the Frame Creator (same row,
    /// same board slot). Nil keeps planned cards on the quick-render popover.
    var onFulfillPlannedFrame: ((ProjectLensHeroImage, LensNewTakeRenderRequest) -> Void)? = nil
    /// Renders a template-less blank frame in the given category, on this theater's
    /// media version.
    var onRenderBlankFrame: ((LensConceptCategory, LensNewTakeRenderRequest) -> Void)? = nil
    /// Source Material provides its own first-position Add Frame card. Other
    /// theaters retain the trailing blank-frame card by default.
    var showsBlankFrameCreationCard: Bool = true
    /// Opens the roster editor focused on this identity.
    var onOpenIdentity: ((LensIdentityTakeGroup) -> Void)? = nil
    /// Removes a planned (never-started) take — the un-cast gesture for a character
    /// whose studies haven't rendered.
    var onRemovePlannedTake: ((ProjectLensHeroImage) -> Void)? = nil
    var onAnimateImage: ((ProjectLensHeroImage) -> Void)? = nil
    var onApplyTakeStyle: ((ProjectLensHeroImage, LensStyleTreatmentSlot, String) -> Void)? = nil
    var onPreviewStyle: (StyleImagePreviewRequest) -> Void = { _ in }
    var onOpenAppSettings: (() -> Void)? = nil
    var hasOpenAICredential: Bool = true
    var hasCivitaiCredential: Bool = false
    var hasFALCredential: Bool = false
    var hasStabilityCredential: Bool = false
    /// Nil while a still render may start; else the engine's reason (pause,
    /// exclusive Scene Plan work, a full take lane).
    var stillRenderBlockReason: String? = nil
    /// Free slots in the engine's parallel Frame take lane.
    var takeLaneFreeSlots: Int = .max
    var isAnimatingLensArtifact: Bool = false
    /// Engine-level pause state: compare mode renders two theaters for one lens, so the
    /// flag must come from the engine, never view-local state.
    var isPaused: Bool = false
    var onTogglePause: (() -> Void)? = nil

    @State private var renderSetupImage: ProjectLensHeroImage?
    @State private var frameCreatorLaunch: FrameCreationContext?
    @State private var stylePickerImage: ProjectLensHeroImage?
    @State private var selectedTakeStyleSlot: LensStyleTreatmentSlot?
    @State private var selectedTakeStyleCatalogVersion = ""
    @State private var expandedVersionsImageId: String?

    private var allImages: [ProjectLensHeroImage] {
        var images = lens.heroImages(mediaVersion: versionId)
        if !excludedImageIds.isEmpty {
            images.removeAll { excludedImageIds.contains($0.imageId) }
        }
        let query = filterQuery.trimmed.lowercased()
        if !query.isEmpty {
            images = images.filter {
                $0.label.lowercased().contains(query)
                    || $0.prompt.lowercased().contains(query)
            }
        }
        return images
    }

    private var images: [ProjectLensHeroImage] {
        activeTheaterImages(from: allImages)
    }

    private var hasActiveWork: Bool {
        allImages.contains { $0.status == "generating" }
    }

    var body: some View {
        let allSectionsByCategory = theaterSectionsByCategory(for: allImages)
        let activeSectionsByCategory = theaterSectionsByCategory(for: images)
        // Areas are no longer a hierarchy level. Any legacy area frame is folded into
        // the flat scene list so every scene frame is a peer — reframe lineage is the
        // only relationship the board shows now.
        let sceneImages = sortedSceneFrameImages(
            (activeSectionsByCategory[.areas] ?? []) + (activeSectionsByCategory[.scenery] ?? [])
        )
        let fullSceneImages = sortedSceneFrameImages(
            (allSectionsByCategory[.areas] ?? []) + (allSectionsByCategory[.scenery] ?? [])
        )
        let sections: [(category: LensConceptCategory, images: [ProjectLensHeroImage], fullImages: [ProjectLensHeroImage])] = [
            (.scenery, sceneImages, fullSceneImages),
            (.characters, activeSectionsByCategory[.characters] ?? [], allSectionsByCategory[.characters] ?? []),
            (.objects, activeSectionsByCategory[.objects] ?? [], allSectionsByCategory[.objects] ?? []),
            (.legacy, activeSectionsByCategory[.legacy] ?? [], allSectionsByCategory[.legacy] ?? [])
        ].filter { section in
            guard displayCategories.contains(section.category) else { return false }
            if !section.images.isEmpty { return true }
            // An empty FRAMES section still renders its blank "+" so frame creation
            // never vanishes with a version's last scenery frame.
            return filterQuery.trimmed.isEmpty
                && section.category == .scenery
                && onRenderBlankFrame != nil
        }
        VStack(alignment: .leading, spacing: 14) {
            if onTogglePause != nil, hasActiveWork || isPaused {
                pauseHeader
            }
            ForEach(sections, id: \.category) { section in
                let fullSectionImages = section.fullImages.isEmpty ? section.images : section.fullImages
                let displayImages = sectionImagesWithReframesAppended(section.images)
                VStack(alignment: .leading, spacing: 6) {
                    if showsSectionHeaders {
                    HStack(alignment: .center, spacing: 8) {
                        Text(section.category.title)
                            .font(CanonType.archive(8.5, weight: .semibold))
                            .kerning(1.4)
                            .foregroundStyle(CanonColor.muted)
                        Spacer(minLength: 0)
                        if let onRenderScope, fullSectionImages.contains(where: isRenderableTake) {
                            let scope = renderScope(for: section.category)
                            let renderableCount = fullSectionImages.filter(isRenderableTake).count
                            // Scene rendering happens per-frame now; the section-level
                            // "Render Scene" CTA is retired. Characters live in the
                            // scene-first sidebar panel, never here — Objects keep theirs.
                            if scope != .scene {
                            Button {
                                onRenderScope(scope)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 8, weight: .semibold))
                                    Text(identityGroups.isEmpty
                                        ? "Render \(scope.label)"
                                        : "Render \(scope.label) · \(renderableCount) planned")
                                        .font(CanonType.interface(10.5, weight: .semibold))
                                }
                                .foregroundStyle(CanonColor.brass)
                                .padding(.horizontal, 8)
                                .frame(height: 24)
                                .background(Capsule().fill(CanonColor.brass.opacity(0.10)))
                                .overlay(Capsule().stroke(CanonColor.brass.opacity(0.45)))
                            }
                            .buttonStyle(.plain)
                            .help("Renders every planned or failed \(scope.label.lowercased()) study in this version")
                            }
                        }
                    }
                    }
                    if !identityGroups.isEmpty, section.category == .characters || section.category == .objects {
                        groupedSectionBody(
                            category: section.category,
                            displayImages: displayImages,
                            fullSectionImages: fullSectionImages
                        )
                    } else if section.category == .scenery, !placeCaptionsByAreaId.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(sceneryPlaceGroups(displayImages)) { group in
                                VStack(alignment: .leading, spacing: 5) {
                                    if !group.caption.isEmpty {
                                        HStack(spacing: 4) {
                                            Image(systemName: "mappin.and.ellipse")
                                                .font(.system(size: 9, weight: .semibold))
                                            Text(group.caption)
                                                .font(CanonType.interface(10.5, weight: .semibold))
                                                .lineLimit(1)
                                        }
                                        .foregroundStyle(CanonColor.ink.opacity(0.55))
                                    }
                                    LazyVGrid(columns: frameGridColumns, alignment: .leading, spacing: 12) {
                                        ForEach(group.entries, id: \.image.imageId) { entry in
                                            compositeCard(
                                                entry.image,
                                                index: entry.index,
                                                category: section.category,
                                                sectionImages: fullSectionImages
                                            )
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        if group.showsBlankFrameCard, shouldShowBlankFrameCard(in: section.category) {
                                            addTakeCard(
                                                launch: .blankFrame(category: section.category),
                                                caption: "New frame",
                                                help: "New blank frame in \(section.category.title) — describe it from scratch"
                                            )
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    } else {
                    LazyVGrid(columns: frameGridColumns, alignment: .leading, spacing: 12) {
                        ForEach(Array(displayImages.enumerated()), id: \.element.imageId) { index, image in
                            compositeCard(
                                image,
                                index: index,
                                category: section.category,
                                sectionImages: fullSectionImages
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if shouldShowBlankFrameCard(in: section.category) {
                            addTakeCard(
                                launch: .blankFrame(category: section.category),
                                caption: "New frame",
                                help: "New blank frame in \(section.category.title) — describe it from scratch"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 2)
                    }
                }
                .zIndex(displayImages.contains { $0.imageId == expandedVersionsImageId } ? 20 : 0)
            }
        }
        .overlayPreferenceValue(LensReframeCardBoundsPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if let expandedVersionsImageId,
                   let anchor = anchors[expandedVersionsImageId],
                   let selectedImage = images.first(where: { $0.imageId == expandedVersionsImageId })
                       ?? allImages.first(where: { $0.imageId == expandedVersionsImageId }) {
                    let rect = proxy[anchor]
                    let parentSize = CGSize(width: rect.width, height: rect.height)
                    generationVersionsSlice(
                        selectedImage: selectedImage,
                        versions: generationVersions(for: selectedImage, in: allImages),
                        parentSize: parentSize
                    )
                    .offset(x: rect.minX, y: rect.maxY + 64)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                    .zIndex(50_000)
                }
            }
            .allowsHitTesting(expandedVersionsImageId != nil)
        }
        .zIndex(expandedVersionsImageId == nil ? 0 : 10_000)
        .onChange(of: expandedVersionsImageId) { newValue in
            onVersionsSliceVisibilityChanged?(newValue != nil)
        }
        .popover(item: $renderSetupImage) { image in
            LensTakeRenderSetupPopover(
                image: image,
                mediaPlan: lens.body.resolvedMediaPlan,
                hasOpenAICredential: hasOpenAICredential,
                hasCivitaiCredential: hasCivitaiCredential,
                hasFALCredential: hasFALCredential,
                hasStabilityCredential: hasStabilityCredential,
                isRenderBlocked: isRenderBlocked,
                renderBlockerHelp: renderBlockerHelp,
                isPaused: isPaused,
                isAnimatingLensArtifact: isAnimatingLensArtifact,
                onSubmit: { request in
                    onRenderImage?(image, request)
                },
                onAnimate: onAnimateImage.map { animate in { animate(image) } },
                onEditStyle: onApplyTakeStyle != nil ? { openStylePicker(image) } : nil,
                onOpenAppSettings: onOpenAppSettings,
                onDismiss: { renderSetupImage = nil }
            )
        }
        .sheet(item: $frameCreatorLaunch) { launch in
            FrameCreatorModal(
                lens: lens,
                context: launch,
                workspaceSize: workspaceSize,
                moodboardItems: moodboardItems,
                moodObservationsById: moodObservationsById,
                hasOpenAICredential: hasOpenAICredential,
                hasCivitaiCredential: hasCivitaiCredential,
                hasFALCredential: hasFALCredential,
                hasStabilityCredential: hasStabilityCredential,
                isRenderBlocked: isRenderBlocked,
                renderBlockerHelp: renderBlockerHelp,
                takeLaneFreeSlots: takeLaneFreeSlots,
                formGenerations: formGenerations,
                isAnalyzingMoods: isAnalyzingMoods,
                onAutoAnalyzeMoods: onAutoAnalyzeMoods,
                onOpenAppSettings: onOpenAppSettings,
                onPreviewStyle: onPreviewStyle,
                onExpandFormOption: onExpandFormOption,
                onTransformFormPrompt: onTransformFormPrompt,
                onSubmit: { requests in
                    frameCreatorLaunch = nil
                    // Each callback spawns its own render task — the batch
                    // fans out and the take lane holds them in parallel.
                    for (index, request) in requests.enumerated() {
                        switch launch {
                        case .blankFrame(let category):
                            onRenderBlankFrame?(category, request)
                        case .plannedFrame(let planned):
                            // First stack fulfills the planned card in place;
                            // the rest land as takes from the same template.
                            if index == 0 {
                                onFulfillPlannedFrame?(planned, request)
                            } else {
                                onRenderNewTake?(planned, request)
                            }
                        case .variation(let template), .restyle(let template), .groupTake(_, let template):
                            onRenderNewTake?(template, request)
                        case .clipMoment, .stageFrame, .shotFrame:
                            // Placement-specific seeds launch only from
                            // the workbench's surfaces, never from the theater.
                            break
                        }
                    }
                },
                onCancel: {
                    frameCreatorLaunch = nil
                },
                mentionEntries: mentionEntries,
                mentionReferenceItems: mentionReferenceItems,
                onEnsureMentionSheet: onEnsureMentionSheet,
                referenceLibraryItems: referenceLibraryItems,
                generatedFrameCandidates: generatedFrameCandidates,
                onAdoptGeneratedFrame: onAdoptGeneratedFrame,
                onUploadReferences: onUploadReferences
            )
        }
        .sheet(item: $stylePickerImage) { image in
            LensTakeStylePickerModal(
                image: image,
                selectedSlot: $selectedTakeStyleSlot,
                catalogVersion: $selectedTakeStyleCatalogVersion,
                onApply: {
                    guard let slot = selectedTakeStyleSlot else { return }
                    stylePickerImage = nil
                    onApplyTakeStyle?(image, slot, selectedTakeStyleCatalogVersion)
                },
                onCancel: {
                    stylePickerImage = nil
                },
                onPreviewStyle: onPreviewStyle
            )
        }
    }

    private func activeTheaterImages(from input: [ProjectLensHeroImage]) -> [ProjectLensHeroImage] {
        var output: [(sortIndex: Int, image: ProjectLensHeroImage)] = []
        var groups: [String: (sortIndex: Int, images: [ProjectLensHeroImage])] = [:]
        for image in input {
            guard let groupId = image.renderVersion?.renderVersionGroupId.trimmed.nilIfEmpty else {
                output.append((image.imageIndex, image))
                continue
            }
            var group = groups[groupId] ?? (image.imageIndex, [])
            group.sortIndex = min(group.sortIndex, image.imageIndex)
            group.images.append(image)
            groups[groupId] = group
        }
        for group in groups.values {
            let sorted = group.images.sorted {
                if $0.imageIndex == $1.imageIndex {
                    return $0.imageId < $1.imageId
                }
                return $0.imageIndex < $1.imageIndex
            }
            guard var selected = sorted.first(where: { $0.renderVersion?.isActive == true }) ?? sorted.first else { continue }
            selected.imageIndex = group.sortIndex
            output.append((group.sortIndex, selected))
        }
        return output.sorted {
            if $0.sortIndex == $1.sortIndex {
                return $0.image.imageId < $1.image.imageId
            }
            return $0.sortIndex < $1.sortIndex
        }.map(\.image)
    }

    private func theaterSectionsByCategory(for input: [ProjectLensHeroImage]) -> [LensConceptCategory: [ProjectLensHeroImage]] {
        var buckets: [LensConceptCategory: [ProjectLensHeroImage]] = [:]
        var legacyAreaCandidates: [ProjectLensHeroImage] = []
        for image in input.sorted(by: theaterImageSort) {
            let explicitKind = LensImageTaxonomyKind.normalized(image.imageKind)
            switch explicitKind {
            case LensImageTaxonomyKind.areaImage:
                buckets[.areas, default: []].append(image)
            case LensImageTaxonomyKind.sceneImage:
                buckets[.scenery, default: []].append(image)
            case LensImageTaxonomyKind.characterImage:
                buckets[.characters, default: []].append(image)
            case LensImageTaxonomyKind.objectImage:
                buckets[.objects, default: []].append(image)
            default:
                let category = LensConceptCategory.category(forRouteKey: image.sourceRouteKey)
                if category == .areas {
                    legacyAreaCandidates.append(image)
                } else {
                    buckets[category, default: []].append(image)
                }
            }
        }
        if (buckets[.areas] ?? []).isEmpty, let firstLegacyArea = legacyAreaCandidates.first {
            buckets[.areas] = [firstLegacyArea]
            buckets[.scenery, default: []].append(contentsOf: legacyAreaCandidates.dropFirst())
        } else {
            buckets[.scenery, default: []].append(contentsOf: legacyAreaCandidates)
        }
        for category in LensConceptCategory.allCases {
            buckets[category] = (buckets[category] ?? []).sorted(by: theaterImageSort)
        }
        return buckets
    }

    private func theaterImageSort(_ lhs: ProjectLensHeroImage, _ rhs: ProjectLensHeroImage) -> Bool {
        if lhs.imageIndex == rhs.imageIndex {
            return lhs.imageId < rhs.imageId
        }
        return lhs.imageIndex < rhs.imageIndex
    }

    private func sortedSceneFrameImages(_ images: [ProjectLensHeroImage]) -> [ProjectLensHeroImage] {
        images.sorted { lhs, rhs in
            let lhsRank = plannedSceneFrameSortRank(lhs)
            let rhsRank = plannedSceneFrameSortRank(rhs)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            return theaterImageSort(lhs, rhs)
        }
    }

    private func plannedSceneFrameSortRank(_ image: ProjectLensHeroImage) -> Int {
        switch image.status.trimmed.lowercased() {
        case "ready", "generating", "failed", "cancelled", "canceled":
            return 0
        default:
            return 1
        }
    }

    private var frameGridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: 196, maximum: 240),
                spacing: 12,
                alignment: .topLeading
            )
        ]
    }

    private func shouldShowAddTakeCard(in category: LensConceptCategory) -> Bool {
        onRenderNewTake != nil && (category == .scenery || category == .characters || category == .objects)
    }

    private func shouldShowBlankFrameCard(in category: LensConceptCategory) -> Bool {
        showsBlankFrameCreationCard
            && onRenderBlankFrame != nil
            && (category == .scenery || category == .characters || category == .objects)
    }

    /// Identity-grouped rendering for a character/object section: per-group header +
    /// that group's cards + a per-group add-take card, then a residual grid for any
    /// displayed take no group covers (grouping never hides work).
    private func groupedSectionBody(
        category: LensConceptCategory,
        displayImages: [ProjectLensHeroImage],
        fullSectionImages: [ProjectLensHeroImage]
    ) -> some View {
        let coveredIds = Set(identityGroups.flatMap { $0.takes.map(\.imageId) })
        let uncovered = displayImages.filter { !coveredIds.contains($0.imageId) }
        return VStack(alignment: .leading, spacing: 14) {
            ForEach(identityGroups) { group in
                identityGroupSection(
                    group,
                    displayImages: displayImages,
                    category: category,
                    fullSectionImages: fullSectionImages
                )
            }
            if !uncovered.isEmpty {
                identityGroupSection(
                    LensIdentityTakeGroup(
                        id: "uncovered_\(category.rawValue)",
                        displayName: category == .characters ? "Other character takes" : "Other object takes",
                        characterId: "",
                        referenceMediaIds: [],
                        descriptionPrompt: "",
                        membership: .unlabeled,
                        takes: uncovered
                    ),
                    displayImages: displayImages,
                    category: category,
                    fullSectionImages: fullSectionImages
                )
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func identityGroupSection(
        _ group: LensIdentityTakeGroup,
        displayImages: [ProjectLensHeroImage],
        category: LensConceptCategory,
        fullSectionImages: [ProjectLensHeroImage]
    ) -> some View {
        let groupIds = Set(group.takes.map(\.imageId))
        let groupImages = displayImages.filter { groupIds.contains($0.imageId) }
        let isRosterIdentity = !group.characterId.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            LensCastGroupHeader(
                group: group,
                candidates: identityReferenceCandidates,
                onOpen: (isRosterIdentity && onOpenIdentity != nil) ? { onOpenIdentity?(group) } : nil,
                onEnlargeThumbnail: { item in
                    onPreviewStyle(StyleImagePreviewRequest(
                        url: URL(fileURLWithPath: item.path).absoluteString,
                        label: group.displayName,
                        detail: item.filename
                    ))
                }
            )
            if groupImages.isEmpty {
                Text("No takes in this version yet.")
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(CanonColor.muted)
                    .padding(.leading, LensCastGroupHeader.thumbnailSide + 8)
            } else {
                LazyVGrid(columns: frameGridColumns, alignment: .leading, spacing: 12) {
                    ForEach(Array(groupImages.enumerated()), id: \.element.imageId) { index, image in
                        compositeCard(
                            image,
                            index: index,
                            category: category,
                            sectionImages: fullSectionImages
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if shouldShowAddTakeCard(in: category),
                       let template = groupImages.last(where: { $0.reframe == nil }) {
                        addTakeCard(
                            launch: .groupTake(groupName: group.displayName, template: template),
                            caption: "Take · \(group.displayName)",
                            help: "Render another \(group.displayName) take — seeded from this group's latest take"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// Pause/resume control shown while the board has an active render or parked pause.
    /// Pausing is cooperative: the render already in flight finishes and saves, then the
    /// chain waits before starting the next frame.
    private var pauseHeader: some View {
        HStack(spacing: 8) {
            Button {
                onTogglePause?()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text(isPaused ? "Resume" : "Pause")
                        .font(CanonType.interface(11, weight: .semibold))
                }
                .foregroundStyle(isPaused ? CanonColor.paper : CanonColor.brass)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(isPaused ? CanonColor.brass : CanonColor.brass.opacity(0.12))
                )
                .overlay(Capsule().stroke(CanonColor.brass.opacity(isPaused ? 0 : 0.55)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(isPaused
                ? "Resume all generations"
                : "Pause all generations — the render in flight finishes, then everything waits")
            Text(isPaused
                ? "Paused — the frame already rendering will finish, nothing new starts."
                : "Rendering — pausing lets the current frame finish, then holds the rest.")
                .font(CanonType.interface(10.5))
                .foregroundStyle(CanonColor.muted)
                .lineLimit(1)
            Spacer()
        }
    }

    private func compositeCard(
        _ image: ProjectLensHeroImage,
        index: Int,
        category: LensConceptCategory,
        sectionImages: [ProjectLensHeroImage]
    ) -> some View {
        let versions = generationVersions(for: image, in: allImages)
        let isVersionsExpanded = expandedVersionsImageId == image.imageId
        let cardSize = thumbnailSize(category: category)
        return VStack(alignment: .leading, spacing: 6) {
            ZStack {
                switch image.status {
                case "ready":
                    // Tap opens, drag sequences into a shot. A Button here would
                    // eat the drag, so open is a tap gesture that coexists with
                    // .draggable on the same view.
                    heroThumbnail(image, size: cardSize)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpenImage(image) }
                        .draggable(ShotFrameTransfer(frameImageId: image.imageId))
                case "generating":
                    shimmerCard(caption: generatingCaption(image))
                case "failed", "cancelled":
                    failedCard(image, category: category)
                default:
                    queuedCard(image, category: category)
                }
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .anchorPreference(
                key: LensReframeCardBoundsPreferenceKey.self,
                value: .bounds
            ) { anchor in
                [image.imageId: anchor]
            }
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(borderColor(image), lineWidth: image.status == "ready" ? 1 : 1.4)
            )
            .overlay(alignment: .topTrailing) {
                if image.status == "ready" {
                    keepStar(image)
                }
            }
            .overlay(alignment: .topLeading) {
                topLeadingThumbnailOverlay(
                    image: image,
                    versions: versions,
                    isVersionsExpanded: isVersionsExpanded
                )
            }
            .contextMenu {
                if onGatherFrame != nil || onGatherFrameToNewStage != nil {
                    ForEach(stageGatherTargets) { target in
                        Button {
                            onGatherFrame?(image, target.id)
                        } label: {
                            Label("Gather on \(target.title)", systemImage: "square.stack.3d.up")
                        }
                    }
                    Button {
                        onGatherFrameToNewStage?(image)
                    } label: {
                        Label("New stage from this frame", systemImage: "plus.rectangle.on.rectangle")
                    }
                }
                if let onDuplicateFrame {
                    Divider()
                    FrameActionsMenu(frame: image, onDuplicate: onDuplicateFrame)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if image.status == "ready", image.renderVersion == nil, onAnimateImage != nil {
                    cardPlayButton(
                        systemName: "play.fill",
                        help: "Animate this frame with WAN 2.5"
                    ) {
                        renderSetupImage = image
                    }
                }
            }
            cardFooter(image, index: index, displayWidth: cardSize.width)
        }
        .zIndex(isVersionsExpanded ? 100 : 0)
    }

    private func thumbnailSize(category: LensConceptCategory) -> CGSize {
        // 16:9 is the frame form, respected on any glance.
        CGSize(width: 196, height: 110)
    }

    /// Dashed creation card. The caption names what a click makes ("New frame",
    /// "Take · Bethany") so no launch mode is ever a surprise.
    private func addTakeCard(launch: FrameCreationContext, caption: String?, help: String) -> some View {
        Button {
            frameCreatorLaunch = launch
        } label: {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(CanonColor.hairlinePaper, style: StrokeStyle(lineWidth: 1.4, dash: [6, 5]))
                .background(CanonColor.paperInset.opacity(0.34), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    VStack(spacing: 6) {
                        LitIconView(icon: .add, size: 34)
                            .foregroundStyle(CanonColor.brass.opacity(0.86))
                        if let caption {
                            Text(caption.uppercased())
                                .font(CanonType.archive(7.5, weight: .semibold))
                                .kerning(1)
                                .foregroundStyle(CanonColor.muted)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                        }
                    }
                }
                .frame(width: 196, height: 148)
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Two-line footer: the title truncates, the qualifier (style name or beat — the
    /// information the anchor row exists to show) always renders whole.
    private func cardFooter(_ image: ProjectLensHeroImage, index: Int, displayWidth: CGFloat = 196) -> some View {
        let label = image.label.trimmed.isEmpty ? "Concept \(index + 1)" : image.label
        let parts = label.components(separatedBy: " · ")
        let title = parts.count > 1 ? parts.dropLast().joined(separator: " · ") : label
        let qualifier = parts.count > 1 ? parts.last ?? "" : ""
        // A planned scene frame decides its stack inside the Frame Creator, so the
        // provider/model line would pre-announce a choice not yet made; its footer
        // shows the authored @mentions instead.
        let isPlannedSceneFrame = LensConceptCategory.category(for: image) == .scenery
            && image.isPlanFulfillmentCandidate
        let mentionNames = isPlannedSceneFrame
            ? RosterMentionResolver.resolve(
                prompt: image.sourcePrompt.trimmed.nilIfEmpty ?? image.prompt,
                entries: mentionEntries
            ).mentions.map(\.name)
            : []
        return VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(CanonType.archive(9, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(CanonColor.ink.opacity(image.status == "ready" ? 0.75 : 0.5))
                .lineLimit(1)
            if !qualifier.isEmpty {
                Text(qualifier)
                    .font(CanonType.archive(8.5))
                    .kerning(0.4)
                    .foregroundStyle(CanonColor.brass.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if !mentionNames.isEmpty {
                HStack(spacing: 3) {
                    ForEach(mentionNames.prefix(3), id: \.self) { name in
                        Text("@\(name)")
                            .font(CanonType.archive(7.8, weight: .semibold))
                            .kerning(0.3)
                            .foregroundStyle(CanonColor.brass)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(CanonColor.brass.opacity(0.12)))
                            .lineLimit(1)
                    }
                    if mentionNames.count > 3 {
                        Text("+\(mentionNames.count - 3)")
                            .font(CanonType.archive(7.8, weight: .medium))
                            .foregroundStyle(CanonColor.ink.opacity(0.45))
                    }
                }
                .padding(.vertical, 1)
            }
            if !isPlannedSceneFrame {
                Text(renderMetadataLine(for: image))
                    .font(CanonType.archive(7.8, weight: .medium))
                    .kerning(0.25)
                    .foregroundStyle(CanonColor.ink.opacity(image.status == "ready" ? 0.46 : 0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            if let styleLine = styleMetadataLine(for: image) {
                Text(styleLine)
                    .font(CanonType.archive(7.8, weight: .medium))
                    .kerning(0.25)
                    .foregroundStyle(CanonColor.brass.opacity(image.status == "ready" ? 0.72 : 0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(maxWidth: displayWidth, alignment: .leading)
    }

    private func keepStar(_ image: ProjectLensHeroImage) -> some View {
        Button {
            onToggleKept(image)
        } label: {
            Image(systemName: image.kept == true ? "star.fill" : "star")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(image.kept == true ? CanonColor.softGold : .white)
                .shadow(color: .black.opacity(0.55), radius: 2)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(image.kept == true ? "Unkeep this concept" : "Keep this concept — mark it as one to follow")
    }

    private func topLeadingThumbnailOverlay(
        image: ProjectLensHeroImage,
        versions: [ProjectLensHeroImage],
        isVersionsExpanded: Bool
    ) -> some View {
        let hasVersions = versions.count > 1
        return VStack(alignment: .leading, spacing: 0) {
            if hasVersions {
                cardOverlayIconButton(
                    systemName: "rectangle.stack",
                    help: isVersionsExpanded ? "Hide versions" : "Show \(versions.count) versions",
                    isActive: isVersionsExpanded
                ) {
                    withAnimation(.easeOut(duration: 0.16)) {
                        expandedVersionsImageId = isVersionsExpanded ? nil : image.imageId
                    }
                }
            }
            if image.kept == true {
                Text("KEPT")
                    .font(CanonType.archive(7, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(CanonColor.paper)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(CanonColor.olive))
                    .padding(.leading, 5)
                    .padding(.top, hasVersions ? -2 : 5)
            }
            if let reframe = image.reframe {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 7, weight: .bold))
                    Text("REFRAME")
                        .font(CanonType.archive(7, weight: .bold))
                        .kerning(0.8)
                }
                .foregroundStyle(CanonColor.paper)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(CanonColor.brass.opacity(0.92)))
                .padding(.leading, 5)
                .padding(.top, hasVersions || image.kept == true ? 3 : 5)
                .help("\(reframe.modeLabel) — reframed from \(reframeParentLabel(for: reframe))")
            }
            if image.narrationArtifact?.isReady == true {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(CanonColor.paper)
                    .padding(4)
                    .background(Circle().fill(CanonColor.olive.opacity(0.9)))
                    .padding(.leading, 5)
                    .padding(.top, 3)
                    .help("This take has a narration — open it to listen")
            }
        }
    }

    private func generationVersionsSlice(
        selectedImage: ProjectLensHeroImage,
        versions: [ProjectLensHeroImage],
        parentSize: CGSize
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text("VERSIONS")
                        .font(CanonType.archive(7.5, weight: .bold))
                        .kerning(1.1)
                        .foregroundStyle(CanonColor.muted)
                    Text(versionGroupTitle(for: selectedImage))
                        .font(CanonType.interface(9.5, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(0.72))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("\(versions.count)")
                    .font(CanonType.archive(8, weight: .bold))
                    .foregroundStyle(CanonColor.brass)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(CanonColor.brass.opacity(0.12)))
                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        expandedVersionsImageId = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(0.48))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Close versions")
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(versions.enumerated()), id: \.element.imageId) { index, version in
                        generationVersionSliceCard(
                            version,
                            versionNumber: version.renderVersion?.versionNumber ?? (index + 1),
                            parentSize: parentSize
                        )
                    }
                }
            }
            .frame(height: versionsSliceScrollHeight(for: versions.count, parentSize: parentSize))
            .overlay(alignment: .trailing) {
                if versions.count > 1 {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(CanonColor.ink.opacity(0.18))
                        .frame(width: 2)
                        .padding(.vertical, 5)
                        .padding(.trailing, 2)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(width: parentSize.width + 12, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(CanonColor.paper.opacity(0.97)))
        .shadow(color: CanonColor.ink.opacity(0.08), radius: 8, x: 0, y: 4)
        .zIndex(4)
    }

    private func generationVersionSliceCard(
        _ image: ProjectLensHeroImage,
        versionNumber: Int,
        parentSize: CGSize
    ) -> some View {
        let cardWidth = parentSize.width
        let cardHeight = parentSize.height
        let isActive = image.renderVersion?.isActive == true
        return Button {
            if image.status == "ready", !image.imagePath.trimmed.isEmpty {
                onOpenImage(image)
            } else if isRenderableTake(image) {
                renderSetupImage = image
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    versionCardMedia(image)
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    Text("V\(max(1, versionNumber))")
                        .font(CanonType.archive(7.2, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.paper)
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .background(Capsule().fill(CanonColor.brass.opacity(0.92)))
                        .padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    if isActive {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                            Text("ACTIVE")
                                .font(CanonType.archive(6.5, weight: .bold))
                                .kerning(0.6)
                        }
                        .foregroundStyle(CanonColor.paper)
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                        .background(Capsule().fill(CanonColor.olive.opacity(0.92)))
                        .padding(6)
                    }
                }
                cardFooter(image, index: max(0, versionNumber - 1), displayWidth: cardWidth)
                    .padding(.horizontal, 4)
            }
            .padding(0)
            .frame(width: cardWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(versionRowHelp(image))
    }

    private func generationVersionCard(
        _ image: ProjectLensHeroImage,
        versionNumber: Int,
        isSelected: Bool
    ) -> some View {
        let cardWidth: CGFloat = 196 * 0.8
        let cardHeight: CGFloat = 148 * 0.8
        return Button {
            if image.status == "ready", !image.imagePath.trimmed.isEmpty {
                onOpenImage(image)
            } else if isRenderableTake(image) {
                renderSetupImage = image
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    versionCardMedia(image)
                }
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? CanonColor.brass.opacity(0.72) : borderColor(image), lineWidth: isSelected ? 1.4 : 1)
                )
                .overlay(alignment: .topLeading) {
                    Text("V\(max(1, versionNumber))")
                        .font(CanonType.archive(8, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.paper)
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .background(Capsule().fill(CanonColor.brass.opacity(0.92)))
                        .padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    if image.renderVersion?.isActive == true {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CanonColor.olive)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(CanonColor.paper.opacity(0.88)))
                            .padding(6)
                    }
                }
                cardFooter(image, index: max(0, versionNumber - 1), displayWidth: cardWidth)
            }
            .padding(6)
            .frame(width: cardWidth + 12, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? CanonColor.brass.opacity(0.12) : CanonColor.paperInset.opacity(0.46))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? CanonColor.brass.opacity(0.58) : CanonColor.hairlinePaper.opacity(0.58), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(versionRowHelp(image))
    }

    private func versionCardMedia(_ image: ProjectLensHeroImage) -> some View {
        ZStack {
            if image.status == "ready", let nsImage = StripThumbnailCache.shared.image(path: image.imagePath) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                CanonColor.paperInset.opacity(0.72)
                VStack(spacing: 6) {
                    if image.status == "generating" {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: versionPlaceholderIcon(image))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(image.status.trimmed.isEmpty ? "Planned" : image.status.capitalized)
                        .font(CanonType.archive(8, weight: .semibold))
                        .kerning(0.6)
                }
                .foregroundStyle(versionStatusColor(image).opacity(0.78))
            }
        }
        .clipped()
    }

    private func generationVersionRow(
        _ image: ProjectLensHeroImage,
        versionNumber: Int,
        isSelected: Bool
    ) -> some View {
        Button {
            if image.status == "ready", !image.imagePath.trimmed.isEmpty {
                onOpenImage(image)
            } else if isRenderableTake(image) {
                renderSetupImage = image
            }
        } label: {
            HStack(alignment: .center, spacing: 7) {
                versionThumbnail(image)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("V\(max(1, versionNumber))")
                            .font(CanonType.archive(8, weight: .bold))
                            .kerning(0.6)
                            .foregroundStyle(CanonColor.brass)
                        Text(versionRowTitle(image))
                            .font(CanonType.interface(9.6, weight: .semibold))
                            .foregroundStyle(CanonColor.ink.opacity(0.78))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    Text(renderMetadataLine(for: image))
                        .font(CanonType.archive(7.3, weight: .medium))
                        .kerning(0.2)
                        .foregroundStyle(CanonColor.ink.opacity(0.48))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let seedLine = versionSeedLine(image) {
                        Text(seedLine)
                            .font(CanonType.archive(7.2, weight: .medium))
                            .kerning(0.2)
                            .foregroundStyle(CanonColor.ink.opacity(0.45))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    if let styleLine = styleMetadataLine(for: image) {
                        Text(styleLine)
                            .font(CanonType.archive(7.2, weight: .medium))
                            .kerning(0.2)
                            .foregroundStyle(CanonColor.brass.opacity(0.7))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                Spacer(minLength: 2)
                versionStatusMark(image)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? CanonColor.brass.opacity(0.13) : CanonColor.paperInset.opacity(0.52))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? CanonColor.brass.opacity(0.62) : CanonColor.hairlinePaper.opacity(0.65), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(versionRowHelp(image))
    }

    private func versionThumbnail(_ image: ProjectLensHeroImage) -> some View {
        ZStack {
            if image.status == "ready", let nsImage = StripThumbnailCache.shared.image(path: image.imagePath, maxPixel: 160) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                CanonColor.paperInset
                if image.status == "generating" {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: versionPlaceholderIcon(image))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(versionStatusColor(image).opacity(0.75))
                }
            }
        }
        .frame(width: 52, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.ink.opacity(0.10), lineWidth: 1))
    }

    private func versionStatusMark(_ image: ProjectLensHeroImage) -> some View {
        Image(systemName: versionPlaceholderIcon(image))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(versionStatusColor(image))
            .frame(width: 17, height: 17)
            .background(Circle().fill(versionStatusColor(image).opacity(0.12)))
    }

    private func heroThumbnail(_ image: ProjectLensHeroImage, size: CGSize) -> some View {
        Color.clear
            .overlay(
                Group {
                    if let nsImage = StripThumbnailCache.shared.image(
                        path: image.imagePath,
                        maxPixel: Int(max(size.width, size.height) * 2)
                    ) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        CanonColor.paperInset
                    }
                }
            )
            .frame(width: size.width, height: size.height)
            .clipped()
            .transition(.opacity)
    }

    private func queuedCard(_ image: ProjectLensHeroImage, category: LensConceptCategory) -> some View {
        RoundedRectangle(cornerRadius: 9)
            .strokeBorder(CanonColor.hairlinePaper, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            .background(CanonColor.paperInset.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: isPaused ? "pause.circle" : "play.circle")
                        .font(.system(size: 15))
                    Text(isPaused ? "Paused" : "Planned")
                        .font(CanonType.archive(9, weight: .semibold))
                        .kerning(0.8)
                }
                .foregroundStyle(CanonColor.muted)
            )
            .overlay(alignment: .bottomTrailing) {
                if plannedFrameOpensCreator(image, category: category) {
                    frameCreatorPillButton(
                        help: "Open the Frame Creator to render this planned frame"
                    ) {
                        frameCreatorLaunch = .plannedFrame(image)
                    }
                } else if onRenderImage != nil, isRenderableTake(image) {
                    cardPlayButton(
                        systemName: "play.fill",
                        help: "Choose stack and render this take"
                    ) {
                        renderSetupImage = image
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if let onRemovePlannedTake, image.isPurePlan {
                    Button {
                        onRemovePlannedTake(image)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(CanonColor.ink.opacity(0.55))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(CanonColor.paper.opacity(0.9)))
                            .overlay(Circle().stroke(CanonColor.hairlinePaper))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .help("Drop this planned study — if it's the character's last take here, they leave the scene")
                }
            }
    }

    private var isRenderBlocked: Bool {
        isPaused || stillRenderBlockReason != nil
    }

    private var renderBlockerHelp: String? {
        if isPaused {
            return "Resume the paused generation before starting a new still render"
        }
        return stillRenderBlockReason
    }

    private func generationVersions(
        for image: ProjectLensHeroImage,
        in sectionImages: [ProjectLensHeroImage]
    ) -> [ProjectLensHeroImage] {
        let key = image.renderVersion?.renderVersionGroupId.trimmed ?? ""
        guard !key.isEmpty else { return [image] }
        return sectionImages
            .filter { $0.renderVersion?.renderVersionGroupId.trimmed == key }
            .sorted { lhs, rhs in
                let lhsVersion = lhs.renderVersion?.versionNumber ?? 0
                let rhsVersion = rhs.renderVersion?.versionNumber ?? 0
                if lhsVersion == rhsVersion {
                    if lhs.imageIndex == rhs.imageIndex {
                        return lhs.imageId < rhs.imageId
                    }
                    return lhs.imageIndex < rhs.imageIndex
                }
                return lhsVersion < rhsVersion
            }
    }

    /// Orders a section's cards: top-level frames first (existing order), then ALL
    /// reframes appended at the end in imageIndex order — so new reframes always
    /// land at a predictable place instead of re-seating under their parent.
    /// (Lineage-adjacent inline grouping was retired for now at the user's request.)
    private func sectionImagesWithReframesAppended(_ sectionImages: [ProjectLensHeroImage]) -> [ProjectLensHeroImage] {
        let topLevel = sectionImages.filter { $0.reframe == nil }
        let reframes = sectionImages
            .filter { $0.reframe != nil }
            .sorted(by: theaterImageSort)
        return topLevel + reframes
    }

    /// Resolves the display title of the frame a reframe was derived from, for the
    /// inline reframe badge's tooltip.
    private func reframeParentLabel(for reframe: LensReframeSpec) -> String {
        let parentId = reframe.parentImageId.trimmed
        guard !parentId.isEmpty,
              let parent = allImages.first(where: { $0.imageId == parentId }) else {
            return "the source frame"
        }
        let title = parent.label.components(separatedBy: " · ").first?.trimmed ?? parent.label.trimmed
        return title.isEmpty ? "the source frame" : title
    }

    private func versionGroupTitle(for image: ProjectLensHeroImage) -> String {
        let title = image.label.components(separatedBy: " · ").first?.trimmed ?? image.label.trimmed
        if !title.isEmpty { return title }
        if let subject = image.subject?.normalized(), !subject.description.isEmpty {
            return subject.description
        }
        return "Selected generation"
    }

    private func versionRowTitle(_ image: ProjectLensHeroImage) -> String {
        let parts = image.label.components(separatedBy: " · ").map { $0.trimmed }.filter { !$0.isEmpty }
        if parts.count > 1, let qualifier = parts.last {
            return qualifier
        }
        if let recipeLabel = image.renderRecipe?.normalized().label.trimmed, !recipeLabel.isEmpty {
            return recipeLabel
        }
        return image.provider.uppercased()
    }

    private func versionSeedLine(_ image: ProjectLensHeroImage) -> String? {
        guard let seed = image.renderVersion?.seed.trimmed.nilIfEmpty else { return nil }
        return "Seed · \(seed)"
    }

    private func versionRowHelp(_ image: ProjectLensHeroImage) -> String {
        switch image.status {
        case "ready":
            return "Open this version"
        case "generating":
            return "This version is rendering"
        case "failed", "cancelled":
            return "Open render setup for this version"
        default:
            return "Open render setup for this planned version"
        }
    }

    private func versionSliceScrollHeight(for versionCount: Int) -> CGFloat {
        min(max(CGFloat(versionCount) * 184, 186), 520)
    }

    private func versionsSliceScrollHeight(for versionCount: Int, parentSize: CGSize) -> CGFloat {
        let rowHeight = parentSize.height + 48
        let fullHeight = CGFloat(max(1, versionCount)) * rowHeight + CGFloat(max(0, versionCount - 1)) * 6
        return min(max(fullHeight, rowHeight), min(520, rowHeight * 2.35))
    }

    private func versionPlaceholderIcon(_ image: ProjectLensHeroImage) -> String {
        switch image.status {
        case "ready":
            return "checkmark"
        case "generating":
            return "clock.fill"
        case "failed", "cancelled":
            return "xmark"
        default:
            return "play.fill"
        }
    }

    private func versionStatusColor(_ image: ProjectLensHeroImage) -> Color {
        switch image.status {
        case "ready":
            return CanonColor.olive
        case "generating":
            return CanonColor.brass
        case "failed", "cancelled":
            return CanonColor.rust
        default:
            return CanonColor.muted
        }
    }

    private func cardPlayButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        cardOverlayIconButton(systemName: systemName, help: help, action: action)
    }

    /// The labeled Frame Creator CTA for planned scene frames — the tuned-render
    /// affordance, visibly distinct from the quick-render play circle.
    private func frameCreatorPillButton(help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("Frame Creator")
                    .font(CanonType.interface(10.5, weight: .semibold))
            }
            .foregroundStyle(CanonColor.paper)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Capsule().fill(CanonColor.brass))
            .shadow(color: CanonColor.ink.opacity(0.18), radius: 2, x: 0, y: 1)
            .padding(7)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func cardOverlayIconButton(
        systemName: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CanonColor.paper)
                .frame(width: 24, height: 24)
                .background(Circle().fill(isActive ? CanonColor.ink.opacity(0.88) : CanonColor.brass))
                .shadow(color: CanonColor.ink.opacity(0.18), radius: 2, x: 0, y: 1)
                .padding(7)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func openStylePicker(_ image: ProjectLensHeroImage) {
        selectedTakeStyleSlot = takeStyleSlot(for: image)
        selectedTakeStyleCatalogVersion = lens.body.styleTreatment?.catalogVersion ?? image.sourceRecipeVersion ?? ""
        stylePickerImage = image
    }

    private func takeStyleSlot(for image: ProjectLensHeroImage) -> LensStyleTreatmentSlot? {
        lensTakeStyleSlot(for: image, treatment: lens.body.styleTreatment)
    }

    private func shimmerCard(caption: String) -> some View {
        TimelineView(.animation(minimumInterval: 0.03)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            RoundedRectangle(cornerRadius: 9)
                .fill(CanonColor.paperInset.opacity(0.7))
                .overlay(
                    LinearGradient(
                        colors: [.clear, CanonColor.paper.opacity(0.85), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 90)
                    .offset(x: -140 + 380 * phase)
                )
                .clipShape(RoundedRectangle(cornerRadius: 9))
        }
        .overlay(
            VStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text(caption)
                    .font(CanonType.interface(10))
                    .foregroundStyle(CanonColor.ink.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        )
    }

    private func failedCard(_ image: ProjectLensHeroImage, category: LensConceptCategory) -> some View {
        let opensCreator = plannedFrameOpensCreator(image, category: category)
        return VStack(spacing: 7) {
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 15))
                .foregroundStyle(CanonColor.rust)
            Text(failedMessage(image))
                .font(CanonType.interface(10))
                .foregroundStyle(CanonColor.ink.opacity(0.7))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                // Two lines cannot hold a quoted refusal explanation; the
                // full message must stay reachable on hover.
                .help(failedMessage(image))
            if opensCreator || (onRenderImage != nil && isRenderableTake(image)) {
                Button {
                    if opensCreator {
                        frameCreatorLaunch = .plannedFrame(image)
                    } else {
                        renderSetupImage = image
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 7.5, weight: .bold))
                        Text("RETRY")
                            .font(CanonType.archive(8, weight: .semibold))
                            .kerning(1)
                    }
                    .foregroundStyle(CanonColor.paper)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(CanonColor.rust.opacity(0.9)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(opensCreator
                    ? "Reopen the Frame Creator and render this planned frame again"
                    : "Choose stack and render this take again")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanonColor.rust.opacity(0.07))
        .overlay(alignment: .bottomTrailing) {
            if opensCreator {
                frameCreatorPillButton(
                    help: "Open the Frame Creator to render this planned frame"
                ) {
                    frameCreatorLaunch = .plannedFrame(image)
                }
            } else if onRenderImage != nil, isRenderableTake(image) {
                cardPlayButton(
                    systemName: "play.fill",
                    help: "Choose stack and render this take"
                ) {
                    renderSetupImage = image
                }
            }
        }
    }

    private func failedMessage(_ image: ProjectLensHeroImage) -> String {
        let message = image.errorMessage.trimmed
        if message.lowercased().hasPrefix("rendering was interrupted") {
            return "Rendering was interrupted for this media."
        }
        return message.isEmpty ? "Rendering failed." : message
    }

    private func generatingCaption(_ image: ProjectLensHeroImage) -> String {
        let label = image.label.trimmed.isEmpty ? "concept" : image.label
        let priorReady = images.filter { $0.status == "ready" && $0.imageIndex < image.imageIndex }.count
        if priorReady == 0 {
            return "Rendering \(label)"
        }
        if isSequence, LensConceptCategory.category(for: image) == .scenery {
            return "Rendering \(label) — advancing from the previous stop"
        }
        return "Rendering \(label) — world continuity from \(priorReady) earlier render\(priorReady == 1 ? "" : "s")"
    }

    private func borderColor(_ image: ProjectLensHeroImage) -> Color {
        switch image.status {
        case "ready": return image.kept == true ? CanonColor.olive.opacity(0.7) : CanonColor.hairlinePaper
        case "failed", "cancelled": return CanonColor.rust.opacity(0.55)
        case "generating": return CanonColor.brass.opacity(0.6)
        default: return CanonColor.hairlinePaper.opacity(0.7)
        }
    }

    private func isRenderableTake(_ image: ProjectLensHeroImage) -> Bool {
        image.status != "ready" && image.status != "generating"
    }

    /// Planned scene frames route to the Frame Creator (tuned render + in-place
    /// fulfillment); every other category keeps the quick-render popover.
    private func plannedFrameOpensCreator(_ image: ProjectLensHeroImage, category: LensConceptCategory) -> Bool {
        onFulfillPlannedFrame != nil && category == .scenery && image.isPlanFulfillmentCandidate
    }

    private struct SceneryPlaceGroup: Identifiable {
        let id: Int
        let caption: String
        let entries: [(index: Int, image: ProjectLensHeroImage)]
        var showsBlankFrameCard = false
    }

    /// The FRAMES strip grouped by place: first-appearance order of each frame's
    /// area, captioned with its place name; frames owned by no captioned area keep a
    /// caption-less group so grouping never hides work. The blank "+" card rides the
    /// last group.
    private func sceneryPlaceGroups(_ images: [ProjectLensHeroImage]) -> [SceneryPlaceGroup] {
        var order: [String] = []
        var byKey: [String: [(Int, ProjectLensHeroImage)]] = [:]
        for (index, image) in images.enumerated() {
            let key = placeCaptionsByAreaId[image.areaId] != nil ? image.areaId : ""
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append((index, image))
        }
        var groups = order.enumerated().map { groupIndex, key in
            SceneryPlaceGroup(
                id: groupIndex,
                caption: key.isEmpty ? "" : (placeCaptionsByAreaId[key] ?? ""),
                entries: (byKey[key] ?? []).map { (index: $0.0, image: $0.1) }
            )
        }
        if groups.isEmpty {
            groups = [SceneryPlaceGroup(id: 0, caption: "", entries: [])]
        }
        groups[groups.count - 1].showsBlankFrameCard = true
        return groups
    }

    private func renderScope(for category: LensConceptCategory) -> LensMediaRenderScope {
        switch category {
        case .characters:
            return .characters
        case .objects:
            return .objects
        case .areas, .scenery, .legacy:
            return .scene
        }
    }

    private func renderMetadataLine(for image: ProjectLensHeroImage) -> String {
        let recipe = image.renderRecipe?.normalized()
        let label = recipe?.label.trimmed.isEmpty == false ? recipe?.label ?? "" : image.label
        let model = recipe?.model.trimmed.isEmpty == false ? recipe?.model ?? "" : image.model
        return uniqueNonEmpty([label.trimmed.isEmpty ? "Scene Plan Stack" : label, model]).joined(separator: " · ")
    }

    private func styleMetadataLine(for image: ProjectLensHeroImage) -> String? {
        guard let style = image.styleAuthorities.first?.normalized(),
              !style.title.trimmed.isEmpty else {
            return nil
        }
        return "Style · \(style.title)"
    }
}

struct LensTakeStylePickerModal: View {
    let image: ProjectLensHeroImage
    @Binding var selectedSlot: LensStyleTreatmentSlot?
    @Binding var catalogVersion: String
    var onApply: () -> Void
    var onCancel: () -> Void
    var onPreviewStyle: (StyleImagePreviewRequest) -> Void

    @State private var unusedPrimarySlot: LensStyleTreatmentSlot?
    @State private var unusedAccentSlots: [LensStyleTreatmentSlot] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit Style")
                        .font(CanonType.interface(17, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    Text(image.label.trimmed.isEmpty ? "This take only" : "\(image.label) · this take only")
                        .font(CanonType.archive(9.5, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.muted)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(0.55))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(16)

            Rectangle().fill(CanonColor.hairlinePaper).frame(height: 1)

            LensStyleBrowserPanel(
                primarySlot: $unusedPrimarySlot,
                accentSlots: $unusedAccentSlots,
                catalogVersion: $catalogVersion,
                onPreviewStyle: onPreviewStyle,
                selectedStyleSlot: $selectedSlot
            )
            .frame(width: 940, height: 610)

            Rectangle().fill(CanonColor.hairlinePaper).frame(height: 1)

            HStack(spacing: 10) {
                if let selectedSlot {
                    Text("Selected · \(selectedSlot.label)")
                        .font(CanonType.interface(11, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(0.72))
                        .lineLimit(1)
                } else {
                    Text("Choose one catalog style for this take.")
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.muted)
                }
                Spacer()
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(CanonType.interface(11, weight: .semibold))
                .foregroundStyle(CanonColor.ink.opacity(0.66))
                .frame(height: 30)

                Button {
                    onApply()
                } label: {
                    Text("Apply Style")
                        .font(CanonType.interface(11.5, weight: .semibold))
                        .foregroundStyle(CanonColor.paper)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 7).fill(CanonColor.brass))
                }
                .buttonStyle(.plain)
                .disabled(selectedSlot == nil)
                .opacity(selectedSlot == nil ? 0.45 : 1)
            }
            .padding(16)
        }
        .background(CanonColor.paper)
    }
}
