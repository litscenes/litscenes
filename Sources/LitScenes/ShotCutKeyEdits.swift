import Foundation

// KEYBOARD AND NUMERIC PARITY FOR PICTURE EDITS — the pure laws behind the
// two-press B blade, the I/O in-out keys, the typed IN/OUT fields, and the
// razor popover's TIMING section. Audio regions have had this parity for a
// while; these bring the strip up to the same standard, sharing the razor
// drag's own clamps so keyboard and pointer commit identical state.

/// The playable band whose material span contains this second, if any.
func shotBandIndex(atMaterialSeconds seconds: Double, assembly: ShotCutAssembly) -> Int? {
    for (index, clip) in assembly.planClips.enumerated() where clip.isPlayable {
        let start = clip.materialStartSeconds
        let end = start + clip.materialSeconds
        if seconds >= start - 0.000_1, seconds <= end + 0.000_1 {
            return index
        }
    }
    return nil
}

/// The two-press B blade: both marks must land in ONE playable band (a razor
/// range never crosses a splice by model), and the range must clear the razor
/// minimum. Returns the cut list with the new razor range appended — in the
/// band's clip-local seconds, pinned exactly as the pointer razor pins
/// (generated cuts to the rendered take, footage cuts persist) — or nil when
/// the marks refuse.
func shotBladeCutList(
    markMaterialSeconds: Double,
    toMaterialSeconds: Double,
    assembly: ShotCutAssembly,
    cutList: ShotCutList,
    now: String
) -> ShotCutList? {
    let start = min(markMaterialSeconds, toMaterialSeconds)
    let end = max(markMaterialSeconds, toMaterialSeconds)
    guard let bandIndex = shotBandIndex(atMaterialSeconds: start, assembly: assembly),
          bandIndex == shotBandIndex(atMaterialSeconds: end, assembly: assembly),
          bandIndex < assembly.bands.count else {
        return nil
    }
    let clip = assembly.planClips[bandIndex]
    let lower = clip.materialStartSeconds
    let upper = clip.materialStartSeconds + clip.materialSeconds
    let clampedStart = min(max(start, lower), upper)
    let clampedEnd = min(max(end, lower), upper)
    guard clampedEnd - clampedStart >= ShotCutList.minimumRangeSeconds else { return nil }
    let band = assembly.bands[bandIndex]
    var list = cutList
    list.segmentCuts.append(ShotSegmentCutRange(
        segmentKey: band.segmentKey,
        clipPath: band.isFootage ? "" : band.clipPath,
        startSeconds: clip.headSeconds + (clampedStart - clip.materialStartSeconds),
        endSeconds: clip.headSeconds + (clampedEnd - clip.materialStartSeconds),
        updatedAt: now
    ))
    return list
}

/// I at the playhead (or a typed IN): clamps exactly as the drag handle does
/// — never past the out point's minimum clearance. nil clears the trim.
func shotCutListSettingIn(
    _ cutList: ShotCutList,
    materialSeconds: Double?,
    assemblyMaterialSeconds: Double
) -> ShotCutList {
    var list = cutList
    guard let materialSeconds else {
        list.shotInSeconds = nil
        return list
    }
    let out = min(list.shotOutSeconds ?? assemblyMaterialSeconds, assemblyMaterialSeconds)
    let clamped = min(
        max(materialSeconds, 0),
        max(out - ShotCutList.minimumRangeSeconds, 0)
    )
    list.shotInSeconds = clamped > 0.000_1 ? clamped : nil
    return list
}

/// O at the playhead (or a typed OUT): clamps like the drag handle, and an
/// out at (or past) the material end clears honestly — "no tail trim" is nil,
/// never a stored copy of the duration that would go stale on re-render.
func shotCutListSettingOut(
    _ cutList: ShotCutList,
    materialSeconds: Double?,
    assemblyMaterialSeconds: Double
) -> ShotCutList {
    var list = cutList
    guard let materialSeconds else {
        list.shotOutSeconds = nil
        return list
    }
    let inPoint = list.shotInSeconds ?? 0
    let clamped = max(materialSeconds, inPoint + ShotCutList.minimumRangeSeconds)
    list.shotOutSeconds = clamped < assemblyMaterialSeconds - ShotCutList.minimumRangeSeconds
        ? clamped
        : nil
    return list
}

/// A razor cut's span in strip material seconds, resolved through its band —
/// cut ranges persist in clip-local file seconds, which no operator should
/// ever have to read. nil when the cut's segment isn't in the assembly.
func shotRazorCutMaterialRange(
    cut: ShotSegmentCutRange,
    assembly: ShotCutAssembly
) -> ClosedRange<Double>? {
    guard let index = assembly.bands.firstIndex(where: {
        cut.applies(toSegmentKey: $0.segmentKey, clipPath: $0.clipPath)
    }), index < assembly.planClips.count else {
        return nil
    }
    let clip = assembly.planClips[index]
    let start = clip.materialStartSeconds + (cut.startSeconds - clip.headSeconds)
    let end = clip.materialStartSeconds + (cut.endSeconds - clip.headSeconds)
    guard end >= start else { return nil }
    return start...end
}

