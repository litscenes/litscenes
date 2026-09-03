import Foundation
import Testing
@testable import LitScenes

private func observation(people: Bool, count: Int? = nil, roles: [String] = [], caption: String = "", literal: String = "") -> ImageObservationResult {
    var value = ImageObservationResult()
    value.peopleVisible = people
    value.peopleCountEstimate = count
    value.peopleRolesVisible = roles
    value.plainCaption = caption
    value.literalDescription = literal
    return value
}

private func context(photos: [String], desiredCount: Int? = nil, cap: Int = GoalCastDocument.automaticCastCap) -> GoalCastArticulationContext {
    GoalCastArticulationContext(
        projectId: "p",
        goalSummary: "A goal.",
        requiredEntityLines: [],
        rosterCharacterLines: [],
        existingMemberSummaries: [],
        excludeNames: [],
        desiredCount: desiredCount,
        peoplePhotoLines: photos,
        castCap: cap
    )
}

@Suite("Media-first casting laws")
struct GoalCastArticulationMediaTests {
    @Test("People-photo lines keep only photos with people, in order, capped, with the media id first")
    func peoplePhotoLines() {
        let entries: [(mediaId: String, observation: ImageObservationResult)] = [
            ("m_new", observation(people: true, count: 2, roles: ["parent", "child"], caption: "two people on a pier", literal: "an adult and a child")),
            ("m_none", observation(people: false, caption: "a pier")),
            ("m_old", observation(people: true, caption: "one person")),
            ("", observation(people: true)),
        ]
        let lines = goalCastPeoplePhotoLines(entries)
        #expect(lines.count == 2)
        #expect(lines[0] == "- media_id=m_new people=2 (parent, child) caption=two people on a pier literal=an adult and a child")
        #expect(lines[1] == "- media_id=m_old people=some caption=one person")
        #expect(goalCastPeoplePhotoLines(entries, limit: 1).count == 1)
    }

    @Test("The articulation prompt caps at two and goes media-first when photos show people")
    func promptWithPhotos() {
        let prompt = OpenAIClient.goalCastArticulationPrompt(context: context(photos: ["- media_id=m_new people=2 caption=two people"]))
        for required in ["at most 2 members in total", "MEDIA FIRST", "reference_media_ids", "media_id=m_new", "Never identify a real person by name"] {
            #expect(prompt.contains(required), "missing: \(required)")
        }
        #expect(!prompt.contains("Return 0-4 members"))
        #expect(!prompt.contains("No Story Input photo shows a person"))
    }

    @Test("Without people photos the prompt invents one, and an explicit add stays exact")
    func promptWithoutPhotos() {
        let auto = OpenAIClient.goalCastArticulationPrompt(context: context(photos: []))
        #expect(auto.contains("No Story Input photo shows a person"))
        #expect(auto.contains("Return 1 member, or 2 only when the Goal clearly needs two people"))
        #expect(auto.contains("at most 2 members in total"))
        #expect(!auto.contains("MEDIA FIRST"))
        let add = OpenAIClient.goalCastArticulationPrompt(context: context(photos: [], desiredCount: 1))
        #expect(add.contains("Return exactly 1 new member."))
        #expect(!add.contains("Return 1 member, or 2 only"))
        // Counter-fixture: a different cap prints as data.
        let five = OpenAIClient.goalCastArticulationPrompt(context: context(photos: [], cap: 5))
        #expect(five.contains("at most 5 members in total"))
    }

    @Test("Articulated members decode with or without reference_media_ids; the response defaults to v0.2")
    func memberDecodesTolerantly() throws {
        let legacy = Data(#"{"schema_version":"litscenes.goal_cast_articulation.v0.1","members":[{"name":"Auri","essence":"e","public_function":"p","desire":"d","operating_rule":"o","cost":"c","signature":"s","formative_pressure":"f","strangeness":0.4,"visual_description":"v","changed_fields":["essence"]}],"casting_note":""}"#.utf8)
        let legacyResponse = try JSONCoding.decoder.decode(GoalCastArticulationResponse.self, from: legacy)
        #expect(legacyResponse.members.first?.referenceMediaIds == [])
        let anchored = Data(#"{"members":[{"name":"Auri","reference_media_ids":["m1","m2"]}]}"#.utf8)
        let anchoredResponse = try JSONCoding.decoder.decode(GoalCastArticulationResponse.self, from: anchored)
        #expect(anchoredResponse.members.first?.referenceMediaIds == ["m1", "m2"])
        #expect(anchoredResponse.schemaVersion == "litscenes.goal_cast_articulation.v0.2")
    }

    @Test("Reference sanitizer keeps known image ids only, deduped and capped")
    func sanitizer() {
        let known: Set<String> = ["m1", "m2", "m3"]
        #expect(sanitizedGoalCastReferenceMediaIds(["m2", "ghost", "m2", " ", "m1"], knownImageMediaIds: known) == ["m2", "m1"])
        #expect(sanitizedGoalCastReferenceMediaIds(["m1", "m2", "m3"], knownImageMediaIds: known, limit: 2) == ["m1", "m2"])
        #expect(sanitizedGoalCastReferenceMediaIds([], knownImageMediaIds: known).isEmpty)
    }

    @Test("Removing the member linked to a deleted character: by id, then by name, else untouched")
    func removingLinkedMember() {
        let document = GoalCastDocument(
            projectId: "p",
            members: [
                GoalCastMember(memberId: "m1", name: "Auri", characterId: "c1"),
                GoalCastMember(memberId: "m2", name: "Mara", characterId: ""),
            ]
        )
        let byId = document.removingMember(linkedTo: "c1", name: "Someone Else")
        #expect(byId.removed?.memberId == "m1")
        #expect(byId.document.members.map(\.memberId) == ["m2"])
        let byName = document.removingMember(linkedTo: "c_unknown", name: "mara")
        #expect(byName.removed?.memberId == "m2")
        #expect(byName.document.members.map(\.memberId) == ["m1"])
        let untouched = document.removingMember(linkedTo: "c_unknown", name: "Nobody")
        #expect(untouched.removed == nil)
        #expect(untouched.document == document)
    }
}

@Suite("One photo, one character")
struct GoalCastReferenceAllocationTests {
    @Test("A contested photo goes to the member with fewer photos; roster-held photos drop out; order survives")
    func allocation() {
        // The scholar holds two photos, the guide only the shared one: the guide keeps it.
        let shared = allocatedGoalCastReferenceMediaIds([["m_shared", "m_scholar"], ["m_shared"]], alreadyClaimed: [])
        #expect(shared == [["m_scholar"], ["m_shared"]])
        // Ties go to the earlier member.
        let tie = allocatedGoalCastReferenceMediaIds([["m_a", "m_x"], ["m_a", "m_y"]], alreadyClaimed: [])
        #expect(tie == [["m_a", "m_x"], ["m_y"]])
        // Photos another roster character already holds never re-anchor; duplicates collapse.
        let claimed = allocatedGoalCastReferenceMediaIds([["m_held", "m_new", "m_new"], ["m_held"]], alreadyClaimed: ["m_held"])
        #expect(claimed == [["m_new"], []])
        #expect(allocatedGoalCastReferenceMediaIds([], alreadyClaimed: ["x"]).isEmpty)
    }

    @Test("The articulation prompt forbids the same photo on two members")
    func promptRule() {
        let prompt = OpenAIClient.goalCastArticulationPrompt(context: GoalCastArticulationContext(
            projectId: "p", goalSummary: "A goal.", peoplePhotoLines: ["- media_id=m1 people=2"]
        ))
        #expect(prompt.contains("never the same media_id for two members"))
    }
}
