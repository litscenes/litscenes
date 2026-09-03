import SwiftUI

/// The SCENES v2 LEDGER RAIL (Option A, a locked design): every scene of
/// the loaded project as a survey card — micro-filmstrip, status edge, live
/// render progress, ledger line, sequence coin — over the one hero stage.
/// Selection is a radio: click a card, the stage shows it; the selected card
/// wears the brass ring and the tab connector pointing at the stage. The
/// Ready Timeline band folded in here: membership reads as numbered coins,
/// PLAY ALL lives in the header, and coin reorder rides the context menu.
/// Deliberately single-project (locked); a dumb view — values
/// in, closures out.
struct ScenesRailView: View {
    static let cardWidth: CGFloat = 132
    static let thumbSize = CGSize(width: 132, height: 74)

    let groups: [ProjectSceneGroup]
    /// The scene on the hero stage ("" = empty stage).
    let selectedSceneId: String
    /// THE UP NEXT HINT: the scene the conveyor would load on READY.
    var upNextSceneId: String = ""
    var onOpenScene: (SceneRef) -> Void
    /// Reorder within the LOADED group only (the engine can't write a foreign
    /// timeline).
    var onMoveScene: (_ shotId: String, _ toVisibleIndex: Int) -> Void
    var onCreateScene: () -> Void
    /// Source material dropped on a card appends to that scene (the
    /// collapsed-row law, lock-aware at the owner); false = honest refusal.
    var onDropMaterial: (_ shotId: String, _ transfer: ShotFrameTransfer) -> Bool = { _, _ in false }
    /// Sequence coin context menu: one step earlier (-1) / later (+1).
    var onSequenceStep: (_ shotId: String, _ delta: Int) -> Void = { _, _ in }
    /// THE COIN DROP: a coin dragged onto another coin re-sequences the
    /// dragged scene BEFORE the target's 0-based position (the deleted Ready
    /// band's drop law, riding the coins).
    var onSequenceDrop: (_ draggedShotId: String, _ beforePosition: Int) -> Void = { _, _ in }
    /// Coin context menu removal (seam-destroying removals confirm at the
    /// owner, exactly like the stage's READY toggle).
    var onUnmark: (String) -> Void = { _ in }

