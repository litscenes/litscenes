import Foundation

/// The two executable ways a Scene tail can continue. The persisted take
/// stores the raw value so a newer build's mode never makes an older project
/// undecodable.
enum ShotContinuationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case nativeExtend = "native_extend"
    case outFrame = "out_frame"
    case arriveAtFrame = "arrive_at_frame"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nativeExtend: return "Native Extend"
        case .outFrame: return "Out-frame"
        case .arriveAtFrame: return "Arrive at Frame"
        }
    }
}

enum ShotContinuationTakeStatus: String, Sendable {
    case queued
    case generating
    case ready
    case failed
    case canceled
    case interrupted
}

/// Exact material endpoint used by one continuation attempt. A still is
/// always present before submission; a tail clip is additive and enables
/// Native Extend without weakening the still-based fallback.
struct ShotContinuationAnchor: Codable, Hashable, Sendable {
    var sourceKind: String = ""
    var sourceEntryId: String = ""
    var sourceTakeId: String = ""
    var sourceRenderVersionId: String = ""
    var sourceSegmentPlacementKey: String = ""
    var framePath: String = ""
    var frameFingerprint: String = ""
    var tailClipPath: String = ""
    var tailClipStartSeconds: Double = 0
    var tailClipEndSeconds: Double = 0
    var tailClipFingerprint: String = ""
    var anchorFingerprint: String = ""
    var endpointEvidence: ShotVideoEndpointEvidence?

    var tailClipDurationSeconds: Double {
        max(tailClipEndSeconds - tailClipStartSeconds, 0)
    }

    var hasFrame: Bool { !framePath.trimmed.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case sourceKind, sourceEntryId, sourceTakeId, sourceRenderVersionId
        case sourceSegmentPlacementKey, framePath, frameFingerprint
        case tailClipPath, tailClipStartSeconds, tailClipEndSeconds
        case tailClipFingerprint, anchorFingerprint, endpointEvidence
    }

    init(
        sourceKind: String = "",
        sourceEntryId: String = "",
        sourceTakeId: String = "",
        sourceRenderVersionId: String = "",
        sourceSegmentPlacementKey: String = "",
        framePath: String = "",
        frameFingerprint: String = "",
        tailClipPath: String = "",
        tailClipStartSeconds: Double = 0,
        tailClipEndSeconds: Double = 0,
        tailClipFingerprint: String = "",
        anchorFingerprint: String = ""
    ) {
        self.sourceKind = sourceKind
        self.sourceEntryId = sourceEntryId
        self.sourceTakeId = sourceTakeId
        self.sourceRenderVersionId = sourceRenderVersionId
        self.sourceSegmentPlacementKey = sourceSegmentPlacementKey
        self.framePath = framePath
        self.frameFingerprint = frameFingerprint
        self.tailClipPath = tailClipPath
        self.tailClipStartSeconds = tailClipStartSeconds
        self.tailClipEndSeconds = tailClipEndSeconds
        self.tailClipFingerprint = tailClipFingerprint
        self.anchorFingerprint = anchorFingerprint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceKind = try container.decodeIfPresent(String.self, forKey: .sourceKind) ?? ""
        sourceEntryId = try container.decodeIfPresent(String.self, forKey: .sourceEntryId) ?? ""
        sourceTakeId = try container.decodeIfPresent(String.self, forKey: .sourceTakeId) ?? ""
        sourceRenderVersionId = try container.decodeIfPresent(String.self, forKey: .sourceRenderVersionId) ?? ""
        sourceSegmentPlacementKey = try container.decodeIfPresent(String.self, forKey: .sourceSegmentPlacementKey) ?? ""
        framePath = try container.decodeIfPresent(String.self, forKey: .framePath) ?? ""
        frameFingerprint = try container.decodeIfPresent(String.self, forKey: .frameFingerprint) ?? ""
        tailClipPath = try container.decodeIfPresent(String.self, forKey: .tailClipPath) ?? ""
        tailClipStartSeconds = try container.decodeIfPresent(Double.self, forKey: .tailClipStartSeconds) ?? 0
        tailClipEndSeconds = try container.decodeIfPresent(Double.self, forKey: .tailClipEndSeconds) ?? 0
        tailClipFingerprint = try container.decodeIfPresent(String.self, forKey: .tailClipFingerprint) ?? ""
        anchorFingerprint = try container.decodeIfPresent(String.self, forKey: .anchorFingerprint) ?? ""
        endpointEvidence = try? container.decodeIfPresent(ShotVideoEndpointEvidence.self, forKey: .endpointEvidence)
    }

