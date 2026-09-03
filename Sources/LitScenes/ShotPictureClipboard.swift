import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - The picture-segment clipboard (mirrors ShotAudioClipboard)

/// THE PICTURE CLIPBOARD: copy/paste for picture spans rides the SYSTEM
/// pasteboard under a custom type — it survives sheets, window churn, and
/// relaunch. The payload is tolerant JSON like every persisted document.
///
/// WYSIWYG COPY LAW: a copy captures the ordered kept material spans under
/// the selection — what you see is what rides the clipboard. A cross-seam
/// selection is simply several spans; skipped and razored-out material is
/// never captured.
extension NSPasteboard.PasteboardType {
    static let litScenesShotPictureSegment =
        NSPasteboard.PasteboardType("com.litscenes.shot-picture-segment")
}

/// One copied span: the Law-2 source tuple plus the modifiers it was showing
/// when copied (copying an arranged copy carries its rate and mute).
struct ShotPictureSegmentSpanRef: Codable, Hashable, Sendable {
    var segmentKey: String = ""
    /// Absolute file path (take file or footage file) — resolve by path
    /// first, the audio-region law.
    var clipPath: String = ""
    /// Footage only; "" on generated spans.
    var mediaId: String = ""
    var startSeconds: Double = 0
    var endSeconds: Double = 0
    var playbackRate: Double = 1
    var muteSourceAudio: Bool = false
    /// The band label at copy time — status lines only, never identity.
    var label: String = ""
    /// SEGMENT CARD fields (the Re-render panel's Copy): a span that carries
    /// its keyframe PAIR travels structurally — cross-shot paste lands it as
    /// first-class material (entries + overrides + seed take) instead of an
    /// arranged copy. Empty on plain strip-span copies.
    var startFrameImageId: String = ""
    var endFrameImageId: String = ""
    /// The card's EDITED prompt ("" = the generated prompt suffices).
    var promptOverride: String = ""
    /// The card's per-segment render stack ("" = the target shot's default).
    var renderStackRaw: String = ""
    /// The rendered take, carried whole so the target keeps full AS RENDERED
    /// provenance (the combined-CUT seed law). nil = unrendered card.
    var seedClip: ShotRenderSegmentClip? = nil
    /// NARRATION CARRY (segment cards only): the slice of the source shot's
    /// narration audible over this segment's output window, captured at COPY
    /// time so the clipboard stays self-contained. Empty path = nothing to
    /// carry (no ready narration, or it ends before this segment).
    var narrationPath: String = ""
    /// In-point into the narration file (output seconds minus the narration
    /// lane's start offset in the SOURCE shot).
    var narrationSourceStartSeconds: Double = 0
    var narrationSliceSeconds: Double = 0
    /// Where within the segment the audible part begins (0 unless the
    /// narration started mid-segment in the source).
    var narrationOffsetIntoSegmentSeconds: Double = 0
    var narrationLabel: String = ""

    var seconds: Double { max(endSeconds - startSeconds, 0) }
    var isFootage: Bool { !mediaId.trimmed.isEmpty }
    var isSegmentCard: Bool {
        !startFrameImageId.trimmed.isEmpty && !endFrameImageId.trimmed.isEmpty
    }
    var carriesNarration: Bool {
        !narrationPath.trimmed.isEmpty && narrationSliceSeconds > 0.05
    }

    private enum CodingKeys: String, CodingKey {
        case segmentKey, clipPath, mediaId, startSeconds, endSeconds
        case playbackRate, muteSourceAudio, label
        case startFrameImageId, endFrameImageId
        case promptOverride, renderStackRaw, seedClip
        case narrationPath, narrationSourceStartSeconds
        case narrationSliceSeconds, narrationOffsetIntoSegmentSeconds
        case narrationLabel
    }

