import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shot timeline document (project-level, persisted)

/// One position in a shot's frame strip. Deliberately minimal: meaning
/// connective tissue is DERIVED (see the strand section below), never stored
/// per entry — rows stay honest. A non-empty `clipMediaId` makes the entry
/// FOOTAGE: a real video (source or Studio trim) whose pixels land verbatim
/// in the rendered reel; `frameImageId` stays empty for those.
struct ShotFrameEntry: Codable, Hashable, Identifiable, Sendable {
    var entryId: String = ""
    var frameImageId: String = ""
    var clipMediaId: String = ""
    /// Optional narrowing of the clip; nil bounds mean the asset's own edges
    /// (a Studio trim IS already its range, so drops carry nil/nil).
    var clipStartSeconds: Double? = nil
    var clipEndSeconds: Double? = nil
    /// How this entry JOINS the previous one: "" auto (bridge on
    /// frame-adjacent seams, cut on clip→clip), "bridge", or "cut". Rides the
    /// RIGHT entry of a seam and travels with it on reorder; ignored on the
    /// first entry. Resolution happens in `resolvedShotSeamStyle`.
    var leadTransition: String = ""
    /// An AI extension: an open-ended generated segment that picks up from
    /// its LEFT neighbor's final frame (no destination keyframe). Its prompt
    /// is editable via the open-ended segment override key.
    var isAIExtension: Bool = false
    /// Skipped: the entry stays in the strip (restorable, keeps its keys and
    /// overrides) but contributes nothing to the plan; the seam its absence
    /// creates between surviving neighbors always heals to a hard cut.
    var isSkipped: Bool = false

    var id: String { entryId }

    var isClip: Bool { !clipMediaId.isEmpty }

    var leadSeamPreference: ShotSeamStyle {
        ShotSeamStyle(rawValue: leadTransition) ?? .auto
    }

    private enum CodingKeys: String, CodingKey {
        case entryId
        case frameImageId
        case clipMediaId
        case clipStartSeconds
        case clipEndSeconds
        case leadTransition
        case isAIExtension
        case isSkipped
    }

    init(
        entryId: String = "",
        frameImageId: String = "",
        clipMediaId: String = "",
        clipStartSeconds: Double? = nil,
        clipEndSeconds: Double? = nil,
        leadTransition: String = "",
        isAIExtension: Bool = false,
        isSkipped: Bool = false
    ) {
        self.entryId = entryId
        self.frameImageId = frameImageId
        self.clipMediaId = clipMediaId
        self.clipStartSeconds = clipStartSeconds
        self.clipEndSeconds = clipEndSeconds
        self.leadTransition = leadTransition
        self.isAIExtension = isAIExtension
        self.isSkipped = isSkipped
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryId = try container.decodeIfPresent(String.self, forKey: .entryId) ?? ""
        frameImageId = try container.decodeIfPresent(String.self, forKey: .frameImageId) ?? ""
        clipMediaId = try container.decodeIfPresent(String.self, forKey: .clipMediaId) ?? ""
        clipStartSeconds = try container.decodeIfPresent(Double.self, forKey: .clipStartSeconds)
        clipEndSeconds = try container.decodeIfPresent(Double.self, forKey: .clipEndSeconds)
        leadTransition = try container.decodeIfPresent(String.self, forKey: .leadTransition) ?? ""
        isAIExtension = try container.decodeIfPresent(Bool.self, forKey: .isAIExtension) ?? false
        isSkipped = try container.decodeIfPresent(Bool.self, forKey: .isSkipped) ?? false
    }

    /// Non-destructive per-placement narrowing: bounds equal to the asset's
    /// own edges normalize back to nil ("whole asset").
    func settingClipRange(
        startSeconds: Double?,
        endSeconds: Double?,
        assetDurationSeconds: Double
    ) -> ShotFrameEntry {
        guard isClip else { return self }
        var value = self
        let duration = max(assetDurationSeconds, 0)
        let low = startSeconds.map { min(max($0, 0), duration) }
        let high = endSeconds.map { min(max($0, 0), duration) }
        value.clipStartSeconds = (low ?? 0) <= 0.01 ? nil : low
        value.clipEndSeconds = (high ?? duration) >= duration - 0.01 ? nil : high
        if let start = value.clipStartSeconds, let end = value.clipEndSeconds, end < start {
            value.clipStartSeconds = end
            value.clipEndSeconds = start
        }
        return value
    }
}

/// Repeated Clip Inspector clicks used to append adjacent extension markers
/// even though the plan can render only the first marker beside real
/// material. Keep that one canonical placement and discard the structurally
/// inert followers during tolerant document normalization.
func collapsingConsecutiveAIExtensionEntries(
    _ entries: [ShotFrameEntry]
) -> [ShotFrameEntry] {
    var collapsed: [ShotFrameEntry] = []
    collapsed.reserveCapacity(entries.count)
    for entry in entries {
        if entry.isAIExtension, collapsed.last?.isAIExtension == true {
            continue
        }
        collapsed.append(entry)
    }
    return collapsed
}

/// The per-seam grammar: a seam between adjacent entries is either a BRIDGE
/// (one generated transition segment) or a CUT (hard join, zero generation).
enum ShotSeamStyle: String, Sendable {
    case auto = ""
    case bridge
    case cut

    var toggled: ShotSeamStyle {
        self == .cut ? .bridge : .cut
    }
}

/// Who is asking for a seam change. THE SEAM BOUNDARY LAW: a skip-restore
/// returns what skip hid and never touches `sourceBoundaries`; only the
/// operator's explicit ‖/≈ toggle may delete a boundary row — an explicitly
/// rendered bridge re-establishes pixel continuity, which is what makes the
/// duplicate-handoff shave correct again. Before this distinction existed,
/// restoring a skipped seam silently deleted the boundary and cost the right
/// clip a permanent 3-frame head shave.
enum ShotSeamEditIntent: Sendable {
    case explicit
    case restoreSkipped
}

/// Resolution law, the single derivation every surface reads: an explicit
/// preference on the right entry always wins — including frame→frame, where
/// an explicit cut IS "skip this generated segment" (the pair between the two
/// stills simply doesn't render; frames no bridge reaches are reported, never
/// silently dropped). Auto = cut for clip→clip, bridge everywhere else
/// (frame→frame in particular still auto-bridges: stills aren't playable
/// material on their own).
func resolvedShotSeamStyle(
    leftIsClip: Bool,
    rightIsClip: Bool,
    rightPreference: ShotSeamStyle
) -> ShotSeamStyle {
    switch rightPreference {
    case .bridge:
        return .bridge
    case .cut:
        return .cut
    case .auto:
        return (leftIsClip && rightIsClip) ? .cut : .bridge
    }
}

/// True when a seam's style is the user's to choose (shown as a toggle):
/// at least one side is footage.
func shotSeamIsToggleable(leftIsClip: Bool, rightIsClip: Bool) -> Bool {
    leftIsClip || rightIsClip
}

/// How a razor-created edit point plays. Hard cut is the tolerant default;
/// dissolve is local/free; generatedBridge names one immutable paid artifact.
enum ShotRazorJoinRepairMode: String, Codable, CaseIterable, Sendable {
    case hardCut = "hard_cut"
    case dissolve
    case generatedBridge = "generated_bridge"
}

struct ShotRazorJoinRepair: Codable, Hashable, Sendable {
    var mode: ShotRazorJoinRepairMode = .hardCut
    var dissolveFrames: Int = 12
    var activeBridgeVersionId: String = ""

    func normalized() -> ShotRazorJoinRepair {
        var value = self
        value.dissolveFrames = [6, 12, 24].min(by: {
            abs($0 - value.dissolveFrames) < abs($1 - value.dissolveFrames)
        }) ?? 12
        value.activeBridgeVersionId = value.activeBridgeVersionId.trimmed
        if value.mode != .generatedBridge {
            value.activeBridgeVersionId = ""
        }
        return value
    }

    func gapCappedDissolveFrames(gapSeconds: Double, framesPerSecond: Double = 24) -> Int {
        guard mode == .dissolve else { return 0 }
        let gapCapacity = Int(floor(max(gapSeconds, 0) * framesPerSecond * 2 + 0.000_1))
        return min(dissolveFrames, max(gapCapacity, 0))
    }
}

/// The deliberately narrow render stacks executable from a razor join.
/// These do not appear in the general Shot/video-chain provider selector.
enum ShotJoinBridgeProvider: String, Codable, CaseIterable, Sendable {
    case falViduQ3 = "fal_vidu_q3"
    case falKlingO1 = "fal_kling_o1"

    var label: String {
        switch self {
        case .falViduQ3: return "FAL · VIDU Q3"
        case .falKlingO1: return "FAL · KLING O1"
        }
    }

    var modelId: String {
        switch self {
        case .falViduQ3: return "fal-ai/vidu/q3/image-to-video"
        case .falKlingO1: return "fal-ai/kling-video/o1/standard/image-to-video"
        }
    }

    var supportedDurations: [Int] {
        switch self {
        case .falViduQ3: return [1, 2, 3]
        case .falKlingO1: return [3]
        }
    }

    var defaultDuration: Int { self == .falViduQ3 ? 2 : 3 }
}

enum ShotJoinBridgePrompt {
    static let defaultText = """
        Smooth continuous camera and subject motion from @Image1 to @Image2. Preserve the same subject, scene identity, and spatial logic while reframing naturally. No cuts, flicker, text, captions, or logos.
        """
}

struct ShotJoinBoundaryPreview: Sendable {
    var outgoingURL: URL
    var incomingURL: URL
    var fingerprint: String
}

/// Immutable provenance for one short generated repair attempt/version.
/// Artifacts remain on the Shot when their cut is restored or becomes stale.
struct ShotJoinBridgeArtifact: Codable, Hashable, Identifiable, Sendable {
    var versionId: String = ""
    var cutId: String = ""
    var sourceSegmentKey: String = ""
    var sourceClipPath: String = ""
    var cutStartSeconds: Double = 0
    var cutEndSeconds: Double = 0
    var boundaryFingerprint: String = ""
    var provider: String = ""
    var model: String = ""
    /// Actual downloaded media duration. The reviewed native request duration
    /// is integral, but playback/ripple use this measured value.
    var durationSeconds: Double = 0
    var prompt: String = ""
    var resolution: String = ""
    var status: String = ""  // generating | ready | failed
    var videoPath: String = ""
    var outgoingFramePath: String = ""
    var incomingFramePath: String = ""
    var requestId: String = ""
    var errorMessage: String = ""
    var generatedAt: String = ""
    var updatedAt: String = ""

    var id: String { versionId }
    var isReady: Bool { status == "ready" && !videoPath.isEmpty }

    func normalized() -> ShotJoinBridgeArtifact {
        var value = self
        value.versionId = value.versionId.trimmed
        value.cutId = value.cutId.trimmed
        value.sourceSegmentKey = value.sourceSegmentKey.trimmed
        value.sourceClipPath = value.sourceClipPath.trimmed
        value.cutStartSeconds = max(value.cutStartSeconds, 0)
        value.cutEndSeconds = max(value.cutEndSeconds, value.cutStartSeconds)
        value.boundaryFingerprint = value.boundaryFingerprint.trimmed
        value.provider = value.provider.trimmed
        value.model = value.model.trimmed
        value.durationSeconds = max(value.durationSeconds.isFinite ? value.durationSeconds : 0, 0)
        value.prompt = value.prompt.trimmed
        value.resolution = value.resolution.trimmed
        value.status = value.status.trimmed
        value.videoPath = value.videoPath.trimmed
        value.outgoingFramePath = value.outgoingFramePath.trimmed
        value.incomingFramePath = value.incomingFramePath.trimmed
        value.requestId = value.requestId.trimmed
        value.errorMessage = value.errorMessage.trimmed
        value.generatedAt = value.generatedAt.trimmed
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

/// One frame-exact reversed copy of a source clip, baked locally so a reversed
/// CUT can play — AVFoundation compositions cannot run backwards.
///
/// Content-addressed by the source file's identity (path + size + mtime +
/// baker version), which buys two things: two shots on the same take share one
/// bake, and a re-render needs no invalidation pass at all — its new clip paths
/// simply stop matching, so nothing stale can ever be played.
struct ShotReverseProxyArtifact: Codable, Hashable, Identifiable, Sendable {
    /// Also the filename stem. See `ReverseProxyBaker.cacheKey(sourcePath:)`.
    var proxyId: String = ""
    var sourcePath: String = ""
    var sourceByteCount: Int64 = 0
    var sourceModifiedAt: String = ""
    /// The VISUAL-track duration that was reversed — the mirror law's `D`.
    /// Never the container duration: embedded audio commonly runs past picture,
    /// and mirroring against the overhang shifts every kept span.
    var sourceDurationSeconds: Double = 0
    /// Measured back off the written file, not assumed from the source.
    var proxyDurationSeconds: Double = 0
    var frameCount: Int = 0
    var proxyPath: String = ""
    /// False when the source had no audio, or when verification rejected the
    /// reversed audio and it was stripped — a silent proxy is honest, an
    /// out-of-sync one is not.
    var hasReversedAudio: Bool = false
    var bakerVersion: Int = 0
    var status: String = ""  // baking | ready | failed
    var errorMessage: String = ""
    var startedAt: String = ""
    var updatedAt: String = ""

    var id: String { proxyId }
    var isReady: Bool { status == "ready" && !proxyPath.isEmpty && proxyDurationSeconds > 0 }

    func normalized() -> ShotReverseProxyArtifact {
        var value = self
        value.proxyId = value.proxyId.trimmed
        value.sourcePath = value.sourcePath.trimmed
        value.sourceByteCount = max(value.sourceByteCount, 0)
        value.sourceModifiedAt = value.sourceModifiedAt.trimmed
        value.sourceDurationSeconds = max(
            value.sourceDurationSeconds.isFinite ? value.sourceDurationSeconds : 0,
            0
        )
        value.proxyDurationSeconds = max(
            value.proxyDurationSeconds.isFinite ? value.proxyDurationSeconds : 0,
            0
        )
        value.frameCount = max(value.frameCount, 0)
        value.proxyPath = value.proxyPath.trimmed
        value.bakerVersion = max(value.bakerVersion, 0)
        value.status = value.status.trimmed
        value.errorMessage = value.errorMessage.trimmed
        value.startedAt = value.startedAt.trimmed
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

enum ShotLookProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    static let preferenceKey = "LITSCENES_SHOT_LOOK_PROVIDER"

    case fal
    case decart

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fal: "FAL (text input)"
        case .decart: "Decart (image input)"
        }
    }

    var modelId: String {
        switch self {
        case .fal: "decart/lucy-restyle"
        case .decart: "lucy-restyle-2"
        }
    }

    var inputMode: String {
        switch self {
        case .fal: "text"
        case .decart: "reference_image"
        }
    }

    var credentialProvider: LitScenesProviderCredential {
        switch self {
        case .fal: .fal
        case .decart: .decart
        }
    }

    static func resolved(_ rawValue: String) -> ShotLookProvider {
        ShotLookProvider(rawValue: rawValue.trimmed.lowercased()) ?? .fal
    }
}

/// A catalog style chosen for a Shot or Clip Look. Its text summary feeds
/// FAL; its hash-verified image snapshot feeds direct Decart. Capturing both
/// at pick time keeps submission and recovery independent of catalog drift.
struct ShotLookStyleSelection: Codable, Hashable, Sendable {
    var styleId = ""
    var label = ""
    var collection = ""
    var hueHex = ""
    var url = ""
    var summary = ""
    var catalogVersion = ""
    var imageReference: SREFStyleImageReference?

    var isUsable: Bool { !styleId.trimmed.isEmpty && !summary.trimmed.isEmpty }
    var hasUsableImageReference: Bool {
        guard let reference = imageReference?.normalized() else { return false }
        return !styleId.trimmed.isEmpty
            && !reference.url.isEmpty
            && !reference.sha256.isEmpty
    }
}

/// The single law joining a chosen style and the operator's notes into the
/// Lucy prompt. Uncapped on purpose: the composer counts and blocks on this
/// exact text, the engine caps with prefix(1_500) — style line first, so
/// truncation eats the note tail, never the style direction.
func shotLookComposedPrompt(styleSummary: String, userText: String) -> String {
    let styleLine = styleSummary.trimmed.isEmpty ? "" : "Style direction: \(styleSummary.trimmed)"
    return [styleLine, userText.trimmed].filter { !$0.isEmpty }.joined(separator: "\n\n")
}

/// A paid, immutable picture finish derived from one exact Original edit.
/// Workflow fields are deliberately tolerant strings so an interrupted queue
/// request can survive app upgrades and resume without another paid submit.
struct ShotRestyleArtifact: Codable, Hashable, Identifiable, Sendable {
    var versionId: String = ""
    var versionNumber: Int = 0
    var status: String = "" // preparing | uploading | queued | generating | downloading | paused | ready | failed | canceled
    var sourceShotId: String = ""
    var sourceRenderVersionId: String = ""
    var sourceVisualFingerprint: String = ""
    /// Which way round the Original ran when this Look was flattened.
    /// A Look is an immutable finishing pass over the edit it was made from, so
    /// its audio must keep being assembled in THIS direction even while the
    /// Original is being watched the other way.
    var sourceIsReversed: Bool = false
    var sourceVideoPath: String = ""
    var sourceVideoSHA256: String = ""
    var sourceDurationSeconds: Double = 0
    var prompt: String = ""
    var enhancePrompt: Bool = true
    var seed: Int = 0
    var resolution: String = "720p"
    var provider: String = "fal"
    var model: String = "decart/lucy-restyle"
    var inputMode: String = "text"
    var requestId: String = ""
    var traceId: String = ""
    var inputRemoteURL: String = ""
    var outputRemoteURL: String = ""
    var estimatedCostUSD: Double = 0
    var estimatedCostCredits: Double = 0
    var pricingUnit: String = "usd_per_source_second"
    var pricingRate: Double = 0.01
    var videoPath: String = ""
    var outputDurationSeconds: Double = 0
    var errorMessage: String = ""
    var styleId: String = ""
    var styleLabel: String = ""
    var styleCollection: String = ""
    var styleHueHex: String = ""
    var styleSummary: String = ""
    var styleCatalogVersion: String = ""
    var styleImageReference: SREFStyleImageReference?
    /// Clip Look provenance: set only when this artifact restyles a placed
    /// footage range instead of a Shot Original. Empty mediaId = shot look.
    var sourceClipMediaId: String = ""
    var sourceClipStartSeconds: Double = 0
    var sourceClipEndSeconds: Double = 0
    /// The archived Footage-tray media once ready; the artifact is a job log.
    var outputMediaId: String = ""
    var generatedAt: String = ""
    var updatedAt: String = ""

    var id: String { versionId }
    var isReady: Bool { status == "ready" && !videoPath.isEmpty }
    var durationDeltaSeconds: Double { outputDurationSeconds - sourceDurationSeconds }
    var isClipLook: Bool { !sourceClipMediaId.trimmed.isEmpty }
    var clipRangeSeconds: Double { max(sourceClipEndSeconds - sourceClipStartSeconds, 0) }
    var restyleProvider: ShotLookProvider { ShotLookProvider.resolved(provider) }
    var canCancelRemotely: Bool { restyleProvider == .fal }

