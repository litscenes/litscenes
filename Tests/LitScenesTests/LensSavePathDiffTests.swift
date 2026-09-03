import Foundation
import SQLite3
import Testing
@testable import LitScenes

// Saving a Scene Plan used to DELETE the lens state row, whose cascade wiped
// every version, lens snapshot, term, ingredient and hero image, and then
// re-inserted all of it. Since a version payload embeds the whole lens
// (heroImages included) and `saveLensHeroImages` saves on every image that
// lands, a saturated project rewrote ~11 MB per save.
//
// These tests pin the diff. SQLite assigns a fresh `rowid` when a row is
// deleted and re-inserted, so a stable rowid is direct proof the row was left
// alone — which is exactly the property the old code could not have.

private func lensDiffTestProject() throws -> (ProjectRecord, ProjectLibrary, ProjectContextStore) {
    // Test runs are sandboxed away from real data (TestEnvironmentIsolationTests).
    let library = ProjectLibrary()
    let project = try library.createProject(named: "Lens Diff \(UUID().uuidString.prefix(6))")
    return (project, library, ProjectContextStore(projectLibrary: library))
}

private func lensDiffTestDocument(projectId: String, versionCount: Int) -> ProjectLensSetDocument {
    var document = ProjectLensSetDocument.bootstrap(projectId: projectId, now: "2026-07-28T00:00:00Z")
    for index in 0..<versionCount {
        var body = LensBody.empty()
        body.title = "Version \(index)"
        document.appendVersion(
            lenses: [ProjectLens(lensId: "lens_canon", body: body)],
            scratchDrafts: [],
            selectedLensId: "lens_canon",
            selectedScratchId: nil,
            changeSummary: "v\(index)",
            model: "test",
            now: "2026-07-28T00:00:0\(index)Z"
        )
    }
    return document
}

/// One stored version row. `rowid` proves whether the row was left alone;
/// `fingerprint` proves whether its content was updated. Both are needed:
/// SQLite hands out `max(rowid) + 1`, so deleting and re-inserting the LAST row
/// reuses its rowid and a rowid check alone cannot see that rewrite.
private struct StoredVersionProbe: Equatable {
    var rowId: Int64
    var fingerprint: String
}

private func lensVersionRows(project: ProjectRecord, library: ProjectLibrary) throws -> [String: StoredVersionProbe] {
    let url = library.projectDirectory(for: project).appendingPathComponent("LitScenes.db")
    var handle: OpaquePointer?
    guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
        throw ScreenGraphError.capture("could not open \(url.path)")
    }
    defer { sqlite3_close(handle) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
        handle,
        "SELECT version_id, rowid, content_fingerprint FROM project_lens_versions;",
        -1, &statement, nil
    ) == SQLITE_OK, let statement else {
        throw ScreenGraphError.capture("prepare failed")
    }
    defer { sqlite3_finalize(statement) }
    var rows: [String: StoredVersionProbe] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
        rows[String(cString: sqlite3_column_text(statement, 0))] = StoredVersionProbe(
            rowId: sqlite3_column_int64(statement, 1),
            fingerprint: String(cString: sqlite3_column_text(statement, 2))
        )
    }
    return rows
}

@Test func savingAnUnchangedLensDocumentRewritesNothing() throws {
    let (project, library, store) = try lensDiffTestProject()
    let document = lensDiffTestDocument(projectId: project.projectId, versionCount: 6)

    try store.saveProjectLenses(document, for: project)
    let first = try lensVersionRows(project: project, library: library)
    try store.saveProjectLenses(document, for: project)
    let second = try lensVersionRows(project: project, library: library)

    #expect(!first.isEmpty)
    // Every row untouched. Under the old delete-and-reinsert every rowid moved.
    #expect(first == second)
}