    var syntheticFrame: ProjectLensHeroImage {
        let fingerprint = resolvedFingerprint
        let gist = "the exact final frame of the Scene material being continued"
        return ProjectLensHeroImage(
            imageId: "continuation_anchor_\(shortHash(fingerprint, length: 20))",
            label: "Continuation anchor",
            provider: "continuation",
            model: "",
            imagePath: framePath,
            prompt: gist,
            sourcePrompt: gist,
            status: "ready"
        )
    }

    var resolvedFingerprint: String {
        anchorFingerprint.trimmed.nilIfEmpty
            ?? shotContinuationAnchorFingerprint(
                sourceKind: sourceKind,
                sourceEntryId: sourceEntryId,
                sourceTakeId: sourceTakeId,
                sourceRenderVersionId: sourceRenderVersionId,
                sourceSegmentPlacementKey: sourceSegmentPlacementKey,
                frameFingerprint: frameFingerprint,
                tailClipFingerprint: tailClipFingerprint,
                tailClipStartSeconds: tailClipStartSeconds,
                tailClipEndSeconds: tailClipEndSeconds
            )
    }

    func normalized() -> ShotContinuationAnchor {
        var value = self
        value.sourceKind = value.sourceKind.trimmed
        value.sourceEntryId = value.sourceEntryId.trimmed
        value.sourceTakeId = value.sourceTakeId.trimmed
        value.sourceRenderVersionId = value.sourceRenderVersionId.trimmed
        value.sourceSegmentPlacementKey = value.sourceSegmentPlacementKey.trimmed
        value.framePath = value.framePath.trimmed
        value.frameFingerprint = value.frameFingerprint.trimmed.lowercased()
        value.tailClipPath = value.tailClipPath.trimmed
        value.tailClipFingerprint = value.tailClipFingerprint.trimmed.lowercased()
        value.tailClipStartSeconds = max(value.tailClipStartSeconds.isFinite ? value.tailClipStartSeconds : 0, 0)
        value.tailClipEndSeconds = max(
            value.tailClipEndSeconds.isFinite ? value.tailClipEndSeconds : 0,
            value.tailClipStartSeconds
        )
        value.anchorFingerprint = value.resolvedFingerprint
        return value
    }
}

func shotContinuationAnchorFingerprint(
    sourceKind: String,
    sourceEntryId: String,
    sourceTakeId: String,
    sourceRenderVersionId: String,
    sourceSegmentPlacementKey: String,
    frameFingerprint: String,
    tailClipFingerprint: String,
    tailClipStartSeconds: Double,
    tailClipEndSeconds: Double
) -> String {
    let basis = [
        sourceKind.trimmed,
        sourceEntryId.trimmed,
        sourceTakeId.trimmed,
        sourceRenderVersionId.trimmed,
        sourceSegmentPlacementKey.trimmed,
        frameFingerprint.trimmed.lowercased(),
        tailClipFingerprint.trimmed.lowercased(),
        String(format: "%.3f", tailClipStartSeconds),
        String(format: "%.3f", tailClipEndSeconds)
    ].joined(separator: "|")
    return sha256Hex(Data(basis.utf8))
}

/// One paid or attempted continuation. The successful segment clip is the
/// canonical media/provenance payload; Scene render artifacts copy it as an
/// immutable snapshot and identify it by `continuationTakeId`.
struct ShotContinuationTake: Codable, Hashable, Sendable, Identifiable {
    var takeId: String = ""
    var takeNumber: Int = 0
    var status: String = ""
    var anchor: ShotContinuationAnchor = ShotContinuationAnchor()
    var targetFrame: ShotContinuationTargetFrame?
    var prompt: String = ""
    var mode: String = ""
    var stack: String = ""
    var segmentClip: ShotRenderSegmentClip?
    var finalFramePath: String = ""
    var providerOutputPath: String = ""
    var workflowStep: String = "preflight"
    var outputFingerprint: String = ""
    var requestId: String = ""
    var traceId: String = ""
    var errorMessage: String = ""
    var createdAt: String = ""
    var updatedAt: String = ""