    init(
        segmentKey: String = "",
        clipPath: String = "",
        mediaId: String = "",
        startSeconds: Double = 0,
        endSeconds: Double = 0,
        playbackRate: Double = 1,
        muteSourceAudio: Bool = false,
        label: String = "",
        startFrameImageId: String = "",
        endFrameImageId: String = "",
        promptOverride: String = "",
        renderStackRaw: String = "",
        seedClip: ShotRenderSegmentClip? = nil,
        narrationPath: String = "",
        narrationSourceStartSeconds: Double = 0,
        narrationSliceSeconds: Double = 0,
        narrationOffsetIntoSegmentSeconds: Double = 0,
        narrationLabel: String = ""
    ) {
        self.segmentKey = segmentKey
        self.clipPath = clipPath
        self.mediaId = mediaId
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.playbackRate = playbackRate
        self.muteSourceAudio = muteSourceAudio
        self.label = label
        self.startFrameImageId = startFrameImageId
        self.endFrameImageId = endFrameImageId
        self.promptOverride = promptOverride
        self.renderStackRaw = renderStackRaw
        self.seedClip = seedClip
        self.narrationPath = narrationPath
        self.narrationSourceStartSeconds = narrationSourceStartSeconds
        self.narrationSliceSeconds = narrationSliceSeconds
        self.narrationOffsetIntoSegmentSeconds = narrationOffsetIntoSegmentSeconds
        self.narrationLabel = narrationLabel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        segmentKey = try container.decodeIfPresent(String.self, forKey: .segmentKey) ?? ""
        clipPath = try container.decodeIfPresent(String.self, forKey: .clipPath) ?? ""
        mediaId = try container.decodeIfPresent(String.self, forKey: .mediaId) ?? ""
        startSeconds = try container.decodeIfPresent(Double.self, forKey: .startSeconds) ?? 0
        endSeconds = try container.decodeIfPresent(Double.self, forKey: .endSeconds) ?? 0
        playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate) ?? 1
        muteSourceAudio = try container.decodeIfPresent(Bool.self, forKey: .muteSourceAudio) ?? false
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        startFrameImageId = try container.decodeIfPresent(String.self, forKey: .startFrameImageId) ?? ""
        endFrameImageId = try container.decodeIfPresent(String.self, forKey: .endFrameImageId) ?? ""
        promptOverride = try container.decodeIfPresent(String.self, forKey: .promptOverride) ?? ""
        renderStackRaw = try container.decodeIfPresent(String.self, forKey: .renderStackRaw) ?? ""
        seedClip = (try? container.decodeIfPresent(ShotRenderSegmentClip.self, forKey: .seedClip)) ?? nil
        narrationPath = try container.decodeIfPresent(String.self, forKey: .narrationPath) ?? ""
        narrationSourceStartSeconds = try container.decodeIfPresent(Double.self, forKey: .narrationSourceStartSeconds) ?? 0
        narrationSliceSeconds = try container.decodeIfPresent(Double.self, forKey: .narrationSliceSeconds) ?? 0
        narrationOffsetIntoSegmentSeconds = try container.decodeIfPresent(Double.self, forKey: .narrationOffsetIntoSegmentSeconds) ?? 0
        narrationLabel = try container.decodeIfPresent(String.self, forKey: .narrationLabel) ?? ""
    }
}

/// What a future planner needs to propose a transform for the copied span —
/// derived at copy time, read-only, never persisted anywhere but the
/// pasteboard. All fields optional-tolerant; an empty context is legal.
struct ShotSegmentContext: Codable, Hashable, Sendable {
    var authoredPrompt: String = ""
    var lookSummary: String = ""
    var castNames: [String] = []
    var clipFilename: String = ""
    var previousSegmentLabel: String = ""
    var nextSegmentLabel: String = ""
    var copiedAt: String = ""

    private enum CodingKeys: String, CodingKey {
        case authoredPrompt, lookSummary, castNames, clipFilename
        case previousSegmentLabel, nextSegmentLabel, copiedAt
    }

