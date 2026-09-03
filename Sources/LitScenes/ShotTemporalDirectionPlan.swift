import Foundation

// MARK: - Temporal Direction Plan (model-neutral timed beats)

/// One beat of a segment's temporal direction. Weights are RELATIVE — absolute
/// seconds are allocated at compile time from the render stack's
/// `segmentSeconds`, so a stack duration change never invalidates the plan.
/// `action` directs subject/scene MOTION; `camera` directs the camera; both
/// deliberately carry no timing numbers — the compiler owns timing syntax.
struct ShotTemporalBeat: Codable, Hashable, Sendable {
    var durationWeight: Double = 1
    var action: String = ""
    var camera: String = ""

    private enum CodingKeys: String, CodingKey {
        case durationWeight
        case action
        case camera
    }

    init(durationWeight: Double = 1, action: String = "", camera: String = "") {
        self.durationWeight = durationWeight
        self.action = action
        self.camera = camera
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        durationWeight = try container.decodeIfPresent(Double.self, forKey: .durationWeight) ?? 1
        action = try container.decodeIfPresent(String.self, forKey: .action) ?? ""
        camera = try container.decodeIfPresent(String.self, forKey: .camera) ?? ""
    }

    /// Weight with junk squeezed out: non-finite or non-positive counts as 1.
    var sanitizedWeight: Double {
        durationWeight.isFinite && durationWeight > 0 ? durationWeight : 1
    }

    var isBlank: Bool { action.trimmed.isEmpty && camera.trimmed.isEmpty }

    func normalized() -> ShotTemporalBeat {
        ShotTemporalBeat(
            durationWeight: sanitizedWeight,
            action: action.trimmed,
            camera: camera.trimmed
        )
    }
}

/// Whether the beats describe ONE unbroken take or deliberate in-segment cuts.
/// Action beats are NOT shot boundaries: a continuous plan with three beats
/// must never become three provider shots — only `multiShot` licenses the
/// compiler to emit hard-cut structures (Kling `multi_prompt`, "Cut to:").
enum ShotTemporalShotMode: String, Codable, Sendable {
    case continuous
    case multiShot = "multi_shot"
}

/// Model-neutral timed-beats direction for one render segment. Deliberately
/// does NOT store a duration: `ShotRenderStack.segmentSeconds` is the single
/// source of truth, applied when the plan compiles.
struct ShotTemporalDirectionPlan: Codable, Hashable, Sendable {
    var shotMode: ShotTemporalShotMode = .continuous
    var beats: [ShotTemporalBeat] = []

    private enum CodingKeys: String, CodingKey {
        case shotMode
        case beats
    }

    init(shotMode: ShotTemporalShotMode = .continuous, beats: [ShotTemporalBeat] = []) {
        self.shotMode = shotMode
        self.beats = beats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawMode = try container.decodeIfPresent(String.self, forKey: .shotMode) ?? ""
        shotMode = ShotTemporalShotMode(rawValue: rawMode) ?? .continuous
        beats = ((try? container.decodeIfPresent([ShotTemporalBeat].self, forKey: .beats)) ?? nil) ?? []
    }

    /// Empty means "nothing to direct" — the segment falls back to the
    /// classic one-sentence prompt exactly as if no plan existed.
    var isEmpty: Bool { beats.allSatisfy(\.isBlank) }

    /// Deterministic content identity (mode + every beat, weights in %g so
    /// 1 and 1.0 agree). Used by the autosave loop guard and staleness
    /// fingerprints; excludes nothing that changes what would render.
    var signature: String {
        let beatParts = beats.map { beat in
            let weight = String(format: "%g", beat.sanitizedWeight)
            return "\(weight):\(beat.action.trimmed):\(beat.camera.trimmed)"
        }
        return "\(shotMode.rawValue)|\(beatParts.joined(separator: ";"))"
    }

    func normalized() -> ShotTemporalDirectionPlan {
        ShotTemporalDirectionPlan(
            shotMode: shotMode,
            beats: beats.map { $0.normalized() }
        )
    }
}

