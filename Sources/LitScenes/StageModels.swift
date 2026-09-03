import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Stage set document (project-level, persisted)
//
// The STAGE / CUT / FINALS organizational layer over the flat shot timeline.
// A STAGE gathers unordered INPUTS (frames + footage — the loose "set"
// palette) and owns CUTs by reference. The cuts themselves remain ProjectShot
// rows in ProjectShotTimelineDocument — this document never copies or embeds
// them, so every render/narration/look subsystem keeps addressing shotId in
// the flat timeline untouched. Deleting an input never deletes a frame;
// inputs are references into the lens version store / media library.

/// One gathered reference on a stage: a frame (generated still) or footage
/// (video media). Exactly one of the two ids is set — same convention as
/// ShotFrameEntry.
struct StageInput: Codable, Hashable, Identifiable, Sendable {
    var inputId: String = ""
    var frameImageId: String = ""
    var clipMediaId: String = ""
    var addedAt: String = ""

    var id: String { inputId }

    var isClip: Bool { !clipMediaId.isEmpty }

    /// Stable identity of the REFERENCED asset (not the input row) — the
    /// dedupe key that keeps a palette from holding the same asset twice.
    var assetKey: String {
        isClip ? "clip:\(clipMediaId)" : "frame:\(frameImageId)"
    }

    private enum CodingKeys: String, CodingKey {
        case inputId
        case frameImageId
        case clipMediaId
        case addedAt
    }

    init(
        inputId: String = "",
        frameImageId: String = "",
        clipMediaId: String = "",
        addedAt: String = ""
    ) {
        self.inputId = inputId
        self.frameImageId = frameImageId
        self.clipMediaId = clipMediaId
        self.addedAt = addedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputId = try container.decodeIfPresent(String.self, forKey: .inputId) ?? ""
        frameImageId = try container.decodeIfPresent(String.self, forKey: .frameImageId) ?? ""
        clipMediaId = try container.decodeIfPresent(String.self, forKey: .clipMediaId) ?? ""
        addedAt = try container.decodeIfPresent(String.self, forKey: .addedAt) ?? ""
    }
}

/// One soft-deleted cut. The cut's timeline row (and every render it paid
/// for) survives untouched — the trash only records that it left its stage.
/// Restore-only in v1: no purge, matching the house rule that render
/// provenance is kept forever.
struct TrashedCut: Codable, Hashable, Identifiable, Sendable {
    var entryId: String = ""
    var cutId: String = ""
    var formerStageId: String = ""
    /// Display name captured at trash time so the row still reads after its
    /// stage is deleted.
    var formerStageName: String = ""
    /// Group recovery metadata when the trashed row was a combined parent.
    var formerGroupId: String = ""
    var combinedSourceCutIds: [String] = []
    var trashedAt: String = ""

    var id: String { entryId }

    private enum CodingKeys: String, CodingKey {
        case entryId
        case cutId
        case formerStageId
        case formerStageName
        case formerGroupId
        case combinedSourceCutIds
        case trashedAt
    }

    init(
        entryId: String = "",
        cutId: String = "",
        formerStageId: String = "",
        formerStageName: String = "",
        formerGroupId: String = "",
        combinedSourceCutIds: [String] = [],
        trashedAt: String = ""
    ) {
        self.entryId = entryId
        self.cutId = cutId
        self.formerStageId = formerStageId
        self.formerStageName = formerStageName
        self.formerGroupId = formerGroupId
        self.combinedSourceCutIds = combinedSourceCutIds
        self.trashedAt = trashedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryId = try container.decodeIfPresent(String.self, forKey: .entryId) ?? ""
        cutId = try container.decodeIfPresent(String.self, forKey: .cutId) ?? ""
        formerStageId = try container.decodeIfPresent(String.self, forKey: .formerStageId) ?? ""
        formerStageName = try container.decodeIfPresent(String.self, forKey: .formerStageName) ?? ""
        formerGroupId = try container.decodeIfPresent(String.self, forKey: .formerGroupId) ?? ""
        combinedSourceCutIds = try container.decodeIfPresent([String].self, forKey: .combinedSourceCutIds) ?? []
        trashedAt = try container.decodeIfPresent(String.self, forKey: .trashedAt) ?? ""
    }
}

/// Stage-only presentation group for an independent combined CUT. All ids
/// continue to reference ordinary ProjectShot rows; source rows are merely
/// collapsed from the visible stage order while the group is active.
struct StageCutGroup: Codable, Hashable, Identifiable, Sendable {
    var groupId: String = ""
    var stageId: String = ""
    var parentCutId: String = ""
    var sourceCutIds: [String] = []
    var createdAt: String = ""

    var id: String { groupId }

    private enum CodingKeys: String, CodingKey {
        case groupId, stageId, parentCutId, sourceCutIds, createdAt
    }

