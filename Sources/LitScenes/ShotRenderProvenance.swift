import Foundation

// PROVENANCE VS INTENT — THE LABEL LAW
//
// A label attached to an ARTIFACT (a render version, a rendered cut's rail
// chip, the player footer) wears what was RENDERED, resolved from the
// version's own persisted clips. A label attached to a FUTURE ACTION (the
// model picker, render buttons, the plan strip) wears intent and names itself
// NEXT. The two never share a surface anonymously — that anonymity is what
// let changing the next-render default relabel an artifact it never touched.
//
// Everything here is pure and reads only persisted state: every generated
// clip already carries provider, exact model id, prompt, trace id, audio
// flag, resolution, and requested + measured durations.

/// The persisted marker pair for a footage segment's clip record (extracted
/// locally, zero provider calls).
private func shotClipIsFootage(provider: String, model: String) -> Bool {
    provider == "footage" || model == "source"
}

/// The Shot-recipe model behind a persisted clip's provider model id, when
/// one exists. Historical CivitAI WAN 2.7 renders resolve to the same model
/// truth as FAL WAN 2.7 — the recipe moved providers, the model did not.
func shotRenderModel(fromClipModel model: String) -> ShotRenderModel? {
    guard let selection = VideoModelSelection.allCases.first(where: { $0.providerModelId == model })
        ?? VideoModelSelection(rawValue: model) else {
        return nil
    }
    switch selection {
    case .falWan27ImageToVideo, .civitaiWanV27: return .wan27
    case .falKlingV3ProImageToVideo: return .falKlingV3Pro
    case .falSeedance20ImageToVideo: return .falSeedance20
    case .falSeedance25ImageToVideo: return .falSeedance25
    case .falHailuo3ImageToVideo: return .falHailuo3
    case .falHailuo3MaxImageToVideo: return .falHailuo3Max
    case .falLTX23AudioToVideo: return .falLTX23Narration
    case .klingV26ImageToVideo: return .klingV26Pro
    default: return nil
    }
}

/// Short display label for one persisted clip's model truth. Falls back to
/// the raw persisted id rather than guessing — an unrecognized id names
/// itself honestly.
func shotClipModelShortLabel(provider: String, model: String) -> String {
    if shotClipIsFootage(provider: provider, model: model) { return "Footage" }
    if let renderModel = shotRenderModel(fromClipModel: model) {
        return renderModel.label
    }
    if let selection = VideoModelSelection.allCases.first(where: { $0.providerModelId == model }) {
        return selection.label
    }
    if let cleaned = model.trimmed.nilIfEmpty { return cleaned }
    return provider.trimmed.nilIfEmpty ?? "Unknown"
}

/// One short line of model truth for a whole version, derived from its clips
/// in first-appearance order:
/// - one model → its label, plus the uniform requested duration and Audio
///   flag when every generated clip agrees (mirror of the intent chip's
///   `shortLabel` shape, so the two are comparable at a glance);
/// - two models → both names ("WAN 2.7 + Kling 3 Pro");
/// - three or more → "Mixed · N models";
/// - only footage clips → "Footage";
/// - a legacy version without per-clip provenance → its version-level stamp,
///   else its recorded stack, else "Rendered".
func shotRenderProvenanceSummary(version: ShotRenderArtifact) -> String {
    let generated = version.segmentClips.filter {
        !shotClipIsFootage(provider: $0.provider, model: $0.model)
    }
    var labels: [String] = []
    for clip in generated {
        let label = shotClipModelShortLabel(provider: clip.provider, model: clip.model)
        if !labels.contains(label) { labels.append(label) }
    }
    switch labels.count {
    case 0:
        if !version.segmentClips.isEmpty { return "Footage" }
        if version.model == "mixed" || version.provider == "mixed" { return "Mixed" }
        if let stack = ShotRenderStack(rawValue: version.stack) { return stack.model.label }
        if let model = version.model.trimmed.nilIfEmpty,
           !["legacy", "local"].contains(model) {
            return shotClipModelShortLabel(provider: version.provider, model: model)
        }
        return "Rendered"
    case 1:
        var parts = [labels[0]]
        let durations = Set(generated.map(\.requestedDurationSeconds)).subtracting([0])
        if durations.count == 1, let seconds = durations.first {
            parts.append("\(seconds)s")
        }
        if generated.allSatisfy(\.generateAudio) {
            parts.append("Audio")
        }
        return parts.joined(separator: " · ")
    case 2:
        return "\(labels[0]) + \(labels[1])"
    default:
        return "Mixed · \(labels.count) models"
    }
}

