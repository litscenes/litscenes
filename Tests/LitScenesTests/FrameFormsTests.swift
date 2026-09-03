import Foundation
import Testing
@testable import LitScenes

@Test func frameFormsResponseDecodesFromSnakeCaseWire() throws {
    let json = """
    {
        "schema_version": "litscenes.frame_forms.v0.1",
        "user_id": "user_1",
        "project_id": "proj_1",
        "mode": "initial",
        "generated_at": "2026-07-08T00:00:00Z",
        "model": "gpt-test",
        "options": [
            {
                "title": "The Locked Archive",
                "prompt": "A librarian pries open a sealed cabinet while dust settles around her.",
                "meaning_slug": "theme.forbidden-knowledge",
                "meaning_name": "forbidden knowledge",
                "pole": "positive",
                "abstraction_level": "thematic",
                "relation_to_parent": ""
            },
            {
                "title": "",
                "prompt": "",
                "meaning_slug": "dropped.empty",
                "pole": "negative"
            }
        ],
        "warnings": ["one warning"],
        "request_id": "req_1"
    }
    """
    let response = try JSONCoding.decoder.decode(FrameFormsGenerateResponse.self, from: Data(json.utf8))
    #expect(response.schemaVersion == "litscenes.frame_forms.v0.1")
    #expect(response.mode == "initial")
    // Empty-prompt options are dropped during decode.
    #expect(response.options.count == 1)
    #expect(response.options[0].meaningSlug == "theme.forbidden-knowledge")
    #expect(response.options[0].meaningName == "forbidden knowledge")
    #expect(response.options[0].abstractionLevel == "thematic")
    #expect(response.warnings == ["one warning"])
}

@Test func frameFormsRequestEncodesSnakeCaseWire() throws {
    var request = FrameFormsGenerateRequest(
        projectId: "proj_1",
        goalFingerprint: "fp_1",
        goalSummary: "A lighthouse town holds its breath.",
        styleFitLine: "quiet coastal scenes",
        meaningNodeRefs: [ProjectGoalMeaningNodeRef(slug: "theme.forbidden-knowledge")]
    )
    request.selectedForm = FrameFormsSelectedForm(
        meaningSlug: "theme.forbidden-knowledge",
        pole: "positive",
        title: "The Locked Archive",
        promptGist: "A librarian pries open a sealed cabinet."
    )
    request.priorFormGists = ["gist one"]
    let data = try JSONCoding.encoder.encode(request)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"project_id\""))
    #expect(text.contains("\"goal_summary\""))
    #expect(text.contains("\"style_fit_line\""))
    #expect(text.contains("\"meaning_node_refs\""))
    #expect(text.contains("\"selected_form\""))
    #expect(text.contains("\"prompt_gist\""))
    #expect(text.contains("\"prior_form_gists\""))
}

@Test func frameFormsDocumentRoundTripsAndHelpersWork() throws {
    let initial = LensFrameFormGeneration(
        generationId: "gen_1",
        mode: "initial",
        parentOptionId: "",
        options: [
            LensFrameFormOption(optionId: "form_a", title: "A", prompt: "Prompt A", meaningSlug: "theme.a", pole: "positive"),
            LensFrameFormOption(optionId: "form_b", title: "B", prompt: "Prompt B", meaningSlug: "theme.b", pole: "negative")
        ],
        generatedAt: "2026-07-08T00:00:00Z"
    )
    let expansion = LensFrameFormGeneration(
        generationId: "gen_2",
        mode: "expansion",
        parentOptionId: "form_a",
        options: [LensFrameFormOption(optionId: "form_c", title: "C", prompt: "Prompt C", meaningSlug: "theme.c", pole: "positive")],
        generatedAt: "2026-07-08T00:01:00Z"
    )
    let document = ProjectFrameFormsDocument(
        projectId: "proj_1",
        goalFingerprint: "fp_1",
        status: "ready",
        generations: [initial, expansion],
        updatedAt: "2026-07-08T00:01:00Z"
    )
    let data = try JSONCoding.encoder.encode(document)
    let decoded = try JSONCoding.decoder.decode(ProjectFrameFormsDocument.self, from: data)
    #expect(decoded == document)
    #expect(decoded.hasInitialGeneration)
    #expect(decoded.hasExpansion(fromOptionId: "form_a"))
    #expect(!decoded.hasExpansion(fromOptionId: "form_b"))
    #expect(!decoded.hasExpansion(fromOptionId: ""))
    #expect(decoded.allOptions.count == 3)
}

@Test func frameFormsDocumentToleratesLegacyBlobs() throws {
    // A blob persisted before newer fields existed decodes with defaults.
    let json = """
    {"project_id": "proj_1", "generations": [{"generation_id": "gen_1", "options": [{"title": "A", "prompt": "P"}]}]}
    """
    let document = try JSONCoding.decoder.decode(ProjectFrameFormsDocument.self, from: Data(json.utf8))
    #expect(document.projectId == "proj_1")
    #expect(document.status == "missing")
    #expect(document.generations.count == 1)
    #expect(document.generations[0].mode.isEmpty)
    #expect(document.generations[0].options[0].title == "A")
    #expect(!document.hasInitialGeneration)
}

@Test func frameFormOptionNormalizedTrimsAndLowercases() {
    let option = LensFrameFormOption(
        optionId: " form_1 ",
        title: "  The Beacon  ",
        prompt: "  A keeper climbs.  ",
        meaningSlug: " Theme.Beacon ",
        meaningName: " beacon ",
        pole: " Positive ",
        abstractionLevel: " Symbolic ",
        relationToParent: " contrasts_with "
    ).normalized()
    #expect(option.optionId == "form_1")
    #expect(option.title == "The Beacon")
    #expect(option.prompt == "A keeper climbs.")
    #expect(option.meaningSlug == "theme.beacon")
    #expect(option.pole == "positive")
    #expect(option.abstractionLevel == "symbolic")
    #expect(option.relationToParent == "contrasts_with")
}

@Test func formRefineComposerCarriesDirectiveContextAndDiscipline() {
    let prompt = FormRefineComposer.transformPrompt(
        current: "A solitary salvage monk crosses the cracked floor of a lunar archive.",
        directive: "this exact sentiment but on a 1950s Earth farm, one relic obviously from 2050+",
        priorDirectives: ["make the guide animal a dog"]
    )
    #expect(prompt.contains("preserving its exact sentiment"))
    #expect(prompt.contains("New direction: this exact sentiment but on a 1950s Earth farm, one relic obviously from 2050+"))
    #expect(prompt.contains("Directions already applied — keep honoring them:"))
    #expect(prompt.contains("- make the guide animal a dog"))
    #expect(prompt.contains("A solitary salvage monk crosses the cracked floor of a lunar archive."))
    #expect(prompt.contains("zero art direction"))
    #expect(prompt.contains("no color or palette words"))
    #expect(prompt.contains("one-line note"))
}

@Test func formRefineComposerOmitsEmptyPriorDirectives() {
    let prompt = FormRefineComposer.transformPrompt(
        current: "A quiet harbor at dawn.",
        directive: "set it underground",
        priorDirectives: ["  ", ""]
    )
    #expect(!prompt.contains("Directions already applied"))
    #expect(prompt.contains("New direction: set it underground"))
}
