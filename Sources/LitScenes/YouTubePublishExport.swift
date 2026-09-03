import Foundation

// MARK: - Export for YouTube (pure)

/// Composes the one-shot YouTube title+description request and renders the
/// markdown that ships beside the exported video. Pure by design — the engine
/// hands in snapshots, nothing here touches state or disk.
enum YouTubePublishComposer {
    /// Appended deterministically in code — never entrusted to the model.
    static let attributionLine = "Made with LitScenes.AI"

    /// What the copy is FOR: the whole Finals Reel or one cut. Swaps the
    /// opening sentence and how the subject lines are introduced; every other
    /// line rides the same shape.
    enum SubjectKind {
        case reel
        case cut
    }

    static func publishCopyPrompt(
        kind: SubjectKind,
        projectName: String,
        story: ProjectStoryDocument,
        brief: ProjectGoalBriefV2,
        subjectLines: [String],
        durationSeconds: Double
    ) -> String {
        var lines: [String] = []
        switch kind {
        case .reel:
            lines.append("Write the YouTube title and description for a finished short film.")
        case .cut:
            lines.append("Write the YouTube title and description for one cut of a short film, published on its own.")
        }
        lines.append("")
        let workingTitle = story.title.trimmed.nilIfEmpty ?? projectName.trimmed
        if !workingTitle.isEmpty {
            lines.append("The film's working title: \(workingTitle)")
        }
        if !story.logline.trimmed.isEmpty {
            lines.append("Logline: \(story.logline.trimmed)")
        }
        if let tension = story.centralTension?.trimmed, !tension.isEmpty {
            lines.append("Central tension: \(tension)")
        }
        if let engine = story.storyEngine?.trimmed, !engine.isEmpty {
            lines.append("Story engine: \(engine)")
        }
        if !story.promptReadySummary.trimmed.isEmpty {
            lines.append("Story summary:")
            lines.append(story.promptReadySummary.trimmed)
        }
        let subjects = subjectLines.map { $0.trimmed }.filter { !$0.isEmpty }
        let runtime = durationSeconds > 0
            ? SessionRecordingClock.elapsedLabel(durationSeconds)
            : ""
        switch kind {
        case .reel:
            if !subjects.isEmpty {
                lines.append(runtime.isEmpty
                    ? "It moves through, in order:"
                    : "It runs about \(runtime) and moves through, in order:")
                lines.append(contentsOf: subjects)
            } else if !runtime.isEmpty {
                lines.append("It runs about \(runtime).")
            }
        case .cut:
            lines.append(contentsOf: subjects)
            if !runtime.isEmpty {
                lines.append("It runs about \(runtime).")
            }
        }
        lines.append(contentsOf: ShotNarrationComposer.briefLines(brief))
        lines.append("")
        lines.append("Rules:")
        lines.append("- The title: at most 70 characters, plain text — concise, clear, specific to THIS film; no clickbait, no quotes, no emoji, no trailing punctuation.")
        lines.append("- The description: 2 to 4 short paragraphs of plain prose separated by blank lines — no headings, no links, no hashtags, no emoji, no bullet lists.")
        lines.append("- Open with one sentence that makes a viewer press play; then say what the film is and what it means, written for the audience above.")
        lines.append("- Never mention prompts, AI tools, rendering, or the production process.")
        lines.append("- Do not add credits or an attribution line — attribution is appended separately.")
        return lines.joined(separator: "\n")
    }

    /// Finals-order subject lines for the reel prompt, restricted to the cuts
    /// actually in the exported plan: "N. <name> — <narration thesis>".
    /// Unknown ids are skipped; the ordinal follows the lines that render.
    static func cutLines(cutIdsInReelOrder: [String], shots: [ProjectShot]) -> [String] {
        var lines: [String] = []
        for cutId in cutIdsInReelOrder {
            guard let shot = shots.first(where: { $0.shotId == cutId }) else { continue }
            let name = shot.name.trimmed.nilIfEmpty ?? "Untitled cut"
            let thesis = shot.narrationArtifact?.messagingText.trimmed ?? ""
            let suffix = thesis.isEmpty ? "" : " — \(thesis)"
            lines.append("\(lines.count + 1). \(name)\(suffix)")
        }
        return lines
    }

