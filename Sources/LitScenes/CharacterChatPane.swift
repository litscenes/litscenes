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
            Text("Say what should change and the next sheet follows. Photos you attach become source images.")
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
        if rendersAfterChat {
            let price = priceNote.isEmpty ? "unpriced" : priceNote
            return "Each message renders a new sheet · \(stackLabel.isEmpty ? "no stack" : stackLabel) · \(price)"
        }
        return "Messages update the sheet prompt. Render when ready."
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
            HStack(spacing: 8) {
                Toggle(isOn: Binding(get: { rendersAfterChat }, set: onToggleAutoRender)) {
                    Text("RENDER AFTER EACH MESSAGE")
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
