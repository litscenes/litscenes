import SwiftUI

/// The LOOP OUTPUT plate, opened from the strip's LOOP button — no selection
/// needed: the WHOLE cut output repeats end to end ×N, preview and export
/// both. Free (assembled at play time, zero provider calls, no new files),
/// one ⌘Z, and the button stays lit "Loop ×N" while active — Remove loop
/// returns to ×1 in one step.
struct ShotOutputLoopPopover: View {
    let baseOutputSeconds: Double
    let currentCount: Int
    var onCommit: (Int) -> Void

    @State private var typedCount = ""
    @State private var clampNote = ""

    private static let countPresets: [Int] = [2, 3, 4, 6, 8]

    /// ×20 hard cap AND total output ≤ 600s — the envelope the export guard
    /// deadline and the Lucy source caps were designed around.
    private var maxCount: Int {
        guard baseOutputSeconds > 0 else { return ShotCutList.maximumOutputLoopCount }
        return max(1, min(ShotCutList.maximumOutputLoopCount, Int(600.0 / baseOutputSeconds)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                PlateLabel(text: "LOOP OUTPUT", size: 8.5, weight: .bold, color: PlateColor.ink)
                Spacer(minLength: 0)
                PlateLabel(
                    text: currentCount > 1
                        ? "×\(currentCount) active · \(String(format: "%.1f", baseOutputSeconds))s pass"
                        : "\(String(format: "%.1f", baseOutputSeconds))s output",
                    size: 8,
                    color: PlateColor.inkFaint
                )
            }
            PlateLabel(
                text: "The whole cut repeats end to end — preview and export both. Every pass sounds "
                    + "like the first: narration, mic, and placed audio ride along. Free, assembled "
                    + "at play time, one ⌘Z.",
                size: 7,
                color: PlateColor.inkFaint
            )
            if maxCount > 1 {
                HStack(spacing: 4) {
                    ForEach(Self.countPresets.filter { $0 <= maxCount }, id: \.self) { preset in
                        Button("×\(preset)") {
                            onCommit(preset)
                        }
                        .buttonStyle(PlateButtonStyle(isProminent: preset == currentCount))
                        .help(previewLine(count: preset))
                    }
                }
                HStack(spacing: 6) {
                    PlateLabel(text: "CUSTOM", size: 7.5, weight: .semibold, color: PlateColor.inkFaint)
                    TextField("5", text: $typedCount)
                        .textFieldStyle(.roundedBorder)
                        .font(PlateType.label(10.5, weight: .regular))
                        .frame(width: 44)
                        .onSubmit(commitTyped)
                    Button("Apply") {
                        commitTyped()
                    }
                    .buttonStyle(PlateButtonStyle(isProminent: true))
                    .disabled(parsedCount == nil)
                    if let count = parsedCount {
                        PlateLabel(text: previewLine(count: count), size: 7.5, color: PlateColor.inkFaint)
                    }
                }
            } else {
                PlateLabel(
                    text: "This cut is too long to loop — total output stays under 10 minutes.",
                    size: 7,
                    color: CanonColor.rust
                )
            }
            if !clampNote.isEmpty {
                PlateLabel(text: clampNote, size: 7, color: CanonColor.rust)
            }
            if currentCount > 1 {
                Button("Remove loop") {
                    onCommit(1)
                }
                .buttonStyle(PlateButtonStyle())
                .help("Play the output once again — one step, same as ⌘Z")
            }
            PlateLabel(
                text: "Loops run ×2–×\(ShotCutList.maximumOutputLoopCount) and total output stays "
                    + "under 10 minutes. Strip clicks seek within the first pass.",
                size: 7,
                color: PlateColor.inkFaint
            )
        }
        .padding(12)
        .frame(width: 300)
    }

    private var parsedCount: Int? {
        guard let value = Int(typedCount.trimmed.replacingOccurrences(of: "×", with: "")),
              value >= 1 else { return nil }
        return value
    }

    private func commitTyped() {
        guard let value = parsedCount else { return }
        let clamped = min(max(value, 1), maxCount)
        clampNote = clamped == value
            ? ""
            : "Clamped to ×\(clamped) — loops run ×2–×\(ShotCutList.maximumOutputLoopCount) and total output stays under 10 minutes"
        onCommit(clamped)
    }

    /// Tilde-honest: durations resolve at assembly, so the preview approximates.
    private func previewLine(count: Int) -> String {
        let clamped = min(max(count, 1), maxCount)
        return "~\(String(format: "%.1f", baseOutputSeconds))s → ~\(String(format: "%.1f", baseOutputSeconds * Double(clamped)))s"
    }
}
