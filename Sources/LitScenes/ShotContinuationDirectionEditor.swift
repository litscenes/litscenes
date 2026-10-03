import SwiftUI

struct ShotContinuationDirectionEditor: View {
    @Binding var prompt: String
    var references: [ShotCharacterReference]
    @State private var caret = 0
    @State private var anchor = CGPoint.zero
    @State private var caretRequest: FramePromptCaretRequest?
    @State private var focused = false
    @State private var suppressed = false
    @State private var selectedIndex = 0

    private var entries: [RosterMentionResolver.Entry] { references.map(\.entry) }
    private var partial: RosterMentionResolver.ActivePartial? {
        guard focused, !suppressed else { return nil }
        return RosterMentionResolver.activePartial(in: prompt, caretUTF16Offset: caret, entries: entries)
    }
    private var suggestions: [RosterMentionResolver.Entry] {
        partial.map { RosterMentionResolver.suggestions(for: $0, entries: entries) } ?? []
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                FrameCreatorPromptTextEditor(text: $prompt, caretRequest: caretRequest,
                    isMentionPickerPresented: !suggestions.isEmpty,
                    onCaretChange: { offset, point in caret = offset; anchor = point; suppressed = false; selectedIndex = 0 },
                    onFocusChange: { focused = $0 },
                    onPickerMove: { selectedIndex = min(max(selectedIndex + $0, 0), max(suggestions.count - 1, 0)) },
                    onPickerSelect: { complete(at: selectedIndex) },
                    onPickerDismiss: { suppressed = true })
                    .padding(7)
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, entry in
                            Button { _ = complete(at: index) } label: {
                                HStack(spacing: 6) {
                                    if let path = references.first(where: { $0.id == entry.id })?.images.first?.path,
                                       let image = StripThumbnailCache.shared.image(path: path) {
                                        Image(nsImage: image).resizable().scaledToFit().frame(width: 34, height: 26)
                                    }
                                    Text("@" + entry.name).font(CanonType.interface(11))
                                    Spacer()
                                }
                                .padding(5)
                                .background(index == selectedIndex ? CanonColor.brass.opacity(0.22) : Color.clear)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .frame(width: 250)
                    .background(ShotReviewPalette.paper, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(CanonColor.hairlinePaper))
                    .shadow(radius: 5)
                    .offset(x: min(max(0, anchor.x), max(0, geometry.size.width - 250)), y: max(24, anchor.y + 6))
                    .zIndex(2)
                }
            }
        }
        .frame(height: 92)
        .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper, lineWidth: 1))
        .zIndex(5)
    }

    private func complete(at index: Int) -> Bool {
        guard let partial = RosterMentionResolver.activePartial(in: prompt, caretUTF16Offset: caret, entries: entries) else { return false }
        let candidates = RosterMentionResolver.suggestions(for: partial, entries: entries)
        guard candidates.indices.contains(index) else { return false }
        let entry = candidates[index]
        let offset = partial.range.lowerBound.utf16Offset(in: prompt) + ("@" + entry.name + " ").utf16.count
        prompt = RosterMentionResolver.completing(text: prompt, partial: partial, with: entry)
        caretRequest = FramePromptCaretRequest(utf16Offset: offset)
        caret = offset
        suppressed = true
        return true
    }
}
