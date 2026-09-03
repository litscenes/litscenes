import SwiftUI

private struct ShotTimelineViewportKey: EnvironmentKey {
    static let defaultValue = ShotTimelineViewport.fit
}

extension EnvironmentValues {
    /// THE WINDOW COROLLARY's carrier: one viewport, set by the shot player
    /// modal, read by every time-mapped lane-stack row — so the visible
    /// window's edges land at the same absolute x on all of them.
    var shotTimelineViewport: ShotTimelineViewport {
        get { self[ShotTimelineViewportKey.self] }
        set { self[ShotTimelineViewportKey.self] = newValue }
    }
}

private struct ShotTimelineMetricsKey: EnvironmentKey {
    static let defaultValue = ShotTimelineMetrics.inline
}

extension EnvironmentValues {
    /// THE METRICS COROLLARY's carrier: the lane stack's vertical numbers.
    /// Defaults to `.inline` so every existing construction site keeps its
    /// historical geometry without naming metrics; the sound editor sheet
    /// sets `.editor` on its subtree.
    var shotTimelineMetrics: ShotTimelineMetrics {
        get { self[ShotTimelineMetricsKey.self] }
        set { self[ShotTimelineMetricsKey.self] = newValue }
    }
}

/// The brass cap both blocks wear at their playhead. Shared so the picture
/// strip's material-space playhead and the lanes' output-space playhead are
/// visibly the same instrument reading the same instant.
struct ShotTimelinePlayheadCap: View {
    var body: some View {
        Image(systemName: "arrowtriangle.down.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(CanonColor.brass)
            .shadow(color: PlateColor.ink.opacity(0.35), radius: 0.5, y: 0.5)
    }
}

/// The output-time ruler: the one row that states what the audio lanes below
/// are measured in. It belongs to the lane stack, not to the gap between
/// blocks, so it stays correct when the picture strip is hidden (active Look,
/// or a shot with no bands).
struct ShotTimelineRulerRow: View {
    let durationSeconds: Double
    let playheadSeconds: Double
    var onSeek: (Double) -> Void
    /// THE SCRUB LATCH: pause on begin, resume on release iff playing.
    var onScrubBegan: () -> Void = { }
    var onScrubEnded: () -> Void = { }
    /// Typed playhead jump (a precision act — the host pauses, clamps,
    /// frame-quantizes, and seeks exactly). nil keeps the static total.
    var onJump: ((Double) -> Void)? = nil
    /// Opens the sound editor sheet. Non-nil turns the empty tail gutter into
    /// the expand button — the affordance sits ON the block it enlarges. nil
    /// (FinalsReel, and the editor's own embedded stack) keeps the gutter
    /// clear.
    var onOpenEditor: (() -> Void)? = nil

    @Environment(\.shotTimelineViewport) private var viewport
    @Environment(\.shotTimelineMetrics) private var metrics

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                PlateLabel(text: "Output", size: 7.5, weight: .semibold, color: PlateColor.ink)
                if let onJump {
                    // The playhead's own position, stated at last — and a
                    // click-to-edit jump. Thanks to the playhead truth law
                    // this reads the exact frame whenever nothing is moving.
                    HStack(spacing: 3) {
                        ShotTimecodeField(
                            label: "",
                            seconds: ShotAudioTiming.frameQuantizedStart(playheadSeconds),
                            isEnabled: true,
                            onCommit: { onJump($0) }
                        )
                        PlateLabel(
                            text: "/ \(durationSeconds > 0 ? ShotAudioTiming.timecode(durationSeconds) : "—")",
                            size: 6.5,
                            color: PlateColor.inkFaint
                        )
                    }
                } else {
                    PlateLabel(
                        text: durationSeconds > 0 ? ShotAudioTiming.timecode(durationSeconds) : "—",
                        size: 6.5,
                        color: PlateColor.inkFaint
                    )
                }
            }
            .frame(width: ShotTimelineAxis.headWidth, alignment: .leading)
            .help("Everything below this line is output time — what plays, after cuts. The picture strip above measures material time, so the two blocks share a start and an end but not their interiors.")

