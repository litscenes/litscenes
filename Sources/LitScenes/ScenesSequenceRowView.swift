import SwiftUI

/// One card of THE SEQUENCE ROW — a pure value snapshot, id'd by the
/// sequence ENTRY (fresh per add, so seam identity follows the pick).
struct SequenceSceneCard: Hashable, Identifiable {
    var entryId: String = ""
    var projectId: String = ""
    var shotId: String = ""
    var displayName: String = ""
    var posterCandidatePaths: [String] = []
    /// 1-based position — the same numeral the rail card's coin wears.
    var position: Int = 0
    var id: String { entryId }
}

/// THE SEQUENCE ROW (locked after live user testing): the
/// Output sequence as its own ordered strip under the rail — the coins alone
/// could not carry "which scenes make the final video, in what order" at
/// real project density. Appears once anything is READY. Cards are the
/// picks in FINAL-VIDEO order; drag to reorder (the same
/// `SequenceCoinTransfer` the rail coins drag, so a coin can be dropped
/// straight into this row); click stages the scene; hover ✕ un-marks
/// (seam-destroying removals confirm at the owner). PLAY ALL lives here —
/// the Reel over this exact order (its footer owns export). A dumb view —
/// values in, closures out.
struct ScenesSequenceRowView: View {
    static let thumbSize = CGSize(width: 96, height: 54)

    let cards: [SequenceSceneCard]
    /// The scene on the hero stage — its card wears the brass ring here too.
    var selectedSceneId: String = ""
    var isExporting: Bool = false
    var exportStatus: String = ""
    /// Click a card: the scene takes the stage.
    var onOpen: (String) -> Void
    /// Hover ✕: un-mark (the scene leaves the sequence; the rail keeps it).
    var onRemove: (String) -> Void
    /// Drag-reorder; `toIndex` reads against the PRE-removal order (the
    /// movingShot convention). Drops ride SequenceCoinTransfer — never
    /// SceneRailTransfer — so a sequence drag can not rearrange the
    /// project's scene order, and vice versa.
    var onMove: (_ shotId: String, _ toIndex: Int) -> Void
    /// Opens the Reel over this exact sequence — playback AND export live
    /// there (its footer owns Export Reel / Export for YouTube).
    var onPlayAll: () -> Void
    /// THE SEAM PILLS: one per gutter, REQUESTED state only — applied truth
    /// needs baked durations that exist only while the Reel is open, so the
    /// pill's help says where that truth lives instead of guessing it.
    var seams: [ReelSeamDisplay] = []
    var onSetSeam: (
        _ leftEntryId: String,
        _ rightEntryId: String,
        _ kind: ReelSeamKind,
        _ frames: Int?
    ) -> Void = { _, _, _, _ in }

