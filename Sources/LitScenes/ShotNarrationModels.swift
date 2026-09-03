import Foundation

// MARK: - Shot narration (persisted per shot)

/// The persisted record of a shot's narration. The spoken text (`script`) is
/// the meaning-message title followed by its LLM-drafted body (or the user's
/// edited version of the whole); `bodyText` records the body component last
/// drafted (provenance, never a display source), and every voiced script lands
/// in `titleVersions` (latest last — no browser yet).
struct ShotNarrationArtifact: Codable, Hashable, Sendable {
    var provider: String = "elevenlabs_tts"
    var model: String = ElevenLabsSpeechModels.defaultModelId
    var status: String = ""          // "generating" | "ready" | "failed"
    var messagingText: String = ""
    /// Active audio consumed by the narration strip, Shot player, and export.
    var audioPath: String = ""
    /// Original ElevenLabs response. Local speed changes always derive from this
    /// path so repeated edits never compound.
    var sourceAudioPath: String = ""
    var script: String = ""
    var bodyText: String = ""
    var titleVersions: [String] = []
    var voicePresetId: String = ""
    var voiceName: String = ""
    var voiceId: String = ""
    var durationSeconds: Double = 0
    var sourceDurationSeconds: Double = 0
    var voiceSpeed: Double = StoryAudioVoiceCatalog.defaultSpeed
    var audioProcessor: String = ""
    var scriptResponseId: String = ""
    var requestId: String = ""
    var traceId: String = ""
    var errorMessage: String = ""
    var generatedAt: String = ""
    var updatedAt: String = DateFormats.now()

    var isReady: Bool {
        status == "ready" && !audioPath.isEmpty
    }

    var effectiveVoiceSpeed: Double {
        StoryAudioVoiceCatalog.clampedSpeed(voiceSpeed)
    }

    var effectiveSourceAudioPath: String {
        sourceAudioPath.trimmed.nilIfEmpty ?? audioPath.trimmed
    }

    var effectiveSourceDurationSeconds: Double {
        if sourceDurationSeconds > 0 {
            return sourceDurationSeconds
        }
        return durationSeconds * effectiveVoiceSpeed
    }

    func duration(at speed: Double) -> Double {
        effectiveSourceDurationSeconds / max(StoryAudioVoiceCatalog.clampedSpeed(speed), 0.01)
    }

    func normalized() -> ShotNarrationArtifact {
        var value = self
        value.provider = value.provider.trimmed.isEmpty ? "elevenlabs_tts" : value.provider.trimmed.lowercased()
        value.model = value.model.trimmed.isEmpty ? ElevenLabsSpeechModels.defaultModelId : value.model.trimmed
        value.status = value.status.trimmed
        value.messagingText = value.messagingText.trimmed
        value.audioPath = value.audioPath.trimmed
        value.sourceAudioPath = value.sourceAudioPath.trimmed
        value.script = value.script.trimmed
        value.bodyText = value.bodyText.trimmed
        value.titleVersions = value.titleVersions.map { $0.trimmed }.filter { !$0.isEmpty }
        value.voicePresetId = value.voicePresetId.trimmed
        value.voiceName = value.voiceName.trimmed
        value.voiceId = value.voiceId.trimmed
        value.durationSeconds = max(0, value.durationSeconds)
        value.sourceDurationSeconds = max(0, value.sourceDurationSeconds)
        value.voiceSpeed = StoryAudioVoiceCatalog.clampedSpeed(value.voiceSpeed)
        value.audioProcessor = value.audioProcessor.trimmed
        value.scriptResponseId = value.scriptResponseId.trimmed
        value.requestId = value.requestId.trimmed
        value.traceId = value.traceId.trimmed
        value.errorMessage = value.errorMessage.trimmed
        value.generatedAt = value.generatedAt.trimmed
        value.updatedAt = value.updatedAt.trimmed
        return value
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case model
        case status
        case messagingText
        case audioPath
        case sourceAudioPath
        case script
        case bodyText
        case titleVersions
        case voicePresetId
        case voiceName
        case voiceId
        case durationSeconds
        case sourceDurationSeconds
        case voiceSpeed
        case audioProcessor
        case scriptResponseId
        case requestId
        case traceId
        case errorMessage
        case generatedAt
        case updatedAt
    }

