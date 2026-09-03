import Foundation

/// What rides alongside the enriched text when it reaches the image model.
///
/// The rewrite is only honest if it knows this. The default enrichment prompt
/// tells the model its text is "sent directly to the image model with no
/// other context, so it must be complete and self-contained" — true for a
/// bare prompt, false whenever reference images ride, and the reason a
/// fourteen-word relational request ("the third frame of the loop where they
/// do a swing-dance twirl", two frames attached) came back rewritten as a
/// self-contained vintage dance hall that contradicted its own references.
enum ImagePromptReferenceMode: Equatable {
    /// Text alone reaches the model: the prompt must stand on its own.
    case textOnly
    /// A style image rides and is the sole authority on rendering, so the
    /// text must be scrubbed of art direction or it overrides the image.
    case styleReference
    /// Subject-bearing references ride: they carry identity and continuity,
    /// and the text must not invent a scene that competes with them.
    case subjectReference(count: Int)
}

/// Picks the rewrite from what a render actually transmits.
///
/// Style scrubbing outranks subject references, preserved verbatim from the
/// condition this replaced: an attached style image is the sole authority on
/// rendering, and any style language left in the text overrides it. Only once
/// that is ruled out do subject-bearing references claim the rewrite.
func imagePromptReferenceMode(
    styleMode: LensRenderStyleMode,
    promptImageReferenceMode: Bool,
    hasStyleAttachment: Bool,
    subjectReferenceCount: Int
) -> ImagePromptReferenceMode {
    let scrubsStyle = (styleMode == .attachStyleImage && !promptImageReferenceMode)
        || hasStyleAttachment
    if scrubsStyle { return .styleReference }
    guard promptImageReferenceMode, subjectReferenceCount > 0 else { return .textOnly }
    return .subjectReference(count: subjectReferenceCount)
}

/// Why an OpenAI Responses image call returned 200 with no picture.
///
/// A refusal is not a malfunction: the model understood the request and
/// declined it, and the sentence explaining why is the most useful thing the
/// operator can be handed. That sentence used to be discarded, because the
/// model delivers it as an assistant `output_text` message rather than a
/// `refusal` content part — so a traced Lens hero render reported only
/// "OpenAI Responses output did not include image data" while OpenAI's own
/// log carried "I can't help generate an image based on the attached
/// references because they include explicit nudity/sexual content."
///
/// The declination also arrives in a second traced shape: the tool itself is
/// blocked (`image_generation_call` status=failed) and the model follows it
/// with the apology. A two-reference render of a traditional Hawaiian
/// ceremony surfaced only "output contained image_generation_call
/// (status=failed), message (status=completed)" while the trailing message
/// carried "I'm sorry, but I can't help create an image that preserves the
/// exposed/thong-clad appearance from the references" — a moderation false
/// positive on ceremonial dress the operator could only have diagnosed from
/// OpenAI's own logs. Prose positioned after the failed call is the model
/// accounting for that failure and must be surfaced, not summarized away.
///
/// Every no-image response — refusal, content filter, truncation, empty tool
/// call — collapsed into that one unactionable string. This type separates
/// them, because they call for different reactions.
enum OpenAIImageFailure: Equatable {
    /// The model declined, and said why.
    case refused(String)
    /// The response stopped before producing output (`incomplete_details`).
    case incomplete(reason: String)
    /// An image call carried no result, or nothing usable came back at all.
    /// The summary names what the payload did contain.
    case resultless(summary: String)

    /// Whether resubmitting can plausibly produce a different answer.
    ///
    /// Retrying a refusal or a content filter spends tokens for a guaranteed
    /// identical outcome; only a genuinely resultless response is worth
    /// another attempt. Callers must consult this before any automatic retry.
    var isTerminal: Bool {
        switch self {
        case .refused:
            return true
        case .incomplete(let reason):
            return reason == "content_filter"
        case .resultless:
            return false
        }
    }