            GeometryReader { geometry in
                Canvas { context, size in
                    draw(context: context, size: size)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            onScrubBegan()
                            onSeek(ShotTimelineAxis.seconds(
                                forX: value.location.x,
                                durationSeconds: durationSeconds,
                                laneWidth: geometry.size.width,
                                viewport: viewport
                            ))
                        }
                        .onEnded { _ in onScrubEnded() }
                )
            }

            if let onOpenEditor {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button(action: onOpenEditor) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(PlateColor.ink.opacity(0.72))
                    }
                    .buttonStyle(.plain)
                    .help("Open the sound editor (E)")
                    .padding(.trailing, 2)
                }
                .frame(width: ShotTimelineAxis.tailWidth)
            } else {
                Color.clear.frame(width: ShotTimelineAxis.tailWidth)
            }
        }
        .frame(height: metrics.rulerHeight)
        .accessibilityLabel("Output timeline ruler")
        .accessibilityValue(ShotAudioTiming.timecode(playheadSeconds))
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let laneWidth = max(size.width, 1)
        let height = max(size.height, 1)
        let baselineY = height - 0.5

        var baseline = Path()
        baseline.move(to: CGPoint(x: ShotTimelineAxis.contentInset, y: baselineY))
        baseline.addLine(to: CGPoint(x: laneWidth - ShotTimelineAxis.contentInset, y: baselineY))
        context.stroke(baseline, with: .color(PlateColor.hairlineFaint), lineWidth: 1)

        let window = viewport.window(durationSeconds: durationSeconds)
        let ticks = shotTimelineRulerTicks(
            durationSeconds: window.length > 0 ? window.length : durationSeconds,
            contentWidth: ShotTimelineAxis.contentWidth(laneWidth: laneWidth),
            windowStartSeconds: window.start
        )
        guard !ticks.isEmpty else { return }

        var majors = Path()
        var minors = Path()
        for tick in ticks {
            let x = ShotTimelineAxis.x(
                forSeconds: tick.seconds,
                durationSeconds: durationSeconds,
                laneWidth: laneWidth,
                viewport: viewport
            )
            // Ticks descend toward the lanes they measure.
            if tick.isMajor {
                majors.move(to: CGPoint(x: x, y: height - 7))
                majors.addLine(to: CGPoint(x: x, y: baselineY))
            } else {
                minors.move(to: CGPoint(x: x, y: height - 3.5))
                minors.addLine(to: CGPoint(x: x, y: baselineY))
            }
            guard let numeral = tick.numeral else { continue }
            // The bound numerals hug their ends so neither bleeds into a gutter.
            let isStart = tick.seconds <= window.start + 0.000_1
            let isEnd = abs(tick.seconds - (window.start + window.length)) <= 0.000_1
            let anchor: UnitPoint = isStart ? .leading : (isEnd ? .trailing : .center)
            context.draw(
                Text(numeral)
                    .font(CanonType.archive(6.5, weight: .medium))
                    .foregroundStyle(PlateColor.inkFaint),
                at: CGPoint(x: x, y: 4.5),
                anchor: anchor
            )
        }
        context.stroke(majors, with: .color(PlateColor.hairline), lineWidth: 1)
        context.stroke(minors, with: .color(PlateColor.hairlineFaint), lineWidth: 0.6)
    }
}

/// One continuous playhead for the whole output block. Drawing it once — over
/// the ruler and every lane — is what makes it unbroken across row gaps and
/// identical on every lane, which per-lane lines could never guarantee.
struct ShotTimelinePlayheadOverlay: View {
    let durationSeconds: Double
    let playheadSeconds: Double
    let isSnapped: Bool
    var laneCount: Int = ShotTimelineAxis.laneCount