    @State private var targetedShotId = ""
    @State private var hoveredShotId = ""
    @State private var isEndTargeted = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // PLAY ALL leads the row (it replaced the SEQUENCE label — the
            // numbered cards already say what this strip is).
            controls
            CanonHScroller {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(cards.enumerated()), id: \.element.entryId) { index, card in
                        sequenceCard(card)
                        if index < cards.count - 1 {
                            seamPill(between: card, and: cards[index + 1])
                        }
                    }
                    endDropZone
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 16)
        .background(CanonColor.brass.opacity(0.05))
    }

    private func sequenceCard(_ card: SequenceSceneCard) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            thumb(for: card)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            card.shotId == selectedSceneId
                                ? CanonColor.brass
                                : CanonColor.hairlinePaper.opacity(0.9),
                            lineWidth: card.shotId == selectedSceneId ? 2 : 1
                        )
                )
                .overlay(alignment: .bottomTrailing) {
                    // The same numeral as the rail card's coin — one identity
                    // across both surfaces.
                    Text("\(card.position)")
                        .font(CanonType.archive(8, weight: .heavy))
                        .foregroundStyle(CanonColor.ink)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(CanonColor.brass))
                        .padding(3)
                }
                .overlay(alignment: .topTrailing) {
                    if hoveredShotId == card.shotId {
                        Button {
                            onRemove(card.shotId)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(CanonColor.ink.opacity(0.8))
                                .padding(3)
                                .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.9)))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(3)
                        .help("Remove from the Output sequence")
                    }
                }
            Text(card.displayName)
                .font(CanonType.archive(7.5, weight: .semibold))
                .foregroundStyle(CanonColor.ink.opacity(0.85))
                .lineLimit(1)
                .frame(width: Self.thumbSize.width, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredShotId = hovering ? card.shotId : (hoveredShotId == card.shotId ? "" : hoveredShotId)
        }
        .onTapGesture { onOpen(card.shotId) }
        .help("Open \(card.displayName) on the stage")
        .draggable(SequenceCoinTransfer(projectId: card.projectId, shotId: card.shotId)) {
            Text(card.displayName)
                .font(CanonType.archive(8.5, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(CanonColor.paperInset))
                .overlay(Capsule().stroke(CanonColor.brass.opacity(0.6), lineWidth: 1))
        }
        .dropDestination(for: SequenceCoinTransfer.self) { items, _ in
            guard let dragged = items.first,
                  dragged.projectId == card.projectId,
                  dragged.shotId != card.shotId,
                  cards.contains(where: { $0.shotId == dragged.shotId }),
                  let targetIndex = cards.firstIndex(where: { $0.shotId == card.shotId })
            else { return false }
            onMove(dragged.shotId, targetIndex)
            return true
        } isTargeted: { targeted in
            targetedShotId = targeted ? card.shotId : (targetedShotId == card.shotId ? "" : targetedShotId)
        }
        .overlay(alignment: .leading) {
            if targetedShotId == card.shotId {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(CanonColor.brass)
                    .frame(width: 3, height: Self.thumbSize.height)
                    .offset(x: -5)
            }
        }
    }

    /// The gutter's seam pill, spanning the thumbnail band as a visible
    /// divider (the `.canvasRow` dress — the Reel's cream chip disappears on
    /// this dark surface). Every row gutter is an adjacent pair by
    /// construction, so every pill authors.
    @ViewBuilder
    private func seamPill(between left: SequenceSceneCard, and right: SequenceSceneCard) -> some View {
        if let seam = seams.first(where: {
            $0.leftEntryId == left.entryId && $0.rightEntryId == right.entryId
        }) {
            ReelSeamPillMenu(seam: seam, truth: .requested, surface: .canvasRow, onSetSeam: onSetSeam)
                .frame(height: Self.thumbSize.height)
        }
    }

    /// Dropping past the last card sends the scene to the end (a drop ON a
    /// card lands before it — this is the only way to become last).
    private var endDropZone: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(isEndTargeted ? CanonColor.brass : Color.clear)
            .frame(width: 3, height: Self.thumbSize.height)
            .frame(width: 18)
            .contentShape(Rectangle())
            .dropDestination(for: SequenceCoinTransfer.self) { items, _ in
                guard let dragged = items.first,
                      cards.contains(where: { $0.shotId == dragged.shotId })
                else { return false }
                onMove(dragged.shotId, cards.count)
                return true
            } isTargeted: { isEndTargeted = $0 }
    }

    /// One CTA: PLAY ALL opens the Reel, whose footer owns export — a second
    /// identically-behaving EXPORT button would be a lie. An export started
    /// there still reports its progress here.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: onPlayAll) {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("PLAY ALL")
                        .font(CanonType.archive(8, weight: .bold))
                        .kerning(0.8)
                }
                .foregroundStyle(CanonColor.brass)
                .padding(.horizontal, 12)
                .frame(height: 22)
                .background(Capsule().fill(CanonColor.brass.opacity(0.10)))
                .overlay(Capsule().stroke(CanonColor.brass.opacity(0.45), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Play the sequence in order — the Reel over these exact picks (export lives in its footer)")
            if isExporting {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                    Text("EXPORTING…")
                        .font(CanonType.archive(7, weight: .bold))
                        .kerning(0.6)
                }
                .foregroundStyle(CanonColor.muted)
                .help(exportStatus.trimmed.nilIfEmpty ?? "Export in progress")
            }
        }
    }

    @ViewBuilder
    private func thumb(for card: SequenceSceneCard) -> some View {
        let image = card.posterCandidatePaths.lazy
            .compactMap { StripThumbnailCache.shared.image(path: $0, maxPixel: 200) }
            .first
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(CanonColor.paperInset.opacity(0.5))
                .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
        }
    }
}
