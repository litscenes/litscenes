import SwiftUI

struct CharacterSmartPromptPanel: View {
    let character: ProjectCharacter
    @Binding var text: String
    var focus: FocusState<CharacterEditField?>.Binding
    let isThinking: Bool
    var onSave: () -> Void
    var onRestore: (String) -> Void
    var onDraft: () -> Void
    @State private var showsHistory = false
    @State private var previewId = ""

    private var history: CharacterPromptHistory { character.promptHistory ?? CharacterPromptHistory() }
    private var isEdited: Bool { text.trimmed != character.descriptionPrompt.trimmed }
    private var preview: CharacterPromptVersion? { history.versions.first { $0.id == previewId } ?? history.activeVersion }
    private var hasProposal: Bool {
        history.versions.last.map { $0.isProposal && $0.id != history.activeVersionId } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CharacterSectionHeader(title: "SMART PROMPT") {
                if let ordinal = history.activeOrdinal {
                    Text("v\(ordinal) · \(history.activeVersion?.sourceLabel ?? "")")
                        .font(CanonType.interface(11))
                        .foregroundStyle(CanonColor.muted)
                }
                CharacterCapsButton(title: "HISTORY · \(history.versions.count)", help: "Preview or restore a saved prompt") {
                    onSave()
                    previewId = hasProposal ? (history.versions.last?.id ?? "") : ""
                    showsHistory = true
                }
            }
            TextEditor(text: $text)
                .font(CanonType.interface(14))
                .lineSpacing(4)
                .foregroundStyle(CanonColor.bone)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 170, idealHeight: 230, maxHeight: 300)
                .padding(12)
                .background(CanonColor.archiveWell, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(focus.wrappedValue == .appearance ? CanonColor.brass : CanonColor.hairlineDark))
                .focused(focus, equals: .appearance)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Describe your subject here, or develop it in the conversation.")
                            .font(CanonType.interface(14))
                            .foregroundStyle(CanonColor.muted)
                            .padding(18)
                            .allowsHitTesting(false)
                    }
                }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(isEdited ? "Unsaved edits · saved before chat or generation" : "Saved · used by image and reference sheet generation")
                    .font(CanonType.interface(11.5))
                    .foregroundStyle(isEdited ? CanonColor.softGold : CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if isEdited { CharacterCapsButton(title: "SAVE VERSION", action: onSave) }
                if text.trimmed.isEmpty {
                    CharacterCapsButton(title: "DRAFT FROM STORY", action: onDraft)
                        .disabled(isThinking)
                }
            }
            if isThinking {
                Text("Chat is revising the prompt. You can keep editing; newer work will be preserved.")
                    .font(CanonType.interface(11.5))
                    .foregroundStyle(CanonColor.muted)
            }
            if hasProposal {
                Button("Chat saved a revision while you were editing. Review it in History.") {
                    previewId = hasProposal ? (history.versions.last?.id ?? "") : ""
                    showsHistory = true
                }
                .buttonStyle(.plain)
                .font(CanonType.interface(12))
                .foregroundStyle(CanonColor.softGold)
            }
        }
        .sheet(isPresented: $showsHistory) { historyBrowser }
    }

    private var historyBrowser: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Prompt history · \(character.name)")
                    .font(CanonType.editorial(21))
                Spacer()
                Button("Done") { showsHistory = false }
            }
            HSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(history.versions.indices.reversed()), id: \.self) { index in
                            let version = history.versions[index]
                            Button { previewId = version.id } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("v\(index + 1) · \(version.sourceLabel)")
                                        .font(CanonType.interface(12, weight: .semibold))
                                    Text(version.id == history.activeVersionId ? "Current" : (version.isProposal ? "Chat proposal" : version.dateLabel))
                                        .font(CanonType.interface(10))
                                        .foregroundStyle(CanonColor.muted)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(preview?.id == version.id ? CanonColor.brass.opacity(0.17) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(minWidth: 190, idealWidth: 210, maxWidth: 250)
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView {
                        Text(preview?.prompt ?? "No saved prompt yet.")
                            .font(CanonType.interface(14))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let preview {
                        if !preview.summary.isEmpty {
                            Text(preview.summary).font(CanonType.interface(12)).foregroundStyle(CanonColor.muted)
                        }
                        let outputs = history.mediaVersionIds.values.filter { $0 == preview.id }.count
                        Text("\(outputs) generated output\(outputs == 1 ? "" : "s") linked to this version")
                            .font(CanonType.interface(11)).foregroundStyle(CanonColor.muted)
                        Button("Use this version") {
                            onRestore(preview.id)
                            showsHistory = false
                        }
                        .disabled(preview.id == history.activeVersionId)
                    }
                    Text("Restores as a new version. Existing images stay unchanged; nothing is generated.")
                        .font(CanonType.interface(11)).foregroundStyle(CanonColor.muted)
                }
                .padding(.leading, 16)
                .frame(minWidth: 350)
            }
        }
        .padding(22)
        .frame(minWidth: 680, idealWidth: 780, minHeight: 440, idealHeight: 540)
        .foregroundStyle(CanonColor.bone)
        .background(CanonColor.room)
    }
}
