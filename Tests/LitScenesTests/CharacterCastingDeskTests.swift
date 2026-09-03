import Foundation
import Testing
@testable import LitScenes

private func mediaItem(_ id: String, kind: String? = nil, path: String? = nil) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: id, sourceId: "src", kind: .image, filename: "\(id).png", path: path ?? "/tmp/\(id).png",
        relativePath: "\(id).png", byteCount: 1, modifiedAt: "", width: 10, height: 10,
        thumbnailPath: "", scannedAt: "", derivativeKind: kind, sourceMediaId: nil
    )
}

@Suite("Casting desk model laws")
struct CharacterCastingDeskModelTests {
    @Test("Legacy character rows decode without the prompt override, stack, or per-sheet hashes")
    func legacyRowsDecodeWithoutTheNewFields() throws {
        let json = #"{"character_id":"c1","name":"Auri","description_prompt":"silver hair","updated_at":"2026-01-01T00:00:00Z"}"#
        let character = try JSONCoding.decoder.decode(ProjectCharacter.self, from: Data(json.utf8))
        #expect(character.sheetPromptOverride == nil)
        #expect(character.sheetPromptOverrideBaseHash == "")
        #expect(character.sheetStackId == nil)
        #expect(character.sheetPromptHashes.isEmpty)
        #expect(!character.hasSheetPromptOverride)
    }

    @Test("The override, stack, and per-sheet hashes normalize and round-trip")
    func promptOverrideStackAndHashesRoundTrip() throws {
        var character = ProjectCharacter(characterId: "c1", name: "Auri", updatedAt: "2026-01-01T00:00:00Z")
        character.sheetPromptOverride = "  Render Auri as a tall figure.  "
        character.sheetPromptOverrideBaseHash = " base "
        character.sheetStackId = " openai_base "
        character.sheetPromptHashes = [" m1 ": " h1 ", "": "x", "m2": "  "]
        let normalized = character.normalized()
        #expect(normalized.sheetPromptOverride == "Render Auri as a tall figure.")
        #expect(normalized.sheetPromptOverrideBaseHash == "base")
        #expect(normalized.sheetStackId == "openai_base")
        #expect(normalized.sheetPromptHashes == ["m1": "h1"])

        let encoded = try JSONCoding.encoder.encode(normalized)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains("\"sheet_prompt_override\""))
        #expect(text.contains("\"sheet_stack_id\""))
        #expect(text.contains("\"sheet_prompt_hashes\""))
        let decoded = try JSONCoding.decoder.decode(ProjectCharacter.self, from: encoded)
        #expect(decoded == normalized)

        var blank = normalized
        blank.sheetPromptOverride = "   "
        let cleared = blank.normalized()
        #expect(cleared.sheetPromptOverride == nil)
        #expect(cleared.sheetPromptOverrideBaseHash == "")

