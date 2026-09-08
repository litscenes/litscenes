import CryptoKit
import Foundation

/// Additive take provenance. Legacy anchors decode without evidence and are
/// re-extracted for a new review; their historical input images stay intact.
struct ShotVideoEndpointEvidence: Codable, Hashable, Sendable {
    var revision: Int
    var sourceFingerprint: String
    var sourceStartSeconds: Double
    var sourceEndSeconds: Double?
    var requestedSeconds: Double
    var actualSeconds: Double
    var frameFingerprint: String
}

enum ShotVideoEndpoint {
    static let revision = 1

    struct Prepared: Sendable {
        var frameURL: URL
        var evidence: ShotVideoEndpointEvidence
    }

    static func fingerprint(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func prepare(
        videoURL: URL, startSeconds: Double = 0, endSeconds: Double? = nil,
        cacheDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("litscenes_video_endpoints", isDirectory: true)
    ) async throws -> Prepared {
        try Task.checkCancellation()
        let sourceFingerprint = try fingerprint(videoURL)
        let key = sha256Hex(Data("\(revision)|\(sourceFingerprint)|\(startSeconds)|\(endSeconds.map(String.init(describing:)) ?? "end")".utf8))
        let frameURL = cacheDirectory.appendingPathComponent("\(key).png")
        let proofURL = cacheDirectory.appendingPathComponent("\(key).json")
        if let data = try? Data(contentsOf: proofURL),
           let proof = try? JSONDecoder().decode(ShotVideoEndpointEvidence.self, from: data),
           proof.revision == revision, proof.sourceFingerprint == sourceFingerprint,
           proof.sourceStartSeconds == startSeconds, proof.sourceEndSeconds == endSeconds,
           proof.requestedSeconds.isFinite, proof.actualSeconds.isFinite,
           let digest = try? fingerprint(frameURL), digest == proof.frameFingerprint {
            try Task.checkCancellation()
            return Prepared(frameURL: frameURL, evidence: proof)
        }
        try ensureDirectory(cacheDirectory)
        // Unique extraction destinations keep concurrent reviews from replacing
        // an image while another caller verifies its digest.
        let temporary = cacheDirectory.appendingPathComponent("\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let frame = try await VideoChainMedia.extractVideoEndpoint(videoURL: videoURL,
            outputURL: temporary, startSeconds: startSeconds, endSeconds: endSeconds)
        guard try fingerprint(videoURL) == sourceFingerprint else {
            throw ScreenGraphError.capture("The continuation source changed during preparation. Reopen the review.")
        }
        let proof = ShotVideoEndpointEvidence(revision: revision, sourceFingerprint: sourceFingerprint,
            sourceStartSeconds: startSeconds, sourceEndSeconds: endSeconds,
            requestedSeconds: frame.requestedSeconds, actualSeconds: frame.actualSeconds,
            frameFingerprint: try fingerprint(temporary))
        try Task.checkCancellation()
        try Data(contentsOf: temporary).write(to: frameURL, options: .atomic)
        try JSONEncoder().encode(proof).write(to: proofURL, options: .atomic)
        return Prepared(frameURL: frameURL, evidence: proof)
    }

    /// Confirmation verifies the still that was displayed as well as its source.
    /// It may refresh derived cache evidence, but cannot silently change inputs.
    static func validateReviewed(_ reviewed: ShotContinuationAnchor, prepared: ShotContinuationAnchor) throws {
        guard !reviewed.frameFingerprint.isEmpty,
              try fingerprint(URL(fileURLWithPath: reviewed.framePath)) == reviewed.frameFingerprint,
              prepared.frameFingerprint == reviewed.frameFingerprint else {
            throw ScreenGraphError.capture("The continuation frame changed. Reopen the review before rendering.")
        }
        if !prepared.tailClipPath.isEmpty {
            guard let previous = reviewed.endpointEvidence,
                  previous == prepared.endpointEvidence else {
                throw ScreenGraphError.capture("The continuation video changed or needs its endpoint verified. Reopen the review before rendering.")
            }
        }
    }
}
