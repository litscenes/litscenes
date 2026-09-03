import Foundation
import Testing
@testable import LitScenes

private func blendReference(_ itemId: String, title: String = "", mimeType: String = "image/png") -> SREFStyleImageReference {
    SREFStyleImageReference(
        catalogKind: "style_browse_catalog",
        catalogVersion: "v-test",
        itemId: itemId,
        title: title.isEmpty ? "Style \(itemId)" : title,
        srefCode: "sref-\(itemId)",
        sourceKey: "sref-\(itemId)",
        variantName: "generated_1024",
        url: "https://example.cloudfront.net/\(itemId).png",
        sha256: String(repeating: "a", count: 60) + String(format: "%04d", abs(itemId.hashValue % 10000)),
        width: 1024,
        height: 1024,
        byteSize: 1000,
        mimeType: mimeType
    )
}

private func blendIngredient(_ reference: SREFStyleImageReference, order: Int) -> LensStyleIngredient {
    LensStyleIngredient(
        ingredientId: "ingredient_\(reference.itemId)",
        order: order,
        title: reference.title,
        role: "style_reference",
        narrativeUse: "",
        presentationUse: "",
        notes: "",
        sourceReferenceIds: [reference.sourceReferenceId]
    )
}

private func blendSlot(_ styleId: String, weight: Int) -> LensStyleTreatmentSlot {
    LensStyleTreatmentSlot(styleId: styleId, label: "Style \(styleId)", weight: weight)
}

private func blendTreatment(primary: (String, Int), accents: [(String, Int)]) -> LensStyleTreatment {
    LensStyleTreatment(
        catalogVersion: "v-test",
        primary: blendSlot(primary.0, weight: primary.1),
        accents: accents.map { blendSlot($0.0, weight: $0.1) }
    )
}

private func browseCatalog(
    styles: [(id: String, sha: String)],
    caption: String = "",
    oneLineStyleSummary: String? = nil
) -> StyleBrowseCatalog {
    StyleBrowseCatalog(
        schemaVersion: "litscenes.style_browse_catalog.v0.1",
        catalogKind: "style_browse_catalog",
        version: "v-cat",
        taxonomyVersion: "t1",
        categorizationModel: "",
        styleCount: styles.count,
        collections: [StyleBrowseCollection(key: "nocturne", name: "Nocturne", description: "", dotColorHex: "#123456", sortOrder: 1)],
        styles: styles.map { entry in
            StyleBrowseStyle(
                id: entry.id,
                title: "Style \(entry.id)",
                label: "Style \(entry.id)",
                caption: caption,
                oneLineStyleSummary: oneLineStyleSummary,
                url: "https://example.cloudfront.net/\(entry.id).png",
                sha256: entry.sha,
                width: 1024,
                height: 1024,
                collection: "nocturne",
                secondaryCollection: nil,
                moods: [],
                hueName: "Blue",
                hueHex: "#3457a8",
                medium: "Digital painting",
                sat: 3, con: 2, ser: 2, lin: 1, sty: 2,
                srefCode: "sref-\(entry.id)",
                page: 1,
                cardIndex: 1
            )
        }
    )
}

@Test
func blendSharesUseLargestRemainderAndSumToOneHundred() {
    let treatment = blendTreatment(primary: ("a", 33), accents: [("b", 33), ("c", 33)])
    let shares = treatment.blendShares()
    #expect(shares.reduce(0, +) == 100)
    #expect(shares.allSatisfy { $0 == 33 || $0 == 34 })
}

@Test
func blendSharesAlwaysSumToOneHundredAcrossRandomWeights() {
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<250 {
        let slotCount = Int.random(in: 1...3, using: &generator)
        var slots: [(String, Int)] = []
        for index in 0..<slotCount {
            slots.append(("s\(index)", Int.random(in: 5...90, using: &generator)))
        }
        let treatment = blendTreatment(primary: slots[0], accents: Array(slots.dropFirst()))
        let shares = treatment.blendShares()
        #expect(shares.count == slotCount)
        #expect(shares.reduce(0, +) == 100)
    }
}

@Test
func treatmentWeightSummaryStaysCompactPercentages() {
    let treatment = blendTreatment(primary: ("a", 60), accents: [("b", 25), ("c", 15)])
    #expect(treatment.weightSummary == "60 · 25 · 15")
}