    init(
        versionId: String = "",
        versionNumber: Int = 0,
        status: String = "",
        sourceShotId: String = "",
        sourceRenderVersionId: String = "",
        sourceVisualFingerprint: String = "",
        sourceIsReversed: Bool = false,
        sourceVideoPath: String = "",
        sourceVideoSHA256: String = "",
        sourceDurationSeconds: Double = 0,
        prompt: String = "",
        enhancePrompt: Bool = true,
        seed: Int = 0,
        resolution: String = "720p",
        provider: String = "fal",
        model: String = "decart/lucy-restyle",
        inputMode: String = "text",
        requestId: String = "",
        traceId: String = "",
        inputRemoteURL: String = "",
        outputRemoteURL: String = "",
        estimatedCostUSD: Double = 0,
        estimatedCostCredits: Double = 0,
        pricingUnit: String = "usd_per_source_second",
        pricingRate: Double = 0.01,
        videoPath: String = "",
        outputDurationSeconds: Double = 0,
        errorMessage: String = "",
        styleId: String = "",
        styleLabel: String = "",
        styleCollection: String = "",
        styleHueHex: String = "",
        styleSummary: String = "",
        styleCatalogVersion: String = "",
        styleImageReference: SREFStyleImageReference? = nil,
        sourceClipMediaId: String = "",
        sourceClipStartSeconds: Double = 0,
        sourceClipEndSeconds: Double = 0,
        outputMediaId: String = "",
        generatedAt: String = "",
        updatedAt: String = ""
    ) {
        self.versionId = versionId
        self.versionNumber = versionNumber
        self.status = status
        self.sourceShotId = sourceShotId
        self.sourceRenderVersionId = sourceRenderVersionId
        self.sourceVisualFingerprint = sourceVisualFingerprint
        self.sourceIsReversed = sourceIsReversed
        self.sourceVideoPath = sourceVideoPath
        self.sourceVideoSHA256 = sourceVideoSHA256
        self.sourceDurationSeconds = sourceDurationSeconds
        self.prompt = prompt
        self.enhancePrompt = enhancePrompt
        self.seed = seed
        self.resolution = resolution
        self.provider = provider
        self.model = model
        self.inputMode = inputMode
        self.requestId = requestId
        self.traceId = traceId
        self.inputRemoteURL = inputRemoteURL
        self.outputRemoteURL = outputRemoteURL
        self.estimatedCostUSD = estimatedCostUSD
        self.estimatedCostCredits = estimatedCostCredits
        self.pricingUnit = pricingUnit
        self.pricingRate = pricingRate
        self.videoPath = videoPath
        self.outputDurationSeconds = outputDurationSeconds
        self.errorMessage = errorMessage
        self.styleId = styleId
        self.styleLabel = styleLabel
        self.styleCollection = styleCollection
        self.styleHueHex = styleHueHex
        self.styleSummary = styleSummary
        self.styleCatalogVersion = styleCatalogVersion
        self.styleImageReference = styleImageReference
        self.sourceClipMediaId = sourceClipMediaId
        self.sourceClipStartSeconds = sourceClipStartSeconds
        self.sourceClipEndSeconds = sourceClipEndSeconds
        self.outputMediaId = outputMediaId
        self.generatedAt = generatedAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case versionId, versionNumber, status, sourceShotId, sourceRenderVersionId
        case sourceVisualFingerprint, sourceIsReversed, sourceVideoPath, sourceVideoSHA256, sourceDurationSeconds
        case prompt, enhancePrompt, seed, resolution, provider, model, inputMode, requestId, traceId
        case inputRemoteURL, outputRemoteURL, estimatedCostUSD, estimatedCostCredits, pricingUnit
        case pricingRate, videoPath, outputDurationSeconds
        case errorMessage, styleId, styleLabel, styleCollection, styleHueHex, styleSummary
        case styleCatalogVersion, styleImageReference, sourceClipMediaId, sourceClipStartSeconds, sourceClipEndSeconds
        case outputMediaId, generatedAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        versionId = try container.decodeIfPresent(String.self, forKey: .versionId) ?? ""
        versionNumber = try container.decodeIfPresent(Int.self, forKey: .versionNumber) ?? 0
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        sourceShotId = try container.decodeIfPresent(String.self, forKey: .sourceShotId) ?? ""
        sourceRenderVersionId = try container.decodeIfPresent(String.self, forKey: .sourceRenderVersionId) ?? ""
        sourceVisualFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceVisualFingerprint) ?? ""
        sourceIsReversed = ((try? container.decodeIfPresent(Bool.self, forKey: .sourceIsReversed)) ?? nil) ?? false
        sourceVideoPath = try container.decodeIfPresent(String.self, forKey: .sourceVideoPath) ?? ""
        sourceVideoSHA256 = try container.decodeIfPresent(String.self, forKey: .sourceVideoSHA256) ?? ""
        sourceDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceDurationSeconds) ?? 0
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        enhancePrompt = try container.decodeIfPresent(Bool.self, forKey: .enhancePrompt) ?? true
        seed = try container.decodeIfPresent(Int.self, forKey: .seed) ?? 0
        resolution = try container.decodeIfPresent(String.self, forKey: .resolution) ?? "720p"
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "fal"
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? "decart/lucy-restyle"
        inputMode = try container.decodeIfPresent(String.self, forKey: .inputMode) ?? "text"
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId) ?? ""
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId) ?? ""
        inputRemoteURL = try container.decodeIfPresent(String.self, forKey: .inputRemoteURL) ?? ""
        outputRemoteURL = try container.decodeIfPresent(String.self, forKey: .outputRemoteURL) ?? ""
        estimatedCostUSD = try container.decodeIfPresent(Double.self, forKey: .estimatedCostUSD) ?? 0
        estimatedCostCredits = try container.decodeIfPresent(Double.self, forKey: .estimatedCostCredits) ?? 0
        pricingUnit = try container.decodeIfPresent(String.self, forKey: .pricingUnit) ?? "usd_per_source_second"
        pricingRate = try container.decodeIfPresent(Double.self, forKey: .pricingRate) ?? 0.01
        videoPath = try container.decodeIfPresent(String.self, forKey: .videoPath) ?? ""
        outputDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .outputDurationSeconds) ?? 0
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
        styleId = try container.decodeIfPresent(String.self, forKey: .styleId) ?? ""
        styleLabel = try container.decodeIfPresent(String.self, forKey: .styleLabel) ?? ""
        styleCollection = try container.decodeIfPresent(String.self, forKey: .styleCollection) ?? ""
        styleHueHex = try container.decodeIfPresent(String.self, forKey: .styleHueHex) ?? ""
        styleSummary = try container.decodeIfPresent(String.self, forKey: .styleSummary) ?? ""
        styleCatalogVersion = try container.decodeIfPresent(String.self, forKey: .styleCatalogVersion) ?? ""
        styleImageReference = try container.decodeIfPresent(SREFStyleImageReference.self, forKey: .styleImageReference)
        sourceClipMediaId = try container.decodeIfPresent(String.self, forKey: .sourceClipMediaId) ?? ""
        sourceClipStartSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceClipStartSeconds) ?? 0
        sourceClipEndSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceClipEndSeconds) ?? 0
        outputMediaId = try container.decodeIfPresent(String.self, forKey: .outputMediaId) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    func normalized() -> ShotRestyleArtifact {
        var value = self
        value.versionId = value.versionId.trimmed
        value.versionNumber = max(value.versionNumber, 0)
        value.status = value.status.trimmed.lowercased()
        value.sourceShotId = value.sourceShotId.trimmed
        value.sourceRenderVersionId = value.sourceRenderVersionId.trimmed
        value.sourceVisualFingerprint = value.sourceVisualFingerprint.trimmed
        value.sourceVideoPath = value.sourceVideoPath.trimmed
        value.sourceVideoSHA256 = value.sourceVideoSHA256.trimmed.lowercased()
        value.sourceDurationSeconds = max(value.sourceDurationSeconds.isFinite ? value.sourceDurationSeconds : 0, 0)
        value.prompt = String(value.prompt.trimmed.prefix(1_500))
        value.seed = max(value.seed, 0)
        value.resolution = value.resolution.trimmed.nilIfEmpty ?? "720p"
        value.provider = ShotLookProvider.resolved(value.provider).rawValue
        value.model = value.model.trimmed.nilIfEmpty ?? value.restyleProvider.modelId
        value.inputMode = value.inputMode.trimmed.nilIfEmpty ?? value.restyleProvider.inputMode
        value.requestId = value.requestId.trimmed
        value.traceId = value.traceId.trimmed
        value.inputRemoteURL = value.inputRemoteURL.trimmed
        value.outputRemoteURL = value.outputRemoteURL.trimmed
        value.estimatedCostUSD = max(value.estimatedCostUSD.isFinite ? value.estimatedCostUSD : 0, 0)
        value.estimatedCostCredits = max(value.estimatedCostCredits.isFinite ? value.estimatedCostCredits : 0, 0)
        value.pricingUnit = value.pricingUnit.trimmed
        value.pricingRate = max(value.pricingRate.isFinite ? value.pricingRate : 0, 0)
        value.videoPath = value.videoPath.trimmed
        value.outputDurationSeconds = max(value.outputDurationSeconds.isFinite ? value.outputDurationSeconds : 0, 0)
        value.errorMessage = value.errorMessage.trimmed
        value.styleId = value.styleId.trimmed
        value.styleLabel = value.styleLabel.trimmed
        value.styleCollection = value.styleCollection.trimmed
        value.styleHueHex = value.styleHueHex.trimmed
        value.styleSummary = value.styleSummary.trimmed
        value.styleCatalogVersion = value.styleCatalogVersion.trimmed
        value.styleImageReference = value.styleImageReference?.normalized()
        value.sourceClipMediaId = value.sourceClipMediaId.trimmed
        value.sourceClipStartSeconds = max(value.sourceClipStartSeconds.isFinite ? value.sourceClipStartSeconds : 0, 0)
        value.sourceClipEndSeconds = max(value.sourceClipEndSeconds.isFinite ? value.sourceClipEndSeconds : 0, 0)
        value.outputMediaId = value.outputMediaId.trimmed
        value.generatedAt = value.generatedAt.trimmed
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

struct ProjectShot: Codable, Hashable, Identifiable, Sendable {
    var shotId: String = ""
    var name: String = ""
    var entries: [ShotFrameEntry] = []
    /// Legacy single-render field, kept as a MIRROR of the active render
    /// version so old reads (and old builds) keep working. Mutate through
    /// upsertingRenderVersion / activatingRenderVersion, not directly.
    var renderArtifact: ShotRenderArtifact?
    /// Every render of this shot, kept forever; the active one is named by
    /// activeRenderVersionId and mirrored onto renderArtifact.
    var renderVersions: [ShotRenderArtifact] = []
    var activeRenderVersionId: String = ""
    /// Immutable Lucy finishing passes. They are intentionally independent
    /// of render versions: the Original owns cuts and segment editing, while
    /// a Look is flattened picture derived from one exact visual edit.
    var lookVersions: [ShotRestyleArtifact] = []
    /// Empty means Original. Unlike render versions, a dangling value must not
    /// fall forward to the newest Look because Original is a real selection.
    var activeLookVersionId: String = ""
    /// Lucy restyles of single placed-footage ranges, started from this
    /// shot's Clip Inspector. A durable job log and resume source only:
    /// clip looks never activate (their output is archived tray media, and
    /// the shot itself is never changed), so there is no active pointer.
    var clipLookVersions: [ShotRestyleArtifact] = []
    var narrationArtifact: ShotNarrationArtifact?
    var narrationChips: ShotNarrationChipSet?
    var audioMix: ShotAudioMix = ShotAudioMix()
    var preferredRenderStack: String = ""
    /// Anchor pick for narration-driven (LTX) renders: the entry whose frame
    /// anchors the one shot-wide clip. Empty or stale falls back to the first
    /// ready frame — a dangling id never refuses a render.
    var narrationAnchorEntryId: String = ""
    /// The operator's vouch against the lip-sync face check, naming the ONE
    /// entry it covers (Vision misses stylized faces). Self-cleaning: a
    /// different resolved anchor simply stops matching and the check re-arms.
    var narrationAnchorFaceOverrideEntryId: String = ""
    var segmentPromptOverrides: [ShotSegmentPromptOverride] = []
    /// Pair-keyed exceptions to the Shot-wide render recipe. They affect only
    /// future renders; saved clips retain the recipe that produced them.
    var segmentRenderOverrides: [ShotSegmentRenderOverride] = []
    /// Pair-keyed temporal direction plans (timed action beats). Additive and
    /// tolerant: absent on every legacy shot, and an absent or empty plan
    /// renders exactly the classic one-sentence prompt.
    var segmentDirectionPlans: [ShotSegmentDirectionPlanRecord] = []
    /// Immutable generated razor-join attempts and ready versions. The cut
    /// stores only which version is active, so restoring material never
    /// destroys paid-render provenance.
    var joinBridgeVersions: [ShotJoinBridgeArtifact] = []
    /// Baked reversed copies of this shot's clips, keyed by source identity.
    /// A cache, not a deliverable: the files are hidden derived media, and
    /// losing them costs only re-encode time, never operator work.
    var reverseProxies: [ShotReverseProxyArtifact] = []
    /// The cut layer: shot-level in/out plus razor ranges inside segments.
    /// Deterministic view state over the rendered clips — applying it never
    /// touches a file on disk and never costs a render.
    var cutList: ShotCutList = ShotCutList()
    /// Independent source snapshots for a locally combined CUT. The source
    /// shot rows remain preserved in the Stage group; these values are
    /// provenance, never live links.
    var combinedSources: [ShotCombinedSource] = []
    /// Structural hard-cut seams introduced between copied source timelines.
    var sourceBoundaries: [ShotSourceBoundary] = []
    /// Readable clips inherited from source renders. Seeds make an editable
    /// combined CUT immediately playable without pretending it has a ready
    /// render version.
    var seedSegmentClips: [ShotRenderSegmentClip] = []
    /// Multiple independently editable placements per audio lane. Empty on
    /// legacy and ordinary CUTs, which continue using the singleton mirrors.
    var audioRegions: [ShotAudioRegion] = []
    /// Per-SEGMENT source-audio intent. Empty means "every segment plays as
    /// rendered" — the flat lane volume — so an untouched cut carries none.
    var sourceSegmentAudio: [ShotSourceSegmentAudio] = []
    /// PICTURE INSERTIONS — the arrangement layer above the cut plan: pasted
    /// copies of picture spans spliced into the output (loop / slow / speed /
    /// mute per copy). Empty means the output is exactly the cut plan, so an
    /// untouched shot carries none. Like a razor, a copy's SOURCE pins the
    /// exact take file (new pixels ≠ old timings); like a segment mute, its
    /// ANCHOR pins only the segment key and survives re-renders.
    var pictureInsertions: [ShotPictureInsertion] = []
    var createdAt: String = ""
    var updatedAt: String = ""

    var id: String { shotId }

    var renderStack: ShotRenderStack {
        (ShotRenderStack(rawValue: preferredRenderStack) ?? .fallback)
            .upgradedForFutureRender
    }

    var sortedRenderVersions: [ShotRenderArtifact] {
        renderVersions.sorted { lhs, rhs in
            if lhs.versionNumber == rhs.versionNumber {
                return lhs.generatedAt < rhs.generatedAt
            }
            return lhs.versionNumber < rhs.versionNumber
        }
    }

    /// The currently selected render; tolerant of a dangling pointer.
    var activeRenderVersion: ShotRenderArtifact? {
        renderVersions.first { $0.versionId == activeRenderVersionId } ?? sortedRenderVersions.last
    }

    /// What the player and assembly SHOW: the selected version when it is
    /// ready, else the newest ready version (view-only substitution while a
    /// re-render is in flight or after a failure), else the selected version
    /// itself (first-render progressive reveal, honest placeholders). Never
    /// moves the persisted pointer — completion re-activates the new version
    /// and playback flips to it automatically.
    var playableRenderVersion: ShotRenderArtifact? {
        if let active = activeRenderVersion, active.isReady { return active }
        return browsableRenderVersions.last ?? activeRenderVersion
    }

    var sortedLookVersions: [ShotRestyleArtifact] {
        lookVersions.sorted { lhs, rhs in
            if lhs.versionNumber == rhs.versionNumber {
                return lhs.generatedAt < rhs.generatedAt
            }
            return lhs.versionNumber < rhs.versionNumber
        }
    }

    var activeLookVersion: ShotRestyleArtifact? {
        guard !activeLookVersionId.isEmpty else { return nil }
        return lookVersions.first { $0.versionId == activeLookVersionId && $0.isReady }
    }

    var browsableLookVersions: [ShotRestyleArtifact] {
        sortedLookVersions.filter(\.isReady)
    }

    /// The versions the browser offers: ready with a video file recorded.
    var browsableRenderVersions: [ShotRenderArtifact] {
        sortedRenderVersions.filter(\.isReady)
    }

    func isActiveRenderVersion(_ version: ShotRenderArtifact) -> Bool {
        version.versionId == activeRenderVersionId
    }

    private enum CodingKeys: String, CodingKey {
        case shotId
        case name
        case entries
        case renderArtifact
        case renderVersions
        case activeRenderVersionId
        case lookVersions
        case activeLookVersionId
        case clipLookVersions
        case narrationArtifact
        case narrationChips
        case audioMix
        case preferredRenderStack
        case narrationAnchorEntryId
        case narrationAnchorFaceOverrideEntryId
        case segmentPromptOverrides
        case segmentRenderOverrides
        case segmentDirectionPlans
        case joinBridgeVersions
        case reverseProxies
        case cutList
        case combinedSources
        case sourceBoundaries
        case seedSegmentClips
        case audioRegions
        case sourceSegmentAudio
        case pictureInsertions
        case createdAt
        case updatedAt
    }

    init(
        shotId: String = "",
        name: String = "",
        entries: [ShotFrameEntry] = [],
        renderArtifact: ShotRenderArtifact? = nil,
        renderVersions: [ShotRenderArtifact] = [],
        activeRenderVersionId: String = "",
        lookVersions: [ShotRestyleArtifact] = [],
        activeLookVersionId: String = "",
        clipLookVersions: [ShotRestyleArtifact] = [],
        narrationArtifact: ShotNarrationArtifact? = nil,
        narrationChips: ShotNarrationChipSet? = nil,
        audioMix: ShotAudioMix = ShotAudioMix(),
        preferredRenderStack: String = "",
        narrationAnchorEntryId: String = "",
        narrationAnchorFaceOverrideEntryId: String = "",
        segmentPromptOverrides: [ShotSegmentPromptOverride] = [],
        segmentRenderOverrides: [ShotSegmentRenderOverride] = [],
        segmentDirectionPlans: [ShotSegmentDirectionPlanRecord] = [],
        joinBridgeVersions: [ShotJoinBridgeArtifact] = [],
        reverseProxies: [ShotReverseProxyArtifact] = [],
        cutList: ShotCutList = ShotCutList(),
        combinedSources: [ShotCombinedSource] = [],
        sourceBoundaries: [ShotSourceBoundary] = [],
        seedSegmentClips: [ShotRenderSegmentClip] = [],
        audioRegions: [ShotAudioRegion] = [],
        sourceSegmentAudio: [ShotSourceSegmentAudio] = [],
        pictureInsertions: [ShotPictureInsertion] = [],
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.shotId = shotId
        self.name = name
        self.entries = entries
        self.renderArtifact = renderArtifact
        self.renderVersions = renderVersions
        self.activeRenderVersionId = activeRenderVersionId
        self.lookVersions = lookVersions
        self.activeLookVersionId = activeLookVersionId
        self.clipLookVersions = clipLookVersions
        self.narrationArtifact = narrationArtifact
        self.narrationChips = narrationChips
        self.audioMix = audioMix
        self.preferredRenderStack = preferredRenderStack
        self.narrationAnchorEntryId = narrationAnchorEntryId
        self.narrationAnchorFaceOverrideEntryId = narrationAnchorFaceOverrideEntryId
        self.segmentPromptOverrides = segmentPromptOverrides
        self.segmentRenderOverrides = segmentRenderOverrides
        self.segmentDirectionPlans = segmentDirectionPlans
        self.joinBridgeVersions = joinBridgeVersions
        self.reverseProxies = reverseProxies
        self.cutList = cutList
        self.combinedSources = combinedSources
        self.sourceBoundaries = sourceBoundaries
        self.seedSegmentClips = seedSegmentClips
        self.audioRegions = audioRegions
        self.sourceSegmentAudio = sourceSegmentAudio
        self.pictureInsertions = pictureInsertions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shotId = try container.decodeIfPresent(String.self, forKey: .shotId) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        entries = try container.decodeIfPresent([ShotFrameEntry].self, forKey: .entries) ?? []
        renderArtifact = try container.decodeIfPresent(ShotRenderArtifact.self, forKey: .renderArtifact)
        renderVersions = ((try? container.decodeIfPresent([ShotRenderArtifact].self, forKey: .renderVersions)) ?? nil) ?? []
        activeRenderVersionId = try container.decodeIfPresent(String.self, forKey: .activeRenderVersionId) ?? ""
        lookVersions = ((try? container.decodeIfPresent([ShotRestyleArtifact].self, forKey: .lookVersions)) ?? nil) ?? []
        activeLookVersionId = try container.decodeIfPresent(String.self, forKey: .activeLookVersionId) ?? ""
        clipLookVersions = ((try? container.decodeIfPresent([ShotRestyleArtifact].self, forKey: .clipLookVersions)) ?? nil) ?? []
        narrationArtifact = (try? container.decodeIfPresent(ShotNarrationArtifact.self, forKey: .narrationArtifact)) ?? nil
        narrationChips = (try? container.decodeIfPresent(ShotNarrationChipSet.self, forKey: .narrationChips)) ?? nil
        audioMix = ((try? container.decodeIfPresent(ShotAudioMix.self, forKey: .audioMix)) ?? nil) ?? ShotAudioMix()
        preferredRenderStack = try container.decodeIfPresent(String.self, forKey: .preferredRenderStack) ?? ""
        narrationAnchorEntryId = try container.decodeIfPresent(String.self, forKey: .narrationAnchorEntryId) ?? ""
        narrationAnchorFaceOverrideEntryId = try container.decodeIfPresent(String.self, forKey: .narrationAnchorFaceOverrideEntryId) ?? ""
        segmentPromptOverrides = ((try? container.decodeIfPresent([ShotSegmentPromptOverride].self, forKey: .segmentPromptOverrides)) ?? nil) ?? []
        segmentRenderOverrides = ((try? container.decodeIfPresent([ShotSegmentRenderOverride].self, forKey: .segmentRenderOverrides)) ?? nil) ?? []
        segmentDirectionPlans = ((try? container.decodeIfPresent([ShotSegmentDirectionPlanRecord].self, forKey: .segmentDirectionPlans)) ?? nil) ?? []
        joinBridgeVersions = ((try? container.decodeIfPresent([ShotJoinBridgeArtifact].self, forKey: .joinBridgeVersions)) ?? nil) ?? []
        reverseProxies = ((try? container.decodeIfPresent([ShotReverseProxyArtifact].self, forKey: .reverseProxies)) ?? nil) ?? []
        cutList = ((try? container.decodeIfPresent(ShotCutList.self, forKey: .cutList)) ?? nil) ?? ShotCutList()
        combinedSources = ((try? container.decodeIfPresent([ShotCombinedSource].self, forKey: .combinedSources)) ?? nil) ?? []
        sourceBoundaries = ((try? container.decodeIfPresent([ShotSourceBoundary].self, forKey: .sourceBoundaries)) ?? nil) ?? []
        seedSegmentClips = ((try? container.decodeIfPresent([ShotRenderSegmentClip].self, forKey: .seedSegmentClips)) ?? nil) ?? []
        audioRegions = ((try? container.decodeIfPresent([ShotAudioRegion].self, forKey: .audioRegions)) ?? nil) ?? []
        sourceSegmentAudio = ((try? container.decodeIfPresent([ShotSourceSegmentAudio].self, forKey: .sourceSegmentAudio)) ?? nil) ?? []
        pictureInsertions = ((try? container.decodeIfPresent([ShotPictureInsertion].self, forKey: .pictureInsertions)) ?? nil) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        migrateLegacyShotRenderPreferencesIfNeeded()
        migrateLegacyRenderArtifactIfNeeded()
    }

    /// Rewrites only future-render preferences. Render artifacts keep their
    /// original stack/provider/model fields as immutable execution history.
    mutating func migrateLegacyShotRenderPreferencesIfNeeded() {
        if let preferred = ShotRenderStack(rawValue: preferredRenderStack),
           preferred.model == .klingV26Pro {
            preferredRenderStack = preferred.upgradedForFutureRender.rawValue
        }
        segmentRenderOverrides = segmentRenderOverrides.map { rawOverride in
            var value = rawOverride
            if let stack = ShotRenderStack(rawValue: value.stack),
               stack.model == .klingV26Pro {
                value.stack = stack.upgradedForFutureRender.rawValue
            }
            return value
        }
        if !preferredRenderStack.isEmpty {
            segmentRenderOverrides.removeAll { $0.stack == preferredRenderStack }
        }
    }

    /// Repairs the version list against the legacy mirror. Runs at decode
    /// (loads skip normalized()) and again from normalized():
    /// 1. dangling/empty active pointer → adopt the newest version;
    /// 2. no versions but a legacy artifact → it becomes version 1, active;
    /// 3. versions present but the mirror matches none of them (an old build
    ///    re-rendered and rewrote only the mirror) → fold the mirror in as the
    ///    newest version, active.
    mutating func migrateLegacyRenderArtifactIfNeeded() {
        if renderVersions.isEmpty {
            guard let legacy = renderArtifact?.normalized() else {
                activeRenderVersionId = ""
                return
            }
            var version = legacy
            version.versionId = "shotrender_\(shortHash("\(shotId):legacy:\(legacy.generatedAt):\(legacy.videoPath)", length: 14))"
            version.versionNumber = 1
            renderVersions = [version]
            activeRenderVersionId = version.versionId
            renderArtifact = version
            return
        }
        if let mirror = renderArtifact?.normalized(),
           !renderVersions.contains(where: { $0.versionId == mirror.versionId && !mirror.versionId.isEmpty })
            && !renderVersions.contains(where: { $0.generatedAt == mirror.generatedAt && $0.videoPath == mirror.videoPath }) {
            var folded = mirror
            folded.versionId = "shotrender_\(shortHash("\(shotId):legacy:\(mirror.generatedAt):\(mirror.videoPath)", length: 14))"
            folded.versionNumber = (renderVersions.map(\.versionNumber).max() ?? 0) + 1
            renderVersions.append(folded)
            activeRenderVersionId = folded.versionId
            renderArtifact = folded
            return
        }
        if !renderVersions.contains(where: { $0.versionId == activeRenderVersionId }) {
            let newest = sortedRenderVersions.last
            activeRenderVersionId = newest?.versionId ?? ""
            renderArtifact = newest
        }
    }

    /// Legacy-mirror write, kept for old call sites and tests; engine renders
    /// go through upsertingRenderVersion instead.
    func settingRenderArtifact(_ artifact: ShotRenderArtifact?, now: String) -> ProjectShot {
        var value = self
        value.renderArtifact = artifact?.normalized()
        value.updatedAt = now
        return value
    }

    /// Inserts or replaces a render version by versionId; when `activate`, the
    /// version becomes the shot's selected render and mirrors onto
    /// renderArtifact.
    func upsertingRenderVersion(_ version: ShotRenderArtifact, activate: Bool, now: String) -> ProjectShot {
        let normalizedVersion = version.normalized()
        guard !normalizedVersion.versionId.isEmpty else { return self }
        var value = self
        value.renderVersions.removeAll { $0.versionId == normalizedVersion.versionId }
        value.renderVersions.append(normalizedVersion)
        value.renderVersions = value.sortedRenderVersions
        if activate {
            value.activeRenderVersionId = normalizedVersion.versionId
            value.renderArtifact = normalizedVersion
        }
        value.updatedAt = now
        return value
    }

    /// Selects an existing render version; unknown ids leave the shot untouched.
    func activatingRenderVersion(_ versionId: String, now: String) -> ProjectShot {
        guard let version = renderVersions.first(where: { $0.versionId == versionId }) else { return self }
        var value = self
        value.activeRenderVersionId = version.versionId
        value.renderArtifact = version
        value.updatedAt = now
        return value
    }

    func upsertingLookVersion(_ version: ShotRestyleArtifact, activate: Bool, now: String) -> ProjectShot {
        let normalizedVersion = version.normalized()
        guard !normalizedVersion.versionId.isEmpty else { return self }
        var value = self
        value.lookVersions.removeAll { $0.versionId == normalizedVersion.versionId }
        value.lookVersions.append(normalizedVersion)
        value.lookVersions = value.sortedLookVersions
        if activate, normalizedVersion.isReady {
            value.activeLookVersionId = normalizedVersion.versionId
        }
        value.updatedAt = now
        return value
    }

    /// Clip Looks never activate — there is no pointer to move; the array is
    /// a durable job log and resume source only.
    func upsertingClipLookVersion(_ version: ShotRestyleArtifact, now: String) -> ProjectShot {
        let normalizedVersion = version.normalized()
        guard !normalizedVersion.versionId.isEmpty else { return self }
        var value = self
        value.clipLookVersions.removeAll { $0.versionId == normalizedVersion.versionId }
        value.clipLookVersions.append(normalizedVersion)
        value.clipLookVersions.sort { lhs, rhs in
            if lhs.versionNumber == rhs.versionNumber {
                return lhs.generatedAt < rhs.generatedAt
            }
            return lhs.versionNumber < rhs.versionNumber
        }
        value.updatedAt = now
        return value
    }

    /// Empty selects the editable Original. Unknown nonempty ids are ignored.
    func activatingLookVersion(_ versionId: String, now: String) -> ProjectShot {
        let candidate = versionId.trimmed
        if candidate.isEmpty {
            var value = self
            value.activeLookVersionId = ""
            value.updatedAt = now
            return value
        }
        guard lookVersions.contains(where: { $0.versionId == candidate && $0.isReady }) else { return self }
        var value = self
        value.activeLookVersionId = candidate
        value.updatedAt = now
        return value
    }

    /// Flips every in-flight render version to failed (relaunch reconcile);
    /// `changed` is false when nothing was generating.
    func failingInFlightRenderVersions(now: String) -> (shot: ProjectShot, changed: Bool) {
        var value = self
        var changed = false
        value.renderVersions = value.renderVersions.map { version in
            guard version.status == "generating" else { return version }
            var failed = version
            failed.status = "failed"
            failed.errorMessage = "Interrupted before completion"
            failed.progressText = ""
            failed.updatedAt = now
            changed = true
            return failed
        }
        if let mirror = value.renderArtifact, mirror.status == "generating" {
            var failed = mirror
            failed.status = "failed"
            failed.errorMessage = "Interrupted before completion"
            failed.progressText = ""
            failed.updatedAt = now
            value.renderArtifact = failed
            changed = true
        }
        value.joinBridgeVersions = value.joinBridgeVersions.map { version in
            guard version.status == "generating" else { return version }
            var failed = version
            failed.status = "failed"
            failed.errorMessage = "Interrupted before completion"
            failed.updatedAt = now
            changed = true
            return failed
        }
        // A half-written proxy is not resumable — there is no remote job behind
        // it, only a dead local encode. Reconcile simply re-bakes.
        value.reverseProxies = value.reverseProxies.map { proxy in
            guard proxy.status == "baking" else { return proxy }
            var failed = proxy
            failed.status = "failed"
            failed.errorMessage = "Interrupted before completion"
            failed.updatedAt = now
            changed = true
            return failed
        }
        if changed {
            if let active = value.renderVersions.first(where: { $0.versionId == value.activeRenderVersionId }) {
                value.renderArtifact = active
            }
            value.updatedAt = now
        }
        return (value, changed)
    }

    /// On a regionized shot (any persisted `audioRegions`), the singleton
    /// artifact is an inert mirror — playback truth is the narration REGION.
    /// This single model-level law keeps the region in sync for every engine
    /// write site: a ready artifact upserts the active-narration region in
    /// place (keeping the operator's timing/gain/mute), and deleting the
    /// artifact removes it. Non-regionized shots keep the old behavior.
    func settingNarrationArtifact(_ artifact: ShotNarrationArtifact?, now: String) -> ProjectShot {
        var value = self
        let priorNarration = narrationArtifact?.normalized()
        value.narrationArtifact = artifact?.normalized()
        value.updatedAt = now
        let priorNarrationWasUsable = !(priorNarration?.audioPath.trimmed ?? "").isEmpty
        if let ready = value.narrationArtifact,
           ready.isReady,
           !priorNarrationWasUsable,
           !value.audioRegions.contains(where: {
               $0.laneId == ShotAudioLaneId.narration && $0.provenance == "active_narration"
           }) {
            value.audioMix = value.audioMix.preparingLaneForNewAudio(ShotAudioLaneId.narration)
        }
        guard !value.audioRegions.isEmpty else { return value }
        let activeIndex = value.audioRegions.firstIndex {
            $0.laneId == ShotAudioLaneId.narration && $0.provenance == "active_narration"
        }
        guard let artifact = value.narrationArtifact else {
            if let activeIndex {
                value.audioRegions.remove(at: activeIndex)
            }
            return value
        }
        guard artifact.isReady, !artifact.audioPath.trimmed.isEmpty else { return value }
        let mediaSeconds = artifact.durationSeconds > 0 ? artifact.durationSeconds : nil
        if let activeIndex {
            value.audioRegions[activeIndex] = value.audioRegions[activeIndex]
                .replacingMedia(
                    path: artifact.audioPath,
                    mediaId: "",
                    label: value.audioRegions[activeIndex].label,
                    sourceDurationSeconds: mediaSeconds,
                    provenance: "active_narration"
                )
            value.audioRegions[activeIndex].sourceArtifactId = artifact.traceId
            value.audioRegions[activeIndex].sourceStartSeconds = 0
            value.audioRegions[activeIndex].durationSeconds = max(
                artifact.durationSeconds,
                ShotAudioTiming.frameSeconds
            )
        } else {
            value.audioRegions.append(ShotAudioRegion(
                regionId: "audio_region_\(shortHash("regionize:\(shotId):\(ShotAudioLaneId.narration):\(artifact.traceId)", length: 12))",
                laneId: ShotAudioLaneId.narration,
                label: "Narration",
                path: artifact.audioPath,
                sourceCutId: shotId,
                sourceArtifactId: artifact.traceId,
                provenance: "active_narration",
                startSeconds: audioMix.lane(ShotAudioLaneId.narration).effectiveStartSeconds,
                durationSeconds: max(artifact.durationSeconds, ShotAudioTiming.frameSeconds),
                sourceDurationSeconds: mediaSeconds,
                gain: 1,
                isMuted: false
            ).normalized())
        }
        return value
    }

    func settingNarrationChips(_ chips: ShotNarrationChipSet?, now: String) -> ProjectShot {
        var value = self
        value.narrationChips = chips?.normalized()
        value.updatedAt = now
        return value
    }

    func settingAudioMix(_ mix: ShotAudioMix, now: String) -> ProjectShot {
        var value = self
        value.audioMix = mix.normalized()
        value.updatedAt = now
        return value
    }

    func settingPreferredRenderStack(_ stack: ShotRenderStack, now: String) -> ProjectShot {
        var value = self
        value.preferredRenderStack = stack.rawValue
        value.segmentRenderOverrides.removeAll { $0.stack == stack.rawValue }
        // Narration-driven stacks are whole-shot-only by law: as segment
        // overrides they refuse every render, and the gated menu can no
        // longer show them. Leaving the shot's narration lane means any
        // such override is stale — sweep it so the refusal can't strand
        // the shot with an invisible cause.
        if !stack.isNarrationDriven {
            value.segmentRenderOverrides.removeAll { override in
                ShotRenderStack(rawValue: override.stack)?.isNarrationDriven == true
            }
        }
        value.updatedAt = now
        return value
    }

    /// The NEW VERSION copy: same name and timeline (entries keep order, clip
    /// ranges, seams, skips — with fresh identities), same render recipe and
    /// segment overrides (they key by FRAME ids, so they carry over intact),
    /// same cut layer — and zero artifacts. Renders, looks, join bridges,
    /// narration, and the audio mix stay with the original; a new version is
    /// unrendered by definition.
    func duplicated(now: String) -> ProjectShot {
        var value = self
        value.shotId = "shot_\(shortHash("\(shotId):dup:\(now):\(UUID().uuidString)", length: 12))"
        value.entries = entries.map { entry in
            var copy = entry
            copy.entryId = "entry_\(shortHash("\(value.shotId):\(entry.entryId):\(UUID().uuidString)", length: 12))"
            return copy
        }
        value.renderArtifact = nil
        value.renderVersions = []
        value.activeRenderVersionId = ""
        value.lookVersions = []
        value.activeLookVersionId = ""
        value.clipLookVersions = []
        value.joinBridgeVersions = []
        // The copy has no clips of its own yet, so it has nothing to point a
        // proxy at. `cutList` is deliberately KEPT: a duplicate of a reversed
        // CUT is still reversed, and re-bakes as soon as it renders.
        value.reverseProxies = []
        value.narrationArtifact = nil
        value.narrationChips = nil
        value.audioMix = ShotAudioMix()
        value.seedSegmentClips = []
        value.audioRegions = []
        // A twin is unrendered and its entries are re-keyed, so any carried
        // intent could never match a segment again.
        value.sourceSegmentAudio = []
        // Same law for arranged copies: their sources pin the original's take
        // files and their anchors pin re-keyed segments.
        value.pictureInsertions = []
        value.createdAt = now
        value.updatedAt = now
        return value
    }

    /// Replaces the segment prompt overrides wholesale with the sheet's save
    /// set, then prunes any whose frames have left the shot's strip.
    func settingSegmentPromptOverrides(_ overrides: [ShotSegmentPromptOverride], now: String) -> ProjectShot {
        var value = self
        value.segmentPromptOverrides = pruningSegmentPromptOverrides(
            overrides.map { $0.normalized() }.filter {
                (!$0.startFrameImageId.isEmpty
                    || !$0.endFrameImageId.isEmpty
                    || !$0.placementStartEntryId.isEmpty
                    || !$0.placementEndEntryId.isEmpty)
                    && !$0.prompt.isEmpty
            },
            entries: entries
        )
        value.updatedAt = now
        return value
    }

    /// Replaces the segment direction plans wholesale with the editor's save
    /// set, then prunes any whose frames have left the shot's strip — the
    /// exact law of `settingSegmentPromptOverrides`, kept parallel.
    func settingSegmentDirectionPlans(_ plans: [ShotSegmentDirectionPlanRecord], now: String) -> ProjectShot {
        var value = self
        value.segmentDirectionPlans = pruningSegmentDirectionPlans(
            plans.map { $0.normalized() }.filter {
                (!$0.startFrameImageId.isEmpty
                    || !$0.endFrameImageId.isEmpty
                    || !$0.placementStartEntryId.isEmpty
                    || !$0.placementEndEntryId.isEmpty)
                    && $0.hasContent
            },
            entries: entries
        )
        value.updatedAt = now
        return value
    }

    /// The persisted direction plan for a render segment, or nil when none
    /// matches — placement-entry match first, legacy image-pair fallback,
    /// identical to `segmentPromptOverride(for:)`.
    func segmentDirectionPlan(for pair: ShotRenderPair) -> ShotSegmentDirectionPlanRecord? {
        let startId = pair.start?.imageId ?? ""
        let endId = pair.end?.imageId ?? ""
        if !pair.startPlacementEntryId.isEmpty || !pair.endPlacementEntryId.isEmpty,
           let exact = segmentDirectionPlans.first(where: {
               $0.placementStartEntryId == pair.startPlacementEntryId
                   && $0.placementEndEntryId == pair.endPlacementEntryId
                   && (!$0.placementStartEntryId.isEmpty || !$0.placementEndEntryId.isEmpty)
           }) {
            return exact
        }
        return segmentDirectionPlans.first {
            $0.placementStartEntryId.isEmpty
                && $0.placementEndEntryId.isEmpty
                && $0.startFrameImageId == startId
                && $0.endFrameImageId == endId
        }
    }

    /// Sets or removes one inherited render-recipe exception. Persisting a
    /// value equal to the Shot default would create false customization, so
    /// it is normalized to removal.
    func settingSegmentRenderOverride(
        startFrameImageId: String,
        endFrameImageId: String,
        placementStartEntryId: String = "",
        placementEndEntryId: String = "",
        stack: ShotRenderStack?,
        now: String
    ) -> ProjectShot {
        var value = self
        let startId = startFrameImageId.trimmed
        let endId = endFrameImageId.trimmed
        let placementStartId = placementStartEntryId.trimmed
        let placementEndId = placementEndEntryId.trimmed
        let usesPlacementIdentity = !placementStartId.isEmpty || !placementEndId.isEmpty
        value.segmentRenderOverrides.removeAll {
            if usesPlacementIdentity {
                return $0.placementStartEntryId == placementStartId
                    && $0.placementEndEntryId == placementEndId
            }
            return $0.placementStartEntryId.isEmpty
                && $0.placementEndEntryId.isEmpty
                && $0.startFrameImageId == startId
                && $0.endFrameImageId == endId
        }
        if let stack,
           stack != renderStack,
           usesPlacementIdentity || !startId.isEmpty || !endId.isEmpty {
            value.segmentRenderOverrides.append(ShotSegmentRenderOverride(
                startFrameImageId: startId,
                endFrameImageId: endId,
                placementStartEntryId: placementStartId,
                placementEndEntryId: placementEndId,
                stack: stack.rawValue,
                updatedAt: now
            ))
        }
        value.segmentRenderOverrides = pruningSegmentRenderOverrides(
            value.segmentRenderOverrides,
            entries: value.entries
        )
        value.updatedAt = now
        return value
    }

    /// The persisted prompt override for a render segment, or nil when none
    /// matches (fall back to the generated prompt).
    func segmentPromptOverride(for pair: ShotRenderPair) -> String? {
        let startId = pair.start?.imageId ?? ""
        let endId = pair.end?.imageId ?? ""
        if !pair.startPlacementEntryId.isEmpty || !pair.endPlacementEntryId.isEmpty,
           let exact = segmentPromptOverrides.first(where: {
               $0.placementStartEntryId == pair.startPlacementEntryId
                   && $0.placementEndEntryId == pair.endPlacementEntryId
                   && (!$0.placementStartEntryId.isEmpty || !$0.placementEndEntryId.isEmpty)
           }) {
            return exact.prompt.trimmed.nilIfEmpty
        }
        return segmentPromptOverrides.first {
            $0.placementStartEntryId.isEmpty
                && $0.placementEndEntryId.isEmpty
                && $0.startFrameImageId == startId
                && $0.endFrameImageId == endId
        }?.prompt.trimmed.nilIfEmpty
    }

    func segmentRenderStack(for pair: ShotRenderPair) -> ShotRenderStack {
        (segmentRenderOverride(for: pair)
            .flatMap { ShotRenderStack(rawValue: $0.stack) }
            ?? renderStack)
            .upgradedForFutureRender
    }

    func hasSegmentRenderOverride(for pair: ShotRenderPair) -> Bool {
        segmentRenderOverride(for: pair)
            .flatMap { ShotRenderStack(rawValue: $0.stack) } != nil
    }

    private func segmentRenderOverride(for pair: ShotRenderPair) -> ShotSegmentRenderOverride? {
        let startId = pair.start?.imageId ?? ""
        let endId = pair.end?.imageId ?? ""
        if !pair.startPlacementEntryId.isEmpty || !pair.endPlacementEntryId.isEmpty,
           let exact = segmentRenderOverrides.first(where: {
               $0.placementStartEntryId == pair.startPlacementEntryId
                   && $0.placementEndEntryId == pair.endPlacementEntryId
                   && (!$0.placementStartEntryId.isEmpty || !$0.placementEndEntryId.isEmpty)
           }) {
            return exact
        }
        return segmentRenderOverrides.first {
            $0.placementStartEntryId.isEmpty
                && $0.placementEndEntryId.isEmpty
                && $0.startFrameImageId == startId
                && $0.endFrameImageId == endId
        }
    }

    func joinBridgeVersion(_ versionId: String) -> ShotJoinBridgeArtifact? {
        joinBridgeVersions.first { $0.versionId == versionId }
    }

    func upsertingJoinBridgeVersion(_ artifact: ShotJoinBridgeArtifact, now: String) -> ProjectShot {
        let normalizedArtifact = artifact.normalized()
        guard !normalizedArtifact.versionId.isEmpty else { return self }
        var value = self
        value.joinBridgeVersions.removeAll { $0.versionId == normalizedArtifact.versionId }
        value.joinBridgeVersions.append(normalizedArtifact)
        value.updatedAt = now
        return value
    }

    func reverseProxy(forSourcePath path: String) -> ShotReverseProxyArtifact? {
        let key = path.trimmed
        guard !key.isEmpty else { return nil }
        return reverseProxies.first { $0.sourcePath == key }
    }

    func upsertingReverseProxy(_ artifact: ShotReverseProxyArtifact, now: String) -> ProjectShot {
        let normalizedArtifact = artifact.normalized()
        guard !normalizedArtifact.proxyId.isEmpty else { return self }
        var value = self
        value.reverseProxies.removeAll { $0.proxyId == normalizedArtifact.proxyId }
        value.reverseProxies.append(normalizedArtifact)
        value.updatedAt = now
        return value
    }

    /// Ready proxies whose file is actually on disk, keyed by the SOURCE path
    /// the assembly holds. `fileExists` is injected so the derivation stays
    /// testable, matching how ready join bridges are resolved.
    func readyReverseProxiesBySourcePath(
        fileExists: (String) -> Bool
    ) -> [String: ShotReverseProxyArtifact] {
        var resolved: [String: ShotReverseProxyArtifact] = [:]
        for proxy in reverseProxies where proxy.isReady && fileExists(proxy.proxyPath) {
            resolved[proxy.sourcePath] = proxy
        }
        return resolved
    }

    /// Skips or restores one entry. The entry keeps its place, keys, and
    /// overrides — only the plan stops (or resumes) seeing it.
    func settingEntrySkipped(entryId: String, skipped: Bool, now: String) -> ProjectShot {
        guard let index = entries.firstIndex(where: { $0.entryId == entryId }) else { return self }
        var value = self
        value.entries[index].isSkipped = skipped
        value.updatedAt = now
        return value
    }

    /// Replaces the cut layer wholesale (normalized + pruned to segments the
    /// strip can still produce).
    func settingCutList(_ list: ShotCutList, now: String) -> ProjectShot {
        var value = self
        value.cutList = list.normalized().pruned(entries: entries)
        value.updatedAt = now
        return value
    }

    /// THE PICTURE SNAPSHOT LAW: the whole picture state, normalized where
    /// normalizers exist so snapshot equality is stable against write-time
    /// normalization (mirrors `shotAudioStateSnapshot`).
    func pictureStateSnapshot() -> ShotPictureStateSnapshot {
        ShotPictureStateSnapshot(
            entries: entries,
            sourceBoundaries: sourceBoundaries,
            cutList: cutList.normalized(),
            audioMix: audioMix.normalized(),
            audioRegions: audioRegions.map { $0.normalized() },
            pictureInsertions: pictureInsertions.map { $0.normalized() }
        )
    }

    /// Restores a picture snapshot wholesale. Order matters: entries and
    /// boundaries land FIRST so `settingCutList`'s prune runs against the
    /// RESTORED entries, then the audio state the cut edit rippled.
    func restoringPictureState(_ snapshot: ShotPictureStateSnapshot, now: String) -> ProjectShot {
        var value = self
        value.entries = snapshot.entries
        value.sourceBoundaries = snapshot.sourceBoundaries
        value.pictureInsertions = snapshot.pictureInsertions
        return value
            .settingCutList(snapshot.cutList, now: now)
            .settingAudioMix(snapshot.audioMix, now: now)
            .settingAudioRegions(snapshot.audioRegions, now: now)
    }

    /// The one seam-style law (extracted from the engine so it is
    /// unit-testable): the style lands on the right entry's lead seam; a
    /// boundary row is deleted ONLY on an explicit non-cut style — see
    /// `ShotSeamEditIntent` (THE SEAM BOUNDARY LAW).
    func settingSeamStyle(
        entryId: String,
        style: ShotSeamStyle,
        intent: ShotSeamEditIntent,
        now: String
    ) -> ProjectShot {
        guard let index = entries.firstIndex(where: { $0.entryId == entryId }) else { return self }
        var value = self
        value.entries[index].leadTransition = style.rawValue
        if intent == .explicit, style != .cut {
            value.sourceBoundaries.removeAll { $0.rightEntryId == entryId }
        }
        value.updatedAt = now
        return value
    }

    // MARK: Pure mutations (unit-testable; each returns the updated shot)

    func insertingEntry(frameImageId: String, at index: Int, now: String) -> ProjectShot {
        guard !frameImageId.trimmed.isEmpty else { return self }
        var value = self
        let entry = ShotFrameEntry(
            entryId: "entry_\(shortHash("\(shotId):\(frameImageId):\(now):\(UUID().uuidString)", length: 12))",
            frameImageId: frameImageId.trimmed
        )
        let clamped = max(0, min(index, value.entries.count))
        value.entries.insert(entry, at: clamped)
        value.updatedAt = now
        return value
    }

    /// Inserts an AI-extension entry: an open-ended generated segment that
    /// picks up from its left neighbor's final frame.
    func insertingExtensionEntry(at index: Int, now: String) -> ProjectShot {
        var value = self
        let entry = ShotFrameEntry(
            entryId: "entry_\(shortHash("\(shotId):extension:\(now):\(UUID().uuidString)", length: 12))",
            isAIExtension: true
        )
        let clamped = max(0, min(index, value.entries.count))
        value.entries.insert(entry, at: clamped)
        value.updatedAt = now
        return value
    }

    /// Inserts real footage (a source video or Studio trim) as a clip entry.
    /// nil bounds ride the asset's own edges — a dropped trim IS its range.
    func insertingClipEntry(
        clipMediaId: String,
        at index: Int,
        now: String,
        clipStartSeconds: Double? = nil,
        clipEndSeconds: Double? = nil
    ) -> ProjectShot {
        guard !clipMediaId.trimmed.isEmpty else { return self }
        var value = self
        let entry = ShotFrameEntry(
            entryId: "entry_\(shortHash("\(shotId):clip:\(clipMediaId):\(now):\(UUID().uuidString)", length: 12))",
            clipMediaId: clipMediaId.trimmed,
            clipStartSeconds: clipStartSeconds,
            clipEndSeconds: clipEndSeconds
        )
        let clamped = max(0, min(index, value.entries.count))
        value.entries.insert(entry, at: clamped)
        value.updatedAt = now
        return value
    }

    /// THE PUNCH-IN EXCURSION INSERT: two entries land immediately after the
    /// anchor — the reframe CHILD (typically still generating) and the anchor's
    /// own frame again as the RETURN. Frame reuse in a cut is legal; the pair
    /// of fresh entry ids keeps every placement distinct. Every seam involved
    /// stays AUTO (frame→frame auto = bridge): the push-in/pull-out motion IS
    /// the segment, so — deliberately unlike the structural-paste boundary
    /// law — nothing here is forced to .cut, and the follower's lead seam is
    /// untouched (it now joins the return copy of the same frame). The return
    /// image derives from the ANCHOR ENTRY, never a parameter, so a nested
    /// dive anchored on a child entry returns to the child for free.
    /// nil = refusal: unknown/clip/extension anchor, or empty child id.
    func insertingPunchInExcursion(
        afterEntryId: String,
        childImageId: String,
        now: String
    ) -> (shot: ProjectShot, childEntryId: String, returnEntryId: String)? {
        guard !childImageId.trimmed.isEmpty,
              let index = entries.firstIndex(where: { $0.entryId == afterEntryId }) else { return nil }
        let anchor = entries[index]
        guard !anchor.isClip, !anchor.isAIExtension, !anchor.frameImageId.trimmed.isEmpty else { return nil }
        var value = self
        let childEntryId = "entry_\(shortHash("\(shotId):punch_in:\(childImageId):\(now):\(UUID().uuidString)", length: 12))"
        let returnEntryId = "entry_\(shortHash("\(shotId):punch_return:\(anchor.frameImageId):\(now):\(UUID().uuidString)", length: 12))"
        value.entries.insert(contentsOf: [
            ShotFrameEntry(entryId: childEntryId, frameImageId: childImageId.trimmed),
            ShotFrameEntry(entryId: returnEntryId, frameImageId: anchor.frameImageId)
        ], at: index + 1)
        value.updatedAt = now
        return (value, childEntryId, returnEntryId)
    }

    /// Gap insert within the row: the entry moves to `index` (index interpreted
    /// against the row BEFORE removal, matching where the user dropped).
    func movingEntry(entryId: String, toIndex index: Int, now: String) -> ProjectShot {
        guard let sourceIndex = entries.firstIndex(where: { $0.entryId == entryId }) else { return self }
        var value = self
        let entry = value.entries.remove(at: sourceIndex)
        var target = index
        if sourceIndex < index {
            target -= 1
        }
        let clamped = max(0, min(target, value.entries.count))
        value.entries.insert(entry, at: clamped)
        value.updatedAt = now
        return value
    }

    func removingEntry(entryId: String, now: String) -> ProjectShot {
        var value = self
        value.entries.removeAll { $0.entryId == entryId }
        value.updatedAt = now
        return value
    }

    func normalized() -> ProjectShot {
        var value = self
        value.shotId = value.shotId.trimmed
        value.name = value.name.trimmed
        value.entries = collapsingConsecutiveAIExtensionEntries(
            value.entries.filter { entry in
                !entry.entryId.trimmed.isEmpty
                    && (!entry.frameImageId.trimmed.isEmpty || entry.isClip || entry.isAIExtension)
            }
        )
        value.renderVersions = value.renderVersions.map { $0.normalized() }
        value.lookVersions = value.lookVersions
            .map { $0.normalized() }
            .filter { !$0.versionId.isEmpty }
        if !value.lookVersions.contains(where: { $0.versionId == value.activeLookVersionId && $0.isReady }) {
            value.activeLookVersionId = ""
        }
        value.clipLookVersions = value.clipLookVersions
            .map { $0.normalized() }
            .filter { !$0.versionId.isEmpty }
        value.segmentPromptOverrides = value.segmentPromptOverrides
            .map { $0.normalized() }
            // Empty start = an AI lead-in override (end-anchored); only a key
            // with NO frame on either side is junk.
            .filter {
                (!$0.startFrameImageId.isEmpty
                    || !$0.endFrameImageId.isEmpty
                    || !$0.placementStartEntryId.isEmpty
                    || !$0.placementEndEntryId.isEmpty)
                    && !$0.prompt.isEmpty
            }
        value.segmentRenderOverrides = pruningSegmentRenderOverrides(
            value.segmentRenderOverrides.map { $0.normalized() },
            entries: value.entries
        )
        value.segmentDirectionPlans = pruningSegmentDirectionPlans(
            value.segmentDirectionPlans,
            entries: value.entries
        )
        value.joinBridgeVersions = value.joinBridgeVersions
            .map { $0.normalized() }
            .filter { !$0.versionId.isEmpty && !$0.cutId.isEmpty }
        value.reverseProxies = value.reverseProxies
            .map { $0.normalized() }
            .filter { !$0.proxyId.isEmpty && !$0.sourcePath.isEmpty }
        value.cutList = value.cutList.normalized()
        value.audioMix = value.audioMix.normalized()
        value.combinedSources = value.combinedSources
            .map { $0.normalized() }
            .filter { !$0.sourceId.isEmpty && !$0.sourceCutId.isEmpty }
        let entryIds = Set(value.entries.map(\.entryId))
        value.sourceBoundaries = value.sourceBoundaries
            .map { $0.normalized() }
            .filter { !$0.boundaryId.isEmpty && entryIds.contains($0.rightEntryId) }
        value.seedSegmentClips = value.seedSegmentClips
            .map { $0.normalized() }
            .filter { !$0.clipPath.isEmpty }
        value.audioRegions = value.audioRegions
            .map { $0.normalized() }
            .filter { !$0.regionId.isEmpty && !$0.laneId.isEmpty && $0.durationSeconds > 0 }
        value.sourceSegmentAudio = pruningSourceSegmentAudio(
            value.sourceSegmentAudio,
            entries: value.entries
        )
        value.pictureInsertions = pruningPictureInsertions(
            value.pictureInsertions,
            entries: value.entries
        )
        value.migrateLegacyShotRenderPreferencesIfNeeded()
        value.migrateLegacyRenderArtifactIfNeeded()
        return value
    }
}

/// Reversible presentation collapse for a locally combined Shot. The source
/// rows remain canonical ProjectShot values; this record only hides them
/// while the independently editable combined parent is active.
struct CombinedShotGroup: Codable, Hashable, Identifiable, Sendable {
    var groupId: String = ""
    var parentShotId: String = ""
    var sourceShotIds: [String] = []
    var createdAt: String = ""

    var id: String { groupId }

    func normalized() -> CombinedShotGroup {
        var value = self
        value.groupId = value.groupId.trimmed
        value.parentShotId = value.parentShotId.trimmed
        value.createdAt = value.createdAt.trimmed
        var seen: Set<String> = []
        value.sourceShotIds = value.sourceShotIds
            .map(\.trimmed)
            .filter { !$0.isEmpty && $0 != value.parentShotId && seen.insert($0).inserted }
        return value
    }
}

/// Soft-delete ledger for a Shot. The ProjectShot row and every paid artifact
/// stay in the canonical timeline; this record only removes it from the live
/// canvas and remembers enough presentation state to restore it honestly.
struct TrashedShot: Codable, Hashable, Identifiable, Sendable {
    var entryId: String = ""
    var shotId: String = ""
    var formerVisibleIndex: Int = 0
    var combinedGroup: CombinedShotGroup?
    var trashedAt: String = ""

    var id: String { entryId }

    func normalized() -> TrashedShot {
        var value = self
        value.entryId = value.entryId.trimmed
        value.shotId = value.shotId.trimmed
        value.formerVisibleIndex = max(0, value.formerVisibleIndex)
        value.combinedGroup = value.combinedGroup?.normalized()
        value.trashedAt = value.trashedAt.trimmed
        return value
    }
}

struct ProjectShotTimelineDocument: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.shot_timeline.v0.3"
    static let documentType = "project_shot_timeline"
    static let flatOrganizationVersion = "flat_shots_v1"

    var schemaVersion: String = ProjectShotTimelineDocument.schemaVersion
    var projectId: String = ""
    var shots: [ProjectShot] = []
    var updatedAt: String = ""
    /// Empty on pre-flat documents. Once stamped, legacy Stage order must
    /// never overwrite later operator Shot reordering on a future launch.
    var organizationVersion: String = ""
    var trashedShots: [TrashedShot] = []
    var shotGroups: [CombinedShotGroup] = []

    static func empty(projectId: String) -> ProjectShotTimelineDocument {
        ProjectShotTimelineDocument(projectId: projectId)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case shots
        case updatedAt
        case organizationVersion
        case trashedShots
        case shotGroups
    }

    init(
        schemaVersion: String = ProjectShotTimelineDocument.schemaVersion,
        projectId: String = "",
        shots: [ProjectShot] = [],
        updatedAt: String = "",
        organizationVersion: String = "",
        trashedShots: [TrashedShot] = [],
        shotGroups: [CombinedShotGroup] = []
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.shots = shots
        self.updatedAt = updatedAt
        self.organizationVersion = organizationVersion
        self.trashedShots = trashedShots
        self.shotGroups = shotGroups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? Self.schemaVersion
        projectId = try container.decodeIfPresent(String.self, forKey: .projectId) ?? ""
        shots = try container.decodeIfPresent([ProjectShot].self, forKey: .shots) ?? []
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        organizationVersion = try container.decodeIfPresent(String.self, forKey: .organizationVersion) ?? ""
        trashedShots = try container.decodeIfPresent([TrashedShot].self, forKey: .trashedShots) ?? []
        shotGroups = try container.decodeIfPresent([CombinedShotGroup].self, forKey: .shotGroups) ?? []
    }

    func normalized() -> ProjectShotTimelineDocument {
        var value = self
        var seenShotIds: Set<String> = []
        value.shots = value.shots
            .map { $0.normalized() }
            .filter { !$0.shotId.isEmpty && seenShotIds.insert($0.shotId).inserted }
        let liveShotIds = Set(value.shots.map(\.shotId))

        var seenTrashIds: Set<String> = []
        var seenTrashedShots: Set<String> = []
        value.trashedShots = value.trashedShots
            .map { $0.normalized() }
            .filter {
                !$0.entryId.isEmpty
                    && liveShotIds.contains($0.shotId)
                    && seenTrashIds.insert($0.entryId).inserted
                    && seenTrashedShots.insert($0.shotId).inserted
            }
        let trashedIds = Set(value.trashedShots.map(\.shotId))

        var seenGroupIds: Set<String> = []
        var seenParents: Set<String> = []
        var claimedSources: Set<String> = []
        value.shotGroups = value.shotGroups
            .map { $0.normalized() }
            .filter { group in
                guard !group.groupId.isEmpty,
                      group.sourceShotIds.count >= 2,
                      liveShotIds.contains(group.parentShotId),
                      !trashedIds.contains(group.parentShotId),
                      group.sourceShotIds.allSatisfy(liveShotIds.contains),
                      group.sourceShotIds.allSatisfy({ !trashedIds.contains($0) }),
                      seenGroupIds.insert(group.groupId).inserted,
                      seenParents.insert(group.parentShotId).inserted else {
                    return false
                }
                guard group.sourceShotIds.allSatisfy({ !claimedSources.contains($0) }) else {
                    return false
                }
                claimedSources.formUnion(group.sourceShotIds)
                return true
            }
        value.organizationVersion = value.organizationVersion.trimmed
        return value
    }

    var trashedShotIds: Set<String> {
        Set(trashedShots.map(\.shotId))
    }

    var hiddenCombinedSourceShotIds: Set<String> {
        Set(
            shotGroups.flatMap(\.sourceShotIds)
                + trashedShots.compactMap(\.combinedGroup).flatMap(\.sourceShotIds)
        )
    }

    var visibleShots: [ProjectShot] {
        let hidden = hiddenCombinedSourceShotIds
        let trashed = trashedShotIds
        return shots.filter { !hidden.contains($0.shotId) && !trashed.contains($0.shotId) }
    }

    func group(parentShotId: String) -> CombinedShotGroup? {
        shotGroups.first { $0.parentShotId == parentShotId }
    }

    func group(containingSourceShotId shotId: String) -> CombinedShotGroup? {
        shotGroups.first { $0.sourceShotIds.contains(shotId) }
    }

    // MARK: Pure mutations

    func appendingShot(name: String, now: String) -> (document: ProjectShotTimelineDocument, shotId: String) {
        var value = self
        let shotId = "shot_\(shortHash("\(projectId):\(value.shots.count):\(now):\(UUID().uuidString)", length: 12))"
        value.shots.append(ProjectShot(shotId: shotId, name: name.trimmed, createdAt: now, updatedAt: now))
        value.updatedAt = now
        return (value, shotId)
    }

    func renamingShot(shotId: String, name: String, now: String) -> ProjectShotTimelineDocument {
        updatingShot(shotId: shotId, now: now) { shot in
            var value = shot
            value.name = name.trimmed
            value.updatedAt = now
            return value
        }
    }

    func deletingShot(shotId: String, now: String) -> ProjectShotTimelineDocument {
        var value = self
        value.shots.removeAll { $0.shotId == shotId }
        value.trashedShots.removeAll { $0.shotId == shotId }
        value.shotGroups.removeAll {
            $0.parentShotId == shotId || $0.sourceShotIds.contains(shotId)
        }
        value.updatedAt = now
        return value
    }

    /// Seam drop between rows: the shot moves to `index` (interpreted against
    /// the document BEFORE removal, matching where the user dropped —
    /// movingEntry semantics).
    func movingShot(shotId: String, toIndex index: Int, now: String) -> ProjectShotTimelineDocument {
        guard let sourceIndex = shots.firstIndex(where: { $0.shotId == shotId }) else { return self }
        var value = self
        let shot = value.shots.remove(at: sourceIndex)
        var target = index
        if sourceIndex < index {
            target -= 1
        }
        let clamped = max(0, min(target, value.shots.count))
        value.shots.insert(shot, at: clamped)
        value.updatedAt = now
        return value
    }

    /// Moves one VISIBLE Shot in the flat workspace. A combined parent carries
    /// its collapsed source rows as a block; hidden sources cannot move alone.
    func movingVisibleShot(shotId: String, toIndex index: Int, now: String) -> ProjectShotTimelineDocument {
        guard group(containingSourceShotId: shotId) == nil,
              visibleShots.contains(where: { $0.shotId == shotId }) else { return self }
        let carried = group(parentShotId: shotId)
        let blockIds = [shotId] + (carried?.sourceShotIds ?? [])
        let movingIds = Set(blockIds)
        let visibleIds = visibleShots.map(\.shotId)
        let clamped = max(0, min(index, visibleIds.count))
        let anchorId = clamped < visibleIds.count ? visibleIds[clamped] : nil
        if let anchorId, movingIds.contains(anchorId) { return self }

        var value = self
        let blockRows = blockIds.compactMap { id in value.shots.first { $0.shotId == id } }
        guard blockRows.count == blockIds.count else { return self }
        value.shots.removeAll { movingIds.contains($0.shotId) }
        let target = anchorId.flatMap { id in value.shots.firstIndex { $0.shotId == id } }
            ?? value.shots.count
        value.shots.insert(contentsOf: blockRows, at: max(0, min(target, value.shots.count)))
        value.updatedAt = now
        return value
    }

    func trashingShot(shotId: String, now: String) -> ProjectShotTimelineDocument {
        guard !shotId.isEmpty,
              !trashedShotIds.contains(shotId),
              group(containingSourceShotId: shotId) == nil,
              let visibleIndex = visibleShots.firstIndex(where: { $0.shotId == shotId }) else {
            return self
        }
        var value = self
        let combined = value.group(parentShotId: shotId)
        value.shotGroups.removeAll { $0.parentShotId == shotId }
        value.trashedShots.append(TrashedShot(
            entryId: "trash_\(shortHash("\(projectId):\(shotId):\(now):\(UUID().uuidString)", length: 12))",
            shotId: shotId,
            formerVisibleIndex: visibleIndex,
            combinedGroup: combined,
            trashedAt: now
        ))
        value.updatedAt = now
        return value
    }

    func restoringShot(trashEntryId: String, now: String) -> ProjectShotTimelineDocument {
        guard let row = trashedShots.first(where: { $0.entryId == trashEntryId }) else { return self }
        var value = self
        value.trashedShots.removeAll { $0.entryId == trashEntryId }
        if let group = row.combinedGroup,
           value.shots.contains(where: { $0.shotId == group.parentShotId }),
           group.sourceShotIds.allSatisfy({ id in value.shots.contains { $0.shotId == id } }) {
            value.shotGroups.removeAll { $0.parentShotId == group.parentShotId }
            value.shotGroups.append(group)
        }
        value.updatedAt = now
        return value.movingVisibleShot(shotId: row.shotId, toIndex: row.formerVisibleIndex, now: now)
    }

    /// Collapses adjacent visible source Shots under an independently editable
    /// combined parent already present in `shots`.
    func groupingCombinedShot(
        parentShotId: String,
        sourceShotIds: [String],
        now: String
    ) -> ProjectShotTimelineDocument {
        guard !parentShotId.isEmpty,
              sourceShotIds.count >= 2,
              let first = visibleShots.firstIndex(where: { $0.shotId == sourceShotIds[0] }),
              Array(visibleShots.dropFirst(first).prefix(sourceShotIds.count).map(\.shotId)) == sourceShotIds,
              shots.contains(where: { $0.shotId == parentShotId }) else {
            return self
        }
        var value = self
        value.shotGroups.removeAll { $0.parentShotId == parentShotId }
        value.shotGroups.append(CombinedShotGroup(
            groupId: "shot_group_\(shortHash("\(projectId):\(parentShotId):\(now):\(UUID().uuidString)", length: 12))",
            parentShotId: parentShotId,
            sourceShotIds: sourceShotIds,
            createdAt: now
        ))
        guard let parent = value.shots.first(where: { $0.shotId == parentShotId }) else {
            return self
        }
        value.shots.removeAll { $0.shotId == parentShotId }
        guard let sourceIndex = value.shots.firstIndex(where: { $0.shotId == sourceShotIds[0] }) else {
            return self
        }
        value.shots.insert(parent, at: sourceIndex)
        value.updatedAt = now
        return value.normalized()
    }

    func ungroupingCombinedShot(parentShotId: String, now: String) -> ProjectShotTimelineDocument {
        guard let visibleIndex = visibleShots.firstIndex(where: { $0.shotId == parentShotId }),
              group(parentShotId: parentShotId) != nil else { return self }
        var value = self
        value.shotGroups.removeAll { $0.parentShotId == parentShotId }
        value.trashedShots.append(TrashedShot(
            entryId: "trash_\(shortHash("\(projectId):\(parentShotId):\(now):\(UUID().uuidString)", length: 12))",
            shotId: parentShotId,
            formerVisibleIndex: visibleIndex,
            combinedGroup: nil,
            trashedAt: now
        ))
        value.updatedAt = now
        return value.normalized()
    }

    func updatingShot(shotId: String, now: String, _ transform: (ProjectShot) -> ProjectShot) -> ProjectShotTimelineDocument {
        guard let index = shots.firstIndex(where: { $0.shotId == shotId }) else { return self }
        var value = self
        value.shots[index] = transform(value.shots[index])
        value.updatedAt = now
        return value
    }
}

