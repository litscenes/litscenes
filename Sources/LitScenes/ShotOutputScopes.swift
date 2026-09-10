import Foundation

/// An editable group of the preceding cut. Entries and generated takes remain
/// owned by the Shot; a scope owns only their order and local edit decisions.
/// The mixed video is a disposable playback cache, never the source of edits.
struct ShotOutputScope: Codable, Hashable, Sendable, Identifiable {
    var scopeId: String
    var entryIds: [String]
    var segmentKeys: [String]
    var edits: ShotOutputEdits
    var children: [ShotOutputScope]
    var cache: ShotOutputScopeCache?
    var lineageAliases: [String: String]?
    var id: String { scopeId }

    init(shot: ProjectShot, segmentKeys: [String], scopeId: String = "scope_\(UUID().uuidString.lowercased())") {
        self.scopeId = scopeId
        entryIds = shot.entries.map(\.entryId)
        self.segmentKeys = segmentKeys
        edits = ShotOutputEdits(shot)
        children = shot.outputScopes
    }

    func project(from shot: ProjectShot) -> ProjectShot {
        var result = edits.applying(to: shot)
        let owned = Set(entryIds)
        result.entries = entryIds.compactMap { id in shot.entries.first { $0.entryId == id } }
        result.continuationRecords = shot.continuationRecords.filter { owned.contains($0.entryId) }
        result.outputScopes = children
        result.sourceBoundaries = shot.sourceBoundaries.filter { owned.contains($0.rightEntryId) }
        return result
    }

    func updating(_ shot: ProjectShot) -> ShotOutputScope {
        var result = self
        result.entryIds = shot.entries.map(\.entryId)
        result.edits = ShotOutputEdits(shot)
        result.children = shot.outputScopes
        return result
    }

    func ownsSegment(_ key: String) -> Bool {
        if segmentKeys.contains(key) { return true }
        let right = shotSegmentKeyRightEntryId(key) ?? ""
        let owner = right.isEmpty ? (shotSegmentKeyLeftEntryId(key) ?? "") : right
        return entryIds.contains(owner)
    }

    var syntheticEntry: ShotFrameEntry { ShotFrameEntry(entryId: scopeId, frameImageId: scopeId) }
    var placementKey: String { shotPlacementSegmentKey(startEntryId: scopeId, endEntryId: "", legacyStartId: scopeId, legacyEndId: "") }
}

struct ShotOutputScopeCache: Codable, Hashable, Sendable {
    var fingerprint: String
    var videoPath: String
    var durationSeconds: Double
    var sourceOffsets: [String: Double]?
    var entryOffsets: [String: Double]?
}

struct ShotOutputEdits: Codable, Hashable, Sendable {
    var cutList: ShotCutList
    var pictureInsertions: [ShotPictureInsertion]
    var audioMix: ShotAudioMix
    var audioRegions: [ShotAudioRegion]
    var sourceSegmentAudio: [ShotSourceSegmentAudio]
    var narrationArtifact: ShotNarrationArtifact?
    var activeLookVersionId: String

    init(_ shot: ProjectShot) {
        cutList = shot.cutList
        pictureInsertions = shot.pictureInsertions
        audioMix = shot.audioMix
        audioRegions = shot.audioRegions
        sourceSegmentAudio = shot.sourceSegmentAudio
        narrationArtifact = shot.narrationArtifact
        activeLookVersionId = shot.activeLookVersionId
    }

    func applying(to shot: ProjectShot) -> ProjectShot {
        var result = shot
        result.cutList = cutList
        result.pictureInsertions = pictureInsertions
        result.audioMix = audioMix
        result.audioRegions = audioRegions
        result.sourceSegmentAudio = sourceSegmentAudio
        result.narrationArtifact = narrationArtifact
        result.activeLookVersionId = activeLookVersionId
        return result
    }
}

/// The exact reviewed cut, retained with a take independently of selection.
final class ShotContinuationOutputReview: Codable, Hashable, Sendable {
    let fingerprint: String
    let scope: ShotOutputScope
    let sourceClips: [ShotRenderSegmentClip]

    init(fingerprint: String, scope: ShotOutputScope, sourceClips: [ShotRenderSegmentClip]) {
        self.fingerprint = fingerprint
        self.scope = scope
        self.sourceClips = sourceClips
    }

    static func == (lhs: ShotContinuationOutputReview, rhs: ShotContinuationOutputReview) -> Bool {
        lhs === rhs || (lhs.fingerprint == rhs.fingerprint && lhs.scope == rhs.scope && lhs.sourceClips == rhs.sourceClips)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fingerprint); hasher.combine(scope); hasher.combine(sourceClips)
    }
}

