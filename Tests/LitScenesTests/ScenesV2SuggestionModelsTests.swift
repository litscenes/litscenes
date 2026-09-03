import Foundation
import Testing
@testable import LitScenes

private func heroRow(
    _ id: String,
    index: Int,
    status: String = "queued",
    suggestedFor: String? = nil,
    suggestedAt: String = ""
) -> ProjectLensHeroImage {
    ProjectLensHeroImage(
        imageId: id,
        imageIndex: index,
        label: "Frame \(id)",
        status: status,
        sourceRouteKey: "lens_media_area_1_scene_\(index)",
        imageKind: LensImageTaxonomyKind.sceneImage,
        sceneId: "scene_\(id)",
        suggestedForCharacterId: suggestedFor,
        suggestedAt: suggestedAt
    )
}

@Suite("SCENES v2 suggestion laws")
struct ScenesV2SuggestionModelsTests {
    @Test("Priority: the newest sheet batch first, plan order inside it, then the plan")
    func priorityOrder() {
        let rows = [
            heroRow("p1", index: 0),
            heroRow("p2", index: 1),
            heroRow("old_b", index: 5, suggestedFor: "char_a", suggestedAt: "2026-09-01T00:00:00Z"),
            heroRow("old_a", index: 4, suggestedFor: "char_a", suggestedAt: "2026-09-01T00:00:00Z"),
            heroRow("new_a", index: 6, suggestedFor: "char_b", suggestedAt: "2026-09-03T00:00:00Z"),
            heroRow("rendered", index: 2, status: "ready", suggestedFor: "char_b", suggestedAt: "2026-09-03T00:00:00Z"),
        ]
        #expect(scenesV2SuggestedFramesInPriorityOrder(rows).map(\.imageId) == ["new_a", "old_a", "old_b", "p1", "p2"])
        #expect(scenesV2SuggestedFramesInPriorityOrder([]).isEmpty)
    }

    @Test("Suggestion provenance encodes only when set and decodes tolerantly")
    func provenanceCodec() throws {
        let plain = heroRow("plain", index: 0)
        let plainJSON = String(decoding: try JSONCoding.encoder.encode(plain), as: UTF8.self)
        #expect(!plainJSON.contains("suggested"))
        let decodedPlain = try JSONCoding.decoder.decode(ProjectLensHeroImage.self, from: Data(plainJSON.utf8))
        #expect(decodedPlain.suggestedForCharacterId == nil)
        #expect(decodedPlain.suggestedAt == "")
        #expect(!decodedPlain.isSheetSuggestion)

        let suggested = heroRow("sug", index: 1, suggestedFor: " char_x ", suggestedAt: " 2026-09-03T00:00:00Z ")
        let json = String(decoding: try JSONCoding.encoder.encode(suggested), as: UTF8.self)
        #expect(json.contains("suggested_for_character_id"))
        #expect(json.contains("suggested_at"))
        let decoded = try JSONCoding.decoder.decode(ProjectLensHeroImage.self, from: Data(json.utf8))
        #expect(decoded.suggestedForCharacterId == "char_x")
        #expect(decoded.suggestedAt == "2026-09-03T00:00:00Z")
        #expect(decoded.isSheetSuggestion)

        // Blank stamps normalize to "not a suggestion" and never encode.
        let blank = heroRow("blank", index: 2, suggestedFor: "  ", suggestedAt: "  ").normalized()
        #expect(blank.suggestedForCharacterId == nil)
        #expect(!blank.isSheetSuggestion)
        #expect(!String(decoding: try JSONCoding.encoder.encode(blank), as: UTF8.self).contains("suggested"))
    }
}

@Suite("SCENES v2 suggestion copy and CTA laws")
struct ScenesV2SuggestionCopyTests {
    @Test("Title splits on the beat and surfaces a character's name")
    func titleLaw() {
        let plain = scenesV2SuggestionTitle(label: "Quay · turn")
        #expect(plain.title == "Quay")
        #expect(plain.beat == "turn")
        let character = scenesV2SuggestionTitle(label: "Character · Bartholomew Quince")
        #expect(character.title == "Bartholomew Quince")
        #expect(character.beat == "")
        #expect(scenesV2SuggestionTitle(label: "  ").title == "Planned Frame")
    }

