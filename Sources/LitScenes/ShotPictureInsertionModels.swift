import Foundation

// MARK: - Picture insertions (the arrangement layer above the cut plan)

/// One arranged copy of picture material, spliced into the output after the
/// cut plan derives kept spans. Free by construction: applying an insertion
/// never touches a file on disk, never invents a generated pair, and never
/// costs a render — it is composition state exactly like a razor.
///
/// Identity split (the razor-vs-mute dichotomy, applied deliberately):
/// - The SOURCE pins the exact take file (`sourceClipPath`), because a copy is
///   about PIXELS — new pixels ≠ old timings, so a copy of a superseded take
///   goes INERT (derived, never stored) until the operator re-copies.
///   Footage sources resolve by absolute path first (the audio-region law)
///   with `sourceMediaId` retained for relink.
/// - The ANCHOR pins only the segment key (`anchorSegmentKey`), because WHERE
///   the copy plays is about the SEGMENT: a re-render of the anchor (or a
///   neighbor) must never kill a loop. `anchorSeconds` clamps onto whatever
///   take currently plays there.
struct ShotPictureInsertion: Codable, Hashable, Sendable, Identifiable {
    var insertionId: String = ""
    var sourceSegmentKey: String = ""
    /// Absolute file path of the copied pixels: a generated take's saved clip,
    /// or a footage file. Never rewritten by re-renders.
    var sourceClipPath: String = ""
    /// Footage only ("" on generated sources): the tray media id, kept so a
    /// moved library can relink the file later.
    var sourceMediaId: String = ""
    /// File-local seconds inside `sourceClipPath`.
    var sourceStartSeconds: Double = 0
    var sourceEndSeconds: Double = 0
    /// Soft anchor: segment key + clip-local seconds, no clip path (see above).
    var anchorSegmentKey: String = ""
    var anchorSeconds: Double = 0
    /// 0.25…4; output duration = source span ÷ rate.
    var playbackRate: Double = 1
    /// THE CARRIAGE VETO: a muted copy rides `includeAudio = false` on its
    /// playback item — the gain law itself is untouched.
    var muteSourceAudio: Bool = false
    /// Reserved (mirrors ShotAudioRegion vocabulary); "" = default.
    var pitchMode: String = ""
    /// THE TRANSFORM LADDER, reserved: "" = identity (v1's only value). A
    /// non-empty kind this build doesn't implement renders the copy inert with
    /// a visible badge — never silently dropped, never pretending to have run.
    var transformKind: String = ""
    /// Opaque spec for future transform kinds; carried verbatim.
    var transformSpec: String = ""
    /// Loop siblings share a group id — display consolidation and group-scope
    /// edits only, zero behavioral weight in the splice.
    var loopGroupId: String = ""
    /// THE SPEED SECTION LINK: the razor cuts this copy replaces (a section
    /// slowed/sped in place = razored base material + this carrier playing it
    /// at `playbackRate`). Deleting the carrier restores them; restoring them
    /// deletes the carrier; re-copy re-pins them. Dangling ids are inert and
    /// tolerated everywhere — removal filters by live cuts, never asserts.
    var replacesRazorCutIds: [String] = []
    var updatedAt: String = ""

    /// Wide on purpose (locked): the safety is THE 2-FRAME OUTPUT LAW at
    /// every rate change, not the clamp — extremes are legal and merely look
    /// like what they are (dropped/repeated frames).
    static let minimumRate: Double = 0.1
    static let maximumRate: Double = 8

    var id: String { insertionId }
    var isFootageSource: Bool { !sourceMediaId.trimmed.isEmpty }
    var sourceSeconds: Double { max(sourceEndSeconds - sourceStartSeconds, 0) }
    var outputSeconds: Double {
        let rate = min(max(playbackRate, Self.minimumRate), Self.maximumRate)
        return rate > 0 ? sourceSeconds / rate : sourceSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case insertionId, sourceSegmentKey, sourceClipPath, sourceMediaId
        case sourceStartSeconds, sourceEndSeconds
        case anchorSegmentKey, anchorSeconds
        case playbackRate, muteSourceAudio, pitchMode
        case transformKind, transformSpec
        case loopGroupId, replacesRazorCutIds, updatedAt
    }

