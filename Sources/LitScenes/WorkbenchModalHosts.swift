import SwiftUI

/// The shot player with its embedded Re-render panel, hosted so both
/// workbench surfaces (the SCENES tab and the SCENES v2 boxes) present the
/// identical instrument. Resolves the LIVE shot and its prompt plan each
/// body pass (edits made anywhere appear immediately). Render persists the
/// edited overrides, closes the player, then starts the render.
/// Everything here is engine wiring; presentation writes route through the
/// three closures.
struct ShotPlayerSheetHost: View {
    @ObservedObject var library: LibraryEngine
    let request: ShotVideoRequest
    var onDismiss: () -> Void
    /// KEEP AS NEW SHOT reopens the player on the new row.
    var onReopen: (ShotVideoRequest) -> Void
    /// Dismisses and focuses the narration strip on the shot's row.
    var onFocusNarration: (String) -> Void
    @State private var sourceInspection: ShotClipInspectorRequest?
    @State private var endingSession: ShotContinuationReviewSession?
    @State private var pendingEndingEntryId = ""
    @State private var endingMessage = ""

    @State private var isTailPickerOpen = false
    @State private var frameCreatorLaunch: WorkbenchFrameCreatorLaunch?
    @State private var pendingFrameCreatorLaunch: WorkbenchFrameCreatorLaunch?
    @State private var pendingTailReview = false
    @State private var promptDraftSaveFailed = false
    @State private var directionDraftSaveFailed = false
    @State private var styleImagePreview: StyleImagePreviewRequest?
    @Environment(\.openSettings) private var openSettings
    @Environment(\.undoManager) private var undoManager
    @State private var focusedEntryId = ""
    @State private var editingScopeId = ""
    @StateObject private var editorPictureUndo = ShotPictureUndoCoordinator()

    private func registerContinuationEdit(_ edit: ShotPictureStateEdit?) {
        guard let edit else { return }
        editorPictureUndo.applyState = { id, snapshot in library.restoreShotPictureState(shotId: id, snapshot: snapshot) }
        editorPictureUndo.registerEdit(shotId: request.shotId, old: edit.before, new: edit.after,
            actionName: "Use continuation take", undoManager: undoManager)
    }

    private func editing<T>(scopeId: String? = nil, _ action: () -> T) -> T {
        let selected = scopeId ?? editingScopeId
        let selection = selected.isEmpty ? nil : ShotOutputEditContext.Selection(shotId: request.shotId, scopeId: selected)
        return ShotOutputEditContext.$selection.withValue(selection, operation: action)
    }

    private func editingAsync<T>(_ action: () async -> T) async -> T {
        let selection = editingScopeId.isEmpty ? nil : ShotOutputEditContext.Selection(shotId: request.shotId, scopeId: editingScopeId)
        return await ShotOutputEditContext.$selection.withValue(selection, operation: action)
    }

    private var tailActions: CutStripActions {
        makeCutStripActions(library: library,
            lensId: library.projectLenses.lenses.first?.lensId ?? "",
            frameLookup: library.projectWideFrameLookup,
            mediaLookup: Dictionary(library.items.map { ($0.mediaId, $0) }, uniquingKeysWith: { first, _ in first }),
            surface: CutStripWorkbenchSurface(
                onOpenPlayer: { next in
                    if !next.focusedEntryId.isEmpty { focusedEntryId = next.focusedEntryId }
                    if next.openEndingReview { reviewEnding(next.focusedEntryId) }
                },
                onLaunchFrameCreator: { pendingFrameCreatorLaunch = $0; isTailPickerOpen = false },
                pictureUndo: editorPictureUndo, undoManager: undoManager))
    }

    private var tailInputs: [StageInput] {
        scenesV2PoolInputs(displayedFrames: [],
            projectWideFrames: scenesV2PoolSourceFrames(Array(library.projectWideFrameLookup.values)),
            items: scenesV2SourceMaterialItems(library.browsableMediaItems))
    }

    private func savePromptDrafts(_ overrides: [ShotSegmentPromptOverride]) -> Bool {
        let saved = library.setShotSegmentPromptOverrides(shotId: request.shotId, overrides: overrides)
        promptDraftSaveFailed = !saved
        if !saved { endingMessage = "The prompt draft could not be saved. Retry from its segment card before rendering." }
        return saved
    }

    private var draftsSaved: Bool { !promptDraftSaveFailed && !directionDraftSaveFailed }

    private func reviewTail() { prepareSegmentReview(entryId: nil) }

    private func reviewEnding(_ entryId: String) { prepareSegmentReview(entryId: entryId) }

    private func prepareSegmentReview(entryId: String?) {
        guard let shot = library.shotTimeline.shots.first(where: { $0.shotId == request.shotId }) else { return }
        let targetId = entryId ?? shot.entries.first { shotPendingEndingEntryIds(shot).contains($0.entryId) }?.entryId ?? ""
        let initial = targetId.isEmpty ? library.shotContinuationAvailability(shotId: request.shotId)
            : shotEndingReviewPreview(shot: shot, entryId: targetId, frameLookup: library.projectWideFrameLookup)
        endingSession = ShotContinuationReviewSession(intent: targetId.isEmpty ? .append
            : (initial.targetFrame == nil ? .retake(targetId) : .ending(targetId)), initial: initial)
    }

