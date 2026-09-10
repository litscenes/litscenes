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
        for section in ["1. SUBJECT PROFILE", "2. FORM AND VIEWS", "3. IDENTITY DETAILS", "4. STATES", "5. MOVEMENT AND CONFIGURATION", "6. DEFINING ELEMENTS", "7. COLOR AND MATERIAL PALETTE", "8. CONTINUITY"] {
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

    @Test("Counter-fixtures preserve explicit appearance changes and remain independent of names")
    func continuityCounterFixtures() throws {
        let cases = [
            ("Polar Navigator", "A navigator with a blunt chin-length haircut", "Change the haircut to a cropped undercut across every view."),
            ("Porcelain Courier", "A faceted ceramic automaton without hair", "Keep the ceramic head hairless; change only the left shoulder marking.")
        ]
        for (name, appearance, directive) in cases {
            func render(_ subject: String) -> String {
                CharacterSheetPrompt.render(
                    template: ProjectPromptSettingsDocument.builtInCharacterSheetBody,
                    fill: CharacterSheetPrompt.Fill(name: subject, visualDescription: appearance, sheetDirectives: [directive], attachesReferences: true)
                )
            }
            let prompt = render(name)
            #expect(prompt.replacingOccurrences(of: name, with: "Another character") == render("Another character"))
            #expect(prompt.components(separatedBy: directive).count == 2)
            #expect(String(prompt.prefix(1400)).contains(directive))
            #expect(String(prompt.prefix(1400)).contains("hair length, cut, silhouette, and texture"))
            #expect(prompt.contains("When a hair change is explicitly requested"))
            #expect(prompt.contains(appearance))
            #expect(prompt.count < 3500)
            let context = CharacterSheetRefineContext(
                projectId: "counter-project", projectName: "Different project", characterName: name,
                visualDescription: appearance, signatureProps: [], storyIdentityLines: "",
                currentDirectives: [directive], renderedSheetPrompt: prompt, sourceImageLines: "",
                hasActiveSheet: true, recentTurnsSummary: "", userMessage: "Change the jacket fastening only.", generatedAt: ""
            )
            let refinement = OpenAIClient.characterSheetRefinePrompt(context: context)
            #expect(refinement.contains("unless the user explicitly changes them"))
            #expect(refinement.contains("Do not promise that a future image will satisfy them"))
            #expect(refinement.contains(directive))
        }
        let retired = CharacterSheetPromptTemplate(body: ProjectPromptSettingsDocument.legacyCharacterSheetBody)
        #expect(ProjectPromptSettingsDocument.normalizedCharacterSheetPrompts([retired]).first?.body == ProjectPromptSettingsDocument.builtInCharacterSheetBody)
        let custom = CharacterSheetPromptTemplate(body: "A custom layout {{character_name}}")
        #expect(ProjectPromptSettingsDocument.normalizedCharacterSheetPrompts([custom]).first?.body == custom.body)

        // Reference and prompt lifecycle exercise a different character from the report.
        var draft = CharacterStudioDraft()
        draft.reconcileReferences(sourceIds: ["front", "back"], availableIds: ["front", "back"])
        draft.recompose(name: "Porcelain Courier", description: "A ceramic figure", signatureProps: [])
        draft.reconcileReferences(sourceIds: ["detail", "back", "front"], availableIds: ["detail", "back", "front"])
        #expect(draft.referenceIds == ["detail", "back", "front"])
        draft.followsCurrentSources = false
        draft.referenceIds = ["front"]
        draft.reconcileReferences(sourceIds: ["detail", "back", "front"], availableIds: ["detail", "back", "front"])
        #expect(draft.referenceIds == ["front"])
        draft.prompt = "Keep my independently written framing."
        draft.recompose(name: "Porcelain Courier", description: "A revised ceramic figure", signatureProps: [])
        #expect(draft.prompt == "Keep my independently written framing.")
        #expect(draft.sourcePromptChanged)
        draft.recompose(name: "Porcelain Courier", description: "A revised ceramic figure", signatureProps: [], force: true)
        #expect(!draft.sourcePromptChanged && !draft.isEdited)
        #expect(draft.prompt.contains("revised ceramic figure"))
        let withoutReferences = CharacterChatAutoRender.decision(
            name: "Porcelain Courier", changed: true, rendersAfterChat: true, hasOverride: false,
            hasStack: true, stackBlocker: nil, isBusy: false, hasReferences: false
        )
        guard case .skip(let status) = withoutReferences else { Issue.record("An image is required before the sheet can render"); return }
        #expect(status.contains("add or create a source image"))
    }

}