        let overflow = ProjectCharacter(
            characterId: "c2", name: "K",
            sheetPromptOverride: String(repeating: "x", count: ProjectCharacter.sheetPromptOverrideMaxLength + 50),
            updatedAt: "2026-01-01T00:00:00Z"
        ).normalized()
        #expect(overflow.sheetPromptOverride?.count == ProjectCharacter.sheetPromptOverrideMaxLength)
    }

    @Test("Activating a sheet restores the hash that sheet rendered with")
    func activatingASheetRestoresItsOwnHash() {
        var character = ProjectCharacter(characterId: "c1", name: "Auri", updatedAt: "2026-01-01T00:00:00Z")
        character.recordRenderedSheet(mediaId: "v1", promptHash: "h1")
        character.recordRenderedSheet(mediaId: "v2", promptHash: "h2")
        #expect(character.activeSheetMediaId == "v2")
        #expect(character.activeSheetPromptHash == "h2")
        character.activateSheet(mediaId: "v1")
        #expect(character.activeSheetMediaId == "v1")
        #expect(character.activeSheetPromptHash == "h1")
        character.activateSheet(mediaId: "unknown")
        #expect(character.activeSheetPromptHash == "")
        character.activateSheet(mediaId: "v2")
        #expect(character.activeSheetPromptHash == "h2")
    }

    @Test("Without the loose-reference fallback a character anchors on its sheet or nothing")
    func looseReferenceFallbackOffAnchorsOnTheSheetOrNothing() {
        let loose = [mediaItem("a"), mediaItem("composite", kind: MediaItemRecord.rosterCompositeSheetDerivativeKind)]
        let sheet = mediaItem("sheet", kind: MediaItemRecord.characterSheetDerivativeKind)
        let withSheet = RosterCharacterRenderPrompt.identityAnchorPicks(
            referenced: loose, referenceLabels: [:], capOne: false, activeSheet: sheet,
            looseReferenceFallback: false, fileExists: { _ in true }
        )
        #expect(withSheet.map(\.item.mediaId) == ["sheet"])
        let noSheet = RosterCharacterRenderPrompt.identityAnchorPicks(
            referenced: loose, referenceLabels: [:], capOne: false, activeSheet: nil,
            looseReferenceFallback: false, fileExists: { _ in true }
        )
        #expect(noSheet.isEmpty)
        let missingSheet = RosterCharacterRenderPrompt.identityAnchorPicks(
            referenced: loose, referenceLabels: [:], capOne: false, activeSheet: sheet,
            looseReferenceFallback: false, fileExists: { $0 != "/tmp/sheet.png" }
        )
        #expect(missingSheet.isEmpty)
        let legacy = RosterCharacterRenderPrompt.identityAnchorPicks(
            referenced: loose, referenceLabels: [:], capOne: false, fileExists: { _ in true }
        )
        #expect(legacy.map(\.item.mediaId) == ["composite"])
    }

    @Test("The prompt state prefers the hand edit, detects drift, and judges currency on the effective text")
    func promptStateEffectiveDriftAndCurrency() {
        let composed = "Composed prompt"
        let composedHash = CharacterSheetPrompt.promptHash(composed)
        let plain = CharacterSheetPromptState.resolve(
            composed: composed, override: nil, overrideBaseHash: "", activeSheetMediaId: nil, activeSheetPromptHash: ""
        )
        #expect(plain.effective == composed)
        #expect(!plain.isHandEdited)
        #expect(!plain.hasDrift)
        #expect(plain.isCurrent)

        let blank = CharacterSheetPromptState.resolve(
            composed: composed, override: "   ", overrideBaseHash: "stale", activeSheetMediaId: nil, activeSheetPromptHash: ""
        )
        #expect(blank.handEdited == nil)
        #expect(!blank.hasDrift)

        let edited = CharacterSheetPromptState.resolve(
            composed: composed, override: " Edited ", overrideBaseHash: composedHash,
            activeSheetMediaId: "sheet", activeSheetPromptHash: CharacterSheetPrompt.promptHash("Edited")
        )
        #expect(edited.effective == "Edited")
        #expect(edited.isHandEdited)
        #expect(!edited.hasDrift)
        #expect(edited.isCurrent)

        let drifted = CharacterSheetPromptState.resolve(
            composed: "Composed prompt moved on", override: "Edited", overrideBaseHash: composedHash,
            activeSheetMediaId: "sheet", activeSheetPromptHash: "other"
        )
        #expect(drifted.hasDrift)
        #expect(!drifted.isCurrent)
        #expect(drifted.effectiveHash == CharacterSheetPrompt.promptHash("Edited"))
    }

    @Test("A sheet render attaches the sheet first, then the leading sources within capacity")
    func sheetRenderPicksLeadWithTheSheetThenSourcesWithinCapacity() {
        let sheet = mediaItem("sheet", kind: MediaItemRecord.characterSheetDerivativeKind)
        let sources = [
            mediaItem("a"), mediaItem("b"),
            mediaItem("composite", kind: MediaItemRecord.rosterCompositeSheetDerivativeKind),
            mediaItem("c"), mediaItem("sheet", kind: MediaItemRecord.characterSheetDerivativeKind),
        ]
        let six = RosterCharacterRenderPrompt.sheetRenderPicks(
            activeSheet: sheet, sources: sources, referenceLabels: ["a": "young"], capacity: 6, fileExists: { _ in true }
        )
        #expect(six.map(\.item.mediaId) == ["sheet", "a", "b", "c"])
        #expect(six.map(\.role) == [.activeSheet, .sourceImage, .sourceImage, .sourceImage])
        #expect(six[0].label == "character sheet")
        #expect(six[1].label == "young")
        #expect(six[0].isSheet && !six[1].isSheet)

        let one = RosterCharacterRenderPrompt.sheetRenderPicks(
            activeSheet: sheet, sources: sources, referenceLabels: [:], capacity: 1, fileExists: { _ in true }
        )
        #expect(one.map(\.item.mediaId) == ["sheet"])
        let oneNoSheet = RosterCharacterRenderPrompt.sheetRenderPicks(
            activeSheet: nil, sources: sources, referenceLabels: [:], capacity: 1, fileExists: { _ in true }
        )
        #expect(oneNoSheet.map(\.item.mediaId) == ["a"])
        let none = RosterCharacterRenderPrompt.sheetRenderPicks(
            activeSheet: sheet, sources: sources, referenceLabels: [:], capacity: 0, fileExists: { _ in true }
        )
        #expect(none.isEmpty)
        let missingSheet = RosterCharacterRenderPrompt.sheetRenderPicks(
            activeSheet: sheet, sources: sources, referenceLabels: [:], capacity: 2, fileExists: { $0 != "/tmp/sheet.png" }
        )
        #expect(missingSheet.map(\.item.mediaId) == ["a", "b"])
    }

    @Test("The sheet-lane source descriptor names the input role, not a scene subject")
    func characterSheetSourceDescriptorNamesTheInputRole() {
        let alone = RosterMentionResolver.characterSheetSourceDescriptor(name: "Milo Blink", label: "young Milo", hasSheet: false)
        #expect(alone.contains("SOURCE IMAGE for \"Milo Blink\""))
        #expect(alone.contains("an input the sheet is built from"))
        #expect(alone.hasSuffix("This particular reference shows: young Milo."))
        #expect(!alone.contains("Reconcile"))
        #expect(!alone.contains("treatment's style"))
        let withSheet = RosterMentionResolver.characterSheetSourceDescriptor(name: "Milo Blink", label: "", hasSheet: true)
        #expect(withSheet.contains("the sheet sets continuity"))
        #expect(!withSheet.contains("This particular reference shows"))
    }

    @Test("The study plan composes shot, look, and attachments within the stack's capacity")
    func characterStudyPlanComposesShotLookAndAttachments() {
        let text = CharacterStudyPrompt.compose(
            name: "Milo Blink", description: "compact gecko", signatureProps: ["a token belt"],
            shot: .portrait, look: .asDescribed, referenceCount: 0
        )
        #expect(text.hasPrefix("Create one square character portrait study."))
        #expect(text.contains("The subject: \"Milo Blink\" — compact gecko"))
        #expect(!text.contains("attached reference"))
        let variant = CharacterStudyPrompt.compose(
            name: "Milo Blink", description: "compact gecko", signatureProps: [],
            shot: .threeQuarter, look: .asPhotographed, referenceCount: 2
        )
        #expect(variant.contains("head to mid-thigh"))
        #expect(variant.hasSuffix("Match the attached reference images exactly — the same person with the same look, hair, and clothing — in the new framing."))
        let described = CharacterStudyPrompt.compose(
            name: "Milo", description: "", signatureProps: [], shot: .fullFigure, look: .asDescribed, referenceCount: 1
        )
        #expect(described.hasSuffix("Use the attached reference image for the face and identity — this is the same person; apply the described appearance faithfully wherever it differs from the reference."))

        let sheet = CharacterStudyReference(item: mediaItem("sheet", kind: MediaItemRecord.characterSheetDerivativeKind), isSheet: true)
        let source = CharacterStudyReference(item: mediaItem("a"), label: "young Milo")
        let plan = CharacterStudyPrompt.plan(
            name: "Milo", references: [source, sheet], look: .asDescribed, capacity: 6, isStability: false, fileExists: { _ in true }
        )
        #expect(plan.attachments.map(\.mediaId) == ["sheet", "a"])
        #expect(plan.attachments[0].isSheet)
        #expect(plan.attachments[0].detail.contains("generated reference sheet"))
        #expect(plan.attachments[1].detail.contains("apply the written appearance where it differs"))
        #expect(plan.attachments[1].detail.hasSuffix("This particular reference shows: young Milo."))
        #expect(!plan.usesComposite)
        #expect(plan.droppedReferenceCount == 0)

        let photographed = CharacterStudyPrompt.plan(
            name: "Milo", references: [source], look: .asPhotographed, capacity: 1, isStability: false, fileExists: { _ in true }
        )
        #expect(photographed.attachments.first?.detail.contains("as photographed") == true)

        let stability = CharacterStudyPrompt.plan(
            name: "Milo", references: [source, sheet], look: .asDescribed, capacity: 6, isStability: true, fileExists: { _ in true }
        )
        #expect(stability.usesComposite)

        let textOnly = CharacterStudyPrompt.plan(
            name: "Milo", references: [source, sheet], look: .asDescribed, capacity: 0, isStability: false, fileExists: { _ in true }
        )
        #expect(textOnly.attachments.isEmpty)
        #expect(textOnly.droppedReferenceCount == 2)

        let capped = CharacterStudyPrompt.plan(
            name: "Milo", references: [source, CharacterStudyReference(item: mediaItem("b")), sheet], look: .asDescribed,
            capacity: 2, isStability: false, fileExists: { _ in true }
        )
        #expect(capped.attachments.map(\.mediaId) == ["sheet", "a"])
        #expect(capped.droppedReferenceCount == 1)
    }
}

