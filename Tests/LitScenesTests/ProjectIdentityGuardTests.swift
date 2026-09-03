import Foundation
import Testing
@testable import LitScenes

// THE PROJECT IDENTITY LAW: a document naming a project saves only into that
// project's store. Pinned when a stale in-memory project
// timeline raced a project switch and replaced the active project's timeline
// wholesale (the payload's own project_id said one project's id inside another's row).

@Test func crossProjectTimelineWriteRefusesAndMatchingWritesLand() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_identity_guard_\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let projectLibrary = ProjectLibrary(root: root)
    let home = try projectLibrary.createProject(named: "Alpha")
    _ = try LitScenesDesktopDatabase.prepareProjectDatabase(for: home, projectLibrary: projectLibrary)
    let contextStore = ProjectContextStore(projectLibrary: projectLibrary)

    // A foreign document must refuse — nothing written.
    var foreign = ProjectShotTimelineDocument.empty(projectId: "project_foreign_other")
    foreign.shots = [ProjectShot(shotId: "shot_foreign", name: "Bleed", entries: [])]
    #expect(throws: (any Error).self) {
        try contextStore.saveShotTimeline(foreign, for: home)
    }
    #expect(contextStore.loadShotTimeline(for: home).shots.isEmpty)

    // The project's own document lands, and an empty-id document (legal
    // legacy in-memory state) lands stamped.
    var own = ProjectShotTimelineDocument.empty(projectId: home.projectId)
    own.shots = [ProjectShot(shotId: "shot_own", name: "Mine", entries: [])]
    try contextStore.saveShotTimeline(own, for: home)
    #expect(contextStore.loadShotTimeline(for: home).shots.map(\.shotId) == ["shot_own"])

    var unstamped = ProjectShotTimelineDocument.empty(projectId: "")
    unstamped.shots = [ProjectShot(shotId: "shot_unstamped", name: "", entries: [])]
    try contextStore.saveShotTimeline(unstamped, for: home)
    #expect(contextStore.loadShotTimeline(for: home).projectId == home.projectId)

    // The stage-set gate and the atomic pair share the law.
    var foreignStages = ProjectStageSetDocument.empty(projectId: "project_foreign_other")
    #expect(throws: (any Error).self) {
        try contextStore.saveStageSet(foreignStages, for: home)
    }
    foreignStages.projectId = home.projectId
    try contextStore.saveStageSet(foreignStages, for: home)
    #expect(throws: (any Error).self) {
        try contextStore.saveShotTimelineAndStageSet(
            timeline: foreign,
            stageSet: foreignStages,
            for: home
        )
    }
}
