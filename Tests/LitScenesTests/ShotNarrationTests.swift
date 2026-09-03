import Foundation
import Testing
@testable import LitScenes

// MARK: Artifact decode / normalize

@Test func shotNarrationArtifactDecodesWithMissingKeys() throws {
    let artifact = try JSONDecoder().decode(ShotNarrationArtifact.self, from: Data("{}".utf8))
    #expect(artifact.provider == "elevenlabs_tts")
    #expect(artifact.model == ElevenLabsSpeechModels.legacyMissingModelId)
    #expect(artifact.status.isEmpty)
    #expect(artifact.messagingText.isEmpty)
    #expect(artifact.audioPath.isEmpty)
    #expect(artifact.durationSeconds == 0)
    #expect(!artifact.isReady)
}

@Test func shotNarrationArtifactNormalizedTrimsAndClamps() {
    let artifact = ShotNarrationArtifact(
        provider: "  ",
        model: " ",
        status: " ready ",
        messagingText: "  Departure costs more than it promises.  ",
        audioPath: " /tmp/a.mp3 ",
        script: "  a line  ",
        durationSeconds: -4
    ).normalized()
    #expect(artifact.provider == "elevenlabs_tts")
    #expect(artifact.model == ElevenLabsSpeechModels.defaultModelId)
    #expect(artifact.status == "ready")
    #expect(artifact.messagingText == "Departure costs more than it promises.")
    #expect(artifact.audioPath == "/tmp/a.mp3")
    #expect(artifact.script == "a line")
    #expect(artifact.durationSeconds == 0)
    #expect(artifact.isReady)
}

// MARK: ProjectShot tolerance

@Test func projectShotWithoutNarrationKeysDecodes() throws {
    let json = """
    {"shotId": "shot_test"}
    """
    let shot = try JSONDecoder().decode(ProjectShot.self, from: Data(json.utf8))
    #expect(shot.shotId == "shot_test")
    #expect(shot.narrationArtifact == nil)
    #expect(shot.narrationChips == nil)
}

@Test func projectShotMalformedNarrationDegradesToNil() throws {
    let json = """
    {"shotId": "shot_test", "narrationArtifact": 42, "narrationChips": "nope"}
    """
    let shot = try JSONDecoder().decode(ProjectShot.self, from: Data(json.utf8))
    #expect(shot.shotId == "shot_test")
    #expect(shot.narrationArtifact == nil)
    #expect(shot.narrationChips == nil)
}

@Test func projectShotNarrationRoundTripsThroughTimelineDocument() throws {
    var shot = ProjectShot(shotId: "shot_take", name: "Into the abyss")
    shot = shot.settingNarrationArtifact(
        ShotNarrationArtifact(
            status: "ready",
            messagingText: "The city keeps what the sea surrenders.",
            audioPath: "/tmp/shot_narration.mp3",
            script: "Salt wind combs the rigging.",
            voicePresetId: "archer",
            voiceName: "Archer",
            voiceId: "voice_123",
            durationSeconds: 11.4
        ),
        now: "2026-07-11T00:00:00Z"
    )
    shot = shot.settingNarrationChips(
        ShotNarrationChipSet(
            statements: ["The city keeps what the sea surrenders.", "Every arrival is a bargain."],
            entriesFingerprint: "abc123",
            responseId: "resp_1",
            generatedAt: "2026-07-11T00:00:00Z"
        ),
        now: "2026-07-11T00:00:00Z"
    )
    let document = ProjectShotTimelineDocument(projectId: "proj", shots: [shot])
    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(ProjectShotTimelineDocument.self, from: data)
    let decodedShot = try #require(decoded.shots.first)
    #expect(decodedShot.narrationArtifact?.isReady == true)
    #expect(decodedShot.narrationArtifact?.messagingText == "The city keeps what the sea surrenders.")
    #expect(decodedShot.narrationArtifact?.durationSeconds == 11.4)
    #expect(decodedShot.narrationChips?.statements.count == 2)
    #expect(decodedShot.narrationChips?.entriesFingerprint == "abc123")
}

@Test func shotNarrationArtifactHiddenBodyAndVersionsDecodeAndRoundTrip() throws {
    let empty = try JSONDecoder().decode(ShotNarrationArtifact.self, from: Data("{}".utf8))
    #expect(empty.bodyText.isEmpty)
    #expect(empty.titleVersions.isEmpty)

    let artifact = ShotNarrationArtifact(
        status: "ready",
        messagingText: "The city keeps what the sea surrenders.",
        audioPath: "/tmp/a.mp3",
        script: "The city keeps what the sea surrenders, always.",
        bodyText: "  Above the furious alien sea, one fragile hand holds the ark together.  ",
        titleVersions: ["The city keeps what the sea surrenders.", "  ", "The city keeps what the sea surrenders, always."]
    )
    let data = try JSONEncoder().encode(artifact)
    let decoded = try JSONDecoder().decode(ShotNarrationArtifact.self, from: data)
    #expect(decoded.bodyText == "Above the furious alien sea, one fragile hand holds the ark together.")
    // normalized() drops the blank version; the voiced history survives in order.
    #expect(decoded.titleVersions == [
        "The city keeps what the sea surrenders.",
        "The city keeps what the sea surrenders, always."
    ])
}

