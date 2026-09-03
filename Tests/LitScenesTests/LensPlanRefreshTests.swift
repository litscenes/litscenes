import Foundation
import Testing
@testable import LitScenes

// MARK: Fixtures

private func planRow(
    _ id: String,
    index: Int,
    routeKey: String,
    kind: String,
    status: String = "queued",
    sceneId: String = "",
    areaId: String = "",
    characterId: String = "",
    label: String = "",
    imagePath: String = "",
    generatedAt: String = "",
    prompt: String = ""
) -> ProjectLensHeroImage {
    var row = ProjectLensHeroImage(
        imageId: id,
        imageIndex: index,
        label: label,
        imagePath: imagePath,
        prompt: prompt,
        sourcePrompt: prompt,
        status: status,
        sourceRouteKey: routeKey,
        imageKind: kind,
        characterId: characterId,
        areaId: areaId,
        sceneId: sceneId,
        generatedAt: generatedAt,
        updatedAt: now
    )
    if kind == LensImageTaxonomyKind.sceneImage {
        row.homeSceneImageId = id
    }
    return row
}

private func scene(_ id: String, title: String, beat: String = "") -> LensAreaScene {
    var setting = LensSceneSetting()
    setting.locationName = title
    return LensAreaScene(sceneId: id, title: title, setting: setting, prosePrompt: "", cast: [], enabled: true, storyBeat: beat)
}

private func area(_ id: String, title: String, scenes: [LensAreaScene], placeId: String = "") -> LensArea {
    var value = LensArea()
    value.areaId = id
    value.placeId = placeId
    value.title = title
    var setting = LensSceneSetting()
    setting.locationName = title
    value.setting = setting
    value.scenes = scenes
    return value
}

private let now = "2026-09-02T01:00:00Z"

@Suite("Lens plan refresh laws")
struct LensPlanRefreshTests {
    // MARK: Spread

    @Test("Four scenes with four distinct canonical beats pass the spread rule")
    func spreadAcceptsFourDistinctBeats() {
        let areas = [
            area("area_1", title: "Harbor", scenes: [scene("s1", title: "Pier", beat: "opening"), scene("s2", title: "Market", beat: "rising")]),
            area("area_2", title: "Cliff", scenes: [scene("s3", title: "Path", beat: "turn"), scene("s4", title: "Shrine", beat: "ending")]),
        ]
        #expect(LensCompositionSpread.validationError(areas: areas) == nil)
    }

    @Test("Spread validation names the count, the beats, and scene-less areas")
    func spreadValidationErrors() {
        let five = [
            area("area_1", title: "Harbor", scenes: [scene("s1", title: "Pier", beat: "opening"), scene("s2", title: "Market", beat: "rising")]),
            area("area_2", title: "Cliff", scenes: [scene("s3", title: "Path", beat: "turn"), scene("s4", title: "Shrine", beat: "ending"), scene("s5", title: "Extra", beat: "ending")]),
        ]
        #expect(LensCompositionSpread.validationError(areas: five)?.contains("5 scenes") == true)

        let duplicate = [
            area("area_1", title: "Harbor", scenes: [scene("s1", title: "Pier", beat: "opening"), scene("s2", title: "Market", beat: "opening")]),
            area("area_2", title: "Cliff", scenes: [scene("s3", title: "Path", beat: "turn"), scene("s4", title: "Shrine", beat: "ending")]),
        ]
        #expect(LensCompositionSpread.validationError(areas: duplicate)?.contains("story_beat") == true)

        let sceneless = [area("area_1", title: "Harbor", scenes: []), area("area_2", title: "Cliff", scenes: [scene("s3", title: "Path", beat: "turn")])]
        #expect(LensCompositionSpread.validationError(areas: sceneless)?.contains("has no scenes") == true)
    }

