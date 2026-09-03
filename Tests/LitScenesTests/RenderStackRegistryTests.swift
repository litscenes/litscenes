import Foundation
import Testing
@testable import LitScenes

/// Overlay-free registry so golden assertions never depend on this machine's
/// user render_stacks.yaml.
private let bundledRegistry = RenderStackRegistry(includeUserOverlay: false)

// MARK: Identity + capability parity with the retired LensTakeRenderStack enum

@Test func defaultStacksLoadInOrderWithExpectedIdentity() {
    let stacks = bundledRegistry.stacks()
    #expect(stacks.map(\.id) == [
        "openai_base",
        "stability_ultra",
        "civitai_wan_2_7",
        "civitai_realistic_portrait",
        "civitai_cinematic_juggernaut_xl",
        "civitai_realcartoon_xl",
        "civitai_zavychroma_xl",
        "civitai_animagine_xl",
        "fal_flux_schnell",
        "fal_flux_2_pro",
        "fal_nano_banana_2",
        "fal_reve_2_1",
        "fal_mai_image_2_5",
        "fal_seedream_v5_pro"
    ])
    #expect(stacks.map(\.stackId) == [
        "openai.base.v0",
        "stability.ultra.v0",
        "civitai.wan_image_27.v0",
        "civitai.flux_klein_portrait.v0",
        "civitai.juggernaut_xl_v9.cinematic.v0",
        "civitai.realcartoon_xl_v6.animated.v0",
        "civitai.zavychroma_xl_v7.editorial.v0",
        "civitai.animagine_xl_3_1.anime.v0",
        "fal.flux_schnell.v0",
        "fal.flux_2_pro.v0",
        "fal.nano_banana_2.v0",
        "fal.reve_2_1.v0",
        "fal.mai_image_2_5.v0",
        "fal.seedream_v5_pro.v0"
    ])
    #expect(stacks.map(\.label) == [
        "OpenAI Base", "Stability Ultra", "WAN 2.7", "Realistic Portrait",
        "Cinematic Realism", "Animated Cinematic", "Vivid Editorial", "Anime Story Frame",
        "FLUX Schnell", "FLUX 2 Pro", "Nano Banana 2",
        "Reve 2.1", "MAI Image 2.5", "Seedream 5 Pro"
    ])
    #expect(stacks.map(\.kind) == [.openai, .stability, .civitai, .civitai, .civitai, .civitai, .civitai, .civitai, .fal, .fal, .fal, .fal, .fal, .fal])
    #expect(stacks.map(\.credentialProvider) == [.openAI, .stability, .civitai, .civitai, .civitai, .civitai, .civitai, .civitai, .fal, .fal, .fal, .fal, .fal, .fal])
    #expect(stacks.map(\.model) == [
        "gpt-image-2",
        "stable-image-ultra",
        "wan.v2.7.text-to-image",
        "flux.2-klein.portrait-engine",
        "urn:air:sdxl:checkpoint:civitai:133005@348913",
        "urn:air:sdxl:checkpoint:civitai:125907@254091",
        "urn:air:sdxl:checkpoint:civitai:119229@490254",
        "urn:air:sdxl:checkpoint:civitai:260267@403131",
        "fal-ai/flux/schnell",
        "fal-ai/flux-2-pro",
        "fal-ai/nano-banana-2",
        "reve/2.1/text-to-image",
        "microsoft/mai-image-2.5",
        "bytedance/seedream/v5/pro/text-to-image"
    ])
    for stack in stacks {
        #expect(!stack.promptInstructions.isEmpty)
        #expect(!stack.detail.isEmpty)
    }
}

