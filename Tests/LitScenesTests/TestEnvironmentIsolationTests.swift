import Foundation
import Testing
@testable import LitScenes

// A test run must leave the user's real LitScenes data untouched.
//
// It did not, for a long time. Several stores default-construct
// `ProjectLibrary()`, and `SoundSceneTimelineStore.shared` is an actor
// singleton that hardcodes one with no injection point, so any test reaching it
// called `prepareProjectDatabase` against the REAL root — registering a row in
// the user's registry and creating a directory in the user's projects folder,
// regardless of the temp root the fixture passed. Eventually that had
// accumulated 1,275 dead registry rows and 84 stray project directories.
//
// The fix redirects `litScenesApplicationSupportDirectory()` itself under test.
// These tests pin that redirect, because the leak is invisible from inside a
// passing suite — every one of those 543 green tests was writing to real data.

@Test func testRunsAreDetectedAsTestRuns() {
    // Everything below rests on this being true in a test process. If the
    // detection ever breaks, the suite silently starts writing to real data
    // again — so this is the assertion that must fail loudest.
    #expect(litScenesIsRunningTests)
}

@Test func applicationSupportDirectoryIsSandboxedDuringTests() {
    let root = litScenesApplicationSupportDirectory()
    let real = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/LitScenes")

    #expect(root.standardizedFileURL != real.standardizedFileURL)
    #expect(!root.path.hasPrefix(real.path))
    // Belt and braces: the sandbox must be under the temp directory.
    #expect(root.path.contains(FileManager.default.temporaryDirectory.lastPathComponent)
            || root.path.hasPrefix("/private/var")
            || root.path.hasPrefix("/var"))
}

@Test func defaultProjectLibraryDoesNotPointAtTheRealProjectsFolder() {
    // This is the exact construction the leaking stores use.
    let library = ProjectLibrary()
    let realProjects = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/LitScenes/projects")

    #expect(!library.root.path.hasPrefix(realProjects.path))
}

@Test func creatingAProjectThroughTheDefaultLibraryStaysInTheSandbox() throws {
    // The end-to-end shape of the leak: create a project the way
    // SoundSceneTimelineStore's hardcoded library would, and prove both the
    // directory and the registry row land outside the user's data.
    let library = ProjectLibrary()
    let project = try library.createProject(named: "Isolation Guard \(UUID().uuidString.prefix(6))")
    let directory = library.projectDirectory(for: project)
    let realProjects = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/LitScenes/projects")

    #expect(FileManager.default.fileExists(atPath: directory.path))
    #expect(!directory.path.hasPrefix(realProjects.path))

    // The registry the row went into must be the sandboxed one too.
    let registry = litScenesApplicationSupportDirectory()
        .appendingPathComponent("LitScenesRegistry.db")
    #expect(!registry.path.hasPrefix(realProjects.deletingLastPathComponent().path))
}
