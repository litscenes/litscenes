import Foundation

/// Stable lane ids. `kind` remains a String on persisted lanes so the next
/// imported-media lane can arrive without making old builds fail to decode.
enum ShotAudioLaneId {
    static let source = "source"
    static let narration = "narration"
    static let microphone = "microphone"
    static let ambient = "ambient"
    /// An audio file the user imported and attached to this shot — the
    /// "imported-media lane" the note above anticipated. Distinct from
    /// `ambient`, which carries a locally SYNTHESIZED bed and can only ever
    /// hold one machine-made loop.
    static let clip = "clip"

    /// THE ROW LAW: `laneId` IDENTIFIES a row, `kind` DECIDES its behavior,
    /// `label` is what the operator reads. A shot may hold several rows of the
    /// same kind — `clip`, `clip_2`, `clip_3` — and every per-type branch must
    /// key on `kind`, never on `laneId`, or the second row of a kind silently
    /// behaves like an unknown lane.
    ///
    /// Extra rows persist their own `kind`, so this parse is only the fallback
    /// for a lane id referenced by a region whose lane row went missing.
    static func kind(ofLaneId laneId: String) -> String {
        let cleaned = laneId.trimmed.lowercased()
        guard let separator = cleaned.lastIndex(of: "_") else { return cleaned }
        let base = String(cleaned[cleaned.startIndex..<separator])
        let suffix = cleaned[cleaned.index(after: separator)...]
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber), extendable.contains(base) else {
            return cleaned
        }
        return base
    }

    /// The kinds that may hold more than one row. SOURCE is picture-locked —
    /// it IS the composition's own tracks. NARRATION is governed by the
    /// artifact-sync law in `settingNarrationArtifact`, which targets the one
    /// base narration lane.
    static let extendable: Set<String> = [clip, ambient, microphone]

    /// The next free row id for a kind, given the ids already in use.
    /// The first row of a kind is the bare kind itself, so existing shots keep
    /// the ids they already have.
    static func nextLaneId(kind: String, existing: Set<String>) -> String {
        guard !existing.contains(kind) else {
            var ordinal = 2
            while existing.contains("\(kind)_\(ordinal)") { ordinal += 1 }
            return "\(kind)_\(ordinal)"
        }
        return kind
    }

    /// Display ordinal of a row within its kind: 1 for the base row.
    static func ordinal(ofLaneId laneId: String) -> Int {
        let cleaned = laneId.trimmed.lowercased()
        guard let separator = cleaned.lastIndex(of: "_"),
              let ordinal = Int(cleaned[cleaned.index(after: separator)...]),
              extendable.contains(String(cleaned[cleaned.startIndex..<separator])) else {
            return 1
        }
        return ordinal
    }
}

/// A picker/drop asset carries its real source kind into the engine. Ambient
/// accepts both variants, while every other imported-media lane accepts only
/// project audio. Keeping the discriminator out of a bare id prevents a bed
/// and a media item from being resolved through the wrong library.
enum ShotAudioAssetReference: Hashable, Sendable {
    case projectAudio(mediaId: String)
    case ambientBed(bedId: String)

    var assetId: String {
        switch self {
        case .projectAudio(let mediaId): return mediaId
        case .ambientBed(let bedId): return bedId
        }
    }

    var stableId: String {
        switch self {
        case .projectAudio(let mediaId): return "project:\(mediaId)"
        case .ambientBed(let bedId): return "bed:\(bedId)"
        }
    }
}

enum ShotAudioTiming {
    static let framesPerSecond = 24.0
    static let playheadSnapPixels = 8.0

    static var frameSeconds: Double { 1 / framesPerSecond }

    static func frameQuantizedStart(_ seconds: Double) -> Double {
        let finiteSeconds = seconds.isFinite ? max(seconds, 0) : 0
        return (finiteSeconds * framesPerSecond).rounded() / framesPerSecond
    }