    init(
        authoredPrompt: String = "",
        lookSummary: String = "",
        castNames: [String] = [],
        clipFilename: String = "",
        previousSegmentLabel: String = "",
        nextSegmentLabel: String = "",
        copiedAt: String = ""
    ) {
        self.authoredPrompt = authoredPrompt
        self.lookSummary = lookSummary
        self.castNames = castNames
        self.clipFilename = clipFilename
        self.previousSegmentLabel = previousSegmentLabel
        self.nextSegmentLabel = nextSegmentLabel
        self.copiedAt = copiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authoredPrompt = try container.decodeIfPresent(String.self, forKey: .authoredPrompt) ?? ""
        lookSummary = try container.decodeIfPresent(String.self, forKey: .lookSummary) ?? ""
        castNames = ((try? container.decodeIfPresent([String].self, forKey: .castNames)) ?? nil) ?? []
        clipFilename = try container.decodeIfPresent(String.self, forKey: .clipFilename) ?? ""
        previousSegmentLabel = try container.decodeIfPresent(String.self, forKey: .previousSegmentLabel) ?? ""
        nextSegmentLabel = try container.decodeIfPresent(String.self, forKey: .nextSegmentLabel) ?? ""
        copiedAt = try container.decodeIfPresent(String.self, forKey: .copiedAt) ?? ""
    }
}

struct ShotPictureSegmentClipboardPayload: Codable, Hashable, Sendable {
    var version: Int = 1
    var spans: [ShotPictureSegmentSpanRef] = []
    var sourceShotId: String = ""
    var sourceProjectId: String = ""
    var context: ShotSegmentContext? = nil

    private enum CodingKeys: String, CodingKey {
        case version, spans, sourceShotId, sourceProjectId, context
    }

    init(
        version: Int = 1,
        spans: [ShotPictureSegmentSpanRef] = [],
        sourceShotId: String = "",
        sourceProjectId: String = "",
        context: ShotSegmentContext? = nil
    ) {
        self.version = version
        self.spans = spans
        self.sourceShotId = sourceShotId
        self.sourceProjectId = sourceProjectId
        self.context = context
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        spans = ((try? container.decodeIfPresent([ShotPictureSegmentSpanRef].self, forKey: .spans)) ?? nil) ?? []
        sourceShotId = try container.decodeIfPresent(String.self, forKey: .sourceShotId) ?? ""
        sourceProjectId = try container.decodeIfPresent(String.self, forKey: .sourceProjectId) ?? ""
        context = (try? container.decodeIfPresent(ShotSegmentContext.self, forKey: .context)) ?? nil
    }

    /// A payload worth pasting: at least one span naming media with real
    /// duration — or a segment card, which is structural (its frames are the
    /// material; an unrendered card is legal and pastes render-ready).
    /// Anything else reads as an empty clipboard.
    var isPasteable: Bool {
        spans.contains {
            $0.isSegmentCard
                || ((!$0.clipPath.trimmed.isEmpty || !$0.mediaId.trimmed.isEmpty)
                    && $0.seconds >= ShotCutList.minimumRangeSeconds)
        }
    }

    var totalSeconds: Double { spans.reduce(0) { $0 + $1.seconds } }
}

enum ShotPictureClipboard {
    /// Declared in code (this app is the only reader), identifier
    /// byte-identical to the pasteboard type's raw string, so provider-written
    /// and directly-written payloads read back through the same `read()`.
    static let utType = UTType(exportedAs: "com.litscenes.shot-picture-segment")

