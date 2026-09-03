import SwiftUI
import AVKit
@preconcurrency import AVFoundation
import AppKit

/// Identifies which shot's rendered video is open in the player.
struct ShotVideoRequest: Identifiable, Hashable {
    var shotId: String
    /// Open with the Re-render segment-prompts panel already slid out.
    var openRerenderPanel: Bool = false
    var id: String { shotId }
}

/// Opens the Ambient Bed Tuner as a nested sheet of the shot player modal.
struct AmbientTunerRequest: Identifiable, Hashable {
    /// The bed whose spec seeds the tuner; nil starts a fresh bed.
    var initialBedId: String?
    var id: String { initialBedId ?? "new" }
}

/// Minimal plate-styled looping player for a shot's rendered video, with the
/// honest facts of the render (stack, segments, duration) and the Re-render
/// segment-prompts panel that slides out to the right of the player. Missing
/// files render an explicit placeholder, never a spinner.
struct ShotRenderPlayerModal: View {
    let shot: ProjectShot
    let shotOrdinal: Int
    let planSegments: [ShotRenderPlanSegment]
    let skipped: [String]
    let skippedPlaceholders: [ShotSkippedSegmentPlaceholder]
    /// True while another shot is rendering — one render at a time.
    let isRenderBlocked: Bool
    let configuredRenderModels: Set<ShotRenderModel>
    /// Live FAL rates for the re-render panel's spend estimates.
    var falPricing: FALPricingSnapshot? = nil
    var isFetchingVideoPricing: Bool = false
    var onActivateVersion: (String) -> Void
    var onSetDefaultRenderStack: (ShotRenderStack) -> Void
    var onSetSegmentRenderStack: (ShotRenderPair, ShotRenderStack?) -> Void
    var onRender: ([ShotSegmentPromptOverride]) -> Void
    var onRenderSegment: ([ShotSegmentPromptOverride], String) -> Void
    /// Debounced draft autosave from the Segment Prompts panel (persist only,
    /// never renders).
    var onAutosaveOverrides: ([ShotSegmentPromptOverride]) -> Void = { _ in }
    /// Persists segment direction plans (beats) from the Segment Prompts
    /// panel — autosave and confirm both land here.
    var onSaveDirectionPlans: ([ShotSegmentDirectionPlanRecord]) -> Void = { _ in }
    /// LLM beat-drafting lane state (keys "shotId|pairKey") + triggers,
    /// forwarded verbatim to the Segment Prompts panel.
    var draftingDirectionKeys: Set<String> = []
    var directionDraftErrors: [String: String] = [:]
    var onDraftDirectionPlan: (String) -> Void = { _ in }
    var onDraftAllDirectionPlans: () -> Void = {}
    // Picture-edit closures return the engine's whole-state edit so the
    // modal can register a single ⌘Z action per gesture (THE PICTURE
    // SNAPSHOT LAW); leaf views below the modal keep Void closures and the
    // modal wraps these into registering versions.
    var onSetSeamStyle: (String, ShotSeamStyle, ShotSeamEditIntent) -> ShotPictureStateEdit?
    var onSetEntrySkipped: (String, Bool) -> ShotPictureStateEdit?
    var onSetCutList: (ShotCutList) -> ShotPictureStateEdit?
    var onSetCutReversed: (Bool) -> ShotPictureStateEdit? = { _ in nil }
    var onRetryReverseProxies: () async -> Void = {}
    /// nil unless this shot's reversed proxies are still baking.
    var reverseBakeProgress: Double?
    let hasFALCredential: Bool
    let hasDecartCredential: Bool
    let activeShotJoinRenderId: String
    var onSetJoinRepair: (String, ShotRazorJoinRepair) -> ShotPictureStateEdit?
    var onRestoreRazorCut: (String) -> ShotPictureStateEdit?
    /// Applies a picture snapshot (the ⌘Z restore primitive).
    var onRestorePictureState: (ShotPictureStateSnapshot) -> Void = { _ in }
    var onRenderJoinBridge: (String, ShotJoinBridgeProvider, Int, String) -> Void
    var onPrepareJoinFrames: (String) async -> ShotJoinBoundaryPreview?
    var onCommitMicrophoneTake: (ShotMicrophoneRecordingResult, Double) async -> ShotMicrophoneTake?
    var onDeleteMicrophoneTake: (String) -> Void
    var ambientBeds: [AmbientBedRecord]
    var audioClips: [MediaItemRecord]
    var isBakingAmbientBed: Bool
    var onSaveAmbientBed: (AmbientBedSpec) async -> AmbientBedRecord?
    var onDeleteAmbientBed: (String) -> Bool
    var onRenameAmbientBed: (String, String) -> Void
    var onSetAmbientBed: (String?) -> Void
    var onOpenNarration: () -> Void
    var audioRegionActions: ShotAudioRegionActions
    let restylePromptSeed: String
    let activeShotRestyleId: String
    var onActivateLook: (String) -> Void
    var onStartRestyle: (String, Bool, Int, ShotLookStyleSelection?, ShotLookProvider) -> Void
    var onCancelRestyle: () -> Void
    var onRetryRestyle: (String) -> Void
    var onContinueLookAsNewShot: () async -> String?
    var onSendToFootage: () async -> Bool
    /// Export for YouTube: flattens this cut + writes its title/description
    /// markdown into ~/Downloads/LitScenes-Finals. Returns the status line.
    var onExportForYouTube: () async -> String = { "" }
    /// Collect Frame: (source video path, file-local seconds, output seconds)
    /// → success. The engine extracts + archives into Media.
    var onCollectFrame: (String, Double, Double) async -> Bool = { _, _, _ in false }
    /// The project this shot lives in — the picture clipboard's cross-project
    /// paste rung reads it.
    var projectId: String = ""
    // Picture-insertion closures (arranged copies — paste/loop/rate/mute):
    // the same edit-returning shape as the cut ops above.
    var onPastePictureSegments: ([ShotPictureInsertion], String?) -> ShotPictureStateEdit? = { _, _ in nil }
    var onRemovePictureInsertions: (Set<String>) -> ShotPictureStateEdit? = { _ in nil }
    var onSetPictureInsertionRate: (Set<String>, Double) -> ShotPictureStateEdit? = { _, _ in nil }
    var onSetPictureInsertionMuted: (Set<String>, Bool) -> ShotPictureStateEdit? = { _, _ in nil }
    var onRecopyPictureInsertion: (String) -> ShotPictureStateEdit? = { _ in nil }
    /// STRUCTURAL paste of copied segment cards: (cards, afterEntryId) —
    /// lands the pair + overrides + seed take as first-class material.
    var onPasteSegmentCards: ([ShotPictureSegmentSpanRef], String?) -> ShotPictureStateEdit? = { _, _ in nil }
    /// SECTION SPEED: (materialStart, materialEnd, rate) — razors the span
    /// and plays a born-muted copy of it in place at `rate`, one edit.
    var onSetSectionRate: (Double, Double, Double) -> ShotPictureStateEdit? = { _, _, _ in nil }
    var onClose: () -> Void

    @Environment(\.undoManager) private var undoManager
    /// The Ambient Tuner's attach path lands region edits from OUTSIDE the
    /// lane stack, so it carries its own coordinator — otherwise attaching a
    /// bed from the tuner was the one region write with no ⌘Z.
    @StateObject private var tunerUndo = ShotAudioRegionUndoCoordinator()
    /// Every picture edit committed through this modal registers here —
    /// razor, blade, skip/restore, seam, IN/OUT, reverse, join repair.
    @StateObject private var cutUndo = ShotPictureUndoCoordinator()
    @StateObject private var microphoneRecorder = ShotMicrophoneRecorder()
    @State private var player: AVPlayer?
    @State private var loopObserver: NSObjectProtocol?
    @State private var playerLoadToken = 0
    @State private var isCollectingFrame = false
    @State private var collectStatus = ""
    @State private var collectFailed = false
    @State private var isPreparingPlayer = false
    @State private var playbackError = ""
    @State private var isPanelOpen: Bool
    /// The segment clip playing instead of the full shot (panel preview).
    @State private var previewClip: ShotRenderSegmentClip?
    /// Honest per-clip durations, loaded off the saved files; the strip and
    /// the composition fall back to estimates until they land.
    @State private var clipDurationsByPath: [String: Double] = [:]
    @State private var playheadSeconds: Double = 0
    @State private var timeObserverToken: Any?
    @State private var pendingSeekSeconds: Double?
    @State private var microphoneDevices: [CameraDeviceOption] = []
    @State private var selectedMicrophoneDeviceId = CaptureAudioInputPreference.deviceId
    @State private var monitorPlayback = LitScenesPreferences.store.bool(
        forKey: ShotVoiceoverPreference.playbackWhileRecordingKey
    )
    @State private var microphoneCountIn: Int?
    @State private var microphoneCountInTask: Task<Void, Never>?
    @State private var microphoneAnchorSeconds: Double = 0
    @State private var microphoneStatus = ""
    @State private var isVersionsPlateOpen = false
    /// Mirrors `ShotPlayerTransportPreference.loopEnabled` for drawing; the
    /// loop observer reads the LIVE preference (its closure outlives toggles).
    @State private var isLoopEnabled = ShotPlayerTransportPreference.loopEnabled
    /// THE SCRUB LATCH: a scrub pauses on begin and resumes on release iff
    /// playback was running. Edits keep the pause law; scrubs are transport.
    @State private var isScrubbing = false
    @State private var wasPlayingBeforeScrub = false
    @State private var transportStatus = ""
    /// THE WINDOW COROLLARY: one viewport for the strip, ruler, and lanes.
    @State private var timelineViewport = ShotTimelineViewport.fit
    /// THE PROJECTION GHOST: the output projection of a strip picture-edit
    /// drag in flight, drawn through the lane stack (nil = no drag).
    @State private var dragGhostOutputSeconds: Double?
    @State private var dragGhostIsSnapped = false
    /// Lane-stack width, measured by a background GeometryReader, so max
    /// zoom is computed against the real mapped span.
    @State private var timelineLaneWidth: CGFloat = 1200
    /// The two-press B blade's armed first mark (material seconds).
    @State private var pendingBladeMaterialSeconds: Double?
    @State private var isKeymapOpen = false
    /// Hoisted strip state, so THE ESCAPE LADDER can walk its rungs.
    @State private var isRazorArmed = false
    @State private var stripSelectedCutId: String?
    /// The strip's span selection and selected arranged-copy cell — hoisted
    /// beside the cut selection so ⌘C/⌘V/⌘D/⌫ and the ladder live here.
    @State private var stripSelectedSpan: ShotStripSpanSelection?
    @State private var stripSelectedInsertionId: String?
    /// Loop preview: an output-seconds range the periodic observer repeats
    /// (⌥L with a selection). View state only — nothing persists.
    @State private var loopPreviewRange: ClosedRange<Double>?
    @State private var isRestyleComposerOpen = false
    @State private var restylePrompt: String
    @State private var restyleEnhancePrompt = true
    @State private var restyleSeed: Int
    @State private var restyleStyleSelection: ShotLookStyleSelection?
    @State private var isRestyleStylePickerOpen = false
    @AppStorage(ShotLookProvider.preferenceKey, store: LitScenesPreferences.store)
    private var restyleProviderRaw = ShotLookProvider.fal.rawValue
    @State private var isContinuingLook = false
    @State private var lookStatus = ""
    @State private var isSendingToFootage = false
    @State private var footageStatus = ""
    @State private var isExportingForYouTube = false
    @State private var youtubeExportStatus = ""
    @State private var ambientTunerRequest: AmbientTunerRequest?
    /// The sound editor nested sheet (never simultaneous with the tuner —
    /// its open paths close this first).
    @State private var soundEditorRequest: ShotSoundEditorRequest?

