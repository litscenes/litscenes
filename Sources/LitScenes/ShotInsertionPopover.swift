import SwiftUI

/// The arranged-copy plate, opened from an insertion cell in the cut strip:
/// rate presets, per-copy sound, +1 loop, re-copy (when inert), delete. A
/// consolidated run (⟳ ×N) edits GROUP-scope — every control below applies
/// to all N siblings; editing one copy alone means deleting and re-pasting
/// it, which keeps the group law simple and the cells honest.
struct ShotInsertionPopover: View {
    let run: [ShotInsertionCell]
    var onSetRate: (Set<String>, Double) -> Void
    var onSetMuted: (Set<String>, Bool) -> Void
    var onDelete: (Set<String>) -> Void
    var onRecopy: (String) -> Void
    var onAddLoopCopy: (ShotPictureInsertion) -> Void

    private static let ratePresets: [Double] = [0.25, 0.5, 1, 1.5, 2]

    @State private var typedRate = ""

    private var leader: ShotPictureInsertion? { run.first?.insertion }
    /// A SPEED SECTION carrier: this copy replaces razored base material —
    /// deleting it IS "back to 1×" (the linked razors restore with it).
    private var isSpeedCarrier: Bool {
        !(leader?.replacesRazorCutIds.isEmpty ?? true)
    }
    private var state: ShotInsertionSourceState { run.first?.state ?? .fresh }
    private var ids: Set<String> { Set(run.map { $0.insertion.insertionId }) }
    private var isMuted: Bool { leader?.muteSourceAudio ?? false }
    private var rate: Double { leader?.playbackRate ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !state.isFresh {
                inertRow
            }
            rateRow
            HStack(spacing: 6) {
                Button(isMuted ? "♪ Muted — Restore Sound" : "♪ Mute This Copy") {
                    onSetMuted(ids, !isMuted)
                }
                .buttonStyle(PlateButtonStyle(isProminent: isMuted))
                .help(isMuted
                    ? "This copy plays silent — click to carry its source sound again"
                    : "Silence this copy's source sound — the base instance keeps playing its own")
            }
            if rate != 1, !isMuted {
                PlateLabel(
                    text: "Audio stretches with the picture at \(shotInsertionRateLabel(rate))",
                    size: 7,
                    color: PlateColor.inkFaint
                )
            }
            HStack(spacing: 6) {
                if let leader, state.isFresh {
                    Button("＋1 Loop") {
                        onAddLoopCopy(leader)
                    }
                    .buttonStyle(PlateButtonStyle())
                    .help("Paste one more copy right after this one (born muted — the ♪ restores sound)")
                }
                Spacer(minLength: 0)
                Button(isSpeedCarrier
                    ? "Delete — Back to 1×"
                    : (run.count > 1 ? "Delete ×\(run.count)" : "Delete")) {
                    onDelete(ids)
                }
                .buttonStyle(PlateButtonStyle())
                .help(isSpeedCarrier
                    ? "Removes this speed section — the razored material returns at its own speed. Free, undoable"
                    : (run.count > 1
                        ? "Remove all \(run.count) copies in this loop — free, undoable"
                        : "Remove this copy — free, undoable"))
            }
        }
        .padding(12)
        .frame(width: 262)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                PlateLabel(
                    text: isSpeedCarrier
                        ? "SPEED SECTION ⟳"
                        : (run.count > 1 ? "ARRANGED COPIES ⟳ ×\(run.count)" : "ARRANGED COPY ⟳"),
                    size: 8.5,
                    weight: .bold,
                    color: PlateColor.ink
                )
                Spacer(minLength: 0)
                if let leader {
                    PlateLabel(
                        text: "\(String(format: "%.1f", leader.sourceSeconds))s · \(shotInsertionRateLabel(leader.playbackRate))",
                        size: 8,
                        color: PlateColor.inkFaint
                    )
                }
            }
            // The shot IN/OUT window can clip a copy shorter than it was
            // authored — say so, or the header's seconds read as a lie.
            if state.isFresh,
               let placed = run.first?.placedOutputSeconds,
               let leader,
               placed < leader.outputSeconds - 0.01 {
                PlateLabel(
                    text: "Plays \(String(format: "%.1f", placed))s — clipped by the shot IN/OUT trim",
                    size: 7,
                    color: PlateColor.inkFaint
                )
            }
            PlateLabel(
                text: "Free — assembled at play time, the source file is never touched",
                size: 7,
                color: PlateColor.inkFaint
            )
        }
    }

    @ViewBuilder
    private var inertRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlateLabel(
                text: "· \(state.badge)",
                size: 8,
                weight: .bold,
                color: CanonColor.rust
            )
            switch state {
            case .olderTake:
                PlateLabel(
                    text: "The segment re-rendered; this copy pinned the old pixels and now plays nothing.",
                    size: 7,
                    color: PlateColor.inkFaint
                )
                if let leader {
                    Button("Re-copy From Current Take") {
                        onRecopy(leader.insertionId)
                    }
                    .buttonStyle(PlateButtonStyle(isProminent: true))
                    .help("Re-establish this copy on the takes now playing, at the same seconds — an explicit swap, undoable")
                }
            case .sourceMissing:
                PlateLabel(
                    text: "The copied file is gone from disk; the copy plays nothing until it returns.",
                    size: 7,
                    color: PlateColor.inkFaint
                )
            case .unsupportedTransform:
                PlateLabel(
                    text: "This copy asks for a transform this build doesn't run yet; it plays nothing rather than pretending.",
                    size: 7,
                    color: PlateColor.inkFaint
                )
            case .trimmedOut:
                PlateLabel(
                    text: "The shot IN/OUT trim excludes this copy; move the handles (or clear the trim) and it plays again.",
                    size: 7,
                    color: PlateColor.inkFaint
                )
            case .fresh:
                EmptyView()
            }
        }
    }

    private var rateRow: some View {
        HStack(spacing: 4) {
            PlateLabel(text: "SPEED", size: 7.5, weight: .semibold, color: PlateColor.inkFaint)
            ForEach(Self.ratePresets, id: \.self) { preset in
                Button(shotInsertionRateLabel(preset)) {
                    onSetRate(ids, preset)
                }
                .buttonStyle(PlateButtonStyle(isProminent: abs(rate - preset) < 0.001))
                .help(preset < 1
                    ? "Slow this copy to \(shotInsertionRateLabel(preset)) — output grows accordingly"
                    : preset > 1
                        ? "Speed this copy to \(shotInsertionRateLabel(preset)) — output shrinks accordingly"
                        : "Play this copy at its source speed")
            }
            TextField("×", text: $typedRate)
                .textFieldStyle(.roundedBorder)
                .font(PlateType.label(10, weight: .regular))
                .frame(width: 44)
                .onSubmit(commitTypedRate)
                .help("Free-form rate, \(shotInsertionRateLabel(ShotPictureInsertion.minimumRate))–\(shotInsertionRateLabel(ShotPictureInsertion.maximumRate)) — extremes look like what they are")
        }
    }

    private func commitTypedRate() {
        guard let value = Double(typedRate.trimmed.replacingOccurrences(of: "×", with: "")),
              value > 0 else { return }
        onSetRate(ids, min(max(value, ShotPictureInsertion.minimumRate), ShotPictureInsertion.maximumRate))
        typedRate = ""
    }
}
