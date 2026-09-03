import AppKit
import SwiftUI

/// CHARACTERS: the casting desk. A rail of characters; the selected character's
/// masthead, cream plate (the sheet, or the casting card while uncast), source
/// images with the studio, identity, and sheet prompt in one scrolling column with
/// the action bar pinned beneath; the refinement conversation on paper. Single
/// project, dark room, one filled element per column.
struct CharactersWorkspaceView: View {
    @ObservedObject var library: LibraryEngine
    @ObservedObject var session: CharactersSession
    var onOpenAppSettings: () -> Void = {}
    var onOpenStory: () -> Void = {}
    var onOpenScenes: () -> Void = {}

    @State private var imagePreview: StyleImagePreviewRequest?
    @State private var alert: CharactersAlert?
    @State private var drafts = CharacterEditDrafts()
    @State private var refiningStudioIds: Set<String> = []
    @State private var isMediaPickerPresented = false
    @FocusState private var focus: CharacterEditField?

    /// The selected character's in-progress edits, owned here so a render, a
    /// character switch, or a tab switch commits them before anything reads the
    /// roster (plain buttons never blur a text editor).
    private struct CharacterEditDrafts: Equatable {
        var characterId = ""
        var name = ""
        var appearance = ""
        var prompt = ""
        var isPromptEditRequested = false
    }

    private enum CharactersAlert: Identifiable {
        case delete(ProjectCharacter)
        case resetPrompt(ProjectCharacter)
        case redraft(ProjectCharacter)

        var id: String {
            switch self {
            case .delete(let character): return "delete:\(character.characterId)"
            case .resetPrompt(let character): return "reset:\(character.characterId)"
            case .redraft(let character): return "redraft:\(character.characterId)"
            }
        }
    }

    private var characters: [ProjectCharacter] { library.projectCharacters.characters }

    private var selectedCharacter: ProjectCharacter? {
        characters.first { $0.characterId == session.selectedCharacterId }
    }

    private var stacks: [RenderStack] { RenderStackRegistry.shared.stacks() }

    private var imageCandidates: [MediaItemRecord] {
        library.items.filter { $0.kind == .image }
    }

    private var selectedName: String { selectedCharacter?.name ?? "" }
    private var selectedAppearance: String { selectedCharacter?.descriptionPrompt ?? "" }
    private var selectedPromptOverride: String { selectedCharacter?.sheetPromptOverride ?? "" }
    private var characterIds: [String] { characters.map(\.characterId) }
    private var currentProjectId: String { library.currentProject?.projectId ?? "" }

    var body: some View {
        hooked(root)
    }

    private var root: some View {
        GeometryReader { geometry in
            columns(size: geometry.size)
        }
        .background(CanonColor.room)
        .safeAreaInset(edge: .bottom, spacing: 0) { statusLine }
        .sheet(item: $imagePreview) { request in
            StyleImagePreviewModal(request: request)
        }
        .sheet(isPresented: $isMediaPickerPresented) { mediaPicker }
        .alert(item: $alert, content: makeAlert)
    }

    /// ADD FROM MEDIA: the project's own images (Story Inputs, library images, and
    /// generated frames) as sources, in the order they are picked.
    @ViewBuilder
    private var mediaPicker: some View {
        if let character = selectedCharacter {
            let characterId = character.characterId
            let current = Set(character.referenceMediaIds)
            MediaPickerSheet(
                title: "Add source images for \(character.name)",
                subtitle: "Chosen images become source images the sheet is rendered from; the first ones lead.",
                items: library.items.filter { $0.kind == .image && !$0.isCharacterSheet && !current.contains($0.mediaId) },
                observationsById: library.mediaObservationsById,
                storyInputMediaIds: Set(library.enabledContentItems.map(\.mediaId)),
                generatedFrameCandidates: generatedFrameReferenceCandidates(lenses: library.projectLenses.lenses, items: library.items),
                confirmLabel: "Add as sources",
                onConfirm: { picks in
                    isMediaPickerPresented = false
                    applyMediaPicks(picks, to: characterId)
                },
                onCancel: { isMediaPickerPresented = false }
            )
            .frame(width: 720, height: 560)
            .environment(\.colorScheme, .light)
        }
    }