    /// Menu-enablement providers only — paste reads the pasteboard directly
    /// (the audio clipboard's live-verified pattern; the provider WRITE path
    /// is a still-open trap and nothing depends on it).
    static func itemProviders(for payload: ShotPictureSegmentClipboardPayload) -> [NSItemProvider] {
        guard let data = try? JSONEncoder().encode(payload) else { return [] }
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: utType.identifier,
            visibility: .all
        ) { completion in
            completion(data, nil)
            return nil
        }
        return [provider]
    }

    static func write(_ payload: ShotPictureSegmentClipboardPayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .litScenesShotPictureSegment)
    }

    static func read() -> ShotPictureSegmentClipboardPayload? {
        guard let data = NSPasteboard.general.data(forType: .litScenesShotPictureSegment),
              let payload = try? JSONDecoder().decode(
                  ShotPictureSegmentClipboardPayload.self,
                  from: data
              ),
              payload.isPasteable else { return nil }
        return payload
    }

    static var hasPayload: Bool {
        NSPasteboard.general.availableType(from: [.litScenesShotPictureSegment]) != nil
    }
}

// MARK: - Paste rungs (legality, refusals honest)

/// nil = paste allowed; otherwise the exact status line the operator reads.
/// Rungs: same shot ⇒ full fidelity. Different shot ⇒ generated spans refuse
/// (their takes belong to their shot's retention; Send to Footage is the
/// carrier), footage spans are file-level and allowed. Cross-project ⇒
/// refused outright.
func shotPictureClipboardPasteRefusal(
    payload: ShotPictureSegmentClipboardPayload,
    targetShotId: String,
    targetProjectId: String
) -> String? {
    guard payload.isPasteable else { return "Nothing on the picture clipboard" }
    if !payload.sourceProjectId.isEmpty, payload.sourceProjectId != targetProjectId {
        return "Picture segments paste only inside their own project"
    }
    // Segment cards travel cross-shot structurally; footage is file-level.
    // Only a plain generated strip-span is shot-bound.
    if payload.sourceShotId != targetShotId,
       payload.spans.contains(where: { !$0.isFootage && !$0.isSegmentCard }) {
        return "Generated spans paste only into their own shot — Copy the segment card (Re-render panel) to carry the whole segment, or Send to Footage"
    }
    return nil
}

// MARK: - Structural paste (segment cards → another CUT row)

/// THE STRUCTURAL PASTE LAW: a copied segment card lands in a CUT as
/// first-class material —
/// - its keyframe PAIR becomes two new entries (frames are project-level, so
///   the pair re-forms under new placement ids),
/// - every boundary seam is a HARD CUT (a paste must never imply a bridge
///   render: the pasted pair's own seam stays auto and is the segment),
/// - the edited prompt and per-segment stack re-key onto the new placement,
/// - the rendered take rides in as a combined-CUT-style SEED CLIP with its
///   provenance intact, so the segment plays immediately at $0 and re-renders
///   locally later.
/// Pure; nil when nothing structural is in `cards`. The engine wraps this in
/// the freeze law and the one picture-edit transaction.
func shotAppendingSegmentCards(
    _ shot: ProjectShot,
    cards: [ShotPictureSegmentSpanRef],
    afterEntryId: String?,
    fileExists: (String) -> Bool,
    now: String
) -> ProjectShot? {
    let structural = cards.filter(\.isSegmentCard)
    guard !structural.isEmpty else { return nil }
    var value = shot
    var insertIndex = value.entries.count
    if let afterEntryId,
       let index = value.entries.firstIndex(where: { $0.entryId == afterEntryId }) {
        insertIndex = index + 1
    }
    // The entry that will FOLLOW the pasted block must lead with a hard cut,
    // or the paste implies a new bridge render against the last pasted frame.
    if value.entries.indices.contains(insertIndex),
       value.entries[insertIndex].leadSeamPreference != .cut {
        value.entries[insertIndex].leadTransition = ShotSeamStyle.cut.rawValue
    }
    var block: [ShotFrameEntry] = []
    for card in structural {
        let startEntryId = "entry_\(shortHash("\(shot.shotId):paste:\(card.startFrameImageId):\(now):\(UUID().uuidString)", length: 12))"
        let endEntryId = "entry_\(shortHash("\(shot.shotId):paste:\(card.endFrameImageId):\(now):\(UUID().uuidString)", length: 12))"
        var start = ShotFrameEntry(entryId: startEntryId, frameImageId: card.startFrameImageId.trimmed)
        // Boundary law: each card cuts against whatever precedes it.
        start.leadTransition = ShotSeamStyle.cut.rawValue
        let end = ShotFrameEntry(entryId: endEntryId, frameImageId: card.endFrameImageId.trimmed)
        block.append(start)
        block.append(end)
        let prompt = card.promptOverride.trimmed
        if !prompt.isEmpty {
            value.segmentPromptOverrides.append(ShotSegmentPromptOverride(
                startFrameImageId: card.startFrameImageId.trimmed,
                endFrameImageId: card.endFrameImageId.trimmed,
                placementStartEntryId: startEntryId,
                placementEndEntryId: endEntryId,
                prompt: prompt,
                updatedAt: now
            ))
        }
        if !card.renderStackRaw.isEmpty, ShotRenderStack(rawValue: card.renderStackRaw) != nil {
            value.segmentRenderOverrides.append(ShotSegmentRenderOverride(
                startFrameImageId: card.startFrameImageId.trimmed,
                endFrameImageId: card.endFrameImageId.trimmed,
                placementStartEntryId: startEntryId,
                placementEndEntryId: endEntryId,
                stack: card.renderStackRaw,
                updatedAt: now
            ))
        }
        if var seed = card.seedClip,
           !seed.clipPath.trimmed.isEmpty,
           fileExists(seed.clipPath) {
            seed.startFrameImageId = card.startFrameImageId.trimmed
            seed.endFrameImageId = card.endFrameImageId.trimmed
            seed.placementStartEntryId = startEntryId
            seed.placementEndEntryId = endEntryId
            seed.updatedAt = now
            value.seedSegmentClips.append(seed.normalized())
        }
    }
    value.entries.insert(contentsOf: block, at: insertIndex)
    value.updatedAt = now
    return value
}

