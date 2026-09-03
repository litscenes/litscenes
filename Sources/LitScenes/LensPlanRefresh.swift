import Foundation

// MARK: - Spread law

/// The composition must sample four disparate story moments: exactly four scenes
/// across 2-4 areas, each carrying a distinct canonical story beat.
enum LensCompositionSpread {
    static let canonicalBeats = ["opening", "rising", "turn", "ending"]
    static let requiredSceneCount = 4

    /// nil when the areas satisfy the spread rule; otherwise one sentence the
    /// composition model can act on when the call is retried.
    static func validationError(areas: [LensArea]) -> String? {
        for (index, area) in areas.enumerated() where area.scenes.filter({ !$0.isEmpty }).isEmpty {
            let title = area.title.trimmed.nilIfEmpty ?? "Area \(index + 1)"
            return "Area \"\(title)\" has no scenes; every area needs 1 or 2 scenes."
        }
        let normalizedAreas = areas.enumerated().map { $0.element.normalized(order: $0.offset) }
        let scenes = normalizedAreas.flatMap { $0.scenes.filter(\.enabled) }
        if scenes.count != requiredSceneCount {
            return "The composition returned \(scenes.count) scenes; exactly \(requiredSceneCount) child scenes are required across 2-4 areas."
        }
        let beats = scenes.map { $0.storyBeat.trimmed.lowercased() }
        if beats.sorted() != canonicalBeats.sorted() {
            let listed = beats.map { $0.isEmpty ? "(none)" : $0 }.joined(separator: ", ")
            return "story_beat values were [\(listed)]; use \(canonicalBeats.joined(separator: ", ")) exactly once each."
        }
        return nil
    }

    /// Deterministic repair when the retry also misses: drop scene-less areas, trim
    /// to four scenes in plan order, keep valid distinct beats, and assign the
    /// missing canonical beats in order. Never invents scenes.
    static func repaired(areas: [LensArea]) -> [LensArea] {
        var budget = requiredSceneCount
        var kept: [LensArea] = []
        for (index, area) in areas.enumerated() {
            guard budget > 0, !area.scenes.filter({ !$0.isEmpty }).isEmpty else { continue }
            var normalized = area.normalized(order: index)
            normalized.scenes = Array(normalized.scenes.prefix(budget))
            budget -= normalized.scenes.count
            kept.append(normalized)
        }
        var used = Set<String>()
        for areaIndex in kept.indices {
            for sceneIndex in kept[areaIndex].scenes.indices {
                let beat = kept[areaIndex].scenes[sceneIndex].storyBeat.trimmed.lowercased()
                if canonicalBeats.contains(beat), !used.contains(beat) {
                    used.insert(beat)
                    kept[areaIndex].scenes[sceneIndex].storyBeat = beat
                } else {
                    kept[areaIndex].scenes[sceneIndex].storyBeat = ""
                }
            }
        }
        var pending = canonicalBeats.filter { !used.contains($0) }
        for areaIndex in kept.indices {
            for sceneIndex in kept[areaIndex].scenes.indices where kept[areaIndex].scenes[sceneIndex].storyBeat.isEmpty {
                guard !pending.isEmpty else { break }
                kept[areaIndex].scenes[sceneIndex].storyBeat = pending.removeFirst()
            }
        }
        return kept
    }
}

// MARK: - Staleness

/// Whether the frame plan still describes the Story it was composed from.
enum FramePlanStaleness: Equatable {
    case fresh
    case stale
    /// The plan predates provenance stamping; treated as stale so it refreshes once.
    case unknownProvenance
}

func framePlanStaleness(storedFingerprint: String?, activeFingerprint: String) -> FramePlanStaleness {
    guard let stored = storedFingerprint?.trimmed.nilIfEmpty else { return .unknownProvenance }
    return stored == activeFingerprint.trimmed ? .fresh : .stale
}

enum FramePlanRefreshDecision: Equatable {
    case none
    /// Un-started suggestions exist: replace them in place from the current Story.
    case autoReplan
    /// Every planned frame rendered; the Story moved on — offer to plan more.
    case offerPlanMore
}

func framePlanRefreshDecision(
    staleness: FramePlanStaleness,
    purePlanCount: Int,
    renderedCount: Int
) -> FramePlanRefreshDecision {
    guard staleness != .fresh else { return .none }
    if purePlanCount > 0 { return .autoReplan }
    if renderedCount > 0 { return .offerPlanMore }
    return .none
}

// MARK: - Merge law