    init(
        provider: String = "elevenlabs_tts",
        model: String = ElevenLabsSpeechModels.defaultModelId,
        status: String = "",
        messagingText: String = "",
        audioPath: String = "",
        sourceAudioPath: String = "",
        script: String = "",
        bodyText: String = "",
        titleVersions: [String] = [],
        voicePresetId: String = "",
        voiceName: String = "",
        voiceId: String = "",
        durationSeconds: Double = 0,
        sourceDurationSeconds: Double = 0,
        voiceSpeed: Double = StoryAudioVoiceCatalog.defaultSpeed,
        audioProcessor: String = "",
        scriptResponseId: String = "",
        requestId: String = "",
        traceId: String = "",
        errorMessage: String = "",
        generatedAt: String = "",
        updatedAt: String = DateFormats.now()
    ) {
        self.provider = provider
        self.model = model
        self.status = status
        self.messagingText = messagingText
        self.audioPath = audioPath
        self.sourceAudioPath = sourceAudioPath
        self.script = script
        self.bodyText = bodyText
        self.titleVersions = titleVersions
        self.voicePresetId = voicePresetId
        self.voiceName = voiceName
        self.voiceId = voiceId
        self.durationSeconds = durationSeconds
        self.sourceDurationSeconds = sourceDurationSeconds
        self.voiceSpeed = voiceSpeed
        self.audioProcessor = audioProcessor
        self.scriptResponseId = scriptResponseId
        self.requestId = requestId
        self.traceId = traceId
        self.errorMessage = errorMessage
        self.generatedAt = generatedAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "elevenlabs_tts"
        model = try container.decodeIfPresent(String.self, forKey: .model)
            ?? ElevenLabsSpeechModels.legacyMissingModelId
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        messagingText = try container.decodeIfPresent(String.self, forKey: .messagingText) ?? ""
        audioPath = try container.decodeIfPresent(String.self, forKey: .audioPath) ?? ""
        sourceAudioPath = try container.decodeIfPresent(String.self, forKey: .sourceAudioPath) ?? ""
        script = try container.decodeIfPresent(String.self, forKey: .script) ?? ""
        bodyText = try container.decodeIfPresent(String.self, forKey: .bodyText) ?? ""
        titleVersions = try container.decodeIfPresent([String].self, forKey: .titleVersions) ?? []
        voicePresetId = try container.decodeIfPresent(String.self, forKey: .voicePresetId) ?? ""
        voiceName = try container.decodeIfPresent(String.self, forKey: .voiceName) ?? ""
        voiceId = try container.decodeIfPresent(String.self, forKey: .voiceId) ?? ""
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        sourceDurationSeconds = try container.decodeIfPresent(Double.self, forKey: .sourceDurationSeconds) ?? 0
        voiceSpeed = try container.decodeIfPresent(Double.self, forKey: .voiceSpeed)
            ?? StoryAudioVoiceCatalog.defaultSpeed
        audioProcessor = try container.decodeIfPresent(String.self, forKey: .audioProcessor) ?? ""
        scriptResponseId = try container.decodeIfPresent(String.self, forKey: .scriptResponseId) ?? ""
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId) ?? ""
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId) ?? ""
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? DateFormats.now()
        self = normalized()
    }
}

/// The 3–5 LLM-drafted meaning messages a shot's narration can start from.
/// `entriesFingerprint` records the frame strip the chips were drafted against
/// so a changed strip shows as STALE instead of silently lying.
struct ShotNarrationChipSet: Codable, Hashable, Sendable {
    var statements: [String] = []
    var entriesFingerprint: String = ""
    var responseId: String = ""
    var generatedAt: String = ""