    static func normalizedStart(_ seconds: Double, timelineDuration: Double) -> Double {
        let duration = max(timelineDuration, 0)
        let latestFrameIndex = max(Int(ceil(duration * framesPerSecond)) - 1, 0)
        let latestFrameStart = Double(latestFrameIndex) / framesPerSecond
        return min(frameQuantizedStart(seconds), latestFrameStart)
    }

    static func movedStart(
        initialStart: Double,
        translationPixels: Double,
        timelineWidth: Double,
        timelineDuration: Double,
        playheadSeconds: Double,
        bypassesPlayheadSnap: Bool
    ) -> (startSeconds: Double, snappedToPlayhead: Bool) {
        guard timelineWidth > 0, timelineDuration > 0 else {
            return (normalizedStart(initialStart, timelineDuration: timelineDuration), false)
        }
        let translated = initialStart + (translationPixels / timelineWidth * timelineDuration)
        let candidate = normalizedStart(translated, timelineDuration: timelineDuration)
        let playhead = normalizedStart(playheadSeconds, timelineDuration: timelineDuration)
        let distancePixels = abs(candidate - playhead) / timelineDuration * timelineWidth
        guard !bypassesPlayheadSnap, distancePixels <= playheadSnapPixels else {
            return (candidate, false)
        }
        return (playhead, true)
    }

    static func nudgedStart(
        _ seconds: Double,
        frames: Int,
        timelineDuration: Double
    ) -> Double {
        normalizedStart(
            seconds + (Double(frames) / framesPerSecond),
            timelineDuration: timelineDuration
        )
    }

    static func timecode(_ seconds: Double) -> String {
        let frames = max(Int((seconds * framesPerSecond).rounded()), 0)
        let wholeSeconds = frames / Int(framesPerSecond)
        return String(
            format: "%02d:%02d:%02d",
            wholeSeconds / 60,
            wholeSeconds % 60,
            frames % Int(framesPerSecond)
        )
    }

    /// Generalized snap: the nearest target within the pixel radius wins.
    /// Targets are the playhead, 0, the timeline end, and neighboring region
    /// edges on the same lane. Option (bypass) keeps the existing convention.
    static func snappedSeconds(
        candidate: Double,
        targets: [Double],
        timelineWidth: Double,
        timelineDuration: Double,
        bypass: Bool
    ) -> (seconds: Double, snapped: Bool) {
        guard !bypass, timelineWidth > 0, timelineDuration > 0 else {
            return (candidate, false)
        }
        var best: (target: Double, pixels: Double)?
        for target in targets where target.isFinite {
            let pixels = abs(candidate - target) / timelineDuration * timelineWidth
            if pixels <= playheadSnapPixels, pixels < (best?.pixels ?? .infinity) {
                best = (target, pixels)
            }
        }
        guard let best else { return (candidate, false) }
        return (best.target, true)
    }

    /// Move-snap for a whole region: its head AND its tail are both magnets
    /// (`targets` are edge positions — a neighbour's start or end, 0, the
    /// timeline end, the playhead), the nearest alignment within the radius
    /// wins, and the result passes through the same clamp the engine's
    /// `movedTo` law applies. The draft an operator drops is therefore
    /// exactly what persists — the old start-only snap could rest the start
    /// on the timeline-end target, which the commit then clamped back a
    /// frame, visibly jumping after release. `snapped` is true only when the
    /// clamp kept the winning alignment.
    static func snappedMoveStart(
        candidateStart: Double,
        regionDurationSeconds: Double,
        targets: [Double],
        timelineWidth: Double,
        timelineDuration: Double,
        bypass: Bool
    ) -> (seconds: Double, snapped: Bool) {
        func clamped(_ start: Double) -> Double {
            let floored = max(start.isFinite ? start : 0, 0)
            guard timelineDuration > 0 else { return floored }
            return min(floored, max(timelineDuration - frameSeconds, 0))
        }
        guard !bypass, timelineWidth > 0, timelineDuration > 0 else {
            return (clamped(candidateStart), false)
        }
        var best: (start: Double, pixels: Double)?
        for target in targets where target.isFinite {
            for alignedStart in [target, target - regionDurationSeconds] {
                let pixels = abs(candidateStart - alignedStart) / timelineDuration * timelineWidth
                if pixels <= playheadSnapPixels, pixels < (best?.pixels ?? .infinity) {
                    best = (alignedStart, pixels)
                }
            }
        }
        guard let best else { return (clamped(candidateStart), false) }
        let resolved = clamped(best.start)
        return (resolved, abs(resolved - best.start) <= 0.000_1)
    }