/// Folds a freshly composed plan into a lens's existing hero rows. Rendered,
/// generating, and attempted rows are records and stay verbatim; never-started
/// plans are intentions and are replaced in place so their identities (imageId,
/// imageIndex, route key) survive for the stage, the Frame Creator, and the pool.
enum LensPlanMerge {
    enum Mode: Equatable {
        /// Replace never-started plans in place; append what does not fit; drop stale leftovers.
        case replacePurePlans
        /// Keep every existing row; only append fresh rows nothing already covers.
        case appendOnly
    }

    struct Outcome: Equatable {
        var heroImages: [ProjectLensHeroImage]
        var replacedImageIds: [String] = []
        var appendedImageIds: [String] = []
        var droppedImageIds: [String] = []
    }

    static func merged(
        existing: [ProjectLensHeroImage],
        fresh: [ProjectLensHeroImage],
        mediaVersionId: String,
        mode: Mode,
        now: String
    ) -> Outcome {
        func isInVersion(_ row: ProjectLensHeroImage) -> Bool {
            ProjectLens.mediaVersionId(fromRouteKey: row.sourceRouteKey) == mediaVersionId
        }
        let otherVersions = existing.filter { !isInVersion($0) }
        let versionRows = existing.filter(isInVersion)
        let keep: [ProjectLensHeroImage]
        var free: [LensConceptCategory: [ProjectLensHeroImage]] = [:]
        switch mode {
        case .replacePurePlans:
            // Sheet-driven suggestions are anchored to a character that still
            // exists, not to the Story text that moved: kept, never a free slot.
            keep = versionRows.filter { !$0.isPurePlan || $0.isSheetSuggestion }
            for row in versionRows.filter({ $0.isPurePlan && !$0.isSheetSuggestion }).sorted(by: { $0.imageIndex < $1.imageIndex }) {
                free[LensConceptCategory.category(for: row), default: []].append(row)
            }
        case .appendOnly:
            keep = versionRows
        }

        let coveredSceneIds = Set(keep.map(\.sceneId).filter { !$0.isEmpty })
        let coveredCharacterIds = Set(
            keep.filter { LensConceptCategory.category(for: $0) == .characters }
                .map(\.characterId)
                .filter { !$0.isEmpty }
        )
        let coveredObjectLabels = Set(
            keep.filter { LensConceptCategory.category(for: $0) == .objects }
                .map { $0.label.trimmed.lowercased() }
                .filter { !$0.isEmpty }
        )

        var nextIndex = (existing.map(\.imageIndex).max() ?? -1) + 1
        var replaced: [ProjectLensHeroImage] = []
        var appended: [ProjectLensHeroImage] = []
        var replacedIds: [String] = []
        var appendedIds: [String] = []

        for candidate in fresh {
            let category = LensConceptCategory.category(for: candidate)
            switch category {
            case .scenery, .areas:
                if !candidate.sceneId.isEmpty, coveredSceneIds.contains(candidate.sceneId) { continue }
            case .characters:
                if !candidate.characterId.isEmpty, coveredCharacterIds.contains(candidate.characterId) { continue }
            case .objects:
                if coveredObjectLabels.contains(candidate.label.trimmed.lowercased()) { continue }
            case .legacy:
                break
            }
            if var slot = free[category]?.first {
                free[category]?.removeFirst()
                slot = replacing(slot, with: candidate, now: now)
                replaced.append(slot)
                replacedIds.append(slot.imageId)
            } else {
                var row = candidate
                row.imageIndex = nextIndex
                nextIndex += 1
                row.updatedAt = now
                appended.append(row.normalized())
                appendedIds.append(row.imageId)
            }
        }
        let dropped = free.values.flatMap { $0 }.map(\.imageId).sorted()
        let merged = (otherVersions + keep + replaced + appended).sorted { lhs, rhs in
            if lhs.imageIndex == rhs.imageIndex { return lhs.provider < rhs.provider }
            return lhs.imageIndex < rhs.imageIndex
        }
        return Outcome(
            heroImages: merged,
            replacedImageIds: replacedIds,
            appendedImageIds: appendedIds,
            droppedImageIds: dropped
        )
    }