// MARK: - Narration carry (the sentence travels with its picture)

/// Provenance for a narration slice carried by a cross-cut segment paste.
/// CLIP lane only — `settingNarrationArtifact` owns the single
/// `active_narration` region and clobbers/deletes it on artifact writes, so
/// a carried slice on the narration lane would not survive the target shot's
/// own narration lifecycle.
let shotCarriedNarrationProvenance = "carried_narration"

/// The audible window of a narration over one segment's output span — pure
/// interval math, captured at COPY time so the clipboard stays
/// self-contained.
struct ShotNarrationCarrySlice: Equatable {
    /// In-point into the narration audio file.
    var sourceStartSeconds: Double
    var sliceSeconds: Double
    /// Where within the segment the audible part begins (a narration that
    /// starts mid-segment lands offset, never stretched).
    var offsetIntoSegmentSeconds: Double
}

func shotNarrationCarrySlice(
    narrationStartSeconds: Double,
    narrationDurationSeconds: Double,
    segmentOutputStartSeconds: Double,
    segmentDurationSeconds: Double
) -> ShotNarrationCarrySlice? {
    guard narrationDurationSeconds > 0, segmentDurationSeconds > 0 else { return nil }
    let overlapStart = max(segmentOutputStartSeconds, narrationStartSeconds)
    let overlapEnd = min(
        segmentOutputStartSeconds + segmentDurationSeconds,
        narrationStartSeconds + narrationDurationSeconds
    )
    let slice = overlapEnd - overlapStart
    guard slice > 0.05 else { return nil }
    return ShotNarrationCarrySlice(
        sourceStartSeconds: max(overlapStart - narrationStartSeconds, 0),
        sliceSeconds: slice,
        offsetIntoSegmentSeconds: max(overlapStart - segmentOutputStartSeconds, 0)
    )
}

