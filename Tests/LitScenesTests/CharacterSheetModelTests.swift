import Foundation
import Testing
@testable import LitScenes

@Suite("Character sheet model laws")
struct CharacterSheetModelTests {
    @Test("Legacy character rows decode without the sheet fields")
    func legacyCharacterDecodes() throws {
        let json = #"{"character_id":"c1","name":"Auri","description_prompt":"silver hair","reference_media_ids":["m1"],"reference_labels":{"m1":"face"},"signature_props":[],"environment_affinity":"","updated_at":"2026-01-01T00:00:00Z"}"#
        let character = try JSONCoding.decoder.decode(ProjectCharacter.self, from: Data(json.utf8))
        #expect(character.activeSheetMediaId == nil)
        #expect(character.sheetDirectives.isEmpty)
        #expect(character.activeSheetPromptHash == "")
        #expect(character.rendersSheetAfterChat)
    }

    @Test("Sheet fields round-trip and normalize")
    func sheetFieldsRoundTrip() throws {
        var character = ProjectCharacter(characterId: "c1", name: "Auri")
        character.activeSheetMediaId = "  genmedia_sheet  "
        character.sheetDirectives = ["longer hair", "", "longer hair", "brass earring"]
        character.activeSheetPromptHash = " abc "
        character.autoRenderSheetAfterChat = false
        let normalized = character.normalized()
        #expect(normalized.activeSheetMediaId == "genmedia_sheet")
        #expect(normalized.sheetDirectives == ["longer hair", "brass earring"])
        #expect(normalized.activeSheetPromptHash == "abc")
        #expect(normalized.rendersSheetAfterChat == false)

        let encoded = try JSONCoding.encoder.encode(normalized)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains("\"active_sheet_media_id\""))
        let decoded = try JSONCoding.decoder.decode(ProjectCharacter.self, from: encoded)
        #expect(decoded == normalized)

        let overflow = ProjectCharacter(characterId: "c2", name: "K", sheetDirectives: (0..<20).map { "directive \($0)" }).normalized()
        #expect(overflow.sheetDirectives.count == 12)
    }

    @Test("Character sheets survive rescans as generated media")
    func characterSheetIsGeneratedMedia() {
        let sheet = MediaItemRecord(
            mediaId: "genmedia_sheet",
            sourceId: "src",
            kind: .image,
            filename: "Auri Character Sheet.png",
            path: "/tmp/sheet.png",
            relativePath: "sheet.png",
            byteCount: 1,
            modifiedAt: "2026-01-01T00:00:00Z",
            width: 1024,
            height: 1536,
            thumbnailPath: "/tmp/sheet_thumb.png",
            scannedAt: "2026-01-01T00:00:00Z",
            derivativeKind: MediaItemRecord.characterSheetDerivativeKind,
            sourceMediaId: "c1"
        )
        #expect(sheet.isGeneratedMedia)
        #expect(sheet.isCharacterSheet)
        #expect(!sheet.isRosterCompositeSheet)
    }

    @Test("The active character sheet anchors identity alone")
    func activeSheetAnchorsAlone() {
        func item(_ id: String, kind: String? = nil) -> MediaItemRecord {
            MediaItemRecord(
                mediaId: id, sourceId: "src", kind: .image, filename: "\(id).png", path: "/tmp/\(id).png",
                relativePath: "\(id).png", byteCount: 1, modifiedAt: "", width: 10, height: 10,
                thumbnailPath: "", scannedAt: "", derivativeKind: kind, sourceMediaId: nil
            )
        }
        let loose = [item("a"), item("b"), item("composite", kind: MediaItemRecord.rosterCompositeSheetDerivativeKind)]
        let sheet = item("sheet", kind: MediaItemRecord.characterSheetDerivativeKind)
        let withSheet = RosterCharacterRenderPrompt.identityAnchorPicks(
            referenced: loose, referenceLabels: [:], capOne: false, activeSheet: sheet, fileExists: { _ in true }
        )
        #expect(withSheet.map(\.item.mediaId) == ["sheet"])
        #expect(withSheet.first?.label == "character sheet")
        #expect(withSheet.first?.isSheet == true)

        let missingSheet = RosterCharacterRenderPrompt.identityAnchorPicks(
            referenced: loose, referenceLabels: [:], capOne: false, activeSheet: sheet, fileExists: { $0 != "/tmp/sheet.png" }
        )
        #expect(missingSheet.map(\.item.mediaId) == ["composite"])

        let noSheet = RosterCharacterRenderPrompt.identityAnchorPicks(
            referenced: [item("a"), item("b"), item("c")], referenceLabels: [:], capOne: false, fileExists: { _ in true }
        )
        #expect(noSheet.map(\.item.mediaId) == ["a", "b"])
    }
}
