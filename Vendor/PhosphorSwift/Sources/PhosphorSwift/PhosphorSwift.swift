import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

public enum Ph: String, CaseIterable, Identifiable {
    public var id: Self { self }

    case arrowRight = "arrow-right"
    case camera = "camera"
    case checkCircle = "check-circle"
    case circle = "circle"
    case crop = "crop"
    case fileText = "file-text"
    case folder = "folder"
    case folderPlus = "folder-plus"
    case gearSix = "gear-six"
    case imagesSquare = "images-square"
    case key = "key"
    case keyReturn = "key-return"
    case pencilSimple = "pencil-simple"
    case plus = "plus"
    case pulse = "pulse"
    case sparkle = "sparkle"
    case tray = "tray"
    case warning = "warning"
    case waveform = "waveform"
}

public extension Ph {
    enum IconWeight: String, CaseIterable, Identifiable {
        public var id: Self { self }

        case regular
        case thin
        case light
        case bold
        case fill
        case duotone
    }

    var regular: Image { Ph.icon(rawValue) }
    var thin: Image { Ph.icon("\(rawValue)-thin") }
    var light: Image { Ph.icon("\(rawValue)-light") }
    var bold: Image { Ph.icon("\(rawValue)-bold") }
    var fill: Image { Ph.icon("\(rawValue)-fill") }
    var duotone: Image { Ph.icon("\(rawValue)-duotone") }

    func weight(_ weight: IconWeight) -> Image {
        switch weight {
        case .regular:
            return regular
        case .thin:
            return thin
        case .light:
            return light
        case .bold:
            return bold
        case .fill:
            return fill
        case .duotone:
            return duotone
        }
    }

    private static func icon(_ name: String) -> Image {
        #if canImport(AppKit)
        if let url = Bundle.module.url(
            forResource: name,
            withExtension: "svg",
            subdirectory: "Assets.xcassets/SVG/\(name).imageset"
        ), let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            return Image(nsImage: image)
                .interpolation(.medium)
                .resizable()
        }
        #endif

        return Image(name, bundle: .module)
            .interpolation(.medium)
            .resizable()
    }
}
