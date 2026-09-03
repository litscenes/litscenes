import Foundation

// SCENES v2 pure laws. In v2 language a "Scene" is a ProjectShot; the
// ProjectLens stays in the data model but leaves the user-facing vocabulary.
// Everything here is a value or a pure function — no engine, no views — so
// the rail, boxes, and pool all derive from one tested set of rules.

// MARK: - Rail values

/// One scene anywhere in the app, across projects.
struct SceneRef: Hashable, Identifiable, Sendable {
    var projectId: String
    var shotId: String
    var id: String { "\(projectId):\(shotId)" }
}

/// Honest render status for a rail card. For the LOADED project the truth is
/// live engine state; for an unloaded project the only truth is the persisted
/// document — where "generating" means PARKED (nothing is running; the next
/// load's reconcile flips it to failed-with-kept-segments), never RENDERING.
enum SceneRenderBadge: String, Sendable {
    case draft
    case rendering
    case parked
    case failed
    case ready
}

/// One rail card. A pure value snapshot — never holds an image.
struct SceneIndexEntry: Hashable, Identifiable, Sendable {
    var projectId: String = ""
    var shotId: String = ""
    var displayName: String = ""
    var entryCount: Int = 0
    /// Ordered candidate poster paths; the view walks them through
    /// StripThumbnailCache until one decodes (the cutPosterImage law keeps
    /// its decode-failure fall-through this way). The ledger card's
    /// micro-filmstrip reads slot i from `dropFirst(i)` of this same list, so
    /// the fall-through law covers every sliver too.
    var posterCandidatePaths: [String] = []
    var badge: SceneRenderBadge = .draft
    /// THE LEDGER LINE: compact frames · clips · runtime, derived live
    /// (`sceneLedgerLine`) — nothing on the card is newly stored.
    var ledgerLine: String = ""
    /// The shot's default stack, first component only ("WAN 2.7").
    var modelLabel: String = ""
    var hasNarration: Bool = false
    var hasPlacedAudio: Bool = false
    /// Live render progress while THIS scene is the active render:
    /// 0…1 fraction of segment clips landed. nil = not rendering.
    var renderProgress: Double? = nil
    /// The artifact's own progress sentence ("SEGMENT 2 OF 3").
    var progressLabel: String = ""
    /// 1-based position in the Output sequence; nil = not marked ready.
    var sequencePosition: Int? = nil
    /// True for a combined scene (kept collapsed sources).
    var isCombined: Bool = false
    var id: String { "\(projectId):\(shotId)" }
}

/// One project group in the rail.
struct ProjectSceneGroup: Hashable, Identifiable, Sendable {
    var projectId: String = ""
    var projectName: String = ""
    var isLoaded: Bool = false
    var scenes: [SceneIndexEntry] = []
    /// "" when clean; a non-empty decode problem is shown honestly on the
    /// group rather than rendering an empty group as if the project were empty.
    var loadIssue: String = ""
    var id: String { projectId }
}

/// A cached decode of one unloaded project's scenes.
struct ProjectSceneSnapshot: Sendable {
    var projectId: String = ""
    var scenes: [SceneIndexEntry] = []
    var loadIssue: String = ""
    var refreshedAt: Date = .distantPast
}

// MARK: - Scene naming

/// The one canonical scene display name. `index` is the 0-based position among
/// VISIBLE scenes. v1 surfaces keep their historical fallbacks ("Untitled
/// Shot", "CUT n", "SHOT <roman>", "Shot n") — consolidating them onto this
/// helper is future work; every v2 surface must use it from day one.
func sceneDisplayName(shot: ProjectShot, index: Int) -> String {
    let trimmed = shot.name.trimmed
    return trimmed.isEmpty ? "Scene \(index + 1)" : trimmed
}

// MARK: - Poster derivation

/// Mirrors cutPosterImage's precedence (first placed material wins: a ready
/// frame's still, else that entry's footage poster) but returns the ordered
/// CANDIDATE paths so the caller preserves the decode-failure fall-through.
func scenePosterCandidatePaths(
    entries: [ShotFrameEntry],
    frameStillPathById: [String: String],
    footageThumbnailPathByMediaId: [String: String]
) -> [String] {
    var paths: [String] = []
    for entry in entries {
        if let still = frameStillPathById[entry.frameImageId], !still.trimmed.isEmpty {
            paths.append(still)
        } else if entry.isClip,
                  let thumb = footageThumbnailPathByMediaId[entry.clipMediaId],
                  !thumb.trimmed.isEmpty {
            paths.append(thumb)
        }
    }
    return paths
}

// MARK: - Badges

/// Badge from a PERSISTED document — the only truth for unloaded projects.
/// Precedence: PARKED > FAILED > READY > DRAFT.
func sceneRenderBadgeFromDocument(shot: ProjectShot) -> SceneRenderBadge {
    if shot.renderVersions.contains(where: { $0.status == "generating" }) {
        return .parked
    }
    return settledRenderBadge(shot: shot)
}

