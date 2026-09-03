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
    let stackLabel: String
    let priceNote: String
    /// How many references the stack attaches; 0 renders from text only.
    let stackCapacity: Int
    let isGenerating: Bool
    let isRefining: Bool
    let blockedReason: String
    let failure: String
    let nextSourceOrdinal: Int
    /// GENERATE drafts the identity from the story before the study renders.
    let draftsFirst: Bool
    var focus: FocusState<CharacterEditField?>.Binding
    var onChipsChanged: () -> Void
    var onReset: () -> Void
    var onRefine: () -> Void
    var onGenerate: () -> Void
    var onClose: () -> Void

    private var stackName: String { stackLabel.trimmed.isEmpty ? "No render stack" : stackLabel.trimmed }
    private var price: String { priceNote.trimmed.isEmpty ? "unpriced" : priceNote.trimmed }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            fromRow
            shotRow
            editor
            stateRow
            refineRow
            footer
        }
        .padding(14)
        .background(CanonColor.archiveWell, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CanonColor.hairlineDark))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("STUDIO")
                .font(CanonType.archive(8.5, weight: .bold))
                .kerning(2.0)
                .foregroundStyle(CanonColor.brass)
            Text(draft.referenceIds.isEmpty ? "A new source image from the description" : "A variant frame of \(name) from the chosen references")
                .font(CanonType.interface(12))
                .foregroundStyle(CanonColor.muted)
                .lineLimit(1)
            Spacer(minLength: 0)
            CharacterCapsButton(title: "CLOSE", color: CanonColor.muted, help: "Close the studio", action: onClose)
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
        HStack(spacing: 6) {
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
                    help: "Attach the current sheet as the identity reference"
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
            Spacer(minLength: 0)
        }
    }

    private func referenceChip(id: String, title: String, item: MediaItemRecord, help: String) -> some View {
        let isActive = draft.referenceIds.contains(id)
        return Button {
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
                Text(title)
                    .font(CanonType.archive(8, weight: isActive ? .bold : .semibold))
                    .kerning(0.8)
                    .lineLimit(1)
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
        .help(help)
    }

    private var shotRow: some View {
        HStack(spacing: 6) {
            rowLabel("SHOT")
            ForEach(RosterCharacterRenderPrompt.Shot.allCases) { shot in
                CharacterChip(title: shot.label, isActive: draft.shot == shot, help: "Seed a \(shot.label.lowercased()) study") {
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
            Spacer(minLength: 0)
        }
    }

    private var editor: some View {
        TextEditor(text: $draft.prompt)
            .font(CanonType.interface(13))
            .lineSpacing(3)
            .foregroundStyle(CanonColor.bone)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 120)
            .padding(10)
            .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(focus.wrappedValue == .studioPrompt ? CanonColor.brass.opacity(0.7) : CanonColor.hairlineDark))
            .focused(focus, equals: .studioPrompt)
    }

    private var stateRow: some View {
        HStack(spacing: 12) {
            Text(draft.isEdited ? "EDITED" : "COMPOSED FROM SHOT + IDENTITY")
                .font(CanonType.archive(7.5, weight: .semibold))
                .kerning(1.0)
                .foregroundStyle(draft.isEdited ? CanonColor.softGold : CanonColor.muted)
            if draft.isEdited {
                CharacterCapsButton(title: "RESET", help: "Recompose the prompt from the shot and identity", action: onReset)
            }
            Spacer(minLength: 0)
            if let note = capacityNote {
                Text(note.text)
                    .font(CanonType.interface(11.5))
                    .foregroundStyle(note.isWarning ? CanonColor.rust : CanonColor.muted)
                    .lineLimit(1)
            }
        }
    }

    private var capacityNote: (text: String, isWarning: Bool)? {
        let chosen = draft.referenceIds.count
        guard chosen > 0 else { return nil }
        if stackCapacity == 0 {
            return ("\(stackName) renders from text only — the chosen references will not attach.", true)
        }
        if chosen > stackCapacity {
            return ("\(stackName) takes \(stackCapacity) reference\(stackCapacity == 1 ? "" : "s"); the first \(stackCapacity) attach.", false)
        }
        return nil
    }

    private var refineRow: some View {
        HStack(spacing: 8) {
            TextField("Same sentiment, but… (rewrite the prompt per this direction)", text: $draft.refineInput)
                .textFieldStyle(.plain)
                .font(CanonType.interface(12.5))
                .foregroundStyle(CanonColor.bone)
                .focused(focus, equals: .studioRefine)
                .onSubmit(onRefine)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(CanonColor.mediaCard, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(focus.wrappedValue == .studioRefine ? CanonColor.brass.opacity(0.7) : CanonColor.hairlineDark))
                .disabled(isRefining)
            if isRefining {
                ProgressView()
                    .controlSize(.small)
                    .tint(CanonColor.brass)
            } else {
                Button(action: onRefine) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(draft.refineInput.trimmed.isEmpty ? CanonColor.muted.opacity(0.5) : CanonColor.brass)
                }
                .buttonStyle(.plain)
                .disabled(draft.refineInput.trimmed.isEmpty || draft.prompt.trimmed.isEmpty)
                .help("Rewrite the prompt per this direction, preserving its sentiment")
            }
        }
    }

    private var disabledReason: String {
        if isGenerating { return "Generating now." }
        if !blockedReason.isEmpty { return blockedReason }
        if draft.prompt.trimmed.isEmpty { return "Write a prompt, or reset it." }
        return ""
    }

    private var caption: String {
        if isGenerating {
            return "Generating a \(draft.shot.label.lowercased()) study… it lands in SOURCE IMAGES as source \(nextSourceOrdinal)."
        }
        var caption = "Lands in SOURCE IMAGES as source \(nextSourceOrdinal) · \(stackName) · \(price)"
        if draftsFirst { caption += " · drafts the identity first" }
        return caption
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            StageBrassPill(
                title: failure.isEmpty ? "GENERATE" : "GENERATE AGAIN",
                icon: "sparkles",
                disabledReason: disabledReason,
                style: .ghost,
                action: onGenerate
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(caption)
                    .font(CanonType.interface(11.5))
                    .foregroundStyle(CanonColor.bone.opacity(0.8))
                    .lineLimit(1)
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
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