    @Test("Repair drops scene-less areas, trims to four, and assigns the missing beats")
    func spreadRepair() {
        let areas = [
            area("area_1", title: "Harbor", scenes: [scene("s1", title: "Pier", beat: "opening"), scene("s2", title: "Market", beat: "opening")]),
            area("area_2", title: "Cliff", scenes: [scene("s3", title: "Path"), scene("s4", title: "Shrine")]),
            area("area_3", title: "Empty", scenes: []),
            area("area_4", title: "Forest", scenes: [scene("s5", title: "Grove", beat: "ending")]),
        ]
        let repaired = LensCompositionSpread.repaired(areas: areas)
        let scenes = repaired.flatMap(\.scenes)
        #expect(repaired.map(\.areaId) == ["area_1", "area_2"])
        #expect(scenes.count == 4)
        #expect(Set(scenes.map(\.storyBeat)) == Set(LensCompositionSpread.canonicalBeats))
        #expect(scenes.first?.storyBeat == "opening")
        #expect(LensCompositionSpread.validationError(areas: repaired) == nil)
    }

    // MARK: Staleness

    @Test("Staleness and refresh decisions")
    func stalenessMatrix() {
        #expect(framePlanStaleness(storedFingerprint: "abc", activeFingerprint: "abc") == .fresh)
        #expect(framePlanStaleness(storedFingerprint: "abc", activeFingerprint: "xyz") == .stale)
        #expect(framePlanStaleness(storedFingerprint: nil, activeFingerprint: "xyz") == .unknownProvenance)
        #expect(framePlanStaleness(storedFingerprint: "  ", activeFingerprint: "xyz") == .unknownProvenance)

        #expect(framePlanRefreshDecision(staleness: .fresh, purePlanCount: 3, renderedCount: 0) == .none)
        #expect(framePlanRefreshDecision(staleness: .stale, purePlanCount: 3, renderedCount: 1) == .autoReplan)
        #expect(framePlanRefreshDecision(staleness: .unknownProvenance, purePlanCount: 1, renderedCount: 0) == .autoReplan)
        #expect(framePlanRefreshDecision(staleness: .stale, purePlanCount: 0, renderedCount: 4) == .offerPlanMore)
        #expect(framePlanRefreshDecision(staleness: .stale, purePlanCount: 0, renderedCount: 0) == .none)
    }

    // MARK: Merge

    private var existingRows: [ProjectLensHeroImage] {
        [
            planRow("s1", index: 0, routeKey: "lens_media_area_1_scene_1", kind: LensImageTaxonomyKind.sceneImage, sceneId: "scene_1_1", areaId: "area_1", label: "Pier", prompt: "old pier"),
            planRow("s2", index: 1, routeKey: "lens_media_area_1_scene_2", kind: LensImageTaxonomyKind.sceneImage, status: "ready", sceneId: "scene_1_2", areaId: "area_1", label: "Market", imagePath: "/tmp/market.png", generatedAt: now, prompt: "old market"),
            planRow("s3", index: 2, routeKey: "lens_media_area_2_scene_1", kind: LensImageTaxonomyKind.sceneImage, status: "failed", sceneId: "scene_2_1", areaId: "area_2", label: "Path", prompt: "old path"),
            planRow("s4", index: 3, routeKey: "lens_media_area_2_scene_2", kind: LensImageTaxonomyKind.sceneImage, sceneId: "scene_2_2", areaId: "area_2", label: "Shrine", prompt: "old shrine"),
            planRow("c1", index: 4, routeKey: "lens_media_character_1", kind: LensImageTaxonomyKind.characterImage, characterId: "char_mara", label: "Character · Mara"),
            planRow("o1", index: 5, routeKey: "lens_media_object_1", kind: LensImageTaxonomyKind.objectImage, label: "Object · Reliquary"),
            planRow("v2", index: 0, routeKey: "lens_media_area_1_scene_1@v2", kind: LensImageTaxonomyKind.sceneImage, sceneId: "scene_1_1", label: "Pier v2"),
        ]
    }

