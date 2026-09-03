import Foundation

// THE ACTIVITY REGISTRY — one honest list of everything the app is doing
// right now, from anywhere. Pure values in, pure rows out: the engine
// gathers its in-flight state into `LibraryActivityInput`, and
// `libraryActivitySnapshot` is the single law turning it into display rows.
//
// LAWS:
// - PAID FIRST: rows that spend money sort above free local work, in a
//   fixed stable order — the operator's eye lands on spend.
// - CANCEL ONLY WHERE REAL: a row wears a cancel affordance only when the
//   engine truly has one (Shot Look, Clip Look, reel bakes, media
//   analysis). No decorative cancel buttons over uncancellable work.
// - THE PAUSE SUFFIX: while generation is paused, every PAID row says
//   "parked — paused" — cooperative pause means the in-flight step finishes
//   and the loop parks, and the row says so instead of implying progress.
// - LABEL RESOLUTION: version/cut ids resolve to shot names at snapshot
//   time via the input's maps; an unresolvable id honestly says "Cut".

/// What a row's cancel button actually does. A pure value the popover maps
/// onto the engine's real cancel entry points — no closures, so the
/// registry stays Equatable and testable.
enum ActivityCancelAction: Equatable, Hashable, Sendable {
    case none
    case shotLook(shotId: String)
    case clipLook(shotId: String, versionId: String)
    /// A viewer restyle of a raw tray video (media-home Clip Look).
    case mediaLook(versionId: String)
    /// A viewer image-to-video render (media-motion lane).
    case mediaMotion(jobId: String)
    case reelBakes
    case mediaAnalysis
}

struct ActivityRow: Equatable, Identifiable, Sendable {
    var id: String
    var kind: String
    var label: String
    var detail: String = ""
    var isPaid: Bool
    var cancel: ActivityCancelAction = .none
}

/// Plain-value mirror of every in-flight engine prop the registry reads.
/// The engine builds one per access; tests build them directly.
struct LibraryActivityInput: Equatable, Sendable {
    var isGenerationPaused = false

    // Paid lanes.
    var shotRenderShotId = ""
    var joinRenderCutId = ""
    var shotLookVersionId = ""
    var clipLookVersionIds: [String] = []
    var shotNarrationShotId = ""
    var lensHeroActive = false
    var lensHeroLabel = ""
    /// Row-scoped frame renders in flight (the parallel take lane).
    var lensHeroTakeOperationCount = 0
    var reframeOperationCount = 0
    var characterRenderActive = false
    var characterRenderName = ""
    var initialDraftsActive = false
    var sceneStoriesActive = false
    var videoChainActive = false
    var storyAudioGenerating = false
    var storyAudioDrafting = false
    var storylineActive = false
    var storyDirectionsActive = false
    var storyBeatBoardActive = false
    var storyBeatBoardLabel = ""
    var storyBeatsDrafting = false
    var storySignalsActive = false
    var storylineInterviewActive = false
    var goalInterviewActive = false
    var lensNarrationActive = false
    var mediaAnalysisRunning = false
    /// Viewer generations: media-home looks and motion renders — labels
    /// resolve to filenames.
    var mediaLookVersionIds: [String] = []
    var mediaLookLabelByVersionId: [String: String] = [:]
    var mediaMotionJobIds: [String] = []
    var mediaMotionLabelByJobId: [String: String] = [:]

    // Free local lanes.
    var reverseBakeShotCount = 0
    var reelBakeRunningCount = 0
    var ambientBedBaking = false
    var narrationRetimeShotId = ""
    var storyAudioRemixActive = false
    var videoTrimSaving = false
    var youtubeExportActive = false

    // Label maps, resolved by the engine at snapshot time.
    var shotNameById: [String: String] = [:]
    var shotIdByLookVersionId: [String: String] = [:]
    var shotIdByClipLookVersionId: [String: String] = [:]
    var clipLookLabelByVersionId: [String: String] = [:]
    var shotIdByCutId: [String: String] = [:]

    init() {}
}

/// The suffix every paid row wears while generation is paused.
let activityPausedSuffix = "parked — paused"