    /// Subject lines for one cut's prompt: its name, then the narration
    /// thesis and spoken body when they exist.
    static func shotSubjectLines(shot: ProjectShot) -> [String] {
        var lines: [String] = []
        if let name = shot.name.trimmed.nilIfEmpty {
            lines.append("The cut is titled: \(name)")
        }
        if let narration = shot.narrationArtifact {
            if let thesis = narration.messagingText.trimmed.nilIfEmpty {
                lines.append("Its narration thesis: \(thesis)")
            }
            if let body = narration.bodyText.trimmed.nilIfEmpty {
                lines.append("Its spoken narration: \(body)")
            }
        }
        return lines
    }

    /// Deterministic copy for when the LLM call fails — the video still
    /// ships, honestly labeled by the caller's status line.
    static func fallbackCopy(
        projectName: String,
        story: ProjectStoryDocument
    ) -> (title: String, description: String) {
        let title = story.title.trimmed.nilIfEmpty
            ?? projectName.trimmed.nilIfEmpty
            ?? "Finals Reel"
        let description = story.logline.trimmed.nilIfEmpty
            ?? story.promptReadySummary.trimmed.nilIfEmpty
            ?? "A short film."
        return (title, description)
    }

    /// The whole .md file: `# title`, description, attribution — the
    /// attribution is ALWAYS the last line. A model-emitted trailing
    /// attribution (last non-blank line naming LitScenes) is dropped first so
    /// the line never doubles.
    static func publishMarkdown(title: String, description: String) -> String {
        let headingText = title
            .components(separatedBy: .newlines)
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty ?? "Untitled"
        var bodyLines = description.trimmed.components(separatedBy: .newlines)
        if let last = bodyLines.lastIndex(where: { !$0.trimmed.isEmpty }),
           bodyLines[last].trimmed.lowercased().contains("made with litscenes") {
            bodyLines.remove(at: last)
        }
        let body = bodyLines.joined(separator: "\n").trimmed
        var out = "# \(headingText)\n"
        if !body.isEmpty {
            out += "\n\(body)\n"
        }
        out += "\n\(attributionLine)\n"
        return out
    }
}

/// Naming for the exported pair in ~/Downloads/LitScenes-Finals. The .mp4 and
/// .md share ONE stem and ONE collision ordinal so they always read as a pair.
enum FinalsReelPublishNaming {
    static let folderName = "LitScenes-Finals"
    static let maximumStemLength = 60

    /// `stableSlug` of the title, capped at 60 characters — cut at the last
    /// dash inside the cap when one exists so words stay whole.
    static func stem(fromTitle title: String, fallback: String) -> String {
        let fallbackStem = stableSlug(fallback, fallback: "finals-reel")
        let slug = stableSlug(title, fallback: fallbackStem)
        guard slug.count > maximumStemLength else { return slug }
        var capped = String(slug.prefix(maximumStemLength))
        if let lastDash = capped.lastIndex(of: "-"), lastDash != capped.startIndex {
            capped = String(capped[..<lastDash])
        }
        return capped.trimmingCharacters(in: CharacterSet(charactersIn: "-")).nilIfEmpty
            ?? fallbackStem
    }

    /// If EITHER file of the pair exists, BOTH step to "<stem>-2", "-3", … —
    /// `SessionRecordingNaming.collisionSafeURL`'s law with two extensions.
    static func collisionSafePairURLs(
        in directory: URL,
        stem: String,
        fileExists: (URL) -> Bool
    ) -> (video: URL, markdown: URL) {
        func pair(_ candidateStem: String) -> (video: URL, markdown: URL) {
            (
                video: directory.appendingPathComponent("\(candidateStem).mp4"),
                markdown: directory.appendingPathComponent("\(candidateStem).md")
            )
        }
        let base = pair(stem)
        guard fileExists(base.video) || fileExists(base.markdown) else { return base }
        var ordinal = 2
        while ordinal < 10_000 {
            let candidate = pair("\(stem)-\(ordinal)")
            if !fileExists(candidate.video), !fileExists(candidate.markdown) {
                return candidate
            }
            ordinal += 1
        }
        return base
    }
}