    init(
        insertionId: String = "",
        sourceSegmentKey: String = "",
        sourceClipPath: String = "",
        sourceMediaId: String = "",
        sourceStartSeconds: Double = 0,
        sourceEndSeconds: Double = 0,
        anchorSegmentKey: String = "",
        anchorSeconds: Double = 0,
        playbackRate: Double = 1,
        muteSourceAudio: Bool = false,
        pitchMode: String = "",
        transformKind: String = "",
        transformSpec: String = "",
        loopGroupId: String = "",
        replacesRazorCutIds: [String] = [],
        updatedAt: String = ""
    ) {
        self.insertionId = insertionId.trimmed.nilIfEmpty
            ?? "pins_\(UUID().uuidString.lowercased())"
        self.sourceSegmentKey = sourceSegmentKey
        self.sourceClipPath = sourceClipPath
        self.sourceMediaId = sourceMediaId
        self.sourceStartSeconds = sourceStartSeconds
        self.sourceEndSeconds = sourceEndSeconds
        self.anchorSegmentKey = anchorSegmentKey
        self.anchorSeconds = anchorSeconds
        self.playbackRate = playbackRate
        self.muteSourceAudio = muteSourceAudio
        self.pitchMode = pitchMode
        self.transformKind = transformKind
        self.transformSpec = transformSpec
        self.loopGroupId = loopGroupId
        self.replacesRazorCutIds = replacesRazorCutIds
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        insertionId = try container.decodeIfPresent(String.self, forKey: .insertionId) ?? ""
        sourceSegmentKey = try container.decodeIfPresent(String.self, forKey: .sourceSegmentKey) ?? ""
        sourceClipPath = try container.decodeIfPresent(String.self, forKey: .sourceClipPath) ?? ""
        sourceMediaId = try container.decodeIfPresent(String.self, forKey: .sourceMediaId) ?? ""
        sourceStartSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceStartSeconds) ?? 0
        sourceEndSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceEndSeconds) ?? 0
        anchorSegmentKey = try container.decodeIfPresent(String.self, forKey: .anchorSegmentKey) ?? ""
        anchorSeconds = try container.decodeIfPresent(Double.self, forKey: .anchorSeconds) ?? 0
        playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate) ?? 1
        muteSourceAudio = try container.decodeIfPresent(Bool.self, forKey: .muteSourceAudio) ?? false
        pitchMode = try container.decodeIfPresent(String.self, forKey: .pitchMode) ?? ""
        transformKind = try container.decodeIfPresent(String.self, forKey: .transformKind) ?? ""
        transformSpec = try container.decodeIfPresent(String.self, forKey: .transformSpec) ?? ""
        loopGroupId = try container.decodeIfPresent(String.self, forKey: .loopGroupId) ?? ""
        replacesRazorCutIds = ((try? container.decodeIfPresent([String].self, forKey: .replacesRazorCutIds)) ?? nil) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    /// Clamps the rate, orders inverted source bounds, trims identities.
    func normalized() -> ShotPictureInsertion {
        var value = self
        value.insertionId = value.insertionId.trimmed
        value.sourceSegmentKey = value.sourceSegmentKey.trimmed
        value.sourceClipPath = value.sourceClipPath.trimmed
        value.sourceMediaId = value.sourceMediaId.trimmed
        value.anchorSegmentKey = value.anchorSegmentKey.trimmed
        value.sourceStartSeconds = max(value.sourceStartSeconds, 0)
        value.sourceEndSeconds = max(value.sourceEndSeconds, 0)
        if value.sourceEndSeconds < value.sourceStartSeconds {
            swap(&value.sourceStartSeconds, &value.sourceEndSeconds)
        }
        value.anchorSeconds = max(value.anchorSeconds, 0)
        value.playbackRate = min(max(value.playbackRate, Self.minimumRate), Self.maximumRate)
        value.replacesRazorCutIds = value.replacesRazorCutIds
            .map(\.trimmed)
            .filter { !$0.isEmpty }
        return value
    }
}

// MARK: - Segment-key producibility (the one predicate, shared with razor pruning)

/// Whether a durable segment key can still be produced by a strip — THE
/// PRODUCIBILITY LAW extracted from `ShotCutList.pruned(entries:)` so razors
/// and insertion anchors prune by the same tolerance (still-present but
/// non-adjacent pairs survive; the user may reorder them back together).
struct ShotSegmentKeyIdentity {
    var presentEntryIds: Set<String>
    var presentIds: Set<String>

    init(entries: [ShotFrameEntry]) {
        presentEntryIds = Set(entries.map(\.entryId))
        var ids = Set(entries.map(\.frameImageId))
        ids.remove("")
        for entry in entries where entry.isClip {
            let key = shotFootageKey(
                mediaId: entry.clipMediaId,
                startSeconds: entry.clipStartSeconds,
                endSeconds: entry.clipEndSeconds
            )
            let boundary = shotFootageBoundaryFrameIds(
                mediaId: entry.clipMediaId,
                startSeconds: entry.clipStartSeconds,
                endSeconds: entry.clipEndSeconds
            )
            ids.insert(key)
            ids.insert(boundary.start)
            ids.insert(boundary.end)
        }
        presentIds = ids
    }

    func canProduce(_ segmentKey: String) -> Bool {
        // Artifact bands are producible whenever their key is well-formed:
        // whether the VERSION still exists is version honesty, and that is
        // the engine sweep's job (same division of labor as insertion
        // sources below). Without this branch `settingCutList`'s prune would
        // kill every artifact cut on the very save that created it.
        if segmentKey.hasPrefix(shotArtifactSegmentKeyPrefix) {
            return shotArtifactSegmentKeyVersionId(segmentKey) != nil
        }
        if segmentKey.hasPrefix("entry:") {
            let placement = String(segmentKey.dropFirst("entry:".count))
                .split(separator: ">", maxSplits: 1, omittingEmptySubsequences: false)
            let first = placement.first.map(String.init) ?? ""
            let second = placement.count > 1 ? String(placement[1]) : ""
            let startOK = first.isEmpty || presentEntryIds.contains(first)
            let endOK = second.isEmpty || presentEntryIds.contains(second)
            return (!first.isEmpty || !second.isEmpty) && startOK && endOK
        }
        let parts = segmentKey.split(separator: ">", maxSplits: 1, omittingEmptySubsequences: false)
        let first = parts.first.map(String.init) ?? ""
        let second = parts.count > 1 ? String(parts[1]) : ""
        // Empty first half = an AI lead-in key (">anchor") — legal iff its
        // anchor is still present; an all-empty key is never legal.
        if first.isEmpty {
            return !second.isEmpty && presentIds.contains(second)
        }
        guard presentIds.contains(first) else { return false }
        return second.isEmpty || presentIds.contains(second)
    }
}

