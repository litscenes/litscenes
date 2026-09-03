import Foundation
import Testing
@testable import LitScenes

// Export for YouTube's pure layer: the shared-stem pair naming, the markdown
// whose last line is ALWAYS the attribution, the prompt composer, and the
// deterministic fallback copy that ships when the LLM call fails.

@Test func youtubeStemSlugsAndCaps() {
    #expect(
        FinalsReelPublishNaming.stem(fromTitle: "The Tide Remembers!", fallback: "project")
            == "the-tide-remembers"
    )
    // Nothing sluggable in the title: the fallback's slug takes over.
    #expect(
        FinalsReelPublishNaming.stem(fromTitle: "???", fallback: "Maker's Project")
            == "maker-s-project"
    )
    #expect(
        FinalsReelPublishNaming.stem(fromTitle: "", fallback: "")
            == "finals-reel"
    )
    // Over the cap: cut at a dash boundary, never a trailing dash.
    let long = Array(repeating: "wave", count: 30).joined(separator: " ")
    let capped = FinalsReelPublishNaming.stem(fromTitle: long, fallback: "project")
    #expect(capped.count <= FinalsReelPublishNaming.maximumStemLength)
    #expect(!capped.hasSuffix("-"))
    #expect(capped.hasPrefix("wave-wave"))
    // A single unbroken word longer than the cap: hard cut, still no dash.
    let unbroken = FinalsReelPublishNaming.stem(
        fromTitle: String(repeating: "a", count: 80),
        fallback: "project"
    )
    #expect(unbroken == String(repeating: "a", count: 60))
}

@Test func youtubePairNamingSharesOneOrdinal() {
    let directory = URL(fileURLWithPath: "/tmp/finals", isDirectory: true)

    let fresh = FinalsReelPublishNaming.collisionSafePairURLs(
        in: directory, stem: "the-tide", fileExists: { _ in false }
    )
    #expect(fresh.video.lastPathComponent == "the-tide.mp4")
    #expect(fresh.markdown.lastPathComponent == "the-tide.md")

    // Only the video taken: BOTH members step to -2 so the pair stays a pair.
    let videoTaken = FinalsReelPublishNaming.collisionSafePairURLs(
        in: directory, stem: "the-tide", fileExists: { $0.lastPathComponent == "the-tide.mp4" }
    )
    #expect(videoTaken.video.lastPathComponent == "the-tide-2.mp4")
    #expect(videoTaken.markdown.lastPathComponent == "the-tide-2.md")

    // Only the markdown taken: same law.
    let markdownTaken = FinalsReelPublishNaming.collisionSafePairURLs(
        in: directory, stem: "the-tide", fileExists: { $0.lastPathComponent == "the-tide.md" }
    )
    #expect(markdownTaken.video.lastPathComponent == "the-tide-2.mp4")
    #expect(markdownTaken.markdown.lastPathComponent == "the-tide-2.md")

    // Base and -2 both occupied (by either member): the next free ordinal.
    let taken: Set<String> = ["the-tide.mp4", "the-tide-2.md"]
    let third = FinalsReelPublishNaming.collisionSafePairURLs(
        in: directory, stem: "the-tide", fileExists: { taken.contains($0.lastPathComponent) }
    )
    #expect(third.video.lastPathComponent == "the-tide-3.mp4")
    #expect(third.markdown.lastPathComponent == "the-tide-3.md")
}

@Test func youtubeMarkdownAlwaysEndsWithAttribution() {
    #expect(
        YouTubePublishComposer.publishMarkdown(title: "The Tide", description: "A film about salt.")
            == "# The Tide\n\nA film about salt.\n\nMade with LitScenes.AI\n"
    )
    // Empty description: heading straight to attribution, still last line.
    #expect(
        YouTubePublishComposer.publishMarkdown(title: "The Tide", description: "  ")
            == "# The Tide\n\nMade with LitScenes.AI\n"
    )
    // A multi-line title collapses to one heading line.
    let multiline = YouTubePublishComposer.publishMarkdown(
        title: "The Tide\nRemembers", description: "Body."
    )
    #expect(multiline.hasPrefix("# The Tide Remembers\n"))
    #expect(multiline.hasSuffix("\nMade with LitScenes.AI\n"))
}

@Test func youtubeMarkdownDedupesModelAttribution() {
    let markdown = YouTubePublishComposer.publishMarkdown(
        title: "The Tide",
        description: "A film about salt.\n\nMade with LitScenes.AI."
    )
    #expect(markdown == "# The Tide\n\nA film about salt.\n\nMade with LitScenes.AI\n")
    let occurrences = markdown.components(separatedBy: "Made with LitScenes").count - 1
    #expect(occurrences == 1)
}

