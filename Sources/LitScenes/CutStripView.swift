import SwiftUI
import AppKit

// MARK: - Cut strip (one CUT: an ordered timeline hanging off its STAGE)
//
// The row anatomy carried over from the retired SHOTS band: rail (numeral,
// name, runtime, Jovilabe dial, render controls, narrate) + a horizontal
// entry strip with gap-insert, seam toggles, and drop-to-replace. New here:
// the append "+" slot is finally a BUTTON — it opens a picker of the stage's
// gathered inputs plus a "New frame…" path, so building a cut never requires
// leaving the strip.

/// Everything a cut strip needs from the workbench, bundled once and shared
/// by every strip on the canvas. Closures take the cutId (== shotId) so the
/// same bundle serves all cuts.
struct CutStripActions {
    var frameLookup: [String: ProjectLensHeroImage] = [:]
    var mediaLookup: [String: MediaItemRecord] = [:]
    var meaningNodes: [LensContextPromptMeaningNode] = []
    /// The OPEN rows (max 3), most-recently-used first — the workbench's one
    /// law for which cut strips build their contents. Every other row renders
    /// a collapsed summary line and constructs none of its heavy subtrees.
    var openCutIds: [String] = []
    /// Marks a cut as the ACTIVE open row (front of the MRU). Fired by the
    /// collapsed row's expand tap and by every row-scoped callback via
    /// `markingRowActive()`.
    var onTouchCut: (String) -> Void = { _ in }
    var activeShotRenderId = ""
    var configuredRenderModels: Set<ShotRenderModel> = []
    var activeShotNarrationId = ""
    var activeShotNarrationSpeedId = ""
    var activeShotChipsId = ""
    var accountVoiceOptions: [StoryAudioVoiceOption] = []
    /// Voice ids curated out of the render-time voice menus (Voices tab).
    var hiddenNarrationVoiceIds: Set<String> = []
    var narrationFocusRequest: ShotNarrationFocusRequest?
    var renderPlanFocusRequest: ShotRenderPlanFocusRequest?
    /// Live FAL rates (day-cached) for the render-plan strip's estimate.
    var falPricing: FALPricingSnapshot?
    var isFetchingVideoPricing = false

    var onRename: (String, String) -> Void = { _, _ in }
    /// Soft-delete: the cut moves to the DELETED CUTS shelf (restorable).
    var onTrash: (String) -> Void = { _ in }
    /// NEW VERSION: duplicate a rendered cut into an editable, unrendered twin.
    var onDuplicate: (String) -> Void = { _ in }
    /// Restores a combined CUT's preserved sources and archives the parent.
    var onUncombine: (String) -> Void = { _ in }
    var onAddToFinals: (String) -> Void = { _ in }
    var onOpenJovilabe: (String) -> Void = { _ in }
    var onSetRenderStack: (String, ShotRenderStack) -> Void = { _, _ in }
    /// Segment-scoped recipe persistence uses placement identity so repeated
    /// appearances of the same frame or clip never share an override.
    var onSetSegmentRenderStack: (String, ShotRenderPair, ShotRenderStack?) -> Void = { _, _, _ in }
    /// (shotId, entryId) — picks the narration-driven render's anchor frame;
    /// empty entryId returns to the first-ready default.
    var onSetNarrationAnchor: (String, String) -> Void = { _, _ in }
    /// (shotId, entryId) — vouches the named anchor entry past the lip-sync
    /// face check; empty entryId re-arms the check.
    var onSetNarrationAnchorFaceOverride: (String, String) -> Void = { _, _ in }
    /// Two-step render confirm: persists the strip's prompt drafts as
    /// overrides, then fires the render. RENDER/RETRY buttons only toggle
    /// the plan strip — nothing spends until this runs.
    /// nil filter = full render; a key set renders only those segments and
    /// reuses every other saved clip (suffix render / resume).
    var onConfirmRender: (String, [ShotSegmentPromptOverride], Set<String>?) -> Void = { _, _, _ in }
    /// Debounced draft autosave from the plan strip (upsert-only union).
    var onAutosavePromptOverrides: (String, [ShotSegmentPromptOverride]) -> Void = { _, _ in }
    /// Persists segment direction plans (beats) from the plan strip —
    /// autosave passes the upsert-only merge, confirm the computed set.
    var onSaveDirectionPlans: (String, [ShotSegmentDirectionPlanRecord]) -> Void = { _, _ in }
    /// LLM beat-drafting lane state (keys are "shotId|pairKey") and the
    /// per-segment trigger: (cutId, segmentKey).
    var draftingDirectionKeys: Set<String> = []
    var directionDraftErrors: [String: String] = [:]
    var onDraftDirectionPlan: (String, String) -> Void = { _, _ in }
    /// Fired when a plan strip opens — refreshes FAL rates if stale.
    var onRenderPlanOpened: () -> Void = {}
    var onRequestRerender: (String) -> Void = { _ in }
    var onOpenShotVideo: (String) -> Void = { _ in }
    var onOpenNarration: (String) -> Void = { _ in }
    /// OPEN: the fully-seed-covered combined draft has nothing left to
    /// generate, so this skips the plan-strip review, assembles locally for
    /// $0, and opens the full instrument the moment it's ready.
    var onFinalizeAndOpen: (String) -> Void = { _ in }
    var onGenerateShotChips: (String, Bool) -> Void = { _, _ in }
    /// (cutId, messagingText, voicePresetId, scriptOverride)
    var onNarrateShot: (String, String, String, String?) -> Void = { _, _, _, _ in }
    var onSetShotNarrationSpeed: (String, Double) -> Void = { _, _ in }

    var onInsertFrame: (String, ShotFrameTransfer, Int) -> Void = { _, _, _ in }
    var onInsertClip: (String, String, Int) -> Void = { _, _, _ in }
    var onMoveEntry: (String, String, Int) -> Void = { _, _, _ in }
    var onRemoveEntry: (String, String) -> Void = { _, _ in }
    var onSetSeamStyle: (String, String, ShotSeamStyle) -> Void = { _, _, _ in }
    /// Opens a Frame with its exact CUT placement so the detail overlay can
    /// browse neighboring Frame entries, including repeated placements.
    var onOpenFrame: (String, String, ProjectLensHeroImage) -> Void = { _, _, _ in }
    /// Opens the Frame Creator on a planned (never-rendered) frame so it can
    /// be art-directed and fulfilled in place. Only `.box` (SCENES v2) cells
    /// invoke it — v1 builds the closure and never calls it. Deliberately not
    /// wrapped by `markingRowActive()`: it opens a modal, not a row edit.
    var onArtDirectPlannedFrame: (ProjectLensHeroImage) -> Void = { _ in }
    /// Enters full-screen Excursion mode on a ready frame at its exact cut
    /// placement: (cutId, entryId, frame). Dives punch INTO the frame and
    /// land there-and-back excursions beside this entry.
    var onEnterExcursion: (String, String, ProjectLensHeroImage) -> Void = { _, _, _ in }
    var onOpenClip: (String, String) -> Void = { _, _ in }
    /// Prepends an AI lead-in entry to this cut (the gap-0 wand).
    var onLeadIn: (String) -> Void = { _ in }

    /// Appends one of the stage's gathered inputs to this cut (the "+" picker).
    var onAppendPoolInput: (String, StageInput) -> Void = { _, _ in }
    /// Opens the Frame Creator seeded for this stage with append-to-cut set.
    var onCreateFrameForCut: (String) -> Void = { _ in }
    /// STRUCTURAL PASTE (row right-click): copied segment cards land at this
    /// cut's end as first-class material — pair entries, prompt/stack
    /// overrides, and the rendered take as a seed clip.
    var onPasteSegmentCards: (String, [ShotPictureSegmentSpanRef]) -> Void = { _, _ in }
    /// Flattens this cut's ACTIVE Look (picture + the cut's current audio
    /// mix) into a new CUT row inserted directly below this one.
    var onKeepLookAsNewCut: (String) -> Void = { _ in }
}

struct ShotNarrationFocusRequest: Identifiable, Equatable {
    let id = UUID()
    var shotId: String
}

struct ShotRenderPlanFocusRequest: Identifiable, Equatable {
    let id = UUID()
    var shotId: String
    var segmentPlacementKey: String
}

