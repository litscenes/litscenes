import Foundation

/// What the Frame Creator would submit for `.plannedFrame` when the operator
/// changes nothing, as one pure law — so the pool card's one-click RENDER, the
/// guided stage's, and the tests all build the identical request. One
/// deliberate difference from the modal: the plan's style slot rides (a
/// one-click Frame should look like the rest of the film), where the modal
/// opens with style off.
enum LensPlannedFrameDefaults {
    /// Structured associations survive prompt edits and roster renames. Scene cast
    /// names are matched only against their saved roster links or unique aliases.
    static func entries(
        planned: ProjectLensHeroImage,
        lens: ProjectLens,
        available: [RosterMentionResolver.Entry]
    ) -> [RosterMentionResolver.Entry] {
        var result: [RosterMentionResolver.Entry] = []
        func append(_ entry: RosterMentionResolver.Entry?) {
            guard let entry, !result.contains(where: { $0.id == entry.id && $0.kind == entry.kind }) else { return }
            result.append(entry)
        }
        for id in [planned.suggestedForCharacterId ?? "", planned.characterId] where !id.trimmed.isEmpty {
            append(available.first { $0.kind == .character && $0.id == id })
        }
        let cast = (lens.body.areas ?? []).flatMap(\.scenes).first { $0.sceneId == planned.sceneId }?.cast ?? []
        for member in cast {
            let links = (lens.body.castMembers ?? []).filter {
                $0.name.trimmed.caseInsensitiveCompare(member.name.trimmed) == .orderedSame
            }
            let ids = Set(links.compactMap(\.characterId).filter { !$0.isEmpty })
            if ids.count == 1, let id = ids.first {
                append(available.first { $0.kind == .character && $0.id == id })
            } else if ids.isEmpty {
                let matches = available.filter { entry in
                    entry.kind == .character && ([entry.name] + entry.aliases).contains {
                        $0.trimmed.caseInsensitiveCompare(member.name.trimmed) == .orderedSame
                    }
                }
                if matches.count == 1 { append(matches.first) }
            }
        }
        let prompt = planned.sourcePrompt.trimmed.nilIfEmpty ?? planned.prompt.trimmed
        for entry in RosterMentionResolver.resolve(prompt: prompt, entries: available).mentions { append(entry) }
        return result
    }

    static func referencePlan(
        planned: ProjectLensHeroImage,
        lens: ProjectLens,
        stack: RenderStack,
        available: [RosterMentionResolver.Entry],
        items: [MediaItemRecord],
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> FrameCreatorAttachmentPlan {
        frameCreatorAttachmentPlan(
            seed: nil, direct: [],
            mention: mentionAttachments(for: entries(planned: planned, lens: lens, available: available), items: items, fileExists: fileExists),
            stack: stack
        )
    }

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
        // The shared merge law owns every provider cap (FAL slots, Stability's
        // composite, the six-image budget).
        let combined = referencePlan(planned: planned, lens: lens, stack: stack, available: mentionEntries, items: mentionItems, fileExists: fileExists).attachments
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
