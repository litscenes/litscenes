import Foundation

/// THE SOURCE INTAKE LAW, extracted pure: a character source is project-owned bytes
/// identified by content. The same bytes already in the inventory are reused; legacy
/// rows without a hash but with the same size are hashed lazily before a copy; only
/// new bytes are copied in. Analysis follows automatically and never blocks.
enum CharacterSourceIntakePlan: Equatable, Sendable {
    /// An inventory item carries this exact content hash.
    case reuse(mediaId: String)
    /// Legacy rows of the same size whose files must be hashed before deciding.
    case hashCandidates([String])
    /// New bytes: copy into the project.
    case copy
}

enum CharacterSourceAnalysisState: Equatable, Sendable {
    case analyzed
    case analyzing
    case queued
    /// No OpenAI key: analysis waits until one is added.
    case unavailable
    /// Not analyzed and not queued (a legacy source before its first visit).
    case pending

    var label: String {
        switch self {
        case .analyzed: return "Analyzed"
        case .analyzing: return "Analyzing…"
        case .queued: return "Queued for analysis"
        case .unavailable: return "Add an OpenAI key in App Settings to analyze"
        case .pending: return "Not analyzed yet"
        }
    }
}

enum CharacterSourceIntake {
    /// How many same-size legacy rows an import hashes before giving up on reuse.
    static let hashCandidateLimit = 8

    static func plan(sha256: String, byteCount: Int, items: [MediaItemRecord]) -> CharacterSourceIntakePlan {
        let sha = sha256.trimmed
        guard !sha.isEmpty else { return .copy }
        if let match = items.first(where: { $0.kind == .image && $0.contentSha256 == sha }) {
            return .reuse(mediaId: match.mediaId)
        }
        let candidates = items
            .filter { $0.kind == .image && $0.contentSha256.isEmpty && Int($0.byteCount) == byteCount && !$0.path.isEmpty }
            .prefix(hashCandidateLimit)
            .map(\.mediaId)
        return candidates.isEmpty ? .copy : .hashCandidates(Array(candidates))
    }

    /// Project-scoped, content-derived: the same photo added twice is one record.
    static func mediaId(projectId: String, sha256: String) -> String {
        "charsrc_\(shortHash("\(projectId):\(sha256)", length: 20))"
    }

    static func analysisState(
        hasCurrentObservation: Bool,
        isQueued: Bool,
        isAnalyzing: Bool,
        hasCredential: Bool
    ) -> CharacterSourceAnalysisState {
        if hasCurrentObservation { return .analyzed }
        if isAnalyzing { return .analyzing }
        if !hasCredential { return .unavailable }
        return isQueued ? .queued : .pending
    }

    /// Which queued ids run now: all of them, in one pass, when nothing else runs
    /// and a key exists; none otherwise (they stay queued).
    static func drainDecision(
        queued: [String],
        isAnalyzingMedia: Bool,
        isScanning: Bool,
        hasCredential: Bool
    ) -> [String] {
        guard !queued.isEmpty, !isAnalyzingMedia, !isScanning, hasCredential else { return [] }
        return uniqueNonEmpty(queued)
    }

    static func intakeStatus(added: Int, reused: Int) -> String {
        var parts: [String] = []
        if added > 0 { parts.append("Added \(added) source image\(added == 1 ? "" : "s")") }
        if reused > 0 { parts.append(added > 0 ? "reused \(reused) already in media" : "Already in media — reused \(reused) image\(reused == 1 ? "" : "s")") }
        return parts.isEmpty ? "No image sources added" : parts.joined(separator: " · ")
    }
}
