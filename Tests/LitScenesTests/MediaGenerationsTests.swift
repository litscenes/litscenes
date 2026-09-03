import Foundation
import Testing
@testable import LitScenes

// The media-viewer generation laws: tolerant persistence outside the shot
// timeline, honest relaunch preflight (motion has NO paid resume), rescan
// survival for the new derivative kinds, and the pure plan/model helpers the
// popovers pin their behavior on.

private func mediaGenTestItem(
    _ mediaId: String,
    kind: MediaKind,
    derivativeKind: String? = nil,
    sourceMediaId: String? = nil
) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: mediaId,
        sourceId: MediaItemRecord.generatedMediaSourceId,
        kind: kind,
        filename: "\(mediaId).\(kind == .image ? "png" : "mp4")",
        path: "/tmp/\(mediaId)",
        relativePath: mediaId,
        byteCount: 1,
        modifiedAt: "",
        width: 100,
        height: 100,
        durationSeconds: kind == .video ? 4 : nil,
        nominalFrameRate: nil,
        thumbnailPath: "",
        videoStripPath: nil,
        scannedAt: "",
        scanError: nil,
        derivativeKind: derivativeKind,
        sourceMediaId: sourceMediaId
    )
}

// MARK: - Tolerant decode

@Test func mediaMotionJobAndDocumentDecodeTolerantly() throws {
    // Empty payloads decode to defaults — an absent document is an empty one.
    let bareJob = try JSONDecoder().decode(MediaMotionJob.self, from: Data("{}".utf8))
    #expect(bareJob.jobId.isEmpty)
    #expect(bareJob.status.isEmpty)
    #expect(!bareJob.isActive)

    let bareDocument = try JSONDecoder().decode(
        ProjectMediaGenerationsDocument.self,
        from: Data("{}".utf8)
    )
    #expect(bareDocument.lookVersions.isEmpty)
    #expect(bareDocument.motionJobs.isEmpty)

    // Future fields never refuse the row.
    let future = try JSONDecoder().decode(
        MediaMotionJob.self,
        from: Data(#"{"jobId": "m1", "status": "generating", "futureField": {"deep": true}}"#.utf8)
    )
    #expect(future.jobId == "m1")
    #expect(future.isActive)

    // Round trip keeps both collections.
    var document = ProjectMediaGenerationsDocument(projectId: "p1")
    document = document.upsertingLookVersion(
        ShotRestyleArtifact(versionId: "look_1", versionNumber: 1, status: "ready", sourceClipMediaId: "vid_1"),
        now: "t1"
    )
    document = document.upsertingMotionJob(
        MediaMotionJob(jobId: "m1", status: "ready", sourceMediaId: "img_1"),
        now: "t2"
    )
    let decoded = try JSONDecoder().decode(
        ProjectMediaGenerationsDocument.self,
        from: JSONEncoder().encode(document)
    )
    #expect(decoded.lookVersions.count == 1)
    #expect(decoded.motionJobs.count == 1)
    #expect(decoded.projectId == "p1")
}

@Test func mediaGenerationsUpsertsReplaceByIdAndNormalizedDropsEmptyIds() {
    var document = ProjectMediaGenerationsDocument(projectId: "p1")
    document = document.upsertingMotionJob(MediaMotionJob(jobId: "m1", status: "preparing"), now: "t1")
    document = document.upsertingMotionJob(MediaMotionJob(jobId: "m1", status: "ready"), now: "t2")
    #expect(document.motionJobs.count == 1)
    #expect(document.motionJobs[0].status == "ready")

    document.motionJobs.append(MediaMotionJob())
    document.lookVersions.append(ShotRestyleArtifact())
    let normalized = document.normalized()
    #expect(normalized.motionJobs.count == 1)
    #expect(normalized.lookVersions.isEmpty)
}

// MARK: - Relaunch preflight

@Test func mediaGenerationsPreflightRewritesInterruptedWorkHonestly() {
    var document = ProjectMediaGenerationsDocument(projectId: "p1")
    // A look interrupted before submission: failed, retry copy.
    document.lookVersions.append(ShotRestyleArtifact(versionId: "look_prep", status: "preparing"))
    // A look mid-generation WITH a request id: recoverable.
    var recoverable = ShotRestyleArtifact(versionId: "look_gen", status: "generating")
    recoverable.requestId = "req_1"
    document.lookVersions.append(recoverable)
    // A look mid-generation WITHOUT a request id: failed.
    document.lookVersions.append(ShotRestyleArtifact(versionId: "look_lost", status: "generating"))
    // Motion jobs: NEVER recoverable — no re-attach surface.
    var submitted = MediaMotionJob(jobId: "m_submitted", status: "generating")
    submitted.requestId = "req_2"
    document.motionJobs.append(submitted)
    document.motionJobs.append(MediaMotionJob(jobId: "m_prep", status: "preparing"))
    document.motionJobs.append(MediaMotionJob(jobId: "m_done", status: "ready"))

    let result = mediaGenerationsResumePreflight(document: document, now: "t9")
    #expect(result.changed)
    #expect(result.resumableLooks.map(\.versionId) == ["look_gen"])

    let looksById = Dictionary(result.document.lookVersions.map { ($0.versionId, $0) }, uniquingKeysWith: { a, _ in a })
    #expect(looksById["look_prep"]?.status == "failed")
    #expect(looksById["look_gen"]?.status == "generating")
    #expect(looksById["look_lost"]?.status == "failed")

    let jobsById = Dictionary(result.document.motionJobs.map { ($0.jobId, $0) }, uniquingKeysWith: { a, _ in a })
    #expect(jobsById["m_submitted"]?.status == "failed")
    // The billed-job warning names the duplicate-spend risk.
    #expect(jobsById["m_submitted"]?.errorMessage.contains("billed") == true)
    #expect(jobsById["m_submitted"]?.requestId == "req_2")
    #expect(jobsById["m_prep"]?.status == "failed")
    #expect(jobsById["m_prep"]?.errorMessage.contains("billed") == false)
    #expect(jobsById["m_done"]?.status == "ready")
}

// MARK: - Rescan survival + tray placement

@Test func newDerivativeKindsSurviveRescanPreservation() {
    let restyle = mediaGenTestItem("r1", kind: .image, derivativeKind: MediaItemRecord.mediaRestyleDerivativeKind, sourceMediaId: "img_1")
    let motion = mediaGenTestItem("m1", kind: .video, derivativeKind: MediaItemRecord.mediaMotionDerivativeKind, sourceMediaId: "img_1")
    #expect(restyle.isGeneratedMedia)
    #expect(motion.isGeneratedMedia)
    // Neither is a trim/clip-look: they keep their own tray identity.
    #expect(!motion.isVideoTrim)
    #expect(!motion.isClipLookMedia)
}

@Test func mediaMotionStaysTopLevelInVideoTray() {
    // Its source is an IMAGE, absent from the video tray — the motion clip
    // must form its own visible top-level group, never orphan or nest.
    let motion = mediaGenTestItem("m1", kind: .video, derivativeKind: MediaItemRecord.mediaMotionDerivativeKind, sourceMediaId: "img_1")
    let plainVideo = mediaGenTestItem("v1", kind: .video)
    let layout = videoTrayLayout(videos: [plainVideo, motion], isRejected: { _ in false })
    let groupIds = layout.visibleGroups.map(\.id)
    #expect(groupIds.contains("m1"))
    #expect(groupIds.contains("v1"))
    #expect(layout.visibleGroups.allSatisfy { $0.trims.isEmpty && $0.looks.isEmpty })
}

// MARK: - Pure popover laws

@Test func mediaMotionSelectableModelsExcludeNarrationDriven() {
    let models = mediaMotionSelectableModels()
    #expect(!models.contains(.falLTX23Narration))
    #expect(models.contains(.wan27))
    // Every offered model can start from a single frame.
    #expect(models.allSatisfy { $0 != .falLTX23Narration })
    #expect(mediaMotionDefaultPrompt().contains("motion"))
}
