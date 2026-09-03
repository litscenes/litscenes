import Foundation

/// One image-to-video render job started from the media viewer ("Start
/// Video"): no shot, no lens — a standalone provider call whose output lands
/// as a top-level `media_motion` tray asset. The job row is the honest log:
/// spend, request id, and failure copy survive a relaunch even though this
/// lane has no paid resume (`generateClip` is a one-shot await with no
/// re-attach surface).
struct MediaMotionJob: Codable, Hashable, Identifiable, Sendable {
    var jobId: String = ""
    var status: String = "" // preparing | submitting | generating | downloading | ready | failed | canceled
    var sourceMediaId: String = ""
    var model: String = ""
    var durationSeconds: Int = 0
    var prompt: String = ""
    var generateAudio: Bool = false
    var requestId: String = ""
    var traceId: String = ""
    var pricingNote: String = ""
    var outputMediaId: String = ""
    var errorMessage: String = ""
    var generatedAt: String = ""
    var updatedAt: String = ""

    var id: String { jobId }
    var isActive: Bool {
        ["preparing", "submitting", "generating", "downloading"].contains(status)
    }

    private enum CodingKeys: String, CodingKey {
        case jobId, status, sourceMediaId, model, durationSeconds, prompt
        case generateAudio, requestId, traceId, pricingNote, outputMediaId
        case errorMessage, generatedAt, updatedAt
    }

    init(
        jobId: String = "",
        status: String = "",
        sourceMediaId: String = "",
        model: String = "",
        durationSeconds: Int = 0,
        prompt: String = "",
        generateAudio: Bool = false,
        requestId: String = "",
        traceId: String = "",
        pricingNote: String = "",
        outputMediaId: String = "",
        errorMessage: String = "",
        generatedAt: String = "",
        updatedAt: String = ""
    ) {
        self.jobId = jobId
        self.status = status
        self.sourceMediaId = sourceMediaId
        self.model = model
        self.durationSeconds = durationSeconds
        self.prompt = prompt
        self.generateAudio = generateAudio
        self.requestId = requestId
        self.traceId = traceId
        self.pricingNote = pricingNote
        self.outputMediaId = outputMediaId
        self.errorMessage = errorMessage
        self.generatedAt = generatedAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = ((try? container.decodeIfPresent(String.self, forKey: .jobId)) ?? nil) ?? ""
        status = ((try? container.decodeIfPresent(String.self, forKey: .status)) ?? nil) ?? ""
        sourceMediaId = ((try? container.decodeIfPresent(String.self, forKey: .sourceMediaId)) ?? nil) ?? ""
        model = ((try? container.decodeIfPresent(String.self, forKey: .model)) ?? nil) ?? ""
        durationSeconds = ((try? container.decodeIfPresent(Int.self, forKey: .durationSeconds)) ?? nil) ?? 0
        prompt = ((try? container.decodeIfPresent(String.self, forKey: .prompt)) ?? nil) ?? ""
        generateAudio = ((try? container.decodeIfPresent(Bool.self, forKey: .generateAudio)) ?? nil) ?? false
        requestId = ((try? container.decodeIfPresent(String.self, forKey: .requestId)) ?? nil) ?? ""
        traceId = ((try? container.decodeIfPresent(String.self, forKey: .traceId)) ?? nil) ?? ""
        pricingNote = ((try? container.decodeIfPresent(String.self, forKey: .pricingNote)) ?? nil) ?? ""
        outputMediaId = ((try? container.decodeIfPresent(String.self, forKey: .outputMediaId)) ?? nil) ?? ""
        errorMessage = ((try? container.decodeIfPresent(String.self, forKey: .errorMessage)) ?? nil) ?? ""
        generatedAt = ((try? container.decodeIfPresent(String.self, forKey: .generatedAt)) ?? nil) ?? ""
        updatedAt = ((try? container.decodeIfPresent(String.self, forKey: .updatedAt)) ?? nil) ?? ""
    }
}

/// The viewer Start-Video default motion prompt — the same open-ended
/// sentence `shotSegmentPrompt(pair:)` uses for a single-keyframe segment,
/// stated here because the viewer has no frame pair to derive it from.
func mediaMotionDefaultPrompt() -> String {
    "Bring this scene to life with gentle, continuous motion true to what is depicted."
}

/// The Start-Video model list: every selectable shot model EXCEPT the
/// narration-driven one, which needs an authored audio driver no raw media
/// image can supply.
func mediaMotionSelectableModels() -> [ShotRenderModel] {
    ShotRenderModel.shotDefaultCases.filter { $0 != .falLTX23Narration }
}

/// Media-viewer generations that need a durable home OUTSIDE the shot
/// timeline: whole-asset looks of raw tray videos (`ShotRestyleArtifact`
/// reused verbatim — `sourceClipMediaId` carries identity, `sourceShotId`
/// stays empty) and image-to-video motion jobs. Tolerant decode, no
/// migrations — an absent document is an empty one.
struct ProjectMediaGenerationsDocument: Codable, Hashable, Sendable {
    static let schemaVersion = "litscenes.media_generations.v0.1"
    static let documentType = "project_media_generations"