/// Badge for the LOADED project — live engine truth. A persisted "generating"
/// version without a matching active render id is a straggler the next
/// reconcile will flip; it reports FAILED, never RENDERING.
func sceneRenderBadgeLive(shot: ProjectShot, activeShotRenderId: String) -> SceneRenderBadge {
    if !activeShotRenderId.isEmpty, activeShotRenderId == shot.shotId {
        return .rendering
    }
    if shot.renderVersions.contains(where: { $0.status == "generating" }) {
        return .failed
    }
    return settledRenderBadge(shot: shot)
}

private func settledRenderBadge(shot: ProjectShot) -> SceneRenderBadge {
    if shot.activeRenderVersion?.status == "failed" {
        return .failed
    }
    if shot.playableRenderVersion?.isReady == true {
        return .ready
    }
    return .draft
}

// MARK: - Usage (the pool's "Unused" truth)

/// Frames referenced by any CURRENT entry of the given scenes. Skipped entries
/// count as used (they stay in the strip); render history never counts. Feed
/// this `visibleShots` — trashed and combined-away scenes hold nothing.
func usedFrameImageIds(in shots: [ProjectShot]) -> Set<String> {
    Set(shots.flatMap(\.entries).map(\.frameImageId).filter { !$0.trimmed.isEmpty })
}

/// Footage referenced by any CURRENT entry of the given scenes.
func usedClipMediaIds(in shots: [ProjectShot]) -> Set<String> {
    Set(shots.flatMap(\.entries).map(\.clipMediaId).filter { !$0.trimmed.isEmpty })
}

// MARK: - Start & End frames (the pool's boundary filter)

/// Frames currently occupying a pair-boundary position in some scene: the
/// first or last READY, non-skipped frame of the strip (a single ready frame
/// is both). This is exactly the outer boundary of shotRenderPairs without
/// building pair structs — equivalence is pinned by test.
func boundaryFrameImageIds(
    shots: [ProjectShot],
    readyFrameImageIds: Set<String>
) -> Set<String> {
    var boundary: Set<String> = []
    for shot in shots {
        let ready = shot.entries
            .filter { !$0.isSkipped && readyFrameImageIds.contains($0.frameImageId) }
            .map(\.frameImageId)
        if let first = ready.first {
            boundary.insert(first)
        }
        if let last = ready.last {
            boundary.insert(last)
        }
    }
    return boundary
}

// MARK: - Pool inventory

/// The one deterministic Source pool order, extracted from the SCENES tab's
/// `sourceMaterialInputs` law: uploaded photos (excluding those adopted into
/// the DISPLAYED frames — a photo adopted in some other Scene must remain
/// present as the original media item; first use here owns its lazy adoption),
/// then the displayed frames in their given order, then remaining project
/// frames, then footage.
func projectPoolInputs(
    displayedFrames: [ProjectLensHeroImage],
    projectWideFrames: [ProjectLensHeroImage],
    items: [MediaItemRecord]
) -> [StageInput] {
    let displayedFrameIds = Set(displayedFrames.map(\.imageId))
    let adoptedInDisplayedFrames = Set(displayedFrames.flatMap { frame in
        frame.sourceDependencies.compactMap { dependency in
            let normalized = dependency.normalized()
            return normalized.role == "source_photo" ? normalized.sourceId : nil
        }
    })
    let photos = items
        .filter { $0.kind == .image && !adoptedInDisplayedFrames.contains($0.mediaId) }
        .sorted { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt { return lhs.filename < rhs.filename }
            return lhs.modifiedAt > rhs.modifiedAt
        }
        .map {
            StageInput(
                inputId: "source_media_\($0.mediaId)",
                clipMediaId: $0.mediaId,
                addedAt: $0.modifiedAt
            )
        }
    let visibleFrames = displayedFrames.map {
        StageInput(
            inputId: "source_frame_\($0.imageId)",
            frameImageId: $0.imageId,
            addedAt: $0.generatedAt
        )
    }
    let otherFrames = projectWideFrames
        .filter { !displayedFrameIds.contains($0.imageId) }
        .sorted { lhs, rhs in
            if lhs.generatedAt == rhs.generatedAt {
                if lhs.imageIndex == rhs.imageIndex { return lhs.imageId < rhs.imageId }
                return lhs.imageIndex < rhs.imageIndex
            }
            return lhs.generatedAt > rhs.generatedAt
        }
        .map {
            StageInput(
                inputId: "source_frame_\($0.imageId)",
                frameImageId: $0.imageId,
                addedAt: $0.generatedAt
            )
        }
    let footage = items
        .filter { $0.kind == .video }
        .sorted { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt { return lhs.filename < rhs.filename }
            return lhs.modifiedAt > rhs.modifiedAt
        }
        .map {
            StageInput(
                inputId: "source_media_\($0.mediaId)",
                clipMediaId: $0.mediaId,
                addedAt: $0.modifiedAt
            )
        }
    return photos + visibleFrames + otherFrames + footage
}

// MARK: - Pool filters