// MARK: - Drag payload

/// The drag payload for frame chips. `frameImageId` is required and NOT
/// defaulted so foreign JSON payloads (e.g. MediaIDTransfer) fail to decode
/// instead of arriving as empty transfers.
struct ShotFrameTransfer: Codable, Hashable, Transferable {
    var frameImageId: String
    var sourceShotId: String = ""
    var sourceEntryId: String = ""
    /// Footage drag: the video media item being placed (tray videos/trims and
    /// clip entries). Empty for frame drags.
    var clipMediaId: String = ""
    /// Stage-palette drags: the input row being carried, so a drop on another
    /// stage MOVES the reference instead of duplicating it. Empty for drags
    /// from the backlot, cut entries, or the footage sidebar.
    var sourceStageId: String = ""
    var sourceInputId: String = ""

    init(
        frameImageId: String,
        sourceShotId: String = "",
        sourceEntryId: String = "",
        clipMediaId: String = "",
        sourceStageId: String = "",
        sourceInputId: String = ""
    ) {
        self.frameImageId = frameImageId
        self.sourceShotId = sourceShotId
        self.sourceEntryId = sourceEntryId
        self.clipMediaId = clipMediaId
        self.sourceStageId = sourceStageId
        self.sourceInputId = sourceInputId
    }

