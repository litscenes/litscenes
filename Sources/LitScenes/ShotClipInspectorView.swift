import AppKit
import SwiftUI

/// Identifies which shot entry's footage is open in the Clip Inspector.
struct ShotClipInspectorRequest: Identifiable, Hashable {
    var shotId: String
    var entryId: String

    var id: String { "\(shotId)#\(entryId)" }
}

/// The placed clip's instrument: watch it, cut it to fit THIS shot (a
/// non-destructive range on the entry — the asset is never touched), and see
/// exactly where neighboring generated segments hand off. The trim edges ARE
/// the handoff anchors: the in/out stills update as the range moves, so a
/// blurry mid-motion boundary is visible before a render pays for it.
struct ShotClipInspectorView: View {
    @ObservedObject var library: LibraryEngine
    let shotId: String
    let entryId: String
    /// A deck card fired: the workbench swaps this sheet for the seeded
    /// Frame Creator.
    var onSpawnFrame: (ClipMomentSeed) -> Void = { _ in }
    /// The extension marker is prepared idempotently, then the workbench
    /// swaps this sheet for the Shot's existing paid render review.
    var onReviewExtension: (ShotExtensionPreparation) -> Void = { _ in }
    var onClose: () -> Void

    @State private var timestampSeconds: Double = 0
    @State private var localStartSeconds: Double = 0
    @State private var localEndSeconds: Double = 0
    @State private var hasSeeded = false
    @State private var isPlaying = false
    @State private var isLoopingPreview = false
    @State private var captureConfirmation = ""
    @State private var anchorInStill: URL?
    @State private var anchorOutStill: URL?
    @State private var placeIntoShot = true
    @State private var isCapturingSeed = false
    @State private var clipLookStyle: ShotLookStyleSelection?
    @State private var clipLookNotes = ""
    @State private var isClipLookStylePickerOpen = false
    /// Holds first responder on the sheet body so Space reaches the transport.
    /// Without it the CLIP LOOK notes field takes initial focus and swallows
    /// the key — and an unmodified `.keyboardShortcut` on the play button can't
    /// resolve at all.
    @FocusState private var transportFocused: Bool
    @AppStorage(ShotLookProvider.preferenceKey, store: LitScenesPreferences.store)
    private var clipLookProviderRaw = ShotLookProvider.fal.rawValue
    /// This sheet is its own window with its own UndoManager, so its picture
    /// edits (Apply Range, the seam toggles) register on their own
    /// coordinator — ⌘Z works where the gesture happened.
    @Environment(\.undoManager) private var undoManager
    @StateObject private var pictureUndo = ShotPictureUndoCoordinator()

    private func registerPictureEdit(_ edit: ShotPictureStateEdit?, _ actionName: String) {
        guard let edit else { return }
        pictureUndo.applyState = { shotId, snapshot in
            library.restoreShotPictureState(shotId: shotId, snapshot: snapshot)
        }
        pictureUndo.registerEdit(
            shotId: shotId,
            old: edit.before,
            new: edit.after,
            actionName: actionName,
            undoManager: undoManager
        )
    }

    private var clipLookProvider: ShotLookProvider {
        ShotLookProvider.resolved(clipLookProviderRaw)
    }

    private var clipLookProviderBinding: Binding<ShotLookProvider> {
        Binding(
            get: { clipLookProvider },
            set: { clipLookProviderRaw = $0.rawValue }
        )
    }

    private var shot: ProjectShot? {
        library.shotTimeline.shots.first { $0.shotId == shotId }
    }

    private var entry: ShotFrameEntry? {
        shot?.entries.first { $0.entryId == entryId }
    }

    private var media: MediaItemRecord? {
        guard let entry, entry.isClip else { return nil }
        return library.items.first { $0.mediaId == entry.clipMediaId }
    }

    private var isTransportActive: Bool {
        isPlaying || isLoopingPreview
    }

    private var assetDuration: Double {
        max(media?.durationSeconds ?? 0, 0)
    }

    private var clampedTimestamp: Double {
        min(max(timestampSeconds, 0), max(assetDuration - 0.01, 0))
    }

    var body: some View {
        if let shot, let entry, let media {
            inspector(shot: shot, entry: entry, media: media)
        } else {
            Color.clear
                .frame(width: 200, height: 120)
                .onAppear(perform: onClose)
        }
    }