    var id: String { takeId }

    private enum CodingKeys: String, CodingKey {
        case takeId, takeNumber, status, anchor, targetFrame, prompt, mode, stack
        case segmentClip, finalFramePath, providerOutputPath, workflowStep, outputFingerprint, requestId, traceId
        case errorMessage, createdAt, updatedAt
    }

    init(
        takeId: String = "",
        takeNumber: Int = 0,
        status: String = "",
        anchor: ShotContinuationAnchor = ShotContinuationAnchor(),
        prompt: String = "",
        mode: String = "",
        stack: String = "",
        segmentClip: ShotRenderSegmentClip? = nil,
        finalFramePath: String = "",
        outputFingerprint: String = "",
        requestId: String = "",
        traceId: String = "",
        errorMessage: String = "",
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.takeId = takeId
        self.takeNumber = takeNumber
        self.status = status
        self.anchor = anchor
        self.prompt = prompt
        self.mode = mode
        self.stack = stack
        self.segmentClip = segmentClip
        self.finalFramePath = finalFramePath
        self.outputFingerprint = outputFingerprint
        self.requestId = requestId
        self.traceId = traceId
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        takeId = try container.decodeIfPresent(String.self, forKey: .takeId) ?? ""
        takeNumber = try container.decodeIfPresent(Int.self, forKey: .takeNumber) ?? 0
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        anchor = ((try? container.decodeIfPresent(ShotContinuationAnchor.self, forKey: .anchor)) ?? nil)
            ?? ShotContinuationAnchor()
        targetFrame = try container.decodeIfPresent(ShotContinuationTargetFrame.self, forKey: .targetFrame)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        mode = try container.decodeIfPresent(String.self, forKey: .mode) ?? ""
        stack = try container.decodeIfPresent(String.self, forKey: .stack) ?? ""
        segmentClip = (try? container.decodeIfPresent(ShotRenderSegmentClip.self, forKey: .segmentClip)) ?? nil
        finalFramePath = try container.decodeIfPresent(String.self, forKey: .finalFramePath) ?? ""
        providerOutputPath = try container.decodeIfPresent(String.self, forKey: .providerOutputPath) ?? ""
        workflowStep = try container.decodeIfPresent(String.self, forKey: .workflowStep) ?? "legacy"
        outputFingerprint = try container.decodeIfPresent(String.self, forKey: .outputFingerprint) ?? ""
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId) ?? ""
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId) ?? ""
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    var hasLocalRecoveryReceipt: Bool {
        guard !anchor.framePath.isEmpty else { return false }
        let url = URL(fileURLWithPath: anchor.framePath).deletingLastPathComponent().appendingPathComponent("take-recovery.json")
        return FileManager.default.fileExists(atPath: url.path)
    }

    var takeStatus: ShotContinuationTakeStatus {
        ShotContinuationTakeStatus(rawValue: status) ?? .failed
    }

    var continuationMode: ShotContinuationMode {
        ShotContinuationMode(rawValue: mode) ?? .outFrame
    }

    var renderStack: ShotRenderStack {
        (ShotRenderStack(rawValue: stack) ?? .fallback).upgradedForFutureRender
    }

    var isReady: Bool {
        takeStatus == .ready
            && segmentClip?.clipPath.trimmed.nilIfEmpty != nil
    }

    func normalized() -> ShotContinuationTake {
        var value = self
        value.takeId = value.takeId.trimmed
        value.takeNumber = max(value.takeNumber, 0)
        value.status = value.status.trimmed
        value.anchor = value.anchor.normalized()
        value.prompt = value.prompt.trimmed
        value.mode = value.mode.trimmed
        value.stack = value.stack.trimmed
        value.segmentClip = value.segmentClip?.normalized()
        value.finalFramePath = value.finalFramePath.trimmed
        value.outputFingerprint = value.outputFingerprint.trimmed.lowercased()
        value.requestId = value.requestId.trimmed
        value.traceId = value.traceId.trimmed
        value.errorMessage = value.errorMessage.trimmed
        value.createdAt = value.createdAt.trimmed
        value.updatedAt = value.updatedAt.trimmed
        return value
    }
}

