import Foundation
import SQLite3
import Testing
@testable import LitScenes

@Test
func existingProjectDatabaseGainsStyleTermRefsTableViaV8Migration() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_goal_style_refs_migration_\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let projectLibrary = ProjectLibrary(root: root)
    let project = try projectLibrary.createProject(named: "Goal Style Refs Migration")

    let databaseURL = try LitScenesDesktopDatabase.prepareProjectDatabase(for: project, projectLibrary: projectLibrary)

    // Simulate a project database created before the V8 migration existed.
    try LitScenesDesktopDatabase.withConnection(url: databaseURL, context: "Test DB") { connection in
        try litScenesSQLiteExecute(connection, "DROP TABLE IF EXISTS project_goal_style_term_refs;", context: "Test DB")
        try litScenesSQLiteExecute(
            connection,
            "DELETE FROM project_schema_migrations WHERE version = '\(LitScenesDesktopDatabase.projectGoalStyleRefsSchemaVersion)';",
            context: "Test DB"
        )
    }

    // Re-preparing the database must apply V8 and recreate the table.
    _ = try LitScenesDesktopDatabase.prepareProjectDatabase(for: project, projectLibrary: projectLibrary)

    // The full goal save/load path exercises the table end to end.
    let contextStore = ProjectContextStore(projectLibrary: projectLibrary)
    var goal = ProjectGoalDocumentV2.empty(projectId: project.projectId)
    var brief = ProjectGoalBriefV2.empty()
    brief.contentType = .documentary
    brief.goal = "Night shift stories"
    brief.styleTermRefs = [
        ProjectGoalStyleTermRef(term: "Mysterious", kind: .mood, weight: 1.2, rationale: "vigil tone"),
        ProjectGoalStyleTermRef(term: "nocturne", kind: .collection, weight: 1.3, rationale: "after-dark lane")
    ]
    goal.appendVersion(brief: brief, changeSummary: "Test goal", model: "test", now: DateFormats.now())
    try contextStore.saveProjectGoalV2(goal, for: project)

    let loaded = try contextStore.loadProjectGoalV2(for: project)
    let loadedBrief = try #require(loaded.activeVersion?.brief)
    #expect(loadedBrief.styleTermRefs.count == 2)
    #expect(loadedBrief.styleTermRefs.first?.term.lowercased() == "mysterious")
    #expect(loadedBrief.styleTermRefs.last?.kind == .collection)
}