    private var scopedAudioRegionActions: ShotAudioRegionActions {
        ShotAudioRegionActions(
                    add: { laneId, asset, startSeconds in
                        editing { library.addShotAudioRegion(
                            shotId: request.shotId,
                            laneId: laneId,
                            asset: asset,
                            startSeconds: startSeconds
                        ) }
                    },
                    addTrack: { kind, asset, startSeconds in
                        editing { library.addShotAudioTrack(
                            shotId: request.shotId,
                            kind: kind,
                            asset: asset,
                            startSeconds: startSeconds
                        ) }
                    },
                    move: { regionId, startSeconds in
                        editing { library.moveShotAudioRegion(
                            shotId: request.shotId,
                            regionId: regionId,
                            startSeconds: startSeconds
                        ) }
                    },
                    setGeometry: { regionId, start, sourceStart, duration in
                        editing { library.setShotAudioRegionGeometry(
                            shotId: request.shotId,
                            regionId: regionId,
                            startSeconds: start,
                            sourceStartSeconds: sourceStart,
                            durationSeconds: duration
                        ) }
                    },
                    split: { regionId, atSeconds in
                        editing { library.splitShotAudioRegion(
                            shotId: request.shotId,
                            regionId: regionId,
                            atSeconds: atSeconds
                        ) }
                    },
                    setLoops: { regionId, loops in
                        editing { library.setShotAudioRegionLoops(
                            shotId: request.shotId,
                            regionId: regionId,
                            loops: loops
                        ) }
                    },
                    replaceMedia: { regionId, asset in
                        editing { library.replaceShotAudioRegionMedia(
                            shotId: request.shotId,
                            regionId: regionId,
                            asset: asset
                        ) }
                    },
                    update: { region in
                        editing { library.setShotAudioRegion(shotId: request.shotId, region: region) }
                    },
                    makeAudible: { regionId in
                        editing { library.makeShotAudioRegionAudible(
                            shotId: request.shotId,
                            regionId: regionId
                        ) }
                    },
                    delete: { regionId in
                        editing { library.deleteShotAudioRegion(shotId: request.shotId, regionId: regionId) }
                    },
                    restore: { region in
                        editing { library.restoreShotAudioRegion(shotId: request.shotId, region: region) }
                    },
                    restoreState: { snapshot in
                        editing(scopeId: snapshot.scopeId, { library.restoreShotAudioState(
                            shotId: request.shotId,
                            snapshot: snapshot
                        ) })
                    },
                    currentRegion: { regionId in
                        editing { library.shotForEditing(shotId: request.shotId)?.audioRegions.first { $0.regionId == regionId } }
                    },
                    importAudioFiles: { urls in
                        await library.importAudioMediaFiles(urls)
                    },
                    backfillDurations: {
                        await editingAsync { await library.backfillShotAudioRegionSourceDurations(shotId: request.shotId) }
                    },
                    setSourceSegment: { segmentKey, gain, isMuted in
                        editing { library.setShotSourceSegmentAudio(
                            shotId: request.shotId,
                            segmentKey: segmentKey,
                            gain: gain,
                            isMuted: isMuted
                        ) }
                    },
                    detachSourceSegment: { segmentKey in
                        editing { library.detachShotSourceSegmentAudio(
                            shotId: request.shotId,
                            segmentKey: segmentKey
                        ) }
                    },
                    restoreSourceDetach: { snapshot in
                        editing { library.restoreShotSourceDetach(shotId: request.shotId, snapshot: snapshot) }
                    },
                    currentSourceState: {
                        let shot = editing { library.shotForEditing(shotId: request.shotId) }
                        return ShotSourceDetachSnapshot(
                            sourceSegmentAudio: shot?.sourceSegmentAudio ?? [],
                            audioRegions: shot?.audioRegions ?? []
                        )
                    },
                    addLane: { kind in
                        editing { library.addShotAudioLane(shotId: request.shotId, kind: kind) }
                    },
                    removeLane: { laneId in
                        editing { library.removeShotAudioLane(shotId: request.shotId, laneId: laneId) }
                    },
                    moveToLane: { regionId, laneId in
                        editing { library.moveShotAudioRegionToLane(
                            shotId: request.shotId,
                            regionId: regionId,
                            laneId: laneId
                        ) }
                    },
                    setLaneEnabled: { laneId, enabled in
                        editing { library.setShotAudioLaneEnabled(
                            shotId: request.shotId,
                            laneId: laneId,
                            enabled: enabled
                        ) }
                    },
                    setLaneVolume: { laneId, volume in
                        editing { library.setShotAudioLaneVolume(
                            shotId: request.shotId,
                            laneId: laneId,
                            volume: volume
                        ) }
                    },
                    activateTake: { takeId in
                        editing { library.activateShotMicrophoneTake(
                            shotId: request.shotId,
                            takeId: takeId
                        ) }
                    },
                    addBatch: { laneId, assets, startSeconds in
                        editing { library.addShotAudioRegionBatch(
                            shotId: request.shotId,
                            laneId: laneId,
                            assets: assets,
                            startSeconds: startSeconds
                        ) }
                    },
                    deleteMany: { regionIds in
                        editing { library.deleteShotAudioRegions(
                            shotId: request.shotId,
                            regionIds: regionIds
                        ) }
                    },
                    paste: { payload, preferredLaneId, startSeconds in
                        editing { library.pasteShotAudioRegion(
                            shotId: request.shotId,
                            payload: payload,
                            preferredLaneId: preferredLaneId,
                            startSeconds: startSeconds
                        ) }
                    },
                    duplicate: { regionId in
                        editing { library.duplicateShotAudioRegion(
                            shotId: request.shotId,
                            regionId: regionId
                        ) }
                    }
                )
    }