    @Environment(\.shotTimelineViewport) private var viewport
    @Environment(\.shotTimelineMetrics) private var metrics

    var body: some View {
        GeometryReader { geometry in
            if durationSeconds > 0 {
                let timeAreaWidth = max(
                    geometry.size.width - ShotTimelineAxis.headWidth - ShotTimelineAxis.tailWidth,
                    1
                )
                let x = ShotTimelineAxis.headWidth + ShotTimelineAxis.x(
                    forSeconds: playheadSeconds,
                    durationSeconds: durationSeconds,
                    laneWidth: timeAreaWidth,
                    viewport: viewport
                )
                let height = metrics.playheadHeight(laneCount: laneCount)
                ZStack(alignment: .top) {
                    Rectangle()
                        .fill(isSnapped ? CanonColor.brass : PlateColor.ink.opacity(0.72))
                        .frame(width: isSnapped ? 2 : 1, height: height)
                    ShotTimelinePlayheadCap()
                        .offset(y: -2)
                }
                .frame(width: 10, height: height, alignment: .top)
                .offset(x: x - 5)
            }
        }
        .allowsHitTesting(false)
    }
}

/// THE PROJECTION GHOST: while a picture edit drags on the MATERIAL strip
/// above, this line marks the drag position's OUTPUT projection through the
/// ruler and lanes — the honest cross-seam readout. The strip's handle and
/// this line may sit at different x's; each is true in its own timeline (the
/// seam law: never claim the two x's are equal — re-project instead). Brass
/// and capless so it never reads as the playhead; 2pt while the drag sits on
/// a snap magnet, matching the playhead's snapped emphasis.
struct ShotTimelineDragGhostOverlay: View {
    let durationSeconds: Double
    let outputSeconds: Double
    let isSnapped: Bool
    var laneCount: Int = ShotTimelineAxis.laneCount

    @Environment(\.shotTimelineViewport) private var viewport
    @Environment(\.shotTimelineMetrics) private var metrics

    var body: some View {
        GeometryReader { geometry in
            if durationSeconds > 0 {
                let timeAreaWidth = max(
                    geometry.size.width - ShotTimelineAxis.headWidth - ShotTimelineAxis.tailWidth,
                    1
                )
                let x = ShotTimelineAxis.headWidth + ShotTimelineAxis.x(
                    forSeconds: outputSeconds,
                    durationSeconds: durationSeconds,
                    laneWidth: timeAreaWidth,
                    viewport: viewport
                )
                Rectangle()
                    .fill(CanonColor.brass.opacity(isSnapped ? 1 : 0.8))
                    .frame(
                        width: isSnapped ? 2 : 1.5,
                        height: metrics.playheadHeight(laneCount: laneCount)
                    )
                    .offset(x: x - (isSnapped ? 1 : 0.75))
            }
        }
        .allowsHitTesting(false)
    }
}

