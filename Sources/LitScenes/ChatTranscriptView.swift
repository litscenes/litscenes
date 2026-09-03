import AppKit
import SwiftUI

/// One turn of a project conversation as the transcript renders it.
struct ChatTranscriptTurn: Identifiable, Hashable {
    var id: String
    var isUser: Bool
    var text: String
    var mediaIds: [String] = []
}

/// The paper-column conversation transcript shared by the Story chat and the
/// per-character chats: bubbles, attachment strips, the thinking row, and the
/// scroll-to-bottom behavior. The host supplies its own empty state and labels.
struct ChatTranscriptView<EmptyState: View>: View {
    let turns: [ChatTranscriptTurn]
    let isThinking: Bool
    var thinkingLabel: String = "Updating Goal"
    var userLabel: String = "You"
    var assistantLabel: String = "LitScenes"
    var bottomAnchorId: String = "chat-bottom"
    var thinkingRowId: String = "chat-thinking-row"
    let resolveMedia: ([String]) -> [MediaItemRecord]
    @ViewBuilder let emptyState: () -> EmptyState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if turns.isEmpty {
                        emptyState()
                    } else {
                        ForEach(turns) { turn in
                            bubble(turn)
                                .id(turn.id)
                        }
                    }

                    if isThinking {
                        thinkingRow
                            .id(thinkingRowId)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorId)
                }
                .padding(24)
            }
            .onChange(of: turns.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: isThinking) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 9) {
            ProgressView()
                .controlSize(.small)
            Text(thinkingLabel)
                .font(CanonType.interface(12, weight: .semibold))
                .foregroundStyle(CanonColor.ink.opacity(0.72))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(CanonColor.paperInset.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CanonColor.hairlinePaper.opacity(0.72))
        )
    }

    private func bubble(_ turn: ChatTranscriptTurn) -> some View {
        let isUser = turn.isUser
        return HStack(alignment: .top) {
            if isUser { Spacer(minLength: 58) }
            VStack(alignment: .leading, spacing: 6) {
                Text(isUser ? userLabel : assistantLabel)
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(isUser ? CanonColor.focusBlue : CanonColor.brass)
                Text(turn.text)
                    .font(CanonType.editorial(14))
                    .foregroundStyle(CanonColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if !turn.mediaIds.isEmpty {
                    attachments(turn.mediaIds)
                }
            }
            .padding(12)
            .background(isUser ? Color.white.opacity(0.58) : CanonColor.paperInset.opacity(0.60), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isUser ? CanonColor.focusBlue.opacity(0.32) : CanonColor.hairlinePaper)
            )
            if !isUser { Spacer(minLength: 58) }
        }
    }

    private func attachments(_ mediaIds: [String]) -> some View {
        let items = resolveMedia(mediaIds)
        return VStack(alignment: .leading, spacing: 6) {
            if !items.isEmpty {
                HStack(spacing: 7) {
                    ForEach(items.prefix(4)) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            if let image = NSImage(contentsOfFile: item.thumbnailPath) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 50)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                            } else {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(CanonColor.paperInset)
                                    .frame(width: 72, height: 50)
                                    .overlay(Image(systemName: "photo").foregroundStyle(CanonColor.muted))
                            }
                            Text(item.filename)
                                .font(CanonType.archive(8, weight: .medium))
                                .foregroundStyle(CanonColor.ink.opacity(0.52))
                                .lineLimit(1)
                                .frame(width: 72, alignment: .leading)
                        }
                    }
                    if items.count > 4 {
                        Text("+\(items.count - 4)")
                            .font(CanonType.archive(9, weight: .semibold))
                            .foregroundStyle(CanonColor.ink.opacity(0.52))
                    }
                }
            } else {
                Text(mediaIds.joined(separator: ", "))
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.52))
                    .lineLimit(1)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        }
    }
}
