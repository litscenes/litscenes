import PhosphorSwift
import SwiftUI

enum LitIcon: Equatable {
    case activity
    case add
    case analyze
    case arrowRight
    case camera
    case complete
    case crop
    case document
    case folder
    case folderAdd
    case incomplete
    case key
    case keyReturn
    case media
    case notices
    case rename
    case settings
    case warning
    case waveform

    var image: Image {
        switch self {
        case .activity:
            Ph.pulse.bold
        case .add:
            Ph.plus.bold
        case .analyze:
            Ph.sparkle.bold
        case .arrowRight:
            Ph.arrowRight.bold
        case .camera:
            Ph.camera.bold
        case .complete:
            Ph.checkCircle.fill
        case .crop:
            Ph.crop.bold
        case .document:
            Ph.fileText.bold
        case .folder:
            Ph.folder.bold
        case .folderAdd:
            Ph.folderPlus.bold
        case .incomplete:
            Ph.circle.bold
        case .key:
            Ph.key.bold
        case .keyReturn:
            Ph.keyReturn.bold
        case .media:
            Ph.imagesSquare.bold
        case .notices:
            Ph.tray.bold
        case .rename:
            Ph.pencilSimple.bold
        case .settings:
            Ph.gearSix.bold
        case .warning:
            Ph.warning.fill
        case .waveform:
            Ph.waveform.bold
        }
    }
}

struct LitIconView: View {
    let icon: LitIcon
    var size: CGFloat = 14

    var body: some View {
        icon.image
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct LitIconLabel: View {
    let title: String
    let icon: LitIcon
    var iconSize: CGFloat = 14
    var spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            LitIconView(icon: icon, size: iconSize)
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }
}