    init(
        groupId: String = "",
        stageId: String = "",
        parentCutId: String = "",
        sourceCutIds: [String] = [],
        createdAt: String = ""
    ) {
        self.groupId = groupId
        self.stageId = stageId
        self.parentCutId = parentCutId
        self.sourceCutIds = sourceCutIds
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId) ?? ""
        stageId = try container.decodeIfPresent(String.self, forKey: .stageId) ?? ""
        parentCutId = try container.decodeIfPresent(String.self, forKey: .parentCutId) ?? ""
        sourceCutIds = try container.decodeIfPresent([String].self, forKey: .sourceCutIds) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
    }

    func normalized() -> StageCutGroup {
        var value = self
        value.groupId = value.groupId.trimmed
        value.stageId = value.stageId.trimmed
        value.parentCutId = value.parentCutId.trimmed
        var seen: Set<String> = []
        value.sourceCutIds = value.sourceCutIds
            .map(\.trimmed)
            .filter { !$0.isEmpty && $0 != value.parentCutId && seen.insert($0).inserted }
        value.createdAt = value.createdAt.trimmed
        return value
    }
}

/// One picked cut on the FINALS shelf. Order = array position in the
/// document's `finals`.
struct StageFinalsEntry: Codable, Hashable, Identifiable, Sendable {
    var entryId: String = ""
    var cutId: String = ""
    var addedAt: String = ""

    var id: String { entryId }

    private enum CodingKeys: String, CodingKey {
        case entryId
        case cutId
        case addedAt
    }

    init(entryId: String = "", cutId: String = "", addedAt: String = "") {
        self.entryId = entryId
        self.cutId = cutId
        self.addedAt = addedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryId = try container.decodeIfPresent(String.self, forKey: .entryId) ?? ""
        cutId = try container.decodeIfPresent(String.self, forKey: .cutId) ?? ""
        addedAt = try container.decodeIfPresent(String.self, forKey: .addedAt) ?? ""
    }
}

/// A STAGE: a named gathering surface. `inputs` is an unordered palette
/// (array order = insertion; the UI assigns it no meaning). `cutIds` reference
/// ProjectShot rows in the flat shot timeline; every cut belongs to exactly
/// one stage (enforced by document normalization + engine reconciliation).
///
/// `cutIds` ORDER IS THE VERTICAL ORDER of the cut rows on the canvas and is
/// user-arrangeable (see `movingCut`). Nothing sorts it — `normalized()` only
/// dedupes. Order drives the rail numerals and COMBINE adjacency; it never
/// reaches a rendered artifact, and the film's order belongs to the FINALS
/// shelf, which keeps its own.
struct ProjectStage: Codable, Hashable, Identifiable, Sendable {
    var stageId: String = ""
    var name: String = ""
    var inputs: [StageInput] = []
    var cutIds: [String] = []
    var createdAt: String = ""
    var updatedAt: String = ""

    var id: String { stageId }

    private enum CodingKeys: String, CodingKey {
        case stageId
        case name
        case inputs
        case cutIds
        case createdAt
        case updatedAt
    }

    init(
        stageId: String = "",
        name: String = "",
        inputs: [StageInput] = [],
        cutIds: [String] = [],
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.stageId = stageId
        self.name = name
        self.inputs = inputs
        self.cutIds = cutIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stageId = try container.decodeIfPresent(String.self, forKey: .stageId) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        inputs = try container.decodeIfPresent([StageInput].self, forKey: .inputs) ?? []
        cutIds = try container.decodeIfPresent([String].self, forKey: .cutIds) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    /// Drops empty/duplicate references. First occurrence wins so palette
    /// order stays stable under repeated drops of the same asset.
    func normalized() -> ProjectStage {
        var value = self
        var seenAssets: Set<String> = []
        value.inputs = value.inputs.filter { input in
            guard !input.inputId.isEmpty else { return false }
            guard !input.frameImageId.isEmpty || !input.clipMediaId.isEmpty else { return false }
            return seenAssets.insert(input.assetKey).inserted
        }
        var seenCuts: Set<String> = []
        value.cutIds = value.cutIds.filter { !$0.isEmpty && seenCuts.insert($0).inserted }
        return value
    }

    func containsAsset(frameImageId: String = "", clipMediaId: String = "") -> Bool {
        inputs.contains { input in
            (!frameImageId.isEmpty && input.frameImageId == frameImageId)
                || (!clipMediaId.isEmpty && input.clipMediaId == clipMediaId)
        }
    }
}

struct ProjectStageSetDocument: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.stage_set.v0.2"
    static let documentType = "project_stage_set"

    var schemaVersion: String = ProjectStageSetDocument.schemaVersion
    var projectId: String = ""
    var stages: [ProjectStage] = []
    var finals: [StageFinalsEntry] = []
    var trashedCuts: [TrashedCut] = []
    var cutGroups: [StageCutGroup] = []
    /// THE FINALS REEL's film-level state, tolerant on old documents.
    /// `reelAudio` is the music bed: `ShotAudioRegion`s on the one
    /// `reel_music` lane, timed in reel OUTPUT seconds; never auto-deleted
    /// when the reel shortens (they clamp at play/export instead).
    /// `reelSeams` are authored per-adjacency crossfades, keyed by ordered
    /// entryId pair and reaped with their entries.
    var reelAudio: [ShotAudioRegion] = []
    var reelSeams: [ReelSeamStyle] = []
    var updatedAt: String = ""

