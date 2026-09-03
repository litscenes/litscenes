import AppKit
import SwiftUI

/// The cream plate: the rendered sheet with its versions, or the casting card while
/// the character is uncast. Light-forced, since the plate palette follows the color
/// scheme and the room is always dark.
struct CharacterSheetPlateView<Card: View>: View {
    let name: String
    let activeSheet: MediaItemRecord?
    /// Newest first, as the engine lists them.
    let sheetVersions: [MediaItemRecord]
    let plateHeight: CGFloat
    let stage: CharacterCastingStage
    var onUseVersion: (String) -> Void
    var onEnlarge: (MediaItemRecord) -> Void
    /// The casting card shown while no sheet exists.
    @ViewBuilder var card: () -> Card

    private var isRendering: Bool {
        if case .rendering = stage { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            plate
            if !sheetVersions.isEmpty {
                versionStrip
            }
        }
    }

    private var plate: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(PlateColor.cream)
            plateContent
            if isRendering, activeSheet != nil {
                RoundedRectangle(cornerRadius: 10)
                    .fill(PlateColor.cream.opacity(0.55))
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(CanonColor.brass)
                    Text("Rendering the next version…")
                        .font(CanonType.display(15, weight: .semibold))
                        .foregroundStyle(PlateColor.ink)
                }
            }
        }
        .overlay(PlateCornerTicks().stroke(CanonColor.brass, lineWidth: 1))
        .frame(maxWidth: .infinity)
        .frame(height: activeSheet == nil ? nil : plateHeight)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var plateContent: some View {
        if let activeSheet, let image = characterThumbnail(activeSheet, maxPixel: 1400) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(18)
                .onTapGesture { onEnlarge(activeSheet) }
                .help("Click to view the sheet larger")
        } else {
            card()
        }
    }

    private var versionStrip: some View {
        CanonHScroller {
            HStack(spacing: 10) {
                ForEach(Array(sheetVersions.enumerated()), id: \.element.mediaId) { index, sheet in
                    versionMini(sheet, ordinal: sheetVersions.count - index)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func versionMini(_ sheet: MediaItemRecord, ordinal: Int) -> some View {
        let isActive = sheet.mediaId == activeSheet?.mediaId
        let numeral = characterSheetOrdinalLabel(ordinal)
        return Button {
            onUseVersion(sheet.mediaId)
        } label: {
            VStack(spacing: 5) {
                Group {
                    if let image = characterThumbnail(sheet) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 6).fill(CanonColor.mediaCard)
                    }
                }
                .frame(width: 72, height: 108)
                .background(CanonColor.mediaCard)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isActive ? CanonColor.brass : CanonColor.hairlineDark, lineWidth: isActive ? 1.5 : 1))
                Text(isActive ? "\(numeral) · CURRENT" : numeral)
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(isActive ? CanonColor.brass : CanonColor.muted)
            }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(isActive ? "Sheet \(numeral) anchors \(name)'s identity" : "Use sheet \(numeral) as \(name)'s identity anchor")
    }
}