    /// Accepts `mm:ss:ff`, `mm:ss`, or plain seconds ("7.5"). nil when the
    /// text isn't a time; negatives are the caller's clamp.
    static func parseTimecode(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        let parts = cleaned.split(separator: ":").map(String.init)
        switch parts.count {
        case 1:
            return Double(parts[0])
        case 2:
            guard let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        case 3:
            guard let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]),
                  let frames = Double(parts[2]) else { return nil }
            return minutes * 60 + seconds + frames / framesPerSecond
        default:
            return nil
        }
    }
}

struct ShotMicrophoneTake: Codable, Hashable, Identifiable, Sendable {
    var takeId: String = ""
    var path: String = ""
    /// Position on the post-cut/output timeline, not source-material time.
    var startSeconds: Double = 0
    /// The playhead where this take was captured; nil on older documents.
    var recordedStartSeconds: Double?
    var durationSeconds: Double = 0
    var inputDeviceId: String = ""
    var inputDeviceName: String = ""
    var createdAt: String = ""

    var id: String { takeId }

    var effectiveRecordedStartSeconds: Double {
        recordedStartSeconds ?? startSeconds
    }

    func normalized() -> ShotMicrophoneTake {
        var value = self
        value.takeId = value.takeId.trimmed
        value.path = value.path.trimmed
        value.startSeconds = max(value.startSeconds, 0)
        if let recordedStartSeconds = value.recordedStartSeconds {
            value.recordedStartSeconds = max(recordedStartSeconds, 0)
        }
        value.durationSeconds = max(value.durationSeconds, 0)
        value.inputDeviceId = value.inputDeviceId.trimmed
        value.inputDeviceName = value.inputDeviceName.trimmed
        value.createdAt = value.createdAt.trimmed
        return value
    }
}

struct ShotAudioLane: Codable, Hashable, Identifiable, Sendable {
    var laneId: String = ""
    var kind: String = ""
    var label: String = ""
    var isEnabled: Bool = true
    var volume: Double = 1
    /// Narration/imported-media output offset. Source ignores this value.
    var startSeconds: Double?
    var activeTakeId: String = ""
    var microphoneTakes: [ShotMicrophoneTake] = []
    /// Ambient lane only; nil on other lanes and on older documents.
    /// HARD RULE: every new stored property on this type must be Optional —
    /// synthesized decode throws on a missing non-optional key, and a lane
    /// decode failure silently resets the user's ENTIRE mix (ProjectShot
    /// decodes audioMix behind `try?` ?? empty).
    var ambientBedId: String?
    /// Absolute baked-bed path (mic-take precedent) so applyMix resolves
    /// playback from shot state alone; recomputed at every attach.
    var ambientBedPath: String?
    /// Clip lane only — the imported audio media item attached to this shot.
    /// Optional for the same hard reason as the ambient fields above.
    var clipMediaId: String?
    /// Absolute path to the imported file, recomputed at every attach so
    /// `applyMix` resolves playback from shot state alone (mic-take precedent).
    var clipPath: String?

    var id: String { laneId }

    var effectiveStartSeconds: Double { max(startSeconds ?? 0, 0) }

    var hasAmbientBed: Bool { !(ambientBedId ?? "").isEmpty }

    var hasAudioClip: Bool { !(clipMediaId ?? "").isEmpty }

    var activeMicrophoneTake: ShotMicrophoneTake? {
        microphoneTakes.first { $0.takeId == activeTakeId }
            ?? microphoneTakes.last
    }

