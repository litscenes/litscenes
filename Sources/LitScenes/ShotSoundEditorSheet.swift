import AVFoundation
import SwiftUI

/// Opens the sound editor as a nested sheet of the shot player modal
/// (the Ambient Tuner presentation precedent). The optional reveal range
/// carries the selected region's output span so the editor opens framed
/// on it; the id is fixed because at most one editor exists per modal.
struct ShotSoundEditorRequest: Identifiable, Hashable {
    var revealStartSeconds: Double?
    var revealEndSeconds: Double?
    var id: String { "sound-editor" }
}

/// THE SOUND EDITOR: the same lane stack the modal shows inline, enlarged to
/// `.editor` metrics on a near-fullscreen plate — every gesture, commit, and
/// undo law is the stack's own, so nothing here re-implements editing.
///
/// The editor drives the SAME AVPlayer as the modal through the pass-through
/// closures — deliberately unlike the Ambient Tuner, which pauses the player
/// because it auditions its own synth. Playback keeps running across open
/// and close; the picture strip is a second AVPlayerLayer on that player, so
/// sound is edited against picture without a second clock.
struct ShotSoundEditorSheet: View {
    let shotOrdinal: Int
    let request: ShotSoundEditorRequest
    let durationSeconds: Double
    /// Live from the modal's 0.1s time observer; commits resolve the exact
    /// clock through `resolvePlayheadSeconds` (the playhead truth law).
    let playheadSeconds: Double
    /// For the picture strip only — transport goes through the closures.
    let player: AVPlayer?
    let initialViewport: ShotTimelineViewport
    let isLoopEnabled: Bool
    /// False while the microphone owns the player (a take in progress).
    let isTransportEnabled: Bool
    let transportStatus: String
    /// Merged output spans of the shot's regions, for the minimap.
    let regionSpans: [ClosedRange<Double>]
    var buildLaneStack: () -> ShotAudioLaneStack
    var resolvePlayheadSeconds: () -> Double
    var onTogglePlayback: () -> Void
    var onPause: () -> Void
    var onShuttleForward: () -> Void
    var onShuttleReverse: () -> Void
    var onFrameStep: (Int) -> Void
    var onJumpTo: (Double) -> Void
    var onToggleLoop: () -> Void
    var onClose: () -> Void

    /// The editor's OWN window (THE WINDOW COROLLARY) — zooming here never
    /// moves the modal's inline viewport, and vice versa.
    @State private var viewport = ShotTimelineViewport.fit
    @State private var laneWidth: CGFloat = 1400
    @State private var isKeymapOpen = false
    /// The editor's own refusals (B/I/O belong to the strip, not here).
    @State private var editorStatus = ""

    private var sheetWidth: CGFloat {
        max((NSScreen.main?.visibleFrame.width ?? 1440) - 96, 1040)
    }

    private var sheetHeight: CGFloat {
        max((NSScreen.main?.visibleFrame.height ?? 1000) - 72, 620)
    }

    private var timeAreaWidth: CGFloat {
        max(laneWidth - ShotTimelineAxis.headWidth - ShotTimelineAxis.tailWidth, 1)
    }