@Test func savingAChangedVersionRewritesOnlyThatVersion() throws {
    let (project, library, store) = try lensDiffTestProject()
    var document = lensDiffTestDocument(projectId: project.projectId, versionCount: 6)

    try store.saveProjectLenses(document, for: project)
    let before = try lensVersionRows(project: project, library: library)

    // What a hero image landing does: mutate the active version in place.
    var body = LensBody.empty()
    body.title = "Edited active version"
    document.updateActiveVersion(
        lenses: [ProjectLens(lensId: "lens_canon", body: body)],
        now: "2026-07-28T01:00:00Z"
    )
    let activeVersionId = document.activeVersionId
    try store.saveProjectLenses(document, for: project)
    let after = try lensVersionRows(project: project, library: library)

    #expect(Set(before.keys) == Set(after.keys))
    // The edited version was rewritten: its stored fingerprint moved.
    #expect(before[activeVersionId]?.fingerprint != after[activeVersionId]?.fingerprint)
    // Everything else was left strictly alone.
    for (versionId, probe) in before where versionId != activeVersionId {
        #expect(after[versionId] == probe, "version \(versionId) was rewritten but did not change")
    }
}

@Test func savingAPrunedDocumentDropsOnlyTheRemovedVersions() throws {
    let (project, library, store) = try lensDiffTestProject()
    var document = lensDiffTestDocument(projectId: project.projectId, versionCount: 6)
    try store.saveProjectLenses(document, for: project)
    let before = try lensVersionRows(project: project, library: library)

    // Front-pruning is what the 35-version cap does; survivors shift down into
    // the vacated version_order slots.
    let dropped = document.versions.first!.versionId
    document.versions.removeFirst()
    try store.saveProjectLenses(document, for: project)
    let after = try lensVersionRows(project: project, library: library)

    #expect(after[dropped] == nil)
    #expect(after.count == before.count - 1)
    // The survivors only moved order — their rows were not rewritten.
    for (versionId, probe) in after {
        #expect(before[versionId] == probe, "surviving version \(versionId) was needlessly rewritten")
    }
}

/// Counts stored lens snapshots. If lazy loading ever writes its own emptiness
/// back, this is the number that collapses.
private func storedLensSnapshotCount(project: ProjectRecord, library: ProjectLibrary) throws -> Int {
    let url = library.projectDirectory(for: project).appendingPathComponent("LitScenes.db")
    var handle: OpaquePointer?
    guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let handle else {
        throw ScreenGraphError.capture("could not open \(url.path)")
    }
    defer { sqlite3_close(handle) }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, "SELECT COUNT(*) FROM project_lens_version_lenses;", -1, &statement, nil) == SQLITE_OK,
          let statement else {
        throw ScreenGraphError.capture("prepare failed")
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int64(statement, 0))
}

@Test func loadOnlyHydratesTheVersionWhoseLensIsActuallyRead() throws {
    let (project, library, store) = try lensDiffTestProject()
    let document = lensDiffTestDocument(projectId: project.projectId, versionCount: 6)
    try store.saveProjectLenses(document, for: project)

    let loaded = store.loadProjectLenses(for: project)

    // Exactly one version carries its lens in memory…
    #expect(loaded.versionIdsWithoutLoadedLenses.count == loaded.versions.count - 1)
    #expect(loaded.versions.filter { !$0.lenses.isEmpty }.count == 1)
    // …and it is the one the UI reads.
    #expect(loaded.hasHydratedLenses(loaded.activeVersionId))
    #expect(loaded.lenses.count == 1)
    #expect(loaded.lenses.first?.lensId == "lens_canon")
    // The history itself is intact — the versions are all still there.
    #expect(loaded.versions.count == document.versions.count)
}

@Test func savingAfterALazyLoadPreservesEveryStoredSnapshot() throws {
    // The load path's one real hazard: an unhydrated version's empty `lenses`
    // must never be mistaken for "this version has no lens" and written back.
    let (project, library, store) = try lensDiffTestProject()
    let document = lensDiffTestDocument(projectId: project.projectId, versionCount: 6)
    try store.saveProjectLenses(document, for: project)
    let snapshotsBefore = try storedLensSnapshotCount(project: project, library: library)
    let rowsBefore = try lensVersionRows(project: project, library: library)
    #expect(snapshotsBefore == 6)

    // Load (hydrating one version), then save straight back — the exact
    // sequence the engine performs on project open followed by any edit.
    var reloaded = store.loadProjectLenses(for: project)
    try store.saveProjectLenses(reloaded, for: project)

    #expect(try storedLensSnapshotCount(project: project, library: library) == snapshotsBefore)
    #expect(try lensVersionRows(project: project, library: library) == rowsBefore)

    // And again with a real edit to the active version mixed in.
    var body = LensBody.empty()
    body.title = "Edited after lazy load"
    reloaded.updateActiveVersion(lenses: [ProjectLens(lensId: "lens_canon", body: body)], now: "2026-07-28T03:00:00Z")
    try store.saveProjectLenses(reloaded, for: project)

    #expect(try storedLensSnapshotCount(project: project, library: library) == snapshotsBefore)
    let final = store.loadProjectLenses(for: project)
    #expect(final.versions.count == document.versions.count)
    #expect(final.lenses.first?.body.title == "Edited after lazy load")
}

