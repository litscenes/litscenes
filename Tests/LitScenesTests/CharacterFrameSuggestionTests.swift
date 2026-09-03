import Foundation
import Testing
@testable import LitScenes

private func setting(_ name: String) -> LensSceneSetting {
    var value = LensSceneSetting()
    value.title = name
    value.locationName = name
    value.spatialLayout = "a long view down \(name)"
    value.foregroundDetails = ["rope", "crate"]
    value.backgroundDetails = ["mast", "cloud"]
    value.notableFeatures = ["a bell"]
    return value
}

private func existingBody() -> LensBody {
    var body = LensBody()
    var area = LensArea()
    area.areaId = "area_pier"
    area.title = "The Long Pier"
    area.setting = setting("The Long Pier")
    area.scenes = [
        LensAreaScene(sceneId: "scene_pier_1", title: "Arrival", setting: setting("The Long Pier"), prosePrompt: "", cast: [LensSceneCastEntry(name: "Auri", presence: "")], enabled: true, storyBeat: "opening"),
    ]
    body.areas = [area]
    return body
}

private func suggestion(areaRef: String, area: LensArea?, title: String, cast: [String], beat: String = "turn") -> CharacterFrameSuggestedScene {
    CharacterFrameSuggestedScene(
        areaRef: areaRef,
        area: area,
        scene: LensAreaScene(
            sceneId: "ignored",
            title: title,
            setting: setting(title),
            prosePrompt: "\(title) prose",
            cast: cast.map { LensSceneCastEntry(name: $0, presence: "standing") },
            enabled: false,
            storyBeat: beat
        )
    )
}

private func newArea(_ title: String) -> LensArea {
    var area = LensArea()
    area.title = title
    area.setting = setting(title)
    area.prosePrompt = "\(title) prose"
    return area
}

@Suite("Sheet → frame suggestion laws")
struct CharacterFrameSuggestionTests {
    @Test("Suggestions attach by area_ref, mint at most one new area, and lead with the character")
    func appendingAttachesAndMintsOnce() throws {
        let body = existingBody()
        let result = body.appendingSuggestedScenes(
            [
                suggestion(areaRef: "area_pier", area: nil, title: "Night Watch", cast: ["mara", "Auri", "Nobody Real"]),
                suggestion(areaRef: "", area: newArea("The Salt House"), title: "The Ledger", cast: ["Mara"]),
                suggestion(areaRef: "", area: newArea("A Third Place"), title: "Never Used", cast: []),
            ],
            characterName: "Auri",
            validCastNames: ["Auri", "Mara"],
            salt: "char_auri:2026-09-03T02:00:00Z"
        )
        let areas = try #require(result.body.areas)
        #expect(areas.count == 2)
        #expect(result.newSceneIds.count == 2)

        let pier = try #require(areas.first { $0.areaId == "area_pier" })
        #expect(pier.scenes.count == 2)
        let watch = try #require(pier.scenes.last)
        #expect(watch.title == "Night Watch")
        #expect(watch.enabled)
        #expect(watch.sceneId != "ignored")
        #expect(watch.sceneId != "scene_pier_1")
        #expect(watch.cast.map(\.name) == ["Auri", "Mara"])
        #expect(watch.storyBeat == "turn")

        let salt = try #require(areas.first { $0.title == "The Salt House" })
        #expect(!salt.areaId.isEmpty)
        #expect(salt.areaId != "area_pier")
        #expect(salt.scenes.count == 1)
        let ledger = try #require(salt.scenes.first)
        #expect(ledger.cast.map(\.name) == ["Auri", "Mara"])
        #expect(ledger.cast.first?.presence == "")
        // The third suggestion was over the batch cap; its area was never minted.
        #expect(!areas.contains { $0.title == "A Third Place" })
    }

    @Test("Unresolvable references and empty scenes are skipped; colliding ids are re-minted")
    func appendingSkipsAndReMints() throws {
        let body = existingBody()
        var duplicate = LensAreaScene(title: "Arrival", setting: setting("The Long Pier"), prosePrompt: "", cast: [], enabled: true, storyBeat: "opening")
        duplicate = duplicate.normalized(areaId: "area_pier", order: 1)
        let result = body.appendingSuggestedScenes(
            [
                suggestion(areaRef: "area_missing", area: nil, title: "Nowhere", cast: ["Auri"]),
                CharacterFrameSuggestedScene(areaRef: "area_pier", area: nil, scene: duplicate),
            ],
            characterName: "Auri",
            validCastNames: ["Auri"],
            salt: "salt"
        )
        #expect(result.newSceneIds.count == 1)
        let ids = Set((result.body.areas ?? []).flatMap(\.scenes).map(\.sceneId))
        #expect(ids.count == 2)
        let blank = body.appendingSuggestedScenes(
            [suggestion(areaRef: "area_pier", area: nil, title: "", cast: [])].map { value in
                var scene = value.scene
                scene.setting = LensSceneSetting()
                scene.prosePrompt = ""
                return CharacterFrameSuggestedScene(areaRef: value.areaRef, area: nil, scene: scene)
            },
            characterName: "Auri",
            validCastNames: ["Auri"],
            salt: "salt"
        )
        #expect(blank.newSceneIds.isEmpty)
    }

