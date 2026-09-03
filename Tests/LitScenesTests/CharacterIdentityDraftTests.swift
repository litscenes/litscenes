import Foundation
import Testing
@testable import LitScenes

private func draftContext(
    name: String = "Auri",
    blanks: Set<CharacterIdentityBlank> = [.appearance, .storyIdentity, .props],
    keepLines: [String] = [],
    sourceCount: Int = 0,
    others: [String] = ["- Senn — a broad-shouldered ferryman | identity: wants quiet"]
) -> CharacterIdentityDraftContext {
    CharacterIdentityDraftContext(
        projectId: "p1",
        projectName: "Project",
        characterName: name,
        blanks: blanks,
        keepLines: keepLines,
        goalSummary: "- goal: a river town after the flood",
        requiredEntityLines: ["- \(name) (healer) [required]"],
        castLines: ["- Senn (ferryman) — keeps the crossing open"],
        otherCharacterLines: others,
        moodboardLines: "- caption=a flooded market mood=quiet",
        sourceImageLines: sourceCount > 0 ? "- media_id=m1 file=a.jpg kind=image size=10x10" : "",
        sourceCount: sourceCount
    )
}

@Suite("Character identity draft")
struct CharacterIdentityDraftTests {
    @Test("The gate drafts only for a blank appearance or story identity, once")
    func gateMatrix() {
        typealias D = CharacterIdentityDraft
        #expect(D.decision(hasAppearance: false, hasCastIdentity: false, hasSignatureProps: false, sourceCount: 1, unlabeledSourceCount: 1, lastDraftFailed: false)
            == .draft(blanks: [.appearance, .storyIdentity, .props, .sourceLabels]))
        #expect(D.decision(hasAppearance: false, hasCastIdentity: true, hasSignatureProps: true, sourceCount: 0, unlabeledSourceCount: 0, lastDraftFailed: false)
            == .draft(blanks: [.appearance]))
        #expect(D.decision(hasAppearance: true, hasCastIdentity: false, hasSignatureProps: true, sourceCount: 2, unlabeledSourceCount: 0, lastDraftFailed: false)
            == .draft(blanks: [.storyIdentity]))
        #expect(D.decision(hasAppearance: true, hasCastIdentity: true, hasSignatureProps: false, sourceCount: 2, unlabeledSourceCount: 2, lastDraftFailed: false) == .skip)
        #expect(D.decision(hasAppearance: false, hasCastIdentity: false, hasSignatureProps: false, sourceCount: 0, unlabeledSourceCount: 0, lastDraftFailed: true) == .skip)
    }

    @Test("Blanks map to cast dimensions and the merge fills only those, honoring pins")
    func allowedDimensionsAndMerge() {
        #expect(CharacterIdentityDraft.allowedDimensions(for: [.appearance]) == [.visualDescription])
        #expect(CharacterIdentityDraft.allowedDimensions(for: [.props, .sourceLabels]).isEmpty)
        #expect(CharacterIdentityDraft.allowedDimensions(for: [.storyIdentity]).count == 8)

        var prior = GoalCastIdentity()
        prior.essence = "a healer who fears touch"
        prior.visualDescription = ""
        var emitted = GoalCastIdentity()
        emitted.essence = "someone else entirely"
        emitted.publicFunction = "wandering healer"
        emitted.visualDescription = "tall, ash-brown skin, velvet antlers"
        emitted.strangeness = 0.8

        let appearanceOnly = CharacterIdentityDraft.mergedIdentity(prior: prior, emitted: emitted, blanks: [.appearance], pinned: [])
        #expect(appearanceOnly.visualDescription == "tall, ash-brown skin, velvet antlers")
        #expect(appearanceOnly.essence == "a healer who fears touch")
        #expect(appearanceOnly.publicFunction == "")

        let storyWithPin = CharacterIdentityDraft.mergedIdentity(prior: prior, emitted: emitted, blanks: [.storyIdentity], pinned: [.essence])
        #expect(storyWithPin.essence == "a healer who fears touch")
        #expect(storyWithPin.publicFunction == "wandering healer")
        #expect(storyWithPin.strangeness == 0.8)
        #expect(storyWithPin.visualDescription == "")
    }

    @Test("The prompt pins the name, lists blanks and keeps, and switches its image rule")
    func promptBuilder() {
        let withImages = OpenAIClient.characterIdentityDraftPrompt(context: draftContext(blanks: [.appearance, .sourceLabels], keepLines: ["signature props: a brass bell"], sourceCount: 2))
        #expect(withImages.contains("named exactly \"Auri\""))
        #expect(withImages.contains("Fill ONLY these parts: appearance (identity.visual_description); source_image_notes."))
        #expect(withImages.contains("  - signature props: a brass bell"))
        #expect(withImages.contains("The attached images ARE this person."))
        #expect(withImages.contains("DISTINCT from every other listed character"))
        #expect(withImages.contains("- Senn — a broad-shouldered ferryman"))
        #expect(withImages.contains("media_id=m1"))
        #expect(withImages.contains("THE FORMULA IS A GAP-FILLER"))

        let textOnly = OpenAIClient.characterIdentityDraftPrompt(context: draftContext())
        #expect(textOnly.contains("No images are attached"))
        #expect(textOnly.contains("- Nothing else is written yet."))
        #expect(textOnly.contains("source_image_notes: []."))
        #expect(!textOnly.contains("The attached images ARE this person."))
    }

    @Test("Counter-fixture: another project's names produce the same shape with no leakage")
    func counterFixture() {
        let prompt = OpenAIClient.characterIdentityDraftPrompt(context: draftContext(
            name: "Bartholomew Quince",
            others: ["- Ottoline Marsh — a seawall engineer in oilskins"]
        ))
        #expect(prompt.contains("named exactly \"Bartholomew Quince\""))
        #expect(prompt.contains("Ottoline Marsh"))
        #expect(!prompt.contains("Auri"))
    }

    @Test("The draft response decodes tolerantly")
    func responseDecodes() throws {
        let json = #"{"schema_version":"litscenes.character_identity_draft.v0.1","identity":{"essence":"a healer","visual_description":"tall and grave"}}"#
        let response = try CharacterIdentityDraftResponse.decode(from: Data(json.utf8))
        #expect(response.identity.essence == "a healer")
        #expect(response.identity.visualDescription == "tall and grave")
        #expect(response.signatureProps.isEmpty)
        #expect(response.sourceImageNotes.isEmpty)
        let full = #"{"schema_version":"x","identity":{"essence":"e","public_function":"f","desire":"d","operating_rule":"r","cost":"c","signature":"s","formative_pressure":"","strangeness":0.4,"visual_description":"v"},"signature_props":["a bell"],"environment_affinity":"the pier","source_image_notes":[{"media_id":"m1","label":"face, three-quarter"}],"casting_note":"Drew from the flood."}"#
        let decoded = try CharacterIdentityDraftResponse.decode(from: Data(full.utf8))
        #expect(decoded.signatureProps == ["a bell"])
        #expect(decoded.environmentAffinity == "the pier")
        #expect(decoded.sourceImageNotes.first?.label == "face, three-quarter")
        #expect(decoded.castingNote == "Drew from the flood.")
    }

    @Test("Drafting is its own casting stage with honest copy")
    func draftingStageCopy() {
        var inputs = CharacterCastingInputs(name: "Auri", hasAppearance: false, stackLabel: "OpenAI Base")
        inputs.isDrafting = true
        inputs.isRenderingSheet = true
        inputs.sourceCount = 1
        #expect(characterCastingStage(inputs) == .drafting(sourceCount: 1))
        let copy = characterCastingCopy(inputs)
        #expect(copy.mastheadStatus == "CASTING…")
        #expect(copy.cardHeadline == "Casting Auri from the story…")
        #expect(copy.cardSentence == "From the Goal, the other characters, and 1 source image.")
        #expect(copy.disabledReason == "Drafting now.")

        var pending = CharacterCastingInputs(name: "Auri", hasAppearance: false, stackLabel: "OpenAI Base")
        pending.draftsFirst = true
        #expect(characterCastingCopy(pending).consequence == "From text alone · OpenAI Base · unpriced · drafts the identity first")

        var failed = CharacterCastingInputs(name: "Auri", hasAppearance: false, stackLabel: "OpenAI Base")
        failed.lastFailure = "Identity draft failed: the model timed out"
        failed.lastFailureIsDraft = true
        let failedCopy = characterCastingCopy(failed)
        #expect(failedCopy.note == "Identity draft failed: the model timed out. RENDER SHEET renders from what is written.")
        #expect(failedCopy.cardFailure == "Identity draft failed: the model timed out.")
        #expect(failedCopy.barTitle == "RENDER SHEET")
    }
}
