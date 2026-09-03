import Foundation
import Testing
@testable import LitScenes

// MARK: Fixtures

private func body(
    status: String? = nil,
    incompleteReason: String? = nil,
    output: [OpenAIResponsesImageBody.OutputItem] = []
) -> OpenAIResponsesImageBody {
    OpenAIResponsesImageBody(
        id: "resp_test",
        model: "gpt-5.5",
        status: status,
        incompleteDetails: incompleteReason.map { OpenAIResponsesImageBody.IncompleteDetails(reason: $0) },
        output: output,
        usage: nil,
        error: nil
    )
}

private func message(_ parts: [OpenAIContentItem]) -> OpenAIResponsesImageBody.OutputItem {
    OpenAIResponsesImageBody.OutputItem(type: "message", content: parts)
}

private func imageCall(status: String?) -> OpenAIResponsesImageBody.OutputItem {
    OpenAIResponsesImageBody.OutputItem(type: "image_generation_call", status: status)
}

// MARK: Refusals — the case that used to vanish

@Test func refusalDeliveredAsOutputTextIsRead() {
    // The exact shape of the traced Lens hero failure: OpenAI explained
    // itself in an assistant message, and the old scan — which matched only
    // `refusal` parts — reported "did not include image data" instead.
    let explanation = "I can't help generate an image based on the attached references because they include explicit nudity/sexual content."
    let failure = OpenAIImageFailureClassifier.failure(from: body(output: [
        imageCall(status: nil),
        message([OpenAIContentItem(type: "output_text", text: explanation)])
    ]))
    #expect(failure == .refused(explanation))
    #expect(failure.message.contains("explicit nudity"))
    #expect(failure.isTerminal)
}

@Test func explicitRefusalPartStillWins() {
    let failure = OpenAIImageFailureClassifier.failure(from: body(output: [
        message([OpenAIContentItem(type: "refusal", refusal: "policy violation")])
    ]))
    #expect(failure == .refused("policy violation"))
}

@Test func explicitRefusalOutranksProse() {
    let failure = OpenAIImageFailureClassifier.failure(from: body(output: [
        message([
            OpenAIContentItem(type: "output_text", text: "some commentary"),
            OpenAIContentItem(type: "refusal", refusal: "the real reason")
        ])
    ]))
    #expect(failure == .refused("the real reason"))
}

@Test func blankProseDoesNotMasqueradeAsARefusal() {
    let failure = OpenAIImageFailureClassifier.failure(from: body(output: [
        message([OpenAIContentItem(type: "output_text", text: "   ")]),
        imageCall(status: "failed")
    ]))
    #expect(failure == .resultless(summary: "output contained message, image_generation_call (status=failed)"))
    // Blank prose after the failed call is equally not an explanation.
    let trailing = OpenAIImageFailureClassifier.failure(from: body(output: [
        imageCall(status: "failed"),
        message([OpenAIContentItem(type: "output_text", text: "   ")])
    ]))
    #expect(trailing == .resultless(summary: "output contained image_generation_call (status=failed), message"))
}

@Test func refusalExplainedAfterAFailedImageCallIsRead() {
    // The traced Hawaiian-ceremony declination: the moderation layer failed
    // the tool call itself, and the model's apology arrived as a completed
    // message AFTER it. The old scan treated any status-bearing call as a
    // malfunction and reported only the shape summary — the operator had to
    // read OpenAI's own logs to learn why two ceremonial-dress references
    // were declined.
    let explanation = "I’m sorry, but I can’t help create an image that preserves the exposed/thong-clad appearance from the references."
    let failure = OpenAIImageFailureClassifier.failure(from: body(output: [
        imageCall(status: "failed"),
        message([OpenAIContentItem(type: "output_text", text: explanation)])
    ]))
    #expect(failure == .refused(explanation))
    #expect(failure.isTerminal)
}

@Test func proseBeforeAFailedImageCallIsAMalfunctionNotARefusal() {
    // Position separates narration from explanation: prose BEFORE a failed
    // attempt is the model announcing intent, and stamping it a terminal
    // refusal would permanently bury a transient provider failure.
    let failure = OpenAIImageFailureClassifier.failure(from: body(output: [
        message([OpenAIContentItem(type: "output_text", text: "Generating that image now.")]),
        imageCall(status: "failed")
    ]))
    #expect(failure == .resultless(summary: "output contained message, image_generation_call (status=failed)"))
    #expect(!failure.isTerminal)
}

@Test func proseAfterAStillRunningCallStaysAMalfunction() {
    // Only a FAILED call licenses reading trailing prose as its explanation.
    // A still-running status is a cut-off response, and whatever prose
    // surrounds it is narration.
    let failure = OpenAIImageFailureClassifier.failure(from: body(output: [
        imageCall(status: "in_progress"),
        message([OpenAIContentItem(type: "output_text", text: "Working on the render.")])
    ]))
    #expect(failure == .resultless(summary: "output contained image_generation_call (status=in_progress), message"))
    #expect(!failure.isTerminal)
}

@Test func longExplanationsAreBounded() {
    let long = String(repeating: "verbose ", count: 200)
    let failure = OpenAIImageFailureClassifier.failure(from: body(output: [
        message([OpenAIContentItem(type: "output_text", text: long)])
    ]))
    guard case .refused(let text) = failure else {
        Issue.record("expected a refusal, got \(failure)")
        return
    }
    #expect(text.count <= OpenAIImageFailureClassifier.explanationLimit)
    #expect(text.hasSuffix("…"))
}

