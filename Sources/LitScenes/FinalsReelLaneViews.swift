import AppKit
import SwiftUI

/// Reel-state undo on the shot-audio idiom: snapshot-based, symmetric —
/// each handler re-registers its inverse, so ⌘Z/⇧⌘Z round-trip without a
/// second path. One committed gesture = one stage-set transaction = one
/// registered action.
@MainActor
final class FinalsReelUndoCoordinator: ObservableObject {
    var applyState: ((ReelStateSnapshot) -> Void)?

    func registerEdit(
        old: ReelStateSnapshot,
        new: ReelStateSnapshot,
        actionName: String,
        undoManager: UndoManager?
    ) {
        guard let undoManager, old != new else { return }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.applyState?(old)
                target.registerEdit(old: new, new: old, actionName: actionName, undoManager: undoManager)
            }
        }
        undoManager.setActionName(actionName)
    }
}

/// One vocabulary for seam-edit undo names, shared by every authoring
/// surface (the Reel strip and the sequence row).
func reelSeamUndoActionName(kind: ReelSeamKind, frames: Int?) -> String {
    guard frames != nil else { return "Set Hard Cut" }
    return kind == .dipToBlack ? "Set Reel Dip to Black" : "Set Reel Crossfade"
}

/// One boundary's display truth for the reel strip.
struct ReelSeamDisplay: Identifiable {
    var leftEntryId: String
    var rightEntryId: String
    /// nil = hard cut (no authored seam).
    var requestedFrames: Int?
    /// What the composition plan actually applied (0 with a requested value
    /// means "capped — cut too short").
    var appliedFrames: Int
    /// The authored seam's kind (meaningful only with an authored seam).
    var kind: ReelSeamKind = .crossfade
    /// False when this boundary exists only because a skipped cut sits
    /// between the two picks — authoring a seam there would go dormant
    /// instantly, so the control refuses honestly instead.
    var isEditable: Bool = true
    var id: String { "\(leftEntryId)>\(rightEntryId)" }
}

/// THE SEAM PILL — the one seam-authoring control, shared by the Reel strip
/// and the SCENES v2 sequence row. Glyphs: ‖ hard cut, ≈N crossfade, ◐N dip
/// through black. `.applied` truth shows the composition plan's real frames
/// (rust when a request capped away); `.requested` shows only the authored
/// request — the sequence row has no baked durations to consult, so it says
/// where the applied truth lives instead of guessing it.
/// `surface` picks the label's dress: `.plate` is the Reel's tiny cream chip;
/// `.canvasRow` is a full-height divider (hairline · glyph chip · hairline)
/// legible on the dark workbench — the plate chip disappears there.
struct ReelSeamPillMenu: View {
    enum Truth { case applied, requested }
    enum Surface { case plate, canvasRow }

    let seam: ReelSeamDisplay
    var truth: Truth = .applied
    var surface: Surface = .plate
    var fps: Int = reelOutputProfile.fps
    var onSetSeam: (
        _ leftEntryId: String,
        _ rightEntryId: String,
        _ kind: ReelSeamKind,
        _ frames: Int?
    ) -> Void

    private var displayedFrames: Int {
        truth == .applied ? seam.appliedFrames : (seam.requestedFrames ?? 0)
    }

    private var isAuthored: Bool { seam.requestedFrames != nil }
    private var isVisible: Bool { isAuthored && displayedFrames > 0 }
    private var isCapped: Bool { truth == .applied && isAuthored && seam.appliedFrames == 0 }

    private func seconds(_ frames: Int) -> String {
        String(format: "%.2f", Double(frames) / Double(max(fps, 1)))
    }

    private func check(_ kind: ReelSeamKind, _ frames: Int) -> String {
        seam.kind == kind && seam.requestedFrames == frames ? "✓ " : ""
    }

