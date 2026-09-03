import Foundation
import Testing
@testable import LitScenes

private func renderPromptMediaItem(
    mediaId: String,
    kind: MediaKind = .image,
    derivativeKind: String? = nil
) -> MediaItemRecord {
    MediaItemRecord(
        mediaId: mediaId,
        sourceId: "source_1",
        kind: kind,
        filename: "\(mediaId).png",
        path: "/tmp/roster_render_prompt/\(mediaId).png",
        relativePath: "\(mediaId).png",
        byteCount: 1234,
        modifiedAt: "2026-07-15T20:00:00.000Z",
        width: 1024,
        height: 1024,
        durationSeconds: nil,
        nominalFrameRate: nil,
        thumbnailPath: "",
        videoStripPath: nil,
        scannedAt: "2026-07-15T20:00:02.000Z",
        scanError: nil,
        derivativeKind: derivativeKind,
        sourceMediaId: derivativeKind == nil ? nil : "character_1",
        sourceTimestampSeconds: nil,
        frameIndex: nil
    )
}

@Test
func generatePromptComposesPerShot() {
    let fullFigure = RosterCharacterRenderPrompt.prompt(
        name: "Milo Blink",
        description: "Adult house gecko with a compact body.",
        signatureProps: ["a token belt", "a small headset", "a token belt"],
        shot: .fullFigure
    )
    #expect(fullFigure.hasPrefix("Create one tall vertical character concept study."))
    #expect(fullFigure.contains("The subject: \"Milo Blink\" — Adult house gecko with a compact body."))
    #expect(fullFigure.contains("Always with them: a token belt; a small headset."))
    #expect(fullFigure.contains("Show the full figure head to toe"))
    #expect(fullFigure.contains("stands alone as a clean isolated character study"))
    #expect(fullFigure.contains("Do not render readable text"))

    let threeQuarter = RosterCharacterRenderPrompt.prompt(
        name: "Milo Blink", description: "d", signatureProps: [], shot: .threeQuarter
    )
    #expect(threeQuarter.hasPrefix("Create one tall vertical character concept study."))
    #expect(threeQuarter.contains("head to mid-thigh"))
    #expect(!threeQuarter.contains("Always with them"))

    let portrait = RosterCharacterRenderPrompt.prompt(
        name: "Milo Blink", description: "d", signatureProps: [], shot: .portrait
    )
    #expect(portrait.hasPrefix("Create one square character portrait study."))
    #expect(portrait.contains("Frame head and shoulders"))
}

@Test
func generatePromptHandlesMissingNameAndDescription() {
    let anonymous = RosterCharacterRenderPrompt.prompt(
        name: "  ", description: "", signatureProps: [], shot: .fullFigure
    )
    #expect(anonymous.contains("The subject: the character."))
    let named = RosterCharacterRenderPrompt.prompt(
        name: "Milo", description: "   ", signatureProps: [], shot: .portrait
    )
    #expect(named.contains("The subject: \"Milo\"."))
    #expect(!named.contains("\"Milo\" —"))
}

@Test
func shotPresetsCarryRenderParameters() {
    #expect(RosterCharacterRenderPrompt.Shot.fullFigure.openAIImageSize == "1024x1536")
    #expect(RosterCharacterRenderPrompt.Shot.threeQuarter.openAIImageSize == "1024x1536")
    #expect(RosterCharacterRenderPrompt.Shot.portrait.openAIImageSize == "1024x1024")
    #expect(RosterCharacterRenderPrompt.Shot.fullFigure.aspect == "portrait")
    #expect(RosterCharacterRenderPrompt.Shot.portrait.aspect == "square")
}

@Test
func identityAnchorPicksPreferSheetAndCapForFAL() {
    let sheet = renderPromptMediaItem(mediaId: "m_sheet", derivativeKind: MediaItemRecord.rosterCompositeSheetDerivativeKind)
    let first = renderPromptMediaItem(mediaId: "m_1")
    let second = renderPromptMediaItem(mediaId: "m_2")
    let third = renderPromptMediaItem(mediaId: "m_3")
    let labels = ["m_1": "young Milo", "m_sheet": "reference sheet"]

    // Sheet wins alone, even when loose refs precede it.
    let withSheet = RosterCharacterRenderPrompt.identityAnchorPicks(
        referenced: [first, second, sheet],
        referenceLabels: labels,
        capOne: false,
        fileExists: { _ in true }
    )
    #expect(withSheet.count == 1)
    #expect(withSheet.first?.item.mediaId == "m_sheet")
    #expect(withSheet.first?.isSheet == true)

    // No sheet → leading two, order preserved, labels resolved.
    let looseRefs = RosterCharacterRenderPrompt.identityAnchorPicks(
        referenced: [first, second, third],
        referenceLabels: labels,
        capOne: false,
        fileExists: { _ in true }
    )
    #expect(looseRefs.map(\.item.mediaId) == ["m_1", "m_2"])
    #expect(looseRefs.first?.label == "young Milo")
    #expect(looseRefs.last?.label == "")

    // FAL keeps only the first loose reference.
    let capped = RosterCharacterRenderPrompt.identityAnchorPicks(
        referenced: [first, second],
        referenceLabels: labels,
        capOne: true,
        fileExists: { _ in true }
    )
    #expect(capped.map(\.item.mediaId) == ["m_1"])

    // Missing files and non-images are filtered before picking.
    let video = renderPromptMediaItem(mediaId: "m_video", kind: .video)
    let filtered = RosterCharacterRenderPrompt.identityAnchorPicks(
        referenced: [video, first, second],
        referenceLabels: [:],
        capOne: false,
        fileExists: { $0.contains("m_2") }
    )
    #expect(filtered.map(\.item.mediaId) == ["m_2"])
}

@Test
func characterStudyDescriptorIsTreatmentNeutral() {
    let plain = RosterMentionResolver.characterStudyAttachmentDescriptor(
        name: "Milo Blink", label: "young Milo", isCompositeSheet: false
    )
    #expect(plain.contains("CHARACTER identity reference for \"Milo Blink\""))
    #expect(plain.contains("follow the written prompt for framing and treatment"))
    #expect(!plain.contains("treatment's style"))
    #expect(!plain.contains("in the scene"))
    #expect(plain.hasSuffix("This particular reference shows: young Milo."))

    let sheet = RosterMentionResolver.characterStudyAttachmentDescriptor(
        name: "Milo Blink", label: "", isCompositeSheet: true
    )
    #expect(sheet.contains("labeled reference sheet"))
    #expect(!sheet.contains("This particular reference shows"))
}

@Test
func rosterCharacterRenderDerivativeKindIsGeneratedMedia() {
    let render = renderPromptMediaItem(mediaId: "m_render", derivativeKind: MediaItemRecord.rosterCharacterRenderDerivativeKind)
    #expect(render.isGeneratedMedia)
    #expect(!render.isRosterCompositeSheet)
    #expect(!render.isExtractedVideoFrame)
}
