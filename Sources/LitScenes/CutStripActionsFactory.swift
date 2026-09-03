import SwiftUI

/// A Frame Creator launch that already knows which lens it renders into and
/// which context seeded it. Shared by every workbench surface that can open
/// the Frame Creator (the SCENES tab and the SCENES v2 boxes).
struct WorkbenchFrameCreatorLaunch: Identifiable {
    let lensId: String
    let context: FrameCreationContext
    /// Library images pre-attached in the Frame Creator's reference well
    /// (a Media "Use in Frame Creator" hand-off rides here).
    var referenceMediaIds: [String] = []
    /// A strip cell the finished take should land beside (variation/restyle
    /// launched from a cut-opened frame detail). nil = pool-only, as ever.
    var placeBeside: HeroPreviewCutNavigation? = nil

    var id: String { "\(lensId)_\(context.id)" }
}

/// Everything the shared CutStrip action builder needs from its hosting
/// workbench. Values are snapshots read at build time; closures write back
/// into host presentation state. Engine mutations never ride through here —
/// they live in the factory so both hosts get identical behavior.
struct CutStripWorkbenchSurface {
    var openCutIds: [String] = []
    var narrationFocusRequest: ShotNarrationFocusRequest?
    var renderPlanFocusRequest: ShotRenderPlanFocusRequest?
    var onTouchCut: (String) -> Void = { _ in }
    var onOpenPlayer: (ShotVideoRequest) -> Void = { _ in }
    /// Focus the narration strip for a shot. The host must dismiss any open
    /// player first — narration focus and the player are exclusive.
    var onFocusNarration: (String) -> Void = { _ in }
    var onOpenJovilabe: (String) -> Void = { _ in }
    var onOpenClipInspector: (ShotClipInspectorRequest) -> Void = { _ in }
    var onOpenFrameDetail: (_ cutId: String, _ entryId: String, _ heroImage: ProjectLensHeroImage) -> Void = { _, _, _ in }
    var onEnterExcursion: (ExcursionLaunchRequest) -> Void = { _ in }
    var onLaunchFrameCreator: (WorkbenchFrameCreatorLaunch) -> Void = { _ in }
    var pictureUndo: ShotPictureUndoCoordinator
    var undoManager: UndoManager?
}

