import SwiftUI

/// A draft rate: moving the slider never mutates the cut. Apply is one edit.
struct ShotPictureSpeedControl: View {
    let initialRate: Double
    let sourceSeconds: Double
    var onApply: (Double) -> String?
    @State private var text = "1.00"
    @State private var error = ""

    private var rate: Double? {
        guard let value = Double(text), value.isFinite,
              (ShotPictureInsertion.minimumRate...ShotPictureInsertion.maximumRate).contains(value) else { return nil }
        return (value * 100).rounded() / 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: Binding(
                get: { log(rate ?? initialRate) },
                set: { text = String(format: "%.2f", exp($0)); error = "" }
            ), in: log(ShotPictureInsertion.minimumRate)...log(ShotPictureInsertion.maximumRate))
            .accessibilityLabel("Picture speed")
            HStack(spacing: 6) {
                TextField("1.00", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(PlateType.label(10.5, weight: .regular))
                    .frame(width: 65)
                    .onSubmit(apply)
                    .accessibilityLabel("Exact picture speed")
                Text("×").font(PlateType.label(10))
                Button("1×") { text = "1.00"; error = "" }
                    .buttonStyle(PlateButtonStyle())
                Spacer(minLength: 0)
                Button("Apply", action: apply)
                    .buttonStyle(PlateButtonStyle(isProminent: true))
                    .disabled(rate == nil)
            }
            if let rate {
                PlateLabel(text: String(format: "%.2fs → %.2fs", sourceSeconds, sourceSeconds / rate), size: 8, color: PlateColor.inkFaint)
            } else {
                PlateLabel(text: "Enter a speed from 0.10× to 16.00×", size: 8, color: CanonColor.rust)
            }
            if !error.isEmpty {
                Text(error).font(PlateType.label(8)).foregroundStyle(CanonColor.rust)
            }
        }
        .onAppear { text = String(format: "%.2f", initialRate) }
    }

    private func apply() {
        guard let rate else { return }
        error = onApply(rate) ?? ""
    }
}

struct ShotSpeedSectionPopover: View {
    let selectionSeconds: Double
    var onCommit: (Double) -> String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlateLabel(text: "SECTION SPEED", size: 8.5, weight: .bold, color: PlateColor.ink)
            ShotPictureSpeedControl(initialRate: 1, sourceSeconds: selectionSeconds, onApply: onCommit)
            PlateLabel(text: "Free, undoable. The section starts muted; ♪ restores its stretched sound.", size: 7, color: PlateColor.inkFaint)
        }
        .padding(12)
        .frame(width: 292)
    }
}