    private func inspector(shot: ProjectShot, entry: ShotFrameEntry, media: MediaItemRecord) -> some View {
        let entryIndex = shot.entries.firstIndex { $0.entryId == entryId } ?? 0
        let range = VideoTrimRange.clamped(
            start: localStartSeconds,
            end: localEndSeconds,
            videoDurationSeconds: assetDuration
        )
        let committedStart = entry.clipStartSeconds ?? 0
        let committedEnd = entry.clipEndSeconds ?? assetDuration
        let isDirty = abs(range.startSeconds - committedStart) > 0.01 || abs(range.endSeconds - committedEnd) > 0.01
        let loopRange: ClosedRange<Double>? = range.durationSeconds > 0.05
            ? range.startSeconds...range.endSeconds
            : nil
        // Hand the players a range only while the loop preview is actually
        // running, matching the Video Studio: free play should never carry a
        // boundary observer parked at the out point.
        let activeLoopRange = isLoopingPreview ? loopRange : nil

        return VStack(spacing: 0) {
            header(media: media, range: range)
            Rectangle().fill(PlateColor.hairline).frame(height: 1)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    ZStack {
                        Color.black
                        if media.isPortrait {
                            BlurFillVideoBackdropView(
                                path: media.path,
                                timestampSeconds: clampedTimestamp,
                                loopRange: activeLoopRange,
                                isLoopPlaying: isLoopingPreview,
                                isFreePlaying: isPlaying
                            )
                        }
                        ScrubVideoPreview(
                            path: media.path,
                            timestampSeconds: $timestampSeconds,
                            loopRange: activeLoopRange,
                            isLoopPlaying: isLoopingPreview,
                            isFreePlaying: isPlaying,
                            onPlaybackTime: { seconds in
                                timestampSeconds = min(max(seconds, 0), max(assetDuration - 0.01, 0))
                            },
                            onPlaybackEnded: {
                                isPlaying = false
                            }
                        )
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(width: 660)
                    .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 1))

                    transportRow(loopRange: loopRange)

                    TrimRangeBar(
                        stripPath: media.videoStripPath,
                        durationSeconds: assetDuration,
                        startSeconds: $localStartSeconds,
                        endSeconds: $localEndSeconds,
                        playheadSeconds: clampedTimestamp,
                        onScrub: { seconds in
                            isPlaying = false
                            isLoopingPreview = false
                            timestampSeconds = min(max(seconds, 0), max(assetDuration - 0.01, 0))
                        }
                    )
                    .frame(width: 660, height: 48)

                    applyRow(range: range, isDirty: isDirty, assetDuration: assetDuration)

                    Rectangle().fill(PlateColor.hairline).frame(height: 1)

                    spawnDeck(
                        shot: shot,
                        entry: entry,
                        media: media,
                        range: range,
                        clampedTimestamp: clampedTimestamp
                    )

                    Rectangle().fill(PlateColor.hairline).frame(height: 1)

                    clipLookSection(shot: shot, entry: entry, media: media, isDirty: isDirty)
                }

