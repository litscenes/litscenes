@preconcurrency import AVFoundation
import AVKit
import SwiftUI
import UniformTypeIdentifiers

struct FinalsReelRequest: Identifiable {
    var id: String { "finals_reel" }
}

/// THE FINALS REEL — the shelf's order, playable and exportable as one film.
/// One live composition (per-cut bakes stitched in finals order + the music
/// bed) backs BOTH the preview player and the export session; reorders,
/// seams, and music cost zero re-encodes because the bakes are cached by
/// fingerprint. Reuses the shot player's transport stack wholesale.
struct FinalsReelPlayerView: View {
    @ObservedObject var library: LibraryEngine
    var onClose: () -> Void

    @Environment(\.undoManager) private var undoManager
    @StateObject private var reelUndo = FinalsReelUndoCoordinator()
    @State private var player: AVPlayer?
    @State private var loopObserver: NSObjectProtocol?
    @State private var timeObserverToken: Any?
    @State private var playerLoadToken = 0
    @State private var playheadSeconds: Double = 0
    @State private var isPreparing = false
    @State private var playbackError = ""
    @State private var selectedRegionId: String?
    @State private var draftGain: Double?
    @State private var isLoopEnabled = ShotPlayerTransportPreference.loopEnabled
    @State private var transportStatus = ""
    @State private var isScrubbing = false
    @State private var wasPlayingBeforeScrub = false
    @State private var isExporting = false
    @State private var exportStatus = ""
    @State private var isKeymapOpen = false
    /// The composition key the current player was built from. Guarding on it
    /// is what makes the FIRST build happen when the bake cache is already
    /// warm — `onChange(of: rebuildKey)` alone never fires on open, because
    /// a fully-cached reel's key never changes.
    @State private var lastBuiltKey = ""

    // MARK: Derived reel state (live document each body pass)

    private var finals: [StageFinalsEntry] { library.outputFinals }

    private var cutNames: [String: String] {
        var names: [String: String] = [:]
        for entry in finals {
            if let shot = library.shotTimeline.shots.first(where: { $0.shotId == entry.cutId }) {
                names[entry.cutId] = shot.name.trimmed.nilIfEmpty ?? "Untitled cut"
            }
        }
        return names
    }

    /// The bakes that are READY, in finals order — what the reel plays now.
    private var readyClips: [ReelBakedClip] {
        finals.compactMap { entry in
            guard case .ready(let url, let duration) = library.reelBakeStates[entry.cutId] else {
                return nil
            }
            return ReelBakedClip(
                entryId: entry.entryId,
                cutId: entry.cutId,
                url: url,
                durationSeconds: duration
            )
        }
    }

    private var plan: ReelCompositionPlan {
        buildReelCompositionPlan(
            clips: readyClips,
            seams: reelActiveSeams(finals: finals, seams: library.outputSequence.reelSeams),
            fadeInFrames: library.outputSequence.reelFadeInFrames,
            fadeOutFrames: library.outputSequence.reelFadeOutFrames,
            fps: Double(reelOutputProfile.fps)
        )
    }

    private var reelDurationSeconds: Double { plan.totalSeconds }

    private var musicRegions: [ShotAudioRegion] { library.outputSequence.reelAudio }

    private var hasBakesInFlight: Bool {
        library.reelBakeStates.values.contains { state in
            if case .queued = state { return true }
            if case .baking = state { return true }
            return false
        }
    }