    private var freshRows: [ProjectLensHeroImage] {
        [
            planRow("f1", index: 0, routeKey: "lens_media_area_1_scene_1", kind: LensImageTaxonomyKind.sceneImage, sceneId: "scene_a_1", areaId: "area_a", label: "Bakery · opening", prompt: "new bakery"),
            planRow("f2", index: 1, routeKey: "lens_media_area_1_scene_2", kind: LensImageTaxonomyKind.sceneImage, sceneId: "scene_1_2", areaId: "area_1", label: "Market again", prompt: "covered"),
            planRow("f3", index: 2, routeKey: "lens_media_area_2_scene_1", kind: LensImageTaxonomyKind.sceneImage, sceneId: "scene_b_1", areaId: "area_b", label: "Lighthouse · turn", prompt: "new lighthouse"),
            planRow("f4", index: 3, routeKey: "lens_media_area_3_scene_1", kind: LensImageTaxonomyKind.sceneImage, sceneId: "scene_c_1", areaId: "area_c", label: "Dunes · ending", prompt: "new dunes"),
            planRow("fc", index: 4, routeKey: "lens_media_character_1", kind: LensImageTaxonomyKind.characterImage, characterId: "char_auri", label: "Character · Auri"),
            planRow("fo", index: 5, routeKey: "lens_media_object_1", kind: LensImageTaxonomyKind.objectImage, label: "Object · Owl Feather"),
        ]
    }

    @Test("Replacing pure plans keeps identity, keeps records verbatim, appends the surplus")
    func mergeReplacesPurePlansInPlace() throws {
        let outcome = LensPlanMerge.merged(existing: existingRows, fresh: freshRows, mediaVersionId: "", mode: .replacePurePlans, now: now)
        let byId = Dictionary(uniqueKeysWithValues: outcome.heroImages.map { ($0.imageId, $0) })

        // s1 took f1 in place.
        let s1 = try #require(byId["s1"])
        #expect(s1.imageIndex == 0)
        #expect(s1.sourceRouteKey == "lens_media_area_1_scene_1")
        #expect(s1.prompt == "new bakery")
        #expect(s1.label == "Bakery · opening")
        #expect(s1.sceneId == "scene_a_1")
        #expect(s1.homeSceneImageId == "s1")
        #expect(s1.status == "queued")
        #expect(s1.isPurePlan)

        // Rendered and failed rows are records: verbatim.
        #expect(byId["s2"] == existingRows[1])
        #expect(byId["s3"] == existingRows[2])

        // s4 took f3 (f2 was covered by the rendered scene_1_2 and skipped).
        #expect(byId["s4"]?.prompt == "new lighthouse")
        #expect(byId["f2"] == nil)

        // f4 had no free scenery slot: appended after the highest existing index.
        let f4 = try #require(byId["f4"])
        #expect(f4.imageIndex == 6)

        // Character and object slots swapped in place.
        #expect(byId["c1"]?.characterId == "char_auri")
        #expect(byId["o1"]?.label == "Object · Owl Feather")

        // The other media version was never touched.
        #expect(byId["v2"] == existingRows[6])

        #expect(Set(outcome.replacedImageIds) == ["s1", "s4", "c1", "o1"])
        #expect(outcome.appendedImageIds == ["f4"])
        #expect(outcome.droppedImageIds.isEmpty)
    }

    @Test("Surplus stale plans are dropped when the fresh plan proposes fewer")
    func mergeDropsSurplusStalePlans() {
        let fresh = Array(freshRows.prefix(1))
        let outcome = LensPlanMerge.merged(existing: existingRows, fresh: fresh, mediaVersionId: "", mode: .replacePurePlans, now: now)
        #expect(outcome.replacedImageIds == ["s1"])
        #expect(Set(outcome.droppedImageIds) == ["s4", "c1", "o1"])
        #expect(outcome.heroImages.contains { $0.imageId == "s2" })
        #expect(outcome.heroImages.contains { $0.imageId == "s3" })
        #expect(!outcome.heroImages.contains { $0.imageId == "s4" })
    }

    @Test("Append-only keeps every row and adds only what nothing covers")
    func mergeAppendOnly() {
        let outcome = LensPlanMerge.merged(existing: existingRows, fresh: freshRows, mediaVersionId: "", mode: .appendOnly, now: now)
        let ids = Set(outcome.heroImages.map(\.imageId))
        #expect(outcome.replacedImageIds.isEmpty)
        #expect(outcome.droppedImageIds.isEmpty)
        for original in existingRows {
            #expect(outcome.heroImages.contains(original))
        }
        #expect(ids.isSuperset(of: ["f1", "f3", "f4", "fc", "fo"]))
        #expect(!ids.contains("f2"))
        let appendedIndexes = outcome.heroImages.filter { outcome.appendedImageIds.contains($0.imageId) }.map(\.imageIndex)
        #expect(appendedIndexes == [6, 7, 8, 9, 10])
    }

