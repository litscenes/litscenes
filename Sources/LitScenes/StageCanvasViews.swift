import SwiftUI
import AppKit

// MARK: - Stage canvas (the unified STAGE / CUT surface on the SCENES tab)
//
// A STAGE plate gathers an unordered palette of inputs (frames + footage) and
// its CUTs hang off the plate's lower edge — outside the plate but tethered
// to it by a brass spine. Gathering and sequencing stay separate gestures:
// drops on the plate never imply an order; drops on a cut strip append or
// gap-insert exactly like the old shots band.

/// Everything a stage plate needs from the workbench, bundled once and shared
/// by every plate in the column.
struct StagePlateActions {
    var frameLookup: [String: ProjectLensHeroImage] = [:]
    var mediaLookup: [String: MediaItemRecord] = [:]

    var onRenameStage: (String, String) -> Void = { _, _ in }
    var onDeleteStage: (String) -> Void = { _ in }
    /// (stageId, transfer) — a frame or footage drag landed on the plate.
    var onGather: (String, ShotFrameTransfer) -> Void = { _, _ in }
    /// Removes a palette reference (never the frame itself).
    var onRemoveInput: (String, StageInput) -> Void = { _, _ in }
    /// Opens the Frame Creator seeded for this stage (pool "+ NEW FRAME").
    var onCreateFrame: (String) -> Void = { _ in }
    /// Duplicates a ready frame (independent copy; lands on the same stage).
    var onDuplicateFrame: (ProjectLensHeroImage) -> Void = { _ in }
    /// Creates an empty cut on this stage.
    var onCreateCut: (String) -> Void = { _ in }
    /// Creates a cut opening with the dropped frame/footage.
    var onCreateCutWith: (String, ShotFrameTransfer) -> Void = { _, _ in }
    var onPreflightCombine: (String, [String]) -> CombinedCutPreflight = { _, ids in
        CombinedCutPreflight(sourceCutIds: ids)
    }
    var onCombine: (String, [String]) -> String = { _, _ in "" }
    var onOpenCombined: (String) -> Void = { _ in }
    /// (cutId, destination stageId, insertion index in that stage's VISIBLE
    /// order) — re-arranges a cut's row, or re-homes it onto another stage.
    var onMoveCut: (String, String, Int) -> Void = { _, _, _ in }
    /// Every stage, for the "Move to Stage…" menu — the long-distance path a
    /// drag can't serve on an unbounded page, and the only way to reach a
    /// stage that renders no spine because it holds nothing yet.
    var stageDirectory: [StageDirectoryRow] = []
    var onOpenFrame: (ProjectLensHeroImage) -> Void = { _ in }
    var onToggleKept: (ProjectLensHeroImage) -> Void = { _ in }
    var onRetryFrame: (ProjectLensHeroImage) -> Void = { _ in }

    var cutActions = CutStripActions()
}

struct StageDirectoryRow: Identifiable, Hashable {
    let stageId: String
    let name: String

    var id: String { stageId }
    var displayName: String { name.trimmed.nilIfEmpty ?? "Untitled stage" }
}

struct StagePlateView: View {
    let stage: ProjectStage
    /// The stage's cuts resolved from the flat timeline, in cutIds order.
    let cuts: [ProjectShot]
    var actions: StagePlateActions

    @State private var isPoolTargeted = false
    @State private var isHoveringHeader = false
    @State private var isConfirmingDelete = false
    @State private var combineReview: StageCombineReviewRequest?
    @State private var hoveredSpineCutId = ""
    /// Which cut's move popover is open (the id-keyed binding idiom).
    @State private var movePopoverCutId: String?
    /// The left cut of the COMBINE seam currently under a droppable drag.
    @State private var isCombineSeamTargeted = ""

    private static let poolColumns = [GridItem(.adaptive(minimum: 196, maximum: 196), spacing: 14, alignment: .topLeading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            plate
            if !cuts.isEmpty || !stage.inputs.isEmpty {
                cutsBlock
            }
        }
        .sheet(item: $combineReview) { request in
            CombinedCutReviewSheet(
                request: request,
                onCancel: { combineReview = nil },
                onCombine: {
                    let cutId = actions.onCombine(request.stageId, request.sourceCutIds)
                    combineReview = nil
                    if !cutId.isEmpty {
                        actions.onOpenCombined(cutId)
                    }
                }
            )
        }
    }

    // MARK: The plate (header + input pool)