    static func empty(projectId: String) -> ProjectStageSetDocument {
        ProjectStageSetDocument(projectId: projectId)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case stages
        case finals
        case trashedCuts
        case cutGroups
        case reelAudio
        case reelSeams
        case updatedAt
    }

    init(
        schemaVersion: String = ProjectStageSetDocument.schemaVersion,
        projectId: String = "",
        stages: [ProjectStage] = [],
        finals: [StageFinalsEntry] = [],
        trashedCuts: [TrashedCut] = [],
        cutGroups: [StageCutGroup] = [],
        reelAudio: [ShotAudioRegion] = [],
        reelSeams: [ReelSeamStyle] = [],
        updatedAt: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.stages = stages
        self.finals = finals
        self.trashedCuts = trashedCuts
        self.cutGroups = cutGroups
        self.reelAudio = reelAudio
        self.reelSeams = reelSeams
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        stages = try container.decodeIfPresent([ProjectStage].self, forKey: .stages) ?? []
        finals = try container.decodeIfPresent([StageFinalsEntry].self, forKey: .finals) ?? []
        trashedCuts = try container.decodeIfPresent([TrashedCut].self, forKey: .trashedCuts) ?? []
        cutGroups = ((try? container.decodeIfPresent([StageCutGroup].self, forKey: .cutGroups)) ?? nil) ?? []
        reelAudio = ((try? container.decodeIfPresent([ShotAudioRegion].self, forKey: .reelAudio)) ?? nil) ?? []
        reelSeams = ((try? container.decodeIfPresent([ReelSeamStyle].self, forKey: .reelSeams)) ?? nil) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    /// Self-repair that needs no outside knowledge: drops empty stage rows,
    /// keeps each STAGE id's first row and each cut in only its FIRST
    /// claiming stage, and dedupes finals by cut. (Repair against the actual
    /// shot timeline — dead cut references, orphan shots — lives in
    /// `reconciled(with:now:)`.)
    func normalized() -> ProjectStageSetDocument {
        var value = self
        var claimedCuts: Set<String> = []
        var seenStageIds: Set<String> = []
        value.stages = value.stages
            .map { $0.normalized() }
            .filter { !$0.stageId.isEmpty && seenStageIds.insert($0.stageId).inserted }
            .map { stage in
                var repaired = stage
                repaired.cutIds = repaired.cutIds.filter { claimedCuts.insert($0).inserted }
                return repaired
            }
        var seenFinalCuts: Set<String> = []
        value.finals = value.finals.filter { entry in
            guard !entry.entryId.isEmpty, !entry.cutId.isEmpty else { return false }
            return seenFinalCuts.insert(entry.cutId).inserted
        }
        // A cut both staged and trashed resolves to staged (the live claim
        // wins); trash rows also dedupe by cut.
        var seenTrashedCuts: Set<String> = []
        value.trashedCuts = value.trashedCuts.filter { row in
            guard !row.entryId.isEmpty, !row.cutId.isEmpty else { return false }
            guard !claimedCuts.contains(row.cutId) else { return false }
            return seenTrashedCuts.insert(row.cutId).inserted
        }
        var seenGroups: Set<String> = []
        var groupedParents: Set<String> = []
        value.cutGroups = value.cutGroups
            .map { $0.normalized() }
            .filter { group in
                guard !group.groupId.isEmpty,
                      !group.stageId.isEmpty,
                      !group.parentCutId.isEmpty,
                      group.sourceCutIds.count >= 2,
                      seenGroups.insert(group.groupId).inserted,
                      groupedParents.insert(group.parentCutId).inserted,
                      let stage = value.stages.first(where: { $0.stageId == group.stageId }),
                      stage.cutIds.contains(group.parentCutId),
                      group.sourceCutIds.allSatisfy(stage.cutIds.contains) else {
                    return false
                }
                return true
            }
        value.reelAudio = value.reelAudio
            .map { $0.normalized() }
            .filter { !$0.regionId.isEmpty && $0.durationSeconds > 0 }
        value.reelSeams = Self.reapedReelSeams(value.reelSeams, finals: value.finals)
        return value
    }

    /// Seams live exactly as long as BOTH their entries: removal, trash, and
    /// reconcile all route their finals changes through the one shared law
    /// (`reelSeamsReaped`, which the Output sequence document also applies).
    static func reapedReelSeams(
        _ seams: [ReelSeamStyle],
        finals: [StageFinalsEntry]
    ) -> [ReelSeamStyle] {
        reelSeamsReaped(seams, entryIds: Set(finals.map(\.entryId)))
    }

    // MARK: Lookups

    func stage(withId stageId: String) -> ProjectStage? {
        stages.first { $0.stageId == stageId }
    }

    func stage(containingCut cutId: String) -> ProjectStage? {
        stages.first { $0.cutIds.contains(cutId) }
    }

    func group(parentCutId: String) -> StageCutGroup? {
        cutGroups.first { $0.parentCutId == parentCutId }
    }

    func group(containingSourceCutId cutId: String) -> StageCutGroup? {
        cutGroups.first { $0.sourceCutIds.contains(cutId) }
    }

    var hiddenCombinedSourceCutIds: Set<String> {
        Set(cutGroups.flatMap(\.sourceCutIds))
    }

    func visibleCutIds(in stage: ProjectStage) -> [String] {
        let hidden = hiddenCombinedSourceCutIds
        return stage.cutIds.filter { !hidden.contains($0) }
    }

    func stages(containingFrame frameImageId: String) -> [ProjectStage] {
        guard !frameImageId.isEmpty else { return [] }
        return stages.filter { $0.containsAsset(frameImageId: frameImageId) }
    }

    /// Frames referenced by ANY stage's inputs — the complement is the
    /// BACKLOT (derived, never stored).
    var stagedFrameImageIds: Set<String> {
        Set(stages.flatMap { $0.inputs.compactMap { $0.frameImageId.isEmpty ? nil : $0.frameImageId } })
    }

    // MARK: Pure mutations — stages

    func appendingStage(name: String, now: String) -> (document: ProjectStageSetDocument, stageId: String) {
        var value = self
        let stageId = "stage_\(shortHash("\(projectId):\(value.stages.count):\(now):\(UUID().uuidString)", length: 12))"
        value.stages.append(ProjectStage(stageId: stageId, name: name.trimmed, createdAt: now, updatedAt: now))
        value.updatedAt = now
        return (value, stageId)
    }

    func renamingStage(stageId: String, name: String, now: String) -> ProjectStageSetDocument {
        updatingStage(stageId: stageId, now: now) { stage in
            var value = stage
            value.name = name.trimmed
            value.updatedAt = now
            return value
        }
    }

    /// Removes the stage and reports which cuts it owned. The report is
    /// INFORMATIONAL: since round 2 the engine trashes those cuts before
    /// calling this (renders are paid artifacts — soft-delete only), so a
    /// caller must never hard-delete shot rows from the returned list.
    func deletingStage(stageId: String, now: String) -> (document: ProjectStageSetDocument, removedCutIds: [String]) {
        guard let stage = stage(withId: stageId) else { return (self, []) }
        var value = self
        value.stages.removeAll { $0.stageId == stageId }
        let removed = stage.cutIds
        value.finals.removeAll { removed.contains($0.cutId) }
        value.updatedAt = now
        return (value, removed)
    }

    /// Seam-drop semantics identical to ProjectShotTimelineDocument.movingShot:
    /// `index` is interpreted against the document BEFORE removal.
    func movingStage(stageId: String, toIndex index: Int, now: String) -> ProjectStageSetDocument {
        guard let sourceIndex = stages.firstIndex(where: { $0.stageId == stageId }) else { return self }
        var value = self
        let stage = value.stages.remove(at: sourceIndex)
        var target = index
        if sourceIndex < index {
            target -= 1
        }
        let clamped = max(0, min(target, value.stages.count))
        value.stages.insert(stage, at: clamped)
        value.updatedAt = now
        return value
    }

    /// A transform that returns the stage unchanged leaves the DOCUMENT
    /// unchanged too (no updatedAt bump) — engine callers rely on equality
    /// to skip pointless persists, so no-ops must be free.
    func updatingStage(stageId: String, now: String, _ transform: (ProjectStage) -> ProjectStage) -> ProjectStageSetDocument {
        guard let index = stages.firstIndex(where: { $0.stageId == stageId }) else { return self }
        let transformed = transform(stages[index])
        guard transformed != stages[index] else { return self }
        var value = self
        value.stages[index] = transformed
        value.updatedAt = now
        return value
    }

    // MARK: Pure mutations — inputs (the unordered palette)

    /// Adds a reference to the stage's palette. Re-gathering an asset the
    /// stage already holds is a friendly no-op, never a duplicate.
    func addingInput(stageId: String, frameImageId: String = "", clipMediaId: String = "", now: String) -> ProjectStageSetDocument {
        guard !frameImageId.isEmpty || !clipMediaId.isEmpty else { return self }
        return updatingStage(stageId: stageId, now: now) { stage in
            guard !stage.containsAsset(frameImageId: frameImageId, clipMediaId: clipMediaId) else { return stage }
            var value = stage
            let inputId = "stageinput_\(shortHash("\(stageId):\(frameImageId):\(clipMediaId):\(now):\(UUID().uuidString)", length: 12))"
            value.inputs.append(StageInput(
                inputId: inputId,
                frameImageId: frameImageId,
                clipMediaId: clipMediaId,
                addedAt: now
            ))
            value.updatedAt = now
            return value
        }
    }

    /// Removes a palette reference. The frame/footage itself is untouched —
    /// it keeps living in the lens version store / media library (and in any
    /// cut entries that reference it).
    func removingInput(stageId: String, inputId: String, now: String) -> ProjectStageSetDocument {
        updatingStage(stageId: stageId, now: now) { stage in
            var value = stage
            value.inputs.removeAll { $0.inputId == inputId }
            value.updatedAt = now
            return value
        }
    }

    /// Re-homes one gathered reference onto another stage (identity-preserving
    /// move; dedupe applies on arrival).
    func movingInput(inputId: String, toStage destinationStageId: String, now: String) -> ProjectStageSetDocument {
        guard let sourceStage = stages.first(where: { $0.inputs.contains { $0.inputId == inputId } }),
              let input = sourceStage.inputs.first(where: { $0.inputId == inputId }),
              sourceStage.stageId != destinationStageId,
              stage(withId: destinationStageId) != nil else {
            return self
        }
        let removed = removingInput(stageId: sourceStage.stageId, inputId: inputId, now: now)
        return removed.addingInput(
            stageId: destinationStageId,
            frameImageId: input.frameImageId,
            clipMediaId: input.clipMediaId,
            now: now
        )
    }

    // MARK: Pure mutations — cut ownership

    /// Claims a cut for a stage, releasing it from any other stage first —
    /// the single-membership invariant lives here.
    func attachingCut(cutId: String, toStage stageId: String, now: String) -> ProjectStageSetDocument {
        guard !cutId.isEmpty, let target = stage(withId: stageId) else { return self }
        guard !target.cutIds.contains(cutId) else { return self }
        var value = detachingCut(cutId: cutId, now: now)
        value = value.updatingStage(stageId: stageId, now: now) { stage in
            var repaired = stage
            if !repaired.cutIds.contains(cutId) {
                repaired.cutIds.append(cutId)
            }
            repaired.updatedAt = now
            return repaired
        }
        return value
    }

    func detachingCut(cutId: String, now: String) -> ProjectStageSetDocument {
        var value = self
        var changed = false
        value.stages = value.stages.map { stage in
            guard stage.cutIds.contains(cutId) else { return stage }
            var repaired = stage
            repaired.cutIds.removeAll { $0 == cutId }
            repaired.updatedAt = now
            changed = true
            return repaired
        }
        if changed {
            value.finals.removeAll { $0.cutId == cutId }
            value.updatedAt = now
        }
        return value
    }

    // MARK: Pure mutations — finals (the picked-cuts shelf)

    func addingFinal(cutId: String, now: String) -> ProjectStageSetDocument {
        guard !cutId.isEmpty, stage(containingCut: cutId) != nil else { return self }
        guard !finals.contains(where: { $0.cutId == cutId }) else { return self }
        var value = self
        let entryId = "final_\(shortHash("\(projectId):\(cutId):\(now):\(UUID().uuidString)", length: 12))"
        value.finals.append(StageFinalsEntry(entryId: entryId, cutId: cutId, addedAt: now))
        value.updatedAt = now
        return value
    }

    func removingFinal(entryId: String, now: String) -> ProjectStageSetDocument {
        var value = self
        value.finals.removeAll { $0.entryId == entryId }
        value.reelSeams = Self.reapedReelSeams(value.reelSeams, finals: value.finals)
        value.updatedAt = now
        return value
    }

    /// Seam-drop semantics against the pre-removal array, like movingStage.
    func movingFinal(entryId: String, toIndex index: Int, now: String) -> ProjectStageSetDocument {
        guard let sourceIndex = finals.firstIndex(where: { $0.entryId == entryId }) else { return self }
        var value = self
        let entry = value.finals.remove(at: sourceIndex)
        var target = index
        if sourceIndex < index {
            target -= 1
        }
        let clamped = max(0, min(target, value.finals.count))
        value.finals.insert(entry, at: clamped)
        value.updatedAt = now
        return value
    }

    // MARK: Pure mutations — trash (soft-deleted cuts; restore-only)

    /// Soft-deletes a cut: it leaves its stage and the FINALS shelf, and the
    /// trash remembers where it lived. The timeline row is never touched.
    func trashingCut(cutId: String, now: String) -> ProjectStageSetDocument {
        guard !cutId.isEmpty else { return self }
        guard !trashedCuts.contains(where: { $0.cutId == cutId }) else { return self }
        let former = stage(containingCut: cutId)
        let formerGroup = group(parentCutId: cutId)
        var value = self
        value.cutGroups.removeAll { $0.parentCutId == cutId }
        var detached = value.detachingCut(cutId: cutId, now: now)
        // A hidden source cannot be trashed independently. If an older caller
        // reaches this path, reveal its parent group instead of leaving a
        // broken disclosure.
        if let containingGroup = detached.group(containingSourceCutId: cutId) {
            detached.cutGroups.removeAll { $0.groupId == containingGroup.groupId }
        }
        value = detached
        value.finals.removeAll { $0.cutId == cutId }
        value.reelSeams = Self.reapedReelSeams(value.reelSeams, finals: value.finals)
        value.trashedCuts.append(TrashedCut(
            entryId: "trash_\(shortHash("\(projectId):\(cutId):\(now):\(UUID().uuidString)", length: 12))",
            cutId: cutId,
            formerStageId: former?.stageId ?? "",
            formerStageName: former?.name ?? "",
            formerGroupId: formerGroup?.groupId ?? "",
            combinedSourceCutIds: formerGroup?.sourceCutIds ?? [],
            trashedAt: now
        ))
        value.updatedAt = now
        return value
    }

    /// Restores a trashed cut to its former stage, else the first stage.
    /// `attachedStageId == nil` with a non-empty cut id means no stage exists —
    /// the caller creates one and attaches. Restore never re-picks FINALS.
    func restoringCut(trashEntryId: String, now: String) -> (document: ProjectStageSetDocument, restoredCutId: String, attachedStageId: String?) {
        guard let row = trashedCuts.first(where: { $0.entryId == trashEntryId }) else {
            return (self, "", nil)
        }
        var value = self
        value.trashedCuts.removeAll { $0.entryId == trashEntryId }
        value.updatedAt = now
        guard let target = stage(withId: row.formerStageId) ?? stages.first else {
            return (value, row.cutId, nil)
        }
        value = value.attachingCut(cutId: row.cutId, toStage: target.stageId, now: now)
        if row.combinedSourceCutIds.count >= 2,
           row.combinedSourceCutIds.allSatisfy(target.cutIds.contains) {
            value = value.groupingCombinedCut(
                parentCutId: row.cutId,
                sourceCutIds: row.combinedSourceCutIds,
                inStage: target.stageId,
                now: now
            )
        }
        return (value, row.cutId, target.stageId)
    }

    /// Attach + position: the claimed cut lands immediately after `afterCutId`
    /// in the stage's order (appends when the anchor is absent). The
    /// new-version flow uses this to seat a duplicate beside its original.
    func attachingCut(cutId: String, toStage stageId: String, afterCutId: String, now: String) -> ProjectStageSetDocument {
        let attached = attachingCut(cutId: cutId, toStage: stageId, now: now)
        return attached.updatingStage(stageId: stageId, now: now) { stage in
            guard let currentIndex = stage.cutIds.firstIndex(of: cutId),
                  let anchorIndex = stage.cutIds.firstIndex(of: afterCutId),
                  currentIndex != anchorIndex + 1 else {
                return stage
            }
            var value = stage
            value.cutIds.remove(at: currentIndex)
            let target = currentIndex < anchorIndex ? anchorIndex : anchorIndex + 1
            value.cutIds.insert(cutId, at: min(target, value.cutIds.count))
            value.updatedAt = now
            return value
        }
    }

    /// Re-arranges a cut inside its stage, or re-homes it onto another stage
    /// AT A POSITION — one gesture, one document, one write.
    ///
    /// `visibleIndex` is an insertion point in the DESTINATION stage's VISIBLE
    /// order (0...visibleCount), interpreted against the document BEFORE
    /// removal, the same seam-drop convention as `movingStage`/`movingFinal`.
    /// Rather than the scalar `if sourceIndex < index` correction those use,
    /// this resolves the ANCHOR cut id before removal and inserts before it:
    /// for a single id the two are arithmetically identical, but a combined
    /// parent moves as an N-id block, where the correction would have to be
    /// `-= block.count`. Anchoring is the honest generalization.
    ///
    /// Three laws index arithmetic alone cannot express:
    ///
    /// - A combined parent CARRIES its hidden sources and its group's stage
    ///   claim as one block. Both `normalized()` and `reconciled(with:)` drop
    ///   any group whose named stage no longer holds parent + every source, so
    ///   a parent that travelled alone would destroy its own group and strand
    ///   its sources permanently visible.
    /// - A drop can never land INSIDE a group: every visible anchor is either
    ///   a standalone cut or a parent seated immediately before its sources
    ///   (see `groupingCombinedCut`), so "insert before the anchor" is always
    ///   a group boundary.
    /// - A FINALS pick SURVIVES. This deliberately does NOT route through
    ///   `attachingCut`, whose `detachingCut` clears finals: that rule exists
    ///   because a detached cut is homeless, and a move never is. Removing and
    ///   inserting in one pass also means the cut is never momentarily
    ///   unclaimed, so the orphan-adoption sweep can never see it.
    func movingCut(
        cutId: String,
        toStage destinationStageId: String,
        toVisibleIndex visibleIndex: Int,
        now: String
    ) -> ProjectStageSetDocument {
        guard !cutId.isEmpty,
              stage(containingCut: cutId) != nil,
              let destination = stage(withId: destinationStageId),
              group(containingSourceCutId: cutId) == nil else {
            return self
        }

        let carried = group(parentCutId: cutId)
        let block = [cutId] + (carried?.sourceCutIds ?? [])
        let moving = Set(block)

        let visible = visibleCutIds(in: destination)
        let clamped = max(0, min(visibleIndex, visible.count))
        let anchorCutId = clamped < visible.count ? visible[clamped] : nil
        // Dropping onto itself is a no-op, not a reshuffle.
        if let anchorCutId, moving.contains(anchorCutId) { return self }

        var value = self
        var changed = false
        value.stages = value.stages.map { stage in
            var repaired = stage
            repaired.cutIds.removeAll { moving.contains($0) }
            if stage.stageId == destinationStageId {
                let target = anchorCutId.flatMap { repaired.cutIds.firstIndex(of: $0) }
                    ?? repaired.cutIds.count
                repaired.cutIds.insert(
                    contentsOf: block,
                    at: max(0, min(target, repaired.cutIds.count))
                )
            }
            guard repaired.cutIds != stage.cutIds else { return stage }
            repaired.updatedAt = now
            changed = true
            return repaired
        }

        if let carried, carried.stageId != destinationStageId {
            value.cutGroups = value.cutGroups.map { group in
                guard group.groupId == carried.groupId else { return group }
                var repaired = group
                repaired.stageId = destinationStageId
                return repaired
            }
            changed = true
        }

        guard changed else { return self }
        value.updatedAt = now
        return value
    }

    /// Append-to-the-end overload — the `Move to Stage…` menu path.
    func movingCut(cutId: String, toStage destinationStageId: String, now: String) -> ProjectStageSetDocument {
        let count = stage(withId: destinationStageId).map { visibleCutIds(in: $0).count } ?? 0
        return movingCut(
            cutId: cutId,
            toStage: destinationStageId,
            toVisibleIndex: count,
            now: now
        )
    }

    /// Seats a combined parent immediately before its adjacent visible
    /// sources. Source ids remain in the stage so uncombine is a metadata-only
    /// reveal; the Stage group controls their collapsed presentation.
    func groupingCombinedCut(
        parentCutId: String,
        sourceCutIds: [String],
        inStage stageId: String,
        now: String
    ) -> ProjectStageSetDocument {
        guard !parentCutId.isEmpty,
              sourceCutIds.count >= 2,
              let stage = stage(withId: stageId) else { return self }
        let visible = visibleCutIds(in: stage)
        guard let firstVisibleIndex = visible.firstIndex(of: sourceCutIds[0]),
              Array(visible.dropFirst(firstVisibleIndex).prefix(sourceCutIds.count)) == sourceCutIds,
              sourceCutIds.allSatisfy(stage.cutIds.contains) else {
            return self
        }
        var value = self
        value = value.detachingCut(cutId: parentCutId, now: now)
        value = value.updatingStage(stageId: stageId, now: now) { current in
            guard let sourceIndex = current.cutIds.firstIndex(of: sourceCutIds[0]) else { return current }
            var updated = current
            updated.cutIds.insert(parentCutId, at: sourceIndex)
            updated.updatedAt = now
            return updated
        }
        value.cutGroups.removeAll { $0.parentCutId == parentCutId }
        value.cutGroups.append(StageCutGroup(
            groupId: "cut_group_\(shortHash("\(projectId):\(parentCutId):\(now):\(UUID().uuidString)", length: 12))",
            stageId: stageId,
            parentCutId: parentCutId,
            sourceCutIds: sourceCutIds,
            createdAt: now
        ))
        value.updatedAt = now
        return value
    }

    /// Reveals untouched sources and archives the independent parent.
    func ungroupingCombinedCut(parentCutId: String, now: String) -> ProjectStageSetDocument {
        guard cutGroups.contains(where: { $0.parentCutId == parentCutId }) else { return self }
        return trashingCut(cutId: parentCutId, now: now)
    }

    // MARK: Seeding + reconciliation against the shot timeline

    /// First-open migration: every existing shot becomes a stage carrying the
    /// shot as its only cut, with the shot's distinct frames/clips gathered
    /// as inputs. The timeline document itself is never rewritten. Frames in
    /// no shot need no migration at all — BACKLOT membership is derived.
    static func seeded(from timeline: ProjectShotTimelineDocument, now: String) -> ProjectStageSetDocument {
        var value = ProjectStageSetDocument(projectId: timeline.projectId, updatedAt: now)
        for (index, shot) in timeline.shots.enumerated() {
            let stageId = "stage_\(shortHash("\(timeline.projectId):seed:\(shot.shotId)", length: 12))"
            var inputs: [StageInput] = []
            var seenAssets: Set<String> = []
            for entry in shot.entries {
                guard !entry.frameImageId.isEmpty || !entry.clipMediaId.isEmpty else { continue }
                let input = StageInput(
                    inputId: "stageinput_\(shortHash("\(stageId):\(entry.entryId)", length: 12))",
                    frameImageId: entry.frameImageId,
                    clipMediaId: entry.clipMediaId,
                    addedAt: now
                )
                guard seenAssets.insert(input.assetKey).inserted else { continue }
                inputs.append(input)
            }
            value.stages.append(ProjectStage(
                stageId: stageId,
                name: shot.name.trimmed.isEmpty ? "Stage \(index + 1)" : shot.name.trimmed,
                inputs: inputs,
                cutIds: [shot.shotId],
                createdAt: shot.createdAt.isEmpty ? now : shot.createdAt,
                updatedAt: now
            ))
        }
        return value
    }

    /// Load-time self-heal against the actual timeline: dead cut references
    /// drop, and any orphan shot (created by a legacy path or a missed write)
    /// gets its own stage — every cut belongs to exactly one stage, always.
    /// Returns `changed == false` when the document was already faithful, so
    /// callers can skip a pointless persist.
    func reconciled(with timeline: ProjectShotTimelineDocument, now: String) -> (document: ProjectStageSetDocument, changed: Bool) {
        var value = normalized()
        var changed = value != self
        let liveCutIds = Set(timeline.shots.map(\.shotId))

        value.stages = value.stages.map { stage in
            let pruned = stage.cutIds.filter { liveCutIds.contains($0) }
            guard pruned.count != stage.cutIds.count else { return stage }
            var repaired = stage
            repaired.cutIds = pruned
            repaired.updatedAt = now
            changed = true
            return repaired
        }

        let beforeTrashCount = value.trashedCuts.count
        value.trashedCuts.removeAll { !liveCutIds.contains($0.cutId) }
        if value.trashedCuts.count != beforeTrashCount {
            changed = true
        }

        // Trashed cuts are deliberately homeless — adoption skips them.
        let trashedIds = Set(value.trashedCuts.map(\.cutId))
        let claimed = Set(value.stages.flatMap(\.cutIds)).union(trashedIds)
        for shot in timeline.shots where !claimed.contains(shot.shotId) {
            let stageId = "stage_\(shortHash("\(timeline.projectId):orphan:\(shot.shotId)", length: 12))"
            var seeded = ProjectStageSetDocument.seeded(
                from: ProjectShotTimelineDocument(projectId: timeline.projectId, shots: [shot]),
                now: now
            ).stages
            if var only = seeded.popLast() {
                only.stageId = stageId
                only.name = shot.name.trimmed.isEmpty ? "Stage \(value.stages.count + 1)" : shot.name.trimmed
                value.stages.append(only)
            }
            changed = true
        }

        let beforeFinals = value.finals.count
        value.finals.removeAll { !liveCutIds.contains($0.cutId) }
        if value.finals.count != beforeFinals {
            changed = true
        }
        let beforeSeams = value.reelSeams
        value.reelSeams = Self.reapedReelSeams(value.reelSeams, finals: value.finals)
        if value.reelSeams != beforeSeams {
            changed = true
        }

        let beforeGroups = value.cutGroups
        value.cutGroups = value.cutGroups.filter { group in
            guard liveCutIds.contains(group.parentCutId),
                  group.sourceCutIds.allSatisfy(liveCutIds.contains),
                  let stage = value.stage(withId: group.stageId),
                  stage.cutIds.contains(group.parentCutId),
                  group.sourceCutIds.allSatisfy(stage.cutIds.contains) else {
                return false
            }
            return true
        }
        if value.cutGroups != beforeGroups {
            changed = true
        }

        if changed {
            value.updatedAt = now
        }
        return (value, changed)
    }
}

// MARK: - Drag payload

extension UTType {
    /// In-app only; deliberately NOT conforming to .json so frame/media drop
    /// targets never activate for cut-strip drags (dropDestination validates
    /// by UTType, not by decode success).
    static let litScenesCut = UTType(exportedAs: "com.litscenes.cut")
}

/// Drag payload for a whole CUT strip — accepted by the FINALS shelf, the
/// COMBINE seam between two adjacent cuts, and the stage spine's reorder lanes
/// (which also re-home the cut when the spine belongs to another stage).
/// Carries no frame/media id so it can never cross-decode with
/// ShotFrameTransfer or MediaIDTransfer, and the source stage is always
/// derivable from the id via `stage(containingCut:)` — so the payload stays a
/// bare id no matter how many destinations learn to accept it.
struct CutTransfer: Codable, Hashable, Transferable {
    var cutId: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .litScenesCut)
    }
}

