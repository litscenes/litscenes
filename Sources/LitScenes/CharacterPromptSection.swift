import SwiftUI

/// SHEET PROMPT: the exact text the next sheet render transmits — composed from the
/// identity, or the operator's hand edit until they reset it.
struct CharacterPromptSection: View {
    let composedPrompt: String
    let handEditedPrompt: String?
    let hasDrift: Bool
    let isEditing: Bool
    @Binding var isExpanded: Bool
    @Binding var promptDraft: String
    var focus: FocusState<CharacterEditField?>.Binding
    var onBeginEdit: () -> Void
    var onCommit: () -> Void
    var onRequestReset: () -> Void
    var onCopy: () -> Void

    private var displayedPrompt: String { handEditedPrompt ?? composedPrompt }

    private var needsClamp: Bool {
        displayedPrompt.count > 480 || displayedPrompt.components(separatedBy: "\n").count > 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            if isEditing {
                editor
            } else {
                readOnlyBody
            }
            if hasDrift {
                driftRow
            }
        }
    }

    private var headerRow: some View {
        CharacterSectionHeader(title: "SHEET PROMPT") {
            HStack(spacing: 14) {
                Text(handEditedPrompt == nil ? "COMPOSED FROM IDENTITY" : "EDITED BY YOU")
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .kerning(1.0)
                    .foregroundStyle(handEditedPrompt == nil ? CanonColor.muted : CanonColor.softGold)
                if !isEditing {
                    CharacterCapsButton(title: "EDIT", help: "Edit the prompt the next sheet render transmits", action: onBeginEdit)
                }
                if handEditedPrompt != nil {
                    CharacterCapsButton(title: "RESET TO COMPOSED", help: "Discard the hand edit and follow the identity again", action: onRequestReset)
                }
                CharacterCapsButton(title: "COPY", help: "Copy the prompt", action: onCopy)
            }
        }
    }

    private var readOnlyBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if isExpanded {
                    Text(displayedPrompt)
                        .textSelection(.enabled)
                } else {
                    Text(displayedPrompt)
                        .lineLimit(needsClamp ? 8 : nil)
                }
            }
            .font(CanonType.interface(13))
            .lineSpacing(3)
            .foregroundStyle(CanonColor.bone.opacity(0.8))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                if !isExpanded, needsClamp {
                    LinearGradient(
                        colors: [CanonColor.archiveWell.opacity(0), CanonColor.archiveWell],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 44)
                    .allowsHitTesting(false)
                }
            }
            .padding(12)
            .background(CanonColor.archiveWell, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark))
            if needsClamp {
                CharacterCapsButton(
                    title: isExpanded ? "SHOW LESS" : "SHOW ALL · \(characterCountLabel(displayedPrompt.count))",
                    help: isExpanded ? "Collapse the prompt" : "Show the whole prompt"
                ) {
                    isExpanded.toggle()
                }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $promptDraft)
                .font(CanonType.interface(13))
                .lineSpacing(3)
                .foregroundStyle(CanonColor.bone)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 260)
                .padding(10)
                .background(CanonColor.archiveWell, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(focus.wrappedValue == .prompt ? CanonColor.brass.opacity(0.7) : CanonColor.hairlineDark))
                .focused(focus, equals: .prompt)
            HStack(spacing: 12) {
                Text("Renders exactly as written. Commits when you leave the field.")
                    .font(CanonType.interface(11.5))
                    .foregroundStyle(CanonColor.muted)
                Spacer(minLength: 0)
                CharacterCapsButton(title: "DONE", help: "Keep this prompt", action: onCommit)
            }
        }
    }

    private var driftRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(characterPromptDriftNote(hasDrift: true) ?? "")
                .font(CanonType.interface(12))
                .foregroundStyle(CanonColor.softGold)
                .fixedSize(horizontal: false, vertical: true)
            CharacterCapsButton(title: "RESET TO COMPOSED", help: "Rebuild the prompt from the identity", action: onRequestReset)
        }
    }
}