@Suite("Character chat auto-render law")
struct CharacterChatAutoRenderTests {
    @Test("The decision matrix, in order")
    func decisionMatrix() {
        typealias D = CharacterChatAutoRender
        #expect(D.decision(name: "Auri", changed: false, rendersAfterChat: true, hasOverride: false, hasStack: true, stackBlocker: nil, isBusy: false)
            == .skip(status: "Nothing about Auri changed"))
        #expect(D.decision(name: "Auri", changed: true, rendersAfterChat: true, hasOverride: true, hasStack: true, stackBlocker: nil, isBusy: false)
            == .skip(status: "Auri's identity updated — the hand-edited prompt still renders; reset or edit it to include this change"))
        #expect(D.decision(name: "Auri", changed: true, rendersAfterChat: false, hasOverride: false, hasStack: true, stackBlocker: nil, isBusy: false)
            == .skip(status: "Sheet prompt updated — render to see it"))
        #expect(D.decision(name: "Auri", changed: true, rendersAfterChat: true, hasOverride: false, hasStack: false, stackBlocker: nil, isBusy: false)
            == .skip(status: "Sheet prompt updated — render to see it"))
        #expect(D.decision(name: "Auri", changed: true, rendersAfterChat: true, hasOverride: false, hasStack: true, stackBlocker: "Add a FAL key in App Settings.", isBusy: false)
            == .skip(status: "Sheet prompt updated — Add a FAL key in App Settings."))
        #expect(D.decision(name: "Auri", changed: true, rendersAfterChat: true, hasOverride: false, hasStack: true, stackBlocker: nil, isBusy: true)
            == .skip(status: "Sheet prompt updated — a render is already running; render again when it finishes"))
        #expect(D.decision(name: "Auri", changed: true, rendersAfterChat: true, hasOverride: false, hasStack: true, stackBlocker: nil, isBusy: false)
            == .render(status: "Sheet prompt updated — rendering Auri's sheet"))
        #expect(D.decision(name: "Auri", changed: true, rendersAfterChat: false, hasOverride: true, hasStack: false, stackBlocker: "x", isBusy: true).status
            .contains("hand-edited prompt"))
    }
}