    private var plate: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            LazyVGrid(columns: Self.poolColumns, alignment: .leading, spacing: 14) {
                ForEach(stage.inputs) { input in
                    StageInputCard(
                        input: input,
                        sourceStageId: stage.stageId,
                        frame: input.isClip ? nil : actions.frameLookup[input.frameImageId],
                        media: input.isClip ? actions.mediaLookup[input.clipMediaId] : nil,
                        onOpenFrame: actions.onOpenFrame,
                        onToggleKept: actions.onToggleKept,
                        onRetryFrame: actions.onRetryFrame,
                        onRemove: { actions.onRemoveInput(stage.stageId, input) },
                        onDuplicateFrame: actions.onDuplicateFrame
                    )
                }
                newFrameCard
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isPoolTargeted ? CanonColor.softGold.opacity(0.14) : Color.white.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isPoolTargeted ? CanonColor.brass : CanonColor.hairlinePaper, lineWidth: isPoolTargeted ? 2 : 1)
        )
        .dropDestination(for: ShotFrameTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            actions.onGather(stage.stageId, transfer)
            return true
        } isTargeted: { targeted in
            isPoolTargeted = targeted
        }
        // Deliberately NOT also a cut-drop target: stacking a second
        // dropDestination here risks shadowing the frame gathering above, and
        // cross-stage moves are already served by dropping on any of that
        // stage's cut rows, or by "Move to Stage…" when it has none.
        .onHover { isHoveringHeader = $0 }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("STAGE")
                .font(CanonType.archive(9, weight: .semibold))
                .kerning(1.6)
                .foregroundStyle(CanonColor.brass)
            StageNameField(
                stageId: stage.stageId,
                name: stage.name,
                onRename: actions.onRenameStage
            )
            Text(headerCountsLabel)
                .font(CanonType.archive(7.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(CanonColor.muted.opacity(0.8))
            Spacer(minLength: 0)
            Button {
                isConfirmingDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isHoveringHeader ? CanonColor.rust.opacity(0.85) : CanonColor.muted.opacity(0.45))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete this stage")
            .confirmationDialog(
                cuts.isEmpty
                    ? "Delete \(stage.name.trimmed.isEmpty ? "this stage" : stage.name)?"
                    : "Delete \(stage.name.trimmed.isEmpty ? "this stage" : stage.name) and its \(cuts.count) cut\(cuts.count == 1 ? "" : "s")?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Stage", role: .destructive) {
                    actions.onDeleteStage(stage.stageId)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Gathered frames and footage stay in the library, and the cuts move to DELETED CUTS below — nothing is destroyed.")
            }
        }
    }

    private var headerCountsLabel: String {
        let inputsPart = "\(stage.inputs.count) gathered"
        let cutsPart = cuts.isEmpty ? "" : " · \(cuts.count) cut\(cuts.count == 1 ? "" : "s")"
        return (inputsPart + cutsPart).uppercased()
    }

    /// The per-stage "+ NEW FRAME" slot — renders into this stage's palette.
    private var newFrameCard: some View {
        Button {
            actions.onCreateFrame(stage.stageId)
        } label: {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(CanonColor.hairlinePaper.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                .background(RoundedRectangle(cornerRadius: 9).fill(CanonColor.paperInset.opacity(0.25)))
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CanonColor.brass.opacity(0.8))
                        Text("NEW FRAME")
                            .font(CanonType.archive(7.5, weight: .semibold))
                            .kerning(1)
                            .foregroundStyle(CanonColor.muted)
                    }
                )
                .frame(width: 196, height: 110)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Render a new frame onto this stage")
    }

    // MARK: Cuts — outside the plate, tethered to it

    /// Re-arranging a cut is a MENU, not a drag.
    ///
    /// Two drag designs shipped and neither worked in the app — first narrow
    /// spine drop lanes, then whole-row drop targets, on both SwiftUI drop
    /// APIs. Rather than keep guessing at a gesture that cannot be verified
    /// on this machine, the handle on the spine now opens a move popover on
    /// click, right-click, or a drag attempt, so every instinct lands on the
    /// control that actually works. The same items live in the row's context
    /// menu, and both call the same engine op.
    private var cutsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(cuts.enumerated()), id: \.element.shotId) { index, cut in
                HStack(alignment: .top, spacing: 0) {
                    cutSpine(index: index, cut: cut)
                    CutStripView(
                        cut: cut,
                        index: index,
                        poolInputs: stage.inputs,
                        actions: actions.cutActions
                    )
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu {
                    if index < cuts.count - 1 {
                        Button("Combine with Next CUT…") {
                            requestCombine(left: cut, right: cuts[index + 1])
                        }
                    }
                    if index > 0 {
                        Button("Combine with Previous CUT…") {
                            requestCombine(left: cuts[index - 1], right: cut)
                        }
                    }
                    moveMenuItems(index: index, cut: cut)
                }
                if index < cuts.count - 1 {
                    combineSeam(left: cut, right: cuts[index + 1])
                }
            }
            HStack(alignment: .top, spacing: 0) {
                Color.clear
                    .frame(width: 26)
                    .background(TetherElbow(isLast: true).allowsHitTesting(false))
                newCutStrip
                    .padding(.vertical, 6)
            }
        }
        .padding(.leading, 22)
    }

    /// The tether column: the decorative elbow with the move handle seated on
    /// its stub.
    private func cutSpine(index: Int, cut: ProjectShot) -> some View {
        ZStack {
            Color.clear
            cutGrip(index: index, cut: cut)
        }
        .frame(width: 26)
        .background(TetherElbow(isLast: false).allowsHitTesting(false))
    }

    /// The move handle. It is not a drag source — click it, right-click it,
    /// or try to drag it, and all three land on the same popover, because a
    /// control that looks grabbable must do SOMETHING when grabbed.
    private func cutGrip(index: Int, cut: ProjectShot) -> some View {
        let isHovered = hoveredSpineCutId == cut.shotId
        let isOpen = movePopoverCutId == cut.shotId
        return Button {
            movePopoverCutId = cut.shotId
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CanonColor.brass.opacity(isHovered || isOpen ? 0.95 : 0.62))
                .frame(width: 22, height: 22)
                .background(Circle().fill(CanonColor.paper))
                .overlay(
                    Circle().strokeBorder(
                        CanonColor.brass.opacity(isHovered || isOpen ? 0.85 : 0.45),
                        lineWidth: isHovered || isOpen ? 1.4 : 1
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 23)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredSpineCutId = hovering ? cut.shotId : ""
            }
            (hovering ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
        // A drag attempt opens the same popover rather than doing nothing.
        .simultaneousGesture(
            DragGesture(minimumDistance: 3).onChanged { _ in
                if movePopoverCutId != cut.shotId { movePopoverCutId = cut.shotId }
            }
        )
        .contextMenu { moveMenuItems(index: index, cut: cut) }
        .help("Move this cut up or down, or to another stage")
        .popover(isPresented: movePopoverBinding(cut.shotId), arrowEdge: .trailing) {
            cutMovePopover(index: index, cut: cut)
        }
    }

    private func movePopoverBinding(_ cutId: String) -> Binding<Bool> {
        Binding(
            get: { movePopoverCutId == cutId },
            set: { isOpen in movePopoverCutId = isOpen ? cutId : nil }
        )
    }

    private func cutMovePopover(index: Int, cut: ProjectShot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MOVE CUT \(FrameCreatorModal.romanNumeral(index + 1))")
                .font(CanonType.archive(8, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(CanonColor.brass)
            Text(cut.name.trimmed.nilIfEmpty ?? "Untitled cut")
                .font(CanonType.interface(11, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .lineLimit(1)

            VStack(spacing: 4) {
                movePopoverRow(
                    title: "Move to Top",
                    systemImage: "arrow.up.to.line",
                    isEnabled: index > 0,
                    closesPopover: true
                ) {
                    actions.onMoveCut(cut.shotId, stage.stageId, 0)
                }
                movePopoverRow(
                    title: "Move Up",
                    systemImage: "arrow.up",
                    isEnabled: index > 0
                ) {
                    actions.onMoveCut(cut.shotId, stage.stageId, index - 1)
                }
                movePopoverRow(
                    title: "Move Down",
                    systemImage: "arrow.down",
                    isEnabled: index < cuts.count - 1
                ) {
                    // Landing after the next cut means inserting before the
                    // one past it — the pre-removal gap law.
                    actions.onMoveCut(cut.shotId, stage.stageId, index + 2)
                }
                movePopoverRow(
                    title: "Move to Bottom",
                    systemImage: "arrow.down.to.line",
                    isEnabled: index < cuts.count - 1,
                    closesPopover: true
                ) {
                    actions.onMoveCut(cut.shotId, stage.stageId, cuts.count)
                }
            }

            let otherStages = actions.stageDirectory.filter { $0.stageId != stage.stageId }
            if !otherStages.isEmpty {
                Divider()
                Text("MOVE TO STAGE")
                    .font(CanonType.archive(7.5, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(CanonColor.muted)
                VStack(spacing: 4) {
                    ForEach(otherStages) { row in
                        movePopoverRow(
                            title: row.displayName,
                            systemImage: "square.stack.3d.up",
                            isEnabled: true,
                            closesPopover: true
                        ) {
                            actions.onMoveCut(cut.shotId, row.stageId, Int.max)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 236)
        .background(CanonColor.paper)
    }

    /// One popover action. It stays open for the up/down rows so a cut can be
    /// walked several places without reopening the menu each time; a move to
    /// another stage closes it, because the cut has left this plate.
    private func movePopoverRow(
        title: String,
        systemImage: String,
        isEnabled: Bool,
        closesPopover: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            if closesPopover { movePopoverCutId = nil }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 14)
                Text(title)
                    .font(CanonType.interface(12))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isEnabled ? CanonColor.ink : CanonColor.muted.opacity(0.5))
            .padding(.horizontal, 9)
            .frame(height: 26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isEnabled ? CanonColor.paperInset.opacity(0.55) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(CanonColor.hairlinePaper.opacity(isEnabled ? 0.8 : 0.3))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    @ViewBuilder
    private func moveMenuItems(index: Int, cut: ProjectShot) -> some View {
        Divider()
        Button("Move Up") {
            actions.onMoveCut(cut.shotId, stage.stageId, index - 1)
        }
        .disabled(index == 0)
        // Landing after the next cut means inserting before the one past it —
        // the same pre-removal gap law the frame strip uses.
        Button("Move Down") {
            actions.onMoveCut(cut.shotId, stage.stageId, index + 2)
        }
        .disabled(index >= cuts.count - 1)
        if actions.stageDirectory.count > 1 {
            Menu("Move to Stage") {
                ForEach(actions.stageDirectory.filter { $0.stageId != stage.stageId }) { row in
                    Button(row.displayName) {
                        actions.onMoveCut(cut.shotId, row.stageId, Int.max)
                    }
                }
            }
        }
    }

    private func combineSeam(left: ProjectShot, right: ProjectShot) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 26)
            Button {
                requestCombine(left: left, right: right)
            } label: {
                HStack(spacing: 7) {
                    Rectangle()
                        .fill(CanonColor.brass.opacity(isCombineSeamTargeted == left.shotId ? 0.9 : 0.35))
                        .frame(height: 1)
                    Image(systemName: "link")
                        .font(.system(size: 9, weight: .semibold))
                    Text("COMBINE")
                        .font(CanonType.archive(7.5, weight: .bold))
                        .kerning(1)
                    Rectangle()
                        .fill(CanonColor.brass.opacity(isCombineSeamTargeted == left.shotId ? 0.9 : 0.35))
                        .frame(height: 1)
                }
                .foregroundStyle(CanonColor.brass)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isCombineSeamTargeted == left.shotId
                            ? CanonColor.softGold.opacity(0.14)
                            : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Review a local $0 combine of these adjacent CUTs")
            .dropDestination(for: CutTransfer.self) { transfers, _ in
                guard let cutId = transfers.first?.cutId,
                      cutId == left.shotId || cutId == right.shotId else {
                    return false
                }
                requestCombine(left: left, right: right)
                return true
            } isTargeted: { targeted in
                // Only lights for the two cuts it can actually combine, so it
                // never promises a drop it would refuse.
                withAnimation(.easeOut(duration: 0.10)) {
                    isCombineSeamTargeted = targeted ? left.shotId : ""
                }
            }
        }
        .padding(.vertical, 1)
    }

    private func requestCombine(left: ProjectShot, right: ProjectShot) {
        let sourceCutIds = [left.shotId, right.shotId]
        combineReview = StageCombineReviewRequest(
            stageId: stage.stageId,
            sourceCutIds: sourceCutIds,
            preflight: actions.onPreflightCombine(stage.stageId, sourceCutIds)
        )
    }

    @State private var isNewCutTargeted = false

    /// The "first/next cut" affordance: click for an empty cut, or drop a
    /// frame/footage to open one with it.
    private var newCutStrip: some View {
        Button {
            actions.onCreateCut(stage.stageId)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CanonColor.brass.opacity(0.8))
                Text(cuts.isEmpty ? "FIRST CUT — sequence this stage into a video" : "NEW CUT")
                    .font(CanonType.archive(8, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(CanonColor.muted)
            }
            .padding(.horizontal, 14)
            .frame(height: isNewCutTargeted ? 52 : 36)
            .frame(minWidth: 320, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isNewCutTargeted ? CanonColor.softGold.opacity(0.16) : CanonColor.paperInset.opacity(0.25))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isNewCutTargeted ? CanonColor.brass : CanonColor.hairlinePaper.opacity(0.8),
                        style: StrokeStyle(lineWidth: isNewCutTargeted ? 2 : 1, dash: [6, 5])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Start a cut — click for an empty timeline, or drop a frame or footage to open with it")
        .dropDestination(for: ShotFrameTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            actions.onCreateCutWith(stage.stageId, transfer)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.12)) { isNewCutTargeted = targeted }
        }
        .animation(.easeOut(duration: 0.12), value: isNewCutTargeted)
    }
}

/// The brass spine tying a cut strip to its stage plate: a vertical line down
/// the tether column with an elbow stub into the strip's top edge.
private struct TetherElbow: View {
    var isLast: Bool

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let x = proxy.size.width * 0.5
                let elbowY: CGFloat = 34
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: isLast ? elbowY : proxy.size.height))
                path.move(to: CGPoint(x: x, y: elbowY))
                path.addLine(to: CGPoint(x: proxy.size.width, y: elbowY))
            }
            .stroke(CanonColor.brass.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
    }
}

/// Inline rename field for a stage plate's header.
struct StageNameField: View {
    let stageId: String
    let name: String
    let onRename: (String, String) -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Name this stage", text: $draft)
            .textFieldStyle(.plain)
            .font(CanonType.editorial(17, weight: .semibold))
            .foregroundStyle(CanonColor.ink)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commit()
                }
            }
            .onAppear { draft = name }
            .onChange(of: name) { _, newValue in
                if !isFocused {
                    draft = newValue
                }
            }
    }

    private func commit() {
        guard draft.trimmed != name.trimmed else { return }
        onRename(stageId, draft)
    }
}

