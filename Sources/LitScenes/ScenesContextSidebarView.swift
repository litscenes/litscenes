import AppKit
import SwiftUI

/// The project-production context shared by both Scenes workbenches. The
/// sidebar is intentionally lens-aware while Shots remain lens-agnostic: each
/// host supplies the exact Scene Plan/version it already uses for its canvas.
enum ScenesContextSidebarTab: String, CaseIterable, Identifiable {
    case characters = "Characters"
    case objects = "Objects"
    case places = "Places"
    case voices = "Voice & Audio"
    case logs = "Logs"

    var id: String { rawValue }
}

struct ScenesContextSidebarView: View {
    @ObservedObject var library: LibraryEngine
    let lens: ProjectLens
    let versionId: String
    @Binding var selectedTab: ScenesContextSidebarTab
    @Binding var isCollapsed: Bool
    let onOpenFrame: (ProjectLensHeroImage) -> Void
    let onOpenRoster: (RosterDetailRequest) -> Void
    let onPreviewStyle: (StyleImagePreviewRequest) -> Void
    let onOpenPlace: (String) -> Void
    let onOpenWorldMap: () -> Void
    let onContentChanged: () -> Void
    let onOpenAppSettings: () -> Void
    /// When provided, a character card opens that character on the CHARACTERS tab
    /// instead of the roster sheet (objects keep the sheet).
    var onOpenCharacter: ((String) -> Void)? = nil

    @StateObject private var projectAudioPlayer = SoundRailPlayerController()
    @StateObject private var projectAudioWaveforms = SoundWaveformLoader()
    @State private var expandedProjectAudioId: String?
    @State private var defaultNarrationVoiceId = ""

    var body: some View {
        Group {
            if isCollapsed {
                collapsedRail
            } else {
                expandedSidebar
            }
        }
        .frame(width: isCollapsed ? 34 : 330)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(CanonColor.paperInset)
        .clipped()
    }

