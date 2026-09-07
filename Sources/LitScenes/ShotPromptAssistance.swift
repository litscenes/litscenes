import Foundation

enum ShotPromptAssistanceIntent: String, Codable, Sendable {
    case improve, suggest
    var label: String { self == .improve ? "Improve" : "Suggest" }
    var progressLabel: String { self == .improve ? "Improving…" : "Suggesting…" }
}

struct ShotPromptDraft: Equatable, Sendable {
    var text: String
    var mode: ShotSegmentPromptMode = .raw

    static func current(item: ShotSegmentPromptPlanItem, text: String?, mode: ShotSegmentPromptMode) -> Self {
        if mode == .beats, let plan = item.directionPlan?.plan,
           let selection = item.renderStack.modelSelection(for: item.pair),
           let compiled = compileTemporalDirection(plan: plan, modelSelection: selection,
               durationSeconds: item.renderStack.segmentSeconds) {
            return Self(text: compiled.canonicalText, mode: mode)
        }
        return Self(text: text ?? item.effectivePrompt, mode: mode)
    }
}

struct ShotPromptDraftUpdate: Sendable {
    var override: ShotSegmentPromptOverride
    var mode: ShotSegmentPromptMode
    var key: String {
        shotPlacementSegmentKey(startEntryId: override.placementStartEntryId, endEntryId: override.placementEndEntryId,
            legacyStartId: override.startFrameImageId, legacyEndId: override.endFrameImageId)
    }
    init(item: ShotSegmentPromptPlanItem, draft: ShotPromptDraft) {
        override = ShotSegmentPromptOverride(startFrameImageId: item.pair.start?.imageId ?? "",
            endFrameImageId: item.pair.end?.imageId ?? "", placementStartEntryId: item.pair.startPlacementEntryId,
            placementEndEntryId: item.pair.endPlacementEntryId, prompt: draft.text)
        mode = draft.mode
    }
}

extension ProjectShot {
    /// Text and timing authority travel in one saved document. Legacy shared
    /// records remain available to other placements of the same Frame pair.
    func applyingPromptDrafts(_ updates: [ShotPromptDraftUpdate], now: String) -> ProjectShot {
        var prompts = segmentPromptOverrides
        var plans = segmentDirectionPlans
        for update in updates where !update.override.prompt.trimmed.isEmpty {
            var prompt = update.override
            prompt.updatedAt = now
            prompts = mergedAutosavePromptOverrides(existing: prompts, computed: [prompt])
            if var record = plans.first(where: { $0.directionKey == update.key }) ?? plans.first(where: {
                $0.placementStartEntryId.isEmpty && $0.placementEndEntryId.isEmpty
                    && $0.startFrameImageId == prompt.startFrameImageId && $0.endFrameImageId == prompt.endFrameImageId
            }) {
                record.placementStartEntryId = prompt.placementStartEntryId
                record.placementEndEntryId = prompt.placementEndEntryId
                record.startFrameImageId = prompt.startFrameImageId
                record.endFrameImageId = prompt.endFrameImageId
                record.promptMode = update.mode.rawValue
                record.updatedAt = now
                plans = mergedAutosaveDirectionPlans(existing: plans, computed: [record])
            }
        }
        guard !promptOverridesAgree(prompts, segmentPromptOverrides) || !directionPlansAgree(plans, segmentDirectionPlans) else { return self }
        return settingSegmentPromptOverrides(prompts, now: now).settingSegmentDirectionPlans(plans, now: now)
    }
}

struct ShotPromptAssistanceRequest: Codable, Sendable {
    var requestId = UUID().uuidString
    var shotId: String
    var segmentKey: String
    var intent: ShotPromptAssistanceIntent
    var operatorPrompt: String
    var renderStack: String
    var context: ShotDirectionPlanDraftContext
    var sourceIdentity: String

    init(shot: ProjectShot, item: ShotSegmentPromptPlanItem, intent: ShotPromptAssistanceIntent, text: String) {
        shotId = shot.shotId
        segmentKey = item.pairKey
        self.intent = intent
        operatorPrompt = intent == .improve ? text : ""
        renderStack = item.renderStack.rawValue
        context = shotDirectionPlanDraftContext(shot: shot, pair: item.pair, segmentSeconds: item.renderStack.segmentSeconds)
        sourceIdentity = sha256Hex(Data([
            shotDirectionPlanInputsFingerprint(context: context), renderStack, item.continuationTakeId,
            item.continuationAnchor?.anchorFingerprint ?? "", item.pair.start?.imagePath ?? "", item.pair.end?.imagePath ?? ""
        ].joined(separator: "|").utf8))
    }

    var providerPrompt: String {
        let instruction = intent == .improve
            ? "Improve the operator's direction. Preserve its intended action, subjects, tone and explicit camera/cut choices. Clarify motion and camera wording without substituting a different idea."
            : "Suggest a fresh direction from the available context. Choose plausible motion and camera direction within the supplied anchors; do not invent new subjects or unrelated scene elements."
        let stack = ShotRenderStack(rawValue: renderStack) ?? .fallback
        let anchorRule = context.startImageId.isEmpty
            ? "Arrive at the ending Frame."
            : (context.endImageId.isEmpty ? "Begin at the starting Frame; the ending is open." : "Begin at the starting Frame and arrive at the ending Frame.")
        return [
            "Write the video-generation prompt for one \(context.segmentSeconds)-second segment using \(stack.shortLabel).",
            instruction, anchorRule,
            "Use available Frame descriptions as context; concentrate on action and camera movement. Do not add cuts unless explicitly requested. Sparse descriptions are acceptable: keep the direction restrained and do not claim unseen details.",
            "Return only the prompt field in the requested schema. Its value is editable direction, without headings, explanations or alternative options.",
            "Starting Frame description: \(context.startFrameGist)", "Ending Frame description: \(context.endFrameGist)",
            "Frame relationship: \(context.lineageSentence)",
            "Narration context: \([context.narrationTitle, context.narrationBody].filter { !$0.isEmpty }.joined(separator: "\n"))",
            intent == .improve ? "Operator direction to preserve:\n\(operatorPrompt)" : ""
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

struct ShotPromptAssistanceResponse: Codable, Sendable {
    var prompt: String
    static func decode(_ text: String) throws -> Self {
        let response = try JSONCoding.decoder.decode(Self.self, from: Data(text.utf8))
        guard !response.prompt.trimmed.isEmpty else { throw ScreenGraphError.openAI("Prompt assistance returned an empty prompt.") }
        return Self(prompt: response.prompt.trimmed)
    }
}

enum ShotPromptAssistanceOutcome: Sendable, WorkflowOutcomeReporting {
    case ready(String)
    case failed(String)
    var workflowSucceeded: Bool { if case .ready = self { return true }; return false }
}