// MARK: - Stage input card (one gathered reference on the palette)

/// Lighter than the theater's compositeCard on purpose: the palette is a
/// gathering surface. Deep frame work (reframe, versions, animate) rides the
/// tap-through preview modal; failed renders keep their RETRY right here.
struct StageInputCard: View {
    let input: StageInput
    /// The owning stage — rides the drag payload so a drop on another stage
    /// MOVES the reference instead of duplicating it.
    var sourceStageId: String = ""
    let frame: ProjectLensHeroImage?
    let media: MediaItemRecord?
    var onOpenFrame: (ProjectLensHeroImage) -> Void = { _ in }
    var onToggleKept: (ProjectLensHeroImage) -> Void = { _ in }
    var onRetryFrame: (ProjectLensHeroImage) -> Void = { _ in }
    var onRemove: () -> Void = {}
    var onDuplicateFrame: (ProjectLensHeroImage) -> Void = { _ in }

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            thumbnail
                .frame(width: 196, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            overlays
        }
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    frame?.status == "failed" ? CanonColor.rust.opacity(0.7) : CanonColor.hairlinePaper.opacity(0.9),
                    lineWidth: 1
                )
        )
        .onHover { isHovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            if let frame, frame.status == "ready" {
                onOpenFrame(frame)
            }
        }
        .draggable(ShotFrameTransfer(
            frameImageId: input.frameImageId,
            clipMediaId: input.clipMediaId,
            sourceStageId: sourceStageId,
            sourceInputId: input.inputId
        ))
        .contextMenu {
            if let frame {
                FrameActionsMenu(frame: frame, onDuplicate: onDuplicateFrame)
            }
        }
        .help(input.isClip ? "Footage — drag into a cut to place it verbatim" : "")
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            CanonColor.mediaCardHover
            if let frame {
                if frame.status == "ready", !frame.imagePath.trimmed.isEmpty,
                   let image = StripThumbnailCache.shared.image(path: frame.imagePath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if frame.status == "generating" || frame.status == "queued" {
                    VStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(frame.status == "generating" ? "RENDERING" : "QUEUED")
                            .font(CanonType.archive(7, weight: .semibold))
                            .kerning(0.6)
                            .foregroundStyle(CanonColor.muted)
                    }
                } else if frame.status == "failed" {
                    VStack(spacing: 6) {
                        Text(frame.errorMessage.trimmed.nilIfEmpty ?? "Render failed")
                            .font(CanonType.interface(9.5))
                            .foregroundStyle(CanonColor.bone.opacity(0.85))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            // Two lines cannot hold a quoted refusal
                            // explanation; keep the full message on hover.
                            .help(frame.errorMessage.trimmed.nilIfEmpty ?? "Render failed")
                        Button {
                            onRetryFrame(frame)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 8, weight: .semibold))
                                Text("RETRY")
                                    .font(CanonType.archive(7.5, weight: .bold))
                                    .kerning(0.6)
                            }
                            .foregroundStyle(CanonColor.rust)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Capsule().fill(CanonColor.rust.opacity(0.12)))
                            .overlay(Capsule().stroke(CanonColor.rust.opacity(0.5), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    placeholderGlyph(icon: "photo", label: "PLANNED")
                }
            } else if input.isClip {
                if let media,
                   let image = (media.videoStripPath.flatMap { StripThumbnailCache.shared.image(path: $0) })
                    ?? StripThumbnailCache.shared.image(path: media.thumbnailPath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholderGlyph(icon: "film.stack", label: "MISSING FOOTAGE")
                }
            } else {
                placeholderGlyph(icon: "questionmark.square.dashed", label: "MISSING FRAME")
            }
            if input.isClip {
                VStack {
                    HStack {
                        Image(systemName: "film")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(CanonColor.bone)
                            .padding(4)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .padding(5)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .clipped()
    }

    private func placeholderGlyph(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CanonColor.muted.opacity(0.75))
            Text(label)
                .font(CanonType.archive(7, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(CanonColor.muted)
        }
    }

    @ViewBuilder
    private var overlays: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(alignment: .top) {
                if let frame {
                    HStack(spacing: 4) {
                        if frame.reframe != nil {
                            badge(icon: "arrow.down.right.and.arrow.up.left", text: "REFRAME")
                        }
                    }
                    .padding(5)
                }
                Spacer()
                if isHovering {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(CanonColor.bone)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .padding(5)
                    .help("Remove from this stage — the \(input.isClip ? "footage" : "frame") stays in the library")
                } else if let frame, frame.kept == true {
                    starGlyph(frame)
                }
            }
            Spacer()
            HStack(alignment: .bottom) {
                if let frame, !frame.label.trimmed.isEmpty {
                    caption(frame.label)
                } else if let media {
                    caption(media.filename)
                }
                Spacer()
                if isHovering, let frame, frame.status == "ready" {
                    starGlyph(frame)
                }
            }
            .padding(6)
        }
        .frame(width: 196, height: 110)
    }

    private func starGlyph(_ frame: ProjectLensHeroImage) -> some View {
        Button {
            onToggleKept(frame)
        } label: {
            Image(systemName: frame.kept == true ? "star.fill" : "star")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(frame.kept == true ? CanonColor.softGold : CanonColor.bone)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .padding(3)
        .help(frame.kept == true ? "Kept — click to release" : "Keep this frame")
    }

    private func badge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .bold))
            Text(text)
                .font(CanonType.archive(6.5, weight: .bold))
                .kerning(0.5)
        }
        .foregroundStyle(CanonColor.bone)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.55)))
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(CanonType.archive(7.5, weight: .semibold))
            .kerning(0.4)
            .foregroundStyle(CanonColor.bone)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.black.opacity(0.45)))
    }
}