    @Test("A Story-driven refresh keeps sheet-driven suggestions and never spends them as free slots")
    func mergeKeepsSheetSuggestions() throws {
        var existing = existingRows
        var suggestion = planRow("g1", index: 6, routeKey: "lens_media_area_3_scene_1", kind: LensImageTaxonomyKind.sceneImage, sceneId: "scene_g_1", areaId: "area_g", label: "Quay · turn", prompt: "quay at dusk")
        suggestion.suggestedForCharacterId = "char_mara"
        suggestion.suggestedAt = "2026-09-03T02:00:00Z"
        existing.append(suggestion)
        let outcome = LensPlanMerge.merged(existing: existing, fresh: freshRows, mediaVersionId: "", mode: .replacePurePlans, now: now)
        let byId = Dictionary(uniqueKeysWithValues: outcome.heroImages.map { ($0.imageId, $0) })
        let kept = try #require(byId["g1"])
        #expect(kept == suggestion)
        #expect(!outcome.replacedImageIds.contains("g1"))
        #expect(!outcome.droppedImageIds.contains("g1"))
        // The surplus fresh row appends after the suggestion instead of taking its slot.
        let f4 = try #require(byId["f4"])
        #expect(f4.imageIndex == 7)
        #expect(!f4.isSheetSuggestion)
    }

    @Test("Append-only keeps two moments for one character; a covered scene id is skipped")
    func appendOnlyKeepsTwoMomentsForOneCharacter() {
        var momentA = planRow("m1", index: 0, routeKey: "lens_media_area_3_scene_1", kind: LensImageTaxonomyKind.sceneImage, sceneId: "scene_m_1", areaId: "area_m", label: "Quay · turn", prompt: "The moment: Mara tears the page.")
        var momentB = planRow("m2", index: 1, routeKey: "lens_media_area_3_scene_2", kind: LensImageTaxonomyKind.sceneImage, sceneId: "scene_m_2", areaId: "area_m", label: "Salt · rising", prompt: "The moment: Mara counts the ledger.")
        var covered = planRow("m3", index: 2, routeKey: "lens_media_area_1_scene_2", kind: LensImageTaxonomyKind.sceneImage, sceneId: "scene_1_2", areaId: "area_1", label: "Market again", prompt: "covered")
        for row in [0, 1, 2] {
            switch row {
            case 0: momentA.suggestedForCharacterId = "char_mara"; momentA.suggestedAt = now
            case 1: momentB.suggestedForCharacterId = "char_mara"; momentB.suggestedAt = now
            default: covered.suggestedForCharacterId = "char_mara"; covered.suggestedAt = now
            }
        }
        let outcome = LensPlanMerge.merged(existing: existingRows, fresh: [momentA, momentB, covered], mediaVersionId: "", mode: .appendOnly, now: now)
        #expect(outcome.appendedImageIds == ["m1", "m2"])
        #expect(!outcome.heroImages.contains { $0.imageId == "m3" })
        let appended = outcome.heroImages.filter { $0.suggestedForCharacterId == "char_mara" }
        #expect(appended.count == 2)
        #expect(appended.allSatisfy { $0.prompt.hasPrefix("The moment:") })
    }

    @Test("A Story-driven refresh never rewrites a moment row's words")
    func replanNeverRewritesAMomentRow() throws {
        var existing = existingRows
        var moment = planRow("g1", index: 6, routeKey: "lens_media_area_3_scene_1", kind: LensImageTaxonomyKind.sceneImage, sceneId: "scene_g_1", areaId: "area_g", label: "Quay · turn", prompt: "The moment: Mara tears the page.")
        moment.suggestedForCharacterId = "char_mara"
        moment.suggestedAt = now
        existing.append(moment)
        let scenery = planRow("f9", index: 0, routeKey: "lens_media_area_3_scene_1", kind: LensImageTaxonomyKind.sceneImage, sceneId: "scene_g_1", areaId: "area_g", label: "Quay · turn", prompt: "Create one wide cinematic environment concept image.")
        let outcome = LensPlanMerge.merged(existing: existing, fresh: [scenery], mediaVersionId: "", mode: .replacePurePlans, now: now)
        let kept = try #require(outcome.heroImages.first { $0.imageId == "g1" })
        #expect(kept.prompt == "The moment: Mara tears the page.")
        #expect(kept.sourcePrompt == "The moment: Mara tears the page.")
        #expect(kept.label == "Quay · turn")
        #expect(!outcome.heroImages.contains { $0.imageId == "f9" })
        #expect(!outcome.replacedImageIds.contains("g1"))
    }