    private func scopedPlayer(shot: ProjectShot, ordinal: Int) -> ShotRenderPlayerModal {
        let plan = library.shotRenderPromptPlan(shot: shot)
        return ShotRenderPlayerModal(
                shot: shot,
                shotOrdinal: ordinal,
                planSegments: plan?.segments ?? [],
                skipped: plan?.skipped ?? [],
                skippedPlaceholders: plan?.skippedPlaceholders ?? [],
                isRenderBlocked: library.cutHasInFlightVideoOperation(cutId: request.shotId),
                configuredRenderModels: Set(
                    ShotRenderModel.allCases.filter(library.canExecuteShotRenderModel)
                ),
                falPricing: library.falPricing,
                isFetchingVideoPricing: library.isFetchingFALPricing,
                openPanelInitially: request.openRerenderPanel,
                initialFocusedEntryId: focusedEntryId.isEmpty ? request.focusedEntryId : focusedEntryId,
                initialFocusedSegmentKey: request.focusedSegmentKey,
                initialPreview: request.initialPreview,
                autoplayOnOpen: request.autoplay,
                openProvenanceOnOpen: request.openProvenance,
                onInspectSource: { entryId in
                    sourceInspection = ShotClipInspectorRequest(shotId: request.shotId, entryId: entryId)
                },
                onReviewEnding: { entryId in reviewEnding(entryId) },
                editingOutputScopeId: editingScopeId,
                outputScopeStatus: library.outputScopePreparation[request.shotId],
                onRetryOutputScope: { library.scheduleOutputScopeRefresh() },
                onSelectOutputScope: { editingScopeId = $0 },
                onExtend: { isTailPickerOpen = true },
                onNewVersion: {
                    guard draftsSaved else {
                        endingMessage = "Save the current segment drafts before creating a New Version."
                        return
                    }
                    let copyId = library.duplicateCut(cutId: request.shotId)
                    if !copyId.isEmpty {
                        focusedEntryId = ""
                        promptDraftSaveFailed = false
                        directionDraftSaveFailed = false
                        onReopen(ShotVideoRequest(shotId: copyId, intent: .edit))
                    }
                },
                onRebuild: { overrides in
                    guard draftsSaved else { return }
                    Task { _ = await library.rebuildShotGeneratedChain(shotId: request.shotId) }
                },
                rebuildEstimate: library.shotContinuationRechainEstimate(shotId: request.shotId, rebuildAll: true),
                continuationEntryEstimate: { entryIds in
                    library.shotContinuationEstimate(shotId: request.shotId, entryIds: entryIds)
                },
                continuationBranchImpact: { entryId, takeId in
                    library.shotContinuationBranchImpact(
                        shotId: request.shotId,
                        entryId: entryId,
                        takeId: takeId
                    )
                },
                onUseContinuationTake: { impact in
                    Task { registerContinuationEdit(await library.useShotContinuationTake(shotId: request.shotId, impact: impact)) }
                },
                onRepairContinuationTake: { entryId, takeId in
                    await library.repairShotContinuationTake(shotId: request.shotId, entryId: entryId, takeId: takeId)
                },
                onRechainContinuations: {
                    await library.rechainShotContinuations(shotId: request.shotId)
                },
                onSetDefaultRenderStack: { stack in
                    library.setShotRenderStack(shotId: request.shotId, stack: stack)
                },
                onSetSegmentRenderStack: { pair, stack in
                    library.setShotSegmentRenderOverride(
                        shotId: request.shotId,
                        startFrameImageId: pair.start?.imageId ?? "",
                        endFrameImageId: pair.end?.imageId ?? "",
                        placementStartEntryId: pair.startPlacementEntryId,
                        placementEndEntryId: pair.endPlacementEntryId,
                        stack: stack
                    )
                },
                onRender: { overrides in
                    let shotId = request.shotId
                    guard draftsSaved else { return }
                    if let shot = library.shotTimeline.shots.first(where: { $0.shotId == shotId }),
                       let entryId = shotPendingEndingForRender(shot: shot, segments: library.shotRenderPromptPlan(shotId: shotId)?.segments ?? [], keys: nil) {
                        reviewEnding(entryId)
                        return
                    }
                    Task { await library.renderShot(shotId: shotId) }
                },
                onRenderSegment: { overrides, segmentKey in
                    let shotId = request.shotId
                    guard draftsSaved else { return }
                    let livePlan = library.shotRenderPromptPlan(shotId: shotId)?.segments ?? []
                    if let shot = library.shotTimeline.shots.first(where: { $0.shotId == shotId }),
                       let item = livePlan.compactMap({ segment -> ShotSegmentPromptPlanItem? in
                           if case .generated(let item) = segment { return item }; return nil
                       }).first(where: { $0.pair.placementKey == segmentKey }),
                       shot.continuationRecord(entryId: item.pair.endPlacementEntryId) != nil
                        || shotPendingEndingEntryIds(shot).contains(item.pair.endPlacementEntryId) {
                        reviewEnding(item.pair.endPlacementEntryId)
                        return
                    }
                    Task { await library.renderShot(shotId: shotId, onlySegmentKeys: [segmentKey]) }
                },
                onPersistPromptDrafts: { updates in
                    let saved = library.saveShotPromptDrafts(shotId: request.shotId, updates: updates)
                    promptDraftSaveFailed = !saved
                    directionDraftSaveFailed = !saved
                    if !saved { endingMessage = "The prompt could not be saved. Retry from its segment card before rendering." }
                    return saved
                },
                canAssistPrompts: library.canAssistShotPrompts,
                onAssistPrompt: { await library.assistShotPrompt($0) },
                onAutosaveOverrides: { overrides in _ = savePromptDrafts(overrides) },
                onSaveDirectionPlans: { plans in
                    let saved = library.setShotSegmentDirectionPlans(shotId: request.shotId, plans: plans)
                    directionDraftSaveFailed = !saved
                    if !saved { endingMessage = "The Beats draft could not be saved. Retry from its segment card before rendering." }
                },
                draftingDirectionKeys: library.draftingDirectionSegmentKeys,
                directionDraftErrors: library.directionDraftErrors,
                onDraftDirectionPlan: { segmentKey in
                    let shotId = request.shotId
                    Task {
                        await library.draftShotSegmentDirectionPlan(shotId: shotId, segmentKey: segmentKey)
                    }
                },
                onDraftAllDirectionPlans: {
                    let shotId = request.shotId
                    Task {
                        await library.draftAllShotSegmentDirectionPlans(shotId: shotId)
                    }
                },
                onSetSeamStyle: { entryId, style, intent in
                    editing { library.setShotSeamStyle(
                        shotId: request.shotId,
                        entryId: entryId,
                        style: style,
                        intent: intent
                    ) }
                },
                onSetEntrySkipped: { entryId, skipped in
                    editing { library.setShotEntrySkipped(shotId: request.shotId, entryId: entryId, skipped: skipped) }
                },
                onSetCutList: { cutList in
                    editing { library.setShotCutList(shotId: request.shotId, cutList: cutList) }
                },
                onSetCutReversed: { reversed in
                    editing { library.setShotCutReversed(shotId: request.shotId, reversed: reversed) }
                },
                onRetryReverseProxies: {
                    // Opening the shot is a deliberate act, so it is the right
                    // moment to try a failed bake again — and the only reason a
                    // reversed CUT would otherwise sit playing forward forever.
                    await editingAsync { await library.ensureReverseProxies(shotId: request.shotId) }
                },
                reverseBakeProgress: library.reverseBakeProgress[request.shotId],
                hasFALCredential: library.videoProviderCredentialStatuses
                    .first(where: { $0.provider == .fal })?.isConfigured == true,
                hasDecartCredential: library.videoProviderCredentialStatuses
                    .first(where: { $0.provider == .decart })?.isConfigured == true,
                activeShotJoinRenderId: library.activeJoinId(for: request.shotId),
                onSetJoinRepair: { cutId, repair in
                    editing { library.setShotRazorJoinRepair(
                        shotId: request.shotId,
                        cutId: cutId,
                        repair: repair
                    ) }
                },
                onRestoreRazorCut: { cutId in
                    editing { library.restoreShotRazorCut(shotId: request.shotId, cutId: cutId) }
                },
                onRestorePictureState: { snapshot in
                    editing(scopeId: snapshot.scopeId, { library.restoreShotPictureState(shotId: request.shotId, snapshot: snapshot) })
                },
                onRenderJoinBridge: { cutId, provider, duration, prompt in
                    Task {
                        await editingAsync { await library.renderShotRazorJoinBridge(
                            shotId: request.shotId,
                            cutId: cutId,
                            provider: provider,
                            durationSeconds: duration,
                            prompt: prompt
                        ) }
                    }
                },
                onPrepareJoinFrames: { cutId in
                    await editingAsync { await library.prepareShotRazorJoinFrames(
                        shotId: request.shotId,
                        cutId: cutId
                    ) }
                },
                onCommitMicrophoneTake: { recording, startSeconds in
                    await editingAsync { await library.commitShotMicrophoneTake(
                        shotId: request.shotId,
                        recording: recording,
                        startSeconds: startSeconds
                    ) }
                },
                onDeleteMicrophoneTake: { takeId in
                    _ = editing { library.deleteShotMicrophoneTake(shotId: request.shotId, takeId: takeId) }
                },
                ambientBeds: library.ambientBedLibrary.beds,
                audioClips: library.projectAudioItems,
                isBakingAmbientBed: library.isBakingAmbientBed,
                onSaveAmbientBed: { spec in
                    await library.saveAmbientBed(spec: spec)
                },
                onDeleteAmbientBed: { bedId in
                    library.deleteAmbientBed(bedId: bedId)
                },
                onRenameAmbientBed: { bedId, displayName in
                    library.renameAmbientBed(bedId: bedId, displayName: displayName)
                },
                onSetAmbientBed: { bedId in
                    editing { library.setShotAmbientBed(shotId: request.shotId, bedId: bedId) }
                },
                onOpenNarration: {
                    onFocusNarration(request.shotId)
                },
                audioRegionActions: scopedAudioRegionActions,
                restylePromptSeed: library.shotLookPromptSeed(),
                activeShotRestyleId: library.activeLookVersionId(for: request.shotId),
                onActivateLook: { versionId in
                    editing { library.activateShotLookVersion(shotId: request.shotId, versionId: versionId) }
                },
                onStartRestyle: { prompt, enhancePrompt, seed, style, provider in
                    editing { library.startShotLookRestyle(
                        shotId: request.shotId,
                        prompt: prompt,
                        enhancePrompt: enhancePrompt,
                        seed: seed,
                        style: style,
                        provider: provider
                    ) }
                },
                onCancelRestyle: {
                    editing { library.cancelShotLookRestyle(shotId: request.shotId) }
                },
                onRetryRestyle: { versionId in
                    editing { library.retryShotLook(shotId: request.shotId, versionId: versionId) }
                },
                onContinueLookAsNewShot: {
                    let newShotId = await editingAsync { await library.continueActiveShotLookAsNewShot(shotId: request.shotId) }
                    if let newShotId {
                        onReopen(ShotVideoRequest(shotId: newShotId))
                    }
                    return newShotId
                },
                onSendToFootage: {
                    await editingAsync { await library.sendShotOutputToFootage(shotId: request.shotId) }
                },
                onExportForYouTube: {
                    await editingAsync { await library.exportShotOutputForYouTube(shotId: request.shotId) }
                },
                onCollectFrame: { path, fileSeconds, outputSeconds in
                    await library.collectShotFrameStill(
                        shotId: request.shotId,
                        sourceVideoPath: path,
                        fileSeconds: fileSeconds,
                        outputSeconds: outputSeconds
                    ) != nil
                },
                projectId: library.currentProject?.projectId ?? "",
                onPastePictureSegments: { insertions, status in
                    editing { library.pasteShotPictureSegments(
                        shotId: request.shotId,
                        insertions: insertions,
                        status: status
                    ) }
                },
                onRemovePictureInsertions: { insertionIds in
                    editing { library.removeShotPictureInsertions(
                        shotId: request.shotId,
                        insertionIds: insertionIds
                    ) }
                },
                onSetPictureInsertionRate: { insertionIds, rate in
                    editing { library.setShotPictureInsertionRate(
                        shotId: request.shotId,
                        insertionIds: insertionIds,
                        rate: rate
                    ) }
                },
                onSetPictureInsertionMuted: { insertionIds, muted in
                    editing { library.setShotPictureInsertionMuted(
                        shotId: request.shotId,
                        insertionIds: insertionIds,
                        muted: muted
                    ) }
                },
                onRecopyPictureInsertion: { insertionId in
                    editing { library.recopyShotPictureInsertion(
                        shotId: request.shotId,
                        insertionId: insertionId
                    ) }
                },
                onPasteSegmentCards: { cards, afterEntryId in
                    editing { library.pasteShotSegmentCards(
                        shotId: request.shotId,
                        cards: cards,
                        afterEntryId: afterEntryId
                    ) }
                },
                onSetSectionRate: { materialStart, materialEnd, rate in
                    let edit = editing { library.setShotSectionRate(
                        shotId: request.shotId,
                        materialStart: materialStart,
                        materialEnd: materialEnd,
                        rate: rate
                    ) }
                    return ShotSectionRateResult(edit: edit, message: library.aestheticStatus)
                },
                onClose: {
                    onDismiss()
                }
            )
    }