/// Which artifact wins a segment's prompt: the structured beats plan, or the
/// classic free-text path (override ?? generated sentence). An explicit flag,
/// never a heuristic — a raw draft the user is typing must not be clobbered
/// by a beats recompile, and vice versa.
enum ShotSegmentPromptMode: String, Codable, Sendable {
    case beats
    case raw
}

/// The persisted per-segment direction plan, keyed exactly like
/// `ShotSegmentPromptOverride` (placement entry ids canonical, frame image
/// ids as legacy fallback). LLM drafts and user edits share one record: an
/// edit overwrites `plan` and flips `source`; `llmDraftPlan` keeps the
/// pristine draft as the RESET target. `promptMode == "raw"` RETAINS the plan
/// while the flat override wins — switching back to beats restores it.
struct ShotSegmentDirectionPlanRecord: Codable, Hashable, Sendable {
    var startFrameImageId: String = ""
    var endFrameImageId: String = ""
    var placementStartEntryId: String = ""
    var placementEndEntryId: String = ""
    var plan: ShotTemporalDirectionPlan = ShotTemporalDirectionPlan()
    var promptMode: String = ShotSegmentPromptMode.beats.rawValue
    var source: String = "user"
    var llmDraftPlan: ShotTemporalDirectionPlan?
    var inputsFingerprint: String = ""
    var responseId: String = ""
    var updatedAt: String = ""

    private enum CodingKeys: String, CodingKey {
        case startFrameImageId
        case endFrameImageId
        case placementStartEntryId
        case placementEndEntryId
        case plan
        case promptMode
        case source
        case llmDraftPlan
        case inputsFingerprint
        case responseId
        case updatedAt
    }

