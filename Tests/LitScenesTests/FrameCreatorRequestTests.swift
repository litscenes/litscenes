import Foundation
import Testing
@testable import LitScenes

@Test func newTakeRequestWithoutMoodInfluencesKeyDecodes() throws {
    // A request blob persisted before the moodInfluences field existed.
    let json = """
    {
        "stack": "openai_base",
        "styleMode": "describe_style_in_prompt",
        "prompt": "A quiet harbor at dawn",
        "label": "",
        "debugParametersJSON": "",
        "styleOverrideCatalogVersion": ""
    }
    """
    let request = try JSONDecoder().decode(LensNewTakeRenderRequest.self, from: Data(json.utf8))
    #expect(request.stack.id == RenderStackID.openAIBase)
    #expect(request.moodInfluences == nil)
}

@Test func newTakeRequestMoodInfluencesRoundTrip() throws {
    var request = LensNewTakeRenderRequest(stack: RenderStackRegistry.shared.stack(id: RenderStackID.falFluxSchnell)!, prompt: "prompt")
    request.moodInfluences = [
        LensMoodInfluence(mediaId: "media_1", label: "dawn.jpg", line: "dawn.jpg: caption=a harbor | mood=calm"),
        LensMoodInfluence(mediaId: "media_2", label: "fog.jpg", line: "fog.jpg: caption=fog bank | mood=hushed")
    ]
    let data = try JSONEncoder().encode(request)
    let decoded = try JSONDecoder().decode(LensNewTakeRenderRequest.self, from: data)
    #expect(decoded.moodInfluences?.count == 2)
    #expect(decoded.moodInfluences?.first?.mediaId == "media_1")
    #expect(decoded.moodInfluences?.last?.line == "fog.jpg: caption=fog bank | mood=hushed")
}

@Test func newTakeRequestNormalizedTrimsCapsAndDropsEmptyMoodInfluences() {
    var request = LensNewTakeRenderRequest(stack: RenderStackRegistry.shared.stack(id: RenderStackID.openAIBase)!, prompt: "prompt")
    request.moodInfluences = [
        LensMoodInfluence(mediaId: " media_1 ", label: " a.jpg ", line: "  a.jpg: caption=one  "),
        LensMoodInfluence(mediaId: "media_2", label: "b.jpg", line: "   "),
        LensMoodInfluence(mediaId: "media_3", label: "c.jpg", line: "c.jpg: caption=three"),
        LensMoodInfluence(mediaId: "media_4", label: "d.jpg", line: "d.jpg: caption=four"),
        LensMoodInfluence(mediaId: "media_5", label: "e.jpg", line: "e.jpg: caption=five")
    ]
    let normalized = request.normalized()
    let influences = normalized.moodInfluences ?? []
    #expect(influences.count == LensNewTakeRenderRequest.maxMoodInfluences)
    #expect(influences[0].mediaId == "media_1")
    #expect(influences[0].line == "a.jpg: caption=one")
    // The empty-line entry drops before capping, so media_3/media_4 survive.
    #expect(influences.map(\.mediaId) == ["media_1", "media_3", "media_4"])
}

@Test func newTakeRequestNormalizedNilsEmptyMoodInfluences() {
    var request = LensNewTakeRenderRequest(stack: RenderStackRegistry.shared.stack(id: RenderStackID.openAIBase)!, prompt: "prompt")
    request.moodInfluences = [LensMoodInfluence(mediaId: "media_1", label: "a.jpg", line: "  ")]
    #expect(request.normalized().moodInfluences == nil)
    request.moodInfluences = nil
    #expect(request.normalized().moodInfluences == nil)
}

@Test func moodInfluenceLineJoinsRenderRelevantFields() {
    var observation = ImageObservationResult()
    observation.plainCaption = "A lighthouse over a cold sea"
    observation.mood = ["lonely", "resolute", "quiet", "extra"]
    observation.paletteTerms = ["slate blue", "bone white", "rust", "kelp green", "extra"]
    observation.setting = "Rocky headland at dusk"
    observation.lighting = "Low raking amber light"
    let line = moodInfluenceLine(filename: "lighthouse.jpg", observation: observation)
    #expect(line == "lighthouse.jpg: caption=A lighthouse over a cold sea | mood=lonely, resolute, quiet | palette=slate blue, bone white, rust, kelp green | setting=Rocky headland at dusk | lighting=Low raking amber light")
}

