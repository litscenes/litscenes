import SwiftUI

/// The SECTION SPEED plate, opened from the strip's SPEED button with a span
/// selected: presets plus a free-form rate, committed as one gesture — the
/// selection's material is razored out and a born-muted copy of it plays in
/// the gap at the chosen rate (THE REPLACE PATTERN). Everything here is
/// free; Delete on the resulting ⟳ cell returns the material to 1×.
struct ShotSpeedSectionPopover: View {
    let selectionSeconds: Double
    var onCommit: (Double) -> Void

    @State private var typedRate = ""
    @State private var clampNote = ""

    private static let ratePresets: [Double] = [0.25, 0.5, 1.5, 2, 4]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                PlateLabel(text: "SECTION SPEED", size: 8.5, weight: .bold, color: PlateColor.ink)
                Spacer(minLength: 0)
                PlateLabel(
                    text: "\(String(format: "%.1f", selectionSeconds))s selected",
                    size: 8,
                    color: PlateColor.inkFaint
                )
            }
            PlateLabel(
                text: "The section plays at the chosen speed in place — free, undoable. Born muted: ♪ on its ⟳ cell restores the stretched sound.",
                size: 7,
                color: PlateColor.inkFaint
            )
            HStack(spacing: 4) {
                ForEach(Self.ratePresets, id: \.self) { preset in
                    Button(shotInsertionRateLabel(preset)) {
                        onCommit(preset)
                    }
                    .buttonStyle(PlateButtonStyle())
                    .help(previewHelp(rate: preset))
                }
            }
            HStack(spacing: 6) {
                PlateLabel(text: "CUSTOM", size: 7.5, weight: .semibold, color: PlateColor.inkFaint)
                TextField("1.25", text: $typedRate)
                    .textFieldStyle(.roundedBorder)
                    .font(PlateType.label(10.5, weight: .regular))
                    .frame(width: 58)
                    .onSubmit(commitTyped)
                Button("Apply") {
                    commitTyped()
                }
                .buttonStyle(PlateButtonStyle(isProminent: true))
                .disabled(parsedRate == nil)
                if let rate = parsedRate {
                    PlateLabel(text: previewLine(rate: rate), size: 7.5, color: PlateColor.inkFaint)
                }
            }
            if !clampNote.isEmpty {
                PlateLabel(text: clampNote, size: 7, color: CanonColor.rust)
            }
            PlateLabel(
                text: "Rates run \(shotInsertionRateLabel(ShotPictureInsertion.minimumRate))–\(shotInsertionRateLabel(ShotPictureInsertion.maximumRate)); extremes look like what they are — dropped or repeated frames.",
                size: 7,
                color: PlateColor.inkFaint
            )
        }
        .padding(12)
        .frame(width: 292)
    }

    private var parsedRate: Double? {
        guard let value = Double(typedRate.trimmed.replacingOccurrences(of: "×", with: "")),
              value > 0 else { return nil }
        return value
    }

    private func commitTyped() {
        guard let value = parsedRate else { return }
        let clamped = min(max(value, ShotPictureInsertion.minimumRate), ShotPictureInsertion.maximumRate)
        clampNote = clamped == value
            ? ""
            : "Clamped to \(shotInsertionRateLabel(clamped)) — rates run \(shotInsertionRateLabel(ShotPictureInsertion.minimumRate))–\(shotInsertionRateLabel(ShotPictureInsertion.maximumRate))"
        onCommit(clamped)
    }

    /// Tilde-honest: spans resolve at commit, so the preview approximates.
    private func previewLine(rate: Double) -> String {
        let clamped = min(max(rate, ShotPictureInsertion.minimumRate), ShotPictureInsertion.maximumRate)
        return "~\(String(format: "%.1f", selectionSeconds))s → ~\(String(format: "%.1f", selectionSeconds / clamped))s"
    }

    private func previewHelp(rate: Double) -> String {
        "\(previewLine(rate: rate)) at \(shotInsertionRateLabel(rate))"
    }
}
