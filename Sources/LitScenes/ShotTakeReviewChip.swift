import SwiftUI

/// The player's own account of what it is showing while a take is under
/// review — which segment, which take, whether it is in the film — with the
/// one mutation (USE IN FILM) and the way back (FULL SHOT) beside it, so the
/// state is legible in the picture, not only in the panel.
struct ShotTakeReviewChip: View {
    let title: String
    var onUse: (() -> Void)? = nil
    var onCompare: (() -> Void)? = nil
    var onFullShot: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            PlateLabel(text: title, size: 8.5, weight: .bold, color: PlateColor.ink)
                .lineLimit(1)
            if let onUse {
                Button("Use in Film", action: onUse)
                    .buttonStyle(PlateButtonStyle(isProminent: true))
                    .help("Put this take in the film — free, and ⌘Z brings the previous take back")
            }
            Button("Full Shot", action: onFullShot)
                .buttonStyle(PlateButtonStyle())
                .help("Return the player to the full shot")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(PlateColor.cream.opacity(0.94)))
        .overlay(Capsule().stroke(PlateColor.hairline, lineWidth: 1))
        .padding(.top, 10)
    }
}

/// The shared "use this take?" confirmation for both take universes. A pick
/// that would leave later continuations stale names them before offering the
/// separately priced rechain; a clean pick confirms for $0.
struct ShotTakeImpactPrompt: Equatable {
    var option: ShotTakeOption
    var resolution: ShotContinuationBranchResolution
}

struct ShotTakeImpactDialog: ViewModifier {
    @Binding var prompt: ShotTakeImpactPrompt?
    var rechainEstimate: ([String]) -> ShotRenderCostEstimate
    var isRendering: Bool
    var onUse: (ShotTakeOption) -> Void
    var onUseAndRechain: (ShotTakeOption, [String]) -> Void

    private var title: String {
        guard let prompt else { return "Use this take?" }
        switch prompt.resolution {
        case .selectCurrent:
            return "Use Take \(prompt.option.takeNumber) in the film?"
        case .rechain(let ids):
            return "This changes \(ids.count) downstream continuation\(ids.count == 1 ? "" : "s")"
        }
    }

    private var message: String {
        guard let prompt else { return "" }
        switch prompt.resolution {
        case .selectCurrent:
            return "Play and export follow the selected take; no render version or provider request is created. ⌘Z brings the previous take back."
        case .rechain(let ids):
            return "Keeping later clips preserves them but marks their anchors stale. Rechain generates \(ids.count) new linked take\(ids.count == 1 ? "" : "s") in order; completed links remain resumable if a later one fails."
        }
    }

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
            titleVisibility: .visible
        ) {
            if let prompt {
                switch prompt.resolution {
                case .selectCurrent:
                    Button("Use Take · $0") { onUse(prompt.option); self.prompt = nil }
                case .rechain(let staleEntryIds):
                    let estimate = rechainEstimate(staleEntryIds)
                    Button("Use Take · Keep Later Clips") { onUse(prompt.option); self.prompt = nil }
                    Button("Use & Rechain · \(estimate.headlineLabel ?? "RATE UNAVAILABLE")") {
                        onUseAndRechain(prompt.option, staleEntryIds); self.prompt = nil
                    }
                    .disabled(isRendering || !estimate.canReview)
                }
                Button("Cancel", role: .cancel) { self.prompt = nil }
            }
        } message: {
            Text(message)
        }
    }
}