extension ProjectShot {
    func outputScope(_ id: String) -> ShotOutputScope? {
        func find(_ scopes: [ShotOutputScope]) -> ShotOutputScope? {
            for scope in scopes {
                if scope.scopeId == id { return scope }
                if let nested = find(scope.children) { return nested }
            }
            return nil
        }
        return find(outputScopes)
    }

    func replacingOutputScope(_ replacement: ShotOutputScope) -> ProjectShot {
        func replace(_ scopes: [ShotOutputScope]) -> [ShotOutputScope] {
            scopes.map { scope in
                if scope.scopeId == replacement.scopeId { return replacement }
                var result = scope
                let childIds = Set(scope.children.flatMap(\.entryIds))
                result.children = replace(scope.children)
                if result.children != scope.children {
                    var ids: [String] = []
                    var emitted = Set<String>()
                    for id in scope.entryIds {
                        if let child = scope.children.first(where: { $0.entryIds.contains(id) }),
                           let updated = result.children.first(where: { $0.scopeId == child.scopeId }) {
                            if emitted.insert(child.scopeId).inserted { ids += updated.entryIds }
                        } else if !childIds.contains(id) { ids.append(id) }
                    }
                    result.entryIds = ids
                }
                return result
            }
        }
        var result = self
        result.outputScopes = replace(outputScopes)
        return result
    }

    func installingReviewedOutput(_ review: ShotContinuationOutputReview, entryId: String = "") -> ProjectShot {
        let scopeId = continuationRecord(entryId: entryId)?.outputScopeId ?? review.scope.scopeId
        guard outputScope(scopeId) == nil else { return self }
        var result = ShotOutputEdits(ProjectShot()).applying(to: self)
        result.outputScopes = [review.scope]
        return result
    }

    /// Scope editing never replaces the take ledger or the rest of the Shot.
    func mergingScopeEdit(_ edited: ProjectShot, scopeId: String) -> ProjectShot {
        guard let scope = outputScope(scopeId) else { return self }
        var result = replacingOutputScope(scope.updating(edited))
        let owned = Set(scope.entryIds)
        let first = result.entries.firstIndex { owned.contains($0.entryId) } ?? result.entries.count
        result.entries.removeAll { owned.contains($0.entryId) }
        result.entries.insert(contentsOf: edited.entries, at: min(first, result.entries.count))
        result.sourceBoundaries.removeAll { owned.contains($0.rightEntryId) }
        result.sourceBoundaries += edited.sourceBoundaries
        result.seedSegmentClips = edited.seedSegmentClips
        result.segmentPromptOverrides = edited.segmentPromptOverrides
        result.segmentRenderOverrides = edited.segmentRenderOverrides
        result.segmentDirectionPlans = edited.segmentDirectionPlans
        result.reverseProxies = edited.reverseProxies
        result.joinBridgeVersions = edited.joinBridgeVersions
        result.lookVersions = edited.lookVersions
        return result
    }
}

/// Stable visual/audio dependencies; attempts, prompt drafts and cache paths
/// are deliberately excluded because they do not change the current output.
func shotOutputFingerprint(_ shot: ProjectShot) -> String {
    struct Basis: Encodable {
        var entries: [ShotFrameEntry]
        var clips: [ShotRenderSegmentClip]
        var selectedTakes: [String]
        var edits: ShotOutputEdits
        var children: [String]
        var look: ShotRestyleArtifact?
        var files: [String]
    }
    let version = shot.playableRenderVersion
    let selected = shot.continuationRecords.compactMap(\.selectedTake)
    let clips = (version?.segmentClips ?? []) + shot.seedSegmentClips + selected.compactMap(\.segmentClip)
    var edits = ShotOutputEdits(shot)
    edits.pictureInsertions = edits.pictureInsertions.map { original in
        var copy = original
        if copy.sourceScope != nil { copy.sourceClipPath = "" }
        return copy
    }
    edits.cutList.segmentCuts = edits.cutList.segmentCuts.map { original in
        var copy = original
        if copy.sourceScope != nil { copy.clipPath = "" }
        return copy
    }
    var sourcePaths = clips.map(\.clipPath)
    sourcePaths += [version?.videoPath ?? "", shot.activeLookVersion?.videoPath ?? ""]
    sourcePaths += shot.pictureInsertions.filter { $0.sourceScope == nil }.map(\.sourceClipPath)
    sourcePaths += shotExpectedAudibleAudioFiles(shot: shot, outputDurationSeconds: .infinity).map(\.path)
    let paths = Set(sourcePaths)
    let basis = Basis(entries: shot.entries, clips: clips, selectedTakes: selected.map(\.takeId),
        edits: edits, children: shot.outputScopes.map { shotOutputFingerprint($0.project(from: shot)) },
        look: shot.activeLookVersion,
        files: paths.filter { !$0.isEmpty }.sorted().map { "\($0):\(continuationFileFingerprint(path: $0, readsBytes: false))" })
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(basis)).map(sha256Hex) ?? ""
}

