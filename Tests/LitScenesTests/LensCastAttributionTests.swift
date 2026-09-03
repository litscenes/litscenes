import Foundation
import Testing
@testable import LitScenes

// Take → character attribution under implicit casting: stamped ids win, label names
// resolve, and unattributable takes are attributed to NO ONE — neither ordinal-indexed
// onto whoever happens to be cast[N] (the deleted fallback) nor surfaced in a residual
// group (removed by ratified decision: legacy-only data, displayed nowhere).

@MainActor
private func makeAttributionTestEngine() -> LibraryEngine {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("litscenes_cast_attribution_\(UUID().uuidString)", isDirectory: true)
    return LibraryEngine(projectLibrary: ProjectLibrary(root: root))
}

private func characterTake(
    imageId: String,
    routeKey: String,
    label: String,
    characterId: String = "",
    status: String = "ready"
) -> ProjectLensHeroImage {
    var take = ProjectLensHeroImage(imageId: imageId, status: status)
    take.sourceRouteKey = routeKey
    take.label = label
    take.characterId = characterId
    take.imageKind = LensImageTaxonomyKind.characterImage
    return take.normalized()
}

private func attributionLens(heroImages: [ProjectLensHeroImage]) -> ProjectLens {
    var body = LensBody()
    body.title = "Attribution Lens"
    body.castMembers = [
        LensCastMember(
            castId: "cast_bethany",
            name: "Bethany",
            descriptionPrompt: "a watchful archivist",
            characterId: "char_bethany"
        ).normalized()
    ]
    return ProjectLens(
        lensId: "lens_attribution_test",
        status: .ready,
        enabled: true,
        body: body,
        heroImage: nil,
        heroImages: heroImages,
        relationSummary: .empty,
        createdAt: DateFormats.now(),
        updatedAt: DateFormats.now()
    ).normalized()
}

@Test
@MainActor
func orphanCharacterTakeIsNotAttributed() {
    let engine = makeAttributionTestEngine()
    // Legacy take: no stamp, label names someone unknown, route key carries the
    // ordinal that used to misattribute it to cast[0] (Bethany).
    let orphan = characterTake(
        imageId: "img_orphan",
        routeKey: "lens_media_character_1@v1",
        label: "Character · Mara Vale"
    )
    let lens = attributionLens(heroImages: [orphan])
    let groups = engine.lensCharacterTakeGroups(lens: lens, versionId: "v1")
    // The orphan appears in NO group — not stapled onto Bethany, and no residual
    // group exists anymore.
    #expect(!groups.contains { group in group.takes.contains { $0.imageId == "img_orphan" } })
    #expect(!groups.contains { $0.characterId.isEmpty })
    let bethany = groups.first { $0.characterId == "char_bethany" }
    #expect(bethany?.takes.isEmpty ?? true)
}

@Test
@MainActor
func stampedAndLabelMatchedTakesStillResolve() {
    let engine = makeAttributionTestEngine()
    let stamped = characterTake(
        imageId: "img_stamped",
        routeKey: "lens_media_character_1@v1",
        label: "Character · Somebody Else",
        characterId: "char_bethany"
    )
    let labelMatched = characterTake(
        imageId: "img_label",
        routeKey: "lens_media_character_2@v1",
        label: "Character · Bethany"
    )
    let lens = attributionLens(heroImages: [stamped, labelMatched])
    let groups = engine.lensCharacterTakeGroups(lens: lens, versionId: "v1")
    let bethany = groups.first { $0.characterId == "char_bethany" }
    #expect(bethany?.takes.map(\.imageId).sorted() == ["img_label", "img_stamped"])
    #expect(!groups.contains { $0.characterId.isEmpty && !$0.takes.isEmpty })
}

@Test
@MainActor
func membershipFollowsNewestVersionWhileTakesFollowDisplayed() {
    let engine = makeAttributionTestEngine()
    // v1 has Bethany's take; v2 (newest) has none of hers — browsing v1 shows her
    // takes but she is no longer "in the scene".
    let v1Take = characterTake(
        imageId: "img_v1",
        routeKey: "lens_media_character_1@v1",
        label: "Character · Bethany",
        characterId: "char_bethany"
    )
    var v2Scenery = ProjectLensHeroImage(imageId: "img_v2_scene", status: "ready")
    v2Scenery.sourceRouteKey = "lens_media_scenery_1@v2"
    v2Scenery.label = "Coast road"
    let lens = attributionLens(heroImages: [v1Take, v2Scenery.normalized()])
    #expect(lens.mediaVersionIds == ["v1", "v2"])
    let groups = engine.lensCharacterTakeGroups(lens: lens, versionId: "v1")
    let bethany = groups.first { $0.characterId == "char_bethany" }
    #expect(bethany?.takes.map(\.imageId) == ["img_v1"])
    #expect(bethany?.membership == .notCast)
}

// Goal cast → roster auto-create: every cast member leaves this mapping roster-linked.

@Test
@MainActor
func goalCastMembersReuseOrCreateRosterEntries() {
    let engine = makeAttributionTestEngine()
    var draft = ProjectCharacterSetDocument(projectId: "proj_test")
    draft.characters = [
        ProjectCharacter(characterId: "char_mira", name: "Mira", updatedAt: DateFormats.now()).normalized()
    ]
    var mira = LensTrioCastMemberResponse()
    mira.name = "mira" // case-insensitive reuse
    mira.description = "a cartographer"
    var kellan = LensTrioCastMemberResponse()
    kellan.name = "Kellan"
    kellan.description = "a tidewatcher"
    let now = DateFormats.now()

    let members = engine.lensCastMembersFromComposition([mira, kellan], rosterDraft: &draft, now: now)
    #expect(members?.count == 2)
    #expect(members?[0].characterId == "char_mira")
    // Kellan was created in the draft and the member links to it.
    #expect(draft.characters.count == 2)
    let created = draft.characters.first { $0.name == "Kellan" }
    #expect(created != nil)
    #expect(created?.descriptionPrompt == "a tidewatcher")
    #expect(members?[1].characterId == created?.characterId)

    // A second slice naming Kellan reuses the same draft entry — no duplicate.
    var kellanAgain = LensTrioCastMemberResponse()
    kellanAgain.name = "KELLAN"
    let secondSlice = engine.lensCastMembersFromComposition([kellanAgain], rosterDraft: &draft, now: now)
    #expect(draft.characters.count == 2)
    #expect(secondSlice?[0].characterId == created?.characterId)
}
