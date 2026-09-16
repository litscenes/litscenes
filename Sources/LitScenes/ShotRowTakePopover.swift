import SwiftUI

/// A row preview that knows which take it is, so the player's chip can say so.
func shotRowTakePreview(tile: ShotRowVideoTile, option: ShotTakeOption, takeCount: Int) -> ShotSegmentPreview? {
    guard let clip = option.clip, option.isReady else { return nil }
    return ShotSegmentPreview(clip: clip, take: ShotTakePreviewContext(
        placementKey: option.placementKey,
        label: "SEGMENT \(tile.ordinal)",
        takeNumber: option.takeNumber,
        takeCount: takeCount,
        isInFilm: option.isInFilm,
        source: option.source
    ))
}

/// The Scene row's take strip for an ordinary segment: preview opens the
/// player on that take; USE puts it in the film through the same law the
/// player uses, with the same downstream-impact confirmation.
struct ShotRowTakePopover: View {
    let cut: ProjectShot
    let tile: ShotRowVideoTile
    var actions: CutStripActions
    var onClose: () -> Void
    @State private var pendingImpact: ShotTakeImpactPrompt?

    private var options: [ShotTakeOption] {
        tile.segment.map { shotTakeOptions(shot: cut, segment: $0) } ?? []
    }

    private var isRendering: Bool {
        actions.videoOperationShotIds.contains(cut.shotId) || actions.isVideoOperationActive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                PlateLabel(text: "Takes", size: 9, weight: .bold, color: PlateColor.ink)
                PlateLabel(text: "\(options.count) retained", size: 7.5, color: PlateColor.inkFaint)
                Spacer(minLength: 0)
                Button("Close", action: onClose).buttonStyle(PlateButtonStyle())
            }
            ShotSegmentTakeStrip(
                options: options,
                isRenderBlocked: isRendering,
                onPreview: previewTake,
                onUse: useTake
            )
            Text("Preview opens the player on that take. Use puts it in the film for $0; ⌘Z brings the current take back.")
                .font(PlateType.label(9.5, weight: .regular))
                .foregroundStyle(PlateColor.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 460)
        .background(PlateColor.cream)
        .environment(\.colorScheme, .light)
        .modifier(ShotTakeImpactDialog(
            prompt: $pendingImpact,
            rechainEstimate: { actions.continuationEntryEstimate(cut.shotId, $0) },
            isRendering: isRendering,
            onUse: { option in actions.onUseShotSegmentTake(cut.shotId, option.placementKey, option.clipPath) },
            onUseAndRechain: { option, _ in
                actions.onUseShotSegmentTake(cut.shotId, option.placementKey, option.clipPath)
                Task { _ = await actions.onRechainContinuations(cut.shotId) }
            }
        ))
    }

    private func previewTake(_ option: ShotTakeOption) {
        guard let preview = shotRowTakePreview(tile: tile, option: option, takeCount: options.count) else { return }
        actions.onPreviewShotSegment(cut.shotId, preview)
    }

    private func useTake(_ option: ShotTakeOption) {
        guard let impact = actions.shotSegmentTakeImpact(cut.shotId, option.placementKey, option.clipPath) else { return }
        if case .selectCurrent = impact.resolution {
            actions.onUseShotSegmentTake(cut.shotId, option.placementKey, option.clipPath)
        } else {
            pendingImpact = ShotTakeImpactPrompt(option: option, resolution: impact.resolution)
        }
    }
}