/// The one CutStrip action assembly, shared verbatim by the SCENES tab and
/// the SCENES v2 boxes. Engine calls are wired here; host presentation is
/// routed through `surface`.
@MainActor
func makeCutStripActions(
    library: LibraryEngine,
    lensId: String,
    frameLookup: [String: ProjectLensHeroImage],
    mediaLookup: [String: MediaItemRecord],
    surface: CutStripWorkbenchSurface
) -> CutStripActions {
    var actions = CutStripActions()
    actions.frameLookup = frameLookup
    actions.mediaLookup = mediaLookup
    actions.meaningNodes = library.lensContext.promptPacket().meaningNodes
    actions.activeShotRenderId = library.activeShotRenderId
    actions.configuredRenderModels = Set(
        ShotRenderModel.allCases.filter(library.canExecuteShotRenderModel)
    )
    actions.activeShotNarrationId = library.activeShotNarrationId
    actions.activeShotNarrationSpeedId = library.activeShotNarrationSpeedId
    actions.activeShotChipsId = library.activeShotChipsId
    actions.accountVoiceOptions = library.accountVoiceOptions
    actions.hiddenNarrationVoiceIds = library.hiddenNarrationVoiceIds
    actions.narrationFocusRequest = surface.narrationFocusRequest
    actions.renderPlanFocusRequest = surface.renderPlanFocusRequest
    actions.openCutIds = surface.openCutIds
    actions.onTouchCut = { cutId in surface.onTouchCut(cutId) }
    actions.onRename = { cutId, name in
        library.renameShot(shotId: cutId, name: name)
    }
    actions.onTrash = { cutId in
        library.trashShot(shotId: cutId)
    }
    actions.onDuplicate = { cutId in
        _ = library.duplicateCut(cutId: cutId)
    }
    actions.onUncombine = { cutId in
        library.uncombineShot(parentShotId: cutId)
    }
    actions.onOpenJovilabe = { cutId in
        surface.onOpenJovilabe(cutId)
    }
    actions.onSetRenderStack = { cutId, stack in
        library.setShotRenderStack(shotId: cutId, stack: stack)
    }
    actions.onSetSegmentRenderStack = { cutId, pair, stack in
        library.setShotSegmentRenderOverride(
            shotId: cutId,
            startFrameImageId: pair.start?.imageId ?? "",
            endFrameImageId: pair.end?.imageId ?? "",
            placementStartEntryId: pair.startPlacementEntryId,
            placementEndEntryId: pair.endPlacementEntryId,
            stack: stack
        )
    }
    actions.onSetNarrationAnchor = { cutId, entryId in
        library.setShotNarrationAnchorEntry(shotId: cutId, entryId: entryId)
    }
    actions.onSetNarrationAnchorFaceOverride = { cutId, entryId in
        library.setShotNarrationAnchorFaceOverride(shotId: cutId, entryId: entryId)
    }
    actions.falPricing = library.falPricing
    actions.isFetchingVideoPricing = library.isFetchingFALPricing
    actions.onRenderPlanOpened = {
        Task {
            await library.refreshFALPricingIfStale()
        }
    }
    actions.onConfirmRender = { cutId, overrides, onlySegmentKeys in
        library.setShotSegmentPromptOverrides(shotId: cutId, overrides: overrides)
        Task {
            await library.renderShot(shotId: cutId, onlySegmentKeys: onlySegmentKeys)
        }
    }
    actions.onAutosavePromptOverrides = { cutId, overrides in
        library.setShotSegmentPromptOverrides(shotId: cutId, overrides: overrides)
    }
    actions.onSaveDirectionPlans = { cutId, plans in
        library.setShotSegmentDirectionPlans(shotId: cutId, plans: plans)
    }
    actions.draftingDirectionKeys = library.draftingDirectionSegmentKeys
    actions.directionDraftErrors = library.directionDraftErrors
    actions.onDraftDirectionPlan = { cutId, segmentKey in
        Task {
            await library.draftShotSegmentDirectionPlan(shotId: cutId, segmentKey: segmentKey)
        }
    }
    actions.onRequestRerender = { cutId in
        surface.onOpenPlayer(ShotVideoRequest(shotId: cutId, openRerenderPanel: true))
    }
    actions.onOpenShotVideo = { cutId in
        // PLAY opens the whole instrument — player, timeline strip,
        // and segment prompts — in one gesture.
        surface.onOpenPlayer(ShotVideoRequest(shotId: cutId, openRerenderPanel: true))
    }
    actions.onOpenNarration = { cutId in
        surface.onFocusNarration(cutId)
    }
    actions.onFinalizeAndOpen = { cutId in
        // OPEN: nothing to review — every segment is already covered by
        // a reusable clip, so assemble locally ($0, no provider calls)
        // and jump straight to the full instrument once it's ready.
        Task {
            let assembled = await library.renderShot(shotId: cutId)
            if assembled {
                surface.onOpenPlayer(ShotVideoRequest(shotId: cutId, openRerenderPanel: true))
            }
        }
    }
    actions.onGenerateShotChips = { cutId, force in
        Task {
            await library.generateShotNarrationChips(shotId: cutId, force: force)
        }
    }
    actions.onNarrateShot = { cutId, messaging, voicePresetId, scriptOverride in
        Task {
            await library.startShotNarration(
                shotId: cutId,
                messagingText: messaging,
                voicePresetId: voicePresetId,
                scriptOverride: scriptOverride
            )
        }
    }
    actions.onSetShotNarrationSpeed = { cutId, speed in
        Task {
            await library.remixShotNarrationSpeed(shotId: cutId, voiceSpeed: speed)
        }
    }
    actions.onInsertFrame = { cutId, transfer, index in
        library.insertShotFrame(shotId: cutId, frameImageId: transfer.frameImageId, at: index)
    }
    actions.onInsertClip = { cutId, mediaId, index in
        _ = library.insertShotMedia(
            shotId: cutId,
            mediaId: mediaId,
            at: index,
            lensId: lensId
        )
    }
    actions.onMoveEntry = { cutId, entryId, index in
        library.moveShotEntry(shotId: cutId, entryId: entryId, toIndex: index)
    }
    actions.onRemoveEntry = { cutId, entryId in
        library.removeShotEntry(shotId: cutId, entryId: entryId)
    }
    actions.onSetSeamStyle = { cutId, entryId, style in
        surface.pictureUndo.applyState = { shotId, snapshot in
            library.restoreShotPictureState(shotId: shotId, snapshot: snapshot)
        }
        if let edit = library.setShotSeamStyle(shotId: cutId, entryId: entryId, style: style) {
            surface.pictureUndo.registerEdit(
                shotId: cutId,
                old: edit.before,
                new: edit.after,
                actionName: style == .cut ? "Seam: Hard Cut" : "Seam: Bridge",
                undoManager: surface.undoManager
            )
        }
    }
    actions.onOpenFrame = { cutId, entryId, heroImage in
        surface.onOpenFrameDetail(cutId, entryId, heroImage)
    }
    actions.onEnterExcursion = { cutId, entryId, heroImage in
        surface.onEnterExcursion(
            ExcursionLaunchRequest(
                cutId: cutId,
                entryId: entryId,
                rootImageId: heroImage.imageId
            )
        )
    }
    actions.onOpenClip = { cutId, entryId in
        surface.onOpenClipInspector(ShotClipInspectorRequest(shotId: cutId, entryId: entryId))
    }
    actions.onLeadIn = { cutId in
        library.insertShotLeadIn(shotId: cutId)
    }
    actions.onAppendPoolInput = { cutId, input in
        let count = library.shotTimeline.shots.first { $0.shotId == cutId }?.entries.count ?? 0
        if input.isClip {
            _ = library.insertShotMedia(
                shotId: cutId,
                mediaId: input.clipMediaId,
                at: count,
                lensId: lensId
            )
        } else {
            library.insertShotFrame(shotId: cutId, frameImageId: input.frameImageId, at: count)
        }
    }
    actions.onCreateFrameForCut = { cutId in
        surface.onLaunchFrameCreator(
            WorkbenchFrameCreatorLaunch(
                lensId: lensId,
                context: .shotFrame(appendToShotId: cutId)
            )
        )
    }
    actions.onArtDirectPlannedFrame = { heroImage in
        surface.onLaunchFrameCreator(
            WorkbenchFrameCreatorLaunch(
                lensId: lensId,
                context: .plannedFrame(heroImage)
            )
        )
    }
    actions.onKeepLookAsNewCut = { cutId in
        Task {
            // Lands directly below the source row; the engine refuses
            // honestly while any video op is in flight.
            _ = await library.continueActiveShotLookAsNewShot(shotId: cutId)
        }
    }
    actions.onPasteSegmentCards = { cutId, cards in
        surface.pictureUndo.applyState = { shotId, snapshot in
            library.restoreShotPictureState(shotId: shotId, snapshot: snapshot)
        }
        if let edit = library.pasteShotSegmentCards(shotId: cutId, cards: cards) {
            surface.pictureUndo.registerEdit(
                shotId: cutId,
                old: edit.before,
                new: edit.after,
                actionName: cards.count > 1 ? "Paste \(cards.count) Segments" : "Paste Segment",
                undoManager: surface.undoManager
            )
        }
    }
    // Any gesture on a row makes it the ACTIVE open row (the LRU law) —
    // wrapped once here rather than sprinkled through the strip.
    return actions.markingRowActive()
}