/// Assembly groups only the playback representation. The segment editor keeps
/// the full source plan, and selecting the bracket opens these same controls
/// on the group's original material. A stale cache remains visibly pending
/// until its replacement is complete, just like a Reverse proxy.
func shotOutputScopePlan(shot: ProjectShot, segments: [ShotRenderPlanSegment]) -> [ShotRenderPlanSegment] {
    guard !shot.outputScopes.isEmpty else { return segments }
    var emitted = Set<String>()
    var result: [ShotRenderPlanSegment] = []
    for segment in segments {
        let key = shotPlanPlacementKey(segment)
        if let scope = shot.outputScopes.first(where: { $0.ownsSegment(key) }) {
            guard emitted.insert(scope.scopeId).inserted else { continue }
            let cache = scope.cache
            let clip = ShotRenderSegmentClip(startFrameImageId: scope.scopeId, endFrameImageId: "",
                placementStartEntryId: scope.scopeId, placementEndEntryId: "",
                clipPath: cache?.videoPath ?? "", provider: "local", model: "edited_cut",
                durationSeconds: cache?.durationSeconds ?? 0)
            result.append(.preserved(ShotPreservedRenderPlanSegment(displayIndex: result.count,
                sourceVersionId: scope.scopeId, clip: clip)))
        } else { result.append(segment) }
    }
    return result
}

func shotPlanPlacementKey(_ segment: ShotRenderPlanSegment) -> String {
    switch segment {
    case .generated(let item): return item.pair.placementKey
    case .footage(let item): return item.placementKey
    case .preserved(let item): return item.placementKey
    case .artifactFallback(let item): return shotArtifactSegmentKey(versionId: item.versionId)
    }
}

/// Restricts an action to the selected edit group. Task-local lifetime keeps
/// background rendering and another open Shot independent of editor selection.
enum ShotOutputEditContext {
    struct Selection: Sendable { var shotId: String; var scopeId: String }
    @TaskLocal static var selection: Selection?
}


struct ShotOutputScopeCopy {
    var scopes: [ShotOutputScope]
    var scopeIds: [String: String]
    var bridges: [ShotJoinBridgeArtifact]
    var looks: [ShotRestyleArtifact]
}