    func normalized() -> ShotAudioLane {
        var value = self
        value.laneId = value.laneId.trimmed.lowercased()
        value.kind = value.kind.trimmed.lowercased()
        value.label = value.label.trimmed
        value.volume = min(max(value.volume, 0), 1)
        if let startSeconds = value.startSeconds {
            value.startSeconds = startSeconds.isFinite ? max(startSeconds, 0) : nil
        }
        if let ambientBedId = value.ambientBedId {
            let cleaned = ambientBedId.trimmed
            value.ambientBedId = cleaned.isEmpty ? nil : cleaned
        }
        if value.ambientBedId == nil {
            value.ambientBedPath = nil
        } else if let ambientBedPath = value.ambientBedPath {
            let cleaned = ambientBedPath.trimmed
            value.ambientBedPath = cleaned.isEmpty ? nil : cleaned
        }
        if let clipMediaId = value.clipMediaId {
            let cleaned = clipMediaId.trimmed
            value.clipMediaId = cleaned.isEmpty ? nil : cleaned
        }
        if value.clipMediaId == nil {
            value.clipPath = nil
        } else if let clipPath = value.clipPath {
            let cleaned = clipPath.trimmed
            value.clipPath = cleaned.isEmpty ? nil : cleaned
        }
        var seen: Set<String> = []
        value.microphoneTakes = value.microphoneTakes
            .map { $0.normalized() }
            .filter { take in
                !take.takeId.isEmpty && !take.path.isEmpty && seen.insert(take.takeId).inserted
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.takeId < rhs.takeId }
                return lhs.createdAt < rhs.createdAt
            }
        if !value.microphoneTakes.contains(where: { $0.takeId == value.activeTakeId }) {
            value.activeTakeId = value.microphoneTakes.last?.takeId ?? ""
        }
        return value
    }

    /// The default row for an id, used whenever `lanes` has no entry for it.
    /// An extra row (`clip_2`) resolves to its KIND's behavior and a numbered
    /// label, so a region whose lane row went missing still mixes and reads
    /// correctly rather than degrading to an unknown lane.
    static func canonical(_ laneId: String) -> ShotAudioLane {
        let kind = ShotAudioLaneId.kind(ofLaneId: laneId)
        let base: String
        switch kind {
        case ShotAudioLaneId.source:
            base = "Source"
        case ShotAudioLaneId.narration:
            base = "Narration"
        case ShotAudioLaneId.microphone:
            base = "Mic"
        case ShotAudioLaneId.ambient:
            base = "Ambient"
        case ShotAudioLaneId.clip:
            base = "Clip"
        default:
            base = laneId
        }
        let ordinal = ShotAudioLaneId.ordinal(ofLaneId: laneId)
        return ShotAudioLane(
            laneId: laneId,
            kind: kind,
            label: ordinal > 1 ? "\(base) \(ordinal)" : base
        )
    }
}

/// Non-destructive shot-level mix state. Empty legacy state resolves to the
/// canonical enabled/full-volume defaults, preserving prior playback.
struct ShotAudioMix: Codable, Hashable, Sendable {
    var lanes: [ShotAudioLane] = []

    func lane(_ laneId: String) -> ShotAudioLane {
        lanes.first { $0.laneId == laneId } ?? .canonical(laneId)
    }

    var activeMicrophoneTake: ShotMicrophoneTake? {
        lane(ShotAudioLaneId.microphone).activeMicrophoneTake
    }

    func settingLaneEnabled(_ laneId: String, enabled: Bool) -> ShotAudioMix {
        updatingLane(laneId) { $0.isEnabled = enabled }
    }

    func settingLaneVolume(_ laneId: String, volume: Double) -> ShotAudioMix {
        updatingLane(laneId) { $0.volume = min(max(volume, 0), 1) }
    }

    /// A placement is an instruction to USE the audio, so a stale mute/zero
    /// lane cannot silently swallow it. Existing nonzero levels survive.
    func preparingLaneForNewAudio(_ laneId: String) -> ShotAudioMix {
        updatingLane(laneId) { lane in
            lane.isEnabled = true
            if lane.volume <= 0.000_1 {
                lane.volume = Self.defaultPlacementVolume(
                    forKind: ShotAudioLaneId.kind(ofLaneId: laneId)
                )
            }
        }
    }