@Test func youtubePublishPromptCarriesStoryAndRules() {
    let story = ProjectStoryDocument(
        projectId: "p1",
        title: "The Tide Remembers",
        logline: "A harbor town bargains with the sea.",
        centralTension: "What the water gives, it first takes.",
        promptReadySummary: "A fisherman's daughter learns the tide's ledger."
    )
    let brief = ProjectGoalBriefV2(
        goal: "Make the sea feel like a creditor",
        audience: "People who grew up near water"
    )
    let prompt = YouTubePublishComposer.publishCopyPrompt(
        kind: .reel,
        projectName: "tide-project",
        story: story,
        brief: brief,
        subjectLines: ["1. First Light — What the water gives, it first takes."],
        durationSeconds: 102
    )
    #expect(prompt.contains("The film's working title: The Tide Remembers"))
    #expect(prompt.contains("Logline: A harbor town bargains with the sea."))
    #expect(prompt.contains("It runs about 01:42 and moves through, in order:"))
    #expect(prompt.contains("1. First Light — What the water gives, it first takes."))
    #expect(prompt.contains("The project's goal: Make the sea feel like a creditor"))
    #expect(prompt.contains("The audience: People who grew up near water"))
    #expect(prompt.contains("at most 70 characters"))
    #expect(prompt.contains("Do not add credits or an attribution line"))
    #expect(prompt.hasPrefix("Write the YouTube title and description for a finished short film."))

    // The cut flavor swaps the opening sentence only.
    let cutPrompt = YouTubePublishComposer.publishCopyPrompt(
        kind: .cut,
        projectName: "tide-project",
        story: story,
        brief: brief,
        subjectLines: ["The cut is titled: First Light"],
        durationSeconds: 0
    )
    #expect(cutPrompt.hasPrefix("Write the YouTube title and description for one cut of a short film"))
    #expect(cutPrompt.contains("The cut is titled: First Light"))
    #expect(!cutPrompt.contains("It runs about"))

    // Empty story/brief fields never emit their labels.
    let bare = YouTubePublishComposer.publishCopyPrompt(
        kind: .reel,
        projectName: "",
        story: ProjectStoryDocument(projectId: "p1"),
        brief: ProjectGoalBriefV2(),
        subjectLines: [],
        durationSeconds: 0
    )
    #expect(!bare.contains("working title"))
    #expect(!bare.contains("Logline:"))
    #expect(!bare.contains("It runs about"))
    #expect(!bare.contains("The project's goal:"))
}

@Test func youtubeCutLinesFollowReelOrder() {
    var first = ProjectShot(shotId: "cut_a", name: "First Light")
    first.narrationArtifact = ShotNarrationArtifact(messagingText: "What the water gives, it first takes.")
    let second = ProjectShot(shotId: "cut_b", name: "  ")
    let third = ProjectShot(shotId: "cut_c", name: "The Bargain")

    let lines = YouTubePublishComposer.cutLines(
        cutIdsInReelOrder: ["cut_c", "cut_ghost", "cut_a", "cut_b"],
        shots: [first, second, third]
    )
    #expect(lines == [
        "1. The Bargain",
        "2. First Light — What the water gives, it first takes.",
        "3. Untitled cut"
    ])
}

@Test func youtubeFallbackCopyPrefersStoryTitle() {
    let full = YouTubePublishComposer.fallbackCopy(
        projectName: "tide-project",
        story: ProjectStoryDocument(
            projectId: "p1",
            title: "The Tide Remembers",
            logline: "A harbor town bargains with the sea."
        )
    )
    #expect(full.title == "The Tide Remembers")
    #expect(full.description == "A harbor town bargains with the sea.")

    var summaryOnly = ProjectStoryDocument(projectId: "p1")
    summaryOnly.promptReadySummary = "A fisherman's daughter learns the tide's ledger."
    let partial = YouTubePublishComposer.fallbackCopy(projectName: "tide-project", story: summaryOnly)
    #expect(partial.title == "tide-project")
    #expect(partial.description == "A fisherman's daughter learns the tide's ledger.")

    let empty = YouTubePublishComposer.fallbackCopy(projectName: " ", story: ProjectStoryDocument(projectId: "p1"))
    #expect(empty.title == "Finals Reel")
    #expect(empty.description == "A short film.")
}
