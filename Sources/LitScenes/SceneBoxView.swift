import SwiftUI

/// The SCENES v2 hero stage (Option A: the ONE working box): a thin
/// honest-status chrome bar over a CutStripView in `.box` layout. Since the
/// unified page scroll the box HUGS its strip content up to
/// `maxStripHeight`: an expanded render-plan or narration strip grows the
/// stage until the cap, and only past it does the internal scroller engage —
/// below the cap the wheel belongs to the page. Drops are the primary
/// gesture here, so the locked law is surfaced BEFORE the per-cell refusal:
/// a persistent badge plus a drag-over hint.
struct SceneBoxView: View {
    /// nil = empty stage (renders the honest exhaustion plate).
    let shot: ProjectShot?
    /// Index among visibleShots — drives numbering and the strip's roman.
    let visibleIndex: Int
    var poolInputs: [StageInput] = []
    var actions: CutStripActions
    /// True when this scene is already in the Ready Timeline — the footer
    /// button renders engaged and a click un-marks.
    var isReady: Bool = false
    /// The engine's mark-ready gate (`sceneCanBeMarkedReady`) — computed by
    /// the owner because it also covers razor-join and Shot Look work this
    /// view cannot see.
    var canMarkReady: Bool = false
    /// The honest reason shown while the button is disabled (rendering vs.
    /// no rendered take) — also the owner's call, for the same reason.
    var readyDisabledHelp: String = ""
    /// A rail thumbnail dropped anywhere on the stage selects that scene.
    var onAssignScene: (String) -> Void
    /// The READY footer button (toggles membership; the workbench owns the
    /// conveyor that follows a mark and the seam-loss confirm on un-mark).
    var onMarkReady: () -> Void = {}
    /// The strip's height ceiling while the box rides the pinned page-scroll
    /// header — the owner derives it from the workspace so the pool always
    /// keeps visible rows beneath the pinned stage.
    var maxStripHeight: CGFloat = .infinity
    /// Scrolls the page back to the top, revealing the collapsed rail. Lives
    /// on the READY footer because the footer stays pinned even after the
    /// shot header has ridden above the fold — the way back must never
    /// scroll away with the thing it comes back from.
    var onRevealRail: (() -> Void)? = nil
    /// The empty plate's message — the owner derives it from live state
    /// (`scenesV2EmptyStagePlateCopy`), since with the guided-stage spotlight
    /// this plate only ever renders while Scenes exist.
    var emptyPlateText: String = "Click a Scene in the rail to stage it"
    /// Forwarded to the strip: what an empty Scene asks for.
    var emptySceneHintText: String = "Drag Frames or Footage from the pool below — or click + to pick material or render a new Frame."

    @State private var isHintTargeted = false
    @State private var stripContentHeight: CGFloat = 0
    @State private var isHoveringReady = false

    private var isLocked: Bool {
        guard let shot else { return false }
        return actions.activeShotRenderId == shot.shotId
            || shot.renderArtifact?.status == "generating"
            || !shot.browsableRenderVersions.isEmpty
    }

    private var isActivelyRendering: Bool {
        guard let shot else { return false }
        return actions.activeShotRenderId == shot.shotId
            || shot.renderArtifact?.status == "generating"
    }

    private var tailStartIndex: Int? {
        guard let shot, !isActivelyRendering else { return nil }
        return shotSuffixTailStartIndex(shot: shot)
    }

