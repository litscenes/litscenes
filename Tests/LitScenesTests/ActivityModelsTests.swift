import Foundation
import Testing
@testable import LitScenes

// THE ACTIVITY REGISTRY's pure laws: paid-first stable order, cancel only
// where real, the paused suffix, and honest label resolution.

@Test func emptyInputYieldsNoRows() {
    #expect(libraryActivitySnapshot(LibraryActivityInput()).isEmpty)
}

@Test func paidRowsSortAboveFreeRows() {
    var input = LibraryActivityInput()
    input.reelBakeRunningCount = 2
    input.ambientBedBaking = true
    input.shotRenderShotId = "shot_1"
    input.mediaAnalysisRunning = true
    let rows = libraryActivitySnapshot(input)
    #expect(rows.map(\.isPaid) == [true, true, false, false])
    #expect(rows.first?.id == "shot_render")
}

@Test func shotRenderResolvesShotNameAndFallsBackToCut() {
    var input = LibraryActivityInput()
    input.shotRenderShotId = "shot_1"
    input.shotNameById = ["shot_1": "Harbor Slams"]
    #expect(libraryActivitySnapshot(input).first?.detail == "Harbor Slams")

    input.shotNameById = [:]
    #expect(libraryActivitySnapshot(input).first?.detail == "Cut")
}

@Test func shotLookCancelExistsOnlyWhenTheOwnerIsKnown() {
    var input = LibraryActivityInput()
    input.shotLookVersionId = "look_1"
    // Unresolvable owner: no decorative cancel.
    #expect(libraryActivitySnapshot(input).first?.cancel == ActivityCancelAction.none)

    input.shotIdByLookVersionId = ["look_1": "shot_1"]
    #expect(libraryActivitySnapshot(input).first?.cancel == .shotLook(shotId: "shot_1"))
}

@Test func clipLookRowsAreStableSortedAndCarryTheirVersionCancel() {
    var input = LibraryActivityInput()
    input.clipLookVersionIds = ["cl_b", "cl_a"]
    input.shotIdByClipLookVersionId = ["cl_a": "shot_1", "cl_b": "shot_2"]
    input.clipLookLabelByVersionId = ["cl_a": "Clip 2 · Look 1"]
    let rows = libraryActivitySnapshot(input)
    #expect(rows.map(\.id) == ["clip_look_cl_a", "clip_look_cl_b"])
    #expect(rows[0].detail == "Clip 2 · Look 1")
    #expect(rows[0].cancel == .clipLook(shotId: "shot_1", versionId: "cl_a"))
    // No label map entry: the shot name (or "Cut") steps in.
    #expect(rows[1].detail == "Cut")
}

@Test func joinBridgeResolvesShotThroughTheCutMap() {
    var input = LibraryActivityInput()
    input.joinRenderCutId = "cut_9"
    input.shotIdByCutId = ["cut_9": "shot_3"]
    input.shotNameById = ["shot_3": "Finale"]
    let rows = libraryActivitySnapshot(input)
    #expect(rows.first?.label == "Join bridge")
    #expect(rows.first?.detail == "Finale")
    #expect(rows.first?.cancel == ActivityCancelAction.none)
}

@Test func pausedSuffixDecoratesEveryPaidRowAndNeverFreeRows() {
    var input = LibraryActivityInput()
    input.isGenerationPaused = true
    input.shotRenderShotId = "shot_1"
    input.shotNameById = ["shot_1": "Opening"]
    input.sceneStoriesActive = true
    input.reelBakeRunningCount = 1
    let rows = libraryActivitySnapshot(input)
    #expect(rows[0].detail == "Opening · \(activityPausedSuffix)")
    // A paid row with no detail wears the suffix alone.
    #expect(rows[1].detail == activityPausedSuffix)
    // Free local work continues while paused — no suffix.
    #expect(rows[2].detail == "1 baking")
}

@Test func mediaAnalysisAndReelBakesWearTheirRealCancels() {
    var input = LibraryActivityInput()
    input.mediaAnalysisRunning = true
    input.reelBakeRunningCount = 3
    let rows = libraryActivitySnapshot(input)
    #expect(rows[0].cancel == .mediaAnalysis)
    #expect(rows[1].cancel == .reelBakes)
    #expect(rows[1].detail == "3 baking")
}

@Test func cancelLessPaidOpsNeverGrowCancelAffordances() {
    var input = LibraryActivityInput()
    input.shotRenderShotId = "shot_1"
    input.joinRenderCutId = "cut_1"
    input.shotNarrationShotId = "shot_1"
    input.lensHeroActive = true
    input.storyAudioGenerating = true
    let rows = libraryActivitySnapshot(input)
    #expect(rows.count == 5)
    let allCancelFree = rows.allSatisfy { $0.cancel == ActivityCancelAction.none }
    #expect(allCancelFree)
}

