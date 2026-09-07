import SwiftUI

/// One field owns the next prompt. Assistance returns text; applying it is
/// a separate local edit, so late responses cannot overwrite current work.
struct ShotSegmentPromptEditor<RenderAction: View>: View {
    let shot: ProjectShot
    let item: ShotSegmentPromptPlanItem
    @Binding var draft: ShotPromptDraft
    var canAssist: Bool
    var onAssist: (ShotPromptAssistanceRequest) async -> ShotPromptAssistanceOutcome
    @ViewBuilder var renderAction: () -> RenderAction

    @State private var requestId: UUID?
    @State private var intent: ShotPromptAssistanceIntent = .suggest
    @State private var contextRevision = 0
    @State private var candidate: String?
    @State private var error = ""
    @State private var undoDrafts: [ShotPromptDraft] = []

    private var sourceIdentity: String {
        ShotPromptAssistanceRequest(shot: shot, item: item, intent: .suggest, text: "").sourceIdentity
    }
    private var revertText: String {
        shotSavedSegmentClip(shot: shot, pair: item.pair)?.prompt.trimmed.nilIfEmpty
            ?? shotSegmentPrompt(pair: item.pair)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ShotEditorFlow(spacing: 8) {
                renderAction()
                HStack(spacing: 8) {
                    assistanceLink(.improve)
                    assistanceLink(.suggest)
                    Button("Revert") { replacePrompt(revertText) }
                        .disabled(draft.text == revertText)
                        .help("Restore the saved take's prompt, or the initial direction for an unrendered segment")
                    if !undoDrafts.isEmpty {
                        Button("Undo") {
                            if let previous = undoDrafts.popLast() { draft = previous; candidate = nil; error = "" }
                        }.help("Undo the last prompt replacement, including its timing mode")
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
                .foregroundStyle(CanonColor.ink.opacity(0.8))
                .fixedSize()
                .frame(minHeight: 30)
            }
            if !canAssist {
                Text("Improve and Suggest need text AI configured in App Settings.")
                    .font(.caption).foregroundStyle(CanonColor.ink.opacity(0.65))
            }
            if !error.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(error).font(.caption).foregroundStyle(CanonColor.rust)
                    Button("Retry") { start(intent) }.buttonStyle(.plain).disabled(!canAssist || requestId != nil)
                }
            }
            if let candidate {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Suggestion ready · your text or segment changed while it was drafting.").font(.caption)
                    Text(candidate).font(.caption).lineLimit(4)
                    HStack {
                        Button("Apply") { replacePrompt(candidate); self.candidate = nil }
                        Button("Dismiss") { self.candidate = nil }
                    }.buttonStyle(.plain)
                }.padding(8).background(CanonColor.softGold.opacity(0.18))
            }
            if item.directionPlan?.plan.shotMode == .multiShot {
                Text(draft.mode == .beats
                    ? "Saved shot timing is retained. Editing this field uses text direction for the next render."
                    : "The next render uses text direction; the saved timing remains retained.")
                    .font(.caption).foregroundStyle(CanonColor.ink.opacity(0.65))
            }
            TextEditor(text: Binding(get: { draft.text }, set: { draft = ShotPromptDraft(text: $0) }))
                .font(PlateType.label(11.5, weight: .regular))
                .foregroundStyle(CanonColor.ink)
                .scrollContentBackground(.hidden)
                .frame(height: 110)
                .padding(7)
                .background(CanonColor.paperInset.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(CanonColor.hairlinePaper))
                .environment(\.colorScheme, .light)
        }
        .onChange(of: sourceIdentity) { _, _ in contextRevision += 1 }
        .onDisappear { requestId = nil }
    }

    private func assistanceLink(_ action: ShotPromptAssistanceIntent) -> some View {
        Button(requestId != nil && intent == action ? action.progressLabel : action.label) { start(action) }
            .disabled(!canAssist || requestId != nil || (action == .improve && draft.text.trimmed.isEmpty))
            .help(action == .improve
                ? "Use text AI to clarify your written direction while preserving its intent; no video is generated"
                : "Use text AI to suggest a fresh direction from the segment's Frames and context; no video is generated")
    }

    private func replacePrompt(_ text: String) {
        undoDrafts.append(draft)
        if undoDrafts.count > 20 { undoDrafts.removeFirst() }
        draft = ShotPromptDraft(text: text)
        error = ""
    }

    private func start(_ action: ShotPromptAssistanceIntent) {
        guard requestId == nil, canAssist, action != .improve || !draft.text.trimmed.isEmpty else { return }
        let token = UUID()
        requestId = token
        intent = action
        error = ""
        candidate = nil
        let original = draft
        let revision = contextRevision
        let request = ShotPromptAssistanceRequest(shot: shot, item: item, intent: action, text: original.text)
        Task { @MainActor in
            let outcome = await onAssist(request)
            guard requestId == token else { return }
            requestId = nil
            switch outcome {
            case .ready(let text):
                if draft == original && contextRevision == revision { replacePrompt(text) }
                else { candidate = text }
            case .failed(let message): error = message
            }
        }
    }
}
