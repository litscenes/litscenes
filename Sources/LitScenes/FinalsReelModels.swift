import Foundation

// THE FINALS REEL — pure laws.
//
// The FINALS shelf's order becomes a playable, exportable film: each picked
// cut bakes once (fingerprint-keyed cache), one stitch composition over the
// bakes in finals order is BOTH the preview player item and the export
// session input, and the music bed rides that same composition as one extra
// audio track. Everything here is pure and test-pinned; AVFoundation stays in
// `FinalsReelComposer`/`VideoChainMedia`.

/// The reel music bed's lane id on `ProjectStageSetDocument.reelAudio`
/// regions (the regions reuse `ShotAudioRegion`'s tolerant type wholesale).
let reelMusicLaneId = "reel_music"

/// Fade halves must leave this many unfaded frames in every clip's middle,
/// or the seam caps — a cut that is all crossfade is not a cut.
let reelMinimumUnfadedFrames = 12

// MARK: - Seams

/// The seam/fade duration vocabulary — the razor-repair dissolve presets.
/// Every authored seam and reel fade snaps here, even by construction, which
/// the centered-fade math requires.
let reelSeamPresetFrames = [6, 12, 24]

/// Head/tail reel-fade preset law: 0 (or less) = off; anything else snaps to
/// the seam presets, so fades and seams speak one duration vocabulary.
func reelFadeSnappedFrames(_ frames: Int) -> Int {
    guard frames > 0 else { return 0 }
    return reelSeamPresetFrames.min(by: {
        abs($0 - frames) < abs($1 - frames)
    }) ?? 0
}

/// What an authored seam DOES with its frames. Tolerant decode: an unknown
/// or absent kind reads as `.crossfade`, so every pre-kind document keeps
/// its exact meaning.
enum ReelSeamKind: String, Codable, Hashable, Sendable {
    /// Centered dissolve — the two cuts overlap.
    case crossfade
    /// Dip through black — outgoing fades to black over the first half,
    /// incoming fades up over the second; the cuts never overlap.
    case dipToBlack = "dip_to_black"
}

/// One authored seam between two FINALS picks, keyed by the ORDERED entryId
/// pair. Presence = an authored transition; absence = hard cut (the
/// default). The pair is adjacency-gated at read time: a reorder that
/// separates the two leaves the seam dormant-but-kept, and re-adjacency
/// resurrects it — seam intent is a statement about the two picked cuts, not
/// about positions. Reaped when either entry leaves the shelf (re-adding
/// mints a fresh entryId, so a removed pick's seams die structurally).
struct ReelSeamStyle: Codable, Hashable, Sendable, Identifiable {
    var leftEntryId: String = ""
    var rightEntryId: String = ""
    var kind: ReelSeamKind = .crossfade
    /// Snapped to `reelSeamPresetFrames` — even by construction, which the
    /// centered-fade math requires. Dips consume frames identically.
    var crossfadeFrames: Int = 12
    var updatedAt: String = ""

    var id: String { "\(leftEntryId)>\(rightEntryId)" }

    private enum CodingKeys: String, CodingKey {
        case leftEntryId, rightEntryId, kind, crossfadeFrames, updatedAt
    }

