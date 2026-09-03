import CoreGraphics
import Foundation

/// One gain window on the OUTPUT timeline for the composition's source audio —
/// the picture's own sound. Geometry is always derived, never persisted.
struct ShotSourceGainWindow: Equatable, Sendable {
    var startSeconds: Double
    var endSeconds: Double
    /// 0…1 with the SOURCE lane volume already folded in.
    var gain: Double
    /// Provenance for tests and the UI. The mixer never reads it.
    var segmentKey: String

    var durationSeconds: Double { max(endSeconds - startSeconds, 0) }
}

/// THE SOURCE GAIN LAW — the one place that decides how loud the picture's own
/// audio is at any moment.
///
/// **Empty hand.** No per-segment intent matches any playback item AND there
/// are no source-lane regions ⇒ `[]`. `applyMix` then takes its flat branch and
/// the output is bit-identical to a shot that never heard of this feature.
///
/// **No assembly** (a legacy single-file shot, an unrendered cut) ⇒ reproduce
/// the historical behavior exactly: one window per source-lane region at its
/// persisted seconds, or `[]` when there are none.
///
/// **Otherwise** one window per PLAYBACK ITEM — `playableSpecs` is what the
/// composition actually lays down, so a window per item is a window per
/// inserted audio span. (`outputPictureSegments` merges razor pieces for
/// DISPLAY; the pieces are contiguous and share a key, so both granularities
/// cover the same instants at the same gains.) Each window's gain is the
/// product of four factors, **each a veto at zero**:
///
/// 1. **Lane** — the SOURCE lane's own volume, zero when it is disabled.
/// 2. **Intent** — the operator's per-segment row, matched by `segmentKey`.
///    Absent ⇒ 1.
/// 3. **Envelope** — a combined CUT's per-source-section window, matched by
///    whether it covers this item's MIDPOINT. No source regions at all ⇒ 1.
///    Source regions exist but none covers the midpoint ⇒ **0**, which is what
///    preserves the older law that once any source window exists, every
///    uncovered moment is silent.
/// 4. **Carriage** — `includeAudio`. A bridge and a reversed span with no
///    reversed audio carry none; emitting 0 STATES that rather than leaving the
///    instant unspecified. Carriage never *creates* windows.
///
/// **Why 2 and 3 are looked up differently, and must stay that way:** intent is
/// a statement about a SEGMENT, so it is matched by identity and follows its
/// segment through a reverse or a re-render. An envelope is authored geometry
/// pinned to output seconds, so it is matched by position and stays where it
/// was authored. That asymmetry is what keeps "source gain windows deliberately
/// do not migrate under reverse" literally true.
func shotSourceGainWindows(
    shot: ProjectShot,
    assembly: ShotCutAssembly?
) -> [ShotSourceGainWindow] {
    let sourceLane = shot.audioMix.lane(ShotAudioLaneId.source)
    let laneGain = sourceLane.isEnabled ? min(max(sourceLane.volume, 0), 1) : 0
    let envelopes = shot.audioRegions
        .map { $0.normalized() }
        .filter { $0.laneId == ShotAudioLaneId.source && $0.durationSeconds > 0 }

    guard let assembly, !assembly.playbackItems.isEmpty else {
        // No assembly: the historical region-or-flat behavior, unchanged.
        return envelopes
            .sorted { $0.startSeconds < $1.startSeconds }
            .map { region in
                ShotSourceGainWindow(
                    startSeconds: region.startSeconds,
                    endSeconds: region.endSeconds,
                    gain: region.isMuted ? 0 : laneGain * min(max(region.gain, 0), 1),
                    segmentKey: ""
                )
            }
    }

    let intentByKey = Dictionary(
        shot.sourceSegmentAudio.map { ($0.segmentKey, $0.normalized()) },
        uniquingKeysWith: { _, latest in latest }
    )
    let hasMatchingIntent = assembly.playbackItems.contains {
        !$0.segmentKey.isEmpty && intentByKey[$0.segmentKey] != nil
    }
    guard hasMatchingIntent || !envelopes.isEmpty else { return [] }

    return assembly.playbackItems.map { item in
        // Envelopes are authored geometry against the BASE output; fold a
        // loop pass's midpoint back into base space so every pass hears the
        // same authored gain — without this, rule 3 above would silence
        // passes 2…N the moment any envelope exists. The emitted window
        // itself stays at the pass's real output seconds.
        let midpoint = item.outputStartSeconds + item.durationSeconds / 2
            - Double(item.loopPass) * assembly.baseOutputSeconds
        let intentGain: Double
        if let intent = intentByKey[item.segmentKey] {
            intentGain = intent.isMuted ? 0 : min(max(intent.gain, 0), 1)
        } else {
            intentGain = 1
        }
        let envelopeGain: Double
        if envelopes.isEmpty {
            envelopeGain = 1
        } else if let covering = envelopes.first(where: {
            midpoint >= $0.startSeconds && midpoint < $0.endSeconds
        }) {
            envelopeGain = covering.isMuted ? 0 : min(max(covering.gain, 0), 1)
        } else {
            envelopeGain = 0
        }
        let carriage: Double = item.includeAudio ? 1 : 0
        return ShotSourceGainWindow(
            startSeconds: item.outputStartSeconds,
            endSeconds: item.outputStartSeconds + item.durationSeconds,
            gain: laneGain * intentGain * envelopeGain * carriage,
            segmentKey: item.segmentKey
        )
    }
}