extension CutStripActions {
    /// One law: a gesture on a cut row makes it the ACTIVE open row. Rather
    /// than sprinkle touch calls through the strip, every row-scoped callback
    /// is wrapped here once, at the single seam the workbench already funnels
    /// them through. Passive callbacks stay unwrapped: the draft autosave fires
    /// without a gesture, and onTrash must not spend
    /// an open slot on a row that is leaving.
    func markingRowActive() -> CutStripActions {
        var wrapped = self
        let touch = onTouchCut
        wrapped.onRename = { touch($0); self.onRename($0, $1) }
        wrapped.onDuplicate = { touch($0); self.onDuplicate($0) }
        wrapped.onUncombine = { touch($0); self.onUncombine($0) }
        wrapped.onAddToFinals = { touch($0); self.onAddToFinals($0) }
        wrapped.onOpenJovilabe = { touch($0); self.onOpenJovilabe($0) }
        wrapped.onSetRenderStack = { touch($0); self.onSetRenderStack($0, $1) }
        wrapped.onSetSegmentRenderStack = { touch($0); self.onSetSegmentRenderStack($0, $1, $2) }
        wrapped.onSetNarrationAnchor = { touch($0); self.onSetNarrationAnchor($0, $1) }
        wrapped.onSetNarrationAnchorFaceOverride = { touch($0); self.onSetNarrationAnchorFaceOverride($0, $1) }
        wrapped.onConfirmRender = { touch($0); self.onConfirmRender($0, $1, $2) }
        wrapped.onRequestRerender = { touch($0); self.onRequestRerender($0) }
        wrapped.onOpenShotVideo = { touch($0); self.onOpenShotVideo($0) }
        wrapped.onOpenNarration = { touch($0); self.onOpenNarration($0) }
        wrapped.onFinalizeAndOpen = { touch($0); self.onFinalizeAndOpen($0) }
        wrapped.onGenerateShotChips = { touch($0); self.onGenerateShotChips($0, $1) }
        wrapped.onNarrateShot = { touch($0); self.onNarrateShot($0, $1, $2, $3) }
        wrapped.onSetShotNarrationSpeed = { touch($0); self.onSetShotNarrationSpeed($0, $1) }
        wrapped.onInsertFrame = { touch($0); self.onInsertFrame($0, $1, $2) }
        wrapped.onInsertClip = { touch($0); self.onInsertClip($0, $1, $2) }
        wrapped.onMoveEntry = { touch($0); self.onMoveEntry($0, $1, $2) }
        wrapped.onRemoveEntry = { touch($0); self.onRemoveEntry($0, $1) }
        wrapped.onSetSeamStyle = { touch($0); self.onSetSeamStyle($0, $1, $2) }
        wrapped.onOpenFrame = { touch($0); self.onOpenFrame($0, $1, $2) }
        wrapped.onEnterExcursion = { touch($0); self.onEnterExcursion($0, $1, $2) }
        wrapped.onOpenClip = { touch($0); self.onOpenClip($0, $1) }
        wrapped.onLeadIn = { touch($0); self.onLeadIn($0) }
        wrapped.onAppendPoolInput = { touch($0); self.onAppendPoolInput($0, $1) }
        wrapped.onCreateFrameForCut = { touch($0); self.onCreateFrameForCut($0) }
        wrapped.onPasteSegmentCards = { touch($0); self.onPasteSegmentCards($0, $1) }
        wrapped.onKeepLookAsNewCut = { touch($0); self.onKeepLookAsNewCut($0) }
        return wrapped
    }
}

/// How a CutStripView fills its host. `.standard` is the SCENES tab's
/// full-width row (116pt left rail + trailing button column). `.box` is the
/// SCENES v2 working box: the rail recomposes as a header bar above the strip
/// so the row survives at ~half the workspace width. Cells are identical in
/// both — only the chrome moves.
enum CutStripLayout {
    case standard
    case box
}

struct CutStripView: View {
    static let cellSize = CGSize(width: 196, height: 110)
    private static let gapWidth: CGFloat = 14
    private static let railWidth: CGFloat = 116

    let cut: ProjectShot
    let index: Int
    /// The owning stage's palette, for the append picker (inputs not already
    /// placed in this cut lead; placed ones are offered again further down —
    /// reuse is legal in a timeline).
    var poolInputs: [StageInput] = []
    var actions: CutStripActions
    var layout: CutStripLayout = .standard
    /// `.box` only: what an empty Scene asks for, named by the caller from what
    /// actually sits below the stage (suggested / rendered Frames).
    var emptySceneHintText: String = "Drag Frames or Footage from the pool below — or click + to pick material or render a new Frame."

    // MARK: Dress
    //
    // `.box` (SCENES v2) prints the row as a cream plate in the dark well;
    // every `.standard` arm below is the row's original literal, so the
    // SCENES tab renders exactly as before.
    private var isPlate: Bool { layout == .box }
    private var cardRadius: CGFloat { isPlate ? ScenesV2StageDress.cardRadius : 12 }
    private var cardFill: Color { isPlate ? ScenesV2StageDress.cardFill : Color.white.opacity(0.34) }
    private var cardStroke: Color { isPlate ? ScenesV2StageDress.hairline : CanonColor.hairlinePaper.opacity(0.9) }
    private var metaInk: Color { isPlate ? ScenesV2StageDress.inkFaint : CanonColor.muted.opacity(0.8) }
    private var chipInk: Color { isPlate ? ScenesV2StageDress.ink : CanonColor.ink.opacity(0.62) }
    private var chipStroke: Color { isPlate ? ScenesV2StageDress.hairline : CanonColor.hairlinePaper.opacity(0.8) }
    private func chipFill(_ legacyOpacity: Double) -> Color {
        isPlate ? ScenesV2StageDress.insetFill : CanonColor.paperInset.opacity(legacyOpacity)
    }
    /// The quiet voice for idle chrome: faint ink on the plate, muted gray in the row.
    private var quietTint: Color { isPlate ? ScenesV2StageDress.inkFaint : CanonColor.muted }
    private func quiet(_ legacyOpacity: Double) -> Color {
        isPlate ? ScenesV2StageDress.inkFaint : CanonColor.muted.opacity(legacyOpacity)
    }
    private func slotStroke(_ legacyOpacity: Double) -> Color {
        isPlate ? ScenesV2StageDress.hairline : CanonColor.hairlinePaper.opacity(legacyOpacity)
    }
    private func slotFill(_ legacyOpacity: Double) -> Color {
        isPlate ? ScenesV2StageDress.insetFill : CanonColor.paperInset.opacity(legacyOpacity)
    }

    @State private var expandedNarration = false
    @State private var expandedRenderPlan = false
    /// `.box` only: the render disclosure remembers its last state across
    /// Scenes and projects — open by default, and closed until reopened once
    /// the operator closes it. Confirming a render never counts as closing.
    @AppStorage("LITSCENES_V2_RENDER_PLAN_OPEN") private var renderPlanOpenPreference = true
    @State private var expandedSources = false
    @State private var isConfirmingUncombine = false
    @State private var hoveredEntryId = ""
    @State private var isHoveringStrip = false
    @State private var targetedGapIndex: Int?
    @State private var targetedCellEntryId = ""
    @State private var isAppendTargeted = false
    @State private var isAppendPickerOpen = false
    @State private var appendSearchQuery = ""
    @State private var isTrashArmed = false
    @State private var trashArmGeneration = 0
    @StateObject private var narrationPlayer = NarrationAudioPlayer()

    /// A rendered (or rendering) cut is IMMUTABLE: its strip must keep
    /// matching the video it produced. Structure edits are refused; iterate
    /// via NEW VERSION. A failed-only render does not lock — retry needs an
    /// editable timeline.
    private var isLocked: Bool {
        actions.activeShotRenderId == cut.shotId
            || cut.renderArtifact?.status == "generating"
            || !cut.browsableRenderVersions.isEmpty
    }

    /// The suffix tail of this locked cut (mirror of the engine's law):
    /// non-nil only when quiet and the ready active version carries a
    /// watermark. Entries at or past this index are appendable/editable.
    private var tailStartIndex: Int? {
        guard actions.activeShotRenderId != cut.shotId,
              cut.renderArtifact?.status != "generating" else { return nil }
        return shotSuffixTailStartIndex(shot: cut)
    }

    private var isSuffixAppendable: Bool {
        isLocked && tailStartIndex != nil
    }

    private func isTailIndex(_ index: Int) -> Bool {
        tailStartIndex.map { index >= $0 } ?? false
    }

    private func isTailEntry(_ entryId: String) -> Bool {
        guard let tail = tailStartIndex,
              let index = cut.entries.firstIndex(where: { $0.entryId == entryId }) else { return false }
        return index >= tail
    }

    /// The picture clipboard's structural cards, read at menu-open. An append
    /// lands in a locked cut's suffix tail; a hard-locked cut disables here
    /// (the engine refuses honestly regardless).
    @ViewBuilder
    private var pasteSegmentMenuItem: some View {
        let cards = ShotPictureClipboard.read()?.spans.filter(\.isSegmentCard) ?? []
        Button(cards.isEmpty
            ? "Paste Segment — copy one from a player's Re-render panel first"
            : "Paste Segment at End\(cards.count > 1 ? " ×\(cards.count)" : "")") {
            actions.onPasteSegmentCards(cut.shotId, cards)
        }
        .disabled(cards.isEmpty || (isLocked && !isSuffixAppendable))
    }

    /// Whether this row is one of the workbench's OPEN 3 (MRU). Collapsed rows
    /// build none of the heavy subtrees: no entry cells (each a full-image
    /// decode), no segment-plan computation.
    private var isOpen: Bool {
        actions.openCutIds.contains(cut.shotId)
    }

    var body: some View {
        Group {
            if isOpen {
                openBody
            } else {
                collapsedRow
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: cardRadius)
                .fill(cardFill)
        )
        // Right-click paste target: "onto another cut row". The menu content
        // builds at open, so the clipboard read is always fresh.
        .contextMenu { pasteSegmentMenuItem }
        .overlay(
            RoundedRectangle(cornerRadius: cardRadius)
                .stroke(cardStroke, lineWidth: 1)
        )
        .overlay {
            if isPlate {
                // Registration ticks sit inside the 12pt content padding.
                PlateCornerTicks(inset: 6, length: 8)
                    .stroke(CanonColor.brass.opacity(0.7), lineWidth: 1.5)
            }
        }
        .onAppear {
            seedBoxRenderPlan()
            consumeNarrationFocusRequest()
            consumeRenderPlanFocusRequest()
        }
        .onChange(of: cut.shotId) { _, _ in
            seedBoxRenderPlan()
        }
        .onChange(of: cut.entries.isEmpty) { _, _ in
            seedBoxRenderPlan()
        }
        .onChange(of: actions.narrationFocusRequest?.id) { _, _ in
            consumeNarrationFocusRequest()
        }
        .onChange(of: actions.renderPlanFocusRequest?.id) { _, _ in
            consumeRenderPlanFocusRequest()
        }
        .onHover { isHoveringStrip = $0 }
        .onDisappear {
            narrationPlayer.stop()
        }
    }