/// Paste-time mint: the carried slice as a CLIP-lane region at the pasted
/// segment's output position, BORN AUDIBLE (a muted carry would re-create
/// the "narration didn't come over" complaint the feature answers). No file
/// slicing — `sourceStartSeconds` + `durationSeconds` ARE the slice, honored
/// natively by the region composition.
func shotCarriedNarrationRegion(
    card: ShotPictureSegmentSpanRef,
    targetSegmentOutputStartSeconds: Double,
    sourceCutId: String,
    regionId: String
) -> ShotAudioRegion? {
    guard card.carriesNarration else { return nil }
    return ShotAudioRegion(
        regionId: regionId,
        laneId: ShotAudioLaneId.clip,
        label: card.narrationLabel.trimmed.nilIfEmpty ?? "Carried narration",
        path: card.narrationPath,
        sourceCutId: sourceCutId,
        provenance: shotCarriedNarrationProvenance,
        startSeconds: targetSegmentOutputStartSeconds + max(card.narrationOffsetIntoSegmentSeconds, 0),
        sourceStartSeconds: card.narrationSourceStartSeconds,
        durationSeconds: card.narrationSliceSeconds
    )
}

// MARK: - The paste pipeline (the LLM seam)

/// Where a paste lands: a segment key + clip-local seconds, exactly the
/// soft-anchor law.
struct ShotSegmentPasteAnchor: Codable, Hashable, Sendable {
    var segmentKey: String = ""
    var anchorSeconds: Double = 0

    private enum CodingKeys: String, CodingKey {
        case segmentKey, anchorSeconds
    }

    init(segmentKey: String = "", anchorSeconds: Double = 0) {
        self.segmentKey = segmentKey
        self.anchorSeconds = anchorSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        segmentKey = try container.decodeIfPresent(String.self, forKey: .segmentKey) ?? ""
        anchorSeconds = try container.decodeIfPresent(Double.self, forKey: .anchorSeconds) ?? 0
    }
}

/// Everything a paste decides — TODAY minted by UI gestures (⌘V, ⌘D,
/// Loop ×N, the popover), TOMORROW by a planner that reads
/// `payload.context` plus an operator utterance and emits this same value.
/// Codable on purpose: the future LLM stage is one new producer of this
/// struct, with zero reshaping of paste, undo, sweep, or assembly.
struct ShotSegmentPasteIntent: Codable, Hashable, Sendable {
    var anchor: ShotSegmentPasteAnchor = ShotSegmentPasteAnchor()
    var loopCount: Int = 1
    /// nil = keep each span's own rate (WYSIWYG); a value overrides all.
    var playbackRate: Double? = nil
    /// nil = the gesture default (plain paste inherits; loop copies are born
    /// muted while the base keeps its sound — THE HYBRID AUDIO DEFAULT).
    var muteSourceAudio: Bool? = nil
    /// Reserved transform ladder — "" = identity, the only v1 value.
    var transformKind: String = ""
    var transformSpec: String = ""

    private enum CodingKeys: String, CodingKey {
        case anchor, loopCount, playbackRate, muteSourceAudio
        case transformKind, transformSpec
    }

    init(
        anchor: ShotSegmentPasteAnchor = ShotSegmentPasteAnchor(),
        loopCount: Int = 1,
        playbackRate: Double? = nil,
        muteSourceAudio: Bool? = nil,
        transformKind: String = "",
        transformSpec: String = ""
    ) {
        self.anchor = anchor
        self.loopCount = loopCount
        self.playbackRate = playbackRate
        self.muteSourceAudio = muteSourceAudio
        self.transformKind = transformKind
        self.transformSpec = transformSpec
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        anchor = ((try? container.decodeIfPresent(ShotSegmentPasteAnchor.self, forKey: .anchor)) ?? nil)
            ?? ShotSegmentPasteAnchor()
        loopCount = try container.decodeIfPresent(Int.self, forKey: .loopCount) ?? 1
        playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate)
        muteSourceAudio = try container.decodeIfPresent(Bool.self, forKey: .muteSourceAudio)
        transformKind = try container.decodeIfPresent(String.self, forKey: .transformKind) ?? ""
        transformSpec = try container.decodeIfPresent(String.self, forKey: .transformSpec) ?? ""
    }
}

