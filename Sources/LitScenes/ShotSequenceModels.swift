import Foundation

/// Immutable destination reference retained with each paid ending take.
struct ShotContinuationTargetFrame: Codable, Hashable, Sendable {
    var entryId: String
    var imageId: String
    var imagePath: String
    var fingerprint: String
    var label: String

    var frame: ProjectLensHeroImage {
        ProjectLensHeroImage(imageId: imageId, label: label, imagePath: imagePath, status: "ready")
    }
}

extension ShotRenderModel {
    var supportsShotEnding: Bool {
        switch self {
        case .wan27, .falKlingV3Pro, .falSeedance20, .falSeedance25, .falHailuo3, .falHailuo3Max: return true
        default: return false
        }
    }
}

/// The saved predecessor of a destination Frame, independent of render versions.
func shotEndingSourceAnchor(shot: ProjectShot, entryId: String) -> ShotContinuationAnchor? {
    // A combined source starts its own sequence; its first Frame is not an
    // ending destination for the preceding source's continuation.
    guard !shot.sourceBoundaries.contains(where: { $0.rightEntryId == entryId }) else { return nil }
    let live = shot.entries.filter { !$0.isSkipped }
    guard let index = live.firstIndex(where: { $0.entryId == entryId }), index > 0 else { return nil }
    let previous = live[index - 1]
    if let take = shot.continuationRecord(entryId: previous.entryId)?.selectedTake, let clip = take.segmentClip {
        return ShotContinuationAnchor(sourceKind: "continuation_take", sourceEntryId: previous.entryId,
            sourceTakeId: take.takeId, sourceSegmentPlacementKey: clip.placementKey,
            framePath: take.finalFramePath, frameFingerprint: take.outputFingerprint,
            tailClipPath: clip.clipPath, tailClipEndSeconds: clip.durationSeconds > 0 ? clip.durationSeconds : Double(clip.requestedDurationSeconds),
            tailClipFingerprint: continuationFileFingerprint(path: clip.clipPath, readsBytes: false)).normalized()
    }
    guard let version = shot.playableRenderVersion,
          version.renderedEntryIds.contains(previous.entryId), !version.renderedEntryIds.contains(entryId) else { return nil }
    let clip = version.clipPaths.last.flatMap { path in version.segmentClips.first { $0.clipPath == path && FileManager.default.fileExists(atPath: path) } }
    let path = clip?.clipPath.trimmed.nilIfEmpty ?? version.videoPath
    guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
    return ShotContinuationAnchor(sourceKind: "rendered_original", sourceEntryId: previous.entryId,
        sourceRenderVersionId: version.versionId, sourceSegmentPlacementKey: clip?.placementKey ?? "",
        tailClipPath: path, tailClipEndSeconds: clip.map { $0.durationSeconds > 0 ? $0.durationSeconds : Double($0.requestedDurationSeconds) } ?? Double(version.totalSeconds),
        tailClipFingerprint: continuationFileFingerprint(path: path, readsBytes: false)).normalized()
}

func shotPendingEndingEntryIds(_ shot: ProjectShot) -> Set<String> {
    Set(shot.entries.filter { entry in
        !entry.isSkipped && !entry.isClip && !entry.isAIExtension
            && shot.continuationRecord(entryId: entry.entryId)?.selectedTake == nil
            && shotEndingSourceAnchor(shot: shot, entryId: entry.entryId) != nil
    }.map(\.entryId))
}

/// Resolve immutable clip provenance in the current plan's order.
func shotSequenceClips(shot: ProjectShot, segments: [ShotRenderPlanSegment]) -> [ShotRenderSegmentClip] {
    segments.compactMap { ShotSegmentPresentation(shot: shot, segment: $0).clip }
}

func shotSequenceProvenance(shot: ProjectShot, segments: [ShotRenderPlanSegment]) -> String {
    let clips = shotSequenceClips(shot: shot, segments: segments)
    let labels = clips.filter { $0.provider != "footage" && $0.model != "source" }.map {
        shotClipModelShortLabel(provider: $0.provider, model: $0.model)
    }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    let label: String
    switch labels.count {
    case 0: label = clips.isEmpty ? "Not rendered" : "Footage"
    case 1: label = labels[0]
    case 2: label = labels.joined(separator: " + ")
    default: label = "Mixed · \(labels.count) models"
    }
    return !labels.isEmpty && clips.contains { $0.provider == "footage" || $0.model == "source" } ? label + " + Footage" : label
}

func continuationFileFingerprint(path: String, readsBytes: Bool) -> String {
        let clean = path.trimmed
        guard !clean.isEmpty else { return "" }
        if readsBytes, let data = try? Data(contentsOf: URL(fileURLWithPath: clean), options: [.mappedIfSafe]) {
            return sha256Hex(data)
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: clean)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return sha256Hex(Data("\(clean)|\(size)|\(String(format: "%.3f", modified))".utf8))
    }


/// A thumbnail addresses a placement boundary in the shared material/output map.
func shotEntryFocusSeconds(shot: ProjectShot, entryId: String, assembly: ShotCutAssembly) -> Double? {
    guard let entry = shot.entries.first(where: { $0.entryId == entryId }) else { return nil }
    var starts: [(Int, Bool)] = []
    var ends: [(Int, Bool)] = []
    for (index, band) in assembly.bands.enumerated() {
        let start: String
        let end: String
        switch band.segment {
        case .generated(let item): start = item.pair.startPlacementEntryId; end = item.pair.endPlacementEntryId
        case .preserved(let saved): start = saved.clip.placementStartEntryId; end = saved.clip.placementEndEntryId
        case .footage(let footage): start = footage.clip.entryId; end = ""
        case .artifactFallback: continue
        }
        if end == entryId { ends.append((index, !entry.isAIExtension)) }
        if start == entryId { starts.append((index, false)) }
    }
    guard let match = (ends + starts).first, assembly.planClips.indices.contains(match.0) else { return nil }
    let clip = assembly.planClips[match.0]
    let material = clip.materialStartSeconds + (match.1 ? clip.materialSeconds : 0)
    let seconds = assembly.outputSeconds(forMaterialSeconds: material)
    return min(max(seconds, 0), max(assembly.outputSeconds - 1.0 / 24.0, 0))
}
