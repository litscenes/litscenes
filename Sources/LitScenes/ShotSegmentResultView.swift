import SwiftUI
import AppKit

/// Controls wrap as whole controls, never as individual letters.
struct ShotEditorFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews, width: proposal.width ?? 460).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = layout(subviews, width: bounds.width).positions
        for (index, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + positions[index].x, y: bounds.minY + positions[index].y),
                       anchor: .topLeading, proposal: .unspecified)
        }
    }
    private func layout(_ views: Subviews, width: CGFloat) -> (size: CGSize, positions: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        var positions: [CGPoint] = []
        for view in views {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += height + spacing; height = 0 }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            height = max(height, size.height)
        }
        return (CGSize(width: width, height: y + height), positions)
    }
}

struct ShotSegmentVideoThumbnail: View {
    let preview: ShotSegmentPreview?
    var width: CGFloat = 128
    var height: CGFloat = 72
    @StateObject private var loader = ShotFilmstripLoader()
    private var sample: Double {
        guard let preview else { return 0 }
        return preview.sourceStartSeconds + max(preview.durationSeconds / 2, 0)
    }
    private var index: Int { Int((sample * 24).rounded()) }
    private var path: String { preview?.clip.clipPath ?? "" }
    var body: some View {
        let _ = loader.revision
        ZStack {
            PlateColor.creamDeep
            if let tile = loader.tile(clipPath: path, rung: 1.0 / 24.0, rungIndex: index, heightPixels: 160) {
                Image(nsImage: tile).resizable().scaledToFit()
            } else {
                Image(systemName: "film").foregroundStyle(PlateColor.inkFaint)
            }
            if preview != nil {
                Image(systemName: "play.circle.fill").font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.9), .black.opacity(0.45))
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .overlay(Rectangle().stroke(PlateColor.hairline))
        .task(id: "\(path)|\(index)") {
            guard !path.isEmpty else { return }
            loader.requestTiles([ShotFilmstripTile(clipPath: path, fileSeconds: sample,
                x: 0, width: 128, rungIndex: index)], rung: 1.0 / 24.0, heightPixels: 160)
        }
    }
}

struct ShotSegmentResultView: View {
    let result: ShotSegmentPresentation
    let ordinal: String
    var isFocused = false
    var isStale = false
    var onSelect: () -> Void
    var onPreview: () -> Void
    var onTakes: () -> Void
    var onCopy: () -> Void = {}
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(ordinal) · \(result.title)".uppercased())
                .font(PlateType.label(9, weight: .semibold)).foregroundStyle(PlateColor.inkFaint)
            HStack(alignment: .top, spacing: 10) {
                Button(action: onSelect) { ShotSegmentStatusThumbnail(result: result, width: 128, height: 72) }
                    .buttonStyle(.plain).help("Select this segment in the Shot timeline")
                VStack(alignment: .leading, spacing: 5) {
                    if let clip = result.clip {
                        Text(shotClipModelShortLabel(provider: clip.provider, model: clip.model))
                            .font(PlateType.label(10, weight: .semibold))
                        Text(String(format: "Saved video · %.1fs", result.preview?.durationSeconds ?? 0))
                            .font(PlateType.label(9, weight: .regular)).foregroundStyle(PlateColor.inkFaint)
                        if let take = result.record?.selectedTake {
                            Text("TAKE \(take.takeNumber) · IN USE").font(PlateType.label(8, weight: .semibold))
                        }
                        if !result.isPlayable {
                            Text("Video file unavailable").font(.caption).foregroundStyle(CanonColor.rust)
                        }
                    } else {
                        Text(result.progress?.stage.label ?? "Not rendered").font(PlateType.label(10, weight: .semibold))
                    }
                    ShotEditorFlow(spacing: 6) {
                        if result.clip != nil {
                            Button("Preview Clip", action: onPreview).disabled(!result.isPlayable)
                            Button("Copy Video", action: onCopy).disabled(!result.isPlayable)
                        }
                        if let record = result.record {
                            Button("Takes (\(record.takes.count))", action: onTakes)
                        }
                    }.buttonStyle(PlateButtonStyle())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let progress = result.progress, progress.stage != .saved {
                Text(progress.label + (progress.errorMessage.isEmpty ? "" : " · " + progress.errorMessage))
                    .font(.caption).foregroundStyle(progress.stage == .failed ? CanonColor.rust : PlateColor.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isStale {
                Text("Source changed · later clips remain in use. Review Takes to rechain.")
                    .font(.caption).foregroundStyle(CanonColor.rust)
            }
            if result.progress == nil || result.progress?.stage == .saved,
               let record = result.record, let attempt = record.renderingTake ?? record.sortedTakes.last,
               attempt.takeId != record.selectedTakeId {
                Text("\(attempt.takeStatus == .ready ? "Alternate take" : "Take") \(attempt.takeNumber) · \(attempt.takeStatus.rawValue)\(attempt.errorMessage.isEmpty ? "" : " · " + attempt.errorMessage)")
                    .font(.caption).foregroundStyle(attempt.takeStatus == .failed ? CanonColor.rust : PlateColor.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(isFocused ? CanonColor.brass.opacity(0.09) : Color.clear)
        .overlay(Rectangle().stroke(isFocused ? CanonColor.brass : .clear))
    }
}
