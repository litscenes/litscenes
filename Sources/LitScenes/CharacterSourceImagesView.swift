import AppKit
import SwiftUI

/// SOURCE IMAGES: the photos and studies the sheet is rendered from. Drag to
/// reorder; the badged ones attach on the current stack; generated frames wear a
/// spark; a dashed placeholder holds the spot while a study renders; the grid ends
/// with the three ways to add one — from the project's media, upload, or the studio.
struct CharacterSourceImagesView: View {
    let name: String
    let referenceMediaIds: [String]
    let referenceLabels: [String: String]
    let candidates: [MediaItemRecord]
    /// The source ids the next sheet render attaches, in attach order.
    let attachedMediaIds: [String]
    let stackLabel: String
    let stackIsTextOnly: Bool
    /// "II" while a sheet anchors the character; nil before the first sheet.
    let sheetOrdinalLabel: String?
    /// The shot of the study rendering right now for this character; nil when idle.
    let generatingShotLabel: String?
    let suggestions: [MediaItemRecord]
    /// Whether each source has been analyzed, is waiting, or cannot be.
    let analysisState: (String) -> CharacterSourceAnalysisState
    var onPlace: (String, Int) -> Void
    var onAppend: ([String]) -> Void
    var onRemove: (String) -> Void
    var onLabel: (String, String) -> Void
    var onUpload: () -> Void
    var onPickFromMedia: () -> Void
    var onEnlarge: (MediaItemRecord) -> Void
    var onMoreLikeThis: (String) -> Void
    var onOpenStudio: () -> Void

    private var sentence: String {
        let stack = stackLabel.trimmed
        let intake = " Added photos are copied into the project and analyzed."
        if stackIsTextOnly {
            return "\(stack.isEmpty ? "This stack" : stack) renders from text only; these photos stay on file for other stacks." + intake
        }
        if let sheetOrdinalLabel {
            return "Photos behind the sheet. Drag to reorder; the badged ones attach with sheet \(sheetOrdinalLabel)." + intake
        }
        if stack.isEmpty {
            return "Photos the sheet renders from. Drag to reorder." + intake
        }
        return "Photos the sheet renders from. Drag to reorder; the badged ones attach on \(stack)." + intake
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CharacterSectionHeader(title: "SOURCE IMAGES", count: referenceMediaIds.count)
            Text(sentence)
                .font(CanonType.interface(12.5))
                .foregroundStyle(CanonColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10, alignment: .top)], alignment: .leading, spacing: 12) {
                ForEach(Array(referenceMediaIds.enumerated()), id: \.element) { index, mediaId in
                    CharacterSourceTile(
                        mediaId: mediaId,
                        index: index,
                        item: candidates.first { $0.mediaId == mediaId },
                        label: referenceLabels[mediaId] ?? "",
                        attachOrdinal: attachedMediaIds.firstIndex(of: mediaId).map { $0 + 1 },
                        analysisState: analysisState(mediaId),
                        onDropBefore: { onPlace($0, index) },
                        onRemove: { onRemove(mediaId) },
                        onMoveToLead: { onPlace(mediaId, 0) },
                        onMoreLikeThis: { onMoreLikeThis(mediaId) },
                        onLabelCommit: { onLabel(mediaId, $0) },
                        onEnlarge: onEnlarge
                    )
                }
                if let generatingShotLabel {
                    generatingTile(generatingShotLabel)
                }
                CharacterSourceActionTile(
                    title: "ADD FROM MEDIA",
                    icon: "photo.on.rectangle",
                    help: "Choose images already in this project — Story Inputs, library images, or generated frames",
                    onTap: onPickFromMedia
                )
                CharacterSourceActionTile(
                    title: "UPLOAD FILES",
                    icon: "square.and.arrow.up",
                    help: "Add image files as sources, or drop images here",
                    onTap: onUpload,
                    onDrop: onAppend
                )
                CharacterSourceActionTile(
                    title: "GENERATE",
                    icon: "sparkles",
                    help: "Generate a source image in the studio — from text, or as a variant of a source",
                    onTap: onOpenStudio
                )
            }
            if !suggestions.isEmpty {
                suggestionsRow
            }
        }
    }

    private func generatingTile(_ shotLabel: String) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(CanonColor.brass.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .frame(width: 96, height: 96)
                .overlay(
                    VStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(CanonColor.brass)
                        Text("GENERATING")
                            .font(CanonType.archive(7, weight: .semibold))
                            .kerning(0.8)
                            .foregroundStyle(CanonColor.brass)
                    }
                )
            Text(shotLabel)
                .font(CanonType.archive(7, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(CanonColor.muted)
                .frame(width: 96)
        }
        .help("A \(shotLabel.lowercased()) study is rendering; it lands here as a source")
    }

    private var suggestionsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SUGGESTED FROM STORY INPUTS")
                .font(CanonType.archive(8, weight: .semibold))
                .kerning(1.4)
                .foregroundStyle(CanonColor.muted)
            HStack(spacing: 10) {
                ForEach(suggestions) { item in
                    VStack(spacing: 4) {
                        sourceThumbnail(item, side: 66)
                            .onTapGesture { onEnlarge(item) }
                        CharacterCapsButton(title: "ADD", size: 7.5, help: "Add as a source image") {
                            onAppend([item.mediaId])
                        }
                    }
                    .help(item.filename)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 4)
    }
}

