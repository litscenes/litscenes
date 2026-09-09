import Foundation

/// Operational state never changes the selected media or the Shot's structure.
enum ShotWorkStage: String, Codable, Sendable {
    case queued, preparing, rendering, finishing, saved, failed, canceled, interrupted, notStarted
    var label: String {
        switch self {
        case .notStarted: return "Not started"
        default: return rawValue.capitalized
        }
    }
    var isWorking: Bool { [.preparing, .rendering, .finishing].contains(self) }
    var isPending: Bool { isWorking || self == .queued }
}

struct WorkflowSegmentProgress: Codable, Hashable, Sendable, Identifiable {
    var placementKey: String
    var startEntryId: String = ""
    var endEntryId: String = ""
    var ordinal: Int = 1
    var segmentCount: Int = 1
    var title: String = "Video"
    var versionId: String = ""
    var takeId: String = ""
    var takeNumber: Int? = nil
    var inputFrameIds: [String]? = nil
    var provider: String = ""
    var model: String = ""
    var durationSeconds: Double = 0
    var isGeneration: Bool = true
    var stageName: String = ShotWorkStage.queued.rawValue
    var startedAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()
    var errorMessage: String = ""
    var id: String { placementKey }
    var stage: ShotWorkStage {
        get { ShotWorkStage(rawValue: stageName) ?? .interrupted }
        set { stageName = newValue.rawValue }
    }
    var label: String {
        "Segment \(ordinal) of \(segmentCount) · \(stage.label)"
            + (takeNumber.map { " · Take \($0)" } ?? "")
    }
}

struct ShotWorkPresentation {
    var jobId = ""
    var phase = ""
    var isActive = false
    var segments: [WorkflowSegmentProgress] = []
    var currentSegments: [WorkflowSegmentProgress] = []

    init(jobs: [WorkflowJob], shotId: String, projectId: String? = nil) {
        let matches = jobs.filter { $0.artifactId == shotId && $0.artifactType == "shot"
            && (projectId == nil || $0.projectId == projectId)
            && ($0.segmentProgress != nil || $0.workflow == "shot_render" || $0.workflow == "scene_extension"
                || $0.workflow == "continuation_retake" || $0.workflow == "rechain"
                || $0.workflow == "rebuild_shot") }
            .sorted { $0.createdAt > $1.createdAt }
        let current = matches.first { [.queued, .running, .stopping].contains($0.state) } ?? matches.first
        if let current {
            jobId = current.id
            isActive = [.queued, .running, .stopping].contains(current.state)
            currentSegments = current.segmentProgress ?? []
            let active = currentSegments.first { $0.stage.isWorking }
            phase = current.state == .pausedAutomatically ? "Interrupted"
                : isActive && !currentSegments.isEmpty && currentSegments.allSatisfy({ $0.stage == .saved }) ? "Finishing Shot"
                : isActive && active != nil ? active!.stage.label
                : current.state == .queued ? "Queued"
                : isActive ? "Rendering" : current.state.label
        }
        var seen: Set<String> = []
        // Retain the latest attempt for each placement, including a failed sibling.
        for job in matches {
            for var segment in job.segmentProgress ?? [] where seen.insert(segment.placementKey).inserted {
                if segment.stage.isPending {
                    if job.state == .pausedAutomatically { segment.stage = .interrupted }
                    else if job.state.isTerminal { segment.stage = job.state == .canceled ? .canceled : .notStarted }
                }
                segments.append(segment)
            }
        }
    }

    func segment(_ key: String) -> WorkflowSegmentProgress? { segments.first { $0.placementKey == key } }
    var label: String {
        if let active = segments.first(where: { $0.stage.isWorking }) { return active.label }
        if isActive, let queued = segments.first(where: { $0.stage == .queued }) { return queued.label }
        return phase
    }
}

func shotWorkflowSegment(_ segment: ShotRenderPlanSegment, count: Int, versionId: String = "") -> WorkflowSegmentProgress? {
    switch segment {
    case .generated(let item):
        return WorkflowSegmentProgress(placementKey: item.pair.placementKey,
            startEntryId: item.pair.startPlacementEntryId, endEntryId: item.pair.endPlacementEntryId,
            ordinal: item.displayIndex + 1, segmentCount: count,
            title: item.isAIExtension ? (item.pair.end == nil ? "Continuation" : "Ending") : "Video",
            versionId: versionId, takeId: item.continuationTakeId,
            inputFrameIds: [item.pair.start?.imageId, item.pair.end?.imageId].compactMap { $0 },
            provider: item.renderStack.providerSelection.rawValue, model: item.renderStack.model.label,
            durationSeconds: Double(item.renderStack.segmentSeconds))
    case .footage(let item):
        return WorkflowSegmentProgress(placementKey: item.placementKey, startEntryId: item.clip.entryId,
            ordinal: item.displayIndex + 1, segmentCount: count, title: "Footage", versionId: versionId,
            provider: "local", model: "Source footage", durationSeconds: item.clip.resolvedDurationSeconds,
            isGeneration: false)
    case .preserved, .artifactFallback: return nil
    }
}