    init(
        startFrameImageId: String = "",
        endFrameImageId: String = "",
        placementStartEntryId: String = "",
        placementEndEntryId: String = "",
        plan: ShotTemporalDirectionPlan = ShotTemporalDirectionPlan(),
        promptMode: String = ShotSegmentPromptMode.beats.rawValue,
        source: String = "user",
        llmDraftPlan: ShotTemporalDirectionPlan? = nil,
        inputsFingerprint: String = "",
        responseId: String = "",
        updatedAt: String = ""
    ) {
        self.startFrameImageId = startFrameImageId
        self.endFrameImageId = endFrameImageId
        self.placementStartEntryId = placementStartEntryId
        self.placementEndEntryId = placementEndEntryId
        self.plan = plan
        self.promptMode = promptMode
        self.source = source
        self.llmDraftPlan = llmDraftPlan
        self.inputsFingerprint = inputsFingerprint
        self.responseId = responseId
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startFrameImageId = try container.decodeIfPresent(String.self, forKey: .startFrameImageId) ?? ""
        endFrameImageId = try container.decodeIfPresent(String.self, forKey: .endFrameImageId) ?? ""
        placementStartEntryId = try container.decodeIfPresent(String.self, forKey: .placementStartEntryId) ?? ""
        placementEndEntryId = try container.decodeIfPresent(String.self, forKey: .placementEndEntryId) ?? ""
        plan = ((try? container.decodeIfPresent(ShotTemporalDirectionPlan.self, forKey: .plan)) ?? nil)
            ?? ShotTemporalDirectionPlan()
        promptMode = try container.decodeIfPresent(String.self, forKey: .promptMode)
            ?? ShotSegmentPromptMode.beats.rawValue
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "user"
        llmDraftPlan = (try? container.decodeIfPresent(ShotTemporalDirectionPlan.self, forKey: .llmDraftPlan)) ?? nil
        inputsFingerprint = try container.decodeIfPresent(String.self, forKey: .inputsFingerprint) ?? ""
        responseId = try container.decodeIfPresent(String.self, forKey: .responseId) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    /// Unknown persisted modes fall to `.beats` (the record's reason to exist).
    var mode: ShotSegmentPromptMode {
        ShotSegmentPromptMode(rawValue: promptMode) ?? .beats
    }

    /// The stable segment key this record answers to — identical law to
    /// prompt overrides.
    var directionKey: String {
        shotPlacementSegmentKey(
            startEntryId: placementStartEntryId,
            endEntryId: placementEndEntryId,
            legacyStartId: startFrameImageId,
            legacyEndId: endFrameImageId
        )
    }

    /// Worth persisting: a plan with content, or a retained LLM draft.
    var hasContent: Bool { !plan.isEmpty || llmDraftPlan != nil }

    func normalized() -> ShotSegmentDirectionPlanRecord {
        var value = self
        value.startFrameImageId = value.startFrameImageId.trimmed
        value.endFrameImageId = value.endFrameImageId.trimmed
        value.placementStartEntryId = value.placementStartEntryId.trimmed
        value.placementEndEntryId = value.placementEndEntryId.trimmed
        value.plan = value.plan.normalized()
        value.promptMode = value.mode.rawValue
        value.source = value.source.trimmed.nilIfEmpty ?? "user"
        value.llmDraftPlan = value.llmDraftPlan?.normalized()
        value.inputsFingerprint = value.inputsFingerprint.trimmed
        value.responseId = value.responseId.trimmed
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

/// The $0 deterministic seed for the beats editor: one beat wrapping exactly
/// the sentence a plan-less render would send, so an untouched beats plan and
/// no plan at all direct the very same motion.
func shotFallbackDirectionPlan(pair: ShotRenderPair) -> ShotTemporalDirectionPlan {
    ShotTemporalDirectionPlan(
        shotMode: .continuous,
        beats: [ShotTemporalBeat(durationWeight: 1, action: shotSegmentPrompt(pair: pair))]
    )
}

// MARK: - Weight → integer-second allocation

/// One beat with its allocated window. Windows are contiguous, start at 0,
/// and the last ends exactly at the requested total.
struct ShotAllocatedBeat: Equatable {
    var beat: ShotTemporalBeat
    var startSecond: Int
    var endSecond: Int
}

/// Deterministic largest-remainder allocation of `totalSeconds` across the
/// plan's beats. Weights sanitize (non-finite/non-positive → 1); shares floor;
/// leftover seconds go to the largest fractional remainders, ties to the
/// EARLIER beat; every beat then gets ≥ 1s by taking from the currently
/// largest allocation (ties to the earlier). When there are more beats than
/// seconds, trailing beats merge into their predecessor ("A, then B", first
/// non-empty camera kept) until they fit. Empty plans or non-positive totals
/// allocate nothing.
func shotTemporalBeatAllocation(
    plan: ShotTemporalDirectionPlan,
    totalSeconds: Int
) -> [ShotAllocatedBeat] {
    guard totalSeconds > 0, !plan.beats.isEmpty else { return [] }
    var beats = plan.beats.map { $0.normalized() }
    while beats.count > totalSeconds, beats.count > 1 {
        let last = beats.removeLast()
        var previous = beats[beats.count - 1]
        previous.durationWeight = previous.sanitizedWeight + last.sanitizedWeight
        let parts = [previous.action, last.action].map(\.trimmed).filter { !$0.isEmpty }
        previous.action = parts.joined(separator: ", then ")
        if previous.camera.trimmed.isEmpty { previous.camera = last.camera }
        beats[beats.count - 1] = previous
    }

    let weights = beats.map(\.sanitizedWeight)
    let totalWeight = weights.reduce(0, +)
    let shares = weights.map { $0 / totalWeight * Double(totalSeconds) }
    var allocated = shares.map { Int($0.rounded(.down)) }
    var leftover = totalSeconds - allocated.reduce(0, +)
    let remainderOrder = shares.indices.sorted { lhs, rhs in
        let lhsFraction = shares[lhs] - shares[lhs].rounded(.down)
        let rhsFraction = shares[rhs] - shares[rhs].rounded(.down)
        if lhsFraction != rhsFraction { return lhsFraction > rhsFraction }
        return lhs < rhs
    }
    for index in remainderOrder where leftover > 0 {
        allocated[index] += 1
        leftover -= 1
    }
    // Min-1s repair: feasible by construction (beats.count ≤ totalSeconds),
    // so while any beat sits at zero, some other beat holds ≥ 2.
    while let zeroIndex = allocated.firstIndex(of: 0) {
        guard let maxValue = allocated.max(), maxValue > 1,
              let donorIndex = allocated.firstIndex(of: maxValue) else { break }
        allocated[donorIndex] -= 1
        allocated[zeroIndex] += 1
    }

    var windows: [ShotAllocatedBeat] = []
    var cursor = 0
    for (index, beat) in beats.enumerated() {
        let end = cursor + allocated[index]
        windows.append(ShotAllocatedBeat(beat: beat, startSecond: cursor, endSecond: end))
        cursor = end
    }
    return windows
}

// MARK: - Draft-law siblings (mirror the prompt-override quartet)

/// Drops direction plans whose frames are no longer anywhere in the shot's
/// strip — the exact present-frame/entry law of
/// `pruningSegmentPromptOverrides`, kept parallel rather than generalized
/// because the override pruner is test-pinned. Later entries win a duplicate
/// key; records with neither content nor a retained LLM draft drop.
func pruningSegmentDirectionPlans(
    _ records: [ShotSegmentDirectionPlanRecord],
    entries: [ShotFrameEntry]
) -> [ShotSegmentDirectionPlanRecord] {
    let presentEntryIds = Set(entries.map(\.entryId))
    var presentIds = Set(entries.map(\.frameImageId))
    presentIds.remove("")
    for entry in entries where entry.isClip {
        let ids = shotFootageBoundaryFrameIds(
            mediaId: entry.clipMediaId,
            startSeconds: entry.clipStartSeconds,
            endSeconds: entry.clipEndSeconds
        )
        presentIds.insert(ids.start)
        presentIds.insert(ids.end)
    }
    var seenKeys = Set<String>()
    var kept: [ShotSegmentDirectionPlanRecord] = []
    for rawRecord in records.reversed() {
        let record = rawRecord.normalized()
        guard record.hasContent else { continue }
        let key = record.directionKey
        if !record.placementStartEntryId.isEmpty || !record.placementEndEntryId.isEmpty {
            let startOK = record.placementStartEntryId.isEmpty
                || presentEntryIds.contains(record.placementStartEntryId)
            let endOK = record.placementEndEntryId.isEmpty
                || presentEntryIds.contains(record.placementEndEntryId)
            guard !seenKeys.contains(key), startOK, endOK else { continue }
            seenKeys.insert(key)
            kept.append(record)
            continue
        }
        let startOK = record.startFrameImageId.isEmpty
            ? !record.endFrameImageId.isEmpty
            : presentIds.contains(record.startFrameImageId)
        let endOK = record.endFrameImageId.isEmpty
            ? !record.startFrameImageId.isEmpty
            : presentIds.contains(record.endFrameImageId)
        guard !seenKeys.contains(key), startOK, endOK else { continue }
        seenKeys.insert(key)
        kept.append(record)
    }
    return kept.reversed()
}

/// The record set to persist from a beats-drafting editor — the sibling of
/// `computedSegmentPromptOverrides`, same keying law: drafts key by the
/// stable pair, an ABSENT draft carries the existing record forward, and the
/// first of a duplicated pair wins its shared key. A raw-mode record whose
/// plan matches the deterministic fallback and holds no LLM draft stores
/// nothing (there is nothing worth retaining). `source` resolves against the
/// retained LLM draft: matching it stays "llm", any other change is "user".
/// `updatedAt` only advances when the stored content actually changes.
func computedSegmentDirectionPlans(
    planDrafts: [String: ShotTemporalDirectionPlan],
    modeDrafts: [String: ShotSegmentPromptMode],
    items: [ShotSegmentPromptPlanItem],
    existing: [ShotSegmentDirectionPlanRecord],
    now: String
) -> [ShotSegmentDirectionPlanRecord] {
    let existingByKey = Dictionary(
        existing.map { ($0.normalized().directionKey, $0.normalized()) },
        uniquingKeysWith: { _, last in last }
    )
    var seenKeys = Set<String>()
    var records: [ShotSegmentDirectionPlanRecord] = []
    for item in items {
        let key = item.pairKey
        guard !seenKeys.contains(key) else { continue }
        seenKeys.insert(key)
        let existingRecord = existingByKey[key]
        guard let draft = (planDrafts[key] ?? existingRecord?.plan)?.normalized() else { continue }
        let mode = modeDrafts[key] ?? existingRecord?.mode ?? .beats
        let fallback = shotFallbackDirectionPlan(pair: item.pair).normalized()
        let llmDraft = existingRecord?.llmDraftPlan?.normalized()
        if llmDraft == nil, draft.isEmpty || (mode == .raw && draft == fallback) { continue }
        let source: String
        if let llmDraft, llmDraft == draft {
            source = "llm"
        } else if let existingRecord, existingRecord.plan == draft {
            source = existingRecord.source
        } else {
            source = "user"
        }
        let contentChanged = existingRecord.map {
            $0.plan != draft || $0.mode != mode
        } ?? true
        records.append(ShotSegmentDirectionPlanRecord(
            startFrameImageId: item.pair.start?.imageId ?? "",
            endFrameImageId: item.pair.end?.imageId ?? "",
            placementStartEntryId: item.pair.startPlacementEntryId,
            placementEndEntryId: item.pair.endPlacementEntryId,
            plan: draft,
            promptMode: mode.rawValue,
            source: source,
            llmDraftPlan: llmDraft,
            inputsFingerprint: existingRecord?.inputsFingerprint ?? "",
            responseId: existingRecord?.responseId ?? "",
            updatedAt: contentChanged ? now : (existingRecord?.updatedAt ?? now)
        ))
    }
    return records
}

/// The autosave law, verbatim from `mergedAutosavePromptOverrides`: an
/// UPSERT-ONLY union by segment key. Keys the computed set omits KEEP their
/// existing record — deleting a plan stays a confirm/RESET-time behavior.
func mergedAutosaveDirectionPlans(
    existing: [ShotSegmentDirectionPlanRecord],
    computed: [ShotSegmentDirectionPlanRecord]
) -> [ShotSegmentDirectionPlanRecord] {
    var byKey: [String: ShotSegmentDirectionPlanRecord] = [:]
    var order: [String] = []
    for record in existing + computed {
        let key = record.directionKey
        if byKey[key] == nil { order.append(key) }
        byKey[key] = record
    }
    return order.compactMap { byKey[$0] }
}

/// Agreement on (key, plan signature, mode) only — timestamps, provenance,
/// and fingerprints are excluded so an autosave can never loop on its own
/// bookkeeping.
func directionPlansAgree(
    _ lhs: [ShotSegmentDirectionPlanRecord],
    _ rhs: [ShotSegmentDirectionPlanRecord]
) -> Bool {
    let normalize: ([ShotSegmentDirectionPlanRecord]) -> Set<String> = { records in
        Set(records.map { record in
            let normalized = record.normalized()
            return "\(normalized.directionKey)|\(normalized.plan.signature)|\(normalized.mode.rawValue)"
        })
    }
    return normalize(lhs) == normalize(rhs)
}

// MARK: - LLM drafting: prompt composer + staleness fingerprint

/// Everything the beat-drafting prompt sees for one segment. Deliberately
/// dialect-free: the plan is model-neutral by contract, so no provider or
/// timing syntax ever reaches the drafting model.
struct ShotDirectionPlanDraftContext {
    var segmentSeconds: Int = 0
    var startImageId: String = ""
    var endImageId: String = ""
    var startFrameGist: String = ""
    var endFrameGist: String = ""
    var lineageSentence: String = ""
    var narrationTitle: String = ""
    var narrationBody: String = ""
    var strandLines: [String] = []
}

/// The ~250-char authored gist of a frame: the authored text when the prompt
/// rewrite kept one, else the provider-bound prompt.
func shotDirectionFrameGist(_ frame: ProjectLensHeroImage?) -> String {
    guard let frame else { return "" }
    let text = frame.sourcePrompt.trimmed.nilIfEmpty ?? frame.prompt.trimmed
    return String(text.prefix(250))
}

/// The drafting context for one segment, derived from what the pair and the
/// shot already carry — no external lookups, so every surface derives the
/// same staleness truth.
func shotDirectionPlanDraftContext(
    shot: ProjectShot,
    pair: ShotRenderPair,
    segmentSeconds: Int,
    strandLines: [String] = []
) -> ShotDirectionPlanDraftContext {
    ShotDirectionPlanDraftContext(
        segmentSeconds: segmentSeconds,
        startImageId: pair.start?.imageId ?? "",
        endImageId: pair.end?.imageId ?? "",
        startFrameGist: shotDirectionFrameGist(pair.start),
        endFrameGist: shotDirectionFrameGist(pair.end),
        lineageSentence: shotReframeLineagePrompt(pair: pair) ?? "",
        narrationTitle: shot.narrationArtifact?.messagingText.trimmed ?? "",
        narrationBody: shot.narrationArtifact?.bodyText.trimmed ?? "",
        strandLines: Array(strandLines.prefix(3))
    )
}

/// Staleness identity for an LLM draft. Strands are deliberately EXCLUDED —
/// they garnish the prompt but must not flip STALE on every meaning-graph
/// tweak, and excluding them keeps the fingerprint derivable from the shot
/// and pair alone.
func shotDirectionPlanInputsFingerprint(context: ShotDirectionPlanDraftContext) -> String {
    shortHash(
        [
            context.startImageId,
            context.endImageId,
            context.startFrameGist,
            context.endFrameGist,
            context.lineageSentence,
            context.narrationTitle,
            context.narrationBody,
            "\(context.segmentSeconds)",
        ].joined(separator: "|"),
        length: 16
    )
}

enum ShotDirectionPlanComposer {
    /// Beat-count guidance scaled to the segment length.
    static func beatCountGuidance(segmentSeconds: Int) -> String {
        if segmentSeconds <= 5 { return "exactly 2 beats" }
        if segmentSeconds <= 8 { return "2 or 3 beats" }
        return "3 or 4 beats"
    }

    static func draftPrompt(context: ShotDirectionPlanDraftContext) -> String {
        var sections: [String] = []
        sections.append(
            "You are directing the MOTION of one \(context.segmentSeconds)-second AI-video segment that "
                + "interpolates between two existing keyframe images. Write \(beatCountGuidance(segmentSeconds: context.segmentSeconds)) "
                + "of temporal direction: each beat is one sentence of subject/scene motion, an optional camera move, "
                + "and a relative duration weight (1-4)."
        )
        var rules = [
            "Beats direct MOTION and CAMERA only — never re-describe what the keyframes already depict.",
            "No timing numbers, seconds, shot numbers, percentages, or geometry in your text — weights alone carry pacing.",
            "The final beat must arrive on the last frame's framing.",
            "Choose multi_shot ONLY when the two keyframes cannot plausibly be one continuous camera move; otherwise continuous.",
        ]
        if context.endImageId.isEmpty {
            rules[2] = "The segment is open-ended: begin exactly on the first frame and keep motion true to it."
        }
        if context.startImageId.isEmpty {
            rules[2] = "The segment is a lead-in: it must ARRIVE exactly on the final frame as depicted."
        }
        sections.append("Rules:\n- " + rules.joined(separator: "\n- "))
        var contextLines: [String] = []
        if !context.startFrameGist.isEmpty {
            contextLines.append("First keyframe (CONTEXT — already depicted, do NOT restate): \(context.startFrameGist)")
        }
        if !context.endFrameGist.isEmpty {
            contextLines.append("Last keyframe (CONTEXT — already depicted, do NOT restate): \(context.endFrameGist)")
        }
        if !context.lineageSentence.isEmpty {
            contextLines.append(
                "STRUCTURAL FACT — the camera relationship between these frames is derived, not optional; "
                    + "your beat cameras must honor it: \(context.lineageSentence)"
            )
        }
        if !context.narrationTitle.isEmpty || !context.narrationBody.isEmpty {
            let narration = [context.narrationTitle, context.narrationBody]
                .filter { !$0.isEmpty }
                .joined(separator: " — ")
            contextLines.append("The shot's stated intent: \(narration)")
        }
        if !context.strandLines.isEmpty {
            contextLines.append("Running motifs: " + context.strandLines.joined(separator: "; "))
        }
        if !contextLines.isEmpty {
            sections.append(contextLines.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }
}
