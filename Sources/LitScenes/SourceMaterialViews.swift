import SwiftUI

struct SourceMaterialHeaderView: View {
    @Binding var filterQuery: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SOURCE MATERIAL")
                    .font(CanonType.archive(10, weight: .semibold))
                    .kerning(1.7)
                    .foregroundStyle(CanonColor.brass)
                Text("Every photo is Frame-ready on first use; videos remain Footage.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted.opacity(0.84))
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.4))
                TextField("Search all source material", text: $filterQuery)
                    .textFieldStyle(.plain)
                    .font(CanonType.interface(11.5))
                if !filterQuery.trimmed.isEmpty {
                    Button {
                        filterQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(CanonColor.ink.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .frame(width: 250, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.52)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper.opacity(0.82)))
        }
    }
}

struct SourceMaterialSectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("\(title.uppercased()) · \(count)")
                .font(CanonType.archive(8.5, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(CanonColor.muted)
            Rectangle()
                .fill(CanonColor.hairlinePaper)
                .frame(height: 1)
        }
    }
}

/// Uploaded and derived project media presented at the same 16:9 working
/// scale as generated Frames. Cards are previews and drag sources; images are
/// not copied into the Frame ledger until a Shot actually uses them.
struct SourceMediaGrid: View {
    @ObservedObject var library: LibraryEngine
    let kind: MediaKind
    var filterQuery: String = ""
    var excludedMediaIds: Set<String> = []
    var onOpenMedia: (MediaItemRecord) -> Void = { _ in }
    var onAddFrame: (() -> Void)? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 196, maximum: 240), spacing: 12, alignment: .topLeading)
    ]

    private var items: [MediaItemRecord] {
        let query = filterQuery.trimmed.lowercased()
        return library.items
            .filter { $0.kind == kind && !excludedMediaIds.contains($0.mediaId) }
            .filter { item in
                query.isEmpty
                    || item.filename.lowercased().contains(query)
                    || library.curation(for: item).tags.contains { $0.lowercased().contains(query) }
            }
            .sorted { lhs, rhs in
                if lhs.modifiedAt == rhs.modifiedAt { return lhs.filename < rhs.filename }
                return lhs.modifiedAt > rhs.modifiedAt
            }
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
            if let onAddFrame {
                SourceMaterialAddFrameCard(onAdd: onAddFrame)
            }
            ForEach(items) { item in
                SourceMediaCard(item: item, onOpen: { onOpenMedia(item) })
            }
        }
    }
}

/// The first cell in Source Material's Frames list. It lives outside the
/// generated-take theater so uploaded photos can never push creation below
/// the fold, and it remains visible while the inventory search is active.
struct SourceMaterialAddFrameCard: View {
    var onAdd: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onAdd) {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        isHovering ? CanonColor.brass : CanonColor.hairlinePaper,
                        style: StrokeStyle(lineWidth: isHovering ? 1.8 : 1.4, dash: [6, 5])
                    )
                    .background(
                        CanonColor.paperInset.opacity(isHovering ? 0.56 : 0.34),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .overlay {
                        LitIconView(icon: .add, size: 34)
                            .foregroundStyle(CanonColor.brass.opacity(0.9))
                    }
                    .frame(height: 110)
                Text("Add Frame")
                    .font(CanonType.interface(10.5, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
                    .lineLimit(1)
                Text("OPEN FRAME CREATOR")
                    .font(CanonType.archive(7, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(CanonColor.muted.opacity(0.78))
            }
            .frame(minWidth: 196, maxWidth: 240, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Create a new Frame in Source Material")
    }
}

struct SourceMediaCard: View {
    let item: MediaItemRecord
    var onOpen: () -> Void = {}

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                CanonColor.mediaCardHover
                if let image = thumbnail {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: item.kind == .video ? "film" : "photo")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CanonColor.muted.opacity(0.62))
                }
                if item.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.black.opacity(0.48)))
                }
            }
            .frame(height: 110)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isHovering ? CanonColor.brass.opacity(0.72) : CanonColor.hairlinePaper.opacity(0.9))
            )
            Text(item.filename)
                .font(CanonType.interface(10.5, weight: .semibold))
                .foregroundStyle(CanonColor.ink.opacity(0.80))
                .lineLimit(1)
            HStack(spacing: 5) {
                Text(item.kind == .video ? "FOOTAGE" : "PHOTO · FRAME-READY")
                if item.kind == .video, let duration = item.durationSeconds {
                    Text("· \(shortDuration(duration))")
                }
            }
            .font(CanonType.archive(7, weight: .semibold))
            .kerning(0.5)
            .foregroundStyle(CanonColor.muted.opacity(0.78))
        }
        .frame(minWidth: 196, maxWidth: 240, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { isHovering = $0 }
        .draggable(ShotFrameTransfer(frameImageId: "", clipMediaId: item.mediaId))
        .help(item.kind == .video
            ? "Preview Footage; drag it into a Shot to place it verbatim"
            : "Preview photo; drag it into a Shot to adopt it as a Frame")
    }

    private var thumbnail: NSImage? {
        if item.kind == .image {
            return StripThumbnailCache.shared.image(path: item.path)
                ?? StripThumbnailCache.shared.image(path: item.thumbnailPath)
        }
        return StripThumbnailCache.shared.image(path: item.thumbnailPath)
    }

    private func shortDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