    /// The in-place swap: the slot keeps its identity and render preferences, the
    /// candidate supplies the plan. A scenery row homes on itself.
    private static func replacing(
        _ slot: ProjectLensHeroImage,
        with candidate: ProjectLensHeroImage,
        now: String
    ) -> ProjectLensHeroImage {
        var row = slot
        row.prompt = candidate.prompt
        row.sourcePrompt = candidate.sourcePrompt
        row.negativePrompt = candidate.negativePrompt
        row.label = candidate.label
        row.subject = candidate.subject
        row.areaId = candidate.areaId
        row.sceneId = candidate.sceneId
        row.areaImageId = candidate.areaImageId
        row.characterId = candidate.characterId
        row.imageKind = candidate.imageKind
        row.taxonomyEnabled = candidate.taxonomyEnabled
        row.styleAuthorities = candidate.styleAuthorities
        row.renderRecipe = candidate.renderRecipe
        row.sourceDependencies = candidate.sourceDependencies
        row.sourceRecipeId = candidate.sourceRecipeId
        row.sourceRecipeVersion = candidate.sourceRecipeVersion
        row.sourceAestheticIds = candidate.sourceAestheticIds
        row.homeSceneImageId = candidate.homeSceneImageId == candidate.imageId && !candidate.imageId.isEmpty
            ? slot.imageId
            : candidate.homeSceneImageId
        row.suggestedForCharacterId = candidate.suggestedForCharacterId
        row.suggestedAt = candidate.suggestedAt
        row.status = "queued"
        row.errorMessage = ""
        row.requestId = ""
        row.traceId = ""
        row.imagePath = ""
        row.generatedAt = ""
        row.promptEnrichmentModel = ""
        row.promptEnrichmentResponseId = ""
        row.promptEnrichmentTraceId = ""
        row.promptEnrichmentSummary = ""
        row.updatedAt = now
        return row.normalized()
    }
}

// MARK: - World replacement

extension LensBody {
    /// Swaps the composed world (areas, cast, objects, dressing) for a fresh one while
    /// every area and scene a kept frame points at survives ahead of the new areas.
    /// New ids that collide with old ones are re-minted so kept frames never drift
    /// onto a different place. Style, palette, title, and claim are untouched: a
    /// refresh replans frames, not the user's look. Scene-less areas are filtered
    /// explicitly because normalization would otherwise synthesize a frame for them.
    func replannedWorld(
        areas newAreas: [LensArea],
        castMembers newCast: [LensCastMember]?,
        objectConcepts newObjects: [LensObjectConcept]?,
        setDressing newDressing: [String]?,
        keptFrames: [ProjectLensHeroImage],
        planGoalVersionId: String,
        planGoalFingerprint: String
    ) -> LensBody {
        var value = self
        let oldAreas = (areas ?? []).enumerated().map { $0.element.normalized(order: $0.offset) }
        let reservedAreaIds = Set(oldAreas.map(\.areaId))
        let reservedSceneIds = Set(oldAreas.flatMap(\.scenes).map(\.sceneId))

        var incoming: [LensArea] = []
        for (index, area) in newAreas.enumerated() where !area.scenes.filter({ !$0.isEmpty }).isEmpty {
            var stamped = area.normalized(order: index)
            if reservedAreaIds.contains(stamped.areaId) {
                stamped.areaId = "\(stamped.areaId)_\(shortHash("\(planGoalFingerprint):\(stamped.areaId)", length: 6))"
            }
            stamped.scenes = stamped.scenes.map { scene in
                var renamed = scene
                if reservedSceneIds.contains(renamed.sceneId) {
                    renamed.sceneId = "\(renamed.sceneId)_\(shortHash("\(planGoalFingerprint):\(renamed.sceneId)", length: 6))"
                }
                return renamed
            }
            incoming.append(stamped)
        }

        let keptSceneIds = Set(keptFrames.map(\.sceneId).filter { !$0.isEmpty })
        var retained: [LensArea] = []
        for area in oldAreas {
            let survivingScenes = area.scenes.filter { keptSceneIds.contains($0.sceneId) }
            guard !survivingScenes.isEmpty else { continue }
            var kept = area
            kept.scenes = survivingScenes
            retained.append(kept)
        }
        value.areas = (retained + incoming).filter { !$0.scenes.isEmpty }

        let keptCharacterIds = Set(
            keptFrames
                .filter { LensConceptCategory.category(for: $0) == .characters }
                .map(\.characterId)
                .filter { !$0.isEmpty }
        )
        var members = newCast ?? []
        for member in castMembers ?? [] {
            guard let characterId = member.characterId, keptCharacterIds.contains(characterId) else { continue }
            let duplicate = members.contains { candidate in
                candidate.name.trimmed.lowercased() == member.name.trimmed.lowercased()
                    || (candidate.characterId != nil && candidate.characterId == member.characterId)
            }
            if !duplicate { members.append(member) }
        }
        value.castMembers = members.isEmpty ? nil : members
        if let newObjects { value.objectConcepts = newObjects.isEmpty ? nil : newObjects }
        if let newDressing { value.setDressingImagePrompts = newDressing.isEmpty ? nil : newDressing }
        value.planGoalVersionId = planGoalVersionId.trimmed.nilIfEmpty
        value.planGoalFingerprint = planGoalFingerprint.trimmed.nilIfEmpty
        return value
    }
}

