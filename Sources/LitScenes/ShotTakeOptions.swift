import Foundation

// MARK: - Take options
//
// The one shape both take universes present to the player and the segment
// cards: ordinary placements derive theirs from the render history
// (`shotSegmentTakes`), continuation markers from their record. USE routes
// back to the owning law through `source`, so the view never decides which
// ledger a pick belongs to.

enum ShotTakeStatus: Hashable, Sendable {
    case ready
    case rendering
    case failed
    case fileMissing
}

struct ShotTakeOption: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case render(versionId: String)
        case continuation(entryId: String, takeId: String)
    }

    var placementKey: String
    var takeNumber: Int
    var clip: ShotRenderSegmentClip?
    var prompt: String
    var modelLabel: String
    var durationSeconds: Double
    var status: ShotTakeStatus
    var isInFilm: Bool
    var source: Source

    var id: String { "\(placementKey)#\(takeNumber)" }
    var isReady: Bool { status == .ready && clip != nil }
    var clipPath: String { clip?.clipPath ?? "" }

    /// "TAKE 2 · HAILUO 3 MAX · 5.2s" — the thumb caption.
    var caption: String {
        var parts = ["TAKE \(takeNumber)"]
        if !modelLabel.isEmpty { parts.append(modelLabel.uppercased()) }
        switch status {
        case .ready:
            if durationSeconds > 0 { parts.append(String(format: "%.1fs", durationSeconds)) }
        case .rendering: parts.append("RENDERING")
        case .failed: parts.append("FAILED")
        case .fileMissing: parts.append("VIDEO FILE UNAVAILABLE")
        }
        return parts.joined(separator: " · ")
    }
}

/// A CivitAI clip is best named by its recipe; everything else by the label law.
func shotTakeModelLabel(clip: ShotRenderSegmentClip) -> String {
    clip.civitaiRecipe?.label ?? shotClipModelShortLabel(provider: clip.provider, model: clip.model)
}

private func shotTakeDuration(_ clip: ShotRenderSegmentClip) -> Double {
    clip.durationSeconds > 0 ? clip.durationSeconds : Double(clip.requestedDurationSeconds)
}

