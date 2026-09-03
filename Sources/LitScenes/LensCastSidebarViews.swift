import SwiftUI

/// Identity header above a character/object take group on the sidebar boards: the
/// roster face and name anchor the group, with take tallies. Casting is implicit — a
/// character is in the scene when they have a take in its newest media version — and
/// membership reads from WHERE a card sits (the scene-first sections), so there is no
/// badge and no cast toggle: the whole header, thumbnail included, opens the roster
/// editor (the thumbnail falls back to enlarging the reference when no editor is wired).
struct LensCastGroupHeader: View {
    let group: LensIdentityTakeGroup
    let candidates: [MediaItemRecord]
    /// Opens the roster editor focused on this identity.
    var onOpen: (() -> Void)? = nil
    /// Enlarges the identity's leading reference image — thumbnail fallback when
    /// onOpen is absent.
    var onEnlargeThumbnail: ((MediaItemRecord) -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.displayName)
                        .font(CanonType.interface(12.5, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                        .lineLimit(1)
                    Text(subLine)
                        .font(CanonType.archive(8.5))
                        .kerning(0.4)
                        .foregroundStyle(subLineIsWarning ? CanonColor.rust.opacity(0.9) : CanonColor.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if onOpen != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(CanonColor.muted.opacity(0.7))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpen?() }
        }
        .help(openHelp)
    }

    /// Header thumbnail edge; the "takes live elsewhere" note in the panel indents past it.
    static let thumbnailSide: CGFloat = 52

