import Foundation
import Testing
@testable import LitScenes

private func trimTestMediaItem(
    id: String,
    kind: MediaKind = .video,
    sourceId: String = "source_test",
    filename: String? = nil,
    width: Int = 1920,
    height: Int = 1080,
    durationSeconds: Double? = 30,
    derivativeKind: String? = nil,
    sourceMediaId: String? = nil,
    sourceTimestampSeconds: Double? = nil
) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: id,
        sourceId: sourceId,
        kind: kind,
        filename: filename ?? "\(id).mp4",
        path: "/tmp/\(id).mp4",
        relativePath: "\(id).mp4",
        byteCount: 1,
        modifiedAt: "2026-07-16T00:00:00Z",
        width: width,
        height: height,
        durationSeconds: durationSeconds,
        nominalFrameRate: 24,
        thumbnailPath: "/tmp/\(id)_thumb.jpg",
        videoStripPath: nil,
        scannedAt: "2026-07-16T00:00:00Z",
        scanError: nil,
        derivativeKind: derivativeKind,
        sourceMediaId: sourceMediaId,
        sourceTimestampSeconds: sourceTimestampSeconds
    )
}

@Test func videoTrimFlagRequiresSourceMediaId() {
    let trim = trimTestMediaItem(id: "trim_1", derivativeKind: "video_trim", sourceMediaId: "vid_1")
    #expect(trim.isVideoTrim)

    let unparented = trimTestMediaItem(id: "trim_2", derivativeKind: "video_trim")
    #expect(!unparented.isVideoTrim)

    let plainVideo = trimTestMediaItem(id: "vid_1")
    #expect(!plainVideo.isVideoTrim)
}

@Test func videoTrimIsExcludedFromGeneratedMedia() {
    // Deliberate, mirroring video_frame: trims are SOURCE-like assets. The
    // scan preservation filter in LibraryEngine keeps them alive via its own
    // `isVideoTrim` clause — adding video_trim to isGeneratedMedia would
    // change tray/roster surfaces that key on generated media.
    let trim = trimTestMediaItem(id: "trim_1", derivativeKind: "video_trim", sourceMediaId: "vid_1")
    #expect(!trim.isGeneratedMedia)

    let chainClip = trimTestMediaItem(id: "clip_1", derivativeKind: "video_chain_clip", sourceMediaId: "segment_1")
    #expect(chainClip.isGeneratedMedia)
}

@Test func videoTrimCannotBeEnabledContent() {
    let trim = trimTestMediaItem(id: "trim_1", derivativeKind: "video_trim", sourceMediaId: "vid_1")
    #expect(!trim.canBeEnabledContent)
}

@Test func videoTrimPortraitDetection() {
    #expect(trimTestMediaItem(id: "p", width: 1080, height: 1920).isPortrait)
    #expect(!trimTestMediaItem(id: "l", width: 1920, height: 1080).isPortrait)
    #expect(!trimTestMediaItem(id: "s", width: 1080, height: 1080).isPortrait)
    #expect(!trimTestMediaItem(id: "z", width: 0, height: 0).isPortrait)
}

@Test func videoTrimRangeClamping() {
    let clamped = VideoTrimRange.clamped(start: -2, end: 40, videoDurationSeconds: 30)
    #expect(clamped.startSeconds == 0)
    #expect(clamped.endSeconds == 30)
    #expect(clamped.isSaveable)

    let inverted = VideoTrimRange.clamped(start: 12, end: 4, videoDurationSeconds: 30)
    #expect(inverted.startSeconds == 4)
    #expect(inverted.endSeconds == 12)

    let tooShort = VideoTrimRange.clamped(start: 5, end: 5.2, videoDurationSeconds: 30)
    #expect(!tooShort.isSaveable)

    let exactlyMinimum = VideoTrimRange.clamped(start: 5, end: 5 + VideoTrimRange.minimumTrimSeconds, videoDurationSeconds: 30)
    #expect(exactlyMinimum.isSaveable)
}

@Test func videoTrimMediaIdIsDeterministic() {
    let range = VideoTrimRange(startSeconds: 4.2, endSeconds: 12.7)
    let first = videoTrimMediaId(parentMediaId: "vid_1", range: range)
    let second = videoTrimMediaId(parentMediaId: "vid_1", range: range)
    #expect(first == second)
    #expect(first.hasPrefix("trim_"))
    #expect(first.count == 25)

    let differentRange = videoTrimMediaId(parentMediaId: "vid_1", range: VideoTrimRange(startSeconds: 4.2, endSeconds: 12.8))
    #expect(differentRange != first)

    let differentParent = videoTrimMediaId(parentMediaId: "vid_2", range: range)
    #expect(differentParent != first)
}

@Test func videoTrimFilenameIsFilesystemSafe() {
    let range = VideoTrimRange(startSeconds: 4.2, endSeconds: 12.7)
    let filename = videoTrimFilename(parentFilename: "My Clip:2024.MOV", range: range)
    #expect(filename == "my-clip-2024_trim_00m04s-00m13s.mp4")
    #expect(!filename.contains(":"))
    #expect(!filename.contains(" "))
    #expect(!filename.contains("·"))
}