    @Test("Brief strips mention tokens and collapses whitespace; eyebrow names the character")
    func briefAndEyebrow() {
        #expect(scenesV2SuggestionBrief(sourcePrompt: "  @Auri waits   by the  pier ", prompt: "x") == "Auri waits by the pier")
        #expect(scenesV2SuggestionBrief(sourcePrompt: "", prompt: "compiled text") == "compiled text")
        #expect(scenesV2SuggestionEyebrow(beat: "turn", forCharacterName: "Auri", isFailed: false) == "For Auri · turn")
        #expect(scenesV2SuggestionEyebrow(beat: "opening", forCharacterName: "", isFailed: false) == "Planned · opening")
        #expect(scenesV2SuggestionEyebrow(beat: "", forCharacterName: "", isFailed: false) == "Planned")
        #expect(scenesV2SuggestionEyebrow(beat: "turn", forCharacterName: "Auri", isFailed: true) == "For Auri · Failed")
    }

    @Test("Render caption states stack and price — unpriced is never $0 — and failures fall back to words")
    func captionAndFailure() {
        #expect(scenesV2RenderCaption(stackLabel: "OpenAI Base", priceNote: "") == "OpenAI Base · unpriced")
        #expect(scenesV2RenderCaption(stackLabel: "OpenAI Base", priceNote: "~$0.04") == "OpenAI Base · ~$0.04")
        #expect(scenesV2RenderCaption(stackLabel: " ", priceNote: "~$0.04") == "No render stack configured")
        #expect(scenesV2SuggestionFailureLine(errorMessage: " rate limited ") == "Render failed — rate limited")
        #expect(scenesV2SuggestionFailureLine(errorMessage: "") == "Render failed — the provider refused")
    }

    @Test("The empty-scene hint names what sits below the stage")
    func emptySceneHint() {
        #expect(scenesV2EmptySceneHint(suggestionCount: 6, renderedCount: 0).contains("6 suggested Frames"))
        #expect(scenesV2EmptySceneHint(suggestionCount: 1, renderedCount: 0).contains("1 suggested Frame below"))
        #expect(scenesV2EmptySceneHint(suggestionCount: 6, renderedCount: 2).contains("Drag a Frame"))
        #expect(scenesV2EmptySceneHint(suggestionCount: 0, renderedCount: 0).contains("click + to pick material"))
    }