    @Test("Moments are recorded per new scene and fill the lead's empty presence")
    func appendingRecordsMoments() throws {
        let body = existingBody()
        var withMoment = suggestion(areaRef: "area_pier", area: nil, title: "Night Watch", cast: ["Auri"])
        withMoment.moment = " Auri tears the ledger page "
        withMoment.scene.cast = []
        let result = body.appendingSuggestedScenes(
            [withMoment],
            characterName: "Auri",
            validCastNames: ["Auri", "Mara"],
            salt: "salt"
        )
        let sceneId = try #require(result.newSceneIds.first)
        #expect(result.momentsBySceneId[sceneId] == "Auri tears the ledger page")
        let scene = try #require((result.body.areas ?? []).flatMap(\.scenes).first { $0.sceneId == sceneId })
        #expect(scene.cast.first?.name == "Auri")
        #expect(scene.cast.first?.presence == "Auri tears the ledger page")
    }

    @Test("Suggestable identity: sheet, else source images (composites excluded), else nothing; the attempt key follows the fingerprint")
    func identityAndAttemptKeyLaws() {
        func media(_ id: String, kind: String? = nil) -> MediaItemRecord {
            MediaItemRecord(
                mediaId: id, sourceId: "src", kind: .image, filename: "\(id).png", path: "/tmp/\(id).png",
                relativePath: "\(id).png", byteCount: 1, modifiedAt: "", width: 10, height: 10,
                thumbnailPath: "", scannedAt: "", derivativeKind: kind, sourceMediaId: nil
            )
        }
        let items = [media("sheet_1", kind: "character_sheet"), media("comp_1", kind: "roster_composite_sheet"), media("src_1"), media("src_2")]
        var character = ProjectCharacter(characterId: "c1", name: "Auri", updatedAt: "2026-01-01T00:00:00Z")
        character.referenceMediaIds = ["comp_1", "src_2", "ghost", "src_1"]
        character.activeSheetMediaId = "sheet_1"
        let withSheet = characterSuggestionIdentity(character: character, items: items)
        #expect(withSheet.isSuggestable)
        #expect(withSheet.sheetMediaId == "sheet_1")
        #expect(withSheet.sourceMediaIds == ["src_2", "src_1"])
        #expect(withSheet.visionMediaId == "sheet_1")
        #expect(withSheet.identityImageKind == .sheet)

        character.activeSheetMediaId = "missing_sheet"
        let sourcesOnly = characterSuggestionIdentity(character: character, items: items)
        #expect(sourcesOnly.sheetMediaId == "")
        #expect(sourcesOnly.visionMediaId == "src_2")
        #expect(sourcesOnly.identityImageKind == .sourcePhoto)

        character.referenceMediaIds = ["comp_1", "ghost"]
        let nothing = characterSuggestionIdentity(character: character, items: items)
        #expect(!nothing.isSuggestable)
        #expect(nothing.identityImageKind == .none)
        #expect(nothing.visionMediaId == nil)

        let keyA = characterFrameSuggestionAttemptKey(projectId: "p1", identity: withSheet)
        let keyB = characterFrameSuggestionAttemptKey(projectId: "p1", identity: sourcesOnly)
        var reordered = withSheet
        reordered.sourceMediaIds = ["src_1", "src_2"]
        #expect(keyA != keyB)
        #expect(keyA != characterFrameSuggestionAttemptKey(projectId: "p1", identity: reordered))
        #expect(keyA != characterFrameSuggestionAttemptKey(projectId: "p2", identity: withSheet))
        #expect(keyA.hasPrefix("p1|c1|"))
    }