@Test func stackCapabilitiesMatchRetiredEnum() throws {
    func stack(_ id: String) throws -> RenderStack {
        try #require(bundledRegistry.stack(id: id))
    }
    let openai = try stack(RenderStackID.openAIBase)
    let stability = try stack(RenderStackID.stabilityUltra)
    let wan = try stack(RenderStackID.wan)
    let portrait = try stack(RenderStackID.realisticPortrait)
    let schnell = try stack(RenderStackID.falFluxSchnell)
    let flux2 = try stack(RenderStackID.falFlux2Pro)
    let nano = try stack(RenderStackID.falNanoBanana2)
    let reve = try stack(RenderStackID.falReve21)
    let mai = try stack(RenderStackID.falMAIImage25)
    let seedream = try stack(RenderStackID.falSeedreamV5Pro)

    #expect(!openai.isFAL && !stability.isFAL && !wan.isFAL && !portrait.isFAL)
    #expect(schnell.isFAL && flux2.isFAL && nano.isFAL)
    #expect(wan.isCivitai && portrait.isCivitai && !openai.isCivitai)
    #expect(stability.isStability && !openai.isStability)

    // canAttachStyleImage: only flux2 + nano; styleImageAttachSupported adds openai.
    #expect(!openai.canAttachStyleImage && openai.styleImageAttachSupported)
    #expect(stability.canAttachStyleImage && stability.styleImageAttachSupported)
    #expect(!wan.styleImageAttachSupported && !portrait.styleImageAttachSupported && !schnell.styleImageAttachSupported)
    #expect(flux2.canAttachStyleImage && nano.canAttachStyleImage)
    #expect(!reve.canAttachStyleImage && !mai.canAttachStyleImage && !seedream.canAttachStyleImage)

    // Reframe/prompt-image gate: openai + flux2 + nano only.
    #expect(openai.reframeCapable && stability.reframeCapable && flux2.reframeCapable && nano.reframeCapable)
    #expect(!wan.reframeCapable && !portrait.reframeCapable && !schnell.reframeCapable)
    #expect(!reve.reframeCapable && !mai.reframeCapable && !seedream.reframeCapable)

    // Prompt limits: fal 2400/2400/3500, civitai 1800, openai none.
    #expect(openai.promptLimit == nil)
    #expect(stability.promptLimit == 10_000)
    #expect(wan.promptLimit == 1_800 && portrait.promptLimit == 1_800)
    #expect(schnell.falPromptLimit == 2_400 && flux2.falPromptLimit == 2_400 && nano.falPromptLimit == 3_500)
    #expect(reve.falPromptLimit == 2_400 && mai.falPromptLimit == 2_400 && seedream.falPromptLimit == 2_400)

    // Output formats: png only for nano.
    #expect(nano.usesPNGOutput)
    #expect(!openai.usesPNGOutput && !stability.usesPNGOutput && !wan.usesPNGOutput && !portrait.usesPNGOutput && !schnell.usesPNGOutput && !flux2.usesPNGOutput)

    // falModelId incl. edit/redux variants; empty for non-FAL.
    #expect(schnell.falModelId(styleMode: .describeStyleInPrompt) == "fal-ai/flux/schnell")
    #expect(schnell.falModelId(styleMode: .attachStyleImage) == "fal-ai/flux/schnell/redux")
    #expect(flux2.falModelId(styleMode: .attachStyleImage) == "fal-ai/flux-2-pro/edit")
    #expect(nano.falModelId(styleMode: .attachStyleImage) == "fal-ai/nano-banana-2/edit")
    #expect(openai.falModelId(styleMode: .attachStyleImage).isEmpty)
    #expect(wan.falModelId(styleMode: .describeStyleInPrompt).isEmpty)
    #expect(flux2.reframePromptModel == "fal-ai/flux-2-pro/edit")
    #expect(openai.reframePromptModel == "gpt-image-2")

    // Enforced wide sizes.
    #expect(openai.imageSize == "1536x1024")
}