@Test func appendingAVersionAfterALazyLoadPersistsIt() throws {
    // Observed while generating a frame in a real project:
    //   "Lens version lens_set_5e5b4a79d56c is unhydrated but has no stored
    //    row — refusing to write an empty snapshot."
    // Generating a frame appends a NEW version to a lazily-loaded document.
    // The load state used to name the HYDRATED versions, so a version created
    // after the load was absent from that set, looked unloaded, and the save
    // refused it. The set now names only the rows the loader skipped, so
    // anything appended later is in memory by default.
    let (project, library, store) = try lensDiffTestProject()
    let document = lensDiffTestDocument(projectId: project.projectId, versionCount: 6)
    try store.saveProjectLenses(document, for: project)
    let snapshotsBefore = try storedLensSnapshotCount(project: project, library: library)

    var reloaded = store.loadProjectLenses(for: project)
    var body = LensBody.empty()
    body.title = "Frame generated after load"
    reloaded.appendVersion(
        lenses: [ProjectLens(lensId: "lens_canon", body: body)],
        scratchDrafts: [],
        selectedLensId: "lens_canon",
        selectedScratchId: nil,
        changeSummary: "Generated a frame",
        model: "test",
        now: "2026-07-28T05:00:00Z"
    )
    let appendedId = reloaded.activeVersionId
    #expect(reloaded.hasHydratedLenses(appendedId))

    try store.saveProjectLenses(reloaded, for: project)

    let final = store.loadProjectLenses(for: project)
    #expect(final.versions.contains { $0.versionId == appendedId })
    #expect(final.activeVersionId == appendedId)
    #expect(final.lenses.first?.body.title == "Frame generated after load")
    // The new snapshot landed and no earlier one was lost.
    #expect(try storedLensSnapshotCount(project: project, library: library) == snapshotsBefore + 1)
}

@Test func lazyLoadKeepsTheCanonicalPickWhenTheActiveVersionHasNoLens() throws {
    // A lens-less active version must still resolve to the newest lens-bearing
    // one, exactly as a full load's `versions.last(where: { !lenses.isEmpty })`
    // fallback did.
    let (project, _, store) = try lensDiffTestProject()
    var document = lensDiffTestDocument(projectId: project.projectId, versionCount: 3)
    document.appendVersion(
        lenses: [],
        scratchDrafts: [],
        selectedLensId: nil,
        selectedScratchId: nil,
        changeSummary: "lens-less tail",
        model: "test",
        now: "2026-07-28T04:00:00Z"
    )
    let lensLessActiveId = document.activeVersionId
    try store.saveProjectLenses(document, for: project)

    let loaded = store.loadProjectLenses(for: project)

    #expect(loaded.activeVersionId != lensLessActiveId)
    #expect(loaded.lenses.count == 1)
    #expect(loaded.hasHydratedLenses(loaded.activeVersionId))
}

@Test func reloadingAfterADiffedSaveReturnsTheSameDocument() throws {
    // The diff must not trade correctness for speed: what comes back has to
    // match what a full rewrite would have produced.
    let (project, _, store) = try lensDiffTestProject()
    var document = lensDiffTestDocument(projectId: project.projectId, versionCount: 4)
    try store.saveProjectLenses(document, for: project)

    var body = LensBody.empty()
    body.title = "Second pass"
    document.updateActiveVersion(lenses: [ProjectLens(lensId: "lens_canon", body: body)], now: "2026-07-28T02:00:00Z")
    try store.saveProjectLenses(document, for: project)

    let reloaded = store.loadProjectLenses(for: project)
    #expect(reloaded.versions.map(\.versionId) == document.versions.map(\.versionId))
    #expect(reloaded.activeVersionId == document.activeVersionId)
    #expect(reloaded.lenses.first?.body.title == "Second pass")
}