extension UTType {
    /// SCENES v2 rail drags. A fresh type (not .litScenesCut) so rail thumbs
    /// can never activate the FINALS shelf / combine-seam / spine targets that
    /// accept CutTransfer today — and vice versa.
    static let litScenesSceneV2 = UTType(exportedAs: "com.litscenes.scene.v2")
}

/// Drag payload for a SCENES v2 rail thumbnail: reorder the project's scene
/// order (or stage a scene by dropping it on the hero), carrying the project
/// id so a foreign-project thumb can be recognized and refused instead of
/// decoding as something placeable.
struct SceneRailTransfer: Codable, Hashable, Transferable {
    var projectId: String
    var shotId: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .litScenesSceneV2)
    }
}

extension UTType {
    /// Sequence-coin drags. A fresh type (not .litScenesSceneV2) so coin
    /// reorders can never activate the rail's scene-order reorder targets —
    /// and vice versa (the deleted Ready band's lesson, kept).
    static let litScenesSequenceCoin = UTType(exportedAs: "com.litscenes.sequence.coin")
}

/// Drag payload for a sequence coin: reorder within the Output sequence only.
struct SequenceCoinTransfer: Codable, Hashable, Transferable {
    var projectId: String
    var shotId: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .litScenesSequenceCoin)
    }
}