    /// Regionization transfers the old singleton lane's mute/level into the
    /// new region. The converted lane must then become neutral or playback
    /// applies the same operator intent twice.
    func neutralizingLanes(_ laneIds: Set<String>) -> ShotAudioMix {
        var value = self
        for laneId in laneIds {
            value = value.updatingLane(laneId) { lane in
                lane.isEnabled = true
                lane.volume = 1
            }
        }
        return value
    }

    private static func defaultPlacementVolume(forKind kind: String) -> Double {
        switch kind {
        case ShotAudioLaneId.ambient:
            return AmbientTunerMetrics.defaultAttachVolume
        case ShotAudioLaneId.clip:
            return 0.6
        default:
            return 1
        }
    }

    /// Attaches (or, with nil, detaches) a baked bed on the ambient lane.
    /// Attaching enables the lane; the default volume applies only to the
    /// lane's FIRST bed, so later swaps keep the user's level. Detaching
    /// disables the lane and clears both pointers.
    func settingAmbientBed(
        bedId: String?,
        path: String?,
        defaultVolume: Double = AmbientTunerMetrics.defaultAttachVolume
    ) -> ShotAudioMix {
        updatingLane(ShotAudioLaneId.ambient) { lane in
            let cleanedId = (bedId ?? "").trimmed
            guard !cleanedId.isEmpty else {
                lane.ambientBedId = nil
                lane.ambientBedPath = nil
                lane.isEnabled = false
                return
            }
            if !lane.hasAmbientBed {
                lane.volume = min(max(defaultVolume, 0), 1)
            }
            lane.ambientBedId = cleanedId
            lane.ambientBedPath = (path ?? "").trimmed
            lane.isEnabled = true
        }
    }

    /// Attaches (or, with nil, detaches) an imported audio file on the clip
    /// lane. Semantics deliberately mirror `settingAmbientBed`: attaching
    /// enables the lane, the default volume applies only to the lane's FIRST
    /// clip so later swaps keep the user's level, and detaching disables the
    /// lane and clears both pointers.
    func settingAudioClip(
        mediaId: String?,
        path: String?,
        defaultVolume: Double = 0.6
    ) -> ShotAudioMix {
        updatingLane(ShotAudioLaneId.clip) { lane in
            let cleanedId = (mediaId ?? "").trimmed
            guard !cleanedId.isEmpty else {
                lane.clipMediaId = nil
                lane.clipPath = nil
                lane.isEnabled = false
                return
            }
            if !lane.hasAudioClip {
                lane.volume = min(max(defaultVolume, 0), 1)
            }
            lane.clipMediaId = cleanedId
            lane.clipPath = (path ?? "").trimmed
            lane.isEnabled = true
        }
    }

    func settingNarrationStartSeconds(_ startSeconds: Double) -> ShotAudioMix {
        updatingLane(ShotAudioLaneId.narration) { lane in
            lane.startSeconds = max(startSeconds, 0)
        }
    }

    func settingMicrophoneTakeStartSeconds(_ takeId: String, startSeconds: Double) -> ShotAudioMix {
        updatingLane(ShotAudioLaneId.microphone) { lane in
            guard let index = lane.microphoneTakes.firstIndex(where: { $0.takeId == takeId }) else { return }
            if lane.microphoneTakes[index].recordedStartSeconds == nil {
                lane.microphoneTakes[index].recordedStartSeconds = lane.microphoneTakes[index].startSeconds
            }
            lane.microphoneTakes[index].startSeconds = max(startSeconds, 0)
        }
    }

    func appendingMicrophoneTake(_ take: ShotMicrophoneTake) -> ShotAudioMix {
        let normalizedTake = take.normalized()
        guard !normalizedTake.takeId.isEmpty, !normalizedTake.path.isEmpty else { return self }
        return updatingLane(ShotAudioLaneId.microphone) { lane in
            lane.microphoneTakes.removeAll { $0.takeId == normalizedTake.takeId }
            lane.microphoneTakes.append(normalizedTake)
            lane.activeTakeId = normalizedTake.takeId
            lane.isEnabled = true
        }
    }

