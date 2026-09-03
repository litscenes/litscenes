@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ShotMicrophoneControlMode: Equatable {
    case idle
    case countIn(Int)
    case recording
    case finalizing

    var buttonLabel: String {
        switch self {
        case .idle: return "Rec Mic"
        case .countIn(let count): return "Cancel \(count)"
        case .recording: return "Stop"
        case .finalizing: return "Saving…"
        }
    }

    var isActive: Bool {
        switch self {
        case .countIn, .recording, .finalizing: return true
        case .idle: return false
        }
    }
}

struct ShotAudioWaveformRegion: Identifiable {
    var id: String
    var path: String
    var startSeconds: Double
    var durationSeconds: Double
    var sourceRanges: [ShotKeepRange] = []
    /// The editable region behind this band; nil = decorative source band.
    var regionId: String? = nil
    var loops: Bool = false
    var sourceStartSeconds: Double = 0
    var loopPhaseSeconds: Double = 0
    var playbackRate: Double = 1
    var sourceDurationSeconds: Double? = nil
    var isMissingFile: Bool = false
    /// The file EXISTS but its audio cannot be read — the cloud-placeholder
    /// case (`fileExists` is true for a dataless Dropbox/iCloud file). Drawn
    /// as OFFLINE, distinct from MISSING, because the cure differs: download
    /// it, don't relink it.
    var isUnreadableFile: Bool = false
    var isMuted: Bool = false
    var fadeInSeconds: Double = 0
    var fadeOutSeconds: Double = 0

    var endSeconds: Double { startSeconds + durationSeconds }
}

@MainActor
final class ShotAudioWaveformLoader: ObservableObject {
    @Published private var states: [String: SoundWaveformLoadState] = [:]
    private var tasks: [String: Task<SoundWaveform, Error>] = [:]

    func state(path: String) -> SoundWaveformLoadState {
        states[path] ?? .idle
    }

    func load(paths: [String]) {
        for path in Set(paths) where !path.isEmpty && states[path] == nil {
            guard FileManager.default.fileExists(atPath: path) else {
                states[path] = .unavailable("Audio file missing.")
                continue
            }
            states[path] = .loading
            let task = Task.detached(priority: .utility) {
                try await SoundWaveformExtractor.extract(
                    soundId: shortHash(path, length: 12),
                    path: path,
                    modifiedAt: "",
                    durationSeconds: 0,
                    sampleCount: 240
                )
            }
            tasks[path] = task
            Task { [weak self] in
                do {
                    let waveform = try await task.value
                    self?.states[path] = .ready(waveform)
                } catch {
                    self?.states[path] = .unavailable("Waveform unavailable.")
                }
                self?.tasks[path] = nil
            }
        }
    }
}

/// Probes each referenced audio path ONCE per stack lifetime and publishes
/// the set that exist on disk but cannot be read — the cloud-placeholder
/// case (`fileExists` is true for a dataless Dropbox/iCloud file, and
/// playback then silently skips it). Owned by the lane STACK, not the
/// per-lane waveform view, because the lane-head chip and the inspector
/// need the answer across lanes. A probe that fails stays failed until the
/// stack is rebuilt (modal reopen) — the same lifetime as the silence it
/// explains. As a side effect the read attempt itself asks the file
/// provider to materialize the file, so opening the editor nudges the
/// download.
@MainActor
final class ShotAudioReadabilityProbe: ObservableObject {
    @Published private(set) var unreadablePaths: Set<String> = []
    private var probedPaths: Set<String> = []

    func probe(paths: [String]) {
        for path in Set(paths) where !path.isEmpty && !probedPaths.contains(path) {
            probedPaths.insert(path)
            guard FileManager.default.fileExists(atPath: path) else { continue }
            Task { [weak self] in
                let audioTracks = try? await AVURLAsset(url: URL(fileURLWithPath: path))
                    .loadTracks(withMediaType: .audio)
                if audioTracks?.isEmpty != false {
                    self?.unreadablePaths.insert(path)
                }
            }
        }
    }

    func couldNotRead(path: String) -> Bool {
        unreadablePaths.contains(path)
    }
}

/// Region edits register REAL UndoManager actions (⌘Z / ⇧⌘Z through the
/// window's Edit menu), replacing the old one-slot local undo. Snapshot
/// based: one committed gesture = one registration, and each handler
/// re-registers its inverse symmetrically (the timing-coordinator precedent).
/// `applyRegion` restores a snapshot WHOLESALE (identity included) via the
/// engine's restore op, so replace-media and delete round-trip exactly.
@MainActor
final class ShotAudioRegionUndoCoordinator: ObservableObject {
    var applyRegion: ((ShotAudioRegion) -> Void)?
    var deleteRegion: ((String) -> Void)?
    var applyAudioState: ((ShotAudioStateSnapshot) -> Void)?

    func registerEdit(
        old: ShotAudioRegion,
        new: ShotAudioRegion,
        actionName: String,
        undoManager: UndoManager?
    ) {
        guard let undoManager, old != new else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.applyRegion?(old)
                target.registerEdit(old: new, new: old, actionName: actionName, undoManager: undoManager)
            }
        }
        undoManager.setActionName(actionName)
    }

    func registerAdd(_ added: ShotAudioRegion, undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.deleteRegion?(added.regionId)
                target.registerDelete(added, undoManager: undoManager)
            }
        }
        undoManager.setActionName("Add Audio")
    }

    func registerDelete(
        _ deleted: ShotAudioRegion,
        actionName: String = "Delete Audio Region",
        undoManager: UndoManager?
    ) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.applyRegion?(deleted)
                target.registerAdd(deleted, undoManager: undoManager)
            }
        }
        undoManager.setActionName(actionName)
    }

    func registerStateEdit(
        old: ShotAudioStateSnapshot,
        new: ShotAudioStateSnapshot,
        actionName: String,
        undoManager: UndoManager?
    ) {
        guard let undoManager, old != new else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.applyAudioState?(old)
                target.registerStateEdit(
                    old: new,
                    new: old,
                    actionName: actionName,
                    undoManager: undoManager
                )
            }
        }
        undoManager.setActionName(actionName)
    }

    /// Per-segment SOURCE intent, and detach — which changes intent AND regions,
    /// so it restores both together or neither. Symmetric by construction: each
    /// undo re-registers its own inverse, so redo works without a second path.
    var applySourceState: ((ShotSourceDetachSnapshot) -> Void)?

    func registerSourceEdit(
        old: ShotSourceDetachSnapshot,
        new: ShotSourceDetachSnapshot,
        actionName: String,
        undoManager: UndoManager?
    ) {
        guard let undoManager,
              old.sourceSegmentAudio != new.sourceSegmentAudio
                  || old.audioRegions != new.audioRegions else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.applySourceState?(old)
                target.registerSourceEdit(
                    old: new,
                    new: old,
                    actionName: actionName,
                    undoManager: undoManager
                )
            }
        }
        undoManager.setActionName(actionName)
    }
}

/// Engine-facing region actions, bundled `CutStripActions`-style so the modal
/// signature stays sane. Mutating closures return the PRE-edit snapshot;
/// `currentRegion` reads the post-edit state (the engine publishes
/// synchronously), so one committed gesture registers exactly one undo action
/// from a true old/new pair.
struct ShotAudioRegionActions {
    var add: (String, ShotAudioAssetReference, Double) -> ShotAudioStateEdit? = { _, _, _ in nil }
    var addTrack: (String, ShotAudioAssetReference, Double) -> ShotAudioStateEdit? = { _, _, _ in nil }
    var move: (String, Double) -> ShotAudioRegion? = { _, _ in nil }
    var setGeometry: (String, Double, Double, Double) -> ShotAudioRegion? = { _, _, _, _ in nil }
    var split: (String, Double) -> ShotAudioStateEdit? = { _, _ in nil }
    var setLoops: (String, Bool) -> ShotAudioRegion? = { _, _ in nil }
    var replaceMedia: (String, ShotAudioAssetReference) -> ShotAudioRegion? = { _, _ in nil }
    var update: (ShotAudioRegion) -> ShotAudioRegion? = { _ in nil }
    var makeAudible: (String) -> ShotAudioStateEdit? = { _ in nil }
    var delete: (String) -> ShotAudioRegion? = { _ in nil }
    var restore: (ShotAudioRegion) -> Void = { _ in }
    var restoreState: (ShotAudioStateSnapshot) -> Void = { _ in }
    var currentRegion: (String) -> ShotAudioRegion? = { _ in nil }
    var importAudioFiles: ([URL]) async -> [MediaItemRecord] = { _ in [] }
    var backfillDurations: () async -> Void = { }

    // Per-segment SOURCE audio. Same contract as the region ops: the mutators
    // return the PRE-edit state so one gesture registers one undo action.
    // Wholesale rosters rather than single rows, because a detach changes the
    // intent roster and the region roster together.
    var setSourceSegment: (String, Double, Bool) -> [ShotSourceSegmentAudio]? = { _, _, _ in nil }
    var detachSourceSegment: (String) -> ShotSourceDetachSnapshot? = { _ in nil }
    var restoreSourceDetach: (ShotSourceDetachSnapshot) -> Void = { _ in }
    var currentSourceState: () -> ShotSourceDetachSnapshot = {
        ShotSourceDetachSnapshot(sourceSegmentAudio: [], audioRegions: [])
    }

    // Rows. `moveToLane` returns the PRE-move snapshot, so a move undoes like
    // every other region edit.
    var addLane: (String) -> ShotAudioStateEdit? = { _ in nil }
    var removeLane: (String) -> ShotAudioStateEdit? = { _ in nil }
    var moveToLane: (String, String) -> ShotAudioRegion? = { _, _ in nil }

    // Lane controls and take activation return whole-state edits so the
    // header's mute, the tail's volume, and the take chooser undo like every
    // region gesture (they were the undo surface's last holes).
    var setLaneEnabled: (String, Bool) -> ShotAudioStateEdit? = { _, _ in nil }
    var setLaneVolume: (String, Double) -> ShotAudioStateEdit? = { _, _ in nil }
    var activateTake: (String) -> ShotAudioStateEdit? = { _ in nil }

    // Batch ops: one engine transaction = one Undo step for a multi-file
    // drop/import (`addBatch`) and the picker's remove-all (`deleteMany`).
    var addBatch: (String, [ShotAudioAssetReference], Double) -> ShotAudioStateEdit? = { _, _, _ in nil }
    var deleteMany: ([String]) -> ShotAudioStateEdit? = { _ in nil }

    // Clipboard ops. `paste` takes (payload, preferred lane, start seconds);
    // `duplicate` butt-joins a copy at the region's exact end. Both return
    // whole-state edits (lane prep + insert = one transaction).
    var paste: (ShotAudioRegionClipboardPayload, String?, Double) -> ShotAudioStateEdit? = { _, _, _ in nil }
    var duplicate: (String) -> ShotAudioStateEdit? = { _ in nil }
}

private struct ShotAudioPickerAsset: Identifiable {
    var asset: ShotAudioAssetReference
    var name: String
    var id: String { asset.stableId }
}

/// What a lane drop resolved to: library media ids and/or Finder files.
struct ShotAudioLaneDropPayload {
    var mediaIds: [String] = []
    var fileURLs: [URL] = []
    var isEmpty: Bool { mediaIds.isEmpty && fileURLs.isEmpty }
}

/// Accepts library audio drags (`MediaIDTransfer` JSON) and Finder audio
/// files, tracking the hover position so the lane can draw a live insertion
/// caret with a timecode chip.
private struct AudioLaneDropDelegate: DropDelegate {
    let durationSeconds: Double
    let width: CGFloat
    let viewport: ShotTimelineViewport
    @Binding var caretSeconds: Double?
    let onPerform: (ShotAudioLaneDropPayload, Double) -> Void

    private func seconds(at location: CGPoint) -> Double {
        guard width > 0, durationSeconds > 0 else { return 0 }
        return ShotAudioTiming.frameQuantizedStart(ShotTimelineAxis.seconds(
            forX: location.x,
            durationSeconds: durationSeconds,
            laneWidth: width,
            viewport: viewport
        ))
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.json, .fileURL])
    }

    func dropEntered(info: DropInfo) {
        caretSeconds = seconds(at: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        caretSeconds = seconds(at: info.location)
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        caretSeconds = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let dropSeconds = seconds(at: info.location)
        caretSeconds = nil
        let providers = info.itemProviders(for: [.json, .fileURL])
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            var payload = ShotAudioLaneDropPayload()
            for provider in providers {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let url = await loadFileURL(from: provider) {
                        payload.fileURLs.append(url)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.json.identifier),
                          let mediaId = await loadMediaId(from: provider) {
                    payload.mediaIds.append(mediaId)
                }
            }
            guard !payload.isEmpty else { return }
            onPerform(payload, dropSeconds)
        }
        return true
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
            }
        }
    }

    private func loadMediaId(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, _ in
                let transfer = data.flatMap { try? JSONDecoder().decode(MediaIDTransfer.self, from: $0) }
                continuation.resume(returning: transfer?.mediaId)
            }
        }
    }
}

/// One lane's waveform: seek on empty space, and full direct manipulation on
/// regions — click selects, dragging the body moves (playhead/edge snapping,
/// Option bypasses), dragging an edge trims, with the honest MEDIA END clamp
/// on non-looping regions. Arrow keys nudge, ⌫ deletes, and every commit is
/// exactly one undoable engine transaction.
struct ShotTimelineWaveformView: View {
    let regions: [ShotAudioWaveformRegion]
    let durationSeconds: Double
    let playheadSeconds: Double
    let isEnabled: Bool
    /// Recording gates all region interaction off (seek stays live).
    var isInteractionEnabled: Bool = true
    var selectedRegionId: String? = nil
    /// Same-lane snap targets beyond the playhead (region edges, 0, end).
    var snapTargets: [Double] = []
    var acceptsAudioDrop: Bool = false
    /// A selected SOURCE envelope's output span, drawn in the selection's
    /// brass but with no handles — envelope geometry is authored at combine
    /// time and is not draggable here.
    var envelopeHighlight: ShotKeepRange? = nil
    /// Bumped by the stack whenever selection is granted from a menu, picker,
    /// or edit side-effect. The lane holding the selection takes keyboard
    /// focus, so M/L/S/⌫/arrows work without a second click.
    var selectionFocusToken: Int = 0
    var onSeek: (Double) -> Void
    var onSelectRegion: (String?) -> Void = { _ in }
    var onGestureBegan: () -> Void = { }
    /// THE SCRUB LATCH: a lane seek pauses on begin and resumes on release
    /// iff playback was running. Region gestures keep the pause law instead.
    var onScrubBegan: () -> Void = { }
    var onScrubEnded: () -> Void = { }
    var onMoveCommitted: (String, Double) -> Void = { _, _ in }
    var onTrimCommitted: (String, Double, Double, Double) -> Void = { _, _, _, _ in }
    /// One committed fade-handle drag: (regionId, fadeIn, fadeOut).
    var onFadeCommitted: (String, Double, Double) -> Void = { _, _, _ in }
    /// Edit-menu clipboard commands, implemented by the stack (which owns the
    /// clipboard and the commit/undo laws). Copy/cut return the providers
    /// SwiftUI writes to the pasteboard; paste targets THIS lane.
    var onCopySelected: () -> [NSItemProvider] = { [] }
    var onCutSelected: () -> [NSItemProvider] = { [] }
    var onPaste: () -> Void = { }
    var onNudgeSelected: (Int) -> Void = { _ in }
    var onTrimSelectedToPlayhead: (Bool) -> Void = { _ in }
    var onToggleLoopSelected: () -> Void = { }
    var onToggleMuteSelected: () -> Void = { }
    var onSplitSelected: () -> Void = { }
    var onDeleteSelected: () -> Void = { }
    var onAudioDrop: (ShotAudioLaneDropPayload, Double) -> Void = { _, _ in }
    /// The playhead now lives on the stack, so snap feedback (which used to
    /// widen this lane's own line) has to travel out to it.
    var onSnapChanged: (Bool) -> Void = { _ in }

    @Environment(\.shotTimelineViewport) private var viewport
    @Environment(\.shotTimelineMetrics) private var metrics
    @StateObject private var loader = ShotAudioWaveformLoader()
    @FocusState private var isKeyboardFocused: Bool
    @State private var gestureMode: GestureMode?
    @State private var draftRegion: DraftRegion?
    @State private var isSnapped = false
    @State private var isClampedAtMediaEnd = false
    @State private var hoveredZone: RegionHitZone?
    @State private var dropCaretSeconds: Double?

    private enum RegionHitZone { case body, inEdge, outEdge, fadeIn, fadeOut }

    private enum GestureMode: Equatable {
        case seek
        case move(String)
        case trimIn(String)
        case trimOut(String)
        case fadeIn(String)
        case fadeOut(String)
    }

    private struct DraftRegion {
        var regionId: String
        var initial: ShotAudioWaveformRegion
        var startSeconds: Double
        var sourceStartSeconds: Double
        var durationSeconds: Double
        var fadeInSeconds: Double = 0
        var fadeOutSeconds: Double = 0
    }

    /// Fade handles are hit-testable only on lanes tall enough to keep them
    /// clear of the trim edges — the sound editor's `.editor` metrics. Inline
    /// lanes still DRAW fades; they edit them through the inspector fields.
    private var fadeHandlesEnabled: Bool { metrics.laneHeight >= 44 }

    private var loadSignature: String {
        regions.map { "\($0.path)#\($0.durationSeconds)" }.joined(separator: "|")
    }

    private var hasInteractiveRegions: Bool {
        isInteractionEnabled && regions.contains { $0.regionId != nil }
    }

    private var selectionIsHere: Bool {
        guard let selectedRegionId else { return false }
        return regions.contains { $0.regionId == selectedRegionId }
    }