    @Test("Whisper trailing slot: stale note, then a running job, then unseen suggestions")
    func whisperTrailing() {
        let stale = (text: "Frame refresh failed", action: ScenesV2PlanStaleAction.refreshSuggestions)
        #expect(scenesV2WhisperTrailing(staleNote: stale, suggestingNames: ["Auri"], unseenSuggestions: [(characterName: "Auri", count: 2)])
            == .staleNote(text: "Frame refresh failed", action: .refreshSuggestions))
        #expect(scenesV2WhisperTrailing(staleNote: nil, suggestingNames: ["Auri"], unseenSuggestions: [])
            == .suggesting(line: "Suggesting Frames for Auri…"))
        #expect(scenesV2WhisperTrailing(staleNote: nil, suggestingNames: ["Auri", "Mara"], unseenSuggestions: [])
            == .suggesting(line: "Suggesting Frames for Auri and Mara…"))
        #expect(scenesV2WhisperTrailing(staleNote: nil, suggestingNames: ["A", "B", "C"], unseenSuggestions: [])
            == .suggesting(line: "Suggesting Frames for 3 characters…"))
        #expect(scenesV2WhisperTrailing(staleNote: nil, suggestingNames: [], unseenSuggestions: [(characterName: "Auri", count: 2)])
            == .newSuggestions(line: "2 NEW FRAMES FOR AURI"))
        #expect(scenesV2WhisperTrailing(staleNote: nil, suggestingNames: [], unseenSuggestions: [(characterName: "Auri", count: 1), (characterName: "Mara", count: 2)])
            == .newSuggestions(line: "3 NEW FRAMES FOR 2 CHARACTERS"))
        #expect(scenesV2WhisperTrailing(staleNote: nil, suggestingNames: [], unseenSuggestions: [(characterName: "Auri", count: 0)]) == .none)
    }

    @Test("Whisper counts say suggested")
    func whisperVocabulary() {
        let parts = scenesV2WhisperParts(hasLens: true, claim: "A claim", fallbackTitle: "", plannedCount: 6, renderedCount: 1, sceneCount: 1)
        #expect(parts?.counts == "6 suggested · 1 rendered · 1 Scene")
    }

    @Test("Scoped status, tile action, seen-id prune, rail fallback")
    func smallLaws() {
        #expect(scenesV2ScopedStatus(current: "Myra's sheet ready", baseline: "Myra's sheet ready") == "")
        #expect(scenesV2ScopedStatus(current: "Rendering Frame", baseline: "Myra's sheet ready") == "Rendering Frame")
        #expect(scenesV2ScopedStatus(current: "", baseline: "x") == "")

        #expect(scenesV2TileAction(stagedSceneName: "", stagedSceneIsLocked: false) == .startScene)
        #expect(scenesV2TileAction(stagedSceneName: "Scene 2", stagedSceneIsLocked: false) == .addToScene(name: "Scene 2"))
        #expect(scenesV2TileAction(stagedSceneName: "Scene 2", stagedSceneIsLocked: true) == .sceneLocked(name: "Scene 2"))
        #expect(ScenesV2TileAction.addToScene(name: "The Long Pier").title == "ADD TO THE LONG PIER")
        #expect(ScenesV2TileAction.sceneLocked(name: "Scene 2").title == "SCENE 2 IS RENDERED")
        #expect(!ScenesV2TileAction.sceneLocked(name: "Scene 2").isEnabled)
        #expect(ScenesV2TileAction.addToScene(name: "Scene 2").menuTitle == "Add to Scene 2")

        #expect(scenesV2PrunedSeenSuggestionIds(seen: ["a", "b"], live: ["b", "c"]) == ["b"])
        #expect(scenesV2RailPosterFallback(entryCount: 0) == "EMPTY")
        #expect(scenesV2RailPosterFallback(entryCount: 3) == "3 FR")
    }
}

private func sourceItem(_ id: String, kind: String? = nil, mediaKind: MediaKind = .image) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: id, sourceId: "src", kind: mediaKind, filename: "\(id).png", path: "/tmp/\(id).png",
        relativePath: "\(id).png", byteCount: 1, modifiedAt: "", width: 10, height: 10,
        thumbnailPath: "", scannedAt: "", derivativeKind: kind, sourceMediaId: nil
    )
}

@Suite("SCENES v2 source material hygiene")
struct ScenesV2SourceMaterialHygieneTests {
    @Test("Derived identity and project kinds drop; photos, footage, and placeable derivatives stay")
    func hygiene() {
        let items = [
            sourceItem("photo"),
            sourceItem("footage", mediaKind: .video),
            sourceItem("sheet", kind: "character_sheet"),
            sourceItem("source", kind: "character_source"),
            sourceItem("composite", kind: "roster_composite_sheet"),
            sourceItem("study", kind: "roster_character_render"),
            sourceItem("project", kind: "project_sheet"),
            sourceItem("map", kind: "terrain_map"),
            sourceItem("region", kind: "terrain_map_region"),
            sourceItem("chain", kind: "video_chain_clip", mediaKind: .video),
            sourceItem("collected", kind: "collected_shot_frame"),
        ]
        let kept = scenesV2SourceMaterialItems(items).map(\.mediaId)
        #expect(kept == ["photo", "footage", "chain", "collected"])
    }
}

@Suite("SCENES v2 character suggestion laws")
struct ScenesV2CharacterSuggestionLawTests {
    private func row(_ id: String, index: Int, kind: String, characterId: String = "", status: String = "queued", suggestedAt: String = "") -> ProjectLensHeroImage {
        ProjectLensHeroImage(
            imageId: id, imageIndex: index, label: id, status: status,
            sourceRouteKey: "lens_media_x_\(index)", imageKind: kind, characterId: characterId,
            sceneId: kind == LensImageTaxonomyKind.sceneImage ? "scene_\(id)" : "",
            suggestedForCharacterId: suggestedAt.isEmpty ? nil : "char_a", suggestedAt: suggestedAt
        )
    }