/// All attempts for one live AI-extension entry. `selectedTakeId` is creative
/// working state; `renderingTakeId` names only the attempt currently being
/// generated and never displaces a ready selection on failure.
struct ShotContinuationRecord: Codable, Hashable, Sendable, Identifiable {
    var entryId: String = ""
    var sourceEntryId: String = ""
    var selectedTakeId: String = ""
    var renderingTakeId: String = ""
    var takes: [ShotContinuationTake] = []
    var preservedSourceClips: [ShotRenderSegmentClip] = []
    var rebuildPending: Bool = false
    var createdAt: String = ""
    var updatedAt: String = ""

    var id: String { entryId }

    private enum CodingKeys: String, CodingKey {
        case entryId, sourceEntryId, selectedTakeId, renderingTakeId
        case takes, preservedSourceClips, rebuildPending, createdAt, updatedAt
    }

    init(
        entryId: String = "",
        sourceEntryId: String = "",
        selectedTakeId: String = "",
        renderingTakeId: String = "",
        takes: [ShotContinuationTake] = [],
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.entryId = entryId
        self.sourceEntryId = sourceEntryId
        self.selectedTakeId = selectedTakeId
        self.renderingTakeId = renderingTakeId
        self.takes = takes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryId = try container.decodeIfPresent(String.self, forKey: .entryId) ?? ""
        sourceEntryId = try container.decodeIfPresent(String.self, forKey: .sourceEntryId) ?? ""
        selectedTakeId = try container.decodeIfPresent(String.self, forKey: .selectedTakeId) ?? ""
        renderingTakeId = try container.decodeIfPresent(String.self, forKey: .renderingTakeId) ?? ""
        takes = ((try? container.decodeIfPresent([ShotContinuationTake].self, forKey: .takes)) ?? nil) ?? []
        preservedSourceClips = try container.decodeIfPresent([ShotRenderSegmentClip].self, forKey: .preservedSourceClips) ?? []
        rebuildPending = try container.decodeIfPresent(Bool.self, forKey: .rebuildPending) ?? false
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    var sortedTakes: [ShotContinuationTake] {
        takes.sorted { lhs, rhs in
            if lhs.takeNumber == rhs.takeNumber { return lhs.createdAt < rhs.createdAt }
            return lhs.takeNumber < rhs.takeNumber
        }
    }

    var selectedTake: ShotContinuationTake? {
        takes.first { $0.takeId == selectedTakeId && $0.isReady }
    }

    var renderingTake: ShotContinuationTake? {
        takes.first { $0.takeId == renderingTakeId && [.queued, .generating].contains($0.takeStatus) }
    }

    var renderTake: ShotContinuationTake? { renderingTake ?? selectedTake }

    var readyTakes: [ShotContinuationTake] { sortedTakes.filter(\.isReady) }

    func normalized() -> ShotContinuationRecord {
        var value = self
        value.entryId = value.entryId.trimmed
        value.sourceEntryId = value.sourceEntryId.trimmed
        value.selectedTakeId = value.selectedTakeId.trimmed
        value.renderingTakeId = value.renderingTakeId.trimmed
        var seen: Set<String> = []
        value.takes = value.takes
            .map { $0.normalized() }
            .filter { !$0.takeId.isEmpty && seen.insert($0.takeId).inserted }
            .sorted { lhs, rhs in
                if lhs.takeNumber == rhs.takeNumber { return lhs.createdAt < rhs.createdAt }
                return lhs.takeNumber < rhs.takeNumber
            }
        if value.selectedTake == nil { value.selectedTakeId = "" }
        if value.renderingTake == nil { value.renderingTakeId = "" }
        value.createdAt = value.createdAt.trimmed
        value.updatedAt = value.updatedAt.trimmed
        return value
    }

    func upsertingTake(_ take: ShotContinuationTake, select: Bool, now: String) -> ShotContinuationRecord {
        let normalizedTake = take.normalized()
        guard !normalizedTake.takeId.isEmpty else { return self }
        var value = self
        value.takes.removeAll { $0.takeId == normalizedTake.takeId }
        value.takes.append(normalizedTake)
        if [.queued, .generating].contains(normalizedTake.takeStatus) {
            value.renderingTakeId = normalizedTake.takeId
        } else if value.renderingTakeId == normalizedTake.takeId {
            value.renderingTakeId = ""
        }
        if select, normalizedTake.isReady {
            value.selectedTakeId = normalizedTake.takeId
        }
        value.updatedAt = now
        return value.normalized()
    }
}

enum ShotContinuationLockReason: String, Sendable {
    case emptyScene = "empty_scene"
    case missingTail = "missing_tail"
    case activeLook = "active_look"
    case shortenedOutput = "shortened_output"
    case reversedOutput = "reversed_output"
    case loopedOutput = "looped_output"
    case arrangedOutput = "arranged_output"
    case staleChain = "stale_chain"
    case rendering = "rendering"
    case missingCredential = "missing_credential"