    private var displayRegions: [ShotAudioWaveformRegion] {
        guard let draftRegion else { return regions }
        return regions.map { region in
            guard region.regionId == draftRegion.regionId else { return region }
            var draft = region
            draft.startSeconds = draftRegion.startSeconds
            draft.sourceStartSeconds = draftRegion.sourceStartSeconds
            draft.durationSeconds = draftRegion.durationSeconds
            draft.fadeInSeconds = draftRegion.fadeInSeconds
            draft.fadeOutSeconds = draftRegion.fadeOutSeconds
            if !draft.loops {
                draft.sourceRanges = [ShotKeepRange(
                    start: draft.sourceStartSeconds,
                    end: draft.sourceStartSeconds + draft.durationSeconds * draft.playbackRate
                )]
            }
            return draft
        }
    }

    private var timingChip: (text: String, isClamped: Bool, seconds: Double)? {
        if let draftRegion {
            switch gestureMode {
            case .trimOut:
                let end = draftRegion.startSeconds + draftRegion.durationSeconds
                return (
                    isClampedAtMediaEnd
                        ? "MEDIA END · \(ShotAudioTiming.timecode(end))"
                        : ShotAudioTiming.timecode(end),
                    isClampedAtMediaEnd,
                    end
                )
            case .fadeIn:
                return (
                    "FADE \(ShotAudioTiming.timecode(draftRegion.fadeInSeconds))",
                    false,
                    draftRegion.startSeconds + draftRegion.fadeInSeconds
                )
            case .fadeOut:
                let end = draftRegion.startSeconds + draftRegion.durationSeconds
                return (
                    "FADE \(ShotAudioTiming.timecode(draftRegion.fadeOutSeconds))",
                    false,
                    end - draftRegion.fadeOutSeconds
                )
            default:
                return (ShotAudioTiming.timecode(draftRegion.startSeconds), false, draftRegion.startSeconds)
            }
        }
        if let dropCaretSeconds {
            return (ShotAudioTiming.timecode(dropCaretSeconds), false, dropCaretSeconds)
        }
        guard selectionIsHere,
              let selected = regions.first(where: { $0.regionId == selectedRegionId }) else { return nil }
        return (ShotAudioTiming.timecode(selected.startSeconds), false, selected.startSeconds)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(PlateColor.creamDeep.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(
                                dropCaretSeconds != nil ? CanonColor.brass : PlateColor.hairline.opacity(0.75),
                                lineWidth: dropCaretSeconds != nil ? 1.2 : 0.7
                            )
                    )
                // No padding: the Canvas must span the SAME box the gestures
                // measure, or drawn positions and hit-tested positions drift
                // (they did, by up to ~8pt — wider than the trim edge zones).
                // The visual inset is arithmetic, via ShotTimelineAxis.
                Canvas { context, size in
                    drawWaveform(context: context, size: size)
                }

                if let dropCaretSeconds, durationSeconds > 0 {
                    let x = ShotTimelineAxis.x(
                        forSeconds: dropCaretSeconds,
                        durationSeconds: durationSeconds,
                        laneWidth: geometry.size.width,
                        viewport: viewport
                    )
                    Rectangle()
                        .fill(CanonColor.brass)
                        .frame(width: 1.5)
                        .position(x: x, y: geometry.size.height / 2)
                        .allowsHitTesting(false)
                }

                if let chip = timingChip {
                    Text(chip.text)
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(chip.isClamped ? Color.white : PlateColor.ink)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            chip.isClamped ? CanonColor.rust : PlateColor.cream.opacity(0.94),
                            in: RoundedRectangle(cornerRadius: 2)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(
                                    chip.isClamped
                                        ? CanonColor.rust
                                        : (isSnapped ? CanonColor.brass : PlateColor.hairline)
                                )
                        )
                        .position(
                            x: timingLabelX(seconds: chip.seconds, width: geometry.size.width),
                            y: 8
                        )
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(width: geometry.size.width, height: geometry.size.height))
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard gestureMode == nil else { return }
                    if isInteractionEnabled,
                       let hit = regionHit(at: location, width: geometry.size.width, height: geometry.size.height) {
                        hoveredZone = hit.zone
                        switch hit.zone {
                        case .body: NSCursor.openHand.set()
                        case .inEdge, .outEdge, .fadeIn, .fadeOut: NSCursor.resizeLeftRight.set()
                        }
                    } else {
                        hoveredZone = nil
                        NSCursor.arrow.set()
                    }
                case .ended:
                    hoveredZone = nil
                    if gestureMode == nil { NSCursor.arrow.set() }
                }
            }
            .onDrop(
                of: acceptsAudioDrop ? [.json, .fileURL] : [],
                delegate: AudioLaneDropDelegate(
                    durationSeconds: durationSeconds,
                    width: geometry.size.width,
                    viewport: viewport,
                    caretSeconds: $dropCaretSeconds,
                    onPerform: onAudioDrop
                )
            )
        }
        .frame(height: metrics.waveformHeight)
        .opacity(isEnabled ? 1 : 0.42)
        .focusable(hasInteractiveRegions)
        .focused($isKeyboardFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            guard selectionIsHere else { return .ignored }
            let frames = press.modifiers.contains(.shift) ? 10 : 1
            onGestureBegan()
            onNudgeSelected(press.key == .leftArrow ? -frames : frames)
            return .handled
        }
        .onKeyPress(keys: ["[", "]"]) { press in
            guard selectionIsHere else { return .ignored }
            onGestureBegan()
            onTrimSelectedToPlayhead(press.key == "[")
            return .handled
        }
        .onKeyPress(keys: ["l"]) { _ in
            guard selectionIsHere else { return .ignored }
            onGestureBegan()
            onToggleLoopSelected()
            return .handled
        }
        .onKeyPress(keys: ["m"]) { _ in
            // No pause: a mute is a level edit and plays through (the pause
            // law lives on the stack's `onGestureBegan`).
            guard selectionIsHere else { return .ignored }
            onToggleMuteSelected()
            return .handled
        }
        .onKeyPress(keys: ["s"]) { _ in
            guard selectionIsHere else { return .ignored }
            onSplitSelected()
            return .handled
        }
        .onDeleteCommand {
            guard selectionIsHere else { return }
            onGestureBegan()
            onDeleteSelected()
        }
        // The real Edit menu (⌘C/⌘X/⌘V): enablement follows lane focus for
        // free, and a focused TEXT FIELD keeps its own copy/paste because
        // these only resolve while the lane owns the keyboard.
        .onCopyCommand {
            guard selectionIsHere else { return [] }
            return onCopySelected()
        }
        .onCutCommand {
            guard selectionIsHere else { return [] }
            return onCutSelected()
        }
        .onPasteCommand(of: [ShotAudioClipboard.utType]) { _ in
            // The payload is read straight off NSPasteboard (synchronous);
            // the providers only gate menu enablement.
            onPaste()
        }
        .onKeyPress(.escape) {
            // THE ESCAPE LADDER's lane rung: a selected region deselects and
            // consumes the press; an unselected lane lets it BUBBLE to the
            // modal's rungs (the old `.onExitCommand` ate it silently, which
            // made Escape's meaning depend on invisible focus state).
            guard selectionIsHere else { return .ignored }
            onSelectRegion(nil)
            return .handled
        }
        .onChange(of: selectionFocusToken) { _, _ in
            // Focus follows selection, wherever it was granted.
            if selectionIsHere { isKeyboardFocused = true }
        }
        .task(id: loadSignature) {
            loader.load(paths: regions.map(\.path))
        }
        .accessibilityLabel(hasInteractiveRegions ? "Audio regions" : "Audio waveform")
        .accessibilityHint(hasInteractiveRegions
            ? "Click a region to select it; drag to move, drag an edge to trim; arrow keys nudge"
            : "Click or drag to seek")
        .accessibilityAdjustableAction { direction in
            guard selectionIsHere else { return }
            onGestureBegan()
            onNudgeSelected(direction == .increment ? 1 : -1)
        }
    }

    // MARK: Gestures

    private func dragGesture(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard durationSeconds > 0 else { return }
                if gestureMode == nil {
                    beginGesture(at: value.startLocation, width: width, height: height)
                }
                switch gestureMode {
                case .move:
                    updateMoveDraft(translation: value.translation.width, width: width)
                case .trimIn:
                    updateTrimInDraft(translation: value.translation.width, width: width)
                case .trimOut:
                    updateTrimOutDraft(translation: value.translation.width, width: width)
                case .fadeIn:
                    updateFadeInDraft(translation: value.translation.width, width: width)
                case .fadeOut:
                    updateFadeOutDraft(translation: value.translation.width, width: width)
                case .seek:
                    onSeek(ShotTimelineAxis.seconds(
                        forX: value.location.x,
                        durationSeconds: durationSeconds,
                        laneWidth: width,
                        viewport: viewport
                    ))
                case nil:
                    break
                }
            }
            .onEnded { value in
                switch gestureMode {
                case .move(let regionId):
                    if let draftRegion,
                       abs(draftRegion.startSeconds - draftRegion.initial.startSeconds) >= 0.000_1 {
                        onMoveCommitted(regionId, draftRegion.startSeconds)
                    }
                case .trimIn(let regionId), .trimOut(let regionId):
                    if let draftRegion,
                       abs(draftRegion.startSeconds - draftRegion.initial.startSeconds) >= 0.000_1
                        || abs(draftRegion.durationSeconds - draftRegion.initial.durationSeconds) >= 0.000_1 {
                        onTrimCommitted(
                            regionId,
                            draftRegion.startSeconds,
                            draftRegion.sourceStartSeconds,
                            draftRegion.durationSeconds
                        )
                    }
                case .fadeIn(let regionId), .fadeOut(let regionId):
                    if let draftRegion,
                       abs(draftRegion.fadeInSeconds - draftRegion.initial.fadeInSeconds) >= 0.000_1
                        || abs(draftRegion.fadeOutSeconds - draftRegion.initial.fadeOutSeconds) >= 0.000_1 {
                        onFadeCommitted(
                            regionId,
                            draftRegion.fadeInSeconds,
                            draftRegion.fadeOutSeconds
                        )
                    }
                case .seek:
                    onSeek(ShotTimelineAxis.seconds(
                        forX: value.location.x,
                        durationSeconds: durationSeconds,
                        laneWidth: width,
                        viewport: viewport
                    ))
                    onScrubEnded()
                case nil:
                    break
                }
                gestureMode = nil
                draftRegion = nil
                isSnapped = false
                onSnapChanged(false)
                isClampedAtMediaEnd = false
                NSCursor.arrow.set()
            }
    }

    private func beginGesture(at location: CGPoint, width: CGFloat, height: CGFloat) {
        if isInteractionEnabled,
           let hit = regionHit(at: location, width: width, height: height),
           let regionId = hit.region.regionId {
            onSelectRegion(regionId)
            isKeyboardFocused = true
            let isFadeZone = hit.zone == .fadeIn || hit.zone == .fadeOut
            // Fades are LEVEL edits — they play through (the mute precedent);
            // everything else changes what/when plays and pauses first.
            if !isFadeZone { onGestureBegan() }
            draftRegion = DraftRegion(
                regionId: regionId,
                initial: hit.region,
                startSeconds: hit.region.startSeconds,
                sourceStartSeconds: hit.region.sourceStartSeconds,
                durationSeconds: hit.region.durationSeconds,
                fadeInSeconds: hit.region.fadeInSeconds,
                fadeOutSeconds: hit.region.fadeOutSeconds
            )
            switch hit.zone {
            case .body:
                gestureMode = .move(regionId)
                NSCursor.closedHand.set()
            case .inEdge:
                gestureMode = .trimIn(regionId)
                NSCursor.resizeLeftRight.set()
            case .outEdge:
                gestureMode = .trimOut(regionId)
                NSCursor.resizeLeftRight.set()
            case .fadeIn:
                gestureMode = .fadeIn(regionId)
                NSCursor.resizeLeftRight.set()
            case .fadeOut:
                gestureMode = .fadeOut(regionId)
                NSCursor.resizeLeftRight.set()
            }
        } else {
            gestureMode = .seek
            onSelectRegion(nil)
            // Focus deliberately KEPT: a seek is transport, and dropping the
            // keyboard here made transport keys dead after every lane click.
            onScrubBegan()
        }
    }

    private func updateMoveDraft(translation: CGFloat, width: CGFloat) {
        guard var draft = draftRegion else { return }
        let initial = draft.initial
        let translated = initial.startSeconds + ShotTimelineAxis.secondsDelta(
            forPoints: translation,
            durationSeconds: durationSeconds,
            laneWidth: width,
            viewport: viewport
        )
        let quantized = ShotAudioTiming.normalizedStart(translated, timelineDuration: durationSeconds)
        let ownEdges = [initial.startSeconds, initial.endSeconds]
        let targets = [playheadSeconds] + snapTargets.filter { target in
            !ownEdges.contains { abs($0 - target) < 0.000_1 }
        }
        // Head AND tail snap, and the result already wears the commit's
        // `movedTo` clamp — the dropped draft is exactly what persists.
        let snapped = ShotAudioTiming.snappedMoveStart(
            candidateStart: quantized,
            regionDurationSeconds: draft.durationSeconds,
            targets: targets,
            timelineWidth: Double(ShotTimelineAxis.mappedWidth(laneWidth: width, viewport: viewport)),
            timelineDuration: durationSeconds,
            bypass: NSEvent.modifierFlags.contains(.option)
        )
        draft.startSeconds = snapped.seconds
        isSnapped = snapped.snapped
        onSnapChanged(snapped.snapped)
        draftRegion = draft
    }

    private func updateTrimInDraft(translation: CGFloat, width: CGFloat) {
        guard var draft = draftRegion else { return }
        let initial = draft.initial
        let translated = initial.startSeconds + ShotTimelineAxis.secondsDelta(
            forPoints: translation,
            durationSeconds: durationSeconds,
            laneWidth: width,
            viewport: viewport
        )
        var newStart = ShotAudioTiming.frameQuantizedStart(max(translated, 0))
        let snapped = ShotAudioTiming.snappedSeconds(
            candidate: newStart,
            targets: [playheadSeconds, 0],
            timelineWidth: Double(ShotTimelineAxis.mappedWidth(laneWidth: width, viewport: viewport)),
            timelineDuration: durationSeconds,
            bypass: NSEvent.modifierFlags.contains(.option)
        )
        newStart = max(snapped.seconds, 0)
        isSnapped = snapped.snapped
        onSnapChanged(snapped.snapped)
        // The in-edge cannot pass the material head (non-looping regions have
        // no audio before source zero — honest, not silent) nor eat the last
        // frame of the region.
        if !initial.loops {
            newStart = max(
                newStart,
                initial.startSeconds - initial.sourceStartSeconds / initial.playbackRate
            )
        }
        newStart = min(newStart, initial.endSeconds - ShotAudioTiming.frameSeconds)
        draft.startSeconds = newStart
        draft.durationSeconds = initial.endSeconds - newStart
        draft.sourceStartSeconds = initial.loops
            ? initial.sourceStartSeconds
            : initial.sourceStartSeconds
                + (newStart - initial.startSeconds) * initial.playbackRate
        draftRegion = draft
    }

    private func updateTrimOutDraft(translation: CGFloat, width: CGFloat) {
        guard var draft = draftRegion else { return }
        let initial = draft.initial
        let translated = initial.endSeconds + ShotTimelineAxis.secondsDelta(
            forPoints: translation,
            durationSeconds: durationSeconds,
            laneWidth: width,
            viewport: viewport
        )
        var newEnd = ShotAudioTiming.frameQuantizedStart(max(translated, 0))
        let snapped = ShotAudioTiming.snappedSeconds(
            candidate: newEnd,
            targets: [playheadSeconds, durationSeconds],
            timelineWidth: Double(ShotTimelineAxis.mappedWidth(laneWidth: width, viewport: viewport)),
            timelineDuration: durationSeconds,
            bypass: NSEvent.modifierFlags.contains(.option)
        )
        newEnd = snapped.seconds
        isSnapped = snapped.snapped
        onSnapChanged(snapped.snapped)
        newEnd = max(newEnd, initial.startSeconds + ShotAudioTiming.frameSeconds)
        newEnd = min(newEnd, max(durationSeconds, initial.startSeconds + ShotAudioTiming.frameSeconds))
        // Honest MEDIA END clamp: a non-looping region cannot claim audio past
        // its file. LOOP releases the clamp (tiling covers any length).
        isClampedAtMediaEnd = false
        if !initial.loops, let mediaSeconds = initial.sourceDurationSeconds {
            let mediaEnd = initial.startSeconds + max(
                (mediaSeconds - draft.sourceStartSeconds) / initial.playbackRate,
                ShotAudioTiming.frameSeconds
            )
            if newEnd >= mediaEnd - 0.000_1 {
                newEnd = min(newEnd, mediaEnd)
                isClampedAtMediaEnd = true
            }
        }
        draft.durationSeconds = newEnd - draft.startSeconds
        draftRegion = draft
    }

    /// Fade drags are continuous (the drag family — no frame quantization)
    /// and clamp through the model's own law: fade-in never past the region's
    /// end minus its fade-out, and vice versa.
    private func updateFadeInDraft(translation: CGFloat, width: CGFloat) {
        guard var draft = draftRegion else { return }
        let delta = ShotTimelineAxis.secondsDelta(
            forPoints: translation,
            durationSeconds: durationSeconds,
            laneWidth: width,
            viewport: viewport
        )
        let ceiling = max(draft.initial.durationSeconds - draft.fadeOutSeconds, 0)
        draft.fadeInSeconds = min(max(draft.initial.fadeInSeconds + delta, 0), ceiling)
        draftRegion = draft
    }

    private func updateFadeOutDraft(translation: CGFloat, width: CGFloat) {
        guard var draft = draftRegion else { return }
        let delta = ShotTimelineAxis.secondsDelta(
            forPoints: translation,
            durationSeconds: durationSeconds,
            laneWidth: width,
            viewport: viewport
        )
        // The fade-out handle sits at (end − fadeOut): dragging LEFT grows
        // the fade.
        let ceiling = max(draft.initial.durationSeconds - draft.fadeInSeconds, 0)
        draft.fadeOutSeconds = min(max(draft.initial.fadeOutSeconds - delta, 0), ceiling)
        draftRegion = draft
    }

    /// The fade handles' drawn geometry, shared by drawing and hit-testing —
    /// one function, one space (the same-box law). nil when handles are off
    /// for this region (not selected, lane too short, missing file).
    private func fadeHandleCenters(
        _ region: ShotAudioWaveformRegion,
        width: CGFloat,
        height: CGFloat
    ) -> (fadeIn: CGPoint, fadeOut: CGPoint)? {
        guard fadeHandlesEnabled,
              isInteractionEnabled,
              region.regionId != nil,
              region.regionId == selectedRegionId,
              !region.isMissingFile,
              !region.isUnreadableFile else { return nil }
        let y = ShotTimelineAxis.bandVerticalInset + 6
        let fadeInX = ShotTimelineAxis.x(
            forSeconds: region.startSeconds + region.fadeInSeconds,
            durationSeconds: durationSeconds,
            laneWidth: width,
            viewport: viewport
        )
        let fadeOutX = ShotTimelineAxis.x(
            forSeconds: region.endSeconds - region.fadeOutSeconds,
            durationSeconds: durationSeconds,
            laneWidth: width,
            viewport: viewport
        )
        return (CGPoint(x: fadeInX, y: y), CGPoint(x: fadeOutX, y: y))
    }

    private func regionHit(
        at point: CGPoint,
        width: CGFloat,
        height: CGFloat
    ) -> (region: ShotAudioWaveformRegion, zone: RegionHitZone)? {
        guard durationSeconds > 0 else { return nil }
        let window = viewport.window(durationSeconds: durationSeconds)
        let windowEnd = window.start + window.length
        let x = point.x
        // Fade handles first: they ride the band's top edge and would
        // otherwise be shadowed by the trim-edge zones at zero fade.
        for region in displayRegions.reversed() where region.regionId != nil {
            guard let centers = fadeHandleCenters(region, width: width, height: height) else { continue }
            let radius: CGFloat = 7
            if hypot(point.x - centers.fadeIn.x, point.y - centers.fadeIn.y) <= radius {
                return (region, .fadeIn)
            }
            if hypot(point.x - centers.fadeOut.x, point.y - centers.fadeOut.y) <= radius {
                return (region, .fadeOut)
            }
        }
        for region in displayRegions.reversed() where region.regionId != nil {
            if window.length > 0,
               region.endSeconds < window.start || region.startSeconds > windowEnd {
                continue
            }
            let startX = ShotTimelineAxis.x(
                forSeconds: region.startSeconds,
                durationSeconds: durationSeconds,
                laneWidth: width,
                viewport: viewport
            )
            let endX = ShotTimelineAxis.x(
                forSeconds: region.endSeconds,
                durationSeconds: durationSeconds,
                laneWidth: width,
                viewport: viewport
            )
            let effectiveEndX = max(endX, startX + 8)
            guard x >= startX - 2, x <= effectiveEndX + 2 else { continue }
            let edgeZone = min(8, max((effectiveEndX - startX) / 3, 3))
            if x <= startX + edgeZone { return (region, .inEdge) }
            if x >= effectiveEndX - edgeZone { return (region, .outEdge) }
            return (region, .body)
        }
        return nil
    }

    // MARK: Drawing

    /// The Canvas spans the whole lane box (no padding — see `body`), so the
    /// visual inset is arithmetic here: x through `ShotTimelineAxis`, y through
    /// `verticalInset`. Drawing space and hit-test space are therefore the
    /// same space, which is the invariant the old `.padding` broke.
    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        let laneWidth = max(size.width, 1)
        let verticalInset = ShotTimelineAxis.bandVerticalInset
        let top = verticalInset
        let height = max(size.height - verticalInset * 2, 1)
        let total = max(durationSeconds, 0.001)
        // Bars fill the VISIBLE window: under zoom each bar samples a finer
        // slice of output time, which is the whole point of zooming.
        let window = viewport.window(durationSeconds: total)
        let windowStart = window.length > 0 ? window.start : 0
        let windowLength = window.length > 0 ? window.length : total
        let contentWidth = ShotTimelineAxis.contentWidth(laneWidth: laneWidth)
        let contentStart = ShotTimelineAxis.contentInset
        let barCount = max(Int(contentWidth / 3), 24)
        let gap: CGFloat = 1
        let barWidth = max((contentWidth - (CGFloat(barCount - 1) * gap)) / CGFloat(barCount), 1)
        let activeProgress = min(max((playheadSeconds - windowStart) / windowLength, 0), 1)

        func x(_ seconds: Double) -> CGFloat {
            ShotTimelineAxis.x(
                forSeconds: seconds,
                durationSeconds: total,
                laneWidth: laneWidth,
                viewport: viewport
            )
        }

        for region in displayRegions {
            if windowLength > 0,
               region.endSeconds < windowStart || region.startSeconds > windowStart + windowLength {
                continue
            }
            let startX = x(region.startSeconds)
            let endX = x(region.endSeconds)
            let regionWidth = max(endX - startX, 1)
            let rect = CGRect(x: startX, y: top, width: regionWidth, height: height)
            let isSelectedRegion = region.regionId != nil && region.regionId == selectedRegionId

            if region.isMissingFile || region.isUnreadableFile {
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 2),
                    with: .color(CanonColor.rust.opacity(0.06))
                )
                var hatch = Path()
                var hatchX = rect.minX - height
                while hatchX < rect.maxX {
                    hatch.move(to: CGPoint(x: max(hatchX, rect.minX), y: rect.maxY))
                    hatch.addLine(to: CGPoint(x: min(hatchX + height, rect.maxX), y: rect.minY))
                    hatchX += 5
                }
                context.stroke(hatch, with: .color(CanonColor.rust.opacity(0.35)), lineWidth: 0.7)
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 2),
                    with: .color(CanonColor.rust.opacity(isSelectedRegion ? 0.9 : 0.6)),
                    lineWidth: isSelectedRegion ? 1.2 : 0.7
                )
                if regionWidth > 44 {
                    context.draw(
                        Text(region.isMissingFile ? "MISSING" : "OFFLINE")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(CanonColor.rust),
                        at: CGPoint(x: rect.midX, y: rect.midY)
                    )
                }
                continue
            }

            context.fill(
                Path(roundedRect: rect, cornerRadius: 2),
                with: .color(PlateColor.ink.opacity(
                    isSelectedRegion ? 0.10 : (region.isMuted ? 0.02 : 0.045)
                ))
            )
            let strokeColor = isSelectedRegion
                ? CanonColor.brass
                : PlateColor.hairline.opacity(region.isMuted ? 0.55 : 0.75)
            if region.isMuted, !isSelectedRegion {
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 2),
                    with: .color(strokeColor),
                    style: StrokeStyle(lineWidth: 0.6, dash: [3, 2])
                )
            } else {
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: 2),
                    with: .color(strokeColor),
                    lineWidth: isSelectedRegion ? 1.2 : 0.6
                )
            }

            // Loop tile separators: one hairline per natural repeat, plus the
            // repeat glyph — the drawing IS the playback plan.
            if region.loops, let chunk = region.sourceDurationSeconds, chunk > 0.01 {
                let phase = region.loopPhaseSeconds.truncatingRemainder(dividingBy: chunk)
                let rate = max(region.playbackRate, ShotAudioRegion.playbackRateRange.lowerBound)
                var tick = region.startSeconds + (chunk - phase) / rate
                var separators = Path()
                while tick < region.endSeconds - 0.01 {
                    let tickX = x(tick)
                    separators.move(to: CGPoint(x: tickX, y: rect.minY + 2))
                    separators.addLine(to: CGPoint(x: tickX, y: rect.maxY - 2))
                    tick += chunk / rate
                }
                context.stroke(
                    separators,
                    with: .color(PlateColor.hairline.opacity(0.5)),
                    lineWidth: 0.6
                )
                if regionWidth > 26 {
                    context.draw(
                        Text(Image(systemName: "repeat"))
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(isSelectedRegion ? CanonColor.brass : PlateColor.inkFaint),
                        at: CGPoint(x: rect.maxX - 8, y: rect.minY + 5)
                    )
                }
            }

            // Extension headroom: a selected non-looping region trimmed short
            // of its media shows how far it can honestly extend.
            if isSelectedRegion, !region.loops, let mediaSeconds = region.sourceDurationSeconds {
                let headroomEnd = region.startSeconds
                    + max(mediaSeconds - region.sourceStartSeconds, 0) / region.playbackRate
                if headroomEnd > region.endSeconds + 0.05 {
                    let headroomX = x(headroomEnd)
                    if headroomX > endX + 2 {
                        var headroom = Path()
                        headroom.move(to: CGPoint(x: endX + 1, y: rect.midY))
                        headroom.addLine(to: CGPoint(x: headroomX, y: rect.midY))
                        context.stroke(
                            headroom,
                            with: .color(CanonColor.brass.opacity(0.45)),
                            style: StrokeStyle(lineWidth: 0.8, dash: [2, 2.5])
                        )
                        var terminal = Path()
                        terminal.move(to: CGPoint(x: headroomX, y: rect.minY + 6))
                        terminal.addLine(to: CGPoint(x: headroomX, y: rect.maxY - 6))
                        context.stroke(terminal, with: .color(CanonColor.brass.opacity(0.45)), lineWidth: 0.8)
                    }
                }
            }

            // Fade wedges at ALL lane sizes: the drawn envelope IS the
            // playback plan — a straight ramp from silence at the edge to
            // full level at the fade boundary.
            if region.fadeInSeconds > 0.000_1 {
                let fadeX = min(x(region.startSeconds + region.fadeInSeconds), rect.maxX)
                if fadeX > rect.minX + 0.5 {
                    var wedge = Path()
                    wedge.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                    wedge.addLine(to: CGPoint(x: fadeX, y: rect.minY))
                    wedge.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                    wedge.closeSubpath()
                    context.fill(wedge, with: .color(PlateColor.ink.opacity(0.07)))
                    var ramp = Path()
                    ramp.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                    ramp.addLine(to: CGPoint(x: fadeX, y: rect.minY))
                    context.stroke(
                        ramp,
                        with: .color(isSelectedRegion
                            ? CanonColor.brass.opacity(0.8)
                            : PlateColor.inkFaint.opacity(0.6)),
                        lineWidth: 0.9
                    )
                }
            }
            if region.fadeOutSeconds > 0.000_1 {
                let fadeX = max(x(region.endSeconds - region.fadeOutSeconds), rect.minX)
                if fadeX < rect.maxX - 0.5 {
                    var wedge = Path()
                    wedge.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    wedge.addLine(to: CGPoint(x: fadeX, y: rect.minY))
                    wedge.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                    wedge.closeSubpath()
                    context.fill(wedge, with: .color(PlateColor.ink.opacity(0.07)))
                    var ramp = Path()
                    ramp.move(to: CGPoint(x: fadeX, y: rect.minY))
                    ramp.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    context.stroke(
                        ramp,
                        with: .color(isSelectedRegion
                            ? CanonColor.brass.opacity(0.8)
                            : PlateColor.inkFaint.opacity(0.6)),
                        lineWidth: 0.9
                    )
                }
            }
            // Fade HANDLES only where they hit-test (selected region, editor-
            // height lanes) — drawn and hit in the same space by sharing
            // `fadeHandleCenters`.
            if let centers = fadeHandleCenters(region, width: laneWidth, height: size.height) {
                for center in [centers.fadeIn, centers.fadeOut] {
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)),
                        with: .color(CanonColor.brass)
                    )
                    context.fill(
                        Path(ellipseIn: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)),
                        with: .color(PlateColor.cream)
                    )
                }
            }

            if isSelectedRegion, regionWidth >= 24 {
                for handleX in [startX + 1.5, endX - 5.5] {
                    let handleRect = CGRect(x: handleX, y: top + 2, width: 4, height: height - 4)
                    context.fill(
                        Path(roundedRect: handleRect, cornerRadius: 1.5),
                        with: .color(CanonColor.brass)
                    )
                    context.fill(
                        Path(CGRect(x: handleRect.midX - 0.5, y: top + 6, width: 1, height: height - 12)),
                        with: .color(PlateColor.cream.opacity(0.85))
                    )
                }
            }

            // Marks t=END, not the plate's edge — which is what it always meant.
            if region.endSeconds > total + 0.000_1 {
                let indicator = CGRect(
                    x: max(laneWidth - contentStart - 4, 0),
                    y: top + 1,
                    width: 4,
                    height: max(height - 2, 1)
                )
                context.fill(Path(indicator), with: .color(CanonColor.brass.opacity(0.62)))
            }
        }

        for index in 0..<barCount {
            let outputSeconds = windowStart + (Double(index) + 0.5) / Double(barCount) * windowLength
            let sampled = sample(at: outputSeconds, fallbackIndex: index)
            let visible = max(sampled.value, 0.035)
            let barHeight = max(CGFloat(visible) * height, 1)
            let barX = contentStart + CGFloat(index) * (barWidth + gap)
            let rect = CGRect(
                x: barX,
                y: top + (height - barHeight) / 2,
                width: barWidth,
                height: barHeight
            )
            let midpoint = (Double(index) + 0.5) / Double(barCount)
            var color = midpoint <= activeProgress
                ? CanonColor.brass.opacity(0.78)
                : PlateColor.ink.opacity(0.20)
            if sampled.isMuted {
                color = color.opacity(0.35)
            }
            context.fill(Path(roundedRect: rect, cornerRadius: 0.8), with: .color(color))
        }
        // A selected SOURCE envelope wears the selection's brass over the
        // bands — stroke and wash only, deliberately no edge handles, because
        // handles promise a trim and envelope geometry is authored at combine
        // time, not draggable here.
        if let envelopeHighlight {
            let startX = x(envelopeHighlight.start)
            let endX = x(envelopeHighlight.end)
            let rect = CGRect(x: startX, y: top, width: max(endX - startX, 2), height: height)
            context.fill(
                Path(roundedRect: rect, cornerRadius: 2),
                with: .color(CanonColor.brass.opacity(0.08))
            )
            context.stroke(
                Path(roundedRect: rect, cornerRadius: 2),
                with: .color(CanonColor.brass),
                lineWidth: 1.2
            )
        }
        // The playhead is NOT drawn here: one continuous line spanning the
        // ruler and every lane is drawn once by the stack, so it can't break
        // at row gaps or drift between lanes.
    }

    private func sample(at outputSeconds: Double, fallbackIndex: Int) -> (value: Double, isMuted: Bool) {
        guard let region = displayRegions.last(where: {
            outputSeconds >= $0.startSeconds && outputSeconds <= $0.endSeconds
        }) else {
            return (0, false)
        }
        guard case .ready(let waveform) = loader.state(path: region.path),
              !waveform.samples.isEmpty else {
            return (fallbackIndex.isMultiple(of: 3) ? 0.14 : 0.07, region.isMuted)
        }
        let local = max(outputSeconds - region.startSeconds, 0)
        let sourceSeconds: Double
        if region.loops {
            // Draw the same internal phase the composition builder plays.
            let period = max(region.sourceDurationSeconds ?? waveform.durationSeconds, 0.001)
            sourceSeconds = (region.loopPhaseSeconds + local * region.playbackRate)
                .truncatingRemainder(dividingBy: period)
        } else if region.regionId != nil {
            sourceSeconds = region.sourceStartSeconds + local * region.playbackRate
        } else {
            sourceSeconds = sourceTime(localOutputSeconds: local, ranges: region.sourceRanges)
        }
        let ratio = min(max(sourceSeconds / max(waveform.durationSeconds, 0.001), 0), 0.999_999)
        return (
            waveform.samples[min(Int(ratio * Double(waveform.samples.count)), waveform.samples.count - 1)],
            region.isMuted
        )
    }

    private func sourceTime(localOutputSeconds: Double, ranges: [ShotKeepRange]) -> Double {
        guard !ranges.isEmpty else { return localOutputSeconds }
        var remaining = localOutputSeconds
        for range in ranges {
            if remaining <= range.seconds { return range.start + remaining }
            remaining -= range.seconds
        }
        return ranges.last?.end ?? localOutputSeconds
    }

    private func timingLabelX(seconds: Double, width: CGFloat) -> CGFloat {
        let x = ShotTimelineAxis.x(
            forSeconds: seconds,
            durationSeconds: durationSeconds,
            laneWidth: width,
            viewport: viewport
        )
        let inset = ShotTimelineAxis.contentInset
        return min(max(x + 28, inset + 30), max(width - inset - 30, inset + 30))
    }
}