    @Test("Only moments and linked studies are suggestions; scenery, objects, id-less studies, and rendered rows are not")
    func characterSuggestionSetLaw() {
        let rows = [
            row("scenery", index: 0, kind: LensImageTaxonomyKind.sceneImage),
            row("object", index: 1, kind: LensImageTaxonomyKind.objectImage),
            row("study", index: 2, kind: LensImageTaxonomyKind.characterImage, characterId: "char_a"),
            row("study_noid", index: 3, kind: LensImageTaxonomyKind.characterImage),
            row("moment_old", index: 4, kind: LensImageTaxonomyKind.sceneImage, suggestedAt: "2026-09-01T00:00:00Z"),
            row("moment_new", index: 5, kind: LensImageTaxonomyKind.sceneImage, suggestedAt: "2026-09-03T00:00:00Z"),
            row("moment_failed", index: 6, kind: LensImageTaxonomyKind.sceneImage, status: "failed", suggestedAt: "2026-09-03T00:00:00Z"),
            row("moment_done", index: 7, kind: LensImageTaxonomyKind.sceneImage, status: "ready", suggestedAt: "2026-09-03T00:00:00Z"),
        ]
        #expect(scenesV2CharacterSuggestions(rows).map(\.imageId) == ["moment_new", "moment_failed", "moment_old", "study"])
        #expect(scenesV2SuggestionKind(imageKind: LensImageTaxonomyKind.characterImage, isSheetSuggestion: false) == .study)
        #expect(scenesV2SuggestionKind(imageKind: LensImageTaxonomyKind.sceneImage, isSheetSuggestion: true) == .moment)
        #expect(scenesV2SuggestionEyebrow(beat: "", forCharacterName: "Auri", isFailed: false, isStudy: true) == "Study")
        #expect(scenesV2SuggestionEyebrow(beat: "", forCharacterName: "Auri", isFailed: true, isStudy: true) == "Study · Failed")
    }

    @Test("The avatar takes the first source image, else the sheet, else nothing")
    func castAvatarLaw() {
        let items = [
            sourceItem("comp", kind: "roster_composite_sheet"),
            sourceItem("sheet", kind: "character_sheet"),
            sourceItem("src_a"),
            sourceItem("src_b"),
        ]
        let first = scenesV2CastAvatarSource(referenceMediaIds: ["comp", "ghost", "src_b", "src_a"], activeSheetMediaId: "sheet", items: items)
        #expect(first.path == "/tmp/src_b.png")
        #expect(!first.isSheet)
        let sheetOnly = scenesV2CastAvatarSource(referenceMediaIds: ["comp"], activeSheetMediaId: "sheet", items: items)
        #expect(sheetOnly.path == "/tmp/sheet.png")
        #expect(sheetOnly.isSheet)
        let nothing = scenesV2CastAvatarSource(referenceMediaIds: [], activeSheetMediaId: "missing", items: items)
        #expect(nothing.path == "")
        #expect(ScenesV2CastMark(name: "  bartholomew", hasSheet: false).initial == "B")
    }

    @Test("Rail visibility and the suggestion notice")
    func railAndNoticeLaws() {
        #expect(!scenesV2RailIsVisible(badges: []))
        #expect(!scenesV2RailIsVisible(badges: [.draft, .rendering, .failed]))
        #expect(scenesV2RailIsVisible(badges: [.draft, .ready]))
        #expect(scenesV2RailIsVisible(badges: [.parked]))
        #expect(scenesV2SuggestionNotice(hasSuggestableCharacters: false, suggestingNames: [], suggestionCount: 0) == .createCharacter)
        #expect(scenesV2SuggestionNotice(hasSuggestableCharacters: true, suggestingNames: [], suggestionCount: 0) == .suggestNow)
        #expect(scenesV2SuggestionNotice(hasSuggestableCharacters: true, suggestingNames: ["Auri"], suggestionCount: 0) == .suggesting(line: "Suggesting Frames for Auri…"))
        #expect(scenesV2SuggestionNotice(hasSuggestableCharacters: false, suggestingNames: ["Auri", "Mara"], suggestionCount: 3) == .suggesting(line: "Suggesting Frames for Auri and Mara…"))
        #expect(scenesV2SuggestionNotice(hasSuggestableCharacters: true, suggestingNames: [], suggestionCount: 2) == nil)
        #expect(scenesV2CreateCharacterNotice.contains("CHARACTERS"))
    }
}