@Test func moodInfluenceLineTruncatesLongFieldsAndSkipsEmptyOnes() {
    var observation = ImageObservationResult()
    observation.plainCaption = String(repeating: "a", count: 200)
    observation.setting = String(repeating: "b", count: 120)
    let line = moodInfluenceLine(filename: "long.jpg", observation: observation)
    #expect(line.contains("caption=\(String(repeating: "a", count: 140))…"))
    #expect(line.contains("setting=\(String(repeating: "b", count: 90))…"))
    #expect(!line.contains("mood="))
    #expect(!line.contains("palette="))
    #expect(!line.contains("lighting="))
}

@Test func moodInfluenceLineEmptyObservationYieldsEmptyString() {
    let line = moodInfluenceLine(filename: "blank.jpg", observation: ImageObservationResult())
    #expect(line.isEmpty)
}

@Test func mediumPresetIsTolerantAndCarriesPromptBlocks() throws {
    // Unknown medium strings normalize to nil; valid ones survive.
    var request = LensNewTakeRenderRequest(stack: RenderStackRegistry.shared.stack(id: RenderStackID.openAIBase)!, prompt: "p")
    request.medium = "claymation"
    #expect(request.normalized().medium == nil)
    request.medium = " filmed "
    #expect(request.normalized().medium == "filmed")
    #expect(request.normalized().mediumPreset == .filmed)

    // Absent key decodes to nil (a request blob persisted before `medium` existed).
    let legacyJSON = """
    {
        "stack": "openai_base",
        "styleMode": "describe_style_in_prompt",
        "prompt": "A quiet harbor at dawn",
        "label": "",
        "debugParametersJSON": "",
        "styleOverrideCatalogVersion": ""
    }
    """
    let decoded = try JSONDecoder().decode(LensNewTakeRenderRequest.self, from: Data(legacyJSON.utf8))
    #expect(decoded.medium == nil)

    // Every preset carries real prompt language and a label.
    for preset in LensMediumPreset.allCases {
        #expect(!preset.promptBlock.trimmed.isEmpty)
        #expect(!preset.label.trimmed.isEmpty)
    }
    #expect(!lensSingleFrameGuard.isEmpty)
}

@Test func realisticPortraitStackIsCivitaiAndDistinct() throws {
    let stack = try #require(RenderStackRegistry.shared.stack(id: RenderStackID.realisticPortrait))
    #expect(stack.isCivitai)
    #expect(!stack.isFAL)
    #expect(!stack.canAttachStyleImage)
    #expect(stack.label == "Realistic Portrait")
    #expect(stack.stackId == "civitai.flux_klein_portrait.v0")
    #expect(stack.falBaseInput(prompt: "p", mediaPlan: LensMediaPlan(), styleMode: .describeStyleInPrompt).isEmpty == false || stack.falInput.isEmpty)
    #expect(stack.falDebugParameterKeys(styleMode: .describeStyleInPrompt).isEmpty)

    // The stack round-trips through a request as its id string.
    let request = LensNewTakeRenderRequest(stack: stack, prompt: "p")
    let decoded = try JSONDecoder().decode(LensNewTakeRenderRequest.self, from: JSONEncoder().encode(request))
    #expect(decoded.stack.id == RenderStackID.realisticPortrait)

    // An unknown stack id decodes to the safe openai fallback, never crashes.
    let unknownJSON = """
    {
        "stack": "stack_deleted_from_yaml",
        "styleMode": "describe_style_in_prompt",
        "prompt": "p",
        "label": "",
        "debugParametersJSON": "",
        "styleOverrideCatalogVersion": ""
    }
    """
    let fallback = try JSONDecoder().decode(LensNewTakeRenderRequest.self, from: Data(unknownJSON.utf8))
    #expect(fallback.stack.id == RenderStackID.openAIBase)
}

@Test func newTakeRequestWithoutAuthoredPromptKeyDecodes() throws {
    // A request blob persisted before the authoredPrompt field existed.
    let json = """
    {
        "stack": "openai_base",
        "styleMode": "describe_style_in_prompt",
        "prompt": "A quiet harbor at dawn",
        "label": "",
        "debugParametersJSON": "",
        "styleOverrideCatalogVersion": ""
    }
    """
    let request = try JSONDecoder().decode(LensNewTakeRenderRequest.self, from: Data(json.utf8))
    #expect(request.authoredPrompt == nil)
}