/// One lane's fixed-width track header. Slot widths come from
/// `ShotAudioLaneHeadLayout` and sum to `ShotTimelineAxis.headWidth`, so the
/// time area next to it always begins at the same x.
struct ShotAudioLaneHeadView<ChipMenu: View>: View {
    let head: ShotAudioLaneHead
    var onToggleMute: () -> Void
    var onToggleRecord: () -> Void
    var onChipPrimaryAction: (() -> Void)? = nil
    @ViewBuilder var chipMenu: () -> ChipMenu

    private var chipColor: Color {
        switch head.chip.tone {
        case .ink: return PlateColor.ink
        case .faint: return PlateColor.inkFaint
        case .brass: return CanonColor.brass
        case .rust: return CanonColor.rust
        }
    }

    private var chipLabel: some View {
        PlateLabel(text: head.chip.text, size: 6.5, weight: .semibold, color: chipColor)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: 58, alignment: .leading)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background(
                Capsule().fill(
                    head.chip.isActionable
                        ? PlateColor.creamDeep
                        : PlateColor.creamDeep.opacity(0.4)
                )
            )
            .overlay(
                Capsule().stroke(
                    head.chip.isActionable
                        ? PlateColor.hairline
                        : PlateColor.hairline.opacity(0.4),
                    lineWidth: 0.7
                )
            )
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggleMute) {
                Image(systemName: head.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(head.isEnabled ? PlateColor.ink : PlateColor.inkFaint)
                    .frame(width: ShotAudioLaneHeadLayout.muteWidth, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(head.isEnabled ? "Mute the \(head.name) lane" : "Enable the \(head.name) lane")

            Spacer().frame(width: ShotAudioLaneHeadLayout.muteGap)

            VStack(alignment: .leading, spacing: 2) {
                PlateLabel(
                    text: head.name,
                    size: 7.5,
                    weight: .semibold,
                    color: head.isAvailable ? PlateColor.ink : PlateColor.inkFaint
                )
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: ShotAudioLaneHeadLayout.identityWidth, alignment: .leading)
                .help(head.name)

                Group {
                    if let onChipPrimaryAction {
                        Button(action: onChipPrimaryAction) {
                            chipLabel
                        }
                        .buttonStyle(.plain)
                    } else {
                        Menu {
                            chipMenu()
                        } label: {
                            chipLabel
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    }
                }
                .frame(width: ShotAudioLaneHeadLayout.identityWidth, alignment: .leading)
                .disabled(!head.chip.isActionable)
                .help(head.chip.help)
            }

            Spacer().frame(width: ShotAudioLaneHeadLayout.identityGap)

            Group {
                if let level = head.inputLevel {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(PlateColor.ink.opacity(0.09))
                        .frame(width: 3, height: 18)
                        .overlay(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(level > 0.88 ? Color.red : CanonColor.brass)
                                .frame(height: 18 * min(max(level, 0), 1))
                        }
                        .help("Microphone input level")
                } else {
                    Color.clear
                }
            }
            .frame(width: ShotAudioLaneHeadLayout.meterWidth)

            Spacer().frame(width: ShotAudioLaneHeadLayout.meterGap)

            Group {
                switch head.action {
                case .none:
                    if onChipPrimaryAction != nil {
                        Menu {
                            chipMenu()
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(PlateColor.inkFaint)
                                .frame(
                                    width: ShotAudioLaneHeadLayout.actionWidth,
                                    height: ShotAudioLaneHeadLayout.actionWidth
                                )
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .help("Narration audio options")
                    } else {
                        Color.clear
                    }
                case .record(let isActive, let isBusy):
                    Button(action: onToggleRecord) {
                        Image(systemName: isActive ? "stop.circle.fill" : "record.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isActive ? Color.red.opacity(0.84) : PlateColor.inkFaint)
                            .frame(
                                width: ShotAudioLaneHeadLayout.actionWidth,
                                height: ShotAudioLaneHeadLayout.actionWidth
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isBusy)
                    .help(isActive
                        ? "Stop and keep this microphone take"
                        : "Record from the current playhead after a 3-second count-in")
                }
            }
            .frame(width: ShotAudioLaneHeadLayout.actionWidth)
        }
        .frame(width: ShotTimelineAxis.headWidth, alignment: .leading)
        .background(head.ownsSelection ? PlateColor.creamDeep.opacity(0.28) : Color.clear)
        .overlay(alignment: .leading) {
            // Pairs with the identical mark on the inspector plate, on the
            // same vertical line, so the attachment survives a selected lane
            // sitting four rows above its editor.
            if head.ownsSelection {
                RoundedRectangle(cornerRadius: 1)
                    .fill(CanonColor.brass)
                    .frame(width: 2, height: 18)
                    .offset(x: -6)
            }
        }
    }
}

/// The five audio lanes of the CUT player. EVERY cut is region-based here:
/// persisted regions when they exist, otherwise the deterministic regionize
/// preview (`legacyAudioRegionPreview`) — a first committed edit persists
/// exactly the previewed ids, so gestures behave identically before and after
/// migration. Selection drives an inline inspector directly under the owning
/// lane; all edits land as single undoable engine transactions.
struct ShotAudioLaneStack: View {
    let shot: ProjectShot
    let assembly: ShotCutAssembly
    let legacySourcePath: String?
    let durationSeconds: Double
    let playheadSeconds: Double
    let inputDevices: [CameraDeviceOption]
    let selectedInputDeviceId: String
    let monitorPlayback: Bool
    let microphoneLevel: Double
    let microphoneControlMode: ShotMicrophoneControlMode
    /// False under an active Look or with no assembled bands: the source lane
    /// then shows one plain band instead of cut-space spans that would
    /// mis-scale against the Look's own duration.
    var pictureReferenceIsValid: Bool = true
    /// THE PROJECTION GHOST: the OUTPUT projection of a picture-edit drag in
    /// flight on the material strip above (nil = no drag). Drawn as a brass
    /// re-projected line through ruler and lanes — the honest cross-seam
    /// readout while the operator trims or razors against the audio.
    var dragGhostOutputSeconds: Double? = nil
    var dragGhostIsSnapped: Bool = false
    var ambientBeds: [AmbientBedRecord] = []
    /// Audio files imported into the project, offered on every media lane,
    /// including Ambient where they loop by default.
    var audioClips: [MediaItemRecord] = []
    var regionActions: ShotAudioRegionActions = ShotAudioRegionActions()
    var onOpenNarration: () -> Void = {}
    /// Opens the tuner sheet; the argument is the bed to load (nil = new bed).
    var onOpenAmbientTuner: (String?) -> Void = { _ in }
    var onSeek: (Double) -> Void
    var onSelectInputDevice: (String) -> Void
    var onSetMonitorPlayback: (Bool) -> Void
    var onDeleteTake: (String) -> Void
    var onToggleMicrophoneRecording: () -> Void
    /// Pauses playback before a manipulation lands.
    ///
    /// THE PAUSE LAW: edits that change WHAT or WHEN audio plays call this
    /// first (moves, trims, splits, loop toggles, deletes, take swaps); edits
    /// that only change HOW LOUD it plays (mute toggles, gain and volume
    /// sliders) play through, so levels can be auditioned against running
    /// picture.
    var onGestureBegan: () -> Void = { }
    /// THE SCRUB LATCH: seeks pause on begin and resume on release iff
    /// playback was running (edits use `onGestureBegan` and stay paused).
    var onScrubBegan: () -> Void = { }
    var onScrubEnded: () -> Void = { }
    /// THE PLAYHEAD TRUTH LAW: `playheadSeconds` is a 10Hz display
    /// approximation; a COMMIT that reads "the playhead" resolves the
    /// player's exact clock through this closure at the commit instant.
    /// nil (previews, hosts without a player) falls back to the display.
    var resolvePlayheadSeconds: (() -> Double)? = nil
    /// The ruler head's typed playhead jump; nil keeps a static readout.
    var onJumpToPlayhead: ((Double) -> Void)? = nil
    /// Opens the sound editor sheet, carrying the selected region's output
    /// span (nil = no selection) so the editor can open framed on it.
    /// Selection is the stack's private state, so the range rides the open
    /// closure instead of hoisting selection to the host. nil hides the
    /// ruler-tail expand button (FinalsReel, and the editor's own stack).
    var onOpenSoundEditor: ((ClosedRange<Double>?) -> Void)? = nil

    @Environment(\.undoManager) private var undoManager
    @Environment(\.shotTimelineMetrics) private var metrics
    @StateObject private var regionUndo = ShotAudioRegionUndoCoordinator()
    @StateObject private var readabilityProbe = ShotAudioReadabilityProbe()
    @State private var pendingDeleteTake: ShotMicrophoneTake?
    @State private var selectedRegionId: String?
    /// A picture SEGMENT is not a region — it has no id in `audioRegions` and
    /// must never reach a region engine op — so it selects on its own state.
    /// The two are mutually exclusive; `select…` clears the other.
    @State private var selectedSourceSegmentKey: String?
    @State private var draftGain: Double?
    @State private var draftSegmentGain: Double?
    /// One lane's in-flight volume drag: drafting locally and committing on
    /// editing-end makes a drag one document write and one Undo action,
    /// matching region gain (the old binding wrote per intermediate value).
    @State private var laneVolumeDraft: LaneVolumeDraft?
    /// Bumped by `selectRegion` so the lane holding the fresh selection takes
    /// keyboard focus, wherever the selection was granted.
    @State private var selectionFocusToken = 0
    @State private var showSpeedPopover = false
    @State private var speedDraft: Double = 1
    @State private var speedEntryText = "1.00"
    @State private var pitchModeDraft: ShotAudioPitchMode = .preserve
    /// Snap feedback travels here from whichever lane is dragging, because the
    /// playhead is drawn once for the whole stack.
    @State private var isPlayheadSnapped = false

    private struct LaneVolumeDraft: Equatable {
        var laneId: String
        var volume: Double
    }

    /// The frame the operator is actually ON, for commits (truth law above).
    private func resolvedPlayheadSeconds() -> Double {
        ShotAudioTiming.frameQuantizedStart(resolvePlayheadSeconds?() ?? playheadSeconds)
    }

    // MARK: The selection law

    /// THE SELECTION LAW: a region and a SOURCE span are never selected
    /// together. Every grant of region selection routes here — gesture,
    /// chip menu, media picker, and edit side-effects alike — so the span
    /// always clears and keyboard focus follows the selection to its lane.
    private func selectRegion(_ regionId: String?) {
        selectedRegionId = regionId
        selectedSourceSegmentKey = nil
        if regionId != nil { selectionFocusToken += 1 }
    }

    // MARK: Effective regions (the unification law)

    private var attachedAmbientRecord: AmbientBedRecord? {
        guard let bedId = shot.audioMix.lane(ShotAudioLaneId.ambient).ambientBedId else { return nil }
        return ambientBeds.first { $0.bedId == bedId }
    }

    private var attachedAudioClip: MediaItemRecord? {
        guard let mediaId = shot.audioMix.lane(ShotAudioLaneId.clip).clipMediaId else { return nil }
        return audioClips.first { $0.mediaId == mediaId }
    }

    /// Persisted regions win; otherwise the deterministic preview stands in.
    /// The first committed edit regionizes with EXACTLY these ids.
    private var effectiveAudioRegions: [ShotAudioRegion] {
        if !shot.audioRegions.isEmpty { return shot.audioRegions }
        return shot.legacyAudioRegionPreview(
            timelineSeconds: durationSeconds,
            ambientBedDurationSeconds: attachedAmbientRecord?.durationSeconds,
            clipMediaDurationSeconds: attachedAudioClip?.durationSeconds
        )
    }

    private var selectedRegion: ShotAudioRegion? {
        guard let selectedRegionId else { return nil }
        return effectiveAudioRegions.first { $0.regionId == selectedRegionId }
    }

    private func laneRegions(_ laneId: String) -> [ShotAudioRegion] {
        effectiveAudioRegions
            .filter { $0.laneId == laneId }
            .sorted {
                $0.startSeconds == $1.startSeconds
                    ? $0.regionId < $1.regionId
                    : $0.startSeconds < $1.startSeconds
            }
    }

    private func laneWaveformRegions(_ laneId: String) -> [ShotAudioWaveformRegion] {
        laneRegions(laneId)
            .filter { !$0.path.isEmpty }
            .map { region in
                let fileOnDisk = FileManager.default.fileExists(atPath: region.path)
                return ShotAudioWaveformRegion(
                    id: region.regionId,
                    path: region.path,
                    startSeconds: region.startSeconds,
                    durationSeconds: region.durationSeconds,
                    sourceRanges: region.loops ? [] : [ShotKeepRange(
                        start: region.sourceStartSeconds,
                        end: region.sourceStartSeconds + region.durationSeconds * region.playbackRate
                    )],
                    regionId: region.regionId,
                    loops: region.loops,
                    sourceStartSeconds: region.sourceStartSeconds,
                    loopPhaseSeconds: region.loopPhaseSeconds,
                    playbackRate: region.playbackRate,
                    sourceDurationSeconds: region.sourceDurationSeconds,
                    isMissingFile: !fileOnDisk,
                    isUnreadableFile: fileOnDisk && readabilityProbe.couldNotRead(path: region.path),
                    isMuted: region.isMuted,
                    fadeInSeconds: region.fadeInSeconds,
                    fadeOutSeconds: region.fadeOutSeconds
                )
            }
    }

    /// Source audio is the composition's own tracks — bands from the cut
    /// assembly, never directly draggable.
    ///
    /// Derived from `playbackItems`, NOT from `planClips.outputStartSeconds`:
    /// that cursor advances only over keep ranges, so with a generated bridge
    /// in the shot every later band drew early against a duration that does
    /// include the bridge. A bridge item carries no source audio, so it draws
    /// as a silent band rather than sampling a waveform it does not have.
    private var sourceWaveformRegions: [ShotAudioWaveformRegion] {
        if pictureReferenceIsValid, !assembly.playbackItems.isEmpty {
            let muted = mutedSourceSegmentKeys
            return assembly.playbackItems.map { item in
                ShotAudioWaveformRegion(
                    id: item.itemId,
                    path: item.isBridge ? "" : item.url.path,
                    startSeconds: item.outputStartSeconds,
                    durationSeconds: item.durationSeconds,
                    sourceRanges: item.keepRange.map { [$0] } ?? [],
                    // The tab is the switch; the BAND is the meter. Lighting the
                    // existing dashed-and-dimmed muted drawing across the whole
                    // span states the mute at any band width, including ones too
                    // narrow to carry a tab at all.
                    isMuted: muted.contains(item.segmentKey)
                )
            }
        }
        guard let legacySourcePath, !legacySourcePath.isEmpty else { return [] }
        return [ShotAudioWaveformRegion(
            id: "source_legacy",
            path: legacySourcePath,
            startSeconds: 0,
            durationSeconds: durationSeconds
        )]
    }

    // MARK: Per-segment SOURCE intent

    private var sourceSegmentIntent: [String: ShotSourceSegmentAudio] {
        Dictionary(
            shot.sourceSegmentAudio.map { ($0.segmentKey, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    /// Every segment that carries a control tab — the picture reference reads
    /// this to move its ordinal out from under one.
    private var controlledSourceSegmentKeys: Set<String> {
        guard pictureReferenceIsValid else { return [] }
        return Set(
            assembly.outputPictureSegments
                .filter { !$0.isBridge && !$0.segmentKey.isEmpty }
                .map(\.segmentKey)
        )
    }

    private var mutedSourceSegmentKeys: Set<String> {
        Set(shot.sourceSegmentAudio.filter(\.isMuted).map(\.segmentKey))
    }

    private var attenuatedSourceSegmentKeys: Set<String> {
        Set(shot.sourceSegmentAudio.filter { !$0.isMuted && $0.gain < 1 }.map(\.segmentKey))
    }

    /// The picture spans described as head input. Purely for display — these
    /// carry synthetic ids and never leave `laneHead`, because the source lane
    /// has no editable regions to key engine ops on.
    private var sourceSpanDescriptors: [ShotAudioRegion] {
        guard pictureReferenceIsValid else { return [] }
        let intent = sourceSegmentIntent
        return assembly.outputPictureSegments
            .filter { !$0.isBridge && !$0.segmentKey.isEmpty }
            .map { segment in
                let row = intent[segment.segmentKey]
                return ShotAudioRegion(
                    regionId: Self.sourceSpanDescriptorId(segment.segmentKey),
                    laneId: ShotAudioLaneId.source,
                    label: "SPAN \(segment.ordinal)",
                    startSeconds: segment.outputStartSeconds,
                    durationSeconds: segment.outputSeconds,
                    gain: row?.gain ?? 1,
                    isMuted: row?.isMuted ?? false
                )
            }
    }

    private static func sourceSpanDescriptorId(_ segmentKey: String) -> String {
        "source_span:\(segmentKey)"
    }

    private func selectSourceSegment(_ segmentKey: String?) {
        selectedSourceSegmentKey = segmentKey
        if segmentKey != nil { selectedRegionId = nil }
        draftSegmentGain = nil
    }

    /// Clicking anywhere on the SOURCE lane seeks AND selects the span under
    /// the click. Reusing the seek that already happens means no new gesture,
    /// no new hit-testing, and no risk to the overlay's no-background rule.
    private func selectSourceSegment(atOutputSeconds seconds: Double) {
        let hit = assembly.outputPictureSegments.first {
            !$0.isBridge && !$0.segmentKey.isEmpty
                && seconds >= $0.outputStartSeconds && seconds < $0.outputEndSeconds
        }
        selectSourceSegment(hit?.segmentKey)
    }

    private var selectedSourceSegment: ShotOutputPictureSegment? {
        guard let selectedSourceSegmentKey else { return nil }
        return assembly.outputPictureSegments.first {
            $0.segmentKey == selectedSourceSegmentKey && !$0.isBridge
        }
    }

    private func toggleSourceSegmentMute(_ segmentKey: String) {
        // No pause — a mute is a level edit and plays through (the pause law).
        let existing = sourceSegmentIntent[segmentKey]
        commitSourceSegment(
            segmentKey: segmentKey,
            gain: existing?.gain ?? 1,
            isMuted: !(existing?.isMuted ?? false),
            actionName: (existing?.isMuted ?? false) ? "Unmute Segment Audio" : "Mute Segment Audio"
        )
    }

    private func commitSourceSegment(
        segmentKey: String,
        gain: Double,
        isMuted: Bool,
        actionName: String
    ) {
        guard let oldRows = regionActions.setSourceSegment(segmentKey, gain, isMuted) else { return }
        registerSourceUndo(
            old: ShotSourceDetachSnapshot(
                sourceSegmentAudio: oldRows,
                audioRegions: shot.audioRegions
            ),
            actionName: actionName
        )
    }

    private func detachSourceSegment(_ segmentKey: String) {
        onGestureBegan()
        guard let old = regionActions.detachSourceSegment(segmentKey) else { return }
        registerSourceUndo(old: old, actionName: "Detach Segment Audio")
    }

    /// The engine publishes synchronously, so reading current state right after
    /// the commit gives a true old/new pair for one undo action.
    private func registerSourceUndo(old: ShotSourceDetachSnapshot, actionName: String) {
        regionUndo.registerSourceEdit(
            old: old,
            new: regionActions.currentSourceState(),
            actionName: actionName,
            undoManager: undoManager
        )
    }

    /// One `FileManager` pass per render, so the pure head resolver never
    /// touches the disk.
    private var missingRegionIds: Set<String> {
        Set(
            effectiveAudioRegions
                .filter { !$0.path.isEmpty && !FileManager.default.fileExists(atPath: $0.path) }
                .map(\.regionId)
        )
    }

    /// Regions whose file is ON disk but whose audio could not be read — the
    /// cloud-placeholder case. Keyed off the waveform loader's probe (the
    /// only component that actually opens the file), so this costs no extra
    /// I/O beyond the `fileExists` pass above.
    private var offlineRegionIds: Set<String> {
        Set(
            effectiveAudioRegions
                .filter {
                    !$0.path.isEmpty
                        && FileManager.default.fileExists(atPath: $0.path)
                        && readabilityProbe.couldNotRead(path: $0.path)
                }
                .map(\.regionId)
        )
    }

    /// The selected SOURCE envelope's output span, for the lane's brass
    /// extent indicator. nil unless the selection is a source-lane region.
    private var selectedSourceEnvelopeRange: ShotKeepRange? {
        guard let selectedRegion, selectedRegion.laneId == ShotAudioLaneId.source else { return nil }
        return ShotKeepRange(start: selectedRegion.startSeconds, end: selectedRegion.endSeconds)
    }

    private func laneHead(laneId: String) -> ShotAudioLaneHead {
        let lane = shot.audioMix.lane(laneId)
        let regions = laneRegions(laneId)
        let takes = shot.audioMix.lane(ShotAudioLaneId.microphone).microphoneTakes
        let empty: String
        let unit: String
        var hasPickerTargets = false
        // Keyed on KIND — a second CLIP row must read NO CLIP, not NO SOURCE.
        switch ShotAudioLaneId.kind(ofLaneId: laneId) {
        case ShotAudioLaneId.clip:
            empty = "NO CLIP"; unit = "CLIP"; hasPickerTargets = true
        case ShotAudioLaneId.ambient:
            empty = "NO AMBIENCE"; unit = "SOUND"; hasPickerTargets = true
        case ShotAudioLaneId.narration:
            empty = "NO NARRATION"; unit = "NARRATION"; hasPickerTargets = true
        case ShotAudioLaneId.microphone:
            empty = "NO TAKES"; unit = "TAKE"; hasPickerTargets = !takes.isEmpty
        default:
            empty = "NO SOURCE"; unit = "SPAN"
        }
        let isSource = laneId == ShotAudioLaneId.source
        return shotAudioLaneHead(
            laneId: laneId,
            laneLabel: lane.label,
            isEnabled: lane.isEnabled,
            laneVolume: lane.volume,
            // The source lane's "regions" are its picture SPANS. Passing [] here
            // was a lie that left SOURCE reading NO SOURCE and permanently
            // faint on every rendered cut.
            regions: isSource ? sourceSpanDescriptors : regions,
            missingRegionIds: missingRegionIds,
            offlineRegionIds: offlineRegionIds,
            emptyText: empty,
            unit: unit,
            hasPickerTargets: hasPickerTargets,
            // For SOURCE, `regions` are its ENVELOPE regions, so an authored
            // section mute or level also turns the chip brass.
            hasOperatorAttenuation: regions.contains { $0.isMuted || $0.gain < 1 }
                || (isSource
                    && !(mutedSourceSegmentKeys.isEmpty && attenuatedSourceSegmentKeys.isEmpty)),
            // Takes and the record affordance belong to the BASE mic row:
            // `commitShotMicrophoneTake` targets `microphone`, so an extra mic
            // row that offered Record would lie about where the take lands.
            takeSummary: laneId == ShotAudioLaneId.microphone
                ? (takes.isEmpty
                    ? "NO TAKES"
                    : "TAKE \((takes.firstIndex { $0.takeId == lane.activeMicrophoneTake?.takeId } ?? 0) + 1)/\(takes.count)")
                : nil,
            microphoneMode: laneId == ShotAudioLaneId.microphone ? microphoneControlMode : nil,
            microphoneLevel: laneId == ShotAudioLaneId.microphone ? microphoneLevel : nil,
            selectedRegionId: isSource
                ? selectedSourceSegmentKey.map { Self.sourceSpanDescriptorId($0) }
                : selectedRegionId,
            sourceEnvelopeCount: isSource ? regions.count : 0,
            ownsEnvelopeSelection: isSource && selectedSourceEnvelopeRange != nil
        )
    }

    private func snapTargets(_ laneId: String) -> [Double] {
        var targets: [Double] = [0, durationSeconds]
        for region in laneRegions(laneId) {
            targets.append(region.startSeconds)
            targets.append(region.endSeconds)
        }
        return targets
    }

    /// Keyed on KIND, so `clip_2` accepts the same drops `clip` does.
    private func laneAcceptsDrops(_ laneId: String) -> Bool {
        [
            ShotAudioLaneId.clip,
            ShotAudioLaneId.narration,
            ShotAudioLaneId.microphone,
            ShotAudioLaneId.ambient
        ]
            .contains(ShotAudioLaneId.kind(ofLaneId: laneId))
    }

    /// The rows this stack draws, in order. Derived, never stored — see
    /// `shotAudioLaneRows`.
    private var laneRows: [String] {
        shotAudioLaneRows(mix: shot.audioMix, regions: effectiveAudioRegions)
    }

    /// LAW: the stack's child count never depends on `selectedRegionId`. The
    /// inspector is an unconditional slot at the bottom, so selecting a region
    /// can never shift a lane — the old inline emission moved every lane below
    /// it by 32pt, including mid-drag on a lane above.
    var body: some View {
        VStack(spacing: metrics.rowSpacing) {
            ShotTimelineRulerRow(
                durationSeconds: durationSeconds,
                playheadSeconds: playheadSeconds,
                onSeek: onSeek,
                onScrubBegan: onScrubBegan,
                onScrubEnded: onScrubEnded,
                onJump: onJumpToPlayhead,
                onOpenEditor: onOpenSoundEditor.map { open in
                    { open(selectedRegion.map { $0.startSeconds...$0.endSeconds }) }
                }
            )
            ForEach(laneRows, id: \.self) { laneId in
                laneRow(laneId)
            }
            inspectorSlot
        }
        .task(id: effectiveAudioRegions.map(\.path).sorted().joined(separator: "|")) {
            readabilityProbe.probe(paths: effectiveAudioRegions.map(\.path))
        }
        .overlay(alignment: .topLeading) {
            ShotTimelinePlayheadOverlay(
                durationSeconds: durationSeconds,
                playheadSeconds: playheadSeconds,
                isSnapped: isPlayheadSnapped,
                // The real row count, not the canonical five: with an extra
                // CLIP row the playhead would otherwise stop one row short.
                laneCount: laneRows.count
            )
        }
        .overlay(alignment: .topLeading) {
            if let dragGhostOutputSeconds {
                ShotTimelineDragGhostOverlay(
                    durationSeconds: durationSeconds,
                    outputSeconds: dragGhostOutputSeconds,
                    isSnapped: dragGhostIsSnapped,
                    laneCount: laneRows.count
                )
            }
        }
        .background(
            // ⌘D duplicate (no Edit-menu equivalent to route through). The
            // zoomShortcutButtons precedent: hidden, zero-size, gated by the
            // handler itself.
            Button("") { duplicateSelected() }
                .keyboardShortcut("d", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        )
        .onAppear {
            regionUndo.applyRegion = { region in regionActions.restore(region) }
            regionUndo.deleteRegion = { regionId in _ = regionActions.delete(regionId) }
            regionUndo.applyAudioState = { state in regionActions.restoreState(state) }
            regionUndo.applySourceState = { state in regionActions.restoreSourceDetach(state) }
        }
        .onDisappear {
            undoManager?.removeAllActions(withTarget: regionUndo)
            regionUndo.applyRegion = nil
            regionUndo.deleteRegion = nil
            regionUndo.applyAudioState = nil
            regionUndo.applySourceState = nil
        }
        .task(id: shot.shotId) {
            await regionActions.backfillDurations()
        }
        .onChange(of: selectedRegionId) { _, _ in
            draftGain = nil
            showSpeedPopover = false
        }
        .onChange(of: selectedSourceSegmentKey) { _, _ in
            draftSegmentGain = nil
        }
        .onChange(of: shot.shotId) { _, _ in
            // Selection is per-shot state; carrying it across shots would pin
            // the inspector to a region the operator never chose here.
            selectedRegionId = nil
            selectedSourceSegmentKey = nil
        }
        .onChange(of: shot.audioRegions) { _, _ in
            // An undone add or split vanishes its region id; a stale selection
            // would hold the head's brass mark on a ghost.
            if let selectedRegionId,
               !effectiveAudioRegions.contains(where: { $0.regionId == selectedRegionId }) {
                self.selectedRegionId = nil
            }
        }
        .confirmationDialog(
            "Move this microphone take to Trash?",
            isPresented: Binding(
                get: { pendingDeleteTake != nil },
                set: { if !$0 { pendingDeleteTake = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move Take to Trash", role: .destructive) {
                if let take = pendingDeleteTake { onDeleteTake(take.takeId) }
                pendingDeleteTake = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteTake = nil }
        } message: {
            Text("Other takes remain available, and the newest remaining take becomes active.")
        }
    }

    /// One row, resolved by KIND. The row list is data (`laneRows`), so an
    /// extra CLIP row is not a special case anywhere below this point.
    @ViewBuilder
    private func laneRow(_ laneId: String) -> some View {
        switch ShotAudioLaneId.kind(ofLaneId: laneId) {
        case ShotAudioLaneId.source:
            audioLane(
                laneId: laneId,
                regions: sourceWaveformRegions,
                isAvailable: !sourceWaveformRegions.isEmpty
            ) {
                sourceSpanSelectionSection
                sourceEnvelopeSelectionSection
            }
        case ShotAudioLaneId.narration:
            audioLane(
                laneId: laneId,
                regions: laneWaveformRegions(laneId),
                isAvailable: !laneRegions(laneId).isEmpty,
                chipPrimaryAction: onOpenNarration
            ) {
                narrationChipMenu(laneId)
            }
        case ShotAudioLaneId.microphone:
            audioLane(
                laneId: laneId,
                regions: laneWaveformRegions(laneId),
                // The mic row is always available: with the strip replaced in
                // Look mode its header is the only recording affordance.
                isAvailable: true
            ) {
                microphoneChipMenu(laneId)
            }
        case ShotAudioLaneId.ambient:
            audioLane(
                laneId: laneId,
                regions: laneWaveformRegions(laneId),
                isAvailable: !laneRegions(laneId).isEmpty
            ) {
                ambientChipMenu(laneId)
            }
        default:
            audioLane(
                laneId: laneId,
                regions: laneWaveformRegions(laneId),
                isAvailable: !laneRegions(laneId).isEmpty
            ) {
                clipChipMenu(laneId)
            }
        }
    }

    /// `[head 132][time area][tail 92]` — the shared axis row shape. Every
    /// lane's time area therefore begins and ends at the same absolute x, and
    /// no lane can widen its own header (the head takes a value-typed
    /// descriptor with fixed slots, never an erased accessory view).
    private func audioLane<ChipMenu: View>(
        laneId: String,
        regions: [ShotAudioWaveformRegion],
        isAvailable: Bool,
        chipPrimaryAction: (() -> Void)? = nil,
        @ViewBuilder chipMenu: @escaping () -> ChipMenu
    ) -> some View {
        let lane = shot.audioMix.lane(laneId)
        let isSource = laneId == ShotAudioLaneId.source
        return HStack(spacing: 0) {
            ShotAudioLaneHeadView(
                head: laneHead(laneId: laneId),
                onToggleMute: { commitLaneEnabled(laneId, enabled: !lane.isEnabled) },
                onToggleRecord: onToggleMicrophoneRecording,
                onChipPrimaryAction: chipPrimaryAction,
                chipMenu: chipMenu
            )
            .frame(width: ShotTimelineAxis.headWidth, alignment: .leading)

            ShotTimelineWaveformView(
                regions: regions,
                durationSeconds: durationSeconds,
                playheadSeconds: playheadSeconds,
                isEnabled: lane.isEnabled && (isAvailable || laneId == ShotAudioLaneId.microphone),
                isInteractionEnabled: microphoneControlMode == .idle && laneId != ShotAudioLaneId.source,
                selectedRegionId: selectedRegionId,
                snapTargets: snapTargets(laneId),
                acceptsAudioDrop: laneAcceptsDrops(laneId),
                envelopeHighlight: isSource ? selectedSourceEnvelopeRange : nil,
                selectionFocusToken: selectionFocusToken,
                onSeek: { seconds in
                    if isSource { selectSourceSegment(atOutputSeconds: seconds) }
                    onSeek(seconds)
                },
                onSelectRegion: { selectRegion($0) },
                onGestureBegan: onGestureBegan,
                onScrubBegan: onScrubBegan,
                onScrubEnded: onScrubEnded,
                onMoveCommitted: { regionId, startSeconds in
                    commitMove(regionId: regionId, startSeconds: startSeconds)
                },
                onTrimCommitted: { regionId, start, sourceStart, duration in
                    commitGeometry(
                        regionId: regionId,
                        startSeconds: start,
                        sourceStartSeconds: sourceStart,
                        durationSeconds: duration
                    )
                },
                onFadeCommitted: { regionId, fadeIn, fadeOut in
                    commitFades(regionId: regionId, fadeInSeconds: fadeIn, fadeOutSeconds: fadeOut)
                },
                onCopySelected: { copySelectedProviders() },
                onCutSelected: { cutSelectedProviders() },
                onPaste: { pasteFromClipboard(preferredLaneId: laneId) },
                onNudgeSelected: { frames in nudgeSelected(by: frames) },
                onTrimSelectedToPlayhead: { isIn in trimSelectedToPlayhead(inEdge: isIn) },
                onToggleLoopSelected: { toggleSelectedLoop() },
                onToggleMuteSelected: { toggleSelectedMute() },
                onSplitSelected: { splitSelectedAtPlayhead() },
                onDeleteSelected: { deleteSelectedRegion() },
                onAudioDrop: { payload, seconds in
                    handleDrop(laneId: laneId, payload: payload, seconds: seconds)
                },
                onSnapChanged: { isPlayheadSnapped = $0 }
            )
            .overlay {
                // Applied OUTSIDE the lane's own enabled-opacity, so muting
                // source AUDIO never fades the picture REFERENCE.
                if isSource, pictureReferenceIsValid {
                    ShotSourcePictureOverlay(
                        segments: assembly.outputPictureSegments,
                        splices: assembly.outputSplices,
                        durationSeconds: durationSeconds,
                        controlledSegmentKeys: controlledSourceSegmentKeys,
                        laneHeight: metrics.laneHeight
                    )
                }
            }
            .overlay {
                // A SEPARATE, higher overlay — see the type's own comment for
                // why it must never gain a background.
                if isSource, pictureReferenceIsValid {
                    ShotSourceSegmentAudioOverlay(
                        segments: assembly.outputPictureSegments,
                        durationSeconds: durationSeconds,
                        mutedSegmentKeys: mutedSourceSegmentKeys,
                        attenuatedSegmentKeys: attenuatedSourceSegmentKeys,
                        laneHeight: metrics.laneHeight,
                        onToggleMute: { toggleSourceSegmentMute($0) },
                        onDetach: { detachSourceSegment($0) }
                    )
                    // While recording, `.opacity` + `.allowsHitTesting(false)`
                    // rather than `.disabled`: a disabled Button still SWALLOWS
                    // clicks, which would kill seek on the source lane for the
                    // whole take.
                    .opacity(microphoneControlMode == .idle ? 1 : 0.35)
                    .allowsHitTesting(microphoneControlMode == .idle)
                }
            }

            laneTail(lane: lane, laneId: laneId)
        }
        .frame(height: metrics.laneHeight)
    }

    /// Level lives at the right rail on every row — lane volume here, region
    /// gain directly beneath it in the inspector, at the same x. The slider
    /// drafts locally and commits once on editing-end (matching region gain),
    /// so one drag is one document write and one Undo action.
    private func laneTail(lane: ShotAudioLane, laneId: String) -> some View {
        let displayedVolume = laneVolumeDraft?.laneId == laneId
            ? (laneVolumeDraft?.volume ?? lane.volume)
            : lane.volume
        return HStack(spacing: 4) {
            Image(systemName: "speaker.wave.1")
                .font(.system(size: 9))
                .foregroundStyle(PlateColor.inkFaint)
                .frame(width: 12)
            Slider(
                value: Binding(
                    get: { displayedVolume },
                    set: { laneVolumeDraft = LaneVolumeDraft(laneId: laneId, volume: $0) }
                ),
                in: 0...1
            ) { editing in
                // No pause — a level edit auditions against running picture.
                if !editing, let draft = laneVolumeDraft, draft.laneId == laneId {
                    commitLaneVolume(laneId, volume: draft.volume)
                    laneVolumeDraft = nil
                }
            }
            .controlSize(.mini)
            .frame(width: 74)
            .help("\(lane.label) volume: \(Int(displayedVolume * 100))%")
        }
        .frame(width: ShotTimelineAxis.tailWidth, alignment: .trailing)
    }

    // MARK: Committed edits (one engine transaction + one undo action each)

    private func registerUndoAfterEdit(old: ShotAudioRegion?, regionId: String, actionName: String) {
        guard let old, let new = regionActions.currentRegion(regionId) else { return }
        regionUndo.registerEdit(old: old, new: new, actionName: actionName, undoManager: undoManager)
    }

    private func commitMove(regionId: String, startSeconds: Double) {
        let old = regionActions.move(regionId, startSeconds)
        registerUndoAfterEdit(old: old, regionId: regionId, actionName: "Move Audio Region")
        if old != nil { selectRegion(regionId) }
    }

    private func commitGeometry(
        regionId: String,
        startSeconds: Double,
        sourceStartSeconds: Double,
        durationSeconds: Double
    ) {
        let old = regionActions.setGeometry(regionId, startSeconds, sourceStartSeconds, durationSeconds)
        registerUndoAfterEdit(old: old, regionId: regionId, actionName: "Trim Audio Region")
        if old != nil { selectRegion(regionId) }
    }

    private func commitLoops(regionId: String, loops: Bool) {
        let old = regionActions.setLoops(regionId, loops)
        registerUndoAfterEdit(old: old, regionId: regionId, actionName: loops ? "Loop Audio Region" : "Unloop Audio Region")
    }

    private func commitReplace(regionId: String, asset: ShotAudioAssetReference) {
        let old = regionActions.replaceMedia(regionId, asset)
        registerUndoAfterEdit(old: old, regionId: regionId, actionName: "Replace Audio Media")
    }

    private func commitUpdate(_ region: ShotAudioRegion, actionName: String) {
        let old = regionActions.update(region)
        registerUndoAfterEdit(old: old, regionId: region.regionId, actionName: actionName)
    }

    /// One committed fade drag or field entry = one engine write + one undo
    /// action. No pause — fades are level edits (the mute precedent).
    private func commitFades(regionId: String, fadeInSeconds: Double, fadeOutSeconds: Double) {
        guard let region = regionActions.currentRegion(regionId) else { return }
        let updated = region.settingFades(fadeInSeconds: fadeInSeconds, fadeOutSeconds: fadeOutSeconds)
        guard updated != region else { return }
        commitUpdate(updated, actionName: "Adjust Audio Fades")
    }

    // MARK: Clipboard (copy / cut / paste / duplicate)

    /// SOURCE envelopes are picture-locked and never travel — detach is the
    /// honest path to movable source audio, so copy answers empty for them.
    private func clipboardPayload(for region: ShotAudioRegion) -> ShotAudioRegionClipboardPayload? {
        guard region.laneId != ShotAudioLaneId.source else { return nil }
        return ShotAudioRegionClipboardPayload(region: region, sourceShotId: shot.shotId)
    }

    private func copySelectedProviders() -> [NSItemProvider] {
        guard let region = selectedRegion,
              let payload = clipboardPayload(for: region) else { return [] }
        return ShotAudioClipboard.itemProviders(for: payload)
    }

    /// Cut = copy + delete in one gesture; the providers hand SwiftUI the
    /// pasteboard write, the delete registers as its own named undo action.
    private func cutSelectedProviders() -> [NSItemProvider] {
        guard let region = selectedRegion,
              let payload = clipboardPayload(for: region) else { return [] }
        let providers = ShotAudioClipboard.itemProviders(for: payload)
        guard !providers.isEmpty else { return [] }
        commitCutDelete(region)
        return providers
    }

    private func commitCutDelete(_ region: ShotAudioRegion) {
        onGestureBegan()
        guard let deleted = regionActions.delete(region.regionId) else { return }
        regionUndo.registerDelete(deleted, actionName: "Cut Audio Region", undoManager: undoManager)
        if selectedRegionId == region.regionId { selectedRegionId = nil }
    }

    /// The inspector buttons' direct pasteboard write (buttons can't hand
    /// SwiftUI providers the way the Edit-menu commands do).
    private func copySelectedToClipboard() {
        guard let region = selectedRegion,
              let payload = clipboardPayload(for: region) else { return }
        ShotAudioClipboard.write(payload)
    }

    private func cutSelectedToClipboard() {
        guard let region = selectedRegion,
              let payload = clipboardPayload(for: region) else { return }
        ShotAudioClipboard.write(payload)
        commitCutDelete(region)
    }

    /// Paste lands at the frame-quantized playhead (the split precedent —
    /// playhead ops quantize, drags don't) on the focused lane when it is
    /// kind-compatible; the engine's three-rung law resolves the rest.
    private func pasteFromClipboard(preferredLaneId: String?) {
        guard let payload = ShotAudioClipboard.read() else { return }
        onGestureBegan()
        guard let edit = regionActions.paste(payload, preferredLaneId, resolvedPlayheadSeconds()) else { return }
        regionUndo.registerStateEdit(
            old: edit.before,
            new: edit.after,
            actionName: "Paste Audio",
            undoManager: undoManager
        )
        if let added = edit.affectedRegion { selectRegion(added.regionId) }
    }

    private func duplicateSelected() {
        guard let region = selectedRegion, region.laneId != ShotAudioLaneId.source else { return }
        onGestureBegan()
        guard let edit = regionActions.duplicate(region.regionId) else { return }
        regionUndo.registerStateEdit(
            old: edit.before,
            new: edit.after,
            actionName: "Duplicate Audio Region",
            undoManager: undoManager
        )
        if let added = edit.affectedRegion { selectRegion(added.regionId) }
    }

    private func commitAdd(
        laneId: String,
        asset: ShotAudioAssetReference,
        startSeconds: Double
    ) -> ShotAudioRegion? {
        guard let edit = regionActions.add(laneId, asset, startSeconds),
              let added = edit.affectedRegion else { return nil }
        regionUndo.registerStateEdit(
            old: edit.before,
            new: edit.after,
            actionName: "Add Audio",
            undoManager: undoManager
        )
        selectRegion(added.regionId)
        return added
    }

    private func commitAddTrack(
        kind: String,
        asset: ShotAudioAssetReference,
        startSeconds: Double
    ) -> ShotAudioRegion? {
        guard let edit = regionActions.addTrack(kind, asset, startSeconds),
              let added = edit.affectedRegion else { return nil }
        regionUndo.registerStateEdit(
            old: edit.before,
            new: edit.after,
            actionName: "Add Audio Track",
            undoManager: undoManager
        )
        selectRegion(added.regionId)
        return added
    }

    private func commitMakeAudible(regionId: String) {
        guard let edit = regionActions.makeAudible(regionId) else { return }
        regionUndo.registerStateEdit(
            old: edit.before,
            new: edit.after,
            actionName: "Make Audio Audible",
            undoManager: undoManager
        )
        selectRegion(regionId)
    }

    private func commitSplit(regionId: String, atSeconds: Double) {
        guard let edit = regionActions.split(regionId, atSeconds),
              let right = edit.affectedRegion else { return }
        regionUndo.registerStateEdit(
            old: edit.before,
            new: edit.after,
            actionName: "Split Audio Region",
            undoManager: undoManager
        )
        selectRegion(right.regionId)
    }

    /// The one split law behind the inspector's SPLIT button and the S key:
    /// frame-quantized playhead, at least one frame on each side, never the
    /// picture-locked source lane. Pauses first — a split changes WHEN audio
    /// plays (the pause law).
    private func splitSelectedAtPlayhead() {
        guard let region = selectedRegion, region.laneId != ShotAudioLaneId.source else { return }
        let splitSeconds = resolvedPlayheadSeconds()
        guard splitSeconds - region.startSeconds >= ShotAudioTiming.frameSeconds,
              region.endSeconds - splitSeconds >= ShotAudioTiming.frameSeconds else { return }
        onGestureBegan()
        commitSplit(regionId: region.regionId, atSeconds: splitSeconds)
    }

    private func commitDelete(regionId: String) {
        guard let deleted = regionActions.delete(regionId) else { return }
        regionUndo.registerDelete(deleted, undoManager: undoManager)
        if selectedRegionId == regionId { selectedRegionId = nil }
    }

    /// The picker's remove-all-placements of one asset: one engine
    /// transaction, one Undo step.
    private func commitDeleteMany(regionIds: [String]) {
        onGestureBegan()
        guard let edit = regionActions.deleteMany(regionIds) else { return }
        regionUndo.registerStateEdit(
            old: edit.before,
            new: edit.after,
            actionName: "Remove Audio",
            undoManager: undoManager
        )
        if let selectedRegionId, regionIds.contains(selectedRegionId) {
            self.selectedRegionId = nil
        }
    }

    /// One multi-asset placement = one engine transaction = one Undo step.
    /// Returns the next placement cursor: the last added region's end for
    /// end-to-end kinds, the original drop point for AMBIENT (which layers).
    @discardableResult
    private func commitAddBatch(
        laneId: String,
        assets: [ShotAudioAssetReference],
        startSeconds: Double
    ) -> Double {
        guard !assets.isEmpty,
              let edit = regionActions.addBatch(laneId, assets, startSeconds) else {
            return startSeconds
        }
        regionUndo.registerStateEdit(
            old: edit.before,
            new: edit.after,
            actionName: assets.count == 1 ? "Add Audio" : "Add Audio Files",
            undoManager: undoManager
        )
        if let added = edit.affectedRegion { selectRegion(added.regionId) }
        if ShotAudioLaneId.kind(ofLaneId: laneId) == ShotAudioLaneId.ambient {
            return startSeconds
        }
        let beforeIds = Set(edit.before.audioRegions.map(\.regionId))
        return edit.after.audioRegions
            .filter { !beforeIds.contains($0.regionId) }
            .map(\.endSeconds)
            .max() ?? startSeconds
    }

    private func commitLaneEnabled(_ laneId: String, enabled: Bool) {
        // No pause — the header mute is a level edit and plays through.
        guard let edit = regionActions.setLaneEnabled(laneId, enabled) else { return }
        regionUndo.registerStateEdit(
            old: edit.before,
            new: edit.after,
            actionName: enabled ? "Unmute Lane" : "Mute Lane",
            undoManager: undoManager
        )
    }

    private func commitLaneVolume(_ laneId: String, volume: Double) {
        guard let edit = regionActions.setLaneVolume(laneId, volume) else { return }
        regionUndo.registerStateEdit(
            old: edit.before,
            new: edit.after,
            actionName: "Adjust Lane Volume",
            undoManager: undoManager
        )
    }

    private func commitActivateTake(_ takeId: String) {
        // Pauses: activation swaps WHICH take plays (the pause law).
        onGestureBegan()
        guard let edit = regionActions.activateTake(takeId) else { return }
        regionUndo.registerStateEdit(
            old: edit.before,
            new: edit.after,
            actionName: "Activate Microphone Take",
            undoManager: undoManager
        )
    }

    private func commitAddLane(kind: String) {
        guard let edit = regionActions.addLane(kind) else { return }
        regionUndo.registerStateEdit(
            old: edit.before,
            new: edit.after,
            actionName: "Add Audio Row",
            undoManager: undoManager
        )
    }

    private func commitRemoveLane(laneId: String) {
        guard let edit = regionActions.removeLane(laneId) else { return }
        regionUndo.registerStateEdit(
            old: edit.before,
            new: edit.after,
            actionName: "Remove Audio Row",
            undoManager: undoManager
        )
    }

    private func deleteSelectedRegion() {
        guard let selectedRegion, selectedRegion.laneId != ShotAudioLaneId.source else { return }
        commitDelete(regionId: selectedRegion.regionId)
    }

    private func nudgeSelected(by frames: Int) {
        guard let selectedRegion, selectedRegion.laneId != ShotAudioLaneId.source else { return }
        let moved = ShotAudioTiming.nudgedStart(
            selectedRegion.startSeconds,
            frames: frames,
            timelineDuration: durationSeconds
        )
        commitMove(regionId: selectedRegion.regionId, startSeconds: moved)
    }

    private func trimSelectedToPlayhead(inEdge: Bool) {
        guard let region = selectedRegion, region.laneId != ShotAudioLaneId.source else { return }
        let playhead = resolvedPlayheadSeconds()
        if inEdge {
            guard playhead < region.endSeconds - ShotAudioTiming.frameSeconds / 2 else { return }
            let delta = playhead - region.startSeconds
            commitGeometry(
                regionId: region.regionId,
                startSeconds: playhead,
                sourceStartSeconds: region.loops
                    ? region.sourceStartSeconds
                    : region.sourceStartSeconds + delta * region.playbackRate,
                durationSeconds: region.durationSeconds - delta
            )
        } else {
            guard playhead > region.startSeconds + ShotAudioTiming.frameSeconds / 2 else { return }
            commitGeometry(
                regionId: region.regionId,
                startSeconds: region.startSeconds,
                sourceStartSeconds: region.sourceStartSeconds,
                durationSeconds: playhead - region.startSeconds
            )
        }
    }

    private func toggleSelectedLoop() {
        guard let selectedRegion, selectedRegion.laneId != ShotAudioLaneId.source else { return }
        commitLoops(regionId: selectedRegion.regionId, loops: !selectedRegion.loops)
    }

    private func toggleSelectedMute() {
        guard let selectedRegion else { return }
        var updated = selectedRegion
        updated.isMuted.toggle()
        commitUpdate(updated, actionName: updated.isMuted ? "Mute Audio Region" : "Unmute Audio Region")
    }

    // MARK: Drops & import

    private func handleDrop(laneId: String, payload: ShotAudioLaneDropPayload, seconds: Double) {
        // Each batch is ONE engine transaction and one Undo step; library
        // items land first, then imported files continue from their cursor.
        let cursor = commitAddBatch(
            laneId: laneId,
            assets: payload.mediaIds.map { .projectAudio(mediaId: $0) },
            startSeconds: seconds
        )
        let audioURLs = payload.fileURLs.filter { url in
            UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true
        }
        guard !audioURLs.isEmpty else { return }
        Task {
            let items = await regionActions.importAudioFiles(audioURLs)
            commitAddBatch(
                laneId: laneId,
                assets: items.map { .projectAudio(mediaId: $0.mediaId) },
                startSeconds: cursor
            )
        }
    }

    private func presentAudioImportPanel(laneId: String) {
        let panel = NSOpenPanel()
        panel.title = "Import Audio"
        panel.message = "Choose audio files to import and place on the \(ShotAudioLane.canonical(laneId).label) lane."
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        let start = resolvedPlayheadSeconds()
        Task {
            let items = await regionActions.importAudioFiles(urls)
            commitAddBatch(
                laneId: laneId,
                assets: items.map { .projectAudio(mediaId: $0.mediaId) },
                startSeconds: start
            )
        }
    }

    private func presentAudioTrackImportPanel(kind: String) {
        let panel = NSOpenPanel()
        panel.title = "Add Audio Track"
        panel.message = "Choose audio files. Each file gets its own independently mixed row at the playhead."
        panel.prompt = "Add Tracks"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio]
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        let start = resolvedPlayheadSeconds()
        Task {
            let items = await regionActions.importAudioFiles(urls)
            for item in items {
                _ = commitAddTrack(
                    kind: kind,
                    asset: .projectAudio(mediaId: item.mediaId),
                    startSeconds: start
                )
            }
        }
    }

    // MARK: Reserved inspector slot

    /// Unconditional: an always-present row is what guarantees selecting a
    /// region can never move a lane. The empty state teaches the affordance
    /// rather than leaving a blank reservation.
    @ViewBuilder
    private var inspectorSlot: some View {
        if let selectedRegion {
            audioRegionInspector(selectedRegion)
        } else if let selectedSourceSegment {
            sourceSegmentInspector(selectedSourceSegment)
        } else {
            HStack(spacing: 0) {
                PlateLabel(text: "No selection", size: 6.5, color: PlateColor.inkFaint)
                    .padding(.leading, ShotAudioLaneHeadLayout.muteWidth + ShotAudioLaneHeadLayout.muteGap - 6)
                    .frame(width: ShotTimelineAxis.headWidth, alignment: .leading)
                PlateLabel(
                    text: "Select a region — or a SOURCE span — to edit its level, mute, or media",
                    size: 7,
                    color: PlateColor.inkFaint
                )
                Spacer(minLength: 0)
            }
            .frame(height: metrics.inspectorHeight)
            .padding(.horizontal, 6)
            .background(PlateColor.creamDeep.opacity(0.24))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    /// The per-segment SOURCE inspector. Same three columns as the region
    /// inspector — identity in the head, actions in the axis column, level in
    /// the tail directly beneath the lane volume — because a segment's level
    /// must read as the same kind of thing as a region's.
    ///
    /// It carries no START/IN/OUT: a segment's geometry belongs to the picture
    /// and is edited on the strip, not here. DETACH is the honest way to get
    /// audio that CAN be moved.
    private func sourceSegmentInspector(_ segment: ShotOutputPictureSegment) -> some View {
        let key = segment.segmentKey
        let intent = sourceSegmentIntent[key]
        let isMuted = intent?.isMuted ?? false
        let gain = draftSegmentGain ?? intent?.gain ?? 1
        let isRecording = microphoneControlMode.isActive
        return HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                PlateLabel(
                    text: "SOURCE · \(segment.isFootage ? "FOOTAGE" : "GENERATED")",
                    size: 6.5,
                    weight: .bold,
                    color: PlateColor.inkFaint
                )
                .lineLimit(1)
                PlateLabel(
                    text: "SPAN \(segment.ordinal)",
                    size: 7.5,
                    weight: .semibold,
                    color: PlateColor.ink
                )
                .lineLimit(1)
            }
            .padding(.leading, ShotAudioLaneHeadLayout.muteWidth + ShotAudioLaneHeadLayout.muteGap - 6)
            .frame(width: ShotTimelineAxis.headWidth - 7, alignment: .leading)

            if isRecording {
                PlateLabel(text: "RECORDING — EDITS PAUSED", size: 6.5, weight: .bold, color: CanonColor.rust)
            }

            PlateLabel(
                text: "\(ShotAudioTiming.timecode(segment.outputStartSeconds)) → \(ShotAudioTiming.timecode(segment.outputEndSeconds))",
                size: 6.5,
                weight: .bold,
                color: PlateColor.inkFaint
            )
            .help("This span's place in the output. Picture timing is edited on the strip above.")

            Button {
                toggleSourceSegmentMute(key)
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .help(isMuted
                ? "Unmute this span's own audio"
                : "Mute this span's own audio — the other spans are untouched")

            Button {
                detachSourceSegment(key)
            } label: {
                PlateLabel(text: "DETACH TO CLIP", size: 6.5, weight: .bold, color: PlateColor.inkFaint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(PlateColor.creamDeep))
                    .overlay(Capsule().stroke(PlateColor.hairline, lineWidth: 0.7))
            }
            .help("Lifts this span's audio onto the Clip lane as an editable region and mutes it here, so it can be moved, trimmed, and re-levelled. Converts this CUT to multi-region audio — reversible only with ⌘Z.")

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.1")
                    .font(.system(size: 9))
                    .foregroundStyle(PlateColor.inkFaint)
                    .frame(width: 12)
                Slider(
                    value: Binding(
                        get: { draftSegmentGain ?? intent?.gain ?? 1 },
                        set: { draftSegmentGain = $0 }
                    ),
                    in: 0...1
                ) { editing in
                    // No pause — a level edit auditions against running
                    // picture (the pause law).
                    if !editing, let committed = draftSegmentGain {
                        commitSourceSegment(
                            segmentKey: key,
                            gain: committed,
                            isMuted: isMuted,
                            actionName: "Adjust Segment Level"
                        )
                        draftSegmentGain = nil
                    }
                }
                .controlSize(.mini)
                .frame(width: 74)
                .help("Span level: \(Int(gain * 100))%")
            }
            .frame(width: ShotTimelineAxis.tailWidth, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .font(.system(size: 9, weight: .semibold))
        .disabled(isRecording)
        .frame(height: metrics.inspectorHeight)
        .padding(.horizontal, 6)
        .background(PlateColor.creamDeep.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .leading) {
            // The same brass mark the region inspector wears, so a selected
            // span reads as the same kind of selection.
            RoundedRectangle(cornerRadius: 1)
                .fill(CanonColor.brass)
                .frame(width: 2, height: 18)
                .offset(x: -6)
        }
    }

    private func provenanceTag(_ region: ShotAudioRegion) -> String {
        switch region.provenance {
        case "detached_source_audio": return "DETACHED"
        case "combined_source": return "SRC"
        case "active_narration": return "NARRATION"
        case "active_microphone_take", "microphone_take": return "MIC TAKE"
        case "imported_microphone_audio", "imported_narration_audio": return "IMPORTED"
        case "ambient_bed", "operator_ambient_bed": return "BED"
        case "operator_ambient_audio": return "AMBIENCE"
        case "operator_replaced_media": return "REPLACED"
        default: return "CLIP"
        }
    }

    /// Three columns on the shared gutters: identity in the head (mirroring
    /// the lane header, so it reads as "the header of the selected region"),
    /// editing controls in the axis column, level in the tail directly beneath
    /// each lane's volume.
    ///
    /// The axis column is NOT time-mapped: its fields sit in reading order,
    /// not at their timecode positions. Nothing here should ever be aligned to
    /// the ruler.
    private func audioRegionInspector(_ region: ShotAudioRegion) -> some View {
        let isSource = region.laneId == ShotAudioLaneId.source
        let laneKind = ShotAudioLaneId.kind(ofLaneId: region.laneId)
        let isMissing = !isSource && !region.path.isEmpty
            && !FileManager.default.fileExists(atPath: region.path)
        let isOffline = !isSource && !isMissing && !region.path.isEmpty
            && readabilityProbe.couldNotRead(path: region.path)
        let lane = shot.audioMix.lane(region.laneId)
        let laneName = lane.label.uppercased()
        let isSilentByControls = !isSource && (
            !lane.isEnabled
                || lane.volume <= 0.000_1
                || region.isMuted
                || region.gain <= 0.000_1
        )
        let isRecording = microphoneControlMode.isActive
        let splitSeconds = ShotAudioTiming.frameQuantizedStart(playheadSeconds)
        let canSplit = !isSource
            && splitSeconds - region.startSeconds >= ShotAudioTiming.frameSeconds
            && region.endSeconds - splitSeconds >= ShotAudioTiming.frameSeconds
        return HStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 1) {
                PlateLabel(
                    text: "\(laneName) · \(provenanceTag(region))",
                    size: 6.5,
                    weight: .bold,
                    color: (isMissing || isOffline) ? CanonColor.rust : PlateColor.inkFaint
                )
                .lineLimit(1)
                PlateLabel(
                    text: (region.label.trimmed.nilIfEmpty ?? "Region").uppercased(),
                    size: 7.5,
                    weight: .semibold,
                    color: PlateColor.ink
                )
                .lineLimit(1)
                .truncationMode(.middle)
            }
            // Indented to sit under the lane NAMES, not under their mute
            // buttons, so the head gutter reads as one column.
            .padding(.leading, ShotAudioLaneHeadLayout.muteWidth + ShotAudioLaneHeadLayout.muteGap - 6)
            .frame(width: ShotTimelineAxis.headWidth - 7, alignment: .leading)
            .help(region.label)

            if isMissing {
                PlateLabel(text: "MISSING FILE", size: 6.5, weight: .bold, color: CanonColor.rust)
                    .help("The audio file is gone. REPLACE points this region at other media — timing, gain, and loop survive.")
            }
            if isOffline {
                PlateLabel(text: "FILE OFFLINE", size: 6.5, weight: .bold, color: CanonColor.rust)
                    .help("The file exists but its audio can't be read — likely offline in cloud storage. Reveal it in Finder to download it; playback picks it up when the player reopens.")
            }
            if isSilentByControls, !isMissing, !isOffline {
                PlateLabel(text: "SILENT", size: 6.5, weight: .bold, color: CanonColor.rust)
                Button {
                    commitMakeAudible(regionId: region.regionId)
                } label: {
                    PlateLabel(text: "MAKE AUDIBLE", size: 6.5, weight: .bold, color: CanonColor.rust)
                }
                .help("Enable this lane, unmute this region, and restore only zero levels. Timing and media stay unchanged.")
            }
            if isRecording {
                PlateLabel(text: "RECORDING — EDITS PAUSED", size: 6.5, weight: .bold, color: CanonColor.rust)
            }

            if isSource {
                // A combined-cut ENVELOPE: authored per-section gain over the
                // picture's own audio. Geometry is fixed at combine time —
                // only its level and mute are editable here.
                PlateLabel(
                    text: "\(ShotAudioTiming.timecode(region.startSeconds)) → \(ShotAudioTiming.timecode(region.endSeconds))",
                    size: 6.5,
                    weight: .bold,
                    color: PlateColor.inkFaint
                )
                .help("This envelope's span of the output. Source audio is picture-locked — only its level and mute are editable.")
            }

            if !isSource {
                ShotTimecodeField(
                    label: "START",
                    seconds: region.startSeconds,
                    isEnabled: true
                ) { parsed in
                    onGestureBegan()
                    commitMove(regionId: region.regionId, startSeconds: max(parsed, 0))
                }
                ShotTimecodeField(
                    label: "IN",
                    seconds: region.sourceStartSeconds,
                    isEnabled: !region.loops,
                    disabledHelp: "IN is fixed while the region loops — loops tile from the file start"
                ) { parsed in
                    onGestureBegan()
                    commitGeometry(
                        regionId: region.regionId,
                        startSeconds: region.startSeconds,
                        sourceStartSeconds: max(parsed, 0),
                        durationSeconds: region.durationSeconds
                    )
                }
                ShotTimecodeField(
                    label: "OUT",
                    seconds: region.endSeconds,
                    isEnabled: true
                ) { parsed in
                    onGestureBegan()
                    commitGeometry(
                        regionId: region.regionId,
                        startSeconds: region.startSeconds,
                        sourceStartSeconds: region.sourceStartSeconds,
                        durationSeconds: max(parsed - region.startSeconds, ShotAudioTiming.frameSeconds)
                    )
                }
                // No pause on fade edits — level edits play through.
                ShotTimecodeField(
                    label: "FADE IN",
                    seconds: region.fadeInSeconds,
                    isEnabled: true
                ) { parsed in
                    commitFades(
                        regionId: region.regionId,
                        fadeInSeconds: max(parsed, 0),
                        fadeOutSeconds: region.fadeOutSeconds
                    )
                }
                ShotTimecodeField(
                    label: "FADE OUT",
                    seconds: region.fadeOutSeconds,
                    isEnabled: true
                ) { parsed in
                    commitFades(
                        regionId: region.regionId,
                        fadeInSeconds: region.fadeInSeconds,
                        fadeOutSeconds: max(parsed, 0)
                    )
                }

                Button {
                    splitSelectedAtPlayhead()
                } label: {
                    PlateLabel(text: "SPLIT", size: 6.5, weight: .bold, color: PlateColor.inkFaint)
                }
                .disabled(!canSplit)
                .help(canSplit
                    ? "Split this region at the playhead (S). The right half stays selected; ⌘Z rejoins it."
                    : "Move the playhead inside this region to split it.")

                Button {
                    copySelectedToClipboard()
                } label: {
                    PlateLabel(text: "COPY", size: 6.5, weight: .bold, color: PlateColor.inkFaint)
                }
                .help("Copy this region (⌘C). Paste lands at the playhead — in this shot or another.")
                Button {
                    cutSelectedToClipboard()
                } label: {
                    PlateLabel(text: "CUT", size: 6.5, weight: .bold, color: PlateColor.inkFaint)
                }
                .help("Cut this region to the clipboard (⌘X). ⌘Z restores it in place.")
                Button {
                    pasteFromClipboard(preferredLaneId: region.laneId)
                } label: {
                    PlateLabel(text: "PASTE", size: 6.5, weight: .bold, color: PlateColor.inkFaint)
                }
                .help("Paste the copied region at the playhead (⌘V), preferring this row when the kinds match.")
                Button {
                    duplicateSelected()
                } label: {
                    PlateLabel(text: "DUPLICATE", size: 6.5, weight: .bold, color: PlateColor.inkFaint)
                }
                .help("Duplicate this region butt-joined at its end (⌘D).")

                Button {
                    onGestureBegan()
                    nudgeSelected(by: NSEvent.modifierFlags.contains(.shift) ? -10 : -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Move one frame earlier (Shift: 10)")
                Button {
                    onGestureBegan()
                    nudgeSelected(by: NSEvent.modifierFlags.contains(.shift) ? 10 : 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Move one frame later (Shift: 10)")

                Button {
                    speedDraft = region.playbackRate
                    speedEntryText = String(format: "%.2f", region.playbackRate)
                    pitchModeDraft = region.pitchMode
                    showSpeedPopover = true
                } label: {
                    HStack(spacing: 3) {
                        PlateLabel(text: "SPEED", size: 6.5, weight: .bold, color: PlateColor.inkFaint)
                        Text(String(format: "%.2f×", region.playbackRate))
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(region.playbackRate == 1 ? PlateColor.inkFaint : CanonColor.brass)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(PlateColor.creamDeep))
                    .overlay(Capsule().stroke(PlateColor.hairline, lineWidth: 0.7))
                }
                .help("Non-destructive region speed and pitch")
                .popover(isPresented: $showSpeedPopover, arrowEdge: .bottom) {
                    audioSpeedPopover(region)
                }

                Button {
                    // Pauses: a loop toggle changes what the tail plays.
                    onGestureBegan()
                    commitLoops(regionId: region.regionId, loops: !region.loops)
                } label: {
                    PlateLabel(
                        text: "LOOP",
                        size: 6.5,
                        weight: .bold,
                        color: region.loops ? PlateColor.cream : PlateColor.inkFaint
                    )
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule().fill(region.loops ? CanonColor.brass : PlateColor.creamDeep)
                    )
                    .overlay(Capsule().stroke(region.loops ? CanonColor.brass : PlateColor.hairline, lineWidth: 0.7))
                }
                .help(region.loops
                    ? "Looping: tiles to fill its length. Turn off to stop honestly at the media's end."
                    : "Plays once, honestly clamped at the media's end. Turn on to tile past it.")

                if ShotAudioLaneId.extendable.contains(laneKind) {
                    Menu {
                        addTrackPicker(kind: laneKind)
                    } label: {
                        PlateLabel(text: "+ TRACK", size: 6.5, weight: .bold, color: CanonColor.brass)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Add audio on a new independently mixed row at the playhead. This region keeps playing unchanged.")
                }
            }

            Button {
                toggleSelectedMute()
            } label: {
                Image(systemName: region.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .help(region.isMuted ? "Unmute region (M)" : "Mute region (M)")

            if !isSource {
                Menu {
                    if ShotAudioLaneId.kind(ofLaneId: region.laneId) == ShotAudioLaneId.ambient {
                        Section("Project Audio") {
                            if audioClips.isEmpty {
                                Text("No audio in this project")
                            }
                            ForEach(audioClips) { clip in
                                Button("\(clip.mediaId == region.mediaId ? "✓ " : "")\(clip.filename)") {
                                    commitReplace(
                                        regionId: region.regionId,
                                        asset: .projectAudio(mediaId: clip.mediaId)
                                    )
                                }
                            }
                        }
                        Section("Generated Beds") {
                            if ambientBeds.isEmpty {
                                Text("No beds in the library")
                            }
                            ForEach(ambientBeds) { bed in
                                Button("\(bed.bedId == region.mediaId ? "✓ " : "")\(bed.displayName)") {
                                    commitReplace(
                                        regionId: region.regionId,
                                        asset: .ambientBed(bedId: bed.bedId)
                                    )
                                }
                            }
                        }
                    } else {
                        if audioClips.isEmpty {
                            Text("No audio in this project")
                        }
                        ForEach(audioClips) { clip in
                            Button("\(clip.mediaId == region.mediaId ? "✓ " : "")\(clip.filename)") {
                                commitReplace(
                                    regionId: region.regionId,
                                    asset: .projectAudio(mediaId: clip.mediaId)
                                )
                            }
                        }
                    }
                    Divider()
                    Button("Import Audio File…") {
                        let panel = NSOpenPanel()
                        panel.title = "Replace Audio"
                        panel.prompt = "Replace"
                        panel.allowsMultipleSelection = false
                        panel.allowedContentTypes = [.audio]
                        guard panel.runModal() == .OK, let url = panel.url else { return }
                        Task {
                            let items = await regionActions.importAudioFiles([url])
                            if let item = items.first {
                                commitReplace(
                                    regionId: region.regionId,
                                    asset: .projectAudio(mediaId: item.mediaId)
                                )
                            }
                        }
                    }
                } label: {
                    PlateLabel(
                        text: "REPLACE",
                        size: 6.5,
                        weight: .bold,
                        color: isMissing ? CanonColor.rust : PlateColor.inkFaint
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Swap this region's media in place — position, trim, gain, and loop survive. Also relinks a missing file.")

                // Only rendered when the lane HAS siblings, so the single-row
                // case keeps the inspector uncluttered.
                let siblings = siblingRows(region.laneId)
                if !siblings.isEmpty {
                    Menu {
                        ForEach(siblings, id: \.self) { target in
                            Button(shot.audioMix.lane(target).label) {
                                onGestureBegan()
                                commitMoveToLane(regionId: region.regionId, laneId: target)
                            }
                        }
                    } label: {
                        PlateLabel(text: "MOVE TO", size: 6.5, weight: .bold, color: PlateColor.inkFaint)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Move this region to another row of the same kind. Its timing, gain, and loop are unchanged — only which row's volume and mute apply.")
                }

                if ShotAudioLaneId.kind(ofLaneId: region.laneId) == ShotAudioLaneId.ambient,
                   ambientBeds.contains(where: { $0.bedId == region.mediaId }) {
                    Button {
                        onOpenAmbientTuner(region.mediaId)
                    } label: {
                        Image(systemName: "slider.vertical.3")
                    }
                    .help("Open this bed in the Ambient Tuner")
                }

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: region.path)])
                } label: {
                    Image(systemName: "folder")
                }
                .disabled(region.path.isEmpty || isMissing)
                .help(isMissing ? "The file is missing" : "Reveal the audio file in Finder")

                Button(role: .destructive) {
                    onGestureBegan()
                    commitDelete(regionId: region.regionId)
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete region (⌫) — ⌘Z restores it")
            }

            Spacer(minLength: 0)

            // Tail column: region gain sits directly beneath the lane volume
            // it modifies — level always lives at the right rail.
            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.1")
                    .font(.system(size: 9))
                    .foregroundStyle(PlateColor.inkFaint)
                    .frame(width: 12)
                Slider(
                    value: Binding(
                        get: { draftGain ?? region.gain },
                        set: { draftGain = $0 }
                    ),
                    in: 0...1
                ) { editing in
                    if !editing, let gain = draftGain {
                        var updated = region
                        updated.gain = gain
                        commitUpdate(updated, actionName: "Adjust Region Gain")
                        draftGain = nil
                    }
                }
                .controlSize(.mini)
                .frame(width: 74)
                .help("Region gain: \(Int((draftGain ?? region.gain) * 100))%")
            }
            .frame(width: ShotTimelineAxis.tailWidth, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .font(.system(size: 9, weight: .semibold))
        .disabled(isRecording)
        .frame(height: metrics.inspectorHeight)
        .padding(.horizontal, 6)
        .background(PlateColor.creamDeep.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .leading) {
            // Same mark, same x as the selected lane's header — the pairing is
            // what keeps the attachment legible from four rows away.
            RoundedRectangle(cornerRadius: 1)
                .fill(CanonColor.brass)
                .frame(width: 2, height: 18)
                .offset(x: -6)
        }
    }

    private func audioSpeedPopover(_ region: ShotAudioRegion) -> some View {
        let preview = region.settingPlayback(rate: speedDraft, pitchMode: pitchModeDraft)
        let overhangSeconds = max(preview.endSeconds - durationSeconds, 0)
        let isExtreme = speedDraft < 0.5 || speedDraft > 2
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PlateLabel(text: "REGION SPEED", size: 8, weight: .bold, color: PlateColor.ink)
                Spacer(minLength: 0)
                Text(String(format: "%.2f×", speedDraft))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(abs(speedDraft - 1) <= 0.001 ? PlateColor.inkFaint : CanonColor.brass)
            }

            HStack(spacing: 5) {
                ForEach([0.25, 0.5, 1, 2, 4], id: \.self) { rate in
                    Button {
                        commitPlayback(
                            rate: rate,
                            pitchMode: pitchModeDraft,
                            actionName: "Adjust Audio Speed"
                        )
                    } label: {
                        Text(String(format: rate < 1 ? "%.2g×" : "%.0f×", rate))
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .background(
                                Capsule().fill(
                                    abs(speedDraft - rate) <= 0.001
                                        ? CanonColor.brass.opacity(0.18)
                                        : PlateColor.creamDeep
                                )
                            )
                            .overlay(
                                Capsule().stroke(
                                    abs(speedDraft - rate) <= 0.001
                                        ? CanonColor.brass.opacity(0.7)
                                        : PlateColor.hairline,
                                    lineWidth: 0.8
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Slider(
                value: Binding(
                    get: { speedDraft },
                    set: {
                        speedDraft = min(
                            max($0, ShotAudioRegion.playbackRateRange.lowerBound),
                            ShotAudioRegion.playbackRateRange.upperBound
                        )
                        speedEntryText = String(format: "%.2f", speedDraft)
                    }
                ),
                in: ShotAudioRegion.playbackRateRange,
                step: 0.05,
                onEditingChanged: { editing in
                    if editing {
                        onGestureBegan()
                    } else {
                        commitPlayback(
                            rate: speedDraft,
                            pitchMode: pitchModeDraft,
                            actionName: "Adjust Audio Speed"
                        )
                    }
                }
            )
            .controlSize(.small)

            HStack(spacing: 6) {
                Text("0.25×")
                Spacer(minLength: 0)
                TextField("Rate", text: $speedEntryText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 58)
                    .onSubmit { commitSpeedEntry() }
                Button("APPLY") { commitSpeedEntry() }
                    .font(.system(size: 7, weight: .bold))
                Button("RESET 1×") {
                    commitPlayback(
                        rate: 1,
                        pitchMode: pitchModeDraft,
                        actionName: "Reset Audio Speed"
                    )
                }
                .font(.system(size: 7, weight: .bold))
                Text("4×")
            }
            .foregroundStyle(PlateColor.inkFaint)

            VStack(alignment: .leading, spacing: 5) {
                PlateLabel(text: "PITCH", size: 7, weight: .bold, color: PlateColor.inkFaint)
                HStack(spacing: 5) {
                    ForEach(ShotAudioPitchMode.allCases, id: \.self) { mode in
                        Button {
                            commitPlayback(
                                rate: speedDraft,
                                pitchMode: mode,
                                actionName: "Change Audio Pitch Mode"
                            )
                        } label: {
                            Text(mode.label.uppercased())
                                .font(.system(size: 7.5, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .background(
                                    Capsule().fill(
                                        pitchModeDraft == mode
                                            ? CanonColor.brass.opacity(0.18)
                                            : PlateColor.creamDeep
                                    )
                                )
                                .overlay(
                                    Capsule().stroke(
                                        pitchModeDraft == mode
                                            ? CanonColor.brass.opacity(0.7)
                                            : PlateColor.hairline,
                                        lineWidth: 0.8
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if region.loops {
                Text("Loop cadence changes; the region keeps its authored length.")
                    .font(.system(size: 8))
                    .foregroundStyle(PlateColor.inkFaint)
            } else {
                Text("Full endpoint · \(ShotAudioTiming.timecode(preview.endSeconds))")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PlateColor.inkFaint)
            }

            if overhangSeconds > 0.000_1 {
                Label(
                    "\(ShotAudioTiming.timecode(overhangSeconds)) continues beyond the CUT. The hidden tail remains recoverable; video duration is unchanged.",
                    systemImage: "arrow.right.to.line"
                )
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(CanonColor.brass)
                .fixedSize(horizontal: false, vertical: true)
            }

            if isExtreme {
                Label(
                    "Extreme rates can introduce audible stretching artifacts.",
                    systemImage: "waveform.badge.exclamationmark"
                )
                .font(.system(size: 8))
                .foregroundStyle(CanonColor.rust)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(
                pitchModeDraft == .preserve
                    ? "Preserve keeps speech and music pitch stable. The source file stays untouched."
                    : "Tape raises pitch when faster and lowers it when slower. The source file stays untouched."
            )
            .font(.system(size: 8))
            .foregroundStyle(PlateColor.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 330)
        .background(PlateColor.cream)
    }

    private func commitSpeedEntry() {
        let cleaned = speedEntryText
            .lowercased()
            .replacingOccurrences(of: "×", with: "")
            .replacingOccurrences(of: "x", with: "")
            .trimmed
        guard let parsed = Double(cleaned), parsed.isFinite else {
            speedEntryText = String(format: "%.2f", speedDraft)
            return
        }
        commitPlayback(
            rate: parsed,
            pitchMode: pitchModeDraft,
            actionName: "Adjust Audio Speed"
        )
    }

    private func commitPlayback(
        rate: Double,
        pitchMode: ShotAudioPitchMode,
        actionName: String
    ) {
        guard let region = selectedRegion, region.laneId != ShotAudioLaneId.source else { return }
        let updated = region.settingPlayback(rate: rate, pitchMode: pitchMode)
        speedDraft = updated.playbackRate
        speedEntryText = String(format: "%.2f", updated.playbackRate)
        pitchModeDraft = updated.pitchMode
        guard updated != region else { return }
        onGestureBegan()
        commitUpdate(updated, actionName: actionName)
    }

    // MARK: Chip menus (truthful pickers, hoisted out of the row flow)
    //
    // Every lane's chip sits at the same x and the same width, so varying menu
    // CONTENTS costs no layout — which is what let the old variable-width
    // accessory cluster and the conditional "N REGIONS" control disappear
    // without losing a single affordance.

    /// One-click route from a selected region to a parallel independently
    /// mixed row. Choosing media is the creation action; no empty row exists.
    @ViewBuilder
    private func addTrackPicker(kind: String) -> some View {
        Section("Project Audio") {
            if audioClips.isEmpty {
                Text("No audio in this project yet")
            }
            ForEach(audioClips) { clip in
                Button(clip.filename) {
                    onGestureBegan()
                    _ = commitAddTrack(
                        kind: kind,
                        asset: .projectAudio(mediaId: clip.mediaId),
                        startSeconds: resolvedPlayheadSeconds()
                    )
                }
            }
        }
        if kind == ShotAudioLaneId.ambient {
            Section("Generated Beds") {
                if ambientBeds.isEmpty {
                    Text("No generated beds yet")
                }
                ForEach(ambientBeds) { bed in
                    Button(bed.displayName) {
                        onGestureBegan()
                        _ = commitAddTrack(
                            kind: kind,
                            asset: .ambientBed(bedId: bed.bedId),
                            startSeconds: resolvedPlayheadSeconds()
                        )
                    }
                }
            }
        }
        Divider()
        Button("Import Audio Files…") {
            onGestureBegan()
            presentAudioTrackImportPanel(kind: kind)
        }
    }

    /// The flat region selector, now a section every lane can carry.
    @ViewBuilder
    private func regionSelectionSection(laneId: String) -> some View {
        let regions = laneRegions(laneId)
        if shotAudioLaneOffersRegionSelector(regionCount: regions.count) {
            Divider()
            Section("Regions") {
                ForEach(regions) { region in
                    Button {
                        selectRegion(region.regionId)
                        onSeek(region.startSeconds)
                    } label: {
                        Text("\(region.regionId == selectedRegionId ? "✓ " : "")\(region.label.trimmed.nilIfEmpty ?? "Region") · \(ShotAudioTiming.timecode(region.startSeconds))")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sourceSpanSelectionSection: some View {
        let spans = assembly.outputPictureSegments.filter { !$0.isBridge && !$0.segmentKey.isEmpty }
        if shotAudioLaneOffersRegionSelector(regionCount: spans.count) {
            Divider()
            Section("Spans") {
                ForEach(spans) { span in
                    Button {
                        selectSourceSegment(span.segmentKey)
                        onSeek(span.outputStartSeconds)
                    } label: {
                        let mark = span.segmentKey == selectedSourceSegmentKey ? "✓ " : ""
                        let muted = mutedSourceSegmentKeys.contains(span.segmentKey) ? " · MUTED" : ""
                        Text("\(mark)Span \(span.ordinal)\(muted) · \(ShotAudioTiming.timecode(span.outputStartSeconds))")
                    }
                }
            }
        }
    }

    /// Combined-cut source ENVELOPES — the authored per-section gain regions
    /// that gate factor three of the source gain law. They had no UI path at
    /// all (the lane draws spans, not regions), which left audio silenced by
    /// state the operator could not see or touch. Selecting one feeds the
    /// region inspector's source branch: level and mute only, never delete.
    @ViewBuilder
    private var sourceEnvelopeSelectionSection: some View {
        let envelopes = laneRegions(ShotAudioLaneId.source)
        if !envelopes.isEmpty {
            Divider()
            Section("Envelopes") {
                ForEach(envelopes) { envelope in
                    Button {
                        selectRegion(envelope.regionId)
                        onSeek(envelope.startSeconds)
                    } label: {
                        let mark = envelope.regionId == selectedRegionId ? "✓ " : ""
                        let state = envelope.isMuted
                            ? " · MUTED"
                            : (envelope.gain < 1 ? " · \(Int(envelope.gain * 100))%" : "")
                        Text("\(mark)\(envelope.label.trimmed.nilIfEmpty ?? "Section")\(state) · \(ShotAudioTiming.timecode(envelope.startSeconds))")
                    }
                }
            }
        }
    }

    /// The sibling rows a region may move to: same kind, not its own row.
    private func siblingRows(_ laneId: String) -> [String] {
        let kind = ShotAudioLaneId.kind(ofLaneId: laneId)
        guard ShotAudioLaneId.extendable.contains(kind) else { return [] }
        return laneRows.filter {
            $0 != laneId && ShotAudioLaneId.kind(ofLaneId: $0) == kind
        }
    }

    private func commitMoveToLane(regionId: String, laneId: String) {
        let old = regionActions.moveToLane(regionId, laneId)
        registerUndoAfterEdit(old: old, regionId: regionId, actionName: "Move Audio to Row")
        if old != nil { selectRegion(regionId) }
    }

    /// Shared body for the two media pickers: place at playhead, or manage the
    /// regions already carrying that asset. An already-placed item never
    /// silently duplicates — adding again is its own worded action.
    @ViewBuilder
    private func mediaPickerItems(
        laneId: String,
        assets: [ShotAudioPickerAsset],
        emptyText: String,
        extraItems: @escaping (ShotAudioAssetReference) -> AnyView = { _ in AnyView(EmptyView()) }
    ) -> some View {
        let regions = laneRegions(laneId)
        if assets.isEmpty {
            Text(emptyText)
        }
        ForEach(assets) { asset in
            let matches = regions.filter { $0.mediaId == asset.asset.assetId }
            if matches.isEmpty {
                Button(asset.name) {
                    _ = commitAdd(
                        laneId: laneId,
                        asset: asset.asset,
                        startSeconds: resolvedPlayheadSeconds()
                    )
                }
            } else {
                Menu("✓ \(asset.name)") {
                    Button("Add Again at Playhead") {
                        _ = commitAdd(
                            laneId: laneId,
                            asset: asset.asset,
                            startSeconds: resolvedPlayheadSeconds()
                        )
                    }
                    ForEach(matches) { match in
                        Button("Select · \(ShotAudioTiming.timecode(match.startSeconds))") {
                            selectRegion(match.regionId)
                            onSeek(match.startSeconds)
                        }
                    }
                    extraItems(asset.asset)
                    Button("Remove", role: .destructive) {
                        commitDeleteMany(regionIds: matches.map(\.regionId))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func clipChipMenu(_ laneId: String) -> some View {
        mediaPickerItems(
            laneId: laneId,
            assets: audioClips.map {
                ShotAudioPickerAsset(asset: .projectAudio(mediaId: $0.mediaId), name: $0.filename)
            },
            emptyText: "No audio in this project yet"
        )
        Divider()
        Button("Import Audio Files…") {
            presentAudioImportPanel(laneId: laneId)
        }
        regionSelectionSection(laneId: laneId)
        rowManagementSection(laneId)
    }

    /// No row management: narration is governed by the artifact-sync law in
    /// `settingNarrationArtifact`, which targets the one base narration lane.
    @ViewBuilder
    private func narrationChipMenu(_ laneId: String) -> some View {
        Button("Open Narration Editor") {
            onOpenNarration()
        }
        Button("Import Existing Narration…") {
            presentAudioImportPanel(laneId: laneId)
        }
        regionSelectionSection(laneId: laneId)
    }

    @ViewBuilder
    private func ambientChipMenu(_ laneId: String) -> some View {
        let regions = laneRegions(laneId)
        let bedIds = Set(ambientBeds.map(\.bedId))
        let selectedBedId = selectedRegion.flatMap {
            $0.laneId == laneId && bedIds.contains($0.mediaId) ? $0.mediaId : nil
        }
        let tunerBedId = selectedBedId ?? regions.first(where: { bedIds.contains($0.mediaId) })?.mediaId
        Section("Project Audio") {
            mediaPickerItems(
                laneId: laneId,
                assets: audioClips.map {
                    ShotAudioPickerAsset(asset: .projectAudio(mediaId: $0.mediaId), name: $0.filename)
                },
                emptyText: "No project audio yet"
            )
        }
        Section("Generated Beds") {
            mediaPickerItems(
                laneId: laneId,
                assets: ambientBeds.map {
                    ShotAudioPickerAsset(asset: .ambientBed(bedId: $0.bedId), name: $0.displayName)
                },
                emptyText: "No generated beds yet",
                extraItems: { asset in
                    guard case .ambientBed(let bedId) = asset else { return AnyView(EmptyView()) }
                    return AnyView(Button("Open in Tuner…") { onOpenAmbientTuner(bedId) })
                }
            )
        }
        Divider()
        Button("Import Audio Files…") {
            presentAudioImportPanel(laneId: laneId)
        }
        Button("New Bed…") { onOpenAmbientTuner(nil) }
        if let tunerBedId, !tunerBedId.isEmpty {
            Button("Open in Tuner…") { onOpenAmbientTuner(tunerBedId) }
        }
        regionSelectionSection(laneId: laneId)
        rowManagementSection(laneId)
    }

    /// Record and the level meter stay in the header — they are per-take and
    /// must survive Look mode, where the timeline strip is replaced. What
    /// lands here is set-once-per-session: which input, and whether video
    /// rolls while you record.
    @ViewBuilder
    private func microphoneChipMenu(_ laneId: String) -> some View {
        let lane = shot.audioMix.lane(laneId)
        let takes = lane.microphoneTakes
        if takes.isEmpty {
            Text("No takes yet")
        } else {
            ForEach(Array(takes.enumerated().reversed()), id: \.element.takeId) { index, take in
                Button {
                    commitActivateTake(take.takeId)
                } label: {
                    let active = take.takeId == lane.activeMicrophoneTake?.takeId
                    Text("\(active ? "✓ " : "")Take \(index + 1) · \(ShotAudioTiming.timecode(take.startSeconds))")
                }
            }
        }
        Divider()
        Menu("Input") {
            if inputDevices.isEmpty {
                Text("No microphone found")
            } else {
                ForEach(inputDevices) { device in
                    Button("\(device.id == selectedInputDeviceId ? "✓ " : "")\(device.name)") {
                        onSelectInputDevice(device.id)
                    }
                }
            }
        }
        Button("\(monitorPlayback ? "✓ " : "")Monitor Video While Recording") {
            onSetMonitorPlayback(!monitorPlayback)
        }
        if let active = lane.activeMicrophoneTake {
            Divider()
            Button("Move Active Take to Trash", role: .destructive) {
                pendingDeleteTake = active
            }
        }
        regionSelectionSection(laneId: laneId)
        rowManagementSection(laneId)
    }

    /// Add-a-row on the base row, remove-this-row on an extra. Only offered for
    /// kinds that may extend — SOURCE is picture-locked and NARRATION is
    /// artifact-governed.
    @ViewBuilder
    private func rowManagementSection(_ laneId: String) -> some View {
        let kind = ShotAudioLaneId.kind(ofLaneId: laneId)
        if ShotAudioLaneId.extendable.contains(kind) {
            Divider()
            Section("Rows") {
                let label = ShotAudioLane.canonical(kind).label
                Button("Add Another \(label) Row") {
                    commitAddLane(kind: kind)
                }
                if ShotAudioLaneId.ordinal(ofLaneId: laneId) > 1 {
                    let occupied = !laneRegions(laneId).isEmpty
                    Button("Remove This Row") {
                        commitRemoveLane(laneId: laneId)
                    }
                    .disabled(occupied)
                    .help(occupied
                        ? "Move this row's audio to another row first — removing a row never deletes audio"
                        : "Removes this empty row")
                }
                if kind == ShotAudioLaneId.microphone {
                    Text("Recording always lands on the first Mic row; move a take afterward.")
                }
            }
        }
    }

}
