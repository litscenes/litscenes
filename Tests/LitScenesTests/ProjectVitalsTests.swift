import Foundation
import Testing
@testable import LitScenes

// The vitals probe is the instrument that turns "this library feels slow" into
// numbers. Two properties matter most: it must never mutate the project it
// measures, and it must report unknowns as unknown rather than as zero.

@Test func projectVitalsTakesPerFrameDescribesStackDepth() {
    var vitals = ProjectVitals(projectName: "atlas")
    vitals.heroImageCount = 980
    vitals.heroImageFrameCount = 42

    // A real reference-machine reading.
    #expect(abs(vitals.takesPerFrame - 23.333) < 0.01)
}

@Test func projectVitalsTakesPerFrameIsZeroWithoutFrames() {
    var vitals = ProjectVitals()
    vitals.heroImageCount = 12
    vitals.heroImageFrameCount = 0

    // Never divide by zero into a NaN that then renders as "nan per frame".
    #expect(vitals.takesPerFrame == 0)
}

@Test func projectVitalsTotalsTheThreeBuckets() {
    var vitals = ProjectVitals()
    vitals.storyBytes = 900
    vitals.libraryBytes = 90
    vitals.databaseBytes = 9

    #expect(vitals.totalBytes == 999)
}

@Test func projectVitalsTableReadingReportsUnknownSizeHonestly() {
    let unknown = ProjectVitalsTableReading(table: "t", rowCount: 5, byteCount: -1)
    let known = ProjectVitalsTableReading(table: "t", rowCount: 5, byteCount: 2048)

    // -1 means "this SQLite build has no dbstat", which must not read as 0 B.
    #expect(!unknown.hasByteCount)
    #expect(known.hasByteCount)
}

@Test func projectVitalsSummaryNamesTheGrowthNumbers() {
    var vitals = ProjectVitals(projectName: "atlas")
    vitals.storyBytes = 890_000_000
    vitals.heroImageCount = 980
    vitals.heroImageFrameCount = 42
    vitals.registryRowCount = 13
    vitals.registryDeadRowCount = 0
    vitals.tables = [ProjectVitalsTableReading(table: "project_lens_hero_images", rowCount: 980, byteCount: 12_480_000)]

    let text = vitals.summaryLines.joined(separator: "\n")
    #expect(text.contains("atlas"))
    #expect(text.contains("980 takes across 42 frames"))
    #expect(text.contains("23.3 per frame"))
    #expect(text.contains("project_lens_hero_images: 980 rows"))
    // A healthy registry says nothing about dead rows.
    #expect(!text.contains("dead"))
}

@Test func projectVitalsSummaryFlagsDeadRegistryRows() {
    var vitals = ProjectVitals(projectName: "atlas")
    vitals.registryRowCount = 1475
    vitals.registryDeadRowCount = 1378

    #expect(vitals.summaryLines.contains { $0.contains("1475 projects (1378 dead)") })
}

@Test func projectVitalsProbeMeasuresARealProjectWithoutMutatingIt() throws {
    // Safe to use the default library: test runs are sandboxed away from the
    // user's real Application Support (see TestEnvironmentIsolationTests).
    let library = ProjectLibrary()
    let project = try library.createProject(named: "Vitals Probe \(UUID().uuidString.prefix(6))")
    let directory = library.projectDirectory(for: project)
    let databaseURL = directory.appendingPathComponent("LitScenes.db")

    let before = try FileManager.default.attributesOfItem(atPath: databaseURL.path)[.modificationDate] as? Date
    let vitals = ProjectVitalsProbe.measure(project: project, projectLibrary: library)
    let after = try FileManager.default.attributesOfItem(atPath: databaseURL.path)[.modificationDate] as? Date

    #expect(vitals.projectId == project.projectId)
    #expect(vitals.databaseBytes > 0)
    // A fresh project has the schema but no takes.
    #expect(vitals.heroImageCount == 0)
    #expect(vitals.takesPerFrame == 0)
    // Measuring must not touch the file it measures.
    #expect(before == after)
}

@Test func projectVitalsProbeSurvivesAMissingProjectDirectory() {
    let library = ProjectLibrary(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes-vitals-absent-\(UUID().uuidString)", isDirectory: true))
    let project = ProjectRecord(
        projectId: "project_absent",
        name: "Absent",
        createdAt: "t0",
        updatedAt: "t0",
        sessionCount: 0,
        lastSessionId: nil
    )

    // Measuring a project whose files are gone reports zeros, never crashes —
    // exactly the state the swept registry rows were in.
    let vitals = ProjectVitalsProbe.measure(project: project, projectLibrary: library)
    #expect(vitals.totalBytes == 0)
    #expect(vitals.tables.isEmpty)
}

@Test func projectVitalsReadOnlyDatabaseRefusesAMissingFile() {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes-vitals-nope-\(UUID().uuidString).db")

    // READONLY without CREATE: the probe can never bring a database into being.
    #expect(ProjectVitalsReadOnlyDatabase(url: url) == nil)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}
