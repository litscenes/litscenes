import SwiftUI

enum ScenesV2Metrics {
    /// The ledger rail: 74pt filmstrip thumbs + two mono info lines + the
    /// header row, plus the canon scroller's track. Taller than the old
    /// poster rail on purpose — the rail carries the full survey (Option A,
    /// a locked design decision).
    static let railHeight: CGFloat = 104
    /// THE SEQUENCE ROW (hidden while the Output sequence is empty): the
    /// picks for the final video as their own ordered strip — restored
    /// after real-project use showed coins alone cannot carry
    /// "which scenes, in what order" at density — plus its scroller track.
    static let sequenceRowHeight: CGFloat = 90
}

/// CutStripView's `.box` layout anchors its frames row's top edge here —
/// everything above that edge (chrome bar, shot name, model row, play
/// controls) is the header the page may carry above the fold before the
/// sticky block holds. An anchor, not a named-space frame: anchors resolve
/// in the reader's own geometry (the LensReframeCardBounds precedent), so
/// the measurement cannot silently die to a missing coordinate space.
struct ScenesV2StageStripTopKey: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = nextValue() ?? value
    }
}

/// THE LATE PIN: the stage holds only after its shot
/// header (chrome bar, name, model row, play controls) has scrolled above
/// the fold, so the pinned remainder is the strip + footer + chips. This is
/// offset-sticky with ONE rendering home: the block keeps its flow slot —
/// the page stack must stay a PLAIN VStack, because a lazy container would
/// cull the block once its slot left the viewport and reset the strip's
/// @State — and only its content offsets, so focus, drops, and state never
/// duplicate. The zero-height marker measures the flow position while the
/// offset rides beside it, so the measurement never feeds back.
private struct ScenesV2StickyStageBlock<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var flowMinY: CGFloat = 0
    @State private var pinAllowance: CGFloat = 0

    private var stickOffset: CGFloat {
        max(0, -flowMinY - pinAllowance)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(height: 0)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .scrollView).minY
                } action: { minY in
                    flowMinY = minY
                }
            content
                .overlayPreferenceValue(ScenesV2StageStripTopKey.self) { anchor in
                    GeometryReader { proxy in
                        let stripTop = anchor.map { proxy[$0].y }
                        Color.clear
                            .onAppear { pinAllowance = max(0, stripTop ?? 0) }
                            .onChange(of: stripTop) { _, newValue in
                                pinAllowance = max(0, newValue ?? 0)
                            }
                    }
                    .allowsHitTesting(false)
                }
                .offset(y: stickOffset)
        }
    }
}

/// A requested Ready Timeline removal that would destroy configured Reel
/// transitions — held for the confirm alert (seams key on the entry id; a
/// re-add mints a fresh one, so the loss is permanent).
private struct PendingReadyUnmark: Identifiable {
    let shotId: String
    let displayName: String
    let seamCount: Int
    var id: String { shotId }
}

/// SCENES v2: the fixed workbench (Option A, a locked design). The
/// LEDGER RAIL — every scene of the loaded project as a rich survey card
/// (micro-filmstrip, status edge, live render progress, ledger line,
/// sequence coin) — over ONE hero stage showing the selected scene at full
/// available canvas width, over the filtered Source pool, with the shared
/// production-context sidebar at the right. Selection is a radio: click a rail
/// card, the stage shows it; the two working boxes and the separate Ready
/// Timeline band are deleted (sequence membership reads as coins on the rail
/// and PLAY ALL lives in the rail header). A "Scene" here is a ProjectShot;
/// the primary lens is the shared context container (its newest media version
/// is the law for both the pool and sidebar). Single-project by design: projects
/// switch with one click in the app sidebar, and the staged selection is
/// remembered per project.
struct ScenesV2WorkbenchView: View {
    @ObservedObject var library: LibraryEngine
    @ObservedObject var session: ScenesV2Session
    var onOpenMediaItem: (String) -> Void
    var onOpenAppSettings: () -> Void
    /// The guided stage's Open Story exit — switches to the Story tab.
    var onOpenStory: () -> Void = {}
    /// The readiness band's exit — switches to the Characters tab.
    var onOpenCharacters: () -> Void = {}
    /// A character card in the shared sidebar opens that character on its tab.
    var onOpenCharacter: (String) -> Void = { _ in }

    @Environment(\.undoManager) private var undoManager
    @StateObject private var pictureUndo = ShotPictureUndoCoordinator()
    /// Seam edits from the sequence row ride the same snapshot Undo as the
    /// Reel's own strip — one ⌘Z vocabulary for reel state everywhere.
    @StateObject private var reelUndo = FinalsReelUndoCoordinator()
    @State private var shotVideoRequest: ShotVideoRequest?
    @State private var jovilabeRequest: JovilabeRequest?
    @State private var clipInspectorRequest: ShotClipInspectorRequest?
    @State private var excursionRequest: ExcursionLaunchRequest?
    @State private var frameCreatorLaunch: WorkbenchFrameCreatorLaunch?
    @State private var styleImagePreview: StyleImagePreviewRequest?
    @State private var heroPreviewRequest: LensHeroPreviewRequest?
    @State private var heroPreviewNavigation: HeroPreviewCutNavigation?
    @State private var narrationFocusRequest: ShotNarrationFocusRequest?
    @State private var renderPlanFocusRequest: ShotRenderPlanFocusRequest?
    @State private var finalsReelRequest: FinalsReelRequest?
    @State private var pendingReadyUnmark: PendingReadyUnmark?
    @State private var localNotice = ""
    @State private var workspaceSize: CGSize = .zero
    @State private var selectedContextSidebarTab: ScenesContextSidebarTab = .characters
    @State private var isContextSidebarCollapsed = false
    @State private var rosterRequest: RosterDetailRequest?
    @State private var expandedPlaceId: String?
    @State private var isTerrainMapPresented = false
    /// The guided stage's chapter chips: the full-snapshot scene titles for
    /// the preferred Story (the v1 landing-card caching pattern — one sync
    /// disk read per story version, deferred off the body pass).
    @State private var storySnapshotTitles: [String] = []
    @State private var storySnapshotKey = ""

    /// v2 has no lens picker: the first lens is the container, its newest
    /// media version the displayed one.
    private var primaryLens: ProjectLens? {
        library.projectLenses.lenses.first
    }

    private var newestVersionId: String {
        primaryLens?.mediaVersionIds.last ?? ""
    }

    private var expandedPlace: ProjectPlace? {
        expandedPlaceId.flatMap { library.projectPlaces.place(withId: $0) }
    }

