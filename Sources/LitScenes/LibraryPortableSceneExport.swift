import Foundation

extension LibraryEngine {
    /// Capture first, then prepare the same local movie used by Copy/Share.
    /// Export never invokes inference or promotes project ideas to frame claims.
    func exportPortableScene(shotId: String, into directory: URL) async throws -> PortableSceneResult {
        guard let project = currentProject,
              let shot = shotTimeline.visibleShots.first(where: { $0.shotId == shotId }) else {
            throw ScreenGraphError.capture("Open a saved scene to export it.")
        }
        let lookup = projectWideFrameLookup
        let media = Dictionary(items.map { ($0.mediaId, $0) }, uniquingKeysWith: { first, _ in first })
        let frames = shot.entries.enumerated().map { index, entry -> PortableSceneFrame in
            let frame = lookup[entry.frameImageId]
            let clip = media[entry.clipMediaId]
            let path = entry.isClip ? clip?.path : frame?.imagePath
            return PortableSceneFrame(id: entry.entryId,
                title: frame?.label.trimmed.nilIfEmpty ?? "Frame \(index + 1)",
                sourceURL: path?.trimmed.nilIfEmpty.map { URL(fileURLWithPath: $0) },
                isVideo: entry.isClip, startSeconds: entry.clipStartSeconds ?? 0,
                endSeconds: entry.clipEndSeconds, skipped: entry.isSkipped)
        }
        let ideas = (lensContext.response?.selectedMeaningNodes ?? []).map {
            PortableSceneIdea(id: $0.id, slug: $0.slug, kind: $0.kind, title: $0.name,
                definition: $0.definition, status: $0.status)
        }
        let index = shotTimeline.visibleShots.firstIndex(where: { $0.shotId == shotId }) ?? 0
        var input = PortableSceneInput(projectId: project.projectId, projectTitle: project.name,
            sceneId: shotId, sceneTitle: sceneDisplayName(shot: shot, index: index), frames: frames, ideas: ideas)
        if shot.playableRenderVersion != nil || shot.activeLookVersion != nil || !shot.seedSegmentClips.isEmpty || shot.entries.contains(where: \.isClip) {
            switch await prepareShotVideoForSharing(shotId: shotId, fingerprint: shotOutputFingerprint(shot)) {
            case .success(let preview):
                input.videoURL = URL(fileURLWithPath: preview.clip.clipPath)
                input.videoDuration = preview.durationSeconds
            case .failure:
                input.warnings.append("The current video could not be prepared. The available storyboard frames are included.")
            }
        }
        let snapshot = input
        return try await Task.detached(priority: .utility) {
            try await PortableSceneExport.write(snapshot, into: directory)
        }.value
    }
}