/// One stage offered by a "Gather on …" context menu.
struct StageGatherTarget: Identifiable {
    let id: String
    let title: String
}

/// The frame right-click action panel — one action today, built as the home
/// for more. Ready frames only.
struct FrameActionsMenu: View {
    let frame: ProjectLensHeroImage
    var onDuplicate: (ProjectLensHeroImage) -> Void = { _ in }

    var body: some View {
        if frame.status == "ready" {
            Button {
                onDuplicate(frame)
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
        }
    }
}

/// First placed material wins: a frame's still, else footage's poster. Shared
/// by the FINALS shelf and the DELETED CUTS shelf.
func cutPosterImage(
    for cut: ProjectShot,
    frameLookup: [String: ProjectLensHeroImage],
    mediaLookup: [String: MediaItemRecord]
) -> NSImage? {
    for entry in cut.entries {
        if !entry.frameImageId.isEmpty,
           let frame = frameLookup[entry.frameImageId],
           frame.status == "ready",
           !frame.imagePath.trimmed.isEmpty,
           let image = StripThumbnailCache.shared.image(path: frame.imagePath) {
            return image
        }
        if entry.isClip,
           let media = mediaLookup[entry.clipMediaId],
           let image = StripThumbnailCache.shared.image(path: media.thumbnailPath) {
            return image
        }
    }
    return nil
}

// MARK: - Deleted cuts shelf (soft-deleted, restore-only)

struct DeletedCutRow: Identifiable {
    let trashed: TrashedCut
    /// Resolved timeline row; nil only in a transient reconcile window.
    let cut: ProjectShot?