/// A cached thumbnail that NEVER crops: the tile keeps the given width and takes
/// the image's own shape inside the Media tab's band (`MediaTileLayout`), so a
/// portrait keeps its head; beyond the band the picture letterboxes on the
/// matte. A dark card with a question mark when the file is gone.
func sourceThumbnail(_ item: MediaItemRecord?, side: CGFloat) -> some View {
    let aspect = item.map { MediaTileLayout.aspect(width: $0.width, height: $0.height) }
        ?? MediaTileAspect(tileAspect: 1, letterboxes: true)
    return Group {
        if let item, let image = characterThumbnail(item) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: aspect.letterboxes ? .fit : .fill)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(CanonColor.mediaCard)
                .overlay(Image(systemName: "questionmark").font(.system(size: 14)).foregroundStyle(CanonColor.muted))
        }
    }
    .frame(width: side, height: (side / aspect.tileAspect).rounded())
    .background(CanonColor.mediaCard)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlineDark))
}

private struct CharacterSourceTile: View {
    let mediaId: String
    let index: Int
    let item: MediaItemRecord?
    let label: String
    let attachOrdinal: Int?
    let analysisState: CharacterSourceAnalysisState
    var onDropBefore: (String) -> Void
    var onRemove: () -> Void
    var onMoveToLead: () -> Void
    var onMoreLikeThis: () -> Void
    var onLabelCommit: (String) -> Void
    var onEnlarge: (MediaItemRecord) -> Void

    @State private var isDropTargeted = false
    @State private var isHovered = false
    @State private var draft = ""
    @FocusState private var isLabelFocused: Bool

    private var isGenerated: Bool {
        item?.derivativeKind == MediaItemRecord.rosterCharacterRenderDerivativeKind
    }

    var body: some View {
        VStack(spacing: 4) {
            sourceThumbnail(item, side: 96)
                .overlay(alignment: .topLeading) {
                    if let attachOrdinal {
                        Text("\(attachOrdinal)")
                            .font(CanonType.archive(8, weight: .bold))
                            .foregroundStyle(CanonColor.ink)
                            .padding(3)
                            .background(Circle().fill(CanonColor.brass))
                            .padding(4)
                            .help("Attaches to the sheet render as image \(attachOrdinal)")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isHovered {
                        Button(action: onRemove) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                        }
                        .buttonStyle(.plain)
                        .padding(3)
                        .help("Remove from sources — the file stays in the Library")
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    analysisDot
                }
                .overlay(alignment: .bottomLeading) {
                    if isGenerated {
                        Image(systemName: "sparkles")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(CanonColor.ink)
                            .padding(3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(CanonColor.brass.opacity(0.9)))
                            .padding(4)
                            .help("Generated in the studio")
                    } else if item?.isRosterCompositeSheet == true {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(CanonColor.ink)
                            .padding(3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(CanonColor.brass.opacity(0.9)))
                            .padding(4)
                    }
                }
                .background(isDropTargeted ? CanonColor.softGold.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDropTargeted ? CanonColor.brass : Color.clear, lineWidth: 2))
                .contentShape(Rectangle())
                .onHover { isHovered = $0 }
                .onTapGesture { if let item { onEnlarge(item) } }
                .draggable(MediaIDTransfer(mediaId: mediaId))
                .dropDestination(for: MediaIDTransfer.self) { payloads, _ in
                    guard let first = payloads.first, first.mediaId != mediaId else { return false }
                    onDropBefore(first.mediaId)
                    return true
                } isTargeted: { isDropTargeted = $0 }
                .contextMenu {
                    Button("Move to slot 1", action: onMoveToLead)
                        .disabled(index == 0)
                    Button("More like this…", action: onMoreLikeThis)
                        .disabled(item == nil)
                    Button("View larger") { if let item { onEnlarge(item) } }
                        .disabled(item == nil)
                    Divider()
                    Button("Remove from sources", action: onRemove)
                }
                .help(item.map { "\(label.isEmpty ? $0.filename : label) — click to view larger" } ?? "Missing media")
            labelField
        }
    }