                anchorColumn(
                    shot: shot,
                    entry: entry,
                    media: media,
                    entryIndex: entryIndex,
                    clampedTimestamp: clampedTimestamp
                )
                .frame(width: 250)
            }
            .padding(16)
        }
        .background(PlateColor.cream)
        .plateEngravedBorder(cornerRadius: 0, inset: 6)
        // Space is handled here, not as a button shortcut: an unmodified
        // `.keyboardShortcut` can't resolve while a text field owns focus, and
        // this sheet has one (CLIP LOOK notes). Keyed off the sheet body's own
        // focus, typing a space in that field still types a space.
        .focusable()
        .focusEffectDisabled()
        .focused($transportFocused)
        .onKeyPress(.space) {
            togglePlayback()
            return .handled
        }
        .background(
            Button("", action: onClose)
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
        )
        .sheet(isPresented: $isClipLookStylePickerOpen) {
            ShotLookStylePickerSheet(
                initialSelection: clipLookStyle,
                provider: clipLookProvider,
                onApply: { selection in
                    clipLookStyle = selection
                    isClipLookStylePickerOpen = false
                },
                onCancel: { isClipLookStylePickerOpen = false }
            )
        }
        .onAppear {
            // Claim first responder before the CLIP LOOK notes field can.
            transportFocused = true
            guard !hasSeeded else { return }
            hasSeeded = true
            localStartSeconds = committedStart
            localEndSeconds = committedEnd
            timestampSeconds = committedStart
        }
        .onDisappear {
            // A closed sheet leaves no stale actions on its window's stack.
            undoManager?.removeAllActions(withTarget: pictureUndo)
            pictureUndo.applyState = nil
        }
        .task(id: anchorTaskKey(range: range)) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let stills = await library.extractClipAnchorStills(
                mediaId: media.mediaId,
                startSeconds: range.startSeconds,
                endSeconds: range.endSeconds
            )
            guard !Task.isCancelled else { return }
            anchorInStill = stills?.inStill
            anchorOutStill = stills?.outStill
        }
    }

    private func anchorTaskKey(range: VideoTrimRange) -> String {
        "\(String(format: "%.2f", range.startSeconds))|\(String(format: "%.2f", range.endSeconds))"
    }

    private func header(media: MediaItemRecord, range: VideoTrimRange) -> some View {
        HStack(alignment: .center, spacing: 12) {
            PlateLabel(text: "Clip · \(media.filename)", size: 11, weight: .semibold)
            PlateLabel(
                text: videoTrimDisplayLabel(range: range),
                size: 9,
                color: PlateColor.inkFaint
            )
            Spacer(minLength: 0)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func transportRow(loopRange: ClosedRange<Double>?) -> some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isTransportActive ? "pause.fill" : "play.fill")
                    .frame(width: 30)
            }
            .buttonStyle(PlateButtonStyle())
            .disabled(assetDuration <= 0)
            .help(isTransportActive ? "Pause (Space)" : "Play (Space)")

            Button {
                step(by: -0.1)
            } label: {
                Image(systemName: "chevron.left").frame(width: 24)
            }
            .buttonStyle(PlateButtonStyle())
            .help("Step back 0.1s")

            Button {
                step(by: 0.1)
            } label: {
                Image(systemName: "chevron.right").frame(width: 24)
            }
            .buttonStyle(PlateButtonStyle())
            .help("Step forward 0.1s")

            PlateLabel(
                text: videoTrimPlayheadLabel(clampedTimestamp),
                size: 9.5,
                weight: .semibold
            )

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
                    isLoopingPreview ? "Stop Preview" : "Preview Range",
                    systemImage: isLoopingPreview ? "stop.circle" : "play.circle"
                )
            }
            .buttonStyle(PlateButtonStyle())
            .disabled(loopRange == nil)
            .help("Loop the selected range")

            Button {
                let seconds = clampedTimestamp
                captureConfirmation = ""
                Task {
                    guard let media else { return }
                    await library.addFrameToMedia(from: media, timestampSeconds: seconds)
                    captureConfirmation = "Still added to Media"
                }
            } label: {
                Label("Capture Still", systemImage: "plus.rectangle.on.rectangle")
            }
            .buttonStyle(PlateButtonStyle())
            .disabled(library.isAddingFrameToMedia)
            .help("Save the current frame to Media as a still")

            Button {
                copyCommittedRange()
            } label: {
                Label("Copy Range", systemImage: "doc.on.doc")
            }
            .buttonStyle(PlateButtonStyle())
            .disabled(committedRangeSeconds < ShotCutList.minimumRangeSeconds)
            .help("Copy this clip's COMMITTED range to the picture clipboard — paste it in the shot player to loop or re-place it. Footage copies are file-level and paste across shots")
        }
    }

    /// The committed (persisted) range in seconds — the Copy Range unit. The
    /// draft in/out handles are not yet the entry's truth; Apply first.
    private var committedRangeSeconds: Double {
        guard let entry else { return 0 }
        let start = entry.clipStartSeconds ?? 0
        let end = entry.clipEndSeconds ?? assetDuration
        return max(end - start, 0)
    }

    private func copyCommittedRange() {
        guard let shot, let entry, let media else { return }
        let start = entry.clipStartSeconds ?? 0
        let end = entry.clipEndSeconds ?? assetDuration
        let span = ShotPictureSegmentSpanRef(
            segmentKey: shotPlacementSegmentKey(
                startEntryId: entry.entryId,
                endEntryId: "",
                legacyStartId: shotFootageKey(
                    mediaId: entry.clipMediaId,
                    startSeconds: entry.clipStartSeconds,
                    endSeconds: entry.clipEndSeconds
                ),
                legacyEndId: ""
            ),
            clipPath: media.path,
            mediaId: media.mediaId,
            startSeconds: start,
            endSeconds: end,
            label: media.filename
        )
        ShotPictureClipboard.write(ShotPictureSegmentClipboardPayload(
            spans: [span],
            sourceShotId: shot.shotId,
            sourceProjectId: library.currentProject?.projectId ?? "",
            context: ShotSegmentContext(
                clipFilename: media.filename,
                copiedAt: DateFormats.now()
            )
        ))
        captureConfirmation = "Range copied — paste it in the shot player"
    }

    private func applyRow(range: VideoTrimRange, isDirty: Bool, assetDuration: Double) -> some View {
        HStack(spacing: 10) {
            Button("Set In") {
                localStartSeconds = min(max(timestampSeconds, 0), localEndSeconds)
            }
            .buttonStyle(PlateButtonStyle())
            .help("Set the in point to the playhead")

            Button("Set Out") {
                localEndSeconds = max(min(timestampSeconds, assetDuration), localStartSeconds)
            }
            .buttonStyle(PlateButtonStyle())
            .help("Set the out point to the playhead")

            if isDirty {
                PlateLabel(text: "Edited", size: 8.5, weight: .semibold)
            }
            if !range.isSaveable {
                PlateLabel(
                    text: "Range must be at least \(String(format: "%.1f", VideoTrimRange.minimumTrimSeconds))s",
                    size: 8.5,
                    color: PlateColor.inkFaint
                )
            }
            if !captureConfirmation.isEmpty {
                PlateLabel(text: captureConfirmation, size: 8.5, color: PlateColor.inkFaint)
            }

            Spacer(minLength: 0)

            Button("Revert") {
                guard let entry, let media else { return }
                let assetDuration = max(media.durationSeconds ?? 0, 0)
                localStartSeconds = entry.clipStartSeconds ?? 0
                localEndSeconds = entry.clipEndSeconds ?? assetDuration
            }
            .buttonStyle(PlateButtonStyle())
            .disabled(!isDirty)
            .help("Back to the placed range")

            Button("Apply Range") {
                isLoopingPreview = false
                registerPictureEdit(
                    library.updateShotClipRange(
                        shotId: shotId,
                        entryId: entryId,
                        startSeconds: range.startSeconds,
                        endSeconds: range.endSeconds
                    ),
                    "Trim Clip Range"
                )
            }
            .buttonStyle(PlateButtonStyle(isProminent: true))
            .disabled(!isDirty || !range.isSaveable)
            .help("Commit this in/out to the placed clip — the asset itself is never modified")
        }
    }

    // MARK: Anchor column

    private enum SeamSide {
        case leadIn
        case leadOut
    }

    private func anchorColumn(
        shot: ProjectShot,
        entry: ShotFrameEntry,
        media: MediaItemRecord,
        entryIndex: Int,
        clampedTimestamp: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            anchorTile(
                still: anchorInStill,
                side: .leadIn,
                shot: shot,
                entry: entry,
                entryIndex: entryIndex
            )
            anchorTile(
                still: anchorOutStill,
                side: .leadOut,
                shot: shot,
                entry: entry,
                entryIndex: entryIndex
            )
            Spacer(minLength: 0)
            PlateLabel(
                text: "Footage renders silent in the reel — narration rides the player.",
                size: 8.5,
                color: PlateColor.inkFaint
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func anchorTile(
        still: URL?,
        side: SeamSide,
        shot: ProjectShot,
        entry: ShotFrameEntry,
        entryIndex: Int
    ) -> some View {
        let neighbor: ShotFrameEntry? = side == .leadIn
            ? (entryIndex > 0 ? shot.entries[entryIndex - 1] : nil)
            : (entryIndex + 1 < shot.entries.count ? shot.entries[entryIndex + 1] : nil)
        let seamStyle: ShotSeamStyle? = neighbor.map { other in
            side == .leadIn
                ? resolvedShotSeamStyle(leftIsClip: other.isClip, rightIsClip: entry.isClip, rightPreference: entry.leadSeamPreference)
                : resolvedShotSeamStyle(leftIsClip: entry.isClip, rightIsClip: other.isClip, rightPreference: other.leadSeamPreference)
        }
        let title: String = {
            guard let seamStyle else {
                return side == .leadIn ? "FIRST IN SHOT" : "LAST IN SHOT"
            }
            switch (side, seamStyle) {
            case (.leadIn, .cut): return "HARD CUT IN"
            case (.leadIn, _): return "GENERATION LANDS HERE"
            case (.leadOut, .cut): return "HARD CUT OUT"
            case (.leadOut, _): return "GENERATION RESUMES HERE"
            }
        }()

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PlateLabel(
                    text: title,
                    size: 8,
                    weight: .semibold,
                    color: seamStyle == .cut ? PlateColor.inkFaint : PlateColor.ink
                )
                Spacer(minLength: 0)
                if let neighbor, let seamStyle,
                   shotSeamIsToggleable(
                       leftIsClip: side == .leadIn ? neighbor.isClip : entry.isClip,
                       rightIsClip: side == .leadIn ? entry.isClip : neighbor.isClip
                   ) {
                    Button(seamStyle == .cut ? "‖ CUT" : "≈ BRIDGED") {
                        registerPictureEdit(
                            library.setShotSeamStyle(
                                shotId: shotId,
                                entryId: side == .leadIn ? entry.entryId : neighbor.entryId,
                                style: seamStyle.toggled
                            ),
                            seamStyle.toggled == .cut ? "Seam: Hard Cut" : "Seam: Bridge"
                        )
                    }
                    .buttonStyle(PlateButtonStyle())
                    .help(seamStyle == .cut
                        ? "Hard cut — click to bridge (generated transition)"
                        : "Generated bridge — click to hard-cut")
                }
            }

            ZStack {
                PlateColor.creamDeep
                if let still, let image = NSImage(contentsOf: still) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PlateColor.inkFaint)
                }
            }
            .frame(width: 250, height: 141)
            .clipped()
            .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 1))
        }
    }

    // MARK: Spawn deck — the clip as generative seed

    /// "From this clip": Precede / Continue / Transform verb cards. Each
    /// captures the relevant moment as a quiet still and swaps this sheet for
    /// the seeded Frame Creator; Continue also hosts the direct AI extension.
    private func spawnDeck(
        shot: ProjectShot,
        entry: ShotFrameEntry,
        media: MediaItemRecord,
        range: VideoTrimRange,
        clampedTimestamp: Double
    ) -> some View {
        let appliedStart = entry.clipStartSeconds ?? 0
        let appliedEnd = entry.clipEndSeconds ?? max(media.durationSeconds ?? 0, 0)
        let rangeIsDirty = abs(range.startSeconds - appliedStart) > 0.01
            || abs(range.endSeconds - appliedEnd) > 0.01
        let entryIndex = shot.entries.firstIndex(where: { $0.entryId == entry.entryId })
        let hasAdjacentExtension = entryIndex.map { index in
            shot.entries.indices.contains(index + 1) && shot.entries[index + 1].isAIExtension
        } ?? false
        return VStack(alignment: .leading, spacing: 8) {
            PlateLabel(text: "From this clip", size: 9.5, weight: .semibold)
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    spawnCard(
                        title: "Precede",
                        icon: "arrow.left",
                        caption: "Author the moment that leads into this footage.",
                        buttonTitle: "New frame → before clip",
                        isHero: false
                    ) {
                        spawn(intent: .precede, media: media, atSeconds: range.startSeconds)
                    }
                    if shot.entries.first(where: { !$0.isSkipped })?.entryId == entryId {
                        Button {
                            isPlaying = false
                            isLoopingPreview = false
                            library.insertShotLeadIn(shotId: shotId)
                            captureConfirmation = "AI lead-in added before the clip — edit its prompt in Re-render"
                        } label: {
                            Label("Lead in with AI (~\(shot.renderStack.segmentSeconds)s)", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(PlateButtonStyle())
                        .disabled(!ShotRenderModel.anyLeadInCapable)
                        .help(ShotRenderModel.anyLeadInCapable
                            ? "Prepend an end-anchored generated segment that arrives on this clip's first frame — no start keyframe"
                            : "Lead in with AI — no wired model accepts a tail frame alone yet")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    spawnCard(
                        title: "Continue",
                        icon: "arrow.right",
                        caption: "Author what happens after the last frame.",
                        buttonTitle: "New frame → after clip",
                        isHero: true
                    ) {
                        spawn(intent: .continueFrom, media: media, atSeconds: range.endSeconds)
                    }
                    Button {
                        isPlaying = false
                        isLoopingPreview = false
                        guard let preparation = library.prepareShotExtension(
                            shotId: shotId,
                            afterEntryId: entryId,
                            startSeconds: range.startSeconds,
                            endSeconds: range.endSeconds
                        ) else { return }
                        registerPictureEdit(
                            preparation.pictureEdit,
                            rangeIsDirty ? "Trim Clip and Prepare Extension" : "Prepare AI Extension"
                        )
                        onReviewExtension(preparation)
                    } label: {
                        Label(
                            rangeIsDirty
                                ? "Apply range & extend with AI…"
                                : (hasAdjacentExtension
                                    ? "Review AI extension…"
                                    : "Extend with AI (~\(shot.renderStack.segmentSeconds)s)…"),
                            systemImage: "wand.and.stars"
                        )
                    }
                    .buttonStyle(PlateButtonStyle())
                    .disabled(!range.isSaveable)
                    .help(rangeIsDirty
                        ? "Commit this visible clip range, prepare one extension, and review its prompt, continuity, and cost before rendering"
                        : "Prepare one extension and review its prompt, continuity, and cost before any paid render")
                }

                spawnCard(
                    title: "Transform",
                    icon: "wand.and.stars",
                    caption: "Recreate the playhead moment in a catalog style.",
                    buttonTitle: "Styled frame from playhead",
                    isHero: false
                ) {
                    spawn(intent: .transform, media: media, atSeconds: clampedTimestamp)
                }
            }
            HStack(spacing: 6) {
                Button {
                    placeIntoShot.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: placeIntoShot ? "checkmark.square" : "square")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Place into the shot next to this clip")
                            .font(PlateType.label(9.5))
                    }
                    .foregroundStyle(PlateColor.ink)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("On: the new frame appears beside the clip immediately as a not-ready cell and fulfills in place. Off: it lands on the FRAMES board only.")
                PlateLabel(
                    text: "— the frame always lands on the FRAMES board too",
                    size: 8.5,
                    color: PlateColor.inkFaint
                )
                Spacer(minLength: 0)
                if isCapturingSeed {
                    PlateLabel(text: "Capturing seed…", size: 8.5, color: PlateColor.inkFaint)
                }
            }
        }
    }

    private func spawnCard(
        title: String,
        icon: String,
        caption: String,
        buttonTitle: String,
        isHero: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PlateColor.ink)
                PlateLabel(text: title, size: 9.5, weight: .semibold)
            }
            Text(caption)
                .font(PlateType.label(9))
                .foregroundStyle(PlateColor.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            Button(buttonTitle, action: action)
                .buttonStyle(PlateButtonStyle(isProminent: isHero))
                .disabled(isCapturingSeed)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            Rectangle()
                .stroke(PlateColor.hairline, lineWidth: isHero ? 1.5 : 1)
        )
    }

    /// Lucy restyle of this entry's COMMITTED range — no shot render needed.
    /// Tray-only landing: the result nests under this clip in Footage; the
    /// shot itself is never changed.
    private func clipLookSection(
        shot: ProjectShot,
        entry: ShotFrameEntry,
        media: MediaItemRecord,
        isDirty: Bool
    ) -> some View {
        let assetDuration = max(media.durationSeconds ?? 0, 0)
        let committed = VideoTrimRange.clamped(
            start: entry.clipStartSeconds ?? 0,
            end: entry.clipEndSeconds ?? assetDuration,
            videoDurationSeconds: assetDuration
        )
        let composed = shotLookComposedPrompt(styleSummary: clipLookStyle?.summary ?? "", userText: clipLookNotes)
        let hasFALCredential = library.videoProviderCredentialStatuses
            .first(where: { $0.provider == .fal })?.isConfigured == true
        let hasDecartCredential = library.videoProviderCredentialStatuses
            .first(where: { $0.provider == .decart })?.isConfigured == true
        let hasSelectedCredential = clipLookProvider == .fal ? hasFALCredential : hasDecartCredential
        // Clip Looks run in their own lane — shot renders / joins / Shot
        // Looks neither block nor are blocked by them. The only gate here is
        // the lane cap.
        let laneIsFull = library.clipLookLaneIsFull
        let inFlightStatuses = ["preparing", "uploading", "queued", "generating", "downloading"]
        let activeClipLooks = shot.clipLookVersions.filter {
            $0.sourceClipMediaId == media.mediaId
                && library.activeClipLookIds.contains($0.versionId)
                && inFlightStatuses.contains($0.status)
        }
        let recoverable = shot.clipLookVersions.reversed().first {
            $0.sourceClipMediaId == media.mediaId
                && abs($0.sourceClipStartSeconds - committed.startSeconds) < 0.05
                && abs($0.sourceClipEndSeconds - committed.endSeconds) < 0.05
                && ["failed", "paused", "queued", "generating", "downloading"].contains($0.status)
                && !$0.requestId.isEmpty
                && !library.activeClipLookIds.contains($0.versionId)
                && ($0.restyleProvider == .decart
                    || !$0.errorMessage.localizedCaseInsensitiveContains("handoff is no longer accessible"))
        }
        let estimatedCost = committed.durationSeconds * 0.01
        let estimatedCostLabel = clipLookProvider == .fal
            ? String(format: "EST. $%.2f", estimatedCost)
            : String(format: "EST. %.1f CREDITS", committed.durationSeconds)
        let hasExecutableInput = clipLookProvider == .fal
            ? (!composed.isEmpty && composed.count <= 1_500)
            : (clipLookStyle?.hasUsableImageReference == true)
        let canSubmit = hasSelectedCredential
            && !laneIsFull
            && committed.isSaveable
            && hasExecutableInput

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PlateLabel(text: "Clip Look", size: 9.5, weight: .semibold)
                PlateLabel(text: "LUCY · 720P", size: 8, color: PlateColor.inkFaint)
                PlateLabel(text: videoTrimDisplayLabel(range: committed), size: 8, color: PlateColor.inkFaint)
                Spacer(minLength: 0)
                PlateLabel(
                    text: estimatedCostLabel,
                    size: 8.5,
                    weight: .bold,
                    color: CanonColor.brass
                )
            }
            HStack(alignment: .top, spacing: 10) {
                Picker("Provider", selection: clipLookProviderBinding) {
                    ForEach(ShotLookProvider.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150)
                ShotLookStyleChipRow(
                    styleSelection: $clipLookStyle,
                    provider: clipLookProvider
                ) {
                    isPlaying = false
                    isLoopingPreview = false
                    isClipLookStylePickerOpen = true
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if clipLookProvider == .fal {
                TextField("Optional refinement notes — the chosen style leads this Look…", text: $clipLookNotes)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(PlateColor.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 1))
                    .onChange(of: clipLookNotes) { _, value in
                        if value.count > 1_500 { clipLookNotes = String(value.prefix(1_500)) }
                    }
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "photo")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(PlateColor.inkFaint)
                    Text("Reference image input · no text prompt · prompt enhancement off")
                        .font(.system(size: 9.5, design: .serif))
                        .foregroundStyle(PlateColor.inkFaint)
                }
                .padding(.vertical, 3)
            }
            // One row per running look — several can target this clip at
            // once (style A/B/C exploration); each cancels independently.
            ForEach(activeClipLooks, id: \.versionId) { runningLook in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        PlateLabel(
                            text: runningLook.status.uppercased(),
                            size: 8.5,
                            weight: .bold,
                            color: CanonColor.brass
                        )
                        PlateLabel(
                            text: runningLook.styleLabel.trimmed.nilIfEmpty ?? "v\(runningLook.versionNumber)",
                            size: 8.5,
                            color: PlateColor.inkFaint
                        )
                        Spacer(minLength: 0)
                        Button(runningLook.restyleProvider == .decart && !runningLook.requestId.isEmpty
                            ? "STOP WAITING"
                            : "CANCEL") {
                            library.cancelClipLookRestyle(shotId: shotId, versionId: runningLook.versionId)
                        }
                        .buttonStyle(PlateButtonStyle())
                    }
                    if runningLook.restyleProvider == .decart && !runningLook.requestId.isEmpty {
                        PlateLabel(
                            text: "Stops local monitoring only; Decart may keep processing or charging.",
                            size: 8,
                            color: CanonColor.rust
                        )
                    }
                }
            }
            HStack(alignment: .center, spacing: 8) {
                if !hasSelectedCredential {
                    clipLookWarning("Add a \(clipLookProvider == .fal ? "FAL" : "Decart") API key in App Settings before creating a Clip Look.")
                } else if laneIsFull {
                    clipLookWarning("\(library.clipLookLaneCap) Clip Looks are already running — wait for one to finish.")
                } else if clipLookProvider == .fal && composed.count > 1_500 {
                    clipLookWarning("Style direction plus notes exceed 1500 characters — trim the notes.")
                } else if clipLookProvider == .decart && clipLookStyle == nil {
                    clipLookWarning("Choose a catalog style for Decart's image input.")
                } else if clipLookProvider == .decart && clipLookStyle?.hasUsableImageReference != true {
                    clipLookWarning("Reselect this style so its verified image can be attached.")
                } else if isDirty {
                    PlateLabel(
                        text: "Restyles the applied range — Apply Range first to use the edited one",
                        size: 8.5,
                        color: PlateColor.inkFaint
                    )
                } else if let recoverable, let errorMessage = recoverable.errorMessage.trimmed.nilIfEmpty {
                    clipLookWarning(String(errorMessage.prefix(160)))
                }
                Spacer(minLength: 0)
                if let recoverable {
                    Button(recoverable.outputRemoteURL.isEmpty ? "Resume Clip Look" : "Retry download") {
                        library.retryClipLook(shotId: shotId, versionId: recoverable.versionId)
                    }
                    .buttonStyle(PlateButtonStyle())
                    .disabled(!credentialAvailable(for: recoverable, hasFAL: hasFALCredential, hasDecart: hasDecartCredential) || laneIsFull)
                    .help(recoverable.errorMessage)
                }
                Button("Restyle clip · \(estimatedCostLabel)") {
                    isPlaying = false
                    isLoopingPreview = false
                    library.startClipLookRestyle(
                        shotId: shotId,
                        entryId: entryId,
                        prompt: clipLookNotes,
                        enhancePrompt: true,
                        seed: Int.random(in: 1...Int(Int32.max)),
                        style: clipLookStyle,
                        provider: clipLookProvider
                    )
                }
                .buttonStyle(PlateButtonStyle(isProminent: true))
                .disabled(!canSubmit)
            }
            PlateLabel(
                text: "Picture by Lucy · original audio kept · lands in Footage under this clip — the shot is not changed",
                size: 8.5,
                color: PlateColor.inkFaint
            )
        }
    }

    private func clipLookWarning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CanonColor.rust)
            Text(text)
                .font(.system(size: 9.5, design: .serif))
                .foregroundStyle(CanonColor.rust)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func credentialAvailable(
        for look: ShotRestyleArtifact,
        hasFAL: Bool,
        hasDecart: Bool
    ) -> Bool {
        look.restyleProvider == .fal ? hasFAL : hasDecart
    }

    private func spawn(intent: ClipMomentIntent, media: MediaItemRecord, atSeconds seconds: Double) {
        guard !isCapturingSeed else { return }
        isPlaying = false
        isLoopingPreview = false
        isCapturingSeed = true
        let placement = placeIntoShot
        Task {
            defer { isCapturingSeed = false }
            guard let still = await library.captureClipSeedStill(
                mediaId: media.mediaId,
                timestampSeconds: seconds
            ) else {
                captureConfirmation = "Couldn't capture the seed frame"
                return
            }
            onSpawnFrame(ClipMomentSeed(
                shotId: shotId,
                entryId: entryId,
                clipMediaId: media.mediaId,
                clipFilename: media.filename,
                stillMediaId: still.mediaId,
                stillPath: still.path,
                timestampSeconds: seconds,
                intent: intent,
                placeIntoShot: placement
            ))
        }
    }

    // MARK: Transport helpers

    private func togglePlayback() {
        guard assetDuration > 0 else { return }
        if isTransportActive {
            isPlaying = false
            isLoopingPreview = false
            return
        }
        if clampedTimestamp >= max(assetDuration - 0.05, 0) {
            timestampSeconds = 0
        }
        isPlaying = true
    }

    private func step(by delta: Double) {
        isPlaying = false
        isLoopingPreview = false
        timestampSeconds = min(max(clampedTimestamp + delta, 0), max(assetDuration - 0.01, 0))
    }
}