    var body: some View {
        let frameLookup = library.projectWideFrameLookup
        let mediaLookup = Dictionary(
            library.items.map { ($0.mediaId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // Pool hygiene (v2 only — the shared law itself is untouched):
        // planned frames belong to the guided stage, never the pool.
        // Kind hygiene (v2 only): derived identity/project images are not
        // source material either. Inventory (v2 only): every source photo is
        // ONE Frame tile — THE ADOPTED PHOTO LAW (AdoptedPhotoFrames.swift).
        let poolInputs = scenesV2PoolInputs(
            displayedFrames: scenesV2PoolSourceFrames(primaryLens?.heroImages(mediaVersion: newestVersionId) ?? []),
            projectWideFrames: scenesV2PoolSourceFrames(Array(frameLookup.values)),
            items: scenesV2SourceMaterialItems(library.items)
        )
        let actions = boxActions(frameLookup: frameLookup, mediaLookup: mediaLookup)
        let sequenceCardsValue = sequenceCards(frameLookup: frameLookup)
        ZStack {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    workbenchScroll(
                        frameLookup: frameLookup,
                        mediaLookup: mediaLookup,
                        poolInputs: poolInputs,
                        actions: actions,
                        sequenceCards: sequenceCardsValue
                    )
                    statusLine
                }
                if let primaryLens {
                    Rectangle()
                        .fill(CanonColor.hairlinePaper)
                        .frame(width: 1)
                        .allowsHitTesting(false)
                    ScenesContextSidebarView(
                        library: library,
                        lens: primaryLens,
                        versionId: newestVersionId,
                        selectedTab: $selectedContextSidebarTab,
                        isCollapsed: $isContextSidebarCollapsed,
                        onOpenFrame: { heroImage in
                            openFrameDetail(heroImage, navigation: nil)
                        },
                        onOpenRoster: { rosterRequest = $0 },
                        onPreviewStyle: { styleImagePreview = $0 },
                        onOpenPlace: { placeId in
                            withAnimation(.easeOut(duration: 0.2)) { expandedPlaceId = placeId }
                        },
                        onOpenWorldMap: {
                            withAnimation(.easeOut(duration: 0.2)) { isTerrainMapPresented = true }
                        },
                        onContentChanged: {},
                        onOpenAppSettings: onOpenAppSettings,
                        onOpenCharacter: onOpenCharacter
                    )
                }
            }
            .animation(.easeOut(duration: 0.22), value: sequenceCardsValue.isEmpty)
            if let expandedPlace, let primaryLens {
                HStack(spacing: 0) {
                    Color.black.opacity(0.16)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.18)) { expandedPlaceId = nil }
                        }
                    ScenesPlaceDetailView(
                        library: library,
                        lens: primaryLens,
                        versionId: newestVersionId,
                        place: expandedPlace,
                        onClose: {
                            withAnimation(.easeOut(duration: 0.18)) { expandedPlaceId = nil }
                        },
                        onLaunchFrameCreator: { context in
                            expandedPlaceId = nil
                            frameCreatorLaunch = WorkbenchFrameCreatorLaunch(
                                lensId: primaryLens.lensId,
                                context: context
                            )
                        },
                        onOpenFrame: { heroImage in
                            expandedPlaceId = nil
                            openFrameDetail(heroImage, navigation: nil)
                        }
                    )
                    .frame(width: 620)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(CanonColor.hairlinePaper).frame(width: 1)
                    }
                }
                .transition(.opacity)
                .zIndex(30)
            }
            if isTerrainMapPresented {
                TerrainMapView(library: library) {
                    withAnimation(.easeOut(duration: 0.18)) { isTerrainMapPresented = false }
                }
                .zIndex(31)
            }
            HeroPreviewModalHost(
                library: library,
                request: $heroPreviewRequest,
                cutNavigation: $heroPreviewNavigation,
                onLaunchFrameCreator: { frameCreatorLaunch = $0 },
                onEnterExcursion: { excursionRequest = $0 },
                onStartScene: { imageId in
                    startNewScene(with: ShotFrameTransfer(frameImageId: imageId))
                },
                onOpenAppSettings: onOpenAppSettings
            )
            .zIndex(20)
            if let excursionRequest {
                ExcursionModeView(
                    library: library,
                    request: excursionRequest,
                    startPunchIn: { afterEntryId, parentImageId, spec, onPlaced in
                        await startPunchIn(
                            cutId: excursionRequest.cutId,
                            afterEntryId: afterEntryId,
                            parentImageId: parentImageId,
                            spec: spec,
                            onPlaced: onPlaced
                        )
                    },
                    onExit: { self.excursionRequest = nil }
                )
                .transition(.opacity)
                .zIndex(30)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { workspaceSize = proxy.size }
                    .onChange(of: proxy.size) { _, newSize in workspaceSize = newSize }
            }
        }
        .foregroundStyle(CanonColor.ink)
        .tint(CanonColor.focusBlue)
        .environment(\.colorScheme, .light)
        .sheet(item: $frameCreatorLaunch) { launch in
            if let lens = library.projectLenses.lenses.first(where: { $0.lensId == launch.lensId }) {
                FrameCreatorModalHost(
                    library: library,
                    lens: lens,
                    launch: launch,
                    workspaceSize: workspaceSize,
                    onDismiss: { frameCreatorLaunch = nil },
                    onPreviewStyle: { styleImagePreview = $0 },
                    onOpenAppSettings: onOpenAppSettings
                )
            }
        }
        .sheet(item: $styleImagePreview) { request in
            StyleImagePreviewModal(request: request)
        }
        .sheet(item: $rosterRequest) { request in
            ProjectRosterView(
                library: library,
                initialKind: request.kind,
                initialSelectedEntryId: request.entryId
            )
        }
        .sheet(item: $jovilabeRequest) { request in
            JovilabeSheetHost(
                library: library,
                request: request,
                workspaceSize: workspaceSize,
                onDismiss: { jovilabeRequest = nil },
                onOpenFrame: { heroImage in openFrameDetail(heroImage, navigation: nil) }
            )
        }
        .sheet(item: $shotVideoRequest) { request in
            ShotPlayerSheetHost(
                library: library,
                request: request,
                onDismiss: { shotVideoRequest = nil },
                onReopen: { shotVideoRequest = $0 },
                onFocusNarration: { shotId in
                    shotVideoRequest = nil
                    narrationFocusRequest = ShotNarrationFocusRequest(shotId: shotId)
                }
            )
        }
        .sheet(item: $clipInspectorRequest) { request in
            ShotClipInspectorView(
                library: library,
                shotId: request.shotId,
                entryId: request.entryId,
                onSpawnFrame: { seed in
                    clipInspectorRequest = nil
                    if let lensId = primaryLens?.lensId {
                        frameCreatorLaunch = WorkbenchFrameCreatorLaunch(
                            lensId: lensId,
                            context: .clipMoment(seed)
                        )
                    }
                },
                onReviewExtension: { preparation in
                    clipInspectorRequest = nil
                    session.select(preparation.shotId)
                    renderPlanFocusRequest = ShotRenderPlanFocusRequest(
                        shotId: preparation.shotId,
                        segmentPlacementKey: preparation.segmentPlacementKey
                    )
                },
                onClose: { clipInspectorRequest = nil }
            )
        }
        .sheet(item: $finalsReelRequest) { _ in
            FinalsReelPlayerView(
                library: library,
                onClose: { finalsReelRequest = nil }
            )
        }
        .alert(
            "Remove from the Output sequence?",
            isPresented: Binding(
                get: { pendingReadyUnmark != nil },
                set: { if !$0 { pendingReadyUnmark = nil } }
            ),
            presenting: pendingReadyUnmark
        ) { pending in
            Button("Remove and lose \(pending.seamCount == 1 ? "the transition" : "\(pending.seamCount) transitions")", role: .destructive) {
                library.unmarkSceneReady(shotId: pending.shotId)
                pendingReadyUnmark = nil
            }
            Button("Cancel", role: .cancel) {
                pendingReadyUnmark = nil
            }
        } message: { pending in
            Text("\(pending.displayName) anchors \(pending.seamCount == 1 ? "a configured Reel transition" : "\(pending.seamCount) configured Reel transitions"). Removing the Scene destroys \(pending.seamCount == 1 ? "it" : "them"), and re-adding the Scene will not bring \(pending.seamCount == 1 ? "it" : "them") back.")
        }
        .onAppear {
            reconcileSession()
            reelUndo.applyState = { snapshot in library.restoreReelState(snapshot) }
            // THE SCOPED STATUS: whatever the engine was saying when SCENES
            // appeared belongs to the previous tab.
            session.statusBaseline = library.aestheticStatus
            session.errorBaseline = library.lastError
            session.pruneSeenSuggestions(live: sheetSuggestionIds)
            // THE ENSURE PASS: characters with reference images get their first
            // suggestions without a click (once per session per identity).
            library.ensureCharacterFrameSuggestions()
            // Live FAL rates for the RENDER captions; cached ~a day, never blocking.
            Task { await library.refreshFALPricingIfStale() }
        }
        .onDisappear {
            session.markSuggestionsSeen(sheetSuggestionIds)
        }
        .onChange(of: library.currentProject?.projectId) { _, _ in
            reconcileSession()
        }
        .onChange(of: library.shotTimeline.visibleShots.map(\.shotId)) { _, ids in
            session.select(scenesV2ReconciledSelection(
                session.selectedSceneId,
                against: ids,
                readySceneIds: Set(library.outputSequence.shots.map(\.shotId)),
                seedsWhenEmpty: !session.selectionIsDeliberate,
                recentSceneIds: session.recentSceneIds
            ))
        }
        .task(id: storyTaskKey) {
            guard let entry = library.storyLibrary.preferredEntry else {
                storySnapshotTitles = []
                storySnapshotKey = ""
                return
            }
            let key = "\(entry.libraryEntryId):\(entry.currentVersionId)"
            let snapshot = library.sceneStorySnapshot(for: entry)
            storySnapshotTitles = snapshot?.scenes
                .sorted { $0.order < $1.order }
                .map { $0.title.trimmed }
                .filter { !$0.isEmpty } ?? []
            storySnapshotKey = key
        }
    }

    private var storyTaskKey: String {
        guard let entry = library.storyLibrary.preferredEntry else { return "" }
        return "\(entry.libraryEntryId):\(entry.currentVersionId)"
    }

    // MARK: Bands

    /// THE UNIFIED PAGE SCROLL (locked, including the late pin above):
    /// the whole tab is one vertical surface. The rail + sequence row scroll
    /// off the top as page content, and so does the stage's shot header —
    /// the sticky block holds only once the strip's top edge reaches the
    /// fold, so the pinned remainder is strip + footer + chips while the
    /// pool grid keeps scrolling beneath. Free scroll by law — anything may
    /// rest half-visible; no snap, no collapse-distance constants. The stack
    /// is deliberately NOT lazy (see ScenesV2StickyStageBlock); the grid's
    /// own LazyVGrids carry the virtualization.
    private func workbenchScroll(
        frameLookup: [String: ProjectLensHeroImage],
        mediaLookup: [String: MediaItemRecord],
        poolInputs: [StageInput],
        actions: CutStripActions,
        sequenceCards: [SequenceSceneCard]
    ) -> some View {
        ScrollViewReader { pageProxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    // Whisper + rail share the reveal id so SCENES ▴ always
                    // lands above both (the whisper is conditional and must
                    // never take the scroll target away with it).
                    // THE TOP BLOCK: the way in when no character can drive
                    // suggestions, and the bare rail once a Scene has rendered.
                    VStack(spacing: 0) {
                        if suggestionNotice == .createCharacter {
                            createCharacterNoticeBand
                        }
                        if railIsVisible {
                            railBand(frameLookup: frameLookup, mediaLookup: mediaLookup)
                        }
                    }
                    .id("v2PageTop")
                    if railIsVisible || suggestionNotice == .createCharacter {
                        Rectangle()
                            .fill(CanonColor.hairlinePaper)
                            .frame(height: 1)
                    }
                    if !sequenceCards.isEmpty {
                        ScenesSequenceRowView(
                            cards: sequenceCards,
                            selectedSceneId: session.selectedSceneId,
                            isExporting: library.isExportingForYouTube,
                            exportStatus: library.youtubeExportStatus,
                            onOpen: { session.select($0) },
                            onRemove: { requestUnmark(shotId: $0) },
                            onMove: { shotId, index in
                                library.moveReadyScene(shotId: shotId, toIndex: index)
                            },
                            onPlayAll: { finalsReelRequest = FinalsReelRequest() },
                            seams: sequenceSeamDisplays(cards: sequenceCards),
                            onSetSeam: { left, right, kind, frames in
                                commitSequenceSeam(left: left, right: right, kind: kind, frames: frames)
                            }
                        )
                        .frame(height: ScenesV2Metrics.sequenceRowHeight)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        Rectangle()
                            .fill(CanonColor.hairlinePaper)
                            .frame(height: 1)
                    }
                    ScenesV2StickyStageBlock {
                        stageAndPoolControls(
                            actions: actions,
                            poolInputs: poolInputs,
                            onRevealRail: {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    pageProxy.scrollTo("v2PageTop", anchor: .top)
                                }
                            }
                        )
                    }
                    .zIndex(1)
                    poolGridContent(
                        poolInputs: poolInputs,
                        frameLookup: frameLookup,
                        mediaLookup: mediaLookup
                    )
                }
            }
            .defaultScrollAnchor(.top)
        }
    }

    /// The sticky block's content: hero stage over the pool's chips/search.
    /// Opaque room paper by law — the grid scrolls UNDER this block, and the
    /// stage's own well and plate only cover their own bounds, so without
    /// this background the tiles ghost through the margins while it holds.
    private func stageAndPoolControls(
        actions: CutStripActions,
        poolInputs: [StageInput],
        onRevealRail: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            stageBand(actions: actions, poolInputs: poolInputs, onRevealRail: onRevealRail)
            ScenesV2PoolControlsRow(
                filter: $session.poolFilter,
                searchQuery: $session.poolSearchQuery
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
            Rectangle()
                .fill(CanonColor.hairlinePaper.opacity(0.5))
                .frame(height: 1)
        }
        .background(CanonColor.room)
    }

    /// THE WAY IN: when no character has a sheet or a source image, SCENES says
    /// so once, at the top, and points to CHARACTERS. Gone the moment a character
    /// has reference images.
    private var createCharacterNoticeBand: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.rectangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CanonColor.brass.opacity(0.8))
            Text(scenesV2CreateCharacterNotice)
                .font(CanonType.displayItalic(13))
                .foregroundStyle(CanonColor.bone.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button(action: onOpenCharacters) {
                Text("CHARACTERS →")
                    .font(CanonType.archive(8, weight: .bold))
                    .kerning(1.0)
                    .foregroundStyle(CanonColor.brass)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 7)
    }

    /// THE RAIL VISIBILITY LAW: the scene rail appears once any Scene has a
    /// completed render.
    private var railIsVisible: Bool {
        scenesV2RailIsVisible(badges: library.shotTimeline.visibleShots.map {
            sceneRenderBadgeLive(shot: $0, activeShotRenderId: library.activeShotRenderId)
        })
    }

    private var suggestingNames: [String] {
        library.suggestingCharacterIds
            .compactMap { library.projectCharacters.character(withId: $0)?.name }
            .sorted()
    }

    private var suggestionNotice: ScenesV2SuggestionNotice? {
        scenesV2SuggestionNotice(
            hasSuggestableCharacters: !library.suggestableCharacterIds.isEmpty,
            suggestingNames: suggestingNames,
            suggestionCount: spotlightFrames.planned.count
        )
    }

    /// The ledger rail, extracted so `body` stays type-checkable.
    private func railBand(
        frameLookup: [String: ProjectLensHeroImage],
        mediaLookup: [String: MediaItemRecord]
    ) -> some View {
        ScenesRailView(
            groups: railGroups(frameLookup: frameLookup, mediaLookup: mediaLookup),
            selectedSceneId: session.selectedSceneId,
            upNextSceneId: upNextSceneId,
            onOpenScene: { ref in
                guard ref.projectId == (library.currentProject?.projectId ?? "") else { return }
                session.select(ref.shotId)
            },
            onMoveScene: { shotId, index in
                library.moveShot(shotId: shotId, toVisibleIndex: index)
            },
            onCreateScene: createScene,
            onDropMaterial: { shotId, transfer in
                appendMaterial(to: shotId, transfer: transfer)
            },
            onSequenceStep: { shotId, delta in
                stepSequence(shotId: shotId, delta: delta)
            },
            onSequenceDrop: { draggedShotId, beforePosition in
                // THE COIN DROP lands BEFORE the target coin — the band's old
                // law; movingShot reads the target against the PRE-REMOVAL
                // order, so the 0-based position IS the index to pass.
                library.moveReadyScene(shotId: draggedShotId, toIndex: beforePosition)
            },
            onUnmark: { requestUnmark(shotId: $0) }
        )
        .frame(height: ScenesV2Metrics.railHeight)
    }

    /// The strip's height ceiling while the stage rides the pinned header:
    /// workspace height minus everything else the header must fit — box
    /// chrome + footer + paddings (~122), chips row (~46), status line (22)
    /// — and ~170pt of guaranteed pool reveal. Floors at 300 so a tiny
    /// window still shows a workable strip; `workspaceSize` is .zero on the
    /// first frame and degrades safely to the floor.
    private var stageStripCap: CGFloat {
        max(300, workspaceSize.height - 360)
    }

    /// The one hero stage. With zero Scenes it is the GUIDED STAGE — the
    /// journey surface (spotlight states from `scenesV2StageSpotlightState`);
    /// with Scenes it is the selected scene's box at full width, and an empty
    /// selection renders the honest plate (no selection / conveyor
    /// exhaustion — `scenesV2EmptyStagePlateCopy`).
    @ViewBuilder
    private func stageBand(
        actions: CutStripActions,
        poolInputs: [StageInput],
        onRevealRail: (() -> Void)? = nil
    ) -> some View {
        let visible = library.shotTimeline.visibleShots
        let spotlight = spotlightState(sceneCount: visible.count)
        if spotlight == .normalStage {
            let index = visible.firstIndex { $0.shotId == session.selectedSceneId }
            let shot = index.map { visible[$0] }
            let readyIds = Set(library.outputSequence.shots.map(\.shotId))
            SceneBoxView(
                shot: shot,
                visibleIndex: index ?? 0,
                poolInputs: poolInputs,
                actions: actions,
                isReady: shot.map { library.sceneIsMarkedReady(shotId: $0.shotId) } ?? false,
                canMarkReady: shot.map { library.sceneCanBeMarkedReady(shotId: $0.shotId) } ?? false,
                readyDisabledHelp: shot.map(readyDisabledHelp) ?? "",
                onAssignScene: { session.select($0) },
                onMarkReady: {
                    guard let shot else { return }
                    toggleSceneReady(shotId: shot.shotId)
                },
                maxStripHeight: stageStripCap,
                onRevealRail: onRevealRail,
                emptyPlateText: scenesV2EmptyStagePlateCopy(
                    allScenesMarkedReady: !visible.isEmpty && visible.allSatisfy { readyIds.contains($0.shotId) }
                ),
                emptySceneHintText: scenesV2EmptySceneHint(
                    suggestionCount: spotlightFrames.planned.count,
                    // Placeable Frames: renders plus every source photo (a photo is a Frame).
                    renderedCount: spotlightFrames.rendered.count
                        + scenesV2SourceMaterialItems(library.items).filter { $0.kind == .image }.count
                )
            )
            .padding(12)
        } else {
            spotlightBand(state: spotlight)
                .padding(12)
        }
    }

    // MARK: Guided stage

    /// The newest version's frames, partitioned once for the spotlight.
    private var spotlightFrames: (planned: [ProjectLensHeroImage], rendered: [ProjectLensHeroImage], generating: [ProjectLensHeroImage]) {
        let frames = primaryLens?.heroImages(mediaVersion: newestVersionId) ?? []
        return (
            planned: scenesV2CharacterSuggestions(frames),
            rendered: scenesV2RenderedFrames(frames),
            generating: frames.filter { $0.status == "generating" }
        )
    }

    private func spotlightState(sceneCount: Int) -> ScenesV2StageSpotlightState {
        let frames = spotlightFrames
        return scenesV2StageSpotlightState(
            hasLens: primaryLens != nil,
            isGoalReady: library.isGoalV2Ready,
            isPlanningActive: library.isGeneratingInitialDraftLenses,
            isRefreshActive: library.isReplanningLensFromStory,
            planFailed: library.initialDraftLensGenerationProgress.isFailed,
            plannedImageIdsInPlanOrder: frames.planned.map(\.imageId),
            renderedFrameCount: frames.rendered.count,
            sceneCount: sceneCount
        )
    }

    private func spotlightBand(state: ScenesV2StageSpotlightState) -> some View {
        let frames = spotlightFrames
        let signature = library.storyLibrary.preferredEntry.flatMap(storySignature(for:))
        return ScenesV2StageSpotlightView(
            state: state,
            chapterTitles: scenesV2StoryChapterTitles(
                snapshotTitlesInOrder: storySnapshotKey == storyTaskKey ? storySnapshotTitles : [],
                signatureSceneFunctions: signature?.sceneFunctionSequence ?? []
            ),
            plannedFrames: frames.planned,
            renderedFrames: frames.rendered,
            generatingFrames: frames.generating,
            accentSwatches: scenesV2StageAccentSwatches(primaryLens?.body.colorPalette ?? []),
            planningTitle: spotlightPlanningTitle,
            planningDetail: spotlightPlanningDetail,
            planBlockedReason: library.lensGenerationBlockers.first ?? "",
            staleNote: planStaleNote,
            onRefreshSuggestions: refreshFrameSuggestions,
            onPlanMoreFrames: planMoreFrames,
            onOpenStory: onOpenStory,
            onPlanFrames: { Task { _ = await library.planLens() } },
            onArtDirect: artDirectPlannedFrame,
            onRender: { renderSuggestion(imageId: $0.imageId) },
            renderCaption: renderCaption,
            renderBlockReason: renderBlockReason,
            characterNamesById: characterNamesById,
            showsCreateCharacterNotice: suggestionNotice == .createCharacter,
            suggestDisabledReason: moreSuggestionsDisabledReason,
            onOpenCharacters: onOpenCharacters,
            onSuggestFrames: suggestForAllCharacters,
            onStartFirstScene: startFirstSceneFromSpotlight,
            onCreateFrame: {
                guard let lens = primaryLens else { return }
                frameCreatorLaunch = WorkbenchFrameCreatorLaunch(
                    lensId: lens.lensId,
                    context: .shotFrame(appendToShotId: nil)
                )
            },
            onOpenFrame: { openFrameDetail($0, navigation: nil) }
        )
    }

    private var spotlightPlanningTitle: String {
        library.isReplanningLensFromStory
            ? library.lensPlanRefreshProgress.title
            : library.initialDraftLensGenerationProgress.title
    }

    private var spotlightPlanningDetail: String {
        library.isReplanningLensFromStory
            ? library.lensPlanRefreshProgress.detail
            : library.initialDraftLensGenerationProgress.detail
    }

    /// The stale note the spotlight and the whisper band both read.
    private var planStaleNote: (text: String, action: ScenesV2PlanStaleAction)? {
        scenesV2PlanStaleNote(
            staleness: library.currentFramePlanStaleness,
            decision: library.currentFramePlanRefreshDecision,
            isRefreshing: library.isReplanningLensFromStory,
            refreshFailed: library.lensPlanRefreshProgress.isFailed
        )
    }

    private func refreshFrameSuggestions() {
        Task { _ = await library.refreshFramePlanFromStory() }
    }

    private func planMoreFrames() {
        Task { _ = await library.planMoreFramesFromStory() }
    }

    // MARK: Suggested Frames

    private struct SuggestionData {
        var cards: [ScenesV2SuggestionCardModel] = []
        var byCharacterId: [String: [ScenesV2SuggestionCardModel]] = [:]
        var unseen: [(characterName: String, count: Int)] = []
    }

    private var characterNamesById: [String: String] {
        Dictionary(
            library.projectCharacters.characters.map { ($0.characterId, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Every sheet-driven suggestion id in the newest version (the NEW ribbon's
    /// universe).
    private var sheetSuggestionIds: Set<String> {
        Set(spotlightFrames.planned.filter(\.isSheetSuggestion).map(\.imageId))
    }

    /// Every suggestion card's copy, computed once per pass from the priority
    /// order. `primaryIsFilled` is false while the guided stage shows its own
    /// filled pill (one brass fill per page).
    private func suggestionData(primaryIsFilled: Bool) -> SuggestionData {
        let planned = spotlightFrames.planned
        guard let lens = primaryLens, !planned.isEmpty else { return SuggestionData() }
        let roster = library.projectCharacters.characters
        let namesById = characterNamesById
        let items = library.items
        let rosterByName = Dictionary(
            roster.map { ($0.name.trimmed.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let sheetByName = Dictionary(
            roster.map { ($0.name.trimmed.lowercased(), library.activeCharacterSheetItem(for: $0.characterId) != nil) },
            uniquingKeysWith: { first, _ in first }
        )
        let idByName = Dictionary(
            roster.map { ($0.name.trimmed.lowercased(), $0.characterId) },
            uniquingKeysWith: { first, _ in first }
        )
        func castMark(_ name: String) -> ScenesV2CastMark {
            let key = name.trimmed.lowercased()
            let character = rosterByName[key]
            let avatar = scenesV2CastAvatarSource(
                referenceMediaIds: character?.referenceMediaIds ?? [],
                activeSheetMediaId: character?.activeSheetMediaId,
                items: items
            )
            return ScenesV2CastMark(
                name: name,
                hasSheet: sheetByName[key] ?? false,
                avatarImagePath: avatar.path,
                avatarIsSheet: avatar.isSheet,
                hasSources: !(character?.referenceMediaIds ?? []).isEmpty
            )
        }
        let scenes = (lens.body.areas ?? []).flatMap(\.scenes)
        let sceneCast = Dictionary(
            scenes.map { ($0.sceneId, $0.cast.map(\.name).filter { !$0.trimmed.isEmpty }) },
            uniquingKeysWith: { first, _ in first }
        )
        var data = SuggestionData()
        var unseenByCharacter: [String: Int] = [:]
        for (index, row) in planned.enumerated() {
            let titles = scenesV2SuggestionTitle(label: row.label)
            let failed = row.status == "failed" || row.status == "cancelled"
            let kind = scenesV2SuggestionKind(imageKind: row.imageKind, isSheetSuggestion: row.isSheetSuggestion)
            let forId = row.suggestedForCharacterId ?? (kind == .study ? row.characterId : "")
            let forName = namesById[forId] ?? ""
            var names = sceneCast[row.sceneId] ?? []
            if !forName.isEmpty, !names.contains(where: { $0.caseInsensitiveCompare(forName) == .orderedSame }) {
                names.insert(forName, at: 0)
            }
            let isNew = row.isSheetSuggestion && !session.seenSuggestionIds.contains(row.imageId)
            let card = ScenesV2SuggestionCardModel(
                imageId: row.imageId,
                title: titles.title,
                beat: titles.beat,
                eyebrow: scenesV2SuggestionEyebrow(beat: titles.beat, forCharacterName: forName, isFailed: failed, isStudy: kind == .study),
                brief: scenesV2SuggestionBrief(sourcePrompt: row.sourcePrompt, prompt: row.prompt),
                cast: names.map(castMark),
                isFailed: failed,
                failureLine: failed ? scenesV2SuggestionFailureLine(errorMessage: row.errorMessage) : "",
                isNew: isNew,
                isPrimary: primaryIsFilled && index == 0,
                kind: kind
            )
            data.cards.append(card)
            var characterIds: [String] = []
            if !forId.isEmpty { characterIds.append(forId) }
            for name in names {
                if let id = idByName[name.trimmed.lowercased()], !characterIds.contains(id) {
                    characterIds.append(id)
                }
            }
            for id in characterIds {
                data.byCharacterId[id, default: []].append(card)
            }
            if isNew {
                unseenByCharacter[forId, default: 0] += 1
            }
        }
        data.unseen = unseenByCharacter.compactMap { id, count -> (characterName: String, count: Int)? in
            guard let name = namesById[id] else { return nil }
            return (characterName: name, count: count)
        }
        .sorted { $0.characterName < $1.characterName }
        return data
    }

    /// "<stack> · <price>" — stated before the click, never $0.
    private var renderCaption: String {
        let stack = library.defaultFrameStack()
        return scenesV2RenderCaption(
            stackLabel: stack?.label ?? "",
            priceNote: stack.map { library.priceNote(for: $0, attachesReferences: false) } ?? ""
        )
    }

    /// The engine's hard refusals, in words, before any click.
    private var renderBlockReason: String {
        if let reason = library.lensHeroTakeStartBlockReason { return reason }
        guard let stack = library.defaultFrameStack() else { return "Add an API key in App Settings to render" }
        return library.renderStackCredentialBlocker(for: stack) ?? ""
    }

    private var moreSuggestionsDisabledReason: String {
        if !library.suggestingCharacterIds.isEmpty { return "Suggesting Frames…" }
        if library.suggestableCharacterIds.isEmpty { return "No characters with reference images yet" }
        return library.characterFrameSuggestionBlockReason ?? ""
    }

    /// SUGGEST FRAMES / MORE SUGGESTIONS: every character with reference images,
    /// under the cap — text calls, no renders.
    private func suggestForAllCharacters() {
        Task { _ = await library.suggestFramesForAllSuggestableCharacters() }
    }

    /// What a ready pool tile offers on hover: add to the staged Scene when one
    /// is staged and editable, else start a Scene.
    private var tileAction: ScenesV2TileAction {
        let visible = library.shotTimeline.visibleShots
        guard let index = visible.firstIndex(where: { $0.shotId == session.selectedSceneId }) else {
            return .startScene
        }
        let shot = visible[index]
        let locked = library.activeShotRenderId == shot.shotId
            || shot.renderArtifact?.status == "generating"
            || (!shot.browsableRenderVersions.isEmpty && shotSuffixTailStartIndex(shot: shot) == nil)
        return scenesV2TileAction(stagedSceneName: sceneDisplayName(shot: shot, index: index), stagedSceneIsLocked: locked)
    }

    /// ONE explicit paid gesture: a card's RENDER. A refusal lands beside the
    /// card in words; a provider failure returns the row as a failed suggestion.
    private func renderSuggestion(imageId: String) {
        guard let lens = primaryLens else { return }
        session.suggestionRefusals[imageId] = nil
        session.markSuggestionsSeen([imageId])
        Task {
            let started = await library.renderPlannedFrameWithDefaults(lensId: lens.lensId, imageId: imageId)
            if !started {
                let words = library.aestheticStatus.trimmed.nilIfEmpty ?? library.lastError.trimmed
                session.suggestionRefusals[imageId] = words.isEmpty ? "The render did not start" : words
            }
        }
    }

    private func artDirectSuggestion(imageId: String) {
        guard let row = primaryLens?.heroImages.first(where: { $0.imageId == imageId }) else { return }
        artDirectPlannedFrame(row)
    }

    private func openBlankFrameCreator() {
        guard let lens = primaryLens else { return }
        frameCreatorLaunch = WorkbenchFrameCreatorLaunch(
            lensId: lens.lensId,
            context: .shotFrame(appendToShotId: nil)
        )
    }


    /// The v1 landing card's signature-resolution law, replicated so v1's
    /// file stays untouched: signature id match first, then project story id.
    private func storySignature(for entry: ProjectStoryLibraryEntry) -> StorySignatureDocument? {
        if !entry.storySignatureId.trimmed.isEmpty,
           let match = library.storySignatures.first(where: { $0.storySignatureId == entry.storySignatureId }) {
            return match
        }
        guard !entry.projectStoryId.trimmed.isEmpty else { return nil }
        return library.storySignatures.first(where: { $0.projectStoryId == entry.projectStoryId })
    }

    /// Opens the Frame Creator on a planned frame — the fulfillment submit
    /// path (`.plannedFrame` in FrameCreatorModalHost) renders it in place.
    private func artDirectPlannedFrame(_ heroImage: ProjectLensHeroImage) {
        guard let lens = primaryLens else { return }
        frameCreatorLaunch = WorkbenchFrameCreatorLaunch(
            lensId: lens.lensId,
            context: .plannedFrame(heroImage)
        )
    }

    /// The spotlight's first-Scene gesture: a Scene seeded with the first
    /// rendered Frame (never an empty shot — the empty-scene dead end is what
    /// this replaces). `createShot` owns the material law and refusals.
    private func startFirstSceneFromSpotlight() {
        guard let lens = primaryLens else { return }
        localNotice = ""
        let firstReady = spotlightFrames.rendered.first
        let shotId = firstReady.map {
            library.createShot(lensId: lens.lensId, withFrameImageId: $0.imageId)
        } ?? library.createShot(lensId: lens.lensId)
        if !shotId.isEmpty {
            session.select(shotId)
        }
    }

    /// The honest disabled reason: distinguish "video work in flight" from
    /// "no rendered take" — the old single message lied while re-rendering a
    /// scene that already had an older playable take.
    private func readyDisabledHelp(_ shot: ProjectShot) -> String {
        if shot.playableRenderVersion?.isReady == true {
            return "Video work is in flight for this Scene — wait for it to finish"
        }
        return "Needs a rendered take before it can be marked ready"
    }

    /// The READY button: marking stamps the sequence coin and runs the
    /// conveyor (the stage loads the next scene that still needs work, or
    /// empties honestly); un-marking leaves the stage alone and confirms
    /// first when configured transitions would be destroyed.
    private func toggleSceneReady(shotId: String) {
        if library.sceneIsMarkedReady(shotId: shotId) {
            requestUnmark(shotId: shotId)
            return
        }
        guard library.markSceneReady(shotId: shotId) else { return }
        let next = nextConveyorSceneId(
            visibleShotIds: library.shotTimeline.visibleShots.map(\.shotId),
            departedShotId: shotId,
            readyShotIds: Set(library.outputSequence.shots.map(\.shotId)),
            boxedShotIds: []
        )
        session.select(next ?? "")
    }

    /// THE UP NEXT HINT: the card the conveyor would load if the staged scene
    /// were marked ready now — computed with the same law AND the same
    /// precondition as the READY button (markable, not already in the
    /// sequence), so the chip never promises a jump the stage is refusing.
    private var upNextSceneId: String {
        let selected = session.selectedSceneId
        guard !selected.isEmpty,
              !library.sceneIsMarkedReady(shotId: selected),
              library.sceneCanBeMarkedReady(shotId: selected) else { return "" }
        return nextConveyorSceneId(
            visibleShotIds: library.shotTimeline.visibleShots.map(\.shotId),
            departedShotId: selected,
            readyShotIds: Set(library.outputSequence.shots.map(\.shotId)),
            boxedShotIds: [selected]
        ) ?? ""
    }

    /// Coin context-menu reorder: one step earlier/later in the Output
    /// sequence. `movingShot` reads the target against the PRE-removal order,
    /// so later-by-one is position + 2; the document clamps out-of-range.
    private func stepSequence(shotId: String, delta: Int) {
        guard let position = library.outputSequence.shots.firstIndex(where: { $0.shotId == shotId }) else {
            return
        }
        library.moveReadyScene(shotId: shotId, toIndex: delta < 0 ? position - 1 : position + 2)
    }

    /// THE SPRING-LOADED RAIL DROP (v1: drop = append at the end): source
    /// material dropped on a rail card lands at that scene's strip end. The
    /// ENGINE is the one gatekeeper — insertShotFrame/insertShotMedia run the
    /// freeze law themselves and speak their own refusals — so this neither
    /// re-derives the lock nor claims success the engine refused. It calls
    /// the engine directly (never the strip's touch-wrapped action closures,
    /// whose `markingRowActive` wrapper would select the target): the quiet
    /// send is the point — material moves without leaving the hero.
    private func appendMaterial(to shotId: String, transfer: ShotFrameTransfer) -> Bool {
        let visible = library.shotTimeline.visibleShots
        guard let index = visible.firstIndex(where: { $0.shotId == shotId }) else { return false }
        let shot = visible[index]
        let end = shot.entries.count
        let landed: Bool
        if transfer.isClipDrag {
            landed = library.insertShotMedia(
                shotId: shotId,
                mediaId: transfer.clipMediaId,
                at: end,
                lensId: primaryLens?.lensId ?? ""
            ) != nil
        } else if !transfer.frameImageId.trimmed.isEmpty {
            landed = library.insertShotFrame(shotId: shotId, frameImageId: transfer.frameImageId, at: end)
        } else {
            return false
        }
        if landed {
            showTransientNotice("Added to \(sceneDisplayName(shot: shot, index: index))")
        }
        return landed
    }

    /// Status-line confirmations are transient by law: they clear themselves
    /// so they can never mask live render progress or an engine refusal (the
    /// collectStatus pattern — never clear a message a later notice replaced).
    private func showTransientNotice(_ text: String) {
        localNotice = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if localNotice == text {
                localNotice = ""
            }
        }
    }

    /// Un-mark, confirming first when the pick anchors configured Reel
    /// transitions — seams key on the entry id, so removal destroys them and
    /// re-adding (a fresh entry id, deliberately) cannot bring them back.
    private func requestUnmark(shotId: String) {
        let seamCount = readySeamCount(shotId: shotId)
        guard seamCount > 0 else {
            library.unmarkSceneReady(shotId: shotId)
            return
        }
        let visible = library.shotTimeline.visibleShots
        let name = visible.firstIndex(where: { $0.shotId == shotId })
            .map { sceneDisplayName(shot: visible[$0], index: $0) } ?? "This Scene"
        pendingReadyUnmark = PendingReadyUnmark(shotId: shotId, displayName: name, seamCount: seamCount)
    }

    private func readySeamCount(shotId: String) -> Int {
        guard let entryId = library.outputSequence.shots.first(where: { $0.shotId == shotId })?.entryId else {
            return 0
        }
        return library.outputSequence.reelSeams
            .filter { $0.leftEntryId == entryId || $0.rightEntryId == entryId }
            .count
    }

    /// The pool grid as page-scroll content (the section body under the
    /// pinned stage header) — the grid's viewport IS the page scroll now.
    private func poolGridContent(
        poolInputs: [StageInput],
        frameLookup: [String: ProjectLensHeroImage],
        mediaLookup: [String: MediaItemRecord]
    ) -> some View {
        let visible = library.shotTimeline.visibleShots
        let readyFrameIds = Set(
            frameLookup.values
                .filter { $0.status == "ready" && !$0.imagePath.trimmed.isEmpty }
                .map(\.imageId)
        )
        let usage = ScenesV2PoolUsage(
            usedFrameIds: usedFrameImageIds(in: visible),
            usedClipIds: usedClipMediaIds(in: visible),
            boundaryFrameIds: boundaryFrameImageIds(shots: visible, readyFrameImageIds: readyFrameIds)
        )
        // The guided stage owns the page's brass fill while it shows; once a
        // Scene exists the first suggestion card carries it.
        let suggestions = suggestionData(primaryIsFilled: spotlightState(sceneCount: visible.count) == .normalStage)
        return ScenesV2PoolGridSections(
            filter: session.poolFilter,
            searchQuery: session.poolSearchQuery,
            inputs: poolInputs,
            usage: usage,
            frameLookup: frameLookup,
            mediaLookup: mediaLookup,
            characterGroups: primaryLens.map {
                library.lensCharacterTakeGroups(lens: $0, versionId: newestVersionId)
            } ?? [],
            objectGroups: primaryLens.map {
                library.lensObjectTakeGroups(lens: $0, versionId: newestVersionId)
            } ?? [],
            onOpenFrame: { openFrameDetail($0, navigation: nil) },
            onOpenMedia: onOpenMediaItem,
            onOpenPhotoAsFrame: openPhotoAsFrame(mediaId:),
            onStartNewScene: startNewScene(with:),
            showsSuggestions: primaryLens != nil,
            suggestions: suggestions.cards,
            suggestionsByCharacterId: suggestions.byCharacterId,
            suggestionRefusals: session.suggestionRefusals,
            renderCaption: renderCaption,
            renderBlockReason: renderBlockReason,
            moreSuggestionsDisabledReason: moreSuggestionsDisabledReason,
            accentSwatches: scenesV2StageAccentSwatches(primaryLens?.body.colorPalette ?? []),
            tileAction: tileAction,
            onRenderSuggestion: renderSuggestion(imageId:),
            onArtDirectSuggestion: artDirectSuggestion(imageId:),
            onMoreSuggestions: suggestForAllCharacters,
            onNewFrame: openBlankFrameCreator,
            onPlaceInStagedScene: { transfer in
                _ = appendMaterial(to: session.selectedSceneId, transfer: transfer)
            },
            suggestionNotice: suggestionNotice,
            onOpenCharacters: onOpenCharacters
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Text(statusText)
                .font(CanonType.archive(7.5, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(CanonColor.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(height: 22)
        .background(CanonColor.archiveWell)
        .overlay(alignment: .top) {
            Rectangle().fill(CanonColor.hairlineDark).frame(height: 1)
        }
    }

    private var statusText: String {
        if !localNotice.isEmpty { return localNotice }
        if !library.activeShotRenderId.isEmpty {
            let visible = library.shotTimeline.visibleShots
            if let index = visible.firstIndex(where: { $0.shotId == library.activeShotRenderId }) {
                let shot = visible[index]
                let progress = shot.renderArtifact?.progressText.trimmed.nilIfEmpty ?? "RENDERING"
                return "\(sceneDisplayName(shot: shot, index: index)) · \(progress)"
            }
        }
        // THE SCOPED STATUS: global engine words show here only once they
        // changed after this tab appeared.
        let error = scenesV2ScopedStatus(current: library.lastError, baseline: session.errorBaseline)
        if !error.isEmpty { return error }
        return scenesV2ScopedStatus(current: library.aestheticStatus, baseline: session.statusBaseline)
    }

    // MARK: Rail data

    /// Single-project by design: only the loaded project's scenes, composed
    /// live from engine state. Project switching is the app sidebar's click.
    private func railGroups(
        frameLookup: [String: ProjectLensHeroImage],
        mediaLookup: [String: MediaItemRecord]
    ) -> [ProjectSceneGroup] {
        guard let current = library.currentProject else { return [] }
        let currentId = current.projectId
        let (stillPaths, footageThumbs) = posterPathLookups(frameLookup: frameLookup)
        // Coin numerals number the RESOLVED sequence — entries whose shot has
        // left the visible timeline (mid-trash-cascade) are transient and
        // must not leave numbering gaps on the cards that remain.
        let visibleIds = Set(library.shotTimeline.visibleShots.map(\.shotId))
        let sequencePositions = Dictionary(
            library.outputSequence.shots
                .filter { visibleIds.contains($0.shotId) }
                .enumerated()
                .map { ($0.element.shotId, $0.offset + 1) },
            uniquingKeysWith: { first, _ in first }
        )
        let scenes = library.shotTimeline.visibleShots.enumerated().map { index, shot in
            let progress = sceneRenderProgress(shot: shot, activeShotRenderId: library.activeShotRenderId)
            return SceneIndexEntry(
                projectId: currentId,
                shotId: shot.shotId,
                displayName: sceneDisplayName(shot: shot, index: index),
                entryCount: shot.entries.count,
                posterCandidatePaths: scenePosterCandidatePaths(
                    entries: shot.entries,
                    frameStillPathById: stillPaths,
                    footageThumbnailPathByMediaId: footageThumbs
                ),
                badge: sceneRenderBadgeLive(shot: shot, activeShotRenderId: library.activeShotRenderId),
                ledgerLine: sceneLedgerLine(shot: shot, frameLookup: frameLookup, mediaLookup: mediaLookup),
                modelLabel: shot.renderStack.shortLabel.components(separatedBy: " · ").first ?? "",
                hasNarration: shot.narrationArtifact?.isReady == true,
                hasPlacedAudio: !shot.audioRegions.isEmpty || shot.audioMix.activeMicrophoneTake != nil,
                renderProgress: progress?.fraction,
                progressLabel: progress?.label ?? "",
                sequencePosition: sequencePositions[shot.shotId],
                isCombined: !shot.combinedSources.isEmpty
            )
        }
        return [ProjectSceneGroup(
            projectId: currentId,
            projectName: current.name,
            isLoaded: true,
            scenes: scenes,
            loadIssue: ""
        )]
    }

    /// THE SEQUENCE ROW's cards: the Output sequence in order, resolved
    /// against live visible scenes (the trash cascade prunes the document, so
    /// an unresolvable entry is transient — it simply doesn't render).
    /// Positions number the RESOLVED order, matching the rail coins.
    private func sequenceCards(frameLookup: [String: ProjectLensHeroImage]) -> [SequenceSceneCard] {
        let currentId = library.currentProject?.projectId ?? ""
        let visible = library.shotTimeline.visibleShots
        let (stillPaths, footageThumbs) = posterPathLookups(frameLookup: frameLookup)
        return library.outputSequence.shots
            .compactMap { entry -> (entry: OutputShotEntry, index: Int)? in
                guard let index = visible.firstIndex(where: { $0.shotId == entry.shotId }) else { return nil }
                return (entry, index)
            }
            .enumerated()
            .map { position, resolved in
                let shot = visible[resolved.index]
                return SequenceSceneCard(
                    entryId: resolved.entry.entryId,
                    projectId: currentId,
                    shotId: shot.shotId,
                    displayName: sceneDisplayName(shot: shot, index: resolved.index),
                    posterCandidatePaths: scenePosterCandidatePaths(
                        entries: shot.entries,
                        frameStillPathById: stillPaths,
                        footageThumbnailPathByMediaId: footageThumbs
                    ),
                    position: position + 1
                )
            }
    }

    /// The row's seam displays — REQUESTED state only (baked durations exist
    /// only while the Reel is open, so applied truth lives there). A gutter
    /// pair that is not adjacent in the DOCUMENT order (a sequenced scene is
    /// hidden from the rail) refuses authoring — its seam would go dormant
    /// the moment it was written.
    private func sequenceSeamDisplays(cards: [SequenceSceneCard]) -> [ReelSeamDisplay] {
        guard cards.count > 1 else { return [] }
        let docShots = library.outputSequence.shots
        let documentPairs = Set(zip(docShots.dropLast(), docShots.dropFirst()).map {
            "\($0.entryId)>\($1.entryId)"
        })
        return (0..<(cards.count - 1)).map { index in
            let left = cards[index].entryId
            let right = cards[index + 1].entryId
            let authored = library.outputSequence.reelSeams.first {
                $0.leftEntryId == left && $0.rightEntryId == right
            }
            return ReelSeamDisplay(
                leftEntryId: left,
                rightEntryId: right,
                requestedFrames: authored?.crossfadeFrames,
                appliedFrames: authored?.crossfadeFrames ?? 0,
                kind: authored?.kind ?? .crossfade,
                isEditable: documentPairs.contains("\(left)>\(right)")
            )
        }
    }

    /// Row seam edits ride the engine's one seam op and register on the
    /// shared reel Undo coordinator — ⌘Z works identically to the Reel's.
    private func commitSequenceSeam(left: String, right: String, kind: ReelSeamKind, frames: Int?) {
        guard let before = library.setReelSeam(
            leftEntryId: left,
            rightEntryId: right,
            kind: kind,
            crossfadeFrames: frames
        ) else { return }
        let new = ReelStateSnapshot(
            reelAudio: library.outputSequence.reelAudio,
            reelSeams: library.outputSequence.reelSeams,
            reelFadeInFrames: library.outputSequence.reelFadeInFrames,
            reelFadeOutFrames: library.outputSequence.reelFadeOutFrames
        )
        reelUndo.registerEdit(
            old: before,
            new: new,
            actionName: reelSeamUndoActionName(kind: kind, frames: frames),
            undoManager: undoManager
        )
    }

    private func posterPathLookups(
        frameLookup: [String: ProjectLensHeroImage]
    ) -> (stillPaths: [String: String], footageThumbs: [String: String]) {
        var stillPaths: [String: String] = [:]
        for image in frameLookup.values
        where image.status == "ready" && !image.imagePath.trimmed.isEmpty {
            stillPaths[image.imageId] = image.imagePath
        }
        var footageThumbs: [String: String] = [:]
        for item in library.items where !item.thumbnailPath.trimmed.isEmpty {
            footageThumbs[item.mediaId] = item.thumbnailPath
        }
        return (stillPaths, footageThumbs)
    }

    // MARK: Actions

    private func boxActions(
        frameLookup: [String: ProjectLensHeroImage],
        mediaLookup: [String: MediaItemRecord]
    ) -> CutStripActions {
        var surface = CutStripWorkbenchSurface(pictureUndo: pictureUndo)
        surface.openCutIds = session.selectedSceneId.isEmpty ? [] : [session.selectedSceneId]
        surface.narrationFocusRequest = narrationFocusRequest
        surface.renderPlanFocusRequest = renderPlanFocusRequest
        surface.undoManager = undoManager
        surface.onTouchCut = { cutId in
            session.select(cutId)
        }
        surface.onOpenPlayer = { shotVideoRequest = $0 }
        surface.onFocusNarration = { cutId in
            shotVideoRequest = nil
            narrationFocusRequest = ShotNarrationFocusRequest(shotId: cutId)
        }
        surface.onOpenJovilabe = { jovilabeRequest = JovilabeRequest(shotId: $0) }
        surface.onOpenClipInspector = { clipInspectorRequest = $0 }
        surface.onOpenFrameDetail = { cutId, entryId, heroImage in
            openFrameDetail(heroImage, navigation: HeroPreviewCutNavigation(cutId: cutId, entryId: entryId))
        }
        surface.onEnterExcursion = { excursionRequest = $0 }
        surface.onLaunchFrameCreator = { frameCreatorLaunch = $0 }
        return makeCutStripActions(
            library: library,
            lensId: primaryLens?.lensId ?? "",
            frameLookup: frameLookup,
            mediaLookup: mediaLookup,
            surface: surface
        )
    }

    /// THE ADOPTED PHOTO LAW at the click: a source photo opens as the Frame it
    /// is — adopted on first open (idempotent, no spend) so the detail overlay's
    /// Restyle / Variation / Animate act on a real row. Without a Scene Plan
    /// nothing can hold a Frame, so the media viewer is the honest fallback.
    private func openPhotoAsFrame(mediaId: String) {
        guard let lens = primaryLens else {
            onOpenMediaItem(mediaId)
            return
        }
        guard let frame = library.adoptMediaImageAsFrame(mediaId: mediaId, lensId: lens.lensId) else {
            localNotice = library.aestheticStatus.trimmed.nilIfEmpty ?? "Could not open this photo as a Frame"
            return
        }
        openFrameDetail(frame, navigation: nil)
    }

    private func openFrameDetail(_ heroImage: ProjectLensHeroImage, navigation: HeroPreviewCutNavigation?) {
        // A planned frame has no pixels to preview — clicking it anywhere
        // (pool identity sections, sidebar, spotlight) art-directs it instead
        // of silently doing nothing.
        if heroImage.isPlanFulfillmentCandidate {
            artDirectPlannedFrame(heroImage)
            return
        }
        guard let request = HeroPreviewModalHost.openingRequest(library: library, imageId: heroImage.imageId) else {
            return
        }
        heroPreviewRequest = request
        heroPreviewNavigation = navigation
    }

    private func createScene() {
        guard let lens = primaryLens else {
            localNotice = "Start a Story first — Scenes render inside its world"
            return
        }
        localNotice = ""
        let shotId = library.createShot(lensId: lens.lensId)
        // A scene you just created is the scene you came to work on — stage
        // it (also what un-empties a deliberately empty stage).
        if !shotId.isEmpty {
            session.select(shotId)
        }
    }

    /// The pool tiles' right-click shortcut: create-scene + drop-this-in-it
    /// as one gesture. `createShot` owns the whole material law (photo→frame
    /// adoption, first entry at index 0, honest refusals via the status
    /// line) and returns "" on failure, so this stages only what was made.
    private func startNewScene(with transfer: ShotFrameTransfer) {
        guard let lens = primaryLens else {
            localNotice = "Start a Story first — Scenes render inside its world"
            return
        }
        localNotice = ""
        let shotId = transfer.isClipDrag
            ? library.createShot(lensId: lens.lensId, withMediaId: transfer.clipMediaId)
            : library.createShot(lensId: lens.lensId, withFrameImageId: transfer.frameImageId)
        if !shotId.isEmpty {
            session.select(shotId)
        }
    }

    private func reconcileSession() {
        guard let projectId = library.currentProject?.projectId else { return }
        session.adoptProject(projectId)
        session.select(scenesV2ReconciledSelection(
            session.selectedSceneId,
            against: library.shotTimeline.visibleShots.map(\.shotId),
            readySceneIds: Set(library.outputSequence.shots.map(\.shotId)),
            seedsWhenEmpty: !session.selectionIsDeliberate,
            recentSceneIds: session.recentSceneIds
        ))
    }

    /// One Excursion dive (behavior-parallel with the SCENES tab's helper):
    /// resolves the parent's lens by image id, composes the modal's exact
    /// default reframe prompt, fires the punch-in kernel, and registers the
    /// placement as a single "Punch-In" Undo.
    private func startPunchIn(
        cutId: String,
        afterEntryId: String,
        parentImageId: String,
        spec: LensReframeSpec,
        onPlaced: @escaping @MainActor (ShotPunchInPlacement) -> Void
    ) async -> Bool {
        var resolved: (lens: ProjectLens, heroImage: ProjectLensHeroImage)?
        for lens in library.projectLenses.lenses {
            if let heroImage = lens.sortedHeroImages.first(where: { $0.imageId == parentImageId }) {
                resolved = (lens, heroImage)
                break
            }
        }
        guard let resolved else { return false }
        let stack = RenderStackRegistry.shared.fallback
        let promptBody = LensReframeComposer.renderDefaultPromptBody(
            spec: spec,
            parent: resolved.heroImage,
            model: stack.reframePromptModel,
            promptSettings: library.projectPromptSettings
        )
        pictureUndo.applyState = { shotId, snapshot in
            library.restoreShotPictureState(shotId: shotId, snapshot: snapshot)
        }
        return await library.startPunchInExcursion(
            cutId: cutId,
            afterEntryId: afterEntryId,
            lensId: resolved.lens.lensId,
            parentImageId: parentImageId,
            spec: spec,
            stack: stack,
            promptBody: promptBody,
            onPlaced: { placement in
                pictureUndo.registerEdit(
                    shotId: cutId,
                    old: placement.edit.before,
                    new: placement.edit.after,
                    actionName: "Punch-In",
                    undoManager: undoManager
                )
                onPlaced(placement)
            }
        )
    }
}