    @ViewBuilder
    var body: some View {
        if let index = library.shotTimeline.shots.firstIndex(where: { $0.shotId == request.shotId }) {
            let rootShot = library.shotTimeline.shots[index]
            let editorShot = rootShot.outputScope(editingScopeId)?.project(from: rootShot) ?? rootShot
            scopedPlayer(shot: editorShot, ordinal: index + 1)
            .id(request.shotId + ":" + editingScopeId)
            .sheet(item: $sourceInspection) { source in
                if library.shotTimeline.shots.first(where: { $0.shotId == source.shotId })?.entries.first(where: { $0.entryId == source.entryId })?.isClip == true {
                    ShotClipInspectorView(library: library, shotId: source.shotId, entryId: source.entryId,
                        onClose: { sourceInspection = nil })
                } else {
                    ShotSourceFrameInspection(library: library, shotId: source.shotId, entryId: source.entryId,
                        onClose: { sourceInspection = nil })
                }
            }
            .sheet(isPresented: $isTailPickerOpen, onDismiss: {
                if let launch = pendingFrameCreatorLaunch {
                    pendingFrameCreatorLaunch = nil
                    frameCreatorLaunch = launch
                } else if pendingTailReview {
                    pendingTailReview = false
                    let target = pendingEndingEntryId
                    pendingEndingEntryId = ""
                    prepareSegmentReview(entryId: target.isEmpty ? nil : target)
                }
            }) {
                ShotTailPickerMenu(cut: library.shotTimeline.shots[index], poolInputs: tailInputs,
                    actions: tailActions,
                    onEnding: { pendingEndingEntryId = $0; pendingTailReview = true; isTailPickerOpen = false },
                    onAI: { pendingTailReview = true; isTailPickerOpen = false },
                    onClose: { isTailPickerOpen = false })
            }
            .sheet(item: $frameCreatorLaunch) { launch in
                if let lens = library.projectLenses.lenses.first(where: { $0.lensId == launch.lensId }) {
                    FrameCreatorModalHost(library: library, lens: lens, launch: launch,
                        onDismiss: { frameCreatorLaunch = nil },
                        onPreviewStyle: { styleImagePreview = $0 },
                        onOpenAppSettings: { openSettings() })
                        .sheet(item: $styleImagePreview) { request in StyleImagePreviewModal(request: request) }
                }
            }
            .onChange(of: library.shotTimeline.shots[index].entries.map(\.entryId)) { old, new in
                if let appended = new.last, !old.contains(appended) { focusedEntryId = appended }
            }
            .sheet(item: $endingSession) { session in
                ShotContinuationReviewSheet(session: session,
                    configuredModels: Set(ShotRenderModel.allCases.filter(library.canExecuteShotRenderModel)),
                    pricing: library.falPricing, prepare: {
                        if !draftsSaved {
                            var value = session.initial
                            value.preparationError = "The latest direction could not be saved. Close this review and retry saving on the segment card."
                            return value
                        }
                        return session.entryId.isEmpty ? await library.prepareShotContinuationAvailability(shotId: request.shotId)
                            : await library.prepareShotContinuationRetakeAvailability(shotId: request.shotId, entryId: session.entryId)
                    }, onPrecedingEnding: { reviewEnding($0) }, onCancel: { endingSession = nil }, onRender: { recipe in
                        endingSession = nil
                        Task {
                            let before = library.shotTimeline.shots.first { $0.shotId == request.shotId }
                            let outcome = session.entryId.isEmpty
                                ? await library.startShotContinuation(shotId: request.shotId, request: recipe)
                                : await library.startShotContinuationRetake(shotId: request.shotId, entryId: session.entryId, request: recipe)
                            registerContinuationEdit(shotContinuationSelectionEdit(before: before,
                                after: library.shotTimeline.shots.first { $0.shotId == request.shotId }, outcome: outcome))
                        }
                    }).id(session.id)
            }
            .onAppear {
                library.scheduleOutputScopeRefresh()
                if request.openEndingReview { reviewEnding(request.focusedEntryId) }
                // The re-render panel shows spend estimates; refresh the
                // day-cached FAL rates whenever the player opens (mirrors
                // the render-plan strip's onRenderPlanOpened trigger).
                Task {
                    await library.refreshFALPricingIfStale()
                }
            }
        } else {
            Color.clear
                .frame(width: 200, height: 120)
                .onAppear { onDismiss() }
        }
    }
}