/// The pool's filter chips. Characters and Objects render grouped roster
/// sections (take stacks + identity refs) instead of filtering the union
/// grid, so only the first three carry a grid predicate.
enum ScenesV2PoolFilter: String, CaseIterable, Codable {
    case all
    case unused
    case startEnd
    case characters
    case objects

    var title: String {
        switch self {
        case .all: return "ALL"
        case .unused: return "UNUSED"
        case .startEnd: return "START & END"
        case .characters: return "CHARACTERS"
        case .objects: return "OBJECTS"
        }
    }
}

/// Grid-filter inputs derived once per body pass.
struct ScenesV2PoolUsage: Equatable, Sendable {
    var usedFrameIds: Set<String> = []
    var usedClipIds: Set<String> = []
    var boundaryFrameIds: Set<String> = []
}

/// Whether a pool input survives the given grid filter. `.characters` and
/// `.objects` return false — those chips replace the grid with roster
/// sections, so nothing from the union grid renders under them.
func poolInputMatchesFilter(
    _ input: StageInput,
    filter: ScenesV2PoolFilter,
    usage: ScenesV2PoolUsage
) -> Bool {
    switch filter {
    case .all:
        return true
    case .unused:
        return input.isClip
            ? !usage.usedClipIds.contains(input.clipMediaId)
            : !usage.usedFrameIds.contains(input.frameImageId)
    case .startEnd:
        return !input.isClip && usage.boundaryFrameIds.contains(input.frameImageId)
    case .characters, .objects:
        return false
    }
}

/// The append-picker's search law, shared by the v2 pool: clips match their
/// filename; frames match their label or prompt. An empty query matches all.
func poolInputMatchesQuery(
    _ input: StageInput,
    query: String,
    frameLookup: [String: ProjectLensHeroImage],
    mediaLookup: [String: MediaItemRecord]
) -> Bool {
    let query = query.trimmed.lowercased()
    guard !query.isEmpty else { return true }
    if input.isClip {
        return mediaLookup[input.clipMediaId]?.filename.lowercased().contains(query) == true
    }
    guard let frame = frameLookup[input.frameImageId] else { return false }
    return frame.label.lowercased().contains(query)
        || frame.prompt.lowercased().contains(query)
}

// MARK: - Stage selection (Option A, locked)

/// THE STAGE SELECTION LAW: SCENES v2 has ONE hero stage and selection is a
/// radio — click a rail card, the stage shows it. The two working boxes
/// (`ScenesV2BoxSlots`: MRU eviction, aimed drops, positional ordinals) are
/// deleted; everything they carried reduces to one selected scene id, and
/// `""` is the honest empty stage.
///
/// Reconcile sweeps a selection whose scene no longer exists: it falls back
/// to the most recent STILL-VISIBLE entry of the selection history (deleting
/// the staged scene returns the operator to the last scene they had staged,
/// never to the top of the rail — a locked decision), and only when the
/// history offers nothing does it seed with the first scene that still needs
/// work (ready scenes only when nothing is unready — the box seed's old
/// preference).
///
/// `seedsWhenEmpty: false` is THE DURABLE EMPTY STAGE (locked):
/// a DELIBERATELY empty selection — the conveyor's exhaustion, or a stored
/// empty preference — survives every reconcile, so the "every Scene is
/// marked ready" plate is a real state, not a flicker. A swept NON-empty
/// selection (its scene trashed) always resolves to SOMETHING regardless.
func scenesV2ReconciledSelection(
    _ selected: String,
    against visibleSceneIds: [String],
    readySceneIds: Set<String> = [],
    seedsWhenEmpty: Bool = true,
    recentSceneIds: [String] = []
) -> String {
    if !selected.isEmpty, visibleSceneIds.contains(selected) {
        return selected
    }
    if selected.isEmpty, !seedsWhenEmpty {
        return ""
    }
    if let recent = recentSceneIds.first(where: { $0 != selected && visibleSceneIds.contains($0) }) {
        return recent
    }
    return visibleSceneIds.first { !readySceneIds.contains($0) }
        ?? visibleSceneIds.first
        ?? ""
}

/// The two-box era's stored blob, reduced to one selection: the MRU slot's
/// scene when it names one, else the first occupied slot — "" holes were the
/// conveyor's exhaustion state and must not eat the remembered scene.
func scenesV2MigratedLegacySelection(sceneIds: [String], mruIndex: Int) -> String {
    if sceneIds.indices.contains(mruIndex), !sceneIds[mruIndex].isEmpty {
        return sceneIds[mruIndex]
    }
    return sceneIds.first { !$0.isEmpty } ?? ""
}

// MARK: - Ledger card derivations (display data, nothing newly stored)

