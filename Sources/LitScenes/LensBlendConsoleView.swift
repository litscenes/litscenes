import SwiftUI

/// The blend console: the lens treatment as a first-class visual instrument. One
/// proportional band shows every style at its true share — segments are the blend —
/// with draggable dividers to rebalance, precise sliders beneath, live percentage
/// readouts from the same largest-remainder shares the pipeline sends, a role/weight
/// inversion warning, and the four-state header (clean / edited diff / changed-since-
/// render / rendering).
struct LensBlendConsoleView: View {
    let lens: ProjectLens
    let treatment: LensStyleTreatment
    @Binding var weightDrafts: [String: Double]
    let isEngineBusy: Bool
    let extraDirty: Bool
    let extraDirtySummary: String
    var onRegenerate: () -> Void
    var onRevert: () -> Void
    var onEditBlend: () -> Void
    var onPromoteHeaviest: () -> Void
    var onPreviewStyle: (StyleImagePreviewRequest) -> Void

    @State private var dragStartWeights: [String: Int]?

    private var draftedTreatment: LensStyleTreatment {
        var updated = treatment
        if var primary = updated.primary {
            primary.weight = draftedWeight(for: primary)
            updated.primary = primary
        }
        updated.accents = updated.accents.map { accent in
            var slot = accent
            slot.weight = draftedWeight(for: accent)
            return slot
        }
        return updated.normalized()
    }

    private var state: LensTreatmentState {
        LensTreatmentState.derive(
            lens: lens,
            treatment: treatment,
            draftedTreatment: draftedTreatment,
            isEngineBusy: isEngineBusy
        )
    }

    private var isRendering: Bool { state.phase == .rendering }

    private var weightsDirty: Bool {
        if case .edited = state.phase { return true }
        return false
    }