/// The Jovilabe modal, hosted for both workbench surfaces. Resolves the LIVE
/// shot each render (honesty: edits made anywhere appear immediately;
/// auto-dismisses if the shot was deleted).
struct JovilabeSheetHost: View {
    @ObservedObject var library: LibraryEngine
    let request: JovilabeRequest
    var workspaceSize: CGSize = .zero
    var onDismiss: () -> Void
    /// Dismisses, then opens the tapped frame's detail on the host surface.
    var onOpenFrame: (ProjectLensHeroImage) -> Void

    var body: some View {
        if let index = library.shotTimeline.shots.firstIndex(where: { $0.shotId == request.shotId }) {
            ShotJovilabeModal(
                shot: library.shotTimeline.shots[index],
                shotOrdinal: index + 1,
                frameLookup: library.projectWideFrameLookup,
                meaningNodes: library.lensContext.promptPacket().meaningNodes,
                workspaceSize: workspaceSize,
                onMoveEntry: { shotId, entryId, gapIndex in
                    library.moveShotEntry(shotId: shotId, entryId: entryId, toIndex: gapIndex)
                },
                onOpenFrame: { heroImage in
                    onDismiss()
                    onOpenFrame(heroImage)
                },
                onClose: onDismiss
            )
        } else {
            Color.clear
                .frame(width: 200, height: 120)
                .onAppear(perform: onDismiss)
        }
    }
}

/// The Frame Creator modal for the SCENES v2 surface. Behavior-parallel with
/// the SCENES tab's `workbenchFrameCreatorModal` (same engine calls, same
/// context switch) with two v2 differences: the render version is always the
/// lens's NEWEST media version (v2 has no version timeline), and there is no
/// draft editor to sync (`onAfterMutation` is the seam where v1 syncs).
/// Consolidating v1 onto this host is future work.
struct FrameCreatorModalHost: View {
    @ObservedObject var library: LibraryEngine
    let lens: ProjectLens
    let launch: WorkbenchFrameCreatorLaunch
    var workspaceSize: CGSize = .zero
    var onDismiss: () -> Void
    var onPreviewStyle: (StyleImagePreviewRequest) -> Void
    var onOpenAppSettings: () -> Void
    var onAfterMutation: () -> Void = {}
    /// Fires the moment a submit is accepted (before any render completes) —
    /// a host that cannot show the generating take uses it to go where it lands.
    var onSubmitted: () -> Void = {}

    private var versionId: String {
        lens.mediaVersionIds.last ?? ""
    }

    private func credentialConfigured(_ provider: LitScenesProviderCredential) -> Bool {
        library.videoProviderCredentialStatuses
            .first(where: { $0.provider == provider })?.isConfigured == true
    }

    var body: some View {
        FrameCreatorModal(
            lens: lens,
            context: launch.context,
            workspaceSize: workspaceSize,
            moodboardItems: library.enabledContentItems.filter { $0.kind == .image },
            moodObservationsById: library.mediaObservationsById,
            hasOpenAICredential: credentialConfigured(.openAI),
            hasCivitaiCredential: credentialConfigured(.civitai),
            hasFALCredential: credentialConfigured(.fal),
            hasStabilityCredential: credentialConfigured(.stability),
            isRenderBlocked: library.frameSubmissionBlockReason != nil,
            renderBlockerHelp: library.frameSubmissionBlockReason,
            takeLaneFreeSlots: library.lensHeroTakeLaneFreeSlots,
            formGenerations: library.frameForms.generations.map(\.options).filter { !$0.isEmpty },
            isAnalyzingMoods: library.isAnalyzingMedia,
            onAutoAnalyzeMoods: {
                Task {
                    await library.analyzeUnanalyzedEnabledMedia()
                }
            },
            onOpenAppSettings: onOpenAppSettings,
            onPreviewStyle: onPreviewStyle,
            onExpandFormOption: { option, styleFitLine in
                await library.expandFrameForms(from: option, styleFitLine: styleFitLine)
            },
            onTransformFormPrompt: { prompt, directive, priorDirectives in
                await library.transformFormPrompt(
                    prompt: prompt,
                    directive: directive,
                    priorDirectives: priorDirectives
                )
            },
            onSubmit: { requests in
                var acceptedCount = 0
                // One Task per request: each start AWAITS its render, so the
                // batch must fan out for the take lane to hold them at once.
                for (index, request) in requests.enumerated() {
                    Task {
                        await WorkflowCoordinator.shared.run(project: library.currentProject, workflow: "frame_render",
                            artifactType: "scene_plan", artifactId: launch.lensId, lane: .image,
                            recipeJSON: workflowRecipe(request), failure: (), onAccepted: {
                                acceptedCount += 1
                                if acceptedCount == requests.count {
                                    onDismiss()
                                    onSubmitted()
                                }
                            }) {
                        switch launch.context {
                        case .blankFrame(let category):
                            _ = await library.startLensHeroNewTakeRender(
                                lensId: launch.lensId,
                                templateImageId: nil,
                                blankCategory: category,
                                versionId: versionId,
                                request: request
                            )
                        case .plannedFrame(let planned):
                            // The FIRST stack fulfills the planned card in
                            // place; the rest land as ordinary takes from the
                            // same planned template (one card, no twins).
                            if index == 0 {
                                _ = await library.startLensHeroPlanFulfillmentRender(
                                    lensId: launch.lensId,
                                    plannedImageId: planned.imageId,
                                    request: request
                                )
                            } else {
                                _ = await library.startLensHeroNewTakeRender(
                                    lensId: launch.lensId,
                                    templateImageId: planned.imageId,
                                    versionId: versionId,
                                    request: request
                                )
                            }
                        case .variation(let template), .restyle(let template), .groupTake(_, let template):
                            _ = await library.startLensHeroNewTakeRender(
                                lensId: launch.lensId,
                                templateImageId: template.imageId,
                                versionId: versionId,
                                request: request,
                                // A strip-launched variation/restyle lands its
                                // generating row beside the source cell.
                                onRowCreated: launch.placeBeside.map { navigation in
                                    { [weak library] childImageId in
                                        library?.placeTransformChildBesideSource(
                                            cutId: navigation.cutId,
                                            sourceEntryId: navigation.entryId,
                                            parentImageId: template.imageId,
                                            imageId: childImageId
                                        )
                                    }
                                }
                            )
                        case .clipMoment(let seed):
                            _ = await library.startClipMomentRender(
                                seed: seed,
                                lensId: launch.lensId,
                                versionId: versionId,
                                request: request
                            )
                        case .stageFrame(let stageId, let appendToCutId):
                            _ = await library.startStageFrameRender(
                                stageId: stageId,
                                appendToCutId: appendToCutId,
                                lensId: launch.lensId,
                                versionId: versionId,
                                request: request
                            )
                        case .shotFrame(let appendToShotId):
                            _ = await library.startShotFrameRender(
                                appendToShotId: appendToShotId,
                                lensId: launch.lensId,
                                versionId: versionId,
                                request: request
                            )
                        }
                        onAfterMutation()
                        }
                    }
                }
            },
            onCancel: onDismiss,
            mentionEntries: library.frameCreatorMentionEntries(for: lens),
            mentionReferenceItems: library.browsableMediaItems.filter { $0.kind == .image },
            onEnsureMentionSheet: { entry in
                switch entry.kind {
                case .character:
                    return await library.buildCharacterCompositeSheet(characterId: entry.id)
                case .object:
                    return await library.buildObjectCompositeSheet(objectId: entry.id)
                case .place:
                    return await library.buildPlaceCompositeSheet(placeId: entry.id)
                }
            },
            referenceLibraryItems: library.browsableMediaItems.filter { $0.kind == .image },
            initialReferenceItems: launch.referenceMediaIds.compactMap { mediaId in
                library.items.first { $0.mediaId == mediaId && $0.kind == .image }
            },
            generatedFrameCandidates: generatedFrameReferenceCandidates(lenses: library.projectLenses.lenses, items: library.browsableMediaItems),
            onAdoptGeneratedFrame: { hero in
                await library.archiveHeroFrameAsReference(hero)
            },
            onUploadReferences: {
                await library.chooseFrameReferenceImages()
            },
            // THE IDENTITY LADDER: sheet, else composite, else source photos —
            // ART-DIRECT attaches what the one-click RENDER attaches.
            identityFromSheetsOnly: false
        )
    }
}

