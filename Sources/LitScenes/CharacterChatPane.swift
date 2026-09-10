import AppKit
import SwiftUI

/// The paper column: a conversation that refines one character's sheet. Every
/// message revises the identity and refinements; when the character renders after
/// each message, a new sheet version follows, priced in the composer's own words.
struct CharacterChatPane: View {
    let character: ProjectCharacter
    let turns: [ChatTranscriptTurn]
    let isThinking: Bool
    let thinkingLabel: String
    @Binding var draft: String
    let attachments: [ChatComposerAttachment]
    let rendersAfterChat: Bool
    let hasReferences: Bool
    let sheetDisabledReason: String
    var onCreateImage: () -> Void
    var onRenderSheet: () -> Void
    let promptIsHandEdited: Bool
    let stackLabel: String
    let priceNote: String
    let statusText: String
    let resolveMedia: ([String]) -> [MediaItemRecord]
    var onSend: () -> Void
    var onUpload: () -> Void
    var onRemoveAttachment: (String) -> Void
    var onPasteImageData: (Data) -> Void
    var onPasteFileURLs: ([URL]) -> Void
    var onDropMediaIds: ([String]) -> Void
    var onToggleAutoRender: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(20)
                .padding(.bottom, 10)
            Divider()
            ChatTranscriptView(
                turns: turns,
                isThinking: isThinking,
                thinkingLabel: thinkingLabel,
                bottomAnchorId: "character-bottom",
                thinkingRowId: "character-thinking-row",
                resolveMedia: resolveMedia
            ) {
                emptyState
            }
            composer
                .padding(20)
                .background(CanonColor.paper)
        }
        .background(CanonColor.paper)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("CONVERSATION")
                .font(CanonType.archive(9, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(CanonColor.muted)
            Text(character.name)
                .font(CanonType.display(20, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Describe or refine \(character.name).")
                .font(CanonType.editorial(18, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            Text("Describe the subject or ask for changes. Chat revises the smart prompt on the left and saves a version; your edits are included in the next turn.")
                .font(CanonType.editorial(14))
                .foregroundStyle(CanonColor.ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .background(CanonColor.paperInset.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper))
    }

    private var composerStatus: String {
        if !statusText.isEmpty { return statusText }
        if promptIsHandEdited {
            return "Prompt is hand-edited. Messages update identity; reset the prompt to include them."
        }
        if !hasReferences {
            return "Messages update the character. Add or create a source image before generating a reference sheet."
        }
        if rendersAfterChat {
            let price = priceNote.isEmpty ? "unpriced" : priceNote
            return "Sending changes also regenerates the reference sheet · \(stackLabel.isEmpty ? "no model" : stackLabel) · \(price)"
        }
        return "Messages revise the smart prompt on the left. Generate when ready."
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 9) {
            ChatComposerView(
                text: $draft,
                attachments: attachments,
                placeholder: "Describe or refine \(character.name)…",
                statusText: composerStatus,
                isWaiting: isThinking,
                canSend: !isThinking && (!draft.trimmed.isEmpty || !attachments.isEmpty),
                onSend: onSend,
                onUpload: onUpload,
                onRemoveAttachment: onRemoveAttachment,
                onPasteImageData: onPasteImageData,
                onPasteFileURLs: onPasteFileURLs,
                onDropMediaIds: onDropMediaIds
            )
            if !hasReferences {
                Button("Create character image…", action: onCreateImage)
                    .buttonStyle(.plain)
                    .foregroundStyle(CanonColor.brass)
            } else if !rendersAfterChat && !turns.isEmpty {
                Button(character.activeSheetMediaId == nil ? "Generate reference sheet" : "Regenerate reference sheet", action: onRenderSheet)
                    .buttonStyle(.plain)
                    .foregroundStyle(CanonColor.brass)
                    .disabled(isThinking || !sheetDisabledReason.isEmpty)
                    .help(sheetDisabledReason.isEmpty ? "Generate the next reference sheet using the saved instructions" : sheetDisabledReason)
                Text("\(stackLabel) · \(priceNote.isEmpty ? "unpriced" : priceNote)")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
            }
            HStack(spacing: 8) {
                Toggle(isOn: Binding(get: { rendersAfterChat }, set: { onToggleAutoRender($0) })) {
                    Text("AUTOMATICALLY REGENERATE REFERENCE SHEET")
                        .font(CanonType.archive(8, weight: .semibold))
                        .kerning(1.2)
                        .foregroundStyle(CanonColor.ink.opacity(0.7))
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                Spacer(minLength: 0)
            }
        }
    }
}