@Test func frameReferenceCapacityDerivesFromRegistry() throws {
    func capacity(_ id: String) throws -> FrameReferenceCapacity {
        try #require(bundledRegistry.stack(id: id)).frameReferenceCapacity
    }
    #expect(try capacity(RenderStackID.openAIBase) == .budget)
    #expect(try capacity(RenderStackID.stabilityUltra) == .compositeSheet)
    // Documented /edit maxima (FLUX 2 Pro 9, Nano Banana 2 14); planning
    // still clamps at the shared 6-image budget.
    #expect(try capacity(RenderStackID.falFlux2Pro) == .slots(9))
    #expect(try capacity(RenderStackID.falNanoBanana2) == .slots(14))
    #expect(try capacity(RenderStackID.falFlux2Pro).planningCap == FrameReferenceCapacity.attachmentBudget)
    #expect(try capacity(RenderStackID.falNanoBanana2).planningCap == FrameReferenceCapacity.attachmentBudget)
    // Non-reframe stacks are text-only regardless of provider slot counts.
    #expect(try capacity(RenderStackID.falFluxSchnell) == .textOnly)
    #expect(try capacity(RenderStackID.falReve21) == .textOnly)
    #expect(try capacity(RenderStackID.falMAIImage25) == .textOnly)
    #expect(try capacity(RenderStackID.falSeedreamV5Pro) == .textOnly)
    #expect(try capacity(RenderStackID.wan) == .textOnly)
    #expect(try capacity(RenderStackID.realisticPortrait) == .textOnly)
    #expect(try capacity("civitai_cinematic_juggernaut_xl") == .textOnly)
    #expect(try capacity("civitai_realcartoon_xl") == .textOnly)
    #expect(try capacity("civitai_zavychroma_xl") == .textOnly)
    #expect(try capacity("civitai_animagine_xl") == .textOnly)

    #expect(FrameReferenceCapacity.textOnly.planningCap == 0)
    #expect(FrameReferenceCapacity.slots(1).planningCap == 1)
    #expect(FrameReferenceCapacity.slots(4).planningCap == 4)
    // A declared limit above the shared budget still plans at the budget.
    #expect(FrameReferenceCapacity.slots(10).planningCap == FrameReferenceCapacity.attachmentBudget)
    #expect(FrameReferenceCapacity.compositeSheet.planningCap == FrameReferenceCapacity.attachmentBudget)
    #expect(FrameReferenceCapacity.budget.planningCap == FrameReferenceCapacity.attachmentBudget)
}

/// Pins EVERY bundled row's effective slot count: the declared-limit
/// mechanism must not move any stack unless its row deliberately raises
/// `prompt_image_limit` with the provider's documented maximum. The two
/// declared rows carry FAL's published numbers (FLUX 2 Pro edit: "up to 9
/// reference images (9 MP total input)"; Nano Banana 2 edit: "up to 14
/// reference images").
@Test func promptImageLimitDefaultsPreserveEveryBundledRow() throws {
    let expected: [(id: String, declared: Int?, effective: Int?)] = [
        (RenderStackID.openAIBase, nil, nil), // unbounded — app budget applies
        (RenderStackID.stabilityUltra, nil, 1),
        (RenderStackID.wan, nil, 0),
        (RenderStackID.realisticPortrait, nil, 0),
        ("civitai_cinematic_juggernaut_xl", nil, 0),
        ("civitai_realcartoon_xl", nil, 0),
        ("civitai_zavychroma_xl", nil, 0),
        ("civitai_animagine_xl", nil, 0),
        (RenderStackID.falFluxSchnell, nil, 1),
        (RenderStackID.falFlux2Pro, 9, 9),
        (RenderStackID.falNanoBanana2, 14, 14),
        (RenderStackID.falOutpaint, nil, 1),
        (RenderStackID.falReve21, nil, 1),
        (RenderStackID.falMAIImage25, nil, 1),
        (RenderStackID.falSeedreamV5Pro, nil, 1)
    ]
    for row in expected {
        let stack = try #require(bundledRegistry.stack(id: row.id), "missing bundled stack \(row.id)")
        #expect(stack.promptImageLimitOverride == row.declared, "declared limit — \(row.id)")
        #expect(stack.nativePromptImageLimit == row.effective, "effective limit — \(row.id)")
    }
}

