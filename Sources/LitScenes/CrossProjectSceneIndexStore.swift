import Foundation

/// Read-only scene snapshots for every project EXCEPT the loaded one (the
/// loaded project is always composed live from the engine). Decodes run
/// off-main through the same canonical store loaders that project loading
/// uses — reads are idempotent (schema ensure + lazy legacy import).
///
/// Invalidation is event-based, not mtime-based: the documents of an unloaded
/// project only change while it is loaded in this app, so a project's
/// snapshot is dropped the moment it stops being `currentProject` (the hop
/// flow calls `invalidate`), and a manual refresh affordance covers the rest.
@MainActor
final class CrossProjectSceneIndexStore: ObservableObject {
    @Published private(set) var snapshotsByProjectId: [String: ProjectSceneSnapshot] = [:]
    @Published private(set) var isRefreshing = false

    func invalidate(projectId: String) {
        snapshotsByProjectId.removeValue(forKey: projectId)
    }

    func invalidateAll() {
        snapshotsByProjectId = [:]
    }

    /// Decode every project except the loaded one, skipping projects that
    /// already hold a snapshot (invalidate first to force one).
    func refreshMissing(projects: [ProjectRecord], excludingProjectId: String?) async {
        guard !isRefreshing else { return }
        let pending = projects.filter {
            $0.projectId != excludingProjectId && snapshotsByProjectId[$0.projectId] == nil
        }
        guard !pending.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        for project in pending {
            let snapshot = await Task.detached(priority: .utility) {
                Self.decodeSnapshot(project: project)
            }.value
            snapshotsByProjectId[project.projectId] = snapshot
        }
    }

    /// One project's decode: timeline → visible shots; lenses → ready-still
    /// path map (dropped immediately after projection); media inventory only
    /// when a visible entry references footage. Pure over the pure laws in
    /// ScenesV2Models — testable without the store.
    nonisolated static func decodeSnapshot(project: ProjectRecord) -> ProjectSceneSnapshot {
        let contextStore = ProjectContextStore()
        let timeline = contextStore.loadShotTimeline(for: project)
        let lenses = contextStore.loadProjectLenses(for: project)
        let visible = timeline.visibleShots

        var frameStillPathById: [String: String] = [:]
        for lens in lenses.lenses {
            for image in lens.sortedHeroImages
            where image.status == "ready" && !image.imagePath.trimmed.isEmpty {
                if frameStillPathById[image.imageId] == nil {
                    frameStillPathById[image.imageId] = image.imagePath
                }
            }
        }

        let referencedClipIds = Set(
            visible.flatMap(\.entries).map(\.clipMediaId).filter { !$0.isEmpty }
        )
        var footageThumbnailPathByMediaId: [String: String] = [:]
        if !referencedClipIds.isEmpty {
            for item in MediaLibraryStore().loadInventory(for: project)
            where referencedClipIds.contains(item.mediaId) {
                footageThumbnailPathByMediaId[item.mediaId] = item.thumbnailPath
            }
        }

        let scenes = visible.enumerated().map { index, shot in
            SceneIndexEntry(
                projectId: project.projectId,
                shotId: shot.shotId,
                displayName: sceneDisplayName(shot: shot, index: index),
                entryCount: shot.entries.count,
                posterCandidatePaths: scenePosterCandidatePaths(
                    entries: shot.entries,
                    frameStillPathById: frameStillPathById,
                    footageThumbnailPathByMediaId: footageThumbnailPathByMediaId
                ),
                badge: sceneRenderBadgeFromDocument(shot: shot)
            )
        }
        return ProjectSceneSnapshot(
            projectId: project.projectId,
            scenes: scenes,
            loadIssue: "",
            refreshedAt: Date()
        )
    }
}