/// Drops insertions whose ANCHOR segment can no longer exist in this strip.
/// The SOURCE side is deliberately unchecked here — sources are file-level
/// (a copied span outlives its base placement); source honesty is the
/// freshness derivation's job, and source retention is the engine sweep's.
func pruningPictureInsertions(
    _ insertions: [ShotPictureInsertion],
    entries: [ShotFrameEntry]
) -> [ShotPictureInsertion] {
    let identity = ShotSegmentKeyIdentity(entries: entries)
    return insertions
        .map { $0.normalized() }
        .filter { insertion in
            !insertion.insertionId.isEmpty
                && (!insertion.sourceClipPath.isEmpty || !insertion.sourceMediaId.isEmpty)
                && insertion.sourceSeconds >= ShotCutList.minimumRangeSeconds
                && !insertion.anchorSegmentKey.isEmpty
                && identity.canProduce(insertion.anchorSegmentKey)
        }
}

/// The left placement entry id of a durable segment key, for entry-order
/// fallback anchoring. nil on legacy (frame-id) keys.
func shotSegmentKeyLeftEntryId(_ segmentKey: String) -> String? {
    guard segmentKey.hasPrefix("entry:") else { return nil }
    let placement = String(segmentKey.dropFirst("entry:".count))
        .split(separator: ">", maxSplits: 1, omittingEmptySubsequences: false)
    let first = placement.first.map(String.init) ?? ""
    let second = placement.count > 1 ? String(placement[1]) : ""
    return (first.nilIfEmpty ?? second.nilIfEmpty)
}

/// The right placement entry id (falls back to the left for one-sided keys).
func shotSegmentKeyRightEntryId(_ segmentKey: String) -> String? {
    guard segmentKey.hasPrefix("entry:") else { return nil }
    let placement = String(segmentKey.dropFirst("entry:".count))
        .split(separator: ">", maxSplits: 1, omittingEmptySubsequences: false)
    let first = placement.first.map(String.init) ?? ""
    let second = placement.count > 1 ? String(placement[1]) : ""
    return (second.nilIfEmpty ?? first.nilIfEmpty)
}

// MARK: - Derived freshness + strip cells

/// Why an insertion is (or isn't) contributing to the output right now.
/// Derived at assembly time, never stored — freshness is a comparison against
/// the take that currently plays, not a fact about the insertion.
enum ShotInsertionSourceState: Equatable {
    case fresh
    /// The copied take is no longer the segment's active take (or the segment
    /// no longer renders). The copy plays nothing; RE-COPY re-mints it on the
    /// current take at the same seconds. Pixels never swap silently.
    case olderTake
    /// The source file is gone from disk.
    case sourceMissing
    /// A transform kind this build doesn't implement.
    case unsupportedTransform
    /// THE MATERIAL-WINDOW LAW: the shot IN/OUT pair excludes this copy — its
    /// splice point sits outside the window, or the window clips its material
    /// below the razor minimum. It plays nothing while the trim stands and
    /// comes back the moment the handles move; never silently dropped.
    case trimmedOut

    var isFresh: Bool { self == .fresh }

    var badge: String {
        switch self {
        case .fresh: return ""
        case .olderTake: return "OLDER TAKE"
        case .sourceMissing: return "SOURCE MISSING"
        case .unsupportedTransform: return "UNSUPPORTED"
        case .trimmedOut: return "TRIMMED OUT"
        }
    }
}

/// One insertion's derived display state: where its cell sits in the strip's
/// cell flow, where it plays in the output, and whether it plays at all.
struct ShotInsertionCell: Identifiable, Equatable {
    var insertion: ShotPictureInsertion
    var state: ShotInsertionSourceState = .fresh
    /// Where the copy plays (or would play, when inert) on the output timeline.
    var outputStartSeconds: Double = 0
    /// Cell flow position: drawn after this band index; nil = before band 0.
    var afterBandIndex: Int? = nil
    /// The in-band anchor instant (material seconds) when the splice point is
    /// strictly inside a band — drawn as a leader tick. nil at band edges.
    var anchorMaterialSeconds: Double? = nil
    /// The seconds this copy ACTUALLY plays — the window-clamped duration the
    /// spliced item carries, 0 when inert. Strip geometry must measure with
    /// THIS, never `insertion.outputSeconds` (the authored span), or a clamped
    /// copy draws at its pre-trim width and shifts everything after it.
    var placedOutputSeconds: Double = 0

    var id: String { insertion.insertionId }
}

// MARK: - The splice (pure; runs inside shotCutAssembly, before reverse)