    var message: String {
        switch self {
        case .emptyScene: return "Add or create a Frame or Footage clip before continuing with AI."
        case .missingTail: return "The Scene tail is not ready or its source file is missing."
        case .activeLook: return "This Scene is showing a Look, so its visible endpoint is not the Original tail. Show Original to continue honestly."
        case .shortenedOutput: return "The OUT point changes the visible endpoint. Clear or bake that edit before continuing with AI."
        case .reversedOutput: return "The Scene ends in reverse, so the Original tail is not the visible endpoint. Turn Reverse off before continuing."
        case .loopedOutput: return "The Scene output is looped. Return it to one pass before continuing from its tail."
        case .arrangedOutput: return "Arranged picture copies change output order. Remove or bake them before continuing with AI."
        case .staleChain: return "This Scene's generated chain has changed upstream. Review the chain before extending its tail."
        case .rendering: return "Wait for the current video operation to finish before extending this Scene."
        case .missingCredential: return "Configure an executable video provider in App Settings before continuing with AI."
        }
    }

    var repairLabel: String? {
        switch self {
        case .activeLook: return "SHOW ORIGINAL"
        case .shortenedOutput, .reversedOutput, .loopedOutput, .arrangedOutput: return "OPEN EDITOR"
        case .staleChain: return "REVIEW CHAIN"
        default: return nil
        }
    }
}

/// Read-only review payload. Preparing an exact footage/render endpoint may
/// replace `anchor` asynchronously, but it never changes ProjectShot state.
struct ShotContinuationAvailability: Sendable {
    var anchor: ShotContinuationAnchor?
    var targetFrame: ShotContinuationTargetFrame?
    var lockReason: ShotContinuationLockReason?
    var outFrameStack: ShotRenderStack = .fallback
    var outFrameAvailable: Bool = false
    var nativeStack: ShotRenderStack?
    var suggestedPrompt: String = "Smooth continuous camera and subject motion from the current final frame."
    var endpointNotice: String?

    var canContinue: Bool {
        lockReason == nil
            && anchor?.hasFrame == true
            && (outFrameAvailable || nativeStack != nil)
    }
    /// Review intent is transient; immutable take recipes remain the ledger.
    var requestedMode: ShotContinuationMode? = nil
    var preferredMode: ShotContinuationMode {
        if targetFrame != nil { return .arriveAtFrame }
        if requestedMode == .outFrame, outFrameAvailable { return .outFrame }
        if requestedMode == .nativeExtend, nativeStack != nil { return .nativeExtend }
        return nativeStack == nil ? .outFrame : .nativeExtend
    }
}

struct ShotContinuationRequest: Codable, Sendable {
    var mode: ShotContinuationMode
    var stack: ShotRenderStack
    var prompt: String
    var preparedAnchor: ShotContinuationAnchor
    var targetFrame: ShotContinuationTargetFrame? = nil
}

/// Runtime source for LTX Native Extend. Placed Footage resolves through the
/// render loop's durable ranged copy; rendered segments and continuation
/// takes already name their exact durable clip directly.
struct ShotNativeExtendSource: Hashable, Sendable {
    var kind: String
    var entryId: String
    var mediaId: String
    var path: String
    var durationSeconds: Double
    var sourceStartSeconds: Double
    var sourceEndSeconds: Double
    var fingerprint: String
    var sourceRenderVersionId: String
    var sourceTakeId: String

    static func footage(_ clip: ShotFootageClip) -> ShotNativeExtendSource {
        ShotNativeExtendSource(
            kind: "shot_footage_range",
            entryId: clip.entryId,
            mediaId: clip.mediaId,
            path: "",
            durationSeconds: clip.resolvedDurationSeconds,
            sourceStartSeconds: clip.resolvedStartSeconds,
            sourceEndSeconds: clip.resolvedEndSeconds,
            fingerprint: "",
            sourceRenderVersionId: "",
            sourceTakeId: ""
        )
    }

