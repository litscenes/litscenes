import AppKit
import SwiftUI

/// One reference the STUDIO can attach: a source image with its slot number.
struct CharacterStudioSourceChip: Identifiable, Hashable {
    var mediaId: String
    var item: MediaItemRecord
    var ordinal: Int
    var label: String

    var id: String { mediaId }
}

/// THE STUDIO: generate a source image for the character — from text, or as a
/// variant of a chosen source or the sheet — with an editable prompt. Results land
/// in SOURCE IMAGES.
struct CharacterStudioPanel: View {
    @Binding var draft: CharacterStudioDraft
    let name: String
    let sources: [CharacterStudioSourceChip]
    let activeSheet: MediaItemRecord?
    let sheetOrdinalLabel: String
    let priceNote: String
    let attachedMediaIds: [String]
    let stacks: [RenderStack]
    let selectedStack: RenderStack?
    let credentialBlocker: (RenderStack) -> String?
    let isGenerating: Bool
    let blockedReason: String
    let failure: String
    /// GENERATE drafts the identity from the story before the study renders.
    let draftsFirst: Bool
    var focus: FocusState<CharacterEditField?>.Binding
    var onChipsChanged: () -> Void
    var onUseCurrentSources: () -> Void
    var onSelectStack: (String) -> Void
    var onOpenAppSettings: () -> Void
    var onGenerate: () -> Void
    var onClose: () -> Void

    private var price: String { priceNote.trimmed.isEmpty ? "unpriced" : priceNote.trimmed }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            fromRow
            HStack(spacing: 8) {
                Text(draft.followsCurrentSources ? "Following current source images" : "Custom reference selection")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
                if !draft.followsCurrentSources {
                    CharacterCapsButton(title: "USE CURRENT SOURCES", action: onUseCurrentSources)
                }
            }
            shotRow
            footer
            DisclosureGroup("Image prompt with framing") {
                Text(draft.prompt).font(CanonType.interface(12)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(CanonType.interface(11.5))
            .foregroundStyle(CanonColor.muted)
        }
        .padding(14)
        .background(CanonColor.archiveWell, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CanonColor.hairlineDark))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("CHARACTER IMAGE")
                .font(CanonType.archive(8.5, weight: .bold))
                .kerning(2.0)
                .foregroundStyle(CanonColor.brass)
            Text("Uses the smart prompt above")
                .font(CanonType.interface(12))
                .foregroundStyle(CanonColor.muted)
                .lineLimit(1)
            Spacer(minLength: 0)

        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(CanonType.archive(7.5, weight: .semibold))
            .kerning(1.2)
            .foregroundStyle(CanonColor.muted)
            .frame(width: 38, alignment: .leading)
    }

    private var fromRow: some View {
        StyleStudioFlowLayout(spacing: 6) {
            rowLabel("FROM")
            ForEach(sources) { source in
                referenceChip(
                    id: source.mediaId,
                    title: source.label.isEmpty ? "SOURCE \(source.ordinal)" : source.label.uppercased(),
                    item: source.item,
                    help: "Attach source \(source.ordinal)\(source.label.isEmpty ? "" : " — \(source.label)")"
                )
            }
            if let activeSheet {
                referenceChip(
                    id: activeSheet.mediaId,
                    title: "SHEET \(sheetOrdinalLabel)",
                    item: activeSheet,
                    help: "Attach the active sheet as the identity reference"
                )
            }
            if draft.referenceIds.isEmpty {
                Text("TEXT ONLY")
                    .font(CanonType.archive(8, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(CanonColor.muted)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .overlay(Capsule().stroke(CanonColor.hairlineDark, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
    }

    private func referenceChip(id: String, title: String, item: MediaItemRecord, help: String) -> some View {
        let isActive = draft.referenceIds.contains(id)
        return Button {
            draft.followsCurrentSources = false
            if isActive {
                draft.referenceIds.removeAll { $0 == id }
            } else {
                draft.referenceIds.append(id)
            }
            onChipsChanged()
        } label: {
            HStack(spacing: 5) {
                Group {
                    if let image = characterThumbnail(item) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 3).fill(CanonColor.mediaCard)
                    }
                }
                .frame(width: 18, height: 18)
                .background(CanonColor.mediaCard)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                if let index = attachedMediaIds.firstIndex(of: id) {
                    Text("\(index + 1)")
                        .font(CanonType.archive(8, weight: .bold))
                }
                Text(title)
                    .font(CanonType.archive(8, weight: isActive ? .bold : .semibold))
                    .kerning(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isActive ? CanonColor.ink : CanonColor.bone.opacity(0.82))
            .padding(.leading, 3)
            .padding(.trailing, 9)
            .frame(height: 24)
            .background(Capsule().fill(isActive ? CanonColor.brass : Color.clear))
            .overlay(Capsule().stroke(isActive ? Color.clear : CanonColor.hairlineDark, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .disabled(!FileManager.default.fileExists(atPath: item.path))
        .help(help + (attachedMediaIds.contains(id) ? " — attaches to the next image" : " — not attached to the next image"))
    }

    private var shotRow: some View {
        StyleStudioFlowLayout(spacing: 6) {
            rowLabel("SHOT")
            ForEach(RosterCharacterRenderPrompt.Shot.allCases) { shot in
                CharacterChip(title: shot.label, isActive: draft.shot == shot, help: "Use \(shot.label.lowercased()) framing for the next image") {
                    draft.shot = shot
                    onChipsChanged()
                }
            }
            if !draft.referenceIds.isEmpty {
                rowLabel("LOOK")
                    .padding(.leading, 6)
                ForEach(CharacterStudyLook.allCases) { look in
                    CharacterChip(title: look.label, isActive: draft.look == look, help: look.help) {
                        draft.look = look
                        onChipsChanged()
                    }
                }
            }
        }
    }

    private var disabledReason: String {
        if isGenerating { return "Generating now." }
        if !blockedReason.isEmpty { return blockedReason }
        if draft.prompt.trimmed.isEmpty { return "Describe the subject in the smart prompt above." }
        return ""
    }

    private var caption: String {
        if isGenerating {
            return "Generating character image… adds one image to Source Images."
        }
        var caption = "Adds one image to Source Images · \(price)"
        if draftsFirst { caption += " · drafts the identity first" }
        return caption
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            StyleStudioFlowLayout(spacing: 10) {
                CharacterStackMenu(
                    stacks: stacks, selectedStack: selectedStack,
                    credentialBlocker: credentialBlocker, onSelect: onSelectStack,
                    onOpenAppSettings: onOpenAppSettings
                )
                StageBrassPill(
                    title: failure.isEmpty ? "GENERATE IMAGE" : "RETRY IMAGE",
                    icon: "sparkles",
                    disabledReason: disabledReason,
                    style: .filled,
                    action: onGenerate
                )
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(caption)
                    .font(CanonType.interface(11.5))
                    .foregroundStyle(CanonColor.bone.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                if !failure.isEmpty {
                    Text("Generation failed: \(failure)")
                        .font(CanonType.interface(11.5))
                        .foregroundStyle(CanonColor.rust)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !disabledReason.isEmpty, !isGenerating {
                    Text(disabledReason)
                        .font(CanonType.interface(11.5))
                        .foregroundStyle(CanonColor.softGold)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
