import SwiftUI

/// The shared Scene tail picker used by the row and the Shot editor. Both
/// surfaces use the same inventory, eligibility, and engine action wiring.
struct ShotTailPickerMenu: View {
    let cut: ProjectShot
    let poolInputs: [StageInput]
    var actions: CutStripActions
    var isPreparingContinuation = false
    var continuationPreparationMessage = ""
    var onAI: () -> Void
    var onClose: () -> Void
    @State private var appendSearchQuery = ""
    private var isBusy: Bool { actions.videoOperationShotIds.contains(cut.shotId) }
    private var isLocked: Bool { isBusy || cut.hasFrozenSourceSequence }
    private var isSuffixAppendable: Bool { !isBusy && shotSuffixTailStartIndex(shot: cut) != nil }
    private var tailActionLabel: String { cut.entries.isEmpty ? "START SCENE" : (cut.hasSavedPlayback ? "EXTEND SCENE" : "ADD TO SCENE") }
    var body: some View {
        let query = appendSearchQuery.trimmed.lowercased()
        let candidates = poolInputs.filter { input in
            guard !query.isEmpty else { return true }
            if input.isClip {
                return actions.mediaLookup[input.clipMediaId]?.filename.lowercased().contains(query) == true
            }
            guard let frame = actions.frameLookup[input.frameImageId] else { return false }
            return frame.label.lowercased().contains(query)
                || frame.prompt.lowercased().contains(query)
        }
        let placedFrameIds = Set(cut.entries.map(\.frameImageId).filter { !$0.isEmpty })
        let placedClipIds = Set(cut.entries.map(\.clipMediaId).filter { !$0.isEmpty })
        let unplaced = candidates.filter { input in
            input.isClip ? !placedClipIds.contains(input.clipMediaId) : !placedFrameIds.contains(input.frameImageId)
        }
        let placed = candidates.filter { input in
            input.isClip ? placedClipIds.contains(input.clipMediaId) : placedFrameIds.contains(input.frameImageId)
        }
        let coarseAvailability = actions.continuationAvailability(cut.shotId)
        let hardLocked = isLocked && !isSuffixAppendable
        return VStack(alignment: .leading, spacing: 10) {
            Text(tailActionLabel)
                .font(CanonType.archive(8, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(CanonColor.muted)
            if !cut.entries.isEmpty {
                Button {
                    onAI()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cut.hasSavedPlayback ? "CONTINUE WITH AI" : "ANIMATE LAST FRAME")
                                .font(CanonType.archive(8.5, weight: .bold))
                                .kerning(0.7)
                            Text("Review the exact endpoint, method, direction, and price")
                                .font(CanonType.interface(9.5))
                                .foregroundStyle(CanonColor.muted)
                        }
                        Spacer()
                        if isPreparingContinuation {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .padding(10)
                    .frame(width: 548, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7).fill(CanonColor.softGold.opacity(0.22)))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.brass.opacity(0.75)))
                }
                .buttonStyle(.plain)
                .disabled(coarseAvailability.lockReason != nil || isPreparingContinuation)
                if let reason = coarseAvailability.lockReason {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(reason.message)
                            .font(CanonType.interface(9.5))
                            .foregroundStyle(CanonColor.rust)
                        if let repair = reason.repairLabel {
                            Button(repair) {
                                onClose()
                                if reason == .activeLook {
                                    actions.onShowOriginal(cut.shotId)
                                } else if reason == .staleChain {
                                    actions.onRequestRerender(cut.shotId)
                                } else {
                                    actions.onOpenShotVideo(cut.shotId)
                                }
                            }
                            .buttonStyle(PlateButtonStyle())
                        }
                    }
                    .frame(width: 548, alignment: .leading)
                }
            }
            if !continuationPreparationMessage.isEmpty {
                Text(continuationPreparationMessage)
                    .font(CanonType.interface(9.5))
                    .foregroundStyle(CanonColor.rust)
                    .frame(width: 548, alignment: .leading)
            }
            Divider()
            Button {
                onClose()
                actions.onCreateFrameForCut(cut.shotId)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles.rectangle.stack")
                    Text("CREATE FRAME WITH AI")
                        .font(CanonType.archive(8.5, weight: .bold))
                        .kerning(0.6)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(CanonColor.brass)
            .disabled(hardLocked || isBusy)
            .help(hardLocked
                ? "Create a NEW VERSION before appending a Frame to this rendered Scene"
                : "Open the Frame Creator; the finished Frame lands at this Scene's tail")
            Text("ADD FRAME OR FOOTAGE")
                .font(CanonType.archive(7.5, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(CanonColor.muted)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
                TextField("Search Frames and Footage", text: $appendSearchQuery)
                    .textFieldStyle(.plain)
                    .font(CanonType.interface(11))
            }
            .padding(.horizontal, 8)
            .frame(width: 548, height: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlinePaper.opacity(0.8)))
            if candidates.isEmpty {
                Text(poolInputs.isEmpty
                    ? "No source material yet — render a new Frame below."
                    : "No Frames or Footage match this search.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
                    .frame(width: 300, alignment: .leading)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 102, maximum: 102), spacing: 8)], spacing: 10) {
                        ForEach(unplaced + placed) { input in
                            appendPickerThumb(input, alreadyPlaced: placed.contains(input))
                        }
                    }
                }
                .frame(width: 548, height: min(CGFloat((candidates.count + 4) / 5) * 84 + 8, 344))
            }
            if hardLocked {
                Text("Frames and Footage require NEW VERSION; AI can continue the immutable rendered Original directly.")
                    .font(CanonType.interface(9))
                    .foregroundStyle(CanonColor.muted)
                    .frame(width: 548, alignment: .leading)
            }
        }
        .padding(14)
        .background(CanonColor.paper)
    }


    private func appendPickerThumb(_ input: StageInput, alreadyPlaced: Bool) -> some View {
        let frame = input.isClip ? nil : actions.frameLookup[input.frameImageId]
        let media = input.isClip ? actions.mediaLookup[input.clipMediaId] : nil
        let path = frame?.imagePath ?? media?.thumbnailPath ?? ""
        return Button {
            onClose()
            actions.onAppendPoolInput(cut.shotId, input)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .bottomLeading) {
                    if let image = StripThumbnailCache.shared.image(path: path) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else { Rectangle().fill(CanonColor.paperInset).overlay(Image(systemName: input.isClip ? "film" : "photo")) }
                    if alreadyPlaced { Text("IN SHOT").font(.caption2).padding(3).background(CanonColor.paper) }
                }.frame(width: 102, height: 57).clipped()
                Text(frame?.label ?? media?.filename ?? "Source material").font(.caption2).lineLimit(1).frame(width: 102, alignment: .leading)
            }
        }.buttonStyle(.plain)
            .disabled(isBusy || (!input.isClip && frame?.status != "ready") || (isLocked && !isSuffixAppendable))
            .help(isLocked && !isSuffixAppendable ? "Create a New Version before appending source material" : "Append to this Shot")
    }
}