// MARK: Chips normalization

@Test func shotNarrationChipSetNormalizedDropsEmptiesAndClampsToFive() {
    let chips = ShotNarrationChipSet(
        statements: ["one", "  ", "two", "three", "four", "five", "six"],
        entriesFingerprint: " fp "
    ).normalized()
    #expect(chips.statements == ["one", "two", "three", "four", "five"])
    #expect(chips.entriesFingerprint == "fp")
}

// MARK: Fingerprint

@Test func shotEntriesFingerprintIsStableAndOrderSensitive() {
    let now = "2026-07-11T00:00:00Z"
    var shot = ProjectShot(shotId: "shot_fp")
    #expect(shotEntriesFingerprint(shot).isEmpty)

    shot = shot.insertingEntry(frameImageId: "frame_a", at: 0, now: now)
    shot = shot.insertingEntry(frameImageId: "frame_b", at: 1, now: now)
    let fingerprint = shotEntriesFingerprint(shot)
    #expect(!fingerprint.isEmpty)
    #expect(shotEntriesFingerprint(shot) == fingerprint)

    var reordered = shot
    reordered.entries = shot.entries.reversed()
    #expect(shotEntriesFingerprint(reordered) != fingerprint)

    // Content sensitivity: the same entry pointing at a different frame
    // changes the fingerprint (replace-by-drop was retired; a direct field
    // change proves the same law).
    var replaced = shot
    replaced.entries[0].frameImageId = "frame_c"
    #expect(shotEntriesFingerprint(replaced) != fingerprint)
}

// MARK: Composer prompts

@Test func shotNarrationChipsPromptCarriesContextAndRules() {
    let prompt = ShotNarrationComposer.chipsPrompt(
        shotName: "Into the abyss",
        frameGists: ["a rain-slick causeway at night", "an archive threshold"],
        strandLines: ["Quest into the unknown — a departure gathers weight"],
        meaningNodeLines: ["Threshold — the moment commitment becomes irreversible"],
        brief: ProjectGoalBriefV2(
            goal: "make leaving feel costly",
            audience: "late-night wanderers",
            desiredResponse: "quiet resolve",
            viewerExperience: "held breath",
            lensSeedSummary: "a drowned industrial city"
        )
    )
    #expect(prompt.contains("3 to 5 candidate meaning messages"))
    #expect(prompt.contains("The passage is titled: Into the abyss"))
    #expect(prompt.contains("1. a rain-slick causeway at night"))
    #expect(prompt.contains("2. an archive threshold"))
    #expect(prompt.contains("Quest into the unknown — a departure gathers weight"))
    #expect(prompt.contains("Threshold — the moment commitment becomes irreversible"))
    #expect(prompt.contains("The project's goal: make leaving feel costly"))
    #expect(prompt.contains("The desired response: quiet resolve"))
    #expect(prompt.contains("The world in brief: a drowned industrial city"))
    #expect(prompt.contains("at most 14 words"))
}

@Test func shotNarrationScriptPromptSpinesOnMessagingAndScalesWords() {
    let prompt = ShotNarrationComposer.scriptPrompt(
        messaging: "Departure costs more than it promises.",
        shotName: "Into the abyss",
        frameGists: ["a rain-slick causeway at night"],
        strandLabels: ["Quest into the unknown"],
        brief: ProjectGoalBriefV2(goal: "make leaving feel costly"),
        targetSeconds: 10
    )
    #expect(prompt.contains("everything serves it: Departure costs more than it promises."))
    #expect(prompt.contains("Meaning threads to honor: Quest into the unknown"))
    // 10s × 2.5 words/s = 25, minus the 6-word spoken title = 19 → floored at 20.
    #expect(prompt.contains("About 20 words"))
    #expect(prompt.contains("roughly 10 seconds"))
    #expect(prompt.contains("Do not repeat or rephrase the opening line"))
    #expect(prompt.contains("Present tense"))
    #expect(!prompt.contains("25 to 45 words"))
}

@Test func shotNarrationScriptPromptClampsWordTarget() {
    let long = ShotNarrationComposer.scriptPrompt(
        messaging: "m",
        shotName: "",
        frameGists: [],
        strandLabels: [],
        brief: ProjectGoalBriefV2(),
        targetSeconds: 90
    )
    // 90s × 2.5 = 225, minus the 1-word title = 224 → clamped to 120.
    #expect(long.contains("About 120 words"))

    let short = ShotNarrationComposer.scriptPrompt(
        messaging: "m",
        shotName: "",
        frameGists: [],
        strandLabels: [],
        brief: ProjectGoalBriefV2(),
        targetSeconds: 4
    )
    // 4s × 2.5 = 10, minus the 1-word title = 9 → floored at 20.
    #expect(short.contains("About 20 words"))
}