/// The takes behind a plan segment. Footage, preserved and whole-file
/// fallbacks have none; a continuation placement answers with its record.
func shotTakeOptions(
    shot: ProjectShot,
    segment: ShotRenderPlanSegment,
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> [ShotTakeOption] {
    guard case .generated(let item) = segment else { return [] }
    if let record = shot.continuationRecord(entryId: item.pair.endPlacementEntryId) {
        return shotTakeOptions(record: record, placementKey: item.pair.placementKey, fileExists: fileExists)
    }
    let inFilm = shotSavedSegmentClip(shot: shot, pair: item.pair)?.clipPath ?? ""
    return shotSegmentTakes(shot: shot, pair: item.pair, fileExists: fileExists).map { take in
        ShotTakeOption(
            placementKey: item.pair.placementKey,
            takeNumber: take.takeNumber,
            clip: take.clip,
            prompt: take.clip.prompt,
            modelLabel: shotTakeModelLabel(clip: take.clip),
            durationSeconds: shotTakeDuration(take.clip),
            status: take.fileExists ? .ready : .fileMissing,
            isInFilm: !inFilm.isEmpty && take.clip.clipPath == inFilm,
            source: .render(versionId: take.originVersionId)
        )
    }
}

/// A continuation record's takes as options. Failed attempts stay out of the
/// strip — the card's own caption already reports the last failed attempt —
/// while queued and generating ones hold their place.
func shotTakeOptions(
    record: ShotContinuationRecord,
    placementKey: String,
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> [ShotTakeOption] {
    record.sortedTakes.compactMap { take in
        let status: ShotTakeStatus
        switch take.takeStatus {
        case .ready:
            guard let clip = take.segmentClip, !clip.clipPath.isEmpty else { return nil }
            status = fileExists(clip.clipPath) ? .ready : .fileMissing
        case .queued, .generating:
            status = .rendering
        default:
            return nil
        }
        return ShotTakeOption(
            placementKey: placementKey,
            takeNumber: take.takeNumber,
            clip: take.segmentClip,
            prompt: take.prompt,
            modelLabel: take.segmentClip.map(shotTakeModelLabel) ?? take.renderStack.shortLabel,
            durationSeconds: take.segmentClip.map(shotTakeDuration) ?? Double(take.renderStack.segmentSeconds),
            status: status,
            isInFilm: take.takeId == record.selectedTakeId,
            source: .continuation(entryId: record.entryId, takeId: take.takeId)
        )
    }
}

func shotInFilmTake(_ options: [ShotTakeOption]) -> ShotTakeOption? {
    options.first { $0.isInFilm }
}

/// The neighboring ready take in strip order, clamped at the ends; nil when
/// the step lands nowhere new.
func shotSteppedTake(options: [ShotTakeOption], currentId: String, delta: Int) -> ShotTakeOption? {
    let ready = options.filter(\.isReady)
    guard !ready.isEmpty else { return nil }
    guard let index = ready.firstIndex(where: { $0.id == currentId }) else {
        return delta >= 0 ? ready.first : ready.last
    }
    let next = min(max(index + delta, 0), ready.count - 1)
    return next == index ? nil : ready[next]
}

/// Compare loops on the longer take; the shorter holds its last frame until
/// the leader wraps and both restart together.
func shotCompareLoopLeaderIsLeft(leftSeconds: Double, rightSeconds: Double) -> Bool {
    leftSeconds >= rightSeconds
}

// MARK: - What the player is looking at

/// Carried inside `ShotSegmentPreview` so the player knows WHAT it previews
/// — which segment, which take, whether that take is in the film — and a
/// whole-shot render file carries its own artifact placement key instead of
/// masquerading as a segment.
struct ShotTakePreviewContext: Hashable, Sendable {
    var placementKey: String
    /// "SEGMENT 1" or "RENDER II · WHOLE-SHOT FILE".
    var label: String
    /// 0 for a whole-shot file.
    var takeNumber: Int
    var takeCount: Int
    var isInFilm: Bool
    var source: ShotTakeOption.Source?
}

struct ShotTakeCompare: Hashable, Sendable {
    var left: ShotTakeOption
    var right: ShotTakeOption
    var placementKey: String
    var segmentLabel: String
}

enum ShotPlayerViewingSelection: Hashable {
    case current
    case segment(ShotSegmentPreview)
    case compare(ShotTakeCompare)
}

func shotTakeChipTitle(_ context: ShotTakePreviewContext) -> String {
    guard context.takeNumber > 0 else { return context.label }
    return "\(context.label) · TAKE \(context.takeNumber) OF \(max(context.takeCount, context.takeNumber)) · \(context.isInFilm ? "IN FILM" : "NOT IN FILM")"
}

func shotCompareChipTitle(_ compare: ShotTakeCompare) -> String {
    "COMPARE · \(compare.segmentLabel) · TAKE \(compare.left.takeNumber) vs TAKE \(compare.right.takeNumber) · PICTURE ONLY"
}

/// The footer's one-line account of the preview: what plays and how long.
func shotTakeFooterLabel(context: ShotTakePreviewContext?, compare: ShotTakeCompare?, seconds: Double) -> String {
    if let compare {
        return "COMPARE · TAKE \(compare.left.takeNumber) vs TAKE \(compare.right.takeNumber)"
    }
    let rounded = "~\(Int(seconds.rounded()))s"
    guard let context else { return "SEGMENT · \(rounded)" }
    guard context.takeNumber > 0 else { return "\(context.label) · \(rounded)" }
    return "\(context.label) · TAKE \(context.takeNumber) OF \(max(context.takeCount, context.takeNumber)) · \(rounded)"
}
