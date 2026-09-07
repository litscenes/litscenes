import Foundation

/// Compatibility repair uses durable ancestry, never timestamps or media names.
/// It runs only for pre-preservation documents, before ordinary editing begins.
func recoveringLegacyShotContinuations(_ original: ProjectShot) -> ProjectShot {
    var shot = original
    func ancestors(of entryId: String, visiting: Set<String>) -> [ShotFrameEntry]? {
        if shot.entries.contains(where: { $0.entryId == entryId }) { return [] }
        guard !visiting.contains(entryId),
              let record = shot.continuationRecord(entryId: entryId),
              let take = record.selectedTake, take.targetFrame == nil,
              !take.anchor.sourceEntryId.isEmpty else { return nil }
        var visited = visiting
        visited.insert(entryId)
        guard let prefix = ancestors(of: take.anchor.sourceEntryId, visiting: visited) else { return nil }
        return prefix + [ShotFrameEntry(entryId: entryId, isAIExtension: true)]
    }
    // A retained selected descendant is evidence for its missing ancestors.
    // Unattached historical attempts are not an instruction to extend the row.
    for entry in original.entries where !entry.isSkipped {
        guard let take = shot.continuationRecord(entryId: entry.entryId)?.selectedTake,
              !take.anchor.sourceTakeId.isEmpty,
              let source = shot.continuationRecord(entryId: take.anchor.sourceEntryId),
              source.takes.contains(where: { $0.takeId == take.anchor.sourceTakeId }),
              let missing = ancestors(of: source.entryId, visiting: [entry.entryId]),
              let index = shot.entries.firstIndex(where: { $0.entryId == entry.entryId }) else { continue }
        shot.entries.insert(contentsOf: missing, at: index)
    }
    let liveIds = Set(shot.entries.map(\.entryId))
    for index in shot.continuationRecords.indices where liveIds.contains(shot.continuationRecords[index].entryId) {
        guard let selected = shot.continuationRecords[index].selectedTake else { continue }
        let candidates = original.continuationRecords.filter { record in
            !liveIds.contains(record.entryId) && record.selectedTake.map {
                sameContinuationPosition($0, selected)
            } == true
        }
        for candidate in candidates {
            for old in candidate.takes where old.isReady && sameContinuationPosition(old, selected) {
                guard !shot.continuationRecords[index].takes.contains(where: { $0.takeId == old.takeId }) else { continue }
                var imported = old
                imported.takeNumber = (shot.continuationRecords[index].takes.map(\.takeNumber).max() ?? 0) + 1
                imported.segmentClip?.placementStartEntryId = shot.continuationRecords[index].sourceEntryId
                imported.segmentClip?.placementEndEntryId = shot.continuationRecords[index].entryId
                shot.continuationRecords[index].takes.append(imported)
            }
        }
    }
    // Preserve the immutable artifacts, but stop presenting extension-only
    // outputs as alternate whole-Shot renders. Every clip must be accounted for.
    let liveTakes = shot.continuationRecords.filter { liveIds.contains($0.entryId) }.flatMap(\.takes)
    for version in shot.renderVersions where !version.clipPaths.isEmpty {
        let accountedFor = version.clipPaths.allSatisfy { path in
            liveTakes.contains { take in
                take.isReady && take.segmentClip?.clipPath == path
                    && !take.anchor.sourceRenderVersionId.isEmpty
                    && take.anchor.sourceRenderVersionId != version.versionId
                    && shot.renderVersions.contains { $0.versionId == take.anchor.sourceRenderVersionId }
            }
        }
        if accountedFor && !shot.continuationOnlyVersionIds.contains(version.versionId) {
            shot.continuationOnlyVersionIds.append(version.versionId)
        }
    }
    return shot
}

private func sameContinuationPosition(_ lhs: ShotContinuationTake, _ rhs: ShotContinuationTake) -> Bool {
    let a = lhs.anchor, b = rhs.anchor
    guard !a.sourceEntryId.isEmpty, a.sourceEntryId == b.sourceEntryId,
          a.sourceKind == b.sourceKind, a.sourceTakeId == b.sourceTakeId,
          a.sourceRenderVersionId == b.sourceRenderVersionId,
          a.tailClipPath == b.tailClipPath,
          abs(a.tailClipStartSeconds - b.tailClipStartSeconds) < 0.001,
          abs(a.tailClipEndSeconds - b.tailClipEndSeconds) < 0.001,
          lhs.targetFrame?.imageId == rhs.targetFrame?.imageId,
          lhs.targetFrame?.fingerprint == rhs.targetFrame?.fingerprint else { return false }
    if !a.sourceTakeId.isEmpty || !a.sourceRenderVersionId.isEmpty { return true }
    return !a.frameFingerprint.isEmpty && a.frameFingerprint == b.frameFingerprint
}