@Test func newTakeRequestAuthoredPromptNormalizesAndRoundTrips() throws {
    var request = LensNewTakeRenderRequest(stack: RenderStackRegistry.shared.stack(id: RenderStackID.openAIBase)!, prompt: "Elise waits")
    request.authoredPrompt = "  @Elise waits  "
    let normalized = request.normalized()
    #expect(normalized.authoredPrompt == "@Elise waits")
    let data = try JSONEncoder().encode(normalized)
    let decoded = try JSONDecoder().decode(LensNewTakeRenderRequest.self, from: data)
    #expect(decoded.authoredPrompt == "@Elise waits")
    request.authoredPrompt = "   "
    #expect(request.normalized().authoredPrompt == nil)
}

// MARK: - Attachment merge law (seed + direct + mention)

/// A one-slot FAL reframe stack decoded from YAML: the bundled FAL edit rows
/// now declare documented multi-image maxima, so single-slot behavior is
/// pinned against the mechanism, not a shipped row.
private let singleSlotTestStack = RenderStackRegistry.decodeStacks(
    yamlText: """
    stacks:
      - id: test_single_slot
        label: SingleSlot
        kind: fal
        model: vendor/single/edit
        reframe_capable: true
        fal:
          input:
            num_images: 1
    """,
    source: "test"
).first!

private func mergeTestAttachment(_ id: String, label: String) -> LensPromptImageAttachment {
    LensPromptImageAttachment(
        source: .moodboardImage,
        sourceId: id,
        label: label,
        detail: "detail for \(label)",
        imagePath: "/tmp/\(id).png"
    )
}

@Test func combinedAttachmentsPreserveSeedDirectMentionOrder() {
    let stack = RenderStackRegistry.shared.stack(id: RenderStackID.openAIBase)!
    let merge = frameCreatorCombinedAttachments(
        seed: mergeTestAttachment("seed", label: "Clip seed — IMG_1.MOV"),
        direct: [mergeTestAttachment("d1", label: "d1.jpg"), mergeTestAttachment("d2", label: "d2.jpg")],
        mention: [mergeTestAttachment("m1", label: "Kai")],
        stack: stack
    )
    #expect(merge.attachments.map(\.sourceId) == ["seed", "d1", "d2", "m1"])
    #expect(merge.notes.isEmpty)
}

@Test func combinedAttachmentsFALKeepsSeedOverDirectOverMention() {
    // Pins single-slot semantics against the mechanism: the bundled FAL edit
    // rows now declare documented multi-image maxima.
    let stack = singleSlotTestStack
    let merge = frameCreatorCombinedAttachments(
        seed: mergeTestAttachment("seed", label: "Clip seed — IMG_1.MOV"),
        direct: [mergeTestAttachment("d1", label: "d1.jpg")],
        mention: [mergeTestAttachment("m1", label: "Kai")],
        stack: stack
    )
    #expect(merge.attachments.map(\.sourceId) == ["seed"])
    #expect(merge.notes.count == 1)
    #expect(merge.notes[0].contains("Clip seed — IMG_1.MOV"))
    // The composite-sheet guidance is mention-specific; a seed winner drops it.
    #expect(!merge.notes[0].contains("composite sheets"))
}

@Test func combinedAttachmentsFALKeepsFirstDirectWithoutSeed() {
    let stack = singleSlotTestStack
    let merge = frameCreatorCombinedAttachments(
        seed: nil,
        direct: [mergeTestAttachment("d1", label: "d1.jpg"), mergeTestAttachment("d2", label: "d2.jpg")],
        mention: [mergeTestAttachment("m1", label: "Kai")],
        stack: stack
    )
    #expect(merge.attachments.map(\.sourceId) == ["d1"])
    #expect(merge.notes.count == 1)
    #expect(merge.notes[0].contains("d1.jpg"))
}

@Test func combinedAttachmentsFALMentionOnlyKeepsSheetGuidance() {
    let stack = singleSlotTestStack
    let merge = frameCreatorCombinedAttachments(
        seed: nil,
        direct: [],
        mention: [mergeTestAttachment("m1", label: "Kai"), mergeTestAttachment("m2", label: "Noa")],
        stack: stack
    )
    #expect(merge.attachments.map(\.sourceId) == ["m1"])
    #expect(merge.notes.count == 1)
    #expect(merge.notes[0].contains("composite sheets"))
}