/// PURE: payload + intent → the insertions a paste commits. Loop copies are
/// `loopCount × spans`, in paste order, sharing one `loopGroupId` whenever
/// more than one lands (display consolidation + group-scope edits).
func mintedPictureInsertions(
    payload: ShotPictureSegmentClipboardPayload,
    intent: ShotSegmentPasteIntent,
    now: String
) -> [ShotPictureInsertion] {
    let spans = payload.spans.filter {
        (!$0.clipPath.trimmed.isEmpty || !$0.mediaId.trimmed.isEmpty)
            && $0.seconds >= ShotCutList.minimumRangeSeconds
    }
    guard !spans.isEmpty, !intent.anchor.segmentKey.trimmed.isEmpty else { return [] }
    let loopCount = max(intent.loopCount, 1)
    let groupId = loopCount * spans.count > 1
        ? "loopg_\(UUID().uuidString.lowercased())"
        : ""
    var minted: [ShotPictureInsertion] = []
    for _ in 0..<loopCount {
        for span in spans {
            minted.append(ShotPictureInsertion(
                sourceSegmentKey: span.segmentKey,
                sourceClipPath: span.clipPath,
                sourceMediaId: span.mediaId,
                sourceStartSeconds: span.startSeconds,
                sourceEndSeconds: span.endSeconds,
                anchorSegmentKey: intent.anchor.segmentKey,
                anchorSeconds: intent.anchor.anchorSeconds,
                playbackRate: intent.playbackRate ?? span.playbackRate,
                muteSourceAudio: intent.muteSourceAudio ?? span.muteSourceAudio,
                transformKind: intent.transformKind,
                transformSpec: intent.transformSpec,
                loopGroupId: groupId,
                updatedAt: now
            ))
        }
    }
    return minted
}

// MARK: - Section speed (THE REPLACE PATTERN as one gesture)

/// THE 2-FRAME OUTPUT LAW: every rated span must still produce at least two
/// output frames, or the compositor would carry a sub-frame sliver the
/// operator can't see or grab. Returns the offending span's source seconds
/// (for the refusal line), nil when every span is legal.
func shotSectionRateSubFrameSpanSeconds(
    spans: [ShotPictureSegmentSpanRef],
    rate: Double
) -> Double? {
    guard rate > 0 else { return spans.first?.seconds }
    for span in spans where span.seconds / rate < 2 * ShotAudioTiming.frameSeconds {
        return span.seconds
    }
    return nil
}

/// THE SECTION SPEED COMPOSITE (pure kernel): one razor per span hiding the
/// base material, one born-muted carrier per span playing the same span back
/// at `rate` in the razored gap (the splice's razored-gap snap lands it
/// exactly where the material was), linked by `replacesRazorCutIds`.
/// nil when nothing structural would change (no spans, or rate ≈ 1).
func shotApplyingSectionRate(
    _ shot: ProjectShot,
    spans: [ShotPictureSegmentSpanRef],
    rate: Double,
    now: String
) -> ProjectShot? {
    let usable = spans.filter { $0.seconds >= ShotCutList.minimumRangeSeconds }
    guard !usable.isEmpty, abs(rate - 1) >= 0.001 else { return nil }
    var list = shot.cutList
    var carriers: [ShotPictureInsertion] = []
    for span in usable {
        let cut = ShotSegmentCutRange(
            segmentKey: span.segmentKey,
            // The razor law verbatim: generated cuts pin the exact take,
            // footage cuts carry "" and persist across renders.
            clipPath: span.isFootage ? "" : span.clipPath,
            startSeconds: span.startSeconds,
            endSeconds: span.endSeconds,
            updatedAt: now
        )
        list.segmentCuts.append(cut)
        carriers.append(ShotPictureInsertion(
            sourceSegmentKey: span.segmentKey,
            sourceClipPath: span.clipPath,
            sourceMediaId: span.mediaId,
            sourceStartSeconds: span.startSeconds,
            sourceEndSeconds: span.endSeconds,
            anchorSegmentKey: span.segmentKey,
            anchorSeconds: span.startSeconds,
            playbackRate: rate,
            // Ratified birth law: the section arrives silent; ♪ on its cell
            // restores the stretched sound.
            muteSourceAudio: true,
            replacesRazorCutIds: [cut.id],
            updatedAt: now
        ))
    }
    var value = shot.settingCutList(list, now: now)
    value.pictureInsertions.append(contentsOf: carriers)
    value.updatedAt = now
    return value
}