@Test
func attachmentPlanAttachesExactlyOneStyleThenContinuity() {
    let refs = ["a", "b", "c"].map { blendReference($0) }
    let ingredients = refs.enumerated().map { blendIngredient($0.element, order: $0.offset + 1) }
    let treatment = blendTreatment(primary: ("a", 60), accents: [("b", 15), ("c", 25)])
    let continuity = [URL(fileURLWithPath: "/tmp/prior-1.jpg")]

    // No assignment → the primary is the single style.
    let plan = LensBlendAttachmentPlan.make(
        treatment: treatment,
        ingredients: ingredients,
        continuityURLs: continuity
    )
    #expect(plan.entries.count == 2)
    #expect(plan.entries[0].role == .primary)
    #expect(plan.entries[0].reference?.itemId == "a")
    #expect(plan.entries[0].attachmentFilename == "style-ref.png")
    #expect(plan.entries[1].role == .continuity)
    #expect(plan.entries[1].attachmentFilename == "continuity-1-rendered-world.jpg")
    #expect(plan.warnings.isEmpty)
    #expect(plan.promptPreamble == "In the style of the first attached image, generate the following:")

    // An assigned accent becomes the single style for that frame.
    let accentPlan = LensBlendAttachmentPlan.make(
        treatment: treatment,
        ingredients: ingredients,
        assignedStyleId: "c"
    )
    #expect(accentPlan.entries.count == 1)
    #expect(accentPlan.entries[0].role == .accent)
    #expect(accentPlan.entries[0].reference?.itemId == "c")
    #expect(accentPlan.entries[0].sharePercent == 25)
    #expect(accentPlan.promptPreamble == "In the style of the attached image, generate the following:")

    // A stale assignment falls back to the primary with a warning.
    let stalePlan = LensBlendAttachmentPlan.make(
        treatment: treatment,
        ingredients: ingredients,
        assignedStyleId: "ghost"
    )
    #expect(stalePlan.entries.first?.reference?.itemId == "a")
    #expect(stalePlan.warnings.count == 1)
}

@Test
func attachmentPlanCarriesStyleSummaryAndSplitsManifest() {
    let sha = String(repeating: "a", count: 64)
    let refs = ["a"].map { blendReference($0) }
    let ingredients = refs.enumerated().map { blendIngredient($0.element, order: $0.offset + 1) }
    let treatment = blendTreatment(primary: ("a", 60), accents: [])
    let summary = "Sunbaked gouache seaside noir with chalky texture and bleached light."

    let plan = LensBlendAttachmentPlan.make(
        treatment: treatment,
        ingredients: ingredients,
        catalog: browseCatalog(styles: [(id: "a", sha: sha)], oneLineStyleSummary: summary),
        continuityURLs: [URL(fileURLWithPath: "/tmp/prior-1.jpg")]
    )
    #expect(plan.styleSummaryText == summary)
    // The split reassembles into exactly the legacy manifest: dynamic entry lines stay
    // per-job, the static style-only policy is separable for the system prompt.
    #expect(plan.manifestText == (plan.manifestEntryLines() + [plan.manifestPolicyText]).joined(separator: "\n"))
    #expect(!plan.manifestPolicyText.isEmpty)
    #expect(plan.manifestEntryLinesText.contains("continuity-1-rendered-world.jpg"))
    #expect(!plan.manifestEntryLinesText.contains("Match the style image"))

    // Older catalogs without the summary field fall back to the browse caption.
    let fallbackPlan = LensBlendAttachmentPlan.make(
        treatment: treatment,
        ingredients: ingredients,
        catalog: browseCatalog(styles: [(id: "a", sha: sha)], caption: "Chalky seaside gouache.")
    )
    #expect(fallbackPlan.styleSummaryText == "Chalky seaside gouache.")

    // No catalog → no summary line; the plan still builds normally.
    let bare = LensBlendAttachmentPlan.make(treatment: treatment, ingredients: ingredients)
    #expect(bare.styleSummaryText.isEmpty)
    #expect(!bare.entries.isEmpty)
}