    init(
        shot: ProjectShot,
        shotOrdinal: Int,
        planSegments: [ShotRenderPlanSegment],
        skipped: [String],
        skippedPlaceholders: [ShotSkippedSegmentPlaceholder] = [],
        isRenderBlocked: Bool,
        configuredRenderModels: Set<ShotRenderModel> = [],
        falPricing: FALPricingSnapshot? = nil,
        isFetchingVideoPricing: Bool = false,
        openPanelInitially: Bool = false,
        onActivateVersion: @escaping (String) -> Void,
        onSetDefaultRenderStack: @escaping (ShotRenderStack) -> Void = { _ in },
        onSetSegmentRenderStack: @escaping (ShotRenderPair, ShotRenderStack?) -> Void = { _, _ in },
        onRender: @escaping ([ShotSegmentPromptOverride]) -> Void,
        onRenderSegment: @escaping ([ShotSegmentPromptOverride], String) -> Void,
        onAutosaveOverrides: @escaping ([ShotSegmentPromptOverride]) -> Void = { _ in },
        onSaveDirectionPlans: @escaping ([ShotSegmentDirectionPlanRecord]) -> Void = { _ in },
        draftingDirectionKeys: Set<String> = [],
        directionDraftErrors: [String: String] = [:],
        onDraftDirectionPlan: @escaping (String) -> Void = { _ in },
        onDraftAllDirectionPlans: @escaping () -> Void = {},
        onSetSeamStyle: @escaping (String, ShotSeamStyle, ShotSeamEditIntent) -> ShotPictureStateEdit? = { _, _, _ in nil },
        onSetEntrySkipped: @escaping (String, Bool) -> ShotPictureStateEdit? = { _, _ in nil },
        onSetCutList: @escaping (ShotCutList) -> ShotPictureStateEdit? = { _ in nil },
        onSetCutReversed: @escaping (Bool) -> ShotPictureStateEdit? = { _ in nil },
        onRetryReverseProxies: @escaping () async -> Void = {},
        reverseBakeProgress: Double? = nil,
        hasFALCredential: Bool = false,
        hasDecartCredential: Bool = false,
        activeShotJoinRenderId: String = "",
        onSetJoinRepair: @escaping (String, ShotRazorJoinRepair) -> ShotPictureStateEdit? = { _, _ in nil },
        onRestoreRazorCut: @escaping (String) -> ShotPictureStateEdit? = { _ in nil },
        onRestorePictureState: @escaping (ShotPictureStateSnapshot) -> Void = { _ in },
        onRenderJoinBridge: @escaping (String, ShotJoinBridgeProvider, Int, String) -> Void = { _, _, _, _ in },
        onPrepareJoinFrames: @escaping (String) async -> ShotJoinBoundaryPreview? = { _ in nil },
        onCommitMicrophoneTake: @escaping (ShotMicrophoneRecordingResult, Double) async -> ShotMicrophoneTake? = { _, _ in nil },
        onDeleteMicrophoneTake: @escaping (String) -> Void = { _ in },
        ambientBeds: [AmbientBedRecord] = [],
        audioClips: [MediaItemRecord] = [],
        isBakingAmbientBed: Bool = false,
        onSaveAmbientBed: @escaping (AmbientBedSpec) async -> AmbientBedRecord? = { _ in nil },
        onDeleteAmbientBed: @escaping (String) -> Bool = { _ in false },
        onRenameAmbientBed: @escaping (String, String) -> Void = { _, _ in },
        onSetAmbientBed: @escaping (String?) -> Void = { _ in },
        onOpenNarration: @escaping () -> Void = {},
        audioRegionActions: ShotAudioRegionActions = ShotAudioRegionActions(),
        restylePromptSeed: String = "",
        activeShotRestyleId: String = "",
        onActivateLook: @escaping (String) -> Void = { _ in },
        onStartRestyle: @escaping (String, Bool, Int, ShotLookStyleSelection?, ShotLookProvider) -> Void = { _, _, _, _, _ in },
        onCancelRestyle: @escaping () -> Void = {},
        onRetryRestyle: @escaping (String) -> Void = { _ in },
        onContinueLookAsNewShot: @escaping () async -> String? = { nil },
        onSendToFootage: @escaping () async -> Bool = { false },
        onExportForYouTube: @escaping () async -> String = { "" },
        onCollectFrame: @escaping (String, Double, Double) async -> Bool = { _, _, _ in false },
        projectId: String = "",
        onPastePictureSegments: @escaping ([ShotPictureInsertion], String?) -> ShotPictureStateEdit? = { _, _ in nil },
        onRemovePictureInsertions: @escaping (Set<String>) -> ShotPictureStateEdit? = { _ in nil },
        onSetPictureInsertionRate: @escaping (Set<String>, Double) -> ShotPictureStateEdit? = { _, _ in nil },
        onSetPictureInsertionMuted: @escaping (Set<String>, Bool) -> ShotPictureStateEdit? = { _, _ in nil },
        onRecopyPictureInsertion: @escaping (String) -> ShotPictureStateEdit? = { _ in nil },
        onPasteSegmentCards: @escaping ([ShotPictureSegmentSpanRef], String?) -> ShotPictureStateEdit? = { _, _ in nil },
        onSetSectionRate: @escaping (Double, Double, Double) -> ShotPictureStateEdit? = { _, _, _ in nil },
        onClose: @escaping () -> Void
    ) {
        self.shot = shot
        self.shotOrdinal = shotOrdinal
        self.planSegments = planSegments
        self.skipped = skipped
        self.skippedPlaceholders = skippedPlaceholders
        self.isRenderBlocked = isRenderBlocked
        self.configuredRenderModels = configuredRenderModels
        self.falPricing = falPricing
        self.isFetchingVideoPricing = isFetchingVideoPricing
        self.onActivateVersion = onActivateVersion
        self.onSetDefaultRenderStack = onSetDefaultRenderStack
        self.onSetSegmentRenderStack = onSetSegmentRenderStack
        self.onRender = onRender
        self.onRenderSegment = onRenderSegment
        self.onAutosaveOverrides = onAutosaveOverrides
        self.onSaveDirectionPlans = onSaveDirectionPlans
        self.draftingDirectionKeys = draftingDirectionKeys
        self.directionDraftErrors = directionDraftErrors
        self.onDraftDirectionPlan = onDraftDirectionPlan
        self.onDraftAllDirectionPlans = onDraftAllDirectionPlans
        self.onSetSeamStyle = onSetSeamStyle
        self.onSetEntrySkipped = onSetEntrySkipped
        self.onSetCutList = onSetCutList
        self.onSetCutReversed = onSetCutReversed
        self.onRetryReverseProxies = onRetryReverseProxies
        self.reverseBakeProgress = reverseBakeProgress
        self.hasFALCredential = hasFALCredential
        self.hasDecartCredential = hasDecartCredential
        self.activeShotJoinRenderId = activeShotJoinRenderId
        self.onSetJoinRepair = onSetJoinRepair
        self.onRestoreRazorCut = onRestoreRazorCut
        self.onRestorePictureState = onRestorePictureState
        self.onRenderJoinBridge = onRenderJoinBridge
        self.onPrepareJoinFrames = onPrepareJoinFrames
        self.onCommitMicrophoneTake = onCommitMicrophoneTake
        self.onDeleteMicrophoneTake = onDeleteMicrophoneTake
        self.ambientBeds = ambientBeds
        self.audioClips = audioClips
        self.isBakingAmbientBed = isBakingAmbientBed
        self.onSaveAmbientBed = onSaveAmbientBed
        self.onDeleteAmbientBed = onDeleteAmbientBed
        self.onRenameAmbientBed = onRenameAmbientBed
        self.onSetAmbientBed = onSetAmbientBed
        self.onOpenNarration = onOpenNarration
        self.audioRegionActions = audioRegionActions
        self.restylePromptSeed = restylePromptSeed
        self.activeShotRestyleId = activeShotRestyleId
        self.onActivateLook = onActivateLook
        self.onStartRestyle = onStartRestyle
        self.onCancelRestyle = onCancelRestyle
        self.onRetryRestyle = onRetryRestyle
        self.onContinueLookAsNewShot = onContinueLookAsNewShot
        self.onSendToFootage = onSendToFootage
        self.onExportForYouTube = onExportForYouTube
        self.onCollectFrame = onCollectFrame
        self.projectId = projectId
        self.onPastePictureSegments = onPastePictureSegments
        self.onRemovePictureInsertions = onRemovePictureInsertions
        self.onSetPictureInsertionRate = onSetPictureInsertionRate
        self.onSetPictureInsertionMuted = onSetPictureInsertionMuted
        self.onRecopyPictureInsertion = onRecopyPictureInsertion
        self.onPasteSegmentCards = onPasteSegmentCards
        self.onSetSectionRate = onSetSectionRate
        self.onClose = onClose
        _isPanelOpen = State(initialValue: openPanelInitially)
        _restylePrompt = State(initialValue: restylePromptSeed)
        _restyleSeed = State(initialValue: Int.random(in: 1...Int(Int32.max)))
    }

    /// The version this player SHOWS — ready-preferring, so an in-flight
    /// re-render or a failed version never blanks playback of the last good
    /// render. The persisted pointer is untouched; `substitutionBadge` wears
    /// the honesty when the two differ.
    private var artifact: ShotRenderArtifact? { shot.playableRenderVersion ?? shot.renderArtifact }
    private var activeLook: ShotRestyleArtifact? { shot.activeLookVersion }
    private var activeRestyle: ShotRestyleArtifact? {
        shot.lookVersions.first {
            $0.versionId == activeShotRestyleId
                && ["preparing", "uploading", "queued", "generating", "downloading"].contains($0.status)
        }
    }
    private var recoverableLook: ShotRestyleArtifact? {
        shot.sortedLookVersions.reversed().first {
            ["failed", "paused", "queued", "generating", "downloading"].contains($0.status)
                && !$0.requestId.isEmpty
                && $0.versionId != activeShotRestyleId
        }
    }

    /// The cut layer's whole derivation: bands, keep-ranges, and the playable
    /// spec list — shared by the strip, playback, and export. Reversed when the
    /// cut layer asks for it and every proxy is baked.
    private var assembly: ShotCutAssembly {
        shotVisibleCutAssembly(
            shot: shot,
            planSegments: planSegments,
            clipDurationsByPath: clipDurationsByPath
        )
    }

    /// The single source of truth for what plays: a previewed segment clip,
    /// else the active version's full video.
    private var currentVideoPath: String? {
        previewClip?.clipPath.nilIfEmpty
            ?? activeLook?.videoPath.trimmed.nilIfEmpty
            ?? artifact?.videoPath.trimmed.nilIfEmpty
    }

    private var isPreviewingClip: Bool { previewClip != nil }

    /// Full-shot playback assembles the saved segment clips live through the
    /// cut layer (skips, razors, in/out) — the mp4 on disk is never touched.
    private var usesCutComposition: Bool {
        !isPreviewingClip && activeLook == nil && assembly.hasPlayableClips
    }

    /// Everything that shapes the playback composition; a change reloads the
    /// player in place (resume at position).
    private var playbackFingerprint: String {
        let videoFingerprint = assembly.playbackItems
            .map { item in
                let range = item.keepRange.map { String(format: "%.3f-%.3f", $0.start, $0.end) } ?? "all"
                // Conditional so pre-insertion shots keep their historical
                // reload keys. Rate and per-copy mute must move this string —
                // neither shows up in url/range/xfade/cut.
                let arranged = item.isInsertion
                    ? "#ins=\(item.insertionId)#mute=\(item.includeAudio ? 0 : 1)#rate=\(String(format: "%.3f", item.playbackRate))"
                    : ""
                return "\(item.url.path)#\(range)#xfade=\(item.transitionFramesBefore)#cut=\(item.cutId)\(arranged)"
            }
            .joined(separator: "|")
        // `rev` names what is actually PLAYING, not what was asked for. While
        // proxies bake, the visible assembly is still the forward one over the
        // same paths — so without this token nothing in the string would move
        // when the last bake lands, and the player would never pick it up.
        // `loop` is conditional so pre-loop shots keep their historical keys;
        // the repeated items would move the string anyway, but the Look path
        // tiles at build time and audio placement depends on N either way.
        // The audio half is the SHARED `shotAudioMixFingerprint`, consumed by
        // this reload key AND the reel bake cache — one function, so the two
        // notions of "the mix changed" can never drift apart.
        let loopToken = outputLoopCount > 1 ? "#loop=\(outputLoopCount)" : ""
        return "look=\(activeLook?.versionId ?? "original")#rev=\(assembly.isReversed)\(loopToken)#\(videoFingerprint)#\(shotAudioMixFingerprint(shot: shot))"
    }

    /// The whole-output repeat playback honors. The REQUEST (cut list), not
    /// the assembly's achieved count: the Look path never expands items, and
    /// the two agree everywhere the cut composition actually plays.
    private var outputLoopCount: Int {
        shot.cutList.normalized().outputLoopCount
    }

    private var timelineDurationSeconds: Double {
        if let activeLook {
            return max(ShotAudioComposition.effectiveLookDurationSeconds(activeLook), 0)
                * Double(outputLoopCount)
        }
        if usesCutComposition { return max(assembly.outputSeconds, 0) }
        return max(Double(artifact?.totalSeconds ?? 0), 0)
    }

    private var microphoneControlMode: ShotMicrophoneControlMode {
        if let microphoneCountIn { return .countIn(microphoneCountIn) }
        switch microphoneRecorder.phase {
        case .recording: return .recording
        case .finalizing: return .finalizing
        case .idle, .preparing, .ready, .failed: return .idle
        }
    }