@Test func combinedAttachmentsCapAtSixKeepsSeedThenDirectThenMention() {
    let stack = RenderStackRegistry.shared.stack(id: RenderStackID.openAIBase)!
    let merge = frameCreatorCombinedAttachments(
        seed: mergeTestAttachment("seed", label: "Clip seed"),
        direct: (1...4).map { mergeTestAttachment("d\($0)", label: "d\($0).jpg") },
        mention: (1...3).map { mergeTestAttachment("m\($0)", label: "Kai \($0)") },
        stack: stack
    )
    #expect(merge.attachments.map(\.sourceId) == ["seed", "d1", "d2", "d3", "d4", "m1"])
    #expect(merge.notes.count == 1)
    #expect(merge.notes[0].contains("first 6"))
}

@Test func combinedAttachmentsNonReframeStackDropsAll() {
    let stack = RenderStackRegistry.shared.stack(id: RenderStackID.wan)!
    #expect(!stack.reframeCapable)
    let withSeedAndDirect = frameCreatorCombinedAttachments(
        seed: mergeTestAttachment("seed", label: "Clip seed"),
        direct: [mergeTestAttachment("d1", label: "d1.jpg")],
        mention: [mergeTestAttachment("m1", label: "Kai")],
        stack: stack
    )
    #expect(withSeedAndDirect.attachments.isEmpty)
    #expect(withSeedAndDirect.notes.count == 1)
    // Mention-only carries no extra note here — the mention strip explains it.
    let mentionOnly = frameCreatorCombinedAttachments(
        seed: nil,
        direct: [],
        mention: [mergeTestAttachment("m1", label: "Kai")],
        stack: stack
    )
    #expect(mentionOnly.attachments.isEmpty)
    #expect(mentionOnly.notes.isEmpty)
}

@Test func combinedAttachmentsStabilityMultiImageAddsCompositeNote() {
    let stack = RenderStackRegistry.shared.stack(id: RenderStackID.stabilityUltra)!
    let merge = frameCreatorCombinedAttachments(
        seed: nil,
        direct: [mergeTestAttachment("d1", label: "d1.jpg"), mergeTestAttachment("d2", label: "d2.jpg")],
        mention: [],
        stack: stack
    )
    #expect(merge.attachments.count == 2)
    #expect(merge.notes.count == 1)
    #expect(merge.notes[0].contains("combined into one labeled sheet"))
}

@Test func attachmentPlanFatesMatchMergeSemantics() {
    let openai = RenderStackRegistry.shared.stack(id: RenderStackID.openAIBase)!
    let allRide = frameCreatorAttachmentPlan(
        seed: mergeTestAttachment("seed", label: "Clip seed"),
        direct: [mergeTestAttachment("d1", label: "d1.jpg")],
        mention: [mergeTestAttachment("m1", label: "Kai")],
        stack: openai
    )
    #expect(allRide.capacity == .budget)
    #expect(allRide.entries.map(\.fate) == [.rides, .rides, .rides])
    #expect(allRide.plannedCount == 3 && allRide.ridingCount == 3)
    #expect(allRide.fate(sourceId: "d1", stratum: .direct) == .rides)
    // Stratum-qualified lookups: the same id under another stratum is a miss.
    #expect(allRide.fate(sourceId: "d1", stratum: .mention) == nil)
    #expect(allRide.notes.isEmpty)

    let singleSlot = frameCreatorAttachmentPlan(
        seed: mergeTestAttachment("seed", label: "Clip seed — IMG_1.MOV"),
        direct: [mergeTestAttachment("d1", label: "d1.jpg")],
        mention: [mergeTestAttachment("m1", label: "Kai")],
        stack: singleSlotTestStack
    )
    #expect(singleSlot.capacity == .slots(1))
    #expect(singleSlot.entries.map(\.fate) == [
        .rides,
        .droppedOverSlotLimit(keptCount: 1, keptLabel: "Clip seed — IMG_1.MOV"),
        .droppedOverSlotLimit(keptCount: 1, keptLabel: "Clip seed — IMG_1.MOV")
    ])
    #expect(singleSlot.attachments.map(\.sourceId) == ["seed"])

    let stability = RenderStackRegistry.shared.stack(id: RenderStackID.stabilityUltra)!
    let sheet = frameCreatorAttachmentPlan(
        seed: nil,
        direct: [mergeTestAttachment("d1", label: "d1.jpg"), mergeTestAttachment("d2", label: "d2.jpg")],
        mention: [],
        stack: stability
    )
    #expect(sheet.capacity == .compositeSheet)
    #expect(sheet.entries.map(\.fate) == [.ridesInSheet, .ridesInSheet])
    // A lone Stability reference rides natively — no sheet, no note.
    let lone = frameCreatorAttachmentPlan(
        seed: nil,
        direct: [mergeTestAttachment("d1", label: "d1.jpg")],
        mention: [],
        stack: stability
    )
    #expect(lone.entries.map(\.fate) == [.rides])
    #expect(lone.notes.isEmpty)

    let overBudget = frameCreatorAttachmentPlan(
        seed: nil,
        direct: (1...7).map { mergeTestAttachment("d\($0)", label: "d\($0).jpg") },
        mention: [],
        stack: openai
    )
    #expect(overBudget.entries.map(\.fate).last == .droppedOverBudget)
    #expect(overBudget.ridingCount == 6)
    #expect(overBudget.notes.contains { $0.contains("first 6") })

    let wan = RenderStackRegistry.shared.stack(id: RenderStackID.wan)!
    let textOnly = frameCreatorAttachmentPlan(
        seed: mergeTestAttachment("seed", label: "Clip seed"),
        direct: [],
        mention: [mergeTestAttachment("m1", label: "Kai")],
        stack: wan
    )
    #expect(textOnly.capacity == .textOnly)
    #expect(textOnly.entries.map(\.fate) == [.droppedTextOnly, .droppedTextOnly])
    #expect(textOnly.attachments.isEmpty)
}