    var id: String { trashed.entryId }
}

/// The recoverable home of trashed cuts: collapsed to one quiet strip, and
/// even expanded it stays an archive — posters, provenance, RESTORE. No
/// purge: renders are paid artifacts and provenance is kept forever.
struct DeletedCutsShelfView: View {
    let rows: [DeletedCutRow]
    var frameLookup: [String: ProjectLensHeroImage] = [:]
    var mediaLookup: [String: MediaItemRecord] = [:]
    var onRestore: (String) -> Void = { _ in }

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CanonColor.muted.opacity(0.7))
                    Text("DELETED CUTS (\(rows.count))")
                        .font(CanonType.archive(8.5, weight: .semibold))
                        .kerning(1.4)
                        .foregroundStyle(CanonColor.muted)
                    Text("restorable — renders kept")
                        .font(CanonType.interface(10.5))
                        .foregroundStyle(CanonColor.muted.opacity(0.7))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse" : "Show the deleted cuts")
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { row in
                        deletedRow(row)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CanonColor.paperInset.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(CanonColor.hairlinePaper.opacity(0.7), lineWidth: 1)
        )
    }

    private func deletedRow(_ row: DeletedCutRow) -> some View {
        HStack(spacing: 12) {
            ZStack {
                CanonColor.mediaCardHover
                if let cut = row.cut,
                   let poster = cutPosterImage(for: cut, frameLookup: frameLookup, mediaLookup: mediaLookup) {
                    Image(nsImage: poster)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CanonColor.muted.opacity(0.6))
                }
            }
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlinePaper.opacity(0.8), lineWidth: 1))
            .opacity(0.85)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.cut?.name.trimmed.nilIfEmpty ?? "Untitled cut")
                    .font(CanonType.interface(11.5, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.8))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !row.trashed.formerStageName.trimmed.isEmpty {
                        Text("FORMERLY \(row.trashed.formerStageName.uppercased())")
                            .font(CanonType.archive(7, weight: .semibold))
                            .kerning(0.8)
                            .foregroundStyle(CanonColor.muted.opacity(0.75))
                            .lineLimit(1)
                    }
                    if row.cut?.renderArtifact?.status == "ready" {
                        Text("· RENDER KEPT")
                            .font(CanonType.archive(7, weight: .semibold))
                            .kerning(0.8)
                            .foregroundStyle(CanonColor.olive.opacity(0.85))
                    }
                }
            }
            Spacer(minLength: 0)
            Button {
                onRestore(row.trashed.entryId)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 8, weight: .semibold))
                    Text("RESTORE")
                        .font(CanonType.archive(7.5, weight: .bold))
                        .kerning(0.6)
                }
                .foregroundStyle(CanonColor.brass)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(CanonColor.brass.opacity(0.10)))
                .overlay(Capsule().stroke(CanonColor.brass.opacity(0.45), lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Restore this cut to \(row.trashed.formerStageName.trimmed.isEmpty ? "a stage" : row.trashed.formerStageName)")
        }
    }
}

