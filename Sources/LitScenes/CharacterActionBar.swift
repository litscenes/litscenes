import SwiftUI

/// The center column's pinned bar: the stack menu, the one brass pill, the
/// consequence in plain words, the state note, and the way forward.
struct CharacterActionBar: View {
    let copy: CharacterCastingCopy
    let stage: CharacterCastingStage
    let stacks: [RenderStack]
    let selectedStack: RenderStack?
    let credentialBlocker: (RenderStack) -> String?
    let nextStep: CharacterNextStep?
    let showsAppSettings: Bool
    var onSelectStack: (String) -> Void
    var onRender: () -> Void
    var onNextStep: (CharacterNextStep) -> Void
    var onOpenAppSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                Text("REFERENCE SHEET")
                    .font(CanonType.archive(8, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(CanonColor.muted)
                StyleStudioFlowLayout(spacing: 10) {
                    stackMenu
                    StageBrassPill(
                        title: copy.barTitle,
                        icon: "arrow.clockwise",
                        disabledReason: copy.disabledReason,
                        action: onRender
                    )
                    if let nextStep { nextStepButton(nextStep) }
                }
                noteColumn
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
        }
        .background(CanonColor.room)
    }

    private var stackMenu: some View {
        CharacterStackMenu(
            stacks: stacks,
            selectedStack: selectedStack,
            credentialBlocker: credentialBlocker,
            onSelect: onSelectStack,
            onOpenAppSettings: onOpenAppSettings
        )
    }

    private var noteColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(copy.consequence)
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.bone.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            if !copy.note.isEmpty {
                HStack(spacing: 8) {
                    if case .rendering = stage {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(CanonColor.brass)
                    }
                    Text(copy.note)
                        .font(CanonType.interface(11.5))
                        .foregroundStyle(castingToneColor(copy.noteTone))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if showsAppSettings {
                        CharacterCapsButton(title: "APP SETTINGS →", help: "Open App Settings", action: onOpenAppSettings)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nextStepButton(_ step: CharacterNextStep) -> some View {
        let title: String
        let help: String
        switch step {
        case .nextUncast(_, let name):
            title = "NEXT: \(name.uppercased()) →"
            help = "\(name) is not yet cast"
        case .continueToScenes:
            title = "ALL CAST · CONTINUE TO SCENES →"
            help = "Every character has a sheet"
        }
        return CharacterCapsButton(title: title, size: 8.5, help: help) { onNextStep(step) }
    }
}