/// Merges abutting windows of equal gain, so the mixer never puts a boundary
/// where nothing changes. This is what lets the ramp emitter assume adjacent
/// windows either differ in gain or have a real gap between them.
func coalescedSourceGainWindows(_ windows: [ShotSourceGainWindow]) -> [ShotSourceGainWindow] {
    let ordered = windows
        .filter { $0.durationSeconds > 0 }
        .sorted { $0.startSeconds < $1.startSeconds }
    var merged: [ShotSourceGainWindow] = []
    for window in ordered {
        if var last = merged.last,
           abs(last.gain - window.gain) < 0.000_001,
           abs(last.endSeconds - window.startSeconds) <= 1.0 / 240.0 {
            last.endSeconds = window.endSeconds
            merged[merged.count - 1] = last
            continue
        }
        merged.append(window)
    }
    return merged
}

/// Half-length of the de-zipper ramp at one end of a window, clamped so it can
/// never reach past this window's midpoint or its neighbour's. Returns 0 when
/// the window is too short to ramp at all — an honest step rather than a ramp
/// that would smear into the next segment.
func sourceGainRampSeconds(
    windowSeconds: Double,
    neighbourSeconds: Double?,
    fadeSeconds: Double
) -> Double {
    guard windowSeconds > 0, fadeSeconds > 0 else { return 0 }
    var limit = min(fadeSeconds, windowSeconds / 2)
    if let neighbourSeconds, neighbourSeconds > 0 {
        limit = min(limit, neighbourSeconds / 2)
    }
    return max(limit, 0)
}

/// The regions a DETACH lifts off one segment, derived from the playback items
/// the composition actually lays down.
///
/// One region PER PIECE, never one spanning region: a razor removes material
/// from a segment, so a single region across the whole span would resurrect
/// exactly the audio the razor took out. Each region's in-point is the piece's
/// own `sourceHeadSeconds` — the SAME derivation `sourceCapture` uses, so a
/// detached region and a captured still agree on where in the file they are.
func shotDetachedSourceRegions(
    pieces: [ShotCutPlaybackItem],
    baseLabel: String,
    regionId: (Int) -> String
) -> [ShotAudioRegion] {
    let playable = pieces.filter { $0.durationSeconds > 0 && !$0.isBridge }
    return playable.enumerated().map { index, item in
        ShotAudioRegion(
            regionId: regionId(index),
            laneId: ShotAudioLaneId.clip,
            label: playable.count > 1 ? "\(baseLabel) · \(index + 1)" : baseLabel,
            path: item.url.path,
            provenance: "detached_source_audio",
            startSeconds: item.outputStartSeconds,
            sourceStartSeconds: item.sourceHeadSeconds,
            durationSeconds: item.durationSeconds
        )
    }
}
