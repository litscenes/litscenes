import Foundation
import Testing
@testable import LitScenes

@Test func lensNarrationArtifactDecodesWithMissingKeys() throws {
    let artifact = try JSONDecoder().decode(LensNarrationArtifact.self, from: Data("{}".utf8))
    #expect(artifact.provider == "elevenlabs_tts")
    #expect(artifact.model == ElevenLabsSpeechModels.legacyMissingModelId)
    #expect(artifact.status.isEmpty)
    #expect(artifact.audioPath.isEmpty)
    #expect(artifact.durationSeconds == 0)
    #expect(!artifact.isReady)
}

@Test func lensNarrationArtifactNormalizedDefaultsAndClamps() {
    let artifact = LensNarrationArtifact(
        provider: "  ",
        model: " ",
        status: " ready ",
        audioPath: " /tmp/a.mp3 ",
        script: "  a line  ",
        durationSeconds: -4
    ).normalized()
    #expect(artifact.provider == "elevenlabs_tts")
    #expect(artifact.model == ElevenLabsSpeechModels.defaultModelId)
    #expect(artifact.status == "ready")
    #expect(artifact.audioPath == "/tmp/a.mp3")
    #expect(artifact.script == "a line")
    #expect(artifact.durationSeconds == 0)
    #expect(artifact.isReady)
}

@Test func lensHeroImageWithoutNarrationKeyDecodes() throws {
    let json = """
    {"imageId": "lens_hero_test", "status": "ready"}
    """
    let image = try JSONDecoder().decode(ProjectLensHeroImage.self, from: Data(json.utf8))
    #expect(image.narrationArtifact == nil)
}

@Test func lensHeroImageMalformedNarrationDegradesToNil() throws {
    let json = """
    {"imageId": "lens_hero_test", "narrationArtifact": 42}
    """
    let image = try JSONDecoder().decode(ProjectLensHeroImage.self, from: Data(json.utf8))
    #expect(image.imageId == "lens_hero_test")
    #expect(image.narrationArtifact == nil)
}

@Test func lensHeroImageNarrationRoundTrips() throws {
    var image = ProjectLensHeroImage(imageId: "lens_hero_take", status: "ready")
    image.narrationArtifact = LensNarrationArtifact(
        status: "ready",
        audioPath: "/tmp/narration.mp3",
        script: "Salt wind combs the rigging.",
        voicePresetId: "archer",
        voiceName: "Archer",
        voiceId: "voice_123",
        durationSeconds: 11.4
    )
    let data = try JSONEncoder().encode(image)
    let decoded = try JSONDecoder().decode(ProjectLensHeroImage.self, from: data)
    #expect(decoded.narrationArtifact?.isReady == true)
    #expect(decoded.narrationArtifact?.script == "Salt wind combs the rigging.")
    #expect(decoded.narrationArtifact?.voiceName == "Archer")
    #expect(decoded.narrationArtifact?.durationSeconds == 11.4)
}

@Test func lensNarrationScriptPromptCarriesWorldContextAndRules() {
    let prompt = LensNarrationComposer.scriptPrompt(
        lensTitle: "Harbor at Dusk",
        subjectSummary: "a weathered fishing pier",
        imagePrompt: "long wooden pier under amber lanterns"
    )
    #expect(prompt.contains("The world: Harbor at Dusk"))
    #expect(prompt.contains("The subject of the image: a weathered fishing pier"))
    #expect(prompt.contains("What the image shows: long wooden pier under amber lanterns"))
    #expect(prompt.contains("25 to 45 words"))
    #expect(prompt.contains("Present tense"))
}

@Test func lensNarrationScriptPromptOmitsEmptySections() {
    let prompt = LensNarrationComposer.scriptPrompt(
        lensTitle: "",
        subjectSummary: "  ",
        imagePrompt: "a lighthouse in fog"
    )
    #expect(!prompt.contains("The world:"))
    #expect(!prompt.contains("The subject of the image:"))
    #expect(prompt.contains("What the image shows: a lighthouse in fog"))
}