    @Test("Replacing a slot carries the candidate's suggestion stamp")
    func replacingCarriesSuggestionStamp() throws {
        var fresh = Array(freshRows.prefix(1))
        fresh[0].suggestedForCharacterId = "char_auri"
        fresh[0].suggestedAt = "2026-09-03T02:00:00Z"
        let outcome = LensPlanMerge.merged(existing: existingRows, fresh: fresh, mediaVersionId: "", mode: .replacePurePlans, now: now)
        let s1 = try #require(outcome.heroImages.first { $0.imageId == "s1" })
        #expect(s1.suggestedForCharacterId == "char_auri")
        #expect(s1.isSheetSuggestion)
    }

    // MARK: World replacement

    @Test("Replanned world keeps rendered scenes ahead, re-mints colliding ids, keeps the look")
    func replannedWorldKeepsRenderedScenes() throws {
        var body = LensBody()
        body.title = "Old Title"
        body.claim = "Old claim"
        body.areas = [
            area("area_1", title: "Harbor", scenes: [scene("scene_1_1", title: "Pier"), scene("scene_1_2", title: "Market")], placeId: "place_harbor"),
            area("area_2", title: "Cliff", scenes: [scene("scene_2_1", title: "Path"), scene("scene_2_2", title: "Shrine")], placeId: "place_cliff"),
        ]
        body.castMembers = [LensCastMember(castId: "cast_mara", name: "Mara", descriptionPrompt: "lean", characterId: "char_mara")]

        let kept = [
            planRow("s2", index: 1, routeKey: "lens_media_area_1_scene_2", kind: LensImageTaxonomyKind.sceneImage, status: "ready", sceneId: "scene_1_2", areaId: "area_1", imagePath: "/tmp/m.png", generatedAt: now),
            planRow("c1", index: 4, routeKey: "lens_media_character_1", kind: LensImageTaxonomyKind.characterImage, status: "ready", characterId: "char_mara", imagePath: "/tmp/c.png", generatedAt: now),
        ]
        let newAreas = [
            area("area_1", title: "Bakery", scenes: [scene("scene_1_1", title: "Counter", beat: "opening"), scene("scene_9_1", title: "Oven", beat: "rising")]),
            area("area_3", title: "Lighthouse", scenes: [scene("scene_3_1", title: "Lamp room", beat: "turn")]),
            area("area_4", title: "Nothing here", scenes: []),
        ]
        let replanned = body.replannedWorld(
            areas: newAreas,
            castMembers: [LensCastMember(castId: "cast_auri", name: "Auri", descriptionPrompt: "silver hair", characterId: "char_auri")],
            objectConcepts: nil,
            setDressing: ["bread baskets"],
            keptFrames: kept,
            planGoalVersionId: "goal_v2",
            planGoalFingerprint: "fp2"
        )
        let areas = try #require(replanned.areas)
        #expect(areas.count == 3)
        #expect(areas[0].areaId == "area_1")
        #expect(areas[0].scenes.map(\.sceneId) == ["scene_1_2"])
        #expect(areas[1].areaId != "area_1")
        #expect(areas[1].scenes.map(\.sceneId).contains("scene_1_1") == false)
        #expect(areas[1].scenes.map(\.sceneId).contains("scene_9_1"))
        #expect(areas[2].areaId == "area_3")
        #expect(!areas.contains { $0.areaId == "area_4" })
        #expect(replanned.title == "Old Title")
        #expect(replanned.claim == "Old claim")
        #expect(Set((replanned.castMembers ?? []).map(\.name)) == ["Auri", "Mara"])
        #expect(replanned.setDressingImagePrompts == ["bread baskets"])
        #expect(replanned.planGoalVersionId == "goal_v2")
        #expect(replanned.planGoalFingerprint == "fp2")
        // Normalization must not resurrect the scene-less area.
        #expect(replanned.normalized().areas?.count == 3)
    }

