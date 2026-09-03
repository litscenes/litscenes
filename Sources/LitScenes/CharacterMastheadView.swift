import SwiftUI

/// The character's name (editable, committed on blur) with the story's one-line
/// role and the casting status beneath — the only place the name appears in the
/// center column.
struct CharacterMastheadView: View {
    let publicFunction: String
    let status: String
    let statusTone: CharacterCastingTone
    @Binding var nameDraft: String
    var focus: FocusState<CharacterEditField?>.Binding
    var onCommitName: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                TextField("Name", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(CanonType.display(28, weight: .semibold))
                    .foregroundStyle(CanonColor.bone)
                    .focused(focus, equals: .name)
                    .onSubmit(onCommitName)
                Rectangle()
                    .fill(focus.wrappedValue == .name ? CanonColor.brass : CanonColor.hairlineDark)
                    .frame(height: focus.wrappedValue == .name ? 1.2 : 0.5)
            }
            statusLine
        }
    }

    private var statusLine: some View {
        let function = publicFunction.trimmed
        var line = Text("")
        if !function.isEmpty {
            line = line
                + Text(function)
                    .font(CanonType.displayItalic(14.5))
                    .foregroundColor(CanonColor.bone.opacity(0.92))
                + Text("   ·   ")
                    .font(CanonType.archive(8, weight: .semibold))
                    .foregroundColor(CanonColor.muted)
        }
        line = line
            + Text(status)
                .font(CanonType.archive(8.5, weight: .semibold))
                .kerning(1.0)
                .foregroundColor(castingToneColor(statusTone))
        return line
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