    /// The collapsed summary line: rail facts only — nothing here decodes an
    /// image or walks the segment plan. Click opens (and fronts) the row; a
    /// material drop lands at the strip's end and opens it, so building onto
    /// a collapsed cut never needs a separate expand step first.
    private var collapsedRow: some View {
        let isRendering = actions.activeShotRenderId == cut.shotId || cut.renderArtifact?.status == "generating"
        return HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CanonColor.brass.opacity(0.8))
            Text("SHOT \(FrameCreatorModal.romanNumeral(index + 1))")
                .font(CanonType.archive(8.5, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(CanonColor.muted)
            if !cut.name.trimmed.isEmpty {
                Text(cut.name)
                    .font(CanonType.interface(11.5, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.85))
                    .lineLimit(1)
            }
            Text("\(cut.entries.count) entr\(cut.entries.count == 1 ? "y" : "ies")")
                .font(CanonType.archive(7.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(CanonColor.muted.opacity(0.8))
            if isRendering {
                ProgressView()
                    .controlSize(.mini)
                Text("RENDERING")
                    .font(CanonType.archive(7, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(CanonColor.brass)
            } else if !cut.browsableRenderVersions.isEmpty {
                Image(systemName: "film")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CanonColor.brass.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 26)
        .contentShape(Rectangle())
        .onTapGesture { actions.onTouchCut(cut.shotId) }
        .dropDestination(for: ShotFrameTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            let end = cut.entries.count
            guard !isLocked || isTailIndex(end) else { return false }
            if transfer.isClipDrag {
                actions.onInsertClip(cut.shotId, transfer.clipMediaId, end)
            } else if !transfer.frameImageId.trimmed.isEmpty {
                actions.onInsertFrame(cut.shotId, transfer, end)
            } else {
                return false
            }
            actions.onTouchCut(cut.shotId)
            return true
        }
        .help("Click to open this Shot — the workbench keeps the 3 most recently used Shots open")
    }

    private var openBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if layout == .box {
                let context = boxPlanContext()
                boxHeaderBar(context)
                stripScroller
                    // The unified page scroll's late-pin fold line: the shot
                    // header above this edge may ride off-screen; the sticky
                    // block holds when this edge reaches the top.
                    .anchorPreference(key: ScenesV2StageStripTopKey.self, value: .top) { $0 }
                boxRenderBar(context)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    rail
                        .frame(width: Self.railWidth, alignment: .leading)
                    stripScroller
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(spacing: 2) {
                            if isLocked {
                                duplicateButton
                            }
                            trashButton
                        }
                    }
                    .frame(height: Self.cellSize.height)
                    .padding(.leading, 4)
                }
            }
            if expandedRenderPlan, actions.activeShotRenderId != cut.shotId, cut.renderArtifact?.status != "generating" {
                CutRenderPlanStrip(
                    cut: cut,
                    actions: actions,
                    layout: layout,
                    focusedSegmentKey: actions.renderPlanFocusRequest?.shotId == cut.shotId
                        ? actions.renderPlanFocusRequest?.segmentPlacementKey
                        : nil,
                    onCancel: {
                        withAnimation(.easeOut(duration: 0.15)) { expandedRenderPlan = false }
                        if layout == .box {
                            renderPlanOpenPreference = false
                        }
                    },
                    onConfirm: { overrides, onlySegmentKeys in
                        withAnimation(.easeOut(duration: 0.15)) { expandedRenderPlan = false }
                        actions.onConfirmRender(cut.shotId, overrides, onlySegmentKeys)
                    }
                )
            }
            if expandedNarration {
                ShotNarrationStrip(
                    shot: cut,
                    isLoadingChips: actions.activeShotChipsId == cut.shotId,
                    isNarrating: actions.activeShotNarrationId == cut.shotId || cut.narrationArtifact?.status == "generating",
                    isRemixingSpeed: actions.activeShotNarrationSpeedId == cut.shotId,
                    extraVoices: actions.accountVoiceOptions,
                    hiddenVoiceIds: actions.hiddenNarrationVoiceIds,
                    player: narrationPlayer,
                    onGenerateChips: { force in
                        actions.onGenerateShotChips(cut.shotId, force)
                    },
                    onNarrate: { messaging, voicePresetId, scriptOverride in
                        actions.onNarrateShot(cut.shotId, messaging, voicePresetId, scriptOverride)
                    },
                    onSetSpeed: { speed in
                        actions.onSetShotNarrationSpeed(cut.shotId, speed)
                    }
                )
            }
            if !cut.combinedSources.isEmpty {
                combinedSourcesDisclosure
            }
        }
    }

    private func consumeNarrationFocusRequest() {
        guard actions.narrationFocusRequest?.shotId == cut.shotId else { return }
        // A focus request must also OPEN the row — the strip it reveals only
        // builds inside an open body.
        actions.onTouchCut(cut.shotId)
        expandedNarration = true
        expandedRenderPlan = false
        narrationPlayer.stop()
    }

    private func consumeRenderPlanFocusRequest() {
        guard actions.renderPlanFocusRequest?.shotId == cut.shotId else { return }
        actions.onTouchCut(cut.shotId)
        expandedRenderPlan = true
        expandedNarration = false
        actions.onRenderPlanOpened()
        narrationPlayer.stop()
    }

    /// Hand-rolled chevron header (the DeletedCutsShelfView idiom — the raw
    /// SwiftUI DisclosureGroup was the only one in the app). The two actions a
    /// combined Shot exists for — inspecting sources and UNCOMBINE — live on the
    /// always-visible header row, never buried behind the disclosure.
    private var combinedSourcesDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { expandedSources.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: expandedSources ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(CanonColor.muted.opacity(0.7))
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 9, weight: .semibold))
                        Text("SOURCES · \(cut.combinedSources.count)")
                            .font(CanonType.archive(7.5, weight: .bold))
                            .kerning(0.8)
                        Text("independent snapshots")
                            .font(CanonType.archive(7.5, weight: .medium))
                            .foregroundStyle(CanonColor.muted)
                    }
                    .foregroundStyle(CanonColor.brass)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expandedSources ? "Collapse the source snapshots" : "Show the source snapshots")
                Spacer(minLength: 8)
                Button("UNCOMBINE") {
                    isConfirmingUncombine = true
                }
                .buttonStyle(PlateButtonStyle())
                .disabled(isActivelyRendering)
                .help("Restore the untouched source Shots; this combined Shot moves to DELETED SHOTS, restorable")
            }
            if expandedSources {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Snapshots copied when this Shot was combined. Later edits to source Shots do not update this timeline.")
                        .font(CanonType.archive(7.5, weight: .medium))
                        .foregroundStyle(CanonColor.muted)
                    ForEach(Array(cut.combinedSources.enumerated()), id: \.element.sourceId) { index, source in
                        HStack(spacing: 8) {
                            Text(FrameCreatorModal.romanNumeral(index + 1))
                                .font(CanonType.archive(7.5, weight: .bold))
                                .foregroundStyle(CanonColor.brass)
                                .frame(width: 18, alignment: .leading)
                            Text(source.sourceCutName.trimmed.nilIfEmpty ?? "Untitled Shot")
                                .font(CanonType.archive(8, weight: .semibold))
                                .foregroundStyle(CanonColor.ink)
                            Text("\(source.sourceEntryIds.count) entries · ~\(Int(source.outputDurationSeconds.rounded()))s")
                                .font(CanonType.archive(7.5, weight: .medium))
                                .foregroundStyle(CanonColor.muted)
                            if source.hadActiveLook {
                                Text("LOOK STAYS ON SOURCE")
                                    .font(CanonType.archive(6.5, weight: .bold))
                                    .foregroundStyle(CanonColor.brass)
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Restore the source Shots?",
            isPresented: $isConfirmingUncombine,
            titleVisibility: .visible
        ) {
            Button("Uncombine and Archive Parent") {
                actions.onUncombine(cut.shotId)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The untouched source Shots return to the workspace. This combined Shot moves to DELETED SHOTS with all of its work preserved.")
        }
    }

    // MARK: Strip

    /// The horizontal cell strip, shared verbatim by both layouts. The canon
    /// scroller draws its own always-visible-on-overflow track, so a mouse
    /// can drive a long strip without a trackpad swipe.
    private var stripScroller: some View {
        CanonHScroller {
            HStack(spacing: 0) {
                ForEach(Array(cut.entries.enumerated()), id: \.element.entryId) { entryIndex, entry in
                    gapStrip(index: entryIndex)
                    entryCell(entry)
                }
                gapStrip(index: cut.entries.count)
                appendZone
                if layout == .box, cut.entries.isEmpty {
                    emptySceneHint
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// `+ NEW` follow-through (`.box` only): a fresh Scene says what it wants
    /// instead of standing silent beside a lone append zone.
    private var emptySceneHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("An empty Scene")
                .font(CanonType.archive(8.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(ScenesV2StageDress.ink)
            Text(emptySceneHintText)
                .font(CanonType.interface(10.5))
                .foregroundStyle(ScenesV2StageDress.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 280, alignment: .leading)
        .padding(.leading, 12)
        .frame(height: Self.cellSize.height)
    }

    // MARK: Box header (SCENES v2)

    /// The `.box` layout's header bar: identity + strip-level buttons on one
    /// row above the strip so the row survives at ~half the workspace width.
    /// The render controls live in `boxRenderBar` under the frames.
    private func boxHeaderBar(_ context: BoxPlanContext) -> some View {
        let generatedSeconds = context.generatedSeconds
        let suffix = context.suffix
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                // No SHOT numeral here: the box chrome bar above already
                // carries the scene's identity ("SCENE N"), and the numeral's
                // CutTransfer drag has no valid target on the v2 page.
                CutRailNameField(
                    cutId: cut.shotId,
                    name: cut.name,
                    onRename: actions.onRename,
                    font: CanonType.display(17, weight: .semibold),
                    tint: ScenesV2StageDress.ink
                )
                .frame(width: 260, alignment: .leading)
                Text(
                    shotRuntimeSummary(shot: cut, frameLookup: actions.frameLookup, mediaLookup: actions.mediaLookup)
                        .railLabel(
                            generatedSeconds: generatedSeconds,
                            unrenderedCount: isSuffixAppendable ? suffix.missingKeys.count : 0
                        )
                )
                .font(CanonType.archive(7.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(metaInk)
                .lineLimit(1)
                Spacer(minLength: 8)
                jovilabeButton
                lookChip
                narrationToggleButton
                if isLocked {
                    duplicateButton
                }
                trashButton
            }
        }
    }

    // MARK: Rail

    /// The SHOT numeral, draggable as the whole row — shared by the rail and
    /// the box header.
    private var railDragTitle: some View {
        Text("SHOT \(FrameCreatorModal.romanNumeral(index + 1))")
            .font(CanonType.archive(8.5, weight: .semibold))
            .kerning(1.4)
            .foregroundStyle(CanonColor.muted)
            .contentShape(Rectangle())
            .help("Drag this Shot")
            .draggable(CutTransfer(cutId: cut.shotId)) {
                Text("SHOT \(FrameCreatorModal.romanNumeral(index + 1))\(cut.name.trimmed.isEmpty ? "" : " · \(cut.name)")")
                    .font(CanonType.archive(9, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(CanonColor.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(CanonColor.paperInset))
                    .overlay(Capsule().stroke(CanonColor.brass.opacity(0.6), lineWidth: 1))
            }
    }

    /// The Jovilabe dial button — shared by the rail and the box header.
    private var jovilabeButton: some View {
        Button {
            actions.onOpenJovilabe(cut.shotId)
        } label: {
            Image(systemName: "dial.min")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(cut.entries.isEmpty ? CanonColor.muted.opacity(0.35) : CanonColor.brass)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(cut.entries.isEmpty)
        .help(cut.entries.isEmpty ? "Add Frames to open this Shot's Jovilabe" : "Open this Shot's Jovilabe")
    }

    private var rail: some View {
        let plan = shotRenderSegmentPlan(
            shot: cut,
            frameLookup: actions.frameLookup,
            mediaLookup: actions.mediaLookup,
            meaningNodes: actions.meaningNodes
        )
        let generatedSeconds = plan.generatedItems.reduce(0.0) { partial, item in
            partial + Double(item.renderStack.segmentSeconds)
        }
        // Computed whenever the cut is quiet with any active version: drives
        // the +N UNRENDERED marker and RENDER NEW on ready versions, and the
        // RESUME affordance on failed ones (their kept clips reuse the same
        // missing-keys law).
        let quiet = actions.activeShotRenderId != cut.shotId && cut.renderArtifact?.status != "generating"
        let suffix = (quiet && cut.activeRenderVersion != nil)
            ? shotSuffixRenderPlan(shot: cut, segments: plan.segments, generatedItems: plan.generatedItems)
            : ShotSuffixRenderPlan()
        return VStack(alignment: .leading, spacing: 5) {
            railDragTitle
            CutRailNameField(
                cutId: cut.shotId,
                name: cut.name,
                onRename: actions.onRename
            )
            Text(
                shotRuntimeSummary(shot: cut, frameLookup: actions.frameLookup, mediaLookup: actions.mediaLookup)
                    .railLabel(
                        generatedSeconds: generatedSeconds,
                        unrenderedCount: isSuffixAppendable ? suffix.missingKeys.count : 0
                    )
            )
            .font(CanonType.archive(7.5, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(CanonColor.muted.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
            jovilabeButton
                .padding(.top, 2)
            renderControls(suffix: suffix, segmentCount: plan.segments.count)
            lookChip
            narrationToggleButton
        }
        .padding(.top, 4)
    }

    /// THE LOOK IS VISIBLE FROM THE RAIL. A finished restyle lands as a
    /// VERSION on this cut (not a new row), and until this chip existed the
    /// only way to know that was to open the player — a restyle appeared to
    /// vanish. The chip names what the row's output currently IS, and hosts
    /// the one gesture that DOES make a row: KEEP AS NEW CUT (below).
    @ViewBuilder
    private var lookChip: some View {
        let looks = cut.browsableLookVersions
        if !looks.isEmpty {
            let active = cut.activeLookVersion
            let tint = active == nil ? quietTint : CanonColor.brass
            Menu {
                Button("Open in Player") {
                    actions.onOpenShotVideo(cut.shotId)
                }
                Divider()
                if active != nil {
                    Button("Keep as New Shot (below)") {
                        actions.onKeepLookAsNewCut(cut.shotId)
                    }
                    .disabled(!actions.activeShotRenderId.isEmpty)
                } else {
                    Text("Showing Original — activate a Look in the player to keep it as a Shot")
                }
            } label: {
                HStack(spacing: 4) {
                    if let active, !active.styleHueHex.trimmed.isEmpty {
                        Circle()
                            .fill(canonColor(fromHex: active.styleHueHex))
                            .frame(width: 6, height: 6)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    Text(shotLookRailChipLabel(active: active, readyLookCount: looks.count))
                        .font(CanonType.archive(7.5, weight: .bold))
                        .kerning(0.6)
                        .lineLimit(1)
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(Capsule().fill(tint.opacity(active == nil ? 0.10 : 0.18)))
                .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 1))
                .contentShape(Capsule())
            }
            .modifier(CutStripMenuChipStyle(isPlate: isPlate))
            .menuIndicator(.hidden)
            .fixedSize()
            .help(shotLookRailChipHelp(active: active, readyLookCount: looks.count))
        }
    }

    private var narrationToggleButton: some View {
        let isReady = cut.narrationArtifact?.isReady == true
        return Button {
            expandedNarration.toggle()
            if expandedNarration {
                expandedRenderPlan = false
            }
            narrationPlayer.stop()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 8, weight: .semibold))
                Text("NARRATE")
                    .font(CanonType.archive(7.5, weight: .bold))
                    .kerning(0.6)
            }
            .foregroundStyle(isReady || expandedNarration ? CanonColor.brass : quietTint)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill((isReady || expandedNarration ? CanonColor.brass : quietTint).opacity(expandedNarration ? 0.18 : 0.10)))
            .overlay(Capsule().stroke((isReady || expandedNarration ? CanonColor.brass : quietTint).opacity(0.45), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(cut.entries.isEmpty)
        .help(
            cut.entries.isEmpty
                ? "Add Frames to narrate this Shot"
                : (expandedNarration ? "Close the narration strip" : "Narrate this Shot")
        )
        .padding(.top, 2)
    }

    // MARK: Render controls (stack menu + state-driven CTA)

    @ViewBuilder
    private func renderControls(suffix: ShotSuffixRenderPlan, segmentCount: Int) -> some View {
        let artifact = cut.renderArtifact
        // A failed version with kept clips resumes: only the missing
        // segments bill; the saved ones travel verbatim.
        let isResumable = artifact?.status == "failed"
            && suffix.reusableSegmentCount > 0
            && suffix.hasNewMaterial
        let resumeHelp = "\(suffix.reusableSegmentCount) of \(suffix.reusableSegmentCount + suffix.missingKeys.count) segments are already rendered — RESUME renders only the rest"
        let isRenderingThis = actions.activeShotRenderId == cut.shotId || artifact?.status == "generating"
        let anotherIsRendering = !actions.activeShotRenderId.isEmpty && actions.activeShotRenderId != cut.shotId
        let renderCTA = cutRenderCTA(cut: cut, segmentCount: segmentCount)
        let isSeedDraft = renderCTA.isSeedDraft
        let canFinalizeLocally = renderCTA == .finalizeFree
        // PROVENANCE, not intent: the chip names what the playable version was
        // actually rendered with, resolved from its persisted clips. The
        // picker beneath it is the NEXT-render control — and wears a NEXT
        // prefix whenever it disagrees with the rendered truth, so changing
        // the default can never again relabel an artifact it never touched.
        let provenance = cut.playableRenderVersion.map { version in
            (label: shotRenderProvenanceSummary(version: version), number: version.versionNumber)
        }
        let nextDiffers = provenance.map { $0.label != cut.renderStack.shortLabel } ?? false
        VStack(alignment: .leading, spacing: 5) {
            if let provenance {
                Text(provenance.label)
                    .font(CanonType.archive(7, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(chipInk)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(chipFill(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(chipStroke, lineWidth: 1))
                    .help("Rendered with — version \(FrameCreatorModal.romanNumeral(provenance.number)). The picker below only sets the NEXT render.")
            }
            if !isPlate {
                Menu {
                    ShotRenderStackMenuContent(cut: cut, actions: actions)
                } label: {
                    HStack(spacing: 4) {
                        Text(nextDiffers ? "NEXT · \(cut.renderStack.shortLabel)" : cut.renderStack.shortLabel)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6, weight: .bold))
                    }
                        .font(CanonType.archive(7, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(chipInk)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(RoundedRectangle(cornerRadius: 4).fill(chipFill(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(chipStroke, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .disabled(isRenderingThis)
                .help("\(cut.renderStack.accurateHelp) Sets the NEXT render's default model and length — existing renders keep their own provenance; segment overrides remain independent.")
            }

            let hasPlayable = !cut.browsableRenderVersions.isEmpty
            if isRenderingThis {
                HStack(spacing: 6) {
                    if hasPlayable {
                        railActionButton(icon: "play.fill", label: "PLAY", tint: CanonColor.brass) {
                            actions.onOpenShotVideo(cut.shotId)
                        }
                        .help("Play the last finished render while this one cooks — playback flips to the new version when it completes")
                    }
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                        Text(artifact?.progressText.trimmed.nilIfEmpty ?? "RENDERING")
                            .font(CanonType.archive(7, weight: .semibold))
                            .kerning(0.5)
                            .foregroundStyle(CanonColor.brass)
                            .lineLimit(2)
                    }
                }
            } else if hasPlayable {
                HStack(spacing: 6) {
                    railActionButton(icon: "play.fill", label: "PLAY", tint: CanonColor.brass) {
                        actions.onOpenShotVideo(cut.shotId)
                    }
                    .help("Play this Shot's rendered video")
                    railActionButton(icon: "arrow.clockwise", label: nil, tint: quietTint) {
                        actions.onRequestRerender(cut.shotId)
                    }
                    .disabled(anotherIsRendering)
                    .help(anotherIsRendering ? "Another Shot is rendering" : "Review the segment prompts and re-render with \(cut.renderStack.shortLabel)")
                    if isSuffixAppendable, suffix.hasNewMaterial {
                        railActionButton(
                            icon: "sparkles",
                            label: "RENDER NEW",
                            tint: CanonColor.brass,
                            isEngaged: expandedRenderPlan
                        ) {
                            toggleRenderPlan()
                        }
                        .disabled(anotherIsRendering)
                        .help(anotherIsRendering
                            ? "Another Shot is rendering"
                            : "Appended material isn't rendered yet — review the plan and render only the new segments; existing ones are reused. A new version is created (Looks flip to OLDER EDIT).")
                    }
                    if artifact?.status == "failed" {
                        railActionButton(
                            icon: isResumable ? "arrow.uturn.forward" : "exclamationmark.triangle",
                            label: isResumable ? "RESUME" : "RETRY",
                            tint: isResumable ? CanonColor.brass : CanonColor.rust,
                            isEngaged: expandedRenderPlan
                        ) {
                            toggleRenderPlan()
                        }
                        .disabled(anotherIsRendering)
                        .help(expandedRenderPlan
                            ? "Close the render plan"
                            : (isResumable
                                ? resumeHelp
                                : (artifact?.errorMessage.trimmed.nilIfEmpty ?? "The newest render failed — review the plan and retry; the last finished version still plays")))
                    }
                }
            } else if artifact?.status == "failed" {
                railActionButton(
                    icon: isResumable ? "arrow.uturn.forward" : "exclamationmark.triangle",
                    label: isResumable ? "RESUME" : "RETRY",
                    tint: isResumable ? CanonColor.brass : CanonColor.rust,
                    isEngaged: expandedRenderPlan
                ) {
                    toggleRenderPlan()
                }
                .disabled(anotherIsRendering)
                .help(expandedRenderPlan
                    ? "Close the render plan"
                    : (isResumable
                        ? resumeHelp
                        : (artifact?.errorMessage.trimmed.nilIfEmpty ?? "The render failed — review the plan and retry")))
            } else {
                railActionButton(
                    icon: "play.fill",
                    label: renderCTA.railLabel,
                    tint: CanonColor.brass,
                    isEngaged: expandedRenderPlan
                ) {
                    if canFinalizeLocally {
                        actions.onFinalizeAndOpen(cut.shotId)
                    } else {
                        toggleRenderPlan()
                    }
                }
                .disabled(cut.entries.isEmpty || anotherIsRendering)
                .help(
                    cut.entries.isEmpty
                        ? "Add Frames to render this Shot"
                        : (anotherIsRendering
                            ? "Another Shot is rendering"
                            : (canFinalizeLocally
                                ? "All source video is reusable — assembles locally for $0 (no AI) and opens the editor"
                                : (expandedRenderPlan
                                    ? "Close the render plan"
                                    : (isSeedDraft
                                        ? "Review the missing segments and future render cost; reusable seed clips stay unchanged and never re-bill"
                                        : "Review segments, prompts, and cost — then render"))))
                )
            }
        }
        .padding(.top, 4)
    }

    /// The two-step gesture: RENDER/RETRY toggle the plan strip open (closing
    /// the narration strip — one disclosure at a time) instead of spending.
    private func toggleRenderPlan() {
        withAnimation(.easeOut(duration: 0.15)) {
            expandedRenderPlan.toggle()
            if expandedRenderPlan {
                expandedNarration = false
                actions.onRenderPlanOpened()
            }
        }
        if layout == .box {
            renderPlanOpenPreference = expandedRenderPlan
        }
        narrationPlayer.stop()
    }

    // MARK: Box render bar (SCENES v2)

    /// What the `.box` header and render bar share: the segment plan and its
    /// suffix, computed once per body.
    private struct BoxPlanContext {
        var segments: [ShotRenderPlanSegment]
        var generatedItems: [ShotSegmentPromptPlanItem]
        var suffix: ShotSuffixRenderPlan
        var generatedSeconds: Double
    }

    private func boxPlanContext() -> BoxPlanContext {
        let plan = shotRenderSegmentPlan(
            shot: cut,
            frameLookup: actions.frameLookup,
            mediaLookup: actions.mediaLookup,
            meaningNodes: actions.meaningNodes
        )
        let generatedSeconds = plan.generatedItems.reduce(0.0) { partial, item in
            partial + Double(item.renderStack.segmentSeconds)
        }
        let quiet = actions.activeShotRenderId != cut.shotId && cut.renderArtifact?.status != "generating"
        let suffix = (quiet && cut.activeRenderVersion != nil)
            ? shotSuffixRenderPlan(shot: cut, segments: plan.segments, generatedItems: plan.generatedItems)
            : ShotSuffixRenderPlan()
        return BoxPlanContext(
            segments: plan.segments,
            generatedItems: plan.generatedItems,
            suffix: suffix,
            generatedSeconds: generatedSeconds
        )
    }

    /// The render disclosure's face for this Shot's state — nil when there is
    /// nothing to plan (rendering now, or rendered with nothing new to add).
    private struct BoxRenderToggle {
        var title: String
        var tint: Color
        var estimateItems: [ShotSegmentPromptPlanItem]
        /// finalizeFree assembles locally instead of opening the plan.
        var actsImmediately = false
        var help: String
    }

    private func boxRenderToggle(_ context: BoxPlanContext) -> BoxRenderToggle? {
        let artifact = cut.renderArtifact
        let isRenderingThis = actions.activeShotRenderId == cut.shotId || artifact?.status == "generating"
        if isRenderingThis { return nil }
        let hasPlayable = !cut.browsableRenderVersions.isEmpty
        let suffix = context.suffix
        let isResumable = artifact?.status == "failed"
            && suffix.reusableSegmentCount > 0
            && suffix.hasNewMaterial
        if artifact?.status == "failed" {
            return BoxRenderToggle(
                title: isResumable ? "RESUME" : "RETRY",
                tint: isResumable ? CanonColor.brass : CanonColor.rust,
                estimateItems: isResumable ? suffix.missingGeneratedItems : context.generatedItems,
                help: isResumable
                    ? "\(suffix.reusableSegmentCount) of \(suffix.reusableSegmentCount + suffix.missingKeys.count) segments are already rendered — RESUME renders only the rest"
                    : (artifact?.errorMessage.trimmed.nilIfEmpty ?? "The render failed — review the plan and retry")
            )
        }
        if hasPlayable {
            guard isSuffixAppendable, suffix.hasNewMaterial else { return nil }
            return BoxRenderToggle(
                title: "RENDER NEW",
                tint: CanonColor.brass,
                estimateItems: suffix.missingGeneratedItems,
                help: "Appended material isn't rendered yet — review the plan and render only the new segments; existing ones are reused. A new version is created (Looks flip to OLDER EDIT)."
            )
        }
        let renderCTA = cutRenderCTA(cut: cut, segmentCount: context.segments.count)
        return BoxRenderToggle(
            title: renderCTA.railLabel,
            tint: CanonColor.brass,
            estimateItems: context.generatedItems,
            actsImmediately: renderCTA == .finalizeFree,
            help: renderCTA == .finalizeFree
                ? "All source video is reusable — assembles locally for $0 (no AI) and opens the editor"
                : (renderCTA.isSeedDraft
                    ? "Review the missing segments and future render cost; reusable seed clips stay unchanged and never re-bill"
                    : "Review segments, prompts, and cost — then render")
        )
    }

    /// Seeds the `.box` disclosure from the remembered preference whenever the
    /// staged Scene (or its emptiness) changes: open only when there is a plan
    /// to show. A focus request or the operator's own click still wins after.
    private func seedBoxRenderPlan() {
        guard layout == .box else { return }
        let toggle = boxRenderToggle(boxPlanContext())
        let shouldOpen = renderPlanOpenPreference
            && !cut.entries.isEmpty
            && toggle != nil
            && toggle?.actsImmediately == false
        guard shouldOpen != expandedRenderPlan else { return }
        expandedRenderPlan = shouldOpen
        if shouldOpen {
            expandedNarration = false
            narrationPlayer.stop()
        }
    }

    /// Under the frames: provenance and playback at the left, the render
    /// disclosure at the right — filled brass while closed (the page's one
    /// fill), an open chevron ghost while the plan below carries the confirm.
    private func boxRenderBar(_ context: BoxPlanContext) -> some View {
        let artifact = cut.renderArtifact
        let isRenderingThis = actions.activeShotRenderId == cut.shotId || artifact?.status == "generating"
        let anotherIsRendering = !actions.activeShotRenderId.isEmpty && actions.activeShotRenderId != cut.shotId
        let hasPlayable = !cut.browsableRenderVersions.isEmpty
        let provenance = cut.playableRenderVersion.map { version in
            (label: shotRenderProvenanceSummary(version: version), number: version.versionNumber)
        }
        let toggle = boxRenderToggle(context)
        let planIsOpen = expandedRenderPlan && !isRenderingThis
        return HStack(alignment: .center, spacing: 8) {
            if let provenance {
                Text(provenance.label)
                    .font(CanonType.archive(7, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(chipInk)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(chipFill(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(chipStroke, lineWidth: 1))
                    .help("Rendered with — version \(FrameCreatorModal.romanNumeral(provenance.number)).")
            }
            if hasPlayable {
                railActionButton(icon: "play.fill", label: "PLAY", tint: CanonColor.brass) {
                    actions.onOpenShotVideo(cut.shotId)
                }
                .help(isRenderingThis
                    ? "Play the last finished render while this one cooks — playback flips to the new version when it completes"
                    : "Play this Shot's rendered video")
                if !isRenderingThis {
                    railActionButton(icon: "arrow.clockwise", label: nil, tint: quietTint) {
                        actions.onRequestRerender(cut.shotId)
                    }
                    .disabled(anotherIsRendering)
                    .help(anotherIsRendering ? "Another Shot is rendering" : "Review the segment prompts and re-render with \(cut.renderStack.shortLabel)")
                }
            }
            if isRenderingThis {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(artifact?.progressText.trimmed.nilIfEmpty ?? "RENDERING")
                        .font(CanonType.archive(7.5, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.brass)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if let toggle {
                let estimate = ShotRenderCostEstimate.estimate(
                    items: toggle.estimateItems,
                    pricing: actions.falPricing,
                    isFetchingRates: actions.isFetchingVideoPricing
                )
                let title = (!toggle.actsImmediately && estimate.headlineLabel != nil)
                    ? "\(toggle.title) · \(estimate.headlineLabel ?? "")"
                    : toggle.title
                let disabledReason = cut.entries.isEmpty
                    ? "Add Frames to render this Shot"
                    : (anotherIsRendering ? "Another Shot is rendering" : "")
                boxRenderTogglePill(
                    title: title,
                    tint: toggle.tint,
                    isOpen: planIsOpen && !toggle.actsImmediately,
                    disabledReason: disabledReason,
                    help: planIsOpen && !toggle.actsImmediately ? "Close the render plan" : toggle.help
                ) {
                    if toggle.actsImmediately {
                        actions.onFinalizeAndOpen(cut.shotId)
                    } else {
                        toggleRenderPlan()
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func boxRenderTogglePill(
        title: String,
        tint: Color,
        isOpen: Bool,
        disabledReason: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        let enabled = disabledReason.isEmpty
        // Rust (RETRY) never fills: a failure asks for review, not a splash.
        let filled = !isOpen && tint == CanonColor.brass
        return Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                Text(title)
                    .font(CanonType.archive(10, weight: .bold))
                    .kerning(1.4)
            }
            .foregroundStyle(enabled ? (filled ? CanonColor.ink : tint) : tint.opacity(0.5))
            .padding(.horizontal, 18)
            .frame(height: 32)
            .background(
                Capsule().fill(
                    enabled
                        ? (filled ? tint : tint.opacity(isOpen ? 0.16 : 0.06))
                        : tint.opacity(0.06)
                )
            )
            .overlay(
                Capsule().stroke(
                    enabled ? (filled ? Color.clear : tint.opacity(isOpen ? 0.7 : 0.45)) : tint.opacity(0.25),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(enabled ? help : disabledReason)
    }

    private func railActionButton(
        icon: String,
        label: String?,
        tint: Color,
        isEngaged: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                if let label {
                    Text(label)
                        .font(CanonType.archive(7.5, weight: .bold))
                        .kerning(0.6)
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill(tint.opacity(isEngaged ? 0.18 : 0.10)))
            .overlay(Capsule().stroke(tint.opacity(isEngaged ? 0.7 : 0.45), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// NEW VERSION — the sanctioned way to iterate on a rendered cut: an
    /// editable, unrendered twin seated right after this one.
    private var duplicateButton: some View {
        Button {
            actions.onDuplicate(cut.shotId)
        } label: {
            Image(systemName: "plus.square.on.square")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHoveringStrip ? CanonColor.brass : CanonColor.muted.opacity(0.7))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New version — duplicate this Shot for editing; renders stay on the original")
    }

    /// True while THIS cut's render is actually in flight (not merely ready)
    /// — trashing then would hide the running work behind the held render
    /// lock. The engine refuses too; this keeps the control honest.
    private var isActivelyRendering: Bool {
        actions.activeShotRenderId == cut.shotId
            || cut.renderArtifact?.status == "generating"
    }

    /// Armed two-click delete: the first click arms (rust), the second within
    /// ~2.5s moves the Shot to DELETED SHOTS. Soft-delete — always restorable.
    private var trashButton: some View {
        Button {
            if isTrashArmed {
                isTrashArmed = false
                actions.onTrash(cut.shotId)
            } else {
                isTrashArmed = true
                trashArmGeneration += 1
                let generation = trashArmGeneration
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    if trashArmGeneration == generation {
                        isTrashArmed = false
                    }
                }
            }
        } label: {
            Image(systemName: isTrashArmed ? "trash.fill" : "trash")
                .font(.system(size: 13, weight: isTrashArmed ? .semibold : .regular))
                .foregroundStyle(isTrashArmed ? CanonColor.rust : (isHoveringStrip ? CanonColor.rust.opacity(0.75) : CanonColor.muted.opacity(0.7)))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(isTrashArmed ? CanonColor.rust.opacity(0.14) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isActivelyRendering)
        .help(isActivelyRendering
            ? "This Shot is rendering — wait for it to finish (or cancel it) before trashing"
            : (isTrashArmed
                ? "Click again to move this Shot to DELETED SHOTS"
                : "Delete this Shot — click twice; it moves to DELETED SHOTS (restorable, renders kept)"))
    }

    // MARK: Entry cells

    private func entryCell(_ entry: ShotFrameEntry) -> some View {
        let frame = entry.isClip ? nil : actions.frameLookup[entry.frameImageId]
        let media = entry.isClip ? actions.mediaLookup[entry.clipMediaId] : nil
        let isCellTargeted = targetedCellEntryId == entry.entryId
        return ZStack(alignment: .topTrailing) {
            Group {
                if entry.isAIExtension {
                    extensionThumbnail(isLeadIn: isLeadInPosition(entry))
                } else if entry.isClip {
                    clipThumbnail(media: media)
                } else {
                    cellThumbnail(frame: frame)
                }
            }
            .frame(width: Self.cellSize.width, height: Self.cellSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            if entry.isClip, let media {
                cellCaption(clipCaption(entry: entry, media: media))
            } else if !entry.isAIExtension, let frame, !frame.label.trimmed.isEmpty {
                cellCaption(frame.label)
            }
            if hoveredEntryId == entry.entryId, !isLocked || isTailEntry(entry.entryId) {
                Button {
                    actions.onRemoveEntry(cut.shotId, entry.entryId)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(CanonColor.bone)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .padding(5)
                .help(isLocked ? "Remove this unrendered append" : "Remove from this Shot")
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    CanonColor.hairlinePaper.opacity(0.8),
                    style: StrokeStyle(
                        lineWidth: 1,
                        dash: entry.isAIExtension || (layout == .box && isPlannedEntry(entry)) ? [5, 4] : []
                    )
                )
        )
        .overlay(alignment: .leading) {
            // A drop on a cell INSERTS BEFORE it, so the affordance is the
            // gap's brass insertion bar at the leading edge — a whole-cell
            // ring here would read as "replace", which was retired.
            if isCellTargeted {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(CanonColor.brass)
                    .frame(width: 3, height: Self.cellSize.height - 16)
                    .padding(.leading, 2)
            }
        }
        .onHover { hovering in
            if hovering {
                hoveredEntryId = entry.entryId
            } else if hoveredEntryId == entry.entryId {
                hoveredEntryId = ""
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.isClip {
                actions.onOpenClip(cut.shotId, entry.entryId)
            } else if let frame, frame.status == "ready" {
                actions.onOpenFrame(cut.shotId, entry.entryId, frame)
            } else if layout == .box, let frame, frame.isPlanFulfillmentCandidate {
                actions.onArtDirectPlannedFrame(frame)
            }
        }
        .contextMenu {
            if !entry.isClip, !entry.isAIExtension, let frame, frame.status == "ready" {
                Button("Enter Excursion") {
                    actions.onEnterExcursion(cut.shotId, entry.entryId, frame)
                }
            }
        }
        .help(entry.isAIExtension
            ? (isLeadInPosition(entry)
                ? "AI lead-in — a generated segment arriving on this Shot's first material; edit its prompt in Re-render"
                : "AI extension — an open-ended generated segment continuing the previous material; edit its prompt in Re-render")
            : (entry.isClip
                ? "Open the Clip Inspector — watch, trim to fit, see handoff frames"
                : (layout == .box && isPlannedEntry(entry)
                    ? "A planned Frame — click to art-direct and render it in place"
                    : "")))
        .draggable(ShotFrameTransfer(
            frameImageId: entry.frameImageId,
            sourceShotId: cut.shotId,
            sourceEntryId: entry.entryId,
            clipMediaId: entry.clipMediaId
        ))
        .dropDestination(for: ShotFrameTransfer.self) { items, _ in
            // A drop ON a cell INSERTS BEFORE it — the gap law at this
            // entry's index. Replacement is retired: a drop never destroys
            // the target frame. The engine re-guards frozen cuts, so a
            // stale view never sneaks a non-tail edit in.
            guard let transfer = items.first,
                  let index = cut.entries.firstIndex(where: { $0.entryId == entry.entryId }) else {
                return false
            }
            guard !isLocked || isTailIndex(index) else { return false }
            guard transfer.sourceEntryId != entry.entryId else { return false }
            if transfer.sourceShotId == cut.shotId, !transfer.sourceEntryId.isEmpty {
                actions.onMoveEntry(cut.shotId, transfer.sourceEntryId, index)
            } else if transfer.isClipDrag {
                actions.onInsertClip(cut.shotId, transfer.clipMediaId, index)
            } else {
                guard !transfer.frameImageId.trimmed.isEmpty else { return false }
                actions.onInsertFrame(cut.shotId, transfer, index)
            }
            return true
        } isTargeted: { targeted in
            let index = cut.entries.firstIndex { $0.entryId == entry.entryId }
            let accepts = !isLocked || index.map(isTailIndex) == true
            targetedCellEntryId = (targeted && accepts) ? entry.entryId : (targetedCellEntryId == entry.entryId ? "" : targetedCellEntryId)
        }
    }

    private func cellCaption(_ text: String) -> some View {
        VStack {
            Spacer()
            HStack {
                Text(text)
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .kerning(0.4)
                    .foregroundStyle(CanonColor.bone)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                Spacer()
            }
            .padding(6)
        }
        .frame(width: Self.cellSize.width, height: Self.cellSize.height)
    }

    private func clipCaption(entry: ShotFrameEntry, media: MediaItemRecord) -> String {
        let assetDuration = media.durationSeconds ?? 0
        let start = entry.clipStartSeconds ?? 0
        let end = entry.clipEndSeconds ?? assetDuration
        let duration = max(end - start, 0)
        guard duration > 0 else { return "FOOTAGE" }
        if entry.clipStartSeconds != nil || entry.clipEndSeconds != nil {
            return "FOOTAGE · \(videoTrimTimestampLabel(start))–\(videoTrimTimestampLabel(end))"
        }
        return "FOOTAGE · \(videoTrimTimestampLabel(duration))"
    }

    @ViewBuilder
    private func cellThumbnail(frame: ProjectLensHeroImage?) -> some View {
        ZStack {
            CanonColor.mediaCardHover
            if let frame, frame.status == "ready", !frame.imagePath.trimmed.isEmpty,
               let image = StripThumbnailCache.shared.image(path: frame.imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if layout == .box, let frame, frame.isPlanFulfillmentCandidate {
                // A plan is not a queue: no spinner for work that isn't
                // running. Candidates can carry status "queued", so this
                // branch must come before the in-flight one. `.box` only —
                // v1's cells render byte-identically.
                VStack(spacing: 5) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CanonColor.brass.opacity(0.85))
                    Text("PLANNED")
                        .font(CanonType.archive(7.5, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.muted)
                    Text("Click to art-direct this Frame")
                        .font(CanonType.archive(7, weight: .medium))
                        .foregroundStyle(CanonColor.muted.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                }
            } else if let frame, frame.status == "generating" || frame.status == "queued" {
                VStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.small)
                    Text(frame.status == "generating" ? "RENDERING" : "QUEUED")
                        .font(CanonType.archive(7, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.muted)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: frame == nil ? "questionmark.square.dashed" : "photo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CanonColor.muted.opacity(0.75))
                    Text(frame == nil ? "MISSING FRAME" : "NOT READY")
                        .font(CanonType.archive(7, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.muted)
                }
            }
        }
        .clipped()
    }

    /// A legacy strip entry whose frame is still an unfulfilled plan (placed
    /// before planned frames left the v2 pool). `.box` renders it as an
    /// honest dashed PLANNED cell that clicks through to the Frame Creator.
    private func isPlannedEntry(_ entry: ShotFrameEntry) -> Bool {
        guard !entry.isClip, !entry.isAIExtension else { return false }
        return actions.frameLookup[entry.frameImageId]?.isPlanFulfillmentCandidate == true
    }

    /// An extension entry's meaning is positional: at the strip's front it is
    /// a LEAD-IN (end-anchored, arrives on the next material); elsewhere it
    /// continues the previous material. Dragging it flips the caption.
    private func isLeadInPosition(_ entry: ShotFrameEntry) -> Bool {
        guard entry.isAIExtension,
              let index = cut.entries.firstIndex(where: { $0.entryId == entry.entryId }) else {
            return false
        }
        return !cut.entries.prefix(index).contains { !$0.isSkipped }
    }

    private func extensionThumbnail(isLeadIn: Bool) -> some View {
        ZStack {
            CanonColor.paperInset.opacity(0.4)
            VStack(spacing: 5) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CanonColor.brass.opacity(0.85))
                Text(isLeadIn ? "AI LEAD-IN" : "AI EXTENSION")
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(CanonColor.muted)
                Text(isLeadIn
                    ? "~\(cut.renderStack.segmentSeconds)s · arrives on the next material"
                    : "~\(cut.renderStack.segmentSeconds)s · continues the previous material")
                    .font(CanonType.archive(7, weight: .medium))
                    .foregroundStyle(CanonColor.muted.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
        }
        .clipped()
    }

    @ViewBuilder
    private func clipThumbnail(media: MediaItemRecord?) -> some View {
        ZStack {
            CanonColor.mediaCardHover
            if let media,
               let image = (media.videoStripPath.flatMap { StripThumbnailCache.shared.image(path: $0) })
                ?? StripThumbnailCache.shared.image(path: media.thumbnailPath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CanonColor.muted.opacity(0.75))
                    Text("MISSING FOOTAGE")
                        .font(CanonType.archive(7, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.muted)
                }
            }
            VStack {
                HStack {
                    Image(systemName: "film")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                        .padding(5)
                    Spacer()
                }
                Spacer()
            }
        }
        .clipped()
    }

    // MARK: Gaps + seams

    private func gapStrip(index: Int) -> some View {
        let isTargeted = targetedGapIndex == index
        return ZStack {
            Color.clear
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isTargeted ? CanonColor.brass : Color.clear)
                .frame(width: 3, height: Self.cellSize.height - 16)
            if !isTargeted, let seam = seamContext(gapIndex: index) {
                seamToggle(seam)
            }
            if index == 0, !isTargeted, !isLocked, !cut.entries.isEmpty,
               !(cut.entries.first?.isAIExtension ?? false) {
                leadInButton
            }
        }
        .frame(width: Self.gapWidth, height: Self.cellSize.height)
        .contentShape(Rectangle())
        .dropDestination(for: ShotFrameTransfer.self) { items, _ in
            // Tail gaps stay live on a locked-but-appendable cut; the engine
            // re-guards, so a stale view never sneaks a non-tail edit in.
            guard !isLocked || isTailIndex(index), let transfer = items.first else { return false }
            if transfer.sourceShotId == cut.shotId, !transfer.sourceEntryId.isEmpty {
                actions.onMoveEntry(cut.shotId, transfer.sourceEntryId, index)
            } else if transfer.isClipDrag {
                actions.onInsertClip(cut.shotId, transfer.clipMediaId, index)
            } else {
                actions.onInsertFrame(cut.shotId, transfer, index)
            }
            return true
        } isTargeted: { targeted in
            let accepts = !isLocked || isTailIndex(index)
            targetedGapIndex = (targeted && accepts) ? index : (targetedGapIndex == index ? nil : targetedGapIndex)
        }
    }

    private struct SeamContext {
        var rightEntryId: String
        var style: ShotSeamStyle
    }

    private func seamContext(gapIndex: Int) -> SeamContext? {
        guard gapIndex > 0, gapIndex < cut.entries.count else { return nil }
        let left = cut.entries[gapIndex - 1]
        let right = cut.entries[gapIndex]
        guard !left.isAIExtension, !right.isAIExtension else { return nil }
        guard shotSeamIsToggleable(leftIsClip: left.isClip, rightIsClip: right.isClip) else { return nil }
        return SeamContext(
            rightEntryId: right.entryId,
            style: resolvedShotSeamStyle(
                leftIsClip: left.isClip,
                rightIsClip: right.isClip,
                rightPreference: right.leadSeamPreference
            )
        )
    }

    private func seamToggle(_ seam: SeamContext) -> some View {
        let editable = !isLocked || isTailEntry(seam.rightEntryId)
        return Button {
            guard editable else { return }
            actions.onSetSeamStyle(cut.shotId, seam.rightEntryId, seam.style.toggled)
        } label: {
            Text(seam.style == .cut ? "‖" : "≈")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(seam.style == .cut ? CanonColor.ink.opacity(0.55) : CanonColor.brass)
                .frame(width: Self.gapWidth, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(CanonColor.hairlinePaper.opacity(0.9), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(!editable
            ? "Rendered — seams are part of this Shot's video; create a NEW VERSION to change them"
            : (isLocked
                ? "This seam joins new material — bridge costs one generated pair; hard cut is free"
                : (seam.style == .cut
                    ? "Hard cut — click to bridge (generated transition)"
                    : "Generated bridge — click to hard-cut")))
    }

    /// The gap-0 mirror of "Extend with AI": prepend an AI lead-in — an
    /// end-anchored generated segment arriving on the cut's first material.
    /// Honestly disabled while no selectable model accepts a tail frame alone.
    private var leadInButton: some View {
        Button {
            actions.onLeadIn(cut.shotId)
        } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ShotRenderModel.anyLeadInCapable ? CanonColor.brass : CanonColor.muted.opacity(0.5))
                .frame(width: Self.gapWidth, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(0.72))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(CanonColor.hairlinePaper.opacity(0.9), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ShotRenderModel.anyLeadInCapable)
        .help(ShotRenderModel.anyLeadInCapable
            ? "Lead in with AI (~\(cut.renderStack.segmentSeconds)s) — a generated segment that arrives on this Shot's first material"
            : "Lead in with AI — no wired model accepts a tail frame alone yet")
    }

    // MARK: Append zone — drop target AND button (the once-unwired "+")

    /// Locked cuts trade the "+" slot for a quiet provenance pill.
    @ViewBuilder
    private var appendZone: some View {
        if isLocked, !isSuffixAppendable {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(slotStroke(0.6), lineWidth: 1)
                .background(RoundedRectangle(cornerRadius: 9).fill(slotFill(0.16)))
                .overlay(
                    VStack(spacing: 5) {
                        Image(systemName: "lock")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(quiet(0.55))
                        Text("RENDERED")
                            .font(CanonType.archive(7.5, weight: .semibold))
                            .kerning(1)
                            .foregroundStyle(quiet(0.8))
                        Text("NEW VERSION to edit")
                            .font(CanonType.archive(7, weight: .medium))
                            .foregroundStyle(quiet(0.6))
                    }
                )
                .frame(width: Self.cellSize.width, height: Self.cellSize.height)
                .help("This Shot is rendered, so its strip stays faithful to the video. Use the NEW VERSION button to duplicate and edit.")
        } else if isSuffixAppendable {
            // Locked-but-appendable: the rendered prefix stays true to the
            // video; new material may join at the end and render separately.
            VStack(spacing: 4) {
                appendButton
                Text("RENDERED · APPENDS ONLY")
                    .font(CanonType.archive(6.5, weight: .semibold))
                    .kerning(0.7)
                    .foregroundStyle(quiet(0.75))
            }
            .help("This Shot is rendered — earlier material is locked, but Frames and Footage can be appended after the rendered tail and rendered on their own.")
        } else {
            appendButton
        }
    }

    private var appendButton: some View {
        Button {
            isAppendPickerOpen = true
        } label: {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    isAppendTargeted ? CanonColor.brass : slotStroke(0.8),
                    style: StrokeStyle(lineWidth: isAppendTargeted ? 2 : 1, dash: [5, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isAppendTargeted ? CanonColor.softGold.opacity(0.16) : slotFill(0.28))
                )
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(quiet(0.7))
                )
                .frame(width: Self.cellSize.width, height: Self.cellSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add Source Material to this Shot, or render a new Frame")
        .popover(isPresented: $isAppendPickerOpen, arrowEdge: .bottom) {
            appendPicker
        }
        .dropDestination(for: ShotFrameTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            if transfer.sourceShotId == cut.shotId, !transfer.sourceEntryId.isEmpty {
                actions.onMoveEntry(cut.shotId, transfer.sourceEntryId, cut.entries.count)
            } else if transfer.isClipDrag {
                actions.onInsertClip(cut.shotId, transfer.clipMediaId, cut.entries.count)
            } else {
                actions.onInsertFrame(cut.shotId, transfer, cut.entries.count)
            }
            return true
        } isTargeted: { targeted in
            isAppendTargeted = targeted
        }
    }

    /// The append picker: the complete Source Material inventory, searchable,
    /// with unused items first and a direct New Frame path.
    private var appendPicker: some View {
        let query = appendSearchQuery.trimmed.lowercased()
        let candidates = poolInputs.filter { input in
            guard !query.isEmpty else { return true }
            if input.isClip {
                return actions.mediaLookup[input.clipMediaId]?.filename.lowercased().contains(query) == true
            }
            guard let frame = actions.frameLookup[input.frameImageId] else { return false }
            return frame.label.lowercased().contains(query)
                || frame.prompt.lowercased().contains(query)
        }
        let placedFrameIds = Set(cut.entries.map(\.frameImageId).filter { !$0.isEmpty })
        let placedClipIds = Set(cut.entries.map(\.clipMediaId).filter { !$0.isEmpty })
        let unplaced = candidates.filter { input in
            input.isClip ? !placedClipIds.contains(input.clipMediaId) : !placedFrameIds.contains(input.frameImageId)
        }
        let placed = candidates.filter { input in
            input.isClip ? placedClipIds.contains(input.clipMediaId) : placedFrameIds.contains(input.frameImageId)
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("SOURCE MATERIAL")
                .font(CanonType.archive(8, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(CanonColor.muted)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
                TextField("Search Frames and Footage", text: $appendSearchQuery)
                    .textFieldStyle(.plain)
                    .font(CanonType.interface(11))
            }
            .padding(.horizontal, 8)
            .frame(width: 548, height: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlinePaper.opacity(0.8)))
            if candidates.isEmpty {
                Text(poolInputs.isEmpty
                    ? "No source material yet — render a new Frame below."
                    : "No Frames or Footage match this search.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
                    .frame(width: 300, alignment: .leading)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 102, maximum: 102), spacing: 8)], spacing: 10) {
                        ForEach(unplaced + placed) { input in
                            appendPickerThumb(input, alreadyPlaced: placed.contains(input))
                        }
                    }
                }
                .frame(width: 548, height: min(CGFloat((candidates.count + 4) / 5) * 84 + 8, 344))
            }
            Divider()
            Button {
                isAppendPickerOpen = false
                actions.onCreateFrameForCut(cut.shotId)
            } label: {
                Label("New Frame for this Shot…", systemImage: "plus.square.on.square")
                    .font(CanonType.interface(11.5, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(CanonColor.brass)
            .help("Open the Frame Creator — the rendered Frame lands at the end of this Shot")
        }
        .padding(14)
        .background(CanonColor.paper)
    }

    private func appendPickerThumb(_ input: StageInput, alreadyPlaced: Bool) -> some View {
        let frame = input.isClip ? nil : actions.frameLookup[input.frameImageId]
        let media = input.isClip ? actions.mediaLookup[input.clipMediaId] : nil
        return Button {
            isAppendPickerOpen = false
            actions.onAppendPoolInput(cut.shotId, input)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if input.isClip {
                            sourceMediaThumbnail(media: media)
                        } else {
                            cellThumbnail(frame: frame)
                        }
                    }
                    .frame(width: 102, height: 57)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    if alreadyPlaced {
                        Text("IN SHOT")
                            .font(CanonType.archive(6.5, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(CanonColor.bone)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(3)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(CanonColor.hairlinePaper.opacity(0.9), lineWidth: 1)
                )
                Text(sourceMaterialTitle(frame: frame, media: media))
                    .font(CanonType.interface(8.5, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.72))
                    .lineLimit(1)
                    .frame(width: 102, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(input.isClip && frameIsUnready(frame, isClip: true) ? 1 : (frameIsUnready(frame, isClip: input.isClip) ? 0.55 : 1))
        .disabled(frameIsUnready(frame, isClip: input.isClip))
        .help(alreadyPlaced ? "Already in this Shot — click to place it again" : "Append to this Shot")
    }

    @ViewBuilder
    private func sourceMediaThumbnail(media: MediaItemRecord?) -> some View {
        if media?.kind == .image {
            ZStack(alignment: .topLeading) {
                CanonColor.mediaCardHover
                if let media,
                   let image = StripThumbnailCache.shared.image(path: media.path)
                    ?? StripThumbnailCache.shared.image(path: media.thumbnailPath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CanonColor.muted.opacity(0.72))
                }
                // SCENES v2 counts every photo as a Frame; the v1 picker keeps its word.
                Text(layout == .box ? "FRAME" : "PHOTO")
                    .font(CanonType.archive(6.5, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(CanonColor.bone)
                    .padding(.horizontal, 5)
                    .frame(height: 17)
                    .background(Capsule().fill(Color.black.opacity(0.52)))
                    .padding(4)
            }
            .clipped()
        } else {
            clipThumbnail(media: media)
        }
    }

    private func sourceMaterialTitle(
        frame: ProjectLensHeroImage?,
        media: MediaItemRecord?
    ) -> String {
        if let media {
            return media.filename.trimmed.nilIfEmpty ?? "Untitled media"
        }
        return frame?.label.trimmed.nilIfEmpty ?? "Untitled Frame"
    }

    private func frameIsUnready(_ frame: ProjectLensHeroImage?, isClip: Bool) -> Bool {
        guard !isClip else { return false }
        return frame?.status != "ready"
    }
}

/// Inline rename field for a cut's rail — commit on submit or focus loss.
/// (Carried over from the retired shots band's ShotRailNameField.)
struct CutRailNameField: View {
    let cutId: String
    let name: String
    let onRename: (String, String) -> Void
    var font: Font = CanonType.editorial(12.5, weight: .semibold)
    var tint: Color = CanonColor.ink

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Name this Shot", text: $draft)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(tint)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commit()
                }
            }
            .onAppear { draft = name }
            .onChange(of: name) { _, newValue in
                if !isFocused {
                    draft = newValue
                }
            }
    }

    private func commit() {
        guard draft.trimmed != name.trimmed else { return }
        onRename(cutId, draft)
    }
}

/// The NEXT-render stack picker's items — every shot-default model with its
/// duration submenu, Hailuo resolution, and the native-audio switch — shared
/// by the row's chip and the SCENES v2 render plan header so the two can
/// never disagree about what a Shot may render with.
struct ShotRenderStackMenuContent: View {
    let cut: ProjectShot
    var actions: CutStripActions

    var body: some View {
        ForEach(ShotRenderModel.shotDefaultCases) { model in
            if model == .falLTX23Narration {
                let stack = cut.renderStack.replacingModel(model)
                Button {
                    actions.onSetRenderStack(cut.shotId, stack)
                } label: {
                    if stack == cut.renderStack {
                        Label(model.label, systemImage: "checkmark")
                    } else {
                        Text(
                            actions.configuredRenderModels.contains(model)
                                ? model.label
                                : "\(model.label) · needs API key"
                        )
                    }
                }
                .disabled(!actions.configuredRenderModels.contains(model))
            } else {
                Menu {
                    ForEach(model.supportedDurations, id: \.self) { seconds in
                        let stack = cut.renderStack
                            .replacingModel(model)
                            .replacingDuration(seconds)
                        Button {
                            actions.onSetRenderStack(cut.shotId, stack)
                        } label: {
                            if stack == cut.renderStack {
                                Label("\(seconds)s", systemImage: "checkmark")
                            } else {
                                Text("\(seconds)s")
                            }
                        }
                    }
                    Hailuo3ResolutionMenuSection(model: model)
                } label: {
                    Text(actions.configuredRenderModels.contains(model) ? model.label : "\(model.label) · needs API key")
                }
                .disabled(!actions.configuredRenderModels.contains(model))
            }
        }
        if cut.renderStack.model.supportsGeneratedAudio {
            Divider()
            Toggle(
                "Native audio",
                isOn: Binding(
                    get: { cut.renderStack.generateAudio },
                    set: {
                        actions.onSetRenderStack(
                            cut.shotId,
                            cut.renderStack.replacingGeneratedAudio($0)
                        )
                    }
                )
            )
        }
    }
}

/// Menu chips draw their own label. The system's borderless menu style now
/// discards that label for a native pull-down, so the plate dress uses the
/// button style with a plain button; the row keeps its original style.
struct CutStripMenuChipStyle: ViewModifier {
    var isPlate: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isPlate {
            content.menuStyle(.button).buttonStyle(.plain)
        } else {
            content.menuStyle(.borderlessButton)
        }
    }
}
