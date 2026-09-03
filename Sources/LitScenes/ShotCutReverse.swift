import Foundation

// MARK: - The reverse law
//
// A CUT plays backwards by playing its spans in the opposite order, each one
// reading from a baked reversed copy of its source file. Nothing here decodes
// or writes media: this is a total function of the forward assembly plus
// whatever proxies happen to be ready, which is what makes it testable without
// a single fixture file.
//
// Five invariants hold on the way out, and every "no change needed" claim
// downstream rests on them:
//
//   I1  Material space is direction-free. `bands`, `planClips`, and
//       `materialSeconds` come through untouched — the strip still shows
//       everything you have, in the order you authored it. This is what keeps
//       razor authoring and the trim handles from ever learning about reverse.
//   I2  Material spans stay ordered intervals (start <= end) even when
//       reversed. Direction rides `playsReversed`, never inverted bounds.
//   I3  `playsReversed` defaults false, so forward assemblies are bit-identical
//       to what they were before reverse existed.
//   I4  `keepRange` comes out in the PROXY file's coordinates and `url` points
//       at the proxy. The stitcher then plays each span forward through a file
//       that is already backwards, so the composition builder, the export, the
//       one-frame agreement assert, and `sourceCapture` need no direction
//       branch at all.
//   I5  `outputSeconds` is preserved. Every audio overlay clamps against
//       `composition.duration`, so this is precisely what lets narration, mic
//       takes, and ambient beds stay where the operator placed them.

/// Mirrors one kept span into its proxy's coordinates.
///
/// The source content occupying `[s, e)` was written to the proxy at
/// `[D - e, D - s)`, so the mirror is a straight reflection about `D`.
///
/// `D` is the source's VISUAL-track duration, never the container duration —
/// embedded audio commonly runs past picture, and reflecting about the longer
/// number slides every span by the overhang.
func mirroredKeepRange(_ keep: ShotKeepRange, sourceDurationSeconds: Double) -> ShotKeepRange {
    // The plan can hand us a span that overshoots the real file: `shotCutPlan`
    // fills `keep.end` from an integral per-segment estimate when exact media
    // durations have not loaded yet. Reflecting about the estimate rather than
    // the file keeps `start >= 0` AND preserves the span's length exactly;
    // clamping a negative start to zero instead would silently SHORTEN the
    // span and trip the player's one-frame agreement assert. The overshooting
    // tail then clamps inside the composition builder exactly as it does
    // when the cut plays forward.
    let mirror = max(sourceDurationSeconds, keep.end)
    return ShotKeepRange(
        start: max(mirror - keep.end, 0),
        end: max(mirror - keep.start, 0)
    )
}