// MARK: Spoken script assembly

@Test func shotNarrationSpokenScriptJoinsTitleAndBody() {
    let script = ShotNarrationComposer.spokenScript(
        title: "Departure costs more than it promises.",
        body: "The causeway narrows and the lights thin out."
    )
    #expect(script == "Departure costs more than it promises.\n\nThe causeway narrows and the lights thin out.")
}

@Test func shotNarrationSpokenScriptFallsBackToTitleAlone() {
    #expect(ShotNarrationComposer.spokenScript(title: "Departure costs.", body: "") == "Departure costs.")
    #expect(ShotNarrationComposer.spokenScript(title: "Departure costs.", body: "   \n") == "Departure costs.")
    #expect(ShotNarrationComposer.spokenScript(title: "", body: "Only a body.") == "Only a body.")
}

@Test func shotNarrationSpokenScriptDropsTitleWhenBodyOpensWithIt() {
    // Case- and punctuation-insensitive prefix match: the body already
    // speaks the thesis line, so the title is not doubled.
    let body = "departure costs more than it promises — the lights thin out."
    let script = ShotNarrationComposer.spokenScript(
        title: "Departure costs more than it promises.",
        body: body
    )
    #expect(script == body)
}

@Test func shotNarrationSpokenScriptTrimsWhitespace() {
    let script = ShotNarrationComposer.spokenScript(
        title: "  A thesis.  ",
        body: "  A body.  "
    )
    #expect(script == "A thesis.\n\nA body.")
}

@Test func shotNarrationScriptPromptFallsBackWithoutDuration() {
    let prompt = ShotNarrationComposer.scriptPrompt(
        messaging: "Departure costs more than it promises.",
        shotName: "",
        frameGists: [],
        strandLabels: [],
        brief: ProjectGoalBriefV2(),
        targetSeconds: 0
    )
    #expect(prompt.contains("25 to 45 words"))
    #expect(!prompt.contains("About "))
}

// MARK: Frame gists

@Test func shotNarrationFrameGistsFollowStripOrderAndSkipMissing() {
    let now = "2026-07-11T00:00:00Z"
    var shot = ProjectShot(shotId: "shot_gist")
    shot = shot.insertingEntry(frameImageId: "frame_a", at: 0, now: now)
    shot = shot.insertingEntry(frameImageId: "frame_missing", at: 1, now: now)
    shot = shot.insertingEntry(frameImageId: "frame_b", at: 2, now: now)

    var frameA = ProjectLensHeroImage(imageId: "frame_a")
    frameA.sourcePrompt = "first line\nsecond line"
    var frameB = ProjectLensHeroImage(imageId: "frame_b")
    frameB.prompt = String(repeating: "x", count: 300)

    let gists = shotNarrationFrameGists(
        shot: shot,
        frameLookup: ["frame_a": frameA, "frame_b": frameB]
    )
    #expect(gists.count == 2)
    #expect(gists[0] == "first line second line")
    #expect(gists[1].hasSuffix("…"))
    #expect(gists[1].count <= 221)
}

// MARK: ElevenLabs voices listing

@Test func elevenLabsVoiceListDecodesTolerantly() throws {
    let json = """
    {"voices": [
        {"voice_id": "v1", "name": "Kai", "category": "cloned", "description": "warm"},
        {"voice_id": "v2"},
        {"name": "no id"}
    ]}
    """
    struct Wrapper: Codable { var voices: [ElevenLabsVoice] }
    let decoded = try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8))
    #expect(decoded.voices.count == 3)
    #expect(decoded.voices[0].name == "Kai")
    #expect(decoded.voices[0].category == "cloned")
    #expect(decoded.voices[1].name.isEmpty)
    #expect(decoded.voices[2].voiceId.isEmpty)
}

@Test func voiceCatalogAppendsAccountVoicesWithoutDuplicates() {
    let extras = [
        StoryAudioVoiceOption(id: "v_custom", name: "Kai", descriptor: "cloned", voiceId: "v_custom"),
        StoryAudioVoiceOption(id: "dup", name: "Dup", descriptor: "premade", voiceId: "L0Dsvb3SLTyegXwtm47J"),
        StoryAudioVoiceOption(id: "empty", name: "Empty", descriptor: "x", voiceId: " ")
    ]
    let options = StoryAudioVoiceCatalog.voiceOptions(customVoiceId: nil, extraVoices: extras)
    // Base three + only the genuinely new voice (Archer's id deduped, empty dropped).
    #expect(options.count == 4)
    #expect(options.last?.id == "v_custom")
    // Exact account-voice preset ids resolve before legacy normalization.
    let resolved = StoryAudioVoiceCatalog.option(for: "v_custom", customVoiceId: nil, extraVoices: extras)
    #expect(resolved.voiceId == "v_custom")
}