@Test func videoTrimDisplayLabelFormats() {
    #expect(videoTrimDisplayLabel(range: VideoTrimRange(startSeconds: 4.2, endSeconds: 12.7)) == "0:04 – 0:13 · 8.5s")
    #expect(videoTrimDisplayLabel(range: VideoTrimRange(startSeconds: 0, endSeconds: 8)) == "0:00 – 0:08 · 8s")
    #expect(videoTrimDisplayLabel(range: VideoTrimRange(startSeconds: 3600, endSeconds: 3725)) == "1:00:00 – 1:02:05 · 125s")
}

@Test func videoTrimPlayheadLabelCarriesTenths() {
    #expect(videoTrimPlayheadLabel(9.44) == "0:09.4")
    #expect(videoTrimPlayheadLabel(9.97) == "0:10.0")
    #expect(videoTrimPlayheadLabel(0) == "0:00.0")
    #expect(videoTrimPlayheadLabel(-3) == "0:00.0")
    // .rounded() is half-away-from-zero: .25 → tenths 2.5 → 3.
    #expect(videoTrimPlayheadLabel(3725.25) == "1:02:05.3")
    #expect(videoTrimPlayheadLabel(3725.21) == "1:02:05.2")
}

@Test func videoTrimTrayGroupingNestsTrimsUnderVisibleParent() {
    let parent = trimTestMediaItem(id: "vid_1")
    let lateTrim = trimTestMediaItem(id: "trim_late", derivativeKind: "video_trim", sourceMediaId: "vid_1", sourceTimestampSeconds: 20)
    let earlyTrim = trimTestMediaItem(id: "trim_early", derivativeKind: "video_trim", sourceMediaId: "vid_1", sourceTimestampSeconds: 2)

    let layout = videoTrayLayout(videos: [parent, lateTrim, earlyTrim], isRejected: { _ in false })
    #expect(layout.visibleGroups.count == 1)
    #expect(layout.visibleGroups[0].parent.mediaId == "vid_1")
    #expect(layout.visibleGroups[0].trims.map(\.mediaId) == ["trim_early", "trim_late"])
    #expect(layout.hiddenItems.isEmpty)
}

@Test func videoTrimTrayGroupingSurfacesOrphanAndHiddenParentTrims() {
    let parent = trimTestMediaItem(id: "vid_1")
    let trim = trimTestMediaItem(id: "trim_1", derivativeKind: "video_trim", sourceMediaId: "vid_1", sourceTimestampSeconds: 4)
    let orphanTrim = trimTestMediaItem(id: "trim_orphan", derivativeKind: "video_trim", sourceMediaId: "vid_missing", sourceTimestampSeconds: 1)

    // Parent hidden → its trim surfaces top-level; missing parent → same.
    let layout = videoTrayLayout(videos: [parent, trim, orphanTrim], isRejected: { $0.mediaId == "vid_1" })
    #expect(layout.hiddenItems.map(\.mediaId) == ["vid_1"])
    #expect(layout.visibleGroups.map(\.parent.mediaId) == ["trim_1", "trim_orphan"])
    #expect(layout.visibleGroups.allSatisfy { $0.trims.isEmpty })
}

@Test func videoTrimTrayGroupingKeepsVideoChainClipsTopLevel() {
    // Chain clips have a sourceMediaId (segment id) but are NOT trims — they
    // keep their own top-level spot exactly as today.
    let chainClip = trimTestMediaItem(id: "clip_1", derivativeKind: "video_chain_clip", sourceMediaId: "segment_x")
    let parent = trimTestMediaItem(id: "vid_1")

    let layout = videoTrayLayout(videos: [chainClip, parent], isRejected: { _ in false })
    #expect(layout.visibleGroups.map(\.parent.mediaId) == ["clip_1", "vid_1"])
}

@Test func videoTrimTrayGroupingRejectedTrimGoesHidden() {
    let parent = trimTestMediaItem(id: "vid_1")
    let trim = trimTestMediaItem(id: "trim_1", derivativeKind: "video_trim", sourceMediaId: "vid_1", sourceTimestampSeconds: 4)

    let layout = videoTrayLayout(videos: [parent, trim], isRejected: { $0.mediaId == "trim_1" })
    #expect(layout.visibleGroups.count == 1)
    #expect(layout.visibleGroups[0].trims.isEmpty)
    #expect(layout.hiddenItems.map(\.mediaId) == ["trim_1"])
}

@Test func clipLookMediaFlagRequiresSourceMediaId() {
    let look = trimTestMediaItem(id: "look_1", derivativeKind: "clip_look", sourceMediaId: "vid_1")
    #expect(look.isClipLookMedia)
    #expect(look.isGeneratedMedia)

    let unparented = trimTestMediaItem(id: "look_2", derivativeKind: "clip_look")
    #expect(!unparented.isClipLookMedia)

    let shotExport = trimTestMediaItem(id: "export_1", derivativeKind: "shot_export", sourceMediaId: "shot_1")
    #expect(!shotExport.isClipLookMedia)
    #expect(shotExport.isGeneratedMedia)
}