/// The declared row override wins over the provider-kind default, clamps at
/// zero, and derives `.slots(n)` behind the unchanged reframe gate.
@Test func promptImageLimitDeclarationDecodesAndDerivesCapacity() throws {
    let yaml = """
    stacks:
      - id: test_multi
        label: Multi
        kind: fal
        model: vendor/multi/edit
        reframe_capable: true
        prompt_image_limit: 4
        fal:
          input:
            num_images: 1
      - id: test_negative
        label: Negative
        kind: fal
        model: vendor/neg
        reframe_capable: true
        prompt_image_limit: -2
        fal:
          input:
            num_images: 1
      - id: test_absent
        label: Absent
        kind: fal
        model: vendor/absent
        reframe_capable: true
        fal:
          input:
            num_images: 1
      - id: test_no_reframe
        label: NoReframe
        kind: fal
        model: vendor/text-only
        prompt_image_limit: 4
        fal:
          input:
            num_images: 1
    """
    let stacks = RenderStackRegistry.decodeStacks(yamlText: yaml, source: "test")
    let byId = Dictionary(uniqueKeysWithValues: stacks.map { ($0.id, $0) })
    let multi = try #require(byId["test_multi"])
    #expect(multi.nativePromptImageLimit == 4)
    #expect(multi.frameReferenceCapacity == .slots(4))
    #expect(multi.frameReferenceCapacity.planningCap == 4)
    let negative = try #require(byId["test_negative"])
    #expect(negative.nativePromptImageLimit == 0)
    #expect(negative.frameReferenceCapacity == .textOnly)
    let absent = try #require(byId["test_absent"])
    #expect(absent.promptImageLimitOverride == nil)
    #expect(absent.nativePromptImageLimit == 1) // fal kind default
    #expect(absent.frameReferenceCapacity == .slots(1))
    // The reframe gate stays the outer door: declared slots without a
    // reframe workflow still render from text alone.
    let noReframe = try #require(byId["test_no_reframe"])
    #expect(noReframe.nativePromptImageLimit == 4)
    #expect(noReframe.frameReferenceCapacity == .textOnly)
}

// MARK: FAL wire bodies — exact scalar types

