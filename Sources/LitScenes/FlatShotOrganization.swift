import Foundation

// MARK: - Legacy Stage → flat Shot migration

extension ProjectShotTimelineDocument {
    /// One-way, idempotent presentation migration. Stage rows supply only
    /// their operator-authored Shot order and reversible collapse/trash state;
    /// gathered inputs and Stage names deliberately have no flat equivalent.
    func flatteningLegacyOrganization(
        _ legacy: ProjectStageSetDocument?,
        now: String
    ) -> ProjectShotTimelineDocument {
        guard organizationVersion != Self.flatOrganizationVersion else { return normalized() }

        var value = self
        let lookup = Dictionary(shots.map { ($0.shotId, $0) }, uniquingKeysWith: { first, _ in first })
        var orderedIds: [String] = []
        var seen: Set<String> = []
        if let legacy {
            for stage in legacy.stages {
                for shotId in stage.cutIds where lookup[shotId] != nil && seen.insert(shotId).inserted {
                    orderedIds.append(shotId)
                }
            }
        }
        for shot in shots where seen.insert(shot.shotId).inserted {
            orderedIds.append(shot.shotId)
        }
        value.shots = orderedIds.compactMap { lookup[$0] }

        if let legacy {
            let legacyGroupsByParent = Dictionary(
                legacy.cutGroups.map { ($0.parentCutId, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            value.shotGroups = legacy.cutGroups.map { group in
                CombinedShotGroup(
                    groupId: group.groupId,
                    parentShotId: group.parentCutId,
                    sourceShotIds: group.sourceCutIds,
                    createdAt: group.createdAt
                )
            }
            value.trashedShots = legacy.trashedCuts.enumerated().map { offset, row in
                let restoredGroup: CombinedShotGroup?
                if let group = legacyGroupsByParent[row.cutId] {
                    restoredGroup = CombinedShotGroup(
                        groupId: group.groupId,
                        parentShotId: group.parentCutId,
                        sourceShotIds: group.sourceCutIds,
                        createdAt: group.createdAt
                    )
                } else if row.combinedSourceCutIds.count >= 2 {
                    restoredGroup = CombinedShotGroup(
                        groupId: row.formerGroupId.trimmed.nilIfEmpty
                            ?? "shot_group_\(shortHash("legacy:\(projectId):\(row.cutId)", length: 12))",
                        parentShotId: row.cutId,
                        sourceShotIds: row.combinedSourceCutIds,
                        createdAt: row.trashedAt
                    )
                } else {
                    restoredGroup = nil
                }
                return TrashedShot(
                    entryId: row.entryId.trimmed.nilIfEmpty
                        ?? "trash_\(shortHash("legacy:\(projectId):\(row.cutId):\(offset)", length: 12))",
                    shotId: row.cutId,
                    formerVisibleIndex: orderedIds.firstIndex(of: row.cutId) ?? orderedIds.count,
                    combinedGroup: restoredGroup,
                    trashedAt: row.trashedAt
                )
            }
            let trashedIds = Set(value.trashedShots.map(\.shotId))
            value.shotGroups.removeAll { trashedIds.contains($0.parentShotId) }
        }

        value.organizationVersion = Self.flatOrganizationVersion
        value.schemaVersion = Self.schemaVersion
        value.updatedAt = now
        return value.normalized()
    }
}

// MARK: - Output-owned sequence state

/// One Shot selected for the future Output sequence. This deliberately does
/// not live in the Scenes organization document.
struct OutputShotEntry: Codable, Hashable, Identifiable, Sendable {
    var entryId: String = ""
    var shotId: String = ""
    var addedAt: String = ""

    var id: String { entryId }
}

struct ProjectOutputSequenceDocument: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.output_sequence.v0.1"
    static let documentType = "project_output_sequence"

    var schemaVersion: String = Self.schemaVersion
    var projectId: String = ""
    var shots: [OutputShotEntry] = []
    var reelAudio: [ShotAudioRegion] = []
    var reelSeams: [ReelSeamStyle] = []
    /// The reel's head/tail fades from/to black. 0 = off; non-zero values
    /// snap to the seam presets. Duration-neutral — they never move a band.
    var reelFadeInFrames: Int = 0
    var reelFadeOutFrames: Int = 0
    var updatedAt: String = ""

    static func empty(projectId: String) -> ProjectOutputSequenceDocument {
        ProjectOutputSequenceDocument(projectId: projectId)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case shots
        case reelAudio
        case reelSeams
        case reelFadeInFrames
        case reelFadeOutFrames
        case updatedAt
    }

    init(
        schemaVersion: String = Self.schemaVersion,
        projectId: String = "",
        shots: [OutputShotEntry] = [],
        reelAudio: [ShotAudioRegion] = [],
        reelSeams: [ReelSeamStyle] = [],
        reelFadeInFrames: Int = 0,
        reelFadeOutFrames: Int = 0,
        updatedAt: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.shots = shots
        self.reelAudio = reelAudio
        self.reelSeams = reelSeams
        self.reelFadeInFrames = reelFadeInFrames
        self.reelFadeOutFrames = reelFadeOutFrames
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        shots = try container.decodeIfPresent([OutputShotEntry].self, forKey: .shots) ?? []
        reelAudio = ((try? container.decodeIfPresent([ShotAudioRegion].self, forKey: .reelAudio)) ?? nil) ?? []
        reelSeams = ((try? container.decodeIfPresent([ReelSeamStyle].self, forKey: .reelSeams)) ?? nil) ?? []
        reelFadeInFrames = ((try? container.decodeIfPresent(Int.self, forKey: .reelFadeInFrames)) ?? nil) ?? 0
        reelFadeOutFrames = ((try? container.decodeIfPresent(Int.self, forKey: .reelFadeOutFrames)) ?? nil) ?? 0
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    func normalized() -> ProjectOutputSequenceDocument {
        var value = self
        var seenEntries: Set<String> = []
        var seenShots: Set<String> = []
        value.shots = value.shots.filter {
            !$0.entryId.trimmed.isEmpty
                && !$0.shotId.trimmed.isEmpty
                && seenEntries.insert($0.entryId).inserted
                && seenShots.insert($0.shotId).inserted
        }
        value.reelSeams = reelSeamsReaped(
            value.reelSeams,
            entryIds: Set(value.shots.map(\.entryId))
        )
        value.reelFadeInFrames = reelFadeSnappedFrames(value.reelFadeInFrames)
        value.reelFadeOutFrames = reelFadeSnappedFrames(value.reelFadeOutFrames)
        return value
    }

    static func migrating(
        legacy: ProjectStageSetDocument?,
        projectId: String,
        now: String
    ) -> ProjectOutputSequenceDocument {
        guard let legacy else { return .empty(projectId: projectId) }
        return ProjectOutputSequenceDocument(
            projectId: projectId,
            shots: legacy.finals.map {
                OutputShotEntry(entryId: $0.entryId, shotId: $0.cutId, addedAt: $0.addedAt)
            },
            reelAudio: legacy.reelAudio,
            reelSeams: legacy.reelSeams,
            updatedAt: now
        ).normalized()
    }

    func removingShot(_ shotId: String, now: String) -> ProjectOutputSequenceDocument {
        var value = self
        value.shots.removeAll { $0.shotId == shotId }
        let ids = Set(value.shots.map(\.entryId))
        value.reelSeams.removeAll {
            !ids.contains($0.leftEntryId) || !ids.contains($0.rightEntryId)
        }
        value.updatedAt = now
        return value
    }

    /// Appends a shot to the sequence. Minting a FRESH entryId is load-bearing:
    /// seams key on entryIds, so a removed-then-re-added pick must not
    /// resurrect the seams of its earlier life. No-op when already sequenced.
    func appendingShot(_ shotId: String, now: String) -> ProjectOutputSequenceDocument {
        guard !shotId.trimmed.isEmpty,
              !shots.contains(where: { $0.shotId == shotId }) else { return self }
        var value = self
        let entryId = "output_\(shortHash("\(projectId):\(shotId):\(now):\(UUID().uuidString)", length: 12))"
        value.shots.append(OutputShotEntry(entryId: entryId, shotId: shotId, addedAt: now))
        value.updatedAt = now
        return value
    }

    /// movingFinal's index semantics: the target index is read against the
    /// pre-removal array. Seams are deliberately untouched — adjacency is
    /// resolved at read time, so a displaced seam goes dormant, not dead.
    func movingShot(_ shotId: String, toIndex index: Int, now: String) -> ProjectOutputSequenceDocument {
        guard let sourceIndex = shots.firstIndex(where: { $0.shotId == shotId }) else { return self }
        var value = self
        let entry = value.shots.remove(at: sourceIndex)
        var target = index
        if sourceIndex < index {
            target -= 1
        }
        let clamped = max(0, min(target, value.shots.count))
        value.shots.insert(entry, at: clamped)
        guard value.shots != shots else { return self }
        value.updatedAt = now
        return value
    }
}
