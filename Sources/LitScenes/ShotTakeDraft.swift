import Foundation

/// An editable recipe for another attempt, owned by a placement and an immutable
/// base take. Inspecting or editing it never changes the film's take selection.
struct ShotTakeDraft: Codable, Hashable, Sendable, Identifiable {
    var placementKey: String
    var startFrameImageId: String
    var endFrameImageId: String
    var startEntryId: String
    var endEntryId: String
    var baseClipPath: String
    var baseTakeId: String
    var baseTakeNumber: Int
    var prompt: String
    var mode: ShotSegmentPromptMode
    var stack: String
    var directionPlan: ShotTemporalDirectionPlan?
    var resolution: String? = nil
    var updatedAt: String = ""

    var id: String { placementKey + "|" + (baseTakeId.nilIfEmpty ?? baseClipPath.nilIfEmpty ?? "unrendered") }
    var renderStack: ShotRenderStack? { ShotRenderStack(rawValue: stack) }
    var promptDraft: ShotPromptDraft { ShotPromptDraft(text: prompt, mode: mode) }

    init(shot: ProjectShot, item: ShotSegmentPromptPlanItem, option: ShotTakeOption?, savedOnly: Bool = false) {
        placementKey = item.pair.placementKey
        startFrameImageId = item.pair.start?.imageId ?? ""
        endFrameImageId = item.pair.end?.imageId ?? ""
        startEntryId = item.pair.startPlacementEntryId
        endEntryId = item.pair.endPlacementEntryId
        baseClipPath = option?.clipPath ?? ""
        baseTakeNumber = option?.takeNumber ?? 0
        baseTakeId = ""
        var savedStack: ShotRenderStack? = nil
        if case .continuation(let entryId, let takeId) = option?.source {
            baseTakeId = takeId
            savedStack = shot.continuationRecord(entryId: entryId)?.takes.first { $0.takeId == takeId }
                .flatMap { ShotRenderStack(rawValue: $0.stack) }
        }
        if let clip = option?.clip {
            if let recipe = clip.civitaiRecipe { savedStack = .civitai(recipe) }
            else if savedStack == nil, let model = (ShotRenderModel.allCases + [.klingV26Pro]).first(where: { model in
                let candidate = ShotRenderStack.recipe(model: model, durationSeconds: max(clip.requestedDurationSeconds, 1))
                return (clip.provider.isEmpty || clip.provider == candidate.providerSelection.rawValue)
                    && [candidate.openEndedModelSelection.providerModelId, candidate.pairedModelSelection.providerModelId, model.label].contains(clip.model)
            }) {
                savedStack = .recipe(model: model, durationSeconds: max(clip.requestedDurationSeconds, 1), generateAudio: clip.generateAudio)
            }
            let candidate = clip.resolution.split(separator: " ").first.map(String.init)?.uppercased() ?? ""
            if let savedStack, Hailuo3ResolutionPreference.choices(for: savedStack.model).contains(candidate) { resolution = candidate }
        }
        let selectedTakeId = baseTakeId
        if !selectedTakeId.isEmpty, let take = shot.continuationRecord(entryId: endEntryId)?.takes.first(where: { $0.takeId == selectedTakeId }) {
            resolution = take.resolutionOverride ?? resolution
        }
        let legacy = !savedOnly && (option == nil || option?.isInFilm == true)
        prompt = legacy ? (item.overridePrompt ?? option?.prompt ?? item.effectivePrompt) : (option?.prompt ?? item.effectivePrompt)
        stack = legacy && item.hasRenderOverride ? item.renderStack.rawValue : (savedStack?.rawValue ?? (option == nil ? item.renderStack.rawValue : ""))
        directionPlan = legacy ? (item.directionPlan?.plan ?? option?.clip?.directionPlan) : option?.clip?.directionPlan
        mode = legacy && item.directionPlan != nil ? item.promptMode : (directionPlan == nil ? .raw : .beats)
    }

    func applying(to item: ShotSegmentPromptPlanItem) -> ShotSegmentPromptPlanItem {
        var value = item
        if let renderStack { value.renderStack = renderStack }
        value.overridePrompt = prompt
        value.hasRenderOverride = true
        value.resolutionOverride = resolution
        value.compiledDirection = nil
        var record = item.directionPlan ?? ShotSegmentDirectionPlanRecord(
            startFrameImageId: startFrameImageId, endFrameImageId: endFrameImageId,
            placementStartEntryId: startEntryId, placementEndEntryId: endEntryId)
        record.promptMode = mode.rawValue
        if let directionPlan { record.plan = directionPlan }
        value.directionPlan = record
        if mode == .beats, let selection = value.renderStack.modelSelection(for: value.pair), let directionPlan {
            value.compiledDirection = compileTemporalDirection(plan: directionPlan, modelSelection: selection,
                durationSeconds: value.renderStack.segmentSeconds)
            value.generatedPrompt = value.compiledDirection?.canonicalText ?? prompt
        }
        return value
    }

    /// Recipe projection only: film selections and saved artifacts are untouched.
    func applyingRecipe(to shot: ProjectShot) -> ProjectShot {
        var value = shot
        value.takeDrafts.removeAll { $0.placementKey == placementKey }
        value.segmentPromptOverrides.removeAll { $0.placementStartEntryId == startEntryId && $0.placementEndEntryId == endEntryId }
        value.segmentPromptOverrides.append(ShotSegmentPromptOverride(startFrameImageId: startFrameImageId,
            endFrameImageId: endFrameImageId, placementStartEntryId: startEntryId,
            placementEndEntryId: endEntryId, prompt: prompt))
        value.segmentRenderOverrides.removeAll { $0.placementStartEntryId == startEntryId && $0.placementEndEntryId == endEntryId }
        value.segmentRenderOverrides.append(ShotSegmentRenderOverride(startFrameImageId: startFrameImageId,
            endFrameImageId: endFrameImageId, placementStartEntryId: startEntryId,
            placementEndEntryId: endEntryId, stack: stack))
        value.segmentDirectionPlans.removeAll { $0.directionKey == placementKey }
        value.segmentDirectionPlans.append(ShotSegmentDirectionPlanRecord(startFrameImageId: startFrameImageId,
            endFrameImageId: endFrameImageId, placementStartEntryId: startEntryId,
            placementEndEntryId: endEntryId, plan: directionPlan ?? ShotTemporalDirectionPlan(), promptMode: mode.rawValue))
        return value
    }
}

/// Kept outside the already large plan builder so legacy plans do not allocate
/// a second recipe and take catalog on each generated-placement stack frame.
func applyStoredShotTakeDraft(to item: inout ShotSegmentPromptPlanItem, shot: ProjectShot) {
    let clip = shotSavedSegmentClip(shot: shot, pair: item.pair)
    let takeId = shot.continuationRecord(entryId: item.pair.endPlacementEntryId)?.selectedTakeId.nilIfEmpty
    let key = item.pair.placementKey + "|" + (takeId ?? clip?.clipPath.nilIfEmpty ?? "unrendered")
    guard let draft = shot.takeDrafts.first(where: { $0.id == key }) else { return }
    item = draft.applying(to: item)
}