/// A frame-detail overlay opened from a cut cell browses the CUT's entries;
/// this pair carries that context. (The SCENES tab keeps its own private
/// equivalent — this one belongs to the hosted overlay.)
struct HeroPreviewCutNavigation: Equatable {
    var cutId: String
    var entryId: String
}

/// The frame-detail overlay (LensHeroPreviewModal) for the SCENES v2 surface.
/// Behavior-parallel with the SCENES tab's inline wiring — same component,
/// same closure laws, same stale-lensId resolution — self-contained so a
/// second workbench can present frame detail without forking the modal.
/// `onAfterMutation` is the seam where v1 syncs its draft editor (v2: no-op).
/// Consolidating v1 onto this host is future work.
struct HeroPreviewModalHost: View {
    @ObservedObject var library: LibraryEngine
    @Binding var request: LensHeroPreviewRequest?
    @Binding var cutNavigation: HeroPreviewCutNavigation?
    var collectionSelection: Binding<FrameBrowseSelection?> = .constant(nil)
    private var browseSelection: FrameBrowseSelection? {
        get { collectionSelection.wrappedValue }
        nonmutating set { collectionSelection.wrappedValue = newValue }
    }
    var collectionItems: [FrameBrowseReference] = []
    /// Optional outside a workbench. Media reuses the truthful Frame detail
    /// without advertising Frame-Creator or Excursion actions it cannot host.
    var onLaunchFrameCreator: ((WorkbenchFrameCreatorLaunch) -> Void)? = nil
    var onEnterExcursion: ((ExcursionLaunchRequest) -> Void)? = nil
    /// Starts a new Scene from the shown Frame (its image id); the host
    /// closes first so the staged Scene is visible. nil hides the action.
    var onStartScene: ((String) -> Void)? = nil
    var onOpenAppSettings: () -> Void
    var onAfterMutation: () -> Void = {}

    @State private var zoom: CGFloat = 1
    @State private var actionStatus = ""

    private func credentialConfigured(_ provider: LitScenesProviderCredential) -> Bool {
        library.videoProviderCredentialStatuses
            .first(where: { $0.provider == provider })?.isConfigured == true
    }