@Test func falBaseInputsPreserveExactScalarTypes() throws {
    let plan = LensMediaPlan()
    let schnell = try #require(bundledRegistry.stack(id: RenderStackID.falFluxSchnell))
    let schnellInput = schnell.falBaseInput(prompt: "p", mediaPlan: plan, styleMode: .describeStyleInPrompt)
    #expect(schnellInput["prompt"] as? String == "p")
    #expect(schnellInput["num_inference_steps"] as? Int == 4)
    #expect(schnellInput["guidance_scale"] as? Double == 3.5)
    #expect(schnellInput["num_images"] as? Int == 1)
    #expect(schnellInput["enable_safety_checker"] as? Bool == true)
    #expect(schnellInput["image_size"] as? String == "landscape_16_9")
    #expect(schnellInput["output_format"] as? String == "jpeg")
    #expect(schnellInput["acceleration"] as? String == "none")

    let flux2 = try #require(bundledRegistry.stack(id: RenderStackID.falFlux2Pro))
    let flux2Input = flux2.falBaseInput(prompt: "p", mediaPlan: plan, styleMode: .attachStyleImage)
    // safety_tolerance must stay a STRING "2" (quoted in YAML) or the wire body changes.
    #expect(flux2Input["safety_tolerance"] as? String == "2")
    #expect(flux2Input["image_size"] as? String == "landscape_16_9")

    let nano = try #require(bundledRegistry.stack(id: RenderStackID.falNanoBanana2))
    let nanoInput = nano.falBaseInput(prompt: "p", mediaPlan: plan, styleMode: .describeStyleInPrompt)
    #expect(nanoInput["aspect_ratio"] as? String == "16:9")
    #expect(nanoInput["resolution"] as? String == "1K")
    #expect(nanoInput["safety_tolerance"] as? String == "4")
    #expect(nanoInput["limit_generations"] as? Bool == true)
    #expect(nanoInput["output_format"] as? String == "png")

    #expect(schnell.falDebugParameterKeys(styleMode: .describeStyleInPrompt) == [
        "num_inference_steps", "image_size", "seed", "guidance_scale", "num_images",
        "enable_safety_checker", "output_format", "acceleration"
    ])
    #expect(nano.falDebugParameterKeys(styleMode: .describeStyleInPrompt).contains("thinking_level"))

    let reve = try #require(bundledRegistry.stack(id: RenderStackID.falReve21))
    let reveInput = reve.falBaseInput(prompt: "p", mediaPlan: plan, styleMode: .describeStyleInPrompt)
    #expect(reveInput["aspect_ratio"] as? String == "16:9")
    #expect(reveInput["num_images"] as? Int == 1)
    #expect(reveInput["output_format"] as? String == "jpeg")

    let mai = try #require(bundledRegistry.stack(id: RenderStackID.falMAIImage25))
    let maiInput = mai.falBaseInput(prompt: "p", mediaPlan: plan, styleMode: .describeStyleInPrompt)
    #expect(maiInput["aspect_ratio"] as? String == "16:9")
    #expect(maiInput["num_images"] as? Int == 1)
    #expect(maiInput["output_format"] as? String == "jpeg")

    let seedream = try #require(bundledRegistry.stack(id: RenderStackID.falSeedreamV5Pro))
    let seedreamInput = seedream.falBaseInput(prompt: "p", mediaPlan: plan, styleMode: .describeStyleInPrompt)
    #expect(seedreamInput["image_size"] as? String == "landscape_16_9")
    #expect(seedreamInput["num_images"] as? Int == 1)
    #expect(seedreamInput["output_format"] as? String == "jpeg")
    #expect(seedreamInput["enable_safety_checker"] as? Bool == true)
}

// MARK: CivitAI wire bodies — one generic builder, both default workflows

@Test func civitaiPayloadsMatchWireBodies() throws {
    let wan = try #require(bundledRegistry.stack(id: RenderStackID.wan))
    let (wanPayload, wanSeed) = wan.civitaiPayload(prompt: "a harbor", requestSeed: 42, negativePrompt: "blurry")
    #expect(wanSeed == 42)
    #expect(wanPayload["tags"] as? [String] == ["litscenes", "lens", "wan-2-7", "image"])
    let wanSteps = try #require(wanPayload["steps"] as? [[String: Any]])
    #expect(wanSteps.count == 1)
    #expect(wanSteps[0]["$type"] as? String == "imageGen")
    #expect(wanSteps[0]["priority"] as? String == "low")
    let wanInput = try #require(wanSteps[0]["input"] as? [String: Any])
    #expect(wanInput["engine"] as? String == "wan")
    #expect(wanInput["version"] as? String == "v2.7")
    #expect(wanInput["sampler"] as? String == "WAN-2.7")
    #expect(wanInput["cfgScale"] as? Int == 0)
    #expect(wanInput["workflow"] as? String == "txt2img")
    #expect(wanInput["width"] as? Int == 1_280)
    #expect(wanInput["height"] as? Int == 720)
    #expect(wanInput["imageSize"] as? String == "landscape_16_9")
    #expect(wanInput["ecosystem"] as? String == "WanImage27")
    #expect(wanInput["quantity"] as? Int == 1)
    #expect(wanInput["seed"] as? Int == 42)
    #expect(wanInput["prompt"] as? String == "a harbor")
    #expect(wanInput["negativePrompt"] as? String == "blurry")
    #expect((wanInput["resources"] as? [Any])?.isEmpty == true)
    #expect(wanInput["enablePromptEnhancer"] as? Bool == false)
    #expect(wanInput["usePro"] as? Bool == false)

    // Random seed resolves when no request seed is provided.
    let (_, randomSeed) = wan.civitaiPayload(prompt: "p", requestSeed: nil, negativePrompt: "")
    #expect(randomSeed >= 1)

    let portrait = try #require(bundledRegistry.stack(id: RenderStackID.realisticPortrait))
    // Fixed seed wins even when a request seed is passed.
    let (portraitPayload, portraitSeed) = portrait.civitaiPayload(prompt: "a face", requestSeed: 42, negativePrompt: "")
    #expect(portraitSeed == 292_181_528)
    let portraitSteps = try #require(portraitPayload["steps"] as? [[String: Any]])
    // The flux2 step wrapper carries NO priority key.
    #expect(portraitSteps[0]["priority"] == nil)
    let portraitInput = try #require(portraitSteps[0]["input"] as? [String: Any])
    #expect(portraitInput["engine"] as? String == "flux2")
    #expect(portraitInput["model"] as? String == "klein")
    #expect(portraitInput["modelVersion"] as? String == "9b")
    #expect(portraitInput["steps"] as? Int == 8)
    #expect(portraitInput["cfgScale"] as? Int == 5)
    #expect(portraitInput["width"] as? Int == 1_280)
    #expect(portraitInput["height"] as? Int == 720)
    #expect(portraitInput["seed"] as? Int == 292_181_528)
    #expect(portraitInput["negativePrompt"] == nil)
    let loras = try #require(portraitInput["loras"] as? [String: Any])
    #expect(loras["urn:air:flux2:lora:civitai:2067704@2998669"] as? Double == 1.0)
}

