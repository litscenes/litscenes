import SwiftUI

/// The per-shot narration strip in the SHOTS band: pick one meaning message
/// (LLM-drafted chips), pick a voice, generate — then the FULL voiced script
/// (the message title followed by its drafted body) shows beneath its chip as a
/// single editable transcript with a play bar. The transcript is exactly what
/// the audio speaks; editing it and pressing RE-VOICE re-records the audio to
/// match verbatim (no re-drafting, so the body is never silently dropped).
/// Picking a different chip generates a fresh narration for that message. Chips
/// drafted against an older frame strip are marked STALE but stay usable.
/// THE QUICK SUBMIT: a "Type the narration yourself…" row skips all of that —
/// exact text, voiced verbatim, no chip and no LLM draft; the typed text
/// becomes both the message label and the transcript, so the result rides the
/// seed-chip + transcript grammar (editable, re-voiceable, versioned).
struct ShotNarrationStrip: View {
    let shot: ProjectShot
    let isLoadingChips: Bool
    let isNarrating: Bool
    let isRemixingSpeed: Bool
    /// ElevenLabs account voices appended to the catalog presets in the menus.
    var extraVoices: [StoryAudioVoiceOption] = []
    /// Voice ids curated out of this menu in the Voices tab.
    var hiddenVoiceIds: Set<String> = []
    @ObservedObject var player: NarrationAudioPlayer
    var onGenerateChips: (Bool) -> Void
    /// (messagingText, voicePresetId, scriptOverride) — a nil override drafts
    /// a fresh script; non-nil voices exactly that text.
    var onNarrate: (String, String, String?) -> Void
    var onSetSpeed: (Double) -> Void

    @State private var selectedMessaging = ""
    @State private var voicePresetId = ""
    @State private var editedScript = ""
    @State private var speedDraft = StoryAudioVoiceCatalog.defaultSpeed
    @State private var isEditingSpeed = false
    @State private var showSpeedPopover = false
    @State private var showQuickComposer = false
    @State private var quickText = ""

    private var narration: ShotNarrationArtifact? { shot.narrationArtifact }

    private var narrationReady: Bool {
        guard let narration, narration.isReady else { return false }
        return FileManager.default.fileExists(atPath: narration.audioPath)
    }

    private var chipsAreStale: Bool {
        guard let chips = shot.narrationChips, !chips.statements.isEmpty else { return false }
        return chips.entriesFingerprint != shotEntriesFingerprint(shot)
    }

    private var hasElevenLabsKey: Bool {
        ElevenLabsSettingsStore.hasResolvedAPIKey()
    }

    /// The MENU list: configured voices minus the ones curated out in the
    /// Voices tab — but never minus the one this narration already uses
    /// (THE VOICE CURATION LAW keeps a menu able to show its own value).
    private var voiceOptions: [StoryAudioVoiceOption] {
        let all = StoryAudioVoiceCatalog.voiceOptions(
            customVoiceId: ElevenLabsSettingsStore.resolvedCustomVoiceId(),
            extraVoices: extraVoices
        )
        .filter { ($0.voiceId?.trimmed.isEmpty ?? true) == false }
        let selected = StoryAudioVoiceCatalog.option(
            for: resolvedVoicePresetId,
            customVoiceId: ElevenLabsSettingsStore.resolvedCustomVoiceId(),
            extraVoices: extraVoices
        ).voiceId
        return StoryAudioVoiceCatalog.visibleOptions(
            all,
            hiddenVoiceIds: hiddenVoiceIds,
            keepingVoiceId: selected
        )
    }

    private var resolvedVoicePresetId: String {
        if !voicePresetId.isEmpty { return voicePresetId }
        if let saved = narration?.voicePresetId.nilIfEmpty { return saved }
        return StoryAudioVoiceCatalog.defaultOption(
            customVoiceId: ElevenLabsSettingsStore.resolvedCustomVoiceId(),
            extraVoices: extraVoices
        ).id
    }

    private var effectiveMessaging: String {
        selectedMessaging.nilIfEmpty ?? narration?.messagingText ?? ""
    }

    /// The chip that seeded the current voiced narration.
    private var scriptChip: String {
        narration?.messagingText ?? ""
    }

    /// The full transcript the current audio actually speaks (title + body).
    private var transcript: String {
        narration?.script.trimmed ?? ""
    }