@Suite("Character casting state and copy")
struct CharacterCastingStateTests {
    private func inputs(_ mutate: (inout CharacterCastingInputs) -> Void = { _ in }) -> CharacterCastingInputs {
        var value = CharacterCastingInputs(name: "Auri", hasAppearance: true, hasStoryIdentity: true, stackLabel: "OpenAI Base")
        mutate(&value)
        return value
    }

    @Test("Stage precedence: rendering beats failure beats cast beats uncast")
    func stagePrecedence() {
        #expect(characterCastingStage(inputs { $0.isRenderingSheet = true; $0.lastFailure = "x"; $0.activeOrdinal = 2 }) == .rendering(stackLabel: "OpenAI Base"))
        #expect(characterCastingStage(inputs { $0.lastFailure = "boom"; $0.activeOrdinal = 2 }) == .failed(reason: "boom", ordinal: 2))
        #expect(characterCastingStage(inputs { $0.activeOrdinal = 2; $0.promptIsCurrent = false }) == .cast(ordinal: 2, promptIsCurrent: false))
        #expect(characterCastingStage(inputs { $0.sourceCount = 1 }) == .uncast(sourceCount: 1, hasAppearance: true))
    }

    @Test("Uncast copy drives toward the studio and states what renders")
    func uncastCopy() {
        let bare = characterCastingCopy(inputs { $0.hasAppearance = false })
        #expect(bare.mastheadStatus == "NOT YET CAST")
        #expect(bare.mastheadTone == .muted)
        #expect(bare.cardHeadline == "Render Auri's reference sheet")
        #expect(bare.cardSentence == "Renders from the description below, then anchors Auri in every scene.")
        #expect(bare.note == "No appearance yet. The sheet will invent Auri from the name and story alone.")
        #expect(bare.noteTone == .softGold)
        #expect(bare.consequence == "From text alone · OpenAI Base · unpriced")
        #expect(bare.barTitle == "RENDER SHEET" && !bare.barIsGhost && bare.disabledReason.isEmpty)

        let one = characterCastingCopy(inputs { $0.sourceCount = 1; $0.attachedSourceCount = 1 })
        #expect(one.cardSentence == "Renders from your 1 source image and the description below, then anchors Auri in every scene.")
        #expect(one.consequence == "From 1 source image · OpenAI Base · unpriced")
        #expect(one.note.isEmpty)

        let three = characterCastingCopy(inputs { $0.sourceCount = 3; $0.attachedSourceCount = 2 })
        #expect(three.cardSentence.contains("your 3 source images"))
        #expect(three.consequence == "From 2 source images · OpenAI Base · unpriced")
    }

