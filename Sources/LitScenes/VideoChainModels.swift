import Foundation

enum VideoOutputAspectRatio: String, Codable, Hashable, CaseIterable, Identifiable {
    case landscape16x9 = "16:9"
    case portrait9x16 = "9:16"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .landscape16x9: "Landscape 16:9"
        case .portrait9x16: "Portrait 9:16"
        }
    }

    var dimensions: (width: Int, height: Int) {
        switch self {
        case .landscape16x9: (1920, 1080)
        case .portrait9x16: (1080, 1920)
        }
    }
}

enum VideoFitPolicy: String, Codable, Hashable, CaseIterable, Identifiable {
    case centerCrop = "center_crop"
    case fitWithBlurFill = "fit_with_blur_fill"
    case fitWithBlackBars = "fit_with_black_bars"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .centerCrop: "Center crop"
        case .fitWithBlurFill: "Blur fill"
        case .fitWithBlackBars: "Black bars"
        }
    }
}

struct VideoOutputProfile: Codable, Hashable, Identifiable {
    var aspectRatio: VideoOutputAspectRatio = .landscape16x9
    var width: Int = 1920
    var height: Int = 1080
    var fps: Int = 24
    var fitPolicy: VideoFitPolicy = .centerCrop

    var id: String { "\(aspectRatio.rawValue)_\(width)x\(height)_\(fps)" }

    var label: String {
        "\(aspectRatio.label) · \(width)x\(height) · \(fps)fps"
    }

    static func standard(_ aspectRatio: VideoOutputAspectRatio, fitPolicy: VideoFitPolicy = .centerCrop) -> VideoOutputProfile {
        let dimensions = aspectRatio.dimensions
        return VideoOutputProfile(
            aspectRatio: aspectRatio,
            width: dimensions.width,
            height: dimensions.height,
            fps: 24,
            fitPolicy: fitPolicy
        )
    }
}

extension VideoOutputProfile {
    enum CodingKeys: String, CodingKey {
        case aspectRatio
        case width
        case height
        case fps
        case fitPolicy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aspectRatio = try container.decodeIfPresent(VideoOutputAspectRatio.self, forKey: .aspectRatio) ?? .landscape16x9
        let defaultDimensions = aspectRatio.dimensions
        width = try container.decodeIfPresent(Int.self, forKey: .width) ?? defaultDimensions.width
        height = try container.decodeIfPresent(Int.self, forKey: .height) ?? defaultDimensions.height
        fps = try container.decodeIfPresent(Int.self, forKey: .fps) ?? 24
        fitPolicy = try container.decodeIfPresent(VideoFitPolicy.self, forKey: .fitPolicy) ?? .centerCrop
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(fps, forKey: .fps)
        try container.encode(fitPolicy, forKey: .fitPolicy)
    }
}

enum VideoContinuityMode: String, Codable, Hashable {
    case firstFrameChain = "first_frame_chain"
    case keyframedChain = "keyframed_chain"
    case videoExtension = "video_extension"
    case promptExport = "prompt_export"

    var label: String {
        switch self {
        case .firstFrameChain: "Open-ended motion chain"
        case .keyframedChain: "Keyframed motion chain"
        case .videoExtension: "Video extension"
        case .promptExport: "Prompt export"
        }
    }
}

enum VideoChainGenerationMode: String, Codable, Hashable {
    case nativeExtend = "native_extend"
    case firstFrameChain = "first_frame_chain"
    case keyframedChain = "keyframed_chain"
    case existingClips = "existing_clips"
    case promptExport = "prompt_export"
}

enum VideoProviderSelection: String, Codable, Hashable, CaseIterable, Identifiable {
    case bestAvailable = "best_available"
    case ltxDirect = "ltx_direct"
    case civitaiWan = "civitai_wan"
    case klingImageToVideo = "kling_image_to_video"
    /// Executable from Shots only; intentionally omitted from the visible
    /// Video Chain provider list until that workflow is separately approved.
    case falImageToVideo = "fal_image_to_video"
    /// Executable from Shots only: supplied narration drives one video clip.
    case falAudioToVideo = "fal_audio_to_video"
    case localPromptExport = "local_prompt_export"
    case localExistingClip = "local_existing_clip"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bestAvailable: "Best Available"
        case .ltxDirect: "LTX Direct"
        case .civitaiWan: "CivitAI WAN"
        case .klingImageToVideo: "Kling Image-to-Video"
        case .falImageToVideo: "FAL Image-to-Video"
        case .falAudioToVideo: "FAL Audio-to-Video"
        case .localPromptExport: "Manifest Export"
        case .localExistingClip: "Existing Clips"
        }
    }

    static var visibleVideoChainProviders: [VideoProviderSelection] {
        [.bestAvailable, .civitaiWan, .klingImageToVideo, .ltxDirect, .localExistingClip]
    }

    var continuityMode: VideoContinuityMode {
        switch self {
        case .bestAvailable:
            return .firstFrameChain
        case .localPromptExport:
            return .promptExport
        case .ltxDirect:
            return .videoExtension
        case .civitaiWan:
            return .keyframedChain
        case .klingImageToVideo:
            return .firstFrameChain
        case .falImageToVideo:
            return .firstFrameChain
        case .falAudioToVideo:
            return .firstFrameChain
        case .localExistingClip:
            return .firstFrameChain
        }
    }
}

/// The JSON type a FAL endpoint's `duration` field takes. Two endpoints can
/// accept the same SECONDS and still disagree about how to spell them.
enum FALDurationEncoding: Hashable, Sendable {
    case integerSeconds
    case stringSeconds

    func payloadValue(seconds: Int) -> Any {
        switch self {
        case .integerSeconds: seconds
        case .stringSeconds: "\(seconds)"
        }
    }
}

enum VideoModelSelection: String, Codable, Hashable, CaseIterable, Identifiable {
    case auto = "auto"
    case ltxDirectDefault = "ltx_direct_default"
    case civitaiWanV25ImageToVideo = "civitai_wan_v2_5_image_to_video"
    case civitaiWanV27 = "civitai_wan_v2_7"
    case klingV26ImageToVideo = "kling_v2_6_image_to_video"
    case falKlingV3ProImageToVideo = "fal_kling_v3_pro_image_to_video"
    case falSeedance20ImageToVideo = "fal_seedance_2_0_image_to_video"
    case falSeedance25ImageToVideo = "fal_seedance_2_5_image_to_video"
    case falWan27ImageToVideo = "fal_wan_2_7_image_to_video"
    case falHailuo3ImageToVideo = "fal_hailuo_3_image_to_video"
    case falHailuo3MaxImageToVideo = "fal_hailuo_3_max_image_to_video"
    case falLTX23AudioToVideo = "fal_ltx_2_3_audio_to_video"
    case attachedClips = "attached_clips"
    case promptManifest = "prompt_manifest"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "Auto"
        case .ltxDirectDefault: "LTX 2.3 Pro"
        case .civitaiWanV25ImageToVideo: "WAN 2.5 Image-to-Video"
        case .civitaiWanV27: "WAN v2.7 Image-to-Video"
        case .klingV26ImageToVideo: "Kling v2.6 Image-to-Video"
        case .falKlingV3ProImageToVideo: "Kling 3 Pro Image-to-Video"
        case .falSeedance20ImageToVideo: "Seedance 2.0 Image-to-Video"
        case .falSeedance25ImageToVideo: "Seedance 2.5 Image-to-Video"
        case .falWan27ImageToVideo: "WAN 2.7 Image-to-Video"
        case .falHailuo3ImageToVideo: "Hailuo 3 Image-to-Video"
        case .falHailuo3MaxImageToVideo: "Hailuo 3 Max Image-to-Video"
        case .falLTX23AudioToVideo: "LTX 2.3 Audio-to-Video"
        case .attachedClips: "Attached Clips"
        case .promptManifest: "Prompt Manifest"
        }
    }

    var providerModelId: String {
        switch self {
        case .auto: "auto"
        case .ltxDirectDefault: "ltx-2-3-pro"
        case .civitaiWanV25ImageToVideo: "wan.v2.5.image-to-video"
        case .civitaiWanV27: "wan.v2.7.image-to-video"
        case .klingV26ImageToVideo: "kling-v2-6"
        case .falKlingV3ProImageToVideo: "fal-ai/kling-video/v3/pro/image-to-video"
        case .falSeedance20ImageToVideo: "bytedance/seedance-2.0/image-to-video"
        case .falSeedance25ImageToVideo: "bytedance/seedance-2.5/image-to-video"
        case .falWan27ImageToVideo: "fal-ai/wan/v2.7/image-to-video"
        case .falHailuo3ImageToVideo: "minimax/h3/image-to-video"
        case .falHailuo3MaxImageToVideo: "minimax/h3-max/image-to-video"
        case .falLTX23AudioToVideo: "fal-ai/ltx-2.3/audio-to-video"
        case .attachedClips: "local.attached-clips"
        case .promptManifest: "local.prompt-manifest"
        }
    }

    /// The `resolution` field this endpoint is rendered at, when it takes one
    /// explicitly. Authoritative for BOTH the request `FALVideoClient` sends
    /// and the frame size `falTokenBilling` prices — a render and its estimate
    /// must never disagree about resolution, so they read this one property.
    var falResolutionTier: FALVideoResolutionTier? {
        switch self {
        case .falSeedance20ImageToVideo: .p1080
        // Seedance 2.5's endpoint tops out at 720p (no 1080p tier).
        case .falSeedance25ImageToVideo: .p720
        case .falWan27ImageToVideo: .p1080
        // Hailuo 3 sends a resolution too, but a USER-CHOSEN one
        // (Hailuo3ResolutionPreference, 480P/768P/2K spellings outside this
        // tier vocabulary) threaded at request-build time — a fixed tier
        // here would lie. Kling derives resolution from the input image;
        // the rest never send a FAL resolution field.
        default: nil
        }
    }

    /// How this endpoint types its `duration` field — NOT just its range.
    ///
    /// FAL is not consistent about this and the wrong type is rejected at
    /// submit: Kling and Seedance declare a string enum, WAN 2.7 declares an
    /// integer. Sending WAN a string produced only "Input should be 2, 3, …
    /// or 15", with no field named, which reads like a range error when it is
    /// really a type error — 6 was always in range. Declared here, beside
    /// `falResolutionTier`, so the payload builder never has to guess.
    var falDurationEncoding: FALDurationEncoding? {
        switch self {
        case .falKlingV3ProImageToVideo, .falSeedance20ImageToVideo, .falSeedance25ImageToVideo: .stringSeconds
        // Hailuo 3's schema declares `duration` an integer, like WAN.
        case .falWan27ImageToVideo, .falHailuo3ImageToVideo, .falHailuo3MaxImageToVideo: .integerSeconds
        default: nil
        }
    }

    /// Non-nil when FAL bills this endpoint by token bucket rather than by
    /// wall-clock second — see `FALTokenBilling`.
    var falTokenBilling: FALTokenBilling? {
        switch self {
        case .falSeedance20ImageToVideo, .falSeedance25ImageToVideo:
            falResolutionTier.map { FALTokenBilling(tier: $0, fps: 24) }
        default:
            nil
        }
    }

    static func options(for provider: VideoProviderSelection) -> [VideoModelSelection] {
        switch provider {
        case .bestAvailable: [.auto]
        case .ltxDirect: [.ltxDirectDefault]
        case .civitaiWan: [.civitaiWanV27, .civitaiWanV25ImageToVideo]
        case .klingImageToVideo: [.klingV26ImageToVideo]
        case .falImageToVideo: [.falKlingV3ProImageToVideo, .falSeedance20ImageToVideo, .falSeedance25ImageToVideo, .falWan27ImageToVideo, .falHailuo3ImageToVideo, .falHailuo3MaxImageToVideo]
        case .falAudioToVideo: [.falLTX23AudioToVideo]
        case .localExistingClip: [.attachedClips]
        case .localPromptExport: [.promptManifest]
        }
    }

    static func defaultModel(for provider: VideoProviderSelection) -> VideoModelSelection {
        options(for: provider).first ?? .auto
    }

    static func resolved(requested: VideoModelSelection?, provider: VideoProviderSelection) -> VideoModelSelection {
        let requested = requested ?? .auto
        let options = options(for: provider)
        if options.contains(requested), requested != .auto {
            return requested
        }
        if provider == .bestAvailable {
            return .auto
        }
        return defaultModel(for: provider)
    }
}