    func normalized() -> ShotNarrationChipSet {
        var value = self
        value.statements = Array(
            value.statements
                .map { $0.trimmed }
                .filter { !$0.isEmpty }
                .prefix(5)
        )
        value.entriesFingerprint = value.entriesFingerprint.trimmed
        value.responseId = value.responseId.trimmed
        value.generatedAt = value.generatedAt.trimmed
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case statements
        case entriesFingerprint
        case responseId
        case generatedAt
    }

    init(
        statements: [String] = [],
        entriesFingerprint: String = "",
        responseId: String = "",
        generatedAt: String = ""
    ) {
        self.statements = statements
        self.entriesFingerprint = entriesFingerprint
        self.responseId = responseId
        self.generatedAt = generatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statements = try container.decodeIfPresent([String].self, forKey: .statements) ?? []
        entriesFingerprint = try container.decodeIfPresent(String.self, forKey: .entriesFingerprint) ?? ""
        responseId = try container.decodeIfPresent(String.self, forKey: .responseId) ?? ""
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        self = normalized()
    }
}

/// Identity of a shot's frame strip: same ordered frames → same fingerprint.
func shotEntriesFingerprint(_ shot: ProjectShot) -> String {
    let joined = shot.entries.map(\.frameImageId).joined(separator: "|")
    guard !joined.isEmpty else { return "" }
    return shortHash(joined, length: 12)
}

/// Content gist of one frame for narration prompts: the source prompt (or
/// prompt) compacted to a single ≤220-character line.
func shotNarrationFrameGist(_ frame: ProjectLensHeroImage) -> String {
    let stored = frame.sourcePrompt.trimmed.nilIfEmpty ?? frame.prompt.trimmed
    let source = RosterMentionResolver.strippingMentionTokens(stored)
    let compact = source.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
    guard compact.count > 220 else { return compact }
    return String(compact.prefix(220)).trimmed + "…"
}

/// The gists of a shot's frames in strip order; frames missing from the lookup
/// are skipped (they carry no content to narrate against).
func shotNarrationFrameGists(
    shot: ProjectShot,
    frameLookup: [String: ProjectLensHeroImage]
) -> [String] {
    shot.entries
        .compactMap { frameLookup[$0.frameImageId] }
        .map { shotNarrationFrameGist($0) }
        .filter { !$0.isEmpty }
}

// MARK: - Prompt composition (pure)

/// Composes the OpenAI requests behind shot narration: the meaning-message
/// chip candidates and the voice-over script seeded by the chosen message.
enum ShotNarrationComposer {
    /// Prompt for the 3–5 candidate meaning messages a narration could serve.
    static func chipsPrompt(
        shotName: String,
        frameGists: [String],
        strandLines: [String],
        meaningNodeLines: [String],
        brief: ProjectGoalBriefV2
    ) -> String {
        var lines: [String] = []
        lines.append("Draft 3 to 5 candidate meaning messages for one continuous passage of a rendered visual story — short thesis statements a narrator could build a voice-over around.")
        lines.append("")
        let name = shotName.trimmed
        if !name.isEmpty {
            lines.append("The passage is titled: \(name)")
        }
        if !frameGists.isEmpty {
            lines.append("The passage moves through, in order:")
            for (index, gist) in frameGists.enumerated() {
                lines.append("\(index + 1). \(gist)")
            }
        }
        let strands = strandLines.map { $0.trimmed }.filter { !$0.isEmpty }
        if !strands.isEmpty {
            lines.append("Meaning threads running through it:")
            for strand in strands {
                lines.append("- \(strand)")
            }
        }
        let nodes = meaningNodeLines.map { $0.trimmed }.filter { !$0.isEmpty }
        if !nodes.isEmpty {
            lines.append("The project's meaning vocabulary:")
            for node in nodes {
                lines.append("- \(node)")
            }
        }
        lines.append(contentsOf: briefLines(brief))
        lines.append("")
        lines.append("Rules:")
        lines.append("- Each message is one sentence of at most 14 words: a claim about what this passage MEANS, never a caption of what it shows.")
        lines.append("- Each message takes a distinct angle — vary the emotional, thematic, and narrative emphasis.")
        lines.append("- Plain spoken language only: no camera or art-direction words (image, render, style, shot, frame, cinematic, palette), no quotation marks, no numbering inside the text.")
        return lines.joined(separator: "\n")
    }

