import Foundation

// MARK: - Trim range

/// A user's in/out selection over a source video, in seconds from the asset start.
struct VideoTrimRange: Hashable {
    /// Anything shorter can't survive the exporter's own clamping (extractTimeRange
    /// floors durations to 0.1s) and reads as a mis-drag rather than an intent.
    static let minimumTrimSeconds: Double = 0.5

    var startSeconds: Double
    var endSeconds: Double

    var durationSeconds: Double {
        max(0, endSeconds - startSeconds)
    }

    var isSaveable: Bool {
        durationSeconds >= Self.minimumTrimSeconds
    }

    /// Normalizes arbitrary handle positions into a valid range: reorders an
    /// inverted selection, clamps both ends into [0, videoDuration].
    static func clamped(start: Double, end: Double, videoDurationSeconds: Double) -> VideoTrimRange {
        let duration = max(videoDurationSeconds, 0)
        let low = min(start, end)
        let high = max(start, end)
        return VideoTrimRange(
            startSeconds: min(max(low, 0), duration),
            endSeconds: min(max(high, 0), duration)
        )
    }
}

/// Deterministic per-(parent, range) id: re-saving the identical selection
/// replaces the same asset instead of stacking duplicates.
func videoTrimMediaId(parentMediaId: String, range: VideoTrimRange) -> String {
    let key = "\(parentMediaId)|\(String(format: "%.3f", range.startSeconds))|\(String(format: "%.3f", range.endSeconds))"
    return "trim_\(shortHash(key, length: 20))"
}

/// Filesystem-safe trim filename: parent basename slug + in/out timecode slugs.
/// (Timecode format mirrors the store's frame filenames: 00m04s / 01h02m03s.)
func videoTrimFilename(parentFilename: String, range: VideoTrimRange) -> String {
    let baseName = URL(fileURLWithPath: parentFilename).deletingPathExtension().lastPathComponent
    let slug = stableSlug(baseName, fallback: "video")
    return "\(slug)_trim_\(videoTrimTimecodeSlug(range.startSeconds))-\(videoTrimTimecodeSlug(range.endSeconds)).mp4"
}

/// Display-only label, e.g. "0:04 – 0:12 · 8.5s".
func videoTrimDisplayLabel(range: VideoTrimRange) -> String {
    let seconds = (range.durationSeconds * 10).rounded() / 10
    let duration = seconds == seconds.rounded()
        ? "\(Int(seconds))s"
        : String(format: "%.1fs", seconds)
    return "\(videoTrimTimestampLabel(range.startSeconds)) – \(videoTrimTimestampLabel(range.endSeconds)) · \(duration)"
}

/// Playhead readout with tenths, e.g. "0:09.4" — frame-nav precision for the
/// Studio's scrubber.
func videoTrimPlayheadLabel(_ seconds: Double) -> String {
    let clamped = max(seconds, 0)
    var whole = Int(clamped)
    var tenths = Int(((clamped - Double(whole)) * 10).rounded())
    if tenths == 10 {
        whole += 1
        tenths = 0
    }
    let hours = whole / 3600
    let minutes = (whole % 3600) / 60
    let remainder = whole % 60
    let base = hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
        : String(format: "%d:%02d", minutes, remainder)
    return "\(base).\(tenths)"
}

func videoTrimTimestampLabel(_ seconds: Double) -> String {
    let wholeSeconds = max(0, Int(seconds.rounded()))
    let hours = wholeSeconds / 3600
    let minutes = (wholeSeconds % 3600) / 60
    let remainder = wholeSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, remainder)
    }
    return String(format: "%d:%02d", minutes, remainder)
}

private func videoTrimTimecodeSlug(_ seconds: Double) -> String {
    let wholeSeconds = max(0, Int(seconds.rounded()))
    let hours = wholeSeconds / 3600
    let minutes = (wholeSeconds % 3600) / 60
    let remainder = wholeSeconds % 60
    if hours > 0 {
        return String(format: "%02dh%02dm%02ds", hours, minutes, remainder)
    }
    return String(format: "%02dm%02ds", minutes, remainder)
}

// MARK: - Video Sources tray layout

/// One visible tray group: a top-level video with its nested trims and looks.
struct VideoTrayGroup: Identifiable {
    var parent: MediaItemRecord
    var trims: [MediaItemRecord]
    var looks: [MediaItemRecord] = []

    var id: String { parent.mediaId }
}

struct VideoTrayLayout {
    var visibleGroups: [VideoTrayGroup]
    var hiddenItems: [MediaItemRecord]
}

/// Pure grouping over pre-sorted video-kind items. Top-level = every non-hidden
/// video that is neither a trim nor a clip look (video-chain clips/reels and
/// shot exports keep their top-level spot). Trims and clip looks nest under
/// their visible ANCHOR, sorted by start offset: a trim's anchor is its parent;
/// a clip look climbs the sourceMediaId chain through nested items (a look of a
/// trim lands in the trim's parent group), so a group shows the source video
/// with everything cut or restyled from it. A nested item whose anchor is
/// missing or hidden surfaces as its own top-level group. Hidden = every
/// rejected video.
func videoTrayLayout(
    videos: [MediaItemRecord],
    isRejected: (MediaItemRecord) -> Bool
) -> VideoTrayLayout {
    var hiddenItems: [MediaItemRecord] = []
    var topLevel: [MediaItemRecord] = []
    var trimsByAnchor: [String: [MediaItemRecord]] = [:]
    var looksByAnchor: [String: [MediaItemRecord]] = [:]
    var orphans: [MediaItemRecord] = []

    let videosById = Dictionary(videos.map { ($0.mediaId, $0) }, uniquingKeysWith: { first, _ in first })
    func isNested(_ item: MediaItemRecord) -> Bool { item.isVideoTrim || item.isClipLookMedia }
    let visibleAnchorIds = Set(
        videos
            .filter { !isNested($0) && !isRejected($0) }
            .map(\.mediaId)
    )

    /// Climbs sourceMediaId through nested items to the top-level anchor;
    /// bounded by a seen-set so a malformed cycle cannot hang the tray.
    func anchorId(for item: MediaItemRecord) -> String? {
        var cursorId = item.sourceMediaId
        var seen: Set<String> = [item.mediaId]
        while let id = cursorId, !seen.contains(id) {
            seen.insert(id)
            guard let candidate = videosById[id], isNested(candidate) else { return id }
            cursorId = candidate.sourceMediaId
        }
        return nil
    }

    for video in videos {
        if isRejected(video) {
            hiddenItems.append(video)
            continue
        }
        guard isNested(video) else {
            topLevel.append(video)
            continue
        }
        if let anchor = anchorId(for: video), visibleAnchorIds.contains(anchor) {
            if video.isVideoTrim {
                trimsByAnchor[anchor, default: []].append(video)
            } else {
                looksByAnchor[anchor, default: []].append(video)
            }
        } else {
            orphans.append(video)
        }
    }

    let byStartOffset: (MediaItemRecord, MediaItemRecord) -> Bool = {
        ($0.sourceTimestampSeconds ?? 0) < ($1.sourceTimestampSeconds ?? 0)
    }
    var groups = topLevel.map { parent in
        VideoTrayGroup(
            parent: parent,
            trims: (trimsByAnchor[parent.mediaId] ?? []).sorted(by: byStartOffset),
            looks: (looksByAnchor[parent.mediaId] ?? []).sorted(by: byStartOffset)
        )
    }
    groups.append(contentsOf: orphans.map { VideoTrayGroup(parent: $0, trims: []) })
    return VideoTrayLayout(visibleGroups: groups, hiddenItems: hiddenItems)
}
