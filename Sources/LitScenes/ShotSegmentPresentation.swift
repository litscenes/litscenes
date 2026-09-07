import Foundation

/// Read-only saved media resolution. File availability is a separate concern:
/// a missing input or file never changes which take the operator selected.
func shotSavedSegmentClip(shot: ProjectShot, pair: ShotRenderPair) -> ShotRenderSegmentClip? {
    shotSavedSegmentClip(shot: shot,
        startEntryId: pair.startPlacementEntryId, endEntryId: pair.endPlacementEntryId,
        startFrameId: pair.start?.imageId ?? "", endFrameId: pair.end?.imageId ?? "")
}

func shotSavedSegmentClip(
    shot: ProjectShot, startEntryId: String, endEntryId: String,
    startFrameId: String, endFrameId: String
) -> ShotRenderSegmentClip? {
    if let selected = shot.continuationRecord(entryId: endEntryId)?.selectedTake?.segmentClip { return selected }
    if let rendered = shot.playableRenderVersion?.segmentClip(
        placementStartEntryId: startEntryId, placementEndEntryId: endEntryId,
        forStart: startFrameId, end: endFrameId) { return rendered }
    if !startEntryId.isEmpty || !endEntryId.isEmpty,
       let seed = shot.seedSegmentClips.first(where: {
           $0.placementStartEntryId == startEntryId && $0.placementEndEntryId == endEntryId
       }) { return seed }
    return shot.seedSegmentClips.first {
        $0.placementStartEntryId.isEmpty && $0.placementEndEntryId.isEmpty
            && $0.startFrameImageId == startFrameId && $0.endFrameImageId == endFrameId
    }
}

struct ShotSegmentPreview: Hashable {
    var clip: ShotRenderSegmentClip
    /// Raw imported footage keeps its placed range; saved generated clips
    /// already represent their complete source segment.
    var sourceStartSeconds: Double = 0
    var sourceEndSeconds: Double? = nil
    var durationSeconds: Double {
        sourceEndSeconds.map { max($0 - sourceStartSeconds, 0) }
            ?? (clip.durationSeconds > 0 ? clip.durationSeconds : Double(clip.requestedDurationSeconds))
    }
}

struct ShotSegmentPresentation: Identifiable {
    var id: String
    var title: String
    var preview: ShotSegmentPreview?
    var record: ShotContinuationRecord?
    var isPlayable: Bool
    var clip: ShotRenderSegmentClip? { preview?.clip }

    init(record: ShotContinuationRecord,
         fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.record = record
        preview = record.selectedTake?.segmentClip.map { ShotSegmentPreview(clip: $0) }
        id = preview?.clip.placementKey ?? record.entryId
        title = record.selectedTake?.targetFrame == nil ? "Continuation" : "Ending"
        isPlayable = preview.map { !$0.clip.clipPath.isEmpty && fileExists($0.clip.clipPath) } ?? false
    }

    init(shot: ProjectShot, segment: ShotRenderPlanSegment,
         fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        record = nil
        switch segment {
        case .generated(let item):
            id = item.pair.placementKey
            record = shot.continuationRecord(entryId: item.pair.endPlacementEntryId)
            title = item.isAIExtension ? (item.pair.end == nil ? "Continuation" : "Ending") : "Generated"
            preview = shotSavedSegmentClip(shot: shot, pair: item.pair).map { ShotSegmentPreview(clip: $0) }
        case .preserved(let source):
            id = source.placementKey
            title = "Saved source"
            preview = ShotSegmentPreview(clip: source.clip)
        case .footage(let source):
            id = source.placementKey
            title = "Footage"
            if let saved = shotSavedSegmentClip(shot: shot, startEntryId: source.clip.entryId,
                endEntryId: "", startFrameId: source.clip.footageKey, endFrameId: "") {
                preview = ShotSegmentPreview(clip: saved)
            } else {
                let clip = ShotRenderSegmentClip(startFrameImageId: source.clip.footageKey,
                    placementStartEntryId: source.clip.entryId, clipPath: source.clip.path,
                    provider: "footage", model: "source", durationSeconds: source.clip.resolvedDurationSeconds)
                preview = ShotSegmentPreview(clip: clip, sourceStartSeconds: source.clip.resolvedStartSeconds,
                    sourceEndSeconds: source.clip.assetDurationSeconds > 0 ? source.clip.resolvedEndSeconds : nil)
            }
        case .artifactFallback(let source):
            id = shotArtifactSegmentKey(versionId: source.versionId)
            title = "Saved whole-Shot video"
            let artifact = shot.renderVersions.first { $0.versionId == source.versionId }
            preview = ShotSegmentPreview(clip: ShotRenderSegmentClip(clipPath: source.videoPath,
                provider: artifact?.provider ?? "", model: artifact?.model ?? "", durationSeconds: source.durationSeconds))
        }
        isPlayable = preview.map { !$0.clip.clipPath.isEmpty && fileExists($0.clip.clipPath) } ?? false
    }
}

/// A row action may address only its own ending, even if other destinations
/// are pending elsewhere in this Shot.
func shotPendingEndingForRender(shot: ProjectShot, segments: [ShotRenderPlanSegment], keys: Set<String>?) -> String? {
    let pending = shotPendingEndingEntryIds(shot)
    for case .generated(let item) in segments where pending.contains(item.pair.endPlacementEntryId) {
        if keys.map({ $0.contains(item.pair.placementKey) || $0.contains(item.pair.segmentKey) }) ?? true {
            return item.pair.endPlacementEntryId
        }
    }
    return nil
}