    private var videoExists: Bool {
        if usesCutComposition { return true }
        guard let path = currentVideoPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// Reveal targets a real file (segment clip or stitched artifact); the
    /// live cut composition has no file to reveal.
    private var revealTargetExists: Bool {
        guard let path = currentVideoPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    /// macOS sheets size to ideal content and happily overflow the window
    /// (the panel column's flexible list + the player's ideal drove the
    /// footer and strip off-screen). Cap the instrument to the visible
    /// screen; the player surface flexes, everything else stays reachable.
    private var maxModalHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 1000
        return max(screenHeight - 72, 620)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    playerSurface
                        .frame(minWidth: 880, minHeight: 380, maxHeight: .infinity)
                        .overlay { microphoneRecordingOverlay }
                    if activeLook != nil {
                        Rectangle().fill(PlateColor.hairline).frame(height: 1)
                        lookControlBar
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                    } else if !assembly.bands.isEmpty {
                        Rectangle().fill(PlateColor.hairline).frame(height: 1)
                        cutTimelineStrip
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                    }
                    if !isPreviewingClip, videoExists {
                        Rectangle().fill(PlateColor.hairline).frame(height: 1)
                        audioLaneStack
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                    }
                    Rectangle().fill(PlateColor.hairline).frame(height: 1)
                    footer
                }
                if isPanelOpen, activeLook == nil {
                    Rectangle().fill(PlateColor.hairline).frame(width: 1)
                    rerenderPanel
                        .frame(width: 460)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .clipped()
        }
        .frame(maxHeight: maxModalHeight)
        .background(PlateColor.cream)
        .plateEngravedBorder(cornerRadius: 0, inset: 6)
        .modifier(transportKeys)
        // The picture clipboard's menu route. Copy schedules a DIRECT write
        // after SwiftUI's provider write, so whatever the provider path does
        // (its write is a still-open live-verify trap), the pasteboard ends
        // holding the real payload. Paste discards providers and reads the
        // pasteboard synchronously — the audio clipboard's proven pattern.
        .onCopyCommand {
            guard let payload = currentPictureCopyPayload() else { return [] }
            DispatchQueue.main.async {
                ShotPictureClipboard.write(payload)
                transportStatus = "Copied \(String(format: "%.1f", payload.totalSeconds))s of picture"
            }
            return ShotPictureClipboard.itemProviders(for: payload)
        }
        .onPasteCommand(of: [ShotPictureClipboard.utType]) { _ in
            pastePictureAtPlayhead()
        }
        .onDeleteCommand {
            _ = deleteSelectedInsertionRun()
        }
        .onChange(of: stripSelectedSpan) { _, _ in
            // A moved selection ends its preview — looping a stale range
            // would audition something the operator no longer has selected.
            loopPreviewRange = nil
        }
        .background(
            Button("", action: onClose)
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        )
        .background(zoomShortcutButtons)
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $isRestyleStylePickerOpen, onDismiss: { isRestyleComposerOpen = true }) {
            ShotLookStylePickerSheet(
                initialSelection: restyleStyleSelection,
                provider: ShotLookProvider.resolved(restyleProviderRaw),
                onApply: { selection in
                    restyleStyleSelection = selection
                    isRestyleStylePickerOpen = false
                },
                onCancel: { isRestyleStylePickerOpen = false }
            )
        }
        .sheet(isPresented: $isVersionsPlateOpen) {
            versionsPlateSheet()
        }
        .sheet(isPresented: $isKeymapOpen) {
            ShotTransportCheatSheet(onClose: { isKeymapOpen = false })
        }
        .sheet(item: $ambientTunerRequest) { request in
            AmbientTunerSheetView(
                beds: ambientBeds,
                initialBedId: request.initialBedId,
                attachedBedId: shot.audioMix.lane(ShotAudioLaneId.ambient).ambientBedId,
                isBaking: isBakingAmbientBed,
                onSave: onSaveAmbientBed,
                onDelete: onDeleteAmbientBed,
                onRename: onRenameAmbientBed,
                onAttach: { record in
                    // Region-aware attach: a regionized shot swaps the bed on
                    // an ambient region in place (keeping timing/gain), or
                    // lays a fresh full-length region; a legacy shot keeps
                    // the singleton attach, which the lane preview mirrors.
                    //
                    // Target law, kind-keyed so numbered ambient rows count:
                    // the region already carrying THIS bed (a re-bake
                    // refresh) wins; else a lone ambient region swaps in
                    // place; with several candidates and no match, guessing
                    // which to replace would be wrong, so the bed lands as a
                    // new region instead. Both paths register real ⌘Z.
                    if shot.audioRegions.isEmpty {
                        onSetAmbientBed(record.bedId)
                        return
                    }
                    let ambientRegions = shot.audioRegions.filter {
                        ShotAudioLaneId.kind(ofLaneId: $0.laneId) == ShotAudioLaneId.ambient
                    }
                    let target = ambientRegions
                        .filter { $0.mediaId == record.bedId }
                        .min(by: { $0.startSeconds < $1.startSeconds })
                        ?? (ambientRegions.count == 1 ? ambientRegions[0] : nil)
                    if let target {
                        if let old = audioRegionActions.replaceMedia(
                            target.regionId,
                            .ambientBed(bedId: record.bedId)
                        ), let new = audioRegionActions.currentRegion(target.regionId) {
                            tunerUndo.registerEdit(
                                old: old,
                                new: new,
                                actionName: "Attach Ambient Bed",
                                undoManager: undoManager
                            )
                        }
                    } else if let edit = audioRegionActions.add(
                        ShotAudioLaneId.ambient,
                        .ambientBed(bedId: record.bedId),
                        0
                    ) {
                        tunerUndo.registerStateEdit(
                            old: edit.before,
                            new: edit.after,
                            actionName: "Attach Ambient Bed",
                            undoManager: undoManager
                        )
                    }
                },
                onClose: { ambientTunerRequest = nil }
            )
        }
        .sheet(item: $soundEditorRequest) { request in
            ShotSoundEditorSheet(
                shotOrdinal: shotOrdinal,
                request: request,
                durationSeconds: timelineDurationSeconds,
                playheadSeconds: playheadSeconds,
                player: player,
                initialViewport: timelineViewport,
                isLoopEnabled: isLoopEnabled,
                isTransportEnabled: microphoneControlMode == .idle,
                transportStatus: transportStatus,
                regionSpans: shot.audioRegions.map { $0.startSeconds...max($0.endSeconds, $0.startSeconds) },
                buildLaneStack: { makeLaneStack(inSoundEditor: true) },
                resolvePlayheadSeconds: { currentPlayheadSeconds() },
                onTogglePlayback: togglePlayback,
                onPause: pausePlaybackResolvingPlayhead,
                onShuttleForward: shuttleForward,
                onShuttleReverse: shuttleReverse,
                onFrameStep: { stepFrames($0) },
                onJumpTo: { jumpTo(seconds: $0) },
                onToggleLoop: toggleLoop,
                onClose: { soundEditorRequest = nil }
            )
        }
        .onAppear {
            refreshMicrophoneDevices()
            preparePlayer()
            tunerUndo.applyRegion = { region in audioRegionActions.restore(region) }
            tunerUndo.deleteRegion = { regionId in _ = audioRegionActions.delete(regionId) }
            tunerUndo.applyAudioState = { state in audioRegionActions.restoreState(state) }
            // shotId travels per-registration; this modal serves one shot.
            cutUndo.applyState = { _, snapshot in onRestorePictureState(snapshot) }
        }
        .task {
            // A reversed CUT whose proxies failed or never finished plays
            // forward. Opening the shot is the natural retry point, and
            // `ensureReverseProxies` is a no-op for everything else.
            await onRetryReverseProxies()
        }
        .onChange(of: currentVideoPath) { _, _ in
            preparePlayer(resume: false)
        }
        .onChange(of: playbackFingerprint) { _, _ in
            // The cut layer or saved clips changed shape — reassemble in
            // place, holding the playback position.
            preparePlayer(resume: true)
        }
        .onChange(of: shot.activeRenderVersionId) { _, _ in
            previewClip = nil
        }
        .onChange(of: playheadSeconds) { previous, current in
            // THE FOLLOW LAW's playback half: pages only on an inside→outside
            // crossing, so a deliberately panned-away window is never yanked.
            timelineViewport = timelineViewport.following(
                previous: previous,
                current: current,
                durationSeconds: timelineDurationSeconds
            )
        }
        .onChange(of: shot.activeLookVersionId) { _, value in
            previewClip = nil
            if !value.isEmpty { isPanelOpen = false }
        }
        .onDisappear {
            undoManager?.removeAllActions(withTarget: tunerUndo)
            tunerUndo.applyRegion = nil
            tunerUndo.deleteRegion = nil
            tunerUndo.applyAudioState = nil
            undoManager?.removeAllActions(withTarget: cutUndo)
            cutUndo.applyState = nil
            // Invalidate any in-flight player build — a load landing after
            // the sheet closes would start an invisible player whose audio
            // keeps running (heard as doubled audio on reopen).
            playerLoadToken += 1
            microphoneCountInTask?.cancel()
            microphoneCountInTask = nil
            microphoneRecorder.shutdown()
            removeTimeObserver()
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            if let loopObserver {
                NotificationCenter.default.removeObserver(loopObserver)
            }
            loopObserver = nil
            player = nil
        }
    }

    // Extracted from `body` as their own type-check units — the body
    // expression tipped the compiler once these grew scrub props.
    private var rerenderPanel: some View {
        ShotRenderPromptPanel(
            shot: shot,
            planSegments: planSegments,
            skipped: skipped,
            skippedPlaceholders: skippedPlaceholders,
            isRenderBlocked: isRenderBlocked,
            previewingSegmentKey: previewClip?.placementKey,
            configuredRenderModels: configuredRenderModels,
            onRender: onRender,
            onRenderSegment: onRenderSegment,
            onPreviewSegment: { clip in previewClip = clip },
            onSetDefaultRenderStack: onSetDefaultRenderStack,
            onSetSegmentRenderStack: onSetSegmentRenderStack,
            onSetSeamStyle: { entryId, style in
                commitSeamStyle(entryId: entryId, style: style)
            },
            onSetEntrySkipped: { entryId, skipped in
                commitEntrySkipped(entryId: entryId, skipped: skipped)
            },
            onRestoreSkippedSeam: { entryId in
                commitRestoreSkippedSeam(entryId: entryId)
            },
            falPricing: falPricing,
            isFetchingRates: isFetchingVideoPricing,
            onAutosaveOverrides: onAutosaveOverrides,
            onCopySegmentCard: { item, draftPrompt in
                copySegmentCard(item, draftPrompt: draftPrompt)
            },
            onSaveDirectionPlans: onSaveDirectionPlans,
            draftingDirectionKeys: draftingDirectionKeys,
            directionDraftErrors: directionDraftErrors,
            onDraftDirectionPlan: onDraftDirectionPlan,
            onDraftAllDirectionPlans: onDraftAllDirectionPlans
        )
    }

    /// Output-space audio landmarks pulled back to MATERIAL seconds for the
    /// strip's snap magnets: every placed region edge (narration, ambient,
    /// clip — with the lane stack's own legacy-preview fallback, minus the
    /// ambient/clip media durations only the stack resolves) plus the active
    /// microphone take's bounds. "Cut where the audio ends" becomes a magnet.
    private func audioSnapMaterialLandmarks() -> [Double] {
        let cutAssembly = assembly
        var outputEdges: [Double] = []
        let regions = shot.audioRegions.isEmpty
            ? shot.legacyAudioRegionPreview(
                timelineSeconds: timelineDurationSeconds,
                ambientBedDurationSeconds: nil,
                clipMediaDurationSeconds: nil
            )
            : shot.audioRegions
        for region in regions {
            outputEdges.append(region.startSeconds)
            outputEdges.append(max(region.endSeconds, region.startSeconds))
        }
        if let take = shot.audioMix.activeMicrophoneTake {
            outputEdges.append(take.startSeconds)
            outputEdges.append(take.startSeconds + take.durationSeconds)
        }
        return outputEdges.map { cutAssembly.materialSeconds(forOutputSeconds: $0) }
    }

    private var cutTimelineStrip: some View {
        ShotCutTimelineStrip(
            shot: shot,
            assembly: assembly,
            placeholders: skippedPlaceholders,
            playheadOutputSeconds: playheadSeconds,
            onSeek: { seconds in seek(toOutputSeconds: seconds) },
            viewport: timelineViewport,
            pendingBladeMaterialSeconds: pendingBladeMaterialSeconds,
            onPictureEditBegan: { player?.pause() },
            onNotice: { transportStatus = $0 },
            audioSnapMaterialSeconds: audioSnapMaterialLandmarks(),
            onDragMaterialSecondsChanged: { seconds, isSnapped in
                // THE PROJECTION GHOST: re-project the material drag into
                // output space for the lane stack — the seam law's honest
                // cross-row readout.
                if let seconds {
                    dragGhostOutputSeconds = assembly.outputSeconds(forMaterialSeconds: seconds)
                    dragGhostIsSnapped = isSnapped
                } else {
                    dragGhostOutputSeconds = nil
                    dragGhostIsSnapped = false
                }
            },
            isRazorMode: $isRazorArmed,
            selectedCutId: $stripSelectedCutId,
            selectedSpan: $stripSelectedSpan,
            selectedInsertionId: $stripSelectedInsertionId,
            cannotPasteReason: ShotPictureClipboard.hasPayload
                ? nil
                : "Nothing on the picture clipboard — select a span and Copy first",
            onCopySelection: copyStripSelection,
            onPasteAtPlayhead: pastePictureAtPlayhead,
            onDuplicateSelection: duplicateStripSelection,
            onInsertionSetRate: { ids, rate in
                registerPictureEdit(
                    onSetPictureInsertionRate(ids, rate),
                    "Copy Speed \(shotInsertionRateLabel(rate))"
                )
            },
            onInsertionSetMuted: { ids, muted in
                registerPictureEdit(
                    onSetPictureInsertionMuted(ids, muted),
                    muted ? "Mute Copy" : "Restore Copy Sound"
                )
            },
            onInsertionDelete: { ids in
                registerPictureEdit(
                    onRemovePictureInsertions(ids),
                    ids.count > 1 ? "Delete \(ids.count) Copies" : "Delete Copy"
                )
            },
            onInsertionRecopy: { insertionId in
                registerPictureEdit(
                    onRecopyPictureInsertion(insertionId),
                    "Re-copy From Current Take"
                )
            },
            onInsertionAddLoopCopy: { insertion in
                player?.pause()
                var sibling = insertion
                sibling.insertionId = ""
                let minted = ShotPictureInsertion(
                    sourceSegmentKey: sibling.sourceSegmentKey,
                    sourceClipPath: sibling.sourceClipPath,
                    sourceMediaId: sibling.sourceMediaId,
                    sourceStartSeconds: sibling.sourceStartSeconds,
                    sourceEndSeconds: sibling.sourceEndSeconds,
                    anchorSegmentKey: sibling.anchorSegmentKey,
                    anchorSeconds: sibling.anchorSeconds,
                    playbackRate: sibling.playbackRate,
                    muteSourceAudio: sibling.muteSourceAudio,
                    loopGroupId: sibling.loopGroupId
                )
                registerPictureEdit(
                    onPastePictureSegments([minted], "One more copy — same speed and sound"),
                    "Add Loop Copy"
                )
            },
            onSetSectionRate: { rate in
                applySectionRate(rate)
            },
            onScrubBegan: scrubBegan,
            onScrubEnded: scrubEnded,
            onSetCutList: { list in commitCutList(list) },
            onSetEntrySkipped: { entryId, skipped in
                commitEntrySkipped(entryId: entryId, skipped: skipped)
            },
            onSetSeamStyle: { entryId, style in
                commitSeamStyle(entryId: entryId, style: style)
            },
            onRestoreSkippedSeam: { entryId in
                commitRestoreSkippedSeam(entryId: entryId)
            },
            hasFALCredential: hasFALCredential,
            isVideoRenderBlocked: isRenderBlocked,
            activeShotJoinRenderId: activeShotJoinRenderId,
            onSetJoinRepair: { cutId, repair in
                commitJoinRepair(cutId: cutId, repair: repair)
            },
            onRestoreRazorCut: { cutId in commitRestoreRazorCut(cutId: cutId) },
            onRenderJoinBridge: onRenderJoinBridge,
            onPrepareJoinFrames: onPrepareJoinFrames,
            microphoneControlMode: microphoneControlMode,
            isMicrophoneAvailable: videoExists
                && !isPreviewingClip
                && !isPreparingPlayer
                && playbackError.isEmpty,
            onToggleMicrophoneRecording: toggleMicrophoneRecording,
            isReversed: shot.cutList.isReversed,
            isPlayingReversed: assembly.isReversed,
            reverseBakeProgress: reverseBakeProgress,
            onSetReversed: { reversed in commitCutReversed(reversed) }
        )
    }

    // MARK: Picture undo (THE PICTURE SNAPSHOT LAW's registration half)

    /// One committed picture gesture = one registered action. nil edits
    /// (refusals and persisted no-ops) register nothing.
    private func registerPictureEdit(_ edit: ShotPictureStateEdit?, _ actionName: String) {
        guard let edit else { return }
        cutUndo.registerEdit(
            shotId: shot.shotId,
            old: edit.before,
            new: edit.after,
            actionName: actionName,
            undoManager: undoManager
        )
    }

    /// The shared `onSetCutList` funnel (razor drags, typed IN/OUT, popover
    /// TIMING, blade, I/O keys) names its action from the persisted diff.
    private func commitCutList(_ list: ShotCutList) {
        guard let edit = onSetCutList(list) else { return }
        registerPictureEdit(
            edit,
            shotCutListEditActionName(before: edit.before.cutList, after: edit.after.cutList)
        )
        // A trim persisted against a dead composition changes nothing the
        // user can see or hear — playback is the last render's plain video.
        let before = edit.before.cutList
        let after = edit.after.cutList
        let trimChanged = before.shotInSeconds != after.shotInSeconds
            || before.shotOutSeconds != after.shotOutSeconds
        if trimChanged, !usesCutComposition {
            transportStatus = "Trim saved — playback still shows the last render; it applies once the plan's segments are rendered"
        }
    }

    private func commitEntrySkipped(entryId: String, skipped: Bool) {
        registerPictureEdit(
            onSetEntrySkipped(entryId, skipped),
            skipped ? "Skip Segment" : "Restore Segment"
        )
    }

    private func commitSeamStyle(entryId: String, style: ShotSeamStyle) {
        registerPictureEdit(
            onSetSeamStyle(entryId, style, .explicit),
            style == .cut ? "Seam: Hard Cut" : "Seam: Bridge"
        )
    }

    private func commitRestoreSkippedSeam(entryId: String) {
        registerPictureEdit(
            onSetSeamStyle(entryId, .bridge, .restoreSkipped),
            "Restore Seam"
        )
    }

    private func commitJoinRepair(cutId: String, repair: ShotRazorJoinRepair) {
        let actionName: String
        switch repair.mode {
        case .hardCut: actionName = "Join: Hard Cut"
        case .dissolve: actionName = "Join: Dissolve"
        case .generatedBridge: actionName = "Join: AI Bridge"
        }
        registerPictureEdit(onSetJoinRepair(cutId, repair), actionName)
    }

    private func commitRestoreRazorCut(cutId: String) {
        guard let edit = onRestoreRazorCut(cutId) else { return }
        let removed = edit.before.cutList.segmentCuts.count - edit.after.cutList.segmentCuts.count
        registerPictureEdit(
            edit,
            removed > 1 ? "Restore \(removed) Razor Cuts" : "Restore Razor Cut"
        )
    }

    private func commitCutReversed(_ reversed: Bool) {
        registerPictureEdit(
            onSetCutReversed(reversed),
            reversed ? "Reverse CUT" : "Play CUT Forward"
        )
    }

    /// One construction for both surfaces: the inline stack and the sound
    /// editor's enlarged stack share every closure, so an edit made in either
    /// place is the same commit through the same undo contract. The editor's
    /// copy drops the expand affordance (it IS the expansion) and both
    /// tuner/narration paths close the editor first — never two sheets on
    /// the modal.
    private func makeLaneStack(inSoundEditor: Bool) -> ShotAudioLaneStack {
        ShotAudioLaneStack(
            shot: shot,
            assembly: assembly,
            legacySourcePath: assembly.hasPlayableClips
                ? nil
                : artifact?.videoPath.trimmed.nilIfEmpty,
            durationSeconds: timelineDurationSeconds,
            playheadSeconds: playheadSeconds,
            inputDevices: microphoneDevices,
            selectedInputDeviceId: selectedMicrophoneDeviceId,
            monitorPlayback: monitorPlayback,
            microphoneLevel: microphoneRecorder.level,
            microphoneControlMode: microphoneControlMode,
            // Under a Look the lanes measure the LOOK's duration, so
            // cut-space picture spans would mis-scale against it.
            pictureReferenceIsValid: activeLook == nil && usesCutComposition,
            dragGhostOutputSeconds: dragGhostOutputSeconds,
            dragGhostIsSnapped: dragGhostIsSnapped,
            ambientBeds: ambientBeds,
            audioClips: audioClips,
            regionActions: audioRegionActions,
            onOpenNarration: {
                soundEditorRequest = nil
                onOpenNarration()
            },
            onOpenAmbientTuner: { initialBedId in
                // The tuner's live audition must not fight the modal's
                // looping player.
                soundEditorRequest = nil
                player?.pause()
                ambientTunerRequest = AmbientTunerRequest(initialBedId: initialBedId)
            },
            onSeek: { seek(toOutputSeconds: $0) },
            onSelectInputDevice: selectMicrophoneDevice,
            onSetMonitorPlayback: setMonitorPlayback,
            onDeleteTake: onDeleteMicrophoneTake,
            onToggleMicrophoneRecording: toggleMicrophoneRecording,
            onGestureBegan: { player?.pause() },
            onScrubBegan: scrubBegan,
            onScrubEnded: scrubEnded,
            resolvePlayheadSeconds: { currentPlayheadSeconds() },
            onJumpToPlayhead: { jumpTo(seconds: $0) },
            onOpenSoundEditor: inSoundEditor
                ? nil
                : { range in openSoundEditor(revealing: range) }
        )
    }

    private var audioLaneStack: some View {
        makeLaneStack(inSoundEditor: false)
            .environment(\.shotTimelineViewport, timelineViewport)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { timelineLaneWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { _, width in
                            timelineLaneWidth = width
                        }
                }
            )
    }

    /// Opens the sound editor WITHOUT pausing — the editor drives this same
    /// player. Guarded like the lane stack itself: no editor for a shot with
    /// nothing to hear against.
    private func openSoundEditor(revealing range: ClosedRange<Double>?) {
        guard videoExists, !isPreviewingClip, timelineDurationSeconds > 0 else { return }
        soundEditorRequest = ShotSoundEditorRequest(
            revealStartSeconds: range?.lowerBound,
            revealEndSeconds: range?.upperBound
        )
    }

    // MARK: Zoom (THE WINDOW COROLLARY's controls)

    private var timelineMaxZoom: CGFloat {
        ShotTimelineViewport.maxZoom(
            durationSeconds: timelineDurationSeconds,
            contentWidth: max(
                timelineLaneWidth - ShotTimelineAxis.headWidth - ShotTimelineAxis.tailWidth
                    - ShotTimelineAxis.contentInset * 2,
                1
            )
        )
    }

    /// Zoom anchored at the playhead when it's visible, else the window's
    /// center — zooming in dives into what you're looking at.
    private func zoomTimeline(byFactor factor: CGFloat) {
        let duration = timelineDurationSeconds
        guard duration > 0 else { return }
        let window = timelineViewport.window(durationSeconds: duration)
        let playhead = currentPlayheadSeconds()
        let anchor = playhead >= window.start && playhead <= window.start + window.length
            ? playhead
            : window.start + window.length / 2
        timelineViewport = timelineViewport.zoomed(
            byFactor: factor,
            anchorSeconds: anchor,
            durationSeconds: duration,
            maxZoom: timelineMaxZoom
        )
    }

    /// THE FOLLOW LAW's transport half: steps and jumps always reveal the
    /// playhead (playback paging lives in the `onChange(of: playheadSeconds)`).
    private func revealPlayheadInViewport(_ seconds: Double) {
        timelineViewport = timelineViewport.revealing(
            seconds,
            durationSeconds: timelineDurationSeconds
        )
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button {
                zoomTimeline(byFactor: 0.5)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundStyle(timelineViewport.isFit ? PlateColor.inkFaint.opacity(0.4) : PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .disabled(timelineViewport.isFit)
            .help("Zoom out (⌘−)")
            PlateLabel(
                text: timelineViewport.isFit ? "FIT" : "\(Int(timelineViewport.zoom))×",
                size: 8,
                weight: .bold,
                color: timelineViewport.isFit ? PlateColor.inkFaint : CanonColor.brass
            )
            .frame(minWidth: 22)
            .help(timelineViewport.isFit
                ? "The whole cut fits the timeline — zoom in for frame-accurate work (⌘+)"
                : "Timeline zoom — ⌘0 fits the whole cut again")
            Button {
                zoomTimeline(byFactor: 2)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundStyle(timelineViewport.zoom >= timelineMaxZoom
                        ? PlateColor.inkFaint.opacity(0.4)
                        : PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .disabled(timelineViewport.zoom >= timelineMaxZoom)
            .help("Zoom in around the playhead (⌘+) — up to where one frame is grabbable")
        }
    }

    private var zoomShortcutButtons: some View {
        Group {
            Button("") { zoomTimeline(byFactor: 2) }
                .keyboardShortcut("=", modifiers: .command)
            Button("") { zoomTimeline(byFactor: 0.5) }
                .keyboardShortcut("-", modifiers: .command)
            Button("") { timelineViewport = .fit }
                .keyboardShortcut("0", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: Transport

    private var transportKeys: ShotPlayerTransportKeys {
        ShotPlayerTransportKeys(
            isEnabled: microphoneControlMode == .idle,
            onTogglePlayback: togglePlayback,
            onPause: pausePlaybackResolvingPlayhead,
            onShuttleForward: shuttleForward,
            onShuttleReverse: shuttleReverse,
            onFrameStep: { stepFrames($0) },
            onJumpToStart: { jumpTo(seconds: 0) },
            onJumpToEnd: { jumpTo(seconds: timelineDurationSeconds) },
            onToggleLoop: toggleLoop,
            onBlade: bladePressed,
            onSetInPoint: { setInOutAtPlayhead(isIn: true, clear: $0) },
            onSetOutPoint: { setInOutAtPlayhead(isIn: false, clear: $0) },
            onEscapeLadder: { escapeLadder() },
            onShowKeymap: { isKeymapOpen = true },
            onOpenSoundEditor: { openSoundEditor(revealing: nil) }
        )
    }

    /// THE ESCAPE LADDER, stated once: a focused lane's selected region
    /// deselects first (it owns the keyboard and consumes the press); then
    /// these rungs — pending blade mark → armed razor → strip cut selection —
    /// and only with every rung clear does Escape reach the hidden
    /// `.cancelAction` button and close the modal.
    private func escapeLadder() -> Bool {
        if pendingBladeMaterialSeconds != nil {
            pendingBladeMaterialSeconds = nil
            transportStatus = "Blade canceled"
            return true
        }
        if isRazorArmed {
            isRazorArmed = false
            return true
        }
        if stripSelectedInsertionId != nil {
            stripSelectedInsertionId = nil
            return true
        }
        if stripSelectedSpan != nil {
            stripSelectedSpan = nil
            loopPreviewRange = nil
            return true
        }
        if stripSelectedCutId != nil {
            stripSelectedCutId = nil
            return true
        }
        return false
    }

    // MARK: Picture clipboard (copy · paste · loop — THE WYSIWYG COPY LAW)

    /// The FORWARD assembly, for copy/anchor resolution: reversed items read
    /// proxy files in proxy coordinates, and copies must pin source files.
    private var forwardAssembly: ShotCutAssembly {
        shotCutAssembly(
            shot: shot,
            planSegments: planSegments,
            clipDurationsByPath: clipDurationsByPath
        )
    }

    /// The payload the current selection copies — span selection resolves
    /// through the WYSIWYG law; a selected arranged-copy run copies itself,
    /// modifiers and all. nil when nothing is selected.
    private func currentPictureCopyPayload() -> ShotPictureSegmentClipboardPayload? {
        let now = DateFormats.now()
        if let leaderId = stripSelectedInsertionId,
           let run = shotInsertionRun(in: assembly.insertionCells, leaderId: leaderId) {
            let spans = run.map { cell in
                ShotPictureSegmentSpanRef(
                    segmentKey: cell.insertion.sourceSegmentKey,
                    clipPath: cell.insertion.sourceClipPath,
                    mediaId: cell.insertion.sourceMediaId,
                    startSeconds: cell.insertion.sourceStartSeconds,
                    endSeconds: cell.insertion.sourceEndSeconds,
                    playbackRate: cell.insertion.playbackRate,
                    muteSourceAudio: cell.insertion.muteSourceAudio
                )
            }
            let payload = ShotPictureSegmentClipboardPayload(
                spans: spans,
                sourceShotId: shot.shotId,
                sourceProjectId: projectId,
                context: ShotSegmentContext(copiedAt: now)
            )
            return payload.isPasteable ? payload : nil
        }
        guard let span = stripSelectedSpan else { return nil }
        let forward = forwardAssembly
        let spans = shotCopiedSpans(
            assembly: forward,
            materialStart: span.lowSeconds,
            materialEnd: span.highSeconds
        )
        let payload = ShotPictureSegmentClipboardPayload(
            spans: spans,
            sourceShotId: shot.shotId,
            sourceProjectId: projectId,
            context: shotCopiedSegmentContext(
                assembly: forward,
                materialStart: span.lowSeconds,
                materialEnd: span.highSeconds,
                lookSummary: activeLook?.styleSummary ?? "",
                now: now
            )
        )
        return payload.isPasteable ? payload : nil
    }

    private func copyStripSelection() {
        guard let payload = currentPictureCopyPayload() else {
            transportStatus = "Nothing selected to copy — drag across the strip first"
            return
        }
        ShotPictureClipboard.write(payload)
        transportStatus = "Copied \(String(format: "%.1f", payload.totalSeconds))s of picture"
    }

    /// The Re-render panel's Copy: this segment as a CARD — keyframe pair,
    /// the card's current draft prompt, its stack, and its rendered take
    /// (resolved exactly as playback resolves it, provenance kept), so a
    /// paste lands it in another CUT as first-class material.
    private func copySegmentCard(_ item: ShotSegmentPromptPlanItem, draftPrompt: String) {
        guard let startId = item.pair.start?.imageId.trimmed.nilIfEmpty,
              let endId = item.pair.end?.imageId.trimmed.nilIfEmpty else {
            transportStatus = "Lead-in and extension segments can't carry yet — they anchor on a neighbor"
            return
        }
        var seed = shot.playableRenderVersion?.segmentClip(
            placementStartEntryId: item.pair.startPlacementEntryId,
            placementEndEntryId: item.pair.endPlacementEntryId,
            forStart: startId,
            end: endId
        ) ?? shot.seedSegmentClips.first { $0.placementKey == item.pair.placementKey }
        if let candidate = seed,
           candidate.clipPath.trimmed.isEmpty
            || !FileManager.default.fileExists(atPath: candidate.clipPath) {
            seed = nil
        }
        if seed != nil {
            seed?.sourceCutId = shot.shotId
            seed?.sourceRenderVersionId = shot.playableRenderVersion?.versionId ?? ""
        }
        // NARRATION CARRY: capture the slice of this shot's narration audible
        // over the copied segment's output window, so the clipboard stays
        // self-contained and a cross-cut paste can land the sentence with its
        // picture. Empty when there is no ready narration or it ends before
        // this segment.
        var narrationPath = ""
        var narrationSourceStart: Double = 0
        var narrationSlice: Double = 0
        var narrationOffset: Double = 0
        var narrationLabel = ""
        if let narration = shot.narrationArtifact,
           narration.isReady,
           FileManager.default.fileExists(atPath: narration.audioPath) {
            let activeRegion = shot.audioRegions.map { $0.normalized() }.first {
                $0.laneId == ShotAudioLaneId.narration && $0.provenance == "active_narration"
            }
            let narrationStart = activeRegion?.startSeconds
                ?? shot.audioMix.lane(ShotAudioLaneId.narration).effectiveStartSeconds
            let narrationDuration = activeRegion?.durationSeconds ?? narration.durationSeconds
            let window = forwardAssembly.playbackItems.filter {
                $0.segmentKey == item.pair.placementKey && !$0.isBridge && $0.durationSeconds > 0
            }
            if let first = window.first,
               let slice = shotNarrationCarrySlice(
                   narrationStartSeconds: narrationStart,
                   narrationDurationSeconds: narrationDuration,
                   segmentOutputStartSeconds: first.outputStartSeconds,
                   segmentDurationSeconds: window.reduce(0) { $0 + $1.durationSeconds }
               ) {
                narrationPath = narration.audioPath
                narrationSourceStart = (activeRegion?.sourceStartSeconds ?? 0) + slice.sourceStartSeconds
                narrationSlice = slice.sliceSeconds
                narrationOffset = slice.offsetIntoSegmentSeconds
                narrationLabel = shot.name.trimmed.isEmpty
                    ? "Carried narration"
                    : "Narration · \(shot.name.trimmed)"
            }
        }
        let prompt = draftPrompt.trimmed
        let span = ShotPictureSegmentSpanRef(
            segmentKey: item.pair.placementKey,
            clipPath: seed?.clipPath ?? "",
            startSeconds: 0,
            endSeconds: seed?.durationSeconds ?? 0,
            label: "Segment \(item.displayIndex + 1)",
            startFrameImageId: startId,
            endFrameImageId: endId,
            promptOverride: prompt == item.generatedPrompt.trimmed ? "" : prompt,
            renderStackRaw: item.hasRenderOverride ? item.renderStack.rawValue : "",
            seedClip: seed,
            narrationPath: narrationPath,
            narrationSourceStartSeconds: narrationSourceStart,
            narrationSliceSeconds: narrationSlice,
            narrationOffsetIntoSegmentSeconds: narrationOffset,
            narrationLabel: narrationLabel
        )
        ShotPictureClipboard.write(ShotPictureSegmentClipboardPayload(
            spans: [span],
            sourceShotId: shot.shotId,
            sourceProjectId: projectId,
            context: ShotSegmentContext(
                authoredPrompt: prompt,
                lookSummary: activeLook?.styleSummary ?? "",
                copiedAt: DateFormats.now()
            )
        ))
        let narrationNote = narrationPath.isEmpty ? "" : " + its narration slice"
        transportStatus = seed == nil
            ? "Segment copied (unrendered)\(narrationNote) — paste it onto another CUT row or in its player"
            : "Segment copied with its rendered take\(narrationNote) — paste it onto another CUT row or in its player"
    }

    private func pastePictureAtPlayhead() {
        guard let payload = ShotPictureClipboard.read() else {
            transportStatus = "Nothing on the picture clipboard — select a span and Copy first"
            return
        }
        if let refusal = shotPictureClipboardPasteRefusal(
            payload: payload,
            targetShotId: shot.shotId,
            targetProjectId: projectId
        ) {
            transportStatus = refusal
            return
        }
        // A card payload pastes STRUCTURALLY — the pair lands after the
        // playhead's segment as first-class material (entries + overrides +
        // seed take), in this shot or another.
        let cards = payload.spans.filter(\.isSegmentCard)
        if !cards.isEmpty, cards.count == payload.spans.count {
            player?.pause()
            let material = assembly.materialSeconds(forOutputSeconds: currentPlayheadSeconds())
            let anchor = shotPasteAnchor(
                assembly: forwardAssembly,
                outputSeconds: forwardAssembly.outputSeconds(forMaterialSeconds: material)
            )
            let afterEntryId = anchor.flatMap { shotSegmentKeyRightEntryId($0.segmentKey) }
            registerPictureEdit(
                onPasteSegmentCards(cards, afterEntryId),
                cards.count > 1 ? "Paste \(cards.count) Segments" : "Paste Segment"
            )
            return
        }
        let forward = forwardAssembly
        let material = assembly.materialSeconds(forOutputSeconds: currentPlayheadSeconds())
        let forwardOutput = forward.outputSeconds(forMaterialSeconds: material)
        guard let anchor = shotPasteAnchor(assembly: forward, outputSeconds: forwardOutput) else {
            transportStatus = "Nothing is playable to paste into yet"
            return
        }
        player?.pause()
        let minted = mintedPictureInsertions(
            payload: payload,
            intent: ShotSegmentPasteIntent(anchor: anchor),
            now: DateFormats.now()
        )
        registerPictureEdit(
            onPastePictureSegments(
                minted,
                "Pasted \(String(format: "%.1f", payload.totalSeconds))s of picture at the playhead"
            ),
            minted.count > 1 ? "Paste \(minted.count) Segments" : "Paste Segment"
        )
    }

    /// ⌘D / the LOOP button: duplicate the selection right after itself. The
    /// copy is born muted — the base instance keeps its sound (THE HYBRID
    /// AUDIO DEFAULT, locked).
    private func duplicateStripSelection() {
        guard let span = stripSelectedSpan else {
            transportStatus = "Select a span to duplicate it in place"
            return
        }
        let forward = forwardAssembly
        let spans = shotCopiedSpans(
            assembly: forward,
            materialStart: span.lowSeconds,
            materialEnd: span.highSeconds
        )
        guard let last = spans.last else {
            transportStatus = "The selection holds no playable picture"
            return
        }
        player?.pause()
        let payload = ShotPictureSegmentClipboardPayload(
            spans: spans,
            sourceShotId: shot.shotId,
            sourceProjectId: projectId
        )
        let minted = mintedPictureInsertions(
            payload: payload,
            intent: ShotSegmentPasteIntent(
                anchor: ShotSegmentPasteAnchor(
                    segmentKey: last.segmentKey,
                    anchorSeconds: last.endSeconds
                ),
                muteSourceAudio: true
            ),
            now: DateFormats.now()
        )
        registerPictureEdit(
            onPastePictureSegments(minted, "Duplicated the selection — the copy is muted (♪ restores its sound)"),
            "Duplicate Selection"
        )
    }

    /// SECTION SPEED — the selection's material razors out and a born-muted
    /// copy plays in its place at `rate`, one undoable edit. The selection
    /// clears on success: the material it named just left the kept set.
    private func applySectionRate(_ rate: Double) {
        guard let span = stripSelectedSpan else {
            transportStatus = "Select a span to change its speed"
            return
        }
        player?.pause()
        let edit = onSetSectionRate(span.lowSeconds, span.highSeconds, rate)
        registerPictureEdit(edit, "Section Speed \(shotInsertionRateLabel(rate))")
        if edit != nil {
            stripSelectedSpan = nil
        }
    }

    /// ⌫ — removes the selected arranged-copy run. Returns whether anything
    /// was selected, so an idle ⌫ stays available to other handlers.
    private func deleteSelectedInsertionRun() -> Bool {
        guard let leaderId = stripSelectedInsertionId,
              let run = shotInsertionRun(in: assembly.insertionCells, leaderId: leaderId) else {
            return false
        }
        stripSelectedInsertionId = nil
        let ids = Set(run.map { $0.insertion.insertionId })
        registerPictureEdit(
            onRemovePictureInsertions(ids),
            ids.count > 1 ? "Delete \(ids.count) Copies" : "Delete Copy"
        )
        return true
    }

    // MARK: Picture parity (B blade, I/O)

    /// The two-press blade: first B marks the razor's start at the resolved
    /// playhead's material projection; second B commits the range through the
    /// same law the pointer razor uses. ⎋ cancels an armed mark.
    private func bladePressed() {
        guard !isPreviewingClip, assembly.hasPlayableClips else { return }
        // Under a Look the strip is hidden and cut edits belong to Original —
        // a blind blade here would razor a picture the operator can't see.
        guard activeLook == nil else {
            transportStatus = "Picture edits belong to Original — leave the Look to razor or trim"
            return
        }
        pausePlaybackResolvingPlayhead()
        let material = assembly.materialSeconds(forOutputSeconds: currentPlayheadSeconds())
        if let mark = pendingBladeMaterialSeconds {
            pendingBladeMaterialSeconds = nil
            if let list = shotBladeCutList(
                markMaterialSeconds: mark,
                toMaterialSeconds: material,
                assembly: assembly,
                cutList: shot.cutList,
                now: DateFormats.now()
            ) {
                commitCutList(list)
                transportStatus = "Razor range set — restorable on the strip"
            } else {
                transportStatus = "Blade refused — both marks must sit in one segment, at least 0.05s apart"
            }
        } else {
            pendingBladeMaterialSeconds = material
            transportStatus = "Blade armed — B again at the razor's other edge (⎋ cancels)"
        }
    }

    private func setInOutAtPlayhead(isIn: Bool, clear: Bool) {
        guard !isPreviewingClip, assembly.hasPlayableClips else { return }
        guard activeLook == nil else {
            transportStatus = "Picture edits belong to Original — leave the Look to razor or trim"
            return
        }
        pausePlaybackResolvingPlayhead()
        let material = clear
            ? nil
            : assembly.materialSeconds(forOutputSeconds: currentPlayheadSeconds())
        let list = isIn
            ? shotCutListSettingIn(
                shot.cutList,
                materialSeconds: material,
                assemblyMaterialSeconds: assembly.materialSeconds
            )
            : shotCutListSettingOut(
                shot.cutList,
                materialSeconds: material,
                assemblyMaterialSeconds: assembly.materialSeconds
            )
        commitCutList(list)
        transportStatus = clear
            ? "Shot \(isIn ? "IN" : "OUT") cleared"
            : "Shot \(isIn ? "IN" : "OUT") set at the playhead"
    }

    /// THE PLAYHEAD TRUTH LAW: the drawn playhead is a 10Hz approximation;
    /// any COMMIT that reads "the playhead" resolves the player's exact clock
    /// through this one choke point at the commit instant. Seeks, steps, and
    /// pauses write `playheadSeconds` directly, so the display is exact
    /// whenever nothing is moving. (`collectCurrentFrame` resolved its own
    /// time before this law existed — the precedent this generalizes.)
    private func currentPlayheadSeconds() -> Double {
        guard let time = player?.currentTime(),
              time.isValid,
              time.seconds.isFinite else {
            return playheadSeconds
        }
        let ceiling = timelineDurationSeconds > 0 ? timelineDurationSeconds : time.seconds
        return min(max(time.seconds, 0), ceiling)
    }

    private func pausePlaybackResolvingPlayhead() {
        player?.pause()
        playheadSeconds = currentPlayheadSeconds()
        // A paused player showing "▶ 2×" would be lying. Messages set AFTER
        // their pause (the honest J fallback, blade refusals) survive.
        transportStatus = ""
    }

    private func togglePlayback() {
        guard let player, !isPreparingPlayer else { return }
        if player.rate != 0 {
            pausePlaybackResolvingPlayhead()
            return
        }
        // Loop off and resting at the end: play means "again from the top".
        if !isLoopEnabled,
           timelineDurationSeconds > 0,
           currentPlayheadSeconds() >= timelineDurationSeconds - ShotAudioTiming.frameSeconds / 2 {
            seek(toOutputSeconds: 0)
        }
        transportStatus = ""
        player.play()
    }

    private func shuttleForward() {
        guard let player, !isPreparingPlayer else { return }
        let canFast = player.currentItem?.canPlayFastForward ?? false
        let cap: Float = canFast ? 4 : 2
        let next = ShotTransportMath.nextForwardRate(current: player.rate, cap: cap)
        transportStatus = !canFast && next >= cap
            ? "This preview caps forward shuttle at 2×"
            : "▶ \(Int(next))×"
        player.rate = next
    }

    private func shuttleReverse() {
        guard let player, !isPreparingPlayer else { return }
        if player.currentItem?.canPlayReverse == true {
            let next = ShotTransportMath.nextReverseRate(current: player.rate)
            transportStatus = "◀ \(Int(-next))×"
            player.rate = next
            return
        }
        // HONEST FALLBACK — never fake a negative rate the item can't play
        // (a composition preview usually can't). J becomes a 1s back-step.
        pausePlaybackResolvingPlayhead()
        seek(toOutputSeconds: max(currentPlayheadSeconds() - 1, 0))
        transportStatus = "Reverse shuttle unavailable for this preview — J steps back 1s"
    }

    private func stepFrames(_ frames: Int) {
        guard player != nil, !isPreparingPlayer else { return }
        pausePlaybackResolvingPlayhead()
        transportStatus = ""
        let target = ShotTransportMath.frameStepped(
            currentPlayheadSeconds(),
            frames: frames,
            durationSeconds: timelineDurationSeconds
        )
        seek(toOutputSeconds: target)
        revealPlayheadInViewport(target)
    }

    /// Home/End and the typed timecode jump: a precision act, so it pauses.
    private func jumpTo(seconds: Double) {
        guard player != nil, !isPreparingPlayer else { return }
        pausePlaybackResolvingPlayhead()
        transportStatus = ""
        let ceiling = timelineDurationSeconds > 0 ? timelineDurationSeconds : max(seconds, 0)
        let target = ShotAudioTiming.frameQuantizedStart(min(max(seconds, 0), ceiling))
        seek(toOutputSeconds: target)
        revealPlayheadInViewport(target)
    }

    /// ⌥L. With a span selected it toggles LOOP PREVIEW — the selection
    /// repeats so a beat can be auditioned before pasting; otherwise the
    /// whole-output loop preference toggles as before.
    private func toggleLoop() {
        if let span = stripSelectedSpan {
            if loopPreviewRange == nil {
                let low = assembly.outputSeconds(forMaterialSeconds: span.lowSeconds)
                let high = assembly.outputSeconds(forMaterialSeconds: span.highSeconds)
                let range = min(low, high)...max(low, high)
                if range.upperBound - range.lowerBound >= 0.1 {
                    loopPreviewRange = range
                    transportStatus = "Loop preview — the selection repeats (⌥L stops)"
                    seek(toOutputSeconds: range.lowerBound)
                    player?.play()
                    return
                }
            } else {
                loopPreviewRange = nil
                transportStatus = "Loop preview off"
                return
            }
        }
        isLoopEnabled.toggle()
        ShotPlayerTransportPreference.loopEnabled = isLoopEnabled
        transportStatus = isLoopEnabled ? "Loop on" : "Loop off — playback rests at the end"
    }

    private func scrubBegan() {
        guard !isScrubbing else { return }
        isScrubbing = true
        wasPlayingBeforeScrub = (player?.rate ?? 0) != 0
        player?.pause()
    }

    private func scrubEnded() {
        guard isScrubbing else { return }
        isScrubbing = false
        if wasPlayingBeforeScrub { player?.play() }
        wasPlayingBeforeScrub = false
    }

    /// Strip seek: output-timeline seconds. Leaves segment-clip preview mode
    /// (the strip always addresses the full shot).
    private func seek(toOutputSeconds seconds: Double) {
        playheadSeconds = seconds
        if isPreviewingClip {
            pendingSeekSeconds = seconds
            previewClip = nil
            return
        }
        player?.seek(
            to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func refreshMicrophoneDevices() {
        microphoneDevices = ShotMicrophoneRecorder.devices()
        selectedMicrophoneDeviceId = CaptureAudioInputPreference.resolvedDeviceId(in: microphoneDevices)
        if !selectedMicrophoneDeviceId.isEmpty {
            CaptureAudioInputPreference.deviceId = selectedMicrophoneDeviceId
        }
    }

    private func selectMicrophoneDevice(_ deviceId: String) {
        guard microphoneControlMode == .idle else { return }
        selectedMicrophoneDeviceId = deviceId
        CaptureAudioInputPreference.deviceId = deviceId
    }

    private func setMonitorPlayback(_ enabled: Bool) {
        monitorPlayback = enabled
        LitScenesPreferences.store.set(enabled, forKey: ShotVoiceoverPreference.playbackWhileRecordingKey)
        guard microphoneRecorder.phase == .recording else { return }
        if enabled {
            player?.play()
        } else {
            player?.pause()
        }
    }

    private func toggleMicrophoneRecording() {
        if microphoneCountIn != nil {
            microphoneCountInTask?.cancel()
            microphoneCountInTask = nil
            microphoneCountIn = nil
            microphoneRecorder.shutdown()
            microphoneStatus = "Count-in canceled"
            return
        }
        if microphoneRecorder.phase == .recording {
            stopMicrophoneRecording()
            return
        }
        guard microphoneRecorder.phase != .finalizing else { return }
        beginMicrophoneRecording()
    }

    private func beginMicrophoneRecording() {
        guard videoExists, !isPreviewingClip, timelineDurationSeconds > 0 else {
            microphoneStatus = "Open a full shot before recording"
            return
        }
        // The take anchors to the frame the operator is ON, not the last
        // 10Hz tick (the playhead truth law).
        microphoneAnchorSeconds = min(max(currentPlayheadSeconds(), 0), timelineDurationSeconds)
        player?.pause()
        player?.seek(
            to: CMTime(seconds: microphoneAnchorSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        microphoneStatus = "Requesting microphone access"

        let task = Task { @MainActor in
            guard await ShotMicrophoneRecorder.requestAccess(), !Task.isCancelled else {
                if !Task.isCancelled { microphoneStatus = "Microphone access is required" }
                return
            }
            refreshMicrophoneDevices()
            guard !selectedMicrophoneDeviceId.isEmpty else {
                microphoneStatus = "No microphone found"
                return
            }
            do {
                try microphoneRecorder.prepare(deviceId: selectedMicrophoneDeviceId)
                for count in stride(from: 3, through: 1, by: -1) {
                    guard !Task.isCancelled else { return }
                    microphoneCountIn = count
                    microphoneStatus = "Recording starts in \(count)"
                    try await Task.sleep(for: .seconds(1))
                }
                guard !Task.isCancelled else { return }
                microphoneCountIn = nil
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("litscenes_shot_mic_\(UUID().uuidString).m4a")
                try microphoneRecorder.startRecording(outputURL: outputURL)
                microphoneStatus = "Recording microphone"
                if monitorPlayback { player?.play() }
            } catch is CancellationError {
                microphoneCountIn = nil
            } catch {
                microphoneCountIn = nil
                microphoneStatus = "Microphone error: \(error.localizedDescription)"
                microphoneRecorder.shutdown()
            }
        }
        microphoneCountInTask = task
    }

    private func stopMicrophoneRecording() {
        guard microphoneRecorder.phase == .recording else { return }
        player?.pause()
        microphoneStatus = "Saving microphone take"
        Task { @MainActor in
            do {
                let result = try await microphoneRecorder.stopRecording()
                guard let take = await onCommitMicrophoneTake(result, microphoneAnchorSeconds) else {
                    microphoneStatus = "Microphone take could not be saved"
                    return
                }
                microphoneStatus = "Take saved at \(timecode(take.startSeconds))"
                pendingSeekSeconds = take.startSeconds
            } catch is CancellationError {
                microphoneStatus = "Microphone take discarded"
            } catch {
                microphoneStatus = "Microphone error: \(error.localizedDescription)"
            }
        }
    }

    @ViewBuilder
    private var microphoneRecordingOverlay: some View {
        if let microphoneCountIn {
            ZStack {
                Color.black.opacity(0.18)
                Text("\(microphoneCountIn)")
                    .font(.system(size: 72, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.5), radius: 8)
                    .accessibilityLabel("Recording starts in \(microphoneCountIn)")
            }
            .allowsHitTesting(false)
        } else if microphoneRecorder.phase == .recording {
            VStack {
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 9, height: 9)
                    Text("REC  \(timecode(microphoneRecorder.elapsedSeconds))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.72), in: Capsule())
                .padding(14)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
        }
    }

    private func timecode(_ seconds: Double) -> String {
        let tenths = max(Int((seconds * 10).rounded(.down)), 0)
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }

    /// Resolves visual-track durations before player construction. The asset
    /// envelope can be longer when embedded audio outlasts the picture.
    private func loadClipDurations() async {
        let missing = Set(
            assembly.planClips.map(\.clipPath).filter { !$0.isEmpty }
                + assembly.playbackItems.map { $0.url.path }
        )
            .subtracting(clipDurationsByPath.keys)
        guard !missing.isEmpty else { return }
        var loaded: [String: Double] = [:]
        for path in missing {
            if let duration = try? await VideoChainMedia.videoDurationSeconds(
                videoURL: URL(fileURLWithPath: path)
            ) {
                loaded[path] = duration
            }
        }
        guard !loaded.isEmpty else { return }
        clipDurationsByPath.merge(loaded) { _, new in new }
    }

    private func removeTimeObserver() {
        if let timeObserverToken, let player {
            player.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Rectangle().fill(PlateColor.hairline).frame(height: 1).frame(maxWidth: 48)
            PlateLabel(
                text: "Shot \(FrameCreatorModal.romanNumeral(shotOrdinal))\(shot.name.trimmed.isEmpty ? "" : " · \(shot.name)")",
                size: 13,
                weight: .semibold
            )
            .fixedSize()
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var playerSurface: some View {
        if !playbackError.isEmpty, usesCutComposition || activeLook != nil {
            ZStack {
                Color.black
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(CanonColor.brass)
                    PlateLabel(
                        text: activeLook == nil ? "CUT PREVIEW UNAVAILABLE" : "LOOK PREVIEW UNAVAILABLE",
                        size: 10,
                        weight: .bold,
                        color: PlateColor.cream
                    )
                    Text(playbackError)
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(PlateColor.cream.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                    Button("RETRY") { preparePlayer(resume: true) }
                        .buttonStyle(PlateButtonStyle(isProminent: true))
                }
                .padding(24)
            }
        } else if isPreparingPlayer {
            ZStack {
                Color.black
                VStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(PlateColor.cream)
                    PlateLabel(text: "PREPARING CUT PREVIEW", size: 8.5, color: PlateColor.cream.opacity(0.7))
                }
            }
        } else if let player, videoExists {
            VideoPlayer(player: player)
                .background(Color.black)
        } else {
            ZStack {
                PlateColor.creamDeep
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(PlateColor.inkFaint)
                    PlateLabel(
                        text: artifact == nil ? "No render for this shot" : "Rendered file is missing on disk",
                        size: 9.5,
                        color: PlateColor.inkFaint
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var lookControlBar: some View {
        if let look = activeLook {
            HStack(spacing: 12) {
                PlateLabel(
                    text: "LOOK \(FrameCreatorModal.romanNumeral(look.versionNumber)) · LUCY · 720P",
                    size: 9,
                    weight: .bold,
                    color: PlateColor.ink
                )
                PlateLabel(text: "SEED \(look.seed)", size: 8, color: PlateColor.inkFaint)
                if !look.styleLabel.trimmed.isEmpty {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(canonColor(fromHex: look.styleHueHex))
                            .frame(width: 6, height: 6)
                        PlateLabel(text: look.styleLabel, size: 8, color: PlateColor.inkFaint)
                            .lineLimit(1)
                    }
                    .help(look.styleSummary.trimmed.isEmpty
                        ? look.styleLabel
                        : "Style direction: \(look.styleSummary.trimmed)")
                }
                if look.sourceVisualFingerprint != shotLookVisualFingerprint(shot: shot, assembly: assembly) {
                    PlateLabel(text: "OLDER EDIT", size: 8, weight: .bold, color: CanonColor.rust)
                        .help("This Look remains available, but the Original picture has changed since it was created.")
                }
                let delta = look.durationDeltaSeconds
                if look.sourceDurationSeconds > 0 {
                    if ShotAudioComposition.lookRetimeTargetSeconds(
                        lookSeconds: look.outputDurationSeconds,
                        sourceSeconds: look.sourceDurationSeconds
                    ) != nil {
                        PlateLabel(
                            text: String(format: "LOOK RETIMED %+.2FS TO SOURCE", delta),
                            size: 8,
                            weight: .bold,
                            color: CanonColor.rust
                        )
                        .help("Lucy returned the picture at a drifted length; it plays retimed to the source duration so Source audio covers the full Look.")
                    } else if abs(delta) > 1.0 / 24.0 + 0.002 {
                        PlateLabel(
                            text: String(format: "LOOK %+.2FS VS SOURCE · AUDIO MAY DRIFT", delta),
                            size: 8,
                            weight: .bold,
                            color: CanonColor.rust
                        )
                        .help(delta < 0
                            ? "Audio beyond the Look's ending is truncated."
                            : "The Look may continue after available Source audio.")
                    }
                }
                Spacer()
                // REC MIC lives on the MIC lane below (visible in Look mode
                // too) and on the timeline strip in Original mode — no third
                // copy here.
                Button("EDIT ORIGINAL") {
                    onActivateLook("")
                    isPanelOpen = true
                }
                .buttonStyle(PlateButtonStyle())
                .help("Return to the editable cuts and segment controls; this Look is preserved.")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            lookCycler
            if activeLook == nil {
                versionCycler
                versionsPlateButton
                substitutionBadge
            }
            if isPreviewingClip {
                let previewSeconds = previewClip?.durationSeconds ?? 0
                let requestedSeconds = previewClip?.requestedDurationSeconds ?? 0
                let segmentSeconds = previewSeconds > 0
                    ? previewSeconds
                    : Double(requestedSeconds > 0 ? requestedSeconds : shot.renderStack.segmentSeconds)
                PlateLabel(
                    text: "SEGMENT · ~\(Int(segmentSeconds.rounded()))s",
                    size: 8.5,
                    weight: .semibold,
                    color: PlateColor.ink
                )
                Button("Full shot") {
                    previewClip = nil
                }
                .buttonStyle(PlateButtonStyle())
                .help("Return the player to the full shot video")
            } else if let activeLook {
                PlateLabel(
                    text: "LUCY · LOOK \(FrameCreatorModal.romanNumeral(activeLook.versionNumber)) · ~\(Int(ShotAudioComposition.effectiveLookDurationSeconds(activeLook).rounded()))s",
                    size: 8.5,
                    color: PlateColor.inkFaint
                )
            } else if artifact != nil || usesCutComposition {
                let stackLabel = footerProvenanceLabel
                let liveCount = assembly.planClips.filter(\.isPlayable).count
                let count = usesCutComposition ? liveCount : (artifact?.segmentCount ?? 0)
                let seconds = usesCutComposition
                    ? Int(assembly.outputSeconds.rounded())
                    : (artifact?.totalSeconds ?? 0)
                PlateLabel(
                    text: "\(stackLabel) · \(count) segment\(count == 1 ? "" : "s") · ~\(seconds)s",
                    size: 8.5,
                    color: PlateColor.inkFaint
                )
            }
            loopToggleButton
            if timelineDurationSeconds > 0 {
                zoomControls
            }
            Button {
                isKeymapOpen = true
            } label: {
                PlateLabel(text: "KEYS ?", size: 8, weight: .bold, color: PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .help("The player's keyboard reference (?)")
            if !transportStatus.isEmpty {
                PlateLabel(text: transportStatus, size: 8, color: PlateColor.inkFaint)
                    .lineLimit(1)
            }
            if !microphoneStatus.isEmpty {
                PlateLabel(text: microphoneStatus, size: 8.5, color: PlateColor.inkFaint)
                    .lineLimit(1)
            }
            if !lookStatus.isEmpty {
                PlateLabel(text: lookStatus, size: 8.5, color: CanonColor.rust)
                    .lineLimit(1)
            }
            if !footageStatus.isEmpty {
                PlateLabel(text: footageStatus, size: 8.5, color: PlateColor.inkFaint)
                    .lineLimit(1)
            }
            if !youtubeExportStatus.isEmpty {
                PlateLabel(text: youtubeExportStatus, size: 8.5, color: PlateColor.inkFaint)
                    .lineLimit(1)
            }
            Spacer()
            if activeLook != nil {
                // Named for what it DOES: this Look already IS this cut's
                // output (a version, not a row) — this is the gesture that
                // makes it a row, and the row lands directly below.
                Button(isContinuingLook ? "Keeping…" : "Keep as New CUT (below)") {
                    isContinuingLook = true
                    lookStatus = ""
                    Task { @MainActor in
                        let created = await onContinueLookAsNewShot()
                        isContinuingLook = false
                        if created == nil { lookStatus = "Could not create CUT" }
                    }
                }
                .buttonStyle(PlateButtonStyle())
                .disabled(isContinuingLook || isRenderBlocked)
                .help("Flattens this Look (picture + this cut's current audio mix) into a NEW CUT row "
                    + "directly below this one, as reusable footage. The Look also stays here as a version — "
                    + "keeping it as a CUT is for editing it further, combining it, or sequencing it.")
            }
            Button(activeRestyle.map { $0.status.uppercased() } ?? "Restyle") {
                isRestyleComposerOpen = true
            }
            .buttonStyle(PlateButtonStyle(isProminent: activeRestyle == nil))
            .disabled(!videoExists || isPreviewingClip || isPreparingPlayer)
            .popover(isPresented: $isRestyleComposerOpen, arrowEdge: .bottom) {
                ShotRestyleComposer(
                    prompt: $restylePrompt,
                    enhancePrompt: $restyleEnhancePrompt,
                    seed: $restyleSeed,
                    styleSelection: $restyleStyleSelection,
                    sourceDurationSeconds: max(
                        assembly.outputSeconds,
                        Double(artifact?.totalSeconds ?? 0)
                    ),
                    hasFALCredential: hasFALCredential,
                    hasDecartCredential: hasDecartCredential,
                    isVideoOperationBlocked: isRenderBlocked && activeRestyle == nil,
                    activeLook: activeRestyle,
                    recoverableLook: recoverableLook,
                    onSubmit: { provider in
                        onStartRestyle(
                            restylePrompt,
                            restyleEnhancePrompt,
                            restyleSeed,
                            restyleStyleSelection,
                            provider
                        )
                    },
                    onCancel: onCancelRestyle,
                    onRetry: onRetryRestyle,
                    onBrowseStyles: {
                        // House pattern: never present a sheet from popover
                        // content — close the popover, let the host present.
                        isRestyleComposerOpen = false
                        isRestyleStylePickerOpen = true
                    }
                )
            }
            Button {
                collectCurrentFrame()
            } label: {
                Label(isCollectingFrame ? "Collecting…" : "Collect Frame", systemImage: "plus.rectangle.on.rectangle")
            }
            .buttonStyle(PlateButtonStyle())
            .disabled(!videoExists || isCollectingFrame || isPreparingPlayer || !playbackError.isEmpty)
            .help("Capture the current playhead moment as a still in Media — it becomes a Story Input and a Frame Creator reference")
            if !collectStatus.isEmpty {
                // Failure has to read as failure: this label is the only feedback
                // the user gets, since the engine's status line sits behind this
                // full-screen modal.
                PlateLabel(
                    text: collectStatus,
                    size: 8.5,
                    color: collectFailed ? CanonColor.brass : PlateColor.inkFaint
                )
            }
            Button(isSendingToFootage ? "Sending…" : "Send to Footage") {
                isSendingToFootage = true
                footageStatus = ""
                Task { @MainActor in
                    let sent = await onSendToFootage()
                    isSendingToFootage = false
                    footageStatus = sent
                        ? "In the Footage tray — drag it into any shot"
                        : "Could not send to Footage"
                }
            }
            .buttonStyle(PlateButtonStyle())
            .disabled(
                !videoExists
                    || isSendingToFootage
                    || isPreviewingClip
                    || isPreparingPlayer
                    || !playbackError.isEmpty
                    || isRenderBlocked
            )
            .help("Flatten exactly what plays here — cut layer, active Look, audio mix — into the Footage tray")
            Button(isExportingForYouTube ? "Exporting for YouTube…" : "Export for YouTube") {
                isExportingForYouTube = true
                youtubeExportStatus = ""
                Task { @MainActor in
                    youtubeExportStatus = await onExportForYouTube()
                    isExportingForYouTube = false
                }
            }
            .buttonStyle(PlateButtonStyle())
            .disabled(
                !videoExists
                    || isExportingForYouTube
                    || isSendingToFootage
                    || isPreviewingClip
                    || isPreparingPlayer
                    || !playbackError.isEmpty
                    || isRenderBlocked
            )
            .help("One click: this cut's .mp4 plus a YouTube title + description .md land in ~/Downloads/LitScenes-Finals")
            Button("Reveal in Finder") {
                if let path = currentVideoPath {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            .buttonStyle(PlateButtonStyle())
            .disabled(!revealTargetExists)
            .help(isPreviewingClip ? "Reveal this segment's clip file" : "Reveal the shot's stitched video file")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var lookCycler: some View {
        let looks = shot.browsableLookVersions
        if !looks.isEmpty {
            HStack(spacing: 7) {
                PlateLabel(text: "LOOK", size: 8, weight: .bold, color: PlateColor.inkFaint)
                Button {
                    onActivateLook("")
                } label: {
                    Text("ORIGINAL")
                        .font(.system(size: 8.5, weight: activeLook == nil ? .bold : .regular, design: .serif))
                        .foregroundStyle(activeLook == nil ? PlateColor.ink : PlateColor.inkFaint)
                        .padding(.vertical, 4)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(activeLook == nil ? PlateColor.ink : .clear).frame(height: 1)
                        }
                }
                .buttonStyle(.plain)
                ForEach(looks, id: \.versionId) { look in
                    let selected = activeLook?.versionId == look.versionId
                    Button {
                        onActivateLook(look.versionId)
                    } label: {
                        Text(FrameCreatorModal.romanNumeral(look.versionNumber).lowercased())
                            .font(.system(size: 10.5, weight: selected ? .bold : .regular, design: .serif))
                            .foregroundStyle(selected ? PlateColor.ink : PlateColor.inkFaint)
                            .frame(minWidth: 18, minHeight: 22)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(selected ? PlateColor.ink : .clear).frame(height: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(look.styleLabel.trimmed.isEmpty
                        ? "Look \(look.versionNumber) · Lucy · seed \(look.seed)"
                        : "Look \(look.versionNumber) · Lucy · seed \(look.seed) · \(look.styleLabel)")
                }
            }
        }
    }

    /// The version browser: one lowercase numeral per ready render, the active
    /// one distinct. Tapping a numeral makes that version the shot's selected
    /// render (persisted) — viewing IS selecting.
    @ViewBuilder
    private var versionCycler: some View {
        let versions = shot.browsableRenderVersions
        if versions.count > 1 {
            HStack(spacing: 8) {
                ForEach(versions, id: \.versionId) { version in
                    let isActive = shot.isActiveRenderVersion(version)
                    Button {
                        if !isActive {
                            onActivateVersion(version.versionId)
                        }
                    } label: {
                        Text(FrameCreatorModal.romanNumeral(version.versionNumber).lowercased())
                            .font(.system(size: 11, weight: isActive ? .bold : .regular, design: .serif))
                            .foregroundStyle(isActive ? PlateColor.ink : PlateColor.inkFaint)
                            .frame(minWidth: 18, minHeight: 22)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(isActive ? PlateColor.ink : .clear)
                                    .frame(height: 1)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isActive
                        ? "Version \(version.versionNumber) — the shot's selected render"
                        : "Show version \(version.versionNumber) and make it the shot's selected render")
                }
            }
        }
    }

    private func versionsPlateSheet() -> some View {
        ShotRenderVersionsPlateView(
            shot: shot,
            planPlacementKeys: planSegments.map { segment in
                switch segment {
                case .generated(let item): return item.pair.placementKey
                case .footage(let footage): return footage.placementKey
                // Never in planSegments (assembly-only); the artifact key can
                // never collide with a saved clip's placement key.
                case .artifactFallback(let artifact): return shotArtifactSegmentKey(versionId: artifact.versionId)
                }
            },
            onActivateVersion: { versionId in
                onActivateVersion(versionId)
                isVersionsPlateOpen = false
            },
            onClose: { isVersionsPlateOpen = false }
        )
    }

    private var loopToggleButton: some View {
        Button {
            toggleLoop()
        } label: {
            PlateLabel(
                text: "LOOP",
                size: 8,
                weight: .bold,
                color: isLoopEnabled ? CanonColor.brass : PlateColor.inkFaint
            )
        }
        .buttonStyle(.plain)
        .help(isLoopEnabled
            ? "Looping — playback restarts at the end (⌥L). Turn off to judge the tail without wrapping."
            : "Loop off — playback rests at the last frame (⌥L)")
    }

    /// Provenance from the version's own clips — a two-model mix is NAMED
    /// ("WAN 2.7 + Kling 3 Pro"), never flattened to a shrug. With no
    /// artifact at all, the default is intent and says so.
    private var footerProvenanceLabel: String {
        if let artifact { return shotRenderProvenanceSummary(version: artifact) }
        return "NEXT · \(shot.renderStack.shortLabel)"
    }

    /// One click from the numerals to the whole provenance story. Shown from
    /// the first version — archaeology should not wait for a second render.
    @ViewBuilder
    private var versionsPlateButton: some View {
        if !shot.renderVersions.isEmpty {
            Button {
                isVersionsPlateOpen = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .help("Every version's provenance — models, prompts, durations, traces, and what was reused")
        }
    }

    /// Honest disclosure while playback substitutes a ready version for the
    /// selected one (re-render in flight, or the newest version failed). The
    /// pointer is untouched; a completed render re-activates and playback
    /// flips to it automatically.
    @ViewBuilder
    private var substitutionBadge: some View {
        if let active = shot.activeRenderVersion,
           let playable = shot.playableRenderVersion,
           active.versionId != playable.versionId {
            let activeRoman = FrameCreatorModal.romanNumeral(active.versionNumber)
            let playableRoman = FrameCreatorModal.romanNumeral(playable.versionNumber)
            if active.status == "generating" {
                PlateLabel(
                    text: "RENDERING \(activeRoman) — SHOWING \(playableRoman)",
                    size: 8,
                    weight: .semibold,
                    color: CanonColor.brass
                )
                .help("Version \(active.versionNumber) is rendering — you're watching the last finished render. Playback flips to the new version when it completes.")
            } else if active.status == "failed" {
                PlateLabel(
                    text: "\(activeRoman) FAILED — SHOWING \(playableRoman)",
                    size: 8,
                    weight: .semibold,
                    color: CanonColor.rust
                )
                .help("Version \(active.versionNumber) failed — you're watching the last finished render.")
            }
        }
    }

    private func preparePlayer(resume: Bool = true) {
        guard videoExists else { return }
        let resumeTime = resume ? player?.currentTime() : nil
        if pendingSeekSeconds == nil,
           let resumeTime,
           resumeTime.isValid,
           resumeTime.seconds > 0 {
            pendingSeekSeconds = resumeTime.seconds
        }
        player?.pause()
        removeTimeObserver()
        player?.replaceCurrentItem(with: nil)
        player = nil
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        // Rapid source switches (segment preview toggles) must not swap the
        // player out of order — only the newest load may land.
        playerLoadToken += 1
        let token = playerLoadToken
        isPreparingPlayer = true
        playbackError = ""
        Task { @MainActor in
            do {
                if usesCutComposition || activeLook != nil {
                    await loadClipDurations()
                }
                guard token == playerLoadToken else { return }
                let item = try await makePlayerItem()
                guard token == playerLoadToken else { return }
                let newPlayer = AVPlayer(playerItem: item)
                loopObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        if microphoneRecorder.phase == .recording {
                            stopMicrophoneRecording()
                        } else if ShotPlayerTransportPreference.loopEnabled {
                            // Read the LIVE preference — this closure outlives
                            // any number of footer toggles.
                            newPlayer.seek(to: .zero)
                            newPlayer.play()
                        } else {
                            // Loop off: rest at the true last frame, resolved
                            // exactly so the readout and at-playhead edits
                            // agree about where the tail is.
                            pausePlaybackResolvingPlayhead()
                        }
                    }
                }
                player = newPlayer
                installTimeObserver(on: newPlayer)
                if let pendingSeekSeconds {
                    let endSeconds = item.forwardPlaybackEndTime.isValid
                        && item.forwardPlaybackEndTime.seconds.isFinite
                        && item.forwardPlaybackEndTime.seconds > 0
                        ? item.forwardPlaybackEndTime.seconds
                        : timelineDurationSeconds
                    let target = CMTime(
                        seconds: min(max(pendingSeekSeconds, 0), max(endSeconds - 1.0 / 600.0, 0)),
                        preferredTimescale: 600
                    )
                    self.pendingSeekSeconds = nil
                    await newPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                }
                playbackError = ""
                isPreparingPlayer = false
                newPlayer.play()
            } catch {
                guard token == playerLoadToken else { return }
                isPreparingPlayer = false
                if usesCutComposition || activeLook != nil {
                    playbackError = String(error.localizedDescription.prefix(260))
                }
            }
        }
    }

    private func installTimeObserver(on player: AVPlayer) {
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { time in
            Task { @MainActor in
                playheadSeconds = max(time.seconds, 0)
                // Loop preview: repeat the selected span (capture-loose — one
                // observer tick of slack, exactly like the Studio's scrubber).
                if let range = loopPreviewRange, playheadSeconds >= range.upperBound - 0.02 {
                    seek(toOutputSeconds: range.lowerBound)
                    player.play()
                }
                if microphoneRecorder.phase == .recording,
                   monitorPlayback,
                   timelineDurationSeconds > 0,
                   playheadSeconds >= timelineDurationSeconds - 0.05 {
                    stopMicrophoneRecording()
                }
            }
        }
    }

    /// Preview and export share one track graph: cut-aware source audio,
    /// narration, and the active microphone take with persisted lane gains.
    private func makePlayerItem() async throws -> AVPlayerItem {
        if let previewClip {
            return AVPlayerItem(url: URL(fileURLWithPath: previewClip.clipPath))
        }
        // One snapshot for the whole function: the specs that lay the audio down
        // and the source gain windows that shape it MUST come from the same
        // assembly, or the windows land at the wrong seconds.
        let cutAssembly = assembly
        if let activeLook {
            let originalAudioAsset: AVAsset?
            if cutAssembly.hasPlayableClips {
                let original = try await VideoChainMedia.buildStitchComposition(
                    specs: cutAssembly.playableSpecs,
                    profile: VideoOutputProfile.standard(.landscape16x9, fitPolicy: .fitWithBlurFill)
                )
                originalAudioAsset = original.composition
            } else if let originalPath = artifact?.videoPath.trimmed.nilIfEmpty {
                originalAudioAsset = AVURLAsset(url: URL(fileURLWithPath: originalPath))
            } else {
                originalAudioAsset = nil
            }
            let videoURL = URL(fileURLWithPath: activeLook.videoPath)
            guard let mixed = await ShotAudioComposition.buildLook(
                videoURL: videoURL,
                originalAudioAsset: originalAudioAsset,
                sourceDurationSeconds: activeLook.sourceDurationSeconds,
                shot: shot,
                assembly: cutAssembly.hasPlayableClips ? cutAssembly : nil,
                loopCount: outputLoopCount
            ) else {
                throw ScreenGraphError.capture("The Look audio mix could not be prepared for preview.")
            }
            let item = AVPlayerItem(asset: mixed.composition)
            item.audioMix = mixed.audioMix
            item.forwardPlaybackEndTime = mixed.composition.duration
            return item
        }
        if usesCutComposition {
            let profile = VideoOutputProfile.standard(.landscape16x9, fitPolicy: .fitWithBlurFill)
            let built = try await VideoChainMedia.buildStitchComposition(
                specs: cutAssembly.playableSpecs,
                profile: profile
            )
            let tolerance = 1.0 / Double(max(profile.fps, 1)) + 0.002
            guard abs(built.durationSeconds - cutAssembly.outputSeconds) <= tolerance else {
                throw ScreenGraphError.capture(
                    "The cut timeline and visual composition disagree by more than one frame. Retry after media metadata reloads."
                )
            }
            let audioMix = await ShotAudioComposition.applyMix(
                to: built.composition,
                shot: shot,
                assembly: cutAssembly
            )
            let item = AVPlayerItem(asset: built.composition)
            item.videoComposition = built.videoComposition
            item.audioMix = audioMix
            item.forwardPlaybackEndTime = CMTime(
                seconds: built.durationSeconds,
                preferredTimescale: 600
            )
            return item
        }
        guard let path = currentVideoPath else {
            throw ScreenGraphError.capture("No rendered video is available for this Shot.")
        }
        let videoURL = URL(fileURLWithPath: path)
        guard let mixed = await ShotAudioComposition.buildLegacy(videoURL: videoURL, shot: shot) else {
            return AVPlayerItem(url: videoURL)
        }
        let item = AVPlayerItem(asset: mixed.composition)
        item.audioMix = mixed.audioMix
        return item
    }

    /// Collect Frame: map the playhead to the SOURCE file actually on screen
    /// (segment clip, bridge, Look, previewed clip, or the stitched video)
    /// and hand it to the engine. Pause not required.
    private func collectCurrentFrame() {
        let time = player?.currentTime()
        let t = max((time?.isValid == true ? time?.seconds : nil) ?? playheadSeconds, 0)
        let capture: (path: String, fileSeconds: Double)?
        if let previewClip {
            capture = (previewClip.clipPath, t)
        } else if let look = activeLook, let path = look.videoPath.trimmed.nilIfEmpty {
            // Retimed Looks are captured at output time — capture-grade. A
            // looped Look tiles one file, so fold the playhead back into the
            // first pass; the frame on screen is the same either way.
            let passSeconds = max(ShotAudioComposition.effectiveLookDurationSeconds(look), 0)
            let folded = outputLoopCount > 1 && passSeconds > 0
                ? t.truncatingRemainder(dividingBy: passSeconds)
                : t
            capture = (path, folded)
        } else if usesCutComposition, let mapped = assembly.sourceCapture(forOutputSeconds: t) {
            capture = (mapped.url.path, mapped.fileSeconds)
        } else if let path = currentVideoPath {
            capture = (path, t)
        } else {
            capture = nil
        }
        guard let capture else {
            collectStatus = "Nothing to collect yet"
            collectFailed = true
            return
        }
        isCollectingFrame = true
        collectStatus = ""
        collectFailed = false
        Task { @MainActor in
            let collected = await onCollectFrame(capture.path, capture.fileSeconds, t)
            isCollectingFrame = false
            collectFailed = !collected
            let message = collected
                ? "Frame collected to Media ▸ Creations"
                : "Could not collect the frame"
            collectStatus = message
            // A transient confirmation, not a permanent caption — but never clear
            // a message a later collect has already replaced.
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if collectStatus == message {
                collectStatus = ""
                collectFailed = false
            }
        }
    }
}