/// The carriers whose links name this cut — R2's pure half.
func shotSectionCarrierIds(
    insertions: [ShotPictureInsertion],
    cutId: String
) -> Set<String> {
    Set(insertions
        .filter { $0.replacesRazorCutIds.contains(cutId) }
        .map(\.insertionId))
}

/// R1's pure kernel: removes the insertions AND the live cut-list cuts their
/// links name (dangling ids ignored — the link law tolerates them). nil when
/// nothing changes.
func shotRemovingSectionSpeed(
    _ shot: ProjectShot,
    insertionIds: Set<String>,
    now: String
) -> (shot: ProjectShot, restoredCutIds: Set<String>)? {
    let removed = shot.pictureInsertions.filter { insertionIds.contains($0.insertionId) }
    guard !removed.isEmpty else { return nil }
    let liveCutIds = Set(shot.cutList.segmentCuts.map(\.id))
    let restored = Set(removed.flatMap(\.replacesRazorCutIds)).intersection(liveCutIds)
    var list = shot.cutList
    list.segmentCuts.removeAll { restored.contains($0.id) }
    var value = shot.settingCutList(list, now: now)
    value.pictureInsertions.removeAll { insertionIds.contains($0.insertionId) }
    value.updatedAt = now
    return (value, restored)
}

/// R3's pure kernel: re-pins a carrier's source AND its linked razors'
/// `clipPath` onto the segment's current take. Seconds stay put — the same
/// clamp-at-play approximation Re-copy already makes for the copy itself.
func shotRecopyingSectionInsertion(
    _ shot: ProjectShot,
    insertionId: String,
    activePath: String,
    now: String
) -> ProjectShot? {
    guard let insertion = shot.pictureInsertions.first(where: { $0.insertionId == insertionId }),
          !activePath.trimmed.isEmpty else { return nil }
    var value = shot
    for index in value.pictureInsertions.indices
        where value.pictureInsertions[index].insertionId == insertionId {
        value.pictureInsertions[index].sourceClipPath = activePath
        value.pictureInsertions[index].updatedAt = now
    }
    let linked = Set(insertion.replacesRazorCutIds)
    if !linked.isEmpty {
        var list = value.cutList
        for index in list.segmentCuts.indices where linked.contains(list.segmentCuts[index].id) {
            // Footage razors ("" pin) never re-pin; generated ones follow
            // the carrier onto the new take.
            if !list.segmentCuts[index].clipPath.isEmpty {
                list.segmentCuts[index].clipPath = activePath
                list.segmentCuts[index].updatedAt = now
            }
        }
        value = value.settingCutList(list, now: now)
    }
    value.updatedAt = now
    return value
}

/// Direction-free ripple boundary for a material section: the smaller of the
/// two bounds' output projections on the VISIBLE assembly — forward this is
/// the section's output start; reversed, the section's output start maps from
/// its HIGH material bound, and min() names it without a direction branch.
func shotSectionRippleStart(
    assembly: ShotCutAssembly,
    materialLow: Double,
    materialHigh: Double
) -> Double {
    min(
        assembly.outputSeconds(forMaterialSeconds: min(materialLow, materialHigh)),
        assembly.outputSeconds(forMaterialSeconds: max(materialLow, materialHigh))
    )
}