struct VideoProviderCapability: Codable, Hashable, Identifiable {
    var providerId: VideoProviderSelection
    var id: String { providerId.rawValue }
    var label: String
    var continuityMode: VideoContinuityMode
    var requiresStartFrame: Bool
    var requiresEndFrame: Bool
    var supportsOptionalEndFrame: Bool
    var supportsExtend: Bool = false
    var supportsRetake: Bool = false
    var chainGenerationMode: VideoChainGenerationMode = .firstFrameChain
    var supportedAspectRatios: [VideoOutputAspectRatio]
    var supportedDurationsSeconds: [Int]
    var supportedFPS: [Int]
    var canRender: Bool = false
    var blockers: [String] = []
    var warnings: [String] = []

    static func capability(
        for provider: VideoProviderSelection,
        outputProfile: VideoOutputProfile,
        durationSeconds: Int,
        credentialStore: LitScenesCredentialResolving = LitScenesCredentialStore()
    ) -> VideoProviderCapability {
        switch provider {
        case .bestAvailable:
            return VideoProviderCapability(
                providerId: provider,
                label: provider.label,
                continuityMode: .firstFrameChain,
                requiresStartFrame: false,
                requiresEndFrame: false,
                supportsOptionalEndFrame: false,
                chainGenerationMode: .firstFrameChain,
                supportedAspectRatios: VideoOutputAspectRatio.allCases,
                supportedDurationsSeconds: [],
                supportedFPS: [24],
                canRender: false,
                blockers: ["video_provider_not_configured"],
                warnings: ["Configure CivitAI, Kling, or LTX, or choose Existing Clips before generating video."]
            )
        case .localPromptExport:
            return VideoProviderCapability(
                providerId: provider,
                label: provider.label,
                continuityMode: .promptExport,
                requiresStartFrame: false,
                requiresEndFrame: false,
                supportsOptionalEndFrame: false,
                chainGenerationMode: .promptExport,
                supportedAspectRatios: VideoOutputAspectRatio.allCases,
                supportedDurationsSeconds: [],
                supportedFPS: [24],
                canRender: true,
                warnings: ["No paid provider call; exports chain prompts and manifest only."]
            )
        case .localExistingClip:
            return VideoProviderCapability(
                providerId: provider,
                label: provider.label,
                continuityMode: .firstFrameChain,
                requiresStartFrame: false,
                requiresEndFrame: false,
                supportsOptionalEndFrame: false,
                chainGenerationMode: .existingClips,
                supportedAspectRatios: VideoOutputAspectRatio.allCases,
                supportedDurationsSeconds: [],
                supportedFPS: [24],
                canRender: true,
                warnings: ["No paid provider call; composes existing clip paths when present."]
            )
        case .ltxDirect:
            var blockers: [String] = []
            let durations = [6, 8, 10, 12, 14, 16, 18, 20]
            if !durations.contains(durationSeconds) {
                blockers.append("duration_not_supported_by_ltx_direct")
            }
            if ![.landscape16x9, .portrait9x16].contains(outputProfile.aspectRatio) {
                blockers.append("aspect_not_supported_by_ltx_direct")
            }
            if credentialStore.resolvedCredential(for: .ltx).isEmpty {
                blockers.append("LTX_API_KEY_missing")
            }
            return VideoProviderCapability(
                providerId: provider,
                label: provider.label,
                continuityMode: .videoExtension,
                requiresStartFrame: true,
                requiresEndFrame: false,
                supportsOptionalEndFrame: true,
                supportsExtend: true,
                supportsRetake: true,
                chainGenerationMode: .nativeExtend,
                supportedAspectRatios: [.landscape16x9, .portrait9x16],
                supportedDurationsSeconds: durations,
                supportedFPS: [24, 25, 48, 50],
                canRender: blockers.isEmpty,
                blockers: blockers,
                warnings: ["End frame is optional; without it each clip is open-ended and hands off its actual final frame."]
            )
        case .civitaiWan:
            var blockers: [String] = []
            let durations = [5, 6, 8, 10]
            if !durations.contains(durationSeconds) {
                blockers.append("duration_not_supported_by_civitai_wan")
            }
            if ![.landscape16x9, .portrait9x16].contains(outputProfile.aspectRatio) {
                blockers.append("aspect_not_supported_by_civitai_wan")
            }
            if credentialStore.resolvedCredential(for: .civitai).isEmpty {
                blockers.append("CIVITAI_API_KEY_missing")
            }
            return VideoProviderCapability(
                providerId: provider,
                label: provider.label,
                continuityMode: .keyframedChain,
                requiresStartFrame: true,
                requiresEndFrame: true,
                supportsOptionalEndFrame: false,
                chainGenerationMode: .keyframedChain,
                supportedAspectRatios: [.landscape16x9, .portrait9x16],
                supportedDurationsSeconds: durations,
                supportedFPS: [24],
                canRender: blockers.isEmpty,
                blockers: blockers,
                warnings: ["Every segment needs a target end frame before render."]
            )
        case .klingImageToVideo:
            var blockers: [String] = []
            let durations = [5, 10]
            if durationSeconds <= 0 || durationSeconds > 10 {
                blockers.append("duration_not_supported_by_kling")
            }
            if ![.landscape16x9, .portrait9x16].contains(outputProfile.aspectRatio) {
                blockers.append("aspect_not_supported_by_kling")
            }
            let klingCredential = credentialStore.resolvedCredential(for: .kling)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if klingCredential.isEmpty {
                blockers.append("KLING_API_KEY_missing")
            } else if !klingCredentialLooksUsableForVideoChain(klingCredential) {
                blockers.append("KLING_API_KEY_invalid_expected_access_secret_or_jwt")
            }
            return VideoProviderCapability(
                providerId: provider,
                label: provider.label,
                continuityMode: .firstFrameChain,
                requiresStartFrame: true,
                requiresEndFrame: false,
                supportsOptionalEndFrame: true,
                chainGenerationMode: .firstFrameChain,
                supportedAspectRatios: [.landscape16x9, .portrait9x16],
                supportedDurationsSeconds: durations,
                supportedFPS: [24, 30],
                canRender: blockers.isEmpty,
                blockers: blockers,
                warnings: ["Kling accepts 5s or 10s native clips; shorter SCENES segment durations are trimmed locally when needed."]
            )
        case .falImageToVideo:
            var blockers: [String] = []
            let durations = Array(3...15)
            if !durations.contains(durationSeconds) {
                blockers.append("duration_not_supported_by_fal_image_to_video")
            }
            if ![.landscape16x9, .portrait9x16].contains(outputProfile.aspectRatio) {
                blockers.append("aspect_not_supported_by_fal_image_to_video")
            }
            if credentialStore.resolvedCredential(for: .fal).trimmed.isEmpty {
                blockers.append("FAL_API_KEY_missing")
            }
            return VideoProviderCapability(
                providerId: provider,
                label: provider.label,
                continuityMode: .firstFrameChain,
                requiresStartFrame: true,
                requiresEndFrame: false,
                supportsOptionalEndFrame: true,
                chainGenerationMode: .firstFrameChain,
                supportedAspectRatios: [.landscape16x9, .portrait9x16],
                supportedDurationsSeconds: durations,
                supportedFPS: [24],
                canRender: blockers.isEmpty,
                blockers: blockers,
                warnings: ["Kling 3 Pro, Seedance 2.0/2.5, WAN 2.7, and Hailuo 3 / 3 Max accept an optional target end frame; native audio follows the persisted Shot recipe (Hailuo 3's audio is always on)."]
            )
        case .falAudioToVideo:
            var blockers: [String] = []
            let durations = Array(2...20)
            if !durations.contains(durationSeconds) {
                blockers.append("duration_not_supported_by_fal_ltx_audio_to_video")
            }
            if outputProfile.aspectRatio != .landscape16x9 {
                blockers.append("aspect_not_supported_by_shot_ltx_audio_to_video")
            }
            if credentialStore.resolvedCredential(for: .fal).trimmed.isEmpty {
                blockers.append("FAL_API_KEY_missing")
            }
            return VideoProviderCapability(
                providerId: provider,
                label: provider.label,
                continuityMode: .firstFrameChain,
                requiresStartFrame: true,
                requiresEndFrame: false,
                supportsOptionalEndFrame: false,
                chainGenerationMode: .firstFrameChain,
                supportedAspectRatios: [.landscape16x9],
                supportedDurationsSeconds: durations,
                supportedFPS: [24],
                canRender: blockers.isEmpty,
                blockers: blockers,
                warnings: ["Requires an authored 2–20 second narration driver; available in Shots only."]
            )
        }
    }
}

