import SwiftUI

/// The shot player's keyboard reference — rendered from the ONE keymap table
/// (`ShotTransportKeymap.all`), so the sheet can never drift from the keys
/// that actually ship. Opened by `?` and the footer's KEYS button.
struct ShotTransportCheatSheet: View {
    var onClose: () -> Void

    private var scopes: [String] {
        var seen: [String] = []
        for row in ShotTransportKeymap.all where !seen.contains(row.scope) {
            seen.append(row.scope)
        }
        return seen
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PlateLabel(text: "KEYBOARD", size: 11, weight: .bold, color: PlateColor.ink)
                Spacer(minLength: 0)
                Button("Close") { onClose() }
                    .buttonStyle(PlateButtonStyle())
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(scopes, id: \.self) { scope in
                        VStack(alignment: .leading, spacing: 6) {
                            PlateLabel(
                                text: scope.uppercased(),
                                size: 8,
                                weight: .bold,
                                color: PlateColor.inkFaint
                            )
                            ForEach(ShotTransportKeymap.all.filter { $0.scope == scope }) { row in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(row.keys)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(PlateColor.ink)
                                        .frame(width: 88, alignment: .leading)
                                    PlateLabel(text: row.action, size: 8.5, color: PlateColor.inkFaint)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    PlateLabel(
                        text: "Audio-lane keys act on the selected region of the focused lane; everything else bubbles to the player.",
                        size: 8,
                        color: PlateColor.inkFaint
                    )
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 460, height: 560)
        .background(PlateColor.cream)
        .environment(\.colorScheme, .light)
    }
}