    /// True when the selected chip is the one whose audio is ready — i.e. the
    /// transcript editor is showing THIS narration's spoken text.
    private var isViewingReadyNarration: Bool {
        narrationReady && !effectiveMessaging.isEmpty && effectiveMessaging == scriptChip
    }

    /// The editor buffer differs from the audio's transcript, so a re-voice is
    /// needed before the audio matches what is on screen.
    private var scriptIsEdited: Bool {
        guard isViewingReadyNarration else { return false }
        return editedScript.trimmed != transcript
    }

    /// The text a re-voice (voice change) should speak: the on-screen edit when
    /// present, otherwise the current transcript — never a bare chip title, so
    /// the drafted body is preserved.
    private var scriptForRevoice: String? {
        editedScript.trimmed.nilIfEmpty ?? narration?.script.trimmed.nilIfEmpty
    }

    /// Seed the editor with the FULL transcript when viewing the ready
    /// narration; otherwise keep it empty (a different/unvoiced chip has no
    /// transcript yet — it is generated fresh).
    private func seedEditor() {
        editedScript = isViewingReadyNarration ? transcript : ""
    }

    private func syncSpeedFromNarration() {
        guard !isEditingSpeed else { return }
        speedDraft = narration?.effectiveVoiceSpeed ?? StoryAudioVoiceCatalog.defaultSpeed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chipsSection
            actionRow
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9).fill(CanonColor.paperInset.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(CanonColor.hairlinePaper.opacity(0.9), lineWidth: 1))
        .frame(maxWidth: 640, alignment: .leading)
        .animation(.easeOut(duration: 0.18), value: effectiveMessaging)
        .animation(.easeOut(duration: 0.18), value: narrationReady)
        .onAppear {
            seedEditor()
            syncSpeedFromNarration()
            if (shot.narrationChips?.statements.isEmpty ?? true) && !isLoadingChips {
                onGenerateChips(false)
            }
        }
        .onChange(of: narration?.script ?? "") { seedEditor() }
        .onChange(of: narrationReady) { seedEditor() }
        .onChange(of: effectiveMessaging) { seedEditor() }
        .onChange(of: narration?.voiceSpeed ?? StoryAudioVoiceCatalog.defaultSpeed) { _, _ in
            syncSpeedFromNarration()
        }
        .onChange(of: isRemixingSpeed) { _, isRemixing in
            if !isRemixing {
                syncSpeedFromNarration()
            }
        }
    }

    // MARK: Meaning-message chips

    @ViewBuilder
    private var chipsSection: some View {
        HStack(spacing: 8) {
            Text("MEANING MESSAGE")
                .font(CanonType.archive(7.5, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(CanonColor.muted)
            if chipsAreStale {
                Text("STALE")
                    .font(CanonType.archive(7, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(CanonColor.rust)
                    .padding(.horizontal, 5)
                    .frame(height: 14)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(CanonColor.rust.opacity(0.55), lineWidth: 1))
                    .help("The frame strip changed after these messages were drafted — refresh to redraft them.")
            }
            if isLoadingChips {
                ProgressView()
                    .controlSize(.mini)
                Text("DRAFTING MESSAGES")
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(CanonColor.brass)
            } else {
                Button {
                    onGenerateChips(true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CanonColor.muted)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Draft fresh meaning messages from the current frame strip")
            }
            Spacer(minLength: 0)
        }
        let statements = shot.narrationChips?.statements ?? []
        if !statements.isEmpty || (!transcript.isEmpty && !scriptChip.isEmpty) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(statements, id: \.self) { statement in
                    chipRow(statement)
                }
                // The narration's seed chip survives even when redrafted chips
                // no longer include it — its transcript must stay reachable.
                if !transcript.isEmpty, !scriptChip.isEmpty, !statements.contains(scriptChip) {
                    chipRow(scriptChip)
                }
            }
        }
        quickComposerRow
    }

    // MARK: Quick submit

    /// Type exact text, voice it verbatim — no chip pick, no LLM draft. Rides
    /// beneath the chips so it is reachable even while messages are drafting,
    /// when drafting refused (footage-only shots), or before any chip exists.
    @ViewBuilder
    private var quickComposerRow: some View {
        if showQuickComposer {
            quickComposerPanel
        } else {
            Button {
                showQuickComposer = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(CanonColor.muted)
                    Text("Type the narration yourself…")
                        .font(CanonType.archive(9))
                        .foregroundStyle(CanonColor.ink.opacity(0.6))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(CanonColor.paperInset.opacity(0.35)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(CanonColor.hairlinePaper, style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Skip the drafted messages — type exact text and voice it as-is")
        }
    }

    private var quickSubmitEnabled: Bool {
        !quickText.trimmed.isEmpty && !isNarrating && !isRemixingSpeed && hasElevenLabsKey
    }

    private var quickComposerPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("QUICK NARRATION")
                    .font(CanonType.archive(6.5, weight: .semibold))
                    .kerning(0.9)
                    .foregroundStyle(CanonColor.muted.opacity(0.85))
                Text("(voiced exactly as typed — nothing is drafted)")
                    .font(CanonType.archive(6.5))
                    .foregroundStyle(CanonColor.muted.opacity(0.6))
                Spacer(minLength: 0)
            }
            TextEditor(text: $quickText)
                .font(CanonType.editorial(13))
                .foregroundStyle(CanonColor.ink)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 100)
                .background(RoundedRectangle(cornerRadius: 6).fill(CanonColor.paper.opacity(0.75)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            quickText.trimmed.isEmpty ? CanonColor.hairlinePaper : CanonColor.brass.opacity(0.55),
                            lineWidth: 1
                        )
                )
            HStack(spacing: 8) {
                Button {
                    submitQuickText()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 8, weight: .semibold))
                        Text("NARRATE THIS TEXT")
                            .font(CanonType.archive(7.5, weight: .bold))
                            .kerning(0.6)
                    }
                    .foregroundStyle(quickSubmitEnabled ? CanonColor.brass : CanonColor.muted)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(CanonColor.brass.opacity(quickSubmitEnabled ? 0.10 : 0.0)))
                    .overlay(Capsule().stroke(CanonColor.brass.opacity(quickSubmitEnabled ? 0.45 : 0.2), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!quickSubmitEnabled)
                .help(hasElevenLabsKey
                    ? "Voice exactly this text with the picked voice"
                    : "Add an ElevenLabs API key in App Settings first")

                Button {
                    showQuickComposer = false
                    quickText = ""
                } label: {
                    Text("CANCEL")
                        .font(CanonType.archive(7.5, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.muted)
                }
                .buttonStyle(.plain)
                .help("Close without narrating")
            }
        }
    }

    /// The typed text is both the message label and the verbatim script — the
    /// finished narration then surfaces as its own seed chip with the standard
    /// editable transcript beneath.
    private func submitQuickText() {
        let text = quickText.trimmed
        guard !text.isEmpty else { return }
        selectedMessaging = ""
        onNarrate(text, resolvedVoicePresetId, text)
        quickText = ""
        showQuickComposer = false
    }

    /// One chip plus, when it is the selected chip, the narration text sliding
    /// down beneath it: the editable transcript for the voiced chip, or a
    /// Generate prompt for any other chip.
    @ViewBuilder
    private func chipRow(_ statement: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            messageChip(statement)
            if effectiveMessaging == statement {
                Group {
                    if narrationReady, statement == scriptChip {
                        transcriptPanel
                    } else if narrationReady {
                        // A narration exists for another chip; offer to voice
                        // this message instead (drafts a fresh body).
                        switchGeneratePanel(statement)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func messageChip(_ statement: String) -> some View {
        let isSelected = effectiveMessaging == statement
        let isVoiced = narrationReady && statement == scriptChip
        return Button {
            selectedMessaging = isSelected ? "" : statement
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(isSelected ? CanonColor.brass : CanonColor.muted.opacity(0.3))
                    .frame(width: 5, height: 5)
                chipText(statement, isSelected: isSelected)
                    .font(CanonType.archive(9, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? CanonColor.ink : CanonColor.ink.opacity(0.72))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if isVoiced {
                    Image(systemName: "waveform")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(CanonColor.brass.opacity(0.8))
                        .help("This message is the current narration")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? CanonColor.brass.opacity(0.12) : CanonColor.paperInset.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected ? CanonColor.brass.opacity(0.6) : CanonColor.hairlinePaper.opacity(0.8),
                        lineWidth: isSelected ? 1.3 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(isVoiced ? "The current narration — its transcript is below" : "Voice this message as the shot's narration")
    }

    /// Title rendering: the first three words carry the weight.
    private func chipText(_ statement: String, isSelected: Bool) -> Text {
        let words = statement.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let head = words.prefix(3).joined(separator: " ")
        let tail = words.dropFirst(3).joined(separator: " ")
        var text = Text(head).fontWeight(.bold)
        if !tail.isEmpty {
            text = text + Text(" " + tail)
        }
        return text
    }

    // MARK: Editable transcript

    /// The full spoken transcript of the current audio: edit freely, then
    /// RE-VOICE to re-record the audio to match exactly (the body is carried
    /// along, never dropped). Each voiced text becomes a new version.
    private var transcriptPanel: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("NARRATION TEXT")
                    .font(CanonType.archive(6.5, weight: .semibold))
                    .kerning(0.9)
                    .foregroundStyle(CanonColor.muted.opacity(0.85))
                Text("(what the audio says)")
                    .font(CanonType.archive(6.5))
                    .foregroundStyle(CanonColor.muted.opacity(0.6))
                let versionCount = narration?.titleVersions.count ?? 0
                if versionCount > 1 {
                    Text("V\(versionCount)")
                        .font(CanonType.archive(6.5, weight: .bold))
                        .kerning(0.5)
                        .foregroundStyle(CanonColor.brass.opacity(0.85))
                        .help("This narration has \(versionCount) voiced versions")
                }
                Spacer(minLength: 0)
            }
            TextEditor(text: $editedScript)
                .font(CanonType.editorial(13))
                .foregroundStyle(CanonColor.ink)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 140)
                .background(RoundedRectangle(cornerRadius: 6).fill(CanonColor.paper.opacity(0.75)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            scriptIsEdited ? CanonColor.brass.opacity(0.55) : CanonColor.hairlinePaper,
                            lineWidth: 1
                        )
                )
            HStack(spacing: 8) {
                Button {
                    onNarrate(effectiveMessaging, resolvedVoicePresetId, editedScript.trimmed)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.system(size: 8, weight: .semibold))
                        Text("RE-VOICE")
                            .font(CanonType.archive(7.5, weight: .bold))
                            .kerning(0.6)
                    }
                    .foregroundStyle(scriptIsEdited ? CanonColor.brass : CanonColor.muted)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(CanonColor.brass.opacity(scriptIsEdited ? 0.10 : 0.0)))
                    .overlay(Capsule().stroke(CanonColor.brass.opacity(scriptIsEdited ? 0.45 : 0.2), lineWidth: 1))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isNarrating || isRemixingSpeed || !scriptIsEdited || editedScript.trimmed.isEmpty)
                .help("Re-record the audio to speak exactly this text — nothing is redrafted")

                Button {
                    seedEditor()
                } label: {
                    Text("REVERT")
                        .font(CanonType.archive(7.5, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(scriptIsEdited ? CanonColor.muted : CanonColor.muted.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!scriptIsEdited)
                .help("Discard the edit and restore the current transcript")

                if scriptIsEdited {
                    Text("· edited — re-voice to update the audio")
                        .font(CanonType.archive(6.5, weight: .medium))
                        .foregroundStyle(CanonColor.brass.opacity(0.8))
                }
            }
        }
        .padding(.leading, 16)
    }

    /// Shown when a narration exists but the user selects a DIFFERENT chip: a
    /// prompt to voice that message instead (drafts a fresh body).
    private func switchGeneratePanel(_ statement: String) -> some View {
        HStack(spacing: 8) {
            Text("No narration for this message yet.")
                .font(CanonType.archive(8))
                .foregroundStyle(CanonColor.muted)
            Button {
                onNarrate(statement, resolvedVoicePresetId, nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 8, weight: .semibold))
                    Text("GENERATE")
                        .font(CanonType.archive(7.5, weight: .bold))
                        .kerning(0.6)
                }
                .foregroundStyle(CanonColor.brass)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Capsule().fill(CanonColor.brass.opacity(0.10)))
                .overlay(Capsule().stroke(CanonColor.brass.opacity(0.45), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isNarrating || isRemixingSpeed || !hasElevenLabsKey)
            .help(hasElevenLabsKey ? "Draft and voice a narration for this message" : "Add an ElevenLabs API key in App Settings first")
            Spacer(minLength: 0)
        }
        .padding(.leading, 16)
    }

    // MARK: Voice + generate / states

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 10) {
            if isNarrating {
                ProgressView()
                    .controlSize(.mini)
                Text("VOICING NARRATION")
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(CanonColor.brass)
            } else if narrationReady, let narration {
                readyPlayer(narration)
            } else if !hasElevenLabsKey {
                Image(systemName: "key")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
                Text("Add an ElevenLabs API key in App Settings to narrate this shot.")
                    .font(CanonType.archive(8.5))
                    .foregroundStyle(CanonColor.muted)
            } else {
                voiceMenu
                generateButton(label: narration?.status == "failed" ? "RETRY" : "GENERATE")
                if narration?.status == "failed" {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CanonColor.rust)
                        .help(narration?.errorMessage.nilIfEmpty ?? "Narration failed")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var voiceMenu: some View {
        Menu {
            ForEach(voiceOptions, id: \.id) { option in
                Button("\(option.name) — \(option.descriptor)") {
                    voicePresetId = option.id
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "person.wave.2")
                    .font(.system(size: 8, weight: .semibold))
                Text(voiceLabel)
                    .font(CanonType.archive(8, weight: .semibold))
                    .kerning(0.4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .semibold))
            }
            .foregroundStyle(CanonColor.ink.opacity(0.62))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill(CanonColor.paperInset.opacity(0.6)))
            .overlay(Capsule().stroke(CanonColor.hairlinePaper.opacity(0.8), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isNarrating || isRemixingSpeed)
        .help("Pick the narration voice")
    }

    private var voiceLabel: String {
        let options = voiceOptions
        return options.first { $0.id == resolvedVoicePresetId }?.name.uppercased()
            ?? options.first?.name.uppercased()
            ?? "VOICE"
    }

    private func generateButton(label: String) -> some View {
        let messaging = effectiveMessaging
        return Button {
            // First voicing of a chip always drafts the body (override nil).
            onNarrate(messaging, resolvedVoicePresetId, nil)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 8, weight: .semibold))
                Text(label)
                    .font(CanonType.archive(7.5, weight: .bold))
                    .kerning(0.6)
            }
            .foregroundStyle(CanonColor.brass)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill(CanonColor.brass.opacity(0.10)))
            .overlay(Capsule().stroke(CanonColor.brass.opacity(0.45), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isNarrating || isRemixingSpeed || messaging.isEmpty)
        .help(messaging.isEmpty ? "Pick a meaning message first" : "Draft and voice this message as the shot's narration")
    }

    // MARK: Ready play bar

    @ViewBuilder
    private func readyPlayer(_ narration: ShotNarrationArtifact) -> some View {
        Button {
            player.toggle(path: narration.audioPath)
        } label: {
            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(CanonColor.brass)
        }
        .buttonStyle(.plain)
        .help(player.isPlaying ? "Pause narration" : "Play narration")

        ZStack(alignment: .leading) {
            Capsule()
                .fill(CanonColor.hairlinePaper)
            Capsule()
                .fill(CanonColor.brass)
                .frame(width: max(0, 110 * player.progress))
        }
        .frame(width: 110, height: 3)

        Text("\(timeLabel(player.currentTime)) / \(timeLabel(playerDuration(narration)))")
            .font(CanonType.archive(8, weight: .medium))
            .foregroundStyle(CanonColor.muted)
            .monospacedDigit()

        Menu {
            ForEach(voiceOptions, id: \.id) { option in
                Button("\(option.name) — \(option.descriptor)") {
                    voicePresetId = option.id
                    // A voice change keeps the script — only the voice is redone.
                    onNarrate(effectiveMessaging, option.id, scriptForRevoice)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.wave.2")
                    .font(.system(size: 8, weight: .semibold))
                Text(narration.voiceName.isEmpty ? "VOICE" : narration.voiceName.uppercased())
                    .font(CanonType.archive(8, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .semibold))
            }
            .foregroundStyle(CanonColor.muted)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isNarrating || isRemixingSpeed)
        .help("Re-voice this script with a different voice")

        Button {
            onNarrate(effectiveMessaging, resolvedVoicePresetId, nil)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CanonColor.muted)
        }
        .buttonStyle(.plain)
        .disabled(isNarrating || isRemixingSpeed || effectiveMessaging.isEmpty)
        .help("Redraft the body and re-voice this message fresh")

        speedControl(narration)
    }

    private func speedControl(_ narration: ShotNarrationArtifact) -> some View {
        Button {
            syncSpeedFromNarration()
            showSpeedPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                if isRemixingSpeed {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text("SPEED")
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .kerning(0.5)
                Text(String(format: "%.2f×", narration.effectiveVoiceSpeed))
                    .font(CanonType.archive(8.5, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(isRemixingSpeed ? CanonColor.brass : CanonColor.muted)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill(CanonColor.paperInset.opacity(0.6)))
            .overlay(Capsule().stroke(CanonColor.hairlinePaper.opacity(0.8), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isNarrating)
        .help("Locally retime this narration — no ElevenLabs call")
        .popover(isPresented: $showSpeedPopover, arrowEdge: .bottom) {
            speedPopover(narration)
        }
    }

    private func speedPopover(_ narration: ShotNarrationArtifact) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("NARRATION SPEED")
                    .font(CanonType.archive(8, weight: .bold))
                    .kerning(0.9)
                    .foregroundStyle(CanonColor.ink)
                Spacer(minLength: 0)
                if isRemixingSpeed {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(String(format: "%.2f×", StoryAudioVoiceCatalog.clampedSpeed(speedDraft)))
                    .font(CanonType.archive(10, weight: .bold))
                    .foregroundStyle(isRemixingSpeed ? CanonColor.brass : CanonColor.muted)
                    .monospacedDigit()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                ForEach(StoryAudioVoiceCatalog.speedPresets) { preset in
                    Button {
                        speedDraft = preset.speed
                        commitSpeed(preset.speed, narration: narration)
                    } label: {
                        Text(preset.label.uppercased())
                            .font(CanonType.archive(7, weight: .semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .background(
                                Capsule().fill(
                                    speedPresetIsSelected(preset)
                                        ? CanonColor.brass.opacity(0.18)
                                        : CanonColor.paperInset.opacity(0.55)
                                )
                            )
                            .overlay(
                                Capsule().stroke(
                                    speedPresetIsSelected(preset)
                                        ? CanonColor.brass.opacity(0.65)
                                        : CanonColor.hairlinePaper,
                                    lineWidth: 1
                                )
                            )
                            .foregroundStyle(speedPresetIsSelected(preset) ? CanonColor.ink : CanonColor.muted)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRemixingSpeed)
                }
            }

            Slider(
                value: Binding(
                    get: { StoryAudioVoiceCatalog.clampedSpeed(speedDraft) },
                    set: { speedDraft = StoryAudioVoiceCatalog.clampedSpeed($0) }
                ),
                in: StoryAudioVoiceCatalog.speedRange,
                step: 0.02,
                onEditingChanged: { editing in
                    isEditingSpeed = editing
                    if !editing {
                        commitSpeed(speedDraft, narration: narration)
                    }
                }
            )
            .controlSize(.small)
            .disabled(isRemixingSpeed)

            HStack {
                Text("0.70×")
                Spacer(minLength: 0)
                Text("2.00×")
            }
            .font(CanonType.archive(7, weight: .medium))
            .foregroundStyle(CanonColor.muted.opacity(0.75))

            if let warning = durationOverflowWarning(narration) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 9, weight: .semibold))
                    Text(warning)
                        .font(CanonType.archive(7.5, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(CanonColor.rust)
            }

            Text("Pitch-preserving local processing. The original ElevenLabs take stays untouched.")
                .font(CanonType.archive(7.5))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 300)
        .background(CanonColor.paper)
    }

    private func speedPresetIsSelected(_ preset: StoryAudioSpeedPreset) -> Bool {
        abs(StoryAudioVoiceCatalog.clampedSpeed(speedDraft) - preset.speed) <= 0.025
    }

    private func commitSpeed(_ speed: Double, narration: ShotNarrationArtifact) {
        let clamped = StoryAudioVoiceCatalog.clampedSpeed(speed)
        speedDraft = clamped
        guard !isRemixingSpeed, abs(narration.effectiveVoiceSpeed - clamped) > 0.001 else { return }
        player.stop()
        onSetSpeed(clamped)
    }

    private func durationOverflowWarning(_ narration: ShotNarrationArtifact) -> String? {
        guard let shotSeconds = shot.renderArtifact?.totalSeconds, shotSeconds > 0 else { return nil }
        let shotDuration = Double(shotSeconds)
        let predicted = narration.duration(at: speedDraft)
        guard predicted > shotDuration + 0.05 else { return nil }
        return "About \(timeLabel(predicted)) of narration for a \(timeLabel(shotDuration)) Shot. Narrated playback and export will trim the ending."
    }

    private func playerDuration(_ narration: ShotNarrationArtifact) -> Double {
        player.duration > 0 ? player.duration : narration.durationSeconds
    }

    private func timeLabel(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