@Test
func styleFrameAssignmentsAllocateFramesByWeight() {
    let treatment = blendTreatment(primary: ("a", 60), accents: [("b", 25), ("c", 15)])

    // Five frames: every style represented, remainder to the primary, primary leads.
    let five = treatment.styleFrameAssignments(frameCount: 5)
    #expect(five.count == 5)
    #expect(five[0] == 0)
    #expect(five.filter { $0 == 0 }.count == 3)
    #expect(five.filter { $0 == 1 }.count == 1)
    #expect(five.filter { $0 == 2 }.count == 1)

    // Three frames: minimum representation — every style appears once.
    let three = treatment.styleFrameAssignments(frameCount: 3)
    #expect(Set(three) == [0, 1, 2])
    #expect(three[0] == 0)

    // Two frames: largest remainder favors the strongest accent over a second primary.
    let two = treatment.styleFrameAssignments(frameCount: 2)
    #expect(two.filter { $0 == 0 }.count == 1)
    #expect(two.filter { $0 == 1 }.count == 1)

    // One frame: the primary.
    #expect(treatment.styleFrameAssignments(frameCount: 1) == [0])

    // Dominant single style keeps every frame.
    let solo = blendTreatment(primary: ("a", 100), accents: [])
    #expect(solo.styleFrameAssignments(frameCount: 4) == [0, 0, 0, 0])
}

@Test
func attachmentPlanResolvesStaleIngredientsThroughCatalog() {
    // Ingredients only know style "old"; the treatment was edited to styles "a" and "new".
    let staleIngredients = [blendIngredient(blendReference("old"), order: 1)]
    let treatment = blendTreatment(primary: ("a", 70), accents: [("new", 30)])
    let catalog = browseCatalog(styles: [
        (id: "a", sha: String(repeating: "b", count: 64)),
        (id: "new", sha: String(repeating: "c", count: 64))
    ])

    let plan = LensBlendAttachmentPlan.make(
        treatment: treatment,
        ingredients: staleIngredients,
        catalog: catalog
    )

    #expect(plan.entries.count == 1)
    #expect(plan.entries[0].reference?.itemId == "a")
    #expect(plan.warnings.isEmpty)

    // The assigned accent also resolves through the catalog despite stale ingredients.
    let accentPlan = LensBlendAttachmentPlan.make(
        treatment: treatment,
        ingredients: staleIngredients,
        catalog: catalog,
        assignedStyleId: "new"
    )
    #expect(accentPlan.entries.count == 1)
    #expect(accentPlan.entries[0].reference?.itemId == "new")
    #expect(accentPlan.warnings.isEmpty)
}

@Test
func attachmentPlanWarnsWhenAssignedStyleHasNoReference() {
    let treatment = blendTreatment(primary: ("a", 70), accents: [("ghost", 30)])
    let ingredients = [blendIngredient(blendReference("a"), order: 1)]

    // The primary resolves cleanly and keeps its true share.
    let plan = LensBlendAttachmentPlan.make(treatment: treatment, ingredients: ingredients)
    #expect(plan.entries.count == 1)
    #expect(plan.entries[0].reference?.itemId == "a")
    #expect(plan.entries[0].sharePercent == 70)
    #expect(plan.warnings.isEmpty)

    // A frame assigned to an unresolvable style renders prompt-only, with a warning.
    let ghostPlan = LensBlendAttachmentPlan.make(
        treatment: treatment,
        ingredients: ingredients,
        assignedStyleId: "ghost"
    )
    #expect(ghostPlan.styleEntries.isEmpty)
    #expect(ghostPlan.promptPreamble.isEmpty)
    #expect(ghostPlan.warnings.count == 1)
}

@Test
func invertedWeightsAllocateMostFramesToTheHeaviestAccent() {
    // The 5/5/90 case: an accent outweighs the primary, so it earns the most frames —
    // and rolesAreWeightConsistent still flags the inversion for the UI.
    let treatment = blendTreatment(primary: ("a", 5), accents: [("b", 5), ("c", 90)])
    #expect(treatment.rolesAreWeightConsistent == false)

    let assignments = treatment.styleFrameAssignments(frameCount: 5)
    #expect(assignments.filter { $0 == 2 }.count == 3)
    #expect(assignments.filter { $0 == 0 }.count == 1)
    #expect(assignments.filter { $0 == 1 }.count == 1)
}