// MARK: Incomplete responses

@Test func incompleteStatusReportsItsReason() {
    let failure = OpenAIImageFailureClassifier.failure(from: body(
        status: "incomplete",
        incompleteReason: "max_output_tokens"
    ))
    #expect(failure == .incomplete(reason: "max_output_tokens"))
    #expect(failure.message.contains("max_output_tokens"))
}

@Test func incompleteWithoutAReasonStillClassifies() {
    let failure = OpenAIImageFailureClassifier.failure(from: body(status: "incomplete"))
    #expect(failure == .incomplete(reason: "unspecified"))
}

@Test func structuralIncompleteOutranksProse() {
    // Truncation and refusal call for different reactions, so a stated
    // `incomplete` must not be relabelled by whatever prose came with it.
    let failure = OpenAIImageFailureClassifier.failure(from: body(
        status: "incomplete",
        incompleteReason: "content_filter",
        output: [message([OpenAIContentItem(type: "output_text", text: "here is what I was doing")])]
    ))
    #expect(failure == .incomplete(reason: "content_filter"))
}

// MARK: Resultless

@Test func resultlessNamesWhatTheResponseDidContain() {
    let failure = OpenAIImageFailureClassifier.failure(from: body(output: [
        OpenAIResponsesImageBody.OutputItem(type: "reasoning"),
        imageCall(status: "in_progress")
    ]))
    #expect(failure == .resultless(summary: "output contained reasoning, image_generation_call (status=in_progress)"))
}

@Test func emptyOutputSaysSo() {
    let failure = OpenAIImageFailureClassifier.failure(from: body())
    #expect(failure == .resultless(summary: "the response carried no output items"))
}

// MARK: Retry policy

@Test func onlyResultlessResponsesAreWorthRetrying() {
    // Retrying a refusal or a content filter spends tokens for a guaranteed
    // identical answer.
    #expect(OpenAIImageFailure.refused("no").isTerminal)
    #expect(OpenAIImageFailure.incomplete(reason: "content_filter").isTerminal)
    #expect(!OpenAIImageFailure.incomplete(reason: "max_output_tokens").isTerminal)
    #expect(!OpenAIImageFailure.resultless(summary: "anything").isTerminal)
}

// MARK: User-facing wording

@Test func declinationsSpeakGentlyAndCarryTheModelsWords() {
    // The stored errorMessage is what the person whose render died reads on
    // the failed card: it must apologize, say what happened, quote the
    // model's own explanation, and point at the one lever that can change
    // the outcome — not read like a log line.
    let message = OpenAIImageFailure.refused("I can’t depict that attire.").message
    #expect(message.hasPrefix("Sorry — OpenAI declined to render this image."))
    #expect(message.contains("I can’t depict that attire."))
    #expect(message.contains("Adjusting the wording or the reference images may help."))
}

@Test func contentFilterStopsSpeakGentlyToo() {
    // A content-filter truncation is the same user story as a declination —
    // moderation said no — so it gets the same gentle frame; other
    // incomplete reasons keep their diagnostic shape.
    let filtered = OpenAIImageFailure.incomplete(reason: "content_filter").message
    #expect(filtered.hasPrefix("Sorry — OpenAI's content filter stopped this image"))
    #expect(filtered.contains("Adjusting the wording or the reference images may help."))
    let truncated = OpenAIImageFailure.incomplete(reason: "max_output_tokens").message
    #expect(!truncated.contains("Sorry"))
}

// MARK: Enrichment mode selection

@Test func subjectReferencesClaimTheirOwnRewrite() {
    // The swing-dance case: two library frames carrying the subject. This
    // used to fall through to the text-only rewrite, whose "self-contained"
    // premise made it invent a dance hall that contradicted the references.
    #expect(imagePromptReferenceMode(
        styleMode: .describeStyleInPrompt,
        promptImageReferenceMode: true,
        hasStyleAttachment: false,
        subjectReferenceCount: 2
    ) == .subjectReference(count: 2))
}

@Test func attachedStyleImageStillOutranksSubjectReferences() {
    // Preserved verbatim: style words left in the text override an attached
    // style image, so scrubbing wins even when subject references ride.
    #expect(imagePromptReferenceMode(
        styleMode: .attachStyleImage,
        promptImageReferenceMode: true,
        hasStyleAttachment: true,
        subjectReferenceCount: 3
    ) == .styleReference)
}

@Test func styleModeWithoutPromptImagesScrubsAsBefore() {
    #expect(imagePromptReferenceMode(
        styleMode: .attachStyleImage,
        promptImageReferenceMode: false,
        hasStyleAttachment: false,
        subjectReferenceCount: 0
    ) == .styleReference)
}

@Test func bareRequestsKeepTheTextOnlyRewrite() {
    #expect(imagePromptReferenceMode(
        styleMode: .describeStyleInPrompt,
        promptImageReferenceMode: false,
        hasStyleAttachment: false,
        subjectReferenceCount: 0
    ) == .textOnly)
    // Flag set but nothing actually riding: no reference rewrite to do.
    #expect(imagePromptReferenceMode(
        styleMode: .none,
        promptImageReferenceMode: true,
        hasStyleAttachment: false,
        subjectReferenceCount: 0
    ) == .textOnly)
}