    // MARK: Places

    @Test("Retired places are pruned only when nothing holds them")
    func placePruning() {
        var document = ProjectPlaceSetDocument(projectId: "p")
        document.places = [
            ProjectPlace(placeId: "p1", name: "Station", updatedAt: now),
            ProjectPlace(placeId: "p2", name: "Sanctuary", referenceMediaIds: ["media_1"], updatedAt: now),
            ProjectPlace(placeId: "p3", name: "Pinned", updatedAt: now),
            ProjectPlace(placeId: "p4", name: "Bakery", updatedAt: now),
        ]
        let pruned = prunedProjectPlaces(document, retiredPlaceIds: ["p1", "p2", "p3"], referencedPlaceIds: ["p3", "p4"], now: now)
        #expect(pruned.places.map(\.placeId) == ["p2", "p3", "p4"])
        #expect(pruned.updatedAt == now)
        let untouched = prunedProjectPlaces(document, retiredPlaceIds: [], referencedPlaceIds: [], now: "later")
        #expect(untouched == document)
    }

    // MARK: Tolerant decode

    @Test("storyBeat and plan provenance decode tolerantly and round-trip")
    func tolerantDecode() throws {
        let legacy = Data(#"{"scene_id":"s","title":"T","setting":{},"prose_prompt":"","cast":[],"enabled":true}"#.utf8)
        let legacyScene = try JSONCoding.decoder.decode(LensAreaScene.self, from: legacy)
        #expect(legacyScene.storyBeat == "")

        let beat = Data(#"{"scene_id":"s","title":"T","setting":{},"prose_prompt":"","cast":[],"enabled":true,"story_beat":" Turn "}"#.utf8)
        let beatScene = try JSONCoding.decoder.decode(LensAreaScene.self, from: beat)
        #expect(beatScene.normalized().storyBeat == "turn")

        // A body persisted before provenance existed carries neither key.
        let legacyEncoded = try JSONCoding.encoder.encode(LensBody())
        #expect(!String(decoding: legacyEncoded, as: UTF8.self).contains("plan_goal_fingerprint"))
        let legacyBody = try JSONCoding.decoder.decode(LensBody.self, from: legacyEncoded)
        #expect(legacyBody.planGoalFingerprint == nil)
        #expect(legacyBody.planGoalVersionId == nil)

        var body = LensBody()
        body.planGoalVersionId = "goal_v2"
        body.planGoalFingerprint = "fp"
        let encoded = try JSONCoding.encoder.encode(body)
        #expect(String(decoding: encoded, as: UTF8.self).contains("plan_goal_fingerprint"))
        let decoded = try JSONCoding.decoder.decode(LensBody.self, from: encoded)
        #expect(decoded.planGoalVersionId == "goal_v2")
        #expect(decoded.planGoalFingerprint == "fp")
    }

    // MARK: Planning inputs

    @Test("Observation lines carry subject matter and no style words")
    func observationLinesAreContentOnly() {
        var observation = ImageObservationResult()
        observation.plainCaption = "A panda-like animal stands on a night path"
        observation.setting = "Outdoor nighttime path"
        observation.objects = ["animal", "tall grass"]
        observation.mood = ["eerie"]
        observation.paletteTerms = ["teal"]
        observation.lighting = "harsh flash"
        observation.peopleVisible = false
        observation.motifCues = ["omen"]
        let lines = lensPlanningMediaObservationLines([("panda.jpg", observation)], limit: 16)
        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.hasPrefix("- panda.jpg: caption="))
        #expect(line.contains("people=none"))
        #expect(line.contains("meanings=omen"))
        #expect(!line.contains("mood="))
        #expect(!line.contains("palette="))
        #expect(!line.contains("lighting="))
        #expect(!line.contains("eerie"))

        let many = (0..<20).map { ("img\($0).png", observation) }
        let capped = lensPlanningMediaObservationLines(many, limit: 16)
        #expect(capped.count == 17)
        #expect(capped.last?.contains("+4 more") == true)
    }

    @Test("Goal-cast lines add only members the roster does not know")
    func goalCastLinesUnion() throws {
        let json = """
        {"schema_version":"litscenes.goal_cast.v0.1","project_id":"p","goal_version_id":"g","articulated_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z","members":[
          {"member_id":"m1","name":"Auri of the Soft Ears","role_label":"guide","character_id":"","active_take_id":"t1","pinned_dimensions":[],"updated_at":"2026-01-01T00:00:00Z","takes":[{"take_id":"t1","origin":"initial","created_at":"2026-01-01T00:00:00Z","identity":{"essence":"Tender omen","visual_description":"Silver hair, large ears","strangeness":0.5}}]},
          {"member_id":"m2","name":"Mara","role_label":"","character_id":"","active_take_id":"","pinned_dimensions":[],"updated_at":"2026-01-01T00:00:00Z","takes":[]}
        ]}
        """
        let document = try JSONCoding.decoder.decode(GoalCastDocument.self, from: Data(json.utf8))
        let lines = lensPlanningGoalCastLines(goalCast: document, excludingNames: ["mara"])
        #expect(lines == ["- Auri of the Soft Ears (guide) — Silver hair, large ears | essence: Tender omen"])
    }

    @Test("The composition prompt is register-neutral, spread-ruled, and cast-locked")
    func compositionPromptRegister() {
        let context = LensTrioContext(
            projectId: "p",
            projectName: "Test",
            goalSummary: "A gentle seaside bakery tale.",
            meaningContext: "",
            slateLines: ["[0] Style"],
            rosterCharacterLines: ["- Auri — silver hair"],
            mediaObservationLines: ["- owl.png: caption=an owl on a branch"]
        )
        let prompt = OpenAIClient.lensCompositionPrompt(context: context)
        for required in ["four DISPARATE", "story_beat", "invent no one", "pristine world has pristine places", "Story Input media observations", "owl.png", "EXACTLY 4 child Scenes"] {
            #expect(prompt.contains(required), "missing: \(required)")
        }
        for banned in ["where the world's history shows", "where the world's condition becomes visible", "signage, equipment, remnants, infrastructure", "continuous journey", "journey's beats", "degraded or environmental text", "exactly 2 scenes"] {
            #expect(!prompt.contains(banned), "present: \(banned)")
        }
    }

    // MARK: v2 spotlight

    @Test("Spotlight distinguishes a Story-driven refresh from the first plan")
    func spotlightRefreshState() {
        let refreshing = scenesV2StageSpotlightState(hasLens: true, isGoalReady: true, isPlanningActive: false, isRefreshActive: true, planFailed: false, plannedImageIdsInPlanOrder: ["a"], renderedFrameCount: 0, sceneCount: 0)
        #expect(refreshing == .planning(refresh: true))
        let planning = scenesV2StageSpotlightState(hasLens: false, isGoalReady: true, isPlanningActive: true, isRefreshActive: true, planFailed: false, plannedImageIdsInPlanOrder: [], renderedFrameCount: 0, sceneCount: 0)
        #expect(planning == .planning(refresh: false))
    }

    @Test("Stale note copy")
    func staleNoteCopy() {
        #expect(scenesV2PlanStaleNote(staleness: .fresh, decision: .none, isRefreshing: false, refreshFailed: false) == nil)
        #expect(scenesV2PlanStaleNote(staleness: .stale, decision: .autoReplan, isRefreshing: false, refreshFailed: false) == nil)
        let refreshing = scenesV2PlanStaleNote(staleness: .stale, decision: .autoReplan, isRefreshing: true, refreshFailed: false)
        #expect(refreshing?.text == "Story changed — refreshing suggestions…")
        #expect(refreshing?.action == .quiet)
        let failed = scenesV2PlanStaleNote(staleness: .stale, decision: .autoReplan, isRefreshing: false, refreshFailed: true)
        #expect(failed?.action == .refreshSuggestions)
        let more = scenesV2PlanStaleNote(staleness: .stale, decision: .offerPlanMore, isRefreshing: false, refreshFailed: false)
        #expect(more?.text == "Story changed since these Frames were planned")
        #expect(more?.action == .planMoreFrames)
    }
}