    private func applyMediaPicks(_ picks: [MediaPickerPick], to characterId: String) {
        Task {
            var mediaIds: [String] = []
            for pick in picks {
                switch pick {
                case .media(let item):
                    mediaIds.append(item.mediaId)
                case .generatedFrame(let candidate):
                    if let adopted = candidate.adoptedMediaId {
                        mediaIds.append(adopted)
                    } else if let adopted = await library.archiveHeroFrameAsReference(candidate.image) {
                        mediaIds.append(adopted.mediaId)
                    }
                }
            }
            appendSources(characterId, mediaIds)
        }
    }

    @ViewBuilder
    private func columns(size: CGSize) -> some View {
        HStack(spacing: 0) {
            rail
                .frame(width: 264)
            divider
            if let character = selectedCharacter {
                centerColumn(for: character, workspaceHeight: size.height)
                divider
                chatPane(for: character)
                    .frame(width: max(340, size.width * 0.30))
            } else {
                emptyStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Lifecycle and draft synchronization, kept off `body` for the type-checker.
    private func hooked<Content: View>(_ content: Content) -> some View {
        content
            .onAppear {
                // Live FAL rates for the consequence line; cached ~a day, never blocking.
                Task { await library.refreshFALPricingIfStale() }
                reconcile()
                loadDrafts()
            }
            .onDisappear { commitPendingEdits() }
            .onChange(of: currentProjectId) { _, _ in reconcile() }
            .onChange(of: characterIds) { _, ids in session.reconcile(characterIds: ids) }
            .onChange(of: session.selectedCharacterId) { _, _ in
                commitPendingEdits()
                loadDrafts()
            }
            .onChange(of: focus) { old, new in
                if let old, old != new { commitField(old) }
            }
            .onChange(of: selectedName) { _, value in
                if focus != .name { drafts.name = value }
            }
            .onChange(of: selectedAppearance) { _, value in
                if focus != .appearance { drafts.appearance = value }
            }
            .onChange(of: selectedPromptOverride) { _, value in
                if focus != .prompt, !drafts.isPromptEditRequested { drafts.prompt = value }
            }
    }

    private var divider: some View {
        Rectangle()
            .fill(CanonColor.hairlineDark)
            .frame(width: 1)
    }

    // MARK: Rail

    private var rail: some View {
        CharactersRailView(
            characters: characters,
            selectedCharacterId: session.selectedCharacterId,
            sheetItem: { library.activeCharacterSheetItem(for: $0) },
            sheetOrdinal: sheetOrdinal(for:),
            candidates: imageCandidates,
            onSelect: { session.select($0) },
            onCreate: createCharacter,
            onAppendSources: appendSources,
            onDelete: { alert = .delete($0) }
        )
    }

    // MARK: Center column

    private func centerColumn(for character: ProjectCharacter, workspaceHeight: CGFloat) -> some View {
        let stack = library.resolvedCharacterSheetStack(for: character)
        let inputs = castingInputs(for: character, stack: stack)
        let copy = characterCastingCopy(inputs)
        let stage = characterCastingStage(inputs)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                masthead(for: character, copy: copy)
                plate(for: character, copy: copy, stage: stage, workspaceHeight: workspaceHeight)
                sources(for: character, stack: stack)
                if session.studio(for: character.characterId).isOpen {
                    studio(for: character, stack: stack)
                }
                identity(for: character)
                promptSection(for: character, stack: stack)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // While uncast the casting card owns the action; the bar takes over once
            // a sheet exists and the plate shows the image.
            if library.activeCharacterSheetItem(for: character.characterId) != nil {
                actionBar(for: character, stack: stack, inputs: inputs, copy: copy, stage: stage)
            }
        }
    }

    private func castingInputs(for character: ProjectCharacter, stack: RenderStack?) -> CharacterCastingInputs {
        let characterId = character.characterId
        let picks = stack.map { library.characterSheetRenderPicks(for: character, stack: $0) } ?? []
        let promptState = stack.map { library.characterSheetPromptState(for: character, stack: $0) }
        let note = library.characterRenderNotes[characterId]
        let identity = library.goalCastMember(forCharacterId: characterId, name: character.name)?.activeIdentity
        var inputs = CharacterCastingInputs(name: character.name)
        inputs.sourceCount = character.referenceMediaIds.count
        inputs.hasAppearance = !character.descriptionPrompt.trimmed.isEmpty
        inputs.hasStoryIdentity = identity.map {
            !$0.essence.trimmed.isEmpty || !$0.publicFunction.trimmed.isEmpty || !$0.desire.trimmed.isEmpty
        } ?? false
        inputs.activeOrdinal = sheetOrdinal(for: characterId)
        inputs.promptIsCurrent = promptState?.isCurrent ?? true
        inputs.isRenderingSheet = library.isGeneratingCharacterSheet && library.activeCharacterSheetCharacterId == characterId
        inputs.isDrafting = library.draftingCharacterIds.contains(characterId)
        if case .draft = library.characterIdentityDraftDecision(for: character) { inputs.draftsFirst = true }
        inputs.lastFailure = (note?.lane == .sheet || note?.lane == .draft) ? (note?.message ?? "") : ""
        inputs.lastFailureIsDraft = note?.lane == .draft
        inputs.stackLabel = stack?.label ?? ""
        inputs.priceNote = stack.map { library.priceNote(for: $0, attachesReferences: !picks.isEmpty) } ?? ""
        inputs.stackIsTextOnly = stack.map { !$0.reframeCapable } ?? false
        inputs.attachesSheet = picks.contains(where: \.isSheet)
        inputs.attachedSourceCount = picks.filter { !$0.isSheet }.count
        inputs.blocker = renderBlocker(for: stack, characterId: characterId)
        inputs.promptIsHandEdited = character.hasSheetPromptOverride
        return inputs
    }

    private func renderBlocker(for stack: RenderStack?, characterId: String) -> CharacterRenderBlocker? {
        guard let stack else { return .noStack }
        if let blocker = library.renderStackCredentialBlocker(for: stack) { return .credential(blocker) }
        if library.isGenerationPaused { return .paused }
        if library.isGeneratingCharacterSheet, library.activeCharacterSheetCharacterId != characterId { return .busy }
        if library.isGeneratingCharacterRender {
            return library.activeCharacterRenderCharacterId == characterId ? .studyRunning : .busy
        }
        return nil
    }

    private func sheetOrdinal(for characterId: String) -> Int? {
        guard let active = library.activeCharacterSheetItem(for: characterId) else { return nil }
        let versions = library.characterSheetItems(characterId: characterId)
        guard let index = versions.firstIndex(where: { $0.mediaId == active.mediaId }) else { return nil }
        return versions.count - index
    }

    private func masthead(for character: ProjectCharacter, copy: CharacterCastingCopy) -> some View {
        CharacterMastheadView(
            publicFunction: library.goalCastMember(forCharacterId: character.characterId, name: character.name)?.activeIdentity.publicFunction ?? "",
            status: copy.mastheadStatus,
            statusTone: copy.mastheadTone,
            nameDraft: $drafts.name,
            focus: $focus,
            onCommitName: { commitField(.name) }
        )
    }

    private func plate(for character: ProjectCharacter, copy: CharacterCastingCopy, stage: CharacterCastingStage, workspaceHeight: CGFloat) -> some View {
        let stack = library.resolvedCharacterSheetStack(for: character)
        return CharacterSheetPlateView(
            name: character.name,
            activeSheet: library.activeCharacterSheetItem(for: character.characterId),
            sheetVersions: library.characterSheetItems(characterId: character.characterId),
            plateHeight: sheetPlateHeight(workspaceHeight: workspaceHeight),
            stage: stage,
            onUseVersion: { _ = library.setActiveCharacterSheet(characterId: character.characterId, mediaId: $0) },
            onEnlarge: { item in
                imagePreview = StyleImagePreviewRequest(
                    url: URL(fileURLWithPath: item.path).absoluteString,
                    label: "\(character.name) — character sheet",
                    detail: item.filename
                )
            }
        ) {
            castingCard(for: character, stack: stack, copy: copy, stage: stage)
        }
    }

    private func castingCard(for character: ProjectCharacter, stack: RenderStack?, copy: CharacterCastingCopy, stage: CharacterCastingStage) -> some View {
        let leads = character.referenceMediaIds.prefix(2).compactMap { id in imageCandidates.first { $0.mediaId == id } }
        let blocker = renderBlocker(for: stack, characterId: character.characterId)
        let showsAppSettings: Bool
        switch blocker {
        case .noStack, .credential: showsAppSettings = true
        default: showsAppSettings = false
        }
        return CharacterCastingCardView(
            copy: copy,
            stage: stage,
            leadThumbnails: Array(leads),
            stacks: stacks,
            selectedStack: stack,
            credentialBlocker: { library.renderStackCredentialBlocker(for: $0) },
            showsAppSettings: showsAppSettings,
            onSelectStack: { _ = library.setCharacterSheetStack(characterId: character.characterId, stackId: $0) },
            onRender: { renderSheet(for: character, stack: stack) },
            onOpenAppSettings: onOpenAppSettings,
            isSuggestingFrames: library.suggestingCharacterIds.contains(character.characterId),
            suggestionNote: library.characterRenderNotes[character.characterId],
            onOpenScenes: onOpenScenes
        )
    }

    private func sources(for character: ProjectCharacter, stack: RenderStack?) -> some View {
        let picks = stack.map { library.characterSheetRenderPicks(for: character, stack: $0) } ?? []
        let characterId = character.characterId
        return CharacterSourceImagesView(
            name: character.name,
            referenceMediaIds: character.referenceMediaIds,
            referenceLabels: character.referenceLabels,
            candidates: imageCandidates,
            attachedMediaIds: picks.filter { !$0.isSheet }.map(\.item.mediaId),
            stackLabel: stack?.label ?? "",
            stackIsTextOnly: stack.map { !$0.reframeCapable } ?? false,
            sheetOrdinalLabel: sheetOrdinal(for: characterId).map(characterSheetOrdinalLabel),
            generatingShotLabel: isGeneratingStudy(for: characterId) ? session.studio(for: characterId).shot.label : nil,
            suggestions: library.suggestedSourceImages(for: characterId),
            analysisState: { library.characterSourceAnalysisState(for: $0) },
            onPlace: { mediaId, index in placeSource(character, mediaId: mediaId, at: index) },
            onAppend: { appendSources(characterId, $0) },
            onRemove: { removeSource(character, mediaId: $0) },
            onLabel: { mediaId, label in
                _ = library.setCharacterReferenceLabel(characterId: characterId, mediaId: mediaId, label: label)
            },
            onUpload: {
                Task {
                    let items = await library.chooseCharacterSourceImages()
                    appendSources(characterId, items.map(\.mediaId))
                }
            },
            onPickFromMedia: { isMediaPickerPresented = true },
            onEnlarge: { item in
                imagePreview = StyleImagePreviewRequest(
                    url: URL(fileURLWithPath: item.path).absoluteString,
                    label: item.filename
                )
            },
            onMoreLikeThis: { openStudio(for: character, referenceId: $0) },
            onOpenStudio: { openStudio(for: character) }
        )
    }

    private func identity(for character: ProjectCharacter) -> some View {
        let characterId = character.characterId
        return CharacterIdentityPanel(
            character: character,
            castMember: library.goalCastMember(forCharacterId: characterId, name: character.name),
            appearanceDraft: $drafts.appearance,
            draftDecision: library.characterIdentityDraftDecision(for: character),
            isDrafting: library.draftingCharacterIds.contains(characterId),
            focus: $focus,
            onCommitAppearance: { commitField(.appearance) },
            onSetProps: { _ = library.setCharacterSignatureProps(characterId: characterId, $0) },
            onSetDirectives: { _ = library.setCharacterSheetDirectives(characterId: characterId, $0) },
            onOpenStory: onOpenStory,
            onDraft: {
                commitPendingEdits()
                Task { _ = await library.draftCharacterIdentity(characterId: characterId) }
            },
            onRedraft: { alert = .redraft(character) }
        )
    }

    private func promptSection(for character: ProjectCharacter, stack: RenderStack?) -> some View {
        let state = stack.map { library.characterSheetPromptState(for: character, stack: $0) }
        return CharacterPromptSection(
            composedPrompt: state?.composed ?? "",
            handEditedPrompt: state?.handEdited,
            hasDrift: state?.hasDrift ?? false,
            isEditing: drafts.isPromptEditRequested || state?.handEdited != nil,
            isExpanded: $session.isPromptExpanded,
            promptDraft: $drafts.prompt,
            focus: $focus,
            onBeginEdit: {
                drafts.prompt = state?.effective ?? ""
                drafts.isPromptEditRequested = true
                focus = .prompt
            },
            onCommit: {
                commitField(.prompt)
                focus = nil
            },
            onRequestReset: { alert = .resetPrompt(character) },
            onCopy: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(state?.effective ?? "", forType: .string)
            }
        )
    }

    private func actionBar(
        for character: ProjectCharacter,
        stack: RenderStack?,
        inputs: CharacterCastingInputs,
        copy: CharacterCastingCopy,
        stage: CharacterCastingStage
    ) -> some View {
        let roster = characters.map {
            (id: $0.characterId, name: $0.name, isCast: library.activeCharacterSheetItem(for: $0.characterId) != nil)
        }
        let showsAppSettings: Bool
        switch inputs.blocker {
        case .noStack, .credential: showsAppSettings = true
        default: showsAppSettings = false
        }
        return CharacterActionBar(
            copy: copy,
            stage: stage,
            stacks: stacks,
            selectedStack: stack,
            credentialBlocker: { library.renderStackCredentialBlocker(for: $0) },
            nextStep: characterNextStep(characters: roster, selectedId: character.characterId),
            showsAppSettings: showsAppSettings,
            onSelectStack: { _ = library.setCharacterSheetStack(characterId: character.characterId, stackId: $0) },
            onRender: { renderSheet(for: character, stack: stack) },
            onNextStep: { step in
                switch step {
                case .nextUncast(let characterId, _): session.select(characterId)
                case .continueToScenes: onOpenScenes()
                }
            },
            onOpenAppSettings: onOpenAppSettings
        )
    }

    private func renderSheet(for character: ProjectCharacter, stack: RenderStack?) {
        guard let stack else { return }
        commitPendingEdits()
        Task { _ = await library.startCharacterSheetRender(characterId: character.characterId, stack: stack) }
    }

    // MARK: Studio

    private func isGeneratingStudy(for characterId: String) -> Bool {
        library.isGeneratingCharacterRender && library.activeCharacterRenderCharacterId == characterId
    }

    private func studio(for character: ProjectCharacter, stack: RenderStack?) -> some View {
        let characterId = character.characterId
        let sources = character.referenceMediaIds.enumerated().compactMap { index, mediaId -> CharacterStudioSourceChip? in
            guard let item = imageCandidates.first(where: { $0.mediaId == mediaId }) else { return nil }
            return CharacterStudioSourceChip(mediaId: mediaId, item: item, ordinal: index + 1, label: character.referenceLabels[mediaId] ?? "")
        }
        let note = library.characterRenderNotes[characterId]
        return CharacterStudioPanel(
            draft: Binding(
                get: { session.studio(for: characterId) },
                set: { session.setStudio($0, for: characterId) }
            ),
            name: character.name,
            sources: sources,
            activeSheet: library.activeCharacterSheetItem(for: characterId),
            sheetOrdinalLabel: sheetOrdinal(for: characterId).map(characterSheetOrdinalLabel) ?? "",
            stackLabel: stack?.label ?? "",
            priceNote: stack.map {
                library.priceNote(for: $0, attachesReferences: !sources.isEmpty || library.activeCharacterSheetItem(for: characterId) != nil)
            } ?? "",
            stackCapacity: stack?.frameReferenceCapacity.planningCap ?? 0,
            isGenerating: isGeneratingStudy(for: characterId),
            isRefining: refiningStudioIds.contains(characterId),
            blockedReason: studioBlockedReason(for: stack, characterId: characterId),
            failure: note?.lane == .study ? (note?.message ?? "") : "",
            nextSourceOrdinal: character.referenceMediaIds.count + 1,
            draftsFirst: {
                if case .draft = library.characterIdentityDraftDecision(for: character) { return true }
                return false
            }(),
            focus: $focus,
            onChipsChanged: { reseedStudio(for: character, force: false) },
            onReset: { reseedStudio(for: character, force: true) },
            onRefine: { refineStudio(for: character) },
            onGenerate: { generateStudy(for: character, stack: stack) },
            onClose: {
                var draft = session.studio(for: characterId)
                draft.isOpen = false
                session.setStudio(draft, for: characterId)
            }
        )
    }

    private func studioBlockedReason(for stack: RenderStack?, characterId: String) -> String {
        guard let stack else { return "Add an API key in App Settings to render." }
        if library.draftingCharacterIds.contains(characterId) { return "Casting from the story…" }
        if let blocker = library.renderStackCredentialBlocker(for: stack) { return blocker }
        if library.isGenerationPaused { return "Generation is paused. Resume it from Activity to continue." }
        if library.isGeneratingCharacterSheet { return "A sheet is rendering. Generate when it lands." }
        if library.isGeneratingCharacterRender, library.activeCharacterRenderCharacterId != characterId {
            return "Another character's study is generating."
        }
        return ""
    }

    /// Opens the studio seeded for the situation: a chosen source (More like this…)
    /// becomes the reference; otherwise the sheet if one exists, else slot 1, else text.
    private func openStudio(for character: ProjectCharacter, referenceId: String? = nil) {
        let characterId = character.characterId
        var draft = session.studio(for: characterId)
        draft.isOpen = true
        var reseed = !draft.hasSeeded
        if let referenceId {
            draft.referenceIds = [referenceId]
            draft.look = .asDescribed
            draft.shot = .threeQuarter
            reseed = true
        } else if !draft.hasSeeded {
            draft.referenceIds = library.activeCharacterSheetItem(for: characterId).map { [$0.mediaId] }
                ?? Array(character.referenceMediaIds.prefix(1))
            draft.shot = draft.referenceIds.isEmpty ? .portrait : .threeQuarter
        }
        session.setStudio(draft, for: characterId)
        reseedStudio(for: character, force: reseed)
    }

    /// Chips re-seed the prompt until the operator edits it; RESET re-seeds on demand.
    private func reseedStudio(for character: ProjectCharacter, force: Bool) {
        let characterId = character.characterId
        var draft = session.studio(for: characterId)
        if draft.isEdited, !force { return }
        let seeded = CharacterStudyPrompt.compose(
            name: character.name,
            description: character.descriptionPrompt,
            signatureProps: character.signatureProps,
            shot: draft.shot,
            look: draft.look,
            referenceCount: draft.referenceIds.count
        )
        draft.prompt = seeded
        draft.seededPrompt = seeded
        draft.hasSeeded = true
        session.setStudio(draft, for: characterId)
    }

    private func refineStudio(for character: ProjectCharacter) {
        let characterId = character.characterId
        var draft = session.studio(for: characterId)
        let directive = draft.refineInput.trimmed
        let current = draft.prompt
        guard !directive.isEmpty, !current.trimmed.isEmpty, !refiningStudioIds.contains(characterId) else { return }
        draft.refineInput = ""
        session.setStudio(draft, for: characterId)
        refiningStudioIds.insert(characterId)
        Task {
            let result = await library.transformFormPrompt(prompt: current, directive: directive, priorDirectives: [])
            refiningStudioIds.remove(characterId)
            var latest = session.studio(for: characterId)
            if let result {
                latest.prompt = result.prompt
            } else {
                latest.refineInput = directive
            }
            session.setStudio(latest, for: characterId)
        }
    }

    private func generateStudy(for character: ProjectCharacter, stack: RenderStack?) {
        guard let stack else { return }
        commitPendingEdits()
        let characterId = character.characterId
        Task {
            // A blank identity is drafted first; the seeded study prompt then
            // carries the drafted appearance (a hand-edited prompt is kept).
            if case .draft = library.characterIdentityDraftDecision(for: character) {
                guard await library.draftCharacterIdentity(characterId: characterId),
                      let refreshed = characters.first(where: { $0.characterId == characterId }) else { return }
                reseedStudio(for: refreshed, force: false)
            }
            let draft = session.studio(for: characterId)
            _ = await library.startCharacterReferenceRender(
                characterId: characterId,
                prompt: draft.prompt,
                shot: draft.shot,
                stack: stack,
                references: CharacterStudyReferences(mediaIds: draft.referenceIds, look: draft.look)
            )
        }
    }

    // MARK: Chat

    private func chatPane(for character: ProjectCharacter) -> some View {
        let characterId = character.characterId
        let stack = library.resolvedCharacterSheetStack(for: character)
        let turns = (library.projectCharacterChats.thread(for: characterId)?.turns ?? []).map {
            ChatTranscriptTurn(id: $0.turnId, isUser: $0.role == .user, text: $0.text, mediaIds: $0.mediaIds)
        }
        let attachments = library.mediaItems(for: session.attachments(for: characterId)).map {
            ChatComposerAttachment(mediaId: $0.mediaId, filename: $0.filename, thumbnailPath: $0.thumbnailPath, kind: $0.kind)
        }
        let isDrafting = library.draftingCharacterIds.contains(characterId)
        return CharacterChatPane(
            character: character,
            turns: turns,
            isThinking: library.refiningCharacterIds.contains(characterId) || isDrafting,
            thinkingLabel: isDrafting ? "Casting \(character.name) from the story" : "Refining \(character.name)",
            draft: Binding(
                get: { session.draft(for: characterId) },
                set: { session.setDraft($0, for: characterId) }
            ),
            attachments: attachments,
            rendersAfterChat: character.rendersSheetAfterChat,
            promptIsHandEdited: character.hasSheetPromptOverride,
            stackLabel: stack?.label ?? "",
            priceNote: stack.map {
                library.priceNote(
                    for: $0,
                    attachesReferences: character.activeSheetMediaId != nil || !character.referenceMediaIds.isEmpty
                )
            } ?? "",
            statusText: library.characterChatStatus,
            resolveMedia: library.mediaItems(for:),
            onSend: { send(character) },
            onUpload: {
                Task {
                    let items = await library.chooseCharacterChatImageAttachments()
                    addAttachments(characterId, items.map(\.mediaId))
                }
            },
            onRemoveAttachment: { mediaId in
                session.setAttachments(session.attachments(for: characterId).filter { $0 != mediaId }, for: characterId)
            },
            onPasteImageData: { data in
                Task {
                    if let item = await library.importCharacterChatImageData(data) {
                        addAttachments(characterId, [item.mediaId])
                    }
                }
            },
            onPasteFileURLs: { urls in
                Task {
                    let items = await library.importCharacterChatImageFiles(urls)
                    addAttachments(characterId, items.map(\.mediaId))
                }
            },
            onDropMediaIds: { addAttachments(characterId, $0) },
            onToggleAutoRender: { enabled in
                _ = library.setCharacterAutoRenderSheet(characterId: characterId, enabled: enabled)
            }
        )
    }

    private func send(_ character: ProjectCharacter) {
        let characterId = character.characterId
        let text = session.draft(for: characterId)
        let mediaIds = session.attachments(for: characterId)
        guard !text.trimmed.isEmpty || !mediaIds.isEmpty else { return }
        commitPendingEdits()
        session.setDraft("", for: characterId)
        session.setAttachments([], for: characterId)
        Task {
            await library.sendCharacterChatMessage(characterId: characterId, text: text, mediaIds: mediaIds)
        }
    }

    private func addAttachments(_ characterId: String, _ mediaIds: [String]) {
        let merged = uniqueNonEmpty(session.attachments(for: characterId) + mediaIds)
        session.setAttachments(Array(merged.prefix(8)), for: characterId)
    }

    // MARK: Drafts

    private func loadDrafts() {
        guard let character = selectedCharacter else {
            drafts = CharacterEditDrafts()
            return
        }
        // A character's existing sources catch up on analysis when it is visited.
        library.ensureCharacterSourcesAnalyzed(mediaIds: character.referenceMediaIds)
        drafts = CharacterEditDrafts(
            characterId: character.characterId,
            name: character.name,
            appearance: character.descriptionPrompt,
            prompt: character.sheetPromptOverride ?? "",
            isPromptEditRequested: false
        )
    }

    private func commitPendingEdits() {
        commitField(.name)
        commitField(.appearance)
        commitField(.prompt)
    }

    private func commitField(_ field: CharacterEditField) {
        guard let character = characters.first(where: { $0.characterId == drafts.characterId }) else { return }
        let characterId = character.characterId
        switch field {
        case .name:
            let trimmed = drafts.name.trimmed
            if trimmed.isEmpty || trimmed == character.name {
                drafts.name = character.name
            } else if !library.renameCharacter(characterId: characterId, name: trimmed) {
                drafts.name = character.name
            }
        case .appearance:
            let trimmed = drafts.appearance.trimmed
            if trimmed != character.descriptionPrompt {
                _ = library.renameCharacter(characterId: characterId, name: character.name, descriptionPrompt: trimmed)
            }
        case .prompt:
            guard drafts.isPromptEditRequested || character.hasSheetPromptOverride else { return }
            _ = library.setCharacterSheetPromptOverride(characterId: characterId, text: drafts.prompt)
            drafts.isPromptEditRequested = false
            drafts.prompt = characters.first { $0.characterId == characterId }?.sheetPromptOverride ?? ""
        case .newProp, .studioPrompt, .studioRefine:
            break
        }
    }

    // MARK: Sources

    private func createCharacter(_ name: String) {
        guard let created = library.createCharacter(name: name) else { return }
        session.select(created.characterId)
    }

    private func appendSources(_ characterId: String, _ mediaIds: [String]) {
        guard let character = characters.first(where: { $0.characterId == characterId }) else { return }
        _ = library.setCharacterReferenceMedia(characterId: characterId, mediaIds: character.referenceMediaIds + mediaIds)
        // Sources already in media only need their analysis; new intake queued its own.
        library.ensureCharacterSourcesAnalyzed(mediaIds: mediaIds)
    }

    private func placeSource(_ character: ProjectCharacter, mediaId: String, at index: Int) {
        _ = library.setCharacterReferenceMedia(
            characterId: character.characterId,
            mediaIds: ProjectRosterView.reorderedReferences(placing: mediaId, at: index, in: character.referenceMediaIds)
        )
    }

    private func removeSource(_ character: ProjectCharacter, mediaId: String) {
        _ = library.setCharacterReferenceMedia(
            characterId: character.characterId,
            mediaIds: character.referenceMediaIds.filter { $0 != mediaId }
        )
    }

    private func reconcile() {
        if let projectId = library.currentProject?.projectId {
            session.adoptProject(projectId)
        }
        session.reconcile(characterIds: characters.map(\.characterId))
    }

    // MARK: Alerts, empty stage, status

    private func makeAlert(_ alert: CharactersAlert) -> Alert {
        switch alert {
        case .delete(let character):
            return Alert(
                title: Text("Delete \(character.name)?"),
                message: Text("Their sheets and source images stay in the Library; only the character and its conversation go."),
                primaryButton: .destructive(Text("Delete")) {
                    _ = library.deleteCharacter(characterId: character.characterId)
                },
                secondaryButton: .cancel()
            )
        case .resetPrompt(let character):
            return Alert(
                title: Text("Reset to the composed prompt?"),
                message: Text("Your edits are discarded and the prompt is rebuilt from \(character.name)'s identity."),
                primaryButton: .destructive(Text("Reset")) {
                    focus = nil
                    drafts.isPromptEditRequested = false
                    drafts.prompt = ""
                    _ = library.clearCharacterSheetPromptOverride(characterId: character.characterId)
                },
                secondaryButton: .cancel()
            )
        case .redraft(let character):
            return Alert(
                title: Text("Redraft \(character.name) from the story?"),
                message: Text("The appearance, props, and story identity are replaced with a fresh draft from the Goal, the other characters, and the source images. Pinned cast dimensions stay."),
                primaryButton: .destructive(Text("Redraft")) {
                    commitPendingEdits()
                    Task { _ = await library.draftCharacterIdentity(characterId: character.characterId, blanks: Set(CharacterIdentityBlank.allCases)) }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var emptyStage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                Text("Define the people of this project")
                    .font(CanonType.display(22, weight: .semibold))
                    .foregroundStyle(PlateColor.ink)
                Text("Characters usually arrive from the Story conversation. Name one here to start, then render its reference sheet.")
                    .font(CanonType.interface(12))
                    .foregroundStyle(PlateColor.inkFaint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                RosterInlineCreateField(title: "New character", prompt: "Character name — Return creates") { name in
                    createCharacter(name)
                }
                .frame(maxWidth: 320)
                CharacterCapsButton(title: "OPEN STORY →", help: "Open the Story conversation", action: onOpenStory)
            }
            .padding(36)
            .frame(maxWidth: 560)
            .background(PlateColor.cream, in: RoundedRectangle(cornerRadius: 10))
            .overlay(PlateCornerTicks().stroke(CanonColor.brass, lineWidth: 1))
            .environment(\.colorScheme, .light)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var statusText: String {
        if library.isGeneratingCharacterSheet || library.isGeneratingCharacterRender { return library.aestheticStatus }
        if !library.characterChatStatus.isEmpty { return library.characterChatStatus }
        if !library.lastError.isEmpty { return library.lastError }
        return library.aestheticStatus
    }

    private var statusLine: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(CanonColor.hairlineDark)
                .frame(height: 1)
            HStack {
                Spacer(minLength: 0)
                Text(statusText)
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .frame(height: 22)
        }
        .background(CanonColor.archiveWell)
    }
}