    @ViewBuilder
    private var thumbnail: some View {
        let leadingItem = group.referenceMediaIds
            .lazy
            .compactMap { mediaId in candidates.first { $0.mediaId == mediaId } }
            .first
        if onOpen != nil || (onEnlargeThumbnail != nil && leadingItem != nil) {
            Button {
                if let onOpen {
                    onOpen()
                } else if let onEnlargeThumbnail, let leadingItem {
                    onEnlargeThumbnail(leadingItem)
                }
            } label: {
                rosterBucketThumbnail(
                    name: group.displayName,
                    referenceMediaIds: group.referenceMediaIds,
                    candidates: candidates,
                    side: Self.thumbnailSide
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(onOpen != nil ? "View and edit \(group.displayName)" : "View \(group.displayName)'s reference larger")
        } else {
            rosterBucketThumbnail(
                name: group.displayName,
                referenceMediaIds: group.referenceMediaIds,
                candidates: candidates,
                side: Self.thumbnailSide
            )
        }
    }

    private var openHelp: String {
        let description = group.descriptionPrompt.isEmpty ? group.displayName : group.descriptionPrompt
        return onOpen == nil ? description : "\(description) — click to view and edit"
    }

    private var subLineIsWarning: Bool {
        group.membership == .cast && group.referenceMediaIds.isEmpty && group.characterId.isEmpty == false
    }

    private var subLine: String {
        if subLineIsWarning {
            return "No reference images — renders from description only"
        }
        var parts: [String] = []
        if !group.referenceMediaIds.isEmpty {
            parts.append("\(group.referenceMediaIds.count) ref\(group.referenceMediaIds.count == 1 ? "" : "s")")
        }
        let ready = group.takes.filter { $0.status == "ready" }.count
        let generating = group.takes.filter { $0.status == "generating" }.count
        let failed = group.takes.filter { $0.status == "failed" || $0.status == "cancelled" }.count
        let planned = group.takes.count - ready - generating - failed
        if ready > 0 { parts.append("\(ready) ready") }
        if generating > 0 { parts.append("\(generating) rendering") }
        if planned > 0 { parts.append("\(planned) planned") }
        if failed > 0 { parts.append("\(failed) failed") }
        if parts.isEmpty { parts.append("No takes in this scene") }
        return parts.joined(separator: " · ")
    }
}

/// Inline create affordance shared by the workbench sidebar and the roster editor:
/// a quiet "+ New character" button that flips into a name field; Return creates.
struct RosterInlineCreateField: View {
    /// e.g. "New character"
    let title: String
    /// e.g. "Character name — Return creates"
    let prompt: String
    var onCreate: (String) -> Void

    @State private var isEditing = false
    @State private var draftName = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        if isEditing {
            TextField(prompt, text: $draftName)
                .textFieldStyle(.roundedBorder)
                .font(CanonType.interface(12.5))
                .focused($isFocused)
                .onSubmit(create)
                .onExitCommand(perform: reset)
        } else {
            Button {
                isEditing = true
                DispatchQueue.main.async { isFocused = true }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text(title)
                        .font(CanonType.interface(12, weight: .semibold))
                }
                .foregroundStyle(CanonColor.brass)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func create() {
        let name = draftName.trimmed
        guard !name.isEmpty else {
            reset()
            return
        }
        onCreate(name)
        reset()
    }

    private func reset() {
        isEditing = false
        draftName = ""
        isFocused = false
    }
}

/// The scene-first Characters/Objects sidebar panel. Two sections: IN THIS SCENE —
/// identities with takes here, each a compact card (identity header + a wrapping strip
/// of small 16:9 take thumbnails) — then the rest of the PROJECT ROSTER as quiet rows.
/// The panel is a browser: cards and rows open the roster editor; planning, adding
/// takes, and batch rendering live elsewhere (only a failed take's retry stays here).
/// Takes that resolve to no identity (legacy, pre-stamping) are not displayed.
struct SceneCharactersPanel: View {
    let lens: ProjectLens
    let versionId: String
    let groups: [LensIdentityTakeGroup]
    /// Full image inventory, for identity thumbnails.
    let candidates: [MediaItemRecord]
    /// Flips the empty-state copy between characters and objects.
    var isObjects: Bool = false
    var hasOpenAICredential: Bool = true
    var hasCivitaiCredential: Bool = false
    var hasFALCredential: Bool = false
    var hasStabilityCredential: Bool = false
    var isRenderBlocked: Bool = false
    var renderBlockerHelp: String? = nil
    var isPaused: Bool = false
    var isAnimatingLensArtifact: Bool = false
    var onOpenImage: (ProjectLensHeroImage) -> Void
    var onOpenIdentity: (LensIdentityTakeGroup) -> Void
    var onSubmitRender: (ProjectLensHeroImage, LensTakeRenderRequest) -> Void
    var onAnimateImage: ((ProjectLensHeroImage) -> Void)? = nil
    var onPreviewStyle: (StyleImagePreviewRequest) -> Void
    var onApplyTakeStyle: ((ProjectLensHeroImage, LensStyleTreatmentSlot, String) -> Void)? = nil
    var onOpenAppSettings: (() -> Void)? = nil

    @State private var renderSetupImage: ProjectLensHeroImage?
    @State private var stylePickerImage: ProjectLensHeroImage?
    @State private var selectedTakeStyleSlot: LensStyleTreatmentSlot?
    @State private var selectedTakeStyleCatalogVersion = ""

    var body: some View {
        let inScene = groups.filter { $0.membership == .cast || (!$0.rosterId.isEmpty && !$0.takes.isEmpty) }
        let roster = groups.filter { !$0.rosterId.isEmpty && $0.membership == .notCast && $0.takes.isEmpty }
        VStack(alignment: .leading, spacing: 14) {
            characterImageryGuidance
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("IN THIS SCENE")
                if inScene.isEmpty {
                    Text(isObjects
                        ? "No objects in this scene yet."
                        : "No one is in this scene yet.")
                        .font(CanonType.interface(10.5))
                        .foregroundStyle(CanonColor.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(inScene) { group in
                    sceneCastCard(group)
                }
            }
            if !roster.isEmpty {
                Rectangle().fill(CanonColor.hairlinePaper.opacity(0.7)).frame(height: 1)
                VStack(alignment: .leading, spacing: 7) {
                    sectionLabel("PROJECT ROSTER")
                    ForEach(roster) { group in
                        rosterRow(group)
                    }
                }
            }
        }
        .popover(item: $renderSetupImage) { image in
            LensTakeRenderSetupPopover(
                image: image,
                mediaPlan: lens.body.resolvedMediaPlan,
                hasOpenAICredential: hasOpenAICredential,
                hasCivitaiCredential: hasCivitaiCredential,
                hasFALCredential: hasFALCredential,
                hasStabilityCredential: hasStabilityCredential,
                isRenderBlocked: isRenderBlocked,
                renderBlockerHelp: renderBlockerHelp,
                isPaused: isPaused,
                isAnimatingLensArtifact: isAnimatingLensArtifact,
                onSubmit: { request in
                    onSubmitRender(image, request)
                },
                onAnimate: onAnimateImage.map { animate in { animate(image) } },
                onEditStyle: onApplyTakeStyle != nil ? { openStylePicker(image) } : nil,
                onOpenAppSettings: onOpenAppSettings,
                onDismiss: { renderSetupImage = nil }
            )
        }
        .sheet(item: $stylePickerImage) { image in
            LensTakeStylePickerModal(
                image: image,
                selectedSlot: $selectedTakeStyleSlot,
                catalogVersion: $selectedTakeStyleCatalogVersion,
                onApply: {
                    guard let slot = selectedTakeStyleSlot else { return }
                    stylePickerImage = nil
                    onApplyTakeStyle?(image, slot, selectedTakeStyleCatalogVersion)
                },
                onCancel: { stylePickerImage = nil },
                onPreviewStyle: onPreviewStyle
            )
        }
    }

    // MARK: - Guidance

    /// The cold-start nudge: every roster character is faceless, so the first
    /// SCENES visit needs a path into imagery, not just monogram rows. One
    /// card (the EmptyReferenceWell idiom), one CTA — it opens the first
    /// character on the roster editor, whose GENERATE pane arrives pre-seeded.
    /// Partial states are carried by the per-row "add imagery" chips instead.
    @ViewBuilder
    private var characterImageryGuidance: some View {
        let characters = groups.filter { !$0.characterId.isEmpty }
        let needing = characters.filter { $0.referenceMediaIds.isEmpty }
        if !isObjects, !characters.isEmpty, needing.count == characters.count {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.rectangle.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(CanonColor.brass)
                    Text("No character imagery yet")
                        .font(CanonType.interface(12, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                }
                Text("Frames anchor each character's likeness on their reference images — without them, faces drift between renders. Open a character and GENERATE composes a reference study from their description.")
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(CanonColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    if let first = needing.first {
                        onOpenIdentity(first)
                    }
                } label: {
                    Label("Generate character imagery", systemImage: "sparkles")
                }
                .buttonStyle(CanonUtilityButtonStyle())
                .help("Open \(needing.first?.displayName ?? "the roster") — the GENERATE pane seeds a reference-study prompt")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(CanonColor.softGold.opacity(0.10)))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(CanonColor.brass.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
        }
    }

    // MARK: - Cards

    private func sceneCastCard(_ group: LensIdentityTakeGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LensCastGroupHeader(
                group: group,
                candidates: candidates,
                onOpen: { onOpenIdentity(group) }
            )
            if group.takes.isEmpty {
                // In the scene (newest version has takes) but the DISPLAYED older
                // version has none — history browsing never fakes takes.
                Text("Takes live in the newest version.")
                    .font(CanonType.interface(10))
                    .foregroundStyle(CanonColor.muted)
                    .padding(.leading, LensCastGroupHeader.thumbnailSide + 8)
            } else {
                takeThumbStrip(group)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 9).fill(CanonColor.paperInset.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(CanonColor.hairlinePaper.opacity(0.8), lineWidth: 1))
    }

    private func rosterRow(_ group: LensIdentityTakeGroup) -> some View {
        HStack(spacing: 8) {
            rosterBucketThumbnail(
                name: group.displayName,
                referenceMediaIds: group.referenceMediaIds,
                candidates: candidates,
                side: 34
            )
            Text(group.displayName)
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.ink.opacity(0.82))
                .lineLimit(1)
            if !group.referenceMediaIds.isEmpty {
                Text("\(group.referenceMediaIds.count) ref\(group.referenceMediaIds.count == 1 ? "" : "s")")
                    .font(CanonType.archive(8.5))
                    .foregroundStyle(CanonColor.muted)
            } else if !group.characterId.isEmpty {
                // Faceless character: the row's monogram is the only signal
                // otherwise, and imagery is one click away in the editor.
                Label("add imagery", systemImage: "sparkles")
                    .font(CanonType.archive(8.5))
                    .foregroundStyle(CanonColor.brass.opacity(0.9))
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(CanonColor.muted.opacity(0.7))
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenIdentity(group) }
        .help(group.descriptionPrompt.isEmpty ? "\(group.displayName) — click to view and edit" : "\(group.descriptionPrompt) — click to view and edit")
    }

    // MARK: - Take thumbnails

    /// Rendered work only — planned takes are managed elsewhere, so the sidebar never
    /// shows their blank placeholder thumbs.
    private func takeThumbStrip(_ group: LensIdentityTakeGroup) -> some View {
        let visibleTakes = group.takes.filter {
            ["ready", "generating", "failed", "cancelled", "canceled"].contains($0.status)
        }
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92, maximum: 118), spacing: 6, alignment: .topLeading)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(visibleTakes) { take in
                takeThumb(take)
            }
        }
    }

    @ViewBuilder
    private func takeThumb(_ image: ProjectLensHeroImage) -> some View {
        switch image.status {
        case "ready":
            // Tap opens, drag sequences into a shot — same gesture pair as the
            // main board's cards (a Button would eat the drag).
            thumbCell {
                if let nsImage = NSImage(contentsOfFile: image.imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    CanonColor.paperInset
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlinePaper))
            .contentShape(Rectangle())
            .onTapGesture { onOpenImage(image) }
            .draggable(ShotFrameTransfer(frameImageId: image.imageId))
            .help(image.label.trimmed.isEmpty ? "Open this take" : "\(image.label) — click to open, drag into a shot")
        case "generating":
            thumbCell {
                ZStack {
                    CanonColor.paperInset.opacity(0.7)
                    ProgressView().controlSize(.mini)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.brass.opacity(0.5)))
            .help("Rendering \(image.label.trimmed.isEmpty ? "this take" : image.label)")
        case "failed", "cancelled", "canceled":
            thumbCell {
                ZStack {
                    CanonColor.rust.opacity(0.08)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CanonColor.rust)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.rust.opacity(0.5)))
            .contentShape(Rectangle())
            .onTapGesture { renderSetupImage = image }
            .help(image.errorMessage.trimmed.isEmpty ? "Rendering failed — choose a stack to retry" : "\(image.errorMessage.trimmed) — choose a stack to retry")
        default:
            // Planned takes are filtered out of the strip; nothing else reaches here.
            EmptyView()
        }
    }

    /// A 16:9 thumbnail cell that fills whatever width the adaptive grid grants.
    private func thumbCell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(content())
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(CanonType.archive(8.5, weight: .semibold))
            .kerning(1.3)
            .foregroundStyle(CanonColor.muted)
    }

    private func openStylePicker(_ image: ProjectLensHeroImage) {
        selectedTakeStyleSlot = lensTakeStyleSlot(for: image, treatment: lens.body.styleTreatment)
        selectedTakeStyleCatalogVersion = lens.body.styleTreatment?.catalogVersion ?? image.sourceRecipeVersion ?? ""
        stylePickerImage = image
    }
}
