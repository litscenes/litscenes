import Foundation
import Testing
@testable import LitScenes

@Suite("Shared character smart prompt")
struct CharacterSmartPromptTests {
    @Test("Adoption preserves existing text and custom sheet overrides exactly once")
    func migration() throws {
        var character = ProjectCharacter(characterId: "subject", name: "Tide Marker", descriptionPrompt: "A floating prism.", signatureProps: ["a tether"], sheetDirectives: ["Keep the edges translucent."], sheetPromptOverride: "Custom sheet layout with six views.")
        character.adoptSmartPrompt()
        let migrated = character
        #expect(character.descriptionPrompt.contains("A floating prism."))
        #expect(character.descriptionPrompt.contains("a tether"))
        #expect(character.descriptionPrompt.contains("Keep the edges translucent."))
        #expect(character.promptHistory?.versions.count == 2)
        #expect(character.promptHistory?.activeOrdinal == 1)
        #expect(character.promptHistory?.versions.last?.source == "legacy_sheet")
        #expect(character.sheetPromptOverride == nil)
        character.adoptSmartPrompt()
        #expect(character == migrated)
        let reopened = try JSONCoding.decoder.decode(ProjectCharacter.self, from: JSONCoding.encoder.encode(character))
        #expect(reopened == character)
        let legacy = try JSONCoding.decoder.decode(ProjectCharacter.self, from: Data(#"{"character_id":"old","name":"Old","description_prompt":"Retained"}"#.utf8))
        #expect(legacy.promptHistory == nil)
        #expect(legacy.descriptionPrompt == "Retained")
    }

    @Test("Manual edits, chat, conflicting results and restore share durable history")
    func versionsAndConflict() throws {
        var character = ProjectCharacter(characterId: "subject", name: "Weather Beacon", descriptionPrompt: "A floating glass prism.")
        character.adoptSmartPrompt()
        character.reviseSmartPrompt("A floating glass prism with a metal base.", source: "manual")
        let submitted = try #require(character.promptHistory?.activeVersion)
        let applied = character.reviseSmartPrompt("A floating glass prism with a copper base.", source: "chat", baseVersionId: submitted.id, chatTurnId: "turn-one")
        #expect(applied)
        let accepted = try #require(character.promptHistory?.activeVersion)
        character.promptHistory?.mediaVersionIds["generated-image"] = accepted.id
        character.reviseSmartPrompt("A stationary glass prism with a copper base.", source: "manual")
        let manual = character.descriptionPrompt
        let proposed = character.reviseSmartPrompt("A floating glass prism with a silver base.", source: "chat", baseVersionId: accepted.id, chatTurnId: "turn-two")
        #expect(!proposed)
        #expect(character.descriptionPrompt == manual)
        #expect(character.promptHistory?.versions.last?.isProposal == true)
        #expect(character.promptVersionLabel(for: "generated-image") == "Prompt v3")
        character.restoreSmartPrompt(versionId: submitted.id)
        #expect(character.descriptionPrompt == submitted.prompt)
        #expect(character.promptHistory?.versions.count == 6)
        #expect(character.promptHistory?.activeVersion?.source == "restore")
        #expect(character.promptHistory?.mediaVersionIds["generated-image"] == accepted.id)
        let reopened = try JSONCoding.decoder.decode(ProjectCharacter.self, from: JSONCoding.encoder.encode(character))
        #expect(reopened.promptHistory == character.promptHistory)
        let count = character.promptHistory?.versions.count
        character.reviseSmartPrompt(character.descriptionPrompt, source: "manual")
        #expect(character.promptHistory?.versions.count == count)
    }

    @Test("External identity updates receive a checkpoint even after assigning the new text")
    func externalUpdate() {
        var character = ProjectCharacter(characterId: "s", name: "Sail", descriptionPrompt: "A woven sail.")
        character.adoptSmartPrompt()
        character.descriptionPrompt = "A patched woven sail."
        character.reviseSmartPrompt(character.descriptionPrompt, source: "identity")
        #expect(character.promptHistory?.versions.count == 2)
        #expect(character.promptHistory?.activeVersion?.prompt == character.descriptionPrompt)
    }

    @Test("Human and nonhuman counter-fixtures preserve creative text without name-based behavior")
    func counterFixtures() throws {
        for (name, prompt) in [
            ("Weather Beacon", "A hollow glass prism suspended by wires, with a copper base and no limbs."),
            ("Harbor Mechanic", "A human mechanic with short hair, a green work jacket, and a repaired sleeve.")
        ] {
            func compose(_ name: String) -> String {
                CharacterStudyPrompt.compose(name: name, description: prompt, signatureProps: [], shot: .fullFigure, look: .asDescribed, referenceCount: 1)
            }
            let image = compose(name)
            #expect(image.contains(prompt))
            #expect(image.replacingOccurrences(of: name, with: "Renamed") == compose("Renamed"))
            #expect(!image.contains("head to toe"))
            #expect(!image.contains("same person"))
            let sheet = CharacterSheetPrompt.render(template: ProjectPromptSettingsDocument.builtInCharacterSheetBody, fill: .init(name: name, visualDescription: prompt))
            #expect(sheet.contains(prompt))
            #expect(sheet.contains("Adapt or omit inapplicable sections"))
            let context = CharacterSheetRefineContext(projectId: "counter", projectName: "Different project", characterName: name, visualDescription: prompt, signatureProps: [], storyIdentityLines: "", currentDirectives: [], renderedSheetPrompt: sheet, sourceImageLines: "", hasActiveSheet: false, recentTurnsSummary: "", userMessage: "Change the surface texture only.", generatedAt: "", smartPromptVersionId: "revision-one")
            let chat = OpenAIClient.characterSheetRefinePrompt(context: context)
            #expect(chat.contains(prompt))
            #expect(chat.contains("FULL revised smart prompt"))
            #expect(chat.contains("including the user's manual edits"))
            #expect(chat.contains("never just a change summary"))
        }
        let previous = CharacterSheetPromptTemplate(body: ProjectPromptSettingsDocument.previousCharacterSheetBody)
        #expect(ProjectPromptSettingsDocument.normalizedCharacterSheetPrompts([previous]).first?.body == ProjectPromptSettingsDocument.builtInCharacterSheetBody)
    }

    @Test("Stale background saves preserve newer text, revision order and render links")
    func staleSnapshot() throws {
        var current = ProjectCharacter(characterId: "s", name: "Beacon", descriptionPrompt: "A glass prism.")
        current.adoptSmartPrompt()
        var submitted = current
        let submittedId = try #require(submitted.promptHistory?.activeVersionId)
        current.reviseSmartPrompt("A stone prism.", source: "manual")
        let savedIds = current.promptHistory?.versions.map(\.id)
        submitted.promptHistory?.mediaVersionIds["earlier-render"] = submittedId
        submitted.reconcileSmartPromptHistory(with: current)
        #expect(submitted.descriptionPrompt == current.descriptionPrompt)
        #expect(submitted.promptHistory?.versions.map(\.id) == savedIds)
        #expect(submitted.promptVersionLabel(for: "earlier-render") == "Prompt v1")
        #expect(submitted.promptHistory?.activeVersionId == current.promptHistory?.activeVersionId)
        let text = CharacterSheetPrompt.renderShared(template: "A custom output layout without placeholders.", fill: .init(name: "Beacon", visualDescription: current.descriptionPrompt, signatureProps: ["outdated prop"], sheetDirectives: ["outdated directive"]))
        #expect(text.hasPrefix("Subject description: A stone prism."))
        #expect(!text.contains("outdated"))
    }

    @Test("Safe prompt provenance augments canonical traces without losing wire text")
    func traceProvenance() async throws {
        let url = try #require(URL(string: "https://provider.invalid/images"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let store = InferenceTraceStore.shared
        let metadata = InferenceTraceRequestMetadata(provider: "local-fixture", apiFamily: "images", operation: "smart_prompt_fixture", projectId: "counter-project", runId: "counter-run", traceGroupId: "counter-run", workflowName: "character_study", workflowStep: "generate", artifactType: "character", artifactId: "counter-subject", model: "fixture", requestTextJSON: #"{"prompt":"Exact provider-bound text","sources":[{"sha256":"fixture-hash"}]}"#, captureRequestBody: false)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        let traceId = await store.record(request: request, metadata: metadata, response: response, responseBody: nil, latencyMs: 3)
        await store.mergeRequestContext(traceId: traceId, values: ["smart_prompt": "A glass prism.", "smart_prompt_version_id": "fixture-version"])
        await store.enrichContext(traceId: traceId, artifactType: "media", artifactId: "fixture-output")
        #expect(!traceId.isEmpty)
    }
}