/// Splices fresh picture insertions into the derived playback items and
/// re-chains the output timeline. Pure and injectable like `shotCutPlan`.
///
/// Position law:
/// - The anchor resolves inside its own band's kept material: strictly inside
///   a kept span ⇒ a DERIVED split at the anchor instant (the persisted cut
///   list is never touched); in a razored gap or at an edge ⇒ snaps to the
///   kept boundary.
/// - An anchor whose band is absent (skipped, seam-cut, healed) falls back to
///   entry order: the copy splices after the last surviving band whose right
///   placement entry sits at or before the anchor's left entry — so a copy of
///   a seam-cut beat still plays exactly where the beat was (THE REPLACE
///   PATTERN: skip the original, keep the modified copy).
/// - A position that lands inside an already-placed insertion run advances
///   past the run (paste order is presentation order).
///
/// Seam law: every insertion boundary is a hard cut — zero transition frames,
/// zero handoff shave — and a base item that comes to directly follow an
/// insertion drops its dissolve frames (a dissolve blends adjacent material;
/// the copy between them is neither side's material).
///
/// THE MATERIAL-WINDOW LAW: the shot IN/OUT pair governs copies exactly as it
/// governs base material. A copy whose splice point falls outside `[in, out]`
/// plays nothing (badged TRIMMED OUT, never silently dropped) — the bounds are
/// CLOSED, so a paste at the exact OUT boundary (the tail of a trimmed shot's
/// kept output, where `shotPasteAnchor` lands) still plays. A copy of on-strip
/// material additionally has its source span clipped to the window rate-aware —
/// the same clamp `shotCutPlan` applies to base keeps, so a speed carrier or
/// loop of tail material ends where the OUT handle says the shot ends, and a
/// copy showing ONLY out-of-window material goes TRIMMED OUT wherever it is
/// pasted (locked: the window hides material everywhere, copies included).
func shotPictureInsertionSplice(
    insertions: [ShotPictureInsertion],
    entries: [ShotFrameEntry],
    planClips: [ShotCutPlanClip],
    playbackItems: [ShotCutPlaybackItem],
    /// The shot-level trim, material seconds (`shotCutPlan`'s own window).
    /// nil = untrimmed on that side.
    shotInSeconds: Double? = nil,
    shotOutSeconds: Double? = nil,
    /// The PLAYABLE render version's saved take per segment key — the
    /// freshness authority. Deliberately NOT the plan's clip paths: a
    /// seam-cut segment leaves the plan but its take stays active, and a copy
    /// of that beat must stay fresh (THE REPLACE PATTERN).
    activeTakePathsBySegmentKey: [String: String],
    fileExists: (String) -> Bool
) -> (playbackItems: [ShotCutPlaybackItem], cells: [ShotInsertionCell], outputSeconds: Double) {
    guard !insertions.isEmpty else {
        let total = playbackItems.reduce(0) { max($0, $1.outputStartSeconds + $1.durationSeconds) }
        return (playbackItems, [], total)
    }

    let epsilon = 1.0 / 240.0
    let minimumKeep = ShotCutList.minimumRangeSeconds
    var items = playbackItems
    /// insertionId → (fresh: placed item carries it) | (inert: the itemId it
    /// would follow, "" = front).
    var inertFollows: [String: String] = [:]
    var resolvedBandIndex: [String: Int?] = [:]
    var anchorTicks: [String: Double] = [:]
    var states: [String: ShotInsertionSourceState] = [:]

    let entryIndexById: [String: Int] = Dictionary(
        uniqueKeysWithValues: entries.enumerated().map { ($0.element.entryId, $0.offset) }
    )

    func clipIndex(forSegmentKey key: String) -> Int? {
        planClips.firstIndex { $0.segmentKey == key }
    }

    /// Entry-order fallback: index AFTER which to insert (into `items`), for
    /// an anchor whose band is gone. nil = could not resolve (append at end).
    func fallbackPosition(anchorKey: String) -> Int? {
        guard let leftId = shotSegmentKeyLeftEntryId(anchorKey),
              let anchorLeft = entryIndexById[leftId] else { return nil }
        var position = -1  // -1 = front
        for (index, item) in items.enumerated() where item.insertionId.isEmpty {
            guard !item.segmentKey.isEmpty,
                  let rightId = shotSegmentKeyRightEntryId(item.segmentKey),
                  let rightIndex = entryIndexById[rightId] else { continue }
            if rightIndex <= anchorLeft {
                position = index
            }
        }
        return position
    }

    /// The index in `items` after which the insertion lands (-1 = front),
    /// splitting a base item when the anchor falls strictly inside its kept
    /// span and `allowSplit` (inert copies resolve a position without leaving
    /// a derived split behind). Returns the band index the cell rides and the
    /// optional in-band tick.
    func resolvePosition(
        for insertion: ShotPictureInsertion,
        allowSplit: Bool
    ) -> (afterIndex: Int, bandIndex: Int?, tickMaterial: Double?) {
        if let anchorClipIndex = clipIndex(forSegmentKey: insertion.anchorSegmentKey) {
            let anchorLocal = max(insertion.anchorSeconds, 0)
            let owned = items.indices.filter {
                items[$0].insertionId.isEmpty
                    && items[$0].segmentKey == insertion.anchorSegmentKey
                    && items[$0].keepRange != nil
            }
            if let firstOwned = owned.first {
                // "Before the band's first kept span" = after whatever item
                // precedes it (another band's span or a bridge), never the
                // front of the whole strip.
                var after = firstOwned - 1
                for index in owned {
                    guard let keep = items[index].keepRange else { continue }
                    if keep.end <= anchorLocal + epsilon {
                        after = index
                        continue
                    }
                    if anchorLocal <= keep.start + epsilon { break }
                    // Strictly inside: derived split, unless a sub-minimum
                    // sliver would result (then snap to the nearer boundary).
                    if anchorLocal - keep.start < minimumKeep {
                        after = index - 1
                        break
                    }
                    if keep.end - anchorLocal < minimumKeep || !allowSplit {
                        after = index
                        break
                    }
                    let item = items[index]
                    var head = item
                    var tail = item
                    let splitMaterial = item.materialStartSeconds + (anchorLocal - keep.start)
                    head.keepRange = ShotKeepRange(start: keep.start, end: anchorLocal)
                    head.durationSeconds = anchorLocal - keep.start
                    head.materialEndSeconds = splitMaterial
                    head.itemId = "\(item.itemId)_a"
                    tail.keepRange = ShotKeepRange(start: anchorLocal, end: keep.end)
                    tail.durationSeconds = keep.end - anchorLocal
                    tail.materialStartSeconds = splitMaterial
                    tail.itemId = "\(item.itemId)_b"
                    tail.transitionFramesBefore = 0
                    items.replaceSubrange(index...index, with: [head, tail])
                    return (index, anchorClipIndex, splitMaterial)
                }
                return (after, anchorClipIndex, nil)
            }
            // Band exists but plays nothing (unrendered): entry-order fallback.
        }
        if let fallback = fallbackPosition(anchorKey: insertion.anchorSegmentKey) {
            let bandIndex = fallback >= 0
                ? planClips.firstIndex { $0.segmentKey == items[fallback].segmentKey }
                : nil
            return (fallback, bandIndex, nil)
        }
        return (items.count - 1, planClips.isEmpty ? nil : planClips.count - 1, nil)
    }

    func sourceState(for insertion: ShotPictureInsertion) -> ShotInsertionSourceState {
        guard insertion.transformKind.trimmed.isEmpty else { return .unsupportedTransform }
        if insertion.isFootageSource {
            return fileExists(insertion.sourceClipPath) ? .fresh : .sourceMissing
        }
        guard fileExists(insertion.sourceClipPath) else { return .sourceMissing }
        let activePath = activeTakePathsBySegmentKey[insertion.sourceSegmentKey] ?? ""
        return (!activePath.isEmpty && activePath == insertion.sourceClipPath)
            ? .fresh
            : .olderTake
    }

    let hasWindow = shotInSeconds != nil || shotOutSeconds != nil
    let windowIn = max(shotInSeconds ?? 0, 0)
    let windowOut = shotOutSeconds ?? .infinity
    /// The strip's material end from the PLAN — the stable last-resort gate
    /// position. `items` grows as copies splice, so reading its tail would let
    /// one copy's material span decide the next copy's verdict by array order.
    let stripMaterialEnd = planClips.last.map { $0.materialStartSeconds + $0.materialSeconds }
        ?? (playbackItems.last?.materialEndSeconds ?? 0)

    /// Where an insertion's splice point sits on the MATERIAL timeline — the
    /// anchor's own band position when it resolves (the band occupies material
    /// even unrendered), else the material end of the entry-order fallback
    /// (`fallbackPosition` only lands on BASE items): the same precedence
    /// `resolvePosition` walks, but read-only, so gating a copy out of the
    /// window never leaves a derived split behind. The gate judges the
    /// AUTHORED anchor, not the kept-boundary snap the splice may perform —
    /// a position the operator placed inside trimmed-away material is trimmed
    /// with it.
    func spliceMaterialInstant(for insertion: ShotPictureInsertion) -> Double {
        if let anchorClipIndex = clipIndex(forSegmentKey: insertion.anchorSegmentKey) {
            let clip = planClips[anchorClipIndex]
            let local = max(insertion.anchorSeconds, 0)
            return min(
                max(clip.materialStartSeconds + (local - clip.headSeconds), clip.materialStartSeconds),
                clip.materialStartSeconds + clip.materialSeconds
            )
        }
        if let fallback = fallbackPosition(anchorKey: insertion.anchorSegmentKey) {
            return fallback >= 0 ? items[fallback].materialEndSeconds : 0
        }
        return stripMaterialEnd
    }

    for rawInsertion in insertions {
        let insertion = rawInsertion.normalized()
        let source = sourceState(for: insertion)

        // THE MATERIAL-WINDOW LAW, decided in full BEFORE position resolution
        // so a copy the window excludes never splits a base item it will not
        // sit between. Two halves: the GATE (closed bounds — a paste exactly
        // at the OUT boundary still plays) and the SOURCE CLAMP (an on-strip
        // span keeps only its in-window material, floored by THE 2-FRAME
        // OUTPUT LAW so a high-rate carrier can never survive as a sub-frame
        // sliver the operator cannot see or grab).
        var keepStart = insertion.sourceStartSeconds
        var keepEnd = insertion.sourceEndSeconds
        var windowExcludes = false
        if hasWindow, source.isFresh {
            let instant = spliceMaterialInstant(for: insertion)
            if instant < windowIn - epsilon || instant > windowOut + epsilon {
                windowExcludes = true
            } else if let sourceIndex = clipIndex(forSegmentKey: insertion.sourceSegmentKey) {
                let clip = planClips[sourceIndex]
                // Clamp only on the side a trim actually stands: the head-shave
                // region sits before material 0, and an unconditional max()
                // here would shave untrimmed copies that legitimately keep it.
                if shotInSeconds != nil {
                    keepStart = max(keepStart, (windowIn - clip.materialStartSeconds) + clip.headSeconds)
                }
                if shotOutSeconds != nil {
                    keepEnd = min(keepEnd, (windowOut - clip.materialStartSeconds) + clip.headSeconds)
                }
                let minimumSource = max(
                    minimumKeep,
                    2 * ShotAudioTiming.frameSeconds * insertion.playbackRate
                )
                if keepEnd - keepStart < minimumSource {
                    windowExcludes = true
                }
            }
        }
        let state: ShotInsertionSourceState = windowExcludes ? .trimmedOut : source
        states[insertion.insertionId] = state
        var (afterIndex, bandIndex, tick) = resolvePosition(
            for: insertion,
            allowSplit: state.isFresh
        )
        // Paste order is presentation order: advance past an insertion run.
        while afterIndex + 1 < items.count, !items[afterIndex + 1].insertionId.isEmpty {
            afterIndex += 1
        }
        resolvedBandIndex[insertion.insertionId] = bandIndex
        if let tick { anchorTicks[insertion.insertionId] = tick }

        guard state.isFresh else {
            inertFollows[insertion.insertionId] = afterIndex >= 0 ? items[afterIndex].itemId : ""
            continue
        }

        // Material coordinates: the source band's span when it is on the strip
        // (the playhead honestly revisits the source material during a loop),
        // computed from the CLAMPED keeps; a file-level source with no band
        // collapses to the splice instant.
        var materialStart: Double
        var materialEnd: Double
        if let sourceIndex = clipIndex(forSegmentKey: insertion.sourceSegmentKey) {
            let clip = planClips[sourceIndex]
            let localStart = keepStart - clip.headSeconds
            let localEnd = keepEnd - clip.headSeconds
            materialStart = clip.materialStartSeconds
                + min(max(localStart, 0), clip.materialSeconds)
            materialEnd = clip.materialStartSeconds
                + min(max(localEnd, 0), clip.materialSeconds)
        } else {
            let spliceInstant = afterIndex >= 0 ? items[afterIndex].materialEndSeconds : 0
            materialStart = spliceInstant
            materialEnd = spliceInstant
        }

        let rate = insertion.playbackRate
        var item = ShotCutPlaybackItem(
            itemId: "insert_\(insertion.insertionId)",
            segmentKey: insertion.sourceSegmentKey,
            url: URL(fileURLWithPath: insertion.sourceClipPath),
            keepRange: ShotKeepRange(start: keepStart, end: keepEnd),
            transitionFramesBefore: 0,
            includeAudio: !insertion.muteSourceAudio,
            outputStartSeconds: 0,
            durationSeconds: rate > 0 ? (keepEnd - keepStart) / rate : keepEnd - keepStart,
            materialStartSeconds: materialStart,
            materialEndSeconds: materialEnd
        )
        item.insertionId = insertion.insertionId
        item.playbackRate = rate
        items.insert(item, at: afterIndex + 1)
        // The base item now following the copy must not dissolve across it.
        let followerIndex = afterIndex + 2
        if items.indices.contains(followerIndex),
           items[followerIndex].insertionId.isEmpty,
           items[followerIndex].transitionFramesBefore > 0 {
            items[followerIndex].transitionFramesBefore = 0
        }
    }

    // Re-chain the output timeline over the final order.
    var cursor = 0.0
    var outputByItemId: [String: Double] = [:]
    for index in items.indices {
        items[index].outputStartSeconds = cursor
        outputByItemId[items[index].itemId] = cursor
        cursor += items[index].durationSeconds
    }

    var cells: [ShotInsertionCell] = []
    for rawInsertion in insertions {
        let insertion = rawInsertion.normalized()
        let state = states[insertion.insertionId] ?? .fresh
        var output = 0.0
        var placedSeconds = 0.0
        if state.isFresh {
            let itemId = "insert_\(insertion.insertionId)"
            output = outputByItemId[itemId] ?? 0
            placedSeconds = items.first(where: { $0.itemId == itemId })?.durationSeconds ?? 0
        } else if let follows = inertFollows[insertion.insertionId], !follows.isEmpty {
            if let item = items.first(where: { $0.itemId == follows }) {
                output = item.outputStartSeconds + item.durationSeconds
            }
        }
        cells.append(ShotInsertionCell(
            insertion: insertion,
            state: state,
            outputStartSeconds: output,
            afterBandIndex: resolvedBandIndex[insertion.insertionId] ?? nil,
            anchorMaterialSeconds: anchorTicks[insertion.insertionId],
            placedOutputSeconds: placedSeconds
        ))
    }
    return (items, cells, cursor)
}

