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

    @ViewBuilder
    var body: some View {
        if let index = library.shotTimeline.shots.firstIndex(where: { $0.shotId == request.shotId }) {
            let plan = library.shotRenderPromptPlan(shotId: request.shotId)
            ShotRenderPlayerModal(
                shot: library.shotTimeline.shots[index],
                shotOrdinal: index + 1,
                planSegments: plan?.segments ?? [],
                skipped: plan?.skipped ?? [],
                skippedPlaceholders: plan?.skippedPlaceholders ?? [],
                isRenderBlocked: !library.activeShotRenderId.isEmpty
                    || !library.activeShotJoinRenderId.isEmpty
                    || !library.activeShotRestyleId.isEmpty,
                configuredRenderModels: Set(
                    ShotRenderModel.allCases.filter(library.canExecuteShotRenderModel)
                ),
                falPricing: library.falPricing,
                isFetchingVideoPricing: library.isFetchingFALPricing,
                openPanelInitially: request.openRerenderPanel,
                onActivateVersion: { versionId in
                    library.activateShotRenderVersion(shotId: request.shotId, versionId: versionId)
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
                    library.setShotSegmentPromptOverrides(shotId: shotId, overrides: overrides)
                    onDismiss()
                    Task {
                        await library.renderShot(shotId: shotId)
                    }
                },
                onRenderSegment: { overrides, segmentKey in
                    let shotId = request.shotId
                    library.setShotSegmentPromptOverrides(shotId: shotId, overrides: overrides)
                    onDismiss()
                    Task {
                        await library.renderShot(shotId: shotId, onlySegmentKeys: [segmentKey])
                    }
                },
                onAutosaveOverrides: { overrides in
                    library.setShotSegmentPromptOverrides(shotId: request.shotId, overrides: overrides)
                },
                onSaveDirectionPlans: { plans in
                    library.setShotSegmentDirectionPlans(shotId: request.shotId, plans: plans)
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
                    library.setShotSeamStyle(
                        shotId: request.shotId,
                        entryId: entryId,
                        style: style,
                        intent: intent
                    )
                },
                onSetEntrySkipped: { entryId, skipped in
                    library.setShotEntrySkipped(shotId: request.shotId, entryId: entryId, skipped: skipped)
                },
                onSetCutList: { cutList in
                    library.setShotCutList(shotId: request.shotId, cutList: cutList)
                },
                onSetCutReversed: { reversed in
                    library.setShotCutReversed(shotId: request.shotId, reversed: reversed)
                },
                onRetryReverseProxies: {
                    // Opening the shot is a deliberate act, so it is the right
                    // moment to try a failed bake again — and the only reason a
                    // reversed CUT would otherwise sit playing forward forever.
                    await library.ensureReverseProxies(shotId: request.shotId)
                },
                reverseBakeProgress: library.reverseBakeProgress[request.shotId],
                hasFALCredential: library.videoProviderCredentialStatuses
                    .first(where: { $0.provider == .fal })?.isConfigured == true,
                hasDecartCredential: library.videoProviderCredentialStatuses
                    .first(where: { $0.provider == .decart })?.isConfigured == true,
                activeShotJoinRenderId: library.activeShotJoinRenderId,
                onSetJoinRepair: { cutId, repair in
                    library.setShotRazorJoinRepair(
                        shotId: request.shotId,
                        cutId: cutId,
                        repair: repair
                    )
                },
                onRestoreRazorCut: { cutId in
                    library.restoreShotRazorCut(shotId: request.shotId, cutId: cutId)
                },
                onRestorePictureState: { snapshot in
                    library.restoreShotPictureState(shotId: request.shotId, snapshot: snapshot)
                },
                onRenderJoinBridge: { cutId, provider, duration, prompt in
                    Task {
                        await library.renderShotRazorJoinBridge(
                            shotId: request.shotId,
                            cutId: cutId,
                            provider: provider,
                            durationSeconds: duration,
                            prompt: prompt
                        )
                    }
                },
                onPrepareJoinFrames: { cutId in
                    await library.prepareShotRazorJoinFrames(
                        shotId: request.shotId,
                        cutId: cutId
                    )
                },
                onCommitMicrophoneTake: { recording, startSeconds in
                    await library.commitShotMicrophoneTake(
                        shotId: request.shotId,
                        recording: recording,
                        startSeconds: startSeconds
                    )
                },
                onDeleteMicrophoneTake: { takeId in
                    library.deleteShotMicrophoneTake(shotId: request.shotId, takeId: takeId)
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
                    library.setShotAmbientBed(shotId: request.shotId, bedId: bedId)
                },
                onOpenNarration: {
                    onFocusNarration(request.shotId)
                },
                audioRegionActions: ShotAudioRegionActions(
                    add: { laneId, asset, startSeconds in
                        library.addShotAudioRegion(
                            shotId: request.shotId,
                            laneId: laneId,
                            asset: asset,
                            startSeconds: startSeconds
                        )
                    },
                    addTrack: { kind, asset, startSeconds in
                        library.addShotAudioTrack(
                            shotId: request.shotId,
                            kind: kind,
                            asset: asset,
                            startSeconds: startSeconds
                        )
                    },
                    move: { regionId, startSeconds in
                        library.moveShotAudioRegion(
                            shotId: request.shotId,
                            regionId: regionId,
                            startSeconds: startSeconds
                        )
                    },
                    setGeometry: { regionId, start, sourceStart, duration in
                        library.setShotAudioRegionGeometry(
                            shotId: request.shotId,
                            regionId: regionId,
                            startSeconds: start,
                            sourceStartSeconds: sourceStart,
                            durationSeconds: duration
                        )
                    },
                    split: { regionId, atSeconds in
                        library.splitShotAudioRegion(
                            shotId: request.shotId,
                            regionId: regionId,
                            atSeconds: atSeconds
                        )
                    },
                    setLoops: { regionId, loops in
                        library.setShotAudioRegionLoops(
                            shotId: request.shotId,
                            regionId: regionId,
                            loops: loops
                        )
                    },
                    replaceMedia: { regionId, asset in
                        library.replaceShotAudioRegionMedia(
                            shotId: request.shotId,
                            regionId: regionId,
                            asset: asset
                        )
                    },
                    update: { region in
                        library.setShotAudioRegion(shotId: request.shotId, region: region)
                    },
                    makeAudible: { regionId in
                        library.makeShotAudioRegionAudible(
                            shotId: request.shotId,
                            regionId: regionId
                        )
                    },
                    delete: { regionId in
                        library.deleteShotAudioRegion(shotId: request.shotId, regionId: regionId)
                    },
                    restore: { region in
                        library.restoreShotAudioRegion(shotId: request.shotId, region: region)
                    },
                    restoreState: { snapshot in
                        library.restoreShotAudioState(
                            shotId: request.shotId,
                            snapshot: snapshot
                        )
                    },
                    currentRegion: { regionId in
                        library.shotTimeline.shots
                            .first { $0.shotId == request.shotId }?
                            .audioRegions.first { $0.regionId == regionId }
                    },
                    importAudioFiles: { urls in
                        await library.importAudioMediaFiles(urls)
                    },
                    backfillDurations: {
                        await library.backfillShotAudioRegionSourceDurations(shotId: request.shotId)
                    },
                    setSourceSegment: { segmentKey, gain, isMuted in
                        library.setShotSourceSegmentAudio(
                            shotId: request.shotId,
                            segmentKey: segmentKey,
                            gain: gain,
                            isMuted: isMuted
                        )
                    },
                    detachSourceSegment: { segmentKey in
                        library.detachShotSourceSegmentAudio(
                            shotId: request.shotId,
                            segmentKey: segmentKey
                        )
                    },
                    restoreSourceDetach: { snapshot in
                        library.restoreShotSourceDetach(shotId: request.shotId, snapshot: snapshot)
                    },
                    currentSourceState: {
                        let shot = library.shotTimeline.shots.first { $0.shotId == request.shotId }
                        return ShotSourceDetachSnapshot(
                            sourceSegmentAudio: shot?.sourceSegmentAudio ?? [],
                            audioRegions: shot?.audioRegions ?? []
                        )
                    },
                    addLane: { kind in
                        library.addShotAudioLane(shotId: request.shotId, kind: kind)
                    },
                    removeLane: { laneId in
                        library.removeShotAudioLane(shotId: request.shotId, laneId: laneId)
                    },
                    moveToLane: { regionId, laneId in
                        library.moveShotAudioRegionToLane(
                            shotId: request.shotId,
                            regionId: regionId,
                            laneId: laneId
                        )
                    },
                    setLaneEnabled: { laneId, enabled in
                        library.setShotAudioLaneEnabled(
                            shotId: request.shotId,
                            laneId: laneId,
                            enabled: enabled
                        )
                    },
                    setLaneVolume: { laneId, volume in
                        library.setShotAudioLaneVolume(
                            shotId: request.shotId,
                            laneId: laneId,
                            volume: volume
                        )
                    },
                    activateTake: { takeId in
                        library.activateShotMicrophoneTake(
                            shotId: request.shotId,
                            takeId: takeId
                        )
                    },
                    addBatch: { laneId, assets, startSeconds in
                        library.addShotAudioRegionBatch(
                            shotId: request.shotId,
                            laneId: laneId,
                            assets: assets,
                            startSeconds: startSeconds
                        )
                    },
                    deleteMany: { regionIds in
                        library.deleteShotAudioRegions(
                            shotId: request.shotId,
                            regionIds: regionIds
                        )
                    },
                    paste: { payload, preferredLaneId, startSeconds in
                        library.pasteShotAudioRegion(
                            shotId: request.shotId,
                            payload: payload,
                            preferredLaneId: preferredLaneId,
                            startSeconds: startSeconds
                        )
                    },
                    duplicate: { regionId in
                        library.duplicateShotAudioRegion(
                            shotId: request.shotId,
                            regionId: regionId
                        )
                    }
                ),
                restylePromptSeed: library.shotLookPromptSeed(),
                activeShotRestyleId: library.activeShotRestyleId,
                onActivateLook: { versionId in
                    library.activateShotLookVersion(shotId: request.shotId, versionId: versionId)
                },
                onStartRestyle: { prompt, enhancePrompt, seed, style, provider in
                    library.startShotLookRestyle(
                        shotId: request.shotId,
                        prompt: prompt,
                        enhancePrompt: enhancePrompt,
                        seed: seed,
                        style: style,
                        provider: provider
                    )
                },
                onCancelRestyle: {
                    library.cancelShotLookRestyle(shotId: request.shotId)
                },
                onRetryRestyle: { versionId in
                    library.retryShotLook(shotId: request.shotId, versionId: versionId)
                },
                onContinueLookAsNewShot: {
                    let newShotId = await library.continueActiveShotLookAsNewShot(shotId: request.shotId)
                    if let newShotId {
                        onReopen(ShotVideoRequest(shotId: newShotId))
                    }
                    return newShotId
                },
                onSendToFootage: {
                    await library.sendShotOutputToFootage(shotId: request.shotId)
                },
                onExportForYouTube: {
                    await library.exportShotOutputForYouTube(shotId: request.shotId)
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
                    library.pasteShotPictureSegments(
                        shotId: request.shotId,
                        insertions: insertions,
                        status: status
                    )
                },
                onRemovePictureInsertions: { insertionIds in
                    library.removeShotPictureInsertions(
                        shotId: request.shotId,
                        insertionIds: insertionIds
                    )
                },
                onSetPictureInsertionRate: { insertionIds, rate in
                    library.setShotPictureInsertionRate(
                        shotId: request.shotId,
                        insertionIds: insertionIds,
                        rate: rate
                    )
                },
                onSetPictureInsertionMuted: { insertionIds, muted in
                    library.setShotPictureInsertionMuted(
                        shotId: request.shotId,
                        insertionIds: insertionIds,
                        muted: muted
                    )
                },
                onRecopyPictureInsertion: { insertionId in
                    library.recopyShotPictureInsertion(
                        shotId: request.shotId,
                        insertionId: insertionId
                    )
                },
                onPasteSegmentCards: { cards, afterEntryId in
                    library.pasteShotSegmentCards(
                        shotId: request.shotId,
                        cards: cards,
                        afterEntryId: afterEntryId
                    )
                },
                onSetSectionRate: { materialStart, materialEnd, rate in
                    library.setShotSectionRate(
                        shotId: request.shotId,
                        materialStart: materialStart,
                        materialEnd: materialEnd,
                        rate: rate
                    )
                },
                onClose: {
                    onDismiss()
                }
            )
            .onAppear {
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
            isRenderBlocked: library.lensHeroTakeStartBlockReason != nil,
            renderBlockerHelp: library.lensHeroTakeStartBlockReason,
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
                onDismiss()
                onSubmitted()
                // One Task per request: each start AWAITS its render, so the
                // batch must fan out for the take lane to hold them at once.
                for (index, request) in requests.enumerated() {
                    Task {
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
            },
            onCancel: onDismiss,
            mentionEntries: library.frameCreatorMentionEntries(for: lens),
            mentionReferenceItems: library.items.filter { $0.kind == .image },
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
            referenceLibraryItems: library.items.filter { $0.kind == .image },
            initialReferenceItems: launch.referenceMediaIds.compactMap { mediaId in
                library.items.first { $0.mediaId == mediaId && $0.kind == .image }
            },
            generatedFrameCandidates: generatedFrameReferenceCandidates(lenses: library.projectLenses.lenses, items: library.items),
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
                reframeSubmissionBlockReason: library.lensHeroReframeBlockReason,
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
        cutNavigation?.entryId ?? request?.imageId ?? ""
    }

    /// ←/→ stepping through `browseItems()`, wrapping in both directions.
    private func navigate(by direction: Int) {
        let items = browseItems()
        guard direction != 0, items.count > 1,
              let currentIndex = items.firstIndex(where: { $0.id == currentBrowseId() }) else {
            return
        }
        let nextIndex = ((currentIndex + direction) % items.count + items.count) % items.count
        openBrowseItem(items[nextIndex])
    }

    /// The lens is re-resolved by image id — the stale-lensId law — so cut
    /// browsing works across frames from different lenses, and a cut context
    /// keeps its cut with the destination entry.
    private func openBrowseItem(_ item: LensHeroPreviewBrowseItem) {
        guard let resolved = resolvedHeroImageAcrossLenses(imageId: item.imageId) else {
            actionStatus = "That frame no longer exists"
            return
        }
        actionStatus = ""
        request = previewRequest(lens: resolved.lens, heroImage: resolved.heroImage)
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