private func klingCredentialLooksUsableForVideoChain(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.split(separator: ".").count == 3 || trimmed.contains(":")
}

enum VideoChainPreset: String, Codable, Hashable, CaseIterable, Identifiable {
    case youtubeStoryReel = "youtube_story_reel"
    case portraitStoryReel = "portrait_story_reel"
    case storeDisplayLoop = "store_display_loop"
    case cinematicProof = "cinematic_proof"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .youtubeStoryReel: "YouTube Story Reel"
        case .portraitStoryReel: "Portrait Story Reel"
        case .storeDisplayLoop: "Store Display Loop"
        case .cinematicProof: "Cinematic Proof"
        }
    }

    var outputProfile: VideoOutputProfile {
        switch self {
        case .youtubeStoryReel, .storeDisplayLoop, .cinematicProof:
            return .standard(.landscape16x9)
        case .portraitStoryReel:
            return .standard(.portrait9x16, fitPolicy: .fitWithBlurFill)
        }
    }

    var clipCount: Int {
        switch self {
        case .storeDisplayLoop: 3
        case .cinematicProof: 5
        case .youtubeStoryReel, .portraitStoryReel: 4
        }
    }

    var durationSeconds: Int {
        switch self {
        case .storeDisplayLoop: 6
        case .cinematicProof: 10
        case .youtubeStoryReel, .portraitStoryReel: 8
        }
    }
}

enum VideoChainStatus: String, Codable, Hashable {
    case draft
    case planned
    case needsKeyframes = "needs_keyframes"
    case readyForApproval = "ready_for_approval"
    case approved
    case generating
    case ready
    case failed
    case stale
}

enum VideoSegmentStatus: String, Codable, Hashable {
    case draft
    case needsStartFrame = "needs_start_frame"
    case needsEndFrame = "needs_end_frame"
    case readyForRender = "ready_for_render"
    case queued
    case generating
    case ready
    case failed
    case stale
}

enum VideoSeamStatus: String, Codable, Hashable {
    case draft
    case ready
    case stale
    case needsRechain = "needs_rechain"
}

enum VideoFrameSourceType: String, Codable, Hashable {
    case none
    case selectedProjectImage = "selected_project_image"
    case sourceMedia = "source_media"
    case attachedImage = "attached_image"
    case generatedStill = "generated_still"
    case previousSegmentEnd = "previous_segment_end"
    case actualSegmentEnd = "actual_segment_end"
}

struct VideoFrameSourceDocument: Codable, Hashable {
    var type: VideoFrameSourceType = .none
    var segmentId: String = ""
    var mediaId: String = ""
    var framePath: String = ""
    var normalizedFramePath: String = ""
    var note: String = ""
    var versionId: String = ""

    enum CodingKeys: String, CodingKey {
        case type
        case segmentId
        case mediaId
        case framePath
        case normalizedFramePath
        case note
        case versionId
    }

    init(
        type: VideoFrameSourceType = .none,
        segmentId: String = "",
        mediaId: String = "",
        framePath: String = "",
        normalizedFramePath: String = "",
        note: String = "",
        versionId: String = ""
    ) {
        self.type = type
        self.segmentId = segmentId
        self.mediaId = mediaId
        self.framePath = framePath
        self.normalizedFramePath = normalizedFramePath
        self.note = note
        self.versionId = versionId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(VideoFrameSourceType.self, forKey: .type) ?? .none
        segmentId = try container.decodeIfPresent(String.self, forKey: .segmentId) ?? ""
        mediaId = try container.decodeIfPresent(String.self, forKey: .mediaId) ?? ""
        framePath = try container.decodeIfPresent(String.self, forKey: .framePath) ?? ""
        normalizedFramePath = try container.decodeIfPresent(String.self, forKey: .normalizedFramePath) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        versionId = try container.decodeIfPresent(String.self, forKey: .versionId) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(segmentId, forKey: .segmentId)
        try container.encode(mediaId, forKey: .mediaId)
        try container.encode(framePath, forKey: .framePath)
        try container.encode(normalizedFramePath, forKey: .normalizedFramePath)
        try container.encode(note, forKey: .note)
        try container.encode(versionId, forKey: .versionId)
    }

    var hasFrame: Bool {
        !normalizedFramePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !framePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let empty = VideoFrameSourceDocument()
}

enum VideoFrameSourceCandidateGroup: String, CaseIterable, Identifiable, Hashable {
    case recommended
    case nearby
    case allEnabled = "all_enabled"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recommended: "Recommended"
        case .nearby: "Nearby"
        case .allEnabled: "All Enabled"
        }
    }
}

struct VideoFrameSourceCandidate: Identifiable, Hashable {
    var mediaId: String
    var id: String { mediaId }
    var group: VideoFrameSourceCandidateGroup
    var filename: String
    var relativePath: String
    var thumbnailPath: String
    var sourcePath: String
    var kind: MediaKind
    var width: Int
    var height: Int
    var sourceTimestampSeconds: Double?
    var provenanceLabels: [String]

    var displaySubtitle: String {
        if !provenanceLabels.isEmpty {
            return provenanceLabels.joined(separator: " · ")
        }
        if !relativePath.isEmpty {
            return relativePath
        }
        return mediaId
    }
}

enum VideoFrameChatRole: String, Codable, Hashable {
    case user
    case assistant
    case system
}

struct VideoFrameChatMessageDocument: Codable, Hashable, Identifiable {
    var messageId: String
    var id: String { messageId }
    var role: VideoFrameChatRole
    var frameRole: String
    var text: String
    var linkedVersionId: String = ""
    var createdAt: String = DateFormats.now()
}