    private var expandedSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            tabBar
            Group {
                switch selectedTab {
                case .characters:
                    frameTab(category: .characters)
                case .objects:
                    frameTab(category: .objects)
                case .places:
                    placesTab
                case .voices:
                    voicesTab
                case .logs:
                    logsTab
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var collapsedRail: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { isCollapsed = false }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.62))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show the Characters / Objects / Places / Voice & Audio / Logs panel")
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { isCollapsed = true }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.55))
                    .frame(width: 26, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Collapse this panel")

            ForEach(ScenesContextSidebarTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(CanonType.interface(11, weight: .semibold))
                        .foregroundStyle(selectedTab == tab ? CanonColor.ink : CanonColor.ink.opacity(0.58))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(selectedTab == tab ? Color.white.opacity(0.70) : Color.white.opacity(0.26))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(selectedTab == tab ? CanonColor.brass.opacity(0.52) : CanonColor.hairlinePaper.opacity(0.62), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func frameTab(category: LensConceptCategory) -> some View {
        let isCharacters = category == .characters
        let identityGroups = isCharacters
            ? library.lensCharacterTakeGroups(lens: lens, versionId: versionId)
            : library.lensObjectTakeGroups(lens: lens, versionId: versionId)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if identityGroups.isEmpty {
                    Text(isCharacters
                        ? "No characters yet — define the recurring people of this project below."
                        : "No objects yet — define the recurring objects of this project below.")
                        .font(CanonType.editorial(13))
                        .foregroundStyle(CanonColor.ink.opacity(0.50))
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                } else {
                    SceneCharactersPanel(
                        lens: lens,
                        versionId: versionId,
                        groups: identityGroups,
                        candidates: library.items.filter { $0.kind == .image },
                        isObjects: !isCharacters,
                        hasOpenAICredential: credentialStatus(.openAI)?.isConfigured == true,
                        hasCivitaiCredential: credentialStatus(.civitai)?.isConfigured == true,
                        hasFALCredential: credentialStatus(.fal)?.isConfigured == true,
                        hasStabilityCredential: credentialStatus(.stability)?.isConfigured == true,
                        isRenderBlocked: library.lensHeroTakeStartBlockReason != nil,
                        renderBlockerHelp: library.lensHeroTakeStartBlockReason,
                        isPaused: library.isGenerationPaused,
                        isAnimatingLensArtifact: library.isAnimatingLensArtifact,
                        onOpenImage: onOpenFrame,
                        onOpenIdentity: { group in
                            var entryId = group.rosterId.nilIfEmpty
                            if !isCharacters, entryId == nil {
                                entryId = library.createObject(
                                    name: group.displayName,
                                    descriptionPrompt: group.descriptionPrompt
                                )?.objectId
                                    ?? library.projectObjects.objects
                                        .first { $0.name.lowercased() == group.displayName.lowercased() }?
                                        .objectId
                            }
                            if isCharacters, let onOpenCharacter, let characterId = entryId {
                                onOpenCharacter(characterId)
                                return
                            }
                            onOpenRoster(RosterDetailRequest(
                                kind: isCharacters ? .characters : .objects,
                                entryId: entryId
                            ))
                        },
                        onSubmitRender: { heroImage, request in
                            Task {
                                _ = await library.startLensHeroImageSiblingRender(
                                    lensId: lens.lensId,
                                    imageId: heroImage.imageId,
                                    request: request
                                )
                                onContentChanged()
                            }
                        },
                        onAnimateImage: { heroImage in
                            Task {
                                _ = await library.animateLensHeroImageWithWAN25(
                                    lensId: lens.lensId,
                                    imageId: heroImage.imageId
                                )
                                onContentChanged()
                            }
                        },
                        onPreviewStyle: onPreviewStyle,
                        onApplyTakeStyle: { heroImage, slot, catalogVersion in
                            Task {
                                _ = await library.setLensHeroImageStyle(
                                    lensId: lens.lensId,
                                    imageId: heroImage.imageId,
                                    slot: slot,
                                    catalogVersion: catalogVersion
                                )
                                onContentChanged()
                            }
                        },
                        onOpenAppSettings: onOpenAppSettings
                    )
                }

                RosterInlineCreateField(
                    title: isCharacters ? "New character" : "New object",
                    prompt: isCharacters ? "Character name — Return creates" : "Object name — Return creates"
                ) { name in
                    if isCharacters {
                        guard let created = library.createCharacter(name: name) else { return }
                        if let onOpenCharacter {
                            onOpenCharacter(created.characterId)
                        } else {
                            onOpenRoster(RosterDetailRequest(kind: .characters, entryId: created.characterId))
                        }
                    } else {
                        guard let created = library.createObject(name: name) else { return }
                        onOpenRoster(RosterDetailRequest(kind: .objects, entryId: created.objectId))
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var placesTab: some View {
        let groups = library.lensPlaceFrameGroups(lens: lens, versionId: versionId)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                worldMapButton
                if groups.isEmpty {
                    Text("No places yet — the scene's places arrive with FRAMES planning, or define one below.")
                        .font(CanonType.editorial(13))
                        .foregroundStyle(CanonColor.ink.opacity(0.50))
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                } else {
                    VStack(spacing: 7) {
                        ForEach(groups) { group in
                            placeRow(group)
                        }
                    }
                }
                RosterInlineCreateField(title: "New place", prompt: "Place name — Return creates") { name in
                    guard let created = library.createPlace(name: name) else { return }
                    onOpenPlace(created.placeId)
                }
                Text("Places hold reference images like characters and objects do. @mention a place in the Frame Creator to attach them.")
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(CanonColor.ink.opacity(0.45))
            }
            .padding(.bottom, 12)
        }
    }

    private var worldMapButton: some View {
        let map = library.terrainMap
        let subtitle = map.isSeeded
            ? "\(map.canvasWidth)×\(map.canvasHeight) · \(map.pins.count) pin\(map.pins.count == 1 ? "" : "s")"
            : "Seed a top-down world map"
        return Button(action: onOpenWorldMap) {
            HStack(spacing: 8) {
                Image(systemName: "map")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CanonColor.brass.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(CanonColor.hairlinePaper, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("World Map")
                        .font(CanonType.interface(12, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    Text(subtitle)
                        .font(CanonType.interface(10.5))
                        .foregroundStyle(CanonColor.ink.opacity(0.55))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.4))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.8)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Open the world map — grow terrain and pin places onto it")
    }

    private func placeRow(_ group: LensPlaceFrameGroup) -> some View {
        Button {
            var placeId = group.placeId.nilIfEmpty
            if placeId == nil, !group.displayName.trimmed.isEmpty, group.id != "residual_scenery" {
                placeId = library.createPlace(
                    name: group.displayName,
                    descriptionPrompt: group.descriptionPrompt
                )?.placeId
                    ?? library.projectPlaces.places
                        .first { $0.name.lowercased() == group.displayName.lowercased() }?
                        .placeId
            }
            guard let placeId else { return }
            onOpenPlace(placeId)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CanonColor.brass.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(CanonColor.hairlinePaper, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayName)
                        .font(CanonType.interface(12, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(1)
                    Text("\(group.frames.count) frame\(group.frames.count == 1 ? "" : "s") · \(group.referenceMediaIds.count) ref\(group.referenceMediaIds.count == 1 ? "" : "s")")
                        .font(CanonType.interface(10.5))
                        .foregroundStyle(CanonColor.ink.opacity(0.55))
                }
                Spacer(minLength: 0)
                if !group.placeId.isEmpty, library.terrainMap.pin(forPlaceId: group.placeId) != nil {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CanonColor.brass.opacity(0.8))
                        .help("Pinned on the world map")
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.4))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.8)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help("Expand \(group.displayName) — description, references, and its frames")
    }

    private var voicesTab: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                projectAudioSection
                Divider().overlay(CanonColor.hairlinePaper)
                narrationVoicesSection
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.visible)
        .onAppear {
            defaultNarrationVoiceId = ElevenLabsSettingsStore.resolvedDefaultNarrationVoice()?.voiceId ?? ""
            Task { await library.loadElevenVoices() }
        }
    }

    private var projectAudioSection: some View {
        let audio = library.projectAudioItems
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("PROJECT AUDIO")
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(CanonColor.muted)
                Spacer(minLength: 0)
                Button {
                    library.addMedia()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(0.55))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add audio files to this project")
            }

            if audio.isEmpty {
                Text("No audio yet — add music or effects with +, or from the Media tab.")
                    .font(CanonType.editorial(13))
                    .foregroundStyle(CanonColor.ink.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 6) {
                    ForEach(audio) { item in
                        projectAudioRow(item)
                    }
                }
                Text("Drag onto CLIP to play once or AMBIENT to loop, or use ⋯ to attach directly.")
                    .font(CanonType.archive(8.5))
                    .foregroundStyle(CanonColor.ink.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func projectAudioRow(_ item: MediaItemRecord) -> some View {
        let asset = SoundSceneAsset(audioMediaItem: item)
        let expanded = expandedProjectAudioId == item.mediaId
        let playing = projectAudioPlayer.isPlayingAsset(soundId: asset.soundId, path: asset.path)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    expandedProjectAudioId = item.mediaId
                    projectAudioPlayer.toggle(soundId: asset.soundId, path: asset.path)
                } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .disabled(!projectAudioPlayer.canPlay(soundId: asset.soundId, path: asset.path))
                .help(playing ? "Pause" : "Play")

                Button {
                    expandedProjectAudioId = expanded ? nil : item.mediaId
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(asset.displayName)
                            .font(CanonType.interface(11, weight: .semibold))
                            .foregroundStyle(CanonColor.ink)
                            .lineLimit(2)
                        Text("\(asset.durationLabel) · \(asset.fileTypeLabel)")
                            .font(CanonType.archive(9, weight: .medium))
                            .foregroundStyle(CanonColor.ink.opacity(0.54))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    MediaUseMenu(library: library, item: item)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(0.55))
                        .frame(width: 24, height: 34)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Use this audio in a CUT")
            }

            if expanded {
                SoundRailPlayerTransport(
                    player: projectAudioPlayer,
                    waveformLoader: projectAudioWaveforms,
                    asset: asset
                )
                .padding(.leading, 34)
                .transition(.opacity)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            expanded ? CanonColor.paperAged.opacity(0.74) : Color.white.opacity(0.22),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(expanded ? CanonColor.brass.opacity(0.70) : CanonColor.hairlinePaper.opacity(0.72))
        )
        .draggable(MediaIDTransfer(mediaId: item.mediaId)) {
            Text(asset.displayName)
                .font(CanonType.interface(11, weight: .semibold))
                .padding(6)
                .background(CanonColor.paperAged, in: RoundedRectangle(cornerRadius: 6))
        }
        .contextMenu {
            MediaUseMenu(library: library, item: item)
        }
    }

    private var narrationVoicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("NARRATION VOICES")
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(1.2)
                    .foregroundStyle(CanonColor.muted)
                Spacer(minLength: 0)
                if library.isLoadingAccountVoices {
                    ProgressView().controlSize(.mini)
                }
                Button {
                    Task { await library.loadElevenVoices(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(0.55))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(library.isLoadingAccountVoices)
                .help("Refresh the ElevenLabs account voice list")
            }
            voiceCurationRow
            if !ElevenLabsSettingsStore.hasResolvedAPIKey() {
                Text("Add an ElevenLabs API key in App Settings to list your account voices.")
                    .font(CanonType.editorial(13))
                    .foregroundStyle(CanonColor.ink.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(sidebarVoiceOptions, id: \.id) { option in
                        voiceRow(option)
                    }
                }
                Text("The eye hides a voice from the render-time menus — it stays here, and a narration already using it keeps working. The default voice seeds every new narration. Voice cloning from the microphone is planned.")
                    .font(CanonType.archive(8.5))
                    .foregroundStyle(CanonColor.ink.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var voiceCurationRow: some View {
        let all = sidebarVoiceOptions
        let hiddenCount = all.filter { option in
            guard let id = option.voiceId?.trimmed, !id.isEmpty else { return false }
            return library.hiddenNarrationVoiceIds.contains(id)
        }.count
        if !all.isEmpty {
            HStack(spacing: 8) {
                Text(hiddenCount > 0 ? "\(all.count - hiddenCount) in menus · \(hiddenCount) hidden" : "\(all.count) in menus")
                    .font(CanonType.archive(8))
                    .foregroundStyle(CanonColor.ink.opacity(0.45))
                Spacer(minLength: 0)
                if !StoryAudioVoiceCatalog.stockVoiceIds(in: all)
                    .subtracting(library.hiddenNarrationVoiceIds).isEmpty {
                    Button("Hide stock") {
                        library.hideStockNarrationVoices()
                    }
                    .buttonStyle(.plain)
                    .font(CanonType.archive(8, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
                    .help("Hide ElevenLabs' built-in catalog voices — everything you cloned, generated, or saved stays")
                }
                if hiddenCount > 0 {
                    Button("Show all") {
                        library.showAllNarrationVoices()
                    }
                    .buttonStyle(.plain)
                    .font(CanonType.archive(8, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.5))
                    .help("Put every hidden voice back in the render menus")
                }
            }
        }
    }

    private var sidebarVoiceOptions: [StoryAudioVoiceOption] {
        StoryAudioVoiceCatalog.voiceOptions(
            customVoiceId: ElevenLabsSettingsStore.resolvedCustomVoiceId(),
            extraVoices: library.accountVoiceOptions
        )
    }

    private func voiceRow(_ option: StoryAudioVoiceOption) -> some View {
        let voiceId = option.voiceId?.trimmed ?? ""
        let isConfigured = !voiceId.isEmpty
        let isDefault = isConfigured && voiceId == defaultNarrationVoiceId
        let isHidden = isConfigured && library.hiddenNarrationVoiceIds.contains(voiceId)
        return HStack(spacing: 4) {
            Button {
                guard isConfigured else { return }
                do {
                    try ElevenLabsSettingsStore.saveDefaultNarrationVoice(voiceId: voiceId, name: option.name)
                    defaultNarrationVoiceId = voiceId
                } catch {
                    library.noteVoiceDefaultSaveFailure(error)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isDefault ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isDefault ? CanonColor.brass : CanonColor.ink.opacity(0.35))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.name)
                            .font(CanonType.interface(12, weight: isDefault ? .semibold : .medium))
                            .foregroundStyle(CanonColor.ink.opacity(isConfigured ? 0.85 : 0.4))
                            .lineLimit(1)
                        Text(isConfigured ? option.descriptor : "\(option.descriptor) — not configured")
                            .font(CanonType.archive(8.5))
                            .foregroundStyle(CanonColor.ink.opacity(0.45))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isDefault {
                        Text("DEFAULT")
                            .font(CanonType.archive(7, weight: .bold))
                            .kerning(0.7)
                            .foregroundStyle(CanonColor.brass)
                    } else if isHidden {
                        Text("HIDDEN")
                            .font(CanonType.archive(7, weight: .bold))
                            .kerning(0.7)
                            .foregroundStyle(CanonColor.ink.opacity(0.35))
                    }
                }
                .opacity(isHidden ? 0.55 : 1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isDefault ? Color.white.opacity(0.6) : Color.white.opacity(0.22))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isDefault ? CanonColor.brass.opacity(0.5) : CanonColor.hairlinePaper.opacity(0.6), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(!isConfigured)
            .help(isConfigured ? "Use \(option.name) as the default narration voice" : "Configure this voice's ID in App Settings first")

            if isConfigured {
                Button {
                    if isDefault, !isHidden {
                        library.noteDefaultVoiceCannotHide()
                    } else {
                        library.setNarrationVoiceHidden(voiceId: voiceId, hidden: !isHidden)
                    }
                } label: {
                    Image(systemName: isHidden ? "eye.slash" : "eye")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(isHidden ? 0.32 : 0.5))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isDefault && !isHidden
                    ? "The default voice always stays in the menus — make another voice the default first"
                    : (isHidden
                        ? "Hidden from render menus — click to show it again"
                        : "Hide this voice from the render-time menus (it stays here)"))
            }
        }
    }

    private var logsTab: some View {
        let versions = Array(library.projectLenses.bodyVersions(for: lens.lensId).reversed())
        let generationEntries = Array(library.generationLogEntries.reversed().prefix(40))
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("GENERATION ACTIVITY")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.45))
                if generationEntries.isEmpty {
                    Text("No image or video generations yet this session.")
                        .font(CanonType.editorial(13))
                        .foregroundStyle(CanonColor.ink.opacity(0.50))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(generationEntries) { entry in
                        generationLogRow(entry)
                    }
                }

                Divider().padding(.vertical, 4)

                Text("LENS BODY VERSIONS")
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.45))
                if versions.isEmpty {
                    Text("No Scene Plan versions saved yet.")
                        .font(CanonType.editorial(13))
                        .foregroundStyle(CanonColor.ink.opacity(0.50))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(versions.prefix(12)), id: \.versionId) { version in
                        lensVersionRow(version)
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func generationLogRow(_ entry: MediaAnalysisLogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: generationLogIcon(for: entry.kind))
                .font(.caption.weight(.semibold))
                .foregroundStyle(generationLogColor(for: entry.kind))
                .frame(width: 15, height: 15)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(entry.timestamp.prefix(19)).replacingOccurrences(of: "T", with: " "))
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.42))
                Text(entry.message)
                    .font(CanonType.interface(12))
                    .foregroundStyle(CanonColor.ink.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func generationLogIcon(for kind: String) -> String {
        if kind.hasSuffix(".error") { return "exclamationmark.triangle" }
        if kind.hasSuffix(".completed") { return "checkmark.circle" }
        if kind.hasPrefix("video") { return "film" }
        if kind.hasPrefix("image") { return "photo" }
        return "circle"
    }

    private func generationLogColor(for kind: String) -> Color {
        if kind.hasSuffix(".error") { return CanonColor.rust }
        if kind.hasSuffix(".completed") { return CanonColor.olive }
        return CanonColor.brass
    }

    private func lensVersionRow(_ version: ProjectLensBodyVersion) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if version.isActive {
                    Circle()
                        .fill(CanonColor.olive)
                        .frame(width: 7, height: 7)
                }
                Text(version.changeSummary.trimmed.isEmpty ? "Scene Plan version" : version.changeSummary)
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                    .lineLimit(2)
            }
            Text(version.createdAt)
                .font(CanonType.archive(10, weight: .medium))
                .foregroundStyle(CanonColor.ink.opacity(0.48))
                .lineLimit(1)
            if !version.model.trimmed.isEmpty {
                Text(version.model)
                    .font(CanonType.archive(9, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            version.isActive ? CanonColor.softGold.opacity(0.22) : Color.white.opacity(0.38),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(version.isActive ? CanonColor.brass.opacity(0.36) : CanonColor.hairlinePaper.opacity(0.70))
        )
    }

    private func credentialStatus(_ provider: LitScenesProviderCredential) -> CredentialStatus? {
        library.videoProviderCredentialStatuses.first { $0.provider == provider }
    }
}

/// The Places sidebar's expanded workspace. Both Scenes surfaces host this
/// same panel over their canvas, so a place row never degrades into a passive
/// summary when the operator changes workbench.
struct ScenesPlaceDetailView: View {
    @ObservedObject var library: LibraryEngine
    let lens: ProjectLens
    let versionId: String
    let place: ProjectPlace
    let onClose: () -> Void
    let onLaunchFrameCreator: (FrameCreationContext) -> Void
    let onOpenFrame: (ProjectLensHeroImage) -> Void

    private var frames: [ProjectLensHeroImage] {
        library.lensPlaceFrameGroups(lens: lens, versionId: versionId)
            .first { $0.placeId == place.placeId }?
            .frames ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(CanonColor.hairlinePaper).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !place.descriptionPrompt.isEmpty {
                        Text(place.descriptionPrompt)
                            .font(CanonType.editorial(13))
                            .foregroundStyle(CanonColor.ink.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    referencesSection
                    framesSection
                }
                .padding(18)
            }
        }
        .background(CanonColor.paperInset)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CanonColor.brass)
            Text(place.name)
                .font(CanonType.editorial(17, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            if place.referenceMediaIds.isEmpty && frames.allSatisfy({ $0.status != "ready" }) {
                Text("PROPOSED")
                    .font(CanonType.archive(8, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(CanonColor.brass)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(CanonColor.brass.opacity(0.12)))
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.55))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Tuck this place back into the sidebar")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.55))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var referencesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REFERENCES")
                .font(CanonType.archive(8.5, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(CanonColor.muted)
            HStack(alignment: .center, spacing: 8) {
                ForEach(referenceItems, id: \.mediaId) { item in
                    referenceThumb(item)
                }
                Button {
                    Task { await attachReferences() }
                } label: {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(CanonColor.hairlinePaper, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                        .frame(width: 46, height: 46)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CanonColor.brass)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Attach reference images to \(place.name)")
                Text("Attach from your files, or promote a rendered frame. @mention \(place.name) in the Frame Creator to attach these references.")
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(CanonColor.ink.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var referenceItems: [MediaItemRecord] {
        place.referenceMediaIds
            .compactMap { mediaId in library.items.first { $0.mediaId == mediaId } }
            .filter { $0.kind == .image }
    }

    private func referenceThumb(_ item: MediaItemRecord) -> some View {
        Group {
            if let image = NSImage(contentsOfFile: item.path) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(CanonColor.paperInset)
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlinePaper))
    }

    private func attachReferences() async {
        let records = await library.chooseRosterReferenceImages()
        guard !records.isEmpty else { return }
        _ = library.setPlaceReferenceMedia(
            placeId: place.placeId,
            mediaIds: place.referenceMediaIds + records.map(\.mediaId)
        )
    }

    private var framesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FRAMES IN THIS PLACE")
                .font(CanonType.archive(8.5, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(CanonColor.muted)
            if frames.isEmpty {
                Text("No frames yet — add one below.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.ink.opacity(0.5))
            }
            ForEach(frames, id: \.imageId) { frame in
                frameRow(frame)
            }
            Button {
                onLaunchFrameCreator(.blankFrame(category: .scenery))
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                    Text("New frame in this place")
                        .font(CanonType.interface(11, weight: .semibold))
                }
                .foregroundStyle(CanonColor.brass)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the Frame Creator for a new frame — @mention \(place.name) to attach its references")
        }
    }

    private func frameRow(_ frame: ProjectLensHeroImage) -> some View {
        let title = frame.label.components(separatedBy: " · ").first?.trimmed ?? frame.label
        return HStack(spacing: 10) {
            frameThumb(frame)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.isEmpty ? "Frame" : title)
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                    .lineLimit(1)
                Text(frameStatusLine(frame))
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(CanonColor.ink.opacity(0.55))
                    .lineLimit(1)
                    .help(frameStatusLine(frame))
            }
            Spacer(minLength: 0)
            if frame.isPlanFulfillmentCandidate {
                Button {
                    onLaunchFrameCreator(.plannedFrame(frame))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .semibold))
                        Text("Frame Creator")
                            .font(CanonType.interface(10.5, weight: .semibold))
                    }
                    .foregroundStyle(CanonColor.paper)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(CanonColor.brass))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Open the Frame Creator to render this planned frame")
            } else if frame.status == "ready" {
                Button {
                    onOpenFrame(frame)
                } label: {
                    Text("Open")
                        .font(CanonType.interface(10.5, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(0.7))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Capsule().fill(Color.white.opacity(0.6)))
                        .overlay(Capsule().stroke(CanonColor.hairlinePaper))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Open this frame in the preview")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.hairlinePaper.opacity(0.8)))
    }

    private func frameStatusLine(_ frame: ProjectLensHeroImage) -> String {
        switch frame.status {
        case "ready":
            return frame.styleAuthorities.first.map { "Style · \($0.title)" } ?? "Ready"
        case "generating":
            return "Rendering"
        case "failed", "cancelled":
            let message = frame.errorMessage.trimmed
            return message.isEmpty ? "Rendering failed — reopen the Frame Creator to retry" : message
        default:
            return "Planned"
        }
    }

    private func frameThumb(_ frame: ProjectLensHeroImage) -> some View {
        Group {
            if frame.status == "ready", !frame.imagePath.isEmpty,
               let image = NSImage(contentsOfFile: frame.imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 47)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(CanonColor.hairlinePaper, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    .frame(width: 84, height: 47)
                    .overlay(
                        Group {
                            if frame.status == "generating" {
                                ProgressView().controlSize(.mini)
                            } else {
                                Text(frame.status == "failed" || frame.status == "cancelled" ? "Failed" : "Planned")
                                    .font(CanonType.archive(8, weight: .semibold))
                                    .kerning(0.8)
                                    .foregroundStyle(CanonColor.muted)
                            }
                        }
                    )
            }
        }
    }
}