/// THE LEDGER LINE: the card's compact material truth — "4 FR · 1 CL · ~9S"
/// — `ShotRuntimeSummary.railLabel(compact:)`, the SAME formatter the v1
/// shot rail reads, abbreviated. The runtime is the summary's estimate and
/// inherits its documented approximations (nominal segment lengths,
/// window-excluded copies); the stage header's plan-walk figure is the
/// precise one.
func sceneLedgerLine(
    shot: ProjectShot,
    frameLookup: [String: ProjectLensHeroImage],
    mediaLookup: [String: MediaItemRecord]
) -> String {
    let summary = shotRuntimeSummary(shot: shot, frameLookup: frameLookup, mediaLookup: mediaLookup)
    return summary.railLabel(segmentSeconds: shot.renderStack.segmentSeconds, compact: true)
}

/// Live render progress for a rail card: the fraction of segment clips that
/// have landed, plus the artifact's own progress sentence. nil unless THIS
/// scene is the active render with a persisted artifact row — before the row
/// exists there is nothing honest to draw, and an unknown segment total
/// reports 0 (starting), never a full bar.
func sceneRenderProgress(
    shot: ProjectShot,
    activeShotRenderId: String
) -> (fraction: Double, label: String)? {
    guard !activeShotRenderId.isEmpty, activeShotRenderId == shot.shotId,
          let artifact = shot.renderVersions.first(where: { $0.status == "generating" })
            ?? shot.renderArtifact else {
        return nil
    }
    let landed = max(
        artifact.clipPaths.filter { !$0.trimmed.isEmpty }.count,
        artifact.segmentClips.filter { !$0.clipPath.trimmed.isEmpty }.count
    )
    guard artifact.segmentCount > 0 else {
        return (0, artifact.progressText.trimmed)
    }
    let fraction = Double(landed) / Double(artifact.segmentCount)
    return (min(max(fraction, 0), 1), artifact.progressText.trimmed)
}

// MARK: - Guided stage (the cold-start journey)

/// THE GUIDED STAGE LAW: with zero Scenes the stage is the journey surface —
/// one state, one primary action — and the moment a Scene exists the stage is
/// its normal cut-strip self (`.normalStage`) and never looks back.
enum ScenesV2StageSpotlightState: Equatable {
    /// No Story yet — the journey starts on the Story tab.
    case storyNotReady
    /// Story saved, no Scene Plan — offer Plan Frames (retry after a failure).
    case readyToPlan(retry: Bool)
    /// Scene Plan generation is running; `refresh` when an existing plan is being
    /// re-planned from a changed Story rather than composed for the first time.
    case planning(refresh: Bool)
    /// Plans exist, nothing rendered — spotlight the focused planned frame.
    case artDirect(focusImageId: String)
    /// At least one rendered frame and still zero Scenes.
    case startFirstScene
    /// A lens with nothing planned and nothing rendered — offer a blank frame.
    case emptyPlan
    /// Scenes exist — SceneBoxView owns the stage.
    case normalStage
}

func scenesV2StageSpotlightState(
    hasLens: Bool,
    isGoalReady: Bool,
    isPlanningActive: Bool,
    isRefreshActive: Bool = false,
    planFailed: Bool,
    plannedImageIdsInPlanOrder: [String],
    renderedFrameCount: Int,
    sceneCount: Int
) -> ScenesV2StageSpotlightState {
    if isPlanningActive { return .planning(refresh: false) }
    if isRefreshActive { return .planning(refresh: true) }
    if !hasLens {
        return isGoalReady ? .readyToPlan(retry: planFailed) : .storyNotReady
    }
    if sceneCount > 0 { return .normalStage }
    if renderedFrameCount > 0 { return .startFirstScene }
    if let first = plannedImageIdsInPlanOrder.first { return .artDirect(focusImageId: first) }
    return .emptyPlan
}

/// THE CHARACTER SHEET READINESS LAW: nil when the roster is empty or every
/// character anchors on a sheet; otherwise a headline and a detail naming who
/// still renders from text alone. Not dismissible — it disappears when satisfied.
func scenesV2CharacterSheetReadiness(
    characters: [(name: String, hasSheet: Bool)]
) -> (headline: String, detail: String, missingNames: [String])? {
    let named = characters.filter { !$0.name.trimmed.isEmpty }
    guard !named.isEmpty else { return nil }
    let missing = named.filter { !$0.hasSheet }.map { $0.name.trimmed }
    guard !missing.isEmpty else { return nil }
    let listed = missing.prefix(3).joined(separator: ", ")
    let overflow = missing.count - min(3, missing.count)
    let names = overflow > 0 ? "\(listed) and \(overflow) more" : listed
    if missing.count == named.count {
        return ("No character sheets yet", "Frames will render \(names) from text alone.", missing)
    }
    let sheeted = named.count - missing.count
    return ("\(sheeted) of \(named.count) characters have sheets", "\(names) still render from text.", missing)
}

/// The secondary affordance a stale plan earns beside the stage's one primary action.
enum ScenesV2PlanStaleAction: Equatable {
    case quiet
    case refreshSuggestions
    case planMoreFrames
}

