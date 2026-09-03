import SwiftUI

/// Dependencies for the flat Scenes workspace. The canonical timeline owns
/// order, trash, and reversible combined groups; no Stage document is read or
/// written by these gestures.
struct FlatShotsCanvasActions {
    var sourceInputs: [StageInput] = []
    var cutActions = CutStripActions()
    var onCreateShot: () -> Void = {}
    var onCreateShotWith: (ShotFrameTransfer) -> Void = { _ in }
    var onMoveShot: (String, Int) -> Void = { _, _ in }
    var onPreflightCombine: ([String]) -> CombinedCutPreflight = {
        CombinedCutPreflight(sourceCutIds: $0)
    }
    var onCombine: ([String]) -> String = { _ in "" }
    var onOpenCombined: (String) -> Void = { _ in }
}

struct FlatShotsCanvasView: View {
    let shots: [ProjectShot]
    var actions: FlatShotsCanvasActions

    @State private var combineReview: StageCombineReviewRequest?
    @State private var isNewShotTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("SHOTS")
                    .font(CanonType.archive(9, weight: .semibold))
                    .kerning(1.6)
                    .foregroundStyle(CanonColor.brass)
                Text(shots.isEmpty
                    ? "Build an ordered sequence from Frames and Footage"
                    : "\(shots.count) ordered Shot\(shots.count == 1 ? "" : "s")")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted.opacity(0.85))
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(shots.enumerated()), id: \.element.shotId) { index, shot in
                    shotRow(shot, index: index)
                    if index < shots.count - 1 {
                        combineSeam(left: shot, right: shots[index + 1])
                    }
                }
                newShotStrip
                    .padding(.top, shots.isEmpty ? 0 : 8)
            }
        }
        .sheet(item: $combineReview) { request in
            CombinedCutReviewSheet(
                request: request,
                onCancel: { combineReview = nil },
                onCombine: {
                    let shotId = actions.onCombine(request.sourceCutIds)
                    combineReview = nil
                    if !shotId.isEmpty { actions.onOpenCombined(shotId) }
                }
            )
        }
    }

    private func shotRow(_ shot: ProjectShot, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            moveMenu(shot, index: index)
                .padding(.top, 23)
            CutStripView(
                cut: shot,
                index: index,
                poolInputs: actions.sourceInputs,
                actions: actions.cutActions
            )
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            if index < shots.count - 1 {
                Button("Combine with Next Shot…") {
                    requestCombine(left: shot, right: shots[index + 1])
                }
            }
            if index > 0 {
                Button("Combine with Previous Shot…") {
                    requestCombine(left: shots[index - 1], right: shot)
                }
            }
            Divider()
            Button("Move Up") { actions.onMoveShot(shot.shotId, index - 1) }
                .disabled(index == 0)
            Button("Move Down") { actions.onMoveShot(shot.shotId, index + 2) }
                .disabled(index >= shots.count - 1)
        }
    }

    private func moveMenu(_ shot: ProjectShot, index: Int) -> some View {
        Menu {
            Button("Move to Top") { actions.onMoveShot(shot.shotId, 0) }
                .disabled(index == 0)
            Button("Move Up") { actions.onMoveShot(shot.shotId, index - 1) }
                .disabled(index == 0)
            Button("Move Down") { actions.onMoveShot(shot.shotId, index + 2) }
                .disabled(index >= shots.count - 1)
            Button("Move to Bottom") { actions.onMoveShot(shot.shotId, shots.count) }
                .disabled(index >= shots.count - 1)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CanonColor.brass.opacity(0.78))
                .frame(width: 24, height: 24)
                .background(Circle().fill(CanonColor.paper))
                .overlay(Circle().stroke(CanonColor.brass.opacity(0.5), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26)
        .help("Reorder this Shot")
    }

    private func combineSeam(left: ProjectShot, right: ProjectShot) -> some View {
        HStack(spacing: 7) {
            Rectangle().fill(CanonColor.brass.opacity(0.32)).frame(height: 1)
            Button {
                requestCombine(left: left, right: right)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text("COMBINE")
                        .font(CanonType.archive(7.5, weight: .bold))
                        .kerning(1)
                }
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(CanonColor.brass)
            }
            .buttonStyle(.plain)
            .help("Review a local $0 combine of these adjacent Shots")
            Rectangle().fill(CanonColor.brass.opacity(0.32)).frame(height: 1)
        }
        .padding(.leading, 34)
        .padding(.vertical, 1)
    }

    private func requestCombine(left: ProjectShot, right: ProjectShot) {
        let ids = [left.shotId, right.shotId]
        combineReview = StageCombineReviewRequest(
            stageId: "",
            sourceCutIds: ids,
            preflight: actions.onPreflightCombine(ids)
        )
    }

    private var newShotStrip: some View {
        Button(action: actions.onCreateShot) {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text(shots.isEmpty ? "FIRST SHOT — start an ordered video sequence" : "NEW SHOT")
                    .font(CanonType.archive(8.5, weight: .semibold))
                    .kerning(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(CanonColor.brass.opacity(0.86))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: isNewShotTargeted ? 58 : 44)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(isNewShotTargeted ? CanonColor.softGold.opacity(0.16) : CanonColor.paperInset.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .strokeBorder(
                        isNewShotTargeted ? CanonColor.brass : CanonColor.hairlinePaper.opacity(0.85),
                        style: StrokeStyle(lineWidth: isNewShotTargeted ? 2 : 1, dash: [7, 6])
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Create an empty Shot, or drop a Frame or Footage item to start with it")
        .dropDestination(for: ShotFrameTransfer.self) { transfers, _ in
            guard let transfer = transfers.first else { return false }
            actions.onCreateShotWith(transfer)
            return true
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.12)) { isNewShotTargeted = targeted }
        }
    }
}

struct DeletedShotRow: Identifiable {
    let trashed: TrashedShot
    let shot: ProjectShot?
    var id: String { trashed.entryId }
}

struct DeletedShotsShelfView: View {
    let rows: [DeletedShotRow]
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
                    Text("DELETED SHOTS (\(rows.count))")
                        .font(CanonType.archive(8.5, weight: .semibold))
                        .kerning(1.4)
                    Text("restorable — renders kept")
                        .font(CanonType.interface(10.5))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(CanonColor.muted.opacity(0.78))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(rows) { row in
                    HStack(spacing: 12) {
                        ZStack {
                            CanonColor.mediaCardHover
                            if let shot = row.shot,
                               let poster = cutPosterImage(
                                   for: shot,
                                   frameLookup: frameLookup,
                                   mediaLookup: mediaLookup
                               ) {
                                Image(nsImage: poster).resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Image(systemName: "film")
                                    .foregroundStyle(CanonColor.muted.opacity(0.6))
                            }
                        }
                        .frame(width: 96, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.shot?.name.trimmed.nilIfEmpty ?? "Untitled Shot")
                                .font(CanonType.interface(11.5, weight: .semibold))
                                .foregroundStyle(CanonColor.ink.opacity(0.8))
                            if row.shot?.renderArtifact?.status == "ready" {
                                Text("RENDER KEPT")
                                    .font(CanonType.archive(7, weight: .semibold))
                                    .foregroundStyle(CanonColor.olive.opacity(0.85))
                            }
                        }
                        Spacer(minLength: 0)
                        Button("RESTORE") { onRestore(row.trashed.entryId) }
                            .buttonStyle(.plain)
                            .font(CanonType.archive(7.5, weight: .bold))
                            .foregroundStyle(CanonColor.brass)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(CanonColor.paperInset.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(CanonColor.hairlinePaper.opacity(0.7)))
    }
}