// MARK: Persisted recipe snapshots per kind

@Test func renderRecipeSnapshotsMatchPerKind() throws {
    let openai = try #require(bundledRegistry.stack(id: RenderStackID.openAIBase))
    let base = openai.renderRecipeSnapshot(mediaPlan: LensMediaPlan(), styleMode: .describeStyleInPrompt)
    // openai keeps stackId nil so legacy render-version fingerprints don't shift.
    #expect(base.stackId == nil)
    #expect(base.provider == "openai")
    #expect(base.parameters.first { $0.key == "image_size" }?.value == "1536x1024")
    #expect(base.parameters.first { $0.key == "output_format" }?.value == "jpeg")
    #expect(base.capabilities == ["textToImage", "imageOutpaint"])
    let study = openai.renderRecipeSnapshot(
        mediaPlan: LensMediaPlan(),
        styleMode: .describeStyleInPrompt,
        isCharacterStudy: true,
        hasStyleReferences: true
    )
    #expect(study.parameters.first { $0.key == "output_format" }?.value == "png")
    #expect(study.capabilities == ["textToImage", "imageToImage", "styleVariant", "identityPreservation", "imageOutpaint"])

    let wan = try #require(bundledRegistry.stack(id: RenderStackID.wan))
    let wanRecipe = wan.renderRecipeSnapshot(mediaPlan: nil, styleMode: .describeStyleInPrompt, seed: 77)
    #expect(wanRecipe.stackId == "civitai.wan_image_27.v0")
    #expect(wanRecipe.parameters.first { $0.key == "seed" }?.value == "77")
    let wanRandom = wan.renderRecipeSnapshot(mediaPlan: nil, styleMode: .describeStyleInPrompt, seed: nil)
    #expect(wanRandom.parameters.first { $0.key == "seed" }?.value == "random")
    #expect(wanRecipe.parameters.first { $0.key == "enable_safety_checker" }?.valueType == "boolean")

    let portrait = try #require(bundledRegistry.stack(id: RenderStackID.realisticPortrait))
    let portraitRecipe = portrait.renderRecipeSnapshot(mediaPlan: nil, styleMode: .describeStyleInPrompt)
    #expect(portraitRecipe.parameters.first { $0.key == "seed" }?.value == "292181528")
    #expect(portraitRecipe.parameters.first { $0.key == "steps" }?.valueType == "number")

    let flux2 = try #require(bundledRegistry.stack(id: RenderStackID.falFlux2Pro))
    let falRecipe = flux2.renderRecipeSnapshot(
        mediaPlan: LensMediaPlan(),
        styleMode: .attachStyleImage,
        debugParametersJSON: #"{"seed": 5}"#
    )
    #expect(falRecipe.stackId == "fal.flux_2_pro.v0")
    #expect(falRecipe.model == "fal-ai/flux-2-pro/edit")
    #expect(falRecipe.capabilities == ["textToImage", "styleImageReference"])
    #expect(falRecipe.parameters.contains { $0.key == "debug_overrides_json" && $0.valueType == "json" })
    #expect(falRecipe.parameters.first { $0.key == "safety_tolerance" }?.valueType == "string")

    let reve = try #require(bundledRegistry.stack(id: RenderStackID.falReve21))
    let reveRecipe = reve.renderRecipeSnapshot(
        mediaPlan: LensMediaPlan(),
        styleMode: .describeStyleInPrompt
    )
    #expect(reveRecipe.model == "reve/2.1/text-to-image")
    #expect(reveRecipe.capabilities == ["textToImage"])
    #expect(reveRecipe.parameters.first { $0.key == "provider_price_note" }?.value == "$0.25 per image")
}