    private var dirty: Bool { weightsDirty || extraDirty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            blendBar
            Text("The anchor scene renders once in every style — a side-by-side bake-off — and all other concepts render in the primary style.")
                .font(CanonType.interface(10.5))
                .foregroundStyle(CanonColor.muted)
            sliderRows
            if !draftedTreatment.rolesAreWeightConsistent {
                inversionWarning
            }
            ctaRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CanonColor.paperInset.opacity(0.68), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CanonColor.hairlinePaper.opacity(0.82)))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Your blend")
                .font(CanonType.interface(13, weight: .semibold))
                .foregroundStyle(CanonColor.ink)
            switch state.phase {
            case .edited(let diff):
                Text(extraDirty && !extraDirtySummary.isEmpty ? "\(diff) · \(extraDirtySummary)" : diff)
                    .font(CanonType.archive(10, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
                    .lineLimit(1)
            case .rendering:
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("rendering")
                        .font(CanonType.archive(10))
                        .foregroundStyle(CanonColor.muted)
                }
            case .changedSinceRender:
                Text(treatment.recipeText)
                    .font(CanonType.archive(10))
                    .foregroundStyle(CanonColor.ink.opacity(0.5))
                    .lineLimit(1)
                Text("blend changed since last render")
                    .font(CanonType.archive(9, weight: .semibold))
                    .foregroundStyle(CanonColor.paper)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(CanonColor.rust.opacity(0.85)))
            case .clean:
                if extraDirty, !extraDirtySummary.isEmpty {
                    Text(extraDirtySummary)
                        .font(CanonType.archive(10, weight: .semibold))
                        .foregroundStyle(CanonColor.brass)
                        .lineLimit(1)
                } else {
                    Text(treatment.recipeText)
                        .font(CanonType.archive(10))
                        .foregroundStyle(CanonColor.ink.opacity(0.5))
                        .lineLimit(1)
                }
            }
            Spacer()
            if weightsDirty {
                Button("Revert") { onRevert() }
                    .buttonStyle(.plain)
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(CanonColor.muted)
                    .disabled(isRendering)
            }
            Button {
                onEditBlend()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Edit blend")
                        .font(CanonType.interface(11, weight: .semibold))
                }
                .foregroundStyle(CanonColor.brass)
            }
            .buttonStyle(.plain)
            .disabled(isRendering)
            .help("Browse the style catalog and recompose this blend in place")
        }
    }

    // MARK: - Proportional blend bar

    private var slots: [LensStyleTreatmentSlot] { draftedTreatment.slots }

    private var blendBar: some View {
        let shares = draftedTreatment.blendShares()
        return GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: 0) {
                ForEach(Array(slots.enumerated()), id: \.element.styleId) { index, slot in
                    let share = shares.indices.contains(index) ? shares[index] : 0
                    segment(
                        slot: slot,
                        index: index,
                        share: share,
                        width: max(28, width * CGFloat(share) / 100)
                    )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(CanonColor.hairlinePaper.opacity(0.9)))
            .overlay(dividerHandles(width: width))
        }
        .frame(height: 108)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: draftedTreatment.blendShares())
    }

    private func segment(slot: LensStyleTreatmentSlot, index: Int, share: Int, width: CGFloat) -> some View {
        let tint = CanonColor.roleTint(forSlotIndex: index)
        return Button {
            onPreviewStyle(StyleImagePreviewRequest(
                url: slot.url,
                label: slot.label,
                detail: "\(index == 0 ? "Primary" : "Accent \(index)") · \(slot.collection)"
            ))
        } label: {
            ZStack(alignment: .bottomLeading) {
                // Fill-mode images overflow their proposed frame; anchor them to a
                // bounded clear layer and clip at the segment's exact size so a segment
                // can never paint outside its share of the bar.
                Color.clear
                    .overlay(
                        AsyncImage(url: URL(string: slot.url)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            default:
                                CanonColor.paperInset
                            }
                        }
                    )
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.52)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(share)%")
                        .font(CanonType.archive(15, weight: .bold))
                        .foregroundStyle(.white)
                    if width >= 84 {
                        Text(slot.label)
                            .font(CanonType.interface(9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .padding(8)
            }
            .frame(width: width, height: 108)
            .clipped()
            .overlay(alignment: .top) {
                Rectangle().fill(tint).frame(height: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(slot.label) — click to view")
    }

    /// Invisible drag handles over each internal segment boundary: dragging transfers
    /// weight between the two adjacent slots, keeping the total constant.
    private func dividerHandles(width: CGFloat) -> some View {
        let shares = draftedTreatment.blendShares()
        var boundaries: [CGFloat] = []
        var running: CGFloat = 0
        for share in shares.dropLast() {
            running += CGFloat(share) / 100
            boundaries.append(running * width)
        }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(boundaries.enumerated()), id: \.offset) { index, x in
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 14, height: 108)
                    .contentShape(Rectangle())
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 3, height: 30)
                            .shadow(color: .black.opacity(0.35), radius: 2)
                    )
                    .position(x: x, y: 54)
                    .gesture(dividerDrag(betweenSlotAt: index, barWidth: width))
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            }
        }
        .allowsHitTesting(!isRendering && slots.count > 1)
    }

    private func dividerDrag(betweenSlotAt index: Int, barWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let startWeights: [String: Int]
                if let dragStartWeights {
                    startWeights = dragStartWeights
                } else {
                    startWeights = Dictionary(uniqueKeysWithValues: slots.map { ($0.styleId, draftedWeight(for: $0)) })
                    dragStartWeights = startWeights
                }
                let allSlots = slots
                guard allSlots.indices.contains(index), allSlots.indices.contains(index + 1) else { return }
                let left = allSlots[index]
                let right = allSlots[index + 1]
                guard let leftStart = startWeights[left.styleId], let rightStart = startWeights[right.styleId] else { return }
                let totalWeight = startWeights.values.reduce(0, +)
                let delta = Int((value.translation.width / max(1, barWidth)) * CGFloat(totalWeight))
                let pairTotal = leftStart + rightStart
                let newLeft = min(min(90, pairTotal - 5), max(5, leftStart + delta))
                let newRight = pairTotal - newLeft
                guard (5...90).contains(newRight) else { return }
                weightDrafts[left.styleId] = Double(newLeft)
                weightDrafts[right.styleId] = Double(newRight)
            }
            .onEnded { _ in
                dragStartWeights = nil
            }
    }

    // MARK: - Precision sliders

    private var sliderRows: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(slots.enumerated()), id: \.element.styleId) { index, slot in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text((index == 0 ? "Primary" : "Accent \(index)").uppercased())
                            .font(CanonType.archive(8, weight: .semibold))
                            .kerning(1)
                            .foregroundStyle(CanonColor.roleTint(forSlotIndex: index))
                        Spacer(minLength: 2)
                        Text("\(draftedWeight(for: slot))")
                            .font(CanonType.archive(9))
                            .foregroundStyle(CanonColor.ink.opacity(0.55))
                    }
                    Slider(
                        value: Binding(
                            get: { Double(draftedWeight(for: slot)) },
                            set: { weightDrafts[slot.styleId] = $0 }
                        ),
                        in: 5...90
                    )
                    .controlSize(.mini)
                    .tint(CanonColor.roleTint(forSlotIndex: index))
                }
                .frame(maxWidth: .infinity)
                .disabled(isRendering)
            }
        }
    }

    // MARK: - Inversion warning

    private var inversionWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(CanonColor.rust)
            Text("An accent outweighs the primary — it will render more frames than the primary style.")
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.ink.opacity(0.75))
            Spacer()
            Button("Promote heaviest to primary") { onPromoteHeaviest() }
                .buttonStyle(.plain)
                .font(CanonType.interface(11, weight: .semibold))
                .foregroundStyle(CanonColor.brass)
                .disabled(isRendering)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(CanonColor.rust.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CanonColor.rust.opacity(0.3)))
    }

    // MARK: - CTA

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                onRegenerate()
            } label: {
                Text(dirty ? "Regenerate with new blend" : "Regenerate")
            }
            .buttonStyle(CanonPrimaryButtonStyle())
            .disabled(isRendering)
            .help(dirty
                ? "Commit the new blend and render a fresh media version"
                : "Re-roll this lens's media with the saved blend")
            if case .changedSinceRender = state.phase {
                Text("The newest media was rendered with an older blend.")
                    .font(CanonType.interface(11))
                    .foregroundStyle(CanonColor.muted)
            }
            Spacer()
        }
    }

    private func draftedWeight(for slot: LensStyleTreatmentSlot) -> Int {
        if let draft = weightDrafts[slot.styleId] {
            return Int(draft)
        }
        return slot.weight
    }
}