// MARK: - Place pruning

/// Removes roster places that a replan retired, but only when nothing else holds
/// them: no reference images, and no surviving area or terrain pin points at them.
func prunedProjectPlaces(
    _ document: ProjectPlaceSetDocument,
    retiredPlaceIds: Set<String>,
    referencedPlaceIds: Set<String>,
    now: String
) -> ProjectPlaceSetDocument {
    var value = document
    let before = value.places.count
    value.places.removeAll { place in
        retiredPlaceIds.contains(place.placeId)
            && place.referenceMediaIds.isEmpty
            && !referencedPlaceIds.contains(place.placeId)
    }
    if value.places.count != before {
        value.updatedAt = now
    }
    return value
}

// MARK: - Planning inputs

/// Content-only lines describing analyzed Story Input media for the composition
/// model. Mood, palette, lighting, and material words stay out: they are style,
/// and the composition's HARD RULE keeps style out of content fields.
func lensPlanningMediaObservationLines(
    _ entries: [(filename: String, observation: ImageObservationResult)],
    limit: Int = 16
) -> [String] {
    func clip(_ text: String, _ max: Int = 160) -> String {
        let trimmed = text.trimmed
        guard trimmed.count > max else { return trimmed }
        return String(trimmed.prefix(max)).trimmed + "…"
    }
    var lines: [String] = []
    for entry in entries.prefix(max(0, limit)) {
        let observation = entry.observation
        var parts: [String] = []
        if !observation.plainCaption.trimmed.isEmpty { parts.append("caption=\(clip(observation.plainCaption))") }
        if !observation.setting.trimmed.isEmpty { parts.append("setting=\(clip(observation.setting))") }
        let places = uniqueNonEmpty(observation.placeCues)
        if !places.isEmpty { parts.append("place=\(clip(places.prefix(4).joined(separator: ", ")))") }
        let eras = uniqueNonEmpty(observation.eraCues)
        if !eras.isEmpty { parts.append("era=\(clip(eras.prefix(3).joined(separator: ", ")))") }
        let objects = uniqueNonEmpty(observation.objects)
        if !objects.isEmpty { parts.append("objects=\(clip(objects.prefix(6).joined(separator: ", ")))") }
        let activities = uniqueNonEmpty(observation.activities)
        if !activities.isEmpty { parts.append("activities=\(clip(activities.prefix(4).joined(separator: ", ")))") }
        if observation.peopleVisible {
            let count = observation.peopleCountEstimate.map(String.init) ?? "some"
            let roles = uniqueNonEmpty(observation.peopleRolesVisible).prefix(4).joined(separator: ", ")
            parts.append(roles.isEmpty ? "people=\(count)" : "people=\(count) (\(clip(roles, 120)))")
        } else {
            parts.append("people=none")
        }
        let meanings = uniqueNonEmpty(observation.motifCues)
        if !meanings.isEmpty { parts.append("meanings=\(clip(meanings.prefix(4).joined(separator: ", ")))") }
        let name = entry.filename.trimmed.nilIfEmpty ?? "image"
        lines.append("- \(name): \(parts.joined(separator: " | "))")
    }
    if entries.count > limit, limit > 0 {
        lines.append("- (+\(entries.count - limit) more analyzed Story Inputs)")
    }
    return lines
}

/// Story-cast members the roster does not know yet, as planning lines, so a
/// just-articulated character is castable before the roster sync lands.
func lensPlanningGoalCastLines(goalCast: GoalCastDocument, excludingNames: [String]) -> [String] {
    let excluded = Set(excludingNames.map { $0.trimmed.lowercased() }.filter { !$0.isEmpty })
    var lines: [String] = []
    for member in goalCast.members {
        let name = member.name.trimmed
        guard !name.isEmpty, !excluded.contains(name.lowercased()) else { continue }
        let identity = member.activeIdentity
        var line = "- \(name)"
        if !member.roleLabel.trimmed.isEmpty { line += " (\(member.roleLabel.trimmed))" }
        if !identity.visualDescription.trimmed.isEmpty { line += " — \(identity.visualDescription.trimmed)" }
        if !identity.essence.trimmed.isEmpty { line += " | essence: \(identity.essence.trimmed)" }
        lines.append(line)
    }
    return lines
}

// MARK: - Refresh progress

/// Progress of a Story-driven frame re-plan, for the v2 stage and status line.
struct LensPlanRefreshProgress: Equatable, Sendable {
    var title: String = ""
    var detail: String = ""
    var status: String = "idle"

    static let idle = LensPlanRefreshProgress()

    var isActive: Bool { status == "running" }
    var isFailed: Bool { status == "failed" }
}