    var body: some View {
        if let current = request {
            LensHeroPreviewModal(
                request: current,
                promptSettings: library.projectPromptSettings,
                browseItems: browseItems(),
                currentBrowseId: currentBrowseId(),
                onOpenBrowseItem: { item in openBrowseItem(item) },
                zoomScale: $zoom,
                reframeSubmissionBlockReason: library.frameSubmissionBlockReason ?? "",
                isNarrating: library.isGeneratingLensNarration,
                hasOpenAICredential: credentialConfigured(.openAI),
                hasFALCredential: credentialConfigured(.fal),
                hasStabilityCredential: credentialConfigured(.stability),
                onMakeActive: { activated in
                    // Resolve by IMAGE id across lenses: the request's lensId
                    // can go stale for cut-opened frames, and a refusal must
                    // state itself in the modal.
                    guard let resolved = resolvedHeroImageAcrossLenses(imageId: activated.imageId) else {
                        actionStatus = "That frame no longer exists"
                        return
                    }
                    if library.setLensHeroImageActiveVersion(lensId: resolved.lens.lensId, imageId: activated.imageId) {
                        actionStatus = ""
                        onAfterMutation()
                        request = previewRequest(lensId: resolved.lens.lensId, imageId: activated.imageId)
                            ?? activated.activeCopy()
                    } else {
                        actionStatus = library.aestheticStatus.trimmed.nilIfEmpty
                            ?? "Could not make this version active"
                    }
                },
                onOpenVersion: { item in
                    if let next = previewRequest(lensId: current.lensId, imageId: item.imageId) {
                        actionStatus = ""
                        request = next
                        zoom = 1
                    }
                },
                onReframe: { spec, stack, promptBody in
                    let lensId = current.lensId
                    let parentImageId = current.imageId
                    // A strip-opened frame places its child beside the source
                    // cell the moment the generating row exists (nav is nil
                    // for pool/Jovilabe opens — those keep landing in the
                    // pool). Captured BEFORE the teardown below. The deep
                    // zoom-out chain never fires onRowCreated, so multi-pass
                    // results stay pool-only by that law.
                    let placement = cutNavigation
                    // Close so the child's generating card is visible once it lands.
                    request = nil
                    cutNavigation = nil
                    browseSelection = nil
                    Task {
                        _ = await library.startLensHeroReframeRender(
                            lensId: lensId,
                            parentImageId: parentImageId,
                            spec: spec,
                            stack: stack,
                            promptBody: promptBody,
                            onRowCreated: placement.map { navigation in
                                { [weak library] childImageId in
                                    library?.placeTransformChildBesideSource(
                                        cutId: navigation.cutId,
                                        sourceEntryId: navigation.entryId,
                                        parentImageId: parentImageId,
                                        imageId: childImageId
                                    )
                                }
                            }
                        )
                        onAfterMutation()
                    }
                },
                onOpenRelated: { imageId in
                    if let next = previewRequest(lensId: current.lensId, imageId: imageId) {
                        request = next
                        zoom = 1
                    }
                },
                onNarrate: { voicePresetId in
                    let lensId = current.lensId
                    let imageId = current.imageId
                    Task {
                        _ = await library.startLensHeroNarration(
                            lensId: lensId,
                            imageId: imageId,
                            voicePresetId: voicePresetId
                        )
                        onAfterMutation()
                        // The modal stays open through narration; refresh it in
                        // place so the bar reflects the finished artifact.
                        if request?.imageId == imageId,
                           let refreshed = previewRequest(lensId: lensId, imageId: imageId) {
                            request = refreshed
                        }
                    }
                },
                onOpenSettings: onOpenAppSettings,
                onVariation: onLaunchFrameCreator == nil
                    ? nil
                    : { launchFrameCreator(imageId: current.imageId, restyle: false) },
                onRestyle: onLaunchFrameCreator == nil
                    ? nil
                    : { launchFrameCreator(imageId: current.imageId, restyle: true) },
                // The attached-motion (ANIMATE) lane is not offered here: the
                // Frame's next step is a Scene, which owns every video render.
                onStartScene: onStartScene.map { start in
                    {
                        let imageId = current.imageId
                        request = nil
                        cutNavigation = nil
                    browseSelection = nil
                        start(imageId)
                    }
                },
                onRetry: {
                    let imageId = current.imageId
                    guard let resolved = resolvedHeroImageAcrossLenses(imageId: imageId) else {
                        actionStatus = "That frame no longer exists"
                        return
                    }
                    actionStatus = ""
                    let lensId = resolved.lens.lensId
                    Task {
                        _ = await library.retryLensHeroImage(lensId: lensId, imageId: imageId)
                        onAfterMutation()
                        if request?.imageId == imageId,
                           let refreshed = previewRequest(lensId: lensId, imageId: imageId) {
                            request = refreshed
                        }
                    }
                },
                actionStatus: actionStatus,
                onDelete: {
                    // Delete honesty: the modal closes only when the engine
                    // actually deleted; a refusal states itself.
                    let deleted = library.disableLensHeroImage(
                        lensId: resolvedHeroImageAcrossLenses(imageId: current.imageId)?.lens.lensId
                            ?? current.lensId,
                        imageId: current.imageId
                    )
                    if deleted {
                        actionStatus = ""
                        onAfterMutation()
                        request = nil
                        cutNavigation = nil
                    browseSelection = nil
                    } else {
                        actionStatus = library.aestheticStatus.trimmed.nilIfEmpty
                            ?? "Could not delete this render"
                    }
                },
                onNavigate: { direction in navigate(by: direction) },
                onEnterExcursion: cutNavigation == nil || onEnterExcursion == nil
                    ? nil
                    : {
                        let imageId = current.imageId
                        if let navigation = cutNavigation {
                            request = nil
                            cutNavigation = nil
                    browseSelection = nil
                            onEnterExcursion?(
                                ExcursionLaunchRequest(
                                    cutId: navigation.cutId,
                                    entryId: navigation.entryId,
                                    rootImageId: imageId
                                )
                            )
                        }
                    }
            ) {
                request = nil
                cutNavigation = nil
                    browseSelection = nil
            }
            .transition(.opacity)
        }
    }

    // MARK: Helpers (behavior-parallel with the SCENES tab's private ones)

    private func resolvedHeroImageAcrossLenses(
        imageId: String
    ) -> (lens: ProjectLens, heroImage: ProjectLensHeroImage)? {
        for lens in library.projectLenses.lenses {
            if let heroImage = lens.sortedHeroImages.first(where: { $0.imageId == imageId }) {
                return (lens, heroImage)
            }
        }
        return nil
    }

    private func launchFrameCreator(imageId: String, restyle: Bool) {
        guard let resolved = resolvedHeroImageAcrossLenses(imageId: imageId) else {
            actionStatus = "That frame no longer exists"
            return
        }
        actionStatus = ""
        // Strip-opened frames carry their cell so the finished take can land
        // beside it (captured before the teardown, like onReframe).
        let placement = cutNavigation
        request = nil
        cutNavigation = nil
                    browseSelection = nil
        onLaunchFrameCreator?(
            WorkbenchFrameCreatorLaunch(
                lensId: resolved.lens.lensId,
                context: restyle ? .restyle(of: resolved.heroImage) : .variation(of: resolved.heroImage),
                placeBeside: placement
            )
        )
    }

    /// Cut-opened frames step through the originating CUT's ready Frame
    /// entries; board-opened frames step through the lens board collapsed to
    /// one stop per version group (the open image represents its own group,
    /// else the group's active version).
    private func browseItems() -> [LensHeroPreviewBrowseItem] {
        if browseSelection != nil {
            return collectionItems.filter { FileManager.default.fileExists(atPath: $0.imagePath) }.map {
                LensHeroPreviewBrowseItem(id: $0.id, imageId: $0.imageId, imagePath: $0.imagePath, mediaId: $0.mediaId)
            }
        }
        if let navigation = cutNavigation,
           let cut = library.shotTimeline.shots.first(where: { $0.shotId == navigation.cutId }) {
            let frameLookup = library.projectWideFrameLookup
            return cut.entries.compactMap { entry in
                guard !entry.isClip,
                      let frame = frameLookup[entry.frameImageId],
                      frame.status == "ready",
                      !frame.imagePath.trimmed.isEmpty else {
                    return nil
                }
                return LensHeroPreviewBrowseItem(
                    id: entry.entryId,
                    imageId: frame.imageId,
                    imagePath: frame.imagePath
                )
            }
        }
        guard let request,
              let resolved = resolvedHeroImageAcrossLenses(imageId: request.imageId) else {
            return []
        }
        let currentImageId = request.imageId
        var representativeByGroup: [String: ProjectLensHeroImage] = [:]
        var groupOrder: [String] = []
        for image in resolved.lens.readyHeroImages {
            let key = image.renderVersion?.renderVersionGroupId.trimmed.nilIfEmpty ?? image.imageId
            if representativeByGroup[key] == nil { groupOrder.append(key) }
            let incumbent = representativeByGroup[key]
            let replaces: Bool
            if image.imageId == currentImageId {
                replaces = true
            } else if incumbent == nil {
                replaces = true
            } else if incumbent?.imageId == currentImageId {
                replaces = false
            } else {
                replaces = image.renderVersion?.isActive == true && incumbent?.renderVersion?.isActive != true
            }
            if replaces { representativeByGroup[key] = image }
        }
        return groupOrder.compactMap { key in
            representativeByGroup[key].map {
                LensHeroPreviewBrowseItem(id: $0.imageId, imageId: $0.imageId, imagePath: $0.imagePath)
            }
        }
    }