    var schemaVersion: String = ProjectMediaGenerationsDocument.schemaVersion
    var projectId: String = ""
    var lookVersions: [ShotRestyleArtifact] = []
    var motionJobs: [MediaMotionJob] = []
    var updatedAt: String = ""

    static func empty(projectId: String) -> ProjectMediaGenerationsDocument {
        ProjectMediaGenerationsDocument(projectId: projectId)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectId
        case lookVersions
        case motionJobs
        case updatedAt
    }

    init(
        schemaVersion: String = ProjectMediaGenerationsDocument.schemaVersion,
        projectId: String = "",
        lookVersions: [ShotRestyleArtifact] = [],
        motionJobs: [MediaMotionJob] = [],
        updatedAt: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.projectId = projectId
        self.lookVersions = lookVersions
        self.motionJobs = motionJobs
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = ((try? container.decodeIfPresent(String.self, forKey: .schemaVersion)) ?? nil) ?? Self.schemaVersion
        projectId = ((try? container.decodeIfPresent(String.self, forKey: .projectId)) ?? nil) ?? ""
        lookVersions = ((try? container.decodeIfPresent([ShotRestyleArtifact].self, forKey: .lookVersions)) ?? nil) ?? []
        motionJobs = ((try? container.decodeIfPresent([MediaMotionJob].self, forKey: .motionJobs)) ?? nil) ?? []
        updatedAt = ((try? container.decodeIfPresent(String.self, forKey: .updatedAt)) ?? nil) ?? ""
    }

    func normalized() -> ProjectMediaGenerationsDocument {
        var value = self
        value.lookVersions = value.lookVersions.filter { !$0.versionId.isEmpty }
        value.motionJobs = value.motionJobs.filter { !$0.jobId.isEmpty }
        return value
    }

    // MARK: Pure mutations

    func upsertingLookVersion(_ artifact: ShotRestyleArtifact, now: String) -> ProjectMediaGenerationsDocument {
        var value = self
        if let index = value.lookVersions.firstIndex(where: { $0.versionId == artifact.versionId }) {
            value.lookVersions[index] = artifact
        } else {
            value.lookVersions.append(artifact)
        }
        value.updatedAt = now
        return value
    }

    func upsertingMotionJob(_ job: MediaMotionJob, now: String) -> ProjectMediaGenerationsDocument {
        var value = self
        if let index = value.motionJobs.firstIndex(where: { $0.jobId == job.jobId }) {
            value.motionJobs[index] = job
        } else {
            value.motionJobs.append(job)
        }
        value.updatedAt = now
        return value
    }
}

/// Relaunch preflight for the media-generations document, mirroring
/// `restyleResumePreflight`'s honesty rules: work interrupted before its
/// provider request id was saved is FAILED with copy that says so; queued or
/// generating looks WITH a request id are recoverable (the clip-look resume
/// pump re-attaches); motion jobs are never recoverable — `generateClip` has
/// no re-attach surface — so an interrupted one fails with a duplicate-spend
/// warning while keeping its request id for a future resume lane.
func mediaGenerationsResumePreflight(
    document: ProjectMediaGenerationsDocument,
    now: String
) -> (
    document: ProjectMediaGenerationsDocument,
    changed: Bool,
    resumableLooks: [ShotRestyleArtifact]
) {
    var document = document
    var resumableLooks: [ShotRestyleArtifact] = []
    var changed = false
    for index in document.lookVersions.indices {
        var look = document.lookVersions[index]
        switch look.status {
        case "preparing":
            look.status = "failed"
            look.errorMessage = "Interrupted before provider submission; restyle again to create a new Look."
            look.updatedAt = now
            document.lookVersions[index] = look
            changed = true
        case "uploading":
            look.status = "failed"
            look.errorMessage = look.restyleProvider == .decart
                ? "Decart submission was interrupted before its job id was saved. Remote acceptance is unknown; check Decart before retrying to avoid duplicate spend."
                : "Interrupted before provider submission; restyle again to create a new Look."
            look.updatedAt = now
            document.lookVersions[index] = look
            changed = true
        case "queued", "generating", "downloading":
            if look.requestId.isEmpty {
                look.status = "failed"
                look.errorMessage = "Interrupted without a recoverable provider request id."
                look.updatedAt = now
                document.lookVersions[index] = look
                changed = true
            } else {
                resumableLooks.append(look)
            }
        default:
            break
        }
    }
    for index in document.motionJobs.indices {
        var job = document.motionJobs[index]
        guard job.isActive else { continue }
        job.status = "failed"
        job.errorMessage = job.requestId.isEmpty
            ? "Interrupted before provider submission; start the video again."
            : "Interrupted mid-render. The provider job may have completed and billed at FAL — check before retrying to avoid duplicate spend."
        job.updatedAt = now
        document.motionJobs[index] = job
        changed = true
    }
    return (document, changed, resumableLooks)
}