// MARK: - Finals shelf (the picked cuts)

struct FinalsShelfEntry: Identifiable {
    let entry: StageFinalsEntry
    let cut: ProjectShot

    var id: String { entry.entryId }
}

/// The selection step of the pipeline: gather (stage) → sequence (cuts) →
/// pick (FINALS). Cuts drag in by their rail numeral; order is the shelf's
/// own, independent of stage order.
struct FinalsShelfView: View {
    let entries: [FinalsShelfEntry]
    var frameLookup: [String: ProjectLensHeroImage] = [:]
    var mediaLookup: [String: MediaItemRecord] = [:]
    /// Resolves the owning stage's display name for a cut's subtitle.
    var stageNameForCut: (String) -> String = { _ in "" }
    var onOpenCut: (String) -> Void = { _ in }
    var onRemoveEntry: (String) -> Void = { _ in }
    /// (cutId, insertion index or nil-for-append) — adds a new pick or moves
    /// an existing one; the workbench resolves which.
    var onDropCut: (String, Int?) -> Void = { _, _ in }
    /// Opens THE FINALS REEL — the shelf's order as one playable film.
    var onPlayReel: (() -> Void)? = nil

    @State private var isShelfTargeted = false
    @State private var targetedEntryId = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("FINALS")
                    .font(CanonType.archive(9, weight: .semibold))
                    .kerning(1.6)
                    .foregroundStyle(CanonColor.brass)
                Text(entries.isEmpty
                    ? "Drag a cut here when it's picked"
                    : "\(entries.count) picked cut\(entries.count == 1 ? "" : "s")")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted.opacity(0.85))
                Spacer(minLength: 0)
                if !entries.isEmpty, let onPlayReel {
                    Button {
                        onPlayReel()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 7, weight: .bold))
                            Text("PLAY REEL")
                                .font(CanonType.archive(7.5, weight: .semibold))
                                .kerning(1)
                        }
                        .foregroundStyle(CanonColor.brass)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(RoundedRectangle(cornerRadius: 4).fill(CanonColor.paperInset.opacity(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(CanonColor.brass.opacity(0.7), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help("Play this shelf's order as one film — the FINALS REEL: crossfades, a music bed, and one-click export. Free; unrendered picks are named and skipped.")
                }
            }
            if entries.isEmpty {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isShelfTargeted ? CanonColor.brass : CanonColor.hairlinePaper.opacity(0.8),
                        style: StrokeStyle(lineWidth: isShelfTargeted ? 2 : 1, dash: [6, 5])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isShelfTargeted ? CanonColor.softGold.opacity(0.14) : CanonColor.paperInset.opacity(0.2))
                    )
                    .frame(height: 44)
                    .overlay(
                        Text("THE PICKED TAKES LAND HERE")
                            .font(CanonType.archive(7.5, weight: .semibold))
                            .kerning(1)
                            .foregroundStyle(CanonColor.muted.opacity(0.7))
                    )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(entries) { shelfEntry in
                            finalsCard(shelfEntry)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isShelfTargeted ? CanonColor.softGold.opacity(0.10) : Color.white.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isShelfTargeted ? CanonColor.brass.opacity(0.8) : CanonColor.hairlinePaper.opacity(0.9), lineWidth: 1)
        )
        .dropDestination(for: CutTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            onDropCut(transfer.cutId, nil)
            return true
        } isTargeted: { targeted in
            isShelfTargeted = targeted
        }
    }

    private func finalsCard(_ shelfEntry: FinalsShelfEntry) -> some View {
        let cut = shelfEntry.cut
        let stageName = stageNameForCut(cut.shotId)
        let isTargeted = targetedEntryId == shelfEntry.id
        return VStack(alignment: .leading, spacing: 5) {
            ZStack {
                posterThumbnail(for: cut)
                    .frame(width: 150, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if cut.playableRenderVersion?.isReady == true {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.black.opacity(0.5)))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isTargeted ? CanonColor.brass : CanonColor.hairlinePaper.opacity(0.9), lineWidth: isTargeted ? 2 : 1)
            )
            Text(cut.name.trimmed.isEmpty ? "Untitled cut" : cut.name)
                .font(CanonType.interface(11, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            if !stageName.isEmpty {
                Text(stageName.uppercased())
                    .font(CanonType.archive(7, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(CanonColor.muted.opacity(0.8))
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenCut(cut.shotId)
        }
        .help(cut.playableRenderVersion?.isReady == true ? "Open this cut's player" : "Open this cut — render it to watch")
        .draggable(CutTransfer(cutId: cut.shotId))
        .contextMenu {
            Button("Remove from FINALS") {
                onRemoveEntry(shelfEntry.id)
            }
        }
        .dropDestination(for: CutTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            guard transfer.cutId != cut.shotId else { return false }
            onDropCut(transfer.cutId, entries.firstIndex(where: { $0.id == shelfEntry.id }))
            return true
        } isTargeted: { targeted in
            targetedEntryId = targeted ? shelfEntry.id : (targetedEntryId == shelfEntry.id ? "" : targetedEntryId)
        }
    }

    @ViewBuilder
    private func posterThumbnail(for cut: ProjectShot) -> some View {
        ZStack {
            CanonColor.mediaCardHover
            if let poster = cutPosterImage(for: cut, frameLookup: frameLookup, mediaLookup: mediaLookup) {
                Image(nsImage: poster)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "film")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CanonColor.muted.opacity(0.7))
            }
        }
        .clipped()
    }
}

// MARK: - New stage affordances

/// The trailing "+ NEW STAGE" strip under the stage column: click for an
/// empty stage, or drop a frame/footage to found one holding it.
struct NewStageStrip: View {
    var isFirstStage: Bool
    var onCreate: () -> Void
    var onCreateWith: (ShotFrameTransfer) -> Void = { _ in }

    @State private var isTargeted = false

    var body: some View {
        Button(action: onCreate) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CanonColor.brass.opacity(0.85))
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEW STAGE")
                        .font(CanonType.archive(9, weight: .semibold))
                        .kerning(1.4)
                        .foregroundStyle(CanonColor.muted)
                    if isFirstStage {
                        Text("Gather frames and footage loosely, then cut them into videos — drop anything here to begin.")
                            .font(CanonType.interface(11))
                            .foregroundStyle(CanonColor.muted.opacity(0.85))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: isFirstStage ? 88 : (isTargeted ? 72 : 52))
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isTargeted ? CanonColor.softGold.opacity(0.16) : CanonColor.paperInset.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isTargeted ? CanonColor.brass : CanonColor.hairlinePaper.opacity(0.85),
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [7, 6])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Found a new stage — click for an empty one, or drop a frame or footage onto it")
        .dropDestination(for: ShotFrameTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            onCreateWith(transfer)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.12)) { isTargeted = targeted }
        }
    }
}
