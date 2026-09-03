import AppKit
import AVFoundation
import AVKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

private enum LibraryWorkspaceStage: Equatable {
    case noProject
    case needsMedia
    case scanning
    case needsIndex
    case mediaReady
}

enum LibraryWorkspaceTab: String, Identifiable {
    case media = "Media"
    case goal = "Story"
    case characters = "Characters"
    /// The former "Scenes" tab — renamed when the v2 workbench took the
    /// plain name and the leading position (a deliberate product decision).
    case aesthetic = "Scenes v1"
    case scenesV2 = "Scenes"

    static let allCases: [LibraryWorkspaceTab] = [.media, .goal, .characters, .scenesV2, .aesthetic]

    var id: String { rawValue }

    var underlineWidth: CGFloat {
        max(64, CGFloat(rawValue.count) * 13)
    }

    /// Maps persisted labels across the Goal/Stories consolidation, the earlier
    /// FRAMES→SCENES rename, the MOODBOARD→MEDIA rename, and the SCENES
    /// swap. Both former creative tabs now reopen the combined STORY.
    /// A legacy persisted "Scenes" resolves to the v2 workbench via the
    /// rawValue init — deliberate: the tab named Scenes IS v2 now.
    static func fromPersisted(_ rawValue: String) -> LibraryWorkspaceTab? {
        if rawValue == "Goal" || rawValue == "Stories" { return .goal }
        if rawValue == "Moodboard" { return .media }
        if rawValue == "Scenes v2" { return .scenesV2 }
        if let tab = LibraryWorkspaceTab(rawValue: rawValue) { return tab }
        return rawValue == "Frames" ? .aesthetic : nil
    }
}

private enum ProjectSidebarMetrics {
    static let expandedWidth: CGFloat = 270
    static let headerVerticalPadding: CGFloat = 14
    static let headerHorizontalPadding: CGFloat = 14
    static let listVerticalPadding: CGFloat = 12
    static let listHorizontalPadding: CGFloat = 12
    static let rowVerticalPadding: CGFloat = 10
    static let rowHorizontalPadding: CGFloat = 10
    static let rowSpacing: CGFloat = 8
    static let headerHeight: CGFloat = 64
    static let rowHeight: CGFloat = 58
    static let collapsedWidth = expandedWidth / 4
    static let collapsedHeaderHorizontalPadding = headerHorizontalPadding / 4
    static let collapsedListHorizontalPadding = listHorizontalPadding / 4
    static let collapsedRowHorizontalPadding = rowHorizontalPadding / 4
}

private enum WorkspaceTrayMetrics {
    static let minimumExpandedWidth: CGFloat = 300
    static let collapsedWidth: CGFloat = 64

    static func expandedWidth(for workspaceWidth: CGFloat) -> CGFloat {
        max(minimumExpandedWidth, workspaceWidth / 3)
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    @State private var isCursorPushed = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovering in
                if isHovering, !isCursorPushed {
                    NSCursor.pointingHand.push()
                    isCursorPushed = true
                } else if !isHovering, isCursorPushed {
                    NSCursor.pop()
                    isCursorPushed = false
                }
            }
            .onDisappear {
                if isCursorPushed {
                    NSCursor.pop()
                    isCursorPushed = false
                }
            }
    }
}

extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursorModifier())
    }
}

struct LibraryRootView: View {
    @ObservedObject var library: LibraryEngine
    @ObservedObject var recorder: RecorderEngine
    @ObservedObject var sessionRecorder: SessionRecorder
    @State private var showingNewProject = false
    @State private var showingRenameProject = false
    @State private var showingAppSettings = false
    @State private var isWelcomeActive = false
    /// First-run welcome latch — versioned so a future overhaul can re-run.
    @AppStorage("litscenes.welcome.seen_version", store: LitScenesPreferences.store)
    private var welcomeSeenVersion = 0
    @State private var isNoticesPresented = false
    @State private var isActivityPresented = false
    @State private var isSpendLedgerPresented = false
    @State private var selectedWorkspaceTab: LibraryWorkspaceTab = .media
    @State private var displayedWorkspaceTab: LibraryWorkspaceTab = .media
    /// SCENES v2 working set. Owned here — the tab body is destroyed on every
    /// switch (.id below), and the box assignments must survive it (they are
    /// also remembered per project, so a sidebar project switch restores them).
    @StateObject private var scenesV2Session = ScenesV2Session()
    /// CHARACTERS working set (selection, unsent drafts, stack pick) — owned here
    /// for the same teardown reason as the SCENES v2 session.
    @StateObject private var charactersSession = CharactersSession()
    /// The last workspace tab the user explicitly opened — restored on launch.
    @AppStorage("LITSCENES_LAST_WORKSPACE_TAB", store: LitScenesPreferences.store)
    private var persistedWorkspaceTabRawValue = LibraryWorkspaceTab.media.rawValue
    /// Guards launch hydration: the first loaded project restores the saved
    /// tab. Later project switches keep the active workspace exactly where the
    /// operator left it.
    @State private var hasHydratedInitialProject = false
    @State private var expandedMediaId: String?
    @State private var imagePreviewItem: MediaItemRecord?
    @State private var imagePreviewZoom: CGFloat = 1
    @State private var studioVideo: MediaItemRecord?
    @State private var studioTimestamp: Double = 0
    /// True when the Studio was opened as click-to-watch (Creations) — it
    /// starts playing immediately; tray/editing entries open paused.
    @State private var studioAutoPlay = false
    /// In-window Frame detail for a lens take from CREATIONS (no native sheet,
    /// so macOS never repositions the application window).
    @State private var takePreview: LensHeroPreviewRequest?
    @State private var takePreviewNavigation: HeroPreviewCutNavigation?
    /// The Frame Creator hosted at the root for Media surfaces: Restyle on a
    /// photo adopts it as a Frame and opens the creator in place.
    @State private var rootFrameCreatorLaunch: WorkbenchFrameCreatorLaunch?
    @State private var rootStylePreview: StyleImagePreviewRequest?
    @State private var rootWorkspaceSize: CGSize = .zero
    @State private var isEnabledContentDropTargeted = false
    @State private var isMediaAnalysisTailDismissed = true
    @State private var isMediaAnalysisTailExpanded = true
    /// STORY readiness-banner dismissals for this launch, keyed
    /// projectId:kind — held here because the tab body is destroyed on every
    /// switch (.id below) and the dismissal must outlive it.
    @State private var dismissedGoalReadinessBannerKeys: Set<String> = []
    /// Replays the Analyze Media attention bounce; bumped when a scan ends
    /// having surfaced new analyzable media. Compared against the count
    /// snapshotted at scan start so rescans that add nothing stay still.
    @State private var analyzeMediaBounceTrigger = 0
    @State private var preScanUnanalyzedCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraRecorderWindowController: CameraRecorderWindowController?

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                sidebar
                Rectangle()
                    .fill(CanonColor.hairlineDark)
                    .frame(width: 1)
                libraryWorkspace
            }

            if let imagePreviewItem {
                ImagePreviewModal(
                    library: library,
                    item: imagePreviewItem,
                    zoomScale: $imagePreviewZoom,
                    onClose: closeImagePreview,
                    onRestyleAsFrame: { restylePhotoAsFrame(imagePreviewItem) },
                    restyleBlockReason: restyleBlockReason
                )
                .transition(.opacity)
            }

            if let video = studioVideo {
                VideoStudioView(
                    library: library,
                    video: video,
                    timestampSeconds: $studioTimestamp,
                    autoPlayOnOpen: studioAutoPlay,
                    onClose: closeVideoStudio
                )
                .transition(.opacity)
                .zIndex(20)
            }

            HeroPreviewModalHost(
                library: library,
                request: $takePreview,
                cutNavigation: $takePreviewNavigation,
                onLaunchFrameCreator: { rootFrameCreatorLaunch = $0 },
                onStartScene: { imageId in
                    // Media has no stage: the new Scene is staged on SCENES
                    // and the workspace follows it there.
                    guard let lens = library.projectLenses.lenses.first else { return }
                    let shotId = library.createShot(lensId: lens.lensId, withFrameImageId: imageId)
                    guard !shotId.isEmpty else { return }
                    scenesV2Session.select(shotId)
                    selectedWorkspaceTab = .scenesV2
                    displayedWorkspaceTab = .scenesV2
                },
                onOpenAppSettings: { showingAppSettings = true }
            )
            .zIndex(24)

            // Re-entry host: outside the .noProject stage the welcome rides
            // the root overlay stack instead of replacing the workspace.
            if isWelcomeActive, workspaceStage != .noProject {
                firstRunWelcome
                    .transition(.opacity)
                    .zIndex(22)
            }

            if library.isScreenAreaRecordingBusy
                || library.screenAreaRecordingPhase == .failed
                || library.screenAreaRecordingPhase == .needsPermission {
                ScreenAreaRecordingHUD(library: library)
                    .padding(.top, 76)
                    .padding(.trailing, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .zIndex(28)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
            }

            if shouldShowMediaAnalysisTail {
                MediaAnalysisTailOverlay(
                    library: library,
                    isExpanded: $isMediaAnalysisTailExpanded
                ) {
                    guard library.mediaAnalysisRunState != .running else { return }
                    isMediaAnalysisTailDismissed = true
                }
                .padding(.top, 76)
                .padding(.trailing, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .zIndex(30)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
            }
        }
        .background(CanonColor.room)
        .onAppear {
            library.reloadProjects()
            library.bootstrapAppNoticesOnLaunch()
            resolveFirstRunWelcome()
        }
        .onChange(of: library.currentProject?.projectId ?? "") { _, _ in
            guard !hasHydratedInitialProject else { return }
            hasHydratedInitialProject = true
            restoreWorkspaceTabPreference()
        }
        .onChange(of: library.pendingFrameCreatorSeed) { _, seed in
            // Media's "Use in Frame Creator" flips to Scenes; the workbench
            // consumes the seed and opens the creator.
            guard seed != nil else { return }
            imagePreviewItem = nil
            selectWorkspaceTab(.aesthetic)
        }
        .onChange(of: library.pendingWorkbenchFocus) { _, focus in
            // Creations' "Reveal in Scenes" flips likewise; the workbench
            // selects the lens and opens the take preview.
            guard focus != nil else { return }
            imagePreviewItem = nil
            selectWorkspaceTab(.aesthetic)
        }
        .onChange(of: library.mediaAnalysisRunState) { _, state in
            switch state {
            case .idle:
                break
            case .running:
                isMediaAnalysisTailDismissed = false
                isMediaAnalysisTailExpanded = true
            case .succeeded:
                isMediaAnalysisTailDismissed = false
                isMediaAnalysisTailExpanded = false
            case .cancelled:
                isMediaAnalysisTailDismissed = false
                isMediaAnalysisTailExpanded = true
            case .failed:
                isMediaAnalysisTailDismissed = false
                isMediaAnalysisTailExpanded = true
            }
        }
        .onChange(of: library.studioAutoOpenVideo) { _, video in
            guard let video else { return }
            openVideoStudio(for: video)
            library.clearStudioAutoOpenRequest()
        }
        .onChange(of: library.isScanning) { wasScanning, isScanning in
            if isScanning, !wasScanning {
                preScanUnanalyzedCount = library.unanalyzedEnabledContentItems.count
            }
            guard wasScanning, !isScanning, !reduceMotion,
                  library.unanalyzedEnabledContentItems.count > preScanUnanalyzedCount else { return }
            analyzeMediaBounceTrigger += 1
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { rootWorkspaceSize = proxy.size }
                    .onChange(of: proxy.size) { _, size in rootWorkspaceSize = size }
            }
        )
        .sheet(item: $rootFrameCreatorLaunch) { launch in
            if let lens = library.projectLenses.lenses.first(where: { $0.lensId == launch.lensId }) {
                FrameCreatorModalHost(
                    library: library,
                    lens: lens,
                    launch: launch,
                    workspaceSize: rootWorkspaceSize,
                    onDismiss: { rootFrameCreatorLaunch = nil },
                    onPreviewStyle: { rootStylePreview = $0 },
                    onOpenAppSettings: { showingAppSettings = true },
                    // A paid render must be visible where it lands: the Media
                    // tab has no surface for a generating take, SCENES does.
                    onSubmitted: { selectWorkspaceTab(.scenesV2) }
                )
            }
        }
        .sheet(item: $rootStylePreview) { request in
            StyleImagePreviewModal(request: request)
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectView { name in
                if library.createProject(named: name) {
                    // A fresh project always opens on MEDIA. Latch hydration so
                    // the launch tab-restore can't re-route a first-ever project;
                    // the reset leaves the persisted last-tab preference alone.
                    hasHydratedInitialProject = true
                    resetWorkspaceToMedia()
                    markWelcomeSeen()
                    showingNewProject = false
                }
            }
            .frame(width: 420)
        }
        .sheet(isPresented: $showingRenameProject) {
            RenameProjectView(initialName: library.currentProject?.name ?? "") { name in
                if library.renameCurrentProject(to: name) {
                    showingRenameProject = false
                }
            }
            .frame(width: 420)
        }
        .sheet(isPresented: $showingAppSettings) {
            AppSettingsView(
                library: library,
                sessionRecorder: sessionRecorder,
                onShowWelcome: { isWelcomeActive = true }
            )
            .frame(width: 640, height: 620)
        }
        .alert("Library Error", isPresented: Binding(
            get: { !library.lastError.isEmpty },
            set: { if !$0 { library.clearError() } }
        )) {
            Button("OK") {
                library.clearError()
            }
        } message: {
            Text(library.lastError)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader(isExpanded: false)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: ProjectSidebarMetrics.rowSpacing) {
                    if library.projects.isEmpty {
                        emptySidebarState(isExpanded: false)
                    } else {
                        ForEach(library.projects) { project in
                            ProjectSidebarRow(
                                project: project,
                                isSelected: project.projectId == library.currentProject?.projectId,
                                isExpanded: false
                            ) {
                                library.selectProject(project)
                            }
                        }
                    }
                }
                .padding(EdgeInsets(
                    top: ProjectSidebarMetrics.listVerticalPadding,
                    leading: ProjectSidebarMetrics.collapsedListHorizontalPadding,
                    bottom: ProjectSidebarMetrics.listVerticalPadding,
                    trailing: ProjectSidebarMetrics.collapsedListHorizontalPadding
                ))
            }

        }
        .frame(width: ProjectSidebarMetrics.collapsedWidth, alignment: .leading)
        .clipped()
        .background {
            ZStack {
                CanonColor.sidebar
                CanonSidebarMotif()
                    .padding(.top, ProjectSidebarMetrics.headerHeight + 24)
                    .opacity(0.78)
            }
        }
        .contentShape(Rectangle())
    }

    private var shouldShowMediaAnalysisTail: Bool {
        !isMediaAnalysisTailDismissed && library.mediaAnalysisRunState != .idle
    }

    @ViewBuilder
    private func sidebarHeader(isExpanded: Bool) -> some View {
        if isExpanded {
            HStack {
                Text("Projects")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Spacer()
                Button {
                    showingNewProject = true
                } label: {
                    LitIconView(icon: .add)
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("New Project")
            }
            .padding(EdgeInsets(
                top: ProjectSidebarMetrics.headerVerticalPadding,
                leading: ProjectSidebarMetrics.headerHorizontalPadding,
                bottom: ProjectSidebarMetrics.headerVerticalPadding,
                trailing: ProjectSidebarMetrics.headerHorizontalPadding
            ))
            .frame(height: ProjectSidebarMetrics.headerHeight)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    showingNewProject = true
                } label: {
                    LitIconView(icon: .add, size: 16)
                        .foregroundStyle(CanonColor.bone)
                        .frame(width: 36, height: 36)
                        .background(CanonColor.mediaCard.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(CanonColor.hairlineDark.opacity(0.85))
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create Project")
                .help("Create Project")
            }
            .padding(EdgeInsets(
                top: 8,
                leading: 8,
                bottom: ProjectSidebarMetrics.headerVerticalPadding,
                trailing: ProjectSidebarMetrics.collapsedHeaderHorizontalPadding
            ))
            .frame(height: ProjectSidebarMetrics.headerHeight, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func emptySidebarState(isExpanded: Bool) -> some View {
        if isExpanded {
            VStack(alignment: .leading, spacing: 8) {
                LitIconView(icon: .folderAdd, size: 22)
                    .foregroundStyle(CanonColor.muted)
                Text("No projects yet.")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text("Create a project to start indexing local media.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 5) {
                LitIconView(icon: .folderAdd, size: 12)
                    .foregroundStyle(CanonColor.muted)
                Text("No projects")
                    .font(CanonType.interface(10, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .padding(EdgeInsets(
                top: ProjectSidebarMetrics.rowVerticalPadding,
                leading: ProjectSidebarMetrics.collapsedRowHorizontalPadding,
                bottom: ProjectSidebarMetrics.rowVerticalPadding,
                trailing: ProjectSidebarMetrics.collapsedRowHorizontalPadding
            ))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var goalWorkspace: some View {
        GoalV2WorkspaceView(
            library: library,
            onContinueToFrames: { selectWorkspaceTab(.aesthetic) },
            onAddMedia: { addMediaFromMediaEntryPoint() },
            onOpenAppSettings: { showingAppSettings = true },
            dismissedReadinessBannerKeys: $dismissedGoalReadinessBannerKeys
        )
    }

    private var charactersWorkspace: some View {
        CharactersWorkspaceView(
            library: library,
            session: charactersSession,
            onOpenAppSettings: { showingAppSettings = true },
            onOpenStory: { selectWorkspaceTab(.goal) },
            onOpenScenes: { selectWorkspaceTab(.scenesV2) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scenesV2Workspace: some View {
        ScenesV2WorkbenchView(
            library: library,
            session: scenesV2Session,
            onOpenMediaItem: { mediaId in
                guard let item = library.items.first(where: { $0.mediaId == mediaId }) else { return }
                if item.kind == .video {
                    openVideoStudio(for: item, autoPlay: true)
                } else if item.kind == .image {
                    openImagePreview(item)
                }
            },
            onOpenAppSettings: { showingAppSettings = true },
            onOpenStory: { selectWorkspaceTab(.goal) },
            onOpenCharacters: { selectWorkspaceTab(.characters) },
            onOpenCharacter: { characterId in
                charactersSession.select(characterId)
                selectWorkspaceTab(.characters)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var aestheticWorkspace: some View {
        LensWorkbenchView(
            library: library,
            onOpenGoal: { selectWorkspaceTab(.goal) },
            onOpenMedia: { selectWorkspaceTab(.media) },
            onOpenMediaItem: { item in
                if item.kind == .video {
                    openVideoStudio(for: item, autoPlay: true)
                } else if item.kind == .image {
                    openImagePreview(item)
                }
            },
            onOpenAppSettings: { showingAppSettings = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mediaWorkspace: some View {
        VStack(spacing: 0) {
            mediaActionBar
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            GeometryReader { geometry in
                let videoTrayWidth = WorkspaceTrayMetrics.expandedWidth(for: geometry.size.width)
                let contentWidth = max(0, geometry.size.width - videoTrayWidth - 1)

                HStack(spacing: 0) {
                    enabledContentBrowser
                        .frame(width: contentWidth)
                    Rectangle()
                        .fill(CanonColor.hairlineDark)
                        .frame(width: 1)
                    VideoSourceTrayView(library: library) { video in
                        openVideoStudio(for: video)
                    }
                    .frame(width: videoTrayWidth)
                }
            }
        }
    }

    private func openVideoStudio(for video: MediaItemRecord, autoPlay: Bool = false) {
        if autoPlay {
            // Click-to-watch (Creations): start at the top and play immediately.
            studioTimestamp = 0
        } else if studioVideo?.mediaId != video.mediaId {
            studioTimestamp = min(max((video.durationSeconds ?? 0) * 0.12, 0), max((video.durationSeconds ?? 0) - 0.01, 0))
        }
        studioAutoPlay = autoPlay
        studioVideo = video
        studioTimestamp = min(max(studioTimestamp, 0), max((video.durationSeconds ?? 0) - 0.01, 0))
    }

    private func openCameraRecorder() {
        let controller = cameraRecorderWindowController ?? CameraRecorderWindowController(library: library)
        cameraRecorderWindowController = controller
        controller.show()
    }

    private func closeVideoStudio() {
        studioVideo = nil
        studioAutoPlay = false
    }

    private func openImagePreview(_ item: MediaItemRecord) {
        guard item.kind == .image else { return }
        library.selectMedia(item)
        imagePreviewItem = item
        imagePreviewZoom = 1
    }

    private func closeImagePreview() {
        imagePreviewItem = nil
        imagePreviewZoom = 1
    }

    /// Restyle on a photo: adopt it as a Frame in the Scene Plan (idempotent,
    /// no spend) and open the Frame Creator in place, style wheel first. The
    /// preview closes first so the sheet has the window.
    private func restylePhotoAsFrame(_ item: MediaItemRecord) {
        guard item.kind == .image, let lens = library.readyLenses.first else { return }
        closeImagePreview()
        guard let frame = library.adoptMediaImageAsFrame(mediaId: item.mediaId, lensId: lens.lensId) else {
            return
        }
        rootFrameCreatorLaunch = WorkbenchFrameCreatorLaunch(
            lensId: lens.lensId,
            context: .restyle(of: frame),
            placeBeside: nil
        )
    }

    /// Why Restyle is disabled on Media surfaces; nil once a Scene Plan exists
    /// to hold the Frame (the same explainer Use in Frame Creator states).
    private var restyleBlockReason: String? {
        library.readyLenses.first == nil ? "Plan your Scenes first" : nil
    }

    private var mediaActionBar: some View {
        HStack(spacing: 10) {
            Button {
                addMediaFromMediaEntryPoint()
            } label: {
                LitIconLabel(title: library.isScanning ? "Adding Media" : "Add Media", icon: .media)
            }
            .buttonStyle(CanonSecondaryButtonStyle())
            .disabled(library.currentProject == nil || library.isScanning || library.isAnalyzingMedia)

            Button {
                if !library.isOpenAICredentialConfigured {
                    showingAppSettings = true
                }
                Task {
                    await library.analyzeUnanalyzedEnabledMedia()
                }
            } label: {
                LitIconLabel(title: library.isAnalyzingMedia ? "Analyzing Media" : "Analyze Media", icon: .analyze)
            }
            .buttonStyle(CanonSecondaryButtonStyle())
            .disabled(!library.canAnalyzeUnanalyzedEnabledMedia)
            .help("Analyze enabled photos and chosen video frames without saved analysis")
            .keyframeAnimator(initialValue: 0.0, trigger: analyzeMediaBounceTrigger) { view, offsetY in
                view.offset(y: offsetY)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-7, duration: 0.12)
                    CubicKeyframe(0, duration: 0.16)
                    CubicKeyframe(-3, duration: 0.10)
                    CubicKeyframe(0, duration: 0.14)
                }
            }

            Menu {
                Button {
                    openCameraRecorder()
                } label: {
                    Label("Record Camera", systemImage: "camera")
                }
                .disabled(!library.canOpenCameraRecorder)

                Button {
                    library.beginScreenAreaRecordingSelection()
                } label: {
                    Label("Record Screen Area", systemImage: "crop")
                }
                .disabled(!library.canRecordScreenArea)
            } label: {
                Label("Experimental", systemImage: "flask")
            }
            .buttonStyle(CanonSecondaryButtonStyle())
            .disabled(library.currentProject == nil)
            .help("Experimental capture — record a camera video or a screen region into MEDIA")

            if library.isScanning || library.isAnalyzingMedia {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Text(library.mediaAnalysisStatus)
                .font(CanonType.interface(12, weight: .medium))
                .foregroundStyle(CanonColor.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(CanonColor.sidebar)
    }

    private func addMediaFromMediaEntryPoint() {
        resetWorkspaceToMedia()
        library.addMedia()
    }

    private var libraryWorkspace: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            // Media is optional before GOAL: pre-index states (start, scanning,
            // needs-index) render only inside the Media tab, and every other tab
            // works from the moment a project exists.
            switch workspaceStage {
            case .noProject:
                if isWelcomeActive {
                    firstRunWelcome
                } else {
                    EmptyLibraryState(
                        title: "No Project Selected",
                        subtitle: "Create a project to build a local Library index.",
                        icon: .folder
                    )
                }
            case .needsMedia:
                if selectedWorkspaceTab == .media {
                    FocusedProjectStartView(
                        projectName: library.currentProject?.name ?? "Project",
                        onAddMedia: {
                            addMediaFromMediaEntryPoint()
                        }
                    )
                } else {
                    workspaceTabContent
                }
            case .scanning, .needsIndex:
                if selectedWorkspaceTab == .media {
                    HStack(spacing: 0) {
                        ProjectSetupPanel(
                            mode: .goal,
                            library: library,
                            isHighlighted: false
                        )
                            .frame(width: 320)
                        Rectangle()
                            .fill(CanonColor.hairlineDark)
                            .frame(width: 1)
                        libraryMainContent
                    }
                } else {
                    workspaceTabContent
                }
            case .mediaReady:
                workspaceTabContent
            }
        }
        .background(CanonColor.room)
    }

    @ViewBuilder
    private var libraryMainContent: some View {
        switch workspaceStage {
        case .scanning:
            FocusedLibraryStatusView(
                title: "Scanning Media",
                subtitle: library.scanStatus,
                icon: .media,
                isLoading: true
            )
        case .needsIndex:
            FocusedLibraryStatusView(
                title: "Media Source Added",
                subtitle: "Build the Library index for this project.",
                icon: .media,
                primaryTitle: "Index Media",
                primaryIcon: .analyze,
                primaryAction: {
                    resetWorkspaceToMedia()
                    library.rescan()
                }
            )
        case .mediaReady:
            workspaceTabContent
        case .noProject, .needsMedia:
            EmptyView()
        }
    }

    private var workspaceTabContent: some View {
        Group {
            switch displayedWorkspaceTab {
            case .media:
                mediaWorkspace
            case .goal:
                goalWorkspace
            case .characters:
                charactersWorkspace
            case .aesthetic:
                aestheticWorkspace
            case .scenesV2:
                scenesV2Workspace
            }
        }
        .id(displayedWorkspaceTab)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.10), value: displayedWorkspaceTab)
    }

    private var workspaceHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(library.currentProject?.name ?? "Library")
                            .font(CanonType.interface(15, weight: .semibold))
                            .foregroundStyle(CanonColor.bone)
                            .lineLimit(1)
                        if library.currentProject != nil {
                            Button {
                                showingRenameProject = true
                            } label: {
                                LitIconView(icon: .rename, size: 12)
                            }
                            .buttonStyle(CanonUtilityButtonStyle())
                            .help("Rename Project")
                        }
                    }
                    Text(headerSubtitle)
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.muted)
                        .lineLimit(1)
                }

                Spacer()

                if workspaceStage == .mediaReady {
                    LibraryStepStrip(library: library)
                        .frame(width: 480)

                    Button {
                        continueToNextWorkspace()
                    } label: {
                        LitIconLabel(title: "Continue", icon: .arrowRight)
                    }
                    .buttonStyle(CanonSecondaryButtonStyle())
                    .help("Continue to the next creative workspace")
                }

                Button {
                    isActivityPresented = true
                } label: {
                    LitIconView(icon: .activity)
                        .overlay(alignment: .topTrailing) {
                            if evaluateSpendFailureAttention(library.spendLedgerSummary) {
                                Circle()
                                    .fill(CanonColor.rust)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 3, y: -3)
                            } else if library.runningPaidCount > 0 {
                                Circle()
                                    .fill(CanonColor.brass)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 3, y: -3)
                            }
                        }
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Activity — running work, pause, and spend")
                .popover(isPresented: $isActivityPresented, arrowEdge: .bottom) {
                    ActivityPopover(
                        library: library,
                        onOpenLedger: {
                            isActivityPresented = false
                            isSpendLedgerPresented = true
                        },
                        onDismiss: { isActivityPresented = false }
                    )
                }
                .sheet(isPresented: $isSpendLedgerPresented) {
                    SpendLedgerPlateView(library: library) {
                        isSpendLedgerPresented = false
                    }
                }

                Button {
                    isNoticesPresented = true
                } label: {
                    LitIconView(icon: .notices)
                        .overlay(alignment: .topTrailing) {
                            if library.diskUsageNeedsAttention {
                                Circle()
                                    .fill(CanonColor.brass)
                                    .frame(width: 6, height: 6)
                                    .offset(x: 3, y: -3)
                            }
                        }
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Notices")
                .popover(isPresented: $isNoticesPresented, arrowEdge: .bottom) {
                    AppNoticesPopover(library: library) {
                        isNoticesPresented = false
                    }
                }

                Button {
                    showingAppSettings = true
                } label: {
                    LitIconView(icon: .settings)
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("App Settings")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(CanonColor.sidebar)

            if workspaceStage != .noProject {
                workspaceNav
            }
        }
    }

    private var workspaceNav: some View {
        HStack(alignment: .bottom, spacing: 34) {
            ForEach(LibraryWorkspaceTab.allCases) { tab in
                workspaceTabButton(tab)
            }

            Spacer()

            Text(workspaceStatusLabel)
                .font(CanonType.archive(11, weight: .medium))
                .foregroundStyle(CanonColor.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 16)
        .background(CanonColor.sidebar)
    }

    private func workspaceTabButton(_ tab: LibraryWorkspaceTab) -> some View {
        let isSelected = selectedWorkspaceTab == tab
        return Button {
            selectWorkspaceTab(tab)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(tab.rawValue)
                    .textCase(.uppercase)
                    .font(CanonType.editorial(isSelected ? 30 : 27, weight: isSelected ? .semibold : .medium))
                    .tracking(1.8)
                    .foregroundStyle(isSelected ? CanonColor.bone : CanonColor.muted)
                Rectangle()
                    .fill(isSelected ? CanonColor.brass : Color.clear)
                    .frame(width: tab.underlineWidth, height: 2)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var enabledContentBrowser: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 12
            let contentWidth = max(1, geometry.size.width - 32)
            let columnCount = mediaGridColumnCount(for: contentWidth, spacing: spacing)
            let tileWidth = mediaGridTileWidth(for: contentWidth, columns: columnCount, spacing: spacing)
            let roleIndex = library.mediaRoleIndex
            let storyInputRows = mediaGridRows(items: library.enabledContentItems, columns: columnCount)
            let libraryRows = mediaGridRows(items: library.disabledPhotoItems, columns: columnCount)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // The promotion drop lands on the Story Inputs section, not
                    // the whole page — dropping an image here is the gesture.
                    VStack(alignment: .leading, spacing: 12) {
                        enabledContentHeader

                        if library.enabledContentItems.isEmpty {
                            MediaEmptyPanel(
                                title: "No Story Inputs yet",
                                subtitle: "Promote images from the Library below, or drop one here — promotion analyzes it automatically."
                            )
                        } else {
                            mediaGrid(rows: storyInputRows, tileWidth: tileWidth, spacing: spacing, roleIndex: roleIndex)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isEnabledContentDropTargeted ? CanonColor.focusBlue.opacity(0.10) : Color.clear)
                            .padding(-8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isEnabledContentDropTargeted ? CanonColor.focusBlue.opacity(0.65) : Color.clear, lineWidth: 1.5)
                            .padding(-8)
                    )
                    .dropDestination(for: MediaIDTransfer.self) { transfers, _ in
                        var accepted = false
                        for transfer in transfers {
                            accepted = library.enableContentItem(transfer.mediaId) || accepted
                        }
                        return accepted
                    } isTargeted: { targeted in
                        isEnabledContentDropTargeted = targeted
                    }

                    if !library.disabledPhotoItems.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text("Library")
                                    .font(CanonType.interface(11, weight: .semibold))
                                    .tracking(0.8)
                                    .textCase(.uppercase)
                                    .foregroundStyle(CanonColor.muted)
                                Rectangle()
                                    .fill(CanonColor.hairlineDark)
                                    .frame(height: 1)
                            }
                            Text("Imported images resting out of Story. Promote one — or right-click to use it anywhere.")
                                .font(CanonType.interface(11))
                                .foregroundStyle(CanonColor.muted)
                            mediaGrid(rows: libraryRows, tileWidth: tileWidth, spacing: spacing, roleIndex: roleIndex)
                        }
                    }

                    MediaCreationsSection(
                        library: library,
                        onOpenImage: { openImagePreview($0) },
                        onOpenVideo: { openVideoStudio(for: $0, autoPlay: true) },
                        onRestyle: restyleBlockReason == nil ? { restylePhotoAsFrame($0) } : nil,
                        onOpenTake: { lensId, image in
                            imagePreviewItem = nil
                            studioVideo = nil
                            takePreviewNavigation = nil
                            takePreview = HeroPreviewModalHost.request(
                                library: library,
                                lensId: lensId,
                                imageId: image.imageId
                            )
                        },
                        onRevealLensTake: { lensId, imageId in
                            library.requestWorkbenchFocus(lensId: lensId, imageId: imageId)
                        }
                    )
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .animation(.easeInOut(duration: 0.18), value: expandedMediaId)
        }
        .background(CanonColor.archiveWell)
    }

    private var enabledContentHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Story Inputs")
                    .font(CanonType.editorial(24, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text("Analyzed images that steer Story, moods, and aesthetics. Drop an image here to promote it.")
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.muted)
            }
            Spacer(minLength: 0)
            Text("\(library.enabledContentItems.count) story input\(library.enabledContentItems.count == 1 ? "" : "s")")
                .font(CanonType.archive(11, weight: .medium))
                .foregroundStyle(CanonColor.muted)
        }
    }

    private func mediaGridColumnCount(for contentWidth: CGFloat, spacing: CGFloat) -> Int {
        let minimumTileWidth: CGFloat = 154
        let rawCount = Int((contentWidth + spacing) / (minimumTileWidth + spacing))
        return max(1, rawCount)
    }

    private func mediaGridTileWidth(for contentWidth: CGFloat, columns: Int, spacing: CGFloat) -> CGFloat {
        guard columns > 1 else { return contentWidth }
        let totalSpacing = CGFloat(columns - 1) * spacing
        return max(1, floor((contentWidth - totalSpacing) / CGFloat(columns)))
    }

    private func mediaGridCellWidth(tileWidth: CGFloat, span: Int, spacing: CGFloat) -> CGFloat {
        tileWidth * CGFloat(span) + spacing * CGFloat(max(0, span - 1))
    }

    private func mediaGridRows(items: [MediaItemRecord], columns: Int) -> [[MediaGridCell]] {
        let safeColumns = max(1, columns)
        var rows: [[MediaGridCell]] = []
        var currentRow: [MediaGridCell] = []
        var occupiedColumns = 0

        for item in items {
            let isExpanded = item.mediaId == expandedMediaId
            let span = isExpanded ? min(3, safeColumns) : 1

            if occupiedColumns + span > safeColumns && !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = []
                occupiedColumns = 0
            }

            currentRow.append(MediaGridCell(item: item, span: span, isExpanded: isExpanded))
            occupiedColumns += span

            if occupiedColumns == safeColumns {
                rows.append(currentRow)
                currentRow = []
                occupiedColumns = 0
            }
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private func mediaGrid(rows: [[MediaGridCell]], tileWidth: CGFloat, spacing: CGFloat, roleIndex: MediaRoleIndex = MediaRoleIndex()) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(row) { cell in
                        if cell.isExpanded {
                            InlineMediaDetailCard(library: library, item: cell.item) {
                                if expandedMediaId == cell.item.mediaId {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        expandedMediaId = nil
                                    }
                                    library.stopVideoPlayback()
                                }
                            }
                            .frame(width: mediaGridCellWidth(tileWidth: tileWidth, span: cell.span, spacing: spacing))
                        } else {
                            MediaTileView(
                                library: library,
                                item: cell.item,
                                curation: library.curation(for: cell.item),
                                roleBadges: roleIndex.badges(for: cell.item, curation: library.curation(for: cell.item)),
                                isSelected: cell.item.mediaId == library.selectedItem?.mediaId,
                                onRestyle: cell.item.kind == .image && restyleBlockReason == nil
                                    ? { restylePhotoAsFrame(cell.item) }
                                    : nil
                            ) {
                                if cell.item.kind == .image {
                                    openImagePreview(cell.item)
                                } else {
                                    library.selectMedia(cell.item)
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        expandedMediaId = cell.item.mediaId
                                    }
                                }
                            } onOpen: {
                                if cell.item.kind == .image {
                                    openImagePreview(cell.item)
                                } else {
                                    library.openMedia(cell.item)
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        expandedMediaId = cell.item.mediaId
                                    }
                                }
                            }
                            .frame(width: tileWidth)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var headerSubtitle: String {
        switch workspaceStage {
        case .noProject:
            return "Create or select a project"
        case .needsMedia:
            return "New project"
        case .scanning:
            return library.scanStatus
        case .needsIndex:
            return "\(library.sources.count) source\(library.sources.count == 1 ? "" : "s") ready to index"
        case .mediaReady:
            break
        }
        let stats = library.stats
        let storyLevel = library.storyWorld.definitionReport.level.label
        let storyInputCount = library.enabledContentItems.count
        return "\(stats.imageCount) images, \(stats.videoCount) videos, \(storyInputCount) story input\(storyInputCount == 1 ? "" : "s"), Story \(storyLevel), \(stats.hydratedRecordCount) screen observations"
    }

    private var workspaceStatusLabel: String {
        switch selectedWorkspaceTab {
        case .media:
            return "\(library.filteredItems.count) media"
        case .goal:
            return library.isGeneratingSceneStories ? library.sceneStoryStatus : library.goalStatus
        case .aesthetic:
            if library.isRetrievingLensContext {
                return library.lensContextStatus
            }
            if library.isGeneratingInitialDraftLenses {
                return library.aestheticStatus
            }
            if !library.readyLenses.isEmpty {
                return ""
            }
            return "Frames workspace"
        case .characters:
            // The CHARACTERS surface carries its own status line.
            return ""
        case .scenesV2:
            // The v2 surface carries its own status line.
            return ""
        }
    }

    private var workspaceStage: LibraryWorkspaceStage {
        guard library.currentProject != nil else {
            return .noProject
        }
        if library.sources.isEmpty {
            return .needsMedia
        }
        if library.items.isEmpty, library.isScanning {
            return .scanning
        }
        if library.items.isEmpty {
            return .needsIndex
        }
        return .mediaReady
    }

    private var firstRunWelcome: some View {
        FirstRunWelcomeView(
            library: library,
            onCreateProject: { showingNewProject = true },
            onOpenAppSettings: { showingAppSettings = true },
            onDismiss: { markWelcomeSeen() }
        )
    }

    private func markWelcomeSeen() {
        welcomeSeenVersion = FirstRunWelcomeEligibility.currentVersion
        isWelcomeActive = false
    }

    private func resolveFirstRunWelcome() {
        let hasAnyCredential = library.videoProviderCredentialStatuses.contains(where: \.isConfigured)
            || library.lensContextCredentialStatuses.contains(where: \.isConfigured)
        switch FirstRunWelcomeEligibility.decide(
            seenVersion: welcomeSeenVersion,
            hasAnyCredential: hasAnyCredential,
            hasAnyProject: !library.projects.isEmpty
        ) {
        case .showWelcome:
            isWelcomeActive = true
        case .markSeenSilently:
            welcomeSeenVersion = FirstRunWelcomeEligibility.currentVersion
        case .none:
            break
        }
    }

    private func resetWorkspaceToMedia() {
        selectedWorkspaceTab = .media
        displayedWorkspaceTab = .media
    }

    /// Restores the last tab the user was on at launch, falling back to Media
    /// if the stored value is missing or not a user-selectable tab.
    private func restoreWorkspaceTabPreference() {
        guard let tab = LibraryWorkspaceTab.fromPersisted(persistedWorkspaceTabRawValue),
              LibraryWorkspaceTab.allCases.contains(tab) else {
            resetWorkspaceToMedia()
            return
        }
        selectedWorkspaceTab = tab
        displayedWorkspaceTab = tab
    }

    /// Story until the Goal is ready, then always forward to Scenes. Output has
    /// no tab of its own, so Scenes is the terminal destination — the old third
    /// branch bounced back to Story forever once a scene existed. "Scenes" is
    /// the v2 workbench since the tab swap.
    /// Story → Characters → Scenes, in order; Characters is visited once (an empty
    /// roster counts as no sheet) and never blocks — from it, Continue moves on.
    static func continueDestination(
        from current: LibraryWorkspaceTab,
        isGoalReady: Bool,
        hasCharacterSheet: Bool
    ) -> LibraryWorkspaceTab {
        guard isGoalReady else { return .goal }
        switch current {
        case .characters, .scenesV2, .aesthetic:
            return .scenesV2
        case .media, .goal:
            return hasCharacterSheet ? .scenesV2 : .characters
        }
    }

    private func continueToNextWorkspace() {
        selectWorkspaceTab(Self.continueDestination(
            from: selectedWorkspaceTab,
            isGoalReady: library.isGoalV2Ready,
            hasCharacterSheet: library.hasAnyCharacterSheet
        ))
    }

    private func selectWorkspaceTab(_ tab: LibraryWorkspaceTab) {
        persistedWorkspaceTabRawValue = tab.rawValue
        guard selectedWorkspaceTab != tab || displayedWorkspaceTab != tab else { return }
        selectedWorkspaceTab = tab
        DispatchQueue.main.async {
            guard selectedWorkspaceTab == tab else { return }
            withAnimation(.easeOut(duration: 0.10)) {
                displayedWorkspaceTab = tab
            }
        }
    }

}

private struct AppSettingsView: View {
    private enum SettingsTab: String, CaseIterable, Identifiable {
        case credentials = "Credentials"
        case stacks = "Stacks"
        case prompts = "Prompts"
        case recording = "Recording"

        var id: String { rawValue }
    }

    private enum StoryInferenceChoice: String, CaseIterable, Identifiable {
        case auto
        case direct
        case hosted

        var id: String { rawValue }

        var label: String {
            switch self {
            case .auto: "Auto"
            case .direct: "Direct (your key)"
            case .hosted: "LitScenes Hosted"
            }
        }
    }

    @ObservedObject var library: LibraryEngine
    @ObservedObject var sessionRecorder: SessionRecorder
    var onShowWelcome: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .credentials
    @State private var settingsMessage = ""
    @State private var storyInferenceChoice: StoryInferenceChoice = .auto
    @State private var storyBaseURLDraft = ""
    @State private var storyModelDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("App Settings")
                        .font(CanonType.interface(16, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                    Text(settingsSubtitle)
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.muted)
                }
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(CanonColor.sidebar)

            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 0) {
                Picker("Settings", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(16)

                Rectangle()
                    .fill(CanonColor.hairlineDark)
                    .frame(height: 1)

                switch selectedTab {
                case .credentials:
                    credentialsContent
                case .stacks:
                    stacksContent
                case .prompts:
                    promptsContent
                case .recording:
                    recordingContent
                }
            }
            .background(CanonColor.room)
        }
        .background(CanonColor.room)
    }

    private var settingsSubtitle: String {
        switch selectedTab {
        case .credentials:
            return "Provider credentials are saved to credentials.env or read from process environment variables."
        case .stacks:
            return "Render stacks load from the bundled render_stacks.yaml plus your overrides in Application Support."
        case .prompts:
            return "Prompt defaults are saved in the selected project."
        case .recording:
            return "Defaults for File → Record Session are saved on this Mac and apply to the next session."
        }
    }

    private var credentialsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                credentialsFilePanel
                storyInferencePanel
                if LitScenesReleaseIdentity.current.showsProInterestPromotion {
                    ProComingSoonCard(face: .card, surface: .dark)
                }
                lensContextCredentialsPanel

                ForEach(LitScenesProviderCredential.allCases) { provider in
                    ProviderCredentialSettingsRow(
                        provider: provider,
                        status: status(for: provider),
                        onSave: { value in
                            try library.saveProviderCredential(provider, value: value)
                        },
                        onRemove: {
                            try library.removeProviderCredential(provider)
                        },
                        onTest: CredentialProbe.supportedProviders.contains(provider)
                            ? {
                                await CredentialProbe().probe(
                                    provider,
                                    apiKey: LitScenesCredentialStore().resolvedCredential(for: provider)
                                )
                            }
                            : nil
                    )
                }

                Button {
                    dismiss()
                    onShowWelcome()
                } label: {
                    Label("Open the Welcome Journey", systemImage: "sparkles")
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Reopen the first-run welcome to add and test keys")
            }
            .padding(16)
        }
    }

    private var stacksContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                stacksFilePanel
                loadedStacksPanel
            }
            .padding(16)
        }
    }

    private var stacksFilePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Render Stacks File", systemImage: "square.stack.3d.up")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Spacer()
                Button {
                    library.reloadRenderStacks()
                    settingsMessage = "Reloaded render stacks (\(library.renderStacks.count) loaded)."
                } label: {
                    Label("Reload Stacks", systemImage: "arrow.clockwise")
                }
                .buttonStyle(CanonSecondaryButtonStyle())
            }

            Text("Your overrides file — entries here merge with the bundled defaults by id (same id overrides, new id adds a stack):")
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text(RenderStackRegistry.userFileURL.path)
                .font(CanonType.archive(10, weight: .medium))
                .foregroundStyle(CanonColor.muted)
                .textSelection(.enabled)
                .lineLimit(2)

            HStack(spacing: 10) {
                Button {
                    do {
                        try library.copyDefaultRenderStacksToUserFile()
                        settingsMessage = "Copied the bundled defaults to your stacks file."
                    } catch {
                        settingsMessage = "Copy failed: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Copy Defaults to My File", systemImage: "doc.on.doc")
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .help("Writes the bundled render_stacks.yaml to your overrides path as a full editable template. Refuses to overwrite an existing file.")

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([
                        FileManager.default.fileExists(atPath: RenderStackRegistry.userFileURL.path)
                            ? RenderStackRegistry.userFileURL
                            : litScenesApplicationSupportDirectory()
                    ])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .buttonStyle(CanonSecondaryButtonStyle())
            }

            if !settingsMessage.isEmpty {
                Text(settingsMessage)
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.olive)
            }
        }
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark.opacity(0.70)))
    }

    /// Read-only list of what actually loaded, so an overlay edit is
    /// verifiable at a glance after Reload.
    private var loadedStacksPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Loaded Stacks", systemImage: "list.bullet")
                .font(CanonType.interface(13, weight: .semibold))
                .foregroundStyle(CanonColor.bone)
            ForEach(library.renderStacks) { stack in
                HStack(spacing: 8) {
                    Text(stack.label)
                        .font(CanonType.interface(12, weight: .medium))
                        .foregroundStyle(CanonColor.bone)
                    Text(stack.id)
                        .font(CanonType.archive(9.5))
                        .foregroundStyle(CanonColor.muted)
                    Spacer(minLength: 0)
                    Text(stack.kind.rawValue.uppercased())
                        .font(CanonType.archive(8.5, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.muted)
                }
            }
        }
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark.opacity(0.70)))
    }

    private var promptsContent: some View {
        ProjectPromptSettingsPanel(library: library)
    }

    private var recordingContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                recordingScopePanel
                recordingSourcesPanel
                recordingOutputPanel
            }
            .padding(16)
        }
    }

    private var recordingScopePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Capture Area", systemImage: "rectangle.dashed.badge.record")
                .font(CanonType.interface(13, weight: .semibold))
                .foregroundStyle(CanonColor.bone)

            ForEach(SessionCaptureScope.allCases) { scope in
                Button {
                    sessionRecorder.captureScope = scope
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: sessionRecorder.captureScope == scope ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(sessionRecorder.captureScope == scope ? CanonColor.brass : CanonColor.muted)
                            .frame(width: 18)
                        Image(systemName: scope.icon)
                            .foregroundStyle(CanonColor.muted)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(scope.title)
                                .font(CanonType.interface(12, weight: .semibold))
                                .foregroundStyle(CanonColor.bone)
                            Text(scope.detail)
                                .font(CanonType.interface(11))
                                .foregroundStyle(CanonColor.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(sessionRecorder.isActive)
            }

            if sessionRecorder.isActive {
                Text("Finish or cancel the current session before changing its capture area.")
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.brass)
            }
        }
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark.opacity(0.70)))
    }

    private var recordingSourcesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Camera & Audio", systemImage: "video.badge.waveform")
                .font(CanonType.interface(13, weight: .semibold))
                .foregroundStyle(CanonColor.bone)

            Toggle(isOn: Binding(
                get: { sessionRecorder.faceCamEnabled },
                set: { sessionRecorder.setFaceCamEnabled($0) }
            )) {
                Label("Show face camera", systemImage: "person.crop.rectangle")
            }

            if sessionRecorder.faceCamEnabled {
                Picker("Camera", selection: Binding(
                    get: { sessionRecorder.preferredCameraDeviceID },
                    set: { sessionRecorder.selectCameraDevice($0) }
                )) {
                    if sessionRecorder.cameraDevices.isEmpty {
                        Text("No camera available").tag("")
                    } else {
                        ForEach(sessionRecorder.cameraDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                }
            }

            Toggle(isOn: Binding(
                get: { sessionRecorder.captureMicrophone },
                set: { sessionRecorder.setCaptureMicrophoneEnabled($0) }
            )) {
                Label("Record narration microphone", systemImage: "mic")
            }

            if sessionRecorder.captureMicrophone {
                Picker("Microphone", selection: Binding(
                    get: { sessionRecorder.preferredMicrophoneDeviceID },
                    set: { sessionRecorder.selectMicrophoneDevice($0) }
                )) {
                    if sessionRecorder.microphoneDevices.isEmpty {
                        Text("No microphone available").tag("")
                    } else {
                        ForEach(sessionRecorder.microphoneDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                }
            }

            Toggle(isOn: $sessionRecorder.captureSystemAudio) {
                Label("Record captured app/system audio", systemImage: "speaker.wave.2")
            }

            Text("LitScenes-only capture limits audio to LitScenes. Camera and microphone permissions are requested only when their source is enabled.")
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(CanonType.interface(12, weight: .medium))
        .foregroundStyle(CanonColor.bone)
        .disabled(sessionRecorder.isActive)
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark.opacity(0.70)))
    }

    private var recordingOutputPanel: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.down.doc")
                .font(.title3.weight(.semibold))
                .foregroundStyle(CanonColor.brass)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text("Downloads")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text("Sessions save as H.264 .mov files and reveal themselves in Finder. Paused time is omitted from the finished video.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark.opacity(0.70)))
    }

    private var credentialsFilePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Local Credentials File", systemImage: "doc.text")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Spacer()
                Button {
                    library.reloadProviderCredentials()
                    settingsMessage = "Reloaded provider credentials."
                } label: {
                    Label("Reload Credentials", systemImage: "arrow.clockwise")
                }
                .buttonStyle(CanonSecondaryButtonStyle())
            }

            Text(OpenAIKeyStore.savedKeyURL.path)
                .font(CanonType.archive(10, weight: .medium))
                .foregroundStyle(CanonColor.muted)
                .textSelection(.enabled)
                .lineLimit(2)

            if !settingsMessage.isEmpty {
                Text(settingsMessage)
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.olive)
            }
        }
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark.opacity(0.70)))
    }

    private var storyInferencePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Story Inference", systemImage: "text.book.closed")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Spacer()
                Text("Now: \(StoryInferenceMode.resolved().label)")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
            }

            Text("How the story spine (Frame Context → Stories → Frame Forms) runs. Direct uses your own OpenAI-compatible key with the bundled starter vocabulary — nothing depends on LitScenes servers. LitScenes Hosted adds live meaning-graph retrieval (edges, corpus evidence, curated candidates) with managed inference at a transparent markup. Hosted is invite-only today and optional — Direct is a complete path with a thinner context. Auto prefers Hosted when it is configured below.")
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Mode", selection: $storyInferenceChoice) {
                ForEach(StoryInferenceChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: storyInferenceChoice) { _, choice in
                do {
                    try library.saveStoryInferenceSetting(
                        key: StoryInferenceMode.preferenceKey,
                        value: choice == .auto ? "" : choice.rawValue
                    )
                    settingsMessage = "Story Inference set to \(choice.label)."
                } catch {
                    settingsMessage = "Could not save Story Inference mode: \(error.localizedDescription)"
                }
            }

            Toggle(isOn: Binding(
                get: { CatalogFetchPolicy.liveCatalogEnabled() },
                set: { enabled in
                    do {
                        try library.saveStoryInferenceSetting(
                            key: CatalogFetchPolicy.preferenceKey,
                            value: enabled ? "1" : ""
                        )
                        settingsMessage = enabled
                            ? "Live style catalog on — the app may fetch catalog.litscenes.ai."
                            : "Live style catalog off — bundled catalog only; Refresh fetches on demand."
                    } catch {
                        settingsMessage = "Could not save the catalog setting: \(error.localizedDescription)"
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live style catalog")
                        .font(CanonType.interface(12, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                    Text("Off by default: the app makes no unconfigured requests and uses the bundled starter catalog. On, it may fetch the full style set from catalog.litscenes.ai. An explicit Refresh always fetches.")
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)

            storyInferenceFieldRow(
                title: "OpenAI-compatible base URL (applies to all OpenAI calls: story, text, and images)",
                placeholder: "https://api.openai.com (or an OpenRouter-style /v1 base)",
                draft: $storyBaseURLDraft,
                key: "OPENAI_BASE_URL"
            )
            storyInferenceFieldRow(
                title: "Story model override",
                placeholder: OpenAITextEndpointSettings.defaultStoryModel,
                draft: $storyModelDraft,
                key: OpenAITextEndpointSettings.storyModelKey
            )
        }
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark.opacity(0.70)))
        .onAppear {
            let store = LitScenesCredentialStore()
            let raw = store.resolvedCredentialValue(forKey: StoryInferenceMode.preferenceKey).trimmed.lowercased()
            storyInferenceChoice = StoryInferenceChoice(rawValue: raw) ?? .auto
            storyBaseURLDraft = store.resolvedCredentialValue(forKeys: OpenAITextEndpointSettings.baseURLKeys)
            storyModelDraft = store.resolvedCredentialValue(forKey: OpenAITextEndpointSettings.storyModelKey)
        }
    }

    private func storyInferenceFieldRow(
        title: String,
        placeholder: String,
        draft: Binding<String>,
        key: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(CanonType.archive(10, weight: .semibold))
                .foregroundStyle(CanonColor.muted)
            HStack(spacing: 8) {
                TextField(placeholder, text: draft)
                    .textFieldStyle(.roundedBorder)
                    .font(CanonType.interface(11))
                Button("Save") {
                    do {
                        try library.saveStoryInferenceSetting(key: key, value: draft.wrappedValue)
                        settingsMessage = draft.wrappedValue.trimmed.isEmpty ? "\(title) cleared." : "\(title) saved."
                    } catch {
                        settingsMessage = "Could not save \(title): \(error.localizedDescription)"
                    }
                }
                .buttonStyle(CanonSecondaryButtonStyle())
            }
        }
    }

    private var lensContextCredentialsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Frame Context Retrieval", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Spacer()
                Text("Hosted Service")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
            }

            Text("Used after GOAL saves to hydrate FRAMES with hosted meaning graph and aesthetic context. Optional: Direct mode plans Frames from the bundled starter vocabulary; the hosted service is invite-only today.")
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(LensContextCredential.allCases) { credential in
                LensContextCredentialSettingsRow(
                    credential: credential,
                    status: status(for: credential),
                    onSave: { value in
                        try library.saveLensContextCredential(credential, value: value)
                    },
                    onRemove: {
                        try library.removeLensContextCredential(credential)
                    }
                )
            }
        }
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark.opacity(0.70)))
    }

    private func status(for provider: LitScenesProviderCredential) -> CredentialStatus {
        library.videoProviderCredentialStatuses.first { $0.provider == provider }
            ?? CredentialStatus(provider: provider, source: .missing, isConfigured: false, message: "\(provider.label) credential missing")
    }

    private func status(for credential: LensContextCredential) -> LensContextCredentialStatus {
        library.lensContextCredentialStatuses.first { $0.credential == credential }
            ?? LensContextCredentialStatus(credential: credential, source: .missing, isConfigured: false, message: "\(credential.label) missing")
    }
}

private struct ProjectPromptSettingsPanel: View {
    @ObservedObject var library: LibraryEngine
    @State private var draft = ProjectPromptSettingsDocument.empty()
    @State private var panelMessage = ""
    @State private var isReframeExpanded = true
    @State private var isCharacterSheetExpanded = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let project = library.currentProject {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(project.name)
                                .font(CanonType.interface(13, weight: .semibold))
                                .foregroundStyle(CanonColor.bone)
                                .lineLimit(1)
                            Text("Project prompt settings")
                                .font(CanonType.archive(10, weight: .medium))
                                .foregroundStyle(CanonColor.muted)
                        }
                        Spacer()
                        if !panelMessage.isEmpty {
                            Text(panelMessage)
                                .font(CanonType.interface(11, weight: .medium))
                                .foregroundStyle(panelMessage.hasPrefix("Could") ? CanonColor.rust : CanonColor.olive)
                                .lineLimit(2)
                        }
                        Button {
                            resetDraft(projectId: project.projectId)
                        } label: {
                            Label("Reset Draft", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(CanonUtilityButtonStyle())
                        Button {
                            saveDraft()
                        } label: {
                            Label("Save Prompts", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(CanonSecondaryButtonStyle())
                    }

                    reframePromptDisclosure
                    characterSheetPromptDisclosure
                } else {
                    Text("Select a project to edit prompt settings.")
                        .font(CanonType.interface(12, weight: .medium))
                        .foregroundStyle(CanonColor.muted)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
        }
        .onAppear(perform: syncDraft)
        .onChange(of: library.currentProject?.projectId ?? "") { _, _ in
            syncDraft()
        }
        .onChange(of: library.projectPromptSettings) { _, _ in
            syncDraft()
        }
    }

    private var reframePromptDisclosure: some View {
        DisclosureGroup(isExpanded: $isReframeExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                promptVariableRow
                reframeModeSection(title: "Zoom In", mode: LensReframeSpec.zoomMode)
                reframeModeSection(title: "Zoom Out", mode: LensReframeSpec.zoomOutMode)
                reframeModeSection(title: "Viewpoint", mode: LensReframeSpec.viewpointMode)
            }
            .padding(.top, 10)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Label("Re-frames / Scene extensions", systemImage: "viewfinder")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Spacer()
                Text("\(draft.reframePrompts.count) templates")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
            }
        }
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark.opacity(0.70)))
    }

    private var characterSheetPromptDisclosure: some View {
        DisclosureGroup(isExpanded: $isCharacterSheetExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                characterSheetVariableRow
                ForEach(draft.characterSheetPrompts.indices, id: \.self) { index in
                    CharacterSheetPromptTemplateEditor(template: $draft.characterSheetPrompts[index])
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Label("Character sheets", systemImage: "person.crop.rectangle")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Spacer()
                Text("\(draft.characterSheetPrompts.count) template\(draft.characterSheetPrompts.count == 1 ? "" : "s")")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
            }
        }
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark.opacity(0.70)))
    }

    private var characterSheetVariableRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(CharacterSheetPrompt.placeholders, id: \.self) { placeholder in
                    promptVariableChip(placeholder)
                }
                Spacer(minLength: 0)
            }
            Text("The sheet renders this text verbatim — no prompt transform. Empty values drop their line.")
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.muted)
        }
    }

    private var promptVariableRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                promptVariableChip("{{focus_x_percent}}")
                promptVariableChip("{{focus_y_percent}}")
                promptVariableChip("{{view_direction}}")
                promptVariableChip("{{character_context}}")
                promptVariableChip("{{original_scene_context}}")
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                promptVariableChip("{{source_scale_percent}}")
                promptVariableChip("{{zoom_out_percent}}")
                promptVariableChip("{{margin_left_percent}}")
                promptVariableChip("{{margin_right_percent}}")
                promptVariableChip("{{margin_top_percent}}")
                promptVariableChip("{{margin_bottom_percent}}")
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                promptVariableChip("{{focus_width_percent}}")
                promptVariableChip("{{focus_height_percent}}")
                promptVariableChip("{{focus_rotation_degrees}}")
                promptVariableChip("{{focus_rotation_clause}}")
                Spacer(minLength: 0)
            }
        }
    }

    private func reframeModeSection(title: String, mode: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(CanonType.interface(11, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(CanonColor.brass)
            ForEach(promptTemplateIndices(mode: mode), id: \.self) { index in
                ReframePromptTemplateEditor(template: $draft.reframePrompts[index])
            }
        }
    }

    private func promptVariableChip(_ value: String) -> some View {
        Text(value)
            .font(CanonType.archive(9.5, weight: .semibold))
            .foregroundStyle(CanonColor.bone.opacity(0.86))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(CanonColor.paperInset.opacity(0.38), in: Capsule())
    }

    private func promptTemplateIndices(mode: String) -> [Int] {
        draft.reframePrompts.indices.filter { index in
            draft.reframePrompts[index].mode == mode
        }
    }

    private func syncDraft() {
        if let project = library.currentProject {
            draft = library.projectPromptSettings.normalized(projectId: project.projectId)
        } else {
            draft = .empty()
        }
    }

    private func resetDraft(projectId: String) {
        draft = ProjectPromptSettingsDocument.empty(projectId: projectId).normalized(projectId: projectId)
        panelMessage = "Draft reset. Save to apply."
    }

    private func saveDraft() {
        do {
            try library.saveProjectPromptSettings(draft)
            panelMessage = "Saved project prompt settings."
            syncDraft()
        } catch {
            panelMessage = "Could not save: \(error.localizedDescription)"
        }
    }
}

private struct ReframePromptTemplateEditor: View {
    @Binding var template: ReframePromptTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(template.title)
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                    .lineLimit(1)
                Text(template.isFallback ? "Fallback" : template.model)
                    .font(CanonType.archive(9.5, weight: .semibold))
                    .foregroundStyle(template.isFallback ? CanonColor.brass : CanonColor.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(CanonColor.paperInset.opacity(0.38), in: Capsule())
                    .lineLimit(1)
                Spacer()
                Button {
                    resetToBuiltIn()
                } label: {
                    Text("Default")
                }
                .font(CanonType.interface(10.5, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(CanonColor.brass)
            }

            TextEditor(text: $template.body)
                .font(CanonType.editorial(12.5))
                .foregroundStyle(CanonColor.bone)
                .frame(minHeight: 112)
                .padding(7)
                .background(CanonColor.paperInset.opacity(0.30), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlineDark.opacity(0.80)))
        }
        .padding(10)
        .background(CanonColor.paperInset.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark.opacity(0.55)))
    }

    private func resetToBuiltIn() {
        let builtIn = ProjectPromptSettingsDocument.builtInTemplate(mode: template.mode, model: template.model)
        template.body = builtIn.body
        template.updatedAt = DateFormats.now()
    }
}

private struct CharacterSheetPromptTemplateEditor: View {
    @Binding var template: CharacterSheetPromptTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(template.title)
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                    .lineLimit(1)
                Text(template.isFallback ? "Fallback" : template.model)
                    .font(CanonType.archive(9.5, weight: .semibold))
                    .foregroundStyle(template.isFallback ? CanonColor.brass : CanonColor.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(CanonColor.paperInset.opacity(0.38), in: Capsule())
                    .lineLimit(1)
                Spacer()
                Button {
                    resetToBuiltIn()
                } label: {
                    Text("Default")
                }
                .font(CanonType.interface(10.5, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(CanonColor.brass)
            }

            TextEditor(text: $template.body)
                .font(CanonType.editorial(12.5))
                .foregroundStyle(CanonColor.bone)
                .frame(minHeight: 220)
                .padding(7)
                .background(CanonColor.paperInset.opacity(0.30), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlineDark.opacity(0.80)))
        }
        .padding(10)
        .background(CanonColor.paperInset.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark.opacity(0.55)))
    }

    private func resetToBuiltIn() {
        let builtIn = ProjectPromptSettingsDocument.builtInCharacterSheetTemplate(model: template.model)
        template.body = builtIn.body
        template.updatedAt = DateFormats.now()
    }
}

private struct LensContextCredentialSettingsRow: View {
    let credential: LensContextCredential
    let status: LensContextCredentialStatus
    let onSave: (String) throws -> Void
    let onRemove: () throws -> Void
    @State private var draftValue = ""
    @State private var rowMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(credential.label, systemImage: iconName)
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text(statusLabel)
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(status.isConfigured ? CanonColor.olive : CanonColor.rust)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(CanonColor.paperInset.opacity(0.58), in: Capsule())
                Spacer()
                Text(status.source.label)
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
            }

            Text(description)
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(credential.keyCandidates.joined(separator: " / "))
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.64))
                    .lineLimit(1)
                Spacer()
                Text(status.message)
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(2)
            }

            if credential.isSecret {
                SecureField(inputPlaceholder, text: $draftValue)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(inputPlaceholder, text: $draftValue)
                    .textFieldStyle(.roundedBorder)
                    .textSelection(.enabled)
            }

            HStack(alignment: .center, spacing: 8) {
                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(draftValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    remove()
                } label: {
                    Label(removeLabel, systemImage: "trash")
                }
                .buttonStyle(CanonUtilityButtonStyle())

                Spacer(minLength: 0)

                if !rowMessage.isEmpty {
                    Text(rowMessage)
                        .font(CanonType.interface(10, weight: .semibold))
                        .foregroundStyle(rowMessage.hasPrefix("Could") ? CanonColor.rust : CanonColor.olive)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .background(CanonColor.paperInset.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(status.isConfigured ? CanonColor.olive.opacity(0.35) : CanonColor.rust.opacity(0.45)))
    }

    private var statusLabel: String {
        status.isConfigured ? "Configured" : "Missing"
    }

    private var iconName: String {
        switch credential {
        case .endpointURL: "link"
        case .token: "key"
        }
    }

    private var description: String {
        switch credential {
        case .endpointURL:
            return "Base URL for the hosted Meaning service. The app appends /lens-context/resolve or /scene-story/generate when needed."
        case .token:
            return "Bearer token used by Desktop to authenticate Frame Context and SceneStory requests."
        }
    }

    private var inputPlaceholder: String {
        switch credential {
        case .endpointURL:
            return status.isConfigured ? "Saved or environment URL" : "https://..."
        case .token:
            return status.isConfigured ? "Saved or environment token" : credential.primaryWritableKey
        }
    }

    private var removeLabel: String {
        credential.isSecret ? "Remove Local Token" : "Remove Local URL"
    }

    private func save() {
        do {
            try onSave(draftValue)
            draftValue = ""
            rowMessage = "Saved"
        } catch {
            rowMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    private func remove() {
        do {
            try onRemove()
            draftValue = ""
            rowMessage = "Removed local value"
        } catch {
            rowMessage = "Could not remove: \(error.localizedDescription)"
        }
    }
}

private struct ProviderCredentialSettingsRow: View {
    let provider: LitScenesProviderCredential
    let status: CredentialStatus
    let onSave: (String) throws -> Void
    let onRemove: () throws -> Void
    let onTest: (() async -> CredentialProbeOutcome)?
    @State private var draftValue = ""
    @State private var isProbing = false
    @State private var rowFeedback: (text: String, tone: Color)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(provider.label, systemImage: iconName)
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text(statusLabel)
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(status.isConfigured ? CanonColor.olive : CanonColor.rust)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(CanonColor.paperInset.opacity(0.58), in: Capsule())
                Spacer()
                Text(status.source.label)
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
            }

            Text(description)
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(provider.keyCandidates.joined(separator: " / "))
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.64))
                    .lineLimit(1)
                Spacer()
                Text(status.message)
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(2)
            }

            SecureField(inputPlaceholder, text: $draftValue)
                .textFieldStyle(.roundedBorder)

            HStack(alignment: .center, spacing: 8) {
                Button {
                    save()
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(draftValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    remove()
                } label: {
                    Label("Remove Local Key", systemImage: "trash")
                }
                .buttonStyle(CanonUtilityButtonStyle())

                if onTest != nil {
                    Button {
                        runProbe()
                    } label: {
                        Label("Test", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(CanonUtilityButtonStyle())
                    .disabled(!status.isConfigured || isProbing)
                    .help("Check the resolved key against \(provider.label) without spending anything")
                }

                if isProbing {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer(minLength: 0)

                if let rowFeedback {
                    Text(rowFeedback.text)
                        .font(CanonType.interface(10, weight: .semibold))
                        .foregroundStyle(rowFeedback.tone)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(status.isConfigured ? CanonColor.olive.opacity(0.35) : CanonColor.rust.opacity(0.45)))
    }

    private var statusLabel: String {
        status.isConfigured ? "Configured" : "Missing"
    }

    private var iconName: String {
        switch provider {
        case .openAI: "sparkles"
        case .elevenLabs: "waveform"
        case .ltx: "film"
        case .civitai: "square.stack.3d.up"
        case .fal: "bolt.fill"
        case .decart: "photo.badge.arrow.down"
        case .kling: "sparkle.magnifyingglass"
        case .stability: "photo.on.rectangle.angled"
        }
    }

    private var description: String {
        switch provider {
        case .openAI:
            return "Used for Story, Beats, and later OpenAI video adapters."
        case .elevenLabs:
            return "Used for global audio bed and voiceover generation after a Video Chain is assembled."
        case .ltx:
            return "Used by LTX Direct for native video extension and retake workflows."
        case .civitai:
            return "Used by CivitAI WAN for keyframed chains that require both start frames and planned target end frames."
        case .fal:
            return "Used by FAL image generation and Lucy text-input video restyling."
        case .decart:
            return "Used by direct Decart Lucy image-reference video restyling."
        case .kling:
            return "Used by Kling Image-to-Video for first-frame chains with optional target end frames."
        case .stability:
            return "Used by Frames to generate Stability AI Stable Image Ultra alternates beside OpenAI stills."
        }
    }

    private var inputPlaceholder: String {
        if provider == .kling {
            return status.isConfigured ? "Saved Kling key or ACCESS_KEY:SECRET_KEY" : "KLING_API_KEY as ACCESS_KEY:SECRET_KEY"
        }
        return status.isConfigured ? "Saved or environment key" : provider.primaryWritableKey
    }

    private func save() {
        do {
            try onSave(draftValue)
            draftValue = ""
            rowFeedback = ("Saved", CanonColor.olive)
        } catch {
            rowFeedback = ("Could not save: \(error.localizedDescription)", CanonColor.rust)
        }
    }

    private func remove() {
        do {
            try onRemove()
            draftValue = ""
            rowFeedback = ("Removed local key", CanonColor.olive)
        } catch {
            rowFeedback = ("Could not remove: \(error.localizedDescription)", CanonColor.rust)
        }
    }

    private func runProbe() {
        guard let onTest else { return }
        isProbing = true
        rowFeedback = nil
        Task { @MainActor in
            let outcome = await onTest()
            isProbing = false
            switch outcome {
            case .valid:
                rowFeedback = ("Verified — \(provider.label) answered.", CanonColor.olive)
            case .invalidKey(let httpStatus):
                let code = httpStatus > 0 ? " (HTTP \(httpStatus))" : ""
                rowFeedback = ("\(provider.label) rejected this key\(code).", CanonColor.rust)
            case .unreachable:
                rowFeedback = ("Couldn't reach \(provider.label) — a network problem, not a key problem.", CanonColor.muted)
            }
        }
    }
}

private enum ProjectSetupMode {
    case goal
}

private struct ProjectSetupPanel: View {
    let mode: ProjectSetupMode
    @ObservedObject var library: LibraryEngine
    let isHighlighted: Bool
    let onContinueToAesthetic: () -> Void
    private let allowsPanelWidthToggle: Bool
    @Binding private var isPanelExpanded: Bool
    @State private var endGoalDraft = ""
    @FocusState private var isEndGoalFocused: Bool

    init(
        mode: ProjectSetupMode,
        library: LibraryEngine,
        isHighlighted: Bool,
        isPanelExpanded: Binding<Bool>? = nil,
        onContinueToAesthetic: @escaping () -> Void = {}
    ) {
        self.mode = mode
        self.library = library
        self.isHighlighted = isHighlighted
        self.onContinueToAesthetic = onContinueToAesthetic
        self.allowsPanelWidthToggle = isPanelExpanded != nil
        _isPanelExpanded = isPanelExpanded ?? .constant(true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch mode {
                case .goal:
                    goalBlock
                }
            }
            .padding(14)
        }
        .background(CanonColor.paper)
        .foregroundStyle(CanonColor.ink)
        .tint(CanonColor.focusBlue)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isHighlighted ? CanonColor.brass : Color.clear)
                .frame(width: 3)
                .animation(.easeInOut(duration: 0.18), value: isHighlighted)
        }
        .onAppear {
            syncEndGoalDraft()
        }
        .onChange(of: library.currentProject?.projectId ?? "") { _, _ in
            syncEndGoalDraft()
        }
        .onChange(of: library.projectAesthetic.updatedAt) { _, _ in
            if !isEndGoalFocused {
                syncEndGoalDraft()
            }
        }
    }

    private var goalBlock: some View {
        GoalInterviewPanel(
            library: library,
            onContinueToAesthetic: onContinueToAesthetic
        )
    }

    private func syncEndGoalDraft() {
        endGoalDraft = library.projectAesthetic.endGoal
    }
}

private struct FocusedProjectStartView: View {
    let projectName: String
    let onAddMedia: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            LitIconView(icon: .media, size: 48)
                .foregroundStyle(CanonColor.brass)

            VStack(spacing: 6) {
                Text("Begin the archive")
                    .font(CanonType.editorial(28, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text(projectName)
                    .font(CanonType.interface(13, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
                Text("Add media files to start composing a story from real material.")
                    .font(CanonType.editorial(15))
                    .foregroundStyle(CanonColor.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Button {
                onAddMedia()
            } label: {
                LitIconLabel(title: "Add Media", icon: .media)
                    .frame(minWidth: 180)
            }
            .buttonStyle(CanonSecondaryButtonStyle())
            .controlSize(.large)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(CanonColor.archiveWell)
    }
}

private struct FocusedLibraryStatusView: View {
    let title: String
    let subtitle: String
    let icon: LitIcon
    var isLoading = false
    var primaryTitle: String?
    var primaryIcon: LitIcon?
    var primaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            if isLoading {
                ProgressView()
                    .controlSize(.large)
            } else {
                LitIconView(icon: icon, size: 42)
                    .foregroundStyle(CanonColor.brass)
            }

            VStack(spacing: 5) {
                Text(title)
                    .font(CanonType.editorial(24, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text(subtitle)
                    .font(CanonType.interface(13))
                    .foregroundStyle(CanonColor.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            if let primaryTitle, let primaryAction {
                Button {
                    primaryAction()
                } label: {
                    LitIconLabel(title: primaryTitle, icon: primaryIcon ?? .arrowRight)
                        .frame(minWidth: 150)
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .controlSize(.large)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(CanonColor.archiveWell)
    }
}

private struct LibraryStepStrip: View {
    @ObservedObject var library: LibraryEngine

    var body: some View {
        let finalReelPath = library.videoChain.stitchedOutputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasFinalReel = !finalReelPath.isEmpty && FileManager.default.fileExists(atPath: finalReelPath)
        let gates = [
            ("Media", !library.items.isEmpty),
            ("Story", library.isGoalV2Ready),
            ("Characters", library.hasAnyCharacterSheet),
            ("Scenes", !library.readyLenses.isEmpty),
            ("Output", hasFinalReel),
        ]
        let currentIndex = gates.firstIndex { !$0.1 } ?? gates.count - 1

        return HStack(spacing: 8) {
            ForEach(Array(gates.enumerated()), id: \.offset) { index, gate in
                gateView(gate.0, state: gateState(index: index, isComplete: gate.1, currentIndex: currentIndex))
                if index < gates.count - 1 {
                    Text("·")
                        .font(CanonType.interface(12, weight: .semibold))
                        .foregroundStyle(CanonColor.hairlineDark)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private enum GateState {
        case complete
        case current
        case future
    }

    private func gateState(index: Int, isComplete: Bool, currentIndex: Int) -> GateState {
        if isComplete {
            return .complete
        }
        return index == currentIndex ? .current : .future
    }

    private func gateView(_ title: String, state: GateState) -> some View {
        let textColor: Color = switch state {
        case .complete: CanonColor.bone.opacity(0.78)
        case .current: CanonColor.brass
        case .future: CanonColor.muted.opacity(0.64)
        }
        return HStack(spacing: 5) {
            gateDot(state)
            Text(title)
                .font(CanonType.interface(11, weight: .semibold))
                .foregroundStyle(textColor)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func gateDot(_ state: GateState) -> some View {
        switch state {
        case .complete:
            Circle()
                .fill(CanonColor.olive)
                .frame(width: 5, height: 5)
        case .current:
            Circle()
                .fill(CanonColor.brass)
                .frame(width: 6, height: 6)
        case .future:
            Circle()
                .stroke(CanonColor.hairlineDark, lineWidth: 1)
                .frame(width: 6, height: 6)
        }
    }
}

private struct ScreenAreaRecordingHUD: View {
    @ObservedObject var library: LibraryEngine
    @State private var committedOffset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if library.screenAreaRecordingPhase == .needsPermission {
                permissionContent
            } else {
                standardContent
            }

            if library.screenAreaRecordingPhase == .recording {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(elapsedText(now: context.date))
                        .font(CanonType.archive(18, weight: .semibold))
                        .foregroundStyle(CanonColor.brass)
                        .monospacedDigit()
                }
            }
        }
        .padding(12)
        .frame(width: library.screenAreaRecordingPhase == .needsPermission ? 540 : 360, alignment: .leading)
        .background(CanonColor.sidebar, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusTint.opacity(0.70))
        )
        .shadow(color: .black.opacity(0.42), radius: 24, x: 0, y: 14)
        .offset(
            x: committedOffset.width + dragTranslation.width,
            y: committedOffset.height + dragTranslation.height
        )
        .gesture(dragGesture)
    }

    private var standardContent: some View {
        HStack(spacing: 10) {
            statusIcon
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Record Screen Area")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text(statusText)
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(3)
            }
            Spacer(minLength: 0)
            controls
        }
    }

    private var permissionContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                statusIcon
                    .frame(width: 18)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screen Recording Permission")
                        .font(CanonType.interface(13, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                    Text(statusText)
                        .font(CanonType.interface(11, weight: .medium))
                        .foregroundStyle(CanonColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    library.cancelScreenAreaRecording()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Dismiss")
            }

            HStack(spacing: 8) {
                Button {
                    library.openScreenRecordingPrivacySettings()
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }
                .buttonStyle(CanonUtilityButtonStyle())

                Button {
                    library.beginScreenAreaRecordingSelection()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(CanonUtilityButtonStyle())

                Button {
                    library.quitForScreenRecordingPermissionRestart()
                } label: {
                    Label("Quit LitScenes", systemImage: "power")
                }
                .buttonStyle(CanonUtilityButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch library.screenAreaRecordingPhase {
        case .selecting, .starting, .finalizing:
            ProgressView()
                .controlSize(.small)
        case .needsPermission:
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(CanonColor.brass)
        case .recording:
            Circle()
                .fill(CanonColor.rust)
                .frame(width: 10, height: 10)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(CanonColor.rust)
        case .idle:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CanonColor.olive)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch library.screenAreaRecordingPhase {
        case .recording:
            Button {
                library.stopScreenAreaRecording()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(CanonUtilityButtonStyle())
        case .selecting, .starting:
            Button {
                library.cancelScreenAreaRecording()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Cancel")
        case .needsPermission:
            EmptyView()
        case .failed:
            Button {
                library.cancelScreenAreaRecording()
            } label: {
                Label("Dismiss", systemImage: "xmark")
            }
            .buttonStyle(CanonUtilityButtonStyle())
        case .finalizing, .idle:
            EmptyView()
        }
    }

    private var statusText: String {
        if !library.screenAreaRecordingStatus.isEmpty {
            return library.screenAreaRecordingStatus
        }
        switch library.screenAreaRecordingPhase {
        case .needsPermission:
            return "Screen Recording permission required"
        case .selecting:
            return "Drag to select a region"
        case .starting:
            return "Starting"
        case .recording:
            return "Recording"
        case .finalizing:
            return "Saving"
        case .failed:
            return "Failed"
        case .idle:
            return "Idle"
        }
    }

    private var statusTint: Color {
        switch library.screenAreaRecordingPhase {
        case .failed:
            return CanonColor.rust
        case .needsPermission, .recording, .selecting, .starting, .finalizing:
            return CanonColor.brass
        case .idle:
            return CanonColor.olive
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                committedOffset.width += value.translation.width
                committedOffset.height += value.translation.height
            }
    }

    private func elapsedText(now: Date) -> String {
        let startedAt = library.screenAreaRecordingStartedAt ?? now
        let elapsed = max(0, Int(now.timeIntervalSince(startedAt).rounded()))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct MediaAnalysisTailOverlay: View {
    @ObservedObject var library: LibraryEngine
    @Binding var isExpanded: Bool
    let onClose: () -> Void
    @State private var committedOffset: CGSize = .zero
    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        Group {
            if library.mediaAnalysisRunState == .succeeded && !isExpanded {
                completedPill
            } else {
                expandedPanel
            }
        }
        .offset(
            x: committedOffset.width + dragTranslation.width,
            y: committedOffset.height + dragTranslation.height
        )
        .animation(.easeInOut(duration: 0.16), value: isExpanded)
        .animation(.easeInOut(duration: 0.16), value: library.mediaAnalysisRunState)
    }

    private var completedPill: some View {
        HStack(spacing: 8) {
            Button {
                isExpanded = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(CanonColor.olive)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Analyze Media Complete")
                            .font(CanonType.interface(12, weight: .semibold))
                            .foregroundStyle(CanonColor.bone)
                        Text(library.mediaAnalysisStatus)
                            .font(CanonType.interface(10, weight: .medium))
                            .foregroundStyle(CanonColor.muted)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Close")
        }
        .padding(.leading, 13)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(width: 330, alignment: .leading)
        .background(CanonColor.sidebar, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.olive.opacity(0.7))
        )
        .shadow(color: .black.opacity(0.34), radius: 18, x: 0, y: 10)
        .gesture(dragGesture)
    }

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            logTail
        }
        .frame(width: 430, height: 360)
        .background(CanonColor.sidebar, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusTint.opacity(0.68))
        )
        .shadow(color: .black.opacity(0.42), radius: 24, x: 0, y: 14)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Group {
                if library.mediaAnalysisRunState == .running {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: statusIconName)
                        .foregroundStyle(statusTint)
                }
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Analyze Media")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text(library.mediaAnalysisStatus)
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if library.mediaAnalysisRunState == .running {
                cancelButton
            }

            if library.mediaAnalysisRunState == .succeeded {
                Button {
                    isExpanded = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Minimize")
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .disabled(library.mediaAnalysisRunState == .running)
            .help(library.mediaAnalysisRunState == .running ? "Analysis is still running" : "Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private var logTail: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    if library.mediaAnalysisLogEntries.isEmpty {
                        Text("Waiting for analysis entries")
                            .font(CanonType.interface(12, weight: .medium))
                            .foregroundStyle(CanonColor.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(library.mediaAnalysisLogEntries) { entry in
                            logEntryRow(entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(12)
            }
            .background(CanonColor.archiveWell)
            .onAppear {
                scrollToLatest(proxy)
            }
            .onChange(of: library.mediaAnalysisLogEntries.count) { _, _ in
                scrollToLatest(proxy)
            }
        }
    }

    private func logEntryRow(_ entry: MediaAnalysisLogEntry) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: iconName(for: entry.kind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(color(for: entry.kind))
                .frame(width: 16, height: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(shortTimestamp(entry.timestamp))
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(CanonColor.muted.opacity(0.8))
                Text(entry.message)
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.bone)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                committedOffset.width += value.translation.width
                committedOffset.height += value.translation.height
            }
    }

    private var statusTint: Color {
        switch library.mediaAnalysisRunState {
        case .idle:
            return CanonColor.muted
        case .running:
            return CanonColor.brass
        case .succeeded:
            return CanonColor.olive
        case .cancelled:
            return CanonColor.rust
        case .failed:
            return CanonColor.rust
        }
    }

    private var statusIconName: String {
        switch library.mediaAnalysisRunState {
        case .idle:
            return "circle"
        case .running:
            return "hourglass"
        case .succeeded:
            return "checkmark.circle.fill"
        case .cancelled:
            return "xmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var cancelButton: some View {
        Button {
            if library.mediaAnalysisCancelRequested {
                return
            }
            if library.mediaAnalysisCancelArmed {
                library.confirmMediaAnalysisCancel()
            } else {
                library.armMediaAnalysisCancel()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: library.mediaAnalysisCancelArmed ? "xmark.octagon.fill" : "xmark.circle")
                    .font(.caption.weight(.bold))
                Text(mediaAnalysisCancelTitle)
                    .font(CanonType.interface(11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(mediaAnalysisCancelForeground)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                mediaAnalysisCancelBackground,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(mediaAnalysisCancelStroke)
            )
        }
        .buttonStyle(.plain)
        .disabled(library.mediaAnalysisCancelRequested)
        .help(mediaAnalysisCancelHelp)
    }

    private var mediaAnalysisCancelTitle: String {
        if library.mediaAnalysisCancelRequested {
            return "Cancelling"
        }
        return library.mediaAnalysisCancelArmed ? "Click one more to cancel" : "Cancel"
    }

    private var mediaAnalysisCancelHelp: String {
        if library.mediaAnalysisCancelRequested {
            return "Analysis will stop after the current item saves"
        }
        if library.mediaAnalysisCancelArmed {
            return "Confirm cancellation after the current item saves"
        }
        return "Arm media analysis cancellation"
    }

    private var mediaAnalysisCancelForeground: Color {
        if library.mediaAnalysisCancelRequested {
            return CanonColor.muted
        }
        return library.mediaAnalysisCancelArmed ? CanonColor.bone : CanonColor.rust
    }

    private var mediaAnalysisCancelBackground: Color {
        if library.mediaAnalysisCancelRequested {
            return CanonColor.archiveWell.opacity(0.72)
        }
        return library.mediaAnalysisCancelArmed ? CanonColor.rust.opacity(0.78) : CanonColor.rust.opacity(0.12)
    }

    private var mediaAnalysisCancelStroke: Color {
        if library.mediaAnalysisCancelRequested {
            return CanonColor.hairlineDark
        }
        return library.mediaAnalysisCancelArmed ? CanonColor.rust.opacity(0.95) : CanonColor.rust.opacity(0.42)
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let id = library.mediaAnalysisLogEntries.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.12)) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        }
    }

    private func shortTimestamp(_ timestamp: String) -> String {
        let trimmed = String(timestamp.prefix(19))
        return trimmed.replacingOccurrences(of: "T", with: " ")
    }

    private func iconName(for kind: String) -> String {
        switch kind {
        case "start":
            return "play.circle"
        case "skip":
            return "forward.circle"
        case "analyze":
            return "sparkles"
        case "saved":
            return "checkmark.circle"
        case "summary":
            return "list.bullet.rectangle"
        case "complete":
            return "checkmark.seal"
        case "cancel", "cancelled":
            return "xmark.circle"
        case "error":
            return "exclamationmark.triangle"
        default:
            return "circle"
        }
    }

    private func color(for kind: String) -> Color {
        switch kind {
        case "saved", "complete":
            return CanonColor.olive
        case "cancel", "cancelled":
            return CanonColor.rust
        case "error":
            return CanonColor.rust
        case "analyze", "start", "summary":
            return CanonColor.brass
        default:
            return CanonColor.muted
        }
    }
}

private struct RenameProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let onRename: (String) -> Void

    init(initialName: String, onRename: @escaping (String) -> Void) {
        _name = State(initialValue: initialName)
        self.onRename = onRename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Rename Project")
                    .font(CanonType.editorial(22, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Cancel")
            }
            .padding(16)

            Rectangle()
                .fill(CanonColor.hairlinePaper)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Project name", text: $name)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Spacer()
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(CanonSecondaryButtonStyle())
                    Button {
                        onRename(name)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .buttonStyle(CanonPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(16)
        }
        .background(CanonColor.paper)
        .foregroundStyle(CanonColor.ink)
    }
}

private struct SourceContextRow: View {
    let source: SourceContextRecord
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: source.kind.systemImage)
                .foregroundStyle(CanonColor.muted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                    .lineLimit(1)
                Text(source.notes.isEmpty ? source.kind.label : source.notes)
                    .font(CanonType.archive(10))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(CanonColor.muted)
            .help("Remove")
        }
        .help(source.path)
    }
}

private struct ProjectSidebarRow: View {
    let project: ProjectRecord
    let isSelected: Bool
    let isExpanded: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            Group {
                if isExpanded {
                    HStack(spacing: 9) {
                        Image(systemName: isSelected ? "folder.fill" : "folder")
                            .foregroundStyle(isSelected ? CanonColor.brass : CanonColor.muted)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(CanonType.interface(13, weight: .semibold))
                                .foregroundStyle(CanonColor.bone)
                                .lineLimit(1)
                            Text("\(project.sessionCount) session\(project.sessionCount == 1 ? "" : "s")")
                                .font(CanonType.archive(10))
                                .foregroundStyle(CanonColor.muted)
                        }
                        Spacer()
                    }
                } else {
                    Text(project.name)
                        .font(CanonType.interface(10, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(EdgeInsets(
                top: ProjectSidebarMetrics.rowVerticalPadding,
                leading: isExpanded ? ProjectSidebarMetrics.rowHorizontalPadding : ProjectSidebarMetrics.collapsedRowHorizontalPadding,
                bottom: ProjectSidebarMetrics.rowVerticalPadding,
                trailing: isExpanded ? ProjectSidebarMetrics.rowHorizontalPadding : ProjectSidebarMetrics.collapsedRowHorizontalPadding
            ))
            .frame(maxWidth: .infinity, minHeight: ProjectSidebarMetrics.rowHeight, maxHeight: ProjectSidebarMetrics.rowHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? CanonColor.mediaCardHover : CanonColor.mediaCard.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? CanonColor.brass.opacity(0.58) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyLibraryState: View {
    let title: String
    let subtitle: String
    let icon: LitIcon

    var body: some View {
        VStack(spacing: 12) {
            LitIconView(icon: icon, size: 38)
                .foregroundStyle(CanonColor.brass)
            Text(title)
                .font(CanonType.editorial(26, weight: .semibold))
                .foregroundStyle(CanonColor.bone)
            Text(subtitle)
                .font(CanonType.editorial(15))
                .foregroundStyle(CanonColor.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanonColor.room)
    }
}

private enum ScenesRightRailItem: String, CaseIterable, Identifiable {
    case sound
    case memes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sound: return "Sound"
        case .memes: return "Memes"
        }
    }

    @ViewBuilder
    func icon(size: CGFloat) -> some View {
        switch self {
        case .sound:
            LitIconView(icon: .waveform, size: size)
        case .memes:
            Image(systemName: "face.smiling")
                .font(.system(size: size, weight: .semibold))
        }
    }
}

struct ScenesWorkspaceView: View {
    @ObservedObject var library: LibraryEngine
    let onOpenAesthetic: () -> Void
    var isEmbeddedInStoryWorkspace = false
    private let rightRailCollapsedWidth: CGFloat = 52
    private let rightRailExpandedWidth: CGFloat = 280
    @State private var elevenAPIKey = ""
    @State private var elevenCustomVoiceId = ElevenLabsSettingsStore.resolvedCustomVoiceId() ?? ""
    @State private var elevenSettingsMessage = ""
    @State private var elevenSettingsRevision = 0
    @State private var isLayersPanelExpanded = false
    @State private var isAdvancedLayersExpanded = false
    @State private var selectedSceneBeatId = ""
    @State private var selectedSceneLayer = SceneLayerType.still
    @State private var selectedVideoSegmentId = ""
    @State private var selectedVideoPreset = VideoChainPreset.youtubeStoryReel
    @State private var selectedVideoProvider = VideoProviderSelection.bestAvailable
    @State private var selectedVideoModel = VideoModelSelection.auto
    @State private var videoResultCopyStatus = ""
    @State private var focusedStorySceneKey = ""
    @State private var selectedStoryEntryId = ""
    @State private var expandedSoundRailAssetId = ""
    @State private var selectedRightRailItem: ScenesRightRailItem = .sound
    @State private var isRightRailHovered = false
    @StateObject private var soundRailPlayer = SoundRailPlayerController()
    @StateObject private var soundWaveformLoader = SoundWaveformLoader()

    var body: some View {
        Group {
            if isEmbeddedInStoryWorkspace || !library.readyLenses.isEmpty {
                scenesWorkbench
            } else {
                StoryGateView(onOpenAesthetic: onOpenAesthetic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanonColor.paper)
        .onAppear {
            library.ensureActiveVideoChainLoaded()
            syncVideoControls()
        }
        .onChange(of: library.videoChain.chainId) { _, _ in
            syncVideoControls()
            reconcileSelectedVideoSegment()
        }
        .onChange(of: library.videoChain.segments.map(\.segmentId).joined(separator: "|")) { _, _ in
            reconcileSelectedVideoSegment()
        }
    }

    private var scenesWorkbench: some View {
        GeometryReader { geometry in
            scenesMainSurface(viewportHeight: geometry.size.height)
        }
    }

    @ViewBuilder
    private func scenesMainSurface(viewportHeight: CGFloat) -> some View {
        if isEmbeddedInStoryWorkspace {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    storyLibraryTopBar
                    initialStoryAutomationPanel
                    sceneStoryProgressPanel
                    sceneStoryVideoPlanStatus
                    storyLibrarySurface
                }
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .topLeading)
            }
            .defaultScrollAnchor(.top)
            .foregroundStyle(CanonColor.ink)
            .tint(CanonColor.focusBlue)
        } else {
            let contentMaxWidth: CGFloat = 1880
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    storyLibraryTopBar
                    sceneStoryProgressPanel
                    sceneStoryVideoPlanStatus
                    scenesUnifiedWorkspaceSurface(viewportHeight: viewportHeight)
                }
                .padding(24)
                .frame(maxWidth: contentMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .topLeading)
            }
            .defaultScrollAnchor(.top)
            .foregroundStyle(CanonColor.ink)
            .tint(CanonColor.focusBlue)
            .task {
                await library.refreshSoundSceneTimeline()
            }
        }
    }

    @ViewBuilder
    private var storyLibraryTopBar: some View {
        if isEmbeddedInStoryWorkspace {
            VStack(alignment: .leading, spacing: 6) {
                Text("Story Library")
                    .font(CanonType.editorial(28, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Text("The first three Stories appear here automatically once intent, cast, context, and Frames are ready.")
                    .font(CanonType.interface(13, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
                storyLibraryActions
                    .padding(.top, 5)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Story Library")
                        .font(CanonType.editorial(36, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    Text("Select a Story, inspect its Scene and Beat structure, compare alternatives, then develop the version worth producing.")
                        .font(CanonType.interface(15, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.64))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 980, alignment: .leading)

                Spacer(minLength: 0)
                storyLibraryActions
            }
        }
    }

    private var storyLibraryActions: some View {
        VStack(alignment: isEmbeddedInStoryWorkspace ? .leading : .trailing, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                if library.canRetryLensContextRetrieval || library.isRetrievingLensContext {
                    Button {
                        library.retryLensContextRetrieval()
                    } label: {
                        Label(library.isRetrievingLensContext ? "Retrieving Context" : "Retry Frame Context", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(CanonSecondaryButtonStyle())
                    .disabled(library.isRetrievingLensContext)
                }

                Button {
                    Task {
                        await library.generateSceneStoriesForReadyLens()
                    }
                } label: {
                    Label(sceneStoryGenerateButtonTitle, systemImage: "sparkles")
                }
                .buttonStyle(CanonPrimaryButtonStyle())
                .disabled(!library.canGenerateSceneStories)
            }

            if library.isGeneratingSceneStories || library.isRetrievingLensContext {
                HStack(alignment: .center, spacing: 7) {
                    ProgressView()
                        .controlSize(.small)
                    Text(library.isGeneratingSceneStories ? library.sceneStoryStatus : library.lensContextStatus)
                        .font(CanonType.interface(12, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.62))
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var initialStoryAutomationPanel: some View {
        if !library.hasVisibleStoryLibraryEntries {
            HStack(alignment: .top, spacing: 9) {
                if library.isGeneratingSceneStories || library.isArticulatingGoalCast || library.isRetrievingLensContext || library.isGeneratingInitialDraftLenses {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Circle()
                        .fill(library.canGenerateSceneStories ? CanonColor.olive : CanonColor.brass)
                        .frame(width: 7, height: 7)
                        .padding(.top, 4)
                }
                Text(library.initialStoryAutomationStatus)
                    .font(CanonType.interface(12, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CanonColor.paperInset.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
        }
    }

    private var sceneStoryGenerateButtonTitle: String {
        if library.isGeneratingSceneStories {
            return "Generating..."
        }
        if library.sceneStoryGenerationProgress.isFailed {
            return "Retry Stories"
        }
        if !library.hasVisibleStoryLibraryEntries && library.hasStoryGenerationAttemptForActiveGoal {
            return "Retry Stories"
        }
        return library.hasVisibleStoryLibraryEntries ? "Generate 3 More Stories" : "Generate 3 Stories"
    }

    @ViewBuilder
    private var sceneStoryProgressPanel: some View {
        let progress = library.sceneStoryGenerationProgress
        let session = sceneStoryProgressSession
        if progress.isActive {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.title)
                        .font(CanonType.interface(13, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    if !progress.detail.trimmed.isEmpty {
                        Text(progress.detail)
                            .font(CanonType.interface(12))
                            .foregroundStyle(CanonColor.ink.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ProgressView(value: sceneStoryProgressFraction(progress: progress, session: session))
                    .tint(sceneStoryProgressTint(progress: progress, session: session))
                VStack(alignment: .leading, spacing: 6) {
                    if let session, !session.slots.isEmpty {
                        ForEach(session.slots.sorted { $0.index < $1.index }) { slot in
                            storyGenerationSlotProgressRow(slot)
                        }
                    } else {
                        ForEach(Array(sceneStoryProgressLabels.enumerated()), id: \.offset) { index, label in
                            sceneStoryProgressRow(label: label, index: index, progress: progress)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
        }
    }

    private var sceneStoryProgressLabels: [String] {
        [
            "Preparing creative context",
            "Creating Story 1 of 3",
            "Creating Story 2 of 3",
            "Creating Story 3 of 3",
            "Comparing against existing Stories",
            "Ready for review"
        ]
    }

    private var sceneStoryProgressSession: StoryGenerationSessionDocument? {
        library.storyGenerationSessions.first
    }

    private func sceneStoryProgressFraction(
        progress: SceneStoryGenerationProgress,
        session: StoryGenerationSessionDocument?
    ) -> Double {
        guard let session, !session.slots.isEmpty else {
            return progress.fractionCompleted
        }
        let resolved = session.slots.filter { slot in
            slot.status == .complete || slot.status == .failed || slot.status == .cancelled
        }.count
        return min(max(Double(resolved) / Double(max(session.requestedStoryCount, 1)), 0), 1)
    }

    private func sceneStoryProgressTint(
        progress: SceneStoryGenerationProgress,
        session: StoryGenerationSessionDocument?
    ) -> Color {
        if session?.failedSlotCount ?? 0 > 0 || progress.isFailed {
            return CanonColor.rust
        }
        return CanonColor.brass
    }

    private func sceneStoryProgressRow(
        label: String,
        index: Int,
        progress: SceneStoryGenerationProgress
    ) -> some View {
        let state = sceneStoryProgressState(index: index, progress: progress)
        return HStack(spacing: 8) {
            sceneStoryProgressIcon(state)
            Text(label)
                .font(CanonType.interface(12, weight: .medium))
                .foregroundStyle(CanonColor.ink)
            Spacer(minLength: 0)
            Text(state)
                .font(CanonType.archive(10, weight: .semibold))
                .foregroundStyle(sceneStoryProgressColor(state))
        }
        .padding(8)
        .background(Color.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 7))
    }

    private func storyGenerationSlotProgressRow(_ slot: StoryGenerationResultSlot) -> some View {
        let state = storyGenerationSlotState(slot)
        let title = slot.title.trimmed
        let label = title.isEmpty ? "Story \(slot.index)" : "Story \(slot.index): \(title)"
        return HStack(spacing: 8) {
            sceneStoryProgressIcon(state)
            Text(label)
                .font(CanonType.interface(12, weight: .medium))
                .foregroundStyle(CanonColor.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(storyGenerationSlotStatusText(slot))
                .font(CanonType.archive(10, weight: .semibold))
                .foregroundStyle(sceneStoryProgressColor(state))
        }
        .padding(8)
        .background(Color.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 7))
    }

    private func storyGenerationSlotState(_ slot: StoryGenerationResultSlot) -> String {
        switch slot.status {
        case .complete:
            return "ready"
        case .generating:
            return "active"
        case .failed:
            return "failed"
        case .cancelled:
            return "cancelled"
        case .queued:
            return "queued"
        }
    }

    private func storyGenerationSlotStatusText(_ slot: StoryGenerationResultSlot) -> String {
        switch slot.status {
        case .complete:
            return "complete"
        case .generating:
            return "generating"
        case .failed:
            return isTimeoutError(slot.errorMessage) ? "timed out" : "failed"
        case .cancelled:
            return "cancelled"
        case .queued:
            return "queued"
        }
    }

    private func isTimeoutError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("timeout") || lowered.contains("timed out") || lowered.contains("504")
    }

    @ViewBuilder
    private func sceneStoryProgressIcon(_ state: String) -> some View {
        Group {
            switch state {
            case "ready":
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CanonColor.olive)
            case "active":
                SceneStoryActiveLoadingRing()
            case "failed":
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(CanonColor.rust)
            case "cancelled":
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(CanonColor.rust)
            default:
                Image(systemName: "circle")
                    .foregroundStyle(CanonColor.ink.opacity(0.34))
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .frame(width: 18, height: 18)
    }

    private func sceneStoryProgressState(index: Int, progress: SceneStoryGenerationProgress) -> String {
        if progress.isFailed {
            return index == max(progress.completedStepCount - 1, 0) ? "failed" : "queued"
        }
        if progress.status == "ready" {
            return "ready"
        }
        if index + 1 < progress.completedStepCount {
            return "ready"
        }
        if index + 1 == progress.completedStepCount {
            return "active"
        }
        return "queued"
    }

    private func sceneStoryProgressColor(_ state: String) -> Color {
        switch state {
        case "ready":
            return CanonColor.olive
        case "active":
            return CanonColor.brass
        case "failed":
            return CanonColor.rust
        case "cancelled":
            return CanonColor.rust
        default:
            return CanonColor.ink.opacity(0.50)
        }
    }

    @ViewBuilder
    private var sceneStoryVideoPlanStatus: some View {
        if library.videoChain.sourceArtifactType == .sceneStory, !library.videoChain.chainId.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "film.stack")
                    .foregroundStyle(CanonColor.brass)
                VStack(alignment: .leading, spacing: 3) {
                    Text("SceneStory Video Plan")
                        .font(CanonType.editorial(17, weight: .semibold))
                    Text("\(library.videoChain.title) · \(library.videoChain.clipSummary) · \(library.videoChainStatus)")
                        .font(CanonType.interface(12, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.62))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button {
                    Task {
                        await library.generateActiveVideoChain()
                    }
                } label: {
                    Label(library.isGeneratingVideoChain ? "Generating Chain" : "Generate Chain", systemImage: "play.rectangle")
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(library.isGeneratingVideoChain || library.videoChain.preflightBlockers.isEmpty == false)
            }
            .padding(12)
            .background(CanonColor.paperInset.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
        }
    }

    @ViewBuilder
    private var storyLibrarySurface: some View {
        storiesWritersRoomSurface
    }

    private func scenesUnifiedWorkspaceSurface(viewportHeight: CGFloat) -> some View {
        let workspaceMinHeight = max(viewportHeight - 176, 520)
        return HStack(alignment: .top, spacing: 16) {
            storyLibrarySurface
                .frame(maxWidth: .infinity, alignment: .topLeading)
            scenesRightRail
                .frame(width: scenesRightRailWidth, alignment: .topLeading)
                .frame(minHeight: workspaceMinHeight, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: workspaceMinHeight, alignment: .topLeading)
    }

    private var scenesRightRailWidth: CGFloat {
        isRightRailHovered ? rightRailExpandedWidth : rightRailCollapsedWidth
    }

    private var scenesRightRail: some View {
        HStack(alignment: .top, spacing: 0) {
            scenesRightRailNavigation
                .frame(width: rightRailCollapsedWidth)

            if isRightRailHovered {
                Rectangle()
                    .fill(CanonColor.hairlinePaper.opacity(0.72))
                    .frame(width: 1)
                scenesRightRailPanel
                    .frame(width: rightRailExpandedWidth - rightRailCollapsedWidth - 1, alignment: .topLeading)
                    .transition(.opacity)
            }
        }
        .frame(width: scenesRightRailWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(CanonColor.paperInset.opacity(0.54), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.86)))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isRightRailHovered = hovering
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isRightRailHovered)
        .onDisappear {
            soundRailPlayer.pause()
        }
    }

    private var scenesRightRailNavigation: some View {
        VStack(alignment: .center, spacing: 8) {
            ForEach(ScenesRightRailItem.allCases) { item in
                scenesRightRailButton(item)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CanonColor.sidebar)
    }

    private func scenesRightRailButton(_ item: ScenesRightRailItem) -> some View {
        let selected = selectedRightRailItem == item
        return Button {
            selectedRightRailItem = item
            withAnimation(.easeInOut(duration: 0.16)) {
                isRightRailHovered = true
            }
        } label: {
            item.icon(size: 18)
                .foregroundStyle(selected ? CanonColor.softGold : CanonColor.bone.opacity(0.72))
                .frame(width: 36, height: 36)
                .background(selected ? CanonColor.mediaCardHover : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? CanonColor.brass.opacity(0.62) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.label)
        .accessibilityLabel(item.label)
    }

    @ViewBuilder
    private var scenesRightRailPanel: some View {
        switch selectedRightRailItem {
        case .sound:
            scenesSoundBrowserRail
        case .memes:
            scenesMemesRail
        }
    }

    private var scenesSoundBrowserRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sound")
                        .font(CanonType.editorial(20, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    Text(soundRailSubtitle)
                        .font(CanonType.interface(11, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.58))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if library.isLoadingSoundSceneTimeline {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    Task {
                        await library.refreshSoundSceneTimeline()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .disabled(library.isLoadingSoundSceneTimeline)
                .help("Refresh sounds")
            }

            if let selected = library.selectedSoundSceneAsset {
                selectedSoundRailCard(selected)
            } else {
                Text(library.isLoadingSoundSceneTimeline ? "Scanning for sound files." : "No sound selected.")
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.58))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CanonColor.paper.opacity(0.50), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.76)))
            }

            if library.soundSceneAssets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No sound files found")
                        .font(CanonType.interface(12, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    Text("Add files to `sounds/` or `audio/`, then refresh.")
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.ink.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.76)))
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(library.soundSceneAssets) { asset in
                        soundRailRow(asset)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var scenesMemesRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memes")
                        .font(CanonType.editorial(20, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    Text("Empty")
                        .font(CanonType.interface(11, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.58))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "face.smiling")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
                    .frame(width: 26, height: 26)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("No memes yet")
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.76)))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var soundRailSubtitle: String {
        if library.soundSceneAssets.isEmpty {
            return library.soundSceneTimelineStatus
        }
        return "\(library.soundSceneAssets.count) sound\(library.soundSceneAssets.count == 1 ? "" : "s")"
    }

    private func selectedSoundRailCard(_ asset: SoundSceneAsset) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(asset.displayName)
                .font(CanonType.editorial(15, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .lineLimit(2)
            Text("\(asset.durationLabel) · \(asset.fileTypeLabel)")
                .font(CanonType.archive(10, weight: .medium))
                .foregroundStyle(CanonColor.brass)
                .lineLimit(1)
            Text(library.soundSceneTimelineStatus)
                .font(CanonType.interface(10, weight: .medium))
                .foregroundStyle(CanonColor.ink.opacity(0.56))
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.paper.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.brass.opacity(0.46)))
    }

    private func soundRailRow(_ asset: SoundSceneAsset) -> some View {
        let selected = asset.soundId == library.selectedSoundSceneAssetId
        let expanded = expandedSoundRailAssetId == asset.soundId
        let playing = soundRailPlayer.isPlayingAsset(soundId: asset.soundId, path: asset.path)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    playSoundRailAsset(asset)
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .disabled(!soundRailPlayer.canPlay(soundId: asset.soundId, path: asset.path))
                .help(playing ? "Pause" : "Play")

                Button {
                    library.selectSoundSceneAsset(soundId: asset.soundId)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(asset.displayName)
                            .font(CanonType.interface(11, weight: .semibold))
                            .foregroundStyle(CanonColor.ink)
                            .lineLimit(2)
                        Text("\(asset.durationLabel) · \(asset.fileTypeLabel)")
                            .font(CanonType.archive(9, weight: .medium))
                            .foregroundStyle(CanonColor.ink.opacity(0.54))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if expanded {
                SoundRailPlayerTransport(
                    player: soundRailPlayer,
                    waveformLoader: soundWaveformLoader,
                    asset: asset
                )
                    .padding(.leading, 34)
                    .transition(.opacity)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? CanonColor.paperAged.opacity(0.74) : Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected || expanded ? CanonColor.brass.opacity(0.70) : CanonColor.hairlinePaper.opacity(0.72)))
    }

    private func playSoundRailAsset(_ asset: SoundSceneAsset) {
        library.selectSoundSceneAsset(soundId: asset.soundId)
        expandedSoundRailAssetId = asset.soundId
        soundRailPlayer.toggle(soundId: asset.soundId, path: asset.path)
    }

    @ViewBuilder
    private var storiesWritersRoomSurface: some View {
        if !library.hasVisibleStoryLibraryEntries {
            VStack(alignment: .leading, spacing: 12) {
                Text("No Stories yet.")
                    .font(CanonType.interface(12, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.60))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
            }
        } else {
            let entries = storyRailEntries
            VStack(alignment: .leading, spacing: 14) {
                if isEmbeddedInStoryWorkspace {
                    storyLibraryRail(entries: entries)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    storyDetailOrComparePane
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        storyLibraryRail(entries: entries)
                            .frame(width: 356)
                        storyDetailOrComparePane
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .onAppear {
                reconcileSelectedStoryEntry()
            }
            .onChange(of: library.storyLibrary.entries.map(\.libraryEntryId).joined(separator: "|")) { _, _ in
                reconcileSelectedStoryEntry()
            }
        }
    }

    private var storyRailEntries: [ProjectStoryLibraryEntry] {
        library.storyLibrary.visibleEntries
    }

    private var selectedStoryEntry: ProjectStoryLibraryEntry? {
        if let entry = storyRailEntries.first(where: { $0.libraryEntryId == selectedStoryEntryId }) {
            return entry
        }
        return library.storyLibrary.preferredEntry
    }

    private func isRemovedStoryEntry(_ entry: ProjectStoryLibraryEntry) -> Bool {
        entry.editorialState == .dismissed || entry.editorialState == .archived
    }

    private func reconcileSelectedStoryEntry() {
        guard let preferred = library.storyLibrary.preferredEntry else {
            selectedStoryEntryId = ""
            return
        }
        if !storyRailEntries.contains(where: { $0.libraryEntryId == selectedStoryEntryId }) {
            selectedStoryEntryId = preferred.libraryEntryId
        }
    }

    private func selectStoryEntry(_ entry: ProjectStoryLibraryEntry) {
        selectedStoryEntryId = entry.libraryEntryId
        if !entry.projectStoryId.trimmed.isEmpty && !isRemovedStoryEntry(entry) {
            library.selectStoryLibraryEntry(libraryEntryId: entry.libraryEntryId)
        }
    }

    private func storyLibraryRail(entries: [ProjectStoryLibraryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if entries.isEmpty {
                Text(storyRailEmptyMessage)
                    .font(CanonType.interface(12, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.58))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(entries) { entry in
                        storyListRow(entry)
                    }
                }
            }
        }
    }

    private var storyRailEmptyMessage: String {
        "No visible Stories. Generate Stories to add one."
    }

    private func storyListRow(_ entry: ProjectStoryLibraryEntry) -> some View {
        let signature = storyLibrarySignature(for: entry)
        let story = library.sceneStorySnapshot(for: entry)
        let title = storyTitle(entry: entry, signature: signature)
        let selected = selectedStoryEntryId == entry.libraryEntryId
        return Button {
            selectStoryEntry(entry)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(CanonType.editorial(15, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                Text(storyPremise(signature: signature, story: story))
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.ink.opacity(0.62))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    StoryMiniChip(storyStateLabel(entry.editorialState), tone: chipTone(for: entry.editorialState))
                    if entry.productionState != .notStarted {
                        StoryMiniChip(productionStateLabel(entry.productionState), tone: chipTone(for: entry.productionState))
                    }
                    StoryMiniChip("\(storySceneCount(story: story, signature: signature)) scene\(storySceneCount(story: story, signature: signature) == 1 ? "" : "s")", tone: .muted)
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(selected ? CanonColor.brass : Color.clear)
                    .frame(width: 4)
            }
            .contentShape(Rectangle())
            .accessibilityLabel("\(title), \(storyStateLabel(entry.editorialState)), \(storySceneCount(story: story, signature: signature)) scenes")
        }
        .buttonStyle(.plain)
        .background(selected ? CanonColor.paperAged.opacity(0.92) : Color.white.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? CanonColor.brass.opacity(0.74) : CanonColor.hairlinePaper.opacity(0.78)))
    }

    @ViewBuilder
    private var storyDetailOrComparePane: some View {
        if let entry = selectedStoryEntry {
            storyDetailPane(entry)
        } else {
            storyDetailEmptyPane
        }
    }

    private var storyDetailEmptyPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select a Story")
                .font(CanonType.editorial(22, weight: .semibold))
            Text("Choose a Story from the Library rail to inspect its scenes and beats.")
                .font(CanonType.interface(12, weight: .medium))
                .foregroundStyle(CanonColor.ink.opacity(0.62))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.paperInset.opacity(0.52), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
    }

    private func storyDetailPane(_ entry: ProjectStoryLibraryEntry) -> some View {
        let signature = storyLibrarySignature(for: entry)
        let story = library.sceneStorySnapshot(for: entry)
        let focusToken = [
            entry.libraryEntryId,
            story?.storyId ?? "",
            story?.scenes.map(\.sceneId).joined(separator: "|") ?? ""
        ].joined(separator: ":")
        return VStack(alignment: .leading, spacing: 14) {
            storyDetailHeader(entry: entry, story: story, signature: signature)
            storyDetailDivider
            storySceneArcList(entry: entry, story: story)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(CanonColor.paperInset.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.88)))
        .onAppear {
            reconcileFocusedStoryScene(entry: entry, story: story)
        }
        .onChange(of: focusToken) { _, _ in
            reconcileFocusedStoryScene(entry: entry, story: story)
        }
    }

    private func storyDetailHeader(
        entry: ProjectStoryLibraryEntry,
        story: SceneStory?,
        signature: StorySignatureDocument?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(storyTitle(entry: entry, signature: signature))
                    .font(CanonType.editorial(34, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(storyPremise(signature: signature, story: story))
                    .font(CanonType.editorial(17))
                    .italic()
                    .lineSpacing(5)
                    .foregroundStyle(CanonColor.ink.opacity(0.72))
                    .frame(maxWidth: 980, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func storySceneArcList(entry: ProjectStoryLibraryEntry, story: SceneStory?) -> some View {
        if let story, !story.scenes.isEmpty {
            let scenes = story.scenes.sorted { $0.order < $1.order }
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 8) {
                    ForEach(scenes) { scene in
                        storySceneArcCard(entry: entry, story: story, scene: scene, scenes: scenes)
                    }
                }
            }
        } else {
            Text("No linked Scene data found.")
                .font(CanonType.editorial(14))
                .foregroundStyle(CanonColor.ink.opacity(0.72))
        }
    }

    @ViewBuilder
    private func storySceneArcCard(
        entry: ProjectStoryLibraryEntry,
        story: SceneStory,
        scene: SceneStoryScene,
        scenes: [SceneStoryScene]
    ) -> some View {
        let sceneKey = storySceneKey(entry: entry, story: story, scene: scene)
        let isFocused = currentFocusedStorySceneKey(entry: entry, story: story, scenes: scenes) == sceneKey
        if isFocused {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        focusedStorySceneKey = sceneKey
                    }
                } label: {
                    storySceneArcCardHeader(scene: scene, isFocused: true)
                }
                .buttonStyle(.plain)

                if !scene.sceneDescription.trimmed.isEmpty {
                    Text(scene.sceneDescription)
                        .font(CanonType.editorial(15))
                        .lineSpacing(4)
                        .foregroundStyle(CanonColor.ink.opacity(0.76))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !scene.sceneBeats.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(scene.sceneBeats.sorted { $0.order < $1.order }) { beat in
                            BeatProductionCard(beat: beat)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.86)))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Scene \(max(scene.order, 1)), \(scene.title.trimmed.isEmpty ? "Scene" : scene.title), selected, \(scene.sceneBeats.count) beats")
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    focusedStorySceneKey = sceneKey
                }
            } label: {
                storySceneArcCardHeader(scene: scene, isFocused: false)
                    .padding(.vertical, 11)
                    .padding(.horizontal, 8)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper.opacity(0.45)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scene \(max(scene.order, 1)), \(scene.title.trimmed.isEmpty ? "Scene" : scene.title), \(scene.sceneBeats.count) beats")
        }
    }

    private func storySceneArcCardHeader(scene: SceneStoryScene, isFocused: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(String(format: "%02d", max(scene.order, 1)))
                .font(CanonType.editorial(isFocused ? 25 : 21, weight: .semibold))
                .foregroundStyle(isFocused ? CanonColor.brass : CanonColor.ink.opacity(0.34))
                .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(scene.title.trimmed.isEmpty ? "Scene" : scene.title)
                    .font(CanonType.editorial(isFocused ? 24 : 18, weight: isFocused ? .semibold : .medium))
                    .foregroundStyle(CanonColor.ink)
                    .lineLimit(isFocused ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(storyLibrarySceneSummary(scene))
                    .font(CanonType.interface(12, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(isFocused ? 0.62 : 0.54))
                    .lineLimit(isFocused ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: isFocused ? "minus" : "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isFocused ? CanonColor.brass : CanonColor.ink.opacity(0.42))
                .frame(width: 18)
        }
    }

    private var storyDetailDivider: some View {
        Rectangle()
            .fill(CanonColor.hairlinePaper.opacity(0.64))
            .frame(height: 1)
    }

    private func storySceneKey(
        entry: ProjectStoryLibraryEntry,
        story: SceneStory,
        scene: SceneStoryScene
    ) -> String {
        "writers_room:\(entry.libraryEntryId):\(story.storyId):\(scene.sceneId)"
    }

    private func currentFocusedStorySceneKey(
        entry: ProjectStoryLibraryEntry,
        story: SceneStory,
        scenes: [SceneStoryScene]
    ) -> String {
        if scenes.contains(where: { storySceneKey(entry: entry, story: story, scene: $0) == focusedStorySceneKey }) {
            return focusedStorySceneKey
        }
        guard let first = scenes.first else { return "" }
        return storySceneKey(entry: entry, story: story, scene: first)
    }

    private func reconcileFocusedStoryScene(entry: ProjectStoryLibraryEntry, story: SceneStory?) {
        guard let story else {
            focusedStorySceneKey = ""
            return
        }
        let scenes = story.scenes.sorted { $0.order < $1.order }
        let key = currentFocusedStorySceneKey(entry: entry, story: story, scenes: scenes)
        if focusedStorySceneKey != key {
            focusedStorySceneKey = key
        }
    }

    private func storyTitle(entry: ProjectStoryLibraryEntry, signature: StorySignatureDocument?) -> String {
        let entryTitle = entry.title.trimmed
        if !entryTitle.isEmpty { return entryTitle }
        let signatureTitle = signature?.title.trimmed ?? ""
        return signatureTitle.isEmpty ? "Untitled Story" : signatureTitle
    }

    private func storyPremise(signature: StorySignatureDocument?, story: SceneStory?) -> String {
        let signaturePremise = signature?.premise.trimmed ?? ""
        if !signaturePremise.isEmpty { return signaturePremise }
        let storyPremise = story?.premise.trimmed ?? ""
        return storyPremise.isEmpty ? "Premise pending." : storyPremise
    }

    private func storySceneCount(story: SceneStory?, signature: StorySignatureDocument?) -> Int {
        if let story { return story.scenes.count }
        return signature?.sceneFunctionSequence.count ?? 0
    }

    private func storyStateLabel(_ state: ProjectStoryEditorialState) -> String {
        switch state {
        case .suggestion: return "Story"
        case .kept: return "Story"
        case .dismissed: return "Removed"
        case .archived: return "Removed"
        }
    }

    private func productionStateLabel(_ state: ProjectStoryProductionState) -> String {
        switch state {
        case .notStarted: return "Not started"
        case .developing: return "Developing"
        case .inProduction: return "In production"
        case .complete: return "Complete"
        }
    }

    private func chipTone(for state: ProjectStoryEditorialState) -> StoryMiniChipTone {
        switch state {
        case .suggestion: return .kept
        case .kept: return .kept
        case .dismissed, .archived: return .muted
        }
    }

    private func chipTone(for state: ProjectStoryProductionState) -> StoryMiniChipTone {
        switch state {
        case .notStarted: return .muted
        case .developing: return .active
        case .inProduction, .complete: return .kept
        }
    }

    private func storyLibrarySignature(for entry: ProjectStoryLibraryEntry) -> StorySignatureDocument? {
        library.storySignatures.first { $0.storySignatureId == entry.storySignatureId }
    }

    private func storyLibrarySceneSummary(_ scene: SceneStoryScene) -> String {
        let compass = scene.emotionalArc.normalized()
        let turn = compass.isEmpty
            ? ""
            : "\(compassPointPlainLabel(compass.entry)) -> \(compassPointPlainLabel(compass.exit))"
        return [
            scene.sceneFunction,
            turn
        ]
        .map(\.trimmed)
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
    }

    private func compassPointPlainLabel(_ point: EmotionalCompassPoint) -> String {
        let label = point.normalized().labelSummary
        return label.isEmpty ? "Unspecified" : label
    }

    @ViewBuilder
    private func sceneStoryTextBlock(_ title: String, _ value: String, lineLimit: Int) -> some View {
        if !value.trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(CanonType.interface(10, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(CanonColor.brass)
                Text(value)
                    .font(CanonType.editorial(14))
                    .foregroundStyle(CanonColor.ink.opacity(0.72))
                    .lineLimit(lineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func expansionBinding(_ key: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                set.wrappedValue.contains(key)
            },
            set: { isExpanded in
                if isExpanded {
                    set.wrappedValue.insert(key)
                } else {
                    set.wrappedValue.remove(key)
                }
            }
        )
    }

    private func shortDateLabel(_ value: String) -> String {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return "now" }
        return String(trimmed.prefix(19)).replacingOccurrences(of: "T", with: " ")
    }

    @ViewBuilder
    private var globalAudioShelf: some View {
        if !library.globalStoryAudioTracks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                StorySectionHeader(
                    eyebrow: "A",
                    title: "Global / Sequence Audio",
                    subtitle: "Sequence-level audio is shown here instead of marking every beat ready."
                )
                HStack(alignment: .top, spacing: 8) {
                    ForEach(library.globalStoryAudioTracks.prefix(4)) { track in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(track.title.isEmpty ? "Audio Layer" : track.title)
                                .font(CanonType.editorial(15, weight: .semibold))
                                .foregroundStyle(CanonColor.ink)
                                .lineLimit(1)
                            Text(track.status.uppercased())
                                .font(CanonType.interface(9, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(track.status == "failed" ? CanonColor.rust : CanonColor.brass)
                            Text(track.mixNotes.isEmpty ? track.beatPrompt : track.mixNotes)
                                .font(CanonType.interface(11))
                                .foregroundStyle(CanonColor.ink.opacity(0.62))
                                .lineLimit(2)
                        }
                        .padding(10)
                        .frame(width: 210, alignment: .topLeading)
                        .background(CanonColor.paperInset.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
                    }
                }
            }
        }
    }

    private var videoChainBuilderSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            StorySectionHeader(
                eyebrow: "1",
                title: "Create a Video Chain",
                subtitle: videoChainSubtitle
            )

            Text("Choose reel type, provider, and model, then build the clip plan.")
                .font(CanonType.interface(11, weight: .medium))
                .foregroundStyle(CanonColor.ink.opacity(0.62))

            HStack(alignment: .top, spacing: 10) {
                VideoChainMenuSelect(
                    title: "Reel Type",
                    value: selectedVideoPreset.label,
                    detail: "\(selectedVideoPreset.outputProfile.aspectRatio.rawValue) · \(selectedVideoPreset.clipCount)x\(selectedVideoPreset.durationSeconds)s",
                    width: 220
                ) {
                    ForEach(VideoChainPreset.allCases) { preset in
                        Button("\(preset.label) · \(preset.outputProfile.aspectRatio.rawValue)") {
                            selectVideoPreset(preset)
                        }
                    }
                }

                VideoChainMenuSelect(
                    title: "Provider",
                    value: selectedVideoProvider.label,
                    detail: selectedVideoProviderDetail,
                    width: 190
                ) {
                    ForEach(VideoProviderSelection.visibleVideoChainProviders) { provider in
                        Button(provider.label) {
                            selectVideoProvider(provider)
                        }
                    }
                }

                VideoChainMenuSelect(
                    title: "Model",
                    value: selectedVideoModel.label,
                    detail: selectedVideoModel.providerModelId,
                    width: 220
                ) {
                    ForEach(VideoModelSelection.options(for: selectedVideoProvider)) { model in
                        Button(model.label) {
                            selectVideoModel(model)
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            if library.videoChain.chainId.isEmpty {
                if library.videoChainLoadIssues.isEmpty {
                    StoryEmptyPanel(
                        title: "No Video Chain yet",
                        subtitle: "Build a Video Plan from the active story or draft Beat Board.",
                        isLight: true
                    )
                } else {
                    videoChainLoadIssuePanel
                }
            } else {
                if videoProviderSetupRequired {
                    Text("Configure CivitAI, Kling, or LTX in App Settings, or choose Existing Clips before generating video.")
                        .font(CanonType.interface(11, weight: .semibold))
                        .foregroundStyle(CanonColor.rust)
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CanonColor.paper.opacity(0.62), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.rust.opacity(0.35)))
                }
                if videoPlanNeedsRebuild {
                    Text("Reel Type changed. Build Video Plan again to apply \(selectedVideoPreset.label).")
                        .font(CanonType.interface(11, weight: .semibold))
                        .foregroundStyle(CanonColor.rust)
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CanonColor.paper.opacity(0.62), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.rust.opacity(0.35)))
                }
                videoChainStatusPanel
                videoChainResultPanel
                videoChainHistorySection
                videoClipChain
            }
        }
        .padding(14)
        .background(CanonColor.paperInset.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
    }

    private var videoChainSubtitle: String {
        if library.videoChain.chainId.isEmpty || videoPlanNeedsRebuild {
            return "\(selectedVideoPreset.clipCount) clips · \(selectedVideoPreset.durationSeconds)s each · \(selectedVideoPreset.outputProfile.aspectRatio.rawValue)"
        }
        return "\(library.videoChain.clipSummary) · \(library.videoChain.outputProfile.label)"
    }

    private var videoChainLoadIssuePanel: some View {
        let issueCount = library.videoChainLoadIssues.count
        let firstIssue = library.videoChainLoadIssues.first
        let firstIssueFile = firstIssue.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "Video Chain JSON"
        let firstIssueMessage = firstIssue?.message ?? "Saved Video Chain files could not be decoded."

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Saved Video Chain could not load")
                    .font(CanonType.editorial(17, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Spacer(minLength: 0)
                StoryMiniChip("\(issueCount) issue\(issueCount == 1 ? "" : "s")")
            }

            Text("SCENES found saved chain files, but none could be restored into the current app model.")
                .font(CanonType.interface(12))
                .foregroundStyle(CanonColor.ink.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)

            Text("\(firstIssueFile): \(firstIssueMessage)")
                .font(CanonType.interface(11, weight: .medium))
                .foregroundStyle(CanonColor.rust)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                library.revealVideoChainsDirectory()
            } label: {
                Label("Reveal Video Chains", systemImage: "folder")
            }
            .buttonStyle(CanonUtilityButtonStyle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.paper.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.rust.opacity(0.32)))
    }

    private var videoChainStatusPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                StoryMiniChip(library.videoChain.status.rawValue.replacingOccurrences(of: "_", with: " "))
                if library.videoChain.missingTargetEndFrameCount > 0 {
                    StoryMiniChip("\(library.videoChain.missingTargetEndFrameCount) keyframe\(library.videoChain.missingTargetEndFrameCount == 1 ? "" : "s") needed")
                }
                Spacer(minLength: 0)
                Text(library.videoChainStatus)
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.62))
                    .lineLimit(1)
            }
            if !library.videoChain.preflightBlockers.isEmpty {
                Text(library.videoChain.preflightBlockers.prefix(3).joined(separator: " · "))
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.rust)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if library.videoChain.requiresTargetEndFrames && library.videoChain.missingTargetEndFrameCount > 0 {
                HStack(spacing: 8) {
                    Text("CivitAI WAN needs target end frames before generation.")
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.ink.opacity(0.62))
                    Spacer(minLength: 0)
                    Button {
                        library.autoPickMissingVideoChainKeyframes()
                    } label: {
                        Label("Auto-pick", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(CanonUtilityButtonStyle())
                }
            }
        }
        .padding(10)
        .background(CanonColor.paper.opacity(0.58), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
    }

    @ViewBuilder
    private var videoChainResultPanel: some View {
        let chain = library.videoChain
        let finalPath = chain.stitchedOutputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasFinal = !finalPath.isEmpty && FileManager.default.fileExists(atPath: finalPath)
        let readyClips = chain.segments.filter { segment in
            let path = segment.activeVideoPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return !path.isEmpty && FileManager.default.fileExists(atPath: path)
        }.count
        let latestJob = chain.jobs.sorted { $0.updatedAt > $1.updatedAt }.first

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(hasFinal ? "Final Reel" : "Partial Videos")
                    .font(CanonType.editorial(18, weight: .semibold))
                StoryMiniChip("\(readyClips)/\(chain.segments.count) clips ready")
                if let latestJob, latestJob.status == .failed {
                    StoryMiniChip("failed")
                }
                Spacer(minLength: 0)
                if hasFinal {
                    videoFileActions(path: finalPath, manifestPath: chain.manifestJSONPath)
                }
            }

            if hasFinal {
                VideoPreview(path: finalPath, autoplayRequestId: 0)
                    .frame(height: chain.outputProfile.aspectRatio == .portrait9x16 ? 260 : 210)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
                Text(URL(fileURLWithPath: finalPath).lastPathComponent)
                    .font(CanonType.archive(10, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.58))
                    .lineLimit(1)
                    .textSelection(.enabled)
            } else if readyClips > 0 {
                Text("No stitched reel yet. The ready partial clips below remain usable and versioned.")
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.66))
            } else {
                Text("Generated partial clips will appear here as each segment completes.")
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.62))
            }

            if let latestJob, latestJob.status == .failed {
                Text(latestJob.message.isEmpty ? "Video Chain failed." : latestJob.message)
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.rust)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let latestJob, library.isGeneratingVideoChain {
                Text("\(latestJob.message) · \(latestJob.progressCompleted)/\(max(latestJob.progressTotal, 1))")
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.brass)
                    .lineLimit(1)
            }

            if !videoResultCopyStatus.isEmpty {
                Text(videoResultCopyStatus)
                    .font(CanonType.interface(10, weight: .semibold))
                    .foregroundStyle(CanonColor.olive)
            }

            if readyClips > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(chain.segments.sorted { $0.order < $1.order }) { segment in
                        let clipPath = segment.activeVideoPath.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clipPath.isEmpty, FileManager.default.fileExists(atPath: clipPath) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(String(format: "%02d", segment.order))
                                    .font(CanonType.archive(10, weight: .semibold))
                                    .foregroundStyle(CanonColor.brass)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(segment.title)
                                        .font(CanonType.interface(11, weight: .semibold))
                                        .foregroundStyle(CanonColor.ink)
                                        .lineLimit(1)
                                    Text("V\(segment.activeVersion?.versionNumber ?? 1) · \(URL(fileURLWithPath: clipPath).lastPathComponent)")
                                        .font(CanonType.archive(9, weight: .medium))
                                        .foregroundStyle(CanonColor.ink.opacity(0.54))
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                videoFileActions(path: clipPath)
                            }
                            .padding(7)
                            .background(CanonColor.paperInset.opacity(0.48), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(CanonColor.paper.opacity(0.62), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(hasFinal ? CanonColor.olive.opacity(0.38) : CanonColor.hairlinePaper))
    }

    @ViewBuilder
    private var videoChainHistorySection: some View {
        if library.videoChains.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Recent Chains")
                        .font(CanonType.interface(10, weight: .semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(CanonColor.brass)
                    Text("\(library.videoChains.count)")
                        .font(CanonType.archive(10, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.58))
                    Spacer(minLength: 0)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(library.videoChains.prefix(8)) { chain in
                            VideoChainHistoryCard(
                                chain: chain,
                                isActive: chain.chainId == library.videoChain.chainId
                            ) {
                                library.selectVideoChain(chainId: chain.chainId)
                                syncVideoControls()
                                reconcileSelectedVideoSegment()
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            .padding(10)
            .background(CanonColor.paper.opacity(0.50), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
        }
    }

    private func videoFileActions(path: String, manifestPath: String = "") -> some View {
        HStack(spacing: 6) {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } label: {
                Image(systemName: "play.rectangle")
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Open video")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Reveal in Finder")

            Button {
                copyToPasteboard(path)
                videoResultCopyStatus = "Copied path"
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Copy path")

            if !manifestPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               FileManager.default.fileExists(atPath: manifestPath) {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: manifestPath)])
                } label: {
                    Image(systemName: "doc.text")
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Reveal manifest")
            }
        }
    }

    private var videoClipChain: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(library.videoChain.segments.sorted { $0.order < $1.order }) { segment in
                    VideoChainClipCard(
                        segment: segment,
                        isSelected: selectedVideoSegment?.segmentId == segment.segmentId,
                        requiresTargetEndFrame: library.videoChain.requiresTargetEndFrames
                    ) {
                        selectedVideoSegmentId = segment.segmentId
                    }
                    if segment.segmentId != library.videoChain.segments.sorted(by: { $0.order < $1.order }).last?.segmentId {
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CanonColor.brass)
                            Text("Seam")
                                .font(CanonType.archive(9, weight: .medium))
                                .foregroundStyle(CanonColor.ink.opacity(0.54))
                        }
                        .frame(width: 46, height: 118)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var advancedLayersSection: some View {
        DisclosureGroup(isExpanded: $isAdvancedLayersExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                if !library.videoChain.chainId.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            Task { await library.exportVideoChainManifest() }
                        } label: {
                            Label("Export Video Chain Manifest", systemImage: "doc.badge.arrow.up")
                        }
                        .buttonStyle(CanonUtilityButtonStyle())
                        Spacer(minLength: 0)
                    }
                }
                if !library.globalStoryAudioTracks.isEmpty {
                    globalAudioShelf
                }
                HStack(alignment: .top, spacing: 14) {
                    sceneMatrixSection
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    SceneLayerInspectorView(
                        library: library,
                        beat: selectedSceneBeat,
                        asset: selectedSceneAsset,
                        onOpenSourceMedia: {
                            selectedSceneLayer = .reference
                        }
                    )
                    .frame(width: 340, alignment: .topLeading)
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3")
                    .foregroundStyle(CanonColor.brass)
                Text("Advanced Layers")
                    .font(CanonType.editorial(18, weight: .semibold))
                Text("Scene Matrix, audio layers, captions, and reference prompts")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.ink.opacity(0.56))
            }
        }
        .padding(14)
        .background(CanonColor.paperInset.opacity(0.50), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
    }

    private var sceneMatrixSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            StorySectionHeader(
                eyebrow: "1",
                title: "Scene Matrix",
                subtitle: "Rows are beats. Columns are production layers."
            )
            if activeSceneBeats.isEmpty {
                StoryEmptyPanel(
                    title: "No Beat Board yet",
                    subtitle: "Scenes are generated from beats.",
                    isLight: true
                )
            } else {
                VStack(spacing: 7) {
                    sceneMatrixHeader
                    ForEach(activeSceneBeats.sorted { $0.order < $1.order }) { beat in
                        sceneMatrixRow(beat)
                    }
                }
                sceneStatusLegend
            }
        }
    }

    private var sceneMatrixHeader: some View {
        HStack(spacing: 7) {
            Text("Beat")
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(SceneLayerType.productionMatrixOrder) { layer in
                Text(layer.label)
                    .frame(width: layer == .textOverlay ? 78 : 66)
            }
            Text("Status")
                .frame(width: 78)
        }
        .font(CanonType.interface(10, weight: .semibold))
        .tracking(0.8)
        .textCase(.uppercase)
        .foregroundStyle(CanonColor.brass)
    }

    private func sceneMatrixRow(_ beat: StoryBeatBoardBeat) -> some View {
        let rowStatus = aggregateStatus(for: beat)
        return HStack(spacing: 7) {
            Button {
                selectedSceneBeatId = beat.beatId
                if selectedSceneLayer == .audio && library.sceneAssetForMatrix(beat: beat, layerType: .audio).status == .global {
                    selectedSceneLayer = .still
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: "%02d %@", beat.order, beat.title))
                        .font(CanonType.editorial(15, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(1)
                    Text(beat.storyFunction.isEmpty ? beat.visualMoment : beat.storyFunction)
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.ink.opacity(0.58))
                        .lineLimit(1)
                    Text(beat.aestheticPresentationBinding.prefix(2).joined(separator: " · "))
                        .font(CanonType.archive(9, weight: .medium))
                        .foregroundStyle(CanonColor.brass)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            ForEach(SceneLayerType.productionMatrixOrder) { layer in
                let asset = library.sceneAssetForMatrix(beat: beat, layerType: layer)
                sceneLayerCell(asset: asset, layer: layer, beat: beat)
            }

            Text(rowStatus.rawValue.capitalized)
                .font(CanonType.interface(10, weight: .semibold))
                .foregroundStyle(sceneStatusColor(rowStatus))
                .frame(width: 78)
        }
        .padding(10)
        .background(CanonColor.paperInset.opacity(beat.beatId == selectedSceneBeatId ? 0.82 : 0.56), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(beat.beatId == selectedSceneBeatId ? CanonColor.brass.opacity(0.86) : CanonColor.hairlinePaper)
        )
    }

    private func sceneLayerCell(asset: SceneAssetDocument, layer: SceneLayerType, beat: StoryBeatBoardBeat) -> some View {
        let isSelected = selectedSceneBeatId == beat.beatId && selectedSceneLayer == layer
        return Button {
            selectedSceneBeatId = beat.beatId
            selectedSceneLayer = layer
        } label: {
            VStack(spacing: 2) {
                Text(sceneLayerStatusLabel(asset))
                    .font(CanonType.interface(9, weight: .semibold))
                    .lineLimit(1)
                if asset.isManuallyEdited {
                    Image(systemName: "pencil")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .foregroundStyle(sceneStatusColor(asset.status))
            .frame(width: layer == .textOverlay ? 78 : 66, height: 36)
            .background(sceneStatusColor(asset.status).opacity(isSelected ? 0.24 : 0.12), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? CanonColor.brass.opacity(0.88) : sceneStatusColor(asset.status).opacity(0.34))
            )
        }
        .buttonStyle(.plain)
        .help("\(layer.label): \(asset.status.rawValue)")
    }

    private var sceneStatusLegend: some View {
        HStack(spacing: 6) {
            ForEach([SceneAssetStatus.missing, .draft, .edited, .ready, .stale, .global], id: \.self) { status in
                HStack(spacing: 4) {
                    Circle()
                        .fill(sceneStatusColor(status))
                        .frame(width: 6, height: 6)
                    Text(status.rawValue)
                        .font(CanonType.archive(9, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.60))
                }
            }
        }
    }

    private func sceneLayerStatusLabel(_ asset: SceneAssetDocument) -> String {
        asset.status.rawValue.capitalized
    }

    private func sceneStatusColor(_ status: SceneAssetStatus) -> Color {
        switch status {
        case .missing, .unavailable:
            return CanonColor.muted
        case .draft:
            return CanonColor.brass
        case .edited, .ready, .generated, .exported:
            return CanonColor.olive
        case .failed, .stale:
            return CanonColor.rust
        case .global:
            return CanonColor.focusBlue
        }
    }

    private func aggregateStatus(for beat: StoryBeatBoardBeat) -> SceneAssetStatus {
        let statuses = SceneLayerType.productionMatrixOrder
            .map { library.sceneAssetForMatrix(beat: beat, layerType: $0).status }
        if statuses.contains(.failed) { return .failed }
        if statuses.contains(.stale) { return .stale }
        if statuses.contains(.edited) || statuses.contains(.ready) || statuses.contains(.generated) { return .ready }
        if statuses.allSatisfy({ $0 == .missing || $0 == .unavailable }) { return .missing }
        return .draft
    }

    @ViewBuilder
    private var layersTray: some View {
        if isLayersPanelExpanded {
            layersExpandedPanel
        } else {
            layersCollapsedRail
        }
    }

    private var layersExpandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            layersHeader
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    audioDraftButton
                    audioStatusStack
                    StoryAudioDirectionPanel(library: library)

                    if shouldShowElevenLabsSettingsPanel {
                        elevenLabsSettingsPanel
                    }

                    if isStoryAudioWorking {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(library.storyStatus)
                                .font(CanonType.interface(12, weight: .medium))
                                .foregroundStyle(CanonColor.muted)
                        }
                    }

                    activeAudioSurface

                    if library.storyAudioTracks.hasTracks {
                        StoryAudioGenerationBrowser(library: library)
                    }
                }
                .padding(14)
            }
        }
        .background(CanonColor.sidebar)
    }

    private var layersHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Layers")
                    .font(CanonType.editorial(22, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text(audioTracksSubtitle)
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isLayersPanelExpanded = false
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Collapse Layers")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var layersCollapsedRail: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isLayersPanelExpanded = true
                }
            } label: {
                Image(systemName: "music.note.list")
                    .font(.title3.weight(.semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Expand Layers")

            Text("\(library.storyAudioTracks.tracks.count)")
                .font(CanonType.archive(12, weight: .semibold))
                .foregroundStyle(CanonColor.bone)
                .frame(width: 34, height: 24)
                .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlineDark))

            Circle()
                .fill(audioTrackStatusColor)
                .frame(width: 8, height: 8)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanonColor.sidebar)
    }

    private var audioDraftButton: some View {
        Button {
            Task {
                await library.draftStoryAudioTrackText()
            }
        } label: {
            Label(
                library.isDraftingStoryAudioTrack ? "Drafting Layer" : "Create Audio Layer",
                systemImage: "text.badge.star"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(CanonPrimaryButtonStyle(isFullWidth: true))
        .disabled(
            library.isDraftingStoryAudioTrack
                || library.isGeneratingStoryAudioTrack
                || library.isRemixingStoryAudioTrack
                || activeSceneBeats.isEmpty
                || library.readyLenses.isEmpty
        )
    }

    private var audioStatusStack: some View {
        VStack(alignment: .leading, spacing: 7) {
            audioStatusRow(systemImage: "rectangle.grid.2x2", text: contextBadge, color: CanonColor.muted)
            audioStatusRow(systemImage: "waveform", text: audioTrackStatusLabel, color: audioTrackStatusColor)
            audioStatusRow(systemImage: "key.fill", text: hasElevenLabsAPIKey ? "ElevenLabs API configured" : "ElevenLabs API missing", color: hasElevenLabsAPIKey ? CanonColor.olive : CanonColor.rust)
            audioStatusRow(systemImage: "person.wave.2", text: activeStoryAudioVoiceReady ? "\(activeStoryAudioVoiceOption.name) voice ready" : "voice missing", color: activeStoryAudioVoiceReady ? CanonColor.olive : CanonColor.rust)
        }
        .padding(10)
        .background(CanonColor.mediaCard.opacity(0.66), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark))
    }

    private func audioStatusRow(systemImage: String, text: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(CanonType.interface(11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(CanonType.archive(11, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    @ViewBuilder
    private var activeAudioSurface: some View {
        if library.hasEditableStoryAudioDraft {
            StoryAudioDraftEditor(
                library: library,
                canGenerateAudio: canGenerateStoryAudio,
                generationBlocker: storyAudioGenerationBlocker
            )
        } else if library.hasCurrentStoryAudioTrack {
            StoryAudioTrackCard(
                track: library.storyAudioTrack,
                isRemixing: library.isRemixingStoryAudioTrack,
                onRepairMix: {
                    Task {
                        await library.repairStoryAudioTrackMix(trackId: library.storyAudioTrack.trackId)
                    }
                },
                onBeatEnabledCommit: { isEnabled in
                    Task {
                        await library.setStoryAudioTrackBeatEnabled(
                            trackId: library.storyAudioTrack.trackId,
                            isEnabled: isEnabled
                        )
                    }
                },
                onSpeedCommit: { speed in
                    Task {
                        await library.remixStoryAudioTrackSpeed(
                            trackId: library.storyAudioTrack.trackId,
                            voiceSpeed: speed
                        )
                    }
                }
            )
        } else {
            StoryEmptyPanel(
                title: "No audio layer yet",
                subtitle: "Create an audio layer from the accepted story or active draft board."
            )
        }
    }

    private var activeSceneBeats: [StoryBeatBoardBeat] {
        library.activeSceneSourceBeats.filter { !$0.isDeleted }
    }

    private var contextTitle: String {
        if library.sceneWorkspace.sourceArtifactType == .projectStory && library.projectStory.hasAcceptedStory {
            return "Using Project Story: \(library.projectStory.title.isEmpty ? "Accepted Story" : library.projectStory.title)"
        }
        if library.storyBeatBoard.hasBeats {
            return "Using Draft Beat Board: \(library.storyBeatBoard.title.isEmpty ? "Draft Board" : library.storyBeatBoard.title)"
        }
        return "No Scene Source"
    }

    private var contextSubtitle: String {
        if library.sceneWorkspace.sourceArtifactType == .projectStory && library.projectStory.hasAcceptedStory {
            return library.projectStory.logline.isEmpty ? "Using the accepted Project Story snapshot." : library.projectStory.logline
        }
        if library.storyBeatBoard.hasBeats {
            return "Not yet set as Project Story. Scene layers will use this draft board until a Project Story is accepted."
        }
        return "Scenes need an accepted Project Story or an active draft Beat Board."
    }

    private var contextBadge: String {
        if library.sceneWorkspace.sourceArtifactType == .projectStory && library.projectStory.hasAcceptedStory {
            return "Accepted Story"
        }
        if library.storyBeatBoard.hasBeats {
            return "Draft Context"
        }
        return "Missing Beats"
    }

    private func hasAudio(for beat: StoryBeatBoardBeat) -> Bool {
        let ids = library.storyAudioTrack.sourceBeatIds ?? []
        return ids.contains(beat.beatId)
            || library.storyAudioTrack.targetBeatId == beat.beatId
            || (ids.isEmpty && library.hasCurrentStoryAudioTrack)
    }

    private func audioLabel(for beat: StoryBeatBoardBeat) -> String {
        hasAudio(for: beat) ? "Ready" : "Open"
    }

    private var selectedSceneBeat: StoryBeatBoardBeat? {
        activeSceneBeats.first { $0.beatId == selectedSceneBeatId } ?? activeSceneBeats.first
    }

    private var selectedSceneAsset: SceneAssetDocument? {
        guard let beat = selectedSceneBeat else { return nil }
        return library.sceneAssetForMatrix(beat: beat, layerType: selectedSceneLayer)
    }

    private var selectedVideoSegment: VideoSegmentDocument? {
        library.videoChain.segments.first { $0.segmentId == selectedVideoSegmentId }
            ?? library.videoChain.segments.sorted { $0.order < $1.order }.first
    }

    private var selectedVideoProviderDetail: String {
        switch selectedVideoProvider {
        case .bestAvailable:
            return "Auto provider"
        case .ltxDirect:
            return "Native extend"
        case .civitaiWan:
            return "Keyframed chain"
        case .klingImageToVideo:
            return "First-frame chain"
        case .falImageToVideo:
            return "FAL image-to-video"
        case .falAudioToVideo:
            return "FAL audio-to-video (Shots)"
        case .localExistingClip:
            return "Attach clips"
        case .localPromptExport:
            return "Internal only"
        }
    }

    private var videoPlanNeedsRebuild: Bool {
        !library.videoChain.chainId.isEmpty && selectedVideoPreset != library.videoChain.preset
    }

    private var videoProviderSetupRequired: Bool {
        !library.videoChain.chainId.isEmpty
            && (
                library.videoChain.selectedProviderId == .bestAvailable
                    || library.videoChain.selectedProviderId == .localPromptExport
                    || library.videoChain.preflightBlockers.contains { blocker in
                        blocker.contains("_API_KEY_missing")
                            || blocker.contains("duration_not_supported")
                            || blocker.contains("aspect_not_supported")
                    }
            )
    }

    private var videoGenerateDisabled: Bool {
        activeSceneBeats.isEmpty
            || library.videoChain.chainId.isEmpty
            || library.isGeneratingVideoChain
            || videoPlanNeedsRebuild
            || videoProviderSetupRequired
    }

    private func selectVideoPreset(_ preset: VideoChainPreset) {
        selectedVideoPreset = preset
    }

    private func selectVideoProvider(_ provider: VideoProviderSelection) {
        selectedVideoProvider = provider == .localPromptExport ? .bestAvailable : provider
        selectedVideoModel = VideoModelSelection.defaultModel(for: selectedVideoProvider)
        if !library.videoChain.chainId.isEmpty {
            library.setVideoChainProvider(selectedVideoProvider)
        }
    }

    private func selectVideoModel(_ model: VideoModelSelection) {
        selectedVideoModel = model
        if !library.videoChain.chainId.isEmpty {
            library.setVideoChainModel(model)
        }
    }

    private func syncVideoControls() {
        if !library.videoChain.chainId.isEmpty {
            selectedVideoPreset = library.videoChain.preset
            selectedVideoProvider = library.videoChain.providerSelection == .localPromptExport ? .bestAvailable : library.videoChain.providerSelection
            let model = library.videoChain.modelSelection ?? VideoModelSelection.defaultModel(for: selectedVideoProvider)
            selectedVideoModel = VideoModelSelection.options(for: selectedVideoProvider).contains(model)
                ? model
                : VideoModelSelection.defaultModel(for: selectedVideoProvider)
        } else if !VideoModelSelection.options(for: selectedVideoProvider).contains(selectedVideoModel) {
            selectedVideoModel = VideoModelSelection.defaultModel(for: selectedVideoProvider)
        }
    }

    private func reconcileSelectedVideoSegment() {
        let ids = Set(library.videoChain.segments.map(\.segmentId))
        if !ids.contains(selectedVideoSegmentId) {
            selectedVideoSegmentId = library.videoChain.segments.sorted { $0.order < $1.order }.first?.segmentId ?? ""
        }
    }

    private func reconcileSelectedSceneLayer() {
        let beats = activeSceneBeats.sorted { $0.order < $1.order }
        if selectedSceneBeatId.isEmpty || !beats.contains(where: { $0.beatId == selectedSceneBeatId }) {
            selectedSceneBeatId = beats.first?.beatId ?? ""
        }
    }

    private var hasElevenLabsAPIKey: Bool {
        _ = elevenSettingsRevision
        return ElevenLabsSettingsStore.hasResolvedAPIKey()
    }

    private var activeStoryAudioVoiceOption: StoryAudioVoiceOption {
        _ = elevenSettingsRevision
        return StoryAudioVoiceCatalog.option(
            for: library.storyAudioTrack.voicePresetId,
            customVoiceId: ElevenLabsSettingsStore.resolvedCustomVoiceId()
        )
    }

    private var activeStoryAudioVoiceReady: Bool {
        let voiceId = (activeStoryAudioVoiceOption.voiceId ?? library.storyAudioTrack.voiceId)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !voiceId.isEmpty
    }

    private var canGenerateStoryAudio: Bool {
        hasElevenLabsAPIKey && activeStoryAudioVoiceReady
    }

    private var shouldShowElevenLabsSettingsPanel: Bool {
        !hasElevenLabsAPIKey
            || ((library.storyAudioTrack.voicePresetId ?? StoryAudioVoiceCatalog.customPresetId) == StoryAudioVoiceCatalog.customPresetId
                && !activeStoryAudioVoiceReady)
    }

    private var storyAudioGenerationBlocker: String {
        if !hasElevenLabsAPIKey {
            return "Add an ElevenLabs API key before generating audio."
        }
        if !activeStoryAudioVoiceReady {
            return "Add a Custom Voice ID or choose Archer/Lucy before generating audio."
        }
        return ""
    }

    private var canSaveElevenLabsSettings: Bool {
        !elevenAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || ElevenLabsSettingsStore.resolvedAPIKey() != nil
    }

    private var elevenLabsSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Label("ElevenLabs Settings", systemImage: "key.fill")
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Spacer()
                Text(ElevenLabsSettingsStore.hasSavedSettings() ? "Saved Locally" : "Missing")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(ElevenLabsSettingsStore.hasSavedSettings() ? CanonColor.olive : CanonColor.rust)
            }
            SecureField(ElevenLabsSettingsStore.resolvedAPIKey() == nil ? "xi-api-key" : "Saved or environment key", text: $elevenAPIKey)
                .textFieldStyle(.roundedBorder)
            TextField("Custom Voice ID", text: $elevenCustomVoiceId)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Button {
                    saveElevenLabsSettings()
                } label: {
                    Label("Save", systemImage: "checkmark.circle")
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(!canSaveElevenLabsSettings)
                Spacer()
                if !elevenSettingsMessage.isEmpty {
                    Text(elevenSettingsMessage)
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.muted)
                }
            }
        }
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.rust.opacity(0.50)))
    }

    private var audioTracksSubtitle: String {
        let count = library.storyAudioTracks.tracks.count
        let generationText = "\(count) generation\(count == 1 ? "" : "s")"
        return "\(generationText) · \(audioTrackStatusLabel)"
    }

    private var isStoryAudioWorking: Bool {
        library.isDraftingStoryAudioTrack
            || library.isGeneratingStoryAudioTrack
            || library.isRemixingStoryAudioTrack
    }

    private var audioTrackStatusLabel: String {
        if library.hasEditableStoryAudioDraft {
            return "draft editable"
        }
        if library.hasCurrentStoryAudioTrack {
            return library.storyAudioTrack.scope == "global_project_audio" ? "project-level audio" : "beat-aware audio"
        }
        return "draft first"
    }

    private var audioTrackStatusColor: Color {
        if library.storyAudioFreshness == .stale {
            return CanonColor.rust
        }
        if library.hasEditableStoryAudioDraft {
            return CanonColor.brass
        }
        if library.hasCurrentStoryAudioTrack {
            return CanonColor.olive
        }
        return CanonColor.muted
    }

    private func refreshElevenLabsFields() {
        elevenAPIKey = ""
        elevenCustomVoiceId = ElevenLabsSettingsStore.resolvedCustomVoiceId() ?? ""
        elevenSettingsRevision += 1
    }

    private func saveElevenLabsSettings() {
        do {
            try ElevenLabsSettingsStore.save(apiKey: elevenAPIKey, customVoiceId: elevenCustomVoiceId)
            elevenSettingsMessage = "Saved local ElevenLabs settings."
            refreshElevenLabsFields()
            if library.storyAudioTrack.isEditableDraft,
               (library.storyAudioTrack.voicePresetId ?? StoryAudioVoiceCatalog.customPresetId) == StoryAudioVoiceCatalog.customPresetId {
                library.updateStoryAudioVoiceSettings(
                    trackId: library.storyAudioTrack.trackId,
                    presetId: StoryAudioVoiceCatalog.customPresetId,
                    voiceSpeed: library.storyAudioTrack.effectiveVoiceSpeed
                )
            }
        } catch {
            elevenSettingsMessage = error.localizedDescription
        }
    }
}

/// Shared with the Voice & Audio sidebar — internal, not private.
struct SoundRailPlayerTransport: View {
    @ObservedObject var player: SoundRailPlayerController
    @ObservedObject var waveformLoader: SoundWaveformLoader
    let asset: SoundSceneAsset

    private let waveformSampleCount = 132

    private var durationSeconds: Double {
        max(asset.durationSeconds, 0)
    }

    private var currentSeconds: Double {
        min(max(player.currentSeconds, 0), max(durationSeconds, player.currentSeconds))
    }

    private var canSeek: Bool {
        player.isLoaded(soundId: asset.soundId, path: asset.path) && durationSeconds > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SoundRailWaveformView(
                state: waveformLoader.state(for: asset, sampleCount: waveformSampleCount),
                progress: durationSeconds > 0 ? currentSeconds / durationSeconds : 0,
                isEnabled: canSeek
            ) { ratio in
                player.seek(to: ratio * max(durationSeconds, 0))
            }

            Slider(
                value: Binding(
                    get: { min(player.currentSeconds, max(durationSeconds, 0.1)) },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(durationSeconds, 0.1)
            )
            .disabled(!canSeek)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(soundSceneTimecode(currentSeconds))
                Spacer(minLength: 0)
                Text(soundSceneTimecode(durationSeconds))
            }
            .font(CanonType.archive(9, weight: .medium))
            .foregroundStyle(CanonColor.ink.opacity(0.56))

            if !player.statusText.isEmpty {
                Text(player.statusText)
                    .font(CanonType.interface(10, weight: .medium))
                    .foregroundStyle(player.statusTone)
                    .lineLimit(2)
            }
        }
        .padding(.top, 4)
        .onAppear {
            waveformLoader.loadIfNeeded(for: asset, sampleCount: waveformSampleCount)
        }
        .onChange(of: asset.soundId) { _, _ in
            waveformLoader.loadIfNeeded(for: asset, sampleCount: waveformSampleCount)
        }
        .onChange(of: asset.modifiedAt) { _, _ in
            waveformLoader.loadIfNeeded(for: asset, sampleCount: waveformSampleCount)
        }
    }
}

/// Shared with the Voice & Audio sidebar. One instance plays one sound at a
/// time, which is what keeps browsing from turning into a chorus.
final class SoundRailPlayerController: ObservableObject, @unchecked Sendable {
    @Published var currentSeconds: Double = 0
    @Published var isPlaying = false
    @Published var statusText = ""

    private var loadedSoundId = ""
    private var loadedPath = ""
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    deinit {
        removeObservers()
    }

    var statusTone: Color {
        statusText.localizedCaseInsensitiveContains("missing") ? CanonColor.rust : CanonColor.ink.opacity(0.56)
    }

    func load(soundId: String, path: String) {
        guard soundId != loadedSoundId || path != loadedPath else { return }
        pause()
        removeObservers()
        loadedSoundId = soundId
        loadedPath = path
        currentSeconds = 0

        guard !path.trimmed.isEmpty, FileManager.default.fileExists(atPath: path) else {
            player = nil
            statusText = "Audio file missing."
            return
        }

        let newPlayer = AVPlayer(url: URL(fileURLWithPath: path))
        player = newPlayer
        statusText = ""
        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.10, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.currentSeconds = max(time.seconds, 0)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: newPlayer.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
            self?.seek(to: 0)
        }
    }

    func unload() {
        pause()
        removeObservers()
        loadedSoundId = ""
        loadedPath = ""
        player = nil
        currentSeconds = 0
        statusText = ""
    }

    func canPlay(soundId: String, path: String) -> Bool {
        if isLoaded(soundId: soundId, path: path) {
            return player != nil || !path.trimmed.isEmpty
        }
        return !path.trimmed.isEmpty
    }

    func isLoaded(soundId: String, path: String) -> Bool {
        loadedSoundId == soundId && loadedPath == path
    }

    func isPlayingAsset(soundId: String, path: String) -> Bool {
        isLoaded(soundId: soundId, path: path) && isPlaying
    }

    func toggle(soundId: String, path: String) {
        if isPlayingAsset(soundId: soundId, path: path) {
            pause()
            return
        }
        if !isLoaded(soundId: soundId, path: path) || player == nil {
            load(soundId: soundId, path: path)
        }
        guard let player else { return }
        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        let clamped = max(seconds, 0)
        currentSeconds = clamped
        player?.seek(
            to: CMTime(seconds: clamped, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func removeObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }
}

private struct SceneLayerInspectorView: View {
    @ObservedObject var library: LibraryEngine
    let beat: StoryBeatBoardBeat?
    let asset: SceneAssetDocument?
    let onOpenSourceMedia: () -> Void
    @State private var draft = SceneLayerInspectorDraft()
    @State private var loadedAssetId = ""
    @State private var copyStatus = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Scene Inspector")
                    .font(CanonType.editorial(22, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Spacer(minLength: 0)
                if let asset {
                    StoryMiniChip(asset.layerType.label)
                }
            }

            if let beat, let asset {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(format: "Beat %02d - %@", beat.order, beat.title))
                                .font(CanonType.editorial(17, weight: .semibold))
                                .foregroundStyle(CanonColor.ink)
                                .lineLimit(2)
                            Text(beat.visualMoment)
                                .font(CanonType.interface(12))
                                .foregroundStyle(CanonColor.ink.opacity(0.64))
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                StoryMiniChip(asset.status.rawValue)
                                StoryMiniChip(asset.sourceArtifactType.rawValue.replacingOccurrences(of: "_", with: " "))
                                if asset.isManuallyEdited {
                                    StoryMiniChip("manual edit")
                                }
                            }
                        }

                        if asset.layerType == .still || asset.layerType == .video {
                            Text("\(asset.layerType.label) generation coming later. Copy, edit, or export this prompt now.")
                                .font(CanonType.interface(11, weight: .medium))
                                .foregroundStyle(CanonColor.ink.opacity(0.60))
                                .padding(9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(CanonColor.paper.opacity(0.62), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
                        }

                        sceneTextArea("Generation brief / prompt", text: $draft.prompt, minHeight: 150)
                        sceneTextArea("Negative prompt / avoid", text: $draft.negativePrompt, minHeight: 62)
                        sceneTextArea("Text overlay", text: $draft.textOverlay, minHeight: 54)
                        sceneTextArea("Caption/social copy", text: $draft.captionDraft, minHeight: 72)

                        VStack(alignment: .leading, spacing: 7) {
                            StoryDraftFieldLabel("Source Media")
                            if asset.mediaAnchors.isEmpty {
                                Text("No anchors attached to this beat yet.")
                                    .font(CanonType.interface(11))
                                    .foregroundStyle(CanonColor.ink.opacity(0.56))
                            } else {
                                ForEach(asset.mediaAnchors) { anchor in
                                    SceneAnchorRow(anchor: anchor, item: library.mediaItems(for: [anchor.mediaId]).first)
                                }
                            }
                            Button {
                                onOpenSourceMedia()
                            } label: {
                                Label("Open Reference Layer", systemImage: "photo.on.rectangle")
                            }
                            .buttonStyle(CanonUtilityButtonStyle())
                        }
                    }
                    .padding(.trailing, 4)
                }

                HStack(spacing: 8) {
                    Button {
                        copyToPasteboard(draft.prompt)
                        copyStatus = "Copied"
                    } label: {
                        Label("Copy Prompt", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(CanonUtilityButtonStyle())
                    .disabled(draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer(minLength: 0)

                    if !copyStatus.isEmpty {
                        Text(copyStatus)
                            .font(CanonType.interface(10, weight: .semibold))
                            .foregroundStyle(CanonColor.olive)
                    }

                    Button {
                        library.updateSceneAsset(
                            assetId: asset.assetId,
                            prompt: draft.prompt,
                            negativePrompt: draft.negativePrompt,
                            textOverlay: draft.textOverlay,
                            captionDraft: draft.captionDraft
                        )
                    } label: {
                        Label("Save Layer", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(CanonPrimaryButtonStyle())
                }
            } else {
                StoryEmptyPanel(
                    title: "No scene layer selected",
                    subtitle: "Select a beat row and layer cell.",
                    isLight: true
                )
            }
        }
        .padding(14)
        .background(CanonColor.paperInset.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
        .onAppear {
            if let asset {
                sync(from: asset)
            }
        }
        .onChange(of: asset?.assetId ?? "") { _, _ in
            if let asset {
                sync(from: asset)
            } else {
                draft = SceneLayerInspectorDraft()
                loadedAssetId = ""
            }
        }
        .onChange(of: asset) { _, value in
            guard let value, value.assetId == loadedAssetId else { return }
            sync(from: value)
        }
    }

    private func sync(from asset: SceneAssetDocument) {
        loadedAssetId = asset.assetId
        copyStatus = ""
        draft = SceneLayerInspectorDraft(asset: asset)
    }

    private func sceneTextArea(_ title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            StoryDraftFieldLabel(title)
            TextEditor(text: text)
                .font(CanonType.editorial(13))
                .foregroundStyle(CanonColor.ink)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .background(CanonColor.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
        }
    }
}

private struct VideoChainMenuSelect<Content: View>: View {
    let title: String
    let value: String
    let detail: String
    let width: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(CanonType.archive(9, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.54))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(value)
                        .font(CanonType.interface(12, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CanonColor.brass)
                }
                Text(detail)
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.58))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
            .background(CanonColor.paper.opacity(0.86), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }
}

private struct VideoChainHistoryCard: View {
    let chain: VideoChainDocument
    let isActive: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(chain.title.isEmpty ? "Video Chain" : chain.title)
                        .font(CanonType.editorial(14, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CanonColor.olive)
                    }
                }
                HStack(spacing: 5) {
                    StoryMiniChip(chain.status.rawValue.replacingOccurrences(of: "_", with: " "))
                    StoryMiniChip("\(readyClipCount)/\(chain.segments.count)")
                    if hasFinal {
                        StoryMiniChip("reel")
                    }
                }
                Text("\(chain.selectedProviderId.label) · \((chain.selectedModelId ?? chain.modelSelection ?? .auto).label)")
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.58))
                    .lineLimit(1)
                Text(latestLine)
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(latestJobFailed ? CanonColor.rust : CanonColor.ink.opacity(0.50))
                    .lineLimit(2)
            }
            .padding(9)
            .frame(width: 218, height: 112, alignment: .topLeading)
            .background(CanonColor.paper.opacity(isActive ? 0.84 : 0.56), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isActive ? CanonColor.brass.opacity(0.70) : CanonColor.hairlinePaper))
        }
        .buttonStyle(.plain)
    }

    private var readyClipCount: Int {
        chain.segments.filter { segment in
            let path = segment.activeVideoPath.trimmingCharacters(in: .whitespacesAndNewlines)
            return !path.isEmpty && FileManager.default.fileExists(atPath: path)
        }.count
    }

    private var hasFinal: Bool {
        let path = chain.stitchedOutputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return !path.isEmpty && FileManager.default.fileExists(atPath: path)
    }

    private var latestJob: VideoGenerationJobDocument? {
        chain.jobs.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    private var latestJobFailed: Bool {
        latestJob?.status == .failed
    }

    private var latestLine: String {
        if let latestJob, latestJob.status == .failed, !latestJob.message.isEmpty {
            return latestJob.message
        }
        return chain.updatedAt
    }
}

private struct VideoChainClipCard: View {
    let segment: VideoSegmentDocument
    let isSelected: Bool
    let requiresTargetEndFrame: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(String(format: "%02d", segment.order))
                        .font(CanonType.archive(11, weight: .semibold))
                        .foregroundStyle(CanonColor.brass)
                    Text(segment.title)
                        .font(CanonType.editorial(15, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(2)
                }
                Text(segment.sourceBeatIds.joined(separator: " · "))
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.54))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    VideoFrameDot(label: "Start", isReady: segment.startFrameSource.hasFrame || segment.order > 1)
                    if requiresTargetEndFrame {
                        VideoFrameDot(label: "End", isReady: segment.targetEndFrameSource.hasFrame)
                    }
                    VideoFrameDot(label: "Actual", isReady: !segment.actualEndFramePath.isEmpty)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    StoryMiniChip("\(segment.durationSeconds)s")
                    StoryMiniChip(segment.status.rawValue.replacingOccurrences(of: "_", with: " "))
                    if !segment.versions.isEmpty {
                        StoryMiniChip("V\(segment.activeVersion?.versionNumber ?? segment.versions.count)/\(segment.versions.count)")
                    }
                    if segment.locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CanonColor.brass)
                    }
                    if segment.downstreamStale {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(CanonColor.rust)
                    }
                }
            }
            .padding(11)
            .frame(width: 214, height: 132, alignment: .topLeading)
            .background(CanonColor.paper.opacity(isSelected ? 0.84 : 0.62), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? CanonColor.brass.opacity(0.90) : CanonColor.hairlinePaper))
        }
        .buttonStyle(.plain)
    }
}

private struct VideoFrameDot: View {
    let label: String
    let isReady: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isReady ? CanonColor.olive : CanonColor.rust)
                .frame(width: 6, height: 6)
            Text(label)
                .font(CanonType.archive(9, weight: .medium))
                .foregroundStyle(CanonColor.ink.opacity(0.62))
        }
    }
}

private struct VideoFrameSourcePickerRequest: Identifiable {
    var role: String
    var id: String { role }
}

private struct VideoFramePreviewRequest: Identifiable {
    var segmentId: String
    var role: String
    var title: String
    var fallbackPath: String
    var id: String { "\(segmentId)|\(role)|\(fallbackPath)" }
}

private struct VideoChainClipInspectorView: View {
    @ObservedObject var library: LibraryEngine
    let segment: VideoSegmentDocument?
    let requiresTargetEndFrames: Bool
    @State private var copyStatus = ""
    @State private var sourcePickerRequest: VideoFrameSourcePickerRequest?
    @State private var framePreviewRequest: VideoFramePreviewRequest?
    @State private var framePreviewZoom: CGFloat = 1
    @State private var retakeInstruction = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Clip Inspector")
                    .font(CanonType.editorial(22, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Spacer(minLength: 0)
                if let segment {
                    StoryMiniChip("Clip \(segment.order)")
                }
            }

            if let segment {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(segment.title)
                                .font(CanonType.editorial(17, weight: .semibold))
                                .foregroundStyle(CanonColor.ink)
                                .lineLimit(2)
                            Text(segment.motionDirective.isEmpty ? "Motion not specified" : segment.motionDirective)
                                .font(CanonType.interface(12))
                                .foregroundStyle(CanonColor.ink.opacity(0.62))
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                StoryMiniChip(library.videoChain.selectedProviderId == .localPromptExport || library.videoChain.selectedProviderId == .bestAvailable ? "Setup required" : library.videoChain.selectedProviderId.label)
                                StoryMiniChip((library.videoChain.selectedModelId ?? library.videoChain.modelSelection ?? .auto).label)
                                StoryMiniChip(library.videoChain.continuityMode.label)
                            }
                        }

                        videoFrameSourceBlock(
                            title: "Start Frame",
                            source: segment.startFrameSource,
                            canUseSource: segment.order == 1,
                            role: "start"
                        )

                        if requiresTargetEndFrames || segment.targetEndFrameSource.hasFrame {
                            videoFrameSourceBlock(
                                title: "Target End Frame",
                                source: segment.targetEndFrameSource,
                                canUseSource: true,
                                role: "target_end"
                            )
                        }

                        if !segment.actualEndFramePath.isEmpty {
                            framePreviewRow(
                                title: "Actual End Frame",
                                subtitle: "Extracted final frame",
                                path: segment.actualEndFramePath,
                                role: "actual_end"
                            )
                        }

                        videoVersionBlock(segment: segment)

                        VStack(alignment: .leading, spacing: 4) {
                            StoryDraftFieldLabel("Prompt")
                            Text(segment.prompt)
                                .font(CanonType.editorial(12))
                                .foregroundStyle(CanonColor.ink.opacity(0.74))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(CanonColor.paper.opacity(0.68), in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
                        }
                    }
                    .padding(.trailing, 4)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            copyToPasteboard(segment.prompt)
                            copyStatus = "Copied"
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(CanonUtilityButtonStyle())

                        Button {
                            Task {
                                await library.regenerateVideoChainSegment(segmentId: segment.segmentId, rechainDownstream: false)
                            }
                        } label: {
                            Label("Regenerate Clip", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(CanonUtilityButtonStyle())
                        .disabled(library.isGeneratingVideoChain)

                        Button {
                            Task {
                                await library.regenerateVideoChainSegment(segmentId: segment.segmentId, rechainDownstream: true)
                            }
                        } label: {
                            Label("Rechain From Here", systemImage: "link")
                        }
                        .buttonStyle(CanonUtilityButtonStyle())
                        .disabled(library.isGeneratingVideoChain)

                        if library.videoChain.selectedProviderId == .localExistingClip {
                            Button {
                                attachExistingClip()
                            } label: {
                                Label("Attach Clip", systemImage: "film")
                            }
                            .buttonStyle(CanonUtilityButtonStyle())
                        }
                    }

                    if !copyStatus.isEmpty {
                        Text(copyStatus)
                            .font(CanonType.interface(10, weight: .semibold))
                            .foregroundStyle(CanonColor.olive)
                    }
                }
            } else {
                StoryEmptyPanel(
                    title: "No clip selected",
                    subtitle: "Build a Video Plan to inspect clips.",
                    isLight: true
                )
            }
        }
        .padding(14)
        .background(CanonColor.paperInset.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
        .sheet(item: $sourcePickerRequest) { request in
            if let segment {
                VideoFrameSourceCandidatePicker(
                    library: library,
                    segment: segment,
                    role: request.role,
                    onSelect: { candidate in
                        sourcePickerRequest = nil
                        Task {
                            await library.generateVideoChainFrameFromSource(
                                segmentId: segment.segmentId,
                                role: request.role,
                                mediaId: candidate.mediaId
                            )
                        }
                    },
                    onCancel: {
                        sourcePickerRequest = nil
                    }
                )
            } else {
                StoryEmptyPanel(
                    title: "No clip selected",
                    subtitle: "Build a Video Plan to inspect clips.",
                    isLight: true
                )
                .padding(20)
            }
        }
        .sheet(item: $framePreviewRequest) { request in
            VideoFramePreviewModal(
                library: library,
                segmentId: request.segmentId,
                role: request.role,
                title: request.title,
                fallbackPath: request.fallbackPath,
                zoomScale: $framePreviewZoom
            ) {
                framePreviewRequest = nil
            }
        }
    }

    @ViewBuilder
    private func videoVersionBlock(segment: VideoSegmentDocument) -> some View {
        let versions = segment.sortedVersions.reversed()
        let activeVersion = segment.activeVersion
        let activePath = segment.activeVideoPath.trimmingCharacters(in: .whitespacesAndNewlines)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StoryDraftFieldLabel("Partial Video Versions")
                StoryMiniChip("\(segment.versions.count)")
                Spacer(minLength: 0)
                if !activePath.isEmpty, FileManager.default.fileExists(atPath: activePath) {
                    partialVideoActions(path: activePath)
                }
            }

            if !activePath.isEmpty, FileManager.default.fileExists(atPath: activePath) {
                VideoPreview(path: activePath, autoplayRequestId: 0)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
            } else {
                Text("No generated partial video for this clip yet.")
                    .font(CanonType.interface(11, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.62))
            }

            if segment.versions.isEmpty {
                Text("Generate this clip to create version 1.")
                    .font(CanonType.archive(10, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.52))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(versions), id: \.versionId) { version in
                        VideoSegmentVersionRow(
                            version: version,
                            isActive: version.versionId == activeVersion?.versionId,
                            isUsable: !version.displayVideoPath.isEmpty && FileManager.default.fileExists(atPath: version.displayVideoPath),
                            onUse: {
                                Task {
                                    await library.activateVideoChainSegmentVersion(
                                        segmentId: segment.segmentId,
                                        versionId: version.versionId
                                    )
                                }
                            },
                            onReveal: {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: version.displayVideoPath)])
                            },
                            onCopy: {
                                copyToPasteboard(version.displayVideoPath)
                                copyStatus = "Copied path"
                            }
                        )
                    }
                }
            }

            if library.videoChain.selectedProviderId == .ltxDirect,
               !activePath.isEmpty,
               FileManager.default.fileExists(atPath: activePath) {
                retakeControls(segment: segment)
            }
        }
        .padding(9)
        .background(CanonColor.paper.opacity(0.58), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
    }

    private func retakeControls(segment: VideoSegmentDocument) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            StoryDraftFieldLabel("LTX Retake")
            TextEditor(text: $retakeInstruction)
                .font(CanonType.editorial(12))
                .foregroundStyle(CanonColor.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 58)
                .padding(6)
                .background(CanonColor.paperInset.opacity(0.48), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper.opacity(0.74)))
            HStack(spacing: 7) {
                retakeButton("First 2s", start: 0, duration: min(2, Double(segment.durationSeconds)), segment: segment)
                retakeButton("Last 2s", start: max(0, Double(segment.durationSeconds) - 2), duration: min(2, Double(segment.durationSeconds)), segment: segment)
                retakeButton("Whole", start: 0, duration: Double(segment.durationSeconds), segment: segment)
            }
        }
        .padding(.top, 4)
    }

    private func retakeButton(_ title: String, start: Double, duration: Double, segment: VideoSegmentDocument) -> some View {
        Button {
            let instruction = retakeInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
            retakeInstruction = ""
            Task {
                await library.retakeVideoChainSegment(
                    segmentId: segment.segmentId,
                    startSeconds: start,
                    durationSeconds: duration,
                    instruction: instruction
                )
            }
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CanonUtilityButtonStyle())
        .disabled(library.isGeneratingVideoChain)
    }

    private func videoFrameSourceBlock(
        title: String,
        source: VideoFrameSourceDocument,
        canUseSource: Bool,
        role: String
    ) -> some View {
        let isGenerating = segment.map { library.isGeneratingVideoChainFrameSource(segmentId: $0.segmentId, role: role) } ?? false
        let path = frameDisplayPath(for: source)
        return VStack(alignment: .leading, spacing: 7) {
            StoryDraftFieldLabel(title)
            framePreviewRow(
                title: source.type.rawValue.replacingOccurrences(of: "_", with: " "),
                subtitle: source.note,
                path: path,
                role: role
            )
            HStack(spacing: 7) {
                if canUseSource {
                    Button {
                        sourcePickerRequest = VideoFrameSourcePickerRequest(role: role)
                    } label: {
                        if isGenerating {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Generating")
                            }
                        } else {
                            Label("Use Source", systemImage: "photo.on.rectangle")
                        }
                    }
                    .buttonStyle(CanonUtilityButtonStyle())
                    .disabled(isGenerating || segment == nil)
                }
                if role == "target_end", segment?.startFrameSource.hasFrame == true {
                    Button {
                        guard let segment else { return }
                        Task {
                            await library.generateVideoChainEndFrameFromStart(segmentId: segment.segmentId)
                        }
                    } label: {
                        if isGenerating {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Generating")
                            }
                        } else {
                            Label("Generate End From Start", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(CanonUtilityButtonStyle())
                    .disabled(isGenerating || segment == nil)
                }
                Button {
                    attachImage(role: role)
                } label: {
                    Label("Attach", systemImage: "paperclip")
                }
                .buttonStyle(CanonUtilityButtonStyle())
            }
        }
        .padding(9)
        .background(CanonColor.paper.opacity(0.58), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
    }

    private func partialVideoActions(path: String) -> some View {
        HStack(spacing: 6) {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } label: {
                Image(systemName: "play.rectangle")
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Open partial video")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Reveal partial video")

            Button {
                copyToPasteboard(path)
                copyStatus = "Copied path"
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Copy partial video path")
        }
    }

    private func framePathRow(title: String, path: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: path.isEmpty ? "circle" : "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(path.isEmpty ? CanonColor.rust : CanonColor.olive)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.capitalized)
                    .font(CanonType.interface(10, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.62))
                Text(path.isEmpty ? "Missing" : URL(fileURLWithPath: path).lastPathComponent)
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.56))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func framePreviewRow(title: String, subtitle: String, path: String, role: String) -> some View {
        let cleanedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let exists = !cleanedPath.isEmpty && FileManager.default.fileExists(atPath: cleanedPath)
        return Button {
            guard let segment, exists else { return }
            framePreviewZoom = 1
            framePreviewRequest = VideoFramePreviewRequest(
                segmentId: segment.segmentId,
                role: role,
                title: title.capitalized,
                fallbackPath: cleanedPath
            )
        } label: {
            HStack(spacing: 9) {
                if exists {
                    ThumbnailImage(path: cleanedPath, kind: .image)
                        .frame(width: 68, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlinePaper))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(CanonColor.paperInset.opacity(0.64))
                        .frame(width: 68, height: 44)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(CanonColor.muted)
                        }
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(systemName: exists ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(exists ? CanonColor.olive : CanonColor.rust)
                        Text(title.capitalized)
                            .font(CanonType.interface(10, weight: .semibold))
                            .foregroundStyle(CanonColor.ink.opacity(0.66))
                    }
                    Text(exists ? URL(fileURLWithPath: cleanedPath).lastPathComponent : "Missing")
                        .font(CanonType.archive(9, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.56))
                        .lineLimit(1)
                    if !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(subtitle)
                            .font(CanonType.archive(9, weight: .medium))
                            .foregroundStyle(CanonColor.muted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if exists {
                    Image(systemName: "magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CanonColor.brass)
                }
            }
            .padding(7)
            .background(CanonColor.paper.opacity(0.48), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper.opacity(0.72)))
        }
        .buttonStyle(.plain)
        .disabled(!exists)
    }

    private func frameDisplayPath(for source: VideoFrameSourceDocument) -> String {
        source.normalizedFramePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? source.framePath
            : source.normalizedFramePath
    }

    private func attachImage(role: String) {
        guard let segment else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        library.attachVideoChainFrame(segmentId: segment.segmentId, role: role, sourceURL: url)
    }

    private func attachExistingClip() {
        guard let segment else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.movie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        library.attachVideoChainExistingClip(segmentId: segment.segmentId, sourceURL: url)
    }
}

private struct VideoFramePreviewModal: View {
    @ObservedObject var library: LibraryEngine
    let segmentId: String
    let role: String
    let title: String
    let fallbackPath: String
    @Binding var zoomScale: CGFloat
    let onClose: () -> Void
    @State private var assistantText = ""
    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 5

    private var segment: VideoSegmentDocument? {
        library.videoChain.segments.first { $0.segmentId == segmentId }
    }

    private var source: VideoFrameSourceDocument? {
        guard let segment else { return nil }
        switch role {
        case "start":
            return segment.startFrameSource
        case "target_end":
            return segment.targetEndFrameSource
        default:
            return nil
        }
    }

    private var activeVersionId: String {
        source?.versionId ?? ""
    }

    private var framePath: String {
        if role == "actual_end" {
            return segment?.actualEndFramePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? segment?.actualEndFramePath ?? fallbackPath
                : fallbackPath
        }
        let normalized = source?.normalizedFramePath.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !normalized.isEmpty { return normalized }
        let raw = source?.framePath.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? fallbackPath : raw
    }

    private var versions: [VideoFrameVersionDocument] {
        Array((segment?.sortedFrameVersions(role: role) ?? []).reversed())
    }

    private var messages: [VideoFrameChatMessageDocument] {
        (segment?.frameChatMessages ?? [])
            .filter { $0.frameRole == role }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var canRegenerate: Bool {
        (role == "start" || role == "target_end")
            && !assistantText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !library.isGeneratingVideoChainFrameSource(segmentId: segmentId, role: role)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            HStack(spacing: 0) {
                imageSurface
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                Rectangle()
                    .fill(CanonColor.hairlineDark)
                    .frame(width: 1)
                sidePanel
                    .frame(width: 360)
            }
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            controls
        }
        .frame(minWidth: 980, minHeight: 680)
        .background(CanonColor.room.opacity(0.98))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(CanonType.editorial(24, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                    .lineLimit(1)
                Text(segment?.title ?? segmentId)
                    .font(CanonType.archive(11, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                copyToPasteboard(framePath)
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Copy frame path")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: framePath)])
            } label: {
                Image(systemName: "folder")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .disabled(framePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Reveal frame")

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .keyboardShortcut(.cancelAction)
            .help("Close")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(CanonColor.sidebar)
    }

    @ViewBuilder
    private var imageSurface: some View {
        if FileManager.default.fileExists(atPath: framePath) {
            ZoomableImageScrollView(
                path: framePath,
                zoomScale: $zoomScale,
                minZoom: minZoom,
                maxZoom: maxZoom
            )
            .background(CanonColor.room)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(CanonColor.brass)
                Text("Frame could not be loaded")
                    .font(CanonType.editorial(22, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text(framePath)
                    .font(CanonType.archive(11))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CanonColor.room)
        }
    }

    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                versionSection
                if role == "start" || role == "target_end" {
                    assistantSection
                } else {
                    Text("Actual end frames are extracted from clip versions. Regenerate or retake the clip to change this frame.")
                        .font(CanonType.interface(12))
                        .foregroundStyle(CanonColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
        }
        .background(CanonColor.sidebar)
    }

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Frame Versions")
                    .font(CanonType.editorial(18, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                StoryMiniChip("\(versions.count)")
            }
            if versions.isEmpty {
                Text(role == "actual_end" ? "No generated frame versions." : "Generate this frame to create version history.")
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.muted)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(versions) { version in
                        frameVersionRow(version)
                    }
                }
            }
        }
    }

    private func frameVersionRow(_ version: VideoFrameVersionDocument) -> some View {
        let isActive = version.versionId == activeVersionId
        return HStack(spacing: 8) {
            ThumbnailImage(path: version.displayFramePath, kind: .image)
                .frame(width: 58, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(CanonColor.hairlineDark))
            VStack(alignment: .leading, spacing: 2) {
                Text("V\(version.versionNumber) \(isActive ? "active" : "")")
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(isActive ? CanonColor.olive : CanonColor.bone)
                    .lineLimit(1)
                Text(version.assistantNote.isEmpty ? version.createdAt : version.assistantNote)
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if !isActive {
                Button {
                    Task {
                        await library.activateVideoChainFrameVersion(segmentId: segmentId, role: role, versionId: version.versionId)
                    }
                } label: {
                    Text("Use")
                        .frame(width: 42)
                }
                .buttonStyle(CanonUtilityButtonStyle())
            }
        }
        .padding(7)
        .background(CanonColor.mediaCard.opacity(isActive ? 0.92 : 0.62), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(isActive ? CanonColor.olive.opacity(0.62) : CanonColor.hairlineDark))
    }

    private var assistantSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Frame Assistant")
                .font(CanonType.editorial(18, weight: .semibold))
                .foregroundStyle(CanonColor.bone)

            if messages.isEmpty {
                Text("Describe what should change. Each send creates a new frame version and activates it.")
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        frameMessageBubble(message)
                    }
                }
            }

            TextEditor(text: $assistantText)
                .font(CanonType.editorial(13))
                .foregroundStyle(CanonColor.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(6)
                .background(CanonColor.paper.opacity(0.90), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))

            HStack {
                Spacer(minLength: 0)
                Button {
                    let text = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
                    assistantText = ""
                    Task {
                        await library.regenerateVideoChainFrameWithAssistant(
                            segmentId: segmentId,
                            role: role,
                            instruction: text
                        )
                    }
                } label: {
                    if library.isGeneratingVideoChainFrameSource(segmentId: segmentId, role: role) {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Generating")
                        }
                    } else {
                        Label("Send & Regenerate", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(CanonPrimaryButtonStyle())
                .disabled(!canRegenerate)
            }
        }
    }

    private func frameMessageBubble(_ message: VideoFrameChatMessageDocument) -> some View {
        let isUser = message.role == .user
        return HStack(alignment: .top) {
            if isUser { Spacer(minLength: 24) }
            VStack(alignment: .leading, spacing: 4) {
                Text(isUser ? "You" : "LitScenes")
                    .font(CanonType.archive(9, weight: .semibold))
                    .foregroundStyle(isUser ? CanonColor.focusBlue : CanonColor.brass)
                Text(message.text)
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .background(isUser ? CanonColor.paperAged.opacity(0.72) : CanonColor.paperInset.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isUser ? CanonColor.focusBlue.opacity(0.28) : CanonColor.hairlinePaper))
            if !isUser { Spacer(minLength: 24) }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                zoomScale = max(minZoom, zoomScale - 0.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 28)
            }
            .buttonStyle(CanonSecondaryButtonStyle())

            Slider(value: $zoomScale, in: minZoom...maxZoom)
                .frame(width: 240)

            Button {
                zoomScale = min(maxZoom, zoomScale + 0.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 28)
            }
            .buttonStyle(CanonSecondaryButtonStyle())

            Text("\(Int((zoomScale * 100).rounded()))%")
                .font(CanonType.archive(11, weight: .medium))
                .foregroundStyle(CanonColor.muted)
                .frame(width: 48, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(CanonColor.sidebar)
    }
}

private struct VideoFrameSourceCandidatePicker: View {
    @ObservedObject var library: LibraryEngine
    let segment: VideoSegmentDocument
    let role: String
    let onSelect: (VideoFrameSourceCandidate) -> Void
    let onCancel: () -> Void
    @State private var searchText = ""

    private var filteredCandidates: [VideoFrameSourceCandidate] {
        let candidates = library.videoFrameSourceCandidates(segmentId: segment.segmentId)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return candidates }
        return candidates.filter { candidate in
            [
                candidate.filename,
                candidate.relativePath,
                candidate.displaySubtitle,
                candidate.mediaId
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(role == "start" ? "Start Source" : "Target End Source")
                        .font(CanonType.editorial(24, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    Text(segment.title)
                        .font(CanonType.interface(12, weight: .medium))
                        .foregroundStyle(CanonColor.ink.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button("Cancel", action: onCancel)
                    .buttonStyle(CanonUtilityButtonStyle())
            }

            TextField("Search media", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(VideoFrameSourceCandidateGroup.allCases) { group in
                        let groupCandidates = filteredCandidates.filter { $0.group == group }
                        if !groupCandidates.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    StoryDraftFieldLabel(group.label)
                                    StoryMiniChip("\(groupCandidates.count)")
                                }
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: 156, maximum: 190), spacing: 10)],
                                    alignment: .leading,
                                    spacing: 10
                                ) {
                                    ForEach(groupCandidates) { candidate in
                                        VideoFrameSourceCandidateCard(
                                            candidate: candidate,
                                            isGenerating: library.isGeneratingVideoChainFrameSource(segmentId: segment.segmentId, role: role),
                                            onSelect: {
                                                onSelect(candidate)
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }

                    if filteredCandidates.isEmpty {
                        StoryEmptyPanel(
                            title: "No media",
                            subtitle: "No enabled media matches this search.",
                            isLight: true
                        )
                    }
                }
                .padding(.trailing, 4)
            }
        }
        .padding(18)
        .frame(width: 880, height: 680)
        .background(CanonColor.paperInset)
    }
}

private struct VideoFrameSourceCandidateCard: View {
    let candidate: VideoFrameSourceCandidate
    let isGenerating: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                ThumbnailImage(path: candidate.thumbnailPath, kind: candidate.kind)
                    .frame(height: 104)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))

                Text(candidate.filename)
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                    .lineLimit(2)
                    .frame(minHeight: 30, alignment: .topLeading)

                Text(candidate.displaySubtitle)
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.56))
                    .lineLimit(2)
                    .frame(minHeight: 24, alignment: .topLeading)

                HStack(spacing: 6) {
                    StoryMiniChip(candidate.kind.rawValue)
                    if candidate.width > 0 && candidate.height > 0 {
                        StoryMiniChip("\(candidate.width)x\(candidate.height)")
                    }
                    if let seconds = candidate.sourceTimestampSeconds {
                        StoryMiniChip(seconds.durationLabel)
                    }
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(CanonColor.paper.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
        }
        .buttonStyle(.plain)
        .disabled(isGenerating)
        .help(candidate.sourcePath)
    }
}

private struct VideoSegmentVersionRow: View {
    let version: VideoSegmentVersionDocument
    let isActive: Bool
    let isUsable: Bool
    let onUse: () -> Void
    let onReveal: () -> Void
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("V\(version.versionNumber)")
                        .font(CanonType.archive(11, weight: .semibold))
                        .foregroundStyle(isActive ? CanonColor.olive : CanonColor.brass)
                    Text(version.status.rawValue.replacingOccurrences(of: "_", with: " "))
                        .font(CanonType.interface(9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(version.status == .failed ? CanonColor.rust : CanonColor.ink.opacity(0.58))
                    if isActive {
                        StoryMiniChip("active")
                    }
                }
                Text(detailLine)
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.54))
                    .lineLimit(1)
                if !version.errorMessage.isEmpty {
                    Text(version.errorMessage)
                        .font(CanonType.interface(10, weight: .medium))
                        .foregroundStyle(CanonColor.rust)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if isUsable {
                Button {
                    onUse()
                } label: {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help(isActive ? "Active version" : "Use this version")
                .disabled(isActive)

                Button {
                    onReveal()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Reveal version")

                Button {
                    onCopy()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Copy version path")
            }
        }
        .padding(7)
        .background(CanonColor.paper.opacity(isActive ? 0.76 : 0.48), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(isActive ? CanonColor.olive.opacity(0.35) : CanonColor.hairlinePaper))
    }

    private var detailLine: String {
        var parts = [
            version.providerId.label,
            (version.modelId ?? .auto).label,
            version.createdAt
        ]
        if !version.providerJobId.isEmpty {
            parts.append("job \(version.providerJobId)")
        }
        return parts.joined(separator: " · ")
    }
}

private struct SceneLayerInspectorDraft: Equatable {
    var prompt = ""
    var negativePrompt = ""
    var textOverlay = ""
    var captionDraft = ""

    init() {}

    init(asset: SceneAssetDocument) {
        prompt = asset.prompt
        negativePrompt = asset.negativePrompt
        textOverlay = asset.textOverlay
        captionDraft = asset.captionDraft
    }
}

private struct SceneAnchorRow: View {
    let anchor: StoryMediaAnchor
    let item: MediaItemRecord?

    var body: some View {
        HStack(spacing: 8) {
            ThumbnailImage(path: anchor.thumbnailPath, kind: anchor.kind == .videoFrame ? .image : (item?.kind ?? .image))
                .frame(width: 42, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(CanonColor.hairlinePaper))
            VStack(alignment: .leading, spacing: 2) {
                Text(item?.filename ?? anchor.mediaId)
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                    .lineLimit(1)
                Text(anchor.note.isEmpty ? anchor.role.label : "\(anchor.role.label) - \(anchor.note)")
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.58))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(7)
        .background(CanonColor.paper.opacity(0.62), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
    }
}

private func copyToPasteboard(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
}

private struct StoryCueColumn: View {
    let title: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(CanonType.interface(10, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(CanonColor.brass)
            if cleanedValues.isEmpty {
                Text("Not specified")
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.ink.opacity(0.55))
            } else {
                Text(cleanedValues.joined(separator: " · "))
                    .font(CanonType.editorial(14))
                    .foregroundStyle(CanonColor.ink.opacity(0.78))
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var cleanedValues: [String] {
        Array(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(6))
    }
}

private struct StorySetupRail: View {
    @ObservedObject var library: LibraryEngine
    @State private var draft = StorySetupDocument.empty()
    @State private var loadedProjectId = ""
    @State private var isSyncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Story Setup")
                    .font(CanonType.editorial(22, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Text("Optional steering. Defaults are ready.")
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.ink.opacity(0.62))
            }

            setupMenu("Output", label: draft.outputType.label) {
                ForEach(StoryOutputType.allCases) { value in
                    Button(value.label) {
                        draft.outputType = value
                    }
                }
            }
            setupMenu("Invention", label: draft.inventionLevel.label) {
                ForEach(StoryInventionLevel.allCases) { value in
                    Button(value.label) {
                        draft.inventionLevel = value
                    }
                }
            }
            setupMenu("Commercial", label: draft.commercialPressure.label) {
                ForEach(StoryCommercialPressure.allCases) { value in
                    Button(value.label) {
                        draft.commercialPressure = value
                    }
                }
            }
            setupPOVMenu
            setupEngineMenu
            setupEndingMenu

            StorySetupTextArea(title: "Must include", placeholder: "Optional required image, turn, phrase, or motif.", text: $draft.mustInclude)
            StorySetupTextArea(title: "Avoid", placeholder: "Optional story or treatment constraints.", text: $draft.avoid)

            if draft.needsCommercialDetails {
                Divider()
                    .overlay(CanonColor.hairlinePaper)
                StorySetupField(title: "Product / service", text: $draft.commercialDetails.productService)
                StorySetupField(title: "Audience", text: $draft.commercialDetails.audience)
                StorySetupField(title: "Offer / promise", text: $draft.commercialDetails.offerOrPromise)
                StorySetupField(title: "CTA", text: $draft.commercialDetails.cta)
                StorySetupField(title: "Do not say", text: $draft.commercialDetails.doNotSay)
                StorySetupField(title: "Brand tone", text: $draft.commercialDetails.brandTone)
            }

            Button {
                Task {
                    await library.generateStoryDirections()
                }
            } label: {
                Label("Generate Storylines", systemImage: "rectangle.stack.badge.play")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CanonPrimaryButtonStyle(isFullWidth: true))
            .disabled(library.isGeneratingStoryDirections || library.currentStoryScopeItems.isEmpty)
        }
        .padding(14)
        .background(CanonColor.paperInset.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper)
        )
        .onAppear(perform: syncFromLibrary)
        .onChange(of: library.currentProject?.projectId ?? "") { _, _ in
            syncFromLibrary()
        }
        .onChange(of: library.storySetup) { _, value in
            guard value != draft else { return }
            syncFromLibrary()
        }
        .onChange(of: draft) { _, _ in
            commit()
        }
    }

    private var goalSetupSuggestions: ProjectGoalStorySetupSuggestions {
        library.activeGoalBrief.storySetupSuggestions.normalized()
    }

    private var setupPOVMenu: some View {
        setupMenu("POV", label: draft.effectivePOVLabel) {
            Button("Auto") {
                draft.pov = .auto
                draft.customPovOption = .empty()
            }
            if !goalSetupSuggestions.povOptions.isEmpty {
                Divider()
                ForEach(goalSetupSuggestions.povOptions) { option in
                    Button(option.displayLabel) {
                        draft.pov = .auto
                        draft.customPovOption = option
                    }
                }
            }
            Divider()
            ForEach(StoryPOV.allCases.filter { $0 != .auto }) { value in
                Button(value.label) {
                    draft.pov = value
                    draft.customPovOption = .empty()
                }
            }
        }
    }

    private var setupEngineMenu: some View {
        setupMenu("Engine", label: draft.effectiveStoryEngineLabel) {
            Button("Auto") {
                draft.storyEngine = .auto
                draft.customStoryEngineOption = .empty()
            }
            if !goalSetupSuggestions.engineOptions.isEmpty {
                Divider()
                ForEach(goalSetupSuggestions.engineOptions) { option in
                    Button(option.displayLabel) {
                        draft.storyEngine = .auto
                        draft.customStoryEngineOption = option
                    }
                }
            }
            Divider()
            ForEach(StoryEnginePreference.allCases.filter { $0 != .auto }) { value in
                Button(value.label) {
                    draft.storyEngine = value
                    draft.customStoryEngineOption = .empty()
                }
            }
        }
    }

    private var setupEndingMenu: some View {
        setupMenu("Ending", label: draft.effectiveEndingStyleLabel) {
            Button("Auto") {
                draft.endingStyle = .ambiguousFinalImage
                draft.customEndingOption = .empty()
            }
            if !goalSetupSuggestions.endingOptions.isEmpty {
                Divider()
                ForEach(goalSetupSuggestions.endingOptions) { option in
                    Button(option.displayLabel) {
                        draft.endingStyle = .ambiguousFinalImage
                        draft.customEndingOption = option
                    }
                }
            }
            Divider()
            ForEach(StoryEndingStyle.allCases) { value in
                Button(value.label) {
                    draft.endingStyle = value
                    draft.customEndingOption = .empty()
                }
            }
        }
    }

    private func setupMenu<Content: View>(
        _ title: String,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            StoryDraftFieldLabel(title)
            Menu {
                content()
            } label: {
                HStack(spacing: 8) {
                    Text(label)
                        .font(CanonType.interface(12, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CanonColor.muted)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CanonColor.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(CanonColor.hairlinePaper)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func syncFromLibrary() {
        isSyncing = true
        loadedProjectId = library.currentProject?.projectId ?? ""
        draft = library.storySetup
        isSyncing = false
    }

    private func commit() {
        guard !isSyncing else { return }
        guard loadedProjectId == (library.currentProject?.projectId ?? "") else { return }
        library.saveStorySetupDraft(draft)
    }
}

private struct StoryCreateStorylinePanel: View {
    @ObservedObject var library: LibraryEngine
    let onClose: () -> Void
    @State private var draftSetup = StorySetupDocument.empty()
    @State private var loadedProjectId = ""
    @State private var isSyncing = false
    @State private var composerText = ""
    @State private var isSubmittingMessage = false
    @FocusState private var isComposerFocused: Bool

    private var draft: StorylineCreationDraft {
        library.storylineCreation.draft.normalized()
    }

    private var isComposerWaiting: Bool {
        isSubmittingMessage || library.isInterviewingStorylineCreation
    }

    private var canSendMessage: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isComposerWaiting && !library.isGeneratingStoryline
    }

    private var canGenerateStoryline: Bool {
        library.storylineCreation.isReadyToGenerate
            && !library.currentStoryScopeItems.isEmpty
            && !library.isGeneratingStoryline
            && !library.isInterviewingStorylineCreation
            && !library.isGeneratingStoryDirections
            && !library.isBuildingStorySignals
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            setupControls
            draftSummary
            chatArea
        }
        .padding(14)
        .background(CanonColor.paperInset.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper)
        )
        .onAppear(perform: syncFromLibrary)
        .onChange(of: library.currentProject?.projectId ?? "") { _, _ in
            syncFromLibrary()
        }
        .onChange(of: library.storylineCreation.draftSetup) { _, value in
            guard value != draftSetup else { return }
            syncFromLibrary()
        }
        .onChange(of: draftSetup) { _, _ in
            commitSetup()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Create Storyline")
                    .font(CanonType.editorial(24, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Text(statusText)
                    .font(CanonType.interface(12, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if library.isInterviewingStorylineCreation || library.isGeneratingStoryline {
                ProgressView()
                    .controlSize(.small)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Close Create Storyline")
        }
    }

    private var statusText: String {
        if library.isGeneratingStoryline {
            return "Generating one Storyline."
        }
        if library.isInterviewingStorylineCreation {
            return "Reading the draft."
        }
        if draft.isReadyToGenerate {
            return "Enough detail to generate one Storyline."
        }
        if !draft.openQuestions.isEmpty {
            return "Clarify the open question before generating."
        }
        return "Untitled until the Storyline direction is clear."
    }

    private var setupControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                setupMenu("Output", label: draftSetup.outputType.label) {
                    ForEach(StoryOutputType.allCases) { value in
                        Button(value.label) {
                            draftSetup.outputType = value
                        }
                    }
                }
                setupMenu("Invention", label: draftSetup.inventionLevel.label) {
                    ForEach(StoryInventionLevel.allCases) { value in
                        Button(value.label) {
                            draftSetup.inventionLevel = value
                        }
                    }
                }
                setupMenu("Commercial", label: draftSetup.commercialPressure.label) {
                    ForEach(StoryCommercialPressure.allCases) { value in
                        Button(value.label) {
                            draftSetup.commercialPressure = value
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 10) {
                setupPOVMenu
                setupEngineMenu
                setupEndingMenu
            }

            HStack(alignment: .top, spacing: 10) {
                StorySetupTextArea(title: "Must include", placeholder: "Optional required image, turn, phrase, or motif.", text: $draftSetup.mustInclude)
                StorySetupTextArea(title: "Avoid", placeholder: "Optional story or treatment constraints.", text: $draftSetup.avoid)
            }

            if draftSetup.needsCommercialDetails {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .overlay(CanonColor.hairlinePaper)
                    HStack(alignment: .top, spacing: 10) {
                        StorySetupField(title: "Product / service", text: $draftSetup.commercialDetails.productService)
                        StorySetupField(title: "Audience", text: $draftSetup.commercialDetails.audience)
                        StorySetupField(title: "Offer / promise", text: $draftSetup.commercialDetails.offerOrPromise)
                    }
                    HStack(alignment: .top, spacing: 10) {
                        StorySetupField(title: "CTA", text: $draftSetup.commercialDetails.cta)
                        StorySetupField(title: "Do not say", text: $draftSetup.commercialDetails.doNotSay)
                        StorySetupField(title: "Brand tone", text: $draftSetup.commercialDetails.brandTone)
                    }
                }
            }
        }
    }

    private var draftSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(draft.storylineTitle.isEmpty ? "Untitled Storyline" : draft.storylineTitle)
                    .font(CanonType.editorial(20, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text("Confidence \(Int((draft.confidence0To1 * 100).rounded()))%")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
            }

            Text(draft.storylineIntent.isEmpty ? "Chat to shape one additional storyline direction. It will append above the current storylines when generated." : draft.storylineIntent)
                .font(CanonType.editorial(14))
                .foregroundStyle(draft.storylineIntent.isEmpty ? CanonColor.muted : CanonColor.ink.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if !draft.readinessSummary.isEmpty {
                Text(draft.readinessSummary)
                    .font(CanonType.interface(12, weight: .medium))
                    .foregroundStyle(draft.isReadyToGenerate ? CanonColor.olive : CanonColor.brass)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !draft.openQuestions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    StoryDraftFieldLabel("Open Questions")
                    Text(draft.openQuestions.joined(separator: "; "))
                        .font(CanonType.editorial(13))
                        .foregroundStyle(CanonColor.ink.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(draft.isReadyToGenerate ? CanonColor.olive : CanonColor.brass)
                .frame(width: 2)
        }
    }

    private var chatArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            transcript
            composer
            HStack(spacing: 8) {
                Button {
                    library.resetStorylineCreationDraft()
                    syncFromLibrary()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(library.isInterviewingStorylineCreation || library.isGeneratingStoryline)

                Spacer(minLength: 0)

                Button {
                    Task {
                        await library.generateStorylineFromCreationDraft()
                    }
                } label: {
                    Label(library.isGeneratingStoryline ? "Generating Storyline" : "Generate Storyline", systemImage: "rectangle.stack.badge.plus")
                }
                .buttonStyle(CanonPrimaryButtonStyle())
                .disabled(!canGenerateStoryline)
            }
        }
    }

    private var transcript: some View {
        Group {
            if library.storylineCreation.messages.isEmpty {
                currentQuestionCard
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(library.storylineCreation.messages) { message in
                                messageBubble(message)
                                    .id(message.messageId)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 220)
                    .onChange(of: library.storylineCreation.messages.count) { _, _ in
                        guard let id = library.storylineCreation.messages.last?.messageId else { return }
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.14)) {
                                proxy.scrollTo(id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    private var currentQuestionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What new Storyline should this add?")
                .font(CanonType.editorial(17, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            Text("Describe the direction, what it should emphasize, and how it should differ from the current Storylines.")
                .font(CanonType.interface(12))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.paper.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.6)))
    }

    private var composer: some View {
        ZStack(alignment: .topLeading) {
            if composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                composerPlaceholder
            }
            TextEditor(text: $composerText)
                .font(CanonType.editorial(14))
                .frame(minHeight: 92, maxHeight: 150)
                .scrollContentBackground(.hidden)
                .foregroundStyle(CanonColor.ink)
                .focused($isComposerFocused)
                .disabled(isComposerWaiting || library.isGeneratingStoryline)
                .onKeyPress(keys: [.return]) { press in
                    guard press.modifiers.contains(.command), canSendMessage else {
                        return .ignored
                    }
                    sendMessage()
                    return .handled
                }
        }
        .padding(.bottom, 38)
        .background(CanonColor.paper.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper.opacity(0.70))
        )
        .overlay(alignment: .bottomTrailing) {
            Button {
                sendMessage()
            } label: {
                Label("Send", systemImage: "paperplane.fill")
            }
            .buttonStyle(CanonSecondaryButtonStyle())
            .disabled(!canSendMessage)
            .padding(8)
        }
    }

    @ViewBuilder
    private var composerPlaceholder: some View {
        if isComposerWaiting {
            TimelineView(.periodic(from: Date(), by: 0.45)) { context in
                Text(thinkingPlaceholderText(at: context.date))
                    .font(CanonType.editorial(14))
                    .foregroundStyle(CanonColor.muted.opacity(0.72))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        } else {
            Text("Describe the Storyline direction, constraints, or difference from the existing Storylines.")
                .font(CanonType.editorial(14))
                .foregroundStyle(CanonColor.muted.opacity(0.72))
                .padding(.horizontal, 7)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
        }
    }

    private func messageBubble(_ message: ProjectGoalMessage) -> some View {
        let isUser = message.role == .user
        return HStack(alignment: .top) {
            if isUser { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 5) {
                Text(isUser ? "You" : "LitScenes")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(isUser ? CanonColor.focusBlue : CanonColor.brass)
                Text(message.text)
                    .font(CanonType.editorial(14))
                    .foregroundStyle(CanonColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(isUser ? CanonColor.paperAged.opacity(0.62) : CanonColor.paper.opacity(0.52), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isUser ? CanonColor.focusBlue.opacity(0.28) : CanonColor.hairlinePaper)
            )
            if !isUser { Spacer(minLength: 36) }
        }
    }

    private func thinkingPlaceholderText(at date: Date) -> String {
        let step = Int(date.timeIntervalSinceReferenceDate / 0.45) % 3
        return "thinking" + String(repeating: ".", count: step + 1)
    }

    private var goalSetupSuggestions: ProjectGoalStorySetupSuggestions {
        library.activeGoalBrief.storySetupSuggestions.normalized()
    }

    private var setupPOVMenu: some View {
        setupMenu("POV", label: draftSetup.effectivePOVLabel) {
            Button("Auto") {
                draftSetup.pov = .auto
                draftSetup.customPovOption = .empty()
            }
            if !goalSetupSuggestions.povOptions.isEmpty {
                Divider()
                ForEach(goalSetupSuggestions.povOptions) { option in
                    Button(option.displayLabel) {
                        draftSetup.pov = .auto
                        draftSetup.customPovOption = option
                    }
                }
            }
            Divider()
            ForEach(StoryPOV.allCases.filter { $0 != .auto }) { value in
                Button(value.label) {
                    draftSetup.pov = value
                    draftSetup.customPovOption = .empty()
                }
            }
        }
    }

    private var setupEngineMenu: some View {
        setupMenu("Engine", label: draftSetup.effectiveStoryEngineLabel) {
            Button("Auto") {
                draftSetup.storyEngine = .auto
                draftSetup.customStoryEngineOption = .empty()
            }
            if !goalSetupSuggestions.engineOptions.isEmpty {
                Divider()
                ForEach(goalSetupSuggestions.engineOptions) { option in
                    Button(option.displayLabel) {
                        draftSetup.storyEngine = .auto
                        draftSetup.customStoryEngineOption = option
                    }
                }
            }
            Divider()
            ForEach(StoryEnginePreference.allCases.filter { $0 != .auto }) { value in
                Button(value.label) {
                    draftSetup.storyEngine = value
                    draftSetup.customStoryEngineOption = .empty()
                }
            }
        }
    }

    private var setupEndingMenu: some View {
        setupMenu("Ending", label: draftSetup.effectiveEndingStyleLabel) {
            Button("Auto") {
                draftSetup.endingStyle = .ambiguousFinalImage
                draftSetup.customEndingOption = .empty()
            }
            if !goalSetupSuggestions.endingOptions.isEmpty {
                Divider()
                ForEach(goalSetupSuggestions.endingOptions) { option in
                    Button(option.displayLabel) {
                        draftSetup.endingStyle = .ambiguousFinalImage
                        draftSetup.customEndingOption = option
                    }
                }
            }
            Divider()
            ForEach(StoryEndingStyle.allCases) { value in
                Button(value.label) {
                    draftSetup.endingStyle = value
                    draftSetup.customEndingOption = .empty()
                }
            }
        }
    }

    private func setupMenu<Content: View>(
        _ title: String,
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            StoryDraftFieldLabel(title)
            Menu {
                content()
            } label: {
                HStack(spacing: 8) {
                    Text(label)
                        .font(CanonType.interface(12, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CanonColor.muted)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CanonColor.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(CanonColor.hairlinePaper)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func sendMessage() {
        guard canSendMessage else { return }
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        composerText = ""
        isComposerFocused = false
        isSubmittingMessage = true
        Task {
            await library.sendStorylineCreationMessage(text: text)
            isSubmittingMessage = false
        }
    }

    private func syncFromLibrary() {
        isSyncing = true
        loadedProjectId = library.currentProject?.projectId ?? ""
        draftSetup = library.storylineCreation.draftSetup.projectId.isEmpty ? library.storySetup : library.storylineCreation.draftSetup
        isSyncing = false
    }

    private func commitSetup() {
        guard !isSyncing else { return }
        guard loadedProjectId == (library.currentProject?.projectId ?? "") else { return }
        library.saveStorylineCreationDraftSetup(draftSetup)
    }
}

private protocol StorySetupPickerValue: Hashable, Identifiable {
    var label: String { get }
}

extension StoryOutputType: StorySetupPickerValue {}
extension StoryInventionLevel: StorySetupPickerValue {}
extension StoryCommercialPressure: StorySetupPickerValue {}
extension StoryPOV: StorySetupPickerValue {}
extension StoryEnginePreference: StorySetupPickerValue {}
extension StoryEndingStyle: StorySetupPickerValue {}

private struct StorySetupTextArea: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StoryDraftFieldLabel(title)
            ZStack(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(CanonType.editorial(13))
                        .foregroundStyle(CanonColor.ink.opacity(0.42))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 7)
                }
                TextEditor(text: $text)
                    .font(CanonType.editorial(13))
                    .frame(minHeight: 58, maxHeight: 82)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(CanonColor.ink)
                    .background(Color.clear)
            }
            .background(CanonColor.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(CanonColor.hairlinePaper)
            )
        }
    }
}

private struct StorySetupField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StoryDraftFieldLabel(title)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct StoryDirectionCardView: View {
    let direction: StoryDirectionCard
    let isSelected: Bool
    let onEnabledChange: (Bool) -> Void
    let onSelect: () -> Void
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(direction.lane.label.uppercased())
                    .font(CanonType.interface(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(isSelected ? CanonColor.ink : CanonColor.brass)
                Spacer(minLength: 0)
                Text(direction.enabled ? "Enabled" : "Disabled")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(direction.enabled ? CanonColor.olive : CanonColor.muted)
            }
            Text(direction.title)
                .font(CanonType.editorial(20, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .lineLimit(2)
            Text(direction.premise)
                .font(CanonType.editorial(14))
                .foregroundStyle(CanonColor.ink.opacity(0.74))
                .lineLimit(3)
            HStack(spacing: 7) {
                StoryMiniChip(direction.storyEngine.isEmpty ? "Engine pending" : direction.storyEngine)
                if let move = direction.meaningMoves.first, !move.isEmpty {
                    StoryMiniChip(move)
                }
            }
            StoryBeatField(
                title: "Aesthetic Use",
                value: [direction.aestheticUse.narrative, direction.aestheticUse.presentation]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: " / "),
                isLight: true
            )
            if !direction.threeBeatPreview.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(direction.threeBeatPreview.prefix(3).enumerated()), id: \.offset) { index, beat in
                        Text("\(index + 1). \(beat)")
                            .font(CanonType.archive(10, weight: .medium))
                            .foregroundStyle(CanonColor.ink.opacity(0.58))
                            .lineLimit(1)
                    }
                }
            }
            if !direction.risk.isEmpty {
                StoryMiniChip("Risk: \(direction.risk)")
                    .lineLimit(1)
            }
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 8) {
                    StoryBeatField(title: "What happens", value: direction.whatHappens, isLight: true)
                    StoryBeatField(title: "Why it works", value: direction.whyItWorks, isLight: true)
                    if !direction.validationWarnings.isEmpty {
                        Text(direction.validationWarnings.joined(separator: " · "))
                            .font(CanonType.interface(10, weight: .medium))
                            .foregroundStyle(CanonColor.rust)
                    }
                }
                .padding(.top, 6)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button("Preview Storyline", action: onSelect)
                    .buttonStyle(CanonUtilityButtonStyle())
                    .disabled(isSelected)
                Button {
                    onExpand()
                } label: {
                    Label("Open in Beats", systemImage: "arrow.right")
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                Spacer(minLength: 0)
                Button {
                    onEnabledChange(!direction.enabled)
                } label: {
                    Label(direction.enabled ? "Disable" : "Enable", systemImage: direction.enabled ? "eye.slash" : "eye")
                }
                .buttonStyle(CanonUtilityButtonStyle())
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 270, alignment: .topLeading)
        .opacity(direction.enabled ? 1 : 0.52)
        .background(CanonColor.paperInset.opacity(isSelected ? 0.95 : 0.62), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? CanonColor.brass.opacity(0.8) : (direction.enabled ? CanonColor.hairlinePaper : CanonColor.hairlinePaper.opacity(0.55)))
        )
    }
}

private struct StorySelectedDirectionView: View {
    let direction: StoryDirectionCard
    let isGenerating: Bool
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(direction.title)
                    .font(CanonType.editorial(25, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Spacer(minLength: 0)
                Text(direction.lane.label.uppercased())
                    .font(CanonType.interface(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(CanonColor.brass)
            }
            Text(direction.whatHappens.isEmpty ? direction.premise : direction.whatHappens)
                .font(CanonType.editorial(16))
                .foregroundStyle(CanonColor.ink.opacity(0.72))
                .lineSpacing(2)
            HStack(alignment: .top, spacing: 12) {
                StoryBeatField(title: "Why it works", value: direction.whyItWorks, isLight: true)
                StoryBeatField(title: "Risk", value: direction.risk, isLight: true)
            }
            Button {
                onExpand()
            } label: {
                Label(isGenerating ? "Opening Beats" : "Open in Beats", systemImage: "rectangle.grid.2x2")
            }
            .buttonStyle(CanonPrimaryButtonStyle())
            .disabled(isGenerating)
        }
        .padding(14)
        .background(CanonColor.paperInset.opacity(0.74), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper)
        )
    }
}

private struct StorySequenceTileView: View {
    let tile: StorySequenceStripTile
    let isSelected: Bool
    let showsMoveControls: Bool
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let onSelect: () -> Void
    let onOpenInspector: () -> Void
    let onMoveEarlier: () -> Void
    let onMoveLater: () -> Void
    let onMoveToStart: () -> Void
    let onMoveToEnd: () -> Void
    let onRewrite: () -> Void
    let onReplace: () -> Void
    let onSplit: () -> Void
    let onDelete: () -> Void
    let onOpenScenes: () -> Void

    init(
        tile: StorySequenceStripTile,
        isSelected: Bool = false,
        showsMoveControls: Bool = false,
        canMoveEarlier: Bool = false,
        canMoveLater: Bool = false,
        onSelect: @escaping () -> Void = {},
        onOpenInspector: @escaping () -> Void = {},
        onMoveEarlier: @escaping () -> Void = {},
        onMoveLater: @escaping () -> Void = {},
        onMoveToStart: @escaping () -> Void = {},
        onMoveToEnd: @escaping () -> Void = {},
        onRewrite: @escaping () -> Void = {},
        onReplace: @escaping () -> Void = {},
        onSplit: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        onOpenScenes: @escaping () -> Void = {}
    ) {
        self.tile = tile
        self.isSelected = isSelected
        self.showsMoveControls = showsMoveControls
        self.canMoveEarlier = canMoveEarlier
        self.canMoveLater = canMoveLater
        self.onSelect = onSelect
        self.onOpenInspector = onOpenInspector
        self.onMoveEarlier = onMoveEarlier
        self.onMoveLater = onMoveLater
        self.onMoveToStart = onMoveToStart
        self.onMoveToEnd = onMoveToEnd
        self.onRewrite = onRewrite
        self.onReplace = onReplace
        self.onSplit = onSplit
        self.onDelete = onDelete
        self.onOpenScenes = onOpenScenes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(String(format: "%02d", tile.order))
                    .font(CanonType.archive(11, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
                Spacer(minLength: 0)
                if tile.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(CanonColor.olive)
                }
            }
            Text(tile.title.isEmpty ? tile.visualCaption : tile.title)
                .font(CanonType.editorial(14, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .lineLimit(2)
            Text(tile.storyFunction.isEmpty ? tile.visualCaption : tile.storyFunction)
                .font(CanonType.interface(10, weight: .medium))
                .foregroundStyle(CanonColor.ink.opacity(0.68))
                .lineLimit(2)
            Text(tile.emotionalState.isEmpty ? tile.meaningMove : tile.emotionalState)
                .font(CanonType.interface(10, weight: .medium))
                .foregroundStyle(CanonColor.ink.opacity(0.58))
                .lineLimit(2)
            Spacer(minLength: 0)
            if showsMoveControls {
                HStack {
                    sequenceMoveButton(
                        systemImage: "chevron.left",
                        isEnabled: canMoveEarlier,
                        help: "Move beat earlier",
                        action: onMoveEarlier
                    )
                    Spacer(minLength: 0)
                    sequenceMoveButton(
                        systemImage: "chevron.right",
                        isEnabled: canMoveLater,
                        help: "Move beat later",
                        action: onMoveLater
                    )
                }
            }
        }
        .padding(10)
        .frame(width: 142, height: 142, alignment: .topLeading)
        .background(CanonColor.paperInset.opacity(isSelected ? 0.95 : 0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? CanonColor.brass.opacity(0.9) : CanonColor.hairlinePaper, lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
        .onTapGesture(count: 2, perform: onOpenInspector)
        .contextMenu {
            Button("Open Beat Inspector", action: onOpenInspector)
            Divider()
            Button("Move Earlier", action: onMoveEarlier)
            Button("Move Later", action: onMoveLater)
            Button("Move to Start", action: onMoveToStart)
            Button("Move to End", action: onMoveToEnd)
            Divider()
            Button("Rewrite", action: onRewrite)
            Button("Replace with Alternatives", action: onReplace)
            Button("Split", action: onSplit)
            Button("Delete", role: .destructive, action: onDelete)
            Divider()
            Button("Open in Scenes", action: onOpenScenes)
            Button("Prepare Scene Layers", action: onOpenScenes)
        }
    }

    private func sequenceMoveButton(
        systemImage: String,
        isEnabled: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 22)
                .foregroundStyle(isEnabled ? CanonColor.brass : CanonColor.muted.opacity(0.42))
                .background(CanonColor.paper.opacity(isEnabled ? 0.58 : 0.24), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(CanonColor.hairlinePaper.opacity(isEnabled ? 0.78 : 0.24))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
    }
}

private struct StoryBeatBoardCardView: View {
    let beat: StoryBeatBoardBeat
    let isSelected: Bool
    let operationState: StoryBeatOperationState?
    let alternativeCount: Int
    let onSelect: () -> Void
    let onToggleLock: (Bool) -> Void
    let onRewrite: (String) -> Void
    let onReplace: () -> Void
    let onSplit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    init(
        beat: StoryBeatBoardBeat,
        isSelected: Bool = false,
        operationState: StoryBeatOperationState? = nil,
        alternativeCount: Int = 0,
        onSelect: @escaping () -> Void = {},
        onToggleLock: @escaping (Bool) -> Void,
        onRewrite: @escaping (String) -> Void = { _ in },
        onReplace: @escaping () -> Void = {},
        onSplit: @escaping () -> Void = {},
        onDuplicate: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {}
    ) {
        self.beat = beat
        self.isSelected = isSelected
        self.operationState = operationState
        self.alternativeCount = alternativeCount
        self.onSelect = onSelect
        self.onToggleLock = onToggleLock
        self.onRewrite = onRewrite
        self.onReplace = onReplace
        self.onSplit = onSplit
        self.onDuplicate = onDuplicate
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%02d", beat.order))
                    .font(CanonType.archive(12, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
                Text(beat.title)
                    .font(CanonType.editorial(21, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button {
                    onToggleLock(!beat.locked)
                } label: {
                    Image(systemName: beat.locked ? "lock.fill" : "lock.open")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help(beat.locked ? "Unlock beat" : "Lock beat")
            }

            StoryBeatField(title: "Event", value: beat.event, isLight: true)
            StoryBeatField(title: "Visual Moment", value: beat.visualMoment, isLight: true)
            StoryBeatField(title: "Turn", value: beat.emotionalTurn, isLight: true)
            StoryBeatField(title: "Prompt Line", value: beat.promptReadyLine, isLight: true)

            HStack(spacing: 6) {
                StoryMiniChip(beat.origin.label)
                StoryMiniChip(beat.supportStatus.label)
            }

            if !beat.aestheticPresentationBinding.isEmpty {
                Text(beat.aestheticPresentationBinding.prefix(4).joined(separator: " · "))
                    .font(CanonType.archive(10, weight: .medium))
                    .foregroundStyle(CanonColor.brass)
                    .lineLimit(2)
            }

            if !beat.validationWarnings.isEmpty {
                Text(beat.validationWarnings.joined(separator: " · "))
                    .font(CanonType.interface(10, weight: .medium))
                    .foregroundStyle(CanonColor.rust)
                    .lineLimit(2)
            }

            if let operationState, operationState.isRunning || operationState.phase == .failed {
                HStack(spacing: 7) {
                    if operationState.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(operationState.phase.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(CanonType.interface(9, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(operationState.phase == .failed ? CanonColor.rust : CanonColor.brass)
                    if !operationState.errorMessage.isEmpty {
                        Text(operationState.errorMessage)
                            .font(CanonType.interface(10))
                            .foregroundStyle(CanonColor.rust)
                            .lineLimit(1)
                    }
                }
            }

            if alternativeCount > 0 {
                Text("\(alternativeCount) alternative\(alternativeCount == 1 ? "" : "s") ready in inspector")
                    .font(CanonType.interface(10, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    beatActionButton("Edit", systemImage: "pencil", disabled: false, action: onSelect)
                    beatActionButton("Rewrite", systemImage: "sparkles", disabled: beat.locked) {
                        onRewrite("Rewrite this beat to be sharper, more visual, and sequence-aware.")
                    }
                    beatActionButton("Replace", systemImage: "rectangle.3.group", disabled: beat.locked, action: onReplace)
                }
                HStack(spacing: 6) {
                    beatActionButton("More visual", systemImage: "eye", disabled: beat.locked) {
                        onRewrite("Make this beat more visual and concrete without breaking board continuity.")
                    }
                    beatActionButton("Stranger", systemImage: "wand.and.stars", disabled: beat.locked) {
                        onRewrite("Make this beat stranger while preserving the story facts and locked beats.")
                    }
                    beatActionButton("Cinematic", systemImage: "camera", disabled: beat.locked) {
                        onRewrite("Make this beat more cinematic and production-ready.")
                    }
                }
                HStack(spacing: 6) {
                    beatActionButton("Split", systemImage: "square.split.2x1", disabled: beat.locked, action: onSplit)
                    beatActionButton("Duplicate", systemImage: "plus.square.on.square", disabled: false, action: onDuplicate)
                    beatActionButton("Delete", systemImage: "trash", disabled: beat.locked, action: onDelete)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 310, alignment: .topLeading)
        .background(CanonColor.paperInset.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? CanonColor.brass.opacity(0.9) : (beat.locked ? CanonColor.olive.opacity(0.7) : CanonColor.hairlinePaper), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
    }

    private func beatActionButton(_ title: String, systemImage: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(CanonType.interface(10, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(CanonUtilityButtonStyle())
        .disabled(disabled)
    }
}

private struct BeatInspectorView: View {
    @ObservedObject var library: LibraryEngine
    let beat: StoryBeatBoardBeat?
    let alternatives: [StoryBeatBoardBeat]
    let onSelectAlternative: (Int) -> Void
    let onInsertAlternative: (Int) -> Void
    let onBranchAlternative: (Int) -> Void
    @State private var draft = BeatInspectorDraft()
    @State private var loadedBeatId = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Beat Inspector")
                    .font(CanonType.editorial(22, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Spacer(minLength: 0)
                if let beat {
                    StoryMiniChip(beat.locked ? "Locked" : "Editable")
                }
            }

            if let beat {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let state = library.storyBeatOperationStatesByBeatId[beat.beatId] {
                            BeatOperationStatusView(state: state) {
                                library.cancelStoryBeatOperation(beatId: beat.beatId)
                            } onRetry: {
                                Task {
                                    await library.rewriteStoryBeat(beatId: beat.beatId, intent: "Retry the previous beat edit while preserving board continuity.")
                                }
                            }
                        }

                        inspectorTextField("Title", text: $draft.title, disabled: beat.locked)
                        inspectorTextField("Story function", text: $draft.storyFunction, disabled: beat.locked)
                        inspectorTextArea("Event", text: $draft.event, minHeight: 62, disabled: beat.locked)
                        inspectorTextArea("Visual moment", text: $draft.visualMoment, minHeight: 72, disabled: beat.locked)
                        inspectorTextArea("Emotional turn", text: $draft.emotionalTurn, minHeight: 52, disabled: beat.locked)
                        inspectorTextArea("Meaning move", text: $draft.meaningMove, minHeight: 62, disabled: beat.locked)
                        inspectorTextArea("Prompt-ready line", text: $draft.promptReadyLine, minHeight: 82, disabled: beat.locked)
                        inspectorTextArea("Voice/text overlay", text: $draft.voiceOrTextOverlay, minHeight: 48, disabled: beat.locked)

                        DisclosureGroup("Aesthetic Bindings") {
                            VStack(alignment: .leading, spacing: 9) {
                                inspectorTextArea("Story cues", text: $draft.aestheticNarrativeBindingText, minHeight: 58, disabled: beat.locked)
                                inspectorTextArea("Presentation cues", text: $draft.aestheticPresentationBindingText, minHeight: 58, disabled: beat.locked)
                            }
                            .padding(.top, 6)
                        }

                        DisclosureGroup("Generation Brief") {
                            VStack(alignment: .leading, spacing: 9) {
                                inspectorTextField("Subject", text: $draft.subject, disabled: beat.locked)
                                inspectorTextField("Setting", text: $draft.setting, disabled: beat.locked)
                                inspectorTextField("Action", text: $draft.action, disabled: beat.locked)
                                inspectorTextField("Visual focus", text: $draft.visualFocus, disabled: beat.locked)
                                inspectorTextField("Camera/framing", text: $draft.cameraOrFraming, disabled: beat.locked)
                                inspectorTextField("Lighting", text: $draft.lighting, disabled: beat.locked)
                                inspectorTextArea("Aesthetic treatment", text: $draft.aestheticTreatment, minHeight: 58, disabled: beat.locked)
                                inspectorTextArea("Negative constraints", text: $draft.negativeConstraintsText, minHeight: 58, disabled: beat.locked)
                            }
                            .padding(.top, 6)
                        }

                        DisclosureGroup("Risks and Invention") {
                            VStack(alignment: .leading, spacing: 9) {
                                inspectorTextArea("Invented elements", text: $draft.inventedElementsText, minHeight: 54, disabled: beat.locked)
                                inspectorTextArea("Risks", text: $draft.risksText, minHeight: 54, disabled: beat.locked)
                            }
                            .padding(.top, 6)
                        }

                        BeatMediaAnchorPicker(library: library, beat: beat)

                        if !alternatives.isEmpty {
                            BeatAlternativesPanel(
                                alternatives: alternatives,
                                onApply: onSelectAlternative,
                                onInsert: onInsertAlternative,
                                onBranch: onBranchAlternative
                            )
                        }
                    }
                    .padding(.trailing, 4)
                }

                HStack(spacing: 8) {
                    Button {
                        sync(from: beat)
                    } label: {
                        Label("Revert", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(CanonUtilityButtonStyle())
                    .disabled(beat.locked)

                    Spacer(minLength: 0)

                    Button {
                        var updated = beat
                        draft.apply(to: &updated)
                        library.updateStoryBeat(updated)
                    } label: {
                        Label("Save Beat", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(CanonPrimaryButtonStyle())
                    .disabled(beat.locked)
                }
            } else {
                StoryEmptyPanel(
                    title: "No beat selected",
                    subtitle: "Select a Sequence Strip tile or Beat Card.",
                    isLight: true
                )
            }
        }
        .padding(14)
        .background(CanonColor.paperInset.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
        .onAppear {
            if let beat {
                sync(from: beat)
            }
        }
        .onChange(of: beat?.beatId ?? "") { _, _ in
            if let beat {
                sync(from: beat)
            } else {
                draft = BeatInspectorDraft()
                loadedBeatId = ""
            }
        }
        .onChange(of: beat) { _, value in
            guard let value, value.beatId == loadedBeatId else { return }
            sync(from: value)
        }
    }

    private func sync(from beat: StoryBeatBoardBeat) {
        loadedBeatId = beat.beatId
        draft = BeatInspectorDraft(beat: beat)
    }

    private func inspectorTextField(_ title: String, text: Binding<String>, disabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            StoryDraftFieldLabel(title)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .disabled(disabled)
        }
    }

    private func inspectorTextArea(_ title: String, text: Binding<String>, minHeight: CGFloat, disabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            StoryDraftFieldLabel(title)
            TextEditor(text: text)
                .font(CanonType.editorial(13))
                .foregroundStyle(CanonColor.ink)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .background(CanonColor.paper.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
                .disabled(disabled)
        }
    }
}

private struct BeatInspectorDraft: Equatable {
    var title = ""
    var storyFunction = ""
    var event = ""
    var visualMoment = ""
    var emotionalTurn = ""
    var meaningMove = ""
    var promptReadyLine = ""
    var voiceOrTextOverlay = ""
    var aestheticNarrativeBindingText = ""
    var aestheticPresentationBindingText = ""
    var inventedElementsText = ""
    var risksText = ""
    var subject = ""
    var setting = ""
    var action = ""
    var visualFocus = ""
    var cameraOrFraming = ""
    var lighting = ""
    var aestheticTreatment = ""
    var negativeConstraintsText = ""

    init() {}

    init(beat: StoryBeatBoardBeat) {
        title = beat.title
        storyFunction = beat.storyFunction
        event = beat.event
        visualMoment = beat.visualMoment
        emotionalTurn = beat.emotionalTurn
        meaningMove = beat.meaningMove
        promptReadyLine = beat.promptReadyLine
        voiceOrTextOverlay = beat.voiceOrTextOverlay
        aestheticNarrativeBindingText = beat.aestheticNarrativeBinding.joined(separator: "\n")
        aestheticPresentationBindingText = beat.aestheticPresentationBinding.joined(separator: "\n")
        inventedElementsText = beat.inventedElements.joined(separator: "\n")
        risksText = beat.risks.joined(separator: "\n")
        subject = beat.generationBrief.subject
        setting = beat.generationBrief.setting
        action = beat.generationBrief.action
        visualFocus = beat.generationBrief.visualFocus
        cameraOrFraming = beat.generationBrief.cameraOrFraming
        lighting = beat.generationBrief.lighting
        aestheticTreatment = beat.generationBrief.aestheticTreatment
        negativeConstraintsText = beat.generationBrief.negativeConstraints.joined(separator: "\n")
    }

    func apply(to beat: inout StoryBeatBoardBeat) {
        beat.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.storyFunction = storyFunction.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.event = event.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.visualMoment = visualMoment.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.emotionalTurn = emotionalTurn.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.meaningMove = meaningMove.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.promptReadyLine = promptReadyLine.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.voiceOrTextOverlay = voiceOrTextOverlay.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.aestheticNarrativeBinding = inspectorList(aestheticNarrativeBindingText)
        beat.aestheticPresentationBinding = inspectorList(aestheticPresentationBindingText)
        beat.inventedElements = inspectorList(inventedElementsText)
        beat.risks = inspectorList(risksText)
        beat.generationBrief.subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.generationBrief.setting = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.generationBrief.action = action.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.generationBrief.visualFocus = visualFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.generationBrief.cameraOrFraming = cameraOrFraming.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.generationBrief.lighting = lighting.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.generationBrief.aestheticTreatment = aestheticTreatment.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.generationBrief.textOverlay = voiceOrTextOverlay.trimmingCharacters(in: .whitespacesAndNewlines)
        beat.generationBrief.negativeConstraints = inspectorList(negativeConstraintsText)
    }
}

private struct BeatOperationStatusView: View {
    let state: StoryBeatOperationState
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if state.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(state.phase.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(CanonType.interface(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(state.phase == .failed ? CanonColor.rust : CanonColor.brass)
                Spacer(minLength: 0)
                if state.isRunning {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(CanonUtilityButtonStyle())
                } else if state.phase == .failed {
                    Button("Retry", action: onRetry)
                        .buttonStyle(CanonUtilityButtonStyle())
                }
            }
            if !state.errorMessage.isEmpty {
                Text(state.errorMessage)
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.rust)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(CanonColor.brass.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.brass.opacity(0.44)))
    }
}

private struct BeatMediaAnchorPicker: View {
    @ObservedObject var library: LibraryEngine
    let beat: StoryBeatBoardBeat

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StoryDraftFieldLabel("Source Media Anchors")
                Spacer(minLength: 0)
                StoryMiniChip("\(beat.mediaAnchors.count) anchor\(beat.mediaAnchors.count == 1 ? "" : "s")")
            }

            if library.currentStoryScopeItems.isEmpty {
                Text("No enabled media is available for anchoring.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.ink.opacity(0.58))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(library.currentStoryScopeItems.prefix(18)) { item in
                            BeatMediaAnchorCard(
                                item: item,
                                beat: beat,
                                onToggle: { role, enabled in
                                    library.setStoryBeatMediaAnchor(
                                        beatId: beat.beatId,
                                        mediaId: item.mediaId,
                                        role: role,
                                        enabled: enabled
                                    )
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(10)
        .background(CanonColor.paper.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
    }
}

private struct BeatMediaAnchorCard: View {
    let item: MediaItemRecord
    let beat: StoryBeatBoardBeat
    let onToggle: (StoryMediaAnchorRole, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ThumbnailImage(path: item.thumbnailPath, kind: item.kind)
                .frame(width: 112, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper))
            Text(item.filename)
                .font(CanonType.interface(10, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .lineLimit(2)
                .frame(width: 112, alignment: .leading)
            HStack(spacing: 4) {
                anchorRoleButton(.source)
                anchorRoleButton(.reference)
                anchorRoleButton(.avoid)
            }
        }
        .padding(8)
        .frame(width: 128, alignment: .topLeading)
        .background(CanonColor.paperInset.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.8)))
    }

    private func anchorRoleButton(_ role: StoryMediaAnchorRole) -> some View {
        let selected = beat.mediaAnchors.contains { $0.mediaId == item.mediaId && $0.role == role }
        return Button {
            onToggle(role, !selected)
        } label: {
            Text(roleShortLabel(role))
                .font(CanonType.interface(9, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(selected ? anchorColor(role).opacity(0.30) : CanonColor.paper.opacity(0.78), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? anchorColor(role).opacity(0.78) : CanonColor.hairlinePaper))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? CanonColor.ink : CanonColor.ink.opacity(0.62))
        .help(role.label)
    }

    private func roleShortLabel(_ role: StoryMediaAnchorRole) -> String {
        switch role {
        case .source: "Use"
        case .reference: "Ref"
        case .avoid: "Avoid"
        }
    }

    private func anchorColor(_ role: StoryMediaAnchorRole) -> Color {
        switch role {
        case .source: CanonColor.olive
        case .reference: CanonColor.brass
        case .avoid: CanonColor.rust
        }
    }
}

private struct BeatAlternativesPanel: View {
    let alternatives: [StoryBeatBoardBeat]
    let onApply: (Int) -> Void
    let onInsert: (Int) -> Void
    let onBranch: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            StoryDraftFieldLabel("Replacement Alternatives")
            ForEach(Array(alternatives.enumerated()), id: \.offset) { index, alternative in
                VStack(alignment: .leading, spacing: 7) {
                    Text(alternative.title)
                        .font(CanonType.editorial(15, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(2)
                    Text(alternative.visualMoment)
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.ink.opacity(0.64))
                        .lineLimit(3)
                    HStack(spacing: 6) {
                        Button("Apply") {
                            onApply(index)
                        }
                        .buttonStyle(CanonUtilityButtonStyle())
                        Button("Insert") {
                            onInsert(index)
                        }
                        .buttonStyle(CanonUtilityButtonStyle())
                        Button("Branch") {
                            onBranch(index)
                        }
                        .buttonStyle(CanonUtilityButtonStyle())
                    }
                }
                .padding(9)
                .background(CanonColor.paper.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
            }
        }
    }
}

private func inspectorList(_ value: String) -> [String] {
    var seen: Set<String> = []
    var result: [String] = []
    for raw in value.split(whereSeparator: { character in
        character == "\n" || character == "," || character == ";"
    }) {
        let item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.isEmpty else { continue }
        let key = item.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        result.append(item)
    }
    return result
}

private struct SceneStoryActiveLoadingRing: View {
    @State private var isRotating = false

    var body: some View {
        Circle()
            .trim(from: 0.16, to: 0.84)
            .stroke(CanonColor.brass, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(isRotating ? 270 : -90))
            .frame(width: 13, height: 13)
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: isRotating)
            .onAppear {
                isRotating = true
            }
            .onDisappear {
                isRotating = false
            }
    }
}

private struct StoryMiniChip: View {
    let text: String
    let tone: StoryMiniChipTone

    init(_ text: String, tone: StoryMiniChipTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(CanonType.interface(9, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(tone.foreground)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tone.background, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(tone.stroke)
            )
    }
}

private enum StoryMiniChipTone {
    case neutral
    case active
    case kept
    case warning
    case muted

    var foreground: Color {
        switch self {
        case .neutral: return CanonColor.ink.opacity(0.72)
        case .active: return CanonColor.brass
        case .kept: return CanonColor.olive
        case .warning: return CanonColor.rust
        case .muted: return CanonColor.ink.opacity(0.52)
        }
    }

    var background: Color {
        switch self {
        case .neutral: return CanonColor.paper.opacity(0.75)
        case .active: return CanonColor.brass.opacity(0.12)
        case .kept: return CanonColor.olive.opacity(0.12)
        case .warning: return CanonColor.rust.opacity(0.12)
        case .muted: return CanonColor.paper.opacity(0.58)
        }
    }

    var stroke: Color {
        switch self {
        case .neutral: return CanonColor.hairlinePaper
        case .active: return CanonColor.brass.opacity(0.52)
        case .kept: return CanonColor.olive.opacity(0.50)
        case .warning: return CanonColor.rust.opacity(0.50)
        case .muted: return CanonColor.hairlinePaper.opacity(0.72)
        }
    }
}

private struct BeatProductionCard: View {
    let beat: SceneStoryBeat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("BEAT \(max(beat.order, 1))")
                    .font(CanonType.interface(11, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(CanonColor.brass)
                Text(beat.beatDescription.trimmed.isEmpty ? "Shot beat" : beat.beatDescription)
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 130), alignment: .topLeading),
                    GridItem(.flexible(minimum: 130), alignment: .topLeading)
                ],
                alignment: .leading,
                spacing: 8
            ) {
                beatField("Meaning proof", beat.meaningProof)
                beatListField("Observable proof", beat.emotionalTurn.observableEvidence)
                beatField("Action", beat.action)
                beatField("Camera", beat.camera)
                beatField("Lighting", beat.lighting)
                beatListField("Continuity", [beat.continuityIn, beat.continuityOut])
                beatListField("Performance", beat.emotionalTurn.performanceDirection)
                beatListField("Avoid", beat.emotionalTurn.avoidEmotionalCliches)
            }

            if !beat.promptSeed.trimmed.isEmpty {
                Text(beat.promptSeed)
                    .font(CanonType.archive(10, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.68))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CanonColor.paper.opacity(0.54), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper.opacity(0.70)))
            }

        }
        .padding(11)
        .background(Color.white.opacity(0.20))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(CanonColor.hairlinePaper.opacity(0.72))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func beatField(_ label: String, _ value: String) -> some View {
        if !value.trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(CanonType.interface(9, weight: .semibold))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(CanonColor.brass)
                Text(value)
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.ink.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func beatListField(_ label: String, _ values: [String]) -> some View {
        let cleaned = uniqueNonEmpty(values, limit: 5)
        if !cleaned.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(CanonType.interface(9, weight: .semibold))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(CanonColor.brass)
                ForEach(cleaned, id: \.self) { value in
                    HStack(alignment: .top, spacing: 5) {
                        Text("•")
                            .font(CanonType.interface(10, weight: .semibold))
                            .foregroundStyle(CanonColor.brass.opacity(0.70))
                        Text(value)
                            .font(CanonType.interface(11))
                            .foregroundStyle(CanonColor.ink.opacity(0.68))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct StoryAdaptiveGridLayout: Layout {
    let minimumItemWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let width = resolvedWidth(for: proposal, subviews: subviews)
        let metrics = gridMetrics(for: width)
        let itemProposal = ProposedViewSize(width: metrics.itemWidth, height: nil)
        var height: CGFloat = 0
        var rowStart = 0

        while rowStart < subviews.count {
            if rowStart > 0 {
                height += spacing
            }
            height += rowHeight(
                rowStart: rowStart,
                columnCount: metrics.columnCount,
                subviews: subviews,
                proposal: itemProposal
            )
            rowStart += metrics.columnCount
        }

        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let metrics = gridMetrics(for: bounds.width)
        let itemProposal = ProposedViewSize(width: metrics.itemWidth, height: nil)
        var y = bounds.minY
        var rowStart = 0

        while rowStart < subviews.count {
            let rowHeight = rowHeight(
                rowStart: rowStart,
                columnCount: metrics.columnCount,
                subviews: subviews,
                proposal: itemProposal
            )
            let rowEnd = min(rowStart + metrics.columnCount, subviews.count)

            for index in rowStart..<rowEnd {
                let column = index - rowStart
                let x = bounds.minX + CGFloat(column) * (metrics.itemWidth + spacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: itemProposal
                )
            }

            y += rowHeight + spacing
            rowStart += metrics.columnCount
        }
    }

    private func resolvedWidth(for proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width, width.isFinite {
            return max(width, minimumItemWidth)
        }

        let widestSubview = subviews
            .map { $0.sizeThatFits(.unspecified).width }
            .max() ?? minimumItemWidth
        return max(widestSubview, minimumItemWidth)
    }

    private func gridMetrics(for width: CGFloat) -> (columnCount: Int, itemWidth: CGFloat) {
        let columnCount = max(1, Int((width + spacing) / (minimumItemWidth + spacing)))
        let totalSpacing = CGFloat(columnCount - 1) * spacing
        let itemWidth = max(1, floor((width - totalSpacing) / CGFloat(columnCount)))
        return (columnCount, itemWidth)
    }

    private func rowHeight(
        rowStart: Int,
        columnCount: Int,
        subviews: Subviews,
        proposal: ProposedViewSize
    ) -> CGFloat {
        let rowEnd = min(rowStart + columnCount, subviews.count)
        var height: CGFloat = 0
        for index in rowStart..<rowEnd {
            height = max(height, subviews[index].sizeThatFits(proposal).height)
        }
        return height
    }
}

private struct StoryGateView: View {
    let onOpenAesthetic: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: "seal")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(CanonColor.brass)
            VStack(spacing: 6) {
                    Text("Plan Frames first.")
                    .font(CanonType.editorial(28, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                Text("SCENES needs planned Frames before it can generate Storylines or beats.")
                    .font(CanonType.editorial(15))
                    .foregroundStyle(CanonColor.ink.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }
            Button {
                onOpenAesthetic()
            } label: {
                Label("Open Frames", systemImage: "arrow.left")
            }
            .buttonStyle(CanonSecondaryButtonStyle())
            Spacer(minLength: 0)
        }
        .padding(32)
    }
}

private struct StoryProgressPill: View {
    @ObservedObject var library: LibraryEngine

    var body: some View {
        HStack(spacing: 8) {
            storyDot(isComplete: !library.readyLenses.isEmpty, label: "Scenes")
            storyDot(isComplete: true, label: "Setup")
            storyDot(isComplete: library.hasCurrentStoryDirections, label: "Storylines")
            storyDot(isComplete: library.hasCurrentStorySignals, label: "Signals")
            storyDot(isComplete: library.hasCurrentStoryBeats, label: "Board")
            storyDot(isComplete: library.hasAcceptedProjectStory, label: "Accepted")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(CanonColor.paperInset.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper)
        )
    }

    private func storyDot(isComplete: Bool, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isComplete ? CanonColor.olive : CanonColor.hairlinePaper)
                .frame(width: 6, height: 6)
            Text(label)
                .font(CanonType.interface(11, weight: .semibold))
                .foregroundStyle(isComplete ? CanonColor.ink.opacity(0.82) : CanonColor.ink.opacity(0.54))
        }
    }
}

private struct StorySectionHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(eyebrow)
                    .font(CanonType.archive(11, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                    .frame(width: 21, height: 21)
                    .background(CanonColor.brass, in: Circle())
                Text(title)
                    .font(CanonType.editorial(23, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
            }
            Text(subtitle)
                .font(CanonType.interface(12))
                .foregroundStyle(CanonColor.ink.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StoryAudioDirectionPanel: View {
    @ObservedObject var library: LibraryEngine
    @State private var direction = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Audio Direction", systemImage: "slider.horizontal.3")
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Spacer(minLength: 0)
                Text(direction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "DEFAULT" : "CUSTOM")
                    .font(CanonType.interface(9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(direction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? CanonColor.muted : CanonColor.brass)
            }

            ZStack(alignment: .topLeading) {
                if direction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Example: drier, stranger, more urgent; make the speech feel like a hard cut from the archive.")
                        .font(CanonType.editorial(14))
                        .foregroundStyle(CanonColor.muted.opacity(0.68))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $direction)
                    .font(CanonType.editorial(14))
                    .frame(minHeight: 68, maxHeight: 92)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(CanonColor.bone)
                    .background(CanonColor.sidebar.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(CanonColor.hairlineDark)
                    )
                    .onChange(of: direction) { _, value in
                        library.setStoryAudioDirection(value)
                    }
            }
        }
        .padding(12)
        .background(CanonColor.mediaCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlineDark)
        )
        .onAppear(perform: syncFromLibrary)
        .onChange(of: library.currentProject?.projectId ?? "") { _, _ in
            syncFromLibrary()
        }
        .onChange(of: library.storyAudioDirection) { _, value in
            if value != direction {
                direction = value
            }
        }
    }

    private func syncFromLibrary() {
        direction = library.storyAudioDirection
    }
}

private struct StoryAudioVoiceSettingsPanel: View {
    @Binding var selectedPresetId: String
    @Binding var voiceSpeed: Double
    let customVoiceId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StoryDraftFieldLabel("Voice")
                Spacer(minLength: 0)
                Text("\(StoryAudioVoiceCatalog.speedLabel(for: voiceSpeed)) \(String(format: "%.2fx", StoryAudioVoiceCatalog.clampedSpeed(voiceSpeed)))")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
            }

            HStack(spacing: 8) {
                ForEach(StoryAudioVoiceCatalog.voiceOptions(customVoiceId: customVoiceId)) { option in
                    Button {
                        selectedPresetId = option.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: iconName(for: option))
                                .font(.system(size: 12, weight: .semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.name)
                                    .font(CanonType.interface(12, weight: .semibold))
                                Text(option.hasVoiceId ? option.descriptor : "\(option.descriptor) missing id")
                                    .font(CanonType.interface(10))
                            }
                        }
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(option.id == selectedPresetId ? CanonColor.brass : CanonColor.sidebar)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(option.id == selectedPresetId ? CanonColor.softGold : CanonColor.hairlineDark)
                        )
                        .foregroundStyle(option.id == selectedPresetId ? CanonColor.ink : (option.hasVoiceId ? CanonColor.bone : CanonColor.rust))
                    }
                    .buttonStyle(.plain)
                    .help("\(option.name): \(option.descriptor)")
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    ForEach(StoryAudioVoiceCatalog.speedPresets) { preset in
                        Button {
                            voiceSpeed = preset.speed
                        } label: {
                            Text(preset.label)
                                .font(CanonType.interface(10, weight: .semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(isSelected(preset) ? CanonColor.brass : CanonColor.sidebar)
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected(preset) ? CanonColor.softGold : CanonColor.hairlineDark)
                                )
                                .foregroundStyle(isSelected(preset) ? CanonColor.ink : CanonColor.muted)
                        }
                        .buttonStyle(.plain)
                        .help("\(preset.label) \(String(format: "%.2fx", preset.speed))")
                    }
                }

                Slider(
                    value: Binding(
                        get: { StoryAudioVoiceCatalog.clampedSpeed(voiceSpeed) },
                        set: { voiceSpeed = StoryAudioVoiceCatalog.clampedSpeed($0) }
                    ),
                    in: StoryAudioVoiceCatalog.speedRange,
                    step: 0.02
                )
                .controlSize(.small)
            }
        }
    }

    private func isSelected(_ preset: StoryAudioSpeedPreset) -> Bool {
        abs(StoryAudioVoiceCatalog.clampedSpeed(voiceSpeed) - preset.speed) <= 0.025
    }

    private func iconName(for option: StoryAudioVoiceOption) -> String {
        switch option.id {
        case StoryAudioVoiceCatalog.lucerPresetId:
            return "person.wave.2"
        case StoryAudioVoiceCatalog.customPresetId:
            return "person.crop.circle"
        default:
            return "person.crop.circle.badge.checkmark"
        }
    }
}

private struct StoryAudioDraftEditor: View {
    @ObservedObject var library: LibraryEngine
    let canGenerateAudio: Bool
    let generationBlocker: String
    @State private var loadedTrackId = ""
    @State private var isSyncing = false
    @State private var title = ""
    @State private var voicePresetId = StoryAudioVoiceCatalog.customPresetId
    @State private var voiceSpeed = StoryAudioVoiceCatalog.defaultSpeed
    @State private var voiceText = ""
    @State private var beatPrompt = ""
    @State private var mixNotes = ""
    @State private var tagsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Draft Audio Copy")
                        .font(CanonType.editorial(22, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                    Text(metadataLine)
                        .font(CanonType.archive(10, weight: .medium))
                        .foregroundStyle(CanonColor.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(library.storyAudioTrack.status.uppercased())
                    .font(CanonType.interface(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(library.storyAudioTrack.status == "failed" ? CanonColor.rust : CanonColor.brass)
            }

            if library.storyAudioTrack.status == "failed" {
                Text(library.storyAudioTrack.errorMessage.isEmpty ? "Audio generation failed." : library.storyAudioTrack.errorMessage)
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.rust)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StoryAudioVoiceSettingsPanel(
                selectedPresetId: $voicePresetId,
                voiceSpeed: $voiceSpeed,
                customVoiceId: ElevenLabsSettingsStore.resolvedCustomVoiceId()
            )
            .onChange(of: voicePresetId) { _, _ in
                commitVoiceSettings()
            }
            .onChange(of: voiceSpeed) { _, _ in
                commitVoiceSettings()
            }

            VStack(alignment: .leading, spacing: 4) {
                StoryDraftFieldLabel("Title")
                TextField("Punchy Audio Track", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: title) { _, _ in
                        commitDraft()
                    }
            }

            StoryAudioDraftTextArea(
                title: "Speech Text",
                placeholder: "One spoken phrase for the voice track.",
                minHeight: 58,
                text: $voiceText,
                onChange: commitDraft
            )

            StoryAudioDraftTextArea(
                title: "Beat Prompt",
                placeholder: "A direct non-vocal ElevenLabs sound-generation prompt.",
                minHeight: 92,
                text: $beatPrompt,
                onChange: commitDraft
            )

            StoryAudioDraftTextArea(
                title: "Mix Notes",
                placeholder: "Short local mix notes.",
                minHeight: 58,
                text: $mixNotes,
                onChange: commitDraft
            )

            VStack(alignment: .leading, spacing: 4) {
                StoryDraftFieldLabel("Tags")
                TextField("tag-one, tag-two", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: tagsText) { _, _ in
                        commitDraft()
                    }
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button {
                    commitDraft()
                    Task {
                        await library.generateStoryAudioTrack()
                    }
                } label: {
                    Label(
                        library.isGeneratingStoryAudioTrack ? "Generating Audio" : "Generate Audio",
                        systemImage: "waveform"
                    )
                }
                .buttonStyle(CanonPrimaryButtonStyle())
                .disabled(
                    library.isGeneratingStoryAudioTrack
                        || library.isDraftingStoryAudioTrack
                        || library.isRemixingStoryAudioTrack
                        || !canGenerateAudio
                        || !hasMinimumDraft
                )
                .help("Calls ElevenLabs TTS and Sound Generation, then mixes the local track.")
            }
            if !generationBlocker.isEmpty {
                Text(generationBlocker)
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.rust)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.brass.opacity(0.45))
        )
        .onAppear(perform: syncFromTrack)
        .onChange(of: library.storyAudioTrack.trackId) { _, _ in
            syncFromTrack()
        }
    }

    private var hasMinimumDraft: Bool {
        !voiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !beatPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var metadataLine: String {
        var parts = [
            "\(Int(library.storyAudioTrack.durationSeconds.rounded()))s",
            library.storyAudioTrack.voiceDisplayName,
            "\(library.storyAudioTrack.voiceSpeedDisplayLabel) \(String(format: "%.2fx", library.storyAudioTrack.effectiveVoiceSpeed))",
            library.storyAudioTrack.outputFormat
        ]
        if let model = library.storyAudioTrack.draftModelId, !model.isEmpty {
            parts.append(model)
        }
        if let direction = library.storyAudioTrack.operatorDirection, !direction.isEmpty {
            parts.append("directed")
        }
        return parts.joined(separator: " · ")
    }

    private func syncFromTrack() {
        let track = library.storyAudioTrack
        isSyncing = true
        loadedTrackId = track.trackId
        title = track.title
        voicePresetId = track.voicePresetId ?? StoryAudioVoiceCatalog.customPresetId
        voiceSpeed = track.effectiveVoiceSpeed
        voiceText = track.voiceText
        beatPrompt = track.beatPrompt
        mixNotes = track.mixNotes
        tagsText = track.tags.joined(separator: ", ")
        isSyncing = false
    }

    private func commitDraft() {
        guard !isSyncing, !loadedTrackId.isEmpty else { return }
        library.updateStoryAudioDraft(
            trackId: loadedTrackId,
            title: title,
            voiceText: voiceText,
            beatPrompt: beatPrompt,
            mixNotes: mixNotes,
            tagsText: tagsText
        )
    }

    private func commitVoiceSettings() {
        guard !isSyncing, !loadedTrackId.isEmpty else { return }
        library.updateStoryAudioVoiceSettings(
            trackId: loadedTrackId,
            presetId: voicePresetId,
            voiceSpeed: voiceSpeed
        )
    }
}

private struct StoryAudioDraftTextArea: View {
    let title: String
    let placeholder: String
    let minHeight: CGFloat
    @Binding var text: String
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StoryDraftFieldLabel(title)
            ZStack(alignment: .topLeading) {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(CanonType.editorial(14))
                        .foregroundStyle(CanonColor.muted.opacity(0.68))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $text)
                    .font(CanonType.editorial(14))
                    .frame(minHeight: minHeight)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(CanonColor.bone)
                    .background(CanonColor.sidebar.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(CanonColor.hairlineDark)
                    )
                    .onChange(of: text) { _, _ in
                        onChange()
                    }
            }
        }
    }
}

private struct StoryDraftFieldLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(CanonType.interface(10, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(CanonColor.muted)
    }
}

private struct StoryAudioPostGenerationSpeedControl: View {
    let track: StoryAudioTrackDocument
    let isRemixing: Bool
    let onCommit: (Double) -> Void
    @State private var draftSpeed = StoryAudioVoiceCatalog.defaultSpeed
    @State private var isEditingSlider = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                StoryDraftFieldLabel("Speed")
                Spacer(minLength: 0)
                if isRemixing {
                    ProgressView()
                        .controlSize(.small)
                }
                Text("\(StoryAudioVoiceCatalog.speedLabel(for: draftSpeed)) \(String(format: "%.2fx", StoryAudioVoiceCatalog.clampedSpeed(draftSpeed)))")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(isRemixing ? CanonColor.brass : CanonColor.muted)
            }

            HStack(spacing: 6) {
                ForEach(StoryAudioVoiceCatalog.speedPresets) { preset in
                    Button {
                        draftSpeed = preset.speed
                        commit(preset.speed)
                    } label: {
                        Text(preset.label)
                            .font(CanonType.interface(10, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(isSelected(preset) ? CanonColor.brass : CanonColor.sidebar)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isSelected(preset) ? CanonColor.softGold : CanonColor.hairlineDark)
                            )
                            .foregroundStyle(isSelected(preset) ? CanonColor.ink : CanonColor.muted)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRemixing)
                    .help("\(preset.label) \(String(format: "%.2fx", preset.speed))")
                }
            }

            Slider(
                value: Binding(
                    get: { StoryAudioVoiceCatalog.clampedSpeed(draftSpeed) },
                    set: { draftSpeed = StoryAudioVoiceCatalog.clampedSpeed($0) }
                ),
                in: StoryAudioVoiceCatalog.speedRange,
                step: 0.02,
                onEditingChanged: { editing in
                    isEditingSlider = editing
                    if !editing {
                        commit(draftSpeed)
                    }
                }
            )
            .controlSize(.small)
            .disabled(isRemixing)
        }
        .onAppear(perform: syncFromTrack)
        .onChange(of: track.trackId) { _, _ in
            syncFromTrack()
        }
        .onChange(of: track.voiceSpeed ?? StoryAudioVoiceCatalog.defaultSpeed) { _, _ in
            if !isEditingSlider {
                syncFromTrack()
            }
        }
    }

    private func isSelected(_ preset: StoryAudioSpeedPreset) -> Bool {
        abs(StoryAudioVoiceCatalog.clampedSpeed(draftSpeed) - preset.speed) <= 0.025
    }

    private func syncFromTrack() {
        draftSpeed = track.effectiveVoiceSpeed
    }

    private func commit(_ speed: Double) {
        let clamped = StoryAudioVoiceCatalog.clampedSpeed(speed)
        guard abs(track.effectiveVoiceSpeed - clamped) > 0.001 else { return }
        onCommit(clamped)
    }
}

private struct StoryAudioBeatBedControl: View {
    let track: StoryAudioTrackDocument
    let isRemixing: Bool
    let onCommit: (Bool) -> Void
    @State private var isBeatEnabled = true

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            StoryDraftFieldLabel("Beat Bed")
            Spacer(minLength: 0)
            if isRemixing {
                ProgressView()
                    .controlSize(.small)
            }
            Text(isBeatEnabled ? "Enabled" : "Muted")
                .font(CanonType.archive(10, weight: .semibold))
                .foregroundStyle(isBeatEnabled ? CanonColor.olive : CanonColor.brass)
            Toggle(
                "",
                isOn: Binding(
                    get: { isBeatEnabled },
                    set: { value in
                        isBeatEnabled = value
                        commit(value)
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(isRemixing)
            .help(isBeatEnabled ? "Disable Beat Bed in the local mix" : "Enable Beat Bed in the local mix")
        }
        .onAppear(perform: syncFromTrack)
        .onChange(of: track.trackId) { _, _ in
            syncFromTrack()
        }
        .onChange(of: track.isBeatEnabled ?? true) { _, _ in
            if !isRemixing {
                syncFromTrack()
            }
        }
    }

    private func syncFromTrack() {
        isBeatEnabled = track.effectiveBeatEnabled
    }

    private func commit(_ enabled: Bool) {
        guard track.effectiveBeatEnabled != enabled else { return }
        onCommit(enabled)
    }
}

private struct StoryAudioMixRepairControl: View {
    let isRepairing: Bool
    let onRepair: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if isRepairing {
                ProgressView()
                    .controlSize(.small)
            }
            Text("Local mix missing")
                .font(CanonType.archive(10, weight: .semibold))
                .foregroundStyle(CanonColor.brass)
            Spacer(minLength: 0)
            Button {
                onRepair()
            } label: {
                Label("Finish Mix", systemImage: "waveform")
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .disabled(isRepairing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CanonColor.sidebar.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(CanonColor.hairlineDark)
        )
    }
}

private struct StoryAudioTrackCard: View {
    let track: StoryAudioTrackDocument
    let isRemixing: Bool
    let onRepairMix: () -> Void
    let onBeatEnabledCommit: (Bool) -> Void
    let onSpeedCommit: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(track.title.isEmpty ? "Punchy Audio Track" : track.title)
                    .font(CanonType.editorial(24, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Spacer(minLength: 0)
                Text(track.status.uppercased())
                    .font(CanonType.interface(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(track.status == "ready" ? CanonColor.olive : CanonColor.brass)
            }

            if let mixPath = playableMixPath {
                StoryAudioPreview(path: mixPath, reloadToken: track.updatedAt)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(CanonColor.hairlineDark)
                    )
            } else if track.canBuildLocalMix {
                StoryAudioMixRepairControl(
                    isRepairing: isRemixing,
                    onRepair: onRepairMix
                )
            }

            StoryBeatField(title: "Voice", value: track.voiceText)
            StoryBeatField(title: "Beat Bed", value: track.beatPrompt)

            if !track.mixNotes.isEmpty {
                StoryBeatField(title: "Mix Notes", value: track.mixNotes)
            }

            if track.status == "ready", playableMixPath != nil {
                StoryAudioPostGenerationSpeedControl(
                    track: track,
                    isRemixing: isRemixing,
                    onCommit: onSpeedCommit
                )
            }

            if track.canBuildLocalMix {
                StoryAudioBeatBedControl(
                    track: track,
                    isRemixing: isRemixing,
                    onCommit: onBeatEnabledCommit
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(metadataLine)
                    .font(CanonType.archive(10, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if let mixPath = playableMixPath {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: mixPath)])
                    } label: {
                        Label("Open in Finder", systemImage: "folder")
                    }
                    .buttonStyle(CanonUtilityButtonStyle())
                    .help("Open audio mix in Finder")
                }
            }

            if !track.tags.isEmpty {
                Text(track.tags.prefix(8).joined(separator: " · "))
                    .font(CanonType.archive(10, weight: .medium))
                    .foregroundStyle(CanonColor.brass)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.brass.opacity(0.45))
        )
    }

    private var playableMixPath: String? {
        guard let path = track.mixAsset?.path.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return path
    }

    private var metadataLine: String {
        var parts = [
            "\(Int(track.durationSeconds.rounded()))s",
            track.voiceDisplayName,
            "\(track.voiceSpeedDisplayLabel) \(String(format: "%.2fx", track.effectiveVoiceSpeed))",
            track.outputFormat,
            track.beatProvider,
            track.voiceProvider
        ]
        if !track.effectiveBeatEnabled {
            parts.append("beat off")
        }
        if let beat = track.beatAsset, !beat.characterCost.isEmpty {
            parts.append("beat cost \(beat.characterCost)")
        }
        if let voice = track.voiceAsset, !voice.characterCount.isEmpty {
            parts.append("voice chars \(voice.characterCount)")
        }
        return parts.joined(separator: " · ")
    }
}

private struct StoryAudioGenerationBrowser: View {
    @ObservedObject var library: LibraryEngine

    private var tracks: [StoryAudioTrackDocument] {
        library.storyAudioTracks.tracks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Generations")
                    .font(CanonType.interface(11, weight: .semibold))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(CanonColor.brass)
                Text("\(tracks.count)")
                    .font(CanonType.archive(11, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
                Spacer(minLength: 0)
                Text("Newest first")
                    .font(CanonType.archive(10, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
            }

            StoryAdaptiveGridLayout(minimumItemWidth: 260, spacing: 12) {
                ForEach(tracks) { track in
                    StoryAudioGenerationCard(
                        track: track,
                        isActive: track.trackId == library.storyAudioTracks.activeTrackId,
                        isRemixing: library.isRemixingStoryAudioTrack,
                        onUse: {
                            library.activateStoryAudioTrack(trackId: track.trackId)
                        },
                        onRepairMix: {
                            Task {
                                await library.repairStoryAudioTrackMix(trackId: track.trackId)
                            }
                        },
                        onBeatEnabledCommit: { isEnabled in
                            Task {
                                await library.setStoryAudioTrackBeatEnabled(
                                    trackId: track.trackId,
                                    isEnabled: isEnabled
                                )
                            }
                        },
                        onSpeedCommit: { speed in
                            Task {
                                await library.remixStoryAudioTrackSpeed(
                                    trackId: track.trackId,
                                    voiceSpeed: speed
                                )
                            }
                        }
                    )
                }
            }
        }
    }
}

private struct StoryAudioGenerationCard: View {
    let track: StoryAudioTrackDocument
    let isActive: Bool
    let isRemixing: Bool
    let onUse: () -> Void
    let onRepairMix: () -> Void
    let onBeatEnabledCommit: (Bool) -> Void
    let onSpeedCommit: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title.isEmpty ? "Untitled Track" : track.title)
                        .font(CanonType.editorial(17, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                        .lineLimit(1)
                    Text(generatedLabel)
                        .font(CanonType.archive(10, weight: .medium))
                        .foregroundStyle(CanonColor.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(statusLabel)
                    .font(CanonType.interface(9, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(statusColor)
            }

            if let mixPath = playableMixPath {
                StoryAudioPreview(path: mixPath, reloadToken: track.updatedAt)
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(CanonColor.hairlineDark)
                    )
            } else if track.canBuildLocalMix {
                StoryAudioMixRepairControl(
                    isRepairing: isRemixing,
                    onRepair: onRepairMix
                )
            } else if !track.errorMessage.isEmpty {
                Text(track.errorMessage)
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.rust)
                    .lineLimit(2)
            }

            StoryAudioPreviewField(title: "Voice", value: track.voiceText)
            StoryAudioPreviewField(title: "Beat", value: track.beatPrompt)

            if track.status == "ready", playableMixPath != nil {
                StoryAudioPostGenerationSpeedControl(
                    track: track,
                    isRemixing: isRemixing,
                    onCommit: onSpeedCommit
                )
            }

            if track.canBuildLocalMix {
                StoryAudioBeatBedControl(
                    track: track,
                    isRemixing: isRemixing,
                    onCommit: onBeatEnabledCommit
                )
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metadataLine)
                    .font(CanonType.archive(10, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    onUse()
                } label: {
                    Label("Use", systemImage: "checkmark.circle")
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .disabled(isActive || playableMixPath == nil)

                if let mixPath = playableMixPath {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: mixPath)])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(CanonUtilityButtonStyle())
                    .help("Open in Finder")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(CanonColor.mediaCard.opacity(isActive ? 1 : 0.78), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? CanonColor.brass.opacity(0.72) : CanonColor.hairlineDark)
        )
    }

    private var playableMixPath: String? {
        guard let path = track.mixAsset?.path.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return path
    }

    private var statusLabel: String {
        let status = track.status.uppercased()
        guard isActive else { return status }
        return track.status == "ready" ? "ACTIVE" : "ACTIVE · \(status)"
    }

    private var generatedLabel: String {
        let source = track.generatedAt.isEmpty ? track.updatedAt : track.generatedAt
        return String(source.prefix(19))
    }

    private var statusColor: Color {
        if isActive, track.status == "ready", playableMixPath != nil {
            return CanonColor.olive
        }
        switch track.status {
        case "ready":
            return CanonColor.olive
        case "failed":
            return CanonColor.rust
        default:
            return CanonColor.brass
        }
    }

    private var metadataLine: String {
        var parts = [
            "\(Int(track.durationSeconds.rounded()))s",
            track.voiceDisplayName,
            "\(track.voiceSpeedDisplayLabel) \(String(format: "%.2fx", track.effectiveVoiceSpeed))",
            track.outputFormat
        ]
        if !track.effectiveBeatEnabled {
            parts.append("beat off")
        }
        return parts.joined(separator: " · ")
    }
}

private struct StoryAudioPreviewField: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(CanonType.interface(9, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(CanonColor.muted)
            Text(value.isEmpty ? "Not specified" : value)
                .font(CanonType.editorial(13))
                .foregroundStyle(CanonColor.bone)
                .lineLimit(2)
        }
    }
}

private struct StoryAudioPreview: NSViewRepresentable {
    let path: String
    var reloadToken: String = ""

    func makeCoordinator() -> Coordinator {
        Coordinator(path: path, reloadToken: reloadToken)
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        let player = makePlayer(for: path)
        view.player = player
        context.coordinator.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if context.coordinator.path != path || context.coordinator.reloadToken != reloadToken {
            context.coordinator.player?.pause()
            let player = makePlayer(for: path)
            view.player = player
            context.coordinator.path = path
            context.coordinator.reloadToken = reloadToken
            context.coordinator.player = player
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        view.player = nil
        coordinator.player = nil
    }

    private func makePlayer(for path: String) -> AVPlayer {
        AVPlayer(url: URL(fileURLWithPath: path))
    }

    final class Coordinator {
        var path: String
        var reloadToken: String
        var player: AVPlayer?

        init(path: String, reloadToken: String) {
            self.path = path
            self.reloadToken = reloadToken
        }
    }
}

private struct StorySignalGroupCard: View {
    let title: String
    let values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(CanonType.interface(11, weight: .semibold))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(CanonColor.brass)

            if values.isEmpty {
                Text("No clear signal")
                    .font(CanonType.editorial(14))
                    .foregroundStyle(CanonColor.ink.opacity(0.58))
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(values.prefix(6), id: \.self) { value in
                        HStack(alignment: .top, spacing: 7) {
                            Circle()
                                .fill(CanonColor.brass.opacity(0.76))
                                .frame(width: 4, height: 4)
                                .padding(.top, 7)
                            Text(value)
                                .font(CanonType.editorial(14))
                                .foregroundStyle(CanonColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(CanonColor.paperInset.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper)
        )
    }
}

private struct StoryBeatCardView: View {
    let beat: StoryBeatCard

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(String(format: "%02d", beat.order))
                    .font(CanonType.archive(12, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
                Text(beat.title)
                    .font(CanonType.editorial(21, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(beat.supportStatus.label)
                    .font(CanonType.interface(10, weight: .semibold))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(supportColor)
            }

            StoryBeatField(title: "Function", value: beat.narrativeFunction, isLight: true)
            StoryBeatField(title: "Turn", value: beat.emotionalTurn, isLight: true)
            StoryBeatField(title: "Visual Opportunity", value: beat.visualOpportunity, isLight: true)

            if !beat.meaningRefs.isEmpty {
                Text(beat.meaningRefs.prefix(4).joined(separator: " · "))
                    .font(CanonType.archive(10, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.56))
                    .lineLimit(2)
            }

            if !beat.constraints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Constraints")
                        .font(CanonType.interface(10, weight: .semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(CanonColor.rust)
                    Text(beat.constraints.prefix(3).joined(separator: "; "))
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.ink.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(CanonColor.paperInset.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper)
        )
    }

    private var supportColor: Color {
        switch beat.supportStatus {
        case .strong:
            return CanonColor.olive
        case .possible:
            return CanonColor.brass
        case .weak:
            return CanonColor.muted
        case .unsupported:
            return CanonColor.rust
        }
    }
}

private struct StoryBeatField: View {
    let title: String
    let value: String
    var isLight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(CanonType.interface(10, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(isLight ? CanonColor.ink.opacity(0.58) : CanonColor.muted)
            Text(value.isEmpty ? "Not specified" : value)
                .font(CanonType.editorial(14))
                .foregroundStyle(isLight ? CanonColor.ink : CanonColor.bone)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StoryEmptyPanel: View {
    let title: String
    let subtitle: String
    var isLight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(CanonType.editorial(18, weight: .semibold))
                .foregroundStyle(isLight ? CanonColor.ink : CanonColor.bone)
            Text(subtitle)
                .font(CanonType.interface(12))
                .foregroundStyle(isLight ? CanonColor.ink.opacity(0.62) : CanonColor.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isLight ? CanonColor.paperInset.opacity(0.56) : CanonColor.mediaCard.opacity(0.72)),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isLight ? CanonColor.hairlinePaper : CanonColor.hairlineDark)
        )
    }
}

private struct GoalOutcomePanel: View {
    @ObservedObject var library: LibraryEngine

    private var brief: ProjectGoalBrief {
        library.activeGoalBrief
    }

    private var hasOutcomeContent: Bool {
        !brief.desiredAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !brief.distributionContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !brief.storyPromise.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !brief.successCriteria.isEmpty
            || !brief.constraints.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if hasOutcomeContent {
                    outcomeField("Premise", brief.storyPromise)
                    outcomeField("Viewer Experience", brief.desiredAction)
                    outcomeField("Platform", brief.distributionContext)
                    outcomeListField("Success", brief.successCriteria)
                    outcomeListField("Constraints", brief.constraints)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("No premise yet")
                            .font(CanonType.editorial(18, weight: .semibold))
                            .foregroundStyle(CanonColor.ink)
                        Text("Use the Goal chat to define the premise, viewer experience, platform, and success criteria.")
                            .font(CanonType.interface(12))
                            .foregroundStyle(CanonColor.ink.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(CanonColor.paperInset.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(CanonColor.hairlinePaper)
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(CanonColor.paper)
        .foregroundStyle(CanonColor.ink)
    }

    @ViewBuilder
    private func outcomeField(_ title: String, _ value: String) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            outcomeBlock(title: title) {
                Text(trimmed)
                    .font(CanonType.editorial(15))
                    .foregroundStyle(CanonColor.ink.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func outcomeListField(_ title: String, _ values: [String]) -> some View {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleaned.isEmpty {
            outcomeBlock(title: title) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(cleaned.prefix(6), id: \.self) { value in
                        HStack(alignment: .top, spacing: 7) {
                            Circle()
                                .fill(CanonColor.brass.opacity(0.76))
                                .frame(width: 4, height: 4)
                                .padding(.top, 7)
                            Text(value)
                                .font(CanonType.editorial(14))
                                .foregroundStyle(CanonColor.ink.opacity(0.86))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func outcomeBlock<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(CanonType.interface(10, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(CanonColor.muted)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.paperInset.opacity(0.52), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper.opacity(0.72))
        )
    }
}

private struct GoalInterviewPanel: View {
    @ObservedObject var library: LibraryEngine
    let onContinueToAesthetic: () -> Void
    @State private var composerText = ""
    @State private var selectedMediaIds: [String] = []
    @State private var viewedVersionId: String?
    @State private var isSubmittingMessage = false
    @State private var isMediaDropTargeted = false
    @FocusState private var isComposerFocused: Bool

    private var versions: [ProjectGoalBriefVersion] {
        library.projectGoal.versions
    }

    private var viewedVersion: ProjectGoalBriefVersion? {
        if let viewedVersionId,
           let version = versions.first(where: { $0.versionId == viewedVersionId }) {
            return version
        }
        return library.projectGoal.activeVersion
    }

    private var displayedBrief: ProjectGoalBrief {
        viewedVersion?.brief ?? library.activeGoalBrief
    }

    private var viewedIndex: Int {
        guard let versionId = viewedVersion?.versionId,
              let index = versions.firstIndex(where: { $0.versionId == versionId }) else {
            return max(versions.count - 1, 0)
        }
        return index
    }

    private var isViewingLatest: Bool {
        viewedVersion?.versionId == library.projectGoal.activeVersionId
    }

    private var isComposerWaiting: Bool {
        isSubmittingMessage || library.isInterviewingGoal
    }

    private var shouldShowChooseAesthetic: Bool {
        library.projectGoal.isReadyForAesthetic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            briefCard
            chatArea
        }
        .padding(18)
        .onAppear {
            viewedVersionId = library.projectGoal.activeVersionId
        }
        .onChange(of: library.projectGoal.activeVersionId) { _, activeVersionId in
            viewedVersionId = activeVersionId
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("GOAL")
                .font(CanonType.interface(11, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(CanonColor.brass)
            Text(library.goalStatus)
                .font(CanonType.interface(11, weight: .semibold))
                .foregroundStyle(CanonColor.muted)
                .lineLimit(1)
            Spacer(minLength: 0)
            if library.isInterviewingGoal {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var briefCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goal Brief")
                        .font(CanonType.editorial(22, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    Text(versionLabel)
                        .font(CanonType.archive(10, weight: .medium))
                        .foregroundStyle(CanonColor.muted)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 7) {
                    if shouldShowChooseAesthetic {
                        chooseAestheticButton
                    }
                    versionControls
                }
            }

            contentTypeChips

            if displayedBrief.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Tell me what this project should accomplish.")
                    .font(CanonType.editorial(15))
                    .foregroundStyle(CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(displayedBrief.goal)
                    .font(CanonType.editorial(17, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            briefField("Audience", displayedBrief.audience)
            aestheticSignalsSection(displayedBrief.aestheticIntent)
            briefListField("Open questions", displayedBrief.openQuestions)

            HStack(spacing: 10) {
                Text("Confidence \(Int((displayedBrief.confidence0To1 * 100).rounded()))%")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
                Spacer(minLength: 0)
                if let version = viewedVersion, !isViewingLatest {
                    Button {
                        library.restoreGoalVersion(version)
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(CanonSecondaryButtonStyle())
                    .disabled(library.isInterviewingGoal)
                }
            }
        }
        .padding(.leading, 13)
        .padding(.vertical, 10)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(CanonColor.brass)
                .frame(width: 2)
        }
    }

    private var versionLabel: String {
        guard !versions.isEmpty else { return "No versions yet" }
        let latest = isViewingLatest ? "latest" : "viewing"
        return "Version \(viewedIndex + 1)/\(versions.count) · \(latest)"
    }

    private var versionControls: some View {
        HStack(spacing: 6) {
            Text("versions")
                .font(CanonType.interface(10, weight: .medium))
                .foregroundStyle(CanonColor.muted.opacity(0.72))
                .lineLimit(1)

            Button {
                moveViewedVersion(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .disabled(viewedIndex <= 0)
            .help("Previous Goal Version")

            Button {
                moveViewedVersion(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .disabled(versions.isEmpty || viewedIndex >= versions.count - 1)
            .help("Next Goal Version")
        }
    }

    private var contentTypeChips: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 0), spacing: 6),
                GridItem(.flexible(minimum: 0), spacing: 6),
                GridItem(.flexible(minimum: 0), spacing: 6),
                GridItem(.flexible(minimum: 0), spacing: 6),
            ],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(ProjectIntent.allCases) { intent in
                let isSelected = displayedBrief.contentType == intent
                Button {
                    library.setGoalContentType(intent)
                } label: {
                    Text(intent.label)
                        .font(CanonType.interface(10, weight: .semibold))
                        .foregroundStyle(isSelected ? CanonColor.ink : CanonColor.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .padding(.horizontal, 4)
                        .background(isSelected ? CanonColor.paperAged : CanonColor.paperInset.opacity(0.42), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? CanonColor.brass.opacity(0.78) : CanonColor.hairlinePaper.opacity(0.56))
                        )
                }
                .buttonStyle(.plain)
                .disabled(library.isInterviewingGoal)
            }
        }
    }

    private var chatArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            transcript
            composer

            if shouldShowChooseAesthetic {
                HStack {
                    Spacer(minLength: 0)
                    chooseAestheticButton
                }
            }
        }
    }

    private var chooseAestheticButton: some View {
        Button {
            guard library.canContinueFromGoal else { return }
            onContinueToAesthetic()
        } label: {
            Label("Choose Aesthetic", systemImage: "arrow.right")
        }
        .buttonStyle(CanonPrimaryButtonStyle())
        .disabled(!library.canContinueFromGoal)
        .help("Choose Aesthetic")
    }

    private var transcript: some View {
        Group {
            if library.projectGoal.messages.isEmpty {
                currentQuestionCard
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(library.projectGoal.messages) { message in
                                messageBubble(message)
                                    .id(message.messageId)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: library.projectGoal.messages.count) { _, _ in
                        guard let id = library.projectGoal.messages.last?.messageId else { return }
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.14)) {
                                proxy.scrollTo(id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    private var currentQuestionCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What should this project do?")
                .font(CanonType.editorial(18, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            Text("Start with the intended outcome, audience, platform, or what would make this feel done.")
                .font(CanonType.interface(12))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.paperInset.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !selectedMediaIds.isEmpty {
                mediaChipTray
            }

            ZStack(alignment: .topLeading) {
                if composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    composerPlaceholder
                }
                TextEditor(text: $composerText)
                    .font(CanonType.editorial(14))
                    .frame(minHeight: 150, maxHeight: 220)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(CanonColor.ink)
                    .focused($isComposerFocused)
                    .disabled(isComposerWaiting)
                    .onKeyPress(keys: [.return]) { press in
                        guard press.modifiers.contains(.command), canSendMessage else {
                            return .ignored
                        }
                        sendMessage()
                        return .handled
                    }
            }
            .background(isMediaDropTargeted ? CanonColor.focusBlue.opacity(0.12) : CanonColor.paperInset.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isMediaDropTargeted ? CanonColor.focusBlue : CanonColor.hairlinePaper.opacity(0.70))
            )
            .dropDestination(for: MediaIDTransfer.self) { transfers, _ in
                guard !isComposerWaiting else { return false }
                for transfer in transfers where !selectedMediaIds.contains(transfer.mediaId) {
                    selectedMediaIds.append(transfer.mediaId)
                }
                return !transfers.isEmpty
            } isTargeted: { targeted in
                isMediaDropTargeted = targeted && !isComposerWaiting
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    sendMessage()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(!canSendMessage)
            }
        }
        .padding(12)
        .background(CanonColor.paperInset.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper.opacity(0.70))
        )
    }

    private var canSendMessage: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isComposerWaiting
    }

    @ViewBuilder
    private var composerPlaceholder: some View {
        if isComposerWaiting {
            TimelineView(.periodic(from: Date(), by: 0.45)) { context in
                Text(thinkingPlaceholderText(at: context.date))
                    .font(CanonType.editorial(14))
                    .foregroundStyle(CanonColor.muted.opacity(0.72))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        } else {
            Text("Describe the outcome, audience, use, or success criteria.")
                .font(CanonType.editorial(14))
                .foregroundStyle(CanonColor.muted.opacity(0.72))
                .padding(.horizontal, 7)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
        }
    }

    private func thinkingPlaceholderText(at date: Date) -> String {
        let step = Int(date.timeIntervalSinceReferenceDate / 0.45) % 3
        return "thinking" + String(repeating: ".", count: step + 1)
    }

    private var mediaChipTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(library.mediaItems(for: selectedMediaIds)) { item in
                    HStack(spacing: 6) {
                        ThumbnailImage(path: item.thumbnailPath, kind: item.kind)
                            .frame(width: 34, height: 26)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(item.filename)
                            .font(CanonType.interface(11, weight: .semibold))
                            .foregroundStyle(CanonColor.ink)
                            .lineLimit(1)
                        Button {
                            selectedMediaIds.removeAll { $0 == item.mediaId }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(CanonColor.muted)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(CanonColor.paperAged.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(CanonColor.hairlinePaper)
                    )
                }
            }
        }
    }

    private func messageBubble(_ message: ProjectGoalMessage) -> some View {
        let isUser = message.role == .user
        return HStack(alignment: .top) {
            if isUser { Spacer(minLength: 42) }
            VStack(alignment: .leading, spacing: 6) {
                Text(isUser ? "You" : "LitScenes")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(isUser ? CanonColor.focusBlue : CanonColor.brass)
                Text(message.text)
                    .font(CanonType.editorial(14))
                    .foregroundStyle(CanonColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if !message.mediaIds.isEmpty {
                    Text(message.mediaIds.joined(separator: ", "))
                        .font(CanonType.archive(9, weight: .medium))
                        .foregroundStyle(CanonColor.muted)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(isUser ? CanonColor.paperAged.opacity(0.66) : CanonColor.paperInset.opacity(0.52), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isUser ? CanonColor.focusBlue.opacity(0.32) : CanonColor.hairlinePaper)
            )
            if !isUser { Spacer(minLength: 42) }
        }
    }

    @ViewBuilder
    private func briefField(_ title: String, _ value: String) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(CanonType.interface(10, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(CanonColor.muted)
                Text(trimmed)
                    .font(CanonType.editorial(14))
                    .foregroundStyle(CanonColor.ink.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func aestheticSignalsSection(_ seed: ProjectAestheticIntentSeed) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Aesthetic Signals")
                    .font(CanonType.interface(10, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(CanonColor.muted)
                Spacer(minLength: 0)
                if seed.confidence0To1 > 0 {
                    Text("\(Int((seed.confidence0To1 * 100).rounded()))%")
                        .font(CanonType.archive(10, weight: .semibold))
                        .foregroundStyle(CanonColor.muted)
                }
            }

            if seed.hasSignals {
                VStack(alignment: .leading, spacing: 6) {
                    signalChips("Values", seed.narrativeValues + seed.emotionalTargets)
                    signalChips("Mood", seed.visualMood)
                    signalChips("Palette", seed.paletteHints)
                    signalChips("Motifs", seed.motifHints)
                    signalChips("Energy", seed.energy)
                    signalChips("Avoid", seed.avoid, isAvoid: true)
                }
            } else {
                Text("Style signals will appear as the Goal becomes clearer.")
                    .font(CanonType.editorial(14))
                    .foregroundStyle(CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !seed.openStyleQuestions.isEmpty {
                Text(seed.openStyleQuestions.joined(separator: "; "))
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(CanonColor.paperInset.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(CanonColor.hairlinePaper.opacity(0.58))
        )
    }

    @ViewBuilder
    private func signalChips(_ title: String, _ values: [String], isAvoid: Bool = false) -> some View {
        let cleaned = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !cleaned.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(CanonType.archive(9, weight: .semibold))
                    .foregroundStyle(CanonColor.muted.opacity(0.82))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 5)], alignment: .leading, spacing: 5) {
                    ForEach(cleaned.prefix(8), id: \.self) { value in
                        Text(value)
                            .font(CanonType.interface(10, weight: .semibold))
                            .foregroundStyle(isAvoid ? CanonColor.rust : CanonColor.brass)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isAvoid ? CanonColor.rust.opacity(0.08) : CanonColor.paperAged.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isAvoid ? CanonColor.rust.opacity(0.28) : CanonColor.brass.opacity(0.24))
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func briefListField(_ title: String, _ values: [String]) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(CanonType.interface(10, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(CanonColor.muted)
                Text(values.joined(separator: "; "))
                    .font(CanonType.editorial(14))
                    .foregroundStyle(CanonColor.ink.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private func moveViewedVersion(by delta: Int) {
        guard !versions.isEmpty else { return }
        let nextIndex = min(max(viewedIndex + delta, 0), versions.count - 1)
        viewedVersionId = versions[nextIndex].versionId
    }

    private func sendMessage() {
        guard canSendMessage else { return }
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let mediaIds = selectedMediaIds
        composerText = ""
        selectedMediaIds = []
        isComposerFocused = false
        isSubmittingMessage = true
        Task {
            await library.sendGoalInterviewMessage(text: text, mediaIds: mediaIds)
            isSubmittingMessage = false
        }
    }
}

private struct MediaGridCell: Identifiable {
    let item: MediaItemRecord
    let span: Int
    let isExpanded: Bool

    var id: String { item.mediaId }
}

enum ImagePreviewDetailPlacement {
    case adaptivePortraitSide
    case below
}

struct ImagePreviewModalShell<HeaderActions: View, ImageActions: View, DetailPanel: View>: View {
    let title: String
    let subtitle: String
    let metadataText: String
    let imagePath: String
    let displayedImageSize: CGSize
    let detailPlacement: ImagePreviewDetailPlacement
    let missingImageTitle: String
    let missingImageSubtitle: String
    let imageActionHeight: CGFloat
    let imageOverlay: AnyView
    @Binding var zoomScale: CGFloat
    let focusRect: CGRect?
    let focusRotationDegrees: Double
    let outpaintSourceRect: CGRect?
    let onImageClick: ((CGPoint) -> Void)?
    let onFocusResize: ((CGRect) -> Void)?
    let onFocusMove: ((CGPoint) -> Void)?
    let onFocusRotate: ((Double) -> Void)?
    let onOutpaintSourceMove: ((CGPoint) -> Void)?
    let collapsibleDetail: Bool
    let onClose: () -> Void
    let headerActions: HeaderActions
    let imageActions: ImageActions
    let detailPanel: DetailPanel
    @State private var isDetailCollapsed: Bool
    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 5

    init(
        title: String,
        subtitle: String,
        metadataText: String,
        imagePath: String,
        displayedImageSize: CGSize,
        zoomScale: Binding<CGFloat>,
        detailPlacement: ImagePreviewDetailPlacement,
        missingImageTitle: String,
        missingImageSubtitle: String,
        imageActionHeight: CGFloat = 0,
        imageOverlay: AnyView = AnyView(EmptyView()),
        focusRect: CGRect? = nil,
        focusRotationDegrees: Double = 0,
        outpaintSourceRect: CGRect? = nil,
        onImageClick: ((CGPoint) -> Void)? = nil,
        onFocusResize: ((CGRect) -> Void)? = nil,
        onFocusMove: ((CGPoint) -> Void)? = nil,
        onFocusRotate: ((Double) -> Void)? = nil,
        onOutpaintSourceMove: ((CGPoint) -> Void)? = nil,
        collapsibleDetail: Bool = false,
        onClose: @escaping () -> Void,
        @ViewBuilder headerActions: () -> HeaderActions,
        @ViewBuilder imageActions: () -> ImageActions,
        @ViewBuilder detailPanel: () -> DetailPanel
    ) {
        self.title = title
        self.subtitle = subtitle
        self.metadataText = metadataText
        self.imagePath = imagePath
        self.displayedImageSize = displayedImageSize
        self._zoomScale = zoomScale
        self.detailPlacement = detailPlacement
        self.missingImageTitle = missingImageTitle
        self.missingImageSubtitle = missingImageSubtitle
        self.imageActionHeight = imageActionHeight
        self.imageOverlay = imageOverlay
        self.focusRect = focusRect
        self.focusRotationDegrees = focusRotationDegrees
        self.outpaintSourceRect = outpaintSourceRect
        self.onImageClick = onImageClick
        self.onFocusResize = onFocusResize
        self.onFocusMove = onFocusMove
        self.onFocusRotate = onFocusRotate
        self.onOutpaintSourceMove = onOutpaintSourceMove
        self.collapsibleDetail = collapsibleDetail
        self.onClose = onClose
        self.headerActions = headerActions()
        self.imageActions = imageActions()
        self.detailPanel = detailPanel()
        self._isDetailCollapsed = State(initialValue: collapsibleDetail)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            GeometryReader { geometry in
                previewBody(size: geometry.size)
            }
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            controls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanonColor.room.opacity(0.98))
        .zIndex(20)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(CanonType.editorial(25, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                    .lineLimit(1)
                Text(subtitle)
                    .font(CanonType.archive(11))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            if !metadataText.trimmed.isEmpty {
                Text(metadataText)
                    .font(CanonType.archive(11, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
            }

            headerActions

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close Image Preview")
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(CanonColor.sidebar)
    }

    @ViewBuilder
    private func previewBody(size: CGSize) -> some View {
        let actionHeight = normalizedImageActionHeight
        if collapsibleDetail, isDetailCollapsed {
            let stripHeight: CGFloat = 34
            let imageHeight = max(1, size.height - stripHeight - actionHeight - 1)
            VStack(spacing: 0) {
                imagePreviewSurface(size: CGSize(width: size.width, height: imageHeight))
                    .frame(width: size.width, height: imageHeight)
                imageActionBar
                Rectangle()
                    .fill(CanonColor.hairlineDark)
                    .frame(height: 1)
                detailCollapseStrip(collapsed: true)
                    .frame(width: size.width, height: stripHeight)
            }
            .background(CanonColor.room)
        } else if shouldUseSideDetailLayout {
            let sideWidth = min(max(260, size.width * 0.34), min(460, max(220, size.width * 0.46)))
            let imageWidth = max(1, size.width - sideWidth - 1)
            let imageHeight = max(1, size.height - actionHeight)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    imagePreviewSurface(size: CGSize(width: imageWidth, height: imageHeight))
                        .frame(width: imageWidth, height: imageHeight)
                    imageActionBar
                }
                .frame(width: imageWidth, height: size.height)
                Rectangle()
                    .fill(CanonColor.hairlineDark)
                    .frame(width: 1)
                detailPanel
                    .frame(width: sideWidth, height: size.height)
            }
            .background(CanonColor.room)
        } else {
            let stripHeight: CGFloat = collapsibleDetail ? 26 : 0
            let preferredDetailHeight = max(150, size.height * 0.32)
            let maximumDetailHeight = max(120, size.height * 0.45)
            let detailHeight = min(320, min(preferredDetailHeight, maximumDetailHeight))
            let imageHeight = max(1, size.height - detailHeight - actionHeight - stripHeight - 1)
            VStack(spacing: 0) {
                imagePreviewSurface(size: CGSize(width: size.width, height: imageHeight))
                    .frame(width: size.width, height: imageHeight)
                imageActionBar
                Rectangle()
                    .fill(CanonColor.hairlineDark)
                    .frame(height: 1)
                if collapsibleDetail {
                    detailCollapseStrip(collapsed: false)
                        .frame(width: size.width, height: stripHeight)
                }
                detailPanel
                    .frame(width: size.width, height: detailHeight)
            }
            .background(CanonColor.room)
        }
    }

    private func detailCollapseStrip(collapsed: Bool) -> some View {
        Button {
            isDetailCollapsed.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: collapsed ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                Text(collapsed ? "Show details" : "Hide details")
                    .font(CanonType.archive(10, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(CanonColor.muted)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(CanonColor.sidebar)
        }
        .buttonStyle(.plain)
        .help(collapsed ? "Show the generation details panel" : "Give the image the full height")
    }

    private var normalizedImageActionHeight: CGFloat {
        max(imageActionHeight, 0)
    }

    @ViewBuilder
    private var imageActionBar: some View {
        if normalizedImageActionHeight > 0 {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(CanonColor.hairlineDark)
                    .frame(height: 1)
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    imageActions
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .frame(height: max(1, normalizedImageActionHeight - 1))
                .frame(maxWidth: .infinity)
                .background(CanonColor.sidebar)
            }
            .frame(height: normalizedImageActionHeight)
        }
    }

    private var shouldUseSideDetailLayout: Bool {
        guard case .adaptivePortraitSide = detailPlacement else { return false }
        guard displayedImageSize.width > 0, displayedImageSize.height > 0 else { return false }
        return displayedImageSize.width / displayedImageSize.height < 0.92
    }

    @ViewBuilder
    private func imagePreviewSurface(size: CGSize) -> some View {
        ZStack(alignment: .trailing) {
            if FileManager.default.fileExists(atPath: imagePath) {
                ZoomableImageScrollView(
                    path: imagePath,
                    zoomScale: $zoomScale,
                    minZoom: minZoom,
                    maxZoom: maxZoom,
                    focusRect: focusRect,
                    focusRotationDegrees: focusRotationDegrees,
                    outpaintSourceRect: outpaintSourceRect,
                    onImageClick: onImageClick,
                    onFocusResize: onFocusResize,
                    onFocusMove: onFocusMove,
                    onFocusRotate: onFocusRotate,
                    onOutpaintSourceMove: onOutpaintSourceMove
                )
                .frame(width: size.width, height: size.height)
                .background(CanonColor.room)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(CanonColor.brass)
                    Text(missingImageTitle)
                        .font(CanonType.editorial(24, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                    Text(missingImageSubtitle)
                        .font(CanonType.archive(11))
                        .foregroundStyle(CanonColor.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
                .background(CanonColor.room)
            }
            imageOverlay
        }
        .frame(width: size.width, height: size.height)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                zoomScale = max(minZoom, zoomScale - 0.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .frame(width: 28)
            }
            .buttonStyle(CanonSecondaryButtonStyle())
            .help("Viewer zoom out")

            Slider(value: $zoomScale, in: minZoom...maxZoom)
                .frame(width: 240)

            Button {
                zoomScale = min(maxZoom, zoomScale + 0.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .frame(width: 28)
            }
            .buttonStyle(CanonSecondaryButtonStyle())
            .help("Viewer zoom in")

            Text("\(Int((zoomScale * 100).rounded()))%")
                .font(CanonType.archive(11, weight: .medium))
                .foregroundStyle(CanonColor.muted)
                .frame(width: 48, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(CanonColor.sidebar)
    }
}

private struct ImagePreviewModal: View {
    @ObservedObject var library: LibraryEngine
    let item: MediaItemRecord
    @Binding var zoomScale: CGFloat
    let onClose: () -> Void
    /// Restyle: adopt this photo as a Frame and open the Frame Creator (style
    /// wheel first). nil hides the verb.
    var onRestyleAsFrame: (() -> Void)? = nil
    /// Why Restyle is disabled (no Scene Plan to hold the Frame); nil = enabled.
    var restyleBlockReason: String? = nil
    @State private var isTagEditorPresented = false
    @State private var isStartVideoPresented = false

    private var imagePath: String {
        FileManager.default.fileExists(atPath: item.path) ? item.path : item.thumbnailPath
    }

    private var hasStartVideoOriginal: Bool {
        !item.path.trimmed.isEmpty && FileManager.default.fileExists(atPath: item.path)
    }

    private var observation: ImageObservationResult? {
        library.mediaObservationsById[item.mediaId]
    }

    private var displayedImageSize: CGSize {
        if let imageSourceSize = imageSourceDisplayedSize(path: imagePath) {
            return imageSourceSize
        }
        if let imageSize = NSImage(contentsOfFile: imagePath)?.size, imageSize.width > 0, imageSize.height > 0 {
            return imageSize
        }
        guard item.width > 0, item.height > 0 else { return .zero }
        return CGSize(width: CGFloat(item.width), height: CGFloat(item.height))
    }

    private func imageSourceDisplayedSize(path: String) -> CGSize? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = positiveCGFloat(properties[kCGImagePropertyPixelWidth]),
              let pixelHeight = positiveCGFloat(properties[kCGImagePropertyPixelHeight])
        else {
            return nil
        }

        let orientation = positiveInt(properties[kCGImagePropertyOrientation]) ?? 1
        if [5, 6, 7, 8].contains(orientation) {
            return CGSize(width: pixelHeight, height: pixelWidth)
        }
        return CGSize(width: pixelWidth, height: pixelHeight)
    }

    private func positiveCGFloat(_ value: Any?) -> CGFloat? {
        guard let number = value as? NSNumber else { return nil }
        let result = CGFloat(truncating: number)
        return result > 0 ? result : nil
    }

    private func positiveInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.intValue
        return result > 0 ? result : nil
    }

    var body: some View {
        ImagePreviewModalShell(
            title: item.filename,
            subtitle: item.relativePath,
            metadataText: "\(item.width)x\(item.height)",
            imagePath: imagePath,
            displayedImageSize: displayedImageSize,
            zoomScale: $zoomScale,
            detailPlacement: .adaptivePortraitSide,
            missingImageTitle: "Image could not be loaded",
            missingImageSubtitle: item.path,
            imageActionHeight: 54,
            onClose: onClose
        ) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            } label: {
                Image(systemName: "folder")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Open in Finder")
        } imageActions: {
            imageActionNav
        } detailPanel: {
            analysisPanel
        }
    }

    /// EARNED CTA LAW: Analyze hides once an analysis is saved and current,
    /// and offers Re-analyze when the saved one is from an older analyzer.
    private var analyzeButtonState: MediaAnalyzeButtonState {
        mediaAnalyzeButtonState(
            hasObservation: observation != nil,
            isCurrentVersion: observation?.isCurrentAestheticObservationVersion == true
        )
    }

    private var imageActionNav: some View {
        HStack(spacing: 8) {
            if analyzeButtonState != .hidden {
                Button {
                    Task {
                        await library.analyzeMediaItem(item)
                    }
                } label: {
                    LitIconLabel(
                        title: library.isAnalyzingMedia
                            ? "Analyzing"
                            : (analyzeButtonState == .reanalyze ? "Re-analyze" : "Analyze"),
                        icon: .analyze,
                        iconSize: 12
                    )
                    .frame(minWidth: 96)
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(!library.canAnalyzeMediaItem(item))
                .help(analyzeButtonState == .reanalyze
                    ? "The saved analysis is from an older analyzer — re-analyze this image"
                    : "Analyze this image only")
            }

            if let onRestyleAsFrame {
                Button {
                    onRestyleAsFrame()
                } label: {
                    Label("Restyle", systemImage: "paintpalette")
                        .frame(minWidth: 96)
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(restyleBlockReason != nil)
                .help(restyleBlockReason
                    ?? "Restyle this photo as a Frame — the Frame Creator opens with the style catalog and the photo pinned as its source")
            }

            Button {
                isStartVideoPresented = true
            } label: {
                Label(
                    library.activeMediaMotionMediaIds.contains(item.mediaId)
                        ? "Rendering"
                        : "Start Video",
                    systemImage: "video.badge.plus"
                )
                .frame(minWidth: 96)
            }
            .buttonStyle(CanonSecondaryButtonStyle())
            .disabled(library.activeMediaMotionMediaIds.contains(item.mediaId))
            .help(hasStartVideoOriginal
                ? "Animate this image into a video clip — it lands in Footage"
                : "Original unavailable — open to see how to restore Start Video")
            .popover(isPresented: $isStartVideoPresented, arrowEdge: .bottom) {
                MediaStartVideoPopover(library: library, item: item) {
                    isStartVideoPresented = false
                }
            }

            Menu {
                MediaUseMenu(
                    library: library,
                    item: item,
                    onEditTags: { isTagEditorPresented = true },
                    onRestyle: restyleBlockReason == nil ? onRestyleAsFrame : nil,
                    onStartVideo: { isStartVideoPresented = true }
                )
            } label: {
                Label("Use", systemImage: "plus.square.on.square")
                    .frame(minWidth: 96)
            }
            .buttonStyle(CanonSecondaryButtonStyle())
            .help("Use this image — attach it to a frame render, a roster entry, or Story")
            // The Tag button is retired (tags auto-write on import and stay
            // searchable); the editor survives behind Use → Tag…, so its
            // popover anchors here now.
            .popover(isPresented: $isTagEditorPresented, arrowEdge: .bottom) {
                MediaTagEditorPopover(library: library, item: item) {
                    isTagEditorPresented = false
                }
            }

            MediaEnableButton(
                library: library,
                item: item,
                mode: .action,
                isSubtleAction: true
            )
        }
    }

    private var analysisPanel: some View {
        ImageAnalysisPanel(
            observation: observation,
            analysisStatus: library.mediaAnalysisStatus,
            isAnalyzing: library.isAnalyzingMedia
        )
    }
}

private struct ImageAnalysisPanel: View {
    let observation: ImageObservationResult?
    let analysisStatus: String
    let isAnalyzing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let observation {
                    summaryList(observation)
                    textSection("Caption", observation.plainCaption)
                    textSection("Literal Description", observation.literalDescription)
                    textSection("Setting", observation.setting)
                    listSection("Objects", values: observation.objects)
                    listSection("Activities", values: observation.activities)
                    listSection("Meanings", values: observation.possibleMeanings)
                    listSection("Visible Text", values: visibleTextRows(observation))
                    listSection("Review Notes", values: reviewRows(observation))
                } else {
                    noAnalysisState
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(CanonColor.paper)
        .foregroundStyle(CanonColor.ink)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Analysis")
                .font(CanonType.editorial(22, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            Spacer(minLength: 0)
            Text(observation == nil ? "Not saved" : "Saved")
                .font(CanonType.archive(10, weight: .semibold))
                .foregroundStyle(observation == nil ? CanonColor.muted : CanonColor.olive)
        }
    }

    private var noAnalysisState: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: isAnalyzing ? "sparkles" : "circle.dashed")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isAnalyzing ? CanonColor.brass : CanonColor.muted)
                Text("No analysis saved yet")
                    .font(CanonType.interface(13, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
            }
            Text(isAnalyzing ? "Analyze Media is running: \(analysisStatus)" : analysisStatus)
                .font(CanonType.interface(12))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.paperInset.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper)
        )
    }

    private func summaryList(_ observation: ImageObservationResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(CanonType.interface(10, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(CanonColor.brass)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(summaryRows(observation), id: \.self) { row in
                    HStack(alignment: .top, spacing: 7) {
                        Circle()
                            .fill(CanonColor.brass.opacity(0.78))
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)
                        Text(row)
                            .font(CanonType.editorial(14))
                            .foregroundStyle(CanonColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.paperInset.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper)
        )
    }

    @ViewBuilder
    private func textSection(_ title: String, _ value: String) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            analysisSection(title) {
                Text(trimmed)
                    .font(CanonType.editorial(14))
                    .foregroundStyle(CanonColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func listSection(_ title: String, values: [String]) -> some View {
        let rows = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !rows.isEmpty {
            analysisSection(title) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(rows, id: \.self) { row in
                        HStack(alignment: .top, spacing: 7) {
                            Circle()
                                .fill(CanonColor.ink.opacity(0.46))
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                            Text(row)
                                .font(CanonType.interface(12))
                                .foregroundStyle(CanonColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }

    private func analysisSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(CanonType.interface(10, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(CanonColor.muted)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryRows(_ observation: ImageObservationResult) -> [String] {
        var rows: [String] = []
        let caption = observation.plainCaption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty {
            rows.append("Caption: \(shortAnalysisText(caption, limit: 120))")
        }
        let setting = observation.setting.trimmingCharacters(in: .whitespacesAndNewlines)
        if !setting.isEmpty {
            rows.append("Setting: \(shortAnalysisText(setting, limit: 90))")
        }
        if !observation.objects.isEmpty {
            rows.append("Objects: \(observation.objects.prefix(6).joined(separator: ", "))")
        }
        if !observation.activities.isEmpty {
            rows.append("Activities: \(observation.activities.prefix(4).joined(separator: ", "))")
        }
        if !observation.possibleMeanings.isEmpty {
            rows.append("Meanings: \(observation.possibleMeanings.prefix(3).joined(separator: ", "))")
        }
        if !observation.visibleText.isEmpty {
            rows.append("Visible text: \(observation.visibleText.count) text observation\(observation.visibleText.count == 1 ? "" : "s")")
        }
        if observation.humanReview.needsReview {
            let reason = observation.humanReview.reviewReason.trimmingCharacters(in: .whitespacesAndNewlines)
            rows.append(reason.isEmpty ? "Review needed" : "Review needed: \(shortAnalysisText(reason, limit: 90))")
        }
        return rows.isEmpty ? ["Observation saved"] : rows
    }

    private func visibleTextRows(_ observation: ImageObservationResult) -> [String] {
        observation.visibleText.compactMap { value in
            let text = value.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let whereSeen = value.whereSeen.trimmingCharacters(in: .whitespacesAndNewlines)
            if whereSeen.isEmpty {
                return text
            }
            return "\(text) - \(whereSeen)"
        }
    }

    private func reviewRows(_ observation: ImageObservationResult) -> [String] {
        var rows: [String] = []
        let reviewReason = observation.humanReview.reviewReason.trimmingCharacters(in: .whitespacesAndNewlines)
        if observation.humanReview.needsReview {
            rows.append(reviewReason.isEmpty ? "Needs human review" : "Needs review: \(reviewReason)")
        } else if !reviewReason.isEmpty {
            rows.append(reviewReason)
        }
        let question = observation.humanReview.suggestedQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !question.isEmpty {
            rows.append("Question: \(question)")
        }
        let detailNotes = observation.detailObservationNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detailNotes.isEmpty {
            rows.append(detailNotes)
        }
        rows.append(contentsOf: observation.uncertainties.prefix(5).compactMap { uncertainty in
            let field = uncertainty.field.trimmingCharacters(in: .whitespacesAndNewlines)
            let question = uncertainty.question.trimmingCharacters(in: .whitespacesAndNewlines)
            let why = uncertainty.whyUncertain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !field.isEmpty || !question.isEmpty || !why.isEmpty else { return nil }
            let lead = field.isEmpty ? "Uncertainty" : field
            let body = [question, why].filter { !$0.isEmpty }.joined(separator: " - ")
            return body.isEmpty ? lead : "\(lead): \(body)"
        })
        return rows
    }

    private func shortAnalysisText(_ value: String, limit: Int) -> String {
        let compact = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard compact.count > limit else { return compact }
        let cutoff = compact.index(compact.startIndex, offsetBy: max(0, limit - 1))
        return String(compact[..<cutoff]) + "..."
    }
}

private enum MediaEnableButtonMode {
    case state
    case action
}

private struct MediaEnableButton: View {
    @ObservedObject var library: LibraryEngine
    let item: MediaItemRecord
    var mode: MediaEnableButtonMode = .state
    var isFullWidth = false
    var isSubtleAction = false

    private var isMediaEnabled: Bool {
        !library.curation(for: item).rejected
    }

    private var title: String {
        switch mode {
        case .state:
            return isMediaEnabled ? "Story Input" : "In Library"
        case .action:
            return isMediaEnabled ? "Return to Library" : "Promote to Story Input"
        }
    }

    private var systemImage: String {
        switch mode {
        case .state:
            return isMediaEnabled ? "checkmark.circle.fill" : "circle"
        case .action:
            return isMediaEnabled ? "arrow.uturn.backward.circle" : "arrow.up.circle"
        }
    }

    var body: some View {
        if item.canBeEnabledContent {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    if isMediaEnabled {
                        library.setRejected(item.mediaId, true)
                    } else {
                        _ = library.enableContentItem(item.mediaId)
                    }
                }
            } label: {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: isFullWidth ? .infinity : nil)
            }
            .buttonStyle(MediaEnableButtonStyle(
                isMediaEnabled: isMediaEnabled,
                isFullWidth: isFullWidth,
                isSubtleAction: isSubtleAction
            ))
            .help(
                isMediaEnabled
                    ? "Return this image to the Library — it stops steering Story (tags and analysis are kept)"
                    : "Promote to Story Input — it analyzes automatically and steers Story, moods, and aesthetics"
            )
        }
    }
}

private struct MediaEnableButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isMediaEnabled: Bool
    var isFullWidth = false
    var isSubtleAction = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CanonType.interface(isSubtleAction ? 11 : 12, weight: isSubtleAction ? .medium : .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, isSubtleAction ? 9 : 10)
            .padding(.vertical, isSubtleAction ? 5 : 6)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(strokeColor)
            )
            .opacity(isEnabled ? 1 : 0.45)
    }

    private var foregroundColor: Color {
        if isSubtleAction {
            return CanonColor.muted.opacity(isMediaEnabled ? 0.78 : 0.72)
        }
        return isMediaEnabled ? CanonColor.bone : CanonColor.muted
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isSubtleAction {
            return isPressed ? CanonColor.mediaCardHover.opacity(0.68) : CanonColor.sidebar.opacity(0.18)
        }
        return isPressed ? CanonColor.mediaCardHover : CanonColor.sidebar
    }

    private var strokeColor: Color {
        if isSubtleAction {
            return CanonColor.hairlineDark.opacity(0.74)
        }
        return isMediaEnabled ? CanonColor.olive.opacity(0.82) : CanonColor.rust.opacity(0.64)
    }
}

private struct ZoomableImageScrollView: NSViewRepresentable {
    let path: String
    @Binding var zoomScale: CGFloat
    let minZoom: CGFloat
    let maxZoom: CGFloat
    var focusRect: CGRect?
    /// Visual tilt of the focus reticle, degrees, clockwise-positive on screen.
    var focusRotationDegrees: Double = 0
    var outpaintSourceRect: CGRect?
    var onImageClick: ((CGPoint) -> Void)?
    /// Reports a new normalized (0-1, top-left) focus rect while the corner grip is dragged.
    var onFocusResize: ((CGRect) -> Void)?
    /// Reports a new normalized (0-1, top-left) focus center while the reticle body is dragged.
    var onFocusMove: ((CGPoint) -> Void)?
    /// Reports the RAW rotation angle (degrees, clockwise-positive) while the
    /// rotate handle is dragged; the SwiftUI side snaps and clamps. nil hides
    /// the handle.
    var onFocusRotate: ((Double) -> Void)?
    /// Reports the normalized center of the locked source inset while it is dragged.
    var onOutpaintSourceMove: ((CGPoint) -> Void)?

    func makeNSView(context: Context) -> ImageZoomScrollView {
        let view = ImageZoomScrollView()
        view.minZoom = minZoom
        view.maxZoom = maxZoom
        view.onZoomChange = { value in
            DispatchQueue.main.async {
                zoomScale = value
            }
        }
        view.onImageClick = onImageClick
        view.onFocusResize = onFocusResize
        view.onFocusMove = onFocusMove
        view.onFocusRotate = onFocusRotate
        view.onOutpaintSourceMove = onOutpaintSourceMove
        view.focusRotationDegrees = focusRotationDegrees
        view.focusRect = focusRect
        view.outpaintSourceRect = outpaintSourceRect
        view.configure(path: path, zoomScale: zoomScale)
        return view
    }

    func updateNSView(_ view: ImageZoomScrollView, context: Context) {
        view.minZoom = minZoom
        view.maxZoom = maxZoom
        view.onZoomChange = { value in
            DispatchQueue.main.async {
                zoomScale = value
            }
        }
        view.onImageClick = onImageClick
        view.onFocusResize = onFocusResize
        view.onFocusMove = onFocusMove
        view.onFocusRotate = onFocusRotate
        view.onOutpaintSourceMove = onOutpaintSourceMove
        view.focusRotationDegrees = focusRotationDegrees
        view.focusRect = focusRect
        view.outpaintSourceRect = outpaintSourceRect
        view.configure(path: path, zoomScale: zoomScale)
    }
}

/// The clicked document point as a normalized (0-1, TOP-LEFT origin) image point.
/// The single place the AppKit y-up coordinate flips to image space.
func imageZoomNormalizedTopLeftPoint(documentPoint: CGPoint, imageFrame: CGRect) -> CGPoint? {
    guard imageFrame.width > 0, imageFrame.height > 0, imageFrame.contains(documentPoint) else {
        return nil
    }
    let x = (documentPoint.x - imageFrame.minX) / imageFrame.width
    let y = (documentPoint.y - imageFrame.minY) / imageFrame.height
    return CGPoint(x: min(max(x, 0), 1), y: min(max(1 - y, 0), 1))
}

/// A normalized (0-1, top-left origin) rect as a document-space frame over the image.
/// The single place image space flips back to the AppKit y-up coordinate.
func imageZoomFocusOverlayFrame(normalizedRect: CGRect, imageFrame: CGRect) -> CGRect {
    CGRect(
        x: imageFrame.minX + normalizedRect.minX * imageFrame.width,
        y: imageFrame.minY + (1 - normalizedRect.maxY) * imageFrame.height,
        width: normalizedRect.width * imageFrame.width,
        height: normalizedRect.height * imageFrame.height
    )
}

/// A document-space frame back to a normalized (0-1, top-left origin) rect — the inverse of
/// `imageZoomFocusOverlayFrame`, used when a drag resizes the focus reticle. Unclamped; the caller
/// bounds it to the image.
func imageZoomFocusReticleNormalizedRect(documentFrame frame: CGRect, imageFrame: CGRect) -> CGRect {
    guard imageFrame.width > 0, imageFrame.height > 0 else { return .zero }
    let width = frame.width / imageFrame.width
    let height = frame.height / imageFrame.height
    let minX = (frame.minX - imageFrame.minX) / imageFrame.width
    let maxY = 1 - (frame.minY - imageFrame.minY) / imageFrame.height
    return CGRect(x: minX, y: maxY - height, width: width, height: height)
}

/// A plain view that shows a fixed cursor on hover. Used for the focus reticle body (a move cursor)
/// and its corner resize handle (a crosshair); the drags themselves are handled by pan recognizers
/// owned by the enclosing scroll view.
private final class CursorTrackingView: NSView {
    var cursor: NSCursor = .arrow

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .cursorUpdate, .inVisibleRect],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }
}

/// Chrome that must never intercept the mouse (the rotate-handle stem); the
/// container's click recognizer still sees these frames and excludes them.
private final class HitTransparentView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class CursorImageView: NSImageView {
    var cursor: NSCursor = .arrow

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .cursorUpdate, .inVisibleRect],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }
}

/// Honest preview for generative perimeter pixels: the source image is drawn
/// separately above this subdued hatch, so no ungenerated content is implied.
private final class OutpaintGuideBackgroundView: NSView {
    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.035, alpha: 1).setFill()
        bounds.fill()
        let path = NSBezierPath()
        let spacing: CGFloat = 18
        var x = -bounds.height
        while x < bounds.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.line(to: CGPoint(x: x + bounds.height, y: bounds.height))
            x += spacing
        }
        path.lineWidth = 1
        NSColor(
            calibratedRed: 0xB6 / 255,
            green: 0x8A / 255,
            blue: 0x33 / 255,
            alpha: 0.18
        ).setStroke()
        path.stroke()
    }
}

private final class ImageZoomScrollView: NSScrollView {
    private struct ZoomAnchor {
        let ratio: CGPoint
        let viewportOffset: CGPoint
    }

    private let containerView = NSView()
    private let imageView = NSImageView()
    private let outpaintCanvasView = OutpaintGuideBackgroundView()
    private let outpaintSourceView = CursorImageView()
    private let focusReticleView = CursorTrackingView()
    private let focusResizeGrip = CursorTrackingView()
    private let focusRotateHandle = CursorTrackingView()
    private let focusRotateStem = HitTransparentView()
    /// Grip edge length in document points; the grip straddles the reticle's bottom-right corner.
    private let focusResizeGripSize: CGFloat = 16
    /// Rotate-handle knob diameter and its stem, in document points.
    private let focusRotateHandleSize: CGFloat = 14
    private let focusRotateStemLength: CGFloat = 16
    private let focusRotateStemWidth: CGFloat = 1.5
    /// Reticle center captured when a resize drag begins, so growth stays anchored on the focus.
    private var focusResizeAnchorCenter: CGPoint?
    /// Reticle center captured when a move drag begins, so translation is applied from a fixed origin.
    private var focusMoveAnchorCenter: CGPoint?
    /// Reticle center captured when a rotation drag begins; a fixed pivot keeps
    /// the reported angle stable even if SwiftUI re-pins the rect mid-drag.
    private var focusRotateAnchorCenter: CGPoint?
    private var outpaintMoveAnchorCenter: CGPoint?
    private var imagePath = ""
    private var imageSize = CGSize(width: 1, height: 1)
    private var isConfiguring = false

    var minZoom: CGFloat = 0.5
    var maxZoom: CGFloat = 5
    var zoomScale: CGFloat = 1
    var onZoomChange: ((CGFloat) -> Void)?
    /// Normalized (0-1, top-left origin) image point of a primary click inside the image.
    var onImageClick: ((CGPoint) -> Void)?
    /// Reports a new normalized (0-1, top-left) focus rect while the corner grip is dragged.
    var onFocusResize: ((CGRect) -> Void)?
    /// Reports a new normalized (0-1, top-left) focus center while the reticle body is dragged.
    var onFocusMove: ((CGPoint) -> Void)?
    /// Reports the RAW rotate-handle angle in degrees (clockwise-positive on
    /// screen); SwiftUI snaps/clamps it. nil hides the rotate handle.
    var onFocusRotate: ((Double) -> Void)?
    var onOutpaintSourceMove: ((CGPoint) -> Void)?
    /// Normalized (0-1, top-left origin) focus square drawn in document space; nil hides it.
    var focusRect: CGRect? {
        didSet {
            guard oldValue != focusRect else { return }
            layoutFocusReticle()
        }
    }
    /// Visual tilt of the reticle, degrees, clockwise-positive on screen.
    var focusRotationDegrees: Double = 0 {
        didSet {
            guard oldValue != focusRotationDegrees else { return }
            layoutFocusReticle()
        }
    }
    /// Normalized source inset inside the output frame; nil restores the normal
    /// full-image preview.
    var outpaintSourceRect: CGRect? {
        didSet {
            guard oldValue != outpaintSourceRect else { return }
            layoutOutpaintGuide()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    func configure(path: String, zoomScale proposedZoom: CGFloat) {
        isConfiguring = true
        defer { isConfiguring = false }

        let pathChanged = path != imagePath
        if pathChanged {
            imagePath = path
            imageView.image = NSImage(contentsOfFile: path)
            outpaintSourceView.image = imageView.image
            imageSize = imageView.image?.size ?? CGSize(width: 1, height: 1)
        }

        let nextZoom = clampedZoom(proposedZoom)
        if pathChanged {
            zoomScale = nextZoom
            layoutImage()
            centerImage()
        } else if abs(zoomScale - nextZoom) > 0.001 {
            setZoom(nextZoom, anchor: visibleCenterAnchor(), notify: false)
        } else {
            layoutImage()
        }
    }

    override func layout() {
        let anchor = visibleCenterAnchor()
        super.layout()
        layoutImage()
        restoreAnchor(anchor)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = min(max(event.scrollingDeltaY, -12), 12)
        guard abs(delta) > 0.01 else {
            super.scrollWheel(with: event)
            return
        }

        let anchor = pointerAnchor(for: event) ?? visibleCenterAnchor()
        let factor = CGFloat(exp(Double(delta) * 0.006))
        setZoom(clampedZoom(zoomScale * factor), anchor: anchor, notify: true)
    }

    private func setup() {
        drawsBackground = true
        backgroundColor = NSColor(
            calibratedRed: 0x0E / 255,
            green: 0x0D / 255,
            blue: 0x0A / 255,
            alpha: 1
        )
        borderType = .noBorder
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true

        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.magnificationFilter = .trilinear
        imageView.layer?.minificationFilter = .trilinear

        outpaintCanvasView.isHidden = true
        outpaintSourceView.imageAlignment = .alignCenter
        outpaintSourceView.imageScaling = .scaleAxesIndependently
        outpaintSourceView.wantsLayer = true
        outpaintSourceView.layer?.borderWidth = 1.5
        outpaintSourceView.layer?.borderColor = NSColor(
            calibratedRed: 0xB6 / 255,
            green: 0x8A / 255,
            blue: 0x33 / 255,
            alpha: 0.95
        ).cgColor
        outpaintSourceView.layer?.shadowColor = NSColor.black.cgColor
        outpaintSourceView.layer?.shadowOpacity = 0.72
        outpaintSourceView.layer?.shadowRadius = 3
        outpaintSourceView.layer?.shadowOffset = .zero
        outpaintSourceView.cursor = .openHand
        outpaintSourceView.isHidden = true
        outpaintSourceView.addGestureRecognizer(
            NSPanGestureRecognizer(target: self, action: #selector(handleOutpaintMove(_:)))
        )

        focusReticleView.wantsLayer = true
        focusReticleView.layer?.borderWidth = 1.5
        focusReticleView.layer?.borderColor = NSColor(
            calibratedRed: 0xB6 / 255,
            green: 0x8A / 255,
            blue: 0x33 / 255,
            alpha: 0.95
        ).cgColor
        focusReticleView.layer?.cornerRadius = 2
        focusReticleView.layer?.shadowColor = NSColor.black.cgColor
        focusReticleView.layer?.shadowOpacity = 0.6
        focusReticleView.layer?.shadowRadius = 2
        focusReticleView.layer?.shadowOffset = .zero
        focusReticleView.isHidden = true
        focusReticleView.cursor = .openHand
        focusReticleView.addGestureRecognizer(
            NSPanGestureRecognizer(target: self, action: #selector(handleFocusMove(_:)))
        )

        let brass = NSColor(
            calibratedRed: 0xB6 / 255,
            green: 0x8A / 255,
            blue: 0x33 / 255,
            alpha: 1
        )
        focusResizeGrip.wantsLayer = true
        focusResizeGrip.cursor = .crosshair
        focusResizeGrip.layer?.backgroundColor = brass.withAlphaComponent(0.95).cgColor
        focusResizeGrip.layer?.borderWidth = 1
        focusResizeGrip.layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        focusResizeGrip.layer?.cornerRadius = 3
        focusResizeGrip.layer?.shadowColor = NSColor.black.cgColor
        focusResizeGrip.layer?.shadowOpacity = 0.5
        focusResizeGrip.layer?.shadowRadius = 1.5
        focusResizeGrip.layer?.shadowOffset = .zero
        focusResizeGrip.addGestureRecognizer(
            NSPanGestureRecognizer(target: self, action: #selector(handleFocusResize(_:)))
        )

        focusRotateStem.wantsLayer = true
        focusRotateStem.layer?.backgroundColor = brass.withAlphaComponent(0.95).cgColor
        focusRotateStem.isHidden = true

        focusRotateHandle.wantsLayer = true
        focusRotateHandle.cursor = .crosshair
        focusRotateHandle.layer?.backgroundColor = brass.withAlphaComponent(0.95).cgColor
        focusRotateHandle.layer?.borderWidth = 1
        focusRotateHandle.layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        focusRotateHandle.layer?.cornerRadius = focusRotateHandleSize / 2
        focusRotateHandle.layer?.shadowColor = NSColor.black.cgColor
        focusRotateHandle.layer?.shadowOpacity = 0.5
        focusRotateHandle.layer?.shadowRadius = 1.5
        focusRotateHandle.layer?.shadowOffset = .zero
        focusRotateHandle.isHidden = true
        focusRotateHandle.addGestureRecognizer(
            NSPanGestureRecognizer(target: self, action: #selector(handleFocusRotate(_:)))
        )

        containerView.addSubview(imageView)
        containerView.addSubview(outpaintCanvasView)
        containerView.addSubview(outpaintSourceView)
        containerView.addSubview(focusReticleView)
        containerView.addSubview(focusResizeGrip)
        containerView.addSubview(focusRotateStem)
        containerView.addSubview(focusRotateHandle)
        containerView.addGestureRecognizer(
            NSClickGestureRecognizer(target: self, action: #selector(handleImageClick(_:)))
        )
        documentView = containerView
    }

    @objc private func handleImageClick(_ recognizer: NSClickGestureRecognizer) {
        guard let onImageClick else { return }
        let documentPoint = recognizer.location(in: containerView)
        if !outpaintSourceView.isHidden, outpaintSourceView.frame.contains(documentPoint) { return }
        // A tap that lands on the resize grip is a resize intent, not a new focus point.
        if !focusResizeGrip.isHidden, focusResizeGrip.frame.contains(documentPoint) { return }
        // Likewise the rotate handle and its stem are rotation chrome, not focus targets.
        if !focusRotateHandle.isHidden, focusRotateHandle.frame.contains(documentPoint) { return }
        if !focusRotateStem.isHidden, focusRotateStem.frame.contains(documentPoint) { return }
        guard let normalized = imageZoomNormalizedTopLeftPoint(
            documentPoint: documentPoint,
            imageFrame: imageView.frame
        ) else { return }
        onImageClick(normalized)
    }

    /// The reticle center in document space, derived from the source of truth
    /// (`focusRect`) rather than the view — `frame` reads are unreliable while
    /// the reticle carries a `frameCenterRotation`.
    private func focusReticleOverlayCenter() -> CGPoint? {
        guard let focusRect, imageView.frame.width > 0, imageView.frame.height > 0 else { return nil }
        let frame = imageZoomFocusOverlayFrame(normalizedRect: focusRect, imageFrame: imageView.frame)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Grows/shrinks the focus reticle symmetrically about its center as the corner grip is dragged.
    /// The reported rect is unclamped square-in-screen; SwiftUI clamps it to the min/max edge and
    /// pushes the result back through `focusRect`.
    @objc private func handleFocusResize(_ recognizer: NSPanGestureRecognizer) {
        guard let onFocusResize, imageView.frame.width > 0, imageView.frame.height > 0 else { return }
        let imageFrame = imageView.frame
        let center: CGPoint
        if recognizer.state == .began || focusResizeAnchorCenter == nil {
            center = focusReticleOverlayCenter() ?? CGPoint(x: focusReticleView.frame.midX, y: focusReticleView.frame.midY)
            focusResizeAnchorCenter = center
        } else {
            center = focusResizeAnchorCenter ?? CGPoint(x: focusReticleView.frame.midX, y: focusReticleView.frame.midY)
        }

        let pointer = recognizer.location(in: containerView)
        // Measure the drag along the reticle's LOCAL (tilted) axes so growth
        // follows the drawn rectangle; the identity transform when level.
        let radians = CGFloat(focusRotationDegrees) * .pi / 180
        let dx = pointer.x - center.x
        let dy = pointer.y - center.y
        let localX = dx * cos(radians) - dy * sin(radians)
        let localY = dx * sin(radians) + dy * cos(radians)
        let halfEdge = max(abs(localX), abs(localY))
        let documentFrame = CGRect(
            x: center.x - halfEdge,
            y: center.y - halfEdge,
            width: halfEdge * 2,
            height: halfEdge * 2
        )
        onFocusResize(imageZoomFocusReticleNormalizedRect(documentFrame: documentFrame, imageFrame: imageFrame))

        if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
            focusResizeAnchorCenter = nil
        }
    }

    /// Rotates the reticle about its center while the rotate handle is dragged.
    /// The pivot is captured at `.began` so mid-drag re-pinning can't wobble the
    /// angle; the RAW angle is reported and SwiftUI snaps/clamps it.
    @objc private func handleFocusRotate(_ recognizer: NSPanGestureRecognizer) {
        guard let onFocusRotate, imageView.frame.width > 0, imageView.frame.height > 0 else { return }
        let center: CGPoint
        if recognizer.state == .began || focusRotateAnchorCenter == nil {
            center = focusReticleOverlayCenter() ?? CGPoint(x: focusReticleView.frame.midX, y: focusReticleView.frame.midY)
            focusRotateAnchorCenter = center
        } else {
            center = focusRotateAnchorCenter ?? CGPoint(x: focusReticleView.frame.midX, y: focusReticleView.frame.midY)
        }

        let pointer = recognizer.location(in: containerView)
        let dx = pointer.x - center.x
        let dy = pointer.y - center.y
        // Within a few points of the pivot the angle is numerically meaningless.
        if dx * dx + dy * dy >= 36 {
            // Straight up from the center is 0°; right of vertical tilts the top
            // edge clockwise — the image-space clockwise-positive convention.
            onFocusRotate(Double(atan2(dx, dy)) * 180 / .pi)
        }

        if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
            focusRotateAnchorCenter = nil
        }
    }

    /// Drags the whole reticle to a new location, translating its center from where the drag began.
    /// The reported center is clamped to the image; SwiftUI keeps the rect pinned inside the frame.
    @objc private func handleFocusMove(_ recognizer: NSPanGestureRecognizer) {
        guard let onFocusMove, imageView.frame.width > 0, imageView.frame.height > 0 else { return }
        let imageFrame = imageView.frame
        let anchor: CGPoint
        if recognizer.state == .began || focusMoveAnchorCenter == nil {
            anchor = focusReticleOverlayCenter() ?? CGPoint(x: focusReticleView.frame.midX, y: focusReticleView.frame.midY)
            focusMoveAnchorCenter = anchor
        } else {
            anchor = focusMoveAnchorCenter ?? CGPoint(x: focusReticleView.frame.midX, y: focusReticleView.frame.midY)
        }

        let translation = recognizer.translation(in: containerView)
        let centerDoc = CGPoint(x: anchor.x + translation.x, y: anchor.y + translation.y)
        let nx = (centerDoc.x - imageFrame.minX) / imageFrame.width
        let nyTop = 1 - (centerDoc.y - imageFrame.minY) / imageFrame.height
        onFocusMove(CGPoint(x: min(max(nx, 0), 1), y: min(max(nyTop, 0), 1)))

        if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
            focusMoveAnchorCenter = nil
        }
    }

    @objc private func handleOutpaintMove(_ recognizer: NSPanGestureRecognizer) {
        guard let onOutpaintSourceMove, imageView.frame.width > 0, imageView.frame.height > 0 else { return }
        if recognizer.state == .began {
            outpaintSourceView.cursor = .closedHand
            NSCursor.closedHand.set()
        }
        let imageFrame = imageView.frame
        let anchor: CGPoint
        if recognizer.state == .began || outpaintMoveAnchorCenter == nil {
            anchor = CGPoint(x: outpaintSourceView.frame.midX, y: outpaintSourceView.frame.midY)
            outpaintMoveAnchorCenter = anchor
        } else {
            anchor = outpaintMoveAnchorCenter
                ?? CGPoint(x: outpaintSourceView.frame.midX, y: outpaintSourceView.frame.midY)
        }
        let translation = recognizer.translation(in: containerView)
        let center = CGPoint(x: anchor.x + translation.x, y: anchor.y + translation.y)
        let nx = (center.x - imageFrame.minX) / imageFrame.width
        let ny = 1 - (center.y - imageFrame.minY) / imageFrame.height
        onOutpaintSourceMove(CGPoint(x: nx, y: ny))

        if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
            outpaintMoveAnchorCenter = nil
            outpaintSourceView.cursor = .openHand
        }
    }

    private func layoutFocusReticle() {
        guard let focusRect, imageView.frame.width > 0, imageView.frame.height > 0 else {
            focusReticleView.isHidden = true
            focusResizeGrip.isHidden = true
            focusRotateHandle.isHidden = true
            focusRotateStem.isHidden = true
            return
        }
        focusReticleView.isHidden = false
        let reticleFrame = imageZoomFocusOverlayFrame(
            normalizedRect: focusRect,
            imageFrame: imageView.frame
        )
        // `frame` is unreliable while a view carries a rotation: always level
        // the view, size it, then re-apply the tilt (which pivots on the center).
        focusReticleView.frameCenterRotation = 0
        focusReticleView.frame = reticleFrame
        focusReticleView.frameCenterRotation = -CGFloat(focusRotationDegrees)

        // Local reticle offsets in y-up document space: +x along the (tilted)
        // top edge, +y toward the reticle's visual top.
        let center = CGPoint(x: reticleFrame.midX, y: reticleFrame.midY)
        let radians = CGFloat(focusRotationDegrees) * .pi / 180
        func anchorPoint(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + dx * cos(radians) + dy * sin(radians),
                y: center.y - dx * sin(radians) + dy * cos(radians)
            )
        }

        // The grip straddles the reticle's visual bottom-right corner — local
        // (+w/2, −h/2), i.e. (maxX, minY) when level — wherever the tilt puts it.
        focusResizeGrip.isHidden = onFocusResize == nil
        let gripCenter = anchorPoint(reticleFrame.width / 2, -reticleFrame.height / 2)
        focusResizeGrip.frame = CGRect(
            x: gripCenter.x - focusResizeGripSize / 2,
            y: gripCenter.y - focusResizeGripSize / 2,
            width: focusResizeGripSize,
            height: focusResizeGripSize
        )

        // Rotate handle: a brass knob on a short stem rising from the top
        // edge's midpoint, riding the tilt.
        let showsRotation = onFocusRotate != nil
        focusRotateStem.isHidden = !showsRotation
        focusRotateHandle.isHidden = !showsRotation
        guard showsRotation else { return }
        let stemCenter = anchorPoint(0, reticleFrame.height / 2 + focusRotateStemLength / 2)
        focusRotateStem.frameCenterRotation = 0
        focusRotateStem.frame = CGRect(
            x: stemCenter.x - focusRotateStemWidth / 2,
            y: stemCenter.y - focusRotateStemLength / 2,
            width: focusRotateStemWidth,
            height: focusRotateStemLength
        )
        focusRotateStem.frameCenterRotation = -CGFloat(focusRotationDegrees)
        let handleCenter = anchorPoint(
            0,
            reticleFrame.height / 2 + focusRotateStemLength + focusRotateHandleSize / 2
        )
        focusRotateHandle.frame = CGRect(
            x: handleCenter.x - focusRotateHandleSize / 2,
            y: handleCenter.y - focusRotateHandleSize / 2,
            width: focusRotateHandleSize,
            height: focusRotateHandleSize
        )
    }

    private func layoutOutpaintGuide() {
        guard let outpaintSourceRect, imageView.frame.width > 0, imageView.frame.height > 0 else {
            outpaintCanvasView.isHidden = true
            outpaintSourceView.isHidden = true
            return
        }
        outpaintCanvasView.isHidden = false
        outpaintSourceView.isHidden = false
        outpaintCanvasView.frame = imageView.frame
        outpaintSourceView.frame = imageZoomFocusOverlayFrame(
            normalizedRect: outpaintSourceRect,
            imageFrame: imageView.frame
        )
    }

    private func setZoom(_ nextZoom: CGFloat, anchor: ZoomAnchor?, notify: Bool) {
        let clamped = clampedZoom(nextZoom)
        guard abs(zoomScale - clamped) > 0.001 else { return }

        let zoomAnchor = anchor ?? visibleCenterAnchor()
        zoomScale = clamped
        layoutImage()
        restoreAnchor(zoomAnchor)

        if notify && !isConfiguring {
            onZoomChange?(clamped)
        }
    }

    private func layoutImage() {
        let viewport = contentView.bounds.size
        guard imageSize.width > 0, imageSize.height > 0, viewport.width > 0, viewport.height > 0 else {
            return
        }

        let fitScale = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
        let displaySize = CGSize(
            width: max(1, imageSize.width * fitScale * zoomScale),
            height: max(1, imageSize.height * fitScale * zoomScale)
        )
        let documentSize = CGSize(
            width: max(viewport.width, displaySize.width),
            height: max(viewport.height, displaySize.height)
        )

        containerView.frame = CGRect(origin: .zero, size: documentSize)
        imageView.frame = CGRect(
            x: (documentSize.width - displaySize.width) / 2,
            y: (documentSize.height - displaySize.height) / 2,
            width: displaySize.width,
            height: displaySize.height
        )
        layoutFocusReticle()
        layoutOutpaintGuide()
    }

    private func centerImage() {
        let imageFrame = imageView.frame
        let origin = CGPoint(
            x: imageFrame.midX - contentView.bounds.width / 2,
            y: imageFrame.midY - contentView.bounds.height / 2
        )
        scroll(to: boundedScrollOrigin(origin))
    }

    private func visibleCenterAnchor() -> ZoomAnchor {
        ZoomAnchor(
            ratio: visibleCenterRatio(),
            viewportOffset: CGPoint(
                x: contentView.bounds.width / 2,
                y: contentView.bounds.height / 2
            )
        )
    }

    private func visibleCenterRatio() -> CGPoint {
        guard imageView.frame.width > 0, imageView.frame.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        return boundedRatio(CGPoint(
            x: (center.x - imageView.frame.minX) / imageView.frame.width,
            y: (center.y - imageView.frame.minY) / imageView.frame.height
        ))
    }

    private func pointerAnchor(for event: NSEvent) -> ZoomAnchor? {
        guard imageView.frame.width > 0, imageView.frame.height > 0 else {
            return nil
        }

        let windowPoint = event.locationInWindow
        let localPoint = convert(windowPoint, from: nil)
        let documentPoint = containerView.convert(localPoint, from: self)
        guard imageView.frame.contains(documentPoint) else {
            return nil
        }

        return ZoomAnchor(
            ratio: boundedRatio(CGPoint(
                x: (documentPoint.x - imageView.frame.minX) / imageView.frame.width,
                y: (documentPoint.y - imageView.frame.minY) / imageView.frame.height
            )),
            viewportOffset: boundedViewportOffset(CGPoint(
                x: documentPoint.x - contentView.bounds.minX,
                y: documentPoint.y - contentView.bounds.minY
            ))
        )
    }

    private func restoreAnchor(_ anchor: ZoomAnchor) {
        let target = CGPoint(
            x: imageView.frame.minX + imageView.frame.width * anchor.ratio.x,
            y: imageView.frame.minY + imageView.frame.height * anchor.ratio.y
        )
        let origin = CGPoint(
            x: target.x - anchor.viewportOffset.x,
            y: target.y - anchor.viewportOffset.y
        )
        scroll(to: boundedScrollOrigin(origin))
    }

    private func scroll(to origin: CGPoint) {
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }

    private func boundedScrollOrigin(_ origin: CGPoint) -> CGPoint {
        let documentSize = documentView?.frame.size ?? .zero
        return CGPoint(
            x: min(max(origin.x, 0), max(documentSize.width - contentView.bounds.width, 0)),
            y: min(max(origin.y, 0), max(documentSize.height - contentView.bounds.height, 0))
        )
    }

    private func boundedViewportOffset(_ offset: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(offset.x, 0), contentView.bounds.width),
            y: min(max(offset.y, 0), contentView.bounds.height)
        )
    }

    private func boundedRatio(_ ratio: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(ratio.x, 0), 1),
            y: min(max(ratio.y, 0), 1)
        )
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, minZoom), maxZoom)
    }
}

private struct MediaEmptyPanel: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(CanonType.editorial(18, weight: .semibold))
                .foregroundStyle(CanonColor.bone)
            Text(subtitle)
                .font(CanonType.interface(12))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.mediaCard.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlineDark)
        )
    }
}

private struct VideoSourceTrayView: View {
    @ObservedObject var library: LibraryEngine
    let onOpenStudio: (MediaItemRecord) -> Void

    @State private var isHiddenVideosExpanded = false

    var body: some View {
        let layout = library.videoTrayLayoutForDisplay
        VStack(alignment: .leading, spacing: 0) {
            trayHeader
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if layout.visibleGroups.isEmpty {
                        MediaEmptyPanel(
                            title: "No video sources",
                            subtitle: "Add video files to trim and pull stills."
                        )
                    } else {
                        ForEach(layout.visibleGroups) { group in
                            VideoSourceCard(
                                library: library,
                                video: group.parent,
                                onOpenStudio: onOpenStudio
                            )
                            ForEach(group.trims) { trim in
                                VideoTrimRowView(
                                    library: library,
                                    trim: trim,
                                    onOpenStudio: onOpenStudio
                                )
                                .padding(.leading, 18)
                            }
                            ForEach(group.looks) { look in
                                VideoLookRowView(
                                    library: library,
                                    look: look,
                                    onOpenStudio: onOpenStudio
                                )
                                .padding(.leading, 18)
                            }
                        }
                    }

                    hiddenVideosSection(layout.hiddenItems)
                }
                .padding(14)
            }
        }
        .background(CanonColor.sidebar)
    }

    private var trayHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Video Sources")
                .font(CanonType.editorial(22, weight: .semibold))
                .foregroundStyle(CanonColor.bone)
            Text("Scrub, trim, and pull stills from your videos. Right-click one to place its footage in a shot — or drag it from the Scenes tab's Footage panel.")
                .font(CanonType.interface(12))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func hiddenVideosSection(_ hiddenItems: [MediaItemRecord]) -> some View {
        if !hiddenItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    isHiddenVideosExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isHiddenVideosExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                        Text("Hidden Videos (\(hiddenItems.count))")
                            .font(CanonType.archive(11, weight: .semibold))
                    }
                    .foregroundStyle(CanonColor.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isHiddenVideosExpanded {
                    ForEach(hiddenItems) { item in
                        HStack(spacing: 8) {
                            ThumbnailImage(path: item.thumbnailPath, kind: .video)
                                .frame(width: 46, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.filename)
                                    .font(CanonType.interface(11))
                                    .foregroundStyle(CanonColor.bone)
                                    .lineLimit(1)
                                Text(item.durationSeconds?.durationLabel ?? "Video")
                                    .font(CanonType.archive(9, weight: .medium))
                                    .foregroundStyle(CanonColor.muted)
                            }
                            Spacer(minLength: 0)
                            Button("Unhide") {
                                library.setRejected(item.mediaId, false)
                            }
                            .buttonStyle(CanonSecondaryButtonStyle())
                        }
                        .padding(6)
                        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 7))
                        .opacity(0.74)
                    }
                }
            }
            .padding(.top, 6)
        }
    }
}

private struct VideoSourceCard: View {
    @ObservedObject var library: LibraryEngine
    let video: MediaItemRecord
    let onOpenStudio: (MediaItemRecord) -> Void

    private var frames: [MediaItemRecord] {
        library.extractedFrames(for: video.mediaId)
    }

    private var trims: [MediaItemRecord] {
        library.trims(for: video.mediaId)
    }

    private var extractionState: VideoFrameExtractionState {
        library.frameExtractionState(for: video.mediaId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader
            existingFramesNote
        }
        .padding(10)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlineDark)
        )
        .draggable(MediaIDTransfer(mediaId: video.mediaId))
        .contextMenu {
            MediaUseMenu(
                library: library,
                item: video,
                onOpenStudio: { onOpenStudio(video) }
            )
        }
    }

    private var cardHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                ThumbnailImage(path: video.thumbnailPath, kind: .video)
                    .frame(width: 82, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(CanonColor.hairlineDark)
                    )
                    .overlay(alignment: .bottomLeading) {
                        if video.isPortrait {
                            Text("9:16")
                                .font(CanonType.archive(8, weight: .semibold))
                                .foregroundStyle(CanonColor.bone)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(CanonColor.room.opacity(0.78), in: RoundedRectangle(cornerRadius: 3))
                                .padding(3)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.filename)
                        .font(CanonType.interface(12, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                        .lineLimit(2)
                    Text(video.durationSeconds?.durationLabel ?? "Video")
                        .font(CanonType.archive(10, weight: .medium))
                        .foregroundStyle(CanonColor.muted)
                    if !frames.isEmpty {
                        Text("\(frames.count) captured frames")
                            .font(CanonType.archive(10, weight: .medium))
                            .foregroundStyle(CanonColor.olive)
                    }
                    if !trims.isEmpty {
                        Text("\(trims.count) trim\(trims.count == 1 ? "" : "s")")
                            .font(CanonType.archive(10, weight: .medium))
                            .foregroundStyle(CanonColor.olive)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    onOpenStudio(video)
                } label: {
                    Label("Open Studio", systemImage: "rectangle.stack.badge.play")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CanonSecondaryButtonStyle(isFullWidth: true))

                Button {
                    library.setRejected(video.mediaId, true)
                } label: {
                    Image(systemName: "eye.slash")
                        .frame(width: 28)
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Hide from tray")

                Button {
                    library.revealInFinder(video)
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 28)
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Open Source in Finder")
            }
        }
    }

    @ViewBuilder
    private var existingFramesNote: some View {
        if !extractionState.errorMessage.isEmpty {
            Label(extractionState.errorMessage, systemImage: "exclamationmark.triangle")
                .font(CanonType.interface(12))
                .foregroundStyle(CanonColor.rust)
                .fixedSize(horizontal: false, vertical: true)
        } else if !frames.isEmpty {
            Text("Existing captures remain available in enabled media when added.")
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A trim nested under its parent video in the tray: a compact, draggable row
/// that opens in the same Studio (a trim is a full video asset in its own right).
private struct VideoTrimRowView: View {
    @ObservedObject var library: LibraryEngine
    let trim: MediaItemRecord
    let onOpenStudio: (MediaItemRecord) -> Void

    private var rangeLabel: String {
        if let start = trim.sourceTimestampSeconds, let duration = trim.durationSeconds {
            return videoTrimDisplayLabel(range: VideoTrimRange(startSeconds: start, endSeconds: start + duration))
        }
        return trim.durationSeconds?.durationLabel ?? "Trim"
    }

    var body: some View {
        HStack(spacing: 8) {
            ThumbnailImage(path: trim.thumbnailPath, kind: .video)
                .frame(width: 58, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(CanonColor.hairlineDark)
                )
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "scissors")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                        .padding(3)
                        .background(CanonColor.room.opacity(0.78), in: RoundedRectangle(cornerRadius: 3))
                        .padding(2)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(trim.filename)
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                    .lineLimit(1)
                Text(rangeLabel)
                    .font(CanonType.archive(10, weight: .medium))
                    .foregroundStyle(CanonColor.olive)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                onOpenStudio(trim)
            } label: {
                Image(systemName: "rectangle.stack.badge.play")
                    .frame(width: 24)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Open Studio")

            Button {
                library.setRejected(trim.mediaId, true)
            } label: {
                Image(systemName: "eye.slash")
                    .frame(width: 24)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Hide from tray")

            Button {
                library.revealInFinder(trim)
            } label: {
                Image(systemName: "folder")
                    .frame(width: 24)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Show in Finder")
        }
        .padding(8)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(CanonColor.hairlineDark)
        )
        .draggable(MediaIDTransfer(mediaId: trim.mediaId))
        .contextMenu {
            MediaUseMenu(
                library: library,
                item: trim,
                onOpenStudio: { onOpenStudio(trim) }
            )
        }
    }
}

/// A Lucy Clip Look nested under its source in the tray: restyled 720p
/// picture carrying the original range's audio — a full footage asset in its
/// own right, draggable into shots like any clip.
private struct VideoLookRowView: View {
    @ObservedObject var library: LibraryEngine
    let look: MediaItemRecord
    let onOpenStudio: (MediaItemRecord) -> Void

    private var rangeLabel: String {
        if let start = look.sourceTimestampSeconds, let duration = look.durationSeconds {
            let range = VideoTrimRange(startSeconds: start, endSeconds: start + duration)
            return "Look · \(videoTrimDisplayLabel(range: range)) · 720p"
        }
        return "Look · \(look.durationSeconds?.durationLabel ?? "720p")"
    }

    var body: some View {
        HStack(spacing: 8) {
            ThumbnailImage(path: look.thumbnailPath, kind: .video)
                .frame(width: 58, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(CanonColor.hairlineDark)
                )
                .overlay(alignment: .bottomLeading) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                        .padding(3)
                        .background(CanonColor.room.opacity(0.78), in: RoundedRectangle(cornerRadius: 3))
                        .padding(2)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(look.filename)
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                    .lineLimit(1)
                Text(rangeLabel)
                    .font(CanonType.archive(10, weight: .medium))
                    .foregroundStyle(CanonColor.olive)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button {
                onOpenStudio(look)
            } label: {
                Image(systemName: "rectangle.stack.badge.play")
                    .frame(width: 24)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Open Studio")

            Button {
                library.setRejected(look.mediaId, true)
            } label: {
                Image(systemName: "eye.slash")
                    .frame(width: 24)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Hide from tray")

            Button {
                library.revealInFinder(look)
            } label: {
                Image(systemName: "folder")
                    .frame(width: 24)
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .help("Show in Finder")
        }
        .padding(8)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(CanonColor.hairlineDark)
        )
        .draggable(MediaIDTransfer(mediaId: look.mediaId))
        .contextMenu {
            MediaUseMenu(
                library: library,
                item: look,
                onOpenStudio: { onOpenStudio(look) }
            )
        }
    }
}

private struct VideoStudioView: View {
    @ObservedObject var library: LibraryEngine
    let video: MediaItemRecord
    @Binding var timestampSeconds: Double
    /// Click-to-watch entries (Creations) start playing on open; editing
    /// entries (tray, scrub) keep opening paused.
    var autoPlayOnOpen: Bool = false
    let onClose: () -> Void

    @State private var trimStartSeconds: Double = 0
    @State private var trimEndSeconds: Double = 0
    @State private var isPlaying = false
    @State private var isLoopingPreview = false
    @State private var savedTrimConfirmation = ""
    // Whole-asset Restyle composer state, hoisted so the style picker can run
    // as a Studio-level sheet (the proven popover→sheet→reopen flow).
    @State private var isRestylePopoverPresented = false
    @State private var isRestyleStyleSheetPresented = false
    @State private var restylePrompt = ""
    @State private var restyleEnhancePrompt = true
    @State private var restyleStyleSelection: ShotLookStyleSelection?

    /// Any playback running — free play or the Trim loop preview. The one
    /// transport button (and Space) pauses whichever is active.
    private var isTransportActive: Bool {
        isPlaying || isLoopingPreview
    }

    private var durationSeconds: Double {
        max(video.durationSeconds ?? 0, 0)
    }

    private var clampedTimestamp: Double {
        min(max(timestampSeconds, 0), max(durationSeconds - 0.01, 0))
    }

    private var stepSeconds: Double {
        0.1
    }

    private var trimRange: VideoTrimRange {
        VideoTrimRange.clamped(
            start: trimStartSeconds,
            end: trimEndSeconds,
            videoDurationSeconds: durationSeconds
        )
    }

    private var activeLoopRange: ClosedRange<Double>? {
        let range = trimRange
        guard range.durationSeconds > 0.05 else { return nil }
        return range.startSeconds...range.endSeconds
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)

            GeometryReader { geometry in
                ZStack {
                    if video.isPortrait {
                        BlurFillVideoBackdropView(
                            path: video.path,
                            timestampSeconds: clampedTimestamp,
                            loopRange: activeLoopRange,
                            isLoopPlaying: isLoopingPreview,
                            isFreePlaying: isPlaying
                        )
                    }
                    ScrubVideoPreview(
                        path: video.path,
                        timestampSeconds: $timestampSeconds,
                        loopRange: activeLoopRange,
                        isLoopPlaying: isLoopingPreview,
                        isFreePlaying: isPlaying,
                        onPlaybackTime: { seconds in
                            timestampSeconds = min(max(seconds, 0), max(durationSeconds - 0.01, 0))
                        },
                        onPlaybackEnded: {
                            isPlaying = false
                        }
                    )
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(CanonColor.room)
            }
            .background(CanonColor.room)
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            studioControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CanonColor.room.opacity(0.98))
        .onAppear {
            timestampSeconds = clampedTimestamp
            seedTrimRange()
            if autoPlayOnOpen {
                isPlaying = true
            }
        }
        .onChange(of: video.mediaId) { _, _ in
            timestampSeconds = min(max(durationSeconds * 0.12, 0), max(durationSeconds - 0.01, 0))
            isPlaying = false
            isLoopingPreview = false
            savedTrimConfirmation = ""
            seedTrimRange()
        }
        .onChange(of: trimStartSeconds) { _, _ in
            savedTrimConfirmation = ""
        }
        .onChange(of: trimEndSeconds) { _, _ in
            savedTrimConfirmation = ""
        }
    }

    private func seedTrimRange() {
        trimStartSeconds = 0
        trimEndSeconds = durationSeconds
    }

    private func togglePlayback() {
        if isTransportActive {
            isPlaying = false
            isLoopingPreview = false
            return
        }
        if clampedTimestamp >= max(durationSeconds - 0.05, 0) {
            timestampSeconds = 0
        }
        isPlaying = true
    }

    private var playPauseButton: some View {
        Button {
            togglePlayback()
        } label: {
            Image(systemName: isTransportActive ? "pause.fill" : "play.fill")
                .frame(width: 34)
        }
        .buttonStyle(CanonSecondaryButtonStyle())
        .disabled(durationSeconds <= 0)
        .keyboardShortcut(.space, modifiers: [])
        .help(isTransportActive ? "Pause (Space)" : "Play (Space)")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Video Studio")
                    .font(CanonType.editorial(25, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text(video.filename)
                    .font(CanonType.archive(11))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)

            Text("\(clampedTimestamp.durationLabel) / \(durationSeconds.durationLabel)")
                .font(CanonType.archive(11, weight: .medium))
                .foregroundStyle(CanonColor.muted)
                .lineLimit(1)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CanonUtilityButtonStyle())
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close Video Studio")
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(CanonColor.sidebar)
    }

    private var studioControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            TrimRangeBar(
                stripPath: video.videoStripPath,
                durationSeconds: durationSeconds,
                startSeconds: $trimStartSeconds,
                endSeconds: $trimEndSeconds,
                playheadSeconds: clampedTimestamp,
                onScrub: { seconds in
                    isPlaying = false
                    isLoopingPreview = false
                    timestampSeconds = min(max(seconds, 0), max(durationSeconds - 0.01, 0))
                }
            )
            .frame(height: 52)
            .disabled(durationSeconds <= 0)

            HStack(spacing: 10) {
                playPauseButton

                Button {
                    isLoopingPreview = false
                    step(by: -stepSeconds)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 28)
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(durationSeconds <= 0)
                .help("Step the playhead back 0.1s")

                Button {
                    isLoopingPreview = false
                    step(by: stepSeconds)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 28)
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(durationSeconds <= 0)
                .help("Step the playhead forward 0.1s")

                HStack(spacing: 5) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(CanonColor.bone)
                    Text(videoTrimPlayheadLabel(clampedTimestamp))
                        .font(CanonType.archive(11, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .help("Playhead — scrub the strip or step to move it")

                Rectangle()
                    .fill(CanonColor.hairlineDark)
                    .frame(width: 1, height: 18)

                Button("Set In") {
                    trimStartSeconds = min(clampedTimestamp, trimEndSeconds)
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(durationSeconds <= 0)
                .help("Set the in point to the playhead")

                Button("Set Out") {
                    trimEndSeconds = max(clampedTimestamp, trimStartSeconds)
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(durationSeconds <= 0)
                .help("Set the out point to the playhead")

                Text(videoTrimDisplayLabel(range: trimRange))
                    .font(CanonType.archive(11, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    if isLoopingPreview {
                        isLoopingPreview = false
                    } else {
                        isPlaying = false
                        isLoopingPreview = true
                    }
                } label: {
                    Label(
                        isLoopingPreview ? "Stop Preview" : "Preview Cut",
                        systemImage: isLoopingPreview ? "stop.circle" : "play.circle"
                    )
                }
                .buttonStyle(CanonSecondaryButtonStyle())
                .disabled(activeLoopRange == nil)
                .help("Loop the selected range")
            }

            videoActionRow

            if !trimRange.isSaveable {
                Text("Selection must be at least \(String(format: "%.1f", VideoTrimRange.minimumTrimSeconds))s")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.rust)
            } else if !savedTrimConfirmation.isEmpty {
                Text(savedTrimConfirmation)
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.olive)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(CanonColor.sidebar)
    }

    private var videoActionRow: some View {
        HStack(spacing: 10) {
            Button {
                isRestylePopoverPresented = true
            } label: {
                Label("Restyle", systemImage: "paintpalette")
            }
            .buttonStyle(CanonSecondaryButtonStyle())
            .disabled(durationSeconds <= 0)
            .help("AI-restyle this whole video — the result nests under it in the tray, audio kept")
            .popover(isPresented: $isRestylePopoverPresented, arrowEdge: .top) {
                MediaLookComposerPopover(
                    library: library,
                    item: video,
                    prompt: $restylePrompt,
                    enhancePrompt: $restyleEnhancePrompt,
                    styleSelection: $restyleStyleSelection,
                    onBrowseStyles: {
                        isRestylePopoverPresented = false
                        isRestyleStyleSheetPresented = true
                    },
                    onSubmit: { provider in
                        isRestylePopoverPresented = false
                        library.startMediaLookRestyle(
                            mediaId: video.mediaId,
                            prompt: restylePrompt,
                            enhancePrompt: restyleEnhancePrompt,
                            seed: 0,
                            style: restyleStyleSelection,
                            provider: provider
                        )
                    }
                )
            }
            .sheet(isPresented: $isRestyleStyleSheetPresented, onDismiss: {
                isRestylePopoverPresented = true
            }) {
                ShotLookStylePickerSheet(
                    initialSelection: restyleStyleSelection,
                    onApply: { selection in
                        restyleStyleSelection = selection
                        isRestyleStyleSheetPresented = false
                    },
                    onCancel: { isRestyleStyleSheetPresented = false }
                )
            }

            Spacer(minLength: 0)

            Button {
                isPlaying = false
                isLoopingPreview = false
                Task {
                    await library.addFrameToMedia(from: video, timestampSeconds: clampedTimestamp)
                }
            } label: {
                Label(
                    library.isAddingFrameToMedia ? "Grabbing Frame…" : "Grab Frame",
                    systemImage: "plus.rectangle.on.rectangle"
                )
                .frame(minWidth: 130)
            }
            .buttonStyle(CanonSecondaryButtonStyle())
            .disabled(library.isAddingFrameToMedia || durationSeconds <= 0)
            .help("Save the image at the current playhead as a Frame-ready Media item")

            Button {
                isPlaying = false
                isLoopingPreview = false
                Task {
                    if let saved = await library.saveVideoTrim(
                        from: video,
                        startSeconds: trimRange.startSeconds,
                        endSeconds: trimRange.endSeconds
                    ) {
                        savedTrimConfirmation = "Saved \(saved.filename) in Footage under this source — it is ready to drag into a Shot"
                    }
                }
            } label: {
                Label(
                    library.isSavingVideoTrim ? "Saving Cut…" : "Save Cut",
                    systemImage: "scissors"
                )
                .frame(minWidth: 130)
            }
            .buttonStyle(CanonPrimaryButtonStyle())
            .disabled(library.isSavingVideoTrim || !trimRange.isSaveable)
            .help("Save the selected in/out range as durable Footage")
        }
    }

    private func step(by delta: Double) {
        isPlaying = false
        timestampSeconds = min(max(clampedTimestamp + delta, 0), max(durationSeconds - 0.01, 0))
    }
}

private struct ExtractedFrameTileView: View {
    @ObservedObject var library: LibraryEngine
    let videoMediaId: String
    let frame: MediaItemRecord

    private var isSelected: Bool {
        library.isFrameSelected(videoMediaId: videoMediaId, frameMediaId: frame.mediaId)
    }

    private var isEnabled: Bool {
        !library.curation(for: frame).rejected
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ThumbnailImage(path: frame.thumbnailPath, kind: .image, fit: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack {
                HStack {
                    if let seconds = frame.sourceTimestampSeconds {
                        Text(seconds.durationLabel)
                            .font(CanonType.archive(9, weight: .medium))
                            .foregroundStyle(CanonColor.bone)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(CanonColor.room.opacity(0.78), in: RoundedRectangle(cornerRadius: 4))
                    }
                    Spacer(minLength: 0)
                    if isEnabled {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CanonColor.olive)
                            .padding(3)
                            .background(CanonColor.room.opacity(0.72), in: Circle())
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CanonColor.focusBlue)
                            .padding(3)
                            .background(CanonColor.room.opacity(0.72), in: Circle())
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? CanonColor.focusBlue : (isEnabled ? CanonColor.olive.opacity(0.78) : CanonColor.hairlineDark), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            library.toggleFrameSelection(videoMediaId: videoMediaId, frameMediaId: frame.mediaId)
        }
        .draggable(MediaIDTransfer(mediaId: frame.mediaId))
        .aspectRatio(MediaTileLayout.aspect(width: frame.width, height: frame.height).tileAspect, contentMode: .fit)
        .help(frame.sourceTimestampSeconds?.durationLabel ?? frame.filename)
    }
}

private struct MediaTileView: View {
    @ObservedObject var library: LibraryEngine
    let item: MediaItemRecord
    let curation: MediaCurationRecord
    var roleBadges: [MediaRoleBadge] = []
    let isSelected: Bool
    /// Restyle this photo as a Frame (images with a Scene Plan); nil hides the verb.
    var onRestyle: (() -> Void)? = nil
    let onSelect: () -> Void
    let onOpen: () -> Void
    @State private var isHovered = false
    @State private var isTagEditorPresented = false

    var body: some View {
        tileContent
        .onTapGesture {
            onSelect()
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            onOpen()
        })
        .draggable(MediaIDTransfer(mediaId: item.mediaId))
        .onHover { hovering in
            isHovered = hovering
        }
        .help(item.path)
        .contextMenu {
            MediaUseMenu(
                library: library,
                item: item,
                onEditTags: { isTagEditorPresented = true },
                onRestyle: onRestyle
            )
        }
        .popover(isPresented: $isTagEditorPresented, arrowEdge: .bottom) {
            MediaTagEditorPopover(library: library, item: item) {
                isTagEditorPresented = false
            }
        }
    }

    private var tileContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ThumbnailImage(path: item.thumbnailPath, kind: item.kind, fit: true)
                    .aspectRatio(tileAspect.tileAspect, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 4) {
                    let storageStatus = library.mediaStorageStatus(for: item)
                    if let badgeText = mediaTileStorageBadgeText(storageStatus) {
                        badge(badgeText, color: storageBadgeColor(storageStatus))
                    }
                    if item.kind == .video {
                        badge(item.durationSeconds?.durationLabel ?? "Video", color: CanonColor.room.opacity(0.78))
                    }
                }
                .padding(6)
            }

            MediaEnableButton(
                library: library,
                item: item,
                mode: .state,
                isFullWidth: true
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename)
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                    .lineLimit(1)
                Text(item.relativePath)
                    .font(CanonType.archive(10))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)

            if !displayedRoleBadges.isEmpty {
                roleBadgeRow
            }
        }
        .padding(8)
        .background(isHovered ? CanonColor.mediaCardHover : CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? CanonColor.focusBlue : CanonColor.hairlineDark, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    /// The tile follows the image's own shape inside the band; it never crops.
    private var tileAspect: MediaTileAspect {
        MediaTileLayout.aspect(width: item.width, height: item.height)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CanonColor.bone)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(CanonColor.hairlineDark)
            )
    }

    private func storageBadgeColor(_ status: MediaStorageStatus) -> Color {
        switch status {
        case .managed: CanonColor.olive.opacity(0.88)
        case .linked: CanonColor.room.opacity(0.82)
        case .missing: CanonColor.rust.opacity(0.92)
        }
    }

    /// Role badges under the caption — the tile says what the item is FOR.
    /// The story-input badge is skipped (the enable button already carries that
    /// state); at most three others show, with an overflow count.
    private var displayedRoleBadges: [MediaRoleBadge] {
        roleBadges.filter { $0 != .storyInput }
    }

    private var roleBadgeRow: some View {
        let shown = Array(displayedRoleBadges.prefix(3))
        let overflow = displayedRoleBadges.count - shown.count
        return HStack(spacing: 4) {
            ForEach(shown, id: \.self) { badge in
                HStack(spacing: 3) {
                    Image(systemName: badge.systemImage)
                        .font(.system(size: 7.5, weight: .semibold))
                    Text(badge.label)
                        .font(CanonType.archive(9, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(CanonColor.olive)
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(CanonColor.room.opacity(0.6)))
                .overlay(Capsule().stroke(CanonColor.hairlineDark))
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
        .help(displayedRoleBadges.map(\.label).joined(separator: " · "))
    }
}

private struct InlineMediaDetailCard: View {
    @ObservedObject var library: LibraryEngine
    let item: MediaItemRecord
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.filename)
                        .font(CanonType.interface(15, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                        .lineLimit(2)
                    Text(item.relativePath)
                        .font(CanonType.archive(10))
                        .foregroundStyle(CanonColor.muted)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CanonColor.muted)
                .help("Collapse Media")
            }

            preview

            if let scanError = item.scanError, !scanError.isEmpty {
                Label(scanError, systemImage: "exclamationmark.triangle")
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.rust)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    metadataBlock
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    curationBlock
                        .frame(width: 190, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 12) {
                    metadataBlock
                    curationBlock
                }
            }
        }
        .padding(12)
        .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.focusBlue.opacity(0.75), lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .help(item.path)
    }

    @ViewBuilder
    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if item.kind == .video {
                if library.isPlaying(item) {
                    VideoPreview(path: item.path, autoplayRequestId: library.videoPlaybackRequestId)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VideoPosterPreview(item: item) {
                        library.playVideo(item)
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if let strip = item.videoStripPath, !strip.isEmpty {
                    ThumbnailImage(path: strip, kind: .video)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } else {
                OriginalMediaImage(path: item.path, fallbackThumbnailPath: item.thumbnailPath)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: 7) {
            inlineHeader("Media")
            metadataRow("Storage", library.mediaStorageStatus(for: item).label)
            metadataRow("Kind", item.kind.rawValue.capitalized)
            metadataRow("Size", "\(item.width)x\(item.height)")
            metadataRow("Bytes", ByteCountFormatter.string(fromByteCount: item.byteCount, countStyle: .file))
            metadataRow("Modified", item.modifiedAt)
            if item.isExtractedVideoFrame {
                metadataRow("Frame Time", item.sourceTimestampSeconds?.durationLabel ?? "Unknown")
                if let sourceMediaId = item.sourceMediaId {
                    metadataRow("Source", sourceMediaId)
                }
            }
            if let duration = item.durationSeconds {
                metadataRow("Duration", duration.durationLabel)
            }
            if let fps = item.nominalFrameRate, fps > 0 {
                metadataRow("Frame Rate", String(format: "%.2f fps", fps))
            }
        }
        .padding(10)
        .background(CanonColor.mediaCardHover, in: RoundedRectangle(cornerRadius: 8))
    }

    private var curationBlock: some View {
        let curation = library.curation(for: item)
        return VStack(alignment: .leading, spacing: 10) {
            inlineHeader("State")

            if item.canBeEnabledContent {
                MediaEnableButton(
                    library: library,
                    item: item,
                    mode: .state,
                    isFullWidth: true
                )

                Text(curation.rejected ? "Disabled media remains visible for review." : "Enabled media can participate in later creation workflows.")
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Source reel", systemImage: "film.stack")
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                Text("Choose frames in Media to add story candidates from this video.")
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                library.revealInFinder(item)
            } label: {
                Label("Open in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CanonSecondaryButtonStyle(isFullWidth: true))
        }
        .padding(10)
        .background(CanonColor.mediaCardHover, in: RoundedRectangle(cornerRadius: 8))
    }

    private func inlineHeader(_ title: String) -> some View {
        Text(title)
            .font(CanonType.interface(10, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(CanonColor.muted)
    }

    private func metadataRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(CanonColor.muted)
            Spacer()
            Text(value)
                .foregroundStyle(CanonColor.bone)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(CanonType.archive(10))
    }
}

private struct OriginalMediaImage: View {
    let path: String
    let fallbackThumbnailPath: String

    var body: some View {
        ZStack {
            CanonColor.mediaCardHover
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ThumbnailImage(path: fallbackThumbnailPath, kind: .image)
                    .scaledToFit()
            }
        }
    }
}

private struct ThumbnailImage: View {
    let path: String
    let kind: MediaKind
    /// Fit shows the whole picture on the matte; fill (the default) crops to the frame.
    var fit: Bool = false

    var body: some View {
        ZStack {
            CanonColor.mediaCardHover
            if let image = NSImage(contentsOfFile: path) {
                if fit {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: kind == .video ? "film" : "photo")
                        .font(.title2)
                    Text(kind.rawValue.capitalized)
                        .font(.caption2)
                }
                .foregroundStyle(CanonColor.muted)
            }
        }
        .clipped()
    }
}

private struct VideoPosterPreview: View {
    let item: MediaItemRecord
    let onPlay: () -> Void

    var body: some View {
        ZStack {
            ThumbnailImage(path: item.thumbnailPath, kind: .video)
            Rectangle()
                .fill(CanonColor.room.opacity(0.22))
            Button {
                onPlay()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(CanonColor.bone)
                    .frame(width: 54, height: 54)
                    .background(CanonColor.room.opacity(0.70), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Play")
        }
    }
}

private struct VideoPreview: NSViewRepresentable {
    let path: String
    let autoplayRequestId: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(path: path, autoplayRequestId: autoplayRequestId)
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        let player = makePlayer(for: path)
        view.player = player
        context.coordinator.player = player
        if autoplayRequestId > 0 {
            DispatchQueue.main.async {
                player.play()
            }
        }
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if context.coordinator.path != path {
            context.coordinator.player?.pause()
            let player = makePlayer(for: path)
            view.player = player
            context.coordinator.path = path
            context.coordinator.player = player
            if autoplayRequestId > 0 {
                player.play()
            }
        } else if context.coordinator.autoplayRequestId != autoplayRequestId {
            context.coordinator.autoplayRequestId = autoplayRequestId
            if autoplayRequestId > 0 {
                context.coordinator.player?.play()
            }
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        view.player = nil
        coordinator.player = nil
    }

    private func makePlayer(for path: String) -> AVPlayer {
        AVPlayer(url: URL(fileURLWithPath: path))
    }

    final class Coordinator {
        var path: String
        var autoplayRequestId: Int
        var player: AVPlayer?

        init(path: String, autoplayRequestId: Int) {
            self.path = path
            self.autoplayRequestId = autoplayRequestId
        }
    }
}

private extension Double {
    var durationLabel: String {
        let seconds = Int(rounded())
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}

private extension Color {
    init(hex: Int, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