    /// The full spoken narration: the thesis title, then the body on a new
    /// paragraph. Empty body → title alone; a body that opens by repeating
    /// the title (case/punctuation-insensitively) is used alone.
    static func spokenScript(title: String, body: String) -> String {
        let title = title.trimmed
        let body = body.trimmed
        guard !body.isEmpty else { return title }
        guard !title.isEmpty else { return body }
        if normalizedForPrefixMatch(body).hasPrefix(normalizedForPrefixMatch(title)) {
            return body
        }
        return title + "\n\n" + body
    }

    private static func normalizedForPrefixMatch(_ text: String) -> String {
        text.lowercased()
            .filter { !$0.isPunctuation }
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Prompt for the voice-over body that continues the spoken thesis line.
    static func scriptPrompt(
        messaging: String,
        shotName: String,
        frameGists: [String],
        strandLabels: [String],
        brief: ProjectGoalBriefV2,
        targetSeconds: Int
    ) -> String {
        var lines: [String] = []
        lines.append("Write the body of a short spoken voice-over for one continuous passage of a rendered visual story. The narration plays while the viewer watches the passage's moving footage.")
        lines.append("")
        lines.append("The opening line, spoken aloud immediately before your text — everything serves it: \(messaging.trimmed)")
        let name = shotName.trimmed
        if !name.isEmpty {
            lines.append("The passage is titled: \(name)")
        }
        if !frameGists.isEmpty {
            lines.append("The footage moves through, in order:")
            for (index, gist) in frameGists.enumerated() {
                lines.append("\(index + 1). \(gist)")
            }
        }
        let motifs = strandLabels.map { $0.trimmed }.filter { !$0.isEmpty }
        if !motifs.isEmpty {
            lines.append("Meaning threads to honor: \(motifs.joined(separator: ", "))")
        }
        lines.append(contentsOf: briefLines(brief))
        lines.append("")
        lines.append("Rules:")
        if targetSeconds > 0 {
            let titleWordCount = messaging.trimmed.split(separator: " ", omittingEmptySubsequences: true).count
            let words = min(120, max(20, Int((Double(targetSeconds) * 2.5).rounded()) - titleWordCount))
            lines.append("- About \(words) words — the footage runs roughly \(targetSeconds) seconds and the opening line plus your text should fill it spoken aloud.")
        } else {
            lines.append("- 2 to 3 sentences, 25 to 45 words total — roughly ten to sixteen seconds spoken aloud.")
        }
        lines.append("- Do not repeat or rephrase the opening line — continue from it as the next spoken sentence.")
        lines.append("- Present tense, as an unseen narrator inside this world's mood; never address the viewer.")
        lines.append("- Evocative and concrete: carry the message through what is seen and what it implies. Add nothing the footage contradicts.")
        lines.append("- Plain spoken prose only: no camera or art-direction words (image, render, style, shot, frame), no greetings, no title, no quotation marks.")
        return lines.joined(separator: "\n")
    }

    static func briefLines(_ brief: ProjectGoalBriefV2) -> [String] {
        var lines: [String] = []
        if !brief.goal.trimmed.isEmpty {
            lines.append("The project's goal: \(brief.goal.trimmed)")
        }
        if !brief.audience.trimmed.isEmpty {
            lines.append("The audience: \(brief.audience.trimmed)")
        }
        if !brief.desiredResponse.trimmed.isEmpty {
            lines.append("The desired response: \(brief.desiredResponse.trimmed)")
        }
        if !brief.viewerExperience.trimmed.isEmpty {
            lines.append("The intended viewer experience: \(brief.viewerExperience.trimmed)")
        }
        if !brief.lensSeedSummary.trimmed.isEmpty {
            lines.append("The world in brief: \(brief.lensSeedSummary.trimmed)")
        }
        return lines
    }
}