    static func anchor(_ anchor: ShotContinuationAnchor) -> ShotNativeExtendSource? {
        guard !anchor.tailClipPath.trimmed.isEmpty,
              anchor.tailClipDurationSeconds > 0 else { return nil }
        return ShotNativeExtendSource(
            kind: anchor.sourceKind.trimmed.nilIfEmpty ?? "shot_render_tail",
            entryId: anchor.sourceEntryId,
            mediaId: "",
            path: anchor.tailClipPath,
            durationSeconds: anchor.tailClipDurationSeconds,
            sourceStartSeconds: anchor.tailClipStartSeconds,
            sourceEndSeconds: anchor.tailClipEndSeconds,
            fingerprint: anchor.tailClipFingerprint,
            sourceRenderVersionId: anchor.sourceRenderVersionId,
            sourceTakeId: anchor.sourceTakeId
        )
    }
}

/// The exact already-rendered clips a continuation was reviewed against.
/// This is derived from immutable anchor lineage rather than persisted as a
/// second owner of the media. It lets an existing rendered Scene remain the
/// first playable sequence after its final open-ended plan slot becomes a
/// continuation slot.
func shotContinuationRenderedSourceClips(
    shot: ProjectShot,
    record: ShotContinuationRecord?
) -> (versionId: String, clips: [ShotRenderSegmentClip])? {
    guard let take = record?.selectedTake ?? record?.renderingTake ?? record?.sortedTakes.last else { return nil }
    if let record, !record.preservedSourceClips.isEmpty {
        return (take.anchor.sourceRenderVersionId, record.preservedSourceClips)
    }
    let anchor = take.anchor.normalized()
    guard anchor.sourceKind == "rendered_original" else { return nil }

    let version = shot.renderVersions.first { $0.versionId == anchor.sourceRenderVersionId }
        ?? shot.renderArtifact.flatMap { artifact in
            artifact.versionId == anchor.sourceRenderVersionId ? artifact : nil
        }
    if let version {
        let ordered = version.clipPaths.compactMap { path in
            version.segmentClips.first { $0.clipPath == path }
        }
        if !ordered.isEmpty, ordered.count == version.clipPaths.count,
           ordered.allSatisfy({ FileManager.default.fileExists(atPath: $0.clipPath) }) {
            return (
                anchor.sourceRenderVersionId,
                ordered.map { clip in
                    var saved = clip
                    if saved.sourceRenderVersionId.isEmpty {
                        saved.sourceRenderVersionId = anchor.sourceRenderVersionId
                    }
                    return saved.normalized()
                }
            )
        }
    }

    // Legacy or incomplete artifacts may not have an ordered per-segment
    // ledger. The reviewed anchor still names their exact whole render; wrap
    // that artifact as one reuse-only clip rather than retaining only its tail.
    let path = version?.videoPath.trimmed.nilIfEmpty
    guard let path else { return nil }
    let sourceEntry = shot.entries.first { $0.entryId == anchor.sourceEntryId }
    let duration: Double
    if let version, path == version.videoPath {
        duration = shotArtifactBandGeometry(version).durationSeconds
    } else {
        duration = anchor.tailClipDurationSeconds > 0
            ? anchor.tailClipDurationSeconds
            : Double(max(version?.totalSeconds ?? 0, 0))
    }
    let clip = ShotRenderSegmentClip(
        startFrameImageId: sourceEntry?.frameImageId ?? "",
        placementStartEntryId: anchor.sourceEntryId,
        clipPath: path,
        requestId: version?.requestIds.last ?? "",
        provider: version?.provider ?? "legacy",
        model: version?.model ?? "legacy",
        requestedDurationSeconds: 0,
        durationSeconds: duration,
        sourceRenderVersionId: anchor.sourceRenderVersionId,
        sourceFingerprint: anchor.tailClipFingerprint,
        updatedAt: version?.updatedAt ?? take.updatedAt
    )
    return (anchor.sourceRenderVersionId, [clip.normalized()])
}

/// Best-effort recipe recovery for extension clips created before take
/// records existed. Exact provider/model provenance wins; unknown historical
/// values fall back to the clip's requested duration without making the
/// project undecodable.
func shotContinuationRenderStack(for clip: ShotRenderSegmentClip) -> ShotRenderStack {
    let duration = max(clip.requestedDurationSeconds, 1)
    if clip.providerOperation.lowercased().contains("extend") {
        return ShotRenderStack.recipe(
            model: .ltx23NativeExtend,
            durationSeconds: duration,
            generateAudio: true
        )
    }
    let candidates = ShotRenderModel.allCases + [.klingV26Pro]
    if let model = candidates.first(where: { model in
        let stack = ShotRenderStack.recipe(model: model, durationSeconds: duration)
        let providerMatches = clip.provider.trimmed.isEmpty
            || clip.provider == stack.providerSelection.rawValue
        return providerMatches
            && (clip.model == stack.openEndedModelSelection.providerModelId
                || clip.model == stack.pairedModelSelection.providerModelId)
    }) {
        return ShotRenderStack.recipe(
            model: model,
            durationSeconds: duration,
            generateAudio: clip.generateAudio
        )
    }
    return ShotRenderStack.fallback.replacingDuration(duration)
}

enum ShotContinuationBranchResolution: Equatable, Sendable {
    case selectCurrent
    case rechain(staleEntryIds: [String])
}

struct ShotContinuationBranchImpact: Equatable, Sendable {
    var requestedEntryId: String
    var requestedTakeId: String
    var resolution: ShotContinuationBranchResolution
}

/// Staleness is lineage, never another persisted status. Once one selected
/// continuation no longer starts at its predecessor's selected output, every
/// dependent continuation after it is stale until a compatible branch is
/// restored or regenerated.
func shotContinuationStaleEntryIds(_ shot: ProjectShot) -> [String] {
    var stale: [String] = []
    var previousContinuationOutput = ""
    var previousContinuationTakeId = ""
    var dependencyBroken = false
    for entry in shot.entries where !entry.isSkipped {
        guard entry.isAIExtension || shot.continuationRecord(entryId: entry.entryId) != nil else {
            previousContinuationOutput = ""
            previousContinuationTakeId = ""
            dependencyBroken = false
            continue
        }
        guard let record = shot.continuationRecord(entryId: entry.entryId),
              let take = record.selectedTake else {
            stale.append(entry.entryId)
            dependencyBroken = true
            continue
        }
        if dependencyBroken {
            stale.append(entry.entryId)
        } else if !previousContinuationTakeId.isEmpty {
            let namesExpectedTake = take.anchor.sourceTakeId == previousContinuationTakeId
            let matchesOutput = !previousContinuationOutput.isEmpty
                && take.anchor.frameFingerprint == previousContinuationOutput
            if !namesExpectedTake && !matchesOutput {
                stale.append(entry.entryId)
                dependencyBroken = true
            }
        }
        previousContinuationOutput = take.outputFingerprint
        previousContinuationTakeId = take.takeId
    }
    return stale
}

func shotHasDependentContinuationChain(_ shot: ProjectShot) -> Bool {
    var previousWasExtension = false
    for entry in shot.entries where !entry.isSkipped {
        let isLink = entry.isAIExtension || shot.continuationRecord(entryId: entry.entryId) != nil
        if isLink, previousWasExtension { return true }
        previousWasExtension = isLink
    }
    return false
}

/// Generation outcomes belong to a continuation, never to a whole-Shot version.
enum ShotContinuationOutcome: Sendable {
    case ready(takeId: String)
    case failed(message: String)

    var succeeded: Bool {
        if case .ready = self { return true }
        return false
    }
}

extension ProjectShot {
    var hasFrozenSourceSequence: Bool {
        !browsableRenderVersions.isEmpty
            || (branchedFromShotId.isEmpty && combinedSources.isEmpty && continuationRecords.contains { $0.selectedTake != nil })
    }

    var hasSavedPlayback: Bool {
        !browsableRenderVersions.isEmpty
            || continuationRecords.contains { $0.selectedTake?.segmentClip.map {
                FileManager.default.fileExists(atPath: $0.clipPath)
            } == true }
            || seedSegmentClips.contains { FileManager.default.fileExists(atPath: $0.clipPath) }
    }
}