// MARK: Registry behaviors

@Test func defaultStackSeedChainMatches() {
    #expect(bundledRegistry.defaultStack(hasOpenAI: true, hasCivitai: true, hasFAL: true)?.id == RenderStackID.openAIBase)
    #expect(bundledRegistry.defaultStack(hasOpenAI: false, hasCivitai: true, hasFAL: true)?.id == RenderStackID.wan)
    #expect(bundledRegistry.defaultStack(hasOpenAI: false, hasCivitai: false, hasFAL: true) == nil)
    #expect(bundledRegistry.defaultStack(hasOpenAI: false, hasCivitai: false, hasFAL: false) == nil)
}

@Test func reframeStacksSubsetMatches() {
    #expect(bundledRegistry.reframeStacks().map(\.id) == [
        RenderStackID.openAIBase, RenderStackID.stabilityUltra, RenderStackID.falFlux2Pro, RenderStackID.falNanoBanana2,
        RenderStackID.falOutpaint
    ])
    // The zoom-out-only outpaint stack never appears for the other modes.
    #expect(!bundledRegistry.reframeStacks(mode: LensReframeSpec.zoomMode).map(\.id).contains(RenderStackID.falOutpaint))
    #expect(!bundledRegistry.reframeStacks(mode: LensReframeSpec.viewpointMode).map(\.id).contains(RenderStackID.falOutpaint))
    #expect(bundledRegistry.reframeStacks(mode: LensReframeSpec.zoomOutMode).map(\.id).contains(RenderStackID.falOutpaint))
}

@Test func userOverlayMergesByIdAndSkipsMalformedEntries() throws {
    let overlay = """
    version: "litscenes.render_stacks.v0"
    stacks:
      - id: fal_flux_schnell
        stack_id: fal.flux_schnell.v0
        label: FLUX Schnell (tuned)
        kind: fal
        credential_provider: fal
        order: 3
        model: fal-ai/flux/schnell
        prompt_limit: 900
        fal:
          input:
            num_inference_steps: 8
          debug_keys: [seed]
      - id: my_custom_civitai
        label: My Custom
        kind: civitai
        credential_provider: civitai
        civitai:
          seed: 7
          input:
            engine: flux2
            model: klein
            modelVersion: 9b
            operation: createImage
      - id: broken_entry
        kind: civitai
        label: Broken
        # no civitai.input → malformed, must be skipped
    """
    let base = RenderStackRegistry.decodeStacks(yamlText: try bundledYAMLText(), source: "test-bundled")
    let user = RenderStackRegistry.decodeStacks(yamlText: overlay, source: "test-user")
    #expect(user.count == 2)  // broken_entry skipped

    let merged = RenderStackRegistry.merged([base, user])
    #expect(merged.count == 16)
    let tuned = try #require(merged.first { $0.id == RenderStackID.falFluxSchnell })
    #expect(tuned.label == "FLUX Schnell (tuned)")
    #expect(tuned.falPromptLimit == 900)
    let custom = try #require(merged.first { $0.id == "my_custom_civitai" })
    #expect(custom.civitaiSeed == .fixed(7))
    #expect(custom.order == 1_000)          // no order → sorts after defaults
    #expect(merged.last?.id == "my_custom_civitai")
}