@Test
func manifestGoldenTextForCanonicalBlendWithCharacterAndContinuity() {
    let refs = ["a", "b", "c"].map { blendReference($0) }
    let ingredients = refs.enumerated().map { blendIngredient($0.element, order: $0.offset + 1) }
    let treatment = blendTreatment(primary: ("a", 60), accents: [("b", 25), ("c", 15)])

    let plan = LensBlendAttachmentPlan.make(
        treatment: treatment,
        ingredients: ingredients,
        characterReferences: [.init(name: "Kai", urls: [URL(fileURLWithPath: "/tmp/kai.png")])],
        continuityURLs: [URL(fileURLWithPath: "/tmp/prior.jpg")]
    )

    // The style is attachment 1, covered by the preamble; the manifest numbers the
    // remaining attachments by their true positions.
    #expect(plan.promptPreamble == "In the style of the first attached image, generate the following:")
    let expected = """
    Additional attached images, after the style image, in this exact order:
    2. character-ref-kai-1.png — CHARACTER reference for "Kai": this exact figure appears in the scene; match their appearance, build, and distinguishing features from this image. It is subject matter, not a style reference — render "Kai" in this treatment's style.
    3. continuity-1-rendered-world.jpg — this same world already rendered: keep its geography, recurring subjects, and staging consistent; this image depicts a different scene. Take NO palette, lighting character, or rendering from it — the style image alone governs rendering.
    Match the style image's rendering technique, palette behavior, surface texture, and lighting character exactly. Never copy its subject matter, its composition, or any internal panel borders it contains.
    """
    #expect(plan.manifestText == expected)
}

@Test
func characterReferenceLabelsRideTheManifestDescriptor() {
    let plan = LensBlendAttachmentPlan.make(
        treatment: nil,
        ingredients: [],
        characterReferences: [
            .init(
                name: "Ava",
                urls: [URL(fileURLWithPath: "/tmp/ava-1.png"), URL(fileURLWithPath: "/tmp/ava-2.png")],
                labels: ["young Ava", ""]
            )
        ]
    )
    #expect(plan.entries.count == 2)
    #expect(plan.entries[0].promptDescriptor.hasSuffix("This particular reference shows: young Ava."))
    // Unlabeled references keep the untouched descriptor.
    #expect(!plan.entries[1].promptDescriptor.contains("This particular reference shows"))
    #expect(plan.entries[1].promptDescriptor.hasSuffix("render \"Ava\" in this treatment's style."))
}

@Test
func characterNamesSlugAndCollisionsDisambiguate() {
    let plan = LensBlendAttachmentPlan.make(
        treatment: nil,
        ingredients: [],
        characterReferences: [
            .init(name: "Kai Aloha", urls: [URL(fileURLWithPath: "/tmp/1.png")]),
            .init(name: "Kai-Aloha!", urls: [URL(fileURLWithPath: "/tmp/2.png")])
        ]
    )
    #expect(plan.entries.count == 2)
    #expect(plan.entries[0].attachmentFilename == "character-ref-kai-aloha-1.png")
    #expect(plan.entries[1].attachmentFilename == "character-ref-kai-aloha-2-1.png")
}

@Test
func treatmentlessLensFallsBackToItsFirstReferenceAsTheSingleStyle() {
    let refs = ["x", "y"].map { blendReference($0) }
    let ingredients = refs.enumerated().map { blendIngredient($0.element, order: $0.offset + 1) }

    let plan = LensBlendAttachmentPlan.make(treatment: nil, ingredients: ingredients)

    #expect(plan.entries.count == 1)
    #expect(plan.entries[0].attachmentFilename == "style-ref.png")
    #expect(plan.entries[0].reference?.itemId == "x")
    #expect(plan.promptPreamble == "In the style of the attached image, generate the following:")
    #expect(!plan.manifestText.contains("%"))
}

@Test
func attachmentCapDropsContinuityFirstWithWarnings() {
    let refs = ["a", "b", "c"].map { blendReference($0) }
    let ingredients = refs.enumerated().map { blendIngredient($0.element, order: $0.offset + 1) }
    let treatment = blendTreatment(primary: ("a", 60), accents: [("b", 25), ("c", 15)])
    let characters = (0..<3).map { index in
        LensBlendAttachmentPlan.CharacterReferenceInput(
            name: "Crew \(index)",
            urls: [URL(fileURLWithPath: "/tmp/c\(index)-1.png"), URL(fileURLWithPath: "/tmp/c\(index)-2.png")]
        )
    }
    let continuity = (0..<4).map { URL(fileURLWithPath: "/tmp/prior-\($0).jpg") }

    // 1 style + 6 character refs + 4 continuity = 11 > cap of 10.
    let plan = LensBlendAttachmentPlan.make(
        treatment: treatment,
        ingredients: ingredients,
        characterReferences: characters,
        continuityURLs: continuity
    )

    #expect(plan.entries.count == LensBlendAttachmentPlan.maxAttachments)
    #expect(plan.entries.filter { $0.role == .continuity }.count == 3)
    #expect(plan.entries.filter { $0.role == .characterReference }.count == 6)
    #expect(plan.warnings.count == 1)
    // The single style always survives.
    #expect(plan.entries.filter(\.isStyle).count == 1)
}