/// THE STALE NOTE: a quiet line when the Story moved past the plan. nil when the
/// plan is fresh or nothing is worth saying. Refreshing → progress copy, no action;
/// failed → retry; every frame rendered → offer to plan more; otherwise nil (the
/// automatic refresh handles un-started plans without a word).
func scenesV2PlanStaleNote(
    staleness: FramePlanStaleness,
    decision: FramePlanRefreshDecision,
    isRefreshing: Bool,
    refreshFailed: Bool
) -> (text: String, action: ScenesV2PlanStaleAction)? {
    if isRefreshing { return ("Story changed — refreshing suggestions…", .quiet) }
    if refreshFailed { return ("Frame refresh failed", .refreshSuggestions) }
    guard staleness != .fresh else { return nil }
    if decision == .offerPlanMore { return ("Story changed since these Frames were planned", .planMoreFrames) }
    return nil
}

/// v2 pool frame hygiene: soft-disabled frames and plan-fulfillment
/// candidates never reach the pool — a plan is not placeable material, it is
/// an intention the guided stage owns. Genuinely in-flight `generating` takes
/// STAY (they will become placeable, and their spinner is honest). Applied
/// only at the v2 call site; `projectPoolInputs` itself is shared with v1 and
/// stays untouched.
func scenesV2PoolSourceFrames(_ frames: [ProjectLensHeroImage]) -> [ProjectLensHeroImage] {
    frames.filter { !$0.disabled && !$0.isPlanFulfillmentCandidate }
}

/// Fulfillment candidates in plan order (imageIndex, then imageId for
/// deterministic ties) — the spotlight filmstrip's spine.
func scenesV2PlannedFramesInPlanOrder(_ frames: [ProjectLensHeroImage]) -> [ProjectLensHeroImage] {
    frames
        .filter(\.isPlanFulfillmentCandidate)
        .sorted { lhs, rhs in
            if lhs.imageIndex == rhs.imageIndex { return lhs.imageId < rhs.imageId }
            return lhs.imageIndex < rhs.imageIndex
        }
}

/// THE SUGGESTION PRIORITY LAW: sheet-driven suggestions lead (newest batch
/// first, plan order inside a batch), then every other fulfillment candidate in
/// plan order. ISO-8601 stamps sort lexically.
func scenesV2SuggestedFramesInPriorityOrder(_ frames: [ProjectLensHeroImage]) -> [ProjectLensHeroImage] {
    let planned = scenesV2PlannedFramesInPlanOrder(frames)
    let suggested = planned.filter(\.isSheetSuggestion).sorted { lhs, rhs in
        if lhs.suggestedAt == rhs.suggestedAt {
            if lhs.imageIndex == rhs.imageIndex { return lhs.imageId < rhs.imageId }
            return lhs.imageIndex < rhs.imageIndex
        }
        return lhs.suggestedAt > rhs.suggestedAt
    }
    return suggested + planned.filter { !$0.isSheetSuggestion }
}

// MARK: - Suggested Frames (SCENES v2)

/// One cast name on a suggestion card, whether that character anchors on a sheet,
/// and THE AVATAR LAW's pick: the first source image (thumbnail, else file), else
/// the active sheet's, else "" — the card then draws a ghost circle with `initial`.
struct ScenesV2CastMark: Hashable, Sendable {
    var name: String
    var hasSheet: Bool
    var avatarImagePath: String = ""
    var avatarIsSheet: Bool = false
    /// The character has source photos to render from when no sheet exists.
    var hasSources: Bool = false

    var initial: String { String(name.trimmed.prefix(1)).uppercased() }
}

func scenesV2CastAvatarSource(
    referenceMediaIds: [String],
    activeSheetMediaId: String?,
    items: [MediaItemRecord]
) -> (path: String, isSheet: Bool) {
    for id in referenceMediaIds {
        guard let item = items.first(where: { $0.mediaId == id }),
              item.kind == .image, !item.isRosterCompositeSheet else { continue }
        return (item.thumbnailPath.trimmed.nilIfEmpty ?? item.path, false)
    }
    if let sheetId = activeSheetMediaId?.trimmed.nilIfEmpty,
       let sheet = items.first(where: { $0.mediaId == sheetId && $0.isCharacterSheet }) {
        return (sheet.thumbnailPath.trimmed.nilIfEmpty ?? sheet.path, true)
    }
    return ("", false)
}

/// A suggestion is a moment a character minted, or a plan character study.
enum ScenesV2SuggestionKind: Hashable, Sendable {
    case moment
    case study
}

func scenesV2SuggestionKind(imageKind: String, isSheetSuggestion: Bool) -> ScenesV2SuggestionKind {
    if isSheetSuggestion { return .moment }
    return LensImageTaxonomyKind.normalized(imageKind) == LensImageTaxonomyKind.characterImage ? .study : .moment
}

/// THE CHARACTER SUGGESTION LAW (SCENES v2): a suggestion is a fulfillment
/// candidate that a character minted (a moment) or that IS a character (a plan
/// study with a roster link). Environment plates and object studies never appear
/// in v2 (V1 untouched).
func scenesV2IsCharacterSuggestion(_ row: ProjectLensHeroImage) -> Bool {
    guard row.isPlanFulfillmentCandidate else { return false }
    if row.isSheetSuggestion { return true }
    return LensImageTaxonomyKind.normalized(row.imageKind) == LensImageTaxonomyKind.characterImage
        && !row.characterId.trimmed.isEmpty
}