    func activatingMicrophoneTake(_ takeId: String) -> ShotAudioMix {
        updatingLane(ShotAudioLaneId.microphone) { lane in
            guard lane.microphoneTakes.contains(where: { $0.takeId == takeId }) else { return }
            lane.activeTakeId = takeId
            lane.isEnabled = true
        }
    }

    func removingMicrophoneTake(_ takeId: String) -> ShotAudioMix {
        updatingLane(ShotAudioLaneId.microphone) { lane in
            lane.microphoneTakes.removeAll { $0.takeId == takeId }
            if lane.activeTakeId == takeId {
                lane.activeTakeId = lane.microphoneTakes.last?.takeId ?? ""
            }
        }
    }

    /// Ripple output-time overlays after an explicit insertion edit. Recorded
    /// microphone origins remain historical facts; only the editable starts
    /// move. All takes move so switching takes cannot resurrect old timing.
    func ripplingPlacements(atOrAfter thresholdSeconds: Double, by deltaSeconds: Double) -> ShotAudioMix {
        guard abs(deltaSeconds) >= ShotAudioTiming.frameSeconds / 2 else { return self }
        let threshold = max(thresholdSeconds, 0)
        return updatingLane(ShotAudioLaneId.narration) { lane in
            if lane.effectiveStartSeconds + 0.000_1 >= threshold {
                lane.startSeconds = max(lane.effectiveStartSeconds + deltaSeconds, 0)
            }
        }.updatingLane(ShotAudioLaneId.microphone) { lane in
            for index in lane.microphoneTakes.indices
                where lane.microphoneTakes[index].startSeconds + 0.000_1 >= threshold {
                lane.microphoneTakes[index].startSeconds = max(
                    lane.microphoneTakes[index].startSeconds + deltaSeconds,
                    0
                )
            }
        }
    }

    func normalized() -> ShotAudioMix {
        var value = self
        var seen: Set<String> = []
        value.lanes = value.lanes
            .map { $0.normalized() }
            .filter { !$0.laneId.isEmpty && seen.insert($0.laneId).inserted }
        return value
    }

    /// Adds an empty extra row of a kind, returning the new lane id (nil when
    /// the kind cannot be extended). Persisting the lane IS creating the row —
    /// `lanes` is the roster; there is no second list to keep in sync.
    ///
    /// Always a NUMBERED sibling, never the bare kind: `shotAudioLaneRows`
    /// draws the base row of every canonical kind whether or not anything has
    /// persisted it, so returning `clip` here would add nothing the operator
    /// can see.
    func addingLane(kind: String) -> (mix: ShotAudioMix, laneId: String)? {
        let cleanedKind = kind.trimmed.lowercased()
        guard ShotAudioLaneId.extendable.contains(cleanedKind) else { return nil }
        let existing = Set(normalized().lanes.map(\.laneId)).union([cleanedKind])
        let laneId = ShotAudioLaneId.nextLaneId(kind: cleanedKind, existing: existing)
        // Touching the lane through `updatingLane` is what persists it, and
        // `.canonical` already resolves the right kind and numbered label.
        return (updatingLane(laneId) { _ in }, laneId)
    }

    /// Drops an extra row. Refuses the base row of any kind: those are the
    /// canonical five and removing one would change what the shot HAS, not
    /// just how it is organized.
    func removingLane(_ laneId: String) -> ShotAudioMix? {
        let cleaned = laneId.trimmed.lowercased()
        guard ShotAudioLaneId.ordinal(ofLaneId: cleaned) > 1 else { return nil }
        var value = normalized()
        guard value.lanes.contains(where: { $0.laneId == cleaned }) else { return nil }
        value.lanes.removeAll { $0.laneId == cleaned }
        return value
    }

    private func updatingLane(
        _ laneId: String,
        mutate: (inout ShotAudioLane) -> Void
    ) -> ShotAudioMix {
        var value = normalized()
        let index: Int
        if let existing = value.lanes.firstIndex(where: { $0.laneId == laneId }) {
            index = existing
        } else {
            value.lanes.append(.canonical(laneId))
            index = value.lanes.count - 1
        }
        mutate(&value.lanes[index])
        value.lanes[index] = value.lanes[index].normalized()
        return value
    }
}