    private enum CodingKeys: String, CodingKey {
        case frameImageId
        case sourceShotId
        case sourceEntryId
        case clipMediaId
        case sourceStageId
        case sourceInputId
    }

    private enum MediaAliasKeys: String, CodingKey {
        case mediaId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frameImageId = try container.decodeIfPresent(String.self, forKey: .frameImageId) ?? ""
        sourceShotId = try container.decodeIfPresent(String.self, forKey: .sourceShotId) ?? ""
        sourceEntryId = try container.decodeIfPresent(String.self, forKey: .sourceEntryId) ?? ""
        clipMediaId = try container.decodeIfPresent(String.self, forKey: .clipMediaId) ?? ""
        sourceStageId = try container.decodeIfPresent(String.self, forKey: .sourceStageId) ?? ""
        sourceInputId = try container.decodeIfPresent(String.self, forKey: .sourceInputId) ?? ""
        // MediaIDTransfer shares the .json content type, so a tray drag lands
        // here as a bare {mediaId} payload — read it as a footage drag.
        if frameImageId.isEmpty, clipMediaId.isEmpty,
           let aliasContainer = try? decoder.container(keyedBy: MediaAliasKeys.self) {
            clipMediaId = (try? aliasContainer.decodeIfPresent(String.self, forKey: .mediaId)) ?? ""
        }
        // Extension cells drag with only their entry identity (no frame, no
        // footage) — same-row moves still work through sourceEntryId.
        if frameImageId.isEmpty, clipMediaId.isEmpty, sourceEntryId.isEmpty {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "ShotFrameTransfer carries neither a frame, footage, nor an entry."
            ))
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }

    var isFromGrid: Bool { sourceShotId.trimmed.isEmpty }

    var isClipDrag: Bool { !clipMediaId.trimmed.isEmpty }
}

// MARK: - Meaning strand network (derived, never persisted, never edited)

enum MeaningStrandKind: String, Hashable, Sendable {
    case meaning
    case style
    case place
}

/// One cell position in the implied timeline: within a shot left→right, then
/// shot-to-shot top→bottom.
struct MeaningStrandTouch: Hashable, Sendable {
    var shotIndex: Int
    var entryIndex: Int
    var shotId: String
    var entryId: String
}

struct MeaningStrand: Hashable, Identifiable, Sendable {
    var strandId: String
    var kind: MeaningStrandKind
    var slug: String
    var label: String
    var detail: String
    var hueIndex: Int
    var touches: [MeaningStrandTouch]

    var id: String { strandId }
}

// MARK: - Shot rendering (keyframe-interpolated video per shot)

/// The model family shown in Shot render controls. A Shot stores a concrete
/// `ShotRenderStack` recipe so model and duration always resolve to an
/// executable provider request rather than two potentially invalid values.
enum ShotRenderModel: String, Codable, CaseIterable, Identifiable, Sendable {
    case wan27 = "wan_2_7"
    case falKlingV3Pro = "fal_kling_v3_pro"
    case falSeedance20 = "fal_seedance_2_0"
    case falSeedance25 = "fal_seedance_2_5"
    /// MiniMax Hailuo 3 (open-weights H3) and fal's post-trained fast
    /// variant (H3 Max). Both ship native stereo audio IN the file with no
    /// off switch — supportsGeneratedAudio stays false because there is no
    /// flag to send; the per-segment SOURCE-audio law governs the sound.
    case falHailuo3 = "fal_hailuo_3"
    case falHailuo3Max = "fal_hailuo_3_max"
    case falLTX23Narration = "fal_ltx_2_3_narration"
    /// Segment-only continuation of placed footage through LTX's native
    /// video-to-video Extend operation. It is deliberately absent from Shot
    /// defaults: only an AI extension immediately after real footage can run
    /// this operation honestly.
    case ltx23NativeExtend = "ltx_2_3_native_extend"
    /// Decode-only compatibility for historical Shot recipes. Current Shot
    /// controls never offer this model; Scenes retains its native provider.
    case klingV26Pro = "kling_v2_6_pro"

    var id: String { rawValue }

    static var allCases: [ShotRenderModel] {
        shotDefaultCases + [.ltx23NativeExtend]
    }

    static var shotDefaultCases: [ShotRenderModel] {
        [.wan27, .falKlingV3Pro, .falSeedance20, .falSeedance25, .falHailuo3, .falHailuo3Max, .falLTX23Narration]
    }

    var label: String {
        switch self {
        case .wan27: return "WAN 2.7"
        case .falKlingV3Pro: return "Kling 3 Pro"
        case .falSeedance20: return "Seedance 2.0"
        case .falSeedance25: return "Seedance 2.5"
        case .falHailuo3: return "Hailuo 3"
        case .falHailuo3Max: return "Hailuo 3 Max"
        case .falLTX23Narration: return "LTX 2.3 · Narration"
        case .ltx23NativeExtend: return "LTX 2.3 · Native Extend"
        case .klingV26Pro: return "Kling v2.6 Pro"
        }
    }

    var supportedDurations: [Int] {
        switch self {
        case .wan27: return [5, 6, 8, 10]
        case .falKlingV3Pro: return Array(3...15)
        case .falSeedance20: return Array(4...15)
        // The endpoint accepts up to 30s; capped at 15 for segment-scale
        // UI/pricing parity with the other stacks.
        case .falSeedance25: return Array(4...15)
        // The family supports 5–15s; the offered set is the locked
        // 5/10/15 vocabulary (a deliberate product decision).
        case .falHailuo3, .falHailuo3Max: return [5, 10, 15]
        // The executable duration is the authored narration driver's exact
        // duration. Five seconds is only a capability-probe/default value.
        case .falLTX23Narration: return [5]
        case .ltx23NativeExtend: return Array(2...20)
        case .klingV26Pro: return [5, 10]
        }
    }

    var defaultDuration: Int {
        switch self {
        case .wan27: return 8
        case .ltx23NativeExtend: return 8
        case .falKlingV3Pro, .falSeedance20, .falSeedance25, .falHailuo3, .falHailuo3Max, .falLTX23Narration, .klingV26Pro: return 5
        }
    }

    var providerSelection: VideoProviderSelection {
        switch self {
        case .wan27, .falKlingV3Pro, .falSeedance20, .falSeedance25, .falHailuo3, .falHailuo3Max: return .falImageToVideo
        case .falLTX23Narration: return .falAudioToVideo
        case .ltx23NativeExtend: return .ltxDirect
        case .klingV26Pro: return .klingImageToVideo
        }
    }

    var supportsGeneratedAudio: Bool {
        switch self {
        case .falKlingV3Pro, .falSeedance20, .falSeedance25, .ltx23NativeExtend: return true
        // Hailuo 3's audio is always on with no schema flag — not a choice,
        // so no "_audio" stack variant exists for it.
        case .wan27, .falHailuo3, .falHailuo3Max, .falLTX23Narration, .klingV26Pro: return false
        }
    }

    var requiresGeneratedAudio: Bool { self == .ltx23NativeExtend }

    /// True when any SELECTABLE stack can render an end-anchored AI lead-in.
    /// While false, lead-in affordances render honestly disabled — an entry
    /// nothing can render would be a selectable promise.
    static var anyLeadInCapable: Bool {
        allCases.contains {
            ShotRenderStack.fallback.replacingModel($0).tailAnchoredModelSelection != nil
        }
    }

}

/// THE HAILUO RESOLUTION PREFERENCE (a locked user choice):
/// a persisted app-level pick per Hailuo model, read at request-build time —
/// deliberately NOT part of `ShotRenderStack`'s rawValue grammar, so recipes
/// and persisted overrides are untouched. Offered sets are deliberate:
/// standard H3 offers 768P/2K only (its 2K/4K upscale from a 768P base — 4K
/// is a paid upscale, 480P is below the 720p pipeline); H3 Max's endpoint
/// tops out at 768P. Defaults are 768P — the pipeline's own scale.
/// The live-read idiom follows `ShotPlayerTransportPreference`.
enum Hailuo3ResolutionPreference {
    static let hailuo3Key = "LITSCENES_H3_RESOLUTION"
    static let hailuo3MaxKey = "LITSCENES_H3_MAX_RESOLUTION"

    static func choices(for model: ShotRenderModel) -> [String] {
        switch model {
        case .falHailuo3: return ["768P", "2K"]
        case .falHailuo3Max: return ["480P", "768P"]
        default: return []
        }
    }

    static func resolution(for model: ShotRenderModel) -> String {
        let key: String
        switch model {
        case .falHailuo3: key = hailuo3Key
        case .falHailuo3Max: key = hailuo3MaxKey
        default: return ""
        }
        let stored = LitScenesPreferences.store.string(forKey: key) ?? ""
        return choices(for: model).contains(stored) ? stored : "768P"
    }

    static func setResolution(_ value: String, for model: ShotRenderModel) {
        guard choices(for: model).contains(value) else { return }
        switch model {
        case .falHailuo3: LitScenesPreferences.store.set(value, forKey: hailuo3Key)
        case .falHailuo3Max: LitScenesPreferences.store.set(value, forKey: hailuo3MaxKey)
        default: break
        }
    }
}

/// The resolution tiers FAL video endpoints accept as an explicit request
/// field. Pixel dimensions are the 16:9 frame for the tier — the app renders
/// 16:9 throughout, and a portrait frame at the same tier carries the same
/// pixel count, so token math is orientation-independent.
enum FALVideoResolutionTier: String, Codable, Hashable, Sendable {
    case p720 = "720p"
    case p1080 = "1080p"

    var frameWidth: Int {
        switch self {
        case .p720: return 1280
        case .p1080: return 1920
        }
    }

    var frameHeight: Int {
        switch self {
        case .p720: return 720
        case .p1080: return 1080
        }
    }
}

/// FAL prices some video models by token bucket, reported through the pricing
/// API as the opaque unit `"units"` — NOT as a flat per-render fee. Seedance's
/// published formula:
///
///     tokens = (height × width × duration × fps) / 1024        billed per 1,000
///
/// Verified against FAL's own published rate: 720p @ 24fps works out to
/// 21,600 tokens/sec × $0.014 = $0.3024/sec, matching their stated figure.
/// At 1080p that is $0.6804/sec, so ONE four-second segment is 194.4 buckets
/// — reading `"units"` as flat under-bills it by that same factor.
struct FALTokenBilling: Equatable, Hashable, Sendable {
    var tier: FALVideoResolutionTier
    var fps: Int
    var tokensPerBilledUnit: Double = 1_000

    /// Billable units consumed by one segment of the given duration.
    func billedUnits(durationSeconds: Int) -> Double? {
        guard durationSeconds > 0, fps > 0, tokensPerBilledUnit > 0 else { return nil }
        let tokens = Double(tier.frameWidth * tier.frameHeight * durationSeconds * fps) / 1024
        return tokens / tokensPerBilledUnit
    }
}

/// A concrete, executable Shot render recipe. Existing raw values remain
/// stable for tolerant project decode. A value type avoids one enum case for
/// every provider duration while still rejecting non-executable pairings.
struct ShotRenderStack: RawRepresentable, Codable, Hashable, Sendable {
    let model: ShotRenderModel
    let segmentSeconds: Int
    let generateAudio: Bool

    static let fallback: ShotRenderStack = .wan27Eight
    static let wan27Five = recipe(model: .wan27, durationSeconds: 5)
    static let wan27Six = recipe(model: .wan27, durationSeconds: 6)
    static let wan27Eight = recipe(model: .wan27, durationSeconds: 8)
    static let wan27Ten = recipe(model: .wan27, durationSeconds: 10)
    /// Historical constants retained for artifact decoding and older callers.
    static let klingProFive = legacyKling(durationSeconds: 5)
    static let klingProTen = legacyKling(durationSeconds: 10)

    var rawValue: String {
        if model == .falLTX23Narration {
            return "fal_ltx_2_3_audio_to_video"
        }
        let base: String
        if model == .klingV26Pro {
            base = "kling_pro_\(segmentSeconds)s"
        } else {
            base = "\(model.rawValue)_\(segmentSeconds)s"
        }
        return generateAudio ? "\(base)_audio" : base
    }

    init?(rawValue: String) {
        let trimmed = rawValue.trimmed
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "fal_ltx_2_3_audio_to_video" {
            self = Self.recipe(model: .falLTX23Narration, durationSeconds: 5)
            return
        }

        let audioEnabled = trimmed.hasSuffix("_audio")
        let base = audioEnabled ? String(trimmed.dropLast("_audio".count)) : trimmed
        if base == "kling_pro_5s" || base == "kling_pro_10s" {
            guard !audioEnabled else { return nil }
            self = Self.legacyKling(durationSeconds: base == "kling_pro_10s" ? 10 : 5)
            return
        }

        for candidate in ShotRenderModel.allCases {
            let prefix = "\(candidate.rawValue)_"
            guard base.hasPrefix(prefix), base.hasSuffix("s") else { continue }
            let durationText = base.dropFirst(prefix.count).dropLast()
            // `continue`, never `return nil`, on a failed parse: one model's
            // rawValue may prefix another's (fal_hailuo_3 / fal_hailuo_3_max),
            // so a non-numeric remainder means "not this candidate", and the
            // loop's end still refuses anything no candidate claims.
            guard let duration = Int(durationText),
                  candidate.supportedDurations.contains(duration),
                  !audioEnabled || candidate.supportsGeneratedAudio else {
                continue
            }
            self.init(
                model: candidate,
                segmentSeconds: duration,
                generateAudio: audioEnabled
            )
            return
        }
        return nil
    }

    private init(model: ShotRenderModel, segmentSeconds: Int, generateAudio: Bool) {
        self.model = model
        self.segmentSeconds = segmentSeconds
        self.generateAudio = model.requiresGeneratedAudio
            || (model.supportsGeneratedAudio && generateAudio)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let value = ShotRenderStack(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown Shot render recipe \(rawValue)"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var shortLabel: String {
        if model == .falLTX23Narration {
            return model.label
        }
        return "\(model.label) · \(segmentSeconds)s\(generateAudio ? " · Audio" : "")"
    }

    var accurateHelp: String {
        switch model {
        case .wan27:
            return "FAL WAN 2.7 — one \(segmentSeconds)-second interpolated clip per adjacent frame pair; a single open-ended frame animates from its start frame alone."
        case .falKlingV3Pro:
            return "FAL Kling 3 Pro — one \(segmentSeconds)-second image-to-video clip per segment, with an optional target end frame and native audio \(generateAudio ? "enabled" : "disabled")."
        case .falSeedance20:
            return "FAL Seedance 2.0 — one \(segmentSeconds)-second 1080p image-to-video clip per segment, with an optional target end frame and native audio \(generateAudio ? "enabled" : "disabled")."
        case .falSeedance25:
            return "FAL Seedance 2.5 — one \(segmentSeconds)-second 720p image-to-video clip per segment, with an optional target end frame, timestamp-aware direction, and native audio \(generateAudio ? "enabled" : "disabled")."
        case .falHailuo3:
            return "FAL MiniMax Hailuo 3 — one \(segmentSeconds)-second \(Hailuo3ResolutionPreference.resolution(for: .falHailuo3)) image-to-video clip per segment, with an optional target end frame. Native stereo audio is always included — mute it per segment if unwanted."
        case .falHailuo3Max:
            return "FAL Hailuo 3 Max — fal's fast post-trained Hailuo 3: one \(segmentSeconds)-second \(Hailuo3ResolutionPreference.resolution(for: .falHailuo3Max)) image-to-video clip per segment (a 5s clip renders in seconds), with an optional target end frame. Native stereo audio is always included — mute it per segment if unwanted."
        case .falLTX23Narration:
            return "FAL LTX 2.3 Audio-to-Video — one shot-wide clip driven by the active ElevenLabs narration (2–20 seconds) and the first ready frame. Later frame cards remain in the cut but do not become keyframes."
        case .ltx23NativeExtend:
            return "LTX 2.3 Native Extend — continues the exact placed footage range for (segmentSeconds) seconds. The source is normalized to the Shot profile and its audio remains on the Source lane."
        case .klingV26Pro:
            return "Kling v2.6 — one native \(segmentSeconds)-second clip per segment. Paired frames use Pro mode with an image tail; a single open-ended frame uses Standard mode."
        }
    }

    var providerSelection: VideoProviderSelection {
        model.providerSelection
    }

    /// The model used for a first+last keyframe pair.
    var pairedModelSelection: VideoModelSelection {
        switch model {
        case .wan27: return .falWan27ImageToVideo
        case .falKlingV3Pro: return .falKlingV3ProImageToVideo
        case .falSeedance20: return .falSeedance20ImageToVideo
        case .falSeedance25: return .falSeedance25ImageToVideo
        case .falHailuo3: return .falHailuo3ImageToVideo
        case .falHailuo3Max: return .falHailuo3MaxImageToVideo
        case .falLTX23Narration: return .falLTX23AudioToVideo
        case .ltx23NativeExtend: return .ltxDirectDefault
        case .klingV26Pro: return .klingV26ImageToVideo
        }
    }

    /// The model used for a single-frame open-ended clip (no end keyframe).
    var openEndedModelSelection: VideoModelSelection {
        switch model {
        case .wan27: return .falWan27ImageToVideo
        case .falKlingV3Pro: return .falKlingV3ProImageToVideo
        case .falSeedance20: return .falSeedance20ImageToVideo
        case .falSeedance25: return .falSeedance25ImageToVideo
        case .falHailuo3: return .falHailuo3ImageToVideo
        case .falHailuo3Max: return .falHailuo3MaxImageToVideo
        case .falLTX23Narration: return .falLTX23AudioToVideo
        case .ltx23NativeExtend: return .ltxDirectDefault
        case .klingV26Pro: return .klingV26ImageToVideo
        }
    }

    /// The model used for an AI lead-in (end-anchored, no start keyframe), or
    /// nil when this stack's provider cannot accept a tail frame alone —
    /// refused honestly at plan/render time, never silently substituted.
    var tailAnchoredModelSelection: VideoModelSelection? {
        switch model {
        case .wan27: return nil            // FAL WAN 2.7 requires a start image (image_url/video_url)
        // FAL's Kling 3 Pro schema marks start_image_url REQUIRED (checked
        // last checked) even though Kling's native API takes image and/or
        // image_tail. Flip this after a tail-only submit probe (a schema 422
        // bills nothing) proves FAL accepts it.
        case .falKlingV3Pro: return nil
        case .falSeedance20: return nil    // tail-only unverified — honest nil
        case .falSeedance25: return nil    // tail-only unverified — honest nil
        case .falHailuo3: return nil       // tail-only unverified — honest nil
        case .falHailuo3Max: return nil    // tail-only unverified — honest nil
        case .falLTX23Narration: return nil
        case .ltx23NativeExtend: return nil
        // Native Kling documents image and/or image_tail — capable, but this
        // stack is decode-only legacy: upgradedForFutureRender rewrites it to
        // FAL Kling on every future-render path, so no plan item reaches it.
        case .klingV26Pro: return .klingV26ImageToVideo
        }
    }

    /// Single source for pair → model. Nil = this stack cannot render the
    /// pair (today: only a lead-in on a stack with no tail-anchored model).
    func modelSelection(for pair: ShotRenderPair) -> VideoModelSelection? {
        if model == .falLTX23Narration {
            return pair.start == nil ? nil : .falLTX23AudioToVideo
        }
        if pair.start == nil { return tailAnchoredModelSelection }
        return pair.end == nil ? openEndedModelSelection : pairedModelSelection
    }

    func replacingModel(_ model: ShotRenderModel) -> ShotRenderStack {
        ShotRenderStack.recipe(
            model: model,
            durationSeconds: model.supportedDurations.contains(segmentSeconds)
                ? segmentSeconds
                : model.defaultDuration,
            // Native audio defaults ON: crossing FROM a model with no audio
            // support seeds it on (there was no choice to preserve — OFF is
            // unrepresentable on WAN); between two audio-capable models the
            // user's explicit choice carries. The init clamp keeps non-audio
            // targets off.
            generateAudio: self.model.supportsGeneratedAudio ? generateAudio : true
        )
    }

    func replacingDuration(_ durationSeconds: Int) -> ShotRenderStack {
        ShotRenderStack.recipe(
            model: model,
            durationSeconds: durationSeconds,
            generateAudio: generateAudio
        )
    }

    func replacingGeneratedAudio(_ enabled: Bool) -> ShotRenderStack {
        ShotRenderStack.recipe(
            model: model,
            durationSeconds: segmentSeconds,
            generateAudio: enabled
        )
    }

    /// Old selectable Kling preferences become current FAL Kling preferences
    /// only where a future render recipe is resolved. Historical artifacts
    /// continue decoding to `.klingV26Pro` and therefore retain truthful copy.
    var upgradedForFutureRender: ShotRenderStack {
        guard model == .klingV26Pro else { return self }
        return ShotRenderStack.recipe(
            model: .falKlingV3Pro,
            durationSeconds: segmentSeconds,
            generateAudio: false
        )
    }

    var isNarrationDriven: Bool {
        model == .falLTX23Narration
    }

    var isNativeFootageExtend: Bool { model == .ltx23NativeExtend }

    /// Legacy two-state cycle retained for older callers and persisted tests;
    /// current UI uses explicit model and duration menus.
    var next: ShotRenderStack {
        model == .wan27 ? .klingProFive : .wan27Eight
    }

    static func recipe(
        model: ShotRenderModel,
        durationSeconds: Int,
        // Default ON — the init clamp keeps it off for
        // models with no native audio; explicit callers are unaffected.
        generateAudio: Bool = true
    ) -> ShotRenderStack {
        let resolvedDuration = model.supportedDurations.contains(durationSeconds)
            ? durationSeconds
            : model.defaultDuration
        return ShotRenderStack(
            model: model,
            segmentSeconds: resolvedDuration,
            generateAudio: generateAudio
        )
    }

    private static func legacyKling(durationSeconds: Int) -> ShotRenderStack {
        ShotRenderStack(
            model: .klingV26Pro,
            segmentSeconds: durationSeconds == 10 ? 10 : 5,
            generateAudio: false
        )
    }
}

/// The persisted record of a shot render: exactly what ran, its progress, and
/// where the output lives. Progress persists per segment so a relaunch shows
/// the truth.
/// The artifact video's own geometry, derived from what stitched it: probed
/// per-clip durations (matched by clipPath) minus the 3-frame handoff shave
/// on every join after the first. Seams are the interior cumulative offsets —
/// honest to ±3/24s (the shave is recomputed, not persisted), which is why
/// they are drawn as inert ticks and never used as snap magnets. Any
/// unresolved clipPath degrades the whole answer to the rounded total with no
/// fake seams.
func shotArtifactBandGeometry(_ artifact: ShotRenderArtifact) -> (durationSeconds: Double, seamSeconds: [Double]) {
    let handoffShaveSeconds = 3.0 / 24.0
    var durations: [Double] = []
    for path in artifact.clipPaths {
        guard let clip = artifact.segmentClips.first(where: { $0.clipPath == path }),
              clip.durationSeconds > 0 else {
            return (Double(artifact.totalSeconds), [])
        }
        durations.append(clip.durationSeconds)
    }
    guard !durations.isEmpty else { return (Double(artifact.totalSeconds), []) }
    var seams: [Double] = []
    var cursor: Double = 0
    for (index, duration) in durations.enumerated() {
        cursor += duration - (index > 0 ? handoffShaveSeconds : 0)
        if index < durations.count - 1 {
            seams.append(cursor)
        }
    }
    return (max(cursor, 0), seams)
}

struct ShotRenderArtifact: Codable, Hashable, Sendable {
    /// Stable version identity within the shot's renderVersions ("" only on
    /// legacy artifacts, repaired by the shot's migration).
    var versionId: String = ""
    /// 1-based, monotonically increasing per shot; drives sort order and the
    /// browser's roman numerals.
    var versionNumber: Int = 0
    var stack: String = ""
    var provider: String = ""
    var model: String = ""
    var status: String = ""          // "generating" | "ready" | "failed"
    var videoPath: String = ""
    var clipPaths: [String] = []
    var segmentCount: Int = 0
    var totalSeconds: Int = 0
    var progressText: String = ""
    var errorMessage: String = ""
    var requestIds: [String] = []
    /// Durable per-segment clips keyed by keyframe pair, so a later render can
    /// re-render one segment and reuse the rest.
    var segmentClips: [ShotRenderSegmentClip] = []
    /// The strip's entryIds snapshotted when this render started — the suffix
    /// watermark: entries after the last watermarked one are appendable while
    /// this version is the ready active render. Empty on legacy versions,
    /// which therefore keep the full freeze (NEW VERSION remains their path).
    var renderedEntryIds: [String] = []
    /// Exact narration-driver provenance for narration-driven video renders.
    var sourceNarrationTraceId: String = ""
    var sourceNarrationRegionId: String = ""
    var sourceNarrationFingerprint: String = ""
    var sourceNarrationDurationSeconds: Double = 0
    var sourceEntryId: String = ""
    var generatedAt: String = ""
    var updatedAt: String = ""