    var body: some View {
        Menu {
            Button("\(seam.requestedFrames == nil ? "✓ " : "")Hard cut") {
                onSetSeam(seam.leftEntryId, seam.rightEntryId, .crossfade, nil)
            }
            Divider()
            ForEach(reelSeamPresetFrames, id: \.self) { frames in
                Button("\(check(.crossfade, frames))Crossfade \(frames)f · −\(seconds(frames))s") {
                    onSetSeam(seam.leftEntryId, seam.rightEntryId, .crossfade, frames)
                }
            }
            Divider()
            ForEach(reelSeamPresetFrames, id: \.self) { frames in
                Button("\(check(.dipToBlack, frames))Dip to black \(frames)f · −\(seconds(frames))s") {
                    onSetSeam(seam.leftEntryId, seam.rightEntryId, .dipToBlack, frames)
                }
            }
            if isCapped {
                Text("Capped to a hard cut — a cut this short can't carry the fade")
            } else if truth == .applied,
                      let requested = seam.requestedFrames,
                      seam.appliedFrames < requested {
                Text("Capped to \(seam.appliedFrames)f — cut too short for \(requested)f")
            }
        } label: {
            switch surface {
            case .plate: plateChip
            case .canvasRow: canvasRowDivider
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: true, vertical: surface == .plate)
        .disabled(!seam.isEditable)
        .help(helpText)
    }

    private var glyphText: String {
        isVisible ? "\(seam.kind == .dipToBlack ? "◐" : "≈")\(displayedFrames)" : "‖"
    }

    private var plateChip: some View {
        PlateLabel(
            text: glyphText,
            size: 7.5,
            weight: .bold,
            color: isCapped ? CanonColor.rust : (isVisible ? CanonColor.brass : PlateColor.inkFaint)
        )
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.cream.opacity(0.95)))
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(isVisible ? CanonColor.brass : PlateColor.hairline, lineWidth: 0.7)
        )
    }

    /// The dark-surface dress: a divider the height of its container —
    /// hairlines above and below a glyph chip big enough to read and hit.
    private var canvasRowDivider: some View {
        let tint: Color = isCapped
            ? CanonColor.rust
            : (isVisible ? CanonColor.brass : Color.white.opacity(0.55))
        return VStack(spacing: 3) {
            Rectangle()
                .fill(tint.opacity(isVisible ? 0.55 : 0.35))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            Text(glyphText)
                .font(CanonType.archive(9.5, weight: .bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(isVisible ? 0.14 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(tint.opacity(isVisible ? 0.8 : 0.5), lineWidth: 1)
                )
            Rectangle()
                .fill(tint.opacity(isVisible ? 0.55 : 0.35))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .contentShape(Rectangle())
    }

    private var helpText: String {
        guard seam.isEditable else {
            return "A skipped cut sits between these two picks — render it, or remove it from FINALS, before authoring this seam"
        }
        let kindName = seam.kind == .dipToBlack ? "Dip to black" : "Crossfade"
        if truth == .requested {
            return isAuthored
                ? "\(kindName) \(displayedFrames)f requested — consumes \(seconds(displayedFrames))s; the Reel shows the applied result"
                : "Hard cut — click for a crossfade or a dip to black"
        }
        if isVisible {
            return "\(kindName) \(seam.appliedFrames)f — consumes \(seconds(seam.appliedFrames))s of the reel. Click for presets"
        }
        if isCapped {
            return "\(kindName) requested but capped to a hard cut — the neighboring cut is too short"
        }
        return "Hard cut — click for a crossfade or a dip to black"
    }
}

/// The reel's cut-band strip: one proportional band per baked cut in FINALS
/// order, the seam control at each boundary, and the playhead. Clicking a
/// band seeks to its start; the strip is output-time (the reel has no
/// razored-out material — its bands ARE what plays).
struct FinalsReelCutStrip: View {
    let bands: [ReelCutBand]
    let totalSeconds: Double
    let playheadSeconds: Double
    let seams: [ReelSeamDisplay]
    let cutNames: [String: String]
    var onSeek: (Double) -> Void
    var onSetSeam: (
        _ leftEntryId: String,
        _ rightEntryId: String,
        _ kind: ReelSeamKind,
        _ frames: Int?
    ) -> Void

    private let stripHeight: CGFloat = 34

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(PlateColor.creamDeep.opacity(0.35))
                ForEach(Array(bands.enumerated()), id: \.element.entryId) { index, band in
                    let frame = bandFrame(band, width: width)
                    ZStack {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(PlateColor.ink.opacity(index.isMultiple(of: 2) ? 0.08 : 0.05))
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(PlateColor.hairline, lineWidth: 0.6)
                        if frame.width > 44 {
                            PlateLabel(
                                text: cutNames[band.cutId] ?? "Cut",
                                size: 6.5,
                                weight: .semibold,
                                color: PlateColor.ink
                            )
                            .lineLimit(1)
                            .padding(.horizontal, 4)
                        }
                    }
                    .frame(width: max(frame.width - 2, 2), height: stripHeight - 4)
                    .offset(x: frame.x + 1, y: 2)
                    .contentShape(Rectangle())
                    .onTapGesture { onSeek(band.startSeconds) }
                    .help("\(cutNames[band.cutId] ?? "Cut") · \(ShotAudioTiming.timecode(band.startSeconds)) — click to seek")
                }
                ForEach(seams) { seam in
                    if let boundaryX = boundaryX(rightEntryId: seam.rightEntryId, width: width) {
                        ReelSeamPillMenu(seam: seam, truth: .applied, onSetSeam: onSetSeam)
                            .position(x: boundaryX, y: stripHeight / 2)
                    }
                }
                if totalSeconds > 0 {
                    let x = CGFloat(min(max(playheadSeconds / totalSeconds, 0), 1)) * width
                    Rectangle()
                        .fill(PlateColor.ink.opacity(0.72))
                        .frame(width: 1, height: stripHeight)
                        .offset(x: x)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: stripHeight)
    }

    private func bandFrame(_ band: ReelCutBand, width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        guard totalSeconds > 0 else { return (0, 0) }
        let x = CGFloat(band.startSeconds / totalSeconds) * width
        let bandWidth = CGFloat(band.durationSeconds / totalSeconds) * width
        return (x, bandWidth)
    }

    private func boundaryX(rightEntryId: String, width: CGFloat) -> CGFloat? {
        guard totalSeconds > 0,
              let band = bands.first(where: { $0.entryId == rightEntryId }) else { return nil }
        return CGFloat(band.startSeconds / totalSeconds) * width
    }

}

/// The bake board: one honest row per cut that is NOT ready — queued, baking,
/// failed, or skipped. All-ready reels show nothing (the film speaks).
struct FinalsReelBakeBoard: View {
    let finals: [StageFinalsEntry]
    let states: [String: ReelBakeState]
    let cutNames: [String: String]
    /// Re-runs the ensure pass — a failed bake's file is gone, so ensure
    /// re-queues exactly the failures.
    var onRetry: (() -> Void)? = nil

    private var rows: [(cutId: String, text: String, isProblem: Bool, isWorking: Bool)] {
        finals.compactMap { entry in
            let name = cutNames[entry.cutId] ?? "Cut"
            switch states[entry.cutId] {
            case .queued:
                return (entry.cutId, "\(name) — queued", false, false)
            case .baking:
                return (entry.cutId, "\(name) — baking", false, true)
            case .failed(let message):
                return (entry.cutId, "\(name) — failed: \(message)", true, false)
            case .skipped(let reason):
                return (entry.cutId, "\(name) — skipped: \(reason)", true, false)
            case .ready, nil:
                return nil
            }
        }
    }

    private var hasFailure: Bool {
        states.values.contains { if case .failed = $0 { return true }; return false }
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.cutId) { row in
                    HStack(spacing: 6) {
                        if row.isWorking {
                            ProgressView().controlSize(.mini)
                        }
                        PlateLabel(
                            text: row.text,
                            size: 8,
                            weight: .semibold,
                            color: row.isProblem ? CanonColor.rust : PlateColor.inkFaint
                        )
                        .lineLimit(1)
                    }
                }
                if hasFailure, let onRetry {
                    Button("Retry Failed Bakes") {
                        onRetry()
                    }
                    .buttonStyle(PlateButtonStyle())
                    .help("Re-runs only what failed — finished bakes stay cached")
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PlateColor.creamDeep.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}