    /// A quiet dot: brass once analyzed, gold while waiting or working, muted when
    /// nothing can run. The tooltip says which.
    private var analysisDot: some View {
        let color: Color
        switch analysisState {
        case .analyzed: color = CanonColor.brass
        case .analyzing, .queued: color = CanonColor.softGold
        case .unavailable, .pending: color = CanonColor.muted
        }
        return ZStack {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(CanonColor.room.opacity(0.8), lineWidth: 1))
            if analysisState == .analyzing {
                ProgressView()
                    .controlSize(.mini)
                    .tint(CanonColor.softGold)
                    .scaleEffect(0.6)
            }
        }
        .padding(5)
        .help(analysisState.label)
    }

    private var labelField: some View {
        TextField("Add label", text: $draft)
            .textFieldStyle(.plain)
            .font(CanonType.interface(10.5))
            .foregroundStyle(CanonColor.bone.opacity(0.8))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .focused($isLabelFocused)
            .onSubmit(commitLabel)
            .onChange(of: isLabelFocused) { _, focused in
                if !focused { commitLabel() }
            }
            .onAppear { draft = label }
            .onChange(of: label) { _, newValue in
                if !isLabelFocused { draft = newValue }
            }
            .frame(width: 96)
            .padding(.vertical, 2)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isLabelFocused ? CanonColor.brass : CanonColor.hairlineDark)
                    .frame(height: isLabelFocused ? 1.2 : 0.5)
            }
            .help(label.isEmpty ? "Label what this image shows, for example \"young \(labelSubject)\"" : label)
    }

    private var labelSubject: String { "Auri" }

    private func commitLabel() {
        guard draft.trimmed != label.trimmed else { return }
        onLabelCommit(draft)
    }
}

/// A labeled action tile at the end of the source grid — the same footprint as a
/// source, dashed because it holds no image yet.
private struct CharacterSourceActionTile: View {
    let title: String
    let icon: String
    var help: String = ""
    var onTap: () -> Void
    var onDrop: (([String]) -> Void)? = nil

    @State private var isDropTargeted = false
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isHovered || isDropTargeted ? CanonColor.brass : CanonColor.muted)
                Text(title)
                    .font(CanonType.archive(7.5, weight: .bold))
                    .kerning(1.0)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isHovered || isDropTargeted ? CanonColor.brass : CanonColor.bone.opacity(0.8))
            }
            .frame(width: 96, height: 96)
            .background(isDropTargeted ? CanonColor.softGold.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isHovered || isDropTargeted ? CanonColor.brass.opacity(0.7) : CanonColor.hairlineDark, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { isHovered = $0 }
        .modifier(SourceDropModifier(onDrop: onDrop, isTargeted: $isDropTargeted))
        .help(help)
    }
}

/// Drop acceptance only for the tile that can take files.
private struct SourceDropModifier: ViewModifier {
    let onDrop: (([String]) -> Void)?
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        if let onDrop {
            content.dropDestination(for: MediaIDTransfer.self) { payloads, _ in
                let ids = payloads.map(\.mediaId)
                onDrop(ids)
                return !ids.isEmpty
            } isTargeted: { isTargeted = $0 }
        } else {
            content
        }
    }
}
