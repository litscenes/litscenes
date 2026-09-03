import SwiftUI
import AppKit

/// Design system for the engraved-plate surfaces (Frame Creator), styled after
/// early-1800s astronomical dial engravings: cream paper, ink linework,
/// graduated tick rings, letterspaced serif labels. Deliberately its own
/// palette — plate surfaces should read as a printed plate, not app chrome.
///
/// Every value is a scheme-adaptive color: in a `.light` environment it prints
/// as the ink-on-cream original, in `.dark` it inverts to a warm bone-on-charcoal
/// negative. The Frame Creator drives this with its own `colorScheme` override,
/// so the whole plate flips from one toggle without touching call sites.
enum PlateColor {
    static let cream = dynamicColor(light: 0xF6EFDC, dark: 0x1A1813)
    static let creamDeep = dynamicColor(light: 0xEDE0C2, dark: 0x262218)
    static let ink = dynamicColor(light: 0x201A12, dark: 0xE9E0C9)
    static let inkFaint = ink.opacity(0.55)
    static let hairline = ink.opacity(0.30)
    static let hairlineFaint = ink.opacity(0.16)

    /// A color that resolves per the SwiftUI `\.colorScheme` environment.
    private static func dynamicColor(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return nsColor(isDark ? dark : light)
        })
    }

    private static func nsColor(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum PlateType {
    static func label(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func title(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func figure(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// Uppercased, letterspaced serif label — the plate's stand-in for engraved
/// small caps (SwiftUI system serif has no true small caps).
struct PlateLabel: View {
    let text: String
    var size: CGFloat = 10
    var weight: Font.Weight = .medium
    var color: Color = PlateColor.ink

    var body: some View {
        Text(text.uppercased())
            .font(PlateType.label(size, weight: weight))
            .kerning(size * 0.18)
            .foregroundStyle(color)
    }
}

/// Radial graduation ticks around a circle, like the minute/degree rings on an
/// astronomical dial. Every `majorEvery`-th tick is drawn at `majorLength`.
struct PlateTickRing: Shape {
    var tickCount: Int = 240
    var majorEvery: Int = 5
    var minorLength: CGFloat = 4
    var majorLength: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard tickCount > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        for tick in 0..<tickCount {
            let angle = Double(tick) / Double(tickCount) * 2 * .pi
            let length = majorEvery > 0 && tick.isMultiple(of: majorEvery) ? majorLength : minorLength
            let innerRadius = outerRadius - length
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            path.move(to: CGPoint(
                x: center.x + direction.x * innerRadius,
                y: center.y + direction.y * innerRadius
            ))
            path.addLine(to: CGPoint(
                x: center.x + direction.x * outerRadius,
                y: center.y + direction.y * outerRadius
            ))
        }
        return path
    }
}

/// Filled triangular indicator with a thin tail, used at the wheel's fixed
/// pointer station and (smaller) on the Frame square edge. Points in -x
/// (leftward) within its rect; rotate for other bearings.
struct PlatePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tipInset = rect.width * 0.42
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + tipInset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + tipInset, y: rect.midY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.minX + tipInset, y: rect.midY + rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.minX + tipInset, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Double-rule engraved border: a 1pt outer rule with a 0.5pt inner rule.
struct PlateEngravedBorder: ViewModifier {
    var cornerRadius: CGFloat = 4
    var inset: CGFloat = 3

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(PlateColor.ink, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: max(0, cornerRadius - inset * 0.6))
                    .stroke(PlateColor.hairline, lineWidth: 0.5)
                    .padding(inset)
            )
    }
}

extension View {
    func plateEngravedBorder(cornerRadius: CGFloat = 4, inset: CGFloat = 3) -> some View {
        modifier(PlateEngravedBorder(cornerRadius: cornerRadius, inset: inset))
    }
}

/// Engraved plate button: serif letterspaced caption inside a double rule.
struct PlateButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var isProminent = false
    var isFullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PlateType.label(11.5, weight: .semibold))
            .kerning(1.6)
            .textCase(.uppercase)
            .foregroundStyle(isProminent ? PlateColor.cream : PlateColor.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        isProminent
                            ? (configuration.isPressed ? PlateColor.inkFaint : PlateColor.ink)
                            : (configuration.isPressed ? PlateColor.creamDeep : Color.clear)
                    )
            )
            .plateEngravedBorder(cornerRadius: 3, inset: 2)
            .opacity(isEnabled ? 1 : 0.4)
    }
}
