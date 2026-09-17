import SwiftUI

/// The take strip on a segment card: every retained take of the placement as
/// a poster thumb, the one in the film ringed brass, the previewed one inked.
/// Clicking a thumb PREVIEWS in the player; only USE IN FILM mutates, and it
/// is free and undoable. Continuation placements keep their full browser one
/// step away for repair, rechain and new takes.
struct ShotSegmentTakeStrip: View {
    let options: [ShotTakeOption]
    var previewedTakeId: String? = nil
    var isRenderBlocked = false
    var onPreview: (ShotTakeOption) -> Void
    var onUse: (ShotTakeOption) -> Void
    var onCompare: ((ShotTakeOption, ShotTakeOption) -> Void)? = nil
    var onAllTakes: (() -> Void)? = nil

    private var inFilm: ShotTakeOption? { shotInFilmTake(options) }
    private var previewed: ShotTakeOption? { options.first { $0.id == previewedTakeId } }
    private var shown: ShotTakeOption? { previewed ?? inFilm }

    /// In-film vs the previewed take, else vs the newest other ready take.
    private var comparePair: (ShotTakeOption, ShotTakeOption)? {
        let ready = options.filter(\.isReady)
        guard ready.count >= 2 else { return nil }
        let anchor = ready.first { $0.isInFilm } ?? ready[0]
        let other = (previewed.flatMap { $0.isReady && $0.id != anchor.id ? $0 : nil })
            ?? ready.last { $0.id != anchor.id }
        guard let other else { return nil }
        return (anchor, other)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(options) { option in
                        ShotTakeThumb(option: option, isPreviewed: option.id == previewedTakeId) {
                            onPreview(option)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            takeActions
            if let shown { promptBlock(shown) }
        }
    }

    private var takeActions: some View {
        ShotEditorFlow(spacing: 6) {
            if let onAllTakes {
                Button("All Takes…") { onAllTakes() }
                    .buttonStyle(PlateButtonStyle())
                    .help("Every attempt for this continuation — repair, rechain, or render another take")
            }
        }
    }

    private func useHelp(for option: ShotTakeOption) -> String {
        if let inFilm {
            return "Put Take \(option.takeNumber) in the film in place of Take \(inFilm.takeNumber) — free, and ⌘Z brings Take \(inFilm.takeNumber) back"
        }
        return "Put Take \(option.takeNumber) in the film — free, and ⌘Z undoes it"
    }

    private func promptBlock(_ option: ShotTakeOption) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                PlateLabel(text: "Prompt · Take \(option.takeNumber)", size: 10, weight: .bold, color: PlateColor.ink.opacity(0.72))
                if let inFilm, inFilm.id != option.id, inFilm.prompt.trimmed != option.prompt.trimmed {
                    PlateLabel(text: "Changed from the in-film take", size: 10, weight: .bold, color: CanonColor.brass)
                        .help(inFilm.prompt.trimmed.nilIfEmpty ?? "The in-film take has no saved direction")
                }
            }
            Text(option.prompt.trimmed.nilIfEmpty ?? "No saved direction")
                .font(PlateType.label(10, weight: .regular))
                .foregroundStyle(PlateColor.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// One 96×54 poster thumb with its caption. A rendering take holds its place
/// with a dashed frame; a take whose file is gone stays listed, dimmed and
/// unclickable, so the count never lies.
private struct ShotTakeThumb: View {
    let option: ShotTakeOption
    let isPreviewed: Bool
    var onPreview: () -> Void

    private var ringColor: Color {
        if isPreviewed { return PlateColor.ink }
        if option.isInFilm { return CanonColor.brass }
        return PlateColor.hairline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onPreview) {
                ZStack {
                    if option.status == .rendering {
                        PlateColor.creamDeep
                        ProgressView().controlSize(.small)
                    } else {
                        ShotSegmentVideoThumbnail(
                            preview: option.clip.map { ShotSegmentPreview(clip: $0) },
                            width: 96, height: 54
                        )
                        .opacity(option.status == .fileMissing ? 0.45 : 1)
                    }
                }
                .frame(width: 96, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(ringColor, lineWidth: isPreviewed || option.isInFilm ? 2 : 1)
                        .opacity(option.status == .rendering ? 0 : 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(PlateColor.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .opacity(option.status == .rendering ? 1 : 0)
                )
            }
            .buttonStyle(.plain)
            .disabled(option.clip == nil)
            .help(option.caption + (option.prompt.trimmed.isEmpty ? "" : "\n\n" + option.prompt.trimmed))
            VStack(alignment: .leading, spacing: 3) {
                Text("Take \(option.takeNumber)")
                    .font(PlateType.label(10, weight: .semibold))
                    .foregroundStyle(option.status == .fileMissing ? CanonColor.rust : PlateColor.inkFaint)
                    .lineLimit(1)
                if isPreviewed { Text("Selected").font(PlateType.label(10, weight: .bold)).foregroundStyle(PlateColor.ink) }
                if option.isInFilm {
                    PlateLabel(text: "In film", size: 10, weight: .bold, color: CanonColor.brass)
                }
            }
            .frame(width: 96 + (option.isInFilm ? 52 : 0), alignment: .leading)
        }
        .padding(2)
        .background(isPreviewed ? PlateColor.creamDeep.opacity(0.7) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