    var isReady: Bool {
        status == "ready" && !videoPath.trimmed.isEmpty
    }

    /// The saved clip for a placement, falling back only to a legacy
    /// pair-keyed record. A modern clip from a different duplicate placement
    /// must never satisfy the lookup.
    func segmentClip(
        placementStartEntryId: String,
        placementEndEntryId: String,
        forStart startId: String,
        end endId: String
    ) -> ShotRenderSegmentClip? {
        if !placementStartEntryId.isEmpty || !placementEndEntryId.isEmpty,
           let exact = segmentClips.first(where: {
               $0.placementStartEntryId == placementStartEntryId
                   && $0.placementEndEntryId == placementEndEntryId
                   && (!$0.placementStartEntryId.isEmpty || !$0.placementEndEntryId.isEmpty)
           }) {
            return exact
        }
        return segmentClips.first {
            $0.placementStartEntryId.isEmpty
                && $0.placementEndEntryId.isEmpty
                && $0.startFrameImageId == startId
                && $0.endFrameImageId == endId
        }
    }

    /// Legacy convenience for callers that do not yet have a placement.
    func segmentClip(forStart startId: String, end endId: String) -> ShotRenderSegmentClip? {
        segmentClip(
            placementStartEntryId: "",
            placementEndEntryId: "",
            forStart: startId,
            end: endId
        )
    }

    /// One record per pair key: replaces any existing record for the clip's pair.
    mutating func upsertSegmentClip(_ clip: ShotRenderSegmentClip) {
        if !clip.placementStartEntryId.isEmpty || !clip.placementEndEntryId.isEmpty {
            segmentClips.removeAll {
                $0.placementStartEntryId == clip.placementStartEntryId
                    && $0.placementEndEntryId == clip.placementEndEntryId
                    && (!$0.placementStartEntryId.isEmpty || !$0.placementEndEntryId.isEmpty)
            }
        } else {
            segmentClips.removeAll {
                $0.placementStartEntryId.isEmpty
                    && $0.placementEndEntryId.isEmpty
                    && $0.startFrameImageId == clip.startFrameImageId
                    && $0.endFrameImageId == clip.endFrameImageId
            }
        }
        segmentClips.append(clip)
    }

    func normalized() -> ShotRenderArtifact {
        var value = self
        value.versionId = value.versionId.trimmed
        value.stack = value.stack.trimmed
        value.provider = value.provider.trimmed
        value.model = value.model.trimmed
        value.status = value.status.trimmed
        value.videoPath = value.videoPath.trimmed
        value.clipPaths = value.clipPaths.map { $0.trimmed }.filter { !$0.isEmpty }
        value.progressText = value.progressText.trimmed
        value.errorMessage = value.errorMessage.trimmed
        value.requestIds = value.requestIds.map { $0.trimmed }.filter { !$0.isEmpty }
        value.segmentClips = value.segmentClips.map { $0.normalized() }.filter { !$0.clipPath.isEmpty }
        value.renderedEntryIds = value.renderedEntryIds.map { $0.trimmed }.filter { !$0.isEmpty }
        value.sourceNarrationTraceId = value.sourceNarrationTraceId.trimmed
        value.sourceNarrationRegionId = value.sourceNarrationRegionId.trimmed
        value.sourceNarrationFingerprint = value.sourceNarrationFingerprint.trimmed
        value.sourceNarrationDurationSeconds = max(
            value.sourceNarrationDurationSeconds.isFinite ? value.sourceNarrationDurationSeconds : 0,
            0
        )
        value.sourceEntryId = value.sourceEntryId.trimmed
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case versionId, versionNumber
        case stack, provider, model, status, videoPath, clipPaths, segmentCount
        case totalSeconds, progressText, errorMessage, requestIds, segmentClips, renderedEntryIds
        case sourceNarrationTraceId, sourceNarrationRegionId, sourceNarrationFingerprint
        case sourceNarrationDurationSeconds, sourceEntryId, generatedAt, updatedAt
    }

    init(
        versionId: String = "",
        versionNumber: Int = 0,
        stack: String = "",
        provider: String = "",
        model: String = "",
        status: String = "",
        videoPath: String = "",
        clipPaths: [String] = [],
        segmentCount: Int = 0,
        totalSeconds: Int = 0,
        progressText: String = "",
        errorMessage: String = "",
        requestIds: [String] = [],
        segmentClips: [ShotRenderSegmentClip] = [],
        renderedEntryIds: [String] = [],
        sourceNarrationTraceId: String = "",
        sourceNarrationRegionId: String = "",
        sourceNarrationFingerprint: String = "",
        sourceNarrationDurationSeconds: Double = 0,
        sourceEntryId: String = "",
        generatedAt: String = "",
        updatedAt: String = ""
    ) {
        self.versionId = versionId
        self.versionNumber = versionNumber
        self.stack = stack
        self.provider = provider
        self.model = model
        self.status = status
        self.videoPath = videoPath
        self.clipPaths = clipPaths
        self.segmentCount = segmentCount
        self.totalSeconds = totalSeconds
        self.progressText = progressText
        self.errorMessage = errorMessage
        self.requestIds = requestIds
        self.segmentClips = segmentClips
        self.renderedEntryIds = renderedEntryIds
        self.sourceNarrationTraceId = sourceNarrationTraceId
        self.sourceNarrationRegionId = sourceNarrationRegionId
        self.sourceNarrationFingerprint = sourceNarrationFingerprint
        self.sourceNarrationDurationSeconds = sourceNarrationDurationSeconds
        self.sourceEntryId = sourceEntryId
        self.generatedAt = generatedAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        versionId = try container.decodeIfPresent(String.self, forKey: .versionId) ?? ""
        versionNumber = try container.decodeIfPresent(Int.self, forKey: .versionNumber) ?? 0
        stack = try container.decodeIfPresent(String.self, forKey: .stack) ?? ""
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        videoPath = try container.decodeIfPresent(String.self, forKey: .videoPath) ?? ""
        clipPaths = try container.decodeIfPresent([String].self, forKey: .clipPaths) ?? []
        segmentCount = try container.decodeIfPresent(Int.self, forKey: .segmentCount) ?? 0
        totalSeconds = try container.decodeIfPresent(Int.self, forKey: .totalSeconds) ?? 0
        progressText = try container.decodeIfPresent(String.self, forKey: .progressText) ?? ""
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
        requestIds = try container.decodeIfPresent([String].self, forKey: .requestIds) ?? []
        segmentClips = ((try? container.decodeIfPresent([ShotRenderSegmentClip].self, forKey: .segmentClips)) ?? nil) ?? []
        renderedEntryIds = try container.decodeIfPresent([String].self, forKey: .renderedEntryIds) ?? []
        sourceNarrationTraceId = try container.decodeIfPresent(String.self, forKey: .sourceNarrationTraceId) ?? ""
        sourceNarrationRegionId = try container.decodeIfPresent(String.self, forKey: .sourceNarrationRegionId) ?? ""
        sourceNarrationFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceNarrationFingerprint) ?? ""
        sourceNarrationDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceNarrationDurationSeconds) ?? 0
        sourceEntryId = try container.decodeIfPresent(String.self, forKey: .sourceEntryId) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

/// One durable segment clip of a shot render, keyed by the keyframe pair that
/// produced it ("" endFrameImageId = the open-ended single-frame segment).
/// Records the prompt that actually rendered. Clip files live in the project's
/// proof directory and are never deleted (consistent with render versions).
struct ShotRenderSegmentClip: Codable, Hashable, Sendable {
    var startFrameImageId: String = ""
    var endFrameImageId: String = ""
    var placementStartEntryId: String = ""
    var placementEndEntryId: String = ""
    var clipPath: String = ""
    var requestId: String = ""
    var prompt: String = ""
    var provider: String = ""
    var model: String = ""
    var providerOperation: String = ""
    var traceId: String = ""
    var generateAudio: Bool = false
    var resolution: String = ""
    var requestedDurationSeconds: Int = 0
    /// Measured visual-track duration of the durable clip.
    var durationSeconds: Double = 0
    /// Original paid/local artifact provenance when this record is reused as
    /// an editable combined-CUT seed.
    var sourceCutId: String = ""
    var sourceRenderVersionId: String = ""
    var sourceMediaId: String = ""
    var sourceRangeStartSeconds: Double = 0
    var sourceRangeEndSeconds: Double = 0
    var sourceFingerprint: String = ""
    /// Temporal-direction provenance: the plan snapshot that compiled this
    /// clip's prompt, the multi_prompt array actually sent (nil = plain
    /// prompt), the dialect label, and the compiler version — so a re-render
    /// diff can tell "new beats" from "same beats, new compiler". All empty
    /// on pre-TDP and plan-less clips; `prompt` stays the canonical text the
    /// artifact wears.
    var directionPlan: ShotTemporalDirectionPlan?
    var compiledMultiShots: [ShotCompiledKlingShot]?
    var compiledDialect: String = ""
    var compilerVersion: Int = 0
    var updatedAt: String = ""

    var pairKey: String { "\(startFrameImageId)>\(endFrameImageId)" }
    var placementKey: String {
        shotPlacementSegmentKey(
            startEntryId: placementStartEntryId,
            endEntryId: placementEndEntryId,
            legacyStartId: startFrameImageId,
            legacyEndId: endFrameImageId
        )
    }

    func normalized() -> ShotRenderSegmentClip {
        var value = self
        value.startFrameImageId = value.startFrameImageId.trimmed
        value.endFrameImageId = value.endFrameImageId.trimmed
        value.placementStartEntryId = value.placementStartEntryId.trimmed
        value.placementEndEntryId = value.placementEndEntryId.trimmed
        value.clipPath = value.clipPath.trimmed
        value.requestId = value.requestId.trimmed
        value.prompt = value.prompt.trimmed
        value.provider = value.provider.trimmed
        value.model = value.model.trimmed
        value.providerOperation = value.providerOperation.trimmed
        value.traceId = value.traceId.trimmed
        value.resolution = value.resolution.trimmed
        value.requestedDurationSeconds = max(value.requestedDurationSeconds, 0)
        value.durationSeconds = max(value.durationSeconds.isFinite ? value.durationSeconds : 0, 0)
        value.sourceCutId = value.sourceCutId.trimmed
        value.sourceRenderVersionId = value.sourceRenderVersionId.trimmed
        value.sourceMediaId = value.sourceMediaId.trimmed
        value.sourceRangeStartSeconds = max(value.sourceRangeStartSeconds.isFinite ? value.sourceRangeStartSeconds : 0, 0)
        value.sourceRangeEndSeconds = max(value.sourceRangeEndSeconds.isFinite ? value.sourceRangeEndSeconds : 0, value.sourceRangeStartSeconds)
        value.sourceFingerprint = value.sourceFingerprint.trimmed
        value.directionPlan = value.directionPlan?.normalized()
        value.compiledDialect = value.compiledDialect.trimmed
        value.compilerVersion = max(value.compilerVersion, 0)
        value.updatedAt = value.updatedAt.trimmed
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case startFrameImageId, endFrameImageId
        case placementStartEntryId, placementEndEntryId
        case clipPath, requestId, prompt
        case provider, model, providerOperation, traceId, generateAudio, resolution
        case requestedDurationSeconds, durationSeconds
        case sourceCutId, sourceRenderVersionId
        case sourceMediaId, sourceRangeStartSeconds, sourceRangeEndSeconds, sourceFingerprint
        case updatedAt
        case directionPlan, compiledMultiShots, compiledDialect, compilerVersion
    }

    init(
        startFrameImageId: String = "",
        endFrameImageId: String = "",
        placementStartEntryId: String = "",
        placementEndEntryId: String = "",
        clipPath: String = "",
        requestId: String = "",
        prompt: String = "",
        provider: String = "",
        model: String = "",
        providerOperation: String = "",
        traceId: String = "",
        generateAudio: Bool = false,
        resolution: String = "",
        requestedDurationSeconds: Int = 0,
        durationSeconds: Double = 0,
        sourceCutId: String = "",
        sourceRenderVersionId: String = "",
        sourceMediaId: String = "",
        sourceRangeStartSeconds: Double = 0,
        sourceRangeEndSeconds: Double = 0,
        sourceFingerprint: String = "",
        directionPlan: ShotTemporalDirectionPlan? = nil,
        compiledMultiShots: [ShotCompiledKlingShot]? = nil,
        compiledDialect: String = "",
        compilerVersion: Int = 0,
        updatedAt: String = ""
    ) {
        self.startFrameImageId = startFrameImageId
        self.endFrameImageId = endFrameImageId
        self.placementStartEntryId = placementStartEntryId
        self.placementEndEntryId = placementEndEntryId
        self.clipPath = clipPath
        self.requestId = requestId
        self.prompt = prompt
        self.provider = provider
        self.model = model
        self.providerOperation = providerOperation
        self.traceId = traceId
        self.generateAudio = generateAudio
        self.resolution = resolution
        self.requestedDurationSeconds = requestedDurationSeconds
        self.durationSeconds = durationSeconds
        self.sourceCutId = sourceCutId
        self.sourceRenderVersionId = sourceRenderVersionId
        self.sourceMediaId = sourceMediaId
        self.sourceRangeStartSeconds = sourceRangeStartSeconds
        self.sourceRangeEndSeconds = sourceRangeEndSeconds
        self.sourceFingerprint = sourceFingerprint
        self.directionPlan = directionPlan
        self.compiledMultiShots = compiledMultiShots
        self.compiledDialect = compiledDialect
        self.compilerVersion = compilerVersion
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startFrameImageId = try container.decodeIfPresent(String.self, forKey: .startFrameImageId) ?? ""
        endFrameImageId = try container.decodeIfPresent(String.self, forKey: .endFrameImageId) ?? ""
        placementStartEntryId = try container.decodeIfPresent(String.self, forKey: .placementStartEntryId) ?? ""
        placementEndEntryId = try container.decodeIfPresent(String.self, forKey: .placementEndEntryId) ?? ""
        clipPath = try container.decodeIfPresent(String.self, forKey: .clipPath) ?? ""
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId) ?? ""
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        providerOperation = try container.decodeIfPresent(String.self, forKey: .providerOperation) ?? ""
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId) ?? ""
        generateAudio = try container.decodeIfPresent(Bool.self, forKey: .generateAudio) ?? false
        resolution = try container.decodeIfPresent(String.self, forKey: .resolution) ?? ""
        requestedDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .requestedDurationSeconds) ?? 0
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        sourceCutId = try container.decodeIfPresent(String.self, forKey: .sourceCutId) ?? ""
        sourceRenderVersionId = try container.decodeIfPresent(String.self, forKey: .sourceRenderVersionId) ?? ""
        sourceMediaId = try container.decodeIfPresent(String.self, forKey: .sourceMediaId) ?? ""
        sourceRangeStartSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceRangeStartSeconds) ?? 0
        sourceRangeEndSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceRangeEndSeconds) ?? 0
        sourceFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceFingerprint) ?? ""
        directionPlan = (try? container.decodeIfPresent(ShotTemporalDirectionPlan.self, forKey: .directionPlan)) ?? nil
        compiledMultiShots = (try? container.decodeIfPresent([ShotCompiledKlingShot].self, forKey: .compiledMultiShots)) ?? nil
        compiledDialect = try container.decodeIfPresent(String.self, forKey: .compiledDialect) ?? ""
        compilerVersion = try container.decodeIfPresent(Int.self, forKey: .compilerVersion) ?? 0
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

/// One render segment: `end == nil` ⇒ the open-ended clip animating forward
/// from `start`; `start == nil` ⇒ the AI lead-in arriving end-anchored ON
/// `end`. Never both nil — every segment has at least one real keyframe.
struct ShotRenderPair {
    var start: ProjectLensHeroImage?
    var end: ProjectLensHeroImage?
    /// Placement identity is canonical for new writes. An empty side retains
    /// semantic meaning (lead-in/open-ended); extension entries occupy that
    /// side when present so repeated frame pairs never alias.
    var startPlacementEntryId: String = ""
    var endPlacementEntryId: String = ""

    /// Legacy content identity retained for tolerant reads.
    var segmentKey: String { "\(start?.imageId ?? "")>\(end?.imageId ?? "")" }

    /// Canonical placement identity, with a legacy fallback for plans created
    /// without entry ids.
    var placementKey: String {
        shotPlacementSegmentKey(
            startEntryId: startPlacementEntryId,
            endEntryId: endPlacementEntryId,
            legacyStartId: start?.imageId ?? "",
            legacyEndId: end?.imageId ?? ""
        )
    }
}

func shotPlacementSegmentKey(
    startEntryId: String,
    endEntryId: String,
    legacyStartId: String,
    legacyEndId: String
) -> String {
    let start = startEntryId.trimmed
    let end = endEntryId.trimmed
    guard !start.isEmpty || !end.isEmpty else {
        return "\(legacyStartId)>\(legacyEndId)"
    }
    return "entry:\(start)>\(end)"
}

/// Ready frames in entry order become interpolation pairs; anything not ready
/// (or missing) is skipped and REPORTED, never faked into a keyframe.
func shotRenderPairs(
    shot: ProjectShot,
    frameLookup: [String: ProjectLensHeroImage]
) -> (pairs: [ShotRenderPair], skipped: [String]) {
    var ready: [(frame: ProjectLensHeroImage, entryId: String)] = []
    var skipped: [String] = []
    for entry in shot.entries {
        // Deliberate skips are choices, not not-ready reports.
        if entry.isSkipped { continue }
        if let frame = frameLookup[entry.frameImageId],
           frame.status == "ready",
           !frame.imagePath.trimmed.isEmpty {
            ready.append((frame, entry.entryId))
        } else {
            let label = frameLookup[entry.frameImageId]?.label.trimmed.nilIfEmpty ?? entry.frameImageId
            skipped.append(label)
        }
    }
    if ready.isEmpty {
        return ([], skipped)
    }
    if ready.count == 1 {
        return ([ShotRenderPair(
            start: ready[0].frame,
            end: nil,
            startPlacementEntryId: ready[0].entryId
        )], skipped)
    }
    let pairs = zip(ready, ready.dropFirst()).map {
        ShotRenderPair(
            start: $0.frame,
            end: $1.frame,
            startPlacementEntryId: $0.entryId,
            endPlacementEntryId: $1.entryId
        )
    }
    return (pairs, skipped)
}

/// The four lineage-derived motion sentences (see `shotReframeLineagePrompt`).
/// One sentence, no digits, no percentages, destination-anchored exactly like
/// the generic defaults below.
let shotReframePushInPrompt =
    "The camera pushes in steadily on the same continuous scene, tightening until it settles "
        + "on the exact framing of the last frame."
let shotReframePullOutPrompt =
    "The camera pulls back steadily within the same continuous scene, widening until it settles "
        + "on the exact framing of the last frame."
let shotReframeVantagePrompt =
    "The camera travels smoothly to a new vantage of the same continuous scene, arriving "
        + "on the exact framing of the last frame."
let shotReframeVantageReturnPrompt =
    "The camera travels smoothly back within the same continuous scene, arriving "
        + "on the exact framing of the last frame."

/// LINEAGE-DERIVED motion default: when one side of an adjacent pair is the
/// other's reframe CHILD (`spec.parentImageId`), the camera relationship
/// between the keyframes is a derived structural FACT — say it, in ONE clean
/// sentence with zero geometry echo. This deliberately softens the
/// authored-by-hand law in the `shotSegmentPrompt` header: lineage is not
/// authored prose and cannot restate reframe descriptors or percentages.
/// `parentRenderVersionId` is IGNORED on purpose — the strip places IMAGES,
/// and a re-rendered parent keeps its imageId, so the camera relationship
/// holds across versions. Detection is content-keyed (image ids), so every
/// placement of the pair — the punch-in return, duplicate reuse entries, and
/// hand-assembled chains — earns the default for free. Viewpoint sentences
/// deliberately omit the compass `promptPhrase` (it references source-frame
/// geometry — exactly the banned echo). Unknown or reserved modes fall to the
/// zoom family.
func shotReframeLineagePrompt(pair: ShotRenderPair) -> String? {
    guard let start = pair.start, let end = pair.end else { return nil }
    // Forward first: the destination is the child (the dive). The reverse
    // cannot simultaneously hold — children mint after parents, ids never
    // cycle — so forward-first is deterministic even against odd documents.
    if let spec = end.reframe, !spec.parentImageId.isEmpty, spec.parentImageId == start.imageId {
        if spec.isZoomOut { return shotReframePullOutPrompt }
        if spec.isViewpoint { return shotReframeVantagePrompt }
        return shotReframePushInPrompt
    }
    // Reverse: the origin is the child (the return).
    if let spec = start.reframe, !spec.parentImageId.isEmpty, spec.parentImageId == end.imageId {
        if spec.isZoomOut { return shotReframePushInPrompt }
        if spec.isViewpoint { return shotReframeVantageReturnPrompt }
        return shotReframePullOutPrompt
    }
    return nil
}

/// Motion-directed, content-only segment prompt — deliberately ONE sentence.
///
/// This used to append the destination frame's gist, the shot's meaning-strand
/// motifs, and a no-cuts/no-captions tail. All three restated in prose what the
/// keyframes already carry, and the destination gist in particular echoed the
/// frame's own authoring prompt (reframe descriptors and their percentage
/// geometry included), so the segment read as a wall of instruction competing
/// with the images instead of directing motion between them. Per-segment
/// intent is now authored by hand in the render plan, where the edit persists
/// per frame pair. One locked-in exception: reframe-lineage adjacency
/// yields a lineage-derived motion sentence (`shotReframeLineagePrompt`) —
/// derived structure, not authored prose, still one sentence, still zero
/// geometry.
func shotSegmentPrompt(pair: ShotRenderPair) -> String {
    if pair.start == nil {
        return "Begin in motion and arrive naturally on the final frame exactly as depicted."
    }
    if pair.end == nil {
        return "Bring this scene to life with gentle, continuous motion true to what is depicted."
    }
    if let lineage = shotReframeLineagePrompt(pair: pair) { return lineage }
    return "Smooth continuous camera and subject motion from the first frame to the last frame."
}

/// The NARRATION-DRIVEN default (LTX audio-to-video): lip-sync has to be
/// ASKED for. This branch used the generic open-ended fallback above, which
/// says nothing about anyone SPEAKING — and the model obliged with ambient
/// motion and a closed mouth. An authored per-segment override
/// still wins verbatim; this only replaces the silence.
func shotNarrationDrivenSegmentPrompt() -> String {
    "The person in frame speaks the narration aloud to camera — natural lip-sync and facial "
        + "articulation matching the voice, with small true-to-scene head and gesture motion; "
        + "everything else stays as depicted."
}

/// A user's persisted edit to one segment's render prompt, keyed by the frame
/// image ids that define the segment — the pair IS what renders, so overrides
/// survive reorders and silently stop matching when the pair stops existing.
/// An empty `endFrameImageId` keys the single-frame open-ended segment. If the
/// same image pair appears twice in one shot, both segments share the override.
struct ShotSegmentPromptOverride: Codable, Hashable, Sendable {
    var startFrameImageId: String = ""
    var endFrameImageId: String = ""
    var placementStartEntryId: String = ""
    var placementEndEntryId: String = ""
    var prompt: String = ""
    var updatedAt: String = ""

    private enum CodingKeys: String, CodingKey {
        case startFrameImageId
        case endFrameImageId
        case placementStartEntryId
        case placementEndEntryId
        case prompt
        case updatedAt
    }