/// THE ACTIVE TAKE AUTHORITY: the file each segment key CURRENTLY plays —
/// the playable version's clip where one exists, else the seed clip (the
/// same `saved ?? seedClip` precedence band resolution uses). This is the
/// freshness referee for arranged copies, and it must cover BOTH sources:
/// judging by version clips alone made every copy on a seed-covered segment
/// (combined CUTs, pasted segment cards) OLDER-TAKE-inert at birth — a
/// SPEED gesture then razored the material and played nothing in the gap,
/// reading as "speed deleted my section". Deliberately NOT the
/// plan's clip paths: a seam-cut segment leaves the plan but its take stays
/// active (THE REPLACE PATTERN).
func shotActiveTakePathsBySegmentKey(shot: ProjectShot) -> [String: String] {
    var paths: [String: String] = [:]
    for seed in shot.seedSegmentClips where !seed.clipPath.trimmed.isEmpty {
        paths[seed.placementKey] = seed.clipPath
    }
    for saved in shot.playableRenderVersion?.segmentClips ?? []
        where !saved.clipPath.trimmed.isEmpty {
        paths[saved.placementKey] = saved.clipPath
    }
    return paths
}

/// THE PIN SWEEP LAW, applied to arranged copies (mirrors
/// `shotStalePinnedCutIds`): a generated copy is swept only when its pinned
/// take file belongs to NO retained take — until then it merely goes inert
/// (OLDER TAKE) and stays re-copyable. Footage copies are file-level and are
/// never swept here.
func shotStalePictureInsertionIds(shot: ProjectShot) -> [String] {
    guard !shot.pictureInsertions.isEmpty else { return [] }
    var retained = Set<String>()
    for version in shot.renderVersions {
        for clip in version.segmentClips where !clip.clipPath.isEmpty {
            retained.insert(clip.clipPath)
        }
        // Copies captured off a synthetic artifact band pin the version's
        // full video — retain it by the same law as its segment clips.
        if !version.videoPath.trimmed.isEmpty {
            retained.insert(version.videoPath.trimmed)
        }
    }
    for clip in shot.seedSegmentClips where !clip.clipPath.isEmpty {
        retained.insert(clip.clipPath)
    }
    return shot.pictureInsertions
        .filter { !$0.isFootageSource && !$0.sourceClipPath.isEmpty && !retained.contains($0.sourceClipPath) }
        .map(\.insertionId)
}

