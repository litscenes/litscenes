import SwiftUI

struct ShotRowVideoTile: Identifiable {
    var result: ShotSegmentPresentation
    var beforeEntryId = ""
    var afterEntryId = ""
    var replacesEntryId = ""
    var ordinal: Int
    var count: Int
    var id: String { result.id }
}

/// Input placements remain the drag/drop authority. Video tiles are a projection.
func shotRowVideoTiles(shot: ProjectShot, segments: [ShotRenderPlanSegment], work: ShotWorkPresentation) -> [ShotRowVideoTile] {
    var tiles: [ShotRowVideoTile] = []
    var seen: Set<String> = []
    let entryIds = Set(shot.entries.map(\.entryId))
    func append(_ result: ShotSegmentPresentation, start: String, end: String, ordinal: Int, count: Int) {
        guard seen.insert(result.id).inserted else { return }
        var tile = ShotRowVideoTile(result: result, ordinal: ordinal, count: count)
        if let entry = shot.entries.first(where: { $0.entryId == end }), entry.isAIExtension {
            tile.replacesEntryId = end
        } else if let entry = shot.entries.first(where: { $0.entryId == start }), entry.isClip, end.isEmpty {
            tile.replacesEntryId = start
        } else if entryIds.contains(end) {
            tile.beforeEntryId = end
        } else if entryIds.contains(start) {
            tile.afterEntryId = start
        } else {
            // An old whole-video source has no recoverable interior placements.
            // Keep it as one saved video instead of inventing missing segments.
            tile.beforeEntryId = shot.entries.first(where: { $0.isAIExtension })?.entryId ?? ""
        }
        tiles.append(tile)
    }
    for (index, segment) in segments.enumerated() {
        let source = ShotSegmentPresentation(shot: shot, segment: segment)
        let result = source.withProgress(work.segment(source.id), shot: shot)
        guard result.preview != nil || result.record != nil || result.progress != nil else { continue }
        let clip = result.clip
        let identity = shotWorkflowSegment(segment, count: segments.count)
        append(result, start: identity?.startEntryId ?? clip?.placementStartEntryId ?? "",
            end: identity?.endEntryId ?? clip?.placementEndEntryId ?? "", ordinal: index + 1, count: segments.count)
    }
    for entry in shot.entries where !entry.isSkipped {
        guard let record = shot.continuationRecord(entryId: entry.entryId) else { continue }
        let source = ShotSegmentPresentation(record: record)
        guard !seen.contains(source.id), record.selectedTake != nil else { continue }
        let result = source.withProgress(work.segment(source.id), shot: shot)
        append(result, start: record.sourceEntryId, end: record.entryId,
            ordinal: tiles.count + 1, count: max(segments.count, tiles.count + 1))
    }
    // Narration and missing generation inputs must not hide a confirmed attempt.
    for progress in work.segments where !seen.contains(progress.placementKey)
        && (entryIds.contains(progress.startEntryId) || entryIds.contains(progress.endEntryId)) {
        let record = shot.continuationRecord(entryId: progress.endEntryId)
        let result = ShotSegmentPresentation(id: progress.placementKey, title: progress.title,
            preview: record?.selectedTake?.segmentClip.map { ShotSegmentPreview(clip: $0) }, record: record)
            .withProgress(progress, shot: shot)
        append(result, start: progress.startEntryId, end: progress.endEntryId,
            ordinal: progress.ordinal, count: progress.segmentCount)
    }
    if !tiles.contains(where: { $0.result.preview != nil }), let artifact = shot.playableRenderVersion,
       !artifact.videoPath.isEmpty {
        let result = ShotSegmentPresentation(id: shotArtifactSegmentKey(versionId: artifact.versionId),
            title: "Saved Shot", preview: ShotSegmentPreview(clip: ShotRenderSegmentClip(
                clipPath: artifact.videoPath, provider: artifact.provider, model: artifact.model,
                durationSeconds: Double(artifact.totalSeconds))))
        append(result, start: "", end: "", ordinal: 1, count: max(segments.count, 1))
    }
    return tiles
}

struct ShotSegmentLoadingThumbnail: View {
    let progress: WorkflowSegmentProgress
    var body: some View {
        VStack(spacing: 7) {
            if progress.stage.isWorking { ProgressView().controlSize(.small) }
            else { Image(systemName: progress.stage == .queued ? "clock" : "exclamationmark.circle") }
            Text(progress.stage.label.uppercased())
                .font(CanonType.archive(8, weight: .bold)).tracking(0.6)
            Text("SEGMENT \(progress.ordinal) OF \(progress.segmentCount)"
                + (progress.takeNumber.map { " · TAKE \($0)" } ?? ""))
                .font(CanonType.archive(7, weight: .semibold))
            if !progress.model.isEmpty {
                Text("\(progress.model) · \(Int(progress.durationSeconds.rounded()))s")
                    .font(CanonType.interface(9)).lineLimit(1)
            }
        }
        .foregroundStyle(progress.stage == .failed ? CanonColor.rust : PlateColor.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PlateColor.creamDeep)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(PlateColor.hairline,
            style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        .accessibilityElement(children: .combine)
    }
}

struct ShotSegmentStatusThumbnail: View {
    let result: ShotSegmentPresentation
    var width: CGFloat = 196
    var height: CGFloat = 110
    var body: some View {
        Group {
            if let progress = result.progress, progress.stage != .saved {
                ShotSegmentLoadingThumbnail(progress: progress)
            } else {
                ShotSegmentVideoThumbnail(preview: result.preview, width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