/// The version number that FIRST paid for the clip carrying this request id.
/// A clip appearing in a later version with the same id traveled in verbatim
/// (partial render, RESUME, suffix render) — the plate marks it REUSED from
/// that origin. Footage and legacy clips (empty request id) never mark.
func shotClipFirstVersionNumber(
    requestId: String,
    versions: [ShotRenderArtifact]
) -> Int? {
    let cleaned = requestId.trimmed
    guard !cleaned.isEmpty else { return nil }
    return versions
        .filter { version in version.segmentClips.contains { $0.requestId == cleaned } }
        .map(\.versionNumber)
        .min()
}

/// The active version's truth for one segment, ONLY when the next render
/// would change it: nil while the clip already matches the segment's
/// effective stack (model, requested duration, and audio), else a short
/// as-rendered descriptor ("Kling 3 Pro · 5s · Audio"). Footage never
/// deltas — it re-extracts identically for free.
func shotSegmentAsRenderedDescriptor(
    clip: ShotRenderSegmentClip,
    nextStack: ShotRenderStack
) -> String? {
    guard !shotClipIsFootage(provider: clip.provider, model: clip.model) else { return nil }
    let matchesModel = shotRenderModel(fromClipModel: clip.model) == nextStack.model
    // A zero requested duration is a legacy record with no claim to compare.
    let matchesDuration = clip.requestedDurationSeconds == 0
        || clip.requestedDurationSeconds == nextStack.segmentSeconds
    let matchesAudio = clip.generateAudio == nextStack.generateAudio
    if matchesModel && matchesDuration && matchesAudio { return nil }
    var parts = [shotClipModelShortLabel(provider: clip.provider, model: clip.model)]
    if clip.requestedDurationSeconds > 0 {
        parts.append("\(clip.requestedDurationSeconds)s")
    }
    if clip.generateAudio { parts.append("Audio") }
    return parts.joined(separator: " · ")
}

/// Why the next render's temporal direction differs from what this clip
/// rendered, or nil when it doesn't. The distinction the clip's plan
/// snapshot exists to make possible: "New beats" when the plans disagree,
/// "New direction compiler" when the beats match but the compiler (or the
/// dialect, via a model change) moved, "Beats added"/"Beats removed" when
/// direction appears or disappears entirely. Clips that rendered plan-less
/// against a plan-less next render never delta.
func shotSegmentDirectionDelta(
    clip: ShotRenderSegmentClip,
    nextPlan: ShotTemporalDirectionPlan?,
    nextCompiled: ShotCompiledSegmentDirection?
) -> String? {
    let hadDirection = clip.directionPlan?.isEmpty == false
    let hasDirection = nextCompiled != nil && nextPlan?.isEmpty == false
    switch (hadDirection, hasDirection) {
    case (false, false):
        return nil
    case (false, true):
        return "Beats added"
    case (true, false):
        return "Beats removed"
    case (true, true):
        if clip.directionPlan?.normalized().signature != nextPlan?.normalized().signature {
            return "New beats"
        }
        if clip.compilerVersion != nextCompiled?.compilerVersion
            || (!clip.compiledDialect.isEmpty && clip.compiledDialect != nextCompiled?.dialect) {
            return "New direction compiler"
        }
        return nil
    }
}

/// A version's clips in the CURRENT plan's placement order where they match,
/// with clips the plan no longer names appended after in persisted order —
/// an old version may predate a re-arrangement, and its orphans are still
/// its history.
func shotVersionClipsInPlanOrder(
    version: ShotRenderArtifact,
    planPlacementKeys: [String]
) -> [ShotRenderSegmentClip] {
    var remaining = version.segmentClips
    var ordered: [ShotRenderSegmentClip] = []
    for key in planPlacementKeys {
        if let index = remaining.firstIndex(where: { $0.placementKey == key }) {
            ordered.append(remaining.remove(at: index))
        }
    }
    return ordered + remaining
}
