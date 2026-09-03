import SwiftUI

/// Monospaced timecode entry (`mm:ss:ff`, `mm:ss`, or seconds). Commits on
/// Return or blur; an unparseable entry snaps back to the truth. Shared by
/// the audio region inspector (START/IN/OUT), the ruler-head playhead jump,
/// and the strip's IN/OUT fields — one parser, one snap-back law.
struct ShotTimecodeField: View {
    let label: String
    let seconds: Double
    let isEnabled: Bool
    var disabledHelp: String = "This value is fixed"
    let onCommit: (Double) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 3) {
            if !label.isEmpty {
                PlateLabel(text: label, size: 6.5, color: PlateColor.inkFaint)
            }
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(isEnabled ? PlateColor.ink : PlateColor.inkFaint)
                .multilineTextAlignment(.center)
                .frame(width: 52)
                .padding(.vertical, 2)
                .background(PlateColor.cream.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(focused ? CanonColor.brass : PlateColor.hairline, lineWidth: focused ? 1 : 0.6)
                )
                .focused($focused)
                .disabled(!isEnabled)
                .onSubmit(commit)
        }
        .onAppear { text = ShotAudioTiming.timecode(seconds) }
        .onChange(of: seconds) { _, value in
            if !focused { text = ShotAudioTiming.timecode(value) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
        .help(isEnabled
            ? "\(label.isEmpty ? "Timecode" : label): mm:ss:ff, mm:ss, or plain seconds"
            : disabledHelp)
    }

    private func commit() {
        guard let parsed = ShotAudioTiming.parseTimecode(text),
              parsed >= 0,
              abs(parsed - seconds) > 0.000_1 else {
            text = ShotAudioTiming.timecode(seconds)
            return
        }
        onCommit(parsed)
    }
}