/// The SOURCE lane's picture reference: the shot's picture in OUTPUT time,
/// directly above the audio that plays with it.
///
/// Five rules keep it from reading as a second copy of the strip above — it is
/// a reference, not an instrument:
///   1. No imagery, ever. Hairlines and marks only; the strip owns filmstrips.
///   2. The REFERENCE never hit-tests. Per-segment audio controls do exist on
///      this band, but they ride a separate, higher overlay with no background
///      of its own — so seek-on-empty-space survives and this Canvas stays
///      inert forever.
///   3. A razor is a bare 2pt NOTCH here versus an area of removed material up
///      there — the visible proof that a cut costs no output time.
///   4. Provenance is a 1.5pt bottom-edge rule (a ledger line under the
///      waveform), never a block fill.
///   5. Labels are bare numerals, and only where a segment is wide enough.
/// The per-segment SOURCE audio controls: one always-visible tab per segment,
/// sitting on the band its audio plays under.
///
/// **This view must never gain a background, a fill, or a `contentShape` on any
/// container.** It floats above `ShotSourcePictureOverlay` and above the
/// waveform's own click-to-seek. SwiftUI hit-tests only the buttons themselves,
/// which is what keeps clicking anywhere else on the SOURCE lane a seek. A
/// stray `.background(Color.clear.contentShape(...))` here would silently eat
/// seek across the entire lane.
///
/// Always visible rather than revealed by selection or hover: the operator must
/// be able to SEE that a segment's audio can be silenced, without discovering a
/// gesture first.
struct ShotSourceSegmentAudioOverlay: View {
    let segments: [ShotOutputPictureSegment]
    let durationSeconds: Double
    /// Keys whose audio operator intent has silenced.
    let mutedSegmentKeys: Set<String>
    /// Keys turned down but not silenced — a distinct state, since a segment at
    /// 30% is neither "on" nor "off".
    let attenuatedSegmentKeys: Set<String>
    var laneHeight: CGFloat = ShotTimelineAxis.laneHeight
    let onToggleMute: (String) -> Void
    let onDetach: (String) -> Void

    @Environment(\.shotTimelineViewport) private var viewport

    var body: some View {
        GeometryReader { geometry in
            let laneWidth = max(geometry.size.width, 1)
            ZStack(alignment: .topLeading) {
                if durationSeconds > 0 {
                    ForEach(controls(laneWidth: laneWidth), id: \.key) { control in
                        tab(control)
                            .offset(x: control.rect.minX, y: control.rect.minY)
                    }
                }
            }
        }
    }

    private struct Control {
        var key: String
        var ordinal: Int
        var isMuted: Bool
        var isAttenuated: Bool
        var rect: CGRect
    }

    private func controls(laneWidth: CGFloat) -> [Control] {
        segments.compactMap { segment in
            guard !segment.isBridge, !segment.segmentKey.isEmpty else { return nil }
            let startX = ShotTimelineAxis.x(
                forSeconds: segment.outputStartSeconds,
                durationSeconds: durationSeconds,
                laneWidth: laneWidth,
                viewport: viewport
            )
            let endX = ShotTimelineAxis.x(
                forSeconds: segment.outputEndSeconds,
                durationSeconds: durationSeconds,
                laneWidth: laneWidth,
                viewport: viewport
            )
            guard let rect = ShotSourceSegmentControlMetrics.tabRect(
                startX: startX,
                endX: endX,
                laneHeight: laneHeight
            ) else { return nil }
            return Control(
                key: segment.segmentKey,
                ordinal: segment.ordinal,
                isMuted: mutedSegmentKeys.contains(segment.segmentKey),
                isAttenuated: attenuatedSegmentKeys.contains(segment.segmentKey),
                rect: rect
            )
        }
    }

