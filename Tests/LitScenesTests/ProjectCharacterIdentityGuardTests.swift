import Foundation
import Testing
@testable import LitScenes

// THE PROJECT IDENTITY LAW covers the character roster: a roster naming another
// project refuses to save; the project's own and an unstamped roster land.
@Test func crossProjectCharacterWriteRefusesAndMatchingWritesLand() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_character_guard_\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let projectLibrary = ProjectLibrary(root: root)
    let home = try projectLibrary.createProject(named: "Alpha")
    _ = try LitScenesDesktopDatabase.prepareProjectDatabase(for: home, projectLibrary: projectLibrary)
    let contextStore = ProjectContextStore(projectLibrary: projectLibrary)

    var foreign = ProjectCharacterSetDocument.empty(projectId: "project_foreign_other")
    foreign.characters = [ProjectCharacter(characterId: "c_foreign", name: "Bleed", updatedAt: "2026-01-01T00:00:00Z")]
    #expect(throws: (any Error).self) {
        try contextStore.saveProjectCharacters(foreign, for: home)
    }
    #expect(contextStore.loadProjectCharacters(for: home).characters.isEmpty)

    var own = ProjectCharacterSetDocument.empty(projectId: home.projectId)
    own.characters = [ProjectCharacter(characterId: "c_own", name: "Mine", updatedAt: "2026-01-01T00:00:00Z")]
    try contextStore.saveProjectCharacters(own, for: home)
    #expect(contextStore.loadProjectCharacters(for: home).characters.map(\.characterId) == ["c_own"])

    var unstamped = ProjectCharacterSetDocument.empty(projectId: "")
    unstamped.characters = [ProjectCharacter(characterId: "c_unstamped", name: "Quiet", updatedAt: "2026-01-01T00:00:00Z")]
    try contextStore.saveProjectCharacters(unstamped, for: home)
    let loaded = contextStore.loadProjectCharacters(for: home)
    #expect(loaded.projectId == home.projectId)
    #expect(loaded.characters.map(\.characterId) == ["c_unstamped"])
}