/// The popover TIMING commit: replaces one razor cut's range from typed or
/// nudged MATERIAL seconds, clamped inside its own band and floored at the
/// razor minimum. Identity, pinning, and repair state survive untouched.
func shotCutListReplacingRazorRange(
    _ cutList: ShotCutList,
    cutId: String,
    materialStart: Double,
    materialEnd: Double,
    assembly: ShotCutAssembly,
    now: String
) -> ShotCutList? {
    guard let cutIndex = cutList.segmentCuts.firstIndex(where: { $0.id == cutId }) else {
        return nil
    }
    let cut = cutList.segmentCuts[cutIndex]
    guard let bandIndex = assembly.bands.firstIndex(where: {
        cut.applies(toSegmentKey: $0.segmentKey, clipPath: $0.clipPath)
    }), bandIndex < assembly.planClips.count else {
        return nil
    }
    let clip = assembly.planClips[bandIndex]
    let lower = clip.materialStartSeconds
    let upper = clip.materialStartSeconds + clip.materialSeconds
    var start = min(max(min(materialStart, materialEnd), lower), upper)
    var end = min(max(max(materialStart, materialEnd), lower), upper)
    if end - start < ShotCutList.minimumRangeSeconds {
        end = min(start + ShotCutList.minimumRangeSeconds, upper)
        start = max(end - ShotCutList.minimumRangeSeconds, lower)
        guard end - start >= ShotCutList.minimumRangeSeconds - 0.000_1 else { return nil }
    }
    var list = cutList
    list.segmentCuts[cutIndex].startSeconds = clip.headSeconds + (start - clip.materialStartSeconds)
    list.segmentCuts[cutIndex].endSeconds = clip.headSeconds + (end - clip.materialStartSeconds)
    list.segmentCuts[cutIndex].updatedAt = now
    return list
}

/// THE RAZOR BLOCK LAW: overlapping or abutting razor cuts on one segment
/// are one connected block — they draw as one bite and they RESTORE as one.
/// Membership: same `segmentKey`, compatible pins ("" matches any, exactly
/// as `applies()`), ranges intersecting or abutting within `tolerance`
/// (1/240s, the join-matching tolerance). Transitive: [1,3]+[2,5]+[4.99,6]
/// is one block. Returns the member ids sorted by start; empty when the
/// cutId is unknown.
func shotRazorCutIdsInSameBlock(
    cutList: ShotCutList,
    cutId: String,
    tolerance: Double = 1.0 / 240.0
) -> [String] {
    guard let target = cutList.segmentCuts.first(where: { $0.id == cutId }) else { return [] }

    func pinsCompatible(_ a: String, _ b: String) -> Bool {
        a.isEmpty || b.isEmpty || a == b
    }

    let candidates = cutList.segmentCuts.filter {
        $0.segmentKey == target.segmentKey && pinsCompatible($0.clipPath, target.clipPath)
    }
    var members: [ShotSegmentCutRange] = [target]
    var span = (start: target.startSeconds, end: target.endSeconds)
    var grew = true
    while grew {
        grew = false
        for cut in candidates where !members.contains(where: { $0.id == cut.id }) {
            if cut.startSeconds <= span.end + tolerance, cut.endSeconds >= span.start - tolerance {
                members.append(cut)
                span.start = min(span.start, cut.startSeconds)
                span.end = max(span.end, cut.endSeconds)
                grew = true
            }
        }
    }
    return members
        .sorted { $0.startSeconds < $1.startSeconds }
        .map(\.id)
}

/// The razor keys a clip-range change must shed, computed from the
/// PRE-change entry: the legacy footage key (how razors were keyed before
/// placement keys existed) AND the modern placement key (how they are keyed
/// today). Before this law the engine matched only the legacy form — dead
/// for every modern footage razor, which then survived the range change and
/// bit at now-wrong clip-local seconds.
func shotClipRangeShedKeys(entry: ShotFrameEntry) -> Set<String> {
    guard entry.isClip else { return [] }
    let footageKey = shotFootageKey(
        mediaId: entry.clipMediaId,
        startSeconds: entry.clipStartSeconds,
        endSeconds: entry.clipEndSeconds
    )
    return [
        "\(footageKey)>",
        shotPlacementSegmentKey(
            startEntryId: entry.entryId,
            endEntryId: "",
            legacyStartId: footageKey,
            legacyEndId: ""
        )
    ]
}

