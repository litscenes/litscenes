import Foundation

/// What the Frame Creator would submit for `.plannedFrame` when the operator
/// changes nothing, as one pure law — so the pool card's one-click RENDER, the
/// guided stage's, and the tests all build the identical request. One
/// deliberate difference from the modal: the plan's style slot rides (a
/// one-click Frame should look like the rest of the film), where the modal
/// opens with style off.
enum LensPlannedFrameDefaults {
    static func request(
        planned: ProjectLensHeroImage,
        lens: ProjectLens,
        stack: RenderStack,
        styleSlot: LensStyleTreatmentSlot?,
        styleCatalogVersion: String,
        mentionEntries: [RosterMentionResolver.Entry],
        mentionItems: [MediaItemRecord],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> LensNewTakeRenderRequest {
        let authored = planned.sourcePrompt.trimmed.nilIfEmpty ?? planned.prompt.trimmed
        let resolution = RosterMentionResolver.resolve(prompt: authored, entries: mentionEntries)
        let styleMode: LensRenderStyleMode = styleSlot == nil ? .none : .describeStyleInPrompt
        let mention = mentionAttachments(for: resolution.mentions, items: mentionItems, fileExists: fileExists)
        // The shared merge law owns every provider cap (FAL slots, Stability's
        // composite, the six-image budget).
        let combined = frameCreatorCombinedAttachments(seed: nil, direct: [], mention: mention, stack: stack).attachments
        return LensNewTakeRenderRequest(
            stack: stack,
            styleMode: styleMode,
            prompt: resolution.cleanedPrompt,
            authoredPrompt: authored,
            label: "",
            debugParametersJSON: stack.isFAL
                ? stack.falDebugParameterTemplate(mediaPlan: lens.body.resolvedMediaPlan, styleMode: styleMode)
                : "",
            promptImageAttachment: nil,
            promptImageAttachments: combined.isEmpty ? nil : combined,
            moodInfluences: nil,
            medium: nil,
            styleOverrideSlot: styleSlot,
            styleOverrideCatalogVersion: styleSlot == nil ? "" : styleCatalogVersion,
            promptEnrichmentDisabled: planned.promptEnrichmentDisabled ? true : nil,
            stabilityStrength: stack.isStability ? planned.stabilityStrength : nil
        ).normalized()
    }

    /// THE IDENTITY LADDER: a character attaches its rendered reference sheet
    /// when it exists, else its roster composite, else its leading two source
    /// photos — never nothing while sources exist. Objects and places use the
    /// same sheet-else-leading-two ladder.
    static func mentionAttachments(
        for entries: [RosterMentionResolver.Entry],
        items: [MediaItemRecord],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [LensPromptImageAttachment] {
        var attachments: [LensPromptImageAttachment] = []
        for entry in entries {
            let picks = RosterCharacterRenderPrompt.identityAnchorPicks(
                referenced: entry.referenceMediaIds.compactMap { id in items.first { $0.mediaId == id } },
                referenceLabels: entry.referenceLabels,
                capOne: false,
                activeSheet: entry.kind == .character ? items.first { $0.mediaId == entry.activeSheetMediaId } : nil,
                looseReferenceFallback: true,
                fileExists: fileExists
            )
            for pick in picks {
                attachments.append(LensPromptImageAttachment(
                    source: .moodboardImage,
                    sourceId: pick.item.mediaId,
                    label: pick.isSheet ? "\(entry.name) — reference sheet" : entry.name,
                    detail: RosterMentionResolver.attachmentDescriptor(
                        for: entry,
                        label: pick.label,
                        isCompositeSheet: pick.isSheet,
                        isCharacterSheet: pick.item.isCharacterSheet
                    ),
                    imagePath: pick.item.path
                ).normalized())
            }
        }
        return attachments
    }
}