extension VideoFrameChatMessageDocument {
    enum CodingKeys: String, CodingKey {
        case messageId
        case role
        case frameRole
        case text
        case linkedVersionId
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageId = try container.decodeIfPresent(String.self, forKey: .messageId) ?? ""
        role = try container.decodeIfPresent(VideoFrameChatRole.self, forKey: .role) ?? .assistant
        frameRole = try container.decodeIfPresent(String.self, forKey: .frameRole) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        linkedVersionId = try container.decodeIfPresent(String.self, forKey: .linkedVersionId) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? DateFormats.now()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageId, forKey: .messageId)
        try container.encode(role, forKey: .role)
        try container.encode(frameRole, forKey: .frameRole)
        try container.encode(text, forKey: .text)
        try container.encode(linkedVersionId, forKey: .linkedVersionId)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct VideoFrameVersionDocument: Codable, Hashable, Identifiable {
    var versionId: String
    var id: String { versionId }
    var versionNumber: Int
    var role: String
    var status: VideoSegmentStatus = .draft
    var framePath: String = ""
    var normalizedFramePath: String = ""
    var sourceFramePath: String = ""
    var sourceMediaId: String = ""
    var sourceFilename: String = ""
    var prompt: String = ""
    var assistantNote: String = ""
    var modelId: String = ""
    var providerRequestId: String = ""
    var traceId: String = ""
    var archivedMediaId: String? = nil
    var errorMessage: String = ""
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()

    var displayFramePath: String {
        normalizedFramePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? framePath
            : normalizedFramePath
    }
}

extension VideoFrameVersionDocument {
    enum CodingKeys: String, CodingKey {
        case versionId
        case versionNumber
        case role
        case status
        case framePath
        case normalizedFramePath
        case sourceFramePath
        case sourceMediaId
        case sourceFilename
        case prompt
        case assistantNote
        case modelId
        case providerRequestId
        case traceId
        case archivedMediaId
        case errorMessage
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        versionId = try container.decodeIfPresent(String.self, forKey: .versionId) ?? ""
        versionNumber = try container.decodeIfPresent(Int.self, forKey: .versionNumber) ?? 0
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? "start"
        status = try container.decodeIfPresent(VideoSegmentStatus.self, forKey: .status) ?? .draft
        framePath = try container.decodeIfPresent(String.self, forKey: .framePath) ?? ""
        normalizedFramePath = try container.decodeIfPresent(String.self, forKey: .normalizedFramePath) ?? ""
        sourceFramePath = try container.decodeIfPresent(String.self, forKey: .sourceFramePath) ?? ""
        sourceMediaId = try container.decodeIfPresent(String.self, forKey: .sourceMediaId) ?? ""
        sourceFilename = try container.decodeIfPresent(String.self, forKey: .sourceFilename) ?? ""
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        assistantNote = try container.decodeIfPresent(String.self, forKey: .assistantNote) ?? ""
        modelId = try container.decodeIfPresent(String.self, forKey: .modelId) ?? ""
        providerRequestId = try container.decodeIfPresent(String.self, forKey: .providerRequestId) ?? ""
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId) ?? ""
        archivedMediaId = try container.decodeIfPresent(String.self, forKey: .archivedMediaId)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? DateFormats.now()
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(versionId, forKey: .versionId)
        try container.encode(versionNumber, forKey: .versionNumber)
        try container.encode(role, forKey: .role)
        try container.encode(status, forKey: .status)
        try container.encode(framePath, forKey: .framePath)
        try container.encode(normalizedFramePath, forKey: .normalizedFramePath)
        try container.encode(sourceFramePath, forKey: .sourceFramePath)
        try container.encode(sourceMediaId, forKey: .sourceMediaId)
        try container.encode(sourceFilename, forKey: .sourceFilename)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(assistantNote, forKey: .assistantNote)
        try container.encode(modelId, forKey: .modelId)
        try container.encode(providerRequestId, forKey: .providerRequestId)
        try container.encode(traceId, forKey: .traceId)
        try container.encodeIfPresent(archivedMediaId, forKey: .archivedMediaId)
        try container.encode(errorMessage, forKey: .errorMessage)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct VideoSegmentVersionDocument: Codable, Hashable, Identifiable {
    var versionId: String
    var id: String { versionId }
    var versionNumber: Int
    var status: VideoSegmentStatus = .draft
    var providerId: VideoProviderSelection = .bestAvailable
    var modelId: VideoModelSelection? = nil
    var providerVideoId: String = ""
    var providerJobId: String = ""
    var providerOperation: String = ""
    var traceId: String = ""
    var providerNativeSize: String = ""
    var videoOutputPath: String = ""
    var normalizedVideoOutputPath: String = ""
    var providerOutputPath: String = ""
    var sourceVideoPath: String = ""
    var extractedFromProviderOutput: Bool = false
    var extractionStartSeconds: Double = 0
    var extractionDurationSeconds: Double = 0
    var retakeStartSeconds: Double = 0
    var retakeDurationSeconds: Double = 0
    var extendContextSeconds: Double = 0
    var startFramePath: String = ""
    var targetEndFramePath: String = ""
    var actualEndFramePath: String = ""
    var prompt: String = ""
    var negativePrompt: String = ""
    var motionDirective: String = ""
    var archivedMediaId: String = ""
    var actualEndFrameMediaId: String = ""
    var errorMessage: String = ""
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()

    enum CodingKeys: String, CodingKey {
        case versionId
        case versionNumber
        case status
        case providerId
        case modelId
        case providerVideoId
        case providerJobId
        case providerOperation
        case traceId
        case providerNativeSize
        case videoOutputPath
        case normalizedVideoOutputPath
        case providerOutputPath
        case sourceVideoPath
        case extractedFromProviderOutput
        case extractionStartSeconds
        case extractionDurationSeconds
        case retakeStartSeconds
        case retakeDurationSeconds
        case extendContextSeconds
        case startFramePath
        case targetEndFramePath
        case actualEndFramePath
        case prompt
        case negativePrompt
        case motionDirective
        case archivedMediaId
        case actualEndFrameMediaId
        case errorMessage
        case createdAt
        case updatedAt
    }

    init(
        versionId: String,
        versionNumber: Int,
        status: VideoSegmentStatus = .draft,
        providerId: VideoProviderSelection = .bestAvailable,
        modelId: VideoModelSelection? = nil,
        providerVideoId: String = "",
        providerJobId: String = "",
        providerOperation: String = "",
        traceId: String = "",
        providerNativeSize: String = "",
        videoOutputPath: String = "",
        normalizedVideoOutputPath: String = "",
        providerOutputPath: String = "",
        sourceVideoPath: String = "",
        extractedFromProviderOutput: Bool = false,
        extractionStartSeconds: Double = 0,
        extractionDurationSeconds: Double = 0,
        retakeStartSeconds: Double = 0,
        retakeDurationSeconds: Double = 0,
        extendContextSeconds: Double = 0,
        startFramePath: String = "",
        targetEndFramePath: String = "",
        actualEndFramePath: String = "",
        prompt: String = "",
        negativePrompt: String = "",
        motionDirective: String = "",
        archivedMediaId: String = "",
        actualEndFrameMediaId: String = "",
        errorMessage: String = "",
        createdAt: String = DateFormats.now(),
        updatedAt: String = DateFormats.now()
    ) {
        self.versionId = versionId
        self.versionNumber = versionNumber
        self.status = status
        self.providerId = providerId
        self.modelId = modelId
        self.providerVideoId = providerVideoId
        self.providerJobId = providerJobId
        self.providerOperation = providerOperation
        self.traceId = traceId
        self.providerNativeSize = providerNativeSize
        self.videoOutputPath = videoOutputPath
        self.normalizedVideoOutputPath = normalizedVideoOutputPath
        self.providerOutputPath = providerOutputPath
        self.sourceVideoPath = sourceVideoPath
        self.extractedFromProviderOutput = extractedFromProviderOutput
        self.extractionStartSeconds = extractionStartSeconds
        self.extractionDurationSeconds = extractionDurationSeconds
        self.retakeStartSeconds = retakeStartSeconds
        self.retakeDurationSeconds = retakeDurationSeconds
        self.extendContextSeconds = extendContextSeconds
        self.startFramePath = startFramePath
        self.targetEndFramePath = targetEndFramePath
        self.actualEndFramePath = actualEndFramePath
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.motionDirective = motionDirective
        self.archivedMediaId = archivedMediaId
        self.actualEndFrameMediaId = actualEndFrameMediaId
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        versionId = try container.decodeIfPresent(String.self, forKey: .versionId) ?? ""
        versionNumber = try container.decodeIfPresent(Int.self, forKey: .versionNumber) ?? 0
        status = try container.decodeIfPresent(VideoSegmentStatus.self, forKey: .status) ?? .draft
        providerId = try container.decodeIfPresent(VideoProviderSelection.self, forKey: .providerId) ?? .bestAvailable
        modelId = try container.decodeIfPresent(VideoModelSelection.self, forKey: .modelId)
        providerVideoId = try container.decodeIfPresent(String.self, forKey: .providerVideoId) ?? ""
        providerJobId = try container.decodeIfPresent(String.self, forKey: .providerJobId) ?? ""
        providerOperation = try container.decodeIfPresent(String.self, forKey: .providerOperation) ?? ""
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId) ?? ""
        providerNativeSize = try container.decodeIfPresent(String.self, forKey: .providerNativeSize) ?? ""
        videoOutputPath = try container.decodeIfPresent(String.self, forKey: .videoOutputPath) ?? ""
        normalizedVideoOutputPath = try container.decodeIfPresent(String.self, forKey: .normalizedVideoOutputPath) ?? ""
        providerOutputPath = try container.decodeIfPresent(String.self, forKey: .providerOutputPath) ?? ""
        sourceVideoPath = try container.decodeIfPresent(String.self, forKey: .sourceVideoPath) ?? ""
        extractedFromProviderOutput = try container.decodeIfPresent(Bool.self, forKey: .extractedFromProviderOutput) ?? false
        extractionStartSeconds = try container.decodeIfPresent(Double.self, forKey: .extractionStartSeconds) ?? 0
        extractionDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .extractionDurationSeconds) ?? 0
        retakeStartSeconds = try container.decodeIfPresent(Double.self, forKey: .retakeStartSeconds) ?? 0
        retakeDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .retakeDurationSeconds) ?? 0
        extendContextSeconds = try container.decodeIfPresent(Double.self, forKey: .extendContextSeconds) ?? 0
        startFramePath = try container.decodeIfPresent(String.self, forKey: .startFramePath) ?? ""
        targetEndFramePath = try container.decodeIfPresent(String.self, forKey: .targetEndFramePath) ?? ""
        actualEndFramePath = try container.decodeIfPresent(String.self, forKey: .actualEndFramePath) ?? ""
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        negativePrompt = try container.decodeIfPresent(String.self, forKey: .negativePrompt) ?? ""
        motionDirective = try container.decodeIfPresent(String.self, forKey: .motionDirective) ?? ""
        archivedMediaId = try container.decodeIfPresent(String.self, forKey: .archivedMediaId) ?? ""
        actualEndFrameMediaId = try container.decodeIfPresent(String.self, forKey: .actualEndFrameMediaId) ?? ""
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? DateFormats.now()
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(versionId, forKey: .versionId)
        try container.encode(versionNumber, forKey: .versionNumber)
        try container.encode(status, forKey: .status)
        try container.encode(providerId, forKey: .providerId)
        try container.encodeIfPresent(modelId, forKey: .modelId)
        try container.encode(providerVideoId, forKey: .providerVideoId)
        try container.encode(providerJobId, forKey: .providerJobId)
        try container.encode(providerOperation, forKey: .providerOperation)
        try container.encode(traceId, forKey: .traceId)
        try container.encode(providerNativeSize, forKey: .providerNativeSize)
        try container.encode(videoOutputPath, forKey: .videoOutputPath)
        try container.encode(normalizedVideoOutputPath, forKey: .normalizedVideoOutputPath)
        try container.encode(providerOutputPath, forKey: .providerOutputPath)
        try container.encode(sourceVideoPath, forKey: .sourceVideoPath)
        try container.encode(extractedFromProviderOutput, forKey: .extractedFromProviderOutput)
        try container.encode(extractionStartSeconds, forKey: .extractionStartSeconds)
        try container.encode(extractionDurationSeconds, forKey: .extractionDurationSeconds)
        try container.encode(retakeStartSeconds, forKey: .retakeStartSeconds)
        try container.encode(retakeDurationSeconds, forKey: .retakeDurationSeconds)
        try container.encode(extendContextSeconds, forKey: .extendContextSeconds)
        try container.encode(startFramePath, forKey: .startFramePath)
        try container.encode(targetEndFramePath, forKey: .targetEndFramePath)
        try container.encode(actualEndFramePath, forKey: .actualEndFramePath)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(negativePrompt, forKey: .negativePrompt)
        try container.encode(motionDirective, forKey: .motionDirective)
        try container.encode(archivedMediaId, forKey: .archivedMediaId)
        try container.encode(actualEndFrameMediaId, forKey: .actualEndFrameMediaId)
        try container.encode(errorMessage, forKey: .errorMessage)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var hasVideoOutput: Bool {
        !normalizedVideoOutputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !videoOutputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayVideoPath: String {
        normalizedVideoOutputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? videoOutputPath
            : normalizedVideoOutputPath
    }
}

struct VideoSegmentDocument: Codable, Hashable, Identifiable {
    var segmentId: String
    var id: String { segmentId }
    var order: Int
    var sourceBeatIds: [String]
    var title: String
    var durationSeconds: Int
    var prompt: String
    var negativePrompt: String
    var motionDirective: String
    var startFrameSource: VideoFrameSourceDocument = .empty
    var targetEndFrameSource: VideoFrameSourceDocument = .empty
    var actualEndFramePath: String = ""
    var videoOutputPath: String = ""
    var normalizedVideoOutputPath: String = ""
    var providerVideoId: String = ""
    var providerJobId: String = ""
    var providerOperation: String = ""
    var providerTraceId: String = ""
    var providerNativeSize: String = ""
    var status: VideoSegmentStatus = .draft
    var locked: Bool = false
    var downstreamStale: Bool = false
    var fitPolicy: VideoFitPolicy = .centerCrop
    var sourceFingerprint: String = ""
    var activeVersionId: String = ""
    var versions: [VideoSegmentVersionDocument] = []
    var frameVersions: [VideoFrameVersionDocument] = []
    var frameChatMessages: [VideoFrameChatMessageDocument] = []
    var updatedAt: String = DateFormats.now()
}

extension VideoSegmentDocument {
    enum CodingKeys: String, CodingKey {
        case segmentId
        case order
        case sourceBeatIds
        case title
        case durationSeconds
        case prompt
        case negativePrompt
        case motionDirective
        case startFrameSource
        case targetEndFrameSource
        case actualEndFramePath
        case videoOutputPath
        case normalizedVideoOutputPath
        case providerVideoId
        case providerJobId
        case providerOperation
        case providerTraceId
        case providerNativeSize
        case status
        case locked
        case downstreamStale
        case fitPolicy
        case sourceFingerprint
        case activeVersionId
        case versions
        case frameVersions
        case frameChatMessages
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        segmentId = try container.decodeIfPresent(String.self, forKey: .segmentId) ?? ""
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        sourceBeatIds = try container.decodeIfPresent([String].self, forKey: .sourceBeatIds) ?? []
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        negativePrompt = try container.decodeIfPresent(String.self, forKey: .negativePrompt) ?? ""
        motionDirective = try container.decodeIfPresent(String.self, forKey: .motionDirective) ?? ""
        startFrameSource = try container.decodeIfPresent(VideoFrameSourceDocument.self, forKey: .startFrameSource) ?? .empty
        targetEndFrameSource = try container.decodeIfPresent(VideoFrameSourceDocument.self, forKey: .targetEndFrameSource) ?? .empty
        actualEndFramePath = try container.decodeIfPresent(String.self, forKey: .actualEndFramePath) ?? ""
        videoOutputPath = try container.decodeIfPresent(String.self, forKey: .videoOutputPath) ?? ""
        normalizedVideoOutputPath = try container.decodeIfPresent(String.self, forKey: .normalizedVideoOutputPath) ?? ""
        providerVideoId = try container.decodeIfPresent(String.self, forKey: .providerVideoId) ?? ""
        providerJobId = try container.decodeIfPresent(String.self, forKey: .providerJobId) ?? ""
        providerOperation = try container.decodeIfPresent(String.self, forKey: .providerOperation) ?? ""
        providerTraceId = try container.decodeIfPresent(String.self, forKey: .providerTraceId) ?? ""
        providerNativeSize = try container.decodeIfPresent(String.self, forKey: .providerNativeSize) ?? ""
        status = try container.decodeIfPresent(VideoSegmentStatus.self, forKey: .status) ?? .draft
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked) ?? false
        downstreamStale = try container.decodeIfPresent(Bool.self, forKey: .downstreamStale) ?? false
        fitPolicy = try container.decodeIfPresent(VideoFitPolicy.self, forKey: .fitPolicy) ?? .centerCrop
        sourceFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceFingerprint) ?? ""
        activeVersionId = try container.decodeIfPresent(String.self, forKey: .activeVersionId) ?? ""
        versions = try container.decodeIfPresent([VideoSegmentVersionDocument].self, forKey: .versions) ?? []
        frameVersions = try container.decodeIfPresent([VideoFrameVersionDocument].self, forKey: .frameVersions) ?? []
        frameChatMessages = try container.decodeIfPresent([VideoFrameChatMessageDocument].self, forKey: .frameChatMessages) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
        migrateLegacyFrameSourcesIfNeeded()
        migrateLegacyClipOutputIfNeeded()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(segmentId, forKey: .segmentId)
        try container.encode(order, forKey: .order)
        try container.encode(sourceBeatIds, forKey: .sourceBeatIds)
        try container.encode(title, forKey: .title)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(negativePrompt, forKey: .negativePrompt)
        try container.encode(motionDirective, forKey: .motionDirective)
        try container.encode(startFrameSource, forKey: .startFrameSource)
        try container.encode(targetEndFrameSource, forKey: .targetEndFrameSource)
        try container.encode(actualEndFramePath, forKey: .actualEndFramePath)
        try container.encode(videoOutputPath, forKey: .videoOutputPath)
        try container.encode(normalizedVideoOutputPath, forKey: .normalizedVideoOutputPath)
        try container.encode(providerVideoId, forKey: .providerVideoId)
        try container.encode(providerJobId, forKey: .providerJobId)
        try container.encode(providerOperation, forKey: .providerOperation)
        try container.encode(providerTraceId, forKey: .providerTraceId)
        try container.encode(providerNativeSize, forKey: .providerNativeSize)
        try container.encode(status, forKey: .status)
        try container.encode(locked, forKey: .locked)
        try container.encode(downstreamStale, forKey: .downstreamStale)
        try container.encode(fitPolicy, forKey: .fitPolicy)
        try container.encode(sourceFingerprint, forKey: .sourceFingerprint)
        try container.encode(activeVersionId, forKey: .activeVersionId)
        try container.encode(versions, forKey: .versions)
        try container.encode(frameVersions, forKey: .frameVersions)
        try container.encode(frameChatMessages, forKey: .frameChatMessages)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var sortedVersions: [VideoSegmentVersionDocument] {
        versions.sorted { lhs, rhs in
            if lhs.versionNumber == rhs.versionNumber {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.versionNumber < rhs.versionNumber
        }
    }

    var activeVersion: VideoSegmentVersionDocument? {
        versions.first { $0.versionId == activeVersionId } ?? sortedVersions.last
    }

    var activeVideoPath: String {
        activeVersion?.displayVideoPath ?? (normalizedVideoOutputPath.isEmpty ? videoOutputPath : normalizedVideoOutputPath)
    }

    var readyVersionCount: Int {
        versions.filter { $0.status == .ready && !$0.displayVideoPath.isEmpty }.count
    }

    func sortedFrameVersions(role: String) -> [VideoFrameVersionDocument] {
        frameVersions
            .filter { $0.role == role }
            .sorted { lhs, rhs in
                if lhs.versionNumber == rhs.versionNumber {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.versionNumber < rhs.versionNumber
            }
    }

    func activeFrameVersion(role: String) -> VideoFrameVersionDocument? {
        let activeId = role == "start" ? startFrameSource.versionId : targetEndFrameSource.versionId
        if !activeId.isEmpty, let active = frameVersions.first(where: { $0.versionId == activeId }) {
            return active
        }
        return sortedFrameVersions(role: role).last
    }

    mutating func activateFrameVersion(_ version: VideoFrameVersionDocument) {
        let source = VideoFrameSourceDocument(
            type: .generatedStill,
            segmentId: segmentId,
            mediaId: version.sourceMediaId,
            framePath: version.framePath,
            normalizedFramePath: version.normalizedFramePath,
            note: version.assistantNote.isEmpty ? "Generated still V\(version.versionNumber)" : version.assistantNote,
            versionId: version.versionId
        )
        if version.role == "start" {
            startFrameSource = source
        } else {
            targetEndFrameSource = source
        }
        updatedAt = version.updatedAt
    }

    mutating func upsertFrameVersion(_ version: VideoFrameVersionDocument, activate: Bool) {
        frameVersions.removeAll { $0.versionId == version.versionId }
        frameVersions.append(version)
        frameVersions.sort {
            if $0.role == $1.role {
                if $0.versionNumber == $1.versionNumber {
                    return $0.createdAt < $1.createdAt
                }
                return $0.versionNumber < $1.versionNumber
            }
            return $0.role < $1.role
        }
        if activate {
            activateFrameVersion(version)
        }
    }

    mutating func activateVersion(_ version: VideoSegmentVersionDocument) {
        activeVersionId = version.versionId
        videoOutputPath = version.videoOutputPath
        normalizedVideoOutputPath = version.normalizedVideoOutputPath
        actualEndFramePath = version.actualEndFramePath
        providerVideoId = version.providerVideoId
        providerJobId = version.providerJobId
        providerOperation = version.providerOperation
        providerTraceId = version.traceId
        providerNativeSize = version.providerNativeSize
        status = version.status
        updatedAt = version.updatedAt
    }

    mutating func upsertVersion(_ version: VideoSegmentVersionDocument, activate: Bool) {
        versions.removeAll { $0.versionId == version.versionId }
        versions.append(version)
        versions.sort {
            if $0.versionNumber == $1.versionNumber {
                return $0.createdAt < $1.createdAt
            }
            return $0.versionNumber < $1.versionNumber
        }
        if activate {
            activateVersion(version)
        }
    }

    mutating func migrateLegacyClipOutputIfNeeded() {
        if activeVersionId.isEmpty, let latest = sortedVersions.last {
            activeVersionId = latest.versionId
        }
        guard versions.isEmpty, !videoOutputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let now = updatedAt.isEmpty ? DateFormats.now() : updatedAt
        let version = VideoSegmentVersionDocument(
            versionId: "clipver_\(shortHash("\(segmentId):legacy:\(videoOutputPath)", length: 14))",
            versionNumber: 1,
            status: status,
            providerId: .bestAvailable,
            modelId: nil,
            providerVideoId: providerVideoId,
            providerJobId: providerJobId,
            providerOperation: providerOperation,
            providerNativeSize: providerNativeSize,
            videoOutputPath: videoOutputPath,
            normalizedVideoOutputPath: normalizedVideoOutputPath,
            startFramePath: startFrameSource.normalizedFramePath.isEmpty ? startFrameSource.framePath : startFrameSource.normalizedFramePath,
            targetEndFramePath: targetEndFrameSource.normalizedFramePath.isEmpty ? targetEndFrameSource.framePath : targetEndFrameSource.normalizedFramePath,
            actualEndFramePath: actualEndFramePath,
            prompt: prompt,
            negativePrompt: negativePrompt,
            motionDirective: motionDirective,
            createdAt: now,
            updatedAt: now
        )
        versions = [version]
        activeVersionId = version.versionId
    }

    mutating private func migrateLegacyFrameSourcesIfNeeded() {
        var startSource = startFrameSource
        migrateLegacyFrameSource(role: "start", source: &startSource)
        startFrameSource = startSource

        var targetEndSource = targetEndFrameSource
        migrateLegacyFrameSource(role: "target_end", source: &targetEndSource)
        targetEndFrameSource = targetEndSource
    }

    mutating private func migrateLegacyFrameSource(role: String, source: inout VideoFrameSourceDocument) {
        guard source.type == .generatedStill,
              source.versionId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              source.hasFrame else { return }
        let path = source.normalizedFramePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? source.framePath
            : source.normalizedFramePath
        guard !frameVersions.contains(where: { $0.role == role && $0.displayFramePath == path }) else { return }
        let versionId = "framever_\(shortHash("\(segmentId):\(role):legacy:\(path)", length: 14))"
        let version = VideoFrameVersionDocument(
            versionId: versionId,
            versionNumber: max(1, sortedFrameVersions(role: role).count + 1),
            role: role,
            status: .ready,
            framePath: source.framePath,
            normalizedFramePath: source.normalizedFramePath,
            sourceMediaId: source.mediaId,
            assistantNote: source.note,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
        frameVersions.append(version)
        source.versionId = versionId
    }
}

struct VideoSeamDocument: Codable, Hashable, Identifiable {
    var seamId: String
    var id: String { seamId }
    var fromSegmentId: String
    var toSegmentId: String
    var handoffFramePath: String = ""
    var stitchMode: String = "hard_cut_trim_duplicate"
    var status: VideoSeamStatus = .draft
}

extension VideoSeamDocument {
    enum CodingKeys: String, CodingKey {
        case seamId
        case fromSegmentId
        case toSegmentId
        case handoffFramePath
        case stitchMode
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seamId = try container.decodeIfPresent(String.self, forKey: .seamId) ?? ""
        fromSegmentId = try container.decodeIfPresent(String.self, forKey: .fromSegmentId) ?? ""
        toSegmentId = try container.decodeIfPresent(String.self, forKey: .toSegmentId) ?? ""
        handoffFramePath = try container.decodeIfPresent(String.self, forKey: .handoffFramePath) ?? ""
        stitchMode = try container.decodeIfPresent(String.self, forKey: .stitchMode) ?? "hard_cut_trim_duplicate"
        status = try container.decodeIfPresent(VideoSeamStatus.self, forKey: .status) ?? .draft
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seamId, forKey: .seamId)
        try container.encode(fromSegmentId, forKey: .fromSegmentId)
        try container.encode(toSegmentId, forKey: .toSegmentId)
        try container.encode(handoffFramePath, forKey: .handoffFramePath)
        try container.encode(stitchMode, forKey: .stitchMode)
        try container.encode(status, forKey: .status)
    }
}

enum VideoGenerationJobStatus: String, Codable, Hashable {
    case queued
    case generating
    case extractingFrame = "extracting_frame"
    case waitingForFrame = "waiting_for_frame"
    case stitching
    case ready
    case failed
    case cancelled
}

struct VideoGenerationJobDocument: Codable, Hashable, Identifiable {
    var jobId: String
    var id: String { jobId }
    var chainId: String
    var segmentId: String = ""
    var providerId: VideoProviderSelection
    var status: VideoGenerationJobStatus = .queued
    var stage: String = "queued"
    var message: String = ""
    var traceId: String = ""
    var progressCompleted: Int = 0
    var progressTotal: Int = 0
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()
}

extension VideoGenerationJobDocument {
    enum CodingKeys: String, CodingKey {
        case jobId
        case chainId
        case segmentId
        case providerId
        case status
        case stage
        case message
        case traceId
        case progressCompleted
        case progressTotal
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decodeIfPresent(String.self, forKey: .jobId) ?? ""
        chainId = try container.decodeIfPresent(String.self, forKey: .chainId) ?? ""
        segmentId = try container.decodeIfPresent(String.self, forKey: .segmentId) ?? ""
        providerId = try container.decodeIfPresent(VideoProviderSelection.self, forKey: .providerId) ?? .bestAvailable
        status = try container.decodeIfPresent(VideoGenerationJobStatus.self, forKey: .status) ?? .queued
        stage = try container.decodeIfPresent(String.self, forKey: .stage) ?? "queued"
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId) ?? ""
        progressCompleted = try container.decodeIfPresent(Int.self, forKey: .progressCompleted) ?? 0
        progressTotal = try container.decodeIfPresent(Int.self, forKey: .progressTotal) ?? 0
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? DateFormats.now()
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jobId, forKey: .jobId)
        try container.encode(chainId, forKey: .chainId)
        try container.encode(segmentId, forKey: .segmentId)
        try container.encode(providerId, forKey: .providerId)
        try container.encode(status, forKey: .status)
        try container.encode(stage, forKey: .stage)
        try container.encode(message, forKey: .message)
        try container.encode(traceId, forKey: .traceId)
        try container.encode(progressCompleted, forKey: .progressCompleted)
        try container.encode(progressTotal, forKey: .progressTotal)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

struct VideoRenderPacket: Codable, Hashable, Identifiable {
    var packetId: String
    var id: String { packetId }
    var chainId: String
    var segmentId: String
    var providerId: VideoProviderSelection
    var modelSelection: VideoModelSelection? = nil
    var continuityMode: VideoContinuityMode
    var promptText: String
    var negativePrompt: String
    var startFramePath: String
    var targetEndFramePath: String
    var outputProfile: VideoOutputProfile
    var approvalStatus: String = "not_required"
    var renderEligible: Bool = false
    var renderBlockers: [String] = []
    var createdAt: String = DateFormats.now()
}

extension VideoRenderPacket {
    enum CodingKeys: String, CodingKey {
        case packetId
        case chainId
        case segmentId
        case providerId
        case modelSelection
        case continuityMode
        case promptText
        case negativePrompt
        case startFramePath
        case targetEndFramePath
        case outputProfile
        case approvalStatus
        case renderEligible
        case renderBlockers
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packetId = try container.decodeIfPresent(String.self, forKey: .packetId) ?? ""
        chainId = try container.decodeIfPresent(String.self, forKey: .chainId) ?? ""
        segmentId = try container.decodeIfPresent(String.self, forKey: .segmentId) ?? ""
        providerId = try container.decodeIfPresent(VideoProviderSelection.self, forKey: .providerId) ?? .bestAvailable
        modelSelection = try container.decodeIfPresent(VideoModelSelection.self, forKey: .modelSelection)
        continuityMode = try container.decodeIfPresent(VideoContinuityMode.self, forKey: .continuityMode) ?? .promptExport
        promptText = try container.decodeIfPresent(String.self, forKey: .promptText) ?? ""
        negativePrompt = try container.decodeIfPresent(String.self, forKey: .negativePrompt) ?? ""
        startFramePath = try container.decodeIfPresent(String.self, forKey: .startFramePath) ?? ""
        targetEndFramePath = try container.decodeIfPresent(String.self, forKey: .targetEndFramePath) ?? ""
        outputProfile = try container.decodeIfPresent(VideoOutputProfile.self, forKey: .outputProfile) ?? .standard(.landscape16x9)
        approvalStatus = try container.decodeIfPresent(String.self, forKey: .approvalStatus) ?? "not_required"
        renderEligible = try container.decodeIfPresent(Bool.self, forKey: .renderEligible) ?? false
        renderBlockers = try container.decodeIfPresent([String].self, forKey: .renderBlockers) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? DateFormats.now()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packetId, forKey: .packetId)
        try container.encode(chainId, forKey: .chainId)
        try container.encode(segmentId, forKey: .segmentId)
        try container.encode(providerId, forKey: .providerId)
        try container.encodeIfPresent(modelSelection, forKey: .modelSelection)
        try container.encode(continuityMode, forKey: .continuityMode)
        try container.encode(promptText, forKey: .promptText)
        try container.encode(negativePrompt, forKey: .negativePrompt)
        try container.encode(startFramePath, forKey: .startFramePath)
        try container.encode(targetEndFramePath, forKey: .targetEndFramePath)
        try container.encode(outputProfile, forKey: .outputProfile)
        try container.encode(approvalStatus, forKey: .approvalStatus)
        try container.encode(renderEligible, forKey: .renderEligible)
        try container.encode(renderBlockers, forKey: .renderBlockers)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct VideoChainDocument: Codable, Hashable, Identifiable {
    var schemaVersion: String = "litscenes.video_chain.v0.1"
    var chainId: String
    var id: String { chainId }
    var projectId: String
    var title: String
    var sourceArtifactType: SceneSourceArtifactType
    var sourceArtifactId: String
    var sourceProjectStoryId: String = ""
    var sourceBeatBoardId: String = ""
    var sourceBoardFingerprint: String = ""
    var preset: VideoChainPreset = .youtubeStoryReel
    var providerSelection: VideoProviderSelection = .bestAvailable
    var selectedProviderId: VideoProviderSelection = .bestAvailable
    var modelSelection: VideoModelSelection? = .auto
    var selectedModelId: VideoModelSelection? = .auto
    var continuityMode: VideoContinuityMode = .promptExport
    var outputProfile: VideoOutputProfile = .standard(.landscape16x9)
    var targetTotalSeconds: Int = 32
    var status: VideoChainStatus = .draft
    var segments: [VideoSegmentDocument] = []
    var seams: [VideoSeamDocument] = []
    var jobs: [VideoGenerationJobDocument] = []
    var renderPackets: [VideoRenderPacket] = []
    var preflightBlockers: [String] = []
    var preflightWarnings: [String] = []
    var approvalToken: String = ""
    var approvedAt: String = ""
    var stitchedOutputPath: String = ""
    var stitchedOutputMediaId: String? = nil
    var manifestJSONPath: String = ""
    var manifestMarkdownPath: String = ""
    var createdAt: String = DateFormats.now()
    var updatedAt: String = DateFormats.now()

    static func empty(projectId: String = "") -> VideoChainDocument {
        VideoChainDocument(
            chainId: "",
            projectId: projectId,
            title: "",
            sourceArtifactType: .beatBoard,
            sourceArtifactId: ""
        )
    }

    static func decode(from data: Data) throws -> VideoChainDocument {
        try JSONCoding.decoder.decode(VideoChainDocument.self, from: data)
    }

    func encoded(pretty: Bool = true) throws -> Data {
        try (pretty ? JSONCoding.prettyEncoder : JSONCoding.encoder).encode(self)
    }
}

extension VideoChainDocument {
    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case chainId
        case projectId
        case title
        case sourceArtifactType
        case sourceArtifactId
        case sourceProjectStoryId
        case sourceBeatBoardId
        case sourceBoardFingerprint
        case preset
        case providerSelection
        case selectedProviderId
        case modelSelection
        case selectedModelId
        case continuityMode
        case outputProfile
        case targetTotalSeconds
        case status
        case segments
        case seams
        case jobs
        case renderPackets
        case preflightBlockers
        case preflightWarnings
        case approvalToken
        case approvedAt
        case stitchedOutputPath
        case stitchedOutputMediaId
        case manifestJSONPath = "manifestJsonPath"
        case manifestJSONPathLegacy = "manifestJSONPath"
        case manifestMarkdownPath
        case createdAt
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "litscenes.video_chain.v0.1"
        chainId = try container.decodeIfPresent(String.self, forKey: .chainId) ?? ""
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        sourceArtifactType = try container.decodeIfPresent(SceneSourceArtifactType.self, forKey: .sourceArtifactType) ?? .beatBoard
        sourceArtifactId = try container.decodeIfPresent(String.self, forKey: .sourceArtifactId) ?? ""
        sourceProjectStoryId = try container.decodeIfPresent(String.self, forKey: .sourceProjectStoryId) ?? ""
        sourceBeatBoardId = try container.decodeIfPresent(String.self, forKey: .sourceBeatBoardId) ?? ""
        sourceBoardFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceBoardFingerprint) ?? ""
        preset = try container.decodeIfPresent(VideoChainPreset.self, forKey: .preset) ?? .youtubeStoryReel
        providerSelection = try container.decodeIfPresent(VideoProviderSelection.self, forKey: .providerSelection) ?? .bestAvailable
        selectedProviderId = try container.decodeIfPresent(VideoProviderSelection.self, forKey: .selectedProviderId) ?? providerSelection
        modelSelection = try container.decodeIfPresent(VideoModelSelection.self, forKey: .modelSelection) ?? .auto
        selectedModelId = try container.decodeIfPresent(VideoModelSelection.self, forKey: .selectedModelId) ?? modelSelection
        continuityMode = try container.decodeIfPresent(VideoContinuityMode.self, forKey: .continuityMode) ?? .promptExport
        outputProfile = try container.decodeIfPresent(VideoOutputProfile.self, forKey: .outputProfile) ?? .standard(.landscape16x9)
        targetTotalSeconds = try container.decodeIfPresent(Int.self, forKey: .targetTotalSeconds) ?? 32
        status = try container.decodeIfPresent(VideoChainStatus.self, forKey: .status) ?? .draft
        segments = try container.decodeIfPresent([VideoSegmentDocument].self, forKey: .segments) ?? []
        seams = try container.decodeIfPresent([VideoSeamDocument].self, forKey: .seams) ?? []
        jobs = try container.decodeIfPresent([VideoGenerationJobDocument].self, forKey: .jobs) ?? []
        renderPackets = try container.decodeIfPresent([VideoRenderPacket].self, forKey: .renderPackets) ?? []
        preflightBlockers = try container.decodeIfPresent([String].self, forKey: .preflightBlockers) ?? []
        preflightWarnings = try container.decodeIfPresent([String].self, forKey: .preflightWarnings) ?? []
        approvalToken = try container.decodeIfPresent(String.self, forKey: .approvalToken) ?? ""
        approvedAt = try container.decodeIfPresent(String.self, forKey: .approvedAt) ?? ""
        stitchedOutputPath = try container.decodeIfPresent(String.self, forKey: .stitchedOutputPath) ?? ""
        stitchedOutputMediaId = try container.decodeIfPresent(String.self, forKey: .stitchedOutputMediaId)
        manifestJSONPath = try container.decodeIfPresent(String.self, forKey: .manifestJSONPath)
            ?? container.decodeIfPresent(String.self, forKey: .manifestJSONPathLegacy)
            ?? ""
        manifestMarkdownPath = try container.decodeIfPresent(String.self, forKey: .manifestMarkdownPath) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? DateFormats.now()
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(chainId, forKey: .chainId)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(title, forKey: .title)
        try container.encode(sourceArtifactType, forKey: .sourceArtifactType)
        try container.encode(sourceArtifactId, forKey: .sourceArtifactId)
        try container.encode(sourceProjectStoryId, forKey: .sourceProjectStoryId)
        try container.encode(sourceBeatBoardId, forKey: .sourceBeatBoardId)
        try container.encode(sourceBoardFingerprint, forKey: .sourceBoardFingerprint)
        try container.encode(preset, forKey: .preset)
        try container.encode(providerSelection, forKey: .providerSelection)
        try container.encode(selectedProviderId, forKey: .selectedProviderId)
        try container.encodeIfPresent(modelSelection, forKey: .modelSelection)
        try container.encodeIfPresent(selectedModelId, forKey: .selectedModelId)
        try container.encode(continuityMode, forKey: .continuityMode)
        try container.encode(outputProfile, forKey: .outputProfile)
        try container.encode(targetTotalSeconds, forKey: .targetTotalSeconds)
        try container.encode(status, forKey: .status)
        try container.encode(segments, forKey: .segments)
        try container.encode(seams, forKey: .seams)
        try container.encode(jobs, forKey: .jobs)
        try container.encode(renderPackets, forKey: .renderPackets)
        try container.encode(preflightBlockers, forKey: .preflightBlockers)
        try container.encode(preflightWarnings, forKey: .preflightWarnings)
        try container.encode(approvalToken, forKey: .approvalToken)
        try container.encode(approvedAt, forKey: .approvedAt)
        try container.encode(stitchedOutputPath, forKey: .stitchedOutputPath)
        try container.encodeIfPresent(stitchedOutputMediaId, forKey: .stitchedOutputMediaId)
        try container.encode(manifestJSONPath, forKey: .manifestJSONPath)
        try container.encode(manifestMarkdownPath, forKey: .manifestMarkdownPath)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

extension VideoChainDocument {
    var requiresTargetEndFrames: Bool {
        selectedProviderId == .civitaiWan || continuityMode == .keyframedChain
    }

    var missingTargetEndFrameCount: Int {
        guard requiresTargetEndFrames else { return 0 }
        return segments.filter { !$0.targetEndFrameSource.hasFrame }.count
    }

    var missingStartFrameCount: Int {
        segments.filter { segment in
            segment.order == 1 && !segment.startFrameSource.hasFrame
        }.count
    }

    var clipSummary: String {
        let duration = segments.reduce(0) { $0 + $1.durationSeconds }
        return "\(segments.count) clips · \(duration)s · \(outputProfile.aspectRatio.rawValue)"
    }

    static func draft(
        projectId: String,
        sourceArtifactType: SceneSourceArtifactType,
        sourceArtifactId: String,
        sourceProjectStoryId: String,
        beatBoard: StoryBeatBoard,
        beats: [StoryBeatBoardBeat],
        preset: VideoChainPreset,
        providerSelection: VideoProviderSelection,
        modelSelection: VideoModelSelection = .auto,
        createdAt: String = DateFormats.now()
    ) -> VideoChainDocument {
        let selectedProvider = resolvedProvider(
            requested: providerSelection,
            outputProfile: preset.outputProfile,
            durationSeconds: preset.durationSeconds,
            segmentsHaveTargetFrames: false
        )
        let selectedModel = VideoModelSelection.resolved(requested: modelSelection, provider: selectedProvider)
        let chainId = "chain_\(shortHash("\(projectId):\(sourceArtifactId):\(preset.rawValue):\(createdAt)", length: 16))"
        let visibleBeats = beats.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
        let segments = makeSegments(
            chainId: chainId,
            beats: visibleBeats,
            preset: preset,
            outputProfile: preset.outputProfile
        )
        return VideoChainDocument(
            chainId: chainId,
            projectId: projectId,
            title: "\(preset.label) V1",
            sourceArtifactType: sourceArtifactType,
            sourceArtifactId: sourceArtifactId,
            sourceProjectStoryId: sourceProjectStoryId,
            sourceBeatBoardId: beatBoard.beatBoardId,
            sourceBoardFingerprint: beatBoard.inputFingerprint.stableId,
            preset: preset,
            providerSelection: providerSelection,
            selectedProviderId: selectedProvider,
            modelSelection: modelSelection,
            selectedModelId: selectedModel,
            continuityMode: selectedProvider.continuityMode,
            outputProfile: preset.outputProfile,
            targetTotalSeconds: segments.reduce(0) { $0 + $1.durationSeconds },
            status: segments.isEmpty ? .draft : .planned,
            segments: segments,
            seams: makeSeams(segments: segments),
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    static func resolvedProvider(
        requested: VideoProviderSelection,
        outputProfile: VideoOutputProfile,
        durationSeconds: Int,
        segmentsHaveTargetFrames: Bool,
        credentialStore: LitScenesCredentialResolving = LitScenesCredentialStore()
    ) -> VideoProviderSelection {
        let requested = requested == .localPromptExport ? .bestAvailable : requested
        if requested != .bestAvailable {
            return requested
        }
        let wan = VideoProviderCapability.capability(for: .civitaiWan, outputProfile: outputProfile, durationSeconds: durationSeconds, credentialStore: credentialStore)
        let kling = VideoProviderCapability.capability(for: .klingImageToVideo, outputProfile: outputProfile, durationSeconds: durationSeconds, credentialStore: credentialStore)
        let ltx = VideoProviderCapability.capability(for: .ltxDirect, outputProfile: outputProfile, durationSeconds: durationSeconds, credentialStore: credentialStore)
        if segmentsHaveTargetFrames, wan.canRender {
            return .civitaiWan
        }
        if kling.canRender {
            return .klingImageToVideo
        }
        if ltx.canRender {
            return .ltxDirect
        }
        if wan.canRender {
            return .civitaiWan
        }
        return .bestAvailable
    }

    private static func makeSegments(
        chainId: String,
        beats: [StoryBeatBoardBeat],
        preset: VideoChainPreset,
        outputProfile: VideoOutputProfile
    ) -> [VideoSegmentDocument] {
        guard !beats.isEmpty else { return [] }
        let count = min(max(1, preset.clipCount), max(1, beats.count))
        let roles = clipRoles(for: count)
        return (0..<count).map { index in
            let start = Int(Double(index) * Double(beats.count) / Double(count))
            let end = max(start + 1, Int(Double(index + 1) * Double(beats.count) / Double(count)))
            let group = Array(beats[start..<min(end, beats.count)])
            let role = roles[min(index, roles.count - 1)]
            let beatIds = group.map(\.beatId)
            let title = "\(role): \(group.first?.title ?? "Story Moment")"
            return VideoSegmentDocument(
                segmentId: "seg_\(String(format: "%02d", index + 1))_\(shortHash("\(chainId):\(index):\(beatIds.joined(separator: ","))", length: 8))",
                order: index + 1,
                sourceBeatIds: beatIds,
                title: title,
                durationSeconds: preset.durationSeconds,
                prompt: prompt(for: group, role: role, outputProfile: outputProfile),
                negativePrompt: group.flatMap { $0.generationBrief.negativeConstraints }.uniqued().joined(separator: "\n"),
                motionDirective: motionDirective(for: group, role: role),
                startFrameSource: index == 0
                    ? VideoFrameSourceDocument(type: .none, note: "Select a project image, source-media still, or attach a start frame.")
                    : VideoFrameSourceDocument(type: .previousSegmentEnd, note: "Will use previous clip actual final frame."),
                status: index == 0 ? .needsStartFrame : .draft,
                fitPolicy: outputProfile.fitPolicy,
                sourceFingerprint: stableHash(group.map(StoryBeatBoardBeatSnapshot.fromBeat))
            )
        }
    }

    private static func makeSeams(segments: [VideoSegmentDocument]) -> [VideoSeamDocument] {
        zip(segments, segments.dropFirst()).map { previous, next in
            VideoSeamDocument(
                seamId: "seam_\(previous.segmentId)_\(next.segmentId)",
                fromSegmentId: previous.segmentId,
                toSegmentId: next.segmentId
            )
        }
    }

    private static func clipRoles(for count: Int) -> [String] {
        switch count {
        case 1: ["Hook"]
        case 2: ["Hook", "Payoff"]
        case 3: ["Hook", "Transformation", "Payoff"]
        case 5: ["Hook", "Proof", "Escalation", "Turn", "Payoff"]
        default: ["Hook", "Proof", "Escalation", "Payoff"]
        }
    }

    private static func prompt(for beats: [StoryBeatBoardBeat], role: String, outputProfile: VideoOutputProfile) -> String {
        let beatLines = beats.map { beat in
            [
                "Beat \(beat.order): \(beat.title)",
                beat.event,
                beat.visualMoment,
                beat.meaningMove,
                beat.promptReadyLine,
                "Action: \(beat.generationBrief.action)",
                "Setting: \(beat.generationBrief.setting)",
                "Treatment: \(beat.generationBrief.aestheticTreatment)"
            ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        }
        return [
            "Create an \(outputProfile.aspectRatio.rawValue) video clip for the \(role) segment.",
            "Preserve story facts and source-media truth. Do not invent unsupported people, claims, or events.",
            beatLines.joined(separator: "\n\n"),
            "Motion should be cinematic but readable, with continuity into the next clip."
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private static func motionDirective(for beats: [StoryBeatBoardBeat], role: String) -> String {
        let camera = beats.map(\.generationBrief.cameraOrFraming).filter { !$0.isEmpty }.prefix(2).joined(separator: "; ")
        if !camera.isEmpty {
            return camera
        }
        switch role {
        case "Hook": return "slow establishing push-in"
        case "Proof": return "controlled reveal with visible evidence"
        case "Escalation": return "increasing motion and tension"
        case "Turn": return "measured pivot into the final meaning"
        default: return "steady final image with soft landing"
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