/// A declared multi-slot stack rides its first N references individually and
/// reports over-slot drops with count-aware copy; slots(1) keeps the
/// historical single-slot note verbatim.
@Test func multiSlotStacksRideDeclaredCountAndNoteHonestly() throws {
    let yaml = """
    stacks:
      - id: test_two_slot
        label: TwoSlot
        kind: fal
        model: vendor/two/edit
        reframe_capable: true
        prompt_image_limit: 2
        fal:
          input:
            num_images: 1
    """
    let twoSlot = try #require(RenderStackRegistry.decodeStacks(yamlText: yaml, source: "test").first)
    #expect(twoSlot.frameReferenceCapacity == .slots(2))
    let plan = frameCreatorAttachmentPlan(
        seed: mergeTestAttachment("seed", label: "Clip seed — IMG_1.MOV"),
        direct: [mergeTestAttachment("d1", label: "d1.jpg")],
        mention: [mergeTestAttachment("m1", label: "Kai")],
        stack: twoSlot
    )
    #expect(plan.entries.map(\.fate) == [
        .rides,
        .rides,
        .droppedOverSlotLimit(keptCount: 2, keptLabel: "Clip seed — IMG_1.MOV")
    ])
    #expect(plan.attachments.map(\.sourceId) == ["seed", "d1"])
    #expect(plan.notes == ["TwoSlot attaches up to 2 images — using the first 2."])

    // slots(1) keeps the historical single-slot copy byte-identical.
    let single = frameCreatorAttachmentPlan(
        seed: mergeTestAttachment("seed", label: "Clip seed — IMG_1.MOV"),
        direct: [mergeTestAttachment("d1", label: "d1.jpg")],
        mention: [],
        stack: singleSlotTestStack
    )
    #expect(single.notes == ["SingleSlot attaches one image — using Clip seed — IMG_1.MOV."])

    // Two riding references, none dropped: no over-slot note at all.
    let exact = frameCreatorAttachmentPlan(
        seed: nil,
        direct: [mergeTestAttachment("d1", label: "d1.jpg"), mergeTestAttachment("d2", label: "d2.jpg")],
        mention: [],
        stack: twoSlot
    )
    #expect(exact.entries.map(\.fate) == [.rides, .rides])
    #expect(exact.notes.isEmpty)

    // A declared limit ABOVE the shared budget (the raised bundled rows):
    // planning clamps at 6 and the note attributes the cut to the budget.
    // Overlay-free registry so the golden copy can't drift with a user yaml.
    let nano = RenderStackRegistry(includeUserOverlay: false).stack(id: RenderStackID.falNanoBanana2)!
    let overBudgetMulti = frameCreatorAttachmentPlan(
        seed: nil,
        direct: (1...7).map { mergeTestAttachment("d\($0)", label: "d\($0).jpg") },
        mention: [],
        stack: nano
    )
    #expect(overBudgetMulti.ridingCount == 6)
    #expect(overBudgetMulti.entries.map(\.fate).last == .droppedOverSlotLimit(keptCount: 6, keptLabel: "d1.jpg"))
    #expect(overBudgetMulti.notes == ["Attachment budget: using the first 6 reference images."])
}

