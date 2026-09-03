import Foundation

/// One vocabulary law for the primary render CTA, shared by the Stage rail
/// (`CutStripView.renderControls`), the render plan strip, and the player's
/// prompt-panel footer — three surfaces that previously named the same state
/// three ways. A draft whose plan is fully covered by readable seed clips —
/// a combined draft, or an ordinary cut that received pasted segment cards —
/// FINALIZEs for $0 (local assembly, zero provider calls); a partially
/// covered draft RENDERs MISSING (seeds reused verbatim, only the gap
/// bills); everything else RENDERs. The engine already reuses seeds
/// regardless of their origin (`renderShot`'s implicit seed filter); this
/// vocabulary must keep saying so, or a pasted take's row offers to re-pay
/// for pixels it already has.
enum CutRenderCTA: Equatable {
    case finalizeFree
    case renderMissing
    case render

    var railLabel: String {
        switch self {
        case .finalizeFree: return "OPEN"
        case .renderMissing: return "RENDER MISSING"
        case .render: return "RENDER"
        }
    }

    /// A draft playing (partly) from seed clips — combined or pasted-into.
    var isSeedDraft: Bool { self != .render }
}

/// Seed coverage for a draft: which placement keys already play from
/// readable seed clips. Shared derivation so the rail, plan strip, and panel
/// can never disagree about what "missing" means.
func cutReadableSeedKeys(cut: ProjectShot) -> Set<String> {
    Set(cut.seedSegmentClips.compactMap { clip in
        FileManager.default.fileExists(atPath: clip.clipPath) ? clip.placementKey : nil
    })
}

/// THE LOOK RAIL VOCABULARY: what the stage rail says about a cut's Looks.
/// A finished restyle lands as a VERSION of the cut (its output becomes the
/// Look everywhere it plays, Finals included) — it is deliberately not a new
/// row, because a Look is flattened picture with no segment structure. That
/// makes the rail the only place a restyle can be seen without opening the
/// player, so this label carries the whole answer to "where did it land?".
@MainActor
func shotLookRailChipLabel(active: ShotRestyleArtifact?, readyLookCount: Int) -> String {
    guard let active else {
        return "\(readyLookCount) LOOK\(readyLookCount == 1 ? "" : "S") · ORIGINAL"
    }
    let roman = FrameCreatorModal.romanNumeral(active.versionNumber)
    let style = active.styleLabel.trimmed
    return style.isEmpty ? "LOOK \(roman)" : "LOOK \(roman) · \(style.uppercased())"
}

@MainActor
func shotLookRailChipHelp(active: ShotRestyleArtifact?, readyLookCount: Int) -> String {
    guard let active else {
        return "\(readyLookCount) finished Look\(readyLookCount == 1 ? "" : "s") live on this CUT, but it is "
            + "playing Original. Looks are versions of this row, not rows of their own — open the player to "
            + "flip between them."
    }
    let roman = FrameCreatorModal.romanNumeral(active.versionNumber)
    return "This CUT's output IS Look \(roman) — everywhere it plays, including the Finals reel. It is a "
        + "version of this row, not a row of its own; KEEP AS NEW CUT flattens it (picture + this cut's "
        + "audio mix) into a new row directly below."
}

func cutRenderCTA(cut: ProjectShot, segmentCount: Int) -> CutRenderCTA {
    guard cut.browsableRenderVersions.isEmpty else { return .render }
    let readableSeedCount = cutReadableSeedKeys(cut: cut).count
    // Seed vocabulary for any draft that HAS seeds (a combined draft with
    // unreadable seed files keeps its RENDER MISSING honesty).
    guard readableSeedCount > 0 || !cut.combinedSources.isEmpty else { return .render }
    return segmentCount > 0 && readableSeedCount >= segmentCount
        ? .finalizeFree
        : .renderMissing
}