    private var editorMaxZoom: CGFloat {
        ShotTimelineViewport.maxZoom(
            durationSeconds: durationSeconds,
            contentWidth: ShotTimelineAxis.contentWidth(laneWidth: timeAreaWidth)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            consoleBand
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            laneArea
                .frame(maxHeight: .infinity)
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            minimapRow
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            footer
        }
        .frame(width: sheetWidth, height: sheetHeight)
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
        .background(zoomShortcutButtons)
        .environment(\.colorScheme, .light)
        .sheet(isPresented: $isKeymapOpen) {
            ShotTransportCheatSheet(onClose: { isKeymapOpen = false })
        }
        .onAppear { seedViewport() }
        .onChange(of: playheadSeconds) { previous, current in
            // THE FOLLOW LAW, on the editor's own window.
            viewport = viewport.following(
                previous: previous,
                current: current,
                durationSeconds: durationSeconds
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            PlateLabel(text: "SOUND EDITOR", size: 11, weight: .bold)
            PlateLabel(text: "SHOT \(shotOrdinal)", size: 8, color: PlateColor.inkFaint)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .help("Close the sound editor (⎋)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: Console (picture strip + transport + zoom)

    private var consoleBand: some View {
        HStack(spacing: 14) {
            ShotEditorPictureStrip(player: player)
                .frame(width: 256, height: 144)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Rectangle().fill(PlateColor.hairlineFaint).frame(width: 1, height: 120)
            VStack(alignment: .leading, spacing: 10) {
                transportCluster
                HStack(spacing: 12) {
                    zoomCluster
                    Button {
                        isKeymapOpen = true
                    } label: {
                        PlateLabel(text: "KEYS ?", size: 8, color: PlateColor.inkFaint)
                    }
                    .buttonStyle(.plain)
                    .help("Keyboard reference (?)")
                }
                statusLine
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var transportCluster: some View {
        HStack(spacing: 10) {
            Button(action: onTogglePlayback) {
                Image(systemName: "playpause.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(PlateColor.ink)
            }
            .buttonStyle(.plain)
            .disabled(!isTransportEnabled)
            .help("Play / pause (Space)")
            Button { onFrameStep(-1) } label: {
                Image(systemName: "backward.frame")
                    .font(.system(size: 11))
                    .foregroundStyle(PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .disabled(!isTransportEnabled)
            .help("Step one frame back (,)")
            Button { onFrameStep(1) } label: {
                Image(systemName: "forward.frame")
                    .font(.system(size: 11))
                    .foregroundStyle(PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .disabled(!isTransportEnabled)
            .help("Step one frame forward (.)")
            Button(action: onToggleLoop) {
                Image(systemName: "repeat")
                    .font(.system(size: 11))
                    .foregroundStyle(isLoopEnabled ? CanonColor.brass : PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .help("Loop playback (⌥L)")
            HStack(spacing: 4) {
                ShotTimecodeField(
                    label: "",
                    seconds: ShotAudioTiming.frameQuantizedStart(playheadSeconds),
                    isEnabled: isTransportEnabled,
                    onCommit: { onJumpTo($0) }
                )
                PlateLabel(
                    text: "/ \(durationSeconds > 0 ? ShotAudioTiming.timecode(durationSeconds) : "—")",
                    size: 7.5,
                    color: PlateColor.inkFaint
                )
            }
        }
    }

    private var zoomCluster: some View {
        HStack(spacing: 4) {
            Button { zoomEditor(byFactor: 0.5) } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundStyle(viewport.isFit ? PlateColor.inkFaint.opacity(0.4) : PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .disabled(viewport.isFit)
            .help("Zoom out (⌘−)")
            PlateLabel(
                text: viewport.isFit ? "FIT" : "\(Int(viewport.zoom))×",
                size: 8,
                weight: .bold,
                color: viewport.isFit ? PlateColor.inkFaint : CanonColor.brass
            )
            .frame(minWidth: 22)
            .help(viewport.isFit
                ? "The whole cut fits the timeline — zoom in, pinch, or two-finger scroll to pan (⌘+)"
                : "Timeline zoom — ⌘0 fits the whole cut again")
            Button { zoomEditor(byFactor: 2) } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundStyle(viewport.zoom >= editorMaxZoom
                        ? PlateColor.inkFaint.opacity(0.4)
                        : PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .disabled(viewport.zoom >= editorMaxZoom)
            .help("Zoom in around the playhead (⌘+)")
        }
    }

    private var statusLine: some View {
        PlateLabel(
            text: editorStatus.nilIfEmpty ?? transportStatus,
            size: 7.5,
            color: PlateColor.inkFaint
        )
        .lineLimit(1)
    }

    // MARK: Lanes

    private var laneArea: some View {
        ScrollView(.vertical) {
            buildLaneStack()
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { laneWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, width in
                                laneWidth = width
                            }
                    }
                )
                .overlay {
                    ShotTimelinePanZoomCatcher(
                        onPan: { points in
                            viewport = viewport.panned(
                                byPoints: points,
                                laneWidth: timeAreaWidth,
                                durationSeconds: durationSeconds
                            )
                        },
                        onMagnify: { factor, localX in
                            guard durationSeconds > 0 else { return }
                            let anchor = ShotTimelineAxis.seconds(
                                forX: localX - ShotTimelineAxis.headWidth,
                                durationSeconds: durationSeconds,
                                laneWidth: timeAreaWidth,
                                viewport: viewport
                            )
                            viewport = viewport.zoomed(
                                byFactor: factor,
                                anchorSeconds: anchor,
                                durationSeconds: durationSeconds,
                                maxZoom: editorMaxZoom
                            )
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .environment(\.shotTimelineViewport, viewport)
        .environment(\.shotTimelineMetrics, .editor)
    }

    private var minimapRow: some View {
        ShotSoundEditorMinimap(
            durationSeconds: durationSeconds,
            playheadSeconds: playheadSeconds,
            regionSpans: regionSpans,
            viewport: viewport,
            onCenter: { fraction in
                viewport = viewport.centered(atFraction: fraction)
            }
        )
        .frame(height: 18)
        .padding(.leading, 16 + ShotTimelineAxis.headWidth)
        .padding(.trailing, 16 + ShotTimelineAxis.tailWidth)
        .padding(.vertical, 3)
    }

    private var footer: some View {
        HStack {
            PlateLabel(
                text: "Pinch to zoom · two-finger scroll to pan · edits land instantly and ⌘Z undoes them",
                size: 7.5,
                color: PlateColor.inkFaint
            )
            Spacer()
            Button("DONE", action: onClose)
                .buttonStyle(PlateButtonStyle(isProminent: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: Behavior

    private var transportKeys: ShotPlayerTransportKeys {
        ShotPlayerTransportKeys(
            isEnabled: isTransportEnabled,
            onTogglePlayback: onTogglePlayback,
            onPause: onPause,
            onShuttleForward: onShuttleForward,
            onShuttleReverse: onShuttleReverse,
            onFrameStep: onFrameStep,
            onJumpToStart: { onJumpTo(0) },
            onJumpToEnd: { onJumpTo(durationSeconds) },
            onToggleLoop: onToggleLoop,
            onBlade: { editorStatus = "Picture edits live on the strip — close the editor to razor" },
            onSetInPoint: { _ in editorStatus = "Picture edits live on the strip — close the editor to set IN/OUT" },
            onSetOutPoint: { _ in editorStatus = "Picture edits live on the strip — close the editor to set IN/OUT" },
            onEscapeLadder: { false },
            onShowKeymap: { isKeymapOpen = true }
        )
    }

    private var zoomShortcutButtons: some View {
        Group {
            Button("") { zoomEditor(byFactor: 2) }
                .keyboardShortcut("=", modifiers: .command)
            Button("") { zoomEditor(byFactor: 0.5) }
                .keyboardShortcut("-", modifiers: .command)
            Button("") { viewport = .fit }
                .keyboardShortcut("0", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// Zoom anchored at the playhead when visible, else the window's center —
    /// the modal's own anchoring law, against the editor's viewport.
    private func zoomEditor(byFactor factor: CGFloat) {
        guard durationSeconds > 0 else { return }
        let window = viewport.window(durationSeconds: durationSeconds)
        let playhead = resolvePlayheadSeconds()
        let anchor = playhead >= window.start && playhead <= window.start + window.length
            ? playhead
            : window.start + window.length / 2
        viewport = viewport.zoomed(
            byFactor: factor,
            anchorSeconds: anchor,
            durationSeconds: durationSeconds,
            maxZoom: editorMaxZoom
        )
    }

    private func seedViewport() {
        if let start = request.revealStartSeconds,
           let end = request.revealEndSeconds {
            viewport = ShotTimelineViewport.framing(
                start: start,
                end: end,
                durationSeconds: durationSeconds,
                maxZoom: editorMaxZoom
            )
        } else {
            viewport = initialViewport.normalized()
        }
    }
}

/// A second `AVPlayerLayer` on the MODAL's player — multiple layers per
/// player is standard AVFoundation, and sharing the player is what keeps the
/// strip frame-locked to what the operator hears. (`ScrubVideoPreview` owns
/// its own player only because it plays a different file.)
struct ShotEditorPictureStrip: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> ScrubPlayerHostView {
        let view = ScrubPlayerHostView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: ScrubPlayerHostView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}

/// The whole-duration overview under the lanes: region extents as ink bands,
/// the window as a brass-stroked rect, the playhead as a brass tick. Click
/// or drag centers the window — at fit it is inert (nowhere to pan).
struct ShotSoundEditorMinimap: View {
    let durationSeconds: Double
    let playheadSeconds: Double
    let regionSpans: [ClosedRange<Double>]
    let viewport: ShotTimelineViewport
    var onCenter: (Double) -> Void

    var body: some View {
        // Captured as values: the Canvas closure is nonisolated.
        let spans = regionSpans
        let viewport = viewport
        let duration = durationSeconds
        let playhead = playheadSeconds
        GeometryReader { geometry in
            Canvas { context, size in
                guard duration > 0, size.width > 0 else { return }
                let width = size.width
                func x(_ seconds: Double) -> CGFloat {
                    CGFloat(min(max(seconds / duration, 0), 1)) * width
                }
                // Baseline.
                context.fill(
                    Path(CGRect(x: 0, y: size.height / 2 - 0.5, width: width, height: 1)),
                    with: .color(PlateColor.hairline)
                )
                // Region extents.
                for span in spans {
                    let startX = x(span.lowerBound)
                    let endX = x(span.upperBound)
                    context.fill(
                        Path(CGRect(
                            x: startX,
                            y: size.height / 2 - 2.5,
                            width: max(endX - startX, 1),
                            height: 5
                        )),
                        with: .color(PlateColor.ink.opacity(0.35))
                    )
                }
                // The visible window.
                let window = viewport.window(durationSeconds: duration)
                let windowRect = CGRect(
                    x: x(window.start),
                    y: 1,
                    width: max(x(window.start + window.length) - x(window.start), 3),
                    height: size.height - 2
                )
                context.stroke(
                    Path(roundedRect: windowRect, cornerRadius: 2),
                    with: .color(CanonColor.brass.opacity(viewport.isFit ? 0.35 : 0.9)),
                    lineWidth: 1
                )
                // The playhead.
                context.fill(
                    Path(CGRect(x: x(playhead) - 0.5, y: 0, width: 1, height: size.height)),
                    with: .color(CanonColor.brass)
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard geometry.size.width > 0 else { return }
                        onCenter(min(max(value.location.x / geometry.size.width, 0), 1))
                    }
            )
        }
        .accessibilityLabel("Timeline overview")
    }
}
