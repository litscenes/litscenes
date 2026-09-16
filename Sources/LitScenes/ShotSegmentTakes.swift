import Foundation

// MARK: - Per-segment TAKES
//
// A Shot's render history keeps every version forever, and every version
// keeps the clip it rendered (or reused) for each placement. Those retained
// clips ARE a placement's takes; nothing here copies them into a second
// ledger. The only new persisted state is the operator's pick per placement,
// keyed by the immutable clip file exactly as razor pins are.

/// The operator's pick among a placement's retained takes. A selection never
/// names a render version as playback authority: a path no retained version
/// or seed still carries is pruned, never refused, and playback falls back to
/// the playable version's clip. `versionId` and `requestId` are provenance.
struct ShotSegmentTakeSelection: Codable, Hashable, Sendable, Identifiable {
    var placementKey: String = ""
    var clipPath: String = ""
    var versionId: String = ""
    var requestId: String = ""
    var selectedAt: String = ""

    var id: String { placementKey }

    private enum CodingKeys: String, CodingKey {
        case placementKey, clipPath, versionId, requestId, selectedAt
    }

    init(
        placementKey: String = "",
        clipPath: String = "",
        versionId: String = "",
        requestId: String = "",
        selectedAt: String = ""
    ) {
        self.placementKey = placementKey
        self.clipPath = clipPath
        self.versionId = versionId
        self.requestId = requestId
        self.selectedAt = selectedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        placementKey = try container.decodeIfPresent(String.self, forKey: .placementKey) ?? ""
        clipPath = try container.decodeIfPresent(String.self, forKey: .clipPath) ?? ""
        versionId = try container.decodeIfPresent(String.self, forKey: .versionId) ?? ""
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId) ?? ""
        selectedAt = try container.decodeIfPresent(String.self, forKey: .selectedAt) ?? ""
    }

    func normalized() -> ShotSegmentTakeSelection {
        var value = self
        value.placementKey = value.placementKey.trimmed
        value.clipPath = value.clipPath.trimmed
        value.versionId = value.versionId.trimmed
        value.requestId = value.requestId.trimmed
        value.selectedAt = value.selectedAt.trimmed
        return value
    }
}

/// One retained take of a placement, derived from the render history. A clip
/// that traveled verbatim across versions is ONE take whose origin is the
/// earliest version carrying it; `carriedByVersionIds` tells the reuse story.
struct ShotSegmentTake: Identifiable, Hashable, Sendable {
    /// 1-based, in first-appearance order (seeds first, then versions ascending).
    var takeNumber: Int
    var clip: ShotRenderSegmentClip
    /// Empty for a seed.
    var originVersionId: String
    /// 0 for a seed.
    var originVersionNumber: Int
    /// Ascending version ids that carry this exact file.
    var carriedByVersionIds: [String]
    var isSeed: Bool
    var fileExists: Bool

    var id: String { clip.clipPath }
}

/// The exact-then-legacy seed lookup shared by every resolver that reads
/// `seedSegmentClips` for a placement.
func shotSeedSegmentClip(
    shot: ProjectShot,
    startEntryId: String,
    endEntryId: String,
    startFrameId: String,
    endFrameId: String
) -> ShotRenderSegmentClip? {
    if !startEntryId.isEmpty || !endEntryId.isEmpty,
       let exact = shot.seedSegmentClips.first(where: {
           $0.placementStartEntryId == startEntryId && $0.placementEndEntryId == endEntryId
       }) {
        return exact
    }
    return shot.seedSegmentClips.first {
        $0.placementStartEntryId.isEmpty && $0.placementEndEntryId.isEmpty
            && $0.startFrameImageId == startFrameId && $0.endFrameImageId == endFrameId
    }
}

