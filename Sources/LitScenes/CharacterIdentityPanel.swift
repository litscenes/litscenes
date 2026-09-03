import AppKit
import SwiftUI

/// IDENTITY: the written half of the character — the appearance (editable,
/// committed on blur), the signature props, the refinements the conversation has
/// accumulated, and the story identity mirrored from the Story cast.
struct CharacterIdentityPanel: View {
    let character: ProjectCharacter
    let castMember: GoalCastMember?
    @Binding var appearanceDraft: String
    /// The gate's answer for this character: draft (blanks remain) or skip (filled).
    let draftDecision: CharacterIdentityDraftDecision
    let isDrafting: Bool
    var focus: FocusState<CharacterEditField?>.Binding
    var onCommitAppearance: () -> Void
    var onSetProps: ([String]) -> Void
    var onSetDirectives: ([String]) -> Void
    var onOpenStory: () -> Void
    var onDraft: () -> Void
    var onRedraft: () -> Void

    @State private var newProp = ""
    @State private var isAddingProp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CharacterSectionHeader(title: "IDENTITY") {
                if isDrafting {
                    Text("CASTING FROM THE STORY…")
                        .font(CanonType.archive(7.5, weight: .semibold))
                        .kerning(1.0)
                        .foregroundStyle(CanonColor.softGold)
                } else if case .draft = draftDecision {
                    CharacterCapsButton(title: "DRAFT FROM STORY →", help: "Fill the blank parts from the Goal, the other characters, and the source images", action: onDraft)
                } else {
                    CharacterCapsButton(title: "REDRAFT →", help: "Replace the appearance and props with a fresh draft from the story", action: onRedraft)
                }
            }
            appearanceEditor
            propsSection
            if !character.sheetDirectives.isEmpty {
                refinementsSection
            }
            if let castMember {
                storyIdentity(castMember)
            }
        }
        .onChange(of: focus.wrappedValue) { old, new in
            if old == .newProp, new != .newProp { commitProp() }
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(CanonType.archive(8, weight: .semibold))
            .kerning(1.4)
            .foregroundStyle(CanonColor.muted)
    }

    private var appearanceEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            eyebrow("APPEARANCE")
            TextEditor(text: $appearanceDraft)
                .font(CanonType.interface(14.5))
                .lineSpacing(3)
                .foregroundStyle(CanonColor.bone)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(8)
                .background(CanonColor.archiveWell, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(focus.wrappedValue == .appearance ? CanonColor.brass.opacity(0.7) : CanonColor.hairlineDark))
                .focused(focus, equals: .appearance)
        }
    }

    private var propsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            eyebrow("SIGNATURE PROPS")
            HStack(spacing: 6) {
                ForEach(character.signatureProps, id: \.self) { prop in
                    CharacterPropChip(text: prop) {
                        onSetProps(character.signatureProps.filter { $0 != prop })
                    }
                }
                if character.signatureProps.count < 3 {
                    if isAddingProp {
                        TextField("Signature prop", text: $newProp)
                            .textFieldStyle(.plain)
                            .font(CanonType.interface(12.5))
                            .foregroundStyle(CanonColor.bone)
                            .frame(width: 180)
                            .focused(focus, equals: .newProp)
                            .onSubmit(commitProp)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .overlay(Capsule().stroke(CanonColor.brass.opacity(0.7)))
                    } else {
                        CharacterCapsButton(title: "+ ADD", help: "Add a prop this character always carries or wears") {
                            isAddingProp = true
                            focus.wrappedValue = .newProp
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func commitProp() {
        let trimmed = newProp.trimmed
        newProp = ""
        isAddingProp = false
        guard !trimmed.isEmpty else { return }
        onSetProps(Array((character.signatureProps + [trimmed]).prefix(3)))
    }

    private var refinementsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                eyebrow("REFINEMENTS")
                Text("FROM THE CONVERSATION")
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .kerning(1.0)
                    .foregroundStyle(CanonColor.muted.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(character.sheetDirectives, id: \.self) { directive in
                    CharacterRefinementRow(text: directive) {
                        onSetDirectives(character.sheetDirectives.filter { $0 != directive })
                    }
                }
            }
        }
    }

    private func storyIdentity(_ member: GoalCastMember) -> some View {
        let identity = member.activeIdentity
        let rows: [(label: String, value: String)] = [
            ("FUNCTION", identity.publicFunction),
            ("WANTS", identity.desire),
            ("TELL", identity.signature),
        ].filter { !$0.value.trimmed.isEmpty }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                eyebrow("STORY IDENTITY")
                Spacer(minLength: 0)
                CharacterCapsButton(title: "OPEN STORY →", help: "The story identity is authored in the Story conversation", action: onOpenStory)
            }
            VStack(alignment: .leading, spacing: 5) {
                if !identity.essence.trimmed.isEmpty {
                    Text(identity.essence)
                        .font(CanonType.displayItalic(15.5))
                        .foregroundStyle(CanonColor.bone.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(rows, id: \.label) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.label)
                            .font(CanonType.archive(7.5, weight: .semibold))
                            .kerning(1.2)
                            .foregroundStyle(CanonColor.muted)
                            .frame(width: 64, alignment: .leading)
                        Text(row.value)
                            .font(CanonType.interface(13.5))
                            .foregroundStyle(CanonColor.bone.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CanonColor.archiveWell, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlineDark))
        }
    }
}

private struct CharacterPropChip: View {
    let text: String
    var onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            Text(text)
                .font(CanonType.interface(12.5))
                .foregroundStyle(CanonColor.bone.opacity(0.85))
                .lineLimit(1)
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(CanonColor.muted)
                }
                .buttonStyle(.plain)
                .help("Remove this prop")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().stroke(CanonColor.hairlineDark))
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
    }
}

private struct CharacterRefinementRow: View {
    let text: String
    var onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Rectangle()
                .fill(CanonColor.brass.opacity(0.6))
                .frame(width: 3, height: 12)
            Text(text)
                .font(CanonType.interface(13))
                .foregroundStyle(CanonColor.bone.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(CanonColor.muted)
                }
                .buttonStyle(.plain)
                .help("Drop this refinement from the sheet prompt")
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