    @Test("A text-only stack with sources says so in rust")
    func textOnlyStack() {
        let copy = characterCastingCopy(inputs { $0.stackLabel = "WAN 2.7"; $0.stackIsTextOnly = true; $0.sourceCount = 2 })
        #expect(copy.cardSentence == "Renders from the description below. WAN 2.7 uses text only, not your source images.")
        #expect(copy.note == "WAN 2.7 renders from text only. Your 2 source images will not be used.")
        #expect(copy.noteTone == .rust)
        #expect(copy.consequence == "From the description · WAN 2.7 · unpriced")
    }

    @Test("Cast copy: current is a ghost new version, stale renders again")
    func castCopy() {
        let current = characterCastingCopy(inputs { $0.activeOrdinal = 2; $0.attachesSheet = true; $0.attachedSourceCount = 2 })
        #expect(current.mastheadStatus == "CAST · SHEET II")
        #expect(current.mastheadTone == .brass)
        #expect(current.barTitle == "NEW VERSION" && current.barIsGhost)
        #expect(current.note == "Sheet II is current." && current.noteTone == .muted)
        #expect(current.consequence == "From sheet II and 2 source images · OpenAI Base · unpriced")

        let stale = characterCastingCopy(inputs { $0.activeOrdinal = 2; $0.promptIsCurrent = false; $0.attachesSheet = true; $0.promptIsHandEdited = true })
        #expect(stale.barTitle == "RENDER AGAIN" && !stale.barIsGhost)
        #expect(stale.note == "Prompt changed since sheet II." && stale.noteTone == .softGold)
        #expect(stale.consequence == "From sheet II · OpenAI Base · unpriced · edited prompt")
    }

    @Test("Failures land in words beside the action")
    func failureCopy() {
        let noSheet = characterCastingCopy(inputs { $0.lastFailure = "OpenAI refused the request." })
        #expect(noSheet.barTitle == "RENDER SHEET")
        #expect(noSheet.note == "Last render failed: OpenAI refused the request.")
        #expect(noSheet.noteTone == .rust)
        #expect(noSheet.cardFailure == "The last render failed: OpenAI refused the request.")
        #expect(noSheet.mastheadStatus == "NOT YET CAST")
        let withSheet = characterCastingCopy(inputs { $0.lastFailure = "timeout"; $0.activeOrdinal = 1 })
        #expect(withSheet.barTitle == "RENDER AGAIN")
        #expect(withSheet.note == "Last render failed: timeout. Sheet I still anchors Auri.")
        #expect(withSheet.mastheadStatus == "CAST · SHEET I")
    }

