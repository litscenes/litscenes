import Foundation

/// A derived file may move while the edited picture it represents stays the same.
/// Ordinary generated media continues to use its immutable saved file identity.
struct ShotPictureScopeReference: Codable, Hashable, Sendable {
    var scopeId: String
    var fingerprint: String

    func remapping(_ ids: [String: String]) -> Self {
        Self(scopeId: ids[scopeId] ?? scopeId, fingerprint: fingerprint)
    }
}

struct ShotPictureSource {
    var path: String
    var scope: ShotPictureScopeReference?
}

/// Active selection and retention are different questions. Every picture edit
/// uses this catalog, including when its base span is temporarily razored away.
struct ShotPictureSourceCatalog {
    var active: [String: ShotPictureSource] = [:]
    var retainedPaths = Set<String>()
    private var artifactPaths: [String: String] = [:]
    private var scopes: [String: ShotOutputScope] = [:]
    private var reviewedScopes: [ShotOutputScope] = []

    init(shot: ProjectShot) {
        func retain(_ path: String) { if !path.trimmed.isEmpty { retainedPaths.insert(path) } }
        func retainScope(_ scope: ShotOutputScope) {
            if let cache = scope.cache { retain(cache.videoPath) }
            scope.children.forEach(retainScope)
        }
        func retainReview(_ scope: ShotOutputScope) {
            reviewedScopes.append(scope)
            if let cache = scope.cache { retain(cache.videoPath) }
            scope.children.forEach(retainReview)
        }
        for version in shot.renderVersions {
            retain(version.videoPath)
            artifactPaths[version.versionId] = version.videoPath
            version.segmentClips.forEach { retain($0.clipPath) }
        }
        for record in shot.continuationRecords {
            for clip in record.preservedSourceClips where !clip.clipPath.trimmed.isEmpty {
                active[clip.placementKey] = ShotPictureSource(path: clip.clipPath)
            }
        }
        for seed in shot.seedSegmentClips where !seed.clipPath.trimmed.isEmpty {
            retain(seed.clipPath)
            active[seed.placementKey] = ShotPictureSource(path: seed.clipPath)
        }
        if let version = shot.playableRenderVersion {
            for clip in version.segmentClips where !clip.clipPath.trimmed.isEmpty {
                active[clip.placementKey] = ShotPictureSource(path: clip.clipPath)
            }
            if !version.videoPath.trimmed.isEmpty {
                active[shotArtifactSegmentKey(versionId: version.versionId)] = ShotPictureSource(path: version.videoPath)
            }
        }
        for record in shot.continuationRecords {
            record.preservedSourceClips.forEach { retain($0.clipPath) }
            for take in record.takes {
                if let clip = take.segmentClip { retain(clip.clipPath) }
                retain(take.providerOutputPath)
                retain(take.anchor.tailClipPath)
                if let review = take.anchor.outputReview { retainReview(review.scope) }
            }
            if let clip = record.selectedTake?.segmentClip, !clip.clipPath.trimmed.isEmpty {
                active[clip.placementKey] = ShotPictureSource(path: clip.clipPath)
            }
        }
        for scope in shot.outputScopes {
            retainScope(scope)
            scopes[scope.scopeId] = scope
            if let cache = scope.cache {
                active[scope.placementKey] = ShotPictureSource(path: cache.videoPath,
                    scope: ShotPictureScopeReference(scopeId: scope.scopeId, fingerprint: cache.fingerprint))
            }
        }
    }

    var activePaths: [String: String] { active.mapValues(\.path) }
    var activeScopeReferences: [String: ShotPictureScopeReference] { active.compactMapValues(\.scope) }

    func scopeReference(key: String, path: String) -> ShotPictureScopeReference? {
        guard let source = active[key], let current = source.scope else { return nil }
        if source.path == path { return current }
        // Legacy references recover only from recorded review/cache evidence.
        for prior in reviewedScopes where prior.cache?.videoPath == path {
            guard let fingerprint = prior.cache?.fingerprint,
                  prior.scopeId == current.scopeId || scopes[current.scopeId]?.lineageAliases?[fingerprint] != nil else { continue }
            return ShotPictureScopeReference(scopeId: current.scopeId, fingerprint: fingerprint)
        }
        return nil
    }

    func resolved(key: String, path: String, scope: ShotPictureScopeReference?) -> ShotPictureSource {
        let reference = scope ?? scopeReference(key: key, path: path)
        guard let reference, let source = active[key], let current = source.scope,
              reference.scopeId == current.scopeId,
              reference.fingerprint == current.fingerprint
                || scopes[current.scopeId]?.lineageAliases?[reference.fingerprint] == current.fingerprint else {
            return ShotPictureSource(path: path, scope: reference)
        }
        return source
    }

    func retains(key: String, path: String, scope: ShotPictureScopeReference?) -> Bool {
        if let versionId = shotArtifactSegmentKeyVersionId(key) { return artifactPaths[versionId] == path }
        return retainedPaths.contains(path) || scope.map { scopes[$0.scopeId] != nil } == true
    }
}

/// Resolve executable cache paths without rewriting stored edits or paid inputs.
func shotResolvingPictureSources(_ shot: ProjectShot) -> ProjectShot {
    let catalog = ShotPictureSourceCatalog(shot: shot)
    var result = shot
    result.pictureInsertions = shot.pictureInsertions.map { insertion in
        var copy = insertion
        let source = catalog.resolved(key: copy.sourceSegmentKey, path: copy.sourceClipPath, scope: copy.sourceScope)
        copy.sourceClipPath = source.path
        copy.sourceScope = source.scope
        return copy
    }
    result.cutList.segmentCuts = shot.cutList.segmentCuts.map { cut in
        var copy = cut
        guard !copy.clipPath.isEmpty else { return copy }
        let source = catalog.resolved(key: copy.segmentKey, path: copy.clipPath, scope: copy.sourceScope)
        copy.clipPath = source.path
        copy.sourceScope = source.scope
        return copy
    }
    return result
}

/// Ordered source coverage, independent of playback rate and derived split IDs.
/// Speed may change timing and sound, but cannot remove or reorder pictures.
func shotSpeedEditPreservesPicture(before: ShotCutAssembly, after: ShotCutAssembly) -> Bool {
    struct Span: Equatable {
        var key: String
        var path: String
        var start: Double
        var end: Double
    }
    func coverage(_ assembly: ShotCutAssembly) -> [Span] {
        var result: [Span] = []
        for item in assembly.playbackItems where item.loopPass == 0 {
            guard let range = item.keepRange else { return [] }
            let span = Span(key: item.segmentKey, path: item.url.path, start: range.start, end: range.end)
            if let last = result.last, last.key == span.key, last.path == span.path,
               abs(last.end - span.start) < 1.0 / 240.0 {
                result[result.count - 1].end = span.end
            } else { result.append(span) }
        }
        return result
    }
    let previous = coverage(before), candidate = coverage(after)
    guard !previous.isEmpty, previous.count == candidate.count else { return false }
    return zip(previous, candidate).allSatisfy { old, new in
        old.key == new.key && old.path == new.path
            && abs(old.start - new.start) < 1.0 / 240.0 && abs(old.end - new.end) < 1.0 / 240.0
    }
}

struct ShotSectionRateResult {
    var edit: ShotPictureStateEdit?
    var message: String = ""
}