/// Newest moment batch first, plan order inside a batch, then plan studies in plan order.
func scenesV2CharacterSuggestions(_ frames: [ProjectLensHeroImage]) -> [ProjectLensHeroImage] {
    scenesV2SuggestedFramesInPriorityOrder(frames.filter(scenesV2IsCharacterSuggestion))
}

/// THE RAIL VISIBILITY LAW: the scene rail appears once any Scene has a
/// completed render; until then the stage leads alone.
func scenesV2RailIsVisible(badges: [SceneRenderBadge]) -> Bool {
    badges.contains { $0 == .ready || $0 == .parked }
}

/// What SCENES says when the suggestion set is empty: the way in (CHARACTERS),
/// a running job, or the explicit action. nil while cards exist.
enum ScenesV2SuggestionNotice: Equatable {
    case createCharacter
    case suggesting(line: String)
    case suggestNow
}

func scenesV2SuggestionNotice(
    hasSuggestableCharacters: Bool,
    suggestingNames: [String],
    suggestionCount: Int
) -> ScenesV2SuggestionNotice? {
    let names = suggestingNames.map(\.trimmed).filter { !$0.isEmpty }
    if !names.isEmpty {
        let who: String
        switch names.count {
        case 1: who = names[0]
        case 2: who = "\(names[0]) and \(names[1])"
        default: who = "\(names.count) characters"
        }
        return .suggesting(line: "Suggesting Frames for \(who)…")
    }
    if suggestionCount > 0 { return nil }
    return hasSuggestableCharacters ? .suggestNow : .createCharacter
}

/// The one sentence SCENES says when no character can drive suggestions yet.
let scenesV2CreateCharacterNotice = "No characters with reference images yet — create one in CHARACTERS and SCENES will suggest Frames for them."

/// A suggestion card's copy, derived once per planned row by the workbench.
struct ScenesV2SuggestionCardModel: Hashable, Identifiable, Sendable {
    var imageId: String
    var title: String
    var beat: String
    var eyebrow: String
    var brief: String
    var cast: [ScenesV2CastMark]
    var isFailed: Bool
    var failureLine: String
    var isNew: Bool
    /// The page's one filled brass element rides the first card in priority order.
    var isPrimary: Bool
    var kind: ScenesV2SuggestionKind = .moment
    var id: String { imageId }
}

/// The v1 card's label split (" · " separates title from the beat), with one
/// adjustment: "Character · Mara Vey" surfaces the NAME as the title. Shared by the
/// spotlight plate and the pool cards so both agree.
func scenesV2SuggestionTitle(label: String) -> (title: String, beat: String) {
    let parts = label.components(separatedBy: " · ")
    guard parts.count > 1 else {
        return (label.trimmed.nilIfEmpty ?? "Planned Frame", "")
    }
    let first = parts[0].trimmed
    let rest = parts.dropFirst().joined(separator: " · ").trimmed
    if ["character", "object"].contains(first.lowercased()) {
        return (rest.nilIfEmpty ?? first, "")
    }
    return (first.nilIfEmpty ?? "Planned Frame", rest)
}