func copyShotOutputScopes(from shot: ProjectShot, entries: [String: String], keys: [String: String], seed: String) -> ShotOutputScopeCopy {
    func fresh(_ kind: String, _ id: String) -> String { id.isEmpty ? "" : "\(kind)_\(shortHash("\(seed):\(id)", length: 18))" }
    var scopeIds: [String: String] = [:]
    func collect(_ scopes: [ShotOutputScope]) {
        for scope in scopes { scopeIds[scope.scopeId] = fresh("scope", scope.scopeId); collect(scope.children) }
    }
    collect(shot.outputScopes)
    var keyMap = keys
    func scopeKeys(_ scopes: [ShotOutputScope]) {
        for scope in scopes {
            let id = scopeIds[scope.scopeId]!
            keyMap[scope.placementKey] = shotPlacementSegmentKey(startEntryId: id, endEntryId: "", legacyStartId: id, legacyEndId: "")
            scopeKeys(scope.children)
        }
    }
    scopeKeys(shot.outputScopes)
    func copy(_ scope: ShotOutputScope) -> ShotOutputScope {
        var result = scope
        result.scopeId = scopeIds[scope.scopeId]!
        result.entryIds = scope.entryIds.map { entries[$0] ?? $0 }
        result.segmentKeys = scope.segmentKeys.map { keyMap[$0] ?? $0 }
        result.children = scope.children.map(copy)
        result.edits.cutList.segmentCuts = scope.edits.cutList.segmentCuts.map { original in
            var cut = original
            cut.cutId = fresh("cut", cut.cutId)
            cut.segmentKey = keyMap[cut.segmentKey] ?? cut.segmentKey
            cut.sourceScope = cut.sourceScope?.remapping(scopeIds)
            cut.joinRepair.activeBridgeVersionId = fresh("join", cut.joinRepair.activeBridgeVersionId)
            return cut
        }
        result.edits.pictureInsertions = scope.edits.pictureInsertions.map { original in
            var insertion = original
            insertion.insertionId = fresh("insertion", insertion.insertionId)
            insertion.sourceSegmentKey = keyMap[insertion.sourceSegmentKey] ?? insertion.sourceSegmentKey
            insertion.anchorSegmentKey = keyMap[insertion.anchorSegmentKey] ?? insertion.anchorSegmentKey
            insertion.sourceScope = insertion.sourceScope?.remapping(scopeIds)
            insertion.replacesRazorCutIds = insertion.replacesRazorCutIds.map { fresh("cut", $0) }
            return insertion
        }
        result.edits.activeLookVersionId = fresh("look", scope.edits.activeLookVersionId)
        result.edits.sourceSegmentAudio = scope.edits.sourceSegmentAudio.map { original in
            var audio = original
            audio.placementStartEntryId = entries[audio.placementStartEntryId] ?? audio.placementStartEntryId
            audio.placementEndEntryId = entries[audio.placementEndEntryId] ?? audio.placementEndEntryId
            return audio
        }
        result.cache?.entryOffsets = scope.cache?.entryOffsets.map { offsets in
            Dictionary(offsets.map { (entries[$0.key] ?? $0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        }
        result.cache?.sourceOffsets = scope.cache?.sourceOffsets.map { offsets in
            Dictionary(offsets.map { (keyMap[$0.key] ?? $0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        }
        return result
    }
    let bridges = shot.joinBridgeVersions.map { original in
        var bridge = original
        bridge.versionId = fresh("join", bridge.versionId)
        bridge.cutId = fresh("cut", bridge.cutId)
        bridge.sourceSegmentKey = keyMap[bridge.sourceSegmentKey] ?? bridge.sourceSegmentKey
        return bridge
    }
    let looks = shot.lookVersions.map { original in
        var look = original; look.versionId = fresh("look", look.versionId); return look
    }
    return ShotOutputScopeCopy(scopes: shot.outputScopes.map(copy), scopeIds: scopeIds, bridges: bridges, looks: looks)
}

/// Re-keying a branch changes placement identity, not picture or sound. Save
/// that exact correspondence once, so later edits still invalidate lineage.
func rebindCopiedScopeCaches(from source: ProjectShot, to target: ProjectShot, scopeIds: [String: String]) -> ProjectShot {
    var result = target
    func visit(_ scopes: [ShotOutputScope]) {
        for scope in scopes {
            visit(scope.children)
            guard let id = scopeIds[scope.scopeId], var copied = result.outputScope(id) else { continue }
            let original = shotOutputFingerprint(scope.project(from: source))
            let mapped = shotOutputFingerprint(copied.project(from: result))
            var aliases = copied.lineageAliases ?? [:]
            aliases[original] = mapped
            for (origin, previous) in scope.lineageAliases ?? [:] where previous == original { aliases[origin] = mapped }
            copied.lineageAliases = aliases
            if scope.cache?.fingerprint == original { copied.cache?.fingerprint = mapped }
            result = result.replacingOutputScope(copied)
        }
    }
    visit(source.outputScopes)
    return result
}


func shotContinuationSelectionEdit(before: ProjectShot?, after: ProjectShot?, outcome: ShotContinuationOutcome) -> ShotPictureStateEdit? {
    guard let before, let after, case .ready(let takeId) = outcome,
          after.continuationRecords.contains(where: { $0.selectedTakeId == takeId }) else { return nil }
    return ShotPictureStateEdit(before: before.pictureStateSnapshot(), after: after.pictureStateSnapshot())
}


enum ShotOutputScopePreparation: Equatable {
    case preparing
    case failed(String)
    var message: String {
        switch self {
        case .preparing: return "Updating earlier cut · No generation charge"
        case .failed(let reason): return "Earlier cut could not update: \(reason)"
        }
    }
}

func shotMissingOutputScopes(_ shot: ProjectShot, fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [String] {
    shot.outputScopes.filter { !fileExists($0.cache?.videoPath ?? "") }.map(\.scopeId)
}

func shotOutputSourceOffsets(shot: ProjectShot, assembly: ShotCutAssembly) -> [String: Double] {
    var result = Dictionary(assembly.planClips.map {
        ($0.segmentKey, assembly.outputSeconds(forMaterialSeconds: $0.materialStartSeconds))
    }, uniquingKeysWith: { first, _ in first })
    for scope in shot.outputScopes {
        guard let group = assembly.planClips.first(where: { $0.segmentKey == scope.placementKey }) else { continue }
        for (key, local) in scope.cache?.sourceOffsets ?? [:] {
            result[key] = assembly.outputSeconds(forMaterialSeconds: group.materialStartSeconds + local)
        }
    }
    return result
}

func shotOutputEntryOffsets(shot: ProjectShot, assembly: ShotCutAssembly) -> [String: Double] {
    Dictionary(shot.entries.compactMap { entry in
        shotEntryFocusSeconds(shot: shot, entryId: entry.entryId, assembly: assembly).map { (entry.entryId, $0) }
    }, uniquingKeysWith: { first, _ in first })
}
