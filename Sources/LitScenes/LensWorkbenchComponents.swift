import SwiftUI

/// The treatment editing state machine, extracted pure so the blend console, picker rail,
/// and tests all derive the same four states: clean, edited-with-diff, blend-changed-since-
/// render, and rendering.
struct LensTreatmentState: Equatable {
    enum Phase: Equatable {
        /// Saved treatment matches drafts and the newest render.
        case clean
        /// Local drafts differ from the saved treatment ("60 · 25 · 15 → 45 · 30 · 25").
        case edited(diff: String)
        /// Saved treatment differs from the blend the newest media version rendered with.
        case changedSinceRender
        /// The newest media version is actively generating.
        case rendering
    }

    var phase: Phase

    static func derive(
        lens: ProjectLens,
        treatment: LensStyleTreatment,
        draftedTreatment: LensStyleTreatment,
        isEngineBusy: Bool
    ) -> LensTreatmentState {
        if isEngineBusy || newestVersionIsRendering(lens) {
            return LensTreatmentState(phase: .rendering)
        }
        if draftedTreatment.slots.map(\.weight) != treatment.slots.map(\.weight)
            || draftedTreatment.slots.map(\.styleId) != treatment.slots.map(\.styleId) {
            return LensTreatmentState(phase: .edited(diff: "\(treatment.weightSummary) → \(draftedTreatment.weightSummary)"))
        }
        if treatmentChangedSinceRender(lens: lens, treatment: treatment) {
            return LensTreatmentState(phase: .changedSinceRender)
        }
        return LensTreatmentState(phase: .clean)
    }

    static func newestVersionIsRendering(_ lens: ProjectLens) -> Bool {
        guard let newest = lens.mediaVersionIds.last else { return false }
        return lens.heroImages(mediaVersion: newest).contains {
            $0.status == "generating"
        }
    }

    static func treatmentChangedSinceRender(lens: ProjectLens, treatment: LensStyleTreatment) -> Bool {
        guard let newest = lens.mediaVersionIds.last else { return false }
        let snapshot = lens.blendSnapshot(mediaVersion: newest)
        guard !snapshot.isEmpty else { return false }
        // Provenance may carry a plan suffix after "|"; compare the recipe part only.
        let snapshotRecipe = snapshot.split(separator: "|").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? snapshot
        return snapshotRecipe != treatment.recipeText
    }
}

struct StyleImagePreviewRequest: Identifiable, Hashable {
    var url: String
    var label: String
    var detail: String = ""

    var id: String { url }
}

/// Large read-only preview for a style reference image, opened from treatment thumbnails.
struct StyleImagePreviewModal: View {
    let request: StyleImagePreviewRequest

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            AsyncImage(url: URL(string: request.url)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                case .failure:
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                        Text("Image unavailable")
                            .font(CanonType.interface(12))
                    }
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 640, minHeight: 560)
            .background(CanonColor.room)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.label)
                        .font(CanonType.editorial(15, weight: .semibold))
                        .foregroundStyle(CanonColor.bone)
                    if !request.detail.isEmpty {
                        Text(request.detail)
                            .font(CanonType.archive(10))
                            .foregroundStyle(CanonColor.muted)
                    }
                }
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .font(CanonType.interface(12, weight: .semibold))
                    .foregroundStyle(CanonColor.softGold)
            }
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 660)
        .background(CanonColor.room)
    }
}

/// Compact weighted thumbnail stack for a lens style treatment: primary and accents as
/// circular chips sized by blend share. Used by the lens picker cards.
struct LensTreatmentOrbitStack: View {
    let treatment: LensStyleTreatment
    var maxSide: CGFloat = 23
    var minSide: CGFloat = 11

    var body: some View {
        let slots = treatment.slots
        let shares = treatment.blendShares()
        HStack(spacing: 3) {
            ForEach(Array(slots.enumerated()), id: \.element.styleId) { index, slot in
                let share = shares.indices.contains(index) ? Double(shares[index]) / 100 : 0
                let side = minSide + CGFloat(share) * (maxSide - minSide)
                AsyncImage(url: URL(string: slot.url)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Color.black.opacity(0.12)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.black.opacity(0.16), lineWidth: 0.5))
                .help("\(slot.label) · \(slot.weight)")
            }
        }
    }
}

/// Minimal wrapping chip layout shared by filter rails and tag groups.
struct FlowChips<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        StyleStudioFlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

struct StyleStudioFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 200
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

func canonColor(fromHex hex: String, fallback: Color = CanonColor.muted) -> Color {
    var cleaned = hex.trimmed
    if cleaned.hasPrefix("#") {
        cleaned = String(cleaned.dropFirst())
    }
    guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
        return fallback
    }
    return Color(
        .sRGB,
        red: Double((value >> 16) & 0xFF) / 255,
        green: Double((value >> 8) & 0xFF) / 255,
        blue: Double(value & 0xFF) / 255,
        opacity: 1
    )
}
