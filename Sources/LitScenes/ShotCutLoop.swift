import Foundation

/// THE WHOLE-OUTPUT LOOP: the final ordered spans, repeated N times end to
/// end. The ×N output is exactly the ×1 output played N times — each pass
/// keeps its own spacing (`pass × base + original start`), so the player's
/// one-frame agreement with the stitched composition holds by construction.
///
/// Bands, planClips, insertionCells, and materialSeconds stay BASE: the strip
/// is material space, and looping what you watch does not change what you
/// have (the `reversedShotCutAssembly` doctrine). Repeated spans get
/// pass-suffixed `itemId`s because splice ids, re-chain maps, and SwiftUI
/// identity all key on them.
///
/// Pass seams are deterministic hard cuts: the base first item's
/// `transitionFramesBefore` is 0 by construction (the forward derivation only
/// sets it past index 0, and the reverse recap zeroes index 0), so no
/// dissolve can smear across a seam.
func loopedShotCutAssembly(_ assembly: ShotCutAssembly, count: Int) -> ShotCutAssembly {
    let n = min(max(count, 1), ShotCutList.maximumOutputLoopCount)
    guard n > 1, !assembly.playbackItems.isEmpty, assembly.outputSeconds > 0 else {
        return assembly
    }
    let base = assembly.outputSeconds
    var value = assembly
    var items = assembly.playbackItems
    items.reserveCapacity(assembly.playbackItems.count * n)
    for pass in 1..<n {
        let offset = Double(pass) * base
        for item in assembly.playbackItems {
            var copy = item
            copy.itemId = "loop\(pass)_\(item.itemId)"
            copy.loopPass = pass
            copy.outputStartSeconds = item.outputStartSeconds + offset
            items.append(copy)
        }
    }
    value.playbackItems = items
    value.outputSeconds = Double(n) * base
    value.baseOutputSeconds = base
    value.outputLoopCount = n
    return value
}

/// Where each loop pass begins on the output timeline: `[0]` unlooped,
/// `[0, B, 2B, …]` looped. The pure primitive the audio mix consumes to
/// re-place narration, microphone, clip, and region overlays per pass —
/// everything repeats, so each pass sounds like the first.
func shotLoopPassOffsets(loopCount: Int, baseOutputSeconds: Double) -> [Double] {
    let n = min(max(loopCount, 1), ShotCutList.maximumOutputLoopCount)
    guard n > 1, baseOutputSeconds > 0 else { return [0] }
    return (0..<n).map { Double($0) * baseOutputSeconds }
}
