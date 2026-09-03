import Foundation
import Testing
@testable import LitScenes

// The persisted hero prompt must echo the exact request text on the Responses
// image path: system-role instructions and the content-only user prompt joined
// by one blank line, with no separator residue when either side is empty.

@Test func responsesTransmittedPromptJoinsInstructionsAndUserPrompt() {
    let transmitted = lensResponsesTransmittedPrompt(
        instructions: "Render one image.\n\nStyle references are style-only.",
        userPrompt: "Style direction: gouache storybook\n\nA quiet harbor at dawn"
    )
    #expect(transmitted == "Render one image.\n\nStyle references are style-only.\n\nStyle direction: gouache storybook\n\nA quiet harbor at dawn")
}

@Test func responsesTransmittedPromptWithoutInstructionsIsUserPromptOnly() {
    let transmitted = lensResponsesTransmittedPrompt(
        instructions: "",
        userPrompt: "A quiet harbor at dawn"
    )
    #expect(transmitted == "A quiet harbor at dawn")
}

@Test func responsesTransmittedPromptWithoutUserPromptIsInstructionsOnly() {
    let transmitted = lensResponsesTransmittedPrompt(
        instructions: "Render one image.",
        userPrompt: ""
    )
    #expect(transmitted == "Render one image.")
}

// Ratified (responses-wire-block-parity): the Responses user prompt
// carries finalPrompt's content segments — style line, scene, medium, mood
// influences, the single-frame guard, attachment entry lines — in that order.

@Test func responsesUserPromptCarriesAllContentSegmentsInCanonicalOrder() {
    let userPrompt = lensResponsesUserPrompt(
        styleSummaryLine: "Style direction: gouache storybook",
        enhancedPrompt: "A quiet harbor at dawn",
        mediumBlock: "FILMED — photographic live-action capture.",
        moodInfluenceBlock: "Mood influences (from the project moodboard):\n- fog-muted palettes",
        manifestEntries: "1. harbor_ref.png — the harbor from the north pier"
    )
    #expect(userPrompt == """
    Style direction: gouache storybook

    A quiet harbor at dawn

    FILMED — photographic live-action capture.

    Mood influences (from the project moodboard):
    - fog-muted palettes

    \(lensSingleFrameGuard)

    1. harbor_ref.png — the harbor from the north pier
    """)
}

@Test func responsesUserPromptDropsEmptySegmentsWithoutResidue() {
    let userPrompt = lensResponsesUserPrompt(
        styleSummaryLine: "",
        enhancedPrompt: "A quiet harbor at dawn",
        mediumBlock: "",
        moodInfluenceBlock: "",
        manifestEntries: ""
    )
    #expect(userPrompt == "A quiet harbor at dawn\n\n\(lensSingleFrameGuard)")
}

@Test func responsesUserPromptAlwaysCarriesSingleFrameGuard() {
    let userPrompt = lensResponsesUserPrompt(
        styleSummaryLine: "",
        enhancedPrompt: "",
        mediumBlock: "",
        moodInfluenceBlock: "",
        manifestEntries: ""
    )
    #expect(userPrompt == lensSingleFrameGuard)
}