/// "0.5×" / "1×" / "1.5×" — one formatting law for status lines and chips.
func shotInsertionRateLabel(_ rate: Double) -> String {
    let value = String(format: "%g", rate)
    return "\(value)×"
}

// MARK: - Copy / paste resolution (THE WYSIWYG COPY LAW)

/// The ordered kept material spans under a material-space selection — copy
/// captures exactly what plays there. Bridges are seam glue (no durable
/// segment identity, so a pasted bridge could never be fresh) and arranged
/// copies duplicate their source's material span; both are excluded, so a
/// selection over a loop copies the base pixels exactly once. Resolve against
/// the FORWARD assembly: reversed items read from proxy files in proxy
/// coordinates, and a copy must pin source files.
func shotCopiedSpans(
    assembly: ShotCutAssembly,
    materialStart: Double,
    materialEnd: Double
) -> [ShotPictureSegmentSpanRef] {
    let low = min(materialStart, materialEnd)
    let high = max(materialStart, materialEnd)
    var spans: [ShotPictureSegmentSpanRef] = []
    for item in assembly.playbackItems where !item.isBridge && !item.isInsertion {
        guard let keep = item.keepRange else { continue }
        let start = max(low, item.materialStartSeconds)
        let end = min(high, item.materialEndSeconds)
        guard end - start >= ShotCutList.minimumRangeSeconds else { continue }
        let bandIndex = assembly.planClips.firstIndex { $0.segmentKey == item.segmentKey }
        let band = bandIndex.flatMap { assembly.bands.indices.contains($0) ? assembly.bands[$0] : nil }
        var mediaId = ""
        if let band, case .footage(let segment) = band.segment {
            mediaId = segment.clip.mediaId
        }
        spans.append(ShotPictureSegmentSpanRef(
            segmentKey: item.segmentKey,
            clipPath: item.url.path,
            mediaId: mediaId,
            startSeconds: keep.start + (start - item.materialStartSeconds),
            endSeconds: keep.start + (end - item.materialStartSeconds),
            label: band?.label ?? ""
        ))
    }
    // Coalesce file-contiguous spans (a derived split around an existing
    // copy, or abutting keeps) — one continuous stretch should paste as one
    // copy, not a stack of seams.
    var merged: [ShotPictureSegmentSpanRef] = []
    for span in spans {
        if var last = merged.last,
           last.segmentKey == span.segmentKey,
           last.clipPath == span.clipPath,
           abs(last.endSeconds - span.startSeconds) <= 1.0 / 240.0 {
            last.endSeconds = span.endSeconds
            merged[merged.count - 1] = last
        } else {
            merged.append(span)
        }
    }
    return merged
}

