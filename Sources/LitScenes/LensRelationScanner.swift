import Foundation

struct LensRelationScanResult: Hashable {
    var summariesByLensId: [String: LensRelationSummary] = [:]

    func summary(for lensId: String) -> LensRelationSummary {
        summariesByLensId[lensId] ?? .empty
    }
}

struct LensRelationScanner {
    var store: ProjectContextStore

    func scan(project: ProjectRecord, lensSet: ProjectLensSetDocument) -> LensRelationScanResult {
        let lensIds = Set(lensSet.lenses.map(\.lensId))
        guard !lensIds.isEmpty else { return LensRelationScanResult() }

        var counters = Dictionary(uniqueKeysWithValues: lensIds.map { ($0, LensRelationSummary(updatedAt: DateFormats.now())) })
        let directionHistory = store.loadStoryDirectionHistory(for: project)
        let boards = store.loadStoryBeatBoards(for: project)
        let projectStory = store.loadProjectStory(for: project)
        let sceneWorkspaces = store.loadSceneWorkspaces(for: project)
        let sceneAssets = store.loadSceneAssets(for: project)
        let audioTracks = store.loadStoryAudioTracks(for: project).tracks

        for set in directionHistory.directionSets {
            let referenced = explicitLensIds(in: set)
            for lensId in referenced where lensIds.contains(lensId) {
                counters[lensId, default: LensRelationSummary(updatedAt: DateFormats.now())].storylineCount += 1
            }
        }

        for board in boards {
            let referenced = explicitLensIds(in: board)
            for lensId in referenced where lensIds.contains(lensId) {
                counters[lensId, default: LensRelationSummary(updatedAt: DateFormats.now())].beatBoardCount += 1
            }
        }

        for lensId in explicitLensIds(in: projectStory) where lensIds.contains(lensId) {
            counters[lensId, default: LensRelationSummary(updatedAt: DateFormats.now())].projectStoryCount += 1
        }

        for workspace in sceneWorkspaces {
            let referenced = explicitLensIds(in: workspace)
            for lensId in referenced where lensIds.contains(lensId) {
                counters[lensId, default: LensRelationSummary(updatedAt: DateFormats.now())].sceneWorkspaceCount += 1
            }
        }

        for asset in sceneAssets {
            let referenced = explicitLensIds(in: asset)
            for lensId in referenced where lensIds.contains(lensId) {
                counters[lensId, default: LensRelationSummary(updatedAt: DateFormats.now())].sceneAssetCount += 1
            }
        }

        for track in audioTracks {
            let referenced = explicitLensIds(in: track)
            for lensId in referenced where lensIds.contains(lensId) {
                counters[lensId, default: LensRelationSummary(updatedAt: DateFormats.now())].audioTrackCount += 1
            }
        }

        return LensRelationScanResult(summariesByLensId: counters)
    }

    private func explicitLensIds<T: Encodable>(in value: T) -> Set<String> {
        guard let data = try? JSONCoding.encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        return explicitLensIds(inJSONObject: object)
    }

    private func explicitLensIds(inJSONObject value: Any) -> Set<String> {
        if let dictionary = value as? [String: Any] {
            var result = Set<String>()
            for (key, child) in dictionary {
                if key == "lens_id", let lensId = child as? String, !lensId.trimmed.isEmpty {
                    result.insert(lensId.trimmed)
                } else {
                    result.formUnion(explicitLensIds(inJSONObject: child))
                }
            }
            return result
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { partial, child in
                partial.formUnion(explicitLensIds(inJSONObject: child))
            }
        }
        return []
    }
}