@Test func codableWireIsIdStringWithSafeFallback() throws {
    let stack = RenderStackRegistry.shared.stack(id: RenderStackID.falNanoBanana2) ?? RenderStackRegistry.shared.fallback
    let encoded = try JSONEncoder().encode(stack)
    #expect(String(data: encoded, encoding: .utf8) == "\"\(stack.id)\"")
    let decoded = try JSONDecoder().decode(RenderStack.self, from: encoded)
    #expect(decoded.id == stack.id)

    let unknown = try JSONDecoder().decode(RenderStack.self, from: Data("\"totally_unknown_stack\"".utf8))
    #expect(unknown.id == RenderStackID.openAIBase)
}

private func bundledYAMLText() throws -> String {
    let url = try packagedResourceURL(named: "render_stacks", extension: "yaml")
    return try String(contentsOf: url, encoding: .utf8)
}

// MARK: CivitAI sdcpp checkpoint stacks — the SDXL shape survives the generic builder

@Test func sdcppCheckpointStackDecodesAndBuildsWireBody() throws {
    let juggernaut = try #require(bundledRegistry.stack(id: "civitai_cinematic_juggernaut_xl"))
    #expect(juggernaut.isCivitai)
    #expect(!juggernaut.reframeCapable)
    #expect(!juggernaut.canAttachStyleImage)
    #expect(juggernaut.promptLimit == 1_800)
    #expect(juggernaut.civitaiSeed == .random)

    let (payload, seed) = juggernaut.civitaiPayload(prompt: "a rain-slick alley", requestSeed: 7, negativePrompt: "")
    #expect(seed == 7)
    #expect(payload["tags"] as? [String] == ["litscenes", "lens", "juggernaut-xl-v9", "cinematic", "image"])
    let steps = try #require(payload["steps"] as? [[String: Any]])
    #expect(steps[0]["priority"] as? String == "low")
    let input = try #require(steps[0]["input"] as? [String: Any])
    #expect(input["engine"] as? String == "sdcpp")
    #expect(input["ecosystem"] as? String == "sdxl")
    #expect(input["model"] as? String == "urn:air:sdxl:checkpoint:civitai:133005@348913")
    #expect(input["scheduler"] as? String == "DPM2Karras")
    #expect(input["steps"] as? Int == 35)
    #expect(input["cfgScale"] as? Int == 5)
    #expect(input["clipSkip"] as? Int == 1)
    #expect(input["width"] as? Int == 1_280)
    #expect(input["height"] as? Int == 720)
    #expect(input["prompt"] as? String == "a rain-slick alley")
    #expect(input["seed"] as? Int == 7)
    // Empty negatives never ride the wire.
    #expect(input["negativePrompt"] == nil)

    // The fractional CFG stack keeps its Double through the JSONScalar tree.
    let zavy = try #require(bundledRegistry.stack(id: "civitai_zavychroma_xl"))
    let (zavyPayload, _) = zavy.civitaiPayload(prompt: "p", requestSeed: 1, negativePrompt: "")
    let zavySteps = try #require(zavyPayload["steps"] as? [[String: Any]])
    let zavyInput = try #require(zavySteps[0]["input"] as? [String: Any])
    #expect(zavyInput["cfgScale"] as? Double == 6.5)
}