/// Whole audio state used only for compound editor actions. Placement and
/// Make Audible can touch a lane and a region together; snapshotting both
/// keeps each action one document transaction and one symmetric Undo step.
struct ShotAudioStateSnapshot: Hashable, Sendable {
    var audioMix: ShotAudioMix
    var audioRegions: [ShotAudioRegion]
}

struct ShotAudioStateEdit: Hashable, Sendable {
    var before: ShotAudioStateSnapshot
    var after: ShotAudioStateSnapshot
    var affectedRegionId: String

    var affectedRegion: ShotAudioRegion? {
        after.audioRegions.first { $0.regionId == affectedRegionId }
    }
}

/// The rows a shot's lane stack renders, in order: the five canonical kinds,
/// with each extra row inserted directly after the other rows of its kind.
///
/// Derived from `audioMix.lanes` and the regions themselves — there is no
/// separate roster to fall out of sync. The region sweep is deliberate: a lane
/// row can go missing (an older document, a hand-edited file), and a region
/// pointing at a row that is not drawn would be audible with no way to reach
/// it. SOURCE and NARRATION never extend, so they contribute exactly one row.
func shotAudioLaneRows(mix: ShotAudioMix, regions: [ShotAudioRegion]) -> [String] {
    let canonicalOrder = [
        ShotAudioLaneId.source,
        ShotAudioLaneId.narration,
        ShotAudioLaneId.microphone,
        ShotAudioLaneId.ambient,
        ShotAudioLaneId.clip
    ]
    var byKind: [String: [String]] = [:]
    var seen: Set<String> = []
    func note(_ laneId: String) {
        let cleaned = laneId.trimmed.lowercased()
        guard !cleaned.isEmpty, !seen.contains(cleaned) else { return }
        seen.insert(cleaned)
        byKind[ShotAudioLaneId.kind(ofLaneId: cleaned), default: []].append(cleaned)
    }
    for lane in mix.normalized().lanes { note(lane.laneId) }
    for region in regions { note(region.laneId) }

    var rows: [String] = []
    for kind in canonicalOrder {
        // The base row is always drawn, even when nothing has persisted it.
        rows.append(kind)
        guard ShotAudioLaneId.extendable.contains(kind) else { continue }
        let extras = (byKind[kind] ?? [])
            .filter { $0 != kind }
            .sorted { ShotAudioLaneId.ordinal(ofLaneId: $0) < ShotAudioLaneId.ordinal(ofLaneId: $1) }
        rows.append(contentsOf: extras)
    }
    // Anything of an unrecognized kind still gets a row rather than vanishing.
    for (kind, ids) in byKind.sorted(by: { $0.key < $1.key })
    where !canonicalOrder.contains(kind) {
        rows.append(contentsOf: ids.sorted())
    }
    return rows
}

/// Where a pasted region lands, in three rungs: the operator's focused lane
/// when it is kind-compatible → the payload's own row when this shot draws
/// it → the base row of the payload's kind, which `shotAudioLaneRows` always
/// draws, so paste never needs to create a lane. SOURCE payloads answer nil:
/// envelope regions are picture-locked and never travel (detach is the
/// honest way to get movable source audio).
func shotAudioPasteLaneId(
    payloadLaneId: String,
    preferredLaneId: String?,
    rows: [String]
) -> String? {
    let payloadLane = payloadLaneId.trimmed.lowercased()
    let kind = ShotAudioLaneId.kind(ofLaneId: payloadLane)
    guard kind != ShotAudioLaneId.source, !kind.isEmpty else { return nil }
    if let preferred = preferredLaneId?.trimmed.lowercased(),
       !preferred.isEmpty,
       ShotAudioLaneId.kind(ofLaneId: preferred) == kind,
       rows.contains(preferred) {
        return preferred
    }
    if rows.contains(payloadLane) { return payloadLane }
    return kind
}