    private func currentBrowseId() -> String {
        browseSelection?.id ?? cutNavigation?.entryId ?? request?.imageId ?? ""
    }

    /// ←/→ stepping through `browseItems()`, wrapping in both directions.
    private func navigate(by direction: Int) {
        let items = browseItems()
        guard direction != 0, items.count > 1 else { return }
        let currentIndex = items.firstIndex(where: { $0.id == currentBrowseId() })
        let base = currentIndex ?? min(browseSelection?.index ?? 0, items.count - 1)
        let step = currentIndex == nil && direction > 0 ? 0 : direction
        let nextIndex = ((base + step) % items.count + items.count) % items.count
        openBrowseItem(items[nextIndex])
    }

    /// The lens is re-resolved by image id — the stale-lensId law — so cut
    /// browsing works across frames from different lenses, and a cut context
    /// keeps its cut with the destination entry.
    private func openBrowseItem(_ item: LensHeroPreviewBrowseItem) {
        var imageId = item.imageId
        if imageId.isEmpty, !item.mediaId.isEmpty,
           let lensId = request?.lensId ?? library.projectLenses.lenses.first?.lensId {
            guard let adopted = library.adoptMediaImageAsFrame(mediaId: item.mediaId, lensId: lensId) else {
                actionStatus = library.aestheticStatus
                return
            }
            imageId = adopted.imageId
        }
        guard let resolved = resolvedHeroImageAcrossLenses(imageId: imageId) else {
            actionStatus = "That frame no longer exists"
            return
        }
        actionStatus = ""
        request = previewRequest(lens: resolved.lens, heroImage: resolved.heroImage)
        if browseSelection != nil {
            browseSelection = FrameBrowseSelection(id: item.id, index: browseItems().firstIndex { $0.id == item.id } ?? 0)
        }
        if let navigation = cutNavigation {
            cutNavigation = HeroPreviewCutNavigation(cutId: navigation.cutId, entryId: item.id)
        }
        zoom = 1
    }

    private func previewRequest(lensId: String, imageId: String) -> LensHeroPreviewRequest? {
        Self.request(library: library, lensId: lensId, imageId: imageId)
    }

    private func previewRequest(lens: ProjectLens, heroImage: ProjectLensHeroImage) -> LensHeroPreviewRequest {
        Self.request(library: library, lens: lens, heroImage: heroImage)
    }

    /// Build an opening request by image id alone (stale-lensId-proof) — the
    /// entry point for surfaces that open frame detail from a pool tile.
    @MainActor
    static func openingRequest(library: LibraryEngine, imageId: String) -> LensHeroPreviewRequest? {
        for lens in library.projectLenses.lenses {
            if let heroImage = lens.sortedHeroImages.first(where: { $0.imageId == imageId }),
               !heroImage.imagePath.trimmed.isEmpty {
                return request(library: library, lens: lens, heroImage: heroImage)
            }
        }
        return nil
    }

    @MainActor
    static func request(library: LibraryEngine, lensId: String, imageId: String) -> LensHeroPreviewRequest? {
        guard let lens = library.projectLenses.lenses.first(where: { $0.lensId == lensId }),
              let image = lens.sortedHeroImages.first(where: { $0.imageId == imageId }),
              !image.imagePath.trimmed.isEmpty else {
            return nil
        }
        return request(library: library, lens: lens, heroImage: image)
    }

    @MainActor
    static func request(library: LibraryEngine, lens: ProjectLens, heroImage: ProjectLensHeroImage) -> LensHeroPreviewRequest {
        LensHeroPreviewRequest(
            lensId: lens.lensId,
            title: lens.body.title.trimmed.isEmpty ? "Frame" : lens.body.title.trimmed,
            imagePath: heroImage.imagePath,
            prompt: heroImage.prompt,
            sourcePrompt: heroImage.sourcePrompt,
            status: heroImage.status,
            imageId: heroImage.imageId,
            providerLabel: heroImage.label.trimmed.isEmpty ? heroImage.provider.capitalized : heroImage.label,
            model: heroImage.model,
            requestId: heroImage.requestId,
            traceId: heroImage.traceId,
            errorMessage: heroImage.errorMessage,
            isActiveVersion: heroImage.renderVersion?.isActive == true,
            versionItems: versionItems(lens: lens, heroImage: heroImage),
            reframeCast: library.lensReframeCastCandidates(for: lens),
            reframeSummary: heroImage.reframe?.modeLabel ?? "",
            reframeParentImageId: heroImage.reframe?.parentImageId ?? "",
            motionArtifact: heroImage.motionArtifact,
            narration: heroImage.narrationArtifact,
            promptEnrichmentSummary: heroImage.promptEnrichmentSummary,
            promptEnrichmentDisabled: heroImage.promptEnrichmentDisabled
        )
    }

    private static func versionItems(lens: ProjectLens, heroImage: ProjectLensHeroImage) -> [LensHeroPreviewVersionItem] {
        guard let groupId = heroImage.renderVersion?.renderVersionGroupId.trimmed.nilIfEmpty else { return [] }
        let versions = lens.sortedHeroImages
            .filter { image in
                image.renderVersion?.renderVersionGroupId.trimmed == groupId
                    && image.status.trimmed.lowercased() == "ready"
                    && !image.imagePath.trimmed.isEmpty
                    && !image.disabled
                    && FileManager.default.fileExists(atPath: image.imagePath)
            }
            .sorted { lhs, rhs in
                let lhsVersion = lhs.renderVersion?.versionNumber ?? 0
                let rhsVersion = rhs.renderVersion?.versionNumber ?? 0
                if lhsVersion == rhsVersion {
                    return lhs.imageId < rhs.imageId
                }
                return lhsVersion < rhsVersion
            }
        guard versions.count > 1 else { return [] }
        return versions.map { image in
            LensHeroPreviewVersionItem(
                imageId: image.imageId,
                imagePath: image.imagePath,
                prompt: image.prompt,
                status: image.status,
                providerLabel: image.label.trimmed.isEmpty ? image.provider.capitalized : image.label,
                model: image.model,
                requestId: image.requestId,
                traceId: image.traceId,
                errorMessage: image.errorMessage,
                isActiveVersion: image.renderVersion?.isActive == true,
                versionNumber: max(1, image.renderVersion?.versionNumber ?? 1)
            )
        }
    }
}