/// The brief a card shows: the authored prompt (else the compiled one) with
/// @mention tokens stripped to plain names and whitespace collapsed.
func scenesV2SuggestionBrief(sourcePrompt: String, prompt: String) -> String {
    let raw = sourcePrompt.trimmed.nilIfEmpty ?? prompt.trimmed
    let stripped = RosterMentionResolver.strippingMentionTokens(raw)
    return stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// The card eyebrow: a sheet-driven suggestion names its character, every plan row
/// names its beat, and a failed one says so. Data stays as-is; the plate label
/// uppercases.
func scenesV2SuggestionEyebrow(beat: String, forCharacterName: String, isFailed: Bool, isStudy: Bool = false) -> String {
    let name = forCharacterName.trimmed
    let lead = isStudy ? "Study" : (name.isEmpty ? "Planned" : "For \(name)")
    if isFailed { return "\(lead) · Failed" }
    let cleanBeat = beat.trimmed
    return cleanBeat.isEmpty ? lead : "\(lead) · \(cleanBeat)"
}

/// The caption under RENDER: stack and price — "unpriced" is never $0 — and the
/// honest line when no stack is configured.
func scenesV2RenderCaption(stackLabel: String, priceNote: String) -> String {
    let label = stackLabel.trimmed
    guard !label.isEmpty else { return "No render stack configured" }
    let price = priceNote.trimmed
    return "\(label) · \(price.isEmpty ? "unpriced" : price)"
}

/// A failed suggestion's line, in words beside RETRY.
func scenesV2SuggestionFailureLine(errorMessage: String) -> String {
    let reason = errorMessage.trimmed
    return "Render failed — \(reason.isEmpty ? "the provider refused" : reason)"
}

/// The `.box` empty-scene hint names what actually sits below the stage.
func scenesV2EmptySceneHint(suggestionCount: Int, renderedCount: Int) -> String {
    if renderedCount > 0 {
        return "Drag a Frame from the pool below — or hover one and click ADD TO SCENE."
    }
    if suggestionCount > 0 {
        return "Render one of the \(suggestionCount) suggested Frame\(suggestionCount == 1 ? "" : "s") below, then drop it here."
    }
    return "Drag Frames or Footage from the pool below — or click + to pick material or render a new Frame."
}

/// The whisper's one trailing slot, by precedence: an actionable stale note, a
/// running suggestion job (a real spinner), then unseen sheet suggestions.
enum ScenesV2WhisperTrailing: Equatable {
    case none
    case staleNote(text: String, action: ScenesV2PlanStaleAction)
    case suggesting(line: String)
    case newSuggestions(line: String)
}

func scenesV2WhisperTrailing(
    staleNote: (text: String, action: ScenesV2PlanStaleAction)?,
    suggestingNames: [String],
    unseenSuggestions: [(characterName: String, count: Int)]
) -> ScenesV2WhisperTrailing {
    if let staleNote { return .staleNote(text: staleNote.text, action: staleNote.action) }
    let names = suggestingNames.map(\.trimmed).filter { !$0.isEmpty }
    if !names.isEmpty {
        let who: String
        switch names.count {
        case 1: who = names[0]
        case 2: who = "\(names[0]) and \(names[1])"
        default: who = "\(names.count) characters"
        }
        return .suggesting(line: "Suggesting Frames for \(who)…")
    }
    let unseen = unseenSuggestions.filter { $0.count > 0 && !$0.characterName.trimmed.isEmpty }
    guard !unseen.isEmpty else { return .none }
    let total = unseen.reduce(0) { $0 + $1.count }
    let frames = "\(total) NEW FRAME\(total == 1 ? "" : "S")"
    if unseen.count == 1 {
        return .newSuggestions(line: "\(frames) FOR \(unseen[0].characterName.trimmed.uppercased())")
    }
    return .newSuggestions(line: "\(frames) FOR \(unseen.count) CHARACTERS")
}

/// v2 pool kind hygiene: derived identity and project kinds are not source
/// material. Deliberately narrower than `isGeneratedMedia`, which would also eat
/// placeable video-chain clips and collected shot frames. Applied by the v2
/// caller BEFORE `projectPoolInputs`; the shared law stays untouched.
func scenesV2SourceMaterialItems(_ items: [MediaItemRecord]) -> [MediaItemRecord] {
    let excluded: Set<String> = [
        "character_sheet", "character_source", "roster_composite_sheet",
        "roster_character_render", "project_sheet", "terrain_map", "terrain_map_region",
    ]
    return items.filter { !excluded.contains(($0.derivativeKind ?? "").trimmed.lowercased()) }
}

/// A global engine status shows on SCENES only once it changed after the tab
/// appeared — the previous tab's last word never leaks in.
func scenesV2ScopedStatus(current: String, baseline: String) -> String {
    current == baseline ? "" : current
}

/// What a ready pool tile offers on hover (and in its menu) beside dragging:
/// start a Scene, add to the staged Scene, or the honest refusal when the staged
/// Scene is rendered and immutable.
enum ScenesV2TileAction: Equatable {
    case startScene
    case addToScene(name: String)
    case sceneLocked(name: String)

    var title: String {
        switch self {
        case .startScene: return "START A SCENE"
        case .addToScene(let name): return "ADD TO \(name.uppercased())"
        case .sceneLocked(let name): return "\(name.uppercased()) IS RENDERED"
        }
    }

    var menuTitle: String {
        switch self {
        case .startScene: return "Start New Scene with This"
        case .addToScene(let name): return "Add to \(name)"
        case .sceneLocked(let name): return "\(name) is rendered — NEW VERSION to edit it"
        }
    }

    var isEnabled: Bool {
        if case .sceneLocked = self { return false }
        return true
    }
}

func scenesV2TileAction(stagedSceneName: String, stagedSceneIsLocked: Bool) -> ScenesV2TileAction {
    let name = stagedSceneName.trimmed
    guard !name.isEmpty else { return .startScene }
    return stagedSceneIsLocked ? .sceneLocked(name: name) : .addToScene(name: name)
}

/// Seen-ribbon memory keeps only ids that still exist as suggestions.
func scenesV2PrunedSeenSuggestionIds(seen: Set<String>, live: Set<String>) -> Set<String> {
    seen.intersection(live)
}

/// The rail card's poster fallback: an empty Scene says so once — the ledger line
/// already counts frames.
func scenesV2RailPosterFallback(entryCount: Int) -> String {
    entryCount == 0 ? "EMPTY" : "\(entryCount) FR"
}

/// THE WHISPER LINE, split for its two voices: the claim (else title, else
/// "Scene Plan") speaks in the display italic, the honest counts in the
/// archive caps. nil with no lens: the stage carries all guidance then.
func scenesV2WhisperParts(
    hasLens: Bool,
    claim: String,
    fallbackTitle: String,
    plannedCount: Int,
    renderedCount: Int,
    sceneCount: Int
) -> (headline: String, counts: String)? {
    guard hasLens else { return nil }
    var headline = claim.trimmed
    if headline.isEmpty { headline = fallbackTitle.trimmed }
    if headline.isEmpty { headline = "Scene Plan" }
    var parts: [String] = []
    if plannedCount > 0 {
        parts.append("\(plannedCount) suggested")
    }
    parts.append("\(renderedCount) rendered")
    if sceneCount > 0 {
        parts.append("\(sceneCount) Scene\(sceneCount == 1 ? "" : "s")")
    }
    return (headline, parts.joined(separator: " · "))
}

func scenesV2WhisperLine(
    hasLens: Bool,
    claim: String,
    fallbackTitle: String,
    plannedCount: Int,
    renderedCount: Int,
    sceneCount: Int
) -> String {
    guard let parts = scenesV2WhisperParts(
        hasLens: hasLens,
        claim: claim,
        fallbackTitle: fallbackTitle,
        plannedCount: plannedCount,
        renderedCount: renderedCount,
        sceneCount: sceneCount
    ) else { return "" }
    return "\(parts.headline) · \(parts.counts)"
}

/// Chapter chips for the spotlight's story header: full-snapshot scene titles
/// win, the signature's function sequence is the fallback (the v1 landing
/// card's law, replicated so v1 stays untouched).
func scenesV2StoryChapterTitles(
    snapshotTitlesInOrder: [String],
    signatureSceneFunctions: [String]
) -> [String] {
    let titles = snapshotTitlesInOrder.map { $0.trimmed }.filter { !$0.isEmpty }
    if !titles.isEmpty { return titles }
    return signatureSceneFunctions.map { $0.trimmed }.filter { !$0.isEmpty }
}

/// The empty stage plate speaks only for scenes-exist states now (the
/// 0-scene states belong to the guided stage spotlight).
func scenesV2EmptyStagePlateCopy(allScenesMarkedReady: Bool) -> String {
    allScenesMarkedReady
        ? "Every Scene is marked ready — click a rail card to revisit one"
        : "Click a Scene in the rail to stage it"
}

// MARK: - Palette-reactive stage accent

/// THE PALETTE ACCENT LAW: the guided stage carries its film's colors — up to
/// three swatches from the Scene Plan's palette, first-listed first, valid
/// 6-hex-digit values only (the shared `canonColor(fromHex:)` parse rule),
/// deduped by hex so a repeated color never doubles a dot.
func scenesV2StageAccentSwatches(_ palette: [LensColorSwatch]) -> [LensColorSwatch] {
    var seen = Set<String>()
    var accents: [LensColorSwatch] = []
    for swatch in palette {
        let hex = swatch.hex.trimmed.replacingOccurrences(of: "#", with: "").uppercased()
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit), seen.insert(hex).inserted else { continue }
        accents.append(swatch)
        if accents.count == 3 { break }
    }
    return accents
}

