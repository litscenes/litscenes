import AppKit
import SwiftUI

/// The uncast character's plate content: a ghost frame of what the sheet will be
/// built from, one sentence, and the render action itself — stack, pill, and the
/// consequence in words — front and center.
struct CharacterCastingCardView: View {
    let copy: CharacterCastingCopy
    let stage: CharacterCastingStage
    let leadThumbnails: [MediaItemRecord]
    let stacks: [RenderStack]
    let selectedStack: RenderStack?
    let credentialBlocker: (RenderStack) -> String?
    let showsAppSettings: Bool
    var onSelectStack: (String) -> Void
    var onRender: () -> Void
    var onOpenAppSettings: () -> Void
    /// The sheet→SCENES lane: a running suggestion job (real spinner), then the
    /// note with its SCENES → link, or the failure in words.
    var isSuggestingFrames: Bool = false
    var suggestionNote: CharacterRenderNote? = nil
    var onOpenScenes: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ghostFrame
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Text(copy.cardHeadline)
                        .font(CanonType.display(21, weight: .semibold))
                        .foregroundStyle(PlateColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if case .rendering = stage {
                        ProgressView()
                            .controlSize(.small)
                            .tint(CanonColor.brass)
                    }
                }
                Text(copy.cardSentence)
                    .font(CanonType.interface(13.5))
                    .foregroundStyle(PlateColor.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                if !copy.cardFailure.isEmpty {
                    Text(copy.cardFailure)
                        .font(CanonType.interface(13.5))
                        .foregroundStyle(CanonColor.rust)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actionRow
                    .padding(.top, 4)
                consequenceColumn
            }
            Spacer(minLength: 0)
        }
        .padding(22)
    }

    private var actionRow: some View {
        HStack(alignment: .center, spacing: 12) {
            CharacterStackMenu(
                stacks: stacks,
                selectedStack: selectedStack,
                credentialBlocker: credentialBlocker,
                onPlate: true,
                onSelect: onSelectStack
            )
            StageBrassPill(
                title: copy.barTitle,
                icon: "sparkles",
                disabledReason: copy.disabledReason,
                action: onRender
            )
        }
    }

    private var consequenceColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(copy.consequence)
                .font(CanonType.interface(11.5))
                .foregroundStyle(PlateColor.inkFaint)
                .lineLimit(1)
            if !copy.note.isEmpty {
                HStack(spacing: 8) {
                    Text(copy.note)
                        .font(CanonType.interface(11.5))
                        .foregroundStyle(copy.noteTone == .muted ? PlateColor.inkFaint : castingToneColor(copy.noteTone))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsAppSettings {
                        CharacterCapsButton(title: "APP SETTINGS →", help: "Open App Settings", action: onOpenAppSettings)
                    }
                }
            }
            suggestionRow
        }
    }

    @ViewBuilder
    private var suggestionRow: some View {
        if isSuggestingFrames {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Suggesting Frames for SCENES…")
                    .font(CanonType.interface(11.5))
                    .foregroundStyle(PlateColor.inkFaint)
            }
        } else if let suggestionNote, suggestionNote.lane == .suggestions {
            HStack(spacing: 8) {
                Text(suggestionNote.message)
                    .font(CanonType.interface(11.5))
                    .foregroundStyle(suggestionNote.suggestedFrameCount > 0 ? PlateColor.inkFaint : CanonColor.rust)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if suggestionNote.suggestedFrameCount > 0 {
                    CharacterCapsButton(
                        title: "SCENES →",
                        help: "Open SCENES — the new suggestions lead the pool",
                        action: onOpenScenes
                    )
                }
            }
        }
    }

    private var ghostFrame: some View {
        ZStack(alignment: .topLeading) {
            if leadThumbnails.count > 1, let second = characterThumbnail(leadThumbnails[1], maxPixel: 400) {
                frameImage(second)
                    .opacity(0.6)
                    .offset(x: 10, y: 10)
            }
            if let first = leadThumbnails.first, let image = characterThumbnail(first, maxPixel: 400) {
                frameImage(image)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(PlateColor.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    )
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(PlateColor.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                    .frame(width: 112, height: 168)
                    .overlay(PlateCornerTicks(inset: 5, length: 7).stroke(PlateColor.ink.opacity(0.35), lineWidth: 1))
                    .overlay(
                        Image(systemName: "person.crop.rectangle")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(PlateColor.inkFaint)
                    )
            }
        }
        .frame(width: leadThumbnails.count > 1 ? 122 : 112, height: leadThumbnails.count > 1 ? 178 : 168, alignment: .topLeading)
    }

    /// The ghost frame never crops a source — a portrait keeps its head; other
    /// shapes letterbox on a faint matte.
    private func frameImage(_ image: NSImage) -> some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 112, height: 168)
            .background(PlateColor.ink.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