/// THE REGISTRY LAW: input → display rows, paid first, stable order,
/// cancel only where real, paused suffix on every paid row.
func libraryActivitySnapshot(_ input: LibraryActivityInput) -> [ActivityRow] {
    var paid: [ActivityRow] = []
    var free: [ActivityRow] = []

    func shotName(_ shotId: String) -> String {
        input.shotNameById[shotId]?.trimmed.nilIfEmpty ?? "Cut"
    }

    if !input.shotRenderShotId.isEmpty {
        paid.append(ActivityRow(
            id: "shot_render",
            kind: "shot_render",
            label: "Shot render",
            detail: shotName(input.shotRenderShotId),
            isPaid: true
        ))
    }
    if !input.joinRenderCutId.isEmpty {
        let shotId = input.shotIdByCutId[input.joinRenderCutId] ?? ""
        paid.append(ActivityRow(
            id: "join_bridge",
            kind: "join_bridge",
            label: "Join bridge",
            detail: shotName(shotId),
            isPaid: true
        ))
    }
    if !input.shotLookVersionId.isEmpty {
        let shotId = input.shotIdByLookVersionId[input.shotLookVersionId] ?? ""
        paid.append(ActivityRow(
            id: "shot_look",
            kind: "shot_look",
            label: "Shot Look",
            detail: shotName(shotId),
            isPaid: true,
            cancel: shotId.isEmpty ? .none : .shotLook(shotId: shotId)
        ))
    }
    for versionId in input.clipLookVersionIds.sorted() {
        let shotId = input.shotIdByClipLookVersionId[versionId] ?? ""
        let label = input.clipLookLabelByVersionId[versionId]?.trimmed.nilIfEmpty
            ?? shotName(shotId)
        paid.append(ActivityRow(
            id: "clip_look_\(versionId)",
            kind: "clip_look",
            label: "Clip Look",
            detail: label,
            isPaid: true,
            cancel: shotId.isEmpty
                ? .none
                : .clipLook(shotId: shotId, versionId: versionId)
        ))
    }
    for versionId in input.mediaLookVersionIds.sorted() {
        paid.append(ActivityRow(
            id: "media_look_\(versionId)",
            kind: "clip_look",
            label: "Media Look",
            detail: input.mediaLookLabelByVersionId[versionId]?.trimmed.nilIfEmpty ?? "Video",
            isPaid: true,
            cancel: .mediaLook(versionId: versionId)
        ))
    }
    for jobId in input.mediaMotionJobIds.sorted() {
        paid.append(ActivityRow(
            id: "media_motion_\(jobId)",
            kind: "shot_render",
            label: "Start Video",
            detail: input.mediaMotionLabelByJobId[jobId]?.trimmed.nilIfEmpty ?? "Image",
            isPaid: true,
            cancel: .mediaMotion(jobId: jobId)
        ))
    }
    if !input.shotNarrationShotId.isEmpty {
        paid.append(ActivityRow(
            id: "shot_narration",
            kind: "narration_tts",
            label: "Shot narration",
            detail: shotName(input.shotNarrationShotId),
            isPaid: true
        ))
    }
    if input.lensHeroActive {
        // The take lane runs several row renders at once; one row states the
        // count (the reframes row's idiom). A single render keeps its label.
        let takeCount = input.lensHeroTakeOperationCount
        paid.append(ActivityRow(
            id: "frame_render",
            kind: "image",
            label: takeCount > 1 ? "Frame renders" : "Frame render",
            detail: takeCount > 1 ? "\(takeCount) running" : input.lensHeroLabel.trimmed,
            isPaid: true
        ))
    }
    if input.reframeOperationCount > 0 {
        paid.append(ActivityRow(
            id: "reframes",
            kind: "image",
            label: "Reframes",
            detail: input.reframeOperationCount == 1
                ? "1 running"
                : "\(input.reframeOperationCount) running",
            isPaid: true
        ))
    }
    if input.characterRenderActive {
        paid.append(ActivityRow(
            id: "character_render",
            kind: "image",
            label: "Character render",
            detail: input.characterRenderName.trimmed,
            isPaid: true
        ))
    }
    if input.initialDraftsActive {
        paid.append(ActivityRow(
            id: "initial_frames",
            kind: "image",
            label: "Initial frames",
            isPaid: true
        ))
    }
    if input.sceneStoriesActive {
        paid.append(ActivityRow(
            id: "scene_stories",
            kind: "story",
            label: "Scene stories",
            isPaid: true
        ))
    }
    if input.videoChainActive {
        paid.append(ActivityRow(
            id: "video_chain",
            kind: "shot_render",
            label: "Video chain",
            isPaid: true
        ))
    }
    if input.storyAudioGenerating {
        paid.append(ActivityRow(
            id: "story_audio",
            kind: "story_audio_tts",
            label: "Story audio",
            isPaid: true
        ))
    }
    if input.storyAudioDrafting {
        paid.append(ActivityRow(
            id: "story_audio_draft",
            kind: "story",
            label: "Story audio draft",
            isPaid: true
        ))
    }
    if input.storylineActive {
        paid.append(ActivityRow(
            id: "storyline",
            kind: "story",
            label: "Storyline",
            isPaid: true
        ))
    }
    if input.storyDirectionsActive {
        paid.append(ActivityRow(
            id: "story_directions",
            kind: "story",
            label: "Story directions",
            isPaid: true
        ))
    }
    if input.storyBeatBoardActive {
        paid.append(ActivityRow(
            id: "beat_board",
            kind: "story",
            label: "Beat board",
            detail: input.storyBeatBoardLabel.trimmed,
            isPaid: true
        ))
    }
    if input.storyBeatsDrafting {
        paid.append(ActivityRow(
            id: "beat_draft",
            kind: "story",
            label: "Beat draft",
            isPaid: true
        ))
    }
    if input.storySignalsActive {
        paid.append(ActivityRow(
            id: "story_signals",
            kind: "story",
            label: "Story signals",
            isPaid: true
        ))
    }
    if input.storylineInterviewActive {
        paid.append(ActivityRow(
            id: "storyline_interview",
            kind: "story",
            label: "Storyline interview",
            isPaid: true
        ))
    }
    if input.goalInterviewActive {
        paid.append(ActivityRow(
            id: "goal_interview",
            kind: "story",
            label: "Goal interview",
            isPaid: true
        ))
    }
    if input.lensNarrationActive {
        paid.append(ActivityRow(
            id: "frame_narration",
            kind: "narration_tts",
            label: "Frame narration",
            isPaid: true
        ))
    }
    if input.mediaAnalysisRunning {
        paid.append(ActivityRow(
            id: "media_analysis",
            kind: "analysis",
            label: "Media analysis",
            isPaid: true,
            cancel: .mediaAnalysis
        ))
    }

    if input.reverseBakeShotCount > 0 {
        free.append(ActivityRow(
            id: "reverse_bakes",
            kind: "local",
            label: "Reverse bakes",
            detail: input.reverseBakeShotCount == 1
                ? "1 cut"
                : "\(input.reverseBakeShotCount) cuts",
            isPaid: false
        ))
    }
    if input.reelBakeRunningCount > 0 {
        free.append(ActivityRow(
            id: "reel_bakes",
            kind: "local",
            label: "Reel bakes",
            detail: input.reelBakeRunningCount == 1
                ? "1 baking"
                : "\(input.reelBakeRunningCount) baking",
            isPaid: false,
            cancel: .reelBakes
        ))
    }
    if input.ambientBedBaking {
        free.append(ActivityRow(
            id: "ambient_bed",
            kind: "local",
            label: "Ambient bed bake",
            isPaid: false
        ))
    }
    if !input.narrationRetimeShotId.isEmpty {
        free.append(ActivityRow(
            id: "narration_retime",
            kind: "local",
            label: "Narration retime",
            detail: shotName(input.narrationRetimeShotId),
            isPaid: false
        ))
    }
    if input.storyAudioRemixActive {
        free.append(ActivityRow(
            id: "audio_remix",
            kind: "local",
            label: "Audio remix",
            isPaid: false
        ))
    }
    if input.videoTrimSaving {
        free.append(ActivityRow(
            id: "video_trim",
            kind: "local",
            label: "Saving cut",
            isPaid: false
        ))
    }
    if input.youtubeExportActive {
        free.append(ActivityRow(
            id: "youtube_export",
            kind: "local",
            label: "YouTube export",
            isPaid: false
        ))
    }

    if input.isGenerationPaused {
        paid = paid.map { row in
            var updated = row
            updated.detail = updated.detail.isEmpty
                ? activityPausedSuffix
                : "\(updated.detail) · \(activityPausedSuffix)"
            return updated
        }
    }
    return paid + free
}