// MARK: - Media viewer Analyze state

/// EARNED CTA LAW: an analyzed image stops offering Analyze. A saved-but-stale
/// observation (older analyzer version) earns "Re-analyze" instead.
enum MediaAnalyzeButtonState: Equatable {
    case hidden
    case analyze
    case reanalyze
}

func mediaAnalyzeButtonState(hasObservation: Bool, isCurrentVersion: Bool) -> MediaAnalyzeButtonState {
    guard hasObservation else { return .analyze }
    return isCurrentVersion ? .hidden : .reanalyze
}

// MARK: - Conveyor (mark ready → next scene)

/// After the staged scene is marked ready, the stage loads the next scene
/// that still needs work: scan VISIBLE order forward from the departed scene
/// (wrapping), skipping scenes already in the Output sequence and scenes in
/// `boxedShotIds` (the single-stage caller passes the selection; the name
/// survives from the two-box era so the tested law needn't move). nil = no
/// unready scene left — the stage empties honestly. Also the UP NEXT hint:
/// called with the CURRENT selection as departed, it names the card the
/// conveyor would load.
func nextConveyorSceneId(
    visibleShotIds: [String],
    departedShotId: String,
    readyShotIds: Set<String>,
    boxedShotIds: [String]
) -> String? {
    guard !visibleShotIds.isEmpty else { return nil }
    let boxed = Set(boxedShotIds)
    let start = visibleShotIds.firstIndex(of: departedShotId).map { $0 + 1 } ?? 0
    for offset in 0..<visibleShotIds.count {
        let candidate = visibleShotIds[(start + offset) % visibleShotIds.count]
        if candidate == departedShotId { continue }
        if readyShotIds.contains(candidate) { continue }
        if boxed.contains(candidate) { continue }
        return candidate
    }
    return nil
}