/// Reverses the ordered playback spans of a cut.
///
/// - Parameter proxies: ready reversed proxies keyed by SOURCE path. A span
///   whose proxy is missing keeps its own file and plays FORWARD in its new
///   slot, silently — forward dialogue under reversed picture reads as a bug,
///   whereas silence reads as pending. In practice the seam only reverses once
///   every span has a proxy; this branch keeps the function total.
func reversedShotCutPlaybackItems(
    _ items: [ShotCutPlaybackItem],
    proxies: [String: ShotReverseProxyArtifact],
    framesPerSecond: Double = ShotAudioTiming.framesPerSecond
) -> [ShotCutPlaybackItem] {
    guard !items.isEmpty else { return items }

    var out = Array(items.reversed())

    // A dissolve belongs to the JOIN, and `transitionFramesBefore` names it by
    // the span on its right. Reversing swaps which span that is, so the values
    // shift one slot rather than riding along with their old owners.
    // `items[0]`'s value is 0 by construction (the forward derivation only sets
    // it for a keep index above zero) and is correctly dropped.
    let forwardTransitions = items.map(\.transitionFramesBefore)
    let count = out.count
    for index in out.indices {
        out[index].transitionFramesBefore = index == 0 ? 0 : forwardTransitions[count - index]
    }

    for index in out.indices {
        let source = items[count - 1 - index]
        guard let proxy = proxies[source.url.path], proxy.isReady else {
            out[index].url = source.url
            out[index].keepRange = source.keepRange
            out[index].includeAudio = false
            out[index].playsReversed = false
            continue
        }

        out[index].url = URL(fileURLWithPath: proxy.proxyPath)
        out[index].playsReversed = true
        // A bridge is silent in both directions; a source span keeps its audio
        // only if the proxy actually carries a reversed copy of it.
        out[index].includeAudio = source.includeAudio && proxy.hasReversedAudio

        if let keep = source.keepRange {
            out[index].keepRange = mirroredKeepRange(
                keep,
                sourceDurationSeconds: proxy.sourceDurationSeconds
            )
        } else if source.trimFrames > 0 {
            // Defensive only: the live derivation sets `keepRange` on every
            // source span, so this is unreachable from `shotCutAssembly`. It
            // exists because a leading trim mirrors into a TRAILING one, which
            // `StitchClipSpec` cannot express — so it must become a range.
            let head = Double(source.trimFrames) / framesPerSecond
            out[index].keepRange = mirroredKeepRange(
                ShotKeepRange(start: head, end: max(proxy.sourceDurationSeconds, head)),
                sourceDurationSeconds: proxy.sourceDurationSeconds
            )
            out[index].trimFrames = 0
        } else if proxy.proxyDurationSeconds > 0 {
            // A whole-file span (a generated bridge). Its output length must
            // agree with the file the compositor will actually open, or the
            // assembly and the composition disagree.
            out[index].durationSeconds = proxy.proxyDurationSeconds
        }
    }

    out = cappedTransitions(out, framesPerSecond: framesPerSecond)

    // Recompute rather than mirror. The same durations summed in the opposite
    // order can differ in the last bits, and every consumer must be comparing
    // against the total that was actually laid down.
    var cursor = 0.0
    for index in out.indices {
        out[index].outputStartSeconds = cursor
        cursor += out[index].durationSeconds
    }
    return out
}

/// Re-applies the forward derivation's dissolve capacity caps in the new order.
///
/// The forward chain walks joins left to right, spending each span's frames as
/// it goes, so a value that fit going one way can exceed what is available
/// going the other. Playback would survive — the composition builder re-caps
/// against the real source handles — but `shotLookVisualFingerprint` records
/// this number, and a fingerprint that claims a dissolve which never renders
/// would stale a paid Look for no reason.
private func cappedTransitions(
    _ items: [ShotCutPlaybackItem],
    framesPerSecond: Double
) -> [ShotCutPlaybackItem] {
    var out = items
    let epsilon = 0.000_1
    var framesIntoPrevious = 0
    for index in out.indices {
        guard index > 0 else {
            out[index].transitionFramesBefore = 0
            continue
        }
        let previousSeconds = out[index - 1].durationSeconds
        let currentSeconds = out[index].durationSeconds
        let outgoingCapacity = Int(floor(previousSeconds * framesPerSecond + epsilon))
        let remaining = max(outgoingCapacity - framesIntoPrevious / 2, 0)
        var frames = min(
            out[index].transitionFramesBefore,
            Int(floor(previousSeconds * framesPerSecond * 2 + epsilon)),
            Int(floor(currentSeconds * framesPerSecond * 2 + epsilon)),
            remaining * 2
        )
        frames = max(frames, 0)
        // The compositor splits a transition as head = T/2, tail = T - T/2,
        // which is only symmetric while T is even.
        frames -= frames % 2
        out[index].transitionFramesBefore = frames
        framesIntoPrevious = frames
    }
    return out
}

/// The whole cut, played backwards.
///
/// Only the ordered spans change. `bands`, `planClips`, and `materialSeconds`
/// are returned exactly as they came in (I1) — reversing what you watch does
/// not change what you have.
func reversedShotCutAssembly(
    _ assembly: ShotCutAssembly,
    proxies: [String: ShotReverseProxyArtifact],
    framesPerSecond: Double = ShotAudioTiming.framesPerSecond
) -> ShotCutAssembly {
    guard !assembly.playbackItems.isEmpty else { return assembly }
    var value = assembly
    value.playbackItems = reversedShotCutPlaybackItems(
        assembly.playbackItems,
        proxies: proxies,
        framesPerSecond: framesPerSecond
    )
    value.outputSeconds = value.playbackItems.reduce(0) { $0 + $1.durationSeconds }
    value.isReversed = value.playbackItems.contains { $0.playsReversed }
    return value
}
