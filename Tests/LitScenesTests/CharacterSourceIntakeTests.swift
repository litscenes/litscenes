import Foundation
import Testing
@testable import LitScenes

private func intakeItem(_ id: String, sha: String = "", byteCount: Int64 = 100, path: String? = nil, kind: MediaKind = .image) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: id, sourceId: "src", kind: kind, filename: "\(id).jpg", path: path ?? "/tmp/\(id).jpg",
        relativePath: "\(id).jpg", byteCount: byteCount, modifiedAt: "", width: 10, height: 10,
        thumbnailPath: "", scannedAt: "", contentSha256: sha
    )
}

@Suite("Character source intake law")
struct CharacterSourceIntakeTests {
    @Test("The same bytes are reused; same-size legacy rows are hashed first; new bytes are copied")
    func planLaw() {
        let items = [
            intakeItem("hashed", sha: "abc", byteCount: 100),
            intakeItem("legacy_same_size", byteCount: 100),
            intakeItem("legacy_other_size", byteCount: 200),
            intakeItem("video_same_size", byteCount: 100, kind: .video),
            intakeItem("pathless", byteCount: 100, path: ""),
        ]
        #expect(CharacterSourceIntake.plan(sha256: "abc", byteCount: 100, items: items) == .reuse(mediaId: "hashed"))
        #expect(CharacterSourceIntake.plan(sha256: "zzz", byteCount: 100, items: items) == .hashCandidates(["legacy_same_size"]))
        #expect(CharacterSourceIntake.plan(sha256: "zzz", byteCount: 300, items: items) == .copy)
        #expect(CharacterSourceIntake.plan(sha256: "", byteCount: 100, items: items) == .copy)
        let many = (0..<20).map { intakeItem("legacy_\($0)", byteCount: 50) }
        if case .hashCandidates(let ids) = CharacterSourceIntake.plan(sha256: "q", byteCount: 50, items: many) {
            #expect(ids.count == CharacterSourceIntake.hashCandidateLimit)
        } else {
            Issue.record("expected candidates")
        }
    }

    @Test("Source media ids are stable and project-scoped")
    func mediaIdLaw() {
        let a = CharacterSourceIntake.mediaId(projectId: "p1", sha256: "abc")
        #expect(a == CharacterSourceIntake.mediaId(projectId: "p1", sha256: "abc"))
        #expect(a != CharacterSourceIntake.mediaId(projectId: "p2", sha256: "abc"))
        #expect(a.hasPrefix("charsrc_"))
    }

    @Test("Analysis state and the drain decision")
    func analysisStateAndDrain() {
        #expect(CharacterSourceIntake.analysisState(hasCurrentObservation: true, isQueued: true, isAnalyzing: true, hasCredential: false) == .analyzed)
        #expect(CharacterSourceIntake.analysisState(hasCurrentObservation: false, isQueued: true, isAnalyzing: true, hasCredential: true) == .analyzing)
        #expect(CharacterSourceIntake.analysisState(hasCurrentObservation: false, isQueued: true, isAnalyzing: false, hasCredential: true) == .queued)
        #expect(CharacterSourceIntake.analysisState(hasCurrentObservation: false, isQueued: true, isAnalyzing: false, hasCredential: false) == .unavailable)
        #expect(CharacterSourceIntake.analysisState(hasCurrentObservation: false, isQueued: false, isAnalyzing: false, hasCredential: true) == .pending)
        #expect(CharacterSourceAnalysisState.unavailable.label.contains("OpenAI key"))

        #expect(CharacterSourceIntake.drainDecision(queued: ["a", "b", "a"], isAnalyzingMedia: false, isScanning: false, hasCredential: true) == ["a", "b"])
        #expect(CharacterSourceIntake.drainDecision(queued: ["a"], isAnalyzingMedia: true, isScanning: false, hasCredential: true).isEmpty)
        #expect(CharacterSourceIntake.drainDecision(queued: ["a"], isAnalyzingMedia: false, isScanning: true, hasCredential: true).isEmpty)
        #expect(CharacterSourceIntake.drainDecision(queued: ["a"], isAnalyzingMedia: false, isScanning: false, hasCredential: false).isEmpty)
        #expect(CharacterSourceIntake.drainDecision(queued: [], isAnalyzingMedia: false, isScanning: false, hasCredential: true).isEmpty)
    }

    @Test("Intake status says what was added and what was reused")
    func intakeStatus() {
        #expect(CharacterSourceIntake.intakeStatus(added: 2, reused: 0) == "Added 2 source images")
        #expect(CharacterSourceIntake.intakeStatus(added: 1, reused: 1) == "Added 1 source image · reused 1 already in media")
        #expect(CharacterSourceIntake.intakeStatus(added: 0, reused: 1) == "Already in media — reused 1 image")
        #expect(CharacterSourceIntake.intakeStatus(added: 0, reused: 0) == "No image sources added")
    }
}
