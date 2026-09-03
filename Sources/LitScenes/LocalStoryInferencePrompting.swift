import Foundation

// Direct-mode ports of the meaning service's SceneStory / Frame Forms prompt
// assembly, strict schemas, post-processing, and validation. The wire request
// and document types are shared with the hosted path; only transport and the
// graph-backed retrieval differ (see LocalStoryInference.swift).

// MARK: - Shared projection limits and helpers

private enum LocalProjectionLimits {
    static let priorLimit = 10
    static let listLimit = 12
    static let constraintItemRunes = 240
    static let northStarRunes = 500
    static let lookRunes = 400
    static let priorFieldRunes = 260
    static let emotionalLabelRunes = 80
    static let shortRunes = 120
    static let lockedItemLimit = 10
}

private func localCompactString(_ value: String, limit: Int) -> String {
    let clean = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    guard limit > 0, clean.count > limit else { return clean }
    return localSmartTruncate(clean, limit: limit)
}

private func localSmartTruncate(_ value: String, limit: Int) -> String {
    guard limit > 0, value.count > limit else { return value.trimmed }
    let prefix = String(value.prefix(limit))
    for boundary in [". ", "! ", "? "] {
        if let range = prefix.range(of: boundary, options: .backwards), range.lowerBound > prefix.startIndex {
            return String(prefix[..<range.upperBound]).trimmed
        }
    }
    for boundary in ["; ", ": ", ", ", " — ", " – ", " - "] {
        if let range = prefix.range(of: boundary, options: .backwards), range.lowerBound > prefix.startIndex {
            return String(prefix[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-—–"))
        }
    }
    if let range = prefix.range(of: " ", options: .backwards), range.lowerBound > prefix.startIndex {
        return String(prefix[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-—–"))
    }
    return prefix.trimmed
}

/// Truncation that never ships a clipped phrase: on overflow it retreats to a
/// sentence/clause boundary or omits the field entirely.
private func localCompactCompletePhrase(_ value: String, limit: Int) -> String {
    let clean = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    guard limit > 0, clean.count > limit else { return clean }
    let prefix = String(clean.prefix(limit))
    for boundary in [". ", "! ", "? "] {
        if let range = prefix.range(of: boundary, options: .backwards), range.lowerBound > prefix.startIndex {
            return String(prefix[..<range.upperBound]).trimmed
        }
    }
    for boundary in ["; ", ": ", " — ", " – ", " -> "] {
        if let range = prefix.range(of: boundary, options: .backwards), range.lowerBound > prefix.startIndex {
            return String(prefix[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-—–"))
        }
    }
    return ""
}

private func localCleanCompactList(_ values: [String], limit: Int, runeLimit: Int) -> [String] {
    var seen = Set<String>()
    var output: [String] = []
    for value in values {
        let clean = localCompactString(value, limit: runeLimit)
        guard !clean.isEmpty else { continue }
        let key = clean.lowercased()
        guard !seen.contains(key) else { continue }
        seen.insert(key)
        output.append(clean)
        if limit > 0, output.count >= limit { break }
    }
    return output
}

/// Encodes a wire model through JSONCoding (snake_case) into a JSON object for
/// dictionary-built model inputs.
private func localJSONObject(_ value: some Encodable) -> Any {
    guard let data = try? JSONCoding.encoder.encode(value),
          let object = try? JSONSerialization.jsonObject(with: data) else {
        return [:] as [String: Any]
    }
    return object
}

// MARK: - SceneStory instructions

enum LocalStoryInferencePrompts {
    static func sceneStoryInstructions(request: LocalSceneStoryRequest) -> String {
        let base = """
        You are LitScenes SceneStory Generator.

        Return only JSON matching the provided strict SceneStorySet schema.

        Use the compact user JSON as the complete creative brief. Treat omitted provenance, source passages, search candidates, scores, UUIDs, and rejected candidates as unavailable.

        Priority:
        1. Goal, success criteria, required entities, explicit constraints, and audience shift.
        2. One coherent cause-and-effect Story.
        3. Saved resolved visual treatment.
        4. Optional meaning line.
        5. Novelty.

        The visual treatment is the user-approved resolved Lens language. Follow it as provided. Do not reintroduce source aesthetic taxonomy or invent a different visual treatment.

        Use required entities according to their stated roles. Every supplied required entity is mandatory and must be an active part of the Story rather than a decorative substitution. Do not invent additional named people, organizations, or places.

        Every Scene must advance the same Story. Demonstrate success criteria through plausible action, behavior, objects, process, sensory evidence, visible consequence, or audience response as appropriate to the project. Do not treat success criteria as independent factual evidence; factual assertions require explicit authorization from Goal text, structured fact fields, or media anchors.

        Goal fit outranks structural novelty. If task_controls.architecture_family is unspecified, devise the simplest natural cause-and-effect Story first, then classify it with the best-fitting concrete architecture family. Architecture families may repeat. If architecture_family is specified, satisfy it exactly.

        When media_anchors is empty, source_media_refs must be [] in every Scene. When no meaning-edge references are supplied, meaning_edges_used and meaning_relation_sequence must be []. Never invent reference identifiers, slugs, media IDs, frame IDs, source works, or provenance.
        """
        return [
            base,
            modeContract(request.wire.generationMode),
            groundingContract(hasMediaAnchors: !request.wire.mediaAnchors.isEmpty),
            architectureContract(request.wire.generationIntent.architectureFamily)
        ].joined(separator: "\n\n")
    }

    private static func modeContract(_ mode: StoryGenerationMode) -> String {
        switch mode {
        case .moreLikeSelected:
            return """
            MODE: MORE LIKE THIS
            - Preserve only memory.preserve.
            - Vary memory.vary materially.
            - Resemblance in preserved dimensions is expected.
            """
        case .branchSelected:
            return """
            MODE: BRANCH
            - Resemblance to the parent is expected.
            - Preserve requested parent constraints and locked material.
            - Change only requested branch dimensions.
            """
        case .reflowSelected:
            return """
            MODE: REFLOW
            - Keep the same Story identity conceptually.
            - Preserve locked or requested material.
            - Improve emotional handoffs, meaning placement, visible proof, and continuity.
            """
        case .ignoreHistory:
            return """
            MODE: IGNORE HISTORY
            - Ignore prior Story signatures, but still build one focused Story instead of a montage.
            """
        case .avoidOverlap:
            return """
            MODE: AVOID OVERLAP
            - Do not repeat a prior Story's combination of causal mechanism, central visual image, and ending consequence.
            - Prefer material differences in at least two additional Blueprint dimensions.
            - Changing only a prop, setting label, graphic treatment, interface, or camera treatment is not meaningful novelty.
            - Architecture families may repeat; do not select an architecture merely because it is absent from memory.
            - When novelty conflicts with Goal fit, success criteria, required entities, explicit constraints, or natural behavior, preserve Goal fit.
            """
        }
    }

    private static func groundingContract(hasMediaAnchors: Bool) -> String {
        if !hasMediaAnchors {
            return """
            GROUNDING AND DIALOGUE
            - No media anchors are supplied.
            - Do not invent dialect, vernacular imitation, culturally marked phrasing, participant testimony, additional named people, additional named organizations, additional named places, documented events, documented transactions, or factual quotations.
            - Dialogue may be plain generated_plain or generated_placeholder only when it has an essential dramatic job.
            - Exact user-supplied project language may be repeated verbatim.
            """
        }
        return """
        GROUNDING AND DIALOGUE
        - Media anchors are visual/factual evidence, not sourced speech unless explicit transcript text is supplied.
        - Mark dialogue provenance as user_supplied, media_transcript, generated_plain, or generated_placeholder.
        - Do not imply invented composite people, organizations, places, events, transactions, or quotations are documented facts.
        """
    }

    private static func architectureContract(_ family: StoryArchitectureFamily) -> String {
        switch family {
        case .embodiedChoice:
            return """
            STORY ARCHITECTURE: EMBODIED CHOICE
            - Center one actor making a consequential choice under pressure.
            - The final proof must be the consequence of that choice, not only a restatement of intent.
            """
        case .systemReconfiguration:
            return """
            STORY ARCHITECTURE: SYSTEM RECONFIGURATION
            - Center a process, dependency, rule, infrastructure, or feedback loop that fails and is materially reconfigured.
            - The payoff must be a changed system state, not merely awareness or agreement.
            """
        case .symbolicInversion:
            return """
            STORY ARCHITECTURE: SYMBOLIC INVERSION
            - Center one object or place whose meaning visibly reverses or transforms.
            - End with a material image or consequence that proves the reversal.
            """
        case .investigationRevelation:
            return """
            STORY ARCHITECTURE: INVESTIGATION AND REVELATION
            - Structure the Story around discovering a hidden relationship, contradiction, cause, or cost.
            - The payoff is the revelation changing a decision, not a presentation of accumulated evidence.
            """
        case .obstacleCountermove:
            return """
            STORY ARCHITECTURE: OBSTACLE AND COUNTERMOVE
            - Give the Story a concrete opposing force or constraint and make the decisive action a counter-move with visible consequence.
            - Do not resolve the Story through explanation alone.
            """
        case .ritualDecision:
            return """
            STORY ARCHITECTURE: RITUAL OR PUBLIC DECISION
            - Center a consequential choice made through a ritual, vote, wager, sacrifice, or declaration.
            - The ritual must alter material behavior; ceremony alone is insufficient.
            """
        case .unspecified:
            return """
            STORY ARCHITECTURE
            - First devise the simplest natural cause-and-effect Story that serves the Goal.
            - Then classify it with one concrete architecture family in story_blueprint.
            - Architecture families may repeat; do not use the taxonomy as an unused-category checklist.
            """
        }
    }

    static func frameFormsInstructions(expansion: Bool) -> String {
        var text = """
        You are the LitScenes Frame Form Generator. Return only JSON matching the strict schema.

        For each of the three option slots, write a story-rich single-image scene description
        (2-4 sentences): a concrete subject caught mid-action or mid-consequence, a specific
        place, and one readable dramatic tension drawn from the slot's meaning node and pole
        expression. Present tense, plain prose, no markdown, no quotes.

        HARD BAN - style vocabulary. The application attaches style reference images; any
        style words in your text override those images and break the render. Never mention:
        art movements, artist or film references, mediums (oil, watercolor, ink, film grain,
        35mm), render or quality terms (cinematic, photorealistic, 8k, HDR, concept art),
        color-grading or palette words, lighting-style jargon (volumetric, golden hour as a
        look, rim light), lens or camera language. Physical light sources that exist in the
        scene (a lamp, a fire, a window at dusk) are allowed as story objects.

        Respect each node's boundary note: it states what the concept is NOT; never build the
        scene on excluded territory. The style fit context, when present, is given ONLY so you
        choose subjects that sit naturally in that style - never echo its words.

        The three options must be materially different from one another in subject, setting,
        and dramatic mechanism. Give each a 2-5 word content-only title.
        """
        if expansion {
            text += """


            ROUTE SO FAR: the user selected a form (title and gist supplied in the input). Each new
            option must read as a branch from that selection via its slot's relation_to_parent
            (contrasts_with = stage the opposing value; inverts = flip the situation's direction;
            intensifies = escalate the same force; resolves = show the tension settling). Do not
            restate the selected gist or any prior_form_gists; avoid their subjects and settings.
            """
        }
        return text
    }
}

// MARK: - SceneStory model-input projection

enum LocalSceneStoryProjection {
    static func modelInput(request: LocalSceneStoryRequest) -> [String: Any] {
        let wire = request.wire
        let brief = resolvedBrief(wire)
        let shiftFrom = conciseCompassLabels(brief.emotionalStart)
        let shiftTo = conciseCompassLabels(brief.emotionalDestination)

        var creativeBrief: [String: Any] = [
            "north_star": localCompactString(
                wire.goal.goal.trimmed.isEmpty ? brief.audienceEffect : wire.goal.goal,
                limit: LocalProjectionLimits.northStarRunes
            ),
            "audience_shift": ["from": shiftFrom, "to": shiftTo],
            "success_criteria": localCleanCompactList(
                wire.goal.successCriteria,
                limit: LocalProjectionLimits.listLimit,
                runeLimit: LocalProjectionLimits.constraintItemRunes
            ),
            "required_entities": requiredEntities(wire),
            "constraints": constraintProjection(wire),
            "claim_policy": claimPolicy
        ]
        setNonEmpty(&creativeBrief, "audience", localCompactString(wire.goal.audience, limit: LocalProjectionLimits.constraintItemRunes))
        setNonEmpty(&creativeBrief, "audience_effect", localCompactString(brief.audienceEffect, limit: LocalProjectionLimits.northStarRunes))
        setNonEmpty(&creativeBrief, "tone_policy", localCompactString(brief.tonePolicy, limit: LocalProjectionLimits.constraintItemRunes))
        setNonEmpty(&creativeBrief, "grounding_policy", localCompactString(brief.groundingPolicy, limit: LocalProjectionLimits.constraintItemRunes))
        setNonEmpty(&creativeBrief, "evidence_policy", localCompactString(brief.evidencePolicy, limit: LocalProjectionLimits.constraintItemRunes))
        setNonEmpty(&creativeBrief, "meaning_line", meaningLine(wire))
        setNonEmpty(&creativeBrief, "meaning_tension", meaningTension(wire))

        var storyTask: [String: Any] = [
            "story_form": brief.storyForm.rawValue,
            "story_count": wire.storyCount,
            "scene_count": wire.scenesPerStory,
            "beats_per_scene": wire.beatsPerScene,
            "priority": "Goal fit, success criteria, required entities, explicit constraints, and audience shift outrank novelty."
        ]
        if wire.outputProfile.durationTargetSeconds > 0 {
            storyTask["duration_seconds"] = wire.outputProfile.durationTargetSeconds
        }

        let maxChanges = max(wire.generationIntent.beatContract.maxMajorStateChanges, 1)
        var taskControls: [String: Any] = [
            "generation_mode": wire.generationMode.rawValue,
            "architecture_family": wire.generationIntent.architectureFamily.rawValue,
            "compass_locks": wire.generationIntent.compassLocks.prefix(LocalProjectionLimits.listLimit).map(localJSONObject),
            "avoid_structures": wire.generationIntent.avoidStructures.map(localJSONObject),
            "max_major_state_changes": maxChanges <= 0 ? 2 : maxChanges,
            "emotional_start": compassLocks(fromLabels: shiftFrom, scope: "story_start"),
            "emotional_destination": compassLocks(fromLabels: shiftTo, scope: "story_end")
        ]
        setNonEmpty(&taskControls, "retry_correction", localCompactString(request.retryCorrection, limit: LocalProjectionLimits.northStarRunes))

        return [
            "creative_brief": creativeBrief,
            "visual_treatment": visualTreatment(wire),
            "story_task": storyTask,
            "task_controls": taskControls,
            "media_anchors": mediaAnchors(wire.mediaAnchors),
            "memory": memoryProjection(wire.storyMemory, currentSessionId: wire.generationSessionId)
        ]
    }

    /// The brief with the service's fallback rules applied (audience effect,
    /// grounding/tone/evidence policies) so the model never sees empty policy.
    private static func resolvedBrief(_ wire: SceneStoryGenerateRequest) -> SceneStoryGenerationBrief {
        var brief = wire.storyGenerationBrief.normalized()
        if brief.audienceEffect.isEmpty {
            brief.audienceEffect = [wire.goal.desiredResponse, wire.goal.viewerExperience, wire.goal.goal]
                .map(\.trimmed).first { !$0.isEmpty } ?? ""
        }
        if brief.groundingPolicy.isEmpty {
            brief.groundingPolicy = groundingPolicyText(wire.groundingMode, hasMediaAnchors: !wire.mediaAnchors.isEmpty)
        }
        if brief.tonePolicy.isEmpty {
            brief.tonePolicy = "Use tone from the Goal and Ready Lenses; do not impose a global house style."
        }
        if brief.evidencePolicy.isEmpty {
            brief.evidencePolicy = evidencePolicyText(wire.groundingMode)
        }
        return brief
    }

    private static func groundingPolicyText(_ mode: StoryGroundingMode, hasMediaAnchors: Bool) -> String {
        switch mode {
        case .mediaBound:
            return "Stay close to supplied media evidence; mark unsupported material as weak or invented."
        case .inventive:
            return "Invent visual material when useful, but disclose invented elements and avoid false factual claims."
        case .balanced:
            if hasMediaAnchors {
                return "Balance supplied media evidence with Goal and Lens interpretation."
            }
            return "No media anchors were supplied; use Goal and Lens interpretation while disclosing invented material."
        }
    }

    private static func evidencePolicyText(_ mode: StoryGroundingMode) -> String {
        switch mode {
        case .mediaBound:
            return "Factual claims require media, transcript, user, or Goal evidence; otherwise use visual metaphor or mark invented."
        case .inventive:
            return "Invented staging is allowed; real-world claims, testimony, names, and quotations still require supplied evidence."
        case .balanced:
            return "Distinguish media-supported, lens-supported, goal-inferred, invented, and weak evidence at Beat level."
        }
    }

    private static let claimPolicy: [String] = [
        "Success criteria describe what the Story should accomplish or communicate; do not treat them as independent factual evidence.",
        "Only make factual assertions that are explicitly supplied and authorized by Goal text, structured fact fields, or media anchors.",
        "Do not convert tone, metaphor, satire, or contrast into unsupported factual claims.",
        "Do not add medical, legal, financial, safety, performance, or comparative-efficacy claims unless they are explicitly supplied and authorized."
    ]

    private static func constraintProjection(_ wire: SceneStoryGenerateRequest) -> [String] {
        localCleanCompactList(
            wire.goal.constraints + wire.toneConstraints + wire.operatorInstructions,
            limit: LocalProjectionLimits.listLimit,
            runeLimit: LocalProjectionLimits.constraintItemRunes
        )
    }

    private static func requiredEntities(_ wire: SceneStoryGenerateRequest) -> [[String: Any]] {
        var output: [[String: Any]] = []
        for entity in wire.goal.requiredEntities {
            let name = localCompactString(entity.name, limit: LocalProjectionLimits.shortRunes)
            guard !name.isEmpty else { continue }
            if let index = output.firstIndex(where: { ($0["name"] as? String)?.lowercased() == name.lowercased() }) {
                if (output[index]["role"] as? String)?.isEmpty ?? true {
                    output[index]["role"] = localCompactString(entity.role, limit: LocalProjectionLimits.shortRunes)
                }
                output[index]["required"] = ((output[index]["required"] as? Bool) ?? false) || entity.required
                continue
            }
            output.append([
                "name": name,
                "role": localCompactString(entity.role, limit: LocalProjectionLimits.shortRunes),
                "required": entity.required
            ])
        }
        return output
    }

    private static func meaningLine(_ wire: SceneStoryGenerateRequest) -> String {
        for ref in wire.goal.meaningNodeRefs where !isTensionRef(ref) {
            let line = localCompactString(ref.evidence, limit: LocalProjectionLimits.constraintItemRunes)
            if !line.isEmpty { return line }
        }
        return localCompactString(wire.lens.claim, limit: LocalProjectionLimits.constraintItemRunes)
    }

    private static func meaningTension(_ wire: SceneStoryGenerateRequest) -> String {
        for ref in wire.goal.meaningNodeRefs where isTensionRef(ref) {
            let line = localCompactString(ref.evidence, limit: LocalProjectionLimits.constraintItemRunes)
            if !line.isEmpty { return line }
        }
        return ""
    }

    private static func isTensionRef(_ ref: ProjectGoalMeaningNodeRef) -> Bool {
        let kind = ref.kind.rawValue.lowercased()
        let role = ref.role.rawValue.lowercased()
        return kind == "value_tension" || role == "value_tension" || role == "tension"
    }

    private static func visualTreatment(_ wire: SceneStoryGenerateRequest) -> [String: Any] {
        guard let resolved = wire.lens.resolvedVisualLanguage else {
            return [
                "look": localCompactString(wire.lens.visualSummary, limit: LocalProjectionLimits.lookRunes),
                "palette": [String](),
                "materials": [String](),
                "product_treatment": [String](),
                "motifs": [String](),
                "composition": [String](),
                "pacing_energy": [String](),
                "avoid": [String]()
            ]
        }
        func list(_ values: [String]) -> [String] {
            localCleanCompactList(values, limit: LocalProjectionLimits.listLimit, runeLimit: LocalProjectionLimits.constraintItemRunes)
        }
        return [
            "look": localCompactString(resolved.look, limit: LocalProjectionLimits.lookRunes),
            "palette": list(resolved.palette),
            "materials": list(resolved.materials),
            "product_treatment": list(resolved.productTreatment),
            "motifs": list(resolved.motifs),
            "composition": list(resolved.composition),
            "pacing_energy": list(resolved.pacingEnergy),
            "avoid": list(resolved.avoid)
        ]
    }

    private static func conciseCompassLabels(_ locks: [CompassLock]) -> [String] {
        let values = locks.compactMap { lock -> String? in
            let clean = localCompactString(lock.text, limit: LocalProjectionLimits.emotionalLabelRunes)
            guard !clean.isEmpty else { return nil }
            let paragraphLike = clean.split(separator: " ").count > 7 || clean.contains(".")
            return paragraphLike ? nil : clean
        }
        return localCleanCompactList(values, limit: 6, runeLimit: LocalProjectionLimits.emotionalLabelRunes)
    }

    private static func compassLocks(fromLabels labels: [String], scope: String) -> [[String: Any]] {
        labels.compactMap { label in
            let clean = localCompactString(label, limit: LocalProjectionLimits.emotionalLabelRunes)
            guard !clean.isEmpty else { return nil }
            return ["scope": scope, "kind": "label", "text": clean]
        }
    }

    private static func mediaAnchors(_ anchors: [SceneStoryMediaAnchor]) -> [[String: Any]] {
        var output: [[String: Any]] = []
        for anchor in anchors {
            let mediaId = anchor.mediaId.trimmed
            guard !mediaId.isEmpty else { continue }
            var entry: [String: Any] = [
                "media_id": mediaId,
                "observed_symbols": localCleanCompactList(anchor.observedSymbols, limit: LocalProjectionLimits.listLimit, runeLimit: LocalProjectionLimits.shortRunes),
                "aesthetic_terms": localCleanCompactList(anchor.aestheticTerms, limit: LocalProjectionLimits.listLimit, runeLimit: LocalProjectionLimits.shortRunes),
                "negative_constraints": localCleanCompactList(anchor.negativeConstraints, limit: LocalProjectionLimits.listLimit, runeLimit: LocalProjectionLimits.shortRunes)
            ]
            setNonEmpty(&entry, "frame_id", localCompactString(anchor.frameId, limit: LocalProjectionLimits.shortRunes))
            setNonEmpty(&entry, "kind", localCompactString(anchor.kind, limit: LocalProjectionLimits.shortRunes))
            setNonEmpty(&entry, "role", localCompactString(anchor.role, limit: LocalProjectionLimits.shortRunes))
            setNonEmpty(&entry, "summary", localCompactString(anchor.summary, limit: LocalProjectionLimits.constraintItemRunes))
            output.append(entry)
            if output.count >= LocalProjectionLimits.listLimit { break }
        }
        return output
    }

    private static func memoryProjection(_ memory: StoryMemoryRequest, currentSessionId: String) -> [String: Any] {
        let mode = memory.mode
        var projection: [String: Any] = [
            "mode": mode.rawValue,
            "preserve": preserveProjection(mode: mode, values: memory.preserveDimensions),
            "vary": varyProjection(mode: mode, values: memory.varyDimensions),
            "prior_concepts": [[String: Any]]()
        ]
        switch mode {
        case .ignoreHistory:
            break
        case .moreLikeSelected:
            if let reference = referenceProjection(memory.positiveReferenceStory ?? firstSignatureReference(memory)) {
                projection["positive_reference"] = reference
            }
        case .branchSelected:
            if let reference = referenceProjection(memory.branchParentStory ?? firstSignatureReference(memory)) {
                projection["branch_parent"] = reference
            }
        case .reflowSelected:
            if let reference = reflowProjection(memory.reflowSelectedStory ?? firstSignatureReference(memory)) {
                projection["reflow_selection"] = reference
            }
        case .avoidOverlap:
            projection["prior_concepts"] = priorConcepts(memory.priorStorySignatures, currentSessionId: currentSessionId)
        }
        return projection
    }

    private static func firstSignatureReference(_ memory: StoryMemoryRequest) -> StoryMemoryReference? {
        guard let first = memory.priorStorySignatures.first else { return nil }
        return StoryMemoryReference(referenceKind: "prior_story", signature: first)
    }

    private static func preserveProjection(mode: StoryGenerationMode, values: [String]) -> [String] {
        let clean = cleanNoveltyDimensions(values)
        if clean.isEmpty, mode == .avoidOverlap {
            return ["project anchors", "success criteria", "tone", "audience destination"]
        }
        return clean
    }

    private static func varyProjection(mode: StoryGenerationMode, values: [String]) -> [String] {
        let clean = cleanNoveltyDimensions(values)
        if clean.isEmpty, mode == .avoidOverlap {
            return ["central dramatic question", "causal mechanism", "setting category", "central visual image", "ending consequence"]
        }
        return clean
    }

    private static func cleanNoveltyDimensions(_ values: [String]) -> [String] {
        let mapped = values.map { value -> String in
            let clean = localCompactString(value, limit: LocalProjectionLimits.shortRunes)
            switch clean.lowercased() {
            case "story engine", "action engine": return "causal mechanism"
            case "setting": return "setting category"
            default: return clean
            }
        }
        return localCleanCompactList(mapped, limit: LocalProjectionLimits.listLimit, runeLimit: LocalProjectionLimits.shortRunes)
    }

    private static func referenceProjection(_ ref: StoryMemoryReference?) -> [String: Any]? {
        guard let ref else { return nil }
        var projection: [String: Any] = [
            "concept": priorConcept(from: ref.signature, includeArchitecture: true)
        ]
        setNonEmpty(&projection, "reference_kind", localCompactString(ref.referenceKind, limit: LocalProjectionLimits.shortRunes))
        setNonEmpty(&projection, "story_suggestion_id", localCompactString(ref.storySuggestionId, limit: LocalProjectionLimits.shortRunes))
        setNonEmpty(&projection, "project_story_id", localCompactString(ref.projectStoryId, limit: LocalProjectionLimits.shortRunes))
        setNonEmpty(&projection, "story_version_id", localCompactString(ref.storyVersionId, limit: LocalProjectionLimits.shortRunes))
        return projection
    }

    private static func reflowProjection(_ ref: StoryMemoryReference?) -> [String: Any]? {
        guard var projection = referenceProjection(ref) else { return nil }
        projection["locked_material"] = lockedMaterial(ref?.storySnapshot)
        return projection
    }

    private static func priorConcepts(_ signatures: [StorySignatureDocument], currentSessionId: String) -> [[String: Any]] {
        var output: [[String: Any]] = []
        var seen = Set<String>()
        for signature in orderedSignatures(signatures, currentSessionId: currentSessionId) {
            let concept = priorConcept(from: signature, includeArchitecture: false)
            let key = ["causal_mechanism", "setting_category", "central_visual_image", "ending_consequence"]
                .map { (concept[$0] as? String ?? "").lowercased() }
                .joined(separator: "|")
            guard key != "|||", !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(concept)
            if output.count >= LocalProjectionLimits.priorLimit { break }
        }
        return output
    }

    private static func orderedSignatures(_ signatures: [StorySignatureDocument], currentSessionId: String) -> [StorySignatureDocument] {
        let sessionId = currentSessionId.trimmed
        var groups: [[StorySignatureDocument]] = [[], [], [], []]
        for signature in signatures {
            if !sessionId.isEmpty, signature.generationSessionId.trimmed.caseInsensitiveCompare(sessionId) == .orderedSame {
                groups[0].append(signature)
            } else if signature.contextClass == .sameSession {
                groups[1].append(signature)
            } else if signature.contextClass == .currentContext {
                groups[2].append(signature)
            } else {
                groups[3].append(signature)
            }
        }
        return groups.flatMap { $0 }
    }

    private static func priorConcept(from signature: StorySignatureDocument, includeArchitecture: Bool) -> [String: Any] {
        let blueprint = signature.storyBlueprint
        var concept: [String: Any] = [:]
        if includeArchitecture {
            concept["architecture_family"] = blueprint.architectureFamily.rawValue
        }
        setNonEmpty(&concept, "causal_mechanism", localCompactCompletePhrase(blueprint.causalEngine, limit: LocalProjectionLimits.priorFieldRunes))
        setNonEmpty(&concept, "setting_category", localCompactCompletePhrase(
            settingSummary(blueprint.settingProgression, fallback: signature.primarySetting),
            limit: LocalProjectionLimits.priorFieldRunes
        ))
        setNonEmpty(&concept, "central_visual_image", localCompactCompletePhrase(
            blueprint.coreVisualImage.trimmed.isEmpty ? signature.coreVisualImage : blueprint.coreVisualImage,
            limit: LocalProjectionLimits.priorFieldRunes
        ))
        setNonEmpty(&concept, "ending_consequence", localCompactCompletePhrase(
            blueprint.payoffMechanism.trimmed.isEmpty ? signature.payoffOrEnding : blueprint.payoffMechanism,
            limit: LocalProjectionLimits.priorFieldRunes
        ))
        return concept
    }

    private static func settingSummary(_ progression: [String], fallback: String) -> String {
        let clean = localCleanCompactList(progression, limit: 6, runeLimit: LocalProjectionLimits.priorFieldRunes)
        switch clean.count {
        case 0: return fallback
        case 1: return clean[0]
        default: return "start: \(clean[0]); end: \(clean[clean.count - 1])"
        }
    }

    private static func lockedMaterial(_ story: SceneStory?) -> [String] {
        guard let story else { return [] }
        var locked: [String] = []
        for scene in story.scenes {
            if scene.locked {
                locked.append("Scene: \(scene.title.trimmed.isEmpty ? scene.sceneDescription : scene.title)")
            }
            for beat in scene.sceneBeats where beat.locked {
                let text = [beat.beatDescription, beat.action, beat.promptSeed].map(\.trimmed).first { !$0.isEmpty } ?? ""
                locked.append("Beat: \(text)")
                if locked.count >= LocalProjectionLimits.lockedItemLimit { break }
            }
            if locked.count >= LocalProjectionLimits.lockedItemLimit { break }
        }
        return localCleanCompactList(locked, limit: LocalProjectionLimits.lockedItemLimit, runeLimit: LocalProjectionLimits.priorFieldRunes)
    }
}

private func setNonEmpty(_ dictionary: inout [String: Any], _ key: String, _ value: String) {
    guard !value.isEmpty else { return }
    dictionary[key] = value
}

// MARK: - Strict JSON schemas

enum LocalStoryInferenceSchemas {
    static func sceneStorySet(
        request: LocalSceneStoryRequest,
        userId: String,
        generatedAt: String,
        model: String
    ) -> [String: Any] {
        let wire = request.wire
        return object(
            [
                "schema_version": stringConst("litscenes.scene_story_set.v0.4"),
                "user_id": stringConst(userId),
                "project_id": stringConst(wire.projectId),
                "goal_fingerprint": stringConst(wire.goalFingerprint),
                "lens_id": stringConst(wire.lensId),
                "lens_context_fingerprint": stringConst(wire.lensContextFingerprint),
                "story_count": intConst(wire.storyCount),
                "scenes_per_story": intConst(wire.scenesPerStory),
                "beats_per_scene": intConst(wire.beatsPerScene),
                "generated_at": stringConst(generatedAt),
                "generator": stringConst("openai"),
                "model": stringConst(model),
                "scene_stories": array(sceneStory(scenesPerStory: wire.scenesPerStory, beatsPerScene: wire.beatsPerScene), min: wire.storyCount, max: wire.storyCount),
                "operator_feedback": array(operatorFeedback, min: 0, max: 12),
                "warnings": array(string, min: 0, max: 24)
            ],
            required: [
                "schema_version", "user_id", "project_id", "goal_fingerprint", "lens_id",
                "lens_context_fingerprint", "story_count", "scenes_per_story", "beats_per_scene",
                "generated_at", "generator", "model", "scene_stories", "operator_feedback", "warnings"
            ]
        )
    }

    private static func sceneStory(scenesPerStory: Int, beatsPerScene: Int) -> [String: Any] {
        object(
            [
                "story_id": string,
                "order": integer,
                "title": string,
                "premise": string,
                "meaning_thesis": string,
                "tone": string,
                "visual_world": string,
                "emotional_arc": storyEmotionalArc,
                "story_blueprint": storyBlueprint,
                "reasoning_summary": reasoningSummary,
                "meaning_edges_used": array(meaningEdgeRef, min: 0, max: 12),
                "meaning_relation_sequence": array(meaningRelationMove, min: 0, max: 16),
                "invented_elements": array(string, min: 0, max: 24),
                "concerns": array(string, min: 0, max: 12),
                "scenes": array(scene(beatsPerScene: beatsPerScene), min: scenesPerStory, max: scenesPerStory)
            ],
            required: [
                "story_id", "order", "title", "premise", "meaning_thesis", "tone", "visual_world",
                "emotional_arc", "story_blueprint", "reasoning_summary", "meaning_edges_used",
                "meaning_relation_sequence", "invented_elements", "concerns", "scenes"
            ]
        )
    }

    private static var compassPoint: [String: Any] {
        object(
            [
                "labels": array(string, min: 1, max: 6),
                "typed_labels": array(typedCompassLabel, min: 1, max: 6),
                "valence": coordinate,
                "activation": coordinate,
                "agency": coordinate
            ],
            required: ["labels", "typed_labels", "valence", "activation", "agency"]
        )
    }

    private static var typedCompassLabel: [String: Any] {
        object(
            [
                "kind": enumeration(["feeling", "agency_posture", "activation_posture", "image", "label"]),
                "text": string
            ],
            required: ["kind", "text"]
        )
    }

    private static var storyBlueprint: [String: Any] {
        object(
            [
                "story_form": enumeration([
                    "dramatic_arc", "documentary_portrait", "process_explainer", "product_demo",
                    "lyrical_montage", "ambient_sequence", "abstract_visual_poem",
                    "testimonial_interview", "instructional_sequence"
                ]),
                "architecture_family": enumeration([
                    "embodied_choice", "system_reconfiguration", "symbolic_inversion",
                    "investigation_revelation", "obstacle_countermove", "ritual_decision"
                ]),
                "primary_actor": string,
                "acting_force": string,
                "causal_engine": string,
                "setting_progression": array(string, min: 1, max: 6),
                "primary_meaning_move": string,
                "compass_destination": string,
                "payoff_mechanism": string,
                "core_visual_image": string
            ],
            required: [
                "story_form", "architecture_family", "primary_actor", "acting_force", "causal_engine",
                "setting_progression", "primary_meaning_move", "compass_destination",
                "payoff_mechanism", "core_visual_image"
            ]
        )
    }

    private static var reasoningSummary: [String: Any] {
        object(
            ["why_this_form": string, "why_this_arc": string, "why_this_payoff": string],
            required: ["why_this_form", "why_this_arc", "why_this_payoff"]
        )
    }

    private static var storyEmotionalArc: [String: Any] {
        object(
            [
                "start": compassPoint,
                "end": compassPoint,
                "arc_shape": enumeration(["build", "descent", "turn", "release", "spiral", "unresolved"])
            ],
            required: ["start", "end", "arc_shape"]
        )
    }

    private static var sceneEmotionalArc: [String: Any] {
        object(
            [
                "entry": compassPoint,
                "exit": compassPoint,
                "primary_turn": string,
                "inherited_from_story": boolean,
                "override_note": string
            ],
            required: ["entry", "exit", "primary_turn", "inherited_from_story", "override_note"]
        )
    }

    private static var beatEmotionalTurn: [String: Any] {
        object(
            [
                "entry": compassPoint,
                "exit": compassPoint,
                "turn_description": string,
                "observable_evidence": array(string, min: 1, max: 8),
                "performance_direction": array(string, min: 0, max: 8),
                "avoid_emotional_cliches": array(string, min: 0, max: 10)
            ],
            required: [
                "entry", "exit", "turn_description", "observable_evidence",
                "performance_direction", "avoid_emotional_cliches"
            ]
        )
    }

    private static var meaningRelationMove: [String: Any] {
        object(
            [
                "relation_type": string,
                "selected_slug": string,
                "neighbor_slug": string,
                "story_stage": enumeration(["setup", "pressure", "turn", "payoff", "counterpoint", "recurrence"]),
                "dramatic_operation": enumeration(["seed", "contrast", "intensify", "invert", "transform", "resolve"]),
                "scene_id": string,
                "beat_id": string,
                "natural_language": string
            ],
            required: [
                "relation_type", "selected_slug", "neighbor_slug", "story_stage",
                "dramatic_operation", "scene_id", "beat_id", "natural_language"
            ]
        )
    }

    private static var meaningEdgeRef: [String: Any] {
        object(
            [
                "selected_slug": string,
                "direction": string,
                "relation_type": string,
                "neighbor_slug": string,
                "natural_language": string
            ],
            required: ["selected_slug", "direction", "relation_type", "neighbor_slug", "natural_language"]
        )
    }

    private static func scene(beatsPerScene: Int) -> [String: Any] {
        object(
            [
                "scene_id": string,
                "order": integer,
                "title": string,
                "scene_function": enumeration(["hook", "setup", "development", "escalation", "turn", "payoff", "button", "other"]),
                "scene_description": string,
                "meaning_focus": string,
                "emotional_arc": sceneEmotionalArc,
                "primary_meaning_move": string,
                "source_media_refs": array(mediaRef, min: 0, max: 12),
                "support_status": enumeration(["media_supported", "lens_supported", "goal_inferred", "invented", "weak"]),
                "concerns": array(string, min: 0, max: 12),
                "scene_beats": array(beat, min: beatsPerScene, max: beatsPerScene)
            ],
            required: [
                "scene_id", "order", "title", "scene_function", "scene_description", "meaning_focus",
                "emotional_arc", "primary_meaning_move", "source_media_refs", "support_status",
                "concerns", "scene_beats"
            ]
        )
    }

    private static var mediaRef: [String: Any] {
        object(
            [
                "media_id": string,
                "frame_id": string,
                "role": enumeration(["source", "reference", "avoid", "inspiration", "other"]),
                "rationale": string
            ],
            required: ["media_id", "frame_id", "role", "rationale"]
        )
    }

    private static var beat: [String: Any] {
        object(
            [
                "beat_id": string,
                "order": integer,
                "beat_description": string,
                "shot_type": enumeration(["wide_action", "medium_action", "close_detail", "reaction", "insert", "transition", "establishing", "other"]),
                "camera": string,
                "action": string,
                "subjects": array(string, min: 0, max: 12),
                "setting": string,
                "emotional_turn": beatEmotionalTurn,
                "meaning_proof": string,
                "support_status": enumeration(["media_supported", "lens_supported", "goal_inferred", "invented", "weak"]),
                "evidence_basis": string,
                "dialogue": array(dialogueLine, min: 0, max: 8),
                "major_state_changes": array(string, min: 1, max: 2),
                "motion": string,
                "lighting": string,
                "composition": string,
                "continuity_in": string,
                "continuity_out": string,
                "prompt_seed": string,
                "negative_constraints": array(string, min: 0, max: 12)
            ],
            required: [
                "beat_id", "order", "beat_description", "shot_type", "camera", "action", "subjects",
                "setting", "emotional_turn", "meaning_proof", "support_status", "evidence_basis",
                "dialogue", "major_state_changes", "motion", "lighting", "composition",
                "continuity_in", "continuity_out", "prompt_seed", "negative_constraints"
            ]
        )
    }

    private static var dialogueLine: [String: Any] {
        object(
            [
                "speaker": string,
                "line": string,
                "delivery": string,
                "provenance": enumeration(["user_supplied", "media_transcript", "generated_plain", "generated_placeholder"])
            ],
            required: ["speaker", "line", "delivery", "provenance"]
        )
    }

    private static var operatorFeedback: [String: Any] {
        object(
            [
                "severity": enumeration(["info", "warning", "concern"]),
                "subject": string,
                "message": string,
                "recommendation": string
            ],
            required: ["severity", "subject", "message", "recommendation"]
        )
    }

    static func frameForms(candidates: [LocalFrameFormCandidate]) -> [String: Any] {
        func slot(_ candidate: LocalFrameFormCandidate) -> [String: Any] {
            object(
                [
                    "title": string,
                    "prompt": string,
                    "meaning_slug": stringConst(candidate.node.slug),
                    "pole": stringConst(candidate.pole),
                    "relation_to_parent": stringConst(candidate.relationToParent)
                ],
                required: ["title", "prompt", "meaning_slug", "pole", "relation_to_parent"]
            )
        }
        return object(
            [
                "schema_version": stringConst("litscenes.frame_forms.v0.1"),
                "option_1": slot(candidates[0]),
                "option_2": slot(candidates[1]),
                "option_3": slot(candidates[2])
            ],
            required: ["schema_version", "option_1", "option_2", "option_3"]
        )
    }

    // Schema builder helpers (port of the service's builders).

    private static func object(_ properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": properties,
            "required": required
        ]
    }

    private static func array(_ items: [String: Any], min: Int, max: Int) -> [String: Any] {
        ["type": "array", "items": items, "minItems": min, "maxItems": max]
    }

    private static var string: [String: Any] { ["type": "string"] }
    private static var boolean: [String: Any] { ["type": "boolean"] }
    private static var integer: [String: Any] { ["type": "integer"] }
    private static var coordinate: [String: Any] { ["type": "number", "minimum": -1, "maximum": 1] }

    private static func stringConst(_ value: String) -> [String: Any] {
        ["type": "string", "const": value]
    }

    private static func intConst(_ value: Int) -> [String: Any] {
        ["type": "integer", "const": value]
    }

    private static func enumeration(_ values: [String]) -> [String: Any] {
        ["type": "string", "enum": values]
    }
}

// MARK: - SceneStory post-processing (ports of the service's repairs)

enum LocalSceneStoryPostProcessing {
    static func repairTerminology(_ document: inout SceneStorySetDocument) {
        var changed = false
        let replacements: [(String, String)] = [
            ("Route candidate", "Story candidate"), ("route candidate", "Story candidate"),
            ("Route strength", "Story strength"), ("route strength", "Story strength"),
            ("Prior route", "Prior Story"), ("prior route", "prior Story"),
            ("Selected route", "Selected Story"), ("selected route", "selected Story"),
            ("This route", "This Story"), ("this route", "this Story"),
            ("the route is", "the Story is"), ("The route is", "The Story is"),
            ("proof route", "proof Story"), ("Proof route", "Proof Story")
        ]
        func repair(_ value: String) -> String {
            var repaired = value
            for (old, new) in replacements {
                repaired = repaired.replacingOccurrences(of: old, with: new)
            }
            if repaired != value { changed = true }
            return repaired
        }
        for index in document.operatorFeedback.indices {
            document.operatorFeedback[index].subject = repair(document.operatorFeedback[index].subject)
            document.operatorFeedback[index].message = repair(document.operatorFeedback[index].message)
            document.operatorFeedback[index].recommendation = repair(document.operatorFeedback[index].recommendation)
        }
        document.warnings = document.warnings.map(repair)
        for storyIndex in document.sceneStories.indices {
            document.sceneStories[storyIndex].title = repair(document.sceneStories[storyIndex].title)
            document.sceneStories[storyIndex].premise = repair(document.sceneStories[storyIndex].premise)
            document.sceneStories[storyIndex].meaningThesis = repair(document.sceneStories[storyIndex].meaningThesis)
            document.sceneStories[storyIndex].visualWorld = repair(document.sceneStories[storyIndex].visualWorld)
            document.sceneStories[storyIndex].concerns = document.sceneStories[storyIndex].concerns.map(repair)
            for sceneIndex in document.sceneStories[storyIndex].scenes.indices {
                var scene = document.sceneStories[storyIndex].scenes[sceneIndex]
                scene.title = repair(scene.title)
                scene.sceneDescription = repair(scene.sceneDescription)
                scene.meaningFocus = repair(scene.meaningFocus)
                scene.primaryMeaningMove = repair(scene.primaryMeaningMove)
                scene.concerns = scene.concerns.map(repair)
                for beatIndex in scene.sceneBeats.indices {
                    scene.sceneBeats[beatIndex].beatDescription = repair(scene.sceneBeats[beatIndex].beatDescription)
                    scene.sceneBeats[beatIndex].action = repair(scene.sceneBeats[beatIndex].action)
                    scene.sceneBeats[beatIndex].meaningProof = repair(scene.sceneBeats[beatIndex].meaningProof)
                    scene.sceneBeats[beatIndex].promptSeed = repair(scene.sceneBeats[beatIndex].promptSeed)
                }
                document.sceneStories[storyIndex].scenes[sceneIndex] = scene
            }
        }
        if changed {
            document.warnings.append("legacy product-object terminology was repaired to Story terminology")
        }
    }

    static func sanitizeDialogue(_ document: inout SceneStorySetDocument, request: LocalSceneStoryRequest) {
        let hasSourcedSpeech = request.wire.mediaAnchors.contains { anchor in
            anchor.notes.lowercased().contains("transcript") || anchor.summary.lowercased().contains("said ")
        }
        var changed = false
        for storyIndex in document.sceneStories.indices {
            for sceneIndex in document.sceneStories[storyIndex].scenes.indices {
                for beatIndex in document.sceneStories[storyIndex].scenes[sceneIndex].sceneBeats.indices {
                    let beat = document.sceneStories[storyIndex].scenes[sceneIndex].sceneBeats[beatIndex]
                    var sanitized: [SceneStoryDialogueLine] = []
                    for var line in beat.dialogue {
                        line = line.normalized()
                        if line.provenance == "media_transcript", !hasSourcedSpeech {
                            line.provenance = "generated_plain"
                            changed = true
                        }
                        if unsupportedCulturallyMarkedDialogue(line) {
                            changed = true
                            continue
                        }
                        sanitized.append(line)
                    }
                    document.sceneStories[storyIndex].scenes[sceneIndex].sceneBeats[beatIndex].dialogue = sanitized
                }
            }
        }
        if changed {
            document.warnings.append("unsupported sourced or culturally marked dialogue was removed or reclassified")
        }
    }

    private static func unsupportedCulturallyMarkedDialogue(_ line: SceneStoryDialogueLine) -> Bool {
        if line.provenance == "user_supplied" || line.provenance == "media_transcript" {
            return false
        }
        let lowered = " " + line.line.lowercased() + " "
        let markers = [" pidgin ", " da ", " brah ", " kine ", " get the road ", " stay ", " pau ", " shoots "]
        return markers.contains { lowered.contains($0) }
    }

    static func appendCompassHandoffWarnings(_ document: inout SceneStorySetDocument) {
        for story in document.sceneStories {
            for index in 1..<max(story.scenes.count, 1) where index < story.scenes.count {
                let previous = story.scenes[index - 1]
                let current = story.scenes[index]
                if !pointsRoughlyMatch(previous.emotionalArc.exit, current.emotionalArc.entry) {
                    document.warnings.append("scene compass handoff mismatch: \(previous.sceneId) exit does not match \(current.sceneId) entry")
                }
            }
            for scene in story.scenes {
                for index in 1..<max(scene.sceneBeats.count, 1) where index < scene.sceneBeats.count {
                    let previous = scene.sceneBeats[index - 1]
                    let current = scene.sceneBeats[index]
                    if !pointsRoughlyMatch(previous.emotionalTurn.exit, current.emotionalTurn.entry) {
                        document.warnings.append("beat compass handoff mismatch: \(previous.beatId) exit does not match \(current.beatId) entry")
                    }
                }
            }
        }
        document.warnings = uniqueNonEmpty(document.warnings, limit: 32)
    }

    private static func pointsRoughlyMatch(_ lhs: EmotionalCompassPoint, _ rhs: EmotionalCompassPoint) -> Bool {
        if let left = lhs.labels.first, let right = rhs.labels.first,
           left.caseInsensitiveCompare(right) == .orderedSame {
            return true
        }
        return abs(lhs.valence - rhs.valence) <= 0.35
            && abs(lhs.activation - rhs.activation) <= 0.35
            && abs(lhs.agency - rhs.agency) <= 0.35
    }
}

// MARK: - SceneStory validation (port of the service's validator)

enum LocalSceneStoryValidation {
    static func validate(
        document: SceneStorySetDocument,
        request: LocalSceneStoryRequest,
        userId: String,
        generatedAt: String
    ) throws {
        let wire = request.wire
        func fail(_ message: String) -> LocalStoryInferenceValidationError {
            LocalStoryInferenceValidationError(message: message)
        }
        guard document.userId == userId else { throw fail("scene_story user_id mismatch") }
        guard document.projectId == wire.projectId else { throw fail("scene_story project_id mismatch") }
        guard document.goalFingerprint == wire.goalFingerprint else { throw fail("scene_story goal_fingerprint mismatch") }
        guard document.lensId == wire.lensId else { throw fail("scene_story lens_id mismatch") }
        guard document.lensContextFingerprint == wire.lensContextFingerprint else {
            throw fail("scene_story lens_context_fingerprint mismatch")
        }
        guard document.storyCount == wire.storyCount, document.sceneStories.count == wire.storyCount else {
            throw fail("scene_story expected \(wire.storyCount) stories, got declared=\(document.storyCount) actual=\(document.sceneStories.count)")
        }
        guard document.scenesPerStory == wire.scenesPerStory else {
            throw fail("scene_story scenes_per_story mismatch: \(document.scenesPerStory)")
        }
        guard document.beatsPerScene == wire.beatsPerScene else {
            throw fail("scene_story beats_per_scene mismatch: \(document.beatsPerScene)")
        }
        guard document.generatedAt == generatedAt else { throw fail("scene_story generated_at mismatch") }

        let validSupportStatuses: Set<String> = ["media_supported", "lens_supported", "theme_supported", "goal_inferred", "invented", "weak"]
        let validArcShapes: Set<String> = ["build", "descent", "turn", "release", "spiral", "unresolved"]
        let maxChanges = max(wire.generationIntent.beatContract.maxMajorStateChanges, 0)

        for (storyIndex, story) in document.sceneStories.enumerated() {
            let storyLabel = "scene_story story \(storyIndex + 1)"
            if story.storyId.trimmed.isEmpty || story.title.trimmed.isEmpty {
                throw fail("\(storyLabel) missing story_id or title")
            }
            try validatePoint(story.emotionalArc.start, label: "\(storyLabel) invalid emotional_arc: start")
            try validatePoint(story.emotionalArc.end, label: "\(storyLabel) invalid emotional_arc: end")
            guard validArcShapes.contains(story.emotionalArc.arcShape.trimmed) else {
                throw fail("\(storyLabel) invalid emotional_arc: invalid arc_shape \(story.emotionalArc.arcShape)")
            }
            try validateBlueprint(story, intent: wire.generationIntent, brief: wire.storyGenerationBrief, label: storyLabel)
            if story.reasoningSummary.whyThisForm.trimmed.isEmpty
                || story.reasoningSummary.whyThisArc.trimmed.isEmpty
                || story.reasoningSummary.whyThisPayoff.trimmed.isEmpty {
                throw fail("\(storyLabel) missing reasoning_summary")
            }
            try validateCompassLocks(arc: story.emotionalArc, locks: wire.generationIntent.compassLocks, label: storyLabel)
            guard story.scenes.count == wire.scenesPerStory else {
                throw fail("\(storyLabel) expected \(wire.scenesPerStory) scenes, got \(story.scenes.count)")
            }
            for (sceneIndex, scene) in story.scenes.enumerated() {
                let sceneLabel = "\(storyLabel) scene \(sceneIndex + 1)"
                if scene.sceneId.trimmed.isEmpty || scene.sceneDescription.trimmed.isEmpty {
                    throw fail("\(sceneLabel) missing scene_id or scene_description")
                }
                try validatePoint(scene.emotionalArc.entry, label: "\(sceneLabel) invalid emotional_arc: entry")
                try validatePoint(scene.emotionalArc.exit, label: "\(sceneLabel) invalid emotional_arc: exit")
                if scene.emotionalArc.primaryTurn.trimmed.isEmpty {
                    throw fail("\(sceneLabel) invalid emotional_arc: missing primary_turn")
                }
                if scene.primaryMeaningMove.trimmed.isEmpty {
                    throw fail("\(sceneLabel) missing primary_meaning_move")
                }
                guard validSupportStatuses.contains(scene.supportStatus.trimmed) else {
                    throw fail("\(sceneLabel) has invalid support_status \(scene.supportStatus)")
                }
                guard scene.sceneBeats.count == wire.beatsPerScene else {
                    throw fail("\(sceneLabel) expected \(wire.beatsPerScene) beats, got \(scene.sceneBeats.count)")
                }
                for (beatIndex, beat) in scene.sceneBeats.enumerated() {
                    let beatLabel = "\(sceneLabel) beat \(beatIndex + 1)"
                    if beat.beatId.trimmed.isEmpty || beat.beatDescription.trimmed.isEmpty {
                        throw fail("\(beatLabel) missing beat_id or beat_description")
                    }
                    try validatePoint(beat.emotionalTurn.entry, label: "\(beatLabel) invalid emotional_turn: entry")
                    try validatePoint(beat.emotionalTurn.exit, label: "\(beatLabel) invalid emotional_turn: exit")
                    if beat.emotionalTurn.turnDescription.trimmed.isEmpty {
                        throw fail("\(beatLabel) invalid emotional_turn: missing turn_description")
                    }
                    if beat.emotionalTurn.observableEvidence.isEmpty {
                        throw fail("\(beatLabel) invalid emotional_turn: missing observable_evidence")
                    }
                    if beat.meaningProof.trimmed.isEmpty { throw fail("\(beatLabel) missing meaning_proof") }
                    guard validSupportStatuses.contains(beat.supportStatus.trimmed) else {
                        throw fail("\(beatLabel) has invalid support_status \(beat.supportStatus)")
                    }
                    if beat.evidenceBasis.trimmed.isEmpty { throw fail("\(beatLabel) missing evidence_basis") }
                    if beat.promptSeed.trimmed.isEmpty { throw fail("\(beatLabel) missing prompt_seed") }
                    if beat.majorStateChanges.isEmpty { throw fail("\(beatLabel) missing major_state_changes") }
                    if maxChanges > 0, beat.majorStateChanges.count > maxChanges {
                        throw fail("\(beatLabel) major_state_changes exceeds generation_intent beat contract")
                    }
                }
            }
        }
    }

    private static func validatePoint(_ point: EmotionalCompassPoint, label: String) throws {
        if point.labels.isEmpty {
            throw LocalStoryInferenceValidationError(message: "\(label): missing labels")
        }
        for value in [point.valence, point.activation, point.agency] where value < -1 || value > 1 {
            throw LocalStoryInferenceValidationError(message: "\(label): coordinate out of range")
        }
    }

    private static func validateBlueprint(
        _ story: SceneStory,
        intent: StoryGenerationIntent,
        brief: SceneStoryGenerationBrief,
        label: String
    ) throws {
        let blueprint = story.storyBlueprint
        func fail(_ message: String) -> LocalStoryInferenceValidationError {
            LocalStoryInferenceValidationError(message: "\(label) invalid story_blueprint: \(message)")
        }
        if blueprint.storyForm != brief.storyForm {
            throw fail("story_form \(blueprint.storyForm.rawValue) does not match story_generation_brief \(brief.storyForm.rawValue)")
        }
        if blueprint.architectureFamily == .unspecified {
            throw fail("missing architecture_family")
        }
        if intent.architectureFamily != .unspecified, blueprint.architectureFamily != intent.architectureFamily {
            throw fail("architecture_family \(blueprint.architectureFamily.rawValue) does not match generation_intent \(intent.architectureFamily.rawValue)")
        }
        if blueprint.primaryActor.trimmed.isEmpty
            || blueprint.causalEngine.trimmed.isEmpty
            || blueprint.primaryMeaningMove.trimmed.isEmpty
            || blueprint.payoffMechanism.trimmed.isEmpty
            || blueprint.coreVisualImage.trimmed.isEmpty {
            throw fail("story_blueprint missing required structural field")
        }
        let haystack = [
            story.title, story.premise, story.meaningThesis, story.visualWorld,
            blueprint.primaryActor, blueprint.actingForce, blueprint.causalEngine,
            blueprint.settingProgression.joined(separator: " "),
            blueprint.primaryMeaningMove, blueprint.compassDestination,
            blueprint.payoffMechanism, blueprint.coreVisualImage
        ].joined(separator: " ").lowercased()
        for item in intent.avoidStructures {
            let value = item.value.trimmed
            if !value.isEmpty, haystack.contains(value.lowercased()) {
                throw LocalStoryInferenceValidationError(
                    message: "\(label) generation_intent avoid_structures matched \(item.dimension)=\"\(value)\""
                )
            }
        }
    }

    private static func validateCompassLocks(arc: StoryEmotionalArc, locks: [CompassLock], label: String) throws {
        for lock in locks {
            guard lock.scope == .storyEnd || lock.scope == .storyStart else { continue }
            let point = lock.scope == .storyStart ? arc.start : arc.end
            let text = lock.text.trimmed
            if !text.isEmpty {
                let matched = point.typedLabels.contains {
                    $0.kind == lock.kind && $0.text.trimmed == text
                }
                guard matched else {
                    throw LocalStoryInferenceValidationError(
                        message: "\(label) generation_intent compass lock failure: missing compass lock label kind=\(lock.kind.rawValue) text=\"\(text)\""
                    )
                }
            }
            try validateCoordinate(point.valence, allowed: lock.valence, name: "valence", label: label)
            try validateCoordinate(point.activation, allowed: lock.activation, name: "activation", label: label)
            try validateCoordinate(point.agency, allowed: lock.agency, name: "agency", label: label)
        }
    }

    private static func validateCoordinate(_ value: Double, allowed: CompassCoordinateRange?, name: String, label: String) throws {
        guard let allowed else { return }
        if let minimum = allowed.min, value < minimum {
            throw LocalStoryInferenceValidationError(message: "\(label) generation_intent compass lock failure: compass lock \(name) below minimum")
        }
        if let maximum = allowed.max, value > maximum {
            throw LocalStoryInferenceValidationError(message: "\(label) generation_intent compass lock failure: compass lock \(name) above maximum")
        }
    }
}

// MARK: - Frame Forms candidate selection (local)

/// One slot of the trio: a vocabulary node, its assigned pole, and the resolved
/// expression text. The bundled index carries no pole articulations, so the
/// definition serves as the expression — disclosed once in the warnings.
struct LocalFrameFormCandidate {
    var node: LocalMeaningIndexNode
    var pole: String
    var expression: String
    var relationToParent: String = ""
    var roleHint: String
}

enum LocalFrameFormSelection {
    static func candidates(request: FrameFormsGenerateRequest, mode: String) -> ([LocalFrameFormCandidate], [String]) {
        let index = LocalMeaningIndex.shared
        var warnings: [String] = [
            "Local mode: forms drawn from the bundled starter vocabulary (definitions as expressions; no graph edges)."
        ]

        if mode == "expansion" {
            // No local graph edges exist to branch along; substitute a canonical
            // top-up trio and say so instead of faking a neighborhood walk.
            warnings.append("no local graph edges; branched from the bundled canonical vocabulary instead")
            var exclude = Set<String>()
            if let selected = request.selectedForm {
                exclude.insert(selected.meaningSlug.trimmed.lowercased())
            }
            let priorGists = request.priorFormGists.map { $0.lowercased() }
            let startPole = request.selectedForm?.pole.trimmed.lowercased() == "positive" ? "negative" : "positive"
            var candidates: [LocalFrameFormCandidate] = []
            for node in canonicalNodes(index, excluding: exclude) {
                guard candidates.count < 3 else { break }
                let mentioned = priorGists.contains { gist in
                    gist.contains(node.slug) || (!node.name.isEmpty && gist.contains(node.name.lowercased()))
                }
                if mentioned { continue }
                let pole = candidates.count % 2 == 0 ? startPole : (startPole == "positive" ? "negative" : "positive")
                candidates.append(LocalFrameFormCandidate(
                    node: node,
                    pole: pole,
                    expression: node.definition,
                    relationToParent: "catalog",
                    roleHint: "branch"
                ))
            }
            return (candidates, warnings)
        }

        var resolved: [LocalMeaningIndexNode] = []
        var seen = Set<String>()
        var missing: [String] = []
        for ref in request.meaningNodeRefs {
            let slug = ref.slug.trimmed
            guard !slug.isEmpty, !seen.contains(slug.lowercased()) else { continue }
            seen.insert(slug.lowercased())
            if let node = index.node(forSlug: slug) {
                resolved.append(node)
            } else {
                missing.append(slug)
            }
        }
        for slug in missing {
            warnings.append("meaning node ref not resolved: \(slug)")
        }
        if resolved.count < 6 {
            if resolved.count < 3 {
                warnings.append("meaning refs resolved fewer than 3 nodes; topped up from the bundled canonical vocabulary")
            }
            for node in canonicalNodes(index, excluding: seen) {
                guard resolved.count < 6 + 6 else { break }
                resolved.append(node)
                seen.insert(node.slug.lowercased())
                if resolved.count >= 12 { break }
            }
        }
        let trio = extremeTrio(from: resolved)
        return (trio, warnings)
    }

    private static func canonicalNodes(_ index: LocalMeaningIndex, excluding: Set<String>) -> [LocalMeaningIndexNode] {
        index.nodes
            .filter { $0.status == "canonical" && !excluding.contains($0.slug.lowercased()) }
            .sorted { lhs, rhs in
                let lhsRank = kindRank(lhs.kind)
                let rhsRank = kindRank(rhs.kind)
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.slug < rhs.slug
            }
    }

    /// The bundled index has no abstraction levels; node kind serves as a local
    /// concreteness ladder so the trio still spans grounded-to-abstract.
    private static func kindRank(_ kind: String) -> Int {
        switch kind {
        case "symbol", "motif": 1
        case "mood", "scene_role", "beat_function": 2
        case "archetypal_situation", "transformation", "genre_force", "value_tension": 3
        case "theme", "meaning_claim": 4
        default: 3
        }
    }

    private static func extremeTrio(from nodes: [LocalMeaningIndexNode]) -> [LocalFrameFormCandidate] {
        var usable: [LocalMeaningIndexNode] = []
        var seen = Set<String>()
        for node in nodes where !node.slug.isEmpty && !seen.contains(node.slug) {
            seen.insert(node.slug)
            usable.append(node)
        }
        guard usable.count >= 3 else { return [] }

        let sorted = usable.sorted { lhs, rhs in
            let lhsRank = kindRank(lhs.kind)
            let rhsRank = kindRank(rhs.kind)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.slug < rhs.slug
        }
        let grounded = sorted[0]
        var abstract = sorted[sorted.count - 1]
        if abstract.slug == grounded.slug {
            abstract = sorted[sorted.count - 2]
        }
        // Highest-tension middle: value tensions first, then remaining order.
        let middle = sorted.first { node in
            node.slug != grounded.slug && node.slug != abstract.slug && node.kind == "value_tension"
        } ?? sorted.first { node in
            node.slug != grounded.slug && node.slug != abstract.slug
        }
        guard let middle else { return [] }

        return [
            LocalFrameFormCandidate(node: grounded, pole: "positive", expression: grounded.definition, roleHint: "grounded_extreme"),
            LocalFrameFormCandidate(node: middle, pole: "negative", expression: middle.definition, roleHint: "tension_middle"),
            LocalFrameFormCandidate(node: abstract, pole: "positive", expression: abstract.definition, roleHint: "abstract_extreme")
        ]
    }

    static func modelInput(
        request: FrameFormsGenerateRequest,
        candidates: [LocalFrameFormCandidate],
        mode: String,
        retryCorrection: String
    ) -> [String: Any] {
        var slots: [[String: Any]] = []
        for (index, candidate) in candidates.enumerated() {
            var slot: [String: Any] = [
                "slot": index + 1,
                "meaning_slug": candidate.node.slug,
                "name": candidate.node.name,
                "kind": candidate.node.kind,
                "abstraction_level": "",
                "pole": candidate.pole,
                "expression": candidate.expression,
                "boundary": "",
                "definition": candidate.node.definition,
                "role_hint": candidate.roleHint
            ]
            if !candidate.relationToParent.isEmpty {
                slot["relation_to_parent"] = candidate.relationToParent
            }
            slots.append(slot)
        }
        var input: [String: Any] = [
            "prompt_version": "litscenes.frame_forms_prompt.v0.1-local",
            "mode": mode,
            "goal_summary": String(request.goalSummary.trimmed.prefix(2000)),
            "slots": slots
        ]
        let styleFit = String(request.styleFitLine.trimmed.prefix(300))
        if !styleFit.isEmpty {
            input["style_fit_context"] = styleFit
        }
        if let selected = request.selectedForm {
            input["selected_form"] = [
                "title": selected.title,
                "prompt_gist": selected.promptGist,
                "pole": selected.pole,
                "meaning_slug": selected.meaningSlug
            ]
        }
        if !request.priorFormGists.isEmpty {
            input["prior_form_gists"] = request.priorFormGists
        }
        if !retryCorrection.isEmpty {
            input["retry_correction"] = retryCorrection
        }
        return input
    }

    private static let styleVocabulary = [
        "cinematic", "photorealistic", "photo-realistic", "8k", "4k", "hdr",
        "film grain", "35mm", "watercolor", "oil painting", "oil-painted",
        "ink wash", "concept art", "illustration", "anime", "unreal engine",
        "octane", "golden hour", "volumetric", "rim light", "rim-lit", "bokeh",
        "color grade", "color-graded", "pastel palette", "monochrome", "sepia",
        "chiaroscuro", "impressionist", "surrealist", "art nouveau", "noir style"
    ]

    static func decodeAndValidate(text: String, candidates: [LocalFrameFormCandidate]) throws -> [LensFrameFormOption] {
        guard let data = text.data(using: .utf8),
              let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw LocalStoryInferenceValidationError(message: "frame forms response decode failed")
        }
        var options: [LensFrameFormOption] = []
        for (index, key) in ["option_1", "option_2", "option_3"].enumerated() {
            guard let draft = decoded[key] as? [String: Any] else {
                throw LocalStoryInferenceValidationError(message: "option \(index + 1) is missing")
            }
            let candidate = candidates[index]
            let title = ((draft["title"] as? String) ?? "").trimmed
            let prompt = ((draft["prompt"] as? String) ?? "").trimmed
            if title.isEmpty {
                throw LocalStoryInferenceValidationError(message: "option \(index + 1) has an empty title")
            }
            if prompt.count < 80 || prompt.count > 1200 {
                throw LocalStoryInferenceValidationError(message: "option \(index + 1) prompt length \(prompt.count) outside 80-1200")
            }
            let haystack = (title + " " + prompt).lowercased()
            if let leak = styleVocabulary.first(where: { haystack.contains($0) }) {
                throw LocalStoryInferenceValidationError(message: "option \(index + 1) contains banned style vocabulary: \(leak)")
            }
            // Identity fields are stamped from the candidates, never from the model.
            options.append(LensFrameFormOption(
                title: title,
                prompt: prompt,
                meaningSlug: candidate.node.slug,
                meaningName: candidate.node.name,
                pole: candidate.pole,
                abstractionLevel: "",
                relationToParent: candidate.relationToParent
            ))
        }
        return options
    }
}

// MARK: - Local style candidates (direct-mode Frame Context)

/// Scores the local catalog's styles against the Goal's style terms so direct
/// mode can populate `styleCandidates` — the field the Scene Plan generator
/// hard-requires. Every style is returned (zero-score entries last) so the
/// spine never dead-ends on an empty candidate list; the honest difference
/// from the hosted service is corpus breadth, not an artificial gate.
enum LocalStyleCandidateBuilder {
    static func candidates(
        from catalog: StyleBrowseCatalog,
        styleTermRefs: [ProjectGoalStyleTermRef],
        limit: Int
    ) -> [LensContextStyleCandidate] {
        let collectionNames = Dictionary(
            uniqueKeysWithValues: catalog.collections.map { ($0.key, $0.name) }
        )
        let refs = styleTermRefs
            .map { $0.normalized() }
            .filter { !$0.term.isEmpty }

        let scored = catalog.styles.map { style -> LensContextStyleCandidate in
            var matched: [LensContextStyleMatchedTerm] = []
            for ref in refs {
                for (fieldName, value) in matchesForRef(ref, style: style) {
                    matched.append(LensContextStyleMatchedTerm(
                        inputTerm: ref.term,
                        kind: ref.kind.rawValue,
                        fieldName: fieldName,
                        value: value,
                        contribution: ref.weight
                    ))
                }
            }
            let score = matched.reduce(0) { $0 + $1.contribution }
            return LensContextStyleCandidate(
                styleId: style.id,
                title: style.title,
                label: style.label,
                caption: style.caption,
                imageUrl: style.url,
                collectionKey: style.collection,
                collectionName: collectionNames[style.collection] ?? style.collection,
                secondaryCollection: style.secondaryCollection ?? "",
                moods: style.moods,
                hueName: style.hueName,
                hueHex: style.hueHex,
                medium: style.medium,
                scalarSat: style.sat,
                scalarCon: style.con,
                scalarSer: style.ser,
                scalarLin: style.lin,
                scalarSty: style.sty,
                score: score,
                matchCount: matched.count,
                matchedTerms: matched,
                positivePromptAtoms: [],
                negativePromptAtoms: [],
                transferableTraits: []
            )
        }
        return Array(
            scored
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
                .prefix(limit)
        )
    }

    /// Typed terms match their own field; phrases match any descriptive field.
    private static func matchesForRef(
        _ ref: ProjectGoalStyleTermRef,
        style: StyleBrowseStyle
    ) -> [(String, String)] {
        let term = ref.term.lowercased()
        var matches: [(String, String)] = []
        func moodMatches() {
            for mood in style.moods where mood.lowercased().contains(term) {
                matches.append(("moods", mood))
            }
        }
        func hueMatches() {
            if style.hueName.lowercased().contains(term) {
                matches.append(("hue_name", style.hueName))
            }
        }
        func collectionMatches() {
            if style.collection.lowercased().contains(term) {
                matches.append(("collection", style.collection))
            }
            if let secondary = style.secondaryCollection, secondary.lowercased().contains(term) {
                matches.append(("secondary_collection", secondary))
            }
        }
        func mediumMatches() {
            if style.medium.lowercased().contains(term) {
                matches.append(("medium", style.medium))
            }
        }
        func textMatches() {
            let haystack = [style.title, style.label, style.caption, style.oneLineStyleSummary ?? ""]
                .joined(separator: " ")
                .lowercased()
            if haystack.contains(term) {
                matches.append(("caption", ref.term))
            }
        }
        switch ref.kind {
        case .mood: moodMatches()
        case .hue: hueMatches()
        case .collection: collectionMatches()
        case .medium: mediumMatches()
        case .phrase:
            moodMatches()
            hueMatches()
            collectionMatches()
            mediumMatches()
            textMatches()
        }
        return matches
    }
}