    init(
        leftEntryId: String = "",
        rightEntryId: String = "",
        kind: ReelSeamKind = .crossfade,
        crossfadeFrames: Int = 12,
        updatedAt: String = ""
    ) {
        self.leftEntryId = leftEntryId
        self.rightEntryId = rightEntryId
        self.kind = kind
        self.crossfadeFrames = crossfadeFrames
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        leftEntryId = try container.decodeIfPresent(String.self, forKey: .leftEntryId) ?? ""
        rightEntryId = try container.decodeIfPresent(String.self, forKey: .rightEntryId) ?? ""
        kind = ((try? container.decodeIfPresent(String.self, forKey: .kind)) ?? nil)
            .flatMap(ReelSeamKind.init(rawValue:)) ?? .crossfade
        crossfadeFrames = try container.decodeIfPresent(Int.self, forKey: .crossfadeFrames) ?? 12
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    func normalized() -> ReelSeamStyle {
        var value = self
        value.leftEntryId = value.leftEntryId.trimmed
        value.rightEntryId = value.rightEntryId.trimmed
        value.crossfadeFrames = reelSeamPresetFrames.min(by: {
            abs($0 - value.crossfadeFrames) < abs($1 - value.crossfadeFrames)
        }) ?? 12
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

/// THE SEAM REAP LAW, shared by both authoring documents (the legacy stage
/// set and the Output sequence): a seam lives exactly as long as BOTH its
/// entries, and duplicates collapse to the first authored.
func reelSeamsReaped(
    _ seams: [ReelSeamStyle],
    entryIds: Set<String>
) -> [ReelSeamStyle] {
    var seen: Set<String> = []
    return seams
        .map { $0.normalized() }
        .filter { seam in
            !seam.leftEntryId.isEmpty
                && !seam.rightEntryId.isEmpty
                && seam.leftEntryId != seam.rightEntryId
                && entryIds.contains(seam.leftEntryId)
                && entryIds.contains(seam.rightEntryId)
                && seen.insert(seam.id).inserted
        }
}

/// THE ADJACENCY LAW: the seams that APPLY under the current finals order —
/// exactly those whose pair is adjacent, in order. Dormant seams are kept in
/// the document but never reach the composition plan.
func reelActiveSeams(
    finals: [StageFinalsEntry],
    seams: [ReelSeamStyle]
) -> [ReelSeamStyle] {
    guard finals.count > 1 else { return [] }
    var active: [ReelSeamStyle] = []
    for index in 0..<(finals.count - 1) {
        if let seam = seams.first(where: {
            $0.leftEntryId == finals[index].entryId
                && $0.rightEntryId == finals[index + 1].entryId
        }) {
            active.append(seam)
        }
    }
    return active
}

// MARK: - Composition plan

/// One baked clip feeding the reel plan. `durationSeconds` is PROBED from
/// the encoded file (the sidecar law) — never an estimate.
struct ReelBakedClip: Hashable, Sendable {
    var entryId: String
    var cutId: String
    var url: URL
    var durationSeconds: Double
}

/// Where one cut lands on the reel's output timeline (nominal seconds).
struct ReelCutBand: Hashable, Sendable {
    var entryId: String
    var cutId: String
    var startSeconds: Double
    var durationSeconds: Double
}

struct ReelCompositionPlan {
    var specs: [VideoChainMedia.StitchClipSpec]
    var cutBands: [ReelCutBand]
    /// Seam id → frames actually applied (0 = hard cut, incl. "capped away").
    var appliedCrossfadeFrames: [String: Int]
    var totalSeconds: Double
    /// Head/tail fades from/to black — duration-NEUTRAL opacity ramps
    /// (unlike seams, they consume nothing), snapped and clamped so the two
    /// can never cross on a short reel.
    var fadeInFrames: Int = 0
    var fadeOutFrames: Int = 0
}

/// THE REEL CROSSFADE LAW + the composition plan.
///
/// `buildStitchComposition`'s transitions are HANDLE-CAPPED: a centered
/// F-frame fade needs F/2 of unused source outside the kept range on each
/// side, and a baked reel clip used whole has zero handles — a bare
/// `transitionFramesBefore` would silently resolve to a hard cut. So the law
/// MANUFACTURES the handles: an F-frame seam shaves F/2 off the outgoing
/// clip's keepRange end and F/2 off the incoming clip's start, then requests
/// `transitionFramesBefore = F`. The stitcher finds exactly the handles it
/// needs, the fade centers on the seam, and — because the stitcher's nominal
/// timeline is the concatenation of KEPT durations — the reel's duration is
/// Σ(bakes) − Σ(F/fps): the locked duration-consuming overlap, honest by
/// construction, with the compositor unmodified.
///
/// Cap law (mirrors the stitcher's own caps so requested == applied and the
/// composer's one-frame assert can't trip): per clip,
/// `applied[left seam] + applied[right seam] ≤ totalFrames − 12` — every cut
/// keeps at least `reelMinimumUnfadedFrames` fully-visible frames. Seams
/// resolve greedily in reel order (the stitcher caps later transitions too);
/// a seam capped below 2 frames becomes a stated hard cut.
func buildReelCompositionPlan(
    clips: [ReelBakedClip],
    seams: [ReelSeamStyle],
    fadeInFrames: Int = 0,
    fadeOutFrames: Int = 0,
    fps: Double = 24
) -> ReelCompositionPlan {
    guard !clips.isEmpty, fps > 0 else {
        return ReelCompositionPlan(specs: [], cutBands: [], appliedCrossfadeFrames: [:], totalSeconds: 0)
    }
    let totalFrames = clips.map { max(Int((($0.durationSeconds) * fps).rounded()), 0) }

    // Resolve applied frames per seam, greedy in order. The kind rides
    // along untouched: a dip consumes exactly what a crossfade would.
    var applied = Array(repeating: 0, count: max(clips.count - 1, 0))
    var boundaryKinds = Array(repeating: ReelSeamKind.crossfade, count: max(clips.count - 1, 0))
    var appliedById: [String: Int] = [:]
    for index in 0..<applied.count {
        let seam = seams.first(where: {
            $0.leftEntryId == clips[index].entryId
                && $0.rightEntryId == clips[index + 1].entryId
        })
        guard let seam else { continue }
        let requested = seam.normalized().crossfadeFrames
        let previousApplied = index > 0 ? applied[index - 1] : 0
        let outgoingBudget = totalFrames[index] - reelMinimumUnfadedFrames - previousApplied
        let incomingBudget = totalFrames[index + 1] - reelMinimumUnfadedFrames
        var frames = min(requested, outgoingBudget, incomingBudget)
        frames -= frames % 2
        applied[index] = max(frames, 0) >= 2 ? max(frames, 0) : 0
        boundaryKinds[index] = seam.kind
        appliedById[seam.id] = applied[index]
    }

    // Shaves derive from the applied frames; kept spans are the nominal
    // timeline.
    var specs: [VideoChainMedia.StitchClipSpec] = []
    var bands: [ReelCutBand] = []
    var cursor: Double = 0
    for (index, clip) in clips.enumerated() {
        let headFrames = index > 0 ? applied[index - 1] / 2 : 0
        let tailFrames = index < applied.count ? applied[index] / 2 : 0
        let keepStart = Double(headFrames) / fps
        let keepEnd = max(clip.durationSeconds - Double(tailFrames) / fps, keepStart)
        specs.append(VideoChainMedia.StitchClipSpec(
            url: clip.url,
            trimFrames: 0,
            keepRanges: [ShotKeepRange(start: keepStart, end: keepEnd)],
            transitionFramesBefore: index > 0 ? applied[index - 1] : 0,
            transitionStyle: index > 0 && boundaryKinds[index - 1] == .dipToBlack
                ? .dipThroughBlack
                : .dissolve,
            includeAudio: true
        ))
        let keptSeconds = max(keepEnd - keepStart, 0)
        bands.append(ReelCutBand(
            entryId: clip.entryId,
            cutId: clip.cutId,
            startSeconds: cursor,
            durationSeconds: keptSeconds
        ))
        cursor += keptSeconds
    }

    // Fades snap to the preset vocabulary and clamp to half the reel each,
    // so a short reel can never fade out before it finished fading in.
    let reelFrames = max(Int((cursor * fps).rounded()), 0)
    let fadeIn = min(reelFadeSnappedFrames(fadeInFrames), reelFrames / 2)
    let fadeOut = min(reelFadeSnappedFrames(fadeOutFrames), reelFrames / 2)

    return ReelCompositionPlan(
        specs: specs,
        cutBands: bands,
        appliedCrossfadeFrames: appliedById,
        totalSeconds: cursor,
        fadeInFrames: fadeIn,
        fadeOutFrames: fadeOut
    )
}

/// The v1 reel profile — one value feeding the fingerprint, the bake, and
/// the composer, so the three can never disagree. Portrait Reframe slots in
/// here later as a parameter, never as another literal.
let reelOutputProfile = VideoOutputProfile.standard(.landscape16x9, fitPolicy: .fitWithBlurFill)

/// One cut's place on the reel bake board — honest named states only (the
/// export API exposes no percentage, so none is invented). `ready` carries
/// the cached file and its PROBED duration; `skipped` names a cut with no
/// playable output rather than silently dropping it.
enum ReelBakeState: Equatable, Sendable {
    case queued
    case baking
    case ready(url: URL, durationSeconds: Double)
    case failed(String)
    case skipped(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

// MARK: - Bake identity

/// Baker version: bump when `flattenShotOutput`'s behavior changes in a way
/// that should invalidate every cached bake.
let reelBakerVersion = 1

/// The audio half of a cut's playable identity — every field that shapes the
/// mix. Consumed by BOTH the player's `playbackFingerprint` and the reel
/// bake fingerprint, so the two can never drift apart.
///
/// Tokens that would otherwise be invisible are deliberate: per-segment
/// source intent shapes the mix without touching a path, range, or region,
/// so without its token a segment mute would be inaudible to any consumer
/// until an unrelated change forced a rebuild.
func shotAudioMixFingerprint(shot: ProjectShot) -> String {
    let laneFingerprint = shot.audioMix.normalized().lanes.map { lane in
        let takes = lane.microphoneTakes.map {
            "\($0.takeId):\($0.path):\($0.startSeconds):\($0.durationSeconds)"
        }.joined(separator: ",")
        return "\(lane.laneId):\(lane.isEnabled):\(lane.volume):\(lane.effectiveStartSeconds):\(lane.activeTakeId):\(takes)"
    }.joined(separator: "|")
    let regionFingerprint = shot.audioRegions.map {
        "\($0.regionId):\($0.laneId):\($0.path):\($0.startSeconds):\($0.sourceStartSeconds):\($0.durationSeconds):\($0.playbackRate):\($0.pitchMode.rawValue):\($0.gain):\($0.isMuted):\($0.loops)"
    }.joined(separator: "|")
    let segmentFingerprint = shot.sourceSegmentAudio.map {
        "\($0.segmentKey):\($0.gain):\($0.isMuted)"
    }.joined(separator: "|")
    return "audio=\(laneFingerprint)#regions=\(regionFingerprint)#segments=\(segmentFingerprint)#narration=\(shot.narrationArtifact?.audioPath ?? "")"
}

/// One referenced audio file's cache-identity token: byte size + mtime,
/// `"missing"` when absent. NOTE a cloud-dataless placeholder stats with its
/// full size and original mtime, so this token CANNOT detect eviction — the
/// bake's readability preflight (`verifyExpectedAudibleFilesReadable`) owns
/// that. The token exists so a file whose CONTENT was swapped in place
/// (re-recorded, re-exported at the same path) re-bakes instead of replaying
/// the cached mix forever.
func shotAudioFileIdentityToken(path: String) -> String {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attributes[.size] as? NSNumber else { return "missing" }
    let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return "\(size.int64Value):\(String(format: "%.3f", modifiedAt))"
}

/// Cache identity for one cut's reel bake: the visible span identity (paths,
/// keep ranges, trims, transitions), the active Look, the ACHIEVED reverse,
/// the whole audio mix, the identity of every expected-audible audio FILE,
/// the output profile, and the baker version.
///
/// LAW: always computed on the duration-RESOLVED assembly (the bake lane
/// resolves once and uses that one snapshot for the staleness check AND the
/// bake), so the identity is deterministic — no separate duration token is
/// added, and a range that moves because the underlying file truly changed
/// invalidates exactly as it should.
///
/// Invalidators: render versions/clip paths, the cut layer, visible reverse,
/// Look, ANY audio change, a referenced audio file's size/mtime, baker
/// version. Non-invalidators: finals order, reel seams, reel music, every
/// other cut. File tokens live HERE and not in `shotAudioMixFingerprint`:
/// that function also feeds the shot player's per-render `playbackFingerprint`
/// and must stay free of disk I/O.
func shotReelBakeFingerprint(
    shot: ProjectShot,
    assembly: ShotCutAssembly,
    profile: VideoOutputProfile,
    fileToken: (String) -> String = shotAudioFileIdentityToken(path:)
) -> String {
    let spanIdentity = assembly.playbackItems.map { item in
        let keep = item.keepRange.map {
            "\(String(format: "%.4f", $0.start))-\(String(format: "%.4f", $0.end))"
        } ?? "all"
        return "\(item.url.path)#\(keep)#trim=\(item.trimFrames)#transition=\(item.transitionFramesBefore)#cut=\(item.cutId)"
    }.joined(separator: "|")
    let legacyPath = shot.activeRenderVersion?.videoPath.trimmed
        ?? shot.renderArtifact?.videoPath.trimmed
        ?? ""
    let audioFileIdentity = shotExpectedAudibleAudioFiles(
        shot: shot,
        outputDurationSeconds: assembly.baseOutputSeconds > 0
            ? assembly.baseOutputSeconds
            : .infinity
    )
    .map { "\($0.path)=\(fileToken($0.path))" }
    .sorted()
    .joined(separator: ",")
    return shortHash(
        "reel_bake.v\(reelBakerVersion)"
            + "|render=\(shot.activeRenderVersionId)"
            + "|look=\(shot.activeLookVersionId)"
            + "|rev=\(assembly.isReversed)"
            + "|spans=\(spanIdentity)"
            + "|legacy=\(legacyPath)"
            + "|mix=\(shotAudioMixFingerprint(shot: shot))"
            + "|audiofiles=\(audioFileIdentity)"
            + "|profile=\(profile.width)x\(profile.height)@\(profile.fps):\(profile.fitPolicy.rawValue)",
        length: 32
    )
}

// MARK: - Undo snapshot

/// Whole reel-state snapshot for symmetric Undo: seams, music, and the
/// head/tail fades together, because a single gesture (and a reap) can touch
/// more than one. One committed gesture = one persisted transaction = one
/// Undo action — the shot-audio idiom, applied to the film.
struct ReelStateSnapshot: Hashable, Sendable {
    var reelAudio: [ShotAudioRegion]
    var reelSeams: [ReelSeamStyle]
    var reelFadeInFrames: Int = 0
    var reelFadeOutFrames: Int = 0
}

// MARK: - Bake sidecar

/// Rides beside each cached bake (`<fingerprint>.json` next to the mp4).
/// `durationSeconds` is probed from the ENCODED file after export — the
/// composition plan consumes probed truth only, never the estimate the bake
/// started from.
struct ReelBakeSidecar: Codable, Hashable, Sendable {
    var fingerprint: String = ""
    var cutId: String = ""
    var durationSeconds: Double = 0
    var bakedAt: String = ""

    private enum CodingKeys: String, CodingKey {
        case fingerprint, cutId, durationSeconds, bakedAt
    }

    init(fingerprint: String = "", cutId: String = "", durationSeconds: Double = 0, bakedAt: String = "") {
        self.fingerprint = fingerprint
        self.cutId = cutId
        self.durationSeconds = durationSeconds
        self.bakedAt = bakedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fingerprint = try container.decodeIfPresent(String.self, forKey: .fingerprint) ?? ""
        cutId = try container.decodeIfPresent(String.self, forKey: .cutId) ?? ""
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        bakedAt = try container.decodeIfPresent(String.self, forKey: .bakedAt) ?? ""
    }
}
