import Foundation
import Testing
@testable import LitScenes

@Suite("Character sheet prompt laws")
struct CharacterSheetPromptTests {
    @Test("Every placeholder is substituted and empty values drop their line")
    func renderSubstitutesEverything() {
        let full = CharacterSheetPrompt.render(
            template: ProjectPromptSettingsDocument.builtInCharacterSheetBody,
            fill: CharacterSheetPrompt.Fill(
                name: "Auri of the Soft Ears",
                visualDescription: "Silver hair, large pale ears",
                signatureProps: ["black ribbon bows"],
                storyIdentity: CharacterSheetPrompt.StoryIdentityLines(essence: "Tender omen", desire: "to be loved as a person"),
                sheetDirectives: ["longer hair", "a brass earring"],
                attachesReferences: true
            )
        )
        #expect(!full.contains("{{"))
        #expect(full.contains("Character Reference Sheet for Auri of the Soft Ears — match the attached reference images exactly."))
        #expect(full.contains("Appearance: Silver hair, large pale ears"))
        #expect(full.contains("Always with them: black ribbon bows."))
        #expect(full.contains("Story identity — who they are: Tender omen; wants: to be loved as a person."))
        #expect(full.contains("Refinements from the character conversation — apply every one:\n- longer hair\n- a brass earring"))
        #expect(!full.contains("\n\n\n"))

        let bare = CharacterSheetPrompt.render(
            template: ProjectPromptSettingsDocument.builtInCharacterSheetBody,
            fill: CharacterSheetPrompt.Fill(name: "")
        )
        #expect(!bare.contains("{{"))
        #expect(bare.contains("Character Reference Sheet for the character. Create"))
        #expect(!bare.contains("Appearance:"))
        #expect(!bare.contains("Always with them"))
        #expect(!bare.contains("Refinements from"))
        #expect(!bare.contains("\n\n\n"))
    }

    @Test("The built-in body carries the eight sections and no aspect ratio")
    func builtInBodyShape() {
        let body = ProjectPromptSettingsDocument.builtInCharacterSheetBody
        for section in ["1. CHARACTER PROFILE", "2. FULL-BODY TURNAROUND", "3. FACE AND IDENTITY DETAILS", "4. EXPRESSION SHEET", "5. POSE AND BODY LANGUAGE", "6. COSTUME DETAILS", "7. COLOR AND MATERIAL PALETTE", "8. DO NOT CHANGE"] {
            #expect(body.contains(section), "missing \(section)")
        }
        #expect(!body.contains("4:5"))
        #expect(CharacterSheetPrompt.placeholders.allSatisfy { body.contains($0) })
    }

    @Test("Template lookup prefers the exact model, then the fallback, then the built-in")
    func templateLookup() {
        var document = ProjectPromptSettingsDocument.empty(projectId: "p1")
        document.characterSheetPrompts = [
            CharacterSheetPromptTemplate(model: "", body: "fallback body"),
            CharacterSheetPromptTemplate(model: "gpt-image-2", body: "openai body"),
        ]
        let normalized = document.normalized(projectId: "p1")
        #expect(normalized.characterSheetTemplate(model: "gpt-image-2").body == "openai body")
        #expect(normalized.characterSheetTemplate(model: "unknown-model").body == "fallback body")
        #expect(normalized.characterSheetTemplate(model: "").templateId == "character_sheet:sheet:fallback")

        let empty = ProjectPromptSettingsDocument(projectId: "p1", characterSheetPrompts: []).normalized(projectId: "p1")
        #expect(empty.characterSheetTemplate(model: "").body == ProjectPromptSettingsDocument.builtInCharacterSheetBody)
    }

    @Test("Sheet templates round-trip and legacy documents receive the built-in")
    func roundTripAndLegacy() throws {
        var document = ProjectPromptSettingsDocument.empty(projectId: "p1").normalized(projectId: "p1")
        document.characterSheetPrompts[0].body = "Operator sheet body."
        let encoded = try JSONCoding.encoder.encode(document)
        #expect(String(decoding: encoded, as: UTF8.self).contains("\"character_sheet_prompts\""))
        let decoded = try JSONCoding.decoder.decode(ProjectPromptSettingsDocument.self, from: encoded).normalized(projectId: "p1")
        #expect(decoded.characterSheetTemplate(model: "").body == "Operator sheet body.")

        let legacy = #"{"schema_version":"litscenes.project_prompt_settings.v0.1","project_id":"p1","reframe_prompts":[],"updated_at":"2026-01-01T00:00:00Z"}"#
        let legacyDocument = try JSONCoding.decoder.decode(ProjectPromptSettingsDocument.self, from: Data(legacy.utf8)).normalized(projectId: "p1")
        #expect(legacyDocument.characterSheetTemplate(model: "").body == ProjectPromptSettingsDocument.builtInCharacterSheetBody)
        #expect(!legacyDocument.reframePrompts.isEmpty)
    }

    @Test("Prompt hashes are stable and whitespace-insensitive at the edges")
    func promptHashStability() {
        let a = CharacterSheetPrompt.promptHash("Sheet prompt")
        #expect(a == CharacterSheetPrompt.promptHash("  Sheet prompt\n"))
        #expect(a != CharacterSheetPrompt.promptHash("Sheet prompt v2"))
        #expect(a.count == 16)
    }
}
