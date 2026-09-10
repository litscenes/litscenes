import SwiftUI

/// Explicit intent survives preparing, failure and retry on both entry points.
struct ShotContinuationReviewSession: Identifiable {
    enum Intent { case append, ending(String), retake(String) }
    let id = UUID()
    var intent: Intent
    var initial: ShotContinuationAvailability
    var entryId: String {
        switch intent { case .append: return ""; case .ending(let id), .retake(let id): return id }
    }
    var title: String {
        switch intent { case .append: return "Extend Scene"; case .ending: return "Render Ending"; case .retake: return "Render new take" }
    }
}

enum ShotReviewPalette {
    static let ink = Color(red: 0.125, green: 0.102, blue: 0.071)
    static let paper = Color(red: 0.965, green: 0.941, blue: 0.859)
    static let muted = ink.opacity(0.66)
}

/// One preparation lifecycle for the row and player. Keeping the review mounted
/// preserves the user's direction and target when local preparation needs retry.
struct ShotContinuationReviewSheet: View {
    let session: ShotContinuationReviewSession
    let configuredModels: Set<ShotRenderModel>
    let pricing: FALPricingSnapshot?
    var prepare: () async -> ShotContinuationAvailability
    var onPrecedingEnding: (String) -> Void
    var onCancel: () -> Void
    var onRender: (ShotContinuationRequest) -> Void
    @State private var availability: ShotContinuationAvailability
    @State private var preparing = true
    @State private var revision = UUID()

    init(session: ShotContinuationReviewSession, configuredModels: Set<ShotRenderModel>, pricing: FALPricingSnapshot?,
         prepare: @escaping () async -> ShotContinuationAvailability, onPrecedingEnding: @escaping (String) -> Void,
         onCancel: @escaping () -> Void, onRender: @escaping (ShotContinuationRequest) -> Void) {
        self.session = session; self.configuredModels = configuredModels; self.pricing = pricing
        self.prepare = prepare; self.onPrecedingEnding = onPrecedingEnding; self.onCancel = onCancel; self.onRender = onRender
        _availability = State(initialValue: session.initial)
    }

    var body: some View {
        ShotContinuationReviewView(availability: availability, configuredModels: configuredModels, pricing: pricing,
            title: session.title, isPreparing: preparing, onRefresh: { revision = UUID() },
            onPrecedingEnding: onPrecedingEnding, onCancel: onCancel, onRender: onRender)
            .task(id: revision) {
                preparing = true
                let prepared = await prepare()
                guard !Task.isCancelled else { return }
                availability = prepared
                preparing = false
            }
            .id(session.id)
    }
}

func shotEndingReviewPreview(shot: ProjectShot, entryId: String, frameLookup: [String: ProjectLensHeroImage]) -> ShotContinuationAvailability {
    let take = shot.continuationRecord(entryId: entryId)?.selectedTake
    let entry = shot.entries.first { $0.entryId == entryId }
    let frame = entry.flatMap { frameLookup[$0.frameImageId] }
    var value = ShotContinuationAvailability(outFrameStack: take?.renderStack ?? shot.renderStack,
        suggestedPrompt: take?.prompt ?? "")
    value.anchor = take?.anchor
    value.targetFrame = take?.targetFrame ?? frame.map {
        ShotContinuationTargetFrame(entryId: entryId, imageId: $0.imageId, imagePath: $0.imagePath, fingerprint: "", label: $0.label)
    }
    return value
}


struct ShotReviewOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(CanonType.archive(9, weight: .semibold))
            .foregroundStyle(ShotReviewPalette.ink).padding(.horizontal, 14).padding(.vertical, 9)
            .background(ShotReviewPalette.paper.opacity(configuration.isPressed ? 0.7 : 1))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(ShotReviewPalette.ink.opacity(0.65)))
    }
}
