import SwiftUI

enum CanonColor {
    static let room = color(0x0E0D0A)
    static let sidebar = color(0x171613)
    static let archiveWell = color(0x1A1814)
    static let mediaCard = color(0x22201B)
    static let mediaCardHover = color(0x29261F)
    static let hairlineDark = color(0x37332A)
    static let paper = color(0xF1E7D2)
    static let paperAged = color(0xE7D9BC)
    static let paperInset = color(0xE7D9BC)
    static let hairlinePaper = color(0xD3C09A)
    static let ink = color(0x1B1711)
    static let bone = color(0xE8E0D0)
    static let muted = color(0x9E9585)
    static let brass = color(0xB68A33)
    static let softGold = color(0xD0B15C)
    static let focusBlue = color(0x2F5E9E)
    static let olive = color(0x6F7F52)
    static let rust = color(0x9B4E35)
    static let paperShadow = color(0x2B2114, opacity: 0.20)

    /// Treatment role tints, shared by every blend surface (console, browser, picker
    /// orbits): brass for the primary voice, teal and rose for the two accents.
    static let rolePrimary = brass
    static let roleAccentOne = color(0x33857D)
    static let roleAccentTwo = color(0x9E5C82)

    static func roleTint(forSlotIndex index: Int) -> Color {
        switch index {
        case 0: return rolePrimary
        case 1: return roleAccentOne
        default: return roleAccentTwo
        }
    }

    private static func color(_ hex: Int, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum CanonType {
    static func editorial(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func interface(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func archive(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Weights that map to the SemiBold display static; everything else
    /// takes the Regular.
    private static let heavyDisplayWeights: Set<Font.Weight> = [.semibold, .bold, .heavy, .black]

    /// The bundled display serif (Fraunces). Falls back to `editorial`
    /// whenever the bundled face is unavailable — never to sans.
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard CanonFontRegistration.displayFaceAvailable else {
            return editorial(size, weight: weight)
        }
        let name = heavyDisplayWeights.contains(weight)
            ? CanonFontRegistration.displaySemiBoldName
            : CanonFontRegistration.displayRegularName
        return .custom(name, size: size)
    }

    /// The bundled display italic — the voice for quoted creative text (the
    /// whisper claim, the brief). Same fallback law as `display`.
    static func displayItalic(_ size: CGFloat) -> Font {
        guard CanonFontRegistration.displayFaceAvailable else {
            return editorial(size).italic()
        }
        return .custom(CanonFontRegistration.displayItalicName, size: size)
    }
}

struct CanonPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var isFullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CanonType.interface(13, weight: .semibold))
            .foregroundStyle(CanonColor.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(configuration.isPressed ? CanonColor.softGold : CanonColor.brass)
            )
            .opacity(isEnabled ? 1 : 0.48)
    }
}

struct CanonSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var isFullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CanonType.interface(13, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? CanonColor.softGold : CanonColor.bone)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(configuration.isPressed ? CanonColor.mediaCardHover : CanonColor.sidebar)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(CanonColor.brass.opacity(configuration.isPressed ? 0.78 : 0.52))
            )
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct CanonUtilityButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CanonType.interface(12, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? CanonColor.softGold : CanonColor.muted)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? CanonColor.mediaCard : Color.clear)
            )
            .opacity(isEnabled ? 1 : 0.42)
    }
}

struct CanonSidebarMotif: View {
    var body: some View {
        Canvas { context, size in
            let text = Text("L")
                .font(CanonType.archive(12, weight: .semibold))
                .foregroundStyle(CanonColor.bone.opacity(0.028))
            let resolved = context.resolve(text)
            let stepX: CGFloat = 26
            let stepY: CGFloat = 30

            var row = 0
            var y: CGFloat = 24
            while y < size.height {
                let xOffset = row.isMultiple(of: 2) ? CGFloat(0) : stepX * 0.45
                var x: CGFloat = 12 + xOffset
                while x < size.width {
                    context.draw(resolved, at: CGPoint(x: x, y: y))
                    x += stepX
                }
                row += 1
                y += stepY
            }
        }
        .opacity(0.8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