/// THE PIN SWEEP LAW: a pinned razor is stale only when its pinned clip file
/// belongs to NO retained take — the union of every render version's segment
/// clips plus the seed clips — not merely "not the active version". Pinning
/// reads `playableRenderVersion`, which ranges over browsable versions, so
/// sweeping against the active version alone killed razors made against the
/// still-watched old take the moment an in-flight render completed.
/// Unpinned (footage) razors are never stale here.
func shotStalePinnedCutIds(shot: ProjectShot) -> [String] {
    var retained = Set<String>()
    for version in shot.renderVersions {
        for clip in version.segmentClips where !clip.clipPath.isEmpty {
            retained.insert(clip.clipPath)
        }
    }
    for clip in shot.seedSegmentClips where !clip.clipPath.isEmpty {
        retained.insert(clip.clipPath)
    }
    // Artifact-band cuts pin the version's FULL video, which is never in the
    // segment-clip union — without this branch every artifact cut would be
    // swept at the first render completion. Their own law: stale only when
    // the version is gone or its video was re-pointed; a merely superseded
    // version's cuts stay (inert while unshown, revived by re-activation).
    let artifactPathsByVersionId = Dictionary(
        shot.renderVersions.map { ($0.versionId, $0.videoPath.trimmed) },
        uniquingKeysWith: { first, _ in first }
    )
    return shot.cutList.segmentCuts
        .filter { cut in
            if let versionId = shotArtifactSegmentKeyVersionId(cut.segmentKey) {
                return artifactPathsByVersionId[versionId] != cut.clipPath
            }
            return !cut.clipPath.isEmpty && !retained.contains(cut.clipPath)
        }
        .map(\.id)
}

/// The marker the Mark button would REMOVE: the nearest reference marker
/// within tolerance of the playhead's material projection. nil means Mark
/// drops a new marker instead — pure, so the toggle law is testable.
/// Markers are inert by law: deliberately NOT part of `shotStripSnapTargets`.
func shotMarkerAtPlayhead(
    cutList: ShotCutList,
    playheadMaterialSeconds: Double,
    toleranceSeconds: Double = 0.1
) -> ShotStripMarker? {
    cutList.markers
        .min { abs($0.materialSeconds - playheadMaterialSeconds) < abs($1.materialSeconds - playheadMaterialSeconds) }
        .flatMap { abs($0.materialSeconds - playheadMaterialSeconds) <= toleranceSeconds ? $0 : nil }
}

/// Undo action names for the shared `onSetCutList` funnel, derived from a
/// pure diff so the Edit menu says what actually happened. First match wins;
/// callers with dedicated ops (skip, seam, reverse, repair) name directly.
func shotCutListEditActionName(before: ShotCutList, after: ShotCutList) -> String {
    let beforeIds = Set(before.segmentCuts.map(\.id))
    let afterIds = Set(after.segmentCuts.map(\.id))
    if afterIds.subtracting(beforeIds).count > 0 { return "Razor Cut" }
    if beforeIds.subtracting(afterIds).count > 0 { return "Restore Razor Cut" }
    if before.segmentCuts != after.segmentCuts { return "Adjust Razor Timing" }
    if before.shotInSeconds != after.shotInSeconds {
        return after.shotInSeconds == nil ? "Clear Shot IN" : "Trim Shot IN"
    }
    if before.shotOutSeconds != after.shotOutSeconds {
        return after.shotOutSeconds == nil ? "Clear Shot OUT" : "Trim Shot OUT"
    }
    if before.isReversed != after.isReversed {
        return after.isReversed ? "Reverse CUT" : "Play CUT Forward"
    }
    if before.outputLoopCount != after.outputLoopCount {
        return after.outputLoopCount > 1 ? "Loop Output ×\(after.outputLoopCount)" : "Remove Output Loop"
    }
    let beforeMarkerIds = Set(before.markers.map(\.id))
    let afterMarkerIds = Set(after.markers.map(\.id))
    if afterMarkerIds.subtracting(beforeMarkerIds).count > 0 { return "Add Marker" }
    if beforeMarkerIds.subtracting(afterMarkerIds).count > 0 { return "Remove Marker" }
    return "Edit Cut List"
}

/// Snap magnets for the strip's razor and in/out drags, all in material
/// seconds: the material bounds, every band edge, every existing razor edge,
/// the shot in/out, the playhead's material projection, and any audio
/// landmarks the owner supplies (region edges, mic take bounds — output
/// positions pulled back through `materialSeconds(forOutputSeconds:)`, so
/// "cut where the audio ends" is a magnet, not an eyeball). Option bypasses
/// at the gesture, exactly like the audio lanes.
func shotStripSnapTargets(
    assembly: ShotCutAssembly,
    cutList: ShotCutList,
    playheadMaterialSeconds: Double,
    audioLandmarkMaterialSeconds: [Double] = []
) -> [Double] {
    var targets: [Double] = [0, assembly.materialSeconds, playheadMaterialSeconds]
    for clip in assembly.planClips {
        targets.append(clip.materialStartSeconds)
        targets.append(clip.materialStartSeconds + clip.materialSeconds)
    }
    for cut in cutList.segmentCuts {
        if let range = shotRazorCutMaterialRange(cut: cut, assembly: assembly) {
            targets.append(range.lowerBound)
            targets.append(range.upperBound)
        }
    }
    if let inPoint = cutList.shotInSeconds { targets.append(inPoint) }
    if let outPoint = cutList.shotOutSeconds { targets.append(outPoint) }
    targets.append(contentsOf: audioLandmarkMaterialSeconds)
    return targets
}