@Test func countedRowsPluralizeHonestly() {
    var input = LibraryActivityInput()
    input.reframeOperationCount = 1
    input.reverseBakeShotCount = 2
    var rows = libraryActivitySnapshot(input)
    #expect(rows[0].detail == "1 running")
    #expect(rows[1].detail == "2 cuts")

    input.reframeOperationCount = 3
    input.reverseBakeShotCount = 1
    rows = libraryActivitySnapshot(input)
    #expect(rows[0].detail == "3 running")
    #expect(rows[1].detail == "1 cut")
}

@Test func parallelFrameTakesShareOneCountedRow() {
    var input = LibraryActivityInput()
    input.lensHeroActive = true
    input.lensHeroTakeOperationCount = 3
    var rows = libraryActivitySnapshot(input)
    #expect(rows.count == 1)
    #expect(rows[0].id == "frame_render")
    #expect(rows[0].label == "Frame renders")
    #expect(rows[0].detail == "3 running")

    // A single render keeps the singular label and its lens-label detail.
    input.lensHeroTakeOperationCount = 1
    input.lensHeroLabel = "Harbor at dusk"
    rows = libraryActivitySnapshot(input)
    #expect(rows[0].label == "Frame render")
    #expect(rows[0].detail == "Harbor at dusk")
}

@Test func theFullBoardKeepsAStableOrder() {
    var input = LibraryActivityInput()
    input.shotRenderShotId = "s"
    input.joinRenderCutId = "c"
    input.shotLookVersionId = "l"
    input.clipLookVersionIds = ["cl"]
    input.shotNarrationShotId = "s"
    input.lensHeroActive = true
    input.mediaAnalysisRunning = true
    input.reverseBakeShotCount = 1
    input.reelBakeRunningCount = 1
    input.ambientBedBaking = true
    input.videoTrimSaving = true
    let rows = libraryActivitySnapshot(input)
    #expect(rows.map(\.id) == [
        "shot_render", "join_bridge", "shot_look", "clip_look_cl",
        "shot_narration", "frame_render", "media_analysis",
        "reverse_bakes", "reel_bakes", "ambient_bed", "video_trim",
    ])
}

@Test func storyLanesSurfaceAsPaidRows() {
    var input = LibraryActivityInput()
    input.storylineActive = true
    input.storyDirectionsActive = true
    input.storyBeatBoardActive = true
    input.storyBeatBoardLabel = "Act II"
    input.goalInterviewActive = true
    let rows = libraryActivitySnapshot(input)
    #expect(rows.count == 4)
    let allPaid = rows.allSatisfy(\.isPaid)
    #expect(allPaid)
    #expect(rows.first { $0.id == "beat_board" }?.detail == "Act II")
}

@Test func mediaViewerLanesRenderPaidRowsWithRealCancelsOnly() {
    var input = LibraryActivityInput()
    input.mediaLookVersionIds = ["medialook_b", "medialook_a"]
    input.mediaLookLabelByVersionId = ["medialook_a": "clip.mp4"]
    input.mediaMotionJobIds = ["mediamotion_1"]
    input.mediaMotionLabelByJobId = ["mediamotion_1": "sunset.png"]

    let rows = libraryActivitySnapshot(input)
    let allPaid = rows.allSatisfy { $0.isPaid }
    #expect(allPaid)

    // Stable sort by versionId; label falls back to "Video".
    let lookRows = rows.filter { $0.id.hasPrefix("media_look_") }
    let lookDetails = lookRows.map { $0.detail }
    #expect(lookDetails == ["clip.mp4", "Video"])
    #expect(lookRows.first?.cancel == .mediaLook(versionId: "medialook_a"))

    let motion = rows.first { $0.id == "media_motion_mediamotion_1" }
    #expect(motion?.label == "Start Video")
    #expect(motion?.cancel == .mediaMotion(jobId: "mediamotion_1"))

    // The paused suffix rides every paid media row too.
    input.isGenerationPaused = true
    let paused = libraryActivitySnapshot(input)
    #expect(paused.allSatisfy { $0.detail.contains(activityPausedSuffix) })
}

@Test func youtubeExportShowsAsAFreeLocalRow() {
    var input = LibraryActivityInput()
    input.youtubeExportActive = true
    let rows = libraryActivitySnapshot(input)
    #expect(rows.count == 1)
    #expect(rows.first?.id == "youtube_export")
    #expect(rows.first?.isPaid == false)
    #expect(rows.first?.cancel == ActivityCancelAction.none)
}