    /// The text stored as the take's `errorMessage`, rendered verbatim by
    /// every failed-frame surface — so it speaks to the person whose render
    /// just died, not to a log reader. A declination opens gently and
    /// apologetically, carries the model's own words (they name the
    /// offending input better than we can), and closes with the one move
    /// that can actually change the outcome: adjusting the prompt or the
    /// references. Malfunctions keep their diagnostic shape.
    var message: String {
        switch self {
        case .refused(let explanation):
            return "Sorry — OpenAI declined to render this image. Its explanation: “\(explanation)” Adjusting the wording or the reference images may help."
        case .incomplete(let reason):
            if reason == "content_filter" {
                return "Sorry — OpenAI's content filter stopped this image before it finished. Adjusting the wording or the reference images may help."
            }
            return "OpenAI stopped before finishing this image (reason: \(reason))."
        case .resultless(let summary):
            return "OpenAI returned no image: \(summary)"
        }
    }
}

enum OpenAIImageFailureClassifier {
    /// Longest explanation carried into a stored `errorMessage`. Refusals run
    /// a sentence or two; this only guards against an unbounded payload.
    static let explanationLimit = 400

    /// Reads a no-image response for the most specific cause it states.
    ///
    /// Only ever called when the payload carried no image, which is what
    /// licenses treating an assistant message as an explanation: with a
    /// picture in hand that prose would be commentary, but without one it is
    /// the model telling us why there is nothing to show.
    ///
    /// Order is most-specific-first: an explicit refusal part and a
    /// structural `incomplete` both outrank free prose, and prose outranks
    /// the generic shape summary.
    static func failure(from body: OpenAIResponsesImageBody) -> OpenAIImageFailure {
        let outputItems = body.output ?? []

        for item in outputItems where item.type == "message" {
            for part in item.content ?? [] where part.type == "refusal" {
                if let refusal = part.refusal?.trimmed, !refusal.isEmpty {
                    return .refused(truncated(refusal))
                }
            }
        }

        if body.status == "incomplete" {
            let reason = body.incompleteDetails?.reason?.trimmed
            return .incomplete(reason: reason?.nilIfEmpty ?? "unspecified")
        }

        // Output items are chronological, and position is what separates
        // narration from explanation. Prose AFTER a failed
        // image_generation_call is the model accounting for that failure —
        // the traced Hawaiian-ceremony declination rode exactly this shape
        // (failed call, then "I'm sorry, but I can't help create…") and was
        // summarized into an opaque shape string. Prose BEFORE the call is
        // narration of intent ("Generating that image now."), and a
        // still-running status (in_progress/generating) is a cut-off, so
        // both keep the malfunction reading below.
        if let failedCallIndex = outputItems.firstIndex(where: { item in
            item.type == "image_generation_call" && item.status?.trimmed == "failed"
        }) {
            for item in outputItems[(failedCallIndex + 1)...] where item.type == "message" {
                for part in item.content ?? [] where part.type == "output_text" {
                    if let text = part.text?.trimmed, !text.isEmpty {
                        return .refused(truncated(text))
                    }
                }
            }
        }

        // A status-bearing image_generation_call with no explanation after
        // it means the tool actually ran (or was cut off mid-run): prose
        // before it is commentary on a malfunction, not a declination —
        // reading it as a refusal would stamp a transient provider failure
        // terminal. A call with NO status is the traced refusal shape: the
        // model narrated instead of rendering, and the prose is the
        // explanation.
        if outputItems.contains(where: { item in
            item.type == "image_generation_call" && !(item.status?.trimmed ?? "").isEmpty
        }) {
            return .resultless(summary: shapeSummary(outputItems))
        }

        for item in outputItems where item.type == "message" {
            for part in item.content ?? [] where part.type == "output_text" {
                if let text = part.text?.trimmed, !text.isEmpty {
                    return .refused(truncated(text))
                }
            }
        }

        return .resultless(summary: shapeSummary(outputItems))
    }

    /// Names what the response actually contained, so a cause we have not
    /// seen before still arrives with evidence attached rather than silence.
    private static func shapeSummary(_ items: [OpenAIResponsesImageBody.OutputItem]) -> String {
        guard !items.isEmpty else { return "the response carried no output items" }
        let described = items.map { item -> String in
            guard let status = item.status?.trimmed, !status.isEmpty else { return item.type }
            return "\(item.type) (status=\(status))"
        }
        return "output contained \(described.joined(separator: ", "))"
    }

    private static func truncated(_ value: String) -> String {
        let compact = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard compact.count > explanationLimit else { return compact }
        return String(compact.prefix(max(0, explanationLimit - 1))) + "…"
    }
}