func shotSegmentTakes(
    shot: ProjectShot,
    pair: ShotRenderPair,
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> [ShotSegmentTake] {
    shotSegmentTakes(
        shot: shot,
        startEntryId: pair.startPlacementEntryId, endEntryId: pair.endPlacementEntryId,
        startFrameId: pair.start?.imageId ?? "", endFrameId: pair.end?.imageId ?? "",
        fileExists: fileExists
    )
}

/// Every retained take of one generated placement. Continuation and ending
/// placements answer with an empty list: their `ShotContinuationRecord` is the
/// take universe and must not be mirrored here.
func shotSegmentTakes(
    shot: ProjectShot,
    startEntryId: String,
    endEntryId: String,
    startFrameId: String,
    endFrameId: String,
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> [ShotSegmentTake] {
    if !endEntryId.isEmpty, shot.continuationRecord(entryId: endEntryId) != nil { return [] }
    var takes: [ShotSegmentTake] = []
    var indexByPath: [String: Int] = [:]
    func append(_ clip: ShotRenderSegmentClip, versionId: String, versionNumber: Int, isSeed: Bool) {
        let path = clip.clipPath.trimmed
        guard !path.isEmpty else { return }
        if let index = indexByPath[path] {
            if !versionId.isEmpty { takes[index].carriedByVersionIds.append(versionId) }
            return
        }
        indexByPath[path] = takes.count
        takes.append(ShotSegmentTake(
            takeNumber: takes.count + 1,
            clip: clip,
            originVersionId: versionId,
            originVersionNumber: versionNumber,
            carriedByVersionIds: versionId.isEmpty ? [] : [versionId],
            isSeed: isSeed,
            fileExists: fileExists(path)
        ))
    }
    if let seed = shotSeedSegmentClip(shot: shot, startEntryId: startEntryId, endEntryId: endEntryId,
                                      startFrameId: startFrameId, endFrameId: endFrameId) {
        append(seed, versionId: "", versionNumber: 0, isSeed: true)
    }
    for version in shot.sortedRenderVersions {
        if let clip = version.segmentClip(
            placementStartEntryId: startEntryId, placementEndEntryId: endEntryId,
            forStart: startFrameId, end: endFrameId
        ) {
            append(clip, versionId: version.versionId, versionNumber: version.versionNumber, isSeed: false)
        }
    }
    return takes
}

/// The retained record behind one clip file for one placement: versions in
/// order, then seeds. A clip with placement ids must belong to the placement;
/// a legacy pair-keyed clip has no placement to disagree with.
func shotRetainedSegmentClip(shot: ProjectShot, clipPath: String, placementKey: String) -> ShotRenderSegmentClip? {
    let path = clipPath.trimmed
    guard !path.isEmpty else { return nil }
    func belongs(_ clip: ShotRenderSegmentClip) -> Bool {
        clip.clipPath == path
            && (clip.placementKey == placementKey
                || (clip.placementStartEntryId.isEmpty && clip.placementEndEntryId.isEmpty))
    }
    for version in shot.sortedRenderVersions {
        if let clip = version.segmentClips.first(where: belongs) { return clip }
    }
    return shot.seedSegmentClips.first(where: belongs)
}

/// THE SELECTION LAW's middle rung: the clip the operator picked for a
/// placement, or nil when nothing is picked or the pick no longer resolves.
func shotSelectedSegmentTakeClip(shot: ProjectShot, placementKey: String) -> ShotRenderSegmentClip? {
    guard let selection = shot.segmentTakeSelection(placementKey: placementKey) else { return nil }
    return shotRetainedSegmentClip(shot: shot, clipPath: selection.clipPath, placementKey: placementKey)
}

/// The entry ids a durable placement key names, in start/end order. Legacy
/// frame-keyed placements name none.
private func shotPlacementKeyEntryIds(_ placementKey: String) -> (start: String, end: String)? {
    guard placementKey.hasPrefix("entry:") else { return nil }
    let parts = String(placementKey.dropFirst("entry:".count))
        .split(separator: ">", maxSplits: 1, omittingEmptySubsequences: false)
    let start = parts.first.map(String.init) ?? ""
    let end = parts.count > 1 ? String(parts[1]) : ""
    return (start, end)
}

/// A selection is invisible to any projection that no longer holds the
/// entries it names (an earlier-cut scope or a continuation prefix).
func shotSelectionNamesPresentEntries(_ placementKey: String, entryIds: Set<String>) -> Bool {
    guard let ids = shotPlacementKeyEntryIds(placementKey) else { return true }
    if !ids.start.isEmpty, !entryIds.contains(ids.start) { return false }
    if !ids.end.isEmpty, !entryIds.contains(ids.end) { return false }
    return true
}

/// Normalization for selections: drops empty keys and paths, paths no
/// retained version or seed carries, placements a continuation record owns,
/// and durable keys naming entries that left the strip; dedupes by placement
/// (last wins) and sorts so snapshot equality is order-stable.
func pruningSegmentTakeSelections(
    _ selections: [ShotSegmentTakeSelection],
    retainedClipPaths: Set<String>,
    entries: [ShotFrameEntry],
    continuationEntryIds: Set<String>
) -> [ShotSegmentTakeSelection] {
    let entryIds = Set(entries.map(\.entryId))
    var byKey: [String: ShotSegmentTakeSelection] = [:]
    for raw in selections {
        let selection = raw.normalized()
        guard !selection.placementKey.isEmpty, !selection.clipPath.isEmpty,
              retainedClipPaths.contains(selection.clipPath),
              shotSelectionNamesPresentEntries(selection.placementKey, entryIds: entryIds) else { continue }
        if let ids = shotPlacementKeyEntryIds(selection.placementKey),
           !ids.end.isEmpty, continuationEntryIds.contains(ids.end) { continue }
        byKey[selection.placementKey] = selection
    }
    return byKey.values.sorted { $0.placementKey < $1.placementKey }
}

extension ProjectShot {
    /// Every clip file some version or seed still carries — the retention set
    /// that selections, razor pins and arranged copies all pin against.
    var retainedTakeClipPaths: Set<String> {
        var paths = Set<String>()
        for version in renderVersions {
            for clip in version.segmentClips where !clip.clipPath.trimmed.isEmpty { paths.insert(clip.clipPath) }
        }
        for seed in seedSegmentClips where !seed.clipPath.trimmed.isEmpty { paths.insert(seed.clipPath) }
        return paths
    }

    func segmentTakeSelection(placementKey: String) -> ShotSegmentTakeSelection? {
        segmentTakeSelections.first { $0.placementKey == placementKey }
    }

    /// Picks a retained take for a placement. Returns self for an empty key,
    /// a path no retained version or seed carries, or a placement a
    /// continuation record owns. Fills provenance from the record itself.
    func selectingSegmentTake(placementKey: String, clipPath: String, now: String) -> ProjectShot {
        let key = placementKey.trimmed
        let path = clipPath.trimmed
        guard !key.isEmpty, !path.isEmpty else { return self }
        if let ids = shotPlacementKeyEntryIds(key), !ids.end.isEmpty, continuationRecord(entryId: ids.end) != nil {
            return self
        }
        guard let clip = shotRetainedSegmentClip(shot: self, clipPath: path, placementKey: key) else { return self }
        let origin = sortedRenderVersions.first { version in
            version.segmentClips.contains { $0.clipPath == path }
        }
        var value = self
        value.segmentTakeSelections.removeAll { $0.placementKey == key }
        value.segmentTakeSelections.append(ShotSegmentTakeSelection(
            placementKey: key,
            clipPath: path,
            versionId: origin?.versionId ?? "",
            requestId: clip.requestId,
            selectedAt: now
        ))
        value.segmentTakeSelections.sort { $0.placementKey < $1.placementKey }
        value.updatedAt = now
        return value
    }

    func clearingSegmentTakeSelection(placementKey: String, now: String) -> ProjectShot {
        guard segmentTakeSelections.contains(where: { $0.placementKey == placementKey }) else { return self }
        var value = self
        value.segmentTakeSelections.removeAll { $0.placementKey == placementKey }
        value.updatedAt = now
        return value
    }

    /// THE FRESH TAKE LAW: activating a ready version makes every placement it
    /// newly rendered play its new take — a clip whose file appears in no
    /// version sorted before this one and in no seed drops that placement's
    /// selection. Clips that traveled in verbatim (partial render, resume,
    /// suffix render) leave the earlier choice alone. Callers gate on the
    /// version being ready: playback substitutes the last ready version while
    /// one is generating, so clearing early would flip the picture mid-render.
    func selectingFreshSegmentTakes(from version: ShotRenderArtifact) -> ProjectShot {
        guard !segmentTakeSelections.isEmpty else { return self }
        var known = Set(seedSegmentClips.map(\.clipPath))
        for earlier in sortedRenderVersions.prefix(while: { $0.versionId != version.versionId }) {
            for clip in earlier.segmentClips { known.insert(clip.clipPath) }
        }
        let freshKeys = Set(version.segmentClips
            .filter { !$0.clipPath.trimmed.isEmpty && !known.contains($0.clipPath) }
            .map(\.placementKey))
        guard !freshKeys.isEmpty else { return self }
        var value = self
        value.segmentTakeSelections.removeAll { freshKeys.contains($0.placementKey) }
        return value
    }
}

/// The clips a partial render may reuse, one per placement: the active
/// version's ledger (a failed render's landed clips stay reusable — never
/// re-bought), then seeds, then selected continuation takes and selected pair
/// takes whose files exist. Selections upsert LAST so the render reuses
/// exactly what the operator is watching.
func shotRenderReuseSource(shot: ProjectShot, fileExists: (String) -> Bool) -> ShotRenderArtifact {
    var reuse = shot.activeRenderVersion ?? ShotRenderArtifact()
    for seed in shot.seedSegmentClips {
        reuse.upsertSegmentClip(seed)
    }
    for record in shot.continuationRecords {
        if let clip = record.selectedTake?.segmentClip, fileExists(clip.clipPath) {
            reuse.upsertSegmentClip(clip)
        }
    }
    for selection in shot.segmentTakeSelections {
        guard let clip = shotRetainedSegmentClip(shot: shot, clipPath: selection.clipPath, placementKey: selection.placementKey),
              fileExists(clip.clipPath) else { continue }
        reuse.upsertSegmentClip(clip)
    }
    return reuse
}

/// The output fingerprint's clip basis: the playable version's ledger with
/// each selected pair take substituted for its placement (appended when the
/// version has no clip there), then seeds and selected continuation clips.
/// Selecting the take that already plays is therefore fingerprint-neutral,
/// and a selection naming entries outside this shot (a scope projection or a
/// continuation prefix) is invisible to it.
func shotFingerprintClipBasis(_ shot: ProjectShot) -> [ShotRenderSegmentClip] {
    var clips = shot.playableRenderVersion?.segmentClips ?? []
    let entryIds = Set(shot.entries.map(\.entryId))
    for selection in shot.segmentTakeSelections {
        guard shotSelectionNamesPresentEntries(selection.placementKey, entryIds: entryIds),
              let clip = shotRetainedSegmentClip(shot: shot, clipPath: selection.clipPath, placementKey: selection.placementKey)
        else { continue }
        if let index = clips.firstIndex(where: { $0.placementKey == selection.placementKey }) {
            clips[index] = clip
        } else {
            clips.append(clip)
        }
    }
    let selected = shot.continuationRecords.compactMap(\.selectedTake)
    return clips + shot.seedSegmentClips + selected.compactMap(\.segmentClip)
}

/// The take that stands in for a rendered tail clip when the next continuation
/// grows from it: the selected take for that placement when its file exists,
/// else the clip itself. Returns the clip's version of origin.
func shotResolvedTailClip(
    shot: ProjectShot,
    base: ShotRenderSegmentClip,
    versionId: String,
    fileExists: (String) -> Bool
) -> (clip: ShotRenderSegmentClip, versionId: String) {
    guard let selection = shot.segmentTakeSelection(placementKey: base.placementKey),
          let selected = shotRetainedSegmentClip(shot: shot, clipPath: selection.clipPath, placementKey: base.placementKey),
          fileExists(selected.clipPath) else { return (base, versionId) }
    return (selected, selection.versionId.nilIfEmpty ?? versionId)
}

/// What choosing a take would do to the continuations after it, computed on a
/// staged copy so nothing persists until the operator confirms.
struct ShotSegmentTakeImpact: Equatable, Sendable {
    var placementKey: String
    var clipPath: String
    var resolution: ShotContinuationBranchResolution
}

func shotSegmentTakeStaleEntryIds(shot: ProjectShot, placementKey: String, clipPath: String) -> [String] {
    shotContinuationStaleEntryIds(shot.selectingSegmentTake(placementKey: placementKey, clipPath: clipPath, now: shot.updatedAt))
}