@Test func clipLookTrayGroupingNestsUnderTopLevelSource() {
    let parent = trimTestMediaItem(id: "vid_1")
    let lateLook = trimTestMediaItem(id: "look_late", derivativeKind: "clip_look", sourceMediaId: "vid_1", sourceTimestampSeconds: 12)
    let earlyLook = trimTestMediaItem(id: "look_early", derivativeKind: "clip_look", sourceMediaId: "vid_1", sourceTimestampSeconds: 3)

    let layout = videoTrayLayout(videos: [parent, lateLook, earlyLook], isRejected: { _ in false })
    #expect(layout.visibleGroups.count == 1)
    #expect(layout.visibleGroups[0].parent.mediaId == "vid_1")
    #expect(layout.visibleGroups[0].looks.map(\.mediaId) == ["look_early", "look_late"])
    #expect(layout.visibleGroups[0].trims.isEmpty)
}

@Test func clipLookOfTrimClimbsToTrimParentGroup() {
    // A look of a trim lands in the trim's parent group, so a group shows
    // the source video with everything cut or restyled from it.
    let parent = trimTestMediaItem(id: "vid_1")
    let trim = trimTestMediaItem(id: "trim_1", derivativeKind: "video_trim", sourceMediaId: "vid_1", sourceTimestampSeconds: 8)
    let lookOfTrim = trimTestMediaItem(id: "look_1", derivativeKind: "clip_look", sourceMediaId: "trim_1", sourceTimestampSeconds: 1)

    let layout = videoTrayLayout(videos: [parent, trim, lookOfTrim], isRejected: { _ in false })
    #expect(layout.visibleGroups.count == 1)
    #expect(layout.visibleGroups[0].parent.mediaId == "vid_1")
    #expect(layout.visibleGroups[0].trims.map(\.mediaId) == ["trim_1"])
    #expect(layout.visibleGroups[0].looks.map(\.mediaId) == ["look_1"])
}

@Test func clipLookTrayGroupingSurfacesOrphanAndHiddenAnchor() {
    let parent = trimTestMediaItem(id: "vid_1")
    let look = trimTestMediaItem(id: "look_1", derivativeKind: "clip_look", sourceMediaId: "vid_1", sourceTimestampSeconds: 2)
    let orphanLook = trimTestMediaItem(id: "look_orphan", derivativeKind: "clip_look", sourceMediaId: "vid_missing", sourceTimestampSeconds: 1)

    let layout = videoTrayLayout(videos: [parent, look, orphanLook], isRejected: { $0.mediaId == "vid_1" })
    #expect(layout.hiddenItems.map(\.mediaId) == ["vid_1"])
    #expect(layout.visibleGroups.map(\.parent.mediaId) == ["look_1", "look_orphan"])
    #expect(layout.visibleGroups.allSatisfy { $0.trims.isEmpty && $0.looks.isEmpty })
}

@Test func clipLookTrayGroupingRejectedLookGoesHidden() {
    let parent = trimTestMediaItem(id: "vid_1")
    let look = trimTestMediaItem(id: "look_1", derivativeKind: "clip_look", sourceMediaId: "vid_1", sourceTimestampSeconds: 2)

    let layout = videoTrayLayout(videos: [parent, look], isRejected: { $0.mediaId == "look_1" })
    #expect(layout.visibleGroups.count == 1)
    #expect(layout.visibleGroups[0].looks.isEmpty)
    #expect(layout.hiddenItems.map(\.mediaId) == ["look_1"])
}

@Test func clipLookTrayGroupingKeepsShotLookAndShotExportTopLevel() {
    // shot_look/shot_export carry a sourceMediaId that is a SHOT id, not a
    // media id — they keep their own top-level spot exactly like chain clips.
    let shotLook = trimTestMediaItem(id: "genlook_1", derivativeKind: "shot_look", sourceMediaId: "shot_1")
    let shotExport = trimTestMediaItem(id: "genexport_1", derivativeKind: "shot_export", sourceMediaId: "shot_1")
    let parent = trimTestMediaItem(id: "vid_1")

    let layout = videoTrayLayout(videos: [shotLook, shotExport, parent], isRejected: { _ in false })
    #expect(layout.visibleGroups.map(\.parent.mediaId) == ["genlook_1", "genexport_1", "vid_1"])
}

@Test func clipLookTrayGroupingCycleGuardDoesNotHang() {
    // Malformed data: two nested items pointing at each other. Both must
    // surface as their own top-level groups instead of hanging the climb.
    let lookA = trimTestMediaItem(id: "look_a", derivativeKind: "clip_look", sourceMediaId: "look_b")
    let lookB = trimTestMediaItem(id: "look_b", derivativeKind: "clip_look", sourceMediaId: "look_a")

    let layout = videoTrayLayout(videos: [lookA, lookB], isRejected: { _ in false })
    #expect(layout.visibleGroups.map(\.parent.mediaId) == ["look_a", "look_b"])
}