/// The copy-time context bundle — what a future paste planner reads. Derived
/// from the bands the selection covers and their neighbors; every field is
/// best-effort and an empty context is legal.
func shotCopiedSegmentContext(
    assembly: ShotCutAssembly,
    materialStart: Double,
    materialEnd: Double,
    lookSummary: String,
    now: String
) -> ShotSegmentContext {
    let low = min(materialStart, materialEnd)
    let high = max(materialStart, materialEnd)
    var context = ShotSegmentContext(lookSummary: lookSummary, copiedAt: now)
    for (index, clip) in assembly.planClips.enumerated() {
        guard assembly.bands.indices.contains(index) else { continue }
        let band = assembly.bands[index]
        let clipLow = clip.materialStartSeconds
        let clipHigh = clip.materialStartSeconds + clip.materialSeconds
        if clipHigh <= low {
            context.previousSegmentLabel = band.label
            continue
        }
        if clipLow >= high {
            if context.nextSegmentLabel.isEmpty { context.nextSegmentLabel = band.label }
            continue
        }
        // Covered band: first generated one supplies the authored prompt,
        // first footage one the filename.
        if context.authoredPrompt.isEmpty, case .generated(let item) = band.segment {
            context.authoredPrompt = item.overridePrompt ?? item.generatedPrompt
        }
        if context.clipFilename.isEmpty, case .footage(let segment) = band.segment {
            context.clipFilename = segment.clip.filename
        }
    }
    return context
}