    @Test("The response decodes tolerantly, area null included")
    func responseDecodes() throws {
        let json = #"""
        {"schema_version":"litscenes.character_frame_suggestions.v0.1","casting_note":"why",
         "scenes":[
          {"area_ref":"area_pier","area":null,"moment":"Auri tears the ledger page","scene":{"title":"Night Watch","setting":{"title":"Pier","location_name":"The Long Pier","location_type":"exterior","time_of_day":"night","weather":"still","spatial_layout":"long","foreground_details":["a","b"],"background_details":["c","d"],"notable_features":["e"]},"prose_prompt":"p","cast":[{"name":"Auri","presence":"waits"}],"story_beat":"turn"}},
          {"area_ref":"","area":{"title":"The Salt House","setting":{"title":"Salt","location_name":"The Salt House","location_type":"interior","time_of_day":"dawn","weather":"dry","spatial_layout":"low","foreground_details":["a","b"],"background_details":["c","d"],"notable_features":["e"]},"prose_prompt":"q"},"scene":{"title":"The Ledger","setting":{"title":"Salt","location_name":"The Salt House","location_type":"interior","time_of_day":"dawn","weather":"dry","spatial_layout":"low","foreground_details":["a","b"],"background_details":["c","d"],"notable_features":["e"]},"prose_prompt":"r","cast":[{"name":"Auri","presence":"counts"}],"story_beat":"rising"}}
         ]}
        """#
        let response = try CharacterFrameSuggestionResponse.decode(from: Data(json.utf8))
        #expect(response.scenes.count == 2)
        #expect(response.scenes[0].area == nil)
        #expect(response.scenes[0].scene.storyBeat == "turn")
        #expect(response.scenes[0].moment == "Auri tears the ledger page")
        #expect(response.scenes[1].moment == "")
        #expect(response.scenes[1].area?.title == "The Salt House")
        #expect(response.scenes[1].area?.prosePrompt == "q")
        #expect(response.scenes[1].scene.setting.locationName == "The Salt House")
        let legacy = try CharacterFrameSuggestionResponse.decode(from: Data(#"{"scenes":[]}"#.utf8))
        #expect(legacy.scenes.isEmpty)
        #expect(legacy.castingNote == "")
    }

    @Test("The suggestion prompt is register-neutral, distinct-scene ruled, and character-locked")
    func promptRegister() {
        func context(project: String, name: String, other: String, scene: String) -> CharacterFrameSuggestionContext {
            CharacterFrameSuggestionContext(
                projectId: "p", projectName: project, characterId: "c", characterName: name,
                characterAppearance: "tall", characterIdentityGist: "wants the ledger",
                otherCharacterLines: ["- \(other)"], goalSummary: "A goal.",
                existingAreaLines: ["- area_id=area_1 · Place · place"],
                existingSceneLines: ["- \(scene) · beat=opening · area_id=area_1 · cast=\(name)"],
                mediaObservationLines: ["- photo: a pier"], sourceImageLines: "", attachedIdentityImage: .sheet
            )
        }
        let one = OpenAIClient.characterFrameSuggestionsPrompt(context: context(project: "Harbor", name: "Auri", other: "Mara", scene: "Arrival"))
        let two = OpenAIClient.characterFrameSuggestionsPrompt(context: context(project: "Orchard", name: "Bartholomew Quince", other: "Wren", scene: "The Long Pier"))
        for prompt in [one, two] {
            #expect(prompt.contains("SUBJECT MATTER ONLY"))
            #expect(prompt.contains("DISTINCT from every existing scene"))
            #expect(prompt.contains("area_ref"))
            #expect(prompt.contains("story_beat"))
            #expect(prompt.contains("rendered reference sheet"))
            #expect(prompt.contains("dramatic MOMENTS"))
            #expect(prompt.contains("ACTS"))
            #expect(prompt.contains("never an empty environment view"))
            #expect(!prompt.lowercased().contains("scenery"))
            #expect(!prompt.contains("environment concept"))
        }
        var photo = context(project: "Harbor", name: "Auri", other: "Mara", scene: "Arrival")
        photo.attachedIdentityImage = .sourcePhoto
        #expect(OpenAIClient.characterFrameSuggestionsPrompt(context: photo).contains("source photo of \"Auri\""))
        photo.attachedIdentityImage = .none
        #expect(OpenAIClient.characterFrameSuggestionsPrompt(context: photo).contains("No reference image is attached"))
        #expect(one.contains("\"Auri\""))
        #expect(!one.contains("Bartholomew"))
        #expect(!one.contains("Orchard"))
        #expect(two.contains("\"Bartholomew Quince\""))
        #expect(!two.contains("Auri"))
        #expect(!two.contains("Harbor"))
    }

    @Test("The composition prompt still carries the HARD RULE core verbatim")
    func compositionPromptCarriesCore() {
        let context = LensTrioContext(
            projectId: "p",
            projectName: "Harbor",
            goalSummary: "A goal.",
            meaningContext: "",
            slateLines: ["[0] Style"],
            rosterCharacterLines: [],
            mediaObservationLines: []
        )
        let prompt = OpenAIClient.lensCompositionPrompt(context: context)
        #expect(prompt.contains(OpenAIClient.contentFieldHardRuleCore))
        #expect(prompt.contains("HARD RULE for every content field (areas, cast_members, object_concepts, set_dressing): SUBJECT MATTER ONLY"))
    }
}