    @Test("Rendering and blocked reasons disable the pill with the reason printed")
    func renderingAndBlockedCopy() {
        let rendering = characterCastingCopy(inputs { $0.isRenderingSheet = true })
        #expect(rendering.mastheadStatus == "RENDERING" && rendering.mastheadTone == .softGold)
        #expect(rendering.cardHeadline == "Rendering Auri's sheet…")
        #expect(rendering.note == "Rendering on OpenAI Base…")
        #expect(rendering.disabledReason == "Rendering now.")

        let credential = characterCastingCopy(inputs { $0.blocker = .credential("Add a FAL key in App Settings.") })
        #expect(credential.note == "Add a FAL key in App Settings." && credential.noteTone == .rust)
        #expect(credential.disabledReason == "Add a FAL key in App Settings.")
        let noStack = characterCastingCopy(inputs { $0.stackLabel = ""; $0.blocker = .noStack })
        #expect(noStack.consequence == "From the description · No render stack · unpriced")
        #expect(!noStack.consequence.contains("$0"))
        let paused = characterCastingCopy(inputs { $0.blocker = .paused })
        #expect(paused.noteTone == .softGold && !paused.disabledReason.isEmpty)
        let busy = characterCastingCopy(inputs { $0.blocker = .busy })
        #expect(busy.note == "Another character's render is running.")
    }

    @Test("The next step wraps to the next uncast character, then SCENES")
    func nextStep() {
        let roster: [(id: String, name: String, isCast: Bool)] = [("a", "Auri", true), ("b", "Senn", true), ("c", "Veyr", false)]
        #expect(characterNextStep(characters: roster, selectedId: "b") == .nextUncast(characterId: "c", name: "Veyr"))
        #expect(characterNextStep(characters: roster, selectedId: "c") == nil)
        let wrapped: [(id: String, name: String, isCast: Bool)] = [("a", "Auri", false), ("b", "Senn", true)]
        #expect(characterNextStep(characters: wrapped, selectedId: "b") == .nextUncast(characterId: "a", name: "Auri"))
        let allCast: [(id: String, name: String, isCast: Bool)] = [("a", "Auri", true), ("b", "Senn", true)]
        #expect(characterNextStep(characters: allCast, selectedId: "a") == .continueToScenes)
        #expect(characterNextStep(characters: [("a", "Auri", true)], selectedId: "a") == .continueToScenes)
        #expect(characterNextStep(characters: [], selectedId: "a") == nil)
    }

    @Test("Plate height and labels")
    func plateHeightAndLabels() {
        #expect(sheetPlateHeight(workspaceHeight: 500) == 360)
        #expect(sheetPlateHeight(workspaceHeight: 900) == 480)
        #expect(sheetPlateHeight(workspaceHeight: 1500) == 680)
        #expect(characterSheetOrdinalLabel(2) == "II")
        #expect(characterSheetOrdinalLabel(11) == "11")
        #expect(characterCountLabel(2140) == "2,140 CHARACTERS")
        #expect(characterCountLabel(1) == "1 CHARACTER")
        #expect(characterSourcesLabel(0) == "NO SOURCES")
        #expect(characterSourcesLabel(1) == "1 SOURCE")
        #expect(characterSourcesLabel(4) == "4 SOURCES")
        #expect(characterPromptDriftNote(hasDrift: false) == nil)
        #expect(characterPromptDriftNote(hasDrift: true) == "Identity changed after your edit. The edited prompt still renders.")
        #expect(characterStackMenuLabel(label: "WAN 2.7", isTextOnly: true, blocked: true) == "WAN 2.7 · text only · needs key")
    }

    @Test("Counter-fixture: another project's names produce the same shapes")
    func counterFixture() {
        let copy = characterCastingCopy(CharacterCastingInputs(name: "Bartholomew Quince", sourceCount: 2, hasAppearance: true, stackLabel: "Stability Ultra", attachedSourceCount: 2))
        #expect(copy.cardHeadline == "Render Bartholomew Quince's reference sheet")
        #expect(copy.consequence == "From 2 source images · Stability Ultra · unpriced")
    }
}
