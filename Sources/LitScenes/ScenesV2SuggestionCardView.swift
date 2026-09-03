import SwiftUI

/// One suggested Frame in the SCENES v2 pool: the guided stage's gilded plate
/// recipe at card size — cream stock, dashed brass, registration ticks — carrying
/// the plan's brief and two verbs: RENDER (one paid image with the plan's
/// defaults) and ART-DIRECT (the Frame Creator). The card body itself is the
/// ART-DIRECT gesture: a click anywhere on the plate opens the Frame Creator.
/// Never draggable: a plan is not placeable material. Light-forced by the
/// workbench, so PlateColor prints cream.
struct ScenesV2SuggestionCardView: View {
    static let height: CGFloat = 176

    let model: ScenesV2SuggestionCardModel
    let renderCaption: String
    let renderBlockReason: String
    /// The engine's last refusal for THIS card, "" otherwise.
    let refusal: String
    let accentSwatches: [LensColorSwatch]
    var onRender: () -> Void
    var onArtDirect: () -> Void

    private var tint: Color { model.isFailed ? CanonColor.rust : CanonColor.brass }

    /// A failure or refusal takes the brief's slot: the reason matters more.
    private var failureText: String {
        if model.isFailed, !model.failureLine.isEmpty { return model.failureLine }
        return refusal
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            eyebrowRow
            Text(model.title)
                .font(CanonType.display(17, weight: .semibold))
                .foregroundStyle(PlateColor.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            descriptionText
            castRow
            Spacer(minLength: 0)
            actionsRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(PlateColor.cream)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    tint.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )
        )
        .overlay(
            PlateCornerTicks(inset: 7, length: 10)
                .stroke(tint.opacity(0.7), lineWidth: 1.5)
        )
        .overlay(alignment: .topTrailing) {
            if model.isNew {
                newRibbon
            }
        }
        // THE AVATAR: the character rides the plate's bottom-right corner,
        // overlapping it slightly; the cell keeps room for the overflow.
        .overlay(alignment: .bottomTrailing) {
            avatarStack
                .offset(x: 8, y: 8)
        }
        // THE PLATE IS THE VERB: clicking anywhere on the card opens the
        // Frame Creator (Art Direct). RENDER stays its own button — a Button
        // inside wins the tap, so the paid gesture never fires by accident.
        .contentShape(Rectangle())
        .onTapGesture(perform: onArtDirect)
        .pointingHandCursor()
        .help("Open in the Frame Creator to art-direct this Frame")
        .padding(.trailing, 8)
        .padding(.bottom, 8)
    }

    /// The anchor character on top at the corner; a second cast member peeks
    /// out to its left underneath.
    private var avatarStack: some View {
        let marks = Array(model.cast.prefix(2))
        return HStack(spacing: -16) {
            ForEach(Array(marks.reversed().enumerated()), id: \.offset) { index, mark in
                avatar(mark)
                    .zIndex(Double(index))
            }
        }
    }

    private func avatar(_ mark: ScenesV2CastMark) -> some View {
        ZStack {
            Circle()
                .fill(PlateColor.cream)
            if !mark.avatarImagePath.isEmpty,
               let image = StripThumbnailCache.shared.image(path: mark.avatarImagePath, maxPixel: 120) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                Circle()
                    .strokeBorder(PlateColor.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 40, height: 40)
                Text(mark.initial)
                    .font(CanonType.archive(11, weight: .bold))
                    .foregroundStyle(PlateColor.inkFaint)
            }
        }
        .frame(width: 44, height: 44)
        .overlay(Circle().stroke(CanonColor.hairlineDark, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
        .help(avatarHelp(mark))
    }

    private func avatarHelp(_ mark: ScenesV2CastMark) -> String {
        if mark.hasSheet { return "\(mark.name) — attaches the reference sheet" }
        if mark.hasSources { return "\(mark.name) — renders from source photos (no sheet yet)" }
        return "\(mark.name) — no reference images; renders from text"
    }

    private var eyebrowRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint.opacity(0.85))
            PlateLabel(
                text: model.eyebrow,
                size: 7.5,
                color: model.isFailed ? CanonColor.rust : PlateColor.inkFaint
            )
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.trailing, model.isNew ? 44 : 0)
    }

    @ViewBuilder
    private var descriptionText: some View {
        let failure = failureText
        if !failure.isEmpty {
            Text(failure)
                .font(CanonType.interface(10.5))
                .foregroundStyle(CanonColor.rust)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        } else if !model.brief.isEmpty {
            Text(model.brief)
                .font(CanonType.interface(11))
                .foregroundStyle(PlateColor.inkFaint)
                .lineSpacing(1.5)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var castRow: some View {
        HStack(spacing: 8) {
            ForEach(model.cast, id: \.self) { mark in
                HStack(spacing: 4) {
                    Circle()
                        .fill(mark.hasSheet ? CanonColor.brass : Color.clear)
                        .overlay(Circle().stroke(mark.hasSheet ? CanonColor.brass : PlateColor.hairline, lineWidth: 1))
                        .frame(width: 5, height: 5)
                    Text(mark.name.uppercased())
                        .font(CanonType.archive(7, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(PlateColor.inkFaint)
                        .lineLimit(1)
                }
                .help(avatarHelp(mark))
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(accentSwatches.prefix(4), id: \.id) { swatch in
                    Circle()
                        .fill(canonColor(fromHex: swatch.hex, fallback: PlateColor.inkFaint))
                        .frame(width: 6, height: 6)
                        .overlay(Circle().stroke(PlateColor.hairline, lineWidth: 0.5))
                }
            }
        }
        .frame(height: 12)
    }

    private var actionsRow: some View {
        HStack(alignment: .center, spacing: 10) {
            StageBrassPill(
                title: model.isFailed ? "RETRY" : "RENDER",
                icon: "sparkles",
                disabledReason: renderBlockReason,
                style: model.isPrimary ? .filled : .ghost,
                size: .compact,
                action: onRender
            )
            .help(renderBlockReason.isEmpty
                ? "One paid render with the plan's defaults — \(renderCaption)"
                : renderBlockReason)
            Text((model.isFailed ? "one more paid render" : renderCaption).uppercased())
                .font(CanonType.archive(7, weight: .medium))
                .kerning(0.5)
                .foregroundStyle(PlateColor.inkFaint)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: onArtDirect) {
                Text("ART-DIRECT →")
                    .font(CanonType.archive(8, weight: .bold))
                    .kerning(1.0)
                    .foregroundStyle(CanonColor.brass)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Shape the prompt and style in the Frame Creator, then render it there.")
        }
    }

    private var newRibbon: some View {
        Text("NEW")
            .font(CanonType.archive(6.5, weight: .bold))
            .kerning(0.8)
            .foregroundStyle(CanonColor.ink)
            .padding(.horizontal, 7)
            .frame(height: 15)
            .background(Capsule().fill(CanonColor.softGold))
            .padding(10)
    }
}