@Test func directReferenceDescriptorStaysContentOnly() {
    let descriptor = mediaReferenceAttachmentDescriptor(filename: "IMG_4722.HEIC")
    #expect(descriptor.contains("IMG_4722.HEIC"))
    #expect(descriptor.localizedCaseInsensitiveContains("prompt remains the primary"))
    // Content/style separation doctrine: no style vocabulary in the manifest.
    #expect(!descriptor.localizedCaseInsensitiveContains("style"))
    #expect(!descriptor.localizedCaseInsensitiveContains("palette"))
}

@Test func promptEnrichmentDisabledDecodesTolerantt() throws {
    // Pre-field request blobs decode with the flag absent (nil = enabled):
    // a nil optional never encodes its key, so this round-trip IS the
    // legacy shape.
    let stack = RenderStackRegistry(includeUserOverlay: false).stack(id: RenderStackID.openAIBase)!
    let legacyData = try JSONEncoder().encode(LensNewTakeRenderRequest(stack: stack))
    #expect(!String(decoding: legacyData, as: UTF8.self).contains("promptEnrichmentDisabled"))
    let legacy = try JSONDecoder().decode(LensNewTakeRenderRequest.self, from: legacyData)
    #expect(legacy.promptEnrichmentDisabled == nil)

    // Round-trip keeps the hardline choice; normalized() passes it through.
    var request = legacy
    request.promptEnrichmentDisabled = true
    let decoded = try JSONDecoder().decode(
        LensNewTakeRenderRequest.self,
        from: JSONEncoder().encode(request.normalized())
    )
    #expect(decoded.promptEnrichmentDisabled == true)

    // Hero rows: absent decodes false; the persisted verbatim choice
    // round-trips (it governs retries/siblings/regenerates).
    let legacyRow = try JSONDecoder().decode(
        ProjectLensHeroImage.self,
        from: Data(#"{"imageId": "img_1"}"#.utf8)
    )
    #expect(!legacyRow.promptEnrichmentDisabled)
    var row = legacyRow
    row.promptEnrichmentDisabled = true
    let decodedRow = try JSONDecoder().decode(
        ProjectLensHeroImage.self,
        from: JSONEncoder().encode(row)
    )
    #expect(decodedRow.promptEnrichmentDisabled)
}

@Test func stabilityStrengthClampsAndRoundTrips() throws {
    let stack = RenderStackRegistry(includeUserOverlay: false).stack(id: RenderStackID.stabilityUltra)!
    var request = LensNewTakeRenderRequest(stack: stack)
    #expect(request.normalized().stabilityStrength == nil)

    request.stabilityStrength = 0.25
    let decoded = try JSONDecoder().decode(
        LensNewTakeRenderRequest.self,
        from: JSONEncoder().encode(request.normalized())
    )
    #expect(decoded.stabilityStrength == 0.25)

    // Out-of-range and non-finite values clamp or drop on normalize.
    request.stabilityStrength = 2.0
    #expect(request.normalized().stabilityStrength == 0.95)
    request.stabilityStrength = -1
    #expect(request.normalized().stabilityStrength == 0.05)
    request.stabilityStrength = .nan
    #expect(request.normalized().stabilityStrength == nil)

    // Hero rows carry the choice for retries.
    var row = try JSONDecoder().decode(
        ProjectLensHeroImage.self,
        from: Data(#"{"imageId": "img_1"}"#.utf8)
    )
    #expect(row.stabilityStrength == nil)
    row.stabilityStrength = 0.5
    let decodedRow = try JSONDecoder().decode(
        ProjectLensHeroImage.self,
        from: JSONEncoder().encode(row)
    )
    #expect(decodedRow.stabilityStrength == 0.5)
}
