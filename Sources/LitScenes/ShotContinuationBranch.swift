import Foundation

/// An editable branch shares immutable media, but owns every placement and choice.
func branchShotContinuationSequence(_ source: ProjectShot, plan: [ShotRenderPlanSegment], now: String) -> ProjectShot {
    guard !source.continuationRecords.isEmpty || !source.outputScopes.isEmpty else { return source.duplicated(now: now) }
    var copy = source
    copy.shotId = "shot_\(UUID().uuidString.lowercased())"
    func fresh(_ kind: String, _ old: String) -> String { "\(kind)_\(shortHash("\(copy.shotId):\(old)", length: 18))" }
    let entries = Dictionary(uniqueKeysWithValues: source.entries.map { ($0.entryId, fresh("entry", $0.entryId)) })
    func entry(_ id: String) -> String { entries[id] ?? id }
    var keys: [String: String] = [:]
    func remapClip(_ clip: ShotRenderSegmentClip) -> ShotRenderSegmentClip {
        var saved = clip
        saved.placementStartEntryId = entry(clip.placementStartEntryId)
        saved.placementEndEntryId = entry(clip.placementEndEntryId)
        if saved.sourceCutId.isEmpty { saved.sourceCutId = source.shotId }
        if saved.sourceRenderVersionId.isEmpty { saved.sourceRenderVersionId = source.playableRenderVersion?.versionId ?? "" }
        keys[clip.placementKey] = saved.placementKey
        return saved
    }
    copy.entries = source.entries.map { raw in
        var value = raw; value.entryId = entry(raw.entryId); return value
    }
    copy.branchedFromShotId = source.shotId
    copy.combinedSources = source.combinedSources.map { raw in
        var value = raw
        value.sourceId = fresh("branch_source", raw.sourceId)
        value.parentEntryIds = raw.parentEntryIds.map(entry)
        return value
    }
    copy.renderArtifact = nil
    copy.renderVersions = []
    copy.activeRenderVersionId = ""
    copy.seedSegmentClips = []
    for segment in plan {
        let clip: ShotRenderSegmentClip?
        switch segment {
        case .preserved(let saved): clip = saved.clip
        case .generated(let item):
            clip = source.continuationRecord(entryId: item.pair.endPlacementEntryId)?.selectedTake?.segmentClip
                ?? source.playableRenderVersion?.segmentClip(placementStartEntryId: item.pair.startPlacementEntryId,
                    placementEndEntryId: item.pair.endPlacementEntryId, forStart: item.pair.start?.imageId ?? "", end: item.pair.end?.imageId ?? "")
                ?? source.seedSegmentClips.first { $0.placementKey == item.pair.placementKey }
        case .footage(let placed):
            clip = source.playableRenderVersion?.segmentClip(placementStartEntryId: placed.clip.entryId,
                placementEndEntryId: "", forStart: placed.clip.footageKey, end: "")
                ?? source.seedSegmentClips.first { $0.placementKey == placed.placementKey }
        case .artifactFallback: clip = nil
        }
        if let clip { copy.seedSegmentClips.append(remapClip(clip)) }
    }
    copy.continuationRecords = source.continuationRecords.compactMap { record in
        guard let selected = record.selectedTake else { return nil }
        var value = record
        value.entryId = entry(record.entryId)
        value.sourceEntryId = entry(record.sourceEntryId)
        value.renderingTakeId = ""
        value.rebuildPending = false
        // Take identity and anchor describe the original provider interaction.
        // Only the branch's placement references change.
        var take = selected
        if take.targetFrame != nil { take.targetFrame?.entryId = entry(record.entryId) }
        take.segmentClip = selected.segmentClip.map(remapClip)
        value.takes = [take]
        value.preservedSourceClips = (shotContinuationRenderedSourceClips(shot: source, record: record)?.clips ?? []).map(remapClip)
        return value
    }
    for original in source.segmentPromptOverrides {
        let newKey = shotPlacementSegmentKey(startEntryId: entry(original.placementStartEntryId), endEntryId: entry(original.placementEndEntryId), legacyStartId: original.startFrameImageId, legacyEndId: original.endFrameImageId)
        keys[shotPlacementSegmentKey(startEntryId: original.placementStartEntryId, endEntryId: original.placementEndEntryId, legacyStartId: original.startFrameImageId, legacyEndId: original.endFrameImageId)] = newKey
    }
    copy.segmentPromptOverrides = source.segmentPromptOverrides.map { raw in
        var value = raw; value.placementStartEntryId = entry(raw.placementStartEntryId); value.placementEndEntryId = entry(raw.placementEndEntryId); return value
    }
    copy.segmentRenderOverrides = source.segmentRenderOverrides.map { raw in
        var value = raw; value.placementStartEntryId = entry(raw.placementStartEntryId); value.placementEndEntryId = entry(raw.placementEndEntryId); return value
    }
    copy.segmentDirectionPlans = source.segmentDirectionPlans.map { raw in
        var value = raw; value.placementStartEntryId = entry(raw.placementStartEntryId); value.placementEndEntryId = entry(raw.placementEndEntryId); return value
    }
    copy.sourceSegmentAudio = source.sourceSegmentAudio.map { raw in
        var value = raw; value.placementStartEntryId = entry(raw.placementStartEntryId); value.placementEndEntryId = entry(raw.placementEndEntryId); return value
    }
    copy.sourceBoundaries = source.sourceBoundaries.map { raw in
        var value = raw; value.rightEntryId = entry(raw.rightEntryId); return value
    }
    let cuts = Dictionary(uniqueKeysWithValues: source.cutList.segmentCuts.map { ($0.cutId, fresh("cut", $0.cutId)) })
    copy.cutList.segmentCuts = source.cutList.segmentCuts.map { raw in
        var value = raw; value.cutId = cuts[raw.cutId] ?? raw.cutId; value.segmentKey = keys[raw.segmentKey] ?? raw.segmentKey; return value
    }
    copy.pictureInsertions = source.pictureInsertions.map { raw in
        var value = raw
        value.insertionId = fresh("insertion", raw.insertionId)
        value.anchorSegmentKey = keys[raw.anchorSegmentKey] ?? raw.anchorSegmentKey
        value.sourceSegmentKey = keys[raw.sourceSegmentKey] ?? raw.sourceSegmentKey
        value.replacesRazorCutIds = raw.replacesRazorCutIds.map { cuts[$0] ?? $0 }
        return value
    }
    copy.joinBridgeVersions = source.joinBridgeVersions.map { raw in
        var value = raw; value.cutId = cuts[raw.cutId] ?? raw.cutId; value.sourceSegmentKey = keys[raw.sourceSegmentKey] ?? raw.sourceSegmentKey; return value
    }
    copy.audioRegions = source.audioRegions.map { raw in
        var value = raw; value.regionId = fresh("audio_region", raw.regionId); return value
    }
    let scopes = copyShotOutputScopes(from: source, entries: entries, keys: keys, seed: copy.shotId)
    copy.outputScopes = scopes.scopes
    let scopeKeys = Dictionary(uniqueKeysWithValues: source.outputScopes.compactMap { original -> (String, String)? in
        guard let mapped = scopes.scopes.first(where: { $0.scopeId == scopes.scopeIds[original.scopeId] }) else { return nil }
        return (original.placementKey, mapped.placementKey)
    })
    copy.cutList.segmentCuts = copy.cutList.segmentCuts.map { original in
        var cut = original
        cut.segmentKey = scopeKeys[cut.segmentKey] ?? cut.segmentKey
        cut.sourceScope = cut.sourceScope?.remapping(scopes.scopeIds)
        return cut
    }
    copy.pictureInsertions = copy.pictureInsertions.map { original in
        var insertion = original
        insertion.sourceSegmentKey = scopeKeys[insertion.sourceSegmentKey] ?? insertion.sourceSegmentKey
        insertion.anchorSegmentKey = scopeKeys[insertion.anchorSegmentKey] ?? insertion.anchorSegmentKey
        insertion.sourceScope = insertion.sourceScope?.remapping(scopes.scopeIds)
        return insertion
    }
    copy.joinBridgeVersions += scopes.bridges
    copy.lookVersions += scopes.looks
    copy.continuationRecords = copy.continuationRecords.map { record in
        var value = record
        let original = record.outputScopeId ?? record.selectedTake?.anchor.outputReview?.scope.scopeId ?? ""
        value.outputScopeId = scopes.scopeIds[original] ?? record.outputScopeId
        return value
    }
    copy.createdAt = now
    copy.updatedAt = now
    return rebindCopiedScopeCaches(from: source, to: copy.normalized(), scopeIds: scopes.scopeIds)
}
