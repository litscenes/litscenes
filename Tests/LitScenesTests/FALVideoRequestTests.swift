import Foundation
import Testing
@testable import LitScenes

// FAL request-shape laws. These exist because the alternative way to learn
// them is a rejected paid render.

/// WAN 2.7 rejected every clip with "Input should be 2, 3, 4, … or 15" — a
/// message that reads like a range error while the value (6) was always in
/// range. It was a TYPE error: the shot payload spelled duration as a string
/// for all three endpoints, and WAN declares an integer.
@Test func falEndpointsDeclareHowTheySpellDuration() {
    #expect(VideoModelSelection.falWan27ImageToVideo.falDurationEncoding == .integerSeconds)
    #expect(VideoModelSelection.falKlingV3ProImageToVideo.falDurationEncoding == .stringSeconds)
    #expect(VideoModelSelection.falSeedance20ImageToVideo.falDurationEncoding == .stringSeconds)
    // Non-FAL and local selections send no FAL duration at all.
    #expect(VideoModelSelection.auto.falDurationEncoding == nil)
    #expect(VideoModelSelection.attachedClips.falDurationEncoding == nil)
    #expect(VideoModelSelection.civitaiWanV27.falDurationEncoding == nil)
}

@Test func durationEncodingProducesTheProviderJSONType() throws {
    // WAN: a JSON number. A string here is what FAL refused.
    let wan = FALDurationEncoding.integerSeconds.payloadValue(seconds: 6)
    #expect(wan as? Int == 6)
    #expect(wan as? String == nil)

    // Kling/Seedance: a JSON string enum member.
    let kling = FALDurationEncoding.stringSeconds.payloadValue(seconds: 6)
    #expect(kling as? String == "6")
    #expect(kling as? Int == nil)

    // Both survive JSONSerialization as the type they claim, which is the
    // only thing the provider actually sees.
    for (encoding, expectsNumber) in [
        (FALDurationEncoding.integerSeconds, true),
        (FALDurationEncoding.stringSeconds, false)
    ] {
        let payload: [String: Any] = ["duration": encoding.payloadValue(seconds: 5)]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text == (expectsNumber ? "{\"duration\":5}" : "{\"duration\":\"5\"}"))
    }
}

/// Every WAN duration the UI offers has to be inside the endpoint's own range,
/// or the app spends a submit to learn what it already knew.
@Test func wanDurationsOfferedAreInsideTheEndpointRange() {
    let wanRange = 2...15
    for seconds in ShotRenderModel.wan27.supportedDurations {
        #expect(wanRange.contains(seconds))
    }
}

/// The Hailuo 3 laws: integer duration spelling, offered durations inside
/// the endpoint's 5–15s range, the exact FAL slugs, no "_audio" stack
/// variant (the audio is always in the file with no flag), and the
/// user-choice resolution vocabulary with its 768P default.
@Test func hailuo3StacksDeclareTheirRequestShape() {
    for selection in [VideoModelSelection.falHailuo3ImageToVideo, .falHailuo3MaxImageToVideo] {
        #expect(selection.falDurationEncoding == .integerSeconds)
        // Resolution is the USER PREFERENCE, threaded at request time — a
        // fixed tier here would let request and estimate disagree.
        #expect(selection.falResolutionTier == nil)
    }
    #expect(VideoModelSelection.falHailuo3ImageToVideo.providerModelId == "minimax/h3/image-to-video")
    #expect(VideoModelSelection.falHailuo3MaxImageToVideo.providerModelId == "minimax/h3-max/image-to-video")

    let endpointRange = 5...15
    for model in [ShotRenderModel.falHailuo3, .falHailuo3Max] {
        #expect(model.supportedDurations == [5, 10, 15])
        for seconds in model.supportedDurations {
            #expect(endpointRange.contains(seconds))
        }
        #expect(model.providerSelection == .falImageToVideo)
        #expect(!model.supportsGeneratedAudio)
    }

    // Stack raw values round-trip; the audio suffix is unrepresentable.
    let stack = ShotRenderStack.fallback.replacingModel(.falHailuo3).replacingDuration(10)
    #expect(stack.rawValue == "fal_hailuo_3_10s")
    #expect(ShotRenderStack(rawValue: "fal_hailuo_3_10s") == stack)
    #expect(ShotRenderStack(rawValue: "fal_hailuo_3_10s_audio") == nil)
    #expect(ShotRenderStack(rawValue: "fal_hailuo_3_max_5s") != nil)

    // Both pair shapes route to the model; tail-only stays an honest nil.
    #expect(stack.pairedModelSelection == .falHailuo3ImageToVideo)
    #expect(stack.openEndedModelSelection == .falHailuo3ImageToVideo)
    #expect(stack.tailAnchoredModelSelection == nil)

    // The resolution preference law: per-model vocabularies, 768P default,
    // and an out-of-vocabulary write is refused.
    #expect(Hailuo3ResolutionPreference.choices(for: .falHailuo3) == ["768P", "2K"])
    #expect(Hailuo3ResolutionPreference.choices(for: .falHailuo3Max) == ["480P", "768P"])
    #expect(Hailuo3ResolutionPreference.choices(for: .wan27).isEmpty)
    Hailuo3ResolutionPreference.setResolution("4K", for: .falHailuo3)
    #expect(Hailuo3ResolutionPreference.resolution(for: .falHailuo3) != "4K")
    Hailuo3ResolutionPreference.setResolution("2K", for: .falHailuo3)
    #expect(Hailuo3ResolutionPreference.resolution(for: .falHailuo3) == "2K")
    Hailuo3ResolutionPreference.setResolution("768P", for: .falHailuo3)
    #expect(Hailuo3ResolutionPreference.resolution(for: .falHailuo3) == "768P")
}