    init(
        startFrameImageId: String = "",
        endFrameImageId: String = "",
        placementStartEntryId: String = "",
        placementEndEntryId: String = "",
        prompt: String = "",
        updatedAt: String = ""
    ) {
        self.startFrameImageId = startFrameImageId
        self.endFrameImageId = endFrameImageId
        self.placementStartEntryId = placementStartEntryId
        self.placementEndEntryId = placementEndEntryId
        self.prompt = prompt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startFrameImageId = try container.decodeIfPresent(String.self, forKey: .startFrameImageId) ?? ""
        endFrameImageId = try container.decodeIfPresent(String.self, forKey: .endFrameImageId) ?? ""
        placementStartEntryId = try container.decodeIfPresent(String.self, forKey: .placementStartEntryId) ?? ""
        placementEndEntryId = try container.decodeIfPresent(String.self, forKey: .placementEndEntryId) ?? ""
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    func normalized() -> ShotSegmentPromptOverride {
        var value = self
        value.startFrameImageId = value.startFrameImageId.trimmed
        value.endFrameImageId = value.endFrameImageId.trimmed
        value.placementStartEntryId = value.placementStartEntryId.trimmed
        value.placementEndEntryId = value.placementEndEntryId.trimmed
        value.prompt = value.prompt.trimmed
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

/// Drops overrides whose frames are no longer anywhere in the shot's strip;
/// overrides for still-present but currently non-adjacent pairs survive (the
/// user may reorder the pair back together). Later entries win a duplicate key.
func pruningSegmentPromptOverrides(
    _ overrides: [ShotSegmentPromptOverride],
    entries: [ShotFrameEntry]
) -> [ShotSegmentPromptOverride] {
    let presentEntryIds = Set(entries.map(\.entryId))
    var presentIds = Set(entries.map(\.frameImageId))
    // Clip/extension entries carry an empty frameImageId — never let "" count
    // as a present frame (it would legitimize junk ">"-only keys).
    presentIds.remove("")
    for entry in entries where entry.isClip {
        let ids = shotFootageBoundaryFrameIds(
            mediaId: entry.clipMediaId,
            startSeconds: entry.clipStartSeconds,
            endSeconds: entry.clipEndSeconds
        )
        presentIds.insert(ids.start)
        presentIds.insert(ids.end)
    }
    var seenKeys = Set<String>()
    var kept: [ShotSegmentPromptOverride] = []
    for rawOverride in overrides.reversed() {
        let override = rawOverride.normalized()
        let key = shotPlacementSegmentKey(
            startEntryId: override.placementStartEntryId,
            endEntryId: override.placementEndEntryId,
            legacyStartId: override.startFrameImageId,
            legacyEndId: override.endFrameImageId
        )
        if !override.placementStartEntryId.isEmpty || !override.placementEndEntryId.isEmpty {
            let startOK = override.placementStartEntryId.isEmpty
                || presentEntryIds.contains(override.placementStartEntryId)
            let endOK = override.placementEndEntryId.isEmpty
                || presentEntryIds.contains(override.placementEndEntryId)
            guard !seenKeys.contains(key), startOK, endOK else { continue }
            seenKeys.insert(key)
            kept.append(override)
            continue
        }
        // Empty start = lead-in (anchor must be present); empty end =
        // open-ended (start must be present); both empty is never legal.
        let startOK = override.startFrameImageId.isEmpty
            ? !override.endFrameImageId.isEmpty
            : presentIds.contains(override.startFrameImageId)
        let endOK = override.endFrameImageId.isEmpty
            ? !override.startFrameImageId.isEmpty
            : presentIds.contains(override.endFrameImageId)
        guard !seenKeys.contains(key), startOK, endOK else {
            continue
        }
        seenKeys.insert(key)
        kept.append(override)
    }
    return kept.reversed()
}

/// The override set to persist from a drafts-keyed prompt editor. Drafts key
/// by the STABLE keyframe pair (`pairKey`), never the positional row id —
/// inserting or reordering entries while an editor is open must not orphan
/// its drafts, and a save must never wipe overrides the editor never showed.
/// Per pair: an ABSENT draft carries the existing override forward; a
/// present-but-empty draft is a deliberate clear (nothing stored, the
/// generated prompt renders); a draft equal to the generated prompt stores
/// nothing. The first of a duplicated keyframe pair wins its shared key.
/// Shared by the re-render panel and the inline render-plan strip so both
/// save identically.
func computedSegmentPromptOverrides(
    drafts: [String: String],
    items: [ShotSegmentPromptPlanItem],
    now: String
) -> [ShotSegmentPromptOverride] {
    var seenKeys = Set<String>()
    var overrides: [ShotSegmentPromptOverride] = []
    for item in items {
        let key = item.pairKey
        let draft = (drafts[key] ?? item.overridePrompt ?? "").trimmed
        guard !draft.isEmpty,
              draft != item.generatedPrompt.trimmed,
              !seenKeys.contains(key) else {
            continue
        }
        seenKeys.insert(key)
        overrides.append(ShotSegmentPromptOverride(
            startFrameImageId: item.pair.start?.imageId ?? "",
            endFrameImageId: item.pair.end?.imageId ?? "",
            placementStartEntryId: item.pair.startPlacementEntryId,
            placementEndEntryId: item.pair.endPlacementEntryId,
            prompt: draft,
            updatedAt: now
        ))
    }
    return overrides
}

/// The draft-autosave law: an UPSERT-ONLY union. Computed entries overlay
/// existing overrides by pair key; keys the computed set omits (drafts that
/// are momentarily empty or equal to the generated prompt) KEEP their
/// existing override — deleting an override stays a confirm/RESET-time
/// behavior, so a transient select-all-retype can never eat persisted work.
func mergedAutosavePromptOverrides(
    existing: [ShotSegmentPromptOverride],
    computed: [ShotSegmentPromptOverride]
) -> [ShotSegmentPromptOverride] {
    var byKey: [String: ShotSegmentPromptOverride] = [:]
    var order: [String] = []
    for override in existing + computed {
        let key = shotPlacementSegmentKey(
            startEntryId: override.placementStartEntryId,
            endEntryId: override.placementEndEntryId,
            legacyStartId: override.startFrameImageId,
            legacyEndId: override.endFrameImageId
        )
        if byKey[key] == nil { order.append(key) }
        byKey[key] = override
    }
    return order.compactMap { byKey[$0] }
}

/// Agreement on (key, prompt) only — `updatedAt` is excluded so an autosave
/// can never loop on its own timestamps.
func promptOverridesAgree(
    _ lhs: [ShotSegmentPromptOverride],
    _ rhs: [ShotSegmentPromptOverride]
) -> Bool {
    let normalize: ([ShotSegmentPromptOverride]) -> Set<String> = { overrides in
        Set(overrides.map {
            "\(shotPlacementSegmentKey(startEntryId: $0.placementStartEntryId, endEntryId: $0.placementEndEntryId, legacyStartId: $0.startFrameImageId, legacyEndId: $0.endFrameImageId))|\($0.prompt.trimmed)"
        })
    }
    return normalize(lhs) == normalize(rhs)
}

/// A future-render recipe exception keyed by the same stable frame pair as a
/// prompt override. The concrete stack raw value preserves an executable
/// model+duration pairing and decodes tolerantly when newer recipes appear.
struct ShotSegmentRenderOverride: Codable, Hashable, Sendable {
    var startFrameImageId: String = ""
    var endFrameImageId: String = ""
    var placementStartEntryId: String = ""
    var placementEndEntryId: String = ""
    var stack: String = ""
    var updatedAt: String = ""

    private enum CodingKeys: String, CodingKey {
        case startFrameImageId, endFrameImageId
        case placementStartEntryId, placementEndEntryId
        case stack, updatedAt
    }

    init(
        startFrameImageId: String = "",
        endFrameImageId: String = "",
        placementStartEntryId: String = "",
        placementEndEntryId: String = "",
        stack: String = "",
        updatedAt: String = ""
    ) {
        self.startFrameImageId = startFrameImageId
        self.endFrameImageId = endFrameImageId
        self.placementStartEntryId = placementStartEntryId
        self.placementEndEntryId = placementEndEntryId
        self.stack = stack
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startFrameImageId = try container.decodeIfPresent(String.self, forKey: .startFrameImageId) ?? ""
        endFrameImageId = try container.decodeIfPresent(String.self, forKey: .endFrameImageId) ?? ""
        placementStartEntryId = try container.decodeIfPresent(String.self, forKey: .placementStartEntryId) ?? ""
        placementEndEntryId = try container.decodeIfPresent(String.self, forKey: .placementEndEntryId) ?? ""
        stack = try container.decodeIfPresent(String.self, forKey: .stack) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    func normalized() -> ShotSegmentRenderOverride {
        var value = self
        value.startFrameImageId = value.startFrameImageId.trimmed
        value.endFrameImageId = value.endFrameImageId.trimmed
        value.placementStartEntryId = value.placementStartEntryId.trimmed
        value.placementEndEntryId = value.placementEndEntryId.trimmed
        value.stack = value.stack.trimmed
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

/// Per-SEGMENT source-audio intent — "segment 2's generated audio is
/// unpleasant, silence it" — keyed by the same durable placement identity as
/// the prompt and render overrides above.
///
/// Deliberately NOT a `ShotAudioRegion`. Three reasons, each load-bearing:
///
/// - It is INTENT, not PLACEMENT: no path, no in-point, no length, no output
///   time. Source audio IS the picture, so its geometry is re-derived from the
///   live assembly on every read and a razor, skip, reverse, or re-render can
///   never leave it describing seconds that moved.
/// - A region would trip the precedence law (`ShotAudioComposition.applyMix`):
///   any region at all suppresses the four singleton overlay branches, so a
///   two-click mute on a legacy cut would have to force an irreversible
///   whole-shot regionization first.
/// - Unlike `ShotSegmentCutRange`, it does NOT pin `clipPath`. A razor is
///   about the TAKE — new pixels mean new timings, so cuts shed on re-render —
///   while a mute is about the SEGMENT, and surviving the re-render is the
///   locked requirement. Do not "fix" this to match the razor.
struct ShotSourceSegmentAudio: Codable, Hashable, Sendable {
    var startFrameImageId: String = ""
    var endFrameImageId: String = ""
    var placementStartEntryId: String = ""
    var placementEndEntryId: String = ""
    var gain: Double = 1
    var isMuted: Bool = false
    var updatedAt: String = ""

    var segmentKey: String {
        shotPlacementSegmentKey(
            startEntryId: placementStartEntryId,
            endEntryId: placementEndEntryId,
            legacyStartId: startFrameImageId,
            legacyEndId: endFrameImageId
        )
    }

    /// A row that says nothing is not state — `normalized()` drops it.
    var isNoOp: Bool { !isMuted && gain >= 1 }

    private enum CodingKeys: String, CodingKey {
        case startFrameImageId, endFrameImageId
        case placementStartEntryId, placementEndEntryId
        case gain, isMuted, updatedAt
    }

    init(
        startFrameImageId: String = "",
        endFrameImageId: String = "",
        placementStartEntryId: String = "",
        placementEndEntryId: String = "",
        gain: Double = 1,
        isMuted: Bool = false,
        updatedAt: String = ""
    ) {
        self.startFrameImageId = startFrameImageId
        self.endFrameImageId = endFrameImageId
        self.placementStartEntryId = placementStartEntryId
        self.placementEndEntryId = placementEndEntryId
        self.gain = gain
        self.isMuted = isMuted
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startFrameImageId = try container.decodeIfPresent(String.self, forKey: .startFrameImageId) ?? ""
        endFrameImageId = try container.decodeIfPresent(String.self, forKey: .endFrameImageId) ?? ""
        placementStartEntryId = try container.decodeIfPresent(String.self, forKey: .placementStartEntryId) ?? ""
        placementEndEntryId = try container.decodeIfPresent(String.self, forKey: .placementEndEntryId) ?? ""
        gain = try container.decodeIfPresent(Double.self, forKey: .gain) ?? 1
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    func normalized() -> ShotSourceSegmentAudio {
        var value = self
        value.startFrameImageId = value.startFrameImageId.trimmed
        value.endFrameImageId = value.endFrameImageId.trimmed
        value.placementStartEntryId = value.placementStartEntryId.trimmed
        value.placementEndEntryId = value.placementEndEntryId.trimmed
        value.gain = min(max(value.gain.isFinite ? value.gain : 1, 0), 1)
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

/// Both halves of a detach in one value, so ⌘Z reverses them together: a
/// detach writes a Clip-lane region AND mutes the segment at source in one
/// transaction, and undoing only one half would leave the audio either doubled
/// or gone.
struct ShotSourceDetachSnapshot {
    var sourceSegmentAudio: [ShotSourceSegmentAudio]
    var audioRegions: [ShotAudioRegion]
}

/// THE PICTURE SNAPSHOT LAW's captured state: whole picture undo for the cut
/// layer. One snapshot covers every picture op — seam style writes
/// `entries.leadTransition` AND `sourceBoundaries`; skip writes
/// `entries.isSkipped`; razor restore and join repair ripple `audioMix`
/// placements AND `audioRegions`; clip-range trim writes entry clip fields
/// AND sheds razors. Per-op minimal snapshots would need four bespoke types
/// and four restore primitives for zero operator benefit.
struct ShotPictureStateSnapshot: Hashable {
    var entries: [ShotFrameEntry]
    var sourceBoundaries: [ShotSourceBoundary]
    var cutList: ShotCutList
    var audioMix: ShotAudioMix
    var audioRegions: [ShotAudioRegion]
    /// The arrangement layer rides the same snapshot: paste, loop, rate,
    /// per-copy mute, and delete all undo through the one picture law.
    var pictureInsertions: [ShotPictureInsertion] = []
}

/// Before AND after travel together (the `ShotAudioStateEdit` shape) because
/// the player modal holds closures rather than the engine, so the post-edit
/// state must ride the return value; equality of the halves is the engine's
/// no-op detector (a caller-visible change can normalize/prune to nothing).
struct ShotPictureStateEdit: Hashable {
    var before: ShotPictureStateSnapshot
    var after: ShotPictureStateSnapshot
}

/// The result of the Clip Inspector's idempotent prepare gesture. The
/// placement key focuses the exact render-plan row; `pictureEdit` is nil when
/// the already-valid extension was merely reopened for review.
struct ShotExtensionPreparation {
    var shotId: String
    var sourceEntryId: String
    var extensionEntryId: String
    var segmentPlacementKey: String
    var pictureEdit: ShotPictureStateEdit?
    var reusedExisting: Bool
}

/// One landed punch-in excursion placement: the generating child image, the
/// two minted cut placements, and the one-transaction picture edit the caller
/// registers as a single Undo (which removes the two entries only — the child
/// render keeps running and lands on the lens board regardless).
struct ShotPunchInPlacement {
    var childImageId: String
    var childEntryId: String
    var returnEntryId: String
    var edit: ShotPictureStateEdit
}

/// Same predicate as `pruningSegmentRenderOverrides`, minus the stack-validity
/// clause and plus the no-op drop: intent equal to the default is not
/// customization, it is absence.
func pruningSourceSegmentAudio(
    _ rows: [ShotSourceSegmentAudio],
    entries: [ShotFrameEntry]
) -> [ShotSourceSegmentAudio] {
    let presentEntryIds = Set(entries.map(\.entryId))
    var presentIds = Set(entries.map(\.frameImageId))
    presentIds.remove("")
    for entry in entries where entry.isClip {
        let ids = shotFootageBoundaryFrameIds(
            mediaId: entry.clipMediaId,
            startSeconds: entry.clipStartSeconds,
            endSeconds: entry.clipEndSeconds
        )
        presentIds.insert(ids.start)
        presentIds.insert(ids.end)
    }
    var seenKeys = Set<String>()
    var kept: [ShotSourceSegmentAudio] = []
    for rawRow in rows.reversed() {
        let row = rawRow.normalized()
        let key = row.segmentKey
        guard !seenKeys.contains(key), !row.isNoOp else { continue }
        let startOK: Bool
        let endOK: Bool
        if !row.placementStartEntryId.isEmpty || !row.placementEndEntryId.isEmpty {
            startOK = row.placementStartEntryId.isEmpty
                || presentEntryIds.contains(row.placementStartEntryId)
            endOK = row.placementEndEntryId.isEmpty
                || presentEntryIds.contains(row.placementEndEntryId)
        } else {
            // Same key law as the overrides: empty start = lead-in (needs its
            // anchor), empty end = open-ended (needs its start), never both.
            startOK = row.startFrameImageId.isEmpty
                ? !row.endFrameImageId.isEmpty
                : presentIds.contains(row.startFrameImageId)
            endOK = row.endFrameImageId.isEmpty
                ? !row.startFrameImageId.isEmpty
                : presentIds.contains(row.endFrameImageId)
        }
        guard startOK, endOK else { continue }
        seenKeys.insert(key)
        kept.append(row)
    }
    return kept.reversed()
}

func pruningSegmentRenderOverrides(
    _ overrides: [ShotSegmentRenderOverride],
    entries: [ShotFrameEntry]
) -> [ShotSegmentRenderOverride] {
    let presentEntryIds = Set(entries.map(\.entryId))
    var presentIds = Set(entries.map(\.frameImageId))
    // "" is clip/extension entries' frameImageId, never a present frame.
    presentIds.remove("")
    for entry in entries where entry.isClip {
        let ids = shotFootageBoundaryFrameIds(
            mediaId: entry.clipMediaId,
            startSeconds: entry.clipStartSeconds,
            endSeconds: entry.clipEndSeconds
        )
        presentIds.insert(ids.start)
        presentIds.insert(ids.end)
    }
    var seenKeys = Set<String>()
    var kept: [ShotSegmentRenderOverride] = []
    for rawOverride in overrides.reversed() {
        let override = rawOverride.normalized()
        let key = shotPlacementSegmentKey(
            startEntryId: override.placementStartEntryId,
            endEntryId: override.placementEndEntryId,
            legacyStartId: override.startFrameImageId,
            legacyEndId: override.endFrameImageId
        )
        if !override.placementStartEntryId.isEmpty || !override.placementEndEntryId.isEmpty {
            let startOK = override.placementStartEntryId.isEmpty
                || presentEntryIds.contains(override.placementStartEntryId)
            let endOK = override.placementEndEntryId.isEmpty
                || presentEntryIds.contains(override.placementEndEntryId)
            guard !seenKeys.contains(key),
                  ShotRenderStack(rawValue: override.stack) != nil,
                  startOK, endOK else {
                continue
            }
            seenKeys.insert(key)
            kept.append(override)
            continue
        }
        // Same key law as prompt overrides: empty start = lead-in (needs its
        // anchor), empty end = open-ended (needs its start), never both.
        let startOK = override.startFrameImageId.isEmpty
            ? !override.endFrameImageId.isEmpty
            : presentIds.contains(override.startFrameImageId)
        let endOK = override.endFrameImageId.isEmpty
            ? !override.startFrameImageId.isEmpty
            : presentIds.contains(override.endFrameImageId)
        guard !seenKeys.contains(key),
              ShotRenderStack(rawValue: override.stack) != nil,
              startOK, endOK else {
            continue
        }
        seenKeys.insert(key)
        kept.append(override)
    }
    return kept.reversed()
}

// MARK: - Cut layer (deterministic view state over rendered clips)

/// THE ARTIFACT BAND KEY: when the live plan resolves no playable clips but a
/// render version's full video exists, the assembly emits one synthetic band
/// over that mp4 so razor/trim/seek/export operate on what actually plays.
/// Its cuts key on "artifact:<versionId>" and pin `clipPath` to the video —
/// they live exactly as long as their version does (the take-pin doctrine).
/// Collision-safe against every plan key form ("entry:a>b", "imgA>imgB",
/// "footageKey>"): none begins with this prefix.
let shotArtifactSegmentKeyPrefix = "artifact:"

func shotArtifactSegmentKey(versionId: String) -> String {
    shotArtifactSegmentKeyPrefix + versionId
}

/// The version a key names, or nil when it is not an artifact key (a bare
/// prefix is not a key — an empty version can never be produced).
func shotArtifactSegmentKeyVersionId(_ segmentKey: String) -> String? {
    guard segmentKey.hasPrefix(shotArtifactSegmentKeyPrefix) else { return nil }
    let versionId = String(segmentKey.dropFirst(shotArtifactSegmentKeyPrefix.count))
    return versionId.isEmpty ? nil : versionId
}

/// One razor range inside a segment, keyed by the segment's durable key
/// ("start>end" pair key; footage uses "footageKey>"). `startSeconds` /
/// `endSeconds` are clip-local seconds within the segment's saved clip file.
/// `clipPath` pins generated-segment cuts to the exact rendered take (new
/// pixels ≠ old timings, so a re-rendered segment sheds its internal cuts);
/// footage cuts carry "" and persist across renders.
struct ShotSegmentCutRange: Codable, Hashable, Sendable, Identifiable {
    var cutId: String = ""
    var segmentKey: String = ""
    var clipPath: String = ""
    var startSeconds: Double = 0
    var endSeconds: Double = 0
    var joinRepair: ShotRazorJoinRepair = ShotRazorJoinRepair()
    var updatedAt: String = ""

    var id: String {
        cutId.trimmed.nilIfEmpty
            ?? "cut_\(shortHash("\(segmentKey):\(clipPath):\(String(format: "%.3f", startSeconds)): \(String(format: "%.3f", endSeconds))", length: 16))"
    }

    var seconds: Double { max(endSeconds - startSeconds, 0) }

    func applies(toSegmentKey key: String, clipPath path: String) -> Bool {
        segmentKey == key && (clipPath.isEmpty || clipPath == path)
    }

    private enum CodingKeys: String, CodingKey {
        case cutId, segmentKey, clipPath, startSeconds, endSeconds, joinRepair, updatedAt
    }

    init(
        cutId: String = "",
        segmentKey: String = "",
        clipPath: String = "",
        startSeconds: Double = 0,
        endSeconds: Double = 0,
        joinRepair: ShotRazorJoinRepair = ShotRazorJoinRepair(),
        updatedAt: String = ""
    ) {
        self.cutId = cutId.trimmed.nilIfEmpty ?? "cut_\(UUID().uuidString.lowercased())"
        self.segmentKey = segmentKey
        self.clipPath = clipPath
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.joinRepair = joinRepair
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cutId = try container.decodeIfPresent(String.self, forKey: .cutId) ?? ""
        segmentKey = try container.decodeIfPresent(String.self, forKey: .segmentKey) ?? ""
        clipPath = try container.decodeIfPresent(String.self, forKey: .clipPath) ?? ""
        startSeconds = try container.decodeIfPresent(Double.self, forKey: .startSeconds) ?? 0
        endSeconds = try container.decodeIfPresent(Double.self, forKey: .endSeconds) ?? 0
        joinRepair = ((try? container.decodeIfPresent(ShotRazorJoinRepair.self, forKey: .joinRepair)) ?? nil) ?? ShotRazorJoinRepair()
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

/// A reference marker on the MATERIAL timeline — a brass pin the operator
/// drops for their own orientation. Markers are INERT by law: nothing in
/// assembly, playback, export, or rendering ever reads them, and they are
/// deliberately not snap magnets. They ride `ShotCutList` only for the
/// persistence and whole-picture-undo machinery it already has.
struct ShotStripMarker: Codable, Hashable, Sendable, Identifiable {
    var markerId: String = ""
    /// MATERIAL seconds, like the shot in/out pair: glued to the picture
    /// content, so razors and skips never slide a marker off what it marks.
    var materialSeconds: Double = 0
    var updatedAt: String = ""

    var id: String {
        markerId.trimmed.nilIfEmpty
            ?? "marker_\(shortHash(String(format: "%.3f", materialSeconds), length: 12))"
    }

    private enum CodingKeys: String, CodingKey {
        case markerId, materialSeconds, updatedAt
    }

    init(markerId: String = "", materialSeconds: Double = 0, updatedAt: String = "") {
        self.markerId = markerId.trimmed.nilIfEmpty ?? "marker_\(UUID().uuidString.lowercased())"
        self.materialSeconds = materialSeconds
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        markerId = try container.decodeIfPresent(String.self, forKey: .markerId) ?? ""
        materialSeconds = try container.decodeIfPresent(Double.self, forKey: .materialSeconds) ?? 0
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }
}

/// The shot's whole cut layer: an optional in/out trim on the material
/// timeline plus razor ranges inside segments. Never baked into rendered
/// files — playback and export apply it as a composition.
struct ShotCutList: Codable, Hashable, Sendable {
    /// Positions on the MATERIAL timeline: skipped segments collapsed,
    /// razor ranges still counted (so dragging a razor never shifts the
    /// handles). Seconds.
    var shotInSeconds: Double? = nil
    var shotOutSeconds: Double? = nil
    var segmentCuts: [ShotSegmentCutRange] = []
    /// Play the whole CUT backwards. Deterministic view state exactly like the
    /// in/out pair — applying it never touches a saved clip. Picture and its
    /// own SOURCE audio mirror together (playback resolves baked reversed
    /// proxies); narration, microphone, ambient, and clip lanes stay FORWARD at
    /// the output seconds the operator placed them at.
    var isReversed: Bool = false
    /// Play the whole CUT's output N times end to end. OUTPUT-space,
    /// deliberately not material: it multiplies whatever the final assembly
    /// is, so it survives re-renders, razors, reverse, and Look swaps.
    /// Applying it never touches a saved clip — the repeat is assembled at
    /// play time (preview == export) and undone by setting it back to 1.
    var outputLoopCount: Int = 1
    /// Reference markers, material seconds. Deliberately EXCLUDED from
    /// `isEmpty`: markers are not cut edits — a marker-only list must keep
    /// reading as "no edits" so export naming and every has-edits check
    /// stay honest about what actually plays.
    var markers: [ShotStripMarker] = []

    static let minimumRangeSeconds: Double = 0.05
    /// Hard ceiling on the output repeat. Together with the popover's
    /// total-runtime clamp (≤ 600s) this keeps every looped export inside
    /// MediaExportGuard's deadline envelope.
    static let maximumOutputLoopCount: Int = 20

    var isEmpty: Bool {
        shotInSeconds == nil && shotOutSeconds == nil && segmentCuts.isEmpty && !isReversed
            && outputLoopCount <= 1
    }

    var razorSecondsTotal: Double { segmentCuts.reduce(0) { $0 + $1.seconds } }

    private enum CodingKeys: String, CodingKey {
        case shotInSeconds, shotOutSeconds, segmentCuts, isReversed, outputLoopCount, markers
    }

    // `isReversed`, `outputLoopCount`, and `markers` are deliberately LAST so
    // existing positional calls such as `ShotCutList(segmentCuts:)` keep
    // compiling.
    init(
        shotInSeconds: Double? = nil,
        shotOutSeconds: Double? = nil,
        segmentCuts: [ShotSegmentCutRange] = [],
        isReversed: Bool = false,
        outputLoopCount: Int = 1,
        markers: [ShotStripMarker] = []
    ) {
        self.shotInSeconds = shotInSeconds
        self.shotOutSeconds = shotOutSeconds
        self.segmentCuts = segmentCuts
        self.isReversed = isReversed
        self.outputLoopCount = outputLoopCount
        self.markers = markers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shotInSeconds = try container.decodeIfPresent(Double.self, forKey: .shotInSeconds)
        shotOutSeconds = try container.decodeIfPresent(Double.self, forKey: .shotOutSeconds)
        segmentCuts = ((try? container.decodeIfPresent([ShotSegmentCutRange].self, forKey: .segmentCuts)) ?? nil) ?? []
        isReversed = ((try? container.decodeIfPresent(Bool.self, forKey: .isReversed)) ?? nil) ?? false
        outputLoopCount = ((try? container.decodeIfPresent(Int.self, forKey: .outputLoopCount)) ?? nil) ?? 1
        markers = ((try? container.decodeIfPresent([ShotStripMarker].self, forKey: .markers)) ?? nil) ?? []
    }

    /// Clamps and orders everything: negative bounds drop, an inverted in/out
    /// pair drops, near-zero razor ranges drop, ranges sort by key + start.
    func normalized() -> ShotCutList {
        var value = self
        value.outputLoopCount = min(max(value.outputLoopCount, 1), Self.maximumOutputLoopCount)
        if let inSeconds = value.shotInSeconds, inSeconds <= Self.minimumRangeSeconds {
            value.shotInSeconds = nil
        }
        if let outSeconds = value.shotOutSeconds, outSeconds <= 0 {
            value.shotOutSeconds = nil
        }
        if let inSeconds = value.shotInSeconds, let outSeconds = value.shotOutSeconds,
           outSeconds - inSeconds < Self.minimumRangeSeconds {
            value.shotInSeconds = nil
            value.shotOutSeconds = nil
        }
        value.segmentCuts = value.segmentCuts
            .map { cut in
                var range = cut
                range.cutId = range.id
                range.segmentKey = range.segmentKey.trimmed
                range.clipPath = range.clipPath.trimmed
                range.startSeconds = max(range.startSeconds, 0)
                range.endSeconds = max(range.endSeconds, 0)
                if range.endSeconds < range.startSeconds {
                    swap(&range.startSeconds, &range.endSeconds)
                }
                range.joinRepair = range.joinRepair.normalized()
                return range
            }
            .filter { !$0.segmentKey.isEmpty && $0.seconds >= Self.minimumRangeSeconds }
            .sorted { lhs, rhs in
                lhs.segmentKey == rhs.segmentKey
                    ? lhs.startSeconds < rhs.startSeconds
                    : lhs.segmentKey < rhs.segmentKey
            }
        var seenMarkerIds = Set<String>()
        value.markers = value.markers
            .map { marker in
                var pin = marker
                pin.markerId = pin.id
                pin.materialSeconds = max(pin.materialSeconds, 0)
                return pin
            }
            .filter { seenMarkerIds.insert($0.markerId).inserted }
            .sorted { $0.materialSeconds < $1.materialSeconds }
        return value
    }

    /// Drops razor ranges whose segment can no longer exist in this strip —
    /// the same tolerance as prompt-override pruning (still-present but
    /// non-adjacent pairs survive; the user may reorder them back together).
    func pruned(entries: [ShotFrameEntry]) -> ShotCutList {
        // THE PRODUCIBILITY LAW lives in ShotSegmentKeyIdentity, shared with
        // picture-insertion anchor pruning so both layers age identically.
        let identity = ShotSegmentKeyIdentity(entries: entries)
        var value = self
        value.segmentCuts = value.segmentCuts.filter { identity.canProduce($0.segmentKey) }
        return value
    }
}

/// A kept span of one clip, clip-local seconds.
struct ShotKeepRange: Hashable {
    var start: Double
    var end: Double

    var seconds: Double { max(end - start, 0) }
}

/// One clip of the assembled cut plan: which spans of its file play, where
/// its material starts on the strip timeline, and where its first kept
/// second lands on the output timeline. Clips without a rendered file take
/// part in the material timeline but play nothing (`keepRanges` empty).
struct ShotCutPlanClip: Hashable {
    var segmentKey: String
    var clipPath: String
    var keepRanges: [ShotKeepRange]
    /// Where this clip's material begins on the strip (material) timeline.
    var materialStartSeconds: Double
    /// This clip's playable material length (duration − handoff shave).
    var materialSeconds: Double
    /// Where this clip's first kept second lands in the playable output.
    var outputStartSeconds: Double
    /// The handoff shave — the clip's material starts at this local second.
    var headSeconds: Double

    var isPlayable: Bool { !keepRanges.isEmpty }
    var keptSeconds: Double { keepRanges.reduce(0) { $0 + $1.seconds } }
}

struct ShotCutPlanClipInput {
    var segmentKey: String
    /// "" ⇒ not rendered yet: occupies material time, plays nothing.
    var clipPath: String
    var durationSeconds: Double
    /// Duplicate-handoff shave at the clip head (bridged seams), seconds.
    var leadingTrimSeconds: Double = 0
}

/// The single deterministic law turning ordered clips + the cut layer into
/// playable spans: per clip, start after the handoff shave, subtract razor
/// ranges, then clamp against the shot-level in/out measured on the material
/// timeline. Pure — playback, export, and the strip all read the same result.
func shotCutPlan(
    clips: [ShotCutPlanClipInput],
    cutList: ShotCutList,
    minimumKeepSeconds: Double = ShotCutList.minimumRangeSeconds
) -> (clips: [ShotCutPlanClip], outputSeconds: Double, materialSeconds: Double) {
    let shotIn = cutList.shotInSeconds ?? 0
    let shotOut = cutList.shotOutSeconds ?? .infinity

    var materialCursor = 0.0
    var outputCursor = 0.0
    var planClips: [ShotCutPlanClip] = []

    for clip in clips {
        let duration = max(clip.durationSeconds, 0)
        let head = min(max(clip.leadingTrimSeconds, 0), duration)
        let materialSeconds = max(duration - head, 0)
        let materialStart = materialCursor
        defer { materialCursor = materialStart + materialSeconds }

        guard !clip.clipPath.isEmpty, materialSeconds >= minimumKeepSeconds else {
            planClips.append(ShotCutPlanClip(
                segmentKey: clip.segmentKey,
                clipPath: clip.clipPath,
                keepRanges: [],
                materialStartSeconds: materialStart,
                materialSeconds: materialSeconds,
                outputStartSeconds: outputCursor,
                headSeconds: head
            ))
            continue
        }

        var keeps: [ShotKeepRange] = [ShotKeepRange(start: head, end: duration)]
        let cuts = cutList.segmentCuts
            .filter { $0.applies(toSegmentKey: clip.segmentKey, clipPath: clip.clipPath) }
            .sorted { $0.startSeconds < $1.startSeconds }
        for cut in cuts {
            var next: [ShotKeepRange] = []
            for keep in keeps {
                let cutStart = max(cut.startSeconds, keep.start)
                let cutEnd = min(cut.endSeconds, keep.end)
                guard cutEnd - cutStart >= minimumKeepSeconds else {
                    next.append(keep)
                    continue
                }
                if cutStart - keep.start >= minimumKeepSeconds {
                    next.append(ShotKeepRange(start: keep.start, end: cutStart))
                }
                if keep.end - cutEnd >= minimumKeepSeconds {
                    next.append(ShotKeepRange(start: cutEnd, end: keep.end))
                }
            }
            keeps = next
        }

        // Material position of a clip-local second: the handoff shave is the
        // material origin, razor ranges still count (they're visible).
        func materialPosition(ofLocal local: Double) -> Double {
            materialStart + (local - head)
        }

        var visible: [ShotKeepRange] = []
        var clipOutputStart: Double?
        for keep in keeps {
            let visibleStart = max(materialPosition(ofLocal: keep.start), shotIn)
            let visibleEnd = min(materialPosition(ofLocal: keep.end), shotOut)
            guard visibleEnd - visibleStart >= minimumKeepSeconds else { continue }
            let local = ShotKeepRange(
                start: keep.start + (visibleStart - materialPosition(ofLocal: keep.start)),
                end: keep.end - (materialPosition(ofLocal: keep.end) - visibleEnd)
            )
            if clipOutputStart == nil {
                clipOutputStart = outputCursor
            }
            visible.append(local)
            outputCursor += local.seconds
        }
        planClips.append(ShotCutPlanClip(
            segmentKey: clip.segmentKey,
            clipPath: clip.clipPath,
            keepRanges: visible,
            materialStartSeconds: materialStart,
            materialSeconds: materialSeconds,
            outputStartSeconds: clipOutputStart ?? outputCursor,
            headSeconds: head
        ))
    }
    return (planClips, outputCursor, materialCursor)
}

/// One row of the Re-render prompt sheet: the segment's keyframe pair, the
/// freshly generated prompt, and any persisted override. `generatedPrompt` is
/// exactly what `renderShot` would send absent an override, so the sheet's
/// preview and the render agree by construction.
struct ShotSegmentPromptPlanItem: Identifiable {
    var index: Int
    var pair: ShotRenderPair
    var generatedPrompt: String
    var overridePrompt: String?
    var renderStack: ShotRenderStack = .fallback
    var hasRenderOverride: Bool = false
    /// Position among ALL of the shot's segments (generated AND footage) —
    /// `index` stays the generated-only ordinal that render decisions use.
    var displayIndex: Int = 0
    /// How to skip this segment: cut its seam (frame–frame pairs), or skip
    /// its entry (AI extensions). nil = not skippable (the lone-frame shot).
    var skipTarget: ShotSkippedSegmentPlaceholder.RestoreAction? = nil
    /// The compiled temporal direction, non-nil ONLY when the segment's plan
    /// record exists in beats mode with content — in which case
    /// `generatedPrompt` is its canonical text and the mode-flag law says the
    /// flat override is ignored. nil = the classic raw path.
    var compiledDirection: ShotCompiledSegmentDirection? = nil
    /// The persisted plan record for this pair, whatever its mode.
    var directionPlan: ShotSegmentDirectionPlanRecord? = nil
    /// True when the record's LLM draft was built from inputs (frames,
    /// lineage, narration, duration) that have since changed. Stale stays
    /// usable — the badge invites a one-click re-draft, never blocks.
    var directionPlanIsStale: Bool = false
    /// True only for the authored AI-extension card. Ordinary open-ended
    /// frame segments have the same pair shape but are not video extensions.
    var isAIExtension: Bool = false
    /// Native Extend is executable only when the extension directly follows
    /// this placed footage clip. The exact range travels with the plan item.
    var nativeExtendSourceClip: ShotFootageClip? = nil

    var nativeExtendContextSeconds: Double? {
        guard let source = nativeExtendSourceClip else { return nil }
        return ltxShotExtendContextSeconds(
            sourceDurationSeconds: source.resolvedDurationSeconds,
            extensionDurationSeconds: renderStack.segmentSeconds
        )
    }

    var canUseNativeFootageExtend: Bool {
        isAIExtension && nativeExtendSourceClip != nil && nativeExtendContextSeconds != nil
    }

    /// Which editing surface owns this segment's prompt.
    var promptMode: ShotSegmentPromptMode { directionPlan?.mode ?? .raw }

    /// The mode-flag law in one place: beats renders its compiled canonical
    /// text (override ignored); raw renders override ?? generated, exactly
    /// as before plans existed.
    var effectivePrompt: String {
        compiledDirection != nil ? generatedPrompt : (overridePrompt ?? generatedPrompt)
    }

    /// Stable identity of the keyframe pair — the key drafts and persisted
    /// overrides share. The positional `id` exists only for row identity in
    /// lists; a draft keyed by it would orphan on any insert or reorder.
    var pairKey: String { pair.placementKey }

    var id: String { "\(pairKey)#\(index)" }

    /// True when either endpoint is a footage boundary still — this segment
    /// IS a bridge into/out of real footage.
    var touchesFootage: Bool {
        pair.start?.provider == "footage" || pair.end?.provider == "footage"
    }
}

/// The ONE plan-item constructor. Both `shotSegmentPromptPlan` and
/// `shotRenderSegmentPlan` build their items here so the editor preview and
/// the render cannot drift — the exact bug the `generatedPrompt` contract
/// exists to prevent. A beats-mode plan record with content compiles into
/// the segment's effective model dialect and becomes the generated prompt;
/// anything else is byte-identical to the classic one-sentence path.
func makeShotSegmentPromptPlanItem(
    shot: ProjectShot,
    pair: ShotRenderPair,
    index: Int,
    displayIndex: Int = 0,
    skipTarget: ShotSkippedSegmentPlaceholder.RestoreAction? = nil,
    isAIExtension: Bool = false,
    nativeExtendSourceClip: ShotFootageClip? = nil
) -> ShotSegmentPromptPlanItem {
    let renderStack = shot.segmentRenderStack(for: pair)
    let record = shot.segmentDirectionPlan(for: pair)
    var compiled: ShotCompiledSegmentDirection?
    if let record, record.mode == .beats, !record.plan.isEmpty,
       let selection = renderStack.modelSelection(for: pair) {
        compiled = compileTemporalDirection(
            plan: record.plan,
            modelSelection: selection,
            durationSeconds: renderStack.segmentSeconds
        )
    }
    let isStale = record.map { candidate in
        candidate.source == "llm"
            && !candidate.inputsFingerprint.isEmpty
            && candidate.inputsFingerprint != shotDirectionPlanInputsFingerprint(
                context: shotDirectionPlanDraftContext(
                    shot: shot,
                    pair: pair,
                    segmentSeconds: renderStack.segmentSeconds
                )
            )
    } ?? false
    return ShotSegmentPromptPlanItem(
        index: index,
        pair: pair,
        generatedPrompt: compiled?.canonicalText ?? shotSegmentPrompt(pair: pair),
        overridePrompt: shot.segmentPromptOverride(for: pair),
        renderStack: renderStack,
        hasRenderOverride: shot.hasSegmentRenderOverride(for: pair),
        displayIndex: displayIndex,
        skipTarget: skipTarget,
        compiledDirection: compiled,
        directionPlan: record,
        directionPlanIsStale: isStale,
        isAIExtension: isAIExtension,
        nativeExtendSourceClip: nativeExtendSourceClip
    )
}

/// LTX 2.3 Extend accepts 1–20 seconds of context and limits context plus
/// generated duration to 505 frames. Shot inputs are normalized to 24 fps;
/// prefer two seconds without ever violating the provider's frame budget.
func ltxShotExtendContextSeconds(
    sourceDurationSeconds: Double,
    extensionDurationSeconds: Int,
    fps: Double = 24
) -> Double? {
    guard sourceDurationSeconds.isFinite,
          sourceDurationSeconds * fps >= 73,
          extensionDurationSeconds >= 2,
          extensionDurationSeconds <= 20,
          fps > 0 else {
        return nil
    }
    let frameBudgetSeconds = 505 / fps - Double(extensionDurationSeconds)
    let context = min(sourceDurationSeconds, 2, frameBudgetSeconds)
    return context >= 1 ? context : nil
}

/// The per-segment prompt plan for a shot — the single derivation both the
/// Re-render sheet and `renderShot` read (same pairs, same strands, same
/// generated prompts).
func shotSegmentPromptPlan(
    shot: ProjectShot,
    frameLookup: [String: ProjectLensHeroImage],
    meaningNodes: [LensContextPromptMeaningNode]
) -> (items: [ShotSegmentPromptPlanItem], skipped: [String], strands: [MeaningStrand]) {
    let plan = shotRenderPairs(shot: shot, frameLookup: frameLookup)
    let strands = deriveMeaningStrands(shots: [shot], frameLookup: frameLookup, meaningNodes: meaningNodes)
    let items = plan.pairs.enumerated().map { index, pair in
        makeShotSegmentPromptPlanItem(shot: shot, pair: pair, index: index)
    }
    return (items, plan.skipped, strands)
}

/// What a render does per segment: reuse a durable clip from the source
/// version, or generate fresh.
enum ShotSegmentRenderDecision: Equatable {
    case generate
    case reuse(ShotRenderSegmentClip)
}

/// Reuse happens only under a partial-render filter, for segments NOT in the
/// filter whose saved clip record exists AND whose file is still on disk —
/// anything else generates. A filter is a minimum-render request, never a
/// reason to fail: legacy versions without saved clips render those segments
/// too.
func shotSegmentRenderDecisions(
    items: [ShotSegmentPromptPlanItem],
    onlySegmentKeys: Set<String>?,
    reuseSource: ShotRenderArtifact?,
    fileExists: (String) -> Bool
) -> [ShotSegmentRenderDecision] {
    items.map { item in
        guard let filter = onlySegmentKeys,
              !filter.contains(item.pair.placementKey),
              !filter.contains(item.pair.segmentKey),
              let clip = reuseSource?.segmentClip(
                  placementStartEntryId: item.pair.startPlacementEntryId,
                  placementEndEntryId: item.pair.endPlacementEntryId,
                  forStart: item.pair.start?.imageId ?? "",
                  end: item.pair.end?.imageId ?? ""
              ),
              fileExists(clip.clipPath) else {
            return .generate
        }
        return .reuse(clip)
    }
}

/// The segment clip the player can preview for a pair: the ACTIVE render
/// version's saved clip, and only when its file is still on disk.
func previewableSegmentClip(
    shot: ProjectShot,
    pair: ShotRenderPair,
    fileExists: (String) -> Bool
) -> ShotRenderSegmentClip? {
    let rendered = shot.activeRenderVersion?.segmentClip(
        placementStartEntryId: pair.startPlacementEntryId,
        placementEndEntryId: pair.endPlacementEntryId,
        forStart: pair.start?.imageId ?? "",
        end: pair.end?.imageId ?? ""
    )
    let seed = shot.seedSegmentClips.first {
        if !pair.startPlacementEntryId.isEmpty || !pair.endPlacementEntryId.isEmpty {
            return $0.placementStartEntryId == pair.startPlacementEntryId
                && $0.placementEndEntryId == pair.endPlacementEntryId
        }
        return $0.placementStartEntryId.isEmpty
            && $0.placementEndEntryId.isEmpty
            && $0.startFrameImageId == pair.start?.imageId ?? ""
            && $0.endFrameImageId == pair.end?.imageId ?? ""
    }
    guard let clip = rendered ?? seed, fileExists(clip.clipPath) else {
        return nil
    }
    return clip
}

// MARK: - Suffix appends on a rendered cut (tail law + missing-keys law)

/// The suffix-editable region of a locked cut: entries after the last entry
/// the ready ACTIVE version's watermark rendered. nil = no relaxation — the
/// cut is unlocked anyway, has no ready active version, or the version
/// predates the watermark (legacy: full freeze, NEW VERSION remains the path).
/// EntryId-based on purpose: saved-clip keys repeat under duplicate frame
/// placements and would mislabel an appended duplicate as rendered.
func shotSuffixTailStartIndex(shot: ProjectShot) -> Int? {
    guard let version = shot.activeRenderVersion, version.isReady,
          !version.renderedEntryIds.isEmpty else { return nil }
    let rendered = Set(version.renderedEntryIds)
    guard let last = shot.entries.lastIndex(where: { rendered.contains($0.entryId) }) else {
        return 0
    }
    return last + 1
}

/// What a partial "render only the new material" run must generate: the live
/// plan's keys with no saved, on-disk clip on the active version. Mirrors the
/// engine's reuse predicate exactly — generated segments by `pair.segmentKey`,
/// footage by BARE `footageKey` — so `renderShot(onlySegmentKeys:)` reuses
/// everything else deterministically. Skip-created mid-plan holes count too.
struct ShotSuffixRenderPlan: Equatable {
    var missingKeys: Set<String> = []
    var missingGeneratedItems: [ShotSegmentPromptPlanItem] = []
    var reusableSegmentCount: Int = 0

    var hasNewMaterial: Bool { !missingKeys.isEmpty }

    static func == (lhs: ShotSuffixRenderPlan, rhs: ShotSuffixRenderPlan) -> Bool {
        lhs.missingKeys == rhs.missingKeys
            && lhs.reusableSegmentCount == rhs.reusableSegmentCount
            && lhs.missingGeneratedItems.map(\.id) == rhs.missingGeneratedItems.map(\.id)
    }
}

func shotSuffixRenderPlan(
    shot: ProjectShot,
    segments: [ShotRenderPlanSegment],
    generatedItems: [ShotSegmentPromptPlanItem],
    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
) -> ShotSuffixRenderPlan {
    let version = shot.activeRenderVersion
    var plan = ShotSuffixRenderPlan()
    for item in generatedItems {
        let saved = version?.segmentClip(
            placementStartEntryId: item.pair.startPlacementEntryId,
            placementEndEntryId: item.pair.endPlacementEntryId,
            forStart: item.pair.start?.imageId ?? "",
            end: item.pair.end?.imageId ?? ""
        )
        if let saved, fileExists(saved.clipPath) {
            plan.reusableSegmentCount += 1
        } else {
            plan.missingKeys.insert(item.pair.placementKey)
            plan.missingGeneratedItems.append(item)
        }
    }
    for case .footage(let footageSegment) in segments {
        let key = footageSegment.placementKey
        let saved = version?.segmentClip(
            placementStartEntryId: footageSegment.clip.entryId,
            placementEndEntryId: "",
            forStart: footageSegment.clip.footageKey,
            end: ""
        )
        if let saved, fileExists(saved.clipPath) {
            plan.reusableSegmentCount += 1
        } else {
            plan.missingKeys.insert(key)
        }
    }
    return plan
}

// MARK: - Footage segments (real clips inside a shot)

/// Durable identity for a clip entry's content: media + narrowed range.
/// Overrides and saved-clip reuse key on this exactly like frame image ids —
/// the same footage placed twice shares its keys, mirroring duplicate pairs.
func shotFootageKey(mediaId: String, startSeconds: Double?, endSeconds: Double?) -> String {
    let start = startSeconds.map { String(format: "%.3f", $0) } ?? "asset_start"
    let end = endSeconds.map { String(format: "%.3f", $0) } ?? "asset_end"
    return "footage:\(mediaId):\(start)-\(end)"
}

func shotFootageBoundaryFrameIds(
    mediaId: String,
    startSeconds: Double?,
    endSeconds: Double?
) -> (start: String, end: String) {
    let key = shotFootageKey(mediaId: mediaId, startSeconds: startSeconds, endSeconds: endSeconds)
    return ("\(key)@start", "\(key)@end")
}

/// A clip entry resolved against the media inventory: everything the plan,
/// the Re-render panel, and the render loop need to place real footage.
struct ShotFootageClip: Hashable, Identifiable {
    var entryId: String
    var mediaId: String
    var sourceId: String
    var path: String
    var filename: String
    var thumbnailPath: String
    var videoStripPath: String?
    var clipStartSeconds: Double?
    var clipEndSeconds: Double?
    var assetDurationSeconds: Double

    var id: String { entryId }

    var footageKey: String {
        shotFootageKey(mediaId: mediaId, startSeconds: clipStartSeconds, endSeconds: clipEndSeconds)
    }

    var boundaryFrameIds: (start: String, end: String) {
        shotFootageBoundaryFrameIds(
            mediaId: mediaId,
            startSeconds: clipStartSeconds,
            endSeconds: clipEndSeconds
        )
    }

    var resolvedStartSeconds: Double {
        min(max(clipStartSeconds ?? 0, 0), assetDurationSeconds)
    }

    var resolvedEndSeconds: Double {
        min(max(clipEndSeconds ?? assetDurationSeconds, resolvedStartSeconds), assetDurationSeconds)
    }

    var resolvedDurationSeconds: Double {
        max(resolvedEndSeconds - resolvedStartSeconds, 0)
    }

    /// True when the entry narrows the asset rather than playing it whole.
    var hasSubRange: Bool {
        clipStartSeconds != nil || clipEndSeconds != nil
    }
}

enum ShotFootageBoundaryEdge {
    case start
    case end
}

/// The synthetic keyframe endpoint a generated segment interpolates to/from
/// at a footage boundary. It rides the existing frame-keyed machinery: its
/// imageId is the durable boundary key (prompt overrides, saved clips, and
/// previews all match by that string). Its imagePath is only a display proxy
/// (the clip's poster thumb) — renders extract the REAL boundary still from
/// the footage itself.
func shotFootageBoundaryFrame(clip: ShotFootageClip, edge: ShotFootageBoundaryEdge) -> ProjectLensHeroImage {
    let ids = clip.boundaryFrameIds
    let gist = edge == .start
        ? "the opening frame of the placed footage clip \(clip.filename)"
        : "the final frame of the placed footage clip \(clip.filename)"
    return ProjectLensHeroImage(
        imageId: edge == .start ? ids.start : ids.end,
        label: edge == .start ? "Footage in · \(clip.filename)" : "Footage out · \(clip.filename)",
        provider: "footage",
        model: "",
        imagePath: clip.thumbnailPath,
        prompt: gist,
        sourcePrompt: gist,
        status: "ready"
    )
}

/// One footage segment of a mixed plan, with its position among ALL segments.
struct ShotFootagePlanSegment: Identifiable {
    var displayIndex: Int
    var clip: ShotFootageClip
    /// True when an arriving BRIDGE ends on this clip's first frame (the seam
    /// resolved to bridge) — the stitcher may shave the duplicate handoff
    /// frames. False after a hard cut: real frames are never eaten.
    var joinsPrevious: Bool = false

    var id: String { "\(clip.footageKey)#\(displayIndex)" }
    var placementKey: String {
        shotPlacementSegmentKey(
            startEntryId: clip.entryId,
            endEntryId: "",
            legacyStartId: clip.footageKey,
            legacyEndId: ""
        )
    }
}

/// The synthetic band's payload when the live plan resolves no playable
/// clips but a render version's full video exists — runtime-only (never
/// persisted, never emitted by the plan generator; only `shotCutAssembly`
/// constructs it), so razor/trim/seek/export operate on what actually plays.
struct ShotArtifactPlanSegment: Hashable {
    var versionId: String
    var versionNumber: Int
    var videoPath: String
    var segmentCount: Int
    var durationSeconds: Double
    /// Interior stitch-join offsets within the video (band-local seconds).
    var seamSeconds: [Double]
}

/// One ordered segment of a mixed render plan.
enum ShotRenderPlanSegment: Identifiable {
    case generated(ShotSegmentPromptPlanItem)
    case footage(ShotFootagePlanSegment)
    /// Never produced by the plan generator — the assembly's fallback band
    /// over the playable version's full video.
    case artifactFallback(ShotArtifactPlanSegment)

    var id: String {
        switch self {
        case .generated(let item): return "gen_\(item.id)"
        case .footage(let segment): return "footage_\(segment.id)"
        case .artifactFallback(let segment): return "artifact_\(segment.versionId)"
        }
    }
}

/// A deliberately skipped piece of the strip, kept visible and restorable:
/// either a skipped entry (footage, frame, or extension) or a frame–frame
/// seam whose explicit cut hides the generated pair between two stills.
/// Distinct from the not-ready `skipped` report — these are choices.
struct ShotSkippedSegmentPlaceholder: Identifiable, Hashable {
    enum RestoreAction: Hashable {
        /// Clear `isSkipped` on this entry.
        case entry(entryId: String)
        /// Re-bridge the seam riding this right entry.
        case seam(rightEntryId: String)
    }

    /// The live plan segment this placeholder sits after (-1 = before the
    /// first segment).
    var afterDisplayIndex: Int
    var label: String
    var isFootage: Bool = false
    var footageSeconds: Double = 0
    var restore: RestoreAction

    var id: String {
        switch restore {
        case .entry(let entryId): return "skip_entry_\(entryId)"
        case .seam(let rightEntryId): return "skip_seam_\(rightEntryId)"
        }
    }
}

/// The mixed derivation for shots that may hold real footage. Frame runs pair
/// exactly as `shotRenderPairs` always has (frame-only shots produce
/// byte-identical prompts and keys); a clip contributes its own footage
/// segment, its neighbors interpolate to/from synthetic boundary endpoints,
/// and adjacent clips hard-cut (no generated bridge). `generatedItems` aligns
/// 1:1 with `shotSegmentRenderDecisions` input; not-ready frames and
/// unresolvable footage are skipped and REPORTED, never faked. Deliberately
/// skipped entries contribute nothing, heal their seams to hard cuts, and
/// come back as `skippedPlaceholders` so every skip stays restorable.
func shotRenderSegmentPlan(
    shot: ProjectShot,
    frameLookup: [String: ProjectLensHeroImage],
    mediaLookup: [String: MediaItemRecord],
    meaningNodes: [LensContextPromptMeaningNode]
) -> (
    segments: [ShotRenderPlanSegment],
    generatedItems: [ShotSegmentPromptPlanItem],
    skipped: [String],
    strands: [MeaningStrand],
    skippedPlaceholders: [ShotSkippedSegmentPlaceholder]
) {
    enum StripNodeKind {
        case frame(ProjectLensHeroImage)
        case clip(ShotFootageClip)
        case aiExtension
    }
    struct StripNode {
        var kind: StripNodeKind
        var entry: ShotFrameEntry
        /// A skipped entry sat immediately before this node — its seam into
        /// the vanished neighbor heals to a hard cut, never a fresh bridge.
        var followsSkippedEntry: Bool = false
        var startsSourceSection: Bool = false

        var isClipNode: Bool {
            if case .clip = kind { return true }
            return false
        }

        var isExtensionNode: Bool {
            if case .aiExtension = kind { return true }
            return false
        }
    }
    struct SkipSeed {
        var label: String
        var isFootage: Bool
        var footageSeconds: Double
        var entryId: String
    }

    var nodes: [StripNode] = []
    let sourceBoundaryEntryIds = Set(shot.sourceBoundaries.map(\.rightEntryId))
    var skipped: [String] = []
    var pendingSkipSeeds: [SkipSeed] = []
    var pendingSourceBoundary = false
    var skipSeedsByNodeIndex: [Int: [SkipSeed]] = [:]
    for entry in shot.entries {
        if sourceBoundaryEntryIds.contains(entry.entryId) {
            pendingSourceBoundary = true
        }
        if entry.isSkipped {
            let label: String
            var isFootage = false
            var footageSeconds = 0.0
            if entry.isAIExtension {
                label = "AI extension"
            } else if entry.isClip {
                let media = mediaLookup[entry.clipMediaId]
                label = media?.filename.trimmed.nilIfEmpty ?? "footage"
                isFootage = true
                let assetDuration = max(media?.durationSeconds ?? 0, 0)
                let start = min(max(entry.clipStartSeconds ?? 0, 0), assetDuration)
                let end = min(max(entry.clipEndSeconds ?? assetDuration, start), assetDuration)
                footageSeconds = max(end - start, 0)
            } else {
                label = frameLookup[entry.frameImageId]?.label.trimmed.nilIfEmpty ?? entry.frameImageId
            }
            pendingSkipSeeds.append(SkipSeed(
                label: label,
                isFootage: isFootage,
                footageSeconds: footageSeconds,
                entryId: entry.entryId
            ))
            continue
        }
        if entry.isAIExtension {
            nodes.append(StripNode(
                kind: .aiExtension,
                entry: entry,
                followsSkippedEntry: !pendingSkipSeeds.isEmpty,
                startsSourceSection: pendingSourceBoundary
            ))
        } else if entry.isClip {
            guard let media = mediaLookup[entry.clipMediaId],
                  media.kind == .video,
                  !media.path.trimmed.isEmpty else {
                skipped.append(mediaLookup[entry.clipMediaId]?.filename ?? "missing footage")
                continue
            }
            let clip = ShotFootageClip(
                entryId: entry.entryId,
                mediaId: media.mediaId,
                sourceId: media.sourceId,
                path: media.path,
                filename: media.filename,
                thumbnailPath: media.thumbnailPath,
                videoStripPath: media.videoStripPath,
                clipStartSeconds: entry.clipStartSeconds,
                clipEndSeconds: entry.clipEndSeconds,
                assetDurationSeconds: max(media.durationSeconds ?? 0, 0)
            )
            guard clip.assetDurationSeconds <= 0 || clip.resolvedDurationSeconds > 0 else {
                skipped.append(media.filename)
                continue
            }
            nodes.append(StripNode(
                kind: .clip(clip),
                entry: entry,
                followsSkippedEntry: !pendingSkipSeeds.isEmpty,
                startsSourceSection: pendingSourceBoundary
            ))
        } else if let frame = frameLookup[entry.frameImageId],
                  frame.status == "ready",
                  !frame.imagePath.trimmed.isEmpty {
            nodes.append(StripNode(
                kind: .frame(frame),
                entry: entry,
                followsSkippedEntry: !pendingSkipSeeds.isEmpty,
                startsSourceSection: pendingSourceBoundary
            ))
        } else {
            let label = frameLookup[entry.frameImageId]?.label.trimmed.nilIfEmpty ?? entry.frameImageId
            skipped.append(label)
            continue
        }
        pendingSourceBoundary = false
        if !pendingSkipSeeds.isEmpty {
            skipSeedsByNodeIndex[nodes.count - 1] = pendingSkipSeeds
            pendingSkipSeeds = []
        }
    }
    let trailingSkipSeeds = pendingSkipSeeds

    let strands = deriveMeaningStrands(shots: [shot], frameLookup: frameLookup, meaningNodes: meaningNodes)

    func endpoint(_ node: StripNode, edge: ShotFootageBoundaryEdge) -> ProjectLensHeroImage {
        switch node.kind {
        case .frame(let frame): return frame
        case .clip(let clip): return shotFootageBoundaryFrame(clip: clip, edge: edge)
        case .aiExtension:
            // Never reached: extension nodes are excluded from every pair —
            // their final frame doesn't exist until rendered.
            return ProjectLensHeroImage(imageId: "extension_endpoint_invalid")
        }
    }

    // Seams resolve between SURVIVING nodes (skipped middles collapse
    // adjacency); a seam a skip created always heals to a hard cut, otherwise
    // the right node's preference + both kinds feed the law.
    func seamStyle(into rightIndex: Int) -> ShotSeamStyle {
        guard !nodes[rightIndex].followsSkippedEntry,
              !nodes[rightIndex].startsSourceSection else { return .cut }
        return resolvedShotSeamStyle(
            leftIsClip: nodes[rightIndex - 1].isClipNode,
            rightIsClip: nodes[rightIndex].isClipNode,
            rightPreference: nodes[rightIndex].entry.leadSeamPreference
        )
    }

    var segments: [ShotRenderPlanSegment] = []
    var generatedItems: [ShotSegmentPromptPlanItem] = []
    var bridgedNodeIndexes = Set<Int>()
    var placeholders: [ShotSkippedSegmentPlaceholder] = []

    func emitSkipSeeds(_ seeds: [SkipSeed]?) {
        for seed in seeds ?? [] {
            placeholders.append(ShotSkippedSegmentPlaceholder(
                afterDisplayIndex: segments.count - 1,
                label: seed.label,
                isFootage: seed.isFootage,
                footageSeconds: seed.footageSeconds,
                restore: .entry(entryId: seed.entryId)
            ))
        }
    }

    func appendGenerated(
        pair: ShotRenderPair,
        skipTarget: ShotSkippedSegmentPlaceholder.RestoreAction? = nil,
        isAIExtension: Bool = false,
        nativeExtendSourceClip: ShotFootageClip? = nil
    ) {
        let item = makeShotSegmentPromptPlanItem(
            shot: shot,
            pair: pair,
            index: generatedItems.count,
            displayIndex: segments.count,
            skipTarget: skipTarget,
            isAIExtension: isAIExtension,
            nativeExtendSourceClip: nativeExtendSourceClip
        )
        segments.append(.generated(item))
        generatedItems.append(item)
    }

    if nodes.count == 1, case .frame(let only) = nodes[0].kind {
        emitSkipSeeds(skipSeedsByNodeIndex[0])
        appendGenerated(pair: ShotRenderPair(
            start: only,
            end: nil,
            startPlacementEntryId: nodes[0].entry.entryId
        ))
    } else {
        for (index, node) in nodes.enumerated() {
            emitSkipSeeds(skipSeedsByNodeIndex[index])
            let startsSection = index == 0 || node.startsSourceSection
            let endsSection = index == nodes.count - 1 || nodes[index + 1].startsSourceSection
            if startsSection,
               endsSection,
               case .frame(let frame) = node.kind {
                // A singleton source CUT was an honest open-ended segment
                // before combining. A structural source boundary partitions
                // planning; it must not make that source disappear merely
                // because other source sections now share the parent strip.
                bridgedNodeIndexes.insert(index)
                appendGenerated(pair: ShotRenderPair(
                    start: frame,
                    end: nil,
                    startPlacementEntryId: node.entry.entryId
                ))
            }
            if case .clip(let clip) = node.kind {
                // A footage segment "joins" only when a real BRIDGE arrives on
                // its first frame — never after a trailing extension (whose
                // final frame is unknown) and never after a hard cut. A LEAD-IN
                // before it joins by construction: it arrives end-anchored on
                // this footage's real first frame.
                let previousIsLeadIn = index == 1 && nodes[0].isExtensionNode
                let joins = previousIsLeadIn
                    || (index > 0
                        && !nodes[index - 1].isExtensionNode
                        && seamStyle(into: index) == .bridge)
                segments.append(.footage(ShotFootagePlanSegment(
                    displayIndex: segments.count,
                    clip: clip,
                    joinsPrevious: joins
                )))
            }
            if node.isExtensionNode {
                let hasPreviousInSection = index > 0
                    && !node.startsSourceSection
                    && !node.followsSkippedEntry
                let hasNextInSection = index < nodes.count - 1
                    && !nodes[index + 1].startsSourceSection
                    && !nodes[index + 1].followsSkippedEntry
                if (index == 0 || node.startsSourceSection),
                   hasNextInSection,
                   !nodes[index + 1].isExtensionNode {
                    bridgedNodeIndexes.insert(index)
                    bridgedNodeIndexes.insert(index + 1)
                    appendGenerated(
                        pair: ShotRenderPair(
                            start: nil,
                            end: endpoint(nodes[index + 1], edge: .start),
                            startPlacementEntryId: node.entry.entryId,
                            endPlacementEntryId: nodes[index + 1].entry.entryId
                        ),
                        skipTarget: .entry(entryId: node.entry.entryId),
                        isAIExtension: true
                    )
                } else if hasPreviousInSection, !nodes[index - 1].isExtensionNode {
                    // The extension IS an open-ended generated segment picking
                    // up from its left neighbor's final frame.
                    bridgedNodeIndexes.insert(index - 1)
                    bridgedNodeIndexes.insert(index)
                    let nativeSourceClip: ShotFootageClip?
                    if case .clip(let clip) = nodes[index - 1].kind {
                        nativeSourceClip = clip
                    } else {
                        nativeSourceClip = nil
                    }
                    appendGenerated(
                        pair: ShotRenderPair(
                            start: endpoint(nodes[index - 1], edge: .end),
                            end: nil,
                            startPlacementEntryId: nodes[index - 1].entry.entryId,
                            endPlacementEntryId: node.entry.entryId
                        ),
                        skipTarget: .entry(entryId: node.entry.entryId),
                        isAIExtension: true,
                        nativeExtendSourceClip: nativeSourceClip
                    )
                } else if !hasPreviousInSection && !hasNextInSection {
                    skipped.append("AI extension (needs a frame or clip beside it)")
                } else if index == 0 || node.startsSourceSection {
                    skipped.append("AI lead-in (needs a frame or clip after it)")
                } else {
                    skipped.append("AI extension (needs a frame or clip before it)")
                }
            }
            guard index < nodes.count - 1 else { break }
            // No pair into or out of an extension: it is generation itself,
            // and its final frame doesn't exist until rendered — whatever
            // follows hard-cuts.
            if node.isExtensionNode || nodes[index + 1].isExtensionNode {
                continue
            }
            guard seamStyle(into: index + 1) == .bridge else {
                // A deliberately cut frame–frame seam hides the whole pair
                // between two stills — keep it visible and restorable.
                // (Footage-adjacent cuts are ordinary seam state, worn by
                // their chips; a skip-healed seam is covered by its entry
                // placeholder.)
                if !node.isClipNode,
                   !nodes[index + 1].isClipNode,
                   !nodes[index + 1].followsSkippedEntry,
                   !nodes[index + 1].startsSourceSection {
                    placeholders.append(ShotSkippedSegmentPlaceholder(
                        afterDisplayIndex: segments.count - 1,
                        label: "Generated segment",
                        restore: .seam(rightEntryId: nodes[index + 1].entry.entryId)
                    ))
                }
                continue
            }
            bridgedNodeIndexes.insert(index)
            bridgedNodeIndexes.insert(index + 1)
            appendGenerated(
                pair: ShotRenderPair(
                    start: endpoint(node, edge: .end),
                    end: endpoint(nodes[index + 1], edge: .start),
                    startPlacementEntryId: node.entry.entryId,
                    endPlacementEntryId: nodes[index + 1].entry.entryId
                ),
                skipTarget: .seam(rightEntryId: nodes[index + 1].entry.entryId)
            )
        }
        // Honesty: a ready frame no bridge reaches contributes nothing —
        // report it rather than let it silently vanish from the render.
        for (index, node) in nodes.enumerated() {
            if case .frame(let frame) = node.kind, !bridgedNodeIndexes.contains(index) {
                let label = frame.label.trimmed.nilIfEmpty ?? frame.imageId
                skipped.append("\(label) (cut off — no bridge reaches it)")
            }
        }
    }
    emitSkipSeeds(trailingSkipSeeds)

    return (segments, generatedItems, skipped, strands, placeholders)
}

// MARK: - Shot runtime summary (rail-honest math, no strand derivation)

struct ShotRuntimeSummary: Hashable {
    var frames: Int = 0
    var clips: Int = 0
    var bridges: Int = 0
    var footageSeconds: Double = 0
    var joinBridgeSeconds: Double = 0
    /// The cut layer's subtraction: razor ranges plus the shot-level in/out.
    var razorCutSeconds: Double = 0
    /// The arrangement layer's ADDITION: fresh picture-insertion output
    /// seconds, added after the in/out clamp. KNOWN APPROXIMATION: since THE
    /// MATERIAL-WINDOW LAW, the splice can clamp or gate copies by the shot
    /// in/out, which this lightweight mirror (built from the shot document
    /// alone, no plan) cannot model — a trimmed shot's rail estimate can
    /// overstate by the excluded copy seconds. The assembly is the truth.
    var loopSeconds: Double = 0
    /// The whole-output repeat. Deliberately NOT folded into
    /// `estimatedSeconds` — planners (narration, combined-cut estimates)
    /// consume the BASE runtime; only the rail label multiplies it out.
    var outputLoopCount: Int = 1
    var shotInSeconds: Double? = nil
    var shotOutSeconds: Double? = nil

    func estimatedSeconds(segmentSeconds: Int) -> Int {
        estimatedSeconds(generatedSeconds: Double(bridges * segmentSeconds))
    }

    func estimatedSeconds(generatedSeconds: Double) -> Int {
        var total = generatedSeconds + footageSeconds + joinBridgeSeconds - razorCutSeconds
        if let shotOutSeconds {
            total = min(total, shotOutSeconds)
        }
        if let shotInSeconds {
            total -= shotInSeconds
        }
        total = max(total, 0) + loopSeconds
        return Int(max(total, 0).rounded())
    }

    /// The shot rail's one-line truth: "2 FRAMES · 1 CLIP · ~21S".
    func railLabel(segmentSeconds: Int, compact: Bool = false) -> String {
        railLabel(generatedSeconds: Double(bridges * segmentSeconds), compact: compact)
    }

    /// `compact` abbreviates the material terms (FR/CL) for the SCENES v2
    /// ledger cards — ONE formatter for both rails, so the terms can never
    /// drift, and the loop/unrendered honesty chips ride the compact form too.
    func railLabel(generatedSeconds: Double, unrenderedCount: Int = 0, compact: Bool = false) -> String {
        var parts: [String] = []
        parts.append(compact
            ? "\(frames) FR"
            : "\(frames) FRAME\(frames == 1 ? "" : "S")")
        if clips > 0 {
            parts.append(compact
                ? "\(clips) CL"
                : "\(clips) CLIP\(clips == 1 ? "" : "S")")
        }
        let seconds = estimatedSeconds(generatedSeconds: generatedSeconds)
        if seconds > 0 {
            // "~12S ×3=36S": the base runtime stays legible while the rail
            // still tells the whole-output truth.
            parts.append(outputLoopCount > 1
                ? "~\(seconds)S ×\(outputLoopCount)=\(seconds * outputLoopCount)S"
                : "~\(seconds)S")
        }
        // The total above already counts loops; the chip names their share.
        if loopSeconds >= 0.5 {
            parts.append("⟳+\(Int(loopSeconds.rounded()))S")
        }
        // The runtime above counts appended material immediately — the marker
        // keeps the label honest until those segments render.
        if unrenderedCount > 0 {
            parts.append("+\(unrenderedCount) UNRENDERED")
        }
        return parts.joined(separator: " · ")
    }
}

/// Lightweight mirror of the plan walk's counting (ready frames, resolvable
/// clips, resolved bridge seams, real footage seconds) for the shot rail.
func shotRuntimeSummary(
    shot: ProjectShot,
    frameLookup: [String: ProjectLensHeroImage],
    mediaLookup: [String: MediaItemRecord]
) -> ShotRuntimeSummary {
    struct Node {
        var isClip: Bool
        var isExtension: Bool
        var preference: ShotSeamStyle
        var footageSeconds: Double
        var followsSkip: Bool
    }
    var nodes: [Node] = []
    var pendingSkip = false
    for entry in shot.entries {
        if entry.isSkipped {
            pendingSkip = true
            continue
        }
        if entry.isAIExtension {
            nodes.append(Node(isClip: false, isExtension: true, preference: entry.leadSeamPreference, footageSeconds: 0, followsSkip: pendingSkip))
        } else if entry.isClip {
            guard let media = mediaLookup[entry.clipMediaId],
                  media.kind == .video else { continue }
            let assetDuration = max(media.durationSeconds ?? 0, 0)
            let start = min(max(entry.clipStartSeconds ?? 0, 0), assetDuration)
            let end = min(max(entry.clipEndSeconds ?? assetDuration, start), assetDuration)
            if assetDuration > 0, end - start <= 0 { continue }
            nodes.append(Node(isClip: true, isExtension: false, preference: entry.leadSeamPreference, footageSeconds: max(end - start, 0), followsSkip: pendingSkip))
        } else if let frame = frameLookup[entry.frameImageId],
                  frame.status == "ready",
                  !frame.imagePath.trimmed.isEmpty {
            nodes.append(Node(isClip: false, isExtension: false, preference: entry.leadSeamPreference, footageSeconds: 0, followsSkip: pendingSkip))
        } else {
            continue
        }
        pendingSkip = false
    }

    var summary = ShotRuntimeSummary()
    summary.frames = nodes.filter { !$0.isClip && !$0.isExtension }.count
    summary.clips = nodes.filter(\.isClip).count
    summary.footageSeconds = nodes.reduce(0) { $0 + $1.footageSeconds }
    summary.razorCutSeconds = shot.cutList.razorSecondsTotal
    summary.loopSeconds = shotPictureInsertionRuntimeSeconds(shot: shot)
    summary.outputLoopCount = shot.cutList.normalized().outputLoopCount
    summary.joinBridgeSeconds = shot.cutList.segmentCuts.reduce(0) { total, cut in
        guard cut.joinRepair.mode == .generatedBridge,
              let artifact = shot.joinBridgeVersion(cut.joinRepair.activeBridgeVersionId),
              artifact.isReady else { return total }
        return total + artifact.durationSeconds
    }
    summary.shotInSeconds = shot.cutList.shotInSeconds
    summary.shotOutSeconds = shot.cutList.shotOutSeconds
    if nodes.count == 1, !nodes[0].isClip, !nodes[0].isExtension {
        summary.bridges = 1  // the lone-frame open-ended segment
    } else if nodes.count > 1 {
        // An AI lead-in (extension at the front, anchored on a real right
        // neighbor) is its own generated segment — the loop below starts at
        // index 1 and never sees node 0.
        if nodes[0].isExtension, !nodes[1].isExtension {
            summary.bridges += 1
        }
        for index in 1..<nodes.count {
            // An extension is its own generated segment (anchored to a real
            // left neighbor); seams touching extensions never bridge.
            if nodes[index].isExtension {
                if !nodes[index - 1].isExtension {
                    summary.bridges += 1
                }
                continue
            }
            if nodes[index - 1].isExtension {
                continue
            }
            // A seam a skip created always heals to a hard cut.
            if nodes[index].followsSkip {
                continue
            }
            let style = resolvedShotSeamStyle(
                leftIsClip: nodes[index - 1].isClip,
                rightIsClip: nodes[index].isClip,
                rightPreference: nodes[index].preference
            )
            if style == .bridge {
                summary.bridges += 1
            }
        }
    }
    return summary
}

// MARK: - Jovilabe geometry (pure; 0° = 12 o'clock, degrees clockwise)

/// The Shot Jovilabe's dial math. Plates sit at uniform ordinal angles; the
/// pointer is fixed at the top; rotation is the only free variable. All
/// functions are total and deterministic so the instrument's readings are
/// dependable by construction.
enum JovilabeGeometry {
    static func normalizedDegrees(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result < 0 { result += 360 }
        return result
    }

    /// The dial-space angle of plate `index` among `count` plates.
    static func plateAngle(index: Int, count: Int) -> Double {
        guard count > 0 else { return 0 }
        return Double(index) / Double(count) * 360
    }

    /// The plate nearest the fixed top pointer at the given rotation.
    static func pointerIndex(rotationDegrees: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let step = 360 / Double(count)
        let raw = Int((normalizedDegrees(-rotationDegrees) / step).rounded())
        return ((raw % count) + count) % count
    }

    /// The shortest-arc rotation that seats plate `index` under the pointer.
    static func rotation(bringing index: Int, count: Int, from current: Double) -> Double {
        guard count > 0 else { return current }
        let target = -plateAngle(index: index, count: count)
        var delta = (target - current).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return current + delta
    }

    /// Maps a lifted plate's on-screen angle back to the dial position it would
    /// occupy on release, at the current rotation.
    static func insertionIndex(atScreenAngle screenAngle: Double, rotationDegrees: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let dialAngle = normalizedDegrees(screenAngle - rotationDegrees)
        let step = 360 / Double(count)
        let raw = Int((dialAngle / step).rounded())
        return ((raw % count) + count) % count
    }

    /// Converts a desired FINAL position into the pre-removal gap index that
    /// `ProjectShot.movingEntry(entryId:toIndex:)` expects.
    static func moveGapIndex(finalIndex: Int, sourceIndex: Int) -> Int {
        finalIndex > sourceIndex ? finalIndex + 1 : finalIndex
    }
}

/// The strand palette: role tints plus a few more Canon hues, indexed by
/// `MeaningStrand.hueIndex`.
enum MeaningStrandPalette {
    static let hues: [Color] = [
        CanonColor.brass,
        CanonColor.roleAccentOne,
        CanonColor.roleAccentTwo,
        CanonColor.olive,
        CanonColor.focusBlue,
        CanonColor.rust
    ]

    static func hue(at index: Int) -> Color {
        hues[((index % hues.count) + hues.count) % hues.count]
    }
}

/// Derives the ambient meaning-strand network from what frames already carry:
/// prompts/subjects matched lexically against the project's resolved meaning
/// nodes, plus shared style identity and shared scene/area taxonomy. A strand
/// exists when a signal touches ≥ 2 cells; the strongest `maxStrands` survive
/// so the braid stays graceful.
func deriveMeaningStrands(
    shots: [ProjectShot],
    frameLookup: [String: ProjectLensHeroImage],
    meaningNodes: [LensContextPromptMeaningNode],
    maxStrands: Int = 6
) -> [MeaningStrand] {
    struct Candidate {
        var kind: MeaningStrandKind
        var slug: String
        var label: String
        var detail: String
        var touches: [MeaningStrandTouch]
    }
    var candidates: [String: Candidate] = [:]

    func addTouch(key: String, kind: MeaningStrandKind, slug: String, label: String, detail: String, touch: MeaningStrandTouch) {
        var candidate = candidates[key] ?? Candidate(kind: kind, slug: slug, label: label, detail: detail, touches: [])
        candidate.touches.append(touch)
        candidates[key] = candidate
    }

    for (shotIndex, shot) in shots.enumerated() {
        for (entryIndex, entry) in shot.entries.enumerated() {
            guard let frame = frameLookup[entry.frameImageId] else { continue }
            let touch = MeaningStrandTouch(
                shotIndex: shotIndex,
                entryIndex: entryIndex,
                shotId: shot.shotId,
                entryId: entry.entryId
            )
            let text = [frame.prompt, frame.sourcePrompt, frame.subject?.description ?? ""]
                .joined(separator: " ")
                .lowercased()

            for node in meaningNodes {
                let name = node.name.trimmed.lowercased()
                let nameHit = name.count >= 4 && text.contains(name)
                let tagHit = !nameHit && node.tags.contains { tag in
                    let cleaned = tag.trimmed.lowercased()
                    return cleaned.count >= 5 && text.contains(cleaned)
                }
                if nameHit || tagHit {
                    addTouch(
                        key: "meaning:\(node.slug)",
                        kind: .meaning,
                        slug: node.slug,
                        label: node.name,
                        detail: node.definition,
                        touch: touch
                    )
                }
            }

            if let styleId = frame.sourceAestheticIds.first?.trimmed, !styleId.isEmpty {
                let styleLabel = frame.styleAuthorities.first?.normalized().title.trimmed.nilIfEmpty ?? styleId
                addTouch(
                    key: "style:\(styleId)",
                    kind: .style,
                    slug: styleId,
                    label: styleLabel,
                    detail: "Shared style identity",
                    touch: touch
                )
            }

            let placeId = frame.sceneId.trimmed.nilIfEmpty ?? frame.areaId.trimmed.nilIfEmpty ?? ""
            if !placeId.isEmpty {
                addTouch(
                    key: "place:\(placeId)",
                    kind: .place,
                    slug: placeId,
                    label: "Shared place",
                    detail: "Frames staged in the same scene or area",
                    touch: touch
                )
            }
        }
    }

    // A strand must connect at least two DISTINCT cells.
    let connected = candidates.filter { $0.value.touches.count >= 2 }

    // Strongest first (touch count desc), deterministic tie-break by key;
    // meaning strands outrank style/place at equal strength.
    func kindRank(_ kind: MeaningStrandKind) -> Int {
        switch kind {
        case .meaning: return 0
        case .style: return 1
        case .place: return 2
        }
    }
    let ranked = connected.sorted { lhs, rhs in
        if lhs.value.touches.count != rhs.value.touches.count {
            return lhs.value.touches.count > rhs.value.touches.count
        }
        if kindRank(lhs.value.kind) != kindRank(rhs.value.kind) {
            return kindRank(lhs.value.kind) < kindRank(rhs.value.kind)
        }
        return lhs.key < rhs.key
    }.prefix(max(0, maxStrands))

    return ranked.enumerated().map { index, element in
        let candidate = element.value
        let orderedTouches = candidate.touches.sorted {
            ($0.shotIndex, $0.entryIndex) < ($1.shotIndex, $1.entryIndex)
        }
        return MeaningStrand(
            strandId: element.key,
            kind: candidate.kind,
            slug: candidate.slug,
            label: candidate.label,
            detail: candidate.detail,
            hueIndex: index,
            touches: orderedTouches
        )
    }
}

/// Launch-time restyle reconcile, pure: after a relaunch NO local task can
/// exist, so any Look still marked in-flight is either an orphan (preparing/
/// uploading — no provider job id was saved; rewritten to failed with honest
/// spend copy) or provider-recoverable (queued/generating/downloading with a
/// request id — returned for resume). The engine persists the returned
/// document when `changed` and spawns the resumes: Shot Looks serially
/// through the single video-operation lock, Clip Looks through their
/// concurrency lane.
func restyleResumePreflight(
    document: ProjectShotTimelineDocument,
    now: String
) -> (
    document: ProjectShotTimelineDocument,
    changed: Bool,
    shotLooks: [(shotId: String, artifact: ShotRestyleArtifact)],
    clipLooks: [(shotId: String, artifact: ShotRestyleArtifact)]
) {
    var document = document
    var shotLooks: [(shotId: String, artifact: ShotRestyleArtifact)] = []
    var clipLooks: [(shotId: String, artifact: ShotRestyleArtifact)] = []
    var changed = false
    for shotIndex in document.shots.indices {
        var shot = document.shots[shotIndex]
        for lookIndex in shot.lookVersions.indices {
            var look = shot.lookVersions[lookIndex]
            switch look.status {
            case "preparing":
                look.status = "failed"
                look.errorMessage = "Interrupted before provider submission; retry creates a new Look."
                look.updatedAt = now
                shot.lookVersions[lookIndex] = look
                changed = true
            case "uploading":
                look.status = "failed"
                look.errorMessage = look.restyleProvider == .decart
                    ? "Decart submission was interrupted before its job id was saved. Remote acceptance is unknown; check Decart before retrying to avoid duplicate spend."
                    : "Interrupted before provider submission; retry creates a new Look."
                look.updatedAt = now
                shot.lookVersions[lookIndex] = look
                changed = true
            case "queued", "generating", "downloading":
                if look.requestId.isEmpty {
                    look.status = "failed"
                    look.errorMessage = "Interrupted without a recoverable provider request id."
                    look.updatedAt = now
                    shot.lookVersions[lookIndex] = look
                    changed = true
                } else {
                    shotLooks.append((shot.shotId, look))
                }
            default:
                break
            }
        }
        for clipIndex in shot.clipLookVersions.indices {
            var look = shot.clipLookVersions[clipIndex]
            switch look.status {
            case "preparing":
                look.status = "failed"
                look.errorMessage = "Interrupted before provider submission; restyle again to create a new Clip Look."
                look.updatedAt = now
                shot.clipLookVersions[clipIndex] = look
                changed = true
            case "uploading":
                look.status = "failed"
                look.errorMessage = look.restyleProvider == .decart
                    ? "Decart submission was interrupted before its job id was saved. Remote acceptance is unknown; check Decart before retrying to avoid duplicate spend."
                    : "Interrupted before provider submission; restyle again to create a new Clip Look."
                look.updatedAt = now
                shot.clipLookVersions[clipIndex] = look
                changed = true
            case "queued", "generating", "downloading":
                if look.requestId.isEmpty {
                    look.status = "failed"
                    look.errorMessage = "Interrupted without a recoverable provider request id."
                    look.updatedAt = now
                    shot.clipLookVersions[clipIndex] = look
                    changed = true
                } else {
                    clipLooks.append((shot.shotId, look))
                }
            default:
                break
            }
        }
        document.shots[shotIndex] = shot
    }
    return (document, changed, shotLooks, clipLooks)
}