    var body: some View {
        Group {
            if let shot {
                VStack(alignment: .leading, spacing: 6) {
                    chromeBar(shot)
                    // The scroller stays permanently mounted: swapping it for
                    // a plain view when content fits would change
                    // CutStripView's structural identity and reset its
                    // expansion @State (render plan, narration, picker).
                    ScrollView(.vertical, showsIndicators: true) {
                        CutStripView(
                            cut: shot,
                            index: visibleIndex,
                            poolInputs: poolInputs,
                            actions: actions,
                            layout: .box,
                            emptySceneHintText: emptySceneHintText
                        )
                        .padding(.bottom, 8)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            stripContentHeight = height
                        }
                    }
                    .frame(height: stripContentHeight == 0
                        ? min(160, maxStripHeight)
                        : min(stripContentHeight, maxStripHeight))
                    .scrollDisabled(stripContentHeight <= maxStripHeight + 0.5)
                    .padding(.horizontal, 10)
                    readyFooter(shot)
                }
            } else {
                emptyPlate
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(ScenesV2StageDress.well)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderTint, lineWidth: isLocked ? 1.5 : 1)
        )
        .dropDestination(for: SceneRailTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            onAssignScene(transfer.shotId)
            return true
        }
    }

    private var borderTint: Color {
        guard isLocked else { return ScenesV2StageDress.wellHairline }
        return tailStartIndex != nil ? CanonColor.brass.opacity(0.55) : CanonColor.muted.opacity(0.5)
    }

    private func chromeBar(_ shot: ProjectShot) -> some View {
        HStack(spacing: 8) {
            // The pool's section-header voice: brass tracked caps and a
            // paper rule across the dark well.
            Text(sceneDisplayName(shot: shot, index: visibleIndex).uppercased())
                .font(CanonType.archive(8.5, weight: .bold))
                .kerning(2.0)
                .foregroundStyle(CanonColor.brass)
                .lineLimit(1)
                .layoutPriority(1)
            lockBadge(shot)
            Rectangle()
                .fill(CanonColor.hairlinePaper)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            if isHintTargeted {
                Text(dragHint)
                    .font(CanonType.archive(7, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(isLocked ? CanonColor.rust : CanonColor.brass)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .contentShape(Rectangle())
        // Dropping source material on the bar lands at the strip's end (the
        // collapsed-row law) — and hovering it announces the locked law
        // before any per-cell refusal.
        .dropDestination(for: ShotFrameTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            let end = shot.entries.count
            let tailAllows = tailStartIndex.map { end >= $0 } ?? false
            guard !isLocked || tailAllows else { return false }
            if transfer.isClipDrag {
                actions.onInsertClip(shot.shotId, transfer.clipMediaId, end)
            } else if !transfer.frameImageId.trimmed.isEmpty {
                actions.onInsertFrame(shot.shotId, transfer, end)
            } else {
                return false
            }
            actions.onTouchCut(shot.shotId)
            return true
        } isTargeted: { isHintTargeted = $0 }
    }

    private var dragHint: String {
        if isActivelyRendering {
            return "Rendering — the strip is locked until it finishes"
        }
        if isLocked {
            return tailStartIndex != nil
                ? "Drops land after the rendered tail"
                : "Rendered — duplicate to edit"
        }
        return "Drop to add at the end"
    }

    @ViewBuilder
    private func lockBadge(_ shot: ProjectShot) -> some View {
        if isActivelyRendering {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                Text("RENDERING")
                    .font(CanonType.archive(6.5, weight: .bold))
                    .kerning(0.6)
            }
            .foregroundStyle(CanonColor.brass)
        } else if isLocked {
            HStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7, weight: .semibold))
                Text(tailStartIndex != nil ? "RENDERED · APPENDS ONLY" : "RENDERED · LOCKED")
                    .font(CanonType.archive(6.5, weight: .bold))
                    .kerning(0.6)
            }
            .foregroundStyle(tailStartIndex != nil ? CanonColor.brass : CanonColor.muted)
            .help(tailStartIndex != nil
                ? "The rendered strip is immutable; new material appends after the rendered tail. NEW VERSION duplicates for free editing."
                : "The rendered strip is immutable. NEW VERSION duplicates for free editing.")
        }
    }

    /// The large-but-muted READY CTA, pinned to the box's bottom-right so it
    /// never occludes the scrolling strip. Gated on the engine's mark-ready
    /// law (playable render, no in-flight video work); the disabled state
    /// stays visible and says the actual reason. Once marked, the button
    /// renders engaged and a click un-marks (seam-destroying removals confirm
    /// at the workbench).
    private func readyFooter(_ shot: ProjectShot) -> some View {
        let enabled = isReady || canMarkReady
        let tint: Color = isReady
            ? CanonColor.brass
            : (canMarkReady && isHoveringReady ? CanonColor.brass : CanonColor.muted)
        return HStack {
            if let onRevealRail {
                Button(action: onRevealRail) {
                    HStack(spacing: 3) {
                        Text("SCENES")
                            .font(CanonType.archive(7, weight: .bold))
                            .kerning(0.8)
                        Image(systemName: "chevron.up")
                            .font(.system(size: 6, weight: .bold))
                    }
                    .foregroundStyle(CanonColor.brass)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show the Scene rail")
            }
            Spacer(minLength: 0)
            Button {
                onMarkReady()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isReady ? "checkmark" : "arrow.up.right")
                        .font(.system(size: 10.5, weight: .bold))
                    Text(isReady ? "IN TIMELINE" : "READY")
                        .font(CanonType.archive(11, weight: .bold))
                        .kerning(1.6)
                }
                .foregroundStyle(tint.opacity(enabled ? 1 : 0.55))
                .padding(.horizontal, 22)
                .frame(height: 36)
                .background(Capsule().fill(tint.opacity(enabled ? 0.10 : 0.06)))
                .overlay(Capsule().stroke(tint.opacity(enabled ? 0.45 : 0.25), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .onHover { isHoveringReady = $0 }
            .help(
                isReady
                    ? "In the Output sequence — its coin marks the order on the rail card; click to remove"
                    : (canMarkReady
                        ? "Mark this Scene ready — it joins the Output sequence and its rail card earns a numbered coin"
                        : readyDisabledHelp)
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var emptyPlate: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(CanonColor.muted.opacity(0.5))
            Text(emptyPlateText)
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.muted)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .contentShape(Rectangle())
    }
}