    @State private var targetedSceneId = ""
    @State private var materialTargetedSceneId = ""
    @State private var coinTargetedSceneId = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                // The canon scroller replaces the stock white overlay bar —
                // its track is always visible on overflow, so the rail still
                // scrolls by mouse, not only by trackpad swipe.
                CanonHScroller(trackInset: 16) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(groups) { group in
                            railGroup(group)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                }
                .onChange(of: selectedSceneId) { _, sceneId in
                    guard !sceneId.isEmpty else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("rail_\(sceneId)", anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func railGroup(_ group: ProjectSceneGroup) -> some View {
        // Lazy on purpose: a ledger card resolves up to three thumbnails, so
        // only the cards actually scrolled into view may pay that cost.
        LazyHStack(alignment: .top, spacing: 8) {
            if !group.loadIssue.isEmpty {
                Text(group.loadIssue)
                    .font(CanonType.archive(7, weight: .medium))
                    .foregroundStyle(CanonColor.rust)
                    .lineLimit(2)
                    .frame(maxWidth: 200, alignment: .leading)
            }
            ForEach(group.scenes) { scene in
                sceneCard(scene, group: group)
                    .id("rail_\(scene.shotId)")
            }
            if group.isLoaded {
                newSceneCard
            }
        }
    }

    // MARK: Ledger card

    private func sceneCard(_ scene: SceneIndexEntry, group: ProjectSceneGroup) -> some View {
        let isSelected = group.isLoaded && scene.shotId == selectedSceneId
        let isUpNext = group.isLoaded && !upNextSceneId.isEmpty && scene.shotId == upNextSceneId && !isSelected
        return VStack(alignment: .leading, spacing: 3) {
            ZStack(alignment: .topTrailing) {
                filmstrip(for: scene)
                badgeOverlay(scene)
                    .padding(3)
            }
            .overlay(alignment: .leading) {
                statusEdge(scene.badge)
            }
            .overlay(alignment: .bottom) {
                if let progress = scene.renderProgress {
                    progressBar(progress)
                }
            }
            .overlay(alignment: .topLeading) {
                if isUpNext {
                    Text("UP NEXT")
                        .font(CanonType.archive(6, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(CanonColor.muted)
                        .padding(.horizontal, 4)
                        .frame(height: 12)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.6)))
                        .padding(3)
                        .help("Loads onto the stage when the current scene is marked READY")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let position = scene.sequencePosition {
                    sequenceCoin(position, scene: scene)
                        .padding(.trailing, 4)
                        .padding(.bottom, scene.renderProgress != nil ? 6 : 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        materialTargetedSceneId == scene.shotId
                            ? CanonColor.softGold
                            : (isSelected ? CanonColor.brass : CanonColor.hairlinePaper.opacity(0.5)),
                        lineWidth: isSelected || materialTargetedSceneId == scene.shotId ? 2 : 1
                    )
            )
        }
        .frame(width: Self.cardWidth)
        // THE BARE RAIL: no text rows — the name and ledger survive as a tooltip.
        .help(scene.ledgerLine.isEmpty ? scene.displayName : "\(scene.displayName) · \(scene.ledgerLine)")
        .overlay(alignment: .bottom) {
            // THE TAB CONNECTOR: the selected card visibly feeds the stage.
            if isSelected {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(CanonColor.brass)
                        .frame(width: 2, height: 5)
                    Triangle()
                        .fill(CanonColor.brass)
                        .frame(width: 10, height: 5)
                }
                .offset(y: 11)
                .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenScene(SceneRef(projectId: scene.projectId, shotId: scene.shotId))
        }
        .help(group.isLoaded
            ? "Open \(scene.displayName) on the stage"
            : "Switch to \(group.projectName) and open \(scene.displayName)")
        .contextMenu {
            // Never an empty menu (macOS pops a blank panel): unsequenced
            // cards get the honest one-liner instead of nothing.
            if group.isLoaded, let position = scene.sequencePosition {
                let sequencedCount = group.scenes.filter { $0.sequencePosition != nil }.count
                Button("Move Earlier in Sequence") { onSequenceStep(scene.shotId, -1) }
                    .disabled(position <= 1)
                Button("Move Later in Sequence") { onSequenceStep(scene.shotId, 1) }
                    .disabled(position >= sequencedCount)
                Divider()
                Button("Remove from Sequence", role: .destructive) { onUnmark(scene.shotId) }
            } else {
                Button("Not in the sequence — READY adds it") {}
                    .disabled(true)
            }
        }
        .modifier(RailCardDragModifier(scene: scene, isLoaded: group.isLoaded))
        .dropDestination(for: SceneRailTransfer.self) { items, _ in
            guard group.isLoaded,
                  let dragged = items.first,
                  dragged.projectId == scene.projectId,
                  dragged.shotId != scene.shotId,
                  let targetIndex = group.scenes.firstIndex(where: { $0.shotId == scene.shotId })
            else { return false }
            onMoveScene(dragged.shotId, targetIndex)
            return true
        } isTargeted: { targeted in
            targetedSceneId = targeted ? scene.shotId : (targetedSceneId == scene.shotId ? "" : targetedSceneId)
        }
        // THE SPRING-LOADED RAIL DROP (v1): source material dropped on the
        // card appends to that scene without leaving the hero.
        .dropDestination(for: ShotFrameTransfer.self) { items, _ in
            guard group.isLoaded, let transfer = items.first else { return false }
            return onDropMaterial(scene.shotId, transfer)
        } isTargeted: { targeted in
            materialTargetedSceneId = targeted
                ? scene.shotId
                : (materialTargetedSceneId == scene.shotId ? "" : materialTargetedSceneId)
        }
        .overlay(alignment: .leading) {
            if targetedSceneId == scene.shotId {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(CanonColor.brass)
                    .frame(width: 3, height: Self.thumbSize.height)
                    .offset(x: -5)
            }
        }
    }

    /// THE LEDGER LINE, state-aware: rendering shows the artifact's own
    /// progress sentence, failed says so in rust, everything else reads
    /// frames · runtime · sound glyphs · model.
    private var newSceneCard: some View {
        Button {
            onCreateScene()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CanonColor.brass.opacity(0.85))
                Text("NEW")
                    .font(CanonType.archive(6.5, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(CanonColor.muted)
            }
            .frame(width: Self.cardWidth, height: Self.thumbSize.height)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.25))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(CanonColor.brass.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New Scene")
        .dropDestination(for: SceneRailTransfer.self) { items, _ in
            guard let dragged = items.first,
                  let loaded = groups.first(where: { $0.isLoaded }),
                  dragged.projectId == loaded.projectId
            else { return false }
            onMoveScene(dragged.shotId, max(loaded.scenes.count - 1, 0))
            return true
        }
    }

    // MARK: Card furniture

    /// THE MICRO-FILMSTRIP: the first placed material large, the next two as
    /// slivers — a scene reads as a sequence, not one poster. ONE walk of the
    /// poster candidates takes the first three DECODABLE stills (the poster
    /// law's fall-through, without ever duplicating a frame across slots),
    /// and the widths adapt so a two-material card fills its full 132pt.
    @ViewBuilder
    private func filmstrip(for scene: SceneIndexEntry) -> some View {
        let images = Array(
            scene.posterCandidatePaths.lazy
                .compactMap { StripThumbnailCache.shared.image(path: $0, maxPixel: 200) }
                .prefix(3)
        )
        if let main = images.first {
            let sliverCount = images.count - 1
            let sliverWidth = sliverCount > 0
                ? (Self.thumbSize.width - 94 - CGFloat(sliverCount)) / CGFloat(sliverCount)
                : 0
            HStack(spacing: 1) {
                Image(nsImage: main)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: sliverCount == 0 ? Self.thumbSize.width : 94,
                        height: Self.thumbSize.height
                    )
                    .clipped()
                ForEach(1..<images.count, id: \.self) { slot in
                    Image(nsImage: images[slot])
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: sliverWidth, height: Self.thumbSize.height)
                        .clipped()
                }
            }
            .frame(width: Self.thumbSize.width, height: Self.thumbSize.height, alignment: .leading)
            .background(CanonColor.archiveWell)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(CanonColor.paperInset.opacity(0.5))
                .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                .overlay(
                    Text(scenesV2RailPosterFallback(entryCount: scene.entryCount))
                        .font(CanonType.archive(7.5, weight: .semibold))
                        .kerning(0.8)
                        .foregroundStyle(CanonColor.muted.opacity(0.6))
                )
        }
    }

    /// THE STATUS EDGE: render truth readable across twenty cards without
    /// reading a word — hollow draft, gold rendering, rust failed, brass
    /// ready (parked reads muted; its badge carries the story).
    private func statusEdge(_ badge: SceneRenderBadge) -> some View {
        Rectangle()
            .fill(statusEdgeColor(badge))
            .frame(width: 3, height: Self.thumbSize.height)
    }

    private func statusEdgeColor(_ badge: SceneRenderBadge) -> Color {
        switch badge {
        case .draft: return CanonColor.hairlineDark
        case .rendering: return CanonColor.softGold
        case .parked: return CanonColor.muted
        case .failed: return CanonColor.rust
        case .ready: return CanonColor.brass
        }
    }

    private func progressBar(_ fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(CanonColor.hairlineDark)
                // A just-started render shows a small leading fill — an empty
                // track would read as "stalled at 0%".
                Rectangle()
                    .fill(CanonColor.softGold)
                    .frame(width: max(proxy.size.width * fraction, 4))
            }
        }
        .frame(height: 3)
        .allowsHitTesting(false)
    }

    /// THE SEQUENCE COIN: the numeral IS the scene's position in the Output
    /// sequence — the Ready Timeline band, folded onto the card. The coin is
    /// its own drag handle (its own transfer type, so a coin drag can never
    /// reorder the project's scene order) and its own drop target: dropping a
    /// coin on another coin re-sequences the dragged scene BEFORE it.
    private func sequenceCoin(_ position: Int, scene: SceneIndexEntry) -> some View {
        Text("\(position)")
            .font(CanonType.archive(8, weight: .heavy))
            .foregroundStyle(CanonColor.ink)
            .frame(width: 16, height: 16)
            .background(Circle().fill(CanonColor.brass))
            .overlay(
                Circle().stroke(
                    coinTargetedSceneId == scene.shotId ? CanonColor.softGold : Color.clear,
                    lineWidth: 2
                )
            )
            .contentShape(Circle())
            .help("№\(position) in the Output sequence — drag onto another coin to reorder, right-click for steps or removal")
            .draggable(SequenceCoinTransfer(projectId: scene.projectId, shotId: scene.shotId)) {
                Text("№\(position)")
                    .font(CanonType.archive(9, weight: .heavy))
                    .foregroundStyle(CanonColor.ink)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(CanonColor.brass))
            }
            .dropDestination(for: SequenceCoinTransfer.self) { items, _ in
                guard let dragged = items.first,
                      dragged.projectId == scene.projectId,
                      dragged.shotId != scene.shotId else { return false }
                onSequenceDrop(dragged.shotId, position - 1)
                return true
            } isTargeted: { targeted in
                coinTargetedSceneId = targeted
                    ? scene.shotId
                    : (coinTargetedSceneId == scene.shotId ? "" : coinTargetedSceneId)
            }
    }

    @ViewBuilder
    private func badgeOverlay(_ scene: SceneIndexEntry) -> some View {
        switch scene.badge {
        case .draft, .rendering:
            EmptyView()
        case .parked:
            Text("PARKED")
                .font(CanonType.archive(6, weight: .bold))
                .kerning(0.5)
                .foregroundStyle(CanonColor.muted)
                .padding(.horizontal, 3)
                .frame(height: 11)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.85)))
                .help("A render was interrupted in this project — opening it reconciles honestly (kept segments are reused)")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(CanonColor.rust)
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.85)))
        case .ready:
            Image(systemName: "film")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(CanonColor.brass)
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.85)))
        }
    }
}

/// The tab connector's arrowhead.
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Only loaded-project cards drag (a foreign scene must hop first); applied
/// as a modifier so the card body stays one expression.
private struct RailCardDragModifier: ViewModifier {
    let scene: SceneIndexEntry
    let isLoaded: Bool

    func body(content: Content) -> some View {
        if isLoaded {
            content.draggable(SceneRailTransfer(projectId: scene.projectId, shotId: scene.shotId)) {
                Text(scene.displayName)
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .foregroundStyle(CanonColor.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(CanonColor.paperInset))
                    .overlay(Capsule().stroke(CanonColor.brass.opacity(0.6), lineWidth: 1))
            }
        } else {
            content
        }
    }
}
