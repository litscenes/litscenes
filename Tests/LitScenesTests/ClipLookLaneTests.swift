import Foundation
import Testing
@testable import LitScenes

// The Clip Look concurrency lane's pure surface: the launch-time resume
// preflight (status rewrites + resumable buckets) and the version-log
// invariants the lane's same-entry parallelism leans on.

private func laneArtifact(
    versionId: String,
    versionNumber: Int = 1,
    status: String,
    provider: String = "fal",
    requestId: String = ""
) -> ShotRestyleArtifact {
    var artifact = ShotRestyleArtifact(
        versionId: versionId,
        versionNumber: versionNumber,
        status: status,
        sourceClipMediaId: "trim_1",
        sourceClipStartSeconds: 0,
        sourceClipEndSeconds: 4,
        generatedAt: "t\(versionNumber)"
    )
    artifact.provider = provider
    artifact.requestId = requestId
    return artifact
}

@Test func restyleResumePreflightRewritesOrphansAndBucketsRecoverables() throws {
    var shot = ProjectShot(shotId: "shot_1", name: "Test", createdAt: "t0", updatedAt: "t0")
    shot.lookVersions = [
        laneArtifact(versionId: "look_preparing", status: "preparing"),
        laneArtifact(versionId: "look_uploading_decart", status: "uploading", provider: "decart"),
        laneArtifact(versionId: "look_generating", status: "generating", requestId: "req_a"),
        laneArtifact(versionId: "look_ready", status: "ready")
    ]
    shot.clipLookVersions = [
        laneArtifact(versionId: "clip_preparing", status: "preparing"),
        laneArtifact(versionId: "clip_uploading_fal", status: "uploading"),
        laneArtifact(versionId: "clip_queued", status: "queued", requestId: "req_b"),
        laneArtifact(versionId: "clip_downloading", status: "downloading", requestId: "req_c"),
        laneArtifact(versionId: "clip_orphan", status: "generating"), // no request id
        laneArtifact(versionId: "clip_failed", status: "failed")
    ]
    var document = ProjectShotTimelineDocument.empty(projectId: "p1")
    document.shots = [shot]

    let preflight = restyleResumePreflight(document: document, now: "now")
    #expect(preflight.changed)

    let looks = Dictionary(uniqueKeysWithValues: preflight.document.shots[0].lookVersions.map { ($0.versionId, $0) })
    let clips = Dictionary(uniqueKeysWithValues: preflight.document.shots[0].clipLookVersions.map { ($0.versionId, $0) })

    // Orphans rewritten with honest copy; Decart uploading carries the spend warning.
    #expect(looks["look_preparing"]?.status == "failed")
    #expect(looks["look_preparing"]?.errorMessage == "Interrupted before provider submission; retry creates a new Look.")
    #expect(looks["look_uploading_decart"]?.status == "failed")
    #expect(looks["look_uploading_decart"]?.errorMessage.contains("Remote acceptance is unknown") == true)
    #expect(clips["clip_preparing"]?.status == "failed")
    #expect(clips["clip_preparing"]?.errorMessage == "Interrupted before provider submission; restyle again to create a new Clip Look.")
    #expect(clips["clip_uploading_fal"]?.status == "failed")
    #expect(clips["clip_uploading_fal"]?.errorMessage == "Interrupted before provider submission; restyle again to create a new Clip Look.")
    #expect(clips["clip_orphan"]?.status == "failed")
    #expect(clips["clip_orphan"]?.errorMessage == "Interrupted without a recoverable provider request id.")

    // Terminal statuses pass through untouched.
    #expect(looks["look_ready"]?.status == "ready")
    #expect(clips["clip_failed"]?.status == "failed")
    #expect(clips["clip_failed"]?.updatedAt != "now") // not stamped by the rewrite

    // Recoverables bucket by kind, in document order.
    #expect(preflight.shotLooks.map(\.artifact.versionId) == ["look_generating"])
    #expect(preflight.shotLooks.map(\.shotId) == ["shot_1"])
    #expect(preflight.clipLooks.map(\.artifact.versionId) == ["clip_queued", "clip_downloading"])
    #expect(preflight.clipLooks.allSatisfy { $0.shotId == "shot_1" })
}

@Test func restyleResumePreflightIsQuietWhenNothingIsInFlight() {
    var shot = ProjectShot(shotId: "shot_1", name: "Test", createdAt: "t0", updatedAt: "t0")
    shot.clipLookVersions = [
        laneArtifact(versionId: "clip_ready", status: "ready"),
        laneArtifact(versionId: "clip_paused", status: "paused", requestId: "req"),
        laneArtifact(versionId: "clip_canceled", status: "canceled")
    ]
    var document = ProjectShotTimelineDocument.empty(projectId: "p1")
    document.shots = [shot]

    let preflight = restyleResumePreflight(document: document, now: "now")
    #expect(!preflight.changed)
    #expect(preflight.shotLooks.isEmpty)
    // "paused" is a deliberate operator stop (Decart keeps processing) — the
    // Inspector's Resume button owns it, not the launch reconcile.
    #expect(preflight.clipLooks.isEmpty)
    #expect(preflight.document == document)
}

/// Same-entry parallelism appends versions concurrently; the durable log must
/// keep them distinct and ordered no matter the completion order.
@Test func clipLookVersionLogKeepsConcurrentAppendsDistinctAndOrdered() {
    var shot = ProjectShot(shotId: "shot_1", name: "Test", createdAt: "t0", updatedAt: "t0")
    // Three lane tasks allocated 1/2/3 on the main actor; they finish and
    // re-upsert out of order.
    shot = shot.upsertingClipLookVersion(laneArtifact(versionId: "v1", versionNumber: 1, status: "queued"), now: "t1")
    shot = shot.upsertingClipLookVersion(laneArtifact(versionId: "v2", versionNumber: 2, status: "queued"), now: "t1")
    shot = shot.upsertingClipLookVersion(laneArtifact(versionId: "v3", versionNumber: 3, status: "queued"), now: "t1")
    var v3Ready = laneArtifact(versionId: "v3", versionNumber: 3, status: "ready")
    v3Ready.videoPath = "/tmp/v3.mp4"
    shot = shot.upsertingClipLookVersion(v3Ready, now: "t2")
    var v1Ready = laneArtifact(versionId: "v1", versionNumber: 1, status: "ready")
    v1Ready.videoPath = "/tmp/v1.mp4"
    shot = shot.upsertingClipLookVersion(v1Ready, now: "t3")

    #expect(shot.clipLookVersions.map(\.versionId) == ["v1", "v2", "v3"])
    #expect(shot.clipLookVersions.map(\.versionNumber) == [1, 2, 3])
    #expect(shot.clipLookVersions.map(\.status) == ["ready", "queued", "ready"])
    // The engine's max+1 allocation over this log yields a fresh number.
    #expect((shot.clipLookVersions.map(\.versionNumber).max() ?? 0) + 1 == 4)
    // Never activates anything — Clip Looks are tray-only.
    #expect(shot.activeLookVersionId.isEmpty)
}