/// Where a paste at this OUTPUT instant anchors: inside a base span, that
/// segment + file-local seconds; inside an arranged copy, the copy's own
/// anchor (the splice then advances past the run — paste lands after it);
/// inside a bridge, the next base span's head; past the end, after the last
/// base span. nil when nothing plays. Call with the FORWARD assembly.
func shotPasteAnchor(
    assembly: ShotCutAssembly,
    outputSeconds: Double
) -> ShotSegmentPasteAnchor? {
    let items = assembly.playbackItems
    guard !items.isEmpty else { return nil }
    let epsilon = 1.0 / 240.0
    for (index, item) in items.enumerated() {
        let end = item.outputStartSeconds + item.durationSeconds
        guard outputSeconds < end - epsilon || index == items.count - 1 else { continue }
        if item.isInsertion {
            if let cell = assembly.insertionCells.first(where: {
                $0.insertion.insertionId == item.insertionId
            }) {
                return ShotSegmentPasteAnchor(
                    segmentKey: cell.insertion.anchorSegmentKey,
                    anchorSeconds: cell.insertion.anchorSeconds
                )
            }
            continue
        }
        if item.isBridge {
            for next in items.dropFirst(index + 1) where !next.isBridge && !next.isInsertion {
                if let keep = next.keepRange {
                    return ShotSegmentPasteAnchor(segmentKey: next.segmentKey, anchorSeconds: keep.start)
                }
            }
            continue
        }
        guard let keep = item.keepRange else { continue }
        let local = keep.start + min(max(outputSeconds - item.outputStartSeconds, 0), item.durationSeconds)
        return ShotSegmentPasteAnchor(segmentKey: item.segmentKey, anchorSeconds: local)
    }
    for item in items.reversed() where !item.isBridge && !item.isInsertion {
        if let keep = item.keepRange {
            return ShotSegmentPasteAnchor(segmentKey: item.segmentKey, anchorSeconds: keep.end)
        }
    }
    return nil
}

/// Display consolidation: consecutive sibling copies (same non-empty loop
/// group, same position, source span, rate, mute, and state) draw as ONE
/// cell with an ×N badge; anything non-uniform stays its own cell. Editing a
/// single member (via the popover's per-copy disclosure) un-consolidates it
/// by construction — its row stops matching.
/// The consolidated run a leader id fronts, resolved the same way the strip
/// draws it (per-band grouping, then run consolidation). nil when the id
/// isn't a run leader.
func shotInsertionRun(
    in cells: [ShotInsertionCell],
    leaderId: String
) -> [ShotInsertionCell]? {
    var byBand: [Int?: [ShotInsertionCell]] = [:]
    for cell in cells {
        byBand[cell.afterBandIndex, default: []].append(cell)
    }
    for group in byBand.values {
        for run in shotInsertionCellRuns(group)
            where run.first?.insertion.insertionId == leaderId {
            return run
        }
    }
    return nil
}

func shotInsertionCellRuns(_ cells: [ShotInsertionCell]) -> [[ShotInsertionCell]] {
    var runs: [[ShotInsertionCell]] = []
    for cell in cells {
        if let last = runs.last, let first = last.first,
           !cell.insertion.loopGroupId.isEmpty,
           first.insertion.loopGroupId == cell.insertion.loopGroupId,
           first.afterBandIndex == cell.afterBandIndex,
           first.state == cell.state,
           first.insertion.sourceClipPath == cell.insertion.sourceClipPath,
           first.insertion.sourceStartSeconds == cell.insertion.sourceStartSeconds,
           first.insertion.sourceEndSeconds == cell.insertion.sourceEndSeconds,
           first.insertion.playbackRate == cell.insertion.playbackRate,
           first.insertion.muteSourceAudio == cell.insertion.muteSourceAudio,
           // A speed carrier never consolidates with plain loop copies —
           // its cell is the section's one honest handle.
           first.insertion.replacesRazorCutIds == cell.insertion.replacesRazorCutIds {
            runs[runs.count - 1].append(cell)
        } else {
            runs.append([cell])
        }
    }
    return runs
}

// MARK: - Runtime mirror (rail honesty)

/// The seconds the rail must add for arranged copies — the lightweight mirror
/// of the splice's freshness, using only what the shot itself carries: a
/// generated copy counts only while its take is still the playable version's
/// clip for that segment (an inert copy on the rail would be a lie); footage
/// copies count on faith in the file (the splice's `fileExists` is the
/// honest gate at play time). KNOWN APPROXIMATION: THE MATERIAL-WINDOW LAW's
/// gate and clamp need the cut plan's material geometry, which this mirror
/// deliberately does not build — a shot with an in/out trim can overstate
/// here by the copy seconds the window excludes.
func shotPictureInsertionRuntimeSeconds(shot: ProjectShot) -> Double {
    guard !shot.pictureInsertions.isEmpty else { return 0 }
    let activeTakePaths = shotActiveTakePathsBySegmentKey(shot: shot)
    var total = 0.0
    for rawInsertion in shot.pictureInsertions {
        let insertion = rawInsertion.normalized()
        guard insertion.transformKind.isEmpty else { continue }
        if insertion.isFootageSource {
            total += insertion.outputSeconds
            continue
        }
        let activePath = activeTakePaths[insertion.sourceSegmentKey] ?? ""
        if !activePath.isEmpty, activePath == insertion.sourceClipPath {
            total += insertion.outputSeconds
        }
    }
    return total
}