@Test func ltxNarrationRouteUsesTheExecutableFALModelAndExactSeconds() {
    let stack = ShotRenderStack.fallback.replacingModel(.falLTX23Narration)
    #expect(stack.rawValue == "fal_ltx_2_3_audio_to_video")
    #expect(ShotRenderStack(rawValue: stack.rawValue) == stack)
    #expect(stack.providerSelection == .falAudioToVideo)
    #expect(stack.pairedModelSelection == .falLTX23AudioToVideo)
    #expect(stack.pairedModelSelection.providerModelId == "fal-ai/ltx-2.3/audio-to-video")
    #expect(!stack.generateAudio)
    #expect(
        falAudioDriverUploadFileName(
            sha256: "ABCDEF0123456789"
        ) == "narration_driver_abcdef012345.m4a"
    )

    let endpoint = stack.pairedModelSelection.providerModelId
    let pricing = FALPricingSnapshot(
        fetchedAt: Date(),
        prices: [
            endpoint: FALModelPrice(
                endpointId: endpoint,
                unitPrice: 0.10,
                unit: "video_second",
                currency: "USD"
            )
        ]
    )
    let coastalEssay = ShotRenderCostEstimate.narrationDrivenUSD(
        stack: stack,
        durationSeconds: 7.25,
        pricing: pricing
    )
    let polarFieldNote = ShotRenderCostEstimate.narrationDrivenUSD(
        stack: stack,
        durationSeconds: 14.5,
        pricing: pricing
    )
    #expect(abs((coastalEssay ?? 0) - 0.725) < 0.0001)
    #expect(abs((polarFieldNote ?? 0) - 1.45) < 0.0001)
    #expect(
        shotSegmentPrompt(pair: ShotRenderPair(
            start: ProjectLensHeroImage(imageId: "terrace_orchard"),
            end: nil
        )) == shotSegmentPrompt(pair: ShotRenderPair(
            start: ProjectLensHeroImage(imageId: "polar_research_station"),
            end: nil
        ))
    )
}

/// The failure that started this named no field: "Input should be 2, 3, … or
/// 15". FAL puts the offending field in `loc`, and the summary threw it away.
@Test func providerValidationFailuresNameTheFieldTheyRejected() {
    let rejected: [String: Any] = [
        "loc": ["body", "duration"],
        "msg": "Input should be 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 or 15",
        "type": "literal_error"
    ]
    #expect(
        falVideoValidationSummary(from: rejected)
            == "duration: Input should be 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 or 15"
    )

    // Nested paths keep their shape; the "body" wrapper is noise.
    #expect(
        falVideoValidationSummary(from: [
            "loc": ["body", "image_url", "0"],
            "msg": "Invalid URL"
        ]) == "image_url.0: Invalid URL"
    )
    // No loc ⇒ the bare message, not a fabricated field.
    #expect(falVideoValidationSummary(from: ["msg": "Rate limited"]) == "Rate limited")
    // Not a validation entry at all.
    #expect(falVideoValidationSummary(from: ["error": "boom"]) == nil)
    #expect(falVideoValidationSummary(from: ["msg": "   "]) == nil)
}