    private func tab(_ control: Control) -> some View {
        let name = control.ordinal > 0 ? "segment \(control.ordinal)" : "this segment"
        return Button {
            onToggleMute(control.key)
        } label: {
            Image(systemName: control.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(control.isMuted ? PlateColor.inkFaint : PlateColor.ink)
                .frame(width: control.rect.width, height: control.rect.height)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(PlateColor.cream.opacity(0.92))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        // Brass states operator intent. Rust stays reserved for
                        // missing files, so a muted segment never reads as broken.
                        .stroke(
                            control.isMuted || control.isAttenuated
                                ? CanonColor.brass
                                : PlateColor.hairline,
                            lineWidth: control.isMuted || control.isAttenuated ? 1 : 0.6
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(control.isMuted
            ? "Unmute \(name)'s own audio"
            : "Mute \(name)'s own audio — the other segments are untouched")
        .contextMenu {
            Button(control.isMuted ? "Unmute \(name)" : "Mute \(name)") {
                onToggleMute(control.key)
            }
            Divider()
            Button("Detach to Clip lane…") { onDetach(control.key) }
                .help("Lifts this segment's audio onto the Clip lane as an editable region, and mutes it here. Converts this CUT to multi-region audio, which cannot be undone except with ⌘Z.")
        }
    }
}

struct ShotSourcePictureOverlay: View {
    let segments: [ShotOutputPictureSegment]
    let splices: [ShotOutputSplice]
    let durationSeconds: Double
    /// Segment keys carrying a control tab, so the ordinal moves out from under
    /// it. Empty when per-segment audio controls are not shown.
    var controlledSegmentKeys: Set<String> = []
    var laneHeight: CGFloat = ShotTimelineAxis.laneHeight

    @Environment(\.shotTimelineViewport) private var viewport

    var body: some View {
        // Captured as a value: the Canvas closure is nonisolated and cannot
        // touch the main-actor environment property directly.
        let viewport = viewport
        Canvas { context, size in
            let laneWidth = max(size.width, 1)
            let height = max(size.height, 1)
            guard durationSeconds > 0 else { return }

            func x(_ seconds: Double) -> CGFloat {
                ShotTimelineAxis.x(
                    forSeconds: seconds,
                    durationSeconds: durationSeconds,
                    laneWidth: laneWidth,
                    viewport: viewport
                )
            }

            for segment in segments {
                let startX = x(segment.outputStartSeconds)
                let endX = x(segment.outputEndSeconds)
                guard endX > startX else { continue }

                var rule = Path()
                rule.move(to: CGPoint(x: startX + 1, y: height - 1.25))
                rule.addLine(to: CGPoint(x: endX - 1, y: height - 1.25))
                let ruleColor: Color = segment.isBridge
                    ? CanonColor.brass.opacity(0.6)
                    : (segment.isFootage
                        ? PlateColor.ink.opacity(0.35)
                        : CanonColor.brass.opacity(0.35))
                if segment.isBridge {
                    context.stroke(
                        rule,
                        with: .color(ruleColor),
                        style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                    )
                } else {
                    context.stroke(rule, with: .color(ruleColor), lineWidth: 1.5)
                }

                let hasControl = !segment.segmentKey.isEmpty
                    && controlledSegmentKeys.contains(segment.segmentKey)
                    && ShotSourceSegmentControlMetrics.tabRect(
                        startX: startX,
                        endX: endX,
                        laneHeight: laneHeight
                    ) != nil
                if !segment.isBridge,
                   segment.ordinal > 0,
                   let inset = ShotSourceSegmentControlMetrics.ordinalPlacement(
                       startX: startX,
                       endX: endX,
                       hasControl: hasControl
                   ) {
                    context.draw(
                        Text("\(segment.ordinal)")
                            .font(CanonType.archive(6.5, weight: .semibold))
                            .foregroundStyle(PlateColor.inkFaint),
                        at: CGPoint(x: startX + inset, y: 5),
                        anchor: .leading
                    )
                }
            }

            for splice in splices {
                let spliceX = x(splice.outputSeconds)
                var notch = Path()
                switch splice.kind {
                case .razorSplice:
                    notch.move(to: CGPoint(x: spliceX, y: height - 6))
                    notch.addLine(to: CGPoint(x: spliceX, y: height))
                    context.stroke(notch, with: .color(PlateColor.ink.opacity(0.55)), lineWidth: 2)
                case .segmentJoin:
                    notch.move(to: CGPoint(x: spliceX, y: height - 4))
                    notch.addLine(to: CGPoint(x: spliceX, y: height))
                    context.stroke(notch, with: .color(PlateColor.hairline), lineWidth: 1)
                case .bridgeIn, .bridgeOut:
                    notch.move(to: CGPoint(x: spliceX, y: height - 5))
                    notch.addLine(to: CGPoint(x: spliceX, y: height))
                    context.stroke(notch, with: .color(CanonColor.brass.opacity(0.7)), lineWidth: 1.2)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