    /// A change here reassembles the player in place (position held).
    private var rebuildKey: String {
        let clipKey = readyClips.map { "\($0.entryId):\($0.url.lastPathComponent)" }.joined(separator: "|")
        let seamKey = plan.appliedCrossfadeFrames.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ",")
            + "|kinds=" + library.outputSequence.reelSeams
                .map { "\($0.id):\($0.kind.rawValue)" }.sorted().joined(separator: ",")
            + "|fades=\(plan.fadeInFrames):\(plan.fadeOutFrames)"
        let musicKey = musicRegions.map {
            "\($0.regionId):\($0.path):\($0.startSeconds):\($0.sourceStartSeconds):\($0.durationSeconds):\($0.gain):\($0.isMuted):\($0.loops):\($0.playbackRate):\($0.pitchMode.rawValue)"
        }.joined(separator: "|")
        return "\(clipKey)#seams=\(seamKey)#music=\(musicKey)"
    }

    /// Boundary displays between READY clips. Only pairs that are adjacent in
    /// the FINALS order are editable — a boundary that exists because a
    /// skipped cut sits between two picks refuses authoring honestly.
    private var seamDisplays: [ReelSeamDisplay] {
        guard readyClips.count > 1 else { return [] }
        let adjacentPairs = Set(zip(finals.dropLast(), finals.dropFirst()).map {
            "\($0.entryId)>\($1.entryId)"
        })
        return (0..<(readyClips.count - 1)).map { index in
            let left = readyClips[index].entryId
            let right = readyClips[index + 1].entryId
            let pairId = "\(left)>\(right)"
            let authored = library.outputSequence.reelSeams.first {
                $0.leftEntryId == left && $0.rightEntryId == right
            }
            return ReelSeamDisplay(
                leftEntryId: left,
                rightEntryId: right,
                requestedFrames: authored?.crossfadeFrames,
                appliedFrames: plan.appliedCrossfadeFrames[pairId] ?? 0,
                kind: authored?.kind ?? .crossfade,
                isEditable: adjacentPairs.contains(pairId)
            )
        }
    }

    private var selectedRegion: ShotAudioRegion? {
        guard let selectedRegionId else { return nil }
        return musicRegions.first { $0.regionId == selectedRegionId }
    }

    private var musicWaveformRegions: [ShotAudioWaveformRegion] {
        musicRegions.map { region in
            ShotAudioWaveformRegion(
                id: region.regionId,
                path: region.path,
                startSeconds: region.startSeconds,
                durationSeconds: region.durationSeconds,
                sourceRanges: region.loops ? [] : [ShotKeepRange(
                    start: region.sourceStartSeconds,
                    end: region.sourceStartSeconds + region.durationSeconds * region.playbackRate
                )],
                regionId: region.regionId,
                loops: region.loops,
                sourceStartSeconds: region.sourceStartSeconds,
                loopPhaseSeconds: region.loopPhaseSeconds,
                playbackRate: region.playbackRate,
                sourceDurationSeconds: region.sourceDurationSeconds,
                isMissingFile: !FileManager.default.fileExists(atPath: region.path),
                isMuted: region.isMuted
            )
        }
    }

    private var musicSnapTargets: [Double] {
        var targets: [Double] = [0, reelDurationSeconds]
        for band in plan.cutBands {
            targets.append(band.startSeconds)
        }
        for region in musicRegions {
            targets.append(region.startSeconds)
            targets.append(region.endSeconds)
        }
        return targets
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            playerSurface
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                FinalsReelBakeBoard(
                    finals: finals,
                    states: library.reelBakeStates,
                    cutNames: cutNames,
                    onRetry: {
                        Task {
                            await library.ensureReelBakes()
                            rebuildPlayerIfNeeded(resume: true)
                        }
                    }
                )
                FinalsReelCutStrip(
                    bands: plan.cutBands,
                    totalSeconds: reelDurationSeconds,
                    playheadSeconds: playheadSeconds,
                    seams: seamDisplays,
                    cutNames: cutNames,
                    onSeek: { seek(toSeconds: $0) },
                    onSetSeam: { left, right, kind, frames in
                        commitSeam(left: left, right: right, kind: kind, frames: frames)
                    }
                )
                ShotTimelineRulerRow(
                    durationSeconds: reelDurationSeconds,
                    playheadSeconds: playheadSeconds,
                    onSeek: { seek(toSeconds: $0) },
                    onScrubBegan: scrubBegan,
                    onScrubEnded: scrubEnded,
                    onJump: { jumpTo(seconds: $0) }
                )
                musicLane
                musicInspector
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            footer
        }
        // macOS sheets size to ideal content and happily overflow the
        // window (the shot modal's own lesson) — cap to the visible screen.
        .frame(
            minWidth: 900,
            minHeight: 560,
            maxHeight: max((NSScreen.main?.visibleFrame.height ?? 1000) - 72, 560)
        )
        .background(PlateColor.cream)
        .plateEngravedBorder(cornerRadius: 0, inset: 6)
        .modifier(transportKeys)
        .background(
            Button("", action: onClose)
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        )
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $isKeymapOpen) {
            ShotTransportCheatSheet(onClose: { isKeymapOpen = false })
        }
        .onAppear {
            reelUndo.applyState = { snapshot in library.restoreReelState(snapshot) }
        }
        .task {
            await library.ensureReelBakes()
            rebuildPlayerIfNeeded(resume: false)
        }
        .onChange(of: rebuildKey) { _, _ in
            rebuildPlayerIfNeeded(resume: true)
        }
        .onDisappear {
            library.cancelReelBakes()
            undoManager?.removeAllActions(withTarget: reelUndo)
            reelUndo.applyState = nil
            teardownPlayer()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            PlateLabel(text: "FINALS REEL", size: 11, weight: .bold, color: PlateColor.ink)
            PlateLabel(
                text: "\(readyClips.count) of \(finals.count) cuts · \(ShotAudioTiming.timecode(reelDurationSeconds))",
                size: 9,
                color: PlateColor.inkFaint
            )
            Spacer(minLength: 0)
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .help("Close the reel (⎋)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var playerSurface: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
            }
            if isPreparing {
                ProgressView().controlSize(.small)
            }
            if readyClips.isEmpty && !isPreparing {
                PlateLabel(
                    text: finals.isEmpty
                        ? "Drag cuts onto the FINALS shelf, then play the reel"
                        : (hasBakesInFlight
                            ? "Baking the picked cuts — the reel starts as soon as one is ready"
                            : "Nothing playable yet — render the picked cuts, or check the board below"),
                    size: 9,
                    color: Color.white.opacity(0.7)
                )
            }
            if !playbackError.isEmpty {
                PlateLabel(text: playbackError, size: 9, color: CanonColor.rust)
                    .padding(8)
                    .background(PlateColor.cream.opacity(0.9))
            }
        }
        .frame(minHeight: 320, maxHeight: .infinity)
    }

    private var musicLane: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                PlateLabel(text: "MUSIC", size: 7.5, weight: .semibold, color: PlateColor.ink)
                PlateLabel(
                    text: musicRegions.isEmpty ? "NO MUSIC" : "\(musicRegions.count) TRACK\(musicRegions.count == 1 ? "" : "S")",
                    size: 6.5,
                    color: PlateColor.inkFaint
                )
            }
            .frame(width: ShotTimelineAxis.headWidth, alignment: .leading)
            .help("The reel's one music bed — it plays straight across cut boundaries. Drag audio from Voice & Audio or Finder onto the lane.")

            ShotTimelineWaveformView(
                regions: musicWaveformRegions,
                durationSeconds: max(reelDurationSeconds, 0.001),
                playheadSeconds: playheadSeconds,
                isEnabled: true,
                isInteractionEnabled: true,
                selectedRegionId: selectedRegionId,
                snapTargets: musicSnapTargets,
                acceptsAudioDrop: true,
                onSeek: { seek(toSeconds: $0) },
                onSelectRegion: { selectedRegionId = $0 },
                onGestureBegan: { player?.pause() },
                onScrubBegan: scrubBegan,
                onScrubEnded: scrubEnded,
                onMoveCommitted: { regionId, start in
                    register(library.moveReelAudioRegion(
                        regionId: regionId,
                        startSeconds: start,
                        reelDurationSeconds: reelDurationSeconds
                    ), "Move Reel Music")
                },
                onTrimCommitted: { regionId, start, sourceStart, duration in
                    register(library.setReelAudioRegionGeometry(
                        regionId: regionId,
                        startSeconds: start,
                        sourceStartSeconds: sourceStart,
                        durationSeconds: duration,
                        reelDurationSeconds: reelDurationSeconds
                    ), "Trim Reel Music")
                },
                onNudgeSelected: { frames in nudgeSelected(by: frames) },
                onTrimSelectedToPlayhead: { isIn in trimSelectedMusicToPlayhead(inEdge: isIn) },
                onToggleLoopSelected: { toggleSelectedLoop() },
                onToggleMuteSelected: { toggleSelectedMute() },
                onDeleteSelected: { deleteSelected() },
                onAudioDrop: { payload, seconds in handleDrop(payload: payload, seconds: seconds) }
            )

            Color.clear.frame(width: ShotTimelineAxis.tailWidth)
        }
        .frame(height: ShotTimelineAxis.laneHeight)
    }

    @ViewBuilder
    private var musicInspector: some View {
        if let region = selectedRegion {
            HStack(spacing: 8) {
                PlateLabel(
                    text: (region.label.trimmed.nilIfEmpty ?? "Track").uppercased(),
                    size: 7.5,
                    weight: .semibold,
                    color: PlateColor.ink
                )
                .lineLimit(1)
                .frame(width: ShotTimelineAxis.headWidth - 8, alignment: .leading)
                ShotTimecodeField(
                    label: "START",
                    seconds: region.startSeconds,
                    isEnabled: true
                ) { parsed in
                    player?.pause()
                    register(library.moveReelAudioRegion(
                        regionId: region.regionId,
                        startSeconds: max(parsed, 0),
                        reelDurationSeconds: reelDurationSeconds
                    ), "Move Reel Music")
                }
                Button {
                    player?.pause()
                    var updated = region
                    updated.loops.toggle()
                    register(library.updateReelAudioRegion(updated), updated.loops ? "Loop Reel Music" : "Unloop Reel Music")
                } label: {
                    PlateLabel(
                        text: "LOOP",
                        size: 6.5,
                        weight: .bold,
                        color: region.loops ? PlateColor.cream : PlateColor.inkFaint
                    )
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(region.loops ? CanonColor.brass : PlateColor.creamDeep))
                    .overlay(Capsule().stroke(region.loops ? CanonColor.brass : PlateColor.hairline, lineWidth: 0.7))
                }
                .help(region.loops ? "Looping — tiles to fill its length (L)" : "Plays once (L)")
                Button {
                    toggleSelectedMute()
                } label: {
                    Image(systemName: region.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .help(region.isMuted ? "Unmute (M)" : "Mute (M)")
                Button(role: .destructive) {
                    deleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Remove from the reel (⌫) — ⌘Z restores")
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Image(systemName: "speaker.wave.1")
                        .font(.system(size: 9))
                        .foregroundStyle(PlateColor.inkFaint)
                    Slider(
                        value: Binding(
                            get: { draftGain ?? region.gain },
                            set: { draftGain = $0 }
                        ),
                        in: 0...1
                    ) { editing in
                        if !editing, let gain = draftGain {
                            var updated = region
                            updated.gain = gain
                            register(library.updateReelAudioRegion(updated), "Adjust Reel Music Gain")
                            draftGain = nil
                        }
                    }
                    .controlSize(.mini)
                    .frame(width: 74)
                    .help("Music gain: \(Int((draftGain ?? region.gain) * 100))%")
                }
                .frame(width: ShotTimelineAxis.tailWidth, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .font(.system(size: 9, weight: .semibold))
            .frame(height: ShotTimelineAxis.inspectorHeight)
            .padding(.horizontal, 6)
            .background(PlateColor.creamDeep.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            HStack {
                PlateLabel(
                    text: "Select a music region — or drop audio on the lane. Seam glyphs on the strip set crossfades and dips; FADE IN/OUT live in the footer.",
                    size: 7,
                    color: PlateColor.inkFaint
                )
                Spacer(minLength: 0)
            }
            .frame(height: ShotTimelineAxis.inspectorHeight)
            .padding(.horizontal, 6)
            .background(PlateColor.creamDeep.opacity(0.24))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            loopToggleButton
            fadeMenu(label: "FADE IN", current: library.outputSequence.reelFadeInFrames, isHead: true)
            fadeMenu(label: "FADE OUT", current: library.outputSequence.reelFadeOutFrames, isHead: false)
            if !transportStatus.isEmpty {
                PlateLabel(text: transportStatus, size: 8, color: PlateColor.inkFaint)
                    .lineLimit(1)
            }
            if !exportStatus.isEmpty {
                PlateLabel(text: exportStatus, size: 8, color: PlateColor.inkFaint)
                    .lineLimit(1)
            }
            if !library.youtubeExportStatus.isEmpty {
                PlateLabel(text: library.youtubeExportStatus, size: 8, color: PlateColor.inkFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                isKeymapOpen = true
            } label: {
                PlateLabel(text: "KEYS ?", size: 8, weight: .bold, color: PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .help("Keyboard reference (?)")
            Button(library.isExportingForYouTube ? "Exporting for YouTube…" : "Export for YouTube") {
                exportForYouTube()
            }
            .buttonStyle(PlateButtonStyle())
            .disabled(isExporting || library.isExportingForYouTube || readyClips.isEmpty)
            .help(readyClips.count < finals.count
                ? "Writes the reel exactly as the preview plays (\(finals.count - readyClips.count) picked cut\(finals.count - readyClips.count == 1 ? " is" : "s are") not in it) plus a YouTube title + description into ~/Downloads/LitScenes-Finals"
                : "One click: the reel .mp4 plus a YouTube title + description .md land in ~/Downloads/LitScenes-Finals")
            Button(isExporting
                ? "Exporting…"
                : (readyClips.count < finals.count ? "Export Partial Reel…" : "Export Reel…")) {
                exportReel()
            }
            .buttonStyle(PlateButtonStyle(isProminent: true))
            .disabled(isExporting || library.isExportingForYouTube || readyClips.isEmpty)
            .help(readyClips.count < finals.count
                ? "Exports exactly what the preview plays — \(finals.count - readyClips.count) picked cut\(finals.count - readyClips.count == 1 ? " is" : "s are") not in it (see the board)"
                : "Export exactly what the preview plays — one 16:9 mp4, no re-encode of the cuts")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// FADE IN / FADE OUT presets — a one-time reel setting, so it lives on
    /// the finished-film surface only (the sequence row does not carry it).
    /// The music bed ramps with the picture through the same plan.
    private func fadeMenu(label: String, current: Int, isHead: Bool) -> some View {
        Menu {
            Button("\(current == 0 ? "✓ " : "")Off") { setFade(isHead: isHead, frames: 0) }
            ForEach(reelSeamPresetFrames, id: \.self) { frames in
                Button("\(current == frames ? "✓ " : "")\(frames)f · \(String(format: "%.2f", Double(frames) / Double(reelOutputProfile.fps)))s") {
                    setFade(isHead: isHead, frames: frames)
                }
            }
        } label: {
            PlateLabel(
                text: current > 0 ? "\(label) \(current)f" : label,
                size: 8,
                weight: .bold,
                color: current > 0 ? CanonColor.brass : PlateColor.inkFaint
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(isHead
            ? "Fade the film in from black — the music bed rises with it"
            : "Fade the film out to black — the music bed falls with it")
    }

    private func setFade(isHead: Bool, frames: Int) {
        player?.pause()
        let doc = library.outputSequence
        register(
            library.setReelFades(
                fadeInFrames: isHead ? frames : doc.reelFadeInFrames,
                fadeOutFrames: isHead ? doc.reelFadeOutFrames : frames
            ),
            isHead ? "Set Reel Fade In" : "Set Reel Fade Out"
        )
    }

    private var loopToggleButton: some View {
        Button {
            isLoopEnabled.toggle()
            ShotPlayerTransportPreference.loopEnabled = isLoopEnabled
            transportStatus = isLoopEnabled ? "Loop on" : "Loop off — playback rests at the end"
        } label: {
            PlateLabel(
                text: "LOOP",
                size: 8,
                weight: .bold,
                color: isLoopEnabled ? CanonColor.brass : PlateColor.inkFaint
            )
        }
        .buttonStyle(.plain)
        .help(isLoopEnabled ? "Looping (⌥L)" : "Loop off (⌥L)")
    }

    // MARK: Transport (the shot player's laws, reel-scoped)

    private var transportKeys: ShotPlayerTransportKeys {
        ShotPlayerTransportKeys(
            isEnabled: true,
            onTogglePlayback: togglePlayback,
            onPause: pausePlaybackResolvingPlayhead,
            onShuttleForward: shuttleForward,
            onShuttleReverse: shuttleReverse,
            onFrameStep: { stepFrames($0) },
            onJumpToStart: { jumpTo(seconds: 0) },
            onJumpToEnd: { jumpTo(seconds: reelDurationSeconds) },
            onToggleLoop: {
                isLoopEnabled.toggle()
                ShotPlayerTransportPreference.loopEnabled = isLoopEnabled
            },
            onEscapeLadder: {
                if selectedRegionId != nil {
                    selectedRegionId = nil
                    return true
                }
                return false
            },
            onShowKeymap: { isKeymapOpen = true }
        )
    }

    private func currentPlayheadSeconds() -> Double {
        guard let time = player?.currentTime(), time.isValid, time.seconds.isFinite else {
            return playheadSeconds
        }
        let ceiling = reelDurationSeconds > 0 ? reelDurationSeconds : time.seconds
        return min(max(time.seconds, 0), ceiling)
    }

    private func pausePlaybackResolvingPlayhead() {
        player?.pause()
        playheadSeconds = currentPlayheadSeconds()
        // A paused player showing "▶ 2×" would be lying.
        transportStatus = ""
    }

    private func togglePlayback() {
        guard let player, !isPreparing else { return }
        if player.rate != 0 {
            pausePlaybackResolvingPlayhead()
            return
        }
        if !isLoopEnabled,
           reelDurationSeconds > 0,
           currentPlayheadSeconds() >= reelDurationSeconds - ShotAudioTiming.frameSeconds / 2 {
            seek(toSeconds: 0)
        }
        transportStatus = ""
        player.play()
    }

    private func shuttleForward() {
        guard let player, !isPreparing else { return }
        let canFast = player.currentItem?.canPlayFastForward ?? false
        let cap: Float = canFast ? 4 : 2
        let next = ShotTransportMath.nextForwardRate(current: player.rate, cap: cap)
        transportStatus = !canFast && next >= cap ? "This preview caps forward shuttle at 2×" : "▶ \(Int(next))×"
        player.rate = next
    }

    private func shuttleReverse() {
        guard let player, !isPreparing else { return }
        if player.currentItem?.canPlayReverse == true {
            let next = ShotTransportMath.nextReverseRate(current: player.rate)
            transportStatus = "◀ \(Int(-next))×"
            player.rate = next
            return
        }
        pausePlaybackResolvingPlayhead()
        seek(toSeconds: max(currentPlayheadSeconds() - 1, 0))
        transportStatus = "Reverse shuttle unavailable for this preview — J steps back 1s"
    }

    private func stepFrames(_ frames: Int) {
        guard player != nil, !isPreparing else { return }
        pausePlaybackResolvingPlayhead()
        transportStatus = ""
        seek(toSeconds: ShotTransportMath.frameStepped(
            currentPlayheadSeconds(),
            frames: frames,
            durationSeconds: reelDurationSeconds
        ))
    }

    private func jumpTo(seconds: Double) {
        guard player != nil, !isPreparing else { return }
        pausePlaybackResolvingPlayhead()
        transportStatus = ""
        let ceiling = reelDurationSeconds > 0 ? reelDurationSeconds : max(seconds, 0)
        seek(toSeconds: ShotAudioTiming.frameQuantizedStart(min(max(seconds, 0), ceiling)))
    }

    private func scrubBegan() {
        guard !isScrubbing else { return }
        isScrubbing = true
        wasPlayingBeforeScrub = (player?.rate ?? 0) != 0
        player?.pause()
    }

    private func scrubEnded() {
        guard isScrubbing else { return }
        isScrubbing = false
        if wasPlayingBeforeScrub { player?.play() }
        wasPlayingBeforeScrub = false
    }

    private func seek(toSeconds seconds: Double) {
        playheadSeconds = seconds
        player?.seek(
            to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    // MARK: Commits (one gesture = one transaction = one Undo action)

    private func register(_ snapshot: ReelStateSnapshot?, _ actionName: String) {
        guard let snapshot else { return }
        let new = ReelStateSnapshot(
            reelAudio: library.outputSequence.reelAudio,
            reelSeams: library.outputSequence.reelSeams,
            reelFadeInFrames: library.outputSequence.reelFadeInFrames,
            reelFadeOutFrames: library.outputSequence.reelFadeOutFrames
        )
        reelUndo.registerEdit(old: snapshot, new: new, actionName: actionName, undoManager: undoManager)
    }

    private func commitSeam(left: String, right: String, kind: ReelSeamKind, frames: Int?) {
        player?.pause()
        register(
            library.setReelSeam(leftEntryId: left, rightEntryId: right, kind: kind, crossfadeFrames: frames),
            reelSeamUndoActionName(kind: kind, frames: frames)
        )
    }

    private func trimSelectedMusicToPlayhead(inEdge: Bool) {
        guard let region = selectedRegion else { return }
        player?.pause()
        let playhead = ShotAudioTiming.frameQuantizedStart(currentPlayheadSeconds())
        if inEdge {
            guard playhead < region.endSeconds - ShotAudioTiming.frameSeconds / 2 else { return }
            let delta = playhead - region.startSeconds
            register(library.setReelAudioRegionGeometry(
                regionId: region.regionId,
                startSeconds: playhead,
                sourceStartSeconds: region.loops
                    ? region.sourceStartSeconds
                    : region.sourceStartSeconds + delta * region.playbackRate,
                durationSeconds: region.durationSeconds - delta,
                reelDurationSeconds: reelDurationSeconds
            ), "Trim Reel Music")
        } else {
            guard playhead > region.startSeconds + ShotAudioTiming.frameSeconds / 2 else { return }
            register(library.setReelAudioRegionGeometry(
                regionId: region.regionId,
                startSeconds: region.startSeconds,
                sourceStartSeconds: region.sourceStartSeconds,
                durationSeconds: playhead - region.startSeconds,
                reelDurationSeconds: reelDurationSeconds
            ), "Trim Reel Music")
        }
    }

    private func nudgeSelected(by frames: Int) {
        guard let region = selectedRegion else { return }
        player?.pause()
        let moved = ShotAudioTiming.nudgedStart(
            region.startSeconds,
            frames: frames,
            timelineDuration: reelDurationSeconds
        )
        register(library.moveReelAudioRegion(
            regionId: region.regionId,
            startSeconds: moved,
            reelDurationSeconds: reelDurationSeconds
        ), "Move Reel Music")
    }

    private func toggleSelectedLoop() {
        guard let region = selectedRegion else { return }
        player?.pause()
        var updated = region
        updated.loops.toggle()
        register(library.updateReelAudioRegion(updated), updated.loops ? "Loop Reel Music" : "Unloop Reel Music")
    }

    private func toggleSelectedMute() {
        guard let region = selectedRegion else { return }
        var updated = region
        updated.isMuted.toggle()
        register(library.updateReelAudioRegion(updated), updated.isMuted ? "Mute Reel Music" : "Unmute Reel Music")
    }

    private func deleteSelected() {
        guard let region = selectedRegion else { return }
        player?.pause()
        register(library.deleteReelAudioRegion(regionId: region.regionId), "Delete Reel Music")
        if selectedRegionId == region.regionId { selectedRegionId = nil }
    }

    private func handleDrop(payload: ShotAudioLaneDropPayload, seconds: Double) {
        var cursor = seconds
        for mediaId in payload.mediaIds {
            cursor = addMusic(.projectAudio(mediaId: mediaId), at: cursor)
        }
        let audioURLs = payload.fileURLs.filter { url in
            UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) == true
        }
        guard !audioURLs.isEmpty else { return }
        Task {
            let items = await library.importAudioMediaFiles(audioURLs)
            var position = cursor
            for item in items {
                position = addMusic(.projectAudio(mediaId: item.mediaId), at: position)
            }
        }
    }

    private func addMusic(_ asset: ShotAudioAssetReference, at seconds: Double) -> Double {
        let snapshot = library.addReelAudioRegion(
            asset: asset,
            startSeconds: seconds,
            reelDurationSeconds: reelDurationSeconds
        )
        register(snapshot, "Add Reel Music")
        guard snapshot != nil, let added = library.outputSequence.reelAudio.last else { return seconds }
        selectedRegionId = added.regionId
        return added.endSeconds
    }

    // MARK: Player lifecycle

    /// One build per composition identity: the warm-cache open (key already
    /// final) builds here from `.task`, and every later change builds from
    /// `onChange` — never both.
    private func rebuildPlayerIfNeeded(resume: Bool) {
        guard rebuildKey != lastBuiltKey || player == nil else { return }
        lastBuiltKey = rebuildKey
        preparePlayer(resume: resume)
    }

    private func preparePlayer(resume: Bool) {
        guard !readyClips.isEmpty else {
            teardownPlayer()
            return
        }
        playerLoadToken += 1
        let token = playerLoadToken
        isPreparing = true
        playbackError = ""
        let planSnapshot = plan
        let music = musicRegions
        Task { @MainActor in
            do {
                let result = try await FinalsReelComposer.buildReelComposition(
                    plan: planSnapshot,
                    musicRegions: music,
                    profile: reelOutputProfile
                )
                guard token == playerLoadToken else { return }
                let item = AVPlayerItem(asset: result.composition)
                item.videoComposition = result.videoComposition
                item.audioMix = result.audioMix
                item.forwardPlaybackEndTime = CMTime(
                    seconds: result.durationSeconds,
                    preferredTimescale: 600
                )
                let resumeSeconds = resume ? min(playheadSeconds, result.durationSeconds) : 0
                // A rebuild while paused stays paused — an edit must never
                // force playback. The first build autoplays (house behavior).
                let wasPlaying = player == nil || (player?.rate ?? 0) != 0
                teardownPlayer()
                let newPlayer = AVPlayer(playerItem: item)
                loopObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { _ in
                    Task { @MainActor in
                        // Live preference: this closure outlives toggles.
                        if ShotPlayerTransportPreference.loopEnabled {
                            newPlayer.seek(to: .zero)
                            newPlayer.play()
                        } else {
                            newPlayer.pause()
                        }
                    }
                }
                timeObserverToken = newPlayer.addPeriodicTimeObserver(
                    forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
                    queue: .main
                ) { time in
                    Task { @MainActor in
                        playheadSeconds = max(time.seconds, 0)
                    }
                }
                player = newPlayer
                if resumeSeconds > 0 {
                    await newPlayer.seek(
                        to: CMTime(seconds: resumeSeconds, preferredTimescale: 600),
                        toleranceBefore: .zero,
                        toleranceAfter: .zero
                    )
                    playheadSeconds = resumeSeconds
                }
                isPreparing = false
                if wasPlaying { newPlayer.play() }
            } catch {
                guard token == playerLoadToken else { return }
                isPreparing = false
                playbackError = String(error.localizedDescription.prefix(260))
            }
        }
    }

    private func teardownPlayer() {
        if let timeObserverToken, let player {
            player.removeTimeObserver(timeObserverToken)
        }
        timeObserverToken = nil
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    // MARK: Export (the same composition the preview plays)

    /// No panel, no dialog: the engine writes the reel + its YouTube markdown
    /// straight into ~/Downloads/LitScenes-Finals and reveals the pair. The
    /// engine owns the Task so the export survives this sheet closing.
    private func exportForYouTube() {
        let planSnapshot = plan
        let music = musicRegions
        Task { await library.exportFinalsReelForYouTube(plan: planSnapshot, musicRegions: music) }
    }

    private func exportReel() {
        let panel = NSSavePanel()
        panel.title = "Export Finals Reel"
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Finals Reel.mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExporting = true
        exportStatus = "Exporting…"
        let planSnapshot = plan
        let music = musicRegions
        Task { @MainActor in
            do {
                let result = try await FinalsReelComposer.buildReelComposition(
                    plan: planSnapshot,
                    musicRegions: music,
                    profile: reelOutputProfile
                )
                guard let session = AVAssetExportSession(
                    asset: result.composition,
                    presetName: AVAssetExportPresetHighestQuality
                ) else {
                    throw ScreenGraphError.capture("The reel export could not start.")
                }
                session.videoComposition = result.videoComposition
                session.audioMix = result.audioMix
                session.timeRange = CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: result.durationSeconds, preferredTimescale: 600)
                )
                try? FileManager.default.removeItem(at: url)
                try await MediaExportGuard.export(session, to: url, as: .mp4, operation: "reel export")
                exportStatus = "Exported \(url.lastPathComponent)"
            } catch {
                exportStatus = "Export failed: \(String(error.localizedDescription.prefix(160)))"
            }
            isExporting = false
        }
    }
}
